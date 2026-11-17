extends RefCounted
## Workstream C — pooled cosmetics: particles, floating text, shockwaves, shake.
##
## Everything is SoA (Packed arrays) and pre-sized, so a busy frame writes into
## existing slots instead of allocating. Caps: 220 particles / 24 texts / 8 waves.
## The RNG here is a tiny local xorshift: the rules' RNG stream must never be
## touched by the presentation.

const PSTheme = preload("res://src/present/ps_theme.gd")
const PSAssets = preload("res://src/present/ps_assets.gd")

const MAX_P := 220
## Floating-text pool. 24 -> 16: every label is its own draw call (text cannot be
## batched with a different string), and at the cap that was 8 extra calls per world
## view - 16 of the 2P frame's draw budget. 16 simultaneous labels is still more
## than a busy second produces (they live ~1 s and pulse out).
const MAX_T := 16
const MAX_W := 8

## Particle kinds.
const K_SPARK := 0
const K_STAR := 1
const K_CONFETTI := 2

var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pvx := PackedFloat32Array()
var pvy := PackedFloat32Array()
var plife := PackedFloat32Array()
var pttl := PackedFloat32Array()
var psize := PackedFloat32Array()
var prot := PackedFloat32Array()
var pspin := PackedFloat32Array()
var pdrag := PackedFloat32Array()
var pcol := PackedColorArray()
var pkind := PackedByteArray()
var pcount := 0
var _pnext := 0
## Reused buffers for the batched shockwave pass (`draw`): no per-frame alloc.
var _wv := PackedVector2Array()
var _wc := PackedColorArray()

var tx := PackedFloat32Array()
var ty := PackedFloat32Array()
var tvy := PackedFloat32Array()
var tlife := PackedFloat32Array()
var tttl := PackedFloat32Array()
var tsize := PackedFloat32Array()
var tcol := PackedColorArray()
var tstr := PackedStringArray()
var tcount := 0

var wx := PackedFloat32Array()
var wy := PackedFloat32Array()
var wr := PackedFloat32Array()
var wlife := PackedFloat32Array()
var wttl := PackedFloat32Array()
var wcol := PackedColorArray()
var wcount := 0

var shake := 0.0
var flash := 0.0
var flash_col := Color(1, 1, 1)
var time := 0.0

# ------------------------------------------------------------------- shake
##
## Screen shake is a **screen-space px offset** applied to the camera by
## `main.gd::_update_cameras()` (`v.cam = follow_centre + shake / zoom`, so the
## rendered offset is exactly `shake_offset()` px). The request magnitudes at the
## call sites (`add_shake(1.0)` pellet, `2.5` big food, `9.0` any snake death,
## `16.0` extra when the player dies) are left alone on purpose: what the owner
## actually felt as "画面抖动太剧烈" was the *camera whip on every turn*
## (`_update_cameras`), not this. The shake itself stays - the owner asked for the
## eating shake to be kept - and is trimmed by the master knob below.
##
## `SHAKE_SCALE` is the single master knob. 1.0 reproduces the pre-2026-11-14
## behaviour; the build-flag-off tuning panel exposes the **live** copy
## (`shake_scale`) as the last row, so it can be dialled in on the box without a
## rebuild. Shipped value 0.70: 30% smaller than before, still clearly felt.
const SHAKE_SCALE := 0.70
## Hard ceiling on the accumulated amplitude (px). A player death asks for
## 16 + 9 = 25 px -> 17.5 px after the scale; a death *and* a kill in the same
## frame asks for 34 px -> 23.8 px and is clamped here, so stacked events cannot
## compound (the old ceiling was 26 px, hit by a plain death + kill stack).
const SHAKE_MAX_PX := 20.0
## Exponential decay rate, 1/s (7.5 => tau 133 ms: 1/e gone in 5 frames, all of
## it inside ~0.4 s). Unchanged from before the fix.
const SHAKE_DECAY := 7.5
## Onset easing in seconds: 0 = full amplitude on the trigger frame (unchanged).
const SHAKE_ATTACK := 0.0
## Offset carrier: two detuned sines per axis (rad/s), 9.7/15.4 Hz on x and
## 11.3/18.0 Hz on y. Unchanged: a short, high-frequency impact rather than a
## camera sway, so it can never be confused with the follow motion.
const SHAKE_WX1 := 61.0
const SHAKE_WX2 := 97.0
const SHAKE_WY1 := 71.0
const SHAKE_WY2 := 113.0

## Live copy of `SHAKE_SCALE` (the tuning panel's `画面抖动强度` row writes this).
var shake_scale: float = SHAKE_SCALE
## Seconds since the last impulse: drives the attack ramp only.
var _shake_t := 1000.0

var _rs := 0x2545F491


func _init() -> void:
	px.resize(MAX_P)
	py.resize(MAX_P)
	pvx.resize(MAX_P)
	pvy.resize(MAX_P)
	plife.resize(MAX_P)
	pttl.resize(MAX_P)
	psize.resize(MAX_P)
	prot.resize(MAX_P)
	pspin.resize(MAX_P)
	pdrag.resize(MAX_P)
	pcol.resize(MAX_P)
	pkind.resize(MAX_P)
	tx.resize(MAX_T)
	ty.resize(MAX_T)
	tvy.resize(MAX_T)
	tlife.resize(MAX_T)
	tttl.resize(MAX_T)
	tsize.resize(MAX_T)
	tcol.resize(MAX_T)
	tstr.resize(MAX_T)
	wx.resize(MAX_W)
	wy.resize(MAX_W)
	wr.resize(MAX_W)
	wlife.resize(MAX_W)
	wttl.resize(MAX_W)
	wcol.resize(MAX_W)


func reset() -> void:
	pcount = 0
	_pnext = 0
	tcount = 0
	wcount = 0
	shake = 0.0
	flash = 0.0


## Cheap local xorshift32 (presentation only).
func rnd() -> float:
	var x := _rs
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_rs = x & 0xFFFFFFFF
	return float(_rs & 0xFFFF) / 65535.0


func rnd_range(a: float, b: float) -> float:
	return a + (b - a) * rnd()


# ------------------------------------------------------------------ spawn

func particle(x: float, y: float, vx: float, vy: float, ttl: float, size: float,
		col: Color, kind: int, drag: float = 2.6, spin: float = 0.0) -> void:
	var i: int
	if pcount < MAX_P:
		i = pcount
		pcount += 1
	else:
		i = _pnext
		_pnext = (_pnext + 1) % MAX_P
	px[i] = x
	py[i] = y
	pvx[i] = vx
	pvy[i] = vy
	plife[i] = ttl
	pttl[i] = ttl
	psize[i] = size
	pcol[i] = col
	pkind[i] = kind
	pdrag[i] = drag
	prot[i] = rnd_range(0.0, TAU)
	pspin[i] = spin


## A pellet was eaten: a small coloured puff plus a couple of sparkles.
func eat(x: float, y: float, col: Color, big: bool) -> void:
	var n := 7 if not big else 14
	var burst := 150.0 if not big else 260.0
	for i in n:
		var a := rnd_range(0.0, TAU)
		var sp := rnd_range(burst * 0.35, burst)
		particle(x, y, cos(a) * sp, sin(a) * sp, rnd_range(0.22, 0.46),
			rnd_range(4.0, 9.0) if not big else rnd_range(5.0, 12.0),
			col.lerp(Color(1, 1, 1, 1), rnd_range(0.0, 0.35)), K_SPARK, 3.4)
	if big:
		for i in 6:
			var a2 := rnd_range(0.0, TAU)
			var sp2 := rnd_range(90.0, 320.0)
			particle(x, y, cos(a2) * sp2, sin(a2) * sp2, rnd_range(0.35, 0.7),
				rnd_range(7.0, 13.0), Color("FFE88A"), K_STAR, 2.2, rnd_range(-6.0, 6.0))


## A snake died: confetti along the corpse + a big wave.
func death(points: PackedVector2Array, col: Color, head: Vector2) -> void:
	var n := points.size()
	var step := maxi(1, int(ceil(float(n) / 22.0)))
	var i := 0
	while i < n:
		var p := points[i]
		var c := col.lerp(Color(1, 1, 1, 1), rnd_range(0.0, 0.45))
		particle(p.x, p.y, rnd_range(-90.0, 90.0), rnd_range(-120.0, 40.0),
			rnd_range(0.45, 0.95), rnd_range(5.0, 12.0), c,
			K_CONFETTI if (i % 3) == 0 else K_SPARK, 1.9)
		i += step
	wave(head.x, head.y, col, 40.0, 520.0)
	add_shake(9.0)


## Pickup: ring + labelled chip handled by the caller.
func pickup(x: float, y: float, col: Color) -> void:
	wave(x, y, col, 26.0, 300.0)
	for i in 10:
		var a := TAU * float(i) / 10.0
		particle(x + cos(a) * 18.0, y + sin(a) * 18.0, cos(a) * 150.0, sin(a) * 150.0,
			0.34, 7.0, col, K_STAR, 3.0, rnd_range(-8.0, 8.0))


func wave(x: float, y: float, col: Color, r0: float, r1: float) -> void:
	var i: int
	if wcount < MAX_W:
		i = wcount
		wcount += 1
	else:
		i = 0
		for k in range(1, MAX_W):
			if wlife[k] < wlife[i]:
				i = k
	wx[i] = x
	wy[i] = y
	wr[i] = r0
	# encode target radius in ttl: life goes 1 -> 0, radius lerps r0 -> r1
	wttl[i] = maxf(0.001, (r1 - r0) / 900.0)
	wlife[i] = 1.0
	wcol[i] = col


func add_shake(v: float) -> void:
	shake = minf(SHAKE_MAX_PX, shake + v * shake_scale)
	_shake_t = 0.0


func add_flash(a: float, col: Color = Color(1, 1, 1)) -> void:
	flash = minf(0.5, flash + a)
	flash_col = col


func text(x: float, y: float, s: String, col: Color, size: float) -> void:
	var i: int
	if tcount < MAX_T:
		i = tcount
		tcount += 1
	else:
		i = 0
		for k in range(1, MAX_T):
			if tlife[k] < tlife[i]:
				i = k
	tx[i] = x
	ty[i] = y
	tvy[i] = -46.0
	tlife[i] = 1.15
	tttl[i] = 1.15
	tsize[i] = size
	tcol[i] = col
	tstr[i] = s


# ----------------------------------------------------------------- update

func update(dt: float) -> void:
	time += dt
	var k := 0
	while k < pcount:
		plife[k] -= dt
		if plife[k] <= 0.0:
			# swap-remove keeps the live range dense without allocating
			pcount -= 1
			if k != pcount:
				px[k] = px[pcount]
				py[k] = py[pcount]
				pvx[k] = pvx[pcount]
				pvy[k] = pvy[pcount]
				plife[k] = plife[pcount]
				pttl[k] = pttl[pcount]
				psize[k] = psize[pcount]
				prot[k] = prot[pcount]
				pspin[k] = pspin[pcount]
				pdrag[k] = pdrag[pcount]
				pcol[k] = pcol[pcount]
				pkind[k] = pkind[pcount]
			continue
		var drag: float = pdrag[k]
		var damp := 1.0 - minf(0.95, drag * dt)
		pvx[k] *= damp
		pvy[k] *= damp
		px[k] += pvx[k] * dt
		py[k] += pvy[k] * dt
		prot[k] += pspin[k] * dt
		k += 1
	k = 0
	while k < tcount:
		tlife[k] -= dt
		if tlife[k] <= 0.0:
			tcount -= 1
			if k != tcount:
				tx[k] = tx[tcount]
				ty[k] = ty[tcount]
				tvy[k] = tvy[tcount]
				tlife[k] = tlife[tcount]
				tttl[k] = tttl[tcount]
				tsize[k] = tsize[tcount]
				tcol[k] = tcol[tcount]
				tstr[k] = tstr[tcount]
			continue
		ty[k] += tvy[k] * dt
		tvy[k] *= 1.0 - minf(0.9, dt * 2.2)
		k += 1
	k = 0
	while k < wcount:
		wlife[k] -= dt / maxf(0.05, wttl[k])
		if wlife[k] <= 0.0:
			wcount -= 1
			if k != wcount:
				wx[k] = wx[wcount]
				wy[k] = wy[wcount]
				wr[k] = wr[wcount]
				wlife[k] = wlife[wcount]
				wttl[k] = wttl[wcount]
				wcol[k] = wcol[wcount]
			continue
		k += 1
	shake *= exp(-SHAKE_DECAY * dt)
	_shake_t += dt
	if shake < 0.01:
		shake = 0.0
	flash *= exp(-6.0 * dt)


func shake_offset() -> Vector2:
	if shake <= 0.01:
		return Vector2.ZERO
	var env := shake
	if SHAKE_ATTACK > 0.0:
		env *= smoothstep(0.0, SHAKE_ATTACK, _shake_t)
	if env <= 0.01:
		return Vector2.ZERO
	return Vector2(
		sin(time * SHAKE_WX1) * 0.7 + sin(time * SHAKE_WX2) * 0.3,
		cos(time * SHAKE_WY1) * 0.6 + cos(time * SHAKE_WY2) * 0.4) * env


# ------------------------------------------------------------------- draw

## Everything is drawn in screen space (`cam`/`zoom` map world -> screen).
func draw(ci: CanvasItem, cam: Vector2, zoom: float, view: Vector2) -> void:
	var half := view * 0.5
	var pad := 48.0
	# ---- particles ----
	var i := 0
	while i < pcount:
		var t := plife[i] / maxf(0.001, pttl[i])
		var sx := (px[i] - cam.x) * zoom + half.x
		var sy := (py[i] - cam.y) * zoom + half.y
		if sx < -pad or sy < -pad or sx > view.x + pad or sy > view.y + pad:
			i += 1
			continue
		var c: Color = pcol[i]
		var sz: float = psize[i] * zoom * (0.35 + 0.65 * t)
		c.a = c.a * (0.25 + 0.75 * t)
		match pkind[i]:
			K_SPARK:
				ci.draw_texture_rect(PSAssets.dot, Rect2(sx - sz, sy - sz, sz * 2.0, sz * 2.0),
					false, c)
			K_STAR:
				sz *= 1.6
				ci.draw_texture_rect(PSAssets.spark, Rect2(sx - sz, sy - sz, sz * 2.0, sz * 2.0),
					false, c)
			_:
				ci.draw_rect(Rect2(sx - sz * 0.5, sy - sz * 0.5, sz, sz), c)
		i += 1
	# ---- shockwaves ----
	# One batched multiline for every ring: `draw_arc` costs one draw call per
	# wave (8 at the cap), and a ring is just a closed polyline. Trade-off vs the
	# old `draw_arc`: the stroke width is shared by all rings (it used to thin out
	# with each ring's own life). Alpha still fades per segment, so the rings still
	# dissolve the same way.
	if wcount > 0:
		var wv := _wv
		var wc := _wc
		wv.resize(0)
		wc.resize(0)
		var steps := 28
		for k in wcount:
			var t2: float = 1.0 - wlife[k]
			var rr: float = (wr[k] + (wttl[k] * 900.0) * t2) * zoom
			var sx2 := (wx[k] - cam.x) * zoom + half.x
			var sy2 := (wy[k] - cam.y) * zoom + half.y
			var c2: Color = wcol[k]
			c2.a = wlife[k] * 0.55
			var seg_col := Color(c2.r, c2.g, c2.b, c2.a)
			var prev := Vector2(sx2 + rr, sy2)
			for j in steps:
				var a := TAU * float(j + 1) / float(steps)
				var cur := Vector2(sx2 + cos(a) * rr, sy2 + sin(a) * rr)
				wv.append(prev)
				wv.append(cur)
				# `draw_multiline_colors` takes ONE colour per SEGMENT (two points).
				wc.append(seg_col)
				prev = cur
		if wv.size() > 0:
			ci.draw_multiline_colors(wv, wc, maxf(1.5, 2.2 * zoom))
			wv.resize(0)
			wc.resize(0)
	# ---- floating text ----
	i = 0
	while i < tcount:
		var t3: float = tlife[i] / maxf(0.001, tttl[i])
		var sx3 := (tx[i] - cam.x) * zoom + half.x
		var sy3 := (ty[i] - cam.y) * zoom + half.y
		if sx3 > -160.0 and sy3 > -80.0 and sx3 < view.x + 160.0 and sy3 < view.y + 80.0:
			var c3: Color = tcol[i]
			c3.a = clampf(t3 * 1.8, 0.0, 1.0)
			var pop := 1.0 + (1.0 - clampf(t3 * 1.15, 0.0, 1.0)) * 0.55
			var fs := int(maxf(14.0, tsize[i] * zoom * pop))
			PSTheme.text_c(ci, sx3, sy3, tstr[i], fs, c3)
		i += 1
