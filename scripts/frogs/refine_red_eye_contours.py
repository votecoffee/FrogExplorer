"""Continue the local red-eyed shape v3 with jaw, digit and web contours.

Run inside Blender, supplying the v3 packed Blender file. No skin, skeleton,
animation or original source assets are embedded in this script.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys

import bpy
from mathutils import Vector
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parent))
from refine_red_eye_shape import fingerprint,gaussian,smooth


def digital_chain(name):
    match=re.match(r'DEF-([fr])_(index|middle|ring|pinky)\.(?:001|002)\.([LR])$',name)
    if match:return (match[1],match[3],['index','middle','ring','pinky'].index(match[2])+1)
    match=re.match(r'DEF-([fr])_palm\.(00[1-4])\.([LR])(?:\.001)?$',name)
    if match:return (match[1],match[3],int(match[2]))
    return None


def refine(body,arm,strength):
    group_names={g.index:g.name for g in body.vertex_groups}
    points=[v.co.copy() for v in body.data.vertices]
    normals=[v.normal.copy() for v in body.data.vertices]
    weights=[{group_names[g.group]:g.weight for g in v.groups} for v in body.data.vertices]
    eyes=[arm.data.bones['FX_eye.'+s].head_local.copy() for s in ['L','R']]
    pads=[]
    for bone in arm.data.bones:
        terminal=any(bone.name.startswith(prefix+digit+'.002.') for prefix in ['DEF-f_','DEF-r_'] for digit in ['index','middle','ring','pinky'])
        if not terminal and bone.name not in ['DEF-r_toe.L','DEF-r_toe.R']:continue
        a=bone.head_local.copy();b=bone.tail_local.copy();axis=b-a
        cloud=[p[:] for p,w in zip(points,weights) if w.get(bone.name,0)>.65 and (p-a).dot(axis)/axis.length_squared>.60]
        if len(cloud)<10:continue
        cloud=np.asarray(cloud);_,vectors=np.linalg.eigh(np.cov(cloud.T));normal=Vector(vectors[:,0].tolist())
        forward=(axis-normal*axis.dot(normal)).normalized();lateral=normal.cross(forward).normalized()
        side_values=(cloud-np.asarray(b))@np.asarray(lateral)
        center_side=float((np.quantile(side_values,.05)+np.quantile(side_values,.95))/2)
        half_width=float((np.quantile(side_values,.95)-np.quantile(side_values,.05))/2)
        pads.append((bone.name,a,b,normal,forward,lateral,center_side,max(.0005,half_width)))
    roots={(family,side):arm.data.bones[('DEF-hand.' if family=='f' else 'DEF-foot.')+side+'.001'].tail_local.copy() for family in ['f','r'] for side in ['L','R']}
    changed=0;maximum=0;web_vertices=0;face_vertices=0;displacements=[]
    polish_mask=np.zeros(len(points))
    for vertex,original,normal_before,w in zip(body.data.vertices,points,normals,weights):
        p=original.copy();head=w.get('FX_gape_lift',0);jaw=w.get('FX_jaw',0)
        clearance=min((original-center).length for center in eyes)
        guard=smooth(.0095,.014,clearance)
        if head:
            roof=gaussian(original.x,0,.018)*gaussian(original.y,-.033,.024)*smooth(.088,.099,original.z)
            nose=gaussian(original.x,0,.014)*gaussian(original.y,-.057,.010)*smooth(.081,.089,original.z)
            p.z-=strength*head*guard*(.00115*roof+.00055*nose)
        if jaw:
            # Taper the ventral chin without opening the closed lip boundary or
            # changing the palate/tongue geometry and its articulation.
            underside=1-smooth(.074,.080,original.z)
            outside=1-smooth(.05,.65,normal_before.z)
            p.z+=strength*jaw*.00145*underside*outside*gaussian(original.y,-.046,.023)
        if (head+jaw)>.2 and (p-original).length>1e-9:face_vertices+=1
        # More slender digit stems, with a curved distal outline rather than
        # widening the already broad, flat-ended pads from the source model.
        for name,a,b,normal,forward,lateral,center_side,half_width in pads:
            weight=w.get(name,0)
            if not weight:continue
            axis=b-a;t=(original-a).dot(axis)/axis.length_squared
            polish_mask[vertex.index]=max(polish_mask[vertex.index],strength*weight*smooth(.30,.70,t))
            side=(original-b).dot(lateral)-center_side
            narrow=.30*gaussian(t,.42,.23)+.16*smooth(.62,.96,t)
            p-=lateral*(strength*weight*side*narrow)
            span=max(-1,min(1,side/half_width))
            round_tip=half_width*.52*(1-math.sqrt(max(0,1-span*span)))*smooth(.50,.94,t)
            p-=forward*(strength*weight*round_tip)
        # Shared weights identify the membrane between neighboring digits.
        # Retract that web slightly; keep single-digit pads and contact centers.
        chains={}
        for name,weight in w.items():
            chain=digital_chain(name)
            if chain:chains[chain]=chains.get(chain,0)+weight
        for family,side in roots:
            values=[weight for (f,s,_),weight in chains.items() if f==family and s==side]
            total=sum(values)
            if total<.4 or len(values)<2:continue
            shared=max(0,min(1,2*(1-sum((value/total)**2 for value in values))))
            if shared<.02:continue
            pull=(roots[(family,side)]-original)*.11
            if pull.length>.0022:pull= pull.normalized()*.0022
            p+=pull*(strength*total*shared);web_vertices+=1
        vertex.co=p;distance=(p-original).length;displacements.append(distance)
        if distance>1e-9:changed+=1;maximum=max(maximum,distance)
    # A masked Taubin pass rounds the small contour kinks introduced by a
    # sampled, triangulated outline, without broadly shrinking the digits.
    coords=np.asarray([v.co[:] for v in body.data.vertices])
    edges=np.asarray([edge.vertices[:] for edge in body.data.edges],dtype=np.int64)
    counts=np.bincount(edges.ravel(),minlength=len(coords)).clip(1)
    for _ in range(3):
        for step in [.35,-.36]:
            neighbors=np.zeros_like(coords)
            np.add.at(neighbors,edges[:,0],coords[edges[:,1]])
            np.add.at(neighbors,edges[:,1],coords[edges[:,0]])
            coords+=step*polish_mask[:,None]*(neighbors/counts[:,None]-coords)
    # Back off only the small neighborhoods whose triangles would fold across
    # their original orientation. Retain a margin for float32 export rounding.
    source=np.asarray(points);faces=np.asarray([p.vertices[:] for p in body.data.polygons],dtype=np.int64)
    assert faces.shape[1]==3,'Expected the prepared triangulated body'
    original_normals=np.cross(source[faces[:,1]]-source[faces[:,0]],source[faces[:,2]]-source[faces[:,0]])
    original_area_squared=np.sum(original_normals**2,axis=1);valid=original_area_squared>1e-20
    delta=coords-source;factors=np.ones(len(coords));repairs=0
    for _ in range(60):
        normals=np.cross(coords[faces[:,1]]-coords[faces[:,0]],coords[faces[:,2]]-coords[faces[:,0]])
        bad=valid & (np.sum(normals*original_normals,axis=1)<original_area_squared*.01)
        if not np.any(bad):break
        affected=np.unique(faces[bad]);neighbor_mask=np.zeros(len(coords),bool);neighbor_mask[affected]=True
        touching=edges[np.any(neighbor_mask[edges],axis=1)].ravel()
        factors[np.unique(touching)]*=.92;factors[affected]*=.75
        coords=source+delta*factors[:,None];repairs+=1
    else:raise ValueError('Could not preserve body triangle orientation')
    for vertex,point in zip(body.data.vertices,coords):vertex.co=point
    displacements=np.linalg.norm(coords-np.asarray(points),axis=1)
    changed=int(np.count_nonzero(displacements>1e-9));maximum=float(displacements.max())
    body.data.update()
    if body.data.has_custom_normals:body.data.normals_split_custom_set([(0,0,0)]*len(body.data.loops))
    return {'body_vertices_changed':changed,'face_vertices_refined':face_vertices,'interdigital_vertices_refined':web_vertices,'terminal_pads_refined':len(pads),'masked_pad_polish_cycles':3,'local_orientation_repair_steps':repairs,'max_displacement_m':maximum,'mean_displacement_m':float(np.mean(displacements)),'strength':strength}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--strength',type=float,default=1)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);args.input=args.input.resolve();args.output=args.output.resolve()
    if not 0<=args.strength<=1:parser.error('strength must be between 0 and 1')
    output=args.output/'Red_Eyed_Tree_Frog_Shape_v4'
    if args.input==output.with_suffix('.blend'):parser.error('Preserve the input by choosing a different output directory')
    args.output.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(args.input));scene=bpy.context.scene
    arm=next(o for o in scene.objects if o.type=='ARMATURE');body=bpy.data.objects['Red_Eyed_Tree_FrogBody']
    assert len(arm.data.bones)==111 and len(bpy.data.actions)==28,'Expected the prepared local model'
    before=fingerprint(arm);metrics=refine(body,arm,args.strength);after=fingerprint(arm)
    assert before['animation']==after['animation'] and before['skeleton']==after['skeleton']
    assert before['packed_images']==after['packed_images']
    for name,old in before['meshes'].items():
        for key in old:
            if name==body.name and key=='positions':continue
            assert old[key]==after['meshes'][name][key],(name,key)
    action=bpy.data.actions['Living_Idle'];arm.animation_data.action=action;arm.animation_data.action_slot=action.slots[0]
    scene.frame_set(0);bpy.context.view_layer.update()
    for track in arm.animation_data.nla_tracks:track.mute=True
    bpy.ops.object.select_all(action='DESELECT')
    for obj in scene.objects:
        if obj.type in ['MESH','ARMATURE']:obj.select_set(True)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.wm.save_as_mainfile(filepath=str(output.with_suffix('.blend')),compress=True)
    bpy.ops.export_scene.gltf(filepath=str(output.with_suffix('.glb')),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_skins=True,export_influence_nb=4,export_image_format='AUTO',export_tangents=True,export_optimize_animation_size=True,export_optimize_animation_keep_anim_armature=False,export_cameras=False,export_lights=False)
    report={'revision':'red-eyed shape v4, continuing v3','metrics':metrics,'animation_curves_and_joint_rest_unchanged':True,'uv_topology_weights_and_packed_images_unchanged':True,'eye_lid_tongue_geometry_unchanged':True,'baseline':before,'candidate':after,'source_terms':'Local derivative; source redistribution restrictions remain.'}
    (args.output/'shape_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('RED_EYE_CONTOURS_SAVED',json.dumps(metrics),flush=True)


if __name__=='__main__':main()
