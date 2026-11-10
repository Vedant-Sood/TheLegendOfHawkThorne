extends CanvasLayer
# HUD — vitals, energy, stims, sidearm mode, cooldowns, boss bar, toasts, room and chapter banners.

const Art = preload("res://src/core/art.gd")
var canvas
var toasts = []
var banner = ""
var banner_sub = ""
var banner_t = 0.0
var boss_name = ""
var boss_sub = ""
var boss_t = 0.0
var t = 0.0
var hp_lag = 100.0

func _ready():
	layer = 10
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_ui)
	add_child(canvas)
	G.toast.connect(func(m): 
		toasts.append([m, 3.2])
		if toasts.size() > 5: toasts.pop_front())

func show_banner(title, sub = ""):
	banner = title
	banner_sub = sub
	banner_t = 3.5

func boss_intro(n, s):
	boss_name = n
	boss_sub = s
	boss_t = 3.0

func _process(dt):
	t += dt
	banner_t = max(0.0, banner_t - dt)
	boss_t = max(0.0, boss_t - dt)
	for x in toasts: x[1] -= dt
	toasts = toasts.filter(func(x): return x[1] > 0)
	canvas.queue_redraw()

func _bar(c, pos, w, frac, col, h = 10.0):
	c.draw_rect(Rect2(pos - Vector2(2, 2), Vector2(w + 4, h + 4)), Color(0, 0, 0, 0.55))
	c.draw_rect(Rect2(pos, Vector2(w * clamp(frac, 0.0, 1.0), h)), col)
	c.draw_rect(Rect2(pos, Vector2(w * clamp(frac, 0.0, 1.0), 2)), Color(1, 1, 1, 0.35))

func _draw_ui():
	var c = canvas
	var lv = G.level
	for i in toasts.size():
		var a = clamp(toasts[i][1], 0.0, 1.0)
		Art.text_shadow(c, Vector2(0, 110 + i * 24), toasts[i][0], 17, Color(1, 0.92, 0.75, a), HORIZONTAL_ALIGNMENT_RIGHT, 1250)
	if banner_t > 0:
		var a = clamp(min(banner_t, 3.5 - banner_t) * 1.5, 0.0, 1.0)
		Art.text_shadow(c, Vector2(0, 150), banner, 30, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		if banner_sub != "": Art.text_shadow(c, Vector2(0, 178), banner_sub, 16, Color(0.75, 0.85, 1, a * 0.8), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	if lv == null or lv.player == null or G.main.dialogue.active: return
	var p = lv.player
	var mh = float(G.max_hp())
	hp_lag = move_toward(hp_lag, p.hp, 40.0 * get_process_delta_time())
	var w = 200.0 + (mh - 100.0) * 0.8
	_bar(c, Vector2(28, 28), w, hp_lag / mh, Color(0.9, 0.9, 0.9, 0.5), 12.0)
	c.draw_rect(Rect2(28, 28, w * clamp(p.hp / mh, 0, 1), 12), Color(0.95, 0.3, 0.32) if p.hp / mh > 0.3 or int(t * 6) % 2 == 0 else Color(1, 0.7, 0.7))
	var me = float(G.max_en())
	_bar(c, Vector2(28, 48), 160.0 + (me - 100.0) * 0.8, p.en / me, Color(0.35, 0.8, 1.0) if p.emp_t <= 0 else Color(0.5, 0.5, 0.5), 7.0)
	for i in G.max_stims():
		var r = Rect2(28 + i * 18, 64, 12, 12)
		c.draw_rect(r, Color(0.4, 1.0, 0.6) if i < G.state.stims else Color(0.2, 0.3, 0.25, 0.7))
	Art.text_shadow(c, Vector2(28, 100), "◆ %d" % G.state.shards, 16, Color(1, 0.9, 0.6))
	var mode = p.AMMO[int(G.state.ammo) % p.AMMO.size()][2]
	Art.text_shadow(c, Vector2(110, 100), mode, 14, Color(0.7, 0.9, 1.0, 0.8))
	# cooldown pips
	var x = 180.0
	for cd in [["dash", p.dash_cd, 0.55, G.has("dash") or true], ["grav", p.grav_cd, 1.5, G.has("gauntlet")], ["sable", p.scan_cd, 9.0, true]]:
		if not cd[3]: continue
		var ready = cd[1] <= 0
		c.draw_arc(Vector2(x, 96), 7, -PI / 2, -PI / 2 + TAU * (1.0 - clamp(cd[1] / cd[2], 0, 1)), 14, Color(1, 1, 1, 0.9 if ready else 0.4), 2.5)
		x += 22
	if p.emp_t > 0: Art.text_shadow(c, Vector2(28, 124), "SYSTEMS SUPPRESSED", 14, Color(0.6, 0.8, 1.0))
	if lv.sight_t > 0: Art.text_shadow(c, Vector2(28, 142), "LATTICE SIGHT %.0f" % lv.sight_t, 14, DB.C("ffb060"))
	# boss
	if lv.boss != null and not lv.boss.dead and lv.boss.alert:
		var b = lv.boss
		_bar(c, Vector2(240, 672), 800, b.hp / b.max_hp, b.col, 10.0)
		for k in [0.33, 0.66]: c.draw_rect(Rect2(240 + 800 * k, 670, 2, 14), Color(0, 0, 0, 0.8))
		Art.text_shadow(c, Vector2(240, 662), b.bcfg.name, 15, Color(1, 1, 1, 0.9))
	if boss_t > 0:
		var a = clamp(min(boss_t, 3.0 - boss_t) * 2.0, 0.0, 1.0)
		c.draw_rect(Rect2(0, 250, 1280, 110), Color(0, 0, 0, 0.6 * a))
		Art.text_shadow(c, Vector2(0, 310), boss_name, 46, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		Art.text_shadow(c, Vector2(0, 342), boss_sub, 18, Color(1, 0.8, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	if p.dead: Art.text_shadow(c, Vector2(0, 360), "SIGNAL LOST", 40, Color(1, 0.4, 0.4, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 1280)
