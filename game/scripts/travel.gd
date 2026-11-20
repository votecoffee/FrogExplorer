class_name WorldTravel
extends Node

signal changed
var game:Node3D
var catalog:Array[Dictionary]=[]
var current_id="home_woodland_pond"
var map_epoch=0
var status="idle"
var progress=0.0
var message=""
var last_error=""
var history:Array[String]=[]
var persist_history=true
var category="any"
var busy=false
var ticket=0
var staged:WoodlandWorld
var verification
var rng=RandomNumberGenerator.new()
const CATALOG="res://data/travel_places.json"
const TileCheck=preload("res://scripts/tile_check.gd")

func _ready():
 rng.randomize()
 var parsed=JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
 if parsed is Dictionary and parsed.get("version",0)==1:
  for item in parsed.get("places",[]):
   if item is Dictionary:catalog.append(item)
 var args=OS.get_cmdline_user_args()
 persist_history=not ("--smoke" in args or "--travel-smoke" in args or "--size-smoke" in args or "--ride-smoke" in args or "--activity-smoke" in args or "--test-session" in args)
 if persist_history:_load_history()

func place(id:String)->Dictionary:
 for item in catalog:
  if item.get("id","")==id:return item
 return {}

func profile()->String:
 if OS.get_name()=="Windows":return "windows"
 return "pi5" if Engine.get_architecture_name() in ["arm64","arm32"] else "linux"

func in_activity()->bool:
 return place(current_id).get("provider","")=="activity"

func unavailable(item:Dictionary)->String:
 if item.is_empty():return "That place is not in the installed catalog."
 if item.get("status","")!="ready":return "This place is still being prepared."
 if not profile() in item.get("profiles",[]):return "This scene pack has not been qualified for this device yet."
 if game.party and game.party.lan:
  var party_reason=game.party.lan.travel_reason(str(item.get("id","")))
  if not party_reason.is_empty():return party_reason
 var size=FrogBodyMetrics.DEFAULT_FACTOR
 var sizes=item.get("size_range",[FrogBodyMetrics.MIN_FACTOR,FrogBodyMetrics.MAX_FACTOR])
 if sizes.size()!=2 or size<float(sizes[0]) or size>float(sizes[1]):return "This place does not support the default arrival size."
 if item.get("provider","")=="pond":return ""
 if item.get("provider","")=="activity":
  if game.party and (game.party.records.size()!=1 or game.party.lan.role!="local"):
   return "Activities are for single-player sessions."
  return "" if item.get("activity","") in ExplorerActivityWorld.ACTIVITIES else "This activity is not installed."
 if item.get("provider","")!="local_mesh":return "This world provider is not installed."
 var tiles=WorldTiles.manifest(item)
 if tiles.has("error"):return tiles.error
 var path=str(item.get("scene","")) if tiles.is_empty() else str(tiles.folder)+"/"+str(tiles.overview_scene)
 if not path.begins_with("res://assets/worlds/") or not ResourceLoader.exists(path):return "The scene pack is missing."
 if not item.has("spawn") or item.spawn.size()!=3 or not item.has("bounds") or item.bounds.size()!=4:return "The scene pack has no safe arrival definition."
 return ""

func available_places()->Array[Dictionary]:
 var result:Array[Dictionary]=[]
 for item in catalog:
  if unavailable(item).is_empty():result.append(item)
 return result

func choose_random()->String:
 var options:Array[Dictionary]=[]
 for item in available_places():
  if item.id!=current_id and item.get("provider","")!="activity" and item.get("random_eligible",false) and (category=="any" or item.get("category","")==category):options.append(item)
 if options.is_empty():return ""
 # Prefer places absent from the last ten visits, shorten for a small pool.
 var fresh=options.filter(func(item):return not item.id in history.slice(maxi(0,history.size()-10)))
 if not fresh.is_empty():options.assign(fresh)
 return str(options[rng.randi_range(0,options.size()-1)].id)

func random_trip():
 if busy:cancel();return
 var id=choose_random()
 if id.is_empty():
  game.hud.toast("No other installed place in this category. N opens places; H returns to the pond.")
  return
 request(id)

func request(id:String):
 if game.party and game.party.lan.is_client() and not game.party.lan.suppress_world:
  game.party.tell("The host chooses travel for the whole group.");return
 if busy:return
 var item=place(id)
 var reason=unavailable(item)
 if not reason.is_empty():_fail(reason);return
 if id==current_id:game.hud.toast("You are already here.");return
 ticket+=1;busy=true;last_error="";progress=.02;status="checking";message="Preparing "+str(item.name)+"...";changed.emit()
 _prepare.call_deferred(item,ticket)

func cancel():
 if not busy:return
 ticket+=1;busy=false;status="cancelled";progress=0;message="Travel cancelled. You are still in "+str(place(current_id).get("name","the pond"))+"."
 if verification:verification.cancel()
 _discard_stage();changed.emit();game.hud.toast(message)

func _valid(token:int)->bool:return busy and token==ticket and not game.quitting

func _prepare(item:Dictionary,token:int):
 if not _valid(token):return
 var scene:PackedScene
 var tiles=WorldTiles.manifest(item)
 if item.provider=="local_mesh":
  if not tiles.is_empty():
   var integrity=await _verify_pack(tiles,token)
   if not _valid(token):return
   if not integrity.is_empty():_fail(integrity);return
  status="loading";message="Loading scenery...";changed.emit()
  if not _valid(token):return
  var path=str(item.scene) if tiles.is_empty() else str(tiles.folder)+"/"+str(tiles.overview_scene)
  if DisplayServer.get_name()=="headless":
   # The dummy rendering backend cannot safely allocate mesh/texture RIDs
   # concurrently with the active scene. Keep headless server loading serial.
   scene=load(path) as PackedScene
  else:
   scene=await _load_scene(path,token)
  if not _valid(token):return
  if not scene:_fail("The scene pack has no usable scene.");return
 if not _valid(token):return
 status="collision";progress=.65;message="Preparing the ground...";changed.emit()
 if item.provider=="pond":staged=WoodlandWorld.new()
 elif item.provider=="activity":
  var activity:=ExplorerActivityWorld.new()
  activity.activity=item.activity
  staged=activity
 else:
  var local_world=LocalMeshWorld.new() if tiles.is_empty() else TiledMeshWorld.new()
  local_world.packed_scene=scene;local_world.pack=item
  if local_world is TiledMeshWorld:local_world.manifest=tiles;local_world.game=game
  staged=local_world
 staged.staging=true;staged.visible=false;staged.name="IncomingWorld"
 game.add_child(staged) # Keep static bodies registered; layer 2 isolates them from the frog.
 staged.set_collision_layers(2);changed.emit()
 if not _valid(token):return
 if staged is TiledMeshWorld:
  var deadline=Time.get_ticks_msec()+60000
  while not staged.initial_ready():
   if not _valid(token):return
   if not staged.stream_error.is_empty():_fail(staged.stream_error);return
   if Time.get_ticks_msec()>deadline:_fail("The arrival tiles did not finish loading. Staying here.");return
   await get_tree().process_frame
   if not _valid(token):return
 # Let the physics server register the isolated collision layer before queries.
 await get_tree().physics_frame
 await get_tree().physics_frame
 if not _valid(token):return
 var reason=unavailable(item)
 if not reason.is_empty():_fail(reason);return
 status="arrival";progress=.85;message="Checking a safe arrival...";changed.emit()
 var p=item.get("spawn",[2.8,.2,3.5]);var expected=Vector3(float(p[0]),float(p[1]),float(p[2]))
 var spawn=_safe_spawn(staged,staged.spawn_point if staged is ExplorerActivityWorld else expected)
 if spawn.is_empty():_fail("There is no clear, walkable ground at this arrival point. Staying here.");return
 _commit(item,spawn)

func _verify_pack(data:Dictionary,token:int)->String:
 # At most one hashing worker exists, including a recently cancelled visit.
 while verification:
  if not _valid(token):return "cancelled"
  await get_tree().process_frame
 if not _valid(token):return "cancelled"
 if WorldTiles.is_verified(data):return ""
 var job=TileCheck.new();verification=job
 if job.start(data)!=OK:verification=null;return "Could not start the scene integrity check."
 status="checking";message="Checking scene pack...";changed.emit()
 while job.is_alive():
  if not _valid(token):job.cancel()
  else:progress=.02+.08*job.fraction()
  await get_tree().process_frame
 var result=job.finish();verification=null
 return result

func _exit_tree():
 if verification:
  verification.cancel();verification.finish();verification=null

func _load_scene(path:String,token:int)->PackedScene:
 var existing=ResourceLoader.load_threaded_get_status(path)
 if existing not in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
  var error=ResourceLoader.load_threaded_request(path,"PackedScene")
  if error!=OK:_fail("The scene pack could not be opened.");return null
 while true:
  if not _valid(token):
   ResourceLoader.load_threaded_get(path);return null
  var amount=[];var state=ResourceLoader.load_threaded_get_status(path,amount)
  if not amount.is_empty():progress=.05+.55*float(amount[0])
  changed.emit()
  if state==ResourceLoader.THREAD_LOAD_LOADED:break
  if state!=ResourceLoader.THREAD_LOAD_IN_PROGRESS:_fail("The scene pack could not be loaded.");return null
  await get_tree().process_frame
 return ResourceLoader.load_threaded_get(path) as PackedScene

func _commit(item:Dictionary,spawn:Dictionary):
 # This is the only swap point. Nothing in the previous world is changed until
 # the new collision and capsule-clearance checks have passed.
 var old=game.woodland
 if game.party:game.party.before_travel()
 var was_paused=game.pilot.paused;game.pilot.paused=true
 if game.rides:game.rides.clear_for_travel()
 game.pilot.release_contacts() # release the old tree/tongue references first
 staged.spawn_point=spawn.position
 if not staged is ExplorerActivityWorld:staged.spawn_heading=deg_to_rad(float(item.get("heading_degrees",0)))
 old.set_collision_layers(0)
 game.woodland=staged;game.pilot.woodland=staged;game.camera_rig.woodland=staged
 game.remove_child(old);old.queue_free()
 staged.set_collision_layers(1);staged.visible=true;staged.process_mode=Node.PROCESS_MODE_INHERIT;staged.activate()
 game.pilot.arrive_at_default_size(spawn.position);game.pilot.paused=was_paused;game.camera_rig.initialized=false
 game.controls.remote_until=0;game.controls.velocity_until=0;game.controls.size_until=0
 game.controls.remote_move=Vector2.ZERO;game.controls.remote_aux=Vector2.ZERO
 game.controls.size_axis=0;game.controls.resize_wait_for_release=true
 game.ambience.stream_paused=item.provider!="pond"
 staged=null;current_id=item.id;map_epoch+=1;busy=false;status="idle";progress=1.0
 if game.party:game.party.after_travel()
 history.append(current_id)
 if history.size()>50:history.pop_front()
 _save_history();message="Arrived in "+str(item.name)+"."
 game._event("place_changed",{"place_id":current_id,"map_epoch":map_epoch,"anchor":item.get("anchor",{}),"scale":FrogBodyMetrics.DEFAULT_FACTOR})
 print("TRAVEL_ARRIVED "+current_id+" epoch="+str(map_epoch))
 game.hud.toast(message);changed.emit()

func _safe_spawn(world:WoodlandWorld,expected:Vector3)->Dictionary:
 var size=FrogBodyMetrics.DEFAULT_FACTOR
 var result=FrogPlacement.arrival(world,expected,size,2)
 if result.is_empty():
  for candidate in world.recovery_points:
   result=FrogPlacement.arrival(world,candidate,size,2)
   if not result.is_empty():break
 return result

func _fail(reason:String):
 print("TRAVEL_FAILED "+reason)
 _discard_stage();busy=false;status="failed";progress=0;last_error=reason;message=reason
 changed.emit();game.hud.toast(reason);game._event("travel_failed",{"reason":reason,"place_id":current_id})

func _discard_stage():
 if is_instance_valid(staged):
  staged.set_collision_layers(0);game.remove_child(staged);staged.queue_free()
 staged=null

func state()->Dictionary:
 var item=place(current_id)
 return {"place_id":current_id,"place_name":item.get("name","Woodland pond"),"map_epoch":map_epoch,"geographic_anchor":item.get("anchor",{}),"travel_state":status,"travel_progress":progress,"world_stream":game.woodland.streaming_state()}

func _load_history():
 var path="user://travel_history.json"
 if not FileAccess.file_exists(path):return
 var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
 if parsed is Array:
  for id in parsed.slice(maxi(0,parsed.size()-50)):
   if id is String and not place(id).is_empty():history.append(id)

func _save_history():
 if not persist_history:return
 var file=FileAccess.open("user://travel_history.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(history)+"\n")
