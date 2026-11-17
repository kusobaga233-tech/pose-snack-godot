extends RefCounted
## Presentation event queue.
##
## The Web prototype calls the fx system directly from the rules
## (`fx.explode`, `fx.explodeDeath`, `fx.floatText`, `fx.pickup`). The port keeps
## the rules free of rendering, so the same moments are published as a small,
## bounded event list that the presentation drains once per frame:
##
##     game.update(dt, steer, real_dt)
##     var q = game.events
##     for i in q.count:
##         var ev = q.events[i]
##         match ev.type:
##             PSEventQueue.EV_FOOD:   fx.explode(ev.x, ev.y, ...)
##             PSEventQueue.EV_DEATH:  fx.explode_death(ev.points, ev.color, ...)
##             PSEventQueue.EV_TEXT:   fx.float_text(ev.x, ev.y, ev.text, ...)
##             PSEventQueue.EV_POWERUP:fx.pickup(ev.x, ev.y, ...)
##
## `count` resets every `PSGame.update()`; events are reused in place, so
## draining the queue allocates nothing. The queue is capped (overflow drops the
## newest cosmetic event) so a pathological frame cannot grow it without bound.
##
## Event kinds
## -----------
## EV_FOOD    a pellet was eaten      x, y, color, big, radius, own, snake_id
## EV_POWERUP a pickup was collected  x, y, color, own, snake_id, powerup_type, label
## EV_DEATH   a snake died            x, y, color, own, killer_is_player, snake_id,
##                                    points (copy of the body polyline)
## EV_TEXT    floating combat text    x, y, color, text, text_size

const EV_FOOD := 0
const EV_POWERUP := 1
const EV_DEATH := 2
const EV_TEXT := 3

## Hard cap: cosmetic events beyond this in a single frame are dropped.
const MAX_EVENTS := 512


## One cosmetic event; fields are a union, only the ones for `type` are valid.
class Event extends RefCounted:
	var type: int = 0
	var x: float = 0.0
	var y: float = 0.0
	var color: Color = Color.WHITE
	var big: bool = false
	## Visual radius of the eaten pellet (EV_FOOD).
	var radius: float = 24.0
	## True when the event belongs to a human snake (screen shake / flash only for self).
	var own: bool = false
	## EV_DEATH: the killer was a human (drives the "kill" impact tier).
	var killer_is_player: bool = false
	## Snake that caused the event (0 = player 1).
	var snake_id: int = -1
	## EV_TEXT payload.
	var text: String = ""
	var text_size: float = 40.0
	## EV_DEATH payload: the corpse polyline, safe to read after the body is cleared.
	var points: PackedVector2Array = PackedVector2Array()
	## EV_POWERUP payload.
	var powerup_type: StringName = &"boost"
	var label: String = ""


var events: Array = []
var count: int = 0


## Drop everything (called at the start of every game update).
func begin_frame() -> void:
	count = 0


## Number of live events this frame.
func size() -> int:
	return count


func event_at(i: int) -> Event:
	return events[i]


func _next(type: int) -> Event:
	if count < events.size():
		var ev: Event = events[count]
		count += 1
		ev.type = type
		ev.big = false
		ev.own = false
		ev.killer_is_player = false
		ev.text = ""
		ev.label = ""
		ev.powerup_type = &"boost"
		ev.snake_id = -1
		return ev
	if count >= MAX_EVENTS:
		return null
	var ev := Event.new()
	ev.type = type
	events.append(ev)
	count += 1
	return ev


## A pellet was eaten.
func push_food(x: float, y: float, color: Color, big: bool, radius: float,
		own: bool, snake_id: int) -> void:
	var ev := _next(EV_FOOD)
	if ev == null:
		return
	ev.x = x
	ev.y = y
	ev.color = color
	ev.big = big
	ev.radius = radius
	ev.own = own
	ev.snake_id = snake_id


## A pickup was collected.
func push_powerup(x: float, y: float, color: Color, own: bool, snake_id: int,
		type: StringName, label: String) -> void:
	var ev := _next(EV_POWERUP)
	if ev == null:
		return
	ev.x = x
	ev.y = y
	ev.color = color
	ev.own = own
	ev.snake_id = snake_id
	ev.powerup_type = type
	ev.label = label


## A snake died; `points` is a snapshot because the body is cleared right after.
func push_death(x: float, y: float, color: Color, own: bool, killer_is_player: bool,
		snake_id: int, points: PackedVector2Array) -> void:
	var ev := _next(EV_DEATH)
	if ev == null:
		return
	ev.x = x
	ev.y = y
	ev.color = color
	ev.own = own
	ev.killer_is_player = killer_is_player
	ev.snake_id = snake_id
	ev.points = points


## Floating combat text (`吞并！` / `击杀` / `阵亡` / `复活` / `同归于尽`).
func push_text(x: float, y: float, text: String, color: Color, size: float) -> void:
	var ev := _next(EV_TEXT)
	if ev == null:
		return
	ev.x = x
	ev.y = y
	ev.text = text
	ev.color = color
	ev.text_size = size
