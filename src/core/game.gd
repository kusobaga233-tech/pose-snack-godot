extends RefCounted
## The world and the rules (JS `js/game.js`).
##
## Owns: the 8 snakes, the food pool, powerups, collision arbitration, respawn
## timers, the 2 minute round clock and the final length ranking.
##
## Collision rules (port deviation marked *):
##   * head vs wall                               -> dies
##   * head vs its OWN body                       -> no-op* (default; the JS
##                                                   prototype killed here).
##                                                   Set `collide.self_kill` to
##                                                   restore the prototype rule.
##   * head vs another snake's body               -> dies
##   * head vs head, both charging (cos >= 0.55)  -> longer one eats the shorter,
##                                                   equal length = both die
##   * head vs head, side-on                      -> whoever charged harder dies
##   * any death scatters the body into food
##   * humans respawn after 3 s, AI respawns 3 s later somewhere far away;
##     the field always holds 7 AI + 1 human (8 ranked players)
##   * 2:00 round, no score: ranking is the body length at the whistle
##
## Determinism / headless contract
## ------------------------------
## `update(dt, signal, real_dt)` is a pure step function of the current state plus
## injected RNG: no Nodes, no Timers, no Tween, no wall clock. A test can therefore
## run a full round in a loop and get identical results every time.
##   * `dt`      simulated seconds (as in the browser, clamp it to <= 0.05;
##               colliding bodies need a sane step size)
##   * `real_dt` seconds used by *countdowns* only (round timer, respawn timer,
##               buff duration). Pass the same value as `dt` for headless runs.
##               The JS version separated these because it clamped `dt` on slow
##               frames; the port exposes the same knob for the same reason.
##
## Per-frame presentation reads are documented in docs/core-model.md.

const PSMath = preload("res://src/core/ps_math.gd")
const PSRng = preload("res://src/core/rng.gd")
const PSFood = preload("res://src/core/food.gd")
const PSPowerup = preload("res://src/core/powerup.gd")
const PSSnake = preload("res://src/core/snake.gd")
const PSBrain = preload("res://src/core/brain.gd")
const PSEventQueue = preload("res://src/core/events.gd")
const PSRankRow = preload("res://src/core/rank_row.gd")
const PSRoundResult = preload("res://src/core/round_result.gd")
const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const SnakeControl = preload("res://src/core/snake_control.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")

# ---- game states (JS `state`: ready | playing | finished) -----------------
const STATE_READY := 0
## Port-only extra state: a visible "3-2-1" countdown before play. `start()`
## with no argument goes straight to PLAYING, which is what the JS game does.
const STATE_COUNTDOWN := 1
const STATE_PLAYING := 2
const STATE_FINISHED := 3

## Hard cap of simultaneous cosmetic events (see PSEventQueue).
const MAX_SNAKES := 8

# ---------------------------------------------------------------- injected

var cfg: PSConfig = null
var tuning: PSRuntimeTuning = null
## Seed this world was built from (kept for logging / replay).
var seed_value: int = 0
## World stream (JS `Math.random()`): food spawns, respawn points, speed jitter.
var rng: PSRng = null
## Per-round stream (JS `roundRandom()`): style + head-style shuffles.
var round_rng: PSRng = null
## Powerup-only stream (JS `powerupRandom()`): never consumed by anything else.
var powerup_rng: PSRng = null

# ---------------------------------------------------------------- world

var world_w: float = 4800.0
var world_h: float = 2700.0
## Cosmetic events produced by the last `update()` (drained by the presentation).
var events = PSEventQueue.new()

# ---------------------------------------------------------------- round

var state: int = STATE_READY
## Remaining seconds of the pre-round countdown (only in STATE_COUNTDOWN).
var countdown_left: float = 0.0
## Simulated seconds since the round started.
var time: float = 0.0
## Internal legacy score counter (not part of the ranking any more).
var score: int = 0
## Historical best length; persistence belongs to the shell, not to the rules.
var best_length: int = 16
## Kills/deaths of the human player(s) (kept for the HUD).
var kills: int = 0
var deaths: int = 0
## 1-based round counter (drives the per-round RNG seed, like the JS game).
var round_index: int = 0
## Seconds left in the current round.
var round_left: float = 120.0
## Sorted rows of the last settlement (`PSRankRow`), empty while playing.
var ranking: Array = []
## Settlement payload (`PSRoundResult`) or null.
var round_result = null

# ---------------------------------------------------------------- entities

var snakes: Array = []
## Human snakes only, `players[0]` is always player 1.
var players: Array = []
## `players[0]` (kept for the single-player code paths and the HUD).
var player = null
var player_count: int = 1
var player_spawns: Array = []
var brains: Array = []

var foods: Array = []
var food_spawn_cd: float = 0.0

var powerups: Array = []
var powerup_spawn_timer: float = 0.0

## Body sample points rebuilt every frame (AI avoidance + food spawn checks).
## Parallel arrays; `hazard_count` holds the live entry count and the arrays keep
## their capacity between frames, so a 60 Hz frame does not allocate.
var hazards: PackedVector2Array = PackedVector2Array()
## Owner snake id per hazard point.
var hazard_owner_id: PackedInt32Array = PackedInt32Array()
## Owner snake length per hazard point (avoids a Variant lookup in the AI loop).
var hazard_owner_len: PackedFloat32Array = PackedFloat32Array()
var hazard_count: int = 0

## Camera focus point (player head; frozen while the player is dead).
var cam_target: Vector2 = Vector2.ZERO
## One focus point per human snake (split screen).
var cam_targets: Array = []

# ---------------------------------------------------------------- diagnostics

var stat_food_spawned: int = 0
var stat_food_trimmed: int = 0
var stat_food_eaten: int = 0
var stat_food_max_batch: int = 0

# ---------------------------------------------------------------- internals

var _player_ctrl = SnakeControl.new()
var _single_signal: Array = [null]
var _frame_id: int = 0

# Palettes (JS module constants in game.js).
var _ai_colors: Array = []
var _food_colors: Array = []
var _food_faces: Array = []


func _init(p_cfg: PSConfig = null, p_tuning: PSRuntimeTuning = null,
		p_seed: int = 12345) -> void:
	cfg = p_cfg if p_cfg != null else PSConfig.new()
	tuning = p_tuning if p_tuning != null else PSRuntimeTuning.new(cfg)
	seed_value = p_seed
	world_w = cfg.world.w
	world_h = cfg.world.h
	rng = PSRng.new(p_seed)
	round_rng = PSRng.new(0x51ED270B)
	powerup_rng = PSRng.new(0x9E3779B9)
	best_length = cfg.snake.start_segments
	_build_palettes()
	build_snakes()
	reset()


func _build_palettes() -> void:
	# AI hues avoid the player's green->cyan->blue arc (see js/game.js comment).
	_ai_colors = [
		Color("5C8AFF"), Color("7F5CFF"), Color("A55CFF"), Color("D05CFF"),
		Color("FF5CD0"), Color("FF5C8A"), Color("FF6B5C"), Color("FF9E5C"),
	]
	_food_colors = [
		Color("FF4D9D"), Color("FFD93D"), Color("5BC8FF"),
		Color("9D6BFF"), Color("4DEFA8"), Color("FF8A4D"),
	]
	_food_faces = [&"happy", &"wink", &"wide", &"tongue", &"sleepy"]


# ---------------------------------------------------------------- construction

## Create 1-2 humans + AI so the field always holds `round.total_players` snakes.
func build_snakes() -> void:
	players.clear()
	snakes.clear()
	brains.clear()

	var n := clampi(player_count, 1, 2)
	var i := 0
	while i < n:
		var pc = cfg.round.player_colors[i % cfg.round.player_colors.size()]
		var s = PSSnake.new(cfg, tuning, rng)
		s.id = i
		s.is_player = true
		s.player_index = i
		s.color = pc.color
		s.head_color = pc.head
		s.has_head_color = true
		s.grad = pc.grad
		s.display_name = cfg.round.player_names[i] if i < cfg.round.player_names.size() \
			else "玩家 %d" % (i + 1)
		players.append(s)
		snakes.append(s)
		i += 1
	player = players[0]

	var ai_count := maxi(0, cfg.round.total_players - n)
	i = 0
	while i < ai_count:
		var s = PSSnake.new(cfg, tuning, rng)
		s.id = n + i
		s.is_player = false
		s.color = _ai_colors[i % _ai_colors.size()]
		s.display_name = "AI %d" % (i + 1)
		# Individual speed jitter so the AI pack does not move in lockstep.
		s.speed_mul = 1.0 - rng.rand_range(-1.0, 1.0) * cfg.ai.speed_jitter
		snakes.append(s)
		# One independent RNG stream per brain, derived from the world seed.
		var brain_seed := PSRng.mix_seed(seed_value, i + 1)
		brains.append(PSBrain.new(s, cfg, PSRng.new(brain_seed)))
		i += 1

	# Spawn points: split-screen players start side by side, never stacked.
	var px := world_w * 0.5
	var py := world_h * 0.5
	var gap := 620.0 if n > 1 else 0.0
	player_spawns.clear()
	cam_targets.clear()
	i = 0
	while i < n:
		var off := 0.0
		if n > 1:
			off = -gap * 0.5 if i == 0 else gap * 0.5
		player_spawns.append(Vector2(px + off, py))
		cam_targets.append(Vector2(px, py))
		i += 1
	cam_target = Vector2(px, py)


## Switch between 1 and 2 human players; rebuilds the field and resets the world.
func set_player_count(n: int) -> int:
	var v := 2 if n >= 2 else 1
	if v == player_count and players.size() == v:
		return player_count
	player_count = v
	build_snakes()
	reset()
	return player_count


## Reset to the ready state (no snake moves until `start()` is called).
func reset() -> void:
	state = STATE_READY
	time = 0.0
	score = 0
	kills = 0
	deaths = 0
	foods.clear()
	powerups.clear()
	round_left = cfg.round.duration_sec
	ranking.clear()
	round_result = null

	# New round: per-round styles are shuffled from a reproducible stream.
	round_index += 1
	round_rng.reset((0x51ED270B ^ ((round_index * 2654435761) & 0xFFFFFFFF)) & 0xFFFFFFFF)

	var i := 0
	while i < snakes.size():
		var s = snakes[i]
		s.kills = 0
		s.food_eaten = 0
		s.deaths = 0
		s.peak_length = cfg.snake.start_segments
		s.style = null
		s.style_label = ""
		s.mistake = false
		i += 1

	# Humans get a fixed spawn point, facing +X (into the arena).
	i = 0
	while i < players.size():
		var p = players[i]
		var sp: Vector2 = player_spawns[i] if i < player_spawns.size() else player_spawns[0]
		p.reset(sp.x, sp.y, 0.0, cfg.snake.start_segments)
		p.immune_until = 0.0
		p.freeze_until = 0.0
		if i < cam_targets.size():
			cam_targets[i] = sp
		i += 1

	# AI spawn far away, facing roughly towards the centre (a random heading can
	# point straight at a wall and kill the AI within a second of the start).
	i = 0
	while i < snakes.size():
		var s = snakes[i]
		i += 1
		if s.is_player:
			continue
		var sp := spawn_point(900.0)
		s.reset(sp.x, sp.y, inward_heading(sp.x, sp.y), cfg.snake.start_segments)
		s.kills = 0
		s.food_eaten = 0
		s.mistake = false

	i = 0
	while i < brains.size():
		brains[i].reset_for_new_round()
		i += 1
	assign_styles()
	assign_head_styles()

	# Fill the arena. NOTE: this intentionally runs before `rebuild_hazards()`,
	# exactly like the JS `reset()` (which therefore tests spawn distance against
	# the previous frame's body samples; the first round of a session has none).
	i = 0
	while i < cfg.food.target_count:
		foods.append(random_food())
		i += 1
	food_spawn_cd = 0.0

	if player != null and player.body.size() > 0:
		cam_target = player.body[0]
	rebuild_hazards()

	powerup_rng.reset(0x9E3779B9)
	powerup_spawn_timer = cfg.powerups.spawn_sec
	if cfg.powerups.enabled:
		i = 0
		while i < cfg.powerups.target_count:
			powerups.append(random_powerup())
			i += 1


## Begin the round. `countdown_sec > 0` runs a port-only countdown state first
## (the JS game starts immediately; the visual countdown lives in the shell).
func start(countdown_sec: float = 0.0) -> void:
	reset()
	var i := 0
	while i < players.size():
		var p = players[i]
		p.immune_until = time + cfg.player.immunity
		apply_spawn_freeze(p)
		i += 1
	if countdown_sec > 0.0:
		state = STATE_COUNTDOWN
		countdown_left = countdown_sec
	else:
		state = STATE_PLAYING


## Heading roughly towards the world centre plus up to +-0.85 rad of jitter.
func inward_heading(x: float, y: float) -> float:
	var to_center := atan2(world_h * 0.5 - y, world_w * 0.5 - x)
	return to_center + rng.rand_range(-0.85, 0.85)


## Respawn freeze length, clamped to the slider range (JS `freezeSec`).
func freeze_sec() -> float:
	return tuning.freeze_sec()


## Put a freshly spawned snake into its "cannot move, cannot be hit" window.
func apply_spawn_freeze(snake) -> void:
	snake.freeze_until = time + freeze_sec()


# ---------------------------------------------------------------- round setup helpers

## Shuffle the personality pool and hand one to each AI (players get none).
func assign_styles() -> void:
	var S = cfg.ai.styles
	var pool: Array = []
	if S.enabled:
		pool = S.pool.duplicate()
		var i := pool.size() - 1
		while i > 0:
			var j := int(round_rng.randf() * float(i + 1))
			var t = pool[i]
			pool[i] = pool[j]
			pool[j] = t
			i -= 1
	var k := 0
	while k < brains.size():
		brains[k].set_style(pool[k % pool.size()] if pool.size() > 0 else null)
		k += 1
	k = 0
	while k < players.size():
		players[k].style = null
		players[k].style_label = ""
		k += 1


## Shuffle the 9 NPC head styles and hand out 7 distinct ones (humans keep theirs).
func assign_head_styles() -> void:
	var H = cfg.ai.head_style
	var on: bool = H.enabled and tuning.head_style_on
	var pool: Array = []
	if on:
		pool = H.pool.duplicate()
		var i := pool.size() - 1
		while i > 0:
			var j := int(round_rng.randf() * float(i + 1))
			var t = pool[i]
			pool[i] = pool[j]
			pool[j] = t
			i -= 1
	var k := 0
	var i2 := 0
	while i2 < snakes.size():
		var s = snakes[i2]
		i2 += 1
		if s.is_player:
			s.head_style = &""
			continue
		s.head_style = pool[k] if k < pool.size() else &""
		k += 1


# ---------------------------------------------------------------- main update

## Advance one frame. Accepts a single steer input or an array (split screen).
## `real_dt < 0` means "same as dt" (the headless case).
func update(dt: float, signal_in: Variant = null, real_dt: float = -1.0) -> void:
	events.begin_frame()
	_frame_id += 1

	if real_dt < 0.0:
		real_dt = dt

	if state == STATE_COUNTDOWN:
		countdown_left -= real_dt
		if countdown_left <= 0.0:
			countdown_left = 0.0
			state = STATE_PLAYING
		return
	if state != STATE_PLAYING:
		return

	# ---- 0. round countdown (real seconds, so hit-stop cannot stretch it) ----
	if cfg.round.mode == &"timed":
		round_left -= real_dt
		if round_left <= 0.0:
			round_left = 0.0
			finish_round()
			return

	time += dt
	# One clock write per frame; the snakes' is_frozen()/is_immune() read this.
	var i := 0
	while i < snakes.size():
		snakes[i].now = time
		snakes[i].tick_buffs(real_dt)
		i += 1

	rebuild_hazards()

	var signals: Array
	if signal_in is Array:
		signals = signal_in
	else:
		_single_signal[0] = signal_in
		signals = _single_signal

	# ---- 1. human control (one signal per human in split screen) ----
	i = 0
	while i < players.size():
		var p = players[i]
		var sig = null
		if i < signals.size():
			sig = signals[i]
		elif signals.size() > 0:
			sig = signals[0]
		i += 1
		if sig == null:
			continue
		if p.alive:
			if sig.is_usable():
				_player_ctrl.set_player(sig.steer_angle_rad, sig.speed_scale)
			else:
				# No tracking: keep the current heading and the previous speed.
				_player_ctrl.angle = NAN
				_player_ctrl.speed_scale = NAN
			p.update(dt, _player_ctrl)
			update_player_look_at(p)
		else:
			p.respawn_timer -= real_dt
			if p.respawn_timer <= 0.0:
				respawn_player(p)

	# ---- 2. AI ----
	i = 0
	while i < brains.size():
		var brain = brains[i]
		var s = brain.snake
		i += 1
		if not s.alive:
			s.mistake = false
			s.respawn_timer -= real_dt
			if s.respawn_timer <= 0.0:
				respawn_ai(s)
			continue
		var control = brain.think(self, dt, time)
		if control != null:
			s.update(dt, control)

	# ---- 3. collisions ----
	resolve_collisions()

	# ---- 4. powerups + food ----
	# Order matters: magnet pulls food in, then pickups, then eating, so food
	# dragged onto the mouth is eaten on the same frame.
	apply_magnets(dt)
	collect_powerups()
	eat_food()
	ensure_food(real_dt)
	ensure_powerups(real_dt)

	# ---- 5. camera focus points ----
	i = 0
	while i < players.size():
		var p = players[i]
		i += 1
		if not p.alive or p.body.size() == 0:
			continue
		if p.player_index >= 0 and p.player_index < cam_targets.size():
			cam_targets[p.player_index] = p.body[0]
	cam_target = cam_targets[0] if cam_targets.size() > 0 else cam_target

	# ---- 6. per-round stats (after growth / absorbs / collisions settled) ----
	i = 0
	while i < snakes.size():
		var s2 = snakes[i]
		i += 1
		if s2.alive and s2.body.size() > s2.peak_length:
			s2.peak_length = s2.body.size()
	i = 0
	while i < players.size():
		var p2 = players[i]
		i += 1
		if p2.peak_length > best_length:
			best_length = p2.peak_length


## Eyes follow the nearest pellet within 520 px (cosmetic only).
func update_player_look_at(snake) -> void:
	if snake.body.size() == 0:
		return
	var h: Vector2 = snake.body[0]
	var best = null
	var best_d2 := 520.0 * 520.0
	var i := 0
	while i < foods.size():
		var f = foods[i]
		var dx: float = h.x - f.x
		var dy: float = h.y - f.y
		var d2 := dx * dx + dy * dy
		if d2 < best_d2:
			best_d2 = d2
			best = f
		i += 1
	if best != null:
		snake.look_at = Vector2(best.x, best.y)
		snake.has_look_at = true


## Sample every second body node of every living snake into the hazard arrays.
func rebuild_hazards() -> void:
	var needed := 0
	var i := 0
	while i < snakes.size():
		var s = snakes[i]
		if s.alive:
			needed += int(ceil(float(s.body.size()) / 2.0))
		i += 1
	if hazards.size() < needed:
		hazards.resize(needed + 64)
		hazard_owner_id.resize(needed + 64)
		hazard_owner_len.resize(needed + 64)
	var n := 0
	i = 0
	while i < snakes.size():
		var s = snakes[i]
		i += 1
		if not s.alive:
			continue
		var b: PackedVector2Array = s.body
		var m := b.size()
		var owner_len := float(m)
		var owner_id: int = s.id
		var k := 0
		while k < m:
			hazards[n] = b[k]
			hazard_owner_id[n] = owner_id
			hazard_owner_len[n] = owner_len
			n += 1
			k += 2
	hazard_count = n


# ---------------------------------------------------------------- collision resolution

func resolve_collisions() -> void:
	var n := snakes.size()
	var C = cfg.collide
	var SH = cfg.ai.self_hit

	# ---- 1. wall (+ own body only in legacy mode) ----
	# DEFAULT RULE (`cfg.collide.self_kill == false`): a head touching its OWN
	# body is a no-op. The snake overlaps/continues; nothing dies, scatters,
	# scores, re-times or publishes an event, and the head is not even clamped.
	# `self_kill == true` restores the JS prototype rule: humans use the standard
	# self-hit test, AI uses the slightly forgiving `ai.self_hit` (start later,
	# smaller radius) so grazing its own body is not instant death. Movement and
	# decisions are untouched in both modes; `PSSnake.hit_self()` stays available
	# as an entity query either way.
	var self_kill: bool = C.self_kill
	var i := 0
	while i < n:
		var s = snakes[i]
		i += 1
		if not s.alive or s.is_immune():
			continue
		var self_hit := false
		if self_kill:
			self_hit = s.hit_self() if s.is_player else s.hit_self(SH.skip, SH.radius_mul)
		if s.hit_wall() or self_hit:
			s.clamp_to_world()
			kill_snake(s, null)

	# ---- 2. head vs head ----
	i = 0
	while i < n:
		var a = snakes[i]
		if not a.alive or a.is_immune():
			i += 1
			continue
		var j := i + 1
		while j < n:
			var b = snakes[j]
			if not b.alive or b.is_immune() or not a.alive:
				j += 1
				continue
			var ha: Vector2 = a.body[0]
			var hb: Vector2 = b.body[0]
			# Head vs head radius uses the *average* of both radii, so a small
			# snake passing a huge one is not swallowed by the huge hitbox.
			var head_r: float = (a.radius() + b.radius()) * 0.5 * C.head_radius
			var dx := hb.x - ha.x
			var dy := hb.y - ha.y
			var d2 := dx * dx + dy * dy
			if d2 > head_r * head_r:
				j += 1
				continue
			var d := sqrt(d2)
			if d < 1e-6:
				j += 1
				continue
			var nx := dx / d
			var ny := dy / d
			# How hard each snake is driving into the other (1 = head on).
			var a_charge := cos(a.heading) * nx + sin(a.heading) * ny
			var b_charge := cos(b.heading) * (-nx) + sin(b.heading) * (-ny)
			if a_charge >= C.head_on_cos and b_charge >= C.head_on_cos:
				# Head-on: length decides; equal length is mutual destruction.
				if a.body.size() == b.body.size():
					if C.even_length_both_die:
						if a.is_player or b.is_player:
							var ph: Vector2 = ha if a.is_player else hb
							events.push_text(ph.x, ph.y - 80.0, "同归于尽", Color("FFC53D"), 44.0)
						kill_snake(a, null)
						kill_snake(b, null)
				else:
					var winner = a if a.body.size() > b.body.size() else b
					var loser = b if winner == a else a
					head_on_eat(winner, loser)
			else:
				# Side-on: the one that charged harder is the one that dies.
				var victim = a if a_charge > b_charge else b
				var survivor = b if victim == a else a
				kill_snake(victim, survivor)
			j += 1
		i += 1

	# ---- 3. head vs another snake's body ----
	# The hit radius is slightly smaller than the visual radius (a little
	# forgiveness), and scales with the *other* snake's girth.
	i = 0
	while i < n:
		var s = snakes[i]
		i += 1
		if not s.alive or s.is_immune():
			continue
		var h: Vector2 = s.body[0]
		var k := 0
		while k < n:
			var other = snakes[k]
			k += 1
			if other == s or not other.alive:
				continue
			var other_r: float = other.radius()
			# Already inside the head-vs-head circle: that pair is decided above.
			var zone_r: float = other_r * C.head_radius
			var oh: Vector2 = other.body[0]
			var zx := h.x - oh.x
			var zy := h.y - oh.y
			if zx * zx + zy * zy < zone_r * zone_r:
				continue
			var body_r: float = other_r * 0.78
			var body_r2 := body_r * body_r
			var b: PackedVector2Array = other.body
			var m := b.size()
			var q := 2
			var hit := false
			while q < m:
				var ddx := h.x - b[q].x
				var ddy := h.y - b[q].y
				if ddx * ddx + ddy * ddy < body_r2:
					hit = true
					break
				q += 1
			if hit:
				kill_snake(s, other)
			if not s.alive:
				break


## Head-on with a length difference: the longer snake eats the shorter.
func head_on_eat(winner, loser) -> void:
	# All accounting/growth goes through kill_snake -> reward_kill so side-on
	# kills, head-on absorbs and "made them crash into my body" all pay the same.
	kill_snake(loser, winner, true)


## Credit a kill and grow the winner (JS `rewardKill`).
func reward_kill(winner, loser_len: int, eaten: bool) -> void:
	var K = cfg.snake.kill_reward
	var gain := 0
	if K.enabled:
		gain = clampi(roundi(float(loser_len) * K.absorb), int(K.min_gain), int(K.max_gain))
	else:
		gain = cfg.snake.grow_per_kill
	if winner.is_player:
		gain = roundi(float(gain) * K.player_mul)
	else:
		gain = maxi(1, roundi(float(gain) * K.ai_mul))

	winner.grow(gain)
	winner.kills += 1
	if winner.pulse.size() > 0:
		winner.pulse[0] = 1.5
	# Short immunity after an absorb so the winner is not instantly killed too.
	winner.immune_until = time + (K.immunity_ms * 0.001 if K.enabled else 0.5)

	if winner.is_player:
		score += 150
		kills += 1
		if eaten:
			var wh: Vector2 = winner.body[0]
			events.push_text(wh.x, wh.y - 70.0, "吞并！", Color("B6FF57"), 56.0)


## Kill a snake: scatter its body into food, start the respawn timer, credit the
## killer (if any) and publish the death event.
func kill_snake(snake, killer, eaten: bool = false) -> void:
	if not snake.alive:
		return
	# The loser's length must be read before the body is cleared.
	var loser_len: int = snake.body.size()
	snake.alive = false
	snake.respawn_timer = cfg.player.respawn_delay if snake.is_player else cfg.ai.respawn_delay

	# ---- body -> food ----
	var step: int = snake.scatter_step(cfg.food.scatter_max)
	var body: PackedVector2Array = snake.body
	var i := 0
	while i < body.size():
		foods.append(make_food(body[i].x, body[i].y, false, snake.color, true))
		i += step

	# ---- presentation event (snapshot the corpse before the body is cleared) ----
	var head: Vector2 = snake.body[0] if snake.body.size() > 0 else Vector2.ZERO
	var pts: PackedVector2Array = snake.body.duplicate()
	events.push_death(head.x, head.y, snake.color, snake.is_player,
		killer != null and killer.is_player and not snake.is_player, snake.id, pts)

	snake.deaths += 1
	if snake.is_player:
		deaths += 1
		var msg := "被吃掉了" if killer != null else "阵亡"
		events.push_text(head.x, head.y - 90.0, msg, Color("FF5C7A"), 44.0)
	elif killer != null and killer.is_player and not eaten:
		events.push_text(head.x, head.y - 60.0, "击杀", Color("B6FF57"), 34.0)

	# ---- unified kill accounting ----
	# Wall / (legacy) self / mutual destruction pass killer = null and pay nothing.
	# With the default `collide.self_kill == false`, this function is never reached
	# for a head-vs-own-body overlap at all, so such an overlap cannot score,
	# grant immunity, start a respawn timer or emit an event.
	if killer != null and killer != snake and killer.alive:
		reward_kill(killer, loser_len, eaten)

	snake.body.resize(0)
	snake.pulse.resize(0)
	snake.has_look_at = false


## Human respawn: back to the starting length somewhere far away, with freeze.
func respawn_player(snake = null) -> void:
	if snake == null:
		snake = player
	var p := spawn_point(1100.0)
	snake.reset(p.x, p.y, inward_heading(p.x, p.y), cfg.snake.start_segments)
	snake.immune_until = time + cfg.player.immunity
	apply_spawn_freeze(snake)
	if snake.player_index >= 0 and snake.player_index < cam_targets.size():
		cam_targets[snake.player_index] = p
	events.push_text(p.x, p.y - 80.0, "复活", snake.color, 48.0)


## AI respawn: same rules, slightly shorter immunity, fresh decision state.
func respawn_ai(snake) -> void:
	var p := spawn_point(1200.0)
	snake.reset(p.x, p.y, inward_heading(p.x, p.y), cfg.snake.start_segments)
	snake.immune_until = time + 0.9
	apply_spawn_freeze(snake)
	var i := 0
	while i < brains.size():
		if brains[i].snake == snake:
			brains[i].reset_for_new_round()
			break
		i += 1


# ---------------------------------------------------------------- powerups

## Powerup-specific RNG (xorshift32; never shares the world stream).
func powerup_random() -> float:
	return powerup_rng.randf()


func make_powerup(x: float, y: float, type: StringName):
	var p = PSPowerup.new()
	var color: Color = cfg.powerups.boost.color if type == &"boost" else cfg.powerups.magnet.color
	var label: String = cfg.powerups.boost.label if type == &"boost" else cfg.powerups.magnet.label
	p.setup(x, y, type, cfg.powerups.radius, color, label, powerup_random() * 100.0)
	return p


## Random position at least `min_dist_from_snake` away from every living snake.
func random_powerup_pos() -> Vector2:
	var P = cfg.powerups
	var m: float = P.spawn_margin
	var min_d2: float = P.min_dist_from_snake * P.min_dist_from_snake
	var t := 0
	while t < 12:
		var x := m + powerup_random() * (world_w - m * 2.0)
		var y := m + powerup_random() * (world_h - m * 2.0)
		var ok := true
		var i := 0
		while i < snakes.size():
			var s = snakes[i]
			i += 1
			if not s.alive or s.body.size() == 0:
				continue
			var h: Vector2 = s.body[0]
			var dx := x - h.x
			var dy := y - h.y
			if dx * dx + dy * dy < min_d2:
				ok = false
				break
		if ok:
			return Vector2(x, y)
		t += 1
	# Fall back to "anywhere inside the world" rather than failing to spawn.
	return Vector2(
		m + powerup_random() * (world_w - m * 2.0),
		m + powerup_random() * (world_h - m * 2.0))


## Random powerup, preferring whichever kind is currently rarer on the field.
func random_powerup():
	var nb := 0
	var nm := 0
	var i := 0
	while i < powerups.size():
		if powerups[i].type == &"boost":
			nb += 1
		else:
			nm += 1
		i += 1
	var type: StringName
	if nb < nm:
		type = &"boost"
	elif nm < nb:
		type = &"magnet"
	else:
		type = &"boost" if powerup_random() < 0.5 else &"magnet"
	var pos := random_powerup_pos()
	return make_powerup(pos.x, pos.y, type)


## Spawn a powerup at a given spot (debug / automation entry point).
func spawn_powerup(type: StringName = &"", x: float = NAN, y: float = NAN):
	var t := type
	if t != &"boost" and t != &"magnet":
		t = &"boost" if powerup_random() < 0.5 else &"magnet"
	var pos := Vector2.ZERO
	if is_finite(x) and is_finite(y):
		pos = Vector2(x, y)
	else:
		pos = random_powerup_pos()
	var p = make_powerup(pos.x, pos.y, t)
	powerups.append(p)
	return p


## One replacement every `powerups.spawn_sec` while below the target count.
func ensure_powerups(real_dt: float) -> void:
	var P = cfg.powerups
	if not P.enabled:
		return
	if powerups.size() >= P.target_count:
		powerup_spawn_timer = P.spawn_sec
		return
	powerup_spawn_timer -= real_dt
	if powerup_spawn_timer > 0.0:
		return
	powerup_spawn_timer = P.spawn_sec
	powerups.append(random_powerup())


## Pick up at most one powerup per snake per frame while the head touches it.
func collect_powerups() -> void:
	var P = cfg.powerups
	if not P.enabled or powerups.size() == 0:
		return
	var i := 0
	while i < snakes.size():
		var s = snakes[i]
		i += 1
		if not s.alive or s.is_frozen():
			continue
		if not s.is_player and not P.ai_can_pickup:
			continue
		if s.body.size() == 0:
			continue
		var hit: float = s.radius() + P.pickup_radius
		var hit2 := hit * hit
		var h: Vector2 = s.body[0]
		var j := powerups.size() - 1
		while j >= 0:
			var p = powerups[j]
			var dx: float = h.x - p.x
			var dy: float = h.y - p.y
			if dx * dx + dy * dy > hit2:
				j -= 1
				continue
			var dur: float = P.boost.duration_sec if p.type == &"boost" else P.magnet.duration_sec
			s.apply_buff(p.buff_index(), dur)
			events.push_powerup(p.x, p.y, p.color, s.is_player, s.id, p.type,
				"%s %ss" % [p.label, dur])
			# O(1) removal; loop is descending so we can stop after one pickup.
			powerups[j] = powerups[powerups.size() - 1]
			powerups.pop_back()
			break


## Magnet: pull nearby pellets towards the head. A pellet is claimed by at most
## one snake per frame (same as the JS `magnetClaimed` set, via a frame stamp).
func apply_magnets(dt: float) -> void:
	var P = cfg.powerups
	if not P.enabled or dt <= 0.0:
		return
	var M = P.magnet
	var r2: float = M.radius * M.radius
	var i := 0
	while i < snakes.size():
		var s = snakes[i]
		i += 1
		if not s.alive or s.is_frozen() or not s.has_buff(PSSnake.BUFF_MAGNET):
			continue
		if s.body.size() == 0:
			continue
		var h: Vector2 = s.body[0]
		var j := 0
		var n := foods.size()
		while j < n:
			var f = foods[j]
			j += 1
			if f.claimed_frame == _frame_id:
				continue
			var dx: float = h.x - f.x
			var dy: float = h.y - f.y
			var d2 := dx * dx + dy * dy
			if d2 > r2 or d2 < 1.0:
				continue
			f.claimed_frame = _frame_id
			var d := sqrt(d2)
			# Closer pellets are pulled faster; 55% floor at the rim.
			var pull: float = M.pull_speed * (0.55 + 0.45 * (1.0 - d / M.radius))
			var step: float = minf(d, pull * dt)
			f.x += (dx / d) * step
			f.y += (dy / d) * step


# ---------------------------------------------------------------- food

## Create a pellet. `color == PSConfig.NO_COLOR` means "pick from the palette"
## (matching the JS `color || (...)` short-circuit and its RNG draw order).
func make_food(x: float, y: float, big: bool, color: Color = Color(-1.0, -1.0, -1.0, -1.0),
		scattered: bool = false):
	var f = PSFood.new()
	var c := color
	if c.r < 0.0:
		if big:
			c = Color("FFC53D")
		else:
			c = _food_colors[int(rng.randf() * float(_food_colors.size()))]
	var face: StringName
	if big:
		face = &"wide"
	else:
		face = _food_faces[int(rng.randf() * float(_food_faces.size()))]
	var r: float = cfg.food.radius * (1.22 if big else 1.0)
	f.setup(x, y, r, big, c, face, rng.randf() * 100.0, scattered)
	return f


## Random pellet position: inside the margin, away from every snake body sample.
func random_food():
	var m: float = cfg.food.spawn_margin
	var min_d2: float = cfg.food.min_dist_from_snake * cfg.food.min_dist_from_snake
	var t := 0
	while t < 10:
		var x := rng.rand_range(m, world_w - m)
		var y := rng.rand_range(m, world_h - m)
		var ok := true
		var i := 0
		while i < hazard_count:
			var hz := hazards[i]
			var dx := x - hz.x
			var dy := y - hz.y
			if dx * dx + dy * dy < min_d2:
				ok = false
				break
			i += 1
		if ok:
			return make_food(x, y, rng.randf() < cfg.food.big_chance)
		t += 1
	# Give up on the distance check (it will be eaten soon anyway).
	return make_food(rng.rand_range(m, world_w - m), rng.rand_range(m, world_h - m), false)


## Eat pellets whose radius overlaps a head. Frozen snakes do not eat.
func eat_food() -> void:
	var pr: float = cfg.compute_ai_pressure(tuning.ai_level, tuning.ai_pressure)
	var i := 0
	while i < snakes.size():
		var s = snakes[i]
		i += 1
		if not s.alive or s.is_frozen():
			continue
		if s.body.size() == 0:
			continue
		var h: Vector2 = s.body[0]
		var R: float = s.radius()
		var j := foods.size() - 1
		while j >= 0:
			var f: PSFood = foods[j]
			var eaten := false
			# Cheap bounding-box pre-filter, then the exact circle test.
			if absf(f.x - h.x) <= 90.0 and absf(f.y - h.y) <= 90.0:
				var hit_r: float = R + f.r * cfg.food.eat_padding
				var dx := h.x - f.x
				var dy := h.y - f.y
				if dx * dx + dy * dy <= hit_r * hit_r:
					var grow_n: int = cfg.snake.grow_per_big_food if f.big else cfg.snake.grow_per_food
					if s.is_player:
						# Humans keep the legacy integer growth exactly.
						s.grow(grow_n)
					else:
						# Pressured AI grows less from pellets, more from hunting.
						var mul: float = 1.0 - (1.0 - cfg.ai.food_mul) * pr
						s.grow_fractional(float(grow_n) * mul)
						# AI leader catch-up: only above the player's length, only
						# while pressure is active, banked fractionally.
						var L = cfg.ai.leader
						if L.enabled and pr > 0.0:
							var base: float = maxf(float(player.body.size()),
								float(cfg.snake.start_segments))
							var edge: float = clampf(
								(float(s.body.size()) - base) / L.edge_scale, 0.0, 1.0)
							s.grow_fractional(L.max_bonus * pr * edge)
					if s.pulse.size() > 0:
						s.pulse[0] = 1.3
					s.food_eaten += 1
					stat_food_eaten += 1
					if s.is_player:
						score += 30 if f.big else 10
					events.push_food(f.x, f.y, f.color, f.big, f.r, s.is_player, s.id)
					eaten = true
			if eaten:
				foods[j] = foods[foods.size() - 1]
				foods.pop_back()
				var bi := 0
				while bi < brains.size():
					brains[bi].forget_target(f)
					bi += 1
			j -= 1


## Keep the food count near `food.target_count`, with a paced refill.
##   * below target: at most one batch of `spawn_per_frame` per cooldown
##   * far above target (mass deaths): drop the pellet farthest from the camera
func ensure_food(dt: float) -> void:
	var F = cfg.food
	food_spawn_cd = maxf(0.0, food_spawn_cd - dt)

	if foods.size() < F.target_count:
		if food_spawn_cd > 0.0:
			return
		var n := mini(F.spawn_per_frame, F.target_count - foods.size())
		var k := 0
		while k < n:
			foods.append(random_food())
			k += 1
		stat_food_spawned += n
		if n > stat_food_max_batch:
			stat_food_max_batch = n
		food_spawn_cd = F.spawn_cooldown_sec
		return

	if foods.size() > F.target_count + F.trim_extra:
		var far_idx := -1
		var far_d2 := -1.0
		var i := 0
		while i < foods.size():
			var d2 := PSMath.dist2(foods[i].x, foods[i].y, cam_target.x, cam_target.y)
			if d2 > far_d2:
				far_d2 = d2
				far_idx = i
			i += 1
		if far_idx >= 0:
			var removed = foods[far_idx]
			foods[far_idx] = foods[foods.size() - 1]
			foods.pop_back()
			stat_food_trimmed += 1
			# Port deviation: drop AI references to the trimmed pellet. The JS code
			# left them dangling, so an AI could chase an invisible pellet for up to
			# one retarget interval. Behaviour is otherwise identical.
			var bi := 0
			while bi < brains.size():
				brains[bi].forget_target(removed)
				bi += 1


# ---------------------------------------------------------------- spawn helper

## Random point at least `min_dist` from every living snake's head.
func spawn_point(min_dist: float) -> Vector2:
	var min_d2 := min_dist * min_dist
	var m := 280.0
	var t := 0
	while t < 50:
		var x := rng.rand_range(m, world_w - m)
		var y := rng.rand_range(m, world_h - m)
		var ok := true
		var i := 0
		while i < snakes.size():
			var s = snakes[i]
			i += 1
			if not s.alive or s.body.size() == 0:
				continue
			var h: Vector2 = s.body[0]
			var dx := x - h.x
			var dy := y - h.y
			if dx * dx + dy * dy < min_d2:
				ok = false
				break
		if ok:
			return Vector2(x, y)
		t += 1
	# Fallback: somewhere near the middle of the world.
	return Vector2(
		clampf(world_w * 0.5 + rng.rand_range(-300.0, 300.0), m, world_w - m),
		clampf(world_h * 0.5 + rng.rand_range(-300.0, 300.0), m, world_h - m))


# ---------------------------------------------------------------- ranking

## True when `a` must be placed before `b` (same order as the JS comparator).
static func _rank_before(a, b) -> bool:
	if a.length != b.length:
		return a.length > b.length
	if a.deaths != b.deaths:
		return a.deaths < b.deaths
	if a.kills != b.kills:
		return a.kills > b.kills
	if a.peak_length != b.peak_length:
		return a.peak_length > b.peak_length
	return a.id < b.id


## Sorted snapshot of the 8 players (allocation happens here only, never in update).
## A snake that is mid-respawn counts as length 0, exactly like the JS game.
func rank_snapshot() -> Array:
	var rows: Array = []
	var i := 0
	while i < snakes.size():
		var s = snakes[i]
		i += 1
		var row = PSRankRow.new()
		row.id = s.id
		row.name = s.display_name
		row.is_player = s.is_player
		row.player_index = s.player_index
		row.color = s.color
		row.style = s.style_label
		row.head_style = s.head_style
		row.length = s.body.size() if s.alive else 0
		row.peak_length = s.peak_length
		row.kills = s.kills
		row.deaths = s.deaths
		row.food_eaten = s.food_eaten
		rows.append(row)
	# Insertion sort: 8 rows, no Callable allocation, deterministic order.
	var n := rows.size()
	var a := 1
	while a < n:
		var key = rows[a]
		var b := a - 1
		while b >= 0 and _rank_before(key, rows[b]):
			rows[b + 1] = rows[b]
			b -= 1
		rows[b + 1] = key
		a += 1
	i = 0
	while i < n:
		rows[i].rank = i + 1
		i += 1
	return rows


## Live ranking for the HUD (call at HUD rate, not per gameplay frame).
func live_ranking() -> Array:
	return rank_snapshot()


## Current place of a snake (1..8).
func rank_of(snake) -> int:
	var rows := rank_snapshot()
	var i := 0
	while i < rows.size():
		if rows[i].id == snake.id:
			return rows[i].rank
		i += 1
	return rows.size()


## Place of player 1; after the whistle this is the settled value.
func player_rank() -> int:
	if state == STATE_FINISHED and round_result != null:
		return round_result.player_rank
	return rank_of(player)


## Freeze the world and build the settlement payload (idempotent).
func finish_round() -> void:
	if state == STATE_FINISHED:
		return
	state = STATE_FINISHED
	ranking = rank_snapshot()
	var human_rows: Array = []
	var i := 0
	while i < ranking.size():
		if ranking[i].is_player:
			human_rows.append(ranking[i])
		i += 1
	var me = human_rows[0] if human_rows.size() > 0 else null
	round_result = PSRoundResult.new()
	round_result.total = ranking.size()
	round_result.player_rank = me.rank if me != null else ranking.size()
	round_result.won = me != null and me.rank == 1
	round_result.player = me
	round_result.players = human_rows
	round_result.best_length = best_length
	round_result.mode = cfg.round.mode
	round_result.duration_sec = cfg.round.duration_sec
	round_result.ranking = ranking


# ---------------------------------------------------------------- HUD helpers

## True during the last `round.last_call_sec` seconds.
func is_last_call() -> bool:
	if cfg.round.mode != &"timed":
		return false
	return round_left <= cfg.round.last_call_sec and round_left > 0.0


## Seconds until player 1 respawns (0 while alive).
func player_respawn_in() -> float:
	if player == null or player.alive:
		return 0.0
	return maxf(0.0, player.respawn_timer)


## Remaining respawn-freeze seconds for player 1 (0 when not frozen).
func player_freeze_in() -> float:
	if player == null or not player.alive or not player.is_frozen():
		return 0.0
	return maxf(0.0, player.freeze_until - time)


## Number of living AI opponents.
func alive_opponents() -> int:
	var n := 0
	var i := 0
	while i < snakes.size():
		if not snakes[i].is_player and snakes[i].alive:
			n += 1
		i += 1
	return n


## Rebuild the field from scratch (kept for symmetry with the JS API).
func round_seed() -> int:
	return round_rng.state
