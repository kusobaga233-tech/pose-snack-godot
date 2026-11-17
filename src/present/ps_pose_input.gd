extends RefCounted
## Workstream C — bridge frame -> `PSSteerInput` (the pose half of the input layer).
##
## The rules only need `steer_angle_rad` / `speed_scale` (see Docs/core-model.md);
## all the pose maths lives in `src/core/pose_steer.gd`. This file's job is to
## turn `YoudooBridge.latest_frame()` into the three numbers that mapper wants:
##
##   1. read the skeleton keypoints (normalised, top-left image space)
##   2. mirror x (`nx = 1 - x`) so moving your own right hand steers right.
##      This is the SDK's own tracked-coordinate mirror: the built-in YouDoo
##      provider reports mirrored coordinates and the framework exposes them
##      through `CameraImageView.MirrorTrackedPlayerCoordinates` /
##      `MatchSessionConfig.MirrorPlayerTrackingHorizontally`
##      (CameraImageTrackingProjectionUtility.cs:75-83, PlayerTracking.cs:29-34,
##      Catalog: "adapt to a mirrored video"). `mirror_x` stays switchable at
##      runtime only as the fallback for a preview that cannot be flipped; the
##      shipped default is ON, in lockstep with the mirrored camera variant.
##   3. steering REFERENCE = the RIGHT SHOULDER (`_indices()["rsho"]`: youdoo18
##      joint 6, coco18 2, blaze33 12). Owner request 2026-11-14:
##      把之前的胸前点位改到肩膀 / 右手与右肩连点, 先只处理右侧. `pose.ref_joint`
##      still knows the old chest point (`lerp(neck, waist, center_t)`) so the
##      trace harness can re-measure the previous pass; the raise-to-start test
##      below always uses that chest point, as before.
##   4. torso_px = avg(|Lsh-Lhip|, |Rsh-Rhip|) (shoulder-width fallback when the
##      hips are not visible, i.e. sitting at a desk)
##   5. hand = the RIGHT wrist, fixed. The old auto-pick (wrist further from the
##      chest, with hysteresis + dwell) still runs behind the scenes for the
##      raise test and for the later left-side option, but it never steers: a
##      hidden right wrist/shoulder loses the slot, it does not fall back left.
##   6. hand the triple to `PSPoseSteer.update_wrist()`, or `mark_lost()` when the
##      tracker dropped the person (the rules then coast on the last heading).
##
## Binding (owner: 做一个绑定阶段, 保证局内除非丢骨骼, 不然不会绑定到别人身上)
## ----------------------------------------------------------------------------
## A SLOT OWNS A PERSON ID, NOT A SCREEN POSITION. `bound_ids[slot]` is the SDK
## person id - the key of the bridge frame's `persons` dictionary, i.e. the SDK's
## own stable track id - and it only ever changes during READY:
##
##   WAITING   no id yet. The person standing in this slot's area is still mapped
##             as a CANDIDATE, so `slot_seen` / `slot_hand_up` work and the READY
##             raise can be confirmed; nothing is published as bound.
##   CANDIDATE that person has stayed in the slot's area for `bind.stable_sec`.
##   BOUND     the raise confirmation completed (main.gd pushes `ready_state==2`
##             through `set_slot_raise_ok`), so the id is frozen.
##
## WAITING must publish the candidate into `ids[]` (the mapper's per-frame input),
## NOT only into `_cand_t`: the raise the FSM waits for is computed by
## `_process_slot()` from that very person. Skipping the mapping deadlocks the
## ladder - no `slot_seen` -> no `ready_state==2` -> no `set_slot_raise_ok` -> no
## BOUND -> still WAITING (the 2026-11-14 device log: `stable=76.88s state=wait`
## with `torso=0 hand=- reason=unbound`).
##
## Person ids come from `YoudooBridge.latest_frame()`, i.e. from `JSON.parse_string`,
## so the keys of `persons` are STRINGS ("0", "3", ...) while the ids this FSM keeps
## are ints. EVERY lookup goes through `_person()` / `_has_person()` and every key
## through `_pid()`; a raw `ps.has(id)` matches nothing on device (and only matched
## in the headless suite because the tests built a native int-keyed dictionary).
## That key mismatch was the other half of the same deadlock: `_process_slot()` was
## never reached, so `torso=0`, `hand=-`, `s0=false`, `slots=0`.
##
## The old code re-assigned the slot by position EVERY frame (1P = lowest id, 2P =
## shoulder-mid x), so a person with a lower id appearing, or the two players
## crossing the centre line, handed the slot to someone else mid-round. Now:
##
##   * COUNTDOWN/PLAY never re-evaluate the binding. A missing bound person makes
##     the slot COAST on its last heading for `bind.grace_sec`, then report lost.
##     Another person's box is never substituted, at any point.
##   * READY is the only phase that may (re)bind, and only after the bound person
##     has been gone for `bind.rebind_absent_sec` - a 0.3 s tracking hole must not
##     hand the slot to whoever walks past.
##   * one person can never feed two slots (candidates exclude every id already
##     bound, bound or claimed this frame).
##
## Modelled on `XXAndroidParseData.personPlayerIds` / `personPlayerLockIng` /
## `readyNeedFrame` in the 1024 project: a locked candidate becomes a confirmed
## binding only after the raise hold, and both are dropped when the person leaves
## the frame for long enough.
##
## Every bind / unbind / lost is ONE `[bind]` line at the transition (never per
## frame), plus one compact `bound=<id0>,<id1>` line per second:
##
##   [bind] t=4.62s slot=0 id=3 -> bound (stable=0.62s raise=1.52s)
##   [bind] slot=1 id=-1 -> lost (grace=1.00s)
##   [bind] t=9.00s slot=0 id=3 -> unbind (absent=3.02s, ready rebind)
##   [bind] t=9.00s phase=ready bound=-1,7 state=wait,bound cand=9,-1 ...
##
## Keypoint layout: the SDK documents 18 joints but not their order. 18 is the
## COCO/OpenPose body layout (`kp[3]` = confidence), which is what the bridge
## probe in workstream A already assumed. Because that is an assumption, the
## mapper *validates* the layout per frame and falls back to COCO-17 /
## BlazePose-33 when the torso does not look like a torso. The chosen layout is
## published in `diag` for the on-device debug overlay.

const PSPoseSteer = preload("res://src/core/pose_steer.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")
## Grace-tolerant raise accumulator (shared with main.gd's READY slot FSM, so a
## noisy frame cannot reset one without the other).
const PSRaiseHold = preload("res://src/present/ps_raise_hold.gd")

const LAYOUT_NAMES := ["coco18", "youdoo18", "blaze33"]

# ------------------------------------------------- bound person (binding FSM)
# See the header block: a slot follows a PERSON ID, not a screen position.
const BIND_WAITING := 0
const BIND_CANDIDATE := 1
const BIND_BOUND := 2
const BIND_STATE_NAMES := ["wait", "cand", "bound"]

var cfg = null
var bridge: Node = null

## One steer struct per human slot (reused every frame).
var steers: Array = []
var mappers: Array = []

var has_frame := false
var tracking := false
## Number of person boxes in the newest bridge frame (`frame["persons"].size()`).
## This is the number the SDK reports, so it is the one the HUD / diag must show.
var persons := 0
## Number of slots that actually got a person mapped to them this frame (0..2).
## `persons` can be > `tracked_slots` (3 people in frame, 1P game maps one slot).
var tracked_slots := 0
## Per-slot "a person is acquired" flags, recomputed every `poll()`. The READY
## screen drives its slot state machine from these. While a slot is unbound this
## is the CANDIDATE (that is how the READY raise can be confirmed before binding).
var slot_seen: Array = [false, false]
## Per-slot "one hand is up" flags (either wrist, normalised raise threshold).
var slot_hand_up: Array = [false, false]
## Age of the newest bridge frame in ms (`-1` before the first one). Computed on
## demand by `frame_age()`: this used to be a stored int that nothing ever wrote,
## so the `[pose] ... age=-1ms` of every device log was a lie.

## Per-slot SDK person id this slot is BOUND to (-1 = not bound). The identity the
## slot follows; it is not recomputed from position outside READY.
var bound_ids: Array = [-1, -1]
## Per-slot binding FSM state (BIND_WAITING / BIND_CANDIDATE / BIND_BOUND).
var bind_state: Array = [BIND_WAITING, BIND_WAITING]
## Binding-phase counters (tests + the `[bind]` lines).
var bind_count := 0
var unbind_count := 0
var lost_count := 0
## The screen phase the game is in (`&"ready"` is the only one that may bind).
## main.gd pushes it from `_flow_to()`.
var phase: StringName = &"mode_select"

## Diagnostics for the HUD / debug overlay.
var diag := {
	"layout": "coco18", "hand": "-", "dist_n": 0.0, "angle": 0.0,
	"torso": 0.0, "conf": 0.0, "reason": "", "slot0": false, "slot1": false,
	## `spd_n` = the distance the SPEED curve consumed (the more extended arm,
	## 2026-11-17); `dist_n` above stays the right-arm steering distance.
	"spd_n": -1.0,
	## `ref` = the steering reference joint in use ("shoulder_r" / "chest"),
	## `kp` = its index in the active layout (-1 for the interpolated chest).
	## Printed by main.gd's `[pose]` line so a device log proves which joint steers.
	"ref": "shoulder_r", "kp": 6,
	## Binding: `bound0/bound1` = the person id each slot owns (-1 = none),
	## `bind0/bind1` = the FSM state number. Printed by `[pose]` + `[bind]`.
	"bound0": -1, "bound1": -1, "bind0": BIND_WAITING, "bind1": BIND_WAITING,
}

# ------------------------------------------- live skeleton for the camera box
#
# The HUD draws the tracked skeleton over the camera pixels (band mirror box +
# READY slot panes). It must land on the *picture*, so everything here is in
# NORMALISED PROVIDER space (0..1, top-left origin, NOT mirrored): the HUD maps a
# point through the exact cover-crop + flip the camera texture uses. `mirror_x`
# only changes the game's steering convention, never this overlay.
#
# Parallel per-slot arrays, owned here and read by `PSHud` (`hud.skel_src`), so the
# per-frame path allocates nothing: the arrays are built once and refilled.

## Highest keypoint count mirrored to the overlay (BlazePose-33 upper bound).
const SKEL_MAX := 33

## Per slot: normalised provider positions, refilled every frame that has a pose.
var skel_pts: Array = []
## Per slot: 1 = this keypoint is usable (present + visible), 0 = skip.
var skel_ok: Array = []
## Per slot: number of keypoints the newest frame reported (0..SKEL_MAX).
var skel_n: Array = [0, 0]
## Per slot: true when `skel_pts` holds a skeleton from the newest frame.
var skel_on: Array = [false, false]
## Per slot: the auto-picked arm (0 = right wrist, 1 = left wrist, -1 = none yet).
## DIAGNOSTIC ONLY since the right-arm-fixed pass: it still drives the raise test,
## it no longer drives the steering angle. See `skel_steer_wri`.
var skel_wrist: Array = [-1, -1]
## Per slot: the steering REFERENCE the mapper actually filters (provider space),
## i.e. the right shoulder (or the chest when `pose.ref_joint` says so).
var skel_ref: Array = [Vector2.ZERO, Vector2.ZERO]
## Per slot: true when `skel_ref` is valid for this frame.
var skel_ref_ok: Array = [false, false]
## Per slot: dead-zone radius as a fraction of the image WIDTH (0 = unknown).
var skel_dead_u: Array = [0.0, 0.0]
## Bone pairs for the active layout, as indices into `skel_pts`. Rebuilt only when
## the layout resolves, so the HUD iterates a ready list (never a table lookup).
var skel_bones: Array = []
## Wrist keypoint indices for the active layout (both wrists get a joint dot).
var skel_rwri: int = 6
var skel_lwri: int = 9
## The wrist index that actually drives the steering (the RIGHT wrist, fixed).
## The HUD draws the hand dot and the shoulder->hand line on THIS joint only; the
## left wrist stays an ordinary (dim) joint dot.
var skel_steer_wri: int = 10

## Raise-a-hand-to-start state (menu shortcut, mirrors pose.raise_*). The hold is
## grace-tolerant (`PSRaiseHold`, 0.30 s): one noisy keypoint frame must not wipe
## a raise that has been held for most of `pose.raise_hold_sec`.
var _raise = PSRaiseHold.new()
var _raise_last := 0.0

## Current layout index (resolved lazily, cached once it validates).
var _layout := 0
var _layout_locked := false

## Provider-x -> game-x convention. ON = `1 - x`, the shipped SDK default
## (mirrored video + mirrored tracking). OFF = raw provider x, used by the
## runtime fallback when the native overlay cannot be mirror-flipped.
var mirror_x := true

var _last_frame_ms := 0
var _frame: Dictionary = {}
var _hand := [-1, -1]
## Monotonic time (seconds) of the last arm switch per slot (`pose.arm_min_dwell_sec`).
var _hand_at := [-1.0e9, -1.0e9]

# ---- binding FSM state (see the header block) -------------------------------
## Candidate id per slot + how long it has been stable in the slot's area (s).
var _cand_id: Array = [-1, -1]
var _cand_t: Array = [0.0, 0.0]
## How long the person this slot needs has been missing from the frame (s).
var _absent_t: Array = [0.0, 0.0]
## READY raise confirmation per slot, pushed by main.gd's `_update_ready()`:
## `_raise_ok` = `ready_state == 2`, `_raise_hold` = seconds the hand was held up.
var _raise_ok: Array = [false, false]
var _raise_hold: Array = [0.0, 0.0]
## `[bind] ... -> lost` is a transition, not a per-frame event.
var _lost_logged: Array = [false, false]
## Previous poll clock (the binding windows are SECONDS, never frame counts).
var _last_poll_at := -1.0e9
var _bind_log_at := -1.0e9

## Bone pairs per layout, as indices into the keypoint array. These are the SDK's
## own layouts (see `_indices()`), not a re-invented skeleton:
##   * coco18  — 1 neck, 2/5 shoulders, 3/6 elbows, 4/7 wrists, 8/11 hips
##   * youdoo18 — 0 nose, 5/6 shoulders, 7/8 elbows, 9/10 wrists, 11/12 hips
##   * blaze33 — 11/12 shoulders, 13/14 elbows, 15/16 wrists, 23/24 hips
## The 18-point layout the device reports (`layout=youdoo18`) also has eyes/ears/
## knees/ankles/chest; those are drawn as joint dots, not bones.
const SKEL_BONES := [
	[[0, 1], [1, 2], [1, 5], [2, 3], [3, 4], [5, 6], [6, 7], [2, 8], [5, 11], [8, 11]],
	[[0, 5], [0, 6], [5, 6], [6, 8], [8, 10], [5, 7], [7, 9], [6, 12], [5, 11], [11, 12]],
	[[11, 12], [12, 14], [14, 16], [11, 13], [13, 15], [12, 24], [11, 23], [23, 24], [0, 11], [0, 12]],
]


func _init(p_cfg, p_bridge: Node) -> void:
	cfg = p_cfg
	bridge = p_bridge
	steers.append(PSSteerInput.new())
	steers.append(PSSteerInput.new())
	mappers.append(PSPoseSteer.new(cfg))
	mappers.append(PSPoseSteer.new(cfg))
	for i in 2:
		skel_pts.append(PackedVector2Array())
		skel_ok.append(PackedByteArray())
		skel_pts[i].resize(SKEL_MAX)
		skel_ok[i].resize(SKEL_MAX)
	_publish_skel_layout()


func reset() -> void:
	for m in mappers:
		m.reset()
	for s in steers:
		s.clear()
	_hand = [-1, -1]
	_hand_at = [-1.0e9, -1.0e9]
	_raise.reset()
	_raise_last = 0.0
	slot_seen = [false, false]
	slot_hand_up = [false, false]
	tracked_slots = 0
	persons = 0
	bound_ids = [-1, -1]
	bind_state = [BIND_WAITING, BIND_WAITING]
	_cand_id = [-1, -1]
	_cand_t = [0.0, 0.0]
	_absent_t = [0.0, 0.0]
	_raise_ok = [false, false]
	_raise_hold = [0.0, 0.0]
	_lost_logged = [false, false]
	bind_count = 0
	unbind_count = 0
	lost_count = 0
	_last_poll_at = -1.0e9
	_bind_log_at = -1.0e9
	_last_frame_ms = 0
	diag["bound0"] = -1
	diag["bound1"] = -1
	diag["bind0"] = BIND_WAITING
	diag["bind1"] = BIND_WAITING
	for i in 2:
		_skel_clear(i)


## Runtime handedness switch (paired with the camera variant, never used alone):
## flips the provider-x convention and forgets the per-slot arm choice, so the
## next frame re-acquires the wrist and angle in the new space.
func set_mirror_x(value: bool) -> void:
	if mirror_x == value:
		return
	mirror_x = value
	_hand = [-1, -1]
	_hand_at = [-1.0e9, -1.0e9]
	_raise.reset()
	_raise_last = 0.0
	for m in mappers:
		m.reset()


func available() -> bool:
	return bridge != null and bridge.is_available()


func status() -> Dictionary:
	if bridge == null or not bridge.has_method("status"):
		return {}
	return bridge.status()


## Poll the newest bridge frame and refresh every slot's steer struct.
func poll(now: float, count: int) -> void:
	var n := clampi(count, 1, 2)
	if bridge == null:
		var dt0 := _poll_dt(now)
		_frame_start(n)
		_track(false)
		_absent_all(n, now, dt0, "no-bridge")
		_bind_second(now)
		return
	tracking = bridge.is_tracking()
	var f: Dictionary = bridge.latest_frame()
	if not tracking or f.is_empty():
		var dt1 := _poll_dt(now)
		has_frame = false
		persons = 0
		_frame_start(n)
		_track(false)
		_absent_all(n, now, dt1, "no-frame")
		_bind_second(now)
		return
	poll_frame(now, n, f)


## Shared body of `poll()`: one bridge-shaped frame -> binding FSM -> per-slot
## mapper. `f` is exactly what `bridge.latest_frame()` returns:
##   {"imageWidth": int, "imageHeight": int, "persons": {<id>: {"kpts": [...]}}}
## `tests/suite_input.gd` calls this directly with synthetic frames, so the
## scripted binding proof runs the shipped FSM, not a copy of it.
func poll_frame(now: float, count: int, f: Dictionary, imgw: float = 0.0,
		imgh: float = 0.0) -> void:
	var n := clampi(count, 1, 2)
	var dt := _poll_dt(now)
	_frame_start(n)
	has_frame = true
	_frame = f
	_last_frame_ms = Time.get_ticks_msec()
	var ps: Dictionary = f.get("persons", {})
	# The bridge frame is the source of truth for the reported person count.
	persons = ps.size()
	if persons == 0:
		_track(false)
		_absent_all(n, now, dt, "no-person")
		_bind_second(now)
		return
	_track(true)
	if imgw <= 0.0:
		imgw = maxf(1.0, float(f.get("imageWidth", 960)))
	if imgh <= 0.0:
		imgh = maxf(1.0, float(f.get("imageHeight", 720)))
	# ---- 1. binding phase: decide WHICH person (if any) feeds each slot ------
	var ids := _bind_step(now, dt, n, ps, imgw)
	# ---- 2. map / coast / lost, one slot at a time ---------------------------
	for slot in n:
		var id := int(ids[slot])
		# The box is fetched through `_person()`, never `ps[id]`: on device the
		# keys are the JSON strings ("0", "3", ...), and an int lookup returned
		# null here - which is why `_process_slot()` never ran for a candidate.
		var box: Variant = _person(ps, id) if id >= 0 else null
		if box == null:
			# No usable person for this slot on this frame. NOTHING is substituted:
			# the slot coasts on its bound id's last heading, then goes lost.
			_coast_slot(slot, now, "coast")
		elif _process_slot(slot, box, imgw, imgh, now):
			slot_seen[slot] = true
			tracked_slots += 1
		else:
			_mark_lost_slot(slot, now, String(diag.get("reason", "bad-pose")))
	_bind_second(now)


func frame_age() -> int:
	if _last_frame_ms <= 0:
		return -1
	return Time.get_ticks_msec() - _last_frame_ms


# --------------------------------------------------------------- binding FSM

## main.gd's phase push (see `_flow_to`). Only `&"ready"` may bind or re-bind;
## every other phase follows the ids frozen when the READY gate opened.
func set_phase(p: StringName) -> void:
	if phase == p:
		return
	phase = p
	if p == &"ready":
		# A new READY re-arms the raise confirmation: only a raise that happened in
		# THIS ready screen may complete a binding.
		_raise_ok = [false, false]
		_raise_hold = [0.0, 0.0]
	print("[bind] t=%.2fs phase->%s bound=%d,%d" % [
		maxf(0.0, _last_poll_at), phase, int(bound_ids[0]), int(bound_ids[1])])


## main.gd's READY FSM push, once per frame per slot: `ok` = this slot's raise
## confirmation completed (`ready_state == 2`), `hold_sec` = how long the hand has
## been up (the `raise=1.52s` in the bind line). The binding FSM and the READY
## cards therefore can never disagree about "the raise completed".
func set_slot_raise_ok(slot: int, ok: bool, hold_sec: float) -> void:
	if slot < 0 or slot > 1:
		return
	_raise_ok[slot] = ok
	_raise_hold[slot] = maxf(0.0, hold_sec)


## Decide which person feeds each slot this frame. Returns `[id0, id1]`, -1 for
## "nobody" (the caller then coasts / loses that slot).
func _bind_step(now: float, dt: float, n: int, ps: Dictionary, imgw: float) -> Array:
	var ids: Array = [-1, -1]
	var used := {}
	# ---- pass 1: a PRESENT bound id always keeps its slot -------------------
	for slot in n:
		var b := int(bound_ids[slot])
		# `_has_person`, not `ps.has(b)`: JSON keys are strings on device.
		if b >= 0 and _has_person(ps, b):
			ids[slot] = b
			used[b] = true
	# ---- pass 2: READY only - candidates for UNBOUND slots ------------------
	# A slot that still holds a binding is never offered to anybody else here,
	# even while its person is momentarily missing: only `_unbind` (after
	# `bind.rebind_absent_sec`) returns it to WAITING.
	if phase == &"ready":
		for slot in n:
			if ids[slot] >= 0:
				_cand_id[slot] = -1
				_cand_t[slot] = 0.0
				continue
			if int(bound_ids[slot]) >= 0:
				continue
			var cand := _pick_candidate(slot, n, ps, imgw, used)
			if cand < 0:
				# Nobody in the area: a CANDIDATE falls back to WAITING. A candidate
				# is not a binding, so there is no unbind / absence clock here.
				_cand_id[slot] = -1
				_cand_t[slot] = 0.0
				_cand_exit(slot, now, "no candidate in area")
				continue
			used[cand] = true
			# PUBLISH THE CANDIDATE, DO NOT BIND IT. `ids` is what the caller maps
			# this frame, so `slot_seen` / `slot_hand_up` / the steering diag all
			# come from a person who is NOT bound yet. This is the WAITING half of
			# the ladder at the top of the file: without it the READY raise can
			# never be confirmed and WAITING can never leave itself.
			ids[slot] = cand
			if cand == int(_cand_id[slot]):
				_cand_t[slot] += dt
			else:
				if int(_cand_id[slot]) >= 0:
					# A different person restarts the stability window (WAITING).
					_cand_exit(slot, now, "candidate changed")
				_cand_id[slot] = cand
				_cand_t[slot] = 0.0
			# WAITING -> CANDIDATE: stable in this slot's area for `stable_sec`.
			# Nothing else gates this step (in particular NOT the raise), and it is
			# checked BEFORE the bind below so a raise that completed while still
			# WAITING binds on the very frame the stability window closes.
			if int(bind_state[slot]) == BIND_WAITING \
					and float(_cand_t[slot]) >= maxf(0.0, cfg.pose.bind.stable_sec):
				_cand_enter(slot, cand, now)
			# CANDIDATE -> BOUND: the READY raise confirmation completed. main.gd
			# pushes `ready_state == 2` through `set_slot_raise_ok`, so the cards
			# and the binding FSM can never disagree about "the raise completed".
			if int(bind_state[slot]) == BIND_CANDIDATE and _raise_ok[slot]:
				_bind(slot, cand, now)
	else:
		# Frozen phase: no candidate hunting at all. A bound id that is missing is
		# handled below (coast -> lost), never replaced.
		for slot in n:
			_cand_id[slot] = -1
			_cand_t[slot] = 0.0
			if int(bound_ids[slot]) < 0:
				_cand_exit(slot, now, "phase left ready")
	# ---- pass 3: absence clock + READY re-bind timeout ----------------------
	for slot in n:
		if ids[slot] >= 0:
			_absent_t[slot] = 0.0
			_lost_logged[slot] = false
			continue
		_absent_t[slot] = minf(float(_absent_t[slot]) + dt, 1.0e6)
		if int(bound_ids[slot]) >= 0 and phase == &"ready" \
				and float(_absent_t[slot]) >= maxf(0.0, cfg.pose.bind.rebind_absent_sec):
			_unbind(slot, now, float(_absent_t[slot]))
	# ---- pass 4: regression tripwire - one person cannot feed two slots -----
	if int(ids[0]) >= 0 and int(ids[0]) == int(ids[1]):
		print("[bind] DUPLICATE id=%d on slot0+slot1 -> slot1 dropped" % int(ids[0]))
		ids[1] = -1
	return ids


## The candidate for `slot`: keep the current one while it is still legal (so a
## lower id walking past cannot restart the stability window), else the lowest id
## that is inside this slot's area and not already used by the other slot.
func _pick_candidate(slot: int, n: int, ps: Dictionary, imgw: float,
		used: Dictionary) -> int:
	var cur := int(_cand_id[slot])
	if cur >= 0 and not used.has(cur):
		var cbox: Variant = _person(ps, cur)
		if cbox != null and _in_area(slot, n, cbox, imgw):
			return cur
	var best := -1
	for key in ps.keys():
		# The key is an int in a hand-built frame and a String in the JSON frame
		# the device delivers; `_pid()` makes both mean the same person id.
		var pid := _pid(key)
		if pid < 0 or used.has(pid):
			continue
		var box: Dictionary = ps[key]
		if not _in_area(slot, n, box, imgw):
			continue
		if best < 0 or pid < best:
			best = pid
	return best


# ------------------------------------------------------- person id lookups
#
# `persons` is `YoudooBridge.latest_frame()["persons"]`, and that dictionary is a
# `JSON.parse_string` result: its keys are STRINGS ("0", "3", ...), while every id
# this file keeps in `bound_ids` / `_cand_id` is an int. These three helpers are the
# ONLY way this file may touch that dictionary; a bare `ps.has(id)` matches
# nothing on device (2026-11-14: `reason=unbound`, `slots=0`, `s0=false`).

## Dictionary key (int from a GDScript literal, String from JSON) -> person id.
## -1 when the key is not a number, which also filters junk keys out.
func _pid(key: Variant) -> int:
	match typeof(key):
		TYPE_INT:
			return int(key)
		TYPE_FLOAT:
			return int(key)
	var s := str(key)
	return s.to_int() if s.is_valid_int() else -1


## Person id -> its box, whatever the key type of `ps` is (null when absent).
func _person(ps: Dictionary, id: int) -> Variant:
	if id < 0:
		return null
	if ps.has(id):
		return ps[id]
	var k := str(id)
	return ps[k] if ps.has(k) else null


## True when `id` is in this frame (int OR String key).
func _has_person(ps: Dictionary, id: int) -> bool:
	return id >= 0 and (ps.has(id) or ps.has(str(id)))


## Slot area test. 2P: the mirrored shoulder mid-x picks the half (the READY
## panes). 1P: the whole frame is slot 0's area - there is no second half to
## steal, and the binding makes the choice sticky.
func _in_area(slot: int, n: int, box: Dictionary, imgw: float) -> bool:
	if n <= 1:
		return slot == 0
	return (_shoulder_mid_x(box, imgw) < 0.5) == (slot == 0)


## WAITING -> CANDIDATE: this person has been standing in the slot's area for
## `bind.stable_sec`. Logged once per transition, like every other binding event.
func _cand_enter(slot: int, id: int, now: float) -> void:
	bind_state[slot] = BIND_CANDIDATE
	diag["bind%d" % slot] = BIND_CANDIDATE
	print("[bind] t=%.2fs slot=%d id=%d -> cand (stable=%.2fs)" % [
		now, slot, id, float(_cand_t[slot])])


## CANDIDATE -> WAITING (the candidate left the area, was replaced, or READY
## ended). A candidate is not a binding, so nothing is published / torn down.
func _cand_exit(slot: int, now: float, why: String) -> void:
	var was := int(bind_state[slot])
	if was != BIND_CANDIDATE:
		# WAITING stays WAITING (nothing to log); BOUND is never demoted here -
		# only `_unbind` after `bind.rebind_absent_sec` may release a binding.
		return
	bind_state[slot] = BIND_WAITING
	diag["bind%d" % slot] = BIND_WAITING
	print("[bind] t=%.2fs slot=%d id=-1 -> wait (%s)" % [now, slot, why])


func _bind(slot: int, id: int, now: float) -> void:
	bound_ids[slot] = id
	bind_state[slot] = BIND_BOUND
	bind_count += 1
	diag["bound%d" % slot] = id
	diag["bind%d" % slot] = BIND_BOUND
	print("[bind] t=%.2fs slot=%d id=%d -> bound (stable=%.2fs raise=%.2fs)" % [
		now, slot, id, float(_cand_t[slot]), float(_raise_hold[slot])])


func _unbind(slot: int, now: float, absent: float) -> void:
	var old := int(bound_ids[slot])
	bound_ids[slot] = -1
	bind_state[slot] = BIND_WAITING
	_cand_id[slot] = -1
	_cand_t[slot] = 0.0
	_absent_t[slot] = 0.0
	_lost_logged[slot] = false
	unbind_count += 1
	diag["bound%d" % slot] = -1
	diag["bind%d" % slot] = BIND_WAITING
	print("[bind] t=%.2fs slot=%d id=%d -> unbind (absent=%.2fs, ready rebind)" % [
		now, slot, old, absent])


## No person for this slot on this frame. Inside `bind.grace_sec` the rules coast
## on the last heading (their own `pose.lost_timeout_ms` hold); past it the slot
## is lost. In READY the absence clock can also release the binding (pass 3).
func _coast_slot(slot: int, now: float, why: String) -> void:
	var grace: float = maxf(0.0, cfg.pose.bind.grace_sec)
	if float(_absent_t[slot]) <= grace:
		_mark_lost_slot(slot, now, "unbound" if int(bound_ids[slot]) < 0 else why)
		return
	if not _lost_logged[slot]:
		_lost_logged[slot] = true
		lost_count += 1
		print("[bind] slot=%d id=-1 -> lost (grace=%.2fs)" % [slot, grace])
	diag["reason"] = "lost"
	mappers[slot].mark_lost(now, steers[slot], true)
	diag["slot%d" % slot] = false


## No frame / no person at all: advance every slot's clock and coast/lose it. The
## BINDING IS KEPT on purpose - a 0.3 s tracking hole must not unbind a player.
func _absent_all(n: int, now: float, dt: float, why: String) -> void:
	for slot in n:
		_absent_t[slot] = minf(float(_absent_t[slot]) + dt, 1.0e6)
		if int(bound_ids[slot]) >= 0 and phase == &"ready" \
				and float(_absent_t[slot]) >= maxf(0.0, cfg.pose.bind.rebind_absent_sec):
			_unbind(slot, now, float(_absent_t[slot]))
		_coast_slot(slot, now, why)


## One compact binding line per second (never per frame, never per state change).
func _bind_second(now: float) -> void:
	if now - _bind_log_at < 1.0:
		return
	_bind_log_at = now
	if phase != &"ready" and phase != &"countdown" and phase != &"play" \
			and phase != &"pause":
		return
	print(("[bind] t=%.2fs phase=%s bound=%d,%d state=%s,%s cand=%d,%d "
		+ "stable=%.2f,%.2f absent=%.2f,%.2f persons=%d slots=%d") % [
		now, phase, int(bound_ids[0]), int(bound_ids[1]),
		String(BIND_STATE_NAMES[clampi(int(bind_state[0]), 0, 2)]),
		String(BIND_STATE_NAMES[clampi(int(bind_state[1]), 0, 2)]),
		int(_cand_id[0]), int(_cand_id[1]), float(_cand_t[0]), float(_cand_t[1]),
		float(_absent_t[0]), float(_absent_t[1]), persons, tracked_slots])


## Poll clock: the binding windows are SECONDS, so every path advances them the
## same way (a frame that carries no person still counts as absence time).
func _poll_dt(now: float) -> float:
	var dt := 0.0
	if _last_poll_at > -1.0e8:
		dt = clampf(now - _last_poll_at, 0.0, 0.25)
	_last_poll_at = now
	return dt


## Per-frame slot resets (the overlay must never show last frame's skeleton).
func _frame_start(n: int) -> void:
	for i in 2:
		slot_seen[i] = false
		slot_hand_up[i] = false
		_skel_clear(i)
	tracked_slots = 0


# --------------------------------------------------------------- internals

func _track(on: bool) -> void:
	if on != tracking:
		tracking = on
	diag["slot0"] = steers[0].valid
	diag["slot1"] = steers[1].valid


func _mark_lost_slot(slot: int, now: float, reason: String) -> void:
	diag["reason"] = reason
	mappers[slot].mark_lost(now, steers[slot])
	diag["slot%d" % slot] = false


## Mirrored shoulder-midpoint x, used for the split-screen slot assignment.
func _shoulder_mid_x(box: Dictionary, imgw: float) -> float:
	var kp: Array = box.get("kpts", [])
	var lo := _indices()
	if kp.size() <= maxi(lo["rsho"], lo["lsho"]):
		return 0.5
	var a: Array = kp[lo["rsho"]]
	var b: Array = kp[lo["lsho"]]
	if a.size() < 2 or b.size() < 2:
		return 0.5
	var ax := _flip_x(float(a[0]))
	var bx := _flip_x(float(b[0]))
	return (ax + bx) * 0.5


## Provider x -> game x (see `mirror_x`).
func _flip_x(provider_x: float) -> float:
	return 1.0 - provider_x if mirror_x else provider_x


## Keypoint index table for the active layout.
func _indices() -> Dictionary:
	match _layout:
		1:
			return {"nose": 0, "neck": -1, "rsho": 6, "lsho": 5, "relb": 8, "lelb": 7,
				"rwri": 10, "lwri": 9, "rhip": 12, "lhip": 11}
		2:
			return {"nose": 0, "neck": -1, "rsho": 12, "lsho": 11, "relb": 14, "lelb": 13,
				"rwri": 16, "lwri": 15, "rhip": 24, "lhip": 23}
		_:
			return {"nose": 0, "neck": 1, "rsho": 2, "lsho": 5, "relb": 3, "lelb": 6,
				"rwri": 4, "lwri": 7, "rhip": 8, "lhip": 11}


## Try every known layout on a few frames; lock the first plausible one.
func _resolve_layout(kp: Array, imgw: float, imgh: float) -> void:
	if _layout_locked:
		return
	var want := 0
	if kp.size() >= 33:
		want = 2
	elif kp.size() >= 17:
		# Frames come from the Youdoo SDK's AIDL FrameInfo, whose body layout is
		# `KeyPointIndex` in Modules/sdk-adapter.youdoo/.../YouDooSDKConstants.FrameInfo.cs:
		#   0 nose, 1 L eye, 2 R eye, 3 L ear, 4 R ear, 5 L shoulder, 6 R shoulder,
		#   7 L elbow, 8 R elbow, 9 L wrist, 10 R wrist, 11 L hip, 12 R hip,
		#   13 L knee, 14 R knee, 15 L ankle, 16 R ankle, 17 chest (may be absent)
		# That is layout 1 here, and it must be tried before the real COCO-18
		# order: with 18 SDK keypoints the loose plausibility test can accept the
		# COCO-18 indices (eye-as-shoulder) and then lock the wrong mapping.
		want = 1
	else:
		return
	var order := [want]
	if want == 2:
		order = [2, 0, 1] if kp.size() >= 33 else [0, 1]
	elif want == 1:
		order = [1, 0]
	elif want == 0:
		order = [0, 1]
	if _layout != order[0]:
		_layout = order[0]
	var ok := false
	for cand in order:
		_layout = cand
		if _plausible(kp, imgw, imgh):
			ok = true
			break
	if ok:
		_layout_locked = true
	_publish_skel_layout()
	diag["layout"] = LAYOUT_NAMES[_layout]


func _plausible(kp: Array, imgw: float, imgh: float) -> bool:
	var lo := _indices()
	var need := maxi(maxi(lo["rsho"], lo["lsho"]), maxi(lo["rhip"], lo["lhip"]))
	if kp.size() <= need:
		return false
	var rsho: Array = kp[lo["rsho"]]
	var lsho: Array = kp[lo["lsho"]]
	var rhip: Array = kp[lo["rhip"]]
	var lhip: Array = kp[lo["lhip"]]
	if rsho.size() < 2 or lsho.size() < 2 or rhip.size() < 2 or lhip.size() < 2:
		return false
	var shy := (float(rsho[1]) + float(lsho[1])) * 0.5 * imgh
	var hiy := (float(rhip[1]) + float(lhip[1])) * 0.5 * imgh
	var torso := absf(hiy - shy)
	# a torso is between 3% and 120% of the image height; anything else means the
	# index order is not what we assumed.
	return torso > imgh * 0.03 and torso < imgh * 1.2


func _process_slot(slot: int, box: Dictionary, imgw: float, imgh: float, now: float) -> bool:
	slot_hand_up[slot] = false
	var kp: Array = box.get("kpts", [])
	if kp.size() < 12:
		diag["reason"] = "few-kpts"
		return false
	_resolve_layout(kp, imgw, imgh)
	var lo := _indices()
	var need := maxi(maxi(lo["rsho"], lo["lsho"]), maxi(lo["rwri"], lo["lwri"]))
	if kp.size() <= need:
		diag["reason"] = "layout-mismatch"
		return false
	# ---- confidence: SDKs that do not fill kp[3] report 0 everywhere ----
	var score_sum := 0.0
	var probes := [lo["rsho"], lo["lsho"], lo["rhip"], lo["lhip"], lo["rwri"], lo["lwri"]]
	for idx in probes:
		var p: Array = kp[idx]
		if p.size() >= 4:
			score_sum += float(p[3])
	var use_scores: bool = score_sum > 0.05
	var min_vis: float = cfg.pose.min_visibility
	var rsho := _pt(kp, lo["rsho"], imgw, imgh, use_scores)
	var lsho := _pt(kp, lo["lsho"], imgw, imgh, use_scores)
	var rhip := _pt(kp, lo["rhip"], imgw, imgh, use_scores)
	var lhip := _pt(kp, lo["lhip"], imgw, imgh, use_scores)
	if rsho.z < min_vis or lsho.z < min_vis:
		diag["reason"] = "low-shoulder"
		return false
	# ---- torso frame: neck / waist / normalising length (XY plane only) ----
	var neck: Vector2 = (_xy(rsho) + _xy(lsho)) * 0.5
	var torso := 0.0
	var waist := Vector2.ZERO
	var use_hips: bool = rhip.z >= cfg.pose.hip_visibility and lhip.z >= cfg.pose.hip_visibility
	if use_hips:
		waist = (_xy(rhip) + _xy(lhip)) * 0.5
		torso = maxf(40.0, (_d2(_xy(rsho), _xy(rhip)) + _d2(_xy(lsho), _xy(lhip))) * 0.5)
	else:
		var shoulder_w := maxf(40.0, _d2(_xy(rsho), _xy(lsho)))
		waist = neck + Vector2(0.0, shoulder_w * 1.5)
		torso = shoulder_w * 1.35
	var centre: Vector2 = neck.lerp(waist, cfg.pose.center_t)
	# ---- steering reference: the RIGHT SHOULDER (owner: 胸前点位 -> 肩膀) ------
	# The vector origin is the right shoulder joint; `centre` above stays the
	# RAISE-TO-START origin (unchanged). `pose.ref_joint = &"chest"` is the
	# trace harness's replay of the previous pass, not a shipped mode.
	var ref_xy: Vector2 = _xy(rsho)
	var ref_kp: int = int(lo["rsho"])
	if String(cfg.pose.ref_joint) == "chest":
		ref_xy = centre
		ref_kp = -1
	# ---- arms ---------------------------------------------------------------
	var rw := _pt(kp, lo["rwri"], imgw, imgh, use_scores)
	var lw := _pt(kp, lo["lwri"], imgw, imgh, use_scores)
	var rel := _pt(kp, lo["relb"], imgw, imgh, use_scores)
	var lel := _pt(kp, lo["lelb"], imgw, imgh, use_scores)
	# Steering is RIGHT-ARM FIXED: a hidden right wrist loses the slot. There is
	# deliberately NO "use the other hand" fallback here - the owner asked for the
	# right side only, and a silent left fallback would make the `[pose]` log lie
	# about which hand is steering. (The right shoulder was already gated above.)
	if rw.z < min_vis:
		diag["reason"] = "low-arm"
		return false
	var rd := _d2(_xy(rw), centre) / torso
	var ld := _d2(_xy(lw), centre) / torso
	# ---- arm pick: "auto" = wrist further from the chest, with hysteresis ----
	# 1.15 was not enough: with both arms similarly extended the two distances
	# cross every frame, so the pick flapped left/right and the target angle
	# flipped by ~180 deg (owner: 有时会乱移动). Now the other wrist must be
	# `arm_hysteresis` further AND the current arm must have been held for
	# `arm_min_dwell_sec`, so a switch is always a deliberate, rare event. Since
	# the right-arm-fixed pass this pick NO LONGER steers: it feeds the raise test
	# and the later left-side option only (see the `update_wrist` call below).
	var hyst: float = maxf(1.0, cfg.pose.arm_hysteresis)
	var dwell: float = maxf(0.0, cfg.pose.arm_min_dwell_sec)
	var pick := 0
	if _hand[slot] < 0:
		pick = 1 if ld > rd else 0
	elif now - _hand_at[slot] >= dwell:
		if ld > rd * hyst:
			pick = 1
		elif rd > ld * hyst:
			pick = 0
		else:
			pick = _hand[slot]
	else:
		pick = _hand[slot]
	var wrist3: Vector3 = lw if pick == 1 else rw
	var elbow3: Vector3 = lel if pick == 1 else rel
	var wvis: float = wrist3.z
	var evis: float = elbow3.z
	if wvis < min_vis:
		# Only the LEFT wrist can be invisible here (the right one is gated above).
		# A dropout is not a choice: fall back to the visible arm immediately.
		pick = 0
		wrist3 = rw
		elbow3 = rel
		wvis = rw.z
	if evis < min_vis and use_scores:
		diag["reason"] = "low-elbow"
		return false
	if pick != _hand[slot]:
		_hand_at[slot] = now
		# NOTE: no `on_hand_switch()` here any more. The pick does not switch the
		# steering arm (right-fixed), so restarting the position filter on a
		# left-arm event would snap the right-shoulder vector for no reason.
	_hand[slot] = pick
	var wrist: Vector2 = _xy(wrist3)
	# "either hand" ready check: both wrists are tested against the same
	# normalised raise threshold the menu shortcut uses (`pose.raise_to_start`).
	# Visibility is required only when the SDK actually reports scores.
	var raise_n: float = cfg.pose.raise_to_start
	var r_up: bool = (not use_scores or rw.z >= min_vis) \
		and (centre.y - _xy(rw).y) / torso >= raise_n
	var l_up: bool = (not use_scores or lw.z >= min_vis) \
		and (centre.y - _xy(lw).y) / torso >= raise_n
	slot_hand_up[slot] = r_up or l_up
	# RIGHT wrist around the RIGHT shoulder. `pose.ref_joint=&"chest"` only moves
	# the origin (previous pass); the wrist is the right one either way.
	# 2026-11-17 (owner: 左/上伸手偏慢): the LEFT arm is handed over too, but only
	# as the SPEED distance (`max(|rwr-rsh|, |lwr-lsh|) / torso`). Steering stays
	# right-arm fixed; the left arm is ignored when its wrist is below
	# `pose.min_visibility`, and the mapper itself drops a passive hanging arm.
	var has_left: bool = lw.z >= min_vis
	mappers[slot].update_wrist(_xy(rw), ref_xy, torso, now, steers[slot],
		_xy(lw) if has_left else null, _xy(lsho) if has_left else null,
		rw.z, lw.z)
	diag["ref"] = String(cfg.pose.ref_joint)
	diag["kp"] = ref_kp
	diag["hand"] = "right" if pick == 0 else "left"
	diag["dist_n"] = mappers[slot].last_dist_n
	diag["spd_n"] = mappers[slot].last_speed_dist_n
	diag["angle"] = steers[slot].steer_angle_rad
	diag["torso"] = torso
	# The published angle is HELD by two independent gates: the wrist dead zone
	# (hand near the reference) and the arm-hanging gate (下垂识别, a lowered arm).
	# Both publish `conf=0.00`; only the hanging one names itself in `reason`, so a
	# device log reads `... conf=0.00 ... reason=arm-low` while the snake keeps its
	# heading. The slot stays VALID (`s0=true`): the person is present and the
	# READY raise test below still runs.
	var hold_dz: bool = not mappers[slot].last_deadzone_pass
	var hold_hang: bool = mappers[slot].last_hang
	diag["conf"] = 0.0 if (hold_dz or hold_hang) else 1.0
	diag["reason"] = "arm-low" if hold_hang else ""
	diag["slot%d" % slot] = steers[slot].valid
	# ---- overlay snapshot (provider space; the HUD applies the camera transform)
	_skel_fill(slot, kp, pick, torso, imgw, imgh, mappers[slot])
	# ---- raise-a-hand-to-start (menu shortcut) ----
	# Same grace window as the READY cards: a single frame with the wrist just
	# under the threshold keeps the accumulated hold for PSRaiseHold.GRACE_SEC
	# and the count resumes if the hand comes back inside it.
	var raised: bool = (centre.y - wrist.y) / torso >= cfg.pose.raise_to_start
	if slot == 0:
		var dt_raise := clampf(now - _raise_last, 0.0, 0.2)
		_raise_last = now
		_raise.step(now, dt_raise, raised, true, cfg.pose.raise_hold_sec)
	return true


func _pt(kp: Array, idx: int, imgw: float, imgh: float, use_scores: bool) -> Vector3:
	var p: Array = kp[idx] if idx < kp.size() else []
	if p.size() < 2:
		return Vector3(0.0, 0.0, 0.0)
	var nx := _flip_x(float(p[0]))
	var ny := float(p[1])
	var vis := float(p[3]) if (use_scores and p.size() >= 4) else 1.0
	return Vector3(nx * imgw, ny * imgh, vis)


## Geometry half of a keypoint (the z component carries visibility only).
func _xy(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y)


## XY-plane distance (the z component carries the visibility, never geometry).
func _d2(a: Vector2, b: Vector2) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return sqrt(dx * dx + dy * dy)


# ------------------------------------------------- verification / capture hooks

## Verification only (`--capture-pose-trace`, `--capture-skeleton`): push a
## synthetic SDK skeleton through the REAL per-slot pipeline - layout validation,
## torso frame, arm pick with hysteresis + dwell, mapper filters, overlay
## snapshot - without a plugin. Exactly the same code path `poll()` uses, so a
## trace through this hook measures the shipped law, not a copy of it.
## `kpts` has the bridge frame's shape: `[[x, y, z, score], ...]` normalised.
func ingest_test_skeleton(slot: int, kpts: Array, imgw: float, imgh: float,
		now_sec: float) -> bool:
	if slot < 0 or slot > 1:
		return false
	return _process_slot(slot, {"kpts": kpts}, imgw, imgh, now_sec)


## True once the player held one hand up for `pose.raise_hold_sec` (one-shot:
## consuming it clears the hold, including any grace window).
func hand_raised() -> bool:
	var v: bool = _raise.latched
	_raise.reset()
	return v


# ------------------------------------------------- skeleton overlay snapshot

## Refill slot `slot`'s overlay snapshot from the newest keypoints. Everything is
## written in place (the Packed arrays are pre-sized), so this allocates nothing.
func _skel_fill(slot: int, kp: Array, pick: int, torso: float, imgw: float,
		imgh: float, mapper) -> void:
	var pts: PackedVector2Array = skel_pts[slot]
	var ok: PackedByteArray = skel_ok[slot]
	var n: int = mini(kp.size(), SKEL_MAX)
	var min_vis: float = cfg.pose.min_visibility
	for i in SKEL_MAX:
		ok[i] = 0
	for i in n:
		var p: Array = kp[i]
		if p.size() < 2:
			continue
		var x := float(p[0])
		var y := float(p[1])
		if not is_finite(x) or not is_finite(y):
			continue
		# Provider space: no `_flip_x`, the HUD mirrors with the camera texture.
		pts[i] = Vector2(x, y)
		if p.size() >= 4 and float(p[3]) < min_vis:
			continue
		ok[i] = 1
	skel_n[slot] = n
	skel_on[slot] = n > 0
	skel_wrist[slot] = pick
	# The steering reference is the mapper's FILTERED reference point (that is what
	# the game is actually steering around - the right shoulder), un-mirrored back
	# into provider space. The HUD draws its one lime dot + dead-zone ring here.
	var c: Vector2 = mapper.last_filtered_ref
	var cu := (1.0 - c.x / imgw) if mirror_x else (c.x / imgw)
	skel_ref[slot] = Vector2(cu, c.y / maxf(1.0, imgh))
	skel_ref_ok[slot] = true
	# Dead-zone radius as a fraction of the image width (0 when filtering is off).
	skel_dead_u[slot] = cfg.pose.deadzone * torso / maxf(1.0, imgw)


## Publish the overlay's layout-dependent tables (bone list + wrist indices).
## Called once at construction and once per layout resolution, never per frame.
func _publish_skel_layout() -> void:
	var lo := _indices()
	skel_bones = SKEL_BONES[clampi(_layout, 0, SKEL_BONES.size() - 1)]
	skel_rwri = int(lo["rwri"])
	skel_lwri = int(lo["lwri"])
	# Steering is right-arm fixed: the bright hand dot, the shoulder->hand line and
	# the vector all use THIS wrist. The left wrist keeps a dim joint dot only.
	skel_steer_wri = skel_rwri


func _skel_clear(slot: int) -> void:
	skel_on[slot] = false
	skel_n[slot] = 0
	skel_wrist[slot] = -1
	skel_ref_ok[slot] = false
	skel_dead_u[slot] = 0.0
	if slot < skel_ok.size():
		var ok: PackedByteArray = skel_ok[slot]
		for i in ok.size():
			ok[i] = 0
