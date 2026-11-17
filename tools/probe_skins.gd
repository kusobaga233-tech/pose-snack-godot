extends SceneTree
## tools/probe_skins.gd — headless probe for the character-skin table.
## `godot --headless --path . --script res://tools/probe_skins.gd`
## Prints what the runtime actually sees (regions, atlas size, texture sizes) so
## a wrong table shows up as numbers instead of a black head on screen.

func _initialize() -> void:
	var PSSkins = load("res://src/present/ps_skins.gd")
	var PSData = load("res://src/present/ps_skin_data.gd")
	PSSkins.prepare()
	print("[probe] count=%d player=%d slug=%s" % [PSSkins.count(), PSSkins.player_skin,
		String(PSSkins.get_skin(PSSkins.player_skin)["slug"])])
	print("[probe] ATLAS_K=%s HEAD_HALF_W=%s HEAD_W_MUL=%s" % [str(PSData.ATLAS_K),
		str(PSData.HEAD_HALF_W), str(PSData.HEAD_W_MUL)])
	for i in [0, 1, 7]:
		var s: Dictionary = PSSkins.get_skin(i)
		var tex: Texture2D = PSSkins.atlas_tex(i)
		var btex: Texture2D = PSSkins.body_tex(i)
		print("[probe] %d %s atlas=%s body=%s usable=%s" % [i, String(s["slug"]),
			str(tex.get_size() if tex != null else Vector2.ZERO),
			str(btex.get_size() if btex != null else Vector2.ZERO),
			str(PSSkins.usable(i))])
		for key in ["head", "eyes_open", "mouth_closed", "decor"]:
			print("    %-13s r=%s o=%s" % [key, str(PSSkins.region(i, key)),
				str(PSSkins.region_off(i, key))])
	# the scale the world view would use for a 42 px head radius
	var hr := 42.0
	print("[probe] sc(hr=42)=%.3f  head px width=%.1f" % [
		(PSData.HEAD_W_MUL * hr) / (PSData.HEAD_HALF_W * PSData.ATLAS_K),
		PSSkins.region(0, "head").size.x * (PSData.HEAD_W_MUL * hr)
			/ (PSData.HEAD_HALF_W * PSData.ATLAS_K)])
	# settings round-trip: `-- --set=3` writes, a bare run reads it back
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--set="):
			PSSkins.set_player_skin(int(a.substr(6)))
			print("[probe] saved player=%d (%s) -> %s" % [PSSkins.player_skin,
				PSSkins.name_of(PSSkins.player_skin), ProjectSettings.globalize_path(
					PSSkins.SETTINGS_PATH)])
	quit()
