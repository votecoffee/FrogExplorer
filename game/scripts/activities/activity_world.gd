class_name ExplorerActivityWorld
extends WoodlandWorld

const GARDEN_PLOT = 1.35
const CAR_SEGMENTS = 80
const ROAD_HALF_WIDTH = 7.0
const ACTIVITIES = ["car_circuit", "balloon_rings", "lily_code_garden"]
const Gardens = preload("res://scripts/activities/garden_program.gd")
var activity: String
var gates: Array[Dictionary] = []
var gate_lights: Array[Node3D] = []
var garden_root: Node3D

func _ready() -> void:
 spawn_point = Vector3(0, 0.04, 0)
 recovery_floor = -12
 surface_top = 130
 surface_bottom = -15
 dry_fog_density = 0.0011
 match activity:
  "car_circuit":
   travel_bounds = Rect2(-118, -82, 236, 164)
   camera_far = 320
   _make_circuit()
  "balloon_rings":
   travel_bounds = Rect2(-145, -130, 290, 275)
   camera_far = 420
   flight_ceiling = 95
   _make_rings()
  "lily_code_garden":
   travel_bounds = Rect2(-9, -9, 18, 18)
   dry_fog_density = 0.008
   _make_garden()
 mark_gate(0)

func ground_height(_x: float, _z: float) -> float:
 return 0.0

func in_water(_point: Vector3) -> bool:
 return false

func streaming_state() -> Dictionary:
 return {"mode":"procedural_activity"}

func _box(center: Vector3, dimensions: Vector3, mat: Material, yaw := 0.0, solid := false, parent: Node3D = self) -> MeshInstance3D:
 var mesh := BoxMesh.new()
 mesh.size = dimensions
 var visual: MeshInstance3D = mesh_instance(mesh, mat, center, Vector3.ONE, parent)
 visual.rotation.y = yaw
 if solid:
  var body := StaticBody3D.new()
  parent.add_child(body)
  body.position = center
  body.rotation.y = yaw
  var collision := CollisionShape3D.new()
  var shape := BoxShape3D.new()
  shape.size = dimensions
  collision.shape = shape
  body.add_child(collision)
 return visual

func _floor(key: String, color: Color) -> void:
 var center: Vector2 = travel_bounds.get_center()
 var extent: Vector2 = travel_bounds.size
 _box(Vector3(center.x, -0.25, center.y), Vector3(extent.x, 0.5, extent.y), material(key, color), 0.0, true)

func _light(key: String, color: Color) -> StandardMaterial3D:
 var mat: StandardMaterial3D = material(key, color)
 mat.emission_enabled = true
 mat.emission = color
 mat.emission_energy_multiplier = 0.35
 return mat

func _label(text: String, point: Vector3, label_scale: float, parent: Node3D = self) -> void:
 var label := Label3D.new()
 label.text = text
 label.position = point
 label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 label.pixel_size = label_scale
 label.outline_size = 10
 label.modulate = Color("#fff3bd")
 parent.add_child(label)

func mark_gate(selected: int) -> void:
 var lit := _light("target_gate", Color("#ffd36e"))
 var muted := _light("course_gate", Color("#34b4ad"))
 var cleared: StandardMaterial3D = material("cleared_gate", Color("#356c65"))
 for index in gate_lights.size():
  for visual in gate_lights[index].get_children():
   if visual is MeshInstance3D:
    visual.material_override = lit if index == selected else cleared if selected == -1 else muted

func _track_center(angle: float, offset := 0.0) -> Vector3:
 var center := Vector3(90 * cos(angle), 0, 51 * sin(angle))
 return center + _track_forward(angle).cross(Vector3.UP) * offset

func _track_forward(angle: float) -> Vector3:
 return Vector3(-90 * sin(angle), 0, 51 * cos(angle)).normalized()

func _strip(low: float, high: float, height: float, mat: StandardMaterial3D) -> void:
 var strip := SurfaceTool.new()
 strip.begin(Mesh.PRIMITIVE_TRIANGLES)
 mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 strip.set_material(mat)
 for index in CAR_SEGMENTS:
  var start := TAU * index / CAR_SEGMENTS
  var end := TAU * (index + 1) / CAR_SEGMENTS
  var a := _track_center(start, low)
  var b := _track_center(start, high)
  var c := _track_center(end, low)
  var d := _track_center(end, high)
  for p in [a, b, c, c, b, d]:
   strip.set_normal(Vector3.UP)
   strip.add_vertex(Vector3(p.x, height, p.z))
 mesh_instance(strip.commit(), mat, Vector3.ZERO)

func _make_circuit() -> void:
 _floor("infield", Color("#536941"))
 _strip(-ROAD_HALF_WIDTH, ROAD_HALF_WIDTH, .014, material("asphalt", Color("#292f36")))
 for side in [-1.0, 1.0]:
  var lip: float = ROAD_HALF_WIDTH * side
  _strip(minf(lip - .45 * side, lip), maxf(lip - .45 * side, lip), .022, material("edge", Color("#fff0d5")))
  for index in CAR_SEGMENTS:
   var start := _track_center(TAU * index / CAR_SEGMENTS, lip)
   var end := _track_center(TAU * (index + 1) / CAR_SEGMENTS, lip)
   var d := end - start
   var curb: StandardMaterial3D = material("rail%d" % (index % 2), Color("#d25445") if index % 2 == 0 else Color("#f4e9cd"))
   _box((start + end) * .5 + Vector3.UP * .26, Vector3(.46, .52, d.length() + .23), curb, atan2(d.x, d.z), true)

 spawn_point = _track_center(-.24) + Vector3.UP * .04
 spawn_heading = atan2(_track_forward(-.24).x, _track_forward(-.24).z)
 recovery_points.append(spawn_point)
 var chalk: StandardMaterial3D = material("line", Color("#f5f1e5"))
 var dark: StandardMaterial3D = material("checker_dark", Color("#172326"))
 for column in 14:
  for row in 2:
   _box(Vector3(83.5 + column, .025, -.5 + row), Vector3(1, .02, 1), chalk if (column + row) % 2 == 0 else dark)
 for index in 8:
  var angle := TAU * index / 8
  var center := _track_center(angle)
  var forward := _track_forward(angle)
  var side := forward.cross(Vector3.UP)
  var yaw := atan2(forward.x, forward.z)
  var signage := Node3D.new()
  add_child(signage)
  gate_lights.append(signage)
  gates.append({"center":center, "forward":forward, "half_width":ROAD_HALF_WIDTH})
  for sign_value in [-1.0, 1.0]:
   _box(center + side * (ROAD_HALF_WIDTH - .32) * sign_value + Vector3.UP * 1.6, Vector3(.35, 2.2, .4), chalk, yaw, false, signage)
  _box(center + Vector3.UP * 2.85, Vector3(ROAD_HALF_WIDTH * 2, .2, .33), chalk, yaw, false, signage)
  _label("START / FINISH" if index == 0 else str(index), center + Vector3.UP * 3.75, .047, signage)

func _make_rings() -> void:
 _floor("moor", Color("#385a56"))
 spawn_point = Vector3(0, .04, 110)
 spawn_heading = PI
 recovery_points.append(spawn_point)
 var points: Array[Vector3] = [
  Vector3(0, 8, 70), Vector3(35, 17, 35), Vector3(70, 26, -6), Vector3(55, 37, -55),
  Vector3(0, 32, -88), Vector3(-58, 20, -60), Vector3(-76, 12, 0), Vector3(-38, 18, 58)]
 var radius := 6.3
 var beacon: StandardMaterial3D = material("signage", Color("#e2eacf"))
 for index in points.size():
  var center := points[index]
  var previous: Vector3 = spawn_point if index == 0 else points[index - 1]
  var forward := (center - previous).normalized()
  gates.append({"center":center, "forward":forward, "radius":radius})
  var node := Node3D.new()
  node.position = center
  add_child(node)
  node.basis = Basis(Quaternion(Vector3.UP, forward))
  var torus := TorusMesh.new()
  torus.inner_radius = radius
  torus.outer_radius = radius + .7
  torus.rings = 40
  torus.ring_segments = 8
  mesh_instance(torus, beacon, Vector3.ZERO, Vector3.ONE, node)
  gate_lights.append(node)
  _label(str(index + 1), center + Vector3.UP * (radius + 2.1), .079)
  _box(Vector3(center.x, .12, center.z), Vector3(5, .24, 5), beacon)
 var launch: StandardMaterial3D = material("launch_pad", Color("#e6ce8b"))
 _box(spawn_point - Vector3.UP * .029, Vector3(8, .02, 8), launch)
 _label("BALLOON LAUNCH", spawn_point + Vector3(0, 2.8, -6), .037)

func _make_garden() -> void:
 _floor("garden_bank", Color("#607949"))
 spawn_point = Vector3(-3, .04, 2.8)
 spawn_heading = PI
 recovery_points.append(spawn_point)
 garden_root = Node3D.new()
 add_child(garden_root)
 var demo := Gardens.new()
 demo.load_puzzle(0)
 show_garden(demo)

func show_garden(garden) -> void:
 for child in garden_root.get_children():
  garden_root.remove_child(child)
  child.queue_free()
 var foliage: StandardMaterial3D = material("leaf", Color("#69a541"))
 var ripe: StandardMaterial3D = material("ripe", Color("#ffbfdf"))
 var sphere := SphereMesh.new()
 sphere.radial_segments = 12
 sphere.rings = 6
 for y in garden.rows.size():
  for x in garden.rows[y].length():
   var cell := Vector2i(x, y)
   var at := Vector3(x * GARDEN_PLOT - 2, 0, y * GARDEN_PLOT - 1)
   var tile: String = garden.tile(cell)
   var soil := Color("#507e98") if tile == "~" else Color("#a3a9a1") if tile == "#" else Color("#674d37")
   if tile == "B":
    soil = Color("#8e6941")
   _box(at + Vector3.UP * .08, Vector3(1.23, .16, 1.23), material("plot_" + tile, soil), 0, false, garden_root)
   var status: String = garden.plant_status(cell)
   if status not in ["", "Gathered", Gardens.EMPTY_BED]:
    mesh_instance(sphere, foliage, at + Vector3.UP * .23, Vector3(.52, .19, .52), garden_root)
    if status == "Ripe":
     mesh_instance(sphere, ripe, at + Vector3.UP * .41, Vector3(.38, .24, .38), garden_root)
   if garden.cell == cell:
    mesh_instance(sphere, material("pond_bot", Color("#ffd370")), at + Vector3.UP * .64, Vector3(.50, .43, .50), garden_root)
