extends SceneTree

var game
var checks=[]
var failures=[]
func _initialize():run.call_deferred()
func wait(seconds:float):await create_timer(seconds).timeout
func check(value:bool,text:String):
 checks.append({"test":text,"passed":value})
 if not value:failures.append(text)
 print(("PASS " if value else "FAIL ")+text)
func button(device:int,index:int):
 var event=InputEventJoypadButton.new();event.device=device;event.button_index=index;event.pressed=true;Input.parse_input_event(event)
func axis(device:int,index:int,value:float):
 var event=InputEventJoypadMotion.new();event.device=device;event.axis=index;event.axis_value=value;Input.parse_input_event(event)
func key(index:int):
 var event=InputEventKey.new();event.physical_keycode=index;event.pressed=true;Input.parse_input_event(event)
func trip(id:String):
 game.travel.request(id);var deadline=Time.get_ticks_msec()+15000
 while game.travel.busy and Time.get_ticks_msec()<deadline:await process_frame
 await wait(.3);check(game.travel.current_id==id,"Party travels to "+id)
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await wait(.3)
 var party:ExplorerParty=game.party
 party.records[0].device=40;game.controls.assign_device(40)
 check(party.records.size()==1 and party.panels.is_empty(),"Single-player retains the original full-screen view")
 button(41,JOY_BUTTON_START);await wait(.3)
 check(party.local_records().size()==2 and party.panels.size()==2,"Start on a second controller creates two split-screen players")
 if party.records.size()!=2:await finish();return
 var second=party.local_records()[1].slot;var a=game.pilot;var b=second.pilot
 check(not b.paused,"The joining Start press does not pause the new frog")
 check(game.controls.device==40 and second.controls.device==41,"Controllers have stable, separate owners")
 check(party.panels[0].viewport.world_3d==party.panels[1].viewport.world_3d,"Both cameras render the same physics world")
 check(party.panels[0].camera==game.camera_rig and party.panels[1].camera==second.camera_rig,"Each split view has its own current camera")
 check(party.panels[0].container.position==Vector2.ZERO and party.panels[1].container.position.x>0 and party.panels[1].container.position.y==0,"Two players use a complete left/right layout")
 check(not game.hud.visible and party.panels[1].label.visible,"Compact per-player HUD replaces the full-screen HUD")
 var species=a.species;var previous=b.species
 button(41,JOY_BUTTON_LEFT_SHOULDER);await wait(.12)
 check(a.species==species and b.species==posmod(previous+1,FrogPilot.SPECIES.size()),"LB changes only the owning controller's frog")
 button(41,JOY_BUTTON_RIGHT_SHOULDER);await wait(.12)
 check(game.camera_rig.view_mode==0 and second.camera_rig.view_mode==1,"RB changes only that player's camera")
 second.camera_rig.view_mode=0
 var origin=a.position;var other=b.position
 axis(41,JOY_AXIS_LEFT_X,1);await wait(.6);axis(41,JOY_AXIS_LEFT_X,0);await wait(.2)
 check(b.position.x>other.x+.15 and a.position.distance_to(origin)<.03,"Player 2 stick moves only Player 2")
 axis(40,JOY_AXIS_TRIGGER_LEFT,1);await wait(.4);axis(40,JOY_AXIS_TRIGGER_LEFT,0);await wait(.1)
 check(a.metrics.factor>1.2 and is_equal_approx(b.metrics.factor,1),"LT resizing is isolated per player")
 a.try_resize(1)
 var y=b.position.y;button(41,JOY_BUTTON_X);await wait(.13)
 check(b.position.y>y+.08 and a.is_on_floor(),"X jumps only the owning frog")
 await wait(.7)
 button(41,JOY_BUTTON_START);await wait(.05)
 check(b.paused and not a.paused,"Start pauses one frog without freezing the other")
 button(41,JOY_BUTTON_START);await wait(.05)
 key(KEY_TAB);await wait(.08)
 check(a.species==posmod(species+1,FrogPilot.SPECIES.size()) and b.species==posmod(previous+1,FrogPilot.SPECIES.size()),"Keyboard actions belong to Player 1 only")
 # First person must hide only the viewer, with independent fog and canopies.
 game.camera_rig.view_mode=2;second.camera_rig.view_mode=0;await wait(.1)
 check(a.model.visible and (game.camera_rig.cull_mask&a.render_layer)==0 and (second.camera_rig.cull_mask&a.render_layer)!=0,"First person hides its frog only in its own camera")
 check(game.camera_rig.environment!=second.camera_rig.environment,"Split-screen cameras have separate environment resources")
 game.camera_rig.view_mode=0
 a.position=Vector3(0,-.4,0);a.velocity=Vector3.ZERO;await wait(.15)
 check(a.mode=="SWIM" and b.mode=="LAND","One frog can swim while the other stays on land")
 check(game.camera_rig.environment.fog_density!=second.camera_rig.environment.fog_density or not game.woodland.in_water(game.camera_rig.global_position),"Per-camera water fog does not overwrite the other view")
 a.reset_position();await wait(.15)
 var tree=game.woodland.trees[0];b.position=tree.center+Vector3(0,.3,tree.radius+.3);b.grab_cooldown=0
 axis(41,JOY_AXIS_LEFT_Y,-1);await wait(.55);axis(41,JOY_AXIS_LEFT_Y,0)
 check(b.mode=="CLIMB" and a.mode=="LAND","Player 2 can climb independently")
 second.controls.neutralize();second.rides.clear_for_travel();b.reset_position();await wait(.2)
 second.rides.request("BALLOON");await wait(.15)
 check(second.rides.kind=="BALLOON" and game.rides.kind=="FOOT","Each player owns their own vehicle")
 if second.rides.kind=="BALLOON":
  var start=second.rides.body.position;axis(41,JOY_AXIS_RIGHT_Y,-1);axis(41,JOY_AXIS_RIGHT_X,1);await wait(.6)
  axis(41,JOY_AXIS_RIGHT_Y,0);axis(41,JOY_AXIS_RIGHT_X,0)
  check(second.rides.body.position.y>start.y+.2 and (second.rides.body.position-start).length()>.4,"Player 2 balloon altitude and strafe use only its right stick")
  button(41,JOY_BUTTON_X);await wait(.05);check(second.rides.kind=="PARACHUTE","Player 2 can jump out into its own parachute")
 await trip("helsinki_senate_square")
 check(a.woodland==b.woodland and a.woodland==game.woodland,"Travel updates every player's world reference")
 check(game.rides.kind=="FOOT" and second.rides.kind=="FOOT" and is_equal_approx(a.metrics.factor,1) and is_equal_approx(b.metrics.factor,1),"Group travel clears all rides and restores all frogs to 1x")
 check(a.is_on_floor() and b.is_on_floor() and a.position.distance_to(b.position)>.3,"Group arrival places both frogs on checked, separated ground")
 var place=game.travel.current_id;button(41,JOY_BUTTON_BACK);await wait(.1)
 check(not game.travel.busy and game.travel.current_id==place,"Player 2 cannot unexpectedly travel the whole group")
 button(42,JOY_BUTTON_START);button(43,JOY_BUTTON_START);await wait(.3)
 check(party.records.size()==4 and party.panels.size()==4,"Four local controllers receive four viewports")
 check(party.panels[2].container.position.y>0 and party.panels[3].container.position.y>0,"Three/four players use a two-by-two grid")
 button(44,JOY_BUTTON_START);await wait(.1)
 check(party.records.size()==4,"A fifth local controller cannot exceed the four-player limit")
 var keep=party.local_records()[2].slot
 party._connection(41,false);await wait(.15)
 check(party.records.size()==3 and party.record_for(keep).device==42,"Disconnect removes only its player and keeps other controller assignments")
 party._connection(43,false);party._connection(42,false);await wait(.2)
 check(party.records.size()==1 and party.panels.is_empty() and game.hud.visible,"Removing extra controllers restores full screen and the standard HUD")
 party._connection(40,false);await wait(.1)
 check(game.controls.device==-1 and game.controls.keyboard_enabled and game.hud.keyboard_legend.visible,"Player 1 disconnect restores the keyboard legend")
 check(game.controls.move==Vector2.ZERO and game.controls.size_axis==0,"Disconnected inputs cannot leave movement or resizing held")
 await trip("home_woodland_pond")
 await finish()
func finish():
 var report={"checks":checks,"failures":failures,"scope":"Windows headless actual viewports, shared physics and injected gamepad/keyboard events; no desktop input or screen capture. Physical multiple F710 and rendered performance untested."}
 var file=FileAccess.open(ProjectSettings.globalize_path("res://../state/party_smoke.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("PARTY_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}));await game.shutdown(0 if failures.is_empty() else 1)
