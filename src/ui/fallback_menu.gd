extends CanvasLayer
# Minimal built-in menus used when src/ui/menus.gd (secondary half) is not present, so the game is
# always startable and completable: title, pause, star map and workbench.

const Art = preload("res://src/core/art.gd")
var canvas
var title = ""
var items = []   # [label, Callable, detail]
var sel = 0
var opened = false
var name_ = ""
var t = 0.0

func _ready():
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_ui)
	add_child(canvas)

func is_open(): return opened

func close_all():
	opened = false
	get_tree().paused = false

func open(n, _args = {}):
	name_ = n
	sel = 0
	opened = true
	items = []
	match n:
		"main":
			title = "HAWKTHORNE  —  ASHES OF THE STARS"
			Snd.music("menu")
			for s in range(1, G.SLOTS + 1):
				var r = G.read_slot(s)
				if r.ok: items.append(["Continue — slot %d  (Chapter %d: %s)" % [s, r.data.chapter, DB.chapters[int(r.data.chapter)].title], func(): 
					close_all()
					G.main.continue_game(s), r.saved])
			for s in range(1, G.SLOTS + 1): items.append(["New game — slot %d" % s, func(): 
				close_all()
				G.main.new_game(s), "Overwrites the slot"])
			items.append(["Difficulty: " + ["Story", "Normal", "Hard"][int(G.settings.difficulty)], func(): 
				G.settings.difficulty = (int(G.settings.difficulty) + 1) % 3
				G.save_meta()
				open("main"), ""])
			items.append(["Quit", func(): get_tree().quit(), ""])
		"pause":
			title = "PAUSED"
			get_tree().paused = true
			items.append(["Resume", close_all, ""])
			items.append(["Save and quit to title", func(): 
				G.save_game()
				close_all()
				G.main.to_menu(), ""])
		"starmap":
			title = "NAVIGATION — THE CINDER WREN"
			var ch = DB.chapters[int(G.state.chapter)]
			items.append(["▶ Chapter %d: %s  (%s)" % [G.state.chapter, ch.title, DB.regions[ch.region].name], func(): 
				close_all()
				G.main.load_room(ch.room), "Main objective"])
			for d in DB.side_dest:
				if G.cond(d[4]) and DB.rooms.has(d[3]) and G.state.quests.get(d[5], 0) < 99:
					items.append([d[1], func(): 
						close_all()
						G.main.load_room(d[3]), "Optional"])
			items.append(["Close", close_all, ""])
		"upgrades":
			title = "WORKBENCH   ◆ %d" % G.state.shards
			for u in DB.upgrades:
				var lvl = int(G.state.upgrades.get(u[0], 0))
				var cost = u[4] * (lvl + 1)
				if lvl >= u[3]: items.append(["%s  [MAX]" % u[1], func(): pass, u[2]])
				else: items.append(["%s  %d/%d  — %d shards" % [u[1], lvl, u[3], cost], func(): 
					if G.state.shards >= cost:
						G.state.shards -= cost
						G.state.upgrades[u[0]] = lvl + 1
						Snd.sfx("unlock")
					var keep = sel
					open("upgrades")
					sel = keep, u[2]])
			items.append(["Close", close_all, ""])
		_:
			title = n.to_upper()
			items.append(["Close", close_all, "This screen is provided by src/ui/menus.gd"])

func _process(dt):
	t += dt
	canvas.queue_redraw()
	if not opened or items.is_empty(): return
	if Input.is_action_just_pressed("down"):
		sel = (sel + 1) % items.size()
		Snd.sfx("ui")
	if Input.is_action_just_pressed("up"):
		sel = (sel - 1 + items.size()) % items.size()
		Snd.sfx("ui")
	if Input.is_action_just_pressed("accept") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact"):
		Snd.sfx("ui_ok")
		items[sel][1].call()
	elif Input.is_action_just_pressed("pause") and name_ != "main":
		Snd.sfx("ui_back")
		close_all()

func _draw_ui():
	if not opened: return
	var c = canvas
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.02, 0.05, 0.86 if name_ != "main" else 1.0))
	if name_ == "main":
		for i in 120:
			var p = Vector2(fmod(i * 197.3 + t * (2 + i % 5), 1280), fmod(i * 331.7, 720))
			c.draw_circle(p, 1.0 + (i % 3) * 0.5, Color(1, 1, 1, 0.3 + 0.3 * sin(t + i)))
		Art.glow(c, Vector2(900, 300), 300, Color(1, 0.5, 0.3, 0.25))
	Art.text_shadow(c, Vector2(0, 150), title, 40, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	c.draw_line(Vector2(400, 170), Vector2(880, 170), Color(1, 0.7, 0.4, 0.6), 1.0)
	var y0 = 240.0
	var first = max(0, sel - 8)
	for i in range(first, min(items.size(), first + 12)):
		var y = y0 + (i - first) * 36
		if i == sel:
			c.draw_rect(Rect2(330, y - 24, 620, 32), Color(0.3, 0.6, 0.8, 0.25))
		Art.text(c, Vector2(350, y), items[i][0], 20, Color(1, 1, 1, 1.0 if i == sel else 0.6))
	if sel < items.size(): Art.text(c, Vector2(0, 690), str(items[sel][2]), 15, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 1280)
