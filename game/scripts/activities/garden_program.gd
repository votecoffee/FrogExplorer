extends RefCounted
## Bounded in-game commands. Programs never execute engine or system code.

const PUZZLES = [
 {"id":"first_bloom", "name":"First bloom", "rows":["~LL"], "target":9, "hint":"Fill at the spring. For each lily: hop east, water, wait, gather.", "draft":"# Harvest two lilies\nfill\nrepeat 2\n  hop east\n  water\n  wait\n  gather\nend\n", "python_draft":"# Harvest two lilies one at a time\nfill()\nhop(east)\nwater()\nwait()\ngather()\nhop(east)\nwater()\nwait()\ngather()\n"},
 {"id":"around_the_stones", "name":"Around the stones", "rows":["~.L#", "##.L", "..L."], "target":16, "hint":"Stones block hops. Use the open corridor to reach all three lilies.", "draft":"# Start at the spring\nfill\nhop east\nhop east\n", "python_draft":"# Start at the spring\nfill()\nhop(east)\nhop(east)\n"},
 {"id":"a_second_drink", "name":"A second drink", "rows":["~.H.", "##.#", ".HL."], "target":21, "hint":"Double lilies need two doses. Return to the spring whenever your tank is empty.", "draft":"# Plan a refill for the double lilies\nfill\n", "python_draft":"# Plan a refill for the double lilies\nfill()\n"},
 {"id":"twin_terraces", "name":"Twin terraces", "unlock_lilies":2, "rows":[".##", "~LL", "~LL"], "target":19, "hint":"Start at the lower spring. The two terraces have the same route. After each bed, return to the spring column and hop north.", "draft":"# Repeat a trip along each terrace\nrepeat 2\n  fill\n  # Tend the row and return west\n  hop north\nend\n", "python_draft":"# Repeat a trip along each terrace\nfor _ in range(2):\n    fill()\n    # Tend the row and return west\n    hop(north)\n"},
 {"id":"reedbank_loop", "name":"Reedbank loop", "unlock_lilies":2, "rows":["~.H#", ".#..", "L#.L", ".H.."], "target":28, "hint":"The tank holds three doses. Pair a double lily with a single lily on each trip, then use the lanes around the stones to refill.", "draft":"# Plan two trips from the spring\nfill\n", "python_draft":"# Plan two trips from the spring\nfill()\n"},
 {"id":"stone_spillway", "name":"Stone spillway", "unlock_lilies":2, "rows":[".###","~LHL",".###","~LHL"], "target":36, "hint":"Start at the lower spring. Each bed has a double lily between two single lilies. Reuse finish_lily after the last dose and refill in the west column.", "draft":"# Reuse this routine after a lily's final dose\nroutine finish_lily\n  wait\n  gather\nend\n\nfill\nhop east\nwater\ncall finish_lily\n", "python_draft":"# Reuse this routine after a lily's final dose\ndef finish_lily():\n    wait()\n    gather()\n\nfill()\nhop(east)\nwater()\nfinish_lily()\n"},
 {"id":"patchwork_beds", "name":"Patchwork beds", "unlock_lilies":8, "rows":["~L.H",".###","~.HL"], "target":26, "hint":"The beds mix empty spaces, single lilies, and double lilies. The starter tends the lower bed. Refill on the west bank to tend the upper bed.", "draft":"# Tend the lower bed, then reuse tend_plot in the upper bed\nroutine tend_plot\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\n\nfill\nrepeat 3\n  hop east\n  call tend_plot\nend\n", "python_draft":"# Tend the lower bed, then reuse tend_plot in the upper bed\ndef tend_plot():\n    for _ in range(2):\n        if thirsty():\n            water()\n    if growing():\n        wait()\n    if ripe():\n        gather()\n\nfill()\nfor _ in range(3):\n    hop(east)\n    tend_plot()\n"},
 {"id":"forked_banks", "name":"Forked banks", "unlock_lilies":8, "rows":["~.L#",".###","~#H#","...#"], "target":20, "hint":"Start at the lower spring. The stone blocks the direct east route here. Reuse the same route routine from the upper spring, where east is open.", "draft":"# Reach both beds by checking whether east is open\nroutine to_lily\n  if clear east\n    repeat 2\n      hop east\n    end\n  else\n    hop south\n    repeat 2\n      hop east\n    end\n    hop north\n  end\nend\n\nfill\ncall to_lily\nwater\n", "python_draft":"# Reach both beds by checking whether east is open\ndef to_lily():\n    if clear(east):\n        for _ in range(2):\n            hop(east)\n    else:\n        hop(south)\n        for _ in range(2):\n            hop(east)\n        hop(north)\n\nfill()\nto_lily()\nwater()\n"},
 {"id":"lantern_rows", "name":"Lantern rows", "unlock_lilies":8, "rows":["~.L.L",".####","~.H##"], "target":22, "hint":"Start at the short bed. Sweep east until the path closes. Walk west to the spring column, hop north twice, then refill and sweep the long bed.", "draft":"# Sweep the short bed, then reuse sweep_east on the long bed\nroutine tend_plot\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\nroutine sweep_east\n  while clear east\n    hop east\n    call tend_plot\n  end\nend\n\nfill\ncall sweep_east\n", "python_draft":"# Sweep the short bed, then reuse sweep_east on the long bed\ndef tend_plot():\n    for _ in range(2):\n        if thirsty():\n            water()\n    if growing():\n        wait()\n    if ripe():\n        gather()\ndef sweep_east():\n    while clear(east):\n        hop(east)\n        tend_plot()\n\nfill()\nsweep_east()\n"},
 {"id":"spring_relay", "name":"Spring relay", "unlock_lilies":8, "rows":["~LHL.",".####","~.HL."], "target":35, "hint":"Sweep the lower bed. Go back west to the spring column and hop north twice. The upper bed takes two tankfuls. Already gathered plots can be crossed again.", "draft":"# Sweep the lower bed, then plan two trips along the upper bed\nroutine tend_plot\n  while thirsty and has_water\n    water\n  end\n  if growing or ripe\n    if growing\n      wait\n    end\n    gather\n  end\nend\nroutine sweep_east\n  while clear east and has_water\n    hop east\n    call tend_plot\n  end\nend\n\nfill\ncall sweep_east\n", "python_draft":"# Sweep the lower bed, then plan two trips along the upper bed\ndef tend_plot():\n    while thirsty() and has_water():\n        water()\n    if growing() or ripe():\n        if growing():\n            wait()\n        gather()\ndef sweep_east():\n    while clear(east) and has_water():\n        hop(east)\n        tend_plot()\n\nfill()\nsweep_east()\n"},
 {"id":"side_channels", "name":"Side channels", "unlock_lilies":18, "rows":["##L#L","~....","#L#L#"], "target":31, "hint":"Follow the center path and look for lilies to the north or south. Return west to refill after the third lily. A second sweep can skip the lilies you already gathered.", "draft":"# Look for lilies off the center path before hopping\nroutine tend_plot\n  water\n  wait\n  gather\nend\nroutine sweep_east\n  while clear east and has_water\n    hop east\n    if lily north\n      hop north\n      call tend_plot\n      hop south\n    end\n    if lily south and has_water\n      hop south\n      call tend_plot\n      hop north\n    end\n  end\nend\n\nfill\ncall sweep_east\n", "python_draft":"# Look for lilies off the center path before hopping\ndef tend_plot():\n    water()\n    wait()\n    gather()\ndef sweep_east():\n    while clear(east) and has_water():\n        hop(east)\n        if lily(north):\n            hop(north)\n            tend_plot()\n            hop(south)\n        if lily(south) and has_water():\n            hop(south)\n            tend_plot()\n            hop(north)\n\nfill()\nsweep_east()\n"},
 {"id":"compass_banks", "name":"Compass banks", "unlock_lilies":18, "rows":["L####","..~..","####H"], "target":17, "hint":"The spring is between two mirrored paths. After the west sweep, return east to the spring. Call sweep again with east along the bank, south toward the lily, and north back to the path.", "draft":"# Sweep west, then reuse the routine with different directions\nroutine tend_bed toward back\n  hop toward\n  while thirsty and has_water\n    water\n  end\n  wait\n  gather\n  hop back\nend\nroutine sweep along branch return_path\n  while clear along and has_water\n    hop along\n    if lily branch\n      call tend_bed branch return_path\n    end\n  end\nend\n\nfill\ncall sweep west north south\n", "python_draft":"# Sweep west, then reuse the routine with different directions\ndef tend_bed(toward, back):\n    hop(toward)\n    while thirsty() and has_water():\n        water()\n    wait()\n    gather()\n    hop(back)\ndef sweep(along, branch, return_path):\n    while clear(along) and has_water():\n        hop(along)\n        if lily(branch):\n            tend_bed(branch, return_path)\n\nfill()\nsweep(west, north, south)\n"},
 {"id":"low_water_row", "name":"Low water row", "unlock_lilies":18, "rows":["~LLHL"], "target":25, "hint":"The first sweep runs out of water at the double lily. Return to the spring, refill, and sweep again. The routine skips plots you already gathered.", "draft":"# Leave the row to refill when a plot still needs water\nroutine sweep\n  while clear east\n    hop east\n    if not lily\n      continue\n    end\n    while thirsty and has_water\n      water\n    end\n    if thirsty\n      break\n    end\n    wait\n    gather\n  end\nend\n\nfill\ncall sweep\n", "python_draft":"# Leave the row to refill when a plot still needs water\ndef sweep():\n    while clear(east):\n        hop(east)\n        if not lily():\n            continue\n        while thirsty() and has_water():\n            water()\n        if thirsty():\n            break\n        wait()\n        gather()\n\nfill()\nsweep()\n"},
 {"id":"nursery_beds", "name":"Nursery beds", "unlock_lilies":26, "rows":["~B.BL"], "target":16, "hint":"Plant the brown seedbeds, then water and gather their lilies. The starter tends the first bed. Keep moving east and reuse tend to handle a blank path, another seedbed, and a lily already planted.", "draft":"# Tend the first bed, then reuse the routine along the row\nroutine tend\n  if empty_bed\n    plant\n  end\n  if lily\n    water\n    wait\n    gather\n  end\nend\n\nfill\nhop east\ncall tend\n", "python_draft":"# Tend the first bed, then reuse the function along the row\ndef tend():\n    if empty_bed():\n        plant()\n    if lily():\n        water()\n        wait()\n        gather()\n\nfill()\nhop(east)\ntend()\n"},
]
const DIRECTIONS = {"north":Vector2i(0,-1), "east":Vector2i(1,0), "south":Vector2i(0,1), "west":Vector2i(-1,0)}
const CONDITIONS := ["spring", "has_water", "empty_bed", "lily", "thirsty", "growing", "ripe"]
const PLOT_DOSES := {"B":0, "L":1, "H":2}
const EMPTY_BED := "Empty bed"
const CAPACITY = 3
const MAX_STEPS = 256
const MAX_WHILE_ITERATIONS := 16
const PYTHON_COMPILER := "res://scripts/activities/garden_python.py"
var rows: Array = []
var plants: Dictionary = {}
var cell := Vector2i.ZERO
var tank := 0
var turn := 0
var harvested := 0
var runtime_error := ""
var runtime_error_line := -1
var while_entries: Dictionary = {}

static func compile(source: String, case_sensitive := false) -> Dictionary:
 if source.length() > 8192:
  return {"error":"Programs can contain up to 8,192 characters.", "line":0}
 var blocks: Array[Dictionary] = [{"steps":[]}]
 var routines: Dictionary = {}
 var parameters := PackedStringArray()
 var lines := source.split("\n")
 for index in lines.size():
  var text := lines[index].get_slice("#", 0).strip_edges().replace("\t", " ")
  if not case_sensitive:
   text = text.to_lower()
  var words := text.split(" ", false)
  if words.is_empty():
   continue
  var command := words[0]
  if command == "routine":
   if blocks.size() != 1:
    return _error(index, "Define routines at the top level of the program.")
   if words.size() < 2 or not words[1].is_valid_ascii_identifier():
    return _error(index, "Use routine NAME with letters, digits, or underscores. Start the name with a letter or underscore.")
   if routines.has(words[1]):
    return _error(index, "Routine %s is already defined." % words[1])
   for parameter in words.slice(2):
    if not parameter.is_valid_ascii_identifier() or DIRECTIONS.has(parameter) or parameter in ["not", "and", "or"]:
     return _error(index, "Use a parameter name like heading or return_path.")
    if parameter in parameters:
     return _error(index, "Parameter %s is already listed." % parameter)
    parameters.append(parameter)
   blocks.append({"steps":[], "routine":words[1], "line":index})
   continue
  if command in ["repeat", "if", "while"]:
   var block_limit := 6 if blocks.size() > 1 and blocks[1].has("routine") else 5
   if blocks.size() >= block_limit:
    return _error(index, "Nest up to four repeat, if, and while blocks.")
   if command == "repeat":
    if words.size() != 2 or not words[1].is_valid_int() or int(words[1]) not in range(1, 17):
     return _error(index, "Use repeat 1–16.")
    blocks.append({"steps":[], "times":int(words[1]), "line":index})
   else:
    var expression := _parse_condition(words.slice(1), parameters)
    if expression.has("error"):
     return _error(index, expression.error)
    blocks.append({"steps":[], "clauses":expression.clauses, "line":index, "loop":command == "while"})
   continue
  if command == "else":
   if words.size() != 1:
    return _error(index, "Put else on its own line.")
   var branch: Dictionary = blocks.back()
   if not branch.has("clauses") or branch.loop or branch.has("then_steps"):
    return _error(index, "Use one else inside an if block.")
   if branch.steps.is_empty():
    return _error(branch.line, "Add at least one command before else.")
   branch.then_steps = branch.steps
   branch.steps = []
   branch.else_line = index
   continue
  if command == "end" and words.size() == 1:
   if blocks.size() == 1:
    return _error(index, "There is no block to close.")
   var inner: Dictionary = blocks.pop_back()
   if inner.has("routine"):
    if inner.steps.is_empty():
     return _error(inner.line, "Add at least one action to this routine.")
    routines[inner.routine] = {"steps":inner.steps, "parameters":parameters}
    parameters = PackedStringArray()
    continue
   var outer: Array = blocks.back().steps
   if inner.has("clauses"):
    var has_else := inner.has("then_steps")
    var is_loop: bool = inner.loop
    var kind := "while" if is_loop else "if"
    if inner.steps.is_empty():
     if has_else:
      return _error(inner.else_line, "Add at least one command after else.")
     return _error(inner.line, "Add at least one command inside this %s block." % kind)
    var then_steps: Array = inner.get("then_steps", inner.steps)
    var else_steps: Array = inner.steps if has_else else []
    var skip := then_steps.size() + int(has_else or is_loop)
    if outer.size() + 1 + skip + else_steps.size() > MAX_STEPS:
     return _error(index, "This %s block exceeds the 256-instruction limit." % kind)
    # Relative jumps still work when a repeat or routine copies these instructions.
    outer.append({"clauses":inner.clauses, "skip":skip, "line":inner.line, "loop":is_loop})
    if is_loop:
     _append_loop_body(outer, then_steps, outer.size() + skip, true)
     outer.append({"back":skip, "line":inner.line})
    else:
     outer.append_array(then_steps)
     if has_else:
      outer.append({"skip":else_steps.size(), "line":inner.else_line})
      outer.append_array(else_steps)
    continue
   var loop_end: int = outer.size() + inner.steps.size() * inner.times
   if loop_end > MAX_STEPS:
    return _error(index, "This loop expands beyond 256 instructions.")
   for count in inner.times:
    _append_loop_body(outer, inner.steps, loop_end)
   continue
  var steps: Array = blocks.back().steps
  if command == "call":
   if words.size() < 2 or not words[1].is_valid_ascii_identifier():
    return _error(index, "Use call NAME with a routine name.")
   if not routines.has(words[1]):
    return _error(index, "Define routine %s before calling it." % words[1])
   var routine: Dictionary = routines[words[1]]
   var targets: PackedStringArray = routine.parameters
   var arguments := words.slice(2)
   if arguments.size() != targets.size():
    var unit := "argument" if targets.size() == 1 else "arguments"
    return _error(index, "Routine %s expects %d direction %s." % [words[1], targets.size(), unit])
   if steps.size() + routine.steps.size() > MAX_STEPS:
    return _error(index, "This call expands the program beyond 256 instructions.")
   var bindings: Dictionary = {}
   for argument_index in arguments.size():
    var argument := arguments[argument_index]
    if not _is_direction(argument, parameters):
     return _error(index, "Argument %s needs a compass direction or a routine parameter." % targets[argument_index])
    bindings[targets[argument_index]] = argument
   steps.append_array(_bind_directions(routine.steps, bindings))
   continue
  var instruction := {"command":command, "direction":"", "line":index}
  if command == "hop":
   if words.size() != 2 or not _is_direction(words[1], parameters):
    return _error(index, "Use hop with north, east, south, west, or a routine parameter.")
   instruction.direction = words[1]
  elif command in ["break", "continue"]:
   if words.size() != 1 or not blocks.any(func(block): return block.has("times") or block.get("loop", false)):
    return _error(index, "Put %s on its own line inside repeat or while." % command)
   instruction = {"loop_control":command, "line":index}
  elif words.size() != 1 or command not in ["fill", "plant", "water", "wait", "gather"]:
   return _error(index, "Use hop, fill, plant, water, wait, gather, repeat, routine, call, if, while, break, or continue.")
  if steps.size() >= MAX_STEPS:
   return _error(index, "Programs can contain up to 256 instructions after expansion.")
  steps.append(instruction)
 if blocks.size() > 1:
  var unclosed: Dictionary = blocks.back()
  var kind := "routine" if unclosed.has("routine") else "repeat block"
  if unclosed.has("clauses"):
   kind = "while block" if unclosed.loop else "if block"
  return _error(unclosed.line, "Close this %s with end." % kind)
 if blocks[0].steps.is_empty():
  return _error(0, "Add at least one action.")
 return {"steps":blocks[0].steps}

static func compile_python(source: String) -> Dictionary:
 if source.length() > 8192:
  return _error(0, "Programs can contain up to 8,192 characters.")
 var compiler := ProjectSettings.globalize_path(PYTHON_COMPILER)
 if not FileAccess.file_exists(compiler):
  return _error(0, "The garden Python compiler is missing from this installation.")
 var temporary := FileAccess.create_temp(FileAccess.WRITE, "frog-garden", "py", true)
 if temporary == null:
  return _error(0, "Could not prepare this draft for Python.")
 var draft_path := temporary.get_path_absolute()
 temporary.store_string(source)
 var write_error := temporary.get_error()
 temporary.close()
 if write_error != OK:
  DirAccess.remove_absolute(draft_path)
  return _error(0, "Could not prepare this draft for Python.")
 var python := OS.get_environment("FROG_GARDEN_PYTHON")
 if python.is_empty():
  python = "python.exe" if OS.get_name() == "Windows" else "python3"
 var output: Array = []
 var status := OS.execute(python, ["-I", "-S", compiler, draft_path], output)
 DirAccess.remove_absolute(draft_path)
 if status != 0 or output.is_empty():
  return _error(0, "Could not start the garden compiler. Put Python 3.10 or newer on PATH.")
 var lowered: Variant = JSON.parse_string(output[0])
 if not lowered is Dictionary:
  return _error(0, "The Python compiler returned an unreadable result.")
 if lowered.has("error"):
  return _error(int(lowered.line), lowered.error)
 var locations: Array = lowered.lines
 var result := compile(lowered.source, true)
 if result.has("error"):
  var index: int = result.line
  var message: String = result.error.trim_prefix("Line %d · " % (index + 1))
  return _error(int(locations[index]) if index < locations.size() else 0, message)
 # Repeat copies can share an instruction. Remap its source line on a fresh copy.
 for index in result.steps.size():
  var instruction: Dictionary = result.steps[index].duplicate()
  instruction.line = int(locations[instruction.line])
  result.steps[index] = instruction
 return result

static func _append_loop_body(outer: Array, body: Array, loop_end: int, is_while := false) -> void:
 var start := outer.size()
 for instruction: Dictionary in body:
  if not instruction.has("loop_control"):
   outer.append(instruction)
   continue
  # Continue reaches the next repeat copy or the while back edge.
  var leaving: bool = instruction.loop_control == "break"
  var destination := loop_end if leaving else start + body.size()
  var jump := {"skip":destination - outer.size() - 1, "line":instruction.line}
  if leaving and is_while:
   jump.leave_while = outer.size() - start + 1
  outer.append(jump)

static func _is_direction(word: String, parameters: PackedStringArray) -> bool:
 return DIRECTIONS.has(word) or word in parameters

static func _bind_directions(instructions: Array, bindings: Dictionary) -> Array:
 if bindings.is_empty():
  return instructions
 # Each call gets independent directions while retaining source lines and relative jumps.
 var expanded: Array[Dictionary] = []
 for original: Dictionary in instructions:
  var instruction := original.duplicate(true)
  if instruction.has("direction"):
   instruction.direction = bindings.get(instruction.direction, instruction.direction)
  elif instruction.has("clauses"):
   for clause: Array in instruction.clauses:
    for test: Dictionary in clause:
     test.direction = bindings.get(test.direction, test.direction)
  expanded.append(instruction)
 return expanded

static func _parse_condition(words: PackedStringArray, parameters: PackedStringArray) -> Dictionary:
 # Each clause is a group of AND tests. Any matching clause satisfies the expression.
 var clauses: Array[Array] = []
 var clause: Array[Dictionary] = []
 var index := 0
 while index < words.size():
  var negated := words[index] == "not"
  index += int(negated)
  if index == words.size():
   break
  var condition := words[index]
  index += 1
  var direction := ""
  if condition == "clear":
   if index == words.size() or not _is_direction(words[index], parameters):
    return {"error":"Use clear with north, south, east, west, or a routine parameter."}
   direction = words[index]
   index += 1
  elif condition not in CONDITIONS:
   return {"error":"Expected a condition. Try spring, has_water, empty_bed, lily north, thirsty, growing, ripe, or clear east."}
  elif index < words.size() and _is_direction(words[index], parameters):
   if condition == "has_water":
    return {"error":"Use has_water without a direction. It checks Pondbot's tank."}
   direction = words[index]
   index += 1
  clause.append({"condition":condition, "direction":direction, "negated":negated})
  if index == words.size():
   clauses.append(clause)
   return {"clauses":clauses}
  match words[index]:
   "and":
    pass
   "or":
    clauses.append(clause)
    clause = []
   _:
    return {"error":"Join conditions with 'and' or 'or'."}
  index += 1
 return {"error":"Expected a condition. Try thirsty or not has_water."}

static func _error(line: int, message: String) -> Dictionary:
 return {"error":"Line %d · %s" % [line + 1, message], "line":line}

static func puzzle_lilies(puzzle: Dictionary) -> int:
 var total := 0
 for row: String in puzzle.rows:
  for plot: String in PLOT_DOSES:
   total += row.count(plot)
 return total

func load_puzzle(index: int) -> void:
 rows = PUZZLES[index].rows
 plants.clear()
 tank = 0
 turn = 0
 harvested = 0
 runtime_error = ""
 runtime_error_line = -1
 while_entries.clear()
 for y in rows.size():
  for x in rows[y].length():
   var location := Vector2i(x, y)
   var plot := tile(location)
   if plot == "~":
    cell = location
   elif PLOT_DOSES.has(plot):
    plants[location] = {"need":PLOT_DOSES[plot], "ready":-1, "harvested":false, "planted":plot != "B"}

func tile(location: Vector2i) -> String:
 if location.y < 0 or location.y >= rows.size() or location.x < 0 or location.x >= rows[location.y].length():
  return "#"
 return rows[location.y][location.x]

func plant_status(location: Vector2i) -> String:
 var plant: Dictionary = plants.get(location, {})
 if plant.is_empty():
  return ""
 if not plant.planted:
  return EMPTY_BED
 if plant.harvested:
  return "Gathered"
 if plant.need > 0:
  return "Thirsty ×%d" % plant.need
 return "Ripe" if turn >= plant.ready else "Growing"

func is_complete() -> bool:
 return harvested == plants.size()

func next_action_index(instructions: Array, first: int) -> int:
 var index := first
 while index < instructions.size() and runtime_error.is_empty():
  var instruction: Dictionary = instructions[index]
  if instruction.has("back"):
   index -= int(instruction.back)
   continue
  if not instruction.has("skip"):
   if turn >= MAX_STEPS:
    runtime_error = "The program reached its %d-action limit." % MAX_STEPS
    runtime_error_line = instruction.line
   break
  if instruction.has("leave_while"):
   while_entries.erase(index - int(instruction.leave_while))
  var passes: bool = instruction.has("clauses") and _meets_any_clause(instruction.clauses)
  if instruction.get("loop", false):
   if passes:
    var entry: Dictionary = while_entries.get(index, {"turn":-1, "iterations":0})
    if entry.turn == turn:
     runtime_error = "This while loop came back without doing an action."
    elif entry.iterations >= MAX_WHILE_ITERATIONS:
     runtime_error = "This while loop reached its %d-iteration limit." % MAX_WHILE_ITERATIONS
    if not runtime_error.is_empty():
     runtime_error_line = instruction.line
     break
    while_entries[index] = {"turn":turn, "iterations":int(entry.iterations) + 1}
   else:
    while_entries.erase(index)
  index += 1 if passes else 1 + int(instruction.skip)
 return index if runtime_error.is_empty() else instructions.size()

func _meets_any_clause(clauses: Array) -> bool:
 for clause: Array in clauses:
  var matches := true
  for test: Dictionary in clause:
   if _meets_condition(test.condition, test.direction) == test.negated:
    matches = false
    break
  if matches:
   return true
 return false

func _meets_condition(condition: String, direction: String) -> bool:
 var location := cell
 if not direction.is_empty():
  location += DIRECTIONS[direction]
 match condition:
  "clear":
   return tile(location) != "#"
  "spring":
   return tile(location) == "~"
  "has_water":
   return tank > 0
  "empty_bed":
   return not plants.get(location, {}).get("planted", true)
  "lily":
   return plants.has(location) and plants[location].planted and not plants[location].harvested
  "thirsty":
   var plant: Dictionary = plants.get(location, {})
   return int(plant.get("need", 0)) > 0
  "growing":
   return plant_status(location) == "Growing"
  "ripe":
   return plant_status(location) == "Ripe"
  _:
   return false

func step(action: Dictionary) -> String:
 var plant: Dictionary = plants.get(cell, {})
 match action.command:
  "hop":
   var next: Vector2i = cell + DIRECTIONS[action.direction]
   if tile(next) == "#":
    return "A stone or the bank blocks this hop."
   cell = next
  "fill":
   if tile(cell) != "~":
    return "Fill at the spring."
   tank = CAPACITY
  "plant":
   if plant.get("planted", true):
    return "Plant on a prepared empty bed."
   plant.planted = true
   plant.need = 1
  "water":
   if not plant.get("planted", true):
    return "Plant this bed before watering it."
   if plant.is_empty() or plant.harvested or plant.need == 0:
    return "This plot does not need water."
   if tank == 0:
    return "The tank is empty. Visit the spring."
   tank -= 1
   plant.need -= 1
   if plant.need == 0:
    plant.ready = turn + 2
  "gather":
   if plant_status(cell) != "Ripe":
    return "Gather a ripe lily. A freshly watered lily needs one more turn."
   plant.harvested = true
   harvested += 1
 turn += 1
 return ""
