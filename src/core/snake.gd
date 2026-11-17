extends RefCounted
## A snake: shared by the human player(s) and the AI (JS `js/snake.js`).
##
## Motion model (faithful port):
##   1. Turning: a *target heading* (wrist angle for humans, `PSBrain` intent for
##      AI) is chased with a **hard capped rotational speed**
##      `turn.rate * turn_ease * turn_mul`, boosted up to `turn.reverse_boost` for
##      U-turns, integrated per frame: `heading += clamp(diff, +-max_turn)`.
##      This is the only thing that limits turning; nobody teleports their heading.
##   2. Speed: `base_speed * speed_mul * (1 - strength * (1 - e^(-extra/scale)))
##      * boost_buff * pose_speed`. Recomputed every frame from the current length,
##      so growing / absorbing / respawning needs no manual bookkeeping.
##   3. Body: a follow chain. Each node is pulled towards its predecessor only when
##      the link is longer than `seg_dist`, which is what makes the body trail
##      smoothly instead of being a rigid rod.
##   4. Rendering wobble is *not* part of the body: collision always uses the raw
##      chain, the sine wobble only exists in `render_points()`.
##
## Determinism notes
## -----------------
## * `body` / `pulse` are Packed arrays owned by this object; `reset()` reuses
##   their capacity instead of reallocating.
## * Every timing value (`freeze_until`, `immune_until`) is measured on the
##   *simulation clock* (`now`, written by `PSGame` each frame). The JS version
##   used `performance.now()`, which is why its respawn freeze could be stretched
##   by dt clamping; the port deliberately uses simulated seconds so a headless
##   test can fast-forward a whole round. See docs/core-model.md, "Deviations".
##
## The presentation layer may read every field in "Read-only contract" order
## documented in docs/core-model.md.

const PSMath = preload("res://src/core/ps_math.gd")
const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSRng = preload("res://src/core/rng.gd")
const SnakeControl = preload("res://src/core/snake_control.gd")

## Buff kinds (index into `buffs`).
const BUFF_BOOST := 0
const BUFF_MAGNET := 1

# --------------------------------------------------------------- identity

## Stable per-round index (0 = player 1, AI ids follow the humans).
var id: int = 0
## True for a human-controlled snake.
var is_player: bool = false
## Human slot (0 = player 1, 1 = player 2); -1 for AI.
var player_index: int = -1
## HUD / result-stage display name (`你` / `玩家 2` / `AI 1`).
var display_name: String = ""
## Body colour (AI palette or player colour).
var color: Color = Color.WHITE
## Head tint; `has_head_color == false` means "derive from `color`" (AI).
var head_color: Color = Color.WHITE
var has_head_color: bool = false
## Player four-stop body gradient (JS `grad`); empty for AI.
var grad: Array = []
## Cosmetics assigned per round (see `PSGame.assign_styles`).
var style = null
var style_label: String = ""
## NPC head style key (`&""` = classic head, always the case for humans).
var head_style: StringName = &""

# --------------------------------------------------------------- motion

## One vector per node; `body[0]` is the head. World pixels.
var body: PackedVector2Array = PackedVector2Array()
## Brightness pulse per node, 0..1.5; decays head -> tail (cosmetic).
var pulse: PackedFloat32Array = PackedFloat32Array()
## Fractional growth accumulator (AI leader bonus / AI food multiplier).
var growth_carry: float = 0.0
## Current heading in radians (canvas convention: 0 = +X, +PI/2 = +Y/down).
var heading: float = 0.0
## Current speed in world pixels per second (recomputed every frame).
var speed: float = 300.0
## Per-individual turning ability multiplier (AI skill; 1.0 for humans).
var turn_mul: float = 1.0
## Per-individual speed multiplier (AI speed jitter; 1.0 for humans).
var speed_mul: float = 1.0
## True while alive; a dead snake keeps `respawn_timer` counting down.
var alive: bool = false
## Seconds until respawn (counts down with real dt only while dead).
var respawn_timer: float = 0.0

# --------------------------------------------------------------- state

## Absolute simulation time (seconds) until which this snake cannot be killed.
var immune_until: float = 0.0
## Absolute simulation time until which this snake cannot move (respawn freeze).
var freeze_until: float = 0.0
## Simulation clock snapshot, written by `PSGame` once per frame.
## All `is_*()` predicates read this instead of a wall clock.
var now: float = 0.0
## Remaining buff seconds: [boost, magnet]. Packed so a frame touches no Dictionary.
var buffs: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Human wrist-distance speed multiplier (AI stays 1.0).
var pose_speed: float = 1.0
## Absolute angle turned this frame (drives the cosmetic body wobble).
var turn_amount: float = 0.0
## AI is currently "spacing out" (presentation draws a "?" over the head).
var mistake: bool = false
## Cosmetic body-wave phase (seconds).
var wave_phase: float = 0.0
## Where the eyes look (nearest food), if `has_look_at`.
var look_at: Vector2 = Vector2.ZERO
var has_look_at: bool = false

# --------------------------------------------------------------- stats

## Kills credited this round (`PSGame.reward_kill`).
var kills: int = 0
## Pellets eaten this round.
var food_eaten: int = 0
## Longest length reached this round (survives death; used by ranking ties).
var peak_length: int = 0
## Deaths this round.
var deaths: int = 0

# --------------------------------------------------------------- injected

var cfg: PSConfig = null
var tuning: PSRuntimeTuning = null
## Shared world RNG, used only for the cosmetic initial wave phase (JS used
## `Math.random()` here too, so the draw order is part of the world stream).
var rng: PSRng = null

# Cached radius (pure function of length + girth slider).
var _radius_len: int = -1
var _radius_girth: float = -1.0
var _radius_value: float = 22.0


func _init(p_cfg: PSConfig = null, p_tuning: PSRuntimeTuning = null,
		p_rng: PSRng = null) -> void:
	cfg = p_cfg
	tuning = p_tuning
	rng = p_rng


# ---------------------------------------------------------------- helpers

## Number of body nodes; the game's definition of "length" for the ranking.
func length() -> int:
	return body.size()


## Visual + collision radius of this snake right now (cached per length/girth).
func radius() -> float:
	var n := body.size()
	var g: float = tuning.girth_max if tuning != null else cfg.snake.girth.default
	if n != _radius_len or g != _radius_girth:
		_radius_len = n
		_radius_girth = g
		_radius_value = cfg.snake_radius(float(n), g)
	return _radius_value


## True during the respawn / round-start freeze (no movement, heading input only).
func is_frozen() -> bool:
	return now < freeze_until


## Same predicate at an explicit time (tests / replay without a game clock).
func is_frozen_at(t: float) -> bool:
	return t < freeze_until


## Frozen snakes are always immune, then `immune_until` extends it further.
func is_immune() -> bool:
	return is_frozen() or now < immune_until


func is_immune_at(t: float) -> bool:
	return is_frozen_at(t) or t < immune_until


## Remaining seconds of `type` (0 = not active). JS `buffLeft()`.
func buff_left(type: int) -> float:
	var v := buffs[type]
	return 0.0 if v < 0.0 else v


func has_buff(type: int) -> bool:
	return buffs[type] > 0.0


## Refresh a buff to at least `sec` (same kind does not stack multiplicatively).
func apply_buff(type: int, sec: float) -> void:
	if not is_finite(sec):
		return
	if sec > buffs[type]:
		buffs[type] = sec


## Count buff timers down with *real* dt (pausing the game freezes them).
func tick_buffs(real_dt: float) -> void:
	if not (real_dt > 0.0):
		return
	if buffs[0] > 0.0:
		buffs[0] = maxf(0.0, buffs[0] - real_dt)
	if buffs[1] > 0.0:
		buffs[1] = maxf(0.0, buffs[1] - real_dt)


func clear_buffs() -> void:
	buffs[0] = 0.0
	buffs[1] = 0.0


## Speed multiplier granted by the boost pickup (1.0 when inactive).
func boost_multiplier() -> float:
	return cfg.powerups.boost.speed_mul if buffs[0] > 0.0 else 1.0


# ---------------------------------------------------------------- lifecycle

## Respawn / round start at `(x, y)` facing `p_heading` with `segments` nodes.
## Body is laid out *behind* the head, exactly like the JS version, so the head
## starts at the requested point and the tail trails towards -heading.
func reset(x: float, y: float, p_heading: float, segments: int) -> void:
	var n := maxi(1, segments)
	body.resize(n)
	pulse.resize(n)
	growth_carry = 0.0
	var dx := cos(p_heading)
	var dy := sin(p_heading)
	var step := cfg.snake.seg_dist
	var i := 0
	while i < n:
		body[i] = Vector2(x - dx * float(i) * step, y - dy * float(i) * step)
		pulse[i] = 0.0
		i += 1
	heading = p_heading
	clear_buffs()
	speed = cfg.snake.base_speed * speed_mul
	alive = true
	respawn_timer = 0.0
	freeze_until = 0.0
	pose_speed = 1.0
	turn_amount = 0.0
	wave_phase = rng.randf() * 10.0 if rng != null else 0.0
	_radius_len = -1
	if peak_length < n:
		peak_length = n


# ---------------------------------------------------------------- movement

## Recompute speed from the current length (JS `updateSpeed`).
##   speed = base * speed_mul * (1 - strength * (1 - e^(-extra/scale)))
##           * boost * pose_speed
func update_speed() -> void:
	var S = cfg.slowdown
	var extra := maxf(0.0, float(body.size() - cfg.snake.start_segments))
	var strength := clampf(tuning.slow_strength, 0.0, 0.95)
	var scale := maxf(1.0, tuning.slow_scale)
	var k := 1.0 - exp(-extra / scale)
	var boost := boost_multiplier()
	var SP = cfg.pose.speed
	var dist := clampf(pose_speed, SP.min_limit, SP.max_limit)
	speed = cfg.snake.base_speed * speed_mul * (1.0 - strength * k) * boost * dist


## Advance one frame. `control` is a `PSSnakeControl` (or null = coast).
## `now` is optional: pass it from tests, `PSGame` writes `snake.now` instead.
func update(dt: float, control: SnakeControl, p_now: float = NAN) -> void:
	if is_finite(p_now):
		now = p_now
	if not alive:
		return

	# Wrist-distance speed only comes from human control; AI does not provide it,
	# and a missing signal keeps the previous multiplier (JS behaviour).
	if control != null and is_finite(control.speed_scale):
		pose_speed = control.speed_scale

	# Refresh speed first: growth / absorbs / respawn take effect immediately.
	update_speed()

	# ---- respawn / round-start freeze: position never moves, heading tracks input
	if is_frozen():
		if control != null and is_finite(control.angle):
			heading = PSMath.norm_angle(control.angle)
		turn_amount = 0.0
		return

	turn_amount = 0.0

	if control != null and is_finite(control.angle):
		# ---- 1. target heading + AI serpentine wobble (0 for humans) ----
		var target_angle: float = control.angle + control.wobble
		var diff := PSMath.norm_angle(target_angle - heading)
		# ---- 2. chase it with a capped rotational speed ----
		var rate: float = tuning.turn_rate * control.turn_ease * turn_mul
		var boost := 1.0 + (absf(diff) / PI) * (cfg.turn.reverse_boost - 1.0)
		var max_turn := rate * boost * dt
		var turned := clampf(diff, -max_turn, max_turn)
		heading = PSMath.norm_angle(heading + turned)
		turn_amount = absf(turned)

	# ---- 3. move the head ----
	var head := body[0]
	head.x += cos(heading) * speed * dt
	head.y += sin(heading) * speed * dt
	body[0] = head

	# ---- 4. body follow chain: only pull in when stretched past seg_dist ----
	var seg_dist: float = cfg.snake.seg_dist
	var n := body.size()
	var i := 1
	while i < n:
		var prev := body[i - 1]
		var cur := body[i]
		var dx := cur.x - prev.x
		var dy := cur.y - prev.y
		var d := sqrt(dx * dx + dy * dy)
		if d < 1e-6:
			dx = 1.0
			dy = 0.0
			d = 1.0
		if d > seg_dist:
			var k := seg_dist / d
			body[i] = Vector2(prev.x + dx * k, prev.y + dy * k)
		i += 1

	# ---- 5. cosmetic wave phase + pulse decay ----
	wave_phase += (2.0 + minf(3.0, turn_amount * 12.0)) * dt
	decay_pulse(dt)


## Brightness pulse: exponential decay, then a head -> tail smear.
func decay_pulse(dt: float) -> void:
	var k := exp(-4.5 * dt)
	var n := pulse.size()
	var i := 0
	while i < n:
		pulse[i] *= k
		i += 1
	i = n - 1
	while i > 0:
		if pulse[i - 1] > pulse[i]:
			pulse[i] = pulse[i - 1] * 0.92
		i -= 1


# ---------------------------------------------------------------- growth

## Append `n` nodes at the tail, continuing the tail direction (JS `grow`).
func grow(n: int) -> void:
	if n <= 0:
		return
	var step: float = cfg.snake.seg_dist
	var i := 0
	while i < n:
		var last := body.size() - 1
		var tail := body[last]
		var prev := body[last - 1] if last >= 1 else tail
		var dx := tail.x - prev.x
		var dy := tail.y - prev.y
		var d := sqrt(dx * dx + dy * dy)
		if d == 0.0:
			d = 1.0
		body.push_back(Vector2(tail.x + (dx / d) * step, tail.y + (dy / d) * step))
		pulse.push_back(0.0)
		i += 1
	_radius_len = -1
	if body.size() > peak_length:
		peak_length = body.size()


## Fractional growth: bank the remainder until a whole node is owed
## (used by the AI food multiplier and the AI leader bonus).
func grow_fractional(amount: float) -> void:
	if not (amount > 0.0):
		return
	growth_carry += amount
	var whole := int(floor(growth_carry))
	if whole > 0:
		growth_carry -= float(whole)
		grow(whole)


# ---------------------------------------------------------------- collision

## Head outside the padded world rectangle (JS `hitWall`).
func hit_wall() -> bool:
	var p: float = cfg.snake.wall_pad
	var h := body[0]
	var w: float = cfg.world.w
	var hh: float = cfg.world.h
	return h.x < p or h.x > w - p or h.y < p or h.y > hh - p


## Pull the head back inside the world (called on wall death, before the corpse
## scatters, so pellets never spawn outside the playfield).
func clamp_to_world() -> void:
	var p: float = cfg.snake.wall_pad
	var h := body[0]
	h.x = clampf(h.x, p, cfg.world.w - p)
	h.y = clampf(h.y, p, cfg.world.h - p)
	body[0] = h


## Head touching its own body, skipping the neck (`skip` nodes).
## Humans use the defaults (9 / 0.62); AI passes `ai.self_hit` (12 / 0.45).
func hit_self(skip: int = 9, radius_mul: float = 0.62) -> bool:
	var h := body[0]
	var rr := radius() * radius_mul
	var r2 := rr * rr
	var n := body.size()
	var i := skip
	while i < n:
		var p := body[i]
		var dx := h.x - p.x
		var dy := h.y - p.y
		if dx * dx + dy * dy < r2:
			return true
		i += 1
	return false


# ---------------------------------------------------------------- presentation

## Presentation-only polyline: body chain + sine wobble that grows when turning.
## Collision never uses this, so "looks like it missed" can never kill you.
func render_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	render_points_into(out)
	return out


## Allocation-friendly variant writing into a caller-owned array.
func render_points_into(out: PackedVector2Array) -> void:
	var n := body.size()
	out.resize(n)
	if n == 0:
		return
	var amp := 0.8 + minf(4.5, turn_amount * 18.0)
	var inv_len := 0.0
	if n > 1:
		inv_len = 1.0 / float(n - 1)
	var i := 0
	while i < n:
		var p := body[i]
		if i == 0 or n < 3:
			out[i] = p
			i += 1
			continue
		var t := float(i) * inv_len
		var a := body[i - 1]
		var next_index := i + 1
		if next_index > n - 1:
			next_index = n - 1
		var b := body[next_index]
		var tx := b.x - a.x
		var ty := b.y - a.y
		var tl := sqrt(tx * tx + ty * ty)
		if tl == 0.0:
			tl = 1.0
		tx /= tl
		ty /= tl
		var envelope := sin(t * PI)
		var offset := amp * envelope * sin(wave_phase - float(i) * 0.55)
		out[i] = Vector2(p.x - ty * offset, p.y + tx * offset)
		i += 1


## Evenly strided body samples for the death scatter (JS `scatterPositions`).
## Returns the stride; call sites loop `i += stride` over `body` so no copy is made.
func scatter_step(max_points: int) -> int:
	var n := body.size()
	if n == 0 or max_points <= 0:
		return 1
	return maxi(1, int(ceil(float(n) / float(max_points))))


## Copy of the scatter positions (convenience for tests / tooling).
func scatter_positions(max_points: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := body.size()
	if n == 0:
		return out
	var step := scatter_step(max_points)
	var i := 0
	while i < n:
		out.push_back(body[i])
		i += step
	return out


func _to_string() -> String:
	return "Snake#%d(%s len=%d alive=%s spd=%.1f)" % [
		id, display_name, body.size(), alive, speed,
	]
