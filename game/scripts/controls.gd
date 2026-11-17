class_name ExplorerControls
extends Node

var device = -1
var auto_assign=true
var keyboard_enabled=true
var hardware_enabled=true
var move = Vector2.ZERO
var auxiliary = Vector2.ZERO
var raw_axes = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var vehicle_triggers=false
var triggers=Vector2.ZERO
var remote_triggers=Vector2.ZERO
var size_axis=0.0
var resize_wait_for_release=false
var remote_size_axis=0.0
var size_until=0.0
var size_requests:Array[float]=[]
var raw_buttons = []
var pending: Array[String] = []
var travel_requests:Array[String]=[]
var remote_move = Vector2.ZERO
var remote_aux = Vector2.ZERO
var remote_until = 0.0
var remote_velocity = Vector4.ZERO
var velocity_until = 0.0
var deadzone = 0.18
var device_name = "Keyboard"
var device_profile:Dictionary={}

const BUTTONS = {JOY_BUTTON_X:"jump", JOY_BUTTON_Y:"catch_fly", JOY_BUTTON_A:"croak", JOY_BUTTON_B:"silly", JOY_BUTTON_LEFT_SHOULDER:"next_frog", JOY_BUTTON_RIGHT_SHOULDER:"next_camera", JOY_BUTTON_START:"help", JOY_BUTTON_BACK:"travel_random", JOY_BUTTON_RIGHT_STICK:"travel_menu", JOY_BUTTON_LEFT_STICK:"toggle_trigger_mode"}
const KEYS = {KEY_SPACE:"jump", KEY_X:"jump", KEY_F:"catch_fly", KEY_Y:"catch_fly", KEY_V:"croak", KEY_B:"silly", KEY_G:"silly", KEY_TAB:"next_frog", KEY_Q:"next_frog", KEY_C:"next_camera", KEY_ESCAPE:"help", KEY_F1:"help", KEY_R:"reset", KEY_M:"mute", KEY_F2:"debug", KEY_T:"travel_random", KEY_N:"travel_menu", KEY_H:"travel_home", KEY_0:"reset_size", KEY_KP_0:"reset_size", KEY_F3:"toggle_trigger_mode", KEY_1:"ride_balloon", KEY_2:"ride_car", KEY_3:"ride_exit"}

func _ready():
 Input.joy_connection_changed.connect(_connection)
 _find_device()

func _connection(_id, _connected):
 if auto_assign:_find_device()
 elif _id==device and not _connected:assign_device(-1);neutralize()

func _find_device():
 if not auto_assign:return
 var pads = Input.get_connected_joypads()
 assign_device(pads[0] if not pads.is_empty() else -1)

func _input(event):
 if hardware_enabled and event is InputEventJoypadButton and event.device == device and event.pressed:
  if BUTTONS.has(event.button_index): pending.append(BUTTONS[event.button_index])
 if keyboard_enabled and event is InputEventKey and event.pressed and not event.echo:
  if KEYS.has(event.physical_keycode): pending.append(KEYS[event.physical_keycode])

func _axis(value):
 return signf(value) * maxf(0.0, (absf(value) - deadzone) / (1.0 - deadzone))

func trigger_value(value:float)->float:
 return clampf((value-.05)/.95,0,1)

func resize_axis(left:float,right:float)->float:
 return trigger_value(left)-trigger_value(right)

func _key_pair(primary,alternative):
 return float(Input.is_physical_key_pressed(primary) or Input.is_physical_key_pressed(alternative))

func sample():
 move = Vector2.ZERO
 auxiliary = Vector2.ZERO
 raw_axes = [0.0,0.0,0.0,0.0,0.0,0.0]
 size_axis=0.0;triggers=Vector2.ZERO
 var local_resize=false
 raw_buttons = []
 if hardware_enabled and device >= 0:
  for axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y,JOY_AXIS_RIGHT_X,JOY_AXIS_RIGHT_Y,JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]: raw_axes[axis] = Input.get_joy_axis(device,axis)
  for button in range(15): raw_buttons.append(1 if Input.is_joy_button_pressed(device,button) else 0)
  move = Vector2(_axis(raw_axes[0]),_axis(raw_axes[1]))
  auxiliary = Vector2(_axis(raw_axes[2]),_axis(raw_axes[3]))
  triggers=Vector2(trigger_value(raw_axes[4]),trigger_value(raw_axes[5]));local_resize=triggers.length()>.001
  if not vehicle_triggers:size_axis=triggers.x-triggers.y
  move += Vector2(float(Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_RIGHT))-float(Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_LEFT)),float(Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_DOWN))-float(Input.is_joy_button_pressed(device,JOY_BUTTON_DPAD_UP)))
 if keyboard_enabled:
  move += Vector2(_key_pair(KEY_D,KEY_RIGHT)-_key_pair(KEY_A,KEY_LEFT),_key_pair(KEY_S,KEY_DOWN)-_key_pair(KEY_W,KEY_UP))
  auxiliary += Vector2(_key_pair(KEY_L,KEY_E)-_key_pair(KEY_J,KEY_Z),_key_pair(KEY_K,KEY_PAGEDOWN)-_key_pair(KEY_I,KEY_PAGEUP))
 var grow=keyboard_enabled and (Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD))
 var shrink=keyboard_enabled and (Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT))
 size_axis=clampf(size_axis+float(grow)-float(shrink),-1,1)
 local_resize=local_resize or grow or shrink
 if not local_resize and Time.get_ticks_msec()/1000.0<size_until:
  if not vehicle_triggers and not grow and not shrink:size_axis=remote_size_axis
  triggers=remote_triggers
 if resize_wait_for_release:
  if not local_resize and triggers.length()<.001 and absf(size_axis)<.001:resize_wait_for_release=false
  size_axis=0.0
 move = move.limit_length()
 auxiliary = auxiliary.limit_length()
 if move.length() < 0.02 and auxiliary.length() < 0.02 and Time.get_ticks_msec()/1000.0 < remote_until:
  move = remote_move
  auxiliary = remote_aux

func drain() -> Array[String]:
 var result = pending.duplicate()
 pending.clear()
 return result

func assign_device(id:int):
 device=id;device_profile=ExplorerGamepadProfile.for_device(id)
 device_name=str(device_profile.display_name) if id>=0 else ("Keyboard" if keyboard_enabled else "Controller disconnected")

func neutralize():
 move=Vector2.ZERO;auxiliary=Vector2.ZERO;size_axis=0;triggers=Vector2.ZERO
 remote_move=Vector2.ZERO;remote_aux=Vector2.ZERO;remote_triggers=Vector2.ZERO
 remote_size_axis=0;remote_until=0;velocity_until=0;size_until=0
 pending.clear();travel_requests.clear();size_requests.clear()

func accept_remote(packet: Dictionary):
 var now = Time.get_ticks_msec()/1000.0
 match packet.get("kind",""):
  "action":
   var action = str(packet.get("action",""))
   if action in ["jump","catch_fly","croak","silly","next_frog","next_camera","reset","travel_random","travel_home","travel_menu","travel_cancel","reset_size","toggle_trigger_mode","ride_balloon","ride_car","ride_exit"]: pending.append(action)
  "travel":
   var id=packet.get("place_id","")
   if id is String and id.length()<=80:travel_requests.append(id)
  "size":
   var factor=float(packet.get("factor",0))
   if is_finite(factor) and factor>=FrogBodyMetrics.MIN_FACTOR and factor<=FrogBodyMetrics.MAX_FACTOR:size_requests.append(factor)
  "axes":
   var m = packet.get("move",[])
   var a = packet.get("aux",[])
   if m is Array and a is Array and m.size()==2 and a.size()==2:
    remote_move=Vector2(float(m[0]),float(m[1])).limit_length()
    remote_aux=Vector2(float(a[0]),float(a[1])).limit_length()
    remote_until=now+clampf(float(packet.get("ttl",0.3)),0.05,0.5)
    var resize=float(packet.get("size_axis",0))
    remote_size_axis=clampf(resize,-1,1) if is_finite(resize) else 0.0;size_until=remote_until
    var t=packet.get("triggers",[maxf(0,remote_size_axis),maxf(0,-remote_size_axis)])
    if t is Array and t.size()==2:remote_triggers=Vector2(trigger_value(float(t[0])),trigger_value(float(t[1])))
    velocity_until=0
  "velocity":
   remote_velocity=Vector4(clampf(float(packet.get("forward",0)),-1.5,1.5),clampf(float(packet.get("strafe",0)),-1.5,1.5),clampf(float(packet.get("vertical",0)),-0.7,0.7),clampf(float(packet.get("yaw",0)),-3,3))
   velocity_until=now+clampf(float(packet.get("ttl",0.3)),0.05,0.5)
   remote_until=0

func velocity_active():
 return Time.get_ticks_msec()/1000.0 < velocity_until and move.length()<0.02 and auxiliary.length()<0.02
