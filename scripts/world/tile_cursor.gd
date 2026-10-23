class_name TileCursor
extends Node2D
## 鼠标指向的图块：白框 = 够得着，红框 = 太远；挖掘时显示裂纹进度。

var target := Vector2i.ZERO
var in_reach := true
var progress := 0.0


func _draw() -> void:
	var r := Rect2(Vector2(target) * 16.0, Vector2(16, 16))
	var c := Color(1, 1, 1, 0.75) if in_reach else Color(1, 0.3, 0.3, 0.6)
	draw_rect(r, c, false, 1.0)
	if progress > 0.0:
		var n := int(progress * 5.0)
		var crack := Color(0, 0, 0, 0.7)
		var p := r.position
		var segs := [[Vector2(8, 8), Vector2(3, 3)], [Vector2(8, 8), Vector2(13, 5)], [Vector2(8, 8), Vector2(6, 14)],
			[Vector2(8, 8), Vector2(14, 12)], [Vector2(3, 3), Vector2(1, 9)]]
		for i in mini(n, segs.size()):
			draw_line(p + segs[i][0], p + segs[i][1], crack, 1.0)
		draw_rect(Rect2(p, Vector2(16, 16)), Color(0, 0, 0, progress * 0.3))
