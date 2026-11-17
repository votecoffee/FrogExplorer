"""Versioned local UDP protocol and Godot-to-ROS frame conversion."""
import json
import math
import re

VERSION = 1
GAME_PORT = 17777
BRIDGE_PORT = 17776
ACTIONS = frozenset(("jump", "catch_fly", "croak", "silly", "next_frog", "next_camera", "reset", "travel_random", "travel_home", "travel_cancel", "travel_menu", "reset_size", "toggle_trigger_mode", "ride_balloon", "ride_car", "ride_exit"))
BUTTON_ACTIONS = {0: "croak", 1: "silly", 2: "jump", 3: "catch_fly", 4: "travel_random", 7: "toggle_trigger_mode", 8: "travel_menu", 9: "next_frog", 10: "next_camera"}


def finite_vector(value, length):
    if not isinstance(value, (list, tuple)) or len(value) != length:
        raise ValueError("Wrong vector length")
    result = tuple(float(x) for x in value)
    if not all(math.isfinite(x) and abs(x) < 1e6 for x in result):
        raise ValueError("Invalid numeric value")
    return result


def _reject_constant(value):
    raise ValueError("Non-JSON numeric constant: " + value)


def decode_state(data):
    if len(data) > 32768:
        raise ValueError("Oversized game packet")
    state = json.loads(data.decode("utf-8"), parse_constant=_reject_constant)
    if not isinstance(state, dict) or state.get("v") != VERSION or state.get("kind") != "state":
        raise ValueError("Unsupported game packet")
    if not isinstance(state.get("session"), str) or not 1 <= len(state["session"]) <= 128:
        raise ValueError("Missing game session")
    if type(state.get("seq")) is not int or state["seq"] < 0:
        raise ValueError("Invalid sequence")
    for field in ("position", "forward", "up"):
        finite_vector(state.get(field), 3)
    if not math.isfinite(float(state.get("time", -1))) or float(state["time"]) < 0:
        raise ValueError("Invalid game time")
    return state


def encode(packet):
    return json.dumps(packet, separators=(",", ":"), allow_nan=False).encode("utf-8")


def godot_to_ros(vector):
    """World: ROS x=-Godot z, ROS y=-Godot x, ROS z=Godot y."""
    x, y, z = finite_vector(vector, 3)
    return (-z, -x, y)


def _unit(v):
    length = math.sqrt(sum(x * x for x in v))
    if length < 1e-8:
        raise ValueError("Zero orientation axis")
    return tuple(x / length for x in v)


def _cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def pose(state):
    position = godot_to_ros(state["position"])
    forward = _unit(godot_to_ros(state["forward"]))
    left = _unit(_cross(_unit(godot_to_ros(state["up"])), forward))
    up = _cross(forward, left)
    m = [[forward[i], left[i], up[i]] for i in range(3)]
    trace = m[0][0] + m[1][1] + m[2][2]
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        q = ((m[2][1]-m[1][2])/s, (m[0][2]-m[2][0])/s, (m[1][0]-m[0][1])/s, .25*s)
    else:
        i = max(range(3), key=lambda k: m[k][k])
        j, k = (i+1) % 3, (i+2) % 3
        s = math.sqrt(max(0.0, 1+m[i][i]-m[j][j]-m[k][k])) * 2
        result = [0., 0., 0., 0.]
        result[i] = .25*s
        result[j] = (m[j][i]+m[i][j])/s
        result[k] = (m[k][i]+m[i][k])/s
        result[3] = (m[k][j]-m[j][k])/s
        q = tuple(result)
    return position, _unit(q)


def velocity_packet(linear, angular_z):
    forward, left, vertical = finite_vector(linear, 3)
    yaw = finite_vector((angular_z,), 1)[0]
    return {"kind": "velocity", "forward": max(-1.5, min(1.5, forward)),
            "strafe": max(-1.5, min(1.5, -left)),
            "vertical": max(-.7, min(.7, vertical)),
            "yaw": max(-3., min(3., yaw)), "ttl": .3}


def joy_axes(axes, buttons, y_up=False):
    x, y, rx, ry = finite_vector(axes[:4], 4)
    if y_up:
        y, ry = -y, -ry
    def pressed(index):
        return int(index < len(buttons) and bool(buttons[index]))
    x += pressed(14) - pressed(13)
    y += pressed(12) - pressed(11)
    return [max(-1., min(1., x)), max(-1., min(1., y))], [rx, ry]


def travel_packet(request):
    """Named installed place, or random/home/cancel; no paths or URLs."""
    if not isinstance(request, str):
        raise ValueError("Travel request must be a place ID")
    request = request.strip()
    if request in ("random", "home", "cancel"):
        return {"kind": "action", "action": "travel_" + request}
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,79}", request):
        raise ValueError("Use an installed place ID, random, home or cancel")
    return {"kind": "travel", "place_id": request}


def size_packet(factor):
    if isinstance(factor, bool):
        raise ValueError("Size must be a numeric multiplier")
    value = float(factor)
    if not math.isfinite(value) or not .25 <= value <= 16:
        raise ValueError("Size must be between 0.25 and 16")
    return {"kind": "size", "factor": value}


def input_axes(axes):
    """Legacy four-stick axes, or six with LT/RT in [0,1]."""
    if not isinstance(axes, (list, tuple)) or len(axes) not in (4, 6):
        raise ValueError("Expected four stick axes, optionally followed by LT/RT")
    return finite_vector(axes, len(axes))


def joy_size_axis(axes):
    values = input_axes(axes)
    if len(values) == 4:
        return 0.
    def trigger(value):
        return max(0., min(1., (value-.05)/.95))
    return trigger(values[4]) - trigger(values[5])
