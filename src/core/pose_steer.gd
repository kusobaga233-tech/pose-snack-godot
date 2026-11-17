extends RefCounted
## Body-motion -> steering mapper (JS `PoseTracker._processPose`, input half).
##
## The bridge (workstream A) converts the SDK skeleton into three numbers per
## frame: the mirrored **wrist** position, the **steering reference** (the right
## shoulder since 2026-11-14, the chest before that), and the **torso scale** in
## pixels (used to normalise for build / distance to the camera). This class turns
## those into the `PSSteerInput` contract:
##
##   1. **wrist + reference 2D low-pass** (`pose.wrist_smooth`): one exponential
##      filter per signal, allocation-free. Only the *direction* maths below uses
##      the filtered vector; `dist_n` stays on the raw wrist so the dead-zone gate
##      and the speed curve react as fast as the tracker (see "Why raw distance").
##   2. angle_raw = atan2(wrist - ref)                        (0 = right, +PI/2 = down)
##   3. **circular low-pass** on that angle (`pose.angle_smooth`): unwrap relative
##      to the running filtered angle, filter, wrap. This is the term that rides
##      the discontinuities the position filter cannot smooth (a reference jump, a
##      torso jump), so the target heading never steps.
## 4. dead zone **with hysteresis**: below `pose.deadzone` the angle is held,
##      and it only starts moving again once the wrist climbs back past
##      `pose.deadzone * pose.deadzone_exit` (a single threshold made a hand
##      resting near the reference toggle the hold every frame).
##   4b. **motion override** (`pose.motion_*`, owner: 手快速从最左边移动到最右边时
##      蛇没有转头): both holds below latch on POSITION only, so a fast sweep gets
##      frozen exactly where it crosses them (right under the shoulder -> the hang
##      cone, right next to it -> the dead zone). The mapper measures the wrist
##      speed in torso lengths per second and, above `motion.fast` for
##      `motion.frames` consecutive raw frames, suppresses BOTH holds so the
##      published angle follows the hand; it re-arms below `motion.slow`. The
##      angle/position low-passes are untouched, so the published angle stays
##      smooth. Slow motion (a drifting hand) never reaches the threshold and keeps
##      holding, which is what makes a resting hand stay still.
##   5. **arm-hanging hold** (`pose.hang_*`, owner option B 下垂识别): a wrist that
##      is far below the shoulder and nearly straight below it is an arm at rest,
##      not a steering gesture, so the angle is frozen exactly like the dead zone
##      does (`conf=0`, `reason=arm-low`, the slot stays valid and the raise test
##      keeps working). Hysteresis on both the depth and the cone angle.
##   6. speed  = lerp(pose.speed.min .. max) over near..far of the *raw* normalised
##      distance, then a first-order low-pass (`smooth`, seconds) and a slew-rate
##      limit (`slew` per second) so a reference jump cannot spike the speed.
##      Since 2026-11-17 the distance is the MORE EXTENDED arm,
##      `max(|rwr - rsh|, |lwr - lsh|) / torso` (see "Why both arms" below); the
##      curve itself, the low-pass and the slew limit are unchanged.
##
## The turn-rate limit itself lives in `PSSnake.update()` (`turn.rate`), i.e. the
## mapper only produces *intent*; the snake is the one that cannot turn faster.
## `--capture-pose-trace` measures both halves of that chain, frame by frame, into
## `evidence/pose-trace-*.txt`.
##
##     var pose := PSPoseSteer.new(cfg)
##     pose.update_wrist(wrist_px, ref_px, torso_px, now, steer,
##         left_wrist_px, left_shoulder_px, rwr_visibility, lwr_visibility)
##     ...
##     pose.mark_lost(now, steer)     # tracker dropped the pose this frame
##
## Everything here is allocation-free; the caller reuses the `steer` struct.
##
## Why both arms (owner 2026-11-17: 右手向右伸很快, 向左/向上伸就慢)
## -----------------------------------------------------------------
## `dist_n = |right wrist - RIGHT shoulder| / torso` is inherently asymmetric:
## reaching RIGHT moves the wrist away from the right shoulder (long), reaching
## LEFT crosses the body towards it (short), and raising the LEFT arm does not
## move the right wrist at all. The owner therefore felt a different maximum
## speed for the same gesture on different sides. The speed now reads the more
## extended of the two arms, while **steering stays right-wrist/right-shoulder
## only** (`last_angle`, the dead zone and the published heading are untouched).
## A PASSIVE hanging arm (the same posture test as the `pose.hang_*` steering
## gate, applied to each arm's own shoulder) is not a reach and is left out of
## the max, so dropping an arm can neither raise nor hold the speed by accident.
## `configuration.pose.speed.both_arms = false` restores the pre-fix law for the
## A/B trace (`--pose-arms=before`).
##
## Why the distance stays raw
## --------------------------
## A 2D filter on the *vector* would also lag its length, and the length is what
## opens the dead zone and drives the speed. Filtering the direction and gating on
## the raw length keeps the "I moved my hand, nothing happened" case out of the
## build entirely: the gate and the speed curve react on the tracker's frame, not
## ~3 tau later, while the angle is still perfectly smooth because the direction
## comes from the filtered vector.

const SteerInput = preload("res://src/core/steer_input.gd")
const PSConfig = preload("res://src/core/config.gd")

## Longest frame the low-passes integrate (s): a hitch must not become a jump.
const MAX_DT := 0.10
## Below this filtered offset length (px^2) the direction is not recomputed: the
## atan2 of a vanishing vector is numerically meaningless.
const MIN_DIR_LEN2 := 1e-6
## Hysteresis margin added to `pose.hang_align` when LEAVING the hanging state:
## the wrist must point this much further out of the "straight down" cone
## (sine +0.10 = 5.7 deg) before the angle is allowed to move again. It is not a
## `PoseCfg` field on purpose: the owner asked for three tunables, and this one is
## the hysteresis half of `hang_align`, not an independent knob.
const HANG_ALIGN_EXIT_MARGIN := 0.10

var cfg: PSConfig = null

## Last angle that passed the dead zone (radians) - the FILTERED angle, i.e. the
## one the rules steer with.
var last_angle: float = 0.0
## Raw (unfiltered) `atan2` of the newest accepted frame. Diagnostics only
## (`--capture-pose-trace` / HUD); never fed to the rules.
var last_raw_angle: float = 0.0
## Whether `last_angle` has ever been set.
var has_angle: bool = false
## Monotonic time (seconds) of the last frame the tracker produced a pose.
var last_seen_at: float = -1.0e9

## Raw (pre-smoothing) speed target.
var speed_target: float = 1.0
## Smoothed speed multiplier actually published.
var smooth_speed: float = 1.0

## Diagnostics for the HUD / tests (JS `signal.debug`).
var last_dist_n: float = 0.0
## The distance the SPEED curve actually consumed last frame: the more extended
## usable arm (`max` of the two per-arm distances), the right-arm distance under
## `speed.both_arms=false`, or -1 when no arm was usable (the target was kept).
var last_speed_dist_n: float = -1.0
## Which arm supplied `last_speed_dist_n`: 0 = right, 1 = left, -1 = none.
var last_speed_arm: int = -1
## Left arm distance (|lwr - lsh| / torso) of the newest frame, 0 when the left
## arm was not supplied. Diagnostics only (`--capture-pose-trace`).
var last_left_dist_n: float = 0.0
## Raw wrist-minus-reference vector in torso units. `last_dy_n > 0` = wrist BELOW
## the reference (canvas y points down); `last_dx_n` is mirrored-game x, so a
## positive value is the player's own right. Read by the hang gate below and by
## `--capture-pose-trace` (the gesture geometry is reported from these).
var last_dx_n: float = 0.0
var last_dy_n: float = 0.0
var last_deadzone_pass: bool = false
## True while the ARM-HANGING hold is active (`pose.hang_*`): the published angle
## is frozen exactly like the dead zone's. `ps_pose_input` turns this into
## `reason=arm-low` / `conf=0.00` for the device log; the slot is NOT lost.
var last_hang: bool = false
## Raw wrist speed of the newest frame, torso lengths / second (`pose.motion_*`).
var last_wrist_speed: float = 0.0
## The low-passed speed the motion gate actually compares (what `[pose-trace]`
## prints as `wrist_tps`).
var last_speed_filt: float = 0.0
## True while a fast sweep is overriding BOTH holds (motion awareness). The gate
## flags (`last_hang`, `last_deadzone_pass`) keep their own values, so the trace
## and the device log still show WHERE the wrist was - `motion` tells whether the
## hold was actually applied.
var last_motion_free: bool = false
## Count of single-frame keypoint jumps rejected as re-acquires (`motion.jump_dist`).
var reacquire_count: int = 0
## The FILTERED steering vector the angle is actually computed from, in the same
## pixel space the caller passes in. Read-only diagnostics: the skeleton overlay
## draws the reference dot here, so the owner sees what the game thinks the
## shoulder is rather than what the raw keypoint says.
var last_filtered_wrist := Vector2.ZERO
var last_filtered_ref := Vector2.ZERO
## The newest RAW wrist / reference, unmodified (diagnostics + trace only).
var last_raw_wrist := Vector2.ZERO
var last_raw_ref := Vector2.ZERO

## Frame clock for every low-pass in this mapper (seconds).
var _last_at: float = -1.0e9
## Wrist / reference filter state (one pair per mapper == one pair per slot).
var _f_wrist := Vector2.ZERO
var _f_ref := Vector2.ZERO
var _f_valid := false
## Running filtered angle, kept UNWRAPPED so the increments stay on the circle.
var _filt_angle: float = 0.0
## Dead-zone state (hysteresis): true while the angle is being held.
var _in_deadzone: bool = false
## Motion-awareness state: previous wrist (raw) + its step, the lag filter the
## speed is measured from, the speed low-pass, consecutive fast frames, and the
## override latch (`pose.motion_*`).
var _prev_wrist := Vector2.ZERO
var _has_prev_wrist: bool = false
var _prev_step: float = 0.0
var _speed_ref := Vector2.ZERO
var _speed_filt: float = 0.0
var _fast_frames: int = 0
var _motion_free: bool = false
## Left-arm "passive hanging" latch, the speed-side twin of `last_hang` (which
## belongs to the RIGHT arm and to the steering gate). Same enter/exit thresholds.
var _left_hang: bool = false


func _init(p_cfg: PSConfig = null) -> void:
	cfg = p_cfg
	reset()


func reset() -> void:
	last_angle = 0.0
	last_raw_angle = 0.0
	has_angle = false
	last_seen_at = -1.0e9
	speed_target = 1.0
	smooth_speed = 1.0
	last_dist_n = 0.0
	last_speed_dist_n = -1.0
	last_speed_arm = -1
	last_left_dist_n = 0.0
	last_dx_n = 0.0
	last_dy_n = 0.0
	last_deadzone_pass = false
	last_hang = false
	last_wrist_speed = 0.0
	last_speed_filt = 0.0
	last_motion_free = false
	last_filtered_wrist = Vector2.ZERO
	last_filtered_ref = Vector2.ZERO
	last_raw_wrist = Vector2.ZERO
	last_raw_ref = Vector2.ZERO
	_last_at = -1.0e9
	_f_wrist = Vector2.ZERO
	_f_ref = Vector2.ZERO
	_f_valid = false
	_filt_angle = 0.0
	_in_deadzone = false
	_prev_wrist = Vector2.ZERO
	_has_prev_wrist = false
	_prev_step = 0.0
	_speed_ref = Vector2.ZERO
	_speed_filt = 0.0
	_fast_frames = 0
	_motion_free = false
	_left_hang = false
	reacquire_count = 0


## Feed one tracked frame. `wrist` / `ref_px` are mirrored pixel coordinates,
## `torso_px` is the normalising torso length in pixels (>= 40 in the JS code).
## `ref_px` is the steering reference joint: the RIGHT SHOULDER since 2026-11-14
## (`pose.ref_joint`), the chest before.
##
## `left_wrist` / `left_ref` (optional, 2026-11-17): the LEFT wrist and the LEFT
## shoulder, same mirrored pixel space, used ONLY by the speed distance (see
## "Why both arms" at the top). Steering never reads them. Callers that do not
## pass them (tests, the older one-arm path) keep the right-arm-only speed.
## `right_vis` / `left_vis` are the tracker visibilities of those wrists; an arm
## below `pose.min_visibility` is ignored for speed (falling back to the other
## arm; when both are invisible the last speed target is kept, as before).
func update_wrist(wrist: Vector2, ref_px: Vector2, torso_px: float,
		now_sec: float, out: SteerInput, left_wrist = null, left_ref = null,
		right_vis: float = 1.0, left_vis: float = 1.0) -> void:
	var P = cfg.pose
	var scale := torso_px
	if not is_finite(scale) or scale < 1e-3:
		scale = 1.0
	var dx := wrist.x - ref_px.x
	var dy := wrist.y - ref_px.y
	var dist := sqrt(dx * dx + dy * dy)
	var dist_n := dist / scale
	last_dist_n = dist_n
	last_dx_n = dx / scale
	last_dy_n = dy / scale
	# ---- left arm (speed only): distance from the LEFT shoulder, plus its own
	# passive-hanging latch. Everything below is diagnostics or the speed max. --
	var have_left: bool = (left_wrist is Vector2) and (left_ref is Vector2)
	var ldx := 0.0
	var ldy := 0.0
	var ldist_n := 0.0
	var lalign := 1.0
	if have_left:
		ldx = float(left_wrist.x) - float(left_ref.x)
		ldy = float(left_wrist.y) - float(left_ref.y)
		ldist_n = sqrt(ldx * ldx + ldy * ldy) / scale
		lalign = absf(ldx) / maxf(1e-6, ldist_n * scale)
	last_left_dist_n = ldist_n if have_left else 0.0
	# The speed-side passivity test is the STEERING hang gate's posture rule
	# applied to the left arm's own shoulder (the gate itself is untouched and
	# stays right-arm/steering only). Same hysteresis thresholds, own latch.
	if have_left:
		if _left_hang:
			if ldy / scale < P.hang_exit or lalign > P.hang_align + HANG_ALIGN_EXIT_MARGIN:
				_left_hang = false
		elif ldy / scale >= P.hang_enter and lalign <= P.hang_align:
			_left_hang = true
	else:
		_left_hang = false

	# ---- frame clock (shared by every low-pass below) ----------------------
	var dt_sec := 0.0
	if _last_at > -1.0e8:
		dt_sec = clampf((now_sec - _last_at), 0.0, MAX_DT)
	_last_at = now_sec

	# ---- 1. wrist + reference 2D low-pass (feeds the angle only) -----------
	var a_pos := _alpha(dt_sec, P.wrist_smooth)
	if _f_valid:
		_f_wrist += (wrist - _f_wrist) * a_pos
		_f_ref += (ref_px - _f_ref) * a_pos
	else:
		# First sample after acquire / reset: no history to smooth against.
		_f_wrist = wrist
		_f_ref = ref_px
		_f_valid = true

	# ---- 2. dead zone WITH hysteresis (on the raw distance) ----------------
	if _in_deadzone:
		if dist_n >= P.deadzone * maxf(1.0, P.deadzone_exit):
			_in_deadzone = false
	elif dist_n < P.deadzone:
		_in_deadzone = true
	var deadzone_pass: bool = not _in_deadzone
	last_deadzone_pass = deadzone_pass

	# ---- 2a. MOTION AWARENESS (owner: 手快速从最左边移动到最右边时蛇没有转头) --
	# The two holds below read POSITION only. During a fast left->right sweep the
	# wrist crosses exactly the places they latch on - straight under the shoulder
	# (the hang cone) and right next to it (the dead zone) - so the published angle
	# froze for the middle of the sweep and the snake never turned.
	#
	# Speed is measured in TORSO LENGTHS PER SECOND (camera/body-size independent)
	# with a POSITION-LAG estimator instead of a raw frame difference: for a steady
	# velocity `v` the exponential filter `_speed_ref` trails the true wrist by
	# `v * tau`, so `|wrist - _speed_ref| / tau == v`. White keypoint jitter
	# averages out inside the filter (the trace's +-6 px rms reads ~0.15 torso/s
	# instead of ~1.9), and a second low-pass of the same tau on the speed itself
	# keeps a single noisy frame from reaching the gate. Measured on the scripted
	# gestures: resting hand 0.0 | slow drift 0.1-0.5 | 2.1 s sweep ~1.3 |
	# full circle ~1.5 | 0.35 s sweep ~7.4 torso/s.
	#
	# One special case: a single-frame wrist step above `motion.jump_dist` while the
	# hand was NOT already moving is a keypoint re-acquire (occlusion, an id swap, or
	# the trace script's teleport between gestures), not a hand movement. The
	# measurement restarts from there, so a static gesture keeps the exact hold law
	# it had before this pass. `_prev_step` is the guard that keeps a genuine 15 Hz
	# sweep (0.74 torso EVERY frame) out of that branch.
	var M = P.motion
	var had_prev := _has_prev_wrist
	var step_n := 0.0
	if had_prev:
		step_n = (wrist - _prev_wrist).length() / scale
	var reacquire: bool = had_prev and step_n > M.jump_dist \
		and _prev_step <= M.jump_dist
	_prev_step = step_n
	_prev_wrist = wrist
	_has_prev_wrist = true
	var spd := 0.0
	if reacquire:
		reacquire_count += 1
		_speed_ref = wrist
		_speed_filt = 0.0
	else:
		if had_prev:
			last_wrist_speed = (wrist - _speed_ref).length() / scale \
				/ maxf(1e-3, M.smooth)
			spd = last_wrist_speed
		_speed_ref += (wrist - _speed_ref) * _alpha(dt_sec, M.smooth)
	_speed_filt += (spd - _speed_filt) * _alpha(dt_sec, M.smooth)
	last_speed_filt = _speed_filt
	if reacquire:
		_fast_frames = 0
		_motion_free = false
	else:
		if _speed_filt >= M.fast:
			_fast_frames += 1
		else:
			_fast_frames = 0
		if _motion_free:
			if _speed_filt <= M.slow:
				_motion_free = false
		elif _fast_frames >= maxi(1, M.frames):
			_motion_free = true
	last_motion_free = _motion_free

	# ---- 2b. ARM-HANGING gate WITH hysteresis (owner option B, 下垂识别) ---
	# Raw geometry, same as the dead-zone gate above: this is a posture test, not
	# a smoothing problem, and the filters must not delay the hold/release.
	#   enter: wrist clearly BELOW the shoulder (dy_n >= hang_enter) AND the vector
	#          points nearly straight down (align <= hang_align, a sine = cone)
	#   exit:  the wrist comes back up (dy_n < hang_exit) OR swings out of the
	#          cone by HANG_ALIGN_EXIT_MARGIN
	# `align` is sin(angle out of vertical), so `hang_align` 0.45 = 26.7 deg.
	var align := absf(last_dx_n) / maxf(1e-6, dist_n)
	if last_hang:
		if last_dy_n < P.hang_exit or align > P.hang_align + HANG_ALIGN_EXIT_MARGIN:
			last_hang = false
	elif last_dy_n >= P.hang_enter and align <= P.hang_align:
		last_hang = true
	# The published angle moves only when NEITHER hold is active AND no fast sweep
	# is overriding them. `last_hang` and `last_deadzone_pass` stay separate
	# diagnostic flags, so the trace (and the device log) shows WHY the angle is
	# frozen - or that a motion overrode a gate that is still tracking position.
	var gate_hold: bool = last_hang or not deadzone_pass
	var holding: bool = gate_hold and not _motion_free

	if not holding:
		# canvas y points down, so atan2(dy, dx) is already the on-screen angle.
		last_raw_angle = atan2(dy, dx)
		# ---- 3. circular low-pass on the FILTERED vector's angle -----------
		var fdx := _f_wrist.x - _f_ref.x
		var fdy := _f_wrist.y - _f_ref.y
		if fdx * fdx + fdy * fdy > MIN_DIR_LEN2:
			var target := atan2(fdy, fdx)
			if has_angle:
				_filt_angle += _wrap(target - _filt_angle) * _alpha(dt_sec, P.angle_smooth)
			else:
				_filt_angle = target
			last_angle = _wrap(_filt_angle)
			has_angle = true
	var angle := last_angle

	# ---- distance -> speed multiplier --------------------------------------
	# 2026-11-17 (owner: 向右伸很快, 向左/向上伸就慢): the SPEED reads the more
	# extended arm, `max(|rwr-rsh|, |lwr-lsh|) / torso`, while the steering above
	# stays right-wrist/right-shoulder only. The dead zone / hang / motion holds
	# are STEERING gates: they must not freeze this target any more, or a left
	# reach with the right arm hanging could never speed the snake up. A passive
	# (hanging) arm is not a reach and is excluded per arm; when no arm is usable
	# the previous target is kept exactly like the pre-fix law did while held.
	var SP = P.speed
	var speed_dn := -1.0
	var speed_arm := -1
	if not SP.both_arms:
		# Pre-fix law (measurement only, `--pose-arms=before`): right arm only and
		# the steering holds still freeze the target. The diagnostic distance is
		# always the right-arm one (that is what the old curve would have read).
		speed_dn = dist_n
		speed_arm = 0
		if not holding:
			var span0 := maxf(0.05, SP.far - SP.near)
			var t0 := clampf((speed_dn - SP.near) / span0, 0.0, 1.0)
			speed_target = SP.min + (SP.max - SP.min) * t0
	else:
		var min_vis: float = P.min_visibility
		var r_ok: bool = right_vis >= min_vis and not last_hang
		var l_ok: bool = have_left and left_vis >= min_vis and not _left_hang
		var r_dn: float = dist_n if r_ok else -1.0
		var l_dn: float = ldist_n if l_ok else -1.0
		if r_dn >= 0.0 and l_dn >= 0.0:
			if l_dn > r_dn:
				speed_dn = l_dn
				speed_arm = 1
			else:
				speed_dn = r_dn
				speed_arm = 0
		elif r_dn >= 0.0:
			speed_dn = r_dn
			speed_arm = 0
		elif l_dn >= 0.0:
			speed_dn = l_dn
			speed_arm = 1
	last_speed_dist_n = speed_dn
	last_speed_arm = speed_arm
	# The two-arm law always evaluates the curve when a usable arm exists; the
	# before law already did its (hold-gated) update in its own branch above.
	if SP.both_arms and speed_dn >= 0.0:
		var span := maxf(0.05, SP.far - SP.near)
		var t_speed := clampf((speed_dn - SP.near) / span, 0.0, 1.0)
		speed_target = SP.min + (SP.max - SP.min) * t_speed

	# Debounce 1: frame-rate independent low-pass (smooth is a time constant).
	var alpha := _alpha(dt_sec, SP.smooth)
	var next_speed := smooth_speed + (speed_target - smooth_speed) * alpha
	# Debounce 2: slew-rate limit (hand swaps / hip fallback jump the distance).
	var max_step: float = SP.slew * dt_sec
	if max_step > 0.0:
		next_speed = clampf(next_speed, smooth_speed - max_step, smooth_speed + max_step)
	# Debounce 3: never leave the promised slider range.
	smooth_speed = clampf(next_speed, minf(SP.min_limit, SP.max_limit), maxf(SP.min_limit, SP.max_limit))

	last_seen_at = now_sec
	last_raw_wrist = wrist
	last_raw_ref = ref_px
	last_filtered_wrist = _f_wrist
	last_filtered_ref = _f_ref
	out.set_pose(angle, smooth_speed, 0.0 if holding else 1.0)


## The caller picked the OTHER wrist this frame (`pose.arm_*` hysteresis decided
## it, so this is a deliberate switch, not noise).
##
## The position filter must not smear across it: easing from one wrist to the
## other drags the vector through the middle of the body, i.e. through a
## vanishing offset whose angle swings ~180 deg - exactly the "erratic" motion the
## hysteresis exists to prevent. So the position filter restarts on the new hand
## (first-sample snap) while the ANGLE filter keeps its value and rides the jump:
## a switch therefore resolves over ~3 * `pose.angle_smooth` instead of instantly.
##
## Since 2026-11-14 steering is right-arm fixed, so the shipped path never calls
## this (a left/right pick change must not disturb the right-arm vector). It stays
## for the later left-side option and for any caller that switches the source arm.
func on_hand_switch() -> void:
	_f_valid = false


## The tracker lost the pose this frame. Keep steering with the last angle for
## `pose.lost_timeout_ms` (JS `hold`), then report "no input".
##
## `force_lost` (binding phase, `pose.bind.grace_sec`): the caller has already
## used up its own grace window, so the hold must end NOW instead of waiting for
## `lost_timeout_ms`. The angle/speed values are still the last good ones, so the
## rules coast on them for exactly as long as the binding FSM allows.
func mark_lost(now_sec: float, out: SteerInput, force_lost: bool = false) -> void:
	var P = cfg.pose
	var held_ms := (now_sec - last_seen_at) * 1000.0
	var hold: bool = (not force_lost) and held_ms < P.lost_timeout_ms and has_angle
	out.steer_angle_rad = last_angle
	out.valid = false
	out.hold = hold
	out.keyboard = false
	out.confidence = 0.0
	# JS keeps the smoothed speed during a dropout (it never jumps back to 1).
	out.speed_scale = smooth_speed


## Direct write for a bridge that computes the angle itself (e.g. the SDK hands
## back a calibrated angle instead of raw landmarks). Bypasses the wrist dead zone
## and the speed smoothing; `speed_scale` is published verbatim (clamped to the
## configured slider range).
func set_angle_direct(angle: float, p_speed_scale: float, now_sec: float,
		out: SteerInput, p_confidence: float = 1.0) -> void:
	last_angle = angle
	last_raw_angle = angle
	has_angle = true
	last_seen_at = now_sec
	last_deadzone_pass = true
	# The bridge-computed angle is not a wrist vector, so it cannot be an
	# arm-hanging pose: drop any hold the wrist path left behind.
	last_hang = false
	# ...and it is not a measured wrist motion either: the next wrist frame must
	# start the speed measurement from scratch instead of comparing against a
	# position from another source.
	_has_prev_wrist = false
	_prev_step = 0.0
	_fast_frames = 0
	_speed_filt = 0.0
	_motion_free = false
	last_wrist_speed = 0.0
	last_speed_filt = 0.0
	last_motion_free = false
	# A bridge angle is not an arm distance either: drop the speed diagnostics so
	# the next wrist frame reports its own.
	last_speed_dist_n = -1.0
	last_speed_arm = -1
	_left_hang = false
	# Restart the angle filter from the new truth, and make the next wrist frame
	# snap the position filter instead of easing away from the old hand.
	_filt_angle = angle
	_f_valid = false
	var SP = cfg.pose.speed
	var lo := minf(SP.min_limit, SP.max_limit)
	var hi := maxf(SP.min_limit, SP.max_limit)
	smooth_speed = clampf(p_speed_scale, lo, hi)
	speed_target = smooth_speed
	out.set_pose(angle, smooth_speed, p_confidence)


## Remaining hold time in seconds (0 when the signal is already too old).
func hold_left(now_sec: float) -> float:
	if not has_angle:
		return 0.0
	var left: float = cfg.pose.lost_timeout_ms / 1000.0 - (now_sec - last_seen_at)
	return 0.0 if left < 0.0 else left


# ------------------------------------------------------------------ internals

## First-order low-pass weight for `dt` and a time constant `tau` (seconds).
## tau <= 0 (or a zero-length frame) means "no filtering": alpha 1.
func _alpha(dt: float, tau: float) -> float:
	if tau <= 0.0 or dt <= 0.0:
		return 1.0
	return 1.0 - exp(-dt / tau)


## Wrap an angle into (-PI, PI].
func _wrap(a: float) -> float:
	while a > PI:
		a -= TAU
	while a <= -PI:
		a += TAU
	return a
