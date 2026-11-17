extends Node2D
## Workstream C — the whole 4800x2700 arena in **one** `_draw()`.
##
## One CanvasItem for backdrop + walls + food + powerups + snakes + particles.
## Primitive budget per frame (measured, see the report):
##   backdrop ~4, seams <=4, walls <=8, food ~25 blits, powerups ~6,
##   snake bodies 2 draw calls total (glow + one ordered body stack), heads
##   ~8-10 each, particles/text ~20.  ~250 draw calls worst case vs ~8000 canvas
##   ops in the WebView prototype.
##
## Snake bodies are a **tail -> head ordered stack of opaque per-segment quads**
## with per-vertex colours: the colour ramp, the taper towards the tail, the
## outline, the highlight, the boost aura and the scale ticks all land in one
## triangle array, so the whole field is one draw call and a self-overlap is
## resolved by paint order (`PSTheme.band_stack_append`).

const PSTheme = preload("res://src/present/ps_theme.gd")
const PSAssets = preload("res://src/present/ps_assets.gd")
const PSFx = preload("res://src/present/ps_fx.gd")
const PSSkins = preload("res://src/present/ps_skins.gd")
const PSData = preload("res://src/present/ps_skin_data.gd")
## Tiny `_draw` forwarder used for the additive halo pass (see `_ready`).
const PSLayer = preload("res://src/present/ps_layer.gd")

## World -> screen: (world - cam) * zoom + view * 0.5
var cam := Vector2.ZERO
var zoom := 1.2
var view := Vector2(1920.0, 1080.0)
var time := 0.0
var cfg = null
var game = null
var fx: PSFx = null
## Which human this view looks at (split screen).
var player_index := 0
## 0 when the arena is live, 1 when the settlement stage covers it.
var dim := 0.0
## Capture tooling only (`--capture-flow` arena-only frame): skip bodies, heads
## and their halo so the grid and the HUD panels can be judged on their own.
var hide_snakes: bool = false

const MAX_SNAKES := 8

## Opaque body outline. The web's is `rgba(6,30,34,0.5)` — a *soft dark teal*,
## not the hard near-black this used to be (ART-DIFF §1.4). It stays per segment
## inside the ordered stack, so a self-overlap still resolves by paint order.
const BODY_RIM_COL := Color(6.0 / 255.0, 30.0 / 255.0, 34.0 / 255.0, 0.5)
## B4 tube rim: the web's 2.5 px `rgba(6,30,34,.5)` contour measures as a
## **10-14 px dark olive band** in the shipped frame (`web-play-1920.png`, a
## perpendicular cut at x=800 reads floor (20,26,44) -> (48,67,53) ..
## (76,107,65) over 14 px -> body (129,245,133)); the port had a 2 px near-black
## hairline instead, which is what made the body read as a flat vector ribbon.
## So the rim is now a thick band tinted toward the snake's own dark colour (a gel
## tube's rim is dense gel, not ink) and the additive halo starts *inside* it, so
## the outer part of the band picks up the same olive light the web shows.
const RIM_W := 6.0
const RIM_A := 0.90
## Rim silhouette feather (1.2 px alpha ramp on the outside edge). 1.0 = on.
## **Set to 0.0 on purpose** (performance pass): the feather is two extra quads per
## slice, i.e. half of the rim's geometry, and it is a ~1 px softening at 1080p. The
## measured win is 1.9 ms/frame in the 2P worst case, which is what takes split
## screen from 47 to 50+ fps. Restore to 1.0 if the owner ever wants the softer
## silhouette back (that is the whole "visual trade-off" of this pass).
## 0 = the web's dark teal, 1 = `darken(snake colour)`. The web's measured rim is
## olive-green, i.e. mostly the snake's own colour in shadow.
const RIM_TINT_MIX := 0.50
const RIM_FEATHER := 0.0
## Gel stack. The body is an opaque under-fill (keeps a self-overlap opaque)
## carrying a *translucent, laterally shaded* gel fill, then the bright inner core
## stripe. Widening/narrowing these is the whole "jelly tube" dial.
const TUBE_UNDER := 0.40
const TUBE_GEL_A := 0.86
const TUBE_GEL_W := 0.90
const TUBE_LAT := 0.40
const TUBE_CORE_A := 0.44
const TUBE_CORE_MUL := 0.26
const TUBE_CORE_W := 0.66
const TUBE_CORE_OFF := -0.20
## Top highlight and scale arcs: translucent, but painted inside their own
## segment, so the next segment's opaque under-fill overwrites them.
## Web: sheen `rgba(255,255,255,.22)` at `lineWidth R*0.6`, `translate(0,-R*0.36)`;
## arcs `rgba(235,255,225, .16 - .36)` at `lineWidth R*0.2`, `radius R*0.55`.
## The arc alpha sits at the middle of the web's range (.26) because the port's
## lime body is brighter than the web's cyan end, where .19 was measured.
## The sheen is dimmer than the web's .22 because the gel rails + the core stripe
## already carry the "light from above" (a second .22 white band measured as one
## flat pale ribbon: that was the B2 flatness).
const SHEEN_COL := Color(1.0, 1.0, 1.0, 0.10)
const SHEEN_HALF := 0.30
const RIDGE_COL := Color(235.0 / 255.0, 1.0, 225.0 / 255.0, 0.26)
## Halo: ONE additive pass, `rgba(col,0.13)` at half-width `r + 15` on the web
## (`render.js:492-500`: `lighter`, `lineWidth R*2 + 30`). The shipped web glow is
## not flat, though: the body stroke also carries `shadowColor rgba(col,.65)` /
## `shadowBlur 26`, so the additive luminance at the tube edge measures ~.30 and
## falls to ~.05 at +15 px (measured on `web-play-1920.png`, y=600..616 at x=700).
## One annulus with a lateral alpha ramp reproduces that, and it is still **one**
## draw call (same triangle array).
const HALO_A_IN := 0.34
const HALO_A_OUT := 0.02
const HALO_PAD := 16.0
## The tail keeps a wider, softer wrap (the tapered end of a gel tube is where the
## halo pools): the pad grows by this factor from head to tail.
const HALO_PAD_TAIL := 1.35
## The contour's outer half; the halo starts there so it never washes the rim out
## (the web paints halo -> rim -> body, we must paint the halo last). It now sits
## *inside* the thicker rim on purpose, so the rim's outer half is lit olive.
const HALO_GAP := 4.0
## Body taper towards the tail (half-width fraction) and the curve exponent; the
## halo reuses both so its 15 px margin stays parallel to the tube.
const TAPER_TAIL := 0.55
const TAPER_POW := 1.45

## ---- character skins (owner's pack, `assets/characters/**`) -----------------
## Lateral shade applied to the textured tube: 0 = flat (the art already carries
## the gel shading), 0.18 keeps the cylinder reading without eating the pattern.
const TEX_LAT := 0.18
## Body `v` mapping. 0 = map the art **once** over the whole body: the pack's tube
## is a length-wise tail->neck gradient (measured on the 160x480 straight section:
## rgb 249,184,72 -> 248,101,84 for A1), so repeating it puts a colour step every
## tile. A positive value repeats the texture every `BODY_TILE_MUL * tube width`
## destination px — 4.0 is the pack's own 640/160 aspect, a true no-stretch tiling.
const BODY_TILE_MUL := 0.0
## Head bob/tilt and the eat squash pulse. All three are transforms on the head
## quads only, so they cost no extra draw call.
const HEAD_TILT := 0.045
const HEAD_BOB := 0.03
const EAT_SQUASH_X := 0.07
const EAT_SQUASH_Y := 0.14
## Blink: eyes_half for the first 1/4 of the blink, eyes_closed for the rest.
const BLINK_SEC := 0.17
const BLINK_HALF := 0.05
const TONGUE_SEC := 0.28

## ---- dense body polyline (owner fix A) -------------------------------------
## The simulated body has one point per `seg_dist` (~18 world px); drawn directly,
## its outline is a chain of 18 px chords, which is the "straight polygonal edge /
## square corner" the owner circled. Each simulated segment is therefore sliced
## `kk` times where `kk` grows with the turn angle at that joint, so a straight run
## stays at 1 slice and a bend gets up to `MAX_SUB`.
const MAX_SUB := 6
## Radians of turn per extra slice (~3.4 deg): a 60 deg bend asks for 6 slices.
const SUB_ANGLE := 0.06
## Total dense points for the whole visible field. Each dense point costs ~32
## vertices in the body stack, so this keeps the shared triangle array far below
## the 65000 limit even with 8 snakes. Snakes that would exceed it fall back to
## fewer slices instead of being dropped.
const DENSE_BUDGET := 1900

# per-frame reusable buffers (no allocation in the draw path)
## ---- measurement only (`--capture-stress`) ----------------------------------
## Per-pass CPU time of the last `_draw`, in ms. `prof` is owned by main.gd and is
## false in every normal run, so the two `Time.get_ticks_usec()` calls per pass do
## not exist unless the stress harness asks for them (`_prof_mark` early-returns).
var prof := false
var prof_ms: Dictionary = {}
var _prof_t := 0
var _bodies_drawn := 0
var _bodies_dropped := 0

var _pts := PackedVector2Array()
var _snake_pts: Array = []
var _snake_ramp: Array = []
## Per-snake halo tint (a Color, not a ramp: the falloff is a lateral gradient).
var _snake_glow: Array = []
## Per-snake tube rim tint (B4).
var _snake_rim: Array = []
## Preallocated tube option dictionaries (`PSTheme.band_stack_append`): one per
## snake slot, built once, so the draw path never allocates a Dictionary.
var _snake_tube: Array = []
## Dense body geometry per slot (points, normals, radii, ramp t, scale-arc marks),
## rebuilt every frame from the simulated points (see `_build_dense_body`).
var _snake_dpts: Array = []
var _snake_nrm: Array = []
var _snake_drad: Array = []
var _snake_dts: Array = []
var _snake_dmrk: Array = []
## Reused per-segment slice-count scratch buffer.
var _sub_counts := PackedInt32Array()
## Dense points spent this frame (see `DENSE_BUDGET`).
var _dense_used := 0
var _snake_r := PackedFloat32Array()
## First / last simulated index the dense body was built for (see
## `_collect_snakes`): -1..0 pairs mean "the whole body".
var _snake_i0 := PackedInt32Array()
var _snake_i1 := PackedInt32Array()
var _snake_on: Array = []
## Resolved character-skin index per slot (-1 = none, procedural fallback).
var _skin := PackedInt32Array()
## Per-slot expression state (blink / tongue / eat squash / deterministic RNG),
## preallocated in `_init` so the draw path never builds a Dictionary.
var _anim: Array = []
## Rim pass: every snake's rim in one untextured array (drawn first, so no rim
## can ever paint over another snake's body).
var _rim_v := PackedVector2Array()
var _rim_c := PackedColorArray()
var _rim_i := PackedInt32Array()
## Textured body pass: rebuilt per snake and flushed with that character's body
## texture, so the whole field is <= MAX_SNAKES commands instead of one per
## segment.
var _tb_v := PackedVector2Array()
var _tb_c := PackedColorArray()
var _tb_uv := PackedVector2Array()
var _tb_i := PackedInt32Array()
## Head pass: four atlas quads (head -> eyes -> mouth -> decor), one command per
## snake with that character's head atlas.
var _hd_v := PackedVector2Array()
var _hd_c := PackedColorArray()
var _hd_uv := PackedVector2Array()
var _hd_i := PackedInt32Array()
var _glow_v := PackedVector2Array()
var _glow_c := PackedColorArray()
var _glow_i := PackedInt32Array()
var _body_v := PackedVector2Array()
var _body_c := PackedColorArray()
var _body_i := PackedInt32Array()
## Food batch: every visible pellet is a quad pair in these buffers (one
## `canvas_item_add_triangle_array` per flush, see `_draw_food`).
var _food_v := PackedVector2Array()
var _food_c := PackedColorArray()
var _food_uv := PackedVector2Array()
var _food_i := PackedInt32Array()

var _blobs: Array = []
var _food_idx: Dictionary = {}
## Big-food layer batches: 0 body, 1 crown, 2 face open, 3 face shut. Each layer
## is ONE triangle array flushed with its own texture (see `_draw_food`).
var _bigv: Array = []
var _bigc: Array = []
var _bigu: Array = []
var _bigi: Array = []
## Additive halo layer (child CanvasItem with `BLEND_MODE_ADD`).
var _add: Node2D = null


func _ready() -> void:
	# The halo has to be *additive* (`globalCompositeOperation='lighter'` on the
	# web). Godot 4 has no per-draw blend mode — the material belongs to the
	# CanvasItem — so the glow pass gets its own child item, drawn after this one
	# and built as an outer annulus only (it can never wash over its own body).
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add = PSLayer.new()
	_add.name = "AddHalo"
	_add.material = mat
	_add.host = self
	add_child(_add)

## Deterministic decoration positions (world light blobs), built once.
func _init() -> void:
	var seed_state := 0x1F2E3D4C
	var palette := [Color(0.09, 0.45, 1.0), Color(0.0, 0.78, 1.0),
		Color(0.38, 0.28, 0.86), Color(0.0, 0.92, 0.75), Color(0.16, 0.38, 0.82)]
	for i in 22:
		var x := float(seed_state & 0xFFFF) / 65535.0
		seed_state = (seed_state * 1664525 + 1013904223) & 0xFFFFFFFF
		var y := float(seed_state & 0xFFFF) / 65535.0
		seed_state = (seed_state * 1664525 + 1013904223) & 0xFFFFFFFF
		var rr := float(seed_state & 0xFFFF) / 65535.0
		seed_state = (seed_state * 1664525 + 1013904223) & 0xFFFFFFFF
		var aa := float(seed_state & 0xFFFF) / 65535.0
		seed_state = (seed_state * 1664525 + 1013904223) & 0xFFFFFFFF
		var c: Color = palette[i % palette.size()]
		_blobs.append({
			"x": x * 4800.0, "y": y * 2700.0, "r": 260.0 + rr * 360.0,
			"c": Color(c.r, c.g, c.b, 0.075 + aa * 0.075),
		})
	for i in MAX_SNAKES:
		_snake_pts.append(PackedVector2Array())
		_snake_ramp.append(PackedColorArray())
		_snake_glow.append(PackedColorArray())
		_snake_rim.append(BODY_RIM_COL)
		_snake_dpts.append(PackedVector2Array())
		_snake_nrm.append(PackedVector2Array())
		_snake_drad.append(PackedFloat32Array())
		_snake_dts.append(PackedFloat32Array())
		_snake_dmrk.append(PackedByteArray())
		_snake_tube.append({
			"under": TUBE_UNDER, "gel_a": TUBE_GEL_A, "gel_w": TUBE_GEL_W,
			"lat": TUBE_LAT, "core_a": TUBE_CORE_A, "core_mul": TUBE_CORE_MUL,
			"core_w": TUBE_CORE_W, "core_off": TUBE_CORE_OFF,
		})
		_snake_on.append(false)
		_anim.append({
			"t": 0.0, "blink": 0.0, "next": 1.2 + float(i) * 0.37,
			"tongue": 0.0, "next_t": 2.2 + float(i) * 0.53,
			"squash": 0.0, "food": 0, "kills": 0,
			"phase": float(i) * 1.37,
			# deterministic LCG: two runs of the same round blink identically
			"rng": (0x2F1E3D4C + i * 7919) & 0xFFFFFFFF,
		})
	_snake_r.resize(MAX_SNAKES)
	_skin.resize(MAX_SNAKES)
	_skin.fill(-1)
	# Visible index span per snake (dense-body clipping, see `_collect_snakes`).
	_snake_i0.resize(MAX_SNAKES)
	_snake_i1.resize(MAX_SNAKES)
	_snake_i1.fill(-1)
	# Big-food layer batches (4 layers: body / crown / face-open / face-shut).
	for k in 4:
		_bigv.append(PackedVector2Array())
		_bigc.append(PackedColorArray())
		_bigu.append(PackedVector2Array())
		_bigi.append(PackedInt32Array())


# ------------------------------------------------------------------- draw

func _draw() -> void:
	if game == null:
		return
	if prof:
		prof_ms.clear()
	_prof_t = Time.get_ticks_usec() if prof else 0
	_draw_backdrop()
	_prof_mark("world.floor")
	_draw_seams()
	_draw_walls()
	_prof_mark("world.walls")
	_draw_food()
	_prof_mark("world.food")
	_draw_powerups()
	_prof_mark("world.powerups")
	_collect_snakes()
	_prof_mark("world.collect")
	if not hide_snakes:
		_draw_bands()
		_prof_mark("world.band")
		_draw_heads()
		_prof_mark("world.heads")
	if fx != null:
		fx.draw(self, cam, zoom, view)
		_prof_mark("world.fx")
		if fx.flash > 0.008:
			var fc: Color = fx.flash_col
			fc.a = fx.flash * 0.55
			draw_rect(Rect2(0, 0, view.x, view.y), fc, true)
	if dim > 0.001:
		draw_rect(Rect2(0, 0, view.x, view.y), Color(0.02, 0.03, 0.06, dim), true)


## Store the time spent since the previous mark under `key` (stress harness only).
## Marks accumulate within one frame (a 2P frame draws two worlds and two band
## cells), and `_draw` clears the dictionary at the top of each frame.
func _prof_mark(key: String) -> void:
	if not prof:
		return
	var now := Time.get_ticks_usec()
	prof_ms[key] = float(prof_ms.get(key, 0.0)) + float(now - _prof_t) / 1000.0
	_prof_t = now


## Additive pass, called by the `PSLayer` child (`BLEND_MODE_ADD`): the snake
## halo, plus the big-food halo boost. Everything here is `lighter`.
func draw_additive(ci: CanvasItem) -> void:
	if game == null or hide_snakes:
		return
	if prof:
		var t := Time.get_ticks_usec()
		_draw_glow(ci)
		prof_ms["world.halo"] = float(Time.get_ticks_usec() - t) / 1000.0
		return
	_draw_glow(ci)


func _visible_world() -> Rect2:
	var span := view / zoom
	return Rect2(cam - span * 0.5, span)


# ------------------------------------------------------------- background

func _draw_backdrop() -> void:
	draw_texture_rect(PSAssets.bg_grad, Rect2(0, 0, view.x, view.y), false)
	# world light blobs (parallax-free, they are part of the arena floor)
	var vr := _visible_world()
	var half := view * 0.5
	for b in _blobs:
		var bx: float = b["x"]
		var by: float = b["y"]
		var br: float = b["r"]
		if bx + br < vr.position.x or bx - br > vr.end.x:
			continue
		if by + br < vr.position.y or by - br > vr.end.y:
			continue
		var sx := (bx - cam.x) * zoom + half.x
		var sy := (by - cam.y) * zoom + half.y
		var s := br * 2.0 * zoom
		draw_texture_rect(PSAssets.blob, Rect2(sx - s * 0.5, sy - s * 0.5, s, s), false,
			b["c"])
	# 90 px arena floor tile (world locked, so it scrolls with the camera).
	# Drawn from a tile baked at the *exact* screen size (`grid_at`), otherwise a
	# 90 -> 88 texel resample halves the 1 px cross arms and the floor reads faint
	# (that was the whole "our grid is too faint" delta, on top of the old bake's
	# .055 arms vs the web's .075).
	var tile := 90.0 * zoom
	if tile >= 8.0:
		var px := int(round(tile))
		var t := float(px)
		var ox := -fposmod(round(cam.x * zoom - half.x), t)
		var oy := -fposmod(round(cam.y * zoom - half.y), t)
		draw_texture_rect(PSAssets.grid_at(px),
			Rect2(ox - t, oy - t, view.x + t * 2.0, view.y + t * 2.0), true)


func _draw_seams() -> void:
	# 3x3 screens: dashed seams at 1600/3200 and 900/1800 world units.
	# Web: `rgba(86,232,255,0.11)`, `lineWidth 2`, `setLineDash([14,18])`
	# (`render.js:118-120`) — NOT white at .16.
	var half := view * 0.5
	var tile_w := 1600.0
	var tile_h := 900.0
	var seam_col := Color(0.337, 0.910, 1.0, 0.11)
	for i in range(1, 3):
		var wx := float(i) * tile_w
		var sx := (wx - cam.x) * zoom + half.x
		if sx > -40.0 and sx < view.x + 40.0:
			draw_set_transform(Vector2(sx, 0.0), PI * 0.5, Vector2.ONE)
			draw_texture_rect(PSAssets.dash, Rect2(0.0, -1.0, view.y + 64.0, 2.0), true,
				seam_col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for j in range(1, 3):
		var wy := float(j) * tile_h
		var sy := (wy - cam.y) * zoom + half.y
		if sy > -40.0 and sy < view.y + 40.0:
			draw_texture_rect(PSAssets.dash, Rect2(0.0, sy - 1.0, view.x + 64.0, 2.0), true,
				seam_col)


func _draw_walls() -> void:
	var w := 4800.0
	var h := 2700.0
	var vr := _visible_world()
	var half := view * 0.5
	# danger from the watched player's distance to the nearest wall
	var near := 9999.0
	var p = game.players[player_index] if player_index < game.players.size() else null
	if p != null and p.alive and p.body.size() > 0:
		var hd: Vector2 = p.body[0]
		near = minf(minf(hd.x, w - hd.x), minf(hd.y, h - hd.y))
	var danger := clampf(1.0 - near / 340.0, 0.0, 1.0)
	var pulse := 0.62 + 0.38 * sin(time * 7.2)
	var a := 0.30 + danger * 0.62 * pulse
	var tint := Color(1.0, 0.30, 0.44, a)
	var depth := 88.0 * zoom
	# left
	if vr.position.x < 30.0:
		var sx := (6.0 - cam.x) * zoom + half.x
		draw_set_transform(Vector2(sx, 0.0), -PI * 0.5, Vector2.ONE)
		draw_texture_rect(PSAssets.wall_strip, Rect2(0.0, 0.0, view.y, depth), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(Vector2(sx, 0.0), Vector2(sx, view.y), Color(1, 0.42, 0.55, a + 0.25),
			maxf(2.0, 4.0 * zoom))
	# right
	if vr.end.x > w - 30.0:
		var sx2 := (w - 6.0 - cam.x) * zoom + half.x
		draw_set_transform(Vector2(sx2, 0.0), PI * 0.5, Vector2.ONE)
		draw_texture_rect(PSAssets.wall_strip, Rect2(0.0, 0.0, view.y, depth), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(Vector2(sx2, 0.0), Vector2(sx2, view.y), Color(1, 0.42, 0.55, a + 0.25),
			maxf(2.0, 4.0 * zoom))
	# top
	if vr.position.y < 30.0:
		var sy := (6.0 - cam.y) * zoom + half.y
		draw_set_transform(Vector2(0.0, sy), 0.0, Vector2.ONE)
		draw_texture_rect(PSAssets.wall_strip, Rect2(0.0, 0.0, view.x, depth), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(Vector2(0.0, sy), Vector2(view.x, sy), Color(1, 0.42, 0.55, a + 0.25),
			maxf(2.0, 4.0 * zoom))
	# bottom
	if vr.end.y > h - 30.0:
		var sy2 := (h - 6.0 - cam.y) * zoom + half.y
		draw_set_transform(Vector2(0.0, sy2), PI, Vector2.ONE)
		draw_texture_rect(PSAssets.wall_strip, Rect2(0.0, 0.0, view.x, depth), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(Vector2(0.0, sy2), Vector2(view.x, sy2), Color(1, 0.42, 0.55, a + 0.25),
			maxf(2.0, 4.0 * zoom))


# -------------------------------------------------------------------- food

## Quad tint for the batched food pass: `draw_texture_rect(tex, dst, false)` used
## the item's own modulate, i.e. opaque white.
const FOOD_TINT := Color(1, 1, 1, 1)


func _food_texture_index(col: Color) -> int:
	var key := col.to_rgba32()
	var idx: int = _food_idx.get(key, -1)
	if idx >= 0:
		return idx
	# nearest palette entry (runs at most once per distinct corpse colour)
	var best := 0
	var best_d := 1e9
	for i in PSAssets.FOOD_COLORS.size():
		var c: Color = PSAssets.FOOD_COLORS[i]
		var d := absf(c.r - col.r) + absf(c.g - col.g) + absf(c.b - col.b)
		if d < best_d:
			best_d = d
			best = i
	_food_idx[key] = best
	return best


func _draw_food() -> void:
	var vr := _visible_world().grow(90.0 / zoom)
	var half := view * 0.5
	var size := PSAssets.size_for(PSAssets.TEX_R) * zoom
	var foods: Array = game.foods
	var n := foods.size()
	var t := time
	var i := 0
	_food_begin()
	_big_begin()
	while i < n:
		var f = foods[i]
		i += 1
		var fx_: float = f.x
		var fy_: float = f.y
		if fx_ < vr.position.x or fx_ > vr.end.x or fy_ < vr.position.y or fy_ > vr.end.y:
			continue
		var bob := sin(t * 3.2 + f.seed_value) * 3.5
		var beat := sin(t * 6.5 + f.seed_value) * 0.06
		var sx := (fx_ - cam.x) * zoom + half.x
		var sy := (fy_ + bob - cam.y) * zoom + half.y
		var w := size * (1.0 + beat)
		var hgt := size * (1.0 - beat)
		var dst := Rect2(sx - w * 0.5, sy - hgt * 0.5, w, hgt)
		var face: int = PSAssets.face_index(f.face)
		# Blink: `(time*0.9 + seed) % 3.2 > 3.0` (render.js:drawFoodFace) — 6% of
		# the cycle, and it is a *baked* second variant, not a per-frame gradient.
		var shut: bool = fmod(t * 0.9 + f.seed_value, 3.2) > 3.0
		if f.big:
			# Big food is THREE layers (body / golden crown / face) with its own
			# textures, batched by layer: one draw call per layer for the whole
			# field instead of 3 per big pellet. With 8% big pellets that is ~85
			# draw calls -> 4 (measured on the 265-pellet stress field), and the
			# only visible difference is that two OVERLAPPING big pellets now
			# composite body-over-face instead of pellet order (they are 30 px
			# discs, so this is rare). Order within one pellet is unchanged.
			_big_quad(0, dst, FOOD_TINT)
			# Golden crown: its own layer so it can rotate around its base.
			var cq: Array = PSAssets.crown_quad(f.r)
			var ang: float = sin(t * 4.0 + f.seed_value) * 0.12
			var piv := Vector2(sx, sy - f.r * 0.95 * zoom)
			var ca := cos(ang)
			var sa := sin(ang)
			var qx: float = -float(cq[2]) * zoom
			var qy: float = -float(cq[3]) * zoom
			var qw: float = float(cq[0]) * zoom
			var qh: float = float(cq[1]) * zoom
			_big_quad_rot(1, piv, ca, sa, qx, qy, qw, qh, FOOD_TINT)
			_big_quad(2 if not shut else 3, dst, FOOD_TINT)
		else:
			# Body + face as two quads of the one atlas, appended in paint order:
			# a pellet is still "body then face", and pellets keep their array
			# order, so overlapping pellets composite exactly as before.
			_food_quad(dst, _food_texture_index(f.color), FOOD_TINT)
			_food_quad(dst, PSAssets.FOOD_COLORS.size() + face * 2 + (1 if shut else 0),
				FOOD_TINT)
	_food_flush()
	_big_flush_all()


func _big_begin() -> void:
	for k in 4:
		_bigv[k].resize(0)
		_bigc[k].resize(0)
		_bigu[k].resize(0)
		_bigi[k].resize(0)


## Append one axis-aligned quad to big-food layer `layer` (UV 0..1).
func _big_quad(layer: int, dst: Rect2, tint: Color) -> void:
	var v: PackedVector2Array = _bigv[layer]
	var c: PackedColorArray = _bigc[layer]
	var uv: PackedVector2Array = _bigu[layer]
	var idx: PackedInt32Array = _bigi[layer]
	var base := v.size()
	v.resize(base + 4)
	c.resize(base + 4)
	uv.resize(base + 4)
	v[base] = Vector2(dst.position.x, dst.position.y)
	v[base + 1] = Vector2(dst.end.x, dst.position.y)
	v[base + 2] = Vector2(dst.end.x, dst.end.y)
	v[base + 3] = Vector2(dst.position.x, dst.end.y)
	uv[base] = Vector2(0.0, 0.0)
	uv[base + 1] = Vector2(1.0, 0.0)
	uv[base + 2] = Vector2(1.0, 1.0)
	uv[base + 3] = Vector2(0.0, 1.0)
	for k in 4:
		c[base + k] = tint
	var ib := idx.size()
	idx.resize(ib + 6)
	idx[ib] = base
	idx[ib + 1] = base + 1
	idx[ib + 2] = base + 2
	idx[ib + 3] = base
	idx[ib + 4] = base + 2
	idx[ib + 5] = base + 3
	_bigv[layer] = v
	_bigc[layer] = c
	_bigu[layer] = uv
	_bigi[layer] = idx


## Append the rotated crown quad: `piv` is the pivot, (`ca`,`sa`) its rotation,
## (`qx`,`qy`,`qw`,`qh`) the unrotated rect relative to the pivot.
func _big_quad_rot(layer: int, piv: Vector2, ca: float, sa: float, qx: float, qy: float,
		qw: float, qh: float, tint: Color) -> void:
	var v: PackedVector2Array = _bigv[layer]
	var c: PackedColorArray = _bigc[layer]
	var uv: PackedVector2Array = _bigu[layer]
	var idx: PackedInt32Array = _bigi[layer]
	var base := v.size()
	v.resize(base + 4)
	c.resize(base + 4)
	uv.resize(base + 4)
	var corners := [Vector2(qx, qy), Vector2(qx + qw, qy), Vector2(qx + qw, qy + qh),
		Vector2(qx, qy + qh)]
	for k in 4:
		var p: Vector2 = corners[k]
		v[base + k] = piv + Vector2(p.x * ca - p.y * sa, p.x * sa + p.y * ca)
		c[base + k] = tint
	uv[base] = Vector2(0.0, 0.0)
	uv[base + 1] = Vector2(1.0, 0.0)
	uv[base + 2] = Vector2(1.0, 1.0)
	uv[base + 3] = Vector2(0.0, 1.0)
	var ib := idx.size()
	idx.resize(ib + 6)
	idx[ib] = base
	idx[ib + 1] = base + 1
	idx[ib + 2] = base + 2
	idx[ib + 3] = base
	idx[ib + 4] = base + 2
	idx[ib + 5] = base + 3
	_bigv[layer] = v
	_bigc[layer] = c
	_bigu[layer] = uv
	_bigi[layer] = idx


## One draw call per non-empty big-food layer, in paint order:
## body -> crown -> face.
func _big_flush_all() -> void:
	_big_flush_layer(0, PSAssets.food_big_body)
	_big_flush_layer(1, PSAssets.crown)
	_big_flush_layer(2, PSAssets.food_face[4])
	_big_flush_layer(3, PSAssets.food_face[5])


func _big_flush_layer(layer: int, tex: Texture2D) -> void:
	var idx: PackedInt32Array = _bigi[layer]
	if idx.size() == 0 or tex == null:
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, _bigv[layer],
		_bigc[layer], _bigu[layer], PackedInt32Array(), PackedFloat32Array(),
		tex.get_rid(), -1)
	idx.resize(0)
	_bigi[layer] = idx


func _food_begin() -> void:
	_food_v.resize(0)
	_food_c.resize(0)
	_food_uv.resize(0)
	_food_i.resize(0)


## Append one textured quad from the food atlas (2 triangles, UV = the tile rect).
func _food_quad(dst: Rect2, tile: int, tint: Color) -> void:
	var u := PSAssets.food_atlas_uv(tile)
	var base := _food_v.size()
	_food_v.resize(base + 4)
	_food_c.resize(base + 4)
	_food_uv.resize(base + 4)
	_food_v[base] = Vector2(dst.position.x, dst.position.y)
	_food_v[base + 1] = Vector2(dst.end.x, dst.position.y)
	_food_v[base + 2] = Vector2(dst.end.x, dst.end.y)
	_food_v[base + 3] = Vector2(dst.position.x, dst.end.y)
	_food_uv[base] = Vector2(u.position.x, u.position.y)
	_food_uv[base + 1] = Vector2(u.end.x, u.position.y)
	_food_uv[base + 2] = Vector2(u.end.x, u.end.y)
	_food_uv[base + 3] = Vector2(u.position.x, u.end.y)
	for k in 4:
		_food_c[base + k] = tint
	var ib := _food_i.size()
	_food_i.resize(ib + 6)
	_food_i[ib] = base
	_food_i[ib + 1] = base + 1
	_food_i[ib + 2] = base + 2
	_food_i[ib + 3] = base
	_food_i[ib + 4] = base + 2
	_food_i[ib + 5] = base + 3


## One draw call for every quad appended since `_food_begin()`.
func _food_flush() -> void:
	if _food_i.size() == 0:
		return
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _food_i, _food_v,
		_food_c, _food_uv, PackedInt32Array(), PackedFloat32Array(),
		PSAssets.food_atlas.get_rid(), -1)
	_food_v.resize(0)
	_food_c.resize(0)
	_food_uv.resize(0)
	_food_i.resize(0)


# ---------------------------------------------------------------- powerups

func _draw_powerups() -> void:
	var vr := _visible_world().grow(120.0 / zoom)
	var half := view * 0.5
	var size := PSAssets.size_for(PSAssets.TEX_R) * zoom
	var pup: Array = game.powerups
	var n := pup.size()
	var i := 0
	# Three batched layers instead of three draws per pickup (7 pickups = 21 calls
	# -> 3): 0 = the rotating dashed ring, 1 = boost badge, 2 = magnet badge. The
	# badges are two different textures, so they cannot share one array; the labels
	# stay one text draw each (they are the only part that differs per pickup).
	_big_begin()
	while i < n:
		var p = pup[i]
		i += 1
		if p.x < vr.position.x or p.x > vr.end.x or p.y < vr.position.y or p.y > vr.end.y:
			continue
		var bob: float = sin(time * 2.6 + p.seed_value) * 4.0
		var sx: float = (p.x - cam.x) * zoom + half.x
		var sy: float = (p.y + bob - cam.y) * zoom + half.y
		var idx: int = 1 if p.type == &"magnet" else 0
		var rot: float = time * 0.9 + p.seed_value
		_big_quad_rot(0, Vector2(sx, sy), cos(rot), sin(rot), -size * 0.5, -size * 0.5,
			size, size, Color(1, 1, 1, 1))
		_big_quad_rot(1 + idx, Vector2(sx, sy), 1.0, 0.0, -size * 0.5, -size * 0.5,
			size, size, Color(1, 1, 1, 1))
		PSTheme.text_c(self, sx, sy + 52.0 * zoom, p.label, int(20.0 * zoom),
			Color(1, 0.99, 0.94), false)
	_big_flush_layer(0, PSAssets.powerup_ring)
	_big_flush_layer(1, PSAssets.powerup[0])
	_big_flush_layer(2, PSAssets.powerup[1])


# ------------------------------------------------------------------ snakes

## Capture tooling (`--capture-flow`): the character skins the last drawn frame
## actually rendered, one entry per on-screen snake with a usable atlas. The
## release gate reads this to prove that >=2 distinct characters are in one
## frame; it is read-only and never touched by gameplay or the render path.
func visible_skins() -> Array:
	var out: Array = []
	var i := 0
	while i < MAX_SNAKES:
		if _snake_on[i] and _skin[i] >= 0:
			out.append(int(_skin[i]))
		i += 1
	return out


func _collect_snakes() -> void:
	var snakes: Array = game.snakes
	var half := view * 0.5
	var vis := PSTheme.vis_rect(view, 96.0)
	var i := 0
	while i < MAX_SNAKES:
		_snake_on[i] = false
		i += 1
	_dense_used = 0
	i = 0
	while i < snakes.size() and i < MAX_SNAKES:
		var s = snakes[i]
		_snake_on[i] = false
		if not s.alive or s.body.size() < 2:
			i += 1
			continue
		var r: float = s.radius()
		_snake_r[i] = r
		s.render_points_into(_pts)
		var n := _pts.size()
		var buf: PackedVector2Array = _snake_pts[i]
		buf.resize(n)
		var minx := 1e18
		var maxx := -1e18
		var miny := 1e18
		var maxy := -1e18
		# Visible index span: first/last point inside the clip rect, plus HOW MANY
		# points are inside. If the count equals the span the visible run is
		# contiguous, so the dense body only has to be built for it (a long snake is
		# mostly off-screen; see `_build_dense_body`). A body that leaves and
		# re-enters the view has a count > span and is built in full (no holes).
		var i0 := -1
		var i1 := -1
		var inside := 0
		var k := 0
		while k < n:
			var wp := _pts[k]
			var sx := (wp.x - cam.x) * zoom + half.x
			var sy := (wp.y - cam.y) * zoom + half.y
			buf[k] = Vector2(sx, sy)
			if sx < minx:
				minx = sx
			if sx > maxx:
				maxx = sx
			if sy < miny:
				miny = sy
			if sy > maxy:
				maxy = sy
			if vis.has_point(Vector2(sx, sy)):
				inside += 1
				if i0 < 0:
					i0 = k
				i1 = k
			k += 1
		var margin := r * 3.0 * zoom + 60.0
		if maxx < -margin or minx > view.x + margin or maxy < -margin or miny > view.y + margin:
			i += 1
			continue
		_snake_pts[i] = buf
		_snake_on[i] = true
		# body colour ramp (16 entries, recomputed per frame)
		var ramp: PackedColorArray = _snake_ramp[i]
		if ramp.size() != 16:
			ramp.resize(16)
		if s.is_player and s.grad.size() >= 4:
			ramp = PSTheme.ramp4(s.grad[0], s.grad[1], s.grad[2], s.grad[3])
		elif s.has_head_color:
			ramp = PSTheme.ramp3(PSTheme.lighten(s.color, 0.28), s.color,
				PSTheme.darken(s.color, 0.30))
		else:
			ramp = PSTheme.ramp3(PSTheme.lighten(s.color, 0.32), s.color,
				PSTheme.darken(s.color, 0.32))
		_snake_ramp[i] = ramp
		# halo tint: the snake's flat colour, or the character's pack palette
		# (the additive halo is the colour a character's gel tube throws on the
		# floor, which is its body colour, not its old procedural ramp).
		var sk: int = PSSkins.of(s)
		_skin[i] = sk if PSSkins.usable(sk) else -1
		_snake_glow[i] = s.color
		_snake_on[i] = true
		# tube rim: the snake's own colour in shadow, pulled toward the web's dark
		# teal contour so a lime and a violet snake still share one material.
		var dark: Color = PSTheme.darken(s.color, 0.55)
		_snake_rim[i] = Color(
			lerpf(BODY_RIM_COL.r, dark.r, RIM_TINT_MIX),
			lerpf(BODY_RIM_COL.g, dark.g, RIM_TINT_MIX),
			lerpf(BODY_RIM_COL.b, dark.b, RIM_TINT_MIX), RIM_A)
		if _skin[i] >= 0:
			var skin: Dictionary = PSSkins.get_skin(_skin[i])
			_snake_glow[i] = skin["halo"]
			_snake_rim[i] = skin["rim"]
		_update_anim(i, s)
		# Contiguous visible run -> densify only that span (head/tail caps then stay
		# where they really are, off-screen: `_snake_cap[i]` selects them).
		if inside >= 2 and inside == i1 - i0 + 1 and i1 - i0 + 1 < n:
			_snake_i0[i] = i0
			_snake_i1[i] = i1
		else:
			_snake_i0[i] = 0
			_snake_i1[i] = n - 1
		_build_dense_body(i, buf, n, r * zoom, int(_snake_i0[i]), int(_snake_i1[i]))
		i += 1


## Densify one snake's screen polyline (owner fix A: "subdivide the centreline").
##
## Each simulated segment becomes `kk` slices where `kk` grows with the local turn
## angle (1 on a straight run, up to `MAX_SUB` on a bend), so a bend is drawn as a
## smooth curve while a straight run costs nothing extra. Position, **radius** and
## the ramp parameter `t` are interpolated per slice; `PSTheme.band_normals` then
## averages the two adjacent directions per point, which is what makes the offset
## rim a smooth outline instead of a chain of chords.
##
## `kk` is capped by what is left of `DENSE_BUDGET` so the shared triangle array
## can never overflow and no snake is ever dropped: worst case every snake falls
## back to 1 slice per segment (the B3 density).
##
## `i0`/`i1` restrict the build to a contiguous **visible** run of the simulated
## polyline (see `_collect_snakes`). The ramp parameter `t` stays the GLOBAL one
## (`k / (n-1)`), so a clipped body keeps exactly the colours it had in full, and
## its sliced ends sit off-screen (the clip rect is grown by 96 px).
func _build_dense_body(slot: int, buf: PackedVector2Array, n: int, r: float,
		i0: int = 0, i1: int = -1) -> void:
	if i1 < i0:
		i1 = n - 1
	var dpts: PackedVector2Array = _snake_dpts[slot]
	var dnrm: PackedVector2Array = _snake_nrm[slot]
	var drad: PackedFloat32Array = _snake_drad[slot]
	var dts: PackedFloat32Array = _snake_dts[slot]
	var dmrk: PackedByteArray = _snake_dmrk[slot]
	var span: int = i1 - i0 + 1
	# per-segment slice counts
	if _sub_counts.size() < span:
		_sub_counts.resize(span)
	var counts: PackedInt32Array = _sub_counts
	var total := 1
	var k_cap := clampi(int(float(DENSE_BUDGET - _dense_used) / float(span)), 1, MAX_SUB)
	var k := i0
	while k < i1:
		var kk := 1
		if k_cap > 1:
			kk = clampi(int(ceil(_turn_at(buf, k, n) / SUB_ANGLE)), 1, k_cap)
		counts[k - i0] = kk
		total += kk
		k += 1
	dpts.resize(total)
	dnrm.resize(total)
	drad.resize(total)
	dts.resize(total)
	dmrk.resize(total)
	var inv := 1.0 / float(n - 1)
	var w := 0
	k = i0
	while k < i1:
		var kk: int = counts[k - i0]
		var pa: Vector2 = buf[k]
		var pb: Vector2 = buf[k + 1]
		var j := 0
		while j < kk:
			var f := float(j) / float(kk)
			var tt := (float(k) + f) * inv
			dpts[w] = pa.lerp(pb, f)
			dts[w] = tt
			drad[w] = r * (1.0 + (TAPER_TAIL - 1.0) * pow(tt, TAPER_POW))
			dmrk[w] = 1 if (j == 0 and (k % 2) == 0) else 0
			w += 1
			j += 1
		k += 1
	dpts[w] = buf[i1]
	dts[w] = float(i1) * inv
	drad[w] = r * (1.0 + (TAPER_TAIL - 1.0) * pow(float(i1) * inv, TAPER_POW))
	dmrk[w] = 0
	w += 1
	_dense_used += w
	PSTheme.band_normals(dpts, dnrm)
	_snake_dpts[slot] = dpts
	_snake_nrm[slot] = dnrm
	_snake_drad[slot] = drad
	_snake_dts[slot] = dts
	_snake_dmrk[slot] = dmrk


## Direction change (radians) at logical point `k`, using its two neighbours: this
## is the angle the body actually bends through at that joint.
func _turn_at(buf: PackedVector2Array, k: int, n: int) -> float:
	var a: Vector2 = buf[k]
	var b: Vector2 = buf[mini(k + 1, n - 1)] - a
	var c: Vector2 = a - buf[maxi(k - 1, 0)]
	if b.length_squared() < 1e-8 or c.length_squared() < 1e-8:
		return 0.0
	return absf(b.angle_to(c))


## Per-snake expression state, advanced once per frame (no allocation: the dict
## lives in `_anim` from `_init`).
##
## Triggers are the only inputs: eating a pellet and swallowing a rival both pop
## the mouth open + squash the head; blinking and the idle tongue flick are on
## their own timers. The RNG is a private LCG so two runs of the same round draw
## the same blinks (the A/B capture harness depends on that).
func _update_anim(slot: int, s) -> void:
	var a: Dictionary = _anim[slot]
	var dt: float = clampf(time - float(a["t"]), 0.0, 0.1)
	a["t"] = time
	var food: int = int(s.food_eaten)
	var kills: int = int(s.kills)
	if food > int(a["food"]) or kills > int(a["kills"]):
		a["tongue"] = TONGUE_SEC
		a["squash"] = 1.0
		a["next_t"] = time + 2.2 + _anim_rand(a) * 2.4
	a["food"] = food
	a["kills"] = kills
	a["squash"] = maxf(0.0, float(a["squash"]) - dt * 3.4)
	a["tongue"] = maxf(0.0, float(a["tongue"]) - dt)
	a["blink"] = maxf(0.0, float(a["blink"]) - dt)
	if float(a["blink"]) <= 0.0 and time >= float(a["next"]):
		a["blink"] = BLINK_SEC
		# 1 in 4 blinks is a double blink
		a["next"] = time + (0.12 if _anim_rand(a) < 0.25 else 3.0 + _anim_rand(a) * 2.8)
	if float(a["tongue"]) <= 0.0 and time >= float(a["next_t"]):
		a["tongue"] = TONGUE_SEC
		a["next_t"] = time + 2.6 + _anim_rand(a) * 2.8


func _anim_rand(a: Dictionary) -> float:
	var st: int = int(a["rng"])
	st = (st * 1664525 + 1013904223) & 0xFFFFFFFF
	a["rng"] = st
	return float(st & 0xFFFF) / 65535.0


func _draw_bands() -> void:
	# Off-screen slice clipping: a long snake is mostly outside the view, so the
	# band appenders skip every slice whose endpoints are both outside this rect.
	# 96 px covers the widest thing attached to a slice (the halo pad + rim).
	var vis := PSTheme.vis_rect(view, 96.0)
	# Pass 1: every snake's rim, untextured, **one** command. Drawing all rims
	# before any body keeps the rule "a rim is never painted over another snake's
	# body" without needing one command per snake.
	var rv := _rim_v
	var rc := _rim_c
	var ri := _rim_i
	rv.resize(0)
	rc.resize(0)
	ri.resize(0)
	var i := 0
	while i < MAX_SNAKES:
		if _snake_on[i]:
			var pts: PackedVector2Array = _snake_dpts[i]
			if pts.size() >= 2:
				# Caps only where the body really ends: a clipped run ends off-screen,
				# so a disc there would be wasted geometry (and would poke into view
				# if the clip rect were ever tightened below the rim width).
				var full: int = game.snakes[i].body.size()
				var cap_h: bool = int(_snake_i0[i]) == 0
				var cap_t: bool = int(_snake_i1[i]) == full - 1
				PSTheme.band_rim_append(rv, rc, ri, pts, _snake_nrm[i],
					_snake_drad[i], _snake_rim[i], RIM_W * zoom, cap_h, cap_t, vis,
					RIM_FEATHER)
		i += 1
	PSTheme.band_flush(self, rv, rc, ri)
	# Pass 2: the bodies. A snake with a character texture is one textured
	# `canvas_item_add_triangle_array` (the tube is a single opaque quad per dense
	# slice, so there is nothing per-segment to flush); snakes whose assets are
	# missing keep the old procedural stack, batched into one command.
	_draw_body_stack()
	i = 0
	while i < MAX_SNAKES:
		if _snake_on[i] and _skin[i] >= 0:
			_draw_skin_body(i, _skin[i])
		i += 1


## One snake's body from its character's tube texture: `u` across the tube, `v`
## along it, one command.
func _draw_skin_body(slot: int, skin_idx: int) -> void:
	var tex := PSSkins.body_tex(skin_idx)
	if tex == null:
		return
	var pts: PackedVector2Array = _snake_dpts[slot]
	if pts.size() < 2:
		return
	var v := _tb_v
	var c := _tb_c
	var uv := _tb_uv
	var idx := _tb_i
	v.resize(0)
	c.resize(0)
	uv.resize(0)
	idx.resize(0)
	var s = game.snakes[slot]
	var aura := Color(0.0, 0.0, 0.0, 0.0)
	var aura_mul := 0.0
	if s.has_buff(0):
		aura = Color(1.0, 0.62, 0.12, 0.22 * (0.55 + 0.15 * sin(time * 9.0)))
		aura_mul = 0.92
	PSTheme.band_tex_append(v, c, uv, idx, pts, _snake_nrm[slot], _snake_drad[slot],
		_snake_dts[slot], TEX_LAT, aura, aura_mul,
		BODY_TILE_MUL * 2.0 * _snake_r[slot] * zoom, PSTheme.vis_rect(view, 96.0))
	if idx.size() > 0:
		_bodies_drawn += 1
	PSTheme.flush_tex(self, v, c, uv, idx, tex)


## Snake halo — the additive pass.
##
## The web draws ONE `lighter` stroke of `rgba(snake.color,0.13)` at half-width
## `R + 15` (`render.js:492-500`). The port used to draw three normal-blend ribbons
## (.085 each at `r+26/+16/+8`), which is what made the body look like it dragged
## a grey vapour trail: alpha blending *desaturates* toward the snake colour
## instead of adding light to the floor (ART-DIFF §1.4 + §6.3 check 3).
##
## Drawn on top of the bodies as the outer annulus only: the inner edge starts just
## outside the body's contour, so no part of it can tint the snake's own tube, and
## where two snakes run side by side a later halo lighting an earlier body is
## exactly what the web does too.
func _draw_glow(ci: CanvasItem) -> void:
	var v := _glow_v
	var c := _glow_c
	var idx := _glow_i
	v.resize(0)
	c.resize(0)
	idx.resize(0)
	var i := 0
	while i < MAX_SNAKES:
		if not _snake_on[i]:
			i += 1
			continue
		var col: Color = _snake_glow[i]
		var cin := Color(col.r, col.g, col.b, HALO_A_IN)
		var cout := Color(col.r, col.g, col.b, HALO_A_OUT)
		PSTheme.band_halo_append(v, c, idx, _snake_dpts[i], _snake_nrm[i],
			_snake_drad[i], cin, cout, HALO_PAD - HALO_GAP, HALO_PAD_TAIL,
			PSTheme.vis_rect(view, 96.0))
		i += 1
	PSTheme.band_flush(ci, v, c, idx)


## The tube: a smooth offset rim (with round caps) under an ordered stack of
## per-slice body layers, all in one triangle array.
##
## Depth rule (unchanged since B2, the owner's requirement): the stack is appended
## tail -> head slice by slice, and every slice starts with an **opaque** under-fill,
## so an overlap always resolves as "later covers earlier" and no translucent layer
## can ever be doubled.
##
## B4 lighting stack (per slice):
##   1. under-fill  the ramp darkened by `TUBE_UNDER` — the tube's inner wall
##   2. gel         translucent ramp, laterally shaded (top lit / bottom shaded)
##   3. core        bright inner stripe, tinted toward white, offset up
##   4. aura        boost only (warm inner shimmer)
##   5. sheen       the web's white `.22` top highlight, offset `-0.36 r`
##   6. scale arc   `#EBFFE1` arc on every 2nd simulated point
func _draw_body_stack() -> void:
	var v := _body_v
	var c := _body_c
	var idx := _body_i
	v.resize(0)
	c.resize(0)
	idx.resize(0)
	_bodies_drawn = 0
	_bodies_dropped = 0
	var i := 0
	while i < MAX_SNAKES:
		if not _snake_on[i] or _skin[i] >= 0:
			i += 1
			continue
		var s = game.snakes[i]
		var pts: PackedVector2Array = _snake_dpts[i]
		if pts.size() >= 2:
			var aura := Color(0.0, 0.0, 0.0, 0.0)
			var aura_mul := 0.0
			if s.has_buff(0):
				# inner heat shimmer, drawn *over* the body so the boost reads warm
				# without the hard halo edge a normal-blend band would leave.
				aura = Color(1.0, 0.62, 0.12, 0.26 * (0.55 + 0.15 * sin(time * 9.0)))
				aura_mul = 0.92
			var ok := PSTheme.band_stack_append(v, c, idx, pts, _snake_nrm[i],
				_snake_drad[i], _snake_dts[i], _snake_dmrk[i], _snake_ramp[i],
				_snake_tube[i], SHEEN_COL, SHEEN_HALF, aura, aura_mul, RIDGE_COL,
				0.36, 0.55, 0.2, 12, PSTheme.vis_rect(view, 96.0))
			if PSTheme.last_capped:
				# The shared triangle array is full: draw what is in it and give this
				# snake a fresh one. A long field therefore costs one extra draw call
				# per overflow instead of losing the snake entirely (which is what
				# happened at 8 x 240 segments: `verts > 65000` silently dropped the
				# bodies of the last snakes while their heads still drew).
				PSTheme.band_flush(self, v, c, idx)
				v.resize(0)
				c.resize(0)
				idx.resize(0)
				ok = PSTheme.band_stack_append(v, c, idx, pts, _snake_nrm[i],
					_snake_drad[i], _snake_dts[i], _snake_dmrk[i], _snake_ramp[i],
					_snake_tube[i], SHEEN_COL, SHEEN_HALF, aura, aura_mul, RIDGE_COL,
					0.36, 0.55, 0.2, 12, PSTheme.vis_rect(view, 96.0))
			if ok:
				_bodies_drawn += 1
			else:
				_bodies_dropped += 1
		i += 1
	PSTheme.band_flush(self, v, c, idx)


# ------------------------------------------------------------------- heads

func _draw_heads() -> void:
	var snakes: Array = game.snakes
	var i := 0
	while i < MAX_SNAKES:
		if not _snake_on[i]:
			i += 1
			continue
		var s = snakes[i]
		var buf: PackedVector2Array = _snake_pts[i]
		var head: Vector2 = buf[0]
		if head.x < -160.0 or head.y < -160.0 or head.x > view.x + 160.0 or head.y > view.y + 160.0:
			i += 1
			continue
		var hr: float = _snake_r[i] * zoom * 1.38
		# status rings under the head
		if s.is_immune() and s.alive:
			var ra: float = 0.5 if s.is_frozen() else 0.3
			draw_arc(head, hr * 1.95, 0.0, TAU, 24, Color(1, 1, 1, ra), maxf(1.5, 2.0 * zoom), false)
		if s.is_player and s.is_frozen():
			var fr: float = hr * 2.45 + sin(time * 9.0) * 3.0
			draw_arc(head, fr, 0.0, TAU, 28, Color(0.71, 1.0, 0.34, 0.9),
				maxf(2.0, 4.0 * zoom), false)
		# magnet radius
		if s.has_buff(1):
			draw_arc(head, cfg.powerups.magnet.radius * zoom, 0.0, TAU, 40,
				PSTheme.with_a(cfg.powerups.magnet.color, 0.30), maxf(1.5, 2.5 * zoom), false)
		# dark rim so the head reads against any body colour (the pack's art
		# carries its own outline, so a textured head skips it)
		var sk: int = _skin[i]
		if not PSSkins.usable(sk):
			draw_set_transform(head, s.heading, Vector2(1.06, 1.0))
			draw_circle(Vector2(hr * 0.06, 0.0), hr * 1.08, Color(0.02, 0.09, 0.11, 0.7))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if s.is_player:
				_draw_player_head(s, head, hr)
			else:
				_draw_npc_head(s, head, hr)
		else:
			_draw_skin_head(s, head, hr, i, sk)
		if not s.is_player:
			var label: String = s.display_name
			if s.style_label != "":
				label += " · " + s.style_label
			# the label follows the character's palette, not the old procedural one
			var lc: Color = s.color
			if PSSkins.usable(sk):
				lc = PSSkins.get_skin(sk)["halo"]
			PSTheme.text_c(self, head.x, head.y - hr * 2.4, label, int(15.0 * zoom),
				PSTheme.with_a(lc, 0.95))
			if s.mistake and not s.is_frozen():
				var by := head.y - hr * 3.4 + sin(time * 8.0) * 3.0
				draw_circle(Vector2(head.x + hr * 1.4, by), 13.0 * zoom, Color(1, 0.84, 0.31, 0.95))
				PSTheme.text_c(self, head.x + hr * 1.4, by + 6.0 * zoom, "?", int(18.0 * zoom),
					Color(0.23, 0.13, 0.0))
		if s.is_player and (s.has_buff(0) or s.has_buff(1)):
			var txt := ""
			if s.has_buff(0):
				txt = "加速 %.1fs" % s.buff_left(0)
			if s.has_buff(1):
				txt += ("  " if txt != "" else "") + "磁铁 %.1fs" % s.buff_left(1)
			PSTheme.text_c(self, head.x, head.y - hr * 3.1, txt, int(17.0 * zoom),
				Color(1.0, 0.96, 0.76))
		i += 1


## A character head from its own atlas: four alpha-blended quads in the pack's
## own order — `head -> eyes(variant) -> mouth(variant) -> decor` — appended to
## one triangle array and flushed with that character's atlas, i.e. **one draw
## call per head** for any expression. The atlas regions keep the pack's shared
## anchor offsets, so the whole head rotates about the head point.
##
## The `+Y` (down) axis of the pack canvas is the snake's heading: the transform
## rotates by `heading - PI/2`, which is also why the eyes end up side by side
## across the body instead of one in front of the other.
##
## Expression state comes from `_anim` (blink / tongue / eat squash) and only
## changes which region rect is sampled or how the quads are transformed, never
## the draw-call count.
func _draw_skin_head(s, head: Vector2, hr: float, slot: int, sk: int) -> void:
	var tex := PSSkins.atlas_tex(sk)
	if tex == null:
		return
	var a: Dictionary = _anim[slot]
	var sc: float = (PSData.HEAD_W_MUL * hr) / (PSData.HEAD_HALF_W * PSData.ATLAS_K)
	if sc <= 0.0:
		return
	var sq: float = float(a["squash"])
	var phase: float = float(a["phase"])
	var rot: float = s.heading - PI * 0.5 + sin(time * 2.1 + phase) * HEAD_TILT
	var ax := Vector2(cos(rot), sin(rot)) * sc * (1.0 - EAT_SQUASH_X * sq)
	var ay := Vector2(-sin(rot), cos(rot)) * sc * (1.0 + EAT_SQUASH_Y * sq)
	var org: Vector2 = head + ay * (sin(time * 3.4 + phase) * hr * HEAD_BOB)
	var blink: float = float(a["blink"])
	var eyes := "eyes_open"
	if blink > BLINK_SEC - BLINK_HALF:
		eyes = "eyes_half"
	elif blink > 0.0:
		eyes = "eyes_closed"
	var tongue: bool = float(a["tongue"]) > 0.0
	var mouth := "mouth_open" if tongue else "mouth_closed"
	var v := _hd_v
	var c := _hd_c
	var uv := _hd_uv
	var idx := _hd_i
	v.resize(0)
	c.resize(0)
	uv.resize(0)
	idx.resize(0)
	var atl := PSSkins.atlas_size(sk)
	var keys := ["head", eyes, mouth, "decor"]
	var k := 0
	while k < 4:
		var key: String = keys[k]
		var rect := PSSkins.region(sk, key)
		var off := PSSkins.region_off(sk, key)
		if key == mouth and tongue:
			# tongue flick: the mouth art rides forward and wobbles for ~0.28 s
			# (atlas texels; ~1.5 px at the shipping head size)
			off += Vector2(0.0, sin(time * 42.0) * 2.2 + 2.2)
		PSTheme.atlas_quad_append(v, c, uv, idx, atl, org, ax, ay, off, rect, Color.WHITE)
		k += 1
	PSTheme.flush_tex(self, v, c, uv, idx, tex)


## Human head: white eyes that follow the nearest pellet, tongue flick, mouth.
func _draw_player_head(s, head: Vector2, hr: float) -> void:
	var base: Color = s.head_color if s.has_head_color else Color("B6FF57")
	var ang: float = s.heading
	var look := ang
	if s.has_look_at and s.body.size() > 0:
		var h: Vector2 = s.body[0]
		look = atan2(s.look_at.y - h.y, s.look_at.x - h.x)
	var local := look - ang
	var open: float = clampf(s.pulse[0] * 1.1, 0.0, 1.0) if s.pulse.size() > 0 else 0.0
	# head disc (slightly oval: x radius 1.06)
	draw_set_transform(head, ang, Vector2(1.06, 1.0))
	draw_circle(Vector2(hr * 0.06, 0.0), hr, base)
	draw_set_transform(head, ang, Vector2.ONE)
	draw_circle(Vector2(-hr * 0.22, -hr * 0.42), hr * 0.52, Color(1, 1, 1, 0.16))
	# tongue
	var cyc := fmod(time, 1.8) / 1.8
	if cyc < 0.28 or open > 0.1:
		var et := sin((cyc / 0.28) * PI) if cyc < 0.28 else 0.0
		var ln := hr * (0.55 + et * 0.75 + open * 0.5)
		var c: Color = Color("FF3D6E")
		draw_line(Vector2(hr * 0.85, 0.0), Vector2(hr * 0.85 + ln * 0.7, 0.0), c,
			maxf(1.5, 4.5 * zoom))
		var bx := hr * 0.85 + ln * 0.7
		draw_line(Vector2(bx, 0.0), Vector2(bx + ln * 0.32, -ln * 0.22), c, maxf(1.2, 3.5 * zoom))
		draw_line(Vector2(bx, 0.0), Vector2(bx + ln * 0.32, ln * 0.22), c, maxf(1.2, 3.5 * zoom))
	# eyes
	var eye_fwd := hr * 0.32
	var eye_side := hr * 0.52
	var eye_r := hr * 0.34
	var ox := cos(local) * eye_r * 0.34
	var oy := sin(local) * eye_r * 0.34
	for si in 2:
		var sgn: float = -1.0 if si == 0 else 1.0
		var ey: float = sgn * eye_side
		draw_circle(Vector2(eye_fwd, ey), eye_r, Color(1, 1, 1, 1))
		draw_circle(Vector2(eye_fwd + ox + eye_r * 0.1, ey + oy * 0.9), eye_r * 0.58,
			Color(0.08, 0.13, 0.06))
		draw_circle(Vector2(eye_fwd + ox + eye_r * 0.28, ey + oy * 0.9 - eye_r * 0.28),
			eye_r * 0.19, Color(1, 1, 1, 0.95))
		if open > 0.3:
			draw_circle(Vector2(eye_fwd, ey), eye_r * 1.05,
				PSTheme.with_a(base, clampf((open - 0.3) * 1.6, 0.0, 0.9)))
	# mouth
	if open > 0.12:
		draw_circle(Vector2(hr * 0.78, 0.0), hr * (0.16 + open * 0.3), Color(0.23, 0.06, 0.13))
		draw_circle(Vector2(hr * 0.82, 0.0), hr * (0.08 + open * 0.12), Color("FF6B8A"))
	else:
		draw_arc(Vector2(hr * 0.42, 0.0), hr * 0.42, -0.55, 0.55, 10, Color(0.05, 0.24, 0.14, 0.85),
			maxf(1.5, 4.0 * zoom), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## NPC heads: nine recognisable procedural faces (the Web prototype's heads.js).
func _draw_npc_head(s, head: Vector2, hr: float) -> void:
	var base: Color = s.head_color if s.has_head_color else PSTheme.lighten(s.color, 0.26)
	var style: StringName = s.head_style
	var ang: float = s.heading
	var t := time
	draw_set_transform(head, ang, Vector2(1.06, 1.0))
	draw_circle(Vector2(hr * 0.06, 0.0), hr, base)
	draw_set_transform(head, ang, Vector2.ONE)
	draw_circle(Vector2(-hr * 0.22, -hr * 0.42), hr * 0.5, Color(1, 1, 1, 0.14))
	match style:
		&"googly":
			for sgn in [-1.0, 1.0]:
				var wy := sin(t * 4.4 + (0.0 if sgn > 0.0 else 2.1)) * hr * 0.06
				draw_circle(Vector2(hr * 0.40, sgn * hr * 0.32), hr * 0.40, Color(1, 1, 1, 1))
				draw_circle(Vector2(hr * 0.28, sgn * hr * 0.18 + wy), hr * 0.18,
					Color(0.06, 0.10, 0.08))
			draw_arc(Vector2(hr * 0.74, -hr * 0.22), hr * 0.2, PI * 0.1, PI * 0.9, 8,
				Color(0.05, 0.18, 0.12, 0.8), maxf(1.5, 4.0 * zoom), false)
		&"bucktooth":
			for sgn in [-1.0, 1.0]:
				draw_arc(Vector2(hr * 0.34, sgn * hr * 0.44), hr * 0.2, PI * 1.1, PI * 1.9, 8,
					Color(0.07, 0.16, 0.11), maxf(1.5, 3.5 * zoom), false)
			draw_circle(Vector2(hr * 0.72, 0.0), hr * 0.34, Color(0.29, 0.05, 0.13))
			draw_rect(Rect2(hr * 0.52, -hr * 0.34, hr * 0.44, hr * 0.26), Color(1, 0.99, 0.94))
			draw_rect(Rect2(hr * 0.52, hr * 0.06, hr * 0.44, hr * 0.26), Color(1, 0.99, 0.94))
		&"moustache":
			for sgn in [-1.0, 1.0]:
				draw_circle(Vector2(hr * 0.20, sgn * hr * 0.44), hr * 0.20, Color(1, 1, 1, 1))
				draw_circle(Vector2(hr * 0.27, sgn * hr * 0.43), hr * 0.10, Color(0.10, 0.09, 0.07))
				draw_line(Vector2(hr * 0.02, sgn * hr * 0.68), Vector2(hr * 0.44, sgn * hr * 0.62),
					Color(0.14, 0.10, 0.07), maxf(1.5, 5.5 * zoom))
			draw_colored_polygon(PackedVector2Array([
				Vector2(hr * 0.96, -hr * 0.06), Vector2(hr * 0.40, -hr * 0.80),
				Vector2(hr * 0.44, -hr * 0.12)]), Color(0.17, 0.11, 0.08))
			draw_colored_polygon(PackedVector2Array([
				Vector2(hr * 0.96, hr * 0.06), Vector2(hr * 0.40, hr * 0.80),
				Vector2(hr * 0.44, hr * 0.12)]), Color(0.17, 0.11, 0.08))
			draw_circle(Vector2(hr * 0.88, 0.0), hr * 0.20, Color(0.84, 0.26, 0.48))
		&"shocked":
			for sgn in [-1.0, 1.0]:
				draw_circle(Vector2(hr * 0.30, sgn * hr * 0.42), hr * 0.34, Color(1, 1, 1, 1))
				draw_circle(Vector2(hr * 0.34, sgn * hr * 0.42), hr * 0.075, Color(0.05, 0.09, 0.07))
				draw_line(Vector2(hr * 0.06, sgn * hr * 0.80), Vector2(hr * 0.50, sgn * hr * 0.80),
					Color(0.09, 0.16, 0.11), maxf(1.5, 5.0 * zoom))
			draw_circle(Vector2(hr * 0.88, 0.0), hr * 0.17, Color(0.23, 0.06, 0.13))
		&"glitch":
			var off := sin(t * 6.5) * hr * 0.18
			draw_circle(Vector2(hr * 0.06 + off, 0.0), hr * 0.98, Color(0, 1, 0.88, 0.20))
			draw_circle(Vector2(hr * 0.06 - off, 0.0), hr * 0.98, Color(1, 0, 0.78, 0.20))
			for sgn in [-1.0, 1.0]:
				draw_rect(Rect2(hr * 0.16, sgn * hr * 0.46 - hr * 0.18, hr * 0.38, hr * 0.36),
					Color(1, 1, 1, 1))
				draw_rect(Rect2(hr * 0.32, sgn * hr * 0.46 - hr * 0.09, hr * 0.18, hr * 0.18),
					Color(0.04, 0.06, 0.07))
			draw_line(Vector2(hr * 0.70, -hr * 0.30), Vector2(hr * 0.98, 0.0),
				Color(0.04, 0.06, 0.07), maxf(1.5, 3.5 * zoom))
			draw_line(Vector2(hr * 0.98, 0.0), Vector2(hr * 0.86, hr * 0.26),
				Color(0.04, 0.06, 0.07), maxf(1.5, 3.5 * zoom))
		&"lowpoly":
			draw_colored_polygon(PackedVector2Array([
				Vector2(hr * 1.06, 0.0), Vector2(hr * 0.5, -hr * 0.92), Vector2(-hr * 0.9, -hr * 0.42),
				Vector2(-hr * 0.9, hr * 0.42), Vector2(hr * 0.5, hr * 0.92)]),
				PSTheme.darken(base, 0.12))
			draw_colored_polygon(PackedVector2Array([
				Vector2(hr * 0.62, -hr * 0.30), Vector2(hr * 1.04, -hr * 0.06),
				Vector2(hr * 0.55, hr * 0.20)]), Color(1, 1, 1, 0.92))
			draw_colored_polygon(PackedVector2Array([
				Vector2(hr * 0.58, hr * 0.30), Vector2(hr * 1.02, hr * 0.14),
				Vector2(hr * 0.50, hr * 0.56)]), Color(1, 1, 1, 0.92))
			draw_colored_polygon(PackedVector2Array([
				Vector2(hr * 0.74, -hr * 0.16), Vector2(hr * 0.94, -hr * 0.09),
				Vector2(hr * 0.76, -hr * 0.02)]), Color(0.05, 0.10, 0.08))
			draw_colored_polygon(PackedVector2Array([
				Vector2(hr * 0.74, hr * 0.16), Vector2(hr * 0.94, hr * 0.11),
				Vector2(hr * 0.76, hr * 0.04)]), Color(0.05, 0.10, 0.08))
			draw_line(Vector2(hr * 0.62, hr * 0.62), Vector2(hr * 0.96, hr * 0.76),
				Color(0.05, 0.10, 0.08), maxf(1.2, 3.0 * zoom))
		&"pixel":
			var sz := hr * 0.55
			draw_rect(Rect2(-sz * 1.75, -sz * 1.75, sz * 3.5, sz * 3.5), base)
			draw_rect(Rect2(-sz * 1.75, -sz * 1.75, sz * 3.5, sz * 0.55),
				PSTheme.darken(base, 0.22))
			for sgn in [-1.0, 1.0]:
				draw_rect(Rect2(sz * 0.2, sgn * sz * 1.05 - sz * 0.5, sz * 1.05, sz), Color(1, 1, 1, 1))
				draw_rect(Rect2(sz * 0.55, sgn * sz * 1.05 - sz * 0.3, sz * 0.42, sz * 0.6),
					Color(0.05, 0.08, 0.07))
			for k in 3:
				var bx := -sz * 0.2
				draw_rect(Rect2(bx, -sz * 0.1 + float(k) * sz * 0.42, sz * 1.5, sz * 0.2),
					Color(0.05, 0.08, 0.07))
		&"neon":
			draw_circle(Vector2.ZERO, hr * 1.02, Color(0.04, 0.06, 0.12, 0.85))
			draw_arc(Vector2.ZERO, hr * 1.02, 0.0, TAU, 28, PSTheme.lighten(base, 0.35),
				maxf(2.0, 4.0 * zoom), false)
			for sgn in [-1.0, 1.0]:
				draw_circle(Vector2(hr * 0.34, sgn * hr * 0.40), hr * 0.30, Color(1, 1, 1, 0.95))
				draw_circle(Vector2(hr * 0.40, sgn * hr * 0.40), hr * 0.16,
					PSTheme.lighten(base, 0.5))
			draw_line(Vector2(hr * 0.5, -hr * 0.1), Vector2(hr * 0.5, hr * 0.1),
				PSTheme.lighten(base, 0.4), maxf(1.5, 3.0 * zoom))
		&"block":
			var b2 := hr * 0.92
			draw_rect(Rect2(-b2, -b2 * 0.95, b2 * 2.0, b2 * 1.9), base)
			draw_rect(Rect2(-b2, -b2 * 0.95, b2 * 2.0, b2 * 0.28), PSTheme.lighten(base, 0.3))
			draw_rect(Rect2(-b2, b2 * 0.67, b2 * 2.0, b2 * 0.28), PSTheme.darken(base, 0.3))
			for sgn in [-1.0, 1.0]:
				draw_rect(Rect2(b2 * 0.1, sgn * b2 * 0.62 - b2 * 0.34, b2 * 0.7, b2 * 0.55),
					Color(1, 1, 1, 0.96))
				draw_rect(Rect2(b2 * 0.42, sgn * b2 * 0.62 - b2 * 0.2, b2 * 0.3, b2 * 0.32),
					Color(0.05, 0.09, 0.07))
			draw_rect(Rect2(b2 * 0.55, -b2 * 0.18, b2 * 0.45, b2 * 0.36), Color(0.14, 0.05, 0.11))
		_:
			# classic face (no style assigned): simple side eyes + smile
			for sgn in [-1.0, 1.0]:
				draw_circle(Vector2(hr * 0.32, sgn * hr * 0.5), hr * 0.3, Color(1, 1, 1, 1))
				draw_circle(Vector2(hr * 0.42, sgn * hr * 0.5), hr * 0.15, Color(0.07, 0.12, 0.07))
			draw_arc(Vector2(hr * 0.52, 0.0), hr * 0.4, -0.6, 0.6, 8, Color(0.05, 0.24, 0.14, 0.85),
				maxf(1.5, 3.5 * zoom), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
