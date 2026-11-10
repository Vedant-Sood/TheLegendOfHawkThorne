extends CanvasLayer
# DialogueUI — runs data-driven dialogue nodes (see data/dialogue/*.txt): typewriter lines with
# animated portraits, conditional lines, branching choices with effects, and stage directions.

const Art = preload("res://src/core/art.gd")

var active = false
var node = null
var idx = 0
var line = null
var shown = 0.0
var choices = []
var sel = 0
var wait_t = 0.0
var on_done = Callable()
var bars = 0.0
var title_text = ""
var title_t = 0.0
var flash_a = 0.0
var canvas
var t = 0.0
var hold_skip = 0.0

func _ready():
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_ui)
	add_child(canvas)

func play(id, done = Callable()):
	var v = DB.resolve(id)
	if v == null:
		if done.is_valid(): done.call()
		return false
	on_done = done
	_enter(v)
	return true

func say(who, text):
	node = {"id": "_say", "once": false, "key": "", "items": [{"k": "line", "who": who, "mood": "", "text": text, "cond": ""}]}
	on_done = Callable()
	idx = 0
	active = true
	line = null
	choices = []
	_advance()

func _enter(v):
	node = v
	idx = 0
	active = true
	line = null
	choices = []
	if v.once: G.state.flags[v.key] = 1
	_advance()

func _advance():
	line = null
	choices = []
	while idx < node.items.size():
		var it = node.items[idx]
		if not G.cond(it.cond):
			idx += 1
			continue
		match it.k:
			"line":
				idx += 1
				line = it
				shown = 0.0
				if it.who != "narr": G.log_line(DB.speaker(it.who).name, it.text)
				return
			"cmd":
				idx += 1
				if _cmd(it.cmd, it.args): return
			"goto":
				var v = DB.resolve(it.to)
				if v == null:
					idx += 1
					continue
				_enter(v)
				return
			"choice":
				while idx < node.items.size() and node.items[idx].k == "choice":
					if G.cond(node.items[idx].cond): choices.append(node.items[idx])
					idx += 1
				if choices.is_empty(): continue
				sel = 0
				return
	_finish()

func _finish():
	active = false
	line = null
	node = null
	if G.main.vista != null and G.main.vista.visible_now(): G.main.vista.hide_vista()
	var cb = on_done
	on_done = Callable()
	if cb.is_valid(): cb.call()

# returns true if the command blocks (wait)
func _cmd(c, a):
	match c:
		"wait":
			wait_t = float(a)
			return true
		"shake":
			if G.level: G.level.shake(float(a) if a != "" else 10.0)
		"flash":
			if G.settings.flash: flash_a = 1.0
		"fade":
			G.main.fade(1.0 if a == "out" else 0.0, 0.6)
			wait_t = 0.6
			return true
		"sfx": Snd.sfx(a)
		"music": Snd.music(a)
		"do": G.apply(a)
		"title":
			title_text = a
			title_t = 4.0
			wait_t = 2.6
			return true
		"vista":
			if G.main.vista != null:
				if a == "off": G.main.vista.hide_vista()
				else: G.main.vista.show_vista(a)
		"boss":
			if G.level and G.level.boss == null: pass
	return false

func _pressed():
	return Input.is_action_just_pressed("accept") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("attack")

func _process(dt):
	t += dt
	bars = move_toward(bars, 1.0 if active else 0.0, dt * 4.0)
	title_t = max(0.0, title_t - dt)
	flash_a = max(0.0, flash_a - dt * 2.0)
	canvas.queue_redraw()
	if not active or get_tree().paused: return
	if wait_t > 0:
		wait_t -= dt
		if wait_t <= 0: _advance()
		return
	if not choices.is_empty():
		if Input.is_action_just_pressed("down"):
			sel = (sel + 1) % choices.size()
			Snd.sfx("ui")
		if Input.is_action_just_pressed("up"):
			sel = (sel - 1 + choices.size()) % choices.size()
			Snd.sfx("ui")
		if _pressed():
			var ch = choices[sel]
			Snd.sfx("ui_ok")
			G.log_line("Hawkthorne", "» " + ch.text)
			G.apply(ch.do)
			choices = []
			if ch.to != "":
				var v = DB.resolve(ch.to)
				if v != null:
					_enter(v)
					return
			_advance()
		return
	if line != null:
		var before = int(shown)
		shown += dt * 55.0 * G.settings.text_speed
		if int(shown) != before and int(shown) < line.text.length() and int(shown) % 3 == 0:
			Snd.sfx("blip_s" if line.who == "sable" else "blip", -12)
		hold_skip = hold_skip + dt if Input.is_action_pressed("dash") else 0.0
		if _pressed() or hold_skip > 0.35:
			if hold_skip > 0.35: hold_skip = 0.25
			if shown < line.text.length(): shown = 9999.0
			else: _advance()

func _draw_ui():
	var c = canvas
	if flash_a > 0: c.draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, flash_a * 0.8))
	if bars > 0.01:
		c.draw_rect(Rect2(0, 0, 1280, 64 * bars), Color(0, 0, 0, 0.95))
		c.draw_rect(Rect2(0, 720 - 64 * bars, 1280, 64 * bars), Color(0, 0, 0, 0.95))
	if title_t > 0:
		var a = clamp(min(title_t, 4.0 - title_t) * 1.2, 0.0, 1.0)
		var parts = title_text.split("|")
		Art.text_shadow(c, Vector2(0, 330), parts[0].strip_edges(), 44, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		if parts.size() > 1: Art.text_shadow(c, Vector2(0, 372), parts[1].strip_edges(), 20, Color(0.8, 0.85, 1.0, a * 0.8), HORIZONTAL_ALIGNMENT_CENTER, 1280)
		c.draw_line(Vector2(640 - 180 * a, 344), Vector2(640 + 180 * a, 344), Color(1, 1, 1, a * 0.5), 1.0)
	if not active: return
	var big = G.settings.big_text
	var fs = 24 if big else 20
	if line != null:
		var sp = DB.speaker(line.who)
		var narr = line.who == "narr"
		var box = Rect2(150, 520, 980, 150)
		c.draw_rect(box, Color(0.02, 0.03, 0.06, 0.88 if not G.settings.contrast else 1.0))
		c.draw_rect(Rect2(box.position, Vector2(box.size.x, 2)), sp.col)
		c.draw_rect(Rect2(box.position + Vector2(0, box.size.y - 1), Vector2(box.size.x, 1)), Color(sp.col.r, sp.col.g, sp.col.b, 0.3))
		var tx = box.position.x + 24
		if not narr:
			Art.portrait(c, sp.port, Rect2(box.position + Vector2(-130, -10), Vector2(140, 170)), line.mood, t, shown < line.text.length(), sp.get("seed", 0))
			Art.text(c, Vector2(tx + 10, box.position.y + 30), sp.name.to_upper(), 15, sp.col)
			if line.mood != "" and line.who == "sable": Art.text(c, Vector2(tx + 10 + 90, box.position.y + 30), "· " + line.mood, 13, Color(1, 1, 1, 0.35))
		var txt = line.text.substr(0, int(shown))
		c.draw_multiline_string(Art.font(), Vector2(tx + 10, box.position.y + (60 if not narr else 48)), txt, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 70, fs, 4, Color(0.93, 0.94, 0.97) if not narr else Color(0.8, 0.82, 0.9))
		if shown >= line.text.length() and int(t * 2) % 2 == 0:
			c.draw_colored_polygon(PackedVector2Array([box.end + Vector2(-30, -22), box.end + Vector2(-18, -22), box.end + Vector2(-24, -14)]), sp.col)
	elif not choices.is_empty():
		var h = 44.0 if not big else 50.0
		var y0 = 660.0 - choices.size() * h
		c.draw_rect(Rect2(260, y0 - 44, 760, choices.size() * h + 56), Color(0.02, 0.03, 0.06, 0.92))
		Art.text(c, Vector2(284, y0 - 16), "HAWKTHORNE", 14, DB.C("d8dde8", 0.6))
		for i in choices.size():
			var r = Rect2(276, y0 + i * h, 728, h - 6)
			if i == sel:
				c.draw_rect(r, Color(0.3, 0.6, 0.8, 0.28))
				c.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(0.5, 0.9, 1.0))
			Art.text(c, r.position + Vector2(18, h * 0.5 + 3), choices[i].text, fs - 2, Color(1, 1, 1, 1.0 if i == sel else 0.65))
