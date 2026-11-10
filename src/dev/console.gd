extends CanvasLayer
# Deliberately a command whitelist: never evaluate arbitrary script from the console.
const Art = preload("res://src/core/art.gd")
const HELP = "room <id> | chapter <1..14> | flag <name> <number> | rel <who> <number>\ngive <shards> | unlock <ability|all> | god | kill | heal | save | time | help"
var opened = false
var input_line = ""
var lines = []
var history = []
var history_pos = 0
var draft_line = ""
var scroll = 0
var panel = null
var was_paused = false
var age = 0.0

class Surface extends Control:
	var console = null
	func _draw():
		if console != null: console.paint(self)

func _ready():
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = Surface.new()
	panel.console = self
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.hide()
	append("HAWKTHORNE / developer console — help lists commands")
	set_process_input(G.dev)

func _process(dt):
	if opened and not G.dev: set_open(false)
	if opened:
		age += dt
		panel.queue_redraw()

func _exit_tree():
	if opened and get_tree() != null: get_tree().paused = was_paused

func set_open(value):
	value = value and G.dev
	if value == opened: return
	opened = value
	if opened:
		was_paused = get_tree().paused
		get_tree().paused = true
		panel.show()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		get_tree().paused = was_paused
		panel.hide()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event):
	if not G.dev: return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_QUOTELEFT or event.keycode == KEY_QUOTELEFT):
		set_open(not opened)
		get_viewport().set_input_as_handled()
		return
	if not opened: return
	get_viewport().set_input_as_handled()
	if not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_ESCAPE:
			set_open(false)
		KEY_ENTER, KEY_KP_ENTER:
			var command = input_line.strip_edges()
			if command != "":
				append("> " + command)
				append(execute(command))
				if history.is_empty() or history.back() != command: history.append(command)
				if history.size() > 100: history.pop_front()
			input_line = ""
			draft_line = ""
			history_pos = history.size()
			scroll = 0
		KEY_BACKSPACE:
			input_line = input_line.left(max(0, input_line.length() - 1))
		KEY_UP:
			if history_pos == history.size(): draft_line = input_line
			history_pos = max(0, history_pos - 1)
			if not history.is_empty(): input_line = history[history_pos]
		KEY_DOWN:
			history_pos = min(history.size(), history_pos + 1)
			input_line = draft_line if history_pos == history.size() else history[history_pos]
		KEY_PAGEUP:
			scroll = min(max(0, lines.size() - 1), scroll + 8)
		KEY_PAGEDOWN:
			scroll = max(0, scroll - 8)
		_:
			if event.unicode >= 32 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
				if input_line.length() < 180: input_line += String.chr(event.unicode)

func append(message):
	for line in str(message).split("\n"): lines.append(line)
	while lines.size() > 200: lines.pop_front()
	if panel != null: panel.queue_redraw()

func execute(command):
	if not G.dev: return "Developer mode is disabled. Launch with -- --dev."
	var args = str(command).strip_edges().split(" ", false)
	if args.is_empty(): return ""
	var verb = args[0].to_lower()
	match verb:
		"help": return HELP
		"room":
			if args.size() != 2: return "Usage: room <id>"
			if not DB.rooms.has(args[1]): return "Unknown room: " + args[1]
			if not _can_load(): return "Room loading is unavailable: main.load_room is not connected."
			set_open(false)
			G.main.load_room(args[1])
			return "Travelled to " + args[1]
		"chapter":
			if args.size() != 2 or not args[1].is_valid_int(): return "Usage: chapter <1..14>"
			var n = int(args[1])
			if not DB.chapters.has(n): return "Unknown chapter. Expected 1..14."
			var room = DB.chapters[n].room
			if not DB.rooms.has(room): return "Chapter room is missing: " + room
			if not _can_load(): return "Room loading is unavailable: main.load_room is not connected."
			G.state.chapter = n
			G.state.flags["sable_stage"] = G.sable_stage()
			set_open(false)
			G.main.load_room(room)
			return "Chapter %d: %s" % [n, DB.chapters[n].title]
		"flag", "rel":
			if args.size() != 3 or not args[2].is_valid_float(): return "Usage: %s <name> <number>" % verb
			var value = float(args[2])
			if not is_finite(value): return "Value must be finite."
			if verb == "rel":
				if not G.state.rel.has(args[1]): return "Unknown relationship: " + args[1]
				G.setv("rel." + args[1], value)
				return "%s relationship = %s" % [args[1], G.state.rel[args[1]]]
			G.state.flags[args[1]] = value
			return "%s = %s" % [args[1], value]
		"give":
			if args.size() != 2 or not args[1].is_valid_int() or int(args[1]) < 0: return "Usage: give <nonnegative shards>"
			var amount = int(args[1])
			if amount > 1000000000: return "Give at most 1000000000 shards at a time."
			G.state.shards += amount
			return "Shards: %d" % G.state.shards
		"unlock":
			if args.size() != 2: return "Usage: unlock <ability|all>"
			if args[1] == "all":
				for id in DB.abilities: G.state.abilities[id] = 1
				return "All %d abilities unlocked." % DB.abilities.size()
			if not DB.abilities.has(args[1]): return "Unknown ability: " + args[1]
			G.state.abilities[args[1]] = 1
			return "Unlocked " + DB.ability_name(args[1])
		"god":
			if args.size() != 1: return "Usage: god"
			var enabled = not bool(G.state.flags.get("dev.god", false))
			G.state.flags["dev.god"] = enabled
			return "God mode request: %s (player damage must honor dev.god)." % ("ON" if enabled else "OFF")
		"kill":
			if args.size() != 1: return "Usage: kill"
			var count = 0
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
					if enemy.has_method("die"): enemy.die()
					else: enemy.queue_free()
					count += 1
			return "Removed %d enemies." % count
		"heal":
			if args.size() != 1: return "Usage: heal"
			G.state.hp = G.max_hp()
			G.state.stims = G.max_stims()
			if is_instance_valid(G.level):
				var player = G.level.get("player")
				if is_instance_valid(player) and player.has_method("full_heal"): player.full_heal()
			return "Vitality and stims restored."
		"save":
			if args.size() != 1: return "Usage: save"
			return "Saved slot %d." % G.slot if G.save_game() else "Save failed: no active room or user directory is not writable."
		"time":
			return "Active time: %.1f minutes; chapter %d: %.1f minutes." % [G.total_time() / 60.0, G.state.chapter, float(G.state.time.get(str(G.state.chapter), 0.0)) / 60.0]
	return "Unknown command: %s. Type help." % verb

func _can_load():
	return is_instance_valid(G.main) and G.main.has_method("load_room")

func paint(ci):
	var size = ci.get_viewport_rect().size
	var height = min(400.0, size.y * 0.6)
	var font_size = 22 if G.settings.big_text else 18
	var row_height = font_size + 7
	ci.draw_rect(Rect2(0, 0, size.x, height), Color(0.015, 0.025, 0.04, 0.98))
	ci.draw_line(Vector2(0, height), Vector2(size.x, height), Color("60d0ff"), 2.0)
	Art.text(ci, Vector2(22, 30), "CINDER WREN / DEBUG", font_size, Color("60d0ff"))
	Art.text(ci, Vector2(size.x - 390, 30), "` close   ↑↓ history   PgUp/PgDn scroll", 14, Color("a0a8b8"))
	var rows = max(1, int((height - 105) / row_height))
	var end = max(0, lines.size() - scroll)
	var begin = max(0, end - rows)
	for i in range(begin, end):
		Art.text(ci, Vector2(22, 65 + (i - begin) * row_height), lines[i], font_size, Color("d8dde8"), HORIZONTAL_ALIGNMENT_LEFT, size.x - 44)
	var shown = input_line
	while Art.font().get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 70:
		shown = shown.substr(1)
	Art.text(ci, Vector2(22, height - 22), "> " + shown + ("_" if fmod(age, 1.0) < 0.5 else ""), font_size, Color("ffb060"))
