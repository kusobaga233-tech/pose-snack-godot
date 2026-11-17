extends RefCounted
## Suite: the food pool (spawn placement, eating, scatter, trim, 2 minute invariants).

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSFood = preload("res://src/core/food.gd")
const PSSnake = preload("res://src/core/snake.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")


static func _fresh(seed_value: int):
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	return PSGame.new(cfg, tuning, seed_value)


## Bare world with exactly one snake, so the food tests are explicit.
static func _one_snake(seed_value: int, segments: int, is_player: bool = true):
	var game = _fresh(seed_value)
	game.brains.clear()
	game.snakes.clear()
	game.players.clear()
	game.foods.clear()
	game.time = 0.0
	var s = PSSnake.new(game.cfg, game.tuning, game.rng)
	s.reset(2400.0, 1350.0, 0.0, segments)
	s.now = 0.0
	s.is_player = is_player
	if is_player:
		game.players.append(s)
		game.player = s
	game.snakes.append(s)
	game.rebuild_hazards()
	return game


static func run(t) -> void:
	t.suite("food")
	var cfg = PSConfig.new()

	# ---- spawn placement --------------------------------------------------
	var game = _fresh(201)
	var m: float = cfg.food.spawn_margin
	var all_inside := true
	var all_finite := true
	var i := 0
	while i < 300:
		var f = game.random_food()
		if f.x < m or f.x > game.world_w - m or f.y < m or f.y > game.world_h - m:
			all_inside = false
		if not (is_finite(f.x) and is_finite(f.y)):
			all_finite = false
		i += 1
	t.ok("300 spawns stay inside the spawn margin", all_inside)
	t.ok("300 spawns are finite", all_finite)
	t.ok("spawns are flagged as not scattered",
		not game.random_food().scattered)

	# ---- min distance from snake bodies ----------------------------------
	game = _one_snake(202, 80)
	var closest := INF
	i = 0
	while i < 200:
		var f = game.random_food()
		var k := 0
		while k < game.hazard_count:
			var d: float = f.x - game.hazards[k].x
			var dy: float = f.y - game.hazards[k].y
			var dist := sqrt(d * d + dy * dy)
			if dist < closest:
				closest = dist
			k += 1
		i += 1
	t.ge("spawns keep min distance from snakes", closest, cfg.food.min_dist_from_snake - 1e-3)

	# ---- eating a normal pellet ------------------------------------------
	game = _one_snake(203, 16)
	var s = game.snakes[0]
	var f2 = game.make_food(s.body[0].x, s.body[0].y, false)
	game.foods.append(f2)
	game.eat_food()
	t.eq_int("eating grows one node", s.length(), 17)
	t.eq_int("eating is counted", s.food_eaten, 1)
	t.eq_int("player score for a pellet", game.score, 10)
	t.eq_float("pellet pulse", s.pulse[0], 1.3, 1e-6)
	t.eq_int("pellet removed from the pool", game.foods.size(), 0)
	t.eq_int("eat counter", game.stat_food_eaten, 1)

	# ---- eating a big pellet ---------------------------------------------
	game = _one_snake(204, 16)
	s = game.snakes[0]
	var big = game.make_food(s.body[0].x, s.body[0].y, true)
	t.eq_float("big pellet radius", big.r, 29.28, 1e-6)
	game.foods.append(big)
	game.eat_food()
	t.eq_int("big pellet grows three", s.length(), 19)
	t.eq_int("big pellet scores thirty", game.score, 30)

	# ---- eat radius uses the padded sum ----------------------------------
	game = _one_snake(205, 16)
	s = game.snakes[0]
	var hit_r: float = s.radius() + cfg.food.radius * cfg.food.eat_padding
	t.eq_float("eat radius", hit_r, 41.68, 1e-6)
	var inside = game.make_food(s.body[0].x + hit_r - 0.5, s.body[0].y, false)
	game.foods.append(inside)
	game.eat_food()
	t.eq_int("pellet just inside the radius is eaten", game.foods.size(), 0)
	var outside = game.make_food(s.body[0].x + hit_r + 0.5, s.body[0].y, false)
	game.foods.append(outside)
	game.eat_food()
	t.eq_int("pellet just outside the radius survives", game.foods.size(), 1)

	# ---- frozen snakes do not eat ----------------------------------------
	game = _one_snake(206, 16)
	s = game.snakes[0]
	s.freeze_until = 5.0
	game.foods.append(game.make_food(s.body[0].x, s.body[0].y, false))
	game.eat_food()
	t.eq_int("frozen snake does not eat", s.length(), 16)
	t.eq_int("frozen snake keeps the pellet", game.foods.size(), 1)

	# ---- death scatter ---------------------------------------------------
	game = _one_snake(207, 30)
	s = game.snakes[0]
	game.kill_snake(s, null)
	t.eq_int("corpse scatters one pellet per node", game.foods.size(), 30)
	var all_scattered := true
	var same_colour := true
	var all_finite2 := true
	i = 0
	while i < game.foods.size():
		var p = game.foods[i]
		i += 1
		if not p.scattered:
			all_scattered = false
		if p.color != s.color:
			same_colour = false
		if not (is_finite(p.x) and is_finite(p.y)):
			all_finite2 = false
	t.ok("scattered pellets flagged", all_scattered)
	t.ok("scattered pellets keep the snake colour", same_colour)
	t.ok("scattered pellets are finite", all_finite2)

	# ---- scatter respects scatter_max ------------------------------------
	game = _one_snake(208, 200)
	s = game.snakes[0]
	game.kill_snake(s, null)
	t.le("scatter count capped", float(game.foods.size()), float(cfg.food.scatter_max))

	# ---- trim drops the pellet farthest from the camera ------------------
	game = _fresh(209)
	game.foods.clear()
	game.cam_target = Vector2(0.0, 0.0)
	i = 0
	while i < cfg.food.target_count + cfg.food.trim_extra + 1:
		game.foods.append(game.make_food(100.0 + float(i), 100.0, false))
		i += 1
	var far_one = game.make_food(4700.0, 2600.0, false)
	game.foods.append(far_one)
	var before_trim: int = game.foods.size()
	game.ensure_food(0.0)
	t.eq_int("trim removes exactly one", game.foods.size(), before_trim - 1)
	var still_there := false
	i = 0
	while i < game.foods.size():
		if game.foods[i] == far_one:
			still_there = true
		i += 1
	t.ok("trim removed the farthest pellet", not still_there)
	t.eq_int("trim counter", game.stat_food_trimmed, 1)
	# ... one pellet per call, not a full sweep
	game.ensure_food(0.0)
	t.eq_int("second call trims another", game.stat_food_trimmed, 2)
	game.ensure_food(0.0)
	t.eq_int("no trim once back at the threshold", game.stat_food_trimmed, 2)

	# ---- spawn pacing ----------------------------------------------------
	game = _fresh(210)
	game.foods.clear()
	game.food_spawn_cd = 0.0
	game.ensure_food(0.0)
	t.eq_int("refill batch size", game.foods.size(), cfg.food.spawn_per_frame)
	game.ensure_food(0.05)
	t.eq_int("cooldown blocks the next batch", game.foods.size(), cfg.food.spawn_per_frame)
	game.ensure_food(cfg.food.spawn_cooldown_sec)
	t.eq_int("next batch after the cooldown", game.foods.size(), cfg.food.spawn_per_frame * 2)

	# ---- two simulated minutes of food churn -----------------------------
	game = _fresh(211)
	var steer = PSSteerInput.new()
	game.start()
	var target: int = cfg.food.target_count
	var hard_cap: int = target + cfg.food.trim_extra + 8 * cfg.food.scatter_max
	var worst_low := 1 << 30
	var worst_high := 0
	var count_sum := 0
	var count_samples := 0
	var nan_food := false
	var frames := 0
	var sample_every := 6
	while frames < 7300 and game.state == PSGame.STATE_PLAYING:
		steer.set_keyboard(sin(float(frames) * 0.017) * 1.1)
		game.update(1.0 / 60.0, steer, 1.0 / 60.0)
		frames += 1
		if frames % sample_every == 0:
			var c: int = game.foods.size()
			if c < worst_low:
				worst_low = c
			if c > worst_high:
				worst_high = c
			count_sum += c
			count_samples += 1
			var k := 0
			while k < game.foods.size():
				var p = game.foods[k]
				if not (is_finite(p.x) and is_finite(p.y)):
					nan_food = true
				k += 1
	t.ok("round finished during the food run", game.state == PSGame.STATE_FINISHED)
	t.gt("food never emptied out", float(worst_low), 0.0)
	t.le("food count stays under the hard cap", float(worst_high), float(hard_cap))
	t.le("average food density stays near target",
		float(count_sum) / float(maxi(1, count_samples)), float(target + cfg.food.trim_extra))
	t.ok("no NaN food positions", not nan_food)
	t.le("refill batches honour spawn_per_frame",
		float(game.stat_food_max_batch), float(cfg.food.spawn_per_frame))
	t.gt("food was spawned continuously", float(game.stat_food_spawned), 100.0)
	t.gt("food was eaten continuously", float(game.stat_food_eaten), 100.0)
	t.between("final food count back near target", float(game.foods.size()),
		float(target) * 0.5, float(target + cfg.food.trim_extra))

	t.end_suite()
