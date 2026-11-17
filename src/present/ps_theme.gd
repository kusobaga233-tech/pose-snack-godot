extends RefCounted
## Workstream C — shared look: palette, CJK font, text/panel helpers, ribbon builder.
##
## Everything the presentation draws goes through here so the world, the HUD and
## the settlement stage cannot drift apart. All helpers are static: no instance
## state, no per-frame allocation, and the font/style objects are cached once.

# --------------------------------------------------------------- palette
const BG_TOP := Color("081226")
const BG_MID := Color("060D1C")
const BG_BOT := Color("040914")

const LIME := Color("B6FF57")
const LIME_SOFT := Color("B8FF6B")
const MINT := Color("5BEFA0")
const TEAL := Color("2FD6C8")
const CYAN := Color("56E8FF")
const CYAN_DEEP := Color("1FA8D8")
const PINK := Color("FF4D9D")
const GOLD := Color("FFC53D")
const GOLD_LIGHT := Color("FFE066")
const DANGER := Color("FF3C6E")
const VIOLET := Color("9D6BFF")

## READY screen slot accents: the 1024 reference project's P1 coral / P2 violet,
## reused verbatim because they read on this dark palette and match the reference
## instant-recognition cue (player 1 warm, player 2 cool).
const SLOT_1 := Color("E03C14")
const SLOT_2 := Color("8417A0")
## Green "ready" stamp.
const CHECK := Color("3BE38B")

const TEXT := Color("EAF4FF")
const TEXT_SOFT := Color("C7D8EE")
const MUTED := Color("93A7C4")
const MUTED_DARK := Color("5F7291")
const INK := Color("050810")

const PANEL_BG := Color(0.045, 0.075, 0.13, 0.84)
const PANEL_BG_SOFT := Color(0.055, 0.09, 0.155, 0.62)
## Chrome stroke. The shipped web skin has exactly one border colour family:
## cyan `#56e8ff` at .34 (solid edges) / .15 (soft inner dividers) / .55 (the
## mirror-box frame), plus the lime `#b6ff57` accent edge. The old steel-blue
## `rgba(89,133,184,.28)` was the purple glass layer and is gone (see
## Docs/WEB-COMPUTED-STYLES.md §1 `--tv-line` / `--tv-line-soft`).
const PANEL_BORDER := Color(0.337, 0.910, 1.0, 0.34)
const PANEL_BORDER_HI := Color(0.337, 0.910, 1.0, 0.55)
const CHIP_BG := Color(0.05, 0.08, 0.14, 0.78)

# ------------------------------------------------------- TV-skin tokens
## Verbatim `--tv-*` custom properties measured on the running web build at
## 1920x1080 (`Docs/WEB-COMPUTED-STYLES.md` §1). Use these instead of mixing
## new colours: the whole skin is this token set.
const TV_TEXT := Color("EAF6FF")            ## --tv-text
const TV_DIM := Color(0.745, 0.839, 0.933, 0.62)   ## --tv-dim
const TV_GOLD := Color("FFD54A")            ## --tv-gold
const TV_DEEP := Color("060C18")            ## --tv-deep
const TV_LINE := Color(0.337, 0.910, 1.0, 0.34)    ## --tv-line
const TV_LINE_SOFT := Color(0.337, 0.910, 1.0, 0.15)  ## --tv-line-soft
const TV_PANEL := Color(7.0 / 255.0, 15.0 / 255.0, 28.0 / 255.0, 0.94)  ## --tv-panel
## HUD band 3-stop vertical gradient (`#uiBar` background layer 3).
const BAND_TOP := Color(12.0 / 255.0, 29.0 / 255.0, 48.0 / 255.0)
const BAND_MID := Color(9.0 / 255.0, 21.0 / 255.0, 36.0 / 255.0)
const BAND_BOT := Color(5.0 / 255.0, 12.0 / 255.0, 22.0 / 255.0)
## Bottom-seam highlight (`#uiBar .ui-seam` uses rgb(230,251,255) at 50%).
const SEAM_HI := Color(230.0 / 255.0, 251.0 / 255.0, 1.0)
## Clock digits / stat values.
const CLOCK_DIGITS := Color(215.0 / 255.0, 247.0 / 255.0, 1.0)
## Muted cell labels (`#hud .stat .k` computed rgba(198,232,248,.82)).
const LABEL_DIM := Color(198.0 / 255.0, 232.0 / 255.0, 248.0 / 255.0, 0.82)
const TOTAL_DIM := Color(190.0 / 255.0, 225.0 / 255.0, 240.0 / 255.0, 0.62)
## Rank numeral while falling / rising (`#rank` computed colour).
const RANK_DOWN := Color(1.0, 154.0 / 255.0, 114.0 / 255.0)
const RANK_UP := Color("B6FF57")
## Header/score colours the pause + title layers use.
const BODY_TEXT := Color(0.937, 0.984, 1.0)          ## rgb(239,251,255)-ish
const KICKER := Color(0.337, 0.910, 1.0)             ## pause kicker cyan

# ------------------------------------------------------------ radius scale
## The shipped skin uses **four radii and nothing else** (WEB-COMPUTED-STYLES
## §6.5): 4 = panels / menus / pause strip / accent cells, 3 = chips / cards /
## rows / buttons, 2 = meta badges, 0 = HUD band / buff bars / result rows.
## Nothing above 4 except `50%` dots. The old 10.5-26 px card look is gone.
const R_PANEL := 4
const R_CARD := 3
const R_BADGE := 2
const R_NONE := 0

## Font families tried in order; the first that carries CJK wins.
const FONT_NAMES := [
	"Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC",
	"Source Han Sans SC", "PingFang SC", "Droid Sans Fallback", "WenQuanYi Zen Hei",
	"sans-serif",
]

## Absolute system font files tried on Android after the family lookup fails.
## `SystemFont.font_names` matches *family* names, and this box's Chinese face is
## shipped as a `.ttc` whose family name does not match any of FONT_NAMES, so the
## shaper ends up with Roboto and renders Chinese as missing glyphs.
const ANDROID_FONT_FILES := [
	"/system/fonts/NotoSansCJK-Regular.ttc",
	"/system/fonts/NotoSansSC-Regular.otf",
	"/system/fonts/NotoSansSC-Regular.ttf",
	"/system/fonts/DroidSansFallback.ttf",
	"/system/fonts/DroidSansFallbackFull.ttf",
]

static var _font: Font = null
static var _font_bold: Font = null
static var _cjk_ok: bool = false
static var _style_cache: Dictionary = {}


# ------------------------------------------------------------------ font

## UI font (CJK capable on Windows and Android). Falls back to the engine font,
## which has no Chinese glyphs — callers use `cjk_ok()` to swap to ASCII labels.
static func font() -> Font:
	if _font == null:
		_font = _make_system_font(700)
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = _make_system_font(900)
		if _font_bold == null:
			_font_bold = font()
	return _font_bold


static func _make_system_font(weight: int) -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(FONT_NAMES)
	sf.font_weight = weight
	sf.font_italic = false
	# `has_char` forces the system font to resolve; on a box without any CJK font
	# this returns false and the caller falls back to the engine font.
	if sf.has_char(0x5206) and sf.has_char(0x6570):
		_cjk_ok = true
		return sf

	# Android ships its Chinese face as a file whose family name the lookup above
	# does not match, so load the file itself before giving up on Chinese.
	if OS.has_feature("android"):
		var direct := _load_font_file(weight)
		if direct != null:
			_cjk_ok = true
			return direct

	if _cjk_ok:
		return sf
	return null


## Loads the first usable system CJK font file (Android). Returns null when none
## of the candidate paths exist or carries the glyphs we need.
static func _load_font_file(weight: int) -> Font:
	for path in ANDROID_FONT_FILES:
		if not FileAccess.file_exists(path):
			continue
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) != OK:
			continue
		ff.font_weight = weight
		if ff.has_char(0x5206) and ff.has_char(0x6570):
			print("[font] loaded CJK face from %s" % path)
			return ff
	return null


static func cjk_ok() -> bool:
	if _font == null:
		font()
	return _cjk_ok


# ------------------------------------------------------------------ text

## Draw a string at `pos` (baseline, left aligned) with a dark outline so it
## stays readable over the arena.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color,
		outline: bool = true) -> void:
	if s.is_empty():
		return
	var f := font()
	if outline:
		var ow := maxi(2, int(float(size) * 0.16))
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, ow,
			Color(0.02, 0.03, 0.06, 0.82 * col.a))
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


## Centred variant: `cx` is the horizontal centre, `y` the baseline.
static func text_c(ci: CanvasItem, cx: float, y: float, s: String, size: int, col: Color,
		outline: bool = true) -> void:
	if s.is_empty():
		return
	var f := font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	text(ci, Vector2(cx - w * 0.5, y), s, size, col, outline)


## Vertically centred in `cy` (caps-height approximation, plenty for HUD work).
static func text_vc(ci: CanvasItem, x: float, cy: float, s: String, size: int, col: Color,
		outline: bool = true) -> void:
	text(ci, Vector2(x, cy + float(size) * 0.35), s, size, col, outline)


static func text_vcc(ci: CanvasItem, cx: float, cy: float, s: String, size: int, col: Color,
		outline: bool = true) -> void:
	text_c(ci, cx, cy + float(size) * 0.35, s, size, col, outline)


## Right-aligned text (`x` is the right edge).
static func text_r(ci: CanvasItem, x: float, y: float, s: String, size: int, col: Color,
		outline: bool = true) -> void:
	if s.is_empty():
		return
	var f := font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	text(ci, Vector2(x - w, y), s, size, col, outline)


static func measure(s: String, size: int) -> Vector2:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)


# -------------------------------------------------------- letter-spacing
## CSS `letter-spacing` (`.24em`–`.32em` all over the web HUD) as Godot text.
##
## `draw_string` has no tracking argument, and the naive fix — a `draw_char`
## loop with a manual advance — costs **one draw call per glyph**, which the
## band's budget (labels + clock + rank, every frame) cannot pay. A cached
## `FontVariation` with `TextServer.SPACING_GLYPH` gets the identical extra
## advance from the shaper and stays **one** `draw_string`, so every tracked
## label below is a single draw call. TextServer takes an int px value, which is
## what the CSS numbers round to at this scale (10.08 -> 10, 8.64 -> 9, 2.4 -> 2).
static var _track_cache: Dictionary = {}
static var _track_bold_cache: Dictionary = {}


static func tracked(px: int, bold: bool = false) -> Font:
	var cache := _track_bold_cache if bold else _track_cache
	if cache.has(px):
		return cache[px]
	var fv := FontVariation.new()
	fv.base_font = font_bold() if bold else font()
	fv.set_spacing(TextServer.SPACING_GLYPH, px)
	cache[px] = fv
	return fv


## Tracked string at `pos` (baseline, left aligned). `bold` selects the 900-weight
## face (the web's clock / rank / stat values); labels use the 700 face.
static func text_t(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color,
		track: float, outline: bool = false, bold: bool = false) -> void:
	if s.is_empty():
		return
	var f := tracked(int(round(track)), bold)
	if outline:
		var ow := maxi(2, int(float(size) * 0.16))
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, ow,
			Color(0.02, 0.03, 0.06, 0.82 * col.a))
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


## Tracked, centred on `cx` (baseline `y`).
static func text_tc(ci: CanvasItem, cx: float, y: float, s: String, size: int, col: Color,
		track: float, outline: bool = false, bold: bool = false) -> void:
	if s.is_empty():
		return
	var w := measure_t(s, size, track, bold).x
	text_t(ci, Vector2(cx - w * 0.5, y), s, size, col, track, outline, bold)


## Tracked, right aligned (`x` is the right edge of the advance box).
static func text_tr(ci: CanvasItem, x: float, y: float, s: String, size: int, col: Color,
		track: float, outline: bool = false, bold: bool = false) -> void:
	if s.is_empty():
		return
	var w := measure_t(s, size, track, bold).x
	text_t(ci, Vector2(x - w, y), s, size, col, track, outline, bold)


static func measure_t(s: String, size: int, track: float, bold: bool = false) -> Vector2:
	return tracked(int(round(track)), bold).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		size)


# ------------------------------------------------------------ CJK fit guard
## TV legibility pass: every fixed-width label asks for the largest size that fits
## its box instead of overflowing it. The measurement uses the SAME font the draw
## call uses (`font()`, i.e. NotoSansCJK on the box when `cjk_ok()`), so a CJK run
## is measured at its real advance width, not at an ASCII estimate.
##
## Cached per (string, size, box width): the per-frame cost is one Dictionary
## lookup, never a re-shape. The first time a string has to shrink it prints ONE
## line, so a `--capture-flow` run lists every tight string for the owner:
##     [ui] text fit: "站到镜头前约 2 米…" 32 -> 28 px (box 716 px)
static var _fit_cache: Dictionary = {}


static func fit_size(s: String, size: int, max_w: float, floor_px: int = 18,
		track: float = 0.0) -> int:
	if s.is_empty() or max_w <= 0.0:
		return size
	var key := "%d|%d|%d|%s" % [size, int(round(track * 100.0)), int(round(max_w)), s]
	var hit: Variant = _fit_cache.get(key)
	if hit != null:
		return int(hit)
	var out := size
	while out > floor_px and measure_t(s, out, track).x > max_w:
		out -= 2
	out = maxi(out, floor_px)
	_fit_cache[key] = out
	if out != size:
		print("[ui] text fit: \"%s\" %d -> %d px (box %.0f px)" % [s, size, out, max_w])
	return out


## Centred line that shrinks only as far as it must to fit `max_w`.
static func text_c_fit(ci: CanvasItem, cx: float, y: float, s: String, size: int, col: Color,
		max_w: float, floor_px: int = 18, outline: bool = true) -> void:
	if s.is_empty():
		return
	text_c(ci, cx, y, s, fit_size(s, size, max_w, floor_px), col, outline)


## Tracked, centred variant of `text_c_fit`.
static func text_tc_fit(ci: CanvasItem, cx: float, y: float, s: String, size: int, col: Color,
		track: float, max_w: float, floor_px: int = 18, outline: bool = false) -> void:
	if s.is_empty():
		return
	var sz := fit_size(s, size, max_w, floor_px, track)
	text_tc(ci, cx, y, s, sz, col, track, outline)


## Two-stop CSS `text-shadow` glow. The web clock is
## `rgba(cyan,.62) 0 0 38px, rgba(cyan,.85) 0 0 10px`; a `draw_string_outline`
## pass is a dilated copy of the glyph run, so two of them (wide + tight, low
## alpha) read as that halo for two extra draw calls and no render target.
static func glow_t(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color,
		glow: Color, track: float = 0.0, w1: int = 40, a1: float = 0.16,
		w2: int = 12, a2: float = 0.30, bold: bool = true) -> void:
	if s.is_empty():
		return
	var f := tracked(int(round(track)), bold)
	if a1 > 0.0:
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, w1,
			Color(glow.r, glow.g, glow.b, glow.a * a1))
	if a2 > 0.0:
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, w2,
			Color(glow.r, glow.g, glow.b, glow.a * a2))
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, col)


## Centred variant of `glow_t`.
static func glow_tc(ci: CanvasItem, cx: float, y: float, s: String, size: int, col: Color,
		glow: Color, track: float = 0.0, w1: int = 40, a1: float = 0.16,
		w2: int = 12, a2: float = 0.30, bold: bool = true) -> void:
	var w := measure_t(s, size, track, bold).x
	glow_t(ci, Vector2(cx - w * 0.5, y), s, size, col, glow, track, w1, a1, w2, a2, bold)


## Right-aligned variant of `glow_t`.
static func glow_tr(ci: CanvasItem, x: float, y: float, s: String, size: int, col: Color,
		glow: Color, track: float = 0.0, w1: int = 40, a1: float = 0.16,
		w2: int = 12, a2: float = 0.30, bold: bool = true) -> void:
	var w := measure_t(s, size, track, bold).x
	glow_t(ci, Vector2(x - w, y), s, size, col, glow, track, w1, a1, w2, a2, bold)


## Per-glyph colour ramp (the web `#panelTitle` is a 100deg
## `rgb(234,255,208) -> rgb(182,255,87) 40% -> rgb(86,232,255)` text fill). Godot
## cannot gradient-fill a string, so the title's few glyphs are drawn one at a
## time with a colour sampled along the run — the only place a per-glyph loop is
## affordable, and it also carries the title's `letter-spacing` (2.32 px).
static func text_grad_c(ci: CanvasItem, cx: float, baseline: float, s: String, size: int,
		c0: Color, c1: Color, c2: Color, track: float) -> void:
	if s.is_empty():
		return
	var f := tracked(int(round(track)))
	var total := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var x := cx - total * 0.5
	var n := s.length()
	for i in n:
		var t := float(i) / maxf(1.0, float(n - 1))
		var c: Color
		if t < 0.4:
			c = c0.lerp(c1, t / 0.4)
		else:
			c = c1.lerp(c2, (t - 0.4) / 0.6)
		var ch := s.substr(i, 1)
		ci.draw_string(f, Vector2(x, baseline), ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, c)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x


# ---------------------------------------------------------------- panels

## Cached StyleBoxFlat: one `draw_style_box` per panel instead of a pile of rects.
static func panel(bg: Color, border: Color, radius: int, border_w: int = 1,
		shadow: int = 0, key: String = "") -> StyleBoxFlat:
	if key != "" and _style_cache.has(key):
		return _style_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 6
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	if shadow > 0:
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 5)
	if key != "":
		_style_cache[key] = sb
	return sb


static func bar_style(bg: Color, radius: int = 3, key: String = "") -> StyleBoxFlat:
	return panel(bg, Color(0, 0, 0, 0), radius, 0, 0, key)


# --------------------------------------------------------------- helpers

static func with_a(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


static func lighten(c: Color, amount: float) -> Color:
	return Color(
		c.r + (1.0 - c.r) * amount,
		c.g + (1.0 - c.g) * amount,
		c.b + (1.0 - c.b) * amount,
		c.a)


static func darken(c: Color, amount: float) -> Color:
	return Color(c.r * (1.0 - amount), c.g * (1.0 - amount), c.b * (1.0 - amount), c.a)


## Four-stop colour ramp sampled into 16 entries (what the snake ribbons use).
static func ramp4(c0: Color, c1: Color, c2: Color, c3: Color) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(16)
	for i in 16:
		var t := float(i) / 15.0
		var c: Color
		if t < 0.35:
			c = c0.lerp(c1, t / 0.35)
		elif t < 0.75:
			c = c1.lerp(c2, (t - 0.35) / 0.40)
		else:
			c = c2.lerp(c3, (t - 0.75) / 0.25)
		out[i] = c
	return out


static func ramp3(c0: Color, c1: Color, c2: Color) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(16)
	for i in 16:
		var t := float(i) / 15.0
		var c: Color = c0.lerp(c1, t * 2.0) if t < 0.5 else c1.lerp(c2, (t - 0.5) * 2.0)
		out[i] = c
	return out


# ------------------------------------------------------- ribbon geometry

## Append one tapered ribbon (the snake body / stage column) to triangle buffers.
## `ramp` holds 16 colours, `r_head`/`r_tail` are half-widths in destination units.
static func band_append(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, pts: PackedVector2Array, ramp: PackedColorArray,
		r_head: float, r_tail: float, alpha_mul: float, taper_pow: float = 2.0) -> void:
	var n := pts.size()
	if n < 2 or n * 2 + verts.size() > 65000 or (n - 1) * 6 + idx.size() > 65000:
		return
	var base := verts.size()
	verts.resize(base + n * 2)
	cols.resize(base + n * 2)
	var inv := 1.0 / float(n - 1)
	var last := n - 1
	for i in n:
		var p := pts[i]
		var pa := pts[maxi(i - 1, 0)]
		var pb := pts[mini(i + 1, last)]
		var dx := pb.x - pa.x
		var dy := pb.y - pa.y
		var d := sqrt(dx * dx + dy * dy)
		if d < 1e-4:
			d = 1.0
		var nx := -dy / d
		var ny := dx / d
		var t := float(i) * inv
		var hw := r_head + (r_tail - r_head) * pow(t, taper_pow)
		var c := ramp[mini(int(t * 15.0), 15)]
		c.a = c.a * alpha_mul
		verts[base + i * 2] = Vector2(p.x + nx * hw, p.y + ny * hw)
		verts[base + i * 2 + 1] = Vector2(p.x - nx * hw, p.y - ny * hw)
		cols[base + i * 2] = c
		cols[base + i * 2 + 1] = c
	var ib := idx.size()
	idx.resize(ib + (n - 1) * 6)
	var k := ib
	for i in n - 1:
		var o := base + i * 2
		idx[k] = o
		idx[k + 1] = o + 1
		idx[k + 2] = o + 2
		idx[k + 3] = o + 1
		idx[k + 4] = o + 3
		idx[k + 5] = o + 2
		k += 6


## One draw call for everything `band_append`ed into the buffers.
static func band_flush(ci: CanvasItem, verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array) -> void:
	if idx.size() == 0:
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, verts, cols,
		PackedVector2Array(), PackedInt32Array(), PackedFloat32Array(), RID(), -1)


## A *ring* around the spine: two ribbons (one per side) between the inner and
## outer half-widths, so the interior (the body itself) is never painted.
##
## This is what an additive halo needs: the web's halo is a `lighter` stroke of
## `lineWidth 2R+30` painted *under* the opaque body, so only the `R..R+15` band is
## ever visible. Drawing the filled ribbon of that width *on top* would lighten
## the whole tube; drawing only the annulus gives the identical pixels.
static func band_ring_append(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, pts: PackedVector2Array, ramp: PackedColorArray,
		r_in_head: float, r_in_tail: float, r_out_head: float, r_out_tail: float,
		alpha_mul: float = 1.0, taper_pow: float = 2.0) -> void:
	var n := pts.size()
	if n < 2 or ramp.size() < 16:
		return
	if verts.size() + n * 16 + 40 > 65000 or idx.size() + n * 24 + 40 > 65000:
		return
	var inv := 1.0 / float(n - 1)
	var last := n - 1
	var s := 0
	while s < last:
		var pa: Vector2 = pts[s]
		var pb: Vector2 = pts[s + 1]
		var na := _pt_normal(pts, s)
		var nb := _pt_normal(pts, s + 1)
		var ta := float(s) * inv
		var tb := float(s + 1) * inv
		var ia := r_in_head + (r_in_tail - r_in_head) * pow(ta, taper_pow)
		var ib := r_in_head + (r_in_tail - r_in_head) * pow(tb, taper_pow)
		var oa := r_out_head + (r_out_tail - r_out_head) * pow(ta, taper_pow)
		var ob := r_out_head + (r_out_tail - r_out_head) * pow(tb, taper_pow)
		var ca: Color = ramp[mini(int(ta * 15.0), 15)]
		var cb: Color = ramp[mini(int(tb * 15.0), 15)]
		ca.a = ca.a * alpha_mul
		cb.a = cb.a * alpha_mul
		_quad(verts, cols, idx, pa + na * oa, pb + nb * ob, pa + na * ia, pb + nb * ib, ca, cb)
		_quad(verts, cols, idx, pa - na * oa, pb - nb * ob, pa - na * ia, pb - nb * ib, ca, cb)
		s += 1


# ------------------------------------------------ ordered snake body stack

## One snake body as an **ordered stack of opaque shapes**: the self-overlap fix.
##
## Why not one ribbon + one strip per layer? A single strip has no per-segment
## paint order, so where a snake crosses itself the later-drawn geometry depends on
## layer order, not on "who is closer to the head": the tail-side strip covered the
## head side, and the translucent layers stacked alpha in the overlap (a darker,
## doubled patch = the "see-through" look).
##
## So the body is walked **tail -> head** (`pts` is head -> tail) and every dense
## slice appends its whole layer stack in one go:
##
##     opaque under-fill -> gel fill -> core stripe -> aura -> sheen -> scale arc
##
## Consequences (all three matter):
##   * an overlap resolves like painted shapes: the part closer to the head is
##     appended later, so it covers the earlier (tailward) part;
##   * a translucent layer can never be doubled: the next slice's opaque under-fill
##     overwrites the pixel before any second translucent quad lands on it, and the
##     gel fill sits on that opaque under-fill, so the tube reads as jelly while a
##     self-overlap stays fully opaque;
##   * the rim is NOT part of this stack (see `band_rim_append`): a per-segment rim
##     quad has a straight end edge that slices across the previous segment's body
##     at every bend, which is what produced the dark hatch at every joint.
##
## The caller passes a **densified** polyline (`main` subdivides each simulated
## segment, up to 6 slices on a bend) plus one normal and one radius per point, so
## the offset outline is smooth instead of a chain of chords. Everything stays in
## the caller's triangle buffers: the whole field is still one `band_flush()`.
##
## `tube` options (absent/empty = the old flat body):
##   "under"    float  under-fill darken amount (0 = no under-fill, one opaque body)
##   "gel_a"    float  gel fill alpha over the under-fill (0 = off)
##   "gel_w"    float  gel half-width as a fraction of the body half-width
##   "lat"      float  lateral (top-lit / bottom-shaded) strength across the width
##   "core_a"   float  inner core stripe alpha (0 = off)
##   "core_mul" float  core half-width fraction of the body half-width
##   "core_w"   float  core tint toward white (0 = body colour)
##   "core_off" float  core offset along screen -Y, in body half-widths
##
## `lat` is what makes the body read as a cylinder: each lateral rail's colour is
## lightened by `dot(rail, screen-up)` and darkened on the opposite side, so a
## horizontal body gets a lit top edge and a shaded bottom edge for free.
## Set by `band_stack_append` when the call was rejected by the shared 65000
## vertex/index cap (the caller must flush the array and retry the same snake) and
## cleared when it appended. Static because the helper is static; the draw path is
## single-threaded, so there is exactly one reader right after each call.
static var last_capped := false


static func band_stack_append(
		verts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, nrm: PackedVector2Array, rad: PackedFloat32Array,
		ts: PackedFloat32Array, marks: PackedByteArray,
		ramp: PackedColorArray, tube: Dictionary,
		hi_col: Color, hi_mul: float, aura_col: Color, aura_mul: float,
		ridge_col: Color, hi_off_mul: float, arc_r_mul: float = 0.55,
		arc_w_mul: float = 0.2, arc_steps: int = 8, vis: Rect2 = Rect2()) -> bool:
	var n := pts.size()
	if n < 2 or ramp.size() < 16:
		return false
	if nrm.size() != n or rad.size() != n or ts.size() != n:
		return false
	# Worst case per slice: 1 under + 2 gel + 2 core + 2 aura + 1 sheen = 8 quads
	# (32 vertices) plus an 8-quad scale arc on a marked point.
	last_capped = false
	if verts.size() + n * 44 + 96 > 65000 or idx.size() + n * 66 + 144 > 65000:
		# One triangle array cannot hold the whole field: the caller flushes what
		# it has and retries this snake into the fresh array instead of silently
		# dropping it (which used to make the last snakes of a long field vanish).
		last_capped = true
		return false
	# ---- tube options (read once, not per segment) ----
	var t_under: float = float(tube.get("under", 0.0))
	var t_gel_a: float = float(tube.get("gel_a", 0.0))
	var t_gel_w: float = float(tube.get("gel_w", 0.92))
	var t_lat: float = float(tube.get("lat", 0.0))
	var t_core_a: float = float(tube.get("core_a", 0.0))
	var t_core_mul: float = float(tube.get("core_mul", 0.34))
	var t_core_w: float = float(tube.get("core_w", 0.62))
	var t_core_off: float = float(tube.get("core_off", -0.16))
	var tube_on: bool = t_under > 0.0 or t_gel_a > 0.0 or t_core_a > 0.0
	var last := n - 1
	# ---- tail cap ----
	# Appended FIRST, i.e. the earliest shape of the snake: the body strip that
	# follows covers its inner half and only the round end sticks out. The rim gets
	# its own, larger round cap in `band_rim_append`, so no rectangle end can
	# protrude past the rounded tip any more.
	if _slice_vis(pts[last], pts[last], vis):
		_disc_append(verts, cols, idx, pts[last], rad[last],
			_dark(ramp[15], t_under) if tube_on else ramp[15], 12)
	# lateral rails: u is the signed position across the body (-1 / +1 = the two
	# contour edges). Uneven widths give the light side more room, like a cylinder
	# whose highlight sits above the centre line.
	var rail := PackedFloat32Array([-1.0, -0.52, 0.16, 1.0])
	var aura_a2: Color = aura_col
	aura_a2.a = minf(1.0, aura_col.a * 1.27)
	var aura_m2: float = aura_mul * 0.565
	var s := n - 2
	while s >= 0:
		var pa: Vector2 = pts[s]
		var pb: Vector2 = pts[s + 1]
		if not _slice_vis(pa, pb, vis):
			s -= 1
			continue
		var na: Vector2 = nrm[s]
		var nb: Vector2 = nrm[s + 1]
		var hwa: float = rad[s]
		var hwb: float = rad[s + 1]
		var ta: float = ts[s]
		var tb: float = ts[s + 1]
		var ca: Color = ramp[mini(int(ta * 15.0), 15)]
		var cbb: Color = ramp[mini(int(tb * 15.0), 15)]
		# -- 1. opaque under-fill: resets the pixel for every layer below AND keeps
		#       a self-overlap opaque --
		if tube_on:
			_quad(verts, cols, idx, pa + na * hwa, pb + nb * hwb, pa - na * hwa,
				pb - nb * hwb, _dark(ca, t_under), _dark(cbb, t_under))
		else:
			_quad(verts, cols, idx, pa + na * hwa, pb + nb * hwb, pa - na * hwa,
				pb - nb * hwb, ca, cbb)
		# -- 2. translucent gel fill: narrower than the under-fill, so the darker
		#       under-fill shows as the tube's inner wall, and shaded across the
		#       width so the tube reads round instead of flat --
		if t_gel_a > 0.0:
			var ga := Color(ca.r, ca.g, ca.b, t_gel_a)
			var gb := Color(cbb.r, cbb.g, cbb.b, t_gel_a)
			var k := 0
			while k < 3:
				var u0: float = rail[k]
				var u1: float = rail[k + 1]
				var ha: float = hwa * t_gel_w
				var hb: float = hwb * t_gel_w
				_quad4(verts, cols, idx,
					pa + na * (ha * u0), pb + nb * (hb * u0),
					pa + na * (ha * u1), pb + nb * (hb * u1),
					_shade(ga, u0 * -na.y, t_lat), _shade(gb, u0 * -nb.y, t_lat),
					_shade(ga, u1 * -na.y, t_lat), _shade(gb, u1 * -nb.y, t_lat))
				k += 1
		# -- 3. inner bright core: the "light piped through the gel" stripe. Two
		#       bands (wide + faint, narrow + bright) give a soft edge for the
		#       price of one extra quad, still inside the ordered stack. --
		if t_core_a > 0.0:
			var off := Vector2(0.0, t_core_off * hwa)
			var c_out := Color(ca.r, ca.g, ca.b, t_core_a * 0.34)
			var c_out2 := Color(cbb.r, cbb.g, cbb.b, t_core_a * 0.34)
			var c_in := ca.lerp(Color(1.0, 1.0, 1.0), t_core_w)
			var c_in2 := cbb.lerp(Color(1.0, 1.0, 1.0), t_core_w)
			c_in.a = t_core_a
			c_in2.a = t_core_a
			var wo: float = hwa * t_core_mul * 1.55
			var wb: float = hwb * t_core_mul * 1.55
			var wi: float = hwa * t_core_mul
			var wj: float = hwb * t_core_mul
			_quad4(verts, cols, idx, pa + na * wo + off, pb + nb * wb + off,
				pa - na * wo + off, pb - nb * wb + off, c_out, c_out2, c_out, c_out2)
			_quad4(verts, cols, idx, pa + na * wi + off, pb + nb * wj + off,
				pa - na * wi + off, pb - nb * wj + off, c_in, c_in2, c_in, c_in2)
		# -- 4. translucent layers, inside the body and therefore never doubled --
		if aura_col.a > 0.0 and aura_mul > 0.0:
			_quad(verts, cols, idx, pa + na * (hwa * aura_mul), pb + nb * (hwb * aura_mul),
				pa - na * (hwa * aura_mul), pb - nb * (hwb * aura_mul), aura_col, aura_col)
			_quad(verts, cols, idx, pa + na * (hwa * aura_m2), pb + nb * (hwb * aura_m2),
				pa - na * (hwa * aura_m2), pb - nb * (hwb * aura_m2), aura_a2, aura_a2)
		if hi_col.a > 0.0 and hi_mul > 0.0:
			var hoff := Vector2(0.0, -hwa * hi_off_mul)
			_quad(verts, cols, idx, pa + na * (hwa * hi_mul) + hoff,
				pb + nb * (hwb * hi_mul) + hoff, pa - na * (hwa * hi_mul) + hoff,
				pb - nb * (hwb * hi_mul) + hoff, hi_col, hi_col)
		# -- 5. back scale arc on the marked slices (every 2nd simulated point) --
		if marks[s] != 0 and ridge_col.a > 0.0:
			var fade := sin(ta * PI * 0.9)
			if fade > 0.06:
				var d := pb - pa
				var dl := d.length()
				if dl > 1e-4:
					var ac := ridge_col
					ac.a = ridge_col.a * fade
					_arc_band(verts, cols, idx, pa, d / dl, hwa * arc_r_mul,
						hwa * arc_w_mul * 0.5, -PI * 0.6, PI * 0.6, arc_steps, ac)
		s -= 1
	return true


## Smooth offset **rim** (the dark band around the tube), with **round caps at both
## ends** and one band per snake.
##
## This is drawn *before* the body stack, so the body always paints over the rim's
## inner edge and the rim can never cut across it - the B2/B4-per-segment version
## had a straight end edge per segment, which sliced the previous segment's body at
## every bend (the dark hatch at each joint) and left a square flap past the tail.
## Because the band follows the caller's dense polyline and averaged normals, its
## outer edge is a smooth offset curve rather than a chain of chords.
static func band_rim_append(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, pts: PackedVector2Array, nrm: PackedVector2Array,
		rad: PackedFloat32Array, col: Color, width: float,
		cap_head: bool = true, cap_tail: bool = true, vis: Rect2 = Rect2(),
		feather: float = 1.0) -> void:
	var n := pts.size()
	if n < 2 or nrm.size() != n or rad.size() != n:
		return
	if verts.size() + n * 32 + 96 > 65000 or idx.size() + n * 48 + 144 > 65000:
		return
	# 1.2 px alpha feather on the outside edge: GL Compatibility cannot do 2D MSAA
	# (measured: 2D MSAA is not yet supported for GLES3), so the silhouette gets
	# a one-quad gradient instead of a hard step against the arena floor.
	# `feather = 0` disables it (the two extra quads per slice are half of the rim's
	# geometry, and the step is ~1 px at 1080p: the split-screen frame needs the
	# budget more than the 1 px edge).
	var feather_w := feather * maxf(0.8, width * 0.22)
	var cf := Color(col.r, col.g, col.b, col.a * 0.5)
	var cz := Color(col.r, col.g, col.b, 0.0)
	var i := 0
	while i < n - 1:
		var pa: Vector2 = pts[i]
		var pb: Vector2 = pts[i + 1]
		if not _slice_vis(pa, pb, vis):
			i += 1
			continue
		var na: Vector2 = nrm[i]
		var nb: Vector2 = nrm[i + 1]
		var oa: float = rad[i] + width
		var ob: float = rad[i + 1] + width
		# out-of-body ring only; the body stack below covers the inner edge
		_quad_io(verts, cols, idx, pa + na * oa, pb + nb * ob, pa + na * rad[i],
			pb + nb * rad[i + 1], col, col)
		_quad_io(verts, cols, idx, pa - na * oa, pb - nb * ob, pa - na * rad[i],
			pb - nb * rad[i + 1], col, col)
		if feather_w > 0.0:
			_quad_io(verts, cols, idx, pa + na * (oa + feather_w),
				pb + nb * (ob + feather_w), pa + na * oa, pb + nb * ob, cz, cf)
			_quad_io(verts, cols, idx, pa - na * (oa + feather_w),
				pb - nb * (ob + feather_w), pa - na * oa, pb - nb * ob, cz, cf)
		i += 1
	# Round caps: a disc whose radius is the local body radius + the rim width. The
	# body cap (tail) / the head disc (head) cover the inner part, so only the rim
	# ring shows - i.e. a real round cap instead of a rectangle end.
	if cap_head and _slice_vis(pts[0], pts[0], vis):
		_disc_append(verts, cols, idx, pts[0], rad[0] + width, col, 14)
	if cap_tail and _slice_vis(pts[n - 1], pts[n - 1], vis):
		_disc_append(verts, cols, idx, pts[n - 1], rad[n - 1] + width, col, 14)


## Per-point normals for the dense polyline: the average of the two adjacent
## directions (the standard smooth offset normal). A degenerate average (an exact
## 180 degree reversal) falls back to the incoming direction so a band can never
## collapse to a zero normal.
static func band_normals(pts: PackedVector2Array, out: PackedVector2Array) -> void:
	var n := pts.size()
	out.resize(n)
	if n < 2:
		return
	var i := 0
	while i < n:
		var d_in: Vector2 = _dir(pts[i - 1], pts[i]) if i > 0 else _dir(pts[0], pts[1])
		var d_out: Vector2 = _dir(pts[i], pts[i + 1]) if i < n - 1 else d_in
		var v := d_in + d_out
		if v.length_squared() < 1e-8:
			v = d_in
		out[i] = Vector2(-v.y, v.x).normalized()
		i += 1


static func _dir(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var l := d.length()
	return Vector2(1.0, 0.0) if l < 1e-5 else d / l


## A filled disc (triangle fan) - the round cap, and the tail end of the body.
static func _disc_append(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, centre: Vector2, radius: float, col: Color,
		steps: int = 12) -> void:
	if radius <= 0.0:
		return
	var base := verts.size()
	verts.resize(base + steps + 1)
	cols.resize(base + steps + 1)
	verts[base] = centre
	cols[base] = col
	var k := 0
	while k < steps:
		var a := TAU * float(k) / float(steps)
		verts[base + 1 + k] = centre + Vector2(cos(a), sin(a)) * radius
		cols[base + 1 + k] = col
		k += 1
	var ib := idx.size()
	idx.resize(ib + steps * 3)
	k = 0
	while k < steps:
		idx[ib + k * 3] = base
		idx[ib + k * 3 + 1] = base + 1 + k
		idx[ib + k * 3 + 2] = base + 1 + (k + 1) % steps
		k += 1


## One annulus sector: `a0..a1` measured from `dir` (the local +x axis), radius
## `radius`, band half-width `half_w`, approximated with `steps` quads.
static func _arc_band(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, c: Vector2, dir: Vector2, radius: float,
		half_w: float, a0: float, a1: float, steps: int, col: Color) -> void:
	var ri := radius - half_w
	var ro := radius + half_w
	var prev_c := cos(a0)
	var prev_s := sin(a0)
	for k in steps:
		var ang := a0 + (a1 - a0) * float(k + 1) / float(steps)
		var ca := cos(ang)
		var sa := sin(ang)
		var r0 := Vector2(dir.x * prev_c - dir.y * prev_s, dir.x * prev_s + dir.y * prev_c)
		var r1 := Vector2(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca)
		_quad(verts, cols, idx, c + r0 * ri, c + r1 * ri, c + r0 * ro, c + r1 * ro,
			col, col)
		prev_c = ca
		prev_s = sa


## Quad with one colour per vertex (`p0`..`p3` in the `_quad` order: two headward
## and two tailward vertices). Used by the gel rails and the core stripe, where the
## colour has to vary **across** the body as well as along it.
static func _quad4(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	var base := verts.size()
	verts.resize(base + 4)
	cols.resize(base + 4)
	verts[base] = p0
	verts[base + 1] = p1
	verts[base + 2] = p2
	verts[base + 3] = p3
	cols[base] = c0
	cols[base + 1] = c1
	cols[base + 2] = c2
	cols[base + 3] = c3
	var ib := idx.size()
	idx.resize(ib + 6)
	idx[ib] = base
	idx[ib + 1] = base + 1
	idx[ib + 2] = base + 2
	idx[ib + 3] = base + 1
	idx[ib + 4] = base + 3
	idx[ib + 5] = base + 2


## `_quad4` plus one UV per vertex (same winding / point order).
static func _quad4uv(verts: PackedVector2Array, cols: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array,
		p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c0: Color, c1: Color, c2: Color, c3: Color,
		u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2) -> void:
	var base := verts.size()
	verts.resize(base + 4)
	cols.resize(base + 4)
	uvs.resize(base + 4)
	verts[base] = p0
	verts[base + 1] = p1
	verts[base + 2] = p2
	verts[base + 3] = p3
	cols[base] = c0
	cols[base + 1] = c1
	cols[base + 2] = c2
	cols[base + 3] = c3
	uvs[base] = u0
	uvs[base + 1] = u1
	uvs[base + 2] = u2
	uvs[base + 3] = u3
	var ib := idx.size()
	idx.resize(ib + 6)
	idx[ib] = base
	idx[ib + 1] = base + 1
	idx[ib + 2] = base + 2
	idx[ib + 3] = base + 1
	idx[ib + 4] = base + 3
	idx[ib + 5] = base + 2


## One textured quad placed by an explicit basis: `origin` is the anchor, `ax`/`ay`
## the already-scaled local axes, `at` where the region's top-left goes **relative
## to `origin`** (atlas texel units) and `src` the region's atlas rect (its UVs and
## its size in texels). This is how a whole character head (base + eyes + mouth +
## decor) becomes four quads in one triangle array: every region shares the head's
## origin and rotation, only its offset and rect differ.
static func atlas_quad_append(verts: PackedVector2Array, cols: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array, tex_size: Vector2,
		origin: Vector2, ax: Vector2, ay: Vector2, at: Vector2, src: Rect2,
		col: Color) -> void:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0 or src.size.x <= 0.0 or src.size.y <= 0.0:
		return
	var w := src.size.x
	var h := src.size.y
	var u0 := src.position.x / tex_size.x
	var v0 := src.position.y / tex_size.y
	var u1 := src.end.x / tex_size.x
	var v1 := src.end.y / tex_size.y
	_quad4uv(verts, cols, uvs, idx,
		origin + ax * at.x + ay * at.y,
		origin + ax * (at.x + w) + ay * at.y,
		origin + ax * at.x + ay * (at.y + h),
		origin + ax * (at.x + w) + ay * (at.y + h),
		col, col, col, col,
		Vector2(u0, v0), Vector2(u1, v0), Vector2(u0, v1), Vector2(u1, v1))


## ---- off-screen slice clipping (owner priority: 帧数) ----------------------
## Every band appender takes an optional `vis` rect in **screen px**. A slice whose
## two endpoints are both outside it is skipped entirely: the vertices are never
## built, so a long snake that leaves the view costs only its visible part. The
## rect is expected to be the view grown by the band's own margin (a clipped slice
## is therefore always off-screen, so the picture is pixel-identical). Empty
## `Rect2()` = no clipping (the READY/HUD/settlement callers).
##
## Measured on the 8 x 240 stress leg: 11% of the body pixels are on screen, so the
## band pass drops from 13.0 ms to 2.4 ms per frame in 1P (and the same ratio in
## 2P) with no visual change. It also keeps the shared 65000-vertex array far below
## its cap, so no snake can be dropped any more.
static func _slice_vis(a: Vector2, b: Vector2, vis: Rect2) -> bool:
	if vis.size.x <= 0.0:
		return true
	return vis.has_point(a) or vis.has_point(b)


## The clip rect a caller should pass for a view: screen rect grown by `margin`.
static func vis_rect(view: Vector2, margin: float) -> Rect2:
	return Rect2(-margin, -margin, view.x + margin * 2.0, view.y + margin * 2.0)


## Textured tube: one **opaque** quad per dense slice, sampled from the
## character's body texture (`u` across the tube, `v` along it), walked
## tail -> head exactly like `band_stack_append` so a self-overlap still resolves
## as "the part closer to the head covers the earlier one".
##
## The pack's body art already carries its own gel shading, so the six procedural
## layers collapse into one textured quad: the vertex colour is only a gentle
## lateral shade (the tube still reads round) and the boost aura is an optional
## second, narrower quad. `v` is `1 - ts`, i.e. v=0 is the tail cap and v=1 the
## neck, which is the direction the pack's gradient runs.
## `tile_world` > 0 repeats the texture every `tile_world` destination units of arc
## length (`v` from the accumulated length, so the pattern never stretches);
## `tile_world` <= 0 maps the whole art once over the body (`v = 1 - ts`, the
## pack's own tail -> neck gradient).
static func band_tex_append(verts: PackedVector2Array, cols: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array,
		pts: PackedVector2Array, nrm: PackedVector2Array, rad: PackedFloat32Array,
		ts: PackedFloat32Array, shade: float, aura_col: Color, aura_mul: float,
		tile_world: float = 0.0, vis: Rect2 = Rect2()) -> void:
	var n := pts.size()
	if n < 2 or nrm.size() != n or rad.size() != n or ts.size() != n:
		return
	# 1 tube quad (4) + 1 aura quad (4) + the tail fan (14) per snake, plus slack.
	if verts.size() + n * 8 + 40 > 65000 or idx.size() + n * 12 + 60 > 65000:
		return
	var last := n - 1
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var tiled := tile_world > 1.0
	var acc := 0.0
	var inv_tile := 1.0 / tile_world if tiled else 0.0
	# ---- tail cap: a flat fan in the tube's tail-end colour, appended first so
	#      the slices after it paint over its inner half (the round tail tip).
	#      v=0 is the tail in both mappings, so the cap is always v=0. ----
	if _slice_vis(pts[last], pts[last], vis):
		_disc_uv_append(verts, cols, uvs, idx, pts[last], rad[last], white,
			Vector2(0.5, 0.0), 14)
	var s := n - 2
	while s >= 0:
		var pa: Vector2 = pts[s]
		var pb: Vector2 = pts[s + 1]
		var na: Vector2 = nrm[s]
		var nb: Vector2 = nrm[s + 1]
		var hwa: float = rad[s]
		var hwb: float = rad[s + 1]
		var va: float
		var vb: float
		if tiled:
			# walk tail -> head: v = arc length since the tail / tile length, so a
			# tile is always `tile_world` long on screen and the pattern cannot
			# stretch when the body grows
			vb = acc * inv_tile
			acc += pa.distance_to(pb)
			va = acc * inv_tile
		else:
			va = 1.0 - ts[s]
			vb = 1.0 - ts[s + 1]
		if _slice_vis(pa, pb, vis):
			_quad4uv(verts, cols, uvs, idx,
				pa + na * hwa, pb + nb * hwb, pa - na * hwa, pb - nb * hwb,
				_shade(white, -na.y, shade), _shade(white, -nb.y, shade),
				_shade(white, na.y, shade), _shade(white, nb.y, shade),
				Vector2(0.0, va), Vector2(0.0, vb), Vector2(1.0, va), Vector2(1.0, vb))
			if aura_col.a > 0.0 and aura_mul > 0.0:
				var aa: float = hwa * aura_mul
				var ab: float = hwb * aura_mul
				_quad4uv(verts, cols, uvs, idx,
					pa + na * aa, pb + nb * ab, pa - na * aa, pb - nb * ab,
					aura_col, aura_col, aura_col, aura_col,
					Vector2(0.0, va), Vector2(0.0, vb), Vector2(1.0, va), Vector2(1.0, vb))
		s -= 1


## Textured triangle fan with one constant UV (the tube's tail cap).
static func _disc_uv_append(verts: PackedVector2Array, cols: PackedColorArray,
		uvs: PackedVector2Array, idx: PackedInt32Array, centre: Vector2,
		radius: float, col: Color, uv: Vector2, steps: int) -> void:
	if radius <= 0.0:
		return
	var base := verts.size()
	verts.resize(base + steps + 1)
	cols.resize(base + steps + 1)
	uvs.resize(base + steps + 1)
	verts[base] = centre
	cols[base] = col
	uvs[base] = uv
	var k := 0
	while k < steps:
		var a := TAU * float(k) / float(steps)
		verts[base + 1 + k] = centre + Vector2(cos(a), sin(a)) * radius
		cols[base + 1 + k] = col
		uvs[base + 1 + k] = uv
		k += 1
	var ib := idx.size()
	idx.resize(ib + steps * 3)
	k = 0
	while k < steps:
		idx[ib + k * 3] = base
		idx[ib + k * 3 + 1] = base + 1 + k
		idx[ib + k * 3 + 2] = base + 1 + (k + 1) % steps
		k += 1


## One textured triangle array. `tex` may be any Texture2D (the body atlas, a
## character's head atlas); `ci` is the CanvasItem that owns the command.
static func flush_tex(ci: CanvasItem, verts: PackedVector2Array,
		cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array,
		tex: Texture2D) -> void:
	if idx.size() == 0 or tex == null:
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, verts,
		cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid(), -1)


## Cross-body shading for one vertex. `k` is `rail * up_dot` (-1 = the side facing
## screen-down, +1 = the side facing screen-up); the light side is lerped toward
## white by `k * amount`, the dark side multiplied down by `-k * amount * 0.85`.
## `k == 0` (a body running vertically) returns `base` untouched.
static func _shade(base: Color, k: float, amount: float) -> Color:
	if amount <= 0.0 or k == 0.0:
		return base
	if k > 0.0:
		var t := clampf(k, 0.0, 1.0) * amount
		return Color(base.r + (1.0 - base.r) * t, base.g + (1.0 - base.g) * t,
			base.b + (1.0 - base.b) * t, base.a)
	var t2 := clampf(-k, 0.0, 1.0) * amount * 0.85
	return Color(base.r * (1.0 - t2), base.g * (1.0 - t2), base.b * (1.0 - t2), base.a)


## Multiplicative darken that keeps the alpha (the tube's opaque under-fill).
static func _dark(base: Color, amount: float) -> Color:
	var m := 1.0 - clampf(amount, 0.0, 0.95)
	return Color(base.r * m, base.g * m, base.b * m, base.a)


## A ring around the spine with a **smooth lateral falloff**: one quad per dense
## slice whose inner edge carries `col_in` and whose outer edge carries `col_out`,
## so the alpha ramps across the band instead of stepping through concentric rings.
##
## This is the additive halo (the web's `lighter` stroke plus the body stroke's
## `shadowBlur 26`, which together measure ~.30 at the tube edge and ~.05 at
## +15 px). The interior is never painted, so the halo cannot tint its own body.
## Built on the dense polyline + averaged normals, so the band follows the tube
## smoothly; `pad_tail_mul` widens it toward the tail, where a gel tube's light
## pools.
static func band_halo_append(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, pts: PackedVector2Array, nrm: PackedVector2Array,
		rad: PackedFloat32Array, col_in: Color, col_out: Color, pad: float,
		pad_tail_mul: float = 1.0, vis: Rect2 = Rect2()) -> void:
	var n := pts.size()
	if n < 2 or nrm.size() != n or rad.size() != n:
		return
	if verts.size() + n * 16 + 40 > 65000 or idx.size() + n * 24 + 40 > 65000:
		return
	var inv := 1.0 / float(n - 1)
	var s := 0
	while s < n - 1:
		var pa: Vector2 = pts[s]
		var pb: Vector2 = pts[s + 1]
		if not _slice_vis(pa, pb, vis):
			s += 1
			continue
		var na: Vector2 = nrm[s]
		var nb: Vector2 = nrm[s + 1]
		var ia: float = rad[s]
		var ib: float = rad[s + 1]
		var pa_i := pad * (1.0 + (pad_tail_mul - 1.0) * float(s) * inv)
		var pb_i := pad * (1.0 + (pad_tail_mul - 1.0) * float(s + 1) * inv)
		_quad_io(verts, cols, idx, pa + na * (ia + pa_i), pb + nb * (ib + pb_i),
			pa + na * ia, pb + nb * ib, col_out, col_in)
		_quad_io(verts, cols, idx, pa - na * (ia + pa_i), pb - nb * (ib + pb_i),
			pa - na * ia, pb - nb * ib, col_out, col_in)
		s += 1


## Quad with an inner/outer colour split: `p0`,`p1` (outer edge) carry `c_out`,
## `p2`,`p3` (inner edge) carry `c_in`.
static func _quad_io(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c_out: Color, c_in: Color) -> void:
	var base := verts.size()
	verts.resize(base + 4)
	cols.resize(base + 4)
	verts[base] = p0
	verts[base + 1] = p1
	verts[base + 2] = p2
	verts[base + 3] = p3
	cols[base] = c_out
	cols[base + 1] = c_out
	cols[base + 2] = c_in
	cols[base + 3] = c_in
	var ib := idx.size()
	idx.resize(ib + 6)
	idx[ib] = base
	idx[ib + 1] = base + 1
	idx[ib + 2] = base + 2
	idx[ib + 3] = base + 1
	idx[ib + 4] = base + 3
	idx[ib + 5] = base + 2


## Averaged unit normal at `pts[i]` (same convention as `band_append`).
static func _pt_normal(pts: PackedVector2Array, i: int) -> Vector2:
	var n := pts.size()
	var pa := pts[maxi(i - 1, 0)]
	var pb := pts[mini(i + 1, n - 1)]
	var dx := pb.x - pa.x
	var dy := pb.y - pa.y
	var d := sqrt(dx * dx + dy * dy)
	if d < 1e-4:
		return Vector2(0.0, 0.0)
	return Vector2(-dy / d, dx / d)


## One quad (two triangles) with a colour per edge: `p0`,`p2` share `c_a`
## (headward edge), `p1`,`p3` share `c_b` (tailward edge).
static func _quad(verts: PackedVector2Array, cols: PackedColorArray,
		idx: PackedInt32Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		c_a: Color, c_b: Color) -> void:
	var base := verts.size()
	verts.resize(base + 4)
	cols.resize(base + 4)
	verts[base] = p0
	verts[base + 1] = p1
	verts[base + 2] = p2
	verts[base + 3] = p3
	cols[base] = c_a
	cols[base + 1] = c_b
	cols[base + 2] = c_a
	cols[base + 3] = c_b
	var ib := idx.size()
	idx.resize(ib + 6)
	idx[ib] = base
	idx[ib + 1] = base + 1
	idx[ib + 2] = base + 2
	idx[ib + 3] = base + 1
	idx[ib + 4] = base + 3
	idx[ib + 5] = base + 2
