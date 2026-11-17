extends RefCounted
## Workstream C — tiny synthesised SFX. No audio assets ship with the project:
## five short mono 22.05 kHz PCM blips are generated once at boot into
## AudioStreamWAV resources and played through a small player pool.
##
## Pre-baked WAVs (instead of AudioStreamGenerator) keep the per-frame cost at
## zero and cannot stall the audio thread on a weak box.
##
## Mute (owner-facing: 音效 开/关)
## -------------------------------
## `enabled` is the boot capability flag (false when the host has no audio bus,
## e.g. `--headless`); `muted` is the player's choice. They are separate on
## purpose: turning the sound back on must never try to rebuild the player pool,
## and a headless run must stay silent whatever the saved setting says.
## The choice is persisted by `PSettings` (`[audio] muted`) and restored by
## `main.gd` at boot through `set_muted()`, which also silences a blip that is
## already playing.

const SR := 22050

var enabled := true
var muted := false
var _players: Array = []
var _streams: Dictionary = {}
var _next := 0
var _host: Node = null


func build(host: Node, volume_db: float = -8.0) -> void:
	_host = host
	if AudioServer.get_bus_count() == 0:
		enabled = false
		return
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		p.volume_db = volume_db
		host.add_child(p)
		_players.append(p)
	_streams["eat"] = _tone(680.0, 1180.0, 0.075, 0.36, 26.0, 0.0)
	_streams["big"] = _tone(520.0, 1560.0, 0.20, 0.42, 12.0, 0.0)
	_streams["pickup"] = _tone(880.0, 1760.0, 0.16, 0.34, 14.0, 0.0)
	_streams["kill"] = _tone(220.0, 70.0, 0.28, 0.5, 9.0, 0.35)
	_streams["death"] = _tone(300.0, 60.0, 0.34, 0.45, 8.0, 0.25)
	_streams["go"] = _tone(440.0, 880.0, 0.22, 0.36, 10.0, 0.0)


## Mute/unmute. Stops whatever is playing so the toggle is audible immediately
## (turning it ON is confirmed by the caller's own blip, not by an old tail).
func set_muted(on: bool) -> void:
	muted = on
	if muted:
		for p in _players:
			var pl: AudioStreamPlayer = p
			if pl.playing:
				pl.stop()


func play(name: StringName, pitch: float = 1.0) -> void:
	if not enabled or muted or _players.is_empty():
		return
	var st: AudioStreamWAV = _streams.get(name, null)
	if st == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = st
	p.pitch_scale = clampf(pitch, 0.6, 1.6)
	p.play()


## One decaying sine sweep with optional noise, written straight into PCM16.
func _tone(f0: float, f1: float, dur: float, amp: float, decay: float,
		noise: float) -> AudioStreamWAV:
	var n := maxi(16, int(dur * float(SR)))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var phase := 0.0
	var rs := 0x1234ABCD
	for i in n:
		var t := float(i) / float(SR)
		var k := t / dur
		var f := f0 + (f1 - f0) * k
		phase += TAU * f / float(SR)
		var env := exp(-decay * t)
		# 4 ms attack so the blip does not click
		env *= clampf(t / 0.004, 0.0, 1.0)
		var v := sin(phase) * env * amp
		if noise > 0.0:
			rs = (rs * 1664525 + 1013904223) & 0xFFFFFFFF
			v += (float(rs & 0xFFFF) / 32767.5 - 1.0) * noise * env * 0.35
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	return w
