"""Blender-only, non-destructive shape pass for a locally supplied red-eyed frog.

This script contains no model or texture data and does not change source terms.
Run Blender --background --python this_file -- --input model.blend --output DIR.
The original file is read only; body topology, UVs, weights and animation stay.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
import numpy as np


def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)


def gaussian(x,center,width):return math.exp(-((x-center)/width)**2)


def fingerprint(arm):
    curves=[]
    for action in sorted(bpy.data.actions,key=lambda a:a.name):
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        curves.append((action.name,curve.data_path,curve.array_index,[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in curve.keyframe_points]))
    bones=[(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in arm.data.bones]
    meshes={}
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH':continue
        mesh=obj.data;uv=[]
        for layer in mesh.uv_layers:
            values=np.empty(len(layer.data)*2,np.float32);layer.data.foreach_get('uv',values);uv.append(hashlib.sha256(values.tobytes()).hexdigest())
        meshes[obj.name]={'positions':hashlib.sha256(np.asarray([v.co[:] for v in mesh.vertices],np.float32).tobytes()).hexdigest(),'topology':hashlib.sha256(str([tuple(p.vertices) for p in mesh.polygons]).encode()).hexdigest(),'uv':uv,'weights':hashlib.sha256(str([[(g.group,g.weight) for g in v.groups] for v in mesh.vertices]).encode()).hexdigest(),'materials':[m.name for m in mesh.materials],'matrix':[list(row) for row in obj.matrix_world]}
    images={im.name:hashlib.sha256(im.packed_file.data).hexdigest() for im in bpy.data.images if im.packed_file}
    return {'animation':hashlib.sha256(str(curves).encode()).hexdigest(),'skeleton':hashlib.sha256(str(bones).encode()).hexdigest(),'meshes':meshes,'packed_images':images}


def refine(body,arm,strength):
    groups={g.index:g.name for g in body.vertex_groups}
    eyes=[arm.data.bones['FX_eye.'+side].head_local.copy() for side in ['L','R']]
    limbs=[]
    for side in ['L','R']:
        for kind,amount in [('upper_arm',.14),('forearm',.20),('hand',.10),('thigh',.10),('shin',.17),('foot',.10)]:
            name='DEF-'+kind+'.'+side
            a=arm.data.bones[name].head_local.copy();b=arm.data.bones[name+'.001'].tail_local.copy()
            limbs.append((name,a,b,amount))
    # The existing pad's thinnest principal axis supplies a local flattening
    # normal; expanding in its other axes avoids spherical fingertip beads.
    pads=[]
    for bone in arm.data.bones:
        if not any(bone.name.startswith(prefix+digit+'.002.') for prefix in ['DEF-f_','DEF-r_'] for digit in ['index','middle','ring','pinky']):continue
        a=bone.head_local.copy();b=bone.tail_local.copy();axis=b-a;length=axis.length_squared
        points=[]
        for vertex in body.data.vertices:
            weight=sum(g.weight for g in vertex.groups if groups[g.group]==bone.name)
            if weight>.5 and (vertex.co-a).dot(axis)/length>.72:points.append(vertex.co[:])
        if len(points)<8:continue
        values=np.asarray(points);_,vectors=np.linalg.eigh(np.cov(values.T));normal=Vector(vectors[:,0].tolist())
        pads.append((bone.name,a,b,normal))
    before=np.asarray([v.co[:] for v in body.data.vertices]);changed=0;largest=0
    for vertex in body.data.vertices:
        original=vertex.co.copy();p=original.copy();weights={groups[g.group]:g.weight for g in vertex.groups}
        trunk=sum(w for name,w in weights.items() if name.startswith('DEF-spine'))
        face=weights.get('FX_gape_lift',0)+weights.get('FX_jaw',0)
        if trunk:
            waist=gaussian(p.y,.030,.031)
            shoulder=gaussian(p.y,-.008,.020)
            p.x*=1-strength*trunk*(.10*waist+.025*shoulder)
            center=.081
            p.z=center+(p.z-center)*(1-strength*trunk*.07*waist)
        if face:
            # A shorter rounded muzzle and lower orbital crest, while retaining
            # the separate iris, cornea, lid shells and their attachment joints.
            p.y+=strength*face*.0012*gaussian(original.y,-.061,.012)
            p.x*=1-strength*face*.025*gaussian(original.y,-.057,.015)
            brow=gaussian(abs(original.x),.013,.009)*gaussian(original.y,-.039,.014)*smooth(.093,.102,original.z)
            # The socket edge must continue covering the rear iris/globe. Keep
            # a smooth protected band around each original eye contact ring.
            clearance=min((original-center).length for center in eyes)
            socket_guard=smooth(.0095,.013,clearance)
            p.z-=strength*weights.get('FX_gape_lift',0)*.0016*brow*socket_guard
        throat=weights.get('FX_native_throat',0)
        if throat:p.z+=strength*throat*.0018*gaussian(original.z,.064,.009)
        delta=Vector()
        for prefix,a,b,amount in limbs:
            weight=sum(w for name,w in weights.items() if name in [prefix,prefix+'.001'])
            if weight==0:continue
            axis=b-a;t=max(0,min(1,(original-a).dot(axis)/axis.length_squared));center=a+axis*t
            taper=.65+.35*math.sin(math.pi*t)
            delta+=(center-original)*(strength*amount*weight*taper)
        p+=delta
        for name,a,b,normal in pads:
            weight=weights.get(name,0)
            if weight==0:continue
            axis=b-a;t=(original-a).dot(axis)/axis.length_squared
            pad=smooth(.48,.86,t)
            radial=original-(a+axis*t)
            planar=radial-normal*radial.dot(normal)
            p+=planar*(strength*weight*(.14*pad-.06*(1-pad)))
            p-=normal*(strength*weight*.10*pad*radial.dot(normal))
        vertex.co=p
        distance=(p-original).length
        if distance>1e-9:changed+=1;largest=max(largest,distance)
    body.data.update()
    if body.data.has_custom_normals:body.data.normals_split_custom_set([(0,0,0)]*len(body.data.loops))
    after=np.asarray([v.co[:] for v in body.data.vertices])
    return {'changed_body_vertices':changed,'body_vertices':len(body.data.vertices),'maximum_rest_displacement_m':largest,'mean_rest_displacement_m':float(np.linalg.norm(after-before,axis=1).mean()),'terminal_pads_refined':len(pads),'strength':strength}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--strength',type=float,default=1)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=True)
    if not 0<=args.strength<=1:parser.error('strength must be between 0 and 1')
    if args.input.resolve()==args.output/'Red_Eyed_Tree_Frog_Shape_v3.blend':parser.error('Choose a different output directory to preserve the input model')
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()));scene=bpy.context.scene
    arm=next(o for o in scene.objects if o.type=='ARMATURE');body=bpy.data.objects['Red_Eyed_Tree_FrogBody']
    assert len(arm.data.bones)==111 and len(bpy.data.actions)==28,'Expected the prepared, fully animated local model'
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
    output=args.output/'Red_Eyed_Tree_Frog_Shape_v3'
    bpy.ops.wm.save_as_mainfile(filepath=str(output.with_suffix('.blend')),compress=True)
    bpy.ops.export_scene.gltf(filepath=str(output.with_suffix('.glb')),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_skins=True,export_influence_nb=4,export_image_format='AUTO',export_tangents=True,export_optimize_animation_size=True,export_optimize_animation_keep_anim_armature=False,export_cameras=False,export_lights=False)
    report={'revision':'red-eyed shape v3','metrics':metrics,'skeleton_unchanged':True,'animation_curves_unchanged':True,'uv_topology_weights_unchanged':True,'packed_skin_and_eye_images_unchanged':True,'separate_eye_lid_and_tongue_geometry_unchanged':True,'baseline':before,'candidate':after,'source_terms':'Derived local Blendkit model; shape edits do not remove its source restrictions.'}
    (args.output/'shape_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('RED_EYE_SHAPE_SAVED',json.dumps(metrics),flush=True)


if __name__=='__main__':main()
