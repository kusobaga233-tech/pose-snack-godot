extends RefCounted
## One row of the length ranking / settlement payload (JS `Game.rankSnapshot()`).
##
## `length` is the **body segment count at the end of the round** (`0` while the
## snake is mid-respawn, exactly like the JS game: dying clears the body, so a
## death in the last second really does zero your score).
##
## Tie-break order (identical to js/game.js `rankSnapshot`):
##   longer length -> fewer deaths -> more kills -> larger peak -> smaller id
## The id tie-break makes the order strict, i.e. ranks are always 1..8 with no
## shared places.

## Snake id (0 = player 1, AI ids follow the humans).
var id: int = 0
## Display name (`你` / `玩家 2` / `AI 1`).
var name: String = ""
## True for a human-controlled snake.
var is_player: bool = false
## Human slot (0/1); -1 for AI.
var player_index: int = -1
## Body colour.
var color: Color = Color.WHITE
## Personality label (`冒险` / `畏强` / ...); empty for humans.
var style: String = ""
## NPC head style key; `&""` for humans (classic head).
var head_style: StringName = &""
## Final length = body segment count (0 when dead at the whistle).
var length: int = 0
## Longest length reached during the round.
var peak_length: int = 0
## Kills credited this round.
var kills: int = 0
## Deaths this round.
var deaths: int = 0
## Pellets eaten this round.
var food_eaten: int = 0
## 1-based place, assigned after sorting.
var rank: int = 0


## 1-based place + name, handy for logs.
func _to_string() -> String:
	return "#%d %s len=%d kills=%d deaths=%d" % [rank, name, length, kills, deaths]
