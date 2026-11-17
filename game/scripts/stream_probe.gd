extends SceneTree

var game
func _initialize():run.call_deferred()
func run():
 var id="tokyo_imperial_palace"
 var out="user://stream_probe.json"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--destination="):id=arg.trim_prefix("--destination=")
  if arg.begins_with("--report="):out=arg.trim_prefix("--report=")
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await create_timer(.2).timeout
 var started=Time.get_ticks_msec();game.travel.request(id)
 while game.travel.busy:await process_frame
 var arrival_ms=Time.get_ticks_msec()-started
 await create_timer(3).timeout
 var data={"place":game.travel.current_id,"arrival_ms":arrival_ms,"settle_ms":3000,"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"stream":game.woodland.streaming_state(),"original_cached":ResourceLoader.has_cached(str(game.travel.place(id).scene)),"headless":true}
 var file=FileAccess.open(out,FileAccess.WRITE);file.store_string(JSON.stringify(data," ")+"\n");file.close()
 print("STREAM_PROBE "+JSON.stringify(data))
 await game.shutdown(0 if game.travel.current_id==id else 1)
