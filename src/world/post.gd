extends CanvasLayer
# Kept below HUD, dialogue and menus. screen_pos uses viewport (not world) pixels.

var screen = null
var effect = null
var region_id = "kharon"
var hit_amount = 0.0
var darkness = 0.0
var light_position = Vector2(640, 360)
var desaturation = 0.0
var elapsed = 0.0

func _ready():
	layer = 5
	_build()
	setup(region_id)
	get_viewport().size_changed.connect(_resize)

func _build():
	if screen != null: return
	screen = ColorRect.new()
	screen.name = "PostProcess"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect = ShaderMaterial.new()
	effect.shader = preload("res://shaders/post.gdshader")
	screen.material = effect
	add_child(screen)
	_resize()

func setup(id):
	region_id = str(id)
	if not is_inside_tree(): return
	_build()
	var region = DB.regions.get(region_id, DB.regions.kharon)
	effect.set_shader_parameter("grade", DB.C(region.get("grade", "ffffff")))
	effect.set_shader_parameter("underwater", bool(region.get("water", false)))
	hit_amount = 0.0
	_sync()

func pulse(amount):
	if not G.settings.get("flash", true): return
	hit_amount = max(hit_amount, clamp(float(amount), 0.0, 1.0))
	_sync()

func set_dark(amount, screen_pos):
	darkness = clamp(float(amount), 0.0, 1.0)
	light_position = screen_pos
	_sync()

func set_desat(amount):
	desaturation = clamp(float(amount), 0.0, 1.0)
	_sync()

func _resize():
	if screen != null:
		screen.size = get_viewport().get_visible_rect().size
		_sync()

func _process(delta):
	elapsed += delta
	hit_amount = move_toward(hit_amount, 0.0, delta * 2.5)
	_sync()

func _sync():
	if effect == null: return
	var dimensions = get_viewport().get_visible_rect().size
	effect.set_shader_parameter("clock", elapsed)
	effect.set_shader_parameter("hit", hit_amount if G.settings.get("flash", true) else 0.0)
	effect.set_shader_parameter("darkness", darkness)
	effect.set_shader_parameter("desaturation", desaturation)
	effect.set_shader_parameter("light_position", light_position / Vector2(max(1.0, dimensions.x), max(1.0, dimensions.y)))
	effect.set_shader_parameter("reduced_flashes", not G.settings.get("flash", true))
	effect.set_shader_parameter("high_contrast", G.settings.get("contrast", false))
