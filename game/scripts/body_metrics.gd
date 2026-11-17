class_name FrogBodyMetrics
extends RefCounted

# World geometry, gravity and external ROS SI velocities never change scale.
const MIN_FACTOR=.25
const MAX_FACTOR=16.0
const DEFAULT_FACTOR=1.0
const LOG_RATE=.6931471805599453 # Full trigger: double / halve in one second.
const BASE_RADIUS=.13
const BASE_HEIGHT=.30
const WALK_SPEED=.52
const SWIM_SPEED=.68
const CLIMB_SPEED=.65
var factor=DEFAULT_FACTOR

static func capsule(value:float)->CapsuleShape3D:
 var shape=CapsuleShape3D.new()
 shape.radius=BASE_RADIUS*value;shape.height=BASE_HEIGHT*value
 return shape

func radius()->float:return BASE_RADIUS*factor
func height()->float:return BASE_HEIGHT*factor
func walk_speed()->float:return WALK_SPEED*factor
func swim_speed()->float:return SWIM_SPEED*factor
func climb_speed()->float:return CLIMB_SPEED*factor
func tongue_range()->float:return 1.25*factor
