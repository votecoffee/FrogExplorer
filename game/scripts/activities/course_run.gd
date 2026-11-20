extends RefCounted
## A gate is a finite, oriented plane. Test the swept path between physics ticks,
## so a fast vehicle can pass a gate without landing inside a trigger volume.

var gates: Array[Dictionary] = []
var order: Array[int] = []
var cursor := 0
var elapsed := 0.0
var timed := false
var finished := false
var previous := Vector3.ZERO
var splits := PackedFloat64Array()
var layout := ""
var checkpoint_count := 0

func setup(course: Array[Dictionary], laps: int, start: Vector3) -> void:
 gates = course
 order.clear()
 splits.clear()
 # Include the lap rule and oriented gate geometry in the comparison key.
 layout = var_to_str([laps, course]).sha256_text()
 for lap in range(maxi(1, laps)):
  for index in gates.size():
   order.append(index)
 if laps > 0:
  order.append(0)
 checkpoint_count = order.size() - (1 if laps > 0 else 0)
 cursor = 0
 elapsed = 0
 timed = laps == 0
 finished = false
 previous = start

func next_gate() -> int:
 return -1 if order.is_empty() or finished else order[cursor]

func advance(point: Vector3, delta: float) -> bool:
 if finished or order.is_empty():
  return false
 var crossed_at := crossing(previous, point, gates[order[cursor]])
 previous = point
 if crossed_at < 0:
  if timed:
   elapsed += delta
  return false
 cursor += 1
 finished = cursor == order.size()
 if not timed:
  timed = true
  elapsed += delta * (1.0 - crossed_at)
 else:
  var split := elapsed + delta * crossed_at
  splits.append(split)
  elapsed = split if finished else elapsed + delta
 return true

static func crossing(from: Vector3, to: Vector3, gate: Dictionary) -> float:
 var center: Vector3 = gate.center
 var forward: Vector3 = gate.forward
 var before := (from - center).dot(forward)
 var after := (to - center).dot(forward)
 if before > 0 or after < 0 or after <= before:
  return -1.0
 var fraction := -before / (after - before)
 var hit := from.lerp(to, fraction) - center
 if gate.has("radius"):
  return fraction if hit.length_squared() <= float(gate.radius) ** 2 else -1.0
 var side := forward.cross(Vector3.UP)
 return fraction if absf(hit.dot(side)) <= gate.half_width and absf(hit.y) <= 2.0 else -1.0
