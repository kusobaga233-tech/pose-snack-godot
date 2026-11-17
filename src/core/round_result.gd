extends RefCounted
## Settlement payload for one timed round (JS `Game.roundResult`).
##
## Produced by `PSGame.finish_round()` when the 2:00 timer hits zero. The result
## stage animates `ranking` (8 rows, already sorted, `rank` 1..8).
##
##     var result = game.round_result
##     for row in result.ranking:
##         print(row.rank, row.name, row.length, row.kills)
##     if result.won:
##         ...
##
## Rows are `PSRankRow` objects and stay valid after the game object is reset, so
## the presentation can keep animating while the next round is being prepared.

## Number of ranked players (always `round.total_players` = 8).
var total: int = 0
## Rank of player 1 (0 when there is no human, which cannot happen in practice).
var player_rank: int = 0
## True when player 1 finished first.
var won: bool = false
## The `PSRankRow` of player 1 (the same object that is inside `ranking`).
var player = null
## The `PSRankRow`s of every human player (1 row in single player, 2 in split screen).
var players: Array = []
## Historical best length (persistence lives outside the core).
var best_length: int = 16
## `&"timed"` / `&"endless"`.
var mode: StringName = &"timed"
## Round length in seconds (120).
var duration_sec: float = 120.0
## Full sorted ranking, index 0 = first place.
var ranking: Array = []


## Row for a given snake id, or null.
func row_for_id(snake_id: int):
	for row in ranking:
		if row.id == snake_id:
			return row
	return null


func _to_string() -> String:
	var best = ranking[0] if ranking.size() > 0 else null
	return "RoundResult(total=%d playerRank=%d won=%s best=%s)" % [
		total, player_rank, won, "none" if best == null else best.name,
	]
