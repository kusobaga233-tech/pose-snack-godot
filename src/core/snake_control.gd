extends RefCounted
## Per-frame steering command handed to `PSSnake.update()`.
##
## JS `Snake.update(dt, control, tuning)` takes a throw-away object:
## `{angle, speedScale, turnEase, wobble}`. Allocating one per snake per frame is
## the one per-frame allocation the JS hot path has, and the port must not repeat
## it on the Amlogic box: every `PSBrain` (and `PSGame` for the humans) owns a
## small set of these buffers and rewrites their fields instead.
##
## `angle` and `speed_scale` use NaN as "not supplied", exactly like the JS
## `Number.isFinite(control.angle)` / `Number.isFinite(control.speedScale)` checks:
##   * AI control     -> speed_scale = NAN (AI speed never depends on a wrist)
##   * "no signal"    -> angle = NAN (keep current heading, keep last speed)

## Target heading in radians; NAN = do not steer this frame.
var angle: float = NAN
## Input speed multiplier; NAN = keep the snake's previous `pose_speed`.
var speed_scale: float = NAN
## Steering-rate multiplier (AI skill / reaction personality); 1 = human.
var turn_ease: float = 1.0
## Sine wobble added to `angle` inside the snake (AI serpentine path).
var wobble: float = 0.0


## Clear to a neutral, non-steering command.
func reset() -> void:
	angle = NAN
	speed_scale = NAN
	turn_ease = 1.0
	wobble = 0.0


## Fill for an AI snapshot (speed_scale must stay NAN: AI is never pose-scaled).
func set_ai(p_angle: float, p_turn_ease: float, p_wobble: float) -> void:
	angle = p_angle
	speed_scale = NAN
	turn_ease = p_turn_ease
	wobble = p_wobble


## Fill from a human steering input (JS `{angle, speedScale}`).
func set_player(p_angle: float, p_speed_scale: float) -> void:
	angle = p_angle
	speed_scale = p_speed_scale
	turn_ease = 1.0
	wobble = 0.0


## Copy every field from another control buffer.
func copy_from(other) -> void:
	angle = other.angle
	speed_scale = other.speed_scale
	turn_ease = other.turn_ease
	wobble = other.wobble


func _to_string() -> String:
	return "SnakeControl(angle=%s speed=%s ease=%.3f wobble=%.3f)" % [
		str(angle), str(speed_scale), turn_ease, wobble,
	]
