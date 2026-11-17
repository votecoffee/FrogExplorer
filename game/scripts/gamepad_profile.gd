class_name ExplorerGamepadProfile
extends RefCounted

# Identification and setup hints only. SDL/Godot owns raw button/axis mapping;
# applying a second model-specific remap would scramble already-normalized input.
# USB identities: Linux xpad table and SDL_gamepad_db.h (see CONTROLLERS.md).
static func describe(name:String,info:Dictionary={},guid="",mapped=true)->Dictionary:
 var raw=str(info.get("raw_name",""));var text=(name+" "+raw).to_lower()
 var vendor=int(info.get("vendor_id",0));var product=int(info.get("product_id",0))
 var logitech=vendor==0x046d
 var family=name if not name.is_empty() else "Gamepad"
 if logitech and product==0xc21d:family="Logitech F310"
 elif logitech and product==0xc21f:family="Logitech F710"
 elif "f310" in text:family="Logitech F310"
 elif "f710" in text:family="Logitech F710"
 elif logitech and product==0xc216:family="Logitech F310 / Dual Action"
 elif logitech and product==0xc219:family="Logitech F710 / Cordless RumblePad 2"
 var mode="SDL gamepad"
 if info.has("xinput_index") or (logitech and product in [0xc21d,0xc21f]) or "xinput" in text:mode="XInput"
 elif (logitech and product in [0xc216,0xc219]) or "dinput" in text or "directinput" in text:mode="DirectInput"
 var hint=""
 if family in ["Logitech F310","Logitech F710"]:
  hint="Use the underside X setting for analog LT/RT. MODE light off keeps the left stick and D-pad in their normal roles."
 elif family.begins_with("Logitech F"):
  hint="Shared Logitech USB identity. If this is an F310/F710, select X for analog LT/RT; older Dual Action/RumblePad models may have no X switch."
 if not mapped:hint="SDL mapping is unavailable. For F310/F710, select X and reconnect. F2 shows device details."
 return {"family":family,"display_name":family,"name":name,"raw_name":raw,"vendor_id":vendor,"product_id":product,"guid":guid,"mapped":mapped,"input_mode":mode,"setup_hint":hint}

static func for_device(device:int)->Dictionary:
 if device<0:
  var keyboard=describe("Keyboard");keyboard.input_mode="Keyboard";keyboard.mapped=false;return keyboard
 if not device in Input.get_connected_joypads():return describe("Gamepad %d"%device,{},"",false)
 return describe(Input.get_joy_name(device),Input.get_joy_info(device),Input.get_joy_guid(device),Input.is_joy_known(device))

static func diagnostics(profile:Dictionary)->String:
 return "%s · %s\nSDL mapped: %s · USB %04x:%04x\nGUID: %s\n%s"%[profile.get("display_name","Gamepad"),profile.get("input_mode","SDL gamepad"),str(profile.get("mapped",false)),int(profile.get("vendor_id",0)),int(profile.get("product_id",0)),profile.get("guid",""),profile.get("setup_hint","")]
