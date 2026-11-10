extends SceneTree
# Integration tests for the secondary-owned modules, using temporary authored-data
# fixtures. This does not certify the campaign; run run_tests.gd for that gate.
# Add -- --render --screenshots /absolute/directory under Xvfb for image checks.
var passed = 0
var failed = 0
var db
var game
var render = false
var output = ""
var completions = 0
var backups = {}

class MainFixture extends Node:
	var calls = []
	func new_game(slot): calls.append(["new_game", slot])
	func continue_game(slot): calls.append(["continue_game", slot])
	func load_room(room, _entry = "start"): calls.append(["load_room", room])
	func to_menu(): calls.append(["to_menu"])

func _initialize(): call_deferred("_run")

func check(ok, message):
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL: " + message)

func _node(path):
	var script = load("res://" + path)
	if script == null or not script.can_instantiate():
		check(false, "script instantiates: " + path)
		return null
	var node = script.new()
	root.add_child(node)
	return node

func _run():
	db = root.get_node("DB")
	game = root.get_node("G")
	# This suite owns UI/visual behavior; audio is primary-owned. Keep visual
	# runs deterministic and avoid queued music playbacks during engine teardown.
	root.get_node("Snd").mute = true
	var arguments = OS.get_cmdline_user_args()
	render = "--render" in arguments
	var index = arguments.find("--screenshots")
	if index >= 0 and index + 1 < arguments.size(): output = arguments[index + 1]
	if render and DisplayServer.get_name() == "headless":
		check(false, "--render requires a graphical display (use xvfb-run)")
		quit(1)
		return
	if output != "" and DirAccess.make_dir_recursive_absolute(output) != OK:
		check(false, "create screenshot directory")
		quit(1)
		return
	# Protect existing user data, even if invoked outside an isolated XDG directory.
	for file in ["user://meta.json", "user://save_slot1.json", "user://save_slot2.json", "user://save_slot3.json"]:
		backups[file] = FileAccess.get_file_as_bytes(file) if FileAccess.file_exists(file) else null
	var state = game.state.duplicate(true)
	var settings = game.settings.duplicate(true)
	var main = game.main
	var level = game.level
	var dev = game.dev
	var meta = game.meta.duplicate(true)
	var rooms = db.rooms.duplicate(true)
	var quests = db.quests.duplicate(true)
	var nodes = db.nodes.duplicate(true)
	var old_slot = game.slot
	game.state = game.new_state()
	game.level = null
	db.rooms["kr_docks"] = {"id": "kr_docks", "name": "Test docks", "region": "kharon", "exit": "__corridor:start", "D": ["__branch:start"]}
	db.rooms["__corridor"] = {"id": "__corridor", "name": "Test corridor", "region": "kharon", "exit": "kr_docks:start"}
	db.rooms["__branch"] = {"id": "__branch", "name": "Test branch", "region": "kharon"}
	db.quests["__quest"] = {"title": "A Test Journey", "type": "side", "stages": {1: "Look for the signal.", 99: "The signal is restored."}}
	db.nodes["lore___entry"] = [{"once": false, "cond": "", "key": "seen.__entry", "items": [{"k": "line", "text": "An archive recovered from the dark."}]}]
	var fixture = MainFixture.new()
	root.add_child(fixture)
	game.main = fixture
	await _test_menus(fixture)
	await _test_scenery()
	await _test_vistas()
	await _test_flight()
	await _test_console(fixture)
	game.state = state
	game.settings = settings
	game.meta = meta
	game.main = main
	game.level = level
	game.dev = dev
	game.slot = old_slot
	db.rooms = rooms
	db.quests = quests
	db.nodes = nodes
	paused = false
	fixture.free()
	for path in backups:
		if backups[path] == null:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_buffer(backups[path])
	game.setup_input()
	game.apply_settings()
	# Let the audio thread release procedural WAV playbacks before engine teardown.
	var sound = root.get_node("Snd")
	sound.set_process(false)
	for child in sound.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	await process_frame
	await process_frame
	print("SECONDARY RESULT: %d passed; %d failed; render=%s" % [passed, failed, render])
	quit(1 if failed > 0 else 0)

func _capture(label):
	await process_frame
	await process_frame
	if not render: return
	await create_timer(0.25, true).timeout
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	if image.is_empty():
		check(false, label + " produced an image")
		return
	var colors = {}
	for y in range(4, image.get_height(), 8):
		for x in range(4, image.get_width(), 8): colors[image.get_pixel(x, y).to_html()] = true
	check(colors.size() > 8, label + " renders a nonblank frame")
	if output != "": check(image.save_png(output.path_join(label + ".png")) == OK, label + " screenshot saved")

func _select(menu, id, key = "", value = ""):
	for i in menu.items.size():
		var item = menu.items[i]
		if item.id == id and (key == "" or str(item.get(key, "")) == value):
			menu.selected = i
			menu._sync_scroll()
			return true
	check(false, "menu contains " + id + " " + value)
	return false

func _test_menus(main):
	print("SUITE: menus, controller input, settings, inventory, maps and saves")
	var menu = _node("src/ui/menus.gd")
	if menu == null: return
	menu.open("main")
	check(menu.is_open() and menu.layer == 30, "main opens on the menu layer")
	check(root.get_node("Snd").theme == "menu", "main requests the menu music theme")
	await _capture("menu_main")
	menu.set_process(false)
	var before = menu.selected
	Input.action_press("down")
	menu._process(0.01)
	Input.action_release("down")
	menu._process(0.01)
	check(menu.selected == before + 1, "menu action navigation advances selection")
	var pad = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	menu._input(pad)
	check(menu.screen == "slots" and menu.args.mode == "new", "controller confirm opens new-game slots")
	menu._activate()
	check(main.calls.back() == ["new_game", 1], "empty slot starts the requested new game")
	# Populate all slots to check the most-recent rule rather than slot order.
	game.state.room = "kr_docks"
	for slot in range(1, 4):
		var data = game.state.duplicate(true)
		var document = {"version": game.SAVE_VERSION, "sum": (JSON.stringify(data) + game.SALT).sha256_text(), "saved": "2026-11-%02dT10:00:00" % (12 - slot), "data": data}
		var file = FileAccess.open(game.slot_path(slot), FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
		file.close()
	menu.open("main")
	check(menu._latest_slot() == 1, "Continue selects the latest valid save timestamp")
	menu._activate()
	check(main.calls.back() == ["continue_game", 1], "Continue calls the selected slot")
	menu.open("slots", {"mode": "new"})
	menu._activate()
	check(menu.screen == "confirm", "occupied slot requires overwrite confirmation")
	menu._back()
	check(menu.screen == "slots", "cancel overwrite returns to slots")
	_select(menu, "delete_slot", "slot", "1")
	menu._activate()
	check(menu.screen == "confirm" and game.read_slot(1).ok, "deletion leaves data intact before confirmation")
	menu.selected = 1
	menu._activate()
	check(game.read_slot(1).get("error", "") == "empty", "confirmed deletion removes only the selected slot")
	menu.open("pause")
	check(paused, "pause menu pauses the tree")
	menu.close_all()
	check(not paused, "closing an owned pause restores gameplay")
	paused = true
	menu.open("pause")
	menu.close_all()
	check(paused, "closing preserves a pause owned by another system")
	paused = false
	menu.open("settings")
	_select(menu, "setting", "key", "master")
	game.settings.master = 1.0
	menu._adjust_setting(1)
	check(game.settings.master == 1.0, "volume clamps at maximum")
	menu._adjust_setting(-1)
	check(is_equal_approx(game.settings.master, 0.9), "volume adjusts in ten-percent steps")
	for key in ["fullscreen", "contrast", "flash", "big_text", "auto_parry", "slow"]:
		if key == "fullscreen": continue # avoid changing the user's actual window mode
		_select(menu, "setting", "key", key)
		var old = game.settings[key]
		menu._activate()
		check(game.settings[key] != old, "accessibility setting toggles: " + key)
	check(FileAccess.file_exists("user://meta.json"), "settings are persisted")
	await _capture("menu_settings")
	menu.open("bindings")
	check(menu.items.size() == game.ACTIONS.size() + 1, "every action is listed for rebinding")
	_select(menu, "binding", "key", "attack")
	menu._activate()
	var key = InputEventKey.new()
	key.physical_keycode = KEY_U
	key.keycode = KEY_U
	key.pressed = true
	menu._input(key)
	check(game.settings.binds.attack.k == [KEY_U], "key capture uses production rebinding API")
	_select(menu, "reset_bindings")
	menu._activate()
	menu.selected = 1
	menu._activate()
	check(game.settings.binds.is_empty(), "binding reset restores defaults after confirmation")
	game.state.mods = ["edge", "plating", "siphon"]
	game.state.equipped = []
	menu.open("inventory")
	menu._navigate("right")
	for i in 3:
		menu.selected = i
		menu._activate()
	check(game.state.equipped == ["edge", "plating"], "inventory prevents equipping a third mod")
	menu.selected = 0
	menu._activate()
	check(game.state.equipped == ["plating"], "inventory unequips selected mod")
	await _capture("menu_inventory")
	game.state.shards = 100000
	menu.open("upgrades")
	var cost = menu.items[0].cost
	var upgrade = menu.items[0].key
	menu._activate()
	check(game.state.shards == 100000 - cost and game.state.upgrades[upgrade] == 1, "workbench charges shards and grants exactly one level")
	var limit = menu.items[0].max
	for i in range(limit + 2): menu._activate()
	check(game.state.upgrades[upgrade] == limit, "workbench enforces the maximum upgrade level")
	game.state.quests = {"__quest": 99}
	game.state.flags["lore.__entry"] = 1
	game.state.log = [["sable", "The stars are not silent."]]
	menu.open("journal")
	check(menu.items[0].value == "Completed", "journal displays completed quest state")
	for i in 4:
		await _capture("journal_%d" % menu.tab)
		menu._navigate("right")
	menu.open("starmap")
	check(menu.star_positions.size() == db.regions.size(), "star chart includes every region")
	await _capture("menu_starmap")
	_select(menu, "travel", "room", "kr_docks")
	menu._activate()
	check(main.calls.back() == ["load_room", "kr_docks"], "star chart loads the selected destination")
	game.state.visited = {"kr_docks": 1}
	menu.open("map")
	check(menu.map_rooms.size() == 3 and menu.map_edges.size() == 3, "local map follows exits and branch doors without cycling")
	await _capture("menu_map")
	for screen in ["slots", "credits", "endings"]:
		menu.open(screen, {"mode": "load"})
		check(not menu.items.is_empty(), screen + " has entries")
		await _capture("menu_" + screen)
	menu.close_all()
	menu.free()

func _test_scenery():
	print("SUITE: all regions, parallax wrap, post processing and accessibility")
	var backdrop = _node("src/world/backdrop.gd")
	var post = _node("src/world/post.gd")
	if backdrop == null or post == null: return
	game.settings.flash = true
	game.settings.contrast = false
	for region in db.regions:
		backdrop.setup(region, {})
		post.setup(region)
		backdrop.update_view(Vector2(9000, 400), 18.0)
		check(backdrop.depths.size() == 4 and backdrop.weather.kind == db.regions[region].weather, "region has parallax depths and correct weather: " + region)
		for part in backdrop.depths:
			check(part.position.x <= 0 and part.position.x > -2560, "parallax wraps within the tile period")
		await _capture("region_" + region)
	post.set_dark(2, Vector2(640, 360))
	post.set_desat(-1)
	check(post.darkness == 1 and post.desaturation == 0, "post process clamps effect strengths")
	post.pulse(2)
	check(post.hit_amount == 1, "damage pulse clamps to one")
	post._process(1)
	check(post.hit_amount == 0, "damage pulse decays")
	game.settings.flash = false
	post.pulse(1)
	check(post.hit_amount == 0, "reduced flashes suppresses damage aberration")
	game.settings.contrast = true
	post.set_dark(0.65, Vector2(640, 360))
	post.set_desat(0.5)
	backdrop.update_view(Vector2(640, 360), 20.0)
	post._process(0)
	await _capture("region_accessibility")
	post.free()
	backdrop.free()

func _test_vistas():
	print("SUITE: every cinematic vista")
	var vista = _node("src/ui/vista.gd")
	if vista == null: return
	for name in vista.NAMES:
		vista.show_vista(name)
		vista._process(1)
		check(vista.visible_now() and vista.scene_name == name, "vista opens: " + name)
		await _capture("vista_" + name)
	vista.hide_vista()
	vista._process(1)
	check(not vista.visible_now(), "vista fades away after hiding")
	vista.free()

func _test_flight():
	print("SUITE: piloting, pause, loss/retry, safe path and completion")
	var flight = _node("src/world/flight.gd")
	if flight == null: return
	var camera = Camera2D.new()
	camera.position = Vector2(2000, -1000)
	root.add_child(camera)
	camera.make_current()
	flight.set_physics_process(false)
	game.settings.slow = false
	game.state.rel.sable = 3
	flight.start({"length_sec": 3, "density": 2.5, "region": "orbit"}, func(): completions += 1)
	check(flight.hull == 3 and flight.assist and flight.running, "flight starts with hull and earned Sable projection")
	flight.local_paused = true
	flight._physics_process(0.25)
	check(flight.elapsed == 0, "flight pause freezes simulation")
	flight.local_paused = false
	var position = flight.ship_pos
	Input.action_press("up")
	flight._physics_process(0.1)
	Input.action_release("up")
	check(flight.ship_pos.y < position.y, "up action steers the ship")
	flight._hit()
	flight._hit()
	flight._hit()
	check(flight.hull == 0 and flight.restart_delay > 0, "three hits trigger a delayed retry")
	flight._physics_process(3)
	check(flight.hull == 3 and flight.elapsed == 0 and flight.attempt == 2, "failed approach restarts with full hull and reset time")
	for i in 180:
		flight.ship_pos.y = flight._path_y(flight.ship_pos.x + flight.distance)
		flight.velocity = Vector2.ZERO
		flight._physics_process(1.0 / 60.0)
	check(flight.hull == 3, "Sable projection follows a collision-free route")
	await _capture("flight")
	flight._physics_process(0.1)
	flight._physics_process(1.3)
	await process_frame
	check(not flight.running and completions == 1, "flight completes and calls back exactly once")
	flight._physics_process(1)
	await process_frame
	check(completions == 1, "completion callback cannot fire again")
	game.state.rel.sable = 0
	flight.start({"length_sec": -1, "density": -1}, Callable())
	check(not flight.assist and flight.config.length_sec == 1 and flight.config.density == 0.15, "unearned projection stays off and invalid flight configuration clamps")
	game.settings.slow = true
	flight._physics_process(0.1)
	check(is_equal_approx(flight.elapsed, 0.08), "flight applies the 80-percent slow-motion setting")
	flight.free()
	camera.free()

func _test_console(main):
	print("SUITE: developer command validation and isolation")
	game.dev = true
	var console = _node("src/dev/console.gd")
	if console == null: return
	game.dev = false
	check(console.execute("give 100").contains("disabled"), "console commands cannot execute without dev mode")
	game.dev = true
	check(console.execute("give -10").contains("Usage"), "console rejects negative shard grants")
	var shards = game.state.shards
	console.execute("give 100")
	check(game.state.shards == shards + 100, "console grants the requested shards")
	console.execute("rel sable 100")
	check(game.state.rel.sable == 10, "console relationship edits respect game bounds")
	check(console.execute("rel nonexistent 2").contains("Unknown"), "console rejects unknown relationships")
	console.execute("flag console_test 3")
	check(game.val("console_test") == 3, "console sets narrative flags")
	console.execute("unlock all")
	check(game.state.abilities.size() == db.abilities.size(), "console unlocks all known abilities")
	check(console.execute("chapter 99").contains("Unknown"), "console rejects invalid chapters")
	console.execute("room kr_docks")
	check(main.calls.back() == ["load_room", "kr_docks"], "console loads a known room through main API")
	console.execute("chapter 1")
	check(game.state.chapter == 1 and main.calls.back() == ["load_room", "kr_docks"], "console sets chapter before loading its entry room")
	check(console.execute("room __absent").contains("Unknown"), "console rejects unknown rooms")
	console.execute("god")
	check(game.state.flags["dev.god"], "console toggles primary player god-mode integration flag")
	var enemy = Node.new()
	root.add_child(enemy)
	enemy.add_to_group("enemies")
	check(console.execute("kill") == "Removed 1 enemies.", "console kill visits the enemies group")
	game.state.hp = 1
	console.execute("heal")
	check(game.state.hp == game.max_hp() and game.state.stims == game.max_stims(), "console heals persistent stats")
	check(console.execute("time").contains("Active time:"), "console reports active gameplay time")
	check(console.execute("save").begins_with("Saved slot"), "console persists an active game with production save API")
	var toggle = InputEventKey.new()
	toggle.keycode = KEY_QUOTELEFT
	toggle.physical_keycode = KEY_QUOTELEFT
	toggle.pressed = true
	console._input(toggle)
	check(paused and console.opened, "developer overlay pauses gameplay")
	await _capture("console")
	console.set_open(false)
	check(not paused, "console releases only its owned pause")
	console.free()
