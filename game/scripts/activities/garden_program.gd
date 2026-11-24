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
 {"id":"low_water_row", "name":"Low water row", "unlock_lilies":18, "rows":["~LLHL"], "target":25, "hint":"The first sweep runs out of water at the double lily. Return to the spring, refill, and sweep again. The routine skips plots you already gathered.", "draft":"# Leave the row to refill when a plot still needs water\nroutine sweep\n  while clear east\n    hop east\n    if not lily\n      continue\n    end\n    while thirsty and has_water\n      water\n    end\n    if thirsty\n      break\n    end\n    wait\n    gather\n  end\nend\n\nfill\ncall sweep\n", "python_draft":"# End the sweep early if a lily still needs water\ndef sweep():\n    while clear(east):\n        hop(east)\n        if not lily():\n            continue\n        while thirsty() and has_water():\n            water()\n        if thirsty():\n            return\n        wait()\n        gather()\n\nfill()\nsweep()\n"},
 {"id":"nursery_beds", "name":"Nursery beds", "unlock_lilies":26, "rows":["~B.BL"], "target":16, "hint":"Plant the brown seedbeds, then water and gather their lilies. The starter tends the first bed. Keep moving east and reuse tend to handle a blank path, another seedbed, and a lily already planted.", "draft":"# Tend the first bed, then reuse the routine along the row\nroutine tend\n  if empty_bed\n    plant\n  end\n  if lily\n    water\n    wait\n    gather\n  end\nend\n\nfill\nhop east\ncall tend\n", "python_draft":"# Tend the first bed, then reuse the function along the row\ndef tend():\n    if empty_bed():\n        plant()\n    if lily():\n        water()\n        wait()\n        gather()\n\nfill()\nhop(east)\ntend()\n"},
 {
  "id":"switchback_beds", "name":"Switchback beds", "unlock_lilies":26, "target":36,
  "rows":["#L##H", "#.##.", "..~..", ".##.#", "H##L#"],
  "hint":"The lilies are two hops off the causeway. The west stops branch north then south. Return to the spring, refill, and mirror that pattern on the east side.",
  "draft":"""# Tend the two west stops
routine tend_spur toward back
  repeat 2
    hop toward
  end
  while thirsty
    water
  end
  wait
  gather
  repeat 2
    hop back
  end
end

fill
hop west
call tend_spur north south
hop west
call tend_spur south north

# Return to the spring and plan the two east stops
""",
  "python_draft":"""# Reuse this route from each stop on the causeway
def tend_spur(toward, back):
    for _ in range(2):
        hop(toward)
    while thirsty():
        water()
    wait()
    gather()
    for _ in range(2):
        hop(back)

spring_column = column()
fill()
for stop in range(1, 3):
    hop(west)
    if stop == 1:
        tend_spur(north, south)
    else:
        tend_spur(south, north)

# Return to spring_column and mirror the sweep on the east side
""",
 },
]
const OPEN_NURSERY := {
 "id":"open_nursery", "name":"Open nursery", "unlock_lilies":26, "practice":true,
 "rows":[".BB","~..",".BB"],
 "hint":"Harvested beds are ready to plant again. Stop keeps the current garden. Reset board clears it and returns Pondbot to the spring.",
 "draft":"""# Keep both nursery rows growing
routine tend_row toward back
  fill
  hop toward
  repeat 2
    hop east
    if empty_bed
      plant
    end
    if thirsty
      water
    end
    if growing
      wait
    end
    if ripe
      gather
    end
  end
  repeat 2
    hop west
  end
  hop back
end

# Find the spring even if the previous run stopped between beds
while clear west
  hop west
end
if not spring
  if spring north
    hop north
  else
    hop south
  end
end

while always
  call tend_row north south
  call tend_row south north
end
""",
 "python_draft":"""# Keep both nursery rows growing
def tend_row(toward, back):
    fill()
    hop(toward)
    for _ in range(2):
        hop(east)
        if empty_bed():
            plant()
        if thirsty():
            water()
        if growing():
            wait()
        if ripe():
            gather()
    for _ in range(2):
        hop(west)
    hop(back)

# Find the spring even if the previous run stopped between beds
while clear(west):
    hop(west)
if not spring():
    if spring(north):
        hop(north)
    else:
        hop(south)

while True:
    tend_row(north, south)
    tend_row(south, north)
""",
}
const WILLOW_NURSERY := {
 "id":"willow_nursery", "name":"Willow nursery", "practice":true,
 "rows":[".BBB","~...",".B.B"],
 "hint":"Tend both banks, including the gap in the south row. Three water doses cover the north bank. Harvested beds can be planted again.",
 "draft":"""# Tend one bed, then extend the route to both banks
routine tend
  if empty_bed
    plant
  end
  if thirsty and has_water
    water
  end
  if growing
    wait
  end
  if ripe
    gather
  end
end

fill
hop north
hop east
call tend
""",
 "python_draft":"""# Tend one bed, then extend the route to both banks
def tend():
    if empty_bed():
        plant()
    if thirsty() and has_water():
        water()
    if growing():
        wait()
    if ripe():
        gather()

fill()
hop(north)
hop(east)
tend()
""",
}
const LOTUS_MARSH := {
 "id":"lotus_marsh", "name":"Lotus marsh", "practice":true,
 "rows":[".XB.","~...",".BX."],
 "hint":"Lotus beds need two doses and ripen three actions after the final watering. Tend a neighboring lily while you wait. Each ripe lotus earns three nursery lilies.",
 "draft":"""# Tend a lotus and its neighbor. Extend the route to the south bank.
routine tend_ahead heading
  if empty_bed heading
    plant heading
  end
  while thirsty heading and has_water
    water heading
  end
end

fill
hop north
call tend_ahead east
hop east
call tend_ahead east
gather
hop east
gather
""",
 "python_draft":"""# Tend a lotus and its neighbor. Extend the route to the south bank.
def tend_ahead(heading):
    if empty_bed(heading):
        plant(heading)
    while thirsty(heading) and has_water():
        water(heading)

fill()
hop(north)
tend_ahead(east)
hop(east)
tend_ahead(east)
gather()
hop(east)
gather()
""",
}
const STONE_RING_NURSERY := {
 "id":"stone_ring_nursery", "name":"Stone ring nursery", "practice":true,
 "rows":["BXXB#", "....~", ".###.", "~....", "#BXXB"],
 "hint":"Fill at each spring and sweep the next bank. Each bank takes six doses. The first circuit plants the crops. Return on the next circuit to harvest and replant from the path.",
 "draft":"""# Run one bank from either spring.
routine tend heading
  if ripe heading
    gather heading
  end
  if empty_bed heading
    plant heading
  end
  while thirsty heading and has_water
    water heading
  end
end

routine sweep along across
  fill
  hop across
  hop across
  while not spring
    call tend across
    hop along
  end
end

if spring
  if column == 0
    call sweep east north
  else
    call sweep west south
  end
end
""",
 "python_draft":"""# Run one bank from either spring. Loop the last block to automate both.
def tend(heading):
    if ripe(heading):
        gather(heading)
    if empty_bed(heading):
        plant(heading)
    while thirsty(heading) and has_water():
        water(heading)

def sweep(along, across):
    fill()
    hop(across)
    hop(across)
    while not spring():
        tend(across)
        hop(along)

if spring():
    if column() == 0:
        sweep(east, north)
    else:
        sweep(west, south)
""",
}
const ALDER_CROSSING := {
 "id":"alder_crossing", "name":"Alder Crossing", "practice":true,
 "rows":[".BXX#", "~...B", "##.#.", "...~.", "BXB##"],
 "hint":"The south bank takes four doses and the north takes six. Tend the bank by your spring, then take the central crossing to the other one.",
 "draft":"""# Harvest the bank by your spring, then cross to the next one.
routine tend heading
  if empty_bed heading
    plant heading
  end
  while thirsty heading and has_water
    water heading
  end
end

routine collect heading
  while growing heading
    wait
  end
  if ripe heading
    gather heading
  end
end

routine south_bank
  repeat 3
    hop west
    call tend south
  end
  repeat 2
    call collect south
    hop east
  end
  call collect south
  hop north
  hop north
  hop west
  hop west
end

routine north_bank
  repeat 3
    hop east
    call tend north
  end
  call tend east
  call collect east
  call collect north
  repeat 2
    hop west
    call collect north
  end
  hop east
  hop south
  hop south
  hop east
end

if spring
  fill
  if row == 3
    call south_bank
  else
    call north_bank
  end
end
""",
 "python_draft":"""# Harvest the bank by your spring, then cross to the next one.
def tend(heading):
    if empty_bed(heading):
        plant(heading)
    while thirsty(heading) and has_water():
        water(heading)

def collect(heading):
    while growing(heading):
        wait()
    if ripe(heading):
        gather(heading)

def south_bank():
    for _ in range(3):
        hop(west)
        tend(south)
    for _ in range(2):
        collect(south)
        hop(east)
    collect(south)
    hop(north)
    hop(north)
    hop(west)
    hop(west)

def north_bank():
    for _ in range(3):
        hop(east)
        tend(north)
    tend(east)
    collect(east)
    collect(north)
    for _ in range(2):
        hop(west)
        collect(north)
    hop(east)
    hop(south)
    hop(south)
    hop(east)

if spring():
    fill()
    if row() == 3:
        south_bank()
    else:
        north_bank()
""",
}
const GARDENS := PUZZLES + [OPEN_NURSERY, WILLOW_NURSERY, LOTUS_MARSH, STONE_RING_NURSERY, ALDER_CROSSING]
const DIRECTIONS = {"north":Vector2i(0,-1), "east":Vector2i(1,0), "south":Vector2i(0,1), "west":Vector2i(-1,0)}
const CONDITIONS := ["always", "spring", "has_water", "empty_bed", "lily", "thirsty", "growing", "ripe", "has_reach_tool", "has_harvest_hook"]
const NUMERIC_SENSORS := ["water_level", "tank_capacity", "row", "column", "harvest_count", "action_count", "harvest_target"]
const COMPARISONS := ["<", "<=", "==", "!=", ">=", ">"]
const NEIGHBOR_ACTIONS := ["plant", "water", "gather"]
const LOTUS_BED := "X"
const SEEDBEDS := ["B", LOTUS_BED]
const PLOT_DOSES := {"B":1, "L":1, "H":2, LOTUS_BED:2}
const EMPTY_BED := "Empty bed"
const CAPACITY = 3
const RESERVOIR_CAPACITY := 6
const DEFAULT_HARVEST_TARGET := 32
const MAX_HARVEST_TARGET := 999
const MAX_STEPS = 256
const MAX_WHILE_ITERATIONS := 16
const MAX_FOR_ITERATIONS := 16
const MAX_COMPUTATION_STEPS := MAX_STEPS * MAX_WHILE_ITERATIONS
const MIN_VALUE := -2147483648
const MAX_VALUE := 2147483647
const MAX_OUTPUT_MESSAGES := 32
const MAX_OUTPUT_LENGTH := 1024
const PYTHON_COMPILER := "res://scripts/activities/garden_python.py"
var rows: Array = []
var plants: Dictionary = {}
var practice := false
var cell := Vector2i.ZERO
var tank := 0
var water_capacity := CAPACITY
var reach_tool := false
var harvest_hook := false
var turn := 0
var harvested := 0
var starting_turn := 0
var starting_harvest := 0
var run_water_used := 0
var run_fills := 0
var harvest_target := DEFAULT_HARVEST_TARGET
var runtime_error := ""
var runtime_error_line := -1
var loop_entries: Dictionary = {}
var output: Array[Dictionary] = []
var variables: Dictionary = {}
var local_frames: Array[Dictionary] = []
var call_revision := 0
var variable_revision := 0
var module_revision := 0

static func _instruction_count(instructions: Array) -> int:
 # A scope used only to track a call does not consume the program's instruction budget.
 var count := 0
 for instruction: Dictionary in instructions:
  if not instruction.has("debug_boundary"):
   count += 1
 return count

static func compile(source: String, case_sensitive := false, details: Dictionary = {}, track_calls := false) -> Dictionary:
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
  var detail: Dictionary = details.get(str(index), {})
  if command == "routine":
   if blocks.size() != 1:
    return _error(index, "Define routines at the top level of the program.")
   if words.size() < 2 or not words[1].is_valid_ascii_identifier():
    return _error(index, "Use routine NAME with letters, digits, or underscores. Start the name with a letter or underscore.")
   if routines.has(words[1]):
    return _error(index, "Routine %s is already defined." % words[1])
   var value_parameters: Dictionary = detail.get("value_parameters", {})
   var direction_parameters := PackedStringArray()
   for parameter in words.slice(2):
    if not parameter.is_valid_ascii_identifier() or DIRECTIONS.has(parameter) or parameter in ["not", "and", "or"]:
     return _error(index, "Use a parameter name like heading or return_path.")
    if parameter in parameters:
     return _error(index, "Parameter %s is already listed." % parameter)
    parameters.append(parameter)
    if not value_parameters.has(parameter):
     direction_parameters.append(parameter)
   blocks.append({"steps":[], "routine":words[1], "line":index, "local_scope":detail.get("local_scope", false),
                  "parameters":parameters, "value_parameters":value_parameters})
   parameters = direction_parameters
   continue
  if command in ["repeat", "if", "while"] or (command == "for" and detail.has("range")):
   var block_limit := 6 if blocks.size() > 1 and blocks[1].has("routine") else 5
   if blocks.size() >= block_limit:
    return _error(index, "Nest up to four condition and loop blocks.")
   if command == "repeat":
    if words.size() != 2 or not words[1].is_valid_int() or int(words[1]) not in range(1, 17):
     return _error(index, "Use repeat 1–16.")
    blocks.append({"steps":[], "times":int(words[1]), "line":index})
   elif command == "for":
    blocks.append({"steps":[], "range":detail.range, "line":index, "loop":true})
   else:
    var test: Variant = detail.get("test")
    if test == null:
     var expression := _parse_condition(words.slice(1), parameters)
     if expression.has("error"):
      return _error(index, expression.error)
     test = expression.clauses
    blocks.append({"steps":[], "test":test, "line":index, "loop":command == "while"})
   continue
  if command == "else":
   if words.size() != 1:
    return _error(index, "Put else on its own line.")
   var branch: Dictionary = blocks.back()
   if not branch.has("test") or branch.loop or branch.has("then_steps"):
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
    var returns_value := _resolve_returns(inner.steps)
    routines[inner.routine] = {"steps":inner.steps, "parameters":inner.parameters,
                              "value_parameters":inner.value_parameters, "scope":inner.local_scope or returns_value}
    parameters = PackedStringArray()
    continue
   var outer: Array = blocks.back().steps
   if inner.has("test") or inner.has("range"):
    var has_else := inner.has("then_steps")
    var is_loop: bool = inner.loop
    var kind := "for" if inner.has("range") else ("while" if is_loop else "if")
    if inner.steps.is_empty():
     if has_else:
      return _error(inner.else_line, "Add at least one command after else.")
     return _error(inner.line, "Add at least one command inside this %s block." % kind)
    var then_steps: Array = inner.get("then_steps", inner.steps)
    var else_steps: Array = inner.steps if has_else else []
    var skip := then_steps.size() + int(has_else or is_loop)
    var count := _instruction_count(outer) + 1 + _instruction_count(then_steps) + int(has_else or is_loop) + _instruction_count(else_steps)
    if count > MAX_STEPS:
     return _error(index, "This %s block exceeds the 256-instruction limit." % kind)
    # Relative jumps still work when a repeat or routine copies these instructions.
    var header := {"skip":skip, "line":inner.line}
    if inner.has("range"):
     header.range = inner.range
    else:
     header.test = inner.test
     header.loop = is_loop
    outer.append(header)
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
   if _instruction_count(outer) + _instruction_count(inner.steps) * int(inner.times) > MAX_STEPS:
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
    var kind := " direction" if routine.value_parameters.is_empty() else ""
    return _error(index, "Routine %s expects %d%s %s." % [words[1], targets.size(), kind, unit])
   var capture: Dictionary = detail.get("capture", {})
   var keeps_scope: bool = routine.scope or not capture.is_empty()
   if _instruction_count(steps) + _instruction_count(routine.steps) + 2 * int(keeps_scope) > MAX_STEPS:
    return _error(index, "This call expands the program beyond 256 instructions.")
   var bindings: Dictionary = {}
   var value_args: Dictionary = detail.get("value_args", {})
   var inputs: Array[Dictionary] = []
   for argument_index in arguments.size():
    var parameter := targets[argument_index]
    if routine.value_parameters.has(parameter):
     var key := str(argument_index)
     if not value_args.has(key):
      return _error(index, "Supply a value for parameter %s." % parameter)
     inputs.append({"name":parameter, "kind":routine.value_parameters[parameter], "value":value_args[key]})
     continue
    var argument := arguments[argument_index]
    if not _is_direction(argument, parameters):
     return _error(index, "Argument %s needs a compass direction or a routine parameter." % parameter)
    bindings[parameter] = argument
   var debug_scope := track_calls and not keeps_scope
   if keeps_scope or debug_scope:
    var enter := {"enter_scope":words[1], "inputs":inputs, "line":index}
    if debug_scope:
     enter.debug_boundary = true
    steps.append(enter)
   steps.append_array(_bind_directions(routine.steps, bindings))
   if keeps_scope or debug_scope:
    var leave := {"leave_scope":true, "capture":capture, "line":index}
    if debug_scope:
     leave.debug_boundary = true
    steps.append(leave)
   continue
  var instruction := {"command":command, "direction":"", "line":index}
  if (command == "diagnostic" and detail.has("output")) or (command == "assign" and detail.has("assign")):
   instruction = detail.merged({"line":index})
  elif command == "hop":
   if words.size() != 2 or not _is_direction(words[1], parameters):
    return _error(index, "Use hop with north, east, south, west, or a routine parameter.")
   instruction.direction = words[1]
  elif command in NEIGHBOR_ACTIONS and words.size() == 2:
   if not _is_direction(words[1], parameters):
    return _error(index, "Use a compass direction or a routine parameter with %s." % command)
   instruction.direction = words[1]
  elif command in ["break", "continue"]:
   if words.size() != 1 or not blocks.any(func(block): return block.has("times") or block.get("loop", false)):
    return _error(index, "Put %s on its own line inside a loop." % command)
   instruction = {"loop_control":command, "line":index}
  elif command == "return" and detail.has("return"):
   if blocks.size() < 2 or not blocks[1].has("routine"):
    return _error(index, "Use return inside a function.")
   instruction = detail.merged({"line":index})
  elif words.size() != 1 or command not in ["fill", "plant", "water", "wait", "gather"]:
   return _error(index, "Use hop, fill, plant, water, wait, gather, repeat, routine, call, if, while, break, or continue.")
  if _instruction_count(steps) >= MAX_STEPS:
   return _error(index, "Programs can contain up to 256 instructions after expansion.")
  steps.append(instruction)
 if blocks.size() > 1:
  var unclosed: Dictionary = blocks.back()
  var kind := "routine" if unclosed.has("routine") else "repeat block"
  if unclosed.has("test"):
   kind = "while block" if unclosed.loop else "if block"
  elif unclosed.has("range"):
   kind = "for block"
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
 var result := compile(lowered.source, true, lowered.get("details", {}), true)
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

static func _resolve_returns(body: Array) -> bool:
 var returns_value := false
 for index in body.size():
  var instruction: Dictionary = body[index]
  if instruction.has("return"):
   # Relative bounds keep the return inside its own call when the body is copied.
   var resolved := {"from_start":index, "return_offset":body.size() - index, "line":instruction.line}
   if instruction.has("value"):
    resolved.value = instruction.value
    returns_value = true
   body[index] = resolved
 return returns_value

static func _append_loop_body(outer: Array, body: Array, loop_end: int, has_loop_header := false) -> void:
 var start := outer.size()
 for instruction: Dictionary in body:
  if not instruction.has("loop_control"):
   outer.append(instruction)
   continue
  # Continue reaches the next repeat copy or the loop's back edge.
  var leaving: bool = instruction.loop_control == "break"
  var destination := loop_end if leaving else start + body.size()
  var jump := {"skip":destination - outer.size() - 1, "line":instruction.line}
  if leaving and has_loop_header:
   jump.leave_loop = outer.size() - start + 1
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
  elif instruction.has("test"):
   if instruction.test is Dictionary:
    _bind_expression(instruction.test, bindings)
   else:
    for clause: Array in instruction.test:
     for test: Dictionary in clause:
      _bind_expression(test, bindings)
  elif instruction.has("output"):
   for value: Dictionary in instruction.output:
    _bind_expression(value, bindings)
  elif instruction.has("range"):
   _bind_expression(instruction.range, bindings)
  elif instruction.has("inputs"):
   for input: Dictionary in instruction.inputs:
    _bind_expression(input.value, bindings)
  elif instruction.has("value"):
   _bind_expression(instruction.value, bindings)
  expanded.append(instruction)
 return expanded

static func _bind_expression(value: Dictionary, bindings: Dictionary) -> void:
 if value.has("direction"):
  value.direction = bindings.get(value.direction, value.direction)
 for child: Dictionary in value.get("args", []):
  _bind_expression(child, bindings)

static func _is_numeric_operand(word: String) -> bool:
 return word in NUMERIC_SENSORS or (word.length() <= 11 and word.is_valid_int() and int(word) >= MIN_VALUE and int(word) <= MAX_VALUE)

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
  if condition in NUMERIC_SENSORS or condition.is_valid_int():
   if not _is_numeric_operand(condition) or index + 1 >= words.size() or words[index] not in COMPARISONS or not _is_numeric_operand(words[index + 1]):
    return {"error":"Compare whole numbers or numeric readings. Try water_level >= 2."}
   clause.append({"left":condition, "comparison":words[index], "right":words[index + 1], "negated":negated})
   index += 2
  else:
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
    if condition in ["has_reach_tool", "has_harvest_hook"]:
     return {"error":"Use %s without a direction." % condition}
    if condition == "always":
     return {"error":"Use always without a direction."}
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

func load_puzzle(index: int, has_reservoir := false, has_reach_tool := false, has_harvest_hook := false) -> void:
 var item: Dictionary = GARDENS[index]
 rows = item.rows
 practice = item.get("practice", false)
 plants.clear()
 tank = 0
 configure_nursery_tools(has_reservoir, has_reach_tool, has_harvest_hook)
 turn = 0
 harvested = 0
 reset_program()
 for y in rows.size():
  for x in rows[y].length():
   var location := Vector2i(x, y)
   var plot := tile(location)
   if plot == "~":
    cell = location
   elif PLOT_DOSES.has(plot):
    var planted := plot not in SEEDBEDS
    plants[location] = {"need":PLOT_DOSES[plot] if planted else 0, "ready":-1, "harvested":false, "planted":planted}

func reset_program() -> void:
 starting_turn = turn
 starting_harvest = harvested
 run_water_used = 0
 run_fills = 0
 runtime_error = ""
 runtime_error_line = -1
 loop_entries.clear()
 output.clear()
 variables.clear()
 local_frames.clear()
 call_revision = 0
 variable_revision = 0
 module_revision = 0

func run_harvest_count() -> int:
 return harvested - starting_harvest

func run_action_count() -> int:
 return turn - starting_turn

func inspect_variables() -> Dictionary:
 var visible_values := variables.duplicate()
 for frame: Dictionary in local_frames:
  var prefix := local_variable_prefix(frame.function)
  for variable: String in frame.locals:
   visible_values[prefix + variable] = frame.locals[variable]
 return visible_values

static func local_variable_prefix(function_name: String) -> String:
 return "%s() · " % function_name

func inspect_call_stack() -> Array[Dictionary]:
 var calls: Array[Dictionary] = []
 for index in range(local_frames.size() - 1, -1, -1):
  var frame := local_frames[index]
  calls.append({"function":frame.function, "line":frame.line})
 return calls

func configure_nursery_tools(has_reservoir: bool, has_reach_tool: bool, has_harvest_hook: bool) -> void:
 water_capacity = RESERVOIR_CAPACITY if practice and has_reservoir else CAPACITY
 reach_tool = practice and has_reach_tool
 harvest_hook = practice and has_harvest_hook
 tank = mini(tank, water_capacity)

func copy_board() -> RefCounted:
 var copy = get_script().new()
 copy.rows = rows
 copy.plants = plants.duplicate(true)
 copy.practice = practice
 copy.cell = cell
 copy.tank = tank
 copy.water_capacity = water_capacity
 copy.reach_tool = reach_tool
 copy.harvest_hook = harvest_hook
 copy.turn = turn
 copy.harvested = harvested
 copy.starting_turn = starting_turn
 copy.starting_harvest = starting_harvest
 copy.run_water_used = run_water_used
 copy.run_fills = run_fills
 copy.harvest_target = harvest_target
 return copy

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
 return not practice and harvested == plants.size()

func next_action_index(instructions: Array, first: int) -> int:
 var index := first
 var computed := 0
 while index < instructions.size() and runtime_error.is_empty():
  var instruction: Dictionary = instructions[index]
  var debug_boundary := instruction.has("debug_boundary")
  if not debug_boundary:
   if computed >= MAX_COMPUTATION_STEPS:
    runtime_error = "The program computed too many steps without doing an action."
    runtime_error_line = instruction.line
    break
   computed += 1
  if instruction.has("back"):
   index -= int(instruction.back)
   continue
  if instruction.has("return_offset"):
   if instruction.has("value"):
    var value: Variant = _expression_value(instruction.value)
    if value == null:
     runtime_error_line = instruction.line
     break
    local_frames.back().result = value
   var start := index - int(instruction.from_start)
   var end := index + int(instruction.return_offset)
   for header: int in loop_entries.keys():
    if header >= start and header < end:
     loop_entries.erase(header)
   index = end
   continue
  if instruction.has("enter_scope"):
   # Evaluate each argument in the caller's scope before exposing the new locals.
   var locals := _call_values(instruction.inputs)
   if not runtime_error.is_empty():
    runtime_error_line = instruction.line
    break
   local_frames.append({"function":instruction.enter_scope, "line":instruction.line, "locals":locals, "revision":0})
   call_revision += 1
   if not debug_boundary:
    variable_revision += 1
   index += 1
   continue
  if instruction.has("leave_scope"):
   var frame: Dictionary = local_frames.pop_back()
   call_revision += 1
   if not debug_boundary:
    variable_revision += 1
   var capture: Dictionary = instruction.capture
   if not capture.is_empty():
    var value: Variant = frame.get("result")
    if value == null:
     runtime_error = "Function '%s' returned without a number or Boolean." % frame.function
     runtime_error_line = instruction.line
     break
    _set_variable(capture.name, value, capture.local)
   index += 1
   continue
  if instruction.has("output"):
   _append_output(instruction)
   if not runtime_error.is_empty():
    runtime_error_line = instruction.line
   index += 1
   continue
  if instruction.has("assign"):
   var variable: String = instruction["assign"]
   var value: Variant = _expression_value(instruction.value)
   if value == null:
    runtime_error_line = instruction.line
    break
   _set_variable(variable, value, instruction.get("local", false))
   index += 1
   continue
  if not instruction.has("skip"):
   if not practice and turn >= MAX_STEPS:
    runtime_error = "The program reached its %d-action limit." % MAX_STEPS
    runtime_error_line = instruction.line
   break
  if instruction.has("leave_loop"):
   loop_entries.erase(index - int(instruction.leave_loop))
  var passes := false
  if instruction.has("range"):
   passes = _next_counted_iteration(index, instruction.range)
   if not runtime_error.is_empty():
    runtime_error_line = instruction.line
    break
  elif instruction.has("test"):
   if instruction.test is Dictionary:
    var value: Variant = _expression_value(instruction.test)
    if value == null:
     runtime_error_line = instruction.line
     break
    passes = bool(value)
   else:
    passes = _meets_any_clause(instruction.test)
  if instruction.get("loop", false):
   if passes:
    var revision: int = module_revision if local_frames.is_empty() else local_frames.back().revision
    var entry: Dictionary = loop_entries.get(index, {"turn":-1, "revision":-1, "iterations":0})
    if entry.turn == turn and entry.revision == revision:
     runtime_error = "This while loop came back without doing an action."
    elif not practice and entry.iterations >= MAX_WHILE_ITERATIONS:
     runtime_error = "This while loop reached its %d-iteration limit." % MAX_WHILE_ITERATIONS
    if not runtime_error.is_empty():
     runtime_error_line = instruction.line
     break
    loop_entries[index] = {"turn":turn, "revision":revision, "iterations":int(entry.iterations) + 1}
   else:
    loop_entries.erase(index)
  index += 1 if passes else 1 + int(instruction.skip)
 return index if runtime_error.is_empty() else instructions.size()

func _call_values(inputs: Array) -> Dictionary:
 var locals: Dictionary = {}
 for input: Dictionary in inputs:
  var value: Variant = _expression_value(input.value)
  if value == null:
   return {}
  var is_flag: bool = input.kind == "bool"
  if typeof(value) != (TYPE_BOOL if is_flag else TYPE_INT):
   var expected := "True or False" if is_flag else "a whole number"
   runtime_error = "Argument '%s' needs %s." % [input.name, expected]
   return {}
  locals[input.name] = value
 return locals

func _variable_store(local: bool) -> Dictionary:
 return local_frames.back().locals if local else variables

func _set_variable(variable: String, value: Variant, local: bool) -> void:
 var store := _variable_store(local)
 if store.has(variable) and is_same(store[variable], value):
  return
 store[variable] = value
 variable_revision += 1
 if local:
  local_frames.back().revision += 1
 else:
  module_revision += 1

func _next_counted_iteration(index: int, spec: Dictionary) -> bool:
 var entry: Dictionary = loop_entries.get(index, {})
 if entry.is_empty():
  var args: Array[int] = []
  for operand: Dictionary in spec.args:
   var value: Variant = _expression_value(operand)
   if value == null:
    return false
   args.append(int(value))
  var start := 0 if args.size() == 1 else args[0]
  var stop := args[0] if args.size() == 1 else args[1]
  var stride := args[2] if args.size() == 3 else 1
  if stride == 0:
   runtime_error = "Use a nonzero step in range()."
   return false
  # A value at position 16 still inside the range would require a 17th iteration.
  var next_after_limit := start + stride * MAX_FOR_ITERATIONS
  if _in_range(next_after_limit, stop, stride):
   runtime_error = "Use a range with at most %d iterations." % MAX_FOR_ITERATIONS
   return false
  entry = {"next":start, "stop":stop, "stride":stride}

 var item: int = entry.next
 if not _in_range(item, entry.stop, entry.stride):
  loop_entries.erase(index)
  return false
 if not spec.target.is_empty():
  _set_variable(spec.target, item, spec.get("local", false))
 entry.next = item + int(entry.stride)
 loop_entries[index] = entry
 return true

static func _in_range(value: int, stop: int, stride: int) -> bool:
 return value < stop if stride > 0 else value > stop

func _append_output(instruction: Dictionary) -> void:
 var fields := PackedStringArray()
 for expression: Dictionary in instruction.output:
  var value: Variant = _expression_value(expression)
  if value == null:
   return
  fields.append(python_value_text(value))
 var message := " ".join(fields)
 if message.length() > MAX_OUTPUT_LENGTH:
  message = message.left(MAX_OUTPUT_LENGTH - 1) + "…"
 if output.size() >= MAX_OUTPUT_MESSAGES:
  output.pop_front()
 output.append({"line":instruction.line, "turn":turn, "text":message})

static func python_value_text(value: Variant) -> String:
 return ("True" if value else "False") if value is bool else str(value)

func _meets_any_clause(clauses: Array) -> bool:
 for clause: Array in clauses:
  var matches := true
  for test: Dictionary in clause:
   var passes := _compare_numbers(_read_number(test.left), _read_number(test.right), test.comparison) if test.has("comparison") else _meets_condition(test.condition, test.direction)
   if passes == test.negated:
    matches = false
    break
  if matches:
   return true
 return false

func _read_number(operand: String) -> int:
 match operand:
  "water_level":
   return tank
  "tank_capacity":
   return water_capacity
  "row":
   return cell.y
  "column":
   return cell.x
  "harvest_count":
   return run_harvest_count()
  "action_count":
   return run_action_count()
  "harvest_target":
   return harvest_target if practice else plants.size()
  _:
   return int(operand)

static func _compare_numbers(left: int, right: int, comparison: String) -> bool:
 match comparison:
  "<":
   return left < right
  "<=":
   return left <= right
  "==":
   return left == right
  "!=":
   return left != right
  ">=":
   return left >= right
  ">":
   return left > right
  _:
   return false

func _expression_value(expression: Dictionary) -> Variant:
 var op: String = expression.op
 match op:
  "literal":
   # JSON decodes a numeric literal as a float. Python literals here are bounded integers.
   return expression.value if expression.value is bool else int(expression.value)
  "text":
   return expression.value
  "direction":
   return expression.direction
  "variable":
   var local: bool = expression.get("local", false)
   var store := _variable_store(local)
   if store.has(expression.name):
    return store[expression.name]
   var label := "Local variable" if local else "Variable"
   runtime_error = "%s '%s' has no value yet." % [label, expression.name]
   return null
  "sensor":
   if expression.name in NUMERIC_SENSORS:
    return _read_number(expression.name)
   return _meets_condition(expression.name, expression.direction)

 var args: Array = expression.args
 var left: Variant = _expression_value(args[0])
 if left == null:
  return null
 match op:
  "not":
   return not bool(left)
  "and", "or":
   for index in range(1, args.size()):
    if bool(left) == (op == "or"):
     return left
    left = _expression_value(args[index])
    if left == null:
     return null
   return left
  "compare":
   for index in expression.operators.size():
    var right: Variant = _expression_value(args[index + 1])
    if right == null:
     return null
    if not _compare_numbers(int(left), int(right), expression.operators[index]):
     return false
    left = right
   return true
  "+", "-":
   var right: Variant = _expression_value(args[1])
   if right == null:
    return null
   var result := int(left) + int(right) if op == "+" else int(left) - int(right)
   if result >= MIN_VALUE and result <= MAX_VALUE:
    return result
   runtime_error = "The result is outside the 32-bit integer range."
   return null
 return null

func _meets_condition(condition: String, direction: String) -> bool:
 var location := cell
 if not direction.is_empty():
  location += DIRECTIONS[direction]
 match condition:
  "always":
   return true
  "clear":
   return tile(location) != "#"
  "spring":
   return tile(location) == "~"
  "has_water":
   return tank > 0
  "has_reach_tool":
   return reach_tool
  "has_harvest_hook":
   return harvest_hook
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
 var target := cell
 var direction: String = action.get("direction", "")
 if action.command in NEIGHBOR_ACTIONS and not direction.is_empty():
  if action.command == "gather":
   if not harvest_hook:
    return "Gathering from a neighboring bed requires the harvest hook."
  elif not reach_tool:
   return "Tending a neighboring bed requires the reach tool."
  target += DIRECTIONS[direction]
 var plant: Dictionary = plants.get(target, {})
 var plot := tile(target)
 match action.command:
  "hop":
   var next: Vector2i = cell + DIRECTIONS[action.direction]
   if tile(next) == "#":
    return "A stone or the bank blocks this hop."
   cell = next
  "fill":
   if tile(cell) != "~":
    return "Fill at the spring."
   tank = water_capacity
   run_fills += 1
  "plant":
   if plant.get("planted", true):
    return "Plant on a prepared empty bed."
   plant.planted = true
   plant.need = PLOT_DOSES[plot]
  "water":
   if not plant.get("planted", true):
    return "Plant this bed before watering it."
   if plant.is_empty() or plant.harvested or plant.need == 0:
    return "This plot does not need water."
   if tank == 0:
    return "The tank is empty. Visit the spring."
   tank -= 1
   run_water_used += 1
   plant.need -= 1
   if plant.need == 0:
    plant.ready = turn + (4 if plot == LOTUS_BED else 2)
  "gather":
   if plant_status(target) != "Ripe":
    if plot == LOTUS_BED:
     return "Gather a ripe lotus. After its final watering, give it three more actions."
    return "Gather a ripe lily. A freshly watered lily needs one more turn."
   if practice and plot in SEEDBEDS:
    plant.planted = false
    plant.ready = -1
   else:
    plant.harvested = true
   harvested += 3 if plot == LOTUS_BED else 1
 turn += 1
 return ""
