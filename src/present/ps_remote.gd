extends RefCounted
## Workstream C — remote-control (RCU) key map. The RCU is the only menu input.
##
## This file is deliberately pure mapping (no scene state): `main.gd` feeds every
## `InputEventKey` through `action_for()` and has a single `_dispatch_action()`
## that owns menu behaviour, so a key can never be activated twice by both a
## Godot `ui_*` action and a raw keycode. The raw-Android and joypad helpers are
## used only when the native hook is missing (see the note below).
##
## Android -> Godot key mapping in Godot 4.6
## (`platform/android/android_keys_utils.h`, `android_input_handler.cpp`):
##
##   KEYCODE_DPAD_UP     (19)  -> KEY_UP        (4194320)
##   KEYCODE_DPAD_DOWN   (20)  -> KEY_DOWN      (4194322)
##   KEYCODE_DPAD_LEFT   (21)  -> KEY_LEFT      (4194319)
##   KEYCODE_DPAD_RIGHT  (22)  -> KEY_RIGHT     (4194321)
##   KEYCODE_DPAD_CENTER (23)  -> KEY_ENTER     (4194309)
##   KEYCODE_ENTER       (66)  -> KEY_ENTER     (4194309)
##   KEYCODE_NUMPAD_ENTER(160) -> KEY_KP_ENTER  (4194310)
##   KEYCODE_SPACE       (62)  -> KEY_SPACE     (32)       (some boxes send OK as space)
##   KEYCODE_BACK        (4)   -> KEY_BACK      (4194376)  (also fires go_back_requested)
##   KEYCODE_ESCAPE      (111) -> KEY_ESCAPE    (4194305)
##
## `InputEventKey.keycode` is the localised code and `physical_keycode` the
## hardware code; `action_for()` is applied to both because some Android boxes
## report only one of them. `unicode` is not used for menu actions.
##
## The physical RCU on the Youdoo box is enumerated as a gamepad: before the
## native hook (android/build-overrides/.../GodotApp.java) Godot routed its key
## events into the joypad path instead of this key path. The hook now consumes
## every remote key and re-injects it as a pure keyboard event, so `action_for()`
## is the normal path. The raw-Android and joypad tables below are fallbacks for
## a build without the hook: the RCU sends KEYCODE_DPAD_* 19..22 and reports OK
## as KEYCODE_BUTTON_A (96), which Godot has no keyboard mapping for.
##
## No on-screen text may name a keyboard: the hints draw "OK / 返回键" only.

const ACT_NONE := 0
const ACT_UP := 1
const ACT_DOWN := 2
const ACT_LEFT := 3
const ACT_RIGHT := 4
const ACT_OK := 5
const ACT_BACK := 6

## Raw Android keycodes exactly as the native hook logs them under
## `GodotRemoteInput: key=<code>`. The hook normally translates these to Godot
## keycodes before Godot sees them; this table is the fallback path.
##   19..22 DPAD_UP/DOWN/LEFT/RIGHT
##   23 DPAD_CENTER, 66 ENTER, 96 BUTTON_A, 160 NUMPAD_ENTER,
##   85 MEDIA_PLAY_PAUSE, 62 SPACE -> OK
##   4 BACK, 111 ESCAPE
## 96 is listed because that is what this platform delivers for OK.
const ANDROID_ACTION := {
	19: ACT_UP,
	20: ACT_DOWN,
	21: ACT_LEFT,
	22: ACT_RIGHT,
	23: ACT_OK,
	66: ACT_OK,
	96: ACT_OK,
	160: ACT_OK,
	85: ACT_OK,
	62: ACT_OK,
	4: ACT_BACK,
	111: ACT_BACK,
}

## Godot JoyButton indices for the same fallback: before the native hook the
## remote's DPAD keys arrived as JOY_BUTTON_DPAD_* 11..14 and OK as gamepad A (0).
const JOY_ACTION := {
	0: ACT_OK,   # JOY_BUTTON_A
	1: ACT_BACK, # JOY_BUTTON_B
	11: ACT_UP,  # JOY_BUTTON_DPAD_UP
	12: ACT_DOWN,
	13: ACT_LEFT,
	14: ACT_RIGHT,
}


## Godot keycode -> semantic action. Accepts both DPAD_CENTER and ENTER (plus
## KP_ENTER/SPACE) for OK, and both Android BACK and desktop ESC for back.
static func action_for(code: int) -> int:
	match code:
		KEY_UP:
			return ACT_UP
		KEY_DOWN:
			return ACT_DOWN
		KEY_LEFT:
			return ACT_LEFT
		KEY_RIGHT:
			return ACT_RIGHT
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			return ACT_OK
		KEY_BACK, KEY_ESCAPE:
			return ACT_BACK
		_:
			return ACT_NONE


## ---------------------------------------------------------------------------
## Internal debug tuning panel (see `ps_tuning_panel.gd`; only reachable at all
## from a build with `PSBuild.TUNING_ENABLED == true`).
##
## Which key opens it, and why these:
##   * `KEY_F8` is the documented one. `adb shell input keyevent 138` reaches it
##     and the native hook (`android/build-overrides/.../GodotApp.java:139-143`)
##     deliberately lets F-keys through to Godot untouched.
##   * `KEY_MENU` is included for a build WITHOUT the hook: with the hook present
##     the box's MENU (82) is canonicalised to KEYCODE_F6 for the camera-variant
##     cycle, so it can never arrive here (main.gd:1917-1938 owns F6).
##   * `KEY_SEARCH` / `KEY_HELP` are the other two remote-ish keys that Godot maps
##     and the hook does not touch.
## NOT usable, despite being the obvious candidates:
##   * `KEYCODE_SETTINGS` (176) — Godot's `platform/android/android_keys_utils.h`
##     has no AKEYCODE_SETTINGS entry at all, so the event arrives with keycode 0
##     and no unicode; the app cannot tell it from a dead key.
##   * `KEYCODE_MENU` (82) — taken by the hook (camera variant, see above).
## Mapping a physical RCU button to `F8` therefore requires one line in the hook
## (`KEYCODE_SETTINGS -> KEYCODE_F8`), which lives in `android/**` (coordinator).
const PANEL_KEYS := [KEY_F8, KEY_MENU, KEY_SEARCH, KEY_HELP]


static func is_panel_key(code: int) -> bool:
	return PANEL_KEYS.has(code)


## Raw Android keycode (19..22, 23/66/96/160/85/62, 4/111) -> action.
## Only used as a last resort when the native hook is absent, because on a
## normal Android build Godot has already translated the code.
static func android_action_for(code: int) -> int:
	return int(ANDROID_ACTION.get(code, ACT_NONE))


## Godot JoyButton index -> action (pre-hook gamepad-style RCU delivery).
static func joy_action_for(button: int) -> int:
	return int(JOY_ACTION.get(button, ACT_NONE))


static func action_name(action: int) -> String:
	match action:
		ACT_UP:
			return "up"
		ACT_DOWN:
			return "down"
		ACT_LEFT:
			return "left"
		ACT_RIGHT:
			return "right"
		ACT_OK:
			return "ok"
		ACT_BACK:
			return "back"
		_:
			return "none"


## One line per received key event. This is the on-device diagnostic format:
## `[key] event=pressed code=4194309 physical=4194309 unicode=0`
## A human presses each physical RCU button once and reads logcat.
static func key_line(event: InputEventKey) -> String:
	return "[key] event=%s code=%d physical=%d unicode=%d" % [
		"pressed" if event.pressed else "released",
		event.keycode, event.physical_keycode, event.unicode]
