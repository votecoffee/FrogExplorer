class_name ExplorerRosLink
extends Node

var input:ExplorerControls
var receive=PacketPeerUDP.new()
var transmit=PacketPeerUDP.new()
var connected=false
var last_heartbeat=-100.0
var session=str(Time.get_unix_time_from_system())+"-"+str(randi())
var sequence=0
var last_command=-1
var remote_session=""
var accumulated=0.0
var events=[]
var bound=false
var travel_state:Dictionary={}
var disabled=false
var client_mode=false

func _ready():
 disabled="--no-ros" in OS.get_cmdline_user_args()
 if disabled:return
 bound=receive.bind(17777,"127.0.0.1")==OK
 transmit.set_dest_address("127.0.0.1",17776)

func poll():
 if disabled:return
 if client_mode:
  for i in range(mini(32,receive.get_available_packet_count())):receive.get_packet()
  connected=false;return
 for i in range(mini(32,receive.get_available_packet_count())):
  var bytes=receive.get_packet()
  if bytes.size()>8192 or receive.get_packet_ip()!="127.0.0.1":continue
  var packet=JSON.parse_string(bytes.get_string_from_utf8())
  if not packet is Dictionary or packet.get("v",0)!=1:continue
  last_heartbeat=Time.get_ticks_msec()/1000.0
  if packet.get("kind","")=="heartbeat":continue
  if packet.get("session","")!=remote_session:remote_session=packet.get("session","");last_command=-1
  var seq=int(packet.get("seq",-1))
  if seq<=last_command:continue
  last_command=seq
  if input:input.accept_remote(packet)
 connected=Time.get_ticks_msec()/1000.0-last_heartbeat<1.5

func publish(delta,pilot:FrogPilot,camera:ExplorerCamera,clock:float):
 if disabled or client_mode:events.clear();return
 accumulated+=delta
 if accumulated<.05:return
 accumulated=0
 var forward=pilot.facing_basis().z.normalized();var up=pilot.facing_basis().y.normalized()
 var p=pilot.global_position
 var state={"v":1,"kind":"state","session":session,"seq":sequence,"time":clock,"position":[p.x,p.y,p.z],"forward":[forward.x,forward.y,forward.z],"up":[up.x,up.y,up.z],"species":FrogPilot.SPECIES[pilot.species].name,"mode":pilot.mode,"camera":ExplorerCamera.NAMES[camera.view_mode],"animation":pilot.current_clip,"flies_caught":pilot.flies_caught,"depth":maxf(0,-p.y),"fps":Engine.get_frames_per_second(),"axes":input.raw_axes,"buttons":input.raw_buttons,"events":events.duplicate()}
 state.merge({"scale":pilot.metrics.factor,"scale_limits":[FrogBodyMetrics.MIN_FACTOR,FrogBodyMetrics.MAX_FACTOR],"body_height_m":pilot.metrics.height(),"collision_radius_m":pilot.metrics.radius(),"walk_speed_mps":pilot.metrics.walk_speed(),"swim_speed_mps":pilot.metrics.swim_speed(),"climb_speed_mps":pilot.metrics.climb_speed(),"resize_blocked":pilot.resize_blocked})
 state.merge(travel_state)
 transmit.put_packet(JSON.stringify(state).to_utf8_buffer());sequence+=1;events.clear()

func set_client_mode(value:bool):
 # A client launched from F4 may already have a local bridge. Keep host-only
 # ROS ownership and discard suspended commands rather than replaying them.
 client_mode=value;connected=false
 if bound:
  while receive.get_available_packet_count()>0:receive.get_packet()

func _exit_tree():
 if disabled:return
 transmit.put_packet(JSON.stringify({"v":1,"kind":"goodbye","session":session,"seq":sequence}).to_utf8_buffer())
 receive.close();transmit.close()
