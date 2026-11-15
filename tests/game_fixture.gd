extends "res://src/core/game.gd"
# Exercise the production state and save code without touching a player's slots,
# metadata, settings, or telemetry. Only filesystem destinations are replaced.
var test_directory = ""
var telemetry = []
var metadata_writes = 0

func _ready():
	state = new_state()

func _process(_dt):
	pass

func slot_path(s):
	return test_directory.path_join("slot_%d.json" % s)

func _telemetry(line):
	telemetry.append(line)

func save_meta():
	metadata_writes += 1
