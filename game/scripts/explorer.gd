extends Node3D

var woodland:WoodlandWorld
var controls:ExplorerControls
var pilot:FrogPilot
var camera_rig:ExplorerCamera
var rides:ExplorerRides
var travel:WorldTravel
var travel_menu:ExplorerTravelMenu
var hud:ExplorerHUD
var ros:ExplorerRosLink
var ambience:AudioStreamPlayer
var marker:Label3D
var party:ExplorerParty
var activities:CanvasLayer
const Activities=preload("res://scripts/activities/activities.gd")
var clock=0.0
var pending_events=[]
var quitting=false
var quit_frames=0
var frames=0

func _ready():
 get_tree().auto_accept_quit=false
 woodland=WoodlandWorld.new();woodland.name="Woodland";add_child(woodland)
 controls=ExplorerControls.new();add_child(controls)
 ros=ExplorerRosLink.new();ros.input=controls;add_child(ros)
 pilot=FrogPilot.new();pilot.name="Frog";pilot.woodland=woodland;pilot.controls=controls;pilot.event_occurred.connect(_event);add_child(pilot);pilot.reset_position()
 camera_rig=ExplorerCamera.new();camera_rig.pilot=pilot;camera_rig.woodland=woodland;pilot.camera_rig=camera_rig;add_child(camera_rig)
 hud=ExplorerHUD.new();add_child(hud);hud.toast("Welcome. Head for the pond — or climb the nearest tree.")
 marker=Label3D.new();marker.text="F / Y";marker.font_size=42;marker.pixel_size=.003;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;marker.modulate=Color(1,.88,.28);marker.outline_size=10;add_child(marker)
 ambience=AudioStreamPlayer.new();ambience.volume_db=-17;add_child(ambience)
 if ResourceLoader.exists("res://assets/audio/woodland.wav"):
  ambience.stream=load("res://assets/audio/woodland.wav");ambience.stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;ambience.stream.loop_end=int(ambience.stream.get_length()*ambience.stream.mix_rate);ambience.play()
 travel=WorldTravel.new();travel.game=self;add_child(travel)
 travel_menu=ExplorerTravelMenu.new();travel_menu.game=self;add_child(travel_menu)
 rides=ExplorerRides.new();rides.game=self;rides.pilot=pilot;rides.controls=controls;pilot.rides=rides;add_child(rides)
 party=ExplorerParty.new();party.game=self;add_child(party)
 activities=Activities.new();activities.game=self;add_child(activities)
 _arguments()

func _arguments():
 var args=OS.get_cmdline_user_args()
 if "--smoke" in args:_smoke.call_deferred()
 if "--travel-smoke" in args:_travel_smoke.call_deferred()
 if "--size-smoke" in args:_size_smoke.call_deferred()
 if "--ride-smoke" in args:_ride_smoke.call_deferred()
 if "--activity-smoke" in args:_activity_smoke.call_deferred()
 for arg in args:
  if arg.begins_with("--place="):travel.request.call_deferred(arg.trim_prefix("--place="))
  if arg.begins_with("--host="):party.lan.host.call_deferred(int(arg.trim_prefix("--host=")),"--lan-test" in args)
  if arg.begins_with("--join="):party.lan.join.call_deferred(arg.trim_prefix("--join="))
 for arg in args:
  if arg.begins_with("--capture="):_capture.call_deferred(arg.trim_prefix("--capture="))
  if arg.begins_with("--tour-capture="):_tour.call_deferred(arg.trim_prefix("--tour-capture="))
  if arg.begins_with("--quit-frames="):quit_frames=int(arg.trim_prefix("--quit-frames="))

func _physics_process(delta):
 if not controls:return
 ros.poll();tick_player(self,delta)

func tick_player(slot,_delta):
 var input=slot.controls;input.sample()
 if slot==self and activities.editor_open():
  input.neutralize();return
 if slot==self and party and party.menu.visible:
  for action in input.drain():
   if action=="help":party.toggle_menu()
  input.travel_requests.clear();input.size_requests.clear();return
 if party and party.lan.is_client():party.lan.route_local(slot);return
 slot.rides.sample_triggers()
 for id in input.travel_requests:
  if not party or party.can_travel(slot):travel.request(id)
  else:slot.hud.toast("Player 1 chooses travel for the whole group.")
 input.travel_requests.clear()
 for factor in input.size_requests:
  if not slot.pilot.paused:slot.pilot.try_resize(factor)
 input.size_requests.clear()
 for action in input.drain():
  if slot==self and travel_menu.visible and travel_menu.handle_action(action):continue
  if slot==self and activities.handle_action(action):continue
  if slot.rides.handle_action(action):continue
  if action in ["travel_random","travel_home","travel_menu","travel_cancel"] and party and not party.can_travel(slot):slot.hud.toast("Player 1 chooses travel for the whole group.");continue
  match action:
   "travel_random":travel.random_trip()
   "travel_home":
    if travel.busy:travel.cancel()
    travel.request("home_woodland_pond")
   "travel_menu":travel_menu.open()
   "travel_cancel":travel.cancel()
   "next_camera":slot.camera_rig.cycle();slot.hud.toast(ExplorerCamera.NAMES[slot.camera_rig.view_mode]);player_event(slot,"camera_switched",{"camera":ExplorerCamera.NAMES[slot.camera_rig.view_mode]})
   "help":
    if travel.busy and slot==self:travel.cancel()
    else:slot.pilot.paused=not slot.pilot.paused;slot.hud.help.visible=slot.pilot.paused
   "mute":AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0))
   "debug":slot.hud.debug_enabled=not slot.hud.debug_enabled
   _:slot.pilot.request_action(action)

func _process(delta):
 if not hud:return
 clock+=delta;hud.update(delta,pilot,camera_rig,controls,ros);ros.travel_state=travel.state();ros.travel_state.merge(rides.state())
 if party:ros.travel_state.merge(party.state())
 ros.publish(delta,pilot,camera_rig,clock)
 hud.update_place(travel)
 var target=woodland.nearest_fly(pilot.eye_position(),pilot.metrics.tongue_range())
 marker.visible=target>=0
 if target>=0:marker.global_position=woodland.flies[target].node.global_position+Vector3.UP*(.10*pilot.metrics.factor)
 marker.pixel_size=.003*pilot.metrics.factor
 frames+=1
 if quit_frames>0 and frames>=quit_frames:quit_frames=0;shutdown.call_deferred(0)

func _notification(what):
 if what==NOTIFICATION_WM_CLOSE_REQUEST:shutdown.call_deferred(0)

func shutdown(code=0):
 if quitting:return
 quitting=true
 if party:party.shutdown()
 if rides:rides.clear_for_travel()
 if pilot:
  pilot.paused=true
  if pilot.sound:pilot.sound.stop();pilot.sound.stream=null
 if ambience:ambience.stop();ambience.stream=null
 # Give the audio mixer time to release its looping WAV playback.
 await get_tree().create_timer(.15).timeout
 get_tree().quit(code)

func _event(kind,details):
 player_event(self,kind,details)

func player_event(slot,kind,details):
 var target=slot.hud
 if party:
  var record=party.record_for(slot)
  if not record.is_empty():details=details.duplicate();details.player_id=record.key
 if ros:ros.events.append({"event":kind,"data":details})
 if not target:return
 match kind:
  "frog_switched":target.toast(details.species)
  "fly_caught":target.toast("Got it!  %d flies caught."%details.count)
  "climb":target.toast("Climbing · left stick up / down, right stick sideways")
  "water_entry":target.toast("Swimming · right stick up / down to dive or surface")
  "resize_blocked":target.toast(details.reason)
  "silly":target.toast(details.clip.replace("_"," "))

func _capture(path):
 await get_tree().create_timer(3.0).timeout
 await RenderingServer.frame_post_draw
 var image=get_viewport().get_texture().get_image();image.save_png(path)
 print("FROG_CAPTURE "+path)

func _smoke():
 await get_tree().create_timer(.5).timeout
 var script=load("res://scripts/smoke.gd").new();add_child(script);await script.run(self)

func _travel_smoke():
 await get_tree().create_timer(.5).timeout
 var script=load("res://scripts/travel_smoke.gd").new();add_child(script);await script.run(self)

func _size_smoke():
 await get_tree().create_timer(.5).timeout
 var script=load("res://scripts/size_smoke.gd").new();add_child(script);await script.run(self)

func _ride_smoke():
 await get_tree().create_timer(.5).timeout
 var script=load("res://scripts/ride_smoke.gd").new();add_child(script);await script.run(self)

func _activity_smoke():
 await get_tree().create_timer(.3).timeout
 var script=load("res://scripts/activities/activity_smoke.gd").new();add_child(script);await script.run(self)

func _save_view(path):
 await get_tree().create_timer(.8).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(path)
 print("FROG_CAPTURE "+path)

func _tour(folder):
 DirAccess.make_dir_recursive_absolute(folder)
 await get_tree().create_timer(1.0).timeout
 pilot.select_species(2);pilot.reset_position();camera_rig.view_mode=0;camera_rig.initialized=false
 await _save_view(folder+"/overhead.png")
 camera_rig.view_mode=1;camera_rig.initialized=false
 await _save_view(folder+"/behind.png")
 pilot.request_action("jump")
 await get_tree().create_timer(.24).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(folder+"/jump.png")
 await get_tree().create_timer(.55).timeout
 pilot.position=Vector3(.5,-.45,.4);pilot.velocity=Vector3.ZERO;camera_rig.view_mode=2;camera_rig.initialized=false
 await _save_view(folder+"/first_person_water.png")
 var tree=woodland.trees[0];pilot.tree_index=0;pilot.mode="CLIMB";pilot.climb_angle=PI;pilot.position.y=tree.center.y+1.2
 camera_rig.view_mode=1;camera_rig.initialized=false
 hud.toast("Climbing · left stick up / down, right stick sideways")
 controls.remote_move=Vector2(0,-.3);controls.remote_aux=Vector2(.25,0);controls.remote_until=Time.get_ticks_msec()/1000.0+1.1
 await _save_view(folder+"/climbing.png")
 controls.remote_until=0;pilot.reset_position();await shutdown()
