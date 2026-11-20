extends CanvasLayer

const Course = preload("res://scripts/activities/course_run.gd")
const Editor = preload("res://scripts/activities/garden_editor.gd")
const Progress = preload("res://scripts/activities/activity_progress.gd")
const CIRCUIT_LAPS = 2
var game: Node3D
var current: ExplorerActivityWorld
var panel: PanelContainer
var title: Label
var stats: Label
var guide: Label
var arrow: Label
var garden: PanelContainer
var saved_pause := false
var course := Course.new()
var ride: CharacterBody3D
var progress := Progress.new()
var starting := false
var start_token := 0
var note := ""

func _ready() -> void:
 layer = 6
 panel = game.hud.panel()
 panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
 panel.position = Vector2(0, 20)
 panel.offset_left = 360
 panel.offset_right = -350
 panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(panel)
 var list := VBoxContainer.new()
 list.mouse_filter = Control.MOUSE_FILTER_IGNORE
 panel.add_child(list)
 title = game.hud.label("", 20, Color("#ffe4a3"))
 stats = game.hud.label("", 16)
 guide = game.hud.label("", 14, Color("#c4dbcc"))
 arrow = game.hud.label("", 18, Color("#ffe4a3"))
 for label in [title, stats, guide, arrow]:
  label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
  label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  label.mouse_filter = Control.MOUSE_FILTER_IGNORE
  list.add_child(label)
 panel.hide()
 if game.travel.persist_history:
  progress.load_from(Progress.DIRECTORY)
 garden = Editor.new()
 garden.hud = game.hud
 garden.progress = progress
 garden.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel"))
 garden.dismissed.connect(_close_editor)
 add_child(garden)
 game.travel.changed.connect(_travel_changed)

func flush_progress() -> void:
 garden.flush_draft()

func editor_open() -> bool:
 return garden != null and garden.visible

func _travel_changed() -> void:
 var next := game.woodland as ExplorerActivityWorld
 if next == current:
  return
 if editor_open():
  garden._close()
 current = next
 start_token += 1
 starting = false
 ride = null
 course = Course.new()
 note = ""
 garden.enter_place(current if is_instance_valid(current) and current.activity == "lily_code_garden" else null)
 panel.visible = is_instance_valid(current)
 if is_instance_valid(current):
  title.text = str(game.travel.place(game.travel.current_id).name)
  guide.text = "A / F5 opens the code editor" if current.activity == "lily_code_garden" else "A / F5 starts or restarts · N / R3 opens Places"
  _update_panel()

func _close_editor() -> void:
 game.pilot.paused = saved_pause
 game.controls.neutralize()

func handle_action(action: String) -> bool:
 if not is_instance_valid(current) or action not in ["croak", "activity"]:
  return false
 if game.pilot.paused or game.travel.busy or starting:
  return true
 if current.activity == "lily_code_garden":
  if game.rides.active():
   game.hud.toast("Step off your ride before opening the code editor.")
   return true
  saved_pause = game.pilot.paused
  game.pilot.paused = true
  game.controls.neutralize()
  garden.open()
 else:
  start_course()
 return true

func start_course() -> void:
 start_token += 1
 var token := start_token
 starting = true
 ride = null
 note = ""
 course = Course.new()
 game.rides.clear_for_travel()
 game.pilot.arrive_at_default_size(current.spawn_point)
 game.controls.neutralize()
 game.camera_rig.view_mode = 1
 game.camera_rig.initialized = false
 await get_tree().physics_frame
 await get_tree().physics_frame
 await get_tree().physics_frame
 if token != start_token:
  return
 starting = false
 if game.travel.busy or not is_instance_valid(current):
  return
 var car := current.activity == "car_circuit"
 game.rides.request("CAR" if car else "BALLOON")
 if not game.rides.active():
  note = "Could not board. A / F5 retries."
  return
 ride = game.rides.body
 course.setup(current.gates, CIRCUIT_LAPS if car else 0, ride.position)
 current.mark_gate(course.next_gate())

func _physics_process(delta: float) -> void:
 if not is_instance_valid(current) or course.next_gate() < 0 or game.pilot.paused:
  return
 if not is_instance_valid(ride) or ride != game.rides.body:
  course.order.clear()
  note = "Run ended. A / F5 restarts."
  current.mark_gate(0)
  return
 if course.advance(ride.position, delta):
  current.mark_gate(course.next_gate())
  if course.finished:
   var id := current.activity
   if progress.record_time(id, course.elapsed) != OK:
    game.hud.toast("Could not save activity progress.")
   game._event("course_finished", {"place_id":game.travel.current_id, "seconds":course.elapsed, "best_seconds":progress.best.get(id, course.elapsed)})

func _process(_delta: float) -> void:
 if is_instance_valid(current):
  _update_panel()

func _update_panel() -> void:
 arrow.text = ""
 if current.activity == "lily_code_garden":
  stats.text = "Program Pondbot to restore three lily gardens."
  return
 var car := current.activity == "car_circuit"
 if course.finished:
  stats.text = "Finished · %.2f s · personal best %.2f s" % [course.elapsed, progress.best.get(current.activity, course.elapsed)]
  return
 var index := course.next_gate()
 if index < 0:
  stats.text = note if not note.is_empty() else "Two timed laps with ordered gates." if car else "Fly through eight rings in order. Right stick controls altitude and strafe."
  if progress.best.has(current.activity):
   stats.text += "\nPersonal best · %.2f s" % progress.best[current.activity]
  return
 var gate: Dictionary = current.gates[index]
 var difference: Vector3 = gate.center - ride.position if is_instance_valid(ride) else Vector3.ZERO
 var next := "Gate %d / %d" % [index, current.gates.size() - 1] if car and index != 0 else "Start / finish" if car else "Ring %d / %d" % [index + 1, current.gates.size()]
 var lap := "Lap %d / %d · " % [mini(CIRCUIT_LAPS, 1 + int(maxi(0, course.cursor - 1) / current.gates.size())), CIRCUIT_LAPS] if car and course.timed else ""
 stats.text = "%s%s · %.0f m · %.2f s" % [lap, next, difference.length(), course.elapsed]
 if not car:
  arrow.text = "Ring altitude %.0f m · %+.0f m from you" % [gate.center.y, difference.y]
  var front: Vector3 = game.camera_rig.planar_forward()
  var direction := Vector2(difference.dot(front.cross(Vector3.UP)), difference.dot(front))
  if direction.length() > 1.0:
   var sector := posmod(roundi(atan2(direction.x, direction.y) * 4.0 / PI), 8)
   arrow.text = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"][sector] + "   " + arrow.text
