extends Node

var game
var p:FrogPilot
var r:ExplorerRides
var c:ExplorerControls
var checks=[]
var failures=[]
var measurements=[]
func check(value:bool,text:String):
 checks.append({"test":text,"passed":value})
 if not value:failures.append(text)
 print(("PASS " if value else "FAIL ")+text)
func wait(t:float):await get_tree().create_timer(t).timeout
func move(m:Vector2,aux=Vector2.ZERO):
 c.remote_move=m;c.remote_aux=aux;c.remote_until=Time.get_ticks_msec()/1000.0+5
func stop():c.remote_until=0;c.velocity_until=0;c.size_until=0
func axis(index:int,value:float):
 var event=InputEventJoypadMotion.new();event.device=42;event.axis=index;event.axis_value=value;Input.parse_input_event(event)
func trip(id:String):
 game.travel.request(id);var deadline=Time.get_ticks_msec()+15000
 while game.travel.busy and Time.get_ticks_msec()<deadline:await get_tree().process_frame
 check(game.travel.current_id==id,"Travel reaches "+id);await wait(.2)
func await_foot(timeout=5.0):
 var deadline=Time.get_ticks_msec()+int(timeout*1000)
 while r.active() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
 await wait(.1)
func square():
 stop();r.clear_for_travel();p.try_resize(1);p.reset_position(Vector3(20,game.woodland.ground_height(20,0)+.04,0));p.heading=PI;game.camera_rig.view_mode=0;await wait(.2)
func run(owner_game):
 game=owner_game;p=game.pilot;r=game.rides;c=game.controls
 await trip("helsinki_senate_square")
 if game.travel.current_id!="helsinki_senate_square":await finish();return
 await square()
 check(not r.enabled and not r.active(),"Starts with the original size controls")
 r.toggle_profile();check(r.enabled and c.vehicle_triggers,"L3 profile switch enables ride triggers")
 c.device=42;axis(JOY_AXIS_TRIGGER_LEFT,0);axis(JOY_AXIS_TRIGGER_RIGHT,0);await wait(.06);axis(JOY_AXIS_TRIGGER_LEFT,1);await wait(.25)
 check(r.kind=="BALLOON" and is_equal_approx(p.metrics.factor,1),"LT summons a balloon without growing the frog")
 if r.kind!="BALLOON":await finish();return
 for i in range(FrogPilot.SPECIES.size()):
  p.select_species(i);await wait(.06)
  var hand=p.skeleton.find_bone("DEF-hand.L");var grip=p.skeleton.global_transform*p.skeleton.get_bone_global_pose(hand).origin
  check(r.kind=="BALLOON" and grip.y>p.position.y+.2,"Balloon grip pose works for "+FrogPilot.SPECIES[i].name)
 for view in range(3):
  game.camera_rig.view_mode=view;game.camera_rig.initialized=false;await wait(.04)
  check(game.camera_rig.global_position.is_finite(),"Balloon camera %d remains valid"%view)
 game.camera_rig.view_mode=0;game.camera_rig.initialized=false
 var body=r.body;await wait(.2);check(r.body==body and r.kind=="BALLOON","Holding LT does not repeatedly enter or exit")
 axis(JOY_AXIS_TRIGGER_LEFT,0);c._find_device()
 check(p.collision_layer==0 and r.body.collision_layer==1,"Ride collision replaces the frog collision while mounted")
 var y=r.body.position.y;move(Vector2.ZERO,Vector2(0,-1));await wait(.6)
 check(r.body.position.y>y+.3,"Right-stick up raises the helium balloon")
 move(Vector2(0,-1));var start=r.body.position;await wait(.7)
 check(Vector2(r.body.position.x-start.x,r.body.position.z-start.z).length()>.5,"Left stick flies across the city")
 stop();await wait(1.2);y=r.body.position.y;await wait(.4)
 check(absf(r.body.position.y-y)<.08,"Released flight controls settle into a hover")
 for view in range(3):
  game.camera_rig.view_mode=view;game.camera_rig.initialized=false;r.heading=.7;await wait(.05)
  var yaw=r.heading;var origin=r.body.position;var right=game.camera_rig.planar_forward().cross(Vector3.UP)
  move(Vector2.ZERO,Vector2(1,0));await wait(.7)
  var motion=r.body.position-origin
  check(motion.dot(right)>.3 and absf(angle_difference(yaw,r.heading))<.001,"Right-stick strafe translates without turning in camera %d"%view)
  stop();await wait(.85)
 game.camera_rig.view_mode=1;game.camera_rig.initialized=false;await wait(.05)
 var origin=r.body.position;var yaw=r.heading;var right=game.camera_rig.planar_forward().cross(Vector3.UP)
 move(Vector2.ZERO,Vector2(.65,-.65));await wait(.7)
 check((r.body.position-origin).dot(right)>.2 and r.body.position.y>origin.y+.1 and absf(angle_difference(yaw,r.heading))<.001,"Right stick combines balloon altitude and strafe without changing heading")
 stop();await wait(.9);game.camera_rig.view_mode=0;game.camera_rig.initialized=false
 var wall=StaticBody3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(20,12,.2);shape.shape=box;wall.position=r.body.position+Vector3(0,3,-2);wall.add_child(shape);game.add_child(wall);await wait(.06)
 move(Vector2(0,-1));await wait(1.3)
 check(r.body.position.z>wall.position.z+.5,"Balloon swept collision blocks flight through a wall")
 stop();wall.queue_free();await wait(.1);r.exit_ride();await await_foot(7)
 check(not r.active() and p.collision_layer==1 and p.is_on_floor(),"Controlled exit lands and restores a grounded frog")
 await square();r.request("CAR");await wait(.15)
 check(r.kind=="CAR","RT can summon the convertible on dry city paving"+(" ("+r.last_notice+")" if r.kind!="CAR" else ""))
 if r.kind!="CAR":await finish();return
 var wheels=r.prop.find_children("Wheel_*","Node3D",true,false)
 check(wheels.size()==4,"Convertible contains four animatable gold wheels")
 start=r.body.position;move(Vector2(0,-1));await wait(2.2)
 measurements.append({"kind":"car","speed_mps":r.speed,"distance_m":r.body.position.distance_to(start)})
 check(r.speed>15 and r.body.position.distance_to(start)>15,"Convertible accelerates to fast exploration speed")
 var heading=r.heading;move(Vector2(.65,-1));await wait(.5)
 check(absf(angle_difference(heading,r.heading))>.1,"Left stick steers the moving convertible")
 stop();r.exit_ride();await await_foot(3)
 check(not r.active() and p.collision_mask==1,"Controlled exit brakes before stepping out of a moving car")
 await square();r.request("CAR");await wait(.1);move(Vector2(0,-1));await wait(.6);stop();r.request("BALLOON")
 var deadline=Time.get_ticks_msec()+4000
 while r.kind!="BALLOON" and Time.get_ticks_msec()<deadline:await get_tree().process_frame
 check(r.kind=="BALLOON","Switching from a moving car brakes and then launches the balloon")
 if r.active():
  game.travel.request("not_a_place");await wait(.06)
  check(r.kind=="BALLOON","Failed travel leaves the current ride intact")
 await trip("home_woodland_pond")
 check(not r.active() and p.collision_layer==1,"Successful world travel removes the old ride and restores walking")
 var size=p.metrics.factor;r.toggle_profile();check(not r.enabled and is_equal_approx(size,p.metrics.factor),"Returning to size controls preserves frog size")
 r.enabled=true;c.vehicle_triggers=true;p.reset_position(Vector3(4.5,game.woodland.ground_height(4.5,0)+.04,0));p.heading=-PI/2;await wait(.2);r.request("CAR");await wait(.15)
 check(r.kind=="CAR","Convertible can start on the pond bank")
 if r.kind=="CAR":
  move(Vector2(0,-1));await wait(1.2);stop()
  check(not game.woodland.in_water(r.body.position) and r.body.position.y>-.25,"The car stops at water rather than driving along the pond bed")
 r.clear_for_travel();p.reset_position();await wait(.1);p.position=Vector3(0,-.3,0);await wait(.1);r.request("CAR")
 check(not r.active(),"Car deployment is rejected while swimming")
 p.reset_position();await wait(.2);r.enabled=true;c.vehicle_triggers=true
 c.device=42;axis(JOY_AXIS_TRIGGER_LEFT,0);axis(JOY_AXIS_TRIGGER_RIGHT,0);await wait(.1);axis(JOY_AXIS_TRIGGER_LEFT,1);axis(JOY_AXIS_TRIGGER_RIGHT,1);await wait(.15)
 check(not r.active() and is_equal_approx(p.metrics.factor,1),"Both ride triggers together do not summon a vehicle or resize")
 axis(JOY_AXIS_TRIGGER_LEFT,0);axis(JOY_AXIS_TRIGGER_RIGHT,0);c._find_device()
 await trip("helsinki_senate_square");await square();r.request("BALLOON");await wait(.5);r.toggle_profile();await await_foot(5)
 check(not r.active() and not r.enabled and not c.vehicle_triggers,"L3 while flying lands before returning to size controls")
 await test_jump_exits()
 await finish()
func finish():
 stop();r.clear_for_travel()
 var report={"checks":checks,"failures":failures,"measurements":measurements,"scope":"Windows headless Godot physics and internal controller events; physical F710, rendering performance, Linux and Pi untested."}
 var file=FileAccess.open(ProjectSettings.globalize_path("res://../state/ride_smoke.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("RIDE_SMOKE "+JSON.stringify(report));await game.shutdown(0 if failures.is_empty() else 1)

func jump_button():
 c.device=42
 var event=InputEventJoypadButton.new();event.device=42;event.button_index=JOY_BUTTON_X;event.pressed=true;c._input(event)
 await wait(.035);c._find_device()

func gone(node)->bool:return not is_instance_valid(node) or not node.is_inside_tree()

func test_jump_exits():
 await square();r.request("BALLOON");await wait(.1);move(Vector2.ZERO,Vector2(0,-1));await wait(2);stop()
 var original=r.prop;var at=p.position;var selected=p.species
 await jump_button()
 check(r.kind=="PARACHUTE" and gone(original),"Jump immediately removes the balloon and deploys a parachute")
 if r.kind!="PARACHUTE":return
 check(p.position.distance_to(at)<.3 and r.suspension.size()==8,"Parachute deploys at the frog's current airborne position")
 for i in range(FrogPilot.SPECIES.size()):
  p.select_species(i);await wait(.04)
  var left=p.skeleton.global_transform*p.skeleton.get_bone_global_pose(p.skeleton.find_bone("DEF-hand.L")).origin
  var right=p.skeleton.global_transform*p.skeleton.get_bone_global_pose(p.skeleton.find_bone("DEF-hand.R")).origin
  check(left.y>p.position.y+.2 and right.y>p.position.y+.2,"Parachute grips work for "+FrogPilot.SPECIES[i].name)
 c.device=42;axis(JOY_AXIS_TRIGGER_LEFT,0);axis(JOY_AXIS_TRIGGER_RIGHT,0);await wait(.05);axis(JOY_AXIS_TRIGGER_RIGHT,1);await wait(.05)
 check(r.kind=="PARACHUTE" and r.next_ride.is_empty() and not r.body.is_on_floor(),"RT cannot summon or queue a car before parachute touchdown")
 axis(JOY_AXIS_TRIGGER_RIGHT,0);await wait(.05);var canopy=r.prop;axis(JOY_AXIS_TRIGGER_LEFT,1);await wait(.08)
 check(r.kind=="BALLOON" and gone(canopy) and not r.body.is_on_floor(),"LT replaces the parachute with a new balloon while still airborne")
 axis(JOY_AXIS_TRIGGER_LEFT,0);c._find_device();await jump_button();await wait(.45)
 check(r.kind=="PARACHUTE" and r.body.velocity.y<0 and r.body.velocity.y>=-2.01,"Parachute descends at a controlled terminal speed")
 await await_foot(8)
 check(not r.active() and p.is_on_floor() and r.suspension.is_empty(),"Touchdown stows the parachute and restores walking")
 r.request("CAR");await wait(.15);check(r.kind=="CAR","A car is available after actual touchdown")
 if r.kind!="CAR":return
 move(Vector2(0,-1));await wait(2.1)
 var before=Vector2(r.body.velocity.x,r.body.velocity.z).length();var car=r.prop;at=p.position
 p.paused=true;await jump_button();check(r.kind=="CAR" and not gone(car),"Jump while paused does not eject the rider");p.paused=false
 await jump_button()
 check(r.kind=="COAST" and gone(car) and r.prop==null,"Jump immediately removes the convertible")
 if r.kind!="COAST":return
 var initial=Vector2(r.body.velocity.x,r.body.velocity.z).length()
 check(initial>before*.8 and r.body.velocity.y>0 and p.position.distance_to(at)<1.5,"Car jump preserves forward momentum and launches the frog without teleporting")
 var coast_start=r.body.position;await wait(.3)
 check(r.speed<initial-1 and r.body.position.distance_to(coast_start)>1,"The frog visibly coasts forward while decelerating")
 move(Vector2(0,-1));await wait(2.2)
 check(r.kind=="COAST" and r.speed<.01,"Held car throttle cannot reaccelerate the exited frog")
 stop();await await_foot(2)
 check(not r.active() and Vector2(p.velocity.x,p.velocity.z).length()<.01,"Coasting comes to rest and releasing the stick restores walking")
 measurements.append({"kind":"car_jump","inherited_mps":before,"initial_coast_mps":initial})
 p.select_species(selected)
