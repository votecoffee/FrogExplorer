class_name TiledMeshWorld
extends LocalMeshWorld

# Each visit owns its detail resources. Texture paths are shared across tiles.
# The overview has no collision and never references the original full mesh.
var manifest:Dictionary
var game:Node3D
var overview:Node3D
var tiles={}
var resident={}
var pending={}
var headless_sources={}
var wanted={}
var pinned={}
var urgent={}
var layer=2
var active=false
var refresh_elapsed=0.0
var stream_error=""
var stalls=0
var peak_resident=0
var frames=0
var error_reported=false
var notice_after=0
const SOFT_LIMIT=96

func _ready():
 _configure_pack()
 var p=pack.spawn;spawn_point=Vector3(p[0],p[1],p[2])
 overview=packed_scene.instantiate();add_child(overview)
 for tile in manifest.tiles:tiles[Vector2i(int(tile.cell[0]),int(tile.cell[1]))]=tile
 for point in [spawn_point]+recovery_points:
  for cell in _region(point,24):pinned[cell]=true
 _refresh()

func activate():
 super.activate();active=true;_refresh()

func set_collision_layers(value:int,node:Node=self):
 layer=value;super.set_collision_layers(value,node)

func _region(point:Vector3,radius:float)->Array:
 var result=[];var size=float(manifest.tile_size)
 var low=Vector2i(floori((point.x-radius)/size),floori((point.z-radius)/size))
 var high=Vector2i(floori((point.x+radius)/size),floori((point.z+radius)/size))
 for x in range(low.x,high.x+1):
  for z in range(low.y,high.y+1):
   var cell=Vector2i(x,z)
   if tiles.has(cell):result.append(cell)
 return result

func _demand(point:Vector3,radius:float,priority:float):
 var size=float(manifest.tile_size)
 for cell in _region(point,radius):
  var center=Vector2((cell.x+.5)*size,(cell.y+.5)*size)
  var score=priority+center.distance_to(Vector2(point.x,point.z))
  wanted[cell]=minf(float(wanted.get(cell,INF)),score)

func _refresh():
 wanted.clear()
 for cell in pinned:wanted[cell]=-20000.0
 var now=Time.get_ticks_msec()
 for cell in urgent.keys():
  if urgent[cell]>now:wanted[cell]=-10000.0
  else:urgent.erase(cell)
 if active and game.party:
  for record in game.party.records:
   var pilot=record.slot.pilot
   var actor=record.slot.rides.body if record.slot.rides.active() else pilot
   if not is_instance_valid(actor):continue
   var radius=maxf(16.0,1.0*pilot.metrics.factor)
   _demand(actor.position,radius,-5000)
   _demand(actor.position+actor.velocity*1.5,radius,-4000)
   _demand(actor.position,float(manifest.detail_radius),10000)
 var ordered=wanted.keys();ordered.sort_custom(func(a,b):return wanted[a]<wanted[b])
 for i in range(SOFT_LIMIT,ordered.size()):
  if wanted[ordered[i]]>=0:wanted.erase(ordered[i])

func initial_ready()->bool:
 for cell in pinned:
  if not _ready_cell(cell):return false
 return true

func _ready_cell(cell:Vector2i)->bool:
 return resident.has(cell) and frames>=resident[cell].ready_frame

func surface_ready(point:Vector3,radius:float)->bool:
 var ready=true
 for cell in _region(point,radius):
  if not _ready_cell(cell):
   urgent[cell]=Time.get_ticks_msec()+2000;wanted[cell]=-10000.0;ready=false
 return ready

func allow_motion(body:CharacterBody3D,radius:float,delta:float)->bool:
 var next=body.position+body.velocity*delta
 var center=(body.position+next)*.5
 var extent=radius+Vector2(next.x-body.position.x,next.z-body.position.z).length()*.5+.04
 if surface_ready(center,extent):return true
 if active and Time.get_ticks_msec()>notice_after:
  game.party.tell("Loading nearby scenery...");notice_after=Time.get_ticks_msec()+4000
 stalls+=1;return false

func _physics_process(_delta):frames+=1

func _process(delta):
 refresh_elapsed+=delta
 if refresh_elapsed>.15:refresh_elapsed=0;_refresh()
 # Retire detail only after it has stayed outside every player's demand.
 var now=Time.get_ticks_msec()
 for cell in resident.keys():
  if wanted.has(cell):resident[cell].last_wanted=now
  elif now-int(resident[cell].last_wanted)>2000:
   var detail=resident[cell].node
   remove_child(detail);detail.queue_free();resident.erase(cell);collision_count-=1;_overview_visible(cell,true)
 # Integrate at most one tile per frame; baked shapes avoid synchronous mesh cooking.
 for cell in pending.keys():
  var path=pending[cell]
  var state=ResourceLoader.THREAD_LOAD_LOADED if headless_sources.has(cell) else ResourceLoader.load_threaded_get_status(path)
  if state==ResourceLoader.THREAD_LOAD_IN_PROGRESS:continue
  pending.erase(cell)
  if state!=ResourceLoader.THREAD_LOAD_LOADED:
   stream_error="Could not load nearby scenery: "+str(tiles[cell].id);break
  var source=(headless_sources[cell] if headless_sources.has(cell) else ResourceLoader.load_threaded_get(path)) as PackedScene
  headless_sources.erase(cell)
  if not source:stream_error="Invalid scenery tile: "+str(tiles[cell].id);break
  if not wanted.has(cell):break
  var detail=source.instantiate();add_child(detail);super.set_collision_layers(layer,detail)
  resident[cell]={"node":detail,"source":source,"ready_frame":frames+2,"last_wanted":now}
  collision_count+=1;peak_resident=maxi(peak_resident,resident.size());break
 for cell in resident:
  if _ready_cell(cell):_overview_visible(cell,false)
 if not stream_error.is_empty():
  if active and not error_reported:
   game.party.tell("Nearby scenery could not load. H returns to the pond.");error_reported=true
  return
 var queue=wanted.keys();queue.sort_custom(func(a,b):return wanted[a]<wanted[b])
 for cell in queue:
  if pending.size()>=2:break
  if resident.has(cell) or pending.has(cell):continue
  var path=manifest.folder+"/"+str(tiles[cell].scene)
  # Godot's dummy renderer has non-thread-safe RID owners (upstream #121949).
  # Headless servers serialize one bounded tile per frame; interactive clients
  # keep background IO and integrate nodes only on the main thread.
  if DisplayServer.get_name()=="headless":
   headless_sources[cell]=load(path);pending[cell]=path;break
  var error=ResourceLoader.load_threaded_request(path,"PackedScene")
  if error!=OK:stream_error="Could not request scenery tile: "+str(tiles[cell].id);break
  pending[cell]=path

func _overview_visible(cell:Vector2i,value:bool):
 var node=overview.get_node_or_null(NodePath(str(tiles[cell].id)))
 if node:node.visible=value

func _exit_tree():
 # A cancelled visit still consumes its bounded outstanding requests. No stale
 # resource task is left behind to race the next visit to this pack.
 for cell in pending:
  if not headless_sources.has(cell):ResourceLoader.load_threaded_get(pending[cell])
 pending.clear();headless_sources.clear()

func streaming_state()->Dictionary:
 var triangles=0
 for cell in resident:triangles+=int(tiles[cell].triangles)
 return {"mode":"tiles","resident":resident.size(),"total":tiles.size(),"pending":pending.size(),"peak_resident":peak_resident,"detail_triangles":triangles,"overview_triangles":manifest.overview_triangles,"stalls":stalls,"error":stream_error}
