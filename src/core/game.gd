extends Node
# G — global game state, narrative flags, save system, settings and input bindings.

const SAVE_VERSION = 2
const SALT = "ashes-of-the-stars"
const SLOTS = 3

# id, label, keys, joy buttons, joy axis [axis, sign] or null
const ACTIONS = [
	["left", "Move Left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [0, -1]],
	["right", "Move Right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [0, 1]],
	["up", "Up / Aim Up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [1, -1]],
	["down", "Down / Crouch", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [1, 1]],
	["jump", "Jump", [KEY_SPACE], [JOY_BUTTON_A], null],
	["attack", "Energy Blade", [KEY_J], [JOY_BUTTON_X], null],
	["shoot", "Sidearm", [KEY_K], [JOY_BUTTON_RIGHT_SHOULDER], null],
	["gauntlet", "Grav Gauntlet", [KEY_L], [JOY_BUTTON_Y], null],
	["dash", "Dash / Roll", [KEY_SHIFT], [JOY_BUTTON_B], null],
	["parry", "Parry", [KEY_I], [JOY_BUTTON_LEFT_SHOULDER], null],
	["heal", "Use Stim", [KEY_Q], [JOY_BUTTON_LEFT_STICK], null],
	["interact", "Interact", [KEY_E], [JOY_BUTTON_RIGHT_STICK], null],
	["swap", "Cycle Ammo", [KEY_R], [JOY_BUTTON_BACK], null],
	["sable", "Sable Assist", [KEY_F], [JOY_BUTTON_MISC1], [4, 1]],
	["journal", "Journal", [KEY_TAB], [JOY_BUTTON_GUIDE], null],
	["pause", "Pause / Back", [KEY_ESCAPE], [JOY_BUTTON_START], null],
	["accept", "Confirm", [KEY_ENTER], [], null],
]

var state = {}
var meta = {"endings": {}}
var settings = {
	"master": 0.8, "music": 0.7, "sfx": 0.9, "fullscreen": false, "shake": 1.0,
	"text_speed": 1.0, "difficulty": 1, "contrast": false, "flash": true,
	"big_text": false, "auto_parry": false, "slow": false, "binds": {},
}
var slot = 1
var dev = false
var main = null
var level = null
var pending_goto = ""
var clock_on = false

signal toast(msg)
signal quest_changed(id)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	dev = "--dev" in OS.get_cmdline_user_args() or "--dev" in OS.get_cmdline_args()
	load_meta()
	setup_input()
	apply_settings()
	state = new_state()

func new_state():
	return {
		"flags": {}, "rel": {"sable": 0, "lyra": 0, "orin": 0, "kestrel": 0, "thorne": 0, "archivist": 0, "nyx": 0},
		"chapter": 1, "room": "", "cp": 0, "shards": 0, "upgrades": {}, "abilities": {"walljump": 1},
		"mods": [], "equipped": [], "items": {}, "quests": {}, "visited": {}, "taken": {}, "bosses": {},
		"log": [], "time": {}, "stats": {"deaths": 0, "kills": 0, "parries": 0}, "ammo": 0, "stims": 3, "hp": 100,
	}

# ---------------------------------------------------------------- narrative values
func val(n):
	n = n.strip_edges()
	if n == "ch": return state.chapter
	if n.begins_with("rel."): return state.rel.get(n.substr(4), 0)
	if n.begins_with("q."): return state.quests.get(n.substr(2), 0)
	if n.begins_with("ab."): return state.abilities.get(n.substr(3), 0)
	if n.begins_with("boss."): return state.bosses.get(n.substr(5), 0)
	if n.begins_with("item."): return state.items.get(n.substr(5), 0)
	if n.begins_with("up."): return state.upgrades.get(n.substr(3), 0)
	if n == "shards": return state.shards
	return state.flags.get(n, 0)

func f(n): return val(n)

func setv(n, v):
	n = n.strip_edges()
	if n.begins_with("rel."):
		var who = n.substr(4)
		var old = state.rel.get(who, 0)
		state.rel[who] = clamp(v, -10, 10)
		if v != old and DB.chars.has(who):
			toast.emit(DB.chars[who].name + (" +" if v > old else " -"))
	elif n == "shards": state.shards = max(0, v)
	else: state.flags[n] = v

func cond(s):
	s = str(s).strip_edges()
	if s == "": return true
	for alt in s.split("|"):
		var ok = true
		for term in alt.split("&"):
			if not _term(term.strip_edges()):
				ok = false
				break
		if ok: return true
	return false

func _term(t):
	if t == "": return true
	if t.begins_with("!"): return float(val(t.substr(1))) == 0.0
	for op in [">=", "<=", "==", "!=", ">", "<"]:
		var i = t.find(op)
		if i > 0:
			var a = float(val(t.substr(0, i)))
			var b = float(t.substr(i + op.length()))
			match op:
				">=": return a >= b
				"<=": return a <= b
				"==": return a == b
				"!=": return a != b
				">": return a > b
				"<": return a < b
	return float(val(t)) != 0.0

func apply(s):
	for e in str(s).split(";"):
		e = e.strip_edges()
		if e == "": continue
		var p = e.split(":")
		match p[0]:
			"quest": set_quest(p[1], int(p[2]))
			"give":
				state.shards += int(p[2])
				toast.emit("+%s shards" % p[2])
			"unlock":
				if not state.abilities.has(p[1]):
					state.abilities[p[1]] = 1
					toast.emit("New technique: " + DB.ability_name(p[1]))
					Snd.sfx("unlock")
			"mod": add_mod(p[1])
			"item":
				state.items[p[1]] = 1
				toast.emit("Acquired: " + DB.items.get(p[1], p[1]))
			"toast": toast.emit(p[1])
			"chapter": set_chapter(int(p[1]))
			"goto": pending_goto = p[1]
			"ending": record_ending(p[1])
			"heal":
				if level and level.player: level.player.full_heal()
			"core":
				var k = "core_" + p[1]
				state.upgrades[k] = state.upgrades.get(k, 0) + 1
				toast.emit("Lattice core absorbed: " + ("Vitality" if p[1] == "hp" else "Energy"))
			_:
				var i = e.find("=")
				if i > 0 and e[i - 1] != "!" and e[i - 1] != ">" and e[i - 1] != "<":
					setv(e.substr(0, i), _num(e.substr(i + 1)))
					continue
				i = e.rfind("+")
				if i > 0:
					setv(e.substr(0, i), val(e.substr(0, i)) + _num(e.substr(i + 1)))
					continue
				i = e.rfind("-")
				if i > 0:
					setv(e.substr(0, i), val(e.substr(0, i)) - _num(e.substr(i + 1)))
					continue
				push_warning("Unknown effect: " + e)

func _num(s):
	s = s.strip_edges()
	return float(s) if s.is_valid_float() else 1.0

func set_quest(id, stage):
	if state.quests.get(id, 0) >= stage: return
	var was = state.quests.get(id, 0)
	state.quests[id] = stage
	var q = DB.quests.get(id)
	if q:
		if stage >= 99:
			toast.emit("Completed: " + q.title)
			Snd.sfx("quest")
		elif was == 0: toast.emit("New entry: " + q.title)
		else: toast.emit("Updated: " + q.title)
	quest_changed.emit(id)

func add_mod(id):
	if id in state.mods: return
	state.mods.append(id)
	if state.equipped.size() < 2: state.equipped.append(id)
	toast.emit("Mod found: " + DB.mods[id].name)

func has_mod(id): return id in state.equipped
func has(ab): return state.abilities.has(ab)

func set_chapter(n):
	if n <= state.chapter: return
	_telemetry("chapter %d complete in %.1f min (slot %d)" % [state.chapter, state.time.get(str(state.chapter), 0.0) / 60.0, slot])
	state.chapter = n
	state.flags["sable_stage"] = sable_stage()

func sable_stage():
	var c = state.chapter
	if c <= 2: return 1
	if c <= 5: return 2
	if c <= 8: return 3
	if c <= 11: return 4
	return 5

func record_ending(id):
	meta.endings[id] = {"time": total_time(), "date": Time.get_date_string_from_system()}
	save_meta()
	_telemetry("ENDING %s total %.1f min" % [id, total_time() / 60.0])

func total_time():
	var t = 0.0
	for k in state.time: t += state.time[k]
	return t

func _telemetry(line):
	var fa = FileAccess.open("user://telemetry.log", FileAccess.READ_WRITE if FileAccess.file_exists("user://telemetry.log") else FileAccess.WRITE)
	if fa:
		fa.seek_end()
		fa.store_line(Time.get_datetime_string_from_system() + " " + line)

func _process(dt):
	if clock_on and level != null and not get_tree().paused:
		var k = str(state.chapter)
		state.time[k] = state.time.get(k, 0.0) + dt

func log_line(who, text):
	state.log.append([who, text])
	if state.log.size() > 250: state.log.pop_front()

# ---------------------------------------------------------------- derived stats
func max_hp(): return 100 + 15 * int(state.upgrades.get("hp", 0)) + 10 * int(state.upgrades.get("core_hp", 0))
func max_en(): return 100 + 15 * int(state.upgrades.get("en", 0)) + 10 * int(state.upgrades.get("core_en", 0))
func max_stims(): return 3 + int(state.upgrades.get("stim", 0))
func blade_dmg(): return 18 + 4 * int(state.upgrades.get("blade", 0)) + (4 if has_mod("edge") else 0)
func gun_dmg(): return 9 + 2 * int(state.upgrades.get("gun", 0))
func dmg_taken_mult(): return [0.5, 1.0, 1.5][int(settings.difficulty)] * (0.85 if has_mod("plating") else 1.0)

# ---------------------------------------------------------------- saves
func slot_path(s): return "user://save_slot%d.json" % s

func save_game():
	if state.room == "": return false
	var body = JSON.stringify(state)
	var doc = {"version": SAVE_VERSION, "sum": (body + SALT).sha256_text(), "saved": Time.get_datetime_string_from_system(), "data": state}
	var fa = FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if fa == null: return false
	fa.store_string(JSON.stringify(doc))
	return true

func read_slot(s):
	# returns {ok, error, data, saved}
	if not FileAccess.file_exists(slot_path(s)): return {"ok": false, "error": "empty"}
	var txt = FileAccess.get_file_as_string(slot_path(s))
	var doc = JSON.parse_string(txt)
	if typeof(doc) != TYPE_DICTIONARY or not doc.has("data") or typeof(doc.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "corrupt"}
	if int(doc.get("version", 0)) > SAVE_VERSION: return {"ok": false, "error": "newer version"}
	if (JSON.stringify(doc.data) + SALT).sha256_text() != doc.get("sum", ""):
		return {"ok": false, "error": "checksum mismatch"}
	var d = migrate(doc.data, int(doc.get("version", 1)))
	var base = new_state()
	for k in base:
		if not d.has(k): d[k] = base[k]
		elif typeof(d[k]) != typeof(base[k]) and not (typeof(base[k]) in [TYPE_INT, TYPE_FLOAT] and typeof(d[k]) in [TYPE_INT, TYPE_FLOAT]):
			return {"ok": false, "error": "invalid field " + k}
	d.chapter = int(d.chapter)
	d.cp = int(d.cp)
	if d.room != "" and not DB.rooms.has(d.room): return {"ok": false, "error": "unknown room"}
	return {"ok": true, "data": d, "saved": doc.get("saved", "")}

func migrate(d, from):
	if from < 2:
		if not d.has("stims"): d["stims"] = 3
	return d

func load_game(s):
	var r = read_slot(s)
	if not r.ok: return false
	slot = s
	state = r.data
	return true

func delete_slot(s):
	if FileAccess.file_exists(slot_path(s)): DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(s)))

func load_meta():
	if FileAccess.file_exists("user://meta.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://meta.json"))
		if typeof(d) == TYPE_DICTIONARY:
			if typeof(d.get("endings")) == TYPE_DICTIONARY: meta.endings = d.endings
			if typeof(d.get("settings")) == TYPE_DICTIONARY:
				for k in d.settings:
					if settings.has(k) and typeof(settings[k]) == typeof(d.settings[k]) or (settings.has(k) and typeof(d.settings[k]) in [TYPE_INT, TYPE_FLOAT]):
						settings[k] = d.settings[k]

func save_meta():
	var fa = FileAccess.open("user://meta.json", FileAccess.WRITE)
	if fa: fa.store_string(JSON.stringify({"endings": meta.endings, "settings": settings}))

# ---------------------------------------------------------------- settings & input
func apply_settings():
	if DisplayServer.get_name() != "headless":
		var want = DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want: DisplayServer.window_set_mode(want)
	AudioServer.set_bus_volume_db(0, linear_to_db(max(0.0001, settings.master)))
	var snd = get_node_or_null("/root/Snd")
	if snd: snd.apply_volumes()

func setup_input():
	for a in ACTIONS:
		var id = a[0]
		if InputMap.has_action(id): InputMap.erase_action(id)
		InputMap.add_action(id, 0.4)
		var b = settings.binds.get(id, {})
		var keys = b.get("k", a[2])
		var joys = b.get("j", a[3])
		for k in keys:
			var ev = InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(id, ev)
		for j in joys:
			var ev = InputEventJoypadButton.new()
			ev.button_index = int(j)
			InputMap.action_add_event(id, ev)
		if a[4] != null:
			var ev = InputEventJoypadMotion.new()
			ev.axis = a[4][0]
			ev.axis_value = a[4][1]
			InputMap.action_add_event(id, ev)
	# menu confirm also on jump / interact pad buttons handled by menus

func rebind(id, ev):
	var b = settings.binds.get(id, {})
	if ev is InputEventKey: b["k"] = [ev.physical_keycode]
	elif ev is InputEventJoypadButton: b["j"] = [ev.button_index]
	else: return
	settings.binds[id] = b
	setup_input()
	save_meta()

func bind_text(id):
	var out = []
	for ev in InputMap.action_get_events(id):
		if ev is InputEventKey: out.append(OS.get_keycode_string(ev.physical_keycode))
		elif ev is InputEventJoypadButton: out.append("Pad" + str(ev.button_index))
	return " / ".join(out)

func key_hint(id):
	for ev in InputMap.action_get_events(id):
		if ev is InputEventKey: return OS.get_keycode_string(ev.physical_keycode)
	return id
