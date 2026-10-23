class_name TileBody
extends Node2D
## 会和图块世界碰撞的"身体"，玩家和敌人共用。
## 自己写的"轴分离"碰撞（先走 X 再走 Y），不依赖物理引擎，结果稳定、可以在无界面模式下测试。
## position 是碰撞盒的左上角，body_size 是碰撞盒大小。

const TS := 16.0

var world: WorldData
var velocity := Vector2.ZERO
var body_size := Vector2(12, 28)
var on_ground := false
var hit_wall := false      ## 这一帧水平方向撞到了墙
var step_up := true        ## 走路时能自动跨上一格高的台阶


func center() -> Vector2:
	return position + body_size * 0.5


func rect() -> Rect2:
	return Rect2(position, body_size)


func collides_at(p: Vector2) -> bool:
	var x0 := floori(p.x / TS)
	var x1 := floori((p.x + body_size.x - 0.01) / TS)
	var y0 := floori(p.y / TS)
	var y1 := floori((p.y + body_size.y - 0.01) / TS)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if world.is_solid(tx, ty):
				return true
	return false


## 和某个图块的格子是否重叠（放方块时用）
func overlaps_tile(t: Vector2i) -> bool:
	return rect().intersects(Rect2(Vector2(t) * TS, Vector2(TS, TS)))


func move_with_collision(motion: Vector2) -> void:
	_move_x(motion.x)
	_move_y(motion.y)


func _move_x(dx: float) -> void:
	hit_wall = false
	var steps := int(ceil(absf(dx) / 4.0))
	if steps == 0:
		return
	var sx := dx / steps
	for i in steps:
		var np := position + Vector2(sx, 0)
		if not collides_at(np):
			position = np
			continue
		if step_up and on_ground and not collides_at(np + Vector2(0, -TS)) and not collides_at(position + Vector2(0, -TS)):
			position = np + Vector2(0, -TS)
			continue
		if sx > 0:
			position.x = floori((np.x + body_size.x - 0.01) / TS) * TS - body_size.x
		else:
			position.x = (floori(np.x / TS) + 1) * TS
		velocity.x = 0.0
		hit_wall = true
		return


func _move_y(dy: float) -> void:
	on_ground = false
	var steps := int(ceil(absf(dy) / 4.0))
	if steps == 0:
		on_ground = collides_at(position + Vector2(0, 0.5))
		return
	var sy := dy / steps
	for i in steps:
		var np := position + Vector2(0, sy)
		if not collides_at(np):
			position = np
			continue
		if sy > 0:
			position.y = floori((np.y + body_size.y - 0.01) / TS) * TS - body_size.y
			on_ground = true
		else:
			position.y = (floori(np.y / TS) + 1) * TS
		velocity.y = 0.0
		return
