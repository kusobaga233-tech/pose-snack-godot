extends SceneTree
## Manual probe (NOT part of `run_all.gd`, so the 444-assertion suite count is
## unchanged): proves the remote-key hook's re-entrancy contract.
##
##   tools\run_godot_safe.ps1 -Script res://tests/probe_remote_guard.gd -TimeoutSeconds 60
##
## Two independent checks:
##   1. SOURCE CONTRACT — reads the real Java (canonical override and the copy
##      `tools\setup_android_build.ps1` generates) and asserts the guard, the
##      synthetic-event signature, the try/finally and the one-down-one-up rule are
##      all present and in the right order. This is what the APK compiles.
##   2. DISPATCH MODEL — the Java hook can only be executed on the device (it needs
##      the Android framework: `DecorView.dispatchKeyEvent` -> `Window.Callback`),
##      so this part models that dispatch shape and asserts the *rule*: with the
##      guard, two nested dispatches terminate and each press injects exactly one
##      ACTION_DOWN and one ACTION_UP; without it, the same dispatch recurses.
##      This is a model of the Java code, not the Java code itself — the device
##      log (`injected key=... action=down/up`) is the end-to-end proof.

const PSTest = preload("res://tests/pstest.gd")

const CANONICAL := "android/build-overrides/src/main/java/com/godot/game/GodotApp.java"
const GENERATED := "android/build/src/main/java/com/godot/game/GodotApp.java"


## Minimal faithful model of GodotApp.dispatchKeyEvent + injectKeyboardKey.
## `_decor()` is `decor.dispatchKeyEvent()`, which calls `Window.Callback` and so
## re-enters `dispatch()` — exactly the shape that overflowed the stack.
class DispatchModel:
	const ACTION_DOWN := 0
	const ACTION_UP := 1
	const MAX_NESTING := 64
	const MAX_CALLS := 5000
	const CONFIRM := [23, 66, 96, 160, 85, 62]

	var guarded := true
	## Pre-fix GodotApp had no signature check either; the buggy model clears both.
	var recognise_synthetic := true
	## Simulate the framework invoking Window.Callback a second time for the same
	## synthetic dispatch (the pre-fix log showed two `key=` lines per level).
	var double_callback := false

	var injecting := false
	var injected: Array = []      # [code, action] per real injection
	var delivered: Array = []     # what the window path finally received
	var callbacks := 0
	var calls := 0
	var nesting := 0
	var max_nesting := 0
	var overflow := false

	func press(code: int, action: int, repeat: int = 0, source: int = 1793) -> bool:
		return dispatch({"code": code, "action": action, "repeat": repeat,
			"device": 9, "source": source, "scan": 0})

	func dispatch(ev: Dictionary) -> bool:
		calls += 1
		nesting += 1
		max_nesting = maxi(max_nesting, nesting)
		if nesting > MAX_NESTING or calls > MAX_CALLS:
			overflow = true
			nesting -= 1
			return false
		var handled := false
		if guarded and injecting:
			# Java: if (Boolean.TRUE.equals(INJECTING.get())) -> super
			handled = _forward(ev)
		elif recognise_synthetic and int(ev["device"]) == -1 \
				and int(ev["scan"]) == 0 and int(ev["source"]) == 0:
			# Java: isInjectedSynthetic(event) -> super
			handled = _forward(ev)
		else:
			var canonical := _canonical(int(ev["code"]))
			if canonical < 0:
				handled = _forward(ev)
			elif int(ev["action"]) == ACTION_DOWN and int(ev["repeat"]) > 0:
				handled = true   # Java: "[inject] repeat suppressed"
			else:
				handled = _inject(canonical, int(ev["action"]))
		nesting -= 1
		return handled

	func _inject(code: int, action: int) -> bool:
		injected.append([code, action])
		var synthetic := {"code": code, "action": action, "repeat": 0,
			"device": -1, "source": 0, "scan": 0}
		var saved := injecting
		injecting = true
		var handled := _decor(synthetic)   # Java: try { decor.dispatchKeyEvent(...) }
		injecting = saved                  # Java: finally { restore }
		return handled

	func _decor(ev: Dictionary) -> bool:
		callbacks += 1
		var handled := dispatch(ev)
		if double_callback:
			handled = dispatch(ev) or handled
		return handled

	func _forward(ev: Dictionary) -> bool:
		delivered.append([int(ev["code"]), int(ev["action"])])
		return true

	static func _canonical(code: int) -> int:
		if CONFIRM.has(code):
			return 66
		if code == 19 or code == 20 or code == 21 or code == 22 or code == 4 or code == 111:
			return code
		return -1


func _initialize() -> void:
	var t = PSTest.new()
	t.suite("remote-guard-source")
	_probe_source(t)
	_probe_model(t)
	quit(t.summary())


# --------------------------------------------------------- 1. source contract

func _read_project_file(relative: String) -> String:
	var absolute: String = ProjectSettings.globalize_path("res://") + relative
	if not FileAccess.file_exists(absolute):
		return ""
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _probe_source(t) -> void:
	var canonical := _read_project_file(CANONICAL)
	var generated := _read_project_file(GENERATED)
	t.ok("canonical override readable", canonical.length() > 1000,
		"%d bytes" % canonical.length())
	t.ok("generated copy readable", generated.length() > 1000,
		"%d bytes" % generated.length())
	t.ok("canonical and generated copies are identical (setup_android_build sync)",
		canonical == generated, "run tools\\setup_android_build.ps1")

	for pair in [["canonical", canonical], ["generated", generated]]:
		var label: String = pair[0]
		var src: String = pair[1]
		var guard := src.find("if (Boolean.TRUE.equals(INJECTING.get()))")
		var remote_log := src.find('Log.i(TAG, "key=" + keyCode')
		var canonicalise := src.find("final int canonical = canonicalKeyCode(keyCode)")
		var inject_call := src.find("if (injectKeyboardKey(canonical, action, 0))")
		var signature := src.find("private static boolean isInjectedSynthetic(KeyEvent event)")
		var set_flag := src.find("INJECTING.set(Boolean.TRUE);")
		var try_open := src.find("try {", maxi(set_flag, 0))
		var decor_call := src.find("handled = decor.dispatchKeyEvent(synthetic);")
		var finally_open := src.find("finally {", maxi(decor_call, 0))
		var remove_flag := src.find("INJECTING.remove();")

		t.ok("%s: thread-local INJECTING guard declared" % label,
			src.find("private static final ThreadLocal<Boolean> INJECTING") >= 0)
		t.ok("%s: guard is the first thing dispatchKeyEvent does" % label,
			guard >= 0 and remote_log > guard and canonicalise > guard and inject_call > guard,
			"guard=%d log=%d canonical=%d inject=%d" % [guard, remote_log, canonicalise, inject_call])
		t.ok("%s: synthetic signature checks deviceId/scanCode/source" % label,
			signature >= 0
			and src.find("event.getDeviceId() == -1", signature) > signature
			and src.find("event.getScanCode() == 0", signature) > signature
			and src.find("event.getSource() == 0", signature) > signature)
		t.ok("%s: synthetic event is forwarded, not re-injected" % label,
			src.find("if (isInjectedSynthetic(event)) {", maxi(guard, 0)) > guard
			and src.find("return super.dispatchKeyEvent(event);",
				src.find("if (isInjectedSynthetic(event)) {", maxi(guard, 0))) > guard)
		t.ok("%s: flag raised, try, decor dispatch, finally, restore (in order)" % label,
			set_flag >= 0 and try_open > set_flag and decor_call > try_open
			and finally_open > decor_call and remove_flag > finally_open,
			"set=%d try=%d decor=%d finally=%d remove=%d" % [
				set_flag, try_open, decor_call, finally_open, remove_flag])
		t.ok("%s: synthetic built with deviceId=-1, scanCode=0 (source 0)" % label,
			src.find("new KeyEvent(now, now, action, keyCode, repeat, 0, -1, 0)") >= 0)
		t.ok("%s: repeat downs suppressed (one action per press)" % label,
			src.find("[inject] repeat suppressed") >= 0
			and src.find("event.getRepeatCount() > 0") >= 0)
		t.ok("%s: key table kept (19-22 dpad, 4/111 back)" % label,
			src.find("case KeyEvent.KEYCODE_DPAD_UP:") >= 0
			and src.find("case KeyEvent.KEYCODE_DPAD_DOWN:") >= 0
			and src.find("case KeyEvent.KEYCODE_DPAD_LEFT:") >= 0
			and src.find("case KeyEvent.KEYCODE_DPAD_RIGHT:") >= 0
			and src.find("case KeyEvent.KEYCODE_BACK:") >= 0
			and src.find("case KeyEvent.KEYCODE_ESCAPE:") >= 0)
		t.ok("%s: confirm keys kept (23/66/96/160/85/62 -> 66)" % label,
			src.find("KeyEvent.KEYCODE_DPAD_CENTER") >= 0
			and src.find("KeyEvent.KEYCODE_BUTTON_A") >= 0
			and src.find("KeyEvent.KEYCODE_ENTER") >= 0
			and src.find("KeyEvent.KEYCODE_NUMPAD_ENTER") >= 0
			and src.find("KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE") >= 0
			and src.find("KeyEvent.KEYCODE_SPACE") >= 0
			and src.find("return KeyEvent.KEYCODE_ENTER;") >= 0)
		t.ok("%s: diagnostic log line kept" % label,
			src.find('"key=" + keyCode + " action="') >= 0)
		t.ok("%s: mapped/injected log lines kept" % label,
			src.find('"mapped key=" + keyCode + " -> key=" + canonical') >= 0
			and src.find('"injected key=" + keyCode + " action="') >= 0)
		t.ok("%s: hook tag kept (device verifier greps GodotRemoteInput)" % label,
			src.find('String TAG = "GodotRemoteInput"') >= 0)


# --------------------------------------------------------- 2. dispatch model

func _probe_model(t) -> void:
	t.suite("remote-guard-model")

	# --- the pre-fix shape: no guard, one press recurses ---------------------
	var buggy = DispatchModel.new()
	buggy.guarded = false
	buggy.recognise_synthetic = false
	buggy.press(21, DispatchModel.ACTION_DOWN)
	t.ok("unguarded model recurses (this is the stack overflow)", buggy.overflow,
		"max_nesting=%d calls=%d" % [buggy.max_nesting, buggy.calls])
	t.ok("unguarded model never delivers a key", buggy.delivered.is_empty(),
		"delivered=%d" % buggy.delivered.size())

	# --- guarded: one press = exactly one injected down + one injected up ----
	var model = DispatchModel.new()
	model.press(21, DispatchModel.ACTION_DOWN)
	model.press(21, DispatchModel.ACTION_UP)
	t.ok("guarded model does not recurse", not model.overflow,
		"max_nesting=%d" % model.max_nesting)
	t.ok("guarded model nests at most one re-entry", model.max_nesting <= 3,
		"max_nesting=%d" % model.max_nesting)
	t.eq_int("guarded: exactly 2 injections for one press", model.injected.size(), 2)
	t.ok("guarded: first injection is ACTION_DOWN",
		model.injected.size() > 0 and model.injected[0] == [21, DispatchModel.ACTION_DOWN])
	t.ok("guarded: second injection is ACTION_UP (the UP path is reached)",
		model.injected.size() > 1 and model.injected[1] == [21, DispatchModel.ACTION_UP])
	t.eq_int("guarded: the window path received both events", model.delivered.size(), 2)
	t.eq_int("guarded: one callback per injection", model.callbacks, 2)

	# --- two nested dispatches inside one injection --------------------------
	# The framework calls Window.Callback again for the same synthetic event: the
	# second entry must still be forwarded, not injected.
	var nested = DispatchModel.new()
	nested.double_callback = true
	nested.press(21, DispatchModel.ACTION_DOWN)
	t.ok("two nested dispatches do not recurse", not nested.overflow,
		"max_nesting=%d calls=%d" % [nested.max_nesting, nested.calls])
	t.eq_int("two nested dispatches: still exactly one injection", nested.injected.size(), 1)
	t.eq_int("two nested dispatches: both forwarded to the window path",
		nested.delivered.size(), 2)
	t.ok("two nested dispatches: nesting stays shallow", nested.max_nesting <= 3,
		"max_nesting=%d" % nested.max_nesting)

	# --- second line of defence: signature alone stops an injection ----------
	var signature_only = DispatchModel.new()
	signature_only.dispatch({"code": 21, "action": DispatchModel.ACTION_DOWN,
		"repeat": 0, "device": -1, "source": 0, "scan": 0})
	t.ok("synthetic signature alone injects nothing", signature_only.injected.is_empty(),
		"injected=%d" % signature_only.injected.size())
	t.eq_int("synthetic signature is forwarded once", signature_only.delivered.size(), 1)

	# --- canonicalisation must not depend on source --------------------------
	var remote = DispatchModel.new()
	remote.press(96, DispatchModel.ACTION_DOWN)
	t.ok("BUTTON_A (96) on a gamepad-source event maps to ENTER 66",
		remote.injected.size() == 1 and remote.injected[0] == [66, DispatchModel.ACTION_DOWN],
		"injected=%s" % str(remote.injected))
	var held = DispatchModel.new()
	held.press(22, DispatchModel.ACTION_DOWN, 1)
	t.eq_int("held-key repeat is not injected", held.injected.size(), 0)
