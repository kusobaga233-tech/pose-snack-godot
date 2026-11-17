extends RefCounted
## Workstream C — every texture the presentation uses is rasterised **once** at
## load into ImageTextures. The per-frame path only ever calls
## `draw_texture_rect`, so no gradient / polygon / particle geometry is rebuilt
## per entity per frame (the WebView prototype died on ~8000 canvas ops/frame).
##
## `TEX_R` is the world-space radius a 160x160 sprite covers, so callers can size
## a draw rect with `tex_size(world_radius)` instead of guessing.

const PSTheme = preload("res://src/present/ps_theme.gd")

const TEX_SIZE := 160
const TEX_R := 80.0

const FOOD_COLORS := [
	Color("FF4D9D"), Color("FFD93D"), Color("5BC8FF"),
	Color("9D6BFF"), Color("4DEFA8"), Color("FF8A4D"),
]
const BIG_FOOD_COLOR := Color("FFC53D")
const BOOST_COLOR := Color("FFD93D")
const MAGNET_COLOR := Color("5BC8FF")

static var ready := false
## Food is drawn as **two baked layers** so the web's 5 face variants and its blink
## can share one palette set without 60 sprites:
##   `food_body[6]`  — glow + shaded jelly + ring + top highlight (per palette)
##   `food_face[10]` — white/ink eyes (open or shut) + the face's mouth, drawn on
##                     top of any body (palette independent)
## `big` food adds `crown` (a third, rotated layer) instead of a baked crown.
static var food_body: Array = []
static var food_face: Array = []
## Both food layers packed into **one texture**: `food_body[6]` then `food_face[10]`
## as a 4x4 grid of `TEX_SIZE` tiles with a transparent gutter, so every visible
## pellet is a textured quad in one triangle array (one draw call for the whole
## field) instead of two `draw_texture_rect` calls per pellet. Tiles are pixel
## copies of the two arrays above, and the gutter keeps bilinear sampling from
## ever touching a neighbouring tile, so the batched pixels are the old ones.
## `food_atlas_uv()` returns a tile's rect in UV space.
const FOOD_ATLAS_COLS := 4
const FOOD_ATLAS_GUT := 4
static var food_atlas: ImageTexture = null
static var _food_atlas_cell := 0
static var _food_atlas_dim := 0
static var food_big_body: Texture2D = null
static var crown: Texture2D = null
## Face order == the core's `_food_faces` array (`src/core/game.gd:181`).
const FOOD_FACES := [&"happy", &"wink", &"wide", &"tongue", &"sleepy"]
static var _face_index: Dictionary = {}
static var powerup: Array = []
static var powerup_ring: Texture2D = null
static var dot: Texture2D = null
static var spark: Texture2D = null
static var blob: Texture2D = null
static var grid: Texture2D = null
static var dash: Texture2D = null
static var bg_grad: Texture2D = null
static var wall_strip: Texture2D = null
static var grad_v: Texture2D = null
static var ring_thin: Texture2D = null

# ---- TV-skin chrome (band / OSD / title slab), all rasterised once ----------
## HUD band vertical gradient (rgb(12,29,48) -> rgb(9,21,36) 58% -> rgb(5,12,22)).
static var band_grad: Texture2D = null
## 52x26 tile: 1 px cyan grid line on each axis (`#uiBar` layers 1-2).
static var band_grid: Texture2D = null
## 8x4 tile: 1 px rgba(190,235,255,.024) line every 4 px (`#uiBar .ui-scan`).
static var band_scan: Texture2D = null
## Soft cyan spill above the seam (`box-shadow: cyan 0 0 22px`).
static var seam_glow: Texture2D = null
## `#uiBar .ui-energy i` horizontal white-hot sweep.
static var energy_grad: Texture2D = null
## 30x5 tile: 2 px cyan ruler tick (`#uiBar .ui-ruler`).
static var ruler: Texture2D = null
## `#hud` horizontal wash: cyan .1 -> cyan .01 62% -> cyan .1.
static var hud_grad: Texture2D = null
## `#rankBlock` lime wash, strongest at the right edge.
static var rank_grad: Texture2D = null
## `body::before` scanlines + `radial-gradient(46% -> 100% rgba(1,3,9,.62))`.
static var scanline: Texture2D = null
static var vignette: Texture2D = null
## Title slab `linear-gradient(155deg, rgba(9,20,36,.98), rgba(5,10,20,.99))`.
static var panel_grad: Texture2D = null
## Lime primary button gradient (startBtn / againBtn).
static var btn_lime: Texture2D = null
## Cyan ghost button gradient (kbBtn / secondary rows).
static var btn_ghost: Texture2D = null
## Mirror-box bottom read-out scrim (`#cam .cam-speed`).
static var cam_grad: Texture2D = null
## `#uiBar` drop shadow onto the arena (`rgba(0,0,0,.78) 0 20px 52px`).
static var band_shadow: Texture2D = null


# ------------------------------------------------------------------ build

static func build() -> void:
	if ready:
		return
	ready = true
	for i in FOOD_FACES.size():
		_face_index[FOOD_FACES[i]] = i
	_build_background()
	_build_food()
	_build_powerups()
	_build_particles()
	_build_ui_bits()


## Sprite edge length (in draw units) for a world radius covered by the texture.
static func size_for(world_radius: float) -> float:
	return world_radius * (float(TEX_SIZE) / TEX_R)


static func _new_img(size: int) -> Image:
	return Image.create(size, size, false, Image.FORMAT_RGBA8)


static func _tex_from(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------- background

static func _build_background() -> void:
	# Diagonal base gradient (#081226 -> #060D1C -> #040914), drawn once per frame
	# as a single stretched quad.
	var g := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var top := Color("081226")
	var mid := Color("060D1C")
	var bot := Color("040914")
	for y in 64:
		for x in 64:
			var t := clampf((float(x) * 0.42 + float(y) * 0.58) / 63.0, 0.0, 1.0)
			var c := top.lerp(mid, t * 1.6) if t < 0.62 else mid.lerp(bot, (t - 0.62) / 0.38)
			g.set_pixel(x, y, c)
	bg_grad = _tex_from(g)

	# 90x90 arena floor tile: the web's `buildPattern()` motif at its source
	# values (`render.js:56-67`): `rgba(120,220,255,0.075)` — a r=2.1 DOT plus a
	# 1x14 / 14x1 CROSS. Both at the same .075 alpha (the old bake used a gradient
	# dot at .075 and dimmer .055 arms, which is why the floor read "faint dotted
	# paper" instead of an arena). `grid_at()` re-bakes the same motif at the exact
	# screen tile size so the 1 px arms stay 1 px after the camera zoom.
	grid = _tex_from(_grid_image(90))

	# 32x2 dash, `setLineDash([14,18])` (render.js:119): 14 on / 18 off.
	var t3 := _new_img(32)
	for x in 32:
		for y in 2:
			if x < 14:
				t3.set_pixel(x, y, Color(1, 1, 1, 1))
	dash = _tex_from(t3)

	# 16x64 red falloff strip: the arena wall glow, stretched along the edge.
	var t4 := _new_img(64)
	for y in 64:
		var a := pow(1.0 - float(y) / 63.0, 2.1) * 0.85
		for x in 16:
			t4.set_pixel(x, y, Color(1.0, 0.28, 0.42, a))
	wall_strip = _tex_from(t4)

	# 4x64 white vertical gradient (settlement stage columns).
	var t5 := Image.create(4, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var a := 0.98 - pow(float(y) / 63.0, 1.4) * 0.55
		for x in 4:
			t5.set_pixel(x, y, Color(1, 1, 1, a))
	grad_v = _tex_from(t5)


## One arena floor tile at `px` texels per 90 design px.
##
## Values are the web's (`render.js:56-67`): a solid r=2.1 dot and a 1x14 / 14x1
## cross, both `rgba(120,220,255,0.075)`. The dot is *solid* (not a radial
## falloff) because the web fills a flat `#78DCFF` at .075 — the old gradient dot
## lost ~70% of its alpha outside the centre texel and read as haze.
static func _grid_image(px: int) -> Image:
	var img := _new_img(px)
	var c := float(px) * 0.5
	var k := float(px) / 90.0
	var dot_r := 2.1 * k
	var arm_half := 7.0 * k
	var arm_w := maxf(0.62, 0.5 * k)
	var col := Color(120.0 / 255.0, 220.0 / 255.0, 1.0)
	for y in px:
		var dy := float(y) + 0.5 - c
		for x in px:
			var dx := float(x) + 0.5 - c
			var a := 0.0
			var d := sqrt(dx * dx + dy * dy)
			if d < dot_r + 0.5:
				a = 0.075 * clampf(dot_r + 0.5 - d, 0.0, 1.0)
			if absf(dx) <= arm_w and absf(dy) <= arm_half:
				a = maxf(a, 0.075)
			if absf(dy) <= arm_w and absf(dx) <= arm_half:
				a = maxf(a, 0.075)
			if a > 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return img


## Screen-tile-sized variant of the floor pattern (cached: one entry per zoom).
## `px` is `round(90 * zoom)`, so the tile is blitted 1:1 and the 1 px arms stay
## 1 px crisp instead of being smeared by a 90 -> 88 (etc.) resample.
static var _grid_cache: Dictionary = {}
static func grid_at(px: int) -> Texture2D:
	px = clampi(px, 12, 190)
	if _grid_cache.has(px):
		return _grid_cache[px]
	var t := _tex_from(_grid_image(px))
	_grid_cache[px] = t
	return t


# ------------------------------------------------------------------ food

static func _build_food() -> void:
	var r := 24.0
	var imgs: Array = []
	for i in FOOD_COLORS.size():
		var bi := _food_body_image(FOOD_COLORS[i], r, FOOD_GLOW_A)
		imgs.append(bi)
		food_body.append(_tex_from(bi))
	food_big_body = _tex_from(_food_body_image(BIG_FOOD_COLOR, r * 1.22, FOOD_GLOW_A + 0.10))
	# 5 faces x (open eyes, shut eyes): the web's `drawFoodFace` switch, with the
	# blink state baked as a second variant (`blinkCycle > 3.0`, 0.2/3.2 = 6% of
	# the time, both eyes become arcs).
	for face in FOOD_FACES.size():
		for shut in 2:
			var fi := _food_face_image(face, shut == 1, r)
			imgs.append(fi)
			food_face.append(_tex_from(fi))
	crown = _tex_from(_crown_image(r))
	_build_food_atlas(imgs)


## Pack `imgs` (6 bodies then 10 faces) into `food_atlas`; tile order is the
## drawing code's: body palette i -> tile i, face variant v -> tile 6 + v.
static func _build_food_atlas(imgs: Array) -> void:
	_food_atlas_cell = TEX_SIZE + FOOD_ATLAS_GUT * 2
	var cols := FOOD_ATLAS_COLS
	var rows := int(ceil(float(imgs.size()) / float(cols)))
	_food_atlas_dim = _food_atlas_cell * cols
	var img := Image.create(_food_atlas_dim, _food_atlas_cell * rows, false,
		Image.FORMAT_RGBA8)
	var src_rect := Rect2i(0, 0, TEX_SIZE, TEX_SIZE)
	for i in imgs.size():
		var cx := (i % cols) * _food_atlas_cell + FOOD_ATLAS_GUT
		var cy := (i / cols) * _food_atlas_cell + FOOD_ATLAS_GUT
		img.blit_rect(imgs[i], src_rect, Vector2i(cx, cy))
	food_atlas = ImageTexture.create_from_image(img)


## UV rect of one food-atlas tile (see `FOOD_ATLAS_COLS`).
static func food_atlas_uv(tile: int) -> Rect2:
	var cx := (tile % FOOD_ATLAS_COLS) * _food_atlas_cell + FOOD_ATLAS_GUT
	var cy := (tile / FOOD_ATLAS_COLS) * _food_atlas_cell + FOOD_ATLAS_GUT
	var d := float(_food_atlas_dim)
	return Rect2(float(cx) / d, float(cy) / d, float(TEX_SIZE) / d, float(TEX_SIZE) / d)


## Face-variant index for a core `Food.face` key (0 = happy, unknown -> 0).
static func face_index(face_key: StringName) -> int:
	return int(_face_index.get(face_key, 0))


## Jelly body only: outer glow + radial-shaded disc + 2.5 px contour + the
## specular blob. The face is a separate layer (`_food_face_image`).
##
## B4 glow: the halo is **3x the face radius** with a long soft tail, measured
## from the shipped web frame (a radial mean around an isolated pellet reads floor
## + ~.46 alpha-equivalent at the face edge, still ~.05 at 2.4x the face radius).
## The B2 bake stopped being perceptible at ~1.3x, which is the "food glow is too
## small" the owner reported. Still **one blit per pellet**: the glow is baked into
## the body tile of the food atlas, and the falloff is clamped so the biggest
## pellet cannot reach the tile edge (which would show a square cut).
const FOOD_GLOW_MUL := 3.0
const FOOD_GLOW_POW := 1.2
const FOOD_GLOW_A := 0.46

static func _food_body_image(col: Color, r: float, glow_a: float) -> Image:
	var img := _new_img(TEX_SIZE)
	var c := float(TEX_SIZE) * 0.5
	var glow_r := minf(r * FOOD_GLOW_MUL, c - 2.0)
	_glow(img, c, c, glow_r, col, glow_a, FOOD_GLOW_POW)
	_disc_shaded(img, c, c, r, PSTheme.lighten(col, 0.5), col, PSTheme.darken(col, 0.34))
	_ring(img, c, c, r, 2.5, Color(28.0 / 255.0, 10.0 / 255.0, 42.0 / 255.0, 0.5))
	_ellipse(img, c - r * 0.34, c - r * 0.42, r * 0.24, r * 0.15, Color(1, 1, 1, 0.6))
	return img


## Eyes + mouth only, on transparent: `render.js:drawFoodFace` verbatim, mapped
## onto the five core face keys. Palette independent, so every body can use it.
##
##   happy  both eyes open, smile arc
##   wink   left open / right shut, smile arc
##   wide   both open, filled gaping mouth + tongue (big food's face)
##   tongue both open, open arc + a tongue sticking out
##   sleepy both shut, wavy mouth
static func _food_face_image(face: int, blink: bool, r: float) -> Image:
	var img := _new_img(TEX_SIZE)
	var c := float(TEX_SIZE) * 0.5
	var ink := Color(27.0 / 255.0, 10.0 / 255.0, 42.0 / 255.0)
	var eye_x := r * 0.34
	var eye_y := c - r * 0.05
	var eye_r := r * 0.25
	var shut_l: bool = blink or face == 4
	var shut_r: bool = blink or face == 1 or face == 4
	_food_eye(img, c - eye_x, eye_y, eye_r, r, ink, shut_l)
	_food_eye(img, c + eye_x, eye_y, eye_r, r, ink, shut_r)
	var mouth_y := c + r * 0.44
	var lw := maxf(1.6, r * 0.09)
	if face == 2:
		_ellipse(img, c, mouth_y, r * 0.34, r * 0.26, Color(58.0 / 255.0, 10.0 / 255.0,
			32.0 / 255.0))
		_ellipse(img, c, mouth_y + r * 0.14, r * 0.2, r * 0.11, Color(1.0, 107.0 / 255.0,
			138.0 / 255.0))
	elif face == 3:
		_arc(img, c, mouth_y - r * 0.08, r * 0.3, PI * 0.15, PI * 0.85, lw, ink)
		_ellipse(img, c, mouth_y + r * 0.12, r * 0.16, r * 0.2, Color(1.0, 92.0 / 255.0,
			138.0 / 255.0))
	elif face == 4:
		# wavy mouth: two quadratic curves, approximated with two shallow arcs
		_arc(img, c - r * 0.11, mouth_y + r * 0.02, r * 0.12, PI * 0.9, PI * 1.9, lw, ink)
		_arc(img, c + r * 0.11, mouth_y + r * 0.02, r * 0.12, PI * 1.1, PI * 2.1, lw, ink)
	else:
		_arc(img, c, mouth_y - r * 0.1, r * 0.32, PI * 0.12, PI * 0.88, lw, ink)
	return img


## One food eye: open = white ellipse + pupil + sparkle, shut = an ink arc.
static func _food_eye(img: Image, x: float, y: float, eye_r: float, r: float,
		ink: Color, shut: bool) -> void:
	var lw := maxf(1.6, r * 0.09)
	if shut:
		_arc(img, x, y + r * 0.05, eye_r * 0.78, PI * 1.12, PI * 1.88, lw, ink)
		return
	_ellipse(img, x, y, eye_r * 0.92, eye_r, Color(1, 1, 1, 1))
	_disc(img, x + eye_r * 0.12, y + r * 0.03, eye_r * 0.55, ink)
	_disc(img, x + eye_r * 0.3, y - eye_r * 0.28, eye_r * 0.2, Color(1, 1, 1, 0.95))


## Golden crown as its own layer so it can **rotate** (web: `rotate(sin(time*4 +
## seed) * 0.12)` around the base midpoint at `(0, -r*0.95)`).
##
## Baked at 4 texels per design px into a 160x96 image whose pivot (crown base
## midpoint) is the texel (80, 84); the world quad is therefore 40 x 24 design px
## for the `r = 24` reference (see `crown_quad()`).
static func _crown_image(r: float) -> Image:
	var img := Image.create(160, 96, false, Image.FORMAT_RGBA8)
	var px := 80.0
	var py := 84.0
	var s := r * 4.0   # 1 design px of the r=24 reference == 4 texels
	var gold := Color(1.0, 224.0 / 255.0, 102.0 / 255.0)
	var stroke := Color(90.0 / 255.0, 50.0 / 255.0, 0.0, 0.5)
	var pts := PackedVector2Array([
		Vector2(px - s * 0.5, py),
		Vector2(px - s * 0.5, py - s * 0.42),
		Vector2(px - s * 0.18, py - s * 0.14),
		Vector2(px, py - s * 0.56),
		Vector2(px + s * 0.18, py - s * 0.14),
		Vector2(px + s * 0.5, py - s * 0.42),
		Vector2(px + s * 0.5, py),
	])
	_poly(img, pts, gold)
	# 2 px contour: a slightly larger dark polygon behind is not possible after
	# the fill, so stroke the outline as 2 rounds of disc chains.
	for i in pts.size():
		_line(img, pts[i].x, pts[i].y, pts[(i + 1) % pts.size()].x, pts[(i + 1) % pts.size()].y,
			2.0, stroke)
	return img


## World-space quad for the crown layer at a big-food radius `rb` and the pivot
## inside it, both in design px (`zoom` is applied by the caller).
static func crown_quad(rb: float) -> Array:
	var k := rb / 24.0
	return [40.0 * k, 24.0 * k, 20.0 * k, 21.0 * k]



# --------------------------------------------------------------- powerups

static func _build_powerups() -> void:
	powerup.append(_tex_from(_powerup_image(BOOST_COLOR, true)))
	powerup.append(_tex_from(_powerup_image(MAGNET_COLOR, false)))
	# rotating dashed ring around the badge
	var ring := _new_img(TEX_SIZE)
	var c := float(TEX_SIZE) * 0.5
	var rr := 26.0 * 1.35
	var steps := 28
	for i in steps:
		if i % 2 == 1:
			continue
		var a0 := TAU * float(i) / float(steps)
		var a1 := TAU * float(i + 1) / float(steps)
		_arc(ring, c, c, rr, a0, a1, 3.2, Color(1, 1, 1, 0.85))
	powerup_ring = _tex_from(ring)
	# thin full circle for the freeze / immunity rings
	var thin := _new_img(TEX_SIZE)
	_ring(thin, c, c, 55.0, 2.4, Color(1, 1, 1, 1))
	ring_thin = _tex_from(thin)


static func _powerup_image(col: Color, boost: bool) -> Image:
	var img := _new_img(TEX_SIZE)
	var c := float(TEX_SIZE) * 0.5
	var r := 26.0
	_glow(img, c, c, r * 2.7, col, 0.45)
	_disc(img, c, c, r, Color("1B1030"))
	_ring(img, c, c, r, 3.0, Color(1, 1, 1, 0.85))
	if boost:
		var pts := PackedVector2Array([
			Vector2(c - r * 0.10, c - r * 0.78),
			Vector2(c + r * 0.48, c - r * 0.78),
			Vector2(c + r * 0.08, c - r * 0.06),
			Vector2(c + r * 0.42, c - r * 0.06),
			Vector2(c - r * 0.36, c + r * 0.82),
			Vector2(c - r * 0.06, c + r * 0.12),
			Vector2(c - r * 0.42, c + r * 0.12),
		])
		_poly(img, pts, col)
	else:
		_arc(img, c, c - r * 0.05, r * 0.45, 0.0, PI, r * 0.42, col)
		_rect(img, c + r * 0.24, c - r * 0.52, r * 0.21, r * 0.52, Color("FF5C7A"))
		_rect(img, c - r * 0.45, c - r * 0.52, r * 0.21, r * 0.52, Color("FF5C7A"))
	return img


# ------------------------------------------------------------- particles

static func _build_particles() -> void:
	var d := _new_img(64)
	_glow(d, 32.0, 32.0, 31.0, Color(1, 1, 1, 1), 1.0)
	dot = _tex_from(d)

	var s := _new_img(64)
	_star(s, 32.0, 32.0, 30.0, 9.0, Color(1, 1, 1, 1))
	spark = _tex_from(s)

	var b := _new_img(128)
	_glow(b, 64.0, 64.0, 63.0, Color(1, 1, 1, 1), 1.0)
	blob = _tex_from(b)


static func _build_ui_bits() -> void:
	_build_band()
	_build_title()
	_build_osd()


## Multi-stop colour ramp sampled at `t` (0..1). Stops are `[pos, Color]` pairs
## in ascending `pos`, interpolated in sRGB — CSS gradients do the same, so the
## baked texture matches `getComputedStyle` values without a colour-space guess.
static func _stop_col(stops: Array, t: float) -> Color:
	var n := stops.size()
	if n == 0:
		return Color(0, 0, 0, 0)
	if t <= float(stops[0][0]):
		return stops[0][1]
	var i := 1
	while i < n:
		var p: float = float(stops[i][0])
		if t <= p:
			var p0: float = float(stops[i - 1][0])
			var k := (t - p0) / maxf(1e-6, p - p0)
			var a: Color = stops[i - 1][1]
			var b: Color = stops[i][1]
			return a.lerp(b, clampf(k, 0.0, 1.0))
		i += 1
	return stops[n - 1][1]


static func _ramp_h(w: int, stops: Array) -> ImageTexture:
	var img := Image.create(w, 1, false, Image.FORMAT_RGBA8)
	for x in w:
		img.set_pixel(x, 0, _stop_col(stops, float(x) / float(maxi(1, w - 1))))
	return _tex_from(img)


static func _ramp_v(h: int, stops: Array) -> ImageTexture:
	var img := Image.create(1, h, false, Image.FORMAT_RGBA8)
	for y in h:
		img.set_pixel(0, y, _stop_col(stops, float(y) / float(maxi(1, h - 1))))
	return _tex_from(img)


## HUD band: gradient + 1 px cyan grid (52 px columns / 26 px rows).
static func _build_band() -> void:
	band_grad = _ramp_v(64, [
		[0.0, PSTheme.BAND_TOP], [0.58, PSTheme.BAND_MID], [1.0, PSTheme.BAND_BOT]])
	var g := Image.create(52, 26, false, Image.FORMAT_RGBA8)
	for y in 26:
		for x in 52:
			var c := Color(0, 0, 0, 0)
			if y == 0:
				c = Color(0.337, 0.910, 1.0, 0.043)
			if x == 0:
				c = Color(0.337, 0.910, 1.0, 0.04)
			g.set_pixel(x, y, c)
	band_grid = _tex_from(g)
	var sc := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 8:
			sc.set_pixel(x, y, Color(190.0 / 255.0, 235.0 / 255.0, 1.0, 0.024) if y == 0
				else Color(0, 0, 0, 0))
	band_scan = _tex_from(sc)
	seam_glow = _ramp_v(16, [[0.0, Color(0.337, 0.910, 1.0, 0.0)],
		[1.0, Color(0.337, 0.910, 1.0, 0.20)]])
	energy_grad = _ramp_h(256, [
		[0.0, Color(0, 0, 0, 0)],
		[0.45, Color(184.0 / 255.0, 247.0 / 255.0, 1.0, 1.0)],
		[0.50, Color(1, 1, 1, 1)],
		[0.55, Color(184.0 / 255.0, 247.0 / 255.0, 1.0, 1.0)],
		[1.0, Color(0, 0, 0, 0)],
	])
	var r := Image.create(30, 5, false, Image.FORMAT_RGBA8)
	for y in 5:
		for x in 30:
			r.set_pixel(x, y, Color(0.337, 0.910, 1.0, 1.0) if x < 2 else Color(0, 0, 0, 0))
	ruler = _tex_from(r)
	hud_grad = _ramp_h(64, [
		[0.0, Color(0.337, 0.910, 1.0, 0.10)],
		[0.62, Color(0.337, 0.910, 1.0, 0.01)],
		[1.0, Color(0.337, 0.910, 1.0, 0.10)],
	])
	rank_grad = _ramp_h(64, [
		[0.0, Color(0, 0, 0, 0)],
		[0.30, Color(0, 0, 0, 0)],
		[1.0, Color(182.0 / 255.0, 1.0, 87.0 / 255.0, 0.09)],
	])
	cam_grad = _ramp_v(32, [
		[0.0, Color(0, 0, 0, 0)],
		[0.32, Color(2.0 / 255.0, 10.0 / 255.0, 20.0 / 255.0, 0.64)],
		[1.0, Color(2.0 / 255.0, 10.0 / 255.0, 20.0 / 255.0, 0.95)],
	])
	band_shadow = _ramp_v(32, [
		[0.0, Color(0, 0, 0, 0.62)],
		[0.35, Color(0, 0, 0, 0.34)],
		[1.0, Color(0, 0, 0, 0.0)],
	])


## Title slab + button gradients.
static func _build_title() -> void:
	var g := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var a := Color(9.0 / 255.0, 20.0 / 255.0, 36.0 / 255.0, 0.98)
	var b := Color(5.0 / 255.0, 10.0 / 255.0, 20.0 / 255.0, 0.99)
	for y in 64:
		for x in 64:
			# 155deg: down-left -> up-right
			var t := clampf((float(x) / 63.0) * 0.42 + (1.0 - float(y) / 63.0) * 0.58, 0.0, 1.0)
			g.set_pixel(x, y, a.lerp(b, t))
	panel_grad = _tex_from(g)
	btn_lime = _ramp_v(32, [
		[0.0, Color(217.0 / 255.0, 1.0, 122.0 / 255.0)],
		[0.60, Color(134.0 / 255.0, 240.0 / 255.0, 106.0 / 255.0)],
		[1.0, Color(79.0 / 255.0, 217.0 / 255.0, 138.0 / 255.0)],
	])
	btn_ghost = _ramp_v(32, [
		[0.0, Color(20.0 / 255.0, 48.0 / 255.0, 70.0 / 255.0, 0.90)],
		[1.0, Color(9.0 / 255.0, 24.0 / 255.0, 40.0 / 255.0, 0.95)],
	])


## OSD: body::before scanlines + vignette (the bracket arms are lines, not a
## texture — 8 arms in one `draw_multiline` is a single draw call).
static func _build_osd() -> void:
	var sc := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 8:
			sc.set_pixel(x, y, Color(160.0 / 255.0, 220.0 / 255.0, 1.0, 0.024) if y == 0
				else Color(0, 0, 0, 0))
	scanline = _tex_from(sc)
	# radial-gradient(at 50% 48%, transparent 46%, rgba(1,3,9,.62) 100%)
	#
	# Calibrated against the shipped pixels, not just the CSS: the web's band
	# edges sample at ~0.60 of their unobstructed colour while the band's middle
	# (and the clock digits at x=960) sample at 1.00, so the painted ramp is
	# narrower and squarer than a straight 46%->100% lerp. A pow() ramp keeps the
	# centre clean (the clock is the headline element) and still settles the
	# corners at 0.58.
	var w := 256
	var h := 144
	var v := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ink := Color(1.0 / 255.0, 3.0 / 255.0, 9.0 / 255.0)
	for y in h:
		var ny := (float(y) + 0.5) / float(h) - 0.48
		ny = ny / 0.52
		for x in w:
			var nx := ((float(x) + 0.5) / float(w) - 0.5) * 2.0
			var r := sqrt(nx * nx + ny * ny)
			var k := clampf((r - 0.62) / 0.38, 0.0, 1.0)
			v.set_pixel(x, y, Color(ink.r, ink.g, ink.b, pow(k, 1.6) * 0.42))
	vignette = _tex_from(v)


# ------------------------------------------------------- raster primitives

static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if c.a <= 0.002:
		return
	var w := img.get_width()
	var h := img.get_height()
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	if c.a >= 0.998:
		img.set_pixel(x, y, c)
		return
	var d := img.get_pixel(x, y)
	var a := c.a + d.a * (1.0 - c.a)
	if a <= 0.0001:
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	img.set_pixel(x, y, Color(
		(c.r * c.a + d.r * d.a * (1.0 - c.a)) / a,
		(c.g * c.a + d.g * d.a * (1.0 - c.a)) / a,
		(c.b * c.a + d.b * d.a * (1.0 - c.a)) / a,
		a))


static func _disc(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	if r <= 0.0:
		return
	var x0 := maxi(0, int(floor(cx - r - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + r + 1.0)))
	var y0 := maxi(0, int(floor(cy - r - 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + r + 1.0)))
	for y in range(y0, y1 + 1):
		var dy := float(y) + 0.5 - cy
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var d := sqrt(dx * dx + dy * dy)
			var cov := clampf(r + 0.5 - d, 0.0, 1.0)
			if cov > 0.0:
				_blend(img, x, y, Color(col.r, col.g, col.b, col.a * cov))


static func _disc_shaded(img: Image, cx: float, cy: float, r: float,
		hi: Color, mid: Color, lo: Color) -> void:
	var x0 := maxi(0, int(floor(cx - r - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + r + 1.0)))
	var y0 := maxi(0, int(floor(cy - r - 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + r + 1.0)))
	# radial shading centred slightly up-left, like the Web canvas gradient
	var gx := cx - r * 0.32
	var gy := cy - r * 0.40
	var gd := r * 1.35
	for y in range(y0, y1 + 1):
		var dy := float(y) + 0.5 - cy
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var d := sqrt(dx * dx + dy * dy)
			var cov := clampf(r + 0.5 - d, 0.0, 1.0)
			if cov <= 0.0:
				continue
			var gdx := float(x) + 0.5 - gx
			var gdy := float(y) + 0.5 - gy
			var t := clampf(sqrt(gdx * gdx + gdy * gdy) / gd, 0.0, 1.0)
			var c := hi.lerp(mid, clampf(t * 1.8, 0.0, 1.0)) if t < 0.55 \
				else mid.lerp(lo, (t - 0.55) / 0.45)
			_blend(img, x, y, Color(c.r, c.g, c.b, cov))


static func _ring(img: Image, cx: float, cy: float, r: float, w: float, col: Color) -> void:
	var x0 := maxi(0, int(floor(cx - r - w - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + r + w + 1.0)))
	var y0 := maxi(0, int(floor(cy - r - w - 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + r + w + 1.0)))
	for y in range(y0, y1 + 1):
		var dy := float(y) + 0.5 - cy
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var d := sqrt(dx * dx + dy * dy)
			var cov := clampf(w * 0.5 + 0.5 - absf(d - r), 0.0, 1.0)
			if cov > 0.0:
				_blend(img, x, y, Color(col.r, col.g, col.b, col.a * cov))


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0 := maxi(0, int(floor(cx - rx - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + rx + 1.0)))
	var y0 := maxi(0, int(floor(cy - ry - 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + ry + 1.0)))
	for y in range(y0, y1 + 1):
		var dy := (float(y) + 0.5 - cy) / ry
		for x in range(x0, x1 + 1):
			var dx := (float(x) + 0.5 - cx) / rx
			var d := sqrt(dx * dx + dy * dy)
			var cov := clampf((1.0 - d) * maxf(rx, ry) + 0.5, 0.0, 1.0)
			if cov > 0.0:
				_blend(img, x, y, Color(col.r, col.g, col.b, col.a * cov))


static func _rect(img: Image, x: float, y: float, w: float, h: float, col: Color) -> void:
	var x0 := maxi(0, int(floor(x)))
	var x1 := mini(img.get_width() - 1, int(ceil(x + w)))
	var y0 := maxi(0, int(floor(y)))
	var y1 := mini(img.get_height() - 1, int(ceil(y + h)))
	for yy in range(y0, y1 + 1):
		for xx in range(x0, x1 + 1):
			_blend(img, xx, yy, col)


static func _rrect(img: Image, x: float, y: float, w: float, h: float, r: float, col: Color) -> void:
	_rect(img, x + r, y, w - r * 2.0, h, col)
	_rect(img, x, y + r, r, h - r * 2.0, col)
	_rect(img, x + w - r, y + r, r, h - r * 2.0, col)
	_disc(img, x + r, y + r, r, col)
	_disc(img, x + w - r, y + r, r, col)
	_disc(img, x + r, y + h - r, r, col)
	_disc(img, x + w - r, y + h - r, r, col)


static func _line(img: Image, x0: float, y0: float, x1: float, y1: float, w: float, col: Color) -> void:
	var dx := x1 - x0
	var dy := y1 - y0
	var len := sqrt(dx * dx + dy * dy)
	var steps := maxi(1, int(len))
	var step := len / float(steps)
	for i in steps + 1:
		_disc(img, x0 + dx * (float(i) / float(steps)), y0 + dy * (float(i) / float(steps)), w * 0.5, col)


static func _arc(img: Image, cx: float, cy: float, r: float, a0: float, a1: float,
		w: float, col: Color) -> void:
	var steps := maxi(3, int(absf(a1 - a0) * r * 0.7))
	for i in steps + 1:
		var a := a0 + (a1 - a0) * (float(i) / float(steps))
		_disc(img, cx + cos(a) * r, cy + sin(a) * r, w * 0.5, col)


static func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var minx := maxi(0, int(floor(minf(a.x, minf(b.x, c.x)))))
	var maxx := mini(img.get_width() - 1, int(ceil(maxf(a.x, maxf(b.x, c.x)))))
	var miny := maxi(0, int(floor(minf(a.y, minf(b.y, c.y)))))
	var maxy := mini(img.get_height() - 1, int(ceil(maxf(a.y, maxf(b.y, c.y)))))
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-6:
		return
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var w0 := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / d
			var w1 := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / d
			var w2 := 1.0 - w0 - w1
			if w0 >= -0.02 and w1 >= -0.02 and w2 >= -0.02:
				_blend(img, x, y, col)


static func _poly(img: Image, pts: PackedVector2Array, col: Color) -> void:
	# fan triangulation: the badge icons are simple convex-ish shapes
	for i in range(1, pts.size() - 1):
		_tri(img, pts[0], pts[i], pts[i + 1], col)


static func _glow(img: Image, cx: float, cy: float, r: float, col: Color, max_a: float,
		pow_k: float = 2.0) -> void:
	var x0 := maxi(0, int(floor(cx - r)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + r)))
	var y0 := maxi(0, int(floor(cy - r)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + r)))
	for y in range(y0, y1 + 1):
		var dy := float(y) + 0.5 - cy
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var d := sqrt(dx * dx + dy * dy)
			if d >= r:
				continue
			var t := d / r
			var a := (1.0 - t) * (1.0 - t) * max_a
			if pow_k != 2.0:
				a = pow(1.0 - t, pow_k) * max_a
			_blend(img, x, y, Color(col.r, col.g, col.b, a))


static func _star(img: Image, cx: float, cy: float, outer: float, inner: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0 - PI * 0.5
		var rr := outer if i % 2 == 0 else inner
		pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr))
	_poly(img, pts, col)
