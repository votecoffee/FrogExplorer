extends SceneTree

var folder=""
var materials={}

func _initialize():bake.call_deferred()

func meshes(node:Node,root:Node3D,prefix:String,collision:bool,parent=Transform3D.IDENTITY):
 var transform=parent*(node.transform if node is Node3D else Transform3D.IDENTITY)
 if node is MeshInstance3D and node.mesh:
  for surface in node.mesh.get_surface_count():
   var material=node.mesh.surface_get_material(surface)
   assert(material)
   var key=material.resource_name
   assert(key.begins_with("FrogExplorerMaterial_"))
   if not materials.has(key):
    assert(ResourceSaver.save(material,folder+"/shared/"+key+".tres",ResourceSaver.FLAG_CHANGE_PATH)==OK)
    materials[key]=folder+"/shared/"+key+".tres"
   node.mesh.surface_set_material(surface,load(materials[key]))
  var index=str(root.get_child_count());var path=prefix+"_mesh_"+index+".res"
  assert(ResourceSaver.save(node.mesh,path,ResourceSaver.FLAG_COMPRESS|ResourceSaver.FLAG_CHANGE_PATH)==OK)
  var visual=MeshInstance3D.new();visual.mesh=load(path);visual.transform=transform;root.add_child(visual);visual.owner=root
  if collision:
   var shape=node.mesh.create_trimesh_shape();assert(shape);shape.backface_collision=true
   path=prefix+"_collision_"+index+".res";assert(ResourceSaver.save(shape,path,ResourceSaver.FLAG_COMPRESS)==OK)
   var body=StaticBody3D.new();body.collision_layer=2;body.collision_mask=0;body.transform=transform;root.add_child(body);body.owner=root
   var child=CollisionShape3D.new();child.shape=load(path);body.add_child(child);child.owner=root
 for child in node.get_children():meshes(child,root,prefix,collision,transform)

func save(root:Node,path:String):
 var packed=PackedScene.new();assert(packed.pack(root)==OK);assert(ResourceSaver.save(packed,path)==OK)

func bake():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--pack="):folder=arg.trim_prefix("--pack=")
 assert(not folder.is_empty())
 var plan=JSON.parse_string(FileAccess.get_file_as_string(folder+"/build_plan.json"))
 var overview=Node3D.new();overview.name="Overview"
 for tile in plan.tiles:
  for level in tile.lods.size():
   var stem=folder+"/"+str(tile.lods[level].scene).trim_suffix(".tscn")
   var source=load(stem+".gltf") as PackedScene;assert(source)
   var root=Node3D.new();root.name=str(tile.id);root.position=Vector3(tile.origin[0],0,tile.origin[2])
   var model=source.instantiate();meshes(model,root,stem,level==0);model.free();save(root,stem+".tscn");root.free()
  var stem=folder+"/overview/"+str(tile.id)
  var source=load(stem+".gltf") as PackedScene;assert(source)
  var root=Node3D.new();root.name=str(tile.id);root.position=Vector3(tile.origin[0],0,tile.origin[2]);overview.add_child(root);root.owner=overview
  var model=source.instantiate();meshes(model,root,stem,false);model.free()
  for child in root.get_children():child.owner=overview
  print("CITY_CELL_BAKED ",tile.id)
 save(overview,folder+"/overview.tscn");overview.free();print("CITY_PACK_BAKED ",plan.tiles.size());quit()
