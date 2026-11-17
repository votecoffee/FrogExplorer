class_name LocalMeshWorld
extends WoodlandWorld

# Local packs share the pond's surface/contact contract. Scanned scenery does
# not acquire climbable trees or water merely because those objects are visible.
var packed_scene:PackedScene
var pack:Dictionary
var collision_count=0

func _ready():
 _configure_pack()
 var scene=packed_scene.instantiate()
 add_child(scene)
 _colliders(scene)

func _configure_pack():
 spawn_point=Vector3.ZERO
 for p in pack.get("spawn_candidates",[]):recovery_points.append(Vector3(float(p[0]),float(p[1]),float(p[2])))
 var b=pack.get("bounds",[-100,-100,100,100])
 travel_bounds=Rect2(float(b[0]),float(b[1]),float(b[2])-float(b[0]),float(b[3])-float(b[1]))
 camera_far=float(pack.get("camera_far",650.0));dry_fog_density=float(pack.get("fog_density",.0007));dry_fog_color=Color(.66,.75,.81)
 if pack.has("vertical_bounds"):
  var heights=pack.vertical_bounds
  surface_top=maxf(surface_top,float(heights[1])+50)
  surface_bottom=minf(surface_bottom,float(heights[0])-50)
  recovery_floor=minf(recovery_floor,float(heights[0])-30)
  flight_ceiling=maxf(flight_ceiling,float(heights[1])+60)
func _colliders(node:Node):
 if node is MeshInstance3D and node.mesh:
  var body=StaticBody3D.new();body.collision_layer=2;body.collision_mask=0
  var shape=CollisionShape3D.new();shape.shape=node.mesh.create_trimesh_shape()
  if shape.shape:
   shape.shape.backface_collision=true;body.add_child(shape);node.add_child(body);collision_count+=1
 # Snapshot children because a mesh receives a new collision child above.
 for child in node.get_children():
  if not child is StaticBody3D:_colliders(child)

func pond_radius(_x:float,_z:float):return INF
func in_water(_p:Vector3):return false

func ground_height(x:float,z:float):
 if not is_inside_tree():return 0.0
 var query=PhysicsRayQueryParameters3D.create(Vector3(x,surface_top,z),Vector3(x,surface_bottom,z),1)
 var hit=get_world_3d().direct_space_state.intersect_ray(query)
 return float(hit.position.y) if not hit.is_empty() else surface_bottom

func activate():
 super.activate()
 environment.fog_light_color=dry_fog_color;environment.fog_density=dry_fog_density
 environment.ambient_light_color=Color(.80,.85,.92)
