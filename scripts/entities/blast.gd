class_name Blast
extends Node2D
## 爆炸的闪光效果（一个迅速扩大并淡出的光圈）。

const DURATION := 0.4

var radius_px := 48.0
var _t := 0.0


func _ready() -> void:
	add_to_group("light")


## 爆炸的一瞬间照亮周围
func light_source() -> Array:
	return [position, Color(1.0, 0.7, 0.35), 1.3 * (1.0 - _t / DURATION)]


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / DURATION
	draw_circle(Vector2.ZERO, radius_px * (0.4 + k * 0.8), Color(1.0, 0.65, 0.25, (1.0 - k) * 0.8))
	draw_circle(Vector2.ZERO, radius_px * (0.2 + k * 0.5), Color(1.0, 0.95, 0.7, (1.0 - k)))
