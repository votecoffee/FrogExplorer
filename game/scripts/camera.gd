class_name ExplorerCamera
extends Camera3D

const NAMES=["Overhead","Behind the frog","First person"]
var pilot:FrogPilot
var woodland:WoodlandWorld
var view_mode=0
var initialized=false
var view_index=-1
var shared_views=false
var environment_world:WoodlandWorld

func _ready():
 fov=57;near=.025;far=65;current=true

func cycle():
 view_mode=(view_mode+1)%3;initialized=false

func planar_forward():
 if view_mode==0:return Vector3.FORWARD
 if pilot:return pilot.forward()
 return Vector3.FORWARD

func _process(delta):
 if not pilot:return
 var size=pilot.metrics.factor
 near=.025*size
 var target=pilot.global_position+Vector3(0,.18*size,0)
 var ride=pilot.rides if pilot.rides and pilot.rides.active() and pilot.rides.kind!="COAST" else null
 if ride:target=ride.camera_target()
 var goal=Vector3.ZERO
 var up=Vector3.UP
 if view_mode==0:
  goal=target+(Vector3(0,5.0,4.5) if ride and ride.kind in ["BALLOON","PARACHUTE"] else Vector3(0,5.2,2.0))*size
 elif view_mode==1:
  var forward=pilot.facing_basis().z.normalized()
  if ride:goal=target-forward*(4.0*size)+Vector3.UP*(1.1*size)
  elif pilot.mode=="CLIMB":goal=target+pilot.facing_basis().y*(2.0*size)+Vector3.UP*(.6*size)
  else:goal=target-forward*(2.0*size)+Vector3.UP*(.95*size)
 else:
  var forward=pilot.facing_basis().z.normalized();up=pilot.facing_basis().y.normalized()
  goal=pilot.eye_position()+forward*(.07*size);target=goal+forward*(3*size)
  if absf(forward.dot(up))>.98:up=Vector3.FORWARD
 if pilot.model:
  pilot.model.visible=true if shared_views else view_mode!=2
  cull_mask=((1<<16)-1)|(1<<(16+maxi(0,view_index))) if shared_views else 1048575
  if shared_views and view_mode==2:cull_mask &= ~pilot.render_layer
 if not initialized or view_mode==2:global_position=goal;initialized=true
 else:global_position=global_position.lerp(goal,1-exp(-delta*6))
 if global_position.distance_to(target)>.01:look_at(target,up)
 if woodland:
  far=maxf(woodland.camera_far,65*size)
  for i in range(woodland.trees.size()):
   var tree=woodland.trees[i]
   var distance=Vector2(tree.center.x-pilot.position.x,tree.center.z-pilot.position.z).length()
   var cutaway=(view_mode==0 and distance<2.8*size) or (pilot.mode=="CLIMB" and pilot.tree_index==i)
   for canopy in tree.canopy:
    if shared_views:
     canopy.visible=true
     if cutaway:canopy.layers &= ~(1<<(16+view_index))
     else:canopy.layers |= 1<<(16+view_index)
    else:canopy.visible=not cutaway
  var underwater=woodland.in_water(global_position) and global_position.y<-.025
  if shared_views and (environment_world!=woodland or environment==null):
   environment=woodland.environment.duplicate();environment_world=woodland
  if not shared_views:environment=null;environment_world=null
  var fog=environment if shared_views else woodland.environment
  fog.fog_density=.22 if underwater else woodland.dry_fog_density
  fog.fog_light_color=Color(.06,.25,.22) if underwater else woodland.dry_fog_color
