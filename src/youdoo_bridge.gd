extends Node

## Autoload wrapper for the YoudooSkeleton Android plugin.
##
## The plugin (android/src/com/youdoo/godot/YoudooSkeletonPlugin.java) binds the
## YoudooGame SDK AIDL service, keeps the newest body-tracking frame and exposes
## it as JSON. This node polls that JSON and turns it into Godot types, so the
## rest of the game never touches JNI.
##
## Degrades gracefully: on desktop/editor (or when the plugin is missing) every
## call is a no-op and returns empty data instead of crashing.

signal frame_received(frame: Dictionary)
signal tracking_changed(tracking: bool)

const PLUGIN_NAME := "YoudooSkeleton"
## How often the native frame counter is polled (seconds). 20 Hz is enough for
## gameplay that consumes the latest pose, and costs one JNI call per tick.
const POLL_INTERVAL := 0.05
## A frame older than this means tracking is considered lost.
const STALE_AFTER_MS := 1500

var _plugin: Object = null
var _available := false
var _reason := ""
var _started := false
var _poll_accum := 0.0
var _frame_count := 0
var _last_frame_ticks := 0
var _tracking := false
var _latest: Dictionary = {}

## Newest camera-frame sequence number already handed to the caller, so a poll can
## never deliver the same frame twice even if the worker published while it ran.
var _cam_seq := 0
## 0 = untested, 1 = the plugin's byte[] marshals to PackedByteArray, 2 = base64.
var _cam_bytes_mode := 0


func _ready() -> void:
	# Autoloads run on the main thread; polling only makes sense while started.
	set_process(false)
	if not OS.has_feature("android"):
		_reason = "desktop/editor build (OS.has_feature('android') is false)"
		return
	if not Engine.has_singleton(PLUGIN_NAME):
		_reason = "plugin singleton '%s' is not registered" % PLUGIN_NAME
		push_warning("[YoudooBridge] " + _reason)
		return
	_plugin = Engine.get_singleton(PLUGIN_NAME)
	_available = true
	print("[YoudooBridge] plugin available: %s" % PLUGIN_NAME)


## True when the native plugin loaded (does not imply the SDK service is bound).
func is_available() -> bool:
	return _available


## Human readable reason why the bridge is unavailable ("" when available).
func unavailable_reason() -> String:
	return _reason


## Binds the SDK service and starts polling. Safe to call when unavailable.
func start() -> bool:
	if not _available:
		return false
	var ok: bool = bool(_plugin.start())
	_started = ok
	_poll_accum = 0.0
	set_process(true)
	if not ok:
		_reason = "native start() returned false (see logcat tag YoudooSkeleton)"
	print("[YoudooBridge] start() -> %s" % ok)
	return ok


## Unbinds the SDK service and stops polling.
func stop() -> void:
	if not _available:
		return
	_started = false
	set_process(false)
	camera_frames_stop()
	_plugin.stop()
	_set_tracking(false)
	print("[YoudooBridge] stop()")


## JSON status with the bridge keys plus the camera-live state the plugin
## reported: {"bound":bool,"binder":String,"frames":int,"lastFrameMs":int,
##             "cameraSupported":bool,"cameraLive":bool,"cameraMode":int,
##             "cameraViews":int}.
## Always has the same keys so callers can read it unconditionally.
func status() -> Dictionary:
	var empty := {
		"bound": false,
		"binder": "none",
		"frames": 0,
		"lastFrameMs": 0,
		"cameraSupported": false,
		"cameraLive": false,
		"cameraMode": 0,
		"cameraViews": 0,
	}
	if not _available:
		empty["error"] = _reason
		return empty
	var parsed: Variant = JSON.parse_string(_plugin.status())
	if typeof(parsed) != TYPE_DICTIONARY:
		empty["error"] = "unparsable status json"
		return empty
	return parsed


## True only while the V1_0_3 SDK binder is bound; the V1_0_2 fallback has no
## camera API. Off-device this is always false.
func camera_live_supported() -> bool:
	if not _available:
		return false
	return bool(_plugin.cameraLiveSupported())


## Turns the SDK's camera preview on. The preview is composited by the device
## service in its own overlay window (no texture upload, no extra draw here), so
## it is drawn ABOVE this app, not behind it — callers must place their UI with
## that in mind or use a bounded destination rect.
##
## The AIDL call carries TWO normalized rect pairs, A then B:
##   A = `source_rect`  the crop taken from the camera frame (proven on device)
##   B = `dest_rect`    the destination rectangle on screen  (proven on device)
## The values are passed through unclamped, so an INVERTED source rect
## (x2 < x1) asks the native renderer for a horizontal flip: that is the SDK's
## own mirror mechanism (Unity's CameraImageUvRegionUtility flips by making the
## UV width negative). `mode` is the opaque AIDL int (0 in the SDK's own
## reference app and the only value the SDK ever sends). Returns true only when
## the service accepted the call (the request is still remembered on failure).
##
## This is the legacy single-view (id 0) form; `camera_live_view` drives any id.
func camera_live_start(source_rect: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0),
		dest_rect: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0), mode: int = 0) -> bool:
	var src := [source_rect.position.x, source_rect.position.y,
		source_rect.end.x, source_rect.end.y]
	var dst := [dest_rect.position.x, dest_rect.position.y,
		dest_rect.end.x, dest_rect.end.y]
	return camera_live_view(0, true, src, dst, mode)


## Drives ONE camera-live view by AIDL id. The SDK service keeps a
## HashMap<Integer, view>, so id 0 and id 1 can be on at the same time (one
## per player in 2P). `src` and `dst` are 4-element arrays in AIDL wire order
## [x1, y1, x2, y2]; `src` may be inverted on either axis (x1 > x2 / y1 > y2)
## to mirror, exactly like the SDK's signed UV rect. Nothing is clamped.
## Returns true only when the service accepted this call.
func camera_live_view(id: int, on: bool, src: Array, dst: Array, mode: int = 0) -> bool:
	if not _available:
		print("[YoudooBridge] camera_live_view(id=%d, on=%s): no plugin (no-op)" % [id, on])
		return false
	if id < 0 or src.size() != 4 or dst.size() != 4:
		push_warning("[YoudooBridge] camera_live_view: bad args id=%d src=%s dst=%s" % [
			id, src, dst])
		return false
	var ok: bool = bool(_plugin.cameraLiveView(id, on,
		float(src[0]), float(src[1]), float(src[2]), float(src[3]),
		float(dst[0]), float(dst[1]), float(dst[2]), float(dst[3]), mode))
	print("[YoudooBridge] camera_live_view(id=%d on=%s A=[%.3f,%.3f,%.3f,%.3f] "
		+ "B=[%.3f,%.3f,%.3f,%.3f] mode=%d) -> %s" % [
		id, on, float(src[0]), float(src[1]), float(src[2]), float(src[3]),
		float(dst[0]), float(dst[1]), float(dst[2]), float(dst[3]), mode, ok])
	return ok


## Clears every camera-live id (the plugin calls clearAllCameraLiveOnScreen).
## This is the teardown path when the game leaves READY/COUNTDOWN/PLAY/PAUSE.
func camera_live_clear() -> void:
	if not _available:
		return
	_plugin.cameraLiveClear()
	print("[YoudooBridge] camera_live_clear()")


## Clears the camera preview (legacy single-view teardown; the plugin's
## cameraLive(false) also calls clearAllCameraLiveOnScreen).
func camera_live_stop() -> void:
	if not _available:
		return
	_plugin.cameraLive(false)
	print("[YoudooBridge] camera_live_stop()")


## True after the service accepted the last camera-live call.
func camera_live_active() -> bool:
	if not _available:
		return false
	return bool(_plugin.cameraLiveActive())


# --------------------------------------------------------------- camera frames
#
# The overlay path above is drawn by the device service *above* this app. This path
# instead brings the pixels into Godot: the plugin's cameraFramesStart() runs a worker
# that, at the configured rate (default 15 fps), reads the newest pose frame time,
# calls IGameServiceV1_0_3.getFrameBuffer(frameTimeMs), converts the YUV420
# HardwareBuffer to RGBA8 inside libcamframe.so at scale 0.3 and keeps ONE newest
# frame. A slow consumer misses frames; no queue ever grows.
#
# Everything here is inert off-device: supported() is false, start() returns false and
# poll() returns {}. Mirroring is applied by this bridge (flip flags on the Image), never
# by the SDK's signed-UV trick, so it stays deterministic across both camera paths.

## True only when this build can deliver RGBA frames: the V1_0_3 binder is bound AND
## libcamframe.so loaded. Off-device (or before binding) this is false.
func camera_frames_supported() -> bool:
	if not _available:
		return false
	return bool(_plugin.cameraFramesSupported())


## Starts the RGBA camera-frame pump. `rate` is fps (0 keeps the plugin default 15,
## clamped 1..30); `scale` is the downscale applied before conversion (0.0 keeps 0.3,
## clamped 0.05..1.0). Returns true only when the pump is actually running, which
## requires a bound V1_0_3 service; otherwise nothing starts.
func camera_frames_start(rate: int = 0, scale: float = 0.0) -> bool:
	_cam_seq = 0
	if not _available:
		print("[YoudooBridge] camera_frames_start(): no plugin (no-op)")
		return false
	if rate > 0:
		_plugin.cameraFramesRate(rate)
	if scale > 0.0:
		_plugin.cameraFramesScale(scale)
	var ok: bool = bool(_plugin.cameraFramesStart())
	print("[YoudooBridge] camera_frames_start() -> %s (supported=%s)" % [
		ok, camera_frames_supported()])
	return ok


## Stops the pump and drops the held frame. Safe to call when it never started, and
## called automatically from stop() before the service is unbound.
func camera_frames_stop() -> void:
	if not _available:
		return
	_plugin.cameraFramesStop()
	_cam_seq = 0
	print("[YoudooBridge] camera_frames_stop()")


## True while the pump worker is alive (independent of whether pixels are flowing).
func camera_frames_running() -> bool:
	if not _available:
		return false
	return bool(_plugin.cameraFramesRunning())


## Pump diagnostics, always the same keys:
## {"running":bool,"reader":bool,"fps":int,"scale":float,"frames":int,"drops":int,
##  "missing":int,"errors":int,"seq":int,"size":"WxH","src":"WxH","format":String}
## plus "readerError"/"probe"/"error" when relevant. All zero/false off-device.
func camera_frame_info() -> Dictionary:
	var empty := {
		"running": false,
		"reader": false,
		"fps": 0,
		"scale": 0.0,
		"frames": 0,
		"drops": 0,
		"missing": 0,
		"errors": 0,
		"seq": 0,
		"size": "0x0",
		"src": "0x0",
		"format": "",
	}
	if not _available:
		empty["error"] = _reason
		return empty
	var parsed: Variant = JSON.parse_string(_plugin.cameraFrameInfoJson())
	if typeof(parsed) != TYPE_DICTIONARY:
		empty["error"] = "unparsable camera frame info json"
		return empty
	return parsed


## Returns the newest frame exactly once, or {} when nothing new arrived:
## {"seq":int, "w":int, "h":int, "bytes":PackedByteArray} with bytes = w*h*4 RGBA8,
## top-left origin, alpha 0xFF, already scaled by the pump. Callers must not assume a
## fixed size: the device frame size and the configured scale decide it.
func camera_frame_poll() -> Dictionary:
	if not _available:
		return {}
	var seq := int(_plugin.cameraFrameSeq())
	if seq <= 0 or seq == _cam_seq:
		return {}
	var width := int(_plugin.cameraFrameWidth())
	var height := int(_plugin.cameraFrameHeight())
	var bytes := _camera_frame_bytes(width, height)
	# Either way this sequence number is done: a frame that could not be decoded must
	# not be retried forever, and a good one must not be delivered twice.
	_cam_seq = seq
	if bytes.is_empty():
		return {}
	return {"seq": seq, "w": width, "h": height, "bytes": bytes}


## Builds a NEW ImageTexture (the caller owns it) from a camera_frame_poll() result.
## `flip_x` mirrors the image horizontally, `flip_y` vertically; both default off and
## are applied here, on the texture, not in the SDK. Returns null on a malformed frame.
func camera_frame_to_texture(frame: Dictionary, flip_x: bool = false,
		flip_y: bool = false) -> ImageTexture:
	var width := int(frame.get("w", 0))
	var height := int(frame.get("h", 0))
	var bytes: PackedByteArray = frame.get("bytes", PackedByteArray())
	if width <= 0 or height <= 0 or bytes.size() != width * height * 4:
		return null
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
	if image == null or image.is_empty():
		return null
	if flip_x:
		image.flip_x()
	if flip_y:
		image.flip_y()
	return ImageTexture.create_from_image(image)


## Pulls RGBA bytes for the newest frame. byte[] -> PackedByteArray is the fast path;
## if this Godot build cannot marshal it, the base64 accessor is used instead and the
## decision is remembered (one warning, never per frame).
func _camera_frame_bytes(width: int, height: int) -> PackedByteArray:
	var needed := width * height * 4
	if needed <= 0:
		return PackedByteArray()
	if _cam_bytes_mode != 2:
		var bytes := _camera_decode_bytes(_plugin.cameraFrameBytes(), needed)
		if not bytes.is_empty():
			_cam_bytes_mode = 1
			return bytes
		if _cam_bytes_mode == 0:
			_cam_bytes_mode = 2
			print("[YoudooBridge] byte[] bridge unsupported; camera frames use base64")
	var encoded: Variant = _plugin.cameraFrameBytesBase64()
	if typeof(encoded) != TYPE_STRING or encoded.is_empty():
		return PackedByteArray()
	var decoded := Marshalls.base64_to_raw(encoded)
	if decoded.size() != needed:
		return PackedByteArray()
	return decoded


## Normalizes whatever the bridge returned into exactly `needed` RGBA bytes.
func _camera_decode_bytes(raw: Variant, needed: int) -> PackedByteArray:
	if typeof(raw) != TYPE_PACKED_BYTE_ARRAY:
		return PackedByteArray()
	var bytes: PackedByteArray = raw
	if bytes.size() > needed:
		bytes = bytes.slice(0, needed)
	if bytes.size() != needed:
		return PackedByteArray()
	return bytes


## Newest frame as a Dictionary ({} before the first frame or when unavailable).
## {"frameTimeMs":int,"imageWidth":int,"imageHeight":int,
##  "persons":{"<id>":{"score":float,"rect":[l,t,r,b],"kpts":[[x,y,z,score],...]}},
##  "lHand":{...},"rHand":{...},"face":{...}}
func latest_frame() -> Dictionary:
	return _latest


## Number of frames the plugin has received since the process started.
func frame_count() -> int:
	if not _available:
		return 0
	return int(_plugin.frameCount())


## True while frames keep arriving.
func is_tracking() -> bool:
	return _tracking


func _process(delta: float) -> void:
	if not _started:
		set_process(false)
		return
	_poll_accum += delta
	if _poll_accum < POLL_INTERVAL:
		return
	_poll_accum = 0.0
	_poll()

	# Drop tracking when the SDK stops pushing frames.
	if _tracking and Time.get_ticks_msec() - _last_frame_ticks > STALE_AFTER_MS:
		_set_tracking(false)


func _poll() -> void:
	var count := int(_plugin.frameCount())
	if count == _frame_count:
		return
	_frame_count = count
	var parsed: Variant = JSON.parse_string(_plugin.latestFrameJson())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_latest = parsed
	_last_frame_ticks = Time.get_ticks_msec()
	_set_tracking(true)
	frame_received.emit(_latest)


func _set_tracking(value: bool) -> void:
	if _tracking == value:
		return
	_tracking = value
	tracking_changed.emit(value)
