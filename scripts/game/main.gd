extends Node2D
## 游戏主控：生成世界，创建玩家/摄像机/界面，处理挖掘、放置、使用道具、合成、增益和昼夜循环。

signal world_ready

const TS := 16
const DAY_LENGTH := 720.0       ## 一整天多少秒（12 分钟）
const BASE_REACH := 5.0         ## 基础触及距离（图块）
const STATION_RADIUS := 5       ## 离制作站多少格以内算"在附近"
const MAX_LIFE_FRUITS := 5
const DAY_AMBIENT := Color(1, 1, 1)
const NIGHT_AMBIENT := Color(0.32, 0.34, 0.5)
const DAWN_AMBIENT := Color(0.95, 0.75, 0.65)
const CAVE_AMBIENT := Color(0.13, 0.12, 0.16)
const RARITY_GOLD := Color(1.0, 0.8, 0.35)

@export var world_width := 4200
@export var world_height := 1200
@export var world_seed := 0     ## 0 = 每次随机

var world: WorldData
var renderer: WorldRenderer
var player: Player
var camera: Camera2D
var inventory: Inventory
var hud: Hud
var sky: SkyBackdrop
var cursor: TileCursor
var canvas_mod: CanvasModulate
var player_light: PointLight2D
var rng := RandomNumberGenerator.new()
var ready_done := false

var time_of_day := 0.3
var day := 1
var buffs := {}                 ## 名字 -> {"effects": {}, "time": 剩余秒数}
var stats := {}                 ## 饰品 + 增益合计
var life_fruits := 0
var dead := false

var _mine_target := Vector2i(-99999, -99999)
var _mine_progress := 0.0
var _use_cooldown := 0.0
var _heal_cooldown := 0.0
var _regen_delay := 0.0
var _respawn_timer := 0.0


func _ready() -> void:
	_setup_input()
	if world_seed == 0:
		rng.randomize()
		world_seed = rng.randi_range(1, 999999)
	rng.seed = world_seed * 7 + 1

	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	sky = SkyBackdrop.new()
	sky_layer.add_child(sky)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	hud = Hud.new()
	ui_layer.add_child(hud)
	hud.loading_text = "正在生成世界（%d × %d）……" % [world_width, world_height]

	await get_tree().process_frame
	await get_tree().process_frame

	var t0 := Time.get_ticks_msec()
	world = WorldGen.generate(world_width, world_height, world_seed)
	print("[世界] 生成完成 %d×%d 种子=%d 用时 %d 毫秒" % [world_width, world_height, world_seed, Time.get_ticks_msec() - t0])

	renderer = WorldRenderer.new()
	add_child(renderer)
	renderer.setup(world)

	cursor = TileCursor.new()
	cursor.z_index = 10
	add_child(cursor)

	player = Player.new()
	player.world = world
	player.z_index = 5
	add_child(player)
	player.teleport(spawn_position())
	player.landed_hard.connect(func(dmg): damage(dmg, "摔伤"))

	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position = Vector2(Player.W, Player.H) * 0.5
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = world.width * TS
	camera.limit_bottom = world.height * TS
	player.add_child(camera)

	player_light = WorldRenderer.make_light(3.0, Color(1.0, 0.95, 0.85), 0.6)
	player_light.position = Vector2(Player.W, Player.H) * 0.5
	player.add_child(player_light)

	canvas_mod = CanvasModulate.new()
	add_child(canvas_mod)

	inventory = Inventory.new()
	_give_start_kit()
	recalc_stats()
	player.hp = player.max_hp

	renderer.update_view(player.center(), _view_size(), true)
	hud.loading_text = ""
	hud.setup(self)
	hud.notify("欢迎来到星壤纪元！按 E 打开背包和制作栏。", Color(1, 0.9, 0.5))
	ready_done = true
	world_ready.emit()


func _setup_input() -> void:
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE, KEY_W, KEY_UP])
	if not InputMap.has_action("use"):
		InputMap.add_action("use")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("use", mb)


func _bind_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _give_start_kit() -> void:
	inventory.add_instance(ItemDB.make("flint_pickaxe", 1))
	inventory.add_instance(ItemDB.make("flint_axe", 1))
	inventory.add("torch", 15)
	inventory.add("apple", 3)


func spawn_position() -> Vector2:
	return Vector2(world.spawn.x * TS + (TS - Player.W) * 0.5, world.spawn.y * TS - Player.H - 0.01)


func _view_size() -> Vector2:
	return get_viewport_rect().size / (camera.zoom if camera else Vector2(2, 2))


# ---------------------------------------------------------------- 每帧更新

func _physics_process(delta: float) -> void:
	if not ready_done or dead:
		return
	var dir := Input.get_axis("move_left", "move_right")
	player.step(delta, dir, Input.is_action_just_pressed("jump"), Input.is_action_pressed("jump"))


func _process(delta: float) -> void:
	if not ready_done:
		return
	_update_time(delta)
	_tick_buffs(delta)
	recalc_stats()
	if dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
	else:
		_regen(delta)
		_handle_use(delta)
	renderer.update_view(player.center(), _view_size())
	_update_ambient()


func _update_time(delta: float) -> void:
	time_of_day += delta / DAY_LENGTH
	if time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
		hud.notify("第 %d 天的黎明来临。" % day, Color(1, 0.85, 0.5))


func underground_factor() -> float:
	var ty := player.center().y / TS
	var s := world.surface_at(int(player.center().x / TS))
	return clampf((ty - (s + 12)) / 35.0, 0.0, 1.0)


func _update_ambient() -> void:
	var dl := SkyBackdrop.daylight(time_of_day)
	var amb := NIGHT_AMBIENT.lerp(DAY_AMBIENT, dl)
	if dl > 0.0 and dl < 1.0:
		amb = amb.lerp(DAWN_AMBIENT, sin(dl * PI) * 0.6)
	var depth := underground_factor()
	amb = amb.lerp(CAVE_AMBIENT, depth)
	canvas_mod.color = amb
	var darkness := 1.0 - amb.get_luminance()
	renderer.set_light_strength(clampf(darkness * 1.4, 0.15, 1.0))
	var light_bonus := float(stats.get("light", 0.0))
	player_light.texture_scale = (3.0 + light_bonus) * TS / 64.0
	player_light.energy = clampf(darkness * 1.2, 0.0, 1.0) * (0.55 if light_bonus <= 0.0 else 1.0)
	var cam := camera.get_screen_center_position()
	sky.time_of_day = time_of_day
	sky.depth = depth
	sky.cam_x = cam.x
	sky.horizon_y = get_viewport_rect().size.y * 0.5 + (world.layers.surface * TS - cam.y) * camera.zoom.y * 0.35


func _regen(delta: float) -> void:
	_heal_cooldown = maxf(0.0, _heal_cooldown - delta)
	_regen_delay = maxf(0.0, _regen_delay - delta)
	if _regen_delay <= 0.0 and player.hp < player.max_hp:
		player.hp = minf(player.max_hp, player.hp + 2.0 * delta)


# ---------------------------------------------------------------- 增益与属性

func _tick_buffs(delta: float) -> void:
	for k in buffs.keys():
		buffs[k].time -= delta
		if buffs[k].time <= 0.0:
			buffs.erase(k)
			hud.notify("「%s」效果结束了。" % k, Color(0.7, 0.7, 0.75))


func recalc_stats() -> void:
	var s := {"move": 0.0, "jump": 0.0, "mine": 0.0, "reach": 0.0, "light": 0.0, "nofall": false, "maxhp": 0.0}
	for a in inventory.accessories:
		if a != null:
			_merge_effects(s, ItemDB.get_def(a.id).get("effects", {}))
	for b in buffs.values():
		_merge_effects(s, b.effects)
	stats = s
	player.move_mult = 1.0 + float(s.move)
	player.jump_mult = 1.0 + float(s.jump) * 0.5
	player.no_fall = bool(s.nofall)
	player.max_hp = 100 + int(s.maxhp) + life_fruits * 20
	player.hp = minf(player.hp, player.max_hp)


func _merge_effects(s: Dictionary, eff: Dictionary) -> void:
	for k in eff:
		if typeof(eff[k]) == TYPE_BOOL:
			s[k] = bool(s.get(k, false)) or bool(eff[k])
		else:
			s[k] = float(s.get(k, 0.0)) + float(eff[k])


# ---------------------------------------------------------------- 鼠标操作

func mouse_tile() -> Vector2i:
	var m := get_global_mouse_position()
	return Vector2i(floori(m.x / TS), floori(m.y / TS))


func reach_tiles(item: Variant) -> float:
	return BASE_REACH + float(stats.get("reach", 0.0)) + ItemDB.tool_reach(item)


func in_reach(t: Vector2i, item: Variant = null) -> bool:
	var c := Vector2(t) * TS + Vector2(TS, TS) * 0.5
	return c.distance_to(player.center()) <= (reach_tiles(item) + 0.5) * TS


func _handle_use(delta: float) -> void:
	_use_cooldown = maxf(0.0, _use_cooldown - delta)
	var t := mouse_tile()
	var item: Variant = inventory.selected_item()
	cursor.target = t
	cursor.in_reach = in_reach(t, item)
	cursor.visible = not hud.blocks_mouse()
	var want := Input.is_action_pressed("use") and not hud.blocks_mouse()
	if not want:
		_mine_progress = 0.0
		cursor.progress = 0.0
		cursor.queue_redraw()
		return
	var d := ItemDB.get_def(item.id) if item != null else {}
	var cat := String(d.get("category", ""))
	if item != null and d.has("place"):
		if _use_cooldown <= 0.0 and place_item(t, inventory.selected):
			_use_cooldown = 0.12
	elif cat == "consumable":
		if Input.is_action_just_pressed("use"):
			use_consumable(inventory.selected)
	elif cat == "throwable":
		if _use_cooldown <= 0.0:
			throw_item(inventory.selected, get_global_mouse_position())
			_use_cooldown = 0.6
	else:
		mine_step(t, item, delta)
	cursor.queue_redraw()


# ---------------------------------------------------------------- 挖掘

func mine_step(t: Vector2i, item: Variant, delta: float) -> void:
	if not in_reach(t, item):
		_mine_progress = 0.0
		cursor.progress = 0.0
		return
	var id := world.get_tile(t.x, t.y)
	if id == TileDB.AIR:
		_mine_progress = 0.0
		cursor.progress = 0.0
		return
	var need := TileDB.tier(id)
	if ItemDB.tool_tier(item) < need:
		if need >= TileDB.UNBREAKABLE_TIER:
			hud.hint("%s 无法被破坏。" % TileDB.tile_name(id))
		else:
			hud.hint("%s 需要镐等级 %d 才能挖开。" % [TileDB.tile_name(id), need])
		return
	if t != _mine_target:
		_mine_target = t
		_mine_progress = 0.0
	var kind := String(TileDB.prop(id, "kind", "earth"))
	_mine_progress += ItemDB.mining_power(item, kind) * (1.0 + float(stats.get("mine", 0.0))) * delta
	var hard := TileDB.hardness(id)
	cursor.progress = clampf(_mine_progress / hard, 0.0, 1.0)
	if _mine_progress >= hard:
		_mine_progress = 0.0
		cursor.progress = 0.0
		break_tile(t, item)


## 破坏一个图块并把掉落物放进背包。返回是否成功。
func break_tile(t: Vector2i, item: Variant = null) -> bool:
	var id := world.get_tile(t.x, t.y)
	if id == TileDB.AIR or TileDB.tier(id) >= TileDB.UNBREAKABLE_TIER:
		return false
	var gained := []
	if id == TileDB.TRUNK:
		gained = _fell_tree(t)
	elif id == TileDB.RELIC_CHEST:
		world.set_tile(t.x, t.y, TileDB.AIR)
		var depth01 := clampf(float(t.y - world.layers.rock) / float(world.height - world.layers.rock), 0.0, 1.0)
		gained = ItemDB.roll_chest_loot(rng, depth01)
		hud.notify("打开了遗迹宝匣！", RARITY_GOLD)
	else:
		world.set_tile(t.x, t.y, TileDB.AIR)
		var drop := String(TileDB.prop(id, "drop", ""))
		if drop != "":
			var n := 1
			if rng.randf() < ItemDB.affix_value(item, "luck"):
				n = 2
			gained.append(ItemDB.make(drop, n))
		if id == TileDB.LEAVES and rng.randf() < 0.08:
			gained.append(ItemDB.make("apple", 1))
	for g in gained:
		give(g)
	_check_supports(t)
	if ItemDB.is_tool_item(item):
		_add_tool_xp(item, maxi(1, roundi(TileDB.hardness(id))))
	return true


## 砍倒整棵树：从砍的位置往上把相连的树干和树叶一起收掉
func _fell_tree(start: Vector2i) -> Array:
	var stack := [start]
	var seen := {start: true}
	var wood := 0
	var apples := 0
	while not stack.is_empty() and seen.size() < 400:
		var p: Vector2i = stack.pop_back()
		var id := world.get_tile(p.x, p.y)
		if id == TileDB.TRUNK:
			wood += 1
		elif id == TileDB.LEAVES:
			if rng.randf() < 0.06:
				apples += 1
		else:
			continue
		world.set_tile(p.x, p.y, TileDB.AIR)
		for dxy in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(0, 1)]:
			var q: Vector2i = p + dxy
			if q.y > start.y or seen.has(q):
				continue
			var qt := world.get_tile(q.x, q.y)
			if qt == TileDB.TRUNK or qt == TileDB.LEAVES:
				seen[q] = true
				stack.append(q)
	var out := [ItemDB.make("wood", wood)]
	if apples > 0:
		out.append(ItemDB.make("apple", apples))
	return out


## 周围的火把、蘑菇等失去支撑就一起掉下来
func _check_supports(t: Vector2i) -> void:
	for dxy in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		var q: Vector2i = t + dxy
		var id := world.get_tile(q.x, q.y)
		if id == TileDB.AIR or TileDB.prop(id, "support", "") == "":
			continue
		if not has_support(q, id):
			world.set_tile(q.x, q.y, TileDB.AIR)
			var drop := String(TileDB.prop(id, "drop", ""))
			if drop != "":
				give(ItemDB.make(drop, 1))


func has_support(t: Vector2i, tile_id: int) -> bool:
	var below_solid := world.is_solid(t.x, t.y + 1)
	match String(TileDB.prop(tile_id, "support", "")):
		"floor":
			return below_solid
		"any":
			return below_solid or world.is_solid(t.x - 1, t.y) or world.is_solid(t.x + 1, t.y) \
				or world.is_solid(t.x, t.y - 1) or world.get_wall(t.x, t.y) != TileDB.WALL_NONE
	# 普通方块：旁边要有东西（方块或背景墙），不能凭空悬浮
	for dxy in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if world.get_tile(t.x + dxy.x, t.y + dxy.y) != TileDB.AIR:
			return true
	return world.get_wall(t.x, t.y) != TileDB.WALL_NONE


func _add_tool_xp(item: Dictionary, amount: int) -> void:
	var before := ItemDB.mastery_level(item)
	item.xp = int(item.get("xp", 0)) + amount
	var after := ItemDB.mastery_level(item)
	if after > before:
		hud.notify("%s 的熟练度提升到 Lv%d！挖掘力 +%d%%" % [ItemDB.display_name(item), after, roundi(after * ItemDB.MASTERY_BONUS * 100)], ItemDB.RARITY_COLORS[4])


# ---------------------------------------------------------------- 放置、使用、投掷

func place_item(t: Vector2i, slot: int) -> bool:
	var item = inventory.slots[slot]
	if item == null:
		return false
	var d := ItemDB.get_def(item.id)
	if not d.has("place"):
		return false
	var tile_id := int(d.place)
	if not in_reach(t, item) or world.get_tile(t.x, t.y) != TileDB.AIR or not world.in_bounds(t.x, t.y):
		return false
	if TileDB.is_solid(tile_id) and player.overlaps_tile(t):
		return false
	if not has_support(t, tile_id):
		return false
	world.set_tile(t.x, t.y, tile_id)
	inventory.consume_slot(slot, 1)
	return true


func use_consumable(slot: int) -> bool:
	var item = inventory.slots[slot]
	if item == null:
		return false
	var d := ItemDB.get_def(item.id)
	var u: Dictionary = d.get("use", {})
	if u.has("heal"):
		if player.hp >= player.max_hp:
			hud.hint("生命值已经是满的。")
			return false
		if _heal_cooldown > 0.0:
			hud.hint("还要等 %d 秒才能再次回血。" % ceili(_heal_cooldown))
			return false
		player.hp = minf(player.max_hp, player.hp + float(u.heal))
		_heal_cooldown = 8.0
		hud.notify("恢复了 %d 点生命。" % int(u.heal), Color(0.5, 1, 0.55))
	elif u.has("buff"):
		buffs[u.buff] = {"effects": u.effects, "time": float(u.time)}
		hud.notify("获得「%s」效果！" % u.buff, Color(0.6, 0.85, 1))
	elif u.has("teleport"):
		player.teleport(spawn_position())
		hud.notify("一阵光芒闪过，你回到了出生点。", Color(0.8, 0.7, 1))
	elif u.has("maxhp"):
		if life_fruits >= MAX_LIFE_FRUITS:
			hud.hint("生命果已经吃到上限了。")
			return false
		life_fruits += 1
		recalc_stats()
		player.hp = minf(player.max_hp, player.hp + float(u.maxhp))
		hud.notify("最大生命提升到 %d！" % player.max_hp, Color(1, 0.5, 0.65))
	else:
		return false
	inventory.consume_slot(slot, 1)
	recalc_stats()
	return true


func throw_item(slot: int, target_px: Vector2) -> void:
	var item = inventory.slots[slot]
	if item == null:
		return
	var d := ItemDB.get_def(item.id)
	var th: Dictionary = d.get("throw", {})
	var b := Bomb.new()
	b.world = world
	b.radius = float(th.get("radius", 3.0))
	b.fuse = float(th.get("fuse", 2.0))
	b.big = b.radius > 4.0
	b.position = player.center() + Vector2(0, -6)
	b.velocity = (target_px - b.position).normalized() * 330.0 + Vector2(0, -60)
	b.z_index = 6
	b.exploded.connect(explode)
	add_child(b)
	inventory.consume_slot(slot, 1)


func explode(center: Vector2, radius: float) -> void:
	var ct := Vector2i(floori(center.x / TS), floori(center.y / TS))
	var r := int(ceil(radius))
	for y in range(ct.y - r, ct.y + r + 1):
		for x in range(ct.x - r, ct.x + r + 1):
			if Vector2(x - ct.x, y - ct.y).length() > radius:
				continue
			var id := world.get_tile(x, y)
			if id == TileDB.AIR or id == TileDB.RELIC_CHEST or TileDB.tier(id) >= TileDB.UNBREAKABLE_TIER:
				continue
			world.set_tile(x, y, TileDB.AIR)
	var blast := Blast.new()
	blast.position = center
	blast.radius_px = radius * TS
	blast.z_index = 20
	add_child(blast)
	var dist := player.center().distance_to(center)
	if dist < (radius + 1.0) * TS:
		damage(int(lerpf(40.0, 10.0, dist / ((radius + 1.0) * TS))), "爆炸")
		player.velocity += (player.center() - center).normalized() * 350.0


func give(inst: Dictionary) -> void:
	if int(inst.count) <= 0:
		return
	var left := inventory.add_instance(inst)
	var got := int(inst.count) - left
	if got > 0:
		hud.notify_item(inst, got)
	if left > 0:
		hud.hint("背包满了！%s ×%d 掉进了虚空。" % [ItemDB.display_name(inst), left])


# ---------------------------------------------------------------- 生命

func damage(amount: int, reason: String) -> void:
	if dead or amount <= 0:
		return
	player.hp -= amount
	player.hurt_flash = 0.25
	_regen_delay = 6.0
	hud.notify("%s：-%d" % [reason, amount], Color(1, 0.45, 0.4))
	if player.hp <= 0:
		dead = true
		player.hp = 0
		player.visible = false
		_respawn_timer = 3.0
		hud.notify("你倒下了……3 秒后在出生点复活。", Color(1, 0.3, 0.3))


func _respawn() -> void:
	dead = false
	player.visible = true
	player.hp = player.max_hp
	player.teleport(spawn_position())


# ---------------------------------------------------------------- 合成

func stations_nearby() -> Dictionary:
	var found := {"": true}
	var c := Vector2i(floori(player.center().x / TS), floori(player.center().y / TS))
	for y in range(c.y - STATION_RADIUS, c.y + STATION_RADIUS + 1):
		for x in range(c.x - STATION_RADIUS, c.x + STATION_RADIUS + 1):
			match world.get_tile(x, y):
				TileDB.WORKBENCH:
					found["workbench"] = true
				TileDB.FURNACE:
					found["furnace"] = true
				TileDB.ANVIL:
					found["anvil"] = true
	return found


func has_ingredients(r: Dictionary) -> bool:
	for id in r.ingredients:
		if inventory.count_of(id) < int(r.ingredients[id]):
			return false
	return true


func can_craft(r: Dictionary, stations: Dictionary) -> bool:
	return stations.has(r.station) and has_ingredients(r)


func craft(r: Dictionary) -> bool:
	if not can_craft(r, stations_nearby()):
		return false
	var result := ItemDB.make(r.result, int(r.count), rng)
	if not inventory.can_fit(result):
		hud.hint("背包放不下了。")
		return false
	for id in r.ingredients:
		inventory.remove(id, int(r.ingredients[id]))
	inventory.add_instance(result)
	var msg := "制作了 %s" % ItemDB.display_name(result)
	if int(r.count) > 1:
		msg += " ×%d" % int(r.count)
	hud.notify(msg, ItemDB.rarity_color(result))
	return true


## 在铁砧旁重铸当前选中工具的词缀
func reforge_selected() -> bool:
	var item = inventory.selected_item()
	if not ItemDB.is_tool_item(item):
		hud.hint("先在快捷栏选中一把工具。")
		return false
	if not stations_nearby().has("anvil"):
		hud.hint("需要站在铁砧旁边。")
		return false
	for id in ItemDB.REFORGE_COST:
		if inventory.count_of(id) < int(ItemDB.REFORGE_COST[id]):
			hud.hint("重铸需要 %d 个%s。" % [int(ItemDB.REFORGE_COST[id]), ItemDB.get_def(id).name])
			return false
	for id in ItemDB.REFORGE_COST:
		inventory.remove(id, int(ItemDB.REFORGE_COST[id]))
	item.affix = ItemDB.roll_affix(rng)
	hud.notify("重铸完成：%s" % ItemDB.display_name(item), ItemDB.rarity_color(item))
	return true
