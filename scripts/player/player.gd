class_name Player
extends TileBody
## 玩家：移动、跳跃、摔落伤害、受击无敌时间、法力。碰撞逻辑在 TileBody 里。

signal landed_hard(damage: int)

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

var facing := 1
var move_mult := 1.0
var jump_mult := 1.0
var no_fall := false
var hp := 100.0
var max_hp := 100
var hurt_flash := 0.0
var invuln := 0.0          ## 受击后的无敌时间
var mana := 40.0
var max_mana := 40
var attack_anim := 0.0     ## >0 时正在挥动武器（攻击时面朝鼠标）
var light_strength := 0.4  ## 玩家身上的光（饰品、萤光药水会加强）

var _coyote := 0.0
var _jump_buffer := 0.0
var _fall_peak := 0.0
var _walk_t := 0.0


func _init() -> void:
	body_size = Vector2(W, H)
	add_to_group("light")


## 给 Lighting 用：[位置, 颜色, 亮度]
func light_source() -> Array:
	return [center(), Color(1.0, 0.95, 0.85), light_strength]


## dir: -1..1 左右输入
func step(dt: float, dir: float, jump_pressed: bool, jump_held: bool) -> void:
	velocity.x = move_toward(velocity.x, dir * RUN_SPEED * move_mult, (GROUND_ACCEL if on_ground else AIR_ACCEL) * dt)
	if dir != 0.0 and attack_anim <= 0.0:
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
	invuln = maxf(0.0, invuln - dt)
	attack_anim = maxf(0.0, attack_anim - dt)
	queue_redraw()


func teleport(px: Vector2) -> void:
	position = px
	velocity = Vector2.ZERO
	_fall_peak = px.y


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
	elif invuln > 0.0:
		modulate = Color(1, 1, 1, 0.55 if int(invuln * 20.0) % 2 == 0 else 0.9)  # 无敌时闪烁
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
