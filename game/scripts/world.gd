class_name WoodlandWorld
extends Node3D

const WATER = 0.0
const POND = Vector2(3.45,2.7)
var trees: Array[Dictionary] = []
var flies: Array[Dictionary] = []
var elapsed = 0.0
var rng = RandomNumberGenerator.new()
var environment: Environment
var fly_mesh: Mesh
var leaf_mesh: Mesh
var stone_mesh: Mesh
var materials = {}
var staging=false
var spawn_point=Vector3(2.8,.2,3.5)
var spawn_heading=PI
var recovery_points:Array[Vector3]=[]
var travel_bounds=Rect2(-10.5,-10.5,21,21)
var camera_far=65.0
var dry_fog_density=.008
var dry_fog_color=Color(.45,.62,.55)
var surface_top=150.0
var surface_bottom=-100.0
var recovery_floor=-60.0
var flight_ceiling=120.0

func activate():
 staging=false
 if environment==null:_lighting()

func set_collision_layers(layer:int,node:Node=self):
 if node is CollisionObject3D:node.collision_layer=layer
 for child in node.get_children():set_collision_layers(layer,child)


func material(key, color, roughness=0.9):
 if materials.has(key): return materials[key]
 var mat = StandardMaterial3D.new()
 mat.albedo_color = color
 mat.roughness = roughness
 materials[key] = mat
 return mat

func noise_texture(noise:FastNoiseLite,width:int,height:int,gradient:Gradient):
 # Generate synchronously so a short headless run cannot exit with texture
 # worker resources still pending.
 var image=noise.get_image(width,height)
 image.convert(Image.FORMAT_RGB8)
 for y in range(height):
  for x in range(width):image.set_pixel(x,y,gradient.sample(image.get_pixel(x,y).r))
 return ImageTexture.create_from_image(image)

func pond_radius(x: float,z: float):
 var angle = atan2(z/POND.y,x/POND.x)
 return Vector2(x/POND.x,z/POND.y).length()/(1+0.045*sin(angle*3)+0.025*cos(angle*5))

func ground_height(x: float,z: float):
 var r = pond_radius(x,z)
 var land = 0.13+0.065*sin(x*0.8)*cos(z*0.7)+0.025*sin(x*2+z)+.65*smoothstep(7.5,16.0,Vector2(x,z).length())
 var bed = -1.18*(1-smoothstep(0.18,1.0,r))+0.10*smoothstep(0.88,1.15,r)
 return lerpf(bed,land,smoothstep(1.0,1.28,r))

func in_water(p: Vector3):
 return pond_radius(p.x,p.z)<1.02 and ground_height(p.x,p.z)<-0.16 and p.y<0.10

func mesh_instance(mesh: Mesh,mat: Material,p: Vector3,scale_value=Vector3.ONE,parent:Node=self):
 var n = MeshInstance3D.new()
 n.mesh=mesh;n.material_override=mat;n.position=p;n.scale=scale_value;parent.add_child(n)
 return n

func _ready():
 spawn_point=Vector3(2.8,ground_height(2.8,3.5)+.04,3.5)
 for p in [Vector2(0,5),Vector2(-2,4),Vector2(4.5,0),Vector2(0,0)]:recovery_points.append(Vector3(p.x,ground_height(p.x,p.y),p.y))
 rng.seed=7102026
 _lighting()
 _terrain()
 _pond()
 _woodland()
 _details()
 _flies()

func _lighting():
 if staging:return
 environment=Environment.new()
 environment.background_mode=Environment.BG_SKY
 var sky=Sky.new();var sky_mat=ProceduralSkyMaterial.new()
 sky_mat.sky_top_color=Color(0.16,0.34,0.43);sky_mat.sky_horizon_color=Color(0.66,0.77,0.72)
 sky_mat.ground_bottom_color=Color(0.08,0.14,0.11);sky_mat.ground_horizon_color=Color(0.44,0.55,0.44)
 sky.sky_material=sky_mat;environment.sky=sky
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color(0.68,0.77,0.70);environment.ambient_light_energy=0.85
 environment.fog_enabled=true;environment.fog_light_color=Color(0.45,0.62,0.55);environment.fog_density=0.008
 var env=WorldEnvironment.new();env.environment=environment;add_child(env)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-54,-35,0);sun.light_color=Color(1.0,0.92,0.75);sun.light_energy=1.25;sun.shadow_enabled=true;sun.directional_shadow_max_distance=25;add_child(sun)

func _terrain():
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var size=18.0;var n=128;var step=size*2/n
 for iz in range(n):
  for ix in range(n):
   var x=-size+ix*step;var z=-size+iz*step
   var points=[Vector2(x,z),Vector2(x+step,z),Vector2(x,z+step),Vector2(x+step,z),Vector2(x+step,z+step),Vector2(x,z+step)]
   for p in points:
    var y=ground_height(p.x,p.y);var r=pond_radius(p.x,p.y)
    var noise=0.5+0.5*sin(p.x*5.3+cos(p.y*3.7))*cos(p.y*6.1)
    var green=Color(0.12,0.22,0.085).lerp(Color(0.24,0.32,0.12),noise)
    var color=Color(0.20,0.16,0.095).lerp(green,smoothstep(0.95,1.38,r))
    if y<-0.1: color=Color(0.12,0.16,0.11).lerp(Color(0.24,0.23,0.15),noise)
    st.set_color(color);st.set_uv(p*.3)
    st.set_normal(Vector3(ground_height(p.x-.02,p.y)-ground_height(p.x+.02,p.y),.04,ground_height(p.x,p.y-.02)-ground_height(p.x,p.y+.02)).normalized())
    st.add_vertex(Vector3(p.x,y,p.y))
 var mesh=st.commit();var mat=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=1;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 var dirt=FastNoiseLite.new();dirt.seed=19;dirt.frequency=.10;dirt.fractal_octaves=4
 var tones=Gradient.new();tones.set_color(0,Color(.50,.50,.50));tones.set_color(1,Color(1,1,1));mat.albedo_texture=noise_texture(dirt,256,256,tones)
 var ground=mesh_instance(mesh,mat,Vector3.ZERO)
 var body=StaticBody3D.new();body.collision_layer=1;var collision=CollisionShape3D.new();var shape=mesh.create_trimesh_shape();shape.backface_collision=true;collision.shape=shape;body.add_child(collision);ground.add_child(body)

func _pond():
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in range(128):
  var a=i*TAU/128;var b=(i+1)*TAU/128
  for p in [Vector3.ZERO,Vector3(cos(b)*POND.x,0,sin(b)*POND.y),Vector3(cos(a)*POND.x,0,sin(a)*POND.y)]:
   st.set_normal(Vector3.UP);st.set_uv(Vector2(p.x,p.z));st.add_vertex(p+Vector3(0,.004,0))
 var mat=ShaderMaterial.new();mat.shader=load("res://shaders/water.gdshader");mesh_instance(st.commit(),mat,Vector3.ZERO)
 var pad_mesh=CylinderMesh.new();pad_mesh.top_radius=1;pad_mesh.bottom_radius=1;pad_mesh.height=.018;pad_mesh.radial_segments=20
 var pad_mat=material("lily",Color(0.16,0.33,0.09))
 for i in range(17):
  var a=rng.randf_range(0,TAU);var r=rng.randf_range(.15,.80);var p=Vector3(cos(a)*POND.x*r,.025,sin(a)*POND.y*r);var s=rng.randf_range(.12,.26)
  mesh_instance(pad_mesh,pad_mat,p,Vector3(s,1,s*.85))
  if i%5==0:
   var blossom=SphereMesh.new();blossom.radial_segments=8;blossom.rings=4
   mesh_instance(blossom,material("blossom",Color(.94,.68,.69)),p+Vector3(0,.04,0),Vector3(.075,.045,.075))

func _woodland():
 leaf_mesh=SphereMesh.new();leaf_mesh.radial_segments=10;leaf_mesh.rings=5
 var bark=material("bark",Color.WHITE)
 var noise=FastNoiseLite.new();noise.seed=72;noise.frequency=.055;noise.fractal_octaves=4
 var gradient=Gradient.new();gradient.set_color(0,Color(.10,.065,.03));gradient.set_color(1,Color(.35,.25,.13));bark.albedo_texture=noise_texture(noise,128,256,gradient);bark.uv1_scale=Vector3(2,5,1)
 var positions=[Vector2(3.6,3.4),Vector2(-3.9,2.5),Vector2(4.2,-1.4),Vector2(-3.5,-3.5)]
 for i in range(22):
  var a=i*TAU/22;var r=rng.randf_range(5.2,9.7);positions.append(Vector2(cos(a)*r,sin(a)*r))
 for i in range(positions.size()):
  var p=positions[i];var h=rng.randf_range(3.5,5.0);var radius=rng.randf_range(.18,.29);var base=Vector3(p.x,ground_height(p.x,p.y),p.y)
  var tree=Node3D.new();tree.name="ClimbableTree_%02d"%i;add_child(tree)
  var trunk=CylinderMesh.new();trunk.top_radius=.70;trunk.bottom_radius=1;trunk.height=1;trunk.radial_segments=12
  mesh_instance(trunk,bark,base+Vector3(0,h*.5,0),Vector3(radius,h,radius),tree)
  var body=StaticBody3D.new();body.collision_layer=1;var cs=CollisionShape3D.new();var shape=CylinderShape3D.new();shape.radius=radius;shape.height=h;cs.shape=shape;cs.position=base+Vector3(0,h*.5,0);body.add_child(cs);tree.add_child(body)
  var canopy=[]
  for j in range(4):
   var a=j*TAU/4+rng.randf_range(-.3,.3);var top=base+Vector3(cos(a)*.65,h-0.25+sin(j)*.3,sin(a)*.65)
   var foliage=mesh_instance(leaf_mesh,material("leaves%d"%(i%4),[Color(.12,.26,.075),Color(.19,.32,.09),Color(.20,.29,.07),Color(.14,.29,.13)][i%4]),top,Vector3(1.05,.75,1.0),tree);canopy.append(foliage)
   _branch(tree,bark,base+Vector3(0,h*.68,0),top,.08)
  for j in range(4):
   var a=j*TAU/4;_branch(tree,bark,base+Vector3(0,.25,0),base+Vector3(cos(a)*radius*2,.03,sin(a)*radius*2),.07)
  trees.append({"center":base,"radius":radius,"height":h-.45,"canopy":canopy})

func _branch(parent,mat,a,b,radius):
 var mesh=CylinderMesh.new();mesh.top_radius=.65;mesh.bottom_radius=1;mesh.height=1;mesh.radial_segments=7
 var n=mesh_instance(mesh,mat,(a+b)*.5,Vector3.ONE,parent);n.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))*Basis.from_scale(Vector3(radius,(b-a).length(),radius))

func _details():
 stone_mesh=SphereMesh.new();stone_mesh.radial_segments=8;stone_mesh.rings=4
 for i in range(130):
  var a=rng.randf_range(0,TAU);var r=rng.randf_range(.98,1.30);var x=cos(a)*POND.x*r;var z=sin(a)*POND.y*r;var s=rng.randf_range(.035,.13)
  mesh_instance(stone_mesh,material("stone%d"%(i%3),[Color(.34,.34,.27),Color(.28,.30,.24),Color(.43,.40,.31)][i%3]),Vector3(x,ground_height(x,z)+s*.25,z),Vector3(s,s*.6,s*1.2))
 var blade_tool=SurfaceTool.new();blade_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 for v in [Vector3(-.025,-.22,0),Vector3(.025,-.22,0),Vector3(.045,.23,.03)]:blade_tool.set_normal(Vector3.UP);blade_tool.add_vertex(v)
 var blade=blade_tool.commit()
 var grass=material("grass",Color(.22,.33,.10));grass.cull_mode=BaseMaterial3D.CULL_DISABLED
 var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=blade;mm.instance_count=650
 for i in range(650):
  var a=rng.randf_range(0,TAU);var r=rng.randf_range(1.03,2.9);var x=cos(a)*POND.x*r;var z=sin(a)*POND.y*r;var scale_value=rng.randf_range(.45,1.3)
  mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,a+rng.randf()).scaled(Vector3(scale_value,scale_value,scale_value)),Vector3(x,ground_height(x,z)+.20*scale_value,z)))
 var blades=MultiMeshInstance3D.new();blades.multimesh=mm;blades.material_override=grass;add_child(blades)
 _ferns()
 # A moss-covered fallen branch on the bank.
 _branch(self,material("fallen",Color(.20,.20,.09)),Vector3(-1.5,.27,3.25),Vector3(.2,.24,3.55),.14)

func _ferns():
 var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for frond in range(7):
  var a=frond*TAU/7;var outward=Vector3(cos(a),0,sin(a));var side=Vector3(-sin(a),0,cos(a))
  for leaf in range(1,7):
   var t=leaf/7.0;var center=outward*t*.34+Vector3.UP*(sin(t*PI*.8)*.22)
   for sign_value in [-1.0,1.0]:
    var tip=center+side*sign_value*(1-t)*.105+outward*.04
    for v in [center-outward*.018,tip,center+outward*.035]:st.set_normal(Vector3.UP);st.add_vertex(v)
 var mesh=st.commit();var mat=material("fern",Color(.10,.29,.075));mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=85
 for i in range(85):
  var a=rng.randf_range(0,TAU);var r=rng.randf_range(1.12,2.7);var x=cos(a)*POND.x*r;var z=sin(a)*POND.y*r;var s=rng.randf_range(.65,1.4)
  mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3.ONE*s),Vector3(x,ground_height(x,z)+.02,z)))
 var ferns=MultiMeshInstance3D.new();ferns.multimesh=mm;ferns.material_override=mat;add_child(ferns)

func _flies():
 fly_mesh=SphereMesh.new();fly_mesh.radial_segments=6;fly_mesh.rings=3
 var body=material("fly",Color(.065,.045,.025));var wings=material("wing",Color(.65,.73,.65))
 for i in range(16):
  var a=i*TAU/16;var r=1.02 if i%2 else .8
  var home=Vector3(cos(a)*POND.x*r,maxf(.20,ground_height(cos(a)*POND.x*r,sin(a)*POND.y*r)+.30),sin(a)*POND.y*r)
  if i>=12:home=trees[i-12].center+Vector3(.45,1.2+float(i%2)*.7,.35)
  if i==0:home=Vector3(2.35,.42,2.75)
  var fly=Node3D.new();add_child(fly);mesh_instance(fly_mesh,body,Vector3.ZERO,Vector3(.018,.015,.025),fly)
  mesh_instance(fly_mesh,wings,Vector3(.018,.009,0),Vector3(.024,.003,.018),fly);mesh_instance(fly_mesh,wings,Vector3(-.018,.009,0),Vector3(.024,.003,.018),fly)
  flies.append({"node":fly,"home":home,"phase":i*2.7,"respawn":0.0})

func _process(delta):
 elapsed+=delta
 for fly in flies:
  var node=fly.node
  if fly.respawn>0:
   fly.respawn-=delta;node.visible=false
  else:
   node.visible=true;var t=elapsed+fly.phase
   node.position=fly.home+Vector3(sin(t*2.3)*.16,sin(t*3.7)*.08,cos(t*2.7)*.14);node.rotation.y=t*3

func nearest_fly(p:Vector3,range_value:float):
 var best=-1;var dist=range_value
 for i in range(flies.size()):
  if flies[i].respawn>0:continue
  var d=p.distance_to(flies[i].node.global_position)
  if d<dist:best=i;dist=d
 return best

func catch_fly(index):
 if index<0 or index>=flies.size() or flies[index].respawn>0:return false
 flies[index].respawn=5.0;flies[index].node.visible=false
 return true

func nearest_tree(p:Vector3,max_distance=.55):
 var best=-1;var distance=max_distance
 for i in range(trees.size()):
  var tree=trees[i];var d=Vector2(p.x-tree.center.x,p.z-tree.center.z).length()-tree.radius
  if d<distance and p.y<tree.center.y+tree.height:best=i;distance=d
 return best
