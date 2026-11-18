extends SceneTree

# Native import/animation validation of the authored GLB, without a desktop.
var failures=[]
var player:AnimationPlayer
var skeleton:Skeleton3D
var meshes:Array[MeshInstance3D]=[]
const CLIPS=["Big_Jump","Breakdance","Catch_Fly","Catch_Fly_Swallow","Climb","Croak","Death","Disco_Frog","Face_Wipe","Foot_Wave","Hit","Hop","Idle","Land","Living_Idle","Puff_Up","Shore_Exit","Slow_Walk","Splat","Swallow","Swamp_Shuffle","Swim","Toe_Tap","Tongue_Snap","Turn_Left","Turn_Right","Victory_Ribbit","Water_Entry"]

func _initialize():run.call_deferred()

func inspect(node:Node):
 if node is AnimationPlayer:player=node
 if node is Skeleton3D:skeleton=node
 if node is MeshInstance3D:meshes.append(node)
 for child in node.get_children():inspect(child)

func run():
 var path="res://assets/frogs/red_eye_original.glb"
 var report_path="res://../state/original_frog_probe.json"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--asset="):path=arg.trim_prefix("--asset=")
  if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
 var model=(load(path) as PackedScene).instantiate();root.add_child(model);inspect(model)
 if not player or not skeleton:push_error("Authored frog has no native animation player/skeleton");quit(1);return
 var samples=0;var furthest=0.0
 if skeleton.get_bone_count()!=61:failures.append("Expected the authored 61-joint rig")
 for mesh in meshes:
  if not mesh.skin:failures.append("Unskinned mesh: "+str(mesh.name))
 for side in ["L","R"]:
  for kind in ["hand","foot"]:
   for digit in range(1,5 if kind=="hand" else 6):
    if skeleton.find_bone("Digit_%s_%d.%s_tip"%[kind,digit,side])<0:failures.append("Missing terminal digit joint")
 for clip in CLIPS:
  if not player.has_animation(clip):failures.append("Missing clip: "+clip);continue
  player.play(clip)
  for part in range(9):
   player.seek(player.get_animation(clip).length*part/8.0,true);player.advance(0)
   skeleton.force_update_all_bone_transforms()
   for bone in range(skeleton.get_bone_count()):
    var pose=skeleton.get_bone_global_pose(bone)
    furthest=maxf(furthest,pose.origin.length())
    if not pose.is_finite() or pose.origin.length()>.4 or pose.basis.determinant()<=0:failures.append("Invalid joint pose in "+clip)
   samples+=1
 var report={"failures":failures,"asset_sha256":FileAccess.get_sha256(path),"clips":CLIPS.size(),"pose_samples":samples,"bones":skeleton.get_bone_count(),"skinned_meshes":meshes.size(),"maximum_joint_distance_m":furthest,"scope":"Godot native GLB import and in-place joint/skin/animation binding; headless, no GPU FPS or hardware input qualification."}
 var file=FileAccess.open(report_path,FileAccess.WRITE)
 if file:file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 print("ORIGINAL_FROG_PROBE "+JSON.stringify(report))
 model.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
