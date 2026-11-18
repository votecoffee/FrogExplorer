extends SceneTree

# Actual optional municipal pack acceptance, separate from source-only fixtures.
var game
var checks=[]
var failures=[]
var measurements=[]
func _initialize():run.call_deferred()
func wait(seconds):await create_timer(seconds).timeout
func check(ok,text):
 checks.append({"test":text,"passed":bool(ok)})
 if not ok:failures.append(text)
 print(("PASS " if ok else "FAIL ")+text)
func idle():
 var end=Time.get_ticks_msec()+90000
 while game.travel.busy and Time.get_ticks_msec()<end:await process_frame
func stop():game.controls.remote_until=0;game.controls.velocity_until=0
func move(value,aux=Vector2.ZERO):
 game.controls.remote_move=value;game.controls.remote_aux=aux;game.controls.remote_until=Time.get_ticks_msec()/1000.0+30
func run():
 var ids=["helsinki_city_center","lyon_bellecour","strasbourg_cathedral"]
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--destination="):ids=[arg.trim_prefix("--destination=")]
 game=load("res://main.tscn").instantiate();root.add_child(game);await wait(.25)
 var travel=game.travel;var pilot=game.pilot
 for id in ids:
  var item=travel.place(id);var data=WorldTiles.manifest(item)
  check(not data.is_empty() and not data.has("error"),id+": complete multi-LOD manifest")
  if data.is_empty() or data.has("error"):continue
  check(WorldTiles.verify(data).is_empty(),id+": native render and collision checksums")
  check(data.lod_distances.size()==3 and data.tiles.size()>=64,id+": three streamed levels and a far overview")
  pilot.try_resize(4);var old=game.woodland
  travel.request(id);travel.cancel();await wait(.1)
  check(game.woodland==old and is_equal_approx(pilot.metrics.factor,4),id+": cancelled travel preserves current world and size")
  var started=Time.get_ticks_msec();travel.request(id);await idle();await wait(.7)
  check(travel.current_id==id and game.woodland is TiledMeshWorld,id+": checked atomic arrival")
  if travel.current_id!=id:print("ARRIVAL_ERROR ",travel.last_error);continue
  var world=game.woodland
  check(pilot.is_on_floor() and pilot.position.is_finite(),id+": frog stands on photographed source collision")
  check(is_equal_approx(pilot.metrics.factor,1),id+": arrival resets size")
  check(not ResourceLoader.has_cached(str(item.scene)),id+": no original whole scene loaded")
  check(world.travel_bounds.size.x>1000 and world.travel_bounds.size.y>1000,id+": exploration exceeds one kilometre each way")
  check(world.trees.is_empty() and not world.in_water(pilot.position),id+": scan does not invent swimming or tree mechanics")
  var origin=pilot.position;move(Vector2(1,0));await wait(1.3);stop();await wait(.25)
  check(pilot.position.distance_to(origin)>.1 and pilot.is_on_floor(),id+": walking uses real source ground")
  pilot.reset_position();await wait(.4)
  var rides=game.rides;rides.request("CAR");await wait(.2)
  check(rides.kind=="CAR",id+": convertible can deploy at the checked arrival")
  if rides.active():rides.clear_for_travel();pilot.reset_position();await wait(.3)
  rides.request("BALLOON");await wait(.25)
  check(rides.kind=="BALLOON",id+": balloon deploys in the arrival's clear space")
  if rides.kind=="BALLOON":
   # Rise above nearby roofs, then cross several detail boundaries with the
   # normal injected analogue controls and loader prefetch active.
   move(Vector2.ZERO,Vector2(0,-1));await wait(6);stop();await wait(.8)
   var flight_origin=rides.body.position
   move(Vector2(-1,0));await wait(8);stop();await wait(1.8)
   var distance=Vector2(rides.body.position.x-flight_origin.x,rides.body.position.z-flight_origin.z).length()
   check(distance>100,id+": fast balloon flight crosses multiple source cells")
   check(world.stream_error.is_empty() and world.surface_ready(rides.body.position,1),id+": fine collision follows the moving balloon")
   rides.jump_out();await wait(.2)
   check(rides.kind=="PARACHUTE",id+": jump deploys a parachute")
   var end=Time.get_ticks_msec()+18000
   while rides.active() and Time.get_ticks_msec()<end:await process_frame
   await wait(.3)
   check(not rides.active() and pilot.is_on_floor(),id+": parachute lands on the newly streamed ground")
  stop();rides.clear_for_travel();pilot.reset_position();await wait(3)
  var state=world.streaming_state()
  check(state.error.is_empty() and state.resident<state.total,id+": bounded subset of detailed cells remains resident")
  check(state.lod_cells.has(0) and (state.lod_cells.has(1) or state.lod_cells.has(2)),id+": near and distant source levels coexist")
  if id=="strasbourg_cathedral":
   var credits=game.hud.credit_logos.get_child_count()==3 and game.hud.credit_layer.visible and game.hud.credit_layer.get_parent()==game
   for logo in game.hud.credit_logos.get_children():credits=credits and logo.texture!=null and logo.texture.get_width()>1
   check(credits,id+": required source credit logos load on a layer shared by all views")
  measurements.append({"id":id,"elapsed_ms":Time.get_ticks_msec()-started,"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"stream":state})
  travel.request("home_woodland_pond");await idle();await wait(.35)
  check(travel.current_id=="home_woodland_pond" and pilot.is_on_floor(),id+": safe return to the pond")
 var report={"checks":checks,"failures":failures,"measurements":measurements,"scope":"Windows headless real source geometry, injected controls and physics. Offscreen appearance reviewed separately. No hardware controller, interactive FPS, Linux or Pi qualification."}
 var path="res://../state/city_pack_smoke_"+str(ids[0])+".json"
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("CITY_PACK_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures,"measurements":measurements}))
 await game.shutdown(0 if failures.is_empty() else 1)
