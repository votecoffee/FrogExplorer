extends PanelContainer

signal dismissed
const Programs = preload("res://scripts/activities/garden_program.gd")
const Progress = preload("res://scripts/activities/activity_progress.gd")
var hud: ExplorerHUD
var garden := Programs.new()
var world: ExplorerActivityWorld
var puzzle := -1
var progress: Progress
var draft_timer: Timer
var loaded_draft := ""
var source: CodeEdit
var status: Label
var board: GridContainer
var info: Label
var score: Label
var hint: Label
var chooser: OptionButton
var check_button: Button
var review_button: Button
var review_controls: VBoxContainer
var review_position: Label
var review_slider: HSlider
var run_button: Button
var step_button: Button
var stop_button: Button
var steps: Array = []
var offset := 0
var interval := 0.0
var running := false
var checked_source: Variant = null
var checked_actions: Array = []
var blocked_line := -1

func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 offset_left = 34
 offset_right = -34
 offset_top = 24
 offset_bottom = -24
 var outer := VBoxContainer.new()
 outer.add_theme_constant_override("separation", 10)
 add_child(outer)
 var top := HBoxContainer.new()
 outer.add_child(top)
 var title: Label = hud.label("Lily Code Garden", 26, Color("#f3ebb4"))
 title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 top.add_child(title)
 _button(top, "Close · Esc", _close)
 var pair := HBoxContainer.new()
 pair.size_flags_vertical = Control.SIZE_EXPAND_FILL
 pair.add_theme_constant_override("separation", 14)
 outer.add_child(pair)
 var left := VBoxContainer.new()
 left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 pair.add_child(left)
 var actions := HBoxContainer.new()
 left.add_child(actions)
 check_button = _button(actions, "Check", _check_code)
 check_button.tooltip_text = "Check the draft on a fresh board"
 run_button = _button(actions, "Run · Ctrl+Enter", _run)
 step_button = _button(actions, "Step · F10", _step)
 stop_button = _button(actions, "Stop", _stop)
 _button(actions, "Reset board", _reset)
 source = CodeEdit.new()
 source.size_flags_vertical = Control.SIZE_EXPAND_FILL
 source.gutters_draw_line_numbers = true
 source.gutters_draw_executing_lines = true
 source.highlight_current_line = true
 source.placeholder_text = "Type Pondbot commands here"
 draft_timer = Timer.new()
 draft_timer.one_shot = true
 draft_timer.wait_time = .65
 draft_timer.timeout.connect(flush_draft)
 add_child(draft_timer)
 source.text_changed.connect(_queue_save)
 source.add_theme_font_size_override("font_size", 18)
 var ink := CodeHighlighter.new()
 for word in ["hop", "fill", "water", "wait", "gather", "repeat", "end"]:
  ink.add_keyword_color(word, Color("#8bd5bc"))
 ink.add_color_region("#", "", Color("#a5ad99"), true)
 source.syntax_highlighter = ink
 left.add_child(source)
 var right := VBoxContainer.new()
 right.custom_minimum_size.x = 285
 right.add_theme_constant_override("separation", 9)
 pair.add_child(right)
 chooser = OptionButton.new()
 for item in Programs.PUZZLES:
  chooser.add_item(item.name + (" ✓" if progress.solved.has(item.id) else ""))
 chooser.item_selected.connect(_choose)
 right.add_child(chooser)
 info = hud.label("", 17, Color("#b9dccc"))
 right.add_child(info)
 score = hud.label("", 15, Color("#b9dccc"))
 score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 right.add_child(score)
 review_button = _button(right, "Review", _toggle_review)
 review_button.hide()
 review_controls = VBoxContainer.new()
 right.add_child(review_controls)
 review_position = hud.label("", 15, Color("#b9dccc"))
 review_controls.add_child(review_position)
 review_slider = HSlider.new()
 review_slider.step = 1
 review_slider.focus_mode = Control.FOCUS_ALL
 review_slider.tooltip_text = "Drag or use Left and Right to choose an action"
 review_slider.value_changed.connect(_draw_review)
 review_controls.add_child(review_slider)
 review_controls.hide()
 board = GridContainer.new()
 board.add_theme_constant_override("h_separation", 3)
 board.add_theme_constant_override("v_separation", 3)
 right.add_child(board)
 hint = hud.label("", 15)
 hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 right.add_child(hint)
 var guide: Label = hud.label("hop north / east / south / west\nfill     water     wait     gather\nrepeat N … end     # comment", 15, Color("#b9dccc"))
 right.add_child(guide)
 var legend: Label = hud.label("● Pondbot     ~ Spring     # Stone\nA watered lily ripens on the next turn.", 14)
 right.add_child(legend)
 status = hud.label("", 17, Color("#f3ebb4"))
 status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 outer.add_child(status)
 _choose(0)
 hide()

func _button(parent: Container, label: String, action: Callable) -> Button:
 var button := Button.new()
 button.text = label
 button.pressed.connect(action)
 parent.add_child(button)
 return button

func enter_place(next: ExplorerActivityWorld) -> void:
 world = next
 if is_instance_valid(world):
  world.show_garden(garden)

func open() -> void:
 show()
 _draw()
 source.grab_focus()

func _close() -> void:
 flush_draft()
 if not steps.is_empty():
  _stop()
 _close_review()
 hide()
 dismissed.emit()

func _queue_save() -> void:
 var matches_check: bool = checked_source is String and checked_source == source.text
 if steps.is_empty() and not matches_check:
  source.clear_executing_lines()
  if checked_source is String:
   _discard_check()
   status.text = "Code changed. Check again for an updated result."
 if puzzle >= 0 and source.text != loaded_draft:
  draft_timer.start()

func flush_draft() -> void:
 draft_timer.stop()
 if puzzle >= 0 and source.text != loaded_draft:
  loaded_draft = source.text
  if progress.edit_draft(Programs.PUZZLES[puzzle].id, loaded_draft) != OK:
   hud.toast("Could not save activity progress.")
 elif progress.flush() != OK:
  hud.toast("Could not save activity progress.")

func _choose(index: int) -> void:
 flush_draft()
 puzzle = index
 chooser.select(index)
 var item: Dictionary = Programs.PUZZLES[index]
 loaded_draft = str(progress.drafts.get(item.id, item.draft))
 source.text = loaded_draft
 _reset()
 hint.text = item.hint

func _clear_program() -> void:
 running = false
 steps.clear()
 offset = 0

func _reset() -> void:
 _discard_check()
 _clear_program()
 source.clear_executing_lines()
 garden.load_puzzle(puzzle)
 status.text = "Harvest every lily. Run or Step starts from a fresh board."
 _draw()

func _stop() -> void:
 _clear_program()
 source.clear_executing_lines()
 status.text = "Stopped. Run or Step starts from a fresh board."
 _draw()

func _compile_draft() -> Array:
 var result: Dictionary = Programs.compile(source.text)
 if result.has("error"):
  _line_error(result.error, result.line)
  return []
 return result.steps

func _check_code() -> void:
 if not steps.is_empty():
  return
 _discard_check()
 checked_source = source.text
 source.grab_focus()
 var commands := _compile_draft()
 if commands.is_empty():
  return
 source.clear_executing_lines()
 var preview := Programs.new()
 preview.load_puzzle(puzzle)
 for action: Dictionary in commands:
  var error := preview.step(action)
  if not error.is_empty():
   blocked_line = action.line
   _line_error("Check · Line %d · %s" % [action.line + 1, error], action.line)
   break
  if preview.is_complete():
   var over: int = preview.turn - Programs.PUZZLES[puzzle].target
   var target := "meets target" if over <= 0 else "%d over target" % over
   status.text = "Check · %d actions to harvest all %d lilies · %s" % [preview.turn, preview.harvested, target]
   break
 if blocked_line < 0 and not preview.is_complete():
  status.text = "Check · %d of %d lilies harvested in %d actions" % [preview.harvested, preview.plants.size(), preview.turn]
 checked_actions = commands.slice(0, preview.turn)
 review_button.show()

func _toggle_review() -> void:
 if review_controls.visible:
  _close_review()
  return
 if not review_button.visible or checked_source != source.text:
  return
 review_slider.max_value = checked_actions.size()
 review_slider.set_value_no_signal(0)
 review_slider.visible = not checked_actions.is_empty()
 review_controls.show()
 review_button.text = "Back to board"
 _draw_review(0)
 if review_slider.visible:
  review_slider.grab_focus()

func _close_review() -> void:
 if not review_controls.visible:
  return
 review_controls.hide()
 review_button.text = "Review"
 source.clear_executing_lines()
 if blocked_line >= 0:
  _mark_line(blocked_line)
 _draw_board(garden)

func _discard_check() -> void:
 checked_source = null
 checked_actions.clear()
 blocked_line = -1
 _close_review()
 review_button.hide()

func _draw_review(value: float) -> void:
 if not review_controls.visible or checked_source != source.text:
  return
 var count := clampi(roundi(value), 0, checked_actions.size())
 var preview := Programs.new()
 preview.load_puzzle(puzzle)
 for index in count:
  preview.step(checked_actions[index])
 var blocked := blocked_line >= 0 and count == checked_actions.size()
 review_position.text = "Preview · %d / %d actions" % [count, checked_actions.size()]
 if blocked:
  review_position.text += " · Blocked"
  _mark_line(blocked_line)
 elif count > 0:
  _mark_line(checked_actions[count - 1].line)
 else:
  source.clear_executing_lines()
 _draw_board(preview, blocked)

func _prepare_program() -> bool:
 if not steps.is_empty():
  return true
 _discard_check()
 steps = _compile_draft()
 if steps.is_empty():
  return false
 garden.load_puzzle(puzzle)
 source.clear_executing_lines()
 return true

func _run() -> void:
 if running:
  running = false
 elif _prepare_program():
  interval = 0
  running = true
 else:
  return
 _show_progress()
 _draw()

func _step() -> void:
 if not running and _prepare_program():
  _advance()

func _show_progress() -> void:
 var next: Dictionary = steps[offset]
 status.text = "%s · %d / %d actions · next line %d" % [
  "Running" if running else "Paused", offset, steps.size(), next.line + 1,
 ]

func _mark_line(line: int) -> void:
 var marked := clampi(line, 0, source.get_line_count() - 1)
 source.clear_executing_lines()
 source.set_line_as_executing(marked, true)
 source.set_caret_line(marked)

func _line_error(message: String, line: int) -> void:
 status.text = message
 _mark_line(line)
 source.grab_focus()

func _process(delta: float) -> void:
 if not visible or not running:
  return
 interval -= delta
 if interval > 0:
  return
 interval = .23
 _advance()

func _advance() -> void:
 var action: Dictionary = steps[offset]
 var error: String = garden.step(action)
 if not error.is_empty():
  _clear_program()
  _line_error("Line %d · %s" % [action.line + 1, error], action.line)
 else:
  _mark_line(action.line)
  offset += 1
  if garden.is_complete():
   _clear_program()
   var item: Dictionary = Programs.PUZZLES[puzzle]
   var previous: int = progress.garden_best.get(item.id, 0)
   if progress.complete_puzzle(item.id, garden.turn) != OK:
    hud.toast("Could not save activity progress.")
   status.text = "Puzzle complete · %d lilies in %d actions" % [garden.harvested, garden.turn]
   if previous > garden.turn:
    status.text += " · New personal best"
   chooser.set_item_text(puzzle, item.name + " ✓")
  elif offset == steps.size():
   _clear_program()
   status.text = "Program ended · %d lilies remain." % (garden.plants.size() - garden.harvested)
  else:
   _show_progress()
 _draw()

func _draw() -> void:
 var item: Dictionary = Programs.PUZZLES[puzzle]
 var best_actions: int = progress.garden_best.get(item.id, 0)
 var target_status := "Target met" if best_actions > 0 and best_actions <= item.target else "Target"
 var best_text := "%d actions" % best_actions if best_actions > 0 else "—"
 score.text = "%s · %d actions\nPersonal best · %s" % [target_status, item.target, best_text]
 var active := not steps.is_empty()
 check_button.disabled = active
 run_button.text = ("Pause" if running else "Resume" if active else "Run") + " · Ctrl+Enter"
 step_button.disabled = running
 stop_button.disabled = not active
 chooser.disabled = active
 source.editable = not active
 if not review_controls.visible:
  _draw_board(garden)
 if is_instance_valid(world):
  world.show_garden(garden)

func _draw_board(view: Programs, blocked := false) -> void:
 info.text = "Water %d / %d    Lilies %d / %d" % [view.tank, Programs.CAPACITY, view.harvested, view.plants.size()]
 for child in board.get_children():
  board.remove_child(child)
  child.queue_free()
 board.columns = view.rows[0].length()
 for y in view.rows.size():
  for x in view.rows[y].length():
   var cell := Vector2i(x, y)
   var tile: String = view.tile(cell)
   var plant: String = view.plant_status(cell)
   var card := PanelContainer.new()
   var style := StyleBoxFlat.new()
   if cell == view.cell:
    style.bg_color = Color("#784b30") if blocked else Color("#1f5950")
   else:
    style.bg_color = Color("#214355") if tile == "~" else Color("#424744") if tile == "#" else Color("#293b27")
   style.set_corner_radius_all(6)
   card.add_theme_stylebox_override("panel", style)
   card.custom_minimum_size = Vector2(67, 44)
   var icon := "● " if cell == view.cell else ""
   var caption := plant if not plant.is_empty() else "Spring" if tile == "~" else "#" if tile == "#" else "·"
   var label: Label = hud.label(icon + "\n" + caption if not icon.is_empty() else caption, 12)
   label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
   card.add_child(label)
   board.add_child(card)

func _input(event: InputEvent) -> void:
 if not visible:
  return
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_ESCAPE:
   _close()
   get_viewport().set_input_as_handled()
  elif event.ctrl_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
   _run()
   get_viewport().set_input_as_handled()
  elif event.keycode == KEY_F10:
   _step()
   get_viewport().set_input_as_handled()
