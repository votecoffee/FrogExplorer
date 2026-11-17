extends Node

# Host-authoritative ENet: clients send only their own input; the host owns
# physics, fly catches, size, rides and world travel. Scenes are installed locally.
const VERSION=1
const DEFAULT_PORT=24970
const ACTIONS=["jump","catch_fly","croak","silly","next_frog","reset","reset_size","toggle_trigger_mode","ride_balloon","ride_car","ride_exit"]
var party:ExplorerParty
var game:Node3D
var role="local"
var status="Local play · F4 for LAN host/join"
var peer:ENetMultiplayerPeer
var members={}
var cached_fingerprint=""
var send_elapsed=0.0
var snapshot_elapsed=0.0
var sequence=0
var seen_sequence={}
var snapshots={}
var network_epoch=0
var received_epoch=-1
var server_sequence=-1
var desired_place=""
var connected_at=0
var suppress_world=false
var last_snapshot_time=0
var action_windows={}
var assemblies={}

func _ready():
 multiplayer.connected_to_server.connect(_connected)
 multiplayer.connection_failed.connect(_connection_failed)
 multiplayer.server_disconnected.connect(_server_left)
 multiplayer.peer_disconnected.connect(_peer_left)

func is_client()->bool:return role in ["client","connecting"]

func fingerprint()->String:
 if not cached_fingerprint.is_empty():return cached_fingerprint
 var files=["res://data/travel_places.json"]
 var folder=DirAccess.open("res://scripts")
 for file in folder.get_files():
  if file.ends_with(".gd") and not file.ends_with("_smoke.gd") and not file.ends_with("_probe.gd") and not file=="smoke.gd":files.append("res://scripts/"+file)
 for item in game.travel.catalog:
  if item.has("scene"):files.append(str(item.scene))
 for species in FrogPilot.SPECIES:files.append("res://assets/frogs/"+species.file+".glb")
 files.sort();var parts=[]
 for path in files:parts.append(path+":"+(FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"))
 parts.append("starter_only:"+str("--starter-models" in OS.get_cmdline_user_args()))
 var engine=Engine.get_version_info()
 cached_fingerprint="%d.%d.%d:"%[engine.major,engine.minor,engine.patch]+FileAccess.get_sha256("res://main.tscn")+str(parts).sha256_text()
 return cached_fingerprint

func _available_ids()->Array:
 var ids=[]
 for item in game.travel.available_places():ids.append(item.id)
 return ids

func host(port=DEFAULT_PORT,loopback=false)->bool:
 if role!="local":party.tell("Disconnect the current LAN session first.");return false
 if port<1024 or port>65535:return false
 fingerprint();peer=ENetMultiplayerPeer.new()
 if loopback:peer.set_bind_ip("127.0.0.1")
 var error=peer.create_server(port,7)
 if error!=OK:peer=null;status="Could not host: UDP port %d is unavailable."%port;party.tell(status);return false
 multiplayer.multiplayer_peer=peer;role="host";party.set_own_peer(1);network_epoch=game.travel.map_epoch
 var addresses=[]
 for ip in IP.get_local_addresses():
  if ip.is_valid_ip_address() and not ":" in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."):addresses.append(ip+":"+str(port))
 status="Hosting UDP %d · %s"%[port,", ".join(addresses)];party.tell(status);return true

func join(address:String)->bool:
 if role!="local":party.tell("Disconnect the current LAN session first.");return false
 var host_name=address.strip_edges();var port=DEFAULT_PORT
 if ":" in host_name:
  var bits=host_name.rsplit(":",true,1)
  if bits.size()!=2 or not bits[1].is_valid_int():party.tell("Enter a host IP or hostname, optionally followed by :port.");return false
  host_name=bits[0];port=int(bits[1])
 if host_name.is_empty() or host_name.length()>253 or "/" in host_name or port<1024 or port>65535:return false
 fingerprint();peer=ENetMultiplayerPeer.new();var error=peer.create_client(host_name,port)
 if error!=OK:peer=null;party.tell("Could not create the LAN connection.");return false
 multiplayer.multiplayer_peer=peer;role="connecting";connected_at=Time.get_ticks_msec();last_snapshot_time=connected_at
 status="Connecting to "+address+"...";_replica_mode(true);return true

func _connected():
 if role!="connecting":return
 party.set_own_peer(multiplayer.get_unique_id());game.travel.persist_history=false
 var indices=[]
 for r in party.local_records():indices.append(r.index)
 hello.rpc_id(1,VERSION,fingerprint(),_available_ids(),indices)

@rpc("any_peer","call_remote","reliable",0)
func hello(version:int,signature:String,available:Array,indices:Array):
 if role!="host":return
 var sender=multiplayer.get_remote_sender_id()
 if version!=VERSION or signature!=fingerprint():reject.rpc_id(sender,"Game scripts or scene packs differ. Use the same FrogExplorer build.");return
 if not game.travel.current_id in available:reject.rpc_id(sender,"This computer cannot load the host's current place. Return the host to the pond first.");return
 if not _valid_indices(indices) or available.size()>128:reject.rpc_id(sender,"Invalid local player list.");return
 if party.records.size()+indices.size()>party.MAX_PLAYERS:reject.rpc_id(sender,"The party is full.");return
 members[sender]={"available":available,"epoch":-1}
 for index in indices:party.add_record(sender,index,false)
 party._layout();_roster();shared_world.rpc_id(sender,game.travel.current_id,network_epoch,game.clock)

func _valid_indices(indices:Array)->bool:
 if indices.is_empty() or indices.size()>4 or not 0 in indices:return false
 var seen=[]
 for index in indices:
  if not index is int or index<0 or index>=4 or index in seen:return false
  seen.append(index)
 return true

@rpc("authority","call_remote","reliable",0)
func reject(reason:String):
 party.tell(reason);disconnect_session();status=reason

func _roster():
 if role!="host":return
 var roster=[]
 for r in party.records:roster.append({"key":r.key,"peer":r.peer,"index":r.index})
 for member in members:receive_roster.rpc_id(member,roster)

@rpc("authority","call_remote","reliable",0)
func receive_roster(roster:Array):
 if not is_client() or roster.size()>party.MAX_PLAYERS:return
 var keys=[]
 for row in roster:
  keys.append(row.key)
  if party.record_key(row.key).is_empty():party.add_record(int(row.peer),int(row.index),int(row.peer)==party.own_peer)
 for r in party.records.duplicate():
  if not r.key in keys and r.slot!=game:party.remove_record(r.key)
 party._layout();_replica_mode(true)

func local_roster_changed():
 if role=="host":_roster()
 elif role=="client":
  var indices=[]
  for r in party.local_records():indices.append(r.index)
  change_local_slots.rpc_id(1,indices)

@rpc("any_peer","call_remote","reliable",0)
func change_local_slots(indices:Array):
 if role!="host":return
 var sender=multiplayer.get_remote_sender_id()
 if not members.has(sender) or not _valid_indices(indices):return
 var owned=party.records.filter(func(r):return r.peer==sender)
 if party.records.size()-owned.size()+indices.size()>party.MAX_PLAYERS:
  var allowed=[]
  for r in owned:allowed.append(r.index)
  slots_full.rpc_id(sender,allowed);return
 for r in owned:
  if not r.index in indices:party.remove_record(r.key)
 for index in indices:party.add_record(sender,index,false)
 party._layout();_roster()

@rpc("authority","call_remote","reliable",0)
func slots_full(allowed:Array):
 if not is_client():return
 for r in party.local_records().duplicate():
  if not r.index in allowed:party.remove_record(r.key)
 party.tell("The party is full; another local frog could not join.")

func travel_reason(id:String)->String:
 if role!="host":return ""
 for member in members:
  if not id in members[member].available:return "A connected computer cannot load that place. Everyone needs the same qualified scene pack."
 return ""

func world_changed():
 if role=="host":
  network_epoch=game.travel.map_epoch
  for member in members:members[member].epoch=-1;shared_world.rpc_id(member,game.travel.current_id,network_epoch,game.clock)
 elif is_client():_client_ready()

@rpc("authority","call_remote","reliable",0)
func shared_world(id:String,epoch:int,clock:float):
 if not is_client():return
 desired_place=id;network_epoch=epoch;received_epoch=-1;snapshots.clear();game.clock=clock
 for r in party.records:r.needs_warp=true
 for r in party.local_records():r.slot.controls.neutralize()
 if game.travel.busy:game.travel.cancel()
 status="Loading shared place: "+id
 if game.travel.current_id==id:_client_ready()
 else:
  suppress_world=true;game.travel.request(id);suppress_world=false

func _client_ready():
 if not is_client() or game.travel.busy or game.travel.current_id!=desired_place:return
 game.travel.map_epoch=network_epoch;role="client";received_epoch=network_epoch;server_sequence=-1;last_snapshot_time=Time.get_ticks_msec()
 ready_world.rpc_id(1,network_epoch);status="Connected · host chooses group travel";_replica_mode(true)

@rpc("any_peer","call_remote","reliable",0)
func ready_world(epoch:int):
 var sender=multiplayer.get_remote_sender_id()
 if role=="host" and members.has(sender) and epoch==network_epoch:members[sender].epoch=epoch

func _owned(sender:int,index:int)->Dictionary:
 if not members.has(sender) or members[sender].epoch!=network_epoch:return {}
 return party.record_key("%d:%d"%[sender,index])

@rpc("any_peer","call_remote","unreliable_ordered",1)
func input_frame(index:int,epoch:int,seq:int,data:Dictionary):
 if role!="host" or epoch!=network_epoch or seq<0:return
 var sender=multiplayer.get_remote_sender_id();var r=_owned(sender,index)
 if r.is_empty() or seq<=int(seen_sequence.get(r.key,-1)):return
 if not data.get("move") is Vector2 or not data.get("aux") is Vector2 or not data.get("triggers") is Vector2:return
 if not data.move.is_finite() or not data.aux.is_finite() or not data.triggers.is_finite():return
 seen_sequence[r.key]=seq
 var c=r.slot.controls;var m:Vector2=data.move.limit_length();var a:Vector2=data.aux.limit_length();var t:Vector2=data.triggers.clamp(Vector2.ZERO,Vector2.ONE)
 c.accept_remote({"kind":"axes","move":[m.x,m.y],"aux":[a.x,a.y],"triggers":[.05+.95*t.x,.05+.95*t.y],"size_axis":clampf(float(data.get("resize",0)),-1,1),"ttl":.3})
 r.slot.camera_rig.view_mode=clampi(int(data.get("camera",0)),0,2);r.slot.pilot.paused=bool(data.get("paused",false))

@rpc("any_peer","call_remote","reliable",0)
func player_action(index:int,epoch:int,action:String):
 if role!="host" or epoch!=network_epoch or not action in ACTIONS:return
 var sender=multiplayer.get_remote_sender_id();var r=_owned(sender,index)
 if r.is_empty():return
 var now=Time.get_ticks_msec();var window=action_windows.get(sender,{"at":now,"count":0})
 if now-window.at>1000:window={"at":now,"count":0}
 window.count+=1;action_windows[sender]=window
 if window.count>40:return
 r.slot.controls.pending.append(action)

func route_local(slot):
 var c=slot.controls;var r=party.record_for(slot)
 c.travel_requests.clear();c.size_requests.clear()
 for action in c.drain():
  if action=="next_camera":slot.camera_rig.cycle()
  elif action=="help":slot.pilot.paused=not slot.pilot.paused;slot.hud.help.visible=slot.pilot.paused
  elif action=="debug":slot.hud.debug_enabled=not slot.hud.debug_enabled
  elif action=="mute":AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0))
  elif action in ACTIONS and role=="client" and not (party.menu.visible and slot==game):player_action.rpc_id(1,int(r.index),network_epoch,action)
  elif action in ["travel_random","travel_home","travel_menu","travel_cancel"]:party.tell("The host's Player 1 chooses travel for the group.")

func _snapshot(r:Dictionary)->Dictionary:
 var p=r.slot.pilot;var ride=r.slot.rides
 return {"key":r.key,"position":p.position,"basis":p.visual_root.quaternion,"velocity":p.velocity,"species":p.species,"scale":p.metrics.factor,"mode":p.mode,"heading":p.heading,"climb_angle":p.climb_angle,"tree_index":p.tree_index,"clip":p.current_clip,"clip_time":p.player.current_animation_position,"clip_rate":p.player.speed_scale,"action_timer":p.action_timer,"action_name":p.action_name,"flies":p.flies_caught,"tongue":p.tongue.visible,"tongue_transform":p.tongue.global_transform,"ride":ride.kind,"ride_enabled":ride.enabled,"ride_speed":ride.speed,"body_position":ride.body.position if ride.active() else p.position}

func _receive_state(epoch:int,seq:int,clock:float,players:Array,elapsed:float,flies:Array):
 if role!="client" or epoch!=received_epoch or seq<=server_sequence or players.size()>party.MAX_PLAYERS:return
 server_sequence=seq;last_snapshot_time=Time.get_ticks_msec();game.clock=clock
 for row in players:
  if not party.record_key(str(row.key)).is_empty():snapshots[row.key]=row
 game.woodland.elapsed=elapsed
 for i in range(mini(flies.size(),game.woodland.flies.size())):game.woodland.flies[i].respawn=float(flies[i])
 game.woodland._process(0)

@rpc("authority","call_remote","unreliable_ordered",2)
func state_chunk(epoch:int,seq:int,index:int,count:int,bytes:PackedByteArray):
 if role!="client" or epoch!=received_epoch or seq<=server_sequence or count<1 or count>32 or index<0 or index>=count or bytes.size()>1000:return
 for old in assemblies.keys():
  if old<seq-2:assemblies.erase(old)
 if not assemblies.has(seq):assemblies[seq]={"count":count,"parts":{}}
 var frame=assemblies[seq]
 if frame.count!=count:return
 frame.parts[index]=bytes
 if frame.parts.size()!=count:return
 var packed=PackedByteArray()
 for i in range(count):packed.append_array(frame.parts[i])
 assemblies.erase(seq)
 var unpacked=packed.decompress_dynamic(262144,FileAccess.COMPRESSION_DEFLATE)
 if unpacked.size()<4:return
 var data=bytes_to_var(unpacked)
 if data is Array and data.size()==6:_receive_state(int(data[0]),int(data[1]),float(data[2]),data[3],float(data[4]),data[5])

func _replica_mode(enabled:bool):
 game.ros.set_client_mode(enabled)
 game.woodland.set_process(not enabled)
 for r in party.records:
  r.slot.pilot.set_physics_process(not enabled)
  if enabled:r.slot.pilot.collision_layer=0;r.slot.pilot.collision_mask=0
 party._layers()

func _apply(r:Dictionary,data:Dictionary,delta:float):
 var p=r.slot.pilot;var rides=r.slot.rides
 if p.species!=int(data.species):p.select_species(int(data.species))
 var size=clampf(float(data.scale),.25,16)
 if not is_equal_approx(p.metrics.factor,size):p._apply_size(size)
 var warp=bool(r.get("needs_warp",true));r.needs_warp=false
 p.heading=float(data.heading);p.climb_angle=float(data.climb_angle);p.tree_index=int(data.tree_index)
 p.action_timer=float(data.action_timer);p.action_name=str(data.action_name);p.flies_caught=int(data.flies)
 rides.replicate(data,delta,warp)
 if not rides.active():
  var target:Vector3=data.position
  p.position=target if warp or p.position.distance_to(target)>5*size else p.position.lerp(target,1-exp(-delta*18))
 p.mode=str(data.mode);p.velocity=data.velocity;p.visual_root.quaternion=p.visual_root.quaternion.slerp(data.basis,1-exp(-delta*25)) if not warp else data.basis
 var changed=p.current_clip!=str(data.clip)
 p._play(str(data.clip),float(data.clip_rate))
 if changed or absf(p.player.current_animation_position-float(data.clip_time))>.18:p.player.seek(float(data.clip_time),true)
 if changed and data.clip=="Croak":p.sound.pitch_scale=FrogPilot.SPECIES[p.species].pitch;p.sound.play()
 p.tongue.visible=bool(data.tongue)
 if p.tongue.visible:p.tongue.global_transform=data.tongue_transform
 p.collision_layer=0;p.collision_mask=0

func _physics_process(delta):
 if role=="client" and received_epoch==network_epoch:
  send_elapsed+=delta
  if send_elapsed>=1.0/30:
   send_elapsed=0;sequence+=1
   for r in party.local_records():
    var slot=r.slot;var c=slot.controls
    input_frame.rpc_id(1,int(r.index),network_epoch,sequence,{"move":c.move,"aux":c.auxiliary,"triggers":c.triggers,"resize":c.size_axis,"camera":slot.camera_rig.view_mode,"paused":slot.pilot.paused or (party.menu.visible and slot==game)})

func _process(delta):
 if is_client():
  if role=="connecting" and Time.get_ticks_msec()-connected_at>12000:disconnect_session();status="Connection timed out.";party.tell(status)
  elif role=="client":
   if game.travel.busy:last_snapshot_time=Time.get_ticks_msec();return
   if game.travel.status=="failed" and game.travel.current_id!=desired_place:
    var reason="Could not load the shared place: "+game.travel.last_error;disconnect_session();status=reason;party.tell(reason);return
   if Time.get_ticks_msec()-last_snapshot_time>8000:disconnect_session();status="Host stopped sending state.";party.tell(status);return
   for r in party.records:
    if snapshots.has(r.key):_apply(r,snapshots[r.key],delta)
 elif role=="host":
  snapshot_elapsed+=delta
  if snapshot_elapsed<.05 or game.travel.busy:return
  snapshot_elapsed=0;sequence+=1
  var players=[];var flies=[]
  for r in party.records:players.append(_snapshot(r))
  for fly in game.woodland.flies:flies.append(fly.respawn)
  var packed=var_to_bytes([network_epoch,sequence,game.clock,players,game.woodland.elapsed,flies]).compress(FileAccess.COMPRESSION_DEFLATE)
  var chunks=ceili(packed.size()/1000.0)
  for member in members:
   if members[member].epoch==network_epoch:
    for i in range(chunks):state_chunk.rpc_id(member,network_epoch,sequence,i,chunks,packed.slice(i*1000,mini(packed.size(),(i+1)*1000)))

func _peer_left(id:int):
 if role!="host" or not members.has(id):return
 members.erase(id)
 for r in party.records.duplicate():
  if r.peer==id:party.remove_record(r.key);seen_sequence.erase(r.key)
 action_windows.erase(id);_roster();party.tell("A remote player disconnected.")

func _server_left():
 if is_client():disconnect_session();status="Host disconnected; local play restored.";party.tell(status)
func _connection_failed():
 if is_client():disconnect_session();status="Could not connect to the host.";party.tell(status)

func close_peer():
 if peer:peer.close()
 multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new();peer=null

func disconnect_session():
 var was_client=is_client();role="local";close_peer();members.clear();snapshots.clear();seen_sequence.clear();action_windows.clear();assemblies.clear()
 for r in party.records.duplicate():
  if not r.local:party.remove_record(r.key)
 party.set_own_peer(1);game.travel.persist_history=not "--test-session" in OS.get_cmdline_user_args()
 for r in party.local_records():
  r.slot.controls.neutralize();r.slot.pilot.paused=false
  if was_client:r.slot.rides.clear_for_travel();r.slot.pilot.release_contacts();r.slot.pilot.reset_position()
 if party.menu.visible:game.pilot.paused=true
 _replica_mode(false);party._layout();status="Local play"
