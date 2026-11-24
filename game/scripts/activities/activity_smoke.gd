extends Node

const Run = preload("res://scripts/activities/course_run.gd")
const Program = preload("res://scripts/activities/garden_program.gd")
const Progress = preload("res://scripts/activities/activity_progress.gd")
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

func press_key(key: Key, ctrl := false, shift := false) -> void:
 var event := InputEventKey.new()
 event.keycode = key
 event.physical_keycode = key
 event.ctrl_pressed = ctrl
 event.shift_pressed = shift
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
 var history: Array = popup.best_route.variable_history
 var second_stop := 0
 for action in range(1, history.size()):
  if history[action - 1].get("stop") == 1 and history[action].get("stop") == 2:
   second_stop = action
   break
 popup.review_slider.value = maxi(0, second_stop - 1)
 press_key(KEY_F7, true)
 press_key(KEY_PAGEDOWN)
 check(second_stop > 0 and popup.review_slider.value == second_stop and popup.review_slider.has_focus() and popup.variables_title.text == "Best run changes" and popup.variables_text.text == "stop = 1 → 2" and popup.garden.turn == 36, "Best program can jump to the counter change at its recorded action without moving the live board")
 press_key(KEY_F7, true)

func check_nursery_storage() -> void:
 var temporary := DirAccess.create_temp("frog-nursery-progress")
 check(temporary != null, "Nursery save checks have an isolated directory")
 if temporary == null:
  return
 var path := temporary.get_current_dir()
 var first := Progress.new()
 var second := Progress.new()
 first.load_from(path)
 second.load_from(path)
 var recorded := first.edit_draft("first_bloom", "fill()\n", true) == OK
 recorded = first.complete_puzzle("first_bloom", 9, "fill()\n", true) == OK and recorded
 for bloom in 8:
  recorded = first.record_nursery_harvest() == OK and recorded
 check(recorded and first.buy_nursery_upgrade(Progress.WILLOW_MARKER) == ERR_UNAVAILABLE and first.nursery_balance() == 8, "An unaffordable nursery purchase leaves the saved harvest intact")
 for bloom in 16:
  recorded = second.record_nursery_harvest() == OK and recorded
 var restored := Progress.new()
 restored.load_from(path)
 check(recorded and restored.nursery_balance() == 24 and restored.earned_lilies() == 2 and restored.python_drafts.get("first_bloom") == "fill()\n", "Reloading combines harvests from two sessions and preserves lesson progress and drafts")
 check(restored.buy_nursery_upgrade(Progress.RESERVOIR_MARKER) == ERR_UNAVAILABLE and restored.nursery_balance() == 24, "The reservoir upgrade opens after the Willow nursery purchase")
 var purchase := second.buy_nursery_upgrade(Progress.WILLOW_MARKER)
 var repeated := first.buy_nursery_upgrade(Progress.WILLOW_MARKER)
 check(purchase == OK and repeated == OK and first.nursery_balance() == 12 and second.nursery_balance() == 12 and first.has_nursery_upgrade(Progress.WILLOW_MARKER), "Two sessions see the same unlock and spend nursery lilies once")
 var saved := first.record_nursery_harvest() == OK
 var reopened := Progress.new()
 reopened.load_from(path)
 check(saved and reopened.nursery_balance() == 13 and reopened.lesson_available(Program.WILLOW_NURSERY, 0), "The purchased nursery and additional harvests survive a restart")
 for bloom in 12:
  saved = first.record_nursery_harvest() == OK and saved
 var reservoir := second.buy_nursery_upgrade(Progress.RESERVOIR_MARKER)
 var reservoir_again := first.buy_nursery_upgrade(Progress.RESERVOIR_MARKER)
 reopened.load_from(path)
 check(saved and reservoir == OK and reservoir_again == OK and reopened.nursery_balance() == 1 and reopened.has_nursery_upgrade(Progress.RESERVOIR_MARKER) and reopened.lesson_available(Program.WILLOW_NURSERY, 0), "Both upgrades and the remaining balance persist and are charged once per profile")
 for bloom in Progress.REACH_TOOL_COST - 1:
  saved = first.record_nursery_harvest() == OK and saved
 var reach := second.buy_nursery_upgrade(Progress.REACH_TOOL_MARKER)
 var reach_again := first.buy_nursery_upgrade(Progress.REACH_TOOL_MARKER)
 reopened.load_from(path)
 check(saved and reach == OK and reach_again == OK and reopened.nursery_balance() == 0 and reopened.has_nursery_upgrade(Progress.REACH_TOOL_MARKER) and reopened.next_nursery_upgrade() == Progress.LOTUS_MARSH_MARKER, "The reach tool persists and charges its price once across sessions")
 saved = first.record_nursery_harvest(Progress.LOTUS_MARSH_COST + 3) == OK and saved
 var marsh := second.buy_nursery_upgrade(Progress.LOTUS_MARSH_MARKER)
 var marsh_again := first.buy_nursery_upgrade(Progress.LOTUS_MARSH_MARKER)
 reopened.load_from(path)
 check(saved and marsh == OK and marsh_again == OK and reopened.nursery_balance() == 3 and reopened.lesson_available(Program.LOTUS_MARSH, 0) and reopened.next_nursery_upgrade() == Progress.HARVEST_HOOK_MARKER, "Lotus marsh and a multi-lily harvest persist across sessions with one purchase")
 saved = first.record_nursery_harvest(Progress.HARVEST_HOOK_COST) == OK and saved
 var hook := second.buy_nursery_upgrade(Progress.HARVEST_HOOK_MARKER)
 var hook_again := first.buy_nursery_upgrade(Progress.HARVEST_HOOK_MARKER)
 reopened.load_from(path)
 check(saved and hook == OK and hook_again == OK and reopened.nursery_balance() == 3 and reopened.has_nursery_upgrade(Progress.HARVEST_HOOK_MARKER) and reopened.next_nursery_upgrade() == Progress.STONE_RING_MARKER, "The harvest hook persists and costs its price once across sessions")
 saved = first.record_nursery_harvest(Progress.STONE_RING_COST) == OK and saved
 var ring := second.buy_nursery_upgrade(Progress.STONE_RING_MARKER)
 var ring_again := first.buy_nursery_upgrade(Progress.STONE_RING_MARKER)
 reopened.load_from(path)
 check(saved and ring == OK and ring_again == OK and reopened.nursery_balance() == 3 and reopened.lesson_available(Program.STONE_RING_NURSERY, 0) and reopened.next_nursery_upgrade() == Progress.SPEED_CONTROL_MARKER, "Stone ring nursery unlocks once and persists across sessions")
 saved = first.record_nursery_harvest(Progress.SPEED_CONTROL_COST) == OK and saved
 var speed := second.buy_nursery_upgrade(Progress.SPEED_CONTROL_MARKER)
 var speed_again := first.buy_nursery_upgrade(Progress.SPEED_CONTROL_MARKER)
 reopened.load_from(path)
 check(saved and speed == OK and speed_again == OK and reopened.nursery_balance() == 3 and reopened.has_nursery_upgrade(Progress.SPEED_CONTROL_MARKER) and reopened.next_nursery_upgrade() == Progress.ALDER_CROSSING_MARKER, "Speed control persists and charges its price once across sessions")
 saved = first.record_nursery_harvest(Progress.ALDER_CROSSING_COST) == OK
 var alder := second.buy_nursery_upgrade(Progress.ALDER_CROSSING_MARKER)
 var alder_again := first.buy_nursery_upgrade(Progress.ALDER_CROSSING_MARKER)
 reopened.load_from(path)
 check(saved and alder == OK and alder_again == OK and reopened.nursery_balance() == 3 and reopened.lesson_available(Program.ALDER_CROSSING, 0) and reopened.next_nursery_upgrade().is_empty(), "Alder Crossing unlocks once and persists across sessions")
 var ring_id: String = Program.STONE_RING_NURSERY.id
 var marsh_id: String = Program.LOTUS_MARSH.id
 var written := first.set_nursery_target(ring_id, 48)
 var separate := second.set_nursery_target(marsh_id, 8)
 var invalid := first.set_nursery_target(ring_id, Program.MAX_HARVEST_TARGET + 1)
 var scored := first.set_nursery_target("first_bloom", 4)
 reopened.load_from(path)
 check(written == OK and separate == OK and invalid == ERR_INVALID_PARAMETER and scored == ERR_INVALID_PARAMETER and reopened.nursery_target(ring_id) == 48 and reopened.nursery_target(marsh_id) == 8 and reopened.nursery_target(Program.OPEN_NURSERY.id) == Program.DEFAULT_HARVEST_TARGET, "Harvest targets persist independently and absent targets use the default")
 var board := Program.new()
 var nursery := Program.GARDENS.find(Program.OPEN_NURSERY)
 var id: String = Program.OPEN_NURSERY.id
 board.load_puzzle(nursery, true, true, true)
 board.harvest_target = 1
 board.harvested = 1
 board.turn = 9
 board.run_water_used = 3
 board.run_fills = 1
 var saved_result := first.record_nursery_best(id, board, "# First draft\nwait()\n", true)
 board.run_water_used = 2
 var best_source := "# Uses less water\nwait\n"
 var lower_water := second.record_nursery_best(id, board, best_source, false)
 board.turn = 10
 board.run_water_used = 1
 var more_actions := first.record_nursery_best(id, board, "# Longer draft\nwait()\n", true)
 board.starting_turn = 1
 var established := second.record_nursery_best(id, board, best_source, false)
 reopened.load_from(path)
 var saved_program := reopened.nursery_record(id, board)
 check(saved_result == OK and lower_water == OK and more_actions == OK and established == ERR_INVALID_PARAMETER and saved_program.score == Vector3i(9, 2, 1) and saved_program.source == best_source and not saved_program.python, "Reload keeps the best result and its exact program across sessions")
 board.harvest_target = 2
 var other_target := reopened.nursery_best(id, board)
 board.harvest_target = 1
 board.reach_tool = false
 check(other_target == Vector3i.ZERO and reopened.nursery_best(id, board) == Vector3i.ZERO, "Personal bests are scoped to the same target and tools")

 board.harvest_target = 2
 board.harvested = 2
 board.starting_turn = 0
 board.turn = 12
 board.run_water_used = 3
 var legacy_file := "%s%s-12-3-1.txt" % [Progress.NURSERY_BEST_PREFIX, first._nursery_best_key(id, board)]
 var legacy_saved := first._save(legacy_file, "completed")
 reopened.load_from(path)
 var older := reopened.nursery_record(id, board)
 var match_source := "# Matched the old score\nwait()\n"
 var matched := reopened.record_nursery_best(id, board, match_source, true)
 first.load_from(path)
 var migrated := first.nursery_record(id, board)
 check(legacy_saved == OK and older.score == Vector3i(12, 3, 1) and older.source.is_empty() and matched == OK and migrated.score == older.score and migrated.source == match_source and migrated.python, "A tied live result adds source to a legacy score without changing the score")

 var main_source := "# Main draft\nwait()\n"
 var main_saved := first.edit_draft(id, main_source, true)
 var first_copy := first.create_draft_copy(id, match_source, true)
 var second_copy := second.create_draft_copy(id, match_source, true)
 var classic_copy := second.create_draft_copy(id, best_source, false)
 var revised := "# Revised copy\nwait()\n"
 var copy_saved := first.edit_draft(first_copy.key, revised, true)
 reopened.load_from(path)
 check(main_saved == OK and first_copy.error == OK and second_copy.error == OK and classic_copy.error == OK and copy_saved == OK and first_copy.key != second_copy.key and reopened.python_drafts.get(id) == main_source and reopened.python_drafts.get(first_copy.key) == revised and reopened.python_drafts.get(second_copy.key) == match_source and reopened.drafts.get(classic_copy.key) == best_source, "Independent copies and the main draft reload with their own saved sources")
 check(reopened.draft_copy_keys(id, true).size() == 2 and reopened.draft_copy_keys(id, false) == PackedStringArray([classic_copy.key]) and reopened.draft_copy_keys(marsh_id, true).is_empty(), "Draft copies are listed only for the matching board and language")
 var named := first.rename_draft_copy(id, first_copy.key, true, "  North / south route  ")
 var classic_named := second.rename_draft_copy(id, classic_copy.key, false, "Bank hop")
 var main_rename := first.rename_draft_copy(id, id, true, "Other")
 var python_selected := first.select_draft(id, first_copy.key, true)
 var classic_selected := second.select_draft(id, classic_copy.key, false)
 var wrong_language := first.select_draft(id, classic_copy.key, true)
 reopened.load_from(path)
 check(named == OK and classic_named == OK and main_rename == ERR_INVALID_PARAMETER and wrong_language == ERR_INVALID_PARAMETER and reopened.draft_copy_name(first_copy.key, true) == "North / south route" and reopened.draft_copy_name(classic_copy.key, false) == "Bank hop" and reopened.draft_copy_name(second_copy.key, true).is_empty(), "Draft names reload with their own copies and languages")
 check(python_selected == OK and classic_selected == OK and reopened.selected_draft(id, true) == first_copy.key and reopened.selected_draft(id, false) == classic_copy.key and reopened.selected_draft(marsh_id, true) == marsh_id, "Selected drafts persist for each board and language")
 var restored_main := reopened.select_draft(id, id, true)
 first.load_from(path)
 check(restored_main == OK and first.selected_draft(id, true) == id and first.python_drafts.get(first_copy.key) == revised and first.draft_copy_name(first_copy.key, true) == "North / south route", "Returning to Main draft preserves the named copy")

func check_willow_nursery(popup, open_nursery: int) -> void:
 var willow := Program.GARDENS.find(Program.WILLOW_NURSERY)
 var earned: int = popup.progress.earned_lilies()
 var balance: int = popup.progress.nursery_balance()
 check(balance > 0 and balance < Progress.WILLOW_COST and popup.nursery_upgrade_button.disabled and popup.chooser.is_item_disabled(willow), "Live harvests remain in the nursery balance and Willow nursery starts locked")
 popup.source.text = Program.OPEN_NURSERY.python_draft
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.progress.nursery_balance() >= Progress.WILLOW_COST:
   break
  popup._process(.25)
 check(popup.running and popup.progress.nursery_balance() == Progress.WILLOW_COST and popup.nursery_upgrade_button.disabled, "Continuous harvesting funds the expansion and purchase waits for Stop")
 popup.stop_button.pressed.emit()
 popup.nursery_upgrade_button.pressed.emit()
 check(popup.puzzle == willow and popup.garden.practice and popup.garden.plants.size() == 5 and popup.progress.nursery_balance() == 0 and popup.progress.earned_lilies() == earned and "Upgrade reservoir" in popup.nursery_upgrade_button.text, "Buying Willow nursery opens five renewable beds and shows the next upgrade")
 popup.check_button.pressed.emit()
 check("Harvested 1 in 7 actions" in popup.status.text and popup.progress.nursery_balance() == 0 and popup.garden.turn == 0, "Check forecasts the Willow starter without crediting its harvest")

 popup.source.text = Program.OPEN_NURSERY.python_draft.replace("range(2)", "range(3)")
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.garden.harvested >= 5:
   break
  popup._process(.25)
 check(popup.running and popup.garden.harvested == 5 and popup.progress.nursery_balance() == 5 and not popup.score.visible, "An automated sweep spans the gap in Willow nursery and earns more lilies")
 popup.stop_button.pressed.emit()
 popup.chooser.item_selected.emit(open_nursery)
 check(popup.puzzle == open_nursery and not popup.chooser.is_item_disabled(willow) and popup.progress.nursery_balance() == 5, "Both nurseries remain available and share their saved harvest balance")

func check_nursery_reservoir(popup, open_nursery: int) -> void:
 var willow := Program.GARDENS.find(Program.WILLOW_NURSERY)
 popup.chooser.item_selected.emit(willow)
 var bank_sweep: String = Program.OPEN_NURSERY.python_draft.replace("range(2)", "range(3)")
 popup.source.text = bank_sweep
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.progress.nursery_balance() >= Progress.RESERVOIR_COST:
   break
  popup._process(.25)
 check(popup.running and popup.garden.water_capacity == 3 and popup.progress.nursery_balance() == Progress.RESERVOIR_COST and popup.nursery_upgrade_button.disabled, "Willow harvests fund the reservoir while the active program keeps its original tank")
 popup.stop_button.pressed.emit()
 var previous_tank: int = popup.garden.tank
 var previous_cell: Vector2i = popup.garden.cell
 var previous_plants: Dictionary = popup.garden.plants.duplicate(true)
 popup.nursery_upgrade_button.pressed.emit()
 check(popup.garden.water_capacity == 6 and popup.garden.tank == previous_tank and popup.garden.cell == previous_cell and popup.garden.plants == previous_plants and popup.progress.nursery_balance() == 0 and "Buy reach tool" in popup.nursery_upgrade_button.text and popup.nursery_upgrade_button.disabled, "Fitting the reservoir preserves the board and reveals the reach tool upgrade")
 popup._reset()
 var one_fill := bank_sweep.get_slice("# Find the spring", 0).replace("    fill()\n", "")
 one_fill += "fill()\ntend_row(north, south)\ntend_row(south, north)\nprint(tank_capacity(), water_level())\n"
 popup.source.text = one_fill
 popup.check_button.pressed.emit()
 check("Harvested 5 in 37 actions" in popup.status.text and popup.output_text.text.ends_with(" · 6 1") and popup.garden.tank == 0 and popup.progress.nursery_balance() == 0, "One fill covers five Willow beds in Check and the capacity sensor reports six")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 1
 check("Water 6 / 6" in popup.info.text and popup.garden.tank == 0, "Review shows the upgraded fill from the simulated board")
 await finish_by_steps(popup, one_fill)
 check(popup.garden.turn == 37 and popup.garden.harvested == 5 and popup.garden.tank == 1 and popup.progress.nursery_balance() == 5, "Running the single-fill route earns five lilies with one dose left")
 popup.chooser.item_selected.emit(open_nursery)
 check(popup.garden.water_capacity == 6 and "Water 0 / 6" in popup.info.text, "The saved reservoir applies to Open nursery too")
 popup.chooser.item_selected.emit(0)
 popup.source.text = "fill()\nprint(tank_capacity(), water_level())\n"
 popup.check_button.pressed.emit()
 check(popup.garden.water_capacity == 3 and popup.output_text.text.ends_with(" · 3 3") and "Water 0 / 3" in popup.info.text, "Scored lessons use the original capacity in the live board and Check")

func check_reach_tool(popup) -> String:
 var willow := Program.GARDENS.find(Program.WILLOW_NURSERY)
 popup.chooser.item_selected.emit(willow)
 popup.source.text = "print(has_reach_tool())\nplant(east)\n"
 popup.check_button.pressed.emit()
 check(popup.output_text.text.ends_with(" · False") and "requires the reach tool" in popup.status.text and popup.checked_route.actions.is_empty(), "Directional planting waits for the nursery upgrade")

 popup.source.text = Program.OPEN_NURSERY.python_draft.replace("range(2)", "range(3)")
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.progress.nursery_balance() >= Progress.REACH_TOOL_COST:
   break
  popup._process(.25)
 check(popup.running and popup.progress.nursery_balance() == Progress.REACH_TOOL_COST and popup.nursery_upgrade_button.disabled, "Willow automation funds the reach tool")
 popup.stop_button.pressed.emit()
 var before: Vector2i = popup.garden.cell
 popup.nursery_upgrade_button.pressed.emit()
 check(popup.garden.reach_tool and popup.garden.cell == before and popup.garden.water_capacity == 6 and popup.progress.nursery_balance() == 0 and popup.nursery_upgrade_button.disabled and "Unlock Lotus marsh" in popup.nursery_upgrade_button.text, "Fitting the reach tool preserves the reservoir and reveals Lotus marsh")
 popup._reset()
 popup.source.text = "fill()\nwater(east)\n"
 popup.check_button.pressed.emit()
 check("This plot does not need water." in popup.status.text and popup.checked_route.preview.tank == 6, "Watering a path with the reach tool spends no water")

 var route := """def tend_ahead(heading):
    if empty_bed(heading):
        plant(heading)
    if thirsty(heading):
        water(heading)
    hop(heading)
    if ripe():
        gather()

def sweep(toward, back):
    hop(toward)
    for _ in range(3):
        tend_ahead(east)
    for _ in range(3):
        hop(west)
    hop(back)

fill()
sweep(north, south)
sweep(south, north)
print(has_reach_tool(), water_level())
"""
 popup.source.text = route
 popup.check_button.pressed.emit()
 check("Harvested 5 in 32 actions" in popup.status.text and popup.output_text.text.ends_with(" · True 1") and popup.garden.turn == 0 and popup.progress.nursery_balance() == 0, "Check predicts all five beds in 32 actions with the reach tool")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 4
 check("Growing" in popup.board.get_child(1).get_child(0).text and "●" in popup.board.get_child(0).get_child(0).text and popup.garden.turn == 0, "Review shows the adjacent lily growing before Pondbot enters its bed")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 32 and popup.garden.harvested == 5 and popup.garden.tank == 1 and popup.progress.nursery_balance() == 5, "The live reach route earns all five lilies with one dose left")

 popup.language.item_selected.emit(1)
 popup.source.text = "fill\nhop north\nplant east\nwater east\nhop east\ngather\n"
 popup.check_button.pressed.emit()
 check("Harvested 1 in 6 actions" in popup.status.text and popup.progress.nursery_balance() == 5, "Classic Pondbot can preview planting and watering a neighboring bed")
 popup.language.item_selected.emit(0)
 popup.chooser.item_selected.emit(0)
 popup.source.text = "print(has_reach_tool())\nwater(east)\n"
 popup.check_button.pressed.emit()
 check(popup.output_text.text.ends_with(" · False") and "requires the reach tool" in popup.status.text and popup.garden.turn == 0, "Scored lessons report their own tool availability")
 return route

func check_lotus_marsh(popup, reach_route: String) -> String:
 var willow := Program.GARDENS.find(Program.WILLOW_NURSERY)
 var marsh := Program.GARDENS.find(Program.LOTUS_MARSH)
 popup.chooser.item_selected.emit(willow)
 popup.chooser.item_selected.emit(marsh)
 check(popup.puzzle == willow and popup.chooser.is_item_disabled(marsh) and "40 nursery lilies" in popup.chooser.get_item_text(marsh), "Lotus marsh stays locked until its purchase")
 popup.source.text = reach_route.get_slice("\nfill()\n", 0) + "\nwhile True:\n    fill()\n    sweep(north, south)\n    sweep(south, north)\n"
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.progress.nursery_balance() >= Progress.LOTUS_MARSH_COST:
   break
  popup._process(.25)
 check(popup.running and popup.progress.nursery_balance() == Progress.LOTUS_MARSH_COST and popup.nursery_upgrade_button.disabled, "The Willow reach route funds Lotus marsh through live harvests")
 popup.stop_button.pressed.emit()
 popup.nursery_upgrade_button.pressed.emit()
 check(popup.puzzle == marsh and not popup.chooser.is_item_disabled(marsh) and popup.progress.nursery_balance() == 0 and popup.nursery_upgrade_button.disabled and "Buy harvest hook" in popup.nursery_upgrade_button.text and popup.garden.water_capacity == 6 and popup.garden.reach_tool and popup.garden.plants.size() == 4, "Lotus marsh opens four renewable beds and offers the harvest hook")

 popup.check_button.pressed.emit()
 check("Harvested 4 in 11 actions" in popup.status.text and popup.garden.turn == 0 and popup.progress.nursery_balance() == 0, "The Python starter tends one pair for four lilies without spending live water or crediting the balance")
 popup.language.item_selected.emit(1)
 popup.check_button.pressed.emit()
 check("Harvested 4 in 11 actions" in popup.status.text, "The Classic starter also tends a lotus and its neighbor")
 popup.language.item_selected.emit(0)
 popup.source.text = "fill()\nhop(north)\nplant(east)\nwater(east)\nwater(east)\nhop(east)\ngather()\n"
 popup.check_button.pressed.emit()
 check("give it three more actions" in popup.status.text and popup.checked_route.actions.size() == 6 and popup.checked_route.preview.plant_status(Vector2i(1, 0)) == "Growing", "An early lotus harvest fails while it is still growing")

 var route := """def tend_ahead(heading):
    if empty_bed(heading):
        plant(heading)
    while thirsty(heading):
        water(heading)

def harvest_pair(approach, neighbor):
    tend_ahead(approach)
    hop(approach)
    tend_ahead(neighbor)
    gather()
    hop(neighbor)
    gather()

fill()
hop(north)
harvest_pair(east, east)
hop(south)
harvest_pair(south, west)
hop(west)
hop(north)
print(water_level())
"""
 popup.source.text = route
 popup.check_button.pressed.emit()
 check("Harvested 8 in 23 actions" in popup.status.text and popup.output_text.text.ends_with(" · 0") and popup.progress.nursery_balance() == 0, "Check predicts eight lilies on six doses and no idle actions")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 4
 check("Lotus\nThirsty ×1" == popup.board.get_child(1).get_child(0).text, "Review shows one more dose is needed after the first watering")
 popup.review_slider.value = 8
 check("● Lotus\nRipe" == popup.board.get_child(1).get_child(0).text and popup.garden.turn == 0 and popup.garden.plant_status(Vector2i(1, 0)) == Program.EMPTY_BED, "Review shows the lotus ripen while the neighboring lily is watered")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 23 and popup.garden.harvested == 8 and popup.progress.nursery_balance() == 8 and popup.garden.cell == Vector2i(0, 1) and popup.garden.tank == 0, "A live circuit pays eight nursery lilies and returns to the spring")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 46 and popup.garden.harvested == 16 and popup.progress.nursery_balance() == 16, "The same program replants and harvests both lotus beds again")
 return route

func check_harvest_hook(popup, lotus_route: String) -> String:
 popup.source.text = "print(has_harvest_hook())\ngather(north)\n"
 popup.check_button.pressed.emit()
 check(popup.output_text.text.ends_with(" · False") and "requires the harvest hook" in popup.status.text and popup.checked_route.actions.is_empty(), "Directional gathering waits for the harvest hook")
 var helpers := lotus_route.get_slice("\nfill()\n", 0)
 var circuit := "fill()\n" + lotus_route.get_slice("\nfill()\n", 1).get_slice("\nprint(", 0)
 popup.source.text = helpers + "\nwhile True:\n" + circuit.indent("    ")
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.progress.nursery_balance() >= Progress.HARVEST_HOOK_COST:
   break
  popup._process(.25)
 check(popup.running and popup.progress.nursery_balance() == Progress.HARVEST_HOOK_COST and popup.nursery_upgrade_button.disabled, "Live Lotus marsh circuits fund the harvest hook")
 popup.stop_button.pressed.emit()
 var prior_cell: Vector2i = popup.garden.cell
 var prior_turn: int = popup.garden.turn
 var prior_tank: int = popup.garden.tank
 var prior_plants: Dictionary = popup.garden.plants.duplicate(true)
 popup.source.text = "print(has_harvest_hook())\ngather(north)\n"
 popup.check_button.pressed.emit()
 popup.nursery_upgrade_button.pressed.emit()
 check(popup.garden.harvest_hook and popup.garden.reach_tool and popup.garden.water_capacity == 6 and popup.garden.cell == prior_cell and popup.garden.turn == prior_turn and popup.garden.tank == prior_tank and popup.garden.plants == prior_plants and popup.progress.nursery_balance() == 0 and not popup.review_button.visible, "Buying the hook preserves the live board and clears the locked preview")

 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.WILLOW_NURSERY))
 popup.source.text = "fill()\nhop(east)\nplant(north)\nwater(north)\ngather(north)\n"
 popup.check_button.pressed.emit()
 check("Gather a ripe lily" in popup.status.text and popup.checked_route.preview.harvested == 0 and popup.checked_route.preview.turn == 4 and popup.checked_route.preview.cell == Vector2i(1, 1) and popup.garden.turn == 0, "A directional harvest cannot gather a growing lily or advance the board")

 var route := """def tend(heading):
    if empty_bed(heading):
        plant(heading)
    while thirsty(heading):
        water(heading)

def collect(heading):
    if ripe(heading):
        gather(heading)

fill()
for _ in range(3):
    hop(east)
    tend(north)
    tend(south)

for _ in range(3):
    collect(north)
    collect(south)
    hop(west)
print(has_harvest_hook(), water_level())
"""
 popup.source.text = route
 popup.check_button.pressed.emit()
 check("Harvested 5 in 22 actions" in popup.status.text and popup.output_text.text.ends_with(" · True 1") and popup.progress.nursery_balance() == 0, "Check predicts five lilies from Willow's center path in 22 actions")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 16
 check("Empty bed" == popup.board.get_child(3).get_child(0).text and "Empty bed" == popup.board.get_child(11).get_child(0).text and "●" in popup.board.get_child(7).get_child(0).text and popup.garden.turn == 0, "Review shows both adjacent beds emptied while Pondbot stays on the path")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 22 and popup.garden.harvested == 5 and popup.progress.nursery_balance() == 5 and popup.garden.cell == Vector2i(0, 1) and popup.garden.tank == 1, "The live Willow route pays five lilies and returns to the spring")

 popup.language.item_selected.emit(1)
 popup.source.text = "fill\nhop east\nplant north\nwater north\nwait\ngather north\n"
 popup.check_button.pressed.emit()
 check("Harvested 1 in 6 actions" in popup.status.text and popup.checked_route.preview.cell == Vector2i(1, 1) and popup.progress.nursery_balance() == 5, "Classic Pondbot can gather from a neighboring bed")
 popup.language.item_selected.emit(0)
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.LOTUS_MARSH))
 popup.source.text = route
 popup.check_button.pressed.emit()
 check("Harvested 8 in 21 actions" in popup.status.text and popup.output_text.text.ends_with(" · True 0"), "The same center path route forecasts eight lilies in Lotus marsh")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 21 and popup.garden.harvested == 8 and popup.progress.nursery_balance() == 13 and popup.garden.cell == Vector2i(0, 1), "The hook collects the full live lotus reward from the path")

 popup.chooser.item_selected.emit(0)
 popup.source.text = "print(has_harvest_hook())\ngather(east)\n"
 popup.check_button.pressed.emit()
 check(popup.output_text.text.ends_with(" · False") and "requires the harvest hook" in popup.status.text and popup.garden.turn == 0, "Scored lessons retain their original gather behavior")
 return route

func check_stone_ring_nursery(popup, hook_route: String) -> void:
 var marsh := Program.GARDENS.find(Program.LOTUS_MARSH)
 var ring := Program.GARDENS.find(Program.STONE_RING_NURSERY)
 popup.chooser.item_selected.emit(marsh)
 popup.chooser.item_selected.emit(ring)
 check(popup.puzzle == marsh and popup.chooser.is_item_disabled(ring) and "72 nursery lilies" in popup.chooser.get_item_text(ring), "Stone ring nursery stays locked until its purchase")
 var helpers := hook_route.get_slice("\nfill()\n", 0)
 var circuit := "fill()\n" + hook_route.get_slice("\nfill()\n", 1).get_slice("\nprint(", 0)
 popup.source.text = helpers + "\nwhile True:\n" + circuit.indent("    ")
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.progress.nursery_balance() >= Progress.STONE_RING_COST:
   break
  popup._process(.25)
 var balance: int = popup.progress.nursery_balance()
 check(popup.running and balance == 73 and popup.nursery_upgrade_button.disabled, "Live harvests with the hook fund Stone ring nursery")
 popup.stop_button.pressed.emit()
 popup.nursery_upgrade_button.pressed.emit()
 var remaining := balance - Progress.STONE_RING_COST
 check(popup.puzzle == ring and popup.nursery_upgrade_button.disabled and "Buy speed control" in popup.nursery_upgrade_button.text and popup.garden.cell == Vector2i(0, 3) and popup.garden.water_capacity == 6 and popup.garden.reach_tool and popup.garden.harvest_hook and popup.garden.plants.size() == 8 and popup.progress.nursery_balance() == remaining, "The purchase opens eight beds at the west spring and preserves the change")

 var starter: String = popup.source.text
 popup.check_button.pressed.emit()
 check("Harvested 0 in 17 actions" in popup.status.text and popup.checked_route.preview.cell == Vector2i(4, 1) and popup.checked_route.preview.tank == 0 and popup.garden.turn == 0, "The Python starter waters the first bank on one tank and ends at the east spring")
 popup.language.item_selected.emit(1)
 popup.check_button.pressed.emit()
 check("Harvested 0 in 17 actions" in popup.status.text and popup.checked_route.preview.cell == Vector2i(4, 1), "Classic Pondbot surveys the same bank and reaches the east spring")
 popup.language.item_selected.emit(0)

 popup.source.text = starter.replace("\nif spring():", "\nwhile spring():")
 popup.check_button.pressed.emit()
 check("Harvested 84 in 256 actions" in popup.status.text and "Preview limit" in popup.status.text and popup.progress.nursery_balance() == remaining, "Continuous Python automation keeps harvesting in the preview without crediting live lilies")

 var route := starter.replace("\nif spring():", "\nfor _ in range(4):")
 popup.source.text = route
 popup.check_button.pressed.emit()
 check("Harvested 16 in 76 actions" in popup.status.text and popup.checked_route.preview.cell == Vector2i(0, 3) and popup.progress.nursery_balance() == remaining, "Check forecasts a complete warm-up circuit and a sixteen-lily harvest circuit")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 18
 check("Water 6 / 6" in popup.info.text and "●" in popup.board.get_child(9).get_child(0).text and popup.garden.tank == 0, "Review shows the second fill taking place at the east spring")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 76 and popup.garden.harvested == 16 and popup.progress.nursery_balance() == remaining + 16 and popup.garden.cell == Vector2i(0, 3), "The live program harvests both banks and returns west")

 route = route.replace("range(4)", "range(2)")
 await finish_by_steps(popup, route)
 check(popup.garden.turn == 118 and popup.garden.harvested == 32 and popup.progress.nursery_balance() == remaining + 32 and popup.garden.cell == Vector2i(0, 3), "The next live circuit harvests sixteen more lilies from the replanted beds")

func check_nursery_speed(popup) -> void:
 press_key(KEY_F8)
 check(not popup.speed_choice.visible and popup.speed_choice.get_selected_id() == 1, "Nursery speeds stay locked before purchase")
 popup.source.text = Program.STONE_RING_NURSERY.python_draft.replace("\nif spring():", "\nwhile spring():")
 press_key(KEY_ENTER, true)
 for action in Program.MAX_STEPS:
  if not popup.running or popup.progress.nursery_balance() >= Progress.SPEED_CONTROL_COST:
   break
  popup._process(.25)
 check(popup.running and popup.progress.nursery_balance() == Progress.SPEED_CONTROL_COST and popup.nursery_upgrade_button.disabled, "The automated Stone ring harvest funds speed control")
 popup.stop_button.pressed.emit()
 var prior_turn: int = popup.garden.turn
 var prior_cell: Vector2i = popup.garden.cell
 var prior_plants: Dictionary = popup.garden.plants.duplicate(true)
 popup.nursery_upgrade_button.pressed.emit()
 check(popup.speed_choice.visible and popup.speed_choice.item_count == 3 and popup.speed_choice.get_selected_id() == 1 and popup.progress.nursery_balance() == 0 and popup.garden.turn == prior_turn and popup.garden.cell == prior_cell and popup.garden.plants == prior_plants, "Buying speed control reveals three speeds without changing the live board")

 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.OPEN_NURSERY))
 popup.source.text = "fill()\nhop(north)\nplant(east)\nwater(east)\nhop(east)\ngather()\n"
 popup.check_button.pressed.emit()
 var preview_status: String = popup.status.text
 popup.speed_choice.select(2)
 popup.check_button.pressed.emit()
 check("Harvested 1 in 6 actions" in preview_status and popup.status.text == preview_status and popup.garden.turn == 0 and popup.progress.nursery_balance() == 0, "Run speed leaves the simulated route and crop growth unchanged")
 press_key(KEY_F8)

 popup.source.set_caret_line(5)
 press_key(KEY_F9)
 press_key(KEY_ENTER, true)
 popup._process(0.0)
 popup._process(.12)
 check(popup.speed_choice.get_selected_id() == 1 and popup.running and popup.garden.turn == 1, "Normal speed leaves the next action waiting after a short frame")
 press_key(KEY_F8)
 popup._process(.06)
 check(popup.speed_choice.get_selected_id() == 2 and popup.running and popup.garden.turn == 2 and popup.garden.cell == Vector2i(0, 0), "F8 changes a running program to double speed")
 press_key(KEY_F8)
 popup._process(.06)
 check(popup.speed_choice.get_selected_id() == 4 and popup.garden.turn == 3 and popup.garden.plant_status(Vector2i(1, 0)) == "Thirsty ×1", "The same frame interval advances the program at quadruple speed")

 press_key(KEY_ENTER, true)
 popup._process(.5)
 var paused_turn: int = popup.garden.turn
 press_key(KEY_F10)
 check(not popup.running and paused_turn == 3 and popup.garden.turn == 4 and popup.garden.plant_status(Vector2i(1, 0)) == "Growing", "Pausing holds the board and Step still runs one action at quadruple speed")
 press_key(KEY_ENTER, true)
 popup._process(0.0)
 popup._process(.06)
 check(not popup.running and popup.garden.turn == 5 and "Breakpoint · line 6" in popup.status.text and popup.garden.plant_status(Vector2i(1, 0)) == "Ripe", "A fast run stops at the breakpoint before harvesting")
 press_key(KEY_ENTER, true)
 popup._process(0.0)
 check(popup.steps.is_empty() and popup.garden.turn == 6 and popup.garden.harvested == 1 and popup.progress.nursery_balance() == 1, "Resuming a fast run earns the same harvest as Check")

 popup.chooser.item_selected.emit(0)
 popup.source.text = "fill()\nwait()\n"
 press_key(KEY_F8)
 press_key(KEY_ENTER, true)
 popup._process(0.0)
 popup._process(.12)
 check(not popup.speed_choice.visible and popup.speed_choice.get_selected_id() == 4 and popup.running and popup.garden.turn == 1, "Scored lessons run at normal speed regardless of the selected nursery speed")
 popup.stop_button.pressed.emit()

func check_run_counters(popup, hook_route: String) -> void:
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.STONE_RING_NURSERY))
 var balance: int = popup.progress.nursery_balance()
 popup.source.text = Program.STONE_RING_NURSERY.python_draft.replace("\nif spring():", "\nwhile spring() and harvest_count() < 32:")
 popup.check_button.pressed.emit()
 check("Harvested 32 in 118 actions" in popup.status.text and popup.checked_route.preview.cell == Vector2i(0, 3) and popup.progress.nursery_balance() == balance, "The Stone ring harvest quota stops at the spring after earning 32 lilies in Check")

 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.LOTUS_MARSH))
 await finish_by_steps(popup, Program.LOTUS_MARSH.python_draft + "hop(west)\nhop(west)\nhop(south)\n")
 var starting_turn: int = popup.garden.turn
 var starting_harvest: int = popup.garden.harvested
 var starting_balance: int = popup.progress.nursery_balance()
 check(starting_turn == 14 and starting_harvest == 4 and starting_balance == balance + 4 and popup.garden.cell == Vector2i(0, 1), "The quota test starts on a nursery with earlier live harvests")

 var helpers := hook_route.get_slice("\nfill()\n", 0)
 var circuit := "fill()\n" + hook_route.get_slice("\nfill()\n", 1).get_slice("\nprint(", 0)
 var program := helpers + "\ndef sweep():\n" + circuit.indent("    ") + """
print("start", harvest_count(), action_count())
while harvest_count() < 16 and action_count() < 30:
    sweep()
    print("lap", harvest_count(), action_count())
"""
 popup.source.text = program
 popup.check_button.pressed.emit()
 check("Harvested 16 in 42 actions" in popup.status.text and " · start 0 0" in popup.output_text.text and " · lap 8 21" in popup.output_text.text and popup.output_text.text.ends_with(" · lap 16 42") and popup.garden.turn == starting_turn and popup.progress.nursery_balance() == starting_balance, "Check counts only the new program on an occupied nursery")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 21
 var middle_counts: bool = popup.output_text.text.ends_with(" · lap 8 21")
 popup.review_slider.value = 0
 check(middle_counts and popup.output_text.text.ends_with(" · start 0 0") and popup.garden.harvested == starting_harvest, "Review restores counters for the selected position without touching live harvests")

 press_key(KEY_ENTER, true)
 for action in 21:
  popup._process(.25)
 press_key(KEY_ENTER, true)
 check(not popup.running and popup.garden.turn == starting_turn + 21 and popup.garden.harvested == starting_harvest + 8 and popup.output_text.text.ends_with(" · lap 8 21"), "The live quota program pauses after one circuit with eight lilies counted")
 press_key(KEY_F10)
 press_key(KEY_ENTER, true)
 for action in 20:
  popup._process(.25)
 check(popup.steps.is_empty() and popup.garden.turn == starting_turn + 42 and popup.garden.harvested == starting_harvest + 16 and popup.progress.nursery_balance() == starting_balance + 16 and popup.output_text.text.ends_with(" · lap 16 42"), "Step and Resume keep counting until the live harvest quota stops the program")

 popup.source.text = "print(harvest_count(), action_count())\nwait()\nprint(harvest_count(), action_count())\n"
 await finish_by_steps(popup, popup.source.text)
 check(" · 0 0" in popup.output_text.text and popup.output_text.text.ends_with(" · 0 1") and popup.garden.harvested == starting_harvest + 16, "Starting a new program resets its counts on the current board")

 popup.language.item_selected.emit(1)
 popup.source.text = "if harvest_count == 0\n  while action_count < 3\n    wait\n  end\nend\n"
 popup.check_button.pressed.emit()
 check("Harvested 0 in 3 actions" in popup.status.text and popup.checked_route.preview.turn == starting_turn + 46, "Classic Pondbot can stop at an action budget on the same nursery")
 popup.language.item_selected.emit(0)

 popup.chooser.item_selected.emit(0)
 popup.source.text = "if action_count() == 0 and harvest_count() == 0:\n    fill()\nprint(harvest_count(), action_count())\n"
 popup.check_button.pressed.emit()
 check("0 of 2 lilies harvested in 1 action" in popup.status.text and popup.output_text.text.ends_with(" · 0 1"), "Scored lesson previews can read the same counters")

func check_nursery_target(popup) -> void:
 var ring := Program.GARDENS.find(Program.STONE_RING_NURSERY)
 var marsh := Program.GARDENS.find(Program.LOTUS_MARSH)
 popup.chooser.item_selected.emit(ring)
 var starting_balance: int = popup.progress.nursery_balance()
 var program: String = Program.STONE_RING_NURSERY.python_draft.replace("\nif spring():", "\nwhile spring() and harvest_count() < harvest_target():")
 popup.source.text = program
 popup.check_button.pressed.emit()
 check(popup.nursery_target_row.visible and int(popup.nursery_target.value) == 32 and "Harvested 32 in 118 actions" in popup.status.text, "Python reads Stone ring's default harvest target")
 popup.review_button.pressed.emit()
 var target_input: LineEdit = popup.nursery_target.get_line_edit()
 target_input.text = "16"
 target_input.text_submitted.emit("16")
 await frames(2)
 check(popup.garden.harvest_target == 16 and popup.checked_route.is_empty() and not popup.review_controls.visible and popup.source.text == program, "Typing a new target clears Review and keeps the same draft")

 target_input.text = "24"
 popup.check_button.pressed.emit()
 check("Harvested 24 in 97 actions · Target 24 met · Water used 30 · Fills 5" in popup.status.text and popup.garden.turn == 0 and popup.progress.nursery_balance() == starting_balance, "Check applies a typed target and reports its harvest and water costs")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 18
 var has_refill: bool = "Water used 6 · Fills 2" in popup.review_position.text
 popup.review_slider.value = 0
 check(has_refill and "Water used 0 · Fills 0" in popup.review_position.text and popup.garden.turn == 0, "Review shows water and refill totals at the selected action")
 target_input.text = "16"
 press_key(KEY_ENTER, true)
 popup.nursery_target.value = 8
 check(popup.running and not popup.nursery_target.editable and int(popup.nursery_target.value) == 16 and popup.garden.harvest_target == 16, "An active run keeps its original target")
 for action in 76:
  popup._process(.25)
 check(popup.steps.is_empty() and popup.nursery_target.editable and popup.garden.turn == 76 and popup.garden.harvested == 16 and popup.progress.nursery_balance() == starting_balance + 16 and "Harvested 16 in 76 actions · Target 16 met · Water used 24 · Fills 4" in popup.status.text, "The live run reports its goal, harvest and water costs")
 press_key(KEY_ENTER, true)
 for action in 42:
  popup._process(.25)
 check(popup.steps.is_empty() and popup.garden.turn == 118 and popup.garden.harvested == 32 and popup.progress.nursery_balance() == starting_balance + 32 and "Harvested 16 in 42 actions · Target 16 met · Water used 12 · Fills 2" in popup.status.text, "A second run reports only its own work on the established nursery")
 check(popup.progress.nursery_best(Program.STONE_RING_NURSERY.id, popup.garden) == Vector3i(76, 24, 4), "An established board cannot replace the fresh-board personal best")

 popup.chooser.item_selected.emit(marsh)
 var starts_with_default: bool = int(popup.nursery_target.value) == 32
 popup.nursery_target.value = 8
 popup.chooser.item_selected.emit(ring)
 check(starts_with_default and int(popup.nursery_target.value) == 16 and popup.source.text == program, "Switching nurseries restores each target with its draft")
 popup.chooser.item_selected.emit(marsh)
 popup.language.item_selected.emit(1)
 popup.source.text = "if harvest_target == 8\n  wait\nend\n"
 popup.check_button.pressed.emit()
 check("Harvested 0 in 1 action" in popup.status.text and popup.checked_route.actions.size() == 1, "Classic Pondbot reads the saved harvest target")
 popup.language.item_selected.emit(0)
 popup.chooser.item_selected.emit(0)
 popup.source.text = "print(harvest_target())\nfill()\n"
 popup.check_button.pressed.emit()
 check(not popup.nursery_target_row.visible and popup.output_text.text.ends_with(" · 2"), "Scored lessons report their required harvest instead of showing a nursery field")

func check_nursery_reports(popup) -> void:
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.LOTUS_MARSH))
 var balance: int = popup.progress.nursery_balance()
 popup.source.text = "fill()\nfill()\nhop(north)\nplant(east)\nwater(east)\nwater(east)\nwater(east)\n"
 popup.check_button.pressed.emit()
 var partial_summary := "Harvested 0 in 6 actions · 8 short of 8 · Water used 2 · Fills 2"
 check("Check · Line 7 · This plot does not need water." in popup.status.text and partial_summary in popup.status.text, "A blocked Check reports completed actions and counts a top-up")
 popup.review_button.pressed.emit()
 popup.review_slider.value = 6
 check("Blocked" in popup.review_position.text and "Water used 2 · Fills 2" in popup.review_position.text and popup.garden.tank == 0 and popup.progress.nursery_balance() == balance, "The blocked preview keeps its water totals off the live board")

 press_key(KEY_ENTER, true)
 for action in 7:
  popup._process(.25)
 check(popup.steps.is_empty() and popup.garden.turn == 6 and popup.garden.tank == 4 and partial_summary in popup.status.text, "A live command error reports the same partial water use as Check")
 popup.source.text = "wait()\nwait()\nwait()\ngather(east)\nwhile True:\n    wait()\n"
 press_key(KEY_ENTER, true)
 for action in 4:
  popup._process(.25)
 var shows_progress: bool = "3 / 8 lilies this run" in popup.status.text
 popup.stop_button.pressed.emit()
 check(shows_progress and popup.progress.nursery_balance() == balance + 3 and popup.status.text == "Stopped · Harvested 3 in 4 actions · 5 short of 8 · Water used 0 · Fills 0", "Stopping reports the current run's lotus reward without counting earlier fills")

func check_nursery_bests(popup) -> void:
 var nursery := Program.GARDENS.find(Program.OPEN_NURSERY)
 var id: String = Program.OPEN_NURSERY.id
 popup.chooser.item_selected.emit(nursery)
 popup.nursery_target.value = 1
 var balance: int = popup.progress.nursery_balance()
 var route := "fill()\nhop(north)\nplant(east)\nwater(east)\nwait()\ngather(east)\n"
 var classic := "fill\nhop north\nplant east\nwater east\nwait\nwait\ngather east\n"
 popup.language.item_selected.emit(1)
 popup.source.text = classic
 press_key(KEY_ENTER, true)
 for action in 7:
  popup._process(.25)
 check(popup.steps.is_empty() and popup.best_button.visible and popup.progress.nursery_best(id, popup.garden) == Vector3i(7, 1, 1) and "New personal best" in popup.status.text and "Best for target 1 · 7 actions" in popup.score.text, "A finished reset-board run earns a nursery personal best and saves its program")
 popup.compare_drafts_button.pressed.emit()
 check(popup.draft_choice.item_count == 1 and popup.comparison_panel.visible and popup.comparison_choice.item_count == 1 and popup.comparison_choice.get_item_text(0) == "Personal best" and popup.comparison_start.selected == 1 and popup.comparison_other_route.initial.turn == 0 and popup.comparison_other_route.actions.size() == 7 and popup.garden.turn == 7, "A same-language best can be compared from a fresh nursery before any copies exist")
 press_key(KEY_ESCAPE)
 popup.language.item_selected.emit(0)
 check(popup.best_button.visible and not popup.compare_drafts_button.visible, "A best in the other language remains available for replay")
 popup.source.text = "# New Python draft\n" + route
 popup.best_button.pressed.emit()
 check(popup.best_panel.visible and popup.best_source.text == classic and not popup.best_source.editable and not popup.best_python and popup.source.text.begins_with("# New Python draft"), "Best program shows the recorded language and leaves the new draft available")
 check(popup.best_route.actions.size() == 7 and popup.best_route.initial.cell == Vector2i(0, 1) and popup.best_route.initial.turn == 0 and popup.garden.turn == 7 and popup.garden.harvested == 1 and popup.progress.nursery_balance() == balance + 1, "The saved replay starts on a fresh nursery while the live board stays intact")
 popup.review_slider.value = 7
 check("Best run · 7 / 7 actions" in popup.review_position.text and "Water used 1 · Fills 1" in popup.review_position.text and popup.progress.nursery_balance() == balance + 1, "The replay reaches the recorded total without earning another lily")
 press_key(KEY_ESCAPE)
 check(popup.visible and not popup.best_panel.visible and popup.nursery_target.editable and popup.garden.turn == 7 and popup.source.text.begins_with("# New Python draft"), "Closing the replay restores the live board and editable draft")
 popup.best_button.pressed.emit()
 popup.edit_copy_button.pressed.emit()
 check(not popup.best_panel.visible and popup.language.selected == 1 and popup.source.text == classic and popup.source.editable and popup.draft_choice.is_visible_in_tree() and popup.draft_choice.selected == 1 and popup.garden.turn == 7 and popup.progress.nursery_balance() == balance + 1, "Edit a copy opens the recorded language and leaves the live nursery intact")
 popup.rename_draft_button.pressed.emit()
 popup.draft_name_edit.text = "Discard this name"
 press_key(KEY_ESCAPE)
 check(popup.visible and not popup.draft_name_edit.visible and popup.draft_choice.get_item_text(1) == "Copy 1", "Escape cancels a rename without closing the garden")
 popup.rename_draft_button.pressed.emit()
 popup.draft_name_edit.text = "Bank hop"
 popup.draft_name_edit.text_submitted.emit("Bank hop")
 check(not popup.draft_name_edit.visible and popup.draft_choice.get_item_text(1) == "1 · Bank hop" and popup.source.text == classic and popup.garden.turn == 7, "Typing a name relabels the selected copy and preserves its code and live board")
 popup.source.text = "# Edited Classic copy\n" + classic
 popup.draft_choice.item_selected.emit(0)
 check(popup.source.text == classic and popup.draft_choice.selected == 0, "Switching back to the main draft leaves its Classic code intact")
 popup.draft_choice.item_selected.emit(1)
 check(popup.source.text.begins_with("# Edited Classic copy") and popup.draft_choice.get_item_text(1) == "1 · Bank hop", "Switching drafts saves the edits and name of the copied program")
 popup.rename_draft_button.pressed.emit()
 popup.draft_name_edit.text = ""
 popup.save_draft_name_button.pressed.emit()
 check(popup.draft_choice.get_item_text(1) == "Copy 1" and popup.source.text.begins_with("# Edited Classic copy"), "Saving an empty name restores the numbered label only")
 popup.language.item_selected.emit(0)
 check(popup.source.text == "# New Python draft\n" + route and not popup.draft_choice.is_visible_in_tree(), "Copying a Classic record preserves the separate Python draft")
 popup._reset()
 popup.source.text = route
 popup.check_button.pressed.emit()
 check("Compared with best · -1 actions · +0 doses · +0 fills" in popup.status.text and popup.progress.nursery_best(id, popup.garden) == Vector3i(7, 1, 1) and popup.progress.nursery_balance() == balance + 1, "Check compares a faster route without recording a new best")
 press_key(KEY_ENTER, true)
 for action in 6:
  popup._process(.25)
 check(popup.steps.is_empty() and popup.progress.nursery_best(id, popup.garden) == Vector3i(6, 1, 1) and popup.progress.nursery_balance() == balance + 2 and "New personal best" in popup.status.text, "Completing the improved route saves the better result")

 popup.nursery_target.value = 2
 check(not popup.score.visible and popup.progress.nursery_best(id, popup.garden) == Vector3i.ZERO, "Changing the target clears the displayed comparison until there is a matching best")
 popup._reset()
 var long_route := "while action_count() < 260:\n    wait()\n" + route + "plant(east)\nwater(east)\nwait()\ngather(east)\n"
 popup.source.text = long_route
 popup.check_button.pressed.emit()
 check(popup.checked_route.actions.size() == Program.MAX_STEPS and not popup.best_button.visible, "Check retains its normal limit on a long nursery script")
 press_key(KEY_ENTER, true)
 for action in 270:
  popup._process(.25)
 popup.best_button.pressed.emit()
 check(popup.best_panel.visible and popup.best_python and popup.best_source.text == long_route and popup.best_route.actions.size() == 270 and not popup.best_route.limited and popup.best_route.preview.run_harvest_count() == 2 and popup.progress.nursery_balance() == balance + 4, "Best program replays a completed nursery run past the Check limit")
 popup.edit_copy_button.pressed.emit()
 popup.source.text = "# Improved copy\n" + long_route
 popup.best_button.pressed.emit()
 popup.edit_copy_button.pressed.emit()
 var second_selected: bool = popup.draft_choice.item_count == 3 and popup.draft_choice.selected == 2 and popup.source.text == long_route
 popup.draft_choice.item_selected.emit(1)
 var kept_first: bool = popup.source.text == "# Improved copy\n" + long_route
 check(second_selected and kept_first and popup.progress.nursery_record(id, popup.garden).source == long_route and popup.garden.turn == 270, "Opening another copy preserves both the earlier edit and the saved best program")
 press_key(KEY_ENTER, true)
 check(popup.draft_choice.disabled and popup.rename_draft_button.disabled and popup.running and popup.draft_choice.selected == 1, "Draft selection and renaming stay locked while the editor executes a copy")
 popup.stop_button.pressed.emit()
 popup.draft_choice.item_selected.emit(0)
 check(popup.source.text == long_route and popup.draft_choice.selected == 0, "The original main draft remains available after creating and running copies")

func check_draft_comparison(popup) -> void:
 var id: String = Program.OPEN_NURSERY.id
 popup._reset()
 popup.nursery_target.value = 1
 var setup := "fill()\nhop(north)\nplant(east)\nwater(east)\nwait()\n"
 await finish_by_steps(popup, setup)
 var balance: int = popup.progress.nursery_balance()
 popup.draft_choice.item_selected.emit(1)
 popup.source.text = "wait()\ngather(east)\n"
 popup.draft_choice.item_selected.emit(2)
 popup.source.text = "hop(east)\nwater()\n"
 popup.draft_choice.item_selected.emit(0)
 var current := "gather(east)\n"
 popup.source.text = current
 var live_plot: Node = popup.world.garden_root.get_child(0)
 popup.compare_drafts_button.pressed.emit()
 check(popup.comparison_panel.visible and popup.comparison_choice.item_count == 3 and popup.comparison_start.visible and popup.comparison_start.get_item_text(popup.comparison_start.selected) == "Live nursery" and "Harvested 1 in 1 action · Target 1 met" in popup.comparison_current.text and "Harvested 1 in 2 actions · Target 1 met" in popup.comparison_other.text, "Compare forecasts both drafts from the same living nursery")
 check(popup.comparison_slider.max_value == 2 and popup.comparison_slider.value == 2 and popup.comparison_slider.has_focus() and "Finished · 1 / 1 actions" in popup.comparison_current.text and "Line 2 · gather east" in popup.comparison_other.text, "The comparison holds the shorter draft at its endpoint")
 var current_board: GridContainer = popup.comparison_current_board
 var other_board: GridContainer = popup.comparison_other_board
 check(current_board.columns == 3 and other_board.columns == 3 and current_board.get_child_count() == 9 and other_board.get_child_count() == 9 and popup.comparison_board_key.visible, "Both previews draw the nursery layout")
 popup.comparison_difference_button.grab_focus()
 press_key(KEY_ENTER)
 check(popup.comparison_slider.value == 1 and popup.comparison_slider.has_focus() and "gather east" in popup.comparison_current.text and "Line 1 · wait" in popup.comparison_other.text, "Enter jumps to the first different command and returns focus to the slider")
 popup.comparison_slider.value = 0
 check("0 / 2 actions" in popup.comparison_position.text and "Start" in popup.comparison_current.text and "Start" in popup.comparison_other.text and "Row 0 · Column 0 · Tank 5 / 6" in popup.comparison_current.text and "Row 0 · Column 0 · Tank 5 / 6" in popup.comparison_other.text and "Harvested 0" in popup.comparison_current.text and "Harvested 0" in popup.comparison_other.text, "Both previews return to the same nursery state at action zero")
 check(current_board.get_child(1).get_child(0).text == "Ripe" and other_board.get_child(1).get_child(0).text == "Ripe" and current_board.get_child(1).get_theme_stylebox("panel").get_margin(SIDE_LEFT) == 0, "Both boards show the same ripe bed without a comparison outline at the start")
 press_key(KEY_RIGHT)
 check(popup.comparison_slider.value == 1 and "Line 1 · gather east" in popup.comparison_current.text and "Line 1 · wait" in popup.comparison_other.text and "Harvested 1 in 1 action" in popup.comparison_current.text and "Harvested 0 in 1 action" in popup.comparison_other.text, "The keyboard moves both drafts to the same action and reveals the different harvests")
 check(current_board.get_child(1).get_child(0).text == Program.EMPTY_BED and other_board.get_child(1).get_child(0).text == "Ripe" and current_board.get_child(1).get_theme_stylebox("panel").get_margin(SIDE_LEFT) == 2 and other_board.get_child(1).get_theme_stylebox("panel").get_margin(SIDE_LEFT) == 2, "The harvest changes and outlines the same tile on both boards")
 press_key(KEY_RIGHT)
 check(popup.comparison_slider.value == 2 and "Finished · 1 / 1 actions" in popup.comparison_current.text and "Harvested 1 in 2 actions" in popup.comparison_other.text, "Advancing past the short route leaves its completed state visible")
 check(current_board.get_child(1).get_child(0).text == Program.EMPTY_BED and other_board.get_child(1).get_child(0).text == Program.EMPTY_BED and other_board.get_child(1).get_theme_stylebox("panel").get_margin(SIDE_LEFT) == 0 and popup.board.get_child(1).get_child(0).text == "Ripe" and popup.world.garden_root.get_child(0) == live_plot, "Matching endpoints clear the outline and leave the live boards untouched")
 check(popup.draft_choice.selected == 0 and popup.source.text == current and popup.progress.python_drafts.get(id) == setup and popup.garden.turn == 5 and popup.garden.tank == 5 and popup.garden.plant_status(Vector2i(1, 0)) == "Ripe" and popup.progress.nursery_balance() == balance, "A comparison leaves the unsaved edit, saved draft, live bed, and wallet intact")
 popup.comparison_choice.select(1)
 popup.comparison_choice.item_selected.emit(1)
 check("Blocked · Line 2 · This plot does not need water." in popup.comparison_other.text and "Harvested 1 in 1 action" in popup.comparison_current.text, "A blocked comparison draft does not hide the other result")
 check("●" in current_board.get_child(0).get_child(0).text and "●" in other_board.get_child(1).get_child(0).text and other_board.get_child(1).get_theme_stylebox("panel").bg_color == Color("#784b30") and other_board.get_child(0).get_theme_stylebox("panel").get_margin(SIDE_LEFT) == 2 and other_board.get_child(1).get_theme_stylebox("panel").get_margin(SIDE_LEFT) == 2, "Different Pondbot positions outline both tiles and show where the other draft blocked")
 popup.comparison_slider.value = 0
 check("Blocked" not in popup.comparison_other.text and "Start" in popup.comparison_other.text and "Harvested 0" in popup.comparison_current.text, "Rewinding the comparison puts the blocked action back in the future")
 press_key(KEY_ESCAPE)
 check(popup.visible and not popup.comparison_panel.visible and current_board.get_child_count() == 0 and other_board.get_child_count() == 0, "Escape closes the comparison and stays in the editor")
 popup.compare_drafts_button.pressed.emit()
 popup.source.text = "wait()\n"
 popup._queue_save()
 check(not popup.comparison_panel.visible and popup.comparison_current_route.is_empty() and popup.comparison_other_route.is_empty() and popup.garden.turn == 5, "Editing the active draft clears both old previews")

 var recorded: Dictionary = popup.progress.create_draft_copy("first_bloom", "fill(east)\n", true)
 popup.chooser.item_selected.emit(0)
 popup.source.text = "fill()\n"
 popup.compare_drafts_button.pressed.emit()
 check(recorded.error == OK and popup.comparison_panel.visible and "Fresh lesson" in popup.comparison_context.text and not popup.comparison_start.visible and "Harvested 0 of 2 in 1 action" in popup.comparison_current.text and "Check the arguments for fill()" in popup.comparison_other.text and popup.garden.turn == 0, "Lesson comparisons start fresh and report each draft's compile result")
 check(current_board.get_child_count() == 3 and other_board.get_child_count() == 0 and not popup.comparison_board_key.visible and not popup.comparison_difference_button.visible, "A draft that cannot compile has no board or first difference control")
 press_key(KEY_ENTER, true)
 check(not popup.comparison_panel.visible and popup.compare_drafts_button.disabled and popup.running, "Starting a run closes the comparison and locks it while the program runs")
 popup.stop_button.pressed.emit()

 var ring: int = Program.GARDENS.find(Program.STONE_RING_NURSERY)
 var ring_copy: Dictionary = popup.progress.create_draft_copy(Program.STONE_RING_NURSERY.id, "fill()\nhop(east)\nhop(west)\nwait()\nhop(east)\nwait()\n", true)
 popup.chooser.item_selected.emit(ring)
 popup.source.text = "fill()\nhop(north)\nhop(south)\nwait()\nhop(north)\nwait()\n"
 popup.compare_drafts_button.pressed.emit()
 await frames(2)
 var current_rect := current_board.get_global_rect()
 var other_rect := other_board.get_global_rect()
 var boards_aligned := is_equal_approx(current_rect.position.y, other_rect.position.y) and current_rect.end.x < other_rect.position.x
 var right_column := popup.board as GridContainer
 var editor_fits: bool = popup.source.size.y >= 100 and get_viewport().get_visible_rect().encloses(popup.get_global_rect())
 check(ring_copy.error == OK and current_board.get_child_count() == 25 and other_board.get_child_count() == 25 and boards_aligned and other_rect.end.x <= right_column.get_global_rect().position.x and editor_fits, "Both five-by-five boards fit beside each other with room to edit Python")

 popup.comparison_difference_button.pressed.emit()
 check(popup.comparison_slider.value == 2 and "hop north" in popup.comparison_current.text and "hop east" in popup.comparison_other.text, "The first difference skips a shared fill and finds the first different direction")
 var slider: HSlider = popup.comparison_slider
 var previous: Button = popup.comparison_previous_difference_button
 var next: Button = popup.comparison_next_difference_button
 press_key(KEY_PAGEUP)
 check(slider.value == 2 and previous.visible and previous.disabled and not next.disabled, "Previous stops at the first difference")
 press_key(KEY_PAGEDOWN)
 check(slider.value == 3 and "Difference 2 of 3" in popup.comparison_board_key.text and "●" in current_board.get_child(15).get_child(0).text and "●" in other_board.get_child(15).get_child(0).text, "Page Down finds different return commands that bring both frogs back to the spring")
 press_key(KEY_PAGEDOWN)
 press_key(KEY_PAGEDOWN)
 check(slider.value == 5 and next.disabled and not previous.disabled and "Difference 3 of 3" in popup.comparison_board_key.text, "Page Down skips the shared action and stops at the final direction difference")
 previous.grab_focus()
 press_key(KEY_ENTER)
 check(slider.value == 3 and slider.has_focus(), "The Previous button works from the keyboard and returns focus to the slider")
 slider.value = 4
 next.pressed.emit()
 check(slider.value == 5 and next.disabled and not previous.disabled, "Next starts from the current slider position")

func check_comparison_stopping_points(popup) -> void:
 var id := "first_bloom"
 var shared := "fill()\nhop(east)\n"
 var current := shared + "wait()\n"
 var programs := ["print(4)\n" + current, shared, shared + "fill()\n", "gather()\n", current + "wait()\nwait()\nfill()\n"]
 var keys: Array[String] = []
 for program: String in programs:
  var copy: Dictionary = popup.progress.create_draft_copy(id, program, true)
  keys.append(copy.key)
 popup.chooser.item_selected.emit(0)
 popup.source.text = current
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var difference: Button = popup.comparison_difference_button
 var slider: HSlider = popup.comparison_slider
 for test in keys.size():
  select_comparison_copy(choice, keys[test])
  match test:
   0:
    check(difference.visible and difference.disabled and difference.text == "No preview difference" and "Line 4 · wait" in popup.comparison_other.text, "Equivalent board actions match even with different Python output and line numbers")
   1:
    slider.value = 0
    difference.pressed.emit()
    check(slider.value == 3 and "Finished" in popup.comparison_other.text and "Line 3 · wait" in popup.comparison_current.text, "The first difference finds the next action after a shorter route finishes")
   2:
    difference.pressed.emit()
    check(slider.value == 2 and "Blocked · Line 3 · Fill at the spring." in popup.comparison_other.text and "Line 2 · hop east" in popup.comparison_current.text, "A blocked command diverges at the last shared action")
   3:
    difference.pressed.emit()
    check(slider.value == 0 and difference.text == "First difference · Start" and "Blocked · Line 1" in popup.comparison_other.text and "Start" in popup.comparison_current.text, "The first difference can occur before either draft completes an action")
   4:
    difference.pressed.emit()
    check(slider.value == 4 and "Finished" in popup.comparison_current.text and "Line 4 · wait" in popup.comparison_other.text and "Difference 1 of 2" in popup.comparison_board_key.text, "The longer route first diverges by continuing after the shorter route")
    press_key(KEY_PAGEDOWN)
    check(slider.value == 5 and "Blocked · Line 6 · Fill at the spring." in popup.comparison_other.text and "Difference 2 of 2" in popup.comparison_board_key.text, "A later blocked command remains a separate difference")

func select_comparison_copy(choice: OptionButton, key: String) -> void:
 for index in choice.item_count:
  if choice.get_item_metadata(index) == key:
   choice.select(index)
   choice.item_selected.emit(index)
   return

func check_comparison_python_details(popup) -> void:
 var id: String = Program.OPEN_NURSERY.id
 var nursery := Program.GARDENS.find(Program.OPEN_NURSERY)
 popup.chooser.item_selected.emit(nursery)
 await finish_by_steps(popup, "marker = 99\nwait()\nprint('live', marker)\n")
 var main_source := "count = 2\nprint('Current start', count)\nwait()\ncount += 1\nprint('Current end', count)\n"
 var other_source := "count = 10\nprint('Other start', count)\nday = 0\nwhile day < 35:\n    wait()\n    count += 1\n    day += 1\n    print('Other action', count)\n"
 var other_draft: Dictionary = popup.progress.create_draft_copy(id, other_source, true)
 var bad_draft: Dictionary = popup.progress.create_draft_copy(id, "fill(east)\n", true)
 popup._refresh_draft_choice()
 popup.source.text = main_source
 popup.compare_drafts_button.pressed.emit()
 var slider: HSlider = popup.comparison_slider
 var chooser: OptionButton = popup.comparison_choice
 var view: OptionButton = popup.comparison_view
 var current: RichTextLabel = popup.comparison_current_details
 var other: RichTextLabel = popup.comparison_other_details
 select_comparison_copy(chooser, other_draft.key)
 check(other_draft.error == OK and bad_draft.error == OK and view.visible and view.selected == 0 and popup.comparison_current_board.visible and slider.value == 35 and popup.garden.turn == 1, "Python comparison starts on the boards using the active nursery")
 slider.value = 0
 view.select(1)
 view.item_selected.emit(1)
 check(slider.value == 0 and current.visible and other.visible and not popup.comparison_current_board.visible and current.get_parsed_text() == "count = 2\nday = —" and other.get_parsed_text() == "count = 10\nday = 0", "Variables shows both sets of assignments before the first board action")
 check("[color=#e8c879]count = 2[/color]" in current.text and "[color=#e8c879]day = —[/color]" in current.text and "[color=#e8c879]day = 0[/color]" in other.text, "Different variables and unassigned values appear in gold on aligned rows")
 slider.grab_focus()
 press_key(KEY_RIGHT)
 check(slider.value == 1 and current.get_parsed_text() == "count = 3\nday = —" and other.get_parsed_text() == "count = 11\nday = 1", "Keyboard stepping shows variable values after the first action")
 view.select(2)
 view.item_selected.emit(2)
 check(slider.value == 1 and current.get_parsed_text() == "Line 2 · Current start 2\nLine 5 · Current end 3" and other.get_parsed_text() == "Line 2 · Other start 10\nLine 8 · Other action 11", "Print output shows both transcripts at the selected action")
 slider.value = 35
 check(current.get_parsed_text().ends_with("Current end 3") and other.get_parsed_text().split("\n").size() == Program.MAX_OUTPUT_MESSAGES and "Other start" not in other.get_parsed_text() and other.get_parsed_text().ends_with("Other action 45"), "The shorter transcript holds as the longer route fills its output buffer")
 await frames(2)
 check("[color=" not in current.text and other.text.ends_with("[color=#e8c879]Line 8 · Other action 45[/color]") and other.get_v_scroll_bar().value > 0, "Print output scrolls to the highlighted message and leaves earlier output plain")
 slider.value = 0
 check(current.get_parsed_text() == "Line 2 · Current start 2" and other.get_parsed_text() == "Line 2 · Other start 10", "Rewinding recovers early output after the final buffer rolls over")
 select_comparison_copy(chooser, bad_draft.key)
 check(view.selected == 2 and other.get_parsed_text() == "Preview unavailable" and "Check the arguments for fill()" in popup.comparison_other.text and current.get_parsed_text().ends_with("Current end 3") and "[color=" not in current.text, "A compile failure clears that draft's details while the other output remains available")
 view.select(0)
 view.item_selected.emit(0)
 check(popup.comparison_current_board.visible and not current.is_visible_in_tree() and popup.source.text == main_source and popup.garden.turn == 1 and popup.garden.variables == {"marker":99} and popup.output_text.text == "Line 3 · live 99", "Switching views preserves the editable draft and the live Python state")
 press_key(KEY_ESCAPE)
 check(popup.visible and not popup.comparison_panel.visible and current.get_parsed_text().is_empty() and other.get_parsed_text().is_empty(), "Closing the comparison clears both Python detail panels")

func check_comparison_python_differences(popup) -> void:
 var current_source := "count = 1\nprint('left')\nwait()\ncount = 3\nprint('same')\nwait()\ncount = 7\nwait()\nwait()\nprint('left end')\n"
 var other_source := "count = 2\nprint('right')\nwait()\ncount = 3\n# A different line number for the same message\nprint('same')\nwait()\ncount = 8\nwait()\nwait()\nprint('right end')\n"
 var other: Dictionary = popup.progress.create_draft_copy("first_bloom", other_source, true)
 var still: Dictionary = popup.progress.create_draft_copy("first_bloom", "print('[b]other[/b]')\n", true)
 popup.chooser.item_selected.emit(0)
 popup.source.text = current_source
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var view: OptionButton = popup.comparison_view
 var first: Button = popup.comparison_difference_button
 var slider: HSlider = popup.comparison_slider
 select_comparison_copy(choice, other.key)
 check(other.error == OK and view.selected == 0 and first.disabled and slider.value == 4, "Boards match when only the Python state and prints differ")
 view.select(1)
 view.item_selected.emit(1)
 check(slider.value == 4 and first.text == "First difference · Start" and popup.comparison_differences == [0, 2], "Variables finds different starting values and skips an unchanged mismatch")
 first.pressed.emit()
 press_key(KEY_PAGEDOWN)
 check(slider.value == 2 and popup.comparison_current_details.get_parsed_text() == "count = 7" and popup.comparison_other_details.get_parsed_text() == "count = 8", "Page Down jumps to the next mismatch after the variables match again")
 view.select(2)
 view.item_selected.emit(2)
 check(slider.value == 2 and popup.comparison_differences == [0, 4], "Print differences skip shared messages whose source lines differ")
 slider.value = 1
 check("[color=" not in popup.comparison_current_details.text and "[color=" not in popup.comparison_other_details.text, "Matching messages at this action leave earlier mismatches unhighlighted")
 press_key(KEY_PAGEDOWN)
 check(slider.value == 4 and "Difference 2 of 2" in popup.comparison_board_key.text and popup.comparison_other_details.get_parsed_text().ends_with("right end"), "Print navigation finds the later different message")
 view.select(0)
 view.item_selected.emit(0)
 check(slider.value == 4 and first.disabled and popup.comparison_differences.is_empty(), "Returning to Boards restores its own difference list")

 popup.compare_drafts_button.pressed.emit()
 popup.source.text = "print('[color=red]main[/color]')\n"
 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(choice, still.key)
 view.select(2)
 view.item_selected.emit(2)
 check(still.error == OK and slider.max_value == 0 and not slider.visible and first.is_visible_in_tree() and first.text == "First difference · Start" and "Difference 1 of 1" in popup.comparison_board_key.text, "Print-only drafts can differ without taking a board action")
 check(popup.comparison_current_details.get_parsed_text() == "Line 1 · [color=red]main[/color]" and popup.comparison_other_details.get_parsed_text() == "Line 1 · [b]other[/b]" and popup.comparison_current_details.text.count("[color=") == 1, "Bracketed print output displays literally inside the comparison highlight")

func check_duplicate_draft(popup) -> void:
 var temporary := DirAccess.create_temp("frog-duplicate-draft")
 check(temporary != null, "Duplicate draft storage uses an isolated profile")
 if temporary == null:
  return
 var id: String = Program.WILLOW_NURSERY.id
 var nursery := Program.GARDENS.find(Program.WILLOW_NURSERY)
 popup.chooser.item_selected.emit(nursery)
 await finish_by_steps(popup, "fill()\nhop(east)\n")
 var original_folder: String = popup.progress.folder
 popup.progress.folder = temporary.get_current_dir()
 var button: Button = popup.duplicate_draft_button
 var choice: OptionButton = popup.draft_choice
 check(button.is_visible_in_tree() and not button.disabled and choice.item_count == 1, "Duplicate draft is available before the first copy exists")
 var main_source := "# Main draft\nwait()\nwait()\n"
 popup.source.text = main_source
 popup.source.set_caret_line(1)
 popup.source.set_caret_column(3)
 popup._queue_save()
 var waiting_for_autosave: bool = popup.draft_timer.time_left > 0 and popup.progress.python_drafts.get(id) != main_source
 button.grab_focus()
 press_key(KEY_ENTER)
 var first_copy: String = popup.progress.selected_draft(id, true)
 check(waiting_for_autosave and first_copy != id and choice.selected == 1 and popup.progress.python_drafts.get(id) == main_source and popup.progress.python_drafts.get(first_copy) == main_source, "Enter duplicates the text before autosave and saves both drafts")
 check(popup.source.has_focus() and popup.source.get_caret_line() == 1 and popup.source.get_caret_column() == 3 and popup.garden.turn == 2 and popup.garden.cell == Vector2i(1, 1), "The new copy opens at the same cursor and keeps the live nursery")

 var first_source := "# Short variant\nwait()\n"
 popup.source.text = first_source
 button.pressed.emit()
 var second_copy: String = popup.progress.selected_draft(id, true)
 check(first_copy != second_copy and choice.item_count == 3 and popup.source.text == first_source and popup.progress.python_drafts.get(first_copy) == first_source and popup.progress.python_drafts.get(id) == main_source, "Duplicating a saved copy keeps its edits and the main draft independently")
 var second_source := "# Walking variant\nhop(east)\nwait()\n"
 popup.source.text = second_source
 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(popup.comparison_choice, id)
 check(popup.comparison_panel.visible and popup.comparison_differences == [1] and popup.garden.turn == 2, "The new draft can be compared with the main route without advancing the live nursery")
 press_key(KEY_ESCAPE)
 popup.step_button.pressed.emit()
 button.pressed.emit()
 check(button.disabled and not popup.steps.is_empty() and choice.item_count == 3 and popup.progress.selected_draft(id, true) == second_copy, "A paused program keeps the duplicate control locked")
 popup.stop_button.pressed.emit()

 popup.language.item_selected.emit(1)
 var classic_source := "wait\n"
 popup.source.text = classic_source
 button.pressed.emit()
 var classic_copy: String = popup.progress.selected_draft(id, false)
 check(not popup.python_mode and popup.source.text == classic_source and classic_copy != id and choice.item_count == 2 and popup.progress.selected_draft(id, true) == second_copy, "Classic copies and selections stay independent of Python")
 var reopened := Progress.new()
 reopened.load_from(temporary.get_current_dir())
 check(reopened.selected_draft(id, true) == second_copy and reopened.selected_draft(id, false) == classic_copy and reopened.python_drafts.get(id) == main_source and reopened.python_drafts.get(first_copy) == first_source and reopened.python_drafts.get(second_copy) == second_source and reopened.drafts.get(classic_copy) == classic_source, "Both copy families and their selected drafts reload from disk")
 popup.progress.folder = original_folder

func check_comparison_source(popup) -> void:
 popup.compare_drafts_button.pressed.emit()
 var view: OptionButton = popup.comparison_view
 var slider: HSlider = popup.comparison_slider
 var current: CodeEdit = popup.comparison_current_code
 var other: CodeEdit = popup.comparison_other_code
 var edit_current := current.get_parent().get_child(1) as Button
 var edit_other := other.get_parent().get_child(1) as Button
 view.select(1)
 view.item_selected.emit(1)
 check(not popup.python_mode and view.item_count == 3 and view.get_item_text(1) == "Source" and view.get_item_text(2) == "Results" and current.is_visible_in_tree() and current.text == "wait\n" and current.get_executing_lines() == PackedInt32Array([0]), "Classic comparisons offer a source view with the selected command marked")
 var live_turn: int = popup.garden.turn
 var live_cell: Vector2i = popup.garden.cell
 edit_other.grab_focus()
 press_key(KEY_ENTER)
 check(live_turn > 0 and popup.garden.turn == live_turn and popup.garden.cell == live_cell and popup.draft_choice.selected == 0 and popup.source.get_caret_line() == 0 and popup.source.has_focus() and not popup.comparison_panel.visible, "Editing the other Classic draft returns to its line without changing the living nursery")

 popup.language.item_selected.emit(0)
 popup.chooser.item_selected.emit(0)
 var current_source := "# Short route\nwait()\n"
 var other_source := "# Longer route\n# Fill first\nfill()\nwait()\nhop(east)\nfill()\n"
 var saved: Dictionary = popup.progress.create_draft_copy("first_bloom", other_source, true)
 var invalid: Dictionary = popup.progress.create_draft_copy("first_bloom", "# Typo\nfill(east)\n", true)
 popup._refresh_draft_choice()
 popup.source.text = current_source
 popup.source.set_caret_line(0)
 popup.source.set_caret_column(4)
 popup.compare_drafts_button.pressed.emit()
 check(not edit_current.is_visible_in_tree() and not edit_other.is_visible_in_tree(), "Edit buttons stay with the Source view")
 select_comparison_copy(popup.comparison_choice, saved.key)
 view.select(3)
 view.item_selected.emit(3)
 check(saved.error == OK and view.get_item_text(3) == "Source" and not current.editable and not other.editable and current.text == current_source and other.text == other_source and slider.value == 3 and current.get_executing_lines() == PackedInt32Array([1]) and other.get_executing_lines() == PackedInt32Array([5]), "Both source panes are read-only and mark the short route's last action and the other route's blocked line")
 slider.value = 0
 check(current.get_executing_lines().is_empty() and other.get_executing_lines().is_empty(), "Rewinding unmarks both sources before the first action")
 slider.grab_focus()
 press_key(KEY_RIGHT)
 check(slider.value == 1 and current.get_executing_lines() == PackedInt32Array([1]) and other.get_executing_lines() == PackedInt32Array([2]), "Keyboard stepping marks the two drafts' own source lines at the shared action")
 press_key(KEY_PAGEDOWN)
 check(slider.value == 2 and current.get_executing_lines() == PackedInt32Array([1]) and other.get_executing_lines() == PackedInt32Array([3]), "Difference navigation in Source follows different board actions")

 select_comparison_copy(popup.comparison_choice, invalid.key)
 check(invalid.error == OK and view.selected == 3 and other.text == "# Typo\nfill(east)\n" and other.get_executing_lines() == PackedInt32Array([1]) and "Check the arguments for fill()" in popup.comparison_other.text, "A compile failure displays the failing source line in its own pane")
 press_key(KEY_ESCAPE)
 check(not popup.comparison_panel.visible and current.text.is_empty() and other.text.is_empty() and popup.source.has_focus() and popup.source.text == current_source and popup.source.get_caret_column() == 4 and popup.garden.turn == 0, "Closing Source keeps the unsaved editor text, cursor, and live board")

 var stored: Variant = popup.progress.python_drafts.get("first_bloom")
 popup.source.select(0, 0, 0, 3)
 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(popup.comparison_choice, saved.key)
 view.select(3)
 view.item_selected.emit(3)
 current.set_caret_column(2)
 edit_current.grab_focus()
 press_key(KEY_ENTER)
 check(edit_current.text == "Edit current draft" and not popup.comparison_panel.visible and popup.draft_choice.selected == 0 and popup.source.has_focus() and popup.source.get_caret_line() == 1 and popup.source.get_caret_column() == 2 and not popup.source.has_selection() and popup.source.text == current_source and popup.progress.python_drafts.get("first_bloom") == stored, "Editing the current draft jumps to the preview cursor and keeps unsaved edits")

 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(popup.comparison_choice, saved.key)
 view.select(3)
 view.item_selected.emit(3)
 edit_other.pressed.emit()
 check(edit_other.text == "Edit other draft" and not popup.comparison_panel.visible and popup.progress.selected_draft("first_bloom", true) == saved.key and popup.source.text == other_source and popup.source.has_focus() and popup.source.get_caret_line() == 5 and popup.progress.python_drafts.get("first_bloom") == current_source, "Editing the other draft saves the current edits and opens the blocked line")

 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(popup.comparison_choice, invalid.key)
 view.select(3)
 view.item_selected.emit(3)
 edit_other.pressed.emit()
 check(popup.progress.selected_draft("first_bloom", true) == invalid.key and popup.source.editable and popup.source.get_caret_line() == 1 and popup.garden.turn == 0, "A compile error can be opened at its editable source line")
 var corrected := "# Typo fixed\nfill()\n"
 popup.source.text = corrected
 popup.draft_choice.item_selected.emit(0)
 check(popup.progress.python_drafts.get(invalid.key) == corrected and popup.progress.python_drafts.get(saved.key) == other_source and popup.source.text == current_source, "Edits from a comparison are saved to the selected copy")

func check_comparison_resume(popup) -> void:
 var id: String = Program.WILLOW_NURSERY.id
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.WILLOW_NURSERY))
 popup.draft_choice.item_selected.emit(0)
 await finish_by_steps(popup, "fill()\nwait()\n")
 var other: Dictionary = popup.progress.create_draft_copy(id, "wait()\nhop(east)\nwait()\nhop(east)\n", true)
 var spare: Dictionary = popup.progress.create_draft_copy(id, "# Spare\nwait()\nwait()\n", true)
 popup._refresh_draft_choice()
 popup.source.text = "wait()\nwait()\nwait()\nwait()\n"
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var view: OptionButton = popup.comparison_view
 var slider: HSlider = popup.comparison_slider
 var current: CodeEdit = popup.comparison_current_code
 var alternate: CodeEdit = popup.comparison_other_code
 var edit_current := current.get_parent().get_child(1) as Button
 var edit_other := alternate.get_parent().get_child(1) as Button
 select_comparison_copy(choice, other.key)
 view.select(3)
 view.item_selected.emit(3)
 slider.value = 3
 edit_current.pressed.emit()
 var revised_main := "hop(east)\nwait()\n"
 popup.source.text = revised_main
 popup.compare_drafts_button.pressed.emit()
 check(other.error == OK and spare.error == OK and view.selected == 3 and slider.value == 3 and choice.get_item_metadata(choice.selected) == other.key and current.text == revised_main and "Column 1" in popup.comparison_current.text and "Finished · 2 / 2 actions" in popup.comparison_current.text and popup.garden.turn == 2, "Editing the current draft restores the comparison and previews the revised code")

 edit_other.pressed.emit()
 popup.source.text = "wait()\n"
 popup.compare_drafts_button.pressed.emit()
 check(popup.progress.selected_draft(id, true) == other.key and choice.get_item_metadata(choice.selected) == id and view.selected == 3 and slider.max_value == 2 and slider.value == 2 and current.text == "wait()\n" and alternate.text == revised_main, "Editing the other draft swaps the panes and clamps the old action to the shorter previews")

 slider.value = 0
 select_comparison_copy(choice, spare.key)
 check(slider.value == 2 and view.selected == 3 and alternate.text.begins_with("# Spare"), "Choosing a different comparison draft still opens at the end in the current view")
 slider.value = 0
 popup.language.item_selected.emit(1)
 popup.compare_drafts_button.pressed.emit()
 view.select(0)
 view.item_selected.emit(0)
 popup.language.item_selected.emit(0)
 popup.compare_drafts_button.pressed.emit()
 check(popup.python_mode and view.selected == 3 and slider.value == 0 and choice.get_item_metadata(choice.selected) == spare.key and popup.progress.selected_draft(id, true) == other.key, "The Python comparison remembers its partner, view, and action zero across a language switch")

 press_key(KEY_ESCAPE)
 await finish_by_steps(popup, "hop(east)\n")
 popup.source.text = "wait()\n"
 popup.compare_drafts_button.pressed.emit()
 check(slider.value == 0 and view.selected == 3 and choice.get_item_metadata(choice.selected) == spare.key and popup.garden.turn == 3 and "Row 1 · Column 1" in popup.comparison_current.text and "Row 1 · Column 1" in popup.comparison_other.text, "A restored comparison uses the nursery's new starting position")

func check_comparison_starting_board(popup) -> void:
 var id: String = Program.OPEN_NURSERY.id
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.OPEN_NURSERY))
 popup.draft_choice.item_selected.emit(0)
 popup.nursery_target.value = 2
 await finish_by_steps(popup, "fill()\nhop(north)\nplant(east)\nwater(east)\nwait()\n")
 var own_source := "gather(east)\n"
 var other: Dictionary = popup.progress.create_draft_copy(id, "wait()\ngather(east)\n", true)
 popup._refresh_draft_choice()
 popup.source.text = own_source
 var live_tile: Node = popup.world.garden_root.get_child(0)
 var balance: int = popup.progress.nursery_balance()
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var start: OptionButton = popup.comparison_start
 var view: OptionButton = popup.comparison_view
 var slider: HSlider = popup.comparison_slider
 select_comparison_copy(choice, other.key)
 check(other.error == OK and start.is_visible_in_tree() and start.selected == 0 and slider.value == 2 and popup.comparison_current_route.initial.turn == 5 and popup.comparison_other_route.initial.tank == 5 and "Harvested 1" in popup.comparison_current.text and "Harvested 1" in popup.comparison_other.text, "Live nursery starts both drafts at the ripe bed with the current tank")

 view.select(3)
 view.item_selected.emit(3)
 start.select(1)
 start.item_selected.emit(1)
 var left = popup.comparison_current_route.initial
 var right = popup.comparison_other_route.initial
 check(view.selected == 3 and slider.max_value == 1 and slider.value == 1 and left.turn == 0 and right.turn == 0 and left.cell == Vector2i(0, 1) and right.cell == left.cell and left.tank == 0 and right.tank == 0 and left.plant_status(Vector2i(1, 0)) == Program.EMPTY_BED and right.plant_status(Vector2i(1, 0)) == Program.EMPTY_BED and "Blocked" in popup.comparison_current.text and "Blocked" in popup.comparison_other.text, "Fresh nursery resets both preview boards and clamps the action to the shorter trace")
 check(left.water_capacity == 6 and right.water_capacity == 6 and left.reach_tool and right.reach_tool and left.harvest_hook and right.harvest_hook and left.harvest_target == 2 and right.harvest_target == 2 and popup.garden.turn == 5 and popup.garden.tank == 5 and popup.garden.cell == Vector2i(0, 0) and popup.garden.plant_status(Vector2i(1, 0)) == "Ripe" and popup.progress.nursery_balance() == balance and popup.world.garden_root.get_child(0) == live_tile and popup.source.text == own_source, "Fresh previews retain the nursery tools and target and leave the live nursery untouched")

 press_key(KEY_ESCAPE)
 popup.compare_drafts_button.pressed.emit()
 check(start.selected == 1 and view.selected == 3 and slider.value == 1 and choice.get_item_metadata(choice.selected) == other.key and popup.comparison_other_route.initial.turn == 0, "Reopening remembers the fresh starting board with the same partner, view, and action")
 start.select(0)
 start.item_selected.emit(0)
 check(slider.max_value == 2 and slider.value == 1 and popup.comparison_current_route.initial.turn == 5 and popup.comparison_other_route.initial.turn == 5 and "Harvested 1" in popup.comparison_current.text and "Harvested 0" in popup.comparison_other.text, "Returning to the live nursery recalculates both forecasts at the current action")

 popup.language.item_selected.emit(1)
 var classic: Dictionary = popup.progress.create_draft_copy(id, "wait\nwait\n", false)
 popup._refresh_draft_choice()
 popup.source.text = "wait\n"
 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(choice, classic.key)
 start.select(1)
 start.item_selected.emit(1)
 check(classic.error == OK and not popup.python_mode and start.is_visible_in_tree() and popup.comparison_current_route.initial.turn == 0 and popup.comparison_other_route.actions.size() == 2 and popup.garden.turn == 5, "Classic drafts can also compare from fresh nursery previews")

func check_compare_personal_best(popup) -> void:
 var id: String = Program.OPEN_NURSERY.id
 popup.language.item_selected.emit(0)
 popup.draft_choice.item_selected.emit(0)
 popup.nursery_target.value = 3
 popup.source.text = "wait()\n"
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var view: OptionButton = popup.comparison_view
 var start: OptionButton = popup.comparison_start
 var slider: HSlider = popup.comparison_slider
 var edit: Button = popup.comparison_other_edit
 var draft_count: int = popup.draft_choice.item_count
 check(popup.comparison_panel.visible and choice.item_count == draft_count - 1, "A different nursery target leaves the personal best out of the choices")
 press_key(KEY_ESCAPE)

 popup.nursery_target.value = 1
 var saved: Dictionary = popup.progress.nursery_record(id, popup.garden)
 var turn: int = popup.garden.turn
 var balance: int = popup.progress.nursery_balance()
 var candidate := "# Candidate\nwait()\n"
 popup.source.text = candidate
 popup.compare_drafts_button.pressed.emit()
 start.select(0)
 start.item_selected.emit(0)
 select_comparison_copy(choice, "<personal-best>")
 check(choice.get_item_text(choice.selected) == "Personal best" and start.selected == 1 and slider.max_value == 6 and popup.comparison_current_route.initial.turn == 0 and popup.comparison_other_route.initial.turn == 0 and popup.comparison_other_code.text == saved.source and popup.garden.turn == turn and popup.draft_choice.item_count == draft_count, "Selecting the personal best compares the recorded source from a shared fresh board without creating a copy")
 start.select(0)
 start.item_selected.emit(0)
 check(start.selected == 0 and popup.comparison_current_route.initial.turn == turn and popup.comparison_other_route.initial.turn == turn and "Blocked" in popup.comparison_other.text, "The live nursery remains available when comparing against the best")

 start.select(1)
 start.item_selected.emit(1)
 slider.value = 6
 view.select(3)
 view.item_selected.emit(3)
 edit.pressed.emit()
 var copy_key: String = popup.progress.selected_draft(id, true)
 check(edit.text == "Edit a copy" and not popup.comparison_panel.visible and popup.draft_choice.item_count == draft_count + 1 and popup.source.text == saved.source and popup.source.get_caret_line() == 5 and popup.progress.python_drafts.get(id) == candidate and popup.progress.nursery_record(id, popup.garden) == saved and popup.progress.nursery_balance() == balance, "Editing the best opens a separate copy at the preview line and preserves the record")
 popup.compare_drafts_button.pressed.emit()
 check(copy_key != id and choice.get_item_text(choice.selected) == "Personal best" and start.selected == 1 and view.selected == 3 and slider.value == 6 and popup.progress.nursery_record(id, popup.garden) == saved, "Returning from the editable copy remembers the personal best and preview position")

func check_extended_comparison(popup) -> void:
 var id: String = Program.OPEN_NURSERY.id
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.OPEN_NURSERY))
 popup.draft_choice.item_selected.emit(0)
 popup.nursery_target.value = 2
 await finish_by_steps(popup, "fill()\n")
 var saved: Dictionary = popup.progress.nursery_record(id, popup.garden)
 var balance: int = popup.progress.nursery_balance()
 var ongoing: Dictionary = popup.progress.create_draft_copy(id, "while True:\n    wait()\n", true)
 popup._refresh_draft_choice()
 var candidate: String = saved.source.replace("260", "258").replace("fill()\n", "print('After warm-up')\nfill()\n")
 popup.source.text = candidate
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var view: OptionButton = popup.comparison_view
 var slider: HSlider = popup.comparison_slider
 var extend: Button = popup.comparison_extend_button
 select_comparison_copy(choice, "<personal-best>")
 check(ongoing.error == OK and saved.score.x == 270 and extend.is_visible_in_tree() and slider.value == Program.MAX_STEPS and popup.comparison_current_route.limited and popup.comparison_other_route.limited, "Long draft and best comparisons start at the standard preview limit")
 check(popup.comparison_current_goal.text == "Preview limit" and popup.comparison_other_goal.text == "Preview limit" and popup.comparison_goal_delta.text == "—", "A truncated preview reports that the target is still outside the visible results")

 view.select(2)
 view.item_selected.emit(2)
 extend.grab_focus()
 press_key(KEY_ENTER)
 check(slider.has_focus() and slider.value == Program.MAX_STEPS and slider.max_value == 270 and view.selected == 2 and not extend.visible and popup.comparison_current_route.actions.size() == 268 and popup.comparison_current_route.preview.run_harvest_count() == 2 and popup.comparison_other_route.preview.run_harvest_count() == 2, "Extending from the keyboard completes both traces and keeps the selected action and view")
 check(popup.comparison_goal_actions == Vector2i(268, 270) and popup.comparison_goal_delta.text == "+2", "Extending reveals when each long draft first reaches the harvest target")

 slider.value = 258
 var printed: bool = "After warm-up" in popup.comparison_current_details.get_parsed_text()
 slider.value = 257
 check(printed and popup.comparison_current_details.get_parsed_text() == "No print output", "The extended timeline shows new output only after its action")
 slider.value = 258
 press_key(KEY_ESCAPE)
 popup.compare_drafts_button.pressed.emit()
 check(view.selected == 2 and slider.value == 258 and slider.max_value == 270 and choice.get_item_text(choice.selected) == "Personal best" and popup.comparison_limit == 512, "Reopening remembers the extended budget and selected step")

 select_comparison_copy(choice, ongoing.key)
 for expansion in 3:
  extend.pressed.emit()
 extend.pressed.emit()
 check(slider.max_value == Program.MAX_COMPUTATION_STEPS and popup.comparison_limit == Program.MAX_COMPUTATION_STEPS and popup.comparison_other_route.limited and not extend.visible, "Continuously running drafts can extend up to the comparison maximum")
 check(popup.garden.turn == 1 and popup.garden.tank == 6 and popup.progress.nursery_balance() == balance and popup.progress.nursery_record(id, popup.garden) == saved and popup.source.text == candidate, "Extended comparisons preserve the live nursery, best, and editable draft")

func check_comparison_results(popup) -> void:
 var id: String = Program.OPEN_NURSERY.id
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.OPEN_NURSERY))
 popup.draft_choice.item_selected.emit(0)
 popup.nursery_target.value = 3
 await finish_by_steps(popup, "fill()\nhop(north)\nplant(east)\nwater(east)\nwait()\ngather(east)\nplant(east)\nwater(east)\nwait()\n")
 var other: Dictionary = popup.progress.create_draft_copy(id, "wait()\ngather(east)\nplant(east)\nwater(east)\nwait()\ngather(east)\nhop(south)\nfill()\n", true)
 var invalid: Dictionary = popup.progress.create_draft_copy(id, "fill(east)\n", true)
 popup._refresh_draft_choice()
 var current := "gather(east)\n"
 popup.source.text = current
 var balance: int = popup.progress.nursery_balance()
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var start: OptionButton = popup.comparison_start
 var view: OptionButton = popup.comparison_view
 var slider: HSlider = popup.comparison_slider
 var values: Array[Label] = popup.comparison_result_values
 start.select(0)
 start.item_selected.emit(0)
 select_comparison_copy(choice, other.key)
 view.select(4)
 view.item_selected.emit(4)
 check(other.error == OK and view.get_item_text(4) == "Results" and popup.comparison_results.is_visible_in_tree() and slider.value == 8 and values.map(func(label): return label.text) == ["1", "2", "+1", "1", "8", "+7", "0", "1", "+1", "0", "1", "+1"], "Results aligns both drafts' totals and signs the right-minus-left differences")
 check(popup.comparison_goal_label.text == "First reaches 3 lilies" and popup.comparison_current_goal.text == "Not reached" and popup.comparison_other_goal.text == "Not reached" and popup.comparison_goal_delta.text == "—", "Completed previews can finish below their harvest target")
 slider.value = 0
 check(values.map(func(label): return label.text) == ["0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"] and popup.garden.harvested == 1 and popup.garden.turn == 9, "Results counts only this preview's work on a nursery already harvested")
 popup.comparison_difference_button.pressed.emit()
 check(slider.has_focus() and slider.value == 1 and values[2].text == "-1" and values[5].text == "0" and values[2].modulate == Color("#e8c879"), "Results navigation jumps to the first differing total")
 select_comparison_copy(choice, invalid.key)
 check(invalid.error == OK and "Check the arguments for fill()" in popup.comparison_other.text and values.map(func(label): return label.text) == ["1", "—", "—", "1", "—", "—", "0", "—", "—", "0", "—", "—"] and not popup.comparison_difference_button.visible, "Results preserves the valid side when the other draft cannot compile")
 press_key(KEY_ESCAPE)
 check(not popup.comparison_panel.visible and popup.garden.turn == 9 and popup.garden.tank == 4 and popup.garden.plant_status(Vector2i(1, 0)) == "Ripe" and popup.progress.nursery_balance() == balance and popup.source.text == current, "Results preserves the live nursery and editable program")

 popup.nursery_target.value = 1
 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(choice, other.key)
 view.select(4)
 view.item_selected.emit(4)
 var current_goal: Button = popup.comparison_current_goal
 var other_goal: Button = popup.comparison_other_goal
 check(popup.comparison_goal_label.text == "First reaches 1 lily" and current_goal.text == "Action 1" and other_goal.text == "Action 2" and popup.comparison_goal_delta.text == "+1", "Target timing uses the first qualifying action even when a draft keeps working")
 other_goal.grab_focus()
 press_key(KEY_ENTER)
 check(slider.has_focus() and slider.value == 2 and values[0].text == "1" and values[1].text == "1", "The other draft's target button jumps the shared slider with the keyboard")
 current_goal.pressed.emit()
 var jumped: bool = slider.value == 1 and values[1].text == "0"
 select_comparison_copy(choice, invalid.key)
 check(jumped and not current_goal.disabled and other_goal.disabled and other_goal.text == "—" and popup.comparison_goal_delta.text == "—", "The current draft's milestone remains available when the other draft fails to compile")

 popup.chooser.item_selected.emit(0)
 popup.draft_choice.item_selected.emit(0)
 var lesson := "fill()\nhop(east)\nwater()\nwait()\ngather()\nhop(east)\nwater()\nwait()\ngather()\n"
 var lesson_copy: Dictionary = popup.progress.create_draft_copy("first_bloom", "wait()\n" + lesson, true)
 popup._refresh_draft_choice()
 popup.source.text = lesson
 popup.compare_drafts_button.pressed.emit()
 select_comparison_copy(choice, lesson_copy.key)
 view.select(4)
 view.item_selected.emit(4)
 check(lesson_copy.error == OK and popup.comparison_goal_label.text == "First reaches 2 lilies" and current_goal.text == "Action 9" and other_goal.text == "Action 10" and popup.comparison_goal_delta.text == "+1" and popup.garden.turn == 0, "A lesson's milestone requires harvesting all of its lilies")

func check_comparison_totals_at_target(popup) -> void:
 var id: String = Program.OPEN_NURSERY.id
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.OPEN_NURSERY))
 popup.draft_choice.item_selected.emit(0)
 popup.nursery_target.value = 1
 await finish_by_steps(popup, "fill()\nhop(north)\nplant(east)\nwater(east)\nwait()\n")
 var other: Dictionary = popup.progress.create_draft_copy(id, "hop(south)\nfill()\nhop(north)\nhop(east)\nplant(east)\nwater(east)\ngather()\nwait()\ngather(east)\n", true)
 var short: Dictionary = popup.progress.create_draft_copy(id, "wait()\n", true)
 popup._refresh_draft_choice()
 var current := "gather(east)\nhop(south)\nfill()\n"
 popup.source.text = current
 var balance: int = popup.progress.nursery_balance()
 popup.compare_drafts_button.pressed.emit()
 var choice: OptionButton = popup.comparison_choice
 var start: OptionButton = popup.comparison_start
 var view: OptionButton = popup.comparison_view
 var timing: OptionButton = popup.comparison_totals_choice
 var slider: HSlider = popup.comparison_slider
 var values: Array[Label] = popup.comparison_result_values
 start.select(0)
 start.item_selected.emit(0)
 select_comparison_copy(choice, other.key)
 view.select(4)
 view.item_selected.emit(4)
 check(other.error == OK and short.error == OK and timing.is_visible_in_tree() and timing.get_item_text(timing.selected) == "Selected action" and slider.value == 9 and values.map(func(label): return label.text) == ["1", "2", "+1", "3", "9", "+6", "0", "1", "+1", "1", "1", "0"], "Selected action still includes all work through the chosen step")

 timing.select(1)
 timing.item_selected.emit(1)
 var at_target := ["1", "1", "0", "1", "7", "+6", "0", "1", "+1", "0", "1", "+1"]
 check(slider.value == 9 and values.map(func(label): return label.text) == at_target and not popup.comparison_difference_button.visible, "First target action compares equal harvest goals and excludes work done after each milestone")
 popup.comparison_other_goal.pressed.emit()
 var jumped: bool = slider.value == 7 and slider.has_focus()
 slider.value = 0
 check(jumped and values.map(func(label): return label.text) == at_target, "Both milestone totals stay pinned while the shared slider jumps or rewinds")
 press_key(KEY_ESCAPE)
 popup.compare_drafts_button.pressed.emit()
 check(view.selected == 4 and timing.selected == 1 and slider.value == 0 and values.map(func(label): return label.text) == at_target, "Reopening restores the target totals and slider independently")

 select_comparison_copy(choice, short.key)
 check(timing.selected == 1 and popup.comparison_other_goal.text == "Not reached" and values.map(func(label): return label.text) == ["1", "—", "—", "1", "—", "—", "0", "—", "—", "0", "—", "—"], "Target totals remain available for the draft that reaches its goal")
 timing.select(0)
 timing.item_selected.emit(0)
 slider.value = 1
 check(popup.comparison_difference_button.visible and values.map(func(label): return label.text) == ["1", "0", "-1", "1", "1", "0", "0", "0", "0", "0", "0", "0"] and popup.garden.turn == 5 and popup.garden.tank == 5 and popup.garden.plant_status(Vector2i(1, 0)) == "Ripe" and popup.progress.nursery_balance() == balance and popup.source.text == current, "Switching back restores shared step totals without changing the live nursery")

func check_alder_crossing(popup) -> void:
 press_key(KEY_ESCAPE)
 var ring := Program.GARDENS.find(Program.STONE_RING_NURSERY)
 var alder := Program.GARDENS.find(Program.ALDER_CROSSING)
 popup.chooser.item_selected.emit(ring)
 popup.chooser.item_selected.emit(alder)
 check(popup.puzzle == ring and popup.chooser.is_item_disabled(alder) and "128 nursery lilies" in popup.chooser.get_item_text(alder), "Alder Crossing stays locked until its purchase")
 var needed := maxi(1, Progress.ALDER_CROSSING_COST - popup.progress.nursery_balance())
 var saved: Error = popup.progress.record_nursery_harvest(needed)
 popup._draw()
 var balance: int = popup.progress.nursery_balance() - Progress.ALDER_CROSSING_COST
 var buy: Button = popup.nursery_upgrade_button
 var offer := buy.visible and not buy.disabled and buy.text == "Unlock Alder Crossing · 128 lilies"
 buy.pressed.emit()
 var starter: String = Program.ALDER_CROSSING.python_draft
 check(saved == OK and offer and popup.puzzle == alder and not popup.chooser.is_item_disabled(alder) and popup.source.text == starter and popup.garden.cell == Vector2i(3, 3) and popup.garden.water_capacity == 6 and popup.garden.reach_tool and popup.garden.harvest_hook and popup.speed_choice.visible and popup.garden.plants.size() == 7 and popup.world.garden_root.get_child_count() > 25 and popup.progress.nursery_balance() == balance, "Buying Alder Crossing opens seven beds and both banks with its starter and prior tools")

 popup.check_button.pressed.emit()
 var south: Program = popup.checked_route.get("preview")
 check(south != null and south.run_harvest_count() == 5 and south.run_action_count() == 21 and south.run_water_used == 4 and south.run_fills == 1 and south.cell == Vector2i(0, 1) and popup.garden.turn == 0, "Check predicts the starter will harvest the south bank on four doses and reach the west spring in 21 actions")
 await finish_by_steps(popup, starter)
 check(popup.garden.harvested == 5 and popup.garden.cell == Vector2i(0, 1) and popup.garden.tank == 2 and popup.garden.turn == 21 and popup.progress.nursery_balance() == balance + 5, "The Python starter harvests the south bank and leaves two doses before the next fill")
 popup.check_button.pressed.emit()
 var north: Program = popup.checked_route.get("preview")
 var northern_forecast := north != null and north.run_harvest_count() == 8 and north.run_action_count() == 25 and north.run_water_used == 6 and north.run_fills == 1 and north.cell == Vector2i(3, 3)
 await finish_by_steps(popup, starter)
 check(northern_forecast and popup.garden.harvested == 13 and popup.garden.cell == Vector2i(3, 3) and popup.garden.tank == 0 and popup.garden.turn == 46 and popup.progress.nursery_balance() == balance + 13, "A rerun from the west spring harvests eight more on six doses and returns south in 25 actions")

 popup.language.item_selected.emit(1)
 popup.nursery_target.value = 13
 popup._reset()
 var classic_loop: String = Program.ALDER_CROSSING.draft.replace("\nif spring\n", "\nwhile spring and harvest_count < harvest_target\n")
 popup.source.text = classic_loop
 popup.check_button.pressed.emit()
 var circuit: Program = popup.checked_route.get("preview")
 check(circuit != null and circuit.run_harvest_count() == 13 and circuit.run_action_count() == 46 and circuit.run_water_used == 10 and circuit.run_fills == 2 and circuit.cell == Vector2i(3, 3) and popup.garden.turn == 0 and popup.progress.nursery_balance() == balance + 13, "The Classic starter loops to the 13-lily target in two fills without changing the live nursery during Check")
 await finish_by_steps(popup, classic_loop)
 var id: String = Program.ALDER_CROSSING.id
 check(popup.garden.harvested == 13 and popup.progress.nursery_best(id, popup.garden) == Vector3i(46, 10, 2) and popup.progress.nursery_record(id, popup.garden).get("source") == classic_loop and popup.progress.nursery_balance() == balance + 26, "A two-bank run saves its target record and source")
 popup.compare_drafts_button.pressed.emit()
 popup.comparison_view.select(2)
 popup.comparison_view.item_selected.emit(2)
 popup.comparison_totals_choice.select(1)
 popup.comparison_totals_choice.item_selected.emit(1)
 check(popup.comparison_panel.visible and popup.comparison_goal_actions == Vector2i(42, 42) and popup.comparison_goal_delta.text == "0" and popup.garden.turn == 46 and popup.progress.nursery_balance() == balance + 26, "Alder Crossing comparison finds the target four steps before either route returns to the spring")

func check_run_to_cursor(popup) -> void:
 press_key(KEY_ESCAPE)
 popup.chooser.item_selected.emit(Program.GARDENS.find(Program.OPEN_NURSERY))
 popup.language.item_selected.emit(0)
 popup._reset()
 popup.source.text = """fill()
print("Tank ready")
for _ in range(2):
    wait()
    wait()
wait()
"""
 popup.source.grab_focus()
 popup.source.set_caret_line(1)
 press_key(KEY_F10, true)
 check(not popup.running and popup.steps.is_empty() and popup.garden.turn == 0 and "Line 2 has no board command" in popup.status.text, "Run to cursor leaves the board alone when the cursor is on a print call")

 popup.source.set_caret_line(0)
 press_key(KEY_F9)
 popup.source.set_caret_line(3)
 press_key(KEY_F10, true)
 popup._process(.25)
 check(not popup.running and popup.garden.turn == 0 and "Breakpoint · line 1" in popup.status.text and popup.run_to_line == 3, "An earlier permanent breakpoint pauses first and keeps the cursor destination")

 press_key(KEY_ENTER, true)
 popup._process(.25)
 popup._process(.25)
 check(not popup.running and popup.garden.turn == 1 and "Cursor · line 4 · 1 action" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([3]) and popup.source.get_breakpointed_lines() == PackedInt32Array([0]) and "Tank ready" in popup.output_text.text, "Run to cursor stops before the Python command with its live output and leaves the breakpoint list intact")
 press_key(KEY_F10)
 check(not popup.running and popup.garden.turn == 2 and popup.run_to_line == -1, "F10 steps the command at the temporary stop")
 press_key(KEY_ENTER, true)
 for action in 8:
  popup._process(.25)
 check(not popup.running and popup.steps.is_empty() and popup.garden.turn == 6 and popup.source.get_breakpointed_lines() == PackedInt32Array([0]), "Resume runs the next loop iteration past the one-time stop")

 popup.language.item_selected.emit(1)
 popup._reset()
 popup.source.text = "fill\nrepeat 2\n  wait\nend\nwait\n"
 press_key(KEY_F10)
 popup.source.set_caret_line(2)
 press_key(KEY_F10, true)
 popup._process(.25)
 check(not popup.running and popup.garden.turn == 1 and "Cursor · line 3" in popup.status.text and popup.source.get_breakpointed_lines().is_empty(), "Run to cursor works on an already paused Classic program")
 popup.source.set_caret_line(4)
 press_key(KEY_F10, true)
 press_key(KEY_ENTER, true)
 var paused: bool = not popup.running and popup.run_to_line == 4 and popup.garden.turn == 1
 popup.stop_button.pressed.emit()
 press_key(KEY_ENTER, true)
 for action in 8:
  popup._process(.25)
 check(paused and popup.run_to_line == -1 and popup.steps.is_empty() and popup.garden.turn == 5, "Stop clears a pending destination before a later regular run")

 popup.language.item_selected.emit(0)
 popup._reset()
 popup.source.text = "fill()\nif False:\n    wait()\nwait()\n"
 popup.source.set_caret_line(2)
 press_key(KEY_F10, true)
 for action in 4:
  popup._process(.25)
 check(not popup.running and popup.steps.is_empty() and popup.garden.turn == 2 and popup.run_to_line == -1 and "Program ended" in popup.status.text, "A skipped destination allows normal completion and leaves no temporary state")

func check_step_out(popup) -> void:
 popup._reset()
 popup.source.grab_focus()
 popup.variables_button.set_pressed_no_signal(true)
 popup._refresh_variables()
 var route := """def sample(value: int):
    wait()
    wait()
    return value + 1

def relay():
    first = sample(4)
    second = sample(4)
    wait()
    return first + second

total = relay()
wait()
"""
 popup.source.text = route
 press_key(KEY_F11, false, true)
 check(popup.steps.is_empty() and popup.garden.turn == 0 and "Pause inside a Python function" in popup.status.text, "Step out requires a paused function and leaves an idle board alone")
 popup.source.set_caret_line(1)
 press_key(KEY_F10, true)
 popup._process(.25)
 popup.source.set_caret_line(2)
 press_key(KEY_F9)
 press_key(KEY_F11, false, true)
 popup._process(.25)
 popup._process(.25)
 check(not popup.running and popup.garden.turn == 1 and "Breakpoint · line 3" in popup.status.text and popup.step_out_frame.get("function") == "sample", "A breakpoint inside the call pauses the run and keeps the Step out request")

 press_key(KEY_ENTER, true)
 popup._process(.25)
 popup._process(.25)
 check(not popup.running and popup.garden.turn == 2 and "Step out · line 2" in popup.status.text and popup.source.get_executing_lines() == PackedInt32Array([1]) and popup.variables_text.text == "relay() · first = 5\nsample() · value = 4", "Step out pauses before the next identical call advances and exposes the first return")
 popup.source.set_caret_line(2)
 press_key(KEY_F9)
 press_key(KEY_F11, false, true)
 for action in 3:
  popup._process(.25)
 check(not popup.running and popup.garden.turn == 4 and "Step out · line 9" in popup.status.text and popup.variables_text.text == "relay() · first = 5\nrelay() · second = 5", "Stepping out of the second call lands in the caller with both return values")
 press_key(KEY_F11, false, true)
 popup._process(.25)
 popup._process(.25)
 check(not popup.running and popup.garden.turn == 5 and "Step out · line 13" in popup.status.text and popup.garden.local_frames.is_empty() and popup.variables_text.text == "total = 10", "Stepping out of the outer call marks the next top-level command and displays the result")
 press_key(KEY_F11, false, true)
 check(not popup.running and popup.garden.turn == 5 and not popup.steps.is_empty() and "Pause inside a Python function" in popup.status.text, "Step out leaves a paused top-level command in place")
 press_key(KEY_F10)
 check(popup.steps.is_empty() and popup.garden.turn == 6 and popup.step_out_frame.is_empty(), "A normal step runs the command after the returned call")

 popup._reset()
 popup.source.set_caret_line(1)
 press_key(KEY_F10, true)
 popup._process(.25)
 popup.source.set_caret_line(2)
 press_key(KEY_F9)
 press_key(KEY_F11, false, true)
 popup._process(.25)
 popup._process(.25)
 press_key(KEY_F9)
 popup.source.set_caret_line(8)
 press_key(KEY_F10, true)
 for action in 4:
  popup._process(.25)
 check(not popup.running and popup.garden.turn == 4 and "Cursor · line 9" in popup.status.text and popup.step_out_frame.is_empty(), "Run to cursor can replace a pending Step out destination")

 popup._reset()
 popup.source.text = "def child():\n    wait()\ndef parent():\n    wait()\n    child()\n    wait()\nparent()\nwait()\n"
 popup.source.set_caret_line(3)
 press_key(KEY_F10, true)
 popup._process(.25)
 press_key(KEY_F11, false, true)
 for action in 4:
  popup._process(.25)
 check(not popup.running and popup.garden.turn == 3 and "Step out · line 8" in popup.status.text and popup.garden.local_frames.is_empty(), "Step out keeps running through a nested call until the selected parent itself returns")

 popup._reset()
 popup.source.text = "def finish():\n    wait()\n    wait()\nfinish()\n"
 press_key(KEY_F10)
 press_key(KEY_F11, false, true)
 popup._process(.25)
 check(popup.steps.is_empty() and popup.garden.turn == 2 and popup.step_out_frame.is_empty() and "Program ended" in popup.status.text, "Step out completes normally when the function ends the program")

 popup._reset()
 var at_limit := "def rest():\n    wait()\n" + "rest()\n".repeat(Program.MAX_STEPS)
 popup.source.text = at_limit
 popup.check_button.pressed.emit()
 var full_preview: bool = popup.checked_route.get("actions", []).size() == Program.MAX_STEPS and not popup.checked_route.get("limited", true)
 popup.source.text = at_limit + "rest()\n"
 popup.check_button.pressed.emit()
 check(full_preview and "beyond 256 instructions" in popup.status.text and popup.garden.turn == 0, "Call boundaries preserve the expansion limit for board-only Python functions")

func call_stack_labels(list: ItemList) -> String:
 var labels := PackedStringArray()
 for index in list.item_count:
  labels.append(list.get_item_text(index))
 return "\n".join(labels)

func check_call_stack(popup) -> void:
 popup._reset()
 popup.nursery_target.value = 2
 var route := """def tend(heading):
    plant(heading)
    water(heading)
    wait()
    gather(heading)
def bank():
    tend(north)
    hop(east)
    tend(north)
fill()
hop(east)
bank()
wait()
"""
 var bank_call := "bank() · called at line 12\nTop level"
 var first_call := "tend() · called at line 7\n" + bank_call
 var second_call := "tend() · called at line 9\n" + bank_call
 popup.source.text = route
 popup.check_button.pressed.emit()
 press_key(KEY_F7, false, true)
 var calls: ItemList = popup.call_stack_list
 check(calls.is_visible_in_tree() and popup.call_stack_button.button_pressed and popup.variables_title.text == "Check call stack" and call_stack_labels(calls) == "Top level" and not calls.is_item_selectable(0) and popup.source.has_focus(), "Shift+F7 shows the final Check call stack while keeping keyboard focus in the editor")
 popup.review_button.pressed.emit()
 var slider: HSlider = popup.review_slider
 var initial := call_stack_labels(calls)
 slider.value = 2
 check(initial == "Top level" and call_stack_labels(calls) == first_call and popup.garden.turn == 0, "Review shows nested calls even when both functions only perform board actions")
 slider.value = 6
 var between := call_stack_labels(calls)
 slider.value = 7
 check(between == bank_call and call_stack_labels(calls) == second_call, "Review distinguishes calls to the same function by the call site")
 slider.value = 12
 var ending := call_stack_labels(calls)
 slider.value = 2
 check(ending == "Top level" and call_stack_labels(calls) == first_call and slider.has_focus(), "Rewinding restores the selected call stack while keeping slider focus")
 press_key(KEY_F7)
 check(popup.variables_panel.visible and not popup.call_stack_button.button_pressed and popup.variables_title.text == "Check variables" and popup.variables_text.text == "No variables assigned" and slider.value == 2 and slider.has_focus(), "F7 switches back to values without moving the review position")
 popup.call_stack_button.set_pressed_no_signal(true)
 popup.call_stack_button.pressed.emit()
 check(popup.variables_title.text == "Check call stack" and call_stack_labels(calls) == first_call, "The inspector can switch views at the same review position")
 var review_mark: PackedInt32Array = popup.source.get_executing_lines()
 calls.item_activated.emit(1)
 check(popup.source.has_focus() and popup.source.get_caret_line() == 11 and popup.source.get_executing_lines() == review_mark and slider.value == 2 and popup.garden.turn == 0, "Activating the caller in Review opens its line and preserves the timeline and last action marker")

 popup.review_button.pressed.emit()
 popup.source.grab_focus()
 popup.source.set_caret_line(1)
 press_key(KEY_F10, true)
 for action in 3:
  popup._process(.25)
 check(not popup.running and popup.garden.turn == 2 and popup.variables_title.text == "Program call stack" and call_stack_labels(calls) == first_call, "A live pause shows the active function and its caller")
 press_key(KEY_F7, false, true)
 var innermost_focused := calls.has_focus() and calls.is_selected(0)
 press_key(KEY_DOWN)
 var caller_selected := calls.is_selected(1)
 press_key(KEY_ENTER)
 check(innermost_focused and caller_selected and popup.source.has_focus() and popup.source.get_caret_line() == 11 and not popup.running and popup.garden.turn == 2 and popup.source.get_executing_lines() == PackedInt32Array([1]), "Keyboard navigation opens the selected caller without moving the live execution point")
 calls.item_activated.emit(0)
 check(popup.source.get_caret_line() == 6 and popup.source.get_executing_lines() == PackedInt32Array([1]) and popup.source.text == route, "Opening the inner call site moves the caret and preserves the source and paused command")
 press_key(KEY_F11, false, true)
 for action in 5:
  popup._process(.25)
 check(not popup.running and popup.garden.turn == 6 and call_stack_labels(calls) == bank_call, "Step out removes the finished call from the inspector")

 await finish_by_steps(popup, route)
 var balance: int = popup.progress.nursery_balance()
 popup.best_button.pressed.emit()
 slider.value = 7
 check(popup.best_panel.visible and popup.best_source.text == route and popup.variables_title.text == "Best run call stack" and call_stack_labels(calls) == second_call and popup.garden.turn == 12 and popup.progress.nursery_balance() == balance, "Best program replays the saved call stack without changing the live nursery or balance")
 check(popup.frame_variables_panel.is_visible_in_tree() and popup.frame_variables_title.text == "tend() locals" and popup.frame_variables_text.text == "No variables assigned", "A saved replay can inspect a board-only function with no locals")
 var draft_line: int = popup.source.get_caret_line()
 var replay_mark: PackedInt32Array = popup.best_source.get_executing_lines()
 calls.item_activated.emit(0)
 check(popup.best_source.has_focus() and popup.best_source.get_caret_line() == 8 and not popup.best_source.editable and popup.best_source.get_executing_lines() == replay_mark and popup.source.get_caret_line() == draft_line and slider.value == 7, "A saved call site opens in the read-only replay and leaves the main draft and action marker alone")
 press_key(KEY_F7, false, true)
 var stack_focused := calls.has_focus()
 press_key(KEY_ESCAPE)
 check(stack_focused and popup.best_panel.visible and popup.best_source.has_focus() and slider.value == 7, "Esc returns focus from the call stack to the saved source without closing the replay")
 press_key(KEY_ESCAPE)
 popup._reset()
 popup.source.text = "def cross():\n    hop(west)\ncross()\n"
 popup.check_button.pressed.emit()
 popup.review_button.pressed.emit()
 check("Blocked" in popup.review_position.text and call_stack_labels(calls) == "cross() · called at line 3\nTop level" and popup.garden.turn == 0, "Review retains the call site when a command fails before the first action")

func check_frame_variables(popup) -> void:
 popup._reset()
 popup.variables_button.set_pressed_no_signal(false)
 var route := """shared = 9
def probe(count: int):
    shared = count
    wait()
    shared += 1
    wait()
def sweep():
    shared = 20
    probe(2)
    wait()
sweep()
wait()
"""
 popup.source.text = route
 popup.check_button.pressed.emit()
 press_key(KEY_F7, false, true)
 check(popup.variables_title.text == "Check call stack" and not popup.frame_variables_panel.is_visible_in_tree(), "A finished Check hides the locals pane at top level")
 popup.review_button.pressed.emit()
 var slider: HSlider = popup.review_slider
 var calls: ItemList = popup.call_stack_list
 check(popup.frame_variables_panel.is_visible_in_tree() and popup.frame_variables_title.text == "probe() locals" and popup.frame_variables_text.text == "count = 2\nshared = 2", "Review defaults to the innermost frame and shows its parameter and local value")

 press_key(KEY_F7, false, true)
 press_key(KEY_DOWN)
 check(calls.has_focus() and calls.is_selected(1) and popup.frame_variables_title.text == "sweep() locals" and popup.frame_variables_text.text == "shared = 20" and slider.value == 0, "Selecting a caller shows only that frame's values without advancing Review")
 slider.value = 1
 var still_selected := calls.is_selected(1)
 slider.value = 2
 var after_return := calls.is_selected(0)
 slider.value = 0
 check(still_selected and after_return and calls.is_selected(1) and popup.frame_variables_text.text == "shared = 20" and popup.garden.turn == 0, "The caller selection survives a nested return and rewind without changing the live board")
 press_key(KEY_UP)
 var before_update: String = popup.frame_variables_text.text
 slider.value = 1
 check(calls.is_selected(0) and before_update == "count = 2\nshared = 2" and popup.frame_variables_text.text == "count = 2\nshared = 3", "A selected frame's locals update even when the call stack stays the same")
 slider.value = 4
 check(not popup.frame_variables_panel.is_visible_in_tree() and call_stack_labels(calls) == "Top level", "Returning from the last call hides the locals pane")
 slider.value = 1
 press_key(KEY_F7)
 var all_values := "probe() · count = 2\nprobe() · shared = 3\nshared = 9\nsweep() · shared = 20"
 check(popup.variables_text.is_visible_in_tree() and popup.variables_text.text == all_values and slider.value == 1, "F7 still shows all scopes together after inspecting a single frame")

 popup.review_button.pressed.emit()
 popup.source.grab_focus()
 popup.source.set_caret_line(3)
 press_key(KEY_F10, true)
 popup._process(.25)
 press_key(KEY_F7, false, true)
 press_key(KEY_F10)
 check(not popup.running and popup.garden.turn == 1 and popup.variables_title.text == "Program call stack" and popup.frame_variables_text.text == "count = 2\nshared = 3", "Stepping the live program updates the selected function's locals")

func check_variable_changes(popup) -> void:
 popup._reset()
 popup.variables_button.set_pressed_no_signal(false)
 var route := """def check_bed():
    sample = 0
    wait()
    sample += 1
    wait()
ready = True
check_bed()
ready = 1
added = 4
wait()
"""
 var changed := "check_bed() · sample = 0 → 1"
 var returned := "added = unassigned → 4\ncheck_bed() · sample = 1 → out of scope\nready = True → 1"
 popup.source.text = route
 popup.check_button.pressed.emit()
 press_key(KEY_F7, true)
 check(popup.variables_panel.visible and popup.variable_changes_button.button_pressed and popup.variables_title.text == "Check changes" and popup.variables_text.text == "No variable changes" and popup.source.has_focus(), "Ctrl+F7 shows changes from the last Check action while keeping code focus")
 popup.review_button.pressed.emit()
 var slider: HSlider = popup.review_slider
 check(popup.variables_text.text == "No variable changes" and slider.value == 0, "The initial Review position has no preceding board action")
 slider.value = 1
 check(popup.variables_text.text == changed and popup.garden.turn == 0, "Review shows a local's old and new values for the selected action")
 slider.value = 2
 check(popup.variables_text.text == returned, "Review distinguishes an assignment, a function return, and a change from Boolean to integer")
 slider.value = 3
 var final: String = popup.variables_text.text
 slider.value = 1
 check(final == "No variable changes" and popup.variables_text.text == changed and slider.has_focus(), "Rewinding shows the same change as stepping forward to the action")
 press_key(KEY_F7)
 check(popup.variables_title.text == "Check variables" and popup.variables_text.text == "check_bed() · sample = 1\nready = True" and slider.value == 1 and slider.has_focus(), "F7 returns to current values without moving Review")
 press_key(KEY_F7, false, true)
 var was_stack: bool = popup.call_stack_list.is_visible_in_tree()
 popup.variable_changes_button.grab_focus()
 press_key(KEY_SPACE)
 check(was_stack and popup.variable_changes_button.button_pressed and not popup.call_stack_button.button_pressed and popup.variables_text.text == changed and slider.value == 1, "The Changes button switches from the stack at the same timeline position")

 popup.review_button.pressed.emit()
 popup.source.grab_focus()
 press_key(KEY_F10)
 var live_first: bool = popup.variables_title.text == "Program changes" and popup.variables_text.text == changed
 press_key(KEY_F10)
 check(live_first and popup.garden.turn == 2 and popup.variables_text.text == returned, "Stepping live shows the same assignment and scope changes as Review")

 popup._reset()
 popup.source.text = "reading = 0\nwait()\nreading = 1\nhop(west)\n"
 press_key(KEY_F10)
 press_key(KEY_F10)
 check(popup.garden.turn == 1 and "Line 4" in popup.status.text and popup.variables_text.text == "reading = 0 → 1", "A blocked command leaves the changes from the last successful action visible")

func check_review_change_navigation(popup) -> void:
 popup._reset()
 popup.variables_button.set_pressed_no_signal(false)
 var route := """count = 0
wait()
wait()
count += 1
wait()
wait()
count += 1
wait()
count += 1
wait()
"""
 popup.source.text = route
 popup.check_button.pressed.emit()
 press_key(KEY_F7)
 popup.review_button.pressed.emit()
 var slider: HSlider = popup.review_slider
 var previous: Button = popup.review_previous_change
 var next: Button = popup.review_next_change
 var hidden_in_values: bool = not popup.review_change_row.is_visible_in_tree()
 press_key(KEY_F7, true)
 check(hidden_in_values and previous.is_visible_in_tree() and previous.disabled and not next.disabled and slider.value == 0 and slider.has_focus(), "Change navigation opens with Changes and starts with only the next direction available")

 press_key(KEY_PAGEDOWN)
 check(slider.value == 2 and popup.variables_text.text == "count = 0 → 1" and slider.has_focus(), "Page Down skips the first unchanged action and shows the first variable change")
 next.grab_focus()
 press_key(KEY_ENTER)
 check(slider.value == 4 and popup.variables_text.text == "count = 1 → 2" and slider.has_focus(), "Next change skips unchanged actions and restores timeline focus")
 press_key(KEY_PAGEDOWN)
 press_key(KEY_PAGEDOWN)
 check(slider.value == 5 and next.disabled and not previous.disabled and popup.variables_text.text == "count = 2 → 3", "Adjacent changes remain separate stops and there is no jump past the last change")
 slider.value = 6
 press_key(KEY_PAGEUP)
 var from_end := slider.value == 5
 previous.grab_focus()
 press_key(KEY_ENTER)
 var from_button := slider.value == 4 and slider.has_focus()
 press_key(KEY_PAGEUP)
 press_key(KEY_PAGEUP)
 check(from_end and from_button and slider.value == 2 and previous.disabled and not next.disabled and popup.garden.turn == 0, "Previous change skips unchanged actions and stops at the first change without updating the live board")
 press_key(KEY_RIGHT)
 check(slider.value == 3 and popup.variables_text.text == "No variable changes" and not previous.disabled and not next.disabled, "The right arrow still visits the individual unchanged action")
 press_key(KEY_F7)
 check(not popup.review_change_row.is_visible_in_tree() and slider.value == 3 and slider.has_focus() and popup.variables_text.text == "count = 1", "Switching to Variables hides navigation without changing the timeline")

 popup.review_button.pressed.emit()
 popup.source.text = "wait()\nwait()\n"
 popup.check_button.pressed.emit()
 press_key(KEY_F7, true)
 popup.review_button.pressed.emit()
 check(slider.max_value == 2 and not popup.review_change_row.is_visible_in_tree() and popup.variables_text.text == "No variable changes", "Opening a route with no changes clears earlier jump destinations")

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
 check_nursery_storage()
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
  check(popup.checked_route.actions.size() == Program.MAX_STEPS and "Preview limit" in popup.status.text and popup.garden.turn == 0 and popup.progress.nursery_balance() == 0, "Check previews the first 256 nursery actions without earning lilies")
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
  check(popup.garden.harvested == 5 and popup.progress.nursery_balance() == 5 and popup.progress.earned_lilies() == earned_for_practice and not popup.best_button.visible, "Nursery harvests credit the nursery balance and leave lesson records intact")
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
  check_willow_nursery(popup, open_nursery)
  await check_nursery_reservoir(popup, open_nursery)
  var reach_route: String = await check_reach_tool(popup)
  var lotus_route: String = await check_lotus_marsh(popup, reach_route)
  var hook_route: String = await check_harvest_hook(popup, lotus_route)
  await check_stone_ring_nursery(popup, hook_route)
  check_nursery_speed(popup)
  await check_run_counters(popup, hook_route)
  await check_nursery_target(popup)
  check_nursery_reports(popup)
  check_nursery_bests(popup)
  await check_draft_comparison(popup)
  check_comparison_stopping_points(popup)
  await check_comparison_python_details(popup)
  check_comparison_python_differences(popup)
  await check_duplicate_draft(popup)
  check_comparison_source(popup)
  await check_comparison_resume(popup)
  await check_comparison_starting_board(popup)
  check_compare_personal_best(popup)
  await check_extended_comparison(popup)
  await check_comparison_results(popup)
  await check_comparison_totals_at_target(popup)
  await check_alder_crossing(popup)
  check_run_to_cursor(popup)
  check_step_out(popup)
  await check_call_stack(popup)
  check_frame_variables(popup)
  check_variable_changes(popup)
  check_review_change_navigation(popup)
  popup._close()

 check(await travel(game, "home_woodland_pond"), "Return home from activities")
 print("ACTIVITY_SMOKE " + JSON.stringify({"checks":checks, "failures":failures}))
 await game.shutdown(0 if failures.is_empty() else 1)
