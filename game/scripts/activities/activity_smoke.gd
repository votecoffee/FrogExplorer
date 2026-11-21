extends Node

const Run = preload("res://scripts/activities/course_run.gd")
const Program = preload("res://scripts/activities/garden_program.gd")
const IDS = ["car_circuit", "balloon_rings", "lily_code_garden"]
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
 checks += 1
 print(("PASS " if value else "FAIL ") + message)
 if not value:
  failures.append(message)

func frames(count: int) -> void:
 for frame in count:
  await get_tree().physics_frame

func press_key(key: Key, ctrl := false) -> void:
 var event := InputEventKey.new()
 event.keycode = key
 event.physical_keycode = key
 event.ctrl_pressed = ctrl
 event.pressed = true
 Input.parse_input_event(event)
 var release := event.duplicate() as InputEventKey
 release.pressed = false
 Input.parse_input_event(release)
 # Deliver the shortcut before checking the editor state.
 Input.flush_buffered_events()

func cross_next(game, tick: float) -> void:
 var course = game.activities.course
 var gate: Dictionary = game.woodland.gates[course.next_gate()]
 var center: Vector3 = gate.center
 var direction: Vector3 = gate.forward
 course.previous = center - direction * 2
 game.rides.body.position = center + direction * 2
 game.activities._physics_process(tick)

func finish_by_steps(popup, program: String) -> void:
 popup.source.text = program
 popup.step_button.pressed.emit()
 for action in Program.MAX_STEPS:
  if popup.steps.is_empty():
   return
  popup.step_button.pressed.emit()
  await frames(1)

func travel(game, id: String) -> bool:
 game.travel.request(id)
 var until := Time.get_ticks_msec() + 10000
 while game.travel.busy and Time.get_ticks_msec() < until:
  await get_tree().physics_frame
 await frames(6)
 return game.travel.current_id == id

func run(game) -> void:
 var t: WorldTravel = game.travel
 check(game.activities.progress.folder.is_empty(), "Activity smoke keeps records and garden drafts in memory")
 game.travel_menu.open()
 for id in IDS:
  var item := t.place(id)
  check(id in game.travel_menu.destinations and not item.random_eligible, id + " appears in Places and is manual")
 game.travel_menu.close()
 for i in range(8):
  check(t.choose_random() not in IDS, "Random travel draw %d excludes activities" % (i + 1))

 var run_state := Run.new()
 var gate := {"center":Vector3.ZERO, "forward":Vector3.FORWARD, "radius":3.0}
 check(Run.crossing(Vector3(4,0,2), Vector3(4,0,-2), gate) < 0, "A ring miss does not count")
 check(Run.crossing(Vector3(0,0,-2), Vector3(0,0,2), gate) < 0, "Reverse ring crossings do not count")
 check(is_equal_approx(Run.crossing(Vector3(0,0,2), Vector3(0,0,-2), gate), .5), "Swept crossings count between ticks")

 run_state.setup([gate], 0, Vector3(0,0,1))
 run_state.advance(Vector3(0,0,-3), .4)
 check(run_state.splits.size() == 1 and is_equal_approx(run_state.elapsed, .1) and is_equal_approx(run_state.splits[0], .1), "A split uses the fractional crossing time within the tick")
 var has_car := await travel(game, IDS[0])
 check(has_car and game.woodland is ExplorerActivityWorld, "Travel stages a procedural car circuit")
 if has_car:
  press_key(KEY_F5)
  await frames(24)
  check(game.rides.kind == "CAR" and game.rides.body.is_on_floor(), "F5 action boards the grounded convertible")
  if game.rides.kind == "CAR":
   var world: ExplorerActivityWorld = game.woodland
   var course = game.activities.course
   var start: Vector3 = game.rides.body.position
   game.controls.remote_move = Vector2(0,-1)
   game.controls.remote_until = Time.get_ticks_msec() / 1000.0 + 3.5
   await frames(120)
   check(game.rides.body.position.distance_to(start) > 5.0, "The convertible accelerates on the physical track")
   check(course.timed and course.cursor == 1, "Driving crosses the first timing gate")
   check(course.splits.is_empty(), "Crossing the first start line only starts the clock")
   game.controls.neutralize()
   # Use swept, forward samples through the actual gate layout to validate order
   # and lap counting without a frame-rate-dependent automated race driver.
   course.setup(world.gates, 2, start)
   for step in course.order.size():
    cross_next(game, .25)
   check(course.finished and course.cursor == world.gates.size() * 2 + 1, "Two complete ordered laps finish the race")
   check(course.elapsed > 0, "Circuit timing starts on the first start-line crossing")
   check(game.activities.progress.best.has(IDS[0]), "The car circuit records a personal best")
   check(course.splits.size() == world.gates.size() * 2 and is_equal_approx(course.splits[-1], course.elapsed), "The car stores a separate split for each gate on both laps")
   var best: float = game.activities.progress.best.get(IDS[0], 0.0)
   press_key(KEY_F5)
   await frames(24)
   var replay = game.activities.course
   check(not game.activities.split_status.visible and not game.activities.reference.is_empty(), "Restart clears the old split display and loads the previous run for comparison")
   if not replay.order.is_empty():
    cross_next(game, .60)
    cross_next(game, .60)
    check(game.activities.split_status.visible and "behind" in game.activities.split_status.text, "The car HUD reports time lost at a gate")
    for step in range(2, replay.order.size()):
     cross_next(game, .60)
    check(is_equal_approx(game.activities.progress.best.get(IDS[0], 0.0), best), "A slower finished run leaves the existing race record intact")

 var has_balloon := await travel(game, IDS[1])
 check(has_balloon, "Travel arrives at the balloon course")
 if has_balloon:
  var prior_device: int = game.controls.device
  game.controls.device = 42
  var event := InputEventJoypadButton.new()
  event.device = 42
  event.button_index = JOY_BUTTON_A
  event.pressed = true
  Input.parse_input_event(event)
  await frames(12)
  var release := event.duplicate() as InputEventJoypadButton
  release.pressed = false
  Input.parse_input_event(release)
  game.controls.device = prior_device
  check(game.rides.kind == "BALLOON", "A action deploys the balloon")
  if game.rides.kind == "BALLOON":
   var air: ExplorerActivityWorld = game.woodland
   var course = game.activities.course
   var first_altitude: float = game.rides.body.position.y
   game.controls.remote_aux = Vector2(0, -.8)
   game.controls.remote_until = Time.get_ticks_msec() / 1000.0 + 1.5
   await frames(33)
   check(game.rides.body.position.y > first_altitude + 1.0, "Altitude control lifts the balloon toward the rings")
   game.camera_rig.view_mode = 0
   var first: Dictionary = air.gates[0]
   for frame in range(240):
    if course.cursor > 0:
     break
    var altitude_error: float = first.center.y - game.rides.body.position.y
    game.controls.remote_move = Vector2(0, -1)
    game.controls.remote_aux = Vector2(0, clampf(-.20 * altitude_error, -.8, .8))
    game.controls.remote_until = Time.get_ticks_msec() / 1000.0 + .5
    await frames(1)
   check(course.cursor == 1, "Flight controls navigate through the first physical ring")
   game.controls.neutralize()
   course.setup(air.gates, 0, game.rides.body.position)
   check(air.gates.size() == 8, "The balloon course has eight ordered rings")
   var second: Dictionary = air.gates[1]
   course.previous = second.center - second.forward * 2.0
   course.advance(second.center + second.forward * 2.0, .2)
   check(course.cursor == 0, "Crossing a later ring cannot skip the active ring")
   for step in air.gates.size():
    cross_next(game, .2)
   check(course.finished and course.elapsed > 0, "The ordered balloon-ring run finishes")
   check(game.activities.progress.best.has(IDS[1]), "The integrated course records a personal best")
   check(course.splits.size() == air.gates.size() and is_equal_approx(course.splits[-1], course.elapsed), "The balloon stores a split for every ring")
   press_key(KEY_F5)
   await frames(24)
   var replay = game.activities.course
   check(not game.activities.reference.is_empty() and replay.checkpoint_count == air.gates.size(), "The balloon loads its own split times")
   if not replay.order.is_empty():
    replay.elapsed = 0.0
    cross_next(game, .1)
    check(game.activities.split_status.visible and "Ring 1" in game.activities.split_status.text and "ahead" in game.activities.split_status.text, "The balloon HUD reports time gained at a ring")

 var has_garden := await travel(game, IDS[2])
 check(has_garden, "Travel arrives at Lily Code Garden")
 check(Program.compile("print(42)").has("error"), "Garden command parser rejects other languages")
 check(Program.compile("repeat 16\nrepeat 16\nwait\nwait\nend\nend").has("error"), "Expanded garden programs are bounded")
 check(Program.compile("repeat 3\nwater").has("error"), "Missing end produces a line error")

 # Each garden has a complete solution using the normal commands.
 var terrace_patrol := "repeat 2\nfill\nrepeat 2\nhop east\nwater\nwait\ngather\nend\nrepeat 2\nhop west\nend\nhop north\nend"
 var solutions := [
  "fill\nrepeat 2\nhop east\nwater\nwait\ngather\nend",
  "fill\nhop east\nhop east\nwater\nwait\ngather\nhop south\nhop east\nwater\nwait\ngather\nhop west\nhop south\nwater\nwait\ngather",
  "fill\nhop east\nhop east\nwater\nwater\nhop west\nhop west\nfill\nhop east\nhop east\ngather\nhop south\nhop south\nwater\nwait\ngather\nhop west\nwater\nwater\nwait\ngather",
  "fill\nhop east\nwater\nwait\ngather\nhop north\nwater\nhop west\nfill\nhop east\ngather\nhop east\nwater\nwait\ngather\nhop south\nwater\nwait\ngather",
  "fill\nhop south\nhop south\nwater\nhop south\nhop east\nwater\nwater\nwait\ngather\nhop west\nhop north\ngather\nhop north\nhop north\nfill\nhop east\nhop east\nwater\nwater\nwait\ngather\nhop south\nhop east\nhop south\nwater\nwait\ngather",
 ]
 check(solutions.size() == Program.PUZZLES.size(), "Every garden has a smoke-test solution")
 for index in solutions.size():
  var program := Program.new()
  program.load_puzzle(index)
  var compiled := Program.compile(solutions[index])
  var error := str(compiled.get("error",""))
  for action in compiled.get("steps", []):
   if error.is_empty():
    error = program.step(action)
  check(error.is_empty() and program.harvested == program.plants.size() and program.turn == Program.PUZZLES[index].target, "Garden puzzle %d can be solved at its action target" % (index + 1))

 if has_garden:
  press_key(KEY_F5)
  await frames(4)
  var popup = game.activities.garden
  check(popup.visible and game.pilot.paused and popup.source.has_focus(), "The garden popup owns keyboard focus and pauses movement")
  check("Target · 9 actions" in popup.score.text and "Personal best · —" in popup.score.text, "A fresh board displays its target and an empty personal best")
  game.controls.pending.append("travel_home")
  await frames(4)
  check(t.current_id == IDS[2] and not t.busy, "Game shortcuts are suspended while editing")
  var starter: String = popup.source.text
  var first_card: Node = popup.board.get_child(0)
  var first_plot: Node = popup.world.garden_root.get_child(0)
  var puzzle_id: String = Program.PUZZLES[0].id
  popup.check_button.pressed.emit()
  check("9 actions to harvest all 2 lilies" in popup.status.text and "meets target" in popup.status.text, "Check predicts the starter program's action count and target")
  check(popup.garden.turn == 0 and not popup.progress.solved.has(puzzle_id) and not popup.progress.garden_best.has(puzzle_id) and popup.board.get_child(0) == first_card and popup.world.garden_root.get_child(0) == first_plot, "Check preserves both boards and the completion record")
  popup.source.set_caret_line(0)
  popup.source.set_caret_column(0)
  popup.source.insert_text_at_caret("# Edit after checking\n")
  await frames(3)
  check("Code changed" in popup.status.text, "Editing invalidates the previous check result")
  popup.source.set_caret_line(0)
  popup.source.set_caret_column(0)
  popup.source.insert_text_at_caret("# Check this edit immediately\n")
  popup.check_button.pressed.emit()
  await frames(3)
  check("9 actions to harvest all 2 lilies" in popup.status.text, "Check keeps a result for the current draft when a text change is delivered later")
  popup.source.text = "fill\nhop east\nwater"
  popup.check_button.pressed.emit()
  check("0 of 2 lilies harvested in 3 actions" in popup.status.text, "Check distinguishes a valid unfinished program")
  popup.source.text = "fill\nrepeat 3\n  hop east\nend"
  popup.check_button.pressed.emit()
  check("Check · Line 3" in popup.status.text and "blocks this hop" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([2]), "Check marks a blocked command inside a loop")
  popup.source.text = "fill\nunknown"
  popup.check_button.pressed.emit()
  check("Line 2" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([1]), "Check marks a compile error before running")
  popup.source.text = starter + "hop north"
  popup.check_button.pressed.emit()
  check("9 actions to harvest all 2 lilies" in popup.status.text, "Check stops at the final harvest just like Run")
  popup.source.text = starter
  press_key(KEY_F10)
  await frames(18)
  check(popup.garden.turn == 1 and popup.garden.tank == Program.CAPACITY and not popup.running, "F10 executes one command and waits for the next step")
  var paused_note: String = popup.status.text
  popup.check_button.pressed.emit()
  check(popup.check_button.disabled and popup.garden.turn == 1 and popup.status.text == paused_note, "Check cannot interrupt a paused program")
  check(popup.source.get_executing_lines() == PackedInt32Array([1]) and "next line 4" in popup.status.text, "The editor marks fill and shows the line of the next command")
  popup.step_button.pressed.emit()
  check(popup.garden.turn == 2 and popup.garden.cell == Vector2i(1, 0) and not popup.source.editable, "The Step button advances the same board and protects the active program")
  press_key(KEY_ENTER, true)
  check(popup.running and popup.step_button.disabled and popup.run_button.text.begins_with("Pause"), "Ctrl+Enter resumes the stepped program")
  var paused_turn: int = popup.garden.turn
  press_key(KEY_ENTER, true)
  await frames(18)
  check(not popup.running and popup.garden.turn == paused_turn and popup.run_button.text.begins_with("Resume"), "Ctrl+Enter pauses without advancing the board")
  press_key(KEY_F10)
  check(popup.garden.turn == paused_turn + 1 and not popup.running, "F10 steps the paused program at its current position")
  press_key(KEY_ENTER, true)
  await frames(3)
  var deadline := Time.get_ticks_msec() + 8000
  while popup.running and Time.get_ticks_msec() < deadline:
   await get_tree().process_frame
  check(popup.progress.solved.get(Program.PUZZLES[0].id, false) and popup.garden.harvested == 2, "The popup animates and completes the starter program")
  check(popup.source.get_executing_lines() == PackedInt32Array([6]) and popup.source.editable, "The completed loop marks its gather command and unlocks the editor")
  check(popup.progress.garden_best.get("first_bloom", 0) == 9 and "Target met" in popup.score.text, "A finished program saves the action count and marks the target")
  popup.step_button.pressed.emit()
  popup.stop_button.pressed.emit()
  check(popup.garden.turn == 1 and popup.source.text == starter and popup.source.editable, "Stop preserves the current board and draft for editing")
  popup.check_button.pressed.emit()
  check("9 actions to harvest all 2 lilies" in popup.status.text and popup.garden.turn == 1 and popup.garden.tank == Program.CAPACITY, "Check starts fresh while preserving a stopped board")
  popup.step_button.pressed.emit()
  popup._reset()
  check(popup.garden.turn == 0 and popup.garden.tank == 0 and popup.source.get_executing_lines().is_empty() and popup.source.text == starter, "Reset clears a paused run and keeps the draft")
  popup.source.text = "# The bank is north of the spring\nhop north"
  popup.step_button.pressed.emit()
  check("Line 2" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([1]) and popup.source.editable, "A blocked step marks its source line and lets the player correct it")
  popup.source.text = "fill\nunknown"
  popup.step_button.pressed.emit()
  check("Line 2" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([1]) and popup.garden.turn == 0, "A syntax error from Step marks the offending line before the board changes")
  popup.source.text = starter
  popup.step_button.pressed.emit()
  press_key(KEY_ESCAPE)
  await frames(4)
  check(not popup.visible and not game.pilot.paused, "Closing the popup restores frog controls")
  check(popup.steps.is_empty() and popup.source.text == starter and popup.source.editable, "Closing a paused program releases the editor and keeps its draft")

  press_key(KEY_F5)
  await frames(4)
  for index in [3, 4]:
   var item: Dictionary = Program.PUZZLES[index]
   popup.chooser.item_selected.emit(index)
   var plot_count: int = item.rows.size() * item.rows[0].length()
   check(popup.visible and popup.chooser.selected == index and popup.board.get_child_count() == plot_count and popup.world.garden_root.get_child_count() > plot_count, item.name + " loads on the popup board and in the 3D garden")
   var start := Vector2i(0, 2) if index == 3 else Vector2i.ZERO
   check(popup.garden.cell == start and popup.garden.plants.size() == 4, item.name + " starts at its spring with four unharvested lilies")
   await finish_by_steps(popup, terrace_patrol if index == 3 else solutions[index])
   check(popup.garden.harvested == 4 and popup.progress.solved.get(item.id, false) and "✓" in popup.chooser.get_item_text(index), item.name + " completes when stepped and receives its own check mark")
  popup.chooser.item_selected.emit(3)
  check(popup.source.text == terrace_patrol and popup.garden.harvested == 0, "Returning to Twin terraces restores its draft on a fresh board")
  check(popup.progress.garden_best.get("twin_terraces", 0) == 21 and "Target · 19 actions" in popup.score.text, "An above-target completion still records a personal best")
  popup.check_button.pressed.emit()
  check("21 actions to harvest all 4 lilies · 2 over target" in popup.status.text, "Check reports how far a valid plan is above the target")
  popup.source.text = solutions[3]
  popup.check_button.pressed.emit()
  check("19 actions to harvest all 4 lilies · meets target" in popup.status.text and popup.progress.garden_best.get("twin_terraces", 0) == 21, "Checking a better route leaves the personal best for a completed run")
  await finish_by_steps(popup, solutions[3])
  check(popup.progress.garden_best.get("twin_terraces", 0) == 19 and "Target met" in popup.score.text and "New personal best" in popup.status.text, "A more efficient program updates the record and marks the target")
  await finish_by_steps(popup, terrace_patrol)
  check(popup.garden.turn == 21 and popup.progress.garden_best.get("twin_terraces", 0) == 19 and "19 actions" in popup.score.text, "A slower clear retains the target and the lowest action count")
  await finish_by_steps(popup, "wait")
  check(popup.garden.harvested == 0 and popup.progress.garden_best.get("twin_terraces", 0) == 19, "A program that ends early does not replace a completed score")
  popup._close()

 check(await travel(game, "home_woodland_pond"), "Return home from activities")
 print("ACTIVITY_SMOKE " + JSON.stringify({"checks":checks, "failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
