extends SceneTree

var checks=[]
var failures=[]
var game
func _initialize():run.call_deferred()
func wait(seconds:float):await create_timer(seconds).timeout
func check(value:bool,text:String):
 checks.append({"test":text,"passed":value})
 if not value:failures.append(text)
 print(("PASS " if value else "FAIL ")+text)
func button(device:int,index:int,pressed=true):
 var event=InputEventJoypadButton.new();event.device=device;event.button_index=index;event.pressed=pressed;Input.parse_input_event(event)
func axis(device:int,index:int,value:float):
 var event=InputEventJoypadMotion.new();event.device=device;event.axis=index;event.axis_value=value;Input.parse_input_event(event)
func identify(controls:ExplorerControls,name:String,info:Dictionary,guid:String):
 # Device metadata fixtures; actual gameplay input still follows Godot's
 # normalized InputEvent path, just as SDL delivers it for physical hardware.
 controls.device_profile=ExplorerGamepadProfile.describe(name,info,guid,true);controls.device_name=controls.device_profile.display_name
func run():
 var f310=ExplorerGamepadProfile.describe("XInput Gamepad",{"vendor_id":0x046d,"product_id":0xc21d,"xinput_index":0},"test-f310")
 check(f310.family=="Logitech F310" and f310.input_mode=="XInput","F310 USB identity is recognized behind a generic XInput name")
 var named=ExplorerGamepadProfile.describe("Logitech Gamepad F310",{},"test-f310")
 check(named.family=="Logitech F310","SDL F310 name works when USB metadata is unavailable")
 var raw=ExplorerGamepadProfile.describe("Gamepad",{"raw_name":"Logitech G F310"})
 check(raw.family=="Logitech F310","F310 raw OS name is recognized")
 var direct=ExplorerGamepadProfile.describe("Logitech Dual Action",{"vendor_id":0x046d,"product_id":0xc216})
 check(direct.family=="Logitech F310 / Dual Action" and direct.input_mode=="DirectInput","Shared DirectInput identity remains explicitly ambiguous")
 check("If this is an F310/F710" in direct.setup_hint,"Shared USB identities do not imply that an older controller has an X switch")
 var exact=ExplorerGamepadProfile.describe("Logitech F310 Gamepad (DInput)",{"vendor_id":0x046d,"product_id":0xc216})
 check(exact.family=="Logitech F310" and exact.input_mode=="DirectInput","Named F310 DirectInput mode is diagnosed correctly")
 check("X setting" in exact.setup_hint and "MODE light off" in exact.setup_hint,"F310 setup guidance covers analog triggers and the hardware MODE swap")
 var f710=ExplorerGamepadProfile.describe("Gamepad",{"vendor_id":0x046d,"product_id":0xc21f})
 check(f710.family=="Logitech F710" and f710.input_mode=="XInput","F710 recognition remains available")
 var xbox=ExplorerGamepadProfile.describe("Xbox 360 Controller",{"vendor_id":0x045e,"product_id":0x028e,"xinput_index":1})
 check(xbox.family=="Xbox 360 Controller" and xbox.input_mode=="XInput","Other XInput controllers are not mislabeled as Logitech")
 var unmapped=ExplorerGamepadProfile.describe("Unknown controller",{},"unknown",false)
 check(not unmapped.mapped and "mapping is unavailable" in unmapped.setup_hint,"Unmapped controllers have actionable diagnostics")
 check(ExplorerGamepadProfile.for_device(-1).input_mode=="Keyboard","Keyboard fallback is not labeled as a gamepad")
 check("046d:c21d" in ExplorerGamepadProfile.diagnostics(f310) and "test-f310" in ExplorerGamepadProfile.diagnostics(f310),"F2 diagnostics include USB identity and GUID")
 game=load("res://main.tscn").instantiate();root.add_child(game);await wait(.3)
 var inventory=[]
 for id in Input.get_connected_joypads():inventory.append(ExplorerGamepadProfile.for_device(id))
 game.party.records[0].device=40;game.controls.assign_device(40);identify(game.controls,"Logitech F710",{"vendor_id":0x046d,"product_id":0xc21f},"test-f710")
 button(41,JOY_BUTTON_START);await wait(.25)
 check(game.party.records.size()==2,"F310 Start joins an F710 player in split screen")
 if game.party.records.size()!=2:await finish(inventory);return
 var second=game.party.local_records()[1].slot;var p=second.pilot
 identify(second.controls,"Logitech F310",{"vendor_id":0x046d,"product_id":0xc21d},"test-f310")
 await wait(.05)
 check("Logitech F310" in game.party.panels[1].label.text and "Logitech F710" in game.party.panels[0].label.text,"Split-screen HUD identifies each assigned controller")
 var primary=game.pilot.position;var origin=p.position
 axis(41,JOY_AXIS_LEFT_X,1);await wait(.6);axis(41,JOY_AXIS_LEFT_X,0);await wait(.2)
 check(p.position.x>origin.x+.15 and game.pilot.position.distance_to(primary)<.03,"F310 left stick moves its frog independently of F710")
 origin=p.position;button(41,JOY_BUTTON_DPAD_UP);await wait(.4);button(41,JOY_BUTTON_DPAD_UP,false);await wait(.15)
 check(p.position.z<origin.z-.08,"F310 D-pad moves the frog")
 var y=p.position.y;button(41,JOY_BUTTON_X);await wait(.15)
 check(p.position.y>y+.08 and game.pilot.is_on_floor(),"F310 X jumps its own frog")
 await wait(.8)
 var species=p.species;button(41,JOY_BUTTON_LEFT_SHOULDER);await wait(.1)
 check(p.species==posmod(species+1,FrogPilot.SPECIES.size()),"F310 LB changes species")
 button(41,JOY_BUTTON_RIGHT_SHOULDER);await wait(.1)
 check(second.camera_rig.view_mode==1 and game.camera_rig.view_mode==0,"F310 RB changes only its own camera")
 axis(41,JOY_AXIS_TRIGGER_LEFT,.65);await wait(.4);axis(41,JOY_AXIS_TRIGGER_LEFT,0);await wait(.1)
 var grown=p.metrics.factor
 check(grown>1.1 and is_equal_approx(game.pilot.metrics.factor,1),"F310 analog LT grows only its frog")
 axis(41,JOY_AXIS_TRIGGER_RIGHT,.65);await wait(.4);axis(41,JOY_AXIS_TRIGGER_RIGHT,0);await wait(.1)
 check(p.metrics.factor<grown*.95,"F310 analog RT shrinks its frog")
 p.try_resize(1);axis(41,JOY_AXIS_TRIGGER_LEFT,1);axis(41,JOY_AXIS_TRIGGER_RIGHT,1);await wait(.3)
 check(is_equal_approx(p.metrics.factor,1),"F310 independent LT and RT cancel equally held resizing")
 axis(41,JOY_AXIS_TRIGGER_LEFT,0);axis(41,JOY_AXIS_TRIGGER_RIGHT,0)
 button(41,JOY_BUTTON_A);await wait(.1);check(p.current_clip=="Croak","F310 A croaks")
 p.action_timer=0;button(41,JOY_BUTTON_B);await wait(.1);check(p.current_clip in FrogPilot.SILLY,"F310 B chooses a silly animation")
 p.action_timer=0;button(41,JOY_BUTTON_Y);await wait(.1);check(p.current_clip=="Catch_Fly_Swallow","F310 Y attempts a fly catch")
 p.action_timer=0;p.reset_position();await wait(.2)
 button(41,JOY_BUTTON_LEFT_STICK);await wait(.1);check(second.rides.enabled,"F310 L3 selects vehicle triggers")
 axis(41,JOY_AXIS_TRIGGER_LEFT,1);await wait(.2);axis(41,JOY_AXIS_TRIGGER_LEFT,0)
 check(second.rides.kind=="BALLOON" and game.rides.kind=="FOOT","F310 LT calls its balloon without changing the F710 frog")
 if second.rides.kind=="BALLOON":
  var start=second.rides.body.position;axis(41,JOY_AXIS_RIGHT_X,1);axis(41,JOY_AXIS_RIGHT_Y,-1);await wait(.65)
  axis(41,JOY_AXIS_RIGHT_X,0);axis(41,JOY_AXIS_RIGHT_Y,0)
  check(second.rides.body.position.y>start.y+.2 and (second.rides.body.position-start).length()>.4,"F310 right stick controls balloon altitude and strafe")
 second.rides.clear_for_travel();p.reset_position();await wait(.2)
 axis(41,JOY_AXIS_TRIGGER_RIGHT,1);await wait(.2);axis(41,JOY_AXIS_TRIGGER_RIGHT,0)
 check(second.rides.kind=="CAR" and game.rides.kind=="FOOT","F310 RT calls its own convertible in ride mode")
 button(42,JOY_BUTTON_START);await wait(.2)
 var third=game.party.local_records()[2].slot;identify(third.controls,"Logitech F310",{"vendor_id":0x046d,"product_id":0xc21d},"test-f310")
 check(game.party.local_records().size()==3 and second.controls.device==41 and third.controls.device==42,"Two identical F310 identities keep separate device ownership alongside F710")
 game.party._connection(41,false);await wait(.15)
 check(game.party.record_for(third).device==42 and game.controls.device==40,"Unplugging one F310 preserves the other F310 and F710 assignments")
 await finish(inventory)
func finish(inventory:Array):
 var report={"checks":checks,"failures":failures,"connected_devices":inventory,"scope":"Windows headless metadata fixtures plus injected SDL-normalized gamepad input and actual shared-world physics. Connected-device inventory is read-only; physical button presses, raw USB/SDL mapping and Linux/Pi hardware remain untested."}
 var folder=ProjectSettings.globalize_path("res://../state");DirAccess.make_dir_recursive_absolute(folder)
 var file=FileAccess.open(folder+"/gamepad_smoke.json",FileAccess.WRITE)
 if file==null:push_error("Could not write controller acceptance report");await game.shutdown(1);return
 file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("GAMEPAD_SMOKE "+JSON.stringify({"checks":checks.size(),"failures":failures}));await game.shutdown(0 if failures.is_empty() else 1)
