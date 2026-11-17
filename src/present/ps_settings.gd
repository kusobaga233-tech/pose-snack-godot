extends RefCounted
## Player settings that must survive an app restart — `user://pose_snake.cfg`.
##
## The project had no settings file before the character picker
## (`ps_skins.gd:SETTINGS_PATH`), which writes `[skin] player`. That file is
## shared, so every writer here follows the same rule `ps_skins` already uses:
## **load the file first, then set only our key, then save**. No module owns the
## whole file and no module can clobber another's section.
##
## Sections / keys:
##
##     [skin]  player       character slug            (ps_skins.gd)
##     [audio] muted        true = SFX off            (this file)
##     [round] best_length  historical best length    (this file)
##     [round] mode         "timed" / "endless"       (this file)
##
## Why these are persisted: they are the three player-visible choices the shell
## makes outside a round (音效 / 赛制) plus the one number a shipped arcade game
## is expected to remember (最佳成绩). The player COUNT is deliberately NOT saved:
## the mode-select screen must have no default selection (product decision, see
## `_act_select`), so the owner still picks 单人/双人 every launch.
##
## Verification harnesses (`--capture*`, `--remote-*`) neither load nor save:
## the release gate compares two bitmap runs, and a best score written by the
## first run would change the second run's score row. `set_harness(true)` makes
## every setter a no-op and keeps the defaults.

const SETTINGS_PATH := "user://pose_snake.cfg"

const MODE_TIMED := "timed"
const MODE_ENDLESS := "endless"

## SFX muted (the HUD control shows the inverse: 音效 开 / 关).
static var muted := false
## Historical best length. `0` = nothing recorded yet.
static var best_length := 0
## `round.mode`: timed 2:00 ranked round, or endless practice.
static var round_mode := MODE_TIMED
static var loaded := false
## Capture/verification run: no disk traffic at all.
static var harness := false


static func load_all() -> void:
	if loaded:
		return
	loaded = true
	if harness:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	muted = bool(cfg.get_value("audio", "muted", muted))
	best_length = maxi(0, int(cfg.get_value("round", "best_length", best_length)))
	var mode := String(cfg.get_value("round", "mode", round_mode))
	if mode == MODE_ENDLESS or mode == MODE_TIMED:
		round_mode = mode


## One-line boot/diagnostic summary (no disk access).
static func describe() -> String:
	return "muted=%s best=%d mode=%s file=%s%s" % [
		str(muted), best_length, round_mode, SETTINGS_PATH,
		" (harness: read-only)" if harness else ""]


static func set_muted(on: bool) -> void:
	muted = on
	_flush("audio", "muted", muted)


static func set_round_mode(mode: String) -> void:
	if mode != MODE_ENDLESS and mode != MODE_TIMED:
		return
	round_mode = mode
	_flush("round", "mode", round_mode)


## Raise the stored best. Returns true when this call set a NEW record (the
## caller logs it; nothing else in the shell needs to know).
static func record_best(length: int) -> bool:
	if length <= best_length:
		return false
	best_length = length
	_flush("round", "best_length", best_length)
	return true


## Write one key, preserving every other section of the shared file.
static func _flush(section: String, key: String, value: Variant) -> void:
	if harness:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)
