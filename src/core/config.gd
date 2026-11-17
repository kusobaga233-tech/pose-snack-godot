extends RefCounted
## Every tunable of the pose-snake rules, ported 1:1 from `js/config.js`.
##
## Conventions
## -----------
## * Names are the JS camelCase names converted to snake_case; values are unchanged.
## * Distances are *world pixels*, time is *seconds*, angles are *radians* in the
##   canvas/Screen convention: 0 = +X (right), +PI/2 = +Y (down). Godot 2D uses the
##   same axis order, so the core needs no coordinate flip anywhere.
## * `world.w` / `world.h` are derived from `tile_w * tiles_x` = 4800 x 2700.
## * Sections that only exist because the prototype ran in a browser are omitted:
##   `boot` (getUserMedia / model-load watchdogs) and `poseLog` (telemetry export).
##   Both live in the browser app, never in the rules.
## * `device_profile` is the one addition that config.js does not have: a named
##   override set for weak hardware (the Amlogic box). See `apply_device_profile`.

const PROFILE_DESKTOP := &"desktop"
const PROFILE_LOW_END := &"low_end"

## Sentinel colour meaning "not supplied" in `PSGame.make_food()` (JS uses `undefined`).
const NO_COLOR := Color(-1.0, -1.0, -1.0, -1.0)


# ---------------------------------------------------------------- world / view

class WorldCfg extends RefCounted:
	## World = 3 x 3 screens of 1600 x 900.
	var tile_w: float = 1600.0
	var tile_h: float = 900.0
	var tiles_x: int = 3
	var tiles_y: int = 3
	## Derived size in world pixels (JS `WORLD`).
	var w: float = 4800.0
	var h: float = 2700.0

	func refresh() -> void:
		w = tile_w * float(tiles_x)
		h = tile_h * float(tiles_y)


class ViewCfg extends RefCounted:
	## Short viewport edge decides the world span; the long edge follows the aspect.
	var w: float = 1600.0
	var h: float = 900.0
	var phone_break_css: float = 620.0
	var phone_short_span: float = 640.0
	var phone_anchor_css: float = 390.0
	var phone_span_min: float = 380.0
	var phone_span_max: float = 780.0
	var split_span_boost: float = 1.5
	var max_view_h: float = 1900.0


class CameraCfg extends RefCounted:
	var follow: float = 9.0
	var lookahead: float = 140.0
	var lookahead_max: float = 240.0


# ---------------------------------------------------------------------- snake

class KillRewardCfg extends RefCounted:
	var enabled: bool = true
	## Length the loser is worth, as a fraction of its segment count.
	var absorb: float = 0.28
	var min_gain: float = 8.0
	var max_gain: float = 42.0
	## Immunity (seconds) granted to the winner of an absorb.
	var immunity_ms: float = 500.0
	var player_mul: float = 2.00
	var ai_mul: float = 0.30


class GirthCfg extends RefCounted:
	## Radius grows linearly from 1.00x at `start_segments` to `default` at
	## `at_segments`, then caps. The same radius drives collision and rendering.
	var enabled: bool = true
	var min: float = 1.00
	var max: float = 2.00
	var default: float = 2.00
	var at_segments: float = 120.0
	var curve: float = 1.0


class SnakeCfg extends RefCounted:
	var start_segments: int = 16
	var seg_dist: float = 18.0
	var radius: float = 22.0
	var base_speed: float = 300.0
	var grow_per_food: int = 1
	var grow_per_big_food: int = 3
	var grow_per_kill: int = 5
	var wall_pad: float = 10.0
	var kill_reward := KillRewardCfg.new()
	var girth := GirthCfg.new()


class SlowdownCfg extends RefCounted:
	## speed = base * (1 - strength * (1 - e^(-extra / scale)))
	var strength: float = 0.20
	var strength_min: float = 0.0
	var strength_max: float = 0.80
	var scale: float = 60.0
	var scale_min: float = 15.0
	var scale_max: float = 180.0


class TurnCfg extends RefCounted:
	## Base rotational speed in radians/second (the hard turn-rate cap).
	var rate: float = 8.5
	var rate_min: float = 2.0
	var rate_max: float = 18.0
	## Compensation when the requested turn is close to a U-turn.
	var reverse_boost: float = 1.35


# ----------------------------------------------------------------------- food

class FoodCfg extends RefCounted:
	var target_count: int = 195
	var radius: float = 24.0
	var spawn_margin: float = 90.0
	var min_dist_from_snake: float = 70.0
	var big_chance: float = 0.08
	## Eat radius = snake radius + food radius * eat_padding.
	var eat_padding: float = 0.82
	## Refill pacing: at most one batch per cooldown, `spawn_per_frame` per batch.
	var spawn_cooldown_sec: float = 0.2
	var spawn_per_frame: int = 8
	var trim_extra: int = 70
	var scatter_max: int = 64


class PickupBuffCfg extends RefCounted:
	var duration_sec: float = 5.0
	var speed_mul: float = 1.65
	var color: Color = Color("FFD93D")
	var label: String = "加速"


class MagnetCfg extends RefCounted:
	var duration_sec: float = 10.0
	var radius: float = 300.0
	var pull_speed: float = 620.0
	var color: Color = Color("5BC8FF")
	var label: String = "磁铁"


class PowerupsCfg extends RefCounted:
	var enabled: bool = true
	var ai_can_pickup: bool = true
	var target_count: int = 7
	var spawn_sec: float = 5.0
	var radius: float = 26.0
	var pickup_radius: float = 30.0
	var spawn_margin: float = 180.0
	var min_dist_from_snake: float = 160.0
	var boost := PickupBuffCfg.new()
	var magnet := MagnetCfg.new()


# ------------------------------------------------------------------------- AI

class PressureCfg extends RefCounted:
	## Difficulty at or below `start` keeps `pressure` at exactly 0 (legacy behaviour).
	var start: float = 0.5
	var default: float = 1.0
	var min: float = 0.0
	var max: float = 1.0


class HuntCfg extends RefCounted:
	var enabled: bool = true
	## Length ratio needed to attack at full pressure (>= 1 means "not shorter").
	var ratio: float = 1.02
	var range_add: float = 260.0
	var aggression_add: float = 0.85
	## Lead the target by this many seconds of its own travel.
	var lead_sec: float = 0.55
	var lead_max: float = 280.0
	## Lateral cut-in as a fraction of the lead distance (body-blocking).
	var cut_in: float = 0.40
	var player_focus: float = 1.45


class SurvivalCfg extends RefCounted:
	var enabled: bool = true
	var wall_probe_add: float = 110.0
	var wall_push_add: float = 0.85
	var sense_add: float = 0.30


class LeaderCfg extends RefCounted:
	## AI-only "don't fall behind the player" fractional growth.
	var enabled: bool = true
	var max_bonus: float = 0.30
	var edge_scale: float = 60.0


class DifficultyCfg extends RefCounted:
	var level: float = 0.85
	var level_min: float = 0.0
	var level_max: float = 1.0
	var mistake_rate: float = 0.10
	var mistake_min: float = 0.0
	var mistake_max: float = 1.0
	var turn_floor: float = 0.34
	var sense_floor: float = 0.38
	var reaction_max_sec: float = 0.50
	var aim_noise_max: float = 0.55
	var attack_bonus: float = 2.2
	var sloppy_food_max: float = 0.55
	var retarget_max_sec: float = 1.1
	var lapse_per_sec: float = 0.40
	var lapse_min_sec: float = 0.25
	var lapse_max_sec: float = 0.85
	var lapse_turn_max: float = 0.95


class SelfAvoidCfg extends RefCounted:
	var enabled: bool = true
	var look_ahead: float = 162.0
	var danger_mul: float = 1.25
	var danger_r_min: float = 34.0
	var skip: int = 8
	var step: int = 2
	var escape_turn: float = 1.15


class AntiLoopCfg extends RefCounted:
	var enabled: bool = true
	var window_sec: float = 2.0
	var turn_deg: float = 180.0
	var path_ratio: float = 0.75
	var escape_sec: float = 1.2
	var escape_turn: float = 0.18
	var blacklist_sec: float = 2.6


class SelfHitCfg extends RefCounted:
	## AI-only forgiveness: start scanning later and shrink the hit radius.
	var skip: int = 12
	var radius_mul: float = 0.45


class StyleCfg extends RefCounted:
	var key: StringName = &"steady"
	var label: String = "稳健"
	var attack_mul: float = 1.0
	var aggression_mul: float = 1.0
	var avoid_mul: float = 1.0
	var sense_mul: float = 1.0
	var sloppy_mul: float = 1.0
	var lapse_mul: float = 1.0
	var food_weight: float = 0.55
	var big_food_bias: float = 1.0
	var flee_mul: float = 1.0


class StylesCfg extends RefCounted:
	var enabled: bool = true
	var pool: Array = []
	## Neutral style used when a brain has none assigned (JS `NEUTRAL_STYLE`):
	## all multipliers are 1 except `food_weight` = 0.55, i.e. exactly the legacy
	## "chase food with weight 0.55" behaviour. Defaults of `StyleCfg` encode it.
	var neutral := StyleCfg.new()


class HeadStyleCfg extends RefCounted:
	var enabled: bool = true
	## Pool of 9, 7 AI per round -> two styles sit out each round.
	var pool: Array = []


class AiCfg extends RefCounted:
	var count: int = 7
	var respawn_delay: float = 3.0
	var skill_min: float = 0.62
	var skill_max: float = 0.96
	var speed_jitter: float = 0.1
	var wander_radius: float = 900.0
	var avoid_radius: float = 230.0
	var probe_dist: float = 190.0
	var attack_ratio: float = 1.45
	## Food only counts as a target inside +-this many radians of the heading.
	var food_fov: float = 1.92
	var pressure := PressureCfg.new()
	var hunt := HuntCfg.new()
	var survival := SurvivalCfg.new()
	var leader := LeaderCfg.new()
	## AI growth multiplier while pressure is active (player is always 1.0).
	var food_mul: float = 0.60
	var difficulty := DifficultyCfg.new()
	var self_avoid := SelfAvoidCfg.new()
	var anti_loop := AntiLoopCfg.new()
	var self_hit := SelfHitCfg.new()
	var styles := StylesCfg.new()
	var head_style := HeadStyleCfg.new()


# ---------------------------------------------------------------------- round

class PlayerColorCfg extends RefCounted:
	var color: Color = Color.WHITE
	var head: Color = Color.WHITE
	var grad: Array = []


class RoundCfg extends RefCounted:
	## &"timed" = 2 minute ranked round | &"endless" = practice, never settles.
	var mode: StringName = &"timed"
	var duration_sec: float = 120.0
	var last_call_sec: float = 10.0
	var best_length_key: String = "poseSnakeBestLength"
	var total_players: int = 8
	var player_colors: Array = []
	var player_names: Array = []


class PlayerCfg extends RefCounted:
	var respawn_delay: float = 3.0
	## Immunity after respawn (may outlast the freeze).
	var immunity: float = 1.4
	## Respawn/round-start freeze: no movement, only heading input, always immune.
	var respawn_freeze: float = 0.5
	var respawn_freeze_min: float = 0.0
	var respawn_freeze_max: float = 1.5
	## ---- respawn border inset (owner 2026-11-17: 复活点不要贴着墙) ------------
	## A respawn must sit at least HALF A SCREEN away from the arena border, i.e.
	## inside the arena inset by half the visible extent. The 1P camera span is
	## 1963.6 x 900 world px (short edge = CAM_SPAN 900, long edge follows the
	## 1920x880 arena aspect), so half of it is 981.8 x 450. Both halves are
	## rounded UP here (982 / 450) so the inset is literally never less than half
	## a screen: the owner's "~960x440" is the unfudged design-canvas half.
	## `PSGame.respawn_point()` searches inside this inset; `Vector2.ZERO` (or any
	## non-positive edge) restores the pre-inset random rule, which is only used
	## by the measurement harness (`--capture-respawn --respawn=before`).
	## This is a rule tunable, not a presentation value: the core does not know
	## the camera, it knows the arena the owner wants the snake kept inside.
	var respawn_inset: Vector2 = Vector2(982.0, 450.0)
	## Minimum distance from a respawn point to every LIVING snake head (world px).
	## Both keep the pre-inset clearance values: humans 1100 (the JS rule), AI 1200
	## ("AI respawns somewhere far away"). Nothing else about the clearance changed.
	var respawn_clear_human: float = 1100.0
	var respawn_clear_ai: float = 1200.0


class CollideCfg extends RefCounted:
	## Head vs its OWN body. `false` (default, a deliberate port deviation from
	## the JS prototype) makes the overlap a complete no-op: no death, no respawn
	## timer, no corpse scatter, no kill credit, no immunity and no presentation
	## event -- the snake simply passes through itself. `true` restores the JS
	## rule ("head vs own body -> dies", with the `ai.self_hit` forgiveness window
	## for AI) and exists so the old behaviour stays reachable for tests and
	## side-by-side comparison. Enemy collisions are unaffected by this switch.
	var self_kill: bool = false
	## Head-vs-head radius = average of both snake radii * this.
	var head_radius: float = 2.05
	## Both agents must charge at >= this cosine to count as head-on.
	var head_on_cos: float = 0.55
	## Equal length head-on: both die (io rules). false = both survive.
	var even_length_both_die: bool = true


# ----------------------------------------------------------------------- pose

class PoseSpeedCfg extends RefCounted:
	var min: float = 0.65
	var max: float = 1.80
	## Normalised wrist distance at which `min` / `max` are reached. Measured from
	## the ACTIVE REFERENCE (right shoulder, see `PoseCfg.ref_joint`), so these are
	## shoulder-scale numbers: the dead zone holds below 0.70, the hand rests on the
	## chest at 0.585, and the measured reaches are 0.900 (forward) / 0.950
	## (raised) / 1.150 (sideways) - see `evidence/pose-trace-shoulder-ref.txt`.
	##
	## 2026-11-17 (owner: 极限速度较慢，手伸出去很远但是角色没有明显加速): option 1,
	## lower the "max speed" threshold so the SAME gesture produces noticeably more
	## speed. The old pair 0.80 / 1.10 put the forward reach (0.900) at only 33% of
	## the range; `far = 0.96` was the first candidate and still left it at 62.5%,
	## i.e. below the 80% target, so the shipped value is 0.92:
	##     (0.900 - 0.80) / (0.92 - 0.80) = 83.3% of the range
	##     0.585 chest    -> min 0.65 (inside the 0.70 hold: the target is frozen)
	##     0.900 forward  -> 1.61 (482 px/s; was 1.03 / 310 px/s)
	##     0.950 raised   -> 1.80 (540 px/s) - pinned at max: the accepted trade-off
	##     1.150 sideways -> 1.80 (already max before)
	## `near` stays 0.80 so a hand pulled in to 0.70..0.80 still reaches the minimum
	## BEFORE the dead zone freezes the target. Measured in
	## `evidence/pose-trace-speed-before.txt` vs `...-speed-after.txt`. The chest-era
	## pair was 0.30 / 0.75.
	var near: float = 0.80
	var far: float = 0.92
	## Low-pass time constant (seconds).
	var smooth: float = 0.09
	## Max multiplier change per second.
	var slew: float = 3.00
	## Slider limits (also the hard clamp applied to the output).
	var min_limit: float = 0.40
	var min_ceil: float = 1.00
	var max_floor: float = 1.00
	var max_limit: float = 1.80
	var near_min: float = 0.10
	## Raised from 0.80 when the reference moved to the shoulder: a sideways reach
	## is 1.15 torso lengths, so the slider must be able to follow it.
	var near_max: float = 1.20
	var far_min: float = 0.40
	var far_max: float = 2.00
	var smooth_max: float = 0.60
	## ---- symmetric speed distance (owner 2026-11-17: 左/上伸手比右慢) ---------
	## `true` (shipped): the distance that feeds the curve is
	##     max(|rwr - rsh|, |lwr - lsh|) / torso
	## i.e. the MORE EXTENDED arm, with an arm that is below `pose.min_visibility`
	## or that is a PASSIVE hanging arm (same posture test as the steering
	## `pose.hang_*` gate, applied per arm) left out of the max. Steering stays
	## right-wrist/right-shoulder only; the dead zone / hang / motion gates are
	## steering gates and no longer freeze the speed target.
	## `false` is the pre-fix law on the same gestures (right arm only, and the
	## steering holds still freeze the target): measurement only, wired to
	## `--capture-pose-trace --pose-arms=before`. Evidence:
	## `evidence/pose-trace-speed-arms-{before,after}.txt`.
	var both_arms: bool = true


class PoseBindCfg extends RefCounted:
	## ---- binding phase (owner: 做一个绑定阶段, 保证局内除非丢骨骼, 不然不会绑定到别人身上)
	## A slot OWNS a person id, it does not own a screen position. During READY a
	## slot may bind to the person that has been standing in its own screen area
	## (2P: left/right half; 1P: anywhere) for `stable_sec` AND whose READY raise
	## confirmation (main.gd's `ready_state == 2`) has completed. From COUNTDOWN on
	## the id is frozen: the slot follows that id only, and a missing id is never
	## replaced by another person - it coasts and then goes lost.
	##
	## Modelled on the 1024 project (`XXAndroidParseData.personPlayerIds` /
	## `personPlayerLockIng` + `readyNeedFrame`): a "locked" candidate becomes a
	## confirmed binding only after the raise hold, and both are cleared when the
	## person leaves the frame for long enough.
	var stable_sec: float = 0.50
	## COUNTDOWN/PLAY: how long a missing bound person keeps the slot coasting on
	## its last heading (the rules' own `pose.lost_timeout_ms` hold) before the slot
	## is reported lost. No substitution happens at any point in this window.
	var grace_sec: float = 1.00
	## READY only: how long the bound person may be gone before the slot drops the
	## binding and may take a new one. Long on purpose - a 0.3 s tracking dropout
	## during READY must not hand the slot to whoever walks past.
	var rebind_absent_sec: float = 3.00


class PoseMotionCfg extends RefCounted:
	## ---- motion awareness (owner: 手快速从最左边移动到最右边时蛇没有转头) ----
	## Both holds (dead zone, arm-hanging) latch on POSITION only, so a fast
	## horizontal sweep is held exactly where it crosses them: right under the
	## shoulder (hang cone) or right next to it (dead zone). This block measures the
	## wrist speed and lets a deliberate sweep override BOTH holds, so the published
	## angle follows the hand immediately; the `wrist_smooth`/`angle_smooth`
	## low-passes still run, so the published angle stays smooth.
	##
	## Units are TORSO LENGTHS PER SECOND (`|wrist - lag_filter| / torso / smooth`),
	## i.e. camera and body-size independent. Measured on the scripted gestures
	## (`evidence/pose-trace-fast-*.txt`):
	##   resting hand 0.0 | slow drift 0.1-0.5 | 2.1 s sweep ~1.3
	##   full-circle gesture ~1.5 | 0.35 s sweep ~7.4 | +-6 px jitter ~0.15
	## 1.60 sits above EVERY non-sweep gesture the trace scripts (the fastest is
	## the 4 s full circle at ~1.49 torso/s, which must keep the old hold law bit
	## for bit) and far below a fast sweep; the owner suggested 1.0-1.5 to start.
	var fast: float = 1.60
	## The override ends when the speed drops below this (hysteresis, a 2:1 ratio),
	## so a hand finishing a sweep cannot chatter between hold and free.
	var slow: float = 0.80
	## Consecutive fast frames before the override engages. A one-frame keypoint
	## jump is handled by `jump_dist` below; this counter is the second guard, so a
	## single noisy frame can never free the holds.
	var frames: int = 2
	## Time constant (seconds) of the lag filter the speed is measured from. The
	## estimator is `|wrist - lag| / smooth`, which is the true speed for a steady
	## motion and ~0.06 torso/s for white keypoint jitter (a raw frame-to-frame
	## difference would read ~1.5 torso/s on the same jitter and free the holds on a
	## completely still arm).
	var smooth: float = 0.10
	## A single-frame wrist step above this many torso lengths, while the hand was
	## NOT already moving, is a keypoint re-acquire (or the trace script's teleport
	## between gestures), not a hand movement: the speed measurement restarts there
	## instead of reading ~3-20 torso/s. The "was not already moving" half is what
	## keeps a real fast sweep at a 15 Hz pose rate (0.74 torso EVERY frame) out of
	## this branch - its steps are large on every frame, not once.
	var jump_dist: float = 0.25


class CenterXCfg extends RefCounted:
	var auto: bool = true
	var max_shift: float = 0.40
	var learn: float = 0.06
	var decay: float = 0.0004
	var min_samples: int = 45
	var min_span: float = 0.50
	var manual: float = 0.0
	var manual_min: float = -0.30
	var manual_max: float = 0.30


class PoseCfg extends RefCounted:
	## Steering REFERENCE joint - the origin of the steering vector
	## (`angle = atan2(wrist - ref)`) and the joint the HUD's lime dot marks.
	##   &"shoulder_r" - the RIGHT SHOULDER (`_indices()["rsho"]`: youdoo18 = 6,
	##                   coco18 = 2, blaze33 = 12). Owner: 把之前的胸前点位改到
	##                   肩膀 / 右手与右肩连点, 先只处理右侧.
	##   &"chest"      - the OLD chest point, `lerp(neck, waist, center_t)`. Kept
	##                   only so `--capture-pose-trace --pose-ref=chest` can
	##                   re-measure the previous pass on the same gestures.
	## The wrist end is the RIGHT wrist (`rwri`: youdoo18 = 10) for both values;
	## the left side is the later pass.
	var ref_joint: StringName = &"shoulder_r"
	## Chest point along the neck -> waist line (0 = neck, 0.35 = chest, 1 = waist).
	## Still the origin of the raise-to-start test (`wrist above centre`); it is
	## the steering reference only when `ref_joint` is &"chest".
	var center_t: float = 0.35
	var center_t_min: float = 0.0
	var center_t_max: float = 1.0
	var center_x := CenterXCfg.new()
	var speed := PoseSpeedCfg.new()
	var bind := PoseBindCfg.new()
	var motion := PoseMotionCfg.new()
	## How long a lost pose keeps steering with the last angle.
	var lost_timeout_ms: float = 1000.0
	var raise_to_start: float = 0.35
	var raise_hold_sec: float = 1.0
	var auto_start_sec: float = 1.0
	var raise_wait_max_sec: float = 8.0
	var force_start_sec: float = 2.5
	var cam_width: int = 960
	var cam_height: int = 720
	## Recognition robustness (bridge side, still part of the input contract).
	var min_confidence: float = 0.30
	var min_visibility: float = 0.25
	var hip_visibility: float = 0.35
	## Arm source for the FUTURE left-side pass. Steering is right-arm fixed today,
	## so this is not read by `PSPoseInput` yet: the auto-pick (wrist further from
	## the chest, with `arm_hysteresis` + `arm_min_dwell_sec`) still runs behind the
	## scenes for the raise test, and `&"auto"` is what to implement the later
	## left/right choice on. Do not read it as "which hand steers right now".
	var hand: StringName = &"auto"
	var infer_stale_ms: float = 120.0

	# ---- steering smoothing / hysteresis ----------------------------------
	# Owner report on device: 体感控制不是很灵敏 / 蛇没有按照我手挥动的轨迹移动 /
	# 有时会乱移动. Every value below is justified by the `--capture-pose-trace`
	# measurements in `evidence/pose-trace-*.txt`.
	#
	# 2026-11-14 second pass (owner: 把手胸连点改成右手与右肩连点, 先只处理右侧):
	# the steering origin moved from the chest to the RIGHT SHOULDER, so every
	# distance below is now measured from the shoulder. The filters are unchanged
	# (they are ratios/times, not lengths); the dead zone and the speed curve had
	# to be recalibrated because the same hand is now ~0.6 instead of ~0.0 torso
	# lengths away from the origin.

	## 2D exponential low-pass on the wrist AND the reference joint, seconds. The
	## angle is computed from the filtered vector, so keypoint jitter cannot
	## reach the target heading. 0 = off (that is the pre-fix law; the trace
	## harness compares against it). 0.08 s is the measured compromise: it kills
	## 22x of the frame-to-frame angle jitter for 0.067 s of added step latency
	## (`evidence/pose-trace-*.txt`).
	var wrist_smooth: float = 0.08
	## Circular low-pass on the angle itself (unwrap -> filter -> wrap), seconds.
	## Small on purpose: the position filter above already rejects the keypoint
	## noise (the trace shows 0.05 vs 0.06 s makes no measurable difference to the
	## tracking error) so this one only rides the discontinuities the position
	## filter cannot smooth - an arm switch is eased over ~3 tau, i.e. 0.15 s.
	## 0 = off.
	var angle_smooth: float = 0.05
	## Wrist-distance dead zone, measured from the ACTIVE REFERENCE JOINT:
	## `dist_n = |wrist - ref| / torso`. 0.70 of a torso length keeps a hand
	## resting on the chest inside the hold (chest-to-right-shoulder = 0.585 +-
	## 0.012 torso) while a straight arm is outside it (0.900 forward / 0.950
	## raised / 1.150 sideways - the measured distribution is in
	## `evidence/pose-trace-shoulder-ref.txt`). The chest-era value was 0.12.
	var deadzone: float = 0.70
	## ...and once inside, the wrist must climb back past `deadzone * this`
	## before the angle is allowed to move again (single threshold -> hysteresis).
	## 1.15 -> the hold releases at 0.805 (measured 0.811 by the extend ramp), i.e.
	## 0.089 below the forward reach (0.900). The chest-era 1.35 would put the
	## release at 0.945 - ABOVE that reach, so an arm extended forward would still
	## be held and never steer (with the 0.66 entry of the trace sweep it released
	## at 0.894, exactly ON the reach: evidence/pose-trace-dz-old-exit.txt).
	var deadzone_exit: float = 1.15

	# ---- ARM-HANGING hold (owner option B, 下垂识别, 2026-11-14) ------------
	# The dead zone above cannot cover a lowered arm: a hanging wrist sits 0.980
	# torso from the right shoulder, so it is OUTSIDE any hold that still lets a
	# sideways reach (1.150) through, and the vector points straight down -> the
	# snake steered 90 deg down and stayed there (`evidence/pose-trace-hang-before.txt`,
	# gesture `hang_down`). The wrist vector alone cannot tell "arm at rest" from
	# "reaching down", so the gate uses the two numbers that can:
	#   dy_n = (wrist.y - shoulder.y) / torso   (> 0 = wrist BELOW the shoulder)
	#   align = abs(dx_n) / dist_n              (sine of the angle out of vertical)
	# `hang_align` is that sine, i.e. a cone around "straight down":
	# 0.45 <=> 26.7 deg. A hanging arm is held (angle frozen, `conf=0`,
	# `reason=arm-low`, the slot stays valid) while
	#     dy_n >= hang_enter AND align <= hang_align
	# and is released only below `hang_exit` or outside `hang_align + 0.10`, so a
	# wrist hovering on the threshold cannot chatter. The deliberate downward
	# gesture stays available OUTSIDE the cone: press the hand down-and-outward
	# (dy 0.75, |dx| = 0.75 of the vector, 48.6 deg out of vertical) -> it steers.
	var hang_enter: float = 0.55
	var hang_exit: float = 0.45
	var hang_align: float = 0.45
	## Arm pick: the other wrist must be further from the chest than the chosen
	## one by this factor (1.15 flapped with two similarly extended arms). This
	## pick is NO LONGER the steering source (steering is right-arm fixed); it
	## stays for the raise-to-start test and for the later left-side option.
	var arm_hysteresis: float = 1.35
	## ...and the pick may not switch again for this many seconds (dwell).
	var arm_min_dwell_sec: float = 0.50


# ------------------------------------------------------------------------- fx

class ImpactLevelCfg extends RefCounted:
	var shake: float = 0.0
	var flash: float = 0.0
	var zoom: float = 0.0
	var hit_stop: float = 0.0


class ImpactCfg extends RefCounted:
	var food := ImpactLevelCfg.new()
	var big_food := ImpactLevelCfg.new()
	var kill := ImpactLevelCfg.new()
	var death := ImpactLevelCfg.new()


class HeadClarityCfg extends RefCounted:
	var enabled: bool = true
	var skip_star: bool = true
	var particle_mul: float = 0.55
	var spark_mul: float = 0.50
	var wave_mul: float = 0.62


class FxCfg extends RefCounted:
	var max_particles: int = 1600
	var head_clarity := HeadClarityCfg.new()
	var impact := ImpactCfg.new()


# -------------------------------------------------------------------- sections

var device_profile: StringName = PROFILE_DESKTOP

var world := WorldCfg.new()
var view := ViewCfg.new()
var camera := CameraCfg.new()
var snake := SnakeCfg.new()
var slowdown := SlowdownCfg.new()
var turn := TurnCfg.new()
var food := FoodCfg.new()
var powerups := PowerupsCfg.new()
var ai := AiCfg.new()
var round := RoundCfg.new()
var player := PlayerCfg.new()
var collide := CollideCfg.new()
var pose := PoseCfg.new()
var fx := FxCfg.new()


func _init() -> void:
	world.refresh()
	_build_styles()
	_build_head_styles()
	_build_player_colors()


func _build_styles() -> void:
	var pool: Array = ai.styles.pool
	pool.clear()
	pool.append(_style(&"bold", "冒险", 0.55, 1.60, 0.62, 0.90, 0.85, 1.35, 0.55, 1.00, 0.60))
	pool.append(_style(&"timid", "畏强", 1.90, 0.35, 1.50, 1.25, 1.00, 0.80, 0.55, 1.00, 2.20))
	pool.append(_style(&"greedy", "贪吃", 1.60, 0.40, 0.90, 1.00, 0.25, 0.80, 0.95, 0.55, 1.00))
	pool.append(_style(&"hunter", "好斗", 0.75, 1.90, 0.85, 1.10, 1.00, 1.00, 0.40, 1.00, 0.80))
	pool.append(_style(&"steady", "稳健", 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.55, 1.00, 1.00))


func _style(key: StringName, label: String, attack_mul: float, aggression_mul: float,
		avoid_mul: float, sense_mul: float, sloppy_mul: float, lapse_mul: float,
		food_weight: float, big_food_bias: float, flee_mul: float) -> StyleCfg:
	var s := StyleCfg.new()
	s.key = key
	s.label = label
	s.attack_mul = attack_mul
	s.aggression_mul = aggression_mul
	s.avoid_mul = avoid_mul
	s.sense_mul = sense_mul
	s.sloppy_mul = sloppy_mul
	s.lapse_mul = lapse_mul
	s.food_weight = food_weight
	s.big_food_bias = big_food_bias
	s.flee_mul = flee_mul
	return s


func _build_head_styles() -> void:
	## 9 NPC head styles, 7 AI per round -> no duplicates within a round.
	ai.head_style.pool.assign([
		&"googly", &"bucktooth", &"moustache", &"shocked", &"glitch",
		&"lowpoly", &"pixel", &"neon", &"block",
	])


func _build_player_colors() -> void:
	var p1 := PlayerColorCfg.new()
	p1.color = Color("B6FF57")
	p1.head = Color("B6FF57")
	p1.grad = [Color("B6FF57"), Color("5BEFA0"), Color("2FD6C8"), Color("1FA8D8")]
	var p2 := PlayerColorCfg.new()
	p2.color = Color("FF7AD9")
	p2.head = Color("FF9BE4")
	p2.grad = [Color("FFC2F0"), Color("FF7AD9"), Color("FF5CA8"), Color("FF8A4D")]
	round.player_colors.assign([p1, p2])
	round.player_names.assign(["你", "玩家 2"])


# -------------------------------------------------------------- device profile

## Apply a named hardware profile. `desktop` restores the JS defaults exactly;
## `low_end` is the Amlogic-box set (fewer foods / fewer particles / less churn).
## Everything here is still a normal tunable: callers may override any field
## after applying a profile.
func apply_device_profile(profile: StringName) -> void:
	device_profile = profile
	# Always restore the JS defaults first so switching profiles is idempotent.
	food.target_count = 195
	food.spawn_per_frame = 8
	food.trim_extra = 70
	food.scatter_max = 64
	powerups.target_count = 7
	fx.max_particles = 1600
	match profile:
		PROFILE_LOW_END:
			# Weak box: ~40% fewer food nodes to iterate + smaller scatter bursts.
			food.target_count = 120
			food.spawn_per_frame = 6
			food.trim_extra = 40
			food.scatter_max = 32
			powerups.target_count = 5
			fx.max_particles = 700
		_:
			pass


# ------------------------------------------------------------------- formulas

## Snake radius (visual + collision share this single source of truth).
## JS `snakeRadius(segments)`; `girth_max` is the runtime slider value
## (`TUNING.girthMax`), clamped into [girth.min, girth.max].
func snake_radius(segments: float, girth_max: float = NAN) -> float:
	var G := snake.girth
	var r0 := snake.radius
	if not G.enabled:
		return r0
	var ln := segments if is_finite(segments) else float(snake.start_segments)
	var top := girth_max if is_finite(girth_max) else G.default
	var mul_top := minf(G.max, maxf(G.min, top))
	var start := float(snake.start_segments)
	var span := maxf(1.0, G.at_segments - start)
	var t := clampf((ln - start) / span, 0.0, 1.0)
	var curve := G.curve if G.curve > 0.0 else 1.0
	var mul := 1.0 + (mul_top - 1.0) * pow(t, curve)
	return r0 * mul


## Unified "AI pressure" (JS `computeAiPressure`).
## Difficulty <= pressure.start yields exactly 0 so legacy behaviour is bit-equal.
func compute_ai_pressure(level: float, pressure: float) -> float:
	var P := ai.pressure
	var D := ai.difficulty
	var lv := level if is_finite(level) else D.level
	var pr := pressure if is_finite(pressure) else P.default
	var a := clampf((lv - P.start) / maxf(1e-3, 1.0 - P.start), 0.0, 1.0)
	var b := clampf(pr, P.min, P.max)
	return a * b
