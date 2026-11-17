extends SceneTree
## Probe for the body-keypoint layout table in `src/present/ps_pose_input.gd`.
##
## The Youdoo SDK's AIDL FrameInfo delivers 18 body keypoints in the order defined
## by `KeyPointIndex` (Modules/sdk-adapter.youdoo/.../YouDooSDKConstants.FrameInfo.cs):
##   0 nose, 1 L eye, 2 R eye, 3 L ear, 4 R ear, 5 L shoulder, 6 R shoulder,
##   7 L elbow, 8 R elbow, 9 L wrist, 10 R wrist, 11 L hip, 12 R hip,
##   13 L knee, 14 R knee, 15 L ankle, 16 R ankle, 17 chest
##
## The pose input must lock onto that layout when it sees 18 keypoints, and must
## NOT lock onto the real COCO-18 order (2 = R shoulder), which would read eyes
## as shoulders and run the torso maths on garbage.
##
## Run:  godot --headless --path <proj> --script res://tests/_probe_kp_layout.gd

const PSConfig = preload("res://src/core/config.gd")
const PSPoseInput = preload("res://src/present/ps_pose_input.gd")

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  PASS  %s%s" % [label, "" if detail.is_empty() else "  (" + detail + ")"])
	else:
		_fails += 1
		print("  FAIL  %s%s" % [label, "" if detail.is_empty() else "  (" + detail + ")"])


## Builds a plausible standing person in the Youdoo keypoint order, normalised
## [0,1] top-left. Values are irrelevant beyond "shoulders above hips, wrists out".
func _youdoo_frame() -> Array:
	var kp := []
	kp.resize(18)
	for i in 18:
		kp[i] = [0.5, 0.5, 0.0]
	kp[0] = [0.50, 0.20, 0.95]   # nose
	kp[1] = [0.47, 0.19, 0.9]    # L eye
	kp[2] = [0.53, 0.19, 0.9]    # R eye
	kp[3] = [0.44, 0.20, 0.8]    # L ear
	kp[4] = [0.56, 0.20, 0.8]    # R ear
	kp[5] = [0.40, 0.32, 0.95]   # L shoulder
	kp[6] = [0.60, 0.32, 0.95]   # R shoulder
	kp[7] = [0.34, 0.45, 0.9]    # L elbow
	kp[8] = [0.66, 0.45, 0.9]    # R elbow
	kp[9] = [0.28, 0.58, 0.9]    # L wrist
	kp[10] = [0.72, 0.58, 0.9]   # R wrist
	kp[11] = [0.43, 0.62, 0.9]   # L hip
	kp[12] = [0.57, 0.62, 0.9]   # R hip
	kp[13] = [0.43, 0.80, 0.8]   # L knee
	kp[14] = [0.57, 0.80, 0.8]   # R knee
	kp[15] = [0.43, 0.96, 0.7]   # L ankle
	kp[16] = [0.57, 0.96, 0.7]   # R ankle
	kp[17] = [0.50, 0.43, 0.9]   # chest
	return kp


func _initialize() -> void:
	print("=".repeat(64))
	print("keypoint layout probe (Youdoo SDK 18-point order)")
	print("=".repeat(64))

	var cfg = PSConfig.new()
	var pose = PSPoseInput.new(cfg, null)

	# 1) the SDK order must win for an 18-keypoint frame
	pose._layout_locked = false
	pose._layout = 0
	pose._resolve_layout(_youdoo_frame(), 1920.0, 1080.0)
	_check("18 SDK keypoints lock the Youdoo layout", int(pose._layout) == 1, "layout=%s" % pose.diag["layout"])
	_check("layout is locked after validation", bool(pose._layout_locked))
	_check("layout name reported to the HUD is youdoo18", String(pose.diag["layout"]) == "youdoo18")

	# 2) the resolved table must point at the right joints
	var idx: Dictionary = pose._indices()
	_check("left shoulder = 5", int(idx["lsho"]) == 5, str(idx["lsho"]))
	_check("right shoulder = 6", int(idx["rsho"]) == 6, str(idx["rsho"]))
	_check("left wrist = 9", int(idx["lwri"]) == 9, str(idx["lwri"]))
	_check("right wrist = 10", int(idx["rwri"]) == 10, str(idx["rwri"]))
	_check("left hip = 11", int(idx["lhip"]) == 11, str(idx["lhip"]))
	_check("right hip = 12", int(idx["rhip"]) == 12, str(idx["rhip"]))

	# 3) plausibility must accept a real person and reject a collapsed torso
	_check("standing person is plausible", bool(pose._plausible(_youdoo_frame(), 1920.0, 1080.0)))

	var flat := _youdoo_frame()
	flat[5] = [0.40, 0.90, 0.95]
	flat[6] = [0.60, 0.90, 0.95]
	flat[11] = [0.43, 0.905, 0.9]
	flat[12] = [0.57, 0.905, 0.9]
	_check("collapsed torso is rejected", not bool(pose._plausible(flat, 1920.0, 1080.0)))

	# 4) a hand frame with only 17 keypoints still resolves (chest optional)
	var short := _youdoo_frame()
	short.resize(17)
	var pose2 = PSPoseInput.new(cfg, null)
	pose2._resolve_layout(short, 1920.0, 1080.0)
	_check("17-keypoint frame (no chest) still locks the Youdoo layout", int(pose2._layout) == 1)

	print("=".repeat(64))
	if _fails == 0:
		print("RESULT: PASS - keypoint layout probe")
	else:
		print("RESULT: FAIL - %d check(s) failed" % _fails)
	print("=".repeat(64))
	quit(0 if _fails == 0 else 1)
