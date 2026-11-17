extends SceneTree

# File-driven, headless acceptance harness, never loaded by normal gameplay.
var game
var folder=""
var label=""
var base_device=40
var processed=0
var hold={}
var hold_until=0
var started=0

func _initialize():run.call_deferred()
func vector(value:Array)->Vector2:return Vector2(float(value[0]),float(value[1]))
func find_local(index:int):
 for r in game.party.local_records():
  if r.index==index:return r
 return {}

func command(data:Dictionary):
 var r=find_local(int(data.get("player",0)))
 match str(data.get("cmd","")):
  "axes":hold=data;hold_until=Time.get_ticks_msec()+int(float(data.get("duration",.5))*1000)
  "action":
   if not r.is_empty():r.slot.controls.pending.append(str(data.action))
  "travel":game.travel.request(str(data.place))
  "add_local":game.party.join_local(base_device+int(data.index))
  "remove_local":game.party._connection(base_device+int(data.index),false)
  "disconnect":hold.clear();game.party.lan.disconnect_session()
  "join":game.party.lan.join(str(data.address))
  "fingerprint":game.party.lan.cached_fingerprint=str(data.value)
  "silence_input":game.party.lan.set_physics_process(not bool(data.enabled))
  "old_epoch":game.party.lan.input_frame.rpc_id(1,0,game.party.lan.network_epoch-1,999999,{"move":Vector2(1,0),"aux":Vector2.ZERO,"triggers":Vector2.ZERO,"resize":1.0})
  "setup_catch":
   if game.party.lan.role=="host":
    var record=game.party.record_key(str(data.key))
    if not record.is_empty():record.slot.rides.clear_for_travel();record.slot.pilot.reset_position(Vector3(2.4,.2,3.2))
  "quit":game.shutdown.call_deferred(0)

func observe()->Dictionary:
 var players=[]
 for r in game.party.records:
  var p=r.slot.pilot;var ride=r.slot.rides
  players.append({"key":r.key,"peer":r.peer,"index":r.index,"local":r.local,"position":[p.position.x,p.position.y,p.position.z],"scale":p.metrics.factor,"species":p.species,"mode":p.mode,"clip":p.current_clip,"ride":ride.kind,"ride_notice":ride.last_notice,"ride_prop":is_instance_valid(ride.prop),"parachute_lines":ride.suspension.size(),"ride_collision":ride.body.collision_layer if ride.active() else -1,"physics":p.is_physics_processing(),"score":p.flies_caught,"camera":r.slot.camera_rig.view_mode})
 var flies=[]
 for fly in game.woodland.flies:flies.append(fly.respawn)
 return {"role":game.party.lan.role,"status":game.party.lan.status,"own_peer":game.party.own_peer,"place":game.travel.current_id,"epoch":game.travel.map_epoch,"net_epoch":game.party.lan.network_epoch,"busy":game.travel.busy,"players":players,"views":game.party.panels.size(),"processed":processed,"flies":flies,"snapshots":game.party.lan.snapshots.size(),"server_sequence":game.party.lan.server_sequence,"ros_client_mode":game.ros.client_mode}

func run():
 var port=24971;var count=2
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--probe-dir="):folder=arg.trim_prefix("--probe-dir=")
  if arg.begins_with("--probe-role="):label=arg.trim_prefix("--probe-role=")
  if arg.begins_with("--probe-port="):port=int(arg.trim_prefix("--probe-port="))
  if arg.begins_with("--probe-pads="):count=int(arg.trim_prefix("--probe-pads="))
 if folder.is_empty() or label.is_empty():quit(2);return
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await create_timer(.3).timeout
 base_device=40 if label=="host" else 60
 game.party.records[0].device=base_device;game.controls.assign_device(base_device)
 for i in range(1,count):game.party.join_local(base_device+i)
 if label=="host":game.party.lan.host(port,true)
 else:game.party.lan.join("127.0.0.1:"+str(port))
 started=Time.get_ticks_msec()
 while not game.quitting and Time.get_ticks_msec()-started<240000:
  var path=folder+"/"+label+"_command_%06d.json"%(processed+1)
  if FileAccess.file_exists(path):
   var data=JSON.parse_string(FileAccess.get_file_as_string(path))
   if data is Dictionary and int(data.get("seq",-1))>processed:processed=int(data.seq);command(data)
  if not hold.is_empty():
   var record=find_local(int(hold.get("player",0)))
   if not record.is_empty():
    var live=Time.get_ticks_msec()<hold_until
    var m=vector(hold.get("move",[0,0])) if live else Vector2.ZERO
    var a=vector(hold.get("aux",[0,0])) if live else Vector2.ZERO
    var t=hold.get("triggers",[0,0]) if live else [0,0]
    record.slot.controls.accept_remote({"kind":"axes","move":[m.x,m.y],"aux":[a.x,a.y],"triggers":t,"size_axis":float(hold.get("resize",0)) if live else 0.0,"ttl":.2})
   if Time.get_ticks_msec()>=hold_until:hold.clear()
  var output=folder+"/"+label+"_state.json";var temp=output+".tmp"
  var file=FileAccess.open(temp,FileAccess.WRITE);file.store_string(JSON.stringify(observe()));file.close()
  if FileAccess.file_exists(output):DirAccess.remove_absolute(output)
  DirAccess.rename_absolute(temp,output)
  await create_timer(.05).timeout
 if not game.quitting:await game.shutdown(1)
