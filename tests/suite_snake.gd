extends RefCounted
## Suite: the snake entity (motion model, growth, self/wall tests, buffs).

const PSConfig = preload("res://src/core/config.gd")
const PSRuntimeTuning = preload("res://src/core/tuning.gd")
const PSRng = preload("res://src/core/rng.gd")
const PSSnake = preload("res://src/core/snake.gd")
const SnakeControl = preload("res://src/core/snake_control.gd")


static func run(t) -> void:
	t.suite("snake")
	var cfg = PSConfig.new()
	var tuning = PSRuntimeTuning.new(cfg)
	var s = PSSnake.new(cfg, tuning, PSRng.new(11))
	var ctrl = SnakeControl.new()
	s.now = 100.0

	# ---- reset lays the body out behind the head ---------------------------
	s.reset(1000.0, 1000.0, 0.0, 16)
	t.eq_int("reset length", s.length(), 16)
	t.ok("alive after reset", s.alive)
	t.eq_float("head at reset point x", s.body[0].x, 1000.0)
	t.eq_float("head at reset point y", s.body[0].y, 1000.0)
	t.eq_float("body[1] one seg behind", s.body[1].x, 1000.0 - cfg.snake.seg_dist, 1e-5)
	t.eq_float("body[15] fifteen segs behind", s.body[15].x,
		1000.0 - 15.0 * cfg.snake.seg_dist, 1e-5)
	t.eq_float("reset speed is base", s.speed, 300.0)
	t.eq_int("peak starts at length", s.peak_length, 16)
	t.eq_float("radius at 16", s.radius(), 22.0)

	# ---- growth ------------------------------------------------------------
	s.grow(5)
	t.eq_int("grow 5", s.length(), 21)
	t.eq_int("peak tracks growth", s.peak_length, 21)
	t.ok("tail keeps extending", s.body[20].x < s.body[15].x)
	s.update_speed()
	t.eq_float("speed after growth", s.speed, 295.2026648777594)

	# fractional growth banks the remainder (AI food multiplier / leader bonus)
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.grow_fractional(0.6)
	t.eq_int("fraction 0.6 does not grow", s.length(), 16)
	t.eq_float("fraction carry", s.growth_carry, 0.6, 1e-9)
	s.grow_fractional(0.6)
	t.eq_int("fraction 1.2 grows one", s.length(), 17)
	t.eq_float("fraction carry left", s.growth_carry, 0.2, 1e-9)
	s.grow_fractional(-1.0)
	t.eq_int("negative fraction ignored", s.length(), 17)

	# ---- radius follows length --------------------------------------------
	s.reset(1000.0, 1000.0, 0.0, 16)
	t.eq_float("radius 16", s.radius(), 22.0)
	s.grow(104)
	t.eq_int("length 120", s.length(), 120)
	t.eq_float("radius 120 (max girth)", s.radius(), 44.0)
	tuning.girth_max = 1.0
	t.eq_float("radius with girth slider at 1", s.radius(), 22.0)
	tuning.girth_max = 2.0
	t.eq_float("radius back to max", s.radius(), 44.0)

	# ---- follow chain -----------------------------------------------------
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.now = 100.0
	s.update(1.0 / 60.0, null)
	t.eq_float("head advanced one frame", s.body[0].x, 1000.0 + 300.0 / 60.0, 1e-4)
	var max_link := 0.0
	var i := 1
	while i < s.length():
		var d: float = s.body[i].distance_to(s.body[i - 1])
		if d > max_link:
			max_link = d
		i += 1
	t.le("links never exceed seg_dist", max_link, cfg.snake.seg_dist + 1e-3)

	# ---- turn-rate cap in a live update ------------------------------------
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.now = 100.0
	ctrl.set_player(PI, 1.0)
	s.update(1.0 / 60.0, ctrl)
	t.eq_float("one frame turn is capped", s.turn_amount, 0.19125)
	t.eq_float("heading moved by the cap", s.heading, 0.19125)
	t.gt("head now moved off the x axis", absf(s.body[0].y - 1000.0), 1e-3)

	# turn_ease (AI) scales the cap: 0.5 -> half the turn
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.now = 100.0
	ctrl.set_ai(PI, 0.5, 0.0)
	s.update(1.0 / 60.0, ctrl)
	t.eq_float("turn_ease 0.5 halves the cap", s.turn_amount, 0.19125 * 0.5)

	# wobble is added to the target angle (0.1 rad off the heading).
	# js/snake.js update(): `turned = clamp(diff, -maxTurn, maxTurn)`, so a
	# 0.1 rad target is followed exactly — maxTurn(0.1) = 0.1432 is only the
	# ceiling, not the applied turn.
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.now = 100.0
	ctrl.set_ai(0.0, 1.0, 0.1)
	s.update(1.0 / 60.0, ctrl)
	t.eq_float("wobble offsets the target", s.turn_amount, 0.1)
	t.eq_float("wobble turns the heading", s.heading, 0.1)

	# A wobble beyond the per-frame cap still obeys the cap (maxTurn(0.5)).
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.now = 100.0
	ctrl.set_ai(0.0, 1.0, 0.5)
	s.update(1.0 / 60.0, ctrl)
	t.eq_float("wobble is clamped by the turn cap", s.turn_amount, 0.1495580992616398)
	t.eq_float("capped wobble heading", s.heading, 0.1495580992616398)

	# ---- respawn freeze ---------------------------------------------------
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.freeze_until = 10.0
	s.immune_until = 0.0
	s.now = 5.0
	var before: Vector2 = s.body[0]
	ctrl.set_player(1.0, 1.0)
	s.update(1.0 / 60.0, ctrl)
	t.ok("frozen snake does not move", s.body[0].is_equal_approx(before))
	t.eq_float("frozen snake takes the heading directly", s.heading, 1.0)
	t.eq_float("frozen snake reports no turn", s.turn_amount, 0.0)
	t.ok("frozen snake is immune", s.is_immune())
	t.ok("frozen snake is frozen", s.is_frozen())
	s.now = 11.0
	t.ok("unfrozen after the window", not s.is_frozen())

	# ---- wall / clamp -----------------------------------------------------
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.body[0] = Vector2(5.0, 500.0)
	t.ok("hit wall on the left", s.hit_wall())
	s.body[0] = Vector2(4795.0, 500.0)
	t.ok("hit wall on the right", s.hit_wall())
	s.body[0] = Vector2(500.0, 2695.0)
	t.ok("hit wall at the bottom", s.hit_wall())
	s.clamp_to_world()
	t.eq_float("clamped to wall pad", s.body[0].y, 2700.0 - cfg.snake.wall_pad)
	t.ok("inside the world after clamp", not s.hit_wall())

	# ---- self hit ---------------------------------------------------------
	# `hit_self()` is an entity query, kept intact: the *game rule* only consults
	# it when `cfg.collide.self_kill` is switched on (default off = harmless
	# overlap, see suite_collisions). The geometry below is still pinned because
	# the legacy mode and the AI's own self-avoidance heuristics rely on it.
	s.reset(1000.0, 1000.0, 0.0, 40)
	s.body[20] = s.body[0]
	t.ok("head inside body[20] is a self hit", s.hit_self())
	t.ok("AI forgiveness: same spot with skip 12 still hits", s.hit_self(12, 0.45))
	s.reset(1000.0, 1000.0, 0.0, 40)
	s.body[3] = s.body[0]
	t.ok("neck nodes inside skip are ignored", not s.hit_self())
	t.ok("neck nodes count when skip is lowered", s.hit_self(2, 0.62))
	# Radius matters: a fat snake hits from farther away.
	s.reset(1000.0, 1000.0, 0.0, 120)
	s.body[30] = s.body[0] + Vector2(20.0, 0.0)
	t.ok("fat snake hits at 20 px", s.hit_self())
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.body[12] = s.body[0] + Vector2(20.0, 0.0)
	t.ok("thin snake misses at 20 px", not s.hit_self())

	# ---- buffs ------------------------------------------------------------
	s.reset(1000.0, 1000.0, 0.0, 16)
	t.ok("no boost at start", not s.has_buff(PSSnake.BUFF_BOOST))
	s.apply_buff(PSSnake.BUFF_BOOST, 5.0)
	t.eq_float("boost left", s.buff_left(PSSnake.BUFF_BOOST), 5.0)
	s.apply_buff(PSSnake.BUFF_BOOST, 3.0)
	t.eq_float("same buff does not shrink", s.buff_left(PSSnake.BUFF_BOOST), 5.0)
	s.apply_buff(PSSnake.BUFF_MAGNET, 4.0)
	t.ok("magnet active", s.has_buff(PSSnake.BUFF_MAGNET))
	s.tick_buffs(2.0)
	t.eq_float("boost ticks down", s.buff_left(PSSnake.BUFF_BOOST), 3.0)
	t.eq_float("magnet ticks down", s.buff_left(PSSnake.BUFF_MAGNET), 2.0)
	s.tick_buffs(100.0)
	t.eq_float("buff floors at zero", s.buff_left(PSSnake.BUFF_BOOST), 0.0)
	t.ok("buff inactive at zero", not s.has_buff(PSSnake.BUFF_BOOST))
	s.apply_buff(PSSnake.BUFF_BOOST, 5.0)
	s.clear_buffs()
	t.ok("clear_buffs drops everything", not s.has_buff(PSSnake.BUFF_BOOST))
	s.clear_buffs()
	s.reset(1000.0, 1000.0, 0.0, 16)
	s.apply_buff(PSSnake.BUFF_BOOST, 5.0)
	s.reset(1000.0, 1000.0, 0.0, 16)
	t.ok("respawn clears buffs", not s.has_buff(PSSnake.BUFF_BOOST))

	# ---- presentation helpers --------------------------------------------
	s.reset(1000.0, 1000.0, 0.0, 20)
	s.now = 100.0
	ctrl.set_player(0.0, 1.0)
	s.update(1.0 / 60.0, ctrl)
	var pts := s.render_points()
	t.eq_int("render points match body", pts.size(), s.length())
	t.eq_float("render head is the real head", pts[0].x, s.body[0].x, 1e-5)
	var stride := s.scatter_step(cfg.food.scatter_max)
	t.eq_int("scatter stride for 20 nodes", stride, 1)
	t.eq_int("scatter positions count", s.scatter_positions(cfg.food.scatter_max).size(), 20)
	s.grow(180)
	t.eq_int("scatter stride caps the count", s.scatter_step(cfg.food.scatter_max), 4)
	t.le("scatter count stays under the cap", s.scatter_positions(64).size(), 64)

	t.end_suite()
