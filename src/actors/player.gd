extends Node2D
# Player — Kael Hawkthorne. Movement (coyote time, jump buffering, wall kicks, dash, roll, slide,
# gravity inversion), energy blade, modular sidearm, gravitational gauntlet, parry and Sable assists.

const Art = preload("res://src/core/art.gd")
const AMMO = [["pulse", "", "Pulse"], ["pierce", "pierce", "Rail"], ["scatter", "scatter", "Scatter"], ["arc", "arc", "Arc"]]

var lv
var pos = Vector2.ZERO
var vel = Vector2.ZERO
var half = Vector2(11, 27)
var on_ground = false
var hit_wall = 0
var hit_ceil = false
var riding = null
var drop = false
var phase = false
var facing = 1
var gdir = 1
var hp = 100.0
var en = 100.0
var coyote = 0.0
var jbuf = 0.0
var dash_t = 0.0
var dash_cd = 0.0
var dash_dir = 1
var dash_kind = ""
var air_dash = true
var air_jump = true
var wall_lock = 0.0
var wall_dir = 0
var low = false
var drop_t = 0.0
var atk_t = 0.0
var atk_dur = 0.22
var atk_step = 0
var atk_dirv = Vector2.RIGHT
var atk_hit = false
var atk_kind = "blade"
var combo_t = 0.0
var hold_t = 0.0
var parry_t = 0.0
var parry_cd = 0.0
var counter_t = 0.0
var shoot_cd = 0.0
var regen_wait = 0.0
var grav_cd = 0.0
var grav_fx = 0.0
var inv_t = 0.0
var hurt_t = 0.0
var dead = false
var dead_t = 0.0
var scan_cd = 0.0
var flip_cd = 0.0
var swim_cd = 0.0
var mote_cd = 1.0
var emp_t = 0.0
var time = 0.0
var phase_anim = 0.0
var blade_col = Color(0.45, 0.9, 1.0)
var locket_used = false
var god = false
var was_ground = true

func init(level, p):
	lv = level
	pos = p
	hp = min(float(G.state.get("hp", G.max_hp())), G.max_hp())
	if hp <= 0: hp = G.max_hp()
	en = G.max_en()
	z_index = 5
	position = pos

func full_heal():
	hp = G.max_hp()
	en = G.max_en()
	G.state.stims = G.max_stims()
	locket_used = false

func heal(a):
	hp = min(G.max_hp(), hp + a)
	Snd.sfx("heal")
	lv.burst(pos, Color(0.4, 1, 0.6), 10, 120, 0.6, -100)

func _jp(a): return Input.is_action_just_pressed(a)

func tick(dt):
	time += dt
	if dead:
		dead_t -= dt
		if dead_t <= 0 and dead_t > -10:
			dead_t = -100
			G.state.hp = G.max_hp()
			G.main.load_room(lv.id, "cp:%d" % G.state.cp)
		return
	for k in ["coyote", "jbuf", "dash_cd", "wall_lock", "combo_t", "parry_t", "parry_cd", "counter_t", "shoot_cd", "regen_wait", "grav_cd", "grav_fx", "inv_t", "hurt_t", "scan_cd", "flip_cd", "swim_cd", "drop_t", "emp_t"]:
		set(k, max(0.0, get(k) - dt))
	var ix = Input.get_axis("left", "right")
	if abs(ix) < 0.3: ix = 0.0
	else: ix = sign(ix)
	var up = Input.is_action_pressed("up")
	var down = Input.is_action_pressed("down")
	if riding != null:
		pos += riding.delta
		riding = null
	var g = 1700.0 * lv.grav_mult * gdir
	if lv.water: g *= 0.3
	wall_dir = 0
	if lv.box_solid(pos + Vector2(3, 0), half, self): wall_dir = 1
	elif lv.box_solid(pos - Vector2(3, 0), half, self): wall_dir = -1

	if dash_t > 0:
		dash_t -= dt
		var sp = {"dash": 640.0, "roll": 430.0, "slide": 500.0, "charge": 560.0}[dash_kind]
		vel = Vector2(dash_dir * sp, 0.0 if dash_kind == "dash" else vel.y + g * dt)
		if dash_kind == "charge": _attack_hits()
		if int(time * 60) % 2 == 0: lv.parts.append({"p": pos + Vector2(randf_range(-6, 6), randf_range(-16, 16)), "v": Vector2.ZERO, "l": 0.25, "m": 0.25, "c": blade_col, "g": 0.0, "s": 4.0})
		if dash_t <= 0:
			vel.x *= 0.45
			phase = false
	else:
		var maxs = 290.0
		if low: maxs = 140.0
		if atk_t > 0 and on_ground: maxs = 110.0
		if lv.water: maxs *= 0.75
		var acc = 2600.0 if on_ground else 1500.0
		if wall_lock > 0: acc = 300.0
		vel.x = move_toward(vel.x, ix * maxs, acc * dt)
		if ix != 0 and atk_t <= 0 and wall_lock <= 0: facing = int(ix)
		vel.y += g * dt
		var maxfall = 150.0 if lv.water else 900.0
		if vel.y * gdir > maxfall: vel.y = maxfall * gdir
		if not on_ground and wall_dir != 0 and ix == wall_dir and vel.y * gdir > 110.0 and G.has("walljump"):
			vel.y = 110.0 * gdir
			if int(time * 30) % 3 == 0: lv.spark(pos + Vector2(wall_dir * 11, 20), Color(1, 1, 1, 0.5), Vector2(0, -1), 1)
		if _jp("jump"): jbuf = 0.13
		if jbuf > 0:
			if down and on_ground and _on_oneway():
				drop_t = 0.22
				jbuf = 0
			elif coyote > 0:
				vel.y = -625.0 * gdir * (0.8 if lv.water else 1.0)
				coyote = 0
				jbuf = 0
				Snd.sfx("jump", -8)
				lv.burst(pos + Vector2(0, half.y * gdir), Color(1, 1, 1, 0.4), 4, 80, 0.3)
			elif wall_dir != 0 and G.has("walljump") and not lv.water:
				vel = Vector2(-wall_dir * 370.0, -590.0 * gdir)
				facing = -wall_dir
				wall_lock = 0.17
				jbuf = 0
				Snd.sfx("jump", -6, 1.2)
			elif lv.water and swim_cd <= 0:
				vel.y = -300.0 * gdir
				swim_cd = 0.28
				jbuf = 0
				lv.burst(pos, Color(0.7, 1, 1, 0.5), 4, 60, 0.5, -60)
			elif G.has("double") and air_jump:
				vel.y = -570.0 * gdir
				air_jump = false
				jbuf = 0
				Snd.sfx("grav", -10, 1.6)
				lv.burst(pos + Vector2(0, half.y * gdir), blade_col, 10, 140, 0.35)
		if not Input.is_action_pressed("jump") and vel.y * gdir < -260.0 and wall_lock <= 0: vel.y = -260.0 * gdir
		if _jp("dash") and dash_cd <= 0:
			var dd = int(ix) if ix != 0 else facing
			if on_ground:
				_start_dash("slide" if (down and abs(vel.x) > 150) else "roll", dd)
			elif G.has("dash") and air_dash:
				air_dash = false
				_start_dash("dash", dd)
	drop = drop_t > 0
	# crouch / low hitbox
	var want_low = (dash_t > 0 and dash_kind in ["roll", "slide"]) or (down and on_ground and dash_t <= 0 and ix == 0)
	if want_low and not low:
		low = true
		half.y = 13.0
		pos.y += 14.0 * gdir
	elif not want_low and low:
		var np = pos - Vector2(0, 14.0 * gdir)
		if not lv.box_solid(np, Vector2(half.x, 27.0), self):
			low = false
			half.y = 27.0
			pos = np
		elif dash_t <= 0 and on_ground:
			vel.x = move_toward(vel.x, facing * 140.0, 2000 * dt)
	lv.move_box(self, dt, gdir)
	if on_ground:
		if not was_ground:
			Snd.sfx("land", -10)
			lv.burst(pos + Vector2(0, half.y * gdir), Color(1, 1, 1, 0.35), 5, 90, 0.3)
		coyote = 0.1
		air_dash = true
		air_jump = true
		if abs(vel.x) > 60:
			var old = phase_anim
			phase_anim += abs(vel.x) * dt * 0.045
			if int(old / PI) != int(phase_anim / PI): Snd.sfx("step", -14)
	was_ground = on_ground
	_combat(dt, ix, up, down)
	_hazards(dt)
	if _jp("interact"): lv.interact()
	G.state.hp = hp
	position = pos + Vector2(0, half.y * gdir)
	scale = Vector2(facing, gdir)
	modulate.a = 0.45 if (inv_t > 0 and int(time * 30) % 2 == 0) else 1.0
	queue_redraw()

func _on_oneway():
	var ty = int((pos.y + half.y + 4) / lv.T)
	for tx in range(int((pos.x - half.x) / lv.T), int((pos.x + half.x) / lv.T) + 1):
		if lv.tile(tx, ty) == 1: return false
	return true

func _start_dash(kind, dd):
	dash_kind = kind
	dash_dir = dd
	facing = dd
	dash_t = {"dash": 0.17, "roll": 0.34, "slide": 0.5, "charge": 0.2}[kind]
	dash_cd = 0.55 * (0.7 if G.has_mod("stride") else 1.0)
	if kind == "roll": inv_t = max(inv_t, 0.3)
	if kind == "dash": inv_t = max(inv_t, 0.12)
	phase = G.has("phase") and kind != "charge"
	atk_t = 0.0 if kind != "charge" else atk_t
	Snd.sfx("dash", -6)

func _combat(dt, ix, up, down):
	# energy regen
	if regen_wait <= 0: en = min(G.max_en(), en + 16.0 * (1.0 + 0.2 * int(G.state.upgrades.get("regen", 0))) * dt)
	# blade
	if atk_t > 0:
		atk_t -= dt
		_attack_hits()
		if atk_t <= 0: combo_t = 0.35
	if Input.is_action_pressed("attack"): hold_t += dt
	if _jp("attack") and atk_t <= 0.06 and dash_t <= 0:
		atk_step = (atk_step + 1) % 3 if combo_t > 0 or atk_t > 0 else 0
		atk_dur = 0.3 if atk_step == 2 else 0.2
		atk_t = atk_dur
		atk_hit = false
		atk_kind = "blade"
		atk_dirv = Vector2(facing, 0)
		if up: atk_dirv = Vector2(0, -gdir)
		elif down and not on_ground: atk_dirv = Vector2(0, gdir)
		elif on_ground: vel.x += facing * 130.0
		hold_t = 0.0
		Snd.sfx("slash2" if atk_step == 2 else "slash", -5)
	if Input.is_action_just_released("attack"):
		if hold_t > 0.45 and G.has("charge") and dash_t <= 0:
			atk_kind = "charge"
			atk_dirv = Vector2(facing, 0)
			atk_dur = 0.24
			atk_t = atk_dur
			atk_hit = false
			_start_dash("charge", facing)
			Snd.sfx("charge")
			lv.shake(5)
		hold_t = 0.0
	# parry
	if _jp("parry") and parry_cd <= 0:
		parry_t = 0.2 + 0.03 * int(G.state.upgrades.get("parry", 0))
		parry_cd = 0.55
	# sidearm
	if Input.is_action_pressed("shoot") and shoot_cd <= 0 and atk_t <= 0 and emp_t <= 0:
		var mode = AMMO[int(G.state.ammo) % AMMO.size()]
		if mode[1] != "" and not G.has(mode[1]):
			G.state.ammo = 0
			mode = AMMO[0]
		var cost = {"pulse": 6.0, "pierce": 24.0, "scatter": 16.0, "arc": 14.0}[mode[0]]
		var dmg = G.gun_dmg()
		if G.has_mod("overclock"):
			cost *= 1.4
			dmg *= 1.4
		if en >= cost:
			en -= cost
			regen_wait = 0.7
			var dir = Vector2(facing, 0)
			if up: dir = Vector2(facing * 0.7, -0.7 * gdir) if ix != 0 else Vector2(0, -gdir)
			elif down and not on_ground: dir = Vector2(facing * 0.7, 0.7 * gdir)
			var o = pos + Vector2(facing * 14, -6 * gdir) + dir * 10
			match mode[0]:
				"pulse":
					lv.shoot({"pos": o, "vel": dir * 900, "team": 0, "dmg": dmg, "col": blade_col})
					shoot_cd = 0.2
					Snd.sfx("shoot", -8)
				"pierce":
					lv.shoot({"pos": o, "vel": dir * 1500, "team": 0, "dmg": dmg * 3.2, "col": Color(1, 0.9, 0.6), "pierce": 5, "r": 7.0})
					shoot_cd = 0.6
					vel -= dir * 160
					Snd.sfx("rail", -4)
					lv.shake(4)
				"scatter":
					for i in 5: lv.shoot({"pos": o, "vel": dir.rotated((i - 2) * 0.13) * randf_range(700, 850), "team": 0, "dmg": dmg * 0.8, "col": Color(1, 0.6, 0.3), "life": 0.32})
					shoot_cd = 0.5
					vel -= dir * 120
					Snd.sfx("scatter", -4)
				"arc":
					lv.shoot({"pos": o, "vel": dir * 700, "team": 0, "dmg": dmg * 1.2, "col": Color(0.7, 0.6, 1.0), "kind": "arc", "r": 8.0})
					shoot_cd = 0.4
					Snd.sfx("tele", -8)
			lv.spark(o, blade_col, dir, 3)
	if _jp("swap"):
		for i in AMMO.size():
			G.state.ammo = (int(G.state.ammo) + 1) % AMMO.size()
			var m = AMMO[int(G.state.ammo)]
			if m[1] == "" or G.has(m[1]): break
		Snd.sfx("ui")
		G.toast.emit("Sidearm: " + AMMO[int(G.state.ammo)][2])
	# gauntlet
	if _jp("gauntlet") and G.has("gauntlet") and grav_cd <= 0 and emp_t <= 0:
		grav_cd = 1.5 * (1.0 - 0.2 * int(G.state.upgrades.get("grav", 0)))
		grav_fx = 0.3
		Snd.sfx("grav")
		lv.shake(4)
		var mode = "push"
		if down: mode = "pull"
		elif up and G.has("suspend"): mode = "suspend"
		var reach = Rect2(pos + Vector2(0 if facing > 0 else -300, -90), Vector2(300, 150))
		for e in lv.enemies:
			if e.dead or not reach.intersects(Rect2(e.pos - e.half, e.half * 2)): continue
			match mode:
				"push": e.take_hit(8, Vector2(facing * 560, -220), "grav", pos.x)
				"pull": e.take_hit(4, Vector2(-facing * 420, -160), "grav", e.pos.x + facing)
				"suspend": e.suspend(2.2)
		for c in lv.crates:
			if reach.has_point(c.pos):
				c.vel = Vector2(facing * 620, -260) if mode != "pull" else Vector2(-facing * 420, -300)
		for s in lv.shots:
			if s.team == 1 and reach.has_point(s.pos):
				s.team = 0
				s.vel = Vector2(facing, 0) * s.vel.length() * 1.2
				s.dmg += 8
		for i in 12: lv.spark(pos + Vector2(facing * 20, randf_range(-30, 30)), Color(0.7, 0.6, 1.0), Vector2(facing if mode != "pull" else -facing, 0), 1)
	# stim
	if _jp("heal") and G.state.stims > 0 and hp < G.max_hp():
		G.state.stims -= 1
		heal(45)
	# Sable assist
	if _jp("sable") and scan_cd <= 0:
		if G.f("sable_silent") != 0:
			G.toast.emit("…no response from Sable.")
			scan_cd = 2.0
		else:
			scan_cd = 9.0
			Snd.sfx("signal", -4)
			var dur = 7.0 * (2.0 if G.has_mod("glass") else 1.0)
			if G.has("sight"): lv.sight_t = dur
			var hijacked = false
			for e in lv.enemies:
				if e.dead or e.pos.distance_to(pos) > 520: continue
				e.marked_t = dur
				if not hijacked and e.cfg.get("hack", false) and G.sable_stage() >= 2 and G.val("rel.sable") >= 0 and e.pos.distance_to(pos) < 320:
					e.ally = true
					hijacked = true
					lv.popup(e.pos + Vector2(0, -40), "HIJACKED", DB.C("ffb060"))
			lv.zone({"shape": "circle", "a": pos, "r": 520.0, "warn": 0.35, "live": 0.01, "dmg": 0, "col": DB.C("ffb060"), "team": 2, "sfx": ""})
	# Mote covering fire — only if Sable is willing
	mote_cd -= dt
	if mote_cd <= 0 and G.state.chapter >= 3 and G.val("rel.sable") >= 2 and G.f("sable_silent") == 0:
		mote_cd = 2.2 * (0.6 if G.has_mod("choir") else 1.0)
		var best = null
		for e in lv.enemies:
			if not e.dead and not e.ally and e.alert and e.pos.distance_to(lv.mote_pos) < 430 and (best == null or e.pos.distance_to(pos) < best.pos.distance_to(pos)): best = e
		if best != null and lv.los(lv.mote_pos, best.pos):
			lv.shoot({"pos": lv.mote_pos, "vel": (best.pos - lv.mote_pos).normalized() * 800, "team": 0, "dmg": 6 + 3 * int(G.state.upgrades.get("mote", 0)), "col": DB.C("ffb060"), "r": 4.0})
			Snd.sfx("shoot", -14, 1.5)

func _attack_hits():
	if atk_hit and atk_kind != "charge": return
	var k = 1.0 - atk_t / atk_dur
	if atk_kind == "blade" and (k < 0.2 or k > 0.8): return
	var r
	if atk_dirv.x != 0: r = Rect2(pos + Vector2(4 if facing > 0 else -70, -30), Vector2(66, 56))
	elif atk_dirv.y * gdir < 0: r = Rect2(pos + Vector2(-34, -78 if gdir > 0 else 20), Vector2(68, 58))
	else: r = Rect2(pos + Vector2(-30, 14 if gdir > 0 else -72), Vector2(60, 58))
	var dmg = G.blade_dmg() * [1.0, 1.0, 1.7][atk_step]
	var kb = Vector2(facing * (160 + 120 * atk_step), -80)
	if atk_kind == "charge":
		if atk_hit:
			lv.hit_enemies(r, 0, Vector2.ZERO, "charge")
			return
		dmg = G.blade_dmg() * 3.0
		kb = Vector2(facing * 480, -200)
	if counter_t > 0: dmg *= 2.0 if not G.has_mod("thorn") else 3.0
	var n = lv.hit_enemies(r, dmg, kb, atk_kind)
	if n > 0:
		atk_hit = true
		counter_t = 0
		en = min(G.max_en(), en + 4.0 * n)
		lv.stop(3 if atk_kind == "blade" else 6)
		lv.shake(3 + 2 * atk_step)
		Snd.sfx("hit", -4)
		if atk_dirv.y * gdir > 0 and not on_ground:
			vel.y = -470.0 * gdir
			air_dash = true

func _hazards(dt):
	var T = lv.T
	for ty in range(int((pos.y - half.y) / T), int((pos.y + half.y) / T) + 1):
		for tx in range(int((pos.x - half.x + 3) / T), int((pos.x + half.x - 3) / T) + 1):
			var t = lv.tile(tx, ty)
			if t == 3 and inv_t <= 0:
				if take_hit(14, pos + Vector2(0, 20 * gdir), "spike") == "hit": vel.y = -380.0 * gdir
			elif t == 4:
				lv.respawn_safe(22)
				return
			elif t == 9:
				vel.y = max(vel.y - 3200.0 * dt, -460.0)
			elif t == 12 and flip_cd <= 0:
				gdir = -gdir
				flip_cd = 0.7
				vel.y = -200.0 * gdir * -1
				Snd.sfx("grav", -6, 1.4)
				lv.burst(pos, lv.pal.acc2, 14, 200)
	if pos.y > lv.H * T + 90 or pos.y < -260: lv.respawn_safe(18)

func take_hit(dmg, from, kind = "melee", src = null):
	if dead or god: return "dodged"
	if kind != "pit" and (inv_t > 0 or (dash_t > 0 and dash_kind == "roll")): return "dodged"
	if kind in ["melee", "shot"]:
		var auto = G.settings.auto_parry and parry_cd <= 0 and atk_t <= 0 and en >= 15
		if parry_t > 0 or auto:
			if auto and parry_t <= 0:
				en -= 15
				parry_cd = 0.8
			counter_t = 0.9
			parry_t = 0.0
			inv_t = 0.25
			G.state.stats.parries += 1
			Snd.sfx("parry")
			lv.stop(7)
			lv.shake(6)
			lv.spark(pos + Vector2(facing * 16, -8), Color(1, 1, 1), Vector2(facing, -0.3), 10)
			if G.has_mod("lantern"): hp = min(G.max_hp(), hp + 6)
			if kind == "melee" and src != null and src.has_method("parried"): src.parried()
			return "parried"
	hp -= dmg * G.dmg_taken_mult()
	inv_t = 0.75
	hurt_t = 0.25
	hold_t = 0.0
	if not G.has_mod("anchor") and kind != "pit":
		vel = Vector2(sign(pos.x - from.x + 0.01) * 260.0, -260.0 * gdir)
	Snd.sfx("hurt", -3)
	lv.shake(8)
	lv.stop(4)
	lv.burst(pos, Color(1, 0.4, 0.3), 10, 220)
	if lv.post != null: lv.post.pulse(1.0)
	if hp <= 0:
		if G.has_mod("heartsteel") and not locket_used:
			locket_used = true
			hp = 25.0
			inv_t = 1.5
			G.toast.emit("The locket holds.")
		else: die()
	return "hit"

func die():
	if dead: return
	dead = true
	dead_t = 1.5
	hp = 0
	G.state.stats.deaths += 1
	Snd.sfx("die")
	lv.burst(pos, blade_col, 30, 320, 0.9)
	lv.shake(12)
	visible = false

func _draw():
	var st = {"body": Color(0.27, 0.3, 0.4), "acc": blade_col, "coat": true, "hair": Color(0.1, 0.1, 0.12), "blade_col": blade_col}
	var p = {"t": time, "phase": phase_anim, "move": clamp(abs(vel.x) / 290.0, 0.0, 1.0) if on_ground else 0.0, "air": 0.0 if on_ground else (1.0 if vel.y * gdir > 0 else -1.0), "crouch": 1.0 if low else 0.0, "lean": clamp(vel.x * facing / 600.0, -0.4, 0.8)}
	if dash_t > 0 and dash_kind in ["roll", "slide"]: p["lean"] = 1.2
	if atk_t > 0:
		var k = 1.0 - atk_t / atk_dur
		var a0 = -2.4
		var a1 = 1.0
		if atk_step == 1:
			a0 = 1.2
			a1 = -2.0
		if atk_dirv.y != 0:
			var up = atk_dirv.y * gdir < 0
			a0 = -2.8 if up else 0.4
			a1 = -0.4 if up else 2.6
		if atk_kind == "charge":
			a0 = -0.2
			a1 = 0.1
		var a = lerp(a0, a1, ease(k, 0.4))
		p["arm"] = a
		p["blade"] = true
		p["blade_ang"] = a
		st["blade_len"] = 44.0 if atk_kind == "blade" else 60.0
		var c = Vector2(4, -40)
		draw_arc(c, 50.0, min(a0, a) , max(a0, a), 14, Color(blade_col.r, blade_col.g, blade_col.b, 0.5 * (1.0 - k)), 14.0)
		draw_arc(c, 56.0, min(a0, a), max(a0, a), 14, Color(1, 1, 1, 0.7 * (1.0 - k)), 3.0)
	elif hold_t > 0.2 and G.has("charge"):
		p["arm"] = -2.6
		p["blade"] = true
		p["blade_ang"] = -2.2
		st["blade_len"] = 36.0 + min(1.0, hold_t / 0.45) * 20.0
		if hold_t > 0.45: Art.ring(self, Vector2(0, -30), 30 + sin(time * 30) * 3, Color(1, 1, 1, 0.7), 2.0, 20)
	elif shoot_cd > 0.05 or Input.is_action_pressed("shoot"):
		p["arm"] = -PI * 0.5 if Input.is_action_pressed("up") else 0.0
		p["gun"] = true
	if parry_t > 0:
		p["arm"] = -0.9
		p["blade"] = true
		p["blade_ang"] = -1.7
		draw_arc(Vector2(10, -34), 26, -1.4, 1.4, 12, Color(1, 1, 1, 0.8), 3.0)
	if grav_fx > 0:
		p["arm"] = 0.0
		for i in 3: draw_arc(Vector2(24 + (0.3 - grav_fx) * 600 + i * 26, -30), 30 + i * 10, -0.9, 0.9, 10, Color(0.7, 0.6, 1.0, grav_fx * 2.5), 3.0)
	if wall_dir != 0 and not on_ground and vel.y * gdir > 0: p["arm"] = -1.2
	Art.humanoid(self, st, p)
