extends RefCounted
## Bounded in-game commands. Programs never execute engine or system code.

const PUZZLES = [
 {"id":"first_bloom", "name":"First bloom", "rows":["~LL"], "hint":"Fill at the spring. For each lily: hop east, water, wait, gather.", "draft":"# Harvest two lilies\nfill\nrepeat 2\n  hop east\n  water\n  wait\n  gather\nend\n"},
 {"id":"around_the_stones", "name":"Around the stones", "rows":["~.L#", "##.L", "..L."], "hint":"Stones block hops. Use the open corridor to reach all three lilies.", "draft":"# Start at the spring\nfill\nhop east\nhop east\n"},
 {"id":"a_second_drink", "name":"A second drink", "rows":["~.H.", "##.#", ".HL."], "hint":"Double lilies need two doses. Return to the spring whenever your tank is empty.", "draft":"# Plan a refill for the double lilies\nfill\n"},
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
 var lines := source.split("\n")
 for index in lines.size():
  var text := lines[index].get_slice("#", 0).strip_edges().replace("\t", " ").to_lower()
  var words := text.split(" ", false)
  if words.is_empty():
   continue
  var command := words[0]
  if command == "repeat":
   if words.size() != 2 or not words[1].is_valid_int() or int(words[1]) not in range(1, 17) or blocks.size() >= 5:
    return _error(index, "Use repeat 1–16, with at most four levels of loops.")
   blocks.append({"steps":[], "times":int(words[1]), "line":index})
   continue
  if command == "end" and words.size() == 1:
   if blocks.size() == 1:
    return _error(index, "There is no repeat block to close.")
   var inner: Dictionary = blocks.pop_back()
   var outer: Array = blocks.back().steps
   if outer.size() + inner.steps.size() * inner.times > MAX_STEPS:
    return _error(index, "This loop expands beyond 256 actions.")
   for count in inner.times:
    outer.append_array(inner.steps)
   continue
  if command == "hop":
   if words.size() != 2 or not DIRECTIONS.has(words[1]):
    return _error(index, "Use hop north, east, south, or west.")
  elif words.size() != 1 or command not in ["fill", "water", "wait", "gather"]:
   return _error(index, "Use hop, fill, water, wait, gather, or repeat … end.")
  var steps: Array = blocks.back().steps
  if steps.size() >= MAX_STEPS:
   return _error(index, "Programs can run up to 256 actions.")
  steps.append({"command":command, "direction":words[1] if command == "hop" else "", "line":index})
 if blocks.size() > 1:
  return _error(blocks.back().line, "Close this repeat block with end.")
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
