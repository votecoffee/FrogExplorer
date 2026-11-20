extends Node

var checks=[]
var failures=[]
var measurements=[]
var game
var p:FrogPilot
var c:ExplorerControls

func check(ok:bool,text:String):
 checks.append({"test":text,"passed":ok})
 if not ok:failures.append(text)
 print(("PASS " if ok else "FAIL ")+text)

func wait(seconds:float):await get_tree().create_timer(seconds).timeout

func trip(id:String):
 game.travel.request(id)
 var deadline=Time.get_ticks_msec()+15000
 while game.travel.busy and Time.get_ticks_msec()<deadline:await get_tree().process_frame
 check(not game.travel.busy and game.travel.current_id==id,"Scaled travel reaches "+id)
 await wait(.25)

func stop():
 c.remote_until=0;c.velocity_until=0;c.size_until=0;c.remote_move=Vector2.ZERO;c.remote_aux=Vector2.ZERO

func place_on_square():
 stop();p.release_contacts();p.action_timer=0;p.mode="LAND";p.heading=PI
 p.position=Vector3(20,game.woodland.ground_height(20,0)+.04*p.metrics.factor,0)
 p.velocity=Vector3.ZERO;await wait(.2)

func axis(index:int,value:float):
 var event=InputEventJoypadMotion.new();event.device=42;event.axis=index;event.axis_value=value;Input.parse_input_event(event)

func key(code:int,pressed:bool):
 var event=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=pressed;Input.parse_input_event(event)

func move(stick:Vector2,aux=Vector2.ZERO):
 c.remote_move=stick;c.remote_aux=aux;c.remote_until=Time.get_ticks_msec()/1000.0+3

func obstacle(at:Vector3,dimensions:Vector3)->StaticBody3D:
 var body=StaticBody3D.new();body.position=at;var collision=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=dimensions;collision.shape=shape;body.add_child(collision);game.add_child(body);return body

func run(owner_game):
 game=owner_game;p=game.pilot;c=game.controls
 await trip("helsinki_senate_square")
 if game.travel.current_id!="helsinki_senate_square":await finish();return
 await place_on_square()
 check(is_equal_approx(c.resize_axis(1,0),1) and is_equal_approx(c.resize_axis(0,1),-1),"LT grows and RT shrinks on the standard trigger axes")
 check(is_zero_approx(c.resize_axis(1,1)) and is_zero_approx(c.resize_axis(.03,.02)),"Equal triggers cancel and trigger noise stays in the dead zone")
 c.device=42;axis(JOY_AXIS_TRIGGER_LEFT,1);await wait(.4);axis(JOY_AXIS_TRIGGER_LEFT,0)
 check(p.metrics.factor>1.25 and p.metrics.factor<1.4,"Injected LT motion grows continuously at the selected rate")
 var held=p.metrics.factor;axis(JOY_AXIS_TRIGGER_LEFT,1);axis(JOY_AXIS_TRIGGER_RIGHT,1);await wait(.2)
 check(absf(p.metrics.factor-held)<.02,"Holding both triggers keeps the current size")
 axis(JOY_AXIS_TRIGGER_LEFT,0);await wait(.4);axis(JOY_AXIS_TRIGGER_RIGHT,0);c._find_device()
 check(absf(p.metrics.factor-1)<.06,"Injected RT motion reverses growth")
 p.try_resize(1);key(KEY_EQUAL,true);await wait(.25);key(KEY_EQUAL,false)
 check(p.metrics.factor>1.1,"Keyboard plus/equal holds grow the frog")
 key(KEY_MINUS,true);await wait(.25);key(KEY_MINUS,false)
 check(absf(p.metrics.factor-1)<.05,"Keyboard minus holds shrink the frog")
 p.try_resize(2);key(KEY_0,true);key(KEY_0,false);await wait(.05)
 check(is_equal_approx(p.metrics.factor,1),"Keyboard zero restores baseline size")
 c.device=42;p.paused=true;axis(JOY_AXIS_TRIGGER_LEFT,1);held=p.metrics.factor;await wait(.2)
 check(is_equal_approx(p.metrics.factor,held),"Pause prevents trigger resizing")
 axis(JOY_AXIS_TRIGGER_LEFT,0);p.paused=false;c._find_device()
 for size in [.25,.5,1.0,2.0,4.0,8.0,16.0]:
  await place_on_square();check(p.try_resize(size),"Clear city paving accepts %.2fx"%size)
  await wait(.12)
  check(is_equal_approx(p.collision_shape.shape.radius,.13*size) and is_equal_approx(p.collision_shape.shape.height,.30*size) and is_equal_approx(p.model.scale.x,2.8*size),"Visual and capsule dimensions agree at %.2fx"%size)
  move(Vector2(0,-1));await wait(.2)
  var early=Vector2(p.velocity.x,p.velocity.z).length()/size
  check(early>.07 and early<.22,"Walking ramps up at %.2fx"%size)
  await wait(.65)
  var origin=p.position;var start=game.clock;await wait(.35)
  var speed=Vector2(p.position.x-origin.x,p.position.z-origin.z).length()/(game.clock-start)
  measurements.append({"kind":"walk","scale":size,"expected_mps":.52*size,"measured_mps":speed})
  check(absf(speed/(.52*size)-1)<.15,"Physical walking speed is proportional at %.2fx"%size)
  check(absf(p.player.speed_scale-2.6)<.15,"Walking cadence stays consistent at %.2fx"%size)
  stop();await wait(.25)
 check(p.try_resize(100) and is_equal_approx(p.metrics.factor,16),"Growth clamps at 16x")
 check(p.try_resize(.01) and is_equal_approx(p.metrics.factor,.25),"Shrink clamps at 0.25x")
 p.try_resize(1);await place_on_square()
 var feet=p.position;var beam=obstacle(feet+Vector3(0,.85,0),Vector3(6,.2,6));await wait(.06)
 check(not p.try_resize(4) and p.metrics.factor>2 and p.metrics.factor<2.51,"Growth stops at the largest capsule below a ceiling")
 check(p.position.distance_to(feet)<.02 and p.resize_blocked,"Blocked growth preserves the foot anchor and reports the obstruction")
 check(p.try_resize(.5),"Shrinking remains available beneath an obstacle")
 beam.queue_free();await wait(.06);p.try_resize(1);await place_on_square()
 feet=p.position;var wall=obstacle(feet+Vector3(.65,3,0),Vector3(.2,6,6));await wait(.06)
 check(not p.try_resize(16) and p.metrics.radius()<.551,"A nearby wall blocks expansion of the physical body")
 check(p.position.distance_to(feet)<.02,"Resizing cannot teleport through a wall")
 wall.queue_free();await wait(.06)
 for size in [1.0,4.0]:
  p.try_resize(size);await place_on_square()
  c.accept_remote({"kind":"velocity","forward":.4,"ttl":.5});await wait(.2)
  var origin=p.position;var start=game.clock;await wait(.18)
  var speed=Vector2(p.position.x-origin.x,p.position.z-origin.z).length()/(game.clock-start)
  check(absf(speed-.4)<.075,"External SI velocity remains 0.4 m/s at %.0fx"%size)
  stop()
 var jumps=[]
 for size in [1.0,4.0]:
  p.try_resize(size);await place_on_square();p.action_timer=0
  var origin=p.position;var start=game.clock;var highest=origin.y;var airborne=false
  p.request_action("jump");var duration=p.jump_duration;var deadline=Time.get_ticks_msec()+4000
  while Time.get_ticks_msec()<deadline:
   await get_tree().physics_frame;highest=maxf(highest,p.position.y)
   if not p.is_on_floor():airborne=true
   if airborne and p.is_on_floor():break
  var distance=Vector2(p.position.x-origin.x,p.position.z-origin.z).length()
  jumps.append({"scale":size,"height":highest-origin.y,"range":distance,"airtime":game.clock-start})
  measurements.append({"kind":"jump","scale":size,"height":highest-origin.y,"range":distance,"airtime":game.clock-start})
  check(airborne and p.is_on_floor() and is_equal_approx(duration,.68*sqrt(size)),"Jump takes off, lands and uses the scaled clip duration at %.0fx"%size)
 check(absf(jumps[1].height/jumps[0].height-4)<.6,"Jump height scales with size under fixed gravity")
 check(absf(jumps[1].range/jumps[0].range-4)<.8,"Jump range scales with size under fixed gravity")
 p.try_resize(4);await place_on_square();p.action_timer=0;p.request_action("jump");await wait(.1)
 var vy=p.velocity.y;var duration=p.jump_duration;p.try_resize(8);p.request_action("jump")
 check(is_equal_approx(p.velocity.y,vy) and is_equal_approx(p.jump_duration,duration),"Midair resizing does not add launch energy or retime the active jump")
 await wait(1.5);p.action_timer=0;await place_on_square();p.try_resize(4)
 for index in range(FrogPilot.SPECIES.size()):
  p.select_species(index);await wait(.05)
  check(is_equal_approx(p.metrics.factor,4) and is_equal_approx(p.model.scale.x,11.2),"Switching species preserves size: "+FrogPilot.SPECIES[index].name)
 for view in range(3):
  game.camera_rig.view_mode=view;game.camera_rig.initialized=false;await wait(.05)
  check(is_equal_approx(game.camera_rig.near,.1) and game.camera_rig.global_position.distance_to(p.eye_position())>0,"Camera %d uses scaled clipping and a valid position"%view)
 game.camera_rig.view_mode=0;game.camera_rig.initialized=false
 check(p.try_resize(16),"City supports the maximum size before travel")
 await trip("home_woodland_pond")
 check(is_equal_approx(p.metrics.factor,1) and p.is_on_floor(),"Travelling home resets a giant frog to its default size")
 check(is_equal_approx(p.collision_shape.shape.radius,.13) and is_equal_approx(p.collision_shape.shape.height,.30) and is_equal_approx(p.model.scale.x,2.8) and is_equal_approx(game.camera_rig.near,.025),"Travel resets visual, collision and camera dimensions together")
 p.try_resize(2)
 check(p.reset_position() and is_equal_approx(p.metrics.factor,2),"Local recovery preserves the size selected after arrival")
 for size in [.5,2.0]:
  p.try_resize(size);p.release_contacts();p.action_timer=0;p.position=Vector3(0,-.2*size,0);p.velocity=Vector3.ZERO;await wait(.12)
  check(p.mode=="SWIM","Pond supports swimming at %.1fx"%size)
  move(Vector2(0,-1));await wait(.3)
  var origin=p.position;var start=game.clock;await wait(.25)
  var speed=Vector2(p.position.x-origin.x,p.position.z-origin.z).length()/(game.clock-start)
  check(absf(speed/(.68*size)-1)<.18,"Swimming speed is proportional at %.1fx"%size)
  move(Vector2.ZERO,Vector2(0,1));await wait(.35)
  check(absf(p.velocity.y/(-.60*size)-1)<.18,"Right-stick dive speed is proportional at %.1fx"%size)
  stop()
 p.try_resize(2);p.reset_position();p.action_timer=0;await wait(.1)
 var fly=game.woodland.flies[0];fly.home=p.eye_position()+Vector3(0,0,-2);fly.respawn=0;await wait(.05)
 var caught=p.flies_caught;p.request_action("catch_fly");await wait(.5)
 check(p.flies_caught==caught+1,"A larger frog can catch a fly beyond the baseline tongue range")
 p.action_timer=0
 p.try_resize(1);p.reset_position();await wait(.15)
 for size in [.5,2.0]:
  p.try_resize(size);p.reset_position();p.action_timer=0;var tree=game.woodland.trees[0]
  p.position=tree.center+Vector3(0,.02*size,tree.radius+.20*size);p.grab_cooldown=0;p.velocity=Vector3.ZERO
  move(Vector2(0,-1));await wait(.4)
  check(p.mode=="CLIMB","Automatic climbing still engages at %.1fx"%size)
  if p.mode=="CLIMB":
   var y=p.position.y;var start=game.clock;await wait(.25)
   check(absf((p.position.y-y)/(game.clock-start)/(.65*size)-1)<.18,"Climbing speed is proportional at %.1fx"%size)
   var tree_data=game.woodland.trees[p.tree_index];p.try_resize(16)
   check(p.resize_blocked and p.metrics.radius()<=tree_data.radius*2+.002,"A small trunk limits growth while attached")
  stop();p.try_resize(1);p.reset_position();await wait(.1)
 await trip("helsinki_senate_square");await place_on_square();p.try_resize(1)
 c.accept_remote({"kind":"axes","move":[0,0],"aux":[0,0],"size_axis":1,"ttl":.1});await wait(.2)
 held=p.metrics.factor;await wait(.2)
 check(held>1 and is_equal_approx(held,p.metrics.factor),"Remote trigger resizing expires without renewal")
 c.accept_remote({"kind":"size","factor":8});await wait(.1)
 check(is_equal_approx(p.metrics.factor,8),"Absolute size protocol request resizes through the clearance check")
 c.accept_remote({"kind":"action","action":"reset_size"});await wait(.1)
 check(is_equal_approx(p.metrics.factor,1),"Protocol reset restores baseline size")
 await finish()

func finish():
 stop()
 var report={"checks":checks,"failures":failures,"measurements":measurements,"scope":"Windows headless Godot physics, internal keyboard/gamepad events and loopback command injection; physical F710, graphical performance, Linux and Pi untested."}
 var file=FileAccess.open(ProjectSettings.globalize_path("res://../state/size_smoke.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("SIZE_SMOKE "+JSON.stringify(report));await game.shutdown(0 if failures.is_empty() else 1)
