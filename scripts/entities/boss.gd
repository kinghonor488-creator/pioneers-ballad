class_name Boss
extends Enemy
## Boss：比普通敌人大得多，有两个阶段（血量低于一半进入二阶段，攻击更凶）。
## 不会被击退或打断；玩家死亡或跑得太远时 Boss 会离开。
##
## 泥沼巨像（boss_mud）：
##   跳向玩家，落地时向两边掀起泥浪；每第三跳是高高跃起的重砸（震屏）。
##   被地形卡住或离玩家太远时会钻进地里，从玩家附近钻出来。
##   二阶段：跳得更快、泥浪更快，重砸时召唤泥团怪。
## 灵晶守望者（boss_warden）：
##   绕着玩家飞，定时放出一圈晶刺；蓄力（发光）后朝玩家猛冲。
##   环形晶刺能穿过岩石（它常常飞在石头里）；二阶段：晶刺更多、冲刺更快，
##   并且会从头顶降下晶刺雨（这个会被天花板挡住，可以找地方躲）。

const LEAVE_DIST := 110.0 * 16.0

var phase := 1
var state := ""
var state_t := 1.2

var _jumps := 0
var _big_jump := false
var _stuck_t := 0.0
var _hidden := 0.0
var _orbit_a := 0.0
var _shot_t := 2.0
var _rain_t := 4.0


func tick(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_squash = maxf(0.0, _squash - delta * 3.0)
	if combat.game.dead or center().distance_to(target.center()) > LEAVE_DIST:
		combat.boss_left(self)
		return
	if phase == 1 and hp < max_hp * 0.5:
		phase = 2
		combat.boss_phase_changed(self)
	var to_p := target.center() - center()
	if absf(to_p.x) > 4.0 and state != "dash":
		facing = 1 if to_p.x > 0.0 else -1
	match String(def.ai):
		"boss_mud":
			_mud(delta, to_p)
		"boss_warden":
			_warden(delta, to_p)
	queue_redraw()


## Boss 不会被击退，也不会被打断
func hit(amount: int, _kb: Vector2) -> bool:
	return super.hit(amount, Vector2.ZERO)


# ---------------------------------------------------------------- 泥沼巨像

func _mud(delta: float, to_p: Vector2) -> void:
	if _hidden > 0.0:
		_hidden -= delta
		if _hidden <= 0.0:
			_emerge()
		return
	_fall(delta)
	if on_ground:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		state_t -= delta
		if state_t <= 0.0:
			_jumps += 1
			_big_jump = _jumps % 3 == 0
			if _big_jump:
				velocity = Vector2(clampf(to_p.x * 1.1, -280.0, 280.0), -640.0)
			else:
				velocity = Vector2(signf(to_p.x) * (160.0 if phase == 1 else 230.0), -420.0)
			state_t = 1.1 if phase == 1 else 0.7
	var was := on_ground
	_move(delta)
	if on_ground and not was:
		_land()
	# 卡住了（推不动、离太远）就钻地
	if (hit_wall and on_ground) or absf(to_p.x) > 28.0 * 16.0:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta)
	if _stuck_t > 2.5 or to_p.length() > 45.0 * 16.0:
		_burrow()


func _land() -> void:
	_squash = 1.0
	var spd := 210.0 if phase == 1 else 280.0
	var y := position.y + body_size.y - 7.0
	var dmg := int(def.wave_damage)
	combat.spawn_hostile_shot(Vector2(position.x - 2.0, y), Vector2(-spd, 0), dmg, "wave")
	combat.spawn_hostile_shot(Vector2(position.x + body_size.x + 2.0, y), Vector2(spd, 0), dmg, "wave")
	combat.game.shake(7.0 if _big_jump else 3.0)
	if _big_jump and phase == 2:
		for s in [-1.0, 1.0]:
			combat.spawn("mudling", position + Vector2(body_size.x * 0.5 - 7.0 + s * 14.0, 4.0))


func _burrow() -> void:
	_hidden = 1.2
	_stuck_t = 0.0
	visible = false
	velocity = Vector2.ZERO
	combat.popup(center(), "钻进了地里！", Color(0.9, 0.75, 0.5))


func _emerge() -> void:
	var pc := Vector2i(target.center() / 16.0)
	for attempt in 12:
		var side := 1 if randf() < 0.5 else -1
		var spot: Variant = combat.find_spawn_spot(pc.x + side * randi_range(7, 14), pc.y - 8, id)
		if spot != null:
			position = spot
			velocity = Vector2(0, -200)
			visible = true
			state_t = 0.8
			combat.game.shake(5.0)
			return
	_hidden = 0.5  # 没找到地方，过一会儿再试


# ---------------------------------------------------------------- 灵晶守望者

func _warden(delta: float, to_p: Vector2) -> void:
	state_t -= delta
	match state:
		"windup":
			velocity *= 0.9
			position += velocity * delta
			if state_t <= 0.0:
				state = "dash"
				state_t = 0.55
				velocity = to_p.normalized() * (480.0 if phase == 1 else 580.0)
		"dash":
			position += velocity * delta
			if state_t <= 0.0:
				state = "orbit"
				state_t = randf_range(4.0, 6.0) if phase == 1 else randf_range(3.0, 4.5)
		_:
			state = "orbit"
			_orbit_a += delta * (0.8 if phase == 1 else 1.2)
			var spot := target.center() + Vector2(cos(_orbit_a) * 170.0, sin(_orbit_a) * 60.0 - 110.0)
			var want := (spot - center()) * 3.0
			if want.length() > float(def.speed):
				want = want.normalized() * float(def.speed)
			velocity = velocity.move_toward(want, 700.0 * delta)
			position += velocity * delta
			_shot_t -= delta
			if _shot_t <= 0.0:
				_ring()
				_shot_t = 2.4 if phase == 1 else 1.7
			if state_t <= 0.0:
				state = "windup"
				state_t = 0.7
	if phase == 2:
		_rain_t -= delta
		if _rain_t <= 0.0:
			_rain()
			_rain_t = 4.5


func _ring() -> void:
	var n := 8 if phase == 1 else 12
	var dmg := int(def.shard_damage)
	for i in n:
		var dir := Vector2.from_angle(TAU * i / n + _t)
		combat.spawn_hostile_shot(center() + dir * 18.0, dir * 170.0, dmg, "shard", true)  # 环形晶刺能穿墙


func _rain() -> void:
	var dmg := int(def.shard_damage)
	for i in 5:
		var x := target.center().x + (i - 2) * 48.0 + randf_range(-10.0, 10.0)
		combat.spawn_hostile_shot(Vector2(x, target.center().y - 230.0), Vector2(0, 240.0), dmg, "shard")


# ---------------------------------------------------------------- 外观

func _draw() -> void:
	modulate = Color(1, 0.55, 0.55) if _flash > 0.0 else Color.WHITE
	match String(def.art):
		"colossus":
			_draw_colossus()
		"warden":
			_draw_warden()


func _draw_colossus() -> void:
	var c: Color = def.color
	var w := body_size.x
	var h := body_size.y
	var sq := _squash * 4.0
	# 身体：下面是方的，上面是半圆的顶
	var pts := PackedVector2Array()
	var cx := w * 0.5
	var top := 4.0 + sq
	for i in 13:
		var a := PI + PI * i / 12.0
		pts.append(Vector2(cx + cos(a) * (cx + sq), h * 0.55 + sin(a) * (h * 0.55 - top)))
	pts.append(Vector2(w + sq, h))
	pts.append(Vector2(-sq, h))
	draw_colored_polygon(pts, c)
	# 苔藓、石块、裂纹
	draw_rect(Rect2(cx - 12, top, 24, 4), Color(0.3, 0.5, 0.22))
	draw_rect(Rect2(cx - 16, top + 3, 6, 3), Color(0.3, 0.5, 0.22))
	for r in [Rect2(5, h - 14, 7, 6), Rect2(w - 13, h - 18, 8, 7), Rect2(cx + 4, h - 9, 6, 5)]:
		draw_rect(r, c.darkened(0.35))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c.lightened(0.15))
	draw_line(Vector2(cx - 4, top + 10), Vector2(cx - 9, top + 18), c.darkened(0.45), 1.0)
	# 眼睛和嘴
	var eye := Color(1.0, 0.85, 0.3) if phase == 1 else Color(1.0, 0.25, 0.2)
	var ex := cx + facing * 4.0
	draw_rect(Rect2(ex - 10, h * 0.42 + sq, 6, 4), eye)
	draw_rect(Rect2(ex + 4, h * 0.42 + sq, 6, 4), eye)
	draw_rect(Rect2(ex - 7, h * 0.66 + sq, 14, 2), c.darkened(0.6))


func _draw_warden() -> void:
	var c: Color = def.color if phase == 1 else Color(0.85, 0.55, 1.0)
	var mid := body_size * 0.5
	var glow := 0.3 + 0.2 * sin(_t * 4.0)
	if state == "windup":
		glow = 0.6 + 0.4 * sin(_t * 30.0)
	draw_circle(mid, 22.0, Color(c.r, c.g, c.b, glow * 0.4))
	# 环绕的晶刺
	for i in 4:
		var a := _t * (1.5 if phase == 1 else 2.4) + TAU * i / 4.0
		var p := mid + Vector2.from_angle(a) * 19.0
		var d := Vector2.from_angle(a)
		var n := d.orthogonal()
		draw_colored_polygon(PackedVector2Array([p + d * 6.0, p + n * 2.5, p - d * 4.0, p - n * 2.5]), c.lightened(0.2))
	# 核心
	draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -13), mid + Vector2(11, 0), mid + Vector2(0, 13), mid + Vector2(-11, 0)]), c)
	draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -13), mid + Vector2(11, 0), mid + Vector2(0, 0), mid + Vector2(-11, 0)]), c.lightened(0.3))
	# 眼睛看着玩家
	var look := (target.center() - global_position - mid).normalized() * 2.0 if is_instance_valid(target) else Vector2.ZERO
	draw_circle(mid, 4.5, Color(0.95, 0.98, 1.0))
	draw_circle(mid + look, 2.2, Color(0.1, 0.15, 0.3))
