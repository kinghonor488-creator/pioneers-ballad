class_name WorldRenderer
extends Node2D
## 分块渲染：世界被切成 32×32 的区块，只把摄像机附近的区块写进 TileMapLayer，
## 走远了就卸载。这样 500 万格的世界也只需要渲染几万格。
## 发光图块（火把、灵晶簇、熔炉……）在区块加载时才生成对应的 PointLight2D。

const CHUNK := 32
const TS := 16
const MAX_LIGHTS_PER_CHUNK := 24

var world: WorldData
var tile_layer: TileMapLayer
var wall_layer: TileMapLayer
var light_root: Node2D
var max_chunks_per_frame := 6
var light_strength := 1.0

var _loaded := {}  # Vector2i(区块) -> {Vector2i(图块): PointLight2D}

static var _light_tex: Texture2D


static func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 128
		gt.height = 128
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		_light_tex = gt
	return _light_tex


static func make_light(radius_tiles: float, color: Color, energy: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = light_texture()
	l.texture_scale = radius_tiles * TS / 64.0
	l.color = color
	l.energy = energy
	return l


func setup(w: WorldData) -> void:
	world = w
	wall_layer = TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.tile_set = _make_tileset(TileArt.build_wall_atlas(), TileDB.WALL_COUNT)
	add_child(wall_layer)
	tile_layer = TileMapLayer.new()
	tile_layer.name = "Tiles"
	tile_layer.tile_set = _make_tileset(TileArt.build_tile_atlas(), TileDB.COUNT)
	add_child(tile_layer)
	light_root = Node2D.new()
	light_root.name = "Lights"
	add_child(light_root)
	world.tile_changed.connect(_on_tile_changed)


func _make_tileset(img: Image, columns: int) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TS, TS)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TS, TS)
	ts.add_source(src, 0)
	for x in range(1, columns):
		for y in TileArt.VARIANTS:
			src.create_tile(Vector2i(x, y))
	return ts


func loaded_chunk_count() -> int:
	return _loaded.size()


## center / view_size 都是世界像素坐标
func update_view(center: Vector2, view_size: Vector2, force := false) -> void:
	var cpx := float(CHUNK * TS)
	var half := view_size * 0.5 + Vector2(cpx, cpx) * 0.5
	var max_c := Vector2i((world.width - 1) / CHUNK, (world.height - 1) / CHUNK)
	var c0 := Vector2i(clampi(floori((center.x - half.x) / cpx), 0, max_c.x), clampi(floori((center.y - half.y) / cpx), 0, max_c.y))
	var c1 := Vector2i(clampi(floori((center.x + half.x) / cpx), 0, max_c.x), clampi(floori((center.y + half.y) / cpx), 0, max_c.y))
	var missing := []
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cy)
			if not _loaded.has(c):
				missing.append(c)
	if not missing.is_empty():
		var cc := Vector2(center.x / cpx, center.y / cpx)
		missing.sort_custom(func(a, b): return Vector2(a).distance_squared_to(cc) < Vector2(b).distance_squared_to(cc))
		var budget := missing.size() if force else max_chunks_per_frame
		for i in mini(budget, missing.size()):
			_load_chunk(missing[i])
	for c in _loaded.keys():
		if c.x < c0.x - 2 or c.x > c1.x + 2 or c.y < c0.y - 2 or c.y > c1.y + 2:
			_unload_chunk(c)


func set_light_strength(s: float) -> void:
	if absf(s - light_strength) < 0.02:
		return
	light_strength = s
	for c in _loaded:
		for pos in _loaded[c]:
			var l: PointLight2D = _loaded[c][pos]
			l.energy = light_strength * float(l.get_meta("base_energy", 1.0))


func _variant(x: int, y: int) -> int:
	return ((x * 73856093) ^ (y * 19349663)) & 3


func _load_chunk(c: Vector2i) -> void:
	var lights := {}
	var x0 := c.x * CHUNK
	var y0 := c.y * CHUNK
	var tiles := world.tiles
	var walls := world.walls
	var w := world.width
	for y in range(y0, mini(y0 + CHUNK, world.height)):
		var row := y * w
		for x in range(x0, mini(x0 + CHUNK, w)):
			var t := tiles[row + x]
			var wl := walls[row + x]
			var v := _variant(x, y)
			if wl != 0:
				wall_layer.set_cell(Vector2i(x, y), 0, Vector2i(wl, v))
			if t != 0:
				tile_layer.set_cell(Vector2i(x, y), 0, Vector2i(t, v))
				if TileDB.light_radius(t) > 0.0 and lights.size() < MAX_LIGHTS_PER_CHUNK:
					lights[Vector2i(x, y)] = _spawn_light(x, y, t)
	_loaded[c] = lights


func _unload_chunk(c: Vector2i) -> void:
	var x0 := c.x * CHUNK
	var y0 := c.y * CHUNK
	for y in range(y0, mini(y0 + CHUNK, world.height)):
		for x in range(x0, mini(x0 + CHUNK, world.width)):
			tile_layer.erase_cell(Vector2i(x, y))
			wall_layer.erase_cell(Vector2i(x, y))
	for pos in _loaded[c]:
		_loaded[c][pos].queue_free()
	_loaded.erase(c)


func _spawn_light(x: int, y: int, t: int) -> PointLight2D:
	var base := 1.0 if t == TileDB.TORCH else 0.8
	var l := make_light(TileDB.light_radius(t), TileDB.prop(t, "light_color", Color.WHITE), base * light_strength)
	l.set_meta("base_energy", base)
	l.position = Vector2(x * TS + TS * 0.5, y * TS + TS * 0.5)
	light_root.add_child(l)
	return l


func _on_tile_changed(x: int, y: int) -> void:
	var c := Vector2i(x / CHUNK, y / CHUNK)
	if not _loaded.has(c):
		return
	var pos := Vector2i(x, y)
	var t := world.get_tile(x, y)
	if t == TileDB.AIR:
		tile_layer.erase_cell(pos)
	else:
		tile_layer.set_cell(pos, 0, Vector2i(t, _variant(x, y)))
	var lights: Dictionary = _loaded[c]
	if lights.has(pos):
		lights[pos].queue_free()
		lights.erase(pos)
	if TileDB.light_radius(t) > 0.0:
		lights[pos] = _spawn_light(x, y, t)
