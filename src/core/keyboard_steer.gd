extends RefCounted
## Keyboard / D-pad fallback steering, behind the same `PSSteerInput` interface.
##
## The Web prototype maps single arrow keys to four absolute angles and keeps the
## last one alive for 4 seconds (js/main.js `KEY_DIR` / `keyState`):
##
##     ArrowRight -> 0        ArrowDown  -> +PI/2
##     ArrowLeft  -> PI       ArrowUp    -> -PI/2
##
## The port additionally accepts **8 directions**: holding two adjacent
## directions produces the exact diagonal (`PI/4` etc.). This is a superset of the
## JS behaviour requested by the port spec — with a single key held the output is
## bit-identical to the prototype. Opposite keys cancel and are ignored.
##
##     var kb := PSKeyboardSteer.new()
##     kb.set_dirs(PSKeyboardSteer.RIGHT | PSKeyboardSteer.DOWN, now)   # 45 deg
##     kb.update(now, steer)     # false when the 4 s window expired
##
## There is no dead zone and no speed smoothing: a key press is already discrete,
## and `speed_scale` stays 1.0 exactly like the JS keyboard path.

const SteerInput = preload("res://src/core/steer_input.gd")

const RIGHT := 1
const DOWN := 2
const LEFT := 4
const UP := 8
const ALL := RIGHT | DOWN | LEFT | UP

## How long the last pressed direction keeps steering (JS: 4000 ms).
var hold_sec: float = 4.0

var angle: float = 0.0
var has_angle: bool = false
var pressed_at: float = -1.0e9


## Resolve a direction bitmask to an absolute angle.
## Returns NAN when the mask holds no direction or cancels itself out.
static func angle_for_mask(mask: int) -> float:
	var dx := 0
	var dy := 0
	if (mask & RIGHT) != 0:
		dx += 1
	if (mask & LEFT) != 0:
		dx -= 1
	if (mask & DOWN) != 0:
		dy += 1
	if (mask & UP) != 0:
		dy -= 1
	if dx == 0 and dy == 0:
		return NAN
	return atan2(float(dy), float(dx))


## Register the currently held directions at `now_sec`.
## Returns true when this produced a fresh angle.
func set_dirs(mask: int, now_sec: float) -> bool:
	var a := angle_for_mask(mask)
	if is_nan(a):
		return false
	angle = a
	has_angle = true
	pressed_at = now_sec
	return true


## Convenience for a single key press.
func press(p_angle: float, now_sec: float) -> void:
	angle = p_angle
	has_angle = true
	pressed_at = now_sec


## Publish the held direction into `out`. Returns false when nothing is held or
## the 4 second window has expired (the caller then falls back to pose input).
func update(now_sec: float, out: SteerInput) -> bool:
	if not has_angle or (now_sec - pressed_at) >= hold_sec:
		return false
	out.set_keyboard(angle)
	return true


func reset() -> void:
	angle = 0.0
	has_angle = false
	pressed_at = -1.0e9


## Remaining seconds before the direction times out.
func hold_left(now_sec: float) -> float:
	if not has_angle:
		return 0.0
	var left := hold_sec - (now_sec - pressed_at)
	return 0.0 if left < 0.0 else left
