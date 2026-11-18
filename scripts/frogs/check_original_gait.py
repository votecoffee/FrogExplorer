"""Measure evaluated toe-pad geometry against the authored support plane.

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
    result = {};issues = []
    for clip in ['Slow_Walk', 'Climb']:
        action = bpy.data.actions[clip];arm.animation_data.action = action
        arm.animation_data.action_slot = action.slots[0]
        minimum = float('inf');maximum = -float('inf')
        for sample in range(48):
            frame = float(action.frame_range[1])*sample/48
            bpy.context.scene.frame_set(floor(frame), subframe=frame-floor(frame))
            depsgraph = bpy.context.evaluated_depsgraph_get()
            for pad in pads:
                obj = pad.evaluated_get(depsgraph);mesh = obj.to_mesh()
                points = np.empty(len(mesh.vertices)*3, dtype=np.float32)
                mesh.vertices.foreach_get('co', points);points = points.reshape(-1, 3)
                matrix = np.asarray(obj.matrix_world)
                height = points @ matrix[2, :3]+matrix[2, 3]
                minimum = min(minimum, float(height.min()));maximum = max(maximum, float(height.max()))
                obj.to_mesh_clear()
        result[clip] = {'minimum_pad_height_m':minimum, 'maximum_pad_height_m':maximum,
                        'sampled_poses':48, 'pads_per_pose':len(pads)}
        if minimum < -.00045:issues.append(clip+' penetrates the support plane')
    report = {'clips':result, 'issues':issues,
              'scope':'Evaluated Blender skin geometry, authored metre scale. 0.45 mm penetration tolerance; no world collision or GPU performance test.'}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print('ORIGINAL_GAIT_CHECK '+json.dumps(report), flush=True)
    assert not issues, issues


if __name__ == '__main__':main()
