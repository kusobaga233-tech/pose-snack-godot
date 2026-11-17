extends SceneTree
## Runs ONE test suite headless, so a hang or OOM can be isolated without
## burning the whole machine on a full run.
##
##   godot --headless --path <project> --script res://tests/run_one.gd \
##         -- res://tests/suite_food.gd
##
## Keep this runner and `run_all.gd` in sync only through the shared `pstest.gd`
## helper; suites stay untouched.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: --script res://tests/run_one.gd -- res://tests/<suite>.gd")
		quit(2)
		return

	var suite_path: String = args[0]
	print("=".repeat(64))
	print("single suite: %s" % suite_path)
	print("=".repeat(64))

	var test_script = load("res://tests/pstest.gd")
	if test_script == null:
		printerr("FATAL: could not load res://tests/pstest.gd")
		quit(1)
		return

	var t = test_script.new()
	var script = load(suite_path)
	if script == null:
		t.fail("load suite", suite_path)
		quit(t.summary())
		return
	if script.has_method("run"):
		script.run(t)
	if script.has_method("run_formulas"):
		script.run_formulas(t)

	quit(t.summary())
