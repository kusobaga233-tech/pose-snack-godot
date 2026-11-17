extends Node2D
## Internal debug tuning panel — **build-time optional**, remote driven.
##
## Why this file exists
## --------------------
## The Web prototype has a 设置 / 调试 panel (`index.html:272-370`, wired in
## `js/main.js:404-700`) that writes the mutable `TUNING` object plus
## `CONFIG.pose.speed.*` / `CONFIG.pose.centerT` / `CONFIG.round.mode` at runtime.
## The Godot port has the same mutable objects — `src/core/config.gd` (the
## `TUNING`-equivalent defaults live in `PSTuning` + the config sections) — but no
## way to reach them on the box. This is that panel, as an **internal debug tool**.
##
## Build switch
## ------------
## The ONE build-time flag lives in `src/present/ps_build.gd`
## (`PSBuild.TUNING_ENABLED`), next to nothing else:
##
##   * `false` (shipped default) — `main.gd` never even `load()`s this script, so
##     its code is not compiled at boot, no node exists, nothing is drawn, no key
##     reaches it and no frame pays for it.
##   * `true` (internal debug build) — F8 (adb `input keyevent 138`) or any key in
##     `PSRemote.PANEL_KEYS` opens / closes it. Flipping that one const is the whole
##     build change; the panel script is only loaded when it is true.
## A ProjectSetting was deliberately NOT used (project.godot is owned by the
## coordinator): a const cannot be toggled at runtime, so it cannot ship by
## accident on the box.
##
## Live application
## ----------------
## Every row stores the *object* + *property name* the rules already read each
## frame, so "apply" is a plain `obj.set(prop, value)` — no restart, no copy, no
## cache to invalidate:
##
##   圆心高度      cfg.pose.center_t       <- read per frame in ps_pose_input.gd:353
##   转向角速度    tuning.turn_rate        <- read per frame in snake.gd:295
##   速度下限/上限 cfg.pose.speed.min/max  <- read per frame in pose_steer.gd:93
##   起速/满速距离 cfg.pose.speed.near/far <- pose_steer.gd:91-92
##   速度平滑      cfg.pose.speed.smooth   <- pose_steer.gd:101
##   体型减速强度  tuning.slow_strength    <- snake.gd:262 (update_speed)
##   减速尺度      tuning.slow_scale       <- snake.gd:262
##   大蛇加粗      tuning.girth_max        <- snake.gd:151 (radius cache keys on it)
##   复活静止保护  tuning.respawn_freeze   <- tuning.gd:62 (freeze_sec)
##   比赛模式      cfg.round.mode          <- game.gd:445 (timed countdown)
##   AI 难度/失误/压迫 tuning.ai_level / ai_mistake / ai_pressure <- brain.gd
##   NPC 蛇头造型  tuning.head_style_on    <- game.gd:401 (+ live reshuffle below)
##   画面抖动强度  fx.shake_scale          <- ps_fx.gd:add_shake() (presentation
##                 row, not in the web panel; default = PSFx.SHAKE_SCALE)
##
## Values are always *read back* from those objects, so the number on screen is
## the live truth (the same rule the Web panel follows with `syncTuningUI`).
##
## Remote interaction (through `PSRemote` -> `main.gd::_dispatch_action`)
## ----------------------------------------------------------------
##   DPAD UP/DOWN   move between rows
##   DPAD L/R       change the value (one step; `step` sizes ~20 presses per range)
##   OK             toggle a switch / cycle an enum / restore the boot default
##   BACK           close the panel
## The panel consumes every action while it is open, so the menu underneath cannot
## be driven at the same time (there is exactly ONE input router).

const PSTheme = preload("res://src/present/ps_theme.gd")
const PSRemote = preload("res://src/present/ps_remote.gd")

# The build switch is NOT here: it is `PSBuild.TUNING_ENABLED` in
# `src/present/ps_build.gd`, so that `main.gd` can branch on it without loading
# this script at all (that is what "off" buys: no compile, no node, no draw).


# ------------------------------------------------------------------ layout
## 36 px rows: the panel carries 17 web rows + the presentation row below and
## still has to end above y=1080 (it starts at PANEL_Y=226). At the old 38 px it
## would end at 1092 and the last row would be off screen.
const ROW_H := 36.0
const GROUP_H := 22.0
const HEAD_H := 58.0
const FOOT_H := 36.0
const PAD := 14.0
## Left of the camera PiP (x >= 1459), right of the minimap (x <= 264) and of the
## 2P bottom-left preview (x <= 326), below the READY hint chip (y <= 230) and
## above the bottom hint line. Nothing in the play HUD sits inside this rect.
const PANEL_X := 352.0
const PANEL_Y := 226.0
const PANEL_W := 744.0

# ------------------------------------------------------------------- state
var cfg = null
var tuning = null
var game = null
## Presentation object for the non-web rows (`PSFx.shake_scale`); may be null and
## is then simply not listed.
var _fx = null
var time := 0.0
var open := false
## Row dictionaries, in draw order; `"group"` rows are captions, not selectable.
var rows: Array = []
## Index into `rows` of the highlighted row (kept on a selectable row only).
var sel := 0
## Boot-time snapshot per row, so OK can restore a value ("确认" = back to default).
var _boot: Array = []
var _nav: Array = []
var _height := 0.0

var _panel_style: StyleBoxFlat = null
var _row_hl: StyleBoxFlat = null
var _group_style: StyleBoxFlat = null


func setup(p_cfg, p_tuning, p_game, p_fx = null) -> void:
	cfg = p_cfg
	tuning = p_tuning
	game = p_game
	_fx = p_fx
	_build_rows()
	_boot.clear()
	for row in rows:
		_boot.append(row.get("obj").get(row.get("prop")) if row.has("obj") else null)
	sel = int(_nav[0]) if _nav.size() > 0 else 0


func _ready() -> void:
	_panel_style = PSTheme.panel(Color(0.03, 0.048, 0.082, 0.95),
		Color(0.42, 0.78, 1.0, 0.55), 16, 2, 20, "tuning_panel")
	_row_hl = PSTheme.panel(Color(0.09, 0.16, 0.24, 0.92),
		Color(0.42, 0.92, 1.0, 0.95), 10, 2, 0, "tuning_row_hl")
	_group_style = PSTheme.panel(Color(0.06, 0.09, 0.15, 0.55),
		Color(0.35, 0.52, 0.72, 0.22), 6, 0, 0, "tuning_group")


func _l(cn: String, en: String) -> String:
	return cn if PSTheme.cjk_ok() else en


# ------------------------------------------------------------------- rows

## The Web panel's 16 controls (`index.html:279-368`), in the same order, with the
## same parameter identity. Bounds come from the config constants, i.e. exactly the
## numbers `js/main.js` clamps against.
func _build_rows() -> void:
	rows.clear()
	_nav.clear()
	var P = cfg.pose
	var SP = P.speed
	var G = cfg.snake.girth
	var SL = cfg.slowdown
	var D = cfg.ai.difficulty
	var PR = cfg.ai.pressure

	_add_group("体感 · 转向 / POSE + TURN")
	_add("圆心高度", "centre h", P, "center_t", P.center_t_min, P.center_t_max, 0.05,
		"%.2f", 1.0, "")
	_add("转向角速度", "turn rate", tuning, "turn_rate", cfg.turn.rate_min,
		cfg.turn.rate_max, 0.5, "%.1f", 1.0, "")
	_add_group("距离 → 速度 / DIST -> SPEED")
	_add("速度下限", "speed min", SP, "min", SP.min_limit, SP.min_ceil, 0.03,
		"%.2f", 1.0, "x")
	_add("速度上限", "speed max", SP, "max", SP.max_floor, SP.max_limit, 0.04,
		"%.2f", 1.0, "x")
	_add("起速距离", "near dist", SP, "near", SP.near_min, SP.near_max, 0.025,
		"%.2f", 1.0, "")
	_add("满速距离", "far dist", SP, "far", SP.far_min, SP.far_max, 0.05,
		"%.2f", 1.0, "")
	_add("速度平滑", "speed smooth", SP, "smooth", 0.0, SP.smooth_max, 0.03,
		"%.2fs", 1.0, "")
	_add_group("体型 · 复活 / BODY + RESPAWN")
	_add("体型减速强度", "slow strength", tuning, "slow_strength", SL.strength_min,
		SL.strength_max, 0.02, "%.0f%%", 100.0, "")
	_add("减速尺度", "slow scale", tuning, "slow_scale", SL.scale_min, SL.scale_max,
		5.0, "%.0f", 1.0, _l(" 节", " seg"))
	_add("大蛇加粗", "girth max", tuning, "girth_max", G.min, G.max, 0.05,
		"%.2f", 1.0, "x")
	_add("复活静止保护", "respawn freeze", tuning, "respawn_freeze",
		cfg.player.respawn_freeze_min, cfg.player.respawn_freeze_max, 0.05,
		"%.2fs", 1.0, "")
	_add_group("单局规则 / ROUND")
	_add_enum("比赛模式", "round mode", cfg.round, "mode",
		[&"timed", &"endless"],
		[_l("2 分钟限时排位", "timed 2 min"), _l("无尽练习（不结算）", "endless")], "")
	_add_group("AI 对手 / AI")
	_add("AI 难度系数", "ai level", tuning, "ai_level", D.level_min, D.level_max, 0.05,
		"%.0f%%", 100.0, "")
	_add("AI 失误频率", "ai mistake", tuning, "ai_mistake", D.mistake_min,
		D.mistake_max, 0.05, "%.0f%%", 100.0, "")
	_add("AI 压迫强度", "ai pressure", tuning, "ai_pressure", PR.min, PR.max, 0.05,
		"%.0f%%", 100.0, "")
	_add_bool("NPC 蛇头造型", "npc head styles", tuning, "head_style_on", "head_styles")
	# ---- presentation rows (not in the web panel) ----
	# 画面抖动强度: `PSFx.shake_scale`, the ONE master knob for screen shake
	# (`SHAKE_SCALE` in ps_fx.gd is its boot default, 0.70). Live row: the fx
	# object reads it on the next `add_shake()`, so a change is visible without a
	# restart. Appended without its own group header so the panel still fits on
	# screen; see ROW_H above.
	if _fx != null:
		_add("画面抖动强度", "shake scale", _fx, "shake_scale", 0.0, 1.5, 0.05,
			"%.2f", 1.0, "x")
	_height = PAD * 2.0 + HEAD_H + FOOT_H
	for row in rows:
		_height += float(row.get("h", ROW_H))


func _add_group(label: String) -> void:
	rows.append({"group": label, "h": GROUP_H})


func _add(label: String, en: String, obj, prop: String, mn: float, mx: float,
		step: float, fmt: String, mul: float, suffix: String) -> void:
	_nav.append(rows.size())
	rows.append({
		"label": label, "en": en, "obj": obj, "prop": prop,
		"min": mn, "max": mx, "step": maxf(0.0001, step),
		"fmt": fmt, "mul": mul, "suffix": suffix, "h": ROW_H,
	})


func _add_enum(label: String, en: String, obj, prop: String, values: Array,
		labels: Array, after: String) -> void:
	_nav.append(rows.size())
	rows.append({
		"label": label, "en": en, "obj": obj, "prop": prop,
		"enum": values, "labels": labels, "after": after, "h": ROW_H,
	})


func _add_bool(label: String, en: String, obj, prop: String, after: String) -> void:
	_nav.append(rows.size())
	rows.append({
		"label": label, "en": en, "obj": obj, "prop": prop,
		"bool": true, "after": after, "h": ROW_H,
	})


# ------------------------------------------------------------------ input

func toggle() -> void:
	open = not open
	queue_redraw()
	print("[tuning] panel %s" % ("open" if open else "closed"))


func _nav_pos() -> int:
	for i in _nav.size():
		if int(_nav[i]) == sel:
			return i
	return 0


## One semantic action from `PSRemote`. Returns true when consumed.
func handle(action: int) -> bool:
	if rows.is_empty() or _nav.is_empty():
		return false
	match action:
		PSRemote.ACT_UP:
			var i := _nav_pos()
			sel = int(_nav[(i + _nav.size() - 1) % _nav.size()])
		PSRemote.ACT_DOWN:
			var j := _nav_pos()
			sel = int(_nav[(j + 1) % _nav.size()])
		PSRemote.ACT_LEFT:
			_adjust(-1)
		PSRemote.ACT_RIGHT:
			_adjust(1)
		PSRemote.ACT_OK:
			_confirm()
		PSRemote.ACT_BACK:
			open = false
		_:
			return false
	queue_redraw()
	return true


func _adjust(dir: int) -> void:
	var row: Dictionary = rows[sel]
	var obj = row.get("obj")
	var prop: String = String(row.get("prop"))
	if row.has("bool"):
		_apply_value(obj, prop, not bool(obj.get(prop)), row)
		return
	if row.has("enum"):
		var values: Array = row["enum"]
		var idx := values.find(obj.get(prop))
		idx = (idx + dir + values.size()) % values.size()
		_apply_value(obj, prop, values[idx], row)
		return
	var mn: float = row["min"]
	var mx: float = row["max"]
	var step: float = row["step"]
	var v: float = float(obj.get(prop))
	# Step on a grid anchored at `min` so repeated presses cannot drift.
	var n := roundi((v - mn) / step) + dir
	_apply_value(obj, prop, clampf(mn + float(n) * step, mn, mx), row)


## OK: switch -> toggle, enum -> cycle, value -> restore the boot default.
func _confirm() -> void:
	var row: Dictionary = rows[sel]
	if row.has("bool") or row.has("enum"):
		_adjust(1)
		return
	_apply_value(row["obj"], String(row["prop"]), _boot[sel], row)


func _apply_value(obj, prop: String, value, row: Dictionary) -> void:
	obj.set(prop, value)
	var after: String = String(row.get("after", ""))
	if after == "head_styles" and game != null and game.has_method("assign_head_styles"):
		# head styles are handed out per round; re-shuffle now so the switch is
		# visible without restarting (`assign_head_styles` is public core API).
		game.assign_head_styles()
	print("[tuning] %s = %s" % [prop, _value_text(row)])


## The live value formatted exactly like the panel shows it.
func _value_text(row: Dictionary) -> String:
	var obj = row.get("obj")
	if obj == null:
		return "-"
	var v = obj.get(row.get("prop"))
	if row.has("bool"):
		return _l("开", "ON") if bool(v) else _l("关", "OFF")
	if row.has("enum"):
		var labels: Array = row["labels"]
		var idx: int = (row["enum"] as Array).find(v)
		return String(labels[clampi(idx, 0, labels.size() - 1)])
	var f: float = float(v) * float(row["mul"])
	return (String(row["fmt"]) % f) + String(row["suffix"])


# ------------------------------------------------------------------- draw

func _draw() -> void:
	if not open or rows.is_empty():
		return
	var r := Rect2(PANEL_X, PANEL_Y, PANEL_W, _height)
	draw_style_box(_panel_style, r)
	# ---- header: title on the left, the live read-out on the right ----
	PSTheme.text(self, Vector2(r.position.x + 22.0, r.position.y + 34.0),
		_l("设置 / 调试 · 内部构建", "SETTINGS / DEBUG - internal build"), 26, PSTheme.TEXT)
	var p = game.player if game != null else null
	var live := _l("%d 节 · %d px/s · 压迫 %.0f%% · 剩 %.0fs",
		"%d seg · %d px/s · pressure %.0f%% · left %.0fs") % [
		p.body.size() if p != null else 0,
		int(p.speed) if p != null else 0,
		tuning.compute_ai_pressure() * 100.0 if tuning != null else 0.0,
		game.round_left if game != null else 0.0]
	PSTheme.text_r(self, r.end.x - 22.0, r.position.y + 33.0, live, 17, PSTheme.MUTED)
	draw_line(Vector2(r.position.x + 18.0, r.position.y + HEAD_H - 10.0),
		Vector2(r.end.x - 18.0, r.position.y + HEAD_H - 10.0),
		Color(0.42, 0.78, 1.0, 0.22), 1.0)
	# ---- rows ----
	var y := r.position.y + HEAD_H
	for i in rows.size():
		var row: Dictionary = rows[i]
		var h: float = float(row.get("h", ROW_H))
		if row.has("group"):
			draw_style_box(_group_style, Rect2(r.position.x + 14.0, y + 2.0,
				r.size.x - 28.0, h - 6.0))
			PSTheme.text_vc(self, r.position.x + 26.0, y + h * 0.5,
				String(row["group"]), 16, PSTheme.CYAN)
			y += h
			continue
		if i == sel:
			draw_style_box(_row_hl, Rect2(r.position.x + 10.0, y + 1.0,
				r.size.x - 20.0, h - 3.0))
		var label: String = String(row["label"]) if PSTheme.cjk_ok() else String(row["en"])
		var col := PSTheme.TEXT if i == sel else PSTheme.TEXT_SOFT
		PSTheme.text_vc(self, r.position.x + 26.0, y + h * 0.5 - 1.0, label, 21, col)
		PSTheme.text_r(self, r.end.x - 26.0, y + h * 0.5 + 8.0, _value_text(row), 21,
			PSTheme.LIME if i == sel else PSTheme.GOLD)
		# value track (float rows only): position inside [min, max]
		if row.has("min"):
			var mn: float = row["min"]
			var mx: float = row["max"]
			var t: float = clampf((float(row["obj"].get(row["prop"])) - mn)
				/ maxf(0.0001, mx - mn), 0.0, 1.0)
			var tx := r.position.x + 26.0
			var tw := r.size.x - 52.0
			draw_rect(Rect2(tx, y + h - 7.0, tw, 3.0), Color(1, 1, 1, 0.10), true)
			draw_rect(Rect2(tx, y + h - 7.0, tw * t, 3.0),
				PSTheme.CYAN if i == sel else PSTheme.with_a(PSTheme.CYAN, 0.55), true)
		y += h
	# ---- footer: remote key legend (the live numbers sit in the header) ----
	var fy := r.end.y - FOOT_H
	draw_line(Vector2(r.position.x + 18.0, fy), Vector2(r.end.x - 18.0, fy),
		Color(0.42, 0.78, 1.0, 0.22), 1.0)
	PSTheme.text_vc(self, r.position.x + 22.0, fy + FOOT_H * 0.5 - 3.0,
		_l("↑↓ 选行 · ←→ 调值 · OK 开关/复位 · 返回/F8 关闭",
			"UP/DN row · L/R change · OK toggle/reset · BACK/F8 close"), 17,
		PSTheme.MUTED)
