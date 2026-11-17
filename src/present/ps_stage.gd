extends Control
## Workstream C — settlement, rebuilt as the web's **borderless score strip**
## (`js/resultStage.js` + `#resultOverlay`, measured in
## `Docs/WEB-COMPUTED-STYLES.md` §4.5 and the `settle` capture
## `evidence/web-ref/web-settle-1920.png`).
##
## What the shipped web does — and this file now does:
##
##   * the arena is replaced by a full-bleed night sky (three-stop gradient +
##     deterministic stars), **not** a card wall and **not** a grid of panels;
##   * all eight snakes are re-laid out as vertical columns growing up from one
##     horizon. The columns are **the real snake bodies**: the same character
##     body texture and head atlas the world view drew this round (`PSSkins`),
##     not a bar or a rounded tile;
##   * the camera starts at the horizon and rises with the tallest head, using the
##     web's own law (`targetScreens 1.55`, `headMargin .22`, `follow 9`), so the
##     segment ruler rolls and the winner's head parks at 22 % of the screen;
##   * the bottom 176 px is one borderless 8-cell strip: **164.56 x 92** rows with
##     a **4 px top border in the lane colour**, the player's row lime, and the
##     measured type ramp (rank 19/900 gold, name 15/700, length 23/900,
##     kills/deaths 11/600). `#resultRows` is **1316.53 px = 68.57 %** wide and its
##     cell centres sit exactly under the column centres (same 60 % lane span);
##   * the top 66 px carries the headline: a 16 px lime dot, **36/900** rank line
##     and the **15/700** stat line (this round's peak vs the stored 历史最长);
##   * the rise is short (**1.1 s**, ease-out) and skippable (OK/BACK); the two
##     remote actions use the band's radius-3 / lime / cyan-stroke language.
##
## The measured geometry below is design px at 1920x1080, i.e. the web's CSS px
## 1:1 (`WEB-COMPUTED-STYLES.md` §6.5). Pixel checks against the reference:
##   rows y 916..1008, x 301.73..1618.26 (lane top borders measured at
##   302..1614 with 1 px dividers), title ink x 52, dot 16 px at (24..39,
##   20..35), button 206.81 x 54 at y 1018 — all reproduced here.

const PSTheme = preload("res://src/present/ps_theme.gd")
const PSAssets = preload("res://src/present/ps_assets.gd")
const PSSkins = preload("res://src/present/ps_skins.gd")
const PSData = preload("res://src/present/ps_skin_data.gd")

const BTN_NONE := 0
const BTN_RETRY := 1
const BTN_MENU := 2

# ---- web ResultStage parameters (`js/resultStage.js` STAGE) ------------------
## The web grow lasts 4.6 s; the owner brief caps the rise at ~1.2 s. Growth and
## camera share this one clock, so "longest reaches the top" still happens first.
const RISE_SEC := 1.1
## Title / stat fade-in after the rise (web: opacity .5 s transition).
const TITLE_FADE := 0.30
## Winner height in screens (`STAGE.targetScreens`) — 1.55 means the column
## always breaks the top, which is what makes the camera rise visible.
const TARGET_SCREENS := 1.55
## Where the tallest head parks on screen (`STAGE.headMargin`).
const HEAD_MARGIN := 0.22
## Camera follow (`STAGE.follow`), frame-rate independent exponential.
const FOLLOW := 9.0
## Body point spacing / mid-body sway (`STAGE.pointGap`, `STAGE.waveAmp`).
const POINT_GAP := 13.0
const WAVE_AMP := 8.0
## Segment px scale bounds (`STAGE.minUnit`, `STAGE.maxUnit`).
const MIN_UNIT := 1.2
const MAX_UNIT := 46.0
## The scale always assumes at least 20 segments (`STAGE.layout` maxLen floor).
const SCALE_LEN_FLOOR := 20
## Column girth: `step * .19 * (.88 + .24 * min(1, len/120))`, clamped.
const GIRTH_RATIO := 0.19
const MIN_R := 12.0
const MAX_R := 40.0
## First-to-last lane centre span / screen width (`STAGE.laneSpan`).
const LANE_SPAN := 0.60
## One ruler line every 10 segments; a lime label every 50.
const RULER_STEP_SEG := 10
const RULER_MAJOR := 5
## Body taper copied from the world tube (`ps_world_view.gd` TAPER_*).
const TAPER_TAIL := 0.55
const TAPER_POW := 1.45
## Lateral shade on the textured tube (`ps_world_view.gd` TEX_LAT).
const TEX_LAT := 0.18

# ---- measured settlement geometry (WEB-COMPUTED-STYLES §4.5 @1920x1080) ----
const TOP_H := 66.0
const ROWS_Y := 916.0
const ROW_H := 92.0
const ROW_BORDER_TOP := 4.0
const STRIP_Y := 904.0
const ACTIONS_Y := 1008.0
const BTN_W := 206.81
const BTN_H := 54.0
const BTN_Y := 1018.0
const BTN_GAP := 16.0
## `#skipStageBtn`: x = 1920 - 167.91, y 10, 143.91 x 46 (13/800).
const SKIP_W := 143.91
const SKIP_H := 46.0
const SKIP_RIGHT := 167.91
const SKIP_Y := 10.0

# ---- type ramp (WEB-COMPUTED-STYLES §3 / §4.5) ------------------------------
const TITLE_SZ := 36
const STATS_SZ := 15
const RANK_SZ := 19
const NAME_SZ := 15
const LEN_SZ := 23
const EXTRA_SZ := 11
const ACTION_SZ := 22
const HINT_SZ := 12
const SKIP_SZ := 13
const TAG_SZ_FIRST := 17
const TAG_SZ := 14

# ---- measured colours --------------------------------------------------------
const TITLE_COL := Color(244.0 / 255.0, 251.0 / 255.0, 1.0)
const STATS_COL := Color(196.0 / 255.0, 224.0 / 255.0, 242.0 / 255.0, 0.78)
const ROW_NAME_COL := Color(220.0 / 255.0, 236.0 / 255.0, 247.0 / 255.0)
const ROW_LEN_COL := Color(242.0 / 255.0, 251.0 / 255.0, 1.0)
const TAG_FIRST_COL := Color("FFE07A")
const SKY_TOP := Color("0B2140")
const SKY_MID := Color("071426")
const SKY_BOT := Color("040912")
const STRIP_INK := Color(4.0 / 255.0, 9.0 / 255.0, 18.0 / 255.0)
const BTN_INK := Color(10.0 / 255.0, 31.0 / 255.0, 16.0 / 255.0)
const BTN_EDGE := Color(95.0 / 255.0, 191.0 / 255.0, 58.0 / 255.0)

## Result payload (`PSRoundResult`), its source game (for skin lookup) and config.
var result = null
var game = null
var cfg = null
## Rise clock; main.gd advances it through `tick()`.
var t := 0.0
## True once growth + camera have finished (or `skip()` was pressed): the title,
## the final lengths and the two actions become live.
var settled := false
## Remote DPAD focus: 0 = 再来一局, 1 = 返回模式选择 (set by main.gd).
var focus: int = 0
## Sorted ranking rows (`PSRankRow`), index 0 = first place.
var rows: Array = []
## Longest final length of the round (columns are scaled together).
var max_len: int = 0
var player_rank: int = 0
var won: bool = false
## Camera state in the stage's screen space (world y = 0 is the horizon).
var cam_y := 0.0
var lift := 0.0

# ---- layout cache (computed in `begin` and whenever the size changes) ------
var _n := 0
var _w := 1920.0
var _h := 1080.0
var _span := 0.0
var _step := 0.0
var _x0 := 0.0
var _rows_w := 0.0
var _rows_x := 0.0
var _row_w := 0.0
var _unit := MIN_UNIT
var _max_height := 0.0
var _scale_len := SCALE_LEN_FLOOR

# ---- per-lane resolved art ---------------------------------------------------
## Character skin index per lane (-1 = files missing, procedural fallback).
var _lane_skin := PackedInt32Array()
## Identity colour per lane: the skin's own `dot` when available, else `row.color`.
var _lane_col: Array = []
## Deterministic star field: [normalised x, normalised y, alpha, radius].
var _star_seed: Array = []

var _btns: Array = []
# ---- reusable draw buffers (no per-frame allocation) ------------------------
var _pts := PackedVector2Array()
var _nrm := PackedVector2Array()
var _rad := PackedFloat32Array()
var _ts := PackedFloat32Array()
var _rv := PackedVector2Array()
var _rc := PackedColorArray()
var _ri := PackedInt32Array()
var _bv := PackedVector2Array()
var _bc := PackedColorArray()
var _buv := PackedVector2Array()
var _bi := PackedInt32Array()
var _hv := PackedVector2Array()
var _hc := PackedColorArray()
var _huv := PackedVector2Array()
var _hi := PackedInt32Array()
var _star_v := PackedVector2Array()
var _star_c := PackedColorArray()
var _star_i := PackedInt32Array()
var _glow_v := PackedVector2Array()
var _glow_c := PackedColorArray()
var _glow_i := PackedInt32Array()
var _osd_arms := PackedVector2Array()
var _div_pairs := PackedVector2Array()
## Cached styles (radius scale 4 / 3 / 2 / 0 only).
var _skip_style: StyleBoxFlat = null
var _key_style: StyleBoxFlat = null
var _ghost_edge: StyleBoxFlat = null
var _focus_style: StyleBoxFlat = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# `#skipStageBtn`: r3, rgba(8,20,36,.92), 1 px cyan + 3 px cyan bottom edge.
	_skip_style = PSTheme.panel(Color(8.0 / 255.0, 20.0 / 255.0, 36.0 / 255.0, 0.92),
		PSTheme.TV_LINE, PSTheme.R_CARD, 1, 0, "st_skip")
	_skip_style.border_width_bottom = 3
	# Keycap (web `.keycap`: white chip, dark glyph); solid + r4 is one draw call.
	_key_style = PSTheme.panel(Color(226.0 / 255.0, 250.0 / 255.0, 1.0),
		Color(1, 1, 1, 0.35), PSTheme.R_PANEL, 1, 0, "st_key")
	# Secondary action: the web's cyan-stroked ghost (r3 + 3 px bottom edge).
	_ghost_edge = PSTheme.panel(Color(0, 0, 0, 0), PSTheme.TV_LINE, PSTheme.R_CARD, 1,
		0, "st_ghost_edge")
	_ghost_edge.border_width_bottom = 3
	# Lime focus chip: 3 px lime ring (the band's focus language), plus a halo.
	_focus_style = PSTheme.panel(Color(0, 0, 0, 0), PSTheme.with_a(PSTheme.LIME, 0.92),
		PSTheme.R_PANEL, 3, 0, "st_focus")
	# OSD arms: 4 corners x 2 x (30, 2) at inset 44 (web `body::after`, alpha .55).
	var l := 44.0
	var e := 44.0 + 30.0
	_osd_arms = PackedVector2Array([
		Vector2(l, l), Vector2(e, l), Vector2(l, l), Vector2(l, l + 30.0),
		Vector2(1920.0 - l, l), Vector2(1920.0 - e, l),
		Vector2(1920.0 - l, l), Vector2(1920.0 - l, l + 30.0),
		Vector2(l, 1080.0 - l), Vector2(e, 1080.0 - l),
		Vector2(l, 1080.0 - l), Vector2(l, 1080.0 - l - 30.0),
		Vector2(1920.0 - l, 1080.0 - l), Vector2(1920.0 - e, 1080.0 - l),
		Vector2(1920.0 - l, 1080.0 - l), Vector2(1920.0 - l, 1080.0 - l - 30.0)])
	_build_stars()


func _cn(cn: String, en: String) -> String:
	return cn if PSTheme.cjk_ok() else en


## 46 deterministic stars (`ResultStage.drawStars`): a sine hash, no RNG use.
func _build_stars() -> void:
	_star_seed.clear()
	var i := 0
	while i < 46:
		var fx := fmod(sin(float(i) * 91.7) * 43758.5453, 1.0)
		var fy := fmod(sin(float(i) * 37.3) * 24634.6345, 1.0)
		if fx < 0.0:
			fx += 1.0
		if fy < 0.0:
			fy += 1.0
		_star_seed.append([fx, fy, 0.12 + 0.18 * (0.5 + 0.5 * sin(float(i) * 1.3)),
			1.7 if i % 7 == 0 else 1.0])
		i += 1


## Start a settlement for `p_result`. Row data is already final; the skin index
## is resolved now, while the round's snake objects still exist.
func begin(p_result, p_game, p_cfg) -> void:
	result = p_result
	game = p_game
	cfg = p_cfg
	t = 0.0
	settled = false
	rows = p_result.ranking if p_result != null else []
	max_len = 0
	for r in rows:
		max_len = maxi(max_len, int(r.length))
	if p_result != null:
		player_rank = int(p_result.player_rank)
		won = bool(p_result.won)
	_lane_skin.resize(rows.size())
	_lane_col.clear()
	var i := 0
	while i < rows.size():
		var sk := -1
		var s = _snake_for(int(rows[i].id))
		if s != null:
			sk = PSSkins.of(s)
		if not PSSkins.usable(sk):
			sk = -1
		_lane_skin[i] = sk
		var col: Color = rows[i].color
		if sk >= 0:
			var dot = PSSkins.get_skin(sk).get("dot", col)
			if dot is Color:
				col = dot
		_lane_col.append(col)
		i += 1
	_layout()
	cam_y = -_h * 0.5
	lift = 0.0
	queue_redraw()


## The snake object this row came from (skin metadata lives there; `PSRankRow`
## has no skin field and the core is not ours to change).
func _snake_for(id: int):
	if game == null:
		return null
	for s in game.snakes:
		if int(s.id) == id:
			return s
	return null


## Recompute lane / strip geometry (also on a viewport size change).
func _layout() -> void:
	_n = rows.size()
	_w = maxf(1.0, size.x)
	_h = maxf(1.0, size.y)
	_scale_len = maxi(SCALE_LEN_FLOOR, max_len)
	_unit = clampf(_h * TARGET_SCREENS / float(_scale_len), MIN_UNIT, MAX_UNIT)
	_max_height = float(max_len) * _unit
	_span = _w * LANE_SPAN
	if _n > 1:
		_step = _span / float(_n - 1)
		_rows_w = _span * float(_n) / float(_n - 1)
		_x0 = _w * 0.5 - _span * 0.5
	else:
		_step = 0.0
		_rows_w = _w
		_x0 = _w * 0.5
	_rows_x = (_w - _rows_w) * 0.5
	_row_w = _rows_w / float(maxi(1, _n))


## Ease-out growth progress (`raw * (2 - raw)`, the web's `ResultStage.update`).
func _progress() -> float:
	if settled:
		return 1.0
	var raw := clampf(t / RISE_SEC, 0.0, 1.0)
	return raw * (2.0 - raw)


func _growth() -> float:
	return _max_height * _progress()


func _lane_height(i: int) -> float:
	return minf(float(rows[i].length) * _unit, _growth())


## Column half-width (`STAGE.layout.radius`): follows the lane pitch, nudged up
## for longer snakes, clamped so a short round cannot draw a wall of tubes.
func _lane_radius(i: int) -> float:
	return clampf(_step * GIRTH_RATIO * (0.88 + 0.24 * minf(1.0,
		float(rows[i].length) / 120.0)), MIN_R, MAX_R)


## Advance the rise (called from main.gd's MODE_SETTLE branch with `real_dt`).
## Every column shares one px/second rate, so short snakes stop early and the
## tallest keeps climbing — the web's "break the screen" show.
func tick(dt: float) -> void:
	t = minf(t + dt, 3.0)
	if rows.is_empty():
		return
	if _n != rows.size():
		_layout()
	var hmax: float = minf(_max_height, _growth())
	var cam0 := -_h * 0.5
	# The target follows the CURRENT tallest head (web `cameraTarget(hMax)`), so
	# the camera only starts rising once the winner actually reaches the top band.
	var target := minf(cam0, -hmax + _h * (0.5 - HEAD_MARGIN))
	# Frame-rate independent exponential follow, same coefficient as the web.
	cam_y += (target - cam_y) * (1.0 - exp(-FOLLOW * dt))
	# Hard invariant: the tallest head may never leave the top of the frame while
	# the camera is still catching up (the web's `minHeadY` clamp).
	var min_head := maxf(70.0, _h * 0.14)
	var head_screen := -hmax - cam_y + _h * 0.5
	if head_screen < min_head:
		cam_y = minf(cam_y, -hmax + _h * 0.5 - min_head)
	if not settled and t >= RISE_SEC:
		settled = true
		cam_y = minf(cam0, -_max_height + _h * (0.5 - HEAD_MARGIN))
	lift = maxf(0.0, cam0 - cam_y)


## Skip the rest of the rise: full height, final camera, actions live at once.
func skip() -> void:
	settled = true
	t = maxf(t, RISE_SEC)
	cam_y = minf(-_h * 0.5, -_max_height + _h * (0.5 - HEAD_MARGIN))
	lift = maxf(0.0, -_h * 0.5 - cam_y)
	queue_redraw()


## True while the stage still changes from frame to frame (rise + title fade).
## main.gd stops queueing redraws once this is false: a settled score screen is a
## still, so keeping the last canvas commands costs no per-frame geometry/text
## rebuild (the eight rim/body/head builds + ~50 text runs are the whole budget).
func is_animating() -> bool:
	return (not settled) or t < RISE_SEC + TITLE_FADE


func button_at(pos: Vector2) -> int:
	for b in _btns:
		if (b[1] as Rect2).has_point(pos):
			return int(b[0])
	return BTN_NONE


# ------------------------------------------------------------------- draw

func _draw() -> void:
	_btns.clear()
	if _w <= 1.0 or _n != rows.size():
		_layout()
	_draw_sky()
	_draw_ruler()
	_draw_ground()
	if result == null or rows.is_empty():
		_draw_osd()
		_draw_brackets()
		return
	var oy := -cam_y + _h * 0.5
	# Rim + halo first (one command each for the whole field), then the bodies.
	_draw_halos(oy)
	_draw_rims(oy)
	var i := 0
	while i < _n:
		var h: float = _lane_height(i)
		if h >= 8.0:
			_build_column(i, h, oy)
			_draw_body(i)
		i += 1
	# Heads: four atlas quads per snake, one command each.
	i = 0
	while i < _n:
		var h: float = _lane_height(i)
		if h >= 8.0:
			_build_column(i, h, oy)
			_draw_head(i, h, oy)
		i += 1
	_draw_winner_glow(oy)
	_draw_tags(oy)
	# OSD vignette + scanlines sit under the strip so the score type stays crisp.
	_draw_osd()
	_draw_strip()
	_draw_actions()
	# OSD corners sit under the top band + headline so the rank line stays crisp;
	# the bottom arms are already over the strip (the brief keeps the brackets).
	_draw_brackets()
	_draw_top_band()
	_draw_headline()
	if not settled:
		_draw_skip()


func _draw_brackets() -> void:
	draw_multiline(_osd_arms, Color(0.337, 0.910, 1.0, 0.55), 2.0)


func _draw_sky() -> void:
	# `linear-gradient(180deg, #0B2140, #071426 50%, #040912)` — two quads with
	# per-vertex colours (Gouraud): two draw calls, no texture.
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(_w, 0),
		Vector2(_w, _h * 0.5), Vector2(0, _h * 0.5)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_MID, SKY_MID]))
	draw_polygon(PackedVector2Array([Vector2(0, _h * 0.5), Vector2(_w, _h * 0.5),
		Vector2(_w, _h), Vector2(0, _h)]),
		PackedColorArray([SKY_MID, SKY_MID, SKY_BOT, SKY_BOT]))
	# Stars use the frozen rise clock, so the settled frame is static (the
	# determinism gate); the web keeps twinkling.
	var clock := minf(t, RISE_SEC)
	_star_v.resize(0)
	_star_c.resize(0)
	_star_i.resize(0)
	for st in _star_seed:
		var a: float = float(st[2]) * (0.65 + 0.35 * (0.5 + 0.5 * sin(clock * 1.3
			+ float(st[0]) * 40.0)))
		PSTheme._disc_append(_star_v, _star_c, _star_i,
			Vector2(float(st[0]) * _w, float(st[1]) * _h), float(st[3]),
			Color(190.0 / 255.0, 230.0 / 255.0, 1.0, a), 5)
	PSTheme.band_flush(self, _star_v, _star_c, _star_i)


## Horizontal 10-segment ruler, labels every 50 segments on the right edge.
## Rises with the camera — the visible proof the camera moved.
func _draw_ruler() -> void:
	var step := _unit * float(RULER_STEP_SEG)
	if step < 1.0 or _max_height <= 0.0:
		return
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	var labels: Array = []
	var top_world := cam_y - _h * 0.5
	var bot_world := cam_y + _h * 0.5
	var max_k := int(ceil((_max_height + _h * 2.0) / step))
	var k := 1
	while k <= max_k:
		var wy := -float(k) * step
		if wy >= top_world - step and wy <= bot_world + step:
			var sy := wy - cam_y + _h * 0.5
			if k % RULER_MAJOR == 0:
				major.append(Vector2(0.0, sy))
				major.append(Vector2(_w, sy))
				labels.append([sy, k * RULER_STEP_SEG])
			else:
				minor.append(Vector2(0.0, sy))
				minor.append(Vector2(_w, sy))
		k += 1
	if minor.size() > 0:
		draw_multiline(minor, PSTheme.with_a(PSTheme.CYAN, 0.08), 1.0)
	if major.size() > 0:
		draw_multiline(major, PSTheme.with_a(PSTheme.LIME, 0.16), 1.0)
	for lb in labels:
		PSTheme.text_r(self, _w - 14.0, float(lb[0]) - 4.0,
			_cn("%d 节" % int(lb[1]), "%d" % int(lb[1])), 12,
			PSTheme.with_a(PSTheme.LIME, 0.55), false)


## Shared horizon: lime line + a short downward glow. Mostly under the strip,
## so it is only visible as the camera lifts (like the web's `drawGround`).
func _draw_ground() -> void:
	var gy := -cam_y + _h * 0.5
	if gy > -80.0 and gy < _h + 400.0:
		draw_rect(Rect2(0.0, gy, _w, 60.0),
			Color(182.0 / 255.0, 1.0, 87.0 / 255.0, 0.10), true)
		draw_line(Vector2(0.0, gy), Vector2(_w, gy),
			Color(182.0 / 255.0, 1.0, 87.0 / 255.0, 0.55), 2.0)


## Column geometry: head at the top, tail on the horizon. The sway is the web's
## `drawSnake` S-curve (`waveAmp 8`, zero at both ends); the phase freezes at
## `RISE_SEC`, so the settled frame cannot depend on wall-clock time.
func _build_column(i: int, height: float, oy: float) -> void:
	var cx: float = _x0 + _step * float(i)
	var r := _lane_radius(i)
	var npts := maxi(2, int(ceil(height / POINT_GAP)) + 1)
	_pts.resize(npts)
	_nrm.resize(npts)
	_rad.resize(npts)
	_ts.resize(npts)
	var clock := minf(t, RISE_SEC)
	var phase := float(i) * 1.73
	var j := 0
	while j < npts:
		var k := float(j) / float(npts - 1)
		var wob := sin(clock * 2.1 + float(j) * 0.25 + phase) * WAVE_AMP * sin(k * PI)
		_pts[j] = Vector2(cx + wob, -height * (1.0 - k) + oy)
		_ts[j] = k
		_rad[j] = r * (1.0 + (TAPER_TAIL - 1.0) * pow(k, TAPER_POW))
		j += 1
	PSTheme.band_normals(_pts, _nrm)


## Character rim for every column in one command, painted before the bodies.
func _draw_rims(oy: float) -> void:
	_rv.resize(0)
	_rc.resize(0)
	_ri.resize(0)
	var i := 0
	while i < _n:
		var h: float = _lane_height(i)
		if h >= 8.0:
			_build_column(i, h, oy)
			var rim: Color = PSTheme.darken(_lane_col[i], 0.55)
			if _lane_skin[i] >= 0:
				var rc = PSSkins.get_skin(_lane_skin[i]).get("rim", rim)
				if rc is Color:
					rim = rc
			PSTheme.band_rim_append(_rv, _rc, _ri, _pts, _nrm, _rad, rim, 5.5,
				true, true, Rect2(), 0.0)
		i += 1
	PSTheme.band_flush(self, _rv, _rc, _ri)


## Soft colour halo behind every column (the world's additive halo, normal-blend
## on this pass: the settle sky is almost black, so .16 inward / 0 outward reads
## as the same coloured air around the tube at a fraction of the cost).
func _draw_halos(oy: float) -> void:
	_glow_v.resize(0)
	_glow_c.resize(0)
	_glow_i.resize(0)
	var i := 0
	while i < _n:
		var h: float = _lane_height(i)
		if h >= 8.0:
			_build_column(i, h, oy)
			var col: Color = _lane_col[i]
			if _lane_skin[i] >= 0:
				var hc = PSSkins.get_skin(_lane_skin[i]).get("halo", col)
				if hc is Color:
					col = hc
			PSTheme.band_halo_append(_glow_v, _glow_c, _glow_i, _pts, _nrm, _rad,
				Color(col.r, col.g, col.b, 0.30), Color(col.r, col.g, col.b, 0.0),
				24.0, 1.35, Rect2())
		i += 1
	PSTheme.band_flush(self, _glow_v, _glow_c, _glow_i)


func _draw_body(i: int) -> void:
	var sk := _lane_skin[i]
	var tex := PSSkins.body_tex(sk) if sk >= 0 else null
	if tex != null:
		_bv.resize(0)
		_bc.resize(0)
		_buv.resize(0)
		_bi.resize(0)
		PSTheme.band_tex_append(_bv, _bc, _buv, _bi, _pts, _nrm, _rad, _ts, TEX_LAT,
			Color(0, 0, 0, 0), 0.0, 0.0, Rect2())
		PSTheme.flush_tex(self, _bv, _bc, _buv, _bi, tex)
		return
	# Procedural fallback (character files missing): the old gel column, tinted
	# with the lane colour. Never hit in a complete build.
	var top: float = _pts[0].y
	var h: float = _pts[_pts.size() - 1].y - top
	var col: Color = _lane_col[i]
	draw_texture_rect(PSAssets.grad_v, Rect2(_pts[0].x - _rad[0], top, _rad[0] * 2.0, h),
		false, Color(col.r, col.g, col.b, 0.92))
	draw_texture_rect(PSAssets.grad_v, Rect2(_pts[0].x - _rad[0] * 0.3, top,
		_rad[0] * 0.6, h), false, Color(1, 1, 1, 0.16))


## The character head from its own atlas: head -> eyes -> mouth -> decor, one
## command (the same quad composite the world view uses), facing up (`-PI/2`).
func _draw_head(i: int, height: float, oy: float) -> void:
	var sk := _lane_skin[i]
	var head := Vector2(_pts[0].x, -height + oy)
	var hr: float = _rad[0] * 1.38
	if sk >= 0:
		var atlas := PSSkins.atlas_tex(sk)
		var sc: float = (PSData.HEAD_W_MUL * hr) / (PSData.HEAD_HALF_W * PSData.ATLAS_K)
		if atlas != null and sc > 0.0:
			# heading = -PI/2 (up) -> rot = -PI: the pack's +Y axis points up.
			var rot := -PI
			var ax := Vector2(cos(rot), sin(rot)) * sc
			var ay := Vector2(-sin(rot), cos(rot)) * sc
			_hv.resize(0)
			_hc.resize(0)
			_huv.resize(0)
			_hi.resize(0)
			var atl := PSSkins.atlas_size(sk)
			var keys := ["head", "eyes_open", "mouth_closed", "decor"]
			for key in keys:
				PSTheme.atlas_quad_append(_hv, _hc, _huv, _hi, atl, head, ax, ay,
					PSSkins.region_off(sk, key), PSSkins.region(sk, key), Color.WHITE)
			PSTheme.flush_tex(self, _hv, _hc, _huv, _hi, atlas)
			return
	# Procedural fallback head: a light disc with two eyes.
	var col: Color = _lane_col[i]
	draw_circle(head, hr, PSTheme.lighten(col, 0.28))
	draw_circle(head + Vector2(-hr * 0.30, -hr * 0.10), hr * 0.22, Color(1, 1, 1, 0.95))
	draw_circle(head + Vector2(hr * 0.30, -hr * 0.10), hr * 0.22, Color(1, 1, 1, 0.95))
	draw_circle(head + Vector2(-hr * 0.30, -hr * 0.10), hr * 0.10, Color(0.06, 0.08, 0.07))
	draw_circle(head + Vector2(hr * 0.30, -hr * 0.10), hr * 0.10, Color(0.06, 0.08, 0.07))


## Gold halo around the champion's head once the result is final (web: the
## `lighter` radial is only drawn in `phase === 'hold'`).
func _draw_winner_glow(oy: float) -> void:
	if not settled or rows.is_empty() or int(rows[0].rank) != 1:
		return
	var h: float = _lane_height(0)
	if h < 8.0:
		return
	var hr: float = _lane_radius(0) * 1.38
	var c := Vector2(_x0, oy - h)
	var a := clampf((t - RISE_SEC) / TITLE_FADE, 0.0, 1.0)
	draw_texture_rect(PSAssets.blob, Rect2(c.x - hr * 4.2, c.y - hr * 4.2,
		hr * 8.4, hr * 8.4), false, Color(1.0, 0.86, 0.36, 0.30 * a))


## Per-column label: `★ N 名 · L 节` above the head (below it when the top band
## would clip it), gold for first place, the lane colour otherwise.
func _draw_tags(oy: float) -> void:
	var safe_top := maxf(62.0, _h * 0.095)
	var i := 0
	while i < _n:
		var h: float = _lane_height(i)
		if h < 8.0:
			i += 1
			continue
		var cx: float = _x0 + _step * float(i)
		var head_sy: float = oy - h
		var r := _lane_radius(i)
		if head_sy > _h - 150.0:
			i += 1
			continue
		var first: bool = int(rows[i].rank) == 1
		var shown := int(rows[i].length) if settled else int(round(h / _unit))
		var label: String
		if _step > 0.0 and _step < 92.0:
			label = "%s%d·%d" % ["★" if first else "", int(rows[i].rank), shown]
		else:
			label = "%s%d 名 · %d 节" % ["★ " if first else "", int(rows[i].rank), shown]
		var sz: int = clampi(int(round(_step * 0.22)), 10,
			TAG_SZ_FIRST if first else TAG_SZ)
		var f := PSTheme.tracked(0, true)
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
		var tx := clampf(cx, tw * 0.5 + 10.0, _w - tw * 0.5 - 10.0)
		var above := head_sy - r * 2.6
		var ty := above
		var below := above < safe_top
		if below:
			# Web: no room above -> tuck the tag under the head on a dark capsule.
			ty = head_sy + r * 3.0
		var base := ty + float(sz) * 0.35
		if below:
			draw_rect(Rect2(tx - tw * 0.5 - 7.0, ty - float(sz) * 0.8, tw + 14.0,
				float(sz) * 1.6), Color(4.0 / 255.0, 9.0 / 255.0, 18.0 / 255.0, 0.74), true)
		var col: Color = TAG_FIRST_COL if first else _lane_col[i]
		draw_string_outline(f, Vector2(tx - tw * 0.5, base), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz, maxi(3, int(round(float(sz) * 0.28))),
			Color(8.0 / 255.0, 4.0 / 255.0, 18.0 / 255.0, 0.9))
		draw_string(f, Vector2(tx - tw * 0.5, base), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz, col)
		i += 1


func _draw_osd() -> void:
	draw_texture_rect(PSAssets.vignette, Rect2(0, 0, _w, _h), false)
	draw_texture_rect(PSAssets.scanline, Rect2(0, 0, _w, _h), true)


## The borderless score strip: 176 px band; 8 cells with a 4 px lane-colour top
## border, the player's row lime, and the measured rank / name / length ramp.
## Cell centres are the column centres by construction (`_rows_w` formula).
func _draw_strip() -> void:
	var ra := 1.0 if settled else 0.42
	# ---- band: transparent -> rgba(4,9,18,.95) over 12 px -> .99 ----
	draw_polygon(PackedVector2Array([Vector2(0, STRIP_Y), Vector2(_w, STRIP_Y),
		Vector2(_w, ROWS_Y), Vector2(0, ROWS_Y)]),
		PackedColorArray([Color(STRIP_INK.r, STRIP_INK.g, STRIP_INK.b, 0.0),
			Color(STRIP_INK.r, STRIP_INK.g, STRIP_INK.b, 0.0),
			Color(STRIP_INK.r, STRIP_INK.g, STRIP_INK.b, 0.95),
			Color(STRIP_INK.r, STRIP_INK.g, STRIP_INK.b, 0.95)]))
	draw_rect(Rect2(0, ROWS_Y, _w, _h - ROWS_Y),
		Color(STRIP_INK.r, STRIP_INK.g, STRIP_INK.b, 0.99), true)
	# ---- one background for the eight cells (cyan .045), player's cell lime ----
	draw_rect(Rect2(_rows_x, ROWS_Y, _rows_w, ROW_H),
		Color(0.337, 0.910, 1.0, 0.045 * ra), true)
	var i := 0
	while i < _n:
		var x: float = _rows_x + _row_w * float(i)
		var is_me: bool = bool(rows[i].is_player)
		if is_me:
			draw_rect(Rect2(x, ROWS_Y, _row_w, ROW_H),
				Color(182.0 / 255.0, 1.0, 87.0 / 255.0, 0.16 * ra), true)
			draw_rect(Rect2(x + 1.0, ROWS_Y + 1.0, _row_w - 2.0, ROW_H - 1.0),
				Color(182.0 / 255.0, 1.0, 87.0 / 255.0, 0.22 * ra), false, 1.0)
		var lane: Color = PSTheme.LIME if is_me else _lane_col[i]
		draw_rect(Rect2(x, ROWS_Y, _row_w, ROW_BORDER_TOP),
			Color(lane.r, lane.g, lane.b, ra), true)
		i += 1
	# ---- 1 px cyan dividers, one multiline command ----
	_div_pairs.resize(0)
	i = 1
	while i < _n:
		_div_pairs.append(Vector2(_rows_x + _row_w * float(i), ROWS_Y))
		_div_pairs.append(Vector2(_rows_x + _row_w * float(i), ROWS_Y + ROW_H))
		i += 1
	if _div_pairs.size() > 0:
		draw_multiline(_div_pairs, Color(0.337, 0.910, 1.0, 0.12 * ra), 1.0)
	# ---- cell typography ----
	i = 0
	while i < _n:
		var r = rows[i]
		var cx: float = _rows_x + _row_w * (float(i) + 0.5)
		var me: bool = bool(r.is_player)
		PSTheme.text_tc(self, cx, ROWS_Y + 28.0, str(int(r.rank)), RANK_SZ,
			Color(PSTheme.TV_GOLD.r, PSTheme.TV_GOLD.g, PSTheme.TV_GOLD.b, ra),
			0.36, false, true)
		PSTheme.text_c(self, cx, ROWS_Y + 51.0, String(r.name), NAME_SZ,
			Color(ROW_NAME_COL.r, ROW_NAME_COL.g, ROW_NAME_COL.b, ra), false)
		if settled:
			var len_s := _cn("%d 节" % int(r.length), "%d" % int(r.length))
			var extra := ""
			if me:
				extra = _cn("吞 %d · 死 %d" % [int(r.kills), int(r.deaths)],
					"%dK·%dD" % [int(r.kills), int(r.deaths)])
			var len_w := PSTheme.measure_t(len_s, LEN_SZ, 0.36, true).x
			var ex_w := PSTheme.measure(extra, EXTRA_SZ).x if extra != "" else 0.0
			var total := len_w + (4.0 + ex_w if extra != "" else 0.0)
			var lx: float = cx - total * 0.5
			# 23/900 #f2fbff with the web's cyan text-shadow (16 px, .4).
			var f := PSTheme.tracked(0, true)
			draw_string_outline(f, Vector2(lx, ROWS_Y + 82.0), len_s,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, LEN_SZ, 8,
				Color(0.337, 0.910, 1.0, 0.14 * ra))
			draw_string(f, Vector2(lx, ROWS_Y + 82.0), len_s,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, LEN_SZ,
				Color(ROW_LEN_COL.r, ROW_LEN_COL.g, ROW_LEN_COL.b, ra))
			if extra != "":
				PSTheme.text(self, Vector2(lx + len_w + 4.0, ROWS_Y + 82.0), extra,
					EXTRA_SZ, Color(ROW_LEN_COL.r, ROW_LEN_COL.g, ROW_LEN_COL.b,
						0.52 * ra), false)
		i += 1


## 再来一局 (lime primary, r3 + 4 px bottom edge) and 返回模式选择 (cyan ghost),
## 206.81 x 54 at y 1018, with the remote hint on the same line (web layout).
func _draw_actions() -> void:
	var alpha := 1.0 if settled else 0.55
	var hint := _cn("← → 选择 · OK 确认", "LEFT/RIGHT · OK")
	var hint_w := PSTheme.measure(hint, HINT_SZ).x
	var total := BTN_W * 2.0 + BTN_GAP + 16.0 + hint_w
	var bx := _w * 0.5 - total * 0.5
	var r0 := Rect2(bx, BTN_Y, BTN_W, BTN_H)
	var r1 := Rect2(bx + BTN_W + BTN_GAP, BTN_Y, BTN_W, BTN_H)
	# ---- primary: 再来一局 ----
	if settled and focus == 0:
		draw_texture_rect(PSAssets.blob, r0.grow(24.0), false,
			Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, 0.10))
	draw_texture_rect(PSAssets.btn_lime, r0, false, Color(1, 1, 1, alpha))
	draw_rect(r0, Color(182.0 / 255.0, 1.0, 87.0 / 255.0, 0.70 * alpha), false, 1.0)
	draw_rect(Rect2(r0.position.x, r0.end.y - 4.0, r0.size.x, 4.0),
		Color(BTN_EDGE.r, BTN_EDGE.g, BTN_EDGE.b, alpha), true)
	var label0 := _cn("再来一局", "PLAY AGAIN")
	var lw0 := PSTheme.measure_t(label0, ACTION_SZ, 2.2, true).x
	var gx0 := r0.get_center().x - (30.0 + 10.0 + lw0) * 0.5
	var kc := Rect2(gx0, r0.get_center().y - 11.0, 30.0, 22.0)
	draw_style_box(_key_style, kc)
	PSTheme.text_tc(self, kc.get_center().x, kc.get_center().y + 4.0, "OK", 11,
		Color(7.0 / 255.0, 32.0 / 255.0, 12.0 / 255.0, alpha), 0.6, false, true)
	PSTheme.text_t(self, Vector2(gx0 + 40.0, r0.get_center().y + 8.0), label0,
		ACTION_SZ, Color(BTN_INK.r, BTN_INK.g, BTN_INK.b, alpha), 2.2, false, true)
	_btns.append([BTN_RETRY, r0])
	# ---- secondary: 返回模式选择 ----
	if settled and focus == 1:
		draw_texture_rect(PSAssets.blob, r1.grow(24.0), false,
			Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, 0.10))
	draw_texture_rect(PSAssets.btn_ghost, r1, false, Color(1, 1, 1, alpha))
	draw_style_box(_ghost_edge, r1)
	PSTheme.text_tc(self, r1.get_center().x, r1.get_center().y + 8.0,
		_cn("返回模式选择", "MODE SELECT"), ACTION_SZ,
		Color(223.0 / 255.0, 246.0 / 255.0, 1.0, alpha), 2.2, false, true)
	_btns.append([BTN_MENU, r1])
	# ---- focus chip: lime ring + 4 px lime bar on the selected key ----
	if settled:
		var fr: Rect2 = r0 if focus == 0 else r1
		draw_style_box(_focus_style, fr.grow(5.0))
		draw_rect(Rect2(fr.position.x - 1.0, fr.position.y + 9.0, 4.0,
			fr.size.y - 18.0), PSTheme.LIME, true)
	# ---- hint ----
	PSTheme.text(self, Vector2(r1.end.x + 16.0, r0.get_center().y + 6.0), hint,
		HINT_SZ, Color(190.0 / 255.0, 220.0 / 255.0, 238.0 / 255.0, 0.70 * alpha),
		false)


## 66 px top band (`result-top`): rgba(4,9,18,.86) fading out. Always present so
## the skip chip and the headline share one band, exactly like the web.
func _draw_top_band() -> void:
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(_w, 0),
		Vector2(_w, TOP_H), Vector2(0, TOP_H)]),
		PackedColorArray([Color(4.0 / 255.0, 9.0 / 255.0, 18.0 / 255.0, 0.86),
			Color(4.0 / 255.0, 9.0 / 255.0, 18.0 / 255.0, 0.86),
			Color(4.0 / 255.0, 9.0 / 255.0, 18.0 / 255.0, 0.0),
			Color(4.0 / 255.0, 9.0 / 255.0, 18.0 / 255.0, 0.0)]))


## Headline: 16 px lime dot, 36/900 rank line with a cyan glow, 15/700 stats.
## Hidden during the rise (web `stage-growing`), faded in after it.
func _draw_headline() -> void:
	if not settled:
		return
	var a := clampf((t - RISE_SEC) / TITLE_FADE, 0.0, 1.0)
	if a <= 0.0:
		return
	draw_circle(Vector2(31.5, 27.5), 8.0,
		Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, 0.60 * a))
	var title := _title_text()
	var stats := _stats_text()
	var stats_w := PSTheme.measure(stats, STATS_SZ).x if stats != "" else 0.0
	var max_tw := _w - 52.0 - 24.0 - (stats_w + 14.0 if stats != "" else 0.0)
	var tsize := PSTheme.fit_size(title, TITLE_SZ, max_tw, 24)
	# The web's title is crisp white with a soft cyan 30 px text-shadow; a single
	# 12 px cyan outline at .07 is the closest GPU-cheap equivalent (two draws and
	# no dark sticker ring around the glyphs). Baseline 42 puts the CJK ink at the
	# reference's y 12..46 (`#resultTitle` box 7.3..48.7 at 36/900).
	var f := PSTheme.tracked(1, true)
	draw_string_outline(f, Vector2(52.0, 42.0), title, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, tsize, 12, Color(PSTheme.CYAN.r, PSTheme.CYAN.g, PSTheme.CYAN.b, 0.07 * a))
	draw_string(f, Vector2(52.0, 42.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, tsize,
		Color(TITLE_COL.r, TITLE_COL.g, TITLE_COL.b, a))
	if stats != "":
		var tw := PSTheme.measure_t(title, tsize, 1.0, true).x
		PSTheme.text(self, Vector2(52.0 + tw + 14.0, 38.0), stats, STATS_SZ,
			Color(STATS_COL.r, STATS_COL.g, STATS_COL.b, STATS_COL.a * a), false)


func _title_text() -> String:
	if result == null:
		return ""
	var players: Array = result.players
	if players.size() > 1:
		# Web 2P headline: `1P 第 2 名 · 2P 第 1 名 · 2P 获胜！`
		var parts := PackedStringArray()
		var champ := ""
		for m in players:
			parts.append(_cn("%s 第 %d 名" % [String(m.name), int(m.rank)],
				"%s #%d" % [String(m.name), int(m.rank)]))
			if int(m.rank) == 1:
				champ = String(m.name)
		var out := ""
		for k in parts.size():
			if k > 0:
				out += _cn(" · ", " / ")
			out += parts[k]
		if champ != "":
			out += _cn(" · %s 获胜！" % champ, " · %s WINS!" % champ)
		return out
	if won:
		return _cn("第 %d 名 · 本局获胜！" % player_rank,
			"RANK %d · ROUND WON!" % player_rank)
	return _cn("第 %d 名" % player_rank, "RANK %d" % player_rank)


func _stats_text() -> String:
	if result == null:
		return ""
	var players: Array = result.players
	if players.size() > 1:
		# Web 2P stats: per-player peaks, no personal best.
		var out := ""
		var k := 0
		for m in players:
			if k > 0:
				out += _cn(" · ", " / ")
			out += _cn("%s 最长 %d 节" % [String(m.name), int(m.peak_length)],
				"%s peak %d" % [String(m.name), int(m.peak_length)])
			k += 1
		return out
	var me = result.player
	if me == null:
		return ""
	var peak := int(me.peak_length)
	var best := maxi(int(result.best_length), peak)
	if best > peak:
		return _cn("最长 %d 节 · 历史最长 %d 节" % [peak, best],
			"peak %d · best %d" % [peak, best])
	return _cn("最长 %d 节" % peak, "peak %d" % peak)


## `#skipStageBtn`: the web's own skip affordance, shown only during the rise.
## Remote only — OK/BACK anywhere on the stage skips, so it is a label.
func _draw_skip() -> void:
	var r := Rect2(_w - SKIP_RIGHT, SKIP_Y, SKIP_W, SKIP_H)
	draw_style_box(_skip_style, r)
	var kc := Rect2(r.position.x + 15.0, r.position.y + 12.0, 26.0, 22.0)
	draw_style_box(_key_style, kc)
	PSTheme.text_tc(self, kc.get_center().x, kc.get_center().y + 4.0, "OK", 10,
		Color(4.0 / 255.0, 16.0 / 255.0, 28.0 / 255.0), 0.5, false, true)
	PSTheme.text_t(self, Vector2(kc.end.x + 8.0, r.get_center().y + 5.0),
		_cn("跳过演出 ›", "SKIP ›"), SKIP_SZ,
		Color(223.0 / 255.0, 246.0 / 255.0, 1.0), 1.04, false, true)
