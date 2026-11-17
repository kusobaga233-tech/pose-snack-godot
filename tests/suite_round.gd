extends RefCounted
## Suite: the round clock, the settlement payload and the strict length ranking.

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")
const PSRankRow = preload("res://src/core/rank_row.gd")


static func _new_game(seed_value: int):
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	return PSGame.new(cfg, tuning, seed_value)


static func run(t) -> void:
	t.suite("round")

	# ---- countdown state --------------------------------------------------
	var game = _new_game(301)
	var steer = PSSteerInput.new()
	steer.set_keyboard(0.0)
	game.start(2.0)
	t.eq_int("start(countdown) enters COUNTDOWN", game.state, PSGame.STATE_COUNTDOWN)
	t.eq_float("countdown length", game.countdown_left, 2.0)
	game.update(1.0 / 60.0, steer, 1.0 / 60.0)
	t.eq_int("countdown does not play yet", game.state, PSGame.STATE_COUNTDOWN)
	game.update(1.0, steer, 1.0)
	t.between("countdown still running", game.countdown_left, 0.0, 1.0)
	game.update(1.2, steer, 1.2)
	t.eq_int("countdown then play", game.state, PSGame.STATE_PLAYING)

	# ---- last call --------------------------------------------------------
	game.round_left = 10.0
	t.ok("last call at exactly 10 s", game.is_last_call())
	game.round_left = 10.01
	t.ok("no last call above the threshold", not game.is_last_call())
	game.round_left = 0.0
	t.ok("no last call after the whistle", not game.is_last_call())

	# ---- full 2 minute round ---------------------------------------------
	game = _new_game(302)
	game.start()
	t.eq_int("start() goes straight to PLAYING", game.state, PSGame.STATE_PLAYING)
	t.eq_int("8 snakes on the field", game.snakes.size(), 8)
	t.eq_int("7 AI brains", game.brains.size(), 7)
	t.eq_float("full round timer", game.round_left, 120.0)
	t.eq_int("round starts with food", game.foods.size(), game.cfg.food.target_count)
	t.eq_int("round starts with powerups", game.powerups.size(),
		game.cfg.powerups.target_count)
	var frozen_at_start := true
	var i := 0
	while i < game.players.size():
		if not game.players[i].is_frozen():
			frozen_at_start = false
		i += 1
	t.ok("humans start inside the spawn freeze", frozen_at_start)
	t.ok("humans start immune", game.players[0].is_immune())

	var frames := 0
	var heads_nan := false
	while frames < 7300 and game.state == PSGame.STATE_PLAYING:
		# Deterministic scripted steering: a slow sweep left and right.
		steer.set_keyboard(sin(float(frames) * 0.013) * 1.3)
		game.update(1.0 / 60.0, steer, 1.0 / 60.0)
		frames += 1
		i = 0
		while i < game.snakes.size():
			var s = game.snakes[i]
			i += 1
			if s.alive and s.body.size() > 0:
				if not (is_finite(s.body[0].x) and is_finite(s.body[0].y)):
					heads_nan = true
	t.eq_int("round reached the finished state", game.state, PSGame.STATE_FINISHED)
	t.eq_float("round timer hit zero", game.round_left, 0.0)
	t.between("round ran for 120 simulated seconds", game.time, 119.5, 120.5)
	t.between("round ended on the 7200th frame", float(frames), 7199.0, 7202.0)

	# ---- settlement payload ----------------------------------------------
	var result = game.round_result
	t.ok("settlement payload exists", result != null)
	t.eq_int("settlement has 8 rows", result.total, 8)
	t.eq_int("ranking array size", result.ranking.size(), 8)
	t.ok("player rank is inside 1..8", result.player_rank >= 1 and result.player_rank <= 8)
	t.ok("player row is present", result.player != null)
	t.ok("win flag matches rank 1", result.won == (result.player_rank == 1))
	t.eq_name("settlement mode", result.mode, &"timed")
	t.eq_float("settlement duration", result.duration_sec, 120.0)
	t.eq_int("ranking is the same array", result.ranking.size(), game.ranking.size())

	# strict ranking: ranks 1..8 in order, ids unique
	var seen_ids: Array = []
	var strict := true
	var sorted_ok := true
	var prev_len := 1 << 30
	var prev = null
	var field_ok := true
	i = 0
	while i < result.ranking.size():
		var row = result.ranking[i]
		if row.rank != i + 1:
			strict = false
		if seen_ids.has(row.id):
			strict = false
		seen_ids.append(row.id)
		if row.length > prev_len:
			sorted_ok = false
		prev_len = row.length
		if row.name == "" or row.id < 0 or row.length < 0 or row.kills < 0:
			field_ok = false
		if prev != null and not _before(prev, row):
			sorted_ok = false
		prev = row
		i += 1
	t.ok("ranks are 1..8 with no duplicate ids", strict)
	t.ok("rows are ordered by the JS comparator", sorted_ok)
	t.ok("payload rows carry id/name/length/kills", field_ok)
	t.eq_int("all 8 snakes are ranked", seen_ids.size(), 8)

	# dead snakes count as zero length
	var zero_ok := true
	i = 0
	while i < result.ranking.size():
		var row = result.ranking[i]
		var snake = null
		var k := 0
		while k < game.snakes.size():
			if game.snakes[k].id == row.id:
				snake = game.snakes[k]
			k += 1
		if snake != null and not snake.alive and row.length != 0:
			zero_ok = false
		i += 1
	t.ok("dead snakes rank with length 0", zero_ok)

	# ---- ranking tie-breaks ---------------------------------------------
	game = _new_game(303)
	game.brains.clear()
	# All 8 snakes dead (length 0) with identical stats, then break the ties.
	var n: int = game.snakes.size()
	i = 0
	while i < n:
		var s = game.snakes[i]
		s.alive = false
		s.body.resize(0)
		s.kills = 0
		s.deaths = 5
		s.peak_length = 16
		i += 1
	# snake 1 has fewer deaths than snake 0 -> snake 1 must rank first
	game.snakes[0].deaths = 2
	game.snakes[1].deaths = 1
	var rows = game.rank_snapshot()
	t.eq_int("fewer deaths wins the tie", rows[0].id, 1)
	t.eq_int("more deaths loses the tie", rows[1].id, 0)
	# equal deaths, more kills wins
	game = _new_game(304)
	game.brains.clear()
	i = 0
	while i < n:
		game.snakes[i].alive = false
		game.snakes[i].body.resize(0)
		game.snakes[i].kills = 0
		game.snakes[i].deaths = 0
		game.snakes[i].peak_length = 16
		i += 1
	game.snakes[4].kills = 3
	rows = game.rank_snapshot()
	t.eq_int("more kills wins the tie", rows[0].id, 4)
	# equal kills, bigger peak wins
	game.snakes[4].kills = 0
	game.snakes[6].peak_length = 90
	rows = game.rank_snapshot()
	t.eq_int("bigger peak wins the tie", rows[0].id, 6)
	# everything equal -> lower id wins, and the order stays strict
	game.snakes[6].peak_length = 16
	rows = game.rank_snapshot()
	t.eq_int("id breaks the final tie", rows[0].id, 0)
	var strictly_increasing := true
	i = 0
	while i < rows.size():
		if rows[i].rank != i + 1:
			strictly_increasing = false
		i += 1
	t.ok("rank numbers stay strict", strictly_increasing)

	# ---- restart hygiene -------------------------------------------------
	game = _new_game(305)
	game.start()
	frames = 0
	while frames < 240 and game.state == PSGame.STATE_PLAYING:
		steer.set_keyboard(0.4)
		game.update(1.0 / 60.0, steer, 1.0 / 60.0)
		frames += 1
	game.start()
	t.eq_int("restart resets the clock", game.state, PSGame.STATE_PLAYING)
	t.eq_float("restart resets round_left", game.round_left, 120.0)
	t.eq_float("restart resets time", game.time, 0.0)
	t.eq_int("restart resets the food pool", game.foods.size(), game.cfg.food.target_count)
	t.eq_int("restart clears the settlement", game.ranking.size(), 0)
	t.ok("restart clears the result", game.round_result == null)

	# ---- respawn inset (2026-11-17, owner: 复活点不要贴着墙) ----------------
	# Every respawn must land inside the half-a-screen inset, keep the existing
	# clearance to every living snake head, and stay deterministic. 40 real
	# `respawn_player()` calls on one game (the AI never respawns here: no
	# update runs, so their heads are static and the clearance is exact).
	game = _new_game(411)
	game.start()
	var inset: Vector2 = game.cfg.player.respawn_inset
	var w: float = game.cfg.world.w
	var h: float = game.cfg.world.h
	var inside_n := 0
	var clear_min := 1.0e18
	var border_min := Vector2(1.0e18, 1.0e18)
	var pts_a: Array = []
	var k2 := 0
	while k2 < 40:
		game.kill_snake(game.player, null)
		game.respawn_player()
		var hd: Vector2 = game.player.body[0]
		pts_a.append(hd)
		if hd.x >= inset.x and hd.x <= w - inset.x \
				and hd.y >= inset.y and hd.y <= h - inset.y:
			inside_n += 1
		border_min.x = minf(border_min.x, minf(hd.x, w - hd.x))
		border_min.y = minf(border_min.y, minf(hd.y, h - hd.y))
		var i2 := 0
		while i2 < game.snakes.size():
			var s2 = game.snakes[i2]
			i2 += 1
			if s2 == game.player or not s2.alive or s2.body.size() == 0:
				continue
			clear_min = minf(clear_min, hd.distance_to(s2.body[0]))
		k2 += 1
	t.eq_int("40 respawns all land inside the half-screen inset", inside_n, 40)
	t.ge("...and keep the human clearance", clear_min,
		game.cfg.player.respawn_clear_human)
	t.ok("...with at least half a screen to every border",
		border_min.x >= inset.x and border_min.y >= inset.y,
		"border=%s inset=%s" % [str(border_min), str(inset)])
	# Same seed -> the identical respawn sequence (the fixed rng stream).
	var game_b = _new_game(411)
	game_b.start()
	var same_seq := true
	k2 = 0
	while k2 < 40:
		game_b.kill_snake(game_b.player, null)
		game_b.respawn_player()
		if game_b.player.body[0] != pts_a[k2]:
			same_seq = false
		k2 += 1
	t.ok("respawn points are deterministic for the same seed", same_seq)
	# Fallback 1: the preferred centre is blocked but the inset still holds a
	# safe point -> the closest safe point INSIDE the inset is used.
	var fcfg = PSConfig.new()
	var ftuning = PSRuntimeTuning.new(fcfg)
	var fg = PSGame.new(fcfg, ftuning, 412)
	fg.start()
	var blocker = fg.snakes[1]
	blocker.alive = true
	blocker.body.resize(1)
	blocker.body[0] = Vector2(2400.0, 1350.0)
	fcfg.player.respawn_inset = Vector2(fcfg.world.w * 0.5 - 1400.0,
		fcfg.world.h * 0.5 - 1100.0)
	var p_in: Vector2 = fg.respawn_point(fcfg.player.respawn_clear_human,
		Vector2(2400.0, 1350.0))
	t.eq_str("blocked preferred candidates -> closest safe inset point",
		fg.respawn_note, "inset-fallback")
	var in_inset: bool = p_in.x >= fcfg.player.respawn_inset.x \
		and p_in.x <= fcfg.world.w - fcfg.player.respawn_inset.x \
		and p_in.y >= fcfg.player.respawn_inset.y \
		and p_in.y <= fcfg.world.h - fcfg.player.respawn_inset.y
	t.ok("...that point is inside the inset and clear of the blocker",
		in_inset and p_in.distance_to(Vector2(2400.0, 1350.0))
			>= fcfg.player.respawn_clear_human)
	# Fallback 2: the WHOLE inset is blocked (a 120x120 box around a blocker) ->
	# the closest safe point OUTSIDE the inset, with the reason recorded.
	fcfg.player.respawn_inset = Vector2(fcfg.world.w * 0.5 - 60.0,
		fcfg.world.h * 0.5 - 60.0)
	var p_out: Vector2 = fg.respawn_point(fcfg.player.respawn_clear_human,
		Vector2(2400.0, 1350.0))
	t.eq_str("whole inset blocked -> world fallback", fg.respawn_note, "world-fallback")
	var outside: bool = p_out.x < fcfg.player.respawn_inset.x \
		or p_out.x > fcfg.world.w - fcfg.player.respawn_inset.x \
		or p_out.y < fcfg.player.respawn_inset.y \
		or p_out.y > fcfg.world.h - fcfg.player.respawn_inset.y
	t.ok("...the fallback is outside the blocked inset, safe and logged",
		outside and p_out.distance_to(Vector2(2400.0, 1350.0))
			>= fcfg.player.respawn_clear_human)

	t.end_suite()


## Same ordering as PSGame._rank_before, expressed on the public row objects.
static func _before(a, b) -> bool:
	if a.length != b.length:
		return a.length > b.length
	if a.deaths != b.deaths:
		return a.deaths < b.deaths
	if a.kills != b.kills:
		return a.kills > b.kills
	if a.peak_length != b.peak_length:
		return a.peak_length > b.peak_length
	return a.id < b.id
