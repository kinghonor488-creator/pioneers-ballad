class_name WorldData
extends RefCounted
## 世界数据：图块和背景墙按行各存一个字节数组（每格 1 字节）。
## 4200×1200 的世界只占大约 10 MB 内存。

signal tile_changed(x: int, y: int)

## 液体：每格 1 字节，高 4 位是种类，低 4 位是量（0~8，8 = 满格）
const LIQ_MAX := 8
enum { LIQ_NONE, LIQ_WATER, LIQ_LAVA }

var width := 0
var height := 0
var seed_value := 0
var tiles := PackedByteArray()
var walls := PackedByteArray()
var liquid := PackedByteArray()
var liquid_dirty: Array = []        ## 液体变了的格子下标，渲染器每帧取走
var surface := PackedInt32Array()  ## 每一列生成时的地表高度
var sky_y := PackedInt32Array()    ## 每一列从上往下第一个实心方块的 y（它上面都能被天光直射）
var spawn := Vector2i.ZERO          ## 出生点（脚下方块的上方一格）
var layers := {}                    ## "surface"/"rock"/"cavern"/"underworld" -> 该层开始的 y


func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	tiles.resize(w * h)
	tiles.fill(0)
	walls.resize(w * h)
	walls.fill(0)
	liquid.resize(w * h)
	liquid.fill(0)
	surface.resize(w)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


## 世界外面当作基岩，玩家走不出去
func get_tile(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return TileDB.BEDROCK
	return tiles[y * width + x]


func get_wall(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return TileDB.WALL_NONE
	return walls[y * width + x]


func set_tile(x: int, y: int, id: int) -> void:
	if not in_bounds(x, y):
		return
	var i := y * width + x
	tiles[i] = id
	if id != TileDB.AIR and liquid.size() == tiles.size() and liquid[i] != 0:
		liquid[i] = 0          # 方块会把液体挤掉
		liquid_dirty.append(i)
	if sky_y.size() == width:
		if TileDB.is_solid(id):
			if y < sky_y[x]:
				sky_y[x] = y
		elif y == sky_y[x]:
			sky_y[x] = _scan_sky(x, y)
	tile_changed.emit(x, y)


## 重新计算每一列的天光高度（生成世界、读档之后调用一次）
func rebuild_sky() -> void:
	sky_y.resize(width)
	for x in width:
		sky_y[x] = _scan_sky(x, 0)


func _scan_sky(x: int, from_y: int) -> int:
	var i := from_y * width + x
	for y in range(from_y, height):
		if TileDB.is_solid(tiles[i]):
			return y
		i += width
	return height


func liquid_type(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return LIQ_NONE
	return liquid[y * width + x] >> 4


func liquid_amount(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return liquid[y * width + x] & 15


## 像素坐标处是什么液体（玩家游泳、受熔岩伤害用）
func liquid_type_px(p: Vector2) -> int:
	var x := floori(p.x / 16.0)
	var y := floori(p.y / 16.0)
	var t := liquid_type(x, y)
	if t == LIQ_NONE:
		return LIQ_NONE
	# 没满的格子，液面以上不算泡在液体里
	var surface_px := (y + 1) * 16.0 - liquid_amount(x, y) * 2.0
	if liquid_type(x, y - 1) == LIQ_NONE and p.y < surface_px:
		return LIQ_NONE
	return t


func set_liquid(x: int, y: int, type: int, amount: int) -> void:
	if not in_bounds(x, y):
		return
	var i := y * width + x
	var v := 0 if amount <= 0 or type == LIQ_NONE else (type << 4) | mini(amount, LIQ_MAX)
	if liquid[i] != v:
		liquid[i] = v
		liquid_dirty.append(i)


func is_solid(x: int, y: int) -> bool:
	return TileDB.is_solid(get_tile(x, y))


func surface_at(x: int) -> int:
	return surface[clampi(x, 0, width - 1)]


## 当前位置属于哪一层
func layer_name(y: int) -> String:
	if y < int(layers.get("surface", 0)) - 40:
		return "天空"
	if y < int(layers.get("rock", 0)):
		return "地表"
	if y < int(layers.get("cavern", 0)):
		return "地下"
	if y < int(layers.get("underworld", 0)):
		return "洞穴层"
	return "深渊"


## 统计各种图块的数量（测试和调试用）
func count_tiles() -> Dictionary:
	var counts := {}
	for i in tiles.size():
		var t := tiles[i]
		counts[t] = int(counts.get(t, 0)) + 1
	return counts
