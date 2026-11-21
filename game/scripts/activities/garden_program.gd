extends RefCounted
## Bounded in-game commands. Programs never execute engine or system code.

const PUZZLES = [
 {"id":"first_bloom", "name":"First bloom", "rows":["~LL"], "target":9, "hint":"Fill at the spring. For each lily: hop east, water, wait, gather.", "draft":"# Harvest two lilies\nfill\nrepeat 2\n  hop east\n  water\n  wait\n  gather\nend\n"},
 {"id":"around_the_stones", "name":"Around the stones", "rows":["~.L#", "##.L", "..L."], "target":16, "hint":"Stones block hops. Use the open corridor to reach all three lilies.", "draft":"# Start at the spring\nfill\nhop east\nhop east\n"},
 {"id":"a_second_drink", "name":"A second drink", "rows":["~.H.", "##.#", ".HL."], "target":21, "hint":"Double lilies need two doses. Return to the spring whenever your tank is empty.", "draft":"# Plan a refill for the double lilies\nfill\n"},
 {"id":"twin_terraces", "name":"Twin terraces", "rows":[".##", "~LL", "~LL"], "target":19, "hint":"Start at the lower spring. The two terraces have the same route. After each bed, return to the spring column and hop north.", "draft":"# Repeat a trip along each terrace\nrepeat 2\n  fill\n  # Tend the row and return west\n  hop north\nend\n"},
 {"id":"reedbank_loop", "name":"Reedbank loop", "rows":["~.H#", ".#..", "L#.L", ".H.."], "target":28, "hint":"The tank holds three doses. Pair a double lily with a single lily on each trip, then use the lanes around the stones to refill.", "draft":"# Plan two trips from the spring\nfill\n"},
 {"id":"stone_spillway", "name":"Stone spillway", "rows":[".###","~LHL",".###","~LHL"], "target":36, "hint":"Start at the lower spring. Each bed has a double lily between two single lilies. Reuse finish_lily after the last dose and refill in the west column.", "draft":"# Reuse this routine after a lily's final dose\nroutine finish_lily\n  wait\n  gather\nend\n\nfill\nhop east\nwater\ncall finish_lily\n"},
]
const DIRECTIONS = {"north":Vector2i(0,-1), "east":Vector2i(1,0), "south":Vector2i(0,1), "west":Vector2i(-1,0)}
const CAPACITY = 3
const MAX_STEPS = 256
var rows: Array = []
var plants: Dictionary = {}
var cell := Vector2i.ZERO
var tank := 0
var turn := 0
var harvested := 0

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
    return _error(index, "Define routines outside repeat blocks and other routines.")
   if words.size() != 2 or not words[1].is_valid_ascii_identifier():
    return _error(index, "Use routine NAME with letters, digits, or underscores. Start the name with a letter or underscore.")
   if routines.has(words[1]):
    return _error(index, "Routine %s is already defined." % words[1])
   blocks.append({"steps":[], "routine":words[1], "line":index})
   continue
  if command == "repeat":
   var block_limit := 6 if blocks.size() > 1 and blocks[1].has("routine") else 5
   if words.size() != 2 or not words[1].is_valid_int() or int(words[1]) not in range(1, 17) or blocks.size() >= block_limit:
    return _error(index, "Use repeat 1–16, with at most four levels of loops.")
   blocks.append({"steps":[], "times":int(words[1]), "line":index})
   continue
  if command == "end" and words.size() == 1:
   if blocks.size() == 1:
    return _error(index, "There is no repeat or routine block to close.")
   var inner: Dictionary = blocks.pop_back()
   if inner.has("routine"):
    if inner.steps.is_empty():
     return _error(inner.line, "Add at least one action to this routine.")
    routines[inner.routine] = inner.steps
    continue
   var outer: Array = blocks.back().steps
   if outer.size() + inner.steps.size() * inner.times > MAX_STEPS:
    return _error(index, "This loop expands beyond 256 actions.")
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
    return _error(index, "This call expands the program beyond 256 actions.")
   # Expanded commands retain their original lines inside the routine.
   steps.append_array(routine_steps)
   continue
  if command == "hop":
   if words.size() != 2 or not DIRECTIONS.has(words[1]):
    return _error(index, "Use hop north, east, south, or west.")
  elif words.size() != 1 or command not in ["fill", "water", "wait", "gather"]:
   return _error(index, "Use hop, fill, water, wait, gather, repeat, routine, or call.")
  if steps.size() >= MAX_STEPS:
   return _error(index, "Programs can run up to 256 actions.")
  steps.append({"command":command, "direction":words[1] if command == "hop" else "", "line":index})
 if blocks.size() > 1:
  var unclosed: Dictionary = blocks.back()
  var kind := "routine" if unclosed.has("routine") else "repeat block"
  return _error(unclosed.line, "Close this %s with end." % kind)
 if blocks[0].steps.is_empty():
  return _error(0, "Add at least one action.")
 return {"steps":blocks[0].steps}

static func _error(line: int, message: String) -> Dictionary:
 return {"error":"Line %d · %s" % [line + 1, message], "line":line}

func load_puzzle(index: int) -> void:
 rows = PUZZLES[index].rows
 plants.clear()
 tank = 0
 turn = 0
 harvested = 0
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
