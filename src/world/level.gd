extends Node2D
# Level — builds a room from data, owns tile collision, entities, hazards, camera and world rendering.

const Art = preload("res://src/core/art.gd")
const Player = preload("res://src/actors/player.gd")
const Enemy = preload("res://src/actors/enemy.gd")
const Boss = preload("res://src/actors/boss.gd")
const T = 32
const ZOOM = 1.3

class Layer extends Node2D:
	var fn: Callable
	func _draw(): fn.call(self)

var id = ""
var room = {}
var reg = {}
var pal = {}
var W = 0
var H = 0
var grid = PackedByteArray()
var player = null
var enemies = []
var crates = []
var platforms = []
var shots = []
var zones = []
var parts = []
var things = []
var triggers = []
var lights = []
var deco = []
var arenas = []
var gate_groups = []
var boss = null
var cam = null
var cam_pos = Vector2.ZERO
var shake_amt = 0.0
var hitstop = 0
var time = 0.0
var grav_mult = 1.0
var water = false
var dark = false
var mods = []
var sight_t = 0.0
var chase_x = -99999.0
var storm_t = 3.0
var spawn = Vector2.ZERO
var safe_pos = Vector2.ZERO
var backdrop = null
var post = null
var l_tiles; var l_dyn; var l_glow; var l_fx
var near_thing = null
var hack = null
var exiting = false
var mote_t = 0.0
var mote_pos = Vector2.ZERO

func setup(room_id, entry):
	id = room_id
	room = DB.rooms[id]
	reg = DB.regions.get(room.region, DB.regions.kharon)
	for k in ["tile", "hi", "in", "acc", "acc2", "fog"]: pal[k] = DB.C(reg[k])
	grav_mult = float(room.get("grav", reg.get("grav", 1.0)))
	water = reg.get("water", false) and room.get("dry", "0") != "1"
	mods = Array(str(room.get("mods", "")).split(",", false))
	dark = "dark" in mods
	var a = DB.assemble(id)
	W = a.W; H = a.H; grid = a.grid
	_layers()
	_spawn_all(a.slots, entry)
	_deco()
	G.state.visited[id] = 1
	G.state.room = id
	Snd.music(room.get("music", "boss" if boss != null else room.region))
	l_tiles.queue_redraw()

func _layers():
	l_tiles = _layer(_draw_tiles, 0)
	l_dyn = _layer(_draw_dyn, 1)
	l_fx = _layer(_draw_fx, 8)
	l_glow = _layer(_draw_glow, 9)
	var m = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	l_glow.material = m
	cam = Camera2D.new()
	add_child(cam)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = max(W * T, 1280)
	cam.limit_bottom = H * T
	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.make_current()
	if ResourceLoader.exists("res://src/world/backdrop.gd"):
		backdrop = load("res://src/world/backdrop.gd").new()
		add_child(backdrop)
		backdrop.setup(room.region, room)
	else:
		var cl = CanvasLayer.new()
		cl.layer = -10
		add_child(cl)
		var cr = ColorRect.new()
		cr.size = Vector2(1280, 720)
		var g = Gradient.new()
		g.set_color(0, DB.C(reg.top))
		g.set_color(1, DB.C(reg.bot))
		var gt = GradientTexture2D.new()
		gt.gradient = g
		gt.fill_to = Vector2(0, 1)
		var tr = TextureRect.new()
		tr.texture = gt
		tr.size = Vector2(1280, 720)
		cl.add_child(tr)
	if ResourceLoader.exists("res://src/world/post.gd"):
		post = load("res://src/world/post.gd").new()
		add_child(post)
		post.setup(room.region)

func _layer(fn, z):
	var l = Layer.new()
	l.fn = fn
	l.z_index = z
	add_child(l)
	return l

func cell_pos(c: Vector2i): return Vector2(c.x * T + T * 0.5, c.y * T + T)  # bottom-centre of the cell

func _spawn_all(slots, entry):
	var taken = G.state.taken
	# checkpoints + spawn
	var cps = [Vector2(48, _ground_y(1))]
	for c in slots.get("C", []): cps.append(cell_pos(c))
	spawn = cps[0]
	if entry == "end": spawn = Vector2(W * T - 48, _ground_y(W - 2))
	elif entry.begins_with("cp:"): spawn = cps[clamp(int(entry.substr(3)), 0, cps.size() - 1)]
	for i in range(1, cps.size()): things.append({"kind": "checkpoint", "pos": cps[i], "idx": i})
	var lists = {"e": room.get("e", []), "n": room.get("n", []), "T": room.get("T", []), "L": room.get("L", []), "S": room.get("S", []), "D": room.get("D", []), "t": room.get("t", []), "X": room.get("X", [])}
	for sym in slots:
		var arr = slots[sym]
		for i in arr.size():
			var p = cell_pos(arr[i])
			var key = "%s:%s%d" % [id, sym, i]
			var spec = lists[sym][i] if lists.has(sym) and i < lists[sym].size() else ""
			match sym:
				"e":
					if spec != "" and spec != "-" and DB.enemies.has(spec): spawn_enemy(spec, p)
				"o":
					if not taken.has(key): things.append({"kind": "shard", "pos": p - Vector2(0, 14), "key": key})
				"h":
					things.append({"kind": "health", "pos": p - Vector2(0, 12), "key": key, "gone": false})
				"c": crates.append({"pos": p - Vector2(0, 14), "half": Vector2(14, 14), "vel": Vector2.ZERO, "on_ground": false, "hit_wall": 0, "hit_ceil": false, "home": p - Vector2(0, 14)})
				"T":
					if spec != "": things.append({"kind": "terminal", "pos": p, "spec": spec, "key": key, "inter": "Access terminal", "done": G.f("done." + key) != 0})
				"X":
					if spec != "": things.append({"kind": "node", "pos": p, "spec": spec, "key": key, "inter": "Lattice node", "done": G.f("done." + key) != 0})
				"N":
					var ns = lists["n"][i] if i < lists["n"].size() else ""
					if ns.begins_with("@"): things.append({"kind": "station", "pos": p, "spec": ns.substr(1), "inter": {"bench": "Workbench", "nav": "Navigation", "bunk": "Rest & save", "sable": "Speak with Sable"}.get(ns.substr(1), "Use")})
					elif ns != "" and ns != "-" and DB.resolve("npc_" + ns) != null:
						var sp = DB.speaker(ns)
						things.append({"kind": "npc", "pos": p, "who": ns, "inter": "Talk — " + sp.name, "col": sp.col, "seed": ns.hash(), "face": -1})
				"L":
					if spec != "": things.append({"kind": "lore", "pos": p, "spec": spec, "inter": "Examine"})
				"S":
					if spec != "" and not taken.has(key): things.append({"kind": "secret", "pos": p - Vector2(0, 10), "spec": spec, "key": key})
				"D":
					if spec != "":
						things.append({"kind": "door", "pos": p, "spec": spec, "inter": "Enter — " + DB.rooms.get(spec, {}).get("name", spec)})
						if entry == "door:" + spec: spawn = p
				"t":
					if spec != "": triggers.append({"x": p.x, "node": spec, "key": "trg." + key})
				"P": things.append({"kind": "plate", "pos": p, "key": key, "done": G.f("done." + key) != 0})
				"Q": things.append({"kind": "switch", "pos": p - Vector2(0, 16), "key": key, "done": G.f("done." + key) != 0})
				"M": platforms.append({"pos": p - Vector2(48, 20), "w": 96.0, "a": p.x - 48 - 110, "b": p.x - 48 + 110, "axis": 0, "ph": i * 1.3, "delta": Vector2.ZERO})
				"V": platforms.append({"pos": p - Vector2(48, 20), "w": 96.0, "a": p.y - 20 - 120, "b": p.y - 20 + 20, "axis": 1, "ph": i * 1.3, "delta": Vector2.ZERO})
				"B":
					var bid = room.get("boss", "")
					if bid != "" and G.state.bosses.get(bid, 0) == 0 and G.cond(room.get("boss_if", "")):
						boss = Boss.new()
						add_child(boss)
						boss.init_boss(self, bid, p)
						enemies.append(boss)
	# gate groups: contiguous columns of tile 8
	var col_has = []
	for x in W:
		var any = false
		for y in H:
			if grid[y * W + x] == 8: any = true
		col_has.append(any)
	var x = 0
	while x < W:
		if col_has[x]:
			var x1 = x
			while x1 + 1 < W and col_has[x1 + 1]: x1 += 1
			gate_groups.append({"x0": x, "x1": x1, "open": false})
			x = x1
		x += 1
	# link openers (terminals with 'gate', plates, switches) to the nearest gate to their right
	for th in things:
		if (th.kind == "terminal" and str(th.spec).begins_with("gate")) or th.kind in ["plate", "switch"]:
			var best = -1
			for gi in gate_groups.size():
				if gate_groups[gi].x0 * T > th.pos.x - 40 and not gate_groups[gi].has("owner"):
					best = gi
					break
			if best < 0: best = gate_groups.size() - 1
			if best >= 0:
				th["gate"] = best
				gate_groups[best]["owner"] = 1
				if th.done: _open_gate(best, false)
	# arenas: pairs of tile-10 columns
	var acols = []
	for xx in W:
		for y in H:
			if grid[y * W + xx] == 10:
				if acols.is_empty() or acols[-1] != xx: acols.append(xx)
				break
	var i2 = 0
	while i2 + 1 < acols.size():
		arenas.append({"x0": acols[i2], "x1": acols[i2 + 1], "on": false, "done": false})
		i2 += 2
	player = Player.new()
	add_child(player)
	player.init(self, spawn - Vector2(0, 28))
	safe_pos = player.pos
	cam_pos = player.pos
	mote_pos = player.pos
	if "chase" in mods: chase_x = -500.0

func _ground_y(tx):
	tx = clamp(tx, 0, W - 1)
	for y in range(H - 1, 1, -1):
		if _solid_t(grid[y * W + tx]) and not _solid_t(grid[(y - 1) * W + tx]): return y * T
	return (H - 3) * T

func spawn_enemy(kind, p):
	var e = Enemy.new()
	add_child(e)
	e.init(self, kind, p)
	enemies.append(e)
	return e

func _deco():
	var rng = RandomNumberGenerator.new()
	rng.seed = id.hash()
	for x in range(1, W - 1):
		for y in range(3, H):
			if grid[y * W + x] == 1 and grid[(y - 1) * W + x] == 0 and grid[(y - 2) * W + x] == 0:
				var r = rng.randf()
				var p = Vector2(x * T + 16, y * T)
				if r < 0.06:
					deco.append({"k": "lamp", "p": p, "s": rng.randi()})
					lights.append({"p": p - Vector2(0, 70), "r": 150.0, "c": pal.acc2, "f": rng.randf() * 6.0})
				elif r < 0.16: deco.append({"k": "tall", "p": p, "s": rng.randi()})
				elif r < 0.4: deco.append({"k": "small", "p": p, "s": rng.randi()})
				break

# ---------------------------------------------------------------- collision
func _solid_t(t): return t == 1 or t == 5 or t == 8 or t == 11 or t == 6

func tile(tx, ty):
	if tx < 0 or tx >= W or ty < 0 or ty >= H: return 0
	return grid[ty * W + tx]

func solid_at(tx, ty, e = null):
	if tx < 0: return not room.has("back")
	if tx >= W: return not room.has("exit")
	if ty < 0 or ty >= H: return false
	var t = grid[ty * W + tx]
	if t == 0: return false
	if t == 1 or t == 5 or t == 8 or t == 11: return true
	if t == 6: return not (e != null and e.get("phase") == true)
	if t == 7: return sight_t > 0.0
	return false

func box_solid(pos, half, e = null):
	var x0 = int(floor((pos.x - half.x) / T))
	var x1 = int(floor((pos.x + half.x) / T))
	var y0 = int(floor((pos.y - half.y) / T))
	var y1 = int(floor((pos.y + half.y) / T))
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if solid_at(tx, ty, e): return true
	return false

func point_solid(p): return solid_at(int(floor(p.x / T)), int(floor(p.y / T)))

func los(a, b):
	var d = b - a
	var n = int(d.length() / 16.0) + 1
	for i in range(1, n):
		if point_solid(a + d * (float(i) / n)): return false
	return true

func move_box(e, dt, gdir = 1):
	e.on_ground = false
	e.hit_wall = 0
	e.hit_ceil = false
	var d = e.vel * dt
	var steps = int(max(1.0, ceil(max(abs(d.x), abs(d.y)) / 10.0)))
	var sx = d.x / steps
	var sy = d.y / steps
	for i in steps:
		if sx != 0.0:
			e.pos.x += sx
			if box_solid(e.pos, e.half, e):
				if sx > 0: e.pos.x = floor((e.pos.x + e.half.x) / T) * T - e.half.x - 0.01
				else: e.pos.x = (floor((e.pos.x - e.half.x) / T) + 1) * T + e.half.x + 0.01
				e.hit_wall = sign(sx)
				e.vel.x = 0
				sx = 0.0
		if sy != 0.0:
			var oldbot = e.pos.y + e.half.y
			e.pos.y += sy
			if box_solid(e.pos, e.half, e):
				if sy > 0: e.pos.y = floor((e.pos.y + e.half.y) / T) * T - e.half.y - 0.01
				else: e.pos.y = (floor((e.pos.y - e.half.y) / T) + 1) * T + e.half.y + 0.01
				if sign(sy) == gdir: e.on_ground = true
				else: e.hit_ceil = true
				e.vel.y = 0
				sy = 0.0
			elif sy > 0 and gdir == 1 and e.get("drop") != true:
				var newbot = e.pos.y + e.half.y
				var row = int(floor(newbot / T))
				if int(floor(oldbot / T)) < row or fmod(oldbot, T) < 0.02:
					var hit = false
					for tx in range(int(floor((e.pos.x - e.half.x) / T)), int(floor((e.pos.x + e.half.x) / T)) + 1):
						if tile(tx, row) == 2: hit = true
					if hit and oldbot <= row * T + 0.02:
						e.pos.y = row * T - e.half.y - 0.01
						e.on_ground = true
						e.vel.y = 0
						sy = 0.0
				if sy != 0.0:
					for pl in platforms:
						if oldbot <= pl.pos.y + 4.0 and newbot >= pl.pos.y and e.pos.x + e.half.x > pl.pos.x and e.pos.x - e.half.x < pl.pos.x + pl.w:
							e.pos.y = pl.pos.y - e.half.y - 0.01
							e.on_ground = true
							e.vel.y = 0
							sy = 0.0
							if e is Node: e.riding = pl
							break

# ---------------------------------------------------------------- combat helpers
func shake(a): shake_amt = max(shake_amt, a * G.settings.shake)
func stop(frames): hitstop = max(hitstop, frames)

func burst(pos, col, n = 8, speed = 180.0, life = 0.5, grav = 400.0):
	if parts.size() > 700: return
	for i in n:
		var a = randf() * TAU
		parts.append({"p": pos, "v": Vector2(cos(a), sin(a)) * speed * randf_range(0.3, 1.0), "l": life * randf_range(0.5, 1.0), "m": life, "c": col, "g": grav, "s": randf_range(1.5, 3.5)})

func spark(pos, col, dir, n = 5):
	for i in n:
		parts.append({"p": pos, "v": (dir.rotated(randf_range(-0.6, 0.6))) * randf_range(120, 380), "l": 0.3, "m": 0.3, "c": col, "g": 300.0, "s": 2.0})

func popup(pos, txt, col):
	parts.append({"p": pos, "v": Vector2(0, -50), "l": 0.8, "m": 0.8, "c": col, "g": 0.0, "s": 0.0, "txt": txt})

func shoot(d):
	# required: pos, vel, team. optional: dmg, r, life, col, kind, grav, pierce, homing
	var s = {"r": 5.0, "dmg": 8, "life": 2.5, "col": pal.acc, "kind": "bolt", "grav": 0.0, "pierce": 0, "homing": 0.0, "hits": []}
	s.merge(d, true)
	shots.append(s)
	return s

func zone(d):
	# shape rect(a=pos,b=size) | circle(a=centre,r) | line(a,b,w); warn, live, dmg
	var z = {"shape": "rect", "warn": 0.7, "live": 0.25, "dmg": 15, "col": Color(1, 0.3, 0.2), "t": 0.0, "hit": false, "w": 14.0, "r": 60.0, "team": 1, "sfx": "boom"}
	z.merge(d, true)
	zones.append(z)
	return z

func hit_enemies(rect: Rect2, dmg, kb, kind = "blade", pierce = true):
	var n = 0
	for e in enemies:
		if e.dead or e.intangible: continue
		if rect.intersects(Rect2(e.pos - e.half, e.half * 2.0)):
			if e.take_hit(dmg, kb, kind, rect.get_center().x): n += 1
			if not pierce: break
	# breakable tiles + switches
	if kind in ["blade", "charge", "crate", "boom"]:
		for th in things:
			if th.kind == "switch" and not th.done and rect.has_point(th.pos): _activate(th)
		if kind != "blade":
			for ty in range(int(rect.position.y / T), int(rect.end.y / T) + 1):
				for tx in range(int(rect.position.x / T), int(rect.end.x / T) + 1):
					if tile(tx, ty) == 5:
						grid[ty * W + tx] = 0
						burst(Vector2(tx * T + 16, ty * T + 16), pal.hi, 10, 220)
						Snd.sfx("boom", -6)
						l_tiles.queue_redraw()
	return n

func hurt_player(dmg, from, kind = "melee", src = null):
	if player.dead: return "none"
	return player.take_hit(dmg, from, kind, src)

func player_rect(): return Rect2(player.pos - player.half, player.half * 2.0)

func alive_enemies(x0 = -1e9, x1 = 1e9):
	var n = 0
	for e in enemies:
		if not e.dead and e.pos.x > x0 and e.pos.x < x1 and not e.ally: n += 1
	return n

# ---------------------------------------------------------------- gates / interactables
func _open_gate(gi, fx = true):
	var g = gate_groups[gi]
	if g.open: return
	g.open = true
	for x in range(g.x0, g.x1 + 1):
		for y in H:
			if grid[y * W + x] == 8: grid[y * W + x] = 0
	if fx:
		Snd.sfx("door")
		shake(4)

func _activate(th):
	th.done = true
	G.state.flags["done." + th.key] = 1
	if th.has("gate"): _open_gate(th.gate)
	Snd.sfx("ui_ok")
	burst(th.pos, pal.acc2, 10, 150)

func interact():
	var th = near_thing
	if th == null: return
	match th.kind:
		"npc": G.main.dialogue.play("npc_" + th.who)
		"lore":
			G.state.flags["lore." + th.spec] = 1
			G.main.dialogue.play("lore_" + th.spec)
		"door":
			if not exiting:
				exiting = true
				G.main.load_room(th.spec, "door:" + id)
		"terminal", "node":
			if th.done and not str(th.spec).contains("dlg:"): return
			var need = 1.4
			if th.kind == "node":
				if G.sable_stage() < int(th.get("stage", 3)):
					G.main.dialogue.say("sable", "I can see that it is a language. I cannot yet see what it says.")
					return
				need = 2.0
			if G.f("sable_silent") != 0:
				need = 4.0
				G.toast.emit("Sable does not answer. Manual override…")
			elif G.val("rel.sable") <= -4 and G.sable_stage() >= 4:
				need = 3.2
				G.toast.emit("Sable: \"…Fine.\"")
			hack = {"th": th, "t": 0.0, "need": need}
			Snd.sfx("hack")
		"station":
			match th.spec:
				"bench": G.main.open_menu("upgrades")
				"nav": G.main.open_menu("starmap")
				"bunk":
					player.full_heal()
					G.save_game()
					G.toast.emit("Rested. Progress saved.")
					Snd.sfx("heal")
				"sable": G.main.dialogue.play("npc_sable")

func _finish_hack(th):
	var spec = str(th.spec)
	if not th.done: _activate(th)
	for part in spec.split("+"):
		if part.begins_with("dlg:"): G.main.dialogue.play(part.substr(4))
		elif part.begins_with("do:"): G.apply(part.substr(3).replace(",", ";"))

func checkpoint(th):
	if G.state.cp == th.idx and th.get("lit", false): return
	th["lit"] = true
	G.state.cp = th.idx
	player.full_heal()
	G.save_game()
	G.toast.emit("Checkpoint")
	Snd.sfx("heal", -6)
	burst(th.pos - Vector2(0, 30), pal.acc2, 14, 160)

# ---------------------------------------------------------------- main loop
func _physics_process(dt):
	if G.main.dialogue.active or G.main.busy(): return
	if hitstop > 0:
		hitstop -= 1
		return
	if G.settings.slow: dt *= 0.8
	time += dt
	sight_t = max(0.0, sight_t - dt)
	for pl in platforms:
		var old = pl.pos
		var k = 0.5 + 0.5 * sin(time * 0.9 + pl.ph)
		if pl.axis == 0: pl.pos.x = lerp(pl.a, pl.b, k)
		else: pl.pos.y = lerp(pl.a, pl.b, k)
		pl.delta = pl.pos - old
	player.tick(dt)
	for e in enemies:
		if e.dead: continue
		if abs(e.pos.x - player.pos.x) < 1000.0 or e.is_boss: e.tick(dt)
	enemies = enemies.filter(func(e): return not e.gone)
	_tick_crates(dt)
	_tick_shots(dt)
	_tick_zones(dt)
	_tick_things(dt)
	_tick_world(dt)
	Snd.combat(1.0 if (boss != null and not boss.dead) else (0.7 if _threat() else 0.0))

func _threat():
	for e in enemies:
		if not e.dead and e.alert and abs(e.pos.x - player.pos.x) < 700: return true
	return false

func _tick_crates(dt):
	for c in crates:
		c.vel.y += 1500.0 * grav_mult * dt
		var sp = c.vel.length()
		move_box(c, dt)
		if c.on_ground: c.vel.x = move_toward(c.vel.x, 0, 900 * dt)
		if sp > 260.0:
			if hit_enemies(Rect2(c.pos - c.half, c.half * 2), 30, c.vel.normalized() * 300, "crate") > 0:
				c.vel *= -0.2
				burst(c.pos, pal.hi, 8)
		if c.pos.y > H * T + 100:
			c.pos = c.home
			c.vel = Vector2.ZERO
		for th in things:
			if th.kind == "plate" and not th.done and abs(c.pos.x - th.pos.x) < 24 and abs(c.pos.y + 14 - th.pos.y) < 12: _activate(th)

func _tick_shots(dt):
	var pr = player_rect()
	for s in shots:
		s.life -= dt
		if s.grav != 0.0: s.vel.y += s.grav * dt
		if s.homing > 0.0 and s.team == 1:
			var want = (player.pos - s.pos).normalized() * s.vel.length()
			s.vel = s.vel.lerp(want, s.homing * dt).normalized() * s.vel.length()
		s.pos += s.vel * dt
		if s.kind != "wave" and point_solid(s.pos):
			s.life = 0
			spark(s.pos, s.col, -s.vel.normalized(), 4)
			if s.kind == "bomb": _explode(s)
			if s.team == 0:
				var tx = int(s.pos.x / T)
				var ty = int(s.pos.y / T)
				if tile(tx, ty) == 5 and s.pierce > 0:
					hit_enemies(Rect2(s.pos - Vector2(8, 8), Vector2(16, 16)), 0, Vector2.ZERO, "charge")
			continue
		if s.team == 1:
			if not player.dead and pr.grow(s.r - 2.0).has_point(s.pos):
				var res = hurt_player(s.dmg, s.pos - s.vel * 0.05, "shot", s)
				if res == "parried":
					s.team = 0
					s.vel = -s.vel * 1.3
					s.dmg = s.dmg * 2 + 10
					s.col = player.blade_col
					s.life = 2.0
				elif res != "dodged":
					s.life = 0
					if s.get("emp", false):
						player.emp_t = 4.0
						player.en = 0.0
					if s.kind == "bomb": _explode(s)
		else:
			for e in enemies:
				if e.dead or e.intangible or e in s.hits: continue
				if Rect2(e.pos - e.half, e.half * 2).grow(s.r).has_point(s.pos):
					e.take_hit(s.dmg, s.vel.normalized() * 120, "gun" if s.kind != "arc" else "arc", s.pos.x - s.vel.x)
					s.hits.append(e)
					if s.pierce <= 0:
						s.life = 0
						break
					s.pierce -= 1
			for th in things:
				if th.kind == "switch" and not th.done and th.pos.distance_to(s.pos) < 18:
					_activate(th)
					s.life = 0
	shots = shots.filter(func(s): return s.life > 0)

func _explode(s):
	zone({"shape": "circle", "a": s.pos, "r": 56.0, "warn": 0.0, "live": 0.15, "dmg": s.dmg, "team": s.team})

func _zone_hits(z, rect: Rect2):
	match z.shape:
		"rect": return Rect2(z.a, z.b).intersects(rect)
		"circle": return rect.grow(z.r).has_point(z.a)
		"line":
			var c = rect.get_center()
			var ab = z.b - z.a
			var tt = clamp((c - z.a).dot(ab) / max(1.0, ab.length_squared()), 0.0, 1.0)
			return (z.a + ab * tt).distance_to(c) < z.w * 0.5 + 14.0
	return false

func _tick_zones(dt):
	for z in zones:
		var was = z.t
		z.t += dt
		if was < z.warn and z.t >= z.warn:
			if z.sfx != "": Snd.sfx(z.sfx, -4)
			shake(5)
			if z.shape == "circle": burst(z.a, z.col, 14, 260)
		if z.t >= z.warn and z.t < z.warn + z.live and not z.hit:
			if z.team == 1:
				if _zone_hits(z, player_rect()):
					var res = hurt_player(z.dmg, z.a if z.shape != "rect" else z.a + z.b * 0.5, "zone")
					if res != "dodged": z.hit = true
			else:
				z.hit = true
				for e in enemies:
					if not e.dead and _zone_hits(z, Rect2(e.pos - e.half, e.half * 2)): e.take_hit(z.dmg, Vector2(0, -200), "boom", z.a.x)
	zones = zones.filter(func(z): return z.t < z.warn + z.live)

func _tick_things(dt):
	near_thing = null
	var best = 46.0
	var pp = player.pos + Vector2(0, player.half.y)
	for th in things:
		var d = th.pos.distance_to(pp)
		match th.kind:
			"shard":
				if d < 30:
					th["gone"] = true
					G.state.taken[th.key] = 1
					var amt = 5 if not G.has_mod("charm") else 6
					G.state.shards += amt
					Snd.sfx("pickup", -8)
					burst(th.pos, pal.acc2, 5, 100, 0.3)
				elif d < 110: th.pos = th.pos.move_toward(player.pos, 300 * dt)
			"health":
				if not th.gone and d < 30 and player.hp < G.max_hp():
					th.gone = true
					player.heal(30)
			"secret":
				if d < 32:
					th["gone"] = true
					G.state.taken[th.key] = 1
					G.apply(str(th.spec).replace(",", ";"))
					Snd.sfx("unlock")
					burst(th.pos, Color(1, 0.9, 0.5), 24, 240)
			"checkpoint":
				if d < 40: checkpoint(th)
			"plate":
				if not th.done and d < 22 and room.get("plate_player", "0") == "1": _activate(th)
			_:
				if th.has("inter") and d < best:
					best = d
					near_thing = th
		if th.kind == "npc": th.face = 1 if player.pos.x > th.pos.x else -1
	things = things.filter(func(t): return not t.get("gone", false) or t.kind == "health")
	if hack != null:
		if hack.th.pos.distance_to(pp) > 70 or player.hurt_t > 0:
			hack = null
			G.toast.emit("Link broken")
		else:
			hack.t += dt
			if hack.t >= hack.need:
				var th = hack.th
				hack = null
				_finish_hack(th)

func _tick_world(dt):
	# triggers
	for tr in triggers:
		if not tr.get("fired", false) and player.pos.x > tr.x:
			tr["fired"] = true
			if G.f(tr.key) == 0 and DB.resolve(tr.node) != null:
				G.state.flags[tr.key] = 1
				G.main.dialogue.play(tr.node)
				return
	# arenas
	for a in arenas:
		if a.done: continue
		var x0 = (a.x0 + 1) * T
		var x1 = a.x1 * T
		var inside = player.pos.x > x0 + 30 and player.pos.x < x1 - 30
		var alive = alive_enemies(x0, x1)
		if not a.on and inside and alive > 0:
			a.on = true
			_set_arena(a, 11)
			Snd.sfx("door")
		elif a.on and alive == 0:
			a.on = false
			a.done = true
			_set_arena(a, 10)
			Snd.sfx("door")
			burst(player.pos, pal.acc2, 12, 200)
	# safe position for pit recovery
	if player.on_ground and not player.dead and player.gdir == 1 and player.riding == null:
		var tx = int(player.pos.x / T)
		var ty = int((player.pos.y + player.half.y + 4) / T)
		if tile(tx, ty) == 1 and tile(tx - 1, ty) != 0 and tile(tx + 1, ty) != 0: safe_pos = player.pos
	# region modifiers
	if "storm" in mods:
		storm_t -= dt
		if storm_t <= 0:
			storm_t = randf_range(1.6, 3.2)
			var x = player.pos.x + randf_range(-260, 320) + player.vel.x * 0.5
			zone({"shape": "rect", "a": Vector2(x - 26, 0), "b": Vector2(52, H * T), "warn": 0.9, "live": 0.2, "dmg": 16, "col": pal.acc, "sfx": "thunder"})
	if "bombard" in mods:
		storm_t -= dt
		if storm_t <= 0:
			storm_t = randf_range(1.2, 2.6)
			var x = player.pos.x + randf_range(-300, 380) + player.vel.x * 0.6
			zone({"shape": "circle", "a": Vector2(x, _ground_at(x, player.pos.y)), "r": 80.0, "warn": 1.1, "live": 0.2, "dmg": 20, "col": Color(1, 0.5, 0.2)})
	if "chase" in mods and not (boss != null and boss.dead):
		chase_x += (150.0 + min(90.0, time * 2.0)) * dt
		chase_x = max(chase_x, player.pos.x - 760)
		if player.pos.x < chase_x + 20 and not player.dead: player.die()
	# exits
	if not exiting and not player.dead:
		if player.pos.x > W * T - 6 and room.has("exit"):
			var locked = boss != null and not boss.dead
			if not locked: _leave(room.exit, "start")
		elif player.pos.x < 6 and room.has("back"): _leave(room.back, "end")

func _ground_at(x, y):
	var tx = int(x / T)
	for ty in range(int(y / T), H):
		if solid_at(tx, ty): return ty * T
	return H * T

func _leave(target, entry):
	exiting = true
	if target.begins_with("@"):
		G.main.dialogue.play(target.substr(1))
		exiting = false
		player.pos.x = clamp(player.pos.x, 12, W * T - 12)
		player.vel.x = 0
		if DB.resolve(target.substr(1)) == null: pass
		return
	G.main.load_room(target, entry)

func _set_arena(a, t):
	for x in [a.x0, a.x1]:
		for y in H:
			var v = grid[y * W + x]
			if v == 10 or v == 11: grid[y * W + x] = t

func boss_dead(b):
	G.state.bosses[b.kind] = 1
	for a in arenas:
		a.done = true
		_set_arena(a, 10)
	Snd.music(room.region)
	G.save_game()
	if room.has("end"): G.main.after(2.2, func(): G.main.dialogue.play(room.end))

func respawn_safe(dmg):
	player.pos = safe_pos
	player.vel = Vector2.ZERO
	player.gdir = 1
	player.take_hit(dmg, player.pos, "pit")

# ---------------------------------------------------------------- frame / rendering
func _process(dt):
	if player == null: return
	var look = Vector2(player.facing * 70.0, -40.0)
	var target = player.pos + look
	if boss != null and not boss.dead: target = target.lerp(boss.pos, 0.25)
	cam_pos = cam_pos.lerp(target, 1.0 - exp(-dt * 5.0))
	shake_amt = max(0.0, shake_amt - dt * 30.0)
	var sh = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amt
	var hx = 640.0 / ZOOM
	var hy = 360.0 / ZOOM
	cam.position = Vector2(clamp(cam_pos.x, hx, max(hx, W * T - hx)), clamp(cam_pos.y, hy, H * T - hy)) + sh
	if backdrop != null: backdrop.update_view(cam.position, time)
	if post != null and dark: post.set_dark(0.85, (player.pos - cam.position) * ZOOM + Vector2(640, 360))
	# particles
	for p in parts:
		p.l -= dt
		p.v.y += p.g * dt
		p.p += p.v * dt
	parts = parts.filter(func(p): return p.l > 0)
	# Sable's drone
	var want = player.pos + Vector2(-player.facing * 26.0, -46.0 + sin(time * 2.0) * 5.0)
	mote_pos = mote_pos.lerp(want, 1.0 - exp(-dt * 4.0))
	l_dyn.queue_redraw()
	l_fx.queue_redraw()
	l_glow.queue_redraw()

func _view(): return Rect2(cam.position - Vector2(560, 340), Vector2(1120, 680))

func _draw_tiles(ci):
	var rng = RandomNumberGenerator.new()
	if reg.get("interior", false):
		ci.draw_rect(Rect2(0, 0, W * T, H * T), Color(pal["in"].r, pal["in"].g, pal["in"].b, 0.82))
		for x in range(0, W, 7):
			ci.draw_rect(Rect2(x * T, 0, 20, H * T), Color(pal.tile.r, pal.tile.g, pal.tile.b, 0.5))
			ci.draw_rect(Rect2(x * T + 20, 0, 3, H * T), Color(pal.hi.r, pal.hi.g, pal.hi.b, 0.08))
		for y in range(3, H, 6): ci.draw_rect(Rect2(0, y * T, W * T, 6), Color(0, 0, 0, 0.25))
	for d in deco: _draw_deco(ci, d)
	for y in H:
		for x in W:
			var t = grid[y * W + x]
			if t == 0: continue
			var r = Rect2(x * T, y * T, T, T)
			rng.seed = x * 7919 + y * 104729
			match t:
				1:
					var up = tile(x, y - 1)
					var open_up = y > 0 and not (up in [1, 5])
					var inner = (tile(x - 1, y) in [1, 5] or x == 0) and (tile(x + 1, y) in [1, 5] or x == W - 1) and not open_up and (tile(x, y + 1) in [1, 5] or y == H - 1)
					ci.draw_rect(r, pal["in"] if inner else pal.tile)
					if inner:
						if rng.randf() < 0.12: ci.draw_rect(Rect2(r.position + Vector2(6, 6), Vector2(20, 20)), pal.tile.darkened(0.25), false, 1.0)
					else:
						ci.draw_rect(Rect2(r.position + Vector2(0, T - 3), Vector2(T, 3)), Color(0, 0, 0, 0.3))
						if rng.randf() < 0.3: ci.draw_line(r.position + Vector2(rng.randi_range(4, 28), 6), r.position + Vector2(rng.randi_range(4, 28), 28), pal.tile.lightened(0.07), 1.0)
					if open_up:
						ci.draw_rect(Rect2(r.position, Vector2(T, 4)), pal.hi)
						ci.draw_rect(Rect2(r.position + Vector2(0, 4), Vector2(T, 2)), pal.hi.darkened(0.5))
						if rng.randf() < 0.1: ci.draw_rect(Rect2(r.position + Vector2(10, 1), Vector2(12, 2)), pal.acc)
					if not (tile(x - 1, y) in [1, 5]) and x > 0: ci.draw_rect(Rect2(r.position, Vector2(2, T)), pal.hi.darkened(0.3))
					if not (tile(x + 1, y) in [1, 5]) and x < W - 1: ci.draw_rect(Rect2(r.position + Vector2(T - 2, 0), Vector2(2, T)), pal.tile.darkened(0.4))
				2:
					ci.draw_rect(Rect2(r.position, Vector2(T, 7)), pal.tile.lightened(0.1))
					ci.draw_rect(Rect2(r.position, Vector2(T, 2)), pal.hi)
					if x % 2 == 0: ci.draw_line(r.position + Vector2(16, 7), r.position + Vector2(16, 15), pal.tile, 2.0)
				3:
					for i in 3:
						var bx = r.position.x + i * 10.67
						ci.draw_colored_polygon(PackedVector2Array([Vector2(bx, r.end.y), Vector2(bx + 5.3, r.position.y + 8), Vector2(bx + 10.6, r.end.y)]), pal.acc.darkened(0.2))
						ci.draw_line(Vector2(bx + 5.3, r.position.y + 8), Vector2(bx + 7, r.end.y), Color(1, 1, 1, 0.4), 1.0)
				5:
					ci.draw_rect(r, pal.tile.lightened(0.12))
					ci.draw_polyline(PackedVector2Array([r.position + Vector2(4, 2), r.position + Vector2(14, 14), r.position + Vector2(9, 22), r.position + Vector2(20, 30)]), pal.acc2.darkened(0.2), 1.5)
					ci.draw_polyline(PackedVector2Array([r.position + Vector2(14, 14), r.position + Vector2(27, 9)]), pal.acc2.darkened(0.2), 1.5)
					ci.draw_rect(r, pal.hi.darkened(0.3), false, 1.0)

func _draw_deco(ci, d):
	var rng = RandomNumberGenerator.new()
	rng.seed = d.s
	var p = d.p
	var dk = pal.tile.darkened(0.15)
	if d.k == "lamp":
		ci.draw_line(p, p + Vector2(0, -70), dk, 3.0)
		ci.draw_line(p + Vector2(0, -70), p + Vector2(10, -72), dk, 3.0)
		ci.draw_circle(p + Vector2(10, -68), 4.0, pal.acc2)
		return
	var tall = d.k == "tall"
	match room.region:
		"kharon", "colony", "ashen":
			if tall:
				var h = rng.randf_range(50, 110)
				ci.draw_rect(Rect2(p + Vector2(-9, -h), Vector2(18, h)), dk)
				ci.draw_rect(Rect2(p + Vector2(-13, -h - 6), Vector2(26, 6)), dk.lightened(0.1))
				if rng.randf() < 0.6: ci.draw_rect(Rect2(p + Vector2(-6, -h + 10), Vector2(12, 16)), Color(pal.acc.r, pal.acc.g, pal.acc.b, 0.55))
			else:
				var w = rng.randf_range(10, 24)
				ci.draw_rect(Rect2(p + Vector2(-w * 0.5, -w * 0.8), Vector2(w, w * 0.8)), dk.lightened(0.05))
				ci.draw_line(p + Vector2(-w * 0.5, -w * 0.4), p + Vector2(w * 0.5, -w * 0.4), dk.darkened(0.3), 1.0)
		"glass", "city", "heart", "mind":
			var n = 3 if tall else 2
			for i in n:
				var h = rng.randf_range(18, 46) * (2.2 if tall else 1.0)
				var ox = rng.randf_range(-12, 12)
				var lean = rng.randf_range(-10, 10)
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(ox - 6, 0), p + Vector2(ox + lean, -h), p + Vector2(ox + 7, 0)]), Color(pal.hi.r, pal.hi.g, pal.hi.b, 0.35))
				ci.draw_line(p + Vector2(ox + lean, -h), p + Vector2(ox + 2, 0), Color(1, 1, 1, 0.35), 1.0)
		"drowned":
			var pts = PackedVector2Array()
			var h = rng.randf_range(30, 90) * (1.5 if tall else 0.7)
			for i in 8: pts.append(p + Vector2(sin(i * 1.1 + rng.randf()) * 6, -h * i / 7.0))
			ci.draw_polyline(pts, Color(0.1, 0.5, 0.4, 0.7), 3.0)
		"cathedral":
			if tall:
				ci.draw_rect(Rect2(p + Vector2(-3, -120), Vector2(6, 120)), dk)
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(3, -116), p + Vector2(30, -110), p + Vector2(26, -60), p + Vector2(3, -66)]), Color(pal.acc2.r, pal.acc2.g, pal.acc2.b, 0.4))
			else:
				ci.draw_rect(Rect2(p + Vector2(-2, -14), Vector2(4, 14)), Color(0.9, 0.85, 0.7))
				ci.draw_circle(p + Vector2(0, -17), 2.5, pal.acc)
		_:
			var w = rng.randf_range(14, 30)
			ci.draw_rect(Rect2(p + Vector2(-w * 0.5, -(26.0 if tall else 12.0)), Vector2(w, 26.0 if tall else 12.0)), dk.lightened(0.06))
			ci.draw_rect(Rect2(p + Vector2(-w * 0.5 + 3, -(22.0 if tall else 9.0)), Vector2(w - 6, 4)), Color(pal.acc2.r, pal.acc2.g, pal.acc2.b, 0.6))

func _draw_dyn(ci):
	var v = _view()
	var x0 = max(0, int(v.position.x / T))
	var x1 = min(W - 1, int(v.end.x / T))
	for y in H:
		for x in range(x0, x1 + 1):
			var t = grid[y * W + x]
			if t < 4 or t == 5: continue
			var r = Rect2(x * T, y * T, T, T)
			match t:
				4:
					var top = tile(x, y - 1) != 4
					var off = (4.0 + sin(time * 2.0 + x) * 3.0) if top else 0.0
					ci.draw_rect(Rect2(r.position + Vector2(0, off), Vector2(T, T - off)), Color(pal.acc.r, pal.acc.g, pal.acc.b, 0.55))
					if top: ci.draw_rect(Rect2(r.position + Vector2(0, off), Vector2(T, 2)), Color(1, 1, 1, 0.7))
				6:
					var a = 0.35 + 0.2 * sin(time * 5.0 + y)
					ci.draw_rect(Rect2(r.position + Vector2(10, 0), Vector2(12, T)), Color(pal.acc2.r, pal.acc2.g, pal.acc2.b, a))
					ci.draw_line(r.position + Vector2(16, 0), r.position + Vector2(16 + sin(time * 20 + y) * 3, T), Color(1, 1, 1, 0.8), 1.5)
				7:
					var on = sight_t > 0
					ci.draw_rect(Rect2(r.position + Vector2(0, 0), Vector2(T, 10)), Color(pal.acc2.r, pal.acc2.g, pal.acc2.b, 0.7 if on else (0.08 if G.has("sight") else 0.0)), on)
				8:
					ci.draw_rect(r, pal.tile.lightened(0.15))
					for i in 3: ci.draw_line(r.position + Vector2(6 + i * 10, 0), r.position + Vector2(6 + i * 10, T), pal.acc.darkened(0.2), 3.0)
				9:
					for i in 2:
						var yy = fmod(time * 90.0 + i * 16 + x * 7, T)
						ci.draw_line(r.position + Vector2(8 + i * 14, T - yy), r.position + Vector2(8 + i * 14, T - yy - 8), Color(1, 1, 1, 0.25), 1.5)
				10:
					ci.draw_line(r.position + Vector2(16, 0), r.position + Vector2(16, T), Color(pal.acc.r, pal.acc.g, pal.acc.b, 0.12), 2.0)
				11:
					ci.draw_rect(Rect2(r.position + Vector2(8, 0), Vector2(16, T)), Color(pal.acc.r, pal.acc.g, pal.acc.b, 0.6 + 0.2 * sin(time * 8 + y)))
					ci.draw_line(r.position + Vector2(16, 0), r.position + Vector2(16, T), Color(1, 1, 1, 0.9), 2.0)
				12:
					ci.draw_rect(Rect2(r.position + Vector2(2, T - 8), Vector2(T - 4, 8)), pal.acc2)
					ci.draw_colored_polygon(PackedVector2Array([r.position + Vector2(8, T - 12), r.position + Vector2(16, T - 24 - sin(time * 4) * 4), r.position + Vector2(24, T - 12)]), Color(1, 1, 1, 0.7))
	for pl in platforms:
		ci.draw_rect(Rect2(pl.pos, Vector2(pl.w, 10)), pal.tile.lightened(0.15))
		ci.draw_rect(Rect2(pl.pos, Vector2(pl.w, 3)), pal.acc2)
		ci.draw_circle(pl.pos + Vector2(pl.w * 0.5, 14), 4.0, pal.acc)
	for c in crates:
		var r = Rect2(c.pos - c.half, c.half * 2)
		ci.draw_rect(r, pal.tile.lightened(0.2))
		ci.draw_rect(r, pal.acc2, false, 2.0)
		ci.draw_line(r.position, r.end, pal.acc2.darkened(0.3), 1.5)
	for th in things:
		if not v.has_point(th.pos): continue
		_draw_thing(ci, th)
	# hack progress
	if hack != null:
		var c = hack.th.pos + Vector2(0, -70)
		ci.draw_arc(c, 16, -PI / 2, -PI / 2 + TAU * hack.t / hack.need, 24, DB.C("ffb060"), 4.0)
		ci.draw_line(mote_pos, hack.th.pos + Vector2(0, -30), Color(1, 0.7, 0.4, 0.5 + 0.3 * sin(time * 30)), 1.5)
	# Mote, Sable's remote body
	if G.f("has_mote") != 0 or G.state.chapter >= 2:
		_draw_mote(ci)
	# zones (telegraphs)
	for z in zones:
		var k = clamp(z.t / max(0.01, z.warn), 0.0, 1.0)
		var live = z.t >= z.warn
		var col = Color(z.col.r, z.col.g, z.col.b, (0.12 + 0.25 * k * (0.6 + 0.4 * sin(time * 30.0))) if not live else 0.9)
		match z.shape:
			"rect":
				ci.draw_rect(Rect2(z.a, z.b), col)
				if not live: ci.draw_rect(Rect2(z.a, z.b), Color(z.col.r, z.col.g, z.col.b, 0.7), false, 1.5)
			"circle":
				ci.draw_circle(z.a, z.r * (k if not live else 1.0), col)
				ci.draw_arc(z.a, z.r, 0, TAU, 32, Color(z.col.r, z.col.g, z.col.b, 0.8), 1.5)
			"line":
				ci.draw_line(z.a, z.b, col, z.w if live else max(2.0, z.w * k))
				if live: ci.draw_line(z.a, z.b, Color(1, 1, 1, 0.9), z.w * 0.3)
	if chase_x > -9000:
		ci.draw_rect(Rect2(chase_x - 900, 0, 900, H * T), Color(pal.acc.r, pal.acc.g, pal.acc.b, 0.35))
		for i in 12:
			var yy = fmod(time * 300 + i * 97, H * T)
			ci.draw_line(Vector2(chase_x, yy), Vector2(chase_x - 60 - 40 * sin(i + time * 9), yy + 30), Color(1, 1, 1, 0.8), 3.0)

func _draw_mote(ci):
	var c = DB.C("ffb060")
	ci.draw_colored_polygon(PackedVector2Array([mote_pos + Vector2(-5, 0), mote_pos + Vector2(0, -5), mote_pos + Vector2(5, 0), mote_pos + Vector2(0, 5)]), c)
	ci.draw_arc(mote_pos, 8.0, time * 3.0, time * 3.0 + 4.0, 10, Color(1, 1, 1, 0.6), 1.2)

func _draw_thing(ci, th):
	var p = th.pos
	match th.kind:
		"shard":
			var b = sin(time * 4.0 + p.x) * 3.0
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, b), p + Vector2(0, -7 + b), p + Vector2(5, b), p + Vector2(0, 7 + b)]), pal.acc2)
		"health":
			if not th.gone:
				ci.draw_rect(Rect2(p + Vector2(-8, -3), Vector2(16, 6)), Color(0.4, 1, 0.6))
				ci.draw_rect(Rect2(p + Vector2(-3, -8), Vector2(6, 16)), Color(0.4, 1, 0.6))
		"secret":
			var b = sin(time * 2.0) * 4.0
			Art.ring(ci, p + Vector2(0, b - 8), 10 + sin(time * 5) * 2, Color(1, 0.9, 0.5), 2.0, 16)
			ci.draw_circle(p + Vector2(0, b - 8), 5, Color(1, 1, 1))
		"terminal", "node":
			var col = pal.acc2 if not th.done else Color(0.4, 0.9, 0.5)
			if th.kind == "node":
				for i in 3: Art.ring(ci, p + Vector2(0, -36), 10 + i * 7 + sin(time * 2 + i) * 2, Color(col.r, col.g, col.b, 0.7 - i * 0.2), 1.5, 5)
			else:
				ci.draw_rect(Rect2(p + Vector2(-12, -44), Vector2(24, 44)), pal.tile.lightened(0.1))
				ci.draw_rect(Rect2(p + Vector2(-9, -40), Vector2(18, 14)), Color(col.r, col.g, col.b, 0.7 + 0.2 * sin(time * 6)))
		"npc":
			ci.draw_set_transform(p, 0, Vector2(th.face, 1))
			var sp = DB.speaker(th.who)
			var st = {"body": Color(0.14, 0.15, 0.2).lerp(th.col, 0.12), "acc": th.col, "coat": th.seed % 2 == 0, "hood": th.seed % 3 == 0}
			if sp.port == "bot":
				Art.mech(ci, th.col, time, 0, 0, 0.6)
			elif sp.port == "archivist":
				st["robe"] = true
				Art.humanoid(ci, st, {"t": time})
			else: Art.humanoid(ci, st, {"t": time + th.seed % 10})
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"lore":
			ci.draw_rect(Rect2(p + Vector2(-8, -20), Vector2(16, 12)), Color(pal.acc.r, pal.acc.g, pal.acc.b, 0.5 + 0.3 * sin(time * 3)))
			ci.draw_line(p, p + Vector2(0, -8), pal.tile.lightened(0.2), 2.0)
		"door":
			ci.draw_rect(Rect2(p + Vector2(-20, -68), Vector2(40, 68)), Color(0, 0, 0, 0.85))
			ci.draw_rect(Rect2(p + Vector2(-20, -68), Vector2(40, 68)), pal.acc2, false, 2.0)
			ci.draw_rect(Rect2(p + Vector2(-14, -80), Vector2(28, 6)), pal.acc)
		"checkpoint":
			var lit = th.get("lit", false)
			ci.draw_line(p, p + Vector2(0, -56), pal.tile.lightened(0.25), 4.0)
			ci.draw_circle(p + Vector2(0, -60), 7 + (sin(time * 4) * 1.5 if lit else 0.0), pal.acc2 if lit else pal.acc2.darkened(0.6))
		"plate":
			ci.draw_rect(Rect2(p + Vector2(-22, -5 if not th.done else -2), Vector2(44, 5)), pal.acc if not th.done else Color(0.4, 0.9, 0.5))
		"switch":
			ci.draw_circle(p, 10, pal.tile.lightened(0.2))
			ci.draw_circle(p, 6, pal.acc if not th.done else Color(0.4, 0.9, 0.5))
		"station":
			ci.draw_rect(Rect2(p + Vector2(-26, -40), Vector2(52, 40)), pal.tile.lightened(0.12))
			ci.draw_rect(Rect2(p + Vector2(-22, -36), Vector2(44, 18)), Color(pal.acc.r, pal.acc.g, pal.acc.b, 0.5 + 0.15 * sin(time * 3 + p.x)))
			if th.spec == "sable": Art.ring(ci, p + Vector2(0, -64), 14 + sin(time * 2) * 2, DB.C("ffb060"), 2.0)
	if th == near_thing:
		Art.text_shadow(ci, p + Vector2(-150, -96), "[%s] %s" % [G.key_hint("interact"), th.inter], 15, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 300)

func _draw_fx(ci):
	for s in shots:
		var d = s.vel.normalized()
		match s.kind:
			"orb", "bomb":
				ci.draw_circle(s.pos, s.r, s.col)
				ci.draw_circle(s.pos, s.r * 0.5, Color(1, 1, 1))
			"wave":
				ci.draw_rect(Rect2(s.pos + Vector2(-8, -s.r * 2.5), Vector2(16, s.r * 2.5)), Color(s.col.r, s.col.g, s.col.b, 0.8))
			"flame":
				ci.draw_circle(s.pos, s.r * (1.5 - s.life), Color(s.col.r, s.col.g, s.col.b, 0.6))
			_:
				ci.draw_line(s.pos - d * 16.0, s.pos, s.col, s.r * 0.9)
				ci.draw_line(s.pos - d * 8.0, s.pos, Color(1, 1, 1), s.r * 0.45)
	for p in parts:
		var a = clamp(p.l / p.m, 0.0, 1.0)
		if p.has("txt"): Art.text_shadow(ci, p.p, p.txt, 15, Color(p.c.r, p.c.g, p.c.b, a))
		else: ci.draw_rect(Rect2(p.p - Vector2(p.s, p.s) * 0.5, Vector2(p.s, p.s)), Color(p.c.r, p.c.g, p.c.b, a))

func _draw_glow(ci):
	var v = _view()
	for l in lights:
		if v.has_point(l.p): Art.glow(ci, l.p, l.r * (0.92 + 0.08 * sin(time * 7.0 + l.f)), Color(l.c.r, l.c.g, l.c.b, 0.22))
	for s in shots: Art.glow(ci, s.pos, s.r * 5.0, Color(s.col.r, s.col.g, s.col.b, 0.5))
	for e in enemies:
		if not e.dead and v.has_point(e.pos): Art.glow(ci, e.pos + Vector2(0, -6), e.half.y * 1.6, Color(e.col.r, e.col.g, e.col.b, 0.16 + (0.5 if e.flash > 0 else 0.0)))
	for th in things:
		if th.kind in ["shard", "secret", "terminal", "node", "checkpoint", "station"] and v.has_point(th.pos):
			Art.glow(ci, th.pos + Vector2(0, -20), 46, Color(pal.acc2.r, pal.acc2.g, pal.acc2.b, 0.2))
	Art.glow(ci, mote_pos, 26, Color(1, 0.7, 0.4, 0.45))
	if player != null and not player.dead:
		Art.glow(ci, player.pos, 90, Color(player.blade_col.r, player.blade_col.g, player.blade_col.b, 0.08 + (0.3 if player.atk_t > 0 else 0.0)))
	for z in zones:
		if z.t >= z.warn:
			var c = z.a if z.shape != "rect" else z.a + z.b * 0.5
			Art.glow(ci, c, 160, Color(z.col.r, z.col.g, z.col.b, 0.5))
