extends Node2D
# Enemy — data-driven archetypes (DB.enemies) on top of a shared state machine:
# idle/patrol -> alert -> chase -> windup (telegraph) -> attack -> recover, plus stagger, suspend, retreat and death.

const Art = preload("res://src/core/art.gd")

var lv
var kind = ""
var cfg = {}
var pos = Vector2.ZERO
var vel = Vector2.ZERO
var half = Vector2(12, 26)
var on_ground = false
var hit_wall = 0
var hit_ceil = false
var riding = null
var drop = false
var phase = false
var hp = 10.0
var max_hp = 10.0
var col = Color.WHITE
var facing = -1
var state = "idle"
var st = 0.0
var alert = false
var dead = false
var gone = false
var intangible = false
var is_boss = false
var ally = false
var ally_t = 0.0
var flash = 0.0
var marked_t = 0.0
var susp_t = 0.0
var stun_t = 0.0
var cd = 0.0
var home = Vector2.ZERO
var anim = 0.0
var time = 0.0
var fly = false
var burst_left = 0
var aim = Vector2.LEFT
var hit_done = false

func init(level, k, p):
	lv = level
	kind = k
	cfg = DB.enemies[k]
	col = DB.C(cfg.col)
	max_hp = cfg.hp * [0.8, 1.0, 1.25][int(G.settings.difficulty)]
	hp = max_hp
	fly = cfg.get("fly", false)
	if cfg.get("big", false): half = Vector2(20, 30)
	match cfg.shape:
		"drone": half = Vector2(15, 10) if not cfg.get("big", false) else Vector2(22, 14)
		"wisp": half = Vector2(8, 8)
		"beast": half = Vector2(18, 13) if not cfg.get("big", false) else Vector2(24, 17)
		"jelly": half = Vector2(14, 14)
		"turret": half = Vector2(14, 14)
		"construct": half = Vector2(16, 20) if not cfg.get("big", false) else Vector2(22, 24)
		"mech": half = Vector2(22, 34)
	pos = p - Vector2(0, half.y + (60 if fly else 0))
	home = pos
	cd = randf_range(0.3, 1.2)
	z_index = 3
	position = pos

func dmg(): return cfg.dmg * [0.8, 1.0, 1.2][int(G.settings.difficulty)]

func _target():
	if not ally: return lv.player.pos
	var best = null
	for e in lv.enemies:
		if e != self and not e.dead and not e.ally and (best == null or e.pos.distance_to(pos) < best.distance_to(pos)): best = e.pos
	return best if best != null else pos + Vector2(facing * 100, 0)

func tick(dt):
	time += dt
	flash = max(0.0, flash - dt)
	marked_t = max(0.0, marked_t - dt)
	cd = max(0.0, cd - dt)
	st += dt
	if ally:
		ally_t += dt
		if ally_t > 16.0:
			die()
			return
	if susp_t > 0:
		susp_t -= dt
		vel = Vector2(0, -25)
		lv.move_box(self, dt)
		_post()
		return
	if stun_t > 0:
		stun_t -= dt
		if not fly: vel.y += 1500.0 * lv.grav_mult * dt
		else: vel = vel.lerp(Vector2.ZERO, dt * 4.0)
		if on_ground: vel.x = move_toward(vel.x, 0, 1200 * dt)
		lv.move_box(self, dt)
		_post()
		return
	var tp = _target()
	var d = tp - pos
	if not alert and not lv.player.dead:
		var rngd = 460.0 if marked_t <= 0 else 700.0
		if d.length() < rngd and abs(d.y) < 260 and lv.los(pos, tp):
			alert = true
			lv.popup(pos + Vector2(-3, -half.y - 14), "!", col)
	if lv.player.dead and not ally: alert = false
	if not alert: _idle(dt)
	else: call("_ai_" + cfg.ai, dt, d)
	if not fly:
		vel.y += 1500.0 * lv.grav_mult * dt
		vel.y = min(vel.y, 900.0)
	lv.move_box(self, dt)
	_post()

func _post():
	if pos.y > lv.H * lv.T + 120:
		die(true)
		return
	position = pos + Vector2(0, half.y)
	scale.x = facing
	queue_redraw()

func _go(s):
	state = s
	st = 0.0
	hit_done = false

func _ledge():
	var tx = int((pos.x + facing * (half.x + 6)) / lv.T)
	var ty = int((pos.y + half.y + 6) / lv.T)
	return not lv.solid_at(tx, ty) and lv.tile(tx, ty) != 2

func _idle(dt):
	if fly:
		vel = vel.lerp(Vector2(sin(time * 0.8 + home.x) * 40.0, cos(time * 1.1) * 14.0), dt * 2.0)
		if abs(vel.x) > 5: facing = int(sign(vel.x))
		return
	if cfg.ai in ["turret", "sniper", "caster"]:
		vel.x = 0
		return
	if on_ground and (hit_wall != 0 or _ledge() or abs(pos.x - home.x) > 150):
		if abs(pos.x - home.x) > 150: facing = int(sign(home.x - pos.x))
		else: facing = -facing
	vel.x = facing * cfg.spd * 0.35
	anim += abs(vel.x) * dt * 0.06

func _walk(dt, dirx, speed):
	facing = int(dirx) if dirx != 0 else facing
	if on_ground and _ledge() and not fly: vel.x = 0
	else: vel.x = move_toward(vel.x, dirx * speed, 1400 * dt)
	anim += abs(vel.x) * dt * 0.06

func _melee(reach = 50.0, h = 56.0, kb = 0):
	if hit_done: return
	var r = Rect2(pos + Vector2(0 if facing > 0 else -reach, -h * 0.5), Vector2(reach, h))
	if ally:
		if lv.hit_enemies(r, dmg(), Vector2(facing * 200, -100), "boom") > 0: hit_done = true
	elif r.intersects(lv.player_rect()):
		hit_done = true
		lv.hurt_player(dmg(), pos, "melee", self)

func _fire(dir, speed = 520.0, extra = {}):
	var s = {"pos": pos + Vector2(facing * half.x, -4) if cfg.shape == "human" else pos, "vel": dir * speed, "team": 0 if ally else 1, "dmg": dmg(), "col": col}
	s.merge(extra, true)
	lv.shoot(s)
	Snd.sfx("eshoot", -10)

func _contact():
	if not ally and Rect2(pos - half, half * 2).intersects(lv.player_rect()):
		return lv.hurt_player(dmg(), pos, "melee", self) == "hit"
	return false

func parried():
	stun_t = 1.3
	vel = Vector2(-facing * 200, -120)
	_go("chase")
	lv.popup(pos + Vector2(-20, -half.y - 16), "OPEN", Color(1, 1, 1))

func suspend(t):
	if is_boss or cfg.get("big", false): t *= 0.4
	susp_t = t
	_go("chase")

# ---------------------------------------------------------------- behaviours
func _ai_grunt(dt, d):
	match state:
		"windup":
			vel.x = move_toward(vel.x, 0, 1500 * dt)
			if st > 0.38:
				_go("attack")
				vel.x = facing * 220
				Snd.sfx("slash", -10, 0.8)
		"attack":
			_melee()
			if st > 0.16: _go("recover")
		"recover":
			vel.x = move_toward(vel.x, 0, 1500 * dt)
			if st > 0.45:
				_go("chase")
				cd = 0.5
		_:
			if abs(d.x) < 48 and abs(d.y) < 56 and cd <= 0:
				facing = int(sign(d.x)) if d.x != 0 else facing
				_go("windup")
			else: _walk(dt, sign(d.x) if abs(d.x) > 30 else 0.0, cfg.spd)

func _ai_shield(dt, d): _ai_grunt(dt, d)

func _ai_gunner(dt, d):
	var rngv = cfg.get("rng", 420)
	match state:
		"windup":
			vel.x = move_toward(vel.x, 0, 1500 * dt)
			facing = int(sign(d.x)) if d.x != 0 else facing
			aim = d.normalized()
			if st > 0.45:
				burst_left = cfg.get("burst", 1)
				_go("attack")
		"attack":
			if st > 0.12:
				st = 0.0
				_fire(aim.rotated(randf_range(-0.05, 0.05)))
				burst_left -= 1
				if burst_left <= 0:
					_go("chase")
					cd = 1.5
		_:
			var dist = d.length()
			if dist < 170: _walk(dt, -sign(d.x), cfg.spd)
			elif dist > rngv: _walk(dt, sign(d.x), cfg.spd)
			else:
				vel.x = move_toward(vel.x, 0, 1200 * dt)
				facing = int(sign(d.x)) if d.x != 0 else facing
				if cd <= 0 and lv.los(pos, pos + d): _go("windup")

func _ai_sniper(dt, d):
	match state:
		"windup":
			vel.x = 0
			facing = int(sign(d.x)) if d.x != 0 else facing
			if st < 0.9: aim = d.normalized()
			if st > 1.15:
				_fire(aim, 1500.0, {"r": 6.0})
				Snd.sfx("rail", -8)
				_go("chase")
				cd = 2.4
		_:
			if d.length() < 200: _walk(dt, -sign(d.x), cfg.spd)
			else:
				vel.x = move_toward(vel.x, 0, 1200 * dt)
				if cd <= 0 and lv.los(pos, pos + d): _go("windup")

func _ai_charger(dt, d):
	match state:
		"windup":
			vel.x = 0
			if st < 0.4: facing = int(sign(d.x)) if d.x != 0 else facing
			if st > 0.75:
				_go("attack")
				Snd.sfx("roar", -10, 1.4)
		"attack":
			vel.x = facing * 520
			anim += dt * 30
			if _contact(): hit_done = true
			if hit_wall != 0:
				stun_t = 1.3
				lv.shake(8)
				lv.burst(pos + Vector2(facing * half.x, 0), lv.pal.hi, 10)
				Snd.sfx("boom", -8)
				_go("chase")
				cd = 1.0
			elif st > 1.1 or (on_ground and _ledge()):
				_go("chase")
				cd = 1.6
		_:
			if abs(d.y) < 70 and abs(d.x) < 480 and cd <= 0: _go("windup")
			else: _walk(dt, sign(d.x) if abs(d.x) > 40 else 0.0, cfg.spd)

func _ai_leaper(dt, d):
	if on_ground:
		if state == "attack": _go("chase")
		vel.x = move_toward(vel.x, 0, 1600 * dt)
		if cd <= 0:
			if abs(d.x) < 360:
				facing = int(sign(d.x)) if d.x != 0 else facing
				vel = Vector2(facing * clamp(abs(d.x) * 1.6, 180, cfg.spd * 2.2), -470 if d.y > -80 else -640)
				_go("attack")
				cd = 0.9
			else: _walk(dt, sign(d.x), cfg.spd)
		elif abs(d.x) > 200: _walk(dt, sign(d.x), cfg.spd)
	elif state == "attack" and not hit_done:
		if _contact(): hit_done = true

func _ai_drone(dt, d):
	if cfg.get("dive", false) and state == "attack":
		vel = aim * 540
		if _contact(): hit_done = true
		if st > 0.55 or hit_wall != 0 or on_ground:
			_go("recover")
			cd = 1.6
		return
	if state == "windup":
		vel = vel.lerp(Vector2.ZERO, dt * 8)
		aim = d.normalized()
		if st > (0.5 if cfg.get("dive", false) else 0.35):
			if cfg.get("dive", false): _go("attack")
			else:
				_fire(aim, 460.0)
				_go("chase")
				cd = 1.8
		return
	var want = pos + d + Vector2(-sign(d.x) * 170, -130) + Vector2(sin(time * 1.3 + home.x) * 40, cos(time * 1.7) * 24)
	vel = vel.lerp((want - pos).limit_length(cfg.spd), dt * 3.0)
	facing = int(sign(d.x)) if d.x != 0 else facing
	if cd <= 0 and d.length() < 420 and lv.los(pos, pos + d): _go("windup")

func _ai_bomber(dt, d):
	var want = Vector2(pos.x + d.x + sin(time * 0.9) * 200, pos.y + d.y - 210)
	vel = vel.lerp((want - pos).limit_length(cfg.spd), dt * 2.5)
	if abs(vel.x) > 5: facing = int(sign(vel.x))
	if cd <= 0 and abs(d.x) < 70 and d.y > 60:
		cd = 1.3
		lv.shoot({"pos": pos + Vector2(0, 12), "vel": Vector2(vel.x * 0.5, 60), "team": 0 if ally else 1, "dmg": dmg(), "col": col, "kind": "bomb", "grav": 900.0, "r": 7.0, "life": 4.0})
		Snd.sfx("eshoot", -10, 0.6)

func _ai_turret(dt, d):
	vel.x = 0
	if state == "attack":
		if st > 0.1:
			st = 0.0
			_fire(aim.rotated(randf_range(-0.04, 0.04)), 560.0, {"pos": pos + Vector2(0, -6) + aim * 24})
			burst_left -= 1
			if burst_left <= 0:
				_go("chase")
				cd = 2.0
		return
	aim = aim.lerp(d.normalized(), dt * 4.0).normalized()
	if state == "windup":
		if st > 0.5:
			burst_left = cfg.get("burst", 3)
			_go("attack")
	elif cd <= 0 and d.length() < cfg.get("rng", 500) and lv.los(pos, pos + d): _go("windup")

func _ai_blinker(dt, d):
	match state:
		"windup":
			vel.x = 0
			if st > 0.32:
				_go("attack")
				vel.x = facing * 260
				Snd.sfx("slash2", -8)
		"attack":
			_melee(60.0)
			if st > 0.16: _go("recover")
		"recover":
			vel.x = move_toward(vel.x, 0, 1500 * dt)
			if st > 0.4: _go("chase")
		"blink":
			intangible = true
			if st > 0.3:
				intangible = false
				var side = -lv.player.facing
				var np = lv.player.pos + Vector2(side * 56, lv.player.half.y - half.y)
				if not lv.box_solid(np, half) and lv.solid_at(int(np.x / lv.T), int((np.y + half.y + 8) / lv.T)):
					pos = np
					lv.burst(pos, col, 10, 160)
					Snd.sfx("tele", -8)
				facing = -side
				_go("windup")
		_:
			if cd <= 0 and d.length() < 420 and d.length() > 90:
				cd = 2.6
				lv.burst(pos, col, 10, 160)
				_go("blink")
			elif abs(d.x) < 50 and abs(d.y) < 56:
				facing = int(sign(d.x)) if d.x != 0 else facing
				_go("windup")
			else: _walk(dt, sign(d.x), cfg.spd)

func _ai_swarm(dt, d):
	var want = d.normalized().rotated(sin(time * 5.0 + home.x) * 0.7) * cfg.spd
	vel = vel.lerp(want, dt * 3.0)
	facing = int(sign(vel.x)) if vel.x != 0 else facing
	if cd <= 0 and _contact():
		cd = 0.8
		vel = -d.normalized() * 300

func _ai_caster(dt, d):
	match state:
		"windup":
			vel.x = 0
			if st > 0.8:
				for i in 3:
					var a = -PI * 0.5 + (i - 1) * 0.7
					if cfg.get("emp", false):
						if i == 1: _fire(d.normalized(), 300.0, {"kind": "orb", "r": 9.0, "emp": true, "col": Color(0.6, 0.8, 1.0), "life": 3.0})
					else: _fire(Vector2.from_angle(a), 230.0, {"kind": "orb", "r": 7.0, "homing": 2.2, "life": 3.5, "pos": pos + Vector2(0, -half.y)})
				Snd.sfx("signal", -8, 1.5)
				_go("chase")
				cd = 3.0
		_:
			facing = int(sign(d.x)) if d.x != 0 else facing
			if fly: vel = vel.lerp(Vector2(-sign(d.x) * 40 if d.length() < 260 else 0.0, sin(time * 2) * 20), dt * 2)
			elif d.length() < 200: _walk(dt, -sign(d.x), cfg.spd)
			else: vel.x = move_toward(vel.x, 0, 900 * dt)
			if cd <= 0 and d.length() < cfg.get("rng", 500): _go("windup")

func _ai_crawler(dt, d):
	match state:
		"burrow":
			intangible = true
			vel.x = sign(d.x) * 240 if abs(d.x) > 20 else 0.0
			if st > 1.2 and abs(d.x) < 60:
				lv.zone({"shape": "circle", "a": pos + Vector2(0, half.y), "r": 70.0, "warn": 0.6, "live": 0.2, "dmg": dmg(), "col": col})
				_go("emerge")
		"emerge":
			vel.x = 0
			if st > 0.6:
				intangible = false
				vel.y = -300
				_go("chase")
				cd = 0.3
		"windup", "attack", "recover": _ai_grunt(dt, d)
		_:
			if st > 3.2 and on_ground:
				lv.burst(pos + Vector2(0, half.y), lv.pal.hi, 12)
				_go("burrow")
			else: _ai_grunt(dt, d)

func _ai_heavy(dt, d):
	match state:
		"windup":
			vel.x = 0
			if st > 0.7:
				_go("attack")
				lv.shake(9)
				Snd.sfx("boom", -4)
				var fx = pos + Vector2(facing * 50, half.y)
				lv.burst(fx, lv.pal.hi, 14, 260)
				for s in [-1, 1]: lv.shoot({"pos": fx + Vector2(s * 20, -2), "vel": Vector2(s * 330, 0), "team": 0 if ally else 1, "dmg": dmg() * 0.6, "col": col, "kind": "wave", "r": 9.0, "life": 0.9})
		"attack":
			_melee(84.0, 80.0)
			if st > 0.2: _go("recover")
		"recover":
			if st > 0.9:
				_go("chase")
				cd = 0.6
		_:
			if abs(d.x) < 86 and abs(d.y) < 80 and cd <= 0:
				facing = int(sign(d.x)) if d.x != 0 else facing
				_go("windup")
			else: _walk(dt, sign(d.x) if abs(d.x) > 40 else 0.0, cfg.spd)

func _ai_exploder(dt, d):
	if state == "windup":
		vel.x = move_toward(vel.x, 0, 600 * dt)
		if st > 0.55:
			lv.zone({"shape": "circle", "a": pos, "r": 84.0, "warn": 0.0, "live": 0.15, "dmg": dmg(), "col": col})
			die(true)
		return
	if d.length() < 56: _go("windup")
	else: _walk(dt, sign(d.x), cfg.spd)

func _ai_splitter(dt, d): _ai_grunt(dt, d)

func _ai_floater(dt, d):
	vel = vel.lerp(d.normalized() * cfg.spd + Vector2(0, sin(time * 2) * 20), dt * 1.5)
	if cd <= 0 and d.length() < 130:
		cd = 3.0
		lv.zone({"shape": "circle", "a": pos, "r": 115.0, "warn": 0.8, "live": 0.2, "dmg": dmg(), "col": col, "sfx": "tele"})

func _ai_flamer(dt, d):
	match state:
		"windup":
			vel.x = 0
			if st > 0.45: _go("attack")
		"attack":
			vel.x = facing * 40
			if int(st * 30) != int((st - dt) * 30):
				lv.shoot({"pos": pos + Vector2(facing * 20, -6), "vel": Vector2(facing * randf_range(300, 420), randf_range(-60, 40)), "team": 1, "dmg": dmg(), "col": Color(1, 0.5, 0.15), "kind": "flame", "r": 10.0, "life": 0.5})
			if st > 1.1:
				_go("chase")
				cd = 2.2
		_:
			if abs(d.x) < 170 and abs(d.y) < 60 and cd <= 0:
				facing = int(sign(d.x)) if d.x != 0 else facing
				_go("windup")
			else: _walk(dt, sign(d.x) if abs(d.x) > 120 else 0.0, cfg.spd)

# ---------------------------------------------------------------- damage
func take_hit(amount, kb, kind_, from_x):
	if dead: return false
	alert = true
	var front = sign(from_x - pos.x) == facing
	if cfg.get("shield", false) and front and kind_ in ["blade", "gun"] and stun_t <= 0 and state != "recover":
		lv.spark(pos + Vector2(facing * 14, -4), Color(1, 1, 1), Vector2(facing, -0.5), 5)
		Snd.sfx("parry", -12, 0.7)
		lv.popup(pos + Vector2(-20, -half.y - 14), "GUARD", col)
		return false
	if cfg.get("shield", false) and kind_ in ["charge", "grav", "crate", "boom"]: stun_t = max(stun_t, 1.2)
	if cfg.has("armor") and kind_ in ["gun", "arc"]: amount *= cfg.armor
	if marked_t > 0: amount *= 1.3
	if amount <= 0 and kind_ != "grav": return false
	hp -= amount
	flash = 0.12
	if kind_ == "arc": stun_t = max(stun_t, 0.9 if not is_boss else 0.0)
	var big = cfg.get("big", false) or is_boss
	if not big or kind_ in ["grav", "charge", "crate"]:
		if not is_boss:
			vel = kb * (0.5 if big else 1.0)
			stun_t = max(stun_t, 0.5 if kind_ == "grav" else 0.16)
			if state in ["windup", "attack"] and not cfg.get("elite", false): _go("chase")
	lv.spark(pos, col, Vector2(sign(kb.x + 0.01), -0.4), 4)
	if amount >= 1: lv.popup(pos + Vector2(randf_range(-10, 10), -half.y - 8), str(int(amount)), Color(1, 1, 1) if marked_t <= 0 else Color(1, 0.8, 0.4))
	if hp <= 0: die()
	return true

func die(silent = false):
	if dead: return
	dead = true
	visible = false
	gone = true
	lv.burst(pos, col, 18, 280, 0.6)
	lv.burst(pos, Color(0.2, 0.2, 0.25), 8, 160, 0.8)
	Snd.sfx("die", -6)
	if not silent and not ally:
		var sh = int(cfg.sh * (1.25 if G.has_mod("charm") else 1.0))
		G.state.shards += sh
		G.state.stats.kills += 1
		lv.popup(pos + Vector2(-8, -half.y - 24), "+%d" % sh, lv.pal.acc2)
		if G.has_mod("siphon"): lv.player.en = min(G.max_en(), lv.player.en + 12)
	if cfg.ai == "splitter" and not silent:
		for s in [-1, 1]:
			var m = lv.spawn_enemy("mote", pos + Vector2(s * 20, 0))
			m.alert = true
			m.vel = Vector2(s * 200, -200)
	queue_free()

# ---------------------------------------------------------------- drawing
func _draw():
	var c = col if flash <= 0 else Color(1, 1, 1)
	var a = 1.0 if not intangible else 0.25
	modulate = Color(1, 1, 1, a) if not ally else Color(1, 0.85, 0.6, a)
	var wind = state == "windup"
	match cfg.shape:
		"human":
			var stl = {"body": Color(0.2, 0.2, 0.26).lerp(c, 0.12) if flash <= 0 else Color(0.8, 0.8, 0.8), "acc": c, "robe": cfg.get("robe", false), "shield": cfg.get("shield", false), "s": 1.2 if cfg.get("big", false) else 1.0, "coat": cfg.get("elite", false)}
			var p = {"t": time, "phase": anim, "move": clamp(abs(vel.x) / 120.0, 0, 1) if on_ground else 0.0, "air": 0.0 if on_ground else 1.0}
			match cfg.ai:
				"gunner", "sniper", "turret":
					p["gun"] = true
					p["arm"] = Vector2(abs(aim.x), aim.y).angle() if state in ["windup", "attack"] else 0.3
				"caster":
					if wind: p["arm"] = -1.8
				"flamer":
					p["gun"] = true
					p["arm"] = 0.1
				_:
					p["blade"] = true
					p["arm"] = 0.6
					p["blade_ang"] = -0.9
					if wind:
						p["arm"] = -2.2
						p["blade_ang"] = -2.6
					elif state == "attack":
						p["arm"] = 0.5
						p["blade_ang"] = 0.3
						draw_arc(Vector2(6, -34), 42, -2.2, 0.6, 10, Color(c.r, c.g, c.b, 0.5), 8.0)
			Art.humanoid(self, stl, p)
		"drone":
			draw_set_transform(Vector2(0, -half.y), 0, Vector2.ONE)
			Art.drone(self, c, time, 1.0, cfg.get("big", false))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"mech": Art.mech(self, c, time, anim, clamp(abs(vel.x) / 60.0, 0, 1), 1.0, (st / 0.7 if wind else (1.0 if state == "attack" else 0.0)))
		"beast": Art.beast(self, c, time, anim, clamp(abs(vel.x) / 100.0, 0, 1), 1.3 if cfg.get("big", false) else 1.0, not on_ground)
		"jelly":
			draw_set_transform(Vector2(0, -4), 0, Vector2.ONE)
			Art.jelly(self, c, time)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"construct": Art.construct(self, c, time, 1.3 if cfg.get("big", false) else 1.0, 3 if cfg.ai == "caster" else 4)
		"wisp": Art.wisp(self, c, time)
		"turret": Art.turret(self, c, Vector2(aim.x * facing, aim.y).angle())
	if wind:
		Art.text(self, Vector2(-4 * facing, -half.y * 2 - 14), "!", 20, Color(1, 0.9, 0.3, 0.6 + 0.4 * sin(time * 30)))
		if cfg.ai == "sniper" or cfg.ai == "turret":
			draw_line(Vector2(0, -half.y), Vector2(0, -half.y) + Vector2(aim.x * facing, aim.y) * 900, Color(c.r, c.g, c.b, 0.25 + 0.4 * st), 1.5)
	if marked_t > 0: Art.ring(self, Vector2(0, -half.y), half.y + 10 + sin(time * 8) * 2, DB.C("ffb060", 0.7), 1.5, 6)
	if hp < max_hp and not is_boss:
		draw_rect(Rect2(-16, -half.y * 2 - 12, 32, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-16, -half.y * 2 - 12, 32 * clamp(hp / max_hp, 0, 1), 3), c)
