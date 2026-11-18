"""Check eyelid coverage and closed-mouth calling on the authored Blender frog."""
import argparse
import json
from math import floor
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    arm=bpy.data.objects['Original_Red_Eye_Rig'];issues=[];coverage={}
    action=bpy.data.actions['Living_Idle'];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
    for label,frame in [('open',0),('closed',float(action.frame_range[1])*.79)]:
        bpy.context.scene.frame_set(floor(frame),subframe=frame-floor(frame))
        depsgraph=bpy.context.evaluated_depsgraph_get();coverage[label]={}
        for side in ['L','R']:
            eye=bpy.data.objects['Red corneal surface '+side]
            uv=eye.data.uv_layers.active.data
            apex=min(eye.data.loops,key=lambda loop:(uv[loop.index].uv-Vector((.5,.5))).length).vertex_index
            indices=sorted({loop.vertex_index for loop in eye.data.loops if (uv[loop.index].uv-Vector((.5,.5))).length<.46})
            obj=eye.evaluated_get(depsgraph);mesh=obj.to_mesh()
            points=[obj.matrix_world@mesh.vertices[index].co for index in indices]
            center=arm.matrix_world@arm.pose.bones['FX_eye.'+side].matrix.translation
            normal=(obj.matrix_world@mesh.vertices[apex].co-center).normalized();obj.to_mesh_clear()
            lid=bpy.data.objects['Mobile upper eyelid '+side].evaluated_get(depsgraph);mesh=lid.to_mesh()
            tree=BVHTree.FromPolygons([lid.matrix_world@v.co for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons]);lid.to_mesh_clear()
            hidden=0
            for point in points:
                _,_,_,distance=tree.ray_cast(point+normal*.05,-normal,.10)
                if distance is not None and distance<.0499:hidden+=1
            fraction=hidden/len(points)
            coverage[label][side]={'sampled_cornea_vertices':len(points),'lid_occluded_fraction':fraction}
            if label=='open' and fraction>.02:issues.append(side+': open lid covers the iris')
            if label=='closed' and fraction<.98:issues.append(side+': closed lid leaves the iris exposed')
    action=bpy.data.actions['Croak'];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
    jaw_angle=0.0;throat_scale=1.0
    for sample in range(17):
        frame=float(action.frame_range[1])*sample/16
        bpy.context.scene.frame_set(floor(frame),subframe=frame-floor(frame))
        jaw_angle=max(jaw_angle,float(arm.pose.bones['FX-jaw'].rotation_quaternion.angle))
        throat_scale=max(throat_scale,float(arm.pose.bones['Throat'].scale.z))
    if jaw_angle>.01:issues.append('Croak opens the jaw instead of keeping a closed mouth')
    if throat_scale<1.7:issues.append('Croak does not inflate the throat')
    report={'lid_coverage':coverage,'croak_maximum_jaw_angle_rad':jaw_angle,'croak_maximum_throat_scale':throat_scale,
            'issues':issues,'scope':'Blender evaluated lid ray coverage over the central 92 percent corneal radius at open and closed blink poses; no more than 2 percent open-lid occlusion and at least 98 percent closed-lid coverage. Seventeen Croak poses check closed jaw and throat inflation. Geometry checks, not an image realism metric or continuous-time guarantee.'}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ORIGINAL_FACE_CHECK '+json.dumps(report),flush=True)
    assert not issues,issues


if __name__=='__main__':main()
