class_name Projectile
extends Node2D
## 飞行道具：玩家的箭矢 / 法术弹，敌人的火球。由 Combat 每个物理帧调用 tick()。

var combat: Node
var world: WorldData
var kind := "arrow"         ## "arrow" / "bolt" / "fireball" / "wave"（泥浪）/ "shard"（晶刺）
var velocity := Vector2.ZERO
var gravity := 0.0
var hostile := false        ## true = 敌人发出的，打玩家
var damage := 0             ## 敌方弹幕的伤害
var weapon: Variant = null  ## 玩家弹幕：发射它的武器（算伤害、暴击、熟练度）
var extra_damage := 0.0     ## 箭矢附加伤害
var pierce := 1
var phase := false          ## true = 穿过方块（守望者的环形晶刺）
var inflict: Array = []     ## 敌方弹幕命中玩家时附带的负面效果
var color := Color.WHITE
var life := 3.0
var dead := false

var _hit := {}


var _light := 0.0


## 让这颗弹幕发光（法术弹、火球、晶刺）
func setup_light(strength: float) -> void:
	_light = strength
	add_to_group("light")


func light_source() -> Array:
	return [position, color, _light]


func tick(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_die()
		return
	velocity.y += gravity * delta
	var motion := velocity * delta
	var steps := maxi(1, ceili(motion.length() / 6.0))
	for i in steps:
		position += motion / steps
		if kind == "wave":
			_follow_ground()
		if not phase and world.is_solid(floori(position.x / 16.0), floori(position.y / 16.0)):
			_die()
			return
		if _check_hits():
			return
	if kind != "wave":
		rotation = velocity.angle()
	queue_redraw()


## 泥浪贴着地面走：能爬上一格高的台阶，遇到坑会落下去
func _follow_ground() -> void:
	var tx := floori(position.x / 16.0)
	var ty := floori(position.y / 16.0)
	if world.is_solid(tx, ty) and not world.is_solid(tx, ty - 1):
		position.y -= 16.0
	elif not world.is_solid(tx, ty) and not world.is_solid(tx, ty + 1) and world.is_solid(tx, ty + 2):
		position.y += 16.0


## 返回 true 表示弹幕已经消失
func _check_hits() -> bool:
	if hostile:
		var p: Player = combat.player()
		if p.visible and p.rect().grow(2.0).has_point(position):
			combat.hurt_player(damage, position, String({"wave": "泥浪", "shard": "晶刺", "seed": "毒种"}.get(kind, "火球")), inflict)
			_die()
			return true
		return false
	for e in combat.enemies:
		if is_instance_valid(e) and e.hp > 0.0 and e.visible and not _hit.has(e) and e.rect().grow(3.0).has_point(position):
			_hit[e] = true
			combat.projectile_hit(self, e)
			pierce -= 1
			if pierce <= 0:
				_die()
				return true
	return false


func _die() -> void:
	if dead:
		return
	dead = true
	queue_free()


func _draw() -> void:
	match kind:
		"arrow":
			draw_line(Vector2(-7, 0), Vector2(4, 0), Color(0.6, 0.42, 0.25), 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(3, -2), Vector2(3, 2)]), color)
			draw_line(Vector2(-7, 0), Vector2(-9, -2), Color(0.95, 0.95, 0.95), 1.0)
			draw_line(Vector2(-7, 0), Vector2(-9, 2), Color(0.95, 0.95, 0.95), 1.0)
		"bolt":
			draw_circle(Vector2(-6, 0), 2.0, Color(color.r, color.g, color.b, 0.35))
			draw_circle(Vector2(-3, 0), 3.0, Color(color.r, color.g, color.b, 0.55))
			draw_circle(Vector2.ZERO, 4.0, color)
			draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
		"wave":
			var k := 0.6 + 0.4 * sin(life * 20.0)
			draw_colored_polygon(PackedVector2Array([Vector2(-8, 6), Vector2(-5, -4 * k - 2), Vector2(0, -7 * k - 1), Vector2(5, -4 * k - 2), Vector2(8, 6)]), Color(0.5, 0.36, 0.22))
			draw_line(Vector2(-4, -3 * k), Vector2(4, -3 * k), Color(0.7, 0.55, 0.35), 1.0)
		"shard":
			draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(0, -2.5), Vector2(-6, 0), Vector2(0, 2.5)]), color)
			draw_line(Vector2(-5, 0), Vector2(6, 0), Color(1, 1, 1, 0.8), 1.0)
		"seed":
			draw_circle(Vector2.ZERO, 3.0, Color(0.35, 0.6, 0.2))
			draw_circle(Vector2(1, -1), 1.2, Color(0.7, 0.95, 0.4))
		"fireball":
			draw_circle(Vector2(-5, 0), 3.0, Color(1, 0.4, 0.1, 0.4))
			draw_circle(Vector2.ZERO, 4.5, Color(1, 0.45, 0.12))
			draw_circle(Vector2(1, 0), 2.5, Color(1, 0.9, 0.4))
