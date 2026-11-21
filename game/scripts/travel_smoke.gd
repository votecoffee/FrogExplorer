extends Node

var checks=[]
var failures=[]
func check(condition:bool,text:String):
 checks.append({"test":text,"passed":condition})
 if not condition:failures.append(text)
 print(("PASS " if condition else "FAIL ")+text)

func wait(seconds:float):await get_tree().create_timer(seconds).timeout

func finish_trip(travel:WorldTravel):
 var deadline=Time.get_ticks_msec()+15000
 while travel.busy and Time.get_ticks_msec()<deadline:await get_tree().process_frame
 check(not travel.busy,"Travel completes within 15 seconds")
 await wait(.25)

func run(game):
 var t:WorldTravel=game.travel;var p:FrogPilot=game.pilot
 if t.profile()!="windows":
  push_error("Travel smoke currently requires the Windows-qualified Helsinki pack.");await game.shutdown(1);return
 check(t.current_id=="home_woodland_pond","Starts at the home pond")
 check(t.catalog.filter(func(item):return item.get("distribution","")!="optional_download" and not t.unavailable(item).is_empty()).is_empty(),"Every bundled catalog entry is ready on Windows")
 check(ExplorerControls.BUTTONS[JOY_BUTTON_BACK]=="travel_random" and ExplorerControls.KEYS[KEY_T]=="travel_random","Back / Select and T request travel")
 check(ExplorerControls.KEYS[KEY_H]=="travel_home" and ExplorerControls.KEYS[KEY_N]=="travel_menu","Keyboard can return home and open places")
 t.category="nature";check(t.choose_random().is_empty(),"Uninstalled nature candidates are excluded")
 var full_catalog=t.catalog.duplicate()
 t.catalog.assign(full_catalog.filter(func(item):return item.id in ["home_woodland_pond","helsinki_senate_square"]))
 t.category="any";t.history.assign(["helsinki_senate_square"])
 check(t.choose_random()=="helsinki_senate_square","Small installed pool shortens the recent-history exclusion")
 t.catalog.assign(full_catalog)
 p.try_resize(2);var before_size=p.metrics.factor
 var old=game.woodland;var epoch=t.map_epoch
 t.request("helsinki_senate_square");t.cancel();await wait(.05)
 check(game.woodland==old and t.current_id=="home_woodland_pond" and t.map_epoch==epoch and is_equal_approx(p.metrics.factor,before_size),"Cancelling before load preserves the old world and epoch")
 var cancel_at_collision=func():
  if is_instance_valid(t.staged):
   check(game.woodland==old and not p.paused,"The current world remains playable while a pack prepares")
   t.cancel()
   check(game.woodland==old and not is_instance_valid(t.staged) and is_equal_approx(p.metrics.factor,before_size),"Cancelling prepared collision removes only the incoming world")
 t.changed.connect(cancel_at_collision)
 t.request("helsinki_senate_square")
 while t.busy:await get_tree().process_frame
 t.changed.disconnect(cancel_at_collision);await wait(.05)
 p.select_species(4);p.flies_caught=7;game.camera_rig.view_mode=1
 var started=game.clock
 t.request("helsinki_senate_square");await finish_trip(t)
 check(t.current_id=="helsinki_senate_square" and game.woodland is LocalMeshWorld,"Arrives in the real Helsinki mesh pack")
 check(is_equal_approx(p.metrics.factor,1),"Successful arrival resets size after preparing the old world at 2x")
 check(p.is_on_floor() and absf(p.position.y)<.15,"Arrival capsule settles on checked mesh collision")
 check(p.species==4 and p.flies_caught==7 and game.camera_rig.view_mode==1,"Species, score and camera survive travel")
 check(game.clock>started and t.map_epoch==epoch+1,"Clock continues and map epoch changes exactly once")
 check(game.woodland.trees.is_empty() and not game.woodland.in_water(Vector3.ZERO),"City scan does not invent climbable trunks or water volumes")
 check(not game.pond_ambience_active and (game.ambience.stream == null or game.ambience.stream_paused),"City travel pauses pond ambience")
 check(game.woodland.collision_count>0,"Loaded world geometry has registered collision")
 var source=t.state().geographic_anchor
 check(source.horizontal_crs=="EPSG:3879" and source.source_srs=="EPSG:3879+5773","Geographic anchor retains the archive's declared CRS and vertical datum")
 var random_id=t.choose_random()
 check(not random_id.is_empty() and random_id not in ["helsinki_senate_square","home_woodland_pond"],"Random travel avoids the current place and excludes the home pond")
 # Exercise movement outside the old pond clamp and recovery on actual scan.
 p.position=Vector3(20,game.woodland.ground_height(20,0)+.04,0);p.velocity=Vector3.ZERO;await wait(.25)
 check(p.position.x>19.9 and p.is_on_floor(),"City movement uses pack bounds rather than the pond's 10.5 m clamp")
 p.reset_position();await wait(.2)
 p.try_resize(4)
 var city=game.woodland;var city_position=p.position;epoch=t.map_epoch
 t.request("not_installed");await wait(.05)
 check(t.status=="failed" and game.woodland==city and t.map_epoch==epoch and is_equal_approx(p.metrics.factor,4),"Unknown place fails without changing world or epoch")
 var broken=t.place("helsinki_senate_square").duplicate(true);broken.id="missing_test";broken.scene="res://assets/worlds/missing.glb";t.catalog.append(broken)
 broken.erase("tile_manifest") # Exercise a genuinely missing whole-scene pack.
 t.request("missing_test");await wait(.05)
 check(t.last_error.contains("missing") and game.woodland==city and is_equal_approx(p.metrics.factor,4),"Missing pack fails before replacing the current world")
 var unsupported=broken.duplicate(true);unsupported.id="size_test";unsupported.scene=t.place("helsinki_senate_square").scene;unsupported.size_range=[2,4];t.catalog.append(unsupported)
 unsupported.tile_manifest=t.place("helsinki_senate_square").tile_manifest
 t.request("size_test");await wait(.05)
 check(t.last_error.contains("size") and game.woodland==city,"Unsupported default arrival size is rejected without changing current size")
 var unsafe=unsupported.duplicate(true);unsafe.id="unsafe_test";unsafe.size_range=[1,1];unsafe.spawn=[0,500,0];unsafe.spawn_candidates=[];t.catalog.append(unsafe)
 t.request("unsafe_test");await finish_trip(t)
 check(t.status=="failed" and game.woodland==city and t.map_epoch==epoch and p.is_on_floor() and is_equal_approx(p.metrics.factor,4),"Missing arrival ground preserves the current world, collision and epoch")
 p.try_resize(.25)
 var blocked=unsafe.duplicate(true);blocked.id="blocked_test";blocked.spawn=[0,0,0];t.catalog.append(blocked)
 var add_obstacle=func():
  if is_instance_valid(t.staged) and t.staged is LocalMeshWorld and t.staged.pack.id=="blocked_test":
   var body=StaticBody3D.new();body.collision_layer=2;body.position=Vector3(.13,.4,0)
   var collision=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(.1,1,1);collision.shape=shape;body.add_child(collision);t.staged.add_child(body)
 t.changed.connect(add_obstacle);t.request("blocked_test");await finish_trip(t);t.changed.disconnect(add_obstacle)
 check(t.status=="failed" and game.woodland==city and t.map_epoch==epoch and is_equal_approx(p.metrics.factor,.25),"Arrival checks the default capsule even when the current frog is smaller")
 p.try_resize(4)
 var baseline_only=t.place("helsinki_senate_square").duplicate(true);baseline_only.id="baseline_test";baseline_only.size_range=[1,1];t.catalog.append(baseline_only)
 check(t.unavailable(baseline_only).is_empty(),"A default-size destination accepts travel from a larger frog")
 t.request("baseline_test");await finish_trip(t)
 check(t.current_id=="baseline_test" and is_equal_approx(p.metrics.factor,1),"A default-only pack validates and receives a 1x frog")
 t.request("helsinki_senate_square");await finish_trip(t)
 t.catalog=t.catalog.filter(func(item):return not str(item.id).ends_with("_test"))
 game.travel_menu.open();check(p.paused and game.travel_menu.buttons.size()>=5,"Places menu pauses movement and offers installed destinations")
 game.travel_menu.handle_action("help");check(not p.paused and not game.travel_menu.visible,"Closing places restores the previous pause state")
 p.try_resize(4);game.controls.device=42
 var held=InputEventJoypadMotion.new();held.device=42;held.axis=JOY_AXIS_TRIGGER_LEFT;held.axis_value=1;Input.parse_input_event(held)
 t.request("home_woodland_pond");await finish_trip(t)
 check(is_equal_approx(p.metrics.factor,1),"Holding LT through travel cannot undo the default-size arrival")
 held.axis_value=0;Input.parse_input_event(held);await wait(.05)
 held.axis_value=1;Input.parse_input_event(held);await wait(.12)
 check(p.metrics.factor>1.04,"Releasing and pressing LT after travel resumes normal growing")
 held.axis_value=0;Input.parse_input_event(held);game.controls._find_device()
 check(t.current_id=="home_woodland_pond" and p.is_on_floor() and game.woodland.trees.size()>=20,"Return home rebuilds the pond, collision and tree semantics")
 check(game.pond_ambience_active and (game.ambience.stream == null or not game.ambience.stream_paused) and p.species==4 and p.flies_caught==7,"Returning home restores ambience and preserves the chosen frog and score")
 check(t.history.back()=="home_woodland_pond" and t.history.has("helsinki_senate_square"),"Travel history records successful arrivals")
 game.controls.accept_remote({"kind":"travel","place_id":"helsinki_senate_square"});await wait(.1);await finish_trip(t)
 check(t.current_id=="helsinki_senate_square","Named protocol travel reaches the requested place")
 game.controls.accept_remote({"kind":"action","action":"travel_home"});await wait(.1);await finish_trip(t)
 check(t.current_id=="home_woodland_pond","Protocol return-home action works")
 var report={"checks":checks,"failures":failures,"scope":"Windows headless Godot physics and injected input/protocol; physical F710, rendered frame rate, Linux and Pi untested."}
 var file=FileAccess.open(ProjectSettings.globalize_path("res://../state/travel_smoke.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("TRAVEL_SMOKE "+JSON.stringify(report));await game.shutdown(0 if failures.is_empty() else 1)
