class_name Debris
extends Node2D
## 碎屑粒子：挖方块时溅出的土块、砍树的木屑、打中敌人的火花。
## 所有粒子都放在这一个节点里统一更新和绘制，很便宜。

const GRAVITY := 600.0
const MAX_PARTICLES := 600

var _parts: Array = []   ## [位置, 速度, 剩余时间, 颜色, 大小]


## 在 pos 处溅出 n 个颜色为 color 的碎屑
func burst(pos: Vector2, color: Color, n: int, speed: float = 90.0, up: float = 60.0) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * speed + Vector2(0, -up)
		var c := color.lightened(randf_range(-0.15, 0.2))
		_parts.append([pos + Vector2(randf_range(-3, 3), randf_range(-3, 3)), v, randf_range(0.35, 0.7), c, 1.0 + float(randi() % 2)])
	if _parts.size() > MAX_PARTICLES:
		_parts = _parts.slice(_parts.size() - MAX_PARTICLES)


func count() -> int:
	return _parts.size()


func _process(delta: float) -> void:
	if _parts.is_empty():
		return
	for p in _parts:
		p[1].y += GRAVITY * delta
		p[0] += p[1] * delta
		p[2] -= delta
	_parts = _parts.filter(func(p): return p[2] > 0.0)
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var c: Color = p[3]
		c.a = clampf(p[2] * 3.0, 0.0, 1.0)
		var s: float = p[4]
		draw_rect(Rect2(p[0] - Vector2(s, s) * 0.5, Vector2(s, s)), c)
