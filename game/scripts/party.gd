class_name ExplorerParty
extends Node

const MAX_LOCAL=4
const MAX_PLAYERS=8
var game:Node3D
var records:Array[Dictionary]=[]
var own_peer=1
var lan
var canvas:CanvasLayer
var panels:Array[Dictionary]=[]
var split_root:Control
var menu:PanelContainer
var address:LineEdit
var status_label:Label
var menu_paused=false
var view_size=Vector2.ZERO
var message="Press Start on another controller to join. F4 opens multiplayer."
var notice_time=0.0

func _ready():
 name="Party"
 records.append({"key":"1:0","peer":1,"index":0,"slot":game,"local":true,"device":game.controls.device})
 game.controls.auto_assign=false
 Input.joy_connection_changed.connect(_connection)
 canvas=CanvasLayer.new();canvas.layer=3;add_child(canvas)
 split_root=Control.new();split_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);split_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(split_root)
 _menu()
 lan=load("res://scripts/lan.gd").new();lan.name="Lan";lan.party=self;lan.game=game;add_child(lan)
 _layout()

func local_records()->Array[Dictionary]:
 var result:Array[Dictionary]=records.filter(func(r):return r.local)
 result.sort_custom(func(a,b):return a.index<b.index)
 return result
func record_for(slot)->Dictionary:
 for r in records:
  if r.slot==slot:return r
 return {}
func record_key(key:String)->Dictionary:
 for r in records:
  if r.key==key:return r
 return {}

func tell(text:String):
 message=text;notice_time=4;game.hud.toast(text)

func _input(event):
 if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F4:
  toggle_menu();get_viewport().set_input_as_handled();return
 if event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START:
  for r in local_records():
   if r.device==event.device:return
  join_local(event.device);get_viewport().set_input_as_handled()

func _connection(id:int,connected:bool):
 if connected:
  tell("Controller connected. Press its Start button to join.");return
 for r in local_records():
  if r.device!=id:continue
  r.slot.controls.neutralize()
  if r.index==0:r.device=-1;r.slot.controls.assign_device(-1);tell("Player 1 controller disconnected. Keyboard controls are available.")
  else:remove_local(r.key);tell("Player %d left. Remaining controllers keep their frogs."%(r.index+1))
  break

func join_local(device:int)->bool:
 if menu.visible or game.travel.busy:tell("Finish the current menu or trip before joining.");return false
 for r in local_records():
  if r.device==device:return false
 var first=local_records()[0]
 if first.device<0:
  first.device=device;first.slot.controls.assign_device(device);first.slot.controls.neutralize();tell("Controller assigned to Player 1.");return true
 if local_records().size()>=MAX_LOCAL or (not lan.is_client() and records.size()>=MAX_PLAYERS):tell("The local or party player limit has been reached.");return false
 var index=1
 while local_records().any(func(r):return r.index==index):index+=1
 var record=add_record(own_peer,index,true,device)
 record.slot.pilot.select_species(index%FrogPilot.SPECIES.size())
 record.slot.controls.neutralize()
 _layout();lan.local_roster_changed();tell("Player %d joined. Each controller now has its own frog and camera."%(index+1));return true

func add_record(peer:int,index:int,is_local:bool,device=-1)->Dictionary:
 var key="%d:%d"%[peer,index];var existing=record_key(key)
 if not existing.is_empty():return existing
 var slot=ExplorerPlayerSlot.new();slot.game=game;slot.name="Player_"+key.replace(":","_");add_child(slot)
 slot.controls.hardware_enabled=is_local;slot.controls.assign_device(device)
 var record={"key":key,"peer":peer,"index":index,"slot":slot,"local":is_local,"device":device}
 records.append(record)
 var spawn=nearby_spawn(game.woodland,game.woodland.spawn_point,records.size()-1,1)
 slot.pilot.reset_position(spawn);slot.pilot.select_species((records.size()-1)%FrogPilot.SPECIES.size())
 slot.pilot.set_physics_process(not lan.is_client())
 _layers();return record

func remove_record(key:String):
 var record=record_key(key)
 if record.is_empty() or record.slot==game:return
 records.erase(record);record.slot.dispose();_layout()

func remove_local(key:String):
 var record=record_key(key)
 if record.is_empty() or not record.local or record.index==0:return
 remove_record(key);lan.local_roster_changed()

func set_own_peer(peer:int):
 own_peer=peer
 for r in local_records():r.peer=peer;r.key="%d:%d"%[peer,r.index]

func nearby_spawn(world:WoodlandWorld,base:Vector3,index:int,mask:int)->Vector3:
 var offsets=[Vector3.ZERO,Vector3(.65,0,0),Vector3(-.65,0,0),Vector3(0,0,.65),Vector3(.65,0,.65),Vector3(-.65,0,.65),Vector3(0,0,-.65),Vector3(.65,0,-.65)]
 for n in range(offsets.size()):
  var point=base+offsets[(index+n)%offsets.size()]
  var result=FrogPlacement.arrival(world,point,1,mask)
  if not result.is_empty():return result.position
 return base # the common, checked arrival is valid; frogs do not body-block

func before_travel():
 for r in records:
  if r.slot==game:continue
  r.slot.rides.clear_for_travel();r.slot.pilot.release_contacts()

func after_travel():
 for i in range(records.size()):
  var slot=records[i].slot
  slot.pilot.woodland=game.woodland;slot.camera_rig.woodland=game.woodland
  if slot!=game:
   slot.pilot.arrive_at_default_size(nearby_spawn(game.woodland,game.woodland.spawn_point,i,1))
   slot.controls.neutralize();slot.controls.resize_wait_for_release=true
  slot.camera_rig.initialized=false;slot.rides.trigger_armed=false
 _layers();lan.world_changed()

func can_travel(slot)->bool:
 return slot==game and not lan.is_client()

func _layers():
 var shared=records.size()>1
 for i in range(records.size()):
  var slot=records[i].slot;var p=slot.pilot
  p.actor_layer=4 if shared else 1
  p.set_render_layer((1<<(4+i)) if shared else 0)
  p.model.visible=true
  p.collision_layer=0 if lan.is_client() or slot.rides.active() else p.actor_layer
  p.collision_mask=0 if lan.is_client() or slot.rides.active() else 1
  if slot.rides.active():slot.rides.body.collision_layer=0 if lan.is_client() else p.actor_layer
 for tree in game.woodland.trees:
  for canopy in tree.canopy:canopy.layers=(15<<16) if shared else 1;canopy.visible=true
 for i in range(local_records().size()):
  var camera=local_records()[i].slot.camera_rig;camera.shared_views=shared;camera.view_index=i;camera.environment_world=null

func _layout():
 for view in panels:
  if is_instance_valid(view.camera) and view.camera.is_inside_tree():view.camera.reparent(game);view.camera.current=false
  split_root.remove_child(view.container);view.container.queue_free()
 panels.clear()
 var locals=local_records();game.hud.visible=locals.size()==1
 get_viewport().audio_listener_enable_3d=locals.size()==1
 if locals.size()==1:
  game.camera_rig.reparent(game);game.camera_rig.set_process(true);game.camera_rig.make_current()
 else:
  for r in locals:
   var container=SubViewportContainer.new();container.stretch=true;container.mouse_filter=Control.MOUSE_FILTER_IGNORE;split_root.add_child(container)
   var viewport=SubViewport.new();viewport.world_3d=game.get_world_3d();viewport.handle_input_locally=false;viewport.gui_disable_input=true
   viewport.msaa_3d=Viewport.MSAA_DISABLED;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
   viewport.audio_listener_enable_3d=r.index==0;container.add_child(viewport)
   var camera=r.slot.camera_rig;camera.reparent(viewport);camera.set_process(true);camera.make_current();camera.initialized=false
   var overlay=Label.new();overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.position=Vector2(12,12);overlay.add_theme_font_size_override("font_size",16)
   overlay.add_theme_color_override("font_outline_color",Color(.01,.02,.01));overlay.add_theme_constant_override("outline_size",5);container.add_child(overlay)
   panels.append({"container":container,"viewport":viewport,"camera":camera,"label":overlay,"record":r})
 _rects();_layers()

func _rects():
 view_size=get_viewport().get_visible_rect().size
 for i in range(panels.size()):
  var panel=panels[i];var columns=2;var rows=1 if panels.size()==2 else 2
  var size=view_size/Vector2(columns,rows)
  panel.container.position=Vector2(i%columns,i/columns)*size;panel.container.size=size

func _physics_process(delta):
 for r in records:
  if r.slot!=game and (r.local or not lan.is_client()):game.tick_player(r.slot,delta)

func _process(delta):
 notice_time=maxf(0,notice_time-delta)
 if get_viewport().get_visible_rect().size!=view_size:_rects()
 for r in records:
  if r.slot!=game:r.slot.hud.update(delta,r.slot.pilot,r.slot.camera_rig,r.slot.controls,game.ros)
 for view in panels:
  var r=view.record;var slot=r.slot;var p=slot.pilot
  var legend="X jump · Y fly · A croak · B silly\nLB frog · RB camera · L3 trigger mode\nStart help · F4 multiplayer"
  if slot.controls.device<0 and slot.controls.keyboard_enabled:legend="WASD move · Space jump · F fly · V croak\nTab frog · C camera · +/- size · F3 rides\n1 balloon · 2 car · I/K altitude · J/L strafe\nEsc help · F4 multiplayer"
  view.label.text="P%d · %s\n%s\n%s · %s · %.2fx\n%s\nFlies %d · %s\n\n%s"%[r.index+1,FrogPilot.SPECIES[p.species].name,slot.controls.device_name,p.mode,ExplorerCamera.NAMES[slot.camera_rig.view_mode],p.metrics.factor,game.travel.place(game.travel.current_id).get("name",""),p.flies_caught,("LT balloon / RT car" if slot.rides.enabled else "LT grow / RT shrink"),slot.hud.notice_label.text if slot.hud.toast_time>0 else (message if notice_time>0 else legend)]
  if p.paused:view.label.text+="\n\nPAUSED · Start resumes\nLeft stick move / climb\nRight stick strafe / swim / balloon altitude"
 status_label.text=lan.status+"\n%d local · %d frogs in this place\n%s"%[local_records().size(),records.size(),message]

func _menu():
 menu=game.hud.panel();menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER);menu.position=Vector2(-300,-250);menu.custom_minimum_size=Vector2(600,500);menu.visible=false;canvas.add_child(menu)
 var box=VBoxContainer.new();box.add_theme_constant_override("separation",12);menu.add_child(box)
 box.add_child(game.hud.label("PLAY TOGETHER",25));box.add_child(game.hud.label("Local: press Start on each extra controller (up to four).",16))
 address=LineEdit.new();address.placeholder_text="Host LAN IP, e.g. 192.168.1.25:24970";address.text="127.0.0.1:24970";box.add_child(address)
 for item in [["Host LAN game",func():lan.host(24970)],["Join this address",func():lan.join(address.text)],["Disconnect LAN",func():lan.disconnect_session()],["Remove last local player",func():
  var locals=local_records()
  if locals.size()>1:remove_local(locals.back().key)
 ],["Keep exploring (F4)",func():toggle_menu()]]:
  var button=Button.new();button.text=item[0];button.pressed.connect(item[1]);box.add_child(button)
 status_label=game.hud.label("",15);status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status_label.custom_minimum_size=Vector2(550,90);box.add_child(status_label)

func toggle_menu():
 if menu.visible:menu.visible=false;game.pilot.paused=menu_paused;return
 if game.travel_menu.visible:game.travel_menu.close()
 menu_paused=game.pilot.paused;game.pilot.paused=true;menu.visible=true;address.grab_focus()

func state()->Dictionary:
 var players=[]
 for r in records:
  var p=r.slot.pilot
  players.append({"player_id":r.key,"local":r.local,"position":[p.position.x,p.position.y,p.position.z],"species":FrogPilot.SPECIES[p.species].name,"scale":p.metrics.factor,"mode":p.mode,"ride":r.slot.rides.kind,"flies_caught":p.flies_caught})
 return {"players":players,"player_count":records.size(),"local_player_count":local_records().size(),"multiplayer_mode":lan.role,"primary_player_id":local_records()[0].key}

func shutdown():
 lan.close_peer()
 for r in records:
  if r.slot!=game:r.slot.rides.clear_for_travel();r.slot.pilot.paused=true;r.slot.pilot.sound.stop();r.slot.pilot.sound.stream=null
