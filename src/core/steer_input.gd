extends RefCounted
## One frame of steering input for a *human* snake.
##
## This is the whole contract between the SDK bridge (workstream A), the
## presentation (C) and the rules (B). The bridge owns the body-tracking maths;
## the rules only need the three numbers below.
##
##     fields
##     ------
##     steer_angle_rad : absolute target heading, radians, 0 = +X (right),
##                       +PI/2 = +Y (down). Same convention as `PSSnake.heading`
##                       and as the JS canvas, so it is a *heading*, not a delta.
##     valid           : the tracker produced a usable angle this frame
##                       (JS `signal.seen`, plus the pose wrist dead zone).
##     confidence      : 0..1 quality of `steer_angle_rad`. 1 = fresh angle that
##                       passed the wrist dead zone, ~0 = stale angle being held
##                       through a dropout. The rules intentionally do NOT gate on
##                       it (JS gates on `seen || hold`); it is published so the
##                       HUD / bridge can react, and so a future "weak signal"
##                       rule can be added without touching the wire format.
##     speed_scale     : wrist-distance speed multiplier, 0.40..1.80
##                       (JS `signal.speedScale`). Only meaningful for pose input;
##                       keyboard/touch keep 1.0, which is exactly the JS behaviour.
##     hold            : we are inside `pose.lost_timeout_ms` of the last good
##                       frame, so the last angle is still trustworthy (JS `hold`).
##     keyboard        : true when the angle came from the keyboard/touch fallback
##                       (presentation hint only, the rules behave identically).
##
## Usage from the bridge:
##
##     steer.steer_angle_rad = wrist_angle
##     steer.valid = true
##     steer.confidence = 1.0
##     steer.speed_scale = 1.25
##     game.update(dt, steer, real_dt)
##
## Usage from a test / replay: build one, mutate the fields, pass it in. The same
## object may be reused for every frame (nothing retains it).

## Absolute target heading in radians (canvas convention: 0 = right, +PI/2 = down).
var steer_angle_rad: float = 0.0
## True when a fresh, trustworthy angle is available this frame.
var valid: bool = false
## 0..1 quality of `steer_angle_rad`.
var confidence: float = 0.0
## Wrist-distance speed multiplier (0.40 .. 1.80).
var speed_scale: float = 1.0
## True while steering on a recently-held angle after a short tracking dropout.
var hold: bool = false
## True when the angle came from the keyboard/touch fallback.
var keyboard: bool = false


## JS rule: a control is applied when `signal.seen || signal.hold`.
func is_usable() -> bool:
	return valid or hold


## Reset to "no input at all" (the snake then keeps its heading and speed).
func clear() -> void:
	steer_angle_rad = 0.0
	valid = false
	confidence = 0.0
	speed_scale = 1.0
	hold = false
	keyboard = false


## Write a pose-derived angle (dead zone already applied by `PSPoseSteer`).
func set_pose(angle: float, p_speed_scale: float, p_confidence: float = 1.0) -> void:
	steer_angle_rad = angle
	valid = true
	hold = false
	keyboard = false
	confidence = clampf(p_confidence, 0.0, 1.0)
	speed_scale = p_speed_scale


## Write a keyboard/touch angle (no dead zone, fixed 1.0 speed multiplier).
func set_keyboard(angle: float) -> void:
	steer_angle_rad = angle
	valid = true
	hold = false
	keyboard = true
	confidence = 1.0
	speed_scale = 1.0


## Copy another input struct (used by tests and two-player signal duplication).
func copy_from(other) -> void:
	steer_angle_rad = other.steer_angle_rad
	valid = other.valid
	confidence = other.confidence
	speed_scale = other.speed_scale
	hold = other.hold
	keyboard = other.keyboard


func _to_string() -> String:
	return "SteerInput(angle=%.3f valid=%s conf=%.2f speed=%.2f hold=%s)" % [
		steer_angle_rad, valid, confidence, speed_scale, hold,
	]
