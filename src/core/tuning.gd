extends RefCounted
## Runtime "feel" parameters — JS `TUNING`.
##
## The Web prototype keeps a mutable TUNING object that the debug sliders write
## into, and the rules read it every frame. The Godot core does the same: one
## instance per game, owned by the caller, read by `PSSnake` / `PSBrain` / `PSGame`.
##
##     var cfg := preload("res://src/core/config.gd").new()
##     var tuning := preload("res://src/core/tuning.gd").new(cfg)
##     tuning.ai_level = 0.5      # live slider, no rebuild needed
##
## `snake_radius()` is the one place that also depends on `girth_max`, so anything
## that measures a snake passes `tuning.girth_max` through.

const PSConfig = preload("res://src/core/config.gd")

var turn_rate: float = 8.5
var slow_strength: float = 0.20
var slow_scale: float = 60.0
var respawn_freeze: float = 0.5
var ai_level: float = 0.85
var ai_mistake: float = 0.10
var ai_pressure: float = 1.0
var girth_max: float = 2.0
var head_style_on: bool = true

var _cfg: PSConfig = null


func _init(cfg: PSConfig = null) -> void:
	_cfg = cfg
	if _cfg != null:
		reset_from_config()


## Restore every value to the `config.js` default (TUNING's initial state).
func reset_from_config() -> void:
	if _cfg == null:
		return
	turn_rate = _cfg.turn.rate
	slow_strength = _cfg.slowdown.strength
	slow_scale = _cfg.slowdown.scale
	respawn_freeze = _cfg.player.respawn_freeze
	ai_level = _cfg.ai.difficulty.level
	ai_mistake = _cfg.ai.difficulty.mistake_rate
	ai_pressure = _cfg.ai.pressure.default
	girth_max = _cfg.snake.girth.default
	head_style_on = _cfg.ai.head_style.enabled


## Live "AI pressure" 0..1 derived from difficulty + pressure sliders.
func compute_ai_pressure() -> float:
	if _cfg == null:
		return 0.0
	return _cfg.compute_ai_pressure(ai_level, ai_pressure)


## Respawn freeze clamped to the slider range (JS `Game.freezeSec`).
func freeze_sec() -> float:
	if _cfg == null:
		return respawn_freeze
	return clampf(respawn_freeze, _cfg.player.respawn_freeze_min,
		_cfg.player.respawn_freeze_max)


## Radius of a snake with `segments` nodes at the current girth slider value.
func snake_radius(segments: float) -> float:
	if _cfg == null:
		return 22.0
	return _cfg.snake_radius(segments, girth_max)
