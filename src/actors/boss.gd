extends "res://src/actors/enemy.gd"
# Boss — phase-driven encounters. Each boss cycles a per-phase list of attacks drawn from a shared,
# heavily telegraphed attack library. Attacks enqueue timed steps: q = [[delay, Callable], ...].

const PAT = {
	"hauler": [["slam", "lob"], ["slam", "charge", "lob"], ["charge", "rain", "slam", "lob"]],
	"nyx1": [["blink_slash", "fan"], ["blink_slash", "dash_line", "fan"], ["blink_slash", "blink_slash", "dash_line", "fan"]],
	"custodian": [["ring", "sweep_beam"], ["summon:mote", "sweep_beam", "ring"], ["rain", "sweep_beam", "ring", "summon:mote"]],
	"registrar": [["hbeam", "lob"], ["hbeam", "slam", "summon:trooper", "lob"], ["hbeam", "rain", "slam", "lob"]],
	"wyrm": [["dive", "breath"], ["dive", "tail", "breath"], ["dive", "dive", "rain", "breath"]],
	"vesper": [["homing", "litany"], ["blink_ring", "summon:acolyte", "litany", "homing"], ["cross", "litany", "blink_ring", "homing"]],
	"warden": [["cross", "homing"], ["vortex", "cross", "summon:jelly"], ["vortex", "cross", "lob", "cross"]],
	"chorus": [["converge", "walls"], ["lament", "converge", "walls"], ["lament", "converge", "walls", "ring"]],
	"bastion": [["artillery", "hbeam"], ["artillery", "summon:hunter", "hbeam", "slam"], ["artillery", "hbeam", "rain", "summon:trooper", "slam"]],
	"nyx2": [["blink_slash", "burst", "guard"], ["dash_line", "blink_slash", "guard", "fan"], ["blink_slash", "dash_line", "burst", "guard", "blink_slash"]],
	"malrek": [["flames", "leap"], ["emp", "flames", "leap", "rain"], ["emp", "summon:purifier", "leap", "flames", "rain"]],
	"sexton": [["homing", "erupt"], ["litany", "erupt", "summon:stalker"], ["homing", "litany", "erupt", "cross"]],
	"rook": [["combo3", "burst"], ["combo3", "artillery", "guard", "burst"], ["combo3", "artillery", "summon:hunter", "guard", "combo3", "burst"]],
	"echo": [["converge", "grid"], ["sunflare", "summon:shade", "grid", "converge"], ["sunflare", "grid", "lament", "converge", "walls"]],
	"sable": [["burst", "ring"], ["sweep_beam", "burst", "summon:mote"], ["cross", "sweep_beam", "burst", "ring"]],
	"orin": [["burst", "combo3"], ["burst", "combo3"], ["burst", "combo3", "leap"]],
}

var bcfg = {}
var q = []
var q_t = 0.0
var phase_n = 1
var atk_i = 0
var ax0 = 0.0
var ax1 = 0.0
var floor_y = 0.0
var mv_to = null
var mv_speed = 300.0
var pose = ""
var contact = false
var guard = false
var trail = []
var sm = 1.0
var shown = false

func init_boss(level, id, p):
	lv = level
	kind = id
	bcfg = DB.bosses[id]
	col = DB.C(bcfg.col)
	cfg = {"ai": "boss", "shape": bcfg.shape, "sh": 150, "big": true, "col": bcfg.col, "dmg": bcfg.get("dmg", 17), "spd": 150, "elite": true, "name": bcfg.name}
	max_hp = bcfg.hp * [0.7, 1.0, 1.25][int(G.settings.difficulty)]
	hp = max_hp
	half = Vector2(bcfg.size[0], bcfg.size[1])
	fly = bcfg.get("fly", false)
	is_boss = true
	floor_y = p.y
	pos = p - Vector2(0, half.y + (150 if fly else 0))
	home = pos
	ax0 = 64.0
	ax1 = lv.W * lv.T - 64.0
	z_index = 3
	position = pos
	contact = bcfg.shape in ["mech", "wyrm"]

func at(delay, fn): q.append([delay, fn])
func P(): return lv.player.pos
func cx(x): return clamp(x, ax0 + 40, ax1 - 40)

func tick(dt):
	time += dt
	flash = max(0.0, flash - dt)
	marked_t = max(0.0, marked_t - dt)
	if not alert:
		for a in lv.arenas:
			if pos.x > a.x0 * lv.T and pos.x < a.x1 * lv.T:
				ax0 = (a.x0 + 1) * lv.T + 16.0
				ax1 = a.x1 * lv.T - 16.0
		if P().x > ax0 + 30 and P().x < ax1 and abs(P().x - pos.x) < 760:
			alert = true
			Snd.sfx("roar")
			lv.shake(10)
			if G.main.hud != null: G.main.hud.boss_intro(bcfg.name, bcfg.sub)
			at(1.6, func(): pass)
		_post()
		return
	if lv.player.dead:
		_post()
		return
	var frac = hp / max_hp
	var want = 1 if frac > 0.66 else (2 if frac > 0.33 else 3)
	if want != phase_n:
		phase_n = want
		q.clear()
		q_t = 0.0
		atk_i = 0
		guard = false
		intangible = false
		pose = ""
		lv.shake(12)
		lv.stop(8)
		lv.burst(pos, col, 30, 360, 0.8)
		Snd.sfx("roar", -2, 1.2)
		at(1.0, func(): pass)
	sm = 1.0 + 0.12 * (phase_n - 1)
	if susp_t > 0:
		susp_t -= dt
	else:
		if q.is_empty(): _choose()
		q_t += dt * sm
		while not q.is_empty() and q_t >= q[0][0]:
			q_t -= q[0][0]
			var s = q.pop_front()
			s[1].call()
			if dead: return
	# movement
	if fly:
		if mv_to != null:
			pos = pos.move_toward(mv_to, mv_speed * dt)
			if pos.distance_to(mv_to) < 2: mv_to = null
		else: pos += Vector2(sin(time * 1.1) * 14, cos(time * 1.6) * 10) * dt
		if bcfg.shape == "wyrm":
			trail.push_front(pos)
			if trail.size() > 70: trail.pop_back()
	else:
		if mv_to != null:
			var dx = mv_to.x - pos.x
			if abs(dx) < 8:
				mv_to = null
				vel.x = 0
			else:
				vel.x = sign(dx) * mv_speed
				facing = int(sign(dx))
				anim += mv_speed * dt * 0.05
		else: vel.x = move_toward(vel.x, 0, 2400 * dt)
		vel.y = min(vel.y + 1700.0 * dt, 900.0)
		lv.move_box(self, dt)
	if contact and not intangible and cd <= 0:
		if _contact(): cd = 0.8
	cd = max(0.0, cd - dt)
	_post()

func _choose():
	var list = PAT[kind][phase_n - 1]
	var a = list[atk_i % list.size()]
	atk_i += 1
	pose = ""
	if a.begins_with("summon:"): a_summon(a.substr(7))
	else: call("a_" + a)
	at(0.5 / sm + 0.25, func(): pose = "")

func face_p(): facing = 1 if P().x > pos.x else -1

func _shot(dir, speed = 480.0, extra = {}):
	var s = {"pos": pos, "vel": dir * speed, "team": 1, "dmg": cfg.dmg * 0.7, "col": col, "r": 6.0}
	s.merge(extra, true)
	lv.shoot(s)

func slash(reach = 80.0, h = 80.0):
	pose = "slash"
	Snd.sfx("slash2", -4)
	var r = Rect2(pos + Vector2(0 if facing > 0 else -reach, -h * 0.5), Vector2(reach, h))
	if r.intersects(lv.player_rect()): lv.hurt_player(cfg.dmg, pos, "melee", self)

func parried():
	q.clear()
	q_t = 0.0
	pose = "stagger"
	guard = false
	mv_to = null
	lv.popup(pos + Vector2(-20, -half.y - 20), "OPEN", Color(1, 1, 1))
	at(1.4, func(): pose = "")

# ---------------------------------------------------------------- attack library
func a_slam():
	mv_speed = 170.0
	mv_to = Vector2(cx(P().x - sign(P().x - pos.x) * 70), pos.y)
	at(0.9, func():
		mv_to = null
		face_p()
		pose = "windup"
		lv.zone({"shape": "rect", "a": Vector2(pos.x + (0 if facing > 0 else -150), floor_y - 110), "b": Vector2(150, 110), "warn": 0.65 / sm, "live": 0.2, "dmg": cfg.dmg}))
	at(0.65, func():
		pose = "slash"
		for s in [-1, 1]: lv.shoot({"pos": Vector2(pos.x + facing * 80, floor_y - 2), "vel": Vector2(s * 380, 0), "team": 1, "dmg": cfg.dmg * 0.6, "col": col, "kind": "wave", "r": 10.0, "life": 1.2}))

func a_lob():
	face_p()
	pose = "aim"
	for i in 2 + phase_n:
		at(0.35, func():
			var dx = P().x - pos.x + randf_range(-60, 60)
			lv.shoot({"pos": pos + Vector2(0, -half.y), "vel": Vector2(dx * 0.9, -520), "team": 1, "dmg": cfg.dmg * 0.8, "col": col, "kind": "bomb", "grav": 950.0, "r": 8.0, "life": 4.0})
			Snd.sfx("eshoot", -6, 0.6))

func a_charge():
	face_p()
	pose = "windup"
	lv.zone({"shape": "rect", "a": Vector2(ax0, floor_y - 70), "b": Vector2(ax1 - ax0, 70), "warn": 0.9 / sm, "live": 0.05, "dmg": 0, "col": col, "sfx": ""})
	at(0.9, func():
		pose = "charge"
		mv_speed = 700.0
		mv_to = Vector2(ax1 - half.x - 8 if facing > 0 else ax0 + half.x + 8, pos.y)
		contact = true)
	at(1.3, func():
		lv.shake(12)
		Snd.sfx("boom")
		pose = "stagger"
		contact = bcfg.shape in ["mech", "wyrm"])
	at(1.2, func(): pose = "")

func a_rain():
	pose = "cast"
	for i in 5 + phase_n * 2:
		at(0.22, func():
			var x = randf_range(ax0, ax1 - 60) if randf() < 0.5 else P().x - 30
			lv.zone({"shape": "rect", "a": Vector2(x, floor_y - 600), "b": Vector2(60, 600), "warn": 0.8, "live": 0.2, "dmg": cfg.dmg * 0.8, "col": col}))

func a_ring():
	pose = "cast"
	at(0.5, func():
		var n = 10 + phase_n * 3
		var off = randf() * TAU
		for i in n: _shot(Vector2.from_angle(off + i * TAU / n), 260.0, {"kind": "orb", "life": 4.0})
		Snd.sfx("signal", -4, 1.4))
	at(0.6, func(): pass)

func a_fan():
	face_p()
	pose = "aim"
	at(0.4, func():
		var d = (P() - pos).normalized()
		for i in range(-phase_n, phase_n + 1): _shot(d.rotated(i * 0.16), 620.0)
		Snd.sfx("eshoot", -4))
	at(0.3, func(): pass)

func a_burst():
	face_p()
	pose = "aim"
	at(0.35, func(): pass)
	for i in 3 + phase_n:
		at(0.13, func():
			face_p()
			_shot((P() + lv.player.vel * 0.15 - pos).normalized(), 720.0)
			Snd.sfx("eshoot", -6))
	at(0.3, func(): pass)

func a_blink_slash():
	pose = "windup"
	intangible = true
	lv.burst(pos, col, 14, 200)
	Snd.sfx("tele", -4)
	at(0.35, func():
		var side = -lv.player.facing
		pos = Vector2(cx(P().x + side * 70), floor_y - half.y - 1)
		vel = Vector2.ZERO
		facing = -side
		intangible = false
		lv.burst(pos, col, 14, 200))
	at(0.3 / sm, func(): slash(84.0))
	at(0.3, func(): pass)

func a_dash_line():
	face_p()
	pose = "windup"
	var y = floor_y - 34
	lv.zone({"shape": "line", "a": Vector2(ax0, y), "b": Vector2(ax1, y), "w": 56.0, "warn": 0.7 / sm, "live": 0.15, "dmg": cfg.dmg, "col": col, "sfx": "slash2"})
	at(0.7, func():
		pose = "slash"
		pos.x = ax1 - 40 if facing > 0 else ax0 + 40
		lv.burst(pos, col, 20, 300))
	at(0.5, func(): pass)

func a_sweep_beam():
	mv_speed = 260.0
	mv_to = Vector2((ax0 + ax1) * 0.5, floor_y - 300)
	pose = "cast"
	var dirn = 1 if randf() < 0.5 else -1
	for i in 9:
		at(0.28 if i > 0 else 1.0, func():
			var ang = PI * 0.5 + dirn * (i - 4) * 0.26
			lv.zone({"shape": "line", "a": pos, "b": pos + Vector2.from_angle(ang) * 900, "w": 26.0, "warn": 0.55, "live": 0.18, "dmg": cfg.dmg * 0.8, "col": col, "sfx": "tele"}))
	at(0.9, func(): pass)

func a_summon(k):
	pose = "cast"
	if lv.alive_enemies() > 4: return
	at(0.6, func():
		for i in (2 if k in ["mote", "acolyte", "jelly"] else 1) + (1 if phase_n == 3 and k == "mote" else 0):
			var p = Vector2(randf_range(ax0 + 60, ax1 - 60), floor_y)
			var e = lv.spawn_enemy(k, p)
			e.alert = true
			lv.burst(e.pos, e.col, 14, 200)
		Snd.sfx("tele", -4, 0.7))
	at(0.8, func(): pass)

func a_hbeam():
	pose = "aim"
	var seq = [0, 1, 0] if phase_n < 3 else [0, 1, 1, 0]
	for i in seq.size():
		at(0.75 if i > 0 else 0.3, func():
			var y = floor_y - (14 if seq[i] == 0 else 62)
			lv.zone({"shape": "line", "a": Vector2(ax0, y), "b": Vector2(ax1, y), "w": 22.0, "warn": 0.7 / sm, "live": 0.2, "dmg": cfg.dmg * 0.8, "col": col, "sfx": "rail"}))
	at(1.0, func(): pass)

func a_dive():
	var tx = cx(P().x)
	mv_speed = 520.0
	mv_to = Vector2(tx, floor_y - 330)
	at(0.7, func():
		tx = cx(P().x + lv.player.vel.x * 0.3)
		lv.zone({"shape": "circle", "a": Vector2(tx, floor_y), "r": 100.0, "warn": 0.7 / sm, "live": 0.25, "dmg": cfg.dmg, "col": col})
		mv_to = Vector2(tx, floor_y - 40)
		mv_speed = 420.0)
	at(0.9, func():
		lv.shake(8)
		mv_speed = 300.0
		mv_to = Vector2(cx(pos.x + (260 if randf() < 0.5 else -260)), floor_y - 260))
	at(0.7, func(): pass)

func a_breath():
	face_p()
	pose = "aim"
	at(0.5, func(): pass)
	for i in 6 + phase_n * 2:
		at(0.09, func():
			var d = (P() - pos).normalized()
			_shot(d.rotated(randf_range(-0.25, 0.25)), randf_range(380, 520), {"r": 5.0}))
	at(0.5, func(): pass)

func a_tail():
	pose = "windup"
	var y = floor_y - 24
	lv.zone({"shape": "line", "a": Vector2(pos.x - 420, y), "b": Vector2(pos.x + 420, y), "w": 40.0, "warn": 0.8 / sm, "live": 0.2, "dmg": cfg.dmg, "col": col})
	at(1.1, func(): pass)

func a_homing():
	pose = "cast"
	for i in 3 + phase_n:
		at(0.3, func():
			_shot(Vector2.from_angle(randf_range(-PI, 0)), 240.0, {"kind": "orb", "homing": 2.4, "life": 4.0, "r": 7.0})
			Snd.sfx("signal", -10, 1.6))
	at(0.6, func(): pass)

func a_litany():
	pose = "cast"
	var n = int((ax1 - ax0) / 90.0)
	var gap = randi() % max(1, n)
	var rev = randf() < 0.5
	for i in n:
		var k = (n - 1 - i) if rev else i
		at(0.11, func():
			if abs(k - gap) > 0 or phase_n == 3 and k % 5 == 0 and k != gap:
				lv.zone({"shape": "rect", "a": Vector2(ax0 + k * 90, floor_y - 640), "b": Vector2(84, 640), "warn": 0.9, "live": 0.2, "dmg": cfg.dmg * 0.8, "col": col, "sfx": "" if i % 3 else "boom"}))
	at(1.3, func(): pass)

func a_blink_ring():
	intangible = true
	lv.burst(pos, col, 14, 200)
	Snd.sfx("tele", -4)
	at(0.4, func():
		pos = Vector2(randf_range(ax0 + 100, ax1 - 100), floor_y - randf_range(160, 280))
		intangible = false
		lv.burst(pos, col, 14, 200))
	a_ring()

func a_cross():
	pose = "cast"
	mv_speed = 300.0
	mv_to = Vector2(cx(P().x), floor_y - 220)
	for j in 2 + (1 if phase_n == 3 else 0):
		at(0.8, func():
			mv_to = null
			for i in 4:
				var ang = i * PI * 0.5 + (PI * 0.25 if j % 2 == 1 else 0.0)
				lv.zone({"shape": "line", "a": pos, "b": pos + Vector2.from_angle(ang) * 1000, "w": 30.0, "warn": 0.7 / sm, "live": 0.25, "dmg": cfg.dmg * 0.9, "col": col, "sfx": "rail" if i == 0 else ""}))
	at(1.0, func(): pass)

func a_vortex():
	pose = "cast"
	mv_speed = 200.0
	mv_to = Vector2((ax0 + ax1) * 0.5, floor_y - 150)
	at(0.8, func():
		lv.zone({"shape": "circle", "a": pos, "r": 300.0, "warn": 1.3 / sm, "live": 0.3, "dmg": cfg.dmg * 1.3, "col": col}))
	at(1.7, func(): pass)

func a_converge():
	pose = "cast"
	at(0.4, func():
		var c = P()
		var n = 8 + phase_n * 2
		for i in n:
			var a = i * TAU / n
			lv.shoot({"pos": c + Vector2.from_angle(a) * 380, "vel": -Vector2.from_angle(a) * 230, "team": 1, "dmg": cfg.dmg * 0.6, "col": col, "kind": "wave" if false else "orb", "r": 7.0, "life": 1.9})
		Snd.sfx("signal", -4))
	at(1.6, func(): pass)

func a_walls():
	pose = "cast"
	var dirn = 1 if randf() < 0.5 else -1
	var n = int((ax1 - ax0) / 140.0)
	for i in n:
		var k = i if dirn > 0 else n - 1 - i
		at(0.32, func(): lv.zone({"shape": "rect", "a": Vector2(ax0 + k * 140, floor_y - 640), "b": Vector2(70, 640 - (70 if k % 2 == 0 else 0)), "warn": 0.6, "live": 0.15, "dmg": cfg.dmg * 0.8, "col": col, "sfx": "tele"}))
	at(0.8, func(): pass)

func a_lament():
	pose = "cast"
	for i in 3 + phase_n:
		at(0.55, func(): lv.zone({"shape": "circle", "a": P() + lv.player.vel * 0.2, "r": 95.0, "warn": 0.75 / sm, "live": 0.2, "dmg": cfg.dmg, "col": col}))
	at(0.9, func(): pass)

func a_artillery():
	pose = "aim"
	for i in 3 + phase_n:
		at(0.45, func():
			var x = cx(P().x + lv.player.vel.x * 0.4 + randf_range(-80, 80))
			lv.zone({"shape": "circle", "a": Vector2(x, floor_y), "r": 90.0, "warn": 1.0, "live": 0.2, "dmg": cfg.dmg, "col": Color(1, 0.5, 0.2)}))
	at(0.8, func(): pass)

func a_combo3():
	mv_speed = 330.0 * sm
	mv_to = Vector2(cx(P().x - sign(P().x - pos.x) * 60), pos.y)
	at(0.7, func(): mv_to = null)
	for i in 3:
		at(0.36 / sm, func():
			face_p()
			pose = "windup"
			vel.x = facing * 260)
		at(0.3 / sm, func(): slash(88.0))
	at(0.5, func(): pass)

func a_guard():
	face_p()
	pose = "guard"
	guard = true
	at(1.3, func():
		guard = false
		pose = "")

func a_emp():
	pose = "cast"
	lv.zone({"shape": "circle", "a": pos, "r": 340.0, "warn": 1.0 / sm, "live": 0.2, "dmg": 6, "col": Color(0.6, 0.8, 1.0), "sfx": "tele"})
	at(1.05, func():
		if P().distance_to(pos) < 350 and lv.player.inv_t <= 0.7:
			lv.player.emp_t = 5.0
			lv.player.en = 0
			G.toast.emit("Systems suppressed — blade only"))
	at(0.5, func(): pass)

func a_flames():
	face_p()
	pose = "aim"
	mv_speed = 120.0
	mv_to = Vector2(cx(P().x), pos.y)
	at(0.5, func(): pass)
	for i in 16:
		at(0.06, func():
			face_p()
			lv.shoot({"pos": pos + Vector2(facing * 24, -8), "vel": Vector2(facing * randf_range(340, 480), randf_range(-70, 30)), "team": 1, "dmg": cfg.dmg * 0.5, "col": Color(1, 0.5, 0.15), "kind": "flame", "r": 12.0, "life": 0.55}))
	at(0.4, func(): mv_to = null)

func a_leap():
	face_p()
	pose = "windup"
	at(0.4, func():
		var tx = cx(P().x)
		vel = Vector2(0, -760)
		mv_speed = max(260.0, abs(tx - pos.x) / 0.85)
		mv_to = Vector2(tx, pos.y)
		lv.zone({"shape": "circle", "a": Vector2(tx, floor_y), "r": 110.0, "warn": 0.85, "live": 0.2, "dmg": cfg.dmg, "col": col}))
	at(0.9, func():
		pose = "slash"
		for s in [-1, 1]: lv.shoot({"pos": Vector2(pos.x, floor_y - 2), "vel": Vector2(s * 400, 0), "team": 1, "dmg": cfg.dmg * 0.6, "col": col, "kind": "wave", "r": 10.0, "life": 1.0}))
	at(0.5, func(): pass)

func a_erupt():
	pose = "cast"
	var x = P().x
	var dirn = 1 if randf() < 0.5 else -1
	for i in 6:
		at(0.2, func(): lv.zone({"shape": "circle", "a": Vector2(cx(x + dirn * (i - 2) * 110), floor_y), "r": 62.0, "warn": 0.7, "live": 0.2, "dmg": cfg.dmg * 0.8, "col": col}))
	at(0.9, func(): pass)

func a_sunflare():
	pose = "cast"
	mv_speed = 300.0
	mv_to = Vector2((ax0 + ax1) * 0.5, floor_y - 240)
	at(0.9, func():
		var c = Vector2((ax0 + ax1) * 0.5, floor_y - 100)
		lv.zone({"shape": "circle", "a": c, "r": (ax1 - ax0) * 0.5 - 110, "warn": 1.6 / sm, "live": 0.3, "dmg": cfg.dmg * 1.4, "col": Color(1, 0.8, 0.5)}))
	at(2.2, func(): pass)

func a_grid():
	pose = "cast"
	for j in 2 + phase_n:
		at(0.75, func():
			var n = int((ax1 - ax0) / 110.0)
			for k in n:
				if (k + j) % 2 == 0: lv.zone({"shape": "rect", "a": Vector2(ax0 + k * 110, floor_y - 640), "b": Vector2(104, 640), "warn": 0.7, "live": 0.15, "dmg": cfg.dmg * 0.8, "col": col, "sfx": "tele" if k < 2 else ""}))
	at(1.0, func(): pass)

# ---------------------------------------------------------------- damage / death
func take_hit(amount, kb, kind_, from_x):
	if dead or not alert: return false
	if guard and kind_ in ["blade", "gun"] and sign(from_x - pos.x) == facing:
		lv.spark(pos + Vector2(facing * 16, 0), Color(1, 1, 1), Vector2(facing, -0.4), 8)
		Snd.sfx("parry", -6, 0.8)
		guard = false
		q.clear()
		q_t = 0.0
		at(0.18, func(): slash(96.0))
		at(0.5, func(): pose = "")
		return false
	if pose == "stagger": amount *= 1.5
	if marked_t > 0: amount *= 1.2
	if kind_ == "grav": amount *= 2.0
	hp -= amount
	flash = 0.1
	lv.spark(pos, col, Vector2(sign(kb.x + 0.01), -0.4), 5)
	if amount >= 1: lv.popup(pos + Vector2(randf_range(-20, 20), -half.y - 8), str(int(amount)), Color(1, 1, 1))
	if hp <= 0: die()
	return true

func die(_silent = false):
	if dead: return
	dead = true
	gone = true
	q.clear()
	lv.stop(20)
	lv.shake(18)
	for i in 5: lv.burst(pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)), col, 26, 420, 1.2)
	Snd.sfx("boom")
	Snd.sfx("roar", -4, 0.7)
	G.state.shards += 150
	for e in lv.enemies:
		if e != self and not e.dead: e.die(true)
	lv.shots.clear()
	lv.zones.clear()
	lv.boss_dead(self)
	visible = false
	queue_free()

# ---------------------------------------------------------------- drawing
func _draw():
	var c = col if flash <= 0 else Color(1, 1, 1)
	modulate.a = 0.2 if intangible else 1.0
	match bcfg.shape:
		"human":
			var stl = {"body": Color(0.2, 0.2, 0.26).lerp(c, 0.15) if flash <= 0 else Color(0.85, 0.85, 0.85), "acc": c, "coat": true, "s": 1.25, "blade_len": 46.0, "robe": kind in ["vesper", "malrek"], "hair": Color(0.8, 0.8, 0.85) if kind.begins_with("nyx") else Color(0.3, 0.3, 0.33)}
			var p = {"t": time, "phase": anim, "move": clamp(abs(vel.x) / 200.0, 0, 1) if on_ground else 0.0, "air": 0.0 if (on_ground or fly) else 1.0, "blade": kind != "vesper", "arm": 0.6, "blade_ang": -0.8}
			match pose:
				"windup":
					p["arm"] = -2.3
					p["blade_ang"] = -2.7
				"slash":
					p["arm"] = 0.5
					p["blade_ang"] = 0.3
					draw_arc(Vector2(8, -42), 60, -2.2, 0.7, 12, Color(c.r, c.g, c.b, 0.6), 12.0)
				"aim":
					p["arm"] = 0.0
					p["gun"] = true
					p["blade"] = false
				"cast":
					p["arm"] = -1.9
					p["blade"] = false
				"guard":
					p["arm"] = -0.6
					p["blade_ang"] = -1.6
					Art.ring(self, Vector2(0, -36), 44 + sin(time * 14) * 2, Color(1, 1, 1, 0.8), 2.0, 24)
				"stagger": p["lean"] = -0.6
			Art.humanoid(self, stl, p)
			if kind == "vesper":
				for i in 10: draw_circle(Vector2(0, -74) + Vector2.from_angle(time * 0.6 + i * TAU / 10) * 24, 2.0, c)
		"mech":
			var s = half.y / 30.0
			Art.mech(self, c, time, anim, 1.0 if mv_to != null else 0.0, s, 1.0 if pose == "slash" else (0.6 if pose == "windup" else 0.0))
			if pose == "stagger": Art.text(self, Vector2(-20, -half.y * 2 - 20), "* * *", 20, Color(1, 1, 0.5))
		"construct":
			draw_set_transform(Vector2(0, -half.y + 46), 0, Vector2.ONE)
			Art.construct(self, c, time * (1.0 + phase_n * 0.5), 2.4, 3 + phase_n)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"wyrm":
			for i in range(trail.size() - 1, 0, -6):
				var r = (26 - i * 0.28)
				var lp = (trail[i] - pos) * Vector2(facing, 1) + Vector2(0, -half.y)
				Art.ell(self, lp, r, r * 0.8, Color(0.08, 0.12, 0.14))
				draw_colored_polygon(PackedVector2Array([lp + Vector2(-6, -r * 0.7), lp + Vector2(6, -r * 0.7), lp + Vector2(0, -r * 1.5)]), Color(c.r, c.g, c.b, 0.8))
			var hc = Vector2(0, -half.y)
			Art.ell(self, hc, 34, 24, Color(0.1, 0.15, 0.18))
			draw_colored_polygon(PackedVector2Array([hc + Vector2(20, -6), hc + Vector2(52, 4), hc + Vector2(20, 14)]), Color(0.1, 0.15, 0.18))
			draw_circle(hc + Vector2(16, -6), 5, c)
			for i in 4: draw_colored_polygon(PackedVector2Array([hc + Vector2(-20 + i * 10, -18), hc + Vector2(-12 + i * 10, -18), hc + Vector2(-20 + i * 10, -40)]), c)
		"chorus", "echo":
			var hc = Vector2(0, -half.y)
			var n = 9 if bcfg.shape == "chorus" else 16
			var R = half.x * (0.9 if bcfg.shape == "chorus" else 1.2)
			for i in n:
				var a = time * (0.5 if i % 2 == 0 else -0.35) + i * TAU / n
				var o = hc + Vector2(cos(a) * R, sin(a * 1.0) * R * 0.8)
				draw_arc(o, 12, 0, TAU, 14, Color(c.r, c.g, c.b, 0.55), 2.0)
				draw_line(o + Vector2(-5, -2), o + Vector2(-2, -2), Color(1, 1, 1, 0.7), 1.5)
				draw_line(o + Vector2(2, -2), o + Vector2(5, -2), Color(1, 1, 1, 0.7), 1.5)
				draw_line(hc, o, Color(c.r, c.g, c.b, 0.15), 1.0)
			Art.ring(self, hc, R * 0.45 + sin(time * 3) * 3, Color(1, 1, 1, 0.9), 3.0)
			if bcfg.shape == "echo":
				for k in 3: Art.ring(self, hc, R * (1.5 + k * 0.4) + sin(time + k) * 6, Color(c.r, c.g, c.b, 0.3 - k * 0.08), 2.0, 48)
			draw_circle(hc, 9 + phase_n * 2, c)
	if marked_t > 0: Art.ring(self, Vector2(0, -half.y), half.y + 14, DB.C("ffb060", 0.7), 2.0, 6)
