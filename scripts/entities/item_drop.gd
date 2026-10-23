class_name ItemDrop
extends TileBody
## 掉在地上的道具：挖出来的方块、打怪的掉落、宝匣里蹦出来的东西、玩家丢出去的东西。
## 会受重力落地、在地上轻轻上下浮动；玩家走近（拾取范围内）就会被吸过去自动捡起。
## 由主控每个物理帧调用 tick()。

const SIZE := 10.0
const MAGNET_SPEED := 340.0
const COLLECT_DIST := 12.0

var item: Dictionary = {}
var pickup_delay := 0.0     ## 刚丢出去的东西过一会儿才能被捡回来
var age := 0.0
var attracted := false


func setup(w: WorldData, inst: Dictionary, center_px: Vector2, vel: Vector2) -> void:
	world = w
	item = inst
	body_size = Vector2(SIZE, SIZE)
	step_up = false
	position = center_px - body_size * 0.5
	velocity = vel
	if ItemDB.rarity(item) >= 2:
		add_to_group("light")   # 稀有道具在地上会发一点光，好找


func light_source() -> Array:
	return [center(), ItemDB.rarity_color(item), 0.35]


## magnet_radius：拾取范围（像素）。返回 true 表示已经碰到玩家、可以捡起来了。
func tick(delta: float, target: Vector2, magnet_radius: float, can_take: bool) -> bool:
	age += delta
	pickup_delay = maxf(0.0, pickup_delay - delta)
	var to := target - center()
	var d := to.length()
	attracted = can_take and pickup_delay <= 0.0 and d < magnet_radius
	if attracted:
		# 被吸向玩家：不受重力、可以穿过方块
		velocity = velocity.move_toward(to.normalized() * MAGNET_SPEED, 1600.0 * delta)
		position += velocity * delta
		queue_redraw()
		return d < COLLECT_DIST
	velocity.y = minf(velocity.y + 900.0 * delta, 500.0)
	velocity.x = move_toward(velocity.x, 0.0, (700.0 if on_ground else 80.0) * delta)
	if collides_at(position):
		position.y -= 4.0   # 被方块埋住了就往上挤
	else:
		move_with_collision(velocity * delta)
	queue_redraw()
	return false


func _draw() -> void:
	var bob := sin(age * 3.0) * 1.5 if on_ground and not attracted else 0.0
	var r := Rect2(Vector2(0, -2.0 + bob), body_size)
	if ItemDB.rarity(item) >= 2:
		var c := ItemDB.rarity_color(item)
		draw_circle(r.get_center(), 7.0, Color(c.r, c.g, c.b, 0.25 + 0.1 * sin(age * 4.0)))
	draw_texture_rect(TileArt.icon(item.id), r, false)
	if int(item.get("count", 1)) > 1:
		draw_rect(Rect2(r.end - Vector2(3, 3), Vector2(3, 3)), Color(1, 1, 1, 0.7))   # 一小点，表示是一堆
