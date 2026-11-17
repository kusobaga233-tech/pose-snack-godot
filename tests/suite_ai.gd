extends RefCounted
## Suite: the AI brains (no NaN, never stuck outside the world, respawn, difficulty).

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")
const PSBrain = preload("res://src/core/brain.gd")


static func run(t) -> void:
	t.suite("ai")

	# ---- 60 simulated seconds of 7 AI brains ------------------------------
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	var game = PSGame.new(cfg, tuning, 401)
	var steer = PSSteerInput.new()
	steer.set_keyboard(0.0)
	game.start()
	var pad: float = cfg.snake.wall_pad
	var world_w: float = game.world_w
	var world_h: float = game.world_h
	var dt := 1.0 / 60.0

	var nan_seen := false
	var inside_violations := 0
	var outside_time := {}
	var had_target := false
	var max_ai_len := 0
	var ai_food := 0
	var frames := 0
	while frames < 3600:
		game.update(dt, steer, dt)
		frames += 1
		var i := 0
		while i < game.snakes.size():
			var s = game.snakes[i]
			i += 1
			if not (is_finite(s.heading) and is_finite(s.speed)):
				nan_seen = true
			if not s.is_player and s.alive:
				if s.body.size() > 0 and s.body.size() > max_ai_len:
					max_ai_len = s.body.size()
			if not s.alive:
				continue
			if s.body.size() == 0:
				nan_seen = true
				continue
			var h: Vector2 = s.body[0]
			if not (is_finite(h.x) and is_finite(h.y)):
				nan_seen = true
				continue
			var inside := h.x >= pad - 0.01 and h.x <= world_w - pad + 0.01 \
				and h.y >= pad - 0.01 and h.y <= world_h - pad + 0.01
			if not inside:
				outside_time[s.id] = outside_time.get(s.id, 0.0) + dt
			else:
				outside_time[s.id] = 0.0
			# A living, non-immune snake must be inside the playfield: the wall
			# check runs every frame, immunity is the only reason to be outside.
			if not inside and not s.is_immune():
				inside_violations += 1
		if frames % 30 == 0:
			var b := 0
			while b < game.brains.size():
				if game.brains[b].target != null:
					had_target = true
				b += 1
	var worst_outside := 0.0
	for key in outside_time:
		if outside_time[key] > worst_outside:
			worst_outside = outside_time[key]
	var ai: Array = []
	var k := 0
	while k < game.snakes.size():
		if not game.snakes[k].is_player:
			ai.append(game.snakes[k])
			ai_food += game.snakes[k].food_eaten
		k += 1

	t.ok("no NaN in AI state", not nan_seen)
	t.eq_int("alive non-immune snakes stay inside the world", inside_violations, 0)
	t.lt("no snake stays outside the world for long", worst_outside, 2.5)
	t.eq_int("field still holds 7 AI", ai.size(), 7)
	t.gt("AI ate food", float(ai_food), 0.0)
	t.gt("AI grew past the starting length", float(max_ai_len), 16.0)
	t.ok("AI locked onto food at least once", had_target)
	t.eq_int("round keeps playing", game.state, PSGame.STATE_PLAYING)

	# ---- brains keep their own personality / skill ------------------------
	var skill_ok := true
	var styles_ok := true
	var head_styles: Array = []
	k = 0
	while k < game.brains.size():
		var brain = game.brains[k]
		if brain.skill < cfg.ai.skill_min - 1e-9 or brain.skill > cfg.ai.skill_max + 1e-9:
			skill_ok = false
		if brain.style == null or brain.style.label == "":
			styles_ok = false
		k += 1
	k = 0
	while k < game.snakes.size():
		if not game.snakes[k].is_player:
			head_styles.append(game.snakes[k].head_style)
		k += 1
	t.ok("skills inside the configured range", skill_ok)
	t.ok("every AI got a personality", styles_ok)
	var unique_heads: Array = []
	for hs in head_styles:
		if not unique_heads.has(hs):
			unique_heads.append(hs)
	t.eq_int("head styles are unique per round", unique_heads.size(), 7)

	# ---- difficulty slider scales the turn ability ------------------------
	var brain = game.brains[0]
	var s0 = brain.snake
	# Force a normal decision frame (no freeze, no lapse, no reaction hold).
	s0.freeze_until = 0.0
	brain.lapse_until = 0.0
	brain.next_lapse_at = 1.0e9
	brain.has_last_control = false
	tuning.ai_level = 0.5
	brain.think(game, dt, game.time)
	t.eq_float("level 0.5 turn factor", brain.turn_factor(0.5), 0.67, 1e-9)
	t.eq_float("turn_mul at level 0.5", s0.turn_mul, brain.skill * 0.67, 1e-9)
	tuning.ai_level = 1.0
	brain.think(game, dt, game.time)
	t.eq_float("turn_mul at level 1.0", s0.turn_mul, brain.skill, 1e-9)
	tuning.ai_level = 0.85
	brain.think(game, dt, game.time)
	t.eq_float("turn_mul back at the default", s0.turn_mul, brain.skill * 0.901, 1e-9)

	# ---- respawn ---------------------------------------------------------
	game = PSGame.new(cfg, tuning, 402)
	game.start()
	var victim = null
	k = 0
	while k < game.snakes.size():
		if not game.snakes[k].is_player:
			victim = game.snakes[k]
			break
		k += 1
	t.ok("found an AI to kill", victim != null)
	game.kill_snake(victim, null)
	t.ok("killed AI is dead", not victim.alive)
	t.eq_float("AI respawn delay", victim.respawn_timer, 3.0)
	frames = 0
	while frames < 200:
		game.update(dt, steer, dt)
		frames += 1
	t.ok("AI respawns after 3 s", victim.alive)
	t.eq_int("AI respawns at the starting length", victim.length(), 16)
	t.ok("respawned AI is protected", victim.is_immune() or victim.is_frozen())
	t.eq_int("respawn keeps the death count", victim.deaths, 1)

	# ---- low-end profile still simulates --------------------------------
	var low_cfg = PSConfig.new()
	low_cfg.apply_device_profile(PSConfig.PROFILE_LOW_END)
	var low_tuning = PSRuntimeTuning.new(low_cfg)
	var low_game = PSGame.new(low_cfg, low_tuning, 403)
	low_game.start()
	t.eq_int("low-end food count", low_game.foods.size(), 120)
	frames = 0
	while frames < 600:
		low_game.update(dt, steer, dt)
		frames += 1
	t.eq_float("low-end round still running", low_game.time, 10.0, 1e-6)
	var low_nan := false
	k = 0
	while k < low_game.snakes.size():
		var ls = low_game.snakes[k]
		k += 1
		if not (is_finite(ls.heading) and is_finite(ls.speed)):
			low_nan = true
	t.ok("low-end profile has no NaN", not low_nan)

	t.end_suite()
