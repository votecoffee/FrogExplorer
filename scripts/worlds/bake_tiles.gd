extends SceneTree

var shared_material:Material

func _initialize():
 call_deferred("bake")

func bake_meshes(node:Node,root:Node3D,prefix:String,transform_so_far:Transform3D=Transform3D.IDENTITY):
 var current=transform_so_far
 if node is Node3D:current=current*node.transform
 if node is MeshInstance3D and node.mesh:
  for surface in range(node.mesh.get_surface_count()):node.mesh.surface_set_material(surface,shared_material)
  var path=prefix+"_mesh_"+str(root.get_child_count())+".res"
  assert(ResourceSaver.save(node.mesh,path,ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_CHANGE_PATH)==OK)
  var mesh=MeshInstance3D.new();mesh.mesh=load(path);mesh.transform=current;root.add_child(mesh);mesh.owner=root
 for child in node.get_children():bake_meshes(child,root,prefix,current)

func add_collision(node:Node,root:Node3D,prefix:String,transform_so_far:Transform3D=Transform3D.IDENTITY):
 var current=transform_so_far
 if node is Node3D:current=current*node.transform
 if node is MeshInstance3D and node.mesh:
  var shape=node.mesh.create_trimesh_shape()
  if shape:
   shape.backface_collision=true
   var path=prefix+"_"+str(root.get_child_count())+".res"
   assert(ResourceSaver.save(shape,path,ResourceSaver.FLAG_COMPRESS)==OK)
   var body=StaticBody3D.new();body.collision_layer=2;body.collision_mask=0;body.transform=current;root.add_child(body);body.owner=root
   var collider=CollisionShape3D.new();collider.shape=load(path);body.add_child(collider);collider.owner=root
 for child in node.get_children():add_collision(child,root,prefix,current)

func save_scene(root:Node,path:String):
 var scene=PackedScene.new();assert(scene.pack(root)==OK);assert(ResourceSaver.save(scene,path)==OK)

func bake():
 var folder=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--pack="):folder=arg.trim_prefix("--pack=")
 assert(not folder.is_empty())
 var plan=JSON.parse_string(FileAccess.get_file_as_string(folder+"/build_plan.json"))
 var overview=Node3D.new();overview.name="Overview"
 for tile in plan.tiles:
  var path=folder+"/detail/"+str(tile.id)
  var source=load(path+".gltf") as PackedScene;assert(source)
  var root=Node3D.new();root.name=str(tile.id)
  root.position=Vector3(tile.origin[0],0,tile.origin[2])
  var mesh=source.instantiate()
  if not shared_material:
   var meshes=mesh.find_children("*","MeshInstance3D",true,false)
   assert(not meshes.is_empty())
   shared_material=meshes[0].mesh.surface_get_material(0)
   assert(ResourceSaver.save(shared_material,folder+"/shared/material.tres",ResourceSaver.FLAG_CHANGE_PATH)==OK)
  bake_meshes(mesh,root,path);add_collision(mesh,root,path);mesh.free()
  save_scene(root,path+".tscn");root.free()
  if tile.overview:
   var far_scene=load(folder+"/overview/"+str(tile.id)+".gltf") as PackedScene;assert(far_scene)
   var far_root=Node3D.new();far_root.name=str(tile.id);far_root.position=Vector3(tile.origin[0],0,tile.origin[2]);overview.add_child(far_root);far_root.owner=overview
   var far_mesh=far_scene.instantiate();bake_meshes(far_mesh,far_root,folder+"/overview/"+str(tile.id));far_mesh.free()
   for child in far_root.get_children():child.owner=overview
 save_scene(overview,folder+"/overview.tscn");overview.free()
 print("TILES_BAKED ",plan.tiles.size());quit()
