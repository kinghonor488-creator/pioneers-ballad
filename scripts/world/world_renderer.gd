class_name WorldRenderer
extends Node2D
## 分块渲染：世界被切成 32×32 的区块，只把摄像机附近的区块写进 TileMapLayer，
## 走远了就卸载。这样 500 万格的世界也只需要渲染几万格。
## 明暗由 Lighting（逐格光照）负责，这里只管画图块。

const CHUNK := 32
const TS := 16

var world: WorldData
var tile_layer: TileMapLayer
var wall_layer: TileMapLayer
var max_chunks_per_frame := 6

var _loaded := {}  # Vector2i(区块) -> true


func setup(w: WorldData, lit_material: Material = null) -> void:
	world = w
	wall_layer = TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.tile_set = _make_tileset(TileArt.build_wall_atlas(), TileDB.WALL_COUNT)
	wall_layer.material = lit_material
	add_child(wall_layer)
	tile_layer = TileMapLayer.new()
	tile_layer.name = "Tiles"
	tile_layer.tile_set = _make_tileset(TileArt.build_tile_atlas(), TileDB.COUNT)
	tile_layer.material = lit_material
	add_child(tile_layer)
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


func _variant(x: int, y: int) -> int:
	return ((x * 73856093) ^ (y * 19349663)) & 3


func _load_chunk(c: Vector2i) -> void:
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
	_loaded[c] = true


func _unload_chunk(c: Vector2i) -> void:
	var x0 := c.x * CHUNK
	var y0 := c.y * CHUNK
	for y in range(y0, mini(y0 + CHUNK, world.height)):
		for x in range(x0, mini(x0 + CHUNK, world.width)):
			tile_layer.erase_cell(Vector2i(x, y))
			wall_layer.erase_cell(Vector2i(x, y))
	_loaded.erase(c)


func _on_tile_changed(x: int, y: int) -> void:
	if not _loaded.has(Vector2i(x / CHUNK, y / CHUNK)):
		return
	var pos := Vector2i(x, y)
	var t := world.get_tile(x, y)
	if t == TileDB.AIR:
		tile_layer.erase_cell(pos)
	else:
		tile_layer.set_cell(pos, 0, Vector2i(t, _variant(x, y)))
