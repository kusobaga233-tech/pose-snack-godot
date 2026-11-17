extends RefCounted
## One food pellet (JS `Game.makeFood()` return value).
##
## Food is a plain data object: the rules never draw it, the presentation reads
## the fields below. Positions are world pixels; `r` is the *visual* radius, the
## eat test uses `snake_radius + r * food.eat_padding`.
##
## `scattered` marks pellets created by a dying snake's body: they carry the dead
## snake's colour and ignore the spawn margin / min-distance rules (JS does the
## same, they are placed exactly on the corpse).

## World position (pixels).
var x: float = 0.0
var y: float = 0.0
## Visual radius (world pixels); big food is `food.radius * 1.22`.
var r: float = 24.0
## Big ("golden") food: worth `snake.grow_per_big_food` segments and 3x score.
var big: bool = false
## Body colour, driven by the palette (or by the dead snake for scatter).
var color: Color = Color.WHITE
## Face variant key for the presentation (`happy` / `wink` / `wide` / ...).
var face: StringName = &"happy"
## Stable 0..100 pseudo-random value for the cosmetic wobble.
var seed_value: float = 0.0
## True when this pellet came from a corpse.
var scattered: bool = false
## Internal: frame stamp of the last magnet that claimed this pellet. Replaces
## the JS `magnetClaimed` Set so no per-frame allocation is needed.
var claimed_frame: int = -1


func setup(p_x: float, p_y: float, p_r: float, p_big: bool, p_color: Color,
		p_face: StringName, p_seed: float, p_scattered: bool = false) -> void:
	x = p_x
	y = p_y
	r = p_r
	big = p_big
	color = p_color
	face = p_face
	seed_value = p_seed
	scattered = p_scattered


func _to_string() -> String:
	return "Food(%.1f, %.1f r=%.1f big=%s scattered=%s)" % [x, y, r, big, scattered]
