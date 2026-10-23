class_name Inventory
extends RefCounted
## 背包：50 格（前 10 格是快捷栏）+ 3 格饰品栏。每格是 null 或一个道具实例字典。

signal changed

const HOTBAR_SIZE := 10
const SIZE := 50
const ACCESSORY_SIZE := 3

var slots: Array = []
var accessories: Array = []
var selected := 0


func _init() -> void:
	slots.resize(SIZE)
	accessories.resize(ACCESSORY_SIZE)


func selected_item() -> Variant:
	return slots[selected]


## 放入一个道具实例，返回放不下的剩余数量
func add_instance(inst: Dictionary) -> int:
	var remaining := int(inst.count)
	var stack := ItemDB.max_stack(inst.id)
	if stack > 1:
		for s in slots:
			if s != null and ItemDB.can_stack(s, inst) and s.count < stack:
				var mv := mini(stack - int(s.count), remaining)
				s.count += mv
				remaining -= mv
				if remaining == 0:
					break
	var i := 0
	while remaining > 0 and i < SIZE:
		if slots[i] == null:
			var n := mini(stack, remaining)
			var copy: Dictionary = inst.duplicate(true)
			copy.count = n
			slots[i] = copy
			remaining -= n
		i += 1
	changed.emit()
	return remaining


func add(id: String, count: int = 1) -> int:
	return add_instance(ItemDB.make(id, count))


func can_fit(inst: Dictionary) -> bool:
	var stack := ItemDB.max_stack(inst.id)
	var need := int(inst.count)
	for s in slots:
		if s == null:
			need -= stack
		elif ItemDB.can_stack(s, inst):
			need -= stack - int(s.count)
		if need <= 0:
			return true
	return false


func count_of(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s.id == id:
			n += int(s.count)
	return n


func remove(id: String, count: int) -> bool:
	if count_of(id) < count:
		return false
	for i in range(SIZE - 1, -1, -1):
		var s = slots[i]
		if s != null and s.id == id:
			var take := mini(count, int(s.count))
			s.count -= take
			count -= take
			if s.count <= 0:
				slots[i] = null
			if count == 0:
				break
	changed.emit()
	return true


func consume_slot(i: int, n: int = 1) -> void:
	var s = slots[i]
	if s == null:
		return
	s.count -= n
	if s.count <= 0:
		slots[i] = null
	changed.emit()


func has_accessory(id: String) -> bool:
	for a in accessories:
		if a != null and a.id == id:
			return true
	return false
