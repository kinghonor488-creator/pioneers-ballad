class_name LiquidSim
extends RefCounted
## 液体流动（元胞自动机）。
## 只处理"活跃"的格子：生成好的湖和水潭一开始是静止的，完全不花时间；
## 你挖开一个口子、倒一桶水、放下或挖掉方块时，附近的格子才会被唤醒。
## 每一步对每个活跃格子：
##   1. 能往下流就先往下流（下面是空气，或者是同种液体但没满）
##   2. 流不下去就把这一层连着的水面一次铺平（除不尽的余数给离得近的格子），
##      水面边上如果是悬崖，就分一点过去，下一步从边上流下去
##   3. 水碰到熔岩：熔岩凝固成黑曜石
## 一格液体没有任何变化，就不再活跃。熔岩流得比水慢（每 3 步才动一次）。

const MAX := WorldData.LIQ_MAX
const WATER := WorldData.LIQ_WATER
const LAVA := WorldData.LIQ_LAVA
const LAVA_EVERY := 3
const LEVEL_SPAN := 64      ## 铺平时向每边最多看多少格

var world: WorldData
var active := {}            ## 格子下标 -> true
var budget := 1500          ## 每一步最多处理多少格（剩下的留到下一步）
var last_processed := 0

var _tick := 0
var _w := 0
var _leveled := {}          ## 这一步已经被铺平过的格子


func _init(w: WorldData) -> void:
	world = w
	_w = w.width
	world.tile_changed.connect(_on_tile_changed)


func _on_tile_changed(x: int, y: int) -> void:
	activate_around(x, y)


func activate(x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < world.width and y < world.height:
		var i := y * _w + x
		if world.liquid[i] != 0:
			active[i] = true


func activate_around(x: int, y: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			activate(x + dx, y + dy)


func step() -> void:
	_tick += 1
	var cells := active.keys()
	active = {}
	_leveled = {}
	cells.sort()
	cells.reverse()   # 从下往上处理，掉落更自然
	last_processed = 0
	for idx in cells:
		if last_processed >= budget:
			active[idx] = true
			continue
		last_processed += 1
		_update(idx)


func _can_hold(i: int, typ: int) -> bool:
	if world.tiles[i] != 0:
		return false
	var v := world.liquid[i]
	return v == 0 or (v >> 4) == typ


## 下面托着：实心方块，或者满格的同种液体
func _supported(c: int, typ: int) -> bool:
	var b := c + _w
	if b >= world.liquid.size():
		return true
	return not _can_hold(b, typ) or (world.liquid[b] & 15) == MAX


func _put(i: int, typ: int, amt: int) -> void:
	var v := 0 if amt <= 0 else (typ << 4) | amt
	if world.liquid[i] != v:
		world.liquid[i] = v
		world.liquid_dirty.append(i)


func _wake(i: int) -> void:
	active[i] = true
	for n in [i - 1, i + 1, i - _w, i + _w]:
		if n >= 0 and n < world.liquid.size() and world.liquid[n] != 0:
			active[n] = true


func _update(i: int) -> void:
	var v := world.liquid[i]
	if v == 0 or _leveled.has(i):
		return
	var typ := v >> 4
	var amt := v & 15
	var y := i / _w
	if world.tiles[i] != 0:
		_put(i, typ, 0)
		return
	if typ == LAVA and _tick % LAVA_EVERY != 0:
		active[i] = true
		return
	# 3. 水碰熔岩 → 黑曜石
	for n in [i - 1, i + 1, i - _w, i + _w]:
		if n < 0 or n >= world.liquid.size():
			continue
		var nv := world.liquid[n]
		if nv != 0 and (nv >> 4) != typ:
			var lava_i: int = i if typ == LAVA else n
			world.set_tile(lava_i % _w, lava_i / _w, TileDB.OBSIDIAN)   # set_tile 会把那格液体清掉
			_wake(i)
			_wake(n)
			return
	# 1. 往下流
	if y + 1 < world.height:
		var b := i + _w
		if _can_hold(b, typ):
			var bamt := world.liquid[b] & 15
			var mv := mini(amt, MAX - bamt)
			if mv > 0:
				_put(b, typ, bamt + mv)
				amt -= mv
				_put(i, typ, amt)
				_wake(b)
				_wake(i)
				if amt == 0:
					return
	# 2. 流不下去（或者流完还剩一些）：铺平这一层
	if _supported(i, typ):
		_level(i, typ)


## 找出 i 所在这一行"连着的水面"：同种液体或空位，并且下面托着；
## 两头如果是悬崖（能装液体但下面没托着），也把那一格算进来。
## 然后把总量平均分配，除不尽的余数优先给离 i 近的格子。整段一次算完，不会来回晃，总量也不会变。
func _level(i: int, typ: int) -> void:
	var row0 := (i / _w) * _w
	var cells := [i]
	for dir in [-1, 1]:
		var c := i
		for k in LEVEL_SPAN:
			var n: int = c + dir
			if n < row0 or n >= row0 + _w or not _can_hold(n, typ):
				break
			cells.append(n)
			if not _supported(n, typ):
				break   # 悬崖边：这一格分到水以后，下一步就会往下掉
			c = n
	if cells.size() == 1:
		return
	var total := 0
	for c in cells:
		total += world.liquid[c] & 15
		_leveled[c] = true
	cells.sort_custom(func(a, b): return absi(a - i) < absi(b - i))
	var q := total / cells.size()
	var r := total % cells.size()
	for k in cells.size():
		var want := q + (1 if k < r else 0)
		var c: int = cells[k]
		if (world.liquid[c] & 15) != want:
			_put(c, typ, want)
			_wake(c)


## 一块区域里液体的总量（测试用：流动时总量应该不变）
func total_amount(x0: int, y0: int, x1: int, y1: int) -> int:
	var t := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			t += world.liquid_amount(x, y)
	return t
