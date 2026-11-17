extends RefCounted
## Suite: collision arbitration, kill rewards and death scatter.
##
## Every case builds a bare world (no AI, no food) so the only thing happening is
## the collision pass being tested.
##
## Rule under test (2026-11-12): a head touching its OWN body is a no-op unless
## `cfg.collide.self_kill` is switched on; enemy collisions are unchanged.

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSSnake = preload("res://src/core/snake.gd")
const SnakeControl = preload("res://src/core/snake_control.gd")


## Empty world: no brains, no snakes, no food, clock parked at 10 s.
static func _fresh(seed_value: int):
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	var game = PSGame.new(cfg, tuning, seed_value)
	game.brains.clear()
	game.snakes.clear()
	game.players.clear()
	game.foods.clear()
	game.powerups.clear()
	game.time = 10.0
	return game


static func _spawn(game, x: float, y: float, heading: float, segments: int,
		is_player: bool = false):
	var s = PSSnake.new(game.cfg, game.tuning, game.rng)
	s.reset(x, y, heading, segments)
	s.now = game.time
	s.is_player = is_player
	if is_player:
		s.player_index = 0
		game.players.append(s)
		game.player = s
	game.snakes.append(s)
	return s


static func run(t) -> void:
	t.suite("collisions")

	# ---- head hits the wall ----------------------------------------------
	var game = _fresh(101)
	var s = _spawn(game, 100.0, 1000.0, -PI * 0.5, 16, true)
	s.body[0] = Vector2(5.0, 1000.0)
	var foods_before: int = game.foods.size()
	game.resolve_collisions()
	t.ok("wall death", not s.alive)
	t.eq_float("wall death respawn timer", s.respawn_timer, 3.0)
	t.eq_int("wall death counts as a death", s.deaths, 1)
	t.ok("wall death scatters food", game.foods.size() > foods_before)
	t.eq_int("wall death scatters one pellet per node", game.foods.size() - foods_before, 16)
	t.eq_int("wall death credits nobody", s.kills, 0)
	t.ok("no body left behind", s.body.size() == 0)

	# ---- head vs its own body: harmless overlap (port rule) --------------
	# `cfg.collide.self_kill` defaults to false, so the head simply overlaps its
	# own body. Nothing may change: not the pose, the length, the scoreboard, the
	# respawn timer, the immunity window, the food pool or the event queue.
	game = _fresh(201)
	s = _spawn(game, 1000.0, 1000.0, 0.0, 40, true)
	var head_before: Vector2 = s.body[0]
	var heading_before: float = s.heading
	var immune_before: float = s.immune_until
	var respawn_before: float = s.respawn_timer
	var score_before: int = game.score
	var self_foods_before: int = game.foods.size()
	s.body[10] = s.body[0]
	t.ok("precondition: the head really is inside its own body", s.hit_self())
	game.resolve_collisions()
	t.ok("self collision no longer kills", s.alive)
	t.eq_float("self collision does not move the head (x)", s.body[0].x, head_before.x, 0.0)
	t.eq_float("self collision does not move the head (y)", s.body[0].y, head_before.y, 0.0)
	t.eq_float("self collision does not turn the heading", s.heading, heading_before, 0.0)
	t.eq_int("self collision is not a death", s.deaths, 0)
	t.eq_int("self collision credits nobody", s.kills, 0)
	t.eq_int("self collision leaves the length alone", s.length(), 40)
	t.eq_int("self collision does not score", game.score, score_before)
	t.eq_int("self collision does not scatter a corpse", game.foods.size(), self_foods_before)
	t.eq_float("self collision leaves the respawn timer alone", s.respawn_timer, respawn_before, 0.0)
	t.eq_float("self collision grants no immunity", s.immune_until, immune_before, 0.0)
	t.eq_int("self collision publishes no event", game.events.size(), 0)

	# ---- prolonged overlap: 600 frames buried in the body -----------------
	game = _fresh(202)
	s = _spawn(game, 1000.0, 1000.0, 0.0, 60, true)
	self_foods_before = game.foods.size()
	score_before = game.score
	immune_before = s.immune_until
	var overlap_frames := 0
	var overlap_hit_frames := 0
	var overlap_alive := true
	var overlap_nan := false
	while overlap_frames < 600:
		# Pin the head onto two of its own body nodes every frame.
		s.body[20] = s.body[0]
		s.body[35] = s.body[0] + Vector2(6.0, 0.0)
		if s.hit_self():
			overlap_hit_frames += 1
		game.resolve_collisions()
		if not s.alive:
			overlap_alive = false
			break
		if not (is_finite(s.body[0].x) and is_finite(s.body[0].y)
				and is_finite(s.heading) and is_finite(s.speed)):
			overlap_nan = true
		overlap_frames += 1
	t.ok("600 frames of self overlap never kill", overlap_alive)
	t.eq_int("the prolonged overlap ran to the end", overlap_frames, 600)
	t.eq_int("the head was inside the body on every frame", overlap_hit_frames, 600)
	t.ok("prolonged overlap produces no NaN", not overlap_nan)
	t.eq_int("prolonged overlap keeps the length", s.length(), 60)
	t.eq_int("prolonged overlap keeps the death count", s.deaths, 0)
	t.eq_int("prolonged overlap keeps the kill count", s.kills, 0)
	t.eq_int("prolonged overlap keeps the score", game.score, score_before)
	t.eq_int("prolonged overlap keeps the food pool", game.foods.size(), self_foods_before)
	t.eq_float("prolonged overlap keeps the respawn timer", s.respawn_timer, 0.0, 0.0)
	t.eq_float("prolonged overlap grants no immunity", s.immune_until, immune_before, 0.0)
	t.eq_int("prolonged overlap publishes no event", game.events.size(), 0)

	# ---- a snake that curls tightly survives a full loop ------------------
	# A constant 0.6 rad target offset keeps the turn saturated every frame, so the
	# snake drives loop after loop through the same patch of world.
	# The turn rate is set to 2.2 rad/s, just above the `turn.rate_min` = 2.0
	# slider floor: at the shipped 8.5 rad/s the head turns a ~28 px circle while
	# the 18 px body links cut the corner so hard that the head orbits *inside* its
	# own coil and never reaches the body (measured nearest node: 52-72 px). At
	# 2.2 rad/s the loop is ~110 px wide, the body tracks it, and the head genuinely
	# crosses its own body -- the "can I loop my own tail?" case a player hits.
	game = _fresh(203)
	game.tuning.turn_rate = 2.2
	s = _spawn(game, 2400.0, 1350.0, 0.0, 90, true)
	self_foods_before = game.foods.size()
	score_before = game.score
	var ctrl = SnakeControl.new()
	var curl_frames := 0
	var curl_hit_frames := 0
	var curl_alive := true
	var curl_nan := false
	var head_min := Vector2(INF, INF)
	var head_max := Vector2(-INF, -INF)
	while curl_frames < 900:
		ctrl.set_player(s.heading + 0.6, 1.0)
		s.update(1.0 / 60.0, ctrl)
		if s.hit_self():
			curl_hit_frames += 1
		game.resolve_collisions()
		if not s.alive:
			curl_alive = false
			break
		var ch: Vector2 = s.body[0]
		if not (is_finite(ch.x) and is_finite(ch.y) and is_finite(s.heading)):
			curl_nan = true
			break
		head_min.x = minf(head_min.x, ch.x)
		head_min.y = minf(head_min.y, ch.y)
		head_max.x = maxf(head_max.x, ch.x)
		head_max.y = maxf(head_max.y, ch.y)
		curl_frames += 1
	var curl_span: float = maxf(head_max.x - head_min.x, head_max.y - head_min.y)
	t.ok("the tight curl really crosses its own body", curl_hit_frames > 40)
	t.ok("the tight curl survives 15 s (5+ loops)", curl_alive and curl_frames == 900)
	t.ok("the curl produces no NaN", not curl_nan)
	t.lt("the curl stays a tight circle (no runaway)", curl_span, 400.0)
	t.eq_int("the curl keeps the length", s.length(), 90)
	t.eq_int("the curl keeps the death count", s.deaths, 0)
	t.eq_int("the curl does not score", game.score, score_before)
	t.eq_int("the curl keeps the food pool", game.foods.size(), self_foods_before)
	t.ok("the curl stays inside the world", not s.hit_wall())

	# ---- the legacy rule stays reachable through the config flag ----------
	game = _fresh(204)
	game.cfg.collide.self_kill = true
	s = _spawn(game, 1000.0, 1000.0, 0.0, 40, true)
	s.body[10] = s.body[0]
	game.resolve_collisions()
	t.ok("self_kill = true restores the prototype self-death", not s.alive)
	t.eq_int("legacy self death counts as one death", s.deaths, 1)
	t.eq_int("legacy self death credits nobody", s.kills, 0)
	t.eq_float("legacy self death starts the respawn timer", s.respawn_timer, 3.0)

	# ... including the AI forgiveness window (skip 12 nodes / 0.45 radius).
	game = _fresh(205)
	game.cfg.collide.self_kill = true
	s = _spawn(game, 1000.0, 1000.0, 0.0, 40)
	s.body[10] = s.body[0]
	game.resolve_collisions()
	t.ok("legacy AI skips the first 12 nodes", s.alive)
	t.eq_int("legacy AI survives the shallow overlap", s.deaths, 0)

	game = _fresh(206)
	game.cfg.collide.self_kill = true
	s = _spawn(game, 1000.0, 1000.0, 0.0, 40)
	s.body[20] = s.body[0]
	game.resolve_collisions()
	t.ok("legacy AI still dies past the skip window", not s.alive)

	# ---- head-on, equal length: both die ---------------------------------
	game = _fresh(104)
	var a = _spawn(game, 1000.0, 1000.0, 0.0, 20)
	var b = _spawn(game, 1030.0, 1000.0, PI, 20)
	game.resolve_collisions()
	t.ok("equal head-on kills the first", not a.alive)
	t.ok("equal head-on kills the second", not b.alive)
	t.eq_int("equal head-on gives no kill", a.kills + b.kills, 0)
	t.eq_int("both deaths counted", a.deaths + b.deaths, 2)
	t.eq_int("both bodies scattered", game.foods.size(), 40)

	# ---- head-on, longer wins and is rewarded ----------------------------
	game = _fresh(105)
	var winner = _spawn(game, 1000.0, 1000.0, 0.0, 40, true)
	var loser = _spawn(game, 1030.0, 1000.0, PI, 20)
	game.resolve_collisions()
	t.ok("longer snake survives a head-on", winner.alive)
	t.ok("shorter snake dies in a head-on", not loser.alive)
	t.eq_int("head-on absorb counts a kill", winner.kills, 1)
	t.eq_int("head-on absorb grows the winner", winner.length(), 40 + 16)
	t.eq_float("winner gets absorb immunity", winner.immune_until, 10.0 + 0.5, 1e-9)
	t.eq_int("game kill counter", game.kills, 1)

	# ---- side-on: the snake that charged harder dies ---------------------
	game = _fresh(106)
	var rear = _spawn(game, 1000.0, 1000.0, 0.0, 20)
	var front = _spawn(game, 1030.0, 1000.0, 0.0, 20)
	game.resolve_collisions()
	t.ok("rear-ending snake dies", not rear.alive)
	t.ok("rammed snake survives", front.alive)
	t.eq_int("rammed snake gets the kill", front.kills, 1)
	t.eq_int("AI kill reward is discounted", front.length(), 20 + 2)

	# ---- head into another snake's body ---------------------------------
	game = _fresh(107)
	var victim = _spawn(game, 1110.0, 1005.0, 0.0, 20)
	var wall_body = _spawn(game, 1200.0, 1000.0, 0.0, 20)
	game.resolve_collisions()
	t.ok("head into a body kills", not victim.alive)
	t.ok("body owner survives", wall_body.alive)
	t.eq_int("body owner credited with the kill", wall_body.kills, 1)

	# The harmless self-overlap must not shield a snake from an enemy body.
	game = _fresh(207)
	var tangled = _spawn(game, 1110.0, 1005.0, 0.0, 40, true)
	var blocker = _spawn(game, 1200.0, 1000.0, 0.0, 20)
	tangled.body[20] = tangled.body[0]     # own body overlap: harmless
	game.resolve_collisions()
	t.ok("enemy body still kills a self-overlapping snake", not tangled.alive)
	t.ok("the blocker survives the tangle", blocker.alive)
	t.eq_int("the blocker still gets the kill", blocker.kills, 1)

	# ---- immunity --------------------------------------------------------
	game = _fresh(108)
	a = _spawn(game, 1000.0, 1000.0, 0.0, 20)
	b = _spawn(game, 1030.0, 1000.0, PI, 20)
	a.immune_until = game.time + 5.0
	game.resolve_collisions()
	t.ok("immune snake cannot die", a.alive)
	t.ok("immune snake blocks the pair", b.alive)

	# ---- frozen spawn protection ----------------------------------------
	game = _fresh(109)
	a = _spawn(game, 1000.0, 1000.0, 0.0, 20)
	a.freeze_until = game.time + 1.0
	a.body[0] = Vector2(2.0, 1000.0)   # deep inside the wall
	game.resolve_collisions()
	t.ok("frozen snake ignores walls", a.alive)

	# ---- kill reward when the switch is off ------------------------------
	game = _fresh(110)
	game.cfg.snake.kill_reward.enabled = false
	winner = _spawn(game, 1000.0, 1000.0, 0.0, 60, true)
	loser = _spawn(game, 1030.0, 1000.0, PI, 20)
	game.resolve_collisions()
	t.ok("loser still dies", not loser.alive)
	t.eq_int("legacy fixed growth (player x2)", winner.length(), 60 + 10)

	# ---- dead snakes do not interact ------------------------------------
	game = _fresh(111)
	a = _spawn(game, 1000.0, 1000.0, 0.0, 20)
	b = _spawn(game, 1010.0, 1000.0, PI, 20)
	game.kill_snake(b, a)
	var gained: int = a.length() - 20
	t.eq_int("kill via kill_snake rewards", a.kills, 1)
	t.eq_int("kill via kill_snake grows", gained, 2)
	game.resolve_collisions()
	t.ok("corpse cannot die twice", a.alive)
	t.eq_int("corpse did not scatter again", b.deaths, 1)

	t.end_suite()
