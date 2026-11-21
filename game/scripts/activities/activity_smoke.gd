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

func wait_for_garden_pause(popup) -> void:
 var deadline := Time.get_ticks_msec() + 8000
 while popup.running and Time.get_ticks_msec() < deadline:
  await get_tree().process_frame

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
 var called := Program.compile("routine rest\nwait\nend\nroutine rest_twice\nrepeat 2\ncall rest\nend\nend\ncall rest_twice")
 var called_steps: Array = called.get("steps", [])
 check(called_steps.size() == 2 and called_steps[0].line == 1 and called_steps[1].line == 1, "Routines compose with earlier routines and keep their source lines through a repeat")
 check(Program.compile("routine 1bad\nwait\nend").get("line", -1) == 0, "A routine requires a valid name")
 check(Program.compile("routine pause\nwait\nend\nroutine PAUSE\nwait\nend").get("line", -1) == 3, "Duplicate routine names report the new definition")
 check(Program.compile("routine again\ncall again\nend\ncall again").get("line", -1) == 1, "A routine cannot call itself before its definition closes")
 check(Program.compile("call later\nroutine later\nwait\nend").get("line", -1) == 0, "Calling an undefined routine reports the call site")
 check(Program.compile("routine unfinished\nwait").get("line", -1) == 0, "An unfinished routine points to its opening line")
 check(Program.compile("repeat 2\nroutine nested\nwait\nend\nend").get("line", -1) == 1, "Routine definitions stay outside repeat blocks")
 var full_routine := "routine full\nrepeat 16\nrepeat 16\nwait\nend\nend\nend\ncall full"
 check(Program.compile(full_routine).get("steps", []).size() == Program.MAX_STEPS and Program.compile(full_routine + "\ncall full").get("line", -1) == 8, "Routine expansion allows exactly 256 actions and rejects a call that exceeds the limit")
 check(Program.compile("fill\nif muddy\nwait\nend").get("line", -1) == 1, "An unknown condition marks the if line")
 check(Program.compile("else\nwait\nend").get("line", -1) == 0, "An else requires an enclosing if")
 check(Program.compile("if ripe\nwait\nelse\nfill\nelse\nwait\nend").get("line", -1) == 4, "A second else points to the duplicate line")
 check(Program.compile("if ripe\ngather\nelse\nend").get("line", -1) == 2, "An empty fallback points to its else line")
 check(Program.compile("if clear upward\nwait\nend").get("line", -1) == 0, "A clear condition requires a valid direction")
 check(Program.compile("while clear upward\nwait\nend").get("line", -1) == 0, "While validates its conditions and directions")
 check(Program.compile("while spring\nwait\nelse\nfill\nend").get("line", -1) == 2, "Else belongs to if blocks")
 check(Program.compile("while spring\nwait").get("line", -1) == 0, "An unclosed while marks its opening line")
 check(Program.compile("if not\nwait\nend").get("line", -1) == 0, "A negated condition requires a test")
 check(Program.compile("fill\nif spring and\nwait\nend").get("line", -1) == 1, "A dangling conjunction points to the condition line")
 check(Program.compile("while clear or has_water\nwait\nend").get("line", -1) == 0 and Program.compile("if spring or and ripe\nwait\nend").get("line", -1) == 0, "Compound tests reject missing directions and operands")
 var tank_error := Program.compile("fill\nif has_water north\nwait\nend")
 check(tank_error.get("line", -1) == 1 and "tank" in tank_error.get("error", ""), "A tank condition rejects a direction and explains why")
 check(Program.compile("if lily upward\nwait\nend").get("line", -1) == 0, "A lily condition rejects an unknown direction")
 check(Program.compile("if ripe\ngather").get("line", -1) == 0, "An unclosed conditional marks its opening line")
 check(Program.compile("repeat 2\nif spring\nrepeat 2\nif thirsty\nif ripe\nwait\nend\nend\nend\nend\nend").get("line", -1) == 4, "Repeats and conditions share a bounded nesting depth")

 # Each garden has a complete solution using the normal commands.
 var terrace_patrol := "repeat 2\nfill\nrepeat 2\nhop east\nwater\nwait\ngather\nend\nrepeat 2\nhop west\nend\nhop north\nend"
 var spillway_solution := "routine finish_lily\n  wait\n  gather\nend\nfill\nhop east\nhop east\nwater\nwater\nhop east\nwater\ncall finish_lily\nhop west\ngather\nhop west\nhop west\nfill\nhop east\nwater\ncall finish_lily\nhop west\nhop north\nhop north\nhop east\nwater\nhop west\nfill\nhop east\ngather\nhop east\nwater\nwater\ncall finish_lily\nhop east\nwater\ncall finish_lily"
 var patchwork_solution := "routine water_plot\n  repeat 2\n    if thirsty\n      if has_water\n        water\n      end\n    end\n  end\nend\nroutine finish_plot\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\nfill\nhop east\nhop east\ncall water_plot\nhop east\ncall water_plot\ncall finish_plot\nhop west\ncall finish_plot\nhop west\nhop west\nhop north\nhop north\nfill\nhop east\ncall water_plot\ncall finish_plot\nhop east\nhop east\ncall water_plot\ncall finish_plot"
 var banks_solution := "routine to_lily\n  if clear east\n    repeat 2\n      hop east\n    end\n  else\n    hop south\n    repeat 2\n      hop east\n    end\n    hop north\n  end\nend\nroutine to_spring\n  if clear west\n    repeat 2\n      hop west\n    end\n  else\n    hop south\n    repeat 2\n      hop west\n    end\n    hop north\n  end\nend\nroutine tend\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  wait\n  gather\nend\nfill\ncall to_lily\ncall tend\ncall to_spring\nrepeat 2\n  hop north\nend\ncall to_lily\ncall tend\n"
 var lantern_solution := "routine tend_plot\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\nroutine sweep_east\n  while clear east\n    hop east\n    call tend_plot\n  end\nend\nfill\ncall sweep_east\nwhile clear west\n  hop west\nend\nrepeat 2\n  hop north\nend\nfill\ncall sweep_east\n"
 var relay_solution: String = Program.PUZZLES[9].draft + "while not spring and clear west\n  hop west\nend\nrepeat 2\n  hop north\nend\nfill\ncall sweep_east\nwhile not spring and clear west\n  hop west\nend\nfill\ncall sweep_east\n"
 var channels_solution: String = Program.PUZZLES[10].draft + "while not spring\n  hop west\nend\nfill\ncall sweep_east\n"
 var solutions := [
  "fill\nrepeat 2\nhop east\nwater\nwait\ngather\nend",
  "fill\nhop east\nhop east\nwater\nwait\ngather\nhop south\nhop east\nwater\nwait\ngather\nhop west\nhop south\nwater\nwait\ngather",
  "fill\nhop east\nhop east\nwater\nwater\nhop west\nhop west\nfill\nhop east\nhop east\ngather\nhop south\nhop south\nwater\nwait\ngather\nhop west\nwater\nwater\nwait\ngather",
  "fill\nhop east\nwater\nwait\ngather\nhop north\nwater\nhop west\nfill\nhop east\ngather\nhop east\nwater\nwait\ngather\nhop south\nwater\nwait\ngather",
  "fill\nhop south\nhop south\nwater\nhop south\nhop east\nwater\nwater\nwait\ngather\nhop west\nhop north\ngather\nhop north\nhop north\nfill\nhop east\nhop east\nwater\nwater\nwait\ngather\nhop south\nhop east\nhop south\nwater\nwait\ngather",
  spillway_solution,
  patchwork_solution,
  banks_solution,
  lantern_solution,
  relay_solution,
  channels_solution,
 ]
 check(solutions.size() == Program.PUZZLES.size(), "Every garden has a smoke-test solution")
 for index in solutions.size():
  var program := Program.new()
  program.load_puzzle(index)
  var compiled := Program.compile(solutions[index])
  var error := str(compiled.get("error",""))
  var instructions: Array = compiled.get("steps", [])
  var cursor := program.next_action_index(instructions, 0)
  while error.is_empty() and cursor < instructions.size():
   error = program.step(instructions[cursor])
   if program.is_complete():
    break
   cursor = program.next_action_index(instructions, cursor + 1)
  check(error.is_empty() and program.runtime_error.is_empty() and program.is_complete() and program.turn == Program.PUZZLES[index].target, "Garden puzzle %d can be solved at its action target" % (index + 1))

 if has_garden:
  press_key(KEY_F5)
  await frames(4)
  var popup = game.activities.garden
  check(popup.visible and game.pilot.paused and popup.source.has_focus(), "The garden popup owns keyboard focus and pauses movement")
  check("Target · 9 actions" in popup.score.text and "Personal best · —" in popup.score.text and not popup.best_button.visible, "A fresh board displays its target and an empty personal best")
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
  popup.review_button.pressed.emit()
  check(popup.review_controls.visible and popup.review_slider.value == 0 and popup.review_slider.max_value == 9 and popup.review_slider.has_focus(), "Review opens the checked program at action zero with the slider focused")
  press_key(KEY_RIGHT)
  check(popup.review_slider.value == 1 and popup.source.get_executing_lines() == PackedInt32Array([1]), "The arrow keys scrub the focused preview slider")
  popup.review_slider.value = 4
  check("Ripe" in popup.board.get_child(1).get_child(0).text and "Water 2 / 3" in popup.info.text and popup.source.get_executing_lines() == PackedInt32Array([5]), "Scrubbing shows the predicted plant, tank and source line")
  popup.review_slider.value = 9
  var preview_harvest: bool = "Lilies 2 / 2" in popup.info.text
  popup.review_slider.value = 1
  check(preview_harvest and "Lilies 0 / 2" in popup.info.text and "Water 3 / 3" in popup.info.text, "Scrubbing backward reconstructs the earlier state")
  check(popup.garden.turn == 0 and popup.world.garden_root.get_child(0) == first_plot and not popup.progress.garden_best.has(puzzle_id), "Review leaves the live scene and personal best intact")
  popup.source.set_caret_line(0)
  popup.source.set_caret_column(0)
  popup.source.insert_text_at_caret("# Edit after checking\n")
  await frames(3)
  check("Code changed" in popup.status.text and not popup.review_controls.visible and not popup.review_button.visible and "Water 0 / 3" in popup.info.text, "Editing invalidates the checked program and returns to the live board")
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
  popup.review_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check(popup.review_slider.max_value == 3 and "Blocked" in popup.review_position.text and "●" in popup.board.get_child(2).get_child(0).text and popup.source.get_executing_lines() == PackedInt32Array([2]), "A blocked hop ends the preview on the last reachable tile")
  popup.review_button.pressed.emit()
  check(not popup.review_controls.visible and "Water 0 / 3" in popup.info.text and "Check · Line 3" in popup.status.text, "Back to board restores the live grid and keeps the check result")
  popup.source.text = "hop north"
  popup.check_button.pressed.emit()
  popup.review_button.pressed.emit()
  check(popup.review_controls.visible and not popup.review_slider.visible and "0 / 0 actions · Blocked" in popup.review_position.text, "A command blocked on the first action still shows the starting tile")
  popup.source.text = "fill\nunknown"
  popup.check_button.pressed.emit()
  check("Line 2" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([1]) and not popup.review_button.visible, "A compile error marks the line and clears the preview")
  popup.source.text = starter + "hop north"
  popup.check_button.pressed.emit()
  check("9 actions to harvest all 2 lilies" in popup.status.text, "Check stops at the final harvest just like Run")
  popup.source.text = starter
  popup.check_button.pressed.emit()
  popup.review_button.pressed.emit()
  popup.review_slider.value = 9
  press_key(KEY_F10)
  await frames(18)
  check(not popup.review_controls.visible and not popup.review_button.visible and "Lilies 0 / 2" in popup.info.text, "Stepping starts the live program and closes Review")
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
  await wait_for_garden_pause(popup)
  check(popup.progress.solved.get(Program.PUZZLES[0].id, false) and popup.garden.harvested == 2, "The popup animates and completes the starter program")
  check(popup.source.get_executing_lines() == PackedInt32Array([6]) and popup.source.editable, "The completed loop marks its gather command and unlocks the editor")
  check(popup.progress.garden_best.get("first_bloom", 0) == 9 and "Target met" in popup.score.text, "A finished program saves the action count and marks the target")
  check(popup.best_button.visible and popup.progress.garden_best_programs.get(puzzle_id) == starter, "Completing a puzzle makes the recorded program available")
  var revision := "# Try a shorter route later\nwait\n"
  popup.source.text = revision
  popup.check_button.pressed.emit()
  popup.review_button.pressed.emit()
  popup.review_slider.value = 1
  var live_plot: Node = popup.world.garden_root.get_child(0)
  popup.best_button.pressed.emit()
  check(popup.best_panel.visible and popup.best_source.text == starter and not popup.best_source.editable and popup.source.text == revision, "Best program shows the saved code in a separate read-only view")
  check(popup.review_controls.visible and popup.review_slider.has_focus() and popup.review_slider.value == 0 and "Best run · 0 / 9 actions" == popup.review_position.text and "Water 0 / 3" in popup.info.text, "Best program opens the saved replay at the starting board")
  press_key(KEY_RIGHT)
  check(popup.review_slider.value == 1 and popup.best_source.get_executing_lines() == PackedInt32Array([1]) and popup.source.get_executing_lines().is_empty() and "Water 3 / 3" in popup.info.text, "The saved replay uses the arrow keys and marks only the recorded source")
  popup.review_slider.value = 9
  var replay_harvest: bool = "Lilies 2 / 2" in popup.info.text and popup.best_source.get_executing_lines() == PackedInt32Array([6])
  popup.review_slider.value = 2
  check(replay_harvest and "Lilies 0 / 2" in popup.info.text and "●" in popup.board.get_child(1).get_child(0).text and popup.world.garden_root.get_child(0) == live_plot, "Scrubbing the saved run in both directions leaves the live garden alone")
  press_key(KEY_F10)
  press_key(KEY_ENTER, true)
  await frames(4)
  check(popup.best_panel.visible and not popup.running and popup.garden.turn == 9, "Run and Step leave the board idle while reading the best program")
  press_key(KEY_ESCAPE)
  check(popup.visible and not popup.best_panel.visible and not popup.review_controls.visible and popup.source.has_focus() and popup.source.text == revision and "Lilies 2 / 2" in popup.info.text, "Escape restores the current draft and live board")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 1
  check(popup.review_controls.visible and "Preview · 1 / 1 actions" == popup.review_position.text and popup.source.get_executing_lines() == PackedInt32Array([1]), "The previously checked draft still has its own route")
  popup.review_button.pressed.emit()
  popup.progress.garden_best_programs[puzzle_id] = "fill\nhop north"
  popup.best_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check("Best run · 1 / 1 actions · Blocked" == popup.review_position.text and "Line 2" in popup.best_title.text and popup.best_source.get_executing_lines() == PackedInt32Array([1]), "A saved route blocked under current rules shows its last reachable action")
  popup.best_button.pressed.emit()
  popup.progress.garden_best_programs[puzzle_id] = "unknown"
  popup.best_button.pressed.emit()
  check(popup.best_panel.visible and not popup.review_controls.visible and "Replay unavailable · Line 1" in popup.best_title.text and popup.best_source.text == "unknown", "Code that cannot be replayed remains available to read")
  popup.best_button.pressed.emit()
  popup.progress.garden_best_programs[puzzle_id] = starter
  await finish_by_steps(popup, "# Same route, different comment\n" + starter)
  check(popup.garden.turn == 9 and popup.progress.garden_best_programs.get(puzzle_id) == starter, "A tied run keeps the previously recorded code")
  popup.source.text = starter
  popup.source.set_caret_line(3)
  press_key(KEY_F9)
  check(popup.source.is_line_breakpointed(3), "F9 sets a breakpoint on the current command")
  popup.check_button.pressed.emit()
  check("9 actions to harvest all 2 lilies" in popup.status.text and popup.source.is_line_breakpointed(3), "Check previews the whole run with breakpoints enabled")
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check(not popup.running and popup.garden.turn == 1 and popup.garden.cell == Vector2i.ZERO and "Breakpoint · line 4" in popup.status.text and popup.run_button.text.begins_with("Resume"), "Run pauses before the marked hop changes the board")
  popup.best_button.pressed.emit()
  check(popup.best_button.disabled and not popup.best_panel.visible, "A paused program keeps Best program closed")
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check(not popup.running and popup.garden.turn == 5 and popup.garden.cell == Vector2i(1, 0) and "Breakpoint · line 4" in popup.status.text, "Resume runs the current hop and stops on the next loop iteration")
  press_key(KEY_F10)
  check(not popup.running and popup.garden.turn == 6 and popup.garden.cell == Vector2i(2, 0), "F10 executes one command while paused at a breakpoint")
  press_key(KEY_F9)
  check(not popup.source.is_line_breakpointed(3), "F9 removes the breakpoint")
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check(popup.garden.turn == 9 and popup.garden.harvested == 2, "Resuming after stepping completes the same program")
  popup.source.set_caret_line(3)
  press_key(KEY_F9)
  popup._reset()
  check(popup.garden.turn == 0 and popup.source.is_line_breakpointed(3), "Reset board keeps breakpoints for another run")
  press_key(KEY_F9)
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
  popup.source.set_caret_line(1)
  press_key(KEY_F9)
  for index in [3, 4]:
   var item: Dictionary = Program.PUZZLES[index]
   popup.chooser.item_selected.emit(index)
   var plot_count: int = item.rows.size() * item.rows[0].length()
   check(popup.visible and popup.chooser.selected == index and popup.source.get_breakpointed_lines().is_empty() and popup.board.get_child_count() == plot_count and popup.world.garden_root.get_child_count() > plot_count, item.name + " loads on both boards with its own editor state")
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
  check(popup.progress.garden_best.get("twin_terraces", 0) == 19 and popup.progress.garden_best_programs.get("twin_terraces") == solutions[3] and "Target met" in popup.score.text and "New personal best" in popup.status.text, "A more efficient program saves its code with the new record")
  await finish_by_steps(popup, terrace_patrol)
  check(popup.garden.turn == 21 and popup.progress.garden_best.get("twin_terraces", 0) == 19 and popup.progress.garden_best_programs.get("twin_terraces") == solutions[3], "A slower clear retains the lowest action count and its program")
  await finish_by_steps(popup, "wait")
  check(popup.garden.harvested == 0 and popup.progress.garden_best.get("twin_terraces", 0) == 19, "A program that ends early does not replace a completed score")
  popup.best_button.pressed.emit()
  popup.chooser.item_selected.emit(5)
  check(not popup.best_panel.visible and not popup.best_button.visible and not popup.review_controls.visible and popup.source.visible, "Changing puzzles closes the saved replay and opens the other draft")
  var spillway: Dictionary = Program.PUZZLES[popup.puzzle]
  check(spillway.id == "stone_spillway" and popup.board.get_child_count() == 16 and popup.garden.cell == Vector2i(0, 3) and "routine finish_lily" in popup.source.text, "Stone spillway opens at its lower spring with a reusable routine in the draft")
  popup.check_button.pressed.emit()
  check("1 of 6 lilies harvested" in popup.status.text, "The starter routine tends one lily")
  popup.source.text = spillway_solution
  popup.check_button.pressed.emit()
  check("36 actions to harvest all 6 lilies · meets target" in popup.status.text and not popup.progress.solved.has(spillway.id), "Check counts the actions inside calls without completing Stone spillway")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 8
  check(popup.source.get_executing_lines() == PackedInt32Array([1]), "Review highlights the routine body at the called wait command")
  popup.review_button.pressed.emit()
  popup.source.set_caret_line(1)
  press_key(KEY_F9)
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check("Breakpoint · line 2" in popup.status.text and popup.garden.turn == 7, "A breakpoint inside a routine pauses before its command")
  press_key(KEY_F10)
  check(popup.garden.turn == 8 and not popup.running, "Step runs a single command inside the routine")
  popup.stop_button.pressed.emit()
  await finish_by_steps(popup, spillway_solution)
  check(popup.garden.harvested == 6 and popup.progress.garden_best.get(spillway.id, 0) == 36, "Stepping through routine calls completes Stone spillway at the target")
  popup.chooser.item_selected.emit(6)
  var patchwork: Dictionary = Program.PUZZLES[popup.puzzle]
  check(patchwork.id == "patchwork_beds" and popup.board.get_child_count() == 12 and popup.garden.cell == Vector2i(0, 2) and "if thirsty" in popup.source.text, "Patchwork beds opens with empty plots and a conditional starter program")
  popup.check_button.pressed.emit()
  check("2 of 4 lilies harvested in 11 actions" in popup.status.text, "The starter handles an empty plot, a double lily, and a single lily")
  popup.source.text = "if ripe\nhop north\nend"
  popup.check_button.pressed.emit()
  check("0 of 4 lilies harvested in 0 actions" in popup.status.text and not popup.review_button.visible, "Check handles a program whose guards skip every command")
  press_key(KEY_F10)
  check(popup.steps.is_empty() and popup.garden.turn == 0 and "Program ended" in popup.status.text, "Step ends a program with no eligible command")
  popup.source.text = "if not has_water\nfill\nend\nif has_water\nhop east\nend\nif ripe\nhop north\nend"
  popup.check_button.pressed.emit()
  popup.review_button.pressed.emit()
  popup.review_slider.value = 2
  check(popup.review_slider.max_value == 2 and "Water 3 / 3" in popup.info.text and popup.source.get_executing_lines() == PackedInt32Array([4]), "Review includes both matching conditions and omits the blocked hop behind a false guard")
  press_key(KEY_F10)
  press_key(KEY_F10)
  check(popup.steps.is_empty() and popup.garden.turn == 2 and popup.garden.cell == Vector2i(1, 2), "Step evaluates the following guard with the new tank state")
  popup.source.text = patchwork_solution
  popup.check_button.pressed.emit()
  check("26 actions to harvest all 4 lilies · meets target" in popup.status.text and not popup.progress.solved.has(patchwork.id), "Check predicts the exact score without counting conditions")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 4
  check(popup.source.get_executing_lines() == PackedInt32Array([4]), "Review highlights the first water command inside nested conditions")
  popup.review_button.pressed.emit()
  popup.source.set_caret_line(4)
  press_key(KEY_F9)
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check("Breakpoint · line 5 · 3 actions" in popup.status.text and popup.garden.turn == 3, "Run reaches the breakpoint inside the matching condition")
  popup.stop_button.pressed.emit()
  await finish_by_steps(popup, patchwork_solution)
  check(popup.garden.harvested == 4 and popup.progress.garden_best.get(patchwork.id, 0) == 26, "Stepping through conditions saves the verified Patchwork beds score")
  popup.chooser.item_selected.emit(7)
  var banks: Dictionary = Program.PUZZLES[popup.puzzle]
  check(banks.id == "forked_banks" and popup.board.get_child_count() == 16 and popup.garden.cell == Vector2i(0, 2) and "if clear east" in popup.source.text, "Forked banks starts at the blocked bank with a route routine")
  popup.check_button.pressed.emit()
  check("0 of 2 lilies harvested in 6 actions" in popup.status.text, "The starter takes the detour to the double lily")
  popup.source.text = "if not has_water\nfill\nelse\nhop east\nend"
  popup.check_button.pressed.emit()
  check("0 of 2 lilies harvested in 1 action" in popup.status.text, "An if branch runs once even when its action changes the condition")
  popup.source.text = "if not clear west\nwait\nelse\nhop west\nend"
  popup.check_button.pressed.emit()
  check("0 of 2 lilies harvested in 1 action" in popup.status.text, "The board edge counts as blocked")
  popup.source.text = banks_solution
  popup.check_button.pressed.emit()
  check("20 actions to harvest all 2 lilies · meets target" in popup.status.text and not popup.progress.solved.has(banks.id), "Check predicts both branches of the route routine and its exact action count")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 2
  var detour_shown: bool = popup.source.get_executing_lines() == PackedInt32Array([6]) and "●" in popup.board.get_child(12).get_child(0).text
  popup.review_slider.value = 16
  check(detour_shown and popup.source.get_executing_lines() == PackedInt32Array([3]) and "●" in popup.board.get_child(1).get_child(0).text, "Review follows the detour on the lower bank and the direct path on the upper bank")
  popup.review_button.pressed.emit()
  popup.source.set_caret_line(3)
  press_key(KEY_F9)
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check("Breakpoint · line 4 · 15 actions" in popup.status.text and popup.garden.cell == Vector2i.ZERO, "A breakpoint in the direct path is skipped at the blocked bank and reached at the open bank")
  press_key(KEY_F10)
  check(popup.garden.turn == 16 and popup.garden.cell == Vector2i(1, 0), "Step executes the marked hop once the path is clear")
  popup.stop_button.pressed.emit()
  await finish_by_steps(popup, banks_solution)
  check(popup.garden.harvested == 2 and popup.progress.garden_best.get(banks.id, 0) == 20, "The reusable route completes Forked banks at its action target")
  popup.chooser.item_selected.emit(8)
  var lantern: Dictionary = Program.PUZZLES[popup.puzzle]
  check(lantern.id == "lantern_rows" and popup.board.get_child_count() == 15 and popup.garden.cell == Vector2i(0, 2) and "while clear east" in popup.source.text, "Lantern rows opens with a sweep routine and beds of different lengths")
  popup.check_button.pressed.emit()
  check("1 of 3 lilies harvested in 7 actions" in popup.status.text, "The starter sweeps the short bed and stops at the stone")
  popup.source.text = "while ripe\nhop north\nend"
  popup.check_button.pressed.emit()
  check("0 of 3 lilies harvested in 0 actions" in popup.status.text and not popup.review_button.visible, "A while loop with a false initial condition skips its body")
  popup.source.text = "while not has_water\nfill\nend"
  popup.check_button.pressed.emit()
  check("0 of 3 lilies harvested in 1 action" in popup.status.text, "A negated while reevaluates its condition after filling")
  popup.source.text = "while spring\nif ripe\nwait\nend\nend"
  popup.check_button.pressed.emit()
  check("Check · Line 1" in popup.status.text and "without doing an action" in popup.status.text and popup.checked_route.actions.is_empty(), "Check catches a while loop with no executable action")
  press_key(KEY_ENTER, true)
  check(not popup.running and popup.garden.turn == 0 and "without doing an action" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([0]), "Run marks the same loop before advancing the board")
  var wait_loop := "while spring\nwait\nend"
  popup.source.text = wait_loop
  popup.check_button.pressed.emit()
  popup.review_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check(popup.review_slider.max_value == Program.MAX_WHILE_ITERATIONS and "Blocked" in popup.review_position.text and popup.source.get_executing_lines() == PackedInt32Array([0]), "Review ends at the iteration limit and marks the while line")
  popup.review_button.pressed.emit()
  await finish_by_steps(popup, wait_loop)
  check(popup.garden.turn == Program.MAX_WHILE_ITERATIONS and "16-iteration limit" in popup.status.text and popup.source.editable, "Stepping a loop halts at the same iteration limit")
  popup.source.text = "while spring\nrepeat 16\nwait\nend\nrepeat 15\nwait\nend\nend"
  popup.check_button.pressed.emit()
  check("256-action limit" in popup.status.text and popup.checked_route.actions.size() == Program.MAX_STEPS, "A while loop with a long body still respects the program action budget")
  popup.source.text = lantern_solution
  popup.check_button.pressed.emit()
  check("22 actions to harvest all 3 lilies · meets target" in popup.status.text and not popup.progress.solved.has(lantern.id), "Check finds the target using the same loop on both beds")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 3
  var short_bed_shown: bool = popup.source.get_executing_lines() == PackedInt32Array([15]) and "●" in popup.board.get_child(12).get_child(0).text
  popup.review_slider.value = 19
  check(short_bed_shown and popup.source.get_executing_lines() == PackedInt32Array([15]) and "●" in popup.board.get_child(4).get_child(0).text, "Review shows the same while command on both bed lengths")
  popup.review_button.pressed.emit()
  popup.source.set_caret_line(15)
  press_key(KEY_F9)
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check("Breakpoint · line 16 · 1 action" in popup.status.text and popup.garden.turn == 1, "A breakpoint pauses on the first while iteration")
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check("Breakpoint · line 16 · 2 actions" in popup.status.text and popup.garden.turn == 2, "Resuming pauses again at the same instruction on the next iteration")
  press_key(KEY_F10)
  check(popup.garden.turn == 3 and popup.garden.cell == Vector2i(2, 2), "Step advances one hop from a while breakpoint")
  popup.stop_button.pressed.emit()
  await finish_by_steps(popup, lantern_solution)
  check(popup.garden.harvested == 3 and popup.progress.garden_best.get(lantern.id, 0) == 22, "Stepping through both while sweeps saves the Lantern rows target")

  popup.chooser.item_selected.emit(9)
  var relay: Dictionary = Program.PUZZLES[popup.puzzle]
  check(relay.id == "spring_relay" and popup.garden.cell == Vector2i(0, 2) and popup.board.get_child_count() == 15 and popup.garden.plants.size() == 5 and "while thirsty and has_water" in popup.source.text, "Spring relay opens with a compound test and five lilies")
  popup.check_button.pressed.emit()
  check("2 of 5 lilies harvested in 11 actions" in popup.status.text, "The starter completes the lower bed with one tank")
  popup.review_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check("Water 0 / 3" in popup.info.text and "●" in popup.board.get_child(13).get_child(0).text and popup.garden.tile(Vector2i(4, 2)) == ".", "A compound while stops on an empty tank even when the next hop is open")
  var precedence := "if not spring and has_water\n  hop west\nend\nif thirsty or not has_water\n  fill\nend\nif spring or ripe and thirsty\n  hop east\nend"
  await finish_by_steps(popup, precedence)
  check(popup.garden.turn == 2 and popup.garden.cell == Vector2i(1, 2) and popup.garden.tank == Program.CAPACITY, "Compound tests evaluate not first, then and, then or")
  popup.source.text = relay_solution
  popup.check_button.pressed.emit()
  check("35 actions to harvest all 5 lilies · meets target" in popup.status.text and not popup.progress.solved.has(relay.id), "Check predicts Spring relay with a return to refill")
  await finish_by_steps(popup, relay_solution)
  check(popup.garden.harvested == 5 and popup.progress.garden_best.get(relay.id, 0) == 35, "Spring relay records a completed compound-condition run")
  popup.best_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check("Best run · 35 / 35 actions" == popup.review_position.text and "Lilies 5 / 5" in popup.info.text, "Best program replays a solution with compound tests")

  popup.chooser.item_selected.emit(10)
  var channels: Dictionary = Program.PUZZLES[popup.puzzle]
  check(channels.id == "side_channels" and popup.garden.cell == Vector2i(0, 1) and popup.garden.plants.size() == 4 and "lily north" in popup.source.text, "Side channels opens at the west spring with four off-path lilies")
  popup.check_button.pressed.emit()
  check("3 of 4 lilies harvested in 19 actions" in popup.status.text, "The Side channels starter checks both sides and tends three lilies on one tank")
  var look_ahead := "fill\nhop east\nif spring west and not spring and thirsty south and not lily north\n  hop south\nend\nwater\nhop north\nif ripe south and lily south and not thirsty south\n  hop south\n  gather\nend\nif lily\n  hop west\nend"
  await finish_by_steps(popup, look_ahead)
  check(popup.garden.turn == 7 and popup.garden.harvested == 1 and popup.garden.cell == Vector2i(1, 2), "Direction checks find the adjacent spring and lily, follow ripeness, and skip gathered plants")
  popup.source.text = channels_solution
  popup.check_button.pressed.emit()
  check("31 actions to harvest all 4 lilies · meets target" in popup.status.text and not popup.progress.solved.has(channels.id), "The second sweep passes the gathered plots and finds the last lily")
  await finish_by_steps(popup, channels_solution)
  check(popup.garden.harvested == 4 and popup.progress.garden_best.get(channels.id, 0) == 31, "Live stepping records the Side channels target")
  popup.best_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check("Best run · 31 / 31 actions" == popup.review_position.text and "Lilies 4 / 4" in popup.info.text, "Best program replays the completed route with neighboring-tile checks")
  popup._close()

 check(await travel(game, "home_woodland_pond"), "Return home from activities")
 print("ACTIVITY_SMOKE " + JSON.stringify({"checks":checks, "failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
