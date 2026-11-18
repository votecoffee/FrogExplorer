"""Original in-place movement and expressive motion keys for the authored frog.

No animation files are imported. Clip names implement FrogExplorer's existing
28-clip interface; motion curves below are authored analytically. MIT.
"""
from math import sin, cos, pi, sqrt, acos

import bpy
from mathutils import Vector, Euler, Quaternion
from original_red_eye_geometry import eye_frame
import original_red_eye_locomotion as locomotion

CLIPS = ['Big_Jump', 'Breakdance', 'Catch_Fly', 'Catch_Fly_Swallow', 'Climb',
         'Croak', 'Death', 'Disco_Frog', 'Face_Wipe', 'Foot_Wave', 'Hit', 'Hop',
         'Idle', 'Land', 'Living_Idle', 'Puff_Up', 'Shore_Exit', 'Slow_Walk',
         'Splat', 'Swallow', 'Swamp_Shuffle', 'Swim', 'Toe_Tap', 'Tongue_Snap',
         'Turn_Left', 'Turn_Right', 'Victory_Ribbit', 'Water_Entry']
LOOPING = ['Climb', 'Disco_Frog', 'Idle', 'Living_Idle', 'Slow_Walk',
           'Swamp_Shuffle', 'Swim', 'Toe_Tap']


def pulse(t, start, end):
    return sin(pi*max(0, min(1, (t-start)/(end-start))))**2


def global_rotation(frog, name, rotation):
    """Rotate about authored world-rest axes, regardless of edit-bone roll."""
    if not isinstance(rotation, Quaternion):rotation = Euler(rotation, 'XYZ').to_quaternion()
    rest = frog.rest[name]
    frog.arm.pose.bones[name].rotation_quaternion = rest.inverted() @ rotation @ rest


def two_joint(frog, side, target, kind='arm'):
    """Solve a hand/ankle and retain the distal palm's resting orientation."""
    points, names = frog.limbs[(side, kind)]
    a, b, c = points[:3]
    target = Vector(target)
    length1, length2 = (b-a).length, (c-b).length
    axis = target-a;distance = min(axis.length, length1+length2-.00001)
    axis.normalize();target = a+axis*distance
    pole = b-(a+c)*.5;pole -= axis*pole.dot(axis);pole.normalize()
    reach = (length1*length1-length2*length2+distance*distance)/(2*distance)
    elbow = a+axis*reach+pole*sqrt(max(0, length1*length1-reach*reach))
    upper = (b-a).rotation_difference(elbow-a)
    lower = (c-b).rotation_difference(target-elbow)
    global_rotation(frog, names[0], upper)
    global_rotation(frog, names[1], upper.inverted() @ lower)
    global_rotation(frog, names[2], lower.inverted())


def animate(frog):
    scene = bpy.context.scene;scene.render.fps = 30
    frog.arm.animation_data_create()
    frog.ik_residuals = []
    for bone in frog.arm.pose.bones:bone.rotation_mode = 'QUATERNION'
    for clip in CLIPS:
        duration = 4.0 if clip in ['Idle', 'Living_Idle'] else 2.0 if clip in LOOPING else 1.6
        # Match the game's 1.4x climbing / 1.2x swimming playback rates.
        if clip == 'Climb':duration = 16/30
        if clip == 'Swim':duration = 1.2
        if clip == 'Slow_Walk':duration = 40/30
        if clip in ['Catch_Fly_Swallow', 'Face_Wipe', 'Victory_Ribbit', 'Breakdance']:duration = 2.4
        action = bpy.data.actions.new(clip);frog.arm.animation_data.action = action
        count = round(duration*30)
        for frame in range(0, count+1, 1 if clip in ['Climb','Slow_Walk','Big_Jump','Swim'] else 2):
            t = frame/count;wave = sin(2*pi*t);bend = sin(pi*t)**2
            for bone in frog.arm.pose.bones:
                bone.rotation_quaternion = Quaternion();bone.location = Vector((0, 0, 0));bone.scale = (1, 1, 1)
            spine = frog.arm.pose.bones['DEF-spine.003']
            spine.scale = (1+.005*wave, 1+.004*wave, 1+.012*wave)
            global_rotation(frog, 'Head', (.008*wave, 0, .012*wave))
            jaw = 0.0;throat = 1.0;blink = pulse(t, .75, .83)
            if clip == 'Slow_Walk':locomotion.walk(frog,t)
            if clip in ['Climb', 'Turn_Left', 'Turn_Right', 'Swamp_Shuffle']:
                # 0.072 m hand travel * 2.8 model scale per stance second
                # matches FrogPilot's 0.20 m/s nominal walking animation rate.
                stride = .036 if clip != 'Climb' else .022
                # Keep the support plane level. Roll/pitch and breathing scale
                # would move planted pads below the ground after solving IK.
                spine.scale = (1, 1, 1)
                global_rotation(frog, 'DEF-spine.003', (0, 0, .018*wave))
                for side, sign in [('L', -1), ('R', 1)]:
                    phase = t*2*pi+(0 if side == 'L' else pi)
                    swing = max(0, sin(phase));step = cos(phase)*stride
                    points, _ = frog.limbs[(side, 'arm')]
                    target = points[2]+Vector((0, step, .009*swing))
                    if clip == 'Swamp_Shuffle':target.x += sign*.009*wave
                    two_joint(frog, side, target)
                    hind_phase = phase+pi
                    leg, _ = frog.limbs[(side, 'leg')]
                    two_joint(frog, side, leg[2]+Vector((0, cos(hind_phase)*stride,
                              .009*max(0, sin(hind_phase)))), 'leg')
                    for label in ['hand', 'foot']:
                        curl = swing if label == 'hand' else max(0, sin(hind_phase))
                        for _, names in frog.digits[(side, label)]:global_rotation(frog, names[-1], (.25*curl, 0, 0))
                if clip.startswith('Turn_'):
                    global_rotation(frog, 'DEF-spine.003', (0, 0, (.18 if clip == 'Turn_Left' else -.18)*bend))
            if clip == 'Big_Jump':locomotion.jump(frog,t)
            if clip in ['Hop', 'Shore_Exit', 'Water_Entry']:
                crouch = pulse(t, 0, .36);extend = pulse(t, .24, .80)
                amount = .6 if clip == 'Hop' else 1.0
                global_rotation(frog, 'DEF-spine.003', ((-.18*crouch+.13*extend)*amount, 0, 0))
                spine.location = frog.rest['DEF-spine.003'].inverted() @ Vector((0, 0, (-.005*crouch+.006*extend)*amount))
                for side in ['L', 'R']:
                    global_rotation(frog, 'DEF-thigh.'+side, ((.4*crouch-.80*extend)*amount, 0, 0))
                    global_rotation(frog, 'DEF-shin.'+side, ((-.4*crouch+1.35*extend)*amount, 0, 0))
                    global_rotation(frog, 'DEF-tarsus.'+side, (-.5*extend*amount, 0, 0))
                    global_rotation(frog, 'DEF-upper_arm.'+side, (-.45*extend*amount, 0, 0))
                    global_rotation(frog, 'DEF-forearm.'+side, (.55*extend*amount, 0, 0))
                if clip == 'Water_Entry':global_rotation(frog, 'DEF-spine.003', (.25*bend, 0, 0))
            if clip == 'Swim':
                locomotion.swim(frog,t)
            if clip in ['Catch_Fly', 'Catch_Fly_Swallow', 'Tongue_Snap']:
                jaw = .60*pulse(t, .08, .62)
                global_rotation(frog, 'Head', (-.06*pulse(t, .08, .62), 0, 0))
                global_rotation(frog, 'Tongue', (-2.4*pulse(t, .19, .46), 0, 0))
                global_rotation(frog, 'TongueTip', (-.2*pulse(t, .19, .46), 0, 0))
                if clip == 'Catch_Fly_Swallow':throat += .65*pulse(t, .55, .94)
            if clip in ['Swallow', 'Croak', 'Victory_Ribbit']:
                croak = pulse(t, .06, .85)
                if clip == 'Victory_Ribbit':croak = sin(t*pi*3)**2*bend
                jaw = (.08 if clip == 'Swallow' else .28)*croak
                throat += (1.0 if clip != 'Swallow' else .55)*croak
            if clip == 'Puff_Up':
                spine.scale = (1+.18*bend, 1+.06*bend, 1+.18*bend);throat += .55*bend
            if clip == 'Face_Wipe':
                points, _ = frog.limbs[('L', 'arm')]
                wipe = pulse(t, .08, .90)
                target = points[2].lerp(Vector((-.031+.010*wave, -.067, .085)), wipe)
                two_joint(frog, 'L', target);blink = wipe
                for _, names in frog.digits[('L', 'hand')]:global_rotation(frog, names[-1], (.5*wipe, 0, 0))
            if clip in ['Toe_Tap', 'Foot_Wave']:
                tap = max(0, sin(t*pi*(4 if clip == 'Toe_Tap' else 3)))*bend
                for _, names in frog.digits[('R', 'hand')]:global_rotation(frog, names[-1], (-.50*tap, 0, 0))
                if clip == 'Foot_Wave':
                    points, _ = frog.limbs[('R', 'arm')]
                    two_joint(frog, 'R', points[2]+Vector((.006*bend, 0, .035*bend)))
                    global_rotation(frog, 'DEF-hand.R', (0, -.45*wave*bend, 0))
            if clip in ['Disco_Frog', 'Victory_Ribbit', 'Breakdance']:
                for side, sign in [('L', -1), ('R', 1)]:
                    points, _ = frog.limbs[(side, 'arm')]
                    lift = max(0, sin(2*pi*t+sign*pi/2))*.035*bend
                    two_joint(frog, side, points[2]+Vector((sign*.007*bend, -.012*bend, lift)))
                global_rotation(frog, 'DEF-spine.003', (.1*wave*bend, .12*wave*bend, .18*wave*bend))
                if clip == 'Breakdance':
                    global_rotation(frog, 'DEF-spine.003', (.65*bend, .30*bend, 2*pi*t))
                    spine.location = frog.rest['DEF-spine.003'].inverted() @ Vector((0, 0, .025*bend))
            if clip in ['Land', 'Hit', 'Splat', 'Death']:
                hit = bend if clip != 'Death' else min(1, t*2.2)
                if clip == 'Death':global_rotation(frog, 'DEF-spine.003', (0, 1.35*hit, 0))
                else:
                    spine.scale = (1+.12*hit, 1+.06*hit, 1-(.35 if clip == 'Splat' else .10)*hit)
                    global_rotation(frog, 'Head', (.15*hit, 0, .07*wave))
                blink = hit
            global_rotation(frog, 'FX-jaw', (jaw, 0, 0))
            frog.arm.pose.bones['Throat'].scale = (1+.20*(throat-1), 1+.13*(throat-1), throat)
            for side, sign in [('L', -1), ('R', 1)]:
                n, _, _ = eye_frame(sign)
                axis = Vector((0, 0, 1)).cross(n).normalized()
                resting_lid = (Vector((0, 0, 1))*.55-n*.90).normalized()
                global_rotation(frog, 'Lid.'+side, Quaternion(axis, acos(resting_lid.dot(n))*blink))
            for bone in frog.arm.pose.bones:
                if bone.name == 'root':continue
                bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
                if bone.name in ['DEF-spine.003', 'Throat']:
                    bone.keyframe_insert('scale', frame=frame, group=bone.name)
                if bone.name == 'DEF-spine.003':bone.keyframe_insert('location', frame=frame, group=bone.name)
        action.use_fake_user = True;action['authoring'] = 'Original analytic motion keys; no imported animation'
        action['loop'] = clip in LOOPING
    frog.arm.animation_data.action = bpy.data.actions['Living_Idle']
    scene.frame_start = 0;scene.frame_end = 120;scene.frame_set(0)
