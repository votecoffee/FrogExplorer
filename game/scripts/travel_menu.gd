class_name ExplorerTravelMenu
extends CanvasLayer

var game:Node3D
var panel:PanelContainer
var rows:VBoxContainer
var scroll:ScrollContainer
var details:Label
var history_label:Label
var buttons:Array[Button]=[]
var destinations:Array[String]=[]
var selected=0
var was_paused=false
const CATEGORIES=["any","city","history","nature"]

func _ready():
 visible=false;layer=5
 panel=game.hud.panel();panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
 panel.position=Vector2(-350,-330);panel.custom_minimum_size=Vector2(700,660);add_child(panel)
 var box=VBoxContainer.new();box.add_theme_constant_override("separation",10);panel.add_child(box)
 box.add_child(game.hud.label("WHERE SHALL WE HOP?",25,Color(.93,.92,.66)))
 box.add_child(game.hud.label("Installed places · left stick / arrows to choose · A / Enter to go",16))
 scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(650,270);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;box.add_child(scroll)
 rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",8);scroll.add_child(rows)
 details=game.hud.label("",16);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size=Vector2(650,90);box.add_child(details)
 history_label=game.hud.label("",14,Color(.67,.79,.70));history_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(history_label)
 box.add_child(game.hud.label("B / Esc closes · H returns home · Back / T travels at random",15))

func open():
 if visible:return
 was_paused=game.pilot.paused;game.pilot.paused=true;visible=true;selected=0;_populate()

func close():
 visible=false;game.pilot.paused=was_paused

func _populate():
 for button in buttons:rows.remove_child(button);button.queue_free()
 buttons.clear();destinations.clear()
 for item in game.travel.available_places():
  destinations.append(str(item.id));_button(str(item.name)+( "  · you are here" if item.id==game.travel.current_id else ""))
 destinations.append("@random");_button("Take me somewhere new")
 destinations.append("@category");_button("Random travel category: "+game.travel.category.capitalize())
 destinations.append("@close");_button("Keep exploring")
 selected=mini(selected,buttons.size()-1);_highlight()
 var names=[]
 for id in game.travel.history.slice(maxi(0,game.travel.history.size()-4)):
  names.append(str(game.travel.place(id).get("name",id)))
 history_label.text="Recent visits: "+(" → ".join(names) if not names.is_empty() else "Your first journey awaits.")

func _button(text:String):
 var index=buttons.size();var button=Button.new();button.text=text;button.alignment=HORIZONTAL_ALIGNMENT_LEFT
 button.custom_minimum_size=Vector2(650,39);button.add_theme_font_size_override("font_size",18);button.focus_mode=Control.FOCUS_NONE
 button.pressed.connect(_click.bind(index));rows.add_child(button);buttons.append(button)

func _click(index:int):selected=index;_activate()

func _highlight():
 for i in range(buttons.size()):buttons[i].modulate=Color(1,1,.60) if selected==i else Color(.78,.87,.81)
 scroll.ensure_control_visible.call_deferred(buttons[selected])
 var id=destinations[selected]
 if not id.begins_with("@"):details.text=str(game.travel.place(id).get("description",""))
 elif id=="@category":details.text="Choose the kind of place for random travel. Only installed, checked packs are eligible. The 120-place research list is not playable yet."
 elif id=="@random":
  var count=game.travel.available_places().filter(func(item):return item.get("random_eligible",false)).size()
  details.text="%d real-world packs are available to everyone in this game. Random travel excludes this place and prefers places you have not visited recently. Choose city areas or historic landmarks. Scene coverage and close-up detail vary."%count
 else:details.text="Return to your frog without changing location."

func _activate():
 var id=destinations[selected]
 if id=="@category":
  game.travel.category=CATEGORIES[(CATEGORIES.find(game.travel.category)+1)%CATEGORIES.size()];_populate();return
 close()
 if id=="@random":game.travel.random_trip()
 elif id!="@close":game.travel.request(id)

func handle_action(action:String)->bool:
 match action:
  "help","travel_menu","silly":close()
  "jump","croak":_activate()
  "travel_random":close();game.travel.random_trip()
  "travel_home":close();game.travel.cancel();game.travel.request("home_woodland_pond")
  "travel_cancel":game.travel.cancel();close()
 return true

func _input(event:InputEvent):
 if not visible:return
 if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device!=game.controls.device:return
 if event.is_action_pressed("ui_down"):
  selected=posmod(selected+1,buttons.size());_highlight();get_viewport().set_input_as_handled()
 elif event.is_action_pressed("ui_up"):
  selected=posmod(selected-1,buttons.size());_highlight();get_viewport().set_input_as_handled()
 elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER,KEY_KP_ENTER]:
  _activate();get_viewport().set_input_as_handled()
