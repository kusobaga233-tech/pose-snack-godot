extends Control
## Workstream C — HUD: the mode-select (title) screen, the READY slot cards, the
## opening "GO!" beat, the play HUD (the **web console band**: mirror box / clock
## / rank block), the pause layer, the OSD overlay and the debug read-out.
##
## Geometry is the shipped web skin measured at 1920x1080, where CSS px == Godot
## design px 1:1 (`Docs/WEB-COMPUTED-STYLES.md`, §3 + §6.4). The numbers are
## constants below, **not** derived from anything: do not scale them, and do not
## re-anchor to `Docs/ART-DIFF.md` (that document is normalised to 1440x810 and
## its geometry rows are wrong).
##
## One CanvasItem, one `_draw()`. Strings are built at most once per frame per
## widget; the hot path reuses cached text and cached StyleBoxes. Bow to the
## frame budget: every helper here is O(fixed) draws, and the band's background
## stack is four `draw_texture_rect` calls (baked tiles), not a per-line loop.
##
## **Owner-requested divergences from the web** (B1 removed these three for
## pixel parity; the owner wants them back, in play):
##   * the 分数 stat row on the play HUD — the web hides it via `.legacy-stat`
##     (the band owns the clock/rank instead). Restored as a compact 4-cell row
##     under the band with the B1 tokens (36/700 labels, 900-weight values that
##     auto-shrink to fit a 4-digit 分数, radius 3, cyan stroke). 长度/吞并/最佳
##     still ALSO live in the pause layer.
##   * the minimap — the web's `drawMinimap` is dead code (no caller), so there
##     is no web reference for a live one; this is the port's own affordance,
##     restyled with the TV tokens (`rgba(5,12,24,.84)` plate, r3, cyan stroke)
##     and ported geometry from `js/render.js:drawMinimap` for the dot/ring
##     sizes so it still matches the web's *art language*.
##   * the in-play leaderboard — the web's `#leaderboard` is `opacity: 0` outside
##     `body.pause-open`. Restored on the arena's right edge (340 px, the pause
##     width, not the invisible 226 px base) and kept clear of the OSD brackets,
##     the mirror boxes and the score row. The pause layer keeps its own copy.
##
## Flow (mirrors `src/main.gd`):
##   MODE_SELECT (no default) -> MODE_READY (slot cards) -> MODE_COUNTDOWN (GO!)
##   -> MODE_PLAY -> MODE_PAUSE / MODE_SETTLE.
##
## **TV typography floors** (owner: 整体调整字体到合适大小, legibility at ~3 m):
## every player-facing string is sized for 1920x1080 viewed from 3 m, and the
## floors are written next to each block:
##   * critical (mode names, slot status, button labels, bottom hints) >= 32 px
##   * labels / captions (stat labels, leaderboard header, minimap caption,
##     kickers) >= 24 px
##   * meta (units, counts, version strings) >= 18 px
##   * titles >= 48 px (the 58 px H1 and the 56/60 px READY/PAUSE titles)
## The HUD **band** keeps its web-parity numbers (clock 120/96, rank 96/66, band
## labels 36/28) because those are already TV-sized and measured 1:1 off the web.
## Labels with a fixed box go through `PSTheme.text_*_fit`, which shrinks by 2 px
## steps only when the CJK run really does not fit and logs the string ONCE.
##
## The READY screen is the only 1:1 transfer from the Unity 1024 reference
## (`Docs/UI-REFERENCE-1024.md`): 428x624 portrait photo, 436x632 outline, 776 px
## centre spacing, 218x488 gauge, 100x100 head icon, 60 px status, +1400 -> 0
## 0.3 s OutQuad entry. Everything else keeps the port's own layout.

const PSTheme = preload("res://src/present/ps_theme.gd")
const PSAssets = preload("res://src/present/ps_assets.gd")
const PSConfig = preload("res://src/core/config.gd")
const PSSkins = preload("res://src/present/ps_skins.gd")

## Mirrors main.gd — keep the numbers in sync.
const MODE_SELECT := 0
const MODE_PLAY := 1
const MODE_PAUSE := 2
const MODE_SETTLE := 3
const MODE_READY := 4
const MODE_COUNTDOWN := 5

const BTN_NONE := 0
const BTN_RESUME := 5
const BTN_RESTART := 6
const BTN_MENU := 7
const BTN_CAMERA := 8
const BTN_MODE_1P := 10
const BTN_MODE_2P := 11

## Slot states on the READY screen (reference semantics).
const SLOT_WAITING := 0
const SLOT_RAISE := 1
const SLOT_READY := 2

## Input sources (mirrors main.gd).
const SRC_POSE := 0
const SRC_KEYBOARD := 1
const SRC_SYNTH := 2

# ---------------------------------------------------------------- band layout
## `#uiBar` is a full-bleed **radius-0** 200 px band: 197 px of content plus the
## 3 px cyan bottom seam. The arena therefore starts at y=200 and is 1920x880 —
## `PSWorldView` is positioned to that rect by main.gd, so nothing on the play
## screen sits on top of the playfield any more.
const ARENA_TOP := 200.0
const BAND_H := 197.0
const SEAM_H := 3.0
const BAND_PAD := 90.0

## 1P grid `340px 1064px 300px`, column-gap 18, padding 0 90.
const CAM_1P := Rect2(90.0, 10.0, 320.0, 180.0)
const HUD_1P := Rect2(448.0, 23.5, 1064.0, 150.0)
const RANK_1P := Rect2(1530.0, 23.5, 300.0, 150.0)
## 2P grid `268 | 250 | 716 | 250 | 268`, gap 14, padding 0 56.
const CAM_2P_L := Rect2(56.0, 23.13, 268.0, 150.75)
const RANK_2P_L := Rect2(338.0, 23.5, 250.0, 150.0)
const HUD_2P := Rect2(602.0, 23.5, 716.0, 150.0)
const RANK_2P_R := Rect2(1332.0, 23.5, 250.0, 150.0)
const CAM_2P_R := Rect2(1596.0, 23.13, 268.0, 150.75)

## READY camera panes: the same RGBA frame the band's mirror box shows, one pane
## per slot card. 1P shows the whole frame; 2P shows the player's own half with
## the same rule as main.gd's `CAMERA_2P_SRC` and the SDK overlay: slot 0 is the
## LEFT half of the mirrored image, i.e. the raw sensor's RIGHT half. Keep in
## sync with main.gd (`CAMERA_2P_SRC`, mirrored below).
const CAM_FULL_UV := Rect2(0.0, 0.0, 1.0, 1.0)
const CAM_2P_UV := [Rect2(0.5, 0.0, 0.5, 1.0), Rect2(0.0, 0.0, 0.5, 1.0)]

## ---- live skeleton overlay style (see `_draw_pose_skeleton`) ----
## Owner request: "能看见骨骼线". 2 px bones in the SDK cyan at .70, 3 px joints,
## a brighter dot on the steering hand (the RIGHT wrist - right-arm fixed since
## 2026-11-14), and ONE lime reference dot on the RIGHT SHOULDER with its
## dead-zone radius - so the overlay also documents what the mapper is doing.
## Owner: 把之前的胸前点位改到肩膀, 手部点位不变. There is no left-side reference.
const SKEL_BONE_COL := Color(0.337, 0.910, 1.0, 0.70)      # #56e8ff @ .70
const SKEL_JOINT_COL := Color(0.337, 0.910, 1.0, 0.85)
const SKEL_HAND_COL := Color(0.86, 0.98, 1.0, 1.0)
const SKEL_REF_COL := Color(0.714, 1.0, 0.341, 0.95)       # #b6ff57 (the player)
const SKEL_RING_COL := Color(0.714, 1.0, 0.341, 0.42)
const SKEL_ARM_COL := Color(0.337, 0.910, 1.0, 0.35)
## Sentinel for "outside the visible crop": a real design px is never this.
const SKEL_OUT := Vector2(-1.0e9, -1.0e9)
## Bone-segment buffer size: the widest layout table has 10 bones -> 20 points.
const SKEL_SEG_MAX := 24
## Joint buffer: 33 keypoints x 4 points (a dot is a 2-segment cross).
const SKEL_JOINT_MAX := 132

## Type scale + baselines measured off `evidence/web-ref/web-play-1920.png`
## (glyph ink bounds, 1:1). The web cell is `305.578 x 164.594` and overflows the
## 150 px `#hud` cell vertically; only the ink positions matter here.
const CLOCK_CX_1P := 982.0
const CLOCK_CX_2P := 962.0
const CLOCK_SZ := 120
const CLOCK_SZ_2P := 96
const CLOCK_BASE := 168.0
const CLOCK_BASE_2P := 155.0
const CLOCK_LABEL_SZ := 36
const CLOCK_LABEL_SZ_2P := 28
const CLOCK_LABEL_BASE := 57.0
const CLOCK_LABEL_BASE_2P := 59.0
## `#rank` numeral, right-aligned to the block's content edge (1830 - 4 - 8).
const RANK_RIGHT_1P := 1818.0
const RANK_RIGHT_2P := 1586.0
const RANK_LEFT_RIGHT := 578.0
const RANK_SZ := 96
const RANK_SZ_2P := 66
const RANK_BASE := 157.0
const RANK_BASE_2P := 136.0
const RANK_LABEL_SZ := 36
const RANK_LABEL_SZ_2P := 24
const RANK_LABEL_BASE := 57.0
const RANK_LABEL_BASE_2P := 62.0
const RANK_TOTAL_SZ := 24
const RANK_TOTAL_SZ_2P := 19
const RANK_TOTAL_BASE := 182.0
const RANK_TOTAL_BASE_2P := 175.0

## Title slab (`#overlay .panel.title-screen`): 780 x 582.72 at (570, 248.64).
const SLAB := Rect2(570.0, 248.64, 780.0, 582.72)
const SLAB_PAD := 32.0
## Type scale (`#overlay .ps-btn`); the *card* stays the web's 351 px wide and
## grows only in height so the 34 px mode name + 20 px sub-label fit. Adopting the
## reference's 342x138 / 48 px card was explicitly declined by the owner.
const CARD_W := 351.0
const CARD_H := 88.0
const CARD_GAP := 12.0

## Pause layer (`#pauseScrim`, `#pauseStats`, `#leaderboard`).
## Kicker/title are the reference's `frame/title/txtTitle` (60 px) on the port's
## own baselines: the title's ink bottom has to clear the `#pauseStats` top edge
## (318), so 300 + 13 px of descender is the lowest 60 px baseline that does.
const PAUSE_KICKER_BASE := 238.0
const PAUSE_HEAD_BASE := 300.0
const PAUSE_HEAD_SZ := 60
const PAUSE_STATS := Rect2(679.36, 318.0, 561.28, 193.39)
const PAUSE_CELL_W := 120.0
const PAUSE_CELL_H := 110.39
const PAUSE_CELL_Y := 335.0
const PAUSE_CELL_X0 := 767.5
const PAUSE_CELL_STEP := 128.0
const LB := Rect2(1536.0, 248.0, 340.0, 0.0)
const LB_ROW_H := 39.0
## 37 -> 48: the header is a 24 px caption now (typography pass), and the rows
## stay 39 px with their 24 px names.
const LB_HEAD_H := 48.0
## In-play copy of the leaderboard (owner request): same 340 px width as the
## pause one, tucked under the band at the arena's right edge. `x` is 1920 - 44
## (the OSD bracket inset) - 340, so the panel never crosses the bracket arms.
const LB_PLAY_Y := 214.0

## ---- restored play-HUD elements (owner request, web divergence) ----
## Score row: 4 cells of 136 x 118, 6 px apart, starting at the arena's left
## edge + 40 (the OSD bracket ends at x=74). Ends at x=646 — left of the debug
## tuning panel (x>=352) is impossible for four cells, so the panel (build-time
## off, `PSBuild.TUNING_ENABLED`) draws over it in `--capture-tuning` only.
const SCORE_X := 84.0
const SCORE_Y := 208.0
const SCORE_W := 136.0
const SCORE_H := 118.0
const SCORE_GAP := 6.0
const SCORE_LABEL_SZ := 36
const SCORE_VALUE_SZ := 56
const SCORE_LABELS_CJK := ["分数", "长度", "吞并", "最佳"]
const SCORE_LABELS_EN := ["SCORE", "LENGTH", "KILLS", "BEST"]
## Minimap: 208 x 117 world plate (the web's `W = 208`, `H = W * world.h/world.w`)
## plus a 6 px frame, bottom-left. Sits right of the OSD bracket's vertical arm
## (x=44) and above its horizontal arm (y=1036).
const MM_FRAME := 6.0
const MM_W := 208.0
const MM_H := 117.0
const MM_PLATE := Rect2(84.0, 901.0, MM_W + MM_FRAME * 2.0, MM_H + MM_FRAME * 2.0)
const MM_MAP := Rect2(90.0, 907.0, MM_W, MM_H)
const MM_DOT_AI := 2.4
const MM_DOT_ME := 3.4

## ---- always-on perf panel (owner request: 游戏启动后显示实时性能窗口) ----
## Bottom-right, the only corner left free by the shipped HUD:
##   * band              0..200        (mirror box + clock + rank, camera boxes)
##   * score row      84..646 x, 208..326 y
##   * leaderboard  1536..1876 x, 214..~600 y (8 snakes) + buff chips below it
##   * minimap        84..304 x, 901..1030 y
##   * OSD bracket: inset 44 -> the bottom-right vertical arm is x=1876,
##     y 1006..1036, the horizontal arm is y=1036, x 1846..1876
## So: right edge 1876 (same as the leaderboard), bottom 1002 (4 px above the
## bracket arm). 1 header + 7 rows at 26 px + 24 px of padding = 232 px.
## The F3 overlay is the detailed developer read-out (bottom-left); this is the
## compact version that is always up and toggles with F10 / double-tap INFO.
const PERF_PANEL := Rect2(1536.0, 770.0, 340.0, 232.0)
const PERF_ROW_H := 26.0
const PERF_FONT_SZ := 20
const PERF_PAD_X := 14.0
const PERF_PAD_TOP := 27.0
## Label column -> value column offset inside the panel (px). Fixed, so the
## values line up without measuring a string per frame.
const PERF_VAL_DX := 150.0
const PERF_LABEL_COL := Color(0.576, 0.655, 0.769)
const PERF_VALUE_COL := Color(0.918, 0.957, 1.0)

var game = null
var cfg = null
var mode: int = MODE_SELECT
var input_source: int = SRC_POSE
var player_count: int = 1
var tracking: bool = false
var persons: int = 0
## Slots a person was actually mapped into this frame (see PSInput.tracked_slots).
var tracked_slots: int = 0
var bridge_ok: bool = false
var bridge_bound: bool = false
var bridge_frames: int = 0
var bridge_age_ms: int = -1
var bridge_binder: String = "none"
var bridge_error: String = ""
## Camera live (SDK system-composited preview) state, debug overlay only.
var cam_supported: bool = false
var cam_armed: bool = false
var cam_on: bool = false
var cam_rect := Rect2()
var cam_mode: int = 0
## The two normalized AIDL rect pairs exactly as the next send uses them
## (A = source crop, B = destination), plus the variant label.
var cam_rect_a := Rect2()
var cam_rect_b := Rect2()
var cam_mode_label: String = "1/3 SDK mirror (A.x1>A.x2)"
## Every AIDL view the next send uses: [{"id","src","dst","mode"}, ...].
## 1P has one entry (id 0), 2P has two (id 0 = left/slot 0, id 1 = right).
var cam_views: Array = []
## Provider-x -> game-x convention in lockstep with the camera variant.
var cam_pose_mirror: bool = true
## Short on-screen confirmation after F6 / remote MENU / remote INFO.
var cam_toast: String = ""
var cam_toast_until: float = 0.0
## ---- RGBA camera frame (B5): the mirror box's pixel source ----
## Owned by main.gd, mirrored here every frame. `cam_rgba_tex == null` means "no
## frame yet": the box then keeps its placeholder chrome (the empty plate plus the
## `1.00×` read-out), which is also the desktop / no-binder state.
var cam_rgba_tex: Texture2D = null
var cam_rgba_size := Vector2i.ZERO
## Flip the frame horizontally to match the SDK's mirrored overlay (device-checked,
## F7 toggles it at runtime).
var cam_rgba_flip := true
var cam_rgba_frames: int = 0
## Short state string for the debug overlay ("placeholder" / "frames 384x216" / ...).
var cam_rgba_state: String = "placeholder"
## ---- live skeleton over the camera pixels (owner request) ----
## `skel_src` is the pose input layer (`PSPoseInput`): the HUD only READS its
## provider-space snapshot (`skel_pts` / `skel_ok` / `skel_n` / `skel_wrist` /
## `skel_ref` / `skel_dead_u` / `skel_bones` / `skel_steer_wri`), so the overlay
## costs no copy and no allocation. `skel_on` is the owner toggle (F9 /
## `--no-skeleton`), ON by default: he asked to see the tracked skeleton.
##
## The overlay is drawn **in the camera's own space**, i.e. through the same
## cover-crop + `cam_rgba_flip` the texture goes through (see `_cam_map_uv`), and
## NOT through the game's `1-x` pose convention: the bones have to sit on the
## person in the picture, whatever the steering convention is.
var skel_src = null
var skel_on := true
var pose_hint: String = ""
var rows: Array = []
var rank: int = 1
## Rank at the previous HUD refresh: draws the ▲ / ▼ movement arrow.
var rank_prev: int = 1
## +1 = moved up since the last change, -1 = down, 0 = no arrow.
var rank_arrow: int = 0
var debug: bool = false
## ---- always-on perf panel ----
## `perf_on` is owned by main.gd (F10 / INFO x2 / `--perf-overlay` / `--no-perf`);
## `perf_labels` and `perf_vals` are the SAME arrays main.gd refills at 4 Hz, so
## drawing them costs no allocation and no per-frame string build.
var perf_on: bool = false
var perf_labels: Array = []
var perf_vals: Array = []
var _perf_font: Font = null
var show_hint_boot: bool = true
var perf := {"fps": 0.0, "draw": 0, "prim": 0, "p": 0, "t": 0, "w": 0}
var go_flash: float = 0.0
var time: float = 0.0
var resync: float = 0.0
var ai_level: float = 0.85

## ---- camera frame, mirrored from main.gd every frame (minimap viewport rect) ----
## Visible world span of the first view and its centre; `world_span` is
## `view_size / zoom`, i.e. exactly the rect `PSWorldView` draws.
var cam_center := Vector2(2400.0, 1350.0)
var world_span := Vector2(1958.0, 898.0)

## ---- mode select ----
## -1 = no default selection (the reference has none either).
var select_focus: int = -1
## Options bar under the title slab: the three remote-reachable, persisted
## player choices. `select_focus` 3/4/5 selects them (mirrored from main.gd).
const OPT_HELP := 3
const OPT_SOUND := 4
const OPT_ROUND := 5
const SELECT_SLOTS := 6
## How-to-play overlay is open (OK/BACK closes it; it owns the screen while open).
var help_open: bool = false
## SFX on (the chip reads 音效 开 / 音效 关). Mirrors `PSAudio.muted` inverted.
var audio_on: bool = true
## `cfg.round.mode`: "timed" = 2:00 ranked round, "endless" = practice.
var round_mode: String = "timed"
## ---- pause ----
## 0 = 继续游戏, 1 = 重新开局, 2 = 返回模式选择.
var pause_focus: int = 0

## ---- ready ----
## Parallel per-slot arrays, owned and mutated by main.gd; the HUD only reads
## them (the same Array objects are re-assigned every frame, no copies).
var ready_state: Array = [SLOT_WAITING, SLOT_WAITING]
var ready_fill: Array = [0.0, 0.0]
var ready_pop: Array = [0.0, 0.0]
## True once nobody has been seen for `READY_NO_PERSON_HINT_SEC`: shows the
## advisory 请站到镜头前 panel (BACK returns to mode select; nothing auto-starts).
var nobody_hint: bool = false
## 0 = ready panel in place, 1 = slid away during the opening beat.
var ready_slide: float = 0.0

## Panel slide-in offset in px (reference: +1400 -> 0, 0.3 s OutQuad). main.gd
## animates it on entry to READY; it is 0 in every other mode.
var ready_card_dy: float = 0.0

## ---- opening beat ----
## 0..1 through the 1.5 s GO! flourish, -1 when not counting down.
var countdown_beat: float = -1.0

var _btns: Array = []
var _card_style: StyleBoxFlat = null
var _chip_style: StyleBoxFlat = null
var _ghost_style: StyleBoxFlat = null
var _sel_card: StyleBoxFlat = null
var _sel_hi: Array = []
var _ready_card: Array = []
var _ready_inner: StyleBoxFlat = null
var _ready_bar: StyleBoxFlat = null
var _nobody_panel: StyleBoxFlat = null
var _slab_edge: StyleBoxFlat = null
var _slab_top: StyleBoxFlat = null
var _ps_btn: StyleBoxFlat = null
var _ps_btn_hi: StyleBoxFlat = null
var _badge_style: StyleBoxFlat = null
var _pause_strip: StyleBoxFlat = null
var _pause_cell_style: StyleBoxFlat = null
var _pause_key: StyleBoxFlat = null
var _pause_key_hi: StyleBoxFlat = null
var _lb_style: StyleBoxFlat = null
## Restored play-HUD chrome: minimap plate + score cells (built once).
var _mm_plate: StyleBoxFlat = null
var _score_cell: StyleBoxFlat = null
var _deco: Array = []
## Static geometry, built once (no per-frame allocation in `_draw`).
var _diamond := PackedVector2Array()
var _osd_arms := PackedVector2Array()
var _cam_brackets := PackedVector2Array()
## Skeleton overlay scratch buffers (sized once; `_skel_v` is resized per box to
## the number of visible bones, which keeps `draw_multiline` allocation-free).
var _skel_v := PackedVector2Array()
var _skel_px := PackedVector2Array()
var _skel_vis := PackedByteArray()
var _skel_jv := PackedVector2Array()
var _skel_jc := PackedColorArray()
var _rank_arrow_pts := PackedVector2Array()
## Minimap buffers: 4 batched 3x3 grid lines + one hexagon per snake dot.
var _mm_grid := PackedVector2Array()
var _mm_v := PackedVector2Array()
var _mm_c := PackedColorArray()
var _mm_i := PackedInt32Array()
var _mm_view_rect := Rect2()
## Score row: reused text array (4 entries, no per-frame container alloc).
var _score_txt: Array = ["", "", "", ""]
## Batched score-cell left edges (4 lines = 8 points).
var _score_edges := PackedVector2Array()

## ---- measurement only (`--capture-stress`) ----------------------------------
## Per-pass CPU time of the last `_draw`, in ms. `prof` is false in every normal
## run; the marks accumulate within one frame (2P band cells share `hud.skeleton`)
## and `_draw` clears the dictionary at the top of each frame.
var prof := false
var prof_ms: Dictionary = {}
var _prof_t := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ---- chrome: cyan stroke family, radius scale 4/3/2/0 only ----
	_card_style = PSTheme.panel(PSTheme.TV_PANEL, PSTheme.PANEL_BORDER, PSTheme.R_PANEL, 1, 6,
		"hud_card")
	_chip_style = PSTheme.panel(Color(6.0 / 255.0, 14.0 / 255.0, 26.0 / 255.0, 0.94),
		PSTheme.PANEL_BORDER, PSTheme.R_CARD, 1, 0, "hud_chip")
	_ghost_style = PSTheme.panel(Color(0.039, 0.078, 0.118, 0.92), PSTheme.PANEL_BORDER,
		PSTheme.R_CARD, 1, 0, "hud_ghost")
	_sel_card = PSTheme.panel(Color(0.035, 0.071, 0.125, 0.94), PSTheme.PANEL_BORDER,
		PSTheme.R_PANEL, 1, 20, "hud_sel_card")
	_sel_hi.append(PSTheme.panel(Color(0.055, 0.105, 0.078, 0.97),
		PSTheme.with_a(PSTheme.LIME, 0.68), PSTheme.R_PANEL, 2, 30, "hud_sel_hi1"))
	_sel_hi.append(PSTheme.panel(Color(0.055, 0.105, 0.078, 0.97),
		PSTheme.with_a(PSTheme.LIME, 0.68), PSTheme.R_PANEL, 2, 30, "hud_sel_hi2"))
	_ready_card.append(PSTheme.panel(Color(0.05, 0.075, 0.13, 0.90),
		PSTheme.with_a(PSTheme.SLOT_1, 0.45), PSTheme.R_PANEL, 2, 16, "hud_ready_card1"))
	_ready_card.append(PSTheme.panel(Color(0.05, 0.075, 0.13, 0.90),
		PSTheme.with_a(PSTheme.SLOT_2, 0.55), PSTheme.R_PANEL, 2, 16, "hud_ready_card2"))
	_ready_inner = PSTheme.panel(Color(0.018, 0.03, 0.058, 0.80), PSTheme.TV_LINE_SOFT,
		PSTheme.R_CARD, 1, 0, "hud_ready_inner")
	_ready_bar = PSTheme.panel(Color(0.018, 0.03, 0.058, 0.90), PSTheme.PANEL_BORDER,
		PSTheme.R_CARD, 1, 0, "hud_ready_bar")
	_nobody_panel = PSTheme.panel(Color(0.10, 0.075, 0.035, 0.94),
		Color(0.85, 0.65, 0.25, 0.55), PSTheme.R_PANEL, 1, 12, "hud_ready_nobody")
	# ---- title slab: 1px cyan edge (r4) + 4px lime top edge (r4) ----
	_slab_edge = PSTheme.panel(Color(0, 0, 0, 0), PSTheme.PANEL_BORDER, PSTheme.R_PANEL, 1)
	_slab_edge.border_width_top = 0
	_slab_top = PSTheme.panel(Color(0, 0, 0, 0), PSTheme.LIME, PSTheme.R_PANEL, 0)
	_slab_top.border_width_left = 0
	_slab_top.border_width_right = 0
	_slab_top.border_width_bottom = 0
	_slab_top.border_width_top = 4
	# ---- mode cards / badges / pause chrome ----
	_ps_btn = PSTheme.panel(Color(0.033, 0.078, 0.125, 0.86), PSTheme.PANEL_BORDER,
		PSTheme.R_CARD, 1)
	_ps_btn.border_width_bottom = 3
	_ps_btn_hi = PSTheme.panel(Color(0.043, 0.094, 0.157, 0.90),
		PSTheme.with_a(PSTheme.LIME, 0.68), PSTheme.R_CARD, 1, 20)
	_ps_btn_hi.border_width_bottom = 3
	_badge_style = PSTheme.panel(Color(0.337, 0.910, 1.0, 0.07), PSTheme.TV_LINE_SOFT,
		PSTheme.R_BADGE, 1)
	# NB: StyleBoxFlat has a single `border_color`; the *accent* edges (the 4 px
	# lime band-cell edges, the 4 px cyan pause-strip left edge, the 3 px cyan
	# leaderboard top edge) are drawn as explicit rects in the draw path.
	_pause_strip = PSTheme.panel(Color(6.0 / 255.0, 16.0 / 255.0, 29.0 / 255.0, 0.97),
		PSTheme.PANEL_BORDER, PSTheme.R_PANEL, 1, 18)
	_pause_cell_style = PSTheme.panel(Color(12.0 / 255.0, 28.0 / 255.0, 46.0 / 255.0, 0.70),
		PSTheme.PANEL_BORDER, PSTheme.R_CARD, 1)
	# 247x196 icon keys (`PauseForm.btnContinue`…): radius 4, cyan hairline, a
	# darker interior than the old 400x54 rows so a 56 px glyph reads on it.
	_pause_key = PSTheme.panel(Color(0.027, 0.059, 0.098, 0.92),
		PSTheme.PANEL_BORDER, PSTheme.R_PANEL, 1, 14)
	_pause_key_hi = PSTheme.panel(Color(0.047, 0.102, 0.078, 0.96),
		PSTheme.with_a(PSTheme.LIME, 0.72), PSTheme.R_PANEL, 2, 26)
	_lb_style = PSTheme.panel(Color(6.0 / 255.0, 14.0 / 255.0, 26.0 / 255.0, 0.95),
		PSTheme.PANEL_BORDER, PSTheme.R_CARD, 1, 16)
	# ---- restored play HUD: minimap plate + score cells (B1 token set) ----
	# `render.js:drawMinimap` plate: fill rgba(5,12,24,.84), cyan stroke .32,
	# radius 12 on the web; the B1 radius scale caps at 4, the owner asked for 3.
	_mm_plate = PSTheme.panel(Color(5.0 / 255.0, 12.0 / 255.0, 24.0 / 255.0, 0.84),
		PSTheme.PANEL_BORDER, PSTheme.R_CARD, 1, 10, "hud_mm_plate")
	# `#hud .stat` card in the TV skin: `rgba(6,14,26,.95)` + 1 px cyan line.
	_score_cell = PSTheme.panel(Color(6.0 / 255.0, 14.0 / 255.0, 26.0 / 255.0, 0.95),
		PSTheme.PANEL_BORDER, PSTheme.R_CARD, 1, 10, "hud_score_cell")
	# ---- static geometry (built once; size is DESIGN and never changes) ----
	var dc := Vector2(960.0, 181.5)
	_diamond = PackedVector2Array([
		dc + Vector2(0.0, -9.0), dc + Vector2(9.0, 0.0),
		dc + Vector2(0.0, 9.0), dc + Vector2(-9.0, 0.0)])
	# OSD: body::after brackets, inset 44, arms 30x2 / 2x30.
	var l := 44.0
	var rr_ := 44.0 + 30.0
	_osd_arms = PackedVector2Array([
		Vector2(l, l), Vector2(rr_, l), Vector2(l, l), Vector2(l, l + 30.0),
		Vector2(1920.0 - l, l), Vector2(1920.0 - rr_, l),
		Vector2(1920.0 - l, l), Vector2(1920.0 - l, l + 30.0),
		Vector2(l, 1080.0 - l), Vector2(rr_, 1080.0 - l),
		Vector2(l, 1080.0 - l), Vector2(l, 1080.0 - l - 30.0),
		Vector2(1920.0 - l, 1080.0 - l), Vector2(1920.0 - rr_, 1080.0 - l),
		Vector2(1920.0 - l, 1080.0 - l), Vector2(1920.0 - l, 1080.0 - l - 30.0)])
	# mirror-box inner bracket: one 22x22 L at +7,+7, 3 px arms (2 segments)
	_cam_brackets.resize(4)
	# Skeleton overlay: fixed buffers, filled per box (no per-frame allocation).
	_skel_v.resize(SKEL_SEG_MAX)
	_skel_px.resize(33)
	_skel_vis.resize(33)
	_skel_jv.resize(SKEL_JOINT_MAX)
	_skel_jc.resize(SKEL_JOINT_MAX >> 1)
	_rank_arrow_pts = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	# Decorative faces on the mode-select screen, placed once (no per-frame alloc).
	_deco.assign([
		[Vector2(74.0, 118.0), 0, 150.0], [Vector2(215.0, 940.0), 6, 160.0],
		[Vector2(1848.0, 140.0), 2, 145.0], [Vector2(1762.0, 944.0), 9, 155.0],
		[Vector2(596.0, 88.0), 4, 120.0], [Vector2(1324.0, 92.0), 7, 130.0],
		[Vector2(66.0, 560.0), 3, 135.0], [Vector2(1854.0, 566.0), 5, 140.0],
		[Vector2(520.0, 1010.0), 8, 145.0], [Vector2(1402.0, 1008.0), 1, 150.0],
	])


func _cn(cn: String, en: String) -> String:
	return cn if PSTheme.cjk_ok() else en


func button_at(pos: Vector2) -> int:
	for b in _btns:
		if (b[1] as Rect2).has_point(pos):
			return int(b[0])
	return BTN_NONE


# ------------------------------------------------------------------- draw

func _draw() -> void:
	if game == null:
		return
	if prof:
		prof_ms.clear()
		_prof_t = Time.get_ticks_usec()
	match mode:
		MODE_SELECT:
			_draw_select()
		MODE_READY:
			_draw_ready()
		MODE_COUNTDOWN:
			_draw_go_beat()
		MODE_PLAY:
			_draw_play()
		MODE_PAUSE:
			_draw_play()
			_draw_pause()
		MODE_SETTLE:
			_draw_settle_hud()
	_prof_mark("hud.screen")
	# OSD chrome sits on every gameplay screen. The web draws it as `body::before`
	# / `body::after`, so the **title overlay** and the **settlement stage** cover
	# it (WEB-COMPUTED-STYLES §7.3) — those two states skip it here too.
	if mode != MODE_SELECT and mode != MODE_SETTLE:
		_draw_osd()
	_prof_mark("hud.osd")
	# The perf panel goes over the OSD chrome (vignette + scanlines) so the
	# corner it lives in cannot dim it; the settlement stage owns its screen and
	# draws on a higher CanvasLayer, so the panel is skipped there.
	if perf_on and mode != MODE_SETTLE:
		_draw_perf()
		_prof_mark("hud.perf")
	if debug:
		_draw_debug()
	_draw_cam_toast()
	_prof_mark("hud.misc")


## Store the time spent since the previous mark under `key` (stress harness only).
func _prof_mark(key: String) -> void:
	if not prof:
		return
	var now := Time.get_ticks_usec()
	prof_ms[key] = float(prof_ms.get(key, 0.0)) + float(now - _prof_t) / 1000.0
	_prof_t = now


## 3 s chip after the camera-variant key: tells the owner which variant is on
## screen without logcat. Under the score row on the play screen (which owns the
## top-left block since B2), in its old slot on the menu screens.
func _draw_cam_toast() -> void:
	if cam_toast.is_empty() or time >= cam_toast_until:
		return
	var ty := 216.0
	if mode == MODE_PLAY or mode == MODE_PAUSE:
		ty = SCORE_Y + SCORE_H + 8.0
	var r := Rect2(40.0, ty, 520.0, 46.0)
	draw_style_box(_chip_style, r)
	draw_circle(Vector2(r.position.x + 24.0, r.position.y + 23.0), 7.0, PSTheme.CYAN)
	PSTheme.text_vc(self, r.position.x + 42.0, r.position.y + 23.0, cam_toast, 20,
		PSTheme.TEXT_SOFT)


# --------------------------------------------------------------- OSD overlay

## `body::before` (scanlines + vignette) and `body::after` (4-corner brackets).
## Brackets: inset 44 px, eight 30x2 / 2x30 arms, opacity .55, solid `#56e8ff` —
## one `draw_multiline` for all eight arms (one draw call).
func _draw_osd() -> void:
	draw_texture_rect(PSAssets.vignette, Rect2(0, 0, size.x, size.y), false)
	draw_texture_rect(PSAssets.scanline, Rect2(0, 0, size.x, size.y), true)
	draw_multiline(_osd_arms, Color(0.337, 0.910, 1.0, 0.55), 2.0)


# ------------------------------------------------------------- band pieces

## The merged console band: `#uiBar` (1920x200, radius 0) + `#hud` clock cell +
## `#rankBlock` + the `#cam` mirror-box chrome.
##
## Background is the measured 3-layer stack — 1 px cyan grid (52 x 26), the
## vertical rgb(12,29,48) -> rgb(9,21,36) 58% -> rgb(5,12,22) gradient, plus the
## `.ui-scan` line texture — then the decor layer (`.ui-energy`, `.ui-ruler`,
## `.ui-notch`, `.ui-diamond`) and the 3 px cyan bottom seam.
func _draw_band() -> void:
	var two := player_count > 1
	var w := size.x
	# ---- background stack ----
	draw_texture_rect(PSAssets.band_grad, Rect2(0, 0, w, BAND_H), false)
	draw_texture_rect(PSAssets.band_grid, Rect2(0, 0, w, BAND_H), true)
	draw_texture_rect(PSAssets.band_scan, Rect2(0, 0, w, BAND_H), true)
	# ---- decor: energy rail + white-hot sweep (`.ui-energy`) ----
	draw_rect(Rect2(0, 0, w, 6.0), Color(0.337, 0.910, 1.0, 0.16), true)
	draw_texture_rect(PSAssets.energy_grad, Rect2(13.0, 0.0, 729.59, 6.0), false)
	# ---- decor: ruler, notches, diamond ----
	draw_texture_rect(PSAssets.ruler, Rect2(BAND_PAD, 185.0, 1740.0, 5.0), true,
		Color(1, 1, 1, 0.32))
	draw_rect(Rect2(0, 183, 30, 14), Color(0.337, 0.910, 1.0, 0.55), true)
	draw_rect(Rect2(w - 30.0, 183, 30, 14), Color(0.337, 0.910, 1.0, 0.55), true)
	draw_colored_polygon(_diamond, Color(0.902, 0.984, 1.0, 1.0))
	# ---- 3 px cyan bottom seam + its spill ----
	# Measured: the shipped seam samples as **solid #56e8ff** all the way from
	# x~600 to x~1320 and only dims at the edges because the OSD vignette sits on
	# top of it (no white core is ever visible). So: one solid rect, and the
	# vignette drawn later does the falloff.
	draw_texture_rect(PSAssets.seam_glow, Rect2(0, BAND_H - 20.0, w, 20.0), false)
	draw_rect(Rect2(0, BAND_H, w, SEAM_H), PSTheme.CYAN, true)
	# `#uiBar` box-shadow onto the arena: keeps the band reading as a raised
	# console instead of a flat strip, and hides the band/arena colour step.
	draw_texture_rect(PSAssets.band_shadow, Rect2(0, BAND_H + SEAM_H, w, 58.0), false)
	# ---- cells ----
	if two:
		# 2P: each band box shows THAT player's half of the shared RGBA frame (the
		# same rule as the READY panes and main.gd's `CAMERA_2P_SRC`: slot 0 is the
		# left half of the mirrored image, i.e. the raw sensor's right half). It
		# used to pass `show_frame = false`, so the split-screen band had two empty
		# plates while the single-player one showed live pixels.
		var uv_l: Rect2 = CAM_2P_UV[0] if cam_pose_mirror else CAM_2P_UV[1]
		var uv_r: Rect2 = CAM_2P_UV[1] if cam_pose_mirror else CAM_2P_UV[0]
		_draw_cam_cell(CAM_2P_L, "1P", PSTheme.CYAN, true, uv_l, 0)
		_draw_cam_cell(CAM_2P_R, "2P", PSTheme.PINK, true, uv_r, 1)
		_draw_clock_cell(HUD_2P, true)
		_draw_rank_cell(RANK_2P_L, 0, true, false)
		_draw_rank_cell(RANK_2P_R, 1, true, true)
	else:
		_draw_cam_cell(CAM_1P, "", PSTheme.CYAN, true)
		_draw_clock_cell(HUD_1P, false)
		_draw_rank_cell(RANK_1P, 0, false, true)


## `#hud`: the clock cell. `lg(90deg, cyan .1, cyan .01 62%, cyan .1)` wash with a
## **4 px lime left border** (not on the band, at x=448).
func _draw_clock_cell(r: Rect2, two: bool) -> void:
	draw_texture_rect(PSAssets.hud_grad, r, false)
	draw_rect(Rect2(r.position.x, r.position.y, 4.0, r.size.y), PSTheme.LIME, true)
	var cx := CLOCK_CX_2P if two else CLOCK_CX_1P
	var lsz := CLOCK_LABEL_SZ_2P if two else CLOCK_LABEL_SZ
	var lbase := CLOCK_LABEL_BASE_2P if two else CLOCK_LABEL_BASE
	var csz := CLOCK_SZ_2P if two else CLOCK_SZ
	var cbase := CLOCK_BASE_2P if two else CLOCK_BASE
	# `剩余` — 36/700/.28em, rgba(198,232,248,.82), 14 px cyan text-shadow
	# label: 36/700 (not the 900 numeral face), cyan .3 14 px text-shadow
	PSTheme.glow_tc(self, cx, lbase, _cn("剩余", "TIME LEFT") if round_mode != "endless"
		else _cn("无尽练习", "ENDLESS"), lsz, PSTheme.LABEL_DIM,
		PSTheme.CYAN, float(lsz) * 0.28, 14, 0.10, 8, 0.20, false)
	# clock digits — 120/900/.32, rgb(215,247,255), cyan .62@38 + cyan .85@10 glow
	# Endless practice has no clock (the rules never count it down): the band shows
	# `--:--` so it cannot read as "2:00 remaining".
	var tl: float = game.round_left
	var clock := "%d:%02d" % [int(tl) / 60, int(tl) % 60]
	if round_mode == "endless":
		clock = "--:--"
	var last_call: bool = game.is_last_call() and round_mode != "endless"
	var col := PSTheme.CLOCK_DIGITS
	var glow := PSTheme.CYAN
	if last_call:
		col = PSTheme.CLOCK_DIGITS.lerp(PSTheme.DANGER, 0.35 + 0.35 * sin(time * 9.0))
		glow = PSTheme.DANGER
	PSTheme.glow_tc(self, cx, cbase, clock, csz, col, glow, 0.32, 44, 0.15, 12, 0.30)


## `#rankBlock`: lime wash strongest at the right edge + a **4 px lime right
## border**; `我的名次` 36/700/.24em, the 96/900 numeral right-aligned with the
## ▲/▼ move arrow, `共 8 位玩家` 24.
func _draw_rank_cell(r: Rect2, player_index: int, two: bool, right_edge: bool) -> void:
	draw_texture_rect(PSAssets.rank_grad, r, false)
	var edge_x: float = r.end.x - 4.0 if right_edge else r.position.x
	draw_rect(Rect2(edge_x, r.position.y, 4.0, r.size.y), PSTheme.LIME, true)
	var rk: int = _rank_of_player(player_index)
	var rgt: float = RANK_RIGHT_1P if not two else (RANK_RIGHT_2P if right_edge
		else RANK_LEFT_RIGHT)
	var lsz := RANK_LABEL_SZ_2P if two else RANK_LABEL_SZ
	var ltrack := float(lsz) * 0.24
	var lbase := RANK_LABEL_BASE_2P if two else RANK_LABEL_BASE
	var nsz := RANK_SZ_2P if two else RANK_SZ
	var nbase := RANK_BASE_2P if two else RANK_BASE
	var tsz := RANK_TOTAL_SZ_2P if two else RANK_TOTAL_SZ
	var tbase := RANK_TOTAL_BASE_2P if two else RANK_TOTAL_BASE
	var arrow: int = rank_arrow if player_index == 0 else 0
	# The shipped `#rank` is never white: lime `rgb(182,255,87)` while holding or
	# rising, salmon `rgb(255,154,114)` while falling (WEB-COMPUTED-STYLES §3).
	var col: Color = PSTheme.RANK_UP
	if arrow < 0:
		col = PSTheme.RANK_DOWN
	var label := _cn("我的名次", "MY RANK")
	if two:
		label = _cn("1P 名次" if player_index == 0 else "2P 名次",
			"P1 RANK" if player_index == 0 else "P2 RANK")
	PSTheme.text_tr(self, rgt, lbase, label, lsz, PSTheme.LABEL_DIM, ltrack)
	# ▲ / ▼ movement arrow, left of the numeral (36/900 ink is ~26x24)
	if arrow != 0:
		var ax: float = r.position.x + (22.0 if right_edge else 20.0)
		var ay: float = nbase - float(nsz) * 0.62
		if arrow < 0:
			_rank_arrow_pts[0] = Vector2(ax - 13.0, ay - 12.0)
			_rank_arrow_pts[1] = Vector2(ax + 13.0, ay - 12.0)
			_rank_arrow_pts[2] = Vector2(ax, ay + 12.0)
		else:
			_rank_arrow_pts[0] = Vector2(ax - 13.0, ay + 12.0)
			_rank_arrow_pts[1] = Vector2(ax + 13.0, ay + 12.0)
			_rank_arrow_pts[2] = Vector2(ax, ay - 12.0)
		draw_colored_polygon(_rank_arrow_pts, col)
	# numeral, right-aligned to the content edge
	# The shipped numeral always carries a soft halo in its own colour (the
	# `.rank-arrow` glow bleeds onto it); stronger + tighter while moving.
	var rtxt := "%d / %d" % [rk, maxi(2, game.snakes.size())]
	if arrow != 0:
		PSTheme.glow_tr(self, rgt, nbase, rtxt, nsz, col, col, 0.32, 34, 0.16, 8, 0.30)
	else:
		PSTheme.glow_tr(self, rgt, nbase, rtxt, nsz, col, col, 0.32, 30, 0.08, 7, 0.16)
	PSTheme.text_tr(self, rgt, tbase, _cn("共 %d 位玩家" % game.snakes.size(),
		"%d PLAYERS" % game.snakes.size()), tsz, PSTheme.TOTAL_DIM, tsz * 0.10)


## `#cam`: the mirror box. Its pixels now come from the plugin's RGBA frames
## (`cam_rgba_tex`), blitted by `_draw_cam_frame`; the SDK's system overlay is no
## longer used by default (it is composited ABOVE this app, so it could never be
## cropped or covered). The chrome — 2 px rgba(cyan,.55) frame, inner corner
## bracket, rec dot and the bottom speed read-out — is drawn *over* the frame,
## exactly where the web's `#cam` children sit.
##
## `host_uv` / `skel_slot` are how a box shows a **part** of the frame: 1P uses
## the whole frame (defaults), 2P uses each player's half plus that slot's
## skeleton, so the split-screen band proves both people are being tracked.
func _draw_cam_cell(r: Rect2, tag_text: String, accent: Color, show_frame: bool = true,
		host_uv: Rect2 = CAM_FULL_UV, skel_slot: int = 0) -> void:
	draw_rect(r, Color(4.0 / 255.0, 11.0 / 255.0, 20.0 / 255.0, 1.0), true)
	if show_frame and cam_rgba_tex != null:
		_draw_cam_frame(r, host_uv)
		_prof_mark("hud.cam")
		# Live skeleton ON the pixels: the same cover-crop (and flip) is applied to
		# both, so the bones sit on the person whatever the box aspect is.
		_draw_pose_skeleton(r, host_uv, skel_slot)
		_prof_mark("hud.skeleton")
	draw_rect(r.grow(1.0), Color(accent.r, accent.g, accent.b, 0.55), false, 2.0)
	# `#cam .cam-frame i`: ONE 22x22 L at +7,+7 (3 px arms) — the shipped box has
	# a single corner bracket plus the rec dot, not four brackets.
	var p0 := r.position + Vector2(7.0, 7.0)
	_cam_brackets[0] = p0
	_cam_brackets[1] = p0 + Vector2(22.0, 0.0)
	_cam_brackets[2] = p0
	_cam_brackets[3] = p0 + Vector2(0.0, 22.0)
	draw_multiline(_cam_brackets, Color(accent.r, accent.g, accent.b, 0.90), 3.0)
	# rec dot + slot tag live OUTSIDE the box (the gutter right of it, and just
	# above it): on device the live preview covers everything inside.
	draw_circle(Vector2(r.end.x + 8.0, r.position.y + 9.0), 6.0,
		Color(1.0, 156.0 / 255.0, 174.0 / 255.0, 1.0))
	if tag_text != "":
		draw_rect(Rect2(r.position.x + 4.0, r.position.y - 20.0, 30.0, 17.0),
			Color(4.0 / 255.0, 10.0 / 255.0, 20.0 / 255.0, 0.82), true)
		PSTheme.text_t(self, Vector2(r.position.x + 9.0, r.position.y - 7.0), tag_text, 10,
			PSTheme.LIME, 1.0)
	# bottom read-out: speed multiplier + track
	var sp_y: float = r.end.y - 46.0
	draw_texture_rect(PSAssets.cam_grad, Rect2(r.position.x + 2.0, sp_y, r.size.x - 4.0, 42.0),
		false)
	var mul := 1.0
	var p = game.player
	if p != null:
		mul = clampf(float(p.speed_mul), 0.5, 2.5)
	PSTheme.text_t(self, Vector2(r.position.x + 14.0, r.end.y - 14.7), "%.2f×" % mul, 26,
		Color(220.0 / 255.0, 248.0 / 255.0, 1.0), 0.52)
	var tw: float = r.size.x - 130.0
	var tr := Rect2(r.end.x - 14.0 - tw, r.end.y - 37.0, tw, 10.0)
	draw_rect(tr, Color(6.0 / 255.0, 22.0 / 255.0, 36.0 / 255.0, 0.86), true)
	draw_rect(tr, Color(0.337, 0.910, 1.0, 0.40), false, 1.0)
	var fk := clampf((mul - 0.65) / 1.15, 0.0, 1.0)
	if fk > 0.01:
		draw_rect(Rect2(tr.position.x + 1.0, tr.position.y + 1.0, (tr.size.x - 2.0) * fk,
			tr.size.y - 2.0), Color(0.337, 0.910, 1.0, 0.95), true)


## Blit the RGBA camera frame into the box: **cover-crop, centred** (the box keeps
## its own aspect whatever the frame aspect is) and horizontally mirrored when
## `cam_rgba_flip`. `src_uv` selects a sub-rectangle of the frame in 0..1 UV space
## (the READY cards' 2P halves); the band's mirror box uses the whole frame. One
## `draw_texture_rect_region` per box per frame — no clipping, no intermediate
## viewport, nothing allocated: the texture object itself is shared by every box
## and reused until the frame size changes (main.gd updates it in place).
func _draw_cam_frame(r: Rect2, src_uv: Rect2 = CAM_FULL_UV) -> void:
	var src := _cam_src_rect(r, src_uv)
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		return
	if cam_rgba_flip:
		# mirror about the box's vertical centre: x' = 2cx - x
		draw_set_transform(Vector2(r.get_center().x * 2.0, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect_region(cam_rgba_tex, r, src)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(cam_rgba_tex, r, src)


## The **cover-crop source rect** (in texture pixels) that `_draw_cam_frame` blits
## into `r`, or an empty Rect2 when there is nothing to draw. This is the single
## description of how the camera pixels land in a box: the frame blit above and the
## skeleton overlay both go through it, so bones cannot drift from the picture.
func _cam_src_rect(r: Rect2, src_uv: Rect2) -> Rect2:
	if cam_rgba_tex == null:
		return Rect2()
	var ts := cam_rgba_tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0 or r.size.x <= 0.0 or r.size.y <= 0.0:
		return Rect2()
	var sub := Rect2(src_uv.position * ts, src_uv.size * ts)
	if sub.size.x <= 0.0 or sub.size.y <= 0.0:
		return Rect2()
	var src := sub
	var dst_aspect := r.size.x / r.size.y
	var src_aspect := sub.size.x / sub.size.y
	if src_aspect > dst_aspect + 0.001:
		var w := sub.size.y * dst_aspect
		src = Rect2(sub.position.x + (sub.size.x - w) * 0.5, sub.position.y, w, sub.size.y)
	elif src_aspect < dst_aspect - 0.001:
		var h := sub.size.x / dst_aspect
		src = Rect2(sub.position.x, sub.position.y + (sub.size.y - h) * 0.5, sub.size.x, h)
	return src


## Map one **provider-normalised** keypoint (0..1 of the whole frame, top-left,
## unmirrored) into design px inside the box `r`.
##
## It is the inverse of what `draw_texture_rect_region(tex, r, src)` does, so the
## skeleton lands exactly on the person:
##
##     ts   = frame texture size            (e.g. 576 x 324)
##     src  = cover-crop rect in that texture (`_cam_src_rect`)
##     fx   = (u * ts.x - src.x) / src.w          0..1 inside the visible crop
##     fy   = (v * ts.y - src.y) / src.h
##     x    = r.x + r.w * fx        (cam_rgba_flip: x = r.end.x - r.w * fx)
##     y    = r.y + r.h * fy
##
## Returns `SKEL_OUT` when the point is outside the crop (the 2P READY halves,
## where half of the body is legitimately off-pane). No allocation, no state.
func _cam_map_uv(r: Rect2, src: Rect2, u: float, v: float) -> Vector2:
	var ts := cam_rgba_tex.get_size()
	var fx := (u * ts.x - src.position.x) / src.size.x
	var fy := (v * ts.y - src.position.y) / src.size.y
	if fx < 0.0 or fx > 1.0 or fy < 0.0 or fy > 1.0:
		return SKEL_OUT
	if cam_rgba_flip:
		fx = 1.0 - fx
	return Vector2(r.position.x + r.size.x * fx, r.position.y + r.size.y * fy)


## Draw the tracked skeleton over the camera pixels of box `r` (band mirror box
## and READY slot panes call this right after `_draw_cam_frame`).
##
## Style: 2 px cyan `#56e8ff` bones at 0.70, 3 px joint dots, a brighter dot on
## the steering hand (the RIGHT wrist), and exactly ONE lime reference dot with its
## dead-zone radius on the RIGHT SHOULDER plus a faint line from it to the right
## wrist - so the owner can see *what the game is steering around* since the
## reference moved off the chest (owner: 手胸连点 -> 右手与右肩连点, 先只处理右侧).
## The left arm keeps ordinary joint dots; it has no reference of its own.
##
## Draw cost: **one** `draw_multiline` for every bone, one `draw_multiline_colors`
## for every joint, one `draw_arc` for the dead-zone ring and one `draw_line` for
## the steering arm. All of it is untextured with the default material, so the 2D
## batcher merges it into the box's existing batch (measured:
## evidence/skeleton-overlay.md).
func _draw_pose_skeleton(r: Rect2, src_uv: Rect2, slot: int) -> void:
	if not skel_on or skel_src == null or cam_rgba_tex == null:
		return
	if slot < 0 or slot >= skel_src.skel_on.size() or not bool(skel_src.skel_on[slot]):
		return
	var src := _cam_src_rect(r, src_uv)
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		return
	var pts: PackedVector2Array = skel_src.skel_pts[slot]
	var ok: PackedByteArray = skel_src.skel_ok[slot]
	var n: int = mini(int(skel_src.skel_n[slot]), pts.size())
	if n <= 0:
		return
	# ---- project the visible keypoints once (fixed buffers, no allocation) ----
	var px := _skel_px
	var vis := _skel_vis
	var anchor := Vector2.ZERO
	var has_anchor := false
	for i in n:
		vis[i] = 0
		if ok[i] == 0:
			continue
		var p := _cam_map_uv(r, src, pts[i].x, pts[i].y)
		px[i] = p
		if p == SKEL_OUT:
			continue
		vis[i] = 1
		if not has_anchor:
			anchor = p
			has_anchor = true
	if not has_anchor:
		return
	# ---- bones: ONE batched multiline (missing joints collapse to a point) ----
	var bones: Array = skel_src.skel_bones
	var seg := 0
	var v := _skel_v
	for b in bones:
		var a: int = int(b[0])
		var c: int = int(b[1])
		if seg + 2 > v.size():
			break
		if a < n and c < n and vis[a] != 0 and vis[c] != 0:
			v[seg] = px[a]
			v[seg + 1] = px[c]
		else:
			# zero-length segment: skipped by the rasteriser, keeps the batch shape
			v[seg] = anchor
			v[seg + 1] = anchor
		seg += 2
	if seg > 0:
		v.resize(seg)
		draw_multiline(v, SKEL_BONE_COL, 2.0)
		v.resize(SKEL_SEG_MAX)
	# ---- joints: 3 px dots, batched into ONE multiline_colors ----
	# A "dot" at this scale is a 2-segment cross: at 320x180 the person is ~90 px
	# tall, so a circle per joint would cost 18 draw calls for a 1.5 px mark. The
	# per-segment colours let the steering hand be brighter in the same call.
	var jv := _skel_jv
	var jc := _skel_jc
	var jseg := 0
	var hand_k: int = int(skel_src.skel_steer_wri)
	for i in n:
		if vis[i] == 0 or jseg + 4 > jv.size():
			continue
		var is_wrist: bool = i == hand_k
		var rad: float = 2.2 if is_wrist else 1.3
		var col: Color = SKEL_HAND_COL if is_wrist else SKEL_JOINT_COL
		var p: Vector2 = px[i]
		jv[jseg] = p + Vector2(-rad, 0.0)
		jv[jseg + 1] = p + Vector2(rad, 0.0)
		jv[jseg + 2] = p + Vector2(0.0, -rad)
		jv[jseg + 3] = p + Vector2(0.0, rad)
		# `draw_multiline_colors` takes ONE colour per SEGMENT (two points).
		jc[jseg >> 1] = col
		jc[(jseg >> 1) + 1] = col
		jseg += 4
	if jseg > 0:
		jv.resize(jseg)
		jc.resize(jseg >> 1)
		draw_multiline_colors(jv, jc, 2.0)
		jv.resize(SKEL_JOINT_MAX)
		jc.resize(SKEL_JOINT_MAX >> 1)
	# ---- ONE reference dot + dead-zone radius on the RIGHT SHOULDER, plus the
	# ---- shoulder -> right-wrist steering line (owner: the hand point stays) ----
	if bool(skel_src.skel_ref_ok[slot]):
		var c := _cam_map_uv(r, src, skel_src.skel_ref[slot].x,
			skel_src.skel_ref[slot].y)
		if c != SKEL_OUT:
			# The dead-zone radius is a fraction of the frame WIDTH (axis-exact);
			# a uniform cover-crop keeps it a circle inside the box.
			var dead_px: float = float(skel_src.skel_dead_u[slot]) * r.size.x \
				* cam_rgba_tex.get_size().x / src.size.x
			if dead_px > 1.0:
				draw_arc(c, dead_px, 0.0, TAU, 28, SKEL_RING_COL, 1.0, true)
			draw_circle(c, 2.5, SKEL_REF_COL)
			var wk: int = int(skel_src.skel_steer_wri)
			if wk >= 0 and wk < n and vis[wk] != 0:
				draw_line(c, px[wk], SKEL_ARM_COL, 1.0)


## Rank of the human in slot `i`. `rows` is the 5 Hz `game.live_ranking()` copy
## main.gd already owns, so this costs one linear scan and no allocation.
func _rank_of_player(i: int) -> int:
	for r in rows:
		if bool(r.is_player) and int(r.player_index) == i:
			return int(r.rank)
	if i == 0 and game != null:
		return game.player_rank()
	return maxi(1, rows.size())


# ---------------------------------------------------------- mode select

## `#overlay` title screen: full-screen grid backdrop + the 780 x 582.72 slab
## (`#overlay .panel.title-screen`, radius 4, 4 px lime top edge).
##
## Interaction is the port's own (remote DPAD + OK picks a mode directly; there
## is no mouse and no separate start button), so the web's `#startBtn` /
## `#kbBtn` row is replaced by the pad-hint keycaps. The chrome is the web's
## (brand line, H1, badges, 游戏人数 label, 351 px mode cards) except for the
## type scale, which follows the TV floors in the file header: the two mode
## cards are still 351 px wide but 88 px tall so a 34 px name and a 20 px sub
## line fit. The 1024 reference's 342x138 / 48 px card was declined by the owner.
func _draw_select() -> void:
	_btns.clear()
	var w := size.x
	var h := size.y
	# ---- `#overlay` backdrop: same 3-layer stack as the band, full screen ----
	draw_texture_rect(PSAssets.band_grad, Rect2(0, 0, w, h), false)
	draw_texture_rect(PSAssets.band_grid, Rect2(0, 0, w, h), true)
	draw_texture_rect(PSAssets.band_scan, Rect2(0, 0, w, h), true)
	draw_texture_rect(PSAssets.vignette, Rect2(0, 0, w, h), false)
	if not _deco.is_empty():
		for d in _deco:
			var p: Vector2 = d[0]
			var s: float = d[2]
			_draw_deco_face(p, s, int(d[1]), 0.22)
	# ---- slab: gradient fill, cyan 1 px edge, 4 px lime top, soft halo ----
	draw_texture_rect(PSAssets.blob, SLAB.grow(110.0), false, Color(0.337, 0.910, 1.0, 0.045))
	draw_texture_rect(PSAssets.panel_grad, SLAB, false)
	draw_style_box(_slab_edge, SLAB)
	draw_style_box(_slab_top, SLAB)
	var cx := SLAB.get_center().x
	var left := SLAB.position.x + SLAB_PAD
	var inner_w := SLAB.size.x - SLAB_PAD * 2.0
	# ---- brand line: MOTION ARENA chip + TV EDITION ----
	# Typography pass: 10 -> 18 px (meta floor 18). The chip grows with its text;
	# everything below it shifts up so the 582.72 px slab (a web-parity anchor that
	# must not change) still holds the whole stack.
	var chip := Rect2(0, 0, 190.0, 28.0)
	chip.position = Vector2(cx - 139.0, SLAB.position.y + 22.0)
	draw_rect(chip, PSTheme.LIME, true)
	PSTheme.text_tc(self, chip.get_center().x, chip.position.y + 20.0, "MOTION ARENA", 18,
		Color(6.0 / 255.0, 33.0 / 255.0, 12.0 / 255.0), 2.4)
	PSTheme.text_t(self, Vector2(chip.end.x + 12.0, chip.position.y + 20.0), "TV EDITION",
		18, Color(150.0 / 255.0, 205.0 / 255.0, 230.0 / 255.0, 0.7), 2.0)
	draw_line(Vector2(left, chip.end.y + 8.0), Vector2(left + inner_w, chip.end.y + 8.0),
		PSTheme.TV_LINE_SOFT, 1.0)
	# ---- logo row: lime snake-dot + gradient H1 (58/900, ls 2.32) ----
	var h1 := _cn("体感贪吃蛇", "POSE SNAKE")
	var h1_w: float = PSTheme.measure_t(h1, 58, 2.32).x
	var dot_c := Vector2(cx + 26.0 - h1_w * 0.5 - 30.0, SLAB.position.y + 90.0)
	draw_circle(dot_c, 18.0, Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, 0.14))
	draw_rect(Rect2(dot_c.x - 9.0, dot_c.y - 9.0, 18.0, 18.0), PSTheme.LIME, true)
	PSTheme.text_grad_c(self, cx + 26.0, SLAB.position.y + 118.0, h1, 58,
		Color(234.0 / 255.0, 1.0, 208.0 / 255.0), PSTheme.LIME, PSTheme.CYAN, 2.32)
	PSTheme.text_tc_fit(self, cx, SLAB.position.y + 158.0,
		_cn("举起手就能玩 · 8 条蛇同场比长度", "raise a hand to play · 8 snakes, one arena"),
		24, Color(196.0 / 255.0, 228.0 / 255.0, 244.0 / 255.0, 0.86), 2.86, inner_w)
	# ---- meta badges (18/700, r2, 3 px cyan left edge) ----
	var badges := [
		[_cn("2:00", "2:00"), _cn("限时", "TIMED")],
		["8", _cn("位玩家", "PLAYERS")],
		[_cn("长度", "LENGTH"), _cn("决胜", "WINS")],
		["9", _cn("屏 地图", "SCREEN MAP")],
	]
	var bx := 0.0
	var bt := SLAB.position.y + 168.0
	var bws := PackedFloat32Array()
	var total := 0.0
	for b in badges:
		var bw: float = PSTheme.measure_t(str(b[0]), 18, 0.88).x \
			+ PSTheme.measure_t(str(b[1]), 18, 0.88).x + 32.0
		bws.append(bw)
		total += bw
	total += 8.0 * float(badges.size() - 1)
	bx = cx - total * 0.5
	for i in badges.size():
		var b: Array = badges[i]
		var br := Rect2(bx, bt, bws[i], 30.0)
		draw_style_box(_badge_style, br)
		draw_rect(Rect2(br.position.x, br.position.y + 1.0, 3.0, br.size.y - 2.0),
			PSTheme.CYAN, true)
		PSTheme.text_t(self, Vector2(br.position.x + 12.0, br.position.y + 22.0), str(b[0]),
			18, PSTheme.LIME, 0.88)
		PSTheme.text_t(self, Vector2(br.position.x + 15.0
			+ PSTheme.measure_t(str(b[0]), 18, 0.88).x, br.position.y + 22.0), str(b[1]), 18,
			Color(206.0 / 255.0, 234.0 / 255.0, 250.0 / 255.0, 0.82), 0.88)
		bx += bws[i] + 8.0
	# ---- 游戏人数 + two 351x88 mode cards ----
	PSTheme.text_tc(self, cx, SLAB.position.y + 228.0, _cn("游戏人数", "PLAYERS"), 24,
		Color(150.0 / 255.0, 205.0 / 255.0, 230.0 / 255.0, 0.75), 2.86)
	var cy := SLAB.position.y + 240.0
	var x0 := cx - (CARD_W * 2.0 + CARD_GAP) * 0.5
	for i in 2:
		_draw_mode_card(Rect2(x0 + float(i) * (CARD_W + CARD_GAP), cy, CARD_W, CARD_H), i)
	# ---- 角色 row: remote DPAD changes the player's character ----
	_draw_skin_row(cx, SLAB.position.y + 338.0)
	# ---- pose status (the web's `#panelHint` slot): the actionable TV hint, 32 px
	var hint := _pose_status_text()
	var hint_col := PSTheme.TV_GOLD
	if bridge_ok and (bridge_bound or bridge_frames > 0):
		hint_col = PSTheme.LIME
	PSTheme.text_tc_fit(self, cx, SLAB.position.y + 420.0, hint, 32, hint_col, 0.32, inner_w)
	# ---- fineprint: 24 px body copy (was 10.5). It stays one size below the hint
	# because the two lines plus the keycaps have to share the slab's last 160 px.
	PSTheme.text_tc_fit(self, cx, SLAB.position.y + 454.0,
		_cn("站到镜头前约 2 米，上半身完整入镜", "stand ~2 m from the camera, full torso in view"),
		24, Color(160.0 / 255.0, 196.0 / 255.0, 218.0 / 255.0, 0.72), 0.32, inner_w)
	# ---- pad hints: the port is remote-only, so the keycaps are OK / BACK.
	# `_draw_pad_hints` puts the keycap top at y-19 and its bottom at y+7.
	_draw_pad_hints(cx, SLAB.position.y + 496.0)
	# ---- rules line ----
	PSTheme.text_tc_fit(self, cx, SLAB.position.y + 532.0,
		_cn("操作：举手转向 · 手伸远加速　完整规则见下方「玩法说明」",
			"controls: raise a hand to steer, reach to boost - full rules in HOW TO PLAY"),
		18, Color(190.0 / 255.0, 220.0 / 255.0, 238.0 / 255.0, 0.62), 0.8, inner_w)
	_draw_bridge_chip(w - 40.0, 34.0)
	# ---- options bar + how-to-play (under the slab, over everything) ----
	_draw_options_bar()
	_draw_help()


## Decorative food head on the mode-select / ready backdrops. Food is two baked
## layers now (body + face overlay, see `PSAssets`), so a decoration is two blits.
func _draw_deco_face(p: Vector2, s: float, idx: int, alpha: float) -> void:
	var r := Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s)
	var tint := Color(1, 1, 1, alpha)
	draw_texture_rect(PSAssets.food_body[idx % PSAssets.food_body.size()], r, false, tint)
	draw_texture_rect(PSAssets.food_face[(idx % PSAssets.FOOD_FACES.size()) * 2], r, false,
		tint)


func _pose_status_text() -> String:
	if not bridge_ok:
		return _cn("体感不可用", "POSE NOT AVAILABLE")
	if bridge_frames <= 0:
		return _cn("正在准备体感资源", "PREPARING POSE")
	if persons > 0:
		return _cn("已识别 %d 人 · 举手即可开始" % persons, "%d PERSON(S) · RAISE A HAND" % persons)
	return _cn("等待玩家进入画面", "WAITING FOR A PLAYER")


## Keycap row (`#padBar .keycap`). Typography pass: keycap glyph 10 -> 16 px,
## keycap 20 -> 26 px tall, label 11 -> 20 px, so the remote legend stays readable
## at 3 m without taking the slab's whole width (336 px total).
func _draw_pad_hints(cx: float, y: float) -> void:
	var items := [[_cn("OK", "OK"), _cn("确认", "CONFIRM")],
		[_cn("◀ ▶", "LEFT/RIGHT"), _cn("选择", "SELECT")],
		[_cn("返回", "BACK"), _cn("退出", "EXIT")]]
	var widths := PackedFloat32Array()
	var total := 0.0
	for it in items:
		var kw: float = PSTheme.measure_t(str(it[0]), 16, 0.6).x + 16.0
		var tw: float = PSTheme.measure_t(str(it[1]), 20, 0.44).x
		widths.append(kw + 8.0 + tw)
		total += kw + 8.0 + tw
	total += 24.0 * float(items.size() - 1)
	var x := cx - total * 0.5
	for i in items.size():
		var it: Array = items[i]
		var kw2: float = PSTheme.measure_t(str(it[0]), 16, 0.6).x + 16.0
		var kc := Rect2(x, y - 19.0, kw2, 26.0)
		draw_rect(kc, Color(226.0 / 255.0, 250.0 / 255.0, 1.0, 1.0), true)
		PSTheme.text_tc(self, kc.get_center().x, kc.position.y + 19.0, str(it[0]), 16,
			Color(4.0 / 255.0, 16.0 / 255.0, 28.0 / 255.0), 0.6)
		PSTheme.text_t(self, Vector2(kc.end.x + 8.0, kc.position.y + 19.0), str(it[1]), 20,
			Color(190.0 / 255.0, 220.0 / 255.0, 238.0 / 255.0, 0.78), 0.44)
		x += widths[i] + 24.0


# ------------------------------------------------------- select options bar
## The three player-facing choices that are not a game mode. They live UNDER the
## title slab, in the empty lower third the web leaves empty (its reference screen
## is logo + two cards only), so the slab itself stays pixel-identical to the
## measured web skin.
##
##   * 玩法说明  — opens the how-to-play overlay (OK / any direction).
##   * 音效 开/关 — the mute control (`PSAudio.muted`, persisted `[audio] muted`).
##   * 赛制 限时/无尽 — `cfg.round.mode`, persisted `[round] mode`.
##
## Reachable with DPAD DOWN from the character row; LEFT/RIGHT/OK actuate the
## focused chip (same interaction as the character row, so the remote never needs
## a key the box does not have). Focus slots are 3/4/5 — main.gd mirrors these
## (`OPT_HELP` / `OPT_SOUND` / `OPT_ROUND`).
const OPT_BAR_Y := 872.0
const OPT_H := 64.0
const OPT_GAP := 22.0
const OPT_W_HELP := 300.0
const OPT_W_SOUND := 300.0
const OPT_W_ROUND := 400.0


func _draw_options_bar() -> void:
	var cx := size.x * 0.5
	var total := OPT_W_HELP + OPT_W_SOUND + OPT_W_ROUND + OPT_GAP * 2.0
	var x := cx - total * 0.5
	# Primary navigation row -> 24 px caption (the file's label floor).
	PSTheme.text_tc(self, cx, OPT_BAR_Y - 16.0,
		_cn("设置 · 方向键选择 · OK 确认", "OPTIONS · DPAD select · OK confirm"),
		24, Color(160.0 / 255.0, 196.0 / 255.0, 218.0 / 255.0, 0.72), 1.2)
	_opt_chip(Rect2(x, OPT_BAR_Y, OPT_W_HELP, OPT_H), OPT_HELP,
		_cn("玩法说明", "HOW TO PLAY"), _cn("查看", "OPEN"), PSTheme.CYAN)
	x += OPT_W_HELP + OPT_GAP
	_opt_chip(Rect2(x, OPT_BAR_Y, OPT_W_SOUND, OPT_H), OPT_SOUND,
		_cn("音效", "SOUND"), _cn("开", "ON") if audio_on else _cn("关", "OFF"),
		PSTheme.LIME if audio_on else PSTheme.MUTED)
	x += OPT_W_SOUND + OPT_GAP
	_opt_chip(Rect2(x, OPT_BAR_Y, OPT_W_ROUND, OPT_H), OPT_ROUND,
		_cn("赛制", "MODE"),
		_cn("限时 2:00", "TIMED 2:00") if round_mode == "timed"
			else _cn("无尽练习", "ENDLESS"),
		PSTheme.TV_GOLD)


## One chip: label on the left, current value right-aligned, 3 px accent edge.
func _opt_chip(r: Rect2, slot: int, label: String, value: String, value_col: Color) -> void:
	var hot: bool = select_focus == slot
	if hot:
		draw_texture_rect(PSAssets.blob, r.grow(20.0), false,
			Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, 0.09))
	draw_style_box(_ps_btn_hi if hot else _ps_btn, r)
	draw_rect(Rect2(r.position.x, r.position.y + 10.0, 3.0, r.size.y - 20.0),
		PSTheme.LIME if hot else PSTheme.with_a(PSTheme.CYAN, 0.55), true)
	PSTheme.text_vc(self, r.position.x + 22.0, r.position.y + r.size.y * 0.5, label, 30,
		PSTheme.TEXT if hot else PSTheme.TEXT_SOFT)
	if value != "":
		PSTheme.text_r(self, r.end.x - 22.0, r.position.y + r.size.y * 0.5 + 10.0, value,
			30, value_col)


# ------------------------------------------------------------ how to play
## Full-screen rules card (owner: a shipped game needs readable 玩法, not one
## line of small print). Remote-only: OK or BACK closes it, and while it is open
## `main.gd` routes every action here instead of to the menu underneath.
const HELP_BOX := Rect2(240.0, 132.0, 1440.0, 816.0)
const HELP_ROW_Y := 150.0
const HELP_ROW_H := 62.0
const HELP_ROW_SZ := 30


func _draw_help() -> void:
	if not help_open:
		return
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.008, 0.02, 0.038, 0.88), true)
	draw_texture_rect(PSAssets.blob, HELP_BOX.grow(90.0), false,
		Color(0.337, 0.910, 1.0, 0.05))
	draw_texture_rect(PSAssets.panel_grad, HELP_BOX, false)
	draw_style_box(_slab_edge, HELP_BOX)
	draw_style_box(_slab_top, HELP_BOX)
	var tab := Rect2(HELP_BOX.position.x + 40.0, HELP_BOX.position.y + 40.0, 470.0, 46.0)
	draw_rect(tab, PSTheme.CYAN, true)
	PSTheme.text_t(self, Vector2(tab.position.x + 16.0, tab.position.y + 32.0),
		_cn("玩法说明", "HOW TO PLAY"), 28, PSTheme.INK, 1.2)
	# 8 numbered rows: number chip + one sentence, both wrapped in the box.
	var rows := [
		[_cn("目标", "GOAL"),
			_cn("8 条蛇同场竞技，结算按最终长度排名，最长者获胜",
				"8 snakes, one arena - the longest body when the whistle blows wins")],
		[_cn("转向", "STEER"),
			_cn("举起右手，手臂指向哪边，蛇就转向哪边",
				"raise your RIGHT hand: the snake turns the way the arm points")],
		[_cn("加速", "BOOST"),
			_cn("手向身体外侧伸远就加速，收回身体附近就减速",
				"reach out to speed up, pull the hand in to slow down")],
		[_cn("进食", "FOOD"),
			_cn("吞下食物 +1 节，大食物 +3 节；吞并对手按对方长度加成",
				"pellet +1, big pellet +3, swallowing a rival adds its length")],
		[_cn("死亡", "DEATH"),
			_cn("撞墙或撞到别人的身体会死亡，3 秒后原地复活",
				"a wall or any body kills you - you respawn 3 s later")],
		[_cn("道具", "POWER-UPS"),
			_cn("加速 5 秒（速度 x1.65） · 磁铁 10 秒（把食物吸过来）",
				"boost 5 s (x1.65 speed) - magnet 10 s (pulls food in)")],
		[_cn("赛制", "MODES"),
			_cn("限时 2:00 到点结算；无尽练习不结算，返回键可暂停退出",
				"timed 2:00 settles at zero; endless never ends (BACK pauses)")],
		[_cn("遥控器", "REMOTE"),
			_cn("左右选择 · OK 确认 · 返回键 暂停 / 返回",
				"left/right select - OK confirm - BACK pause / back")],
	]
	var x0 := HELP_BOX.position.x + 44.0
	var y := HELP_BOX.position.y + HELP_ROW_Y
	for i in rows.size():
		var row: Array = rows[i]
		# number plate
		draw_rect(Rect2(x0, y - 22.0, 34.0, 34.0), PSTheme.with_a(PSTheme.CYAN, 0.14), true)
		PSTheme.text_vc(self, x0 + 17.0, y - 5.0, str(i + 1), 22, PSTheme.CYAN)
		PSTheme.text_t(self, Vector2(x0 + 52.0, y), String(row[0]), HELP_ROW_SZ,
			PSTheme.LIME, 1.2)
		PSTheme.text_t(self, Vector2(x0 + 210.0, y), String(row[1]), HELP_ROW_SZ,
			PSTheme.TEXT_SOFT, 1.0)
		y += HELP_ROW_H
	PSTheme.text_tc_fit(self, HELP_BOX.get_center().x,
		HELP_BOX.end.y - 34.0, _cn("按 OK 或返回键关闭", "OK or BACK closes"),
		26, Color(1, 1, 1, 0.55), 0.32, HELP_BOX.size.x - 80.0)



## `角色 [◀] (portrait) 辣椒蛇 [▶]` — the player's character picker, under the
## mode cards on the select screen.
##
## Remote-first: the row is focus slot 2 (`SKIN_FOCUS`), reached with DOWN from the
## two mode cards; while it is focused LEFT/RIGHT step the character and the rest
## of the menu keeps its old key handling untouched. The portrait is four region
## blits out of the character's head atlas (head, eyes, mouth, decor) — the same
## regions the world view samples, so the row shows exactly what the snake is.
const SKIN_FOCUS := 2
const SKIN_ROW_H := 48.0


func _draw_skin_row(cx: float, y: float) -> void:
	if PSSkins.count() == 0:
		return
	var row := Rect2(cx - 186.0, y, 372.0, SKIN_ROW_H)
	var hot: bool = select_focus == SKIN_FOCUS
	var sk: int = PSSkins.player_skin
	var skd: Dictionary = PSSkins.get_skin(sk)
	var accent: Color = skd.get("halo", PSTheme.CYAN)
	if hot:
		draw_texture_rect(PSAssets.blob, row.grow(18.0), false,
			Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, 0.09))
	draw_style_box(_ps_btn_hi if hot else _ps_btn, row)
	draw_rect(Rect2(row.position.x, row.position.y + 6.0, 3.0, row.size.y - 12.0),
		accent, true)
	PSTheme.text_t(self, Vector2(row.position.x + 12.0, row.position.y + 31.0),
		_cn("角色", "SKIN"), 22, PSTheme.LABEL_DIM, 2.0)
	_skin_arrow(Rect2(row.position.x + 58.0, row.position.y + 10.0, 30.0, 28.0), -1, hot)
	_skin_arrow(Rect2(row.position.x + 322.0, row.position.y + 10.0, 30.0, 28.0), 1, hot)
	# the head base is 130 atlas texels tall; 34 px keeps head + decor + mouth
	# inside the 48 px row when the anchor sits 25 px down
	_draw_skin_face(Vector2(row.position.x + 118.0, row.position.y + 25.0), sk, 34.0, 1.0)
	PSTheme.text_tc(self, row.position.x + 236.0, row.position.y + 33.0,
		String(skd.get("name", "?")), 26, PSTheme.LIME if hot else PSTheme.TEXT, 1.0)


func _skin_arrow(r: Rect2, dir: int, hot: bool) -> void:
	var col := PSTheme.LIME if hot else Color(0.72, 0.86, 1.0, 0.75)
	draw_rect(r, Color(226.0 / 255.0, 250.0 / 255.0, 1.0, 0.08), true)
	draw_rect(r, Color(col.r, col.g, col.b, 0.40), false, 1.0)
	var c := r.get_center()
	var h := 6.0
	if dir < 0:
		draw_colored_polygon(PackedVector2Array([c + Vector2(h, -h),
			c + Vector2(h, h), c + Vector2(-h, 0.0)]), col)
	else:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-h, -h),
			c + Vector2(-h, h), c + Vector2(h, 0.0)]), col)


## Portrait out of the character's head atlas. `anchor` is where the pack's head
## anchor (199,900) goes; `head_h` is the drawn height of the head base.
func _draw_skin_face(anchor: Vector2, sk: int, head_h: float, alpha: float) -> void:
	var tex := PSSkins.atlas_tex(sk)
	if tex == null:
		return
	var hr := PSSkins.region(sk, "head")
	if hr.size.y <= 0.0:
		return
	var k: float = head_h / hr.size.y
	var tint := Color(1.0, 1.0, 1.0, alpha)
	for key in ["head", "eyes_open", "mouth_closed", "decor"]:
		var r := PSSkins.region(sk, key)
		if r.size.x <= 0.0:
			continue
		var o := PSSkins.region_off(sk, key)
		draw_texture_rect_region(tex, Rect2(anchor + o * k, r.size * k), r, tint)


func _draw_mode_card(r: Rect2, i: int) -> void:
	var hot: bool = select_focus == i
	if hot:
		# `#overlay .ps-btn.active`: lime edge + a lime glow skirt
		draw_texture_rect(PSAssets.blob, r.grow(26.0), false,
			Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, 0.10))
	draw_style_box(_ps_btn_hi if hot else _ps_btn, r)
	# 19/11.5 -> 34/20 px: the card's own name is a critical TV label, and 351x88
	# is still the web card's width and visual language (r3, 3 px lime bottom edge).
	PSTheme.text_tc_fit(self, r.get_center().x, r.position.y + 40.0,
		_cn("1 人", "1 PLAYER") if i == 0 else _cn("2 人", "2 PLAYERS"), 34,
		PSTheme.LIME, 1.52, r.size.x - 24.0)
	PSTheme.text_tc_fit(self, r.get_center().x, r.position.y + 74.0,
		_cn("你 + 7 个 AI", "you + 7 AI") if i == 0
			else _cn("左右分屏 · 6 个 AI", "split screen · 6 AI"),
		20, Color(210.0 / 255.0, 240.0 / 255.0, 220.0 / 255.0, 0.88), 0.69,
		r.size.x - 24.0)
	_btns.append([BTN_MODE_1P if i == 0 else BTN_MODE_2P, r])


func _draw_bridge_chip(right: float, top: float) -> void:
	var r := Rect2(right - 286.0, top, 286.0, 58.0)
	draw_style_box(_chip_style, r)
	var ok_col: Color = PSTheme.LIME if bridge_bound or bridge_frames > 0 else PSTheme.TV_GOLD
	var ctxt := _cn("体感就绪", "POSE READY")
	if not bridge_ok:
		ok_col = PSTheme.MUTED_DARK
		ctxt = _cn("体感不可用", "POSE N/A")
	elif bridge_frames <= 0:
		ctxt = _cn("等待体感", "POSE WAIT")
	draw_circle(Vector2(r.position.x + 26.0, r.position.y + 29.0), 7.0, ok_col)
	PSTheme.text_vc(self, r.position.x + 46.0, r.position.y + 29.0, ctxt, 24,
		PSTheme.TEXT_SOFT)


# ------------------------------------------------------------------ ready

## ---- READY slot card: the reference's portrait photo card, 1:1 -------------
## `KinestheticInfoForm.findPlayerRoot` (Unity, 1920x1080 canvas — so these are
## our design px verbatim, see `Docs/UI-REFERENCE-1024.md` §4.4):
##   * `frame/cameraTex`  428 x 624  (portrait photo; our RGBA pane)
##   * `frame/outline`    436 x 632  (4 px bezel)
##   * `progress/bg|fill` 218 x 488  (vertical gauge, dead-centre of the photo)
##   * `headIcon`         100 x 100, straddling the photo's top edge: its bottom
##                        sits 13 px INSIDE the photo (prefab: photo top 228,
##                        icon 141..241)
##   * `txtLabel`         60 px status, above the icon
##   * player_1/player_2 centres 572/1348 -> **776 px** apart (`_baseCardSpacing`)
const READY_FRAME := 4.0
const READY_CARD_W := 428.0
const READY_CARD_H := 624.0
## Card row top. Chosen so the 100 px head icon (83 px above the card) clears the
## 26 px control prompt and the 60 px status line, and the card bottom (925)
## clears the advisory strip (940) and the bottom hint (baseline 1046).
const READY_CARD_TOP := 293.0
const READY_SPACING := 776.0
const READY_ICON := 100.0
const READY_ICON_OVER := 13.0
const READY_BAR_W := 218.0
const READY_BAR_H := 488.0
## Gauge top inside the card: below the 24 px "玩家 N" header (which sits at
## card.y+28), so the 488 px bar ends at card.y+534 = 827 — 6 px above the
## 60 px status ink, and still inside the 624 px photo.
const READY_BAR_TOP := 46.0
const READY_STATUS_SZ := 60
const READY_HOLD_SZ := 22
## Entry motion (reference `KinestheticInfoForm.cs:352-377`): the panel slides
## from `ap.y = +1400` to 0 over 0.3 s, OutQuad. Cards only — the port's header,
## title and prompt stay put, so the screen does not fade as a whole.
const READY_SLIDE_FROM := 1400.0
const READY_SLIDE_SEC := 0.3


func _draw_ready(offset_y: float = 0.0, draw_scrim: bool = true) -> void:
	_btns.clear()
	var w := size.x
	var h := size.y
	if draw_scrim:
		# Opaque designed backdrop (like mode select), tinted per player slot:
		# no arena / food bleed-through behind the cards.
		draw_texture_rect(PSAssets.bg_grad, Rect2(0, 0, w, h), false)
		draw_texture_rect(PSAssets.grid, Rect2(0, 0, w, h), true, Color(0.6, 0.9, 1.0, 0.34))
		if player_count > 1:
			draw_rect(Rect2(0, 0, w * 0.5, h), PSTheme.with_a(PSTheme.SLOT_1, 0.13), true)
			draw_rect(Rect2(w * 0.5, 0, w * 0.5, h), PSTheme.with_a(PSTheme.SLOT_2, 0.16), true)
		else:
			draw_rect(Rect2(0, 0, w, h), PSTheme.with_a(PSTheme.SLOT_1, 0.07), true)
		draw_texture_rect(PSAssets.blob,
			Rect2(w * 0.5 - 900.0, 320.0, 1800.0, 1000.0), false,
			Color(0.95, 0.30, 0.14, 0.10))
		# Same decorative faces as mode select, dimmed: the ready screen stays
		# focused on the cards but does not read as a black void.
		if not _deco.is_empty():
			for d in _deco:
				var p: Vector2 = d[0]
				var s: float = d[2]
				_draw_deco_face(p, s, int(d[1]), 0.15)
	var oy := offset_y
	# ---- header ----
	# x=448, not x=48: the SDK camera preview is composited ABOVE this app into
	# the band's mirror box (90..410, y 8.5..188.5), which is armed during
	# READY/COUNTDOWN too — the header must not sit under it.
	var hx := 448.0
	draw_rect(Rect2(hx, 40.0 + oy, 104.0, 42.0), PSTheme.LIME, true)
	PSTheme.text_vc(self, hx + 12.0, 61.0 + oy, _cn("准备", "READY"), 22, PSTheme.INK)
	PSTheme.text_vc(self, hx + 124.0, 61.0 + oy, _mode_label(), 32, PSTheme.TEXT)
	# 2P has a second mirror box at the top right (1596..1864), so the tracking
	# chip drops below the band there.
	_draw_tracking_chip(w - 40.0, (34.0 if player_count <= 1 else 200.0) + oy)
	# ---- title + the single control prompt (the cards own y>=210) ----
	PSTheme.text_c(self, w * 0.5, 146.0 + oy, _cn("准备开始", "GET READY"), 56, PSTheme.TEXT)
	PSTheme.text_c_fit(self, w * 0.5, 196.0 + oy,
		_cn("举起右手 → 方向 · 手伸远 → 加速", "raise a hand to steer · reach out to speed up"),
		30, PSTheme.TEXT_SOFT, 1500.0)
	# ---- slot cards: 428x624 photo + 4 px outline, 776 px centre spacing ----
	var n := clampi(player_count, 1, 2)
	var card_w := READY_CARD_W + READY_FRAME * 2.0
	var row_w := READY_SPACING * float(n - 1) + card_w
	var x0 := (w - row_w) * 0.5
	var dy := oy + ready_card_dy
	for i in n:
		_draw_ready_card(Rect2(x0 + float(i) * READY_SPACING, READY_CARD_TOP + dy,
			card_w, READY_CARD_H + READY_FRAME * 2.0), i)
	# ---- 30 s nobody-detected advisory (never starts anything) ----
	if nobody_hint:
		_draw_nobody_panel(oy)
	# ---- navigation hint (remote only). x=84 clears the OSD bracket's vertical
	# arm (x=44..46) and its bottom horizontal arm (x=44..74 at y=1036); the perf
	# panel lives at x>=1536, so the two cannot meet either.
	PSTheme.text(self, Vector2(84.0, h - 34.0 + oy),
		_cn("按返回键回到模式选择", "BACK to mode select"), 32, Color(1, 1, 1, 0.52))


func _mode_label() -> String:
	return _cn("双人模式", "TWO PLAYERS") if player_count > 1 else _cn("单人模式", "ONE PLAYER")


func _draw_tracking_chip(right: float, top: float) -> void:
	var r := Rect2(right - 286.0, top, 286.0, 58.0)
	draw_style_box(_chip_style, r)
	var col := PSTheme.MUTED_DARK
	var ctxt := _cn("体感不可用", "POSE N/A")
	if bridge_ok:
		if not tracking:
			col = PSTheme.TV_GOLD
			ctxt = _cn("等待体感", "WAITING FOR POSE")
		elif persons > 0:
			col = PSTheme.LIME
			ctxt = _cn("已识别 %d 人" % persons, "%d PERSON(S)" % persons)
		else:
			col = PSTheme.TV_GOLD
			ctxt = _cn("未识别到人", "NO PERSON")
	draw_circle(Vector2(r.position.x + 26.0, r.position.y + 29.0), 7.0, col)
	PSTheme.text_vc(self, r.position.x + 46.0, r.position.y + 29.0, ctxt, 24,
		PSTheme.TEXT_SOFT)


func _draw_ready_card(cr: Rect2, i: int) -> void:
	var col: Color = PSTheme.SLOT_1 if i == 0 else PSTheme.SLOT_2
	var st: int = int(ready_state[i]) if i < ready_state.size() else SLOT_WAITING
	var fill: float = float(ready_fill[i]) if i < ready_fill.size() else 0.0
	var pop: float = float(ready_pop[i]) if i < ready_pop.size() else 0.0
	var is_ready: bool = st == SLOT_READY
	var photo := cr.grow(-READY_FRAME)
	# ---- card plate + slot accent edge ----
	draw_style_box(_ready_card[i], cr)
	draw_rect(Rect2(cr.position.x + 18.0, cr.position.y, cr.size.x - 36.0, 4.0),
		PSTheme.with_a(col, 0.9), true)
	# ---- person viewport: live camera (one shared RGBA frame) or placeholder ----
	# 1P shows the whole frame; 2P shows this player's own half with the same rule
	# as main.gd's `CAMERA_2P_SRC` and the SDK overlay: slot 0 is the LEFT half of
	# the mirrored image, i.e. the raw sensor's RIGHT half.
	var uv: Rect2 = CAM_FULL_UV
	if player_count > 1:
		uv = CAM_2P_UV[i] if cam_pose_mirror else CAM_2P_UV[1 - i]
	if cam_rgba_tex != null:
		_draw_cam_frame(photo, uv)
	else:
		draw_style_box(_ready_inner, photo)
		_draw_person(photo.get_center().x, photo.get_center().y + 10.0, 190.0,
			col if st != SLOT_WAITING else PSTheme.MUTED_DARK)
	# ---- 218x488 vertical gauge (reference `progress/bg|fill`), drawn BEFORE the
	# bones so the live skeleton overlay always stays readable on top of it ----
	_draw_ready_bar(cr, col, fill, is_ready)
	# ---- same pixels, same transform -> this slot's skeleton lands on the person
	# in this pane (the cover-crop is aspect-parametric, see `_cam_src_rect`) ----
	if cam_rgba_tex != null:
		_draw_pose_skeleton(photo, uv, i)
		draw_rect(photo.grow(1.0), PSTheme.with_a(col, 0.55), false, 2.0)
	var br_col: Color = PSTheme.with_a(col, 0.65) if st != SLOT_WAITING \
		else Color(1, 1, 1, 0.14)
	_draw_corner_brackets(photo, br_col)
	if is_ready:
		_draw_stamp(photo.get_center(), pop)
	# ---- slot header, over the pixels (outlined text keeps it legible) ----
	draw_circle(Vector2(cr.position.x + 24.0, cr.position.y + 28.0), 7.0,
		col if st != SLOT_WAITING else PSTheme.MUTED_DARK)
	PSTheme.text_vc(self, cr.position.x + 40.0, cr.position.y + 28.0,
		_cn("玩家 %d" % (i + 1), "PLAYER %d" % (i + 1)), 24, PSTheme.TEXT_SOFT)
	if player_count > 1:
		PSTheme.text_r(self, cr.end.x - 20.0, cr.position.y + 36.0,
			_cn("画面左侧", "LEFT SIDE") if i == 0 else _cn("画面右侧", "RIGHT SIDE"),
			24, PSTheme.MUTED)
	# ---- headIcon 100x100 straddling the photo's top edge (its bottom 13 px are
	# on the photo, exactly like the reference's 141..241 vs photo 228) ----
	_draw_ready_head_icon(cr, i, col)
	# ---- status line 60 px + the hold cue ----
	var st_col := PSTheme.MUTED
	match st:
		SLOT_RAISE:
			st_col = PSTheme.TEXT
		SLOT_READY:
			st_col = PSTheme.CHECK
	PSTheme.text_c_fit(self, cr.get_center().x, cr.end.y - 40.0, _ready_label(st),
		READY_STATUS_SZ, st_col, cr.size.x - 16.0, 40)
	if is_ready:
		PSTheme.text_c(self, cr.get_center().x, cr.end.y - 6.0,
			_cn("请保持举手", "hold your hand up"), READY_HOLD_SZ,
			PSTheme.with_a(PSTheme.CHECK, 0.75))


## `progress/bg` + `progress/fill`: 218 x 488, dead-centre of the 428 px photo in
## the reference. The plate is deliberately translucent (the reference's camera is
## behind it too): the pane stays a camera, the gauge reads as a fill meter over
## the player. Cost: 1 plate rect + 1 hairline + 3 tick lines + 1 gradient blit +
## 1 text, i.e. the same order as the old 64x280 bar.
func _draw_ready_bar(cr: Rect2, col: Color, fill: float, is_ready: bool) -> void:
	var bar := Rect2(cr.get_center().x - READY_BAR_W * 0.5, cr.position.y + READY_BAR_TOP,
		READY_BAR_W, READY_BAR_H)
	draw_rect(bar, Color(0.012, 0.03, 0.055, 0.42), true)
	draw_rect(bar, Color(1.0, 1.0, 1.0, 0.10), false, 1.0)
	for k in 3:
		var ty := bar.end.y - bar.size.y * (float(k + 1) * 0.25)
		draw_line(Vector2(bar.position.x + 12.0, ty), Vector2(bar.end.x - 12.0, ty),
			Color(1, 1, 1, 0.10), 1.0)
	if not is_ready and fill > 0.004:
		var fh: float = (bar.size.y - 10.0) * clampf(fill, 0.0, 1.0)
		draw_texture_rect(PSAssets.grad_v,
			Rect2(bar.position.x + 5.0, bar.end.y - 5.0 - fh, bar.size.x - 10.0, fh), false,
			PSTheme.with_a(col, 0.62))
		draw_rect(Rect2(bar.position.x + 5.0, bar.end.y - 5.0 - fh, bar.size.x - 10.0, 3.0),
			PSTheme.with_a(PSTheme.lighten(col, 0.45), 0.95), true)
	PSTheme.text_c(self, bar.get_center().x, bar.end.y - 14.0,
		"%d%%" % int(round(fill * 100.0)), 26,
		PSTheme.CHECK if is_ready else PSTheme.TEXT_SOFT)


## The reference's `headIcon` (100 x 100, `imgIcon` = the character's head): the
## port's stand-in is the same head-atlas portrait the mode-select skin row uses,
## inside the slot-coloured ring. Drawn last so it overlaps the card's top edge.
func _draw_ready_head_icon(cr: Rect2, i: int, col: Color) -> void:
	var c := Vector2(cr.get_center().x,
		cr.position.y - READY_ICON * 0.5 + READY_FRAME + READY_ICON_OVER)
	draw_circle(c, READY_ICON * 0.5 + 5.0, Color(0.012, 0.03, 0.055, 0.88))
	draw_circle(c, READY_ICON * 0.5, Color(0.05, 0.075, 0.13, 0.97))
	draw_arc(c, READY_ICON * 0.5, 0.0, TAU, 40, PSTheme.with_a(col, 0.92), 3.0, true)
	var sk: int = PSSkins.player_skin
	if game != null and game.snakes.size() > i and PSSkins.usable(PSSkins.of(game.snakes[i])):
		sk = PSSkins.of(game.snakes[i])
	# the head base is anchored at its bottom-centre: 54 px tall, 27 px down from
	# the circle's centre, keeps head + decor inside the 100 px ring
	_draw_skin_face(c + Vector2(0.0, 27.0), sk, 54.0, 1.0)


func _draw_corner_brackets(r: Rect2, col: Color) -> void:
	var l := 26.0
	draw_line(r.position, r.position + Vector2(l, 0.0), col, 2.0)
	draw_line(r.position, r.position + Vector2(0.0, l), col, 2.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - l, r.position.y), col, 2.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + l), col, 2.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + l, r.end.y), col, 2.0)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - l), col, 2.0)
	draw_line(r.end, r.end - Vector2(l, 0.0), col, 2.0)
	draw_line(r.end, r.end - Vector2(0.0, l), col, 2.0)


## Simple "bust" pictogram (head + shoulders), no textures.
func _draw_person(cx: float, cy: float, s: float, col: Color) -> void:
	draw_circle(Vector2(cx, cy - s * 0.30), s * 0.24, col)
	draw_arc(Vector2(cx, cy + s * 0.55), s * 0.58, PI, TAU, 24, col, maxf(2.0, s * 0.12), true)


## Green check stamp with the reference's 0.3 s pop (scale 0 -> 1 with overshoot).
func _draw_stamp(c: Vector2, pop: float) -> void:
	var k := clampf(pop / 0.32, 0.0, 1.0)
	var sc := k * (1.0 + 0.18 * sin(k * PI))
	var rr := 64.0 * sc
	if rr < 1.0:
		return
	draw_circle(c, rr + 10.0, PSTheme.with_a(PSTheme.CHECK, 0.18))
	draw_circle(c, rr, PSTheme.CHECK)
	draw_arc(c, rr, 0.0, TAU, 48, PSTheme.darken(PSTheme.CHECK, 0.35), 3.0, true)
	var lw := maxf(2.0, 9.0 * sc)
	draw_line(c + Vector2(-rr * 0.42, 0.0), c + Vector2(-rr * 0.10, rr * 0.34),
		Color(1, 1, 1, 1), lw, true)
	draw_line(c + Vector2(-rr * 0.12, rr * 0.36), c + Vector2(rr * 0.46, -rr * 0.34),
		Color(1, 1, 1, 1), lw, true)


## 30 s with nobody in view: advisory only. There is no button and no auto-start;
## the remote BACK (accepted on every READY frame) is the way out. The strip sits
## under the cards (925) and is centred, so it never touches the bottom-left hint
## (x=84) nor the perf panel (x>=1536).
func _draw_nobody_panel(oy: float) -> void:
	var w := size.x
	var er := Rect2(w * 0.5 - 390.0, 940.0 + oy, 780.0, 56.0)
	draw_style_box(_nobody_panel, er)
	draw_circle(Vector2(er.position.x + 30.0, er.position.y + 28.0), 8.0, PSTheme.TV_GOLD)
	PSTheme.text_vc(self, er.position.x + 50.0, er.position.y + 28.0,
		_cn("没有检测到玩家 · 请站到镜头前", "NO PLAYER · STEP INTO VIEW"),
		28, PSTheme.TEXT)


## The 60 px reference label, shortened so a CJK run at 60 px still fits the
## 428 px photo (424 px of usable ink width): the full sentences used to be
## 等待玩家进入屏幕 / 请举手确认准备, which need 540 / 420 px at this size.
func _ready_label(st: int) -> String:
	match st:
		SLOT_RAISE:
			return _cn("请举手确认", "RAISE A HAND")
		SLOT_READY:
			return _cn("已准备", "READY")
		_:
			return _cn("等待玩家入镜", "WAITING")


# ------------------------------------------------------ opening GO! beat

func _draw_go_beat() -> void:
	_btns.clear()
	var w := size.x
	var h := size.y
	var k := clampf(countdown_beat, 0.0, 1.0)
	# The band is already live during the opening beat (frozen clock at 2:00,
	# rank 1/8), so the GO! flourish reads as a transition inside the console
	# instead of a black strip above a live arena.
	_draw_band()
	# The ready panel slides up and dims while the beat takes over.
	if ready_slide < 1.0:
		_draw_ready(-ready_slide * 300.0, false)
	draw_rect(Rect2(0, 0, w, h), Color(0.01, 0.02, 0.04, 0.26 + 0.26 * k), true)
	var cx := w * 0.5
	var cy := h * 0.46
	var rr := 220.0 - 70.0 * k
	draw_circle(Vector2(cx, cy), rr, Color(0.0, 0.0, 0.0, 0.30))
	draw_arc(Vector2(cx, cy), rr, -PI * 0.5,
		-PI * 0.5 + TAU * clampf(k * 1.15, 0.0, 1.0), 64,
		PSTheme.with_a(PSTheme.LIME, 0.92), 8.0, true)
	var grow := 0.72 + 0.40 * (1.0 - pow(1.0 - clampf(k * 2.6, 0.0, 1.0), 2.0))
	var col := PSTheme.LIME.lerp(Color.WHITE, 0.25 * (1.0 - k))
	PSTheme.text_c(self, cx, cy + 56.0, "GO!", int(156.0 * grow), col)
	PSTheme.text_c(self, cx, cy + 124.0, _cn("出发！", "GO!"), 32, PSTheme.TEXT_SOFT)


# --------------------------------------------------------------- play HUD

## The play screen is the band **plus the three owner-requested in-play
## affordances** (score row / minimap / leaderboard — see the header). Everything
## else outside the band is transient feedback that the web does not need because
## it shows a live camera instead: the pose-dropout chip, the respawn countdown,
## the buff chips and the GO! flash.
##
## Placement contract (1920x1080): band 0..200, OSD bracket arms at inset 44,
## mirror boxes live *inside* the band, and the three panels never overlap each
## other: score row (84,208)-(646,326), leaderboard (1536,214)-(1876,~563),
## minimap (84,901)-(304,1030). Buff chips stack under the leaderboard.
func _draw_play() -> void:
	_btns.clear()
	_draw_band()
	_prof_mark("hud.band")
	var w := size.x
	# The pause layer draws its own scrim + stats + leaderboard over this one, so
	# the in-play copies are skipped there (they would otherwise double up).
	# The one exception is the 分数 row, which the pause layer re-draws itself on
	# top of its scrim (see `_draw_pause`): score 长度 吞并 最佳 stay readable.
	var in_play: bool = mode != MODE_PAUSE
	if in_play:
		_draw_score_row()
		_prof_mark("hud.score")
		_draw_minimap()
		_prof_mark("hud.minimap")
		_draw_leaderboard(LB_PLAY_Y)
		_prof_mark("hud.leaderboard")
	var p = game.player
	# ---- buff chips (web `#buffs` is display:none; kept as gameplay feedback) ----
	# Below the leaderboard: the right edge above it now belongs to the board.
	var by := ARENA_TOP + 16.0
	if in_play:
		by = LB_PLAY_Y + _lb_height() + 14.0
	if p != null and p.alive and in_play:
		if p.has_buff(0):
			by = _buff_chip(w - 250.0, by, cfg.powerups.boost.label, p.buff_left(0),
				cfg.powerups.boost.duration_sec, cfg.powerups.boost.color)
		if p.has_buff(1):
			by = _buff_chip(w - 250.0, by, cfg.powerups.magnet.label, p.buff_left(1),
				cfg.powerups.magnet.duration_sec, cfg.powerups.magnet.color)
	# ---- respawn / freeze hint ----
	if p != null and not p.alive:
		var sec: float = game.player_respawn_in()
		PSTheme.text_c(self, w * 0.5, size.y * 0.5 - 40.0,
			_cn("%.1f 秒后复活" % sec, "RESPAWN %.1fs" % sec), 44, PSTheme.PINK)
		PSTheme.text_c(self, w * 0.5, size.y * 0.5 + 10.0,
			_cn("尸体化成了食物", "your body became food"), 26, PSTheme.MUTED)
	# ---- pose dropout hint ----
	if pose_hint != "":
		var hw := 480.0
		var hr := Rect2(w * 0.5 - hw * 0.5, ARENA_TOP + 18.0, hw, 58.0)
		draw_style_box(_chip_style, hr)
		draw_circle(Vector2(hr.position.x + 28.0, hr.position.y + 29.0), 7.0,
			PSTheme.TV_GOLD.lerp(PSTheme.DANGER, 0.4 + 0.4 * sin(time * 6.0)))
		PSTheme.text_vc(self, hr.position.x + 50.0, hr.position.y + 29.0, pose_hint, 24,
			PSTheme.TV_GOLD)
	if go_flash > 0.0:
		var a: float = clampf(go_flash, 0.0, 1.0)
		PSTheme.text_c(self, w * 0.5, size.y * 0.42, "GO!", int(140.0 * (1.4 - 0.4 * a)),
			Color(PSTheme.LIME.r, PSTheme.LIME.g, PSTheme.LIME.b, a))
	# ---- round-up banner during the last second ----
	var tl: float = game.round_left
	if tl <= 3.0 and tl > 0.0:
		draw_rect(Rect2(0, ARENA_TOP, w, size.y - ARENA_TOP),
			Color(1, 0.2, 0.3, 0.05 + 0.03 * sin(time * 14.0)), true)


# ------------------------------------------- restored in-play affordances

## 分数 / 长度 / 吞并 / 最佳 — the row the owner asked back.
##
## The web hides 分数 with `.legacy-stat` and moves 长度/吞并/最长 into the pause
## layer; this diverges on purpose. Tokens are the B1 set: radius 3, cyan `.34`
## stroke, 36/700 tracked labels, 900-weight tabular-ish values (56 px, shrunk
## per cell only when a 4-5 digit 分数 would overflow), 分数 in the accent gold.
func _draw_score_row() -> void:
	var p = game.player
	var plen: int = p.body.size() if p != null and p.alive else 0
	_score_txt[0] = str(game.score)
	_score_txt[1] = str(plen)
	_score_txt[2] = str(game.kills)
	_score_txt[3] = str(game.best_length)
	var labels := SCORE_LABELS_CJK if PSTheme.cjk_ok() else SCORE_LABELS_EN
	var y := SCORE_Y
	# The 4 cyan left edges are one `draw_multiline` (2 points each) instead of
	# four `draw_rect` calls: the row is on the play screen every frame.
	if _score_edges.size() != 8:
		_score_edges.resize(8)
	for i in 4:
		var ex := SCORE_X + float(i) * (SCORE_W + SCORE_GAP)
		_score_edges[i * 2] = Vector2(ex, y + 4.0)
		_score_edges[i * 2 + 1] = Vector2(ex, y + SCORE_H - 4.0)
	for i in 4:
		var r := Rect2(SCORE_X + float(i) * (SCORE_W + SCORE_GAP), y, SCORE_W, SCORE_H)
		draw_style_box(_score_cell, r)
		PSTheme.text_tc(self, r.get_center().x, r.position.y + 42.0, labels[i],
			SCORE_LABEL_SZ, PSTheme.TOTAL_DIM, 4.0)
		var txt: String = _score_txt[i]
		var inner: float = r.size.x - 28.0
		var vsz := SCORE_VALUE_SZ
		while vsz > 40 and PSTheme.measure_t(txt, vsz, 1.0, true).x > inner:
			vsz -= 6
		var col: Color = PSTheme.TV_GOLD if i == 0 else Color(242.0 / 255.0,
			251.0 / 255.0, 1.0)
		if i == 0:
			# accent cell: the web's gold value carries a gold glow
			PSTheme.glow_tc(self, r.get_center().x, r.position.y + 96.0, txt, vsz, col,
				PSTheme.TV_GOLD, 1.0, 18, 0.22, 6, 0.30)
		else:
			PSTheme.text_tc(self, r.get_center().x, r.position.y + 96.0, txt, vsz, col,
				1.0, false, true)
	draw_multiline(_score_edges, PSTheme.CYAN, 3.0)


## Minimap — bottom-left, over the arena, below the band (owner request).
##
## Geometry and dot metrics are the web's `render.js:drawMinimap`: 208 x 117
## plate for a 4800x2700 world, cyan `.13` 3x3 splits, 3.4 px player dot with a
## lime ring that breathes +-0.7, 2.4 px AI dots in snake colour, and the current
## camera rect in white `.5`. The web's 26 per-pellet food blits are dropped: they
## are 26 draw calls for confetti at this size, and the owner's spec for the
## restored map is world outline + snake dots + viewport.
##
## Cost: 1 style box + 1 world rect + 1 batched grid (all four 3x3 lines) + 1
## batched dot pass (hexagons, one triangle array) + 2 player glyphs + 1 viewport
## rect + 1 label = 8 draw calls, no per-frame allocation.
func _draw_minimap() -> void:
	if game == null:
		return
	draw_style_box(_mm_plate, MM_PLATE)
	draw_rect(MM_MAP, Color(8.0 / 255.0, 22.0 / 255.0, 40.0 / 255.0, 0.86), true)
	var ww: float = maxf(1.0, game.world_w)
	var wh: float = maxf(1.0, game.world_h)
	var kx: float = MM_MAP.size.x / ww
	var ky: float = MM_MAP.size.y / wh
	var mx := MM_MAP.position.x
	var my := MM_MAP.position.y
	# ---- 3x3 world outline (the two internal seams, batched into one call) ----
	if _mm_grid.size() != 8:
		_mm_grid.resize(8)
	for i in 2:
		var gx: float = mx + ww * (float(i + 1) / 3.0) * kx
		_mm_grid[i * 4] = Vector2(gx, my)
		_mm_grid[i * 4 + 1] = Vector2(gx, my + MM_MAP.size.y)
		var gy: float = my + wh * (float(i + 1) / 3.0) * ky
		_mm_grid[i * 4 + 2] = Vector2(mx, gy)
		_mm_grid[i * 4 + 3] = Vector2(mx + MM_MAP.size.x, gy)
	draw_multiline(_mm_grid, Color(0.337, 0.910, 1.0, 0.13), 1.0)
	# ---- snake dots, one triangle array for the whole field ----
	_mm_v.resize(0)
	_mm_c.resize(0)
	_mm_i.resize(0)
	var me := Vector2.ZERO
	var me_r := MM_DOT_ME
	var has_me := false
	var beat: float = sin(time / 0.26) * 0.7
	for s in game.snakes:
		if not s.alive or s.body.size() == 0:
			continue
		var b: Vector2 = s.body[0]
		var sp := Vector2(mx + b.x * kx, my + b.y * ky)
		# A character skin overrides the dot colour with its own palette, so the
		# minimap reads as "the red one is 辣到喷火", the same colour the arena's
		# rim and halo use.
		var sk: int = PSSkins.of(s)
		var skin_dot: Color = PSSkins.get_skin(sk)["dot"] if PSSkins.usable(sk) \
			else Color(0, 0, 0, 0)
		if s.is_player:
			# white-green dot, batched with the rest; the lime ring is one arc on top
			me = sp
			me_r = MM_DOT_ME + beat
			has_me = true
			if PSSkins.usable(sk):
				_mm_dot(sp, me_r, PSTheme.lighten(skin_dot, 0.45))
			else:
				_mm_dot(sp, me_r, Color(234.0 / 255.0, 1.0, 201.0 / 255.0))
			continue
		_mm_dot(sp, MM_DOT_AI, skin_dot if PSSkins.usable(sk) else s.color)
	PSTheme.band_flush(self, _mm_v, _mm_c, _mm_i)
	if has_me:
		draw_arc(me, me_r + 3.0, 0.0, TAU, 16, Color(182.0 / 255.0, 1.0, 87.0 / 255.0, 0.85),
			1.4, true)
	# ---- current camera rect (web: white .5, 1 px) ----
	if world_span.x > 1.0 and world_span.y > 1.0:
		_mm_view_rect.position = Vector2(
			clampf((cam_center.x - world_span.x * 0.5) * kx, 0.0, MM_MAP.size.x),
			clampf((cam_center.y - world_span.y * 0.5) * ky, 0.0, MM_MAP.size.y))
		_mm_view_rect.size = Vector2(minf(world_span.x * kx, MM_MAP.size.x),
			minf(world_span.y * ky, MM_MAP.size.y))
		draw_rect(Rect2(mx + _mm_view_rect.position.x, my + _mm_view_rect.position.y,
			_mm_view_rect.size.x, _mm_view_rect.size.y), Color(1, 1, 1, 0.5), false, 1.0)
	# ---- caption (web: `3x3 地图`, 10 px, rgba(150,210,235,.65), above the plate) ----
	PSTheme.text_t(self, Vector2(MM_PLATE.position.x + 2.0, MM_PLATE.position.y - 11.0),
		_cn("3×3 地图", "3×3 MAP"), 24,
		Color(150.0 / 255.0, 210.0 / 255.0, 235.0 / 255.0, 0.75), 1.2)


## One minimap dot as a 6-gon fan appended to the batched buffers.
func _mm_dot(p: Vector2, rr: float, col: Color) -> void:
	var base := _mm_v.size()
	_mm_v.resize(base + 7)
	_mm_c.resize(base + 7)
	_mm_v[base] = p
	_mm_c[base] = col
	for k in 6:
		var a := TAU * float(k) / 6.0
		_mm_v[base + 1 + k] = p + Vector2(cos(a), sin(a)) * rr
		_mm_c[base + 1 + k] = col
	var ib := _mm_i.size()
	_mm_i.resize(ib + 18)
	for k in 6:
		_mm_i[ib + k * 3] = base
		_mm_i[ib + k * 3 + 1] = base + 1 + k
		_mm_i[ib + k * 3 + 2] = base + 1 + (k + 1) % 6


## Panel height of the leaderboard for the current row count (0 rows -> 0).
func _lb_height() -> float:
	var n: int = mini(rows.size(), 8)
	if n == 0:
		return 0.0
	return LB_HEAD_H + LB_ROW_H * float(n)


func _buff_chip(x: float, y: float, label: String, left: float, total: float,
		col: Color) -> float:
	var r := Rect2(x, y, 210.0, 54.0)
	draw_style_box(_chip_style, r)
	draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), col, true)
	PSTheme.text_vc(self, r.position.x + 18.0, r.position.y + 20.0, label, 22, PSTheme.TEXT)
	PSTheme.text_r(self, r.end.x - 16.0, r.position.y + 28.0, "%.1fs" % left, 22, PSTheme.TEXT_SOFT)
	var frac := clampf(left / maxf(0.01, total), 0.0, 1.0)
	draw_rect(Rect2(r.position.x + 16.0, r.end.y - 14.0, r.size.x - 32.0, 4.0),
		Color(1, 1, 1, 0.12), true)
	draw_rect(Rect2(r.position.x + 16.0, r.end.y - 14.0, (r.size.x - 32.0) * frac, 4.0), col, true)
	return y + 62.0


## `#leaderboard` — the web's is `opacity: 0` outside `body.pause-open`, so the
## only shipped reference is the pause one (340 x 213, r3, 3 px cyan top edge).
## The owner asked for it back **in play** too: same width/chrome, anchored under
## the band at the arena's right edge (`LB_PLAY_Y`); the pause layer passes its
## own `y` so both screens can show one board each.
##
## Per-row `draw_string`s stay: measured at 6 draw calls for the whole board
## (`--capture-flow` HUD probe), i.e. Godot already batches these glyph runs — a
## `draw_multiline_string` rewrite was measured at exactly the same frame cost.
func _draw_leaderboard(y: float = -1.0) -> void:
	var n: int = mini(rows.size(), 8)
	if n == 0:
		return
	var top: float = LB.position.y if y < 0.0 else y
	var r := Rect2(LB.position.x, top, LB.size.x, LB_HEAD_H + LB_ROW_H * float(n))
	draw_style_box(_lb_style, r)
	draw_rect(Rect2(r.position.x + 4.0, r.position.y, r.size.x - 8.0, 3.0), PSTheme.CYAN, true)
	PSTheme.text_t(self, Vector2(r.position.x + 12.0, r.position.y + 32.0),
		_cn("本局排名 · 按长度", "RANK · BY LENGTH"), 24, PSTheme.CYAN, 1.2)
	PSTheme.text_tr(self, r.end.x - 12.0, r.position.y + 32.0, "%d:%02d" % [
		int(game.round_left) / 60, int(game.round_left) % 60], 20, PSTheme.TV_GOLD, 0.32)
	for i in n:
		var row = rows[i]
		var ry := r.position.y + LB_HEAD_H + LB_ROW_H * float(i)
		if row.is_player:
			draw_rect(Rect2(r.position.x + 1.0, ry, r.size.x - 2.0, LB_ROW_H - 2.0),
				Color(0.714, 1.0, 0.341, 0.16), true)
			draw_rect(Rect2(r.position.x + 1.0, ry, 3.0, LB_ROW_H - 2.0), PSTheme.LIME, true)
		var col: Color = Color(234.0 / 255.0, 1.0, 210.0 / 255.0) if row.is_player \
			else Color(220.0 / 255.0, 234.0 / 255.0, 245.0 / 255.0)
		var base := ry + 25.0
		PSTheme.text_t(self, Vector2(r.position.x + 16.0, base), "%d" % row.rank, 24,
			PSTheme.TV_GOLD if row.rank == 1 else PSTheme.MUTED, 0.32)
		var nm: String = row.name
		if nm.length() > 8:
			nm = nm.substr(0, 8)
		PSTheme.text_t(self, Vector2(r.position.x + 48.0, base), nm, 24, col, 0.32)
		PSTheme.text_tr(self, r.end.x - 12.0, base, "%d" % row.length, 24, col, 0.32)


# ----------------------------------------------------------------- pause

## `#pauseScrim` + `#pauseStats`: kicker 24/800/.28em, headline **60**/900 (the
## reference's `PauseForm.txtTitle` size; the 1148x556 frame and the full-screen
## scrim are owner-pending and deliberately NOT taken), the 561.28x193.39 stats
## strip (radius 4, 4 px cyan left edge) whose cells are 120x110.39 (radius 3,
## 1 px cyan divider, label 28, value 48).
##
## The strip carries 长度 / 吞并 / 最长 — this is where the legacy stat cards
## went. The remote actions are the reference's three 247x196 icon keys (gap 100,
## 48 px label UNDER each key, order 继续 / 重开 / 返回) because the port's pause
## is a real menu; the web's is an info panel dismissed with O.
func _draw_pause() -> void:
	_btns.clear()
	var w := size.x
	# arena scrim only (the band stays live behind the pause layer)
	draw_rect(Rect2(0, ARENA_TOP, w, size.y - ARENA_TOP), Color(0.012, 0.03, 0.055, 0.82), true)
	# ---- 分数 row: re-drawn ON TOP of the scrim ----
	# `_draw_play` skips all three in-play panels while paused (`in_play`), and the
	# stats strip below this layer only carries 长度 / 吞并 / 最长 — so the player's
	# SCORE used to disappear the moment he opened the pause menu. The row keeps its
	# normal place (84..646 x, 208..326 y), which the pause chrome never uses: the
	# kicker/title are centred and the strip starts at x 679.
	_draw_score_row()
	var cx := w * 0.5
	PSTheme.text_tc(self, cx, PAUSE_KICKER_BASE, _cn("OPTIONS / 局内信息", "OPTIONS / ROUND"),
		24, PSTheme.KICKER, 6.72)
	PSTheme.text_tc(self, cx, PAUSE_HEAD_BASE, _cn("设置与本局数据", "ROUND DATA"),
		PAUSE_HEAD_SZ, PSTheme.BODY_TEXT, 3.52)
	# ---- stats strip ----
	draw_style_box(_pause_strip, PAUSE_STATS)
	draw_rect(Rect2(PAUSE_STATS.position.x, PAUSE_STATS.position.y + 4.0, 4.0,
		PAUSE_STATS.size.y - 8.0), PSTheme.CYAN, true)
	var p = game.player
	var plen: int = p.body.size() if p != null and p.alive else 0
	_pause_cell(0, str(plen), _cn("长度", "LENGTH"))
	_pause_cell(1, str(game.kills), _cn("吞并", "KILLS"))
	_pause_cell(2, str(game.best_length), _cn("最长", "PEAK"))
	var buff_txt := _cn("道具 · 无", "POWER-UP · NONE")
	var buff_col := PSTheme.KICKER
	if p != null and p.alive and p.has_buff(0):
		buff_txt = _cn("道具 · 加速 %.1fs", "BOOST · %.1fs") % p.buff_left(0)
		buff_col = PSTheme.TV_GOLD
	elif p != null and p.alive and p.has_buff(1):
		buff_txt = _cn("道具 · 磁铁 %.1fs", "MAGNET · %.1fs") % p.buff_left(1)
		buff_col = PSTheme.TV_GOLD
	PSTheme.text_tc(self, PAUSE_STATS.get_center().x, PAUSE_STATS.end.y - 22.0, buff_txt, 26,
		buff_col, 1.56)
	# ---- remote actions: the reference's `btnRoot` --------------------------
	# `PauseForm`: three 247 x 196 icon keys, 100 px apart, centred
	# (3*247 + 2*100 = 941 -> x 489.5..1430.5) at top 467 in the reference's
	# 1148x556 frame. We keep the port's own y (below `#pauseStats`, top 537.39)
	# and the port's own 3 actions, but the key size, gap, ordering (继续 / 重开 /
	# 返回) and the 48 px label under each key are the reference's.
	# Nothing here touches `#pauseStats` (679.36,318 561.28x193.39) — that strip is
	# the web-parity element and stays pixel-identical.
	var bw := 247.0
	var bh := 196.0
	var gap := 100.0
	var row_w := bw * 3.0 + gap * 2.0
	var bx := cx - row_w * 0.5
	var by := PAUSE_STATS.end.y + 26.0
	for k in 3:
		var br := Rect2(bx + float(k) * (bw + gap), by, bw, bh)
		var hot: bool = pause_focus == k
		draw_style_box(_pause_key_hi if hot else _pause_key, br)
		# the reference's selected ring is 359x306, i.e. ~56 px wider than the key
		draw_rect(Rect2(br.position.x, br.end.y - 3.0, br.size.x, 3.0),
			PSTheme.with_a(PSTheme.CYAN if k > 0 else PSTheme.LIME, 0.85), true)
		_draw_pause_icon(k, br, hot)
		if hot:
			_draw_focus_ring(br)
		_btns.append([BTN_RESUME if k == 0 else (BTN_RESTART if k == 1 else BTN_MENU), br])
		var lcol: Color = PSTheme.LIME if hot else PSTheme.TEXT
		PSTheme.text_tc(self, br.get_center().x, br.end.y + 96.0,
			_pause_label(k), 48, lcol, 1.92)
	PSTheme.text_tc_fit(self, cx, by + bh + 156.0,
		_cn("← → 选择 · OK 确认 · 按返回键继续", "LEFT/RIGHT select · OK confirm · BACK resumes"),
		32, Color(1, 1, 1, 0.52), 0.32, 1400.0)
	# ---- leaderboard (pause-only in the shipped skin) ----
	_draw_leaderboard()


## The three pause actions, in the reference's order (`PauseForm.cs:70-91`:
## 继续游戏 / … / 返回主页). Our single-scene port keeps 继续 / 重开 / 返回
## left-to-right and a 4-character label rhythm (a 6-character "返回模式选择" would
## be 288 px at 48 px and break the row's symmetry).
func _pause_label(k: int) -> String:
	match k:
		0:
			return _cn("继续游戏", "RESUME")
		1:
			return _cn("重新开局", "RESTART")
		_:
			return _cn("返回模式", "MODE SELECT")


## A 247x196 "icon key": the glyph is the port's own vector art (no new texture),
## 56 px tall, in the key's upper half — the 48 px label sits UNDER the key, so the
## interior is free for it, exactly like the reference's 248x70 text box at
## top 715..785 below the 467..663 key.
func _draw_pause_icon(kind: int, r: Rect2, hot: bool) -> void:
	var c := Vector2(r.get_center().x, r.position.y + 76.0)
	var col: Color = PSTheme.LIME if (kind == 0 and not hot) else (
		PSTheme.LIME if hot else PSTheme.TEXT_SOFT)
	if kind == 0:
		# 继续: play triangle
		draw_colored_polygon(PackedVector2Array([c + Vector2(-20.0, -32.0),
			c + Vector2(-20.0, 32.0), c + Vector2(32.0, 0.0)]), col)
	elif kind == 1:
		# 重开: open circular arrow with an arrowhead
		draw_arc(c, 30.0, -PI * 0.42, PI * 1.22, 28, col, 7.0, true)
		var tip := c + Vector2(cos(-PI * 0.42), sin(-PI * 0.42)) * 30.0
		draw_colored_polygon(PackedVector2Array([tip + Vector2(16.0, -2.0),
			tip + Vector2(-4.0, -18.0), tip + Vector2(-4.0, 12.0)]), col)
	else:
		# 返回: left arrow
		draw_line(c + Vector2(28.0, 0.0), c + Vector2(-18.0, 0.0), col, 8.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-32.0, 0.0),
			c + Vector2(-14.0, -17.0), c + Vector2(-14.0, 17.0)]), col)


## One `#pauseStats .stat` cell: 120x110.39, radius 3, 1 px cyan left divider,
## label 28/600/.14em above the 48/900 value.
func _pause_cell(i: int, value: String, label: String) -> void:
	var cr := Rect2(PAUSE_CELL_X0 + float(i) * PAUSE_CELL_STEP, PAUSE_CELL_Y,
		PAUSE_CELL_W, PAUSE_CELL_H)
	draw_style_box(_pause_cell_style, cr)
	draw_rect(Rect2(cr.position.x, cr.position.y + 1.0, 1.0, cr.size.y - 2.0),
		PSTheme.CYAN, true)
	PSTheme.text_tc(self, cr.get_center().x, cr.position.y + 40.0, label, 28,
		PSTheme.TOTAL_DIM, 3.92)
	PSTheme.text_tc(self, cr.get_center().x, cr.position.y + 88.0, value, 48,
		Color(242.0 / 255.0, 251.0 / 255.0, 1.0), 0.32, false, true)


## DPAD focus ring: drawn around the selected row, same accent as the band.
func _draw_focus_ring(r: Rect2) -> void:
	draw_rect(r.grow(4.0), PSTheme.with_a(PSTheme.CYAN, 0.92), false, 3.0)


func _draw_settle_hud() -> void:
	# The stage owns the screen; keep only the debug overlay + a small hint.
	_btns.clear()


# ------------------------------------------------------------------ debug

func _draw_debug() -> void:
	var lines := PackedStringArray()
	lines.append("fps %.0f  draw %d  prim %d" % [perf.get("fps", 0.0), perf.get("draw", 0),
		perf.get("prim", 0)])
	lines.append("snakes %d  food %d  pwr %d  fx %d/%d/%d" % [
		game.snakes.size(), game.foods.size(), game.powerups.size(),
		perf.get("p", 0), perf.get("t", 0), perf.get("w", 0)])
	lines.append("input %s  tracking %s  persons %d  slots %d  hint %s" % [
		["pose", "debug", "demo"][input_source], "YES" if tracking else "no", persons,
		tracked_slots, pose_hint])
	lines.append("binder %s  bound %s  frames %d  age %s" % [
		bridge_binder, "yes" if bridge_bound else "no", bridge_frames,
		"-" if bridge_age_ms < 0 else "%dms" % bridge_age_ms])
	lines.append("state %d  mode %d  round %.1f  players %d  ai %.2f" % [
		game.state, mode, game.round_left, player_count, ai_level])
	lines.append("camera supported %s  on %s  armed %s  variant %s  pose_mirror %s" % [
		"yes" if cam_supported else "no", "yes" if cam_on else "no",
		"yes" if cam_armed else "no", cam_mode_label, "yes" if cam_pose_mirror else "no"])
	lines.append("camera aidl mode %d  views %d  pip %.2f,%.2f,%.2f,%.2f" % [
		cam_mode, cam_views.size(), cam_rect.position.x, cam_rect.position.y,
		cam_rect.size.x, cam_rect.size.y])
	for view in cam_views:
		var src: Array = view.get("src", [0.0, 0.0, 1.0, 1.0])
		var dst: Array = view.get("dst", [0.0, 0.0, 1.0, 1.0])
		lines.append("camera id %d  A %.3f,%.3f,%.3f,%.3f  B %.3f,%.3f,%.3f,%.3f  mode %d" % [
			int(view.get("id", 0)), float(src[0]), float(src[1]), float(src[2]),
			float(src[3]), float(dst[0]), float(dst[1]), float(dst[2]), float(dst[3]),
			int(view.get("mode", 0))])
	lines.append("camera rgba %s  flip_x %s  frames %d" % [
		cam_rgba_state, "yes" if cam_rgba_flip else "no", cam_rgba_frames])
	if cam_on:
		lines.append("camera: SYSTEM OVERLAY (service draws it ABOVE this app)")
	if bridge_error != "":
		lines.append("bridge: " + bridge_error)
	var r := Rect2(292.0, size.y - 320.0, 660.0, 26.0 + 22.0 * float(lines.size()))
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.62), true)
	draw_rect(r, Color(0.337, 0.910, 1.0, 0.35), false, 1.0)
	var f := ThemeDB.fallback_font
	for i in lines.size():
		draw_string(f, Vector2(r.position.x + 12.0, r.position.y + 24.0 + 22.0 * float(i)),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.72, 0.92, 1.0))


# ------------------------------------------------------- always-on perf panel

## The compact always-on read-out (F10 / double-tap INFO). main.gd fills
## `perf_labels` / `perf_vals` at 4 Hz; this function only draws them.
##
## Cost: 1 dark plate + 1 cyan hairline + ONE text batch (every row is the same
## font atlas and the same material, so the 16 string commands collapse into a
## single draw call). Measured with `--capture-perf`: +3 draw calls, 0 alloc in
## the per-frame path, no node and no CanvasItem of its own.
func _draw_perf() -> void:
	if perf_vals.is_empty():
		return
	var r := PERF_PANEL
	draw_rect(r, Color(0.012, 0.026, 0.047, 0.80), true)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1.0),
		Color(0.337, 0.910, 1.0, 0.42), true)
	var f := _perf_mono_font()
	var x0 := r.position.x + PERF_PAD_X
	var xv := x0 + PERF_VAL_DX
	var y := r.position.y + PERF_PAD_TOP
	var n: int = mini(perf_labels.size(), perf_vals.size())
	for i in n:
		var head: bool = i == 0
		draw_string(f, Vector2(x0, y), String(perf_labels[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERF_FONT_SZ,
			PSTheme.CYAN if head else PERF_LABEL_COL)
		draw_string(f, Vector2(xv, y), String(perf_vals[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, PERF_FONT_SZ,
			PSTheme.CYAN if head else PERF_VALUE_COL)
		y += PERF_ROW_H


## Monospace-ish: a real mono face when the host has one (Consolas on the dev
## PC, Droid Sans Mono / monospace on the box), else the engine font — the value
## column is a fixed x offset either way, so the rows stay aligned. Resolved
## once, never per frame.
func _perf_mono_font() -> Font:
	if _perf_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Droid Sans Mono",
			"monospace"])
		sf.font_weight = 400
		_perf_font = sf if sf.has_char(0x30) else ThemeDB.fallback_font
	return _perf_font
