class_name ExplorerPlayerSlot
extends Node3D

# Same player-facing interface as the original game root, preserving Player 1's
# ROS and test interfaces while giving every extra frog independent state.
var game:Node3D
var pilot:FrogPilot
var controls:ExplorerControls
var camera_rig:ExplorerCamera
var rides:ExplorerRides
var hud:ExplorerHUD
var travel:
 get:return game.travel
var quitting:
 get:return game.quitting

func _ready():
 controls=ExplorerControls.new();controls.auto_assign=false;controls.keyboard_enabled=false;add_child(controls)
 pilot=FrogPilot.new();pilot.woodland=game.woodland;pilot.controls=controls;pilot.event_occurred.connect(_event);add_child(pilot)
 var holder=SubViewport.new();holder.size=Vector2i(2,2);holder.world_3d=game.get_world_3d();holder.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(holder)
 camera_rig=ExplorerCamera.new();camera_rig.pilot=pilot;camera_rig.woodland=game.woodland;pilot.camera_rig=camera_rig;holder.add_child(camera_rig)
 camera_rig.current=false;camera_rig.set_process(false)
 hud=ExplorerHUD.new();add_child(hud);hud.visible=false
 rides=ExplorerRides.new();rides.game=self;rides.pilot=pilot;rides.controls=controls;pilot.rides=rides;add_child(rides)

func _event(kind,details):
 if hud:game.player_event(self,kind,details)

func dispose():
 rides.clear_for_travel();pilot.sound.stop();pilot.sound.stream=null
 pilot.set_physics_process(false);camera_rig.get_parent().remove_child(camera_rig);camera_rig.queue_free()
 queue_free()
