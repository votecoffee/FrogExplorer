class_name WorldTiles
extends RefCounted

static var cache={}

static func manifest(item:Dictionary)->Dictionary:
 if "--whole-scenes" in OS.get_cmdline_user_args():return {}
 var path=str(item.get("tile_manifest",""))
 # The optional derived pack is not required by the original asset bundle.
 if path.is_empty() or not FileAccess.file_exists(path):return {}
 if cache.has(path):return cache[path]
 var result=_read(path);cache[path]=result;return result

static func safe_relative(path:String)->bool:
 return not path.is_empty() and not path.is_absolute_path() and not ":" in path and not "\\" in path and not ".." in path.split("/")

static func _read(path:String)->Dictionary:
 var invalid={"error":"The tile pack is incomplete or invalid: "+path.get_file()}
 if not path.begins_with("res://assets/worlds/") or ".." in path.split("/"):return invalid
 var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not parsed is Dictionary or parsed.get("version",0)!=1:return invalid
 if not parsed.get("tiles") is Array or not parsed.get("files") is Dictionary:return invalid
 var size=float(parsed.get("tile_size",0))
 if size<16 or size>512 or parsed.tiles.is_empty():return invalid
 if not parsed.get("detail_radius") is float and not parsed.get("detail_radius") is int:return invalid
 if float(parsed.detail_radius)<size or float(parsed.detail_radius)>size*4:return invalid
 if not parsed.get("overview_triangles") is float and not parsed.get("overview_triangles") is int:return invalid
 var folder=path.get_base_dir()
 for file in parsed.files:
  if not safe_relative(file) or str(parsed.files[file]).length()!=64 or not FileAccess.file_exists(folder+"/"+file):return invalid
 var overview=str(parsed.get("overview_scene",""))
 if not safe_relative(overview) or not parsed.files.has(overview):return invalid
 var seen={}
 for tile in parsed.tiles:
  if not tile is Dictionary or not tile.get("cell") is Array or tile.cell.size()!=2 or not tile.get("origin") is Array or tile.origin.size()!=3:return invalid
  var scene=str(tile.get("scene",""));var id=str(tile.get("id",""));var cell=Vector2i(int(tile.cell[0]),int(tile.cell[1]))
  if id.is_empty() or seen.has(cell) or not safe_relative(scene) or not parsed.files.has(scene):return invalid
  if not is_equal_approx(float(tile.origin[0]),cell.x*size) or not is_zero_approx(float(tile.origin[1])) or not is_equal_approx(float(tile.origin[2]),cell.y*size):return invalid
  seen[cell]=true
 parsed["folder"]=folder;parsed["path"]=path
 return parsed

static func verify(data:Dictionary)->String:
 # Run once before travel, never once per frame. Collision and render inputs
 # are both covered; a damaged pack cannot replace the current world.
 for file in data.files:
  if FileAccess.get_sha256(data.folder+"/"+file)!=data.files[file]:return "Tile pack integrity check failed: "+str(file)
 return ""
