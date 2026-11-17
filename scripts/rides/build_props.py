"""Create original lightweight exploration props; run with Blender --background."""
from pathlib import Path
from math import sin,cos,pi
import bpy,json
from mathutils import Vector
P=Path(__file__).resolve().parents[2];OUT=P/'game/assets/rides';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
def v(p):return Vector((p[0],-p[2],p[1]))
def mat(name,color,metal=0,rough=.35,alpha=1):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,alpha);m.use_nodes=True;s=m.node_tree.nodes.get('Principled BSDF');s.inputs['Base Color'].default_value=(*color,alpha);s.inputs['Metallic'].default_value=metal;s.inputs['Roughness'].default_value=rough;s.inputs['Alpha'].default_value=alpha
 if alpha<1:m.surface_render_method='DITHERED';s.inputs['Transmission Weight'].default_value=.35
 return m
green=mat('Lime enamel',(.075,.57,.018),.5,.22);gold=mat('Gold alloy',(.88,.49,.045),.75,.22);black=mat('Black leather',(.012,.016,.014),0,.45);rubber=mat('Tire rubber',(.015,.019,.017),0,.85);chrome=mat('Chrome',(.6,.67,.7),.9,.18);glass=mat('Blue glass',(.35,.65,.72),.15,.12,.26);lamp=mat('Headlamp lens',(.85,.94,.95),.25,.14);red=mat('Tail lamps',(.65,.015,.01),.2,.25)
def finish(o,name,m,parent=None):
 o.name=name;o.data.materials.append(m)
 if parent:o.parent=parent
 for p in o.data.polygons:p.use_smooth=True
 return o
def sphere(name,p,s,m,parent=None):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=v(p));o=bpy.context.object;o.scale=(s[0],s[2],s[1]);return finish(o,name,m,parent)
def cube(name,p,s,m,bevel=.025,parent=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=v(p));o=bpy.context.object;o.scale=(s[0],s[2],s[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  b=o.modifiers.new('Soft edges','BEVEL');b.width=bevel;b.segments=3;bpy.ops.object.modifier_apply(modifier=b.name)
 return finish(o,name,m,parent)
def tube(name,points,r,m,parent=None):
 curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=r;curve.bevel_resolution=3
 poly=curve.splines.new('POLY');poly.points.add(len(points)-1)
 for a,b in zip(poly.points,points):a.co=(*v(b),1)
 o=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(o);curve.materials.append(m)
 if parent:o.parent=parent
 return o
def disk(name,p,r,depth,m,parent=None):
 bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=depth,location=v(p),rotation=(0,pi/2,0));return finish(bpy.context.object,name,m,parent)
# Smooth front and rear shells leave a genuinely open cockpit.
cube('Undertray',(0,.11,0),(.59,.10,1.2),black)
sphere('Hood',(0,.255,.37),(.345,.125,.39),green)
sphere('Rear deck',(0,.255,-.46),(.345,.12,.25),green)
for side in [-1,1]:
 tube('Sculpted sill',[(side*(.285+.035*sin(i*pi/20)),.22+.012*cos(i*pi/20),-.44+i*.78/20) for i in range(21)],.066,green)
 tube('Door waist',[(side*.31,.31,-.40+i*.64/16) for i in range(17)],.026,green)
 for axle,z in [('F',.43),('R',-.43)]:
  # Parent geometry is authored in world space, then shifted to the wheel hub.
  center=(side*.345,.145,z);parent=bpy.data.objects.new('Wheel_'+axle+('L' if side<0 else 'R'),None);bpy.context.collection.objects.link(parent);parent.location=v(center)
  for o in [disk('Tire',center,.148,.105,rubber),disk('Alloy', (side*.403,.145,z),.111,.012,gold),disk('Hub',(side*.414,.145,z),.028,.015,chrome)]:o.parent=parent;o.matrix_parent_inverse=parent.matrix_world.inverted()
  for spoke in range(5):
   a=spoke*2*pi/5
   tube('Gold spoke',[(side*.412,.145+cos(a)*.025,z+sin(a)*.025),(side*.412,.145+cos(a)*.097,z+sin(a)*.097)],.013,gold,parent).matrix_parent_inverse=parent.matrix_world.inverted()
  tube('Wheel arch',[(side*.335,.145+sin(a)*.182,z+cos(a)*.182) for a in [i*pi/24 for i in range(25)]],.027,green)
 # Round forward-facing headlamps, a cheerful dark grille and mirrors.
 sphere('Lamp surround',(side*.245,.32,.65),(.108,.105,.047),chrome)
 sphere('Headlamp',(side*.245,.32,.678),(.089,.087,.025),lamp)
 sphere('Tail lamp',(side*.245,.28,-.67),(.075,.037,.022),red)
 tube('Mirror stalk',[(side*.31,.37,.12),(side*.41,.41,.14)],.012,black)
 sphere('Mirror',(side*.43,.42,.14),(.053,.034,.044),black)
 tube('Windshield upright',[(side*.295,.32,.255),(side*.26,.59,.105)],.018,black)
# Windshield pane and its black upper frame.
verts=[v(p) for p in [(-.295,.32,.255),(.295,.32,.255),(.26,.59,.105),(-.26,.59,.105)]]
mesh=bpy.data.meshes.new('Windshield');mesh.from_pydata(verts,[],[(0,1,2,3)]);o=bpy.data.objects.new('Windshield',mesh);bpy.context.collection.objects.link(o);finish(o,'Windshield',glass)
tube('Windshield rim',[(-.26,.59,.105),(0,.61,.105),(.26,.59,.105)],.020,black)
tube('Rear rollover',[(-.25,.33,-.38),(-.25,.59,-.38),(-.17,.65,-.38),(.17,.65,-.38),(.25,.59,-.38),(.25,.33,-.38)],.022,black)
for x in [-.145,.145]:
 cube('Seat cushion',(x,.255,-.12),(.24,.065,.29),black,.03)
 seat=cube('Seat back',(x,.37,-.27),(.235,.25,.07),black,.035);seat.rotation_euler.x=-.12
 cube('Headrest',(x,.51,-.285),(.14,.085,.065),black,.025)
cube('Dashboard',(0,.35,.22),(.57,.085,.085),black,.03)
tube('Steering wheel',[(-.145+cos(a)*.074,.418+sin(a)*.074,.12) for a in [i*2*pi/32 for i in range(33)]],.009,black)
tube('Wheel spoke',[(-.215,.418,.12),(-.075,.418,.12)],.007,chrome)
sphere('Smile grille',(0,.165,.706),(.205,.039,.012),black)
tube('Smile trim',[(-.19,.16,.71),(-.10,.13,.722),(0,.125,.725),(.10,.13,.722),(.19,.16,.71)],.009,red)
car_objects=list(bpy.data.objects)
bpy.ops.export_scene.gltf(filepath=str(OUT/'frog_convertible.glb'),export_format='GLB',export_animations=False,export_cameras=False,export_lights=False)
bpy.ops.wm.save_as_mainfile(filepath=str(P/'data/frog_convertible.blend'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
# A red latex helium balloon, with a tapered neck and tied knot.
latex=mat('Red latex',(.65,.018,.035),.05,.19)
profile=[(1.31,.018),(1.36,.045),(1.46,.125),(1.65,.29),(1.91,.425),(2.15,.45),(2.37,.35),(2.54,.18),(2.60,.015)]
vs=[];fs=[];n=40
for y,r in profile:
 for k in range(n):
  a=2*pi*k/n;vs.append(v((r*cos(a),y,r*sin(a))))
for i in range(len(profile)-1):
 for k in range(n):a=i*n+k;b=i*n+(k+1)%n;fs.append((a,b,b+n,a+n))
fs+=[tuple(reversed(range(n))),tuple((len(profile)-1)*n+k for k in range(n))]
mesh=bpy.data.meshes.new('Latex envelope');mesh.from_pydata(vs,[],fs);o=bpy.data.objects.new('Latex envelope',mesh);bpy.context.collection.objects.link(o);finish(o,'Latex envelope',latex)
mod=o.modifiers.new('Smooth latex','SUBSURF');mod.levels=2;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
sphere('Tied knot',(0,1.3,0),(.047,.026,.035),latex)
tube('Knot tie',[(.02,1.30,0),(.05,1.25,.01),(.015,1.24,.02),(-.02,1.29,0)],.003,black)
bpy.ops.export_scene.gltf(filepath=str(OUT/'helium_balloon.glb'),export_format='GLB',export_animations=False,export_cameras=False,export_lights=False)
bpy.ops.wm.save_as_mainfile(filepath=str(P/'data/helium_balloon.blend'))
print('RIDE_ASSETS_BUILT')
