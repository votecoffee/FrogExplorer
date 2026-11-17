extends SceneTree

# Self-contained collision/streaming checks; no downloaded scenery is needed.
var game
var checks=[]
var failures=[]
func _initialize():run.call_deferred()
func wait(seconds:float):await create_timer(seconds).timeout
func check(ok:bool,text:String):
 checks.append({"test":text,"passed":ok})
 if not ok:failures.append(text)
 print(("PASS " if ok else "FAIL ")+text)

func ready_at(world:TiledMeshWorld,point:Vector3,radius:float)->bool:
 var end=Time.get_ticks_msec()+10000
 while not world.surface_ready(point,radius) and Time.get_ticks_msec()<end:await process_frame
 return world.surface_ready(point,radius)

func fixture()->Dictionary:
 var folder="user://stream_test_"+str(Time.get_ticks_usec())
 DirAccess.make_dir_recursive_absolute(folder)
 var material=StandardMaterial3D.new();material.albedo_color=Color(.3,.5,.2)
 var plane=PlaneMesh.new();plane.size=Vector2(16,16);plane.material=material
 var overview=Node3D.new();var tiles=[]
 for x in range(10):
  for z in range(2):
   var id="x%d_z%d"%[x,z];var tile=Node3D.new();tile.name=id;tile.position=Vector3(x*16,0,z*16)
   var mesh=MeshInstance3D.new();mesh.mesh=plane;mesh.position=Vector3(8,0,8);tile.add_child(mesh);mesh.owner=tile
   var body=StaticBody3D.new();body.collision_layer=2;body.collision_mask=0;tile.add_child(body);body.owner=tile
   var collider=CollisionShape3D.new();collider.shape=plane.create_trimesh_shape();collider.position=mesh.position;body.add_child(collider);collider.owner=tile
   var scene=PackedScene.new();scene.pack(tile);ResourceSaver.save(scene,folder+"/"+id+".tscn");tile.free()
   var far=MeshInstance3D.new();far.name=id;far.mesh=plane;far.position=Vector3(x*16+8,0,z*16+8);overview.add_child(far);far.owner=overview
   tiles.append({"id":id,"cell":[x,z],"origin":[x*16,0,z*16],"scene":id+".tscn","triangles":2})
 var far_scene=PackedScene.new();far_scene.pack(overview);overview.free()
 return {"scene":far_scene,"manifest":{"folder":folder,"tile_size":16,"tiles":tiles,"overview_triangles":40,"detail_radius":20}}

func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await wait(.2)
 var data=fixture();var world=TiledMeshWorld.new();world.game=game;world.manifest=data.manifest;world.packed_scene=data.scene
 world.pack={"spawn":[4,.04,4],"bounds":[0,0,160,32],"spawn_candidates":[],"camera_far":200}
 world.staging=true;game.add_child(world)
 var end=Time.get_ticks_msec()+10000
 while not world.initial_ready() and Time.get_ticks_msec()<end:await process_frame
 check(world.initial_ready(),"Arrival collision is registered before a tiled world becomes active")
 var arrival=FrogPlacement.arrival(world,world.spawn_point,1,2)
 check(not arrival.is_empty(),"Isolated staging collision supports a capsule-clear arrival")
 var old=game.woodland;old.set_collision_layers(0);game.remove_child(old);old.queue_free()
 game.woodland=world;game.pilot.woodland=world;game.camera_rig.woodland=world;world.set_collision_layers(1);world.activate()
 game.pilot.arrive_at_default_size(arrival.get("position",world.spawn_point));await wait(.3)
 check(game.pilot.is_on_floor(),"Frog stands on streamed collision after activation")
 check(world.resident.size()<world.tiles.size(),"Distant detail remains unloaded")
 check(not world.overview.find_children("*","CollisionObject3D",true,false).size(),"Far overview contributes no collision")
 var pilot=game.pilot
 # Stop the IO scheduler to make a reproducible slow-disk boundary.
 world.set_process(false);pilot.position=Vector3(132,2,4);pilot.velocity=Vector3.ZERO
 var frozen=pilot.position;await wait(.25)
 check(pilot.position.is_equal_approx(frozen) and world.stalls>0,"Frog cannot fall or move into a tile whose collision is not ready")
 check(not pilot._fits_size(16),"Growth cannot claim clearance from an unloaded tile")
 check(not game.rides._fits("CAR",pilot.position,0),"Vehicle boarding cannot claim clearance from an unloaded tile")
 world.set_process(true)
 check(await ready_at(world,pilot.position,3),"Deferred frontier demand loads when IO resumes")
 await wait(.9);check(pilot.is_on_floor(),"Frog resumes and lands after collision becomes ready")
 # Sweep a small capsule physically across a real cell boundary.
 await ready_at(world,Vector3(128,0,4),3)
 pilot.position=Vector3(127.7,.035,4);pilot.velocity=Vector3.ZERO;await wait(.15)
 game.controls.remote_move=Vector2(1,0);game.controls.remote_until=Time.get_ticks_msec()/1000.0+3
 await wait(1.3);game.controls.neutralize();await wait(.2)
 check(pilot.position.x>128 and pilot.is_on_floor(),"Walking across a clipped tile seam keeps floor contact")
 check(pilot.try_resize(.25) and pilot.try_resize(16),"Minimum and maximum capsules fit a loaded, clear tiled floor")
 pilot.try_resize(1)
 # A remote actor is authoritative on the host and must retain its own region.
 var remote=game.party.add_record(2,0,false);remote.slot.pilot.paused=true;remote.slot.pilot.position=Vector3(68,.035,20)
 await wait(.5)
 check(await ready_at(world,remote.slot.pilot.position,1),"A remote frog's separate region receives collision")
 await wait(2.8)
 check(world.resident.has(Vector2i(4,1)),"Remote frog demand survives the unload grace period")
 check(not world.resident.has(Vector2i(2,0)),"Unvisited detail outside all player regions stays absent")
 var far_cell=Vector2i(8,0);pilot.paused=true;pilot.position=world.spawn_point
 await wait(3)
 check(not world.resident.has(far_cell),"Old detail unloads after every frog leaves")
 check(world.resident.has(Vector2i(0,0)),"Arrival tiles stay pinned for recovery")
 pilot.position=Vector3(132,2,4)
 check(await ready_at(world,pilot.position,1),"Returning to an evicted region reloads its collision")
 check(WorldTiles.safe_relative("detail/tile.tscn") and not WorldTiles.safe_relative("../other.tscn") and not WorldTiles.safe_relative("C:/other.tscn"),"Manifest paths cannot escape their tile pack")
 var report={"checks":checks,"failures":failures,"stream":world.streaming_state()}
 var file=FileAccess.open("res://../state/stream_smoke.json",FileAccess.WRITE);file.store_string(JSON.stringify(report," ")+"\n");file.close()
 print("STREAM_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
