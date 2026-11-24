extends PanelContainer

signal dismissed
const Programs = preload("res://scripts/activities/garden_program.gd")
const Progress = preload("res://scripts/activities/activity_progress.gd")
const RUN_INTERVAL := .23
const COMPARISON_BOARD_KEY := "Gold outline · Tile differs between drafts"
const COMPARISON_BEST := "<personal-best>"
const COMPARISON_GOLD := "#e8c879"
const COMPARISON_HIGHLIGHT := "[color=" + COMPARISON_GOLD + "]"
const COMPARISON_TOTAL_NAMES := ["Lilies harvested", "Actions", "Water doses", "Fills"]
enum ComparisonView { BOARDS, VARIABLES, PRINT_OUTPUT, SOURCE, RESULTS }
enum ComparisonStart { LIVE, FRESH }
enum ComparisonTotals { SELECTED_ACTION, FIRST_TARGET }
const CLASSIC_GUIDE := "hop north / east / south / west\nfill     plant     water     wait     gather\nrepeat N … end     # comment\nroutine NAME heading · call NAME east\nif / while CONDITION … end\nelse · not · and · or · break · continue\nLook ahead with clear east or lily north\nF9 toggles a breakpoint\nCtrl+F10 runs to cursor"
const PYTHON_GUIDE := "hop(east)    fill()    water()\nplant()       wait()       gather()\nfor bed in range(2):\nif water_level() < tank_capacity():\nwhile clear(east):\ndef walk(heading, steps: int):\nstart = column()    print(start)\nTab indents · Shift+Tab unindents\nF9 toggles a breakpoint\nCtrl+F10 runs to cursor\nShift+F11 steps out of a function"
var hud: ExplorerHUD
var garden := Programs.new()
var world: ExplorerActivityWorld
var puzzle := -1
var progress: Progress
var draft_timer: Timer
var loaded_draft := ""
var draft_bar: HBoxContainer
var draft_choice: OptionButton
var duplicate_draft_button: Button
var compare_drafts_button: Button
var comparison_panel: VBoxContainer
var comparison_choice: OptionButton
var comparison_context: Label
var comparison_start: OptionButton
var comparison_timeline: HBoxContainer
var comparison_slider: HSlider
var comparison_position: Label
var comparison_difference_button: Button
var comparison_previous_difference_button: Button
var comparison_next_difference_button: Button
var comparison_extend_button: Button
var comparison_limit := Programs.MAX_STEPS
var comparison_differences: Array[int] = []
var comparison_current_route: Dictionary = {}
var comparison_other_route: Dictionary = {}
var comparison_current: Label
var comparison_other: Label
var comparison_current_board: GridContainer
var comparison_other_board: GridContainer
var comparison_board_key: Label
var comparison_view: OptionButton
var comparison_current_details: RichTextLabel
var comparison_other_details: RichTextLabel
var comparison_current_code: CodeEdit
var comparison_other_code: CodeEdit
var comparison_other_edit: Button
var comparison_results_panel: VBoxContainer
var comparison_results: GridContainer
var comparison_totals_choice: OptionButton
var comparison_result_values: Array[Label] = []
var comparison_goal_label: Label
var comparison_current_goal: Button
var comparison_other_goal: Button
var comparison_goal_delta: Label
var comparison_goal_actions := Vector2i(-1, -1)
var comparison_best_source := ""
var comparison_source := ""
var comparison_key := ""
var comparison_positions: Dictionary = {}
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
var review_history_list: ItemList
var review_history_source_button: Button
var variable_changes_button: Button
var call_stack_button: Button
var call_stack_list: ItemList
var call_stack_row: HBoxContainer
var frame_variables_panel: VBoxContainer
var frame_variables_title: Label
var frame_variables_text: RichTextLabel
var displayed_variables: Dictionary = {}
var displayed_previous_variables: Dictionary = {}
var live_previous_variables: Variant = null
var displayed_calls: Array = []
var diagnostics_context := ""
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
var review_variable_row: HBoxContainer
var review_variable_filter: OptionButton
var review_variable_name := ""
var review_history_button: Button
var review_change_row: HBoxContainer
var review_previous_change: Button
var review_next_change: Button
var review_change_actions := PackedInt32Array()
var run_button: Button
var speed_choice: OptionButton
var step_button: Button
var stop_button: Button
var steps: Array = []
var submitted_program := ""
var offset := 0
var breakpoint_offset := -1
var run_to_line := -1
var step_out_frame: Dictionary = {}
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
 variables_button.tooltip_text = "F7 shows variables. Ctrl+F7 shows changes. Shift+F7 shows the call stack. Ctrl+Shift+F7 opens a followed variable's history."
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
 step_button.tooltip_text = "Step one command. In the editor, Ctrl+F10 runs to the command at the cursor."
 stop_button = _button(actions, "Stop", _stop)
 _button(actions, "Reset board", _reset)
 draft_bar = HBoxContainer.new()
 left.add_child(draft_bar)
 draft_choice = OptionButton.new()
 draft_choice.tooltip_text = "Switch between the main draft and saved copies."
 draft_choice.item_selected.connect(_select_draft)
 draft_bar.add_child(draft_choice)
 duplicate_draft_button = _button(draft_bar, "Duplicate draft", _duplicate_draft)
 duplicate_draft_button.tooltip_text = "Save the current code as a separate editable draft."
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
 best_source.highlight_current_line = true
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
 var variables_header := HBoxContainer.new()
 variables_stack.add_child(variables_header)
 variables_title = hud.label("", 15, Color("#b9dccc"))
 variables_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 variables_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 variables_header.add_child(variables_title)
 var inspector_views := ButtonGroup.new()
 inspector_views.allow_unpress = true
 variable_changes_button = _button(variables_header, "Changes", _refresh_variables)
 variable_changes_button.toggle_mode = true
 variable_changes_button.button_group = inspector_views
 variable_changes_button.tooltip_text = "Show assignments, new values, and locals that left scope after the selected action."
 call_stack_button = _button(variables_header, "Call stack", _refresh_variables)
 call_stack_button.toggle_mode = true
 call_stack_button.button_group = inspector_views
 call_stack_button.tooltip_text = "Show the active Python calls and their source lines."
 variables_text = RichTextLabel.new()
 variables_text.custom_minimum_size.y = output_text.custom_minimum_size.y
 variables_text.add_theme_font_override("normal_font", source.get_theme_font("font"))
 variables_text.add_theme_font_size_override("normal_font_size", 15)
 variables_text.selection_enabled = true
 variables_stack.add_child(variables_text)
 review_history_list = ItemList.new()
 review_history_list.custom_minimum_size.y = variables_text.custom_minimum_size.y
 review_history_list.add_theme_font_override("font", source.get_theme_font("font"))
 review_history_list.add_theme_font_size_override("font_size", 15)
 review_history_list.focus_mode = Control.FOCUS_ALL
 review_history_list.tooltip_text = "Press Enter or double-click an entry to jump to that action."
 review_history_list.item_activated.connect(_jump_to_history_action)
 review_history_list.item_selected.connect(func(_row: int): _refresh_history_source_button())
 variables_stack.add_child(review_history_list)
 review_history_list.hide()
 review_history_source_button = _button(variables_stack, "Source line · F12", _jump_to_history_source)
 review_history_source_button.hide()
 call_stack_row = HBoxContainer.new()
 variables_stack.add_child(call_stack_row)
 call_stack_list = ItemList.new()
 call_stack_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 call_stack_list.size_flags_stretch_ratio = 1.25
 call_stack_list.custom_minimum_size.y = variables_text.custom_minimum_size.y
 call_stack_list.add_theme_font_override("font", source.get_theme_font("font"))
 call_stack_list.add_theme_font_size_override("font_size", 15)
 call_stack_list.focus_mode = Control.FOCUS_ALL
 call_stack_list.tooltip_text = "Press Enter or double-click a call to open its source line."
 call_stack_list.item_activated.connect(_open_call_site)
 call_stack_list.item_selected.connect(func(_index: int): _refresh_frame_variables())
 call_stack_list.add_item("Top level", null, false)
 call_stack_row.add_child(call_stack_list)
 frame_variables_panel = VBoxContainer.new()
 frame_variables_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 call_stack_row.add_child(frame_variables_panel)
 frame_variables_title = hud.label("", 15, Color("#b9dccc"))
 frame_variables_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 frame_variables_panel.add_child(frame_variables_title)
 frame_variables_text = RichTextLabel.new()
 frame_variables_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
 frame_variables_text.add_theme_font_override("normal_font", source.get_theme_font("font"))
 frame_variables_text.add_theme_font_size_override("normal_font_size", 15)
 frame_variables_text.selection_enabled = true
 frame_variables_panel.add_child(frame_variables_text)
 call_stack_row.hide()
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
 review_slider.tooltip_text = "Drag or use Left and Right to choose an action. In Changes, use Page Up or Page Down to jump."
 review_slider.value_changed.connect(_draw_review)
 review_controls.add_child(review_slider)
 review_variable_row = HBoxContainer.new()
 review_controls.add_child(review_variable_row)
 review_variable_filter = OptionButton.new()
 review_variable_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 review_variable_filter.fit_to_longest_item = false
 review_variable_filter.clip_text = true
 review_variable_filter.tooltip_text = "Choose which variable to follow in this replay."
 review_variable_filter.item_selected.connect(_select_review_variable)
 review_variable_row.add_child(review_variable_filter)
 review_history_button = _button(review_variable_row, "History", _refresh_variables)
 review_history_button.toggle_mode = true
 review_history_button.tooltip_text = "Show the followed variable's history. Ctrl+Shift+F7 opens and focuses the list."
 review_variable_row.hide()
 review_change_row = HBoxContainer.new()
 review_controls.add_child(review_change_row)
 review_previous_change = _button(review_change_row, "Previous change", _jump_to_review_change.bind(false))
 review_next_change = _button(review_change_row, "Next change", _jump_to_review_change.bind(true))
 review_previous_change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 review_next_change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 review_change_row.hide()
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
 _open_draft_copy(best_source.text, best_python)

func _open_draft_copy(text: String, copy_python: bool) -> void:
 flush_draft()
 var id: String = Programs.GARDENS[puzzle].id
 var copy := progress.create_draft_copy(id, text, copy_python)
 python_mode = copy_python
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
 elif upgrade == Progress.ALDER_CROSSING_MARKER:
  _choose(Programs.GARDENS.find(Programs.ALDER_CROSSING))
  status.text = "Alder Crossing unlocked. Run the starter to tend the bank by your spring."
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
 _open_saved_draft(draft_choice.get_item_metadata(index))

func _open_saved_draft(key: String) -> void:
 flush_draft()
 if progress.select_draft(Programs.GARDENS[puzzle].id, key, python_mode) != OK:
  hud.toast("Could not save the selected draft.")
 _load_draft(false)
 source.grab_focus()

func _duplicate_draft() -> void:
 if not steps.is_empty() or best_panel.visible:
  return
 _save_draft_name()
 var line := source.get_caret_line()
 var column := source.get_caret_column()
 _open_draft_copy(source.text, python_mode)
 source.set_caret_line(line)
 source.set_caret_column(column)

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
 choices.add_child(comparison_context)
 comparison_start = OptionButton.new()
 comparison_start.add_item("Live nursery", ComparisonStart.LIVE)
 comparison_start.add_item("Fresh nursery", ComparisonStart.FRESH)
 comparison_start.tooltip_text = "Choose the starting board for both previews."
 comparison_start.item_selected.connect(_select_comparison_start)
 choices.add_child(comparison_start)
 var spacer := Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 choices.add_child(spacer)
 choices.add_child(hud.label("Compare with", 14))
 comparison_choice = OptionButton.new()
 comparison_choice.item_selected.connect(_select_comparison_target)
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
 comparison_difference_button = _button(comparison_timeline, "First difference", func(): _jump_to_comparison_difference(0))
 comparison_previous_difference_button = _button(comparison_timeline, "Previous", func(): _jump_to_adjacent_comparison_difference(false))
 comparison_previous_difference_button.tooltip_text = "Previous difference · Page Up when the slider is focused"
 comparison_next_difference_button = _button(comparison_timeline, "Next", func(): _jump_to_adjacent_comparison_difference(true))
 comparison_next_difference_button.tooltip_text = "Next difference · Page Down when the slider is focused"
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
 comparison_current_details = _comparison_details_box(results)
 comparison_other_details = _comparison_details_box(results)
 comparison_current_code = _comparison_code_box(results, false)
 comparison_other_code = _comparison_code_box(results, true)
 _add_comparison_results(comparison_panel)
 var footer := HBoxContainer.new()
 comparison_panel.add_child(footer)
 comparison_board_key = hud.label(COMPARISON_BOARD_KEY, 13, Color(COMPARISON_GOLD))
 comparison_board_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 footer.add_child(comparison_board_key)
 comparison_extend_button = _button(footer, "Extend preview", _extend_comparison)
 comparison_extend_button.hide()
 comparison_view = OptionButton.new()
 comparison_view.tooltip_text = "Choose what to compare at this action."
 comparison_view.item_selected.connect(_select_comparison_view)
 footer.add_child(comparison_view)
 comparison_panel.hide()

func _add_comparison_results(parent: Container) -> void:
 comparison_results_panel = VBoxContainer.new()
 parent.add_child(comparison_results_panel)
 var controls := HBoxContainer.new()
 comparison_results_panel.add_child(controls)
 controls.add_child(hud.label("Totals at", 14))
 comparison_totals_choice = OptionButton.new()
 comparison_totals_choice.add_item("Selected action", ComparisonTotals.SELECTED_ACTION)
 comparison_totals_choice.add_item("First target action", ComparisonTotals.FIRST_TARGET)
 comparison_totals_choice.tooltip_text = "Use the shared slider position or each draft's own harvest target action."
 comparison_totals_choice.item_selected.connect(_select_comparison_view)
 controls.add_child(comparison_totals_choice)
 comparison_results = GridContainer.new()
 comparison_results.columns = 4
 comparison_results.add_theme_constant_override("h_separation", 16)
 comparison_results.add_theme_constant_override("v_separation", 5)
 comparison_results_panel.add_child(comparison_results)
 for title in ["Total", "Current", "Other", "Other − current"]:
  var heading: Label = hud.label(title, 14, Color("#b9dccc"))
  comparison_results.add_child(heading)
  if title != "Total":
   heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
   heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 for name in COMPARISON_TOTAL_NAMES:
  comparison_results.add_child(hud.label(name, 14))
  for column in 3:
   var value: Label = hud.label("", 14)
   value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
   comparison_results.add_child(value)
   comparison_result_values.append(value)
 comparison_goal_label = hud.label("", 14)
 comparison_results.add_child(comparison_goal_label)
 comparison_current_goal = _button(comparison_results, "", func(): _jump_to_comparison_goal(comparison_goal_actions.x))
 comparison_other_goal = _button(comparison_results, "", func(): _jump_to_comparison_goal(comparison_goal_actions.y))
 for button in [comparison_current_goal, comparison_other_goal]:
  button.size_flags_horizontal = Control.SIZE_SHRINK_END
  button.tooltip_text = "Jump to the action that first reaches the harvest target."
 comparison_goal_delta = hud.label("", 14)
 comparison_goal_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 comparison_results.add_child(comparison_goal_delta)
 comparison_results_panel.hide()

func _select_comparison_view(_index: int) -> void:
 if comparison_panel.visible:
  _update_comparison_differences()
  _show_comparison_step(comparison_slider.value)

func _comparison_details_box(parent: Container) -> RichTextLabel:
 var panel := PanelContainer.new()
 panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(panel)
 var details := RichTextLabel.new()
 details.custom_minimum_size.y = 144
 details.bbcode_enabled = true
 details.selection_enabled = true
 details.focus_mode = Control.FOCUS_ALL
 details.add_theme_font_size_override("normal_font_size", 14)
 panel.add_child(details)
 panel.hide()
 return details

func _comparison_code_box(parent: Container, use_other: bool) -> CodeEdit:
 var column := VBoxContainer.new()
 column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 parent.add_child(column)
 var editor := _code_edit()
 editor.editable = false
 editor.custom_minimum_size.y = 144
 editor.add_theme_font_size_override("font_size", 14)
 column.add_child(editor)
 var title := "Edit other draft" if use_other else "Edit current draft"
 var button := _button(column, title, func(): _edit_compared_draft(use_other))
 button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
 button.tooltip_text = "Open the editable draft at the preview cursor."
 if use_other:
  comparison_other_edit = button
 column.hide()
 return editor

func _edit_compared_draft(use_other: bool) -> void:
 if not comparison_panel.visible or comparison_view.get_selected_id() != ComparisonView.SOURCE or not steps.is_empty() or best_panel.visible:
  return
 var preview := comparison_other_code if use_other else comparison_current_code
 var line := preview.get_caret_line()
 var column := preview.get_caret_column()
 if use_other:
  var other: String = comparison_choice.get_item_metadata(comparison_choice.selected)
  if other == COMPARISON_BEST:
   var position := _comparison_position_for(COMPARISON_BEST)
   _open_draft_copy(preview.text, python_mode)
   comparison_positions[_comparison_key_for(_draft_key())] = position
  else:
   comparison_positions[_comparison_key_for(other)] = _comparison_position_for(_draft_key())
   _open_saved_draft(other)
 else:
  _close_draft_comparison()
  source.grab_focus()
 source.deselect()
 source.remove_secondary_carets()
 source.set_caret_line(line)
 source.set_caret_column(column)

func _toggle_draft_comparison() -> void:
 if comparison_panel.visible:
  _close_draft_comparison()
  return
 if not steps.is_empty() or best_panel.visible:
  return
 _save_draft_name()
 _commit_target_edit()
 var id: String = Programs.GARDENS[puzzle].id
 var record := progress.nursery_record(id, garden) if garden.practice else {}
 comparison_best_source = _best_source_for_comparison(id, record)
 if draft_choice.item_count < 2 and comparison_best_source.is_empty():
  return
 _close_review()
 comparison_key = _comparison_key_for(_draft_key())
 var remembered: Dictionary = comparison_positions.get(comparison_key, {})
 var remembered_other: String = remembered.get("other", "")
 var selected := -1
 comparison_choice.clear()
 for index in draft_choice.item_count:
  if index == draft_choice.selected:
   continue
  var key: String = draft_choice.get_item_metadata(index)
  comparison_choice.add_item(draft_choice.get_item_text(index))
  var item := comparison_choice.item_count - 1
  comparison_choice.set_item_metadata(item, key)
  if key == remembered_other:
   selected = item
 if not comparison_best_source.is_empty():
  comparison_choice.add_item("Personal best")
  var item := comparison_choice.item_count - 1
  comparison_choice.set_item_metadata(item, COMPARISON_BEST)
  if remembered_other == COMPARISON_BEST:
   selected = item
 if selected < 0:
  remembered = {}
  selected = 0
 comparison_choice.select(selected)
 comparison_view.clear()
 comparison_view.add_item("Boards", ComparisonView.BOARDS)
 if python_mode:
  comparison_view.add_item("Variables", ComparisonView.VARIABLES)
  comparison_view.add_item("Print output", ComparisonView.PRINT_OUTPUT)
 comparison_view.add_item("Source", ComparisonView.SOURCE)
 comparison_view.add_item("Results", ComparisonView.RESULTS)
 comparison_view.select(remembered.get("view", 0))
 comparison_totals_choice.select(remembered.get("totals", ComparisonTotals.SELECTED_ACTION))
 for editor in [comparison_current_code, comparison_other_code]:
  _color_code(editor, python_mode)
 comparison_context.text = "Starting board" if garden.practice else "Starting board · Fresh lesson"
 var best_target: bool = comparison_choice.get_item_metadata(selected) == COMPARISON_BEST
 var default_start := ComparisonStart.FRESH if best_target and garden.practice else ComparisonStart.LIVE
 comparison_start.select(remembered.get("start", default_start))
 comparison_start.visible = garden.practice
 comparison_limit = remembered.get("limit", Programs.MAX_STEPS)
 comparison_source = source.text
 comparison_current_code.text = comparison_source
 comparison_current_route = _trace_draft(comparison_source)
 comparison_panel.show()
 compare_drafts_button.text = "Close comparison"
 _compare_drafts(selected, remembered.get("action", -1))
 if comparison_slider.is_visible_in_tree():
  comparison_slider.grab_focus()

func _best_source_for_comparison(id: String, nursery_record: Dictionary) -> String:
 if garden.practice:
  return nursery_record.get("source", "") if nursery_record.get("python", false) == python_mode else ""
 return progress.garden_best_programs.get(id, "") if progress.garden_best_python.get(id, false) == python_mode else ""

func _select_comparison_target(index: int) -> void:
 if not comparison_panel.visible:
  return
 if garden.practice and comparison_choice.get_item_metadata(index) == COMPARISON_BEST and comparison_start.selected != ComparisonStart.FRESH:
  comparison_start.select(ComparisonStart.FRESH)
  comparison_current_route = _trace_draft(comparison_source)
 _compare_drafts(index)

func _select_comparison_start(_index: int) -> void:
 if comparison_panel.visible and garden.practice:
  _retrace_comparison()

func _extend_comparison() -> void:
 if not comparison_panel.visible or not comparison_extend_button.visible:
  return
 comparison_limit = mini(comparison_limit * 2, Programs.MAX_COMPUTATION_STEPS)
 _retrace_comparison()
 comparison_slider.grab_focus()

func _retrace_comparison() -> void:
 comparison_current_route = _trace_draft(comparison_source)
 _compare_drafts(comparison_choice.selected, roundi(comparison_slider.value))

func _compare_drafts(index: int, action := -1) -> void:
 if not comparison_panel.visible:
  return
 var other: String = comparison_choice.get_item_metadata(index)
 var is_best := other == COMPARISON_BEST
 var other_source := comparison_best_source if is_best else _draft_source(other)
 comparison_other_edit.text = "Edit a copy" if is_best else "Edit other draft"
 comparison_other_code.text = other_source
 comparison_other_route = _trace_draft(other_source)
 var current_actions: Array = comparison_current_route.get("actions", [])
 var other_actions: Array = comparison_other_route.get("actions", [])
 var total := maxi(current_actions.size(), other_actions.size())
 var position := total if action < 0 else mini(action, total)
 comparison_slider.set_value_no_signal(0)
 comparison_slider.max_value = total
 comparison_slider.set_value_no_signal(position)
 var limited: bool = comparison_current_route.get("limited", false) or comparison_other_route.get("limited", false)
 comparison_extend_button.visible = limited and comparison_limit < Programs.MAX_COMPUTATION_STEPS
 if comparison_extend_button.visible:
  comparison_extend_button.tooltip_text = "Preview both drafts up to %d actions." % mini(comparison_limit * 2, Programs.MAX_COMPUTATION_STEPS)
 _update_comparison_goal()
 _update_comparison_differences()
 _show_comparison_step(position)

func _update_comparison_differences() -> void:
 var both_compiled := comparison_current_route.has("actions") and comparison_other_route.has("actions")
 var view := comparison_view.get_selected_id()
 var follows_slider := view != ComparisonView.RESULTS or comparison_totals_choice.selected == ComparisonTotals.SELECTED_ACTION
 comparison_differences.clear()
 if both_compiled and follows_slider:
  match view:
   ComparisonView.BOARDS, ComparisonView.SOURCE:
    comparison_differences = _find_board_differences(comparison_current_route, comparison_other_route)
   ComparisonView.VARIABLES:
    comparison_differences = _find_variable_differences(comparison_current_route.variable_history, comparison_other_route.variable_history)
   ComparisonView.PRINT_OUTPUT:
    comparison_differences = _find_print_differences(comparison_current_route, comparison_other_route)
   ComparisonView.RESULTS:
    comparison_differences = _find_result_differences(comparison_current_route.totals_history, comparison_other_route.totals_history)
 comparison_slider.visible = comparison_slider.max_value > 0
 comparison_timeline.visible = comparison_slider.visible or not comparison_differences.is_empty()
 comparison_difference_button.visible = both_compiled and follows_slider
 match view:
  ComparisonView.BOARDS:
   comparison_difference_button.tooltip_text = "Compare board commands, directions, and stopping points."
  ComparisonView.VARIABLES:
   comparison_difference_button.tooltip_text = "Compare new or changing differences in Python variables."
  ComparisonView.PRINT_OUTPUT:
   comparison_difference_button.tooltip_text = "Compare the messages printed at each action."
  ComparisonView.SOURCE:
   comparison_difference_button.tooltip_text = "Jump to the source for different board commands and stopping points."
  ComparisonView.RESULTS:
   comparison_difference_button.tooltip_text = "Jump to changes in the difference between the two sets of totals."
 comparison_difference_button.disabled = comparison_differences.is_empty()
 comparison_previous_difference_button.visible = comparison_differences.size() > 1
 comparison_next_difference_button.visible = comparison_previous_difference_button.visible
 if comparison_differences.is_empty():
  comparison_difference_button.text = "No preview difference"
 elif comparison_differences[0] == 0:
  comparison_difference_button.text = "First difference · Start"
 else:
  comparison_difference_button.text = "First difference · %d" % comparison_differences[0]

func _find_board_differences(current: Dictionary, other: Dictionary) -> Array[int]:
 var current_actions: Array = current.actions
 var other_actions: Array = other.actions
 var shared_steps := mini(current_actions.size(), other_actions.size())
 var differences: Array[int] = []
 for index in shared_steps:
  var left: Dictionary = current_actions[index]
  var right: Dictionary = other_actions[index]
  if left.command != right.command or left.get("direction", "") != right.get("direction", ""):
   differences.append(index + 1)
 var different_end := _comparison_interruption(current, shared_steps) != _comparison_interruption(other, shared_steps)
 var different_lengths := current_actions.size() != other_actions.size()
 # The slider shows an interruption at the last completed action.
 if different_end:
  if differences.is_empty() or differences[-1] != shared_steps:
   differences.append(shared_steps)
 elif different_lengths:
  differences.append(shared_steps + 1)
 if different_lengths:
  var longer := current if current_actions.size() > other_actions.size() else other
  var length: int = longer.actions.size()
  if differences[-1] < length and not _comparison_interruption(longer, length).is_empty():
   differences.append(length)
 return differences

func _find_variable_differences(current: Array, other: Array) -> Array[int]:
 var differences: Array[int] = []
 var previous: Dictionary = {}
 for index in maxi(current.size(), other.size()):
  var left: Dictionary = current[mini(index, current.size() - 1)]
  var right: Dictionary = other[mini(index, other.size() - 1)]
  var mismatches := _variable_mismatches(left, right)
  if not mismatches.is_empty() and mismatches != previous:
   differences.append(index)
  previous = mismatches
 return differences

func _variable_mismatches(current: Dictionary, other: Dictionary) -> Dictionary:
 var mismatches: Dictionary = {}
 for name: String in current:
  var left: Variant = current[name]
  var right: Variant = other.get(name)
  if not is_same(left, right):
   mismatches[name] = [typeof(left), left, typeof(right), right]
 for name: String in other:
  if not current.has(name):
   var right: Variant = other[name]
   mismatches[name] = [TYPE_NIL, null, typeof(right), right]
 return mismatches

func _find_print_differences(current: Dictionary, other: Dictionary) -> Array[int]:
 var differences: Array[int] = []
 for index in maxi(current.output_history.size(), other.output_history.size()):
  if _prints_at_action(current, index) != _prints_at_action(other, index):
   differences.append(index)
 return differences

func _prints_at_action(route: Dictionary, index: int) -> PackedStringArray:
 var messages := PackedStringArray()
 if index < route.output_history.size():
  var turn: int = route.initial.turn + index
  for entry: Dictionary in route.output_history[index]:
   if entry.turn == turn:
    messages.append(entry.text)
 return messages

func _find_result_differences(current: Array[Vector4i], other: Array[Vector4i]) -> Array[int]:
 var differences: Array[int] = []
 var previous := Vector4i.ZERO
 for index in maxi(current.size(), other.size()):
  var delta := other[mini(index, other.size() - 1)] - current[mini(index, current.size() - 1)]
  if delta != Vector4i.ZERO and delta != previous:
   differences.append(index)
  previous = delta
 return differences

func _comparison_totals(board: Programs) -> Vector4i:
 return Vector4i(board.run_harvest_count(), board.run_action_count(), board.run_water_used, board.run_fills)

func _totals_for_results(board: Programs, route: Dictionary, goal_action: int) -> Variant:
 if comparison_totals_choice.selected == ComparisonTotals.FIRST_TARGET:
  return route.totals_history[goal_action] if goal_action >= 0 else null
 return _comparison_totals(board) if board != null else null

func _show_comparison_results(current: Programs, other: Programs) -> void:
 var left: Variant = _totals_for_results(current, comparison_current_route, comparison_goal_actions.x)
 var right: Variant = _totals_for_results(other, comparison_other_route, comparison_goal_actions.y)
 var comparable: bool = left != null and right != null
 var delta: Vector4i = right - left if comparable else Vector4i.ZERO
 for row in COMPARISON_TOTAL_NAMES.size():
  var offset := 3 * row
  comparison_result_values[offset].text = str(left[row]) if left != null else "—"
  comparison_result_values[offset + 1].text = str(right[row]) if right != null else "—"
  _show_comparison_delta(comparison_result_values[offset + 2], delta[row], comparable)

func _show_comparison_delta(label: Label, delta: int, available: bool) -> void:
 if available:
  label.text = "%+d" % delta if delta != 0 else "0"
 else:
  label.text = "—"
 label.modulate = Color(COMPARISON_GOLD) if available and delta != 0 else Color.WHITE

func _update_comparison_goal() -> void:
 var goal := garden.harvest_target if garden.practice else garden.plants.size()
 comparison_goal_label.text = "First reaches %d %s" % [goal, "lily" if goal == 1 else "lilies"]
 comparison_goal_actions = Vector2i(
  _first_harvest_goal_action(comparison_current_route, goal),
  _first_harvest_goal_action(comparison_other_route, goal),
 )
 _show_goal_button(comparison_current_goal, comparison_current_route, comparison_goal_actions.x)
 _show_goal_button(comparison_other_goal, comparison_other_route, comparison_goal_actions.y)
 var both_reached := comparison_goal_actions.x >= 0 and comparison_goal_actions.y >= 0
 _show_comparison_delta(comparison_goal_delta, comparison_goal_actions.y - comparison_goal_actions.x, both_reached)

func _first_harvest_goal_action(route: Dictionary, goal: int) -> int:
 var history: Array = route.get("totals_history", [])
 for index in history.size():
  if history[index].x >= goal:
   return index
 return -1

func _show_goal_button(button: Button, route: Dictionary, action: int) -> void:
 button.disabled = action < 0
 if action >= 0:
  button.text = "Action %d" % action
 elif route.has("totals_history"):
  button.text = "Not reached" if not route.get("limited", false) else "Preview limit"
 else:
  button.text = "—"

func _jump_to_comparison_goal(action: int) -> void:
 if action < 0 or not comparison_results.is_visible_in_tree():
  return
 comparison_slider.value = action
 if comparison_slider.visible:
  comparison_slider.grab_focus()

func _comparison_interruption(route: Dictionary, index: int) -> String:
 if _comparison_blocked(route, index):
  return route.error
 return "Preview limit" if index == route.actions.size() and route.get("limited", false) else ""

func _jump_to_comparison_difference(position: int) -> void:
 if position >= 0 and position < comparison_differences.size():
  comparison_slider.value = comparison_differences[position]
  if comparison_slider.is_visible_in_tree():
   comparison_slider.grab_focus()

func _jump_to_adjacent_comparison_difference(forward: bool) -> void:
 var index := roundi(comparison_slider.value)
 var position := comparison_differences.bsearch(index, not forward)
 _jump_to_comparison_difference(position if forward else position - 1)

func _trace_draft(text: String) -> Dictionary:
 var result := _compile(text, python_mode)
 var fresh := garden.practice and comparison_start.get_selected_id() == ComparisonStart.FRESH
 return result if result.has("error") else _trace(result.steps, fresh, comparison_limit, true)

func _show_comparison_step(value: float) -> void:
 if not comparison_panel.visible:
  return
 var index := roundi(value)
 comparison_position.text = "%d / %d actions" % [index, int(comparison_slider.max_value)]
 var current := _comparison_board_at(comparison_current_route, index)
 var other := _comparison_board_at(comparison_other_route, index)
 var view := comparison_view.get_selected_id()
 var show_results := view == ComparisonView.RESULTS
 comparison_current.text = draft_choice.get_item_text(draft_choice.selected) + "\n" + _comparison_snapshot(comparison_current_route, index, current, not show_results)
 comparison_other.text = comparison_choice.get_item_text(comparison_choice.selected) + "\n" + _comparison_snapshot(comparison_other_route, index, other, not show_results)
 comparison_results_panel.visible = show_results
 if show_results:
  _show_comparison_results(current, other)
 var show_boards := view == ComparisonView.BOARDS
 comparison_current_board.visible = show_boards
 comparison_other_board.visible = show_boards
 if show_boards:
  _draw_grid(comparison_current_board, current, _comparison_blocked(comparison_current_route, index), other, Vector2(61, 36))
  _draw_grid(comparison_other_board, other, _comparison_blocked(comparison_other_route, index), current, Vector2(61, 36))
 _show_comparison_details(comparison_current_details, comparison_current_route, comparison_other_route, index, view)
 _show_comparison_details(comparison_other_details, comparison_other_route, comparison_current_route, index, view)
 var show_source := view == ComparisonView.SOURCE
 _show_comparison_source(comparison_current_code, comparison_current_route, index, show_source)
 _show_comparison_source(comparison_other_code, comparison_other_route, index, show_source)
 var before := comparison_differences.bsearch(index)
 var after := comparison_differences.bsearch(index, false)
 comparison_previous_difference_button.disabled = before == 0
 comparison_next_difference_button.disabled = after == comparison_differences.size()
 var legend := ""
 if show_source:
  legend = "Read-only source · Marked line follows the selected action"
 elif current != null and other != null:
  match view:
   ComparisonView.BOARDS:
    legend = COMPARISON_BOARD_KEY
   ComparisonView.VARIABLES:
    legend = "Gold text · Different values    ·    — Unassigned"
   ComparisonView.PRINT_OUTPUT:
    legend = "Gold text · Different messages at this action"
 if before < after:
  legend += ("    ·    " if not legend.is_empty() else "") + "Difference %d of %d" % [after, comparison_differences.size()]
 comparison_board_key.text = legend
 comparison_board_key.visible = not legend.is_empty()

func _show_comparison_details(details: RichTextLabel, route: Dictionary, peer: Dictionary, index: int, view: int) -> void:
 var panel := details.get_parent() as PanelContainer
 panel.visible = view in [ComparisonView.VARIABLES, ComparisonView.PRINT_OUTPUT]
 if not panel.visible:
  return
 var text := "Preview unavailable"
 if route.has("actions"):
  if view == ComparisonView.VARIABLES:
   text = _comparison_variable_text(route, peer, index)
  else:
   text = _comparison_print_text(route, peer, index)
 if details.text != text:
  details.text = text
  var first_highlight := text.find(COMPARISON_HIGHLIGHT)
  var paragraph := text.left(first_highlight).count("\n") if first_highlight >= 0 else 0
  details.scroll_to_paragraph(paragraph)

func _show_comparison_source(editor: CodeEdit, route: Dictionary, index: int, show_source: bool) -> void:
 (editor.get_parent() as Control).visible = show_source
 if not show_source:
  return
 var line := -1
 if not route.has("actions") or _comparison_blocked(route, index):
  line = route.get("line", -1)
 else:
  var count := mini(index, route.actions.size())
  if count > 0:
   line = route.actions[count - 1].line
 if line >= 0:
  _mark_line(editor, line)
 else:
  editor.clear_executing_lines()

func _comparison_variable_text(route: Dictionary, peer: Dictionary, index: int) -> String:
 var values: Dictionary = route.variable_history[mini(index, route.actions.size())]
 var mismatches := {}
 if peer.has("actions"):
  var other_values: Dictionary = peer.variable_history[mini(index, peer.actions.size())]
  mismatches = _variable_mismatches(values, other_values)
 var names := values.keys()
 for name: String in mismatches:
  if not values.has(name):
   names.append(name)
 names.sort()
 var lines := PackedStringArray()
 for name: String in names:
  var value := Programs.python_value_text(values[name]) if values.has(name) else "—"
  lines.append(_comparison_text("%s = %s" % [name, value], mismatches.has(name)))
 return "No variables assigned" if lines.is_empty() else "\n".join(lines)

func _comparison_print_text(route: Dictionary, peer: Dictionary, index: int) -> String:
 var entries: Array = route.output_history[mini(index, route.actions.size())]
 var peer_compiled := peer.has("actions")
 var other_messages := _prints_at_action(peer, index) if peer_compiled else PackedStringArray()
 var turn: int = route.initial.turn + index
 var message_index := 0
 var lines := PackedStringArray()
 for entry: Dictionary in entries:
  var different := false
  if peer_compiled and entry.turn == turn:
   different = message_index >= other_messages.size() or entry.text != other_messages[message_index]
   message_index += 1
  lines.append(_comparison_text(_print_line(entry), different))
 return "No print output" if lines.is_empty() else "\n".join(lines)

func _comparison_text(value: String, different: bool) -> String:
 # User output is plain text. Only our color tag is interpreted as BBCode.
 var escaped := value.replace("[", "[lb]")
 return COMPARISON_HIGHLIGHT + escaped + "[/color]" if different else escaped

func _comparison_board_at(route: Dictionary, index: int) -> Programs:
 return _board_after_actions(route, mini(index, route.actions.size())) if route.has("actions") else null

func _comparison_blocked(route: Dictionary, index: int) -> bool:
 return route.has("actions") and route.line >= 0 and index >= route.actions.size()

func _comparison_snapshot(route: Dictionary, index: int, preview: Programs, include_summary: bool) -> String:
 if preview == null:
  return route.error
 var traced: Array = route.actions
 var count := mini(index, traced.size())
 var at_end := count == traced.size()
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
 var snapshot := "%s\n%s" % [step, position]
 if not include_summary:
  return snapshot
 var summary := _nursery_summary(preview)
 if not preview.practice:
  var unit := "action" if preview.turn == 1 else "actions"
  summary = "Harvested %d of %d in %d %s · %s" % [
   preview.harvested, preview.plants.size(), preview.turn, unit, _water_summary(preview),
  ]
 return snapshot + "\n" + summary

func _comparison_key_for(draft: String) -> String:
 return ("python:" if python_mode else "classic:") + draft

func _comparison_position_for(other: String) -> Dictionary:
 return {
  "other":other, "view":comparison_view.selected, "action":roundi(comparison_slider.value),
  "start":comparison_start.selected, "limit":comparison_limit, "totals":comparison_totals_choice.selected,
 }

func _close_draft_comparison() -> void:
 if comparison_panel.visible:
  var other: String = comparison_choice.get_item_metadata(comparison_choice.selected)
  comparison_positions[comparison_key] = _comparison_position_for(other)
  comparison_panel.hide()
  comparison_current_route.clear()
  comparison_other_route.clear()
  comparison_differences.clear()
  _draw_grid(comparison_current_board, null)
  _draw_grid(comparison_other_board, null)
  comparison_current_details.text = ""
  comparison_other_details.text = ""
  for editor in [comparison_current_code, comparison_other_code]:
   editor.clear_executing_lines()
   editor.text = ""
  comparison_source = ""
  comparison_best_source = ""
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
 run_to_line = -1
 step_out_frame = {}

func _reset() -> void:
 live_previous_variables = null
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
 var history: Array = checked_route.variable_history
 _draw_diagnostics(preview, "Check", -1, history[-1], null, history[maxi(0, history.size() - 2)])
 if not checked_route.actions.is_empty() or line >= 0:
  review_button.show()

func _trace(commands: Array, fresh_board := false, practice_limit := Programs.MAX_STEPS, capture_comparison := false) -> Dictionary:
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
 preview.track_variable_sources = not capture_comparison
 var traced: Array[Dictionary] = []
 var index := preview.next_action_index(commands, 0)
 # Review position zero includes assignments before the first board action.
 var variable_history: Array[Dictionary] = [preview.inspect_variables()]
 var call_history: Array[Array] = []
 var variable_source_history: Array[Dictionary] = []
 if not capture_comparison:
  call_history.append(preview.inspect_call_stack())
  variable_source_history.append(preview.variable_sources)
 var output_history: Array[Array] = []
 var totals_history: Array[Vector4i] = []
 var capture_output := capture_comparison and python_mode
 if capture_comparison:
  totals_history.append(_comparison_totals(preview))
 if capture_output:
  output_history.append(preview.output.duplicate())
 while index < commands.size() and (not preview.practice or traced.size() < practice_limit):
  var action: Dictionary = commands[index]
  var error := preview.step(action)
  if not error.is_empty():
   return {"actions":traced, "initial":initial, "preview":preview, "line":action.line,
           "error":error, "variable_history":variable_history, "output_history":output_history,
           "totals_history":totals_history, "call_history":call_history, "variable_source_history":variable_source_history}
  traced.append(action)
  var complete := preview.is_complete()
  var revision := preview.variable_revision
  var call_revision := preview.call_revision
  if not complete:
   index = preview.next_action_index(commands, index + 1)
  var values: Dictionary = variable_history.back() if preview.variable_revision == revision else preview.inspect_variables()
  variable_history.append(values)
  if not capture_comparison:
   var calls: Array = call_history[-1] if preview.call_revision == call_revision else preview.inspect_call_stack()
   call_history.append(calls)
   variable_source_history.append({} if complete else preview.variable_sources)
  if capture_comparison:
   totals_history.append(_comparison_totals(preview))
  if capture_output:
   # The current buffer can be reused until another message is printed.
   var printed_this_turn: bool = not preview.output.is_empty() and preview.output.back().turn == preview.turn
   output_history.append(preview.output.duplicate() if printed_this_turn else output_history.back())
  if complete:
   break
 return {"actions":traced, "initial":initial, "preview":preview, "line":preview.runtime_error_line,
         "error":preview.runtime_error, "limited":preview.practice and index < commands.size(),
         "variable_history":variable_history, "output_history":output_history, "totals_history":totals_history,
         "call_history":call_history, "variable_source_history":variable_source_history}

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
 var route := best_route if best_panel.visible else checked_route
 var history: Array = route.variable_history
 _populate_review_variables(history)
 _index_review_changes(history, route.variable_source_history)
 review_slider.max_value = length
 review_slider.set_value_no_signal(0)
 review_slider.visible = length > 0
 review_controls.show()
 _draw_review(0)
 if review_slider.visible:
  review_slider.grab_focus()

func _populate_review_variables(history: Array) -> void:
 var seen: Dictionary = {}
 for snapshot: Dictionary in history:
  for name: String in snapshot:
   seen[name] = true
 var names := seen.keys()
 names.sort()
 review_variable_filter.clear()
 review_variable_filter.add_item("All variables")
 for name: String in names:
  review_variable_filter.add_item(name)
 var index := names.find(review_variable_name)
 if index < 0:
  review_variable_name = ""
 review_variable_filter.select(index + 1)

func _select_review_variable(index: int) -> void:
 if not review_controls.visible:
  return
 review_variable_name = "" if index == 0 else review_variable_filter.get_item_text(index)
 var route := best_route if best_panel.visible else checked_route
 _index_review_changes(route.variable_history, route.variable_source_history)
 _refresh_variables()
 if review_slider.visible:
  review_slider.grab_focus()

func _index_review_changes(history: Array, source_history: Array) -> void:
 review_change_actions.clear()
 for index in range(1, history.size()):
  var before: Dictionary = history[index - 1]
  var after: Dictionary = history[index]
  if is_same(before, after):
   continue
  var changed: bool
  if review_variable_name.is_empty():
   changed = not _variable_mismatches(before, after).is_empty()
  else:
   changed = not is_same(before.get(review_variable_name), after.get(review_variable_name))
  if changed:
   review_change_actions.append(index)
 _rebuild_review_history(history, source_history)

func _rebuild_review_history(history: Array, source_history: Array) -> void:
 review_history_list.clear()
 if review_variable_name.is_empty():
  return
 var initial: Dictionary = history[0]
 var value := Programs.python_value_text(initial[review_variable_name]) if initial.has(review_variable_name) else "unassigned"
 _add_review_history_entry("Start · %s" % value, source_history[0])
 for action in review_change_actions:
  var transition := _format_variable_transition(history[action - 1], history[action], review_variable_name)
  _add_review_history_entry("Action %d · %s" % [action, transition], source_history[action])

func _add_review_history_entry(label: String, sources: Dictionary) -> void:
 var row := review_history_list.item_count
 var line: int = sources.get(review_variable_name, -1)
 review_history_list.add_item(label)
 review_history_list.set_item_metadata(row, line)
 if line >= 0:
  review_history_list.set_item_tooltip(row, "Source line %d" % (line + 1))

func _review_history_source_line() -> int:
 var selected := review_history_list.get_selected_items()
 return -1 if selected.is_empty() else int(review_history_list.get_item_metadata(selected[0]))

func _refresh_history_source_button() -> void:
 var line := _review_history_source_line()
 review_history_source_button.disabled = line < 0
 review_history_source_button.text = "Source line %d · F12" % (line + 1) if line >= 0 else "Source line · F12"

func _jump_to_history_source() -> void:
 if review_history_list.is_visible_in_tree():
  _focus_source_line(_review_history_source_line())

func _jump_to_history_action(row: int) -> void:
 if not review_history_list.is_visible_in_tree() or row < 0 or row >= review_history_list.item_count:
  return
 review_slider.value = 0 if row == 0 else review_change_actions[row - 1]
 _focus_review_timeline()

func _focus_review_timeline() -> void:
 if review_slider.is_visible_in_tree():
  review_slider.grab_focus()
 else:
  (best_source if best_panel.visible else source).grab_focus()

func _review_change_index(forward: bool) -> int:
 var action := roundi(review_slider.value)
 var index := review_change_actions.bsearch(action, not forward)
 return index if forward else index - 1

func _jump_to_review_change(forward: bool) -> void:
 var index := _review_change_index(forward)
 if review_change_row.is_visible_in_tree() and index >= 0 and index < review_change_actions.size():
  review_slider.value = review_change_actions[index]
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
 _draw_diagnostics(route.preview, "Best run" if replaying_best else "Check", preview.turn,
                   route.variable_history[count], route.call_history[count], route.variable_history[maxi(0, count - 1)])

func _prepare_program(target_line := -1) -> bool:
 if best_panel.visible:
  return false
 if not steps.is_empty():
  return _can_run_to(steps, target_line)
 _save_draft_name()
 _commit_target_edit()
 _discard_check()
 var commands := _compile_draft()
 if commands.is_empty() or not _can_run_to(commands, target_line):
  return false
 steps = commands
 live_previous_variables = null
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

func _can_run_to(commands: Array, line: int) -> bool:
 if line < 0 or commands.any(func(instruction): return instruction.line == line and instruction.has("command")):
  return true
 status.text = "Line %d has no board command in this program." % (line + 1)
 return false

func _run(target_line := -1) -> void:
 if running:
  if target_line >= 0:
   return
  running = false
 elif _prepare_program(target_line):
  if target_line >= 0:
   run_to_line = target_line
   step_out_frame = {}
  interval = 0
  running = true
 else:
  return
 _show_progress()
 _draw()

func _step() -> void:
 if not running and _prepare_program():
  step_out_frame = {}
  _advance()

func _step_out() -> void:
 if running:
  return
 if steps.is_empty() or garden.local_frames.is_empty():
  status.text = "Pause inside a Python function to step out."
  return
 # Retain this call's frame. A new call to the same function may be active at the next action.
 step_out_frame = garden.local_frames.back()
 run_to_line = -1
 _run()

func _show_progress() -> void:
 var next: Dictionary = steps[offset]
 status.text = "%s · %d actions · next line %d" % [
  "Running" if running else "Paused", garden.run_action_count(), next.line + 1,
 ]
 if garden.practice:
  status.text += " · %d / %d lilies this run" % [garden.run_harvest_count(), garden.harvest_target]
 if run_to_line >= 0:
  status.text += " · Cursor line %d" % (run_to_line + 1)
 elif not step_out_frame.is_empty():
  status.text += " · Stepping out of %s()" % step_out_frame.function

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
 var cursor_reached: bool = action.line == run_to_line
 var call_returned := not step_out_frame.is_empty() and not garden.local_frames.any(func(frame): return is_same(frame, step_out_frame))
 if cursor_reached or call_returned or (breakpoint_offset != offset and source.is_line_breakpointed(action.line)):
  running = false
  breakpoint_offset = offset
  var reason := "Breakpoint"
  if cursor_reached:
   reason = "Cursor"
   run_to_line = -1
  elif call_returned:
   reason = "Step out"
   step_out_frame = {}
  var actions_count := garden.run_action_count()
  var unit := "action" if actions_count == 1 else "actions"
  status.text = "%s · line %d · %d %s" % [reason, action.line + 1, actions_count, unit]
  _mark_line(source, action.line)
  _draw()
  return
 _advance()

func _advance() -> void:
 breakpoint_offset = -1
 var action: Dictionary = steps[offset]
 if action.line == run_to_line:
  run_to_line = -1
 var before := garden.harvested
 var before_variables := garden.inspect_variables()
 var error: String = garden.step(action)
 if not error.is_empty():
  _clear_program()
  _line_error("Line %d · %s" % [action.line + 1, error], action.line, garden)
 else:
  live_previous_variables = before_variables
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
   Progress.ALDER_CROSSING_MARKER:
    label = "Unlock Alder Crossing"
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
 var has_copies := draft_choice.item_count > 1
 draft_bar.visible = not best_panel.visible
 draft_choice.visible = has_copies
 draft_choice.disabled = active
 duplicate_draft_button.disabled = active
 compare_drafts_button.visible = has_copies or not _best_source_for_comparison(item.id, nursery_record).is_empty()
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

func _format_program_output(entries: Array, through_turn := -1) -> String:
 var lines := PackedStringArray()
 for entry: Dictionary in entries:
  if through_turn < 0 or entry.turn <= through_turn:
   lines.append(_print_line(entry))
 return "\n".join(lines)

func _print_line(entry: Dictionary) -> String:
 return "Line %d · %s" % [entry.line + 1, entry.text]

func _draw_diagnostics(view: Programs, context := "Program", through_turn := -1,
                       snapshot: Variant = null, calls: Variant = null, previous: Variant = null) -> void:
 var transcript := _format_program_output(view.output, through_turn)
 output_panel.visible = not transcript.is_empty()
 output_title.text = context + " output"
 if output_text.text != transcript:
  output_text.text = transcript
 var values: Dictionary = view.inspect_variables() if snapshot == null else snapshot
 var baseline: Variant = live_previous_variables if view == garden else previous
 _show_variables(values, context, view.inspect_call_stack() if calls == null else calls,
                 values if baseline == null else baseline)

func _show_variables(values: Dictionary, context: String, calls: Array = [], previous: Dictionary = {}) -> void:
 displayed_variables = values
 displayed_previous_variables = previous
 if displayed_calls != calls:
  var selected := call_stack_list.get_selected_items()
  var selected_call: Dictionary = displayed_calls[selected[0]] if not selected.is_empty() else {}
  displayed_calls = calls
  _refresh_call_stack_list(displayed_calls.find(selected_call))
 diagnostics_context = context
 _refresh_variables()

func _refresh_variables() -> void:
 variables_button.visible = best_python if best_panel.visible else python_mode
 variables_panel.visible = variables_button.visible and variables_button.button_pressed
 var show_calls := call_stack_button.button_pressed
 var show_changes := variable_changes_button.button_pressed
 var show_review_changes := review_controls.visible and variables_panel.visible and show_changes
 review_variable_row.visible = show_review_changes and review_variable_filter.item_count > 1
 review_history_button.visible = show_review_changes and not review_variable_name.is_empty()
 if not review_controls.visible or review_variable_name.is_empty():
  review_history_button.set_pressed_no_signal(false)
 var show_history := review_history_button.visible and review_history_button.button_pressed
 review_history_list.visible = show_history
 review_history_source_button.visible = show_history
 review_change_row.visible = show_review_changes and not review_change_actions.is_empty()
 if review_change_row.visible:
  review_previous_change.disabled = _review_change_index(false) < 0
  review_next_change.disabled = _review_change_index(true) >= review_change_actions.size()
 var view_name := "changes" if show_changes else "variables"
 if show_history:
  view_name = "history"
 if show_calls:
  view_name = "call stack"
 variables_title.text = "%s %s" % [diagnostics_context, view_name]
 variables_text.visible = not show_calls and not show_history
 call_stack_row.visible = show_calls
 variables_panel.size_flags_stretch_ratio = 2.0 if show_calls and not displayed_calls.is_empty() else 1.0
 if not variables_panel.visible:
  return
 if show_history:
  var row := review_change_actions.bsearch(roundi(review_slider.value), false)
  review_history_list.select(row)
  review_history_list.ensure_current_is_visible()
  _refresh_history_source_button()
  return
 if show_calls:
  _refresh_frame_variables()
  return
 var content := _format_variable_changes() if show_changes else _format_program_variables(displayed_variables)
 if variables_text.text != content:
  variables_text.text = content

func _refresh_call_stack_list(selection: int) -> void:
 call_stack_list.clear()
 for call: Dictionary in displayed_calls:
  call_stack_list.add_item("%s() · called at line %d" % [call.function, int(call.line) + 1])
 call_stack_list.add_item("Top level", null, false)
 if not displayed_calls.is_empty():
  call_stack_list.select(maxi(0, selection))

func _refresh_frame_variables() -> void:
 var selected := call_stack_list.get_selected_items()
 frame_variables_panel.visible = not selected.is_empty()
 if selected.is_empty():
  return
 var function: String = displayed_calls[selected[0]].function
 var prefix := Programs.local_variable_prefix(function)
 var locals: Dictionary = {}
 for variable: String in displayed_variables:
  if variable.begins_with(prefix):
   locals[variable.trim_prefix(prefix)] = displayed_variables[variable]
 frame_variables_title.text = "%s() locals" % function
 var content := _format_program_variables(locals)
 if frame_variables_text.text != content:
  frame_variables_text.text = content

func _open_call_site(index: int) -> void:
 if index < 0 or index >= displayed_calls.size():
  return
 _focus_source_line(displayed_calls[index].line)

func _focus_source_line(line: int) -> void:
 var editor := best_source if best_panel.visible else source
 if not editor.is_visible_in_tree() or line < 0 or line >= editor.get_line_count():
  return
 # Navigation changes the caret without replacing the existing execution marker.
 editor.grab_focus()
 editor.deselect()
 editor.remove_secondary_carets()
 editor.set_caret_line(line)
 editor.set_caret_column(0)

func _format_program_variables(values: Dictionary) -> String:
 var names := values.keys()
 names.sort()
 var lines := PackedStringArray()
 for variable: String in names:
  lines.append("%s = %s" % [variable, Programs.python_value_text(values[variable])])
 return "\n".join(lines) if not lines.is_empty() else "No variables assigned"

func _format_variable_changes() -> String:
 var before := displayed_previous_variables
 var after := displayed_variables
 var variable_filter := review_variable_name if review_controls.visible else ""
 var names: Array
 if variable_filter.is_empty():
  names = _variable_mismatches(before, after).keys()
  names.sort()
 elif is_same(before.get(variable_filter), after.get(variable_filter)):
  return "No change to %s" % variable_filter
 else:
  names = [variable_filter]
 var lines := PackedStringArray()
 for variable: String in names:
  lines.append("%s = %s" % [variable, _format_variable_transition(before, after, variable)])
 return "\n".join(lines) if not lines.is_empty() else "No variable changes"

func _format_variable_transition(before: Dictionary, after: Dictionary, variable: String) -> String:
 var old := Programs.python_value_text(before[variable]) if before.has(variable) else "unassigned"
 var new := Programs.python_value_text(after[variable]) if after.has(variable) else "out of scope"
 return "%s → %s" % [old, new]

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
    style.border_color = Color(COMPARISON_GOLD)
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
   elif review_history_list.has_focus():
    _focus_review_timeline()
   elif call_stack_list.has_focus():
    (best_source if best_panel.visible else source).grab_focus()
   elif best_panel.visible:
    _close_best_program()
   else:
    _close()
   get_viewport().set_input_as_handled()
  elif event.ctrl_pressed and event.keycode == KEY_PAGEDOWN and next_lesson_button.visible:
   _continue_lessons()
   get_viewport().set_input_as_handled()
  elif comparison_slider.has_focus() and not comparison_differences.is_empty() and event.get_modifiers_mask() == 0 and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
   _jump_to_adjacent_comparison_difference(event.keycode == KEY_PAGEDOWN)
   get_viewport().set_input_as_handled()
  elif review_slider.has_focus() and review_change_row.is_visible_in_tree() and event.get_modifiers_mask() == 0 and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
   _jump_to_review_change(event.keycode == KEY_PAGEDOWN)
   get_viewport().set_input_as_handled()
  elif event.keycode == KEY_F7 and variables_button.visible:
   var show_calls: bool = event.shift_pressed
   var show_changes: bool = event.ctrl_pressed and not show_calls
   if event.ctrl_pressed and event.shift_pressed:
    if review_controls.visible and not review_variable_name.is_empty():
     call_stack_button.set_pressed_no_signal(false)
     variable_changes_button.set_pressed_no_signal(true)
     variables_button.set_pressed_no_signal(true)
     review_history_button.set_pressed_no_signal(true)
     _refresh_variables()
     review_history_list.grab_focus()
   elif show_calls and variables_panel.visible and call_stack_button.button_pressed:
    call_stack_list.grab_focus()
   else:
    var return_focus := call_stack_list.has_focus()
    var return_to_timeline := review_history_list.has_focus()
    var different_view := call_stack_button.button_pressed != show_calls or variable_changes_button.button_pressed != show_changes or review_history_button.button_pressed
    var reveal := not variables_button.button_pressed or different_view
    call_stack_button.set_pressed_no_signal(show_calls)
    variable_changes_button.set_pressed_no_signal(show_changes)
    review_history_button.set_pressed_no_signal(false)
    variables_button.set_pressed_no_signal(reveal)
    _refresh_variables()
    if return_focus:
     (best_source if best_panel.visible else source).grab_focus()
    elif return_to_timeline:
     _focus_review_timeline()
   get_viewport().set_input_as_handled()
  elif event.keycode == KEY_F12 and review_history_list.has_focus():
   _jump_to_history_source()
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
   if event.ctrl_pressed:
    if not source.has_focus():
     return
    _run(source.get_caret_line())
   else:
    _step()
   get_viewport().set_input_as_handled()
  elif python_mode and event.keycode == KEY_F11 and event.get_modifiers_mask() == KEY_MASK_SHIFT and source.has_focus():
   _step_out()
   get_viewport().set_input_as_handled()
