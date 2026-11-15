extends CanvasLayer
## Procedural cutscene illustrations. Dialogue remains above this layer.
const Art = preload("res://src/core/art.gd")
const NAMES = ["veyra_fall", "black_dawn", "cockpit", "fleet_battle", "dimming", "memorial", "senate", "heart", "mesh", "sever", "ascend", "dominion", "steward"]
const SIZE = Vector2(1280, 720)
var scene_name = ""
var elapsed = 0.0
var opacity = 0.0
var active = false
var surface = null

class Illustration extends Control:
	var vista = null
	func _draw():
		if is_instance_valid(vista): vista._paint(self)

func _ready():
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	surface = Illustration.new()
	surface.vista = self
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(surface)
	visible = active

func show_vista(vista_name):
	if not str(vista_name) in NAMES:
		push_warning("Unknown vista: " + str(vista_name))
		return
	scene_name = str(vista_name)
	elapsed = 0.0
	opacity = 0.0
	active = true
	visible = true

func hide_vista():
	active = false

func visible_now():
	return active or opacity > 0.0

func _process(dt):
	if not active and opacity <= 0.0:
		visible = false
		return
	elapsed += dt
	opacity = move_toward(opacity, 1.0 if active else 0.0, dt * 2.4)
	if surface:
		surface.modulate.a = opacity
		surface.queue_redraw()

func _hash(n):
	return fposmod(sin(float(n) * 127.1 + 311.7) * 43758.5453, 1.0)

func _paint(ci):
	var viewport_size = ci.get_viewport_rect().size
	var scale_xy = viewport_size / SIZE
	ci.draw_set_transform(Vector2.ZERO, 0, scale_xy)
	_sky(ci)
	# A restrained, continuous camera drift gives illustrations depth without shaking.
	var drift = Vector2(sin(elapsed * 0.11) * 8, cos(elapsed * 0.09) * 4)
	ci.draw_set_transform((Vector2(-12, -7) + drift) * scale_xy, 0, scale_xy * 1.02)
	match scene_name:
		"veyra_fall": _veyra(ci, true)
		"black_dawn": _veyra(ci, false)
		"cockpit": _cockpit(ci)
		"fleet_battle": _battle(ci)
		"dimming": _dimming(ci)
		"memorial": _memorial(ci)
		"senate": _senate(ci)
		"heart": _heart(ci)
		"mesh": _mesh(ci)
		"sever": _sever(ci)
		"ascend": _ascend(ci)
		"dominion": _dominion(ci)
		"steward": _steward(ci)
	ci.draw_set_transform(Vector2.ZERO, 0, scale_xy)
	ci.draw_rect(Rect2(0, 0, 1280, 64), Color(0.005, 0.007, 0.012))
	ci.draw_rect(Rect2(0, 656, 1280, 64), Color(0.005, 0.007, 0.012))
	ci.draw_line(Vector2(0, 64), Vector2(1280, 64), Color(0.55, 0.7, 0.8, 0.12))
	ci.draw_line(Vector2(0, 656), Vector2(1280, 656), Color(0.55, 0.7, 0.8, 0.12))

func _sky(ci):
	var top = Color("040714")
	var bottom = Color("14263a")
	if scene_name in ["heart", "dominion", "veyra_fall"]: bottom = Color("3c1d29")
	if scene_name in ["ascend", "steward", "mesh"]: bottom = Color("193c48")
	for i in 48:
		ci.draw_rect(Rect2(0, i * 15, 1280, 16), top.lerp(bottom, float(i) / 47))
	for i in 5:
		Art.glow(ci, Vector2(160 + i * 260, 180 + sin(i * 2.3) * 130), 260, Color(0.18, 0.25, 0.6, 0.075))
	for i in 260:
		var alpha = 0.3 + _hash(i + 900) * 0.65
		if scene_name == "dimming": alpha *= clamp(1.0 - max(0.0, elapsed - _hash(i + 530) * 22) * 0.7, 0.0, 1.0)
		var p = Vector2(_hash(i) * 1280, _hash(i + 400) * 720)
		ci.draw_circle(p, 0.65 + _hash(i + 200) * 1.15, Color(0.73, 0.85, 1.0, alpha))

func _planet(ci, center, radius, ocean, land, ruined = false):
	Art.glow(ci, center, radius * 1.16, Color(0.25, 0.7, 0.94, 0.28))
	ci.draw_circle(center, radius, ocean)
	# Continents and clouds stay inside the sphere's visible cross-section.
	for i in 32:
		var y = (-0.91 + i * 0.057) * radius
		var half_width = sqrt(max(0.0, radius * radius - y * y))
		var length = half_width * (0.25 + 0.47 * _hash(i + 80))
		var x = sin(i * 0.53) * half_width * 0.36
		ci.draw_line(center + Vector2(x - length, y), center + Vector2(x + length, y + 0.8), land, radius * 0.045, true)
	for i in 13:
		var y = (-0.82 + i * 0.13) * radius
		var half_width = sqrt(max(0.0, radius * radius - y * y)) * 0.87
		var x = sin(i * 1.7 + elapsed * 0.008) * half_width * 0.12
		ci.draw_line(center + Vector2(x - half_width, y), center + Vector2(x + half_width * 0.6, y + 5), Color(0.73, 0.93, 1, 0.18), radius * 0.025, true)
	# The terminator is a crescent built as a strip, without covering the lit rim.
	var shadow = PackedVector2Array()
	for i in 49:
		var a = -PI / 2 + i * PI / 48
		shadow.append(center + Vector2(cos(a), sin(a)) * radius)
	for i in 49:
		var a = PI / 2 - i * PI / 48
		shadow.append(center + Vector2(cos(a) * 0.24, sin(a)) * radius)
	ci.draw_colored_polygon(shadow, Color(0.005, 0.008, 0.02, 0.68))
	ci.draw_arc(center, radius, PI * 0.7, PI * 1.65, 80, Color(0.5, 0.9, 1, 0.65), 2, true)
	if ruined:
		for i in 15:
			var p = center + Vector2(sin(i * 2.2) * radius * 0.55, (-0.7 + i * 0.09) * radius)
			var reach = clamp((elapsed * 0.13 - _hash(i)) * radius * 0.9, 0, radius * 0.55)
			var q = p + Vector2(reach, -reach * 0.14)
			ci.draw_line(p, q, Color(1, 0.23, 0.06, 0.3), 10, true)
			ci.draw_line(p, q, Color(1, 0.65, 0.23), 2, true)
			Art.glow(ci, q, 22, Color(1, 0.22, 0.05, 0.3))

func _ship(ci, p, size, facing = 1.0, col = Color("94aec5")):
	var points = PackedVector2Array()
	for v in [Vector2(34, 0), Vector2(12, -10), Vector2(-8, -9), Vector2(-27, -24), Vector2(-20, -3), Vector2(-31, 5), Vector2(-8, 10), Vector2(-16, 24), Vector2(12, 10)]:
		points.append(p + Vector2(v.x * facing, v.y) * size)
	ci.draw_colored_polygon(points, col)
	ci.draw_line(p + Vector2(-22 * facing, 1) * size, p + Vector2(-43 * facing, 1) * size, Color(0.35, 0.85, 1, 0.75), 4 * size, true)
	ci.draw_line(p + Vector2(5 * facing, -5) * size, p + Vector2(18 * facing, -2) * size, Color(0.4, 0.95, 1), 3 * size, true)
	ci.draw_line(p + Vector2(-12 * facing, 6) * size, p + Vector2(20 * facing, 2) * size, col.darkened(0.45), 2 * size, true)

func _station(ci, center, radius, broken = false):
	ci.draw_arc(center, radius, 0.12, TAU - 0.12, 100, Color("202b3c"), 26, true)
	ci.draw_arc(center, radius, 0.12, TAU - 0.12, 100, Color("7593ab"), 2, true)
	for i in 18:
		var a = float(i) * TAU / 18
		var offset = Vector2.ZERO
		if broken and i % 3 == 0: offset = Vector2.from_angle(a) * (18 + elapsed * 1.7)
		var p = center + Vector2.from_angle(a) * radius + offset
		ci.draw_line(center + offset, p, Color("28374b"), 6, true)
		ci.draw_circle(p, 8, Color("52657b"))
		ci.draw_circle(p, 2.5, Color("ff9965") if broken else Color("80e4fa"))
	ci.draw_rect(Rect2(center - Vector2(16, 58), Vector2(32, 116)), Color("52657b"))
	ci.draw_line(center - Vector2(0, 92), center + Vector2(0, 92), Color("879eae"), 5, true)

func _veyra(ci, falling):
	_planet(ci, Vector2(830, 530), 330, Color("164354"), Color("397f70"), falling)
	_station(ci, Vector2(400, 240), 132, falling)
	if falling:
		for i in 35:
			var a = _hash(i + 40) * TAU
			var p = Vector2(400, 240) + Vector2.from_angle(a) * (145 + _hash(i) * 95 + fmod(elapsed, 40) * (0.5 + _hash(i + 70)))
			ci.draw_line(p, p + Vector2(12, 8), Color(1, 0.5, 0.2, 0.65), 2, true)
		Art.glow(ci, Vector2(485, 285), 82, Color(1, 0.35, 0.08, 0.4))
	else:
		for i in 9:
			var p = Vector2(90 + i * 95 + sin(elapsed * 0.1) * 12, 460 + sin(i * 2) * 70)
			_ship(ci, p, 0.6 + float(i) * 0.1, 1, Color("3f4659"))
		_ship(ci, Vector2(150, 205), 2.7, 1, Color("141b2b"))

func _cockpit(ci):
	_planet(ci, Vector2(1060, 440), 210, Color("253652"), Color("525f70"))
	# Window pillars and the winged dashboard frame the moving stars.
	for side in [-1, 1]:
		ci.draw_line(Vector2(640 + side * 390, 60), Vector2(640 + side * 540, 570), Color("111925"), 50, true)
		ci.draw_line(Vector2(640 + side * 386, 60), Vector2(640 + side * 536, 570), Color("4c5d6d"), 3, true)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(0, 520), Vector2(330, 560), Vector2(470, 510), Vector2(810, 510), Vector2(950, 560), Vector2(1280, 520), Vector2(1280, 720), Vector2(0, 720)]), Color("101a27"))
	for i in 3:
		var r = Rect2(420 + i * 150, 554, 130, 62)
		ci.draw_rect(r, Color("062a36"))
		ci.draw_rect(r, Color("537888"), false, 2)
		for j in 8:
			ci.draw_line(r.position + Vector2(10, 8 + j * 6), r.position + Vector2(15 + _hash(i * 30 + j) * 100, 8 + j * 6), Color(0.3, 0.9, 1, 0.55), 1)
	Art.glow(ci, Vector2(900, 500), 90, Color(1, 0.55, 0.2, 0.13))
	Art.portrait(ci, "sable", Rect2(930, 468, 92, 92), "soft", elapsed, false)
	ci.draw_arc(Vector2(640, 300), 53, 0, TAU, 40, Color(0.4, 0.8, 0.8, 0.16), 1)
	ci.draw_line(Vector2(622, 300), Vector2(658, 300), Color(0.4, 0.8, 0.8, 0.24))

func _battle(ci):
	_planet(ci, Vector2(1080, 630), 390, Color("172b41"), Color("3a5265"))
	for i in 16:
		var p = Vector2(70 + _hash(i) * 1120, 130 + _hash(i + 50) * 450)
		var side = 1 if i % 2 == 0 else -1
		p.x += sin(elapsed * 0.1 + i) * 30
		_ship(ci, p, 0.5 + _hash(i + 30) * 1.7, side, Color("68859e") if side == 1 else Color("594352"))
		var shot = fposmod(elapsed * 0.22 + _hash(i + 8), 1.0)
		var q = p + Vector2(side * shot * 400, -shot * 70)
		ci.draw_line(q, q + Vector2(side * 35, -5), Color(0.6, 0.85, 1, 0.65) if side == 1 else Color(1, 0.43, 0.26, 0.65), 2, true)
	if G.settings.get("flash", true):
		for i in 4:
			var pulse = pow(max(0.0, sin(elapsed * 0.7 + i * 2.3)), 5)
			Art.glow(ci, Vector2(220 + i * 260, 240 + sin(i) * 80), 65, Color(1, 0.5, 0.2, pulse * 0.3))

func _dimming(ci):
	# These last bright stars extinguish in sequence, leaving only the vessel.
	for i in 12:
		var a = clamp(1.0 - max(0.0, elapsed - 5 - i * 1.6), 0, 1)
		var p = Vector2(100 + _hash(i + 81) * 1070, 130 + _hash(i + 63) * 330)
		Art.glow(ci, p, 25, Color(0.7, 0.82, 1, a * 0.5))
		ci.draw_circle(p, 2, Color(0.95, 0.97, 1, a))
	_ship(ci, Vector2(680, 510), 1.5, 1, Color("303b50"))

func _memorial(ci):
	var rock = PackedVector2Array([Vector2(70, 720), Vector2(100, 150), Vector2(255, 90), Vector2(460, 125), Vector2(690, 80), Vector2(940, 110), Vector2(1130, 180), Vector2(1210, 720)])
	ci.draw_colored_polygon(rock, Color("1d2832"))
	for i in 20:
		var x = 120 + _hash(i + 3) * 1040
		ci.draw_line(Vector2(x, 165), Vector2(x + sin(i * 2.1) * 50, 635), Color(0.4, 0.5, 0.6, 0.1), 1)
	for row in 36:
		for col in 72:
			var idx = row * 72 + col
			var p = Vector2(145 + col * 13.8, 190 + row * 10.5)
			ci.draw_circle(p, 1 + _hash(idx) * 0.9, Color(1, 0.76 + _hash(idx + 9) * 0.2, 0.4, 0.3 + _hash(idx + 4) * 0.7))
	ci.draw_rect(Rect2(0, 610, 1280, 110), Color("0b121c"))
	_person(ci, Vector2(610, 634), 1.25, Color("101926"))
	_person(ci, Vector2(670, 634), 1.05, Color("253949"))
	Art.glow(ci, Vector2(640, 584), 28, Color(1, 0.7, 0.3, 0.25))

func _person(ci, p, scale_person, col):
	ci.draw_circle(p + Vector2(0, -44) * scale_person, 6 * scale_person, col)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, -36) * scale_person, p + Vector2(8, -36) * scale_person, p + Vector2(13, 0) * scale_person, p + Vector2(-13, 0) * scale_person]), col)

func _senate(ci):
	Art.glow(ci, Vector2(640, 230), 280, Color(0.72, 0.7, 0.38, 0.18))
	for i in 9:
		var x = 80 + i * 140
		ci.draw_rect(Rect2(x, 90, 22, 430), Color("29313c"))
		ci.draw_line(Vector2(x + 22, 90), Vector2(x + 22, 500), Color("65707c"), 2)
	for tier in range(4, -1, -1):
		var width = 250 + tier * 100
		var y = 430 + tier * 47
		ci.draw_arc(Vector2(640, y - 110), width, 0.12, PI - 0.12, 80, Color("3b3840"), 30, true)
		ci.draw_arc(Vector2(640, y - 110), width, 0.12, PI - 0.12, 80, Color("c0a36c"), 2, true)
		for i in 16:
			var a = 0.2 + i * (PI - 0.4) / 15
			_person(ci, Vector2(640, y - 110) + Vector2.from_angle(a) * width, 0.55 + tier * 0.08, Color("111924"))
	ci.draw_circle(Vector2(640, 250), 90, Color("273b48"))
	ci.draw_arc(Vector2(640, 250), 92, 0, TAU, 64, Color("ccaf72"), 4, true)
	for i in 7: ci.draw_line(Vector2(640, 175), Vector2(580 + i * 20, 300), Color(0.85, 0.75, 0.5, 0.3), 1)

func _heart(ci):
	var c = Vector2(720, 342)
	Art.glow(ci, c, 310, Color(1, 0.36, 0.13, 0.5))
	ci.draw_circle(c, 160, Color("f08c43"))
	for i in 10:
		ci.draw_arc(c, 151 - i * 11, elapsed * 0.015 + i, elapsed * 0.015 + i + PI * 1.3, 60, Color(0.5, 0.14, 0.1, 0.18), 9, true)
	for i in 4:
		var r = 205 + i * 55
		var a = elapsed * 0.008 * (1 if i % 2 == 0 else -1) + i * 0.75
		ci.draw_arc(c, r, a, a + PI * 1.7, 100, Color("27303e"), 18 - i * 3, true)
		ci.draw_arc(c, r + 7, a, a + PI * 1.7, 100, Color(0.65, 0.6, 0.8, 0.6), 1, true)
		for j in 12:
			var p = c + Vector2.from_angle(a + j * PI / 6) * r
			ci.draw_circle(p, 3, Color("c4a2ff"))
	_ship(ci, Vector2(300, 560), 1.2, 1, Color("192b3a"))

func _mesh(ci):
	var nodes = []
	for i in 13:
		var a = i * 2.4
		var p = Vector2(650, 340) + Vector2(cos(a) * (90 + i * 24), sin(a) * (60 + i * 13))
		nodes.append(p)
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if nodes[i].distance_to(nodes[j]) < 350:
				ci.draw_line(nodes[i], nodes[j], Color(0.35, 0.9, 0.9, 0.25), 1, true)
		_planet(ci, nodes[i], 10 + _hash(i + 8) * 13, Color("225466"), Color("588b80"))
	Art.glow(ci, Vector2(650, 340), 160, Color(0.4, 0.95, 1, 0.25))
	_person(ci, Vector2(640, 415), 1.65, Color("b6dfd9"))
	ci.draw_arc(Vector2(640, 350), 67, 0, TAU, 60, Color("7bdfcf"), 1, true)

func _sever(ci):
	var c = Vector2(750, 310)
	Art.glow(ci, c, 220, Color(1, 0.5, 0.2, 0.22))
	ci.draw_circle(c, 92, Color("c88657"))
	for i in 9:
		var a = i * TAU / 9
		var drift = Vector2.from_angle(a) * (12 + min(elapsed, 80) * 0.8)
		ci.draw_arc(c + drift, 165, a, a + 0.48, 20, Color("626675"), 12, true)
	for i in 40:
		var p = c + Vector2.from_angle(_hash(i) * TAU) * (190 + _hash(i + 50) * 180)
		ci.draw_circle(p, 1 + _hash(i + 70) * 3, Color("9293a4"))
	_ship(ci, Vector2(310 - min(elapsed, 80) * 0.5, 475), 2, -1, Color("a0b2bb"))

func _ascend(ci):
	var c = Vector2(640, 348)
	Art.glow(ci, c, 340, Color(0.65, 0.8, 1, 0.4))
	for i in 12:
		var r = 55 + i * 24
		ci.draw_arc(c, r, elapsed * 0.008 + i * 0.5, elapsed * 0.008 + i * 0.5 + PI * 1.6, 96, Color(0.73, 0.72, 1, 0.35 - i * 0.018), 1, true)
	for i in 100:
		var p = Vector2(350 + _hash(i) * 580, 90 + fposmod(_hash(i + 10) * 520 - elapsed * (4 + _hash(i + 30) * 7), 520))
		ci.draw_rect(Rect2(p, Vector2(2, 5 + _hash(i + 20) * 9)), Color(0.8, 0.9, 1, 0.4))
	_person(ci, Vector2(640, 425), 2.5, Color("d4e9f4"))
	Art.glow(ci, Vector2(640, 320), 70, Color(0.9, 0.97, 1, 0.5))

func _dominion(ci):
	_planet(ci, Vector2(640, 710), 360, Color("1b2536"), Color("4c4851"))
	for i in 11:
		var p = Vector2(95 + i * 110, 190 + abs(i - 5) * 25)
		_ship(ci, p, 0.8 + (1 - abs(i - 5) / 6.0), 1, Color("78828d"))
	for side in [-1, 1]:
		var x = 640 + side * 470
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 48, 80), Vector2(x + 48, 80), Vector2(x + 48, 440), Vector2(x, 486), Vector2(x - 48, 440)]), Color("541e2b"))
		ci.draw_line(Vector2(x, 130), Vector2(x, 380), Color("c9a16d"), 4)
		ci.draw_arc(Vector2(x, 220), 27, 0, TAU, 32, Color("c9a16d"), 3, true)
	ci.draw_rect(Rect2(440, 580, 400, 100), Color("131a26"))
	_person(ci, Vector2(640, 580), 2, Color("a1a9b3"))

func _steward(ci):
	_planet(ci, Vector2(900, 270), 155, Color("23556b"), Color("5a9880"))
	Art.glow(ci, Vector2(250, 200), 180, Color(1, 0.78, 0.4, 0.3))
	ci.draw_circle(Vector2(250, 200), 46, Color("e8c98e"))
	for tier in 4:
		var y = 470 + tier * 48
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, y + 30), Vector2(300, y - 45), Vector2(620, y + 20), Vector2(920, y - 5), Vector2(1280, y - 70), Vector2(1280, 720), Vector2(0, 720)]), Color("264c49").darkened(tier * 0.15))
	for i in 18:
		var x = 80 + i * 67
		var y = 555 + sin(i * 0.8) * 35
		ci.draw_line(Vector2(x, y), Vector2(x, y - 42), Color("52645d"), 3)
		ci.draw_circle(Vector2(x - 5, y - 48), 17, Color("406b5e"))
		ci.draw_circle(Vector2(x + 8, y - 40), 14, Color("507a64"))
	_person(ci, Vector2(600, 624), 1.5, Color("b3bbb3"))
	Art.glow(ci, Vector2(660, 550), 38, Color(1, 0.65, 0.3, 0.4))
	ci.draw_circle(Vector2(660, 550), 6, Color("ffd99e"))
