class_name SkyBackdrop
extends Control
## 背景天空：随时间变化的渐变色、太阳和月亮、星星、两层远山（视差滚动）。
## 越往地下越暗。

var time_of_day := 0.3   ## 0 = 午夜，0.5 = 正午
var depth := 0.0         ## 0 = 地表，1 = 地下深处
var cam_x := 0.0
var horizon_y := 400.0   ## 地平线在屏幕上的 y 坐标

var _stars: Array = []

## 天空颜色关键帧：[时间, 颜色]
const SKY_KEYS := [
	[0.0, Color(0.02, 0.03, 0.1)],
	[0.2, Color(0.04, 0.05, 0.16)],
	[0.25, Color(0.85, 0.48, 0.35)],
	[0.32, Color(0.45, 0.7, 0.95)],
	[0.7, Color(0.45, 0.7, 0.95)],
	[0.77, Color(0.92, 0.45, 0.3)],
	[0.83, Color(0.05, 0.05, 0.16)],
	[1.0, Color(0.02, 0.03, 0.1)],
]


static func daylight(t: float) -> float:
	if t < 0.22 or t > 0.8:
		return 0.0
	if t < 0.3:
		return smoothstep(0.22, 0.3, t)
	if t > 0.72:
		return 1.0 - smoothstep(0.72, 0.8, t)
	return 1.0


static func sky_color(t: float) -> Color:
	for i in range(1, SKY_KEYS.size()):
		if t <= SKY_KEYS[i][0]:
			var a: Array = SKY_KEYS[i - 1]
			var b: Array = SKY_KEYS[i]
			return Color(a[1]).lerp(b[1], (t - a[0]) / (b[0] - a[0]))
	return SKY_KEYS[0][1]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 140:
		_stars.append(Vector3(rng.randf(), rng.randf() * 0.7, rng.randf_range(1.0, 2.0)))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var sz := get_viewport_rect().size
	var base := sky_color(time_of_day)
	var dark := Color(0.02, 0.02, 0.035)
	var top := base.darkened(0.35).lerp(dark, depth)
	var bottom := base.lightened(0.12).lerp(dark, depth)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	var vis := 1.0 - depth
	if vis <= 0.01:
		return
	var night := 1.0 - daylight(time_of_day)
	for s in _stars:
		var a: float = night * vis * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.002 + s.x * 50.0))
		if a > 0.02:
			draw_rect(Rect2(s.x * sz.x, s.y * sz.y, s.z, s.z), Color(1, 1, 0.9, a))
	# 太阳：6 点升起，18 点落下
	var sp := (time_of_day - 0.22) / 0.6
	if sp > 0.0 and sp < 1.0:
		var pos := Vector2(sz.x * sp, sz.y * 0.8 - sin(sp * PI) * sz.y * 0.65)
		draw_circle(pos, 46, Color(1, 0.9, 0.6, 0.15 * vis))
		draw_circle(pos, 26, Color(1, 0.95, 0.7, vis))
	# 月亮
	var mp := fposmod(time_of_day - 0.78, 1.0) / 0.46
	if mp > 0.0 and mp < 1.0:
		var pos := Vector2(sz.x * mp, sz.y * 0.8 - sin(mp * PI) * sz.y * 0.6)
		draw_circle(pos, 18, Color(0.92, 0.93, 1.0, vis))
		draw_circle(pos + Vector2(7, -4), 15, top.lerp(bottom, 0.3))
	# 远山（两层，视差）：用一条条竖着的色块画，不会出现多边形三角化失败
	for layer in 2:
		var col := bottom.darkened(0.25 + layer * 0.2).lerp(Color(0.1, 0.18, 0.15), 0.35)
		col.a = vis
		var par := 0.08 + layer * 0.12
		var base_y := horizon_y + 20.0 + layer * 50.0
		var x := 0.0
		while x < sz.x:
			var wx := x + cam_x * par
			var hy := base_y - (sin(wx * 0.004 + layer) * 45.0 + sin(wx * 0.013 + layer * 3.0) * 18.0 + 60.0)
			if hy < sz.y:
				draw_rect(Rect2(x, maxf(hy, 0.0), 4.0, sz.y - maxf(hy, 0.0)), col)
			x += 4.0
