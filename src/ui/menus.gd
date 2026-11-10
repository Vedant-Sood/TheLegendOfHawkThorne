extends CanvasLayer
# All navigation uses G.ACTIONS. The same drawn list serves keyboard and gamepad.
const Art = preload("res://src/core/art.gd")
const SIZE = Vector2(1280, 720)
const INK = Color("e7edf5")
const MUTED = Color("95a7bc")
const ACCENT = Color("7ad7c0")
const GOLD = Color("edbd7f")
const ENDINGS = ["mesh", "sever", "ascend", "dominion", "steward"]
const JOURNAL_TABS = ["Quests", "Relationships", "Dialogue History", "Codex"]
const INVENTORY_TABS = ["Key Items", "Mods", "Abilities"]

class MenuCanvas extends Control:
	var host = null
	func _draw():
		if host:
			draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(1280, 720))
			host._draw_menu(self)

var screen = ""
var args = {}
var items = []
var selected = 0
var scroll = 0
var tab = 0
var history = []
var capture_action = ""
var status = ""
var status_time = 0.0
var elapsed = 0.0
var active = false
var paused_by_menu = false
var root_control = null
var canvas = null
var sky = null
var transition = null
var nav_direction = ""
var nav_wait = 0.0
var map_rooms = []
var map_edges = []
var star_positions = {}

func _ready():
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_view()

func _ensure_view():
	if root_control != null: return
	root_control = Control.new()
	root_control.name = "MenuRoot"
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	sky = ColorRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.color = Color("030711")
	if ResourceLoader.exists("res://shaders/sky.gdshader"):
		var material = ShaderMaterial.new()
		material.shader = load("res://shaders/sky.gdshader")
		sky.material = material
	root_control.add_child(sky)
	canvas = MenuCanvas.new()
	canvas.host = self
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(canvas)
	root_control.hide()

func open(name, options = {}):
	_ensure_view()
	if name == "main": _release_pause()
	if name == "pause" or (G.level != null and name != "main"):
		if not get_tree().paused:
			get_tree().paused = true
			paused_by_menu = true
	history.clear()
	active = true
	_show(str(name), options)
	if name == "main": Snd.music("menu")

func close_all():
	active = false
	capture_action = ""
	history.clear()
	nav_direction = ""
	_release_pause()
	if root_control == null: return
	if transition: transition.kill()
	transition = create_tween().set_parallel(true)
	transition.tween_property(root_control, "modulate:a", 0.0, 0.16)
	transition.tween_property(canvas, "position:x", 28.0, 0.16)
	transition.chain().tween_callback(root_control.hide)

func is_open() -> bool:
	return active

func _release_pause():
	if paused_by_menu and is_inside_tree(): get_tree().paused = false
	paused_by_menu = false

func _exit_tree():
	if transition: transition.kill()
	_release_pause()

func _show(name, options = {}, restore = {}):
	screen = name
	args = options.duplicate(true)
	selected = int(restore.get("selected", 0))
	scroll = int(restore.get("scroll", 0))
	tab = int(restore.get("tab", 0))
	capture_action = ""
	status = ""
	nav_direction = ""
	_build_items()
	sky.visible = screen == "main"
	root_control.show()
	if transition: transition.kill()
	root_control.modulate.a = 0.0
	canvas.position.x = 28.0
	transition = create_tween().set_parallel(true)
	transition.tween_property(root_control, "modulate:a", 1.0, 0.2)
	transition.tween_property(canvas, "position:x", 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	canvas.queue_redraw()

func _push(name, options = {}):
	history.append({"screen": screen, "args": args.duplicate(true), "selected": selected, "scroll": scroll, "tab": tab})
	_show(name, options)

func _back():
	Snd.sfx("ui_back")
	if capture_action != "":
		capture_action = ""
		return
	if not history.is_empty():
		var prev = history.pop_back()
		_show(prev.screen, prev.args, prev)
	elif screen != "main": close_all()

func _item(id, label, value = "", detail = "", extra = {}):
	var result = {"id": id, "label": label, "value": str(value), "detail": str(detail), "disabled": false}
	result.merge(extra, true)
	items.append(result)

func _build_items():
	items.clear()
	match screen:
		"main":
			var latest = _latest_slot()
			_item("continue", "Continue", "", "Return to your most recent journey.", {"slot": latest, "disabled": latest == 0})
			_item("new", "New Game", "", "Begin a new journey through the dying stars.")
			_item("load", "Load Game", "", "Choose from three saved journeys.")
			_item("settings", "Settings", "", "Controls, sound and accessibility.")
			_item("endings", "Endings & Records", "%d / 5" % G.meta.endings.size(), "Every choice leaves a different constellation.")
			_item("credits", "Credits")
			_item("quit", "Quit")
		"slots":
			for n in range(1, G.SLOTS + 1):
				var result = G.read_slot(n)
				var detail = str(result.get("error", "empty"))
				var value = detail.capitalize()
				if result.ok:
					var chapter = DB.chapters.get(int(result.data.get("chapter", 1)), {})
					value = chapter.get("title", "Chapter %s" % result.data.get("chapter", 1))
					detail = "Chapter %d · %s played\nSaved %s\n%s" % [int(result.data.get("chapter", 1)), _playtime(result.data.get("time", {})), result.get("saved", "Unknown date"), result.data.get("room", "")]
				_item("slot", "Slot %d" % n, value, detail, {"slot": n, "disabled": args.get("mode", "load") == "load" and not result.ok})
				if result.get("error", "") != "empty":
					_item("delete_slot", "Delete slot %d" % n, "", "Permanently remove this save. A confirmation follows.", {"slot": n})
		"pause":
			for entry in [["resume", "Resume"], ["journal", "Journal"], ["map", "Map"], ["inventory", "Inventory"], ["settings", "Settings"], ["save_quit", "Save & Quit to Title"]]:
				_item(entry[0], entry[1])
		"settings":
			for spec in [["master", "Master Volume"], ["music", "Music Volume"], ["sfx", "Effects Volume"], ["shake", "Screen Shake"]]:
				_item("setting", spec[1], "%d%%" % round(float(G.settings[spec[0]]) * 100), "Left / right to adjust.", {"key": spec[0]})
			_item("setting", "Text Speed", "%.1f×" % G.settings.text_speed, "Adjust dialogue reveal speed from 0.5× to 3×.", {"key": "text_speed"})
			_item("setting", "Difficulty", ["Story", "Normal", "Hard"][clampi(int(G.settings.difficulty), 0, 2)], "Story softens incoming damage; Hard increases it.", {"key": "difficulty"})
			for spec in [["fullscreen", "Fullscreen"], ["contrast", "High Contrast"], ["flash", "Reduce Flashes"], ["big_text", "Large Text"], ["auto_parry", "Auto-Parry Assist"], ["slow", "Slow Motion (80%)"]]:
				var enabled = bool(G.settings[spec[0]])
				if spec[0] == "flash": enabled = not enabled
				_item("setting", spec[1], "On" if enabled else "Off", "Confirm or left / right to toggle.", {"key": spec[0]})
			_item("bindings", "Control Bindings", "Configure", "Remap keyboard keys and controller buttons.")
		"bindings":
			for action in G.ACTIONS:
				_item("binding", action[1], G.bind_text(action[0]), "Confirm, then press a key or controller button. Back cancels capture.", {"key": action[0]})
			_item("reset_bindings", "Reset to Defaults", "", "Restore the original keyboard and controller bindings.")
		"journal": _journal_items()
		"inventory": _inventory_items()
		"upgrades":
			for upgrade in DB.upgrades:
				var level = int(G.state.upgrades.get(upgrade[0], 0))
				var cost = int(upgrade[4]) * (level + 1)
				_item("upgrade", upgrade[1], "MAX" if level >= upgrade[3] else "%d shards" % cost, "%s\nLevel %d / %d" % [upgrade[2], level, upgrade[3]], {"key": upgrade[0], "cost": cost, "max": upgrade[3], "disabled": level >= upgrade[3] or int(G.state.shards) < cost})
		"starmap": _destination_items()
		"map": _local_map_items()
		"credits":
			_item("read", "Hawkthorne", "Ashes of the Stars", "A science-fiction action-adventure about memory, loyalty and the lives we leave behind.")
			_item("read", "Development", "The Hawkthorne project", "Created collaboratively for TheLegendOfHawkThorne. See the repository history for contributor credits.")
			_item("read", "Engine", "Godot Engine", "Made with Godot Engine, released under the MIT license. godotengine.org/license")
			_item("read", "Art & Sound", "Procedural", "Every skyline, portrait, sound and musical phrase is generated in code.")
		"endings":
			for id in ENDINGS:
				var record = G.meta.endings.get(id, {})
				_item("read", id.capitalize() if not record.is_empty() else "Unknown ending", "Recorded" if not record.is_empty() else "Undiscovered", "%s\nJourney time: %s\nRecorded: %s" % [id.capitalize(), _duration(float(record.get("time", 0))), record.get("date", "")] if not record.is_empty() else "The choices you make will shape what remains.")
		"confirm":
			_item("cancel", "Cancel", "", args.get("message", ""))
			_item("confirm", args.get("label", "Confirm"), "", args.get("message", ""))
		_:
			_item("read", "Screen unavailable", "", "Unknown menu: " + screen)
	if items.is_empty(): _item("read", "No entries yet", "", "Your discoveries will appear here.")
	selected = clampi(selected, 0, items.size() - 1)
	_sync_scroll()

func _journal_items():
	match tab:
		0:
			for completed in [false, true]:
				for id in G.state.quests:
					var stage = int(G.state.quests[id])
					if (stage >= 99) != completed or stage <= 0: continue
					var quest = DB.quests.get(id, {"title": str(id).capitalize(), "stages": {}})
					_item("read", quest.title, "Completed" if completed else "Active", quest.stages.get(stage, quest.stages.get(str(stage), "Stage %d" % stage)))
		1:
			for who in G.state.rel:
				var value = float(G.state.rel[who])
				var word = "Estranged" if value <= -5 else "Wary" if value < 0 else "Acquainted" if value < 3 else "Trusted" if value < 7 else "Devoted"
				_item("read", DB.speaker(who).name, word, "Trust: %d\nYour conversations and choices shape this bond." % value, {"portrait": who})
		2:
			for index in range(G.state.log.size() - 1, -1, -1):
				var line = G.state.log[index]
				if line is Array and line.size() >= 2:
					_item("read", DB.speaker(str(line[0])).name if str(line[0]) != "narr" else "Narration", "#%d" % (index + 1), str(line[1]))
		3:
			for flag in G.state.flags:
				if not str(flag).begins_with("lore.") or not G.state.flags[flag]: continue
				var id = str(flag).trim_prefix("lore.")
				var text = "Recovered archive: " + id.replace("_", " ")
				var node = DB.resolve("lore_" + id)
				# Once-only entries still belong in the codex after being read.
				if node == null and DB.nodes.has("lore_" + id) and not DB.nodes["lore_" + id].is_empty(): node = DB.nodes["lore_" + id][0]
				if node != null:
					var lines = []
					for entry in node.get("items", []):
						if entry.get("k", "") == "line": lines.append(entry.get("text", ""))
					if not lines.is_empty(): text = "\n".join(lines)
				_item("read", id.replace("_", " ").capitalize(), "Recovered", text)

func _inventory_items():
	match tab:
		0:
			for id in G.state.items:
				if G.state.items[id]: _item("read", DB.items.get(id, str(id).capitalize()), "Key Item", "Kept safely aboard the Cinder Wren.")
		1:
			for id in G.state.mods:
				var mod_data = DB.mods.get(id, {"name": str(id), "desc": ""})
				_item("mod", mod_data.name, "Equipped" if id in G.state.equipped else "Available", mod_data.desc + "\nEquip up to two mods. Confirm to equip or remove.", {"key": id})
		2:
			for id in DB.abilities:
				_item("read", DB.abilities[id], "Unlocked" if G.state.abilities.get(id, 0) else "Locked", "Technique available." if G.state.abilities.get(id, 0) else "Continue your journey to learn this technique.")

func _destination_items():
	var chapter = int(G.state.chapter)
	if DB.chapters.has(chapter):
		var current = DB.chapters[chapter]
		_item("travel", current.title, "Main Objective", current.get("act", ""), {"room": current.room, "region": current.region, "main": true})
	for dest in DB.side_dest:
		if G.cond(dest[4]):
			_item("travel", dest[1], "Optional", "Travel to " + DB.regions.get(dest[2], {}).get("name", dest[2]), {"room": dest[3], "region": dest[2]})
	for n in DB.chapters:
		if int(n) >= chapter: continue
		var previous = DB.chapters[n]
		_item("travel", previous.title, "Revisit", "Chapter %s · Free roam" % n, {"room": previous.room, "region": previous.region})
	star_positions.clear()
	var keys = DB.regions.keys()
	for i in keys.size():
		var angle = -PI * 0.5 + i * TAU / keys.size()
		star_positions[keys[i]] = Vector2(978 + cos(angle) * 182, 352 + sin(angle) * 156)

func _local_map_items():
	map_rooms.clear()
	map_edges.clear()
	var start = DB.chapters.get(int(G.state.chapter), {}).get("room", G.state.room)
	var pending = [start]
	var seen = {}
	while not pending.is_empty():
		var id = str(pending.pop_front())
		if seen.has(id) or not DB.rooms.has(id): continue
		seen[id] = true
		map_rooms.append(id)
		var room = DB.rooms[id]
		var targets = []
		if str(room.get("exit", "")) != "": targets.append(str(room.exit).split(":")[0])
		for door in room.get("D", []): targets.append(str(door).split(":")[0])
		for target in targets:
			if not DB.rooms.has(target): continue
			map_edges.append([id, target])
			if not seen.has(target): pending.append(target)
	for id in map_rooms:
		var room = DB.rooms[id]
		var visited = G.state.visited.has(id)
		_item("read", room.get("name", id) if visited or id == G.state.room else "Unexplored", "You are here" if id == G.state.room else "Visited" if visited else "Unknown", DB.regions.get(room.get("region", ""), {}).get("name", ""), {"room": id})

func _latest_slot():
	var latest = 0
	var newest = ""
	for n in range(1, G.SLOTS + 1):
		var result = G.read_slot(n)
		if result.ok and (latest == 0 or str(result.get("saved", "")) > newest):
			latest = n
			newest = str(result.get("saved", ""))
	return latest

func _playtime(times):
	var total = 0.0
	if times is Dictionary:
		for amount in times.values(): total += float(amount)
	return _duration(total)

func _duration(seconds):
	var minutes = int(seconds) / 60
	return "%dh %02dm" % [int(minutes / 60), minutes % 60]

func _process(dt):
	elapsed += dt
	if active and sky != null and sky.material != null:
		sky.material.set_shader_parameter("clock", elapsed)
		sky.material.set_shader_parameter("reduced_flashes", not G.settings.flash)
		sky.material.set_shader_parameter("high_contrast", G.settings.contrast)
	if status_time > 0:
		status_time -= dt
		if status_time <= 0: status = ""
	if active and capture_action == "":
		var direction = ""
		for action in ["up", "down", "left", "right"]:
			if Input.is_action_pressed(action):
				direction = action
				break
		if direction == "":
			nav_direction = ""
			nav_wait = 0.0
		elif direction != nav_direction:
			nav_direction = direction
			nav_wait = 0.35
			_navigate(direction)
		else:
			nav_wait -= dt
			if nav_wait <= 0:
				nav_wait = 0.11
				_navigate(direction)
	if canvas and root_control.visible: canvas.queue_redraw()

func _input(event):
	if not active: return
	if capture_action != "":
		if event.is_action_pressed("pause") or event.is_action_pressed("dash"):
			_back()
		elif ((event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed)):
			if event is InputEventKey and event.physical_keycode == 0: event.physical_keycode = event.keycode
			G.rebind(capture_action, event)
			capture_action = ""
			_build_items()
			Snd.sfx("ui_ok")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("dash"):
		_back()
	elif event.is_action_pressed("accept") or event.is_action_pressed("jump") or event.is_action_pressed("interact"):
		_activate()
	# Consume all input while open so gameplay cannot react behind a menu.
	get_viewport().set_input_as_handled()

func _navigate(direction):
	if items.is_empty(): return
	if direction in ["left", "right"]:
		var step = -1 if direction == "left" else 1
		if screen == "settings":
			_adjust_setting(step)
			return
		if screen in ["journal", "inventory"]:
			var count = JOURNAL_TABS.size() if screen == "journal" else INVENTORY_TABS.size()
			tab = posmod(tab + step, count)
			selected = 0
			scroll = 0
			_build_items()
		else:
			selected = posmod(selected + step, items.size())
	else:
		selected = posmod(selected + (-1 if direction == "up" else 1), items.size())
	_sync_scroll()
	Snd.sfx("ui")

func _visible_rows():
	return 7 if G.settings.big_text else 9

func _sync_scroll():
	var rows = _visible_rows()
	scroll = clampi(scroll, 0, maxi(0, items.size() - rows))
	if selected < scroll: scroll = selected
	if selected >= scroll + rows: scroll = selected - rows + 1

func _activate():
	if items.is_empty(): return
	var item = items[selected]
	if item.get("disabled", false):
		_notify("Not available" if item.id != "upgrade" else "More shards are needed, or this upgrade is complete.")
		return
	Snd.sfx("ui_ok")
	match item.id:
		"continue": _main_call("continue_game", [item.slot])
		"new": _push("slots", {"mode": "new"})
		"load": _push("slots", {"mode": "load"})
		"settings", "bindings", "journal", "inventory", "map", "endings", "credits": _push(item.id)
		"resume": close_all()
		"quit": _confirm("Quit Hawkthorne?", "Quit", {"action": "quit"})
		"save_quit":
			if G.main == null or not G.main.has_method("to_menu"):
				_notify("The title-screen transition is not available yet.")
			elif G.save_game(): _main_call("to_menu", [])
			else: _notify("Could not save. Your journey is still open; please try again.")
		"slot":
			if args.get("mode", "load") == "load": _main_call("continue_game", [item.slot])
			elif G.read_slot(item.slot).get("error", "") != "empty":
				_confirm("Overwrite slot %d? The previous journey will be replaced." % item.slot, "Overwrite & Begin", {"action": "new_game", "slot": item.slot})
			else: _main_call("new_game", [item.slot])
		"delete_slot": _confirm("Permanently delete slot %d?" % item.slot, "Delete Save", {"action": "delete_slot", "slot": item.slot})
		"setting": _adjust_setting(1)
		"binding": capture_action = item.key
		"reset_bindings": _confirm("Restore all keyboard and controller bindings?", "Reset Bindings", {"action": "reset_bindings"})
		"mod":
			if item.key in G.state.equipped: G.state.equipped.erase(item.key)
			elif G.state.equipped.size() < 2: G.state.equipped.append(item.key)
			else: _notify("Two mods are equipped. Remove one before equipping another.")
			_build_items()
		"upgrade":
			var level = int(G.state.upgrades.get(item.key, 0))
			if level < int(item.max) and G.state.shards >= item.cost:
				G.state.shards -= item.cost
				G.state.upgrades[item.key] = level + 1
				_notify("Installed " + item.label)
			_build_items()
		"travel":
			if not DB.rooms.has(item.room): _notify("This destination is not available yet.")
			else: _main_call("load_room", [item.room])
		"cancel": _back()
		"confirm": _perform_confirmation()

func _confirm(message, label, operation):
	_push("confirm", {"message": message, "label": label, "operation": operation})

func _perform_confirmation():
	var operation = args.get("operation", {})
	match operation.get("action", ""):
		"quit": get_tree().quit()
		"new_game": _main_call("new_game", [operation.slot])
		"delete_slot":
			G.delete_slot(operation.slot)
			_back()
			_build_items()
		"reset_bindings":
			G.settings.binds = {}
			G.setup_input()
			G.save_meta()
			_back()
			_build_items()

func _main_call(method, arguments):
	if G.main == null or not G.main.has_method(method):
		_notify("This journey is not available yet.")
		return false
	close_all()
	G.main.callv(method, arguments)
	return true

func _adjust_setting(direction):
	if items.is_empty() or items[selected].id != "setting": return
	var key = items[selected].key
	match key:
		"master", "music", "sfx", "shake": G.settings[key] = clampf(round((float(G.settings[key]) + direction * 0.1) * 10.0) / 10.0, 0.0, 1.0)
		"text_speed": G.settings[key] = clampf(round((float(G.settings[key]) + direction * 0.1) * 10.0) / 10.0, 0.5, 3.0)
		"difficulty": G.settings[key] = posmod(int(G.settings[key]) + direction, 3)
		_: G.settings[key] = not bool(G.settings[key])
	G.apply_settings()
	G.save_meta()
	_build_items()
	Snd.sfx("ui")

func _notify(message):
	status = message
	status_time = 5.0
	G.toast.emit(message)

func _draw_menu(ci):
	var big = bool(G.settings.big_text)
	var text_size = 25 if big else 21
	var high = bool(G.settings.contrast)
	var muted = Color("c9d6e8") if high else MUTED
	var main = screen == "main"
	ci.draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.012, 0.021, 0.038, 0.28 if main else 0.98 if high else 0.94))
	if main: _draw_title_sky(ci)
	ci.draw_line(Vector2(64, 54), Vector2(1216, 54), Color(ACCENT, 0.3), 1)
	Art.text(ci, Vector2(64, 41), "CINDER WREN  /  NAVIGATION SYSTEM", 13, muted)
	Art.text(ci, Vector2(1010, 41), "ASHES OF THE STARS", 13, muted)
	if main:
		Art.text_shadow(ci, Vector2(80, 133), "HAWKTHORNE", 57, INK)
		Art.text(ci, Vector2(85, 168), "A S H E S   O F   T H E   S T A R S", 19, GOLD)
	else:
		Art.text(ci, Vector2(80, 117), _title(), 36 if big else 32, INK)
		Art.text(ci, Vector2(80, 148), _subtitle(), 16 if big else 14, muted)
	var list_top = 219.0 if main else 204.0
	if screen in ["journal", "inventory"]:
		var tabs = JOURNAL_TABS if screen == "journal" else INVENTORY_TABS
		var tab_x = 80.0
		for i in tabs.size():
			Art.text(ci, Vector2(tab_x, 181), tabs[i], 18 if big else 16, ACCENT if i == tab else muted)
			var width = Art.font().get_string_size(tabs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18 if big else 16).x
			if i == tab: ci.draw_line(Vector2(tab_x, 188), Vector2(tab_x + width, 188), ACCENT, 2)
			tab_x += width + 32
	var row_height = 53.0 if big else 42.0
	var list_width = 600.0
	for i in range(scroll, mini(items.size(), scroll + _visible_rows())):
		var item = items[i]
		var y = list_top + (i - scroll) * row_height
		var chosen = i == selected
		var disabled = item.get("disabled", false)
		if chosen:
			ci.draw_rect(Rect2(76, y - 27, list_width + 22, row_height - 4), Color(0.12, 0.25, 0.28, 0.9 if high else 0.7))
			ci.draw_rect(Rect2(76, y - 27, 3, row_height - 4), GOLD if disabled else ACCENT)
			Art.text(ci, Vector2(88, y), "›", text_size + 3, GOLD if disabled else ACCENT)
		var label = _ellipsize(str(item.label), 350 if item.value != "" else 550, text_size)
		Art.text(ci, Vector2(110, y), label, text_size, muted if disabled else INK)
		if item.value != "":
			Art.text(ci, Vector2(463, y), _ellipsize(str(item.value), 218, 17 if big else 15), 17 if big else 15, GOLD if chosen else muted)
	if items.size() > _visible_rows():
		var track = Rect2(708, list_top - 27, 2, row_height * _visible_rows() - 4)
		ci.draw_rect(track, Color(muted, 0.2))
		var thumb_h = maxf(14, track.size.y * _visible_rows() / items.size())
		var thumb_y = track.position.y + (track.size.y - thumb_h) * scroll / maxi(1, items.size() - _visible_rows())
		ci.draw_rect(Rect2(track.position.x, thumb_y, 2, thumb_h), ACCENT)
		Art.text(ci, Vector2(606, 622), "%d / %d" % [selected + 1, items.size()], 14, muted)
	if screen == "starmap": _draw_starmap(ci)
	elif screen == "map": _draw_local_map(ci)
	elif not items.is_empty():
		var item = items[selected]
		var detail_y = 253.0
		if item.has("portrait"):
			Art.portrait(ci, item.portrait, Rect2(790, 204, 180, 190), "", elapsed, false)
			detail_y = 432
		elif main:
			Art.text(ci, Vector2(790, 440), "SOME STARS LEAVE ASHES.", 18, GOLD)
			detail_y = 480
		else:
			Art.text(ci, Vector2(790, 213), _ellipsize(str(item.label).to_upper(), 390, 17), 17, GOLD)
		_draw_wrapped(ci, str(item.detail), Vector2(790, detail_y), 390, 22 if big else 19, muted, 6 if item.has("portrait") or main else 13)
	if screen == "confirm":
		_draw_wrapped(ci, args.get("message", ""), Vector2(790, 256), 390, 23 if big else 21, INK, 9)
	if status != "":
		ci.draw_rect(Rect2(76, 626, 1128, 30), Color("182c36"))
		Art.text(ci, Vector2(88, 648), _ellipsize(status, 1100, 17), 17, GOLD)
	ci.draw_line(Vector2(64, 668), Vector2(1216, 668), Color(ACCENT, 0.3), 1)
	var footer = "↑ ↓  Navigate    " + G.key_hint("accept") + " / " + G.key_hint("jump") + "  Select    " + G.key_hint("pause") + " / Pad B  Back"
	if screen in ["journal", "inventory"]: footer = "← →  Tabs    " + footer
	elif screen == "settings": footer = "← →  Adjust    " + footer
	Art.text(ci, Vector2(80, 698), _ellipsize(footer, 1120, 15 if big else 14), 15 if big else 14, muted)
	if capture_action != "":
		ci.draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.005, 0.01, 0.02, 0.9))
		ci.draw_rect(Rect2(300, 270, 680, 170), Color("142531"))
		ci.draw_rect(Rect2(300, 270, 680, 170), ACCENT, false, 2)
		Art.text(ci, Vector2(340, 322), "REBIND " + capture_action.to_upper(), 24, GOLD)
		Art.text(ci, Vector2(340, 369), "Press a key or controller button", 25, INK)
		Art.text(ci, Vector2(340, 413), "Pause / Back cancels", 18, muted)

func _title():
	match screen:
		"slots": return "BEGIN A JOURNEY" if args.get("mode", "load") == "new" else "SAVED JOURNEYS"
		"pause": return "JOURNEY PAUSED"
		"starmap": return "THE EXPANSE"
		"map": return "LOCAL SURVEY"
		"upgrades": return "CINDER WREN WORKBENCH"
		"endings": return "ENDINGS & RECORDS"
		"confirm": return "CONFIRM YOUR CHOICE"
		_: return screen.to_upper()

func _subtitle():
	match screen:
		"upgrades": return "%d SHARDS AVAILABLE" % int(G.state.shards)
		"inventory": return "%d / 2 MODS EQUIPPED  ·  %d SHARDS" % [G.state.equipped.size(), int(G.state.shards)]
		"starmap": return "Select a destination to set course."
		"map": return "Explored rooms are illuminated. Your current position is marked."
		"settings": return "Changes are saved automatically."
		"slots": return "Three journeys. Each leaves its own mark."
		"journal": return "THE THINGS WE CHOOSE TO REMEMBER"
		_: return "THE CINDER WREN  /  PERSONAL TERMINAL"

func _ellipsize(text, width, font_size):
	if Art.font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width: return text
	var result = text
	while result.length() > 0 and Art.font().get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		result = result.left(result.length() - 1)
	return result + "…"

func _draw_wrapped(ci, text, origin, width, font_size, color, max_lines):
	var lines = []
	for paragraph in text.split("\n"):
		var line = ""
		for word in paragraph.split(" "):
			var candidate = word if line == "" else line + " " + word
			if line != "" and Art.font().get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				lines.append(line)
				line = word
			else: line = candidate
		lines.append(line)
	for i in mini(lines.size(), max_lines):
		var value = lines[i]
		if i == max_lines - 1 and lines.size() > max_lines: value = _ellipsize(value + " …", width, font_size)
		Art.text(ci, origin + Vector2(0, i * (font_size + 8)), value, font_size, color)

func _draw_title_sky(ci):
	# Procedural stars also provide a fallback if the sky shader is still being authored.
	for i in 100:
		var x = fposmod(i * 193.73 + sin(i * 2.3) * 100, 1280)
		var y = fposmod(i * 87.31, 660)
		var alpha = 0.2 + 0.2 * sin(elapsed * 0.3 + i)
		ci.draw_circle(Vector2(x, y), 1.0 if i % 4 else 1.7, Color(0.7, 0.83, 1, alpha))
	var center = Vector2(1040 + sin(elapsed * 0.09) * 8, 292)
	Art.glow(ci, center, 206, Color(0.18, 0.38, 0.55, 0.22))
	ci.draw_circle(center, 106, Color("111d30"))
	ci.draw_arc(center, 109, -1.5, 1.5, 80, Color("88aeb8"), 2)
	ci.draw_arc(center, 145, -2.2, 0.8, 80, Color(0.5, 0.73, 0.8, 0.24), 1)
	ci.draw_arc(center, 167, 0.1, 2.5, 80, Color(0.5, 0.73, 0.8, 0.14), 1)
	var ship = Vector2(933, 359 + sin(elapsed * 0.5) * 4)
	ci.draw_colored_polygon(PackedVector2Array([ship + Vector2(-57, 9), ship + Vector2(47, -9), ship + Vector2(71, 1), ship + Vector2(-26, 24), ship + Vector2(-6, 1)]), Color("344b5c"))
	ci.draw_line(ship + Vector2(8, 1), ship + Vector2(46, -3), ACCENT, 2)
	Art.glow(ci, ship + Vector2(-36, 13), 17, Color(0.35, 0.8, 1, 0.7))

func _draw_starmap(ci):
	if star_positions.is_empty(): return
	var current = DB.chapters.get(int(G.state.chapter), {}).get("region", "")
	var selected_region = items[selected].get("region", "")
	var origin_region = DB.rooms.get(G.state.room, {}).get("region", "ship")
	var origin = star_positions.get(origin_region, Vector2(978, 352))
	for region in star_positions:
		var point = star_positions[region]
		var color = GOLD if region == current else ACCENT if region == selected_region else MUTED
		if region == selected_region:
			ci.draw_line(origin, point, Color(ACCENT, 0.55), 1.5)
			ci.draw_arc(point, 14 + sin(elapsed * 2), 0, TAU, 32, ACCENT, 1.5)
		Art.glow(ci, point, 18 if region == current else 11, Color(color, 0.3))
		ci.draw_circle(point, 5 if region == current else 3, color)
		Art.text(ci, point + Vector2(-48, 23), _ellipsize(DB.regions[region].name, 135, 12), 12, color)
	if not items.is_empty():
		_draw_wrapped(ci, items[selected].label, Vector2(790, 564), 390, 19, GOLD, 3)

func _draw_local_map(ci):
	if map_rooms.is_empty():
		_draw_wrapped(ci, "No survey data is available for this chapter.", Vector2(790, 240), 390, 21, MUTED, 5)
		return
	var positions = {}
	var rows = int(ceil(map_rooms.size() / 3.0))
	var cell_h = minf(78, 356.0 / maxi(1, rows))
	for i in map_rooms.size(): positions[map_rooms[i]] = Vector2(796 + (i % 3) * 132, 224 + int(i / 3) * cell_h)
	for edge in map_edges:
		if positions.has(edge[0]) and positions.has(edge[1]):
			ci.draw_line(positions[edge[0]] + Vector2(51, 16), positions[edge[1]] + Vector2(51, 16), Color(MUTED, 0.35), 1.5)
	for id in map_rooms:
		var rect = Rect2(positions[id], Vector2(108, minf(36, cell_h - 4)))
		var known = G.state.visited.has(id) or id == G.state.room
		var color = GOLD if id == G.state.room else ACCENT if known else Color("536171")
		ci.draw_rect(rect, Color("13232f") if known else Color("0a111c"))
		ci.draw_rect(rect, color, false, 2 if id == items[selected].get("room", "") else 1)
		Art.text(ci, rect.position + Vector2(5, minf(23, cell_h - 10)), _ellipsize(DB.rooms[id].get("name", id) if known else "?", 98, 12), 12, color)
	_draw_wrapped(ci, items[selected].label, Vector2(790, 615), 390, 18, GOLD, 2)
