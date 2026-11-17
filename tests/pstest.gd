extends RefCounted
## Tiny assertion harness for the headless rule tests.
##
## No framework dependency, no scenes: suites are `RefCounted` scripts with a
## `static func run(t: PSTest)` entry point, and `tests/run_all.gd` (a SceneTree
## script) calls them in order, prints a PASS/FAIL line per assertion and exits
## non-zero when anything failed.
##
##     node-free usage inside a suite:
##         t.eq_float("turn cap", s.turn_amount, 0.19125)

var passed: int = 0
var failed: int = 0
## "suite / assertion :: detail" for every failure.
var failures: Array = []

var _suite: String = "?"
var _suite_start_ms: int = 0


# ------------------------------------------------------------------ suites

func suite(name: String) -> void:
	_suite = name
	_suite_start_ms = Time.get_ticks_msec()
	print("[suite] %s" % name)


func end_suite() -> void:
	var ms := Time.get_ticks_msec() - _suite_start_ms
	print("[suite] %s done in %d ms" % [_suite, ms])


# ------------------------------------------------------------------ asserts

func _record(name: String, okv: bool, detail: String) -> bool:
	if okv:
		passed += 1
		print("  PASS  %s" % name)
	else:
		failed += 1
		var line := "%s / %s" % [_suite, name]
		if detail != "":
			line += " :: " + detail
		failures.append(line)
		print("  FAIL  %s   <- %s" % [name, detail])
	return okv


func ok(name: String, cond: bool, detail: String = "") -> bool:
	return _record(name, cond, detail if not cond else "")


func fail(name: String, detail: String) -> bool:
	return _record(name, false, detail)


func eq_int(name: String, got: int, want: int) -> bool:
	return _record(name, got == want, "got %d want %d" % [got, want])


func eq_bool(name: String, got: bool, want: bool) -> bool:
	return _record(name, got == want, "got %s want %s" % [got, want])


func eq_str(name: String, got: String, want: String) -> bool:
	return _record(name, got == want, "got '%s' want '%s'" % [got, want])


func eq_name(name: String, got: StringName, want: StringName) -> bool:
	return _record(name, got == want, "got '%s' want '%s'" % [got, want])


## Relative-tolerant float comparison (absolute for tiny expectations).
func eq_float(name: String, got: float, want: float, eps: float = 1e-9) -> bool:
	if not is_finite(got):
		return _record(name, false, "got %s want %s" % [str(got), str(want)])
	var tol := eps * maxf(1.0, absf(want))
	return _record(name, absf(got - want) <= tol, "got %.12f want %.12f" % [got, want])


func lt(name: String, got: float, limit: float) -> bool:
	return _record(name, got < limit, "got %.6f, expected < %.6f" % [got, limit])


func le(name: String, got: float, limit: float) -> bool:
	return _record(name, got <= limit, "got %.6f, expected <= %.6f" % [got, limit])


func gt(name: String, got: float, limit: float) -> bool:
	return _record(name, got > limit, "got %.6f, expected > %.6f" % [got, limit])


func ge(name: String, got: float, limit: float) -> bool:
	return _record(name, got >= limit, "got %.6f, expected >= %.6f" % [got, limit])


func between(name: String, got: float, lo: float, hi: float) -> bool:
	return _record(name, got >= lo and got <= hi, "got %.6f, expected [%.6f, %.6f]" % [got, lo, hi])


func finite(name: String, value: float) -> bool:
	return _record(name, is_finite(value), "got %s (not finite)" % str(value))


# ------------------------------------------------------------------ summary

## Prints the final summary and returns the process exit code.
func summary() -> int:
	print("")
	print("=".repeat(64))
	if failed == 0:
		print("RESULT: PASS - %d assertions, 0 failures" % passed)
	else:
		print("RESULT: FAIL - %d passed, %d failed" % [passed, failed])
		for f in failures:
			print("  FAILED  %s" % f)
	print("=".repeat(64))
	return 0 if failed == 0 else 1
