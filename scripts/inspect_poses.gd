extends SceneTree
var player
var skeleton
func find_nodes(n):
 if n is AnimationPlayer:player=n
 if n is Skeleton3D:skeleton=n
 for child in n.get_children():find_nodes(child)
func _initialize():call_deferred("run")
func run():
 for name in ["montane","toad","bullfrog","whites","red_eye"]:
  var scene=load("res://assets/frogs/"+name+".glb").instantiate();root.add_child(scene);find_nodes(scene)
  for clip in ["Living_Idle","Climb"]:
   var a=player.get_animation(clip)
   for t in range(a.get_track_count()):
    var p=a.track_get_path(t)
    if p.get_subname_count()>0 and p.get_subname(0)=="root":a.track_set_enabled(t,false)
   player.play(clip);player.seek(.1,true);player.advance(0)
   var q=skeleton.get_bone_global_pose(skeleton.find_bone("DEF-spine.003")).basis.get_rotation_quaternion()
   var nose=skeleton.get_bone_global_pose(skeleton.find_bone("FX_eye.L")).origin
   var hip=skeleton.get_bone_global_pose(skeleton.find_bone("DEF-spine")).origin
   print("POSE ",name," ",clip," q=",q," axis=",(nose-hip).normalized())
  scene.queue_free()
 quit()
