"""Read-only Blender floor/height inspection for source-scale calibration."""
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

folder=Path(sys.argv[sys.argv.index("--")+1]);root=Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(folder/"source.glb"))
vertices=[];faces=[]
for obj in bpy.context.scene.objects:
    if obj.type!="MESH":continue
    obj.data.calc_loop_triangles();offset=len(vertices)
    vertices.extend(obj.matrix_world@v.co for v in obj.data.vertices)
    faces.extend(tuple(offset+i for i in face.vertices) for face in obj.data.loop_triangles)
lo=Vector(tuple(min(v[i] for v in vertices) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
bvh=BVHTree.FromPolygons(vertices,faces,all_triangles=True)
n=180;samples=[]
for row in range(n):
    line=[];y=hi.y-(hi.y-lo.y)*row/(n-1)
    for col in range(n):
        x=lo.x+(hi.x-lo.x)*col/(n-1)
        at,normal,index,distance=bvh.ray_cast(Vector((x,y,hi.z+1)),Vector((0,0,-1)),hi.z-lo.z+2)
        line.append([at.z,abs(normal.z)] if at is not None else None)
    samples.append(line)
data={"bounds":[list(lo),list(hi)],"n":n,"heights":samples}
(folder/"height_probe.json").write_bytes((json.dumps(data)+"\n").encode("utf-8"))
# Source top view for visual calibration, no desktop/window capture.
scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=4
scene.world=bpy.data.worlds.new("Sky");scene.world.color=(.6,.6,.6)
bpy.ops.object.light_add(type="SUN");bpy.context.object.data.energy=2
center=(lo+hi)*.5;span=hi.x-lo.x
bpy.ops.object.camera_add(location=(center.x,center.y,hi.z+span*2));camera=bpy.context.object
camera.rotation_euler=(0,0,0);camera.data.type="ORTHO";camera.data.ortho_scale=span*1.05;camera.data.clip_end=span*10;camera.data.clip_start=span*.00001;scene.camera=camera
scene.render.resolution_x=1400;scene.render.resolution_y=700;scene.render.resolution_percentage=100
scene.render.filepath=str(root/"outputs/Landmarks_20261117"/(folder.name+"_top.png"));bpy.ops.render.render(write_still=True)
