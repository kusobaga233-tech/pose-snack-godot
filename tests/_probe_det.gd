extends SceneTree
## Determinism proof (not part of run_all): replays the determinism suite's
## scenario and prints the full observable-state signature of two independent
## same-seed runs, so two consecutive invocations can be diffed byte for byte.
##
##   godot --headless --path <project> --script res://tests/_probe_det.gd
##
## Expected: SIG_A == SIG_B and IDENTICAL=true, and the whole stdout identical
## across two invocations.

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSRng = preload("res://src/core/rng.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")


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


func _initialize() -> void:
	var input_log: Array = []
	var i := 0
	while i < 2400:
		input_log.append(sin(float(i) * 0.031) * 2.4)
		i += 1

	var a := _run(777, input_log, 1200)
	var b := _run(777, input_log, 1200)
	print("SIG_A=%s" % a)
	print("SIG_B=%s" % b)
	print("IDENTICAL=%s len_a=%d len_b=%d" % [str(a == b), a.length(), b.length()])

	# The ranking / food / player-position block of suite_determinism.
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
	var rank_parts: Array = []
	i = 0
	while i < r1.size():
		rank_parts.append("%d/%d/%d/%d" % [r1[i].id, r1[i].length, r1[i].kills, r1[i].deaths])
		i += 1
	print("RANK_1=%s" % "|".join(rank_parts))
	rank_parts.clear()
	i = 0
	while i < r2.size():
		rank_parts.append("%d/%d/%d/%d" % [r2[i].id, r2[i].length, r2[i].kills, r2[i].deaths])
		i += 1
	print("RANK_2=%s" % "|".join(rank_parts))
	print("FOOD_1=%d FOOD_2=%d" % [g1.foods.size(), g2.foods.size()])
	print("PLAYER_X_1=%.12f PLAYER_X_2=%.12f" % [
		g1.player.body[0].x, g2.player.body[0].x,
	])
	quit(0)
