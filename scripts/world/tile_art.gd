class_name TileArt
extends RefCounted
## 程序生成的像素美术：图块图集、墙壁图集和道具图标全部用代码"画"出来，不使用任何外部素材。
## 每种图块画 4 个变体（随机种子不同），渲染时按坐标挑一个，地面看起来不会太重复。

const TS := 16
const VARIANTS := 4
const WOOD := Color(0.55, 0.36, 0.2)

static var _icon_cache := {}


static func build_tile_atlas() -> Image:
	var img := Image.create_empty(TS * TileDB.COUNT, TS * VARIANTS, false, Image.FORMAT_RGBA8)
	for id in range(1, TileDB.COUNT):
		for v in VARIANTS:
			paint_tile(img, id, Vector2i(id * TS, v * TS), _rng(id * 1009 + v * 7919 + 13))
	return img


static func build_wall_atlas() -> Image:
	var img := Image.create_empty(TS * TileDB.WALL_COUNT, TS * VARIANTS, false, Image.FORMAT_RGBA8)
	for id in range(1, TileDB.WALL_COUNT):
		var base: Color = TileDB.WALL_COLORS[id]
		for v in VARIANTS:
			var rng := _rng(id * 577 + v * 31)
			var o := Vector2i(id * TS, v * TS)
			_noise_fill(img, o, base, rng, 0.03)
			# 横向的砌缝，让背景墙和前景方块一眼能分开
			for y in [4, 11]:
				for x in TS:
					if rng.randf() < 0.7:
						_px(img, o, x, y, base.darkened(0.25))
	return img


## 道具图标（16×16）。能放置的道具直接用对应图块的样子。
static func icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	var d := ItemDB.get_def(id)
	if d.has("place") and not d.has("icon"):
		var tile_id := int(d.place)
		paint_tile(img, tile_id, Vector2i.ZERO, _rng(tile_id * 1009 + 13))
	else:
		paint_icon(img, String(d.get("icon", "")), d.get("color", Color.MAGENTA))
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[id] = tex
	return tex


# ---------------------------------------------------------------- 绘图小工具

static func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


static func _px(img: Image, o: Vector2i, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= TS or y >= TS:
		return
	img.set_pixel(o.x + x, o.y + y, c)


static func _jitter(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
	var k := rng.randf_range(-amount, amount)
	return Color(clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k, 0, 1), c.a)


static func _noise_fill(img: Image, o: Vector2i, c: Color, rng: RandomNumberGenerator, amount: float) -> void:
	for y in TS:
		for x in TS:
			_px(img, o, x, y, _jitter(c, rng, amount))


static func _rect(img: Image, o: Vector2i, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, o, x, y, c)


static func _disc(img: Image, o: Vector2i, center: Vector2, r: float, c: Color) -> void:
	for y in TS:
		for x in TS:
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				_px(img, o, x, y, c)


static func _line(img: Image, o: Vector2i, a: Vector2i, b: Vector2i, c: Color) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in steps + 1:
		var t := 0.0 if steps == 0 else float(i) / steps
		_px(img, o, roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)), c)


static func _speckle(img: Image, o: Vector2i, c: Color, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		_px(img, o, rng.randi() % TS, rng.randi() % TS, c)


# ---------------------------------------------------------------- 图块

static func paint_tile(img: Image, id: int, o: Vector2i, rng: RandomNumberGenerator) -> void:
	var d := TileDB.def(id)
	var c: Color = d.get("color", Color.MAGENTA)
	match String(d.get("art", "noise")):
		"noise":
			_noise_fill(img, o, c, rng, 0.04)
			_speckle(img, o, c.darkened(0.25), rng, 7)
			_speckle(img, o, c.lightened(0.15), rng, 4)
		"grass":
			_noise_fill(img, o, c, rng, 0.04)
			_speckle(img, o, c.darkened(0.25), rng, 5)
			var g := Color(0.33, 0.66, 0.26)
			for x in TS:
				var h := 3 + rng.randi() % 3
				for y in h:
					_px(img, o, x, y, _jitter(g if y < h - 1 else g.darkened(0.25), rng, 0.04))
		"ore":
			var base := Color(TileDB.def(int(d.get("base", TileDB.STONE))).color)
			_noise_fill(img, o, base, rng, 0.04)
			_speckle(img, o, base.darkened(0.25), rng, 5)
			for i in 4:
				var cx := rng.randi_range(2, 12)
				var cy := rng.randi_range(2, 12)
				for p in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
					if rng.randf() < 0.85:
						_px(img, o, cx + p.x, cy + p.y, _jitter(c, rng, 0.06))
				_px(img, o, cx, cy, c.lightened(0.35))
		"trunk":
			for y in TS:
				for x in range(3, 13):
					var k := c
					if (x + y / 5) % 3 == 0:
						k = c.darkened(0.2)
					if x == 3 or x == 12:
						k = c.darkened(0.4)
					_px(img, o, x, y, _jitter(k, rng, 0.03))
		"leaves":
			_noise_fill(img, o, c, rng, 0.05)
			_speckle(img, o, c.darkened(0.35), rng, 12)
			_speckle(img, o, c.lightened(0.2), rng, 6)
		"planks":
			for y in TS:
				for x in TS:
					var k := c
					if y % 4 == 3:
						k = c.darkened(0.35)
					elif (x + (y / 4) * 5) % 8 == 0:
						k = c.darkened(0.2)
					_px(img, o, x, y, _jitter(k, rng, 0.03))
		"brick":
			for y in TS:
				for x in TS:
					var off := 4 if (y / 4) % 2 == 1 else 0
					var k := c
					if y % 4 == 3 or (x + off) % 8 == 7:
						k = c.darkened(0.4)
					_px(img, o, x, y, _jitter(k, rng, 0.03))
		"glass":
			for y in TS:
				for x in TS:
					var k := Color(c.r, c.g, c.b, 0.22)
					if x == 0 or y == 0 or x == TS - 1 or y == TS - 1:
						k.a = 0.85
					_px(img, o, x, y, k)
			_line(img, o, Vector2i(3, 9), Vector2i(9, 3), Color(1, 1, 1, 0.7))
			_line(img, o, Vector2i(5, 11), Vector2i(7, 9), Color(1, 1, 1, 0.5))
		"torch":
			_rect(img, o, 7, 7, 7, 15, WOOD)
			_rect(img, o, 8, 7, 8, 15, WOOD.darkened(0.3))
			_rect(img, o, 6, 3, 9, 6, Color(1.0, 0.55, 0.15))
			_rect(img, o, 7, 2, 8, 5, Color(1.0, 0.85, 0.3))
			_px(img, o, 7, 4, Color(1, 1, 0.85))
			_px(img, o, 8, 1, Color(1.0, 0.7, 0.2))
		"workbench":
			_rect(img, o, 0, 6, 15, 8, c)
			_rect(img, o, 0, 6, 15, 6, c.lightened(0.2))
			_rect(img, o, 1, 9, 2, 15, c.darkened(0.3))
			_rect(img, o, 13, 9, 14, 15, c.darkened(0.3))
			_rect(img, o, 3, 12, 12, 12, c.darkened(0.2))
			# 桌上的小锤子
			_rect(img, o, 9, 2, 13, 3, Color(0.6, 0.6, 0.65))
			_rect(img, o, 10, 4, 10, 5, WOOD)
		"furnace":
			_rect(img, o, 1, 2, 14, 15, c)
			for y in range(2, 16):
				for x in range(1, 15):
					if (y % 4 == 1) or ((x + (y / 4) * 3) % 6 == 0):
						_px(img, o, x, y, c.darkened(0.3))
			_rect(img, o, 4, 8, 11, 13, Color(0.12, 0.08, 0.06))
			_rect(img, o, 5, 10, 10, 13, Color(1.0, 0.45, 0.12))
			_rect(img, o, 6, 11, 9, 13, Color(1.0, 0.8, 0.3))
			_rect(img, o, 6, 0, 9, 1, c.darkened(0.2))
		"anvil":
			_rect(img, o, 1, 6, 14, 8, c)
			_rect(img, o, 0, 6, 0, 7, c)
			_rect(img, o, 1, 6, 14, 6, c.lightened(0.3))
			_rect(img, o, 5, 9, 10, 11, c.darkened(0.15))
			_rect(img, o, 3, 12, 12, 15, c.darkened(0.3))
		"chest":
			_rect(img, o, 1, 4, 14, 15, c)
			_rect(img, o, 1, 4, 14, 7, c.darkened(0.2))
			_rect(img, o, 1, 4, 14, 4, c.lightened(0.15))
			var gold := Color(1.0, 0.8, 0.3)
			_rect(img, o, 1, 8, 14, 8, gold)
			_rect(img, o, 1, 4, 1, 15, gold.darkened(0.2))
			_rect(img, o, 14, 4, 14, 15, gold.darkened(0.2))
			_rect(img, o, 7, 8, 8, 11, gold)
			_px(img, o, 7, 10, Color(0.2, 0.12, 0.05))
			# 符文
			_px(img, o, 4, 12, Color(0.5, 1.0, 0.9))
			_px(img, o, 11, 12, Color(0.5, 1.0, 0.9))
		"mushroom":
			_rect(img, o, 7, 10, 8, 15, Color(0.93, 0.88, 0.78))
			for y in range(5, 11):
				for x in range(3, 13):
					if Vector2(x + 0.5, (y + 0.5) * 1.5).distance_to(Vector2(8, 15)) <= 5.6:
						_px(img, o, x, y, _jitter(c, rng, 0.04))
			_px(img, o, 5, 8, Color(1, 0.95, 0.85))
			_px(img, o, 9, 6, Color(1, 0.95, 0.85))
			_px(img, o, 10, 8, Color(1, 0.95, 0.85))
		"crystal":
			var shards := [[8, 2, 1], [5, 6, 1], [11, 7, 1]]
			for s in shards:
				for y in range(s[1], 16):
					for dx in range(-s[2], s[2] + 1):
						var k := c if dx <= 0 else c.darkened(0.3)
						if y == s[1]:
							k = c.lightened(0.5)
						_px(img, o, s[0] + dx, y, k)
		"basalt":
			_noise_fill(img, o, c, rng, 0.03)
			_speckle(img, o, c.lightened(0.15), rng, 6)
			var x := rng.randi() % TS
			for y in TS:
				if rng.randf() < 0.4:
					x = clampi(x + rng.randi_range(-1, 1), 0, TS - 1)
				if rng.randf() < 0.6:
					_px(img, o, x, y, c.darkened(0.4))
		"bedrock":
			_noise_fill(img, o, c, rng, 0.03)
			for i in 3:
				var y := rng.randi() % TS
				for x in TS:
					if rng.randf() < 0.7:
						_px(img, o, x, y, Color(0.22, 0.12, 0.25))
		_:
			_rect(img, o, 0, 0, TS - 1, TS - 1, Color.MAGENTA)


# ---------------------------------------------------------------- 道具图标

static func paint_icon(img: Image, shape: String, c: Color) -> void:
	var o := Vector2i.ZERO
	match shape:
		"pickaxe":
			_line(img, o, Vector2i(2, 14), Vector2i(10, 6), WOOD)
			_line(img, o, Vector2i(3, 14), Vector2i(11, 6), WOOD.darkened(0.3))
			var arc := [Vector2i(3, 5), Vector2i(4, 4), Vector2i(5, 3), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2),
				Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 4), Vector2i(12, 5), Vector2i(12, 6), Vector2i(13, 7),
				Vector2i(13, 8), Vector2i(13, 9), Vector2i(14, 10)]
			for p in arc:
				_px(img, o, p.x, p.y, c)
				_px(img, o, p.x, p.y + 1, c.darkened(0.3))
			_px(img, o, 7, 2, c.lightened(0.4))
		"axe":
			_line(img, o, Vector2i(3, 14), Vector2i(10, 3), WOOD)
			_line(img, o, Vector2i(4, 14), Vector2i(11, 3), WOOD.darkened(0.3))
			_rect(img, o, 9, 2, 13, 8, c)
			_rect(img, o, 14, 3, 14, 7, c.lightened(0.4))
			_px(img, o, 13, 2, Color(0, 0, 0, 0))
			_px(img, o, 13, 8, Color(0, 0, 0, 0))
			_rect(img, o, 9, 6, 12, 8, c.darkened(0.25))
		"drill":
			_rect(img, o, 1, 9, 4, 12, Color(0.25, 0.25, 0.3))
			_rect(img, o, 4, 6, 10, 11, c)
			_rect(img, o, 4, 6, 10, 6, c.lightened(0.3))
			for i in 5:
				_rect(img, o, 11 + i, 7 + i / 2, 11 + i, 10 - i / 2, Color(0.8, 0.82, 0.88) if i % 2 == 0 else Color(0.6, 0.62, 0.7))
		"bar":
			for y in range(6, 12):
				var half := (y - 6) / 2
				for x in range(4 - half, 12 + half):
					var k := c
					if y == 6:
						k = c.lightened(0.35)
					elif y == 11:
						k = c.darkened(0.35)
					_px(img, o, x, y, k)
		"potion", "bottle":
			var glass := Color(0.85, 0.95, 1.0, 0.75)
			_rect(img, o, 6, 2, 9, 4, glass)
			if shape == "potion":
				_rect(img, o, 6, 1, 9, 1, WOOD)
			_disc(img, o, Vector2(8, 10.5), 4.8, glass)
			if shape == "potion":
				for y in range(8, 16):
					for x in TS:
						if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 10.5)) <= 3.9:
							_px(img, o, x, y, c)
			_px(img, o, 6, 8, Color(1, 1, 1, 0.95))
		"bomb":
			_disc(img, o, Vector2(7.5, 9.5), 5.2, c)
			_px(img, o, 5, 7, c.lightened(0.5))
			_px(img, o, 6, 6, c.lightened(0.35))
			_line(img, o, Vector2i(10, 5), Vector2i(12, 2), WOOD)
			_px(img, o, 13, 1, Color(1.0, 0.95, 0.4))
			_px(img, o, 12, 1, Color(1.0, 0.6, 0.2))
			_px(img, o, 13, 2, Color(1.0, 0.6, 0.2))
		"scroll":
			_rect(img, o, 3, 4, 12, 11, c)
			_rect(img, o, 2, 3, 3, 12, c.darkened(0.25))
			_rect(img, o, 12, 3, 13, 12, c.darkened(0.25))
			_rect(img, o, 5, 6, 10, 6, c.darkened(0.45))
			_rect(img, o, 5, 8, 9, 8, c.darkened(0.45))
			_disc(img, o, Vector2(9, 10.5), 1.6, Color(0.8, 0.15, 0.15))
		"apple", "fruit":
			_disc(img, o, Vector2(8, 9.5), 5.2, c)
			_px(img, o, 5, 7, c.lightened(0.5))
			_px(img, o, 6, 6, c.lightened(0.35))
			if shape == "fruit":
				_disc(img, o, Vector2(8, 10), 2.2, c.lightened(0.35))
			_line(img, o, Vector2i(8, 2), Vector2i(8, 4), WOOD)
			_rect(img, o, 9, 2, 10, 3, Color(0.3, 0.7, 0.25))
		"roast":
			_rect(img, o, 7, 10, 8, 14, Color(0.85, 0.75, 0.55))
			_disc(img, o, Vector2(8, 8.5), 4.5, c)
			_rect(img, o, 3, 10, 13, 15, Color(0, 0, 0, 0))
			_rect(img, o, 7, 10, 8, 14, Color(0.85, 0.75, 0.55))
			_px(img, o, 6, 6, c.darkened(0.4))
			_px(img, o, 9, 7, c.darkened(0.4))
			_line(img, o, Vector2i(2, 14), Vector2i(13, 14), WOOD.darkened(0.2))
		"shard":
			for y in range(2, 15):
				var half := int((6 - absi(y - 8)) * 0.6)
				for x in range(8 - half, 8 + half + 1):
					_px(img, o, x, y, c.lightened(0.25) if x < 8 else c.darkened(0.15))
			_px(img, o, 7, 5, Color.WHITE)
		"log":
			_rect(img, o, 2, 5, 13, 11, WOOD)
			_rect(img, o, 2, 5, 13, 5, WOOD.lightened(0.15))
			_rect(img, o, 2, 8, 9, 8, WOOD.darkened(0.25))
			_rect(img, o, 12, 5, 13, 11, Color(0.82, 0.66, 0.45))
			_px(img, o, 12, 8, WOOD)
		"boots":
			_rect(img, o, 4, 2, 8, 10, c)
			_rect(img, o, 4, 10, 12, 13, c)
			_rect(img, o, 4, 4, 8, 4, c.lightened(0.4))
			_rect(img, o, 4, 14, 13, 14, c.darkened(0.45))
			_px(img, o, 12, 10, Color(0, 0, 0, 0))
		"amulet":
			_line(img, o, Vector2i(3, 1), Vector2i(7, 8), Color(0.9, 0.8, 0.45))
			_line(img, o, Vector2i(12, 1), Vector2i(8, 8), Color(0.9, 0.8, 0.45))
			_disc(img, o, Vector2(8, 11), 3.2, c)
			_px(img, o, 7, 10, Color.WHITE)
		"feather":
			_line(img, o, Vector2i(3, 14), Vector2i(12, 2), c.darkened(0.3))
			for i in range(2, 10):
				var p := Vector2i(3 + i, 14 - int(i * 1.33))
				_line(img, o, p, p + Vector2i(-2, -1), c)
				_line(img, o, p, p + Vector2i(1, 2), c.darkened(0.1))
		"glove":
			_rect(img, o, 4, 6, 11, 12, c)
			for fx in [4, 6, 8, 10]:
				_rect(img, o, fx, 2, fx + 1, 6, c.lightened(0.1) if fx % 4 == 0 else c)
			_rect(img, o, 2, 8, 3, 10, c)
			_rect(img, o, 4, 12, 11, 14, c.darkened(0.35))
		"bracer":
			for y in TS:
				for x in TS:
					var dist := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 9))
					if dist <= 5.5 and dist >= 3.3:
						_px(img, o, x, y, c if y < 9 else c.darkened(0.25))
			_disc(img, o, Vector2(8, 4), 1.7, Color(0.4, 1.0, 0.9))
		"core":
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_line(img, o, Vector2i(8, 8), Vector2i(8, 8) + dir * 7, c)
			for dir in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				_line(img, o, Vector2i(8, 8), Vector2i(8, 8) + dir * 4, c.darkened(0.15))
			_disc(img, o, Vector2(8.5, 8.5), 3.3, c.lightened(0.3))
			_px(img, o, 7, 7, Color.WHITE)
		_:
			_rect(img, o, 2, 2, 13, 13, Color.MAGENTA)
