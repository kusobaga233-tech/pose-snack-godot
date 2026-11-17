extends RefCounted
## Math helpers shared by the pure-GDScript rule core.
##
## Mirrors `js/utils.js`. Only the helpers the rules need are ported: colour
## string parsing / localStorage wrappers stay in the presentation and bridge
## workstreams. Angles follow the canvas convention used by the whole game:
## `0` = +X (right), `+PI/2` = +Y (down), normalised to `[-PI, PI]`.

const TAU_F := 6.283185307179586476925286766559


## Normalise an angle to `[-PI, PI]` (JS `normAngle`).
static func norm_angle(a: float) -> float:
	if a >= -PI and a <= PI:
		return a
	var t := fmod(a + PI, TAU_F)
	if t < 0.0:
		t += TAU_F
	return t - PI


## Squared distance (JS `dist2`); avoids the square root in compare-only paths.
static func dist2(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := ax - bx
	var dy := ay - by
	return dx * dx + dy * dy


## Clamp into [0, 1] (JS `clamp01`).
static func clamp01(v: float) -> float:
	if v < 0.0:
		return 0.0
	if v > 1.0:
		return 1.0
	return v


## Ease-out cubic (JS `easeOutCubic`), used by presentation tweens.
static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


## Frame-rate independent exponential smoothing coefficient (JS `smoothK`).
static func smooth_k(k: float, dt: float) -> float:
	return 1.0 - exp(-k * dt)


## Exponential decay that snaps to exactly 0 below 1e-4 (JS `decay`).
static func decay(value: float, k: float, dt: float) -> float:
	var v := value * exp(-k * dt)
	if absf(v) < 1e-4:
		return 0.0
	return v


## True when every component is finite (guards the AI from NaN poisoning).
static func vec_is_finite(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)
