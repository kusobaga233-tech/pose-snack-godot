extends RefCounted
## One pickup (JS `Game.makePowerup()` return value): speed boost or magnet.
##
## Both kinds are on the field at once, every snake may pick them up
## (`powerups.ai_can_pickup`), and a pickup refreshes its own duration instead of
## stacking. Effects are stored as remaining *seconds* on the snake
## (`buff_left()`), so a paused game freezes them for free.

## Buff kind ids; also index into the per-snake buff array.
const BOOST := 0
const MAGNET := 1

## World position (pixels).
var x: float = 0.0
var y: float = 0.0
## `&"boost"` or `&"magnet"`.
var type: StringName = &"boost"
## Icon radius (`powerups.radius`).
var r: float = 26.0
## Icon tint (from the matching config section).
var color: Color = Color.WHITE
## HUD label (`加速` / `磁铁`).
var label: String = ""
## Stable 0..100 pseudo-random value for the cosmetic wobble.
var seed_value: float = 0.0


func setup(p_x: float, p_y: float, p_type: StringName, p_r: float, p_color: Color,
		p_label: String, p_seed: float) -> void:
	x = p_x
	y = p_y
	type = p_type
	r = p_r
	color = p_color
	label = p_label
	seed_value = p_seed


## Buff index for this pickup kind (BOOST / MAGNET).
func buff_index() -> int:
	return MAGNET if type == &"magnet" else BOOST


func _to_string() -> String:
	return "Powerup(%s @ %.1f,%.1f)" % [type, x, y]
