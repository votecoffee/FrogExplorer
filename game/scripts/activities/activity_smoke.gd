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

func check_python_variables(popup) -> void:
 popup._reset()
 popup.source.grab_focus()
 press_key(KEY_F7)
 check(popup.variables_panel.visible and popup.variables_text.text == "No variables assigned" and popup.source.has_focus(), "F7 opens the variable inspector without stealing keyboard focus")
 var draft := """def survey(heading):
    if clear(heading) and visits < 2:
        hop(heading)
    print(column() - start, visits)
start = column()
start_row = row()
visits = 0
while visits < 2 and clear(east):
    survey(east)
    visits += 1
print(start, start_row, visits, column())
"""
 var expected := "Line 4 · 1 0\nLine 4 · 2 1\nLine 11 · 0 1 2 2"
 popup.source.text = draft
 popup.check_button.pressed.emit()
 check(popup.garden.variables.is_empty() and popup.garden.turn == 0 and popup.checked_route.actions.size() == 2 and popup.output_text.text == expected, "Check uses its own Python variables and predicts the whole route")
 var initial_values := "start = 0\nstart_row = 1\nvisits = 0"
 var final_values := "start = 0\nstart_row = 1\nvisits = 2"
 check(popup.variables_title.text == "Check variables" and popup.variables_text.text == final_values, "Check displays the final simulated variables")
 popup.review_button.pressed.emit()
 check(popup.variables_text.text == initial_values, "Review begins with values assigned before the first action")
 popup.review_slider.value = 1
 var middle_values: String = popup.variables_text.text
 popup.review_slider.value = 0
 check("visits = 1" in middle_values and popup.variables_text.text == initial_values and popup.garden.variables.is_empty(), "Scrubbing backward restores earlier variable values without changing the live program")
 press_key(KEY_ENTER, true)
 popup._process(.25)
 press_key(KEY_ENTER, true)
 check(not popup.running and popup.garden.turn == 1 and popup.garden.variables.get("visits") == 1, "Paused code retains its counter after the first action")
 press_key(KEY_F10)
 check(popup.steps.is_empty() and popup.garden.turn == 2 and popup.garden.variables.get("visits") == 2 and popup.output_text.text == expected, "The live counter and saved starting readings match Check")
 check(popup.variables_title.text == "Program variables" and popup.variables_text.text == final_values, "Stepping displays the live values after leaving Review")

 popup.source.text = "at_spring = spring()\nvisits = 0\nwhile visits < 3:\n    visits += 1\nprint(visits, False and missing, 7 or missing, 3 < 2 < missing)\n"
 press_key(KEY_F10)
 check(popup.garden.turn == 2 and not popup.garden.variables.has("start") and popup.output_text.text == "Line 5 · 3 False 7 False" and popup.variables_text.text == "at_spring = False\nvisits = 3", "A fresh program clears earlier variables and shows Boolean readings without board actions")

 popup.source.text = "if False:\n    visits = 5\nwait()\nprint(visits)\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 3 and "Variable 'visits' has no value yet" in popup.status.text and popup.garden.variables.get("visits") == 3 and popup.garden.turn == 2, "Check reports an unset variable on its source line and preserves live values")
 press_key(KEY_F10)
 check(popup.garden.turn == 3 and popup.steps.is_empty() and popup.source.is_line_executing(3) and "Variable 'visits' has no value yet" in popup.status.text, "Step reports an unset variable after the preceding action")

 popup.source.text = "at_edge = not clear(east)\nhop(east)\n"
 popup.check_button.pressed.emit()
 popup.review_button.pressed.emit()
 check("Blocked" in popup.review_position.text and popup.variables_text.text == "at_edge = True" and popup.garden.variables.is_empty(), "Review shows assignments before a failed movement without copying them to the live program")

 popup.source.text = "visits = 2147483647\nvisits += 1\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 1 and "32-bit integer range" in popup.status.text and popup.garden.turn == 3, "Check reports overflow on the assignment line")
 popup.source.text = "visits = 0\nwhile True:\n    visits += 1\n"
 popup.check_button.pressed.emit()
 check("computed too many steps" in popup.status.text and popup.garden.turn == 3, "A changing endless counter stops within the computation budget")
 popup._reset()
 popup.language.item_selected.emit(1)
 check(not popup.variables_button.visible and not popup.variables_panel.visible, "Classic Pondbot keeps the Python variable inspector hidden")
 popup.language.item_selected.emit(0)
 press_key(KEY_F7)

func check_python_ranges(popup) -> void:
 var survey := """def move(heading):
    for _ in range(clear(heading)):
        hop(heading)
for stride in range(1, 4, 2):
    move(east)
    print(stride, column())
for stride in range(3, 2):
    wait()
print(stride)
"""
 var expected := "Line 6 · 1 1\nLine 6 · 3 2\nLine 9 · 3"
 popup.source.text = survey
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == 2 and popup.garden.turn == 0 and popup.output_text.text == expected, "Check previews a stepped range with a direction-bound routine and skips an empty range")
 await finish_by_steps(popup, survey)
 check(popup.garden.cell == Vector2i(2, 1) and popup.garden.turn == 2 and popup.garden.variables.get("stride") == 3 and popup.output_text.text == expected, "A named loop moves Pondbot and retains its final index")

 var nested := """limit = 3
for lap in range(limit):
    limit = 1
    if lap == 1:
        continue
    for offset in range(3, -1, -1):
        if offset < 2:
            break
        print(lap, offset)
        wait()
print(lap, offset, limit)
"""
 var nested_log := "Line 9 · 0 3\nLine 9 · 0 2\nLine 9 · 2 3\nLine 9 · 2 2\nLine 11 · 2 1 1"
 popup.source.text = nested
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == 4 and popup.garden.turn == 2 and popup.output_text.text == nested_log, "A counted loop captures its bound once and nested break and continue advance the right loop")
 await finish_by_steps(popup, nested)
 check(popup.garden.turn == 6 and popup.garden.loop_entries.is_empty() and popup.output_text.text == nested_log, "Live descending ranges restart after a break and release their finished cursors")

 popup.source.text = "print(1)\nfor i in range(0, 4, 0):\n    wait()\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 1 and "nonzero step" in popup.status.text and popup.garden.turn == 6, "Check reports a zero step on the range line before any board action")
 popup.source.text = "for i in range(1, 35, 2):\n    wait()\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 0 and "at most 16 iterations" in popup.status.text and popup.garden.turn == 6, "Counted loops preserve the 16-iteration limit")
 popup._reset()

func check_function_locals(popup) -> void:
 press_key(KEY_F7)
 var route := """def read_counter():
    print("global", counter)
def visit(heading):
    counter = 100
    ready = clear(heading)
    if ready:
        hop(heading)
    counter += 1
    read_counter()
    print("visit", heading, counter)
def sweep(heading):
    for counter in range(2):
        visit(heading)
        print("sweep", counter)
counter = 9
sweep(east)
print("done", counter)
"""
 var expected := "Line 2 · global 9\nLine 10 · visit east 101\nLine 14 · sweep 0\nLine 2 · global 9\nLine 10 · visit east 101\nLine 14 · sweep 1\nLine 17 · done 9"
 popup.source.text = route
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == 2 and popup.output_text.text == expected and popup.variables_text.text == "counter = 9" and popup.garden.variables.is_empty(), "Check isolates nested function counters and reads the module variable from a separate function")
 popup.review_button.pressed.emit()
 check(popup.variables_text.text == "counter = 9\nsweep() · counter = 0\nvisit() · counter = 100\nvisit() · ready = True", "Review lists both active functions' locals before the first hop")
 press_key(KEY_F10)
 check(popup.garden.turn == 1 and popup.variables_text.text == "counter = 9\nsweep() · counter = 1\nvisit() · counter = 100\nvisit() · ready = True", "Step enters the next call with fresh locals and keeps the caller's loop index")
 press_key(KEY_F10)
 check(popup.garden.turn == 2 and popup.garden.cell == Vector2i(2, 1) and popup.garden.local_frames.is_empty() and popup.variables_text.text == "counter = 9" and popup.output_text.text == expected, "Completed calls release their locals and preserve the module counter")

 popup._reset()
 popup.source.text = "counter = 9\ndef sample():\n    print(counter)\n    counter = 3\nsample()\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 2 and "Local variable 'counter' has no value yet" in popup.status.text and popup.garden.turn == 0, "An assignment makes a name local even before that assignment runs")

 popup.source.text = "def sample(heading):\n    if clear(heading):\n        saved = column()\n        hop(heading)\n    print(saved)\nhop(east)\nfor _ in range(2):\n    sample(east)\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == 2 and popup.checked_route.get("line", -1) == 4 and "Local variable 'saved' has no value yet" in popup.status.text and popup.output_text.text == "Line 5 · 1", "Reentering the same call site never reuses values from the previous call")

 popup.source.text = "def count_up():\n    count = 0\n    while count < 3:\n        count += 1\n    print(count)\ncount_up()\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -2) == -1 and popup.output_text.text == "Line 5 · 3" and popup.garden.turn == 0, "A function can advance its own finite while loop without advancing the board")

 popup.source.text = "def scratch():\n    count = 1\nwhile True:\n    scratch()\n"
 popup.check_button.pressed.emit()
 check("without doing an action" in popup.status.text and popup.garden.turn == 0, "A helper that only updates its own locals leaves the caller's stalled-loop guard intact")
 popup._reset()
 press_key(KEY_F7)

func check_python_returns(popup) -> void:
 press_key(KEY_F7)
 var route := """def scan(toward):
    start = column()
    for attempt in range(2):
        while True:
            if not clear(toward):
                print("edge", start, attempt)
                return
            hop(toward)
            print("hop", start, column())
            return
    wait()
def sweep():
    for trip in range(3):
        scan(east)
        print("caller", trip)
    print("sweep done")
sweep()
wait()
"""
 var expected := "Line 9 · hop 0 1\nLine 15 · caller 0\nLine 9 · hop 1 2\nLine 15 · caller 1\nLine 6 · edge 2 0\nLine 15 · caller 2\nLine 16 · sweep done"
 popup.source.text = route
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == 3 and popup.checked_route.get("line", -2) == -1 and popup.output_text.text == expected and popup.garden.turn == 0, "Check predicts nested early returns and keeps the caller's loop running")
 popup.review_button.pressed.emit()
 check(popup.variables_text.text == "scan() · attempt = 0\nscan() · start = 0\nsweep() · trip = 0", "Review shows both active functions before the first return")
 press_key(KEY_F10)
 check(popup.garden.turn == 1 and popup.variables_text.text == "scan() · attempt = 0\nscan() · start = 1\nsweep() · trip = 1", "Returning clears the inner loop state so the next call starts fresh")
 press_key(KEY_F10)
 check(popup.garden.turn == 2 and popup.garden.loop_entries.is_empty() and popup.garden.local_frames.is_empty() and popup.variables_text.text == "No variables assigned" and popup.output_text.text == expected, "Returning at a blocked path releases the callee's locals and reaches the next top-level action")
 press_key(KEY_F10)
 check(popup.garden.turn == 3 and popup.garden.cell == Vector2i(2, 1) and popup.steps.is_empty(), "Early returns spend no board actions")

 popup.source.text = "def skip():\n    return None\n    wait()\ndef caller():\n    count = 7\n    skip()\n    print(count)\ncaller()\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.is_empty() and popup.output_text.text == "Line 7 · 7", "Returning from a function with no locals preserves the caller's values")
 popup.source.text = "wait()\nreturn\n"
 popup.check_button.pressed.emit()
 check("Line 2 · Use return inside a function." in popup.status.text and popup.garden.turn == 3, "A top-level return reports its source line before running")
 popup._reset()
 press_key(KEY_F7)

func check_function_results(popup) -> void:
 press_key(KEY_F7)
 var route := """def can_hop(heading):
    return clear(heading)
def walk(heading):
    moved = 0
    for _ in range(3):
        ready = can_hop(heading)
        if not ready:
            return moved
        hop(heading)
        moved += 1
    return moved
def probe(heading):
    reads = walk(heading)
    available = can_hop(heading)
    return available or reads
first = probe(east)
edge = can_hop(east)
print(first, edge)
second = walk(west)
third = walk(west)
print(second, third, column())
"""
 var expected := "Line 18 · 2 False\nLine 21 · 2 0 0"
 popup.source.text = route
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == 4 and popup.output_text.text == expected and popup.variables_text.text == "edge = False\nfirst = 2\nsecond = 2\nthird = 0" and popup.garden.variables.is_empty(), "Check captures nested function results, including zero and False, without changing the live board")
 popup.review_button.pressed.emit()
 check(popup.variables_text.text == "walk() · moved = 0\nwalk() · ready = True", "Review shows the local reading returned before the first hop")
 popup.review_slider.value = 2
 check(popup.variables_text.text == "edge = False\nfirst = 2\nwalk() · moved = 0\nwalk() · ready = True" and popup.garden.turn == 0, "Review shows the two results assigned when Pondbot reaches the east bank")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 4 and popup.garden.cell == Vector2i(0, 1) and popup.garden.local_frames.is_empty() and popup.garden.loop_entries.is_empty() and popup.output_text.text == expected, "Returning values preserves the live route and releases the completed calls")

 popup.source.text = "def sensor():\n    return 99\ndef maybe():\n    sensor()\n    if False:\n        return 8\nreading = 5\nreading = maybe()\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 7 and "Function 'maybe' returned without a number or Boolean" in popup.status.text and popup.variables_text.text == "reading = 5", "A discarded inner result cannot fill a missing outer result or overwrite its destination")
 popup.source.text = "def broken():\n    return missing\nbroken()\nwait()\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 1 and popup.checked_route.actions.is_empty() and "Variable 'missing' has no value yet" in popup.status.text, "Returning an expression evaluates it even when the caller discards the result")
 popup._reset()
 press_key(KEY_F7)

func check_value_parameters(popup) -> void:
 press_key(KEY_F7)
 var route := """def walk(heading, count: int, allowed: bool):
    moved = 0
    if not allowed:
        return moved
    for _ in range(count):
        if not clear(heading):
            return moved
        hop(heading)
        moved += 1
    return moved
def plan(heading, count: int):
    got = walk(heading, count + 1, clear(heading))
    return got
seed = column() + 1
eastbound = plan(east, seed)
westbound = walk(west, eastbound - 1, clear(west))
skipped = walk(north, 1, False)
print(eastbound, westbound, skipped, column())
"""
 var expected := "Line 18 · 2 1 0 1"
 popup.source.text = route
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == 3 and popup.output_text.text == expected and popup.garden.turn == 0, "Check predicts a route that passes readings, counts, and directions through nested calls")
 popup.review_button.pressed.emit()
 check(popup.variables_text.text == "plan() · count = 1\nseed = 1\nwalk() · allowed = True\nwalk() · count = 2\nwalk() · moved = 0", "Review shows the caller and callee's independent parameter values")
 popup.review_slider.value = 2
 check(popup.variables_text.text == "eastbound = 2\nseed = 1\nwalk() · allowed = True\nwalk() · count = 1\nwalk() · moved = 0" and popup.garden.turn == 0, "The next call receives the previous call's result and its own direction reading")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 3 and popup.garden.cell == Vector2i(1, 1) and popup.garden.local_frames.is_empty() and popup.output_text.text == expected, "Live input parameters produce the same route and result as Check")

 await finish_by_steps(popup, "def probe(heading, start: int):\n    hop(heading)\n    return start\nwas = probe(west, column())\nprint(was, column())\n")
 check(popup.garden.turn == 4 and popup.output_text.text == "Line 5 · 1 0", "A numeric argument captures the reading before the function moves Pondbot")
 popup.source.text = "def scout(heading, count: int):\n    hop(heading)\nscout(east, True)\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 2 and "Argument 'count' needs a whole number" in popup.status.text and popup.checked_route.actions.is_empty(), "An integer parameter reports a Boolean argument at the call before it moves")
 popup.source.text = "def scout(allowed: bool, heading):\n    hop(heading)\nscout(1, east)\n"
 popup.check_button.pressed.emit()
 check(popup.checked_route.get("line", -1) == 2 and "Argument 'allowed' needs True or False" in popup.status.text and popup.checked_route.actions.is_empty(), "A Boolean parameter reports a numeric argument at the call")
 popup._reset()
 press_key(KEY_F7)

func check_switchback_beds(popup, index: int) -> void:
 var earned: int = popup.progress.earned_lilies()
 popup.chooser.item_selected.emit(index)
 check(popup.puzzle == index and not popup.chooser.is_item_disabled(index) and popup.board.columns == 5 and popup.board.get_child_count() == 25 and popup.garden.cell == Vector2i(2, 2), "Switchback beds opens with a five-by-five board and a central spring")
 var starter: String = popup.source.text
 popup.check_button.pressed.emit()
 check("2 of 4 lilies harvested in 18 actions" in popup.status.text and popup.garden.turn == 0 and popup.progress.earned_lilies() == earned, "The starter uses the stop number to reach the two west beds")

 var full_route := starter + """while column() < spring_column:
    hop(east)
fill()
for stop in range(1, 3):
    hop(east)
    if stop == 1:
        tend_spur(south, north)
    else:
        tend_spur(north, south)
"""
 popup.source.text = full_route
 popup.check_button.pressed.emit()
 check("36 actions to harvest all 4 lilies" in popup.status.text and "meets target" in popup.status.text and popup.garden.turn == 0, "Check predicts the full mirrored route at its target")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 21
 check("Preview · 21 / 36 actions" == popup.review_position.text and "Water 3 / 3" in popup.info.text and "Lilies 2 / 4" in popup.info.text and popup.garden.harvested == 0, "Review shows the refill between sweeps without changing the live board")

 await finish_by_steps(popup, full_route)
 check(popup.garden.turn == 36 and popup.garden.harvested == 4 and popup.progress.earned_lilies() == earned + 4 and popup.progress.garden_best_python.get("switchback_beds", false), "Completing Switchback beds earns four lilies and saves the Python best")
 popup.best_button.pressed.emit()
 popup.review_slider.value = popup.review_slider.max_value
 check(popup.best_source.text == full_route and "Best run · 36 / 36 actions" == popup.review_position.text and "Lilies 4 / 4" in popup.info.text, "Best program replays the saved switchback route")
 press_key(KEY_F7)
 check(popup.variables_panel.visible and popup.variables_title.text == "Best run variables" and popup.variables_text.text == "spring_column = 2\nstop = 2", "F7 shows the loop counter and starting position from the recorded best")
 popup.review_slider.value = 0
 check(popup.variables_text.text == "spring_column = 2", "Best program shows the variables at the beginning of the recorded run")
 press_key(KEY_F7)

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
 var direction_routine := "routine stride heading\nhop heading\nend\n"
 check(Program.compile(direction_routine + "call stride").get("line", -1) == 3 and Program.compile(direction_routine + "call stride north east").get("line", -1) == 3, "A call requires one direction for each declared parameter")
 check(Program.compile(direction_routine + "call stride upward").get("line", -1) == 3 and Program.compile(direction_routine + "hop heading").get("line", -1) == 3, "A direction must be a compass point or a parameter in scope")
 check(Program.compile("routine stride heading heading\nhop heading\nend").get("line", -1) == 0, "A routine rejects duplicate parameter names")
 var reversals := Program.compile("routine pair first second\nrepeat 2\nhop first\nhop second\nend\nend\nroutine reversed first second\ncall pair second first\nend\ncall reversed east north\ncall reversed west south")
 var reversed_steps: Array = reversals.get("steps", [])
 check(reversed_steps.map(func(action): return action.direction) == ["north", "east", "north", "east", "south", "west", "south", "west"], "Forwarded arguments can swap positions across repeated instructions and independent calls")
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
 check(Program.compile("if spring\nbreak\nend").get("line", -1) == 1 and Program.compile("routine skip\ncontinue\nend\nrepeat 2\ncall skip\nend").get("line", -1) == 1, "Loop control requires a loop in the same routine or top-level program")
 check(Program.compile("repeat 2\ncontinue east\nend").get("line", -1) == 1, "Continue takes no arguments")

 # Each garden has a complete solution using the normal commands.
 var terrace_patrol := "repeat 2\nfill\nrepeat 2\nhop east\nwater\nwait\ngather\nend\nrepeat 2\nhop west\nend\nhop north\nend"
 var spillway_solution := "routine finish_lily\n  wait\n  gather\nend\nfill\nhop east\nhop east\nwater\nwater\nhop east\nwater\ncall finish_lily\nhop west\ngather\nhop west\nhop west\nfill\nhop east\nwater\ncall finish_lily\nhop west\nhop north\nhop north\nhop east\nwater\nhop west\nfill\nhop east\ngather\nhop east\nwater\nwater\ncall finish_lily\nhop east\nwater\ncall finish_lily"
 var patchwork_solution := "routine water_plot\n  repeat 2\n    if thirsty\n      if has_water\n        water\n      end\n    end\n  end\nend\nroutine finish_plot\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\nfill\nhop east\nhop east\ncall water_plot\nhop east\ncall water_plot\ncall finish_plot\nhop west\ncall finish_plot\nhop west\nhop west\nhop north\nhop north\nfill\nhop east\ncall water_plot\ncall finish_plot\nhop east\nhop east\ncall water_plot\ncall finish_plot"
 var banks_solution := "routine to_lily\n  if clear east\n    repeat 2\n      hop east\n    end\n  else\n    hop south\n    repeat 2\n      hop east\n    end\n    hop north\n  end\nend\nroutine to_spring\n  if clear west\n    repeat 2\n      hop west\n    end\n  else\n    hop south\n    repeat 2\n      hop west\n    end\n    hop north\n  end\nend\nroutine tend\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  wait\n  gather\nend\nfill\ncall to_lily\ncall tend\ncall to_spring\nrepeat 2\n  hop north\nend\ncall to_lily\ncall tend\n"
 var lantern_solution := "routine tend_plot\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\nroutine sweep_east\n  while clear east\n    hop east\n    call tend_plot\n  end\nend\nfill\ncall sweep_east\nwhile clear west\n  hop west\nend\nrepeat 2\n  hop north\nend\nfill\ncall sweep_east\n"
 var relay_solution: String = Program.PUZZLES[9].draft + "while not spring and clear west\n  hop west\nend\nrepeat 2\n  hop north\nend\nfill\ncall sweep_east\nwhile not spring and clear west\n  hop west\nend\nfill\ncall sweep_east\n"
 var channels_solution: String = Program.PUZZLES[10].draft + "while not spring\n  hop west\nend\nfill\ncall sweep_east\n"
 var compass_solution: String = Program.PUZZLES[11].draft + "while not spring\n  hop east\nend\ncall sweep east south north\n"
 var low_water_solution: String = Program.PUZZLES[12].draft + "while not spring\n  hop west\nend\nfill\ncall sweep\n"
 var nursery_sweep: String = Program.PUZZLES[13].draft + "while clear east\n  hop east\n  call tend\nend\n"
 var switchback := Program.PUZZLES.size() - 1
 var switchback_solution: String = Program.PUZZLES[switchback].draft + "while not spring\n  hop east\nend\nfill\nhop east\ncall tend_spur south north\nhop east\ncall tend_spur north south\n"
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
  compass_solution,
  low_water_solution,
  nursery_sweep,
  switchback_solution,
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

 var open_nursery := Program.PUZZLES.size()
 var nursery_loop := Program.new()
 nursery_loop.load_puzzle(open_nursery)
 var ongoing: Array = Program.compile("while always\n  wait\nend").steps
 var next := nursery_loop.next_action_index(ongoing, 0)
 for action in Program.MAX_STEPS + 17:
  if next >= ongoing.size():
   break
  nursery_loop.step(ongoing[next])
  next = nursery_loop.next_action_index(ongoing, next + 1)
 check(nursery_loop.turn == Program.MAX_STEPS + 17 and next < ongoing.size() and nursery_loop.runtime_error.is_empty(), "Nursery practice loops keep running past the scored action and iteration limits")

 if has_garden:
  press_key(KEY_F5)
  await frames(4)
  var popup = game.activities.garden
  check(popup.visible and game.pilot.paused and popup.source.has_focus(), "The garden popup owns keyboard focus and pauses movement")
  check("Target · 9 actions" in popup.score.text and "Personal best · —" in popup.score.text and not popup.best_button.visible, "A fresh board displays its target and an empty personal best")
  check(popup.puzzle == 0 and popup.lesson_status.text == "Lilies earned · 0   Next unlock · 2" and not popup.chooser.is_item_disabled(2) and popup.chooser.is_item_disabled(3) and popup.chooser.is_item_disabled(10) and popup.chooser.is_item_disabled(switchback) and popup.chooser.is_item_disabled(open_nursery), "A new garden opens the first lesson and shows the next lily milestone")
  popup.chooser.item_selected.emit(3)
  check(popup.puzzle == 0 and popup.chooser.selected == 0, "A locked lesson cannot replace the current draft")
  popup.progress.drafts["compass_banks"] = "fill\n"
  popup.progress.python_drafts["low_water_row"] = "fill()\n"
  popup._draw()
  check(not popup.chooser.is_item_disabled(11) and not popup.chooser.is_item_disabled(12) and popup.progress.earned_lilies() == 0, "Existing classic and Python drafts retain access without adding lilies")
  popup.progress.drafts.erase("compass_banks")
  popup.progress.python_drafts.erase("low_water_row")
  popup._draw()
  check(popup.python_mode and popup.language.selected == 0 and popup.source.indent_use_spaces and "fill()" in popup.source.text, "The keyboard editor opens in Python")
  popup.check_button.pressed.emit()
  check("9 actions to harvest all 2 lilies" in popup.status.text and popup.garden.turn == 0 and popup.progress.earned_lilies() == 0, "Check previews a Python starter without moving Pondbot or earning lilies")
  press_key(KEY_F10)
  check(popup.garden.turn == 1 and popup.source.get_executing_lines() == PackedInt32Array([1]) and popup.language.disabled, "F10 executes the Python fill call and marks its source line")
  popup.stop_button.pressed.emit()
  popup.source.text = "if spring():"
  popup.source.set_caret_column(popup.source.text.length())
  popup.source.grab_focus()
  press_key(KEY_ENTER)
  check(popup.source.text == "if spring():\n    ", "Enter indents a Python block for keyboard editing")
  popup.source.text = "fill()\nif spring()\n    wait()"
  popup.check_button.pressed.emit()
  check("Line 2" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([1]), "Python syntax errors mark the original editor line")
  popup.language.item_selected.emit(1)
  check(not popup.python_mode and popup.source.text == Program.PUZZLES[0].draft and popup.progress.python_drafts.get("first_bloom") == "fill()\nif spring()\n    wait()", "Switching language saves the Python draft and opens the classic starter")
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
  check(popup.progress.earned_lilies() == 2 and "Next unlock · 8" in popup.lesson_status.text and not popup.chooser.is_item_disabled(5) and popup.chooser.is_item_disabled(6), "Completing First bloom earns two lilies and opens the next set of boards")
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
  check(popup.progress.earned_lilies() == 2 and popup.next_lesson_button.visible, "Another clear leaves the lily total at two and keeps the next lesson available")
  press_key(KEY_PAGEDOWN, true)
  check(popup.puzzle == 1 and popup.source.has_focus() and popup.progress.drafts.get(puzzle_id) == "# Same route, different comment\n" + starter, "Ctrl+Page Down saves the draft and focuses the first unfinished lesson")
  popup.chooser.item_selected.emit(0)
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
  check(popup.progress.earned_lilies() == 10 and not popup.chooser.is_item_disabled(6) and popup.chooser.is_item_disabled(10), "Eight lilies open the middle lessons even after an above-target clear")
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
  check(popup.progress.earned_lilies() == 20 and not popup.chooser.is_item_disabled(12) and popup.chooser.is_item_disabled(13) and "Next unlock · 26" in popup.lesson_status.text, "Eighteen earned lilies open the advanced sweeps and show the nursery milestone")
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

  popup.chooser.item_selected.emit(11)
  var compass: Dictionary = Program.PUZZLES[popup.puzzle]
  check(compass.id == "compass_banks" and popup.garden.cell == Vector2i(2, 1) and "routine sweep along branch return_path" in popup.source.text, "Compass banks opens with a mirrored route and direction parameters")
  popup.check_button.pressed.emit()
  check("1 of 2 lilies harvested in 8 actions" in popup.status.text, "The starter forwards directions to reach the west lily and return to the bank")
  popup.source.text = compass_solution
  popup.check_button.pressed.emit()
  check("17 actions to harvest all 2 lilies · meets target" in popup.status.text and not popup.progress.solved.has(compass.id), "Different arguments reuse the same sweep on both banks")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 2
  var west_shown: bool = popup.source.get_executing_lines() == PackedInt32Array([12]) and "●" in popup.board.get_child(6).get_child(0).text
  popup.review_slider.value = 11
  check(west_shown and popup.source.get_executing_lines() == PackedInt32Array([12]) and "●" in popup.board.get_child(8).get_child(0).text, "Review marks the same source line for a west hop and an east hop")
  popup.review_button.pressed.emit()
  popup.source.set_caret_line(2)
  press_key(KEY_F9)
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  var paused_west: bool = popup.garden.turn == 3 and popup.garden.cell == Vector2i(0, 1) and "Breakpoint · line 3" in popup.status.text
  press_key(KEY_ENTER, true)
  await wait_for_garden_pause(popup)
  check(paused_west and popup.garden.turn == 12 and popup.garden.cell == Vector2i(4, 1) and "Breakpoint · line 3" in popup.status.text, "A breakpoint stops in the called routine with either direction")
  press_key(KEY_F9)
  await finish_by_steps(popup, compass_solution)
  check(popup.garden.harvested == 2 and popup.progress.garden_best.get(compass.id, 0) == 17, "Live execution records the Compass banks target")
  popup.best_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check("Best run · 17 / 17 actions" == popup.review_position.text and "Lilies 2 / 2" in popup.info.text, "Best program replays the saved calls with both sets of directions")

  popup.chooser.item_selected.emit(12)
  var low_water: Dictionary = Program.PUZZLES[popup.puzzle]
  check(low_water.id == "low_water_row" and popup.garden.plants.size() == 4 and "continue" in popup.source.text and "break" in popup.source.text, "Low water row opens with a sweep that can skip and exit")
  popup.check_button.pressed.emit()
  check("2 of 4 lilies harvested in 11 actions" in popup.status.text, "The starter leaves the double lily half watered when the tank runs dry")
  var nested_control := "repeat 3\n  while spring\n    wait\n    break\n    hop west\n  end\n  continue\n  hop east\nend\nfill"
  await finish_by_steps(popup, nested_control)
  check(popup.garden.turn == 4 and popup.garden.cell == Vector2i.ZERO and popup.garden.tank == Program.CAPACITY, "Inner break leaves the enclosing repeat open and continue advances it")
  await finish_by_steps(popup, "fill\nrepeat 4\n  hop east\n  if lily\n    break\n  end\n  hop west\nend\nwater")
  check(popup.garden.turn == 3 and popup.garden.cell == Vector2i(1, 0) and popup.garden.plant_status(Vector2i(1, 0)) == "Growing", "Break skips all remaining repeat iterations and reaches the following action")
  popup.source.text = "while spring\n  continue\nend"
  popup.check_button.pressed.emit()
  check("Check · Line 1" in popup.status.text and "without doing an action" in popup.status.text, "Continuing without an action still trips the while guard")
  popup.source.text = "while spring\n  while spring\n    if has_water\n      break\n    end\n    fill\n  end\n  wait\nend"
  popup.check_button.pressed.emit()
  check("Check · Line 1" in popup.status.text and "16-iteration limit" in popup.status.text and popup.checked_route.actions.size() == 17, "Breaking and reentering a nested while starts a fresh iteration budget")
  popup.source.text = low_water_solution
  popup.check_button.pressed.emit()
  check("25 actions to harvest all 4 lilies · meets target" in popup.status.text and not popup.progress.solved.has(low_water.id), "Check counts the partial watering, refill, and second sweep")
  await finish_by_steps(popup, low_water_solution)
  check(popup.garden.harvested == 4 and popup.progress.garden_best.get(low_water.id, 0) == 25, "The Low water row solution saves a score with loop control")
  popup.best_button.pressed.emit()
  popup.review_slider.value = 17
  var skipped_again: bool = popup.best_source.get_executing_lines() == PackedInt32Array([3]) and "●" in popup.board.get_child(2).get_child(0).text
  popup.review_slider.value = popup.review_slider.max_value
  check(skipped_again and "Best run · 25 / 25 actions" == popup.review_position.text and "Lilies 4 / 4" in popup.info.text, "Replay skips gathered lilies on the second sweep and shows the final harvest")

  popup.language.item_selected.emit(0)
  var low_water_python: String = popup.source.text
  popup.check_button.pressed.emit()
  check("            return" in low_water_python and "2 of 4 lilies harvested in 11 actions" in popup.status.text, "The Python Low water row starter ends its sweep with return")
  low_water_python += "while not spring():\n    hop(west)\nfill()\nsweep()\n"
  popup.source.text = low_water_python
  popup.check_button.pressed.emit()
  check("25 actions to harvest all 4 lilies · meets target" in popup.status.text, "Python Check reaches the refill after the sweep returns early")
  await finish_by_steps(popup, low_water_python)
  check(popup.garden.harvested == 4 and popup.garden.turn == 25, "The Python return route completes Low water row at its target")
  popup.chooser.item_selected.emit(1)
  var around_python := "# Route around the stones\nfill()\nfor _ in range(2):\n    hop(east)\nwater()\nwait()\ngather()\nhop(south)\nhop(east)\nwater()\nwait()\ngather()\nhop(west)\nhop(south)\nwater()\nwait()\ngather()\n"
  await finish_by_steps(popup, around_python)
  check(popup.garden.turn == 16 and popup.garden.harvested == 3 and popup.progress.garden_best_python.get("around_the_stones", false), "A completed Python run records its source language and score")
  popup.language.item_selected.emit(1)
  popup.best_button.pressed.emit()
  popup.review_slider.value = 3
  check(popup.best_source.text == around_python and popup.best_source.get_executing_lines() == PackedInt32Array([3]) and "Best run · 3 / 16 actions" == popup.review_position.text, "Best program replays Python with correct lines from the classic editor")
  press_key(KEY_ESCAPE)
  popup.language.item_selected.emit(0)
  check(popup.source.text == around_python, "Switching back to Python restores its separate draft")
  popup.source.text = "if not (lily() or thirsty()) and (spring() or ripe()):\n    fill()\nelse:\n    hop(west)"
  popup.check_button.pressed.emit()
  check("0 of 3 lilies harvested in 1 action" in popup.status.text, "Python grouping and negation determine the same action during Check")
  var earned_before: int = popup.progress.earned_lilies()
  popup.chooser.item_selected.emit(13)
  var nursery: Dictionary = Program.PUZZLES[popup.puzzle]
  check(nursery.id == "nursery_beds" and "Lilies 0 / 3" in popup.info.text and "Empty bed" in popup.board.get_child(1).get_child(0).text, "Nursery beds opens with its two seedbeds counted in the harvest goal")
  var bare_scene_size: int = popup.world.garden_root.get_child_count()
  var nursery_starter: String = popup.source.text
  popup.check_button.pressed.emit()
  check("1 of 3 lilies harvested in 6 actions" in popup.status.text and popup.garden.turn == 0, "Check predicts planting and tending the first bed")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 3
  check("Thirsty" in popup.board.get_child(1).get_child(0).text and popup.garden.plant_status(Vector2i(1, 0)) == Program.EMPTY_BED and popup.world.garden_root.get_child_count() == bare_scene_size, "Review shows the new plant while the live bed stays empty")
  popup.review_button.pressed.emit()
  popup.source.text = "plant()"
  popup.check_button.pressed.emit()
  check("Plant on a prepared empty bed" in popup.status.text, "Planting at the spring reports a blocked command")
  popup.source.text = "fill()\nhop(east)\nwater()"
  popup.check_button.pressed.emit()
  check("Line 3" in popup.status.text and "Plant this bed before watering it" in popup.status.text, "Watering an unplanted bed points to the original Python line")
  await finish_by_steps(popup, "if empty_bed(east) and not lily(east):\n    hop(east)\n    plant()\n    plant()\n")
  check(popup.garden.turn == 2 and popup.garden.plant_status(Vector2i(1, 0)) == "Thirsty ×1" and popup.world.garden_root.get_child_count() == bare_scene_size + 1 and "Line 4" in popup.status.text, "The adjacent bed sensor leads to a visible seedling and a second planting is blocked")
  var nursery_python := "print('Ready', spring())\n" + nursery_starter + "while clear(east):\n    hop(east)\n    tend()\n"
  await finish_by_steps(popup, nursery_python)
  check(popup.garden.turn == 16 and popup.garden.harvested == 3 and popup.progress.earned_lilies() == earned_before + 3 and popup.progress.garden_best_python.get(nursery.id, false), "The Python sweep harvests all three lilies and earns credit for the planted beds")
  popup.best_button.pressed.emit()
  popup.review_slider.value = popup.review_slider.max_value
  check("Best run · 16 / 16 actions" == popup.review_position.text and "Lilies 3 / 3" in popup.info.text, "Best program replays planting and harvesting")
  check(popup.output_panel.visible and popup.output_title.text == "Best run output" and "Line 1 · Ready True" in popup.output_text.text, "Best program replays Python output from the recorded draft")

  await check_switchback_beds(popup, switchback)
  var earned_for_practice: int = popup.progress.earned_lilies()
  popup.chooser.item_selected.emit(open_nursery)
  var practice_start: String = popup.source.text
  check(popup.puzzle == open_nursery and popup.garden.practice and not popup.score.visible and "while True:" in practice_start, "Open nursery offers continuous Python practice without an action target")
  popup.source.text = "while True:\n    continue\n"
  popup.check_button.pressed.emit()
  check("Line 1" in popup.status.text and "without doing an action" in popup.status.text, "The nursery stops a loop that cannot advance")
  popup.source.text = practice_start
  popup.check_button.pressed.emit()
  check(popup.checked_route.actions.size() == Program.MAX_STEPS and "Preview limit" in popup.status.text and popup.garden.turn == 0, "Check previews the first 256 nursery actions on a copy")
  press_key(KEY_ENTER, true)
  for action in 30:
   popup._process(.25)
  check(popup.running and popup.garden.harvested == 4 and popup.garden.cell == Vector2i(0, 1) and popup.garden.plant_status(Vector2i(1, 0)) == Program.EMPTY_BED, "The nursery replants after harvest and keeps running after the first circuit")
  press_key(KEY_ENTER, true)
  await frames(4)
  check(not popup.running and popup.garden.turn == 30 and "Harvested 4" in popup.info.text, "Ctrl+Enter pauses the nursery without advancing the board")
  press_key(KEY_F10)
  popup.stop_button.pressed.emit()
  check(popup.garden.turn == 31 and popup.garden.harvested == 4 and popup.source.editable, "Step and Stop work on the paused nursery")
  await finish_by_steps(popup, "hop(north)\nhop(east)\nplant()\n")
  check(popup.garden.turn == 34 and popup.garden.harvested == 4 and popup.garden.plant_status(Vector2i(1, 0)) == "Thirsty ×1", "A new program starts at the current nursery position")
  popup.language.item_selected.emit(1)
  check(popup.garden.turn == 34 and "while always" in popup.source.text, "Changing source format keeps the nursery state")
  popup.language.item_selected.emit(0)
  popup.source.text = "water()\nwait()\ngather()\n"
  popup.check_button.pressed.emit()
  check("Harvested 1 in 3 actions" in popup.status.text and popup.garden.turn == 34, "Check projects harvest from the current nursery state")
  popup.review_button.pressed.emit()
  var captured_nursery: bool = "Thirsty" in popup.board.get_child(1).get_child(0).text and "Harvested 4" in popup.info.text
  popup.review_slider.value = 3
  check(captured_nursery and "Empty bed" in popup.board.get_child(1).get_child(0).text and "Harvested 5" in popup.info.text and popup.garden.harvested == 4, "Review replays the captured nursery without changing the live bed")
  await finish_by_steps(popup, "water()\nwait()\ngather()\n")
  check(popup.garden.harvested == 5 and popup.progress.earned_lilies() == earned_for_practice and not popup.best_button.visible, "Nursery harvest counts stay separate from lesson records")
  await finish_by_steps(popup, "plant()\n")
  popup.source.text = practice_start
  press_key(KEY_ENTER, true)
  for action in 8:
   popup._process(.25)
  press_key(KEY_ENTER, true)
  check(popup.garden.turn == 46 and popup.garden.harvested == 6, "The starter returns to the spring and tends a partially planted row on restart")
  popup._reset()
  check(popup.garden.turn == 0 and popup.garden.harvested == 0 and popup.garden.cell == Vector2i(0, 1), "Reset restores the starting nursery")
  var logging_draft := "def report(heading):\n    print('Bed', heading, empty_bed(heading))\nprint('Spring', spring())\nfill()\nhop(north)\nreport(east)\nreport(west)\nhop(east)\nplant()\nprint('Thirsty', thirsty(), has_water())\n"
  popup.source.text = logging_draft
  popup.check_button.pressed.emit()
  var expected_log := "Line 3 · Spring True\nLine 2 · Bed east True\nLine 2 · Bed west False\nLine 10 · Thirsty True True"
  check(popup.garden.turn == 0 and popup.garden.output.is_empty() and popup.checked_route.actions.size() == 4 and popup.output_title.text == "Check output" and popup.output_text.text == expected_log, "Check prints sensor readings from the simulated board with original Python line numbers")
  popup.review_button.pressed.emit()
  check(popup.output_text.text == "Line 3 · Spring True", "Review starts with output written before the first action")
  popup.review_slider.value = 2
  check(popup.output_text.text == "Line 3 · Spring True\nLine 2 · Bed east True\nLine 2 · Bed west False" and popup.garden.turn == 0, "Review reveals output as actions advance")
  await finish_by_steps(popup, logging_draft)
  check(popup.garden.turn == 4 and popup.output_title.text == "Program output" and popup.output_text.text == expected_log, "Live output matches Check without spending extra actions")
  popup.source.text = "while True:\n    print('still here')\n"
  press_key(KEY_F10)
  check(popup.garden.turn == 4 and "without doing an action" in popup.status.text and popup.output_text.text == "Line 2 · still here", "A print-only loop reports an error without advancing the board")
  popup.source.text = "while True:\n    print(has_water())\n    wait()\n"
  popup.check_button.pressed.emit()
  var preview_output: Array = popup.checked_route.preview.output
  check(preview_output.size() == Program.MAX_OUTPUT_MESSAGES and preview_output.back().turn == 4 + Program.MAX_STEPS and popup.garden.output.size() == 1, "Check keeps recent messages without replacing the live output buffer")
  popup._reset()
  check(not popup.output_panel.visible and popup.garden.output.is_empty(), "Reset clears program output")
  var measurement_draft := """def tend(heading):
    hop(heading)
    plant()
    if water_level() >= 2:
        water()
    print("Bed", column(), row(), water_level())
print("Spring", column(), row(), water_level())
if column() == 0 and row() == 1 and water_level() != 3:
    fill()
hop(north)
while column() < 2 and 0 < water_level() <= 3:
    tend(east)
wait()
gather()
if not (3 <= water_level() <= 7) and column() > row():
    print("End", column(), row(), water_level())
"""
  var measurement_log := "Line 7 · Spring 0 1 0\nLine 6 · Bed 1 0 2\nLine 6 · Bed 2 0 1\nLine 16 · End 2 0 1"
  popup.source.text = measurement_draft
  popup.check_button.pressed.emit()
  check(popup.garden.turn == 0 and popup.garden.tank == 0 and popup.garden.cell == Vector2i(0, 1) and popup.checked_route.actions.size() == 10 and popup.output_text.text == measurement_log, "Check predicts numeric sensor readings and branches without changing the nursery")
  popup.review_button.pressed.emit()
  popup.review_slider.value = 5
  check(popup.output_text.text == "Line 7 · Spring 0 1 0\nLine 6 · Bed 1 0 2" and "Water 2 / 3" in popup.info.text, "Review aligns numeric readings with water and movement on the board")
  await finish_by_steps(popup, measurement_draft)
  check(popup.garden.turn == 10 and popup.garden.cell == Vector2i(2, 0) and popup.garden.tank == 1 and popup.garden.harvested == 1 and popup.output_text.text == measurement_log, "Numeric guards steer and water both beds in the live nursery")
  var classic_measurement := Program.compile("if column == 2 and water_level >= 1\n wait\nend")
  var bad_measurement := Program.compile_python("if row(north) == 1:\n    wait()")
  check(classic_measurement.has("steps") and popup.garden.next_action_index(classic_measurement.get("steps", []), 0) == 1 and bad_measurement.get("line", -1) == 0, "Classic comparisons share the simulator and invalid Python sensor calls report their line")
  check_python_variables(popup)
  await check_python_ranges(popup)
  check_function_locals(popup)
  check_python_returns(popup)
  await check_function_results(popup)
  await check_value_parameters(popup)
  popup._close()

 check(await travel(game, "home_woodland_pond"), "Return home from activities")
 print("ACTIVITY_SMOKE " + JSON.stringify({"checks":checks, "failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
