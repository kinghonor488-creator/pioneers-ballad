class_name Bomb
extends Node2D
## 扔出去的炸弹：受重力影响、碰到方块会弹，引信烧完就爆炸。

signal exploded(center: Vector2, radius: float)

var world: WorldData
var velocity := Vector2.ZERO
var fuse := 2.0
var radius := 3.0
var big := false


func _ready() -> void:
	add_to_group("light")


## 引信的小火花
func light_source() -> Array:
	return [position, Color(1.0, 0.6, 0.25), 0.35]


func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		exploded.emit(position, radius)
		queue_free()
		return
	velocity.y = minf(velocity.y + 900.0 * delta, 700.0)
	var nx := position + Vector2(velocity.x * delta, 0)
	if _solid_at(nx):
		velocity.x *= -0.4
	else:
		position = nx
	var ny := position + Vector2(0, velocity.y * delta)
	if _solid_at(ny):
		velocity.y *= -0.35
		velocity.x *= 0.75
	else:
		position = ny
	queue_redraw()


func _solid_at(p: Vector2) -> bool:
	return world.is_solid(floori(p.x / 16.0), floori(p.y / 16.0))


func _draw() -> void:
	var body := Color(0.55, 0.12, 0.12) if big else Color(0.2, 0.2, 0.25)
	draw_circle(Vector2.ZERO, 6.0 if big else 4.5, body)
	draw_circle(Vector2(-1.5, -1.5), 1.2, body.lightened(0.4))
	var spark := Color(1.0, 0.95, 0.4) if int(fuse * 12.0) % 2 == 0 else Color(1.0, 0.5, 0.15)
	draw_line(Vector2(2, -4), Vector2(4, -7), Color(0.55, 0.36, 0.2), 1.0)
	draw_circle(Vector2(4, -8), 1.5, spark)
