class_name Player
extends Node2D
## 玩家：自己写的"轴分离"图块碰撞（先走 X 再走 Y），不依赖物理引擎，
## 结果稳定、可以在无界面模式下做自动测试。
## position 是碰撞盒的左上角。

signal landed_hard(damage: int)

const TS := 16.0
const W := 12.0
const H := 28.0
const RUN_SPEED := 150.0
const GROUND_ACCEL := 1500.0
const AIR_ACCEL := 900.0
const GRAVITY := 1300.0
const MAX_FALL := 900.0
const JUMP_SPEED := 420.0
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
const SAFE_FALL_TILES := 22.0

var world: WorldData
var velocity := Vector2.ZERO
var on_ground := false
var facing := 1
var move_mult := 1.0
var jump_mult := 1.0
var no_fall := false
var hp := 100.0
var max_hp := 100
var hurt_flash := 0.0

var _coyote := 0.0
var _jump_buffer := 0.0
var _fall_peak := 0.0
var _walk_t := 0.0


func center() -> Vector2:
	return position + Vector2(W, H) * 0.5


## dir: -1..1 左右输入
func step(dt: float, dir: float, jump_pressed: bool, jump_held: bool) -> void:
	velocity.x = move_toward(velocity.x, dir * RUN_SPEED * move_mult, (GROUND_ACCEL if on_ground else AIR_ACCEL) * dt)
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1
	_coyote = COYOTE if on_ground else maxf(0.0, _coyote - dt)
	_jump_buffer = JUMP_BUFFER if jump_pressed else maxf(0.0, _jump_buffer - dt)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = -JUMP_SPEED * jump_mult
		_jump_buffer = 0.0
		_coyote = 0.0
		on_ground = false
	var g := GRAVITY
	if velocity.y < 0.0 and not jump_held:
		g *= 2.2  # 松开跳跃键就跳得矮一些
	velocity.y = minf(velocity.y + g * dt, MAX_FALL)

	var was_ground := on_ground
	_move_x(velocity.x * dt)
	_move_y(velocity.y * dt)

	if was_ground and not on_ground:
		_fall_peak = position.y
	elif not on_ground:
		_fall_peak = minf(_fall_peak, position.y)
	elif not was_ground and on_ground:
		var tiles := (position.y - _fall_peak) / TS
		if tiles > SAFE_FALL_TILES and not no_fall:
			landed_hard.emit(int((tiles - SAFE_FALL_TILES) * 6.0))
		_fall_peak = position.y
	if on_ground:
		_fall_peak = position.y

	_walk_t = _walk_t + dt * absf(velocity.x) * 0.08 if on_ground and absf(velocity.x) > 10.0 else 0.0
	hurt_flash = maxf(0.0, hurt_flash - dt)
	queue_redraw()


func teleport(px: Vector2) -> void:
	position = px
	velocity = Vector2.ZERO
	_fall_peak = px.y


func collides_at(p: Vector2) -> bool:
	var x0 := floori(p.x / TS)
	var x1 := floori((p.x + W - 0.01) / TS)
	var y0 := floori(p.y / TS)
	var y1 := floori((p.y + H - 0.01) / TS)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if world.is_solid(tx, ty):
				return true
	return false


## 和某个图块的格子是否重叠（放方块时用）
func overlaps_tile(t: Vector2i) -> bool:
	return Rect2(position, Vector2(W, H)).intersects(Rect2(Vector2(t) * TS, Vector2(TS, TS)))


func _move_x(dx: float) -> void:
	var steps := int(ceil(absf(dx) / 4.0))
	if steps == 0:
		return
	var sx := dx / steps
	for i in steps:
		var np := position + Vector2(sx, 0)
		if not collides_at(np):
			position = np
			continue
		# 自动跨上一格高的台阶
		if on_ground and not collides_at(np + Vector2(0, -TS)) and not collides_at(position + Vector2(0, -TS)):
			position = np + Vector2(0, -TS)
			continue
		if sx > 0:
			position.x = floori((np.x + W - 0.01) / TS) * TS - W
		else:
			position.x = (floori(np.x / TS) + 1) * TS
		velocity.x = 0.0
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
			position.y = floori((np.y + H - 0.01) / TS) * TS - H
			on_ground = true
		else:
			position.y = (floori(np.y / TS) + 1) * TS
		velocity.y = 0.0
		return


# ---------------------------------------------------------------- 外观（纯代码绘制的小探险家）

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	if facing < 0:
		x = W - x - w
	draw_rect(Rect2(x, y, w, h), c)


func _draw() -> void:
	var skin := Color(0.96, 0.78, 0.6)
	var hair := Color(0.25, 0.16, 0.1)
	var scarf := Color(0.15, 0.7, 0.7)
	var tunic := Color(0.55, 0.35, 0.2)
	var pants := Color(0.2, 0.22, 0.32)
	var boots := Color(0.3, 0.2, 0.12)
	if hurt_flash > 0.0:
		modulate = Color(1, 0.5, 0.5)
	else:
		modulate = Color.WHITE
	var leg := sin(_walk_t * 1.0) * 2.0
	var airborne := not on_ground
	# 腿
	_r(2, 20, 3, 6 + (leg if not airborne else -1.0), pants)
	_r(7, 20, 3, 6 - (leg if not airborne else 1.0), pants)
	_r(1, 25 + (leg if not airborne else -1.0), 5, 3, boots)
	_r(6, 25 - (leg if not airborne else 1.0), 5, 3, boots)
	# 身体
	_r(1, 11, 10, 10, tunic)
	_r(1, 18, 10, 2, tunic.darkened(0.3))
	# 手臂
	_r(8, 12 - leg * 0.5, 3, 7, skin.darkened(0.08))
	# 头
	_r(2, 1, 8, 9, skin)
	_r(1, 0, 10, 3, hair)
	_r(1, 0, 3, 7, hair)
	_r(7, 4, 2, 2, Color(0.1, 0.1, 0.15))  # 眼睛
	# 围巾（在身后飘）
	_r(1, 9, 10, 3, scarf)
	_r(-2, 10 + (1.0 if airborne else 0.0), 3, 2, scarf.darkened(0.15))
