class_name WorldGen
extends RefCounted
## 程序化世界生成。同一个种子永远生成同一个世界。
## 从上到下的分层：天空 → 地表（草地/泥土/沙漠）→ 地下（石头夹泥土）→ 洞穴层（大溶洞）→ 深渊（玄武岩）→ 基岩
## 从左到右的生物群系：出生点在中间（森林），雪原和丛林分在两边（一直延伸到深渊上方），
## 沙漠夹在中间和其中一边之间；洞穴层里还藏着几个发光的水晶洞
## 步骤：
##   1. 每列算地表高度（两层噪声叠加，出生点附近压平）
##   2. 逐格填充泥土/石头/沙子/玄武岩和背景墙，用噪声挖出隧道和大溶洞
##   3. 挖几个通往地下的天然洞口
##   4. 地表泥土长草，种树
##   5. 撒矿石、蘑菇、灵晶簇和遗迹宝匣
##   6. 地表湖泊、洞穴水潭、深处的熔岩池（生成时就是静止的，不占模拟时间）
##   7. 选出生点

static func generate(width: int, height: int, seed_value: int) -> WorldData:
	var w := WorldData.new(width, height)
	w.seed_value = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var surface_base := int(height * 0.26)
	var rock_y := int(height * 0.36)
	var cavern_y := int(height * 0.52)
	var underworld_y := int(height * 0.86)
	w.layers = {"surface": surface_base, "rock": rock_y, "cavern": cavern_y, "underworld": underworld_y}

	var T := w.tiles   # 局部副本，最后再写回去（比每次走成员访问快）
	var WL := w.walls
	var LQ := w.liquid

	# ---------- 1. 地表高度 ----------
	var n_hill := _noise(seed_value, 0.0035, 3)
	var n_bump := _noise(seed_value + 1, 0.03, 2)
	var n_dirt := _noise(seed_value + 2, 0.05, 1)
	var surface := PackedInt32Array()
	surface.resize(width)
	var dirt_depth := PackedInt32Array()
	dirt_depth.resize(width)
	var uw_off := PackedInt32Array()
	uw_off.resize(width)
	var cx := width / 2
	# 生物群系布局
	var snow_left := rng.randf() < 0.5
	var snow_c := int(width * (0.18 if snow_left else 0.82))
	var jungle_c := int(width * (0.8 if snow_left else 0.2))
	var snow_half := maxi(30, int(width * 0.06))
	var jungle_half := maxi(35, int(width * 0.07))
	var desert_w := maxi(40, int(width * 0.07))
	var desert_x0 := int(width * (0.33 if rng.randf() < 0.5 else 0.6))
	var desert_x1 := desert_x0 + desert_w
	var biome_cols := PackedByteArray()
	biome_cols.resize(width)
	for x in width:
		var j := int(n_bump.get_noise_1d(x * 0.3) * 6.0)   # 边界弯弯曲曲
		var b := WorldData.B_FOREST
		if absi(x - snow_c) + j < snow_half:
			b = WorldData.B_SNOW
		elif absi(x - jungle_c) + j < jungle_half:
			b = WorldData.B_JUNGLE
		elif x >= desert_x0 and x < desert_x1:
			b = WorldData.B_DESERT
		biome_cols[x] = b
	w.biome_cols = biome_cols
	for x in width:
		var h := surface_base + n_hill.get_noise_1d(x) * height * 0.06 + n_bump.get_noise_1d(x) * 4.0
		if biome_cols[x] == WorldData.B_DESERT:
			h = lerpf(h, surface_base + 4.0 + n_bump.get_noise_1d(x * 0.5) * 3.0, 0.6)
		elif biome_cols[x] == WorldData.B_JUNGLE:
			h += n_bump.get_noise_1d(x * 1.7) * 5.0      # 丛林更崎岖
		h = lerpf(surface_base, h, clampf(absf(x - cx) / 60.0, 0.0, 1.0))  # 出生点附近压平
		surface[x] = int(h)
		dirt_depth[x] = int(10.0 + (n_dirt.get_noise_1d(x) + 1.0) * 6.0)
		uw_off[x] = int(n_bump.get_noise_1d(x * 2.0) * 5.0)
	w.surface = surface

	# ---------- 2. 填充 + 洞穴 ----------
	# 噪声图一次性在引擎内部（C++）算好，比逐格调用快得多。值是 0~255，128 大约是噪声的 0。
	var tun := _noise(seed_value + 11, 0.018, 2).get_image(width, height).get_data()
	var cav := _noise(seed_value + 23, 0.008, 3).get_image(width, height).get_data()
	var patch := _noise(seed_value + 37, 0.06, 1).get_image(width, height).get_data()

	for x in width:
		var s := surface[x]
		var dd := dirt_depth[x]
		var b := biome_cols[x]
		var desert := b == WorldData.B_DESERT
		var uw := underworld_y + uw_off[x]
		var idx := s * width + x
		for y in range(s, height):
			var d := y - s
			var t := TileDB.STONE
			var wall := TileDB.WALL_STONE
			var p := patch[idx]
			if y >= height - 3 or (y >= height - 7 and p > 120):
				T[idx] = TileDB.BEDROCK
				idx += width
				continue
			if y >= uw:
				t = TileDB.BASALT
				wall = TileDB.WALL_NONE
			elif b == WorldData.B_JUNGLE:
				wall = TileDB.WALL_MUD
				t = TileDB.MUD if d < dd + 6 or p > 115 else TileDB.STONE
			elif b == WorldData.B_SNOW:
				wall = TileDB.WALL_ICE
				if d < dd or p < 70:
					t = TileDB.SNOW
				elif p > 150:
					t = TileDB.ICE
			elif d < dd:
				t = TileDB.SAND if desert else TileDB.DIRT
				wall = TileDB.WALL_DIRT
			elif desert and d < dd + 12:
				t = TileDB.SAND
				wall = TileDB.WALL_DIRT
			elif y < rock_y:
				if p > 150:
					t = TileDB.DIRT
					wall = TileDB.WALL_DIRT
			elif p > 205:
				t = TileDB.DIRT
			if d < 3:
				wall = TileDB.WALL_NONE
			# 洞穴
			var air := false
			if d > 4:
				var tw := 5 + mini(d, 160) / 14     # 越深隧道越宽
				if absi(tun[idx] - 128) < tw:
					air = true
				elif y >= uw:
					air = cav[idx] > 135              # 深渊：大片空腔
				elif y > cavern_y:
					air = cav[idx] > 178 - mini((y - cavern_y) / 6, 28)
			T[idx] = TileDB.AIR if air else t
			WL[idx] = wall
			idx += width

	# ---------- 3. 天然洞口 ----------
	var entrances := maxi(2, width / 380)
	for i in entrances:
		var ex := rng.randi_range(20, width - 20)
		if absi(ex - cx) < 80:
			continue
		var ey := surface[ex] - 2
		var shaft_len := rng.randi_range(40, 90)
		var fx := float(ex)
		for step in shaft_len:
			fx += rng.randf_range(-0.8, 0.8)
			var r := 1 + (step % 7) / 4
			for dy in range(-r, r + 1):
				for dx in range(-r - 1, r + 2):
					var xx := int(fx) + dx
					var yy := ey + step + dy
					if xx > 1 and xx < width - 2 and yy > 0 and yy < underworld_y:
						T[yy * width + xx] = TileDB.AIR

	# ---------- 3.2 水晶洞 ----------
	var crystal_caves := []
	for i in maxi(2, width / 500):
		var ccx := rng.randi_range(40, width - 40)
		var ccy := rng.randi_range(cavern_y + 20, underworld_y - 30)
		var rx := rng.randi_range(14, 24)
		var ry := rng.randi_range(9, 15)
		crystal_caves.append(Rect2i(ccx - rx, ccy - ry, rx * 2, ry * 2))
		for y in range(ccy - int(ry * 1.4) - 1, ccy + int(ry * 1.4) + 2):
			for x in range(ccx - int(rx * 1.4) - 1, ccx + int(rx * 1.4) + 2):
				if x < 1 or x >= width - 1 or y < 1 or y >= height - 8:
					continue
				var idx := y * width + x
				var e := pow(float(x - ccx) / rx, 2.0) + pow(float(y - ccy) / ry, 2.0) + (patch[idx] - 128) / 400.0
				if e < 1.0:
					T[idx] = TileDB.AIR
					WL[idx] = TileDB.WALL_CRYSTAL
				elif e < 1.45:
					var r := rng.randf()
					T[idx] = TileDB.CRYSTAL_BLOCK if r < 0.5 else (TileDB.PRISM_ORE if r < 0.6 else TileDB.STONE)
					WL[idx] = TileDB.WALL_CRYSTAL

	# ---------- 3.5 地表湖泊 ----------
	var lakes := maxi(1, width / 700)
	for i in lakes:
		var lx := rng.randi_range(60, width - 60)
		if absi(lx - cx) < 90 or (lx > desert_x0 - 40 and lx < desert_x1 + 40):
			continue
		var half := rng.randi_range(10, 20)
		var depth := rng.randi_range(5, 9)
		var water_y := surface[lx] + 2
		for x in range(lx - half, lx + half + 1):
			var k := 1.0 - pow(float(x - lx) / half, 2.0)
			var d := int(depth * sqrt(maxf(k, 0.0)))
			for y in range(mini(surface[x], water_y) - 1, water_y + d + 1):
				var idx := y * width + x
				if y <= water_y + d and y >= water_y:
					T[idx] = TileDB.AIR
					WL[idx] = TileDB.WALL_NONE
					LQ[idx] = (WorldData.LIQ_WATER << 4) | WorldData.LIQ_MAX
				elif y < water_y:
					T[idx] = TileDB.AIR   # 湖岸以上清空
					WL[idx] = TileDB.WALL_NONE
			# 湖底铺沙
			for y in range(water_y + d + 1, water_y + d + 3):
				T[y * width + x] = TileDB.SAND
		# 湖两边如果比水面低，用泥土垫高，免得一开始就漏水
		for x in [lx - half - 1, lx + half + 1, lx - half - 2, lx + half + 2]:
			for y in range(water_y, water_y + 3):
				if T[y * width + x] == TileDB.AIR:
					T[y * width + x] = TileDB.DIRT

	# ---------- 4. 草地和树 ----------
	var tops := PackedInt32Array()
	tops.resize(width)
	for x in width:
		tops[x] = -1
		for y in range(maxi(0, surface[x] - 2), mini(height, surface[x] + 30)):
			var t := T[y * width + x]
			if t != TileDB.AIR:
				if t == TileDB.DIRT:
					T[y * width + x] = TileDB.GRASS
				elif t == TileDB.MUD:
					T[y * width + x] = TileDB.JUNGLE_GRASS
				tops[x] = y
				break
	# 地下丛林：泥浆露在洞里的一面也长草
	for x in width:
		if biome_cols[x] != WorldData.B_JUNGLE:
			continue
		for y in range(surface[x] + 1, underworld_y):
			var idx := y * width + x
			if T[idx] == TileDB.MUD and T[idx - width] == TileDB.AIR:
				T[idx] = TileDB.JUNGLE_GRASS
	var tx := 4
	while tx < width - 4:
		tx += rng.randi_range(4, 9)
		if tx >= width - 4 or absi(tx - cx) < 6:
			continue
		var tb := biome_cols[tx]
		if tb == WorldData.B_DESERT or (tx >= desert_x0 - 2 and tx < desert_x1 + 2):
			continue
		var gy := tops[tx]
		if gy < 22 or not T[gy * width + tx] in [TileDB.GRASS, TileDB.SNOW, TileDB.JUNGLE_GRASS]:
			continue
		if tb == WorldData.B_SNOW:
			_boreal_tree(T, width, rng, tx, gy)
			continue
		if tb == WorldData.B_JUNGLE:
			_jungle_tree(T, width, rng, tx, gy)
			continue
		var th := rng.randi_range(5, 12)
		var ok := true
		for k in range(1, th + 4):
			if T[(gy - k) * width + tx] != TileDB.AIR:
				ok = false
				break
		if not ok:
			continue
		for k in range(1, th + 1):
			T[(gy - k) * width + tx] = TileDB.TRUNK
		var r := 2 if th < 8 else 3
		var top := gy - th
		for dy in range(-r - 1, r):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r + 1:
					var li := (top + dy) * width + tx + dx
					if T[li] == TileDB.AIR:
						T[li] = TileDB.LEAVES

	# ---------- 5. 矿石和各种小东西 ----------
	var area := width * height
	_scatter(T, width, height, rng, TileDB.COPPER_ORE, area / 9000, surface_base + 6, cavern_y + 60, 4, 10, [TileDB.STONE, TileDB.DIRT])
	_scatter(T, width, height, rng, TileDB.CLAY, area / 22000, surface_base, rock_y, 6, 14, [TileDB.DIRT])
	_scatter(T, width, height, rng, TileDB.IRON_ORE, area / 11000, rock_y - 30, underworld_y, 4, 9, [TileDB.STONE])
	_scatter(T, width, height, rng, TileDB.SULFUR, area / 15000, rock_y, underworld_y, 3, 7, [TileDB.STONE])
	_scatter(T, width, height, rng, TileDB.MOONSILVER_ORE, area / 17000, cavern_y, underworld_y, 3, 8, [TileDB.STONE])
	_scatter(T, width, height, rng, TileDB.STARSTONE_ORE, area / 30000, (cavern_y + underworld_y) / 2, underworld_y, 3, 7, [TileDB.STONE])
	_scatter(T, width, height, rng, TileDB.EMBER_ORE, area / 26000, underworld_y, height - 6, 3, 8, [TileDB.BASALT])

	_decorate_floor(T, width, rng, TileDB.MUSHROOM, area / 2500, rock_y, underworld_y, [TileDB.STONE, TileDB.DIRT])
	_decorate_floor(T, width, rng, TileDB.CRYSTAL, area / 5000, cavern_y, underworld_y, [TileDB.STONE])

	var chests := maxi(8, area / 70000)
	var placed := 0
	for attempt in chests * 60:
		if placed >= chests:
			break
		var x := rng.randi_range(2, width - 3)
		var y := rng.randi_range(surface_base + 40, height - 9)
		var i := y * width + x
		if T[i] == TileDB.AIR and T[i - width] == TileDB.AIR and TileDB.is_solid(T[i + width]):
			T[i] = TileDB.RELIC_CHEST
			placed += 1

	# 丛林：孢子花、藤蔓
	for x in width:
		if biome_cols[x] != WorldData.B_JUNGLE:
			continue
		for y in range(maxi(1, surface[x] - 25), underworld_y):
			var idx := y * width + x
			var t := T[idx]
			if t == TileDB.AIR and T[idx + width] == TileDB.JUNGLE_GRASS and rng.randf() < 0.06:
				T[idx] = TileDB.SPORE_FLOWER
			elif TileDB.is_solid(t) and T[idx + width] == TileDB.AIR and y > surface[x] and rng.randf() < 0.09:
				_hang_vine(T, width, idx + width, rng.randi_range(2, 6))
	# 水晶洞：地面上长满灵晶簇
	for r in crystal_caves:
		for k in r.size.x * 2:
			var x := rng.randi_range(r.position.x, r.end.x)
			var y := rng.randi_range(r.position.y, r.end.y)
			if x < 1 or x >= width - 1 or y < 1 or y >= height - 2:
				continue
			var idx := y * width + x
			if T[idx] == TileDB.AIR and TileDB.is_solid(T[idx + width]):
				T[idx] = TileDB.CRYSTAL

	# ---------- 6. 洞穴水潭和熔岩池 ----------
	for attempt in area / 800:
		var x := rng.randi_range(2, width - 3)
		var y := rng.randi_range(rock_y, height - 8)
		var typ := WorldData.LIQ_WATER
		if y > underworld_y - 30 or (y > cavern_y and rng.randf() < 0.15):
			typ = WorldData.LIQ_LAVA
		_fill_basin(T, LQ, width, x, y, typ, rng.randi_range(2, 6))

	# ---------- 7. 出生点 ----------
	for x in range(cx - 3, cx + 4):
		for y in range(0, surface[cx] + 20):
			var t := T[y * width + x]
			if t == TileDB.TRUNK or t == TileDB.LEAVES:
				T[y * width + x] = TileDB.AIR
	var sy := 0
	while sy < height - 1 and not TileDB.is_solid(T[sy * width + cx]):
		sy += 1
	w.spawn = Vector2i(cx, sy)

	w.tiles = T
	w.walls = WL
	w.liquid = LQ
	w.rebuild_sky()
	return w


static func _noise(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


## 雪松：尖尖的塔形树冠
static func _boreal_tree(T: PackedByteArray, width: int, rng: RandomNumberGenerator, tx: int, gy: int) -> void:
	var th := rng.randi_range(7, 13)
	for k in range(1, th + 3):
		if T[(gy - k) * width + tx] != TileDB.AIR:
			return
	for k in range(1, th + 1):
		T[(gy - k) * width + tx] = TileDB.TRUNK
	var top := gy - th - 1
	for dy in range(0, th - 2):
		var half := 1 + dy / 2
		var y := top + dy
		for dx in range(-half, half + 1):
			var li := y * width + tx + dx
			if T[li] == TileDB.AIR:
				T[li] = TileDB.BOREAL_LEAVES
	T[(top - 1) * width + tx] = TileDB.BOREAL_LEAVES


## 丛林树：又高又大的树冠，下面垂着藤蔓
static func _jungle_tree(T: PackedByteArray, width: int, rng: RandomNumberGenerator, tx: int, gy: int) -> void:
	var th := rng.randi_range(9, 17)
	if gy - th - 6 < 2:
		return
	for k in range(1, th + 4):
		if T[(gy - k) * width + tx] != TileDB.AIR:
			return
	for k in range(1, th + 1):
		T[(gy - k) * width + tx] = TileDB.TRUNK
	var top := gy - th
	var rx := rng.randi_range(4, 5)
	var ry := 3
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			if pow(float(dx) / rx, 2.0) + pow(float(dy) / ry, 2.0) <= 1.1:
				var li := (top + dy) * width + tx + dx
				if T[li] == TileDB.AIR:
					T[li] = TileDB.JUNGLE_LEAVES
	for dx in range(-rx + 1, rx):
		if dx != 0 and rng.randf() < 0.4:
			var y := top + ry
			while T[y * width + tx + dx] == TileDB.JUNGLE_LEAVES:
				y += 1
			_hang_vine(T, width, y * width + tx + dx, rng.randi_range(1, 4))


static func _hang_vine(T: PackedByteArray, width: int, start: int, length: int) -> void:
	var i := start
	for k in length:
		if i >= T.size() or T[i] != TileDB.AIR:
			return
		T[i] = TileDB.VINE
		i += width


## 往下找到洞穴地面，如果这一段地面两头都被石壁挡住（是个"盆"），就往里面灌液体，最多 rows 层
static func _fill_basin(T: PackedByteArray, LQ: PackedByteArray, width: int, x: int, y: int, typ: int, rows: int) -> void:
	var idx := y * width + x
	var n := T.size()
	var k := 0
	while k < 30 and idx + width < n and not (T[idx] == TileDB.AIR and T[idx + width] != TileDB.AIR):
		idx += width
		k += 1
	if k >= 30 or idx + width >= n or not TileDB.is_solid(T[idx + width]):
		return
	var full := (typ << 4) | WorldData.LIQ_MAX
	for r in rows:
		var row := idx - r * width
		if row < width:
			return
		# 向左右找边界：每一格都得是空气，下面得是实心或已经灌满的液体
		var l := row
		var ok := true
		while true:
			var c := l - 1
			if TileDB.is_solid(T[c]):
				break
			if T[c] != TileDB.AIR or not (TileDB.is_solid(T[c + width]) or LQ[c + width] == full) or row - c > 40:
				ok = false
				break
			l = c
		var rr := row
		while ok:
			var c := rr + 1
			if TileDB.is_solid(T[c]):
				break
			if T[c] != TileDB.AIR or not (TileDB.is_solid(T[c + width]) or LQ[c + width] == full) or c - row > 40:
				ok = false
				break
			rr = c
		if not ok or T[row] != TileDB.AIR:
			return
		for c in range(l, rr + 1):
			LQ[c] = full


## 随机游走撒一团团矿石，只替换 replace 列表里的图块
static func _scatter(T: PackedByteArray, width: int, height: int, rng: RandomNumberGenerator, ore: int, count: int,
		y_min: int, y_max: int, size_min: int, size_max: int, replace: Array) -> void:
	y_min = clampi(y_min, 1, height - 2)
	y_max = clampi(y_max, y_min + 1, height - 2)
	for i in count:
		var x := rng.randi_range(1, width - 2)
		var y := rng.randi_range(y_min, y_max)
		for j in rng.randi_range(size_min, size_max):
			if x > 0 and x < width - 1 and y > 0 and y < height - 1:
				var idx := y * width + x
				if T[idx] in replace:
					T[idx] = ore
			x += rng.randi_range(-1, 1)
			y += rng.randi_range(-1, 1)


## 在洞穴地面（空气且下方是指定方块）上放装饰：随机挑一点，往下找最近的地面
static func _decorate_floor(T: PackedByteArray, width: int, rng: RandomNumberGenerator, tile: int, count: int,
		y_min: int, y_max: int, floor_tiles: Array) -> void:
	for i in count:
		var x := rng.randi_range(1, width - 2)
		var y := rng.randi_range(y_min, y_max - 1)
		var idx := y * width + x
		while y < y_max - 1 and T[idx] != TileDB.AIR:
			y += 1
			idx += width
		for k in 40:
			if y >= y_max - 1:
				break
			if T[idx] == TileDB.AIR and T[idx + width] != TileDB.AIR:
				if T[idx + width] in floor_tiles:
					T[idx] = tile
				break
			y += 1
			idx += width
