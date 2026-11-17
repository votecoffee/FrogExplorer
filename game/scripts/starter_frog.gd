class_name StarterFrog
extends RefCounted

# Original primitive geometry and keyframes; no scan, texture, rig or animation
# data is copied from the optional realistic model pack.
const CLIPS=["Big_Jump","Breakdance","Catch_Fly","Catch_Fly_Swallow","Climb","Croak","Death","Disco_Frog","Face_Wipe","Foot_Wave","Hit","Hop","Idle","Land","Living_Idle","Puff_Up","Shore_Exit","Slow_Walk","Splat","Swallow","Swamp_Shuffle","Swim","Toe_Tap","Tongue_Snap","Turn_Left","Turn_Right","Victory_Ribbit","Water_Entry"]
const COLORS=[Color(.32,.23,.12),Color(.38,.30,.17),Color(.23,.40,.10),Color(.18,.55,.48),Color(.23,.65,.16),Color(.40,.31,.18)]

static func ellipsoid(parent:Node,at:Vector3,size:Vector3,color:Color):
 var node=MeshInstance3D.new();var mesh=SphereMesh.new()
 mesh.radius=1;mesh.height=2;mesh.radial_segments=16;mesh.rings=8
 node.mesh=mesh;node.position=at;node.scale=size
 var material=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.65
 node.material_override=material;parent.add_child(node);return node

static func bone(skeleton:Skeleton3D,name:String,at:Vector3,parent=-1)->int:
 var index=skeleton.get_bone_count();skeleton.add_bone(name)
 if parent>=0:skeleton.set_bone_parent(index,parent)
 skeleton.set_bone_rest(index,Transform3D(Basis.IDENTITY,at));return index

static func attachment(skeleton:Skeleton3D,name:String)->BoneAttachment3D:
 var node=BoneAttachment3D.new();node.bone_name=name;skeleton.add_child(node);return node

static func rotation_track(animation:Animation,bone_name:String,keys:Array):
 var track=animation.add_track(Animation.TYPE_ROTATION_3D)
 animation.track_set_path(track,NodePath("Skeleton3D:"+bone_name))
 for i in range(keys.size()):animation.rotation_track_insert_key(track,animation.length*i/(keys.size()-1),Quaternion.from_euler(keys[i]))

static func create(species:int)->Node3D:
 var model=Node3D.new();model.name="OriginalStarterFrog";model.set_meta("starter_model",true)
 var skeleton=Skeleton3D.new();skeleton.name="Skeleton3D";model.add_child(skeleton)
 var root=bone(skeleton,"root",Vector3.ZERO)
 bone(skeleton,"DEF-spine.003",Vector3(0,.052,0),root)
 bone(skeleton,"FX-jaw",Vector3(0,.049,.064),root)
 var color=COLORS[species%COLORS.size()];var body=attachment(skeleton,"DEF-spine.003")
 ellipsoid(body,Vector3(0,0,-.015),Vector3(.046,.029,.062),color)
 ellipsoid(body,Vector3(0,.008,.044),Vector3(.051,.025,.040),color)
 ellipsoid(body,Vector3(0,-.017,.003),Vector3(.036,.014,.049),Color(.73,.75,.51))
 ellipsoid(attachment(skeleton,"FX-jaw"),Vector3(0,0,.005),Vector3(.042,.007,.026),Color(.72,.77,.56))
 for side in ["L","R"]:
  var sign_x=-1 if side=="L" else 1
  bone(skeleton,"FX_eye."+side,Vector3(.032*sign_x,.083,.058),root)
  var eye=attachment(skeleton,"FX_eye."+side)
  ellipsoid(eye,Vector3.ZERO,Vector3.ONE*.015,Color(.8,.1,.04) if species==4 else Color(.65,.56,.24))
  ellipsoid(eye,Vector3(0,0,.011),Vector3(.008,.010,.004),Color(.012,.016,.012))
  ellipsoid(eye,Vector3(-.003,.004,.014),Vector3.ONE*.0025,Color(.96,.98,.92))
  var upper=bone(skeleton,"DEF-upper_arm."+side,Vector3(.041*sign_x,.053,.035),root)
  var forearm=bone(skeleton,"DEF-forearm."+side,Vector3(.017*sign_x,-.023,.005),upper)
  bone(skeleton,"DEF-hand."+side,Vector3(0,-.020,.019),forearm)
  ellipsoid(attachment(skeleton,"DEF-upper_arm."+side),Vector3(.008*sign_x,-.012,.002),Vector3(.012,.022,.012),color)
  ellipsoid(attachment(skeleton,"DEF-forearm."+side),Vector3(0,-.010,.010),Vector3(.010,.015,.020),color)
  var hand=attachment(skeleton,"DEF-hand."+side)
  for toe in range(4):ellipsoid(hand,Vector3((toe-1.5)*.005,0,.009),Vector3(.003,.003,.014),color.lightened(.12))
  var thigh=bone(skeleton,"DEF-thigh."+side,Vector3(.039*sign_x,.045,-.048),root)
  var calf=bone(skeleton,"DEF-calf."+side,Vector3(.022*sign_x,-.021,-.019),thigh)
  bone(skeleton,"DEF-foot."+side,Vector3(0,-.012,.043),calf)
  ellipsoid(attachment(skeleton,"DEF-thigh."+side),Vector3(.008*sign_x,-.003,-.010),Vector3(.027,.025,.036),color)
  ellipsoid(attachment(skeleton,"DEF-calf."+side),Vector3(0,-.005,.019),Vector3(.012,.010,.027),color)
  var foot=attachment(skeleton,"DEF-foot."+side)
  for toe in range(5):ellipsoid(foot,Vector3((toe-2)*.004,0,.010),Vector3(.003,.003,.018),color.lightened(.1))
 var player=AnimationPlayer.new();player.name="AnimationPlayer";player.root_node=NodePath("..");model.add_child(player)
 var library=AnimationLibrary.new();player.add_animation_library("",library)
 for clip in CLIPS:
  var animation=Animation.new();animation.length=2.0 if clip in ["Living_Idle","Idle"] else 1.2
  var spine=[];var jaw=[];var left=[];var right=[];var legs=[]
  for step in range(9):
   var phase=step/8.0;var wave=sin(phase*TAU);var pulse=sin(phase*PI)
   var dance=clip in ["Breakdance","Disco_Frog","Swamp_Shuffle","Victory_Ribbit"]
   var moving=clip in ["Slow_Walk","Swim","Climb","Hop","Toe_Tap","Foot_Wave","Shore_Exit","Water_Entry"]
   spine.append(Vector3(.025*wave,0,.18*wave if dance else 0))
   jaw.append(Vector3(.5*pulse if clip in ["Croak","Catch_Fly","Catch_Fly_Swallow","Tongue_Snap","Swallow","Victory_Ribbit"] else 0,0,0))
   var amount=.35*wave if moving or dance else .02*wave
   if clip=="Big_Jump":amount=-.7*pulse
   if clip=="Face_Wipe":amount=-.9*pulse
   left.append(Vector3(amount,0,.08*wave));right.append(Vector3(-amount,0,-.08*wave))
   legs.append(Vector3(.5*pulse if clip=="Big_Jump" else amount,0,0))
  rotation_track(animation,"DEF-spine.003",spine);rotation_track(animation,"FX-jaw",jaw)
  rotation_track(animation,"DEF-upper_arm.L",left);rotation_track(animation,"DEF-upper_arm.R",right)
  rotation_track(animation,"DEF-thigh.L",legs);rotation_track(animation,"DEF-thigh.R",legs)
  library.add_animation(clip,animation)
 return model
