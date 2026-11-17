class_name FrogPilot
extends CharacterBody3D

signal event_occurred(kind:String,details:Dictionary)
const SPECIES = [
 {"name":"Montane brown frog","file":"montane","pitch":1.1},
 {"name":"Japanese toad","file":"toad","pitch":0.75},
 {"name":"American bullfrog","file":"bullfrog","pitch":0.65},
 {"name":"White’s tree frog","file":"whites","pitch":0.95},
 {"name":"Red-eyed tree frog","file":"red_eye","pitch":1.3},
 {"name":"American toad","file":"american_toad","pitch":1.0,"call":"american_toad.wav"}]
const LOOPING=["Idle","Living_Idle","Slow_Walk","Swim","Climb","Toe_Tap","Swamp_Shuffle","Disco_Frog"]
const SILLY=["Toe_Tap","Foot_Wave","Swamp_Shuffle","Disco_Frog","Victory_Ribbit","Breakdance"]
var rides:ExplorerRides
var actor_layer=1
var render_layer=0
var metrics=FrogBodyMetrics.new()
var collision_shape:CollisionShape3D
var resize_blocked=false
var resize_message=""
var resize_notice_after=0
var jump_factor=1.0
var jump_duration=.68
var last_safe_position=Vector3.ZERO
var last_safe_world:WoodlandWorld
var woodland:WoodlandWorld
var controls:ExplorerControls
var camera_rig:ExplorerCamera
var species=0
var visual_root:Node3D
var model:Node3D
var player:AnimationPlayer
var skeleton:Skeleton3D
var sound:AudioStreamPlayer3D
var current_clip=""
var mode="LAND"
var heading=PI
var tree_index=-1
var climb_angle=0.0
var grab_cooldown=0.0
var action_timer=0.0
var action_name=""
var paused=false
var flies_caught=0
var catch_index=-1
var catch_timer=-1.0
var catch_endpoint=Vector3.ZERO
var tongue:MeshInstance3D
var hop_impulse=Vector3.ZERO
var coyote=0.0
var rng=RandomNumberGenerator.new()
var climb_correction=Basis.IDENTITY
var idle_spine_rotation=Quaternion.IDENTITY

func _ready():
 rng.randomize();floor_snap_length=.18;floor_max_angle=deg_to_rad(55)
 collision_shape=CollisionShape3D.new();collision_shape.shape=FrogBodyMetrics.capsule(1.0);collision_shape.position.y=.15;add_child(collision_shape)
 visual_root=Node3D.new();add_child(visual_root)
 sound=AudioStreamPlayer3D.new();sound.max_distance=15;add_child(sound)
 if ResourceLoader.exists("res://assets/audio/croak.wav"):sound.stream=load("res://assets/audio/croak.wav")
 var mesh=CylinderMesh.new();mesh.top_radius=.009;mesh.bottom_radius=.012;mesh.height=1;mesh.radial_segments=8
 tongue=MeshInstance3D.new();tongue.mesh=mesh;var mat=StandardMaterial3D.new();mat.albedo_color=Color(.65,.24,.24);mat.roughness=.4;tongue.material_override=mat;tongue.visible=false;add_child(tongue)
 select_species(0)

func _find_nodes(node):
 if node is AnimationPlayer:player=node
 if node is Skeleton3D:skeleton=node
 for child in node.get_children():_find_nodes(child)

func select_species(index):
 species=posmod(index,SPECIES.size())
 if is_instance_valid(model):model.queue_free()
 var asset_path="res://assets/frogs/"+SPECIES[species].file+".glb"
 if ResourceLoader.exists(asset_path) and not "--starter-models" in OS.get_cmdline_user_args():
  model=(load(asset_path) as PackedScene).instantiate()
 else:model=StarterFrog.create(species)
 model.scale=Vector3.ONE*(2.8*metrics.factor);visual_root.add_child(model)
 set_render_layer(render_layer)
 player=null;skeleton=null;_find_nodes(model)
 assert(player!=null and skeleton!=null,"Frog asset missing its rig")
 # Physical movement belongs to CharacterBody3D. Cancel baked root offsets.
 for clip in player.get_animation_list():
  var animation=player.get_animation(clip)
  animation.loop_mode=Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
  for track in range(animation.get_track_count()):
   var path=animation.track_get_path(track)
   if path.get_subname_count()>0 and path.get_subname(0)=="root":animation.track_set_enabled(track,false)
 # AFK's Climb already pitches the skeleton upright. Remove that bulk pose
 # before orienting it onto the current trunk, so it is not rotated twice.
 var spine=skeleton.find_bone("DEF-spine.003")
 player.play("Living_Idle");player.seek(.1,true);player.advance(0)
 idle_spine_rotation=skeleton.get_bone_global_pose(spine).basis.get_rotation_quaternion()
 player.play("Climb");player.seek(.1,true);player.advance(0)
 var climb_rotation=skeleton.get_bone_global_pose(spine).basis.get_rotation_quaternion()
 climb_correction=Basis((climb_rotation*idle_spine_rotation.inverse()).inverse())
 var call_path="res://assets/audio/"+str(SPECIES[species].get("call","croak.wav"))
 if ResourceLoader.exists(call_path):sound.stream=load(call_path)
 action_timer=0;catch_timer=-1;current_clip="";_play("Living_Idle")
 event_occurred.emit("frog_switched",{"species":SPECIES[species].name})

func set_render_layer(value:int,node:Node=null):
 if node==null:render_layer=value;node=model
 if node is VisualInstance3D:node.layers=value if value>0 else 1
 for child in node.get_children():set_render_layer(value,child)

func _play(clip,rate=1.0):
 if not player.has_animation(clip):return
 player.speed_scale=rate
 if current_clip!=clip:player.play(clip,.12);current_clip=clip

func request_action(action):
 if action=="next_frog":select_species(species+1);return
 if action=="reset":reset_position();return
 if paused:return
 if action=="jump" and rides and rides.active():rides.jump_out();return
 if action=="reset_size":try_resize(1.0);return
 if action=="jump":
  if action_timer>0 and action_name=="Big_Jump" and (not is_on_floor() or velocity.y>0):return
  var launch=sqrt(metrics.factor)
  if mode=="CLIMB":
   var tree=woodland.trees[tree_index];var radial=Vector3(sin(climb_angle),0,cos(climb_angle));_leave_tree();hop_impulse=radial*(1.8*launch);velocity=hop_impulse+Vector3.UP*(2.7*launch)
  elif mode=="SWIM":
   mode="LAND";position.y=.12*metrics.factor;velocity.y=2.6*launch;hop_impulse=forward()*(1.3*launch)
  elif is_on_floor() or coyote>0:
   velocity.y=3.1*launch;hop_impulse=forward()*(1.1*launch);coyote=0
   var takeoff=Vector2(velocity.x,velocity.z).limit_length(FrogBodyMetrics.WALK_SPEED*launch);velocity.x=takeoff.x;velocity.z=takeoff.y
  else:return
  jump_factor=metrics.factor;jump_duration=.68*launch
  action_timer=jump_duration;action_name="Big_Jump";_play("Big_Jump",player.get_animation("Big_Jump").length/jump_duration);event_occurred.emit("jump",{});return
 if action_timer>0:return
 match action:
  "catch_fly":
   catch_index=woodland.nearest_fly(eye_position(),metrics.tongue_range());catch_timer=.32
   if catch_index>=0:
    catch_endpoint=woodland.flies[catch_index].node.global_position
    if mode!="CLIMB":heading=atan2(catch_endpoint.x-position.x,catch_endpoint.z-position.z)
   action_name="Catch_Fly_Swallow";action_timer=player.get_animation(action_name).length;_play(action_name)
   event_occurred.emit("tongue_snap",{"target_found":catch_index>=0})
  "croak":
   action_name="Croak";action_timer=player.get_animation("Croak").length;_play("Croak");sound.pitch_scale=SPECIES[species].pitch;sound.play();event_occurred.emit("croak",{})
  "silly":
   action_name=SILLY[rng.randi_range(0,SILLY.size()-1)];action_timer=player.get_animation(action_name).length;_play(action_name);event_occurred.emit("silly",{"clip":action_name})

func release_contacts():
 if mode=="CLIMB":_leave_tree()
 tree_index=-1;catch_timer=-1;catch_index=-1;tongue.visible=false

func reset_position(checked_spawn:Variant=null):
 var destination=woodland.spawn_point
 if checked_spawn is Vector3:destination=checked_spawn
 elif not is_equal_approx(metrics.factor,1.0):
  var result=FrogPlacement.arrival(woodland,destination,metrics.factor,1,[get_rid()])
  if result.is_empty():
   for candidate in woodland.recovery_points:
    result=FrogPlacement.arrival(woodland,candidate,metrics.factor,1,[get_rid()])
    if not result.is_empty():break
  if result.is_empty() and is_instance_valid(last_safe_world) and last_safe_world==woodland:
   result=FrogPlacement.arrival(woodland,last_safe_position,metrics.factor,1,[get_rid()])
  if result.is_empty():
   _resize_warning("No clear recovery spot at this size. Shrink to recover.");return false
  destination=result.position
 release_contacts()
 position=destination;velocity=Vector3.ZERO;hop_impulse=Vector3.ZERO;heading=woodland.spawn_heading;mode="LAND";action_timer=0;grab_cooldown=1;current_clip="";visual_root.basis=Basis(Vector3.UP,heading)
 last_safe_position=destination;last_safe_world=woodland
 return true

func _resize_warning(reason:String):
 resize_blocked=true;resize_message=reason
 if Time.get_ticks_msec()>resize_notice_after:
  resize_notice_after=Time.get_ticks_msec()+1500;event_occurred.emit("resize_blocked",{"reason":reason})

func _can_climb(tree:Dictionary,size:float)->bool:
 return FrogBodyMetrics.BASE_RADIUS*size<=float(tree.radius)*2 and float(tree.height)>.5*size

func _resized_position(size:float)->Vector3:
 if mode!="CLIMB" or tree_index<0:return position
 var tree=woodland.trees[tree_index];var radial=Vector3(sin(climb_angle),0,cos(climb_angle))
 var proposed=tree.center+radial*(tree.radius+.14*size);proposed.y=position.y
 return proposed

func _fits_size(size:float)->bool:
 var foot=_resized_position(size)
 if mode=="CLIMB" and not _can_climb(woodland.trees[tree_index],size):return false
 if not FrogPlacement.within_bounds(woodland,foot,size):return false
 return FrogPlacement.fits(get_world_3d().direct_space_state,foot,size,1,[get_rid()])

func _apply_size(factor:float):
 metrics.factor=factor
 collision_shape.shape=FrogBodyMetrics.capsule(factor);collision_shape.position.y=.15*factor
 model.scale=Vector3.ONE*(2.8*factor);floor_snap_length=.18*factor;safe_margin=.001*factor;sound.max_distance=15*factor

func arrive_at_default_size(checked_spawn:Vector3):
 # Travel validates this position with the default capsule before committing.
 # Apply dimensions here rather than testing growth at the previous location.
 _apply_size(FrogBodyMetrics.DEFAULT_FACTOR)
 resize_blocked=false;resize_message="";resize_notice_after=0
 reset_position(checked_spawn)

func try_resize(requested:float)->bool:
 if rides and rides.active():rides.notify("Step off the ride before resizing.");return false
 if not is_finite(requested) or requested<=0:return false
 var target=clampf(requested,FrogBodyMetrics.MIN_FACTOR,FrogBodyMetrics.MAX_FACTOR)
 var old=metrics.factor;resize_blocked=false;resize_message=""
 if is_equal_approx(target,old):return true
 var complete=_fits_size(target)
 if not complete:
  var low=old;var high=target
  # Keep the largest safe growth, or the nearest safe shrink on a trunk.
  for i in range(10):
   var mid=(low+high)*.5
   if _fits_size(mid):low=mid
   else:high=mid
  target=low
  _resize_warning("Trunk is too small. Jump off to grow." if mode=="CLIMB" and not _can_climb(woodland.trees[tree_index],requested) else "Space is too tight to resize here.")
 if absf(target-old)>.000001:
  position=_resized_position(target);_apply_size(target)
  if catch_index>=0 and eye_position().distance_to(catch_endpoint)>metrics.tongue_range():catch_index=-1;tongue.visible=false
  if is_on_floor():last_safe_position=position;last_safe_world=woodland
 return complete

func _resize_input(delta:float):
 if absf(controls.size_axis)>.001:
  try_resize(metrics.factor*exp(controls.size_axis*FrogBodyMetrics.LOG_RATE*delta))
 elif Time.get_ticks_msec()>resize_notice_after:resize_blocked=false;resize_message=""


func forward():
 return Vector3(sin(heading),0,cos(heading))

func facing_basis():
 if mode=="CLIMB":
  var radial=Vector3(sin(climb_angle),0,cos(climb_angle))
  return Basis(radial.cross(Vector3.UP),radial,Vector3.UP)
 return Basis(Vector3.UP,heading)

func eye_position():
 if skeleton:
  var l=skeleton.find_bone("FX_eye.L");var r=skeleton.find_bone("FX_eye.R")
  if l>=0 and r>=0:return skeleton.global_transform*((skeleton.get_bone_global_pose(l).origin+skeleton.get_bone_global_pose(r).origin)*.5)
 return position+Vector3(0,.23*metrics.factor,0)

func _leave_tree():
 if tree_index>=0:
  for canopy in woodland.trees[tree_index].canopy:canopy.visible=true
 mode="LAND";tree_index=-1;grab_cooldown=1.2;visual_root.basis=Basis(Vector3.UP,heading)

func _physics_process(delta):
 if not woodland or not controls or paused:return
 if rides and rides.active():
  action_timer=maxf(0,action_timer-delta);_catch_update(delta);rides.physics_update(delta);return
 _resize_input(delta)
 var size=metrics.factor
 grab_cooldown=maxf(0,grab_cooldown-delta)
 if action_timer>0:action_timer=maxf(0,action_timer-delta)
 _catch_update(delta)
 var m=controls.move;var aux=controls.auxiliary
 var remote=controls.velocity_active()
 var frozen=action_timer>0 and action_name in ["Croak","Catch_Fly_Swallow"]+SILLY
 if frozen:m=Vector2.ZERO;aux=Vector2.ZERO;remote=false
 if mode=="CLIMB":
  var tree=woodland.trees[tree_index]
  var vertical=-m.y*metrics.climb_speed()
  var lateral=(m.x+aux.x)*1.45*(tree.radius+.14)*size/(tree.radius+.14*size)
  if remote:vertical=controls.remote_velocity.x;lateral=controls.remote_velocity.y/maxf(.025,tree.radius+.14*size)
  var previous=position;var old_angle=climb_angle
  climb_angle+=lateral*delta
  position.y=clampf(position.y+vertical*delta,tree.center.y+.16*size,tree.center.y+tree.height-.30*size)
  var radial=Vector3(sin(climb_angle),0,cos(climb_angle))
  position.x=tree.center.x+radial.x*(tree.radius+.14*size);position.z=tree.center.z+radial.z*(tree.radius+.14*size)
  if not FrogPlacement.fits(get_world_3d().direct_space_state,position,size,1,[get_rid()]):position=previous;climb_angle=old_angle
  visual_root.basis=facing_basis()*(climb_correction if action_timer<=0 else Basis.IDENTITY)
  velocity=Vector3.ZERO
  if position.y<=tree.center.y+.17*size and vertical<0:_leave_tree()
  if action_timer<=0:_play("Climb",1.4 if absf(vertical)/size+absf(lateral)>.02 else 0.0)
  return
 var wet=woodland.in_water(position+Vector3.UP*(.08*(size-1)))
 if mode=="SWIM" and not wet:
  mode="LAND";position.y=maxf(position.y,woodland.ground_height(position.x,position.z)+.02*size);event_occurred.emit("shore_exit",{})
 elif wet and mode!="SWIM":mode="SWIM";hop_impulse=Vector3.ZERO;event_occurred.emit("water_entry",{})
 var frame_forward=camera_rig.planar_forward() if camera_rig else Vector3.FORWARD
 var frame_right=frame_forward.cross(Vector3.UP)
 var direction=(frame_right*m.x-frame_forward*m.y)
 if camera_rig and camera_rig.view_mode!=0:
  heading-=m.x*delta*1.8
  frame_forward=forward();frame_right=frame_forward.cross(Vector3.UP)
  direction=frame_forward*(-m.y)
 var speed=metrics.swim_speed() if mode=="SWIM" else metrics.walk_speed()
 var jumping=action_timer>0 and action_name=="Big_Jump"
 if jumping:speed=FrogBodyMetrics.WALK_SPEED*sqrt(jump_factor)
 var desired=(direction+frame_right*aux.x).limit_length()*speed
 if direction.length()>.05 and (not camera_rig or camera_rig.view_mode==0):heading=lerp_angle(heading,atan2(direction.x,direction.z),minf(1,delta*10))
 if remote:
  heading+=controls.remote_velocity.w*delta
  desired=forward()*controls.remote_velocity.x+forward().cross(Vector3.UP)*controls.remote_velocity.y
 if jumping:desired+=hop_impulse
 var acceleration=3.5 if jumping else 3.5*size
 velocity.x=move_toward(velocity.x,desired.x,delta*acceleration);velocity.z=move_toward(velocity.z,desired.z,delta*acceleration)
 if mode=="SWIM":
  var up=-aux.y*.60*size
  if remote:up=controls.remote_velocity.z
  if absf(up)<(.02 if remote else .02*size):up=clampf((-.08*size-position.y)*1.8,-.18*size,.18*size)
  velocity.y=move_toward(velocity.y,up,delta*2*size)
  if position.y>=-.06*size and velocity.y>0:velocity.y=0;position.y=-.06*size
 else:
  if is_on_floor() and velocity.y<=0:coyote=.12
  else:coyote=maxf(0,coyote-delta)
  velocity.y-=9.0*delta
 var was_grounded=is_on_floor();move_and_slide()
 if not was_grounded and is_on_floor() and velocity.y<=0:hop_impulse=Vector3.ZERO
 var bounds=woodland.travel_bounds.grow(-metrics.radius())
 position.x=clampf(position.x,bounds.position.x,bounds.end.x);position.z=clampf(position.z,bounds.position.y,bounds.end.y)
 if position.y < woodland.recovery_floor:reset_position();event_occurred.emit("recovered",{});return
 if is_on_floor():last_safe_position=position;last_safe_world=woodland
 visual_root.basis=Basis(Vector3.UP,heading)
 var approach=desired if remote else direction
 if mode=="LAND" and grab_cooldown<=0 and approach.length()>.1 and action_timer<=0:
  var tree=woodland.nearest_tree(position,.33*size)
  if tree>=0 and _can_climb(woodland.trees[tree],size):
   var center=woodland.trees[tree].center;var toward=Vector3(center.x-position.x,0,center.z-position.z).normalized()
   if approach.normalized().dot(toward)>.45:
    tree_index=tree;mode="CLIMB";climb_angle=atan2(position.x-center.x,position.z-center.z);position.y=maxf(position.y,center.y+.22*size)
    for canopy in woodland.trees[tree].canopy:canopy.visible=false
    event_occurred.emit("climb",{})
 if action_timer<=0:
  if mode=="SWIM":_play("Swim",1.2 if desired.length()>.1*size else .55)
  elif not is_on_floor():_play("Hop")
  elif desired.length()>.05*size:_play("Slow_Walk",clampf(desired.length()/(.20*size),.7,2.8))
  else:_play("Living_Idle")

func _catch_update(delta):
 tongue.visible=false
 if catch_timer==-1:return
 catch_timer-=delta
 if catch_index>=0:
  if woodland.flies[catch_index].respawn<=0:catch_endpoint=woodland.flies[catch_index].node.global_position
  var start=eye_position()-facing_basis().y*(.055*metrics.factor)
  var progress=clampf(1-absf(catch_timer)/.32,0,1);var end=start.lerp(catch_endpoint,progress);var d=end-start
  if d.length()>.01:
   tongue.visible=true;tongue.global_position=(start+end)*.5;tongue.global_basis=Basis(Quaternion(Vector3.UP,d.normalized()))*Basis.from_scale(Vector3(metrics.factor,d.length(),metrics.factor))
  if catch_timer<=0 and woodland.catch_fly(catch_index):flies_caught+=1;event_occurred.emit("fly_caught",{"count":flies_caught})
 if catch_timer<-.28:catch_timer=-1;catch_index=-1
