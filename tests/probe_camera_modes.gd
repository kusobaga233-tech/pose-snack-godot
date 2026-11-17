extends SceneTree
## Manual probe (NOT part of `run_all.gd`, so the 444-assertion suite count is
## unchanged): the SDK-derived camera variants and the exact per-view AIDL
## values `main.gd` hands to `YoudooBridge.camera_live_view()`.
##
##   tools\run_godot_safe.ps1 -Script res://tests/probe_camera_modes.gd -TimeoutSeconds 60
##
## Runs on desktop with a fake bridge (records every send), so no SDK service and
## no device are involved. It proves:
##   * the shipped default is variant 0 (mirror H + pose 1-x) and inverts A.x;
##   * F6 cycles 1/3 -> 2/3 (raw preview + raw pose) -> 3/3 (H+V) -> 1/3;
##   * 1P sends one view (id 0), 2P sends two views (id 0 left / id 1 right),
##     each cropped to its own sensor half and mirrored with the variant;
##   * the teardown path calls camera_live_clear() (clearAllCameraLiveOnScreen);
##   * the F3 HUD fields follow;
##   * the legacy YoudooBridge.camera_live_start(A, B, mode) signature still works.

const PSTest = preload("res://tests/pstest.gd")
const MainScript = preload("res://src/main.gd")
const BridgeScript = preload("res://src/youdoo_bridge.gd")

const PIP_BR := Rect2(0.76, 0.74, 0.22, 0.22)
const PIP_TL := Rect2(0.02, 0.02, 0.28, 0.32)
const TWO_P_DEST_0 := [0.02, 0.70, 0.17, 0.98]
const TWO_P_DEST_1 := [0.83, 0.70, 0.98, 0.98]


## Records what main.gd sends without touching JNI.
class FakeBridge:
	extends Node
	var calls: Array = []
	var clears: int = 0

	func is_available() -> bool:
		return true

	func camera_live_supported() -> bool:
		return true

	func camera_live_view(id: int, on: bool, src: Array, dst: Array, mode: int = 0) -> bool:
		calls.append({"id": id, "on": on, "src": src.duplicate(), "dst": dst.duplicate(),
			"mode": mode})
		return true

	func camera_live_clear() -> void:
		clears += 1
		calls.append({"clear": true})

	func camera_live_stop() -> void:
		clears += 1
		calls.append({"clear": true})

	func camera_live_active() -> bool:
		return true


func _eq4(got: Array, want: Array) -> bool:
	# Godot's Rect2 stores 32-bit reals, so compare with a tolerance.
	if got.size() != 4:
		return false
	for i in 4:
		if absf(float(got[i]) - float(want[i])) > 0.0005:
			return false
	return true


func _initialize() -> void:
	_run()


func _run() -> void:
	var t = PSTest.new()
	t.suite("camera variants (SDK-derived)")

	var main = MainScript.new()
	get_root().add_child(main)
	await process_frame

	# ---- shipped default -----------------------------------------------------
	t.eq_int("boot variant is 0 (1/3 SDK mirror)", main._camera_variant_index, 0)
	t.eq_str("boot variant name", main._camera_mode_name(main._camera_variant_index),
		"SDK mirror H")
	t.eq_bool("boot pose convention is 1-x", main.pose.mirror_x, true)
	t.ok("boot 1P pip rect is the shipped bottom-right", main._camera_live_rect == PIP_BR,
		str(main._camera_live_rect))
	t.eq_bool("boot camera live is not applied yet", main._camera_live_on, false)

	# ---- 1P default send: one view, mirrored source --------------------------
	var fake = FakeBridge.new()
	get_root().add_child(fake)
	main.bridge = fake
	main.player_count = 1
	main._camera_live_wanted = true
	main._apply_camera_live("probe")
	t.eq_int("1P sends exactly one view", fake.calls.size(), 1)
	var sent: Dictionary = fake.calls[0] if fake.calls.size() > 0 else {}
	t.eq_int("1P view id", int(sent.get("id", -1)), 0)
	t.eq_bool("1P view is ON", bool(sent.get("on", false)), true)
	t.ok("1P source x is inverted (mirror)", _eq4(sent.get("src", []), [1.0, 0.0, 0.0, 1.0]),
		str(sent.get("src", [])))
	t.ok("1P dest stays the bottom-right pip",
		_eq4(sent.get("dst", []), [0.76, 0.74, 0.98, 0.96]), str(sent.get("dst", [])))
	t.eq_int("1P AIDL mode is 0", int(sent.get("mode", -1)), 0)
	t.eq_bool("service accepted the default send", main._camera_live_on, true)

	# ---- F6: 1/3 (H) -> 2/3 (H+V) -> 3/3 (raw) -> 1/3 ------------------------
	main._cycle_camera_mode()
	t.eq_int("F6 #1 = variant 2/3", main._camera_variant_index, 1)
	var hv: Dictionary = fake.calls[fake.calls.size() - 1]
	t.ok("2/3 inverts both axes", _eq4(hv.get("src", []), [1.0, 1.0, 0.0, 0.0]),
		str(hv.get("src", [])))

	main._cycle_camera_mode()
	t.eq_int("F6 #2 = variant 3/3", main._camera_variant_index, 2)
	var raw: Dictionary = fake.calls[fake.calls.size() - 1]
	t.ok("3/3 sends the raw source rect", _eq4(raw.get("src", []), [0.0, 0.0, 1.0, 1.0]),
		str(raw.get("src", [])))

	main._cycle_camera_mode()
	t.eq_int("F6 #3 wraps to variant 1/3", main._camera_variant_index, 0)
	t.eq_bool("camera cycle never touches the pose convention", main.pose.mirror_x, true)

	# ---- INFO/KEY_F7: independent pose toggle, live -------------------------
	main._toggle_pose_mirror("probe")
	t.eq_bool("pose toggle flips mirror_x", main.pose.mirror_x, false)
	t.eq_bool("pose toggle updates main's state", main._pose_mirror, false)
	main._toggle_pose_mirror("probe")
	t.eq_bool("pose toggle flips back", main.pose.mirror_x, true)

	# ---- 2P: two views, own sensor half each ---------------------------------
	main.player_count = 2
	fake.calls.clear()
	main._apply_camera_live("probe-2p")
	t.eq_int("2P sends exactly two views", fake.calls.size(), 2)
	var p1: Dictionary = fake.calls[0] if fake.calls.size() > 0 else {}
	var p2: Dictionary = fake.calls[1] if fake.calls.size() > 1 else {}
	t.eq_int("2P P1 view id", int(p1.get("id", -1)), 0)
	t.eq_int("2P P2 view id", int(p2.get("id", -1)), 1)
	t.ok("2P P1 crops the raw right half, mirrored",
		_eq4(p1.get("src", []), [1.0, 0.0, 0.5, 1.0]), str(p1.get("src", [])))
	t.ok("2P P2 crops the raw left half, mirrored",
		_eq4(p2.get("src", []), [0.5, 0.0, 0.0, 1.0]), str(p2.get("src", [])))
	t.ok("2P P1 dest is bottom-left", _eq4(p1.get("dst", []), TWO_P_DEST_0),
		str(p1.get("dst", [])))
	t.ok("2P P2 dest is bottom-right", _eq4(p2.get("dst", []), TWO_P_DEST_1),
		str(p2.get("dst", [])))

	# ---- 2P with the pose raw: halves swap, nothing is inverted --------------
	main._camera_variant_index = 2
	main._pose_mirror = false
	main.pose.set_mirror_x(false)
	fake.calls.clear()
	main._apply_camera_live("probe-2p-raw")
	var r1: Dictionary = fake.calls[0] if fake.calls.size() > 0 else {}
	var r2: Dictionary = fake.calls[1] if fake.calls.size() > 1 else {}
	t.ok("raw 2P P1 crops the raw left half", _eq4(r1.get("src", []), [0.0, 0.0, 0.5, 1.0]),
		str(r1.get("src", [])))
	t.ok("raw 2P P2 crops the raw right half", _eq4(r2.get("src", []), [0.5, 0.0, 1.0, 1.0]),
		str(r2.get("src", [])))

	# ---- teardown: clearAll path --------------------------------------------
	main._camera_variant_index = 0
	main._pose_mirror = true
	main.pose.set_mirror_x(true)
	main._camera_live_wanted = false
	fake.clears = 0
	main._apply_camera_live("probe-off")
	t.eq_int("teardown calls camera_live_clear() once", fake.clears, 1)
	t.eq_int("teardown forgets every id", main._camera_views_on.size(), 0)

	# ---- F3 HUD fields ------------------------------------------------------
	main.player_count = 2
	main._poll_bridge_status(0.0)
	t.eq_str("hud variant label", main.hud.cam_mode_label, "1/3 SDK mirror H")
	t.eq_int("hud shows both views", main.hud.cam_views.size(), 2)
	t.eq_bool("hud follows the pose convention", main.hud.cam_pose_mirror, true)

	# ---- F5 stays 1P-only, legacy bridge signature stays callable ------------
	main.player_count = 1
	main._camera_live_wanted = true
	main._cycle_camera_rect()
	var f5: Dictionary = fake.calls[fake.calls.size() - 1]
	t.ok("F5 moves the 1P pip to the top-left",
		_eq4(f5.get("dst", []), [0.02, 0.02, 0.30, 0.34]), str(f5.get("dst", [])))

	var real = BridgeScript.new()
	get_root().add_child(real)
	t.eq_bool("YoudooBridge.camera_live_start(A, B, mode) is callable (desktop no-op)",
		real.camera_live_start(Rect2(0.0, 0.0, 1.0, 1.0), PIP_BR, 0), false)

	quit(t.summary())
