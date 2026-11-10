extends RefCounted
# Conservative tile graph, not a replacement for the real controller smoke test.
# Nodes are empty cells immediately above safe support; gates (G / tile 8) are
# open. One-way platforms support feet but do not obstruct an ascending jump.
const SUPPORT = [1, 2, 5, 7, 9]
const BLOCKING = [1, 5, 7, 9]

static func tile(room, p):
	if p.x < 0 or p.y < 0 or p.x >= room.W or p.y >= room.H:
		return 1
	return int(room.grid[p.y * room.W + p.x])

static func standable(room, p):
	return tile(room, p) in [0, 4, 6, 8] and tile(room, p + Vector2i.DOWN) in SUPPORT

static func nodes(room):
	var out = {}
	for x in room.W:
		for y in range(room.H - 1):
			var p = Vector2i(x, y)
			if standable(room, p): out[p] = true
	return out

static func edge_clear(room, a, b):
	var dx = abs(b.x - a.x)
	var rise = a.y - b.y
	if dx > 6 or rise > 3: return false
	# Test the swept point at quarter-tile intervals. Use a bounded jump arc;
	# drops can fall farther than three tiles, but cannot cross a solid wall.
	var arc = min(1.5, 3.0 - max(0, rise)) if dx > 1 or rise != 0 else 0.0
	var count = max(4, int(Vector2(a).distance_to(Vector2(b)) * 8.0))
	for i in range(1, count):
		var t = float(i) / count
		var point = Vector2(a).lerp(Vector2(b), t) + Vector2(0, -4.0 * arc * t * (1.0 - t))
		var cell = Vector2i(floor(point.x + 0.5), floor(point.y + 0.5))
		if tile(room, cell) in BLOCKING or tile(room, cell) in [3, 10, 12]: return false
	return true

static func reach(room, spawn):
	var available = nodes(room)
	# Spawn may be above the floor: land vertically before searching.
	var start = Vector2i(spawn)
	while start.y < room.H - 1 and not available.has(start):
		if tile(room, start) in BLOCKING or tile(room, start) in [3, 10, 12]:
			return {"ok": false, "reason": "spawn is blocked or hazardous", "visited": 0}
		start.y += 1
	if not available.has(start):
		return {"ok": false, "reason": "no safe support below spawn", "visited": 0}
	var columns = {}
	for p in available:
		if not columns.has(p.x): columns[p.x] = []
		columns[p.x].append(p)
	var queue = [start]
	var seen = {start: true}
	var index = 0
	var farthest = start.x
	while index < queue.size():
		var a = queue[index]
		index += 1
		farthest = max(farthest, a.x)
		if a.x == room.W - 1:
			return {"ok": true, "reason": "right edge reached", "visited": seen.size()}
		for x in range(max(0, a.x - 6), min(room.W, a.x + 7)):
			for b in columns.get(x, []):
				if not seen.has(b) and edge_clear(room, a, b):
					seen[b] = true
					queue.append(b)
	return {"ok": false, "reason": "stopped at column %d of %d" % [farthest, room.W - 1], "visited": seen.size()}
