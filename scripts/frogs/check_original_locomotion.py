"""Check the three revised clips for sampled distal skin/body intersections.

Run in Blender with --input ORIGINAL.blend --report REPORT.json. Proximal
attachments have a separate check; this checks pads and lower limb surfaces.
"""
import argparse
import json
from math import floor
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    arm = bpy.data.objects['Original_Red_Eye_Rig'];trunk = bpy.data.objects['Original continuous trunk and muzzle']
    pads = [o for o in bpy.data.objects if o.type=='MESH' and 'adhesive disc' in o.name]
    assert len(pads)==18
    selected = {o.name:list(range(len(o.data.vertices))) for o in pads}
    for obj in bpy.data.objects:
        if not obj.name.startswith('Continuous '):continue
        uv = obj.data.uv_layers.active.data
        selected[obj.name] = sorted({loop.vertex_index for loop in obj.data.loops if uv[loop.index].uv.x>.40})
    clips = {};issues = []
    for clip in ['Slow_Walk','Big_Jump','Swim']:
        action = bpy.data.actions[clip];arm.animation_data.action = action;arm.animation_data.action_slot = action.slots[0]
        penetration = 0.0;separation = float('inf');hind_y = float('inf');worst = None
        for sample in range(48):
            frame = float(action.frame_range[1])*sample/48
            bpy.context.scene.frame_set(floor(frame),subframe=frame-floor(frame))
            depsgraph = bpy.context.evaluated_depsgraph_get()
            body = trunk.evaluated_get(depsgraph);mesh = body.to_mesh()
            tree = BVHTree.FromPolygons([body.matrix_world@v.co for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons])
            body.to_mesh_clear();centers = {}
            for name,indices in selected.items():
                obj = bpy.data.objects[name].evaluated_get(depsgraph);mesh = obj.to_mesh()
                points = [obj.matrix_world@mesh.vertices[index].co for index in indices]
                for point in points:
                    nearest,normal,_,_ = tree.find_nearest(point)
                    depth = -(point-nearest).dot(normal)
                    if depth>penetration:
                        penetration = depth;worst = {'mesh':name,'frame':frame,'point':list(point)}
                if 'adhesive disc' in name:
                    centers[name] = sum(points,Vector())/len(points)
                    if name.startswith('foot'):hind_y = min(hind_y,min(p.y for p in points))
                obj.to_mesh_clear()
            for hand,p in centers.items():
                if not hand.startswith('hand'):continue
                for foot,q in centers.items():
                    if foot.startswith('foot'):separation = min(separation,(p-q).length)
        clips[clip] = {'sampled_poses':48,'maximum_distal_skin_trunk_penetration_m':penetration,
                       'minimum_hand_hind_pad_center_distance_m':separation,'minimum_hind_pad_y_m':hind_y,
                       'worst_intrusion':worst}
        if penetration>.0008:issues.append(clip+': distal skin enters the trunk')
        if separation<.008:issues.append(clip+': hand and hind pads overlap')
        if hind_y<-.045:issues.append(clip+': hind pads sweep into the head region')
    report = {'clips':clips,'issues':issues,'scope':'144 sampled Blender poses. Oriented nearest-surface distances on pads and lower limb vertices, 0.8 mm trunk intrusion tolerance; 8 mm minimum fore/hind pad center clearance; hind pads remain behind Y=-0.045 m. Authored metre scale. Does not prove all mesh self-intersections or continuous-time clearance.'}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ORIGINAL_LOCOMOTION_CHECK '+json.dumps(report),flush=True)
    assert not issues,issues


if __name__=='__main__':main()
