extends SceneTree

var game
var checks=[]
var failures=[]
func _initialize():run.call_deferred()
func wait(seconds):await create_timer(seconds).timeout
func check(value,text):
 checks.append({"test":text,"passed":bool(value)})
 if not value:failures.append(text)
 print(("PASS " if value else "FAIL ")+text)
func ready(world,cell,level):
 var end=Time.get_ticks_msec()+6000
 while Time.get_ticks_msec()<end:
  if world.resident.has(cell) and int(world.resident[cell].lod)==level and world.frames>=world.resident[cell].ready_frame:return true
  await process_frame
 return false

func fixture():
 var folder="user://lod_test_"+str(Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
 var fine=PlaneMesh.new();fine.size=Vector2(16,16);var green=StandardMaterial3D.new();green.albedo_color=Color(.2,.6,.2);fine.material=green
 var coarse=PlaneMesh.new();coarse.size=Vector2(16,16);var blue=StandardMaterial3D.new();blue.albedo_color=Color(.2,.3,.6);coarse.material=blue
 var overview=Node3D.new();var tiles=[]
 for x in range(10):
  for z in range(2):
   var id="x%d_z%d"%[x,z];var lods=[]
   for level in range(2):
    var node=Node3D.new();node.name=id;node.position=Vector3(x*16,0,z*16)
    var mesh=MeshInstance3D.new();mesh.mesh=fine if level==0 else coarse;mesh.position=Vector3(8,0,8);node.add_child(mesh);mesh.owner=node
    if level==0:
     var body=StaticBody3D.new();body.collision_layer=2;body.collision_mask=0;node.add_child(body);body.owner=node
     var shape=CollisionShape3D.new();shape.shape=fine.create_trimesh_shape();shape.position=mesh.position;body.add_child(shape);shape.owner=node
    var path=id+"_lod%d.tscn"%level;var scene=PackedScene.new();scene.pack(node);ResourceSaver.save(scene,folder+"/"+path);node.free()
    lods.append({"scene":path,"triangles":2,"collision":level==0})
   var far=MeshInstance3D.new();far.name=id;far.mesh=coarse;far.position=Vector3(x*16+8,0,z*16+8);overview.add_child(far);far.owner=overview
   tiles.append({"id":id,"cell":[x,z],"origin":[x*16,0,z*16],"scene":lods[0].scene,"triangles":2,"lods":lods})
 var scene=PackedScene.new();scene.pack(overview);overview.free()
 return {"scene":scene,"manifest":{"folder":folder,"tile_size":16,"tiles":tiles,"overview_triangles":40,"detail_radius":64,"lod_distances":[16,64]}}

func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await wait(.2)
 var data=fixture();var world=TiledMeshWorld.new();world.game=game;world.manifest=data.manifest;world.packed_scene=data.scene
 world.pack={"spawn":[4,.04,4],"bounds":[0,0,160,32],"spawn_candidates":[],"camera_far":200};world.staging=true;game.add_child(world)
 check(await ready(world,Vector2i(0,0),0),"Multi-LOD arrival loads finest collision")
 var arrival=FrogPlacement.arrival(world,world.spawn_point,1,2)
 check(not arrival.is_empty(),"Finest staging mesh supports a clear arrival")
 var old=game.woodland;old.set_collision_layers(0);game.remove_child(old);old.queue_free()
 game.woodland=world;game.pilot.woodland=world;game.camera_rig.woodland=world;world.set_collision_layers(1);world.activate()
 game.pilot.arrive_at_default_size(arrival.get("position",world.spawn_point));await wait(.4)
 var cell=Vector2i(3,0)
 check(await ready(world,cell,1),"Distant cells use a coarser source LOD")
 check(world.resident[cell].node.find_children("*","CollisionObject3D",true,false).is_empty(),"Coarse visual LOD has no accidental floor collision")
 check(world.layer==1,"Loading visual-only scenery preserves the world's active collision layer")
 check(world.streaming_state().lod_cells.has(1),"Streaming diagnostics report resident LODs")
 var pilot=game.pilot;pilot.paused=true;world.set_process(false);pilot.position=Vector3(52,2,4)
 var previous=world.resident[cell].node
 check(not world.surface_ready(pilot.position,1),"A coarse visual cell cannot claim precise ground readiness")
 check(not game.rides._fits("CAR",pilot.position,0),"Vehicle boarding waits for the finest collision LOD")
 check(is_instance_valid(previous) and previous.is_inside_tree(),"Existing scenery remains visible while finer data is pending")
 world.set_process(true)
 check(await ready(world,cell,0),"Approaching a coarse cell upgrades to the finest source mesh")
 pilot.paused=false;await wait(.9)
 check(pilot.is_on_floor(),"Frog lands on the newly upgraded collision")
 pilot.paused=true;pilot.position=world.spawn_point;world._refresh();await wait(2.8)
 check(await ready(world,cell,1),"Leaving a cell releases fine geometry and restores coarse detail")
 check(world.resident[cell].node.find_children("*","CollisionObject3D",true,false).is_empty(),"Downgrading removes the departed cell's fine collision")
 var remote=game.party.add_record(2,0,false);remote.slot.pilot.paused=true;remote.slot.pilot.position=Vector3(52,.035,4)
 check(await ready(world,cell,0),"Remote player demand also upgrades fine collision")
 await wait(2.8)
 check(int(world.resident[cell].lod)==0,"A remote frog retains its detailed region")
 check(world.overview.find_children("*","CollisionObject3D",true,false).is_empty(),"The distant overview remains non-colliding")
 var report={"checks":checks,"failures":failures,"stream":world.streaming_state(),"scope":"Windows headless LOD selection and real collision; no rendered FPS or Pi measurement."}
 var file=FileAccess.open("res://../state/lod_smoke.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("LOD_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}));await game.shutdown(0 if failures.is_empty() else 1)
