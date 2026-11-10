extends Node2D
## A self-contained piloting interlude. The caller owns insertion/removal and
## suspending the level; completion calls on_done exactly once with no arguments.
const Art = preload("res://src/core/art.gd")
const SIZE = Vector2(1280, 720)
var config = {}
var on_done = Callable()
var running = false
var hull = 3
var elapsed = 0.0
var distance = 0.0
var ship_pos = Vector2(240, 360)
var velocity = Vector2.ZERO
var debris = []
var next_wave = 700.0
var invulnerable = 0.0
var restart_delay = 0.0
var finish_delay = 0.0
var attempt = 0
var callout = ""
var callout_time = 0.0
var last_warning = -1
var local_paused = false
var assist = false
var speed = 270.0
var accent = Color("80daf0")

func _ready():
	z_index = 20
	visible = running

func start(options: Dictionary, finished: Callable):
	config = {
		"length_sec": clamp(float(options.get("length_sec", 35)), 1.0, 600.0),
		"density": clamp(float(options.get("density", 1.0)), 0.15, 3.0),
		"region": str(options.get("region", "orbit")),
	}
	on_done = finished
	var region = DB.regions.get(config.region, DB.regions.orbit)
	accent = DB.C(region.get("acc2", "80daf0"))
	speed = 270.0
	assist = G.val("rel.sable") >= 3
	attempt = 0
	running = true
	visible = true
	local_paused = false
	_restart()
	Snd.music(config.region if Snd.themes.has(config.region) else "orbit")

func _restart():
	attempt += 1
	hull = 3
	elapsed = 0.0
	distance = 0.0
	ship_pos = Vector2(240, _path_y(240))
	velocity = Vector2.ZERO
	debris.clear()
	next_wave = 850.0
	invulnerable = 2.0
	restart_delay = 0.0
	finish_delay = 0.0
	last_warning = -1
	_say("I have a route. Follow my projection." if assist else "Wreckage ahead. Keep the Wren in one piece.")

func _hash(n):
	return fposmod(sin(float(n) * 127.1 + 311.7) * 43758.5453, 1.0)

func _path_y(x):
	return 360.0 + sin(x * 0.0021) * 115.0 + sin(x * 0.0008 + 1.4) * 45.0

func _say(line):
	callout = str(line)
	callout_time = 4.0
	# The interlude draws the callout itself and also records it in the journal.
	G.log_line("sable", callout)

func _unhandled_input(event):
	if not running: return
	if event.is_action_pressed("pause"):
		local_paused = not local_paused
		Snd.sfx("ui_back" if local_paused else "ui_ok")
		get_viewport().set_input_as_handled()
	elif local_paused and (event.is_action_pressed("accept") or event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("dash")):
		local_paused = false
		get_viewport().set_input_as_handled()

func _physics_process(dt):
	if not running: return
	queue_redraw()
	if local_paused: return
	if G.settings.get("slow", false): dt *= 0.8
	callout_time = max(0.0, callout_time - dt)
	invulnerable = max(0.0, invulnerable - dt)
	if restart_delay > 0.0:
		restart_delay = max(0.0, restart_delay - dt)
		if restart_delay == 0.0: _restart()
		return
	if finish_delay > 0.0:
		finish_delay = max(0.0, finish_delay - dt)
		if finish_delay == 0.0:
			running = false
			visible = false
			var done = on_done
			on_done = Callable()
			if done.is_valid(): done.call_deferred()
		return
	elapsed = min(elapsed + dt, float(config.length_sec))
	distance += speed * dt
	var direction = Input.get_vector("left", "right", "up", "down")
	velocity = velocity.move_toward(direction * 340, dt * 1150)
	ship_pos += velocity * dt
	ship_pos.x = clamp(ship_pos.x, 85, 530)
	ship_pos.y = clamp(ship_pos.y, 105, 605)
	while next_wave < distance + 1450:
		_spawn_wave(next_wave)
		next_wave += 440.0 / config.density
	var keep = []
	var closest = null
	for rock in debris:
		var p = Vector2(rock.x - distance, rock.y)
		if p.x < -130: continue
		keep.append(rock)
		if p.x > ship_pos.x + 160 and p.x < ship_pos.x + 600:
			if closest == null or rock.x < closest.x: closest = rock
		if invulnerable <= 0.0 and p.distance_to(ship_pos) < rock.radius + 19:
			_hit()
	debris = keep
	if closest != null and closest.wave != last_warning and callout_time <= 0.0:
		last_warning = closest.wave
		_say("Gap above us — climb." if _path_y(closest.x) < ship_pos.y - 28 else ("Gap below us — descend." if _path_y(closest.x) > ship_pos.y + 28 else "Hold this line. Debris on both sides."))
	if hull > 0 and elapsed >= config.length_sec:
		finish_delay = 1.2
		_say("Clear of the field. Nicely flown, Hawkthorne.")
		Snd.sfx("ui_ok")

func _spawn_wave(x):
	# Every wave leaves a 190 px corridor. Its continuous curve is also the
	# projection: the assist never points through a collision obstacle.
	var center = _path_y(x)
	var wave = int(x)
	for side in [-1, 1]:
		var radius = 26 + _hash(wave + side * 7) * 37
		var y = center + side * (102 + radius)
		debris.append({"x": x, "y": y, "radius": radius, "seed": wave + side * 11, "wave": wave})
	if config.density > 1.4:
		var radius = 20 + _hash(wave + 60) * 18
		var side = 1 if wave % 2 == 0 else -1
		debris.append({"x": x + 75, "y": _path_y(x + 75) + side * (215 + radius), "radius": radius, "seed": wave + 44, "wave": wave})

func _hit():
	hull -= 1
	invulnerable = 1.7
	Snd.sfx("hurt")
	if hull <= 0:
		restart_delay = 2.2
		velocity = Vector2.ZERO
		_say("Hull breach. Rewinding our approach — we can do this.")
	else:
		_say("Hull impact. Two plates holding." if hull == 2 else "Last hull plate. Stay with me.")

func _draw():
	if not running: return
	var viewport_size = get_viewport_rect().size
	# Remain in viewport space even if the caller still has a Camera2D active.
	draw_set_transform_matrix(get_global_transform_with_canvas().affine_inverse() * Transform2D(0.0, Vector2.ZERO).scaled(viewport_size / SIZE))
	for i in 36:
		draw_rect(Rect2(0, i * 20, 1280, 21), Color("030711").lerp(Color("152235"), float(i) / 35))
	Art.glow(self, Vector2(1080 - distance * 0.015, 300), 330, Color(accent.r, accent.g, accent.b, 0.12))
	for i in 170:
		var depth = 0.08 + _hash(i + 50) * 0.28
		var p = Vector2(fposmod(_hash(i) * 1400 - distance * depth, 1400) - 60, 80 + _hash(i + 20) * 540)
		draw_line(p, p + Vector2(1.0 + depth * 12, 0), Color(0.65, 0.8, 1, 0.25 + depth), 1, true)
	# Distant ribs of a destroyed carrier convey motion without adding collisions.
	for i in 5:
		var p = Vector2(fposmod(300 + i * 350 - distance * 0.32, 1800) - 260, 230 + sin(i) * 160)
		draw_arc(p, 100 + i * 7, -1.0 + i, 1.4 + i, 28, Color(0.22, 0.28, 0.36, 0.36), 11, true)
	if assist:
		var route = PackedVector2Array()
		for i in 56:
			var x = 80 + i * 22
			route.append(Vector2(x, _path_y(x + distance)))
		draw_polyline(route, Color(0.4, 0.95, 0.85, 0.12), 15, true)
		draw_polyline(route, Color(0.5, 1, 0.85, 0.72), 2, true)
	for rock in debris: _rock(rock)
	_draw_ship()
	_hud()
	if local_paused:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.02, 0.04, 0.8))
		Art.text(self, Vector2(0, 330), "FLIGHT PAUSED", 36, Color("e2edf4"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		Art.text(self, Vector2(0, 374), "Confirm or Back to resume", 22, Color("9eb8c9"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	elif restart_delay > 0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.06, 0.01, 0.02, 0.58))
		Art.text(self, Vector2(0, 330), "APPROACH LOST", 36, Color("ffc6a7"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		Art.text(self, Vector2(0, 375), "Sable is resetting the flight path…", 22, Color("ccd7e3"), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	elif finish_delay > 0:
		Art.text(self, Vector2(0, 310), "FLIGHT PATH CLEAR", 32, Color("a4efdb"), HORIZONTAL_ALIGNMENT_CENTER, 1280)

func _rock(rock):
	var p = Vector2(rock.x - distance, rock.y)
	var points = PackedVector2Array()
	for i in 9:
		var a = i * TAU / 9 + elapsed * 0.13 + rock.seed
		# Visual radius never exceeds the collision radius.
		points.append(p + Vector2.from_angle(a) * rock.radius * (0.78 + _hash(rock.seed + i) * 0.22))
	draw_colored_polygon(points, Color("303d4a"))
	points.append(points[0])
	draw_polyline(points, Color("73828b"), 2, true)
	draw_line(p - Vector2(rock.radius * 0.5, 0), p + Vector2(rock.radius * 0.4, -rock.radius * 0.3), Color("1d2836"), 3, true)
	draw_circle(p + Vector2(rock.radius * 0.25, rock.radius * 0.2), rock.radius * 0.18, Color("24303c"))

func _draw_ship():
	var p = ship_pos
	var col = Color("b8c8d2")
	if invulnerable > 0.0:
		draw_arc(p, 44, 0, TAU, 36, Color(0.5, 0.9, 1, 0.6), 2, true)
		if G.settings.get("flash", true): col = col.lerp(Color("e9faff"), 0.3 + sin(invulnerable * 8) * 0.15)
	var thrust = 26 + abs(velocity.x) * 0.05 + sin(elapsed * 20) * 4
	draw_colored_polygon(PackedVector2Array([p + Vector2(-24, -6), p + Vector2(-24 - thrust, 0), p + Vector2(-24, 6)]), Color(0.3, 0.75, 1, 0.7))
	draw_colored_polygon(PackedVector2Array([p + Vector2(37, 0), p + Vector2(10, -11), p + Vector2(-6, -10), p + Vector2(-28, -24), p + Vector2(-21, -2), p + Vector2(-28, 6), p + Vector2(-7, 11), p + Vector2(-18, 24), p + Vector2(12, 10)]), col)
	draw_line(p + Vector2(-10, 5), p + Vector2(25, 1), Color("567080"), 2, true)
	draw_line(p + Vector2(4, -6), p + Vector2(20, -2), Color("58cfee"), 4, true)

func _hud():
	var text_size = 24 if G.settings.get("big_text", false) else 20
	draw_rect(Rect2(0, 0, 1280, 78), Color(0.02, 0.03, 0.055, 0.95))
	draw_rect(Rect2(0, 630, 1280, 90), Color(0.02, 0.03, 0.055, 0.95))
	Art.text(self, Vector2(30, 32), "CINDER WREN / " + str(config.region).to_upper(), text_size, Color("dce8ed"))
	Art.text(self, Vector2(30, 60), "HULL", 15, Color("91aebb"))
	for i in 3:
		var r = Rect2(88 + i * 28, 45, 22, 13)
		draw_rect(r, Color("8fddbf") if i < hull else Color("3c3540"))
		draw_rect(r, Color("adc6c9"), false, 1)
	var progress = elapsed / max(1.0, float(config.length_sec))
	draw_rect(Rect2(770, 26, 350, 6), Color("293b4c"))
	draw_rect(Rect2(770, 26, 350 * progress, 6), accent)
	Art.text(self, Vector2(770, 60), "EXIT VECTOR  %d%%" % int(progress * 100), 16, Color("b1c8d5"))
	Art.text(self, Vector2(1138, 35), "%02d:%02d" % [int(max(0.0, config.length_sec - elapsed)) / 60, int(max(0.0, config.length_sec - elapsed)) % 60], 22, Color("e2edef"))
	Art.text(self, Vector2(30, 659), "Steer: %s / %s / %s / %s    Pause: %s" % [G.key_hint("left"), G.key_hint("right"), G.key_hint("up"), G.key_hint("down"), G.key_hint("pause")], 16, Color("9fb4c3"))
	if callout_time > 0.0:
		Art.text(self, Vector2(30, 696), "SABLE  /  " + callout, text_size, Color("ffd29d"))
	elif assist:
		Art.text(self, Vector2(30, 696), "SABLE  /  Safe-path projection active", text_size, Color("9de0c8"))
