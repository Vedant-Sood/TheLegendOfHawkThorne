extends SceneTree
# Called by run_tests.gd in a separate process for every room, so any engine
# script error is captured even when Godot itself would exit successfully.
var level
var room_id = ""
var frames = 0
var started_at = 0
var watchdog_seconds = 30
var save_directory = ""

func _initialize():
	call_deferred("_run")

func _run():
	var args = OS.get_cmdline_user_args()
	var index = args.find("--room")
	if index < 0 or index + 1 >= args.size():
		printerr("SMOKE_FAIL: --room <id> is required")
		quit(1)
		return
	room_id = args[index + 1]
	var db = root.get_node_or_null("DB")
	var game = root.get_node_or_null("G")
	if db == null or game == null or not db.rooms.has(room_id):
		printerr("SMOKE_FAIL: database or room is unavailable")
		quit(1)
		return
	# Keep the autoload node (and thus the registered G singleton identity),
	# replacing only its save destinations. Level checkpoints cannot overwrite
	# a real player's files during a smoke run.
	var fixture = load("res://tests/game_fixture.gd")
	if fixture == null or not fixture.can_instantiate():
		printerr("SMOKE_FAIL: isolated game fixture cannot instantiate")
		quit(1)
		return
	save_directory = "user://test_runs/smoke_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(save_directory) != OK:
		printerr("SMOKE_FAIL: cannot create isolated save directory")
		quit(1)
		return
	game.set_script(fixture)
	game.test_directory = save_directory
	var script = load("res://src/world/level.gd")
	if script == null or not script.can_instantiate():
		printerr("SMOKE_FAIL: level script cannot instantiate")
		quit(1)
		return
	level = script.new()
	if not level.has_method("setup"):
		printerr("SMOKE_FAIL: level must expose setup(room_id, entry='start')")
		level.free()
		quit(1)
		return
	game.state = game.new_state()
	game.state.room = room_id
	game.clock_on = false
	game.level = level
	root.add_child(level)
	level.setup(room_id, "start")
	started_at = Time.get_ticks_msec()
	for i in 120:
		await physics_frame
		frames += 1
		if not is_instance_valid(level) or not level.is_inside_tree():
			printerr("SMOKE_FAIL: level exited during frame %d" % frames)
			quit(1)
			return
	await process_frame
	print("SMOKE_COMPLETE %s %d" % [room_id, frames])
	game.level = null
	level.queue_free()
	await process_frame
	var directory = DirAccess.open(save_directory)
	if directory:
		for file in directory.get_files(): directory.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_directory))
	quit(0)

func _process(_dt):
	if started_at > 0 and Time.get_ticks_msec() - started_at > watchdog_seconds * 1000:
		printerr("SMOKE_FAIL: physics stopped after %d frames" % frames)
		quit(1)
	return false
