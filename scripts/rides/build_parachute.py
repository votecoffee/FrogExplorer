"""Build the lightweight parachute canopy; suspension lines are posed at runtime."""
from pathlib import Path
from math import sin,cos,pi
import bpy
P=Path(__file__).resolve().parents[2];OUT=P/'game/assets/rides'
bpy.ops.wm.read_factory_settings(use_empty=True)
def material(name,color):
 m=bpy.data.materials.new(name);m.use_nodes=True;s=m.node_tree.nodes.get('Principled BSDF');s.inputs['Base Color'].default_value=(*color,1);s.inputs['Roughness'].default_value=.65;return m
orange=material('Orange parachute silk',(.85,.13,.015));cream=material('Cream parachute silk',(.86,.83,.69));cord=material('Reinforced rim',(.14,.08,.035))
vertices=[];faces=[];sectors=64;rings=10
for j in range(rings):
 t=.08+(pi/2-.08)*j/(rings-1)
 for i in range(sectors):
  a=2*pi*i/sectors;x=.75*sin(t)*cos(a);z=.75*sin(t)*sin(a);y=1.05+.55*cos(t)
  vertices.append((x,-z,y))
for j in range(rings-1):
 for i in range(sectors):faces.append((j*sectors+i,j*sectors+(i+1)%sectors,(j+1)*sectors+(i+1)%sectors,(j+1)*sectors+i))
mesh=bpy.data.meshes.new('Vented silk canopy');mesh.from_pydata(vertices,[],faces);obj=bpy.data.objects.new('Parachute canopy',mesh);bpy.context.collection.objects.link(obj);mesh.materials.append(orange);mesh.materials.append(cream)
for i,p in enumerate(mesh.polygons):p.material_index=((i%sectors)//8)%2;p.use_smooth=True
bpy.context.view_layer.objects.active=obj;obj.select_set(True);mod=obj.modifiers.new('Thin fabric','SOLIDIFY');mod.thickness=.004;bpy.ops.object.modifier_apply(modifier=mod.name)
curve=bpy.data.curves.new('Canopy rim','CURVE');curve.dimensions='3D';curve.bevel_depth=.006;curve.bevel_resolution=2;spline=curve.splines.new('POLY');spline.points.add(sectors)
for i,p in enumerate(spline.points):a=i*2*pi/sectors;p.co=(.75*cos(a),-.75*sin(a),1.05,1)
rim=bpy.data.objects.new('Canopy rim',curve);bpy.context.collection.objects.link(rim);curve.materials.append(cord)
bpy.ops.export_scene.gltf(filepath=str(OUT/'parachute.glb'),export_format='GLB',export_animations=False,export_cameras=False,export_lights=False)
bpy.ops.wm.save_as_mainfile(filepath=str(P/'data/parachute.blend'))
print('PARACHUTE_BUILT')
