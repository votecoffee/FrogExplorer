extends Node

var failures=[]
var checks=[]
func check(condition,message):
 checks.append({"check":message,"passed":bool(condition)})
 if not condition:failures.append(message)

func wait(seconds=.15):
 await get_tree().create_timer(seconds).timeout

func run(game):
 var p=game.pilot
 await wait(.25)
 if "--require-ros" in OS.get_cmdline_user_args():check(game.ros.connected,"Windows launcher starts a connected ROS bridge")
 check(p.is_on_floor(),"Spawn has physical ground contact")
 check(game.woodland.trees.size()>=20 and game.woodland.flies.size()>=12,"Woodland contains trees and catchable flies")
 for i in range(FrogPilot.SPECIES.size()):
  p.select_species(i);await wait(.05);check(p.player.get_animation_list().size()==28,"All 28 clips load for "+FrogPilot.SPECIES[i].name)
 check(p.species==FrogPilot.SPECIES.size()-1,"All registered species can be selected")
 check(FrogPilot.SPECIES[p.species].file=="american_toad","American toad is selectable")
 check(p.sound.stream==load("res://assets/audio/american_toad.wav"),"American toad loads its authored trill")
 p.request_action("next_frog");check(p.species==0,"Species cycle wraps after American toad")
 p.select_species(FrogPilot.SPECIES.size()-1)
 var base_camera=game.camera_rig.view_mode
 for i in range(3):game.camera_rig.cycle()
 check(game.camera_rig.view_mode==base_camera,"Three camera modes cycle correctly")
 for button in [JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_A,JOY_BUTTON_B,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]:
  game.controls.device=42;var event=InputEventJoypadButton.new();event.device=42;event.button_index=button;event.pressed=true;game.controls._input(event)
  check(game.controls.pending.size()>0,"Gamepad button maps: "+str(button));game.controls.pending.clear()
 game.controls._find_device()
 game.camera_rig.view_mode=1;p.reset_position();await wait(.1)
 var steer_start=p.heading;game.controls.remote_move=Vector2(.8,0);game.controls.remote_aux=Vector2.ZERO;game.controls.remote_until=Time.get_ticks_msec()/1000.0+.3
 await wait(.15);check(angle_difference(steer_start,p.heading)<-.05,"Right stick direction on left control steers right in chase view")
 game.controls.remote_until=0;game.camera_rig.view_mode=0
 p.reset_position();await wait(.25);var y=p.position.y;p.request_action("jump");await wait(.12);check(p.position.y>y+.08,"Jump lifts the physical character")
 p.action_timer=0;p.position=Vector3(0,-.3,0);p.velocity=Vector3.ZERO;await wait(.12);check(p.mode=="SWIM","Entering pond switches to swimming")
 check(p.current_clip=="Water_Entry","Pond entry plays its transition clip")
 game.controls.remote_aux=Vector2(0,1);game.controls.remote_move=Vector2.ZERO;game.controls.remote_until=Time.get_ticks_msec()/1000.0+1
 var depth=p.position.y;await wait(.35);check(p.position.y<depth-.03,"Right-stick down dives below the surface")
 game.controls.remote_until=0
 await wait(.25);check(p.current_clip=="Swim","Water entry settles into swimming")
 p.position=game.woodland.spawn_point;p.velocity=Vector3.ZERO;await wait(.12)
 check(p.mode=="LAND" and p.current_clip=="Shore_Exit","Leaving the pond plays shore exit")
 await wait(.65);check(p.current_clip=="Living_Idle","Shore exit returns to the land idle")
 p.request_action("croak");p.position=Vector3(0,-.3,0);p.velocity=Vector3.ZERO;await wait(.12)
 check(p.current_clip=="Croak" and p.mode=="SWIM","Pond entry preserves an active croak")
 p.action_timer=0;p.mode="LAND";p.position=Vector3(0,-.3,0);await wait(.12)
 p.position=game.woodland.spawn_point;p.velocity=Vector3.ZERO;await wait(.12)
 check(p.current_clip=="Shore_Exit","Reversing a pond crossing replaces the transition")
 p.position=Vector3(0,-.3,0);p.velocity=Vector3.ZERO;await wait(.12);p.request_action("croak")
 check(p.current_clip=="Croak","Action buttons can interrupt a water transition")
 p.action_timer=0;p.mode="LAND";p.position=Vector3(0,-.3,0);await wait(.12);p.request_action("jump")
 check(p.current_clip=="Big_Jump" and p.mode=="LAND","Jump interrupts water entry and exits the pond")
 for index in range(FrogPilot.SPECIES.size()):
  p.reset_position();p.select_species(index);await wait(.05)
  p.position=Vector3(0,-.3,0);p.velocity=Vector3.ZERO;await wait(.08)
  check(p.current_clip=="Water_Entry","Water entry clip plays for "+FrogPilot.SPECIES[index].name)
  p.position=game.woodland.spawn_point;p.velocity=Vector3.ZERO;await wait(.08)
  check(p.current_clip=="Shore_Exit","Shore exit clip plays for "+FrogPilot.SPECIES[index].name)
 p.reset_position();await wait(.2)
 var tree=game.woodland.trees[0];p.position=tree.center+Vector3(0,0,tree.radius+.30);p.position.y=game.woodland.ground_height(p.position.x,p.position.z)+.01;p.grab_cooldown=0
 game.controls.remote_move=Vector2(0,-1);game.controls.remote_aux=Vector2.ZERO;game.controls.remote_until=Time.get_ticks_msec()/1000.0+3
 await wait(.5);check(p.mode=="CLIMB","Moving into trunk automatically engages climbing")
 if p.mode=="CLIMB":
  var height=p.position.y;game.controls.remote_aux=Vector2(.8,0);var angle=p.climb_angle;await wait(.4)
  check(p.position.y>height+.08,"Left-stick up climbs the trunk")
  check(absf(p.climb_angle-angle)>.1,"Right-stick strafe traverses around the trunk")
  var spine=p.skeleton.get_bone_global_pose(p.skeleton.find_bone("DEF-spine.003")).basis.get_rotation_quaternion()
  var back=(p.skeleton.global_basis*((spine*p.idle_spine_rotation.inverse())*Vector3.UP)).normalized()
  check(back.dot(p.facing_basis().y)>.70,"Climbing back faces outward from trunk")
  for index in range(FrogPilot.SPECIES.size()):
   p.select_species(index);await wait(.20)
   var rotation=p.skeleton.get_bone_global_pose(p.skeleton.find_bone("DEF-spine.003")).basis.get_rotation_quaternion()
   var facing=(p.skeleton.global_basis*((rotation*p.idle_spine_rotation.inverse())*Vector3.UP)).normalized()
   check(facing.dot(p.facing_basis().y)>.70,"Correct wall orientation: "+FrogPilot.SPECIES[index].name)
  p.request_action("jump");check(p.mode!="CLIMB","Jump detaches from the tree")
 game.controls.remote_until=0;p.reset_position();await wait(.2);p.action_timer=0
 var fly=game.woodland.flies[0];fly.home=p.eye_position()+Vector3(0,0,-.45);fly.respawn=0;await wait(.05)
 var count=p.flies_caught;p.request_action("catch_fly");await wait(.5);check(p.flies_caught==count+1,"Tongue action catches a nearby fly")
 p.action_timer=0;p.request_action("croak");check(p.current_clip=="Croak","A action plays croak")
 p.action_timer=0;p.request_action("silly");check(p.current_clip in FrogPilot.SILLY,"B action selects a silly animation")
 game.controls.remote_until=0;game.controls.velocity_until=0
 game.controls.accept_remote({"kind":"velocity","forward":.4,"ttl":.1});check(game.controls.velocity_active(),"ROS velocity command becomes active")
 await wait(.2);check(not game.controls.velocity_active(),"ROS velocity command expires without renewal")
 var path=ProjectSettings.globalize_path("res://../state/game_smoke.json")
 var report={"engine":Engine.get_version_info(),"checks":checks,"failures":failures,"gamepads":Input.get_connected_joypads(),"scope":"Windows game logic and injected SDL-style input; physical F710, Linux and Pi untested."}
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
 print("FROG_SMOKE "+JSON.stringify(report));await game.shutdown(0 if failures.is_empty() else 1)
