class_name Enemy
extends TileBody
## 敌人：数据来自 EnemyDB，行为由 ai 字段决定，外观由 art 字段决定（全部用代码绘制）。
## 由 Combat 每个物理帧调用 tick()，这样暂停菜单打开时敌人也会一起停下。

signal died(enemy: Enemy)

const GRAVITY := 1100.0
const MAX_FALL := 700.0

var id := ""
var def := {}
var hp := 1.0
var max_hp := 1.0
var facing := 1
var target: Player
var combat: Node          ## Combat，用来发射敌方弹幕

var _t := 0.0
var _ai_timer := 0.0
var _shoot_timer := 0.0
var _stun := 0.0
var _flash := 0.0
var _wander := 1.0
var _fly_dir := Vector2.ZERO
var _squash := 0.0
var poison_t := 0.0          ## 中毒剩余时间（毒刺短剑造成）
var _poison_acc := 0.0


func setup(enemy_id: String, w: WorldData, player: Player, combat_ref: Node) -> void:
	id = enemy_id
	def = EnemyDB.get_def(id)
	world = w
	target = player
	combat = combat_ref
	body_size = def.size
	max_hp = float(def.hp)
	hp = max_hp
	step_up = def.ai == "walker"
	_ai_timer = randf_range(0.4, 1.4)
	_shoot_timer = randf_range(1.0, 2.0)
	_wander = 1.0 if randf() < 0.5 else -1.0
	_t = randf() * 10.0
	if def.has("glow"):
		add_to_group("light")
	if combat.game.lighting != null:
		material = combat.game.lighting.material


## 发光的敌人（游魂、灵晶傀儡、余烬魔、Boss）本身就是光源
func light_source() -> Array:
	return [center(), def.color, Lighting.strength_for_radius(float(def.get("glow", 0.0)))]


func flying() -> bool:
	return EnemyDB.is_flying(id)


func tick(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_squash = maxf(0.0, _squash - delta * 4.0)
	if poison_t > 0.0:
		poison_t -= delta
		_poison_acc += 5.0 * delta
		if _poison_acc >= 1.0:
			var n := int(_poison_acc)
			_poison_acc -= n
			hp -= n
			if hp <= 0.0:
				died.emit(self)
				queue_free()
				return
	var to_p := target.center() - center()
	if absf(to_p.x) > 2.0:
		facing = 1 if to_p.x > 0.0 else -1
	if _stun > 0.0:
		_stun -= delta
		velocity *= 0.92 if flying() else 1.0
		if not flying():
			_fall(delta)
		_move(delta)
	else:
		match String(def.ai):
			"hopper":
				_ai_hopper(delta, to_p)
			"walker":
				_ai_walker(delta, to_p)
			"flyer":
				_ai_flyer(delta, to_p)
			"bat":
				_ai_bat(delta, to_p)
			"shooter":
				_ai_shooter(delta, to_p)
			"turret":
				_ai_turret(delta, to_p)
	queue_redraw()


## 受到伤害。kb 是击退速度。返回是否被打死。
func hit(amount: int, kb: Vector2) -> bool:
	hp -= amount
	_flash = 0.15
	_stun = 0.18
	velocity = kb * (1.0 - float(def.get("kb_resist", 0.0)))
	if hp <= 0.0:
		died.emit(self)
		queue_free()
		return true
	return false


func _fall(delta: float) -> void:
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)


func _move(delta: float) -> void:
	if def.get("phase", false):
		position += velocity * delta
	else:
		move_with_collision(velocity * delta)


func _ai_hopper(delta: float, to_p: Vector2) -> void:
	if on_ground:
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			var dir := signf(to_p.x) if to_p.length() < 40.0 * TS else _wander
			velocity = Vector2(dir * float(def.speed) * randf_range(0.8, 1.2), -float(def.jump) * randf_range(0.8, 1.1))
			_ai_timer = randf_range(0.8, 1.8)
			_squash = 1.0
	_fall(delta)
	_move(delta)


func _ai_walker(delta: float, to_p: Vector2) -> void:
	var dir := _wander
	if to_p.length() < 32.0 * TS:
		dir = signf(to_p.x) if absf(to_p.x) > 4.0 else 0.0
	else:
		_ai_timer -= delta
		if _ai_timer <= 0.0:
			_wander = -_wander
			_ai_timer = randf_range(2.0, 5.0)
	velocity.x = move_toward(velocity.x, dir * float(def.speed), 500.0 * delta)
	_fall(delta)
	_move(delta)
	if hit_wall and on_ground:
		velocity.y = -320.0  # 被挡住就跳一下


func _ai_flyer(delta: float, to_p: Vector2) -> void:
	var desired := to_p.normalized() * float(def.speed) + Vector2(0, sin(_t * 3.0) * 30.0)
	velocity = velocity.move_toward(desired, 160.0 * delta)
	_move(delta)


func _ai_bat(delta: float, to_p: Vector2) -> void:
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		var chase := to_p.normalized() if to_p.length() < 30.0 * TS else Vector2.ZERO
		_fly_dir = (chase + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 0.9).normalized()
		_ai_timer = randf_range(0.35, 0.9)
	velocity = velocity.move_toward(_fly_dir * float(def.speed), 500.0 * delta)
	var before := velocity
	_move(delta)
	if hit_wall:
		velocity.x = -before.x * 0.8
		_fly_dir.x = -_fly_dir.x
	if velocity.y == 0.0 and before.y != 0.0:
		velocity.y = -before.y * 0.8
		_fly_dir.y = -_fly_dir.y


func _ai_shooter(delta: float, to_p: Vector2) -> void:
	# 停在玩家斜上方一段距离外
	var spot := target.center() + Vector2(-signf(to_p.x) * 110.0, -70.0 + sin(_t * 1.5) * 20.0)
	var d := spot - center()
	velocity = velocity.move_toward(d.normalized() * float(def.speed) * clampf(d.length() / 40.0, 0.0, 1.0), 240.0 * delta)
	_move(delta)
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and to_p.length() < 22.0 * TS:
		var sh: Dictionary = def.shoot
		combat.spawn_hostile_shot(center(), to_p.normalized() * float(sh.speed), int(sh.damage))
		_shoot_timer = float(sh.cooldown) * randf_range(0.8, 1.2)


func _draw_biome_art(c: Color, w: float, h: float) -> void:
	match String(def.art):
		"wolf":
			var leg := sin(_t * 14.0) * 1.5 if absf(velocity.x) > 5.0 else 0.0
			for lx in [3.0, 7.0, 13.0, 17.0]:
				draw_rect(Rect2(lx - 1 + (leg if int(lx) % 2 == 1 else -leg), h - 4, 2, 4), c.darkened(0.35))
			draw_rect(Rect2(2, 3, w - 6, h - 7), c)
			draw_rect(Rect2(2, 3, w - 6, 2), c.lightened(0.2))
			var hx := w - 6.0 if facing > 0 else 0.0
			draw_rect(Rect2(hx, 0, 6, 6), c)
			draw_rect(Rect2(hx + (4 if facing > 0 else 0), 3, 2, 2), c.darkened(0.2))
			draw_rect(Rect2(hx + (3 if facing > 0 else 1), 1, 1, 1), Color(0.2, 0.5, 0.9))
			draw_rect(Rect2(hx + (1 if facing > 0 else 3), -2, 2, 2), c.darkened(0.15))
			var tx := 0.0 if facing > 0 else w - 3.0
			draw_rect(Rect2(tx, 1, 3, 3), c.lightened(0.1))
		"hornet":
			var mid := body_size * 0.5
			var flap := sin(_t * 30.0) * 3.0
			draw_colored_polygon(PackedVector2Array([mid + Vector2(-1, -2), mid + Vector2(-4, -6 - flap), mid + Vector2(2, -3)]), Color(0.9, 0.95, 1.0, 0.7))
			draw_colored_polygon(PackedVector2Array([mid + Vector2(1, -2), mid + Vector2(5, -6 + flap), mid + Vector2(3, -2)]), Color(0.9, 0.95, 1.0, 0.7))
			for i in 3:
				draw_rect(Rect2(mid.x - 5 + i * 3, mid.y - 2, 3, 5), c if i % 2 == 0 else Color(0.15, 0.12, 0.08))
			draw_line(mid + Vector2(-facing * 6, 2), mid + Vector2(-facing * 8, 4), Color(0.2, 0.15, 0.1), 1.0)
			draw_circle(mid + Vector2(facing * 5, 0), 2.0, Color(0.2, 0.15, 0.1))
		"plant":
			var sq := _squash * 2.0
			draw_rect(Rect2(w * 0.5 - 1, h * 0.45, 2, h * 0.55), Color(0.25, 0.55, 0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.75), Vector2(1, h * 0.55), Vector2(4, h * 0.85)]), Color(0.3, 0.65, 0.25))
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.7), Vector2(w - 1, h * 0.5), Vector2(w - 4, h * 0.8)]), Color(0.3, 0.65, 0.25))
			draw_circle(Vector2(w * 0.5, 6), 6.0 + sq, c)
			draw_circle(Vector2(w * 0.5 + facing * 2, 6), 2.5 + sq * 0.5, Color(0.25, 0.05, 0.1))
			for i in 5:
				var a := TAU * i / 5.0 + _t
				draw_circle(Vector2(w * 0.5, 6) + Vector2.from_angle(a) * 6.5, 1.0, Color(1, 0.9, 0.5))
		"frog":
			var sq := _squash * 2.0
			draw_rect(Rect2(1, 3 + sq, w - 2, h - 3 - sq), c)
			draw_rect(Rect2(1, h - 3, w - 2, 3), c.lightened(0.25))
			draw_rect(Rect2(2, 0 + sq, 4, 4), c)
			draw_rect(Rect2(w - 6, 0 + sq, 4, 4), c)
			draw_rect(Rect2(3, 1 + sq, 2, 2), Color(0.95, 0.85, 0.3))
			draw_rect(Rect2(w - 5, 1 + sq, 2, 2), Color(0.95, 0.85, 0.3))
			draw_line(Vector2(4, h - 5), Vector2(w - 4, h - 5), c.darkened(0.4), 1.0)
		"urchin":
			var mid := body_size * 0.5 + Vector2(0, 1)
			for i in 10:
				var a := TAU * i / 10.0 + sin(_t * 2.0) * 0.1
				draw_line(mid, mid + Vector2.from_angle(a) * 9.0, c.lightened(0.3), 1.0)
			draw_circle(mid, 5.5, c)
			draw_circle(mid + Vector2(-1.5, -1.5), 1.5, Color.WHITE)
			draw_rect(Rect2(mid.x + facing * 2 - 1, mid.y - 1, 2, 2), Color(0.2, 0.1, 0.3))
		"phantom":
			var a := 0.55 + 0.25 * sin(_t * 4.0)
			var pts := PackedVector2Array()
			for i in 9:
				var ang := PI + PI * i / 8.0
				pts.append(Vector2(w * 0.5 + cos(ang) * w * 0.5, h * 0.45 + sin(ang) * h * 0.45))
			for i in 4:
				pts.append(Vector2(w - i * w / 3.0, h - (2.0 if i % 2 == 0 else 0.0) + sin(_t * 6.0 + i) * 1.5))
			draw_colored_polygon(pts, Color(c.r, c.g, c.b, a))
			draw_rect(Rect2(w * 0.5 - 4 + facing, h * 0.35, 2, 3), Color(0.15, 0.1, 0.3))
			draw_rect(Rect2(w * 0.5 + 2 + facing, h * 0.35, 2, 3), Color(0.15, 0.1, 0.3))


func _ai_turret(delta: float, to_p: Vector2) -> void:
	velocity.x = 0.0
	_fall(delta)
	_move(delta)
	_shoot_timer -= delta
	if _shoot_timer <= 0.0 and to_p.length() < 18.0 * TS:
		var sh: Dictionary = def.shoot
		var mouth := position + Vector2(body_size.x * 0.5, 4.0)
		var aim := (target.center() - mouth).normalized()
		combat.spawn_hostile_shot(mouth, aim * float(sh.speed), int(sh.damage), String(sh.get("kind", "fireball")), false, sh.get("inflict", []))
		_shoot_timer = float(sh.cooldown) * randf_range(0.8, 1.2)
		_squash = 1.0


# ---------------------------------------------------------------- 外观

func _draw() -> void:
	modulate = Color(1, 0.45, 0.45) if _flash > 0.0 else (Color(0.7, 1.0, 0.6) if poison_t > 0.0 else Color.WHITE)
	var c: Color = def.color
	var w := body_size.x
	var h := body_size.y
	match String(def.art):
		"blob":
			var sq := _squash * 2.0
			var r := Rect2(-sq * 0.5, sq, w + sq, h - sq)
			draw_rect(Rect2(r.position + Vector2(1, 2), r.size - Vector2(2, 2)), c)
			draw_rect(Rect2(r.position + Vector2(2, 0), r.size - Vector2(4, 0)), c)
			draw_rect(Rect2(r.position + Vector2(3, 1), Vector2(3, 2)), c.lightened(0.35))
			var ex := w * 0.5 + facing * 2.0
			draw_rect(Rect2(ex - 3, h * 0.45, 2, 2), Color(0.1, 0.08, 0.05))
			draw_rect(Rect2(ex + 1, h * 0.45, 2, 2), Color(0.1, 0.08, 0.05))
		"wisp":
			var a := 0.65 + 0.25 * sin(_t * 6.0)
			var mid := body_size * 0.5
			for i in 3:
				draw_circle(mid + Vector2(-facing * (4.0 + i * 3.0), sin(_t * 5.0 + i) * 2.0), 3.0 - i * 0.7, Color(c.r, c.g, c.b, a * 0.5))
			draw_circle(mid, 6.0, Color(c.r, c.g, c.b, a * 0.45))
			draw_circle(mid, 4.0, Color(1, 1, 1, a))
			draw_rect(Rect2(mid + Vector2(facing * 1.0 - 1.0, -1), Vector2(1, 2)), Color(0.1, 0.2, 0.4))
		"bat":
			var mid := body_size * 0.5
			var flap := sin(_t * 18.0) * 4.0
			for s in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([mid + Vector2(s * 2, -1), mid + Vector2(s * 8, -3 - flap), mid + Vector2(s * 7, 2)]), c.darkened(0.2))
			draw_circle(mid, 3.5, c)
			draw_rect(Rect2(mid + Vector2(-2, -2), Vector2(1, 1)), Color(1, 0.3, 0.3))
			draw_rect(Rect2(mid + Vector2(1, -2), Vector2(1, 1)), Color(1, 0.3, 0.3))
		"beetle":
			var leg := sin(_t * 12.0) * 1.5 if absf(velocity.x) > 5.0 else 0.0
			for i in 3:
				var lx := 4.0 + i * 5.0
				draw_line(Vector2(lx, h - 3), Vector2(lx - 1 + (leg if i % 2 == 0 else -leg), h), c.darkened(0.5), 1.0)
			draw_rect(Rect2(1, 2, w - 2, h - 5), c)
			draw_rect(Rect2(2, 1, w - 4, 2), c.lightened(0.25))
			draw_line(Vector2(w * 0.5, 2), Vector2(w * 0.5, h - 4), c.darkened(0.35), 1.0)
			var hx := w - 3.0 if facing > 0 else 0.0
			draw_rect(Rect2(hx, h - 7, 3, 4), c.darkened(0.3))
		"golem":
			draw_rect(Rect2(3, 8, w - 6, h - 12), c.darkened(0.45))
			draw_rect(Rect2(2, h - 4, 5, 4), c.darkened(0.5))
			draw_rect(Rect2(w - 7, h - 4, 5, 4), c.darkened(0.5))
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w - 3, 7), Vector2(w * 0.5, 12), Vector2(3, 7)]), c)
			draw_colored_polygon(PackedVector2Array([Vector2(1, 10), Vector2(4, 9), Vector2(3, 16)]), c.darkened(0.15))
			draw_colored_polygon(PackedVector2Array([Vector2(w - 1, 10), Vector2(w - 4, 9), Vector2(w - 3, 16)]), c.darkened(0.15))
			draw_rect(Rect2(w * 0.5 - 1 + facing, 5, 2, 2), Color.WHITE)
		"imp":
			var flap := sin(_t * 10.0) * 3.0
			for s in [-1.0, 1.0]:
				var base := Vector2(w * 0.5, 6)
				draw_colored_polygon(PackedVector2Array([base + Vector2(s * 2, 0), base + Vector2(s * 10, -4 - flap), base + Vector2(s * 8, 5)]), c.darkened(0.45))
			draw_rect(Rect2(3, 4, w - 6, h - 6), c.darkened(0.25))
			draw_rect(Rect2(4, 2, w - 8, 6), c)
			draw_rect(Rect2(3, 0, 2, 3), c.darkened(0.5))
			draw_rect(Rect2(w - 5, 0, 2, 3), c.darkened(0.5))
			draw_rect(Rect2(w * 0.5 - 3 + facing, 4, 2, 2), Color(1, 1, 0.5))
			draw_rect(Rect2(w * 0.5 + 1 + facing, 4, 2, 2), Color(1, 1, 0.5))
			draw_rect(Rect2(4, h - 2, 2, 2), c.darkened(0.4))
			draw_rect(Rect2(w - 6, h - 2, 2, 2), c.darkened(0.4))
	_draw_biome_art(c, w, h)
	if hp < max_hp:
		var bw := maxf(w, 14.0)
		var bx := (w - bw) * 0.5
		draw_rect(Rect2(bx, -5, bw, 2), Color(0.2, 0.05, 0.05, 0.85))
		draw_rect(Rect2(bx, -5, bw * clampf(hp / max_hp, 0.0, 1.0), 2), Color(0.9, 0.25, 0.25))
