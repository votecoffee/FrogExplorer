class_name ExplorerRides
extends Node3D

# Arcade exploration vehicles. The frog and its saved size stay intact; a
# separate swept kinematic body owns motion while a ride is active.
var game
var pilot:FrogPilot
var controls:ExplorerControls
var enabled=false
var kind="FOOT"
var body:CharacterBody3D
var collision:CollisionShape3D
var prop:Node3D
var rope:MeshInstance3D
var suspension:Array[MeshInstance3D]=[]
var ride_scale=1.0
var speed=0.0
var steering=0.0
var age=0.0
var heading=0.0
var last_dry=Vector3.ZERO
var landing=false
var exit_pending=false
var next_ride=""
var trigger_armed=false
var profile_after_exit=false
var notice_after=0
var last_notice=""
var last_pose_species=-1

func active()->bool:return kind!="FOOT"

func notify(text:String):
 last_notice=text
 if Time.get_ticks_msec()>notice_after:
  notice_after=Time.get_ticks_msec()+1200;game.hud.toast(text)

func toggle_profile():
 if pilot.paused:return
 if active():
  profile_after_exit=true;exit_ride();return
 enabled=not enabled;controls.vehicle_triggers=enabled;controls.size_axis=0;trigger_armed=false
 game.hud.toast("Ride triggers: LT balloon / RT convertible" if enabled else "Size triggers: LT grow / RT shrink")
 game._event("trigger_mode",{"mode":"rides" if enabled else "size"})

func sample_triggers():
 if not enabled or pilot.paused:return
 if not controls.hardware_enabled and Time.get_ticks_msec()/1000.0>=controls.remote_until:return
 var t=controls.triggers
 if t.x<.2 and t.y<.2:trigger_armed=true
 if not trigger_armed:return
 if t.x>.55 and t.y>.55:trigger_armed=false;return
 if t.x>.55:trigger_armed=false;request("BALLOON")
 elif t.y>.55:trigger_armed=false;request("CAR")

func handle_action(action:String)->bool:
 match action:
  "toggle_trigger_mode":toggle_profile();return true
  "ride_balloon":request("BALLOON");return true
  "ride_car":request("CAR");return true
  "ride_exit":exit_ride();return true
 if not active():return false
 if action=="jump":
  if not pilot.paused:jump_out()
  return true
 if action=="reset":
  clear_for_travel();pilot.reset_position();return true
 if action=="reset_size":notify("Step off the ride before resizing.");return true
 return false

func _shape(ride:String)->Shape3D:
 if ride in ["PARACHUTE","COAST"]:return FrogBodyMetrics.capsule(ride_scale)
 var shape=CapsuleShape3D.new()
 shape.radius=(.54 if ride=="BALLOON" else .38)*ride_scale
 shape.height=(2.90 if ride=="BALLOON" else 1.50)*ride_scale
 return shape

func _shape_transform(ride:String,foot:Vector3,yaw:float)->Transform3D:
 var rotation=Basis(Vector3.UP,yaw)
 if ride=="CAR":rotation=rotation*Basis(Vector3.RIGHT,PI/2)
 return Transform3D(rotation,foot+Vector3.UP*((1.45 if ride=="BALLOON" else .38)*ride_scale+.003*ride_scale))

func _fits(ride:String,foot:Vector3,yaw:float)->bool:
 var extent=(.54 if ride=="BALLOON" else .84)*ride_scale
 if not pilot.woodland.travel_bounds.grow(-extent).has_point(Vector2(foot.x,foot.z)):return false
 var query=PhysicsShapeQueryParameters3D.new();query.shape=_shape(ride);query.transform=_shape_transform(ride,foot,yaw);query.collision_mask=1
 var exclude:Array[RID]=[pilot.get_rid()]
 if is_instance_valid(body):exclude.append(body.get_rid())
 query.exclude=exclude
 return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func request(ride:String):
 if pilot.paused or game.travel.busy:return
 if ride not in ["BALLOON","CAR"]:return
 var inherited=Vector3.ZERO
 if kind in ["PARACHUTE","COAST"]:
  if ride=="CAR":notify("Land and finish stopping before calling the car.");return
  if not _fits("BALLOON",pilot.position,heading):notify("Not enough clear space to deploy a new balloon.");return
  inherited=body.velocity
  clear_for_travel()
 if kind==ride:exit_ride();return
 if kind=="BALLOON":
  next_ride=ride;landing=true;notify("Landing before changing rides…");return
 if kind=="CAR" and absf(speed)>.2:
  next_ride=ride;exit_pending=true;notify("Braking before changing rides…");return
 if active() and not exit_ride():return
 enabled=true;controls.vehicle_triggers=true;controls.size_axis=0;trigger_armed=false
 ride_scale=pilot.metrics.factor;heading=pilot.heading
 var foot=pilot.position
 # The wider balloon capsule needs a little lift above sloping ground. Its
 # bottom hemisphere can overlap a hill even when the smaller frog fits.
 if ride=="BALLOON":foot+=Vector3.UP*(.08*ride_scale)
 if ride=="CAR":
  if not pilot.is_on_floor() or pilot.mode in ["SWIM","CLIMB"] or pilot.woodland.in_water(foot):
   notify("The car needs dry ground. Use the balloon from open space.");return
  var ground=_ground(foot)
  if ground.is_empty() or ground.normal.dot(Vector3.UP)<.88:notify("Find a more level place for the car.");return
  foot=ground.position+Vector3.UP*(.16*ride_scale)
 if not _fits(ride,foot,heading):notify("There is not enough clear space for this ride.");return
 pilot.release_contacts();pilot.velocity=Vector3.ZERO;pilot.hop_impulse=Vector3.ZERO;pilot.action_timer=0
 _new_body(ride,foot)
 body.velocity=inherited
 kind=ride;pilot.mode=ride;speed=0;steering=0;age=0;landing=false;exit_pending=false;next_ride="";last_dry=foot;last_pose_species=-1
 _visual_props()
 game.camera_rig.initialized=false;_sync_rider()
 game._event("ride_entered",{"ride":kind,"scale":ride_scale})
 game.hud.toast("Helium balloon · right stick altitude / strafe · X parachute" if kind=="BALLOON" else "Convertible · left stick drive · X jump out and coast")

func _visual_props():
 if kind=="COAST":return
 var asset={"BALLOON":"helium_balloon","CAR":"frog_convertible","PARACHUTE":"parachute"}.get(kind,"")
 if asset.is_empty():return
 prop=load("res://assets/rides/"+asset+".glb").instantiate();prop.scale=Vector3.ONE*ride_scale;body.add_child(prop)
 if kind=="BALLOON":
  var mesh=CylinderMesh.new();mesh.top_radius=.003*ride_scale;mesh.bottom_radius=.003*ride_scale;mesh.height=1;mesh.radial_segments=6
  rope=MeshInstance3D.new();rope.mesh=mesh;var material=StandardMaterial3D.new();material.albedo_color=Color(.08,.055,.035);rope.material_override=material;body.add_child(rope)
 if kind=="PARACHUTE":
  for i in range(8):
   var mesh=CylinderMesh.new();mesh.top_radius=.002*ride_scale;mesh.bottom_radius=.002*ride_scale;mesh.height=1;mesh.radial_segments=5
   var line=MeshInstance3D.new();line.mesh=mesh;var mat=StandardMaterial3D.new();mat.albedo_color=Color(.16,.10,.055);line.material_override=mat;body.add_child(line);suspension.append(line)

func _new_body(ride:String,foot:Vector3):
 body=CharacterBody3D.new();body.name="ExplorationRide";body.collision_layer=pilot.actor_layer;body.collision_mask=1;body.safe_margin=.001*ride_scale
 body.floor_snap_length=(.18 if ride in ["PARACHUTE","COAST"] else .35)*ride_scale
 body.floor_max_angle=deg_to_rad(55 if ride in ["PARACHUTE","COAST"] else 38);body.max_slides=6
 collision=CollisionShape3D.new();collision.shape=_shape(ride)
 collision.position.y=(.15 if ride in ["PARACHUTE","COAST"] else (1.45 if ride=="BALLOON" else .38))*ride_scale
 if ride=="CAR":collision.rotation.x=PI/2
 body.add_child(collision);add_child(body);body.global_position=foot;body.rotation.y=heading
 body.add_collision_exception_with(pilot);pilot.add_collision_exception_with(body)
 pilot.collision_layer=0;pilot.collision_mask=0

func jump_out():
 if pilot.paused or kind not in ["BALLOON","CAR"]:return
 var previous=kind;var foot=pilot.position;var momentum=body.velocity;var yaw=heading;var size=ride_scale
 clear_for_travel() # Removes the old vehicle from the scene immediately.
 ride_scale=size;heading=yaw;kind="PARACHUTE" if previous=="BALLOON" else "COAST"
 _new_body(kind,foot);age=0;last_pose_species=-1
 if kind=="PARACHUTE":
  momentum.y=clampf(momentum.y,-minf(6,2*sqrt(size)),0)
  _visual_props()
  game.hud.toast("Parachuting · left stick steers · LT deploys a new balloon · car after landing")
 else:
  momentum.y=maxf(momentum.y,3.1*sqrt(size));pilot.jump_duration=.68*sqrt(size);pilot.action_timer=pilot.jump_duration;pilot.action_name="Big_Jump"
  pilot._play("Big_Jump",pilot.player.get_animation("Big_Jump").length/pilot.jump_duration)
  game.hud.toast("Jumped out · coasting to a stop. Release the stick to walk again.")
 body.velocity=momentum;speed=Vector2(momentum.x,momentum.z).length();_sync_rider();game.camera_rig.initialized=false
 game._event("ride_exited",{"ride":previous,"reason":"jump"})
 game._event("ride_jump",{"from":previous,"mode":kind,"velocity":[momentum.x,momentum.y,momentum.z]})

func _ground(at:Vector3)->Dictionary:
 var query=PhysicsRayQueryParameters3D.create(at+Vector3.UP*2,Vector3(at.x,pilot.woodland.surface_bottom,at.z),1)
 var exclude:Array[RID]=[pilot.get_rid()]
 if is_instance_valid(body):exclude.append(body.get_rid())
 query.exclude=exclude
 return get_world_3d().direct_space_state.intersect_ray(query)

func physics_update(delta:float):
 if not active() or pilot.paused:return
 age+=delta
 if kind=="BALLOON":_fly(delta)
 elif kind=="CAR":_drive(delta)
 elif kind=="PARACHUTE":_parachute(delta)
 elif kind=="COAST":_coast(delta)
 if not active():return
 _sync_rider()
 if body.position.y < pilot.woodland.recovery_floor:
  clear_for_travel();pilot.reset_position();notify("Recovered at the arrival point.")

func _parachute(delta:float):
 var m=controls.move;var forward=game.camera_rig.planar_forward();var right=forward.cross(Vector3.UP)
 var direction=(right*(m.x+controls.auxiliary.x)-forward*m.y).limit_length()
 var desired=direction*minf(12,4*sqrt(ride_scale))
 body.velocity.x=move_toward(body.velocity.x,desired.x,delta*4*sqrt(ride_scale))
 body.velocity.z=move_toward(body.velocity.z,desired.z,delta*4*sqrt(ride_scale))
 body.velocity.y=move_toward(body.velocity.y,-minf(6,2*sqrt(ride_scale)),delta*5*sqrt(ride_scale))
 if direction.length()>.1:heading=lerp_angle(heading,atan2(direction.x,direction.z),minf(1,delta*2))
 if controls.velocity_active():
  heading+=controls.remote_velocity.w*delta
  var v=pilot.forward()*controls.remote_velocity.x+pilot.forward().cross(Vector3.UP)*controls.remote_velocity.y
  body.velocity.x=v.x;body.velocity.z=v.z # Descent remains controlled by the chute.
 body.rotation.y=heading;body.move_and_slide();_bound(FrogBodyMetrics.BASE_RADIUS*ride_scale)
 prop.rotation.z=sin(age*1.9)*.035;prop.rotation.x=sin(age*1.4)*.025
 if body.is_on_floor() or pilot.woodland.in_water(body.position):_finish_fall("parachute_landed")

func _coast(delta:float):
 # Inherit car momentum, then brake independently of held throttle input.
 var horizontal=Vector2(body.velocity.x,body.velocity.z).move_toward(Vector2.ZERO,delta*10*sqrt(ride_scale))
 body.velocity.x=horizontal.x;body.velocity.z=horizontal.y;body.velocity.y-=9*delta
 body.move_and_slide();_bound(FrogBodyMetrics.BASE_RADIUS*ride_scale)
 speed=Vector2(body.velocity.x,body.velocity.z).length()
 if pilot.woodland.in_water(body.position):_finish_fall("coast_stopped");return
 if speed<.03*ride_scale and body.is_on_floor() and controls.move.length()<.1 and controls.auxiliary.length()<.1:
  _finish_fall("coast_stopped")

func _finish_fall(event:String):
 var at=body.position;var yaw=heading;var change_profile=profile_after_exit
 clear_for_travel();pilot.reset_position(at);pilot.heading=yaw;pilot.grab_cooldown=.4;game.camera_rig.initialized=false
 if change_profile:enabled=false;controls.vehicle_triggers=false;controls.size_axis=0;trigger_armed=false
 game._event(event,{"position":[at.x,at.y,at.z]})

func _fly(delta:float):
 var m=controls.move;var aux=controls.auxiliary;var forward=game.camera_rig.planar_forward();var right=forward.cross(Vector3.UP)
 var movement=right*m.x-forward*m.y
 var direction=(movement+right*aux.x).limit_length()
 var limit=minf(18,6*sqrt(ride_scale));var desired=direction*limit
 var vertical=-aux.y*minf(10,3*sqrt(ride_scale))
 if absf(aux.y)>.1:landing=false;next_ride="";profile_after_exit=false
 if landing:desired=Vector3.ZERO;vertical=-minf(5,1.5*sqrt(ride_scale))
 elif age<1.4 and absf(aux.y)<.1:vertical=.9*sqrt(ride_scale)
 if controls.velocity_active():
  heading+=controls.remote_velocity.w*delta
  desired=pilot.forward()*controls.remote_velocity.x+pilot.forward().cross(Vector3.UP)*controls.remote_velocity.y;vertical=controls.remote_velocity.z
 body.velocity=body.velocity.move_toward(Vector3(desired.x,vertical,desired.z),delta*4*sqrt(ride_scale))
 if movement.length()>.1:heading=lerp_angle(heading,atan2(movement.x,movement.z),minf(1,delta*2))
 body.rotation.y=heading;body.move_and_slide()
 _bound(.54*ride_scale)
 if body.position.y>pilot.woodland.flight_ceiling:body.position.y=pilot.woodland.flight_ceiling;body.velocity.y=minf(0,body.velocity.y)
 prop.rotation.z=sin(age*1.7)*.035;prop.rotation.x=sin(age*1.3)*.025
 if landing and body.is_on_floor():
  var wanted=next_ride
  if exit_ride():
   if not wanted.is_empty():request(wanted)

func _drive(delta:float):
 var throttle=-controls.move.y;steering=move_toward(steering,controls.move.x,delta*3)
 if exit_pending:throttle=0
 var limit=minf(45,18*sqrt(ride_scale));var reverse_limit=minf(10,4*sqrt(ride_scale))
 var desired=throttle*(limit if throttle>=0 else reverse_limit)
 var braking=exit_pending or (speed*desired<0) or is_zero_approx(throttle)
 speed=move_toward(speed,desired,delta*(20 if braking else 10)*sqrt(ride_scale))
 var turn=clampf(speed*tan(-steering*.42)/(.88*ride_scale),-1.9/sqrt(ride_scale),1.9/sqrt(ride_scale))
 var yaw=heading+turn*delta
 if _fits("CAR",body.position,yaw):heading=yaw
 body.rotation.y=heading
 var forward=Vector3(sin(heading),0,cos(heading));body.velocity.x=forward.x*speed;body.velocity.z=forward.z*speed;body.velocity.y-=9.8*delta
 if controls.velocity_active():
  # External SI commands remain SI; angular Z remains radians per second.
  heading+=controls.remote_velocity.w*delta;body.rotation.y=heading;speed=controls.remote_velocity.x
  body.velocity.x=sin(heading)*speed;body.velocity.z=cos(heading)*speed
 body.move_and_slide();_bound(.84*ride_scale)
 var actual=Vector2(body.velocity.x,body.velocity.z).length()
 if body.is_on_wall() and actual<absf(speed)*.5:speed=signf(speed)*actual
 if pilot.woodland.in_water(body.position):body.position=last_dry;body.velocity=Vector3.ZERO;speed=0;notify("The convertible cannot swim. Try the balloon.")
 elif body.is_on_floor():last_dry=body.position
 for node in prop.find_children("Wheel_*","Node3D",true,false):node.rotate_x(speed*delta/(.148*ride_scale))
 if exit_pending and absf(speed)<.15:
  var wanted=next_ride
  if exit_ride():
   if not wanted.is_empty():request(wanted)
  else:exit_pending=false;next_ride=""

func _bound(radius:float):
 var bounds=pilot.woodland.travel_bounds.grow(-radius);var before=body.position
 body.position.x=clampf(body.position.x,bounds.position.x,bounds.end.x);body.position.z=clampf(body.position.z,bounds.position.y,bounds.end.y)
 if body.position.distance_to(before)>.001:
  body.velocity.x=0;body.velocity.z=0;speed=0;notify("Edge of this loaded place. N opens the places list.")

func _sync_rider():
 pilot.heading=heading;pilot.mode=kind
 var offset=Vector3(-.14,.30,-.10)*ride_scale if kind=="CAR" else Vector3.ZERO
 pilot.position=body.position+Basis(Vector3.UP,heading)*offset;pilot.velocity=body.velocity
 pilot.visual_root.basis=Basis(Vector3.UP,heading)*(Basis(Vector3.RIGHT,.35) if kind in ["BALLOON","PARACHUTE"] else Basis.IDENTITY)
 var clip="Living_Idle" if kind=="CAR" else "Climb"
 if kind=="COAST":clip="Big_Jump" if pilot.action_timer>0 else ("Hop" if not body.is_on_floor() else ("Slow_Walk" if speed>.1*ride_scale else "Living_Idle"))
 if last_pose_species!=pilot.species or pilot.current_clip!=clip and pilot.action_timer<=0:
  pilot.player.active=true;pilot._play(clip);pilot.player.seek(.12,true);pilot.player.advance(0);last_pose_species=pilot.species
  if kind in ["BALLOON","PARACHUTE"]:
   _raise_hand()
   if kind=="PARACHUTE":_raise_hand("R",Vector3(.10,.60,0))
   pilot.player.active=false
 pilot.player.speed_scale=1.0 if pilot.action_timer>0 else (.45 if kind=="CAR" else 0.0)
 if kind=="COAST":pilot.player.speed_scale=pilot.player.get_animation("Big_Jump").length/pilot.jump_duration if pilot.action_timer>0 else (clampf(speed/(.20*ride_scale),.7,2.8) if clip=="Slow_Walk" else 1.0)
 if pilot.action_timer>0 or kind in ["CAR","COAST"]:pilot.player.active=true
 if kind=="BALLOON" and is_instance_valid(rope):
  var start=pilot.eye_position();var highest=-INF
  for name in ["DEF-hand.L","DEF-hand.R"]:
   var hand=pilot.skeleton.find_bone(name)
   if hand>=0:
    var at=pilot.skeleton.global_transform*pilot.skeleton.get_bone_global_pose(hand).origin
    if at.y>highest:start=at;highest=at.y
  var finish=prop.global_transform*Vector3(0,1.30,0);var line=finish-start
  rope.global_position=(start+finish)*.5
  if line.length()>.001:rope.global_basis=Basis(Quaternion(Vector3.UP,line.normalized()))*Basis.from_scale(Vector3(1,line.length(),1))
 if kind=="PARACHUTE":
  for i in range(suspension.size()):
   var angle=i*TAU/suspension.size();var side="L" if cos(angle)<0 else "R";var hand=pilot.skeleton.find_bone("DEF-hand."+side)
   var start=pilot.skeleton.global_transform*pilot.skeleton.get_bone_global_pose(hand).origin
   var finish=prop.global_transform*Vector3(.75*cos(angle),1.05,.75*sin(angle));var line=finish-start
   suspension[i].global_position=(start+finish)*.5
   if line.length()>.001:suspension[i].global_basis=Basis(Quaternion(Vector3.UP,line.normalized()))*Basis.from_scale(Vector3(1,line.length(),1))

func _raise_hand(side="L",offset=Vector3(-.10,.60,0)):
 # Pose a grip at runtime without editing the source rig or animation library.
 var skeleton=pilot.skeleton;var hand=skeleton.find_bone("DEF-hand."+side)
 if hand<0:return
 var target=skeleton.global_transform.affine_inverse()*(body.global_transform*(offset*ride_scale))
 for iteration in range(8):
  for name in ["DEF-forearm."+side,"DEF-upper_arm."+side]:
   var joint=skeleton.find_bone(name)
   if joint<0:continue
   var pose=skeleton.get_bone_global_pose(joint);var end=skeleton.get_bone_global_pose(hand).origin
   var a=end-pose.origin;var b=target-pose.origin
   if a.length()<.00001 or b.length()<.00001:continue
   pose.basis=Basis(Quaternion(a.normalized(),b.normalized()))*pose.basis
   skeleton.set_bone_global_pose(joint,pose)

func exit_ride()->bool:
 if not active():return true
 if kind=="PARACHUTE":notify("Parachuting to the ground. LT can deploy another balloon.");return false
 if kind=="COAST":notify("Coasting to a stop. Release the stick to resume walking.");return false
 if kind=="BALLOON" and not body.is_on_floor():landing=true;notify("Descending to a clear landing. Right stick up cancels.");return false
 if kind=="CAR" and absf(speed)>.2:exit_pending=true;notify("Braking before stepping out…");return false
 var exclude:Array[RID]=[pilot.get_rid(),body.get_rid()]
 var options=[Vector3(0,0,-.9),Vector3(-.8,0,0),Vector3(.8,0,0),Vector3(0,0,.9)] if kind=="CAR" else [Vector3.ZERO,Vector3(.55,0,0),Vector3(-.55,0,0)]
 for offset in options:
  var point=body.position+Basis(Vector3.UP,heading)*(offset*ride_scale)
  var result=FrogPlacement.arrival(pilot.woodland,point,ride_scale,1,exclude)
  if result.is_empty():continue
  var position=result.position;var old=kind;var change_profile=profile_after_exit
  clear_for_travel();pilot.reset_position(position);pilot.heading=heading;game.camera_rig.initialized=false
  if change_profile:enabled=false;controls.vehicle_triggers=false;controls.size_axis=0;trigger_armed=false
  game._event("ride_exited",{"ride":old});return true
 notify("No clear place to step out. Move to more open ground.");return false

func clear_for_travel():
 if not active():return
 pilot.collision_layer=pilot.actor_layer;pilot.collision_mask=1;pilot.mode="LAND";pilot.velocity=Vector3.ZERO;pilot.current_clip="";pilot.action_timer=0
 pilot.player.active=true;pilot.player.speed_scale=1.0
 if is_instance_valid(body):
  pilot.remove_collision_exception_with(body);body.collision_layer=0;body.collision_mask=0;remove_child(body);body.queue_free()
 body=null;prop=null;rope=null;suspension.clear();kind="FOOT";speed=0;landing=false;exit_pending=false;next_ride="";last_pose_species=-1;profile_after_exit=false

func camera_target()->Vector3:
 return body.global_position+Vector3.UP*((1.3 if kind=="BALLOON" else (.8 if kind=="PARACHUTE" else .45))*ride_scale)

func replicate(data:Dictionary,delta:float,warp:bool):
 var wanted=str(data.ride)
 if kind!=wanted or not is_equal_approx(ride_scale,float(data.scale)):
  clear_for_travel();ride_scale=float(data.scale)
  if wanted!="FOOT":
   kind=wanted;_new_body(kind,data.body_position);body.collision_layer=0;body.collision_mask=0;_visual_props();last_pose_species=-1
 enabled=bool(data.ride_enabled);controls.vehicle_triggers=enabled
 if active():
  var target:Vector3=data.body_position
  body.position=target if warp or body.position.distance_to(target)>5*ride_scale else body.position.lerp(target,1-exp(-delta*18))
  body.velocity=data.velocity;heading=float(data.heading);speed=float(data.ride_speed);body.rotation.y=heading
  _sync_rider()

func state()->Dictionary:
 var ground=_ground(body.position) if active() else {}
 return {"trigger_mode":"rides" if enabled else "size","ride":kind,"ride_speed_mps":absf(speed) if kind in ["CAR","COAST"] else (body.velocity.length() if active() else 0.0),"ride_altitude_m":maxf(0,body.position.y-ground.position.y) if not ground.is_empty() else 0.0,"ride_landing":landing,"parachute_active":kind=="PARACHUTE","coasting":kind=="COAST"}
