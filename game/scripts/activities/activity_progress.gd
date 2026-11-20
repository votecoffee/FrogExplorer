extends RefCounted
## Drafts, completion markers and race records have independent files so a
## save for one activity cannot overwrite another activity's progress.

const DIRECTORY := "user://activity-progress-v1"
const Programs = preload("res://scripts/activities/garden_program.gd")
const COURSES := ["car_circuit", "balloon_rings"]

var best: Dictionary = {}
var drafts: Dictionary = {}
var solved: Dictionary = {}
var folder := ""
var pending: Dictionary = {}

func load_from(path: String) -> void:
 folder = ProjectSettings.globalize_path(path)
 if not DirAccess.dir_exists_absolute(folder):
  return
 var names := DirAccess.get_files_at(folder)
 for course: String in COURSES:
  var prefix := "best-" + course + "-"
  for name in names:
   if not name.begins_with(prefix) or not name.ends_with(".ms"):
    continue
   var value := name.trim_prefix(prefix).trim_suffix(".ms")
   if not value.is_valid_int() or int(value) <= 0:
    continue
   best[course] = minf(float(best.get(course, INF)), int(value) / 1000.0)
 for puzzle in Programs.PUZZLES:
  var id: String = puzzle.id
  var draft := folder.path_join("draft-" + id + ".txt")
  if FileAccess.file_exists(draft):
   drafts[id] = FileAccess.get_file_as_string(draft)
  if FileAccess.file_exists(folder.path_join("solved-" + id)):
   solved[id] = true

func record_time(course: String, seconds: float) -> Error:
 if course not in COURSES or not is_finite(seconds) or seconds <= 0:
  return ERR_INVALID_PARAMETER
 var milliseconds := maxi(1, roundi(seconds * 1000))
 var value := milliseconds / 1000.0
 if value >= float(best.get(course, INF)):
  return OK
 best[course] = value
 # Each record has a distinct key. Two instances can finish a race at the
 # same time and both results contribute to the minimum on the next load.
 return _save("best-%s-%d.ms" % [course, milliseconds], "")

func edit_draft(id: String, text: String) -> Error:
 drafts[id] = text
 return _save("draft-" + id + ".txt", text)

func complete_puzzle(id: String) -> Error:
 solved[id] = true
 return _save("solved-" + id, "")

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
