extends SceneTree

# Optional actual-pack travel failure/cancellation checks. Source-only streaming
# physics is covered separately by stream_smoke.gd.
var game
var failures=[]
var checks=[]
func _initialize():run.call_deferred()
func check(ok:bool,text:String):
 checks.append({"test":text,"passed":ok})
 if not ok:failures.append(text)
 print(("PASS " if ok else "FAIL ")+text)
func wait_idle():
 var end=Time.get_ticks_msec()+30000
 while game.travel.busy and Time.get_ticks_msec()<end:await process_frame
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await create_timer(.2).timeout
 var travel=game.travel;var item=travel.place("tokyo_imperial_palace");var data=WorldTiles.manifest(item)
 check(not data.is_empty() and not data.has("error"),"Actual Tokyo tile pack is installed and structurally valid")
 if data.is_empty() or data.has("error"):await game.shutdown(1);return
 var old=game.woodland;var before=game.pilot.position;var path=str(item.tile_manifest)
 WorldTiles.cache[path]={"error":"Injected invalid tile manifest"};travel.request(item.id);await process_frame
 check(game.woodland==old and travel.current_id=="home_woodland_pond" and not travel.busy,"Invalid manifest leaves the current world active")
 var damaged=data.duplicate(true);damaged.files[data.overview_scene]="0".repeat(64);WorldTiles.cache[path]=damaged
 travel.request(item.id);await wait_idle()
 check(game.woodland==old and travel.current_id=="home_woodland_pond" and travel.last_error.contains("integrity"),"Integrity failure cannot replace the old world or its collision")
 WorldTiles.cache[path]=data;travel.request(item.id)
 var end=Time.get_ticks_msec()+10000
 while not is_instance_valid(travel.staged) and travel.busy and Time.get_ticks_msec()<end:await process_frame
 check(is_instance_valid(travel.staged),"Travel stages arrival tiles before switching worlds")
 travel.cancel();await create_timer(.2).timeout
 check(game.woodland==old and travel.current_id=="home_woodland_pond" and game.pilot.is_on_floor(),"Cancelling staged tile loading preserves the playable old world")
 travel.request(item.id);await wait_idle();await create_timer(3).timeout
 check(game.woodland is TiledMeshWorld and travel.current_id==item.id,"A cancelled tile pack can be requested again successfully")
 check(not ResourceLoader.has_cached(str(item.scene)),"Tiled travel never loads the original full-resolution GLB")
 if game.woodland is TiledMeshWorld:
  var stream=game.woodland.streaming_state()
  check(stream.resident<stream.total and stream.pending==0 and stream.error.is_empty(),"Settled arrival keeps only nearby detail resources resident")
  check(game.pilot.is_on_floor() and game.pilot.position.distance_to(game.woodland.spawn_point)<.2,"Checked arrival stands on real source collision")
 travel.request("rome_colosseum");await wait_idle();await create_timer(.5).timeout
 check(game.woodland is TiledMeshWorld and travel.current_id=="rome_colosseum" and game.pilot.is_on_floor(),"Travel between two tiled packs registers the correct collision")
 travel.request("home_woodland_pond");await wait_idle();await create_timer(.3).timeout
 check(not game.woodland is TiledMeshWorld and game.pilot.is_on_floor(),"Returning to the procedural pond restores the original world contract")
 var missing=item.duplicate();missing.tile_manifest="res://assets/worlds/not_installed/manifest.json"
 check(WorldTiles.manifest(missing).is_empty(),"An absent optional tile pack retains compatibility with original asset imports")
 var file=FileAccess.open("res://../state/tile_travel_smoke.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures}," ")+"\n");file.close()
 print("TILE_TRAVEL_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
