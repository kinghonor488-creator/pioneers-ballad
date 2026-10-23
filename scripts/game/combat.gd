class_name Combat
extends Node2D
## 战斗系统：刷怪和清理、玩家攻击（挥剑 / 射箭 / 法术）、伤害计算、伤害数字。
## 伤害公式：武器伤害 ×（1 + 词缀 + 熟练度 + 饰品/增益）→ 暴击 ×2 → 减去敌人防御的一半（至少 1 点）。

const SPAWN_MIN_DIST := 26      ## 刷怪离玩家至少多少格（在屏幕外）
const SPAWN_MAX_DIST := 44
const DESPAWN_DIST := 75.0      ## 离玩家太远的敌人直接消失
const CONTACT_KNOCKBACK := 230.0

var game: Node
var enemies: Array = []
var boss: Enemy = null           ## 当前在场的 Boss
var projectiles: Array = []
var spawning_enabled := true
var popups: Array = []          ## 伤害数字 {"pos", "text", "color", "t", "vy"}
var rng := RandomNumberGenerator.new()
var font: Font

var _swing := {}                ## 正在挥的剑 {"t", "dur", "dir", "weapon", "range", "hit": {}}
var _cooldown := 0.0
var _spawn_timer := 2.0


func setup(g: Node) -> void:
	game = g
	rng.seed = int(g.world_seed) * 31 + 5
	font = ThemeDB.fallback_font
	z_index = 15


func player() -> Player:
	return game.player


func clear() -> void:
	if is_instance_valid(boss) and boss.hp > 0.0:
		game.hud.notify("%s离开了……" % boss.def.name, Color(0.8, 0.7, 0.7))
	boss = null
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for p in projectiles:
		if is_instance_valid(p):
			p.queue_free()
	projectiles.clear()
	_swing = {}


# ---------------------------------------------------------------- 每帧

func physics_tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	for e in enemies.duplicate():
		if is_instance_valid(e) and e.hp > 0.0:
			e.tick(delta)
	for p in projectiles.duplicate():
		if is_instance_valid(p) and not p.dead:
			p.tick(delta)
	projectiles = projectiles.filter(func(p): return is_instance_valid(p) and not p.dead)
	enemies = enemies.filter(func(e): return is_instance_valid(e) and e.hp > 0.0)
	if boss != null and (not is_instance_valid(boss) or boss.hp <= 0.0):
		boss = null
	_update_swing(delta)
	if not game.dead:
		_contact_damage()
	if spawning_enabled:
		_spawn_tick(delta)
	_despawn()


func _process(delta: float) -> void:
	for p in popups:
		p.t -= delta
		p.pos.y += p.vy * delta
		p.vy *= 0.9
	popups = popups.filter(func(p): return p.t > 0.0)
	queue_redraw()


# ---------------------------------------------------------------- 玩家攻击

## 用武器攻击鼠标方向。返回是否真的出手了。
func use_weapon(item: Dictionary, target_px: Vector2) -> bool:
	if _cooldown > 0.0 or game.dead:
		return false
	var w := ItemDB.weapon_def(item)
	var p := player()
	var aim := (target_px - p.center()).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2(p.facing, 0)
	var speed := ItemDB.weapon_speed(item) * (1.0 + float(game.stats.get("speed", 0.0)))
	match String(w.type):
		"melee":
			var dur := clampf(0.85 / speed, 0.14, 0.35)
			_swing = {"t": 0.0, "dur": dur, "dir": 1 if aim.x >= 0.0 else -1, "weapon": item, "range": float(w.range), "hit": {}}
		"bow":
			var slot := find_ammo("arrow")
			if slot < 0:
				game.hud.hint("没有箭矢了！在工作台用木材和石块做一些。")
				return false
			var ammo: Dictionary = game.inventory.slots[slot]
			var ad: Dictionary = ItemDB.get_def(ammo.id).ammo
			var pr := _new_projectile("arrow", p.center() + aim * 8.0, aim * float(w.shot_speed), ItemDB.get_def(ammo.id).color)
			pr.gravity = 380.0
			pr.weapon = item
			pr.extra_damage = float(ad.damage)
			pr.pierce = int(ad.get("pierce", 1))
			game.inventory.consume_slot(slot, 1)
		"staff":
			var cost := int(w.mana)
			if p.mana < cost:
				game.hud.hint("法力不足！")
				return false
			p.mana -= cost
			game.mana_used()
			var pr := _new_projectile("bolt", p.center() + aim * 8.0, aim * float(w.shot_speed), ItemDB.get_def(item.id).color)
			pr.weapon = item
			pr.pierce = int(w.get("pierce", 1))
			pr.life = 1.6
			pr.setup_light(2.5)
	_cooldown = 1.0 / speed
	p.facing = 1 if aim.x >= 0.0 else -1
	p.attack_anim = minf(1.0 / speed, 0.35)
	return true


func find_ammo(ammo_type: String) -> int:
	var slots: Array = game.inventory.slots
	for i in slots.size():
		var s: Variant = slots[i]
		if s != null and String(ItemDB.get_def(s.id).get("ammo", {}).get("type", "")) == ammo_type:
			return i
	return -1


func _new_projectile(kind: String, pos: Vector2, vel: Vector2, color: Color) -> Projectile:
	var pr := Projectile.new()
	pr.combat = self
	pr.world = game.world
	pr.kind = kind
	pr.position = pos
	pr.velocity = vel
	pr.color = color
	game.add_child(pr)
	pr.z_index = 7
	projectiles.append(pr)
	return pr


func _update_swing(delta: float) -> void:
	if _swing.is_empty():
		return
	_swing.t += delta
	if _swing.t >= _swing.dur:
		_swing = {}
		return
	var p := player()
	var r: float = _swing.range
	var dir: int = _swing.dir
	var c := p.center()
	var area := Rect2(c + Vector2(0.0 if dir > 0 else -r, -r * 0.85), Vector2(r, r * 1.6))
	for e in enemies:
		if is_instance_valid(e) and e.hp > 0.0 and e.visible and not _swing.hit.has(e) and area.intersects(e.rect()):
			_swing.hit[e] = true
			deal_damage(e, _swing.weapon, 0.0, Vector2(dir, 0))


func projectile_hit(pr: Projectile, e: Enemy) -> void:
	deal_damage(e, pr.weapon, pr.extra_damage, pr.velocity.normalized())


## 玩家对敌人造成伤害（含暴击、防御、击退、熟练度、掉落）
func deal_damage(e: Enemy, weapon: Variant, extra: float, dir: Vector2) -> int:
	var stats: Dictionary = game.stats
	var raw := ItemDB.weapon_damage(weapon, extra) * (1.0 + float(stats.get("damage", 0.0)))
	var crit := rng.randf() < ItemDB.weapon_crit(weapon) + float(stats.get("crit", 0.0))
	if crit:
		raw *= 2.0
	var amount := maxi(1, roundi(raw * rng.randf_range(0.9, 1.1) - float(e.def.get("defense", 0)) * 0.5))
	var kb := ItemDB.weapon_knockback(weapon)
	var kb_vec := Vector2(signf(dir.x) if dir.x != 0.0 else float(player().facing), 0) * kb * 45.0 + Vector2(0, -60.0 - kb * 12.0)
	if e.flying():
		kb_vec = dir.normalized() * kb * 45.0
	var where := e.center()
	var killed := e.hit(amount, kb_vec)
	popup(where + Vector2(0, -10), str(amount) + ("!" if crit else ""), Color(1, 0.85, 0.2) if crit else Color(1, 1, 1))
	if weapon != null:
		game.add_weapon_xp(weapon, 5 if killed else 1)
	return amount


func _on_enemy_died(e: Enemy) -> void:
	for inst in EnemyDB.roll_drops(e.id, rng):
		game.give(inst)
	var choice: Array = e.def.get("choice", [])
	if not choice.is_empty():
		game.give(ItemDB.make(choice[rng.randi() % choice.size()], 1, rng))
	game.on_enemy_killed(e.id)
	if e == boss:
		boss = null
		game.on_boss_defeated(e.id)


func spawn_hostile_shot(pos: Vector2, vel: Vector2, dmg: int, kind: String = "fireball", phase: bool = false) -> void:
	var colors := {"fireball": Color(1.0, 0.5, 0.2), "shard": Color(0.6, 1.0, 0.95), "wave": Color(0.6, 0.45, 0.3)}
	var pr := _new_projectile(kind, pos, vel, colors.get(kind, Color.WHITE))
	pr.hostile = true
	pr.damage = dmg
	pr.phase = phase
	pr.life = 4.0 if kind != "wave" else 2.2
	if kind != "wave":
		pr.setup_light(2.0 if kind == "fireball" else 1.5)


# ---------------------------------------------------------------- Boss

## 召唤 Boss。成功返回空字符串，失败返回原因。
func summon_boss(id: String) -> String:
	var d := EnemyDB.get_def(id)
	if is_instance_valid(boss) and boss.hp > 0.0:
		return "%s还在场上！" % boss.def.name
	var layer: String = game.world.layer_name(int(player().center().y / 16.0))
	var layers: Array = d.get("summon_layers", [])
	if not layers.is_empty() and not layer in layers:
		return "%s 只能在「%s」召唤（你现在在「%s」）。" % [d.name, "、".join(layers), layer]
	var pos: Variant = null
	var pc := Vector2i(player().center() / 16.0)
	if EnemyDB.is_flying(id):
		pos = player().center() + Vector2(280.0 if rng.randf() < 0.5 else -280.0, -170.0)
	else:
		for attempt in 30:
			var side := 1 if rng.randf() < 0.5 else -1
			pos = find_spawn_spot(pc.x + side * rng.randi_range(16, 26), pc.y - 12, id)
			if pos != null:
				break
	if pos == null:
		return "附近没有足够的空间让%s出现。" % d.name
	boss = spawn(id, pos)
	game.hud.banner(String(d.get("intro", d.name + "出现了！")), Color(1.0, 0.45, 0.4))
	game.shake(6.0)
	return ""


func boss_left(b: Enemy) -> void:
	game.hud.notify("%s离开了……" % b.def.name, Color(0.8, 0.7, 0.7))
	b.hp = 0.0
	b.queue_free()
	boss = null


func boss_phase_changed(b: Enemy) -> void:
	game.hud.banner("%s被激怒了！" % b.def.name, Color(1.0, 0.35, 0.3))
	game.shake(5.0)


func hurt_player(amount: int, from: Vector2, reason: String) -> void:
	game.damage(amount, reason, from)


func _contact_damage() -> void:
	var p := player()
	if p.invuln > 0.0:
		return
	var pr := p.rect()
	for e in enemies:
		if is_instance_valid(e) and e.hp > 0.0 and e.visible and pr.intersects(e.rect()):
			hurt_player(int(e.def.damage), e.center(), String(e.def.name))
			return


func popup(pos: Vector2, text: String, color: Color) -> void:
	popups.append({"pos": pos, "text": text, "color": color, "t": 0.8, "vy": -40.0})


# ---------------------------------------------------------------- 刷怪

func max_enemies() -> int:
	if is_instance_valid(boss):
		return 2   # Boss 战时少刷一点小怪
	if game.underground_factor() > 0.5:
		return 7
	var night := 1.0 - SkyBackdrop.daylight(game.time_of_day)
	return 3 + int(night * 4.0)


func is_night() -> bool:
	return SkyBackdrop.daylight(game.time_of_day) < 0.3


func _spawn_tick(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = rng.randf_range(1.0, 2.5)
	if enemies.size() < max_enemies():
		try_spawn()


## 在玩家附近（屏幕外）找个合适的位置刷一只怪。force_id 用来指定种类（测试用）。
func try_spawn(force_id: String = "") -> Enemy:
	var w: WorldData = game.world
	var pc := Vector2i(player().center() / 16.0)
	for attempt in 16:
		var tx := pc.x + (1 if rng.randf() < 0.5 else -1) * rng.randi_range(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
		var ty := pc.y + rng.randi_range(-18, 18)
		if tx < 2 or tx >= w.width - 2 or ty < 2 or ty >= w.height - 4:
			continue
		var id := force_id
		if id == "":
			var cands := EnemyDB.candidates(w.layer_name(ty), is_night())
			if cands.is_empty():
				continue
			id = String(ItemDB.weighted_pick(cands, rng))
		var pos: Variant = find_spawn_spot(tx, ty, id)
		if pos == null:
			continue
		return spawn(id, pos)
	return null


func find_spawn_spot(tx: int, ty: int, id: String) -> Variant:
	var w: WorldData = game.world
	var size: Vector2 = EnemyDB.get_def(id).size
	var tw := ceili(size.x / 16.0)
	var th := ceili(size.y / 16.0)
	if EnemyDB.is_flying(id):
		if _area_free(tx, ty, tw, th):
			return Vector2(tx * 16, ty * 16)
		return null
	# 地面怪：往下找地面
	for y in range(ty, mini(ty + 24, w.height - 1)):
		if _area_free(tx, y - th + 1, tw, th) and w.is_solid(tx, y + 1):
			return Vector2(tx * 16, (y + 1) * 16 - size.y - 0.01)
	return null


func _area_free(x0: int, y0: int, tw: int, th: int) -> bool:
	for y in range(y0, y0 + th):
		for x in range(x0, x0 + tw):
			if game.world.is_solid(x, y):
				return false
	return true


func spawn(id: String, pos: Vector2) -> Enemy:
	var e: Enemy = Boss.new() if EnemyDB.is_boss(id) else Enemy.new()
	e.setup(id, game.world, player(), self)
	e.position = pos
	e.z_index = 6
	e.died.connect(_on_enemy_died)
	game.add_child(e)
	enemies.append(e)
	return e


func _despawn() -> void:
	var pc := player().center()
	var day := not is_night()
	for e in enemies:
		if not is_instance_valid(e) or e == boss:
			continue
		var d: float = e.center().distance_to(pc) / 16.0
		var night_only: bool = e.def.spawn.get("time", "any") == "night"
		if d > DESPAWN_DIST or (day and night_only and d > 30.0):
			e.queue_free()
			e.hp = 0.0


# ---------------------------------------------------------------- 绘制（世界坐标）

func _draw() -> void:
	if not _swing.is_empty() and is_instance_valid(game.player):
		var p := player()
		var k: float = _swing.t / _swing.dur
		var dir: int = _swing.dir
		var ang := lerpf(-2.0, 0.7, k)   # 从头顶上方挥到身前下方
		var pivot := p.center() + Vector2(dir * 2.0, -2.0)
		var reach: float = _swing.range
		# 刀光
		var pts := PackedVector2Array()
		for i in 9:
			var a := lerpf(-2.0, ang, i / 8.0) - PI * 0.25
			pts.append(pivot + Vector2(cos(a) * dir, sin(a)) * reach * 0.9)
		if pts.size() > 1:
			draw_polyline(pts, Color(1, 1, 1, 0.35 * (1.0 - k)), 3.0)
		var icon := TileArt.icon(_swing.weapon.id)
		var s := reach / 22.0
		draw_set_transform(pivot, ang * dir, Vector2(dir * s, s))
		draw_texture(icon, Vector2(-2, -14))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for pp in popups:
		var c: Color = pp.color
		c.a = clampf(pp.t * 2.0, 0.0, 1.0)
		draw_string(font, pp.pos + Vector2(1, 1), pp.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0, 0, 0, c.a))
		draw_string(font, pp.pos, pp.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, c)
