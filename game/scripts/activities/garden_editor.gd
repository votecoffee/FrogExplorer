extends PanelContainer

signal dismissed
const Programs = preload("res://scripts/activities/garden_program.gd")
var hud: ExplorerHUD
var garden := Programs.new()
var world: ExplorerActivityWorld
var puzzle := -1
var drafts: Dictionary = {}
var solved: Dictionary = {}
var source: CodeEdit
var status: Label
var board: GridContainer
var info: Label
var hint: Label
var chooser: OptionButton
var run_button: Button
var stop_button: Button
var pending: Array = []
var offset := 0
var interval := 0.0
var running := false

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
 run_button = _button(actions, "Run · Ctrl+Enter", _run)
 stop_button = _button(actions, "Stop", _stop)
 _button(actions, "Reset board", _reset)
 source = CodeEdit.new()
 source.size_flags_vertical = Control.SIZE_EXPAND_FILL
 source.gutters_draw_line_numbers = true
 source.placeholder_text = "Type Pondbot commands here"
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
  chooser.add_item(item.name)
 chooser.item_selected.connect(_choose)
 right.add_child(chooser)
 info = hud.label("", 17, Color("#b9dccc"))
 right.add_child(info)
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
 if running:
  _stop()
 hide()
 dismissed.emit()

func _choose(index: int) -> void:
 if puzzle >= 0:
  drafts[puzzle] = source.text
 puzzle = index
 chooser.select(index)
 source.text = str(drafts.get(index, Programs.PUZZLES[index].draft))
 _reset()
 hint.text = Programs.PUZZLES[index].hint

func _reset() -> void:
 running = false
 pending.clear()
 garden.load_puzzle(puzzle)
 status.text = "Harvest every lily. Run starts from a fresh board."
 _draw()

func _stop() -> void:
 running = false
 status.text = "Stopped. Run starts from a fresh board."
 _draw()

func _run() -> void:
 if running:
  return
 var result: Dictionary = Programs.compile(source.text)
 if result.has("error"):
  _line_error(result.error, result.line)
  return
 _reset()
 pending = result.steps
 offset = 0
 interval = 0
 running = true
 status.text = "Running…"
 _draw()

func _line_error(message: String, line: int) -> void:
 status.text = message
 source.set_caret_line(clampi(line, 0, maxi(0, source.get_line_count() - 1)))

func _process(delta: float) -> void:
 if not visible or not running:
  return
 interval -= delta
 if interval > 0:
  return
 interval = .23
 var action: Dictionary = pending[offset]
 var error: String = garden.step(action)
 if not error.is_empty():
  running = false
  _line_error("Line %d · %s" % [action.line + 1, error], action.line)
 else:
  offset += 1
  if garden.harvested == garden.plants.size():
   solved[puzzle] = true
   running = false
   status.text = "Puzzle complete · %d lilies in %d actions" % [garden.harvested, garden.turn]
   chooser.set_item_text(puzzle, Programs.PUZZLES[puzzle].name + " ✓")
  elif offset == pending.size():
   running = false
   status.text = "Program ended · %d lilies remain." % (garden.plants.size() - garden.harvested)
  else:
   status.text = "Action %d / %d · line %d" % [offset, pending.size(), action.line + 1]
 _draw()

func _draw() -> void:
 info.text = "Water %d / %d    Lilies %d / %d" % [garden.tank, Programs.CAPACITY, garden.harvested, garden.plants.size()]
 run_button.disabled = running
 stop_button.disabled = not running
 chooser.disabled = running
 source.editable = not running
 for child in board.get_children():
  board.remove_child(child)
  child.queue_free()
 board.columns = garden.rows[0].length()
 for y in garden.rows.size():
  for x in garden.rows[y].length():
   var cell := Vector2i(x, y)
   var tile: String = garden.tile(cell)
   var plant: String = garden.plant_status(cell)
   var card := PanelContainer.new()
   var style := StyleBoxFlat.new()
   style.bg_color = Color("#1f5950") if cell == garden.cell else Color("#214355") if tile == "~" else Color("#424744") if tile == "#" else Color("#293b27")
   style.set_corner_radius_all(6)
   card.add_theme_stylebox_override("panel", style)
   card.custom_minimum_size = Vector2(67, 44)
   var icon := "● " if cell == garden.cell else ""
   var caption := plant if not plant.is_empty() else "Spring" if tile == "~" else "#" if tile == "#" else "·"
   var label: Label = hud.label(icon + "\n" + caption if not icon.is_empty() else caption, 12)
   label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
   card.add_child(label)
   board.add_child(card)
 if is_instance_valid(world):
  world.show_garden(garden)

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
