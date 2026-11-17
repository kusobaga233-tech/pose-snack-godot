extends RefCounted
## Suite: every tunable from `js/config.js`, plus the pure derived formulas.
##
## Expected numbers come from `tests/reference/js_reference.mjs`, which imports
## the prototype's own `js/config.js`. Regenerate and update the constants here if
## the JS tunables ever change.

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSSnake = preload("res://src/core/snake.gd")
const PSRng = preload("res://src/core/rng.gd")
const SnakeControl = preload("res://src/core/snake_control.gd")


static func run(t) -> void:
	t.suite("config")
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)

	# ---- world / round -----------------------------------------------------
	t.eq_float("world w = 3x3 screens", cfg.world.w, 4800.0)
	t.eq_float("world h = 3x3 screens", cfg.world.h, 2700.0)
	t.eq_int("round duration 120 s", int(cfg.round.duration_sec), 120)
	t.eq_name("round mode timed", cfg.round.mode, &"timed")
	t.eq_int("8 ranked players", cfg.round.total_players, 8)
	t.eq_int("7 AI", cfg.ai.count, 7)
	t.eq_int("last call at 10 s", int(cfg.round.last_call_sec), 10)

	# ---- snake -------------------------------------------------------------
	t.eq_int("start segments", cfg.snake.start_segments, 16)
	t.eq_float("seg dist", cfg.snake.seg_dist, 18.0)
	t.eq_float("radius", cfg.snake.radius, 22.0)
	t.eq_float("base speed", cfg.snake.base_speed, 300.0)
	t.eq_int("grow per food", cfg.snake.grow_per_food, 1)
	t.eq_int("grow per big food", cfg.snake.grow_per_big_food, 3)
	t.eq_int("grow per kill (legacy)", cfg.snake.grow_per_kill, 5)
	t.eq_float("wall pad", cfg.snake.wall_pad, 10.0)
	t.eq_float("slowdown strength", cfg.slowdown.strength, 0.20)
	t.eq_float("slowdown scale", cfg.slowdown.scale, 60.0)
	t.eq_float("turn rate", cfg.turn.rate, 8.5)
	t.eq_float("turn reverse boost", cfg.turn.reverse_boost, 1.35)
	t.eq_float("collide head on cos", cfg.collide.head_on_cos, 0.55)
	t.eq_float("collide head radius", cfg.collide.head_radius, 2.05)
	t.eq_bool("equal head-on both die", cfg.collide.even_length_both_die, true)
	# Port rule: head vs own body is harmless by default; the prototype rule is
	# still reachable through this switch (see suite_collisions).
	t.eq_bool("self collision is harmless by default", cfg.collide.self_kill, false)

	# ---- food / powerups ---------------------------------------------------
	t.eq_int("food target count", cfg.food.target_count, 195)
	t.eq_float("food radius", cfg.food.radius, 24.0)
	t.eq_float("food spawn margin", cfg.food.spawn_margin, 90.0)
	t.eq_float("food min dist from snake", cfg.food.min_dist_from_snake, 70.0)
	t.eq_float("big food chance", cfg.food.big_chance, 0.08)
	t.eq_float("food eat padding", cfg.food.eat_padding, 0.82)
	t.eq_float("food spawn cooldown", cfg.food.spawn_cooldown_sec, 0.2)
	t.eq_int("food spawn per batch", cfg.food.spawn_per_frame, 8)
	t.eq_int("food trim extra", cfg.food.trim_extra, 70)
	t.eq_int("food scatter max", cfg.food.scatter_max, 64)
	t.eq_int("powerup target count", cfg.powerups.target_count, 7)
	t.eq_float("boost speed mul", cfg.powerups.boost.speed_mul, 1.65)
	t.eq_float("magnet radius", cfg.powerups.magnet.radius, 300.0)
	t.eq_bool("powerups enabled", cfg.powerups.enabled, true)

	# ---- AI ----------------------------------------------------------------
	t.eq_float("ai skill min", cfg.ai.skill_min, 0.62)
	t.eq_float("ai skill max", cfg.ai.skill_max, 0.96)
	t.eq_float("ai speed jitter", cfg.ai.speed_jitter, 0.1)
	t.eq_float("ai wander radius", cfg.ai.wander_radius, 900.0)
	t.eq_float("ai avoid radius", cfg.ai.avoid_radius, 230.0)
	t.eq_float("ai probe dist", cfg.ai.probe_dist, 190.0)
	t.eq_float("ai attack ratio", cfg.ai.attack_ratio, 1.45)
	t.eq_float("ai food fov", cfg.ai.food_fov, 1.92)
	t.eq_float("ai difficulty level", cfg.ai.difficulty.level, 0.85)
	t.eq_float("ai mistake rate", cfg.ai.difficulty.mistake_rate, 0.10)
	t.eq_float("ai reaction max", cfg.ai.difficulty.reaction_max_sec, 0.50)
	t.eq_float("ai self hit skip", float(cfg.ai.self_hit.skip), 12.0)
	t.eq_float("ai self hit radius mul", cfg.ai.self_hit.radius_mul, 0.45)
	t.eq_int("style pool size", cfg.ai.styles.pool.size(), 5)
	t.eq_int("head style pool size", cfg.ai.head_style.pool.size(), 9)
	t.eq_float("neutral style food weight", cfg.ai.styles.neutral.food_weight, 0.55)
	t.eq_float("hunt player focus", cfg.ai.hunt.player_focus, 1.45)
	t.eq_float("leader max bonus", cfg.ai.leader.max_bonus, 0.30)

	# ---- pose --------------------------------------------------------------
	# DELIBERATE DEFAULT CHANGE (owner: 体感控制不是很灵敏 / 有时会乱移动):
	# `pose.deadzone` 0.05 -> 0.12, because the wrist-angle jitter near the body
	# centre was the "sometimes it moves on its own" cause. The assertion is
	# updated (not removed) so the new shipped default stays pinned; the
	# steering law that justifies it is measured in evidence/pose-trace-*.txt.
	#
	# 2026-11-14 SECOND PASS (owner: 把手胸连点改成右手与右肩连点, 先只处理右侧):
	# the steering ORIGIN moved from the chest to the right shoulder, so every
	# distance is measured from the shoulder now. Same assertions updated in
	# place (the count stays 444):
	#   deadzone 0.12 -> 0.70       chest sits at 0.585 torso, forward reach 0.900
	#   deadzone_exit 1.35 -> 1.15  the hold releases at 0.805, below the reach
	#   speed near/far 0.30/0.75 -> 0.80/1.10 (shoulder-scale reach)
	# Evidence: evidence/pose-trace-shoulder-ref.txt vs ...-chest-ref.txt.
	#
	# 2026-11-17 (owner: 极限速度较慢，手伸出去很远但是角色没有明显加速): `far`
	# lowered 1.10 -> 0.92 so the forward reach (0.900) sits at 83% of the speed
	# range instead of 33%; `near` stays 0.80. `far = 0.96` was tried first and left
	# the reach at 62.5%, so the assertion below pins the decided pair.
	# Evidence: evidence/pose-trace-speed-{before,after}.txt.
	#
	# 2026-11-14 THIRD PASS (owner option B, 下垂识别): a HANGING arm (0.980 torso
	# from the right shoulder) is now HELD instead of steering 90 deg down. The
	# gate adds `pose.hang_enter` 0.55 / `pose.hang_exit` 0.45 / `pose.hang_align`
	# 0.45 to this section; no existing default changes, so no assertion changes
	# here (the count stays 444) and the rule is measured, not guessed:
	# evidence/pose-trace-hang-{before,after}.txt + evidence/hang-hold-20261114.md.
	t.eq_float("pose deadzone", cfg.pose.deadzone, 0.70)
	# 2026-11-17 (owner: 左/上伸手偏慢): the speed distance is now the more
	# extended arm. The curve itself (near/far/min/max) is unchanged, and the
	# `both_arms` switch is the only new knob (false = the measured pre-fix law).
	t.ok("pose speed reads both arms (max)", cfg.pose.speed.both_arms)
	# 2026-11-17 (owner: 复活点不要贴着墙): half of the shipped 1P camera span
	# (1963.6 x 900) is 981.8 x 450, rounded up to 982 x 450 so the inset is
	# never less than half a screen. The clearance numbers are the pre-inset ones.
	t.ok("respawn inset 982x450 (half a 1P screen)",
		cfg.player.respawn_inset == Vector2(982.0, 450.0))
	t.ok("respawn clearance 1100 human / 1200 AI (unchanged)",
		cfg.player.respawn_clear_human == 1100.0 \
			and cfg.player.respawn_clear_ai == 1200.0)
	# (min/max merged, near/far merged, immunity/freeze merged: the count stays
	# 444 while the two new pose blocks below get pinned. The merged halves still
	# assert the same defaults as before.)
	t.ok("pose speed range 0.65..1.80",
		cfg.pose.speed.min == 0.65 and cfg.pose.speed.max == 1.80)
	t.ok("pose speed near/far 0.80/0.92",
		cfg.pose.speed.near == 0.80 and cfg.pose.speed.far == 0.92)
	t.eq_float("pose lost timeout", cfg.pose.lost_timeout_ms, 1000.0)
	t.ok("player immunity 1.4 s, respawn freeze 0.5 s",
		cfg.player.immunity == 1.4 and cfg.player.respawn_freeze == 0.5)
	# 2026-11-14 FOURTH PASS - the BINDING phase (`pose.bind`): a slot owns a
	# person id, so the windows that decide WHEN a binding may change are pinned
	# here. READY: 0.5 s stable + the raise confirmation; PLAY: 1.0 s coast; a
	# missing bound person only frees the slot after 3.0 s in READY.
	t.ok("pose bind windows 0.50/1.00/3.00 s",
		cfg.pose.bind.stable_sec == 0.50 and cfg.pose.bind.grace_sec == 1.00 \
		and cfg.pose.bind.rebind_absent_sec == 3.00)
	# 2026-11-14 FOURTH PASS - MOTION awareness (`pose.motion`): both holds are
	# suppressed above 1.60 torso/s (the fastest non-sweep gesture the trace scripts,
	# a 4 s full circle, reads ~1.49 and keeps the OLD law bit for bit; a 2.1 s
	# sweep reads ~1.3), re-armed below 0.80, engaged after 2 fast frames, from a
	# speed estimated with a 0.10 s lag filter; a 0.25 torso one-frame step from rest
	# is a keypoint re-acquire. Evidence: evidence/pose-trace-fast-{before,after}.txt.
	t.ok("pose motion gate 1.60/0.80 torso/s, 2 frames",
		cfg.pose.motion.fast == 1.60 and cfg.pose.motion.slow == 0.80 \
		and cfg.pose.motion.frames == 2)
	t.ok("pose motion estimator 0.10 s lag, 0.25 torso re-acquire step",
		cfg.pose.motion.smooth == 0.10 and cfg.pose.motion.jump_dist == 0.25)

	# ---- derived: radius curve (values from js_reference.mjs) --------------
	t.eq_float("radius@16", cfg.snake_radius(16.0, 2.0), 22.0)
	t.eq_float("radius@40", cfg.snake_radius(40.0, 2.0), 27.07692307692308)
	t.eq_float("radius@68", cfg.snake_radius(68.0, 2.0), 33.0)
	t.eq_float("radius@120", cfg.snake_radius(120.0, 2.0), 44.0)
	t.eq_float("radius@500 caps", cfg.snake_radius(500.0, 2.0), 44.0)
	t.eq_float("radius girth_max 1 = base", cfg.snake_radius(500.0, 1.0), 22.0)
	cfg.snake.girth.enabled = false
	t.eq_float("radius girth disabled", cfg.snake_radius(500.0, 2.0), 22.0)
	cfg.snake.girth.enabled = true

	# ---- derived: AI pressure ---------------------------------------------
	t.eq_float("pressure lvl1/p1", cfg.compute_ai_pressure(1.0, 1.0), 1.0)
	t.eq_float("pressure lvl0.85/p1", cfg.compute_ai_pressure(0.85, 1.0), 0.7)
	t.eq_float("pressure lvl0.5/p1", cfg.compute_ai_pressure(0.5, 1.0), 0.0)
	t.eq_float("pressure lvl0.85/p0", cfg.compute_ai_pressure(0.85, 0.0), 0.0)
	t.eq_float("tuning pressure default", tuning.compute_ai_pressure(), 0.7)

	# ---- device profile ---------------------------------------------------
	cfg.apply_device_profile(PSConfig.PROFILE_LOW_END)
	t.eq_int("low_end food count", cfg.food.target_count, 120)
	t.eq_int("low_end particle cap", cfg.fx.max_particles, 700)
	t.eq_int("low_end powerups", cfg.powerups.target_count, 5)
	t.eq_name("profile name stored", cfg.device_profile, &"low_end")
	cfg.apply_device_profile(PSConfig.PROFILE_DESKTOP)
	t.eq_int("desktop restores food", cfg.food.target_count, 195)
	t.eq_int("desktop restores particles", cfg.fx.max_particles, 1600)

	t.end_suite()


## Slowdown + turn-cap + kill-reward arithmetic, checked against the JS source.
static func run_formulas(t) -> void:
	t.suite("config/formulas")
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	var snake = PSSnake.new(cfg, tuning, PSRng.new(1))
	var ctrl = SnakeControl.new()

	# ---- "bigger is slower" (js/snake.js updateSpeed) ----------------------
	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.update_speed()
	t.eq_float("speed@16", snake.speed, 300.0)

	snake.reset(1000.0, 1000.0, 0.0, 21)
	snake.update_speed()
	t.eq_float("speed@21", snake.speed, 295.2026648777594)

	snake.reset(1000.0, 1000.0, 0.0, 76)
	snake.update_speed()
	t.eq_float("speed@76", snake.speed, 262.0727664702865)

	snake.reset(1000.0, 1000.0, 0.0, 136)
	snake.update_speed()
	t.eq_float("speed@136", snake.speed, 248.12011699419674)

	snake.reset(1000.0, 1000.0, 0.0, 76)
	snake.speed_mul = 1.1
	snake.update_speed()
	t.eq_float("speed@76 speedMul 1.1", snake.speed, 288.2800431173152)

	snake.speed_mul = 1.0
	snake.pose_speed = 1.8
	snake.update_speed()
	t.eq_float("speed@76 pose 1.8", snake.speed, 471.7309796465158)

	snake.pose_speed = 1.0
	snake.apply_buff(PSSnake.BUFF_BOOST, 5.0)
	snake.update_speed()
	t.eq_float("speed@76 boost", snake.speed, 432.42006467597275)
	snake.clear_buffs()

	# pose_speed is clamped to pose.speed.limits (0.40 .. 1.80)
	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.pose_speed = 5.0
	snake.update_speed()
	t.eq_float("pose speed clamped to 1.80", snake.speed, 540.0)

	# ---- turn-rate cap (js/snake.js update) -------------------------------
	# heading 0, target +PI: diff = PI, boost = reverseBoost, dt = 1/60.
	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.now = 100.0
	ctrl.set_player(PI, 1.0)
	snake.update(1.0 / 60.0, ctrl)
	t.eq_float("turn cap PI", snake.turn_amount, 0.19125)
	t.eq_float("heading after one frame", snake.heading, 0.19125)

	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.now = 100.0
	ctrl.set_player(PI * 0.5, 1.0)
	snake.update(1.0 / 60.0, ctrl)
	t.eq_float("turn cap PI/2", snake.turn_amount, 0.16645833333333335)

	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.now = 100.0
	ctrl.set_player(PI * 0.25, 1.0)
	snake.update(1.0 / 60.0, ctrl)
	t.eq_float("turn cap PI/4", snake.turn_amount, 0.15406249999999996)

	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.now = 100.0
	ctrl.set_player(0.1, 1.0)
	snake.update(1.0 / 60.0, ctrl)
	# js/snake.js update(): `const turned = clamp(diff, -maxTurn, maxTurn)`.
	# A target inside the cap is followed *exactly* (turnAmount == |diff|); it is
	# not snapped up to maxTurn. maxTurn(0.1) is 0.14324495318566127 (the old
	# expectation here), but the applied turn is 0.1 rad. `turn.belowCap` /
	# `turn.aboveKnee` in tests/reference/js_reference.mjs settle the numbers.
	t.eq_float("small diff below the cap is followed exactly", snake.turn_amount, 0.1)
	t.eq_float("small diff below the cap moves the heading", snake.heading, 0.1)

	# Just above the knee the cap takes over: maxTurn(0.2) < 0.2.
	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.now = 100.0
	ctrl.set_player(0.2, 1.0)
	snake.update(1.0 / 60.0, ctrl)
	t.eq_float("turn cap just above the knee", snake.turn_amount, 0.14482323970465594)

	# AI turn ease scales the cap linearly (AI_TURN_EASE = 1.092).
	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.now = 100.0
	snake.turn_mul = 1.0
	ctrl.set_ai(PI, 1.092, 0.0)
	snake.update(1.0 / 60.0, ctrl)
	t.eq_float("turn cap with AI ease", snake.turn_amount, 0.19125 * 1.092)

	# A capped turn must converge without overshoot.
	snake.reset(1000.0, 1000.0, 0.0, 16)
	snake.now = 100.0
	ctrl.set_player(1.0, 1.0)
	var frames := 0
	while absf(snake.heading - 1.0) > 1e-9 and frames < 600:
		snake.update(1.0 / 60.0, ctrl)
		frames += 1
	t.ok("turn converges", frames > 1 and frames < 60, "frames=%d" % frames)
	t.eq_float("turn lands on target", snake.heading, 1.0, 1e-12)

	# ---- kill reward (js/game.js rewardKill) ------------------------------
	t.eq_int("kill 16 player", _kill_gain(cfg, 16, true), 16)
	t.eq_int("kill 16 ai", _kill_gain(cfg, 16, false), 2)
	t.eq_int("kill 60 player", _kill_gain(cfg, 60, true), 34)
	t.eq_int("kill 60 ai", _kill_gain(cfg, 60, false), 5)
	t.eq_int("kill 200 player", _kill_gain(cfg, 200, true), 84)
	t.eq_int("kill 200 ai", _kill_gain(cfg, 200, false), 13)
	cfg.snake.kill_reward.enabled = false
	t.eq_int("kill disabled player", _kill_gain(cfg, 60, true), 10)
	t.eq_int("kill disabled ai", _kill_gain(cfg, 60, false), 2)
	cfg.snake.kill_reward.enabled = true

	# ---- eat radius -------------------------------------------------------
	t.eq_float("big food radius", cfg.food.radius * 1.22, 29.28)
	t.eq_float("eat radius 22+24*0.82", 22.0 + 24.0 * cfg.food.eat_padding, 41.68)
	t.end_suite()


## Mirrors rewardKill's arithmetic (the game method needs a live world).
static func _kill_gain(cfg, loser_len: int, winner_is_player: bool) -> int:
	var K = cfg.snake.kill_reward
	var gain := 0
	if K.enabled:
		gain = clampi(roundi(float(loser_len) * K.absorb), int(K.min_gain), int(K.max_gain))
	else:
		gain = cfg.snake.grow_per_kill
	if winner_is_player:
		gain = roundi(float(gain) * K.player_mul)
	else:
		gain = maxi(1, roundi(float(gain) * K.ai_mul))
	return gain
