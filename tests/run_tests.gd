extends SceneTree
# Run the complete campaign/state suite:
# godot --headless --path . -s tests/run_tests.gd
# -- --unit-only runs ONLY isolated state, saves, and graph regression tests.
# A missing campaign is a failure in the default mode, never a passing empty run.
const Graph = preload("res://tests/platform_graph.gd")
var passed = 0
var failed = 0
var skipped = 0
var db
var game
var directory = ""

func _initialize():
	call_deferred("_run")

func _check(ok, message):
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: " + message)
	return ok

func _skip(message):
	skipped += 1
	print("SKIP: " + message)

func _run():
	db = root.get_node_or_null("DB")
	if not _check(db != null, "DB autoload exists"):
		_finish()
		return
	var unit_only = "--unit-only" in OS.get_cmdline_user_args()
	print("MODE: isolated units only" if unit_only else "MODE: full campaign and units")
	# Autoload global names are not registered during SceneTree entry-script
	# compilation; load the production subclass after the autoloads are ready.
	var fixture_script = load("res://tests/game_fixture.gd")
	if not _check(fixture_script != null and fixture_script.can_instantiate(), "production game fixture compiles"):
		_finish()
		return
	game = fixture_script.new()
	directory = "user://test_runs/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if not _check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated test-save directory"):
		game.free()
		_finish()
		return
	game.test_directory = directory
	root.add_child(game)
	_test_conditions_and_effects()
	_test_saves()
	_test_graph()
	if unit_only:
		_skip("campaign data, chapter connectivity, all-room reachability, and 120-frame level smoke (explicit --unit-only)")
	else:
		_test_database()
		_test_chapters()
		_test_room_graphs()
		await _test_level_smoke()
	game.free()
	_clean_directory()
	_finish()

func _finish():
	print("RESULT: %d passed; %d failed; %d skipped" % [passed, failed, skipped])
	quit(1 if failed > 0 else 0)

func _clean_directory():
	# Remove only the unique directory created by this run, never user slots.
	var dir = DirAccess.open(directory)
	if dir:
		for file in dir.get_files(): dir.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))

func _test_conditions_and_effects():
	print("SUITE: production G.cond / G.apply / progression")
	game.state = game.new_state()
	var cases = [["", true], ["missing", false], ["!missing", true], ["ch==1", true],
		["ch>=1&ch<=1", true], ["ch>1", false], ["ch<2", true], ["ch!=2", true],
		["missing|ch==1", true], ["ch==1&missing|ch==2", false], [" ch == 1 & !missing ", true]]
	for case in cases:
		_check(game.cond(case[0]) == case[1], "condition '%s' returns %s" % [case[0], case[1]])
	game.apply("test_flag=1;rel.sable+4;rel.sable-1;give:shards:100;unlock:dash;item:recording;mod:edge;quest:__test_quest:1;core:hp")
	_check(game.cond("test_flag&rel.sable==3&shards>=100&ab.dash&item.recording&q.__test_quest==1&up.core_hp==1"), "effects expose values in every supported namespace")
	_check(game.state.mods == ["edge"] and game.state.equipped == ["edge"], "a first acquired mod equips")
	game.apply("mod:edge;mod:plating;mod:siphon;quest:__test_quest:99;quest:__test_quest:2")
	_check(game.state.mods.size() == 3 and game.state.equipped.size() == 2, "mod acquisition deduplicates and caps automatic equipment at two")
	_check(game.state.quests.__test_quest == 99, "completed quests cannot regress")
	game.apply("rel.sable+100;shards-500")
	_check(game.state.rel.sable == 10 and game.state.shards == 0, "relationships and shard subtraction clamp")
	game.apply("rel.sable-100;test_flag=0;chapter:4;chapter:2;goto:__test_room")
	_check(game.state.rel.sable == -10 and game.cond("!test_flag"), "negative relationship and cleared flag")
	_check(game.state.chapter == 4 and game.sable_stage() == 2, "chapter progression is monotonic and advances Sable")
	_check(game.pending_goto == "__test_room", "goto effect schedules the requested room")
	game.state.bosses["hauler"] = 1
	_check(game.cond("boss.hauler&!boss.echo"), "boss conditions use boss state")
	_check(game.max_hp() == 110 and game.blade_dmg() == 22, "upgrades and equipped mod affect derived stats")
	game.apply("ending:mesh")
	_check(game.meta.endings.has("mesh") and game.metadata_writes == 1, "ending records invoke metadata persistence (isolated fixture)")
	game.state = game.new_state()

func _write_doc(data, version):
	var doc = {"version": version, "sum": (JSON.stringify(data) + game.SALT).sha256_text(), "saved": "test-run", "data": data}
	var file = FileAccess.open(game.slot_path(game.slot), FileAccess.WRITE)
	if not _check(file != null, "open isolated save fixture"): return
	file.store_string(JSON.stringify(doc))
	file.close()

func _test_saves():
	print("SUITE: production save/load, checksum rejection, migration")
	var room_id = "__test_room_%d" % OS.get_process_id()
	_check(not db.rooms.has(room_id), "isolated room fixture does not overwrite authored content")
	db.rooms[room_id] = {"id": room_id}
	game.state = game.new_state()
	game.slot = 1
	_check(not game.save_game(), "saving before entering a room is refused")
	_check(game.read_slot(1).error == "empty", "unused slot is reported empty")
	game.state.room = room_id
	game.state.chapter = 3
	game.state.cp = 2
	game.state.shards = 517
	game.state.rel.sable = -2
	game.state.flags["round_trip"] = 1
	game.state.time["1"] = 12.5
	game.state.items["recording"] = 1
	var original = JSON.stringify(game.state)
	_check(game.save_game(), "save_game writes an isolated slot")
	var result = game.read_slot(1)
	_check(result.ok, "fresh save checksum and schema validate")
	if result.ok:
		_check(JSON.stringify(result.data) == original, "all state fields round-trip through JSON unchanged")
	game.state = game.new_state()
	_check(game.load_game(1) and JSON.stringify(game.state) == original, "load_game restores state and selected slot")
	var document = JSON.parse_string(FileAccess.get_file_as_string(game.slot_path(1)))
	document.data.shards = 999999
	var file = FileAccess.open(game.slot_path(1), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	result = game.read_slot(1)
	_check(not result.ok and result.error == "checksum mismatch", "tampering without a matching checksum is rejected")
	var before = JSON.stringify(game.state)
	_check(not game.load_game(1) and JSON.stringify(game.state) == before, "invalid load leaves the current state untouched")
	var old = JSON.parse_string(original)
	old.erase("stims")
	old.erase("stats")
	_write_doc(old, 1)
	result = game.read_slot(1)
	_check(result.ok and result.data.get("stims") == 3 and result.data.has("stats"), "version-one saves migrate stims and fill missing fields")
	_write_doc(JSON.parse_string(original), game.SAVE_VERSION + 1)
	result = game.read_slot(1)
	_check(not result.ok and result.error == "newer version", "future save versions are rejected")
	var bad = JSON.parse_string(original)
	bad.rel = []
	_write_doc(bad, game.SAVE_VERSION)
	result = game.read_slot(1)
	_check(not result.ok and result.error == "invalid field rel", "valid-checksum malformed schema is rejected")
	bad = JSON.parse_string(original)
	bad.room = "__nonexistent_test_room"
	_write_doc(bad, game.SAVE_VERSION)
	result = game.read_slot(1)
	_check(not result.ok and result.error == "unknown room", "unknown save room is rejected")
	game.delete_slot(1)
	_check(not FileAccess.file_exists(game.slot_path(1)), "slot deletion removes only the isolated save")
	db.rooms.erase(room_id)
	game.state = game.new_state()

func _flat(width = 16):
	var grid = PackedByteArray()
	grid.resize(width * 10)
	for x in width: grid[8 * width + x] = 1
	return {"W": width, "H": 10, "grid": grid, "slots": {}}

func _test_graph():
	print("SUITE: standable-tile graph regressions")
	var room = _flat()
	_check(Graph.reach(room, Vector2i(0, 7)).ok, "flat room reaches the right edge")
	for x in range(3, 8): room.grid[8 * room.W + x] = 0
	_check(Graph.reach(room, Vector2i(0, 7)).ok, "six-tile landing distance can be jumped")
	room.grid[8 * room.W + 8] = 0
	_check(not Graph.reach(room, Vector2i(0, 7)).ok, "seven-tile landing distance cannot be jumped")
	room = _flat()
	for y in range(8): room.grid[y * room.W + 7] = 1
	_check(not Graph.reach(room, Vector2i(0, 7)).ok, "a solid full-height wall cannot be crossed")
	for y in range(8): room.grid[y * room.W + 7] = 8
	_check(Graph.reach(room, Vector2i(0, 7)).ok, "gates are considered open")
	room = _flat()
	_check(Graph.edge_clear(room, Vector2i(0, 7), Vector2i(3, 4)), "a three-tile rise is within the jump budget")
	_check(not Graph.edge_clear(room, Vector2i(0, 7), Vector2i(3, 3)), "a four-tile rise exceeds the jump budget")
	room.grid[7 * room.W] = 3
	_check(not Graph.reach(room, Vector2i(0, 7)).ok, "hazardous spawn fails")

func _target(raw):
	return str(raw).strip_edges().get_slice(":", 0)

func _room_links(room):
	var targets = []
	for key in ["exit", "back"]:
		var id = _target(room.get(key, ""))
		if id != "": targets.append(id)
	for door in room.get("D", []):
		var id = _target(door)
		if id != "": targets.append(id)
	return targets

func _room_nodes(room):
	var refs = []
	for key in ["enter", "end"]:
		if str(room.get(key, "")) != "": refs.append(str(room[key]))
	for id in room.get("t", []): refs.append(_target(id))
	for id in room.get("n", []): refs.append("npc_" + _target(id))
	for id in room.get("L", []): refs.append("lore_" + _target(id))
	return refs

func _node_ref(id, source):
	# Validate every authored variant structurally, even when its condition or
	# once flag makes DB.resolve return null in the current playthrough.
	if id == "": return
	_check(db.nodes.has(id) and not db.nodes.get(id, []).is_empty(), "%s references resolvable dialogue '%s'" % [source, id])

func _effects(text, source):
	for effect in str(text).split(";", false):
		var parts = effect.strip_edges().split(":")
		if parts[0] == "quest":
			_check(parts.size() == 3 and db.quests.has(parts[1]), "%s references a valid quest in '%s'" % [source, effect])
		elif parts[0] == "goto" and parts.size() > 1:
			_check(db.rooms.has(parts[1]), "%s goto room '%s' exists" % [source, parts[1]])

func _item_effects(item):
	if item.get("k") == "choice": return item.get("do", "")
	if item.get("k") == "cmd" and item.get("cmd") in ["do", "effect", "effects", "set"]:
		return item.get("args", "")
	return ""

func _test_database():
	print("SUITE: authored database and all cross-references")
	_check(db.errors.is_empty(), "DB loads without errors: " + "; ".join(db.errors))
	for key in ["chunks", "rooms", "quests", "nodes"]:
		_check(not db.get(key).is_empty(), "authored %s are nonempty (zero entries is not validation)" % key)
	for room_id in db.rooms:
		var room = db.rooms[room_id]
		_check(db.regions.has(room.get("region", "")), "room %s has a known region" % room_id)
		_check(not room.get("chunks", []).is_empty(), "room %s has chunks" % room_id)
		for chunk in room.get("chunks", []):
			_check(db.chunks.has(chunk) and not db.chunks.get(chunk, []).is_empty(), "room %s chunk '%s' exists and is nonempty" % [room_id, chunk])
		for target in _room_links(room): _check(db.rooms.has(target), "room %s target '%s' exists" % [room_id, target])
		for id in _room_nodes(room): _node_ref(id, "room " + room_id)
		for enemy in room.get("e", []):
			_check(db.enemies.has(_target(enemy)), "room %s enemy '%s' exists" % [room_id, enemy])
		var boss = _target(room.get("boss", ""))
		if boss != "": _check(db.bosses.has(boss), "room %s boss '%s' exists" % [room_id, boss])
	for id in db.nodes:
		for variant in db.nodes[id]:
			for item in variant.get("items", []):
				if item.get("k") in ["goto", "choice"]: _node_ref(item.get("to", ""), "dialogue " + id)
				if item.get("k") == "line":
					var who = item.get("who", "")
					_check(db.chars.has(who) or db.aliases.has(who), "dialogue %s speaker '%s' is known" % [id, who])
				_effects(_item_effects(item), "dialogue " + id)
	for destination in db.side_dest:
		_check(db.rooms.has(destination[3]), "optional destination %s room exists" % destination[0])
		_check(db.quests.has(destination[5]), "optional destination %s quest exists" % destination[0])

func _dialogue_advances(start, chapter):
	var queue = [start]
	var seen = {}
	while not queue.is_empty():
		var id = queue.pop_back()
		if seen.has(id) or not db.nodes.has(id): continue
		seen[id] = true
		for variant in db.nodes[id]:
			for item in variant.get("items", []):
				for effect in str(_item_effects(item)).split(";", false):
					var parts = effect.strip_edges().split(":")
					if parts.size() == 2 and parts[0] == "chapter" and int(parts[1]) == chapter: return true
				if item.get("k") in ["goto", "choice"] and item.get("to", "") != "": queue.append(item.to)
	return false

func _test_chapters():
	print("SUITE: chapter 1 through 14 connectivity")
	for chapter in range(1, 15):
		if not _check(db.chapters.has(chapter), "chapter %d is defined" % chapter): continue
		var start = db.chapters[chapter].get("room", "")
		if not _check(db.rooms.has(start), "chapter %d start '%s' exists" % [chapter, start]): continue
		if chapter == 14: continue
		var queue = [start]
		var seen = {}
		var advances = false
		while not queue.is_empty() and not advances:
			var id = queue.pop_back()
			if seen.has(id) or not db.rooms.has(id): continue
			seen[id] = true
			var room = db.rooms[id]
			for node in _room_nodes(room):
				if _dialogue_advances(node, chapter + 1): advances = true
			for target in _room_links(room):
				if not seen.has(target): queue.append(target)
		_check(advances, "chapter %d can reach a dialogue effect advancing to chapter %d" % [chapter, chapter + 1])

func _test_room_graphs():
	print("SUITE: platform reachability for every authored room")
	if db.rooms.is_empty():
		_skip("no authored rooms available for platform reachability; database emptiness already failed")
		return
	for room_id in db.rooms:
		var source = db.rooms[room_id]
		var complete = not source.get("chunks", []).is_empty()
		for chunk in source.get("chunks", []):
			if not db.chunks.has(chunk) or db.chunks[chunk].is_empty(): complete = false
		if not complete:
			_skip("room %s graph blocked by invalid chunks (reported by database suite)" % room_id)
			continue
		var room = db.assemble(room_id)
		var spawns = []
		for marker in ["p", "P", "@", "s"]:
			if room.slots.has(marker): spawns.append_array(room.slots[marker])
		if not _check(not spawns.is_empty(), "room %s defines a spawn marker (p/P/@/s)" % room_id): continue
		for spawn in spawns:
			var result = Graph.reach(room, spawn)
			_check(result.ok, "room %s spawn %s reaches right edge: %s" % [room_id, spawn, result.reason])

func _test_level_smoke():
	print("SUITE: real level instances, 120 physics frames per room")
	if not _check(ResourceLoader.exists("res://src/world/level.gd"), "primary-owned src/world/level.gd exists for room smoke"):
		_skip("120-frame room smoke blocked by missing level implementation")
		return
	if not _check(not db.rooms.is_empty(), "at least one authored room can execute the smoke test"): return
	for room_id in db.rooms:
		# Isolate each room in its own engine. Engine script errors do not always
		# produce a nonzero exit code, so inspect output as well as completion.
		var output = []
		var arguments = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/room_smoke.gd", "--", "--room", str(room_id)]
		var exit_code = OS.execute(OS.get_executable_path(), arguments, output, true)
		var log = "\n".join(output)
		var success = exit_code == 0 and log.contains("SMOKE_COMPLETE " + str(room_id) + " 120") and not log.contains("SCRIPT ERROR:") and not log.contains("ERROR:")
		if not _check(success, "room %s completes 120 physics frames without engine/script errors" % room_id): printerr(log)
		await process_frame
