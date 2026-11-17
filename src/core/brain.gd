extends RefCounted
## AI opponent brain (JS `js/ai.js`), seven instances per round.
##
## Per frame the brain:
##   1. picks a target food (difficulty may pick a worse one, and lock it longer)
##   2. probes forward for walls / other bodies / oncoming heads -> avoidance vector
##   3. blends target direction + avoidance (+ attack) into a desired heading
##   4. if clearly longer than a nearby opponent and pressure is high, attacks:
##      leads the target's motion and cuts across its nose
##   5. adds a slow sine wobble so the path is serpentine, not a straight line
##
## Difficulty does not just slow the AI down; it weakens five dimensions at once
## (turn rate, reaction interval, senses/avoidance, aggression, aiming) and adds
## random "spacing out" lapses where the brain does not avoid anything at all.
##
## `pressure` (2026-11-09) adds hunt/survival abilities above difficulty 0.5:
##   pressure = clamp((level-0.5)/0.5) * ai_pressure   -> exactly 0 at level<=0.5,
## so low difficulty reproduces the legacy behaviour bit for bit.
##
## The brain only ever outputs *intent* (`PSSnakeControl`); the rotational speed
## cap lives in `PSSnake.update()`, so AI and humans share the same physics.
##
## Buffer strategy (port-specific, no behaviour change): one brain owns three
## control buffers (`_ctrl`, `_ctrl_alt`, `_lapse_ctrl`) that are overwritten in
## place, so a 60 Hz frame allocates nothing. `_ctrl` doubles as `last_control`;
## it is only ever overwritten *after* the reaction-interval branch has returned,
## so "reuse the previous decision" keeps working exactly like the JS object copy.

const PSMath = preload("res://src/core/ps_math.gd")
const SnakeControl = preload("res://src/core/snake_control.gd")
const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSRng = preload("res://src/core/rng.gd")
const PSSnake = preload("res://src/core/snake.gd")
const PSFood = preload("res://src/core/food.gd")

## Turn-rate multiplier numerically equivalent to the old elbow chain
## (extend 0.62 -> lerp(0.72, 1.32, 0.62)).
const AI_TURN_EASE := 0.72 + (1.32 - 0.72) * 0.62
## Wobble gain (halved again on 2026-11-11: constant 0.30 read as head jitter).
const AI_WOBBLE_GAIN := 0.15

var snake: PSSnake = null
var cfg: PSConfig = null
var rng: PSRng = null

## Individual turning skill, rolled once per round.
var skill: float = 0.9

# ---- decision state -------------------------------------------------------
## Currently locked food (`PSFood`) or null.
var target: PSFood = null
## Game time (seconds) when the target may be re-picked.
var retarget_at: float = 0.0
## Wander heading used while no food is in range.
var wander_angle: float = 0.0
## Serpentine wobble phase / amplitude.
var wobble_phase: float = 0.0
var wobble_amp: float = 0.5
## Previous decision (JS `lastControl`); `has_last_control` is the null check.
var last_control = null
var has_last_control: bool = false
## Game time (seconds) when a new decision is allowed again.
var next_decision_at: float = 0.0
## Low-frequency aim jitter (radians) and the time of its next re-roll.
var aim_bias: float = 0.0
var aim_bias_target: float = 0.0
var bias_at: float = 0.0
## Lapse ("spacing out") window: while `now < lapse_until` the brain returns
## `lapse_control` and skips probing / foraging entirely.
var lapse_until: float = 0.0
var lapse_control = null
var next_lapse_at: float = 0.0

# ---- cumulative counters (debug / calibration, never reset per round) -----
var lapses: int = 0
var mistake_frames: int = 0
var escape_hits: int = 0
var escape_stuck: int = 0
var loop_triggers: int = 0

# ---- anti-loop / intent smoothing ----------------------------------------
var smooth_angle: float = 0.0
var has_smooth_angle: bool = false
var loop_turn: float = 0.0
var loop_path: float = 0.0
var loop_signed: float = 0.0
var has_loop_ref: bool = false
var loop_ref_x: float = 0.0
var loop_ref_y: float = 0.0
var loop_check_at: float = 0.0
var has_prev_heading: bool = false
var prev_heading: float = 0.0
var escape_until: float = 0.0
var escape_dir: int = 1
var escape_side: int = 1
## Food that was just declared unreachable; blacklisted until `avoid_food_until`.
var avoid_food: PSFood = null
var avoid_food_until: float = 0.0

## Per-round personality (`PSConfig.StyleCfg`) or null = neutral.
var style = null

# ---- reusable buffers -----------------------------------------------------
var _ctrl = SnakeControl.new()
var _ctrl_alt = SnakeControl.new()
var _lapse_ctrl = SnakeControl.new()
var near_food: Array = [null, null, null, null, null, null]
var near_score: PackedFloat64Array = PackedFloat64Array()
var near_count: int = 0


func _init(p_snake: PSSnake, p_cfg: PSConfig, p_rng: PSRng) -> void:
	snake = p_snake
	cfg = p_cfg
	rng = p_rng
	near_score.resize(6)
	var A := cfg.ai
	skill = rng.rand_range(A.skill_min, A.skill_max)
	# Difficulty also scales the turn ability; recomputed every think() so a
	# slider move takes effect on the next frame without rebuilding anything.
	snake.turn_mul = skill * turn_factor(A.difficulty.level)
	wander_angle = rng.rand_range(0.0, TAU)
	wobble_phase = rng.rand_range(0.0, TAU)
	wobble_amp = rng.rand_range(0.35, 0.75)


# ---------------------------------------------------------------- style

## Assign this round's personality; also publishes it to the snake for the HUD.
func set_style(p_style):
	style = p_style
	snake.style = style
	snake.style_label = "" if style == null else style.label
	return style


## Difficulty -> turn ability multiplier (level 1 == legacy, 1.0x).
func turn_factor(level: float) -> float:
	var D := cfg.ai.difficulty
	var lv := clampf(level if is_finite(level) else D.level, D.level_min, D.level_max)
	return D.turn_floor + (1.0 - D.turn_floor) * lv


# ---------------------------------------------------------------- self avoidance

## Smallest perpendicular distance from `angle`'s ray to this snake's own body
## within `look_ahead`; INF means "clear". Compared against the danger radius so
## several candidate headings can be ranked instead of "blocked / not blocked".
func self_clearance(s, angle: float) -> float:
	var G := cfg.ai.self_avoid
	var b: PackedVector2Array = s.body
	var n := b.size()
	if n == 0:
		return INF
	var hx := b[0].x
	var hy := b[0].y
	var dx := cos(angle)
	var dy := sin(angle)
	var best := INF
	var k: int = G.skip
	while k < n:
		var vx := b[k].x - hx
		var vy := b[k].y - hy
		var along := vx * dx + vy * dy
		if along >= 0.0 and along <= G.look_ahead:
			var side := absf(vx * dy - vy * dx)
			if side < best:
				best = side
		k += G.step
	return best


## Route-level self avoidance: if the intended heading grazes our own body, pick
## the left/right candidate that is clearer. `guard` 0 disables it entirely.
## Hysteresis (`escape_side`) keeps the AI from twitching between two equal sides.
func self_escape(s, angle: float, guard: float) -> float:
	var G := cfg.ai.self_avoid
	if not G.enabled or guard <= 0.0:
		return angle
	var danger_r := maxf(G.danger_r_min, s.radius() * G.danger_mul)
	if self_clearance(s, angle) >= danger_r:
		return angle
	escape_hits += 1

	var turn: float = G.escape_turn * guard
	var cw := PSMath.norm_angle(angle + turn)
	var ccw := PSMath.norm_angle(angle - turn)
	var clr_cw := self_clearance(s, cw)
	var clr_ccw := self_clearance(s, ccw)
	var cw_ok := clr_cw >= danger_r
	var ccw_ok := clr_ccw >= danger_r
	var side: int = escape_side if escape_side != 0 else 1

	if cw_ok and ccw_ok:
		if side > 0 and clr_cw >= clr_ccw * 0.7:
			return cw
		if side < 0 and clr_ccw >= clr_cw * 0.7:
			return ccw
		var d_cw := absf(PSMath.norm_angle(cw - s.heading))
		var d_ccw := absf(PSMath.norm_angle(ccw - s.heading))
		var go_cw := d_cw <= d_ccw
		escape_side = 1 if go_cw else -1
		return cw if go_cw else ccw
	if cw_ok:
		escape_side = 1
		return cw
	if ccw_ok:
		escape_side = -1
		return ccw

	# Both sides blocked: turn only 35% of the way (the old code always slammed a
	# full lock in one direction, which locked long snakes into ever-tighter circles).
	var go_cw2 := clr_cw >= clr_ccw
	escape_side = 1 if go_cw2 else -1
	escape_stuck += 1
	var target_dir := cw if go_cw2 else ccw
	return PSMath.norm_angle(angle + PSMath.norm_angle(target_dir - angle) * 0.35)


## Anti-loop detector: accumulate heading change and path length per window.
## "Lots of turning, little displacement" means the snake is circling a food it
## cannot reach -> give up on that food and drive straight for a moment.
func update_loop_guard(head: Vector2, s, now: float, dt: float) -> void:
	var L := cfg.ai.anti_loop
	if not L.enabled:
		return

	if has_prev_heading:
		var d := PSMath.norm_angle(s.heading - prev_heading)
		loop_turn += absf(d)
		loop_signed += d
	prev_heading = s.heading
	has_prev_heading = true
	loop_path += s.speed * dt

	if not has_loop_ref:
		loop_ref_x = head.x
		loop_ref_y = head.y
		loop_turn = 0.0
		loop_signed = 0.0
		loop_path = 0.0
		loop_check_at = now + L.window_sec
		return
	if now < loop_check_at:
		return

	var dx := head.x - loop_ref_x
	var dy := head.y - loop_ref_y
	var moved := sqrt(dx * dx + dy * dy)
	var turned_deg := loop_turn * 180.0 / PI
	var ratio := moved / loop_path if loop_path > 1.0 else 1.0
	if turned_deg > L.turn_deg and ratio < L.path_ratio:
		loop_triggers += 1
		escape_until = now + L.escape_sec
		escape_dir = 1 if loop_signed >= 0.0 else -1
		if target != null:
			avoid_food = target
			avoid_food_until = now + L.blacklist_sec
			target = null
			retarget_at = 0.0
	loop_ref_x = head.x
	loop_ref_y = head.y
	loop_turn = 0.0
	loop_signed = 0.0
	loop_path = 0.0
	loop_check_at = now + L.window_sec


## Clear per-round transient state (also used on respawn, like the JS version).
func reset_for_new_round() -> void:
	target = null
	retarget_at = 0.0
	last_control = null
	has_last_control = false
	next_decision_at = 0.0
	aim_bias = 0.0
	aim_bias_target = 0.0
	bias_at = 0.0
	lapse_until = 0.0
	lapse_control = null
	next_lapse_at = 0.0
	smooth_angle = 0.0
	has_smooth_angle = false
	loop_turn = 0.0
	loop_signed = 0.0
	loop_path = 0.0
	has_loop_ref = false
	loop_check_at = 0.0
	has_prev_heading = false
	escape_until = 0.0
	escape_dir = 1
	escape_side = 1
	avoid_food = null
	avoid_food_until = 0.0
	snake.mistake = false


## Clear the calibration counters (tests compare before/after deltas).
func reset_stats() -> void:
	lapses = 0
	mistake_frames = 0


## Bearing towards the nearest non-neck body node (NAN when there is none).
## Used to run *away* from our own coil when breaking out of a loop.
func nearest_body_angle(s) -> float:
	var b: PackedVector2Array = s.body
	var n := b.size()
	if n <= 6:
		return NAN
	var hx := b[0].x
	var hy := b[0].y
	var best := NAN
	var best_d2 := INF
	var k := 6
	while k < n:
		var dx := b[k].x - hx
		var dy := b[k].y - hy
		var d2 := dx * dx + dy * dy
		if d2 < best_d2:
			best_d2 = d2
			best = atan2(dy, dx)
		k += 2
	return best


## First-order low-pass on the *intent* angle (tau ~ 0.09 s).
## The physical rate cap stays in the snake, this only removes staircase commands.
func lowpass(angle: float, dt: float) -> float:
	if not has_smooth_angle:
		smooth_angle = angle
		has_smooth_angle = true
		return angle
	var k := 1.0 - exp(-dt / 0.09)
	smooth_angle = PSMath.norm_angle(smooth_angle + PSMath.norm_angle(angle - smooth_angle) * k)
	return smooth_angle


# ---------------------------------------------------------------- think

## Produce this frame's control. Returns null when the snake is dead.
## `game` is deliberately untyped: `PSGame` preloads this script, so a typed
## parameter would create a cyclic preload. Only a handful of fields are read per
## frame, and each is copied into a statically typed local once.
func think(game, dt: float, now: float):
	var s := snake
	if not s.alive:
		return null
	var head: Vector2 = s.body[0]

	# Respawn / round-start freeze: body cannot move but the snake snaps its
	# heading to the command, so emit the *current* heading to avoid a head whip.
	if s.is_frozen():
		_ctrl.set_ai(s.heading, AI_TURN_EASE, 0.0)
		return _ctrl

	var A := cfg.ai
	var D := A.difficulty
	var ST: PSConfig.StyleCfg = style if style != null else A.styles.neutral
	var tune: PSRuntimeTuning = game.tuning
	var level := clampf(tune.ai_level if is_finite(tune.ai_level) else D.level, D.level_min, D.level_max)
	var mistake_rate := clampf(
		tune.ai_mistake if is_finite(tune.ai_mistake) else D.mistake_rate,
		D.mistake_min, D.mistake_max)
	var weak := 1.0 - level
	# ---- pressure: exactly 0 at or below difficulty 0.5 (legacy replay) ----
	var pressure: float = cfg.compute_ai_pressure(level, tune.ai_pressure)
	var hunt := pressure if A.hunt.enabled else 0.0
	var surv := pressure if A.survival.enabled else 0.0
	# Big snakes stop taking risks and defend the lead.
	var maturity := clampf(
		(float(s.body.size()) - float(cfg.snake.start_segments)) / 60.0, 0.0, 1.0) * surv
	var sense: float = (D.sense_floor + (1.0 - D.sense_floor) * level) * ST.sense_mul
	var old_guard := 1.0 - level
	# Self-avoidance strength: legacy was 1-level, which made "smarter" mean
	# "suicidal". Pressure slides it towards `level`; they meet at level 0.5.
	var guard := clampf(old_guard + (level - old_guard) * surv + 0.35 * maturity, 0.0, 1.0)

	# Turn ability is written every frame so the slider applies without a rebuild.
	s.turn_mul = skill * turn_factor(level)
	s.mistake = false

	# ---------- 0. spacing out ----------
	# During a lapse the brain skips probing and foraging and returns a fixed,
	# deliberately-wrong heading, so the AI really does hit things.
	if lapse_until > 0.0 and now < lapse_until:
		s.mistake = true
		mistake_frames += 1
		return lapse_control
	if lapse_until > 0.0:
		lapse_until = 0.0
		lapse_control = null
		next_lapse_at = now + rng.rand_range(0.5, 1.4)
		next_decision_at = 0.0
	if now >= next_lapse_at and mistake_rate > 0.0 \
			and rng.randf() < D.lapse_per_sec * mistake_rate * dt * ST.lapse_mul:
		var dur := rng.rand_range(D.lapse_min_sec, D.lapse_max_sec)
		var dir := -1.0 if rng.randf() < 0.5 else 1.0
		var off := rng.rand_range(D.lapse_turn_max * 0.45, D.lapse_turn_max) * dir
		lapse_until = now + dur
		_lapse_ctrl.set_ai(PSMath.norm_angle(s.heading + off), AI_TURN_EASE, 0.0)
		lapse_control = _lapse_ctrl
		lapses += 1
		mistake_frames += 1
		s.mistake = true
		return lapse_control

	# ---------- 0.6 anti-loop ----------
	# Must run before the reaction interval: that branch returns the previous
	# command, which would otherwise keep feeding a circling snake forever.
	update_loop_guard(head, s, now, dt)
	var loop_escaping := now < escape_until

	# ---------- 0.5 reaction interval ----------
	# Low difficulty re-decides less often and coasts on the last command in
	# between, which reads as "slow to react". Self avoidance still runs every
	# frame (being slow is no excuse for eating your own body).
	if not loop_escaping and now < next_decision_at and has_last_control:
		var base = last_control
		var safe := self_escape(s, base.angle, guard)
		var a := lowpass(safe, dt)
		if a == base.angle:
			return base
		_ctrl_alt.copy_from(base)
		_ctrl_alt.angle = a
		return _ctrl_alt

	# ---------- 1. pick a target food ----------
	if not loop_escaping and (target == null or now >= retarget_at):
		target = find_food(game, head, weak)
		# Low difficulty locks a target for longer (fails to notice it is gone).
		retarget_at = now + rng.rand_range(0.4, 0.9) + D.retarget_max_sec * weak

	# desired direction: break-out > food > wander
	var desired_x := 0.0
	var desired_y := 0.0
	if loop_escaping:
		# Drive away from our own coil rather than straight ahead (straight ahead
		# is usually the very circle we are trying to escape).
		var a2 := s.heading
		var near := nearest_body_angle(s)
		if is_finite(near):
			var away := PSMath.norm_angle(near + PI)
			if absf(PSMath.norm_angle(away - s.heading)) < 1.2:
				a2 = away
		a2 = PSMath.norm_angle(a2 + float(escape_dir) * A.anti_loop.escape_turn)
		desired_x = cos(a2)
		desired_y = sin(a2)
	elif target != null:
		desired_x = target.x - head.x
		desired_y = target.y - head.y
	else:
		wander_angle += rng.rand_range(-1.0, 1.0) * dt * 1.6
		desired_x = cos(wander_angle)
		desired_y = sin(wander_angle)
	var dl := sqrt(desired_x * desired_x + desired_y * desired_y)
	if dl == 0.0:
		dl = 1.0
	desired_x /= dl
	desired_y /= dl

	# ---------- 2. forward probing ----------
	var ax := cos(s.heading)
	var ay := sin(s.heading)
	var SV := A.survival
	var probe_dist := (A.probe_dist + SV.wall_probe_add * surv) * sense
	# Thicker snakes must start avoiding earlier or they look stupid when the
	# collision radius grows but their planning distance does not.
	var girth_extra: float = s.radius() - cfg.snake.radius
	var avoid_r := (A.avoid_radius + girth_extra) * (1.0 + SV.sense_add * surv) * sense
	var wall_push := sense * (1.0 + SV.wall_push_add * surv) * (1.0 + 0.40 * maturity)

	var avoid_x := 0.0
	var avoid_y := 0.0

	# 2.1 walls: probe two points ahead and push away from the padded border
	var wall_m: float = cfg.snake.wall_pad + 30.0
	var world_w: float = game.world_w
	var world_h: float = game.world_h
	var step_i := 0
	while step_i < 2:
		var d: float = probe_dist * (0.55 if step_i == 0 else 1.0)
		var px := head.x + ax * d
		var py := head.y + ay * d
		if px < wall_m:
			avoid_x += ((wall_m - px) / 60.0) * wall_push
		if px > world_w - wall_m:
			avoid_x -= ((px - (world_w - wall_m)) / 60.0) * wall_push
		if py < wall_m:
			avoid_y += ((wall_m - py) / 60.0) * wall_push
		if py > world_h - wall_m:
			avoid_y -= ((py - (world_h - wall_m)) / 60.0) * wall_push
		step_i += 1

	# 2.2 other bodies / heads: closer means stronger push, front hemisphere only.
	# Our own body is excluded here (two opposite pushes would cancel); it is
	# handled by self_escape() at route level instead.
	# Flat typed arrays (position / owner id / owner length) keep this loop free
	# of Variant property lookups, which matters on the target Amlogic box.
	var avoid_r2 := avoid_r * avoid_r
	var hzs: PackedVector2Array = game.hazards
	var hz_ids: PackedInt32Array = game.hazard_owner_id
	var hz_lens: PackedFloat32Array = game.hazard_owner_len
	var hz_n: int = game.hazard_count
	var s_len := float(s.body.size())
	var s_id := s.id
	var i := 0
	while i < hz_n:
		if hz_ids[i] == s_id:
			i += 1
			continue
		var vx := hzs[i].x - head.x
		var vy := hzs[i].y - head.y
		var d2 := vx * vx + vy * vy
		if d2 > avoid_r2 or d2 < 1e-3:
			i += 1
			continue
		if vx * ax + vy * ay < 0.0:
			i += 1
			continue
		var dd := sqrt(d2)
		var push := (1.0 - dd / avoid_r) / dd
		# `avoid_mul` = style courage; `flee_mul` = extra respect for bigger snakes.
		var bigger: bool = hz_lens[i] > s_len * 1.15
		var k: float = 1.6 * sense * ST.avoid_mul * (ST.flee_mul if bigger else 1.0)
		avoid_x -= vx * push * k
		avoid_y -= vy * push * k
		i += 1

	# ---------- 3. attack (head-on hunting) ----------
	var H := A.hunt
	var base_ratio: float = A.attack_ratio + D.attack_bonus * weak
	var attack_ratio: float = (base_ratio + (H.ratio - base_ratio) * hunt) * ST.attack_mul
	var attack_range: float = 420.0 * (0.4 + 0.6 * level) + H.range_add * hunt
	var attack_x := 0.0
	var attack_y := 0.0
	for other in game.snakes:
		if other == s or not other.alive:
			continue
		if s_len < float(other.body.size()) * attack_ratio:
			continue
		var oh: Vector2 = other.body[0]
		var odx := oh.x - head.x
		var ody := oh.y - head.y
		if odx * odx + ody * ody > attack_range * attack_range:
			continue

		# Intercept point: aim where the target will be, not where it is.
		# With hunt == 0 travel/cut/focus collapse to the legacy "chase the head".
		var ospeed: float = other.speed if other.speed != 0.0 else cfg.snake.base_speed
		var travel := minf(H.lead_max, ospeed * H.lead_sec * hunt)
		var ox := cos(other.heading)
		var oy := sin(other.heading)
		# Lateral cut: put our body across its nose; side alternates by snake id.
		var cut := travel * H.cut_in * (1.0 if (s.id % 2) != 0 else -1.0)
		var tx := oh.x + ox * travel - oy * cut
		var ty := oh.y + oy * travel + ox * cut
		var to_x := oh.x - head.x
		var to_y := oh.y - head.y
		var tl := sqrt(to_x * to_x + to_y * to_y)
		if tl == 0.0:
			tl = 1.0
		var facing := (ax * to_x + ay * to_y) / tl
		# Charging from the side/behind counts as "I hit them" and gifts the kill,
		# so only go all-in when actually facing the target.
		var charge := 1.0 - hunt + hunt * (0.35 + 0.65 * clampf((facing + 1.0) / 2.0, 0.0, 1.0))
		var vx2 := tx - head.x
		var vy2 := ty - head.y
		var il := sqrt(vx2 * vx2 + vy2 * vy2)
		if il == 0.0:
			il = 1.0
		var focus := 1.0
		if other.is_player:
			focus = 1.0 + (H.player_focus - 1.0) * hunt
		var k2 := focus * charge * (1.0 - 0.60 * maturity)
		attack_x += (vx2 / il) * k2
		attack_y += (vy2 / il) * k2

	# ---------- 4. blend into a desired heading ----------
	var av_len := sqrt(avoid_x * avoid_x + avoid_y * avoid_y)
	var mix_x := desired_x
	var mix_y := desired_y
	if av_len > 0.05:
		var w := clampf(av_len, 0.0, 2.2) * sense * (1.0 + 0.50 * maturity)
		mix_x = desired_x * ST.food_weight + (avoid_x / av_len) * w
		mix_y = desired_y * ST.food_weight + (avoid_y / av_len) * w
	if attack_x != 0.0 or attack_y != 0.0:
		var aggression: float = (0.8 + H.aggression_add * hunt) * (0.25 + 0.75 * level) * ST.aggression_mul
		mix_x += attack_x * aggression
		mix_y += attack_y * aggression
	var ml := sqrt(mix_x * mix_x + mix_y * mix_y)
	if ml == 0.0:
		ml = 1.0
	var angle := atan2(mix_y / ml, mix_x / ml)

	# ---------- 4.5 wide per-frame delta guard ----------
	# Only a safety net (92 degrees): the real smoothing is the low-pass below.
	var max_delta := 1.6
	var delta := PSMath.norm_angle(angle - s.heading)
	angle = PSMath.norm_angle(s.heading + clampf(delta, -max_delta, max_delta))

	# ---------- 4.6 low-frequency aim jitter ----------
	# White noise would be averaged out by the turn controller, so the bias is
	# re-rolled every 0.45..1.1 s and interpolated (no step jumps).
	if now >= bias_at:
		aim_bias_target = rng.rand_range(-1.0, 1.0) * D.aim_noise_max * weak
		bias_at = now + rng.rand_range(0.45, 1.1)
	aim_bias += (aim_bias_target - aim_bias) * clampf(dt * 6.0, 0.0, 1.0)
	angle = PSMath.norm_angle(angle + aim_bias)

	# ---------- 4.7 avoidance *then* low-pass ----------
	# Order matters: safety first, smoothing second. The other way round makes
	# avoidance jump to a new heading every frame (measured 7-9 reversals/s).
	angle = self_escape(s, angle, guard)
	angle = lowpass(angle, dt)

	# ---------- 5. serpentine wobble ----------
	# Numerically equals the old elbow bias: bend * elbowWeight * elbowBiasGain.
	this_wobble(dt)
	var wobble := sin(wobble_phase) * wobble_amp * AI_WOBBLE_GAIN

	_ctrl.set_ai(angle, AI_TURN_EASE, wobble)
	last_control = _ctrl
	has_last_control = true
	next_decision_at = now + D.reaction_max_sec * weak
	return _ctrl


## Advance the wobble phase; kept separate so the RNG draw order stays obvious.
func this_wobble(dt: float) -> void:
	wobble_phase += dt * rng.rand_range(1.6, 2.6)


# ---------------------------------------------------------------- foraging

## Nearest *useful* food. Only food inside `ai.food_fov` of the heading counts:
## turning around to chase food behind you is the main cause of self-biting.
## Low difficulty may deliberately pick the 2nd..6th nearest (sloppy).
func find_food(game, head: Vector2, weak: float):
	var foods: Array = game.foods
	near_count = 0
	var D := cfg.ai.difficulty
	var ST: PSConfig.StyleCfg = style if style != null else cfg.ai.styles.neutral
	var best: PSFood = null
	var best_score := INF
	var best_d2 := INF
	var now: float = game.time
	var fov: float = cfg.ai.food_fov
	var heading: float = snake.heading
	var i := 0
	var n := foods.size()
	while i < n:
		var f: PSFood = foods[i]
		# Food we just declared unreachable stays blacklisted for a while,
		# otherwise it becomes the nearest target again the moment we break out.
		if f == avoid_food and now < avoid_food_until:
			i += 1
			continue
		var dx: float = f.x - head.x
		var dy: float = f.y - head.y
		if absf(PSMath.norm_angle(atan2(dy, dx) - heading)) > fov:
			i += 1
			continue
		var d2 := dx * dx + dy * dy
		var score := d2 * (ST.big_food_bias if f.big else 1.0)
		if score < best_score:
			best_score = score
			best_d2 = d2
			best = f
		# keep the six best (weighted) candidates, sorted ascending
		if near_count < 6:
			var pos := near_count
			while pos > 0 and near_score[pos - 1] > score:
				near_score[pos] = near_score[pos - 1]
				near_food[pos] = near_food[pos - 1]
				pos -= 1
			near_score[pos] = score
			near_food[pos] = f
			near_count += 1
		elif score < near_score[5]:
			var pos2 := 5
			while pos2 > 0 and near_score[pos2 - 1] > score:
				near_score[pos2] = near_score[pos2 - 1]
				near_food[pos2] = near_food[pos2 - 1]
				pos2 -= 1
			near_score[pos2] = score
			near_food[pos2] = f
		i += 1

	# Nothing close enough: wander towards the middle of the map instead of all
	# eight snakes racing for the same pellet.
	var wander_r: float = cfg.ai.wander_radius
	if best == null or best_d2 > wander_r * wander_r:
		wander_angle = atan2(head.y - game.world_h * 0.5, head.x - game.world_w * 0.5) + PI \
			+ rng.rand_range(-0.7, 0.7)
		return null

	# Difficulty 1 never makes mistakes here (probability 0); styles scale it.
	if weak > 0.0 and near_count > 1 \
			and rng.randf() < D.sloppy_food_max * weak * ST.sloppy_mul:
		return near_food[1 + int(rng.randf() * float(near_count - 1))]
	return best


## Drop a target that was just eaten; the next frame picks a new one.
func forget_target(food) -> void:
	if target == food:
		target = null
		retarget_at = 0.0


func _to_string() -> String:
	return "Brain(skill=%.2f style=%s lapses=%d)" % [
		skill, "" if style == null else str(style.key), lapses,
	]
