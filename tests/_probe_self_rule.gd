extends SceneTree
## Manual probe (NOT part of `run_all.gd`): measures the 2026-11-12 rule change.
##
##   tools\run_godot_safe.ps1 -Script res://tests/_probe_self_rule.gd
##
## Prints, in order:
##   CURL   one snake driven into a saturated turn: how often its head is inside
##          its own body, how far the head travels, whether it survives.
##   ROUND  a full deterministic 2-minute round with the scripted human sweep from
##          `suite_round`: every death is attributed exactly (the ProbeGame
##          subclass hooks `kill_snake`, so a death is known before the corpse is
##          cleared), plus how often a living snake overlapped its own body without
##          dying and how much work the AI still spends on self-avoidance.

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSSnake = preload("res://src/core/snake.gd")
const SnakeControl = preload("res://src/core/snake_control.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")
const PSMath = preload("res://src/core/ps_math.gd")


## Exact death attribution: `kill_snake` is called before the body is cleared, and
## `kill_snake(..., null)` is only reached from the wall branch (self-kill is off
## by default) or from the equal-length head-on branch, which kills two snakes in
## the same collision pass.
class ProbeGame extends "res://src/core/game.gd":
	var cause := {"wall": 0, "enemy": 0, "mutual": 0, "self": 0, "unknown": 0}
	var ai_cause := {"wall": 0, "enemy": 0, "mutual": 0, "self": 0, "unknown": 0}
	var player_deaths := 0
	var _null_deaths: Array = []
	var _null_on_pad: Array = []
	var _null_len: Array = []

	func resolve_collisions() -> void:
		_null_deaths.clear()
		_null_on_pad.clear()
		_null_len.clear()
		super()
		var pending := 0
		var k := 0
		while k < _null_deaths.size():
			if not bool(_null_on_pad[k]):
				pending += 1
			k += 1
		# Two non-wall killer-less deaths in one pass = equal-length head-on.
		k = 0
		while k < _null_deaths.size():
			var tag := "self"
			if bool(_null_on_pad[k]):
				tag = "wall"
			elif pending >= 2:
				tag = "mutual"
			_record(_null_deaths[k], int(_null_len[k]), tag)
			k += 1

	func kill_snake(snake, killer, eaten: bool = false) -> void:
		if not snake.alive:
			return
		if killer != null:
			_record(snake, snake.body.size(), "enemy")
		else:
			var p: float = cfg.snake.wall_pad
			var h: Vector2 = snake.body[0]
			_null_deaths.append(snake)
			_null_len.append(snake.body.size())
			_null_on_pad.append(
				absf(h.x - p) < 1e-6 or absf(h.x - (world_w - p)) < 1e-6
				or absf(h.y - p) < 1e-6 or absf(h.y - (world_h - p)) < 1e-6)
		super(snake, killer, eaten)

	func _record(snake, length: int, tag: String) -> void:
		cause[tag] = int(cause[tag]) + 1
		if snake.is_player:
			player_deaths += 1
		else:
			ai_cause[tag] = int(ai_cause[tag]) + 1
		print("  DEATH t=%.2f id=%d player=%s len=%d cause=%s" % [
			time, snake.id, str(snake.is_player), length, tag,
		])


func _initialize() -> void:
	_curl_matrix()
	_round()
	quit(0)


## One snake, constant turn: how often does its head end up inside its own body?
## `turn_rate` is the runtime tuning knob (8.5 rad/s is the shipped value); a lower
## rate widens the circle until the 18 px body links can actually follow it.
## `period > 0` flips the turn every `period` frames (a zig-zag), which is how a
## real player folds the body back onto itself at the shipped turn rate.
func _curl_trial(segments: int, turn_rate: float, frames_max: int, offset: float,
		period: int) -> Array:
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	tuning.turn_rate = turn_rate
	var game = PSGame.new(cfg, tuning, 203)
	game.brains.clear()
	game.snakes.clear()
	game.players.clear()
	game.foods.clear()
	game.powerups.clear()
	game.time = 10.0

	var s = PSSnake.new(cfg, tuning, game.rng)
	s.reset(2400.0, 1350.0, 0.0, segments)
	s.now = game.time
	s.is_player = true
	s.player_index = 0
	game.players.append(s)
	game.player = s
	game.snakes.append(s)

	var ctrl = SnakeControl.new()
	var frames := 0
	var hit_frames := 0
	var min_clear := INF
	var turn_sum := 0.0
	var alive_all := true
	var sign := 1.0
	while frames < frames_max:
		if period > 0 and frames % period == 0:
			sign = -sign
		ctrl.set_player(s.heading + offset * sign, 1.0)
		var before_heading: float = s.heading
		s.update(1.0 / 60.0, ctrl)
		turn_sum += absf(PSMath.norm_angle(s.heading - before_heading))
		# Nearest own-body node outside the neck, every frame.
		var h: Vector2 = s.body[0]
		var nearest := INF
		var k := 9
		while k < s.body.size():
			var d: float = h.distance_to(s.body[k])
			if d < nearest:
				nearest = d
			k += 1
		if nearest < min_clear:
			min_clear = nearest
		if s.hit_self():
			hit_frames += 1
		game.resolve_collisions()
		if not s.alive:
			alive_all = false
			break
		frames += 1
	return [frames, alive_all, hit_frames, min_clear, s.radius() * 0.62,
		turn_sum / TAU, s.deaths, s.length(), frames_max]


func _curl_matrix() -> void:
	#            segments, turn_rate, frames, offset, period
	var trials := [
		[90, 8.5, 1200, 0.6, 0],
		[90, 2.2, 600, 0.6, 0],
		[90, 2.2, 900, 0.6, 0],
		[90, 2.2, 1200, 0.6, 0],
		[90, 3.0, 900, 0.6, 0],
		[60, 2.2, 900, 0.6, 0],
		[40, 2.2, 900, 0.6, 0],
	]
	for trial in trials:
		var r := _curl_trial(int(trial[0]), float(trial[1]), int(trial[2]),
			float(trial[3]), int(trial[4]))
		print("CURL seg=%d rate=%.1f amp=%.1f period=%d frames=%d/%d alive=%s hit=%d min_clear=%.2f rr=%.2f loops=%.2f deaths=%d len=%d" % [
			int(trial[0]), float(trial[1]), float(trial[3]), int(trial[4]),
			r[0], r[8], str(r[1]), r[2], r[3], r[4], r[5], r[6], r[7],
		])


## Full 2-minute round; every death is attributed by ProbeGame.
func _round() -> void:
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	var game = ProbeGame.new(cfg, tuning, 302)
	var steer = PSSteerInput.new()
	game.start()

	var dt := 1.0 / 60.0
	var frames := 0
	var self_overlap_frames := 0   # living snake-frames with the head inside its body
	var self_overlap_snakes := {}
	while frames < 7300 and game.state == PSGame.STATE_PLAYING:
		var i := 0
		while i < game.snakes.size():
			var s = game.snakes[i]
			if s.alive and s.body.size() > 0 and s.hit_self():
				self_overlap_frames += 1
				self_overlap_snakes[s.id] = true
			i += 1
		steer.set_keyboard(sin(float(frames) * 0.013) * 1.3)
		game.update(dt, steer, dt)
		frames += 1

	var escape_hits := 0
	var escape_stuck := 0
	var lapses := 0
	var k := 0
	while k < game.brains.size():
		escape_hits += game.brains[k].escape_hits
		escape_stuck += game.brains[k].escape_stuck
		lapses += game.brains[k].lapses
		k += 1
	var lengths: Array = []
	k = 0
	while k < game.snakes.size():
		lengths.append(game.snakes[k].length())
		k += 1
	print("ROUND t=%.1f state=%d causes=%s ai_causes=%s player_deaths=%d" % [
		game.time, game.state, str(game.cause), str(game.ai_cause), game.player_deaths,
	])
	print("ROUND self_overlap_frames=%d snakes_overlapping=%d escape_hits=%d escape_stuck=%d ai_lapses=%d" % [
		self_overlap_frames, self_overlap_snakes.size(), escape_hits, escape_stuck, lapses,
	])
	print("ROUND final_lengths=%s food=%d" % [str(lengths), game.foods.size()])
