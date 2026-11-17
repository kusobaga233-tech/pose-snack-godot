extends SceneTree
## Headless test entry point for the pure-GDScript rule core (workstream B).
##
##   "D:\godot-proj\Godot_v4.6.3-stable_win64.exe" --headless \
##       --path D:\CODEX-PROJ\yoodou\pose-snake-godot --script res://tests/run_all.gd
##
## Prints one PASS/FAIL line per assertion plus a summary, and exits non-zero when
## anything failed.
##
## Windows note: the Godot binary is a GUI-subsystem executable, so a plain
## `& <godot.exe> ...` call returns immediately in PowerShell and `$LASTEXITCODE`
## stays empty. Wrap it to observe the exit code:
##
##   $p = Start-Process -FilePath <godot.exe> -Wait -PassThru -NoNewWindow `
##        -ArgumentList '--headless','--path',<project>,'--script','res://tests/run_all.gd'
##   exit $p.ExitCode
##
## Suites are loaded at runtime (`load`) instead of `preload`, so a compile error
## in one suite is reported as a normal failure instead of aborting the runner
## before it can call `quit()`.
##
## No scene, no autoload, no rendering: the whole run is ~20 s headless.

const SUITE_PATHS := [
	"res://tests/suite_config.gd",
	"res://tests/suite_input.gd",
	"res://tests/suite_snake.gd",
	"res://tests/suite_collisions.gd",
	"res://tests/suite_food.gd",
	"res://tests/suite_round.gd",
	"res://tests/suite_ai.gd",
	"res://tests/suite_determinism.gd",
]


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	print("=".repeat(64))
	print("pose-snake core tests (pure GDScript rules, headless)")
	print("Godot %s" % Engine.get_version_info().string)
	print("=".repeat(64))

	var test_script = load("res://tests/pstest.gd")
	if test_script == null:
		printerr("FATAL: could not load res://tests/pstest.gd")
		quit(1)
		return
	var t = test_script.new()

	for path in SUITE_PATHS:
		var script = load(path)
		if script == null:
			t.suite(path.get_file())
			t.fail("load suite", "compile error, see stderr above")
			continue
		if script.has_method("run"):
			script.run(t)
		if script.has_method("run_formulas"):
			script.run_formulas(t)

	var code: int = t.summary()
	print("total time: %d ms" % (Time.get_ticks_msec() - started))
	quit(code)
