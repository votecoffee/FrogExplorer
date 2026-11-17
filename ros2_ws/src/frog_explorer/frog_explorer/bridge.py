"""ROS 2 Lyrical node; renderer and physics remain in Godot."""
import json
import socket
import time
import uuid

import rclpy
from rclpy.node import Node
from rclpy.clock import Clock, ClockType
from rclpy.qos import qos_profile_sensor_data
from rclpy.executors import ExternalShutdownException
from geometry_msgs.msg import PoseStamped, TransformStamped, Twist
from sensor_msgs.msg import Joy
from std_msgs.msg import String, Float32
from rosgraph_msgs.msg import Clock as ClockMessage
from tf2_ros import TransformBroadcaster

from . import protocol


class FrogBridge(Node):
    def __init__(self):
        super().__init__("frog_explorer_bridge")
        self.declare_parameter("game_port", protocol.GAME_PORT)
        self.declare_parameter("bridge_port", protocol.BRIDGE_PORT)
        self.declare_parameter("world_frame", "woodland")
        self.declare_parameter("joy_y_up", False)
        self.session = uuid.uuid4().hex
        self.command_sequence = 0
        self.game_session = ""
        self.game_sequence = -1
        self.last_state = None
        self.last_received = 0.0
        self.bad_packets = 0
        self.buttons = []
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", int(self.get_parameter("bridge_port").value)))
        self.sock.setblocking(False)
        self.destination = ("127.0.0.1", int(self.get_parameter("game_port").value))
        self.pose_pub = self.create_publisher(PoseStamped, "/frog_explorer/pose", 10)
        self.state_pub = self.create_publisher(String, "/frog_explorer/state", 10)
        self.events_pub = self.create_publisher(String, "/frog_explorer/events", 10)
        self.joy_pub = self.create_publisher(Joy, "/frog_explorer/input/joy", qos_profile_sensor_data)
        self.clock_pub = self.create_publisher(ClockMessage, "/clock", 10)
        self.tf = TransformBroadcaster(self)
        self.create_subscription(Twist, "/frog_explorer/cmd_vel", self.on_velocity, 10)
        self.create_subscription(String, "/frog_explorer/action", self.on_action, 10)
        self.create_subscription(String, "/frog_explorer/travel", self.on_travel, 10)
        self.create_subscription(Float32, "/frog_explorer/size", self.on_size, 10)
        self.create_subscription(Joy, "/frog_explorer/cmd/joy", self.on_joy, qos_profile_sensor_data)
        steady = Clock(clock_type=ClockType.STEADY_TIME)
        self.create_timer(.02, self.poll, clock=steady)
        self.create_timer(.25, lambda: self.send({"kind": "heartbeat"}), clock=steady)
        self.get_logger().info("FrogExplorer bridge ready: local UDP %d -> %d" % (self.sock.getsockname()[1], self.destination[1]))

    def send(self, packet):
        packet = dict(packet, v=1, session=self.session, seq=self.command_sequence)
        self.command_sequence += 1
        try:
            self.sock.sendto(protocol.encode(packet), self.destination)
        except (ConnectionResetError, ConnectionRefusedError):
            # The renderer can start after the bridge, or close before it.
            # Windows reports an ICMP "port unreachable" on later UDP calls.
            pass

    def on_velocity(self, message):
        try:
            self.send(protocol.velocity_packet((message.linear.x, message.linear.y, message.linear.z), message.angular.z))
        except ValueError as exc:
            self.get_logger().warning(str(exc))

    def on_action(self, message):
        action = message.data.strip()
        if action in protocol.ACTIONS:
            self.send({"kind": "action", "action": action})
        else:
            self.get_logger().warning("Unknown frog action: " + action[:80])

    def on_travel(self, message):
        try:
            self.send(protocol.travel_packet(message.data))
        except ValueError as exc:
            self.get_logger().warning(str(exc))

    def on_size(self, message):
        try:
            self.send(protocol.size_packet(message.data))
        except ValueError as exc:
            self.get_logger().warning(str(exc))

    def on_joy(self, message):
        try:
            axes = list(message.axes)
            move, aux = protocol.joy_axes(axes, message.buttons, self.get_parameter("joy_y_up").value)
            self.send({"kind": "axes", "move": move, "aux": aux, "size_axis": protocol.joy_size_axis(axes), "triggers": [max(0.,min(1.,x)) for x in axes[4:6]] if len(axes)==6 else [0.,0.], "ttl": .3})
            for index, action in protocol.BUTTON_ACTIONS.items():
                now = index < len(message.buttons) and bool(message.buttons[index])
                before = index < len(self.buttons) and bool(self.buttons[index])
                if now and not before:
                    self.send({"kind": "action", "action": action})
            self.buttons = list(message.buttons)
        except ValueError as exc:
            self.get_logger().warning(str(exc))

    def poll(self):
        for _ in range(64):
            try:
                data, address = self.sock.recvfrom(65536)
            except BlockingIOError:
                break
            except (ConnectionResetError, ConnectionRefusedError):
                continue
            if address[0] != "127.0.0.1":
                continue
            try:
                if len(data) <= 32768:
                    header = json.loads(data.decode("utf-8"))
                    if isinstance(header, dict) and header.get("v") == 1 and header.get("kind") == "goodbye" and (not self.game_session or header.get("session") == self.game_session):
                        self.get_logger().info("Game closed; stopping bridge")
                        rclpy.try_shutdown()
                        return
                state = protocol.decode_state(data)
                if state["session"] == self.game_session and state["seq"] <= self.game_sequence:
                    continue
                self.publish_state(state)
                self.game_session = state["session"]
                self.game_sequence = state["seq"]
                self.last_state = state
                self.last_received = time.monotonic()
            except (ValueError, TypeError, KeyError, UnicodeError, json.JSONDecodeError):
                self.bad_packets += 1

    def publish_state(self, state):
        position, orientation = protocol.pose(state)
        stamp = PoseStamped()
        nanoseconds = int(float(state["time"]) * 1e9)
        stamp.header.stamp.sec, stamp.header.stamp.nanosec = divmod(nanoseconds, 1_000_000_000)
        stamp.header.frame_id = str(self.get_parameter("world_frame").value)
        stamp.pose.position.x, stamp.pose.position.y, stamp.pose.position.z = position
        stamp.pose.orientation.x, stamp.pose.orientation.y, stamp.pose.orientation.z, stamp.pose.orientation.w = orientation
        self.pose_pub.publish(stamp)
        transform = TransformStamped()
        transform.header = stamp.header
        transform.child_frame_id = "frog_base"
        transform.transform.translation.x, transform.transform.translation.y, transform.transform.translation.z = position
        transform.transform.rotation = stamp.pose.orientation
        self.tf.sendTransform(transform)
        clock = ClockMessage()
        clock.clock = stamp.header.stamp
        self.clock_pub.publish(clock)
        summary = {k: state.get(k) for k in ("session", "seq", "time", "species", "mode", "camera", "animation", "flies_caught", "depth", "fps", "place_id", "place_name", "map_epoch", "geographic_anchor", "travel_state", "travel_progress", "scale", "scale_limits", "body_height_m", "collision_radius_m", "walk_speed_mps", "swim_speed_mps", "climb_speed_mps", "resize_blocked", "trigger_mode", "ride", "ride_speed_mps", "ride_altitude_m", "ride_landing", "parachute_active", "coasting", "players", "player_count", "local_player_count", "multiplayer_mode", "primary_player_id")}
        self.state_pub.publish(String(data=json.dumps(summary)))
        joy = Joy()
        joy.header = stamp.header
        joy.header.frame_id = "gamepad_sdl_y_down"
        joy.axes = list(protocol.input_axes(state.get("axes", [0., 0., 0., 0.])))
        joy.buttons = [int(x) for x in state.get("buttons", [])[:32]]
        self.joy_pub.publish(joy)
        for event in state.get("events", [])[:32]:
            self.events_pub.publish(String(data=json.dumps(event)))

    def destroy_node(self):
        self.sock.close()
        return super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = None
    try:
        node = FrogBridge()
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        if node is not None:
            node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
