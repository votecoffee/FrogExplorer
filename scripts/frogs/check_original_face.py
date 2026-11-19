"""Check eyelid coverage and oral surfaces on the authored Blender frog."""
import argparse
import json
from math import floor
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def check_open_oral_floor(arm):
    """Count oral-floor faces obscured by the exterior throat skin."""
    action = bpy.data.actions['Catch_Fly']
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(18)  # Near peak gape in Catch_Fly.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    throat = bpy.data.objects['Gular breathing sac'].evaluated_get(depsgraph)
    mesh = throat.to_mesh()
    surface = BVHTree.FromPolygons(
        [throat.matrix_world @ vertex.co for vertex in mesh.vertices],
        [tuple(face.vertices) for face in mesh.polygons],
    )
    throat.to_mesh_clear()
    jaw = bpy.data.objects['Articulated jaw and recessed oral floor'].evaluated_get(depsgraph)
    mesh = jaw.to_mesh()
    oral_material = jaw.data.materials.find('Warm oral mucosa')
    sampled = 0
    obstructed = 0
    for face in mesh.polygons:
        if face.material_index != oral_material:
            continue
        sampled += 1
        point = jaw.matrix_world @ face.center
        normal = (jaw.matrix_world.to_3x3() @ face.normal).normalized()
        _, _, _, hit = surface.ray_cast(point + normal*.004, -normal, .0038)
        if hit is not None:
            obstructed += 1
    jaw.to_mesh_clear()
    assert sampled, 'Missing oral-floor material on the articulated jaw'
    return {'sampled_faces': sampled, 'obstructed_faces': obstructed}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()))
    arm=bpy.data.objects['Original_Red_Eye_Rig'];issues=[];coverage={}
    action=bpy.data.actions['Living_Idle'];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
    bpy.context.scene.frame_set(0);depsgraph=bpy.context.evaluated_depsgraph_get();envelopes=[]
    for name in ['Original continuous trunk and muzzle','Articulated jaw and recessed oral floor']:
        obj=bpy.data.objects[name].evaluated_get(depsgraph);mesh=obj.to_mesh()
        envelopes.append(BVHTree.FromPolygons([obj.matrix_world@v.co for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons]));obj.to_mesh_clear()
    palate=bpy.data.objects['Recessed curved palate'].evaluated_get(depsgraph);mesh=palate.to_mesh();palate_exposure=-float('inf')
    for vertex in mesh.vertices:
        point=palate.matrix_world@vertex.co;distances=[]
        for tree in envelopes:
            nearest,normal,_,_=tree.find_nearest(point);distances.append((point-nearest).dot(normal))
        palate_exposure=max(palate_exposure,min(distances))
    palate.to_mesh_clear()
    if palate_exposure>.00020:issues.append('Closed palate protrudes beyond both head and jaw surfaces')
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
            if label=='open':
                skin=bpy.data.objects['Original continuous trunk and muzzle'].evaluated_get(depsgraph);mesh=skin.to_mesh()
                tree=BVHTree.FromPolygons([skin.matrix_world@v.co for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons]);skin.to_mesh_clear()
                hidden=0
                for point in points:
                    _,_,_,distance=tree.ray_cast(point+normal*.05,-normal,.10)
                    if distance is not None and distance<.0499:hidden+=1
                fraction=hidden/len(points);coverage[label][side]['cranial_skin_occluded_fraction']=fraction
                if fraction>.02:issues.append(side+': cranial skin cuts across the open iris')
    action=bpy.data.actions['Croak'];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
    jaw_angle=0.0;throat_scale=1.0
    for sample in range(17):
        frame=float(action.frame_range[1])*sample/16
        bpy.context.scene.frame_set(floor(frame),subframe=frame-floor(frame))
        jaw_angle=max(jaw_angle,float(arm.pose.bones['FX-jaw'].rotation_quaternion.angle))
        throat_scale=max(throat_scale,float(arm.pose.bones['Throat'].scale.z))
    if jaw_angle>.01:issues.append('Croak opens the jaw instead of keeping a closed mouth')
    if throat_scale<1.7:issues.append('Croak does not inflate the throat')
    oral_floor = check_open_oral_floor(arm)
    if oral_floor['obstructed_faces']:
        issues.append('Throat skin protrudes through the oral floor during Catch_Fly')
    report={'lid_coverage':coverage,'croak_maximum_jaw_angle_rad':jaw_angle,'croak_maximum_throat_scale':throat_scale,
            'closed_palate_maximum_exposure_m':palate_exposure,'open_oral_floor':oral_floor,
            'issues':issues,'scope':'Blender evaluated rays over the central 92 percent corneal radius: at most 2 percent open-lid or cranial-skin occlusion and at least 98 percent closed-lid coverage. Closed-palate vertices are checked against nearest oriented head/jaw surfaces with 0.20 mm exposure tolerance. Oral floor faces are checked for throat skin obstruction at one open Catch_Fly pose with 0.20 mm tolerance. Seventeen Croak poses check closed jaw and throat inflation. All checks use sampled geometry.'}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ORIGINAL_FACE_CHECK '+json.dumps(report),flush=True)
    assert not issues,issues


if __name__=='__main__':main()
