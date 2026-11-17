extends SceneTree
## tools/probe_skin_default.gd — headless probe for the **默认** picker entry.
##
##     godot --headless --path . --script res://tools/probe_skin_default.gd
##
## Owner: 所谓默认角色是指原来网页中的玩家控制角色形象 — 默认 is the web original's
## procedural player snake, NOT one of the character-pack skins. This probe drives
## the real `ps_skins.gd` code paths (no mocks) and checks:
##
##   1. the picker order 默认 -> 辣椒蛇 -> ... -> 熬夜熊猫 -> 默认, plus both wrap
##      edges (LEFT from the first character, RIGHT from the last);
##   2. the AI pool: 默认 leaves `count()` characters available, a specific pick
##      leaves `count() - 1`, and the player's character is never dealt to an AI;
##   3. the load rules: missing file / missing key / "" / "!default" / unknown
##      slug all load as 默认, and a real slug still loads as that character;
##   4. the exact value written to `user://pose_snake.cfg` for both states.
##
## Ends on 默认 (the fresh-install state). Prints `[skin-default] PASS` and exits
## 0, or `FAIL: ...` lines and exits 1.

const CASES := [
	["missing-file", null, -1],
	["missing-key", "", -1],          # placeholder: written as a [audio] section
	["empty-string", "", -1],
	["explicit-default", "!default", -1],
	["legacy-B5_diva", "B5_diva", 9],
	["legacy-A1_spicy", "A1_spicy", 0],
	["unknown-slug", "@@nope", -1],
]


class Dummy extends RefCounted:
	var is_player := false
	var player_index := 0


func _initialize() -> void:
	var PS = load("res://src/present/ps_skins.gd")
	PS.prepare()
	var fails: Array = []
	var n: int = PS.count()
	print("[skin-default] count=%d picker=%d file=%s" % [n, PS.picker_count(),
		ProjectSettings.globalize_path(PS.SETTINGS_PATH)])
	if n < 4:
		fails.append("only %d character(s) in the table" % n)

	_order(PS, n, fails)
	_pool(PS, n, fails)
	_reset(PS, n, fails)
	_load_rules(PS, n, fails)
	_disk(PS, fails)

	if fails.is_empty():
		PS.set_player_skin(-1)
		print("[skin-default] left on pick=%s -> %s" % [PS.describe_pick(), _raw(PS)])
		print("[skin-default] PASS")
		quit(0)
	else:
		for f in fails:
			print("[skin-default] FAIL: " + String(f))
		print("[skin-default] FAIL")
		quit(1)


# ------------------------------------------------------------- 1. picker order
func _order(PS, n: int, fails: Array) -> void:
	PS.set_player_skin(-1)
	var seen: Array = [String(PS.get_skin(PS.player_skin)["slug"])]
	for i in n + 1:
		PS.step_player_skin(1)
		seen.append(String(PS.get_skin(PS.player_skin)["slug"]))
	var want: Array = ["!default"]
	for i in n:
		want.append(String(PS.get_skin(i)["slug"]))
	want.append("!default")
	if seen != want:
		fails.append("cycle order %s != %s" % [str(seen), str(want)])
	print("[skin-default] order: " + " -> ".join(PackedStringArray(seen)))

	# wrap edges
	PS.set_player_skin(-1)
	PS.step_player_skin(-1)
	var left_from_def := String(PS.get_skin(PS.player_skin)["slug"])
	if left_from_def != String(PS.get_skin(n - 1)["slug"]):
		fails.append("LEFT from 默认 -> %s (expected the last character %s)"
			% [left_from_def, String(PS.get_skin(n - 1)["slug"])])
	PS.step_player_skin(1)
	if PS.player_skin != -1:
		fails.append("RIGHT from the last character -> %s (expected 默认)"
			% PS.describe_pick())
	PS.step_player_skin(1)
	if PS.player_skin != 0:
		fails.append("RIGHT from 默认 -> %s (expected the first character)"
			% PS.describe_pick())
	PS.step_player_skin(-1)
	if PS.player_skin != -1:
		fails.append("LEFT from the first character -> %s (expected 默认)"
			% PS.describe_pick())
	print("[skin-default] edges: LEFT 默认 -> %s, RIGHT last -> 默认, LEFT first -> 默认" \
		% left_from_def)


# ------------------------------------------------------------------ 2. AI pool
func _field(count: int, players: int) -> Array:
	var out: Array = []
	for i in count:
		var d := Dummy.new()
		d.is_player = i < players
		d.player_index = i
		out.append(d)
	return out


func _pool(PS, n: int, fails: Array) -> void:
	# ---- 默认: nothing is excluded, all n characters are available ----------
	PS.set_player_skin(-1)
	if PS.ai_pool_count() != n:
		fails.append("默认 pool=%d (expected %d)" % [PS.ai_pool_count(), n])
	var snakes := _field(8, 1)
	PS.assign_round(snakes, 20261117)
	var p1: int = PS.of(snakes[0])
	if p1 != -1:
		fails.append("默认: player got %d (expected -1 = procedural)" % p1)
	var seen: Dictionary = {}
	for i in range(1, snakes.size()):
		var idx: int = PS.of(snakes[i])
		if idx < 0 or idx >= n:
			fails.append("默认 seed: AI slot %d got %d out of range" % [i, idx])
		if seen.has(idx):
			fails.append("默认 seed: duplicate skin %d" % idx)
		seen[idx] = i
	print("[skin-default] pool 默认: available=%d dealt-to-7-AI=%d distinct=%d player=%s"
		% [PS.ai_pool_count(), snakes.size() - 1, seen.size(), PS.get_skin(-1)["slug"]])

	# ---- specific pick: that character is out of the deal --------------------
	var pick: int = PS.index_of_slug("B5_diva")
	if pick < 0:
		fails.append("B5_diva missing from the table")
		return
	PS.set_player_skin(pick)
	if PS.ai_pool_count() != n - 1:
		fails.append("specific pool=%d (expected %d)" % [PS.ai_pool_count(), n - 1])
	var s2 := _field(8, 1)
	PS.assign_round(s2, 20261117)
	if PS.of(s2[0]) != pick:
		fails.append("specific: player got %d, expected %d" % [PS.of(s2[0]), pick])
	var seen2: Dictionary = {}
	for i in range(1, s2.size()):
		var idx: int = PS.of(s2[i])
		if idx == pick:
			fails.append("specific: AI slot %d got the player's character" % i)
		if seen2.has(idx):
			fails.append("specific: duplicate skin %d" % idx)
		seen2[idx] = i
	print("[skin-default] pool specific(%s): available=%d dealt-to-7-AI=%d distinct=%d player=%d"
		% [String(PS.get_skin(pick)["slug"]), PS.ai_pool_count(), s2.size() - 1,
			seen2.size(), PS.of(s2[0])])

	# ---- 2P on 默认: P1 keeps the procedural look, P2 + 6 AI from the pool ---
	PS.set_player_skin(-1)
	var s3 := _field(8, 2)
	PS.assign_round(s3, 77001)
	if PS.of(s3[0]) != -1:
		fails.append("2P 默认: P1 got %d (expected -1)" % PS.of(s3[0]))
	var seen3: Dictionary = {}
	for i in range(1, s3.size()):
		var idx: int = PS.of(s3[i])
		if idx < 0 or idx >= n:
			fails.append("2P 默认: slot %d got %d out of range" % [i, idx])
		if seen3.has(idx):
			fails.append("2P 默认: duplicate skin %d" % idx)
		seen3[idx] = i
	print("[skin-default] pool 2P 默认: P1=-1, P2+6-AI distinct=%d" % seen3.size())


# --------------------------------------------------------- 3. reset affordance
## From a character pick, step the picker onto 默认 and deal a round: the player
## must come back as the procedural snake (the reset the owner asked for).
func _reset(PS, n: int, fails: Array) -> void:
	PS.set_player_skin(PS.index_of_slug("B5_diva"))
	PS.step_player_skin(1)   # 下午茶蛇 -> 熬夜熊猫
	PS.step_player_skin(1)   # 熬夜熊猫 -> 默认 (RIGHT wraps)
	if PS.player_skin != -1:
		fails.append("picker did not land on 默认 (%s)" % PS.describe_pick())
	var snakes := _field(8, 1)
	PS.assign_round(snakes, 4242)
	var p1: int = PS.of(snakes[0])
	print("[skin-default] reset: pick=%s -> next round player skin=%d (%s)" % [
		PS.describe_pick(), p1, String(PS.get_skin(p1)["slug"])])
	if p1 != -1:
		fails.append("next round player skin is %d, expected -1 (procedural)" % p1)
	var seen: Dictionary = {}
	for i in range(1, snakes.size()):
		var idx: int = PS.of(snakes[i])
		if idx < 0 or idx >= n:
			fails.append("reset deal: AI slot %d got %d out of range" % [i, idx])
		seen[idx] = i
	if seen.size() != snakes.size() - 1:
		fails.append("reset deal: %d distinct AI skins, expected %d"
			% [seen.size(), snakes.size() - 1])


# ---------------------------------------------------------------- 4. load rules
func _load_rules(PS, n: int, fails: Array) -> void:
	for c in CASES:
		var name: String = c[0]
		var want: int = int(c[2])
		if name == "missing-file":
			var abs := ProjectSettings.globalize_path(PS.SETTINGS_PATH)
			if FileAccess.file_exists(PS.SETTINGS_PATH):
				DirAccess.remove_absolute(abs)
		elif name == "missing-key":
			var cfg := ConfigFile.new()
			cfg.set_value("audio", "muted", false)
			cfg.save(PS.SETTINGS_PATH)
		else:
			var cfg2 := ConfigFile.new()
			cfg2.set_value("skin", "player", String(c[1]))
			cfg2.save(PS.SETTINGS_PATH)
		PS.load_settings(true)
		var got: int = PS.player_skin
		var want_slug := String(PS.get_skin(want)["slug"])
		var got_slug := String(PS.get_skin(got)["slug"])
		print("[skin-default] load %s -> player=%s slug=%s (expected %s %s) %s" % [
			name.rpad(16), str(got), got_slug, str(want), want_slug,
			"OK" if got == want else "MISMATCH"])
		if got != want:
			fails.append("load %s -> %d, expected %d" % [name, got, want])
	# the derived name of the 默认 entry must be the owner-facing label
	if String(PS.get_skin(-1)["name"]) != PS.DEFAULT_NAME:
		fails.append("默认 name is %s" % String(PS.get_skin(-1)["name"]))
	print("[skin-default] default entry: slug=%s name=%s usable=%s picker_pos=%d" % [
		PS.DEFAULT_SLUG, String(PS.get_skin(-1)["name"]), str(PS.usable(-1)),
		PS.picker_pos()])


# ------------------------------------------------------------ 4. on-disk value
func _raw(PS) -> String:
	var f := FileAccess.open(PS.SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return "<no file>"
	var out := ""
	for line in f.get_as_text().split("\n"):
		var t := line.strip_edges()
		if t.begins_with("player"):
			out = t
	f.close()
	return "[" + out + "]"


func _disk(PS, fails: Array) -> void:
	PS.set_player_skin(-1)
	var d := _raw(PS)
	print("[skin-default] disk 默认: %s" % d)
	if d != '[player="!default"]':
		fails.append("默认 wrote %s, expected [player=\"!default\"]" % d)
	PS.set_player_skin(PS.index_of_slug("B5_diva"))
	var s := _raw(PS)
	print("[skin-default] disk specific: %s" % s)
	if s != '[player="B5_diva"]':
		fails.append("B5_diva wrote %s" % s)
	print("[skin-default] describe: %s" % PS.describe_pick())
