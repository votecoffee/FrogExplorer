extends RefCounted
## Drafts, completion markers and race records have independent files so a
## save for one activity cannot overwrite another activity's progress.

const DIRECTORY := "user://activity-progress-v1"
const Programs = preload("res://scripts/activities/garden_program.gd")
const COURSES := ["car_circuit", "balloon_rings"]
const WILLOW_COST := 12
const WILLOW_MARKER := "nursery-willow-unlocked"
const RESERVOIR_COST := 24
const RESERVOIR_MARKER := "nursery-reservoir-unlocked"
const REACH_TOOL_COST := 32
const REACH_TOOL_MARKER := "nursery-reach-tool-unlocked"
const LOTUS_MARSH_COST := 40
const LOTUS_MARSH_MARKER := "nursery-lotus-marsh-unlocked"
const NURSERY_UPGRADE_COSTS := {
 WILLOW_MARKER:WILLOW_COST, RESERVOIR_MARKER:RESERVOIR_COST, REACH_TOOL_MARKER:REACH_TOOL_COST,
 LOTUS_MARSH_MARKER:LOTUS_MARSH_COST,
}
const NURSERY_UNLOCKS := {Programs.WILLOW_NURSERY.id:WILLOW_MARKER, Programs.LOTUS_MARSH.id:LOTUS_MARSH_MARKER}
const NURSERY_TALLY_PREFIX := "nursery-yield-"
const NURSERY_TALLY_SUFFIX := ".txt"

var best: Dictionary = {}
var split_records: Dictionary = {}
var drafts: Dictionary = {}
var python_drafts: Dictionary = {}
var solved: Dictionary = {}
var garden_best: Dictionary = {}
var garden_best_programs: Dictionary = {}
var garden_best_python: Dictionary = {}
var nursery_upgrades: Dictionary = {}
var nursery_harvested := 0
var session_harvests := 0
var nursery_tally := ""
var folder := ""
var pending: Dictionary = {}

func load_from(path: String) -> void:
 folder = ProjectSettings.globalize_path(path)
 session_harvests = 0
 nursery_tally = ""
 nursery_harvested = 0
 nursery_upgrades.clear()
 if not DirAccess.dir_exists_absolute(folder):
  return
 var names := DirAccess.get_files_at(folder)
 _load_nursery(names)
 for course: String in COURSES:
  var prefix := "best-" + course + "-"
  for name in names:
   if not name.begins_with(prefix) or not name.ends_with(".ms"):
    continue
   var record := name.trim_prefix(prefix).trim_suffix(".ms").split("-", true, 1)
   if not record[0].is_valid_int() or int(record[0]) <= 0:
    continue
   var milliseconds := int(record[0])
   best[course] = minf(float(best.get(course, INF)), milliseconds / 1000.0)
   if record.size() == 2 and record[1].length() == 64:
    var data := JSON.new()
    if data.parse(FileAccess.get_file_as_string(folder.path_join(name))) == OK and data.data is Array:
     _remember_splits(course, record[1], data.data, milliseconds)
 for puzzle in Programs.GARDENS:
  var id: String = puzzle.id
  var draft := folder.path_join("draft-" + id + ".txt")
  if FileAccess.file_exists(draft):
   drafts[id] = FileAccess.get_file_as_string(draft)
  var python_draft := folder.path_join("draft-" + id + ".py")
  if FileAccess.file_exists(python_draft):
   python_drafts[id] = FileAccess.get_file_as_string(python_draft)
  if puzzle.get("practice", false):
   continue
  var marker := "solved-" + id
  if marker in names:
   solved[id] = true
  var prefix := marker + "-"
  var best_actions := Programs.MAX_STEPS + 1
  var best_file := ""
  for name in names:
   if not name.begins_with(prefix):
    continue
   var count := name.trim_prefix(prefix)
   if count.is_valid_int() and int(count) in range(1, best_actions):
    best_actions = int(count)
    best_file = name
  if not best_file.is_empty():
   solved[id] = true
   garden_best[id] = best_actions
   var program := FileAccess.get_file_as_string(folder.path_join(best_file))
   garden_best_python.erase(id)
   if program.begins_with("{"):
    var record: Variant = JSON.parse_string(program)
    if record is Dictionary and record.get("format") == "python" and record.get("source") is String:
     program = record.source
     garden_best_python[id] = true
   if program.is_empty():
    garden_best_programs.erase(id)
   else:
    garden_best_programs[id] = program

func comparison(course: String, layout: String, checkpoints: int) -> Array:
 return split_records.get(_split_key(course, layout, checkpoints), [])

func record_run(course: String, seconds: float, layout: String, splits: PackedFloat64Array) -> Error:
 if course not in COURSES or not is_finite(seconds) or seconds <= 0 or splits.is_empty():
  return ERR_INVALID_PARAMETER
 var milliseconds := maxi(1, roundi(seconds * 1000))
 var times_ms: Array[int] = []
 for split in splits:
  times_ms.append(roundi(split * 1000))
 times_ms[-1] = milliseconds
 if not _remember_splits(course, layout, times_ms, milliseconds):
  return OK
 best[course] = minf(float(best.get(course, INF)), milliseconds / 1000.0)
 # Layout-specific runs can coexist with older time-only records and with
 # finishes saved by another instance of the game.
 return _save("best-%s-%d-%s.ms" % [course, milliseconds, layout], JSON.stringify(times_ms))

func _remember_splits(course: String, layout: String, times_ms: Array, milliseconds: int) -> bool:
 if times_ms.is_empty():
  return false
 var previous := 0
 var validated: Array[int] = []
 for value in times_ms:
  if not (value is int or value is float) or value < previous or value > milliseconds or value != int(value):
   return false
  previous = int(value)
  validated.append(previous)
 if previous != milliseconds:
  return false
 var key := _split_key(course, layout, validated.size())
 if split_records.has(key) and split_records[key][-1] <= milliseconds:
  return false
 split_records[key] = validated
 return true

func _split_key(course: String, layout: String, checkpoints: int) -> String:
 return "%s/%s/%d" % [course, layout, checkpoints]

func earned_lilies() -> int:
 var total := 0
 for puzzle in Programs.PUZZLES:
  if solved.has(puzzle.id):
   total += Programs.puzzle_lilies(puzzle)
 return total

func lesson_available(puzzle: Dictionary, lilies: int) -> bool:
 var id: String = puzzle.id
 var upgrade: String = NURSERY_UNLOCKS.get(id, "")
 if not upgrade.is_empty():
  return has_nursery_upgrade(upgrade)
 return lilies >= int(puzzle.get("unlock_lilies", 0)) or solved.has(id) or drafts.has(id) or python_drafts.has(id)

func nursery_balance() -> int:
 var spent := 0
 for upgrade: String in nursery_upgrades:
  spent += NURSERY_UPGRADE_COSTS[upgrade]
 return maxi(0, nursery_harvested - spent)

func has_nursery_upgrade(upgrade: String) -> bool:
 return nursery_upgrades.has(upgrade)

func next_nursery_upgrade() -> String:
 for upgrade: String in NURSERY_UPGRADE_COSTS:
  if not has_nursery_upgrade(upgrade):
   return upgrade
 return ""

func record_nursery_harvest(yield_lilies := 1) -> Error:
 nursery_harvested += yield_lilies
 if folder.is_empty():
  return OK
 session_harvests += yield_lilies
 if nursery_tally.is_empty():
  # Each game session writes its own cumulative harvests.
  var key := "%d-%d-%d" % [roundi(Time.get_unix_time_from_system() * 1000), OS.get_process_id(), Time.get_ticks_usec()]
  nursery_tally = NURSERY_TALLY_PREFIX + key + NURSERY_TALLY_SUFFIX
 return _save(nursery_tally, str(session_harvests))

func refresh_nursery() -> Error:
 if folder.is_empty():
  return OK
 var error := flush()
 if error == OK:
  var names := DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(folder) else PackedStringArray()
  _load_nursery(names)
 return error

func buy_nursery_upgrade(upgrade: String) -> Error:
 var error := refresh_nursery()
 if error != OK or has_nursery_upgrade(upgrade):
  return error
 if upgrade.is_empty() or upgrade != next_nursery_upgrade() or nursery_balance() < int(NURSERY_UPGRADE_COSTS[upgrade]):
  return ERR_UNAVAILABLE
 if not folder.is_empty():
  # The same marker charges the balance once, even across game instances.
  var marker := folder.path_join(upgrade)
  error = _write(marker, "unlocked")
  if error != OK and not FileAccess.file_exists(marker):
   return error
 nursery_upgrades[upgrade] = true
 return OK

func _load_nursery(names: PackedStringArray) -> void:
 nursery_upgrades.clear()
 for upgrade: String in NURSERY_UPGRADE_COSTS:
  if upgrade in names:
   nursery_upgrades[upgrade] = true
 nursery_harvested = 0
 for name in names:
  if not name.begins_with(NURSERY_TALLY_PREFIX) or not name.ends_with(NURSERY_TALLY_SUFFIX):
   continue
  var tally := FileAccess.get_file_as_string(folder.path_join(name)).strip_edges()
  if tally.is_valid_int() and int(tally) > 0:
   nursery_harvested += int(tally)

func next_lesson(lilies: int) -> int:
 for index in Programs.PUZZLES.size():
  var item: Dictionary = Programs.PUZZLES[index]
  if not solved.has(item.id) and lesson_available(item, lilies):
   return index
 return -1

func edit_draft(id: String, text: String, python := false) -> Error:
 var saved := python_drafts if python else drafts
 saved[id] = text
 return _save("draft-" + id + (".py" if python else ".txt"), text)

func complete_puzzle(id: String, actions: int, program: String, python := false) -> Error:
 if actions <= 0 or actions > Programs.MAX_STEPS or program.is_empty():
  return ERR_INVALID_PARAMETER
 solved[id] = true
 var previous: int = garden_best.get(id, Programs.MAX_STEPS + 1)
 if actions > previous or (actions == previous and garden_best_programs.has(id)):
  return OK
 garden_best[id] = actions
 garden_best_programs[id] = program
 garden_best_python[id] = python
 # Store the source with its score so a different record cannot supply the code.
 var stored := JSON.stringify({"format":"python", "source":program}) if python else program
 return _save("solved-%s-%d" % [id, actions], stored)

func _save(name: String, text: String) -> Error:
 if folder.is_empty():
  return OK
 pending[name] = text
 return flush()

func flush() -> Error:
 if pending.is_empty():
  return OK
 var failure := DirAccess.make_dir_recursive_absolute(folder)
 if failure != OK:
  return failure
 for name in pending.keys():
  var result := _write(folder.path_join(name), pending[name])
  if result == OK:
   pending.erase(name)
  else:
   failure = result
 return failure

func _write(path: String, text: String) -> Error:
 # Write to a sibling and replace only after the entire file is on disk.
 var temporary := "%s.%d.%d.part" % [path, OS.get_process_id(), Time.get_ticks_usec()]
 var file := FileAccess.open(temporary, FileAccess.WRITE)
 if not file:
  return FileAccess.get_open_error()
 file.store_string(text)
 file.flush()
 var error := file.get_error()
 file.close()
 if error == OK:
  error = DirAccess.rename_absolute(temporary, path)
 if error != OK:
  DirAccess.remove_absolute(temporary)
 return error
