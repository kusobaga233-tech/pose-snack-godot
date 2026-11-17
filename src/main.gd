extends Node2D
## Workstream C — Pose Snake presentation shell.
##
## Input contract for the shipped Android build:
##   * MENUS  = the remote control only (DPAD / OK / BACK), handled in exactly one
##              place: `_input()` -> `_dispatch_action()`. There is no mouse click
##              path and no keyboard menu shortcut on Android.
##   * PLAY   = body tracking only. The keyboard steering path is compiled in for
##              desktop testing but `_allow_keyboard_steer` is false on Android,
##              so no UI can select it there.
##
## Owns the round flow, the pose input layer, the camera and the three
## CanvasItems that draw the game:
##
##   * one `PSWorldView` per human  (1 in single player, 2 SubViewports in split)
##   * one `PSHud`      (mode select, ready cards, GO! beat, cards/clock/buffs,
##                      leaderboard, mini map, pause, debug)
##   * one `PSStage`    (settlement "grow-up comparison")
##
## Flow (product decision, mirrors `Docs/FLOW-REFERENCE-1024.md`):
##
##     MODE_SELECT  (单人模式 / 双人模式, no default, waits forever)
##        -> MODE_READY     (per-player slot cards: 等待玩家进入屏幕 / 请举手确认准备 / 已准备)
##        -> MODE_COUNTDOWN (1.5 s "GO!" beat)
##        -> MODE_PLAY      (rules core runs here and only here)
##        -> MODE_PAUSE / MODE_SETTLE
##
## BACK semantics (reference `ButtonMgr` / `ModelForm`, see
## `Docs/UI-REFERENCE-1024.md` §3): mode select = background-or-quit, READY =
## mode select, play = pause, pause = resume. A human slot lost in play for
## `PLAY_SLOT_LOST_SEC` re-opens READY (the reference slides its ready panel back
## in) instead of coasting with nobody steering.
##
## The simulation is frozen in every state before MODE_PLAY: `PSGame.update()` is
## only called from the MODE_PLAY branch of `_process()`.
##
## The rules live in `src/core/**` and are only stepped here; this file never
## mutates game state except through PSGame's public API.
##
## Command line (user args after `--`):
##   --capture        old scripted 1P round: saves evidence/render-preview*.png,
##                    prints fps min/avg + draw calls, quits (goes straight to play)
##   --capture2p      same, split screen (saves render-preview-split.png)
##   --capture-flow   walks MODE_SELECT -> READY -> COUNTDOWN -> PLAY and saves
##                    evidence/flow-01..04 PNGs + the play-state fps/draw readout.
##                    Add --capture2p to walk the 2-player branch (2P ready cards).
##   --capture-escape verification only: enters 1P READY with no pose, time-scales
##                    the 30 s no-person timer, saves flow-05-ready-escape.png
##   --capture-remote verification only: drives MODE_SELECT -> READY -> PLAY ->
##                    PAUSE -> SETTLE through real `InputEventKey` events
##                    (Input.parse_input_event) and saves evidence/remote-0*.png
##   --capture-overlap verification only: stages a self-crossing body and saves
##                    evidence/overlap-<tag>.png + a 3x crop of the crossing
##                    (`--overlap-tag=NAME`, default `shot`)
##   --capture-tuning verification only: opens the internal tuning panel and
##                    drives it with real key events (only a PSBuild.TUNING_ENABLED build
##                    has the panel; with the flag off it just proves that)
##   --capture-cam    camera-turn stability evidence: a scripted straight run then
##                    90/180/90 deg turns, one line per frame with the follow
##                    centre, per-frame step, speed and head screen offset
##   --capture-cam-boost  acceleration evidence: a straight run, then the REAL
##                    boost powerup plus the pose wrist-speed ceiling are held for
##                    4.5 s while the script drives 90/180/90 deg turns at that
##                    speed. One line per frame with the measured snake speed, the
##                    camera speed/step, the head offset from the camera centre
##                    (px and % of the safe box), inside/outside the drawn arena
##                    rect and the adaptive caps. `--cam-boost-tag=NAME` names the
##                    two saved frames (default `run`).
##   --capture-shake  screen-shake evidence: scripted eat / kill / death / stack
##                    impulses through the real event router, one line per frame
##   --capture-perf   perf-panel evidence: measures draw calls with the panel on
##                    vs off and saves evidence/perf-overlay-1920.png
##   --capture-pose-trace  STEERING evidence: scripts the owner's gestures (hand
##                    on the chest, arm forward, arm sideways, arm raised, slow
##                    sweep, plus step/circle/stress legs) relative to the RIGHT
##                    SHOULDER through the REAL mapper
##                    (`PSPoseInput.ingest_test_skeleton` -> `_process_slot` ->
##                    `PSPoseSteer`) and the REAL turn law (`PSSnake.update`), one
##                    line per simulated frame into
##                    evidence/pose-trace-<ref>.txt. `--pose-ref=chest` replays
##                    the previous pass (chest origin, old dead zone/speed) on the
##                    same gestures; `--pose-dz=DZ,EXIT` and `--pose-tau=W,A`
##                    override numbers for a sweep; `--pose-tag=NAME` renames the
##                    output. `--pose-law=before` still replays the pre-fix law
##                    (no filters, deadzone 0.05, arm hysteresis 1.15, no dwell);
##                    `--pose-motion=off` replays the PRE-fast-sweep-fix law on the
##                    same gestures (both holds latch on position only), which is
##                    the before/after pair evidence/pose-trace-fast-{before,after}.txt.
##   --capture-skeleton  OVERLAY evidence: paints a 576x324 camera frame with a
##                    32 px reference grid, mirror markers and the 18 joints of a
##                    staged person, pushes the matching skeleton through the real
##                    pipeline and saves
##                    evidence/skeleton-shoulder-ref{,-ready,-off}.png.
##                    Also measures the overlay's draw-call cost (ON vs OFF).
##   --remote-probe   headless key journey (no screenshots): exercises every
##                    remote action and prints only `[key]` / `[flow]` lines
##   --remote-nav     headless BACK/OK journey (verification only): drives BACK on
##                    mode select / READY / play / pause, injects one mid-play
##                    slot loss and asserts each outcome (`[nav]` lines). The last
##                    step presses BACK on mode select, which backgrounds the app
##                    (or quits, see `_background_or_quit()`), so the probe ends
##                    with the `[ui] BACK on mode_select ->` line.
##   --keys           print every key event as
##                    `[key] event=<pressed|released> code=<c> physical=<p> unicode=<u>`
##                    (also auto-on for Android debug builds: press each RCU
##                    button once and read logcat)
##   --debug          start with the debug overlay (F3 toggles it at runtime)
##   Camera live is ON by default, driving the HUD band's **mirror box** (the
##   web's 320x180 `#cam` pane in the band's left cell); no flag and no key press
##   is needed (READY/COUNTDOWN/PLAY/PAUSE on, SELECT/SETTLE off). The SDK service
##   composites the preview in its own overlay window ABOVE this app, so the
##   destination rect is inset 2 px to leave the cyan frame visible.
##   The **RGBA-frame path** (the shipped pixel source) draws the same mirror box
##   from `camera_frame_poll()`, and the READY slot cards now show it too: one
##   shared texture, one poll per frame, per-player half in 2P. Its pump runs ONLY
##   while a camera box is on screen (READY/COUNTDOWN/PLAY/PAUSE) and is stopped on
##   MODE_SELECT/SETTLE by `_camera_pump_sync`, so it never decodes unseen (the
##   plugin's `drops` counter used to climb on the menu).
##   The SDK's camera video is a MIRRORED image: MatchSessionConfig
##   .mirrorPlayerTrackingHorizontally exists "to adapt to mirrored video"
##   (Documentation~/Configuration/catalog.json:6258-6269) and the built-in
##   provider's tracking coordinates are documented as mirrored
##   (Documentation~/sdk-framework-integration.zh-CN.md:497). The SDK's display
##   flip is a NEGATIVE UV width (CameraImageUvRegionUtility.CalculateUvRect),
##   i.e. an inverted source rect. Our native overlay shows the unmirrored
##   sensor frame, so the shipped default inverts A.x and keeps mode 0 — the
##   only mode the SDK ever sends. The A/B order is proven on device:
##   A = source crop, B = on-screen destination.
##   --camera-live    debug override: full-screen preview (covers the HUD)
##   --camera-live-pip          explicit PiP rect (the default)
##   --camera-live-rect=x,y,w,h override the 1P PiP rect (normalized, x/y/w/h)
##   --camera-live-mode=N       opaque AIDL mode int (default 0; the SDK only
##                    uses 0 — this is an emergency override, not a variant)
##   --camera-variant=N         DEBUG: 0 mirror H (shipped, device-confirmed) /
##                    1 mirror H+V / 2 raw. The F6 cycle is a debug key only.
##   --no-pose-mirror           boot with the raw pose convention (Ctrl+F7 toggles)
##                    Debug keys (desktop keyboard, or `adb shell input keyevent`):
##                    F3 = the detailed developer overlay (bottom-left),
##                    F4 = camera on/off, F5 = 1P PiP placement,
##                    F6 = cycle the 3 camera variants (remote MENU),
##                    F7 = flip the mirror box (remote INFO), Ctrl+F7 = pose `1-x`,
##                    F8 = tuning panel (PSBuild.TUNING_ENABLED build only),
##                    F9 = the live skeleton overlay over the camera pixels
##                    (`adb shell input keyevent 139`; F1 = 131, so F9 = 139 and
##                    F10 = 140, which the perf panel already uses. KEY_HELP /
##                    KEY_SEARCH are the only remote-ish keys the native hook
##                    leaves untouched, so they are accepted as an alias in a
##                    build WITHOUT the tuning panel - no physical button on this
##                    box is known to send them, so F9 is the guaranteed path),
##                    F10 = the always-on perf panel (F10 = adb keyevent 140;
##                    the remote has no F10, so a **double tap on INFO** does the
##                    same (the second tap also undoes its camera flip).
##   --no-perf        hide the always-on perf panel (it is ON by default)
##   --perf-overlay   force the perf panel ON in a capture/verification run
##   --no-skeleton    hide the live skeleton overlay (it is ON by default)
##   --no-auto-ready  desktop only: keep the real READY gate (no dev pose)
##   --auto-ok        verification only: inject LEFT + OK at boot through the real
##                    input queue, so the desktop auto-ready path can be proven
##   --lowend         force the config.gd low_end device profile
##   --fullend        force the desktop device profile on Android
##   --menu           accepted for old scripts; mode select is the normal entry now
##   --capture-stress  WORST-CASE perf run (Docs/WRAPUP-AUDIT.md, Phase B): 8 snakes
##                    x 240 segments, 265 pellets, 7 powerups, FX pools at cap,
##                    boost on every snake, perf panel ON, the staged camera.
##                    Real time (add NO `--fixed-fps`); add `--capture2p` for split
##                    screen. Prints one `[stress] leg=...` line per length leg
##                    (240 / 120) plus a `[stress] prof` per-pass CPU break-down,
##                    and a `[stress] nofxpanel` window with the panel OFF.
##                    Measurement-only switches: `--stress-uncapped` (vsync off,
##                    max_fps 0: the real frame cost), `--stress-no-cam`,
##                    `--stress-no-hud`, `--stress-no-world` (layer attribution).
##   --capture-cam2p  evidence for the split-screen band mirror boxes: stages a
##                    576x324 frame with two people + one skeleton per human slot
##                    and saves evidence/cam-2p-band-1920.png
##   --mute           boot with SFX muted (the saved `[audio] muted` wins otherwise)
##   --endless        boot in 无尽练习 / endless practice (`[round] mode`)
##
## Persisted player settings live in `user://pose_snake.cfg` (`ps_settings.gd`):
## `[audio] muted`, `[round] best_length`, `[round] mode` (the character pick is
## `[skin] player`, owned by `ps_skins.gd`). Verification harnesses are read-only.
## Mode-select options bar (focus slots 3/4/5, `ps_hud.gd`): 玩法说明 / 音效 / 赛制.

const PSConfig = preload("res://src/core/config.gd")
const PSTuning = preload("res://src/core/tuning.gd")
const PSGame = preload("res://src/core/game.gd")
const PSSteerInput = preload("res://src/core/steer_input.gd")
const PSSnake = preload("res://src/core/snake.gd")
const PSSnakeControl = preload("res://src/core/snake_control.gd")
const PSPoseSteer = preload("res://src/core/pose_steer.gd")
const PSRng = preload("res://src/core/rng.gd")
const PSKeyboardSteer = preload("res://src/core/keyboard_steer.gd")
const PSTheme = preload("res://src/present/ps_theme.gd")
const PSAssets = preload("res://src/present/ps_assets.gd")
const PSFx = preload("res://src/present/ps_fx.gd")
const PSWorldView = preload("res://src/present/ps_world_view.gd")
const PSHud = preload("res://src/present/ps_hud.gd")
const PSStage = preload("res://src/present/ps_stage.gd")
const PSAudio = preload("res://src/present/ps_audio.gd")
const PSPoseInput = preload("res://src/present/ps_pose_input.gd")
## Grace-tolerant raise accumulator, shared with ps_pose_input.gd (menu shortcut)
## so the two raises cannot disagree about what "held" means.
const PSRaiseHold = preload("res://src/present/ps_raise_hold.gd")
const PSSkins = preload("res://src/present/ps_skins.gd")
const PSRemote = preload("res://src/present/ps_remote.gd")
const PSBuild = preload("res://src/present/ps_build.gd")
const PSSettings = preload("res://src/present/ps_settings.gd")
const PSEvents = preload("res://src/core/events.gd")

## Mirrors ps_hud.gd — keep the numbers in sync.
const MODE_SELECT := 0
const MODE_PLAY := 1
const MODE_PAUSE := 2
const MODE_SETTLE := 3
const MODE_READY := 4
const MODE_COUNTDOWN := 5

# --- READY thresholds: seconds, never frame counts (product decision B) ---
## 1. A person must be held in this slot's zone this long before the hand counts.
const READY_ZONE_SEC := 1.0
## 2. Then a hand (either one) must stay up this long to confirm the slot.
##    NOTE: unchanged on purpose. The pose stream is 15-30 Hz with keypoint noise,
##    so a single frame with the wrist just under the threshold used to reset the
##    counter and wipe ~1.4 s of a genuinely held raise (owner: 30 s with the arm
##    up, `slot=0 -> raise`, never `-> ready`). The fix is the grace window in
##    `PSRaiseHold` (0.30 s), not a shorter threshold — this value stays 1.5 s
##    until device evidence says otherwise.
const READY_RAISE_SEC := 1.5
## `[ready] fill=` progress line throttle: max 4 lines/s per slot, and only when
## the fill moved >= 0.05 or the raise flag flipped (see `_ready_fill_log`).
const READY_FILL_LOG_SEC := 0.25
## A slot missing for longer than this falls back to 等待玩家进入屏幕 and loses
## its progress (a dropped frame must not reset the card).
const READY_LOST_GRACE_SEC := 0.25
## Hold the green checks this long after the last slot confirms.
const READY_DONE_HOLD_SEC := 0.35
## No person at all for this long in READY -> advisory 请站到镜头前 panel.
## The panel is advisory only: nothing starts, READY keeps waiting, BACK returns
## to MODE_SELECT (the same BACK hint is on screen before the 30 s mark too).
const READY_NO_PERSON_HINT_SEC := 30.0
## Opening beat after ready completes (product decision A: 1.5 s, not the old 3 s).
const READY_COUNTDOWN_SEC := 1.5

## Desktop-only dev pose: on the PC there is no SDK camera, so `pose.tracking` is
## never true and the READY gate could never open (the editor sat on 准备开始
## forever). When this is on, a NON-ANDROID build reports each slot as present
## with the hand raised, so the SHIPPED ready timers (READY_ZONE_SEC +
## READY_RAISE_SEC, ~2.5 s) run normally into countdown -> play and the arrow keys
## can steer. It is hard-gated by `OS.has_feature("android")` (a box with no
## person must keep waiting), ignored by every capture harness, and can be turned
## off with `--no-auto-ready`.
const DESKTOP_AUTO_READY := true

const SRC_POSE := 0
const SRC_KEYBOARD := 1
const SRC_SYNTH := 2

# Button ids, mirrored from ps_hud.gd / ps_stage.gd.
const BTN_RESUME := 5
const BTN_RESTART := 6
const BTN_MENU := 7
const BTN_MODE_1P := 10
const BTN_MODE_2P := 11
## ps_stage.gd ids (its BTN_RETRY/BTN_MENU are a separate namespace).
const BTN_RETRY := 1
const BTN_STAGE_MENU := 2

## Cross-channel duplicate guard: the same action within this many ms is treated
## as one physical press. The native hook consumes the original event, so this
## only catches a broadcast and a key event racing each other (and is a final
## backstop if a future build adds another delivery path).
const DUP_ACTION_MS := 90

## Pause menu: 继续游戏 / 重新开局 / 返回模式选择.
const PAUSE_ACTION_COUNT := 3
## Settlement: 再来一局 / 返回模式选择.
const SETTLE_ACTION_COUNT := 2

## Normalized preview rects for F5 / --camera-live. Index 0 keeps the SDK
## reference behaviour (full screen). CAMERA_PIP_INDEX is the SHIPPED default.
##
## The preview is the web's **mirror box**: `#cam` is a 320x180 pane in the HUD
## band's left cell. Measured web rect: x=90, y=8.5, r=2, 2 px rgba(cyan,.55)
## frame. Owner-confirmed on device (2026-11-13): the system overlay renders real
## video into this rect with **A=[1,0,0,1]** (inverted source width = the SDK
## mirror) and that orientation is correct — lock it as the shipped behaviour.
##
## Shipped 1P destination, in 1920x1080 design px: **B = (90,10)-(410,190)**,
## i.e. x1=0.046875, y1=0.009259, x2=0.213542, y2=0.175926.
##
## The SDK service composites the preview in its own overlay window ABOVE this
## app, so the whole destination is opaque video: ps_hud.gd draws the 2 px frame
## as a bezel *outside* this rect (everything inside it is covered on device).
const CAMERA_LIVE_RECTS := [
	Rect2(0.0, 0.0, 1.0, 1.0),
	Rect2(0.046875, 0.009259, 0.166667, 0.166667),
	Rect2(0.02, 0.02, 0.28, 0.32),
]
## Index of the shipped band mirror-box rect.
const CAMERA_PIP_INDEX := 1

## ---- camera live: SDK-derived geometry -------------------------------------
## The SDK's camera presentation is a MIRRORED video image. Evidence:
##   * MatchSessionConfig.mirrorPlayerTrackingHorizontally (default true; the
##     FULL and SPLIT template configs both store 1) = "horizontally mirror the
##     player x before the matching-area calculation, to adapt to a mirrored
##     video" (Documentation~/Configuration/catalog.json:6258-6269).
##   * CameraImageViewProfileAsset.trackingCoordinatesAreMirrored defaults true
##     because the built-in YouDoo provider reports mirrored coordinates
##     (Documentation~/sdk-framework-integration.zh-CN.md:497).
## The SDK applies that mirror with a NEGATIVE UV WIDTH, never with a mode int:
##   source.x += source.width; source.width = -source.width;
## (Modules/camera-match-flow/Runtime/CameraImage/CameraImageUvRegionUtility.cs:
##  192-196). The AIDL call carries the same signed floats and its `mode` is 0
## in every SDK call site, so SDK parity is: inverted source rect, mode 0.
##
## Our pose layer already lives in that mirrored space (`1.0 - x` in
## ps_pose_input.gd, the SDK's TransformTrackedPlayerPoint x' = 1 - x), so the
## native overlay — which shows the unmirrored sensor frame — must be flipped.
const CAMERA_VARIANT_DEFAULT := 0
const CAMERA_VARIANTS := [
	{"name": "SDK mirror H", "mirror_h": true, "mirror_v": false},
	{"name": "mirror H+V", "mirror_h": true, "mirror_v": true},
	{"name": "raw frame", "mirror_h": false, "mirror_v": false},
]

## 2P per-player previews. Slot 0 is the LEFT half of the mirrored frame: our
## pose layer maps provider x through 1-x and ps_pose_input assigns slot 0 when
## that is < 0.5 (SDK split slots are LeftToRight, slot 0 = left). The raw
## sensor half for slot 0 is therefore the RIGHT half (0.5..1) before the
## mirror flip. Destination follows the 2P band (WEB-COMPUTED-STYLES §6.4): the
## two mirror boxes are the band's outer cells — 268 x 150.75 at x=56 and
## x=1596, y=23.13. Same A convention as 1P (owner-confirmed on device).
const CAMERA_2P_SRC := [
	Rect2(0.5, 0.0, 0.5, 1.0),
	Rect2(0.0, 0.0, 0.5, 1.0),
]
## The two 2P mirror boxes (ps_hud.gd draws the frame as a bezel outside them).
const CAMERA_2P_DEST := [
	Rect2(56.0 / 1920.0, 23.13 / 1080.0, 268.0 / 1920.0, 150.75 / 1080.0),
	Rect2(1596.0 / 1920.0, 23.13 / 1080.0, 268.0 / 1920.0, 150.75 / 1080.0),
]

const DESIGN := Vector2(1920.0, 1080.0)
## The gameplay canvas: the web's `#uiBar` is a full-bleed 200 px band, so the
## arena (`#arena`) starts at y=200 and is 1920x880 — not 1920x1080.
const ARENA_TOP := 200.0
const ARENA_SIZE := Vector2(1920.0, 880.0)
const CAM_SPAN := 900.0

var cfg: PSConfig = null
var tuning: PSTuning = null
var game = null

var mode := MODE_SELECT
var input_source := SRC_POSE

var player_count := 1

## Mode-select focus: -1 means nothing is selected (no default, no auto-confirm).
## LEFT/UP focuses 单人模式, RIGHT/DOWN moves through the ladder
## 1人 -> 2人 -> 角色 -> 玩法说明 -> 音效 -> 赛制 -> back to 1人, OK confirms.
var select_focus := -1
## How-to-play overlay (mode select only). When true the router sends every action
## to it, and OK/BACK closes it (see `_act_select`).
var help_open := false
## SFX on/off: the player-facing control is the 音效 chip on the mode-select
## options bar; the state lives in `PSAudio.muted` and is persisted.
var _audio_on := true
## Pause focus: 0 = 继续游戏, 1 = 重新开局, 2 = 返回模式选择.
var pause_focus := 0
## Settlement focus: 0 = 再来一局, 1 = 返回模式选择.
var settle_focus := 0
## Last focus the settlement stage was redrawn for (see the `stage.is_animating`
## block in `_process`).
var _stage_focus_drawn := -1

## READY slot state, index 0/1. Parallel arrays so the per-frame path allocates
## nothing; ps_hud reads the same Array objects.
var ready_state: Array = [0, 0]
var ready_zone: Array = [0.0, 0.0]
## Per-slot raise accumulator (grace-tolerant, see ps_raise_hold.gd). The HUD
## only reads `ready_fill`, so the hold objects stay internal to main.gd.
var ready_hold: Array = [PSRaiseHold.new(), PSRaiseHold.new()]
## `[ready] fill=` log bookkeeping: last print clock / fill / previous raise flag
## / last raise-flip line clock.
var _ready_log_t: Array = [0.0, 0.0]
var _ready_log_fill: Array = [0.0, 0.0]
var _ready_prev_raised: Array = [false, false]
var _ready_log_flap_t: Array = [0.0, 0.0]
var ready_fill: Array = [0.0, 0.0]
var ready_pop: Array = [0.0, 0.0]
var ready_lost: Array = [0.0, 0.0]
var _ready_done_t := 0.0
var _ready_no_person_t := 0.0
## True once nobody at all has been seen for READY_NO_PERSON_HINT_SEC: draws the
## advisory 请站到镜头前 panel (never starts anything).
var _nobody_hint := false
var _ready_slide := 0.0
## READY panel entry motion (reference `KinestheticInfoForm.findPlayerRoot`:
## `ap.y = +1400 -> 0`, 0.3 s OutQuad). Only the card block slides, not the header.
var _ready_in_t := 0.0
var _countdown_t := 0.0

## Mid-play human-slot loss (reference `XXAndroidParseData.cs:615-630`: the ready
## panel slides back in when a player leaves the round). Counted in seconds; a
## single dropped pose frame must not yank a live round, so this is longer than
## READY's 0.25 s slot grace and shorter than the 30 s nobody-in-view advisory.
const PLAY_SLOT_LOST_SEC := 1.0
var _play_lost_t := 0.0

## `--remote-nav` verification probe (never ships): drives BACK on every screen and
## injects a slot loss, asserting what each one does.
var _probe_nav := false
var _probe_nav_step := 0
var _probe_nav_t := 0.0
var _probe_nav_done := false
var _probe_nav_fail := 0
var _probe_slot_lost := false

## The shipped Android plugin's Godot singleton. BACK on the player-count screen
## must background the app the way the reference's `MoveTaskToBack` does; that
## method has to be exposed by the plugin (`@UsedByGodot public void
## moveTaskToBack(boolean)`), and today it is not, so `_background_or_quit()`
## keeps the documented `quit()` fallback and logs which path ran.
const PLUGIN_SINGLETON := "YoudooSkeleton"

## Previous state name for `[flow]` logs.
var _flow_prev := "boot"

var fx: PSFx = null
var audio: PSAudio = null
var pose: PSPoseInput = null
var bridge: Node = null
var kb = PSKeyboardSteer.new()

var worlds: Array = []
var split_root: Control = null
## The 2P split SubViewports (empty in 1P): `_set_worlds_visible` also stops their
## render target from updating while the arena is covered by the menu backdrops.
var vps: Array = []
var hud: PSHud = null
var stage: PSStage = null
## Internal debug tuning panel. **Null in every shipped build**:
## `PSBuild.TUNING_ENABLED` is false, so the node below is never created and every
## `_tuning_panel != null` test in this file is a single constant-folded branch.
var _tuning_panel = null

var cams: Array = [Vector2.ZERO, Vector2.ZERO]
var zooms: Array = [1.2, 1.2]
var spans: Array = [Vector2(1600.0, 900.0), Vector2(1600.0, 900.0)]

var now := 0.0
var hud_accum := 0.0
var perf_accum := 0.0
var frame_count := 0
var go_flash := 0.0
var pose_lost_for := 0.0
var rows: Array = []
var rank_prev := 1
var _rank_arrow_t := 0.0

var _steers: Array = []
var _bridge_status: Dictionary = {}
var _bridge_frames := 0
var _status_accum := 0.0
var _show_debug := false
var _keys_held := false
## Camera live is the SDK's system-composited preview. It is OFF by default on
## purpose: the SDK service adds its SurfaceView with TYPE_APPLICATION_OVERLAY,
## i.e. it is drawn ABOVE this app (see Docs/CAMERA-LIVE-EVIDENCE.md). Opt in
## with `--camera-live`, or F4 / F5 at runtime on device for verification.
# ---- camera RGBA frames (B5): the band's mirror box source -------------------
## The mirror box is fed by `YoudooBridge.camera_frame_poll()` and blitted by the
## HUD, so it is part of *our* scene: it can be cropped, covered and styled, which
## the SDK's system overlay (composited above this app) cannot. Off-device the whole
## path is inert: no plugin -> `camera_frames_supported()` false -> the box keeps
## its placeholder chrome.
var _camera_overlay := false
var _camera_rgba_started := false
var _camera_rgba_retry := 0.0
var _camera_rgba_wait := 0.0
var _camera_rgba_accum := 0.0
var _camera_rgba_log_t := 0.0
var _camera_rgba_log_seq := 0
var _camera_rgba_frames := 0
var _camera_rgba_image: Image = null
var _camera_rgba_tex: ImageTexture = null
var _camera_rgba_size := Vector2i.ZERO
## Mirroring: the SDK overlay was confirmed correct on device with an INVERTED
## source rect (A.x1 > A.x2, i.e. the SDK mirror). The raw RGBA buffer is the same
## frame that overlay samples, so `flip_x = true` reproduces that orientation.
## F7 flips it live if the device disagrees.
var _camera_rgba_flip := true
var _camera_rgba_fallback_logged := false
## Capture tooling only (--camera-test): feeds a synthetic 384x216 RGBA frame
## through the **same** _camera_rgba_apply path the plugin uses, so the mirror-box
## blit (cover-crop, mirror flip, in-place texture update) can be verified, and
## screenshotted, without a device.
var _camera_test := false
var _camera_test_img: Image = null
var _camera_test_seq := 0
const CAMERA_RGBA_RATE := 15
const CAMERA_RGBA_POLL := 1.0 / 15.0
## Say why after this long without a first frame (the box keeps the placeholder;
## the pump keeps running, so a late frame is still used).
const CAMERA_RGBA_WAIT := 2.0
## The binder may still be connecting at boot: retry the pump for this long.
const CAMERA_RGBA_RETRY_S := 10.0
var _camera_live_armed := false
## True when the current mode wants the preview (armed AND in a live mode).
## Kept separate from `_camera_live_armed` so mode changes never disarm the flag.
var _camera_live_wanted := false
var _camera_live_on := false
var _camera_live_supported := false
var _camera_live_rect := Rect2(0.0, 0.0, 1.0, 1.0)
var _camera_live_mode := 0
var _camera_live_rect_index := 0
## Which SDK-derived variant the camera uses (index into CAMERA_VARIANTS):
## 0 = mirrored preview + `1-x` pose (shipped), 1 = raw preview + raw pose
## (fallback), 2 = H+V mirror control. F6 / remote MENU / remote INFO cycles it
## and re-sends immediately. The variant also carries the pose convention so
## preview and controls can never disagree by construction.
var _camera_variant_index := CAMERA_VARIANT_DEFAULT
## Provider-x -> game-x convention, kept in lockstep with the camera variant.
var _pose_mirror := true
## Ids this build last sent as ON, so a 2P -> 1P change can turn the extra id off.
var _camera_views_on: Array = []
var _camera_live_retry := 0.0
var _camera_live_unbound_logged := false
## Keyboard steering is a desktop-testing fallback only: it can never be armed on
## Android (body tracking is the only gameplay input in the shipped build).
var _allow_keyboard_steer := true
## Desktop-only dev pose (see `DESKTOP_AUTO_READY`): resolved once in `_ready()`.
var _auto_ready := false
## `--auto-ok` (verification only): inject ONE real OK press 0.8 s after boot
## through `Input.parse_input_event`, i.e. the exact path an RCU press takes. It
## exists so the desktop auto-ready path can be proven end to end (mode select ->
## READY -> countdown -> play) without a person and without a keyboard; it does
## not set `_tool_synth`, so the real ready gate runs.
var _auto_ok := false
var _auto_ok_done := false
var _auto_ok_done2 := false
## `--keys` (and Android debug builds): print every InputEventKey.
var _keys_diag := false
## One-action-per-frame guard: an Android press can surface as both a raw keycode
## and a ui_accept action in the same frame; we only ever read the raw keycode,
## and this drops a duplicate delivery of the same action in one frame.
var _last_action := PSRemote.ACT_NONE
var _last_action_frame := -1
## Cross-channel backstop (native hook vs. Godot's normal path vs. the
## SendHotKey broadcast): the same action within DUP_ACTION_MS is one press.
var _last_action_ms := -1000
## Android BACK arrives twice (KEY_BACK event + go_back_requested signal), in the
## same or adjacent frame; this drops the second delivery, not a second press.
var _last_back_frame := -10
var _perf := {"fps": 0.0, "draw": 0, "prim": 0, "p": 0, "t": 0, "w": 0}

# ---- always-on perf panel (owner request: 游戏启动后显示实时性能窗口) --------
# A 10 s history of 0.25 s buckets. `_perf_panel_sample()` runs once per frame and
# only writes six pre-sized array slots (no allocation, no engine query); the
# bucket boundary is also the 4 Hz publish tick, which is where the strings are
# rebuilt and where `Performance` is read. `--no-perf` hides the panel and stops
# the sampler entirely, so a hidden panel costs exactly nothing.
const PERF_BUCKET_SEC := 0.25
const PERF_BUCKETS := 40
## Double-tap window for the RCU's INFO key (the native hook maps INFO -> F7).
const PERF_TAP_MS := 420
var _perf_on := false
var _perf_labels: Array = []
var _perf_vals: Array = []
var _perf_pb_t := PackedFloat32Array()
var _perf_pb_n := PackedInt32Array()
var _perf_pb_ms := PackedFloat32Array()
var _perf_pb_max := PackedFloat32Array()
var _perf_pb_cam := PackedInt32Array()
var _perf_pb_i := 0
var _perf_f7_ms := -100000
var _capture_perf := false
var _perf_cap_t := 0.0
var _perf_cap_step := 0
var _perf_cap_n := 0
var _perf_cap_draw_on := 0
var _perf_cap_draw_off := 0
var _perf_cap_prim_on := 0
var _perf_cap_prim_off := 0

# ---- capture mode ----
var _capture := false
var _capture_2p := false
var _capture_flow := false
var _capture_escape := false
## Verification harnesses. They inject pose presence + synthetic steering, but
## menu steps are driven through real InputEventKey events.
var _capture_remote := false
var _remote_probe := false
var _tool_synth := false
var _cap_t := 0.0
var _cap_step := 0
var _cap_frames := 0
var _cap_fps_sum := 0.0
var _cap_fps_min := 999.0
var _cap_draw_sum := 0.0
var _cap_saved := false
var _cap_fx := false
var _cap_paused := false
var _cap_pause_shot := false
# --capture-flow timeline
var _cap_flow_step := 0
var _cap_play_t := 0.0
var _cap_play_frames := 0
var _cap_play_fps_sum := 0.0
var _cap_play_fps_min := 999.0
var _cap_play_draw_sum := 0.0
## Settlement window of the flow capture: the web-parity frames + the draw/fps
## numbers for the settle screen (the gate measures PLAY; this is evidence).
var _cap_settle_frames := 0
var _cap_settle_fps_sum := 0.0
var _cap_settle_fps_min := 999.0
var _cap_settle_draw_sum := 0.0
var _cap_settle_prim := 0
var _cap_settle_started := false
## Wall-clock frame time of the settle window. `--fixed-fps` makes `delta` a
## constant, so the stress-style ms measurement is the only honest cost number.
var _cap_settle_last_usec := 0
var _cap_settle_ms_sum := 0.0
var _cap_settle_ms_max := 0.0
## Pause / settle leg of the flow capture (B1 evidence frames).
var _b1_t := 0.0
# --capture-remote / --remote-probe timeline
var _remote_t := 0.0
var _remote_step := 0
## The settle-rise skip has been fed once (OK during the 1.1 s rise).
var _remote_skip_sent := false
var _remote_play_t := 0.0
var _remote_previewed := false
var _remote_done := false
# --capture-overlap (self-overlap occlusion evidence)
var _capture_overlap := false
var _overlap_tag := "shot"
var _overlap_t := 0.0
var _overlap_step := 0
## World-space centre of the synthetic lasso and the world point where the head
## side of the body crosses over the tail side (the crop target).
var _overlap_centre := Vector2.ZERO
var _overlap_cross := Vector2.ZERO
var _overlap_path := PackedVector2Array()
var _overlap_built := false
# --capture-tuning
var _capture_tuning := false
var _tune_t := 0.0
var _tune_step := 0
var _tune_seq: Array = []
var _tune_seq_i := 0
var _tune_next := 0.0
var _tune_shot_t := 0.0
# --capture-shake: scripted eat / kill / death impulses, one sample per frame.
## The measured screen-space camera offset is `(worlds[0].cam - cams[0]) * zoom`,
## i.e. exactly `fx.shake_offset()` as it lands on the viewport, in px.
var _capture_shake := false
var _shake_t := 0.0
var _shake_step := 0
var _shake_seq_t := 0.0
var _shake_ev := 0
var _shake_frames := 0
var _shake_peak_axis := 0.0
var _shake_peak_vec := 0.0
var _shake_settle_frame := -1
var _shake_win_name := ""
var _shake_trace: Array = []
# --capture-cam: scripted straight run + sharp turns, one camera sample per frame.
## Owner report (2026-11-14): "移动时只要角色变向就会立刻快拉相机导致的画面不稳" —
## the camera whips the moment the snake turns. This probe drives a fixed heading
## script through `_synth_steer` and prints the follow centre, its per-frame step,
## its speed and the head's screen offset, so the fix is a number, not a claim.
## The AI snakes, food and powerups are removed: the only camera motion measured
## is the follow law. `cams[]` is the follow centre (shake excluded by design).
const CAM_SEQ := [
	[0.0, 0.0, "straight"],
	[1.5, 1.5707963267948966, "turn_90"],
	[2.5, -1.5707963267948966, "u_turn_180"],
	[3.5, 0.0, "turn_90b"],
	[4.5, 0.0, "settle"],
]
const CAM_SEQ_END := 5.7
var _capture_cam := false
var _cam_cap_t := 0.0
var _cam_cap_step := 0
var _cam_cap_leg := 0
var _cam_cap_prev := Vector2.ZERO
var _cam_cap_leg_max_step := 0.0
var _cam_cap_leg_peak_v := 0.0
var _cam_cap_leg_head_max := 0.0
var _cam_cap_max_step := 0.0
var _cam_scripted := false
var _cam_script_angle := 0.0
# --capture-cam-boost: the acceleration evidence. Same scripted heading idea as
# CAM_SEQ, but the real boost buff + the pose wrist-speed ceiling are held for
# 4.5 s and the 90/180/90 turns happen inside that window.
## The probe's own numbers are per frame, so the before/after table is a
## measurement, not an opinion (see evidence/cam-boost-*.txt).
const CAM_BOOST_SEQ := [
	[0.0, 0.0, "normal_straight"],
	[1.0, 0.0, "boost_straight"],
	[2.5, 1.5707963267948966, "boost_turn90"],
	[3.5, -1.5707963267948966, "boost_u180"],
	[4.5, 0.0, "boost_turn90b"],
	[5.5, 0.0, "normal_settle"],
]
const CAM_BOOST_ON := 1.0
const CAM_BOOST_OFF := 5.5
const CAM_BOOST_END := 7.5
const CAM_BOOST_SHOT1 := 3.0
const CAM_BOOST_SHOT2 := 3.62
const CAM_BOOST_START := Vector2(1000.0, 1100.0)
var _capture_cam_boost := false
var _cam_boost_tag := "run"
## `--capture-pose-trace`: scripted hand path through the real mapper, one line per
## frame into `evidence/pose-trace-<law>.txt` (see the block below).
var _capture_pose_trace := false
## Live skeleton overlay over the camera pixels (F9 / `--no-skeleton`).
var _skeleton_on := true
var _cam_boost_t := 0.0
var _cam_boost_step := 0
var _cam_boost_leg := 0
var _cam_boost_prev := Vector2.ZERO
var _cam_boost_hold := false
var _cam_boost_leg_frames := 0
var _cam_boost_leg_max_step := 0.0
var _cam_boost_leg_peak_v := 0.0
var _cam_boost_leg_max_off := 0.0
var _cam_boost_leg_max_off_x := 0.0
var _cam_boost_leg_max_off_y := 0.0
var _cam_boost_leg_max_pct := 0.0
var _cam_boost_leg_out := 0
var _cam_boost_leg_clamp := 0
var _cam_boost_leg_catch := 0
var _cam_boost_leg_snake_max := 0.0
var _cam_boost_leg_clamp_max_off := 0.0
var _cam_boost_leg_clamp_max_pct := 0.0
var _cam_boost_frames := 0
var _cam_boost_max_off := 0.0
var _cam_boost_max_off_x := 0.0
var _cam_boost_max_off_y := 0.0
var _cam_boost_max_pct := 0.0
var _cam_boost_out_frames := 0
var _cam_boost_clamp_frames := 0
var _cam_boost_clamp_out_frames := 0
var _cam_boost_clamp_max_off := 0.0
var _cam_boost_clamp_max_pct := 0.0
var _cam_boost_catch_frames := 0
var _cam_boost_peak_v := 0.0
var _cam_boost_max_step := 0.0
var _cam_boost_snake_max := 0.0
var _cam_boost_vmax_max := 0.0
var _cam_boost_amax_max := 0.0
var _cam_boost_vmax_base_max := 0.0
var _cam_boost_amax_base_max := 0.0
var _cam_boost_min_edge := 1.0e18
var _cam_boost_min_head_edge := 1.0e18
var _cam_boost_shot1 := false
var _cam_boost_shot2 := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_capture_flow = args.has("--capture-flow")
	_capture_escape = args.has("--capture-escape")
	_capture_remote = args.has("--capture-remote")
	_capture_overlap = args.has("--capture-overlap")
	_capture_tuning = args.has("--capture-tuning")
	_capture_shake = args.has("--capture-shake")
	_capture_perf = args.has("--capture-perf")
	_capture_cam = args.has("--capture-cam")
	_capture_cam_boost = args.has("--capture-cam-boost")
	_capture_pose_trace = args.has("--capture-pose-trace")
	_capture_skeleton = args.has("--capture-skeleton")
	_capture_stress = args.has("--capture-stress")
	_capture_cam2p = args.has("--capture-cam2p")
	_stress_cam = not args.has("--stress-no-cam")
	_stress_no_hud = args.has("--stress-no-hud")
	_stress_no_world = args.has("--stress-no-world")
	_ptrace_tag = _str_from_args(args, "--pose-law=", "after")
	_cam_boost_tag = _str_from_args(args, "--cam-boost-tag=", "run")
	_overlap_tag = _str_from_args(args, "--overlap-tag=", "shot")
	_remote_probe = args.has("--remote-probe") and not _capture_remote
	_probe_nav = args.has("--remote-nav") and not _capture_remote and not _remote_probe
	_capture = args.has("--capture") or args.has("--capture2p") or _capture_flow \
		or _capture_escape
	_capture_2p = args.has("--capture2p")
	_tool_synth = _capture or _capture_remote or _remote_probe or _capture_overlap \
		or _capture_tuning or _capture_shake or _capture_perf or _capture_cam \
		or _capture_cam_boost or _capture_pose_trace or _capture_skeleton or _probe_nav \
		or _capture_stress or _capture_cam2p
	# ---- desktop dev pose (owner: the editor is stuck on 准备开始) -------------
	# On the PC there is no SDK camera, so `pose.tracking` is permanently false and
	# the READY gate can never open - the game sits on 准备开始 forever. On desktop
	# only (NEVER on Android, where a box with no person must keep waiting), treat
	# the slot as present with the hand raised, so the real READY timers
	# (READY_ZONE_SEC + READY_RAISE_SEC) run their normal course into countdown ->
	# play and the arrow keys work. Every capture/verification harness keeps its
	# old behaviour (`_tool_synth`), and `--no-auto-ready` turns it off so the real
	# gate can still be exercised on the desktop.
	_auto_ready = DESKTOP_AUTO_READY and not OS.has_feature("android") \
		and not _tool_synth and not args.has("--no-auto-ready")
	_auto_ok = args.has("--auto-ok")
	# Always-on perf panel: ON in every normal run (the owner asked for it), OFF
	# for the verification harnesses (they must keep producing byte-identical
	# frames) unless `--perf-overlay` forces it on. `--no-perf` is the
	# "get out of my shot" switch for the owner.
	_perf_on = (not _tool_synth) and not args.has("--no-perf")
	if args.has("--perf-overlay"):
		_perf_on = true
	# The stress harness measures the SHIPPED state, where the panel is ON by
	# default (owner request); its own cost is measured by the panel-off window.
	if _capture_stress and not args.has("--no-perf"):
		_perf_on = true
	_show_debug = args.has("--debug")
	# ---- live skeleton overlay (owner: 能看到骨骼线) ----
	# Drawn over the camera pixels in the band's mirror box and the READY slot
	# panes. ON by default; F9 (`adb shell input keyevent 139`) or
	# `--no-skeleton` turns it off. Its per-frame cost is measured by
	# `--capture-skeleton` (evidence/skeleton-overlay.md).
	_skeleton_on = not args.has("--no-skeleton")
	# ---- camera source: RGBA frames in the mirror box (shipped default) --------
	# The SDK's system overlay is retired as the default: it is composited ABOVE
	# this app, so the HUD cannot crop, cover or style it. `--camera-overlay`
	# (or F4 at runtime) restores it as a device fallback.
	_camera_overlay = args.has("--camera-overlay")
	_camera_test = args.has("--camera-test")
	_camera_rgba_flip = not args.has("--camera-no-flip")
	_camera_live_armed = _camera_overlay
	_camera_live_rect_index = CAMERA_PIP_INDEX
	_camera_live_rect = CAMERA_LIVE_RECTS[CAMERA_PIP_INDEX]
	# `--camera-variant=N` picks any camera variant at boot; the pose convention
	# is an INDEPENDENT runtime switch (INFO key / `--no-pose-mirror`), so the
	# owner can cross the two axes while testing by hand.
	var variant_arg := _camera_int_from_args(args, "--camera-variant=", CAMERA_VARIANT_DEFAULT)
	_camera_variant_index = clampi(variant_arg, 0, CAMERA_VARIANTS.size() - 1)
	_pose_mirror = not args.has("--no-pose-mirror")
	if args.has("--camera-live"):
		# Debug override: full-screen preview.
		_camera_live_rect_index = 0
		_camera_live_rect = CAMERA_LIVE_RECTS[0]
	# `--camera-live-pip` is accepted as an explicit alias of the shipped default.
	_camera_live_rect = _camera_rect_from_args(args, _camera_live_rect)
	_camera_live_mode = _camera_int_from_args(args, "--camera-live-mode=", 0)
	# Measurement only (--msaa=1|2|3): raise 2D MSAA at runtime so its fps/draw
	# cost can be measured WITHOUT editing project.godot (the equivalent project
	# setting is rendering/anti_aliasing/quality/msaa_2d = 1 for 2x, 2 for 4x).
	var msaa_req := _camera_int_from_args(args, "--msaa=", 0)
	if msaa_req > 0:
		get_viewport().msaa_2d = msaa_req
		print("[render] msaa_2d requested=%d active=%d hdr_2d=%s" % [msaa_req,
			get_viewport().msaa_2d, str(get_viewport().use_hdr_2d)])
	_allow_keyboard_steer = not OS.has_feature("android")
	# The headless key journey runs with the shipped Android gating: keyboard
	# steering fully disabled, menus remote-only.
	if _remote_probe or _probe_nav:
		_allow_keyboard_steer = false
	# Diagnostics: `--keys` always, and automatically on Android debug exports so
	# the device verifier only needs adb logcat (exported activities strip intent
	# extras, so a debug APK cannot be given `--keys` from adb).
	_keys_diag = args.has("--keys") or (OS.has_feature("android") and OS.is_debug_build())
	# Android BACK is handled by us, not by the engine's auto-quit. Both the raw
	# KEY_BACK event and the root window's go_back_requested signal land in
	# `_dispatch_action()` and are de-duplicated there.
	get_tree().quit_on_go_back = false
	get_tree().root.go_back_requested.connect(_on_go_back_requested)
	# The key journey compresses READY/COUNTDOWN waits; the real constants are
	# untouched (the probe never ships).
	if _remote_probe or _probe_nav:
		Engine.time_scale = 4.0
	# The escape capture compresses the 30 s timer (verification only; the real
	# threshold is READY_NO_PERSON_HINT_SEC and is never changed at runtime).
	if _capture_escape:
		Engine.time_scale = 6.0
	# --menu used to mean "keep the old menu"; mode select is the normal entry
	# now, so the flag is accepted and has no effect (old scripts keep working).
	var _menu_arg := args.has("--menu")

	# ---- rules ----
	cfg = PSConfig.new()
	if args.has("--lowend") or (OS.has_feature("android") and not args.has("--fullend")):
		cfg.apply_device_profile(PSConfig.PROFILE_LOW_END)
	# ---- persisted player settings (音效 / 最佳成绩 / 赛制) -------------------
	# `user://pose_snake.cfg`, shared with the character picker (`ps_skins.gd`).
	# Verification harnesses read nothing and write nothing: the release gate
	# compares two bitmap runs, and a best score saved by the first run would
	# change the second run's score row.
	PSSettings.harness = _tool_synth
	PSSettings.load_all()
	cfg.round.mode = StringName(PSSettings.round_mode)
	if args.has("--mute"):
		PSSettings.muted = true
	if args.has("--endless"):
		PSSettings.round_mode = PSSettings.MODE_ENDLESS
		cfg.round.mode = &"endless"
	_audio_on = not PSSettings.muted
	# `--pose-law=before` replays the pose trace under the PRE-FIX steering law:
	# unfiltered wrist/angle, single-threshold dead zone at 0.05, arm hysteresis
	# 1.15 and no dwell. Pure config overrides, so the rules carry no legacy path.
	if _capture_pose_trace and _ptrace_tag == "before":
		cfg.pose.wrist_smooth = 0.0
		cfg.pose.angle_smooth = 0.0
		cfg.pose.deadzone = 0.05
		cfg.pose.deadzone_exit = 1.0
		cfg.pose.arm_hysteresis = 1.15
		cfg.pose.arm_min_dwell_sec = 0.0
		print("[pose-trace] law=before: no filters, deadzone 0.05 (no hysteresis), " +
			"arm hysteresis 1.15, no dwell")
	# `--pose-ref=shoulder_r|chest` (measurement only): which joint is the steering
	# origin. `chest` ALSO restores the previous pass's pose numbers, so the two
	# trace files differ in the reference point alone:
	#     <godot> --headless --path . -- --capture-pose-trace --pose-ref=chest
	#     <godot> --headless --path . -- --capture-pose-trace
	# `--pose-dz=DZ,EXIT` overrides the dead zone for the calibration sweep,
	# `--pose-tag=NAME` renames the trace file (evidence/pose-trace-NAME.txt).
	var ref_arg := _str_from_args(args, "--pose-ref=", "shoulder_r")
	_ptrace_ref_joint = ref_arg
	cfg.pose.ref_joint = StringName(ref_arg)
	if ref_arg == "chest":
		cfg.pose.deadzone = 0.12
		cfg.pose.deadzone_exit = 1.35
		cfg.pose.speed.near = 0.30
		cfg.pose.speed.far = 0.75
		_ptrace_file_tag = "chest-ref"
		print("[pose-trace] ref=chest: previous pass numbers " +
			"(deadzone 0.12 exit 1.35, speed 0.30..0.75, origin = chest)")
	else:
		_ptrace_file_tag = "shoulder-ref"
	var dz_arg := _str_from_args(args, "--pose-dz=", "")
	if dz_arg != "":
		var dz_parts := dz_arg.split(",")
		if dz_parts.size() == 2:
			cfg.pose.deadzone = float(dz_parts[0])
			cfg.pose.deadzone_exit = float(dz_parts[1])
			print("[pose-trace] deadzone override: dz=%.3f exit=%.2fx" % [
				cfg.pose.deadzone, cfg.pose.deadzone_exit])
	# `--pose-speed=NEAR,FAR` (measurement only): overrides the distance -> speed
	# curve so the SAME scripted gestures can be quoted before AND after a
	# recalibration (2026-11-17 极限速度 pass: `--pose-speed=0.80,1.10` is the old
	# pair, the shipped default is what the `after` run uses).
	var spd_arg := _str_from_args(args, "--pose-speed=", "")
	if spd_arg != "":
		var spd_parts := spd_arg.split(",")
		if spd_parts.size() == 2:
			cfg.pose.speed.near = float(spd_parts[0])
			cfg.pose.speed.far = float(spd_parts[1])
			print("[pose-trace] speed curve override: near=%.2f far=%.2f" % [
				cfg.pose.speed.near, cfg.pose.speed.far])
	var tag_arg := _str_from_args(args, "--pose-tag=", "")
	if tag_arg != "":
		_ptrace_file_tag = tag_arg
	# `--pose-tau=W,A` (measurement only): override the two time constants so the
	# shipped values can be chosen from a sweep instead of a guess.
	var tau_arg := _str_from_args(args, "--pose-tau=", "")
	if tau_arg != "":
		var parts := tau_arg.split(",")
		if parts.size() == 2:
			cfg.pose.wrist_smooth = float(parts[0])
			cfg.pose.angle_smooth = float(parts[1])
			print("[pose-trace] tau override: wrist=%.3f s angle=%.3f s" % [
				cfg.pose.wrist_smooth, cfg.pose.angle_smooth])
	# `--pose-hang=off` (measurement only): disables the arm-hanging gate, i.e. the
	# PRE-RULE behaviour on the SAME scripted gestures. That is the A/B pair in
	# evidence/pose-trace-hang-{before,after}.txt: same code, same hand paths, the
	# gate alone differs. `hang_enter` is the only knob needed (1e9 = never enter).
	if _str_from_args(args, "--pose-hang=", "on") == "off":
		cfg.pose.hang_enter = 1.0e9
		print("[pose-trace] hang gate OFF: pre-rule law on the same gestures " +
			"(arm hanging steers down again)")
	# `--pose-motion=off` (measurement only): disables the motion override, i.e.
	# the law as it was BEFORE the fast-sweep fix, on the SAME scripted gestures.
	# That is the A/B pair in evidence/pose-trace-fast-{before,after}.txt: same
	# code, same hand paths, the motion gate alone differs.
	if _str_from_args(args, "--pose-motion=", "on") == "off":
		cfg.pose.motion.fast = 1.0e9
		cfg.pose.motion.frames = 1
		print("[pose-trace] motion override OFF: pre-fix law on the same sweeps " +
			"(both holds latch on position only)")
	tuning = PSTuning.new(cfg)
	game = PSGame.new(cfg, tuning, 20261112)

	# ---- assets / audio / fx ----
	var t0 := Time.get_ticks_msec()
	PSAssets.build()
	# Character skins: load the ten atlases + tube textures once and restore the
	# player's last pick from `user://pose_snake.cfg`. A missing character logs
	# once and that snake keeps the procedural head/body.
	PSSkins.prepare()
	print("[skin] %d characters, player=%s, missing=%d" % [PSSkins.count(),
		PSSkins.name_of(PSSkins.player_skin), PSSkins.missing])
	PSTheme.font()
	fx = PSFx.new()
	audio = PSAudio.new()
	audio.build(self)
	# The persisted mute is applied ONCE here, after the player pool exists, so a
	# headless run stays silent either way and a saved 音效 关 cannot be undone by
	# the next boot line.
	audio.set_muted(not _audio_on)
	print("[settings] %s" % PSSettings.describe())
	print("[settings] round.mode=%s  audio=%s  best=%d" % [
		String(cfg.round.mode), "on" if _audio_on else "off", PSSettings.best_length])

	# ---- bridge ----
	bridge = get_node_or_null("/root/YoudooBridge")
	pose = PSPoseInput.new(cfg, bridge)
	pose.set_mirror_x(_pose_mirror)
	if bridge != null and bridge.has_method("start"):
		bridge.start()
	# The mirror box's pixel source. It is started from `_camera_pump_sync` when a
	# screen with a camera box appears (READY/COUNTDOWN/PLAY/PAUSE) and stopped on
	# MODE_SELECT/MODE_SETTLE, so the decoder never runs unseen. Inert off-device
	# (no plugin / no V1_0_3 binder): the boxes keep the placeholder art and
	# `_camera_frames_tick` logs the reason once.
	if bridge != null and bridge.has_method("camera_live_supported"):
		_camera_live_supported = bridge.camera_live_supported()
	# One boot line stating the shipped variant, the pose convention and every
	# normalized AIDL view (x1,y1,x2,y2), so a device verifier can match logcat
	# against the screen.
	var boot_views: Array = _camera_view_defs()
	print("[camera] shipped default: camera mode %d/%d %s pose_mirror=%s views=%d aidl_mode=%d" % [
		_camera_variant_index + 1, CAMERA_VARIANTS.size(), _camera_mode_name(_camera_variant_index),
		str(_pose_mirror), boot_views.size(), _camera_live_mode])
	for view in boot_views:
		print(("[camera] boot id=%d A=%s (source crop, inverted x = mirror)  B=%s "
			+ "(on-screen; drawn above the app)") % [
			int(view["id"]), _float_rect_str(view["src"]), _float_rect_str(view["dst"])])
	if _camera_live_armed:
		print("[camera] armed at boot: supported=%s pip=%s aidl_mode=%d" % [
			_camera_live_supported, _camera_live_rect, _camera_live_mode])

	_steers.append(PSSteerInput.new())
	_steers.append(PSSteerInput.new())

	# ---- nodes ----
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = PSHud.new()
	hud.size = DESIGN
	hud.game = game
	hud.cfg = cfg
	hud.mode = MODE_SELECT
	hud.player_count = player_count
	hud.input_source = input_source
	hud.debug = _show_debug
	# Live skeleton overlay over the camera pixels: the HUD reads the pose input
	# layer's provider-space snapshot directly (no per-frame copy). Default ON —
	# the owner asked to see the tracked skeleton.
	hud.skel_src = pose
	hud.skel_on = _skeleton_on
	hud_layer.add_child(hud)
	_perf_panel_init()

	var stage_layer := CanvasLayer.new()
	stage_layer.layer = 20
	add_child(stage_layer)
	stage = PSStage.new()
	stage.size = DESIGN
	stage.visible = false
	stage.game = game
	stage.cfg = cfg
	stage_layer.add_child(stage)

	# Internal debug tuning panel: exists ONLY in a build that sets
	# `PSBuild.TUNING_ENABLED = true` (`src/present/ps_build.gd`). With the flag
	# off the panel script is never loaded, no node is created, so no key can
	# reach it and nothing is drawn or stepped (one boot line records the state).
	if PSBuild.TUNING_ENABLED:
		var tuning_layer := CanvasLayer.new()
		tuning_layer.layer = 30
		add_child(tuning_layer)
		var panel_script = load("res://src/present/ps_tuning_panel.gd")
		if panel_script == null:
			printerr("[tuning] TUNING_ENABLED but ps_tuning_panel.gd failed to load")
		else:
			_tuning_panel = panel_script.new()
			_tuning_panel.setup(cfg, tuning, game, fx)
			tuning_layer.add_child(_tuning_panel)
			print("[tuning] internal tuning panel ENABLED (debug build): %d rows, keys=%s" % [
				_tuning_panel.rows.size(), str(PSRemote.PANEL_KEYS)])
	else:
		print("[tuning] internal tuning panel off at build time (PSBuild.TUNING_ENABLED=false)")

	# Shipped Android: POSE only. Desktop keeps the keyboard fallback for testing,
	# but no UI on Android can select it (`_allow_keyboard_steer` is false).
	if _tool_synth:
		input_source = SRC_SYNTH
		if _capture_2p:
			player_count = 2
			game.set_player_count(2)
	elif bridge != null and bridge.is_available():
		input_source = SRC_POSE
	elif _allow_keyboard_steer:
		input_source = SRC_KEYBOARD
	else:
		input_source = SRC_POSE
	_rebuild_views()
	# Stress harness: per-pass CPU timing on the world views and the HUD (the
	# flags are compile-time-cheap early returns everywhere else).
	if _capture_stress:
		if hud != null:
			hud.prof = true
		for w in worlds:
			w.prof = true
	# Boot lands on the mode-select screen, whose backdrop is opaque: the arena
	# the views were just built with is covered, so the first frame already skips
	# it (every later transition sets this itself, see `_set_worlds_visible`).
	_set_worlds_visible(false)
	hud.input_source = input_source
	_snap_cameras()

	Engine.max_fps = 60
	if _capture_stress and args.has("--stress-uncapped"):
		# MEASUREMENT ONLY: uncap the frame rate and drop vsync so the windows show
		# the real cost of a frame instead of a vsync-quantised fps. The DEFAULT
		# stress run keeps the shipped 60/vsync state, because that is the number the
		# owner's target is stated in.
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		print("[stress] measurement mode: vsync off, max_fps 0 (shipped build is 60/vsync on)")
	print("[boot] PoseSnake presentation ready: godot=%s renderer=%s cjk=%s assets=%dms" % [
		Engine.get_version_info().string, RenderingServer.get_video_adapter_name(),
		PSTheme.cjk_ok(), Time.get_ticks_msec() - t0])
	print("[boot] viewport=%s window=%s profile=%s players=%d mode=%s" % [
		get_viewport().get_visible_rect().size, DisplayServer.window_get_size(),
		cfg.device_profile, game.players.size(), _flow_name(mode)])
	print("[boot] flow=select->ready->countdown->play  ready=zone_%.2fs+raise_%.2fs  countdown=%.1fs" % [
		READY_ZONE_SEC, READY_RAISE_SEC, READY_COUNTDOWN_SEC])
	print("[boot] input=%s keyboard_steer=%s menu=rcu ok=KEY_ENTER(DPAD_CENTER/ENTER/KP_ENTER/SPACE) back=KEY_BACK/KEY_ESCAPE keys_diag=%s" % [
		["pose", "keyboard", "synth"][input_source],
		"desktop-only" if _allow_keyboard_steer else "disabled",
		"on" if _keys_diag else "off"])
	if not OS.has_feature("android"):
		print("[boot] desktop dev pose: auto-ready %s (%s)" % [
			"on" if _auto_ready else "off",
			"--no-auto-ready to disable" if _auto_ready else "real ready gate"])
	if _keys_diag:
		print("[key] diagnostics on: press each remote button once, one [key] line per event")
	print("[perf] always-on panel %s: 4 Hz, 8 rows, bottom-right (1876,1002); toggles F10 / remote INFO x2%s" % [
		"ON" if _perf_on else "OFF",
		" (harness frame: --perf-overlay forces it on)" if not _perf_on else ""])
	_flow_to("mode_select", "boot")


## The plugin also clears the overlay in onMainDestroy(); this is the early path
## so a clean quit does not leave the SDK preview on screen.
func _exit_tree() -> void:
	if _camera_live_on and bridge != null and bridge.has_method("camera_live_stop"):
		bridge.camera_live_stop()
	if _camera_rgba_started and bridge != null and bridge.has_method("camera_frames_stop"):
		bridge.camera_frames_stop()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var real_dt := minf(delta, 0.1)
	now += real_dt
	frame_count += 1

	_poll_bridge_status(real_dt)
	# Verification only: the mode-select screen has no default focus, so it takes
	# LEFT (focus 单人模式) and then OK - two real presses through the input queue.
	if _auto_ok and now > 0.8:
		if not _auto_ok_done:
			_auto_ok_done = true
			print("[autook] real LEFT press at t=%.2fs (verification only)" % now)
			_feed_tap(KEY_LEFT)
		elif now > 0.95 and not _auto_ok_done2:
			_auto_ok_done2 = true
			print("[autook] real OK press at t=%.2fs (verification only)" % now)
			_feed_tap(KEY_ENTER)
	_resolve_input(real_dt)
	_camera_live_tick(real_dt)
	_camera_frames_tick(real_dt)

	match mode:
		MODE_PLAY:
			game.update(dt, (_steers if player_count > 1 else _steers[0]), real_dt)
			_drain_events()
			if game.state == PSGame.STATE_FINISHED:
				_enter_settle()
			else:
				_watch_play_slots(real_dt)
		MODE_READY:
			_update_ready(real_dt)
		MODE_COUNTDOWN:
			_update_countdown(real_dt)
		MODE_SELECT:
			pass
		MODE_SETTLE:
			# The stage owns its own clock: growth + camera rise share one 1.1 s
			# ease-out and stop at 3 s, so the settled frame is static.
			stage.tick(real_dt)

	if mode == MODE_PLAY or mode == MODE_SELECT or mode == MODE_READY:
		fx.update(real_dt)
	if go_flash > 0.0:
		go_flash = maxf(0.0, go_flash - real_dt * 1.2)
	_update_cameras(real_dt, dt)
	_update_hud(real_dt)
	for w in worlds:
		w.time = now
		w.queue_redraw()
	if hud != null:
		hud.queue_redraw()
	if stage != null and stage.visible:
		# The settled score screen is a still: redraw it only while it animates or
		# when the remote focus moved. Rebuilding the eight skin columns and the
		# strip type every frame was the whole settlement frame budget.
		if stage.is_animating() or stage.focus != _stage_focus_drawn:
			stage.queue_redraw()
		_stage_focus_drawn = stage.focus
	if _tuning_panel != null and _tuning_panel.open:
		_tuning_panel.time = now
		_tuning_panel.queue_redraw()

	_perf_sample(real_dt)
	if _perf_on:
		_perf_panel_sample(real_dt)
	if _probe_nav:
		_probe_nav_tick(real_dt)
	elif _capture_tuning:
		_capture_tuning_tick(real_dt)
	elif _capture_overlap:
		_capture_overlap_tick(real_dt)
	elif _capture_remote:
		_capture_remote_tick(real_dt)
	elif _remote_probe:
		_remote_probe_tick(real_dt)
	elif _capture_shake:
		_capture_shake_tick(real_dt)
	elif _capture_cam:
		_capture_cam_tick(real_dt)
	elif _capture_cam_boost:
		_capture_cam_boost_tick(real_dt)
	elif _capture_pose_trace:
		_capture_pose_trace_tick()
	elif _capture_skeleton:
		_capture_skeleton_tick(real_dt)
	elif _capture_perf:
		_capture_perf_tick(real_dt)
	elif _capture_stress:
		_capture_stress_tick(real_dt)
	elif _capture_cam2p:
		_capture_cam2p_tick(real_dt)
	elif _capture:
		if _capture_escape:
			_capture_escape_tick(real_dt)
		elif _capture_flow:
			_capture_flow_tick(real_dt)
		else:
			_capture_tick(real_dt)


# ------------------------------------------------------------------ nodes

## One world view for 1P, two clipped SubViewport views for split screen.
##
## Both are placed on the **gameplay canvas** (0,200,1920,880): the HUD band owns
## the top 200 px, so nothing on the play screen covers the playfield any more —
## this is the single biggest layout change of the web parity pass.
func _rebuild_views() -> void:
	for w in worlds:
		w.queue_free()
	worlds.clear()
	vps.clear()
	if split_root != null:
		split_root.queue_free()
		split_root = null
	if player_count <= 1:
		var w := PSWorldView.new()
		w.cfg = cfg
		w.game = game
		w.fx = fx
		w.prof = _capture_stress
		w.view = ARENA_SIZE
		w.position = Vector2(0.0, ARENA_TOP)
		add_child(w)
		worlds.append(w)
		spans[0] = _span_for(ARENA_SIZE)
		zooms[0] = minf(ARENA_SIZE.x / spans[0].x, ARENA_SIZE.y / spans[0].y)
		return
	split_root = Control.new()
	split_root.size = ARENA_SIZE
	split_root.position = Vector2(0.0, ARENA_TOP)
	split_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(split_root)
	var half := Vector2(ARENA_SIZE.x * 0.5, ARENA_SIZE.y)
	spans[0] = _span_for(half)
	spans[1] = spans[0]
	for i in 2:
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.position = Vector2(half.x * float(i), 0.0)
		cont.size = half
		cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
		split_root.add_child(cont)
		var vp := SubViewport.new()
		vp.size = Vector2i(int(half.x), int(half.y))
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		cont.add_child(vp)
		var w2 := PSWorldView.new()
		w2.cfg = cfg
		w2.game = game
		w2.fx = fx
		w2.prof = _capture_stress
		w2.view = half
		w2.player_index = i
		vp.add_child(w2)
		worlds.append(w2)
		vps.append(vp)
		zooms[i] = minf(half.x / spans[i].x, half.y / spans[i].y)


func _span_for(view_size: Vector2) -> Vector2:
	# short edge decides the world span, the long edge follows the aspect
	var boost: float = 1.0 if player_count <= 1 else cfg.view.split_span_boost
	var span: float = CAM_SPAN * boost
	var ratio := view_size.x / maxf(1.0, view_size.y)
	if ratio >= 1.0:
		return Vector2(span * ratio, span)
	return Vector2(span, span / ratio)


## Show/hide the arena (1P `PSWorldView`, 2P two SubViewports).
##
## SELECT/READY paint a full-screen opaque backdrop over the arena, so the world
## used to be rendered for nothing there — and in 2P that is two whole world
## passes per frame. The split SubViewports also stop updating: their
## `UPDATE_ALWAYS` keeps re-rendering even while hidden, which would keep paying
## the 2P cost with nothing on screen. `UPDATE_ALWAYS` is restored the moment the
## arena is shown again (COUNTDOWN/PLAY), and the render happens in the same frame.
func _set_worlds_visible(on: bool) -> void:
	if split_root != null:
		split_root.visible = on
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for vp in vps:
		vp.render_target_update_mode = mode
	for w in worlds:
		w.visible = on


## Capture tooling only (`--capture-flow`): hide snake bodies/heads/glow so the
## arena-only still frame can judge the grid and the restored in-play HUD panels.
## Nothing in the rules reads this; it is a draw-time flag on the world view.
func _set_hide_snakes(on: bool) -> void:
	for w in worlds:
		w.hide_snakes = on


# ------------------------------------------------------------------ flow

## `[flow]` breadcrumb: one line per state entry, with wall clock + seconds since
## boot. This is the state-transition proof for the new session flow.
func _flow_to(state: String, detail: String = "") -> void:
	var stamp := Time.get_time_string_from_system()
	if detail.is_empty():
		print("[flow] %s t=%.2fs  %s -> %s" % [stamp, now, _flow_prev, state])
	else:
		print("[flow] %s t=%.2fs  %s -> %s  (%s)" % [stamp, now, _flow_prev, state, detail])
	_flow_prev = state
	# ---- binding phase (Fix 1) ---------------------------------------------
	# A slot OWNS A PERSON ID. Only READY may bind or re-bind; every other phase
	# follows the ids frozen when the READY gate opened (see ps_pose_input.gd).
	# Pushed here because this is the single place every mode transition passes
	# through, so the binding FSM can never disagree with the screen.
	if pose != null:
		pose.set_phase(StringName(state))


func _flow_name(m: int) -> String:
	match m:
		MODE_READY:
			return "ready"
		MODE_COUNTDOWN:
			return "countdown"
		MODE_PLAY:
			return "play"
		MODE_PAUSE:
			return "pause"
		MODE_SETTLE:
			return "settle"
		_:
			return "mode_select"


# ------------------------------------------------- camera frames (RGBA path)

## Starts the RGBA camera-frame pump (15 fps, plugin default scale). Safe off-device:
## it logs why and returns false, and the mirror box keeps its placeholder chrome.
func _camera_frames_start() -> bool:
	if bridge == null or not bridge.has_method("camera_frames_supported"):
		if not _camera_rgba_fallback_logged:
			_camera_rgba_fallback_logged = true
			print(("[camera] rgba: no bridge (desktop/editor) -> mirror box placeholder; "
				+ "system overlay stays off"))
		_camera_rgba_retry = CAMERA_RGBA_RETRY_S
		return false
	if not bridge.is_available():
		# The plugin singleton never registered (desktop, or an export without the
		# plugin): log the bridge's own reason once and keep the placeholder box.
		if not _camera_rgba_fallback_logged:
			_camera_rgba_fallback_logged = true
			print(("[camera] rgba: YoudooBridge unavailable (%s) -> mirror box "
				+ "placeholder; system overlay stays off") % bridge.unavailable_reason())
		_camera_rgba_retry = CAMERA_RGBA_RETRY_S
		return false
	if not bridge.camera_frames_supported():
		return false
	var ok: bool = bridge.camera_frames_start(CAMERA_RGBA_RATE, 0.0)
	if ok:
		_camera_rgba_started = true
		print("[camera] rgba: pump started rate=%d scale=default(0.3) flip_x=%s" % [
			CAMERA_RGBA_RATE, str(_camera_rgba_flip)])
	return ok


## Stops the RGBA pump and forgets the retry clock. The last texture is kept on
## purpose: re-entering READY reuses it instead of flashing the placeholder art
## while the decoder warms up again. The pump is only started again on a screen
## that actually draws a camera box.
func _camera_frames_stop(reason: String) -> void:
	if bridge != null and bridge.has_method("camera_frames_stop"):
		bridge.camera_frames_stop()
	_camera_rgba_started = false
	_camera_rgba_accum = 0.0
	_camera_rgba_wait = 0.0
	_camera_rgba_retry = 0.0
	_camera_rgba_log_t = 0.0
	print("[camera] rgba: pump stopped (%s)" % reason)


## True while the current screen has a camera surface: the READY slot cards and
## the band's mirror box (PLAY / PAUSE / COUNTDOWN). MODE_SELECT and MODE_SETTLE
## have neither, and the pump must not decode there (it used to run forever on
## the menu and the plugin's `drops` counter climbed).
func _camera_surface_visible() -> bool:
	return mode == MODE_READY or mode == MODE_COUNTDOWN or mode == MODE_PLAY \
		or mode == MODE_PAUSE


## Starts/stops the pump to match the screen. Called from every mode transition;
## a no-op when the wanted state already holds. The overlay path (`--camera-overlay`)
## never uses the RGBA pump.
func _camera_pump_sync(reason: String) -> void:
	var want: bool = _camera_surface_visible() and not _camera_overlay
	if want == _camera_rgba_started:
		return
	if not want:
		_camera_frames_stop(reason)
		return
	if _camera_test:
		# --camera-test fabricates the frame; there is no plugin to start.
		_camera_rgba_started = true
		return
	_camera_frames_start()


## Pumps at most 15 fps and only acts when `seq` changed (the bridge hands each
## frame out exactly once). The texture is rebuilt ONLY when the frame size
## changes; otherwise the same Image + ImageTexture are updated in place, so steady
## state allocates one byte copy per frame and no GPU texture.
func _camera_frames_tick(dt: float) -> void:
	if _camera_overlay:
		return
	# Defensive: even if a transition missed the stop call, no screen without a
	# camera box (mode select / settlement) decodes or polls a frame.
	if not _camera_surface_visible():
		return
	if _camera_test:
		_camera_test_tick(dt)
		return
	if not _camera_rgba_started:
		# The binder may still be connecting at boot: retry, then say why once.
		_camera_rgba_retry += dt
		if _camera_rgba_retry >= 1.0:
			_camera_rgba_retry = 0.0
			_camera_frames_start()
			if not _camera_rgba_started and now >= CAMERA_RGBA_RETRY_S \
					and not _camera_rgba_fallback_logged:
				_camera_rgba_fallback_logged = true
				print(("[camera] rgba: no frames after %.0fs (%s) -> mirror box "
					+ "placeholder; system overlay stays off") % [now,
					"desktop/no plugin" if bridge == null or not bridge.is_available()
					else "pump refused (needs a bound IGameServiceV1_0_3)"])
		return
	_camera_rgba_accum += dt
	if _camera_rgba_accum < CAMERA_RGBA_POLL:
		return
	_camera_rgba_accum = 0.0
	var frame: Dictionary = bridge.camera_frame_poll()
	if not frame.is_empty():
		_camera_rgba_apply(frame)
	if _camera_rgba_tex == null:
		_camera_rgba_wait += dt
		if _camera_rgba_wait >= CAMERA_RGBA_WAIT and not _camera_rgba_fallback_logged:
			_camera_rgba_fallback_logged = true
			print(("[camera] rgba: pump running but no frame after %.0fs -> mirror "
				+ "box placeholder (see logcat tag YoudooSkeleton)") % _camera_rgba_wait)
	# `[camera] rgba: seq=... size=WxH fps=...`, at most once a second.
	_camera_rgba_log_t += CAMERA_RGBA_POLL
	if _camera_rgba_log_t >= 1.0:
		var info: Dictionary = bridge.camera_frame_info()
		print("[camera] rgba: seq=%d size=%dx%d fps=%d frames=%d drops=%d" % [
			_camera_rgba_log_seq, _camera_rgba_size.x, _camera_rgba_size.y,
			int(info.get("fps", 0)), _camera_rgba_frames, int(info.get("drops", 0))])
		_camera_rgba_log_t = 0.0


## One polled frame -> the HUD texture (in place unless the size changed).
func _camera_rgba_apply(frame: Dictionary) -> void:
	var w := int(frame.get("w", 0))
	var h := int(frame.get("h", 0))
	var bytes: PackedByteArray = frame.get("bytes", PackedByteArray())
	if w <= 0 or h <= 0 or bytes.size() != w * h * 4:
		return
	_camera_rgba_log_seq = int(frame.get("seq", _camera_rgba_log_seq))
	if _camera_rgba_tex == null or _camera_rgba_size != Vector2i(w, h):
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
		if img == null or img.is_empty():
			return
		_camera_rgba_image = img
		_camera_rgba_tex = ImageTexture.create_from_image(img)
		_camera_rgba_size = Vector2i(w, h)
		print("[camera] rgba: first frame %dx%d -> mirror box texture (flip_x=%s)" % [
			w, h, str(_camera_rgba_flip)])
	else:
		_camera_rgba_image.set_data(w, h, false, Image.FORMAT_RGBA8, bytes)
		_camera_rgba_tex.update(_camera_rgba_image)
	_camera_rgba_frames += 1


## --camera-test only: a 384x216 RGBA pattern through the real apply path.
## The left third is red, the right third blue, and a yellow marker sits left of
## centre, so a screenshot of the box proves both the cover-crop fit AND the mirror
## flip (with flip_x the marker must appear right of centre).
func _build_camera_test_image() -> void:
	var img := Image.create(384, 216, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.09, 0.16))
	img.fill_rect(Rect2i(0, 0, 120, 216), Color(0.85, 0.20, 0.28))
	img.fill_rect(Rect2i(264, 0, 120, 216), Color(0.18, 0.38, 0.95))
	img.fill_rect(Rect2i(120, 0, 144, 216), Color(0.10, 0.14, 0.22))
	img.fill_rect(Rect2i(96, 78, 56, 60), Color(1.0, 0.86, 0.16))
	img.fill_rect(Rect2i(0, 96, 384, 24), Color(0.9, 0.95, 1.0, 0.35))
	_camera_test_img = img


func _camera_test_tick(dt: float) -> void:
	_camera_rgba_accum += dt
	if _camera_rgba_accum < CAMERA_RGBA_POLL:
		return
	_camera_rgba_accum = 0.0
	if _camera_test_img == null:
		_build_camera_test_image()
		_camera_rgba_started = true
	_camera_test_seq += 1
	_camera_rgba_apply({"seq": _camera_test_seq, "w": _camera_test_img.get_width(),
		"h": _camera_test_img.get_height(), "bytes": _camera_test_img.get_data()})
	_camera_rgba_log_t += CAMERA_RGBA_POLL
	if _camera_rgba_log_t >= 1.0:
		print("[camera] rgba: seq=%d size=%dx%d fps=%d frames=%d (test pattern)" % [
			_camera_rgba_log_seq, _camera_rgba_size.x, _camera_rgba_size.y,
			CAMERA_RGBA_RATE, _camera_rgba_frames])
		_camera_rgba_log_t = 0.0


## F9 / `--no-skeleton`: show or hide the live skeleton over the camera pixels.
## One switch, one place; the HUD only reads `skel_on`.
func _toggle_skeleton(reason: String = "key") -> void:
	_skeleton_on = not _skeleton_on
	if hud != null:
		hud.skel_on = _skeleton_on
		hud.cam_toast = "SKELETON %s" % ("ON" if _skeleton_on else "OFF")
		hud.cam_toast_until = now + 2.0
	print("[skel] live skeleton overlay %s (%s)" % [
		"ON" if _skeleton_on else "OFF", reason])


## F7: mirror the RGBA frame in the box (the one thing the device check must
## confirm). The next polled frame is flipped the other way, so the change shows
## within ~66 ms.
func _toggle_camera_flip() -> void:
	_camera_rgba_flip = not _camera_rgba_flip
	print("[camera] F7: mirror box flip_x=%s" % str(_camera_rgba_flip))


# ------------------------------------------------------------- camera live

## A live mode is one where the player is in (or resuming) a round. Pause keeps
## it on: the round is still alive, resume needs no re-init, and the SDK service
## holds the overlay until we clear it. Menus (select/settle) are off.
func _mode_wants_camera() -> bool:
	return mode == MODE_READY or mode == MODE_COUNTDOWN or mode == MODE_PLAY \
		or mode == MODE_PAUSE


## Derives the wanted state from the armed flag + mode, then applies it.
## `_camera_live_armed` (user intent) and `_camera_live_wanted` (this mode) are
## separate so a mode change never silently disarms the F4/CLI request.
func _set_camera_live(mode_on: bool, reason: String) -> void:
	var want := _camera_live_armed and mode_on
	if want == _camera_live_wanted:
		return
	_camera_live_wanted = want
	_apply_camera_live(reason)


func _apply_camera_live(reason: String) -> void:
	if bridge == null or not bridge.has_method("camera_live_view"):
		return
	if not _camera_live_wanted:
		if _camera_live_on or not _camera_views_on.is_empty():
			# Teardown path: the plugin calls clearAllCameraLiveOnScreen(), so no
			# overlay can outlive READY/COUNTDOWN/PLAY/PAUSE.
			bridge.camera_live_clear()
			_camera_live_on = false
			_camera_views_on = []
			print("[camera] t=%.2fs OFF (all ids cleared) (%s)" % [now, reason])
		return
	if bridge.has_method("is_available") and not bridge.is_available():
		# Desktop/editor: a graceful no-op, and no point retrying.
		_camera_live_wanted = false
		_camera_live_on = false
		if not _camera_live_unbound_logged:
			_camera_live_unbound_logged = true
			print(("[camera] t=%.2fs requested but stays off: plugin not available " +
				"(desktop/editor) (%s)") % [now, reason])
		return
	_camera_live_supported = bridge.camera_live_supported()
	if not _camera_live_supported:
		# A V1_0_2-only device cannot ever enable it: stop retrying and say why.
		if str(_bridge_status.get("binder", "none")) == "IGameServiceV1_0_2":
			_camera_live_wanted = false
			if not _camera_live_unbound_logged:
				_camera_live_unbound_logged = true
				print("[camera] device SDT only exposes IGameServiceV1_0_2; " +
					"camera live needs V1_0_3 (staying off)")
			return
		# The binder is still connecting: keep the request, retry from _process.
		_camera_live_on = false
		if not _camera_live_unbound_logged:
			_camera_live_unbound_logged = true
			var why := "IGameServiceV1_0_3 not bound yet"
			if bridge.has_method("is_available") and not bridge.is_available():
				why = "plugin not available (desktop/editor)"
			print("[camera] t=%.2fs requested but stays off: %s (%s)" % [now, why, reason])
		return
	_camera_live_unbound_logged = false
	var views: Array = _camera_view_defs()
	var ok_all := true
	var keep := {}
	for view in views:
		var id: int = int(view["id"])
		var src: Array = view["src"]
		var dst: Array = view["dst"]
		var mode: int = int(view["mode"])
		keep[id] = true
		var ok: bool = bool(bridge.camera_live_view(id, true, src, dst, mode))
		ok_all = ok_all and ok
		# The exact values the service received, one line per view: A is the
		# source crop (inverted x = mirror), B the on-screen destination.
		print("[camera] t=%.2fs ON id=%d A=%s B=%s aidl=%d applied=%s (%s)" % [
			now, id, _float_rect_str(src), _float_rect_str(dst), mode, ok, reason])
	# A 2P -> 1P change must not leave the second overlay on screen.
	for old_id in _camera_views_on:
		if not keep.has(int(old_id)):
			bridge.camera_live_view(int(old_id), false,
				[0.0, 0.0, 1.0, 1.0], [0.0, 0.0, 1.0, 1.0], _camera_live_mode)
			print("[camera] t=%.2fs OFF id=%d (not in the current view list)" % [
				now, int(old_id)])
	_camera_views_on = []
	for view in views:
		_camera_views_on.append(int(view["id"]))
	_camera_live_on = ok_all
	print("[camera] t=%.2fs ON camera mode %d/%d %s pose_mirror=%s views=%d applied=%s (%s)" % [
		now, _camera_variant_index + 1, CAMERA_VARIANTS.size(),
		_camera_mode_name(_camera_variant_index), str(_pose_mirror), views.size(), ok_all, reason])


## F4: arm/disarm camera live at runtime (device verifier hook).
func _toggle_camera_live() -> void:
	_camera_live_armed = not _camera_live_armed
	_camera_live_unbound_logged = false
	_camera_live_supported = bridge != null and bridge.has_method("camera_live_supported") \
		and bridge.camera_live_supported()
	print("[camera] F4: armed=%s supported=%s mode=%s variant=%d/%d" % [
		_camera_live_armed, _camera_live_supported, _flow_name(mode),
		_camera_variant_index + 1, CAMERA_VARIANTS.size()])
	_set_camera_live(_mode_wants_camera() if _camera_live_armed else false, "f4")


## F5: DEBUG ONLY (desktop keyboard; the box has no keyboard, so no shipped path
## can reach it). The shipped destination is always CAMERA_PIP_INDEX — the band's
## mirror box — and the owner confirmed that geometry on device. F5 exists only
## to prove the overlay follows a rect change; it cycles
## band -> top-left -> full screen, and 2P ignores it (fixed per-player dests).
func _cycle_camera_rect() -> void:
	_camera_live_rect_index = (_camera_live_rect_index + 1) % CAMERA_LIVE_RECTS.size()
	_camera_live_rect = CAMERA_LIVE_RECTS[_camera_live_rect_index]
	print("[camera] F5: 1P pip rect=%s (index %d; 2P uses fixed per-player dests)" % [
		_camera_live_rect, _camera_live_rect_index])
	if _camera_live_wanted:
		_apply_camera_live("f5")


## F6 = remote MENU (82), via GodotApp's native hook. Cycles the camera
## variants only; the pose convention is the independent INFO toggle below:
##   1/3 SDK mirror H (A.x1>A.x2, A.y normal)  <- shipped default
##   2/3 mirror H+V (A = 1,1,0,0)              <- if the renderer needs both
##   3/3 raw frame (A = 0,0,1,1)               <- old behaviour / control
## Re-sends immediately and logs the exact A/B edges and the AIDL mode.
func _cycle_camera_mode(reason: String = "f6") -> void:
	_camera_variant_index = (_camera_variant_index + 1) % CAMERA_VARIANTS.size()
	_apply_camera_variant(reason)


## INFO (165) / adb keyevent 165 / KEY_F7: flip the pose handedness live.
## Independent of the camera variant, so the owner can test all four
## combinations without a rebuild. Logged exactly as
## `[pose] mirror=on|off (source=key)`.
func _toggle_pose_mirror(source: String = "key") -> void:
	_pose_mirror = not _pose_mirror
	if pose != null:
		pose.set_mirror_x(_pose_mirror)
	print("[pose] mirror=%s (source=%s)" % ["on" if _pose_mirror else "off", source])
	if hud != null:
		hud.cam_toast = "POSE mirror %s" % ("ON" if _pose_mirror else "OFF")
		hud.cam_toast_until = now + 3.0
	# The 2P per-player crop halves follow the pose convention, so re-send.
	if _camera_live_wanted:
		_apply_camera_live("pose-mirror")


## Applies the active camera variant, logs every view's exact values and
## re-sends if the preview is wanted.
func _apply_camera_variant(reason: String) -> void:
	print("[camera] %s: camera mode %d/%d %s pose_mirror=%s aidl_mode=%d wanted=%s" % [
		reason, _camera_variant_index + 1, CAMERA_VARIANTS.size(),
		_camera_mode_name(_camera_variant_index), str(_pose_mirror),
		_camera_live_mode, str(_camera_live_wanted)])
	for view in _camera_view_defs():
		print("[camera] %s: id=%d A=%s B=%s mode=%d" % [reason, int(view["id"]),
			_float_rect_str(view["src"]), _float_rect_str(view["dst"]),
			int(view["mode"])])
	if hud != null:
		hud.cam_toast = "CAM %d/%d  %s" % [
			_camera_variant_index + 1, CAMERA_VARIANTS.size(),
			_camera_mode_name(_camera_variant_index)]
		hud.cam_toast_until = now + 3.0
	if _camera_live_wanted:
		_apply_camera_live(reason.to_lower())


func _camera_variant() -> Dictionary:
	return CAMERA_VARIANTS[clampi(_camera_variant_index, 0, CAMERA_VARIANTS.size() - 1)]


## The exact per-view AIDL values this build will send, as Dictionaries:
## {"id": int, "src": [x1,y1,x2,y2], "dst": [x1,y1,x2,y2], "mode": int}.
## A may be inverted on x and/or y; B is never inverted. 1P = id 0, 2P = id 0/1
## with each player's own half of the sensor frame.
func _camera_view_defs() -> Array:
	var v: Dictionary = _camera_variant()
	var mirror_h: bool = bool(v["mirror_h"])
	var mirror_v: bool = bool(v["mirror_v"])
	var out: Array = []
	if player_count <= 1:
		out.append({
			"id": 0,
			"src": _camera_edges(CAMERA_LIVE_RECTS[0], mirror_h, mirror_v),
			"dst": _camera_edges(_camera_live_rect, false, false),
			"mode": _camera_live_mode,
		})
		return out
	# Slot 0 is the raw RIGHT half when the pose mirrors x (`1-x` keeps slot 0
	# on that side); with the raw pose convention it is the raw LEFT half.
	for i in 2:
		var src: Rect2 = CAMERA_2P_SRC[i] if _pose_mirror else CAMERA_2P_SRC[1 - i]
		out.append({
			"id": i,
			"src": _camera_edges(src, mirror_h, mirror_v),
			"dst": _camera_edges(CAMERA_2P_DEST[i], false, false),
			"mode": _camera_live_mode,
		})
	return out


## Rect2 -> AIDL [x1,y1,x2,y2], inverting either axis on request. Inversion is
## how the SDK mirrors (negative UV width), and the AIDL float edges keep it.
func _camera_edges(rect: Rect2, mirror_h: bool, mirror_v: bool) -> Array:
	var x1 := rect.position.x
	var y1 := rect.position.y
	var x2 := rect.end.x
	var y2 := rect.end.y
	if mirror_h:
		var tx := x1
		x1 = x2
		x2 = tx
	if mirror_v:
		var ty := y1
		y1 = y2
		y2 = ty
	return [x1, y1, x2, y2]


func _camera_mode_name(index: int) -> String:
	if index < 0 or index >= CAMERA_VARIANTS.size():
		return "?"
	return str(CAMERA_VARIANTS[index]["name"])


## AIDL-form edge text: x1,y1,x2,y2 (normalized, 3 decimals; may be inverted).
func _float_rect_str(e: Array) -> String:
	return "[%.3f,%.3f,%.3f,%.3f]" % [e[0], e[1], e[2], e[3]]


## AIDL-form rect text: x1,y1,x2,y2 (normalized, 3 decimals).
func _rect_str(rect: Rect2) -> String:
	return "[%.3f,%.3f,%.3f,%.3f]" % [
		rect.position.x, rect.position.y, rect.end.x, rect.end.y]


## Retries while the V1_0_3 binder is still connecting (1 Hz), and mirrors the
## plugin state after its reconnect re-send. No-op when the feature is disarmed.
func _camera_live_tick(dt: float) -> void:
	if not _camera_live_armed:
		return
	if _camera_live_wanted and not _camera_live_on:
		_camera_live_retry += dt
		if _camera_live_retry >= 1.0:
			_camera_live_retry = 0.0
			_apply_camera_live("retry")


func _camera_rect_from_args(args: PackedStringArray, fallback: Rect2) -> Rect2:
	for arg in args:
		if arg.begins_with("--camera-live-rect="):
			var parts := arg.trim_prefix("--camera-live-rect=").split(",", false)
			if parts.size() == 4:
				return Rect2(float(parts[0]), float(parts[1]),
					float(parts[2]), float(parts[3]))
			print("[camera] bad --camera-live-rect (want x,y,w,h): %s" % arg)
	return fallback


func _camera_int_from_args(args: PackedStringArray, prefix: String, fallback: int) -> int:
	for arg in args:
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return fallback


func _str_from_args(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


## MODE_SELECT is a real screen: it waits forever, there is no default and no
## auto-confirm. `reason` only feeds the log. Only a DPAD focus + OK leaves it;
## BACK exits the app from this root screen.
func _enter_select(reason: String = "") -> void:
	# Endless practice never settles, so this is its only exit: keep the record.
	_save_best_length()
	game.reset()
	mode = MODE_SELECT
	select_focus = -1
	help_open = false
	hud.help_open = false
	pause_focus = 0
	settle_focus = 0
	# Leaving the capture harness behind: on a device with the SDK bridge the
	# pose input is the normal path again for the next attempt.
	if bridge != null and bridge.is_available():
		input_source = SRC_POSE
	stage.visible = false
	# The select backdrop is opaque: no arena behind it (see `_set_worlds_visible`).
	_set_worlds_visible(false)
	hud.mode = MODE_SELECT
	hud.select_focus = -1
	hud.pause_focus = 0
	hud.input_source = input_source
	fx.reset()
	rows = []
	_reset_ready()
	_snap_cameras()
	_set_camera_live(false, "mode_select")
	_camera_pump_sync("mode_select")
	_flow_to("mode_select", reason)


## A mode card was chosen by the remote (DPAD focus + OK). This is the only path
## out of MODE_SELECT, so the player count is always an explicit choice.
func _on_mode_selected(n: int) -> void:
	if mode != MODE_SELECT:
		return
	_set_player_count(n)
	audio.play(&"pickup")
	_enter_ready("players=%d" % player_count)


func _enter_ready(reason: String) -> void:
	game.set_player_count(player_count)
	game.reset()
	# `reset()` seeds `best_length` with the start length; the shell owns the
	# persisted record (the core has no file access), so re-apply it here.
	_apply_best_length()
	# New round, new character line-up: the player keeps his pick and the nine
	# others are dealt to the AI snakes (distinct, stable until the next reset).
	_assign_skins()
	mode = MODE_READY
	select_focus = -1
	pause_focus = 0
	settle_focus = 0
	stage.visible = false
	# The ready backdrop is opaque too: the arena is hidden until COUNTDOWN.
	_set_worlds_visible(false)
	hud.mode = MODE_READY
	hud.player_count = player_count
	hud.pause_focus = 0
	fx.reset()
	rows = []
	_reset_ready()
	_snap_cameras()
	_set_camera_live(true, "ready")
	# The READY slot cards are camera surfaces now: start the RGBA pump here (it
	# used to start at boot and kept decoding on the mode-select screen).
	_camera_pump_sync("ready")
	_flow_to("ready", reason)


func _reset_ready() -> void:
	for i in 2:
		ready_state[i] = 0
		ready_zone[i] = 0.0
		ready_hold[i].reset()
		ready_fill[i] = 0.0
		ready_pop[i] = 0.0
		ready_lost[i] = 0.0
		_ready_log_t[i] = 0.0
		_ready_log_fill[i] = 0.0
		_ready_prev_raised[i] = false
		_ready_log_flap_t[i] = 0.0
	_ready_done_t = 0.0
	_ready_no_person_t = 0.0
	_nobody_hint = false
	_ready_slide = 0.0
	_ready_in_t = 0.0
	_play_lost_t = 0.0


## READY entry offset in px: +1400 -> 0 over 0.3 s, OutQuad (`1-(1-k)^2`), i.e.
## the reference's `ap.y = +1400` slide with its easing. 0 in every other mode
## (the COUNTDOWN `ready_slide` handles the exit).
func _ready_card_offset() -> float:
	if mode != MODE_READY:
		return 0.0
	var k := clampf(_ready_in_t / READY_SLIDE_SEC, 0.0, 1.0)
	return READY_SLIDE_FROM * (1.0 - k) * (1.0 - k)


## Mirrors ps_hud.READY_SLIDE_SEC / READY_SLIDE_FROM (keep the two files in sync).
const READY_SLIDE_SEC := 0.3
const READY_SLIDE_FROM := 1400.0


# ------------------------------------------------------------------ ready

## Per-frame READY update: slot state machines + the "nobody here" advisory.
## The simulation is not stepped from here (`PSGame.update()` is MODE_PLAY only).
func _update_ready(dt: float) -> void:
	# Entry motion clock (0.3 s): the cards slide from +1400 to 0, OutQuad. Drawn
	# only — nothing here can block input and it emits no log lines, so the 4 Hz
	# `[ready] fill=` rate is unchanged.
	_ready_in_t += dt
	var n := clampi(player_count, 1, 2)
	var any_present := false
	var all_ready := true
	for i in n:
		var present := _slot_present(i)
		if present:
			any_present = true
		_ready_step(i, present, _slot_hand_up(i), dt)
		# ---- binding phase (Fix 1) -----------------------------------------
		# The slot's binding completes only when THIS READY raise confirmation
		# completes (`ready_state == 2` -> 已准备), i.e. the same 1.0 s zone hold
		# and 1.5 s raise hold the cards show. `rh.hold` is the `raise=` number in
		# the `[bind]` line.
		if pose != null:
			pose.set_slot_raise_ok(i, int(ready_state[i]) == 2,
				float(ready_hold[i].hold))
		# The opening beat only starts while every confirmed player is still
		# visible: a slot inside its loss grace is not "ready" for this check.
		if not present or int(ready_state[i]) != 2:
			all_ready = false
	if any_present:
		_ready_no_person_t = 0.0
	else:
		_ready_no_person_t += dt
	# 30 s with nobody at all -> advisory panel. It never starts or ends a round;
	# BACK (available on every READY frame, not just after 30 s) is the only exit.
	_nobody_hint = _ready_no_person_t >= READY_NO_PERSON_HINT_SEC and not all_ready
	if all_ready:
		_ready_done_t += dt
		if _ready_done_t >= READY_DONE_HOLD_SEC:
			_begin_countdown("all_ready")
	else:
		_ready_done_t = 0.0


## One slot's state machine. Thresholds are seconds (see the READY_* constants):
## present for READY_ZONE_SEC -> 请举手确认准备, then READY_RAISE_SEC with a hand
## up -> 已准备. Leaving for longer than READY_LOST_GRACE_SEC falls back to
## 等待玩家进入屏幕 and clears the progress, so READY is re-enterable.
##
## The raise itself is grace-tolerant (`PSRaiseHold`): a frame with the wrist just
## under the threshold pauses the hold for `PSRaiseHold.GRACE_SEC` (0.30 s)
## instead of resetting it, because the 15-30 Hz pose stream is noisy enough that
## the old instant reset made a held raise unreachable on device.
func _ready_step(i: int, present: bool, hand_up: bool, dt: float) -> void:
	var rh = ready_hold[i]
	if not present:
		ready_lost[i] += dt
		if ready_lost[i] >= READY_LOST_GRACE_SEC and int(ready_state[i]) != 0:
			ready_state[i] = 0
			ready_zone[i] = 0.0
			rh.reset()
			ready_fill[i] = 0.0
			ready_pop[i] = 0.0
			_ready_log(i, "waiting", "left", false)
		return
	ready_lost[i] = 0.0
	ready_zone[i] = minf(ready_zone[i] + dt, READY_ZONE_SEC)
	if int(ready_state[i]) == 0:
		ready_state[i] = 1
		_ready_log(i, "raise", "present", hand_up)
	if int(ready_state[i]) == 1:
		# The raise gate opens only after the zone hold: before that a raised hand
		# neither counts nor starts a grace window.
		rh.step(now, dt, hand_up, ready_zone[i] >= READY_ZONE_SEC, READY_RAISE_SEC)
		ready_fill[i] = clampf(rh.hold / READY_RAISE_SEC, 0.0, 1.0)
		_ready_fill_log(i, hand_up, rh)
		if ready_fill[i] >= 1.0:
			ready_state[i] = 2
			ready_pop[i] = 0.0
			_ready_log(i, "ready", "raise=%.2fs" % rh.hold, hand_up)
	else:
		ready_pop[i] += dt


## Acquired = a person was mapped into this slot on the latest bridge frame.
## (The capture harnesses inject it: there is no SDK camera on the desktop.)
func _slot_present(i: int) -> bool:
	if _capture_flow or _capture_remote or _remote_probe or _probe_nav \
			or _capture_stress or _capture_cam2p:
		return true
	# Desktop dev pose: no bridge, but the card must still fill (see the const).
	if _auto_ready:
		return true
	if pose == null or not pose.tracking:
		return false
	return i < pose.slot_seen.size() and bool(pose.slot_seen[i])


## Raise check is "either hand", computed in ps_pose_input from both wrists.
func _slot_hand_up(i: int) -> bool:
	if _capture_flow or _capture_remote or _remote_probe or _probe_nav \
			or _capture_stress or _capture_cam2p:
		return true
	if _auto_ready:
		return true
	if pose == null:
		return false
	return i < pose.slot_hand_up.size() and bool(pose.slot_hand_up[i])


## A human slot that the person detector has genuinely LOST (not "hand not up"):
## the round is still alive but nobody is steering it. Two guards keep this from
## firing on a false positive:
##   * only the pose path counts (`input_source == SRC_POSE`), so the desktop
##     keyboard fallback and every capture harness are inert;
##   * `pose.tracking` must be true — a camera that never started is not "the
##     player left", it is "there is no pose at all" (booting / service down).
## Returns true only when EVERY human slot is gone: in 2P one remaining player
## still steers, so the round must not be yanked to READY.
func _human_slots_lost() -> bool:
	if _probe_nav:
		return _probe_slot_lost
	if input_source != SRC_POSE or pose == null or not pose.tracking:
		return false
	var n := clampi(player_count, 1, 2)
	for i in n:
		if i < pose.slot_seen.size() and bool(pose.slot_seen[i]):
			return false
	return true


## MODE_PLAY: the reference re-opens the READY panel when a player leaves the
## round (`XXAndroidParseData.cs:615-630`) instead of coasting. Our READY screen
## owns a fresh `game.reset()`, so entering it restarts the round for the player
## who comes back — documented in the `[flow]` line.
func _watch_play_slots(dt: float) -> void:
	if not _human_slots_lost():
		_play_lost_t = 0.0
		return
	_play_lost_t += dt
	if _play_lost_t < PLAY_SLOT_LOST_SEC:
		return
	_play_lost_t = 0.0
	print(("[flow] play: human slot(s) lost for %.2fs -> READY (reference reopen; "
		+ "the round is reset, the player re-confirms by raising a hand)") % PLAY_SLOT_LOST_SEC)
	_enter_ready("slot_lost")


## State transition line. `gr` = seconds left in the raise grace window, so a
## `raised=0 gr=0.28s` line proves the hold survived a dropped frame instead of
## being reset to 0 (the bug this pair of fixes addresses).
func _ready_log(i: int, state: String, why: String, raised: bool) -> void:
	print("[ready] t=%.2fs slot=%d fill=%.2f raised=%d gr=%.2fs -> %s (%s)" % [
		now, i, float(ready_fill[i]), 1 if raised else 0,
		float(ready_hold[i].grace), state, why])


## Progress line while a slot fills: at most 4/s for fill movement
## (`READY_FILL_LOG_SEC`) and only when the fill moved by >= 0.05. A raise-flag
## flip (hand dropped / came back) is the diagnostic a stalled hold needs, so it
## may skip the fill throttle — but at most twice a second, so a wrist hovering
## exactly on the threshold cannot flood logcat. The grace shows up here as
## `raised=0 gr=0.23s`: the hold was NOT reset by that frame.
func _ready_fill_log(i: int, raised: bool, rh) -> void:
	var fill: float = ready_fill[i]
	var flap: bool = raised != bool(_ready_prev_raised[i])
	_ready_prev_raised[i] = raised
	var moved: bool = absf(fill - float(_ready_log_fill[i])) >= 0.05
	var due: bool = now - float(_ready_log_t[i]) >= READY_FILL_LOG_SEC
	var flap_due: bool = flap and now - float(_ready_log_flap_t[i]) >= 0.5
	if not flap_due and (not moved or not due):
		return
	_ready_log_t[i] = now
	_ready_log_fill[i] = fill
	if flap:
		_ready_log_flap_t[i] = now
	print("[ready] t=%.2fs slot=%d fill=%.2f raised=%d gr=%.2fs hold=%.2fs" % [
		now, i, fill, 1 if raised else 0, float(rh.grace), float(rh.hold)])


# --------------------------------------------------------------- countdown

## Build the world now (so the arena is visible behind the beat) and freeze it:
## `PSGame.update()` is not called until MODE_PLAY, so no simulation time can
## pass during the beat.
func _begin_countdown(reason: String) -> void:
	game.set_player_count(player_count)
	game.start(0.0)
	fx.reset()
	rows = []
	rank_prev = 1
	go_flash = 0.0
	_countdown_t = 0.0
	_ready_slide = 0.0
	mode = MODE_COUNTDOWN
	hud.mode = MODE_COUNTDOWN
	hud.rank_prev = 1
	hud.rank_arrow = 0
	_rank_arrow_t = 0.0
	_nobody_hint = false
	pause_focus = 0
	settle_focus = 0
	stage.visible = false
	_set_worlds_visible(true)
	_snap_cameras()
	_set_camera_live(true, "countdown")
	_camera_pump_sync("countdown")
	_flow_to("countdown", "%s sim_t=%.3fs round=%.1fs" % [
		reason, game.time, game.round_left])


func _update_countdown(dt: float) -> void:
	_countdown_t += dt
	_ready_slide = clampf(_countdown_t / 0.35, 0.0, 1.0)
	if _countdown_t >= READY_COUNTDOWN_SEC:
		_begin_play()


func _begin_play() -> void:
	mode = MODE_PLAY
	hud.mode = MODE_PLAY
	go_flash = 1.0
	_play_lost_t = 0.0
	audio.play(&"go")
	_set_camera_live(true, "play")
	_camera_pump_sync("play")
	# game.time is still 0 here: nothing stepped the simulation before this line.
	_flow_to("play", "sim_t=%.3fs round=%.1fs" % [game.time, game.round_left])


## Push the persisted best length into the rules object. Called after every
## `game.reset()` that starts a round; the harness default (0) leaves the core's
## own seed in place, so a capture frame never depends on this PC's user file.
func _apply_best_length() -> void:
	if game == null:
		return
	game.best_length = maxi(int(game.best_length), int(PSSettings.best_length))


## Persist the historical best on every round exit: the settlement stage, and
## "pause -> 返回模式" (the only way out of an endless practice round, which never
## settles). `record_best` writes only when the number actually grew.
func _save_best_length() -> void:
	if game == null:
		return
	if PSSettings.record_best(int(game.best_length)):
		print("[settings] new best length=%d%s" % [int(game.best_length),
			" (harness: not written)" if PSSettings.harness
				else " -> " + PSSettings.SETTINGS_PATH])


func _enter_settle() -> void:
	_save_best_length()
	mode = MODE_SETTLE
	stage.begin(game.round_result, game, cfg)
	stage.t = 0.0
	stage.visible = true
	settle_focus = 0
	stage.focus = 0
	hud.mode = MODE_SETTLE
	_set_worlds_visible(false)
	audio.play(&"go", 0.8)
	_set_camera_live(false, "settle")
	# No camera surface on the settlement stage: stop decoding.
	_camera_pump_sync("settle")
	_flow_to("settle", "rank=%d" % game.player_rank())


## `reason` is only for the `[flow]` breadcrumb ("ok", "back", "resume", ...).
## Camera live deliberately stays ON in both directions: the round is still
## alive, resume does not need a re-init, and the SDK service keeps the overlay
## until it is cleared (only SELECT/SETTLE do that).
func _toggle_pause(reason: String = "") -> void:
	if mode == MODE_PLAY:
		mode = MODE_PAUSE
		pause_focus = 0
		hud.pause_focus = 0
		hud.mode = MODE_PAUSE
		# Pause keeps the band (and its mirror box) visible behind the scrim, so
		# the pump stays on; the call documents the intent and is a no-op.
		_camera_pump_sync("pause")
		_flow_to("pause", reason)
	elif mode == MODE_PAUSE:
		mode = MODE_PLAY
		hud.mode = MODE_PLAY
		_camera_pump_sync("resume")
		_flow_to("play", "resume" if reason.is_empty() else reason)


# ---------------------------------------------------------------- cameras

## Camera follow: two smoothings plus two hard caps.
##
## WHY (owner report 2026-11-14: "移动时只要角色变向就会立刻快拉相机导致的画面不稳")
## The old law built its goal from the **instantaneous** heading:
##
##     goal = head + Vector2(cos(heading), sin(heading)) * lookahead
##
## so every turn rotated that offset in place. At the speed cap the lookahead is
## 240 px, i.e. a 90 deg turn displaced the goal by 240*sqrt(2) = 339 px while the
## snake's 8.5-10 rad/s turn rate swept it in ~0.17 s (about 2000 px/s), and the
## 111 ms follow loop (follow = 9) turned that into 15-40 px single-frame camera
## jumps. That - not the shake - is the instability the owner feels.
##
## WHAT
##   1. the lookahead is a **low-passed vector** (`CAM_LA_TAU`), so a turn rotates
##      it over ~0.3 s instead of inside one frame; direction and length both
##      ramp, so a speed change cannot whip the goal either;
##   2. the lookahead **magnitude is capped at `CAM_LA_MAX`** (70 px, was up to
##      `cfg.camera.lookahead_max` = 240). The offset is what a turn has to swing,
##      so its length is also what the camera has to recover: 70 px keeps the
##      recovery inside a few calm seconds instead of many;
##   3. the follow law is still a frame-rate-independent exponential (dt-safe
##      `1 - exp(-follow * dt)`), rewritten as a velocity so it can be clamped;
##   4. the camera velocity is clamped by an adaptive speed + acceleration cap
##      (`_cam_caps`): the old static 324 px/s / 420 px/s^2 pair at normal speed,
##      growing with the round's measured boost speed, so a single frame can
##      never jump while a boost cannot outrun the follow;
##   5. a predictive catch-up term enforces the hard invariant (the head must not
##      leave the drawn arena rect) once the predicted offset leaves the safe box,
##      and the arena clamp / shake offset are unchanged. The shake is still
##      applied **after** the smoothing (`c + shake / zoom`), so a death still
##      kicks the picture.
const CAM_LA_MAX := 70.0
const CAM_LA_TAU := 0.32
const CAM_SPEED_EXTRA := 24.0
const CAM_ACCEL := 420.0
## ---- adaptive caps (owner report 2026-11-14: "当蛇加速时，镜头会追不上，导致蛇
## 跑出镜头范围") -------------------------------------------------------------
## The static caps above are tuned for the 280 px/s un-boosted snake: the camera
## may run at most `speed + 24` and accelerate at 420 px/s^2. A boost is x1.65 on
## top of the x1.80 pose wrist ceiling, i.e. 832 px/s measured here, and then the
## same 420 px/s^2 needs 2 s just to stop the old velocity after a turn - the head
## leaves the frame for 104 frames of the scripted boost run (evidence/
## cam-boost-before.txt). The caps therefore follow the snake:
##
##     vmax = max(324, 1.35 * peak + 220)      peak = measured round max, px/s
##     amax = max(420, 900 + peak)
##
## applied over the part of `peak` above 1.25x base speed. A normal run (peak
## 280 px/s here) therefore keeps the EXACT static 324 / 420 pair that cured the
## turn whip (peak turn speed 324 px/s, max step 5.40 px), while a boost gets the
## owner's requested headroom. `peak` is the round max, not the instantaneous
## speed: when a boost expires the camera is still travelling at boost speed, so
## collapsing the caps in that frame would slam it into a 420 px/s^2 brake.
const CAM_BOOST_VMAX_GAIN := 1.35
const CAM_BOOST_VMAX_FLAT := 220.0
const CAM_BOOST_AMAX_FLAT := 900.0
const CAM_BOOST_RAMP_LO := 0.25
const CAM_BOOST_RAMP_HI := 1.00
## A measured per-frame head velocity above this is a teleport (respawn), not
## motion; fall back to the rule speed for that frame.
const CAM_HEAD_VEL_MAX := 5000.0
## Safe frame used by the hard catch-up invariant. `CAM_SAFE_FRAC` is where the
## catch-up switches on, `CAM_SAFE_TARGET_FRAC` is where it aims and stays on
## until the head is back inside (hysteresis, so the camera cannot chatter on the
## trigger line). The measured normal-speed turn already reaches 64% of the SHORT
## half-extent (evidence/cam-turn-after.txt: head_y_max=280px of 440px), so a
## 0.30 box would fire during every calm turn and re-introduce the whip. 0.80 is
## the earliest trigger that leaves the normal-turn numbers untouched while still
## leaving a measurable margin to the drawn edge.
const CAM_SAFE_FRAC := 0.80
const CAM_SAFE_TARGET_FRAC := 0.70
## The camera must be able to close a safe-box overflow in this many seconds.
const CAM_CATCH_T := 0.25
var _cam_la: Array = [Vector2.ZERO, Vector2.ZERO]
var _cam_vel: Array = [Vector2.ZERO, Vector2.ZERO]
## Measured head position + the round's max plausible speed (the input to the
## adaptive caps). Reset by `_cam_seed` on every round start / respawn.
var _cam_head_prev: Array = [Vector2.ZERO, Vector2.ZERO]
var _cam_speed_max: Array = [0.0, 0.0]
## True while the catch-up term owns the follow for a view (see CAM_SAFE_FRAC).
var _cam_catch: Array = [false, false]
## Presentation-only diagnostics for the camera probes (view 0). The follow law
## writes them every frame; nothing in the rules reads them.
var _cam_dbg_speed := 0.0
var _cam_dbg_vmax := 0.0
var _cam_dbg_amax := 0.0
var _cam_dbg_vmax_base := 0.0
var _cam_dbg_amax_base := 0.0
var _cam_dbg_off := Vector2.ZERO
var _cam_dbg_safe := Vector2.ZERO
var _cam_dbg_catch := false
var _cam_dbg_clamp := false


## Adaptive camera caps for `speed` (px/s) with `peak` = the round's measured max
## speed. Returns (vmax, amax).
func _cam_caps(speed: float, peak: float) -> Vector2:
	var base: float = cfg.snake.base_speed
	var span: float = maxf(1.0, (CAM_BOOST_RAMP_HI - CAM_BOOST_RAMP_LO) * base)
	var ramp := clampf(((peak - base) - CAM_BOOST_RAMP_LO * base) / span, 0.0, 1.0)
	var vmax_lo := maxf(speed, base) + CAM_SPEED_EXTRA
	var vmax_hi: float = peak * CAM_BOOST_VMAX_GAIN + CAM_BOOST_VMAX_FLAT
	var amax_hi: float = CAM_BOOST_AMAX_FLAT + peak
	return Vector2(maxf(vmax_lo, lerpf(vmax_lo, vmax_hi, ramp)),
		maxf(CAM_ACCEL, lerpf(CAM_ACCEL, amax_hi, ramp)))


## Re-anchor both views: jump the follow centre onto its target and re-seed the
## smoothed lookahead + the velocity from the snake's current state, so the caps
## never turn a deliberate re-frame (boot, countdown, 2P change) into a slow drift.
func _snap_cameras() -> void:
	for i in 2:
		var t: Vector2 = game.cam_targets[i] if i < game.cam_targets.size() else game.cam_target
		cams[i] = t
		_cam_seed(i, game.players[i] if i < game.players.size() else null)


## Seed the smoothed lookahead vector and the follow velocity from a snake's
## current heading/speed. Used by every teleport (boot, countdown, 2P change and
## the >1500 px respawn snap): without it the acceleration cap would start the
## camera from a standstill and turn one teleport into a multi-second lag.
func _cam_seed(i: int, p) -> void:
	_cam_la[i] = Vector2.ZERO
	_cam_vel[i] = Vector2.ZERO
	_cam_speed_max[i] = 0.0
	_cam_catch[i] = false
	var t: Vector2 = game.cam_targets[i] if i < game.cam_targets.size() else game.cam_target
	_cam_head_prev[i] = t
	if p != null and p.alive and p.body.size() > 0:
		var dir := Vector2(cos(p.heading), sin(p.heading))
		_cam_la[i] = dir * _cam_lookahead(p)
		_cam_vel[i] = dir * p.speed
		_cam_head_prev[i] = p.body[0]
		_cam_speed_max[i] = maxf(0.0, p.speed)


## Lookahead length in world px: 0.45 x speed, capped at `CAM_LA_MAX` (the
## magnitude that a turn has to swing and that the caps then have to recover).
func _cam_lookahead(p) -> float:
	return minf(CAM_LA_MAX, p.speed * 0.45)


func _update_cameras(dt: float, sim_dt: float = -1.0) -> void:
	if sim_dt <= 0.0:
		sim_dt = dt
	var world_w: float = cfg.world.w
	var world_h: float = cfg.world.h
	var shake: Vector2 = fx.shake_offset()
	var la_k := 1.0 - exp(-dt / maxf(0.01, CAM_LA_TAU))
	var n := worlds.size()
	for i in n:
		var p = game.players[i] if i < game.players.size() else null
		var t: Vector2 = game.cam_targets[i] if i < game.cam_targets.size() else game.cam_target
		var head: Vector2 = t
		# ---- 0. measure the head: actual velocity and the round's max speed ----
		var head_vel := Vector2.ZERO
		var speed := 0.0
		if p != null and p.alive and p.body.size() > 0:
			head = p.body[0]
			if sim_dt > 0.0:
				var raw: Vector2 = (head - _cam_head_prev[i]) / sim_dt
				if raw.length() <= CAM_HEAD_VEL_MAX:
					head_vel = raw
			# First frame after a seed / a frozen snake: fall back to the rule's
			# own speed for one frame so the caps never see a bogus 0.
			if head_vel.length() <= 0.01 and not p.is_frozen():
				head_vel = Vector2(cos(p.heading), sin(p.heading)) * maxf(0.0, p.speed)
			speed = head_vel.length()
			if speed <= 0.01 and not p.is_frozen():
				speed = maxf(0.0, p.speed)
		_cam_head_prev[i] = head
		_cam_speed_max[i] = maxf(_cam_speed_max[i], speed)
		var peak: float = _cam_speed_max[i]
		var caps: Vector2 = _cam_caps(speed, peak)
		var fmax: float = caps.x
		var amax: float = caps.y
		var fmax_base: float = fmax
		var amax_base: float = amax
		# ---- 1. low-passed lookahead vector ----
		var want_la := Vector2.ZERO
		if p != null and p.alive and p.body.size() > 0:
			want_la = Vector2(cos(p.heading), sin(p.heading)) * _cam_lookahead(p)
		var la: Vector2 = _cam_la[i]
		la = la.lerp(want_la, la_k)
		_cam_la[i] = la
		var goal: Vector2 = t + la
		# ---- 2. velocity follow with the adaptive speed + acceleration caps ----
		var c: Vector2 = cams[i]
		var clamp_x := false
		var clamp_y := false
		var catching := false
		if c.distance_to(goal) > 1500.0:
			# Respawn / round start: re-anchor onto the new target and re-seed the
			# lookahead + velocity in sync (see `_cam_seed`).
			_cam_seed(i, p)
			c = t + _cam_la[i]
		else:
			var v: Vector2 = _cam_vel[i]
			var want_v: Vector2 = (goal - c) * cfg.camera.follow
			if want_v.length() > fmax:
				want_v = want_v.normalized() * fmax
			# ---- 3. hard catch-up invariant ----
			# Safe box = CAM_SAFE_FRAC of the visible half-extent. Once the head is
			# outside it, the camera must close the overflow within CAM_CATCH_T.
			# The arena clamp can make an offset unavoidable (the camera is already
			# on the arena limit and the head is on the far side of it); that axis
			# is excluded here and REPORTED by the probe, never "fixed" by pushing
			# the camera into the wall.
			var span: Vector2 = spans[i]
			var half := span * 0.5
			var lim_lo := Vector2(half.x, half.y)
			var lim_hi := Vector2(world_w - half.x, world_h - half.y)
			var off: Vector2 = head - c
			if span.x >= world_w:
				clamp_x = true
			elif off.x < 0.0 and c.x <= lim_lo.x + 0.01:
				clamp_x = true
			elif off.x > 0.0 and c.x >= lim_hi.x - 0.01:
				clamp_x = true
			if span.y >= world_h:
				clamp_y = true
			elif off.y < 0.0 and c.y <= lim_lo.y + 0.01:
				clamp_y = true
			elif off.y > 0.0 and c.y >= lim_hi.y - 0.01:
				clamp_y = true
			var safe := half * CAM_SAFE_FRAC
			var target := half * CAM_SAFE_TARGET_FRAC
			# Predict where the gap will be in CAM_CATCH_T if the camera does not
			# change velocity. Reacting to the CURRENT gap is already too late at
			# boost speed: a 90 deg turn reverses 800+ px/s in ~0.1 s, so the head
			# is at the safe box and past the drawn edge 0.25 s later (that is what
			# the 15 out-of-frame U-turn frames in the first adaptive attempt
			# showed). The predictive gap makes the catch-up lead the turn instead.
			var gap_vel: Vector2 = head_vel - v
			var pred: Vector2 = off + gap_vel * CAM_CATCH_T
			var out_x: bool = not clamp_x and absf(pred.x) > safe.x
			var out_y: bool = not clamp_y and absf(pred.y) > safe.y
			if out_x or out_y:
				_cam_catch[i] = true
			elif (clamp_x or absf(pred.x) <= target.x) \
					and (clamp_y or absf(pred.y) <= target.y):
				_cam_catch[i] = false
			var over := Vector2.ZERO
			if _cam_catch[i]:
				if not clamp_x and absf(pred.x) > target.x:
					over.x = signf(pred.x) * (absf(pred.x) - target.x)
				if not clamp_y and absf(pred.y) > target.y:
					over.y = signf(pred.y) * (absf(pred.y) - target.y)
			if over != Vector2.ZERO:
				catching = true
				# Constant acceleration that lands the predicted gap on the box
				# after T: pred - 0.5 * a * T^2 = pred - over  ->  a = 2*over/T^2.
				# The velocity target after T is `v + a*T`; the caps only GROW to
				# admit it, so the camera is never clamped below the requirement
				# that restores the safe box.
				var a_req: Vector2 = 2.0 * over / (CAM_CATCH_T * CAM_CATCH_T)
				var catch_v: Vector2 = v + a_req * CAM_CATCH_T
				fmax = maxf(fmax, catch_v.length())
				amax = maxf(amax, a_req.length())
				want_v = catch_v
			var dv: Vector2 = want_v - v
			var dv_max: float = amax * dt
			if dv.length() > dv_max:
				dv = dv.normalized() * dv_max
			v += dv
			_cam_vel[i] = v
			c += v * dt
		# ---- 4. arena clamp (after the follow, as before) ----
		var span2: Vector2 = spans[i]
		var half2 := span2 * 0.5
		var free := c
		if span2.x >= world_w:
			c.x = world_w * 0.5
		else:
			c.x = clampf(c.x, half2.x, world_w - half2.x)
		if span2.y >= world_h:
			c.y = world_h * 0.5
		else:
			c.y = clampf(c.y, half2.y, world_h - half2.y)
		# The clamp blocks the motion, so the blocked velocity component must die
		# with it; otherwise the camera "banks" speed into a wall it can never
		# spend and has to reverse it when the head comes back.
		var v_now: Vector2 = _cam_vel[i]
		if c.x != free.x:
			v_now.x = 0.0
		if c.y != free.y:
			v_now.y = 0.0
		_cam_vel[i] = v_now
		cams[i] = c
		if i == 0:
			_cam_dbg_speed = speed
			_cam_dbg_vmax = fmax
			_cam_dbg_amax = amax
			_cam_dbg_vmax_base = fmax_base
			_cam_dbg_amax_base = amax_base
			_cam_dbg_off = (head - c) * zooms[i]
			_cam_dbg_safe = span2 * 0.5 * CAM_SAFE_FRAC * zooms[i]
			_cam_dbg_catch = catching
			_cam_dbg_clamp = clamp_x or clamp_y
		var v2 = worlds[i]
		var z: float = zooms[i]
		v2.zoom = z
		v2.cam = c + shake / maxf(0.2, z)


# ------------------------------------------------------------------ input

func _poll_bridge_status(dt: float) -> void:
	if bridge == null or hud == null:
		return
	# `status()` crosses JNI and parses JSON: 4 Hz is plenty for a read-out.
	_status_accum += dt
	if _status_accum >= 0.25:
		_status_accum = 0.0
		_bridge_status = pose.status() if pose != null else {}
		_bridge_frames = int(_bridge_status.get("frames", 0))
		# The plugin re-sends camera live after a reconnect; mirror its state.
		if _camera_live_armed and bridge.has_method("camera_live_active"):
			_camera_live_on = bridge.camera_live_active()
	hud.bridge_ok = bridge.is_available()
	hud.bridge_bound = bool(_bridge_status.get("bound", false))
	hud.bridge_frames = _bridge_frames
	hud.bridge_age_ms = pose.frame_age() if pose != null else -1
	hud.bridge_binder = str(_bridge_status.get("binder", "none"))
	hud.bridge_error = str(_bridge_status.get("error", ""))
	hud.cam_rgba_tex = _camera_rgba_tex
	hud.cam_rgba_size = _camera_rgba_size
	hud.cam_rgba_flip = _camera_rgba_flip
	hud.cam_rgba_frames = _camera_rgba_frames
	if _camera_overlay:
		hud.cam_rgba_state = "off (--camera-overlay)"
	elif _camera_rgba_tex != null:
		hud.cam_rgba_state = "frames %dx%d" % [_camera_rgba_size.x, _camera_rgba_size.y]
	elif _camera_rgba_started:
		hud.cam_rgba_state = "pump on, no frame"
	else:
		hud.cam_rgba_state = "placeholder"
	hud.cam_supported = _camera_live_supported
	hud.cam_armed = _camera_live_armed
	hud.cam_on = _camera_live_on
	hud.cam_rect = _camera_live_rect
	hud.cam_mode = _camera_live_mode
	# The exact AIDL views the next re-send would use, for the F3 overlay.
	var cam_views: Array = _camera_view_defs()
	hud.cam_views = cam_views
	hud.cam_pose_mirror = _pose_mirror
	var cam0: Dictionary = cam_views[0] if not cam_views.is_empty() else {}
	if not cam0.is_empty():
		var src: Array = cam0["src"]
		var dst: Array = cam0["dst"]
		hud.cam_rect_a = Rect2(src[0], src[1], src[2] - src[0], src[3] - src[1])
		hud.cam_rect_b = Rect2(dst[0], dst[1], dst[2] - dst[0], dst[3] - dst[1])
	hud.cam_mode_label = "%d/%d %s" % [
		_camera_variant_index + 1, CAMERA_VARIANTS.size(),
		_camera_mode_name(_camera_variant_index)]
	hud.tracking = pose.tracking if pose != null else false
	# Persons = bridge frame `persons` dictionary size; slots = actually mapped.
	hud.persons = pose.persons if pose != null else 0
	hud.tracked_slots = pose.tracked_slots if pose != null else 0
	hud.ai_level = tuning.ai_level


func _resolve_input(real_dt: float) -> void:
	if pose != null:
		pose.poll(now, player_count)
	# Keyboard steering exists only for desktop testing: on Android this branch is
	# never compiled off but is permanently disabled (`_allow_keyboard_steer`).
	if _allow_keyboard_steer:
		_poll_keyboard()
	for i in 2:
		var st = _steers[i]
		st.clear()
		# 1. desktop-only keyboard (never armed on Android)
		if _allow_keyboard_steer and i == 0 \
				and (input_source == SRC_KEYBOARD or _keys_held):
			if kb.update(now, st):
				continue
		# 2. capture tooling only (`--capture*` / `--remote-probe`)
		if _tool_synth:
			_synth_steer(i, st)
			continue
		# 3. pose (the only gameplay input in the shipped build)
		if input_source == SRC_POSE and pose != null:
			st.copy_from(pose.steers[i])
	if hud == null:
		return
	var bad: bool = input_source == SRC_POSE and (pose == null or not pose.tracking
		or not _steers[0].is_usable())
	if bad:
		pose_lost_for += real_dt
	else:
		pose_lost_for = 0.0
	if pose_lost_for > 0.45 and mode == MODE_PLAY:
		hud.pose_hint = "未识别到人 · 请站到镜头前" if PSTheme.cjk_ok() \
			else "NO PERSON · STEP INTO VIEW"
	elif input_source == SRC_POSE and pose != null and pose.tracking and not _steers[0].valid:
		hud.pose_hint = "手放到身体外侧再移动" if PSTheme.cjk_ok() \
			else "MOVE YOUR HAND AWAY FROM YOUR CHEST"
	else:
		hud.pose_hint = ""


## Desktop-testing fallback only: feed the currently held direction into the
## mapper. Never called on Android.
func _poll_keyboard() -> void:
	var mask := 0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		mask |= PSKeyboardSteer.RIGHT
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		mask |= PSKeyboardSteer.DOWN
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		mask |= PSKeyboardSteer.LEFT
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		mask |= PSKeyboardSteer.UP
	_keys_held = mask != 0
	if _keys_held:
		kb.set_dirs(mask, now)


## Capture-tooling autopilot steering (no mouse path: gameplay is pose only).
func _synth_steer(slot: int, st) -> void:
	var p = game.players[slot] if slot < game.players.size() else null
	if p == null or not p.alive or p.body.size() == 0:
		return
	# `--capture-cam` drives a fixed heading script instead of the pellet chase.
	if _cam_scripted and slot == 0:
		st.set_keyboard(_cam_script_angle)
		# `--capture-cam-boost`: the wrist-distance multiplier is a REAL pose
		# input in the shipped build (0.40..1.80), so the probe drives it at the
		# ceiling instead of pretending a keyboard user can reach boost speeds.
		if _cam_boost_hold:
			st.speed_scale = cfg.pose.speed.max_limit
		return
	var head: Vector2 = p.body[0]
	st.set_keyboard(_autopilot(p, head))


## Capture / demo autopilot: chase the best pellet, but never into a wall.
func _autopilot(p, head: Vector2) -> float:
	var best_angle: float = p.heading
	var best := -1e9
	var foods: Array = game.foods
	var i := 0
	var n: int = foods.size()
	while i < n:
		var f = foods[i]
		i += 1
		var dx: float = f.x - head.x
		var dy: float = f.y - head.y
		var d2 := dx * dx + dy * dy
		if d2 > 2250000.0:
			continue
		var d := sqrt(d2) + 1.0
		var a := atan2(dy, dx)
		var diff := absf(_norm(a - p.heading))
		var score := (2.2 if f.big else 0.6) + 240.0 / d - diff * 1.6
		if score > best:
			best = score
			best_angle = a
	var margin := 420.0
	var w: float = cfg.world.w
	var h: float = cfg.world.h
	var push := Vector2.ZERO
	if head.x < margin:
		push.x += (margin - head.x) / margin
	if head.x > w - margin:
		push.x -= (head.x - (w - margin)) / margin
	if head.y < margin:
		push.y += (margin - head.y) / margin
	if head.y > h - margin:
		push.y -= (head.y - (h - margin)) / margin
	if push.length() > 0.35:
		best_angle = atan2(push.y, push.x)
	return best_angle


func _norm(a: float) -> float:
	while a > PI:
		a -= TAU
	while a < -PI:
		a += TAU
	return a


# ---------------------------------------------------------------- events

func _drain_events() -> void:
	var q = game.events
	var i := 0
	var n: int = q.count
	while i < n:
		var ev = q.events[i]
		i += 1
		match ev.type:
			PSEvents.EV_FOOD:
				fx.eat(ev.x, ev.y, ev.color, ev.big)
				audio.play(&"big" if ev.big else &"eat", 0.9 + fx.rnd() * 0.25)
				# The eat shake stays (owner: 吃东西抖动可留). It is the smallest
				# request in the system - 1.0 px on a pellet, 2.5 px on big food -
				# and `SHAKE_SCALE` trims it like everything else.
				if ev.own:
					fx.add_shake(2.5 if ev.big else 1.0)
					if ev.big:
						fx.add_flash(0.10, ev.color)
			PSEvents.EV_POWERUP:
				fx.pickup(ev.x, ev.y, ev.color)
				fx.text(ev.x, ev.y - 60.0, ev.label, ev.color, 30.0)
				audio.play(&"pickup")
			PSEvents.EV_DEATH:
				fx.death(ev.points, ev.color, Vector2(ev.x, ev.y))
				audio.play(&"kill" if ev.killer_is_player else &"death", 0.9 + fx.rnd() * 0.2)
				if ev.own:
					fx.add_shake(16.0)
					fx.add_flash(0.24, Color(1.0, 0.3, 0.4))
			PSEvents.EV_TEXT:
				fx.text(ev.x, ev.y, ev.text, ev.color, ev.text_size)


# ------------------------------------------------------------------- HUD

func _update_hud(dt: float) -> void:
	hud.mode = mode
	hud.player_count = player_count
	hud.input_source = input_source
	hud.debug = _show_debug
	hud.perf = _perf
	hud.go_flash = go_flash
	hud.time = now
	hud.select_focus = select_focus
	hud.help_open = help_open
	hud.audio_on = _audio_on
	hud.round_mode = String(cfg.round.mode)
	hud.pause_focus = pause_focus
	hud.countdown_beat = _countdown_t / READY_COUNTDOWN_SEC if mode == MODE_COUNTDOWN else -1.0
	hud.ready_slide = _ready_slide
	hud.ready_card_dy = _ready_card_offset()
	hud.nobody_hint = _nobody_hint
	hud.ready_state = ready_state
	hud.ready_fill = ready_fill
	hud.ready_pop = ready_pop
	# Minimap viewport rect: the same centre/span `_update_cameras` wrote into
	# `worlds[0]` (cam is that centre plus the shake offset), so the drawn rect is
	# exactly what the arena is showing.
	if not cams.is_empty():
		hud.cam_center = cams[0]
	if not spans.is_empty():
		hud.world_span = spans[0]
	if stage != null:
		stage.focus = settle_focus
	hud_accum += dt
	if hud_accum >= 0.2:
		hud_accum = 0.0
		if mode == MODE_PLAY or mode == MODE_SETTLE:
			rows = game.live_ranking()
			hud.rows = rows
			var rk: int = game.player_rank()
			if rk != rank_prev:
				hud.rank_arrow = 1 if rk < rank_prev else -1
				rank_prev = rk
				_rank_arrow_t = 2.6
			elif _rank_arrow_t > 0.0:
				_rank_arrow_t -= 0.2
				if _rank_arrow_t <= 0.0:
					hud.rank_arrow = 0


# ------------------------------------------------------------------- perf

func _perf_sample(dt: float) -> void:
	perf_accum += dt
	if perf_accum < 1.0:
		return
	perf_accum = 0.0
	_perf["fps"] = Engine.get_frames_per_second()
	_perf["draw"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_perf["prim"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_perf["p"] = fx.pcount
	_perf["t"] = fx.tcount
	_perf["w"] = fx.wcount
	print("[perf] fps=%d draw=%d prim=%d snakes=%d food=%d pwr=%d fx=%d/%d/%d zoom=%.2f cam=(%d,%d)" % [
		_perf["fps"], _perf["draw"], _perf["prim"], game.snakes.size(), game.foods.size(),
		game.powerups.size(), fx.pcount, fx.tcount, fx.wcount, zooms[0], int(cams[0].x),
		int(cams[0].y)])
	_print_pose_diag()


# ------------------------------------- always-on perf panel (F10 / INFO x2)
#
# The read-out itself is drawn by `PSHud._draw_perf()`; everything below is the
# sampling side. Two rules keep it near-free:
#   * the per-frame path (`_perf_panel_sample`) only accumulates into pre-sized
#     Packed arrays - no allocation, no `Performance` query, no string build;
#   * the engine queries and the string formatting happen on a 0.25 s bucket
#     boundary, i.e. exactly 4 Hz, into the SAME `_perf_vals` array the HUD draws
#     (handed over by reference, so nothing is copied per frame).
# With the panel off (`--no-perf`) neither runs at all.

## Build the read-out once and hand the arrays to the HUD by reference.
func _perf_panel_init() -> void:
	_perf_pb_t.resize(PERF_BUCKETS)
	_perf_pb_n.resize(PERF_BUCKETS)
	_perf_pb_ms.resize(PERF_BUCKETS)
	_perf_pb_max.resize(PERF_BUCKETS)
	_perf_pb_cam.resize(PERF_BUCKETS)
	_perf_labels = ["PERF", "fps", "frame ms", "draw calls", "primitives",
		"objects", "mem st+tx", "rgba fps"]
	_perf_vals = ["F10 / INFO 2x", "-", "-", "-", "-", "-", "-", "-"]
	_perf_panel_reset()
	if hud != null:
		hud.perf_labels = _perf_labels
		hud.perf_vals = _perf_vals
		hud.perf_on = _perf_on


## Drop the history (on toggle / capture start): a partly filled 10 s window
## would otherwise mix stale zero buckets into the minimum.
func _perf_panel_reset() -> void:
	for i in PERF_BUCKETS:
		_perf_pb_t[i] = 0.0
		_perf_pb_n[i] = 0
		_perf_pb_ms[i] = 0.0
		_perf_pb_max[i] = 0.0
		_perf_pb_cam[i] = 0
	_perf_pb_i = 0


## Force the panel on/off without the key path (capture harnesses).
func _perf_panel_force(on: bool) -> void:
	_perf_on = on
	if hud != null:
		hud.perf_on = on
	if on:
		_perf_panel_reset()


## F10 / double-tap INFO / `--no-perf`. One switch, one place.
func _toggle_perf_panel(reason: String) -> void:
	_perf_on = not _perf_on
	if hud != null:
		hud.perf_on = _perf_on
	if _perf_on:
		_perf_panel_reset()
	print("[perf] always-on panel %s (%s)" % ["ON" if _perf_on else "OFF", reason])


## Index of the bucket `back` positions behind the newest closed one.
func _perf_bucket_index(back: int) -> int:
	return (_perf_pb_i - 1 - back + PERF_BUCKETS * 8) % PERF_BUCKETS


## Once per frame. Six array writes; the bucket boundary is the 4 Hz publish.
func _perf_panel_sample(dt: float) -> void:
	var i := _perf_pb_i
	_perf_pb_t[i] += dt
	_perf_pb_n[i] += 1
	var ms := dt * 1000.0
	_perf_pb_ms[i] += ms
	if ms > _perf_pb_max[i]:
		_perf_pb_max[i] = ms
	if _perf_pb_t[i] < PERF_BUCKET_SEC:
		return
	# Close the bucket, advance the ring, then publish: `_perf_bucket_index(0)`
	# is the bucket that just closed.
	_perf_pb_cam[i] = _camera_rgba_frames
	var j := (i + 1) % PERF_BUCKETS
	_perf_pb_i = j
	_perf_pb_t[j] = 0.0
	_perf_pb_n[j] = 0
	_perf_pb_ms[j] = 0.0
	_perf_pb_max[j] = 0.0
	_perf_pb_cam[j] = 0
	_perf_publish()


## The 4 Hz refresh: the only place the panel touches the engine or builds text.
func _perf_publish() -> void:
	if _perf_vals.is_empty():
		return
	# ---- fps: mean over the last 1 s (4 buckets) ----
	var frames := 0
	var secs := 0.0
	var ms_sum := 0.0
	var ms_max := 0.0
	for k in 4:
		var idx := _perf_bucket_index(k)
		if _perf_pb_t[idx] <= 0.0:
			continue
		frames += _perf_pb_n[idx]
		secs += _perf_pb_t[idx]
		ms_sum += _perf_pb_ms[idx]
		ms_max = maxf(ms_max, _perf_pb_max[idx])
	# ---- fps min: the same 1 s window, walked ten times over the 10 s ring ----
	var fps_min := 1.0e9
	for w in PERF_BUCKETS / 4:
		var f2 := 0
		var s2 := 0.0
		var ok := true
		for j in 4:
			var idx2 := _perf_bucket_index(w * 4 + j)
			if _perf_pb_t[idx2] <= 0.0:
				ok = false
				break
			f2 += _perf_pb_n[idx2]
			s2 += _perf_pb_t[idx2]
		if ok and s2 > 0.0:
			fps_min = minf(fps_min, float(f2) / s2)
	if secs > 0.0:
		if fps_min > 1.0e8:
			fps_min = float(frames) / secs
		_perf_vals[1] = "%.1f / %.1f" % [float(frames) / secs, fps_min]
		_perf_vals[2] = "%.1f / %.1f" % [ms_sum / maxf(1.0, float(frames)), ms_max]
	_perf_vals[3] = str(int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_perf_vals[4] = str(int(Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_perf_vals[5] = "%d / %d" % [
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
	_perf_vals[6] = "%.1f + %.1f MB" % [
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0]
	# ---- RGBA camera: frames actually received over the same window ----
	if not _camera_rgba_started:
		_perf_vals[7] = "off"
	elif secs > 0.0:
		var cam_old: int = _perf_pb_cam[_perf_bucket_index(3)]
		_perf_vals[7] = "%.1f" % (float(_camera_rgba_frames - cam_old) / secs)


## Body-tracking diagnostics: proves on-device that the SDK skeleton is being
## mapped to a heading (layout / WHICH JOINT STEERS / normalised reach / angle).
## `ref` is the steering reference joint and `kp` its index in the active layout
## (youdoo18: ref=shoulder_r kp=6, wrist=rwri 10), so a device log proves the
## owner's 胸前点位 -> 右肩 change took effect. `hand` is the auto-picked arm,
## which only feeds the raise test now (steering is right-arm fixed).
## `persons` is `frame["persons"].size()` from the newest bridge frame (the SDK's
## own count); `slots` is how many of our 1/2 player slots actually got mapped.
## `bound` is the SDK person id each slot OWNS (`pose.bound_ids`): with the binding
## phase (Fix 1) a slot follows that id for the whole round, so `bound=3,-1` on a
## device log proves the split-screen slot did not get re-assigned by position.
## Cheap enough to keep on for debug builds; drop it for a release build.
func _print_pose_diag() -> void:
	if pose == null:
		return
	var d: Dictionary = pose.diag
	print("[pose] layout=%s ref=%s kp=%d hand=%s dist_n=%.2f angle=%.3f conf=%.2f torso=%.0f reason=%s s0=%s s1=%s persons=%d slots=%d age=%dms bound=%d,%d" % [
		String(d.get("layout", "?")), String(d.get("ref", "?")), int(d.get("kp", -1)),
		String(d.get("hand", "-")), float(d.get("dist_n", 0.0)),
		float(d.get("angle", 0.0)), float(d.get("conf", 0.0)), float(d.get("torso", 0.0)),
		String(d.get("reason", "")), str(d.get("slot0", false)), str(d.get("slot1", false)),
		pose.persons, pose.tracked_slots, pose.frame_age(),
		int(d.get("bound0", -1)), int(d.get("bound1", -1))])


# --------------------------------------------------------------- capture

func _capture_tick(dt: float) -> void:
	_cap_t += dt
	if _cap_t > 0.9 and _cap_step == 0:
		_cap_step = 1
		# MODE_SELECT is the first screen now; keep the historical file name.
		_save_png("res://evidence/render-preview-menu.png")
		_begin_countdown("capture")
	if _cap_t > 2.7 and _cap_step == 1:
		_cap_step = 2
		_prepare_preview()
	if _cap_t > 7.4 and _cap_step == 2:
		_cap_step = 3
		_save_png("res://evidence/render-preview-split.png" if _capture_2p
			else "res://evidence/render-preview.png")
		if not _capture_2p:
			game.finish_round()
			_enter_settle()
	if _cap_t > 7.0 and _cap_step == 2 and not _cap_fx:
		_cap_fx = true
		_preview_fx()
	if _cap_t > 5.0 and _cap_step == 2 and not _cap_paused:
		_cap_paused = true
		_toggle_pause()
	if _cap_t > 5.25 and _cap_step == 2 and not _cap_pause_shot:
		_cap_pause_shot = true
		_save_png("res://evidence/render-preview-pause.png")
		_toggle_pause()
	if _cap_t > 9.6 and _cap_step == 3:
		_cap_step = 4
		if not _capture_2p:
			_save_png("res://evidence/render-preview-settlement.png")
	# fps / draw sampling is PLAY only (that is the state the report cares about).
	if mode == MODE_PLAY and _cap_t > 2.0 and _cap_t <= 9.4 and _cap_step >= 2:
		_cap_frames += 1
		var f := float(Engine.get_frames_per_second())
		_cap_fps_sum += f
		_cap_fps_min = minf(_cap_fps_min, f)
		_cap_draw_sum += float(_perf["draw"])
	if _cap_t > 9.9 and not _cap_saved:
		_cap_saved = true
		var avg := _cap_fps_sum / maxf(1.0, float(_cap_frames))
		var draws := _cap_draw_sum / maxf(1.0, float(_cap_frames))
		print("[capture] frames=%d fps_avg=%.1f fps_min=%.1f drawcalls_avg=%.0f last_draw=%d prim=%d" % [
			_cap_frames, avg, _cap_fps_min, draws, _perf["draw"], _perf["prim"]])
		print("[capture] done")
		get_tree().quit(0)


## --capture-flow: walk the real session flow (mode select -> ready -> GO beat ->
## play -> pause -> settle) and save one PNG per screen, plus the play-state
## fps/draw readout.
##
## Ship-evidence names (B2 art fidelity, 1920x1080): `b2-title-1920.png`,
## `b2-play-1920.png`, `b2-play-nosnake-1920.png` (snakes hidden: judges the grid
## and the three restored play-HUD panels with no bodies over them),
## `b2-pause-1920.png`, `b2-settle-1920.png`. The older `flow-0*` names are still
## written at the same moments so old scripts keep working. `--capture2p` walks
## the 2-player branch (two ready cards, split-screen play) and stops after the
## play frame.
func _capture_flow_tick(dt: float) -> void:
	_cap_t += dt
	if _cap_flow_step == 0 and _cap_t > 0.8:
		# The how-to-play card is part of the title screen now, so the flow captures
		# it too (1P only): open it, screenshot, close, then start the round.
		_cap_flow_step = 12
		_save_png("res://evidence/flow-01-mode-select.png")
		if not _capture_2p:
			_save_png("res://evidence/b2-title-1920.png")
			_save_png("res://evidence/ui-select-1024.png")
			_open_help()
	if _cap_flow_step == 12:
		_b1_t += dt
		if _b1_t >= 0.25:
			_b1_t = 0.0
			if not _capture_2p:
				_save_png("res://evidence/help-1920.png")
				help_open = false
				hud.help_open = false
			_cap_flow_step = 1
			_on_mode_selected(2 if _capture_2p else 1)
	if _cap_flow_step == 1 and mode == MODE_READY and float(ready_fill[0]) >= 0.88:
		_cap_flow_step = 2
		_save_png("res://evidence/flow-02-ready-2p.png" if _capture_2p
			else "res://evidence/flow-02-ready.png")
		if not _capture_2p:
			# 1024-alignment evidence: the same frame under the reference's name.
			_save_png("res://evidence/ui-ready-1024.png")
	if _cap_flow_step == 2 and mode == MODE_READY \
			and int(ready_state[0]) == 2 and float(ready_pop[0]) >= 0.26:
		_cap_flow_step = 3
		_save_png("res://evidence/flow-02b-ready-done-2p.png" if _capture_2p
			else "res://evidence/flow-02b-ready-done.png")
	if _cap_flow_step == 3 and mode == MODE_COUNTDOWN and _countdown_t >= 0.45:
		_cap_flow_step = 4
		_save_png("res://evidence/flow-03-go.png")
	if _cap_flow_step == 4 and mode == MODE_PLAY:
		_cap_flow_step = 5
		_cap_play_t = 0.0
		_prepare_preview()
	if _cap_flow_step >= 5 and _cap_flow_step <= 6 and mode == MODE_PLAY:
		_cap_play_t += dt
		_cap_play_frames += 1
		var f := float(Engine.get_frames_per_second())
		_cap_play_fps_sum += f
		_cap_play_fps_min = minf(_cap_play_fps_min, f)
		if _cap_flow_step == 5 and _cap_play_t >= 1.25:
			# Lead the shot by a few frames: clear any AI that drifted into the
			# subject, then let _preview_fx stage the three showcase rivals and
			# the "YUM!" burst (the saved viewport frame is one frame old).
			_cap_flow_step = 6
			if game.player != null and game.player.body.size() > 0:
				_clear_rivals_near(game.player.body[0], 700.0)
			_preview_fx()
		elif _cap_flow_step == 6 and _cap_play_t >= 1.6:
			_cap_flow_step = 7
			_print_visible_skins()
			_save_png("res://evidence/flow-04-play-2p.png" if _capture_2p
				else "res://evidence/flow-04-play.png")
			if not _capture_2p:
				_save_png("res://evidence/b2-play-1920.png")
			var avg := _cap_play_fps_sum / maxf(1.0, float(_cap_play_frames))
			print("[capture] play fps_avg=%.1f fps_min=%.1f draw=%d prim=%d frames=%d players=%d" % [
				avg, _cap_play_fps_min, _perf["draw"], _perf["prim"], _cap_play_frames,
				player_count])
			_b1_t = 0.0
			if _capture_2p:
				# Keep walking into the 2P settlement (new web-parity evidence).
				_cap_flow_step = 20
			else:
				# Arena-only frame: same HUD, snakes hidden (capture tooling only).
				_set_hide_snakes(true)
	# ---- arena-only frame (1P): grid + the three restored panels, no bodies ----
	elif _cap_flow_step == 7:
		_b1_t += dt
		if _b1_t >= 0.2:
			_cap_flow_step = 8
			_b1_t = 0.0
			_save_png("res://evidence/b2-play-nosnake-1920.png")
			_set_hide_snakes(false)
	# ---- pause frame (1P only): the web's `body.pause-open` layer ----
	elif _cap_flow_step == 8:
		_b1_t += dt
		if _b1_t >= 0.3:
			_cap_flow_step = 9
			_b1_t = 0.0
			_toggle_pause("capture")
	elif _cap_flow_step == 9:
		_b1_t += dt
		if _b1_t >= 0.35:
			_cap_flow_step = 10
			_b1_t = 0.0
			_save_png("res://evidence/b2-pause-1920.png")
			if not _capture_2p:
				_save_png("res://evidence/ui-pause-1024.png")
			_toggle_pause("capture")
			# Real end-of-round path, then the settlement stage. The final lengths
			# are staged to a web-reference-like spread so all eight columns fit
			# (capture-only evidence data, see `_stage_settle_showcase`).
			_stage_settle_showcase(1 if not _capture_2p else 2)
			game.finish_round()
			_enter_settle()
			_settle_cap_begin()
	# ---- settlement rise, 1P: mid-rise frame at 0.82 s of the 1.1 s rise ----
	elif _cap_flow_step == 10:
		_b1_t += dt
		if _b1_t >= 0.82:
			_cap_flow_step = 11
			_save_png("res://evidence/settle-webparity-mid-1920.png")
			if stage != null:
				print("[capture] settle mid-rise t=%.2fs lift=%.0fpx settled=%s lanes=%d" % [
					stage.t, stage.lift, str(stage.settled), stage.rows.size()])
			_cap_settle_started = false
	# ---- settlement hold, 1P: final frames + the settle draw/fps readout ----
	elif _cap_flow_step == 11:
		_b1_t += dt
		# Measure only the settled hold (t >= 1.15 s): the one-off glyph/first-draw
		# cost of the title+length type belongs to the transition, not the screen.
		if _b1_t >= 1.15:
			if not _cap_settle_started:
				_cap_settle_started = true
				_settle_cap_begin()
			_cap_settle_sample()
		if _b1_t >= 1.75:
			_cap_flow_step = 13
			_settle_cap_report("1P")
			_save_png("res://evidence/b2-settle-1920.png")
			_save_png("res://evidence/settle-webparity-1920.png")
			print("[capture] flow: mode_select -> ready -> countdown -> play -> pause -> settle")
			print("[capture] done")
			get_tree().quit(0)
	# ---- 2P settlement (new web-parity evidence) ----
	elif _cap_flow_step == 20:
		_b1_t += dt
		if _b1_t >= 0.35:
			_cap_flow_step = 21
			_b1_t = 0.0
			_stage_settle_showcase(2)
			game.finish_round()
			_enter_settle()
			_settle_cap_begin()
	elif _cap_flow_step == 21:
		_b1_t += dt
		if _b1_t >= 1.15:
			if not _cap_settle_started:
				_cap_settle_started = true
				_settle_cap_begin()
			_cap_settle_sample()
		if _b1_t >= 1.75:
			_cap_flow_step = 22
			_settle_cap_report("2P")
			_save_png("res://evidence/settle-webparity-2p.png")
			print("[capture] flow: mode_select -> ready -> countdown -> play -> settle (2P)")
			print("[capture] done")
			get_tree().quit(0)


## --capture-flow only: stage a final length spread close to the web reference
## (24 / 21 / 21 / 19 / 19 / 18 / 18 / 16 from its ~4 s round). With a real
## 2-minute spread (e.g. 67 vs 17) the web's own 1.55-screen winner law pushes
## the short columns off the bottom of the frame — that is the shipped behaviour,
## but it makes the parity crop unreadable. This is evidence data, not a rule
## change: normal rounds settle with the real `body.size()`. It also pins a
## historical best above the round peak so the 最长 / 历史最长 split is visible.
func _stage_settle_showcase(players: int) -> void:
	if game == null or game.snakes.is_empty():
		return
	var want := [24, 21, 21, 19, 19, 18, 18, 16]
	if players >= 2:
		# 2P: both humans in the top two, no ties, so both ranks are predictable.
		want = [24, 21, 20, 19, 18, 17, 16, 15]
	var i := 0
	for s in game.snakes:
		var n: int = int(want[mini(i, want.size() - 1)])
		var col := float(i % 4) - 1.5
		var row := float(i / 4) - 0.5
		s.alive = true
		s.reset(cfg.world.w * 0.5 + 420.0 * col, cfg.world.h * 0.5 + 360.0 * row, 0.0, n)
		s.kills = 0
		s.deaths = 0
		s.peak_length = n
		s.food_eaten = maxi(0, n - int(cfg.snake.start_segments))
		i += 1
	game.best_length = 31
	print("[capture] settle showcase: lengths=%s best=%d (staged evidence data)" % [
		str(want), int(game.best_length)])


## Settlement performance window (evidence only; the gate measures PLAY).
func _settle_cap_begin() -> void:
	_cap_settle_frames = 0
	_cap_settle_fps_sum = 0.0
	_cap_settle_fps_min = 999.0
	_cap_settle_draw_sum = 0.0
	_cap_settle_prim = 0
	_cap_settle_last_usec = 0
	_cap_settle_ms_sum = 0.0
	_cap_settle_ms_max = 0.0


func _cap_settle_sample() -> void:
	var now := Time.get_ticks_usec()
	if _cap_settle_last_usec > 0:
		var ms := float(now - _cap_settle_last_usec) / 1000.0
		_cap_settle_frames += 1
		_cap_settle_ms_sum += ms
		_cap_settle_ms_max = maxf(_cap_settle_ms_max, ms)
		_cap_settle_fps_sum += 1000.0 / maxf(0.001, ms)
		_cap_settle_fps_min = minf(_cap_settle_fps_min, 1000.0 / maxf(0.001, ms))
		_cap_settle_draw_sum += float(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_cap_settle_prim = int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_cap_settle_last_usec = now


func _settle_cap_report(tag: String) -> void:
	var n := maxf(1.0, float(_cap_settle_frames))
	var avg_ms := _cap_settle_ms_sum / n
	print("[capture] settle %s fps_avg=%.1f fps_min=%.1f ms_avg=%.2f ms_max=%.2f draw_avg=%.1f draw_last=%d prim=%d frames=%d lift=%.0fpx lanes=%d" % [
		tag, _cap_settle_fps_sum / n, _cap_settle_fps_min, avg_ms, _cap_settle_ms_max,
		_cap_settle_draw_sum / n,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		_cap_settle_prim, _cap_settle_frames,
		stage.lift if stage != null else 0.0, stage.rows.size() if stage != null else 0])


## --capture-shake: the before/after evidence for the screen-shake retune. Runs a
## fixed 60 fps scripted sequence through the REAL presentation router
## (`game.events` push -> `_drain_events()`), samples the camera offset once per
## frame and prints it in px, so "the shake is 1/3 as strong" is a number, not a
## claim. The rules are parked in STATE_COUNTDOWN with a huge timer, exactly like
## `--capture-overlap`: nothing eats, dies or spawns on its own, so the only
## impulse in each window is the scripted one, and the run is reproducible.
const SHAKE_SEQ := [
	[0.30, "eat-pellet"],
	[1.20, "eat-big"],
	[2.10, "kill"],
	[3.00, "death"],
	[4.00, "stack"],
	[5.20, "end"],
]


func _capture_shake_tick(dt: float) -> void:
	_shake_t += dt
	if _shake_step == 0 and _shake_t > 0.4:
		_shake_step = 1
		print("[shake] begin scale=%.3f cap=%.2fpx decay=%.2f/s attack=%.3fs wx=%.1f,%.1f wy=%.1f,%.1f" % [
			fx.shake_scale, PSFx.SHAKE_MAX_PX, PSFx.SHAKE_DECAY, PSFx.SHAKE_ATTACK,
			PSFx.SHAKE_WX1, PSFx.SHAKE_WX2, PSFx.SHAKE_WY1, PSFx.SHAKE_WY2])
		_begin_countdown("shake-probe")
	if _shake_step == 1 and mode == MODE_PLAY:
		_shake_step = 2
		_shake_seq_t = 0.0
		# Park the rules: cameras keep following and `_drain_events()` still runs,
		# but the simulation spawns nothing and no round timer can end the probe.
		game.state = PSGame.STATE_COUNTDOWN
		game.countdown_left = 999.0
		_set_hide_snakes(true)
		_shake_window_open("")
	if _shake_step != 2:
		return
	_shake_seq_t += dt
	while _shake_ev < SHAKE_SEQ.size() and _shake_seq_t >= float(SHAKE_SEQ[_shake_ev][0]):
		var name := String(SHAKE_SEQ[_shake_ev][1])
		_shake_ev += 1
		if name == "end":
			_shake_window_close()
			print("[shake] end max_axis=%.2fpx max_vec=%.2fpx" % [
				_shake_peak_axis, _shake_peak_vec])
			print("[capture] done")
			get_tree().quit(0)
			return
		_shake_window_close()
		_shake_window_open(name)
		_shake_fire(name)
	# ---- one sample per frame: exactly what the world view is handed ----
	if worlds.is_empty():
		return
	var off: Vector2 = (worlds[0].cam - cams[0]) * float(zooms[0])
	var m := maxf(absf(off.x), absf(off.y))
	_shake_frames += 1
	_shake_peak_axis = maxf(_shake_peak_axis, m)
	_shake_peak_vec = maxf(_shake_peak_vec, off.length())
	if m >= 1.0:
		_shake_settle_frame = _shake_frames
	if m > 0.02:
		print("[shake] f=%d t=%.3f a=%.3f x=%.2f y=%.2f m=%.2f" % [
			_shake_frames, _shake_seq_t, fx.shake, off.x, off.y, m])


## Open a measurement window: reset the per-event peak/settle accumulators.
func _shake_window_open(name: String) -> void:
	_shake_frames = 0
	_shake_peak_axis = 0.0
	_shake_peak_vec = 0.0
	_shake_settle_frame = -1
	_shake_win_name = name
	if name != "":
		print("[shake] event name=%s t=%.3f" % [name, _shake_seq_t])


## Close it: one line with the peak axis offset, the peak vector length and the
## last frame that was still >= 1 px (the decay time).
func _shake_window_close() -> void:
	if _shake_frames <= 0:
		return
	print("[shake] peak name=%s frames=%d peak_axis=%.2fpx peak_vec=%.2fpx last_ge_1px_frame=%d decay_ms=%d" % [
		_shake_win_name, _shake_frames, _shake_peak_axis, _shake_peak_vec,
		_shake_settle_frame, int(round(1000.0 * float(_shake_settle_frame) / 60.0))])


func _shake_cur_name() -> String:
	return _shake_win_name


## Push the real cosmetic events for one scripted moment and drain them through
## the shipped router. `eat-pellet` is the "trivial event" the owner complained
## about; `stack` fires a kill AND a player death in the same frame (the case the
## old 26 px cap let compound).
func _shake_fire(name: String) -> void:
	var c := Vector2(2400.0, 1350.0)
	var p = game.player
	if p != null and p.body.size() > 0:
		c = p.body[0]
	var q = game.events
	match name:
		"eat-pellet":
			q.push_food(c.x + 60.0, c.y, Color("FFD93D"), false, 24.0, true, 0)
		"eat-big":
			q.push_food(c.x - 60.0, c.y + 40.0, Color("FF7A59"), true, 44.0, true, 0)
		"kill":
			q.push_death(c.x + 420.0, c.y - 200.0, Color("8CFF9E"), false, true, 1,
				_shake_corpse(c + Vector2(420.0, -200.0)))
		"death":
			q.push_death(c.x, c.y, Color("FF5C7A"), true, false, 0, _shake_corpse(c))
		"stack":
			q.push_death(c.x + 420.0, c.y - 200.0, Color("8CFF9E"), false, true, 1,
				_shake_corpse(c + Vector2(420.0, -200.0)))
			q.push_death(c.x, c.y, Color("FF5C7A"), true, false, 0, _shake_corpse(c))
	_drain_events()


func _shake_corpse(centre: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(centre + Vector2(float(i) * 14.0 - 168.0, sin(float(i) * 0.6) * 26.0))
	return pts


## --capture-cam: the camera-stability evidence. A 1.5 s straight run at the
## scripted heading, then three sharp turns (90 deg, 180 deg, 90 deg back) and a
## settle tail. One line per frame with the follow centre, the per-frame step,
## the speed and the head's screen offset, plus one summary per leg.
func _capture_cam_tick(dt: float) -> void:
	_cam_cap_t += dt
	if _cam_cap_step == 0 and _cam_cap_t > 0.5:
		_cam_cap_step = 1
		print("[cam] begin follow=%.1f lookahead_max=%.0f la_tau=%.2f speed_extra=%.0f accel=%.0f" % [
			cfg.camera.follow, cfg.camera.lookahead_max, CAM_LA_TAU, CAM_SPEED_EXTRA,
			CAM_ACCEL])
		_begin_countdown("cam-probe")
	if _cam_cap_step == 1 and mode == MODE_PLAY:
		_cam_cap_step = 2
		_cam_cap_t = 0.0
		_cam_cap_place()
		_cam_cap_open_leg()
	if _cam_cap_step != 2:
		return
	# ---- advance the heading script (takes effect on the next frame) ----
	if _cam_cap_leg + 1 < CAM_SEQ.size() \
			and _cam_cap_t >= float(CAM_SEQ[_cam_cap_leg + 1][0]):
		_cam_cap_close_leg()
		_cam_cap_leg += 1
		_cam_script_angle = float(CAM_SEQ[_cam_cap_leg][1])
		_cam_cap_open_leg()
	if _cam_cap_t >= CAM_SEQ_END:
		_cam_cap_close_leg()
		print("[cam] end legs=%d max_step=%.2fpx" % [CAM_SEQ.size(), _cam_cap_max_step])
		print("[capture] done")
		get_tree().quit(0)
		return
	# ---- one sample per frame ----
	var cam: Vector2 = cams[0]
	var step: float = cam.distance_to(_cam_cap_prev)
	var v: float = step / maxf(0.0001, dt)
	_cam_cap_prev = cam
	var head_off := Vector2.ZERO
	if game.player != null and game.player.body.size() > 0:
		head_off = (game.player.body[0] - cam) * float(zooms[0])
	_cam_cap_leg_max_step = maxf(_cam_cap_leg_max_step, step)
	_cam_cap_max_step = maxf(_cam_cap_max_step, step)
	_cam_cap_leg_peak_v = maxf(_cam_cap_leg_peak_v, v)
	_cam_cap_leg_head_max = maxf(_cam_cap_leg_head_max, absf(head_off.x))
	print("[cam] f=%d t=%.3f leg=%s x=%.2f y=%.2f step=%.2f v=%.1f head=%.1f,%.1f" % [
		int(round(_cam_cap_t * 60.0)), _cam_cap_t, String(CAM_SEQ[_cam_cap_leg][2]),
		cam.x, cam.y, step, v, head_off.x, head_off.y])


func _cam_cap_open_leg() -> void:
	_cam_cap_leg_max_step = 0.0
	_cam_cap_leg_peak_v = 0.0
	_cam_cap_leg_head_max = 0.0
	print("[cam] leg name=%s t=%.3f angle=%.1fdeg" % [
		String(CAM_SEQ[_cam_cap_leg][2]), _cam_cap_t,
		rad_to_deg(float(CAM_SEQ[_cam_cap_leg][1]))])


func _cam_cap_close_leg() -> void:
	print("[cam] leg_end name=%s max_step=%.2fpx peak_v=%.1fpx/s head_x_max=%.1fpx" % [
		String(CAM_SEQ[_cam_cap_leg][2]), _cam_cap_leg_max_step, _cam_cap_leg_peak_v,
		_cam_cap_leg_head_max])


## Stage the probe: one human at the world centre, heading +X, nothing else on
## the map (no AI to collide with, no food to eat, no powerup buffs), the camera
## snapped to the same frame so the measurement starts from a steady state.
func _cam_cap_place() -> void:
	var p = game.player
	if p == null:
		return
	p.reset(2400.0, 1350.0, 0.0, 40)
	p.immune_until = game.time + 9999.0
	var i := 1
	while i < game.snakes.size():
		var s = game.snakes[i]
		s.alive = false
		s.body.resize(0)
		s.pulse.resize(0)
		s.respawn_timer = 9999.0
		i += 1
	game.foods.resize(0)
	game.powerups.resize(0)
	_snap_cameras()
	_cam_cap_prev = cams[0]
	_cam_scripted = true
	_cam_script_angle = 0.0


## --capture-cam-boost: the acceleration evidence.
##
## Script: 1.0 s straight at normal speed -> the REAL boost buff (1.65x) plus the
## pose wrist-speed ceiling (1.80x) switch on at t=1.0 and stay on until t=5.5
## (4.5 s, well past the required 3 s) -> 90/180/90 degree turns at t=2.5/3.5/4.5
## at that speed -> boost off, then a 2 s settle. The AI, food and powerups are
## removed; the only motion is the scripted heading + the boost.
##
## One line per frame: `snake=` the measured snake speed (p.speed, which already
## includes boost x slowdown x pose speed), `cam=` the measured follow-centre
## speed, `off=` the head's screen offset from the camera centre, `off_pct=` the
## largest axis offset as a percentage of the safe box, `inside=` whether the head
## is inside the drawn arena rect (the visible playfield), `arena=` whether it is
## inside the world rectangle, `clamp=` the arena clamp is what is holding the
## head off-centre, `catch=` the catch-up term is active, `cap_v/cap_a=` the caps
## the law actually used this frame.
func _capture_cam_boost_tick(dt: float) -> void:
	_cam_boost_t += dt
	if _cam_boost_step == 0 and _cam_boost_t > 0.5:
		_cam_boost_step = 1
		print(("[cam-boost] begin follow=%.1f base_speed=%.0f base_vmax=%.0f " +
			"base_amax=%.0f la_max=%.0f safe_frac=%.2f catch_t=%.2f " +
			"boost=%.2f..%.2fs pose_speed_max=%.2f") % [
			cfg.camera.follow, cfg.snake.base_speed,
			cfg.snake.base_speed + CAM_SPEED_EXTRA, CAM_ACCEL, CAM_LA_MAX,
			CAM_SAFE_FRAC, CAM_CATCH_T, CAM_BOOST_ON, CAM_BOOST_OFF,
			cfg.pose.speed.max_limit])
		_begin_countdown("cam-boost")
	if _cam_boost_step == 1 and mode == MODE_PLAY:
		_cam_boost_step = 2
		_cam_boost_t = 0.0
		_cam_boost_place()
		_cam_boost_open_leg()
		return
	if _cam_boost_step != 2:
		return
	# ---- boost window: real buff + the wrist-speed ceiling (applies next frame) --
	var p = game.player
	if p != null:
		if _cam_boost_t >= CAM_BOOST_ON and _cam_boost_t < CAM_BOOST_OFF:
			p.buffs[0] = 999.0
			_cam_boost_hold = true
		else:
			_cam_boost_hold = false
			if _cam_boost_t >= CAM_BOOST_OFF:
				p.buffs[0] = 0.0
	# ---- advance the heading script (takes effect on the next frame) ----
	if _cam_boost_leg + 1 < CAM_BOOST_SEQ.size() \
			and _cam_boost_t >= float(CAM_BOOST_SEQ[_cam_boost_leg + 1][0]):
		_cam_boost_close_leg()
		_cam_boost_leg += 1
		_cam_script_angle = float(CAM_BOOST_SEQ[_cam_boost_leg][1])
		_cam_boost_open_leg()
	if _cam_boost_t >= CAM_BOOST_END:
		_cam_boost_close_leg()
		_cam_boost_report()
		print("[capture] done")
		get_tree().quit(0)
		return
	# ---- one sample per frame ----
	var cam: Vector2 = cams[0]
	var step: float = cam.distance_to(_cam_boost_prev)
	_cam_boost_prev = cam
	var cam_v: float = step / maxf(0.0001, dt)
	var head := Vector2.ZERO
	if p != null and p.body.size() > 0:
		head = p.body[0]
	var off: Vector2 = _cam_dbg_off
	var safe: Vector2 = _cam_dbg_safe
	var half: Vector2 = spans[0] * 0.5 * float(zooms[0])
	var inside := absf(off.x) <= half.x and absf(off.y) <= half.y
	var in_world: bool = head.x >= 0.0 and head.x <= cfg.world.w \
		and head.y >= 0.0 and head.y <= cfg.world.h
	var off_len: float = off.length()
	var off_pct: float = 0.0
	if safe.x > 0.0 and safe.y > 0.0:
		off_pct = maxf(absf(off.x) / safe.x, absf(off.y) / safe.y) * 100.0
	# Distance from the head centre to the nearest drawn edge, and the same with
	# the drawn head disc (`PSWorldView` uses radius * 1.38 * zoom) subtracted.
	var edge: float = minf(half.x - absf(off.x), half.y - absf(off.y))
	var head_r := 0.0
	if p != null and p.alive:
		head_r = p.radius() * 1.38 * float(zooms[0])
	var head_edge: float = edge - head_r
	# ---- global + per-leg accumulation ----
	_cam_boost_frames += 1
	_cam_boost_leg_frames += 1
	_cam_boost_leg_max_step = maxf(_cam_boost_leg_max_step, step)
	_cam_boost_leg_peak_v = maxf(_cam_boost_leg_peak_v, cam_v)
	_cam_boost_leg_max_off = maxf(_cam_boost_leg_max_off, off_len)
	_cam_boost_leg_max_off_x = maxf(_cam_boost_leg_max_off_x, absf(off.x))
	_cam_boost_leg_max_off_y = maxf(_cam_boost_leg_max_off_y, absf(off.y))
	_cam_boost_leg_max_pct = maxf(_cam_boost_leg_max_pct, off_pct)
	_cam_boost_leg_snake_max = maxf(_cam_boost_leg_snake_max, _cam_dbg_speed)
	if not inside:
		_cam_boost_leg_out += 1
		_cam_boost_out_frames += 1
	if _cam_dbg_clamp:
		_cam_boost_leg_clamp += 1
		_cam_boost_clamp_frames += 1
		_cam_boost_leg_clamp_max_off = maxf(_cam_boost_leg_clamp_max_off, off_len)
		_cam_boost_leg_clamp_max_pct = maxf(_cam_boost_leg_clamp_max_pct, off_pct)
		_cam_boost_clamp_max_off = maxf(_cam_boost_clamp_max_off, off_len)
		_cam_boost_clamp_max_pct = maxf(_cam_boost_clamp_max_pct, off_pct)
		if not inside:
			_cam_boost_clamp_out_frames += 1
	if _cam_dbg_catch:
		_cam_boost_leg_catch += 1
		_cam_boost_catch_frames += 1
	_cam_boost_max_off = maxf(_cam_boost_max_off, off_len)
	_cam_boost_max_off_x = maxf(_cam_boost_max_off_x, absf(off.x))
	_cam_boost_max_off_y = maxf(_cam_boost_max_off_y, absf(off.y))
	_cam_boost_max_pct = maxf(_cam_boost_max_pct, off_pct)
	_cam_boost_peak_v = maxf(_cam_boost_peak_v, cam_v)
	_cam_boost_max_step = maxf(_cam_boost_max_step, step)
	_cam_boost_snake_max = maxf(_cam_boost_snake_max, _cam_dbg_speed)
	_cam_boost_vmax_max = maxf(_cam_boost_vmax_max, _cam_dbg_vmax)
	_cam_boost_amax_max = maxf(_cam_boost_amax_max, _cam_dbg_amax)
	_cam_boost_vmax_base_max = maxf(_cam_boost_vmax_base_max, _cam_dbg_vmax_base)
	_cam_boost_amax_base_max = maxf(_cam_boost_amax_base_max, _cam_dbg_amax_base)
	_cam_boost_min_edge = minf(_cam_boost_min_edge, edge)
	_cam_boost_min_head_edge = minf(_cam_boost_min_head_edge, head_edge)
	# ---- two frames of visual evidence (shot1 after the first boost 90, shot2
	# at the worst moment of the 180) ----
	if not _cam_boost_shot1 and _cam_boost_t >= CAM_BOOST_SHOT1:
		_cam_boost_shot1 = true
		_save_png("res://evidence/cam-boost-%s-turn.png" % _cam_boost_tag)
	if not _cam_boost_shot2 and _cam_boost_t >= CAM_BOOST_SHOT2:
		_cam_boost_shot2 = true
		_save_png("res://evidence/cam-boost-%s-uturn.png" % _cam_boost_tag)
	print(("[cam-boost] f=%d t=%.3f leg=%s snake=%.1f cam=%.1f off=%.1f,%.1f " +
		"off_pct=%.0f%% edge=%.1f inside=%d arena=%d clamp=%d catch=%d " +
		"cap_v=%.0f cap_a=%.0f") % [
		int(round(_cam_boost_t * 60.0)), _cam_boost_t,
		String(CAM_BOOST_SEQ[_cam_boost_leg][2]), _cam_dbg_speed, cam_v,
		off.x, off.y, off_pct, edge, 1 if inside else 0, 1 if in_world else 0,
		1 if _cam_dbg_clamp else 0, 1 if _cam_dbg_catch else 0,
		_cam_dbg_vmax, _cam_dbg_amax])


func _cam_boost_open_leg() -> void:
	_cam_boost_leg_frames = 0
	_cam_boost_leg_max_step = 0.0
	_cam_boost_leg_peak_v = 0.0
	_cam_boost_leg_max_off = 0.0
	_cam_boost_leg_max_off_x = 0.0
	_cam_boost_leg_max_off_y = 0.0
	_cam_boost_leg_max_pct = 0.0
	_cam_boost_leg_out = 0
	_cam_boost_leg_clamp = 0
	_cam_boost_leg_catch = 0
	_cam_boost_leg_snake_max = 0.0
	_cam_boost_leg_clamp_max_off = 0.0
	_cam_boost_leg_clamp_max_pct = 0.0
	print("[cam-boost] leg name=%s t=%.3f angle=%.1fdeg boost=%d" % [
		String(CAM_BOOST_SEQ[_cam_boost_leg][2]), _cam_boost_t,
		rad_to_deg(float(CAM_BOOST_SEQ[_cam_boost_leg][1])),
		1 if _cam_boost_hold else 0])


func _cam_boost_close_leg() -> void:
	print(("[cam-boost] leg_end name=%s frames=%d snake_max=%.1f max_off=%.1fpx " +
		"(x=%.1f,y=%.1f) off_pct=%.0f%% max_step=%.2fpx peak_cam=%.1fpx/s " +
		"out=%d clamp=%d catch=%d") % [
		String(CAM_BOOST_SEQ[_cam_boost_leg][2]), _cam_boost_leg_frames,
		_cam_boost_leg_snake_max, _cam_boost_leg_max_off,
		_cam_boost_leg_max_off_x, _cam_boost_leg_max_off_y,
		_cam_boost_leg_max_pct, _cam_boost_leg_max_step,
		_cam_boost_leg_peak_v, _cam_boost_leg_out, _cam_boost_leg_clamp,
		_cam_boost_leg_catch])
	if _cam_boost_leg_clamp > 0:
		print(("[cam-boost] leg_clamp name=%s frames=%d max_off=%.1fpx (%.0f%% " +
			"of safe box) - reported, the arena clamp is the only fix") % [
			String(CAM_BOOST_SEQ[_cam_boost_leg][2]), _cam_boost_leg_clamp,
			_cam_boost_leg_clamp_max_off, _cam_boost_leg_clamp_max_pct])


## The before/after numbers: max head offset (px + % of the safe box), frames
## outside the drawn arena rect (must be 0 after the fix), peak camera speed and
## max single-frame step, and the caps the adaptive law ended up using.
func _cam_boost_report() -> void:
	print(("[cam-boost] end frames=%d max_off=%.1fpx (x=%.1f,y=%.1f) " +
		"max_off_pct=%.0f%% frames_outside=%d clamp_frames=%d catch_frames=%d " +
		"snake_max=%.1f peak_cam=%.1fpx/s max_step=%.2fpx min_edge=%.1fpx " +
		"min_head_edge=%.1fpx") % [
		_cam_boost_frames, _cam_boost_max_off, _cam_boost_max_off_x,
		_cam_boost_max_off_y, _cam_boost_max_pct, _cam_boost_out_frames,
		_cam_boost_clamp_frames, _cam_boost_catch_frames, _cam_boost_snake_max,
		_cam_boost_peak_v, _cam_boost_max_step, _cam_boost_min_edge,
		_cam_boost_min_head_edge])
	print(("[cam-boost] result max_off_px=%.1f max_off_pct=%.1f out_frames=%d " +
		"peak_cam=%.1f max_step=%.2f snake_max=%.1f cap_v=%.1f cap_a=%.1f " +
		"cap_v_eff=%.1f cap_a_eff=%.1f clamp_frames=%d clamp_out=%d " +
		"clamp_max_off=%.1f clamp_max_pct=%.1f catch_frames=%d " +
		"min_edge=%.1f min_head_edge=%.1f frames=%d") % [
		_cam_boost_max_off, _cam_boost_max_pct, _cam_boost_out_frames,
		_cam_boost_peak_v, _cam_boost_max_step, _cam_boost_snake_max,
		_cam_boost_vmax_base_max, _cam_boost_amax_base_max,
		_cam_boost_vmax_max, _cam_boost_amax_max, _cam_boost_clamp_frames,
		_cam_boost_clamp_out_frames, _cam_boost_clamp_max_off,
		_cam_boost_clamp_max_pct, _cam_boost_catch_frames,
		_cam_boost_min_edge, _cam_boost_min_head_edge, _cam_boost_frames])


## Stage the boost probe: one human near the left of the world centre, heading
## +X, nothing else on the map (no AI to collide with, no food, no pickups), no
## buffs at t=0, the camera snapped so the measurement starts from rest.
func _cam_boost_place() -> void:
	var p = game.player
	if p == null:
		return
	p.reset(CAM_BOOST_START.x, CAM_BOOST_START.y, 0.0, 40)
	p.immune_until = game.time + 9999.0
	p.buffs[0] = 0.0
	p.buffs[1] = 0.0
	p.pose_speed = 1.0
	var i := 1
	while i < game.snakes.size():
		var s = game.snakes[i]
		s.alive = false
		s.body.resize(0)
		s.pulse.resize(0)
		s.respawn_timer = 9999.0
		i += 1
	game.foods.resize(0)
	game.powerups.resize(0)
	# The probe start is deliberately NOT the round's spawn point, so the follow
	# centre has to be re-anchored on the head itself: `game.cam_targets` still
	# holds the spawn point until the next `game.update()`.
	_snap_cameras()
	cams[0] = p.body[0]
	_cam_seed(0, p)
	_cam_boost_prev = cams[0]
	_cam_scripted = true
	_cam_script_angle = 0.0
	_cam_boost_hold = false
	_cam_boost_frames = 0
	_cam_boost_max_off = 0.0
	_cam_boost_max_off_x = 0.0
	_cam_boost_max_off_y = 0.0
	_cam_boost_max_pct = 0.0
	_cam_boost_out_frames = 0
	_cam_boost_clamp_frames = 0
	_cam_boost_clamp_out_frames = 0
	_cam_boost_clamp_max_off = 0.0
	_cam_boost_clamp_max_pct = 0.0
	_cam_boost_catch_frames = 0
	_cam_boost_peak_v = 0.0
	_cam_boost_max_step = 0.0
	_cam_boost_snake_max = 0.0
	_cam_boost_vmax_max = 0.0
	_cam_boost_amax_max = 0.0
	_cam_boost_vmax_base_max = 0.0
	_cam_boost_amax_base_max = 0.0
	_cam_boost_min_edge = 1.0e18
	_cam_boost_min_head_edge = 1.0e18
	_cam_boost_shot1 = false
	_cam_boost_shot2 = false


## --capture-perf: the always-on panel's own evidence. Parks a real 1080p play
## frame (showcase food/powerups/rivals, nothing moving), measures draw calls and
## primitives with the panel ON and OFF - the only difference between the two
## passes is `hud.perf_on` - then saves `evidence/perf-overlay-1920.png` with the
## panel up and prints the delta.
# ------------------------------------------------------- pose steering trace
#
# `--capture-pose-trace` answers the owner's pose complaints with numbers instead
# of adjectives. A scripted hand path is pushed through the **real** input chain
# (`PSPoseInput.ingest_test_skeleton` -> `_process_slot` -> `PSPoseSteer`) and the
# **real** turn law (`PSSnake.update`), and one line per simulated frame is
# written to `evidence/pose-trace-<tag>.txt`:
#
#   dist_n, the PUBLISHED speed multiplier and the real snake speed in px/s, raw
#   wrist, filtered wrist, raw angle, filtered angle, dead-zone state, auto-picked
#   arm, steering reference, snake heading - plus a second snake driven by the
#   IDEAL angle (no mapper at all) as the "what would the turn rate alone do"
#   reference.
#
# Since 2026-11-14 the hand is scripted **relative to the RIGHT SHOULDER** and the
# ideal angle is the shoulder->wrist direction, i.e. exactly the vector the owner
# asked for (手胸连点 -> 右手与右肩连点). The scripted gestures are the ones the
# owner named: hand at the chest, arm forward, arm sideways, arm raised, slow
# sweep - each leg's `dist_n = |wrist - ref| / torso` distribution is printed, and
# that is what the dead zone in `cfg.pose` is calibrated from. Since 2026-11-17 the
# per-leg summary also prints the speed curve's OUTPUT (`spd` = the multiplier the
# player feels, and `px/s` = the real `PSSnake.speed`), because that is what the
# 极限速度 pass calibrates `cfg.pose.speed.near/far` from.
#
# `--pose-ref=chest` replays the PREVIOUS pass: it only writes the old numbers into
# `cfg.pose` (chest origin, dead zone 0.12/1.35, speed 0.30..0.75) - same code,
# same gestures - so `before` and `after` differ in the reference point alone.
# `--pose-law=before` still re-runs the pre-fix law (no filters, dead zone 0.05,
# arm hysteresis 1.15, no dwell) for the older notes.
#
# The simulation runs on a FIXED 1/60 s step (not wall clock), so the files are
# reproducible on any machine and the latencies are exact frame counts.

const PTRACE_DT := 1.0 / 60.0
const PTRACE_IMG_W := 1920.0
const PTRACE_IMG_H := 1080.0
## Fixed standing body, normalised provider space (device-like proportions).
const PTRACE_LSHO := Vector2(0.430, 0.300)
const PTRACE_RSHO := Vector2(0.570, 0.300)
const PTRACE_LHIP := Vector2(0.455, 0.560)
const PTRACE_RHIP := Vector2(0.545, 0.560)
## Per-frame keypoint jitter, in POSE-IMAGE px (2% of the 281 px torso). This is
## the noise every skeleton tracker has; it is what the mapper has to reject.
const PTRACE_NOISE_PX := 6.0
## The deliberate press down-and-OUTWARD gesture the owner asked to keep:
## dy_n = 0.75 with abs(dx_n) = 0.75 * |wrist - shoulder|, i.e. 48.6 deg out of
## vertical - clearly OUTSIDE the `pose.hang_align` cone (26.7 deg), so it steers.
## angle = 90 - asin(0.75) = 41.41 deg, dist = 0.75 / sin(angle) = 1.1339 torso.
const PTRACE_DOWN_OUT_ANGLE := 0.7227342478134157
const PTRACE_DOWN_OUT_DIST := 1.1338934190276817
## `hang_side`: PI/2 - asin(0.30) = 72.54 deg = 17.46 deg out of vertical, i.e.
## abs(dx_n) = 0.30 of the vector - INSIDE the 26.7 deg cone, so it must hold.
const PTRACE_HANG_SIDE_ANGLE := 1.2661036727794992
## [name, seconds, kind, p0, p1, dist, alt]
##   `dist` = |wrist - RIGHT SHOULDER| in TORSO lengths (the geometry of the
##   gesture; only kind 6 ignores it because the wrist sits on the chest).
##   `alt`  = the LEFT hand's angle for the two-hand proof leg (NAN = the left arm
##   just hangs at the side, which is what it does in every steering gesture).
##   kind 0 = static right arm at p0
##   kind 1 = hold p0 for 0.35 s, then step to p1 (the latency leg)
##   kind 2 = triangular sweep p0 -> p1 -> p0
##   kind 3 = full circle over the leg (p1 = total sweep, PI or TAU)
##   kind 4 = two-hand proof: right at p0, left at `alt` and FURTHER from the chest
##            (the old auto-pick deliberately picks the left arm here)
##   kind 6 = right wrist exactly ON the old chest point (the (a) hold gesture)
##   kind 7 = EXTEND ramp: distance `dist` -> p1 at angle p0. This measures the
##            RELEASE radius: the dist_n of the first un-held frame.
##   kind 8 = RETURN ramp: distance `dist` -> the chest point at angle p0. This
##            measures the RE-HOLD radius: the dist_n at which the gate closes.
##   kind 9 = ARM-HANGING probe (2026-11-14, owner option B 下垂识别): a static
##            wrist `dist` below the shoulder at angle p0, expected to be HELD.
##   kind 11 = the MEASURED step (like kind 1) - moved to the down-and-outward
##            target because a straight-down step is now a hanging arm and is
##            held; only kind 11 fills the step/latency metrics.
##   kind 12 = SWEEP (owner: 手快速从最左边移动到最右边时蛇没有转头). The wrist
##            travels a straight line in GAME space from (-dist, p0) to
##            (+dist, p1) relative to the RIGHT SHOULDER, over `alt` seconds,
##            starting at PTRACE_METRIC_SETTLE. `p0` / `p1` are torso offsets in y
##            (negative = above the shoulder), `dist` is the half-span. A straight
##            line is what the owner's hand actually does: it crosses the dead zone
##            (chest / overhead height) and the hanging cone (belly height) in the
##            MIDDLE of the sweep, which is exactly where the position-only holds
##            used to freeze the angle.
const PTRACE_LEGS := [
	["hand_at_chest", 2.00, 6, 0.0, 0.0, 0.0, NAN],
	["arm_extend", 1.80, 7, 0.0, 0.95, 0.60, NAN],
	["arm_return", 1.80, 8, 0.0, 0.0, 1.15, NAN],
	["arm_forward", 1.60, 0, -0.20, 0.0, 0.90, NAN],
	["arm_sideways", 1.60, 0, 0.0, 0.0, 1.15, NAN],
	["arm_raised", 1.60, 0, -PI * 0.5, 0.0, 0.95, NAN],
	["arm_hanging", 1.60, 0, PI * 0.5, 0.0, 0.98, NAN],
	["sweep_slow", 4.00, 2, -PI * 0.25, PI * 0.25, 0.95, NAN],
	["hold_right", 1.20, 0, 0.0, 0.0, 0.90, NAN],
	["step_to_down", 1.20, 1, 0.0, PI * 0.5, 0.90, NAN],
	["circle", 4.00, 3, 0.0, TAU, 0.95, NAN],
	["two_hand_proof", 2.50, 4, PI * 0.25, PI * 0.25, 0.90, -PI * 0.75],
	# ---- 2026-11-14 hang pass: appended AFTER every existing leg, so the frames
	# (and the shared RNG stream) of the legs above are untouched and the
	# `--pose-hang=off` run is byte-comparable on them. `step_down_out` is first so
	# the step/latency metrics are measured on a target that still steers: the arm
	# starts UP (-90 deg, not hanging, and the snake heading is +45 from the proof
	# leg) and steps to the down-and-out direction, a 131 deg step.
	["step_down_out", 1.80, 11, -PI * 0.5, PTRACE_DOWN_OUT_ANGLE, PTRACE_DOWN_OUT_DIST, NAN],
	# Heading pre-roll: 1.2 s of arm up at 1.0 torso (NOT hanging, dy_n = -1.0)
	# converges the snake to -90 deg, so the hang legs below measure "the heading
	# does not change", not the previous gesture's transient.
	["arm_up_settle", 1.20, 0, -PI * 0.5, 0.0, 1.00, NAN],
	# Gesture 1: arm hanging straight down - dy_n 0.98, dx_n 0.0 -> must HOLD.
	["hang_down", 1.60, 9, PI * 0.5, 0.0, 0.98, NAN],
	# Gesture 2: same, with the wrist 17.46 deg out of vertical (|dx| = 0.30 of the
	# vector, inside the 26.7 deg cone) -> must HOLD.
	["hang_side", 1.60, 9, PTRACE_HANG_SIDE_ANGLE, 0.0, 0.98, NAN],
	# Gesture 3: the deliberate press down-and-OUTWARD (dy 0.75, |dx| = 0.75 of
	# the vector, 48.6 deg out of vertical) -> must STEER down to 41.41 deg.
	["down_out", 1.60, 0, PTRACE_DOWN_OUT_ANGLE, 0.0, PTRACE_DOWN_OUT_DIST, NAN],
	# Gesture 6: slow lower -> raise sweep through the hanging zone (-90 -> +90 ->
	# -90 deg at 0.98 torso, 6 s = 60 deg/s). The hysteresis must flip the state
	# exactly twice: once entering (63.3 deg) and once leaving (56.6 deg).
	["hang_sweep", 6.00, 2, -PI * 0.5, PI * 0.5, 0.98, NAN],
	# ---- 2026-11-14 fast-sweep pass: appended AFTER every existing leg, so the
	# frames (and the shared RNG stream) of the legs above are untouched and the
	# `--pose-motion=off` run is byte-comparable on them.
	#
	# Sweep 1: the owner's literal complaint - a fast left->right sweep at CHEST
	# height, 2.60 torso of travel in 0.35 s (~7.4 torso/s). The wrist crosses
	# straight next to the right shoulder in the middle (dist_n 0.35 < deadzone
	# 0.70), so with position-only holds the angle froze for the whole crossing.
	["sweep_fast_chest", 1.65, 12, 0.345, 0.345, 1.30, 0.35],
	# Sweep 2: the same traverse OVERHEAD (`p0`/`p1` are 0.62 torso above the right
	# shoulder, i.e. over the head), so the crossing passes through the dead zone
	# from the negative-y side and the ideal angle runs -150 -> -29 deg.
	["sweep_fast_overhead", 1.65, 12, -0.62, -0.62, 1.30, 0.35],
	# Sweep 3: the slow reference for the same 2.60 torso chest-height path in
	# 2.10 s (~1.1 torso/s). It must stay SMOOTH (both holds behave as before); it
	# also pins the motion threshold: 1.1 torso/s is below `motion.fast`.
	["sweep_slow_chest", 3.40, 12, 0.345, 0.345, 1.30, 2.10],
	# Sweep 4 (supplementary): a fast sweep at BELLY height (0.80 torso below the
	# shoulder). The middle of this one sits inside the HANGING cone (align 0,
	# dy_n 0.80 >= hang_enter 0.55), i.e. it isolates the hang half of the bug from
	# the dead-zone half.
	["sweep_fast_hang", 1.65, 12, 0.80, 0.80, 1.30, 0.35],
	# Sweep 5: a fast DIAGONAL sweep (below-left -> above-right) that crosses the
	# shoulder's own y level while the wrist is still left of it, i.e. the published
	# angle crosses the +-PI wrap in the middle of the motion.
	["sweep_fast_wrap", 1.65, 12, 0.30, -0.60, 1.30, 0.35],
]
## The step leg's settle window before the jump (frames).
const PTRACE_STEP_SETTLE := 0.35
## Metric settle window: the script TELEPORTS the hand between gestures, and the
## 0.08 s position filter needs ~5 tau to forget the old wrist, so the first 0.40 s
## of every leg measures the transit, not the law. All angle/heading statistics
## below are taken after this window; `dist_n` and the dead-zone rate are raw.
const PTRACE_METRIC_SETTLE := 0.40
## Distance the hanging left arm keeps from the LEFT shoulder (torso lengths).
const PTRACE_LEFT_HANG := 0.95
## Distance the proof leg's left arm keeps from the LEFT shoulder.
const PTRACE_LEFT_PROOF := 1.10

var _ptrace_tag := "after"
var _ptrace_ref_joint := "shoulder_r"
var _ptrace_file_tag := "shoulder-ref"
var _ptrace_snake = null
var _ptrace_ref = null
var _ptrace_ctrl = null
var _ptrace_rng = null
var _ptrace_leg := 0
var _ptrace_leg_t := 0.0
var _ptrace_t := 0.0
var _ptrace_frame := 0
var _ptrace_lines: Array = []
var _ptrace_done := false
var _ptrace_total := 0.0
# Per-leg accumulators (reset when a leg starts).
## Per-leg distribution of `dist_n = |wrist - ref| / torso` (ALL frames: this is
## what the dead zone is calibrated from).
var _ptrace_pt_dnsum := 0.0
var _ptrace_pt_dn2 := 0.0
var _ptrace_pt_hold := 0        # frames the dead zone held the angle
var _ptrace_pt_n := 0
## After `PTRACE_METRIC_SETTLE`: published target angle, signed error vs the
## scripted ideal, signed heading error, and (proof leg) error vs the left hand.
var _ptrace_pt_angsum := 0.0
var _ptrace_pt_ang2 := 0.0
var _ptrace_pt_ang_n := 0
var _ptrace_pt_easum := 0.0
var _ptrace_pt_ea2 := 0.0
var _ptrace_pt_hdgsum := 0.0
var _ptrace_pt_hdg2 := 0.0
var _ptrace_pt_ehsum := 0.0
var _ptrace_pt_eh2 := 0.0
var _ptrace_pt_err_n := 0
var _ptrace_pt_alt_sum := 0.0
var _ptrace_pt_alt2 := 0.0
var _ptrace_pt_alt_n := 0
## After `PTRACE_METRIC_SETTLE`: the speed curve's OUTPUT - the published
## `speed_scale` (what the player feels) and `PSSnake.speed` in px/s (what the
## snake actually moves at, boost/slowdown included). This is what the
## `cfg.pose.speed.near/far` calibration is read from.
var _ptrace_pt_spdsum := 0.0
var _ptrace_pt_spd2 := 0.0
var _ptrace_pt_pxsum := 0.0
var _ptrace_pt_px2 := 0.0
var _ptrace_pt_spd_n := 0
## Per-leg raw wrist-minus-reference geometry (torso units), the numbers the
## arm-hanging gate reads: `dy_n` = wrist below the shoulder, `dx_n` = sideways.
## `hang` is the fraction of frames the gate held; `hflips` the state changes.
var _ptrace_pt_dysum := 0.0
var _ptrace_pt_dy2 := 0.0
var _ptrace_pt_dxsum := 0.0
var _ptrace_pt_dx2 := 0.0
var _ptrace_pt_hang := 0
var _ptrace_pt_hflips := 0
var _ptrace_prev_hang := false
## Snake heading at the first / newest frame of the leg, and the reason string the
## REAL input layer published on the newest frame (`arm-low` while hanging).
var _ptrace_leg_hdg0 := 0.0
var _ptrace_leg_hdg1 := 0.0
var _ptrace_leg_reason := ""
## Auto-pick switches (diagnostic only since steering is right-arm fixed).
var _ptrace_pt_flips := 0
var _ptrace_pt_pick1 := 0
var _ptrace_prev_pick := -1
## Measured hysteresis radii (kind 7 / kind 8): the dist_n at which the gate opens
## while extending, and closes while returning to the chest. -1 = not measured.
var _ptrace_release_dn := -1.0
var _ptrace_rehold_dn := -1.0
var _ptrace_leg_pass_seen := false
var _ptrace_legs_out: Array = []
# Step-response capture (filled by the `kind 1` leg).
var _ptrace_step_t := -1.0
var _ptrace_step_target := 0.0
var _ptrace_step_span := 0.0
var _ptrace_step_m90 := -1.0
var _ptrace_step_s90 := -1.0
var _ptrace_step_r90 := -1.0
var _ptrace_step_over := 0.0
# Sweep capture (kind 12): heading at the traverse start/end, plus how much of the
# traverse the motion override was active for. -1 = the leg is not a sweep.
var _ptrace_sw_t0 := -1.0
var _ptrace_sw_t1 := -1.0
var _ptrace_sw_h0 := 0.0
var _ptrace_sw_h1 := 0.0
var _ptrace_sw_free := 0
var _ptrace_sw_n := 0


func _capture_pose_trace_tick() -> void:
	if _ptrace_done:
		return
	if _ptrace_snake == null:
		_ptrace_init()
	var legs: Array = PTRACE_LEGS
	if _ptrace_leg >= legs.size():
		_ptrace_finish()
		return
	var leg: Array = legs[_ptrace_leg]
	var leg_dur: float = float(leg[1])
	var kind: int = int(leg[2])
	var d_arm: float = float(leg[5])
	var alt: float = float(leg[6])
	# ---- scripted hand for this frame ----
	var kpts: Array = _ptrace_kpts(kind, _ptrace_leg_t, leg_dur, float(leg[3]),
		float(leg[4]), d_arm, alt)
	pose.ingest_test_skeleton(0, kpts, PTRACE_IMG_W, PTRACE_IMG_H, _ptrace_t)
	var steer = pose.steers[0]
	var ideal: float = _ptrace_ideal_angle(kind, _ptrace_leg_t, leg_dur,
		float(leg[3]), float(leg[4]), d_arm, alt)
	# ---- one frame of the REAL turn law, twice ----
	_ptrace_ctrl.set_player(steer.steer_angle_rad, steer.speed_scale)
	_ptrace_snake.update(PTRACE_DT, _ptrace_ctrl, _ptrace_t)
	_ptrace_ctrl.set_player(ideal, 1.0)
	_ptrace_ref.update(PTRACE_DT, _ptrace_ctrl, _ptrace_t)
	# ---- one trace line (provider-space u/v stay readable next to the picture) --
	var m = pose.mappers[0]
	var rw: Vector2 = m.last_raw_wrist
	var fw: Vector2 = m.last_filtered_wrist
	var rf: Vector2 = m.last_filtered_ref
	_ptrace_lines.append(("%d,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,"
		+ "%.1f,%.1f,%d,%d,%s,%.1f,%.1f,%.1f,%s,%.4f,%.4f,%d,%.2f,%.2f,%d,"
		+ "%.3f,%.1f") % [
		_ptrace_frame, _ptrace_t, m.last_dist_n,
		_to_prov_u(rw.x), rw.y / PTRACE_IMG_H,
		_to_prov_u(fw.x), fw.y / PTRACE_IMG_H,
		_to_prov_u(rf.x), rf.y / PTRACE_IMG_H,
		rad_to_deg(m.last_raw_angle), rad_to_deg(steer.steer_angle_rad),
		1 if m.last_deadzone_pass else 0, int(pose.skel_wrist[0]),
		_ptrace_ref_joint,
		rad_to_deg(_ptrace_snake.heading), rad_to_deg(_ptrace_ref.heading),
		rad_to_deg(ideal), String(leg[0]),
		m.last_dy_n, m.last_dx_n, 1 if m.last_hang else 0, steer.confidence,
		m.last_wrist_speed, 1 if m.last_motion_free else 0,
		steer.speed_scale, _ptrace_snake.speed])
	# ---- metrics for this leg ----
	var pub: float = steer.steer_angle_rad
	var dn: float = m.last_dist_n
	_ptrace_pt_dnsum += dn
	_ptrace_pt_dn2 += dn * dn
	_ptrace_pt_dysum += m.last_dy_n
	_ptrace_pt_dy2 += m.last_dy_n * m.last_dy_n
	_ptrace_pt_dxsum += m.last_dx_n
	_ptrace_pt_dx2 += m.last_dx_n * m.last_dx_n
	if m.last_hang:
		_ptrace_pt_hang += 1
	if m.last_hang != _ptrace_prev_hang:
		_ptrace_pt_hflips += 1
	_ptrace_prev_hang = m.last_hang
	if _ptrace_pt_n == 0:
		_ptrace_leg_hdg0 = _ptrace_snake.heading
	_ptrace_leg_hdg1 = _ptrace_snake.heading
	_ptrace_leg_reason = String(pose.diag.get("reason", ""))
	if not m.last_deadzone_pass:
		_ptrace_pt_hold += 1
	else:
		_ptrace_leg_pass_seen = true
	# ---- the gate's two radii, measured on the ramps (kind 7 / kind 8) --------
	if kind == 7 and _ptrace_release_dn < 0.0 and m.last_deadzone_pass \
			and _ptrace_leg_t > PTRACE_DT:
		_ptrace_release_dn = dn
	elif kind == 8 and _ptrace_rehold_dn < 0.0 and not m.last_deadzone_pass \
			and _ptrace_leg_pass_seen:
		_ptrace_rehold_dn = dn
	# Everything below is steady-state: the script teleports the hand between
	# gestures, so the transit frames would measure the position filter's memory
	# of the PREVIOUS gesture instead of this one.
	var held: bool = m.last_hang or not m.last_deadzone_pass
	var settled: bool = _ptrace_leg_t >= PTRACE_METRIC_SETTLE
	if settled:
		_ptrace_pt_angsum += pub
		_ptrace_pt_ang2 += pub * pub
		_ptrace_pt_ang_n += 1
		_ptrace_pt_hdgsum += _ptrace_snake.heading
		_ptrace_pt_hdg2 += _ptrace_snake.heading * _ptrace_snake.heading
		_ptrace_pt_spdsum += steer.speed_scale
		_ptrace_pt_spd2 += steer.speed_scale * steer.speed_scale
		_ptrace_pt_pxsum += _ptrace_snake.speed
		_ptrace_pt_px2 += _ptrace_snake.speed * _ptrace_snake.speed
		_ptrace_pt_spd_n += 1
		if not held:
			var e: float = _wrap_pi(pub - ideal)
			_ptrace_pt_easum += e
			_ptrace_pt_ea2 += e * e
			var eh: float = _wrap_pi(_ptrace_snake.heading - ideal)
			_ptrace_pt_ehsum += eh
			_ptrace_pt_eh2 += eh * eh
			_ptrace_pt_err_n += 1
			if is_finite(alt):
				# The two-hand proof: how far the published angle is from the OTHER
				# hand's direction. A left-arm pick would make this ~0 and the
				# right-hand error ~180 deg. ABSOLUTE value: the two directions are
				# 180 deg apart, i.e. exactly the wrap discontinuity, so a signed
				# mean would cancel out.
				var ea: float = absf(_wrap_pi(pub - alt))
				_ptrace_pt_alt_sum += ea
				_ptrace_pt_alt2 += ea * ea
				_ptrace_pt_alt_n += 1
	var pick: int = int(pose.skel_wrist[0])
	if _ptrace_prev_pick >= 0 and pick >= 0 and pick != _ptrace_prev_pick:
		_ptrace_pt_flips += 1
	if pick == 1:
		_ptrace_pt_pick1 += 1
	_ptrace_prev_pick = pick
	_ptrace_pt_n += 1
	# ---- step response (kind 11 - the measured step; kind 1 is now a hang leg) --
	if kind == 11:
		if _ptrace_step_t < 0.0 and _ptrace_leg_t >= PTRACE_STEP_SETTLE:
			_ptrace_step_t = _ptrace_leg_t
			_ptrace_step_target = float(leg[4])
			_ptrace_step_span = absf(_wrap_pi(_ptrace_step_target - float(leg[3])))
		if _ptrace_step_t >= 0.0 and _ptrace_leg_t >= _ptrace_step_t:
			var span: float = _ptrace_step_span
			var tol: float = span * 0.10
			if _ptrace_step_m90 < 0.0 \
					and absf(_wrap_pi(_ptrace_step_target - pub)) <= tol:
				_ptrace_step_m90 = _ptrace_leg_t - _ptrace_step_t
			if _ptrace_step_s90 < 0.0 \
					and absf(_wrap_pi(_ptrace_step_target - _ptrace_snake.heading)) <= tol:
				_ptrace_step_s90 = _ptrace_leg_t - _ptrace_step_t
			if _ptrace_step_r90 < 0.0 \
					and absf(_wrap_pi(_ptrace_step_target - _ptrace_ref.heading)) <= tol:
				_ptrace_step_r90 = _ptrace_leg_t - _ptrace_step_t
			# Overshoot past the target in the direction of travel.
			var over: float = _wrap_pi(_ptrace_snake.heading - _ptrace_step_target)
			if signf(over) == signf(_wrap_pi(_ptrace_step_target - float(leg[3]))) \
					and absf(over) > _ptrace_step_over:
				_ptrace_step_over = absf(over)
	# ---- sweep metrics (kind 12): heading change over the TRAVERSE window ----
	# The leg-wide `hdg_d` also contains the settle before and the convergence
	# after, so a sweep reports its own window: the 0.35 s where the hand actually
	# travels. That is the number the owner's complaint is about.
	if kind == 12:
		if _ptrace_sw_t0 < 0.0 and _ptrace_leg_t >= PTRACE_METRIC_SETTLE:
			_ptrace_sw_t0 = _ptrace_leg_t
			_ptrace_sw_h0 = _ptrace_snake.heading
		if _ptrace_sw_t1 < 0.0 \
				and _ptrace_leg_t >= PTRACE_METRIC_SETTLE + float(leg[6]):
			_ptrace_sw_t1 = _ptrace_leg_t
			_ptrace_sw_h1 = _ptrace_snake.heading
		if _ptrace_sw_t0 >= 0.0 and _ptrace_sw_t1 < 0.0:
			_ptrace_sw_n += 1
			if m.last_motion_free:
				_ptrace_sw_free += 1
	# ---- advance ----
	_ptrace_t += PTRACE_DT
	_ptrace_frame += 1
	_ptrace_leg_t += PTRACE_DT
	if _ptrace_leg_t >= leg_dur:
		_ptrace_leg_end(leg)
		_ptrace_leg += 1
		_ptrace_leg_t = 0.0
		_ptrace_reset_leg_accum()


func _ptrace_init() -> void:
	_ptrace_lines.append("# pose steering trace (ref=%s law=%s) - fixed 1/60 s simulation"
		% [_ptrace_ref_joint, _ptrace_tag])
	_ptrace_lines.append("# image %dx%d px, torso %s px, keypoint jitter +-%.1f px rms/axis" % [
		int(PTRACE_IMG_W), int(PTRACE_IMG_H), str(_ptrace_torso_px()), PTRACE_NOISE_PX])
	_ptrace_lines.append("# reference: %s -> right wrist; right arm only (layout keys: see console)"
		% [_ptrace_ref_joint])
	_ptrace_lines.append("# law: wrist_smooth=%.3f s angle_smooth=%.3f s deadzone=%.3f exit=%.2fx"
		% [cfg.pose.wrist_smooth, cfg.pose.angle_smooth, cfg.pose.deadzone,
			cfg.pose.deadzone_exit])
	_ptrace_lines.append("#      arm_hysteresis=%.2f dwell=%.2f s speed near=%.2f far=%.2f" % [
		cfg.pose.arm_hysteresis, cfg.pose.arm_min_dwell_sec,
		cfg.pose.speed.near, cfg.pose.speed.far])
	_ptrace_lines.append("#      hang: enter dy_n>=%.2f & |dx|<=%.2f*|W-S|, exit dy_n<%.2f or |dx|>%.2f*|W-S| (%s)" % [
		cfg.pose.hang_enter, cfg.pose.hang_align, cfg.pose.hang_exit,
		cfg.pose.hang_align + PSPoseSteer.HANG_ALIGN_EXIT_MARGIN,
		"ON" if cfg.pose.hang_enter < 1.0 else "OFF (--pose-hang=off)"])
	_ptrace_lines.append(("#      motion: holds suppressed while wrist speed >= %.2f torso/s for %d frames, "
		+ "re-armed below %.2f; estimator lag %.2f s, re-acquire jump %.2f torso (%s)") % [
		cfg.pose.motion.fast, cfg.pose.motion.frames, cfg.pose.motion.slow,
		cfg.pose.motion.smooth, cfg.pose.motion.jump_dist,
		"ON" if cfg.pose.motion.fast < 1.0e8 else "OFF (--pose-motion=off)"])
	_ptrace_lines.append("# frame,t,dist_n,raw_u,raw_v,flt_u,flt_v,ref_u,ref_v,raw_deg," +
		"flt_deg,dz,arm,ref,hdg_deg,hdg_ref_deg,ideal_deg,leg,dy_n,dx_n,hang,conf," +
		"wrist_tps,motion_free,spd,px_s")
	# The curve's two ends in the units the owner feels: base_speed * multiplier.
	_ptrace_lines.append(("#      speed out: near=%.2f -> %.2f (%.0f px/s), far=%.2f -> %.2f "
		+ "(%.0f px/s) at base_speed %.0f; boost x%.2f multiplies on top") % [
		cfg.pose.speed.near, cfg.pose.speed.min,
		cfg.pose.speed.min * cfg.snake.base_speed,
		cfg.pose.speed.far, cfg.pose.speed.max,
		cfg.pose.speed.max * cfg.snake.base_speed, cfg.snake.base_speed,
		cfg.powerups.boost.speed_mul])
	_ptrace_snake = PSSnake.new(cfg, tuning, null)
	_ptrace_snake.reset(2400.0, 1350.0, 0.0, cfg.snake.start_segments)
	_ptrace_snake.is_player = true
	_ptrace_snake.player_index = 0
	_ptrace_ref = PSSnake.new(cfg, tuning, null)
	_ptrace_ref.reset(2400.0, 1350.0, 0.0, cfg.snake.start_segments)
	_ptrace_ref.is_player = true
	_ptrace_ref.player_index = 0
	_ptrace_ctrl = PSSnakeControl.new()
	_ptrace_rng = PSRng.new(20261114)
	_ptrace_reset_leg_accum()
	for leg in PTRACE_LEGS:
		_ptrace_total += float(leg[1])
	print("[pose-trace] ref=%s law=%s frames=%d (%.1f s @60fps) -> evidence/pose-trace-%s.txt" % [
		_ptrace_ref_joint, _ptrace_tag, int(round(_ptrace_total / PTRACE_DT)),
		_ptrace_total, _ptrace_file_tag])
	print(("[pose-trace] ref=%s wrist_smooth=%.3f s angle_smooth=%.3f s "
		+ "deadzone=%.3f exit=%.2fx arm_hyst=%.2f dwell=%.2f s speed=%.2f..%.2f "
		+ "(turn.rate=%.2f rad/s)") % [
		_ptrace_ref_joint,
		cfg.pose.wrist_smooth, cfg.pose.angle_smooth, cfg.pose.deadzone,
		cfg.pose.deadzone_exit, cfg.pose.arm_hysteresis,
		cfg.pose.arm_min_dwell_sec, cfg.pose.speed.near, cfg.pose.speed.far,
		tuning.turn_rate])
	print("[pose-trace] speed curve: near=%.2f -> x%.2f (%.0f px/s) | far=%.2f -> x%.2f (%.0f px/s) | range %.0f..%.0f px/s" % [
		cfg.pose.speed.near, cfg.pose.speed.min,
		cfg.pose.speed.min * cfg.snake.base_speed,
		cfg.pose.speed.far, cfg.pose.speed.max,
		cfg.pose.speed.max * cfg.snake.base_speed,
		cfg.pose.speed.min * cfg.snake.base_speed,
		cfg.pose.speed.max * cfg.snake.base_speed])
	print(("[pose-trace] hang gate: enter dy_n>=%.2f & |dx|<=%.2f*|W-S| (%.1f deg cone) | "
		+ "exit dy_n<%.2f or |dx|>%.2f*|W-S| | %s") % [
		cfg.pose.hang_enter, cfg.pose.hang_align, rad_to_deg(asin(cfg.pose.hang_align)),
		cfg.pose.hang_exit, cfg.pose.hang_align + PSPoseSteer.HANG_ALIGN_EXIT_MARGIN,
		"ON" if cfg.pose.hang_enter < 1.0 else "OFF (--pose-hang=off: pre-rule law)"])


func _ptrace_reset_leg_accum() -> void:
	_ptrace_pt_dnsum = 0.0
	_ptrace_pt_dn2 = 0.0
	_ptrace_pt_hold = 0
	_ptrace_pt_n = 0
	_ptrace_pt_angsum = 0.0
	_ptrace_pt_ang2 = 0.0
	_ptrace_pt_ang_n = 0
	_ptrace_pt_easum = 0.0
	_ptrace_pt_ea2 = 0.0
	_ptrace_pt_hdgsum = 0.0
	_ptrace_pt_hdg2 = 0.0
	_ptrace_pt_ehsum = 0.0
	_ptrace_pt_eh2 = 0.0
	_ptrace_pt_err_n = 0
	_ptrace_pt_alt_sum = 0.0
	_ptrace_pt_alt2 = 0.0
	_ptrace_pt_alt_n = 0
	_ptrace_pt_spdsum = 0.0
	_ptrace_pt_spd2 = 0.0
	_ptrace_pt_pxsum = 0.0
	_ptrace_pt_px2 = 0.0
	_ptrace_pt_spd_n = 0
	_ptrace_pt_flips = 0
	_ptrace_pt_pick1 = 0
	_ptrace_pt_dysum = 0.0
	_ptrace_pt_dy2 = 0.0
	_ptrace_pt_dxsum = 0.0
	_ptrace_pt_dx2 = 0.0
	_ptrace_pt_hang = 0
	_ptrace_pt_hflips = 0
	_ptrace_leg_reason = ""
	_ptrace_leg_pass_seen = false
	_ptrace_sw_t0 = -1.0
	_ptrace_sw_t1 = -1.0
	_ptrace_sw_h0 = 0.0
	_ptrace_sw_h1 = 0.0
	_ptrace_sw_free = 0
	_ptrace_sw_n = 0
	# NOTE: `_ptrace_prev_hang` is deliberately NOT reset - the hang state is
	# carried across legs by the mapper, and a transition on the first frame of a
	# new leg is a real state change that the hysteresis count must include.


## mean / std helper pair for the per-leg accumulators (radians in, degrees out).
func _sd(sum: float, sum2: float, n: int) -> float:
	if n <= 0:
		return 0.0
	var m := sum / float(n)
	return sqrt(maxf(0.0, sum2 / float(n) - m * m))


func _ptrace_leg_end(leg: Array) -> void:
	var n: int = maxi(1, _ptrace_pt_n)
	var mean_dn: float = _ptrace_pt_dnsum / float(n)
	var an: int = _ptrace_pt_ang_n
	var en: int = _ptrace_pt_err_n
	_ptrace_legs_out.append({
		"name": String(leg[0]), "frames": n, "kind": int(leg[2]),
		"dn": mean_dn,
		"dn_sd": _sd(_ptrace_pt_dnsum, _ptrace_pt_dn2, n),
		"dy": _ptrace_pt_dysum / float(n),
		"dy_sd": _sd(_ptrace_pt_dysum, _ptrace_pt_dy2, n),
		"dx": _ptrace_pt_dxsum / float(n),
		"dx_sd": _sd(_ptrace_pt_dxsum, _ptrace_pt_dx2, n),
		"hold": float(_ptrace_pt_hold) / float(n),
		"hang": float(_ptrace_pt_hang) / float(n),
		"hflips": _ptrace_pt_hflips,
		"hdg_d": rad_to_deg(_wrap_pi(_ptrace_leg_hdg1 - _ptrace_leg_hdg0)),
		"reason": _ptrace_leg_reason,
		"ang": rad_to_deg(_ptrace_pt_angsum / float(maxi(1, an))),
		"ang_sd": rad_to_deg(_sd(_ptrace_pt_angsum, _ptrace_pt_ang2, an)),
		"ang_err": rad_to_deg(_ptrace_pt_easum / float(maxi(1, en))),
		"ang_err_sd": rad_to_deg(_sd(_ptrace_pt_easum, _ptrace_pt_ea2, en)),
		"hdg_err": rad_to_deg(_ptrace_pt_ehsum / float(maxi(1, en))),
		"hdg_err_sd": rad_to_deg(_sd(_ptrace_pt_ehsum, _ptrace_pt_eh2, en)),
		"err_n": en, "ang_n": an,
		# speed curve output (settled frames): multiplier the player feels and the
		# real snake px/s (300 * multiplier here: start length, no boost).
		"spd": _ptrace_pt_spdsum / float(maxi(1, _ptrace_pt_spd_n)),
		"spd_sd": _sd(_ptrace_pt_spdsum, _ptrace_pt_spd2, _ptrace_pt_spd_n),
		"px": _ptrace_pt_pxsum / float(maxi(1, _ptrace_pt_spd_n)),
		"px_sd": _sd(_ptrace_pt_pxsum, _ptrace_pt_px2, _ptrace_pt_spd_n),
		"spd_n": _ptrace_pt_spd_n,
		"flips": _ptrace_pt_flips,
		"pick1": float(_ptrace_pt_pick1) / float(n),
		"alt_err": rad_to_deg(_ptrace_pt_alt_sum / float(maxi(1, _ptrace_pt_alt_n))),
		"alt_err_sd": rad_to_deg(_sd(_ptrace_pt_alt_sum, _ptrace_pt_alt2,
			_ptrace_pt_alt_n)),
		"alt_n": _ptrace_pt_alt_n,
		# sweep (kind 12): the traverse window only
		"sw_d": rad_to_deg(_wrap_pi(_ptrace_sw_h1 - _ptrace_sw_h0)) \
			if _ptrace_sw_t1 >= 0.0 else 0.0,
		"sw_trav": float(_ptrace_sw_t1 - _ptrace_sw_t0) if _ptrace_sw_t1 >= 0.0 else 0.0,
		"sw_free": float(_ptrace_sw_free) / float(maxi(1, _ptrace_sw_n)),
		"sw_id0": rad_to_deg(atan2(float(leg[3]), -float(leg[5]))),
		"sw_id1": rad_to_deg(atan2(float(leg[4]), float(leg[5]))),
	})


func _ptrace_finish() -> void:
	_ptrace_done = true
	var path := "res://evidence/pose-trace-%s.txt" % _ptrace_file_tag
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		for line in _ptrace_lines:
			f.store_line(line)
		f.close()
		print("[pose-trace] wrote %s (%d lines)" % [
			ProjectSettings.globalize_path(path), _ptrace_lines.size()])
	else:
		printerr("[pose-trace] could not write %s" % path)
	# ---- summary: this is what the report quotes ----
	print("[pose-trace] layout=%s ref=%s rsho=%d rwri=%d deadzone=%.3f exit=%.2fx (release at %.3f)" % [
		String(pose.diag.get("layout", "?")), _ptrace_ref_joint,
		int(pose._indices()["rsho"]), int(pose._indices()["rwri"]),
		cfg.pose.deadzone, cfg.pose.deadzone_exit,
		cfg.pose.deadzone * cfg.pose.deadzone_exit])
	print("[pose-trace] metric settle %.2f s; errors are signed: published - ideal"
		% PTRACE_METRIC_SETTLE)
	print("[pose-trace] leg                 dn(m+-sd)      dy_n   dx_n dz_h  hang  target(deg m+-sd)  "
		+ "ang_err(m+-sd)  hdg_err(m+-sd)   hdg_d  flip hflip   spd(m+-sd)   px/s")
	for row in _ptrace_legs_out:
		var en: int = int(row["err_n"])
		var ang_s := "%7.2f+-%5.2f" % [float(row["ang"]), float(row["ang_sd"])]
		var ae_s := "%7.2f+-%5.2f" % [float(row["ang_err"]), float(row["ang_err_sd"])]
		var he_s := "%7.2f+-%5.2f" % [float(row["hdg_err"]), float(row["hdg_err_sd"])]
		if en == 0:
			# Fully held leg (dead zone OR arm-hanging): an "error vs the ideal"
			# would be meaningless, the hold rates are the result.
			ae_s = "     n/a (held)"
			he_s = "     n/a (held)"
		var why := String(row["reason"])
		var tail := ("  reason=%s" % why) if why != "" else ""
		# Speed curve output: a HELD leg does not evaluate the curve, it freezes the
		# last target, so its multiplier is inherited from the gesture before it.
		var spd_s := "%6.3f+-%5.3f" % [float(row["spd"]), float(row["spd_sd"])]
		print("[pose-trace] %-19s %6.3f+-%5.3f %6.3f %6.3f %5.2f %5.2f   %s   %s   %s %+7.1f %5d %5d   %s %6.1f%s" % [
			String(row["name"]), float(row["dn"]), float(row["dn_sd"]),
			float(row["dy"]), float(row["dx"]), float(row["hold"]), float(row["hang"]),
			ang_s, ae_s, he_s, float(row["hdg_d"]), int(row["flips"]),
			int(row["hflips"]), spd_s, float(row["px"]), tail])
	# ---- the fast sweeps: what the motion gate is for ----------------------
	# Owner: 手快速从最左边移动到最右边时蛇没有转头. The key number is the heading
	# change over the TRAVERSE window plus the fraction of that window the holds
	# were actually suppressed; the table above still reports the gate state itself.
	for row in _ptrace_legs_out:
		if int(row["kind"]) != 12:
			continue
		var trav: float = float(row["sw_trav"])
		var swd: float = float(row["sw_d"])
		var id_d: float = _wrap_pi(deg_to_rad(float(row["sw_id1"])
			- float(row["sw_id0"]))) * 180.0 / PI
		print(("[pose-trace] sweep %-19s trav=%.2fs hdg %+7.1f deg (%+.0f deg/s) | "
			+ "ideal %+7.1f -> %+7.1f = %+7.1f deg | freed=%.2f of the traverse, "
			+ "gate_hold=%.2f") % [
			String(row["name"]), trav, swd, swd / maxf(1e-3, trav),
			float(row["sw_id0"]), float(row["sw_id1"]), id_d,
			float(row["sw_free"]), float(row["hold"])])
	# ---- the right-arm-fixed rule, proved on the two-hand leg ----
	for row in _ptrace_legs_out:
		if String(row["name"]) != "two_hand_proof":
			continue
		print(("[pose-trace] right-fixed: auto-pick sat on the LEFT %.0f%% of frames, "
			+ "published vs RIGHT arm %+.2f+-%.2f deg, vs LEFT arm %.2f+-%.2f deg "
			+ "(n=%d)") % [
			float(row["pick1"]) * 100.0, float(row["ang_err"]),
			float(row["ang_err_sd"]), float(row["alt_err"]),
			float(row["alt_err_sd"]), int(row["alt_n"])])
	# ---- the gate's two radii, measured by the extend / return ramps ----
	print(("[pose-trace] gate: release at dist_n=%s (dz %.3f), re-hold at dist_n=%s "
		+ "(dz %.3f); chest sits at %.3f") % [
		_ptrace_dn_str(_ptrace_release_dn), cfg.pose.deadzone,
		_ptrace_dn_str(_ptrace_rehold_dn), cfg.pose.deadzone,
		_ptrace_chest_dn()])
	print("[pose-trace] step 0->%+.1fdeg (down-and-out): mapper 90%% %s | snake 90%% %s | turn-rate-only 90%% %s | overshoot %.1f deg" % [
		rad_to_deg(_ptrace_step_span), _ptrace_ms(_ptrace_step_m90),
		_ptrace_ms(_ptrace_step_s90), _ptrace_ms(_ptrace_step_r90),
		rad_to_deg(_ptrace_step_over)])
	var turns: float = _ptrace_step_span / maxf(0.001, tuning.turn_rate)
	var share: float = -1.0
	if _ptrace_step_s90 >= 0.0 and _ptrace_step_r90 >= 0.0:
		share = _ptrace_step_s90 - _ptrace_step_r90
	print("[pose-trace] a %.1fdeg turn at turn.rate=%.2f takes %.3f s; mapper adds %s" % [
		rad_to_deg(_ptrace_step_span), tuning.turn_rate, turns, _ptrace_ms(share)])
	# ---- the arm-hanging gate, from the rows above -------------------------
	# Owner acceptance: gestures 1 and 2 must HOLD (frozen target, no heading
	# change, reason=arm-low), gesture 3 must still STEER down.
	for row in _ptrace_legs_out:
		var nm := String(row["name"])
		if nm == "hang_down" or nm == "hang_side":
			var ok_hold: bool = float(row["hang"]) >= 0.99 \
				and absf(float(row["ang_sd"])) < 0.01 \
				and absf(float(row["hdg_d"])) < 0.5 \
				and String(row["reason"]) == "arm-low"
			print("[pose-trace] hang  %-12s %s  hang=%.2f target_sd=%.3f deg hdg_d=%+.1f deg reason=%s" % [
				nm, ("PASS" if ok_hold else "FAIL"), float(row["hang"]),
				float(row["ang_sd"]), float(row["hdg_d"]), String(row["reason"])])
		elif nm == "down_out":
			var ok_steer: bool = float(row["hang"]) == 0.0 \
				and absf(float(row["ang"]) - rad_to_deg(PTRACE_DOWN_OUT_ANGLE)) < 0.5
			print("[pose-trace] steer %-12s %s  target=%.2f deg (gesture %.2f) hang=%.2f hdg_d=%+.1f deg" % [
				nm, ("PASS" if ok_steer else "FAIL"), float(row["ang"]),
				rad_to_deg(PTRACE_DOWN_OUT_ANGLE), float(row["hang"]),
				float(row["hdg_d"])])
		elif nm == "hang_sweep":
			print(("[pose-trace] hang hysteresis: %d state flip(s) over %.1f s of lower->raise "
				+ "(%.0f%% of frames held as arm-low) - 2 expected, more = chatter") % [
				int(row["hflips"]), float(int(row["frames"])) * PTRACE_DT,
				float(row["hang"]) * 100.0])
	print("[capture] done")
	get_tree().quit(0)


func _ptrace_ms(sec: float) -> String:
	if sec < 0.0:
		return "  n/a"
	return "%5.3f s" % sec


func _ptrace_dn_str(dn: float) -> String:
	return "  n/a" if dn < 0.0 else "%.3f" % dn


## The torso length the MAPPER will compute from these keypoints, in px:
## avg(|Lsh-Lhip|, |Rsh-Rhip|). It must be measured in PIXELS (x scaled by the
## image width, y by the height) - the old version took the distance in
## normalised space, which is squashed by the 16:9 aspect and read 282.1 px
## instead of 284.9 px, i.e. every scripted `dist_n` came out 1% short of its
## nominal value.
func _ptrace_torso_px() -> float:
	var dl := Vector2((PTRACE_LSHO.x - PTRACE_LHIP.x) * PTRACE_IMG_W,
		(PTRACE_LSHO.y - PTRACE_LHIP.y) * PTRACE_IMG_H).length()
	var dr := Vector2((PTRACE_RSHO.x - PTRACE_RHIP.x) * PTRACE_IMG_W,
		(PTRACE_RSHO.y - PTRACE_RHIP.y) * PTRACE_IMG_H).length()
	return (dl + dr) * 0.5


## The OLD reference point (chest), normalised provider space: what the previous
## pass steered around and what the raise-to-start test still uses.
func _ptrace_chest_n() -> Vector2:
	var neck := (PTRACE_LSHO + PTRACE_RSHO) * 0.5
	var waist := (PTRACE_LHIP + PTRACE_RHIP) * 0.5
	return neck.lerp(waist, cfg.pose.center_t)


## |chest - right shoulder| / torso: the distance a hand resting on the chest sits
## at, in the same units as `dist_n` (i.e. the number the dead zone has to cover).
func _ptrace_chest_dn() -> float:
	return _game_px(_ptrace_chest_n()).distance_to(_game_px(PTRACE_RSHO)) \
		/ maxf(1.0, _ptrace_torso_px())


## Scripted hand angle for this frame, in the GAME's mirrored convention and
## measured FROM THE RIGHT SHOULDER (what the snake should follow). See
## `_ptrace_kpts` for how it is placed in provider space.
## `span` / `travel` are only used by kind 12 (the straight-line sweep).
func _ptrace_ideal_angle(kind: int, t: float, dur: float, p0: float, p1: float,
		span: float = 0.0, travel: float = 0.0) -> float:
	var k: float = clampf(t / maxf(0.001, dur), 0.0, 1.0)
	match kind:
		0:
			return p0
		1, 11:
			# the measured step (11) scripts the same path as the plain step (1)
			return p0 if t < PTRACE_STEP_SETTLE else p1
		2:
			return p0 + (p1 - p0) * (1.0 - absf(2.0 * k - 1.0))
		3:
			return p0 + p1 * k
		4:
			# the left hand dithers, the right one holds p0: the target is p0
			return p0
		6:
			# the wrist sits on the old chest point: the geometric shoulder->chest
			# angle is what the vector says, but the dead zone must HOLD here
			var d: Vector2 = _game_px(_ptrace_chest_n()) - _game_px(PTRACE_RSHO)
			return atan2(d.y, d.x)
		7, 8:
			# gate ramps: the direction is fixed, only the distance changes
			return p0
		12:
			# straight-line sweep: the ideal is the true shoulder->wrist direction
			var k12: float = clampf((t - PTRACE_METRIC_SETTLE) / maxf(0.001, travel),
				0.0, 1.0)
			return atan2(lerpf(p0, p1, k12), lerpf(-span, span, k12))
	return p0


## Normalised provider point -> GAME-space px (the space `PSPoseInput` steers in).
func _game_px(p: Vector2) -> Vector2:
	return Vector2((1.0 - p.x) * PTRACE_IMG_W, p.y * PTRACE_IMG_H) \
		if _pose_mirror else Vector2(p.x * PTRACE_IMG_W, p.y * PTRACE_IMG_H)


## Build one synthetic Youdoo-18 frame for the scripted hand path.
## The RIGHT wrist is placed relative to the RIGHT SHOULDER at the scripted angle
## and distance, so the mapper's `angle = atan2(wrist - rsho)` is exactly the
## ideal angle; the LEFT wrist is placed relative to the LEFT shoulder (hanging at
## the side, or at `alt` for the two-hand proof). Everything is built in GAME
## space and written back in provider space through the inverse of `_flip_x`.
func _ptrace_kpts(kind: int, t: float, dur: float, p0: float, p1: float,
		d_arm: float, alt: float) -> Array:
	var torso_px: float = _ptrace_torso_px()
	var chest_n := _ptrace_chest_n()
	var ga: float = _ptrace_ideal_angle(kind, t, dur, p0, p1, d_arm, alt)
	var ga_l: float = PI * 0.5
	var d_r: float = d_arm
	var d_l: float = PTRACE_LEFT_HANG
	var k: float = clampf(t / maxf(0.001, dur), 0.0, 1.0)
	if is_finite(alt):
		ga_l = alt
		d_l = PTRACE_LEFT_PROOF
	if kind == 4:
		# The proof pose: the left hand is FURTHER from the chest than the right
		# one, at 180 deg to it. The auto-pick therefore sits on the LEFT wrist,
		# and the shipped law must still steer with the right arm only.
		ga_l = alt
		d_l = PTRACE_LEFT_PROOF
	elif kind == 7:
		# extend ramp: the gate must release somewhere between the two distances
		d_r = lerpf(d_arm, p1, k)
	elif kind == 8:
		# return ramp: the gate must re-close as the hand comes back to the chest
		d_r = lerpf(d_arm, _ptrace_chest_dn(), k)
	var sho_g := _game_px(PTRACE_RSHO)
	var lsho_g := _game_px(PTRACE_LSHO)
	var nz := Vector2(_ptrace_rng.rand_range(-PTRACE_NOISE_PX, PTRACE_NOISE_PX),
		_ptrace_rng.rand_range(-PTRACE_NOISE_PX, PTRACE_NOISE_PX))
	var wr_g: Vector2 = sho_g + Vector2(cos(ga), sin(ga)) * (d_r * torso_px)
	var wl_g: Vector2 = lsho_g + Vector2(cos(ga_l), sin(ga_l)) * (d_l * torso_px)
	if kind == 6:
		# (a) hand resting ON the chest: the exact point the old law steered around
		wr_g = _game_px(chest_n)
	elif kind == 12:
		# straight-line sweep: y from p0 to p1 (torso offsets), x from -dist to
		# +dist, over `alt` seconds starting at PTRACE_METRIC_SETTLE. The scripted
		# hand crosses the shoulder's own x in the middle, which is the frame the
		# snake must turn on.
		var k12: float = clampf((t - PTRACE_METRIC_SETTLE) / maxf(0.001, alt), 0.0, 1.0)
		wr_g = sho_g + Vector2(lerpf(-d_arm, d_arm, k12), lerpf(p0, p1, k12)) * torso_px
	wr_g += nz
	wl_g -= nz
	var er_g: Vector2 = (sho_g + wr_g) * 0.5
	var el_g: Vector2 = (lsho_g + wl_g) * 0.5
	var wr := _prov_norm(wr_g)
	var wl := _prov_norm(wl_g)
	var er := _prov_norm(er_g)
	var el := _prov_norm(el_g)
	var sl := (PTRACE_LSHO + PTRACE_LHIP) * 0.5
	var sr := (PTRACE_RSHO + PTRACE_RHIP) * 0.5
	return [
		_pt(np(chest_n + Vector2(0.0, -0.075))),            # 0 nose
		_pt(np(chest_n + Vector2(-0.020, -0.085))),         # 1 L eye
		_pt(np(chest_n + Vector2(0.020, -0.085))),          # 2 R eye
		_pt(np(chest_n + Vector2(-0.040, -0.080))),         # 3 L ear
		_pt(np(chest_n + Vector2(0.040, -0.080))),          # 4 R ear
		_pt(PTRACE_LSHO),                                   # 5 L shoulder
		_pt(PTRACE_RSHO),                                   # 6 R shoulder
		_pt(el),                                            # 7 L elbow
		_pt(er),                                            # 8 R elbow
		_pt(wl),                                            # 9 L wrist
		_pt(wr),                                            # 10 R wrist
		_pt(PTRACE_LHIP),                                   # 11 L hip
		_pt(PTRACE_RHIP),                                   # 12 R hip
		_pt(np(sl + Vector2(0.0, 0.24))),                   # 13 L knee
		_pt(np(sr + Vector2(0.0, 0.24))),                   # 14 R knee
		_pt(np(sl + Vector2(0.0, 0.46))),                   # 15 L ankle
		_pt(np(sr + Vector2(0.0, 0.46))),                   # 16 R ankle
		_pt(chest_n),                                       # 17 chest = the old ref
	]


## GAME-space px -> normalised provider space (inverse of `PSPoseInput._flip_x`).
func _prov_norm(p: Vector2) -> Vector2:
	return Vector2(_to_prov_u(p.x), p.y / PTRACE_IMG_H)


## Normalised pixel position -> the kp entry format [x, y, 0, score].
func _pt(p) -> Array:
	return [p.x, p.y, 0.0, 1.0]


## pose-image px -> normalised provider space.
func np(p: Vector2) -> Vector2:
	return Vector2(p.x / PTRACE_IMG_W, p.y / PTRACE_IMG_H)


func _wrap_pi(a: float) -> float:
	while a > PI:
		a -= TAU
	while a <= -PI:
		a += TAU
	return a


## Mirrored pose-image x -> normalised provider x (inverse of `_flip_x`).
func _to_prov_u(x: float) -> float:
	return (1.0 - x / PTRACE_IMG_W) if _pose_mirror else (x / PTRACE_IMG_W)


# ------------------------------------------------------ skeleton overlay capture
#
# `--capture-skeleton` proves the overlay transform: it paints a synthetic RGBA
# camera frame (576x324, the device's real preview size) that already contains
#   * a 32 px REFERENCE GRID,
#   * the mirrored colour markers the camera-test pattern uses (left red / right
#     blue), so the flip is verifiable in the same shot, and
#   * a PAINTED PERSON whose 18 joint dots sit at exactly the keypoint
#     coordinates the overlay receives,
# then pushes the matching 18-point skeleton through the real pose pipeline and
# saves the READY pane and the band mirror box. If the cyan skeleton lands on the
# orange painted joints, the transform is right.
#
# It also measures the overlay's draw-call cost on the same play frame (ON vs OFF),
# like `--capture-perf` does for the perf panel.

const SKEL_W := 576
const SKEL_H := 324
## The staged 18-point youdoo18 skeleton, normalised provider space. The RIGHT arm
## (6 -> 8 -> 10) is stretched out and up, 1.29 torso lengths from the right
## shoulder - i.e. well OUTSIDE the 0.70 dead zone - and the left arm hangs: an
## asymmetric pose makes both the mirror and the new shoulder reference obvious at
## a glance. Joint 6 (right shoulder) is where the lime dot/ring must land; joint
## 10 (right wrist) is the hand dot the line must reach. The legs stop at v=0.745
## because the band box's own chrome (the 1.00x badge + countdown bar) covers the
## bottom ~25 px of the box: every joint has to stay measurable above it.
const SKEL_POSE := [
	[0.500, 0.300], [0.487, 0.289], [0.513, 0.289], [0.470, 0.295], [0.530, 0.295],
	[0.430, 0.355], [0.570, 0.355], [0.400, 0.455], [0.670, 0.375],
	[0.385, 0.550], [0.770, 0.395], [0.455, 0.620], [0.545, 0.620],
	[0.450, 0.685], [0.550, 0.685], [0.445, 0.745], [0.555, 0.745], [0.500, 0.480],
]
const SKEL_BONES := [[0, 5], [0, 6], [5, 6], [6, 8], [8, 10], [5, 7], [7, 9],
	[6, 12], [5, 11], [11, 12], [11, 13], [12, 14], [13, 15], [14, 16]]

var _capture_skeleton := false
var _skel_cap_step := 0
var _skel_cap_t := 0.0
var _skel_cap_n := 0
var _skel_cap_draw_on := 0
var _skel_cap_draw_off := 0
var _skel_cap_prim_on := 0
var _skel_cap_prim_off := 0
var _skel_cap_img: Image = null
## True once the capture has switched to the HANG pose (step 5).
var _skel_hang_pose := false
## Right-wrist drop for the hang pose, in normalised v: 0.98 * torso_px / SKEL_H.
## torso_px = |Rsho - Rhip| = 87.06 px at SKEL_W/SKEL_H, so 0.98 torso = 85.32 px
## = 0.2633 of the frame height. Joint 8 (elbow) sits halfway down that arm.
const SKEL_HANG_DV := 0.2633


func _capture_skeleton_tick(dt: float) -> void:
	_skel_cap_t += dt
	if _skel_cap_img == null:
		_skel_cap_img = _skel_build_frame()
		_camera_rgba_apply({"seq": 1, "w": SKEL_W, "h": SKEL_H,
			"bytes": _skel_cap_img.get_data()})
		if hud != null:
			hud.persons = 1
			hud.tracking = true
	# The texture is uploaded once; the skeleton is re-ingested EVERY frame because
	# `pose.poll()` clears the overlay snapshot on every frame it runs (there is no
	# bridge here, so it would otherwise wipe the staged skeleton immediately).
	pose.ingest_test_skeleton(0, _skel_pose_kpts(), float(SKEL_W), float(SKEL_H), now)
	match _skel_cap_step:
		0:
			if _skel_cap_t > 0.5:
				_skel_cap_step = 1
				_on_mode_selected(1)
		1:
			# READY: the slot card's own camera pane, a different rect + aspect
			# than the band box - proving the transform is rect-independent.
			# ON + OFF pair: the diff isolates the overlay ink, and the OFF frame
			# keeps the painted joints as ground truth for `ui1024_measure.py`.
			if mode == MODE_READY and _skel_cap_t > 1.6:
				_skel_cap_step = 11
				_skel_cap_n = 0
				_save_png("res://evidence/skeleton-shoulder-ref-ready.png")
				if hud != null:
					hud.skel_on = false
		11:
			_skel_cap_n += 1
			if _skel_cap_n >= 2:
				_skel_cap_step = 2
				_save_png("res://evidence/skeleton-shoulder-ref-ready-off.png")
				if hud != null:
					hud.skel_on = true
				_begin_countdown("skeleton")
		2:
			if mode == MODE_PLAY:
				_skel_cap_step = 3
				_skel_cap_n = 0
				_prepare_preview()
				_snap_cameras()
				game.state = PSGame.STATE_COUNTDOWN
				game.countdown_left = 9999.0
				fx.reset()
				if hud != null:
					hud.skel_on = true
		3:
			_skel_cap_n += 1
			if _skel_cap_n > 20:
				_skel_cap_draw_on = maxi(_skel_cap_draw_on,
					int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
				_skel_cap_prim_on = maxi(_skel_cap_prim_on,
					int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			if _skel_cap_n == 24:
				_save_png("res://evidence/skeleton-shoulder-ref.png")
			if _skel_cap_n >= 60:
				_skel_cap_step = 4
				_skel_cap_n = 0
				if hud != null:
					hud.skel_on = false
		4:
			_skel_cap_n += 1
			if _skel_cap_n > 20:
				_skel_cap_draw_off = maxi(_skel_cap_draw_off,
					int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
				_skel_cap_prim_off = maxi(_skel_cap_prim_off,
					int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			if _skel_cap_n == 24:
				_save_png("res://evidence/skeleton-shoulder-ref-off.png")
			if _skel_cap_n >= 60:
				_skel_cap_step = 5
				_skel_cap_n = 0
				if hud != null:
					hud.skel_on = true
				print(("[skeleton] draw calls ON=%d OFF=%d delta=%d | primitives "
					+ "ON=%d OFF=%d delta=%d") % [
					_skel_cap_draw_on, _skel_cap_draw_off,
					_skel_cap_draw_on - _skel_cap_draw_off,
					_skel_cap_prim_on, _skel_cap_prim_off,
					_skel_cap_prim_on - _skel_cap_prim_off])
				print("[skeleton] staged frame " + str(SKEL_W) + "x" + str(SKEL_H)
					+ " px (the device preview size), 32 px reference grid, "
					+ str(SKEL_POSE.size()) + " keypoints, "
					+ str(SKEL_BONES.size()) + " bones")
		5:
			# HANG shot (2026-11-14, owner option B 下垂识别): the same camera
			# frame, repainted with the RIGHT arm hanging straight down 0.98 torso
			# from the right shoulder - the exact gesture the hang gate holds. The
			# overlay is ON, so the lime ring stays at the shoulder, the hand dot
			# drops outside it, and the console line below proves the mapper is
			# holding (`hang=true conf=0.00 reason=arm-low`). No new HUD cue was
			# added: the ring + the held hand dot are the existing drawing.
			if _skel_cap_n == 0:
				_skel_hang_pose = true
				_skel_cap_img = _skel_build_frame()
				_camera_rgba_apply({"seq": 2, "w": SKEL_W, "h": SKEL_H,
					"bytes": _skel_cap_img.get_data()})
			_skel_cap_n += 1
			if _skel_cap_n == 24:
				var m = pose.mappers[0]
				_save_png("res://evidence/skeleton-hang.png")
				print(("[skeleton] hang shot: dist_n=%.3f dy_n=%.3f dx_n=%.3f hang=%s "
					+ "conf=%.2f angle=%.1f deg reason=%s -> evidence/skeleton-hang.png") % [
					m.last_dist_n, m.last_dy_n, m.last_dx_n, str(m.last_hang),
					pose.steers[0].confidence,
					rad_to_deg(pose.steers[0].steer_angle_rad),
					String(pose.diag.get("reason", ""))])
			if _skel_cap_n >= 30:
				print("[capture] done")
				get_tree().quit(0)


## The active staged skeleton, normalised provider space: `SKEL_POSE`, or the same
## body with the RIGHT arm (joint 6 -> 8 -> 10) hanging straight down for the hang
## shot. The wrist lands 0.98 torso below the right shoulder, i.e. the exact
## gesture `pose.hang_*` is calibrated on.
func _skel_pts() -> Array:
	var pts: Array = []
	for i in SKEL_POSE.size():
		var p: Array = SKEL_POSE[i]
		pts.append([float(p[0]), float(p[1])])
	if _skel_hang_pose:
		pts[8] = [0.570, 0.355 + SKEL_HANG_DV * 0.5]
		pts[10] = [0.570, 0.355 + SKEL_HANG_DV]
	return pts


## The staged skeleton as bridge-shaped keypoints ([x, y, 0, score] x 18).
func _skel_pose_kpts() -> Array:
	var out: Array = []
	for p in _skel_pts():
		out.append([float(p[0]), float(p[1]), 0.0, 1.0])
	return out


## Paint the staged camera frame: reference grid + mirror markers + the person the
## skeleton is supposed to land on (same normalised coordinates as `_skel_pts()`).
func _skel_build_frame() -> Image:
	var pts := _skel_pts()
	var img := Image.create(SKEL_W, SKEL_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.055, 0.075, 0.115))
	# mirror markers, identical idea to `--camera-test`: red on the raw LEFT, blue
	# on the raw RIGHT, so a flipped blit puts red on the right of the box.
	img.fill_rect(Rect2i(0, 0, 96, SKEL_H), Color(0.55, 0.13, 0.18))
	img.fill_rect(Rect2i(SKEL_W - 96, 0, 96, SKEL_H), Color(0.13, 0.26, 0.62))
	# 32 px reference grid: every line is a UV landmark (32/576, 32/324).
	for gx in range(0, SKEL_W + 1, 32):
		img.fill_rect(Rect2i(gx, 0, 1, SKEL_H), Color(0.20, 0.42, 0.55))
	for gy in range(0, SKEL_H + 1, 32):
		img.fill_rect(Rect2i(0, gy, SKEL_W, 1), Color(0.20, 0.42, 0.55))
	# the person: painted from the very keypoints the overlay receives
	for b in SKEL_BONES:
		var a: Array = pts[int(b[0])]
		var c: Array = pts[int(b[1])]
		_skel_paint_line(img, Vector2(float(a[0]) * SKEL_W, float(a[1]) * SKEL_H),
			Vector2(float(c[0]) * SKEL_W, float(c[1]) * SKEL_H),
			Color(0.85, 0.52, 0.12), 5)
	for p in pts:
		var px := int(float(p[0]) * SKEL_W)
		var py := int(float(p[1]) * SKEL_H)
		img.fill_rect(Rect2i(px - 2, py - 2, 5, 5), Color(1.0, 0.78, 0.20))
	return img


## Thick line into an Image (fill_rect stamps along the segment).
func _skel_paint_line(img: Image, a: Vector2, b: Vector2, col: Color, w: int) -> void:
	var steps := int(maxf(1.0, a.distance_to(b)))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		img.fill_rect(Rect2i(int(p.x) - w / 2, int(p.y) - w / 2, w, w), col)


func _capture_perf_tick(dt: float) -> void:
	_perf_cap_t += dt
	if _perf_cap_step == 0 and _perf_cap_t > 0.6:
		_perf_cap_step = 1
		# Straight to the countdown: this probe measures one play frame, and the
		# READY gate is covered by `--capture-flow` (which walks it for real).
		_begin_countdown("perf")
	if _perf_cap_step == 1 and mode == MODE_PLAY:
		_perf_cap_step = 2
		_perf_cap_t = 0.0
		_perf_cap_n = 0
		_prepare_preview()
		_snap_cameras()
		# Park the rules so the two passes draw the exact same scene.
		game.state = PSGame.STATE_COUNTDOWN
		game.countdown_left = 9999.0
		fx.reset()
		_perf_panel_force(true)
		return
	if _perf_cap_step < 2:
		return
	_perf_cap_n += 1
	if _perf_cap_step == 2:
		# Panel ON: sample after the pipeline settles, then switch it off.
		if _perf_cap_n > 20:
			_perf_cap_draw_on = maxi(_perf_cap_draw_on, int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			_perf_cap_prim_on = maxi(_perf_cap_prim_on, int(Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		if _perf_cap_n >= 50:
			_perf_cap_step = 3
			_perf_cap_n = 0
			_perf_panel_force(false)
	elif _perf_cap_step == 3:
		# Panel OFF: the same scene, one HUD layer lighter.
		if _perf_cap_n > 20:
			_perf_cap_draw_off = maxi(_perf_cap_draw_off, int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			_perf_cap_prim_off = maxi(_perf_cap_prim_off, int(Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		if _perf_cap_n >= 50:
			_perf_cap_step = 4
			_perf_cap_n = 0
			_perf_panel_force(true)
	elif _perf_cap_step == 4:
		if _perf_cap_n == 4:
			_save_png("res://evidence/perf-overlay-1920.png")
		if _perf_cap_n >= 8:
			print("[perf-panel] draw on=%d off=%d delta=%d | prim on=%d off=%d delta=%d" % [
				_perf_cap_draw_on, _perf_cap_draw_off,
				_perf_cap_draw_on - _perf_cap_draw_off,
				_perf_cap_prim_on, _perf_cap_prim_off,
				_perf_cap_prim_on - _perf_cap_prim_off])
			print("[capture] done")
			get_tree().quit(0)


# =========================================================== stress harness
#
# `--capture-stress` (+ `--capture2p`): the WORST-CASE frame this build can reach,
# measured in **real time** (never with `--fixed-fps`, which would just report a
# fake 60). Two length legs per player count: 240 segments/snake (the hard ceiling
# asked for: 2x the 120-segment girth cap, ~2x a realistic 2-minute peak) and 120
# (the realistic ceiling), so the table shows both the stress and the real case.
#
# The scenario, all of it applied before the window opens:
#   * 8 snakes, `cap` segments each, woven through the view (every body's bounding
#     box crosses the arena view, so no snake is culled - and each body is 4x
#     wider than the view, i.e. most of every snake is off-screen but still built,
#     which is the honest cost of the shipped per-snake culling)
#   * food filled to the spawner's own trim cap (target_count + trim_extra)
#   * powerups at target_count
#   * the FX pools held at their caps every frame (220 particles / 24 texts /
#     8 waves). NOTE: particles are one `draw_texture_rect` each, so this is also
#     the draw-call worst case, not just the fill worst case.
#   * boost aura on every snake (the extra aura quads + warm shimmer layer)
#   * the camera at the widest span the build has (zoom is fixed per player
#     count: 0.98 in 1P, 0.65 in 2P - that IS max zoom-out)
#   * the always-on perf panel ON (shipped default, owner request), then a second
#     window with it OFF so its own cost is a number, then back ON
#   * the camera surface staged (one 576x324 frame + both skeletons through the
#     real pipeline), because the box always has a live camera in these screens
#
# Prints, per leg:
#   [stress] leg=1p cap=240 players=1 snakes=8 food=265 pwr=7 fx=220/24/8 ...
#            draw=NNN prim=NNNN fps_avg=NN.N fps_min=NN.N ms=N.NN p95=N.NN slow=N
#            bodies=8/8 dropped=0
#   [stress] nofxpanel leg=1p ... (perf panel OFF window, same fields minus bodies)
#   [stress] prof leg=1p world.food=... hud.band=... (the last frame's per-pass CPU)
#
# The release gate parses the `cap=240` lines (see tools/verify_release.ps1).

const STRESS_CAPS := [240, 120]
const STRESS_WARM_SEC := 0.7
const STRESS_MEASURE_SEC := 2.4
const STRESS_PANEL_OFF_SEC := 1.2
## Ring for the per-frame ms samples used by p95 (2.4 s at 60 fps = 144 frames).
const STRESS_SAMPLES := 512

var _capture_stress := false
var _capture_cam2p := false
## `--stress-no-cam`: drop the staged camera surface (attribution runs only).
var _stress_cam := true
## Attribution-only switches (`--stress-no-hud`, `--stress-no-world`): remove one
## whole layer so the stress numbers can be split between world / HUD / composite.
var _stress_no_hud := false
var _stress_no_world := false
var _stress_t := 0.0
var _stress_step := 0
var _stress_cap_i := 0
var _stress_phase_t := 0.0
var _stress_img: Image = null
var _stress_cam_applied := false
var _stress_frames := 0
var _stress_last_us := 0
var _stress_ms_sum := 0.0
var _stress_ms_max := 0.0
var _stress_draw_max := 0
var _stress_draw_sum := 0
var _stress_prim_max := 0
var _stress_slow := 0
var _stress_ms_ring := PackedFloat32Array()


func _capture_stress_tick(dt: float) -> void:
	_stress_t += dt
	if _stress_cam:
		_stress_ensure_camera()
	if _stress_step >= 2:
		_stress_fx_saturate()
	# True frame interval from the wall clock: `_process`'s delta is clamped to
	# 100 ms (`real_dt`), which would make a 40 ms frame read as 100 ms.
	var now_us := Time.get_ticks_usec()
	var frame_ms := 0.0
	if _stress_last_us > 0:
		frame_ms = float(now_us - _stress_last_us) / 1000.0
	_stress_last_us = now_us
	match _stress_step:
		0:
			if _stress_t > 0.5:
				if _stress_cam and hud != null:
					# The band box needs the texture BEFORE the ready cards draw.
					hud.cam_rgba_tex = _camera_rgba_tex
					hud.persons = 2 if _capture_2p else 1
					hud.tracking = true
				_stress_step = 1
				_on_mode_selected(2 if _capture_2p else 1)
		1:
			if mode == MODE_PLAY:
				# Attribution-only switches: they change what is DRAWN, never what
				# the harness measures on the other layers.
				if _stress_no_hud and hud != null:
					hud.visible = false
				if _stress_no_world:
					_set_worlds_visible(false)
				_stress_cap_i = 0
				_stress_begin_leg()
		2:
			_stress_phase_t += dt
			_stress_sample(frame_ms)
			if _stress_phase_t >= STRESS_WARM_SEC:
				_stress_phase_t = 0.0
				_stress_measure_reset()
				_stress_step = 3
		3:
			_stress_phase_t += dt
			_stress_sample(frame_ms)
			if _stress_phase_t >= STRESS_MEASURE_SEC:
				_stress_phase_t = 0.0
				_stress_print_leg("")
				_perf_panel_force(false)
				_stress_measure_reset()
				_stress_step = 4
		4:
			_stress_phase_t += dt
			_stress_sample(frame_ms)
			if _stress_phase_t >= STRESS_PANEL_OFF_SEC:
				_stress_phase_t = 0.0
				_stress_print_leg("nofxpanel")
				_perf_panel_force(true)
				_stress_step = 5
		5:
			_stress_cap_i += 1
			if _stress_cap_i < STRESS_CAPS.size():
				_stress_begin_leg()
			else:
				print("[capture] done")
				get_tree().quit(0)


## Stage one leg: 8 woven snakes at `cap` segments, the food/powerup caps, a boost
## buff on every snake, and the rules parked (no eating/dying during the window,
## exactly like `--capture-perf`: the frame under test is the one the owner sees
## when the field is long, not a lucky mid-round moment).
func _stress_begin_leg() -> void:
	var cap: int = int(STRESS_CAPS[_stress_cap_i])
	_stress_stage(cap)
	fx.reset()
	_snap_cameras()
	_stress_phase_t = 0.0
	_stress_measure_reset()
	_stress_step = 2


func _stress_stage(cap: int) -> void:
	# Rules parked: `game.update()` returns on STATE_COUNTDOWN, so bodies, food and
	# buffs stay exactly as staged while the renderer is measured.
	game.state = PSGame.STATE_COUNTDOWN
	game.countdown_left = 9999.0
	var centre := Vector2(cfg.world.w * 0.5, cfg.world.h * 0.5)
	var step: float = float(cfg.snake.seg_dist)
	var n: int = game.snakes.size()
	for i in n:
		var s = game.snakes[i]
		var y := centre.y + (float(i) - float(n - 1) * 0.5) * 104.0
		var phase := float(i) * 0.9
		var body := PackedVector2Array()
		body.resize(cap)
		for k in cap:
			var d := step * float(k)
			# Head 520 px left of centre, tail running right: a 1200 px wave over
			# 300 px of amplitude (~0.05 rad per joint, a normal weaving snake).
			body[k] = Vector2(centre.x - 520.0 + d,
				y + sin(d / 1200.0 * TAU + phase) * 300.0)
		s.body = body
		s.pulse.resize(cap)
		s.alive = true
		s.respawn_timer = 0.0
		s.freeze_until = 0.0
		s.heading = 0.0
		s.peak_length = cap
		s.clear_buffs()
		# Boost aura on every snake: the extra aura quads + the warm shimmer layer.
		s.apply_buff(0, 9999.0)
	# ---- food at the spawner's own trim cap ----
	# `random_food()` RETURNS a pellet; the caller appends it (only `ensure_food`
	# does that inside the core).
	var food_target: int = int(cfg.food.target_count) + int(cfg.food.trim_extra)
	var guard := 0
	while game.foods.size() < food_target and guard < food_target * 2:
		guard += 1
		game.foods.append(game.random_food())
	# ---- powerups at their cap ----
	guard = 0
	while game.powerups.size() < int(cfg.powerups.target_count) and guard < 64:
		guard += 1
		game.spawn_powerup(&"", NAN, NAN)
	if game.player != null:
		game.player.immune_until = game.time + 600.0


## Keep the FX pools saturated: 60 particles, 3 texts and 1 wave per frame is well
## above the drain rate, so pcount/tcount/wcount sit at their caps for the window.
func _stress_fx_saturate() -> void:
	var c: Vector2 = cams[0] if not cams.is_empty() else Vector2(2400.0, 1350.0)
	var f := float(_stress_frames)
	for k in 60:
		var a := (f + float(k)) * 0.37
		fx.particle(c.x + cos(a) * 380.0, c.y + sin(a) * 260.0, cos(a) * 130.0,
			sin(a) * 130.0, 0.55, 9.0, Color(0.92, 0.82, 0.45, 0.9), 0, 3.0)
	for k in 3:
		fx.text(c.x + cos(f * 0.3 + float(k)) * 300.0, c.y - 120.0, "YUM!",
			PSTheme.TV_GOLD, 48.0)
	fx.wave(c.x, c.y, PSTheme.CYAN, 30.0, 420.0)


## Stage the camera surface the box always has: one 576x324 synthetic frame (the
## device preview size) plus one skeleton per human slot, pushed through the REAL
## pipeline every frame (`pose.poll()` clears the snapshot otherwise).
func _stress_ensure_camera() -> void:
	if not _stress_cam_applied:
		_stress_cam_applied = true
		_stress_img = _skel_build_frame()
		_camera_rgba_apply({"seq": 1, "w": SKEL_W, "h": SKEL_H,
			"bytes": _stress_img.get_data()})
		if hud != null:
			hud.cam_rgba_tex = _camera_rgba_tex
	pose.ingest_test_skeleton(0, _skel_pose_kpts(), float(SKEL_W), float(SKEL_H), now)
	if player_count > 1:
		pose.ingest_test_skeleton(1, _cam2p_kpts(1), float(SKEL_W), float(SKEL_H), now)


func _stress_measure_reset() -> void:
	_stress_frames = 0
	_stress_last_us = Time.get_ticks_usec()
	_stress_ms_sum = 0.0
	_stress_ms_max = 0.0
	_stress_draw_max = 0
	_stress_draw_sum = 0
	_stress_prim_max = 0
	_stress_slow = 0
	_stress_ms_ring.resize(STRESS_SAMPLES)


## One per frame inside a window: wall-clock frame time, fps and the render
## counters. `fps_min` is the worst SINGLE frame (1000 / max ms), i.e. the number
## that shows a hitch; `fps_avg` is frames / seconds.
func _stress_sample(ms: float) -> void:
	if ms <= 0.0:
		return
	_stress_frames += 1
	_stress_ms_sum += ms
	if ms > _stress_ms_max:
		_stress_ms_max = ms
	if ms > 20.0:
		_stress_slow += 1
	if _stress_frames - 1 < STRESS_SAMPLES:
		_stress_ms_ring[_stress_frames - 1] = ms
	var d := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var p := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_stress_draw_sum += d
	if d > _stress_draw_max:
		_stress_draw_max = d
	if p > _stress_prim_max:
		_stress_prim_max = p


func _stress_p95() -> float:
	var n: int = mini(_stress_frames, STRESS_SAMPLES)
	if n <= 0:
		return 0.0
	var tmp := _stress_ms_ring.slice(0, n)
	tmp.sort()
	return float(tmp[mini(n - 1, int(ceil(float(n) * 0.95))) - 1])


func _stress_print_leg(tag: String) -> void:
	var n: int = maxi(1, _stress_frames)
	var avg_ms := _stress_ms_sum / float(n)
	var fps_avg := float(_stress_frames) / maxf(0.001, _stress_ms_sum / 1000.0)
	var fps_min := 1000.0 / maxf(0.001, _stress_ms_max)
	var bodies := 0
	var dropped := 0
	for w in worlds:
		bodies = maxi(bodies, int(w.get("_bodies_drawn")))
		dropped = maxi(dropped, int(w.get("_bodies_dropped")))
	var cap: int = int(STRESS_CAPS[_stress_cap_i])
	var prefix := "[stress] " if tag == "" else "[stress] %s " % tag
	print((prefix + "leg=%dp cap=%d players=%d snakes=%d food=%d pwr=%d fx=%d/%d/%d "
		+ "buffs=%d zoom=%.2f draw=%d prim=%d fps_avg=%.1f fps_min=%.1f ms=%.2f "
		+ "p95=%.2f slow=%d bodies=%d/%d dropped=%d") % [
		player_count, cap, player_count, game.snakes.size(), game.foods.size(),
		game.powerups.size(), fx.pcount, fx.tcount, fx.wcount, game.snakes.size(),
		zooms[0], _stress_draw_max, _stress_prim_max, fps_avg, fps_min, avg_ms,
		_stress_p95(), _stress_slow, bodies, game.snakes.size(), dropped])
	# Per-pass CPU of the last measured frame (world view + HUD).
	var parts := PackedStringArray()
	if not worlds.is_empty() and worlds[0].prof:
		for k in worlds[0].prof_ms.keys():
			parts.append("%s=%.2f" % [String(k), float(worlds[0].prof_ms[k])])
	if hud != null and hud.prof:
		for k in hud.prof_ms.keys():
			parts.append("%s=%.2f" % [String(k), float(hud.prof_ms[k])])
	if parts.size() > 0:
		print("[stress] prof leg=%dp cap=%d %s" % [
			player_count, cap, " ".join(parts)])


## The staged skeleton of the SECOND human slot: the same pose shifted into the
## raw LEFT half (x - 0.26), which is that player's half of the mirrored frame.
func _cam2p_kpts(slot: int) -> Array:
	var out: Array = []
	for p in _skel_pose_kpts():
		var q: Array = p.duplicate()
		if slot > 0:
			q[0] = clampf(float(q[0]) - 0.26, 0.02, 0.98)
		out.append(q)
	return out


# ------------------------------------------------------- 2P camera band proof
#
# `--capture-cam2p`: the evidence for the split-screen band mirror boxes, which
# used to be two empty plates (`show_frame = false`). Stages a frame with TWO
# people (one per half), pushes each slot's skeleton through the real pipeline,
# walks MODE_SELECT -> 2P READY -> PLAY and saves the play frame, where both band
# boxes must show camera pixels + that slot's bones.

var _cam2p_step := 0
var _cam2p_t := 0.0
var _cam2p_n := 0
var _cam2p_img: Image = null


func _capture_cam2p_tick(dt: float) -> void:
	_cam2p_t += dt
	if _cam2p_img == null:
		_cam2p_img = _cam2p_build_frame()
		_camera_rgba_apply({"seq": 1, "w": SKEL_W, "h": SKEL_H,
			"bytes": _cam2p_img.get_data()})
		pose.ingest_test_skeleton(0, _skel_pose_kpts(), float(SKEL_W), float(SKEL_H), now)
		pose.ingest_test_skeleton(1, _cam2p_kpts(1), float(SKEL_W), float(SKEL_H), now)
		if hud != null:
			hud.cam_rgba_tex = _camera_rgba_tex
			hud.persons = 2
			hud.tracking = true
	# Re-ingest every frame: `pose.poll()` clears the overlay snapshot otherwise.
	pose.ingest_test_skeleton(0, _skel_pose_kpts(), float(SKEL_W), float(SKEL_H), now)
	pose.ingest_test_skeleton(1, _cam2p_kpts(1), float(SKEL_W), float(SKEL_H), now)
	match _cam2p_step:
		0:
			if _cam2p_t > 0.5:
				_cam2p_step = 1
				_on_mode_selected(2)
		1:
			if mode == MODE_PLAY:
				_cam2p_step = 2
				_cam2p_n = 0
				_prepare_preview()
				_snap_cameras()
				game.state = PSGame.STATE_COUNTDOWN
				game.countdown_left = 9999.0
				fx.reset()
		2:
			_cam2p_n += 1
			if _cam2p_n == 10:
				_save_png("res://evidence/cam-2p-band-1920.png")
			if _cam2p_n >= 16:
				print(("[cam2p] band boxes slot0=%s slot1=%s tex=%s flip_x=%s "
					+ "skel_on=%s/%s") % [
					CAMERA_2P_SRC[0], CAMERA_2P_SRC[1],
					"none" if _camera_rgba_tex == null else str(_camera_rgba_size),
					str(_camera_rgba_flip), str(pose.skel_on[0]), str(pose.skel_on[1])])
				print("[capture] done")
				get_tree().quit(0)


## The synthetic frame from `_skel_build_frame()` (grid + one person) plus a second
## person in the raw left half, so BOTH halves of the split have somebody on them.
func _cam2p_build_frame() -> Image:
	var img := _skel_build_frame()
	var pts := _skel_pts()
	for b in SKEL_BONES:
		var a: Array = pts[int(b[0])]
		var c: Array = pts[int(b[1])]
		_skel_paint_line(img, Vector2((float(a[0]) - 0.26) * float(SKEL_W),
			float(a[1]) * float(SKEL_H)), Vector2((float(c[0]) - 0.26) * float(SKEL_W),
			float(c[1]) * float(SKEL_H)), Color(0.85, 0.52, 0.12), 5)
	for p in pts:
		var px := int((float(p[0]) - 0.26) * float(SKEL_W))
		var py := int(float(p[1]) * float(SKEL_H))
		if px >= 0:
			img.fill_rect(Rect2i(px - 2, py - 2, 5, 5), Color(1.0, 0.78, 0.20))
	return img


## --capture-escape: verification only. Enter 1P READY with no pose at all and
## screenshot the panel that appears after READY_NO_PERSON_HINT_SEC. The timer is
## compressed with Engine.time_scale (the constant itself stays 30 s).
func _capture_escape_tick(dt: float) -> void:
	_cap_t += dt
	if _cap_flow_step == 0 and _cap_t > 0.5:
		_cap_flow_step = 1
		_on_mode_selected(1)
	if _cap_flow_step == 2:
		# One frame after the flag flips, so the saved frame contains the panel.
		_cap_flow_step = 3
		_save_png("res://evidence/flow-05-ready-escape.png")
		print("[capture] nobody-detected panel shown after %.1fs of READY with no person" % \
			_ready_no_person_t)
		print("[capture] done")
		get_tree().quit(0)
	if _cap_flow_step == 1 and mode == MODE_READY and _nobody_hint:
		_cap_flow_step = 2


## --capture-overlap: verification only. Drives a 1-player round, then replaces
## the human body with a synthetic self-crossing "lasso" and parks the simulation
## (`PSGame.update()` returns before stepping) so the still frame shows exactly
## one snake crossing itself. The head side of the body runs over the rising
## return stroke, so the PNG shows which layer covers which. Saves
## `evidence/overlap-<tag>.png` plus a 3x crop of the crossing
## (`overlap-<tag>-crop.png`); `--overlap-tag=before|after` names the pair.
## No rule is touched: `body` is presentation input, and a rival-free frame keeps
## the shot about one snake.
func _capture_overlap_tick(dt: float) -> void:
	_overlap_t += dt
	if _overlap_t > 20.0 and _overlap_step < 3:
		printerr("[capture] overlap timeline TIMEOUT at step %d" % _overlap_step)
		get_tree().quit(1)
		return
	match _overlap_step:
		0:
			if _overlap_t > 0.3:
				_overlap_step = 1
				_begin_countdown("overlap")
		1:
			# Same frame _begin_play() ran: the simulation has not stepped yet.
			if mode == MODE_PLAY:
				_overlap_step = 2
				_overlap_prepare()
		2:
			_overlap_place()
			if _overlap_t > 3.0:
				_overlap_step = 3
				_save_png("res://evidence/overlap-%s.png" % _overlap_tag)
				_overlap_save_crop("res://evidence/overlap-%s-crop.png" % _overlap_tag)
				print("[capture] overlap: tag=%s body=%d crossing_world=%s camera=%s" % [
					_overlap_tag,
					game.player.body.size() if game.player != null else 0,
					_overlap_cross, _overlap_centre])
				print("[capture] done")
				get_tree().quit(0)


## Park the simulation and stage the self-crossing pose.
func _overlap_prepare() -> void:
	var p = game.player
	if p == null:
		return
	# COUNTDOWN with a huge timer: `PSGame.update()` decrements and returns, so
	# the body placed below can never be pulled back by the follow chain.
	game.state = PSGame.STATE_COUNTDOWN
	game.countdown_left = 999.0
	var i := 1
	while i < game.snakes.size():
		var s = game.snakes[i]
		s.alive = false
		s.body.resize(0)
		s.pulse.resize(0)
		s.respawn_timer = 999.0
		i += 1
	_overlap_build()
	_overlap_place()


## One frame of the staged pose (idempotent; cheap enough to re-apply).
func _overlap_place() -> void:
	var p = game.player
	if p == null or _overlap_path.size() < 2:
		return
	p.alive = true
	p.freeze_until = 0.0
	# No immunity ring in the shot: the simulation is parked (COUNTDOWN with a
	# huge timer), so nothing can collide with the staged body anyway.
	p.immune_until = 0.0
	p.body = _overlap_path
	p.pulse.resize(_overlap_path.size())
	var head: Vector2 = p.body[0]
	var nxt: Vector2 = p.body[1]
	p.heading = atan2(head.y - nxt.y, head.x - nxt.x)
	p.speed = cfg.snake.base_speed
	# Frame the whole lasso (world -> screen is cam/zoom in PSWorldView).
	cams[0] = _overlap_centre
	if worlds.size() > 0:
		worlds[0].cam = _overlap_centre


## Build the lasso in world space and remember its centre + crossing point.
func _overlap_build() -> void:
	if _overlap_built:
		return
	_overlap_built = true
	var centre := Vector2(cfg.world.w * 0.5, cfg.world.h * 0.5)
	# Local control points (head -> tail), relative to the arena centre.
	#   * outbound stroke (head side): y = -152, x = -470 .. +210
	#   * right/down loop, then a LEFT rise that cuts the outbound stroke at
	#     about x = -301 (near vertical => a clean 90 degree crossing)
	#   * tail parks above-left of the crossing
	var ctrl := PackedVector2Array([
		Vector2(-470.0, -150.0), Vector2(-300.0, -152.0), Vector2(-120.0, -154.0),
		Vector2(60.0, -152.0), Vector2(210.0, -146.0), Vector2(320.0, -120.0),
		Vector2(388.0, -50.0), Vector2(405.0, 40.0), Vector2(392.0, 132.0),
		Vector2(340.0, 205.0), Vector2(250.0, 250.0), Vector2(130.0, 268.0),
		Vector2(10.0, 262.0), Vector2(-100.0, 232.0), Vector2(-190.0, 178.0),
		Vector2(-258.0, 104.0), Vector2(-296.0, 16.0), Vector2(-308.0, -80.0),
		Vector2(-300.0, -170.0), Vector2(-296.0, -260.0), Vector2(-310.0, -350.0),
	])
	var dense := _catmull_rom(ctrl, 12)
	var pts := _resample_path(dense, cfg.snake.seg_dist)
	var mn := Vector2(1.0e18, 1.0e18)
	var mx := Vector2(-1.0e18, -1.0e18)
	for q in pts:
		mn = Vector2(minf(mn.x, q.x), minf(mn.y, q.y))
		mx = Vector2(maxf(mx.x, q.x), maxf(mx.y, q.y))
	_overlap_path = PackedVector2Array()
	for q in pts:
		_overlap_path.append(q + centre)
	_overlap_centre = centre + (mn + mx) * 0.5
	_overlap_cross = centre + Vector2(-301.0, -152.0)


## Uniform Catmull-Rom through the control points (`sub` samples per span).
func _catmull_rom(ctrl: PackedVector2Array, sub: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	if n < 2:
		return ctrl
	for i in n - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, n - 1)]
		for k in sub:
			var t := float(k) / float(sub)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	return out


## Re-space a polyline at `step` units (the body's own node spacing).
func _resample_path(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 2 or step <= 0.0:
		return pts
	out.append(pts[0])
	var remaining := step
	for i in range(1, n):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		if seg <= 0.0001:
			continue
		var pos := 0.0
		while pos + remaining <= seg:
			pos += remaining
			out.append(a.lerp(b, pos / seg))
			remaining = step
		remaining -= seg - pos
	if out.size() < 2:
		out.append(pts[n - 1])
	return out


## 3x crop of the crossing (evidence: the eye can see which layer is on top).
func _overlap_save_crop(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[capture] skip %s (headless)" % path)
		return
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[capture] FAILED: no viewport image")
		return
	var zoom: float = worlds[0].zoom if worlds.size() > 0 else 1.2
	var view: Vector2 = worlds[0].view if worlds.size() > 0 else ARENA_SIZE
	var cam: Vector2 = worlds[0].cam if worlds.size() > 0 else _overlap_centre
	var wpos: Vector2 = worlds[0].position if worlds.size() > 0 else Vector2.ZERO
	var sp := (_overlap_cross - cam) * zoom + view * 0.5 + wpos
	var iw := img.get_width()
	var ih := img.get_height()
	var cw := mini(420, iw)
	var ch := mini(300, ih)
	var rx := clampi(int(sp.x) - cw / 2, 0, maxi(0, iw - cw))
	var ry := clampi(int(sp.y) - ch / 2, 0, maxi(0, ih - ch))
	var sub := img.get_region(Rect2i(rx, ry, cw, ch))
	sub.resize(cw * 3, ch * 3)
	var abs_path := ProjectSettings.globalize_path(path)
	var err := sub.save_png(abs_path)
	print("[capture] saved %s (%dx%d) from (%d,%d) err=%d" % [
		abs_path, sub.get_width(), sub.get_height(), rx, ry, err])


## --capture-tuning: verification only. Two jobs in one run, picked by the build:
##
##  * `PSBuild.TUNING_ENABLED == true`  -> opens the panel with a real F8 key event
##    (`Input.parse_input_event`, the same path an RCU press takes), drives it
##    with DPAD/OK/BACK events, and prints the config values before/after so the
##    log proves the changes were written to the objects the rules read.
##  * `PSBuild.TUNING_ENABLED == false` -> proves the panel does not exist: F8 is
##    pressed, nothing opens, nothing is drawn, and the screen is saved as
##    evidence/tuning-off.png.
func _capture_tuning_tick(dt: float) -> void:
	_tune_t += dt
	if _tune_t > 40.0 and _tune_step < 9:
		printerr("[capture] tuning timeline TIMEOUT at step %d mode=%d" % [
			_tune_step, mode])
		get_tree().quit(1)
		return
	match _tune_step:
		0:
			if _tune_t > 0.3:
				_tune_step = 1
				_begin_countdown("tuning")
		1:
			if mode == MODE_PLAY:
				_tune_step = 2
				_prepare_preview()
				_tune_print_values("boot")
				if _tuning_panel == null:
					# Build flag off: no node, so no key can reach it.
					_tune_step = 20
					_tune_seq = [[0.2, KEY_F8]]
					_tune_seq_i = 0
					_tune_next = _tune_t
				else:
					_tune_seq = [[0.3, KEY_F8]]
					_tune_seq_i = 0
					_tune_next = _tune_t
		2:
			if _tune_advance():
				_tune_step = 3
				_tune_shot_t = _tune_t
		3:
			if _tune_t - _tune_shot_t > 0.35:
				_tune_step = 4
				_save_png("res://evidence/tuning-01-panel-open.png")
				print("[capture] tuning panel: node=%s open=%s rows=%d keys=%s" % [
					_tuning_panel != null, _tuning_panel.open if _tuning_panel != null else false,
					_tuning_panel.rows.size() if _tuning_panel != null else 0,
					str(PSRemote.PANEL_KEYS)])
				if _tuning_panel != null:
					# centre +3 steps, turn rate +2 steps, round mode OK, head
					# style OK, then BACK to close.
					var seq := [[0.15, KEY_RIGHT], [0.15, KEY_RIGHT], [0.15, KEY_RIGHT],
						[0.15, KEY_DOWN], [0.15, KEY_RIGHT], [0.15, KEY_RIGHT]]
					seq.append([0.15, KEY_DOWN])
					for i in 9:
						seq.append([0.14, KEY_DOWN])
					seq.append([0.25, KEY_ENTER])
					for i in 4:
						seq.append([0.14, KEY_DOWN])
					seq.append([0.25, KEY_ENTER])
					_tune_seq = seq
					_tune_seq_i = 0
					_tune_next = _tune_t
		4:
			if _tune_advance():
				_tune_step = 5
				_tune_shot_t = _tune_t
		5:
			if _tune_t - _tune_shot_t > 0.3:
				_tune_step = 6
				_save_png("res://evidence/tuning-02-panel-changed.png")
				_tune_print_values("after keys")
				_tune_seq = [[0.2, KEY_BACK]]
				_tune_seq_i = 0
				_tune_next = _tune_t
		6:
			if _tune_advance():
				_tune_step = 7
				_tune_shot_t = _tune_t
		7:
			if _tune_t - _tune_shot_t > 0.3:
				_tune_step = 8
				_save_png("res://evidence/tuning-03-panel-closed.png")
				print("[capture] tuning panel: open=%s (BACK closed it)" % [
					_tuning_panel.open if _tuning_panel != null else false])
				print("[capture] done")
				get_tree().quit(0)
		20:
			# Build flag off: one F8 press, then prove nothing happened.
			if _tune_advance():
				_tune_step = 21
				_tune_shot_t = _tune_t
		21:
			if _tune_t - _tune_shot_t > 0.35:
				_tune_step = 22
				_save_png("res://evidence/tuning-off.png")
				print("[capture] tuning panel: node=absent open=false (F8 pressed, mode=%d)" % mode)
				print("[capture] tuning panel: no node, no draw, no key handler (build flag off)")
				print("[capture] done")
				get_tree().quit(0)


## Feeds the queued [delay, keycode] pairs; true when the queue is empty.
func _tune_advance() -> bool:
	while _tune_seq_i < _tune_seq.size():
		if _tune_t < _tune_next:
			return false
		_feed_tap(int(_tune_seq[_tune_seq_i][1]))
		_tune_seq_i += 1
		if _tune_seq_i < _tune_seq.size():
			_tune_next = _tune_t + float(_tune_seq[_tune_seq_i][0])
	return true


## One line with every value the panel writes (read back from cfg/tuning, i.e.
## exactly what the rules will use on the next frame).
func _tune_print_values(tag: String) -> void:
	print(("[capture] tuning %s: centre=%.2f turn=%.1f spd=%.2f..%.2f near=%.2f far=%.2f "
		+ "smooth=%.2f slow=%.2f/%.0f girth=%.2f freeze=%.2f round=%s "
		+ "ai=%.2f/%.2f/%.2f head=%s pressure=%.2f") % [
		tag, cfg.pose.center_t, tuning.turn_rate, cfg.pose.speed.min, cfg.pose.speed.max,
		cfg.pose.speed.near, cfg.pose.speed.far, cfg.pose.speed.smooth,
		tuning.slow_strength, tuning.slow_scale, tuning.girth_max,
		tuning.respawn_freeze, str(cfg.round.mode), tuning.ai_level,
		tuning.ai_mistake, tuning.ai_pressure, str(tuning.head_style_on),
		tuning.compute_ai_pressure()])


## --capture-remote: screenshots + a real key-driven menu journey. Every menu
## step is an InputEventKey fed through Input.parse_input_event (exactly what the
## Android RCU delivers); READY/PLAY still use the synthetic pose harness so the
## screen can advance without a camera.
func _capture_remote_tick(dt: float) -> void:
	_remote_t += dt
	if _remote_t > 30.0 and not _remote_done:
		_remote_done = true
		printerr("[capture] remote timeline TIMEOUT at step %d mode=%d" % [
			_remote_step, mode])
		get_tree().quit(1)
		return
	match _remote_step:
		0:
			if _remote_t > 0.4:
				_remote_step = 1
				_save_png("res://evidence/remote-01-mode-select.png")
				_feed_tap(KEY_RIGHT)   # focus 双人模式
		1:
			if _remote_t > 0.95:
				_remote_step = 2
				_save_png("res://evidence/remote-01b-mode-select-2p.png")
				_feed_tap(KEY_ENTER)   # OK -> MODE_READY (2P)
		2:
			if mode == MODE_READY and _remote_t > 2.5:
				_remote_step = 3
				_save_png("res://evidence/remote-02-ready.png")
		3:
			if mode == MODE_PLAY:
				_remote_step = 4
				_remote_play_t = 0.0
		4:
			_remote_play_t += dt
			if not _remote_previewed and _remote_play_t > 0.35:
				_remote_previewed = true
				_prepare_preview()
			elif _remote_previewed and _remote_play_t > 1.0:
				_remote_step = 5
				_save_png("res://evidence/remote-03-play.png")
				_feed_tap(KEY_ENTER)   # OK -> pause
		5:
			if mode == MODE_PAUSE:
				_remote_step = 6
				_remote_play_t = 0.0
		6:
			_remote_play_t += dt
			if _remote_play_t > 0.35:
				_remote_step = 7
				_save_png("res://evidence/remote-04-pause.png")
				_feed_tap(KEY_BACK)    # BACK -> resume
		7:
			if mode == MODE_PLAY:
				_remote_step = 8
				game.finish_round()    # tooling: jump to settlement for the shot
		8:
			if mode == MODE_SETTLE:
				_remote_step = 9
				_remote_play_t = 0.0
		9:
			_remote_play_t += dt
			if not _remote_skip_sent and _remote_play_t > 0.4:
				# OK during the 1.1 s camera rise must skip it in place (the same
				# press must NOT be swallowed as "wait for the animation").
				_remote_skip_sent = true
				_feed_tap(KEY_ENTER)
				print("[capture] remote: OK during the settle rise skipped it")
			if _remote_play_t > 1.0:
				_remote_step = 10
				_save_png("res://evidence/remote-05-settle.png")
				_feed_tap(KEY_BACK)    # settled settle: BACK -> MODE_SELECT
		10:
			if mode == MODE_SELECT:
				_remote_done = true
				print("[capture] remote key journey: select -> ready -> play -> pause -> settle -> select")
				print("[capture] done")
				get_tree().quit(0)


## --remote-probe: headless key journey. Same InputEventKey feed as
## --capture-remote, but time-scaled and no screenshots; proves every action.
func _remote_probe_tick(dt: float) -> void:
	_remote_t += dt
	if _remote_t > 40.0 and not _remote_done:
		_remote_done = true
		printerr("[probe] TIMEOUT at step %d mode=%d" % [_remote_step, mode])
		get_tree().quit(1)
		return
	match _remote_step:
		0:
			if _remote_t > 0.3:
				_remote_step = 1
				_feed_tap(KEY_RIGHT)   # mode select: focus 双人模式
		1:
			if _remote_t > 0.45:
				_remote_step = 2
				_feed_tap(KEY_ENTER)   # OK -> READY 2P
		2:
			if mode == MODE_READY:
				_remote_step = 3
				_feed_tap(KEY_BACK)    # READY: BACK -> mode select
		3:
			if mode == MODE_SELECT:
				_remote_step = 4
				_feed_tap(KEY_LEFT)    # focus 单人模式
				_feed_tap(KEY_KP_ENTER)  # OK (keypad-enter variant) -> READY 1P
		4:
			if mode == MODE_PLAY:
				_remote_step = 5
				_feed_tap(KEY_ENTER)   # PLAY: OK -> pause
		5:
			if mode == MODE_PAUSE:
				_remote_step = 6
				_feed_tap(KEY_BACK)    # PAUSE: BACK -> resume
		6:
			if mode == MODE_PLAY:
				_remote_step = 7
				_feed_tap(KEY_ENTER)   # PLAY: OK -> pause again
		7:
			if mode == MODE_PAUSE:
				_remote_step = 8
				_feed_tap(KEY_DOWN)    # focus 重新开局
				_feed_tap(KEY_ENTER)   # OK -> COUNTDOWN (restart)
		8:
			if mode == MODE_COUNTDOWN:
				_remote_step = 9
				_feed_tap(KEY_ESCAPE)  # COUNTDOWN: ESC -> mode select
		9:
			if mode == MODE_SELECT:
				_remote_step = 10
				_feed_tap(KEY_LEFT)
				_feed_tap(KEY_SPACE)   # OK via space variant -> READY
		10:
			if mode == MODE_PLAY:
				_remote_step = 11
				_remote_play_t = 0.0
				game.finish_round()    # tooling: jump to settlement
		11:
			_remote_play_t += dt
			if mode == MODE_SETTLE and not _remote_skip_sent and _remote_play_t > 0.3:
				# OK during the camera rise must skip it in place; a second press
				# (RIGHT + OK below) then navigates, so nothing is swallowed.
				_remote_skip_sent = true
				_remote_step = 12
				_feed_tap(KEY_ENTER)
				print("[probe] settle rise: OK skip fed at t=%.2fs" % _remote_play_t)
		12:
			_remote_play_t += dt
			if stage != null and stage.settled and _remote_play_t > 0.9:
				_remote_step = 13
				print("[probe] settle rise skipped -> settled=%s (OK)" % str(stage.settled))
				_feed_tap(KEY_RIGHT)   # focus 返回模式选择
				_feed_tap(KEY_ENTER)   # OK -> mode select
		13:
			if mode == MODE_SELECT:
				_remote_step = 14
				_feed_tap(KEY_LEFT)
				_feed_tap(KEY_ENTER)   # READY again (for the Android BACK test)
		14:
			if mode == MODE_READY:
				_remote_step = 15
				_feed_tap(KEY_BACK)    # Android KEYCODE_BACK path -> mode select
		15:
			if mode == MODE_SELECT:
				_remote_done = true
				print("[probe] PASS: mode_select/ready/pause/countdown/settle all driven by remote keys")
				print("[probe] no keyboard, no mouse and no touch was used")
				get_tree().quit(0)


## --remote-nav (verification only, never ships): drives BACK on every screen plus
## one injected mid-play slot loss, and prints one `[nav]` line per claim. Every
## press goes through the REAL input queue (`_feed_tap` -> Input.parse_input_event
## -> `_input` -> `_dispatch_action`), i.e. exactly the Android RCU path, and no
## keyboard/mouse/touch handler is involved.
##
## The last step presses BACK on MODE_SELECT on purpose: that path backgrounds the
## app (or, without the plugin binding, quits), so the process ends there — the
## `[ui] BACK on mode_select ->` line is the evidence for it.
func _probe_nav_tick(dt: float) -> void:
	_probe_nav_t += dt
	if _probe_nav_step == 0:
		if _probe_nav_t > 0.4:
			_probe_nav_t = 0.0
			_probe_nav_step = 1
			print("[nav] mode_select: LEFT + OK (focus 单人模式, confirm)")
			_feed_tap(KEY_LEFT)
			_feed_tap(KEY_ENTER)
		return
	if _probe_nav_t > 6.0:
		printerr("[nav] TIMEOUT at step %d (mode=%d)" % [_probe_nav_step, mode])
		get_tree().quit(1)
		return
	match _probe_nav_step:
		1:
			if mode == MODE_READY:
				_probe_nav_t = 0.0
				_probe_nav_step = 2
				print("[nav] 1/7 mode_select OK -> READY                       PASS")
				_feed_tap(KEY_BACK)
		2:
			if mode == MODE_SELECT:
				_probe_nav_t = 0.0
				_probe_nav_step = 3
				print("[nav] 2/7 READY + BACK -> mode_select (unchanged)        PASS")
				_feed_tap(KEY_LEFT)
				_feed_tap(KEY_ENTER)
		3:
			if mode == MODE_READY:
				_probe_nav_t = 0.0
				_probe_nav_step = 4
		4:
			if mode == MODE_PLAY:
				_probe_nav_t = 0.0
				_probe_nav_step = 5
				print("[nav] 3/7 READY -> COUNTDOWN -> PLAY                     PASS")
				_feed_tap(KEY_BACK)
		5:
			if mode == MODE_PAUSE:
				# `_dispatch_action` drops a second BACK inside DUP_ACTION_MS
				# (90 ms of WALL clock) — and this probe runs at 4x time scale, so
				# 0.6 s of probe time is only ~150 ms wall. Waiting on the probe
				# clock any less than that silently eats the press.
				if _probe_nav_t < 0.6:
					return
				_probe_nav_t = 0.0
				_probe_nav_step = 6
				print("[nav] 4/7 PLAY + BACK -> pause (round frozen)            PASS")
				_feed_tap(KEY_BACK)
		6:
			if mode == MODE_PLAY:
				_probe_nav_t = 0.0
				_probe_nav_step = 7
				print("[nav] 5/7 PAUSE + BACK -> resume (play)                  PASS")
				_probe_slot_lost = true
				print("[nav] injecting a human-slot loss in play (probe hook)")
		7:
			if mode == MODE_READY:
				_probe_slot_lost = false
				_probe_nav_t = 0.0
				_probe_nav_step = 8
				print("[nav] 6/7 slot lost in play for %.1fs -> READY           PASS" % PLAY_SLOT_LOST_SEC)
				_feed_tap(KEY_BACK)
		8:
			if mode == MODE_SELECT:
				# Same 90 ms wall-clock guard as step 5 (4x time scale).
				if _probe_nav_t < 0.6:
					return
				_probe_nav_t = 0.0
				_probe_nav_step = 9
				print("[nav] 7/7 READY + BACK -> mode_select                    PASS")
				print("[nav] mode_select + BACK -> background-or-quit; the [ui] line below names the path")
				_feed_tap(KEY_BACK)
		9:
			# The fallback calls quit(); this only runs if a moveTaskToBack binding
			# exists (the app stays alive), so end the probe cleanly either way.
			print("[nav] PASS: every BACK/OK route behaving as documented")
			get_tree().quit(0)


## Capture only: make the preview look like a mid-round TV frame.
func _prepare_preview() -> void:
	var p = game.player
	if p == null:
		return
	# Put the player mid-world facing +X-ish so the shot shows the arena, not a wall.
	var segs: int = mini(90, p.body.size() + 46)
	p.reset(1980.0, 1320.0, 0.22, segs)
	p.apply_buff(0, 9.0)
	# Capture only: keep the subject alive for the screenshot. Without this the
	# autopilot can be eaten by a rival while the capture timer runs.
	p.immune_until = game.time + 120.0
	var head: Vector2 = p.body[0]
	game.spawn_powerup(&"boost", head.x + 260.0, head.y - 120.0)
	game.spawn_powerup(&"magnet", head.x - 300.0, head.y + 160.0)
	game.spawn_powerup(&"boost", head.x + 40.0, head.y + 300.0)
	for i in 6:
		game.foods.append(game.make_food(head.x + cos(float(i)) * 210.0,
			head.y + sin(float(i)) * 210.0, i == 0))
	# bring two rivals into frame so the shot also shows the NPC heads/colours
	_place_rivals(head)


## Capture only: a burst + "YUM!" right before the screenshot is taken.
func _preview_fx() -> void:
	var p = game.player
	if p == null or p.body.size() == 0:
		return
	var head: Vector2 = p.body[0]
	# rivals are placed at shot time: the AI keeps moving, so placing them
	# earlier in the round would leave an empty frame.
	_place_rivals(head)
	var mx := head.x + cos(p.heading) * 90.0
	var my := head.y + sin(p.heading) * 90.0
	fx.eat(mx, my, Color("FFD93D"), true)
	fx.text(head.x, head.y - 120.0, "YUM!", PSTheme.GOLD, 64.0)
	fx.add_shake(4.0)


func _place_rivals(head: Vector2) -> void:
	if game.snakes.size() < 4:
		return
	var a = game.snakes[1]
	a.reset(head.x + 520.0, head.y - 360.0, PI * 0.85, 34)
	var b = game.snakes[2]
	b.reset(head.x - 380.0, head.y + 380.0, -PI * 0.15, 26)
	var c = game.snakes[3]
	c.reset(head.x + 700.0, head.y + 260.0, -PI * 0.6, 20)


## Capture only: move AI snakes that wandered into the subject out of frame, so
## the play screenshot is readable (the autopilot deliberately ignores rivals).
func _clear_rivals_near(head: Vector2, radius: float) -> void:
	var i := 4
	while i < game.snakes.size():
		var s = game.snakes[i]
		i += 1
		if not s.alive or s.body.size() == 0:
			continue
		if (s.body[0] as Vector2).distance_to(head) >= radius:
			continue
		s.reset(clampf(head.x + 1180.0, 200.0, cfg.world.w - 200.0),
			clampf(head.y - 620.0 + 120.0 * float(i), 200.0, cfg.world.h - 200.0),
			PI * 0.5, 18)


## Capture tooling only: prove the play frame has real character skins in it.
## The world view reports the skins its last drawn frame rendered (one entry per
## on-screen snake with a usable atlas), so `distinct` is the number of different
## characters that are actually visible, not just dealt. Read-only.
func _print_visible_skins() -> void:
	var all: Array = []
	for w in worlds:
		if w != null and w.has_method("visible_skins"):
			all.append_array(w.visible_skins())
	var names := ""
	var seen := {}
	for idx in all:
		var slug := String(PSSkins.get_skin(int(idx)).get("slug", "?"))
		if not seen.has(slug):
			seen[slug] = true
			names += " " + slug
	print("[skin] visible-in-frame=%d distinct=%d:%s" % [all.size(), seen.size(), names])


func _save_png(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[capture] skip %s (headless)" % path)
		return
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[capture] FAILED: no viewport image")
		return
	var abs_path := ProjectSettings.globalize_path(path)
	var err := img.save_png(abs_path)
	print("[capture] saved %s (%dx%d) err=%d" % [abs_path, img.get_width(), img.get_height(), err])


## Verification harness only: one press + release through Godot's real input
## queue. This is the same path an Android RCU press takes:
## Input.parse_input_event -> Input -> Viewport -> `_input()`.
func _feed_tap(code: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _on_hud_button(id: int) -> void:
	match id:
		BTN_MODE_1P:
			_on_mode_selected(1)
		BTN_MODE_2P:
			_on_mode_selected(2)
		BTN_RESUME:
			_toggle_pause("resume")
		BTN_RESTART:
			_begin_countdown("restart")
		BTN_MENU:
			_enter_select("pause_menu")


func _on_stage_button(id: int) -> void:
	if id == BTN_RETRY:
		_begin_countdown("retry")
	elif id == BTN_STAGE_MENU:
		_enter_select("settle_menu")


func _set_player_count(n: int) -> void:
	var want := 2 if n >= 2 else 1
	if want == player_count:
		return
	player_count = want
	game.set_player_count(want)
	_rebuild_views()
	_snap_cameras()
	hud.player_count = player_count


# ------------------------------------------------------------- RCU input

## The ONE input handler for the whole game. There is deliberately no
## `_unhandled_input`, no mouse/touch handler and no `ui_accept` polling: a single
## physical press therefore cannot fire twice through two different code paths.
##
## Shipped Android build: `GodotApp.dispatchKeyEvent()` consumes every remote key
## and re-injects it as a pure-keyboard KeyEvent, so this function receives
## exactly one `InputEventKey` per press (backed by `_dispatch_action()`'s
## duplicate guard). The joypad/raw-Android branches below are fallbacks for a
## stock template where that native hook is missing.
func _input(event: InputEvent) -> void:
	# Pre-hook fallback: the RCU is a gamepad, so Godot can deliver dpad/A as
	# JOY_BUTTON_DPAD_* / JOY_BUTTON_A instead of keys.
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if pad.pressed:
			var pad_act := PSRemote.joy_action_for(pad.button_index)
			if pad_act != PSRemote.ACT_NONE:
				_dispatch_action(pad_act)
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if _keys_diag:
		print(PSRemote.key_line(key))
	# Desktop-only debug overlay toggle; not a menu action.
	if key.pressed and not key.echo and key.keycode == KEY_F3:
		_show_debug = not _show_debug
		get_viewport().set_input_as_handled()
		return
	# Device verification hooks (work from `adb shell input keyevent`):
	# F4 = camera live on/off, F5 = 1P PiP placement, F6 = camera variant,
	# F7 = pose-mirror toggle. On the box the native hook canonicalises remote
	# MENU (82) -> KEYCODE_F6 and INFO (165) -> KEYCODE_F7, so both remote keys
	# reach these branches; adb F6/F7 are left unmapped by the hook and arrive
	# here as normal keys.
	if key.pressed and not key.echo and key.keycode == KEY_F4:
		_toggle_camera_live()
		get_viewport().set_input_as_handled()
		return
	if key.pressed and not key.echo and key.keycode == KEY_F5:
		_cycle_camera_rect()
		get_viewport().set_input_as_handled()
		return
	if key.pressed and not key.echo and key.keycode == KEY_F6:
		_cycle_camera_mode()
		get_viewport().set_input_as_handled()
		return
	if key.pressed and not key.echo and key.keycode == KEY_F10:
		# Owner-requested always-on perf window (adb: `input keyevent 141`).
		_toggle_perf_panel("F10")
		get_viewport().set_input_as_handled()
		return
	if key.pressed and not key.echo and (key.keycode == KEY_F9 or (
			_tuning_panel == null and (key.keycode == KEY_HELP or key.keycode == KEY_SEARCH))):
		# Live skeleton overlay toggle. F9 is the documented key: Android
		# KEYCODE_F9 = 139, so `adb shell input keyevent 139` flips it (F1 = 131,
		# so F9 = 139 and F10 = 140, which the perf panel already uses - 142 is
		# F12, not F9). KEY_HELP / KEY_SEARCH are the only remote-ish keys the
		# native hook leaves untouched and no shipped action owns (they are the
		# tuning panel's fallbacks, so they are only taken when that panel does
		# not exist in this build); no physical button on this box is known to
		# send them, so F9 stays the guaranteed path.
		_toggle_skeleton("F9")
		get_viewport().set_input_as_handled()
		return
	if key.pressed and not key.echo and key.keycode == KEY_F7:
		# F7 = flip the mirror box's RGBA frame (the owner's device check).
		# Ctrl+F7 keeps the pose-handedness toggle on a keyboard; the remote INFO
		# key, which the native hook canonicalises to KEY_F7, now flips the camera.
		#
		# RCU path for the perf panel: a SECOND F7 within PERF_TAP_MS cancels that
		# flip and toggles the panel instead. The native hook only maps MENU->F6 and
		# INFO->F7, MENU/F6 is taken by the camera-variant cycle and `android/**`
		# is out of scope for this batch, so a double tap on INFO is the one spare
		# gesture the shipped hook can deliver. A single tap is unchanged.
		if key.ctrl_pressed:
			_toggle_pose_mirror("key")
		else:
			var now_ms := Time.get_ticks_msec()
			if now_ms - _perf_f7_ms <= PERF_TAP_MS:
				_perf_f7_ms = -100000
				_toggle_camera_flip()
				_toggle_perf_panel("RCU INFO x2")
			else:
				_perf_f7_ms = now_ms
				_toggle_camera_flip()
		get_viewport().set_input_as_handled()
		return
	# Internal debug tuning panel (only exists when `PSBuild.TUNING_ENABLED`):
	# F8 / MENU / SEARCH / HELP toggle it. With the flag off `_tuning_panel` is
	# null, so this is one constant-folded test and the key falls through to the
	# normal router.
	if key.pressed and not key.echo and _tuning_panel != null \
			and PSRemote.is_panel_key(key.keycode):
		_tuning_panel.toggle()
		get_viewport().set_input_as_handled()
		return
	if not key.pressed or key.echo:
		return
	# keycode covers Android's translated code; physical covers hardware-only
	# reports (some boxes fill just one of the two).
	var act := PSRemote.action_for(key.keycode)
	if act == PSRemote.ACT_NONE and key.physical_keycode != key.keycode:
		act = PSRemote.action_for(key.physical_keycode)
	# Last resort, stock template only: a raw Android keycode reached GDScript.
	# `unicode == 0` keeps printable keys (e.g. Godot's KEY_B == 66) out of it.
	if act == PSRemote.ACT_NONE and OS.has_feature("android") and key.unicode == 0:
		act = PSRemote.android_action_for(key.keycode)
		if act == PSRemote.ACT_NONE and key.physical_keycode != key.keycode:
			act = PSRemote.android_action_for(key.physical_keycode)
	if act == PSRemote.ACT_NONE:
		return
	_dispatch_action(act)
	get_viewport().set_input_as_handled()


## Android sends BACK twice: the native key event (KEY_BACK) and the window's
## go_back_requested signal. Both feed this method, which de-duplicates them.
func _on_go_back_requested() -> void:
	_dispatch_action(PSRemote.ACT_BACK)


## Single action entry point. Duplicate guard: the same action in one frame OR
## within DUP_ACTION_MS is ignored (never a second activation). The native hook
## already consumes the original event, so this is the cross-channel backstop.
func _dispatch_action(action: int) -> void:
	if action == PSRemote.ACT_NONE:
		return
	# The internal tuning panel owns every action while it is open: same router,
	# no second input path. `_tuning_panel` is always null in a shipped build.
	if _tuning_panel != null and _tuning_panel.open:
		if _tuning_panel.handle(action):
			return
	var frame := Engine.get_process_frames()
	var now := Time.get_ticks_msec()
	if action == _last_action and (frame == _last_action_frame or now - _last_action_ms < DUP_ACTION_MS):
		return
	_last_action = action
	_last_action_frame = frame
	_last_action_ms = now
	if action == PSRemote.ACT_BACK:
		# The engine's go_back_requested signal and the raw KEY_BACK event for one
		# physical press land in the same frame (or one frame apart).
		if frame - _last_back_frame <= 1:
			return
		_last_back_frame = frame
	match mode:
		MODE_SELECT:
			_act_select(action)
		MODE_READY:
			# No OK action here: only body tracking confirms a slot.
			if action == PSRemote.ACT_BACK:
				_enter_select("back")
		MODE_COUNTDOWN:
			if action == PSRemote.ACT_BACK:
				_enter_select("back")
		MODE_PLAY:
			# Gameplay steering is pose only, so DPAD is ignored here.
			if action == PSRemote.ACT_OK:
				_toggle_pause("ok")
			elif action == PSRemote.ACT_BACK:
				_toggle_pause("back")
		MODE_PAUSE:
			_act_pause(action)
		MODE_SETTLE:
			_act_settle(action)


## MODE_SELECT: DPAD walks one ladder, OK confirms the focus, BACK leaves the app.
## There is no default focus; OK without a focus does nothing.
##
## Ladder (focus slots, mirrored in `ps_hud.gd`):
##     0 单人模式 · 1 双人模式 · 2 角色 · 3 玩法说明 · 4 音效 · 5 赛制 -> wraps to 0
##
## LEFT/RIGHT actuate the focused row the same way everywhere: they step the
## character, flip 音效 开/关 and switch 限时/无尽 (and open the rules card on the
## 玩法说明 row), while on the two mode cards they keep their old focus meaning.
## That keeps the interaction one-handed on a 5-key remote — the box has no INFO/
## MENU key that the app may consume for a settings panel.
func _act_select(action: int) -> void:
	# The rules card owns the screen while it is open: OK and BACK close it, every
	# other key is swallowed (so a stray DPAD cannot change a setting behind it).
	if help_open:
		if action == PSRemote.ACT_OK or action == PSRemote.ACT_BACK:
			help_open = false
			hud.help_open = false
			audio.play(&"pickup")
			print("[ui] how-to-play closed")
		return
	var on_skin := select_focus == SKIN_FOCUS
	match action:
		PSRemote.ACT_LEFT:
			if on_skin:
				_step_skin(-1)
			elif select_focus == OPT_SOUND:
				_toggle_audio()
			elif select_focus == OPT_ROUND:
				_cycle_round_mode()
			elif select_focus == OPT_HELP:
				_open_help()
			else:
				select_focus = 0 if select_focus < 0 else maxi(0, select_focus - 1)
			hud.select_focus = select_focus
		PSRemote.ACT_UP:
			if select_focus < 0:
				select_focus = 0
			elif select_focus == 0:
				select_focus = SELECT_SLOTS - 1
			else:
				select_focus -= 1
			hud.select_focus = select_focus
		PSRemote.ACT_RIGHT:
			if on_skin:
				_step_skin(1)
			elif select_focus == OPT_SOUND:
				_toggle_audio()
			elif select_focus == OPT_ROUND:
				_cycle_round_mode()
			elif select_focus == OPT_HELP:
				_open_help()
			else:
				select_focus = 1 if select_focus < 0 else mini(1, select_focus + 1)
			hud.select_focus = select_focus
		PSRemote.ACT_DOWN:
			if select_focus < 0:
				select_focus = 1
			elif select_focus >= SELECT_SLOTS - 1:
				select_focus = 0
			else:
				select_focus += 1
			hud.select_focus = select_focus
		PSRemote.ACT_OK:
			match select_focus:
				SKIN_FOCUS:
					# OK on the row is a second way to step it (never a dead key)
					_step_skin(1)
				OPT_HELP:
					_open_help()
				OPT_SOUND:
					_toggle_audio()
				OPT_ROUND:
					_cycle_round_mode()
				-1:
					print("[ui] OK ignored: mode select has no default (DPAD first)")
				_:
					_on_hud_button(BTN_MODE_1P if select_focus == 0 else BTN_MODE_2P)
		PSRemote.ACT_BACK:
			_background_or_quit()


## 音效 开/关. `PSAudio.muted` is the single switch the SFX pool reads, and the
## choice is persisted (`[audio] muted`), so it survives a restart.
func _toggle_audio() -> void:
	_audio_on = not _audio_on
	audio.set_muted(not _audio_on)
	PSSettings.set_muted(not _audio_on)
	hud.audio_on = _audio_on
	print("[audio] SFX %s (muted=%s, saved to %s)" % [
		"on" if _audio_on else "off", str(not _audio_on), PSSettings.SETTINGS_PATH])
	if _audio_on:
		audio.play(&"pickup")


## 赛制 限时 2:00 <-> 无尽练习. The rules core reads `cfg.round.mode` every frame
## (`game.gd:445,1301`), so switching it here is enough: a timed round counts down
## and settles, endless never does. Persisted (`[round] mode`).
func _cycle_round_mode() -> void:
	var endless: bool = String(cfg.round.mode) != PSSettings.MODE_ENDLESS
	cfg.round.mode = StringName(PSSettings.MODE_ENDLESS if endless else PSSettings.MODE_TIMED)
	PSSettings.set_round_mode(String(cfg.round.mode))
	hud.round_mode = String(cfg.round.mode)
	audio.play(&"pickup")
	print("[round] mode=%s (%s, saved to %s)" % [String(cfg.round.mode),
		"practice, never settles" if endless else "2:00 ranked", PSSettings.SETTINGS_PATH])


func _open_help() -> void:
	help_open = true
	hud.help_open = true
	audio.play(&"pickup")
	print("[ui] how-to-play opened (OK/BACK closes)")


## MODE_SELECT BACK: the reference's `ModelForm` does `MoveTaskToBack(true)` — it
## backgrounds the TV app and the box returns to its launcher, it does NOT kill the
## process (`ModelForm.cs:88-95`). The same call has to be exposed by the Android
## plugin (`@UsedByGodot public void moveTaskToBack(boolean)`); today it is not, so
## this keeps a `quit()` fallback and prints WHICH path ran for the device log.
## No `OS.shell_open` is involved either way.
func _background_or_quit() -> void:
	var via := "plugin"
	var ok := false
	if Engine.has_singleton(PLUGIN_SINGLETON):
		var plugin: Object = Engine.get_singleton(PLUGIN_SINGLETON)
		if plugin != null and plugin.has_method("moveTaskToBack"):
			plugin.call("moveTaskToBack", true)
			ok = true
	if not ok:
		via = "quit"
	_flow_to("background" if ok else "quit", "back from mode_select via " + via)
	print("[ui] BACK on mode_select -> %s" % ("MoveTaskToBack (plugin binding)" if ok
		else "quit() (no moveTaskToBack binding in the plugin; reference = MoveTaskToBack)"))
	if not ok:
		get_tree().quit()


## The character row's slot on the mode-select screen (mirrors
## `ps_hud.gd:SKIN_FOCUS`; 0/1 are the two mode cards).
const SKIN_FOCUS := 2
## Options bar under the title slab (mirrors `ps_hud.gd` OPT_*). One ladder:
## 1人 -> 2人 -> 角色 -> 玩法说明 -> 音效 -> 赛制 -> 1人.
const OPT_HELP := 3
const OPT_SOUND := 4
const OPT_ROUND := 5
const SELECT_SLOTS := 6


func _step_skin(dir: int) -> void:
	PSSkins.step_player_skin(dir)
	print("[skin] player -> %s (%s)" % [PSSkins.name_of(PSSkins.player_skin),
		String(PSSkins.get_skin(PSSkins.player_skin)["slug"])])


## Deal the character pack to this round's field. Called from `_enter_ready`
## after `game.reset()`, i.e. exactly once per round, so the line-up is stable
## while the round runs and is re-rolled by the next reset.
func _assign_skins() -> void:
	if PSSkins.count() == 0 or game == null:
		return
	PSSkins.assign_round(game.snakes, game.round_index * 2654435761 + 977)
	var line := ""
	for s in game.snakes:
		line += " %s" % String(PSSkins.get_skin(PSSkins.of(s)).get("slug", "?"))
	print("[skin] round=%d line-up:%s" % [game.round_index, line])


## MODE_PAUSE: UP/LEFT and DOWN/RIGHT cycle 继续游戏 / 重新开局 / 返回模式选择.
## BACK closes the pause scrim (resume); use the menu item to leave the round.
func _act_pause(action: int) -> void:
	match action:
		PSRemote.ACT_LEFT, PSRemote.ACT_UP:
			pause_focus = (pause_focus + PAUSE_ACTION_COUNT - 1) % PAUSE_ACTION_COUNT
			hud.pause_focus = pause_focus
		PSRemote.ACT_RIGHT, PSRemote.ACT_DOWN:
			pause_focus = (pause_focus + 1) % PAUSE_ACTION_COUNT
			hud.pause_focus = pause_focus
		PSRemote.ACT_OK:
			match pause_focus:
				0:
					_on_hud_button(BTN_RESUME)
				1:
					_on_hud_button(BTN_RESTART)
				_:
					_on_hud_button(BTN_MENU)
		PSRemote.ACT_BACK:
			_toggle_pause("back_resume")


## MODE_SETTLE: 再来一局 / 返回模式选择; BACK always goes to mode select.
##
## The camera-rise is skippable: OK finishes it in place (the two actions become
## live immediately, focus already on 再来一局) and BACK finishes it **and**
## leaves in the same press, so BACK on the settlement is always one press —
## "skip" never turns into a press the player has to repeat to get out.
func _act_settle(action: int) -> void:
	if stage != null and not stage.settled:
		if action == PSRemote.ACT_OK:
			stage.skip()
			audio.play(&"pickup")
			print("[ui] settlement rise skipped (OK)")
			return
		if action == PSRemote.ACT_BACK:
			stage.skip()
			_enter_select("settle_back_skip")
			return
	match action:
		PSRemote.ACT_LEFT, PSRemote.ACT_UP:
			settle_focus = 0
			stage.focus = 0
		PSRemote.ACT_RIGHT, PSRemote.ACT_DOWN:
			settle_focus = 1
			stage.focus = 1
		PSRemote.ACT_OK:
			_on_stage_button(BTN_RETRY if settle_focus == 0 else BTN_STAGE_MENU)
		PSRemote.ACT_BACK:
			_enter_select("settle_back")
