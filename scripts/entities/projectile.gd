class_name Projectile
extends Node2D
## 飞行道具：玩家的箭矢 / 法术弹，敌人的火球。由 Combat 每个物理帧调用 tick()。

var combat: Node
var world: WorldData
var kind := "arrow"         ## "arrow" / "bolt" / "fireball"
var velocity := Vector2.ZERO
var gravity := 0.0
var hostile := false        ## true = 敌人发出的，打玩家
var damage := 0             ## 敌方弹幕的伤害
var weapon: Variant = null  ## 玩家弹幕：发射它的武器（算伤害、暴击、熟练度）
var extra_damage := 0.0     ## 箭矢附加伤害
var pierce := 1
var color := Color.WHITE
var life := 3.0
var dead := false

var _hit := {}


func setup_light(radius: float) -> void:
	var l := WorldRenderer.make_light(radius, color, 0.9)
	add_child(l)


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
		if world.is_solid(floori(position.x / 16.0), floori(position.y / 16.0)):
			_die()
			return
		if _check_hits():
			return
	rotation = velocity.angle()
	queue_redraw()


## 返回 true 表示弹幕已经消失
func _check_hits() -> bool:
	if hostile:
		var p: Player = combat.player()
		if p.visible and p.rect().grow(2.0).has_point(position):
			combat.hurt_player(damage, position, "火球")
			_die()
			return true
		return false
	for e in combat.enemies:
		if is_instance_valid(e) and e.hp > 0.0 and not _hit.has(e) and e.rect().grow(3.0).has_point(position):
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
		"fireball":
			draw_circle(Vector2(-5, 0), 3.0, Color(1, 0.4, 0.1, 0.4))
			draw_circle(Vector2.ZERO, 4.5, Color(1, 0.45, 0.12))
			draw_circle(Vector2(1, 0), 2.5, Color(1, 0.9, 0.4))
