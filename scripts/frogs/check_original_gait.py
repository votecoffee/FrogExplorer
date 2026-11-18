"""Measure evaluated pads and surrounding skin against the support plane.

Run in Blender with --input ORIGINAL.blend --report REPORT.json.
This checks the skinned surfaces between keys, rather than joint positions.
"""
import argparse
import json
from math import floor
from pathlib import Path
import sys

import bpy
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    report_path = args.report.resolve()
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    arm = bpy.data.objects['Original_Red_Eye_Rig']
    pads = [o for o in bpy.data.objects if o.type=='MESH' and 'adhesive disc' in o.name]
    assert len(pads)==18
    contact = [o for o in bpy.data.objects if o.type=='MESH' and
               any(token in o.name for token in ['adhesive disc','digit','palm','webbing','Continuous '])]
    assert len(contact)==48, 'The full limb/contact mesh set must be checked'
    result = {};issues = []
    for clip in ['Slow_Walk', 'Climb']:
        action = bpy.data.actions[clip];arm.animation_data.action = action
        arm.animation_data.action_slot = action.slots[0]
        minimum = float('inf');maximum = -float('inf');stance_gap = -float('inf')
        skin_minimum = {o.name:float('inf') for o in contact}
        previous = {};stance_speed = []
        for sample in range(48):
            frame = float(action.frame_range[1])*sample/48
            bpy.context.scene.frame_set(floor(frame), subframe=frame-floor(frame))
            depsgraph = bpy.context.evaluated_depsgraph_get()
            for part in contact:
                obj = part.evaluated_get(depsgraph);mesh = obj.to_mesh()
                points = np.empty(len(mesh.vertices)*3, dtype=np.float32)
                mesh.vertices.foreach_get('co', points);points = points.reshape(-1, 3)
                matrix = np.asarray(obj.matrix_world)
                height = points @ matrix[2, :3]+matrix[2, 3]
                lowest = float(height.min());skin_minimum[part.name] = min(skin_minimum[part.name], lowest)
                if 'adhesive disc' in part.name:
                    minimum = min(minimum, lowest);maximum = max(maximum, float(height.max()))
                    phase = sample/48*2*np.pi+(0 if part.name.endswith('L') else np.pi)
                    if part.name.startswith('foot'):phase += np.pi
                    planted = np.sin(phase)<-.20
                    if planted:stance_gap = max(stance_gap, lowest)
                    y = float((points@matrix[1,:3]+matrix[1,3]).mean())
                    if clip=='Slow_Walk' and planted and previous.get(part.name,(0,False))[1]:
                        dt = float(action.frame_range[1])/bpy.context.scene.render.fps/48
                        stance_speed.append((y-previous[part.name][0])/dt)
                    previous[part.name] = (y,planted)
                obj.to_mesh_clear()
        result[clip] = {'minimum_pad_height_m':minimum, 'maximum_pad_height_m':maximum,
                        'sampled_poses':48, 'pads_per_pose':len(pads),
                        'maximum_stance_pad_gap_m':stance_gap,
                        'minimum_contact_skin_height_m':min(skin_minimum.values()),
                        'contact_meshes':len(contact), 'contact_mesh_minima':skin_minimum}
        if minimum < -.00045:issues.append(clip+' penetrates the support plane')
        if stance_gap > .0009:issues.append(clip+' leaves planted pads above the support plane')
        if min(skin_minimum.values()) < -.00045:issues.append(clip+' surrounding limb/digit skin penetrates the support plane')
        if clip=='Slow_Walk':
            assert stance_speed
            error = max(abs(speed-.072) for speed in stance_speed)
            result[clip].update({'expected_stance_speed_m_s':.072, 'maximum_stance_speed_error_m_s':error})
            if error>.007:issues.append(clip+' planted pads slide relative to the calibrated travel speed')
    report = {'clips':result, 'issues':issues,
              'scope':'Evaluated Blender pad, digit, web, palm and limb skin, authored metre scale. 0.45 mm penetration tolerance, 0.9 mm maximum stance-pad gap and 0.007 m/s maximum walking stance-speed error against 0.072 m/s calibration; no world collision or GPU performance test.'}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print('ORIGINAL_GAIT_CHECK '+json.dumps(report), flush=True)
    assert not issues, issues


if __name__ == '__main__':main()
