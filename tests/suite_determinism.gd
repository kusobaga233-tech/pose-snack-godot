extends RefCounted
## Suite: determinism. Same seed + same input log => identical simulation.
##
## This is the guarantee that makes headless tests (and bug reports) useful: no
## wall clock, no global RNG, no Node/Timer anywhere in the rule core.

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSRng = preload("res://src/core/rng.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")
const PSSnake = preload("res://src/core/snake.gd")


## Full observable state: identity, size, scoreboard, pose and food count.
static func _signature(game) -> String:
	var parts: Array = []
	var i := 0
	while i < game.snakes.size():
		var s = game.snakes[i]
		i += 1
		var hx := 0.0
		var hy := 0.0
		if s.body.size() > 0:
			hx = s.body[0].x
			hy = s.body[0].y
		parts.append("%d/%d/%d/%d/%d/%.9f/%.9f/%.9f/%.9f/%s" % [
			s.id, s.body.size(), s.kills, s.deaths, s.food_eaten,
			hx, hy, s.heading, s.speed, str(s.alive),
		])
	return "|".join(parts) + "|foods=%d|powerups=%d|t=%.9f" % [
		game.foods.size(), game.powerups.size(), game.time,
	]


static func _run(seed_value: int, input_log: Array, frames: int) -> String:
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	var game = PSGame.new(cfg, tuning, seed_value)
	var steer = PSSteerInput.new()
	game.start()
	var i := 0
	while i < frames and game.state == PSGame.STATE_PLAYING:
		steer.set_keyboard(input_log[i % input_log.size()])
		game.update(1.0 / 60.0, steer, 1.0 / 60.0)
		i += 1
	return _signature(game)


static func run(t) -> void:
	t.suite("determinism")

	# A recorded "input log": the same list is replayed into both worlds.
	var input_log: Array = []
	var i := 0
	while i < 2400:
		input_log.append(sin(float(i) * 0.031) * 2.4)
		i += 1

	var frames := 1200   # 20 simulated seconds
	var a := _run(777, input_log, frames)
	var b := _run(777, input_log, frames)
	t.ok("same seed + same input log produce identical state", a == b,
		"signatures differ" if a != b else "")
	t.eq_int("signature length is stable", a.length(), b.length())

	var c := _run(778, input_log, frames)
	t.ok("a different seed diverges", a != c)

	var other_log: Array = []
	i = 0
	while i < 2400:
		other_log.append(cos(float(i) * 0.017) * 1.1)
		i += 1
	var d := _run(777, other_log, frames)
	t.ok("a different input log diverges", a != d)

	# Two runs of the same seed must also agree on the ranking payload.
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	var g1 = PSGame.new(cfg, tuning, 999)
	var g2 = PSGame.new(cfg, tuning, 999)
	g1.start()
	g2.start()
	var steer = PSSteerInput.new()
	var f := 0
	while f < 900:
		steer.set_keyboard(input_log[f])
		g1.update(1.0 / 60.0, steer, 1.0 / 60.0)
		g2.update(1.0 / 60.0, steer, 1.0 / 60.0)
		f += 1
	var r1 = g1.rank_snapshot()
	var r2 = g2.rank_snapshot()
	var same_rank := true
	i = 0
	while i < r1.size():
		if r1[i].id != r2[i].id or r1[i].length != r2[i].length or r1[i].kills != r2[i].kills:
			same_rank = false
		i += 1
	t.ok("ranking is identical for the same seed", same_rank)
	t.eq_int("food pools match", g1.foods.size(), g2.foods.size())
	t.eq_float("game clocks match", g1.time, g2.time, 1e-12)
	t.eq_float("player position matches exactly", g1.player.body[0].x, g2.player.body[0].x, 1e-12)

	# ---- RNG itself ------------------------------------------------------
	var rng_a = PSRng.new(1234)
	var rng_b = PSRng.new(1234)
	var rng_c = PSRng.new(1235)
	var same := true
	var differs := false
	i = 0
	while i < 32:
		var va := rng_a.randf()
		var vb := rng_b.randf()
		if va != vb:
			same = false
		if va != rng_c.randf():
			differs = true
		i += 1
	t.ok("PSRng is reproducible", same)
	t.ok("PSRng differs across seeds", differs)

	# rand_range / rand_int must consume the *seeded* stream. A bare `randf()`
	# inside rng.gd resolves to Godot's global built-in, which made every
	# rand_range() draw nondeterministic while leaving the injected stream
	# frozen (the original determinism failure). These two assertions are the
	# regression guard for that.
	var ra = PSRng.new(4321)
	var rb = PSRng.new(4321)
	var same_range := true
	i = 0
	while i < 16:
		if ra.rand_range(-3.0, 7.0) != rb.rand_range(-3.0, 7.0):
			same_range = false
		i += 1
	t.ok("rand_range is reproducible", same_range)

	var rc = PSRng.new(99)
	rc.rand_range(0.0, 1.0)
	var after_range := rc.randf()
	var rd = PSRng.new(99)
	rd.randf()
	var second_draw := rd.randf()
	t.ok("rand_range consumes exactly one seeded draw", after_range == second_draw)

	var re = PSRng.new(4321)
	var rf = PSRng.new(4321)
	var same_int := true
	i = 0
	while i < 16:
		if re.rand_int(1, 6) != rf.rand_int(1, 6):
			same_int = false
		i += 1
	t.ok("rand_int is reproducible", same_int)

	var r3 = PSRng.new(0)
	var values: Array = []
	i = 0
	while i < 8:
		var v := r3.randf()
		values.append(v)
		if v < 0.0 or v >= 1.0:
			t.fail("PSRng stays in [0,1)", "got %f" % v)
		i += 1
	t.ok("zero seed is remapped, not degenerate", values.size() == 8 and values[0] != values[1])
	t.ok("rand_int stays in range", PSRng.new(5).rand_int(3, 3) == 3)
	t.ok("rand_range spans the interval", PSRng.new(6).rand_range(10.0, 20.0) >= 10.0)

	# ---- no hidden wall-clock dependency ---------------------------------
	# Timers (freeze / immunity / buffs) run on the simulation clock, so a real
	# 40 ms pause must not change any of them.
	var snap_cfg = PSConfig.new()
	var snap_tuning = PSRuntimeTuning.new(snap_cfg)
	var snap = PSSnake.new(snap_cfg, snap_tuning, PSRng.new(1))
	snap.reset(2400.0, 1350.0, 0.0, 16)
	snap.now = 0.2
	snap.freeze_until = 1.0
	snap.immune_until = 2.0
	snap.apply_buff(PSSnake.BUFF_BOOST, 4.0)
	var frozen_before: bool = snap.is_frozen()
	var immune_before: bool = snap.is_immune()
	var buff_before: float = snap.buff_left(PSSnake.BUFF_BOOST)
	OS.delay_msec(40)
	t.eq_bool("freeze ignores wall-clock time", snap.is_frozen(), frozen_before)
	t.eq_bool("immunity ignores wall-clock time", snap.is_immune(), immune_before)
	t.eq_float("buff timer ignores wall-clock time",
		snap.buff_left(PSSnake.BUFF_BOOST), buff_before)
	snap.now = 1.5
	t.ok("freeze ends on the simulation clock", not snap.is_frozen())
	t.ok("immunity outlasts the freeze", snap.is_immune())

	t.end_suite()
