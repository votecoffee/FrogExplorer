extends SceneTree

# Actual exported geometry and injected controls; no desktop capture/input.
const IDS=["tokyo_imperial_palace","shanghai_lujiazui","berlin_teufelsberg","moscow_andronikov","montreal_sainte_elisabeth","mexico_city_cathedral"]
var game
var checks=[]
var failures=[]
var measurements=[]
func _initialize():run.call_deferred()
func wait(seconds:float):await create_timer(seconds).timeout
func check(value:bool,text:String):
 checks.append({"test":text,"passed":value})
 if not value:failures.append(text)
 print(("PASS " if value else "FAIL ")+text)
func move(value:Vector2,aux=Vector2.ZERO):
 game.controls.remote_move=value;game.controls.remote_aux=aux;game.controls.remote_until=Time.get_ticks_msec()/1000.0+3
func stop():game.controls.neutralize()
func recover():
 stop();game.rides.clear_for_travel();game.pilot.reset_position();await wait(.3)
func trip(id:String):
 game.travel.request(id);var deadline=Time.get_ticks_msec()+20000
 while game.travel.busy and Time.get_ticks_msec()<deadline:await process_frame
 await wait(.4);check(game.travel.current_id==id,"Arrives at "+id)
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await wait(.3)
 var t:WorldTravel=game.travel;var p:FrogPilot=game.pilot;var rides:ExplorerRides=game.rides
 game.party.records[0].device=40;game.controls.assign_device(40)
 for device in [41,42,43]:
  var event=InputEventJoypadButton.new();event.device=device;event.button_index=JOY_BUTTON_START;event.pressed=true;Input.parse_input_event(event)
 await wait(.3)
 check(game.party.local_records().size()==4,"Four local frogs join before international city travel")
 check(t.available_places().size()==t.catalog.size(),"Every catalog destination is installed and available")
 var full_catalog=t.catalog.duplicate()
 t.catalog.assign(full_catalog.filter(func(item):return item.id in IDS or item.id=="home_woodland_pond"))
 t.category="city"
 check(t.choose_random() in IDS,"City random selection includes the new international destinations")
 t.catalog.assign(full_catalog)
 var countries=[]
 for id in IDS:countries.append(t.place(id).get("country",""))
 countries.sort()
 check(countries==["CA","CN","DE","JP","MX","RU"],"Six new city entries cover all six requested countries")
 game.travel_menu.open();await wait(.05)
 check(game.travel_menu.buttons.size()==t.catalog.size()+3,"Scrollable places list includes all destinations and category controls")
 game.travel_menu.close()
 for id in IDS:
  var item=t.place(id)
  check(t.unavailable(item).is_empty() and item.category=="city",id+": ready city-category pack")
  p.try_resize(2);rides.request("BALLOON");await wait(.05)
  await trip(id)
  if t.current_id!=id:continue
  var w:LocalMeshWorld=game.woodland
  check(w.collision_count>0,id+": exported mesh has collision")
  var group_ok=true
  for record in game.party.records:
   var frog=record.slot.pilot
   group_ok=group_ok and frog.is_on_floor() and frog.woodland==w and is_equal_approx(frog.metrics.factor,1) and record.slot.rides.kind=="FOOT"
  check(group_ok,id+": all four frogs arrive grounded at default size without rides")
  check(t.state().geographic_anchor.horizontal_crs=="LOCAL_MODEL" and not item.anchor.georeferenced,id+": local frame honestly declares missing survey georeferencing")
  check(w.recovery_floor<float(item.vertical_bounds[0]) and w.surface_bottom<float(item.vertical_bounds[0]) and w.surface_top>float(item.vertical_bounds[1]) and w.flight_ceiling>float(item.vertical_bounds[1])+50,id+": height limits cover the source cut and balloon clearance")
  check(absf(w.ground_height(p.position.x,p.position.z)-p.position.y)<.12,id+": ground queries agree with actual arrival collision")
  check(not w.in_water(p.position) and w.trees.is_empty(),id+": visible scenery does not invent water or climb volumes")
  var origin=p.position
  game.camera_rig.view_mode=0;game.camera_rig.initialized=false
  move(Vector2(0,-1));await wait(.4);stop();await wait(.1)
  check(Vector2(p.position.x-origin.x,p.position.z-origin.z).length()>.09,id+": walking advances on source geometry")
  var y=p.position.y;p.request_action("jump");await wait(.15)
  check(p.position.y>y+.06 and not p.is_on_floor(),id+": jumping leaves source ground")
  await wait(.8);await recover()
  check(p.try_resize(.25) and is_equal_approx(p.metrics.factor,.25),id+": small size fits the checked arrival")
  var grew=p.try_resize(2)
  check((grew and is_equal_approx(p.metrics.factor,2)) or (not grew and p.metrics.factor>=.25 and p.metrics.factor<2 and p.resize_blocked and p._fits_size(p.metrics.factor)),id+": growth respects actual architecture and scan clearance")
  p.try_resize(1);await recover()
  rides.request("BALLOON");await wait(.15)
  check(rides.kind=="BALLOON",id+": tethered balloon boards at arrival")
  if rides.kind=="BALLOON":
   var start=rides.body.position
   move(Vector2.ZERO,Vector2(1,-1));await wait(.6);stop()
   check(rides.body.position.y>start.y+.15 and rides.body.position.distance_to(start)>.3,id+": right stick controls balloon altitude and strafe")
   for view in range(3):
    game.camera_rig.view_mode=view;game.camera_rig.initialized=false;await wait(.04)
    check(game.camera_rig.global_position.is_finite(),id+": camera %d remains valid"%view)
   p.request_action("jump");await wait(.05)
   check(rides.kind=="PARACHUTE",id+": balloon jump deploys parachute")
  await recover();rides.request("CAR");await wait(.15)
  check(rides.kind=="CAR",id+": convertible boards on checked dry ground")
  if rides.kind=="CAR":
   var start=rides.body.position
   move(Vector2(0,-1));await wait(.35);stop()
   check(rides.body.position.distance_to(start)>.15,id+": car advances across the arrival surface")
   p.request_action("jump");await wait(.05)
   check(rides.kind=="COAST",id+": car jump removes vehicle and coasts")
  await recover()
  p.position.y=w.recovery_floor-1;await wait(.25)
  check(p.position.distance_to(w.spawn_point)<.3 and p.is_on_floor(),id+": falling below source cut recovers safely")
  var source_hash=FileAccess.get_sha256(item.scene) if FileAccess.file_exists(item.scene) else WorldTiles.manifest(item).source_sha256
  measurements.append({"id":id,"spawn":str(w.spawn_point),"collision_groups":w.collision_count,"vertical_bounds":item.vertical_bounds,"recovery_floor":w.recovery_floor,"flight_ceiling":w.flight_ceiling,"scene_sha256":source_hash})
 await trip("home_woodland_pond")
 check(game.woodland.recovery_floor==-60 and game.woodland.flight_ceiling==120,"Pond retains its original height limits")
 check(game.pilot.is_on_floor() and game.woodland.trees.size()>=20,"Returning home restores pond collision and climbing trees")
 var report={"checks":checks,"failures":failures,"measurements":measurements,"scope":"Windows headless actual international city meshes, four local frogs and injected controls. Offline Blender previews inspected separately. Physical controller, rendered game FPS, Linux and Pi untested."}
 var path=ProjectSettings.globalize_path("res://../state")
 DirAccess.make_dir_recursive_absolute(path)
 var file=FileAccess.open(path+"/world_city_smoke.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 else:failures.append("Cannot write report")
 print("WORLD_CITY_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
