extends Node
# Snd — fully procedural audio. Every sound effect and instrument sample is synthesised at boot;
# music is played by a small step sequencer with per-region themes and leitmotifs.

const SR = 22050
var sfx_bank = {}
var inst = {}
var sfx_players = []
var mus_players = []
var sfx_i = 0
var mus_i = 0
var theme = ""
var cur = null
var step = 0
var step_t = 0.0
var intensity = 0.0
var target_intensity = 0.0
var amb_player = null
var mute = false

# scales as semitone sets
const MINOR = [0, 2, 3, 5, 7, 8, 10]
const DORIAN = [0, 2, 3, 5, 7, 9, 10]
const PHRYG = [0, 1, 3, 5, 7, 8, 10]
const LYD = [0, 2, 4, 6, 7, 9, 11]
const MAJOR = [0, 2, 4, 5, 7, 9, 11]

# motif: scale degrees (-1 = rest) at 8th notes. chords: root degrees per bar.
var themes = {
	# Hawkthorne's theme: a falling fourth that never resolves
	"menu": {"bpm": 66, "root": -3, "scale": MINOR, "chords": [0, 5, 3, 4], "motif": [4, -1, 1, -1, 2, 0, -1, -1, 4, -1, 1, -1, 3, 2, -1, -1], "lead": "piano", "perc": 0, "arp": 0.3},
	"ship": {"bpm": 60, "root": 0, "scale": LYD, "chords": [0, 4, 1, 3], "motif": [0, 2, 4, -1, 6, -1, 4, -1, 0, 2, 4, -1, 7, -1, -1, -1], "lead": "bell", "perc": 0, "arp": 0.2},
	"kharon": {"bpm": 92, "root": -5, "scale": DORIAN, "chords": [0, 0, 3, 4], "motif": [0, -1, -1, 2, -1, 4, 3, -1, 0, -1, -1, 2, -1, 6, 4, -1], "lead": "pluck", "perc": 1, "arp": 0.6},
	"colony": {"bpm": 80, "root": -2, "scale": DORIAN, "chords": [0, 3, 5, 4], "motif": [4, 2, 0, -1, 2, -1, -1, -1, 4, 2, 0, -1, 5, 4, -1, -1], "lead": "piano", "perc": 1, "arp": 0.4},
	"glass": {"bpm": 72, "root": 2, "scale": LYD, "chords": [0, 1, 0, 5], "motif": [7, -1, 4, -1, 6, -1, -1, 3, 7, -1, 4, -1, 8, -1, -1, -1], "lead": "bell", "perc": 0, "arp": 0.7},
	"drowned": {"bpm": 54, "root": -7, "scale": PHRYG, "chords": [0, 1, 0, 3], "motif": [0, -1, -1, -1, 1, -1, 0, -1, -1, -1, 4, -1, 3, -1, -1, -1], "lead": "bell", "perc": 0, "arp": 0.25},
	"cathedral": {"bpm": 70, "root": -4, "scale": MINOR, "chords": [0, 5, 2, 4], "motif": [0, 2, 4, 7, 4, 2, 0, -1, 5, 4, 2, 4, 0, -1, -1, -1], "lead": "choir", "perc": 0, "arp": 0.5},
	"orbit": {"bpm": 62, "root": -6, "scale": MINOR, "chords": [0, 3, 0, 6], "motif": [0, -1, -1, 4, -1, -1, 3, -1, 0, -1, -1, 6, -1, -1, -1, -1], "lead": "bell", "perc": 0, "arp": 0.3},
	"city": {"bpm": 58, "root": -8, "scale": PHRYG, "chords": [0, 0, 1, 0], "motif": [0, 4, 1, -1, -1, 0, -1, -1, 0, 4, 1, -1, -1, 5, -1, -1], "lead": "choir", "perc": 0, "arp": 0.4},
	"ashen": {"bpm": 104, "root": -5, "scale": MINOR, "chords": [0, 5, 3, 4], "motif": [0, 0, -1, 2, 3, -1, 2, 0, 0, 0, -1, 2, 4, -1, 3, 2], "lead": "pluck", "perc": 2, "arp": 0.5},
	"heart": {"bpm": 64, "root": -3, "scale": LYD, "chords": [0, 1, 5, 4], "motif": [4, -1, 1, -1, 2, 0, -1, -1, 6, -1, 4, -1, 7, -1, -1, -1], "lead": "choir", "perc": 0, "arp": 0.8},
	"mind": {"bpm": 56, "root": 0, "scale": MAJOR, "chords": [0, 5, 3, 0], "motif": [0, 2, 4, -1, 6, -1, 4, -1, 2, 0, -1, -1, 4, -1, -1, -1], "lead": "piano", "perc": 0, "arp": 0.2},
	# Veyra's lament: Sable's ship motif, but in minor and slowed
	"veyra": {"bpm": 50, "root": 0, "scale": MINOR, "chords": [0, 5, 3, 4], "motif": [0, 2, 4, -1, 6, -1, 4, -1, 0, 2, 4, -1, 7, -1, -1, -1], "lead": "piano", "perc": 0, "arp": 0.0},
	"boss": {"bpm": 132, "root": -5, "scale": PHRYG, "chords": [0, 0, 1, 5], "motif": [0, -1, 0, 1, -1, 0, 3, -1, 0, -1, 0, 1, -1, 4, 3, 1], "lead": "pluck", "perc": 2, "arp": 1.0},
	"directorate": {"bpm": 112, "root": -4, "scale": MINOR, "chords": [0, 3, 4, 4], "motif": [0, -1, 0, -1, 4, -1, 3, 2, 0, -1, 0, -1, 5, -1, 4, -1], "lead": "pluck", "perc": 2, "arp": 0.7},
}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless": mute = true
	_buses()
	for i in 12:
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)
	for i in 18:
		var p = AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		mus_players.append(p)
	if not mute: _build()
	apply_volumes()

func _buses():
	for n in ["Music", "SFX"]:
		if AudioServer.get_bus_index(n) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, n)
	var rv = AudioEffectReverb.new()
	rv.room_size = 0.85
	rv.wet = 0.35
	rv.damping = 0.4
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), rv)
	var rv2 = AudioEffectReverb.new()
	rv2.room_size = 0.4
	rv2.wet = 0.12
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), rv2)

func apply_volumes():
	if AudioServer.get_bus_index("Music") < 0: return
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(max(0.0001, G.settings.music)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(max(0.0001, G.settings.sfx)))

func _wav(buf: PackedFloat32Array):
	var bytes = PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clamp(buf[i], -1.0, 1.0) * 32000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.data = bytes
	return w

# generic synth: f0->f1 sweep, wave (0 sine,1 saw,2 square,3 noise), attack/decay envelope
func _tone(dur, f0, f1, wave, vol, atk = 0.005, noise = 0.0, harm = 0.0, vib = 0.0):
	var n = int(dur * SR)
	var buf = PackedFloat32Array()
	buf.resize(n)
	var ph = 0.0
	var rng = RandomNumberGenerator.new()
	rng.seed = int(f0 * 13 + dur * 1000)
	var lp = 0.0
	for i in n:
		var t = float(i) / n
		var f = lerp(f0, f1, t) * (1.0 + vib * sin(i * 0.0016))
		ph += f / SR
		var s = 0.0
		match wave:
			0: s = sin(ph * TAU) + harm * sin(ph * TAU * 2.0) * 0.5 + harm * sin(ph * TAU * 3.0) * 0.25
			1: s = fmod(ph, 1.0) * 2.0 - 1.0
			2: s = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			3: s = rng.randf_range(-1, 1)
		if noise > 0: s = lerp(s, rng.randf_range(-1.0, 1.0), noise)
		if wave == 1 or wave == 2:
			lp = lerp(lp, s, 0.25)
			s = lp
		var env = min(1.0, t * dur / atk) * pow(1.0 - t, 2.0)
		buf[i] = s * env * vol
	return buf

func _mix(a: PackedFloat32Array, b: PackedFloat32Array):
	var n = max(a.size(), b.size())
	var o = PackedFloat32Array()
	o.resize(n)
	for i in n:
		o[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return o

func _build():
	var S = sfx_bank
	S["slash"] = _wav(_tone(0.16, 900, 200, 3, 0.5, 0.01, 0.0))
	S["slash2"] = _wav(_mix(_tone(0.2, 1400, 300, 1, 0.25), _tone(0.18, 800, 200, 3, 0.4)))
	S["charge"] = _wav(_mix(_tone(0.45, 200, 1200, 1, 0.3, 0.2), _tone(0.4, 100, 60, 0, 0.6)))
	S["hit"] = _wav(_mix(_tone(0.12, 220, 60, 2, 0.5), _tone(0.1, 500, 100, 3, 0.5)))
	S["hurt"] = _wav(_mix(_tone(0.25, 160, 50, 1, 0.6), _tone(0.2, 300, 100, 3, 0.4)))
	S["shoot"] = _wav(_tone(0.14, 1500, 300, 2, 0.3, 0.002, 0.15))
	S["rail"] = _wav(_mix(_tone(0.35, 2400, 200, 1, 0.35), _tone(0.3, 80, 40, 0, 0.5)))
	S["scatter"] = _wav(_tone(0.2, 700, 150, 3, 0.55))
	S["eshoot"] = _wav(_tone(0.16, 600, 200, 1, 0.3, 0.002, 0.2))
	S["parry"] = _wav(_mix(_tone(0.3, 2200, 1800, 0, 0.5, 0.001, 0.0, 0.8), _tone(0.08, 3000, 500, 3, 0.4)))
	S["jump"] = _wav(_tone(0.12, 260, 420, 0, 0.3))
	S["land"] = _wav(_tone(0.1, 120, 50, 3, 0.35))
	S["dash"] = _wav(_tone(0.2, 400, 1600, 3, 0.35, 0.05))
	S["step"] = _wav(_tone(0.05, 180, 80, 3, 0.18))
	S["grav"] = _wav(_mix(_tone(0.4, 90, 40, 0, 0.8, 0.01, 0.0, 0.6), _tone(0.3, 300, 900, 1, 0.15, 0.1)))
	S["boom"] = _wav(_mix(_tone(0.6, 90, 25, 0, 0.9, 0.005, 0.0, 0.5), _tone(0.5, 400, 60, 3, 0.7)))
	S["pickup"] = _wav(_tone(0.18, 880, 1760, 0, 0.3, 0.005, 0.0, 0.4))
	S["heal"] = _wav(_tone(0.5, 330, 660, 0, 0.35, 0.1, 0.0, 0.6))
	S["ui"] = _wav(_tone(0.05, 1200, 1000, 0, 0.25))
	S["ui_ok"] = _wav(_tone(0.12, 700, 1400, 0, 0.3, 0.005, 0.0, 0.3))
	S["ui_back"] = _wav(_tone(0.1, 700, 350, 0, 0.3))
	S["blip"] = _wav(_tone(0.03, 900, 850, 0, 0.12))
	S["blip_s"] = _wav(_tone(0.035, 1300, 1500, 0, 0.1, 0.002, 0.0, 0.5))
	S["door"] = _wav(_mix(_tone(0.5, 70, 110, 1, 0.4, 0.1), _tone(0.4, 200, 100, 3, 0.2)))
	S["hack"] = _wav(_tone(0.4, 500, 2500, 2, 0.15, 0.01, 0.1, 0.0, 30.0))
	S["unlock"] = _wav(_mix(_tone(0.9, 440, 440, 0, 0.3, 0.02, 0.0, 0.7), _tone(0.9, 660, 660, 0, 0.25, 0.2, 0.0, 0.5)))
	S["quest"] = _wav(_mix(_tone(0.7, 523, 523, 0, 0.25, 0.01, 0.0, 0.5), _tone(0.7, 784, 784, 0, 0.25, 0.15, 0.0, 0.5)))
	S["warn"] = _wav(_tone(0.3, 500, 480, 2, 0.2, 0.01))
	S["tele"] = _wav(_tone(0.25, 2000, 200, 0, 0.3, 0.01, 0.2))
	S["die"] = _wav(_mix(_tone(0.35, 300, 40, 1, 0.4), _tone(0.3, 600, 80, 3, 0.4)))
	S["thunder"] = _wav(_tone(1.2, 60, 30, 3, 0.9, 0.01))
	S["roar"] = _wav(_mix(_tone(1.0, 110, 55, 1, 0.6, 0.1, 0.3, 0.0, 12.0), _tone(1.0, 60, 40, 0, 0.6, 0.1)))
	S["signal"] = _wav(_tone(1.2, 880, 890, 0, 0.2, 0.3, 0.0, 0.9, 6.0))
	# instruments, base pitch A2 = 110Hz
	inst["pad"] = _wav(_inst_pad())
	inst["bass"] = _wav(_tone(1.2, 55, 55, 0, 0.7, 0.01, 0.0, 0.7))
	inst["pluck"] = _wav(_tone(0.7, 220, 220, 1, 0.4, 0.003))
	inst["piano"] = _wav(_tone(2.2, 220, 220, 0, 0.5, 0.004, 0.0, 0.6))
	inst["bell"] = _wav(_mix(_tone(2.5, 440, 440, 0, 0.3, 0.003), _tone(1.5, 440 * 2.76, 440 * 2.76, 0, 0.12, 0.003)))
	inst["choir"] = _wav(_inst_choir())
	inst["kick"] = _wav(_tone(0.25, 140, 35, 0, 0.9, 0.002))
	inst["hat"] = _wav(_tone(0.05, 8000, 8000, 3, 0.18))
	inst["clang"] = _wav(_mix(_tone(0.3, 300, 280, 2, 0.2, 0.002, 0.3), _tone(0.2, 1200, 300, 3, 0.3)))

func _inst_pad():
	var n = int(3.5 * SR)
	var buf = PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t = float(i) / SR
		var s = 0.0
		for d in [0.994, 1.0, 1.006, 2.003]: s += sin(t * 110.0 * d * TAU) + 0.3 * sin(t * 220.0 * d * TAU)
		var env = min(1.0, t / 0.8) * min(1.0, (3.5 - t) / 1.5)
		buf[i] = s * 0.07 * env
	return buf

func _inst_choir():
	var n = int(3.0 * SR)
	var buf = PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t = float(i) / SR
		var vib = 1.0 + 0.004 * sin(t * 5.2 * TAU)
		var s = 0.0
		for h in range(1, 9):
			var fq = 220.0 * h * vib
			var formant = exp(-pow((fq - 700.0) / 400.0, 2.0)) + 0.6 * exp(-pow((fq - 1200.0) / 300.0, 2.0)) + 0.15
			s += sin(t * fq * TAU) * formant / h
		var env = min(1.0, t / 0.5) * min(1.0, (3.0 - t) / 1.2)
		buf[i] = s * 0.16 * env
	return buf

func sfx(name, vol = 0.0, pitch = 1.0):
	if mute or not sfx_bank.has(name): return
	var p = sfx_players[sfx_i]
	sfx_i = (sfx_i + 1) % sfx_players.size()
	p.stream = sfx_bank[name]
	p.volume_db = vol
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()

func music(name):
	if name == theme: return
	theme = name
	cur = themes.get(name)
	step = 0
	step_t = 0.0

func combat(x): target_intensity = x

func _note(i_name, semis, vol):
	if mute or not inst.has(i_name): return
	var p = mus_players[mus_i]
	mus_i = (mus_i + 1) % mus_players.size()
	p.stream = inst[i_name]
	p.pitch_scale = pow(2.0, semis / 12.0)
	p.volume_db = vol
	p.play()

func _deg(scale, d):
	var o = int(floor(d / 7.0))
	return scale[posmod(d, 7)] + 12 * o

func _process(dt):
	intensity = move_toward(intensity, target_intensity, dt * 0.5)
	if cur == null or mute: return
	var spb = 60.0 / cur.bpm / 2.0  # 8th notes
	step_t -= dt
	if step_t > 0: return
	step_t += spb
	var bar = int(step / 8) % cur.chords.size()
	var beat = step % 8
	var root = cur.root
	var ch = cur.chords[bar]
	if beat == 0:
		_note("pad", root + _deg(cur.scale, ch), -9)
		_note("pad", root + _deg(cur.scale, ch + 2), -11)
		_note("pad", root + _deg(cur.scale, ch + 4), -11)
		_note("bass", root + _deg(cur.scale, ch), -7)
	if beat == 4 and (cur.perc > 0 or intensity > 0.3): _note("bass", root + _deg(cur.scale, ch) + (12 if step % 16 >= 8 else 0), -10)
	# leitmotif every other 2-bar phrase
	var mi = step % 32
	if mi < 16:
		var d = cur.motif[mi]
		if d >= 0: _note(cur.lead, root + 12 + _deg(cur.scale, d) + (0 if cur.lead in ["piano", "pluck"] else -12), -8)
	# arpeggio shimmer
	if randf() < cur.arp * (0.5 + intensity * 0.5) and beat % 2 == 1:
		_note("bell" if cur.lead != "bell" else "pluck", root + 12 + _deg(cur.scale, ch + [0, 2, 4, 7][randi() % 4]), -18)
	var pl = cur.perc + (1 if intensity > 0.5 else 0)
	if pl >= 1:
		if beat == 0 or (pl >= 2 and beat == 5): _note("kick", 0, -6)
		if beat == 4: _note("clang", 0, -14)
		if pl >= 2 and beat % 2 == 1: _note("hat", 0, -16)
	step += 1
