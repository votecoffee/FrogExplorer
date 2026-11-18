"""Check the skinned limb roots remain covered by the torso through all clips.

Run in Blender with --input ORIGINAL.blend --report REPORT.json. This checks
the closed proximal rims against the evaluated trunk, not just bone positions.
"""
import argparse
import json
from math import floor
from pathlib import Path
import sys

import bpy
from mathutils.bvhtree import BVHTree


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    arm = bpy.data.objects['Original_Red_Eye_Rig']
    trunk = bpy.data.objects['Original continuous trunk and muzzle']
    limbs = [o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Continuous ')]
    assert len(limbs)==4
    roots = {}
    for obj in limbs:
        uv = obj.data.uv_layers.active.data
        roots[obj.name] = sorted({loop.vertex_index for loop in obj.data.loops if abs(uv[loop.index].uv.x)<1e-7})
        assert len(roots[obj.name])==24, obj.name
    clips = {};issues = []
    for action in sorted(bpy.data.actions, key=lambda a:a.name):
        arm.animation_data.action = action;arm.animation_data.action_slot = action.slots[0]
        worst = {o.name:{'maximum_exposure_m':-float('inf'), 'frame':0} for o in limbs}
        for sample in range(9):
            frame = action.frame_range[0]+(action.frame_range[1]-action.frame_range[0])*sample/8
            bpy.context.scene.frame_set(floor(frame), subframe=frame-floor(frame))
            depsgraph = bpy.context.evaluated_depsgraph_get()
            body = trunk.evaluated_get(depsgraph);mesh = body.to_mesh()
            tree = BVHTree.FromPolygons([body.matrix_world@v.co for v in mesh.vertices],
                                        [tuple(p.vertices) for p in mesh.polygons])
            body.to_mesh_clear()
            for part in limbs:
                obj = part.evaluated_get(depsgraph);mesh = obj.to_mesh()
                for index in roots[part.name]:
                    point = obj.matrix_world@mesh.vertices[index].co
                    nearest, normal, _, _ = tree.find_nearest(point)
                    exposure = (point-nearest).dot(normal)
                    if exposure>worst[part.name]['maximum_exposure_m']:
                        worst[part.name] = {'maximum_exposure_m':exposure, 'frame':float(frame)}
                obj.to_mesh_clear()
        clips[action.name] = {'sampled_poses':9, 'limb_roots':worst}
        for name,record in worst.items():
            if record['maximum_exposure_m']>.00045:issues.append(action.name+': exposed root rim on '+name)
    report = {'clips':clips, 'pose_samples':9*len(clips), 'root_rim_vertices_per_pose':sum(map(len,roots.values())),
              'maximum_exposure_m':max(r['maximum_exposure_m'] for c in clips.values() for r in c['limb_roots'].values()),
              'issues':issues, 'scope':'Evaluated proximal skin rims versus the closed trunk using nearest oriented surfaces, nine poses per clip. Positive values indicate exposure; 0.45 mm tolerance at authored metre scale. This does not prove manifold union, self-intersection-free limbs or continuous-time coverage.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8', newline='\n')
    print('ORIGINAL_ATTACHMENT_CHECK '+json.dumps({k:v for k,v in report.items() if k!='clips'}), flush=True)
    assert not issues, issues


if __name__ == '__main__':main()
