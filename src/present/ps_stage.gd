extends Control
## Workstream C — settlement "grow-up comparison" stage (js/resultStage.js).
##
## Eight lanes, one per ranked snake: the body grows upward to its final length,
## the tallest wins, and the lane card underneath carries rank / name / style /
## length / kills-deaths. The stage is fully deterministic from
## `PSGame.round_result`, so it keeps animating while the next round is prepared.

const PSTheme = preload("res://src/present/ps_theme.gd")
const PSAssets = preload("res://src/present/ps_assets.gd")

const BTN_NONE := 0
const BTN_RETRY := 1
const BTN_MENU := 2

var result = null
var game = null
var cfg = null
var t := 0.0
## Remote DPAD focus: 0 = 再来一局, 1 = 返回模式选择 (set by main.gd).
var focus: int = 0
var rows: Array = []
var max_len: int = 16
var player_rank: int = 0
var won: bool = false
## Height of the tallest column in design pixels.
var bar_max := 330.0
var baseline := 720.0

var _btns: Array = []
var _card: StyleBoxFlat = null
var _lane: StyleBoxFlat = null
var _lane_me: StyleBoxFlat = null
var _ghost: StyleBoxFlat = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Radius scale is 4 / 3 / 2 / 0 only (WEB-COMPUTED-STYLES §6.5); the
	# settlement rows themselves are radius 0 on the web and are re-cut in B3.
	_card = PSTheme.panel(Color(0.045, 0.07, 0.125, 0.88), PSTheme.PANEL_BORDER, PSTheme.R_PANEL,
		1, 8, "st_card")
	_lane = PSTheme.panel(Color(0.035, 0.055, 0.10, 0.72), PSTheme.TV_LINE_SOFT, PSTheme.R_NONE,
		1, 0, "st_lane")
	_lane_me = PSTheme.panel(Color(0.10, 0.16, 0.10, 0.82), Color(0.71, 1.0, 0.34, 0.85),
		PSTheme.R_NONE, 1, 0, "st_lane_me")
	_ghost = PSTheme.panel(Color(0.039, 0.078, 0.118, 0.92), PSTheme.PANEL_BORDER,
		PSTheme.R_CARD, 1, 12, "st_ghost")


func begin(p_result, p_game, p_cfg) -> void:
	result = p_result
	game = p_game
	cfg = p_cfg
	t = 0.0
	rows = p_result.ranking if p_result != null else []
	max_len = 16
	for r in rows:
		if r.length > max_len:
			max_len = r.length
	player_rank = p_result.player_rank if p_result != null else 0
	won = p_result.won if p_result != null else false


func button_at(pos: Vector2) -> int:
	for b in _btns:
		if (b[1] as Rect2).has_point(pos):
			return int(b[0])
	return BTN_NONE


func _ease(x: float) -> float:
	var k := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


## DPAD focus ring for the two settlement actions (remote-only navigation).
func _draw_focus_ring(r: Rect2) -> void:
	draw_rect(r.grow(4.0), PSTheme.with_a(PSTheme.CYAN, 0.92), false, 3.0)


func _draw() -> void:
	_btns.clear()
	var w := size.x
	var h := size.y
	# ---- opaque stage backdrop ----
	draw_texture_rect(PSAssets.bg_grad, Rect2(0, 0, w, h), false)
	var tile := 90.0
	draw_texture_rect(PSAssets.grid, Rect2(0, 0, w, h), true, Color(0.6, 0.9, 1.0, 0.5))
	# horizon glow behind the columns
	draw_texture_rect(PSAssets.blob, Rect2(-200.0, baseline - 620.0, w + 400.0, 900.0), false,
		Color(0.06, 0.24, 0.42, 0.30))
	if result == null:
		return
	var n := rows.size()
	if n == 0:
		return
	# ---- header ----
	var hx := 62.0
	var tab := Rect2(hx, 46.0, 470.0, 46.0)
	draw_rect(tab, PSTheme.CYAN, true)
	PSTheme.text(self, Vector2(tab.position.x + 16.0, tab.position.y + 32.0),
		"FINAL RESULTS / 长度赛" if PSTheme.cjk_ok() else "FINAL RESULTS / LENGTH",
		28, PSTheme.INK)
	var rank_col := PSTheme.LIME if won else PSTheme.TEXT
	var rtxt := "第 %d 名" % player_rank
	if not PSTheme.cjk_ok():
		rtxt = "RANK #%d" % player_rank
	draw_circle(Vector2(hx + 12.0, 150.0), 10.0, PSTheme.LIME if won else PSTheme.CYAN)
	PSTheme.text(self, Vector2(hx + 34.0, 168.0), rtxt, 62, rank_col)
	var sub := "2 分钟 · %d 条小蛇按最终长度比高 · 镜头随最高者升高" % n
	if not PSTheme.cjk_ok():
		sub = "2:00 round · %d snakes ranked by final length" % n
	PSTheme.text_c_fit(self, hx, 208.0, sub, 26, PSTheme.TEXT_SOFT, 1400.0)
	var me = result.player
	var stats := ""
	if me != null:
		# `peak_length` is THIS round's high-water mark; `result.best_length` is the
		# historical best (persisted across runs, see `PSettings`). They used to be
		# the same field printed twice, so the card claimed the round peak was the
		# all-time record.
		var peak: int = int(me.peak_length)
		if PSTheme.cjk_ok():
			stats = "本局最长 %d 节 · 吞食 %d 个 · 吞并 %d 次 · 死亡 %d 次 · 历史最佳 %d 节" % [
				peak, me.food_eaten, me.kills, me.deaths, result.best_length]
		else:
			stats = "round peak %d · ate %d · kills %d · deaths %d · all-time best %d" % [
				peak, me.food_eaten, me.kills, me.deaths, result.best_length]
	PSTheme.text_c_fit(self, hx, 240.0, stats, 24, PSTheme.MUTED, 1400.0)
	if won:
		PSTheme.text(self, Vector2(hx, 276.0), "冠军！" if PSTheme.cjk_ok() else "CHAMPION!",
			32, PSTheme.LIME)
	# ---- layout ----
	var lane_w := 132.0
	var gap := 18.0
	var total := lane_w * float(n) + gap * float(n - 1)
	var x0 := (w - total) * 0.5
	# length gridlines (right side labels)
	for k in 3:
		var frac := float(k + 1) * 0.25
		var gy := baseline - bar_max * frac
		draw_line(Vector2(x0 - 40.0, gy), Vector2(x0 + total + 40.0, gy),
			Color(0.34, 0.91, 1.0, 0.07), 1.0)
		PSTheme.text_r(self, x0 + total + 34.0, gy + 6.0, "%d 节" % int(float(max_len) * frac),
			20, PSTheme.with_a(PSTheme.CYAN, 0.45))
	# baseline neon
	for i in n:
		var row = rows[i]
		var lx := x0 + float(i) * (lane_w + gap)
		draw_line(Vector2(lx, baseline), Vector2(lx + lane_w, baseline),
			PSTheme.with_a(row.color, 0.85), 3.0)
	draw_line(Vector2(x0 - 30.0, baseline), Vector2(x0 + total + 30.0, baseline),
		Color(0.34, 0.91, 1.0, 0.22), 1.0)
	# ---- lanes ----
	for i in n:
		var row = rows[i]
		var lx2 := x0 + float(i) * (lane_w + gap)
		var delay := float(i) * 0.055
		var g := _ease((t - delay) / 0.95)
		var bh := bar_max * (float(row.length) / float(max_len)) * g
		var bw := lane_w - 34.0
		var bx := lx2 + 17.0
		var top := baseline - bh
		# column: tinted vertical gradient + inner highlight
		if bh > 2.0:
			draw_texture_rect(PSAssets.grad_v, Rect2(bx, top, bw, bh), false,
				PSTheme.with_a(row.color, 0.92))
			draw_texture_rect(PSAssets.grad_v, Rect2(bx + bw * 0.22, top, bw * 0.26, bh), false,
				Color(1, 1, 1, 0.16))
			# glow skirt
			draw_texture_rect(PSAssets.blob, Rect2(bx - 26.0, top - 40.0, bw + 52.0, 90.0), false,
				PSTheme.with_a(row.color, 0.20))
			# scale ticks
			var ticks := int(bh / 26.0)
			var k2 := 1
			while k2 <= ticks:
				var ty := baseline - 26.0 * float(k2)
				draw_line(Vector2(bx + 6.0, ty), Vector2(bx + bw - 6.0, ty),
					Color(1, 1, 1, 0.07), 1.0)
				k2 += 1
			# head on top of the column
			var hr := bw * 0.46
			var hc := Vector2(bx + bw * 0.5, top - hr * 0.4)
			draw_circle(hc, hr, PSTheme.lighten(row.color, 0.28))
			draw_circle(hc + Vector2(-hr * 0.18, -hr * 0.22), hr * 0.5, Color(1, 1, 1, 0.18))
			draw_circle(hc + Vector2(-hr * 0.32, -hr * 0.06), hr * 0.24, Color(1, 1, 1, 0.95))
			draw_circle(hc + Vector2(hr * 0.32, -hr * 0.06), hr * 0.24, Color(1, 1, 1, 0.95))
			draw_circle(hc + Vector2(-hr * 0.28, -hr * 0.04), hr * 0.12, Color(0.06, 0.08, 0.07))
			draw_circle(hc + Vector2(hr * 0.36, -hr * 0.04), hr * 0.12, Color(0.06, 0.08, 0.07))
			# rank label above the head: 24 px needs the short form — the card
			# below already spells out "N 节", so the column only carries the pair.
			var label := ""
			if PSTheme.cjk_ok():
				label = "%d · %d" % [row.rank, row.length]
			else:
				label = "#%d · %d" % [row.rank, row.length]
			if g > 0.35:
				PSTheme.text_c_fit(self, bx + bw * 0.5, top - hr * 1.5, label,
					24, PSTheme.TEXT if row.rank > 1 else PSTheme.GOLD, lane_w - 6.0, 20)
		# ---- lane card ----
		var card := Rect2(lx2, baseline + 8.0, lane_w, 140.0)
		draw_style_box(_lane_me if row.is_player else _lane, card)
		if row.is_player:
			draw_rect(Rect2(card.position.x, card.position.y, lane_w, 3.0), PSTheme.LIME, true)
		PSTheme.text_c(self, card.get_center().x, card.position.y + 34.0, str(row.rank), 30,
			PSTheme.LIME if row.rank == 1 else PSTheme.MUTED)
		var nm: String = row.name
		PSTheme.text_c_fit(self, card.get_center().x, card.position.y + 62.0, nm, 24,
			PSTheme.TEXT if row.is_player else PSTheme.TEXT_SOFT, lane_w - 8.0)
		if row.style != "":
			PSTheme.text_c_fit(self, card.get_center().x, card.position.y + 84.0, row.style,
				18, PSTheme.with_a(row.color, 0.9), lane_w - 8.0, 12)
		PSTheme.text_c(self, card.get_center().x, card.position.y + 110.0,
			"%d 节" % row.length if PSTheme.cjk_ok() else "%d" % row.length, 28, PSTheme.TEXT)
		PSTheme.text_c_fit(self, card.get_center().x, card.position.y + 132.0,
			"吞 %d · 死 %d" % [row.kills, row.deaths] if PSTheme.cjk_ok() \
			else "%dK %dD" % [row.kills, row.deaths], 18, PSTheme.MUTED, lane_w - 8.0, 12)
	# ---- actions: 再来一局 / 返回模式选择 (remote DPAD + OK) ----
	var bw := 380.0
	var bgap := 40.0
	var bx := (w - (bw * 2.0 + bgap)) * 0.5
	var by := h - 150.0
	var br := Rect2(bx, by, bw, 74.0)
	draw_style_box(PSTheme.panel(PSTheme.LIME, Color(0, 0, 0, 0), 18, 0, 16, "st_retry"), br)
	if focus == 0:
		_draw_focus_ring(br)
	PSTheme.text_c(self, br.get_center().x, br.get_center().y + 12.0,
		"再来一局" if PSTheme.cjk_ok() else "PLAY AGAIN", 36, PSTheme.INK)
	_btns.append([BTN_RETRY, br])
	br = Rect2(bx + bw + bgap, by, bw, 74.0)
	draw_style_box(_ghost, br)
	if focus == 1:
		_draw_focus_ring(br)
	PSTheme.text_c(self, br.get_center().x, br.get_center().y + 12.0,
		"返回模式选择" if PSTheme.cjk_ok() else "MODE SELECT", 36, PSTheme.TEXT)
	_btns.append([BTN_MENU, br])
	var hint_y := h - 44.0
	PSTheme.text_c_fit(self, w * 0.5, hint_y,
		"← → 选择 · OK 确认 · 按返回键回模式选择"
		if PSTheme.cjk_ok() else "LEFT/RIGHT select · OK confirm · BACK to mode select",
		28, PSTheme.MUTED, 1600.0)
	# right side info block (what the Web prototype shows as camera read-out)
	var info := Rect2(w - 300.0, 52.0, 240.0, 84.0)
	draw_style_box(_card, info)
	PSTheme.text(self, Vector2(info.position.x + 16.0, info.position.y + 30.0),
		"镜头 · 最高者" if PSTheme.cjk_ok() else "CAMERA · LEADER", 20, PSTheme.MUTED)
	PSTheme.text(self, Vector2(info.position.x + 16.0, info.position.y + 62.0),
		"视野 16 ~ %d 节" % max_len if PSTheme.cjk_ok() else "RANGE 16 ~ %d" % max_len,
		24, PSTheme.CYAN)
