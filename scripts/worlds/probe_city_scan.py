"""Inspect native model XY heights and a fitted top view for arrival selection."""
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[2]
place_id=sys.argv[sys.argv.index("--")+1];folder=ROOT/"data/world_sources"/place_id
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(folder/"source.glb"))
config_path=folder/"build_config.json"
config=json.loads(config_path.read_bytes().decode("utf-8")) if config_path.exists() else {}
for obj in list(bpy.context.scene.objects):
    if obj.type=="MESH" and obj.name in config.get("exclude_meshes",[]):bpy.data.objects.remove(obj,do_unlink=True)
vertices=[];faces=[]
for obj in bpy.context.scene.objects:
    if obj.type!="MESH":continue
    obj.data.calc_loop_triangles();offset=len(vertices)
    vertices.extend(obj.matrix_world@v.co for v in obj.data.vertices)
    faces.extend(tuple(offset+i for i in t.vertices) for t in obj.data.loop_triangles)
lo=Vector(tuple(min(v[i] for v in vertices) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
bvh=BVHTree.FromPolygons(vertices,faces,all_triangles=True);n=160;samples=[]
for row in range(n):
    line=[];y=hi.y-(hi.y-lo.y)*row/(n-1)
    for col in range(n):
        x=lo.x+(hi.x-lo.x)*col/(n-1)
        at,normal,_,_=bvh.ray_cast(Vector((x,y,hi.z+1)),Vector((0,0,-1)),hi.z-lo.z+2)
        line.append([at.z,abs(normal.z)] if at is not None else None)
    samples.append(line)
data={"bounds":[list(lo),list(hi)],"n":n,"heights":samples}
(folder/"height_probe.json").write_bytes((json.dumps(data)+"\n").encode("utf-8"))
scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=6;scene.cycles.use_denoising=True
scene.world=bpy.data.worlds.new("Sky");scene.world.color=(.65,.65,.65)
bpy.ops.object.light_add(type="SUN");bpy.context.object.data.energy=2
center=(lo+hi)*.5;span=max(hi.x-lo.x,(hi.y-lo.y)*1200/850)*1.05
bpy.ops.object.camera_add(location=(center.x,center.y,hi.z+span*2));camera=bpy.context.object;camera.rotation_euler=(0,0,0)
camera.data.type="ORTHO";camera.data.ortho_scale=span;camera.data.clip_end=span*10;camera.data.clip_start=span*.00001;scene.camera=camera
scene.render.resolution_x=1200;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.render.filepath=str(ROOT/"outputs/World_Cities_20261117"/(place_id+"_top.png"));bpy.ops.render.render(write_still=True)
