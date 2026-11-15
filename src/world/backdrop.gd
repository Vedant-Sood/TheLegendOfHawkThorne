extends CanvasLayer
# Geometry is cached by CanvasItem. Camera movement only translates the four layers;
# weather and the few animated landmarks are the only geometry redrawn each frame.

const Art = preload("res://src/core/art.gd")
const VIEW = Vector2(1280, 720)
const PERIOD = 2560.0
const FACTORS = [0.08, 0.2, 0.4, 0.65]

var region_id = "kharon"
var room_data = {}
var sky = null
var fog = null
var scenery = null
var depths = []
var foreground = null
var weather = null
var moving = null
var camera_center = VIEW * 0.5
var elapsed = 0.0

func _ready():
	layer = -10
	_build()
	setup(region_id, room_data)
	get_viewport().size_changed.connect(_resize)

func _build():
	if sky != null: return
	sky = _shader_rect(preload("res://shaders/sky.gdshader"))
	sky.name = "Sky"
	add_child(sky)
	scenery = Node2D.new()
	scenery.name = "Parallax"
	add_child(scenery)
	for depth in 4:
		var part = Scenery.new()
		part.name = "Depth%d" % depth
		part.depth = depth
		scenery.add_child(part)
		depths.append(part)
	moving = Moving.new()
	moving.name = "DistantMotion"
	scenery.add_child(moving)
	foreground = CanvasLayer.new()
	foreground.name = "WeatherAndFog"
	foreground.layer = 2
	add_child(foreground)
	fog = _shader_rect(preload("res://shaders/fog.gdshader"))
	fog.name = "Fog"
	foreground.add_child(fog)
	weather = Weather.new()
	weather.name = "Weather"
	foreground.add_child(weather)
	_resize()

func _shader_rect(shader):
	var rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material = ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	return rect

func setup(id, room):
	region_id = str(id)
	room_data = room if room is Dictionary else {}
	if not is_inside_tree(): return
	_build()
	var region = DB.regions.get(region_id, DB.regions.kharon)
	var material = sky.material
	material.set_shader_parameter("top_color", DB.C(region.top))
	material.set_shader_parameter("bottom_color", DB.C(region.bot))
	material.set_shader_parameter("sun_color", DB.C(region.sunc))
	material.set_shader_parameter("sun", Vector3(region.sun[0], region.sun[1], region.sun[2]))
	material.set_shader_parameter("stars", float(region.stars))
	material.set_shader_parameter("nebula", float(region.neb))
	material.set_shader_parameter("planet", region_id == "orbit")
	fog.material.set_shader_parameter("fog_color", DB.C(region.fog))
	fog.material.set_shader_parameter("density", float(region.foga))
	for part in depths:
		part.region_id = region_id
		part.region = region
		part.queue_redraw()
	moving.region_id = region_id
	moving.region = region
	weather.kind = str(region.weather)
	weather.tint = DB.C(region.acc2)
	update_view(camera_center, elapsed)

func update_view(cam_center: Vector2, t: float):
	camera_center = cam_center
	elapsed = t
	if sky == null: return
	var shift = camera_center - VIEW * 0.5
	for i in depths.size():
		depths[i].position = Vector2(-fposmod(shift.x * FACTORS[i], PERIOD), -clamp(shift.y * FACTORS[i] * 0.22, -100.0, 100.0))
	sky.material.set_shader_parameter("clock", t)
	sky.material.set_shader_parameter("camera_offset", shift * 0.000008)
	sky.material.set_shader_parameter("reduced_flashes", not G.settings.get("flash", true))
	sky.material.set_shader_parameter("high_contrast", G.settings.get("contrast", false))
	fog.material.set_shader_parameter("clock", t)
	fog.material.set_shader_parameter("camera_offset", shift * 0.00012)
	fog.material.set_shader_parameter("high_contrast", G.settings.get("contrast", false))
	weather.t = t
	weather.camera = shift
	weather.queue_redraw()
	moving.t = t
	moving.camera = shift
	moving.queue_redraw()
	foreground.visible = visible

func _resize():
	if sky == null: return
	var size = get_viewport().get_visible_rect().size
	sky.size = size
	fog.size = size
	sky.material.set_shader_parameter("aspect", size.x / max(1.0, size.y))
	scenery.scale = size / VIEW
	weather.scale = size / VIEW

class Scenery extends Node2D:
	const Art = preload("res://src/core/art.gd")
	var region_id = "kharon"
	var region = {}
	var depth = 0

	func h(n): return fposmod(sin(n * 127.1 + depth * 311.7) * 43758.5453, 1.0)

	func _draw():
		if region.is_empty(): return
		# Three identical 2560px tiles cover wraparound at both viewport edges.
		for tile in [-1, 0, 1]:
			draw_set_transform(Vector2(tile * 2560, 0))
			_tile()
		draw_set_transform(Vector2.ZERO)

	func _tile():
		var base = DB.C(region.tile).lerp(DB.C(region.bot), 0.48 - depth * 0.11)
		var rim = DB.C(region.hi).darkened(0.38)
		var accent = DB.C(region.acc)
		var light = DB.C(region.acc2)
		var ground = 475.0 + depth * 68.0
		match region_id:
			"kharon":
				for i in 16:
					var x = i * 160.0 + h(i) * 35
					var width = 62 + h(i + 8) * 80
					var height = 90 + h(i + 30) * (280 - depth * 30)
					var roof = ground - height
					draw_rect(Rect2(x, roof, width, 900 - roof), base)
					draw_rect(Rect2(x + width - 5, roof + 12, 3, height), rim)
					draw_line(Vector2(x + 15, roof), Vector2(x + 15, roof - 26), rim, 2)
					for row in int(height / 24):
						for col in int(width / 16):
							if h(i * 70 + row * 13 + col) > 0.55:
								draw_rect(Rect2(x + 8 + col * 16, roof + 14 + row * 24, 5, 7), Color(light, 0.23 + depth * 0.08))
					if i % 3 == 0:
						draw_rect(Rect2(x + 12, roof + 35, 24, 70), Color(accent, 0.35))
						for line in 5:
							draw_line(Vector2(x + 16, roof + 44 + line * 12), Vector2(x + 29, roof + 44 + line * 12), accent, 2)
					if i % 2 == 0:
						draw_rect(Rect2(x + width, ground - 95, 100, 10), base)
						draw_line(Vector2(x + width, ground - 95), Vector2(x + width + 90, ground - 125), rim, 2)
			"colony":
				_ridge(base, ground - 70, 120, 90)
				for i in 8:
					var x = i * 320 + 90
					var radius = 60 + h(i) * 60
					var y = ground + 20 + h(i + 1) * 30
					Art.ell(self, Vector2(x, y), radius, radius * 0.65, base, 32, PI, TAU)
					draw_arc(Vector2(x, y), radius, PI, TAU, 32, Color(light, 0.35), 2)
					draw_line(Vector2(x, y - radius * 0.6), Vector2(x, y), rim, 2)
					draw_rect(Rect2(x - radius, y, radius * 2, 180), base)
					draw_line(Vector2(x + radius + 22, y + 50), Vector2(x + radius + 22, y - 110), rim, 3)
					draw_line(Vector2(x + radius + 5, y - 85), Vector2(x + radius + 40, y - 85), rim, 2)
					draw_circle(Vector2(x + radius + 22, y - 111), 2, accent)
			"glass":
				_ridge(base, ground, 30, 210)
				for i in 14:
					var x = i * 183 + h(i + 1) * 40
					var height = 50 + h(i) * 170
					var y = ground + 20
					var polygon = PackedVector2Array([Vector2(x - 20, y), Vector2(x - 12, y - height + 25), Vector2(x + 3, y - height), Vector2(x + 26, y - 25), Vector2(x + 12, y + 12)])
					draw_colored_polygon(polygon, base.lightened(0.07))
					draw_line(Vector2(x + 3, y - height), Vector2(x + 5, y), Color(light, 0.45), 2)
					draw_line(Vector2(x + 3, y - height), Vector2(x + 26, y - 25), Color(accent, 0.3), 1)
				if depth == 1:
					for i in 7:
						draw_arc(Vector2(600 + i * 33, ground + 50), 110 - i * 7, PI * 1.1, PI * 1.9, 20, rim, 5)
					Art.ell(self, Vector2(1800, ground + 20), 125, 90, base, 32, PI, TAU)
					draw_line(Vector2(1800, ground - 65), Vector2(1825, ground - 145), rim, 12)
			"drowned":
				for i in 9:
					var x = i * 290 + 30
					var y = ground - 130 - h(i) * 100
					draw_rect(Rect2(x, y, 210, 450), base)
					draw_rect(Rect2(x + 10, y + 20, 190, 45), Color(light, 0.06))
					for window in 6:
						draw_rect(Rect2(x + 15 + window * 30, y + 28, 15, 24), Color(light, 0.15))
					draw_line(Vector2(x + 30, y + 100), Vector2(x + 260, y + 100), rim, 8)
					if depth == 0:
						draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 25, 0), Vector2(x + 210, 720), Vector2(x + 70, 720)]), Color(light, 0.035))
					for stem in 5:
						var points = PackedVector2Array()
						for n in 10:
							points.append(Vector2(x + stem * 37 + sin(n * 0.8 + stem) * 13, ground + 190 - n * (10 + h(stem) * 8)))
						draw_polyline(points, base.lightened(0.09), 3)
			"cathedral":
				for i in 9:
					var x = i * 290 + 145
					var y = ground - 190
					draw_arc(Vector2(x, y), 110, PI, TAU, 48, base, 20)
					draw_arc(Vector2(x, y), 98, PI, TAU, 48, rim, 2)
					for side in [-1, 1]:
						draw_rect(Rect2(x + side * 110 - 10, y, 20, 650), base)
						draw_line(Vector2(x + side * 110, y), Vector2(x + side * 110, 720), rim, 2)
					var center = Vector2(x, y + 10)
					draw_colored_polygon(PackedVector2Array([center + Vector2(0, -82), center + Vector2(54, 0), center + Vector2(0, 100), center + Vector2(-54, 0)]), Color(light, 0.12))
					for k in 5:
						draw_line(center + Vector2(-40, k * 28 - 55), center + Vector2(40, 55 - k * 28), Color(accent, 0.2), 2)
					draw_line(Vector2(x + 50, 0), Vector2(x + 50, y - 40), rim, 2)
					draw_rect(Rect2(x + 34, y - 50, 32, 23), base)
			"orbit":
				for i in 8:
					var x = i * 320 + 70
					var y = 250 + h(i) * 350
					var length = 65 + h(i + 4) * 140
					draw_colored_polygon(PackedVector2Array([Vector2(x - length, y), Vector2(x - 40, y - 18), Vector2(x + length, y - 6), Vector2(x + length * 0.7, y + 17), Vector2(x - 60, y + 25)]), base)
					draw_line(Vector2(x - 30, y), Vector2(x + length * 0.8, y), rim, 2)
					for strut in 3:
						draw_line(Vector2(x + strut * 30, y), Vector2(x + strut * 30 + 10, y + 48), base, 5)
					draw_circle(Vector2(x + length * 0.8, y), 2, Color(accent, 0.6))
			"city":
				for i in 13:
					var x = i * 200 + 30
					var height = 150 + h(i) * 260
					draw_colored_polygon(PackedVector2Array([Vector2(x - 25, ground + 150), Vector2(x - 40, ground - height), Vector2(x + 10, ground - height - 35), Vector2(x + 75, ground - height + 10), Vector2(x + 65, ground + 150)]), base)
					draw_line(Vector2(x + 10, ground - height - 35), Vector2(x + 10, ground + 140), rim, 2)
					for k in 3:
						var y = ground - height + 60 + k * 45
						draw_polyline(PackedVector2Array([Vector2(x - 17, y), Vector2(x + 5, y), Vector2(x + 5, y + 20), Vector2(x + 45, y + 20)]), Color(accent, 0.35), 2)
					if depth == 0:
						draw_colored_polygon(PackedVector2Array([Vector2(x - 65, 0), Vector2(x + 100, 0), Vector2(x + 10, 100 + h(i) * 180)]), base)
			"ashen":
				for i in 17:
					var x = i * 150.0
					var y = ground - 70 - h(i) * 220
					draw_colored_polygon(PackedVector2Array([Vector2(x, 900), Vector2(x, y + 20), Vector2(x + 20, y), Vector2(x + 33, y + 30), Vector2(x + 65, y + 4), Vector2(x + 90, y + 40), Vector2(x + 95, 900)]), base)
					for fire in 3:
						draw_line(Vector2(x + 15 + fire * 23, y + 70), Vector2(x + 15 + fire * 23, y + 85 + h(i + fire) * 30), Color(accent, 0.5), 4)
				if depth == 1:
					draw_line(Vector2(900, 800), Vector2(800, 40), base, 38)
					draw_line(Vector2(800, 40), Vector2(730, -80), rim, 20)
					draw_line(Vector2(828, 205), Vector2(1020, 305), base, 25)
					for strand in 5:
						draw_line(Vector2(798 + strand * 4, 80), Vector2(850 + strand * 12, 230), rim, 1)
			"heart":
				var center = Vector2(1280, 380)
				var radius = 270 + depth * 95
				for arc in 5:
					var angle = arc * TAU / 5.0
					draw_arc(center, radius, angle, angle + 0.85, 40, base, 19 + depth * 5)
					draw_arc(center, radius - 12, angle, angle + 0.85, 40, Color(light, 0.28), 2)
					var pos = center + Vector2.from_angle(angle) * radius
					draw_line(pos, center + Vector2.from_angle(angle) * (radius + 100), rim, 4)
				for i in 12:
					var x = i * 220 + h(i) * 40
					var y = 150 + h(i + 1) * 440
					draw_rect(Rect2(x, y, 15 + h(i + 2) * 40, 8), base)
					draw_line(Vector2(x, y), Vector2(x + 30, y), Color(accent, 0.45), 1)
			"mind":
				for i in 12:
					var x = i * 215 + 30
					var y = 150 + h(i) * 320
					var width = 65 + h(i + 2) * 60
					draw_rect(Rect2(x, y - 95, width, 95), Color(base, 0.45 + depth * 0.1))
					draw_colored_polygon(PackedVector2Array([Vector2(x - 12, y), Vector2(x + width + 12, y), Vector2(x + width * 0.5, y + 55)]), base)
					for window in 3:
						draw_rect(Rect2(x + 10 + window * (width - 15) / 3.0, y - 58, 10, 18), Color(light, 0.25))
					draw_line(Vector2(x + width * 0.5, y - 95), Vector2(x + width * 0.5, y - 145), Color(base, 0.3), 1)
			"ship":
				if depth < 2: return
				var y = 80 + (depth - 2) * 40
				draw_rect(Rect2(0, 0, 2560, y), base)
				draw_rect(Rect2(0, 590 + depth * 20, 2560, 180), base)
				for i in 8:
					var x = i * 320
					draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 40, 0), Vector2(x + 80, 720), Vector2(x + 45, 720)]), base)
					draw_line(Vector2(x + 40, y), Vector2(x + 74, 620), rim, 2)
					draw_rect(Rect2(x + 95, 642, 170, 5), Color(light, 0.6))
					draw_rect(Rect2(x + 105, 65 + y / 2, 140, 3), Color(accent, 0.5))

	func _ridge(col, y, amplitude, wavelength):
		var points = PackedVector2Array([Vector2(0, 1000)])
		for i in 65:
			var x = i * 40.0
			# Integer waves make the 2560px tile continuous.
			var height = sin(x / 2560.0 * TAU * (3 + depth) + depth) * amplitude
			height += sin(x / 2560.0 * TAU * 11) * amplitude * 0.2 * min(1.0, 120.0 / wavelength)
			points.append(Vector2(x, y + height))
		points.append(Vector2(2560, 1000))
		draw_colored_polygon(points, col)

class Moving extends Node2D:
	const Art = preload("res://src/core/art.gd")
	var region_id = "kharon"
	var region = {}
	var t = 0.0
	var camera = Vector2.ZERO

	func _draw():
		if region.is_empty(): return
		var accent = DB.C(region.acc2)
		var hull = DB.C(region.tile).lightened(0.08)
		match region_id:
			"kharon":
				for i in 5:
					var pos = Vector2(fposmod(i * 317 + t * (9 + i * 3) - camera.x * 0.12, 1450) - 85, 135 + i * 48)
					draw_colored_polygon(PackedVector2Array([pos + Vector2(-24, 0), pos + Vector2(-16, -6), pos + Vector2(18, -4), pos + Vector2(27, 1), pos + Vector2(-18, 4)]), hull)
					draw_line(pos + Vector2(-24, 0), pos + Vector2(-37, 0), Color(accent, 0.6), 2)
			"orbit":
				for i in 4:
					var pos = Vector2(fposmod(i * 360 - camera.x * 0.17, 1480) - 100, 180 + i * 115)
					draw_set_transform(pos, t * 0.025 * (1 if i % 2 == 0 else -1) + i)
					draw_rect(Rect2(-28, -6, 72, 12), hull)
					draw_rect(Rect2(-16, -32, 10, 65), hull)
					draw_rect(Rect2(6, -25, 21, 12), Color(accent, 0.18))
					draw_line(Vector2(-24, -4), Vector2(36, -4), Color(accent, 0.4), 1)
				draw_set_transform(Vector2.ZERO)
			"ashen":
				if G.settings.get("flash", true) and not G.settings.get("contrast", false):
					for i in 3:
						var phase = fposmod(t * 0.24 + i * 0.37, 1.0)
						var brightness = max(0.0, 1.0 - abs(phase - 0.4) / 0.055)
						Art.glow(self, Vector2(220 + i * 440, 430 - i * 40), 90, Color(1.0, 0.3, 0.04, brightness * 0.18))
			"ship":
				for i in 40:
					var x = fposmod(i * 193.3 - t * (20 + i % 5 * 12), 1320)
					var y = 150 + fposmod(i * 117.3, 430)
					draw_line(Vector2(x, y), Vector2(x + 5 + i % 5 * 3, y), Color(accent, 0.3), 1)

class Weather extends Node2D:
	var kind = "none"
	var tint = Color.WHITE
	var t = 0.0
	var camera = Vector2.ZERO

	func h(n): return fposmod(sin(n * 127.1 + 311.7) * 43758.5453, 1.0)

	func _draw():
		if kind == "none": return
		var contrast = G.settings.get("contrast", false)
		var count = 45 if contrast else 100
		var opacity = 0.14 if contrast else 0.3
		for i in count:
			var seed_x = h(i + 1)
			var seed_y = h(i + 100)
			var speed = 0.6 + h(i + 300)
			var x = seed_x * 1400
			var y = seed_y * 860
			match kind:
				"rain":
					x -= t * 90 * speed
					y += t * 600 * speed
				"bubbles":
					x += sin(t * 0.7 + i) * 18
					y -= t * 42 * speed
				"sand", "dust":
					x -= t * (130 if kind == "sand" else 25) * speed
					y += t * 8 * speed + sin(t + i) * 15
				"ash":
					x -= t * 30 * speed + sin(t * 0.7 + i) * 20
					y += t * 24 * speed
				"debris":
					x -= t * 12 * speed
					y += t * 7 * speed
				_:
					x += sin(t * 0.25 + i) * 25
					y -= t * 10 * speed
			x = fposmod(x - camera.x * 0.14, 1400) - 60
			y = fposmod(y - camera.y * 0.08, 860) - 70
			var pos = Vector2(x, y)
			var col = Color(tint, opacity * (0.5 + seed_y * 0.5))
			match kind:
				"rain": draw_line(pos, pos + Vector2(-4, 21) * speed, col, 1)
				"bubbles": draw_arc(pos, 1.5 + seed_x * 3, 0, TAU, 10, col, 1)
				"memory":
					var radius = 2 + seed_x * 5
					draw_set_transform(pos, sin(t * 0.15 + i) * 0.3)
					draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2.6), col, false, 1)
					draw_line(Vector2(-radius, 0), Vector2(radius, 0), col, 1)
					draw_set_transform(Vector2.ZERO)
				"debris":
					draw_set_transform(pos, t * 0.1 + i)
					draw_rect(Rect2(-2, -1, 5 + seed_x * 6, 3), col)
					draw_set_transform(Vector2.ZERO)
				"sand": draw_line(pos, pos + Vector2(-7, 1), col, 1)
				_: draw_circle(pos, 0.7 + seed_x * 1.5, col)
