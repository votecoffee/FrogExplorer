extends PanelContainer

signal dismissed
const Programs = preload("res://scripts/activities/garden_program.gd")
const Progress = preload("res://scripts/activities/activity_progress.gd")
const RUN_INTERVAL := .23
const CLASSIC_GUIDE := "hop north / east / south / west\nfill     plant     water     wait     gather\nrepeat N … end     # comment\nroutine NAME heading · call NAME east\nif / while CONDITION … end\nelse · not · and · or · break · continue\nLook ahead with clear east or lily north\nF9 toggles a breakpoint"
const PYTHON_GUIDE := "hop(east)    fill()    water()\nplant()       wait()       gather()\nfor bed in range(2):\nif water_level() < tank_capacity():\nwhile clear(east):\ndef walk(heading, steps: int):\nstart = column()    print(start)\nTab indents · Shift+Tab unindents\nF9 toggles a breakpoint"
var hud: ExplorerHUD
var garden := Programs.new()
var world: ExplorerActivityWorld
var puzzle := -1
var progress: Progress
var draft_timer: Timer
var loaded_draft := ""
var draft_bar: HBoxContainer
var draft_choice: OptionButton
var compare_drafts_button: Button
var comparison_panel: VBoxContainer
var comparison_choice: OptionButton
var comparison_context: Label
var comparison_timeline: HBoxContainer
var comparison_slider: HSlider
var comparison_position: Label
var comparison_difference_button: Button
var comparison_first_difference := -1
var comparison_current_route: Dictionary = {}
var comparison_other_route: Dictionary = {}
var comparison_current: Label
var comparison_other: Label
var comparison_current_board: GridContainer
var comparison_other_board: GridContainer
var comparison_board_key: Label
var comparison_source := ""
var rename_draft_button: Button
var draft_name_edit: LineEdit
var save_draft_name_button: Button
var source: CodeEdit
var actions: HBoxContainer
var best_button: Button
var best_panel: VBoxContainer
var best_title: Label
var edit_copy_button: Button
var best_source: CodeEdit
var output_panel: PanelContainer
var output_title: Label
var output_text: RichTextLabel
var variables_button: Button
var variables_panel: PanelContainer
var variables_title: Label
var variables_text: RichTextLabel
var displayed_variables: Dictionary = {}
var status: Label
var board: GridContainer
var info: Label
var score: Label
var nursery_wallet: Label
var nursery_upgrade_button: Button
var nursery_target_row: HBoxContainer
var nursery_target: SpinBox
var hint: Label
var guide: Label
var chooser: OptionButton
var lesson_status: Label
var next_lesson_button: Button
var language: OptionButton
var python_mode := true
var check_button: Button
var review_button: Button
var review_controls: VBoxContainer
var review_position: Label
var review_slider: HSlider
var run_button: Button
var speed_choice: OptionButton
var step_button: Button
var stop_button: Button
var steps: Array = []
var submitted_program := ""
var offset := 0
var breakpoint_offset := -1
var interval := 0.0
var running := false
var checked_source: Variant = null
var checked_route: Dictionary = {}
var best_route: Dictionary = {}
var best_python := false

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
 lesson_status = hud.label("", 15, Color("#b9dccc"))
 top.add_child(lesson_status)
 next_lesson_button = _button(top, "Next lesson · Ctrl+PgDn", _continue_lessons)
 language = OptionButton.new()
 language.add_item("Python")
 language.add_item("Classic Pondbot")
 language.item_selected.connect(_select_language)
 top.add_child(language)
 variables_button = _button(top, "Variables · F7", _refresh_variables)
 variables_button.toggle_mode = true
 _button(top, "Close · Esc", _close)
 var pair := HBoxContainer.new()
 pair.size_flags_vertical = Control.SIZE_EXPAND_FILL
 pair.add_theme_constant_override("separation", 14)
 outer.add_child(pair)
 var left := VBoxContainer.new()
 left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 pair.add_child(left)
 actions = HBoxContainer.new()
 left.add_child(actions)
 check_button = _button(actions, "Check", _check_code)
 check_button.tooltip_text = "Check the draft on a fresh board"
 run_button = _button(actions, "Run · Ctrl+Enter", _run)
 speed_choice = OptionButton.new()
 for speed in [1, 2, 4]:
  speed_choice.add_item("Speed %d×" % speed, speed)
 speed_choice.select(0)
 speed_choice.tooltip_text = "F8 cycles nursery run speed."
 speed_choice.hide()
 actions.add_child(speed_choice)
 step_button = _button(actions, "Step · F10", _step)
 stop_button = _button(actions, "Stop", _stop)
 _button(actions, "Reset board", _reset)
 draft_bar = HBoxContainer.new()
 left.add_child(draft_bar)
 draft_choice = OptionButton.new()
 draft_choice.tooltip_text = "Switch between the main draft and saved copies."
 draft_choice.item_selected.connect(_select_draft)
 draft_bar.add_child(draft_choice)
 rename_draft_button = _button(draft_bar, "Rename", _rename_draft)
 compare_drafts_button = _button(draft_bar, "Compare drafts", _toggle_draft_comparison)
 draft_name_edit = LineEdit.new()
 draft_name_edit.placeholder_text = "Draft name"
 draft_name_edit.max_length = Progress.MAX_DRAFT_NAME
 draft_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 draft_name_edit.text_submitted.connect(func(_value: String): _save_draft_name())
 draft_name_edit.hide()
 draft_bar.add_child(draft_name_edit)
 save_draft_name_button = _button(draft_bar, "Save name", _save_draft_name)
 save_draft_name_button.hide()
 _add_draft_comparison(left)
 source = _code_edit()
 source.gutters_draw_breakpoints_gutter = true
 source.highlight_current_line = true
 source.indent_use_spaces = true
 draft_timer = Timer.new()
 draft_timer.one_shot = true
 draft_timer.wait_time = .65
 draft_timer.timeout.connect(flush_draft)
 add_child(draft_timer)
 source.text_changed.connect(_queue_save)
 left.add_child(source)
 best_panel = VBoxContainer.new()
 best_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
 left.add_child(best_panel)
 var best_header := HBoxContainer.new()
 best_panel.add_child(best_header)
 best_title = hud.label("", 17, Color("#f3ebb4"))
 best_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 best_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 best_header.add_child(best_title)
 edit_copy_button = _button(best_header, "Edit a copy", _edit_best_copy)
 edit_copy_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
 best_source = _code_edit()
 best_source.editable = false
 best_panel.add_child(best_source)
 best_panel.hide()
 var diagnostics := HBoxContainer.new()
 left.add_child(diagnostics)
 output_panel = PanelContainer.new()
 output_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 output_panel.size_flags_stretch_ratio = 2.0
 diagnostics.add_child(output_panel)
 var output_stack := VBoxContainer.new()
 output_panel.add_child(output_stack)
 output_title = hud.label("", 15, Color("#b9dccc"))
 output_stack.add_child(output_title)
 output_text = RichTextLabel.new()
 output_text.custom_minimum_size.y = 88
 output_text.add_theme_font_size_override("normal_font_size", 15)
 output_text.scroll_following = true
 output_text.selection_enabled = true
 output_stack.add_child(output_text)
 output_panel.hide()
 variables_panel = PanelContainer.new()
 variables_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 diagnostics.add_child(variables_panel)
 var variables_stack := VBoxContainer.new()
 variables_panel.add_child(variables_stack)
 variables_title = hud.label("", 15, Color("#b9dccc"))
 variables_stack.add_child(variables_title)
 variables_text = RichTextLabel.new()
 variables_text.custom_minimum_size.y = output_text.custom_minimum_size.y
 variables_text.add_theme_font_override("normal_font", source.get_theme_font("font"))
 variables_text.add_theme_font_size_override("normal_font_size", 15)
 variables_text.selection_enabled = true
 variables_stack.add_child(variables_text)
 variables_panel.hide()
 var sidebar := VBoxContainer.new()
 sidebar.custom_minimum_size.x = 285
 sidebar.add_theme_constant_override("separation", 9)
 pair.add_child(sidebar)
 chooser = OptionButton.new()
 for item in Programs.GARDENS:
  chooser.add_item(item.name)
 chooser.item_selected.connect(_choose)
 sidebar.add_child(chooser)
 var sidebar_scroll := ScrollContainer.new()
 sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 sidebar_scroll.focus_mode = Control.FOCUS_ALL
 sidebar_scroll.follow_focus = true
 sidebar.add_child(sidebar_scroll)
 var right := VBoxContainer.new()
 right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 right.add_theme_constant_override("separation", 9)
 sidebar_scroll.add_child(right)
 info = hud.label("", 17, Color("#b9dccc"))
 right.add_child(info)
 score = hud.label("", 15, Color("#b9dccc"))
 score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 right.add_child(score)
 nursery_target_row = HBoxContainer.new()
 nursery_wallet = hud.label("", 15, Color("#b9dccc"))
 nursery_wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 nursery_target_row.add_child(nursery_wallet)
 nursery_target_row.add_child(hud.label("Harvest target", 15))
 nursery_target = SpinBox.new()
 nursery_target.min_value = 1
 nursery_target.max_value = Programs.MAX_HARVEST_TARGET
 nursery_target.step = 1
 nursery_target.value = Programs.DEFAULT_HARVEST_TARGET
 nursery_target.select_all_on_focus = true
 nursery_target.tooltip_text = "Python reads this value with harvest_target()."
 nursery_target.value_changed.connect(_set_nursery_target)
 nursery_target_row.add_child(nursery_target)
 right.add_child(nursery_target_row)
 nursery_upgrade_button = _button(right, "", _buy_nursery_upgrade)
 best_button = _button(right, "Best program", _toggle_best_program)
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
 board = _board_grid(right)
 hint = hud.label("", 15)
 hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 right.add_child(hint)
 guide = hud.label("", 15, Color("#b9dccc"))
 right.add_child(guide)
 var legend: Label = hud.label("● Pondbot     ~ Spring     # Stone\nA watered lily ripens on the next turn.", 14)
 right.add_child(legend)
 status = hud.label("", 17, Color("#f3ebb4"))
 status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 outer.add_child(status)
 _choose(maxi(0, progress.next_lesson(progress.earned_lilies())))
 hide()

func _code_edit() -> CodeEdit:
 var editor := CodeEdit.new()
 editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
 editor.gutters_draw_line_numbers = true
 editor.gutters_draw_executing_lines = true
 editor.add_theme_font_size_override("font_size", 18)
 return editor

func _color_code(editor: CodeEdit, python: bool) -> void:
 var ink := CodeHighlighter.new()
 var structural := ["for", "in", "range", "def", "elif", "print", "return", "int", "bool"] if python else ["repeat", "routine", "call", "end"]
 for word in ["hop", "fill", "plant", "water", "wait", "gather", "if", "else", "while", "not", "and", "or", "clear", "break", "continue"] + structural + Programs.CONDITIONS + Programs.NUMERIC_SENSORS:
  ink.add_keyword_color(word, Color("#8bd5bc"))
 ink.add_color_region("#", "", Color("#a5ad99"), true)
 editor.syntax_highlighter = ink

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
 if progress.refresh_nursery() != OK:
  hud.toast("Could not save nursery progress.")
 _apply_nursery_tools()
 show()
 _draw()
 source.grab_focus()

func _close() -> void:
 _commit_target_edit()
 _cancel_draft_rename()
 _close_draft_comparison()
 flush_draft()
 if not steps.is_empty():
  _stop()
 _close_best_program()
 _close_review()
 hide()
 dismissed.emit()

func _queue_save() -> void:
 if comparison_panel.visible and comparison_source != source.text:
  _close_draft_comparison()
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
  if progress.edit_draft(_draft_key(), loaded_draft, python_mode) != OK:
   hud.toast("Could not save activity progress.")
 elif progress.flush() != OK:
  hud.toast("Could not save activity progress.")

func _toggle_best_program() -> void:
 if best_panel.visible:
  _close_best_program()
  return
 if not steps.is_empty():
  return
 _commit_target_edit()
 var item: Dictionary = Programs.GARDENS[puzzle]
 var record := progress.nursery_record(item.id, garden) if garden.practice else {}
 var recorded: String = record.get("source", "") if garden.practice else progress.garden_best_programs.get(item.id, "")
 if recorded.is_empty():
  return
 _close_review()
 best_python = record.get("python", false) if garden.practice else progress.garden_best_python.get(item.id, false)
 var language_name := "Python" if best_python else "Classic Pondbot"
 if garden.practice:
  var result: Vector3i = record.score
  best_title.text = "%s · Target %d · %d actions · %s\nWater used %d · Fills %d" % [
   item.name, garden.harvest_target, result.x, language_name, result.y, result.z,
  ]
 else:
  best_title.text = "%s · %d actions · %s" % [item.name, progress.garden_best[item.id], language_name]
 _color_code(best_source, best_python)
 best_source.text = recorded
 best_source.set_caret_line(0)
 best_source.set_caret_column(0)
 actions.hide()
 _cancel_draft_rename()
 _close_draft_comparison()
 draft_bar.hide()
 source.hide()
 status.hide()
 best_panel.show()
 nursery_target.editable = false
 nursery_upgrade_button.disabled = true
 output_panel.hide()
 _show_variables({}, "Best run")
 best_button.text = "Back to draft"
 review_button.disabled = true
 best_source.grab_focus()
 var result := _compile(recorded, best_python)
 if result.has("error"):
  best_title.text += "\nReplay unavailable · " + result.error
  _mark_line(best_source, result.line)
  return
 var limit := Programs.MAX_STEPS
 if garden.practice:
  limit = mini(record.score.x, Programs.MAX_COMPUTATION_STEPS)
 best_route = _trace(result.steps, true, limit)
 var preview: Programs = best_route.preview
 if best_route.line >= 0:
  best_title.text += "\nLine %d · %s" % [best_route.line + 1, best_route.error]
 elif garden.practice:
  if best_route.limited:
   best_title.text += "\nReplay shows the first %d actions" % best_route.actions.size()
  elif Vector3i(preview.run_action_count(), preview.run_water_used, preview.run_fills) != record.score or preview.run_harvest_count() < garden.harvest_target:
   best_title.text += "\nReplay differs from the saved result."
 elif not preview.is_complete():
  best_title.text += "\nReplay gathers %d of %d lilies" % [preview.harvested, preview.plants.size()]
 _open_review(best_route.actions.size())

func _edit_best_copy() -> void:
 if not best_panel.visible or not steps.is_empty() or best_source.text.is_empty():
  return
 flush_draft()
 var id: String = Programs.GARDENS[puzzle].id
 var copy := progress.create_draft_copy(id, best_source.text, best_python)
 python_mode = best_python
 language.select(0 if python_mode else 1)
 var selection_error := progress.select_draft(id, copy.key, python_mode)
 _close_best_program()
 _load_draft(false)
 status.text = "Editing %s" % draft_choice.get_item_text(draft_choice.selected)
 if copy.error != OK or selection_error != OK:
  hud.toast("Could not save activity progress.")
 source.grab_focus()

func _close_best_program() -> void:
 if not best_panel.visible:
  return
 best_panel.hide()
 best_route.clear()
 review_controls.hide()
 actions.show()
 source.show()
 status.show()
 best_button.text = "Best program"
 review_button.disabled = false
 _draw()
 source.grab_focus()

func _choose(index: int) -> void:
 if not steps.is_empty() or not progress.lesson_available(Programs.GARDENS[index], progress.earned_lilies()):
  chooser.select(puzzle)
  return
 _commit_target_edit()
 flush_draft()
 _close_best_program()
 puzzle = index
 chooser.select(index)
 _load_draft()

func _continue_lessons() -> void:
 if not next_lesson_button.visible or next_lesson_button.disabled:
  return
 var index := progress.next_lesson(progress.earned_lilies())
 if index >= 0:
  _choose(index)
  source.grab_focus()

func _buy_nursery_upgrade() -> void:
 if not steps.is_empty() or not garden.practice or best_panel.visible:
  return
 var upgrade := progress.next_nursery_upgrade()
 if upgrade.is_empty():
  return
 if progress.buy_nursery_upgrade(upgrade) != OK:
  status.text = "Could not buy the nursery upgrade."
  _draw()
  return
 if upgrade == Progress.WILLOW_MARKER:
  _choose(Programs.GARDENS.find(Programs.WILLOW_NURSERY))
  status.text = "Willow nursery unlocked. Run or Step to tend the new beds."
 elif upgrade == Progress.LOTUS_MARSH_MARKER:
  _choose(Programs.GARDENS.find(Programs.LOTUS_MARSH))
  status.text = "Lotus marsh unlocked. Tend a neighboring lily while the lotus ripens."
 elif upgrade == Progress.STONE_RING_MARKER:
  _choose(Programs.GARDENS.find(Programs.STONE_RING_NURSERY))
  status.text = "Stone ring nursery unlocked. Run the starter from either spring to tend one bank."
 elif upgrade == Progress.SPEED_CONTROL_MARKER:
  _refresh_speed_choice()
  status.text = "Speed control fitted. Choose a speed or press F8."
 else:
  _apply_nursery_tools()
  if upgrade == Progress.RESERVOIR_MARKER:
   status.text = "Reservoir fitted. Fill at the spring for six doses."
  elif upgrade == Progress.REACH_TOOL_MARKER:
   status.text = "Reach tool fitted. Use plant(east) or water(east) on a neighboring bed."
  else:
   status.text = "Harvest hook fitted. Use gather(east) on a neighboring ripe bed."
  _draw()

func _apply_nursery_tools() -> void:
 var previous_capacity := garden.water_capacity
 var previous_reach := garden.reach_tool
 var previous_hook := garden.harvest_hook
 garden.configure_nursery_tools(progress.has_nursery_upgrade(Progress.RESERVOIR_MARKER),
                               progress.has_nursery_upgrade(Progress.REACH_TOOL_MARKER),
                               progress.has_nursery_upgrade(Progress.HARVEST_HOOK_MARKER))
 if previous_capacity != garden.water_capacity or previous_reach != garden.reach_tool or previous_hook != garden.harvest_hook:
  _discard_check()
 _refresh_speed_choice()

func _refresh_speed_choice() -> void:
 speed_choice.visible = garden.practice and progress.has_nursery_upgrade(Progress.SPEED_CONTROL_MARKER)

func _select_language(index: int) -> void:
 if not steps.is_empty():
  return
 flush_draft()
 _close_best_program()
 python_mode = index == 0
 language.select(index)
 _load_draft(not garden.practice)
 source.grab_focus()

func _draft_key() -> String:
 return progress.selected_draft(Programs.GARDENS[puzzle].id, python_mode)

func _refresh_draft_choice() -> void:
 var id: String = Programs.GARDENS[puzzle].id
 var current := _draft_key()
 var copies := progress.draft_copy_keys(id, python_mode)
 draft_choice.clear()
 draft_choice.add_item("Main draft")
 draft_choice.set_item_metadata(0, id)
 var selected := 0
 for index in copies.size():
  var title := progress.draft_copy_name(copies[index], python_mode)
  var label := "Copy %d" % (index + 1) if title.is_empty() else "%d · %s" % [index + 1, title]
  draft_choice.add_item(label)
  draft_choice.set_item_metadata(index + 1, copies[index])
  if copies[index] == current:
   selected = index + 1
 draft_choice.select(selected)

func _select_draft(index: int) -> void:
 if not steps.is_empty() or best_panel.visible:
  return
 flush_draft()
 if progress.select_draft(Programs.GARDENS[puzzle].id, draft_choice.get_item_metadata(index), python_mode) != OK:
  hud.toast("Could not save the selected draft.")
 _load_draft(false)
 source.grab_focus()

func _rename_draft() -> void:
 if draft_choice.selected < 1 or not steps.is_empty() or best_panel.visible:
  return
 _close_draft_comparison()
 draft_name_edit.text = progress.draft_copy_name(_draft_key(), python_mode)
 draft_name_edit.show()
 save_draft_name_button.show()
 rename_draft_button.hide()
 draft_name_edit.grab_focus()
 draft_name_edit.select_all()

func _cancel_draft_rename() -> void:
 draft_name_edit.hide()
 save_draft_name_button.hide()
 rename_draft_button.visible = draft_choice.selected > 0

func _save_draft_name() -> void:
 if not draft_name_edit.visible:
  return
 if progress.rename_draft_copy(Programs.GARDENS[puzzle].id, _draft_key(), python_mode, draft_name_edit.text) != OK:
  hud.toast("Could not save the draft name.")
 _cancel_draft_rename()
 _refresh_draft_choice()
 source.grab_focus()

func _add_draft_comparison(parent: Container) -> void:
 comparison_panel = VBoxContainer.new()
 parent.add_child(comparison_panel)
 var choices := HBoxContainer.new()
 comparison_panel.add_child(choices)
 comparison_context = hud.label("", 14)
 comparison_context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 choices.add_child(comparison_context)
 choices.add_child(hud.label("Compare with", 14))
 comparison_choice = OptionButton.new()
 comparison_choice.item_selected.connect(_compare_drafts)
 choices.add_child(comparison_choice)
 comparison_timeline = HBoxContainer.new()
 comparison_panel.add_child(comparison_timeline)
 comparison_position = hud.label("", 14)
 comparison_timeline.add_child(comparison_position)
 comparison_slider = HSlider.new()
 comparison_slider.step = 1
 comparison_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 comparison_slider.focus_mode = Control.FOCUS_ALL
 comparison_slider.tooltip_text = "Drag or use Left and Right to review both drafts at the same action."
 comparison_slider.value_changed.connect(_show_comparison_step)
 comparison_timeline.add_child(comparison_slider)
 comparison_difference_button = _button(comparison_timeline, "First difference", _jump_to_comparison_difference)
 comparison_difference_button.tooltip_text = "Compare board commands, directions, and points where either draft stops."
 var results := GridContainer.new()
 results.columns = 2
 results.add_theme_constant_override("h_separation", 18)
 comparison_panel.add_child(results)
 comparison_current = hud.label("", 14, Color("#b9dccc"))
 comparison_other = hud.label("", 14, Color("#b9dccc"))
 for label in [comparison_current, comparison_other]:
  label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  results.add_child(label)
 comparison_current_board = _board_grid(results)
 comparison_other_board = _board_grid(results)
 comparison_board_key = hud.label("Gold outline · Tile differs between drafts", 13, Color("#e8c879"))
 comparison_panel.add_child(comparison_board_key)
 comparison_panel.hide()

func _toggle_draft_comparison() -> void:
 if comparison_panel.visible:
  _close_draft_comparison()
  return
 if not steps.is_empty() or best_panel.visible or draft_choice.item_count < 2:
  return
 _save_draft_name()
 _commit_target_edit()
 _close_review()
 comparison_choice.clear()
 for index in draft_choice.item_count:
  if index == draft_choice.selected:
   continue
  comparison_choice.add_item(draft_choice.get_item_text(index))
  comparison_choice.set_item_metadata(comparison_choice.item_count - 1, draft_choice.get_item_metadata(index))
 comparison_choice.select(0)
 comparison_context.text = "Starting board · Live nursery" if garden.practice else "Starting board · Fresh lesson"
 comparison_source = source.text
 comparison_current_route = _trace_draft(comparison_source)
 comparison_panel.show()
 compare_drafts_button.text = "Close comparison"
 _compare_drafts(0)
 if comparison_timeline.visible:
  comparison_slider.grab_focus()

func _compare_drafts(index: int) -> void:
 if not comparison_panel.visible:
  return
 var other: String = comparison_choice.get_item_metadata(index)
 comparison_other_route = _trace_draft(_draft_source(other))
 var current_actions: Array = comparison_current_route.get("actions", [])
 var other_actions: Array = comparison_other_route.get("actions", [])
 var total := maxi(current_actions.size(), other_actions.size())
 comparison_slider.set_value_no_signal(0)
 comparison_slider.max_value = total
 comparison_slider.set_value_no_signal(total)
 comparison_timeline.visible = total > 0
 _update_comparison_difference()
 _show_comparison_step(total)

func _update_comparison_difference() -> void:
 var both_compiled := comparison_current_route.has("actions") and comparison_other_route.has("actions")
 comparison_difference_button.visible = both_compiled
 comparison_first_difference = _find_comparison_difference(comparison_current_route, comparison_other_route) if both_compiled else -1
 comparison_difference_button.disabled = comparison_first_difference < 0
 if comparison_first_difference == 0:
  comparison_difference_button.text = "First difference · Start"
 elif comparison_first_difference > 0:
  comparison_difference_button.text = "First difference · %d" % comparison_first_difference
 else:
  comparison_difference_button.text = "No preview difference"

func _find_comparison_difference(current: Dictionary, other: Dictionary) -> int:
 var current_actions: Array = current.actions
 var other_actions: Array = other.actions
 var shared_steps := mini(current_actions.size(), other_actions.size())
 # Both traces use the same starting board. Matching resolved commands keep its state equal.
 for index in shared_steps:
  var left: Dictionary = current_actions[index]
  var right: Dictionary = other_actions[index]
  if left.command != right.command or left.get("direction", "") != right.get("direction", ""):
   return index + 1
 if _comparison_interruption(current, shared_steps) != _comparison_interruption(other, shared_steps):
  return shared_steps
 return shared_steps + 1 if current_actions.size() != other_actions.size() else -1

func _comparison_interruption(route: Dictionary, index: int) -> String:
 if _comparison_blocked(route, index):
  return route.error
 return "Preview limit" if index == route.actions.size() and route.get("limited", false) else ""

func _jump_to_comparison_difference() -> void:
 if comparison_first_difference >= 0:
  comparison_slider.value = comparison_first_difference
  comparison_slider.grab_focus()

func _trace_draft(text: String) -> Dictionary:
 var result := _compile(text, python_mode)
 return result if result.has("error") else _trace(result.steps)

func _show_comparison_step(value: float) -> void:
 if not comparison_panel.visible:
  return
 var index := roundi(value)
 comparison_position.text = "%d / %d actions" % [index, int(comparison_slider.max_value)]
 var current := _comparison_board_at(comparison_current_route, index)
 var other := _comparison_board_at(comparison_other_route, index)
 comparison_current.text = draft_choice.get_item_text(draft_choice.selected) + "\n" + _comparison_snapshot(comparison_current_route, index, current)
 comparison_other.text = comparison_choice.get_item_text(comparison_choice.selected) + "\n" + _comparison_snapshot(comparison_other_route, index, other)
 _draw_grid(comparison_current_board, current, _comparison_blocked(comparison_current_route, index), other, Vector2(61, 36))
 _draw_grid(comparison_other_board, other, _comparison_blocked(comparison_other_route, index), current, Vector2(61, 36))
 comparison_board_key.visible = current != null and other != null

func _comparison_board_at(route: Dictionary, index: int) -> Programs:
 return _board_after_actions(route, mini(index, route.actions.size())) if route.has("actions") else null

func _comparison_blocked(route: Dictionary, index: int) -> bool:
 return route.has("actions") and route.line >= 0 and index >= route.actions.size()

func _comparison_snapshot(route: Dictionary, index: int, preview: Programs) -> String:
 if preview == null:
  return route.error
 var traced: Array = route.actions
 var count := mini(index, traced.size())
 var at_end := count == traced.size()
 var summary := _nursery_summary(preview)
 if not preview.practice:
  var unit := "action" if preview.turn == 1 else "actions"
  summary = "Harvested %d of %d in %d %s · %s" % [
   preview.harvested, preview.plants.size(), preview.turn, unit, _water_summary(preview),
  ]
 var step := "Start" if count == 0 else "%d / %d actions" % [count, traced.size()]
 if _comparison_blocked(route, index):
  step = "Blocked · Line %d · %s" % [route.line + 1, route.error]
 elif at_end and route.limited:
  step += " · Preview limit"
 elif index > count:
  step = "Finished · " + step
 elif count > 0:
  var action: Dictionary = traced[count - 1]
  var command := (str(action.command) + " " + str(action.get("direction", ""))).strip_edges()
  step += " · Line %d · %s" % [action.line + 1, command]
 var position := "Row %d · Column %d · Tank %d / %d" % [preview.cell.y, preview.cell.x, preview.tank, preview.water_capacity]
 return "%s\n%s\n%s" % [step, position, summary]

func _close_draft_comparison() -> void:
 if comparison_panel.visible:
  comparison_panel.hide()
  comparison_current_route.clear()
  comparison_other_route.clear()
  comparison_first_difference = -1
  _draw_grid(comparison_current_board, null)
  _draw_grid(comparison_other_board, null)
  compare_drafts_button.text = "Compare drafts"

func _draft_source(key: String) -> String:
 var item: Dictionary = Programs.GARDENS[puzzle]
 var saved := progress.python_drafts if python_mode else progress.drafts
 return str(saved.get(key, item.python_draft if python_mode else item.draft))

func _load_draft(reset_board := true) -> void:
 _cancel_draft_rename()
 var item: Dictionary = Programs.GARDENS[puzzle]
 loaded_draft = _draft_source(_draft_key())
 _refresh_draft_choice()
 _color_code(source, python_mode)
 source.indent_automatic = python_mode
 source.placeholder_text = "Type Python for Pondbot" if python_mode else "Type Pondbot commands"
 guide.text = PYTHON_GUIDE if python_mode else CLASSIC_GUIDE
 source.clear_breakpointed_lines()
 source.text = loaded_draft
 if reset_board:
  _reset()
 else:
  _discard_check()
  _stop()
 hint.text = item.hint

func _clear_program() -> void:
 running = false
 steps.clear()
 submitted_program = ""
 offset = 0
 breakpoint_offset = -1

func _reset() -> void:
 _discard_check()
 _clear_program()
 source.clear_executing_lines()
 garden.load_puzzle(puzzle, progress.has_nursery_upgrade(Progress.RESERVOIR_MARKER),
                    progress.has_nursery_upgrade(Progress.REACH_TOOL_MARKER),
                    progress.has_nursery_upgrade(Progress.HARVEST_HOOK_MARKER))
 _refresh_speed_choice()
 nursery_target_row.visible = garden.practice
 if garden.practice:
  garden.harvest_target = progress.nursery_target(Programs.GARDENS[puzzle].id)
  _show_nursery_target()
 status.text = "Run or Step tends the current nursery." if garden.practice else "Harvest every lily. Run or Step starts from a fresh board."
 _draw()

func _commit_target_edit() -> void:
 if garden.practice and steps.is_empty() and not best_panel.visible:
  nursery_target.apply()

func _show_nursery_target() -> void:
 nursery_target.set_value_no_signal(garden.harvest_target)
 nursery_target.get_line_edit().text = str(garden.harvest_target)

func _set_nursery_target(value: float) -> void:
 if not garden.practice or not steps.is_empty() or best_panel.visible:
  _show_nursery_target()
  return
 if garden.harvest_target == int(value):
  return
 garden.harvest_target = int(value)
 _show_nursery_target()
 if progress.set_nursery_target(Programs.GARDENS[puzzle].id, garden.harvest_target) != OK:
  hud.toast("Could not save the harvest target.")
 _discard_check()
 status.text = "Harvest target · %d lilies" % garden.harvest_target
 _draw()

func _stop() -> void:
 var show_summary := garden.practice and not steps.is_empty()
 _clear_program()
 source.clear_executing_lines()
 if show_summary:
  status.text = "Stopped · " + _nursery_summary(garden)
 else:
  status.text = "Stopped. Run or Step continues from the current garden." if garden.practice else "Stopped. Run or Step starts from a fresh board."
 _draw()

func _compile(text: String, python: bool) -> Dictionary:
 return Programs.compile_python(text) if python else Programs.compile(text)

func _compile_draft() -> Array:
 var result := _compile(source.text, python_mode)
 if result.has("error"):
  _line_error(result.error, result.line)
  return []
 return result.steps

func _check_code() -> void:
 if best_panel.visible or not steps.is_empty():
  return
 _commit_target_edit()
 _discard_check()
 checked_source = source.text
 source.grab_focus()
 var commands := _compile_draft()
 if commands.is_empty():
  return
 source.clear_executing_lines()
 checked_route = _trace(commands)
 var preview: Programs = checked_route.preview
 var line: int = checked_route.line
 if line >= 0:
  _line_error("Check · Line %d · %s" % [line + 1, checked_route.error], line, preview)
 elif preview.practice:
  status.text = "Check · " + _nursery_summary(preview) + (" · Preview limit" if checked_route.limited else "")
  if preview.starting_turn == 0 and preview.run_harvest_count() >= preview.harvest_target and not checked_route.limited:
   var best := progress.nursery_best(Programs.GARDENS[puzzle].id, preview)
   if best != Vector3i.ZERO:
    var change := Vector3i(preview.run_action_count(), preview.run_water_used, preview.run_fills) - best
    status.text += "\nCompared with best · %+d actions · %+d doses · %+d fills" % [change.x, change.y, change.z]
 elif preview.is_complete():
  var over: int = preview.turn - Programs.GARDENS[puzzle].target
  var target := "meets target" if over <= 0 else "%d over target" % over
  status.text = "Check · %d actions to harvest all %d lilies · %s" % [preview.turn, preview.harvested, target]
 else:
  var unit := "action" if preview.turn == 1 else "actions"
  status.text = "Check · %d of %d lilies harvested in %d %s" % [preview.harvested, preview.plants.size(), preview.turn, unit]
 _draw_diagnostics(preview, "Check")
 if not checked_route.actions.is_empty() or line >= 0:
  review_button.show()

func _trace(commands: Array, fresh_board := false, practice_limit := Programs.MAX_STEPS) -> Dictionary:
 var initial := Programs.new()
 if not garden.practice:
  initial.load_puzzle(puzzle)
 elif fresh_board:
  initial.load_puzzle(puzzle, garden.water_capacity == Programs.RESERVOIR_CAPACITY, garden.reach_tool, garden.harvest_hook)
  initial.harvest_target = garden.harvest_target
 else:
  initial = garden.copy_board() as Programs
  initial.reset_program()
 var preview := initial.copy_board() as Programs
 var traced: Array[Dictionary] = []
 var index := preview.next_action_index(commands, 0)
 # Review position zero includes assignments before the first board action.
 var variable_history: Array[Dictionary] = [preview.inspect_variables()]
 while index < commands.size() and (not preview.practice or traced.size() < practice_limit):
  var action: Dictionary = commands[index]
  var error := preview.step(action)
  if not error.is_empty():
   return {"actions":traced, "initial":initial, "preview":preview, "line":action.line,
           "error":error, "variable_history":variable_history}
  traced.append(action)
  var complete := preview.is_complete()
  var revision := preview.variable_revision
  if not complete:
   index = preview.next_action_index(commands, index + 1)
  var values: Dictionary = variable_history.back() if preview.variable_revision == revision else preview.inspect_variables()
  variable_history.append(values)
  if complete:
   break
 return {"actions":traced, "initial":initial, "preview":preview, "line":preview.runtime_error_line,
         "error":preview.runtime_error, "limited":preview.practice and index < commands.size(),
         "variable_history":variable_history}

func _toggle_review() -> void:
 if best_panel.visible:
  return
 _close_draft_comparison()
 if review_controls.visible:
  _close_review()
  return
 if not review_button.visible or checked_source != source.text:
  return
 review_button.text = "Back to board"
 _open_review(checked_route.actions.size())

func _open_review(length: int) -> void:
 review_slider.max_value = length
 review_slider.set_value_no_signal(0)
 review_slider.visible = length > 0
 review_controls.show()
 _draw_review(0)
 if review_slider.visible:
  review_slider.grab_focus()

func _close_review() -> void:
 if best_panel.visible or not review_controls.visible:
  return
 review_controls.hide()
 review_button.text = "Review"
 source.clear_executing_lines()
 var line: int = checked_route.get("line", -1)
 if line >= 0:
  _mark_line(source, line)
 _draw_board(garden)
 _draw_diagnostics(garden)

func _discard_check() -> void:
 _close_draft_comparison()
 checked_source = null
 checked_route.clear()
 _close_review()
 review_button.hide()
 _draw_diagnostics(garden)

func _board_after_actions(route: Dictionary, count: int) -> Programs:
 var traced: Array = route.actions
 if count == traced.size():
  return route.preview as Programs
 var initial: Programs = route.initial
 var preview := initial.copy_board() as Programs
 for index in count:
  preview.step(traced[index])
 return preview

func _draw_review(value: float) -> void:
 var replaying_best := best_panel.visible
 if not review_controls.visible or (not replaying_best and checked_source != source.text):
  return
 var route := best_route if replaying_best else checked_route
 var traced: Array = route.actions
 var line: int = route.line
 var editor := best_source if replaying_best else source
 var count := clampi(roundi(value), 0, traced.size())
 var preview := _board_after_actions(route, count)
 var blocked := line >= 0 and count == traced.size()
 review_position.text = "%s · %d / %d actions" % ["Best run" if replaying_best else "Preview", count, traced.size()]
 if blocked:
  review_position.text += " · Blocked"
  _mark_line(editor, line)
 elif count > 0:
  _mark_line(editor, traced[count - 1].line)
 else:
  editor.clear_executing_lines()
 if preview.practice:
  review_position.text += "\n" + _water_summary(preview)
 _draw_board(preview, blocked)
 _draw_diagnostics(route.preview, "Best run" if replaying_best else "Check", preview.turn, route.variable_history[count])

func _prepare_program() -> bool:
 if best_panel.visible:
  return false
 if not steps.is_empty():
  return true
 _save_draft_name()
 _commit_target_edit()
 _discard_check()
 steps = _compile_draft()
 if steps.is_empty():
  return false
 submitted_program = source.text
 if garden.practice:
  garden.reset_program()
 else:
  garden.load_puzzle(puzzle)
 source.clear_executing_lines()
 offset = garden.next_action_index(steps, 0)
 if offset == steps.size():
  _finish_incomplete()
  _draw()
  return false
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
 status.text = "%s · %d actions · next line %d" % [
  "Running" if running else "Paused", garden.run_action_count(), next.line + 1,
 ]
 if garden.practice:
  status.text += " · %d / %d lilies this run" % [garden.run_harvest_count(), garden.harvest_target]

func _mark_line(editor: CodeEdit, line: int) -> void:
 var marked := clampi(line, 0, editor.get_line_count() - 1)
 editor.clear_executing_lines()
 editor.set_line_as_executing(marked, true)
 editor.set_caret_line(marked)

func _line_error(message: String, line: int, report: Programs = null) -> void:
 status.text = message
 if report != null and report.practice:
  status.text += "\n" + _nursery_summary(report)
 _mark_line(source, line)
 source.grab_focus()

func _process(delta: float) -> void:
 if not visible or not running:
  return
 var speed := speed_choice.get_selected_id() if speed_choice.visible else 1
 interval -= delta * speed
 if interval > 0:
  return
 # Carry fractional timing between frames and advance at most one action per frame.
 interval = maxf(0.0, interval + RUN_INTERVAL)
 var action: Dictionary = steps[offset]
 if breakpoint_offset != offset and source.is_line_breakpointed(action.line):
  running = false
  breakpoint_offset = offset
  var actions_count := garden.run_action_count()
  var unit := "action" if actions_count == 1 else "actions"
  status.text = "Breakpoint · line %d · %d %s" % [action.line + 1, actions_count, unit]
  _mark_line(source, action.line)
  _draw()
  return
 _advance()

func _advance() -> void:
 breakpoint_offset = -1
 var action: Dictionary = steps[offset]
 var before := garden.harvested
 var error: String = garden.step(action)
 if not error.is_empty():
  _clear_program()
  _line_error("Line %d · %s" % [action.line + 1, error], action.line, garden)
 else:
  _mark_line(source, action.line)
  var harvest := garden.harvested - before
  if garden.practice and harvest > 0 and progress.record_nursery_harvest(harvest) != OK:
   hud.toast("Could not save the nursery harvest.")
  if garden.is_complete():
   var completed_program := submitted_program
   _clear_program()
   var item: Dictionary = Programs.GARDENS[puzzle]
   var previous: int = progress.garden_best.get(item.id, 0)
   if progress.complete_puzzle(item.id, garden.turn, completed_program, python_mode) != OK:
    hud.toast("Could not save activity progress.")
   status.text = "Puzzle complete · %d lilies in %d actions" % [garden.harvested, garden.turn]
   if previous > garden.turn:
    status.text += " · New personal best"
  else:
   offset = garden.next_action_index(steps, offset + 1)
   if offset == steps.size():
    _finish_incomplete()
   else:
    _show_progress()
 _draw()

func _finish_incomplete() -> void:
 var completed_program := submitted_program
 _clear_program()
 if not garden.runtime_error.is_empty():
  var line: int = garden.runtime_error_line
  _line_error("Line %d · %s" % [line + 1, garden.runtime_error], line, garden)
 elif garden.practice:
  status.text = "Program ended · " + _nursery_summary(garden)
  if garden.starting_turn == 0 and garden.run_harvest_count() >= garden.harvest_target:
   var id: String = Programs.GARDENS[puzzle].id
   var previous := progress.nursery_best(id, garden)
   if progress.record_nursery_best(id, garden, completed_program, python_mode) != OK:
    hud.toast("Could not save the nursery best.")
   elif progress.nursery_best(id, garden) != previous:
    status.text += " · New personal best"
 else:
  status.text = "Program ended · %d lilies remain." % (garden.plants.size() - garden.harvested)

func _water_summary(view: Programs) -> String:
 return "Water used %d · Fills %d" % [view.run_water_used, view.run_fills]

func _nursery_summary(view: Programs) -> String:
 var count := view.run_harvest_count()
 var actions_count := view.run_action_count()
 var unit := "action" if actions_count == 1 else "actions"
 var harvest := "Harvested %d in %d %s" % [count, actions_count, unit]
 var shortfall := view.harvest_target - count
 var target := "Target %d met" % view.harvest_target if shortfall <= 0 else "%d short of %d" % [shortfall, view.harvest_target]
 return "%s · %s · %s" % [harvest, target, _water_summary(view)]

func _draw() -> void:
 var item: Dictionary = Programs.GARDENS[puzzle]
 var nursery_record := progress.nursery_record(item.id, garden) if garden.practice else {}
 if garden.practice:
  var nursery_best: Vector3i = nursery_record.get("score", Vector3i.ZERO)
  score.visible = nursery_best != Vector3i.ZERO
  if score.visible:
   score.text = "Best for target %d · %d actions\nWater used %d · Fills %d" % [
    garden.harvest_target, nursery_best.x, nursery_best.y, nursery_best.z,
   ]
 else:
  score.show()
  var best_actions: int = progress.garden_best.get(item.id, 0)
  var target_status := "Target met" if best_actions > 0 and best_actions <= item.target else "Target"
  var best_text := "%d actions" % best_actions if best_actions > 0 else "—"
  score.text = "%s · %d actions\nPersonal best · %s" % [target_status, item.target, best_text]
 var active := not steps.is_empty()
 var balance := progress.nursery_balance()
 nursery_wallet.visible = garden.practice
 nursery_wallet.text = "Nursery lilies · %d" % balance
 var upgrade := progress.next_nursery_upgrade()
 nursery_upgrade_button.visible = garden.practice and not upgrade.is_empty()
 if nursery_upgrade_button.visible:
  var cost: int = Progress.NURSERY_UPGRADE_COSTS[upgrade]
  var label := "Buy reach tool"
  match upgrade:
   Progress.WILLOW_MARKER:
    label = "Unlock Willow nursery"
   Progress.RESERVOIR_MARKER:
    label = "Upgrade reservoir"
   Progress.LOTUS_MARSH_MARKER:
    label = "Unlock Lotus marsh"
   Progress.HARVEST_HOOK_MARKER:
    label = "Buy harvest hook"
   Progress.STONE_RING_MARKER:
    label = "Unlock Stone ring nursery"
   Progress.SPEED_CONTROL_MARKER:
    label = "Buy speed control"
  nursery_upgrade_button.text = "%s · %d lilies" % [label, cost]
  nursery_upgrade_button.disabled = active or best_panel.visible or balance < cost
 best_button.visible = not nursery_record.get("source", "").is_empty() if garden.practice else progress.garden_best_programs.has(item.id)
 best_button.disabled = active
 check_button.disabled = active
 run_button.text = ("Pause" if running else "Resume" if active else "Run") + " · Ctrl+Enter"
 step_button.disabled = running
 stop_button.disabled = not active
 nursery_target.editable = not active and not best_panel.visible
 chooser.disabled = active
 draft_bar.visible = draft_choice.item_count > 1 and not best_panel.visible
 draft_choice.disabled = active
 compare_drafts_button.disabled = active
 rename_draft_button.visible = draft_choice.selected > 0 and not draft_name_edit.visible
 rename_draft_button.disabled = active
 language.disabled = active
 source.editable = not active
 _draw_lessons(active)
 if not review_controls.visible:
  _draw_board(garden)
  _draw_diagnostics(garden)
 if is_instance_valid(world):
  world.show_garden(garden)

func _draw_lessons(active: bool) -> void:
 var lilies := progress.earned_lilies()
 var next_unlock := 0
 for index in Programs.GARDENS.size():
  var item: Dictionary = Programs.GARDENS[index]
  var available := progress.lesson_available(item, lilies)
  var label: String = item.name
  var purchase: String = Progress.NURSERY_UNLOCKS.get(item.id, "")
  if not available and not purchase.is_empty():
   label += " · %d nursery lilies" % Progress.NURSERY_UPGRADE_COSTS[purchase]
  elif not available:
   var threshold: int = item.unlock_lilies
   next_unlock = threshold if next_unlock == 0 else mini(next_unlock, threshold)
   label += " · %d lilies" % threshold
  elif progress.solved.has(item.id):
   label += " ✓"
  chooser.set_item_disabled(index, not available)
  chooser.set_item_text(index, label)
 lesson_status.text = "Lilies earned · %d" % lilies
 if next_unlock > 0:
  lesson_status.text += "   Next unlock · %d" % next_unlock
 next_lesson_button.visible = progress.solved.has(Programs.GARDENS[puzzle].id) and progress.next_lesson(lilies) >= 0
 next_lesson_button.disabled = active

func _draw_diagnostics(view: Programs, context := "Program", through_turn := -1, snapshot: Variant = null) -> void:
 var lines := PackedStringArray()
 for entry: Dictionary in view.output:
  if through_turn < 0 or entry.turn <= through_turn:
   lines.append("Line %d · %s" % [entry.line + 1, entry.text])
 output_panel.visible = not lines.is_empty()
 output_title.text = context + " output"
 var transcript := "\n".join(lines)
 if output_text.text != transcript:
  output_text.text = transcript
 _show_variables(view.inspect_variables() if snapshot == null else snapshot, context)

func _show_variables(values: Dictionary, context: String) -> void:
 displayed_variables = values
 variables_title.text = context + " variables"
 _refresh_variables()

func _refresh_variables() -> void:
 variables_button.visible = best_python if best_panel.visible else python_mode
 variables_panel.visible = variables_button.visible and variables_button.button_pressed
 if not variables_panel.visible:
  return
 var names := displayed_variables.keys()
 names.sort()
 var lines := PackedStringArray()
 for variable: String in names:
  lines.append("%s = %s" % [variable, Programs.python_value_text(displayed_variables[variable])])
 var content := "\n".join(lines) if not lines.is_empty() else "No variables assigned"
 if variables_text.text != content:
  variables_text.text = content

func _board_grid(parent: Container) -> GridContainer:
 var grid := GridContainer.new()
 grid.add_theme_constant_override("h_separation", 3)
 grid.add_theme_constant_override("v_separation", 3)
 parent.add_child(grid)
 return grid

func _draw_board(view: Programs, blocked := false) -> void:
 var harvest := "Harvested %d" % view.harvested if view.practice else "Lilies %d / %d" % [view.harvested, view.plants.size()]
 info.text = "Water %d / %d    %s" % [view.tank, view.water_capacity, harvest]
 _draw_grid(board, view, blocked)

func _draw_grid(grid: GridContainer, view: Programs, blocked := false, peer: Programs = null, card_size := Vector2(67, 44)) -> void:
 for child in grid.get_children():
  grid.remove_child(child)
  child.queue_free()
 if view == null:
  return
 grid.columns = view.rows[0].length()
 for y in view.rows.size():
  for x in view.rows[y].length():
   var cell := Vector2i(x, y)
   var tile: String = view.tile(cell)
   var plant: String = view.plant_status(cell)
   var card := PanelContainer.new()
   var style := StyleBoxFlat.new()
   if cell == view.cell:
    style.bg_color = Color("#784b30") if blocked else Color("#1f5950")
   elif tile == Programs.LOTUS_BED:
    style.bg_color = Color("#513c62")
   elif tile == "B":
    style.bg_color = Color("#694f35")
   else:
    style.bg_color = Color("#214355") if tile == "~" else Color("#424744") if tile == "#" else Color("#293b27")
   style.set_corner_radius_all(6)
   if peer != null and ((cell == view.cell) != (cell == peer.cell) or plant != peer.plant_status(cell)):
    style.border_color = Color("#e8c879")
    style.set_border_width_all(2)
   card.add_theme_stylebox_override("panel", style)
   card.custom_minimum_size = card_size
   var heading := "● " if cell == view.cell else ""
   if tile == Programs.LOTUS_BED:
    heading += "Lotus"
   var caption := plant if not plant.is_empty() else "Spring" if tile == "~" else "#" if tile == "#" else "·"
   var label: Label = hud.label(heading + "\n" + caption if not heading.is_empty() else caption, 12)
   label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
   card.add_child(label)
   grid.add_child(card)

func _input(event: InputEvent) -> void:
 if not visible:
  return
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_ESCAPE:
   if draft_name_edit.visible:
    _cancel_draft_rename()
    source.grab_focus()
   elif comparison_panel.visible:
    _close_draft_comparison()
    source.grab_focus()
   elif best_panel.visible:
    _close_best_program()
   else:
    _close()
   get_viewport().set_input_as_handled()
  elif event.ctrl_pressed and event.keycode == KEY_PAGEDOWN and next_lesson_button.visible:
   _continue_lessons()
   get_viewport().set_input_as_handled()
  elif event.keycode == KEY_F7 and variables_button.visible:
   variables_button.set_pressed_no_signal(not variables_button.button_pressed)
   _refresh_variables()
   get_viewport().set_input_as_handled()
  elif best_panel.visible:
   return
  elif event.ctrl_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
   _run()
   get_viewport().set_input_as_handled()
  elif event.keycode == KEY_F8 and speed_choice.visible:
   speed_choice.select((speed_choice.selected + 1) % speed_choice.item_count)
   get_viewport().set_input_as_handled()
  elif event.keycode == KEY_F9:
   var line := source.get_caret_line()
   source.set_line_as_breakpoint(line, not source.is_line_breakpointed(line))
   get_viewport().set_input_as_handled()
  elif event.keycode == KEY_F10:
   _step()
   get_viewport().set_input_as_handled()
