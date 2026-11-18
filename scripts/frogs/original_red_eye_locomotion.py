"""Authored foot paths and parent-aware limb IK for the original frog. MIT.

No motion capture or external animation data is read. The body is in place;
Godot supplies travel and the jump trajectory.
"""
from math import sin, cos, pi, sqrt

from mathutils import Vector, Quaternion, Euler


def smooth(a, b, t):
    value = max(0, min(1, (t-a)/(b-a)))
    return value*value*(3-2*value)


def rotate(frog, name, delta):
    rest = frog.rest[name]
    frog.arm.pose.bones[name].rotation_quaternion = rest.inverted()@delta@rest


def body(frog, angles=(0, 0, 0), offset=(0, 0, 0)):
    rotation = Euler(angles, 'XYZ').to_quaternion();offset = Vector(offset)
    spine = frog.arm.pose.bones['DEF-spine.003'];spine.scale = (1, 1, 1)
    rotate(frog, spine.name, rotation)
    spine.location = frog.rest[spine.name].inverted()@offset
    return rotation, offset


def place(frog, side, kind, palm, torso, distal=None, tarsus=None, pole_blend=1):
    """Place a palm using an outward knee/elbow pole and world foot attitude."""
    points, names = frog.limbs[(side, kind)];sign = -1 if side=='L' else 1
    distal = Quaternion() if distal is None else distal
    tarsus = Quaternion() if tarsus is None else tarsus
    parent, offset = torso;pivot = frog.bones['DEF-spine.003'][0]
    root = pivot+parent@(points[0]-pivot)+offset
    target = Vector(palm)-distal@(points[-1]-points[-2])
    if kind=='leg':target -= tarsus@(points[3]-points[2])
    length1 = (points[1]-points[0]).length;length2 = (points[2]-points[1]).length
    axis = target-root;distance = axis.length;axis.normalize()
    reach = min(length1+length2-.00005, max(abs(length1-length2)+.00005, distance))
    error = abs(distance-reach)
    frog.ik_residuals.append(error)
    target = root+axis*reach
    pole = Vector((sign*.85, .65 if kind=='arm' else -.65, -.85 if kind=='arm' else -.12))
    if pole_blend<1:
        rest_pole = parent@(points[1]-(points[0]+points[2])*.5)
        pole = rest_pole.normalized().lerp(pole.normalized(),pole_blend)
    pole -= axis*pole.dot(axis);pole.normalize()
    along = (length1*length1-length2*length2+reach*reach)/(2*reach)
    joint = root+axis*along+pole*sqrt(max(0, length1*length1-along*along))
    upper = (points[1]-points[0]).rotation_difference(joint-root)
    lower = (points[2]-points[1]).rotation_difference(target-joint)
    rotate(frog, names[0], parent.inverted()@upper)
    rotate(frog, names[1], upper.inverted()@lower)
    if kind=='leg':
        rotate(frog, names[2], lower.inverted()@tarsus)
        rotate(frog, names[3], tarsus.inverted()@distal)
    else:rotate(frog, names[2], lower.inverted()@distal)


def walk(frog, t):
    torso = body(frog, (0, .008*sin(2*pi*t), .010*sin(2*pi*t)),
                 (0, 0, .0010*sin(2*pi*t)**2))
    for side in ['L', 'R']:
        phase = 2*pi*t+(0 if side=='L' else pi)
        for kind, label, extra in [('arm','hand',0),('leg','foot',pi)]:
            p = phase+extra;swing = max(0, sin(p))
            palm = frog.limbs[(side, kind)][0][-1].copy()
            cycle = (p/(2*pi))%1
            if cycle<.5:
                w = cycle*2;travel = 1+2*w-12*w*w+8*w*w*w
            else:travel = -1+4*(cycle-.5)
            # Constant rearward speed while planted matches Godot travel;
            # the swing has matching endpoint velocity and a soft toe lift.
            palm.y += .024*travel+(.018 if kind=='leg' else 0)
            palm.z += .009*swing*swing
            place(frog, side, kind, palm, torso)
            for _,names in frog.digits[(side,label)]:rotate(frog,names[-1],Quaternion((1,0,0), .16*swing))


def kick(frog, side, extension, torso, recovery=0, settle=1):
    sign = -1 if side=='L' else 1
    # Folded ankle/foot orientations progress together; the palm remains
    # behind the torso rather than sweeping forward across the face.
    distal = Quaternion((0,0,1), sign*pi*extension)
    tarsus = Quaternion((0,0,1), sign*pi*extension)
    base_y = .027 if settle==1 else .009+.018*settle
    palm = (sign*(.052+.018*sin(pi*extension)+.006*recovery),
            base_y+.180*extension, .005+.009*extension+.008*recovery)
    place(frog, side, 'leg', palm, torso, distal, tarsus, settle)


def jump(frog, t):
    crouch = smooth(0,.12,t)*(1-smooth(.12,.24,t))
    extension = smooth(.12,.40,t)*(1-smooth(.62,.94,t))
    torso = body(frog, (.035*crouch-.025*extension,0,0), (0,0,-.003*crouch))
    for side in ['L','R']:
        sign = -1 if side=='L' else 1
        kick(frog,side,extension,torso)
        palm = frog.limbs[(side,'arm')][0][-1].copy()
        palm.y += .025*extension;palm.z += .022*extension
        palm.x += sign*.002*extension
        place(frog,side,'arm',palm,torso)


def swim(frog, t):
    # Quick paired power stroke, brief glide, then slower recovery.
    extension = smooth(0,.32,t)*(1-smooth(.48,1,t))
    recovery = sin(pi*smooth(.48,1,t))**2
    torso = body(frog, (.012*sin(2*pi*t),0,0))
    for side in ['L','R']:
        sign = -1 if side=='L' else 1
        kick(frog,side,extension,torso,recovery)
        # Small steering sweep; forefeet stay lateral and below the mouth.
        palm = (sign*(.061+.007*recovery),-.045+.006*extension,.018)
        place(frog,side,'arm',palm,torso)


def hop(frog, t):
    settle = smooth(0,.10,t)*(1-smooth(.88,1,t))
    crouch = smooth(0,.10,t)*(1-smooth(.10,.22,t))
    extension = .65*smooth(.12,.38,t)*(1-smooth(.55,.92,t))
    torso = body(frog,(.028*crouch-.018*extension,0,0),(0,0,-.002*crouch))
    for side in ['L','R']:
        sign = -1 if side=='L' else 1
        kick(frog,side,extension,torso,settle=settle)
        palm = frog.limbs[(side,'arm')][0][-1].copy()
        palm += Vector((sign*.002*extension,.018*extension,.015*extension))
        place(frog,side,'arm',palm,torso,pole_blend=settle)


def water_entry(frog, t):
    settle = smooth(0,.10,t)
    extension = .75*smooth(.08,.36,t)*(1-smooth(.50,.84,t))
    dive = sin(pi*smooth(.16,.96,t))**2
    approach = smooth(.42,.92,t)
    torso = body(frog,(.12*dive,0,0))
    for side in ['L','R']:
        sign = -1 if side=='L' else 1
        kick(frog,side,extension,torso,settle=settle)
        palm = frog.limbs[(side,'arm')][0][-1].lerp(Vector((sign*.061,-.045,.018)),approach)
        palm.z += .014*extension*(1-approach)
        place(frog,side,'arm',palm,torso,pole_blend=settle)


def shore_exit(frog, t):
    settle = 1-smooth(.86,1,t)
    extension = .80*smooth(.04,.33,t)*(1-smooth(.45,.83,t))
    reach = sin(pi*smooth(.08,.65,t))**2
    plant = smooth(.04,.65,t)
    absorb = sin(pi*smooth(.62,.92,t))**2
    torso = body(frog,(-.045*sin(pi*smooth(0,.75,t))**2,0,0),(0,0,-.002*absorb))
    for side in ['L','R']:
        sign = -1 if side=='L' else 1
        kick(frog,side,extension,torso,settle=settle)
        palm = Vector((sign*.061,-.045,.018)).lerp(frog.limbs[(side,'arm')][0][-1],plant)
        palm.z += .018*reach
        place(frog,side,'arm',palm,torso,pole_blend=settle)
