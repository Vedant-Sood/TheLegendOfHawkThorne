extends Node
# Main — scene flow: owns the current Level and the persistent UI layers.

const Level = preload("res://src/world/level.gd")
const HUD = preload("res://src/ui/hud.gd")
const DialogueUI = preload("res://src/ui/dialogue_ui.gd")
const Fallback = preload("res://src/ui/fallback_menu.gd")

var level = null
var hud = null
var dialogue = null
var menus = null
var vista = null
var console = null
var fade_rect = null
var fade_a = 1.0
var fade_to = 0.0
var fade_speed = 3.0
var loading = false
var timers = []
var shot_path = ""
var shot_t = 3.0
var bot = false
var bot_t = 0.0

func _ready():
	G.main = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = HUD.new()
	add_child(hud)
	dialogue = DialogueUI.new()
	add_child(dialogue)
	menus = _opt("res://src/ui/menus.gd")
	if menus == null:
		menus = Fallback.new()
		add_child(menus)
	vista = _opt("res://src/ui/vista.gd")
	if G.dev: console = _opt("res://src/dev/console.gd")
	var fl = CanvasLayer.new()
	fl.layer = 40
	add_child(fl)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(fade_rect)
	var start_room = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--room="): start_room = a.substr(7)
		if a.begins_with("--chapter="): G.state.chapter = int(a.substr(10))
		if a.begins_with("--shot="): shot_path = a.substr(7)
		if a.begins_with("--shot-t="): shot_t = float(a.substr(9))
		if a == "--bot": bot = true
	if start_room != "" and DB.rooms.has(start_room):
		G.slot = 9
		G.clock_on = true
		for ab in DB.abilities: G.state.abilities[ab] = 1
		load_room(start_room)
	else: to_menu()

func _opt(path):
	if not ResourceLoader.exists(path): return null
	var n = load(path).new()
	add_child(n)
	return n

func busy(): return loading or (menus != null and menus.is_open())
func after(t, fn): timers.append([t, fn])

func fade(to, seconds):
	fade_to = to
	fade_speed = 1.0 / max(0.01, seconds)

func to_menu():
	if level != null:
		level.queue_free()
		level = null
	G.level = null
	G.clock_on = false
	fade(0.0, 0.5)
	menus.open("main")

func open_menu(n, args = {}): menus.open(n, args)

func new_game(slot):
	G.slot = slot
	G.state = G.new_state()
	G.clock_on = true
	load_room(DB.chapters[1].room)

func continue_game(slot):
	if not G.load_game(slot): return
	G.clock_on = true
	load_room(G.state.room, "cp:%d" % G.state.cp)

func load_room(id, entry = "start"):
	if loading or not DB.rooms.has(id):
		if not DB.rooms.has(id): push_warning("unknown room " + str(id))
		return
	loading = true
	fade(1.0, 0.22)
	after(0.25, _do_load.bind(id, entry))

func _do_load(id, entry):
	if level != null:
		level.queue_free()
		level = null
	var first = not G.state.visited.has(id)
	if not entry.begins_with("cp:"): G.state.cp = 0
	level = Level.new()
	add_child(level)
	move_child(level, 0)
	level.setup(id, entry)
	G.level = level
	loading = false
	fade(0.0, 0.4)
	if G.slot != 9: G.save_game()
	var room = DB.rooms[id]
	if first: hud.show_banner(room.name, DB.regions[room.region].name)
	if room.has("enter"): after(0.5, func(): dialogue.play(room.enter))

func _dev_tools(dt):
	if bot and level != null:
		bot_t += dt
		Input.action_press("right")
		for a in ["jump", "attack", "dash", "accept"]:
			if randf() < 0.04: Input.action_press(a)
			elif randf() < 0.3: Input.action_release(a)
	if shot_path != "":
		shot_t -= dt
		if shot_t <= 0:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()

func _process(dt):
	_dev_tools(dt)
	var i = 0
	while i < timers.size():
		timers[i][0] -= dt
		if timers[i][0] <= 0:
			var fn = timers[i][1]
			timers.remove_at(i)
			fn.call()
		else: i += 1
	fade_a = move_toward(fade_a, fade_to, dt * fade_speed)
	fade_rect.color.a = fade_a
	if G.pending_goto != "" and not dialogue.active and not loading:
		var t = G.pending_goto
		G.pending_goto = ""
		match t:
			"hub": load_room("ship_hub")
			"menu": to_menu()
			"credits":
				to_menu()
				open_menu("credits")
			_: load_room(t)
	if level != null and not dialogue.active and not busy():
		if Input.is_action_just_pressed("pause"): open_menu("pause")
		elif Input.is_action_just_pressed("journal"): open_menu("journal")
