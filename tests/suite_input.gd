extends RefCounted
## Suite: the steering input contract (pose dead zone / speed mapping / keyboard),
## the BINDING phase (`PSPoseInput.bound_ids`, Fix 1) and the motion gate
## (`pose.motion`, Fix 2).

const PSConfig = preload("res://src/core/config.gd")
const PSPoseSteer = preload("res://src/core/pose_steer.gd")
const PSPoseInput = preload("res://src/present/ps_pose_input.gd")
const PSKeyboardSteer = preload("res://src/core/keyboard_steer.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")

## Image size the binding proof feeds the bridge frame with (the real capture size).
const BIND_W := 1920
const BIND_H := 1080
## Frame clock of the scripted binding scenes (60 Hz, like the pose trace).
const BIND_DT := 1.0 / 60.0


## Synthetic youdoo18 body for the binding scenes, in PROVIDER space: the person
## stands at game-x `gx` (0..1, mirrored), all 18 points visible, torso 0.26 of the
## image height (so `_plausible()` accepts it and the torso is ~285 px). Two people
## at 0.25 / 0.75 are exactly the READY left/right slot panes.
static func _body(gx: float) -> Dictionary:
	var px := 1.0 - gx                      # game x -> provider x (mirror_x = ON)
	var sho := 0.30
	var hip := 0.56
	var r := 0.070
	return {"kpts": [
		[px, sho - 0.16, 0.0, 1.0],          # 0 nose
		[px - 0.02, sho - 0.17, 0.0, 1.0],   # 1 L eye
		[px + 0.02, sho - 0.17, 0.0, 1.0],   # 2 R eye
		[px - 0.04, sho - 0.16, 0.0, 1.0],   # 3 L ear
		[px + 0.04, sho - 0.16, 0.0, 1.0],   # 4 R ear
		[px - r, sho, 0.0, 1.0],             # 5 L shoulder
		[px + r, sho, 0.0, 1.0],             # 6 R shoulder
		[px - r - 0.03, sho + 0.13, 0.0, 1.0],  # 7 L elbow
		[px + r + 0.07, sho + 0.06, 0.0, 1.0],  # 8 R elbow
		[px - r - 0.06, sho + 0.26, 0.0, 1.0],  # 9 L wrist (hanging)
		# RIGHT wrist out to the side, level with the shoulder: dist_n ~0.95 (outside
		# the 0.70 dead zone) and dy_n < 0 (outside the hanging cone), so the mapper
		# actually PUBLISHES an angle. A hanging right arm would never set
		# `has_angle`, and then "coast on the last heading" has nothing to coast on.
		[px + r + 0.14, sho - 0.02, 0.0, 1.0],  # 10 R wrist
		[px - 0.045, hip, 0.0, 1.0],         # 11 L hip
		[px + 0.045, hip, 0.0, 1.0],         # 12 R hip
		[px - 0.05, hip + 0.12, 0.0, 1.0],   # 13 L knee
		[px + 0.05, hip + 0.12, 0.0, 1.0],   # 14 R knee
		[px - 0.05, hip + 0.24, 0.0, 1.0],   # 15 L ankle
		[px + 0.05, hip + 0.24, 0.0, 1.0],   # 16 R ankle
		[px, sho + 0.13, 0.0, 1.0],          # 17 chest
	]}


## Build a bridge frame EXACTLY the way the device delivers it.
##
## `YoudooBridge.latest_frame()` is a `JSON.parse_string()` result, so the
## `persons` keys are STRINGS ("0", "3", ...) and every number is a float. A suite
## that injects a native int-keyed dictionary exercises a shape the device never
## produces: on 2026-11-14 that hid the WAITING slot never processing its
## candidate (every `[pose]` line said `torso=0 hand=- reason=unbound`, `stable`
## grew for 76 s and the READY raise never completed) while this suite stayed
## green. `device_shape=false` keeps the int-key shape covered as well, so neither
## can regress silently.
static func _frame(bodies: Dictionary, device_shape: bool = true) -> Dictionary:
	var persons := {}
	for id in bodies:
		if device_shape:
			persons[str(int(id))] = _body(float(bodies[id]))
		else:
			persons[int(id)] = _body(float(bodies[id]))
	var f: Dictionary = {"imageWidth": BIND_W, "imageHeight": BIND_H, "persons": persons}
	if not device_shape:
		return f
	return JSON.parse_string(JSON.stringify(f))


## Run `frames` bridge frames through the REAL binding FSM (the same entry point
## `poll()` uses) and return the advanced clock.
static func _run(pin, t: float, frames: int, f: Dictionary, count: int = 2) -> float:
	for k in frames:
		pin.poll_frame(t, count, f)
		t += BIND_DT
	return t


## Run `frames` identical pose frames (1/60 s apart) through the mapper so the
## speed low-pass (0.09 s) and the 3/s slew limit settle, and return the
## published multiplier. `left` may be null (one-arm call); the two visibilities
## are passed straight through.
static func _settle(pose, out, right: Vector2, left, ref: Vector2, torso: float,
		t0: float, frames: int = 60, r_vis: float = 1.0, l_vis: float = 1.0) -> float:
	var tt := t0
	for k in frames:
		tt += 1.0 / 60.0
		pose.update_wrist(right, ref, torso, tt, out, left, ref, r_vis, l_vis)
	return out.speed_scale


static func run(t) -> void:
	t.suite("input")
	var cfg = PSConfig.new()
	var pose = PSPoseSteer.new(cfg)
	var out = PSSteerInput.new()
	var torso := 200.0
	var center := Vector2(500.0, 500.0)

	# ---- first tracked frame: angle + full speed --------------------------
	# NOTE (2026-11-14, right-shoulder reference): the probe distances below are
	# expressed on the NEW shoulder scale - `pose.speed.far` is 0.92 (2026-11-17,
	# was 1.10) and the dead zone is 0.70 - but every assertion still means exactly
	# what it did before (far -> max speed, near -> min speed, 90 deg -> PI/2, ...).
	# Only the numbers changed, not the contract; the count stays 448.
	pose.reset()
	pose.update_wrist(center + Vector2(1.10 * torso, 0.0), center, torso, 1.0, out)
	t.eq_float("angle to the right is 0", out.steer_angle_rad, 0.0, 1e-12)
	t.ok("valid pose frame", out.valid)
	t.ok("not a hold frame", not out.hold)
	t.eq_float("deadzone passed -> confidence 1", out.confidence, 1.0)
	t.eq_float("dist_n past far -> max speed", out.speed_scale, 1.80)
	t.eq_float("dist_n reported", pose.last_dist_n, 1.10, 1e-6)
	t.ok("usable", out.is_usable())

	# ---- directions follow the canvas convention --------------------------
	pose.reset()
	pose.update_wrist(center + Vector2(0.0, -torso), center, torso, 2.0, out)
	t.eq_float("wrist up is -PI/2", out.steer_angle_rad, -PI * 0.5, 1e-9)
	pose.reset()
	pose.update_wrist(center + Vector2(-torso, 0.0), center, torso, 2.0, out)
	t.eq_float("wrist left is PI", absf(out.steer_angle_rad), PI, 1e-9)
	# DELIBERATE DEFAULT CHANGE (2026-11-14, owner option B 下垂识别): a wrist
	# straight below the reference is no longer a steering direction - it is the
	# ARM-HANGING gesture, and `pose.hang_*` freezes the published angle (the old
	# "wrist down is +PI/2" probe would now be held). The canvas y-down convention
	# is proved with the gesture the owner asked to KEEP: press down-and-OUTWARD,
	# dy = 0.75 torso with abs(dx) = 0.75 of the vector (48.6 deg out of vertical,
	# outside the 26.7 deg hang cone). One assertion covers both halves of the
	# change, so the suite count stays 444; the hysteresis itself is measured
	# frame by frame in evidence/pose-trace-hang-*.txt (gesture `hang_sweep`).
	pose.reset()
	pose.update_wrist(center + Vector2(cos(0.5), sin(0.5)) * (0.90 * torso),
		center, torso, 2.0, out)                                  # publishes ~+0.5 rad
	var published: float = out.steer_angle_rad
	pose.update_wrist(center + Vector2(0.0, 0.98 * torso), center, torso, 2.05, out)
	var hang_ok: bool = pose.last_hang and out.valid and out.confidence == 0.0 \
		and out.steer_angle_rad == published
	var down_out := PI * 0.5 - asin(0.75)                          # 41.41 deg
	var down_out_d := 0.75 / sin(down_out)                         # 1.1339 torso
	pose.reset()
	pose.update_wrist(center + Vector2(cos(down_out), sin(down_out)) * (down_out_d * torso),
		center, torso, 2.10, out)
	var steer_ok: bool = (not pose.last_hang) and out.confidence == 1.0 \
		and absf(out.steer_angle_rad - down_out) < 1e-6
	t.ok("hanging arm holds, down-and-out steers down", hang_ok and steer_ok)

	# ---- dead zone: hand resting on the chest holds the last angle --------
	pose.reset()
	pose.update_wrist(center + Vector2(1.10 * torso, 0.0), center, torso, 3.0, out)
	t.eq_float("good frame angle", out.steer_angle_rad, 0.0, 1e-9)
	# `pose.deadzone` is 0.70 (was 0.12, when the origin was the chest): the gate
	# reads the RAW wrist distance from the REFERENCE, so this 0.04-of-a-torso
	# hand is inside it on the very first frame.
	var inside := center + Vector2(torso * 0.04, 0.0)   # dist_n = 0.04 < 0.70
	pose.update_wrist(inside, center, torso, 3.05, out)
	# (valid + conf 0 merged into one assertion in the motion pass so the count
	# stays 444; the motion test below proves the SAME frame pair is still held.)
	t.ok("dead zone keeps the pose valid with confidence 0", out.valid and out.confidence == 0.0)
	t.eq_float("dead zone holds the last angle", out.steer_angle_rad, 0.0, 1e-9)
	t.ok("dead zone reported", not pose.last_deadzone_pass)
	# ... and it does not corrupt the speed: the previous target is kept and the
	# low-pass keeps chasing it.
	# 2026-11-17 (speed symmetry): the steering holds no longer FREEZE the speed
	# target - the dead zone / hang / motion gates are steering gates and the
	# speed curve reads the wrist distance (max over the usable arms). One held
	# frame therefore starts easing the speed down (smooth 0.09 s + 3/s slew),
	# but cannot jump to the minimum in a single frame.
	t.gt("speed starts easing inside the dead zone", out.speed_scale, 1.3)
	t.lt("speed does not snap to the minimum in one held frame", out.speed_scale, 1.8)

	# ---- distance -> speed mapping ----------------------------------------
	# First frame snaps to the target (no previous sample => dt 0 => alpha 1).
	# 2026-11-17: `far` moved 1.10 -> 0.92, so the two probes below moved with it
	# (0.92 is now the far end, the old 0.95 mid-probe is now past `far`, so the
	# midway probe is 0.86 = (0.80+0.92)/2). Same assertions, same numbers.
	pose.reset()
	pose.update_wrist(center + Vector2(0.80 * torso, 0.0), center, torso, 4.0, out)
	t.eq_float("dist_n 0.80 (near) -> min speed", out.speed_scale, 0.65, 1e-9)
	pose.reset()
	pose.update_wrist(center + Vector2(0.92 * torso, 0.0), center, torso, 4.0, out)
	t.eq_float("dist_n 0.92 (far) -> max speed", out.speed_scale, 1.80, 1e-9)
	pose.reset()
	pose.update_wrist(center + Vector2(0.86 * torso, 0.0), center, torso, 4.0, out)
	t.eq_float("dist_n midway -> mid speed", out.speed_scale, 1.225, 1e-9)
	pose.reset()
	pose.update_wrist(center + Vector2(3.0 * torso, 0.0), center, torso, 4.0, out)
	t.eq_float("far reach clamps to max", out.speed_scale, 1.80, 1e-9)

	# ---- speed distance = the MORE EXTENDED arm (2026-11-17) --------------
	# Owner: 右手向右伸很快, 向左/向上伸就慢, 抬左臂完全没用. The curve now reads
	#     speed_dist = max(|rwr - rsh|, |lwr - lsh|) / torso
	# while steering stays right-wrist/right-shoulder only. The two wrists are
	# passed relative to the same abstract centre here: the mapper only needs the
	# two arm lengths, the reference for the left arm is its own shoulder.
	var lhang := center + Vector2(0.0, 0.98 * torso)        # left arm hanging
	var lreach := center + Vector2(-0.95 * torso, 0.0)      # left arm out to the left
	var lup := center + Vector2(0.0, -0.95 * torso)         # left arm raised
	var lbent := center + Vector2(-0.30, 0.10) * torso       # bent, near its shoulder
	# The old chest direction from the right shoulder (|v| = 0.5845 torso), which
	# is inside the 0.70 dead zone: it may HOLD the angle but must not hide the
	# speed distance from the other arm.
	var chest_v := Vector2(cos(2.509), sin(2.509)) * 0.5845
	pose.reset()
	pose.update_wrist(center + Vector2(0.80 * torso, 0.0), center, torso, 20.0, out,
		lhang, center)
	var s_low := _settle(pose, out, center + Vector2(0.80 * torso, 0.0), lhang,
		center, torso, 20.0)
	t.eq_float("low extension on both arms -> min speed", s_low, 0.65, 1e-3)
	# Right arm HANGING (passive) + left arm reaching: the left arm alone must
	# reach max speed. That is exactly the gesture the owner could not feel.
	var s_left := _settle(pose, out, center + Vector2(0.0, 0.98 * torso), lreach,
		center, torso, 20.6)
	t.eq_float("left reach (right arm hanging) -> max speed", s_left, 1.80, 1e-3)
	t.eq_int("...the left arm is the speed source", pose.last_speed_arm, 1)
	var s_up := _settle(pose, out, center + Vector2(0.0, 0.98 * torso), lup,
		center, torso, 21.2)
	t.eq_float("raised left arm -> max speed", s_up, 1.80, 1e-3)
	t.eq_int("...the left arm is the speed source (raised)", pose.last_speed_arm, 1)
	# Side effect guard: with max(), a left arm that is BENT near its shoulder -
	# or hanging - must NOT raise the speed while the right hand steers at the
	# chest. Both are either below `near` or a passive arm.
	pose.reset()
	pose.update_wrist(center + chest_v * torso, center, torso, 22.0, out, lhang, center)
	var s_bent := _settle(pose, out, center + chest_v * torso, lbent,
		center, torso, 22.0)
	t.eq_float("bent left arm near the shoulder -> min speed", s_bent, 0.65, 1e-3)
	pose.reset()
	pose.update_wrist(center + chest_v * torso, center, torso, 23.0, out, lhang, center)
	var s_hang := _settle(pose, out, center + chest_v * torso, lhang,
		center, torso, 23.0)
	t.eq_float("hanging left arm -> min speed (passive arm ignored)", s_hang, 0.65, 1e-3)
	# A wrist below `min_visibility` is ignored for speed: fall back to the other
	# arm (here the right one is pulled in, so the result is the minimum).
	pose.reset()
	pose.update_wrist(center + Vector2(0.40 * torso, 0.0), center, torso, 24.0, out,
		lreach, center, 1.0, 0.10)
	var s_inv := _settle(pose, out, center + Vector2(0.40 * torso, 0.0), lreach,
		center, torso, 24.0, 60, 1.0, 0.10)
	t.eq_float("invisible left wrist is ignored for speed", s_inv, 0.65, 1e-3)
	t.eq_int("...speed falls back to the right arm", pose.last_speed_arm, 0)
	# BOTH arms invisible: the last target is kept (no curve evaluation at all).
	pose.reset()
	pose.update_wrist(center + Vector2(1.10 * torso, 0.0), center, torso, 25.0, out,
		lreach, center)
	pose.update_wrist(center + Vector2(0.04 * torso, 0.0), center, torso, 25.02, out,
		lreach, center, 0.0, 0.0)
	t.eq_float("both wrists invisible -> last speed kept", out.speed_scale, 1.80, 1e-9)

	# ---- speed smoothing + slew limit -------------------------------------
	pose.reset()
	pose.update_wrist(center + Vector2(0.80 * torso, 0.0), center, torso, 5.0, out)
	t.eq_float("smoothing start", out.speed_scale, 0.65, 1e-9)
	# jump the hand out: the target is 1.8 but one frame may only move slew*dt
	pose.update_wrist(center + Vector2(1.5 * torso, 0.0), center, torso, 5.0 + 1.0 / 60.0, out)
	t.eq_float("slew limits one frame", out.speed_scale, 0.65 + 3.0 / 60.0, 1e-6)
	# a long frame lets it move further
	pose.update_wrist(center + Vector2(1.5 * torso, 0.0), center, torso, 5.0 + 0.2, out)
	t.lt("speed keeps rising", out.speed_scale, 1.80)
	t.gt("speed rose", out.speed_scale, 0.65 + 3.0 / 60.0)

	# ---- dropout: hold the last angle, then report "no input" ------------
	pose.reset()
	pose.update_wrist(center + Vector2(1.10 * torso, 0.0), center, torso, 10.0, out)
	pose.mark_lost(10.5, out)
	# (holds + usable + not-fresh merged into one assertion: the count must stay
	# 444 after the binding/motion blocks below.)
	t.ok("dropout inside the window holds, usable but not fresh",
		out.hold and out.is_usable() and not out.valid)
	t.eq_float("held angle is the last good one", out.steer_angle_rad, 0.0, 1e-9)
	t.eq_float("hold confidence is 0", out.confidence, 0.0)
	pose.mark_lost(11.5, out)
	t.ok("dropout past the timeout releases", not out.hold)
	t.ok("stale input is unusable", not out.is_usable())

	# ---- bridge-direct angle ---------------------------------------------
	pose.reset()
	pose.set_angle_direct(2.5, 0.9, 12.0, out)
	t.eq_float("direct angle passed through", out.steer_angle_rad, 2.5)
	t.eq_float("direct speed passed through", out.speed_scale, 0.9)
	t.ok("direct angle usable", out.is_usable())
	pose.set_angle_direct(2.5, 99.0, 12.0, out)
	t.eq_float("direct speed clamps to max", out.speed_scale, 1.80)

	# ---- keyboard fallback: 4 axes + 4 diagonals -------------------------
	t.eq_float("kb right", PSKeyboardSteer.angle_for_mask(PSKeyboardSteer.RIGHT), 0.0, 1e-12)
	t.eq_float("kb down", PSKeyboardSteer.angle_for_mask(PSKeyboardSteer.DOWN), PI * 0.5, 1e-12)
	t.eq_float("kb left", PSKeyboardSteer.angle_for_mask(PSKeyboardSteer.LEFT), PI, 1e-12)
	t.eq_float("kb up", PSKeyboardSteer.angle_for_mask(PSKeyboardSteer.UP), -PI * 0.5, 1e-12)
	t.eq_float("kb right+down", PSKeyboardSteer.angle_for_mask(
		PSKeyboardSteer.RIGHT | PSKeyboardSteer.DOWN), PI * 0.25, 1e-12)
	t.eq_float("kb left+down", PSKeyboardSteer.angle_for_mask(
		PSKeyboardSteer.LEFT | PSKeyboardSteer.DOWN), PI * 0.75, 1e-12)
	t.eq_float("kb left+up", PSKeyboardSteer.angle_for_mask(
		PSKeyboardSteer.LEFT | PSKeyboardSteer.UP), -PI * 0.75, 1e-12)
	t.eq_float("kb right+up", PSKeyboardSteer.angle_for_mask(
		PSKeyboardSteer.RIGHT | PSKeyboardSteer.UP), -PI * 0.25, 1e-12)
	t.ok("kb opposite cancels", is_nan(PSKeyboardSteer.angle_for_mask(
		PSKeyboardSteer.RIGHT | PSKeyboardSteer.LEFT)))
	t.ok("kb empty mask", is_nan(PSKeyboardSteer.angle_for_mask(0)))

	var kb = PSKeyboardSteer.new()
	t.ok("kb idle produces nothing", not kb.update(20.0, out))
	t.ok("kb accepts a direction", kb.set_dirs(PSKeyboardSteer.RIGHT | PSKeyboardSteer.DOWN, 20.0))
	t.ok("kb publishes while held", kb.update(20.5, out))
	t.ok("kb input is valid at speed 1.0", out.valid and out.speed_scale == 1.0)
	t.eq_float("kb angle", out.steer_angle_rad, PI * 0.25, 1e-12)
	t.gt("kb hold window", kb.hold_left(20.5), 3.0)
	t.ok("kb hold expired after 4 s", not kb.update(24.1, out))
	var held_angle: float = kb.angle
	kb.set_dirs(PSKeyboardSteer.UP | PSKeyboardSteer.DOWN, 30.0)
	t.eq_float("cancelling dirs keep the last angle", kb.angle, held_angle)

	# ---- input struct helpers --------------------------------------------
	out.clear()
	t.ok("cleared input is unusable", not out.is_usable())
	t.eq_float("cleared speed is 1", out.speed_scale, 1.0)
	var other = PSSteerInput.new()
	other.set_pose(1.25, 1.1, 0.8)
	out.copy_from(other)
	t.eq_float("copy angle", out.steer_angle_rad, 1.25)
	t.eq_float("copy speed", out.speed_scale, 1.1)
	t.eq_float("copy confidence", out.confidence, 0.8)

	# =====================================================================
	# Fix 1 - BINDING PHASE. A slot owns a PERSON ID, not a screen position.
	# Every stage runs through the shipped FSM (`PSPoseInput.poll_frame`), so the
	# `[bind]` lines this prints are the device log's own format.
	# =====================================================================
	# (a) READY: two people, one in each half -> slot 0 owns id 3, slot 1 owns 7.
	var pin = PSPoseInput.new(cfg, null)
	pin.set_phase(&"ready")
	var bt := 0.0
	var two := _frame({3: 0.25, 7: 0.75})
	bt = _run(pin, bt, 6, two)                       # candidates appear
	pin.set_slot_raise_ok(0, true, 1.52)
	pin.set_slot_raise_ok(1, true, 1.50)
	bt = _run(pin, bt, 40, two)                      # 0.67 s stable + raise done
	var ready_bound: bool = int(pin.bound_ids[0]) == 3 and int(pin.bound_ids[1]) == 7 \
		and pin.tracked_slots == 2 and int(pin.bind_state[0]) == PSPoseInput.BIND_BOUND
	# (b) mid-round the two players SWAP halves: the slots must NOT swap.
	pin.set_phase(&"play")
	var swapped := _frame({3: 0.75, 7: 0.25})
	bt = _run(pin, bt, 30, swapped)
	var no_rebind: bool = int(pin.bound_ids[0]) == 3 and int(pin.bound_ids[1]) == 7 \
		and pin.tracked_slots == 2
	# (c) walking across BEFORE binding must not bind one id to both slots.
	var pin2 = PSPoseInput.new(cfg, null)
	pin2.set_phase(&"ready")
	pin2.set_slot_raise_ok(0, true, 1.50)
	pin2.set_slot_raise_ok(1, true, 1.50)
	var t2 := _run(pin2, 0.0, 12, _frame({3: 0.25, 7: 0.75}))   # 0.2 s, unstable
	t2 = _run(pin2, t2, 12, _frame({3: 0.75, 7: 0.25}))         # they cross
	t2 = _run(pin2, t2, 60, _frame({3: 0.75, 7: 0.25}))         # 1.0 s stable
	var unique_bind: bool = int(pin2.bound_ids[0]) == 7 \
		and int(pin2.bound_ids[1]) == 3 \
		and int(pin2.bound_ids[0]) != int(pin2.bound_ids[1])
	t.ok("binding: READY binds per half, a mid-round swap never rebinds, crossing before binding binds once each",
		ready_bound and no_rebind and unique_bind)

	# (d) the bound person leaves -> coast within the grace, then LOST; a third
	# person walking into that half must NOT steal the slot; only READY (after the
	# 3 s absence) may re-bind, and then to the new person.
	var gone := _frame({7: 0.75, 9: 0.25})
	bt = _run(pin, bt, 30, gone)                     # 0.5 s inside grace
	var coast_dbg := "bound=%s seen=%s hold=%s slots=%d absent=%.2f" % [
		str(pin.bound_ids), str(pin.slot_seen), str(pin.steers[0].hold),
		pin.tracked_slots, float(pin._absent_t[0])]
	var coast: bool = int(pin.bound_ids[0]) == 3 and not pin.slot_seen[0] \
		and pin.steers[0].hold and pin.tracked_slots == 1
	bt = _run(pin, bt, 45, gone)                     # past grace 1.0 s
	var lost: bool = int(pin.bound_ids[0]) == 3 and not pin.steers[0].hold \
		and not pin.slot_seen[0] and pin.tracked_slots == 1
	var steal: bool = int(pin.bound_ids[0]) == 3 and int(pin.bound_ids[1]) == 7
	pin.set_phase(&"ready")                          # re-arm: raise must happen again
	bt = _run(pin, bt, 200, gone)                    # 3.3 s -> unbind
	# After the release the slot is FREE: `_unbind` leaves it in WAITING, and the
	# person still standing there immediately starts a new candidate window (that
	# is the whole point of the WAITING->CANDIDATE ladder), so the assertion is
	# "not bound any more", not "back to WAITING".
	var unbound: bool = int(pin.bound_ids[0]) == -1 \
		and int(pin.bind_state[0]) != PSPoseInput.BIND_BOUND
	pin.set_slot_raise_ok(0, true, 1.50)
	bt = _run(pin, bt, 40, gone)                     # 0.67 s -> binds id 9
	var rebound: bool = int(pin.bound_ids[0]) == 9 and int(pin.bound_ids[1]) == 7
	t.ok("binding: grace coast -> lost, a third person cannot steal the slot",
		coast and lost and steal,
		"coast=%s lost=%s steal=%s | at coast: %s" % [
			str(coast), str(lost), str(steal), coast_dbg])
	t.ok("binding: READY-only rebind after the 3 s absence", unbound and rebound,
		"unbound=%s rebound=%s bound=%s state=%s" % [
			str(unbound), str(rebound), str(pin.bound_ids), str(pin.bind_state)])

	# =====================================================================
	# Fix 1b - REGRESSION (2026-11-14 device deadlock). A WAITING slot must still
	# SELECT and FULLY PROCESS the person standing in its area; that person is a
	# candidate (never published as bound) and is the only way the READY raise can
	# be confirmed. Every frame here is device-shaped (JSON: string person keys),
	# which is the shape `YoudooBridge.latest_frame()` actually returns.
	# Before the fix this exact scene printed, for ever:
	#   [pose] ... hand=- dist_n=0.00 torso=0 reason=unbound s0=false slots=0
	#   [bind] phase=ready bound=-1,-1 state=wait cand=0 stable=76.88
	# =====================================================================
	var pw = PSPoseInput.new(cfg, null)
	pw.set_phase(&"ready")
	var one := _frame({5: 0.5})                      # one person, standing still
	var tw := _run(pw, 0.0, 12, one, 1)              # 0.20 s
	var waiting_map: bool = bool(pw.slot_seen[0]) and pw.tracked_slots == 1 \
		and int(pw.bind_state[0]) == PSPoseInput.BIND_WAITING \
		and int(pw.bound_ids[0]) == -1 \
		and float(pw.diag["torso"]) > 100.0 and String(pw.diag["hand"]) == "right" \
		and String(pw.diag["reason"]) == "" and pw.steers[0].is_usable()
	t.ok("binding: WAITING maps+publishes its candidate (seen/hand-up usable, not bound)",
		waiting_map, "seen=%s slots=%d state=%d bound=%d torso=%.0f hand=%s reason=%s valid=%s" % [
			str(pw.slot_seen), pw.tracked_slots, int(pw.bind_state[0]),
			int(pw.bound_ids[0]), float(pw.diag["torso"]), String(pw.diag["hand"]),
			String(pw.diag["reason"]), str(pw.steers[0].valid)])
	# `bind.stable_sec` (0.5 s) later the same person is a CANDIDATE, still unbound.
	tw = _run(pw, tw, 30, one, 1)                    # 0.70 s total
	var ladder_cand: bool = int(pw.bind_state[0]) == PSPoseInput.BIND_CANDIDATE \
		and int(pw.bound_ids[0]) == -1 and bool(pw.slot_seen[0]) \
		and float(pw._cand_t[0]) >= cfg.pose.bind.stable_sec
	t.ok("binding: stable for bind.stable_sec -> CANDIDATE (bound only by the raise)",
		ladder_cand, "state=%d bound=%d stable=%.2f seen=%s" % [
			int(pw.bind_state[0]), int(pw.bound_ids[0]), float(pw._cand_t[0]),
			str(pw.slot_seen[0])])
	# The READY raise confirmation (`ready_state == 2`) is the only thing that may
	# freeze the id: CANDIDATE -> BOUND, on that id, exactly once.
	pw.set_slot_raise_ok(0, true, 1.50)
	tw = _run(pw, tw, 2, one, 1)
	var ladder_bound: bool = int(pw.bind_state[0]) == PSPoseInput.BIND_BOUND \
		and int(pw.bound_ids[0]) == 5 and bool(pw.slot_seen[0]) \
		and pw.bind_count == 1 and pw.tracked_slots == 1
	t.ok("binding: raise confirmation -> BOUND (wait -> cand -> bound, one id)",
		ladder_bound, "state=%d bound=%d binds=%d seen=%s slots=%d" % [
			int(pw.bind_state[0]), int(pw.bound_ids[0]), pw.bind_count,
			str(pw.slot_seen[0]), pw.tracked_slots])
	# Neither key shape may regress: editor harnesses still hand in int keys.
	var pi = PSPoseInput.new(cfg, null)
	pi.set_phase(&"ready")
	_run(pi, 0.0, 12, _frame({5: 0.5}, false), 1)
	t.ok("binding: int-key frames (editor/preview harnesses) map the candidate too",
		bool(pi.slot_seen[0]) and int(pi.bind_state[0]) == PSPoseInput.BIND_WAITING
			and String(pi.diag["hand"]) == "right",
		"seen=%s state=%d hand=%s" % [str(pi.slot_seen), int(pi.bind_state[0]),
			String(pi.diag["hand"])])

	# =====================================================================
	# Fix 2 - MOTION AWARENESS. A fast sweep suppresses BOTH position holds so
	# the published angle follows the hand; a resting hand still holds.
	# =====================================================================
	var mpose = PSPoseSteer.new(cfg)
	var mout = PSSteerInput.new()
	var mcen := Vector2(500.0, 500.0)
	var mtor := 200.0
	# (a) static: the same "hand arrives at the chest" frame pair as the dead-zone
	# block above - it must still hold (bit-identical: same angle, conf 0).
	mpose.reset()
	mpose.update_wrist(mcen + Vector2(1.10 * mtor, 0.0), mcen, mtor, 1.0, mout)
	var a_before: float = mout.steer_angle_rad
	mpose.update_wrist(mcen + Vector2(0.04 * mtor, 0.0), mcen, mtor, 1.05, mout)
	var still_holds: bool = (not mpose.last_deadzone_pass) and not mpose.last_motion_free \
		and mout.steer_angle_rad == a_before and mout.confidence == 0.0
	# (b) fast sweep at chest height: 2.6 torso of travel in 0.35 s (7.4 torso/s)
	# through the dead zone. Both holds are overridden, the angle moves > 90 deg.
	mpose.reset()
	mpose.update_wrist(mcen + Vector2(-1.30 * mtor, 0.345 * mtor), mcen, mtor, 2.0, mout)
	var a_start: float = mout.steer_angle_rad
	var free_frames := 0
	var dz_seen := false
	for k in 30:
		var tt: float = 2.0 + 0.0167 * float(k + 1)
		var u: float = -1.30 + 2.60 * clampf((tt - 2.0) / 0.35, 0.0, 1.0)
		mpose.update_wrist(mcen + Vector2(u * mtor, 0.345 * mtor), mcen, mtor, tt, mout)
		if mpose.last_motion_free:
			free_frames += 1
		if not mpose.last_deadzone_pass:
			dz_seen = true
	var a_end: float = mout.steer_angle_rad
	var swept: bool = free_frames >= 10 and dz_seen \
		and absf(wrapf(a_end - a_start, -PI, PI)) > PI * 0.5
	# (c) a SLOW move inside the hold (0.4 torso/s) must NOT trip the gate.
	mpose.reset()
	mpose.update_wrist(mcen + Vector2(0.30 * mtor, 0.0), mcen, mtor, 3.0, mout)
	var slow_free := false
	for k in 20:
		var st: float = 3.0 + 0.0167 * float(k + 1)
		mpose.update_wrist(mcen + Vector2((0.30 + 0.0067 * float(k + 1)) * mtor, 0.0),
			mcen, mtor, st, mout)
		if mpose.last_motion_free:
			slow_free = true
	t.ok("motion: a fast sweep overrides the dead zone, a resting hand and a slow drift still hold",
		still_holds and swept and not slow_free)

	t.end_suite()
