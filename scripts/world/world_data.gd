class_name WorldData
extends RefCounted
## 世界数据：图块和背景墙按行各存一个字节数组（每格 1 字节）。
## 4200×1200 的世界只占大约 10 MB 内存。

signal tile_changed(x: int, y: int)

var width := 0
var height := 0
var seed_value := 0
var tiles := PackedByteArray()
var walls := PackedByteArray()
var surface := PackedInt32Array()  ## 每一列生成时的地表高度
var spawn := Vector2i.ZERO          ## 出生点（脚下方块的上方一格）
var layers := {}                    ## "surface"/"rock"/"cavern"/"underworld" -> 该层开始的 y


func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	tiles.resize(w * h)
	tiles.fill(0)
	walls.resize(w * h)
	walls.fill(0)
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
	tiles[y * width + x] = id
	tile_changed.emit(x, y)


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
