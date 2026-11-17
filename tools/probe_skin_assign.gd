extends SceneTree
## tools/probe_skin_assign.gd — headless probe for the per-round NPC skin deal.
##
##     godot --headless --path . --script res://tools/probe_skin_assign.gd
##
## Proves the invariant the world view relies on: the player keeps his pick and
## every other visible snake gets a **different** character from the
## `count() - 1` pool (the player's pick excluded).  Nothing here hard-codes the
## character count: adding a character widens the pool, it must not create a
## duplicate.  Both modes are checked over several round seeds:
##
##   1P  player + 7 AI           -> 8 distinct visible skins
##   2P  P1 + P2 + 6 AI          -> 8 distinct visible skins, P2 != player
##
## Prints `[skin-assign] no-duplicate-visible=PASS`, then `[skin-assign] PASS`
## and exits 0; any violation prints `FAIL: ...` and exits 1.

class Dummy extends RefCounted:
	var is_player := false
	var player_index := 0


func _initialize() -> void:
	var PSSkins = load("res://src/present/ps_skins.gd")
	PSSkins.prepare()
	var fails: Array = []
	var n: int = PSSkins.count()
	if n < 3:
		fails.append("only %d character(s) in the table" % n)
	# Exercise the panda pick (the capture skin) without writing the setting.
	var saved: int = PSSkins.player_skin
	var panda: int = PSSkins.index_of_slug("C1_panda")
	var pick: int = panda if panda >= 0 else 0
	PSSkins.player_skin = pick
	var pool: int = n - 1
	if pool < 8:
		fails.append("pool of %d is smaller than the 8 visible snakes" % pool)

	# ---- 1P: player + 7 AI, over 24 round seeds ----------------------------
	var rounds := 24
	for r in rounds:
		var snakes: Array = []
		for i in 8:
			var d := Dummy.new()
			d.is_player = (i == 0)
			snakes.append(d)
		PSSkins.assign_round(snakes, 20261112 + r)
		var seen: Dictionary = {}
		for i in snakes.size():
			var idx: int = PSSkins.of(snakes[i])
			if idx < 0 or idx >= n:
				fails.append("1P seed %d slot %d: skin %d out of range" % [r, i, idx])
				continue
			if i == 0 and idx != pick:
				fails.append("1P seed %d: player got %d, expected %d" % [r, idx, pick])
			if i > 0 and idx == pick:
				fails.append("1P seed %d slot %d: AI got the player's pick" % [r, i])
			if seen.has(idx):
				fails.append("1P seed %d: duplicate skin %d (slots %d and %d)"
					% [r, idx, int(seen[idx]), i])
			seen[idx] = i
		if seen.size() != 8:
			fails.append("1P seed %d: only %d distinct skins for 8 snakes"
				% [r, seen.size()])

	# ---- 2P: P1 + P2 + 6 AI, over 8 round seeds ----------------------------
	for r in 8:
		var snakes: Array = []
		for i in 8:
			var d := Dummy.new()
			d.is_player = (i < 2)
			d.player_index = i
			snakes.append(d)
		PSSkins.assign_round(snakes, 77001 + r)
		var seen: Dictionary = {}
		var p2: int = -1
		for i in snakes.size():
			var idx: int = PSSkins.of(snakes[i])
			if idx < 0 or idx >= n:
				fails.append("2P seed %d slot %d: skin %d out of range" % [r, i, idx])
				continue
			if i == 0 and idx != pick:
				fails.append("2P seed %d: P1 got %d, expected %d" % [r, idx, pick])
			if i == 1:
				p2 = idx
				if idx == pick:
					fails.append("2P seed %d: P2 got P1's pick" % r)
			if seen.has(idx):
				fails.append("2P seed %d: duplicate skin %d (slots %d and %d)"
					% [r, idx, int(seen[idx]), i])
			seen[idx] = i
		if p2 < 0 or seen.size() != 8:
			fails.append("2P seed %d: %d distinct skins for 8 snakes" % [r, seen.size()])

	PSSkins.player_skin = saved
	var tag := "C1_panda" if panda >= 0 else "skin0"
	if fails.is_empty():
		print("[skin-assign] count=%d pool=%d player=%s 1P=8 distinct, 2P=8 distinct"
			% [n, pool, tag])
		print("[skin-assign] no-duplicate-visible=PASS")
		print("[skin-assign] PASS")
		quit(0)
	else:
		for f in fails:
			print("[skin-assign] FAIL: " + String(f))
		print("[skin-assign] FAIL")
		quit(1)
