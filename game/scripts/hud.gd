class_name ExplorerHUD
extends CanvasLayer

var place_label:Label
var travel_label:Label
var species_label:Label
var state_label:Label
var size_label:Label
var score_label:Label
var connection_label:Label
var notice_label:Label
var debug_label:Label
var help:PanelContainer
var gamepad_legend:PanelContainer
var trigger_legend:Label
var keyboard_legend:Label
var toast_time=0.0
var debug_enabled=false

func label(text,size=18,color=Color(.9,.94,.83)):
 var n=Label.new();n.text=text;n.add_theme_font_size_override("font_size",size);n.add_theme_color_override("font_color",color);return n

func panel():
 var n=PanelContainer.new();var style=StyleBoxFlat.new();style.bg_color=Color(.025,.08,.065,.88);style.corner_radius_top_left=14;style.corner_radius_top_right=14;style.corner_radius_bottom_left=14;style.corner_radius_bottom_right=14;style.content_margin_left=18;style.content_margin_right=18;style.content_margin_top=12;style.content_margin_bottom=12;n.add_theme_stylebox_override("panel",style);return n

func _ready():
 var root=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(root)
 var brand=panel();brand.position=Vector2(22,20);root.add_child(brand);var box=VBoxContainer.new();brand.add_child(box)
 box.add_child(label("F R O G  E X P L O R E R",23,Color(.89,.93,.65)))
 place_label=label("Woodland pond",16,Color(.65,.77,.64));box.add_child(place_label)
 travel_label=label("",13,Color(.88,.86,.66));box.add_child(travel_label)
 var status=panel();status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);status.position=Vector2(-345,20);status.custom_minimum_size=Vector2(323,105);root.add_child(status)
 var stack=VBoxContainer.new();status.add_child(stack);species_label=label("",20);state_label=label("",15);score_label=label("",15,Color(.88,.79,.42));stack.add_child(species_label);stack.add_child(state_label);size_label=label("",15,Color(.73,.87,.88));stack.add_child(size_label);stack.add_child(score_label)
 gamepad_legend=panel();gamepad_legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);gamepad_legend.position=Vector2(22,-148);gamepad_legend.visible=false;root.add_child(gamepad_legend)
 var cb=VBoxContainer.new();gamepad_legend.add_child(cb);cb.add_child(label("Gamepad:  X  Jump    Y  Catch a fly    A  Croak    B  Be silly",17));cb.add_child(label("LB  Switch frog    RB  Camera    Left stick  Move    Right stick  Strafe / depth",14,Color(.68,.79,.68)))
 trigger_legend=label("",14,Color(.68,.79,.68));cb.add_child(trigger_legend)
 cb.add_child(label("L3  Trigger mode    Back  Travel    R3  Places    Start  Help",14,Color(.68,.79,.68)))
 cb.add_child(label("Extra controller: Start to join    F4: multiplayer",14,Color(.68,.79,.68)))
 keyboard_legend=label("KEYBOARD\nWASD / arrows  Move / climb\nSpace / X  Jump\nF / Y  Catch a fly    V  Croak\nB / G  Silly    Tab / Q  Switch frog\nC  Camera    J / L  Strafe / circle tree\nI / K  Swim up / down\n+ / -  Grow / shrink    0  Normal size\nF3  Trigger mode    1  Balloon    2  Car\nSpace / X  Jump out    3  Controlled exit\nR  Recover here    H  Return to pond\nT  Travel / cancel    N  Places    M  Mute\nEsc / F1  Help / pause    F2  Input details\nF4  Multiplayer / LAN host or join",15)
 keyboard_legend.name="KeyboardLegend";keyboard_legend.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;keyboard_legend.mouse_filter=Control.MOUSE_FILTER_IGNORE;keyboard_legend.visible=false
 keyboard_legend.add_theme_color_override("font_outline_color",Color(.015,.025,.02,.95));keyboard_legend.add_theme_constant_override("outline_size",4)
 keyboard_legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
 var legend_size=keyboard_legend.get_combined_minimum_size()
 keyboard_legend.offset_left=-22-legend_size.x;keyboard_legend.offset_right=-22;keyboard_legend.offset_top=-54-legend_size.y;keyboard_legend.offset_bottom=-54
 root.add_child(keyboard_legend)
 connection_label=label("",13,Color(.64,.75,.65));connection_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);connection_label.position=Vector2(-330,-35);root.add_child(connection_label)
 notice_label=label("",18,Color(.95,.92,.64));notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);notice_label.position=Vector2(-260,-160);notice_label.size=Vector2(520,32);notice_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;root.add_child(notice_label)
 debug_label=label("",13);debug_label.position=Vector2(24,150);debug_label.visible=false;root.add_child(debug_label)
 help=panel();help.set_anchors_and_offsets_preset(Control.PRESET_CENTER);help.position=Vector2(-370,-310);help.custom_minimum_size=Vector2(740,620);help.visible=false;root.add_child(help)
 var hb=VBoxContainer.new();hb.add_theme_constant_override("separation",8);help.add_child(hb)
 hb.add_child(label("WELCOME TO THE WOODLAND POND",24,Color(.93,.92,.66)))
 hb.add_child(label("Move into a tree trunk to grab it automatically.",18))
 hb.add_child(label("Climbing: left stick up / down, right stick sideways.",17))
 hb.add_child(label("Swimming: right stick up / down changes depth.",17))
 hb.add_child(label("X jumps from land, out of water, or away from a tree.",17))
 hb.add_child(label("LB cycles all %d frogs. RB cycles all three views."%FrogPilot.SPECIES.size(),17))
 hb.add_child(label("Hold LT to grow; RT to shrink. Speed follows size.",17))
 hb.add_child(label("L3 / F3: size or ride triggers. LT balloon; RT convertible.",17))
 hb.add_child(label("Balloon: right stick up/down altitude, left/right strafe.",17))
 hb.add_child(label("X / Space: jump out    3: controlled exit    1 / 2: balloon / car.",17))
 hb.add_child(label("Keyboard",20,Color(.93,.92,.66)))
 hb.add_child(label("WASD / arrows: move / climb    Space / X: jump",17))
 hb.add_child(label("F / Y: catch a fly    V: croak    B / G: silly",17))
 hb.add_child(label("Tab / Q: switch frog    C: change camera",17))
 hb.add_child(label("J / L or Z / E: strafe    I / K or PgUp / PgDn: swim",17))
 hb.add_child(label("Hold + / -: grow / shrink    0: normal size",17))
 hb.add_child(label("R: recover here    H: home pond    M: mute    F2: input details",17))
 hb.add_child(label("Back / T: random travel    R3 / N: places    Esc: cancel travel",16))
 hb.add_child(label("Esc / F1 / Start: resume",18,Color(.93,.92,.66)))
 hb.add_child(label("Extra controller: Start joins    F4: split screen / LAN options",16))

func toast(text):
 notice_label.text=text;toast_time=3.5

func update(delta,pilot,camera,controls,link):
 keyboard_legend.visible=controls.device<0
 gamepad_legend.visible=controls.device>=0
 toast_time=maxf(0,toast_time-delta)
 if toast_time==0:notice_label.text=""
 species_label.text=FrogPilot.SPECIES[pilot.species].name
 var mode={"LAND":"On land","SWIM":"Swimming · %.2f m deep"%maxf(0,-pilot.position.y),"CLIMB":"Climbing"}.get(pilot.mode,pilot.mode)
 state_label.text=mode+"\n"+ExplorerCamera.NAMES[camera.view_mode]
 size_label.text="Size %.2fx  |  Walk %.2f m/s"%[pilot.metrics.factor,pilot.metrics.walk_speed()]
 if pilot.resize_blocked:size_label.text+="  (blocked)"
 var rides=pilot.rides
 trigger_legend.text="LT  Balloon    RT  Convertible    X  Jump out" if rides and rides.enabled else "LT  Grow    RT  Shrink    Hold both equally to keep size"
 if rides and rides.active():
  var ride_text="Convertible · %.0f km/h"%(absf(rides.speed)*3.6)
  if rides.kind=="BALLOON":ride_text="Helium balloon · %.0f km/h · %.1f m above ground"%[Vector2(rides.body.velocity.x,rides.body.velocity.z).length()*3.6,rides.state().ride_altitude_m]
  elif rides.kind=="PARACHUTE":ride_text="Parachuting · %.0f m/s down · LT balloon · car after landing"%maxf(0,-rides.body.velocity.y)
  elif rides.kind=="COAST":ride_text="Coasting · %.0f km/h"%(rides.speed*3.6)
  state_label.text=ride_text+"\n"+ExplorerCamera.NAMES[camera.view_mode]
  size_label.text="Ride triggers · L3 / F3 switches controls"
 elif rides and rides.enabled:size_label.text+="  |  Ride triggers"
 score_label.text="Flies caught  %02d"%pilot.flies_caught
 connection_label.text=("ROS 2 connected" if link.connected else "Local play · ROS 2 offline")+"  /  "+("Gamepad" if controls.device>=0 else "Keyboard")
 debug_label.visible=debug_enabled
 if debug_enabled:debug_label.text="%s\nAxes: %s\nButtons: %s\nAnimation: %s  /  %.0f FPS"%[ExplorerGamepadProfile.diagnostics(controls.device_profile),str(controls.raw_axes),str(controls.raw_buttons),pilot.current_clip,Engine.get_frames_per_second()]
 if debug_enabled and pilot.woodland is TiledMeshWorld:
  var stream=pilot.woodland.streaming_state()
  debug_label.text+="\nScenery: %d/%d tiles, %d pending\n%s"%[stream.resident,stream.total,stream.pending,stream.error]

func update_place(travel:WorldTravel):
 var item=travel.place(travel.current_id)
 place_label.text=str(item.get("name","Woodland pond"))
 travel_label.text=(travel.message+"  %d%%"%int(travel.progress*100)) if travel.busy else str(item.get("attribution",""))
