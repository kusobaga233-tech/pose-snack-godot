extends SceneTree
## `--capture-bind`-style headless trace for the 2026-11-14 READY binding fix.
##
##   godot --headless --path <project> --script res://tests/probe_bind_trace.gd
##
## Drives the SHIPPED binding FSM (`PSPoseInput.poll_frame` + the same
## `PSRaiseHold` / READY thresholds `main.gd` uses) with DEVICE-SHAPED frames:
## every frame is a `JSON.parse_string()` result, so `persons` keys are the
## strings the YoudooBridge actually delivers. One person stands still in a 1P
## READY screen and raises the right hand at t=1.0 s.
##
## It prints the FSM's own `[bind]` transition/second lines plus the exact
## `[pose] ...` format from main.gd's `_print_pose_diag()`, so a log from the box
## can be compared line for line against this file.
##
## EXPECTED (the fix): seen=true from frame 1 while state=wait, `-> cand` at
## ~stable_sec, `-> bound` once the raise confirmation completes (zone 1.0 s +
## raise 1.5 s after the hand goes up), i.e. wait -> cand -> bound in < 5 s.

const PSConfig = preload("res://src/core/config.gd")
const PSPoseInput = preload("res://src/present/ps_pose_input.gd")
const PSRaiseHold = preload("res://src/present/ps_raise_hold.gd")
const SuiteInput = preload("res://tests/suite_input.gd")

## main.gd's READY gate (kept in sync by hand: READY_ZONE_SEC / READY_RAISE_SEC).
const ZONE_SEC := 1.0
const RAISE_SEC := 1.5
const DT := 1.0 / 60.0
const DURATION := 6.0
const HAND_UP_AT := 1.0
const POSE_EVERY := 0.25
const MARK_EVERY := 1.0


## One person at game-x 0.5, right wrist hanging at `raised` = 0, up at = 1.
static func _body(raised: float) -> Dictionary:
	var body: Dictionary = SuiteInput._body(0.5)
	var kp: Array = body["kpts"]
	# Provider space, mirror ON: index 10 is the right wrist. At rest it hangs
	# LOW (below the RAISE threshold, which is measured from the chest), out to
	# the side so it is outside both the hanging cone and the dead zone; the
	# raise lifts it above the shoulder. The rest pose must NOT count as a raise,
	# or the trace would confirm ready without the gesture.
	var sho: float = float(kp[6][1])
	var x: float = float(kp[10][0])
	kp[10] = [x, lerpf(sho + 0.20, sho - 0.22, raised), 0.0, 1.0]
	return {"kpts": kp}


static func _frame(raised: float) -> Dictionary:
	var f: Dictionary = {
		"imageWidth": SuiteInput.BIND_W, "imageHeight": SuiteInput.BIND_H,
		"persons": {"3": _body(raised)}}
	return JSON.parse_string(JSON.stringify(f))


## Byte-identical to main.gd `_print_pose_diag()`: same fields, same order, no
## trace-only timestamp on this line (the `[bind]` lines carry `t=` already, which
## is exactly the shipped format, so the two can be lined up on the box too).
static func _pose_line(pin) -> void:
	var d: Dictionary = pin.diag
	print("[pose] layout=%s ref=%s kp=%d hand=%s dist_n=%.2f angle=%.3f conf=%.2f torso=%.0f reason=%s s0=%s s1=%s persons=%d slots=%d age=%dms bound=%d,%d" % [
		String(d.get("layout", "?")), String(d.get("ref", "?")), int(d.get("kp", -1)),
		String(d.get("hand", "-")), float(d.get("dist_n", 0.0)),
		float(d.get("angle", 0.0)), float(d.get("conf", 0.0)), float(d.get("torso", 0.0)),
		String(d.get("reason", "")), str(d.get("slot0", false)), str(d.get("slot1", false)),
		pin.persons, pin.tracked_slots, pin.frame_age(),
		int(d.get("bound0", -1)), int(d.get("bound1", -1))])


func _initialize() -> void:
	var cfg = PSConfig.new()
	var pin = PSPoseInput.new(cfg, null)
	print("[trace] device-shaped frames (JSON string person keys), 1P READY, hand up at %.1fs" % HAND_UP_AT)
	print("[trace] stable_sec=%.2f zone_sec=%.1f raise_sec=%.1f grace_sec=%.2f" % [
		cfg.pose.bind.stable_sec, ZONE_SEC, RAISE_SEC, cfg.pose.bind.grace_sec])
	pin.set_phase(&"ready")
	var rh = PSRaiseHold.new()
	var zone := 0.0
	var raise_confirmed := false
	var t := 0.0
	var next_pose := 0.0
	var next_mark := 0.0
	var bound_at := -1.0
	var cand_at := -1.0
	var seen_at := -1.0
	while t < DURATION:
		var up: bool = t >= HAND_UP_AT
		var f: Dictionary = _frame(1.0 if up else 0.0)
		pin.poll_frame(t, 1, f)
		if seen_at < 0.0 and bool(pin.slot_seen[0]):
			seen_at = t
		if cand_at < 0.0 and int(pin.bind_state[0]) == PSPoseInput.BIND_CANDIDATE:
			cand_at = t
		if bound_at < 0.0 and int(pin.bind_state[0]) == PSPoseInput.BIND_BOUND:
			bound_at = t
		# ---- main.gd `_ready_step` equivalent (same thresholds) --------------
		zone = minf(zone + DT, ZONE_SEC)
		rh.step(t, DT, bool(pin.slot_hand_up[0]), zone >= ZONE_SEC, RAISE_SEC)
		pin.set_slot_raise_ok(0, rh.hold >= RAISE_SEC or raise_confirmed, rh.hold)
		if rh.hold >= RAISE_SEC:
			raise_confirmed = true
		# The `[pose]` line itself is byte-identical to the shipped one; the trace
		# clock rides on a separate 1 Hz marker so the two never get confused.
		if t >= next_mark:
			next_mark += MARK_EVERY
			print("[trace] t=%.2fs" % t)
		if t >= next_pose:
			next_pose += POSE_EVERY
			_pose_line(pin)
		t += DT
	print("[trace] seen at %.2fs, cand at %.2fs, bound at %.2fs (wait->cand->bound)" % [
		seen_at, cand_at, bound_at])
	print("[trace] final: state=%s bound=%d seen=%s slots=%d" % [
		String(PSPoseInput.BIND_STATE_NAMES[int(pin.bind_state[0])]),
		int(pin.bound_ids[0]), str(pin.slot_seen[0]), pin.tracked_slots])
	var ok: bool = seen_at >= 0.0 and seen_at <= 0.05 \
		and cand_at > 0.4 and cand_at < 1.0 \
		and bound_at > 2.0 and bound_at < 4.0 \
		and int(pin.bound_ids[0]) == 3
	print("[trace] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
