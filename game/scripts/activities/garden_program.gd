extends RefCounted
## Bounded in-game commands. Programs never execute engine or system code.

const PUZZLES = [
 {"id":"first_bloom", "name":"First bloom", "rows":["~LL"], "target":9, "hint":"Fill at the spring. For each lily: hop east, water, wait, gather.", "draft":"# Harvest two lilies\nfill\nrepeat 2\n  hop east\n  water\n  wait\n  gather\nend\n"},
 {"id":"around_the_stones", "name":"Around the stones", "rows":["~.L#", "##.L", "..L."], "target":16, "hint":"Stones block hops. Use the open corridor to reach all three lilies.", "draft":"# Start at the spring\nfill\nhop east\nhop east\n"},
 {"id":"a_second_drink", "name":"A second drink", "rows":["~.H.", "##.#", ".HL."], "target":21, "hint":"Double lilies need two doses. Return to the spring whenever your tank is empty.", "draft":"# Plan a refill for the double lilies\nfill\n"},
 {"id":"twin_terraces", "name":"Twin terraces", "rows":[".##", "~LL", "~LL"], "target":19, "hint":"Start at the lower spring. The two terraces have the same route. After each bed, return to the spring column and hop north.", "draft":"# Repeat a trip along each terrace\nrepeat 2\n  fill\n  # Tend the row and return west\n  hop north\nend\n"},
 {"id":"reedbank_loop", "name":"Reedbank loop", "rows":["~.H#", ".#..", "L#.L", ".H.."], "target":28, "hint":"The tank holds three doses. Pair a double lily with a single lily on each trip, then use the lanes around the stones to refill.", "draft":"# Plan two trips from the spring\nfill\n"},
 {"id":"stone_spillway", "name":"Stone spillway", "rows":[".###","~LHL",".###","~LHL"], "target":36, "hint":"Start at the lower spring. Each bed has a double lily between two single lilies. Reuse finish_lily after the last dose and refill in the west column.", "draft":"# Reuse this routine after a lily's final dose\nroutine finish_lily\n  wait\n  gather\nend\n\nfill\nhop east\nwater\ncall finish_lily\n"},
 {"id":"patchwork_beds", "name":"Patchwork beds", "rows":["~L.H",".###","~.HL"], "target":26, "hint":"The beds mix empty spaces, single lilies, and double lilies. The starter tends the lower bed. Refill on the west bank to tend the upper bed.", "draft":"# Tend the lower bed, then reuse tend_plot in the upper bed\nroutine tend_plot\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\n\nfill\nrepeat 3\n  hop east\n  call tend_plot\nend\n"},
 {"id":"forked_banks", "name":"Forked banks", "rows":["~.L#",".###","~#H#","...#"], "target":20, "hint":"Start at the lower spring. The stone blocks the direct east route here. Reuse the same route routine from the upper spring, where east is open.", "draft":"# Reach both beds by checking whether east is open\nroutine to_lily\n  if clear east\n    repeat 2\n      hop east\n    end\n  else\n    hop south\n    repeat 2\n      hop east\n    end\n    hop north\n  end\nend\n\nfill\ncall to_lily\nwater\n"},
 {"id":"lantern_rows", "name":"Lantern rows", "rows":["~.L.L",".####","~.H##"], "target":22, "hint":"Start at the short bed. Sweep east until the path closes. Walk west to the spring column, hop north twice, then refill and sweep the long bed.", "draft":"# Sweep the short bed, then reuse sweep_east on the long bed\nroutine tend_plot\n  repeat 2\n    if thirsty\n      water\n    end\n  end\n  if growing\n    wait\n  end\n  if ripe\n    gather\n  end\nend\nroutine sweep_east\n  while clear east\n    hop east\n    call tend_plot\n  end\nend\n\nfill\ncall sweep_east\n"},
 {"id":"spring_relay", "name":"Spring relay", "rows":["~LHL.",".####","~.HL."], "target":35, "hint":"Sweep the lower bed. Go back west to the spring column and hop north twice. The upper bed takes two tankfuls. Already gathered plots can be crossed again.", "draft":"# Sweep the lower bed, then plan two trips along the upper bed\nroutine tend_plot\n  while thirsty and has_water\n    water\n  end\n  if growing or ripe\n    if growing\n      wait\n    end\n    gather\n  end\nend\nroutine sweep_east\n  while clear east and has_water\n    hop east\n    call tend_plot\n  end\nend\n\nfill\ncall sweep_east\n"},
]
const DIRECTIONS = {"north":Vector2i(0,-1), "east":Vector2i(1,0), "south":Vector2i(0,1), "west":Vector2i(-1,0)}
const CONDITIONS := ["spring", "has_water", "thirsty", "growing", "ripe"]
const CAPACITY = 3
const MAX_STEPS = 256
const MAX_WHILE_ITERATIONS := 16
var rows: Array = []
var plants: Dictionary = {}
var cell := Vector2i.ZERO
var tank := 0
var turn := 0
var harvested := 0
var runtime_error := ""
var runtime_error_line := -1
var while_entries: Dictionary = {}

static func compile(source: String) -> Dictionary:
 if source.length() > 8192:
  return {"error":"Programs can contain up to 8,192 characters.", "line":0}
 var blocks: Array[Dictionary] = [{"steps":[], "times":1, "line":0}]
 var routines: Dictionary = {}
 var lines := source.split("\n")
 for index in lines.size():
  var text := lines[index].get_slice("#", 0).strip_edges().replace("\t", " ").to_lower()
  var words := text.split(" ", false)
  if words.is_empty():
   continue
  var command := words[0]
  if command == "routine":
   if blocks.size() != 1:
    return _error(index, "Define routines at the top level of the program.")
   if words.size() != 2 or not words[1].is_valid_ascii_identifier():
    return _error(index, "Use routine NAME with letters, digits, or underscores. Start the name with a letter or underscore.")
   if routines.has(words[1]):
    return _error(index, "Routine %s is already defined." % words[1])
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
    var expression := _parse_condition(words.slice(1))
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
    routines[inner.routine] = inner.steps
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
    outer.append_array(then_steps)
    if is_loop:
     outer.append({"back":skip, "line":inner.line})
    elif has_else:
     outer.append({"skip":else_steps.size(), "line":inner.else_line})
     outer.append_array(else_steps)
    continue
   if outer.size() + inner.steps.size() * inner.times > MAX_STEPS:
    return _error(index, "This loop expands beyond 256 instructions.")
   for count in inner.times:
    outer.append_array(inner.steps)
   continue
  var steps: Array = blocks.back().steps
  if command == "call":
   if words.size() != 2 or not words[1].is_valid_ascii_identifier():
    return _error(index, "Use call NAME with a routine name.")
   if not routines.has(words[1]):
    return _error(index, "Define routine %s before calling it." % words[1])
   var routine_steps: Array = routines[words[1]]
   if steps.size() + routine_steps.size() > MAX_STEPS:
    return _error(index, "This call expands the program beyond 256 instructions.")
   # Expanded commands retain their original lines inside the routine.
   steps.append_array(routine_steps)
   continue
  if command == "hop":
   if words.size() != 2 or not DIRECTIONS.has(words[1]):
    return _error(index, "Use hop north, east, south, or west.")
  elif words.size() != 1 or command not in ["fill", "water", "wait", "gather"]:
   return _error(index, "Use hop, fill, water, wait, gather, repeat, routine, call, if, or while.")
  if steps.size() >= MAX_STEPS:
   return _error(index, "Programs can contain up to 256 instructions after expansion.")
  steps.append({"command":command, "direction":words[1] if command == "hop" else "", "line":index})
 if blocks.size() > 1:
  var unclosed: Dictionary = blocks.back()
  var kind := "routine" if unclosed.has("routine") else "repeat block"
  if unclosed.has("clauses"):
   kind = "while block" if unclosed.loop else "if block"
  return _error(unclosed.line, "Close this %s with end." % kind)
 if blocks[0].steps.is_empty():
  return _error(0, "Add at least one action.")
 return {"steps":blocks[0].steps}

static func _parse_condition(words: PackedStringArray) -> Dictionary:
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
   if index == words.size() or not DIRECTIONS.has(words[index]):
    return {"error":"Use clear north, south, east, or west."}
   direction = words[index]
   index += 1
  elif condition not in CONDITIONS:
   return {"error":"Expected a condition. Try spring, has_water, thirsty, growing, ripe, or clear east."}
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
   match tile(location):
    "~": cell = location
    "L": plants[location] = {"need":1, "ready":-1, "harvested":false}
    "H": plants[location] = {"need":2, "ready":-1, "harvested":false}

func tile(location: Vector2i) -> String:
 if location.y < 0 or location.y >= rows.size() or location.x < 0 or location.x >= rows[location.y].length():
  return "#"
 return rows[location.y][location.x]

func plant_status(location: Vector2i) -> String:
 var plant: Dictionary = plants.get(location, {})
 if plant.is_empty():
  return ""
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
 match condition:
  "clear":
   return tile(cell + DIRECTIONS[direction]) != "#"
  "spring":
   return tile(cell) == "~"
  "has_water":
   return tank > 0
  "thirsty":
   var plant: Dictionary = plants.get(cell, {})
   return int(plant.get("need", 0)) > 0
  "growing":
   return plant_status(cell) == "Growing"
  "ripe":
   return plant_status(cell) == "Ripe"
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
  "water":
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
