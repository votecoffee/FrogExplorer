extends SceneTree

# Run with --headless --script res://scripts/city_smoke.gd -- --test-session.
# Uses the real scene packs and physics; no window input or screen capture.
const IDS=["rochester_high_falls","washington_national_mall","holland_downtown","norfolk_waterfront","lynchburg_riverfront"]
var game
var checks=[]
var failures=[]
var measurements=[]

func _initialize():run.call_deferred()

func check(value:bool,text:String):
 checks.append({"test":text,"passed":value})
 if not value:failures.append(text)
 print(("PASS " if value else "FAIL ")+text)

func wait(seconds:float):await create_timer(seconds).timeout

func move(value:Vector2,aux=Vector2.ZERO):
 game.controls.remote_move=value;game.controls.remote_aux=aux;game.controls.remote_until=Time.get_ticks_msec()/1000.0+4

func stop():
 game.controls.remote_until=0;game.controls.velocity_until=0;game.controls.size_until=0

func trip(id:String):
 game.travel.request(id)
 var deadline=Time.get_ticks_msec()+15000
 while game.travel.busy and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.travel.busy and game.travel.current_id==id,"Arrives at "+id)
 await wait(.35)

func recover():
 stop();game.rides.clear_for_travel();game.pilot.reset_position();await wait(.3)

func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await wait(.3)
 var t:WorldTravel=game.travel;var p:FrogPilot=game.pilot;var rides:ExplorerRides=game.rides
 check(not t.persist_history,"City test leaves player travel history untouched")
 check(t.available_places().size()==t.catalog.size(),"All catalog destinations are available on Windows")
 game.travel_menu.open();await wait(.1)
 var menu=game.travel_menu
 check(menu.panel.get_global_rect().position.y>=0 and menu.panel.get_global_rect().end.y<=root.get_visible_rect().size.y,"Places panel fits the viewport with all installed destinations")
 menu.selected=menu.buttons.size()-1;menu._highlight();await wait(.1)
 check(menu.scroll.scroll_vertical>0,"Gamepad/keyboard selection scrolls the last place-menu row into view")
 menu.close()
 var original_species=p.species
 for id in IDS:
  var item=t.place(id)
  check(not item.is_empty() and t.unavailable(item).is_empty(),id+": installed catalog entry is ready")
  p.try_resize(4)
  await trip(id)
  if t.current_id!=id:continue
  check(is_equal_approx(p.metrics.factor,1) and p.species==original_species,id+": arrival resets size and preserves frog")
  check(p.is_on_floor() and p.position.is_finite(),id+": capsule settles on actual terrain collision")
  check(game.woodland is LocalMeshWorld and game.woodland.collision_count==6,id+": terrain and five building groups have collision")
  check(t.state().geographic_anchor.horizontal_crs.begins_with("EPSG:326"),id+": UTM geographic anchor is published")
  check(game.woodland.travel_bounds.size.x>=950,id+": city movement extends beyond the pond bounds")
  var origin=p.position
  game.camera_rig.view_mode=0;game.camera_rig.initialized=false
  move(Vector2(0,-1));await wait(.45);stop();await wait(.15)
  check(Vector2(p.position.x-origin.x,p.position.z-origin.z).length()>.1,id+": walking advances across terrain")
  p.request_action("jump");await wait(.18)
  check(not p.is_on_floor() and p.position.y>origin.y+.05,id+": jumping leaves the ground")
  await wait(.8);await recover()
  check(p.try_resize(.25) and is_equal_approx(p.metrics.factor,.25),id+": minimum size fits at arrival")
  check(p.try_resize(16) and is_equal_approx(p.metrics.factor,16),id+": maximum size fits at arrival")
  p.try_resize(1);await recover()
  rides.request("BALLOON");await wait(.15)
  check(rides.kind=="BALLOON",id+": balloon can board at arrival")
  if rides.kind=="BALLOON":
   var start=rides.body.position
   move(Vector2.ZERO,Vector2(1,-1));await wait(.7);stop()
   check(rides.body.position.y>start.y+.2 and (rides.body.position-start).length()>.4,id+": right stick raises and strafes balloon")
   for view in range(3):
    game.camera_rig.view_mode=view;game.camera_rig.initialized=false;await wait(.04)
    check(game.camera_rig.global_position.is_finite(),id+": camera %d is valid"%view)
   p.request_action("jump");await wait(.05)
   check(rides.kind=="PARACHUTE",id+": jumping from balloon deploys parachute")
  await recover()
  rides.request("CAR");await wait(.15)
  check(rides.kind=="CAR",id+": convertible can board on dry ground")
  if rides.kind=="CAR":
   var start=rides.body.position
   move(Vector2(0,-1));await wait(.6);stop()
   check((rides.body.position-start).length()>.4,id+": convertible accelerates across terrain")
   p.request_action("jump");await wait(.05)
   check(rides.kind=="COAST",id+": jumping removes car and retains momentum")
  await recover()
  # Reference source footprint edges so intervening hills cannot mask the wall.
  var facade=false
  var prepared=JSON.parse_string(FileAccess.get_file_as_string("res://../data/world_sources/"+id+"/prepared.json"))
  for building in prepared.buildings.slice(0,20):
   var a=building.rings[0][0];var b=building.rings[0][1]
   var midpoint=Vector3((a[0]+b[0])/2,(building.base+building.roof-building.roof_height)/2,-(a[1]+b[1])/2)
   var direction=Vector3(-(b[1]-a[1]),0,-(b[0]-a[0])).normalized()
   var query=PhysicsRayQueryParameters3D.create(midpoint+direction,midpoint-direction,1)
   var hit=game.woodland.get_world_3d().direct_space_state.intersect_ray(query)
   if not hit.is_empty() and absf(hit.normal.y)<.1:facade=true;break
  check(facade,id+": actual building facades block physics rays")
  measurements.append({"id":id,"spawn":str(p.position),"collision_groups":game.woodland.collision_count,"facade_hit":facade,"scene_sha256":FileAccess.get_sha256(item.scene),"anchor":item.anchor})
  p.try_resize(2)
  # Travel must discard any current ride and restore default size in the next pack.
  rides.request("BALLOON");await wait(.05)
 await trip("home_woodland_pond")
 check(rides.kind=="FOOT" and is_equal_approx(p.metrics.factor,1),"Return home clears ride and restores default size")
 check(p.is_on_floor() and game.woodland.trees.size()>=20,"Pond floor and climbing semantics return")
 var ids=[]
 for item in t.available_places():
  if item.get("random_eligible",false) and item.get("category","")=="city":ids.append(item.id)
 t.history.assign(ids.slice(0,ids.size()-1));t.category="city"
 var recent=t.history.slice(maxi(0,t.history.size()-10));var selected=t.choose_random()
 check(ids.has(selected) and not recent.has(selected),"Random travel prefers cities absent from the last ten visits")
 var report={"checks":checks,"failures":failures,"measurements":measurements,"scope":"Windows headless actual city meshes, physics and injected controls. Offline Blender previews inspected separately. Rendered game FPS, physical F710, Linux and Pi remain untested."}
 var file=FileAccess.open(ProjectSettings.globalize_path("res://../state/city_smoke.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("CITY_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
