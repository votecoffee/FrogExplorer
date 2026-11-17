extends SceneTree

# Check the runtime dependency closure and baked geometry in every installed
# tile pack, without loading source GLBs or driving a desktop window.
var failures=[]
var reports=[]
func _initialize():run.call_deferred()
func dependencies(path:String,allowed:Dictionary,visited:Dictionary):
 if visited.has(path):return
 visited[path]=true
 for item in ResourceLoader.get_dependencies(path):
  var dependency=str(item).split("::")[-1]
  if not allowed.has(dependency):failures.append("Unbundled dependency: "+path+" -> "+dependency);continue
  dependencies(dependency,allowed,visited)

func inspect(node:Node)->Dictionary:
 var triangles=0;var collision=0;var materials={}
 if node is MeshInstance3D and node.mesh:
  for i in range(node.mesh.get_surface_count()):
   var arrays=node.mesh.surface_get_arrays(i)
   var indices=arrays[Mesh.ARRAY_INDEX]
   triangles+=(indices.size() if indices!=null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size())/3
   var material=node.mesh.surface_get_material(i)
   if material:materials[material.resource_name]=true
 if node is CollisionShape3D and node.shape is ConcavePolygonShape3D:collision=node.shape.get_faces().size()/3
 for child in node.get_children():
  var data=inspect(child);triangles+=data.triangles;collision+=data.collision
  materials.merge(data.materials)
 return {"triangles":triangles,"collision":collision,"materials":materials}

func run():
 var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/travel_places.json"))
 for place in catalog.places:
  if place.provider!="local_mesh":continue
  var data=WorldTiles.manifest(place)
  if data.is_empty() or data.has("error"):failures.append("Missing/invalid tile pack: "+str(place.id));continue
  var reason=WorldTiles.verify(data)
  if not reason.is_empty():failures.append(reason);continue
  var allowed={};var visited={}
  for file in data.files:allowed[data.folder+"/"+str(file)]=true
  dependencies(data.folder+"/"+str(data.overview_scene),allowed,visited)
  var count=0;var triangles=0;var materials={}
  for tile in data.tiles:
   var path=data.folder+"/"+str(tile.scene)
   dependencies(path,allowed,visited)
   var source=load(path) as PackedScene
   if not source:failures.append("Invalid tile scene: "+path);continue
   var node=source.instantiate();var geometry=inspect(node);node.free()
   if geometry.triangles!=int(tile.triangles) or geometry.collision!=geometry.triangles:failures.append("Render/collision triangle mismatch: "+path)
   count+=1;triangles+=geometry.triangles;materials.merge(geometry.materials)
   await process_frame
  var overview=(load(data.folder+"/"+str(data.overview_scene)) as PackedScene).instantiate()
  var far=inspect(overview);overview.free()
  if far.collision!=0 or far.triangles!=int(data.overview_triangles):failures.append("Invalid overview geometry: "+str(place.id))
  if materials.size()!=int(data.source_materials):failures.append("Source material slots lost: "+str(place.id))
  if ResourceLoader.has_cached(str(place.scene)):failures.append("Original full mesh loaded: "+str(place.id))
  reports.append({"id":place.id,"tiles":count,"triangles":triangles,"materials":materials.size(),"runtime_dependencies":visited.size()})
  print("TILE_CATALOG_PACK "+JSON.stringify(reports.back()))
 var report={"places":reports,"failures":failures}
 var file=FileAccess.open("res://../state/tile_catalog_probe.json",FileAccess.WRITE);file.store_string(JSON.stringify(report," ")+"\n");file.close()
 print("TILE_CATALOG_PROBE "+JSON.stringify({"places":reports.size(),"failures":failures}))
 quit(0 if failures.is_empty() and reports.size()==16 else 1)
