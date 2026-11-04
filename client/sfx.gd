class_name Sfx
extends Node
## Tiny synthesiser for placeholder sound effects (GDD 10 Audio: short punchy sounds
## for hits, prayers, freezes, specials and eating, plus an optional tick metronome).

const RATE := 22050

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var volume: float = 0.7


func _ready() -> void:
	for i in range(12):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build()


func play(name: String, vol: float = 1.0, pitch: float = 1.0) -> void:
	if not _streams.has(name) or volume <= 0.0:
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[name]
			p.volume_db = linear_to_db(clampf(volume * vol, 0.001, 1.0))
			p.pitch_scale = pitch
			p.play()
			return


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Generic voice: wave in {sine, square, saw, noise}, frequency sweep f0->f1, decay envelope.
func _tone(dur: float, f0: float, f1: float, wave: String, decay: float = 6.0, attack: float = 0.005) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 1000 + dur * 77)
	for i in range(n):
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur)
		phase += f / RATE
		var s := 0.0
		match wave:
			"sine": s = sin(phase * TAU)
			"square": s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			"saw": s = fmod(phase, 1.0) * 2.0 - 1.0
			"noise": s = rng.randf_range(-1.0, 1.0)
		var env := minf(1.0, t / attack) * exp(-decay * t / dur)
		out[i] = s * env * 0.6
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gb: float = 1.0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0) * gb
	return out


func _seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


func _build() -> void:
	_streams["hit"] = _wav(_mix(_tone(0.12, 180, 60, "noise", 8), _tone(0.12, 120, 50, "sine", 6), 0.8))
	_streams["block"] = _wav(_mix(_tone(0.15, 900, 700, "square", 9), _tone(0.1, 2000, 1500, "noise", 10), 0.3))
	_streams["melee"] = _wav(_tone(0.12, 1400, 300, "noise", 5, 0.01))
	_streams["arrow"] = _wav(_mix(_tone(0.18, 300, 200, "saw", 6), _tone(0.1, 3000, 1000, "noise", 8), 0.4))
	_streams["cast"] = _wav(_tone(0.35, 300, 900, "sine", 3, 0.04))
	_streams["splash"] = _wav(_tone(0.25, 2500, 400, "noise", 5))
	_streams["freeze"] = _wav(_mix(_tone(0.5, 1600, 2400, "sine", 3), _tone(0.5, 2400, 3200, "sine", 4), 0.5))
	_streams["eat"] = _wav(_seq([_tone(0.06, 400, 300, "noise", 6), _tone(0.04, 1, 1, "sine", 1), _tone(0.06, 400, 300, "noise", 6)]))
	_streams["drink"] = _wav(_tone(0.25, 300, 600, "sine", 4))
	_streams["prayer_on"] = _wav(_tone(0.12, 880, 1320, "sine", 4))
	_streams["prayer_off"] = _wav(_tone(0.12, 990, 550, "sine", 4))
	_streams["spec"] = _wav(_mix(_tone(0.4, 110, 220, "saw", 3), _tone(0.4, 165, 330, "saw", 3), 0.7))
	_streams["death"] = _wav(_tone(0.6, 300, 60, "saw", 3))
	_streams["kill"] = _wav(_seq([_tone(0.08, 1320, 1320, "square", 3), _tone(0.12, 1760, 1760, "square", 4)]))
	_streams["hitmarker"] = _wav(_tone(0.05, 3000, 2500, "square", 8))
	_streams["level_up"] = _wav(_seq([_tone(0.15, 523, 523, "square", 2), _tone(0.15, 659, 659, "square", 2), _tone(0.15, 784, 784, "square", 2), _tone(0.4, 1046, 1046, "square", 2)]))
	_streams["streak"] = _wav(_seq([_tone(0.2, 392, 392, "saw", 2), _tone(0.35, 523, 523, "saw", 2)]))
	_streams["tick"] = _wav(_tone(0.03, 2000, 2000, "square", 10))
	_streams["click"] = _wav(_tone(0.03, 1200, 1000, "square", 10))
	_streams["meteor"] = _wav(_mix(_tone(0.9, 120, 30, "noise", 3), _tone(0.9, 80, 30, "sine", 3)))
	_streams["countdown"] = _wav(_tone(0.12, 660, 660, "square", 4))
	_streams["go"] = _wav(_tone(0.4, 990, 990, "square", 3))
