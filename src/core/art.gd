extends RefCounted
# Art — the procedural art pipeline. Every character, creature and portrait in the game is
# drawn from code with these helpers (no bitmap assets), giving one cohesive rim-lit silhouette style.

static var _glow = null
static var _font = null

static func font():
	if _font == null: _font = ThemeDB.fallback_font
	return _font

static func glow_tex():
	if _glow == null:
		var g = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.3, Color(1, 1, 1, 0.35))
		var t = GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 96
		t.height = 96
		_glow = t
	return _glow

static func glow(ci, pos, radius, col):
	ci.draw_texture_rect(glow_tex(), Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, col)

static func text(ci, pos, s, size, col, align = HORIZONTAL_ALIGNMENT_LEFT, width = -1.0):
	ci.draw_string(font(), pos, s, align, width, size, col)

static func text_shadow(ci, pos, s, size, col, align = HORIZONTAL_ALIGNMENT_LEFT, width = -1.0):
	ci.draw_string(font(), pos + Vector2(1, 2), s, align, width, size, Color(0, 0, 0, 0.7 * col.a))
	ci.draw_string(font(), pos, s, align, width, size, col)

static func limb(ci, a, b, w, col):
	ci.draw_line(a, b, col, w)
	ci.draw_circle(a, w * 0.5, col)
	ci.draw_circle(b, w * 0.5, col)

static func ik(a, b, l1, l2, bend):
	var d = b - a
	var dist = clamp(d.length(), 0.001, l1 + l2 - 0.01)
	var cosv = clamp((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	return a + Vector2.from_angle(d.angle() + acos(cosv) * bend) * l1

static func ell(ci, c, rx, ry, col, n = 18, a0 = 0.0, a1 = TAU):
	var pts = PackedVector2Array()
	for i in n + 1:
		var a = lerp(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if a1 - a0 < TAU - 0.01: pts.append(c)
	ci.draw_colored_polygon(pts, col)

static func ring(ci, c, r, col, w = 1.5, n = 32):
	ci.draw_arc(c, r, 0, TAU, n, col, w)

static func blade(ci, a, ang, length, col, w = 3.0):
	var b = a + Vector2.from_angle(ang) * length
	ci.draw_line(a, b, Color(col.r, col.g, col.b, 0.25), w * 3.0)
	ci.draw_line(a, b, Color(col.r, col.g, col.b, 0.6), w * 1.6)
	ci.draw_line(a, b, Color(1, 1, 1, 0.95), w * 0.6)

# ---------------------------------------------------------------- humanoid puppet
# st: body, acc, s, coat, robe, hood, shield, hair(Color)   p: phase, move, air, crouch, lean, arm, blade, blade_ang, gun, hurt, t
static func humanoid(ci, st, p):
	var s = st.get("s", 1.0)
	var body = st.body
	var acc = st.acc
	var cr = p.get("crouch", 0.0)
	var lean = p.get("lean", 0.0)
	var ph = p.get("phase", 0.0)
	var mv = p.get("move", 0.0)
	var air = p.get("air", 0.0)
	var t = p.get("t", 0.0)
	var breath = sin(t * 2.2) * 0.6
	var hip = Vector2(0, -26.0 * s * (1.0 - 0.5 * cr))
	var sh = hip + Vector2(lean * 9.0, -19.0 * s * (1.0 - 0.3 * cr) + breath)
	var head = sh + Vector2(lean * 4.0 + 1.0, -9.0 * s)
	var dark = body.darkened(0.3)
	# coat / cape behind
	if st.get("coat", false):
		var sway = -lean * 14.0 - mv * 8.0 + sin(t * 3.0 + ph) * 2.0
		ci.draw_colored_polygon(PackedVector2Array([sh + Vector2(-5 * s, 0), sh + Vector2(3 * s, 2), hip + Vector2(2 * s, 6 * s), hip + Vector2(-9 * s + sway, 17 * s), hip + Vector2(-13 * s + sway * 1.3, 12 * s)]), dark)
	# back arm
	var aa = PI * 0.5 - sin(ph) * 0.7 * mv + 0.1
	var hand_b = sh + Vector2.from_angle(aa) * 19.0 * s
	limb(ci, sh, ik(sh, hand_b, 10 * s, 10 * s, 1.0), 4.5 * s, dark)
	limb(ci, ik(sh, hand_b, 10 * s, 10 * s, 1.0), hand_b, 4.0 * s, dark)
	# legs
	for i in 2:
		var a = ph + PI * i
		var foot = Vector2(sin(a) * 12.0 * mv * s, -max(0.0, cos(a)) * 7.0 * mv * s)
		if air != 0.0: foot = Vector2((-7.0 + 13.0 * i) * s + air * 2.0, (-9.0 if i == 1 else -2.0) * s)
		elif cr > 0.5: foot.x = (-8.0 + 16.0 * i) * s
		elif mv < 0.05: foot.x = (-3.5 + 7.0 * i) * s
		var knee = ik(hip, foot, 13.5 * s, 13.5 * s, -1.0)
		var c = dark if i == 0 else body
		limb(ci, hip, knee, 6.0 * s, c)
		limb(ci, knee, foot, 5.0 * s, c)
		ci.draw_line(foot + Vector2(-1, -1), foot + Vector2(5.5 * s, -1), c, 3.0 * s)
	if st.get("robe", false):
		ci.draw_colored_polygon(PackedVector2Array([hip + Vector2(-6 * s, -2), hip + Vector2(6 * s, -2), Vector2(9 * s + sin(ph) * 2 * mv, -2), Vector2(-9 * s - sin(ph) * 2 * mv, -2)]), body.darkened(0.12))
	# torso
	ci.draw_colored_polygon(PackedVector2Array([sh + Vector2(-6 * s, -1), sh + Vector2(6.5 * s, -1), hip + Vector2(5.5 * s, 3), hip + Vector2(-5.5 * s, 3)]), body)
	ci.draw_line(sh + Vector2(5.5 * s, 1), hip + Vector2(4.5 * s, 0), acc.darkened(0.2), 1.5)
	# head
	ci.draw_circle(head, 6.5 * s, body.lightened(0.06))
	if st.get("hood", false) or st.get("robe", false):
		ell(ci, head + Vector2(-1.5, -0.5), 7.6 * s, 7.6 * s, dark, 12, PI * 0.6, PI * 2.1)
	elif st.has("hair"):
		ell(ci, head + Vector2(-1, -1.5), 7.0 * s, 6.5 * s, st.hair, 10, PI * 0.9, PI * 1.9)
	ci.draw_line(head + Vector2(1.0 * s, -0.5), head + Vector2(6.4 * s, -0.5), acc, 2.0 * s)
	# front arm + weapon
	var fa = p.get("arm", PI * 0.5 + sin(ph) * 0.7 * mv - 0.15)
	var hand = sh + Vector2.from_angle(fa) * 20.0 * s
	var elbow = ik(sh, hand, 10.5 * s, 10.5 * s, 1.0)
	if st.get("shield", false):
		var sc = hip + Vector2(13 * s, -12 * s)
		ci.draw_colored_polygon(PackedVector2Array([sc + Vector2(-3, -24 * s), sc + Vector2(4, -20 * s), sc + Vector2(5, 16 * s), sc + Vector2(-3, 20 * s)]), acc.darkened(0.45))
		ci.draw_line(sc + Vector2(5, -19 * s), sc + Vector2(6, 15 * s), acc, 2.0)
	limb(ci, sh, elbow, 5.0 * s, body.lightened(0.04))
	limb(ci, elbow, hand, 4.5 * s, body.lightened(0.04))
	if p.get("gun", false):
		ci.draw_line(hand, hand + Vector2.from_angle(fa) * 11.0 * s, Color(0.15, 0.16, 0.2), 4.0 * s)
		ci.draw_circle(hand + Vector2.from_angle(fa) * 11.0 * s, 1.5, acc)
	if p.get("blade", false):
		blade(ci, hand, p.get("blade_ang", fa), st.get("blade_len", 36.0) * s, st.get("blade_col", acc))
	return {"hand": hand, "head": head, "sh": sh}

static func drone(ci, col, t, s = 1.0, big = false):
	var bob = sin(t * 4.0) * 2.0
	var c = Vector2(0, bob)
	var body = Color(0.13, 0.15, 0.2)
	ell(ci, c, 15 * s, 8 * s, body)
	ell(ci, c + Vector2(0, -3 * s), 9 * s, 5 * s, body.lightened(0.12))
	for sx in [-1, 1]:
		ci.draw_line(c + Vector2(sx * 12 * s, -3 * s), c + Vector2(sx * 20 * s, -9 * s), body.lightened(0.2), 2.0)
		var rw = 9.0 * s * abs(sin(t * 40.0 + sx))
		ci.draw_line(c + Vector2(sx * 20 * s - rw, -10 * s), c + Vector2(sx * 20 * s + rw, -10 * s), Color(col.r, col.g, col.b, 0.6), 1.5)
	ci.draw_circle(c + Vector2(5 * s, 1 * s), 3.0 * s, col)
	if big:
		ci.draw_rect(Rect2(c + Vector2(-8 * s, 6 * s), Vector2(16 * s, 5 * s)), body.darkened(0.2))

static func mech(ci, col, t, phase, mv, s = 1.0, atk = 0.0):
	var body = Color(0.16, 0.18, 0.23)
	var hip = Vector2(0, -30 * s)
	for i in 2:
		var a = phase + PI * i
		var foot = Vector2(sin(a) * 12 * mv * s + (-10 + 20 * i) * s, -max(0.0, cos(a)) * 6 * mv * s)
		var knee = ik(hip + Vector2((-8 + 16 * i) * s, 0), foot, 17 * s, 17 * s, 1.0 if i == 0 else -1.0)
		limb(ci, hip + Vector2((-8 + 16 * i) * s, 0), knee, 8 * s, body.darkened(0.2 if i == 0 else 0.0))
		limb(ci, knee, foot, 7 * s, body.darkened(0.2 if i == 0 else 0.0))
		ci.draw_rect(Rect2(foot + Vector2(-7 * s, -4 * s), Vector2(16 * s, 5 * s)), body.lightened(0.1))
	var tc = hip + Vector2(0, -18 * s + sin(t * 3.0))
	ci.draw_colored_polygon(PackedVector2Array([tc + Vector2(-20 * s, -16 * s), tc + Vector2(16 * s, -18 * s), tc + Vector2(22 * s, 6 * s), tc + Vector2(10 * s, 16 * s), tc + Vector2(-16 * s, 14 * s)]), body)
	ci.draw_line(tc + Vector2(-18 * s, -6 * s), tc + Vector2(20 * s, -8 * s), body.lightened(0.18), 2.0)
	ci.draw_rect(Rect2(tc + Vector2(6 * s, -12 * s), Vector2(12 * s, 6 * s)), col)
	var arm = tc + Vector2(10 * s, 4 * s)
	var ang = 0.5 - atk * 1.8
	limb(ci, arm, arm + Vector2.from_angle(ang) * 26 * s, 9 * s, body.lightened(0.08))
	ci.draw_circle(arm + Vector2.from_angle(ang) * 28 * s, 7 * s, col.darkened(0.3))
	limb(ci, tc + Vector2(-14 * s, 2 * s), tc + Vector2(-22 * s, 20 * s), 8 * s, body.darkened(0.25))

static func beast(ci, col, t, phase, mv, s = 1.0, air = false):
	var body = Color(0.1, 0.13, 0.16)
	var c = Vector2(0, -15 * s)
	for i in 4:
		var a = phase + i * PI * 0.5
		var hx = (-12 + 8 * i) * s
		var foot = Vector2(hx + sin(a) * 8 * mv * s, -max(0.0, cos(a)) * 5 * mv * s) if not air else Vector2(hx + (i - 1.5) * 4, -4 * s)
		var knee = ik(c + Vector2(hx * 0.7, 0), foot, 10 * s, 10 * s, -1.0 if i < 2 else 1.0)
		limb(ci, c + Vector2(hx * 0.7, 0), knee, 3.5 * s, body.lightened(0.1))
		limb(ci, knee, foot, 2.5 * s, body.lightened(0.1))
	ell(ci, c, 17 * s, 8 * s, body)
	for i in 5:
		var px = (-12 + 6 * i) * s
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(px - 3, -5 * s), c + Vector2(px + 3, -5 * s), c + Vector2(px - 2, (-13 - 3 * sin(t * 3 + i)) * s)]), Color(col.r, col.g, col.b, 0.8))
	ell(ci, c + Vector2(17 * s, -1 * s), 7 * s, 5 * s, body.lightened(0.08))
	ci.draw_circle(c + Vector2(20 * s, -2 * s), 1.8 * s, col)
	ci.draw_line(c + Vector2(-16 * s, 0), c + Vector2(-27 * s, (-6 + 3 * sin(t * 5)) * s), body, 3 * s)

static func jelly(ci, col, t, s = 1.0):
	var pulse = sin(t * 2.5)
	var c = Vector2(0, -10 * s)
	for i in 6:
		var x = (-10 + 4 * i) * s
		var pts = PackedVector2Array()
		for j in 6: pts.append(c + Vector2(x + sin(t * 3 + i + j * 0.9) * 3, j * 6 * s))
		ci.draw_polyline(pts, Color(col.r, col.g, col.b, 0.5), 1.5)
	ell(ci, c, (14 + pulse * 2) * s, (11 - pulse) * s, Color(col.r, col.g, col.b, 0.35), 14, PI, TAU)
	ell(ci, c, (9 + pulse) * s, (7 - pulse * 0.5) * s, Color(col.r, col.g, col.b, 0.7), 12, PI, TAU)
	ci.draw_circle(c + Vector2(0, -4 * s), 2.5 * s, Color(1, 1, 1, 0.9))

static func construct(ci, col, t, s = 1.0, sides = 4):
	for k in 3:
		var r = (20 - k * 6) * s
		var pts = PackedVector2Array()
		var rot = t * (1.0 + k * 0.7) * (1 if k % 2 == 0 else -1)
		for i in sides + 1: pts.append(Vector2(0, -20 * s) + Vector2.from_angle(rot + i * TAU / sides) * r)
		ci.draw_polyline(pts, Color(col.r, col.g, col.b, 0.5 + 0.2 * k), 2.0)
	ci.draw_circle(Vector2(0, -20 * s), 4.0 * s + sin(t * 6) * 1.0, Color(1, 1, 1, 0.95))

static func wisp(ci, col, t, s = 1.0):
	var c = Vector2(0, -6)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-7 * s, 0), c + Vector2(0, -6 * s), c + Vector2(8 * s, 0), c + Vector2(0, 6 * s)]), col)
	ci.draw_line(c + Vector2(-7 * s, 0), c + Vector2(-16 * s, sin(t * 12) * 4), Color(col.r, col.g, col.b, 0.4), 2)

static func turret(ci, col, aim, s = 1.0):
	var body = Color(0.15, 0.17, 0.22)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2(8, -12), Vector2(-8, -12)]), body)
	var c = Vector2(0, -16)
	ci.draw_line(c, c + Vector2.from_angle(aim) * 24, body.lightened(0.15), 6)
	ci.draw_circle(c, 9, body.lightened(0.08))
	ci.draw_circle(c, 3.5, col)

# ---------------------------------------------------------------- portraits
static func portrait(ci, who, r: Rect2, mood, t, talking, seed = 0):
	var ch = DB.chars.get(who, DB.chars.npc)
	var col = DB.C(ch.col)
	var u = r.size.y / 100.0
	ci.draw_rect(r, Color(0.02, 0.03, 0.06, 0.96))
	for i in 6:
		ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y * i / 6.0), Vector2(r.size.x, r.size.y / 6.0)), Color(col.r, col.g, col.b, 0.02 + 0.022 * i))
	var c = r.position + r.size * Vector2(0.5, 0.5)
	match ch.style:
		"none": pass
		"sable": _p_sable(ci, c, u, col, t, talking)
		"archivist": _p_archivist(ci, c, u, col, t, talking)
		"echo": _p_echo(ci, c, u, t, talking)
		"bot": _p_bot(ci, c, u, col, t, talking)
		"voice": _p_voice(ci, c, u, col, t, talking)
		"malrek": _p_malrek(ci, c, u, col, t)
		_: _p_human(ci, c, u, ch, mood, t, talking, seed)
	# scanline + frame
	for i in int(r.size.y / 4.0):
		ci.draw_line(r.position + Vector2(0, i * 4), r.position + Vector2(r.size.x, i * 4), Color(0, 0, 0, 0.12), 1)
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.8), false, 2.0)
	ci.draw_line(r.position + Vector2(0, r.size.y), r.position + Vector2(r.size.x * 0.4, r.size.y), col, 4.0)

static func _p_human(ci, c, u, ch, mood, t, talking, seed):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed
	var skin = DB.C(ch.get("skin", "b89070"))
	var hair = DB.C(ch.get("hair", "403830"))
	var acc = DB.C(ch.col)
	var style = ch.style
	if style == "npc" and seed != 0:
		skin = Color.from_hsv(0.06 + rng.randf() * 0.04, 0.3 + rng.randf() * 0.3, 0.45 + rng.randf() * 0.45)
		hair = Color.from_hsv(rng.randf(), 0.2, 0.15 + rng.randf() * 0.5)
		style = ["npc", "npc_hood", "npc_cap", "npc_long"][rng.randi() % 4]
	var hc = c + Vector2(0, -10 * u + sin(t * 1.5) * 0.6 * u)
	var cloth = Color(0.12, 0.13, 0.17)
	match style:
		"kael": cloth = Color(0.16, 0.17, 0.2)
		"lyra": cloth = Color(0.1, 0.2, 0.2)
		"orin": cloth = Color(0.14, 0.16, 0.26)
		"thorne": cloth = Color(0.75, 0.74, 0.7)
		"kestrel": cloth = Color(0.35, 0.18, 0.1)
		"rook": cloth = Color(0.2, 0.22, 0.28)
		"vael": cloth = Color(0.85, 0.82, 0.7)
		"nyx": cloth = Color(0.08, 0.07, 0.12)
		"vesper": cloth = Color(0.5, 0.42, 0.2)
	# shoulders
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-42 * u, 50 * u), c + Vector2(-34 * u, 24 * u), c + Vector2(-12 * u, 14 * u), c + Vector2(12 * u, 14 * u), c + Vector2(34 * u, 24 * u), c + Vector2(42 * u, 50 * u)]), cloth)
	ci.draw_polyline(PackedVector2Array([c + Vector2(-34 * u, 24 * u), c + Vector2(-12 * u, 14 * u), c + Vector2(0, 26 * u), c + Vector2(12 * u, 14 * u), c + Vector2(34 * u, 24 * u)]), acc.darkened(0.2), 1.5 * u)
	if style in ["rook", "kael"]:
		for sx in [-1, 1]: ci.draw_rect(Rect2(c + Vector2(sx * 30 * u - 6 * u, 22 * u), Vector2(12 * u, 4 * u)), acc.darkened(0.3))
	if style == "rook":
		for i in 4: ci.draw_circle(c + Vector2((-22 + i * 5) * u, 36 * u), 1.6 * u, Color(0.9, 0.75, 0.3))
	if style in ["vael", "kestrel", "thorne"]:
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-16 * u, 16 * u), c + Vector2(-9 * u, -2 * u), c + Vector2(-5 * u, 18 * u)]), cloth.lightened(0.15))
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(16 * u, 16 * u), c + Vector2(9 * u, -2 * u), c + Vector2(5 * u, 18 * u)]), cloth.lightened(0.15))
	if style == "orin":
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-16 * u, 10 * u), c + Vector2(16 * u, 10 * u), c + Vector2(20 * u, 22 * u), c + Vector2(-20 * u, 22 * u)]), acc.darkened(0.45))
	# neck + back hair
	if style in ["lyra", "npc_long", "vael", "nyx"]:
		ell(ci, hc + Vector2(0, 2 * u), 22 * u, 26 * u, hair.darkened(0.2))
	if style == "vesper" or style == "npc_hood":
		ell(ci, hc + Vector2(0, 1 * u), 25 * u, 29 * u, cloth.darkened(0.25))
	ci.draw_rect(Rect2(hc + Vector2(-6 * u, 14 * u), Vector2(12 * u, 14 * u)), skin.darkened(0.3))
	# head
	ell(ci, hc, 16 * u, 20 * u, skin)
	ell(ci, hc + Vector2(-6 * u, 0), 10 * u, 20 * u, skin.darkened(0.14), 12, PI * 0.5, PI * 1.5)
	ci.draw_arc(hc, 17 * u, -1.2, 0.9, 12, Color(acc.r, acc.g, acc.b, 0.35), 1.5 * u)
	# hair
	match style:
		"kael":
			ell(ci, hc + Vector2(0, -8 * u), 17 * u, 14 * u, hair, 14, PI, TAU)
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-17 * u, -8 * u), hc + Vector2(-14 * u, 2 * u), hc + Vector2(-12 * u, -8 * u)]), hair)
			for i in 14: ci.draw_circle(hc + Vector2((-9 + rng.randf() * 18) * u, (9 + rng.randf() * 9) * u), 0.6 * u, Color(0, 0, 0, 0.25))
			ci.draw_line(hc + Vector2(4 * u, -12 * u), hc + Vector2(9 * u, 2 * u), skin.lightened(0.25), 1.2 * u)
		"lyra":
			ell(ci, hc + Vector2(0, -7 * u), 18 * u, 16 * u, hair, 14, PI, TAU)
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-18 * u, -8 * u), hc + Vector2(-20 * u, 16 * u), hc + Vector2(-12 * u, 12 * u), hc + Vector2(-13 * u, -6 * u)]), hair)
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(18 * u, -8 * u), hc + Vector2(20 * u, 16 * u), hc + Vector2(13 * u, 10 * u), hc + Vector2(2 * u, -16 * u)]), hair)
			ring(ci, hc + Vector2(7 * u, -3 * u), 5 * u, acc, 1.0 * u, 14)
		"orin":
			for i in 11: ci.draw_circle(hc + Vector2.from_angle(PI + i * PI / 10.0) * 16 * u + Vector2(0, -3 * u), 5 * u, hair)
			ell(ci, hc + Vector2(0, -9 * u), 16 * u, 11 * u, hair, 12, PI, TAU)
		"thorne":
			ell(ci, hc + Vector2(2 * u, -9 * u), 18 * u, 13 * u, hair, 14, PI * 0.95, TAU * 1.02)
			for sx in [-1, 1]: ring(ci, hc + Vector2(sx * 7 * u, -3 * u), 5 * u, Color(0.8, 0.85, 0.9), 1.0 * u, 14)
			ci.draw_line(hc + Vector2(-2 * u, -3 * u), hc + Vector2(2 * u, -3 * u), Color(0.8, 0.85, 0.9), 1.0 * u)
		"kestrel":
			ell(ci, hc + Vector2(3 * u, -9 * u), 17 * u, 14 * u, hair, 14, PI * 1.05, TAU)
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-14 * u, -14 * u), hc + Vector2(-30 * u, -4 * u), hc + Vector2(-24 * u, 10 * u), hc + Vector2(-14 * u, -4 * u)]), hair)
			ci.draw_line(hc + Vector2(-13 * u, 3 * u), hc + Vector2(-9 * u, 9 * u), skin.lightened(0.2), 1.0 * u)
		"rook":
			ell(ci, hc + Vector2(0, -11 * u), 16.5 * u, 10 * u, hair, 14, PI, TAU)
		"vael":
			ell(ci, hc + Vector2(0, -10 * u), 17 * u, 13 * u, hair, 14, PI, TAU)
			ell(ci, hc + Vector2(0, -27 * u), 9 * u, 9 * u, hair)
			ci.draw_arc(hc + Vector2(0, -8 * u), 17 * u, PI * 1.15, PI * 1.85, 10, Color(0.95, 0.8, 0.35), 2.0 * u)
		"nyx":
			ell(ci, hc + Vector2(0, -8 * u), 18 * u, 15 * u, hair, 14, PI, TAU)
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-18 * u, -8 * u), hc + Vector2(-16 * u, 14 * u), hc + Vector2(-4 * u, -2 * u), hc + Vector2(2 * u, -18 * u)]), hair)
			ci.draw_rect(Rect2(hc + Vector2(-2 * u, -6 * u), Vector2(17 * u, 5 * u)), Color(0.05, 0.03, 0.1))
			ci.draw_line(hc + Vector2(0, -3.5 * u), hc + Vector2(14 * u, -3.5 * u), acc, 1.5 * u)
		"vesper":
			ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-19 * u, 8 * u), hc + Vector2(-17 * u, -14 * u), hc + Vector2(0, -24 * u), hc + Vector2(17 * u, -14 * u), hc + Vector2(19 * u, 8 * u), hc + Vector2(13 * u, -10 * u), hc + Vector2(-13 * u, -10 * u)]), cloth.darkened(0.1))
			for i in 12:
				var a = t * 0.3 + i * TAU / 12.0
				ci.draw_circle(hc + Vector2(cos(a) * 30 * u, sin(a) * 30 * u - 4 * u), 1.3 * u, Color(acc.r, acc.g, acc.b, 0.8))
		"npc_hood": pass
		"npc_cap":
			ell(ci, hc + Vector2(0, -10 * u), 17 * u, 11 * u, hair, 12, PI, TAU)
			ci.draw_rect(Rect2(hc + Vector2(-2 * u, -12 * u), Vector2(22 * u, 3 * u)), hair.darkened(0.2))
		_:
			ell(ci, hc + Vector2(0, -8 * u), 17 * u, 14 * u, hair, 14, PI, TAU)
	# face
	var blink = fmod(t + seed % 7, 4.3) < 0.12
	var brow = 0.0
	match mood:
		"angry", "hard", "cold": brow = 0.35
		"sad", "soft", "afraid": brow = -0.3
	var closed = style == "vesper" or blink or mood == "closed"
	if style != "nyx":
		for sx in [-1, 1]:
			var e = hc + Vector2(sx * 7 * u, -3 * u)
			if closed: ci.draw_line(e + Vector2(-3 * u, 0), e + Vector2(3 * u, 0), Color(0.05, 0.04, 0.05), 1.2 * u)
			else:
				ell(ci, e, 3.2 * u, 1.9 * u, Color(0.92, 0.92, 0.9), 8)
				ci.draw_circle(e + Vector2(0.6 * u, 0), 1.6 * u, Color(0.08, 0.07, 0.08))
			ci.draw_line(e + Vector2(-sx * 4 * u, (-5 + brow * 3) * u), e + Vector2(sx * 4 * u, (-5 - brow * 3) * u), hair.darkened(0.3), 1.6 * u)
	ci.draw_line(hc + Vector2(1 * u, -1 * u), hc + Vector2(2 * u, 5 * u), skin.darkened(0.25), 1.0 * u)
	var my = hc + Vector2(0.5 * u, 11 * u)
	if talking:
		ell(ci, my, 3.5 * u, (1.0 + abs(sin(t * 14.0)) * 2.2) * u, Color(0.15, 0.05, 0.06), 8)
	else:
		var curve = 0.0
		if mood in ["wry", "smile", "warm"]: curve = 1.5
		if mood in ["sad", "angry", "hard", "cold"]: curve = -1.2
		ci.draw_polyline(PackedVector2Array([my + Vector2(-4 * u, -curve * u * 0.5), my + Vector2(0, curve * u * 0.3), my + Vector2(4 * u, -curve * u)]), Color(0.2, 0.08, 0.08), 1.2 * u)

static func _p_sable(ci, c, u, col, t, talking):
	var stage = G.sable_stage()
	var organic = (stage - 1) / 4.0
	var hue_shift = Color(col.r, col.g * (1.0 - 0.25 * organic), col.b + 0.25 * organic)
	# outer rings: rigid hexagon early, breathing circles later
	for k in 3:
		var pts = PackedVector2Array()
		var n = 6 if stage == 1 else 48
		var rot = t * 0.2 * (1 if k % 2 == 0 else -1) * (0.2 + organic)
		for i in n + 1:
			var a = rot + i * TAU / n
			var r = (22 + k * 8) * u * (1.0 + organic * 0.07 * sin(a * (3 + k) + t * (1.0 + k * 0.4)))
			pts.append(c + Vector2.from_angle(a) * r)
		ci.draw_polyline(pts, Color(hue_shift.r, hue_shift.g, hue_shift.b, 0.75 - k * 0.2), (2.0 - k * 0.4) * u)
	# the voices she is made of: faint points that appear once she begins to wake
	if stage >= 3:
		for i in 24:
			var a = i * 2.399 + t * 0.07
			var r = (12 + fmod(i * 7.3, 26.0)) * u
			ci.draw_circle(c + Vector2(cos(a), sin(a)) * r, 0.9 * u, Color(1, 0.8, 0.8, 0.25 + 0.2 * sin(t * 1.3 + i)))
	var amp = (7.0 if talking else 1.5 + organic * 2.0) * u
	var wav = PackedVector2Array()
	for i in 25:
		var x = (i - 12) * 1.6 * u
		var env = 1.0 - abs(i - 12) / 12.0
		wav.append(c + Vector2(x, sin(i * 0.9 + t * (12.0 if talking else 2.0)) * amp * env))
	ci.draw_polyline(wav, Color(1, 1, 1, 0.9), 1.6 * u)
	glow(ci, c, 30 * u, Color(hue_shift.r, hue_shift.g, hue_shift.b, 0.25))

static func _p_archivist(ci, c, u, col, t, talking):
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-40 * u, 50 * u), c + Vector2(-24 * u, -10 * u), c + Vector2(0, -36 * u), c + Vector2(24 * u, -10 * u), c + Vector2(40 * u, 50 * u)]), Color(0.06, 0.09, 0.09))
	ell(ci, c + Vector2(0, -6 * u), 15 * u, 20 * u, Color(0.01, 0.02, 0.02))
	for k in 3:
		var pts = PackedVector2Array()
		for i in 4: pts.append(c + Vector2(0, -6 * u) + Vector2.from_angle(t * (0.4 + k * 0.3) + i * TAU / 3.0) * (11 - k * 3) * u)
		ci.draw_polyline(pts, Color(col.r, col.g, col.b, 0.9 - k * 0.2), 1.2 * u)
	ci.draw_circle(c + Vector2(0, -6 * u), (1.6 + (1.2 * abs(sin(t * 10)) if talking else 0.0)) * u, Color(1, 1, 1))

static func _p_echo(ci, c, u, t, talking):
	for i in 9:
		var a = i * 0.7 + t * 0.15
		var o = c + Vector2(cos(a) * 14 * u, sin(a * 1.3) * 10 * u)
		ci.draw_arc(o, 15 * u, 0, TAU, 20, Color(1, 1, 1, 0.07 + 0.03 * sin(t + i)), 1.2 * u)
		ci.draw_line(o + Vector2(-5 * u, -3 * u), o + Vector2(-2 * u, -3 * u), Color(1, 1, 1, 0.12), u)
		ci.draw_line(o + Vector2(2 * u, -3 * u), o + Vector2(5 * u, -3 * u), Color(1, 1, 1, 0.12), u)
	ring(ci, c, (20 + (3 * sin(t * 9) if talking else 0.0)) * u, Color(1, 1, 1, 0.9), 2.0 * u, 40)
	glow(ci, c, 40 * u, Color(1, 0.95, 0.85, 0.35))

static func _p_bot(ci, c, u, col, t, talking):
	ci.draw_rect(Rect2(c + Vector2(-26 * u, 18 * u), Vector2(52 * u, 32 * u)), Color(0.18, 0.2, 0.22))
	ci.draw_rect(Rect2(c + Vector2(-18 * u, -26 * u), Vector2(36 * u, 38 * u)), Color(0.25, 0.28, 0.3))
	ci.draw_line(c + Vector2(0, -26 * u), c + Vector2(4 * u, -38 * u), Color(0.4, 0.4, 0.4), 1.5 * u)
	for sx in [-1, 1]: ci.draw_circle(c + Vector2(sx * 8 * u, -12 * u), 4.5 * u, col if fmod(t, 3.7) > 0.1 else col.darkened(0.7))
	for i in 5: ci.draw_rect(Rect2(c + Vector2((-10 + i * 4.4) * u, 2 * u), Vector2(2.5 * u, (2 + (4 * abs(sin(t * 12 + i)) if talking else 0.0)) * u)), col.darkened(0.2))

static func _p_voice(ci, c, u, col, t, talking):
	for i in 17:
		var h = (4 + 22 * abs(sin(i * 1.7 + t * (9.0 if talking else 1.0))) * (1.0 - abs(i - 8) / 9.0)) * u
		ci.draw_rect(Rect2(c + Vector2((-34 + i * 4) * u, -h), Vector2(2.4 * u, h * 2)), Color(col.r, col.g, col.b, 0.8))

static func _p_malrek(ci, c, u, col, t):
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-44 * u, 50 * u), c + Vector2(-30 * u, 10 * u), c + Vector2(0, -38 * u), c + Vector2(30 * u, 10 * u), c + Vector2(44 * u, 50 * u)]), Color(0.1, 0.03, 0.03))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-13 * u, -24 * u), c + Vector2(13 * u, -24 * u), c + Vector2(15 * u, 2 * u), c + Vector2(0, 16 * u), c + Vector2(-15 * u, 2 * u)]), Color(0.16, 0.16, 0.18))
	ci.draw_line(c + Vector2(0, -20 * u), c + Vector2(0, 10 * u), col, 2.2 * u)
	ci.draw_line(c + Vector2(-9 * u, -8 * u), c + Vector2(9 * u, -8 * u), Color(col.r, col.g, col.b, 0.5 + 0.3 * sin(t * 2)), 1.6 * u)
	glow(ci, c + Vector2(0, -6 * u), 22 * u, Color(col.r, col.g, col.b, 0.25))
