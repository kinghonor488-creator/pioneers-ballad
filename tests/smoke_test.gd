extends SceneTree
## 自动冒烟测试（无界面运行）：
##   godot --headless --path . -s res://tests/smoke_test.gd
## 加上 -- --full 会额外测一次 4200×1200 完整世界的生成速度。
## 全部通过时退出码为 0，否则为 1。

var failures := 0
var checks := 0


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ✔ ", what)
	else:
		failures += 1
		printerr("  ✘ 失败: ", what)


func _initialize() -> void:
	# 看门狗：脚本出错导致协程中断时，不会一直卡住
	create_timer(240.0).timeout.connect(func():
		printerr("✘ 测试超时（可能有脚本错误中断了测试）")
		quit(2))
	_run()


func _run() -> void:
	print("== 数据表 ==")
	_test_data()
	print("== 世界生成 ==")
	_test_worldgen()
	if "--full" in OS.get_cmdline_user_args():
		print("== 完整世界 4200×1200 ==")
		var t0 := Time.get_ticks_msec()
		var big := WorldGen.generate(4200, 1200, 2024)
		var ms := Time.get_ticks_msec() - t0
		print("  生成用时 %d 毫秒" % ms)
		check(big.tiles.size() == 4200 * 1200, "完整世界尺寸正确")
		var big_path := "user://test_saves/big.sav"
		var hdr := {"name": "大世界", "width": big.width, "height": big.height, "spawn": big.spawn,
			"layers": big.layers, "surface": big.surface, "seed": big.seed_value, "player": {}}
		t0 = Time.get_ticks_msec()
		check(SaveSystem.save(big_path, hdr, big) == OK, "完整世界能保存")
		var save_ms := Time.get_ticks_msec() - t0
		t0 = Time.get_ticks_msec()
		var loaded := SaveSystem.load_full(big_path)
		var load_ms := Time.get_ticks_msec() - t0
		var kb := FileAccess.open(big_path, FileAccess.READ).get_length() / 1024.0
		print("  保存 %d 毫秒，读取 %d 毫秒，文件 %.0f KB" % [save_ms, load_ms, kb])
		check(not loaded.is_empty() and loaded.world.tiles == big.tiles, "完整世界原样读回")
		SaveSystem.delete_save(big_path)
	print("== 游戏场景 ==")
	await _test_game()
	print("\n%d 项检查，%d 项失败" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_data() -> void:
	var items := ItemDB.items()
	check(items.size() >= 50, "道具数量 >= 50（实际 %d）" % items.size())
	var bad := []
	for r in ItemDB.recipes():
		if not ItemDB.exists(r.result):
			bad.append(r.result)
		for id in r.ingredients:
			if not ItemDB.exists(id):
				bad.append(id)
	check(bad.is_empty(), "配方里的道具都存在 %s" % [bad])
	bad = []
	for t in range(1, TileDB.COUNT):
		var drop := String(TileDB.prop(t, "drop", ""))
		if drop != "" and not ItemDB.exists(drop):
			bad.append(drop)
	check(bad.is_empty(), "图块掉落物都存在 %s" % [bad])
	bad = []
	for id in items:
		if TileArt.icon(id) == null:
			bad.append(id)
	check(bad.is_empty(), "每个道具都能生成图标")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var affixed := 0
	for i in 200:
		if ItemDB.make("iron_pickaxe", 1, rng).affix != "":
			affixed += 1
	check(affixed > 80 and affixed < 190, "工具词缀会随机出现（200 把里 %d 把有词缀）" % affixed)
	var loot := ItemDB.roll_chest_loot(rng, 0.5)
	check(loot.size() >= 3, "宝匣至少掉 3 样东西（%d）" % loot.size())
	var pick := ItemDB.make("flint_pickaxe")
	var p0 := ItemDB.mining_power(pick, "earth")
	pick.xp = ItemDB.MASTERY_XP[3]
	check(ItemDB.mastery_level(pick) == 3 and ItemDB.mining_power(pick, "earth") > p0, "熟练度升级后挖得更快")
	bad = []
	for eid in EnemyDB.DEFS:
		for d in EnemyDB.get_def(eid).drops:
			if not ItemDB.exists(d[0]):
				bad.append(d[0])
	check(bad.is_empty(), "敌人掉落物都存在 %s" % [bad])
	var sw := ItemDB.make("iron_sword")
	var base_dmg := ItemDB.weapon_damage(sw)
	sw.affix = "锋利"
	check(ItemDB.weapon_damage(sw) > base_dmg and ItemDB.rarity(sw) == 2, "武器词缀提高伤害和稀有度")
	var wsw := 0
	for i in 100:
		var a := String(ItemDB.make("iron_sword", 1, rng).affix)
		if a != "" and ItemDB.WEAPON_AFFIXES.has(a):
			wsw += 1
	check(wsw > 30, "武器会随机到武器词缀（100 把里 %d 把）" % wsw)
	var night_c := EnemyDB.candidates("地表", true).map(func(e): return e[0])
	var day_c := EnemyDB.candidates("地表", false).map(func(e): return e[0])
	check("wisp" in night_c and not "wisp" in day_c and "mudling" in day_c, "游魂只在夜晚出现")


func _test_worldgen() -> void:
	var t0 := Time.get_ticks_msec()
	var w := WorldGen.generate(800, 400, 12345)
	print("  800×400 生成用时 %d 毫秒" % (Time.get_ticks_msec() - t0))
	var w2 := WorldGen.generate(800, 400, 12345)
	check(w.tiles == w2.tiles, "同一种子生成的世界完全一样")
	var c := w.count_tiles()
	var total := float(w.width * w.height)
	print("  图块分布: ", _fmt_counts(c))
	# 顶部 15% 应该基本是空气
	var sky_air := 0
	for y in int(w.height * 0.15):
		for x in w.width:
			if w.get_tile(x, y) == TileDB.AIR:
				sky_air += 1
	check(sky_air == int(w.height * 0.15) * w.width, "天空层全是空气")
	check(int(c.get(TileDB.STONE, 0)) / total > 0.25, "石头占比足够")
	check(int(c.get(TileDB.DIRT, 0)) > 0 and int(c.get(TileDB.GRASS, 0)) > 0, "有泥土和草地")
	check(int(c.get(TileDB.SAND, 0)) > 0, "有沙漠")
	for ore in [TileDB.COPPER_ORE, TileDB.IRON_ORE, TileDB.SULFUR, TileDB.MOONSILVER_ORE, TileDB.STARSTONE_ORE, TileDB.EMBER_ORE]:
		check(int(c.get(ore, 0)) > 0, "有 %s（%d 格）" % [TileDB.tile_name(ore), int(c.get(ore, 0))])
	check(int(c.get(TileDB.TRUNK, 0)) > 20, "有树")
	check(int(c.get(TileDB.RELIC_CHEST, 0)) >= 8, "有遗迹宝匣（%d 个）" % int(c.get(TileDB.RELIC_CHEST, 0)))
	check(int(c.get(TileDB.MUSHROOM, 0)) > 0 and int(c.get(TileDB.CRYSTAL, 0)) > 0, "有蘑菇和灵晶簇")
	check(int(c.get(TileDB.BASALT, 0)) > 0, "有深渊玄武岩")
	# 地下空气（洞穴）比例
	var under := 0
	var under_air := 0
	for y in range(w.layers.rock, w.layers.underworld):
		for x in w.width:
			under += 1
			if w.get_tile(x, y) == TileDB.AIR:
				under_air += 1
	var ratio := float(under_air) / under
	check(ratio > 0.05 and ratio < 0.5, "地下洞穴比例合理（%.1f%%）" % (ratio * 100.0))
	var bottom_ok := true
	for x in w.width:
		if w.get_tile(x, w.height - 1) != TileDB.BEDROCK:
			bottom_ok = false
	check(bottom_ok, "最底层是基岩")
	check(w.is_solid(w.spawn.x, w.spawn.y) and not w.is_solid(w.spawn.x, w.spawn.y - 1), "出生点脚下是实地、头上是空的")


func _fmt_counts(c: Dictionary) -> String:
	var parts := []
	for id in c:
		parts.append("%s:%d" % [TileDB.tile_name(id), c[id]])
	return ", ".join(parts)


func _test_game() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.world_width = 600
	main.world_height = 300
	main.world_seed = 777
	root.add_child(main)
	await main.world_ready
	check(main.world != null and main.player != null, "主场景能加载并生成世界")
	check(main.renderer.loaded_chunk_count() > 0, "渲染器加载了区块（%d 个）" % main.renderer.loaded_chunk_count())

	# 玩家从空中落下，应该站在地面上
	var p: Player = main.player
	p.teleport(p.position + Vector2(0, -160))
	for i in 240:
		p.step(1.0 / 60.0, 0.0, false, false)
	check(p.on_ground, "玩家落地了")
	check(not p.collides_at(p.position), "玩家没有卡进方块里")
	var x_before := p.position.x
	for i in 60:
		p.step(1.0 / 60.0, 1.0, false, false)
	check(p.position.x != x_before, "玩家能左右移动")
	var y_ground := p.position.y
	var min_y := y_ground
	p.step(1.0 / 60.0, 0.0, true, true)
	for i in 30:
		p.step(1.0 / 60.0, 0.0, false, true)
		min_y = minf(min_y, p.position.y)
	check(min_y < y_ground - 20.0, "玩家能跳起来（跳了 %.0f 像素）" % (y_ground - min_y))
	for i in 120:
		p.step(1.0 / 60.0, 0.0, false, false)

	# 挖脚下的方块，掉落进背包
	var inv: Inventory = main.inventory
	var feet := Vector2i(floori(p.center().x / 16.0), floori((p.position.y + Player.H + 1.0) / 16.0))
	var tile_id: int = main.world.get_tile(feet.x, feet.y)
	var drop := String(TileDB.prop(tile_id, "drop", ""))
	var before := inv.count_of(drop)
	check(main.break_tile(feet, inv.slots[0]), "能挖掉脚下的 %s" % TileDB.tile_name(tile_id))
	check(main.world.get_tile(feet.x, feet.y) == TileDB.AIR, "挖掉后变成空气")
	check(drop == "" or inv.count_of(drop) == before + 1, "掉落物进了背包（%s）" % drop)

	# 放回去
	inv.slots[5] = ItemDB.make("dirt", 3)
	main.inventory.selected = 5
	# 在玩家旁边找一个"空气、下面是实心方块、不和玩家重叠"的格子
	var spot := Vector2i(-1, -1)
	for dx in [2, -2, 3, -3, 4, -4]:
		for y in range(feet.y + 2, feet.y - 4, -1):
			var c := Vector2i(feet.x + dx, y)
			if main.world.get_tile(c.x, c.y) == TileDB.AIR and main.world.is_solid(c.x, c.y + 1) \
					and main.world.liquid_type(c.x, c.y) == 0 and not p.overlaps_tile(c):
				spot = c
				break
		if spot.x >= 0:
			break
	check(main.place_item(spot, 5), "能放置泥土")
	check(main.world.get_tile(spot.x, spot.y) == TileDB.DIRT and int(inv.slots[5].count) == 2, "放置后背包数量减少")
	check(not main.place_item(Vector2i(spot.x + 40, spot.y), 5), "太远的地方放不了")

	# 合成：木材 → 工作台 → 熔炉
	inv.add("wood", 20)
	inv.add("stone", 25)
	var r_bench := _find_recipe("workbench")
	check(main.craft(r_bench), "徒手合成工作台")
	check(inv.count_of("workbench") == 1 and inv.count_of("wood") == 10, "合成消耗了材料")
	check(not main.craft(_find_recipe("furnace")), "附近没有工作台时不能做熔炉")
	var bench_spot := Vector2i(floori(p.center().x / 16.0) + 1, floori((p.position.y + Player.H - 1.0) / 16.0))
	main.world.set_tile(bench_spot.x, bench_spot.y, TileDB.WORKBENCH)
	check(main.stations_nearby().has("workbench"), "能识别附近的工作台")
	check(main.craft(_find_recipe("furnace")), "站在工作台旁边可以做熔炉")

	# 工具：制作出来的工具带词缀字段；砍树
	inv.add("copper_bar", 8)
	check(main.craft(_find_recipe("copper_pickaxe")), "能做赤铜镐")
	var made: Variant = null
	for s in inv.slots:
		if s != null and s.id == "copper_pickaxe":
			made = s
	check(made != null and made.has("affix"), "工具实例带词缀字段（%s）" % ItemDB.display_name(made))

	# 药水增益、饰品
	inv.accessories[0] = ItemDB.make("gale_boots")
	main.recalc_stats()
	check(absf(p.move_mult - 1.25) < 0.001, "饰品疾风靴让移动速度 +25%")
	inv.slots[6] = ItemDB.make("miner_potion", 2)
	check(main.use_consumable(6) and main.buffs.has("采掘"), "喝采掘药水获得增益")
	main.recalc_stats()
	check(absf(float(main.stats.mine) - 0.35) < 0.001, "增益效果生效")

	# 炸弹
	var bc := Vector2(p.center().x + 16 * 12, p.center().y + 16 * 6)
	var bt := Vector2i(floori(bc.x / 16.0), floori(bc.y / 16.0))
	main.world.set_tile(bt.x, bt.y, TileDB.STONE)
	main.explode(bc, 2.0)
	check(main.world.get_tile(bt.x, bt.y) == TileDB.AIR, "炸弹能炸掉方块")

	_test_lighting(main)
	_test_liquids(main)
	await _test_combat(main)
	await _test_bosses(main)

	# 跑几帧游戏主循环，确认不报错
	for i in 30:
		await process_frame
	check(main.ready_done, "游戏主循环运行正常")

	await _test_save_load(main)


const GAME_VIEW := Vector2(640, 360)   ## 1280×720 窗口、2 倍缩放时看到的世界范围


func _test_lighting(main: Node2D) -> void:
	print("== 光照 ==")
	var L: Lighting = main.lighting
	var w: WorldData = main.world
	var p: Player = main.player
	var pt := Vector2i(p.center() / 16.0)
	main.time_of_day = 0.5
	main._update_ambient()
	L.compute_now(p.center(), GAME_VIEW)
	print("  光照计算用时 %.1f 毫秒（%d×%d 格）" % [L.last_ms, L.last_image.get_width(), L.last_image.get_height()])
	check(L.last_ms < 200.0, "光照计算足够快")
	var sky_cell := Vector2i(pt.x, w.sky_y[pt.x] - 6)
	check(L.light_at(sky_cell) > 0.9, "白天露天的地方是亮的（%.2f）" % L.light_at(sky_cell))
	var deep := Vector2i(pt.x, w.sky_y[pt.x] + 9)
	var all_solid := true
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			all_solid = all_solid and w.is_solid(deep.x + dx, deep.y + dy)
	if all_solid:
		check(L.light_at(deep) < 0.05, "厚土层里面是黑的（%.2f）" % L.light_at(deep))
	# 在地下挖一个小洞放火把
	var c := Vector2i(pt.x + 7, w.sky_y[pt.x + 7] + 11)
	var saved := {}
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var q := c + Vector2i(dx, dy)
			saved[q] = w.get_tile(q.x, q.y)
			var inside := absi(dx) <= 1 and absi(dy) <= 1
			w.set_tile(q.x, q.y, TileDB.AIR if inside else TileDB.STONE)
	w.set_tile(c.x, c.y + 1, TileDB.STONE)
	w.set_tile(c.x, c.y, TileDB.TORCH)
	L.compute_now(p.center(), GAME_VIEW)
	var at := L.light_at(c)
	var wall := L.light_at(c + Vector2i(3, 0))
	var far := L.light_at(c + Vector2i(9, 0))
	check(at > 0.8, "火把所在的格子很亮（%.2f）" % at)
	check(wall > 0.05 and wall < at, "火把照亮洞壁表面（%.2f）" % wall)
	check(far >= 0.0 and far < 0.05, "光照不透厚岩层（%.2f）" % far)
	var torch_px := L.last_image.get_pixelv(c - L.last_origin)
	check(torch_px.r > torch_px.b, "火把的光是暖色的")
	w.set_tile(c.x, c.y, TileDB.CRYSTAL)
	L.compute_now(p.center(), GAME_VIEW)
	var crystal_px := L.last_image.get_pixelv(c - L.last_origin)
	check(crystal_px.g > crystal_px.r, "灵晶簇的光是青色的")
	for q in saved:
		w.set_tile(q.x, q.y, saved[q])
	# 夜晚
	main.time_of_day = 0.0
	main._update_ambient()
	L.compute_now(p.center(), GAME_VIEW)
	var night_px := L.last_image.get_pixelv(sky_cell - L.last_origin)
	check(night_px.r < 0.45 and night_px.b > night_px.r, "夜晚露天变暗、偏蓝（%.2f, %.2f, %.2f）" % [night_px.r, night_px.g, night_px.b])
	# 天光高度随挖掘和建造更新
	var col := pt.x + 3
	var top := w.sky_y[col]
	var old_top := w.get_tile(col, top)
	w.set_tile(col, top, TileDB.AIR)
	check(w.sky_y[col] > top, "挖掉最上面的方块后，天光能照得更深")
	var old_above := w.get_tile(col, top - 6)
	w.set_tile(col, top - 6, TileDB.STONE)
	check(w.sky_y[col] == top - 6, "在空中放方块会挡住天光")
	w.set_tile(col, top - 6, old_above)
	w.set_tile(col, top, old_top)
	check(w.sky_y[col] == top, "恢复后天光高度也恢复")
	# 玩家身上的光
	main.time_of_day = 0.5
	main._update_ambient()


## 在地下挖一个封闭的石头盒子（内部 iw×ih 是空的），返回内部左上角
func _make_box(w: WorldData, x0: int, y0: int, iw: int, ih: int) -> Vector2i:
	for y in range(y0 - 1, y0 + ih + 1):
		for x in range(x0 - 1, x0 + iw + 1):
			var inside := x >= x0 and x < x0 + iw and y >= y0 and y < y0 + ih
			w.set_tile(x, y, TileDB.AIR if inside else TileDB.STONE)
			w.set_liquid(x, y, 0, 0)
	return Vector2i(x0, y0)


func _run_liquids(sim: LiquidSim, max_steps: int) -> int:
	var n := 0
	while not sim.active.is_empty() and n < max_steps:
		sim.step()
		n += 1
	return n


func _test_liquids(main: Node2D) -> void:
	print("== 液体 ==")
	var w: WorldData = main.world
	var sim: LiquidSim = main.liquids
	var p: Player = main.player
	var inv: Inventory = main.inventory
	# 生成
	var water := 0
	var lava := 0
	var lava_high := 0
	var floating := 0
	for i in w.liquid.size():
		var v := w.liquid[i]
		if v == 0:
			continue
		if (v >> 4) == WorldData.LIQ_WATER:
			water += 1
		else:
			lava += 1
			if i / w.width < int(w.layers.cavern):
				lava_high += 1
		var below := i + w.width
		if below < w.liquid.size() and w.tiles[below] == TileDB.AIR and w.liquid[below] == 0:
			floating += 1
	check(water > 0 and lava > 0, "世界里有水（%d 格）和熔岩（%d 格）" % [water, lava])
	check(lava_high == 0, "熔岩只出现在洞穴层以下")
	check(floating == 0, "生成的液体都有东西托着，不会悬空")
	check(sim.active.is_empty(), "生成好的液体是静止的（不占用模拟时间）")

	# 流动：往盒子左上角倒 2 桶水
	sim.active = {}
	var box := _make_box(w, w.spawn.x + 40, int(w.layers.rock) + 10, 12, 6)
	w.set_liquid(box.x, box.y, WorldData.LIQ_WATER, 8)
	w.set_liquid(box.x + 1, box.y, WorldData.LIQ_WATER, 8)
	sim.activate_around(box.x, box.y)
	var steps := _run_liquids(sim, 600)
	var total := sim.total_amount(box.x, box.y, box.x + 11, box.y + 5)
	check(total == 16, "流动时液体总量不变（%d）" % total)
	var bottom_ok := true
	for x in range(box.x, box.x + 12):
		bottom_ok = bottom_ok and w.liquid_amount(x, box.y + 5) >= 1
	check(bottom_ok, "水流下去铺满了盒子底部")
	check(w.liquid_amount(box.x, box.y) == 0, "上面不再悬着水")
	check(sim.active.is_empty(), "流完之后静止下来（%d 步）" % steps)

	# 水 + 熔岩 → 黑曜石
	var box2 := _make_box(w, w.spawn.x + 60, int(w.layers.rock) + 10, 6, 3)
	w.set_liquid(box2.x, box2.y + 2, WorldData.LIQ_WATER, 8)
	w.set_liquid(box2.x + 5, box2.y + 2, WorldData.LIQ_LAVA, 8)
	sim.activate_around(box2.x, box2.y + 2)
	sim.activate_around(box2.x + 5, box2.y + 2)
	_run_liquids(sim, 600)
	var obs := 0
	for y in range(box2.y, box2.y + 3):
		for x in range(box2.x, box2.x + 6):
			if w.get_tile(x, y) == TileDB.OBSIDIAN:
				obs += 1
	check(obs > 0, "水碰到熔岩会凝固成黑曜石（%d 块）" % obs)

	# 桶、游泳、憋气、熔岩伤害：把玩家放进一个大水池
	var pool := _make_box(w, w.spawn.x + 80, int(w.layers.rock) + 10, 8, 8)
	for y in range(pool.y, pool.y + 8):
		for x in range(pool.x, pool.x + 8):
			w.set_liquid(x, y, WorldData.LIQ_WATER, 8)
	sim.active = {}
	p.teleport(Vector2(pool.x * 16 + 40, pool.y * 16 + 40))
	var cell := pool + Vector2i(1, 4)
	inv.slots[9] = ItemDB.make("empty_bucket", 2)
	check(main.use_bucket(cell, 9) and inv.count_of("water_bucket") == 1, "空桶能装水")
	inv.slots[9] = ItemDB.make("lava_bucket", 1)
	var air_spot := Vector2i(cell.x, cell.y)
	check(not main.use_bucket(air_spot, 9) or w.liquid_type(air_spot.x, air_spot.y) != WorldData.LIQ_WATER, "不能把熔岩倒进水里")
	inv.slots[9] = null
	_run_liquids(sim, 300)
	# 游泳
	p.velocity = Vector2.ZERO
	for i in 30:
		p.step(1.0 / 60.0, 0.0, false, false)
	check(p.in_liquid == WorldData.LIQ_WATER and p.velocity.y <= 140.0, "在水里下沉得很慢（%.0f）" % p.velocity.y)
	var y_before := p.position.y
	for i in 30:
		p.step(1.0 / 60.0, 0.0, false, true)
	check(p.position.y < y_before, "按住跳跃键能往上游")
	# 憋气
	p.teleport(Vector2(pool.x * 16 + 40, pool.y * 16 + 60))
	p.step(1.0 / 60.0, 0.0, false, false)
	main.breath = main.max_breath()
	p.hp = 100.0
	for i in 14:
		main._liquid_effects(1.0)
	check(main.breath == 0.0 and p.hp < 100.0, "憋气用完后会溺水（剩 %.0f 生命）" % p.hp)
	main.buffs["水息"] = {"effects": {"breath": 99.0}, "time": 300.0}
	main.recalc_stats()
	main.breath = main.max_breath()
	p.hp = 100.0
	for i in 14:
		main._liquid_effects(1.0)
	check(p.hp == 100.0, "喝了水息药水可以在水下呼吸")
	main.buffs.erase("水息")
	main.recalc_stats()
	# 熔岩
	for y in range(pool.y, pool.y + 8):
		for x in range(pool.x, pool.x + 8):
			w.set_liquid(x, y, WorldData.LIQ_LAVA, 8)
	p.step(1.0 / 60.0, 0.0, false, false)
	p.invuln = 0.0
	p.hp = 100.0
	main._liquid_effects(0.1)
	check(p.in_liquid == WorldData.LIQ_LAVA and is_equal_approx(p.hp, 100.0 - main.LAVA_DAMAGE), "熔岩会烫伤（-%d）" % main.LAVA_DAMAGE)
	inv.accessories[2] = ItemDB.make("magma_charm")
	main.recalc_stats()
	p.invuln = 0.0
	p.hp = 100.0
	main._liquid_effects(0.1)
	check(is_equal_approx(p.hp, 91.0), "熔火护符减少 70%% 熔岩伤害（剩 %.0f）" % p.hp)
	inv.accessories[2] = null
	main.recalc_stats()
	# 熔岩发光
	main.lighting.compute_now(p.center(), GAME_VIEW)
	var lava_px: Color = main.lighting.last_image.get_pixelv(pool + Vector2i(4, 7) - main.lighting.last_origin)
	check(lava_px.r > 0.4 and lava_px.r > lava_px.b, "熔岩会发出橙色的光")
	# 性能：1500 个活跃格子
	for y in range(pool.y, pool.y + 8):
		for x in range(pool.x, pool.x + 8):
			w.set_liquid(x, y, 0, 0)
	var big := _make_box(w, w.spawn.x - 120, int(w.layers.rock) + 5, 60, 30)
	for y in range(big.y, big.y + 25):
		for x in range(big.x, big.x + 60):
			w.set_liquid(x, y, WorldData.LIQ_WATER, 8 if (x + y) % 3 != 0 else 3)
			sim.activate(x, y)
	var t0 := Time.get_ticks_usec()
	sim.step()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  液体模拟一步：处理 %d 格，用时 %.1f 毫秒" % [sim.last_processed, ms])
	check(ms < 40.0, "液体模拟足够快")
	_run_liquids(sim, 2000)
	check(sim.active.is_empty(), "大水池最终也会静止下来")
	w.liquid_dirty = []
	main.renderer.flush_liquids()
	p.teleport(main.spawn_position())
	for i in 30:
		p.step(1.0 / 60.0, 0.0, false, false)
	p.invuln = 0.0
	p.hp = p.max_hp


func _test_combat(main: Node2D) -> void:
	print("== 战斗 ==")
	var cb: Combat = main.combat
	var p: Player = main.player
	var inv: Inventory = main.inventory
	cb.spawning_enabled = false
	cb.clear()
	var sword := ItemDB.make("iron_sword")
	var e := cb.spawn("mudling", p.position + Vector2(40, p.body_size.y - 10))
	var hp0 := e.hp
	var dealt := cb.deal_damage(e, sword, 0.0, Vector2.RIGHT)
	check(dealt > 0 and is_equal_approx(e.hp, hp0 - dealt), "武器能对敌人造成伤害（%d）" % dealt)
	check(int(sword.xp) == 1, "命中会增加武器熟练度")
	var cores := inv.count_of("mud_core")
	for i in 20:
		if not is_instance_valid(e) or e.hp <= 0.0:
			break
		cb.deal_damage(e, sword, 0.0, Vector2.RIGHT)
	check(e.hp <= 0.0, "能打死敌人")
	check(inv.count_of("mud_core") > cores, "击败泥团怪掉落泥核")
	check(int(main.kills.get("mudling", 0)) == 1, "击杀计数 +1")

	# 防御和无敌时间
	inv.accessories[1] = ItemDB.make("chitin_charm")
	main.recalc_stats()
	p.invuln = 0.0
	p.hp = 100.0
	main.damage(20, "测试", p.center() + Vector2(10, 0))
	check(is_equal_approx(p.hp, 82.0), "防御 4 减少 2 点伤害（剩 %.0f）" % p.hp)
	main.damage(20, "测试", p.center() + Vector2(10, 0))
	check(is_equal_approx(p.hp, 82.0), "受伤后有短暂无敌时间")
	p.invuln = 0.0
	p.velocity = Vector2.ZERO

	# 挥剑
	var beetle := cb.spawn("rock_beetle", p.position + Vector2(14, 2))
	cb._cooldown = 0.0
	check(cb.use_weapon(sword, p.center() + Vector2(100, 0)), "能挥剑")
	check(not cb.use_weapon(sword, p.center() + Vector2(100, 0)), "攻击有冷却时间")
	cb._update_swing(0.02)
	check(beetle.hp < beetle.max_hp, "挥剑砍中身前的岩甲虫")
	p.invuln = 5.0

	# 弓和箭
	var bow := ItemDB.make("wooden_bow")
	for i in inv.slots.size():
		if inv.slots[i] != null and ItemDB.category(inv.slots[i].id) == "ammo":
			inv.slots[i] = null
	cb._cooldown = 0.0
	check(not cb.use_weapon(bow, p.center() + Vector2(100, 0)), "没有箭矢时弓射不出去")
	inv.add("arrow", 10)
	var shots := cb.projectiles.size()
	check(cb.use_weapon(bow, p.center() + Vector2(100, -20)) and inv.count_of("arrow") == 9, "射箭消耗 1 支箭")
	check(cb.projectiles.size() == shots + 1, "射出了箭矢")

	# 法杖
	var staff := ItemDB.make("wisp_staff")
	p.mana = 40.0
	cb._cooldown = 0.0
	check(cb.use_weapon(staff, p.center() + Vector2(100, 0)) and is_equal_approx(p.mana, 35.0), "法杖消耗法力")
	p.mana = 2.0
	cb._cooldown = 0.0
	check(not cb.use_weapon(staff, p.center() + Vector2(100, 0)), "法力不足时不能施法")

	# 弹幕：箭命中敌人、火球命中玩家
	cb.clear()
	var target := cb.spawn("mudling", p.center() + Vector2(60, -20))
	var arrow_hp := target.hp
	cb._cooldown = 0.0
	cb.use_weapon(bow, target.center())
	for i in 30:
		cb.physics_tick(1.0 / 60.0)
		if not is_instance_valid(target) or target.hp < arrow_hp:
			break
	check(not is_instance_valid(target) or target.hp < arrow_hp, "箭矢命中敌人")
	cb.clear()
	p.invuln = 0.0
	var hp_before := p.hp
	cb.spawn_hostile_shot(p.center() + Vector2(0, -40), Vector2(0, 300), 10)
	for i in 20:
		cb.physics_tick(1.0 / 60.0)
	check(p.hp < hp_before, "敌人的火球会伤到玩家")

	# 刷怪
	cb.clear()
	var spawned := 0
	for i in 10:
		if cb.try_spawn() != null:
			spawned += 1
	check(spawned > 0, "能在玩家附近刷出敌人（%d 只）" % spawned)
	var far_ok := true
	for en in cb.enemies:
		if en.center().distance_to(p.center()) < Combat.SPAWN_MIN_DIST * 16.0 - 40.0:
			far_ok = false
	check(far_ok, "敌人刷在屏幕外")
	for i in 120:
		cb.physics_tick(1.0 / 60.0)
	check(true, "敌人 AI 运行 2 秒没有报错")
	cb.clear()
	check(cb.enemies.is_empty(), "清除所有敌人")
	inv.accessories[1] = null
	main.recalc_stats()
	p.invuln = 0.0
	p.hp = p.max_hp
	cb.spawning_enabled = true


func _test_bosses(main: Node2D) -> void:
	print("== Boss ==")
	var cb: Combat = main.combat
	var p: Player = main.player
	var inv: Inventory = main.inventory
	var dt := 1.0 / 60.0
	cb.spawning_enabled = false
	cb.clear()
	var natural := false
	for layer in ["地表", "地下", "洞穴层", "深渊"]:
		for c in EnemyDB.candidates(layer, true) + EnemyDB.candidates(layer, false):
			if EnemyDB.is_boss(c[0]):
				natural = true
	check(not natural, "Boss 不会自然刷出")
	check(ItemDB.recipes().any(func(r): return r.result == "starstone_pickaxe" and r.ingredients.has("warden_prism")), "星辉镐需要守望者棱晶（Boss 推进进度）")

	# —— 泥沼巨像 ——
	p.teleport(main.spawn_position())
	for i in 30:
		p.step(dt, 0.0, false, false)
	inv.slots[9] = ItemDB.make("crystal_beacon", 1)
	check(not main.use_consumable(9) and inv.slots[9] != null, "灵晶信标在地表用不了，也不会被消耗")
	inv.slots[9] = ItemDB.make("mud_offering", 2)
	check(main.use_consumable(9) and cb.boss != null and cb.boss.id == "mud_colossus", "在地表用泥沼祭品召唤出泥沼巨像")
	check(inv.slots[9] != null and int(inv.slots[9].count) == 1, "召唤消耗 1 个祭品")
	check(not main.use_consumable(9), "Boss 在场时不能重复召唤")
	var b: Boss = cb.boss
	check(b.center().distance_to(p.center()) > 12.0 * 16.0, "Boss 出现在离玩家一段距离的地方")
	p.invuln = 9999.0
	var saw_wave := false
	for i in 600:
		cb.physics_tick(dt)
		for pr in cb.projectiles:
			if is_instance_valid(pr) and pr.kind == "wave":
				saw_wave = true
	check(is_instance_valid(b) and b.hp > 0.0, "巨像 AI 运行 10 秒没有出错")
	check(saw_wave, "巨像落地会掀起泥浪")
	b.hp = b.max_hp * 0.45
	cb.physics_tick(dt)
	check(b.phase == 2, "血量低于一半进入二阶段")
	var hearts := inv.count_of("mud_heart")
	var sword := ItemDB.make("starstone_sword")
	for i in 500:
		if not is_instance_valid(b) or b.hp <= 0.0:
			break
		cb.deal_damage(b, sword, 0.0, Vector2.RIGHT)
	check(b.hp <= 0.0 and cb.boss == null, "能打败泥沼巨像")
	check(inv.count_of("mud_heart") == hearts + 1 and inv.count_of("colossus_shard") >= 6, "掉落泥王之心和巨像碎片")
	check(inv.count_of("mud_hammer") + inv.count_of("sludge_staff") >= 1, "随机掉落一把 Boss 专属武器")
	check(int(main.bosses.get("mud_colossus", 0)) == 1, "记录了击败泥沼巨像")
	cb.clear()

	# —— 灵晶守望者（要到洞穴层）——
	var w: WorldData = main.world
	var spot := Vector2i(-1, -1)
	for dx in range(0, w.width / 2):
		for sx in [1, -1]:
			var x: int = w.spawn.x + dx * sx
			for y in range(int(w.layers.cavern) + 4, int(w.layers.underworld) - 4):
				if not w.is_solid(x, y) and not w.is_solid(x, y - 1) and w.is_solid(x, y + 1):
					spot = Vector2i(x, y)
					break
			if spot.x >= 0:
				break
		if spot.x >= 0:
			break
	check(spot.x >= 0, "测试世界里找到洞穴层的落脚点")
	p.teleport(Vector2(spot.x * 16 + 2, (spot.y + 1) * 16 - Player.H - 0.01))
	inv.slots[9] = ItemDB.make("crystal_beacon", 2)
	check(main.use_consumable(9) and cb.boss != null and cb.boss.id == "crystal_warden", "在洞穴层用灵晶信标召唤出灵晶守望者")
	var wd: Boss = cb.boss
	var saw_shard := false
	var saw_dash := false
	for i in 600:
		cb.physics_tick(dt)
		saw_dash = saw_dash or wd.state == "dash"
		for pr in cb.projectiles:
			if is_instance_valid(pr) and pr.kind == "shard":
				saw_shard = true
	check(is_instance_valid(wd) and wd.hp > 0.0, "守望者 AI 运行 10 秒没有出错")
	check(saw_shard, "守望者会放环形晶刺（在岩石里也能放出来）")
	check(saw_dash, "守望者会蓄力冲刺")
	wd.hp = wd.max_hp * 0.4
	for i in 300:
		cb.physics_tick(dt)
	check(wd.phase == 2, "守望者进入二阶段")
	var prisms := inv.count_of("warden_prism")
	for i in 800:
		if not is_instance_valid(wd) or wd.hp <= 0.0:
			break
		cb.deal_damage(wd, sword, 0.0, Vector2.RIGHT)
	check(wd.hp <= 0.0 and inv.count_of("warden_prism") >= prisms + 3 and inv.count_of("warden_eye") >= 1, "打败守望者，掉落棱晶和守望之眼")

	# 玩家死了 Boss 会离开
	check(main.use_consumable(9) and cb.boss != null, "可以再次召唤")
	main.damage(99999, "测试")
	check(main.dead and cb.boss == null, "玩家倒下后 Boss 离开")
	main._respawn()
	cb.clear()
	p.invuln = 0.0
	p.hp = p.max_hp
	cb.spawning_enabled = true


func _test_save_load(main: Node2D) -> void:
	print("== 存档 / 读档 ==")
	var path := "user://test_saves/smoke.sav"
	SaveSystem.delete_save(path)
	main.world_name = "测试世界"
	main.save_path = path
	main.day = 3
	main.life_fruits = 2
	main.inventory.slots[7] = ItemDB.make("ancient_pickaxe", 1)
	main.inventory.slots[7].affix = "星选"
	main.inventory.slots[7].xp = 321
	check(main.save_game(false), "能保存游戏")
	var hdr := SaveSystem.read_header(path)
	check(String(hdr.get("name", "")) == "测试世界" and int(hdr.get("width", 0)) == 600, "能读取存档头信息")
	var data := SaveSystem.load_full(path)
	check(not data.is_empty() and data.world.tiles == main.world.tiles and data.world.walls == main.world.walls, "图块和墙壁原样读回")
	check(not data.is_empty() and data.world.liquid == main.world.liquid and main.world.liquid.count(0) < main.world.liquid.size(), "液体原样读回")
	var size := FileAccess.open(path, FileAccess.READ).get_length()
	print("  存档大小 %.1f KB（世界 600×300）" % (size / 1024.0))
	# 记下保存时的状态，然后用一个全新的主场景把它读回来
	var tiles_before: PackedByteArray = main.world.tiles.duplicate()
	var slots_before: Array = main.inventory.slots.duplicate(true)
	var acc_before: Array = main.inventory.accessories.duplicate(true)
	var pos_before: Vector2 = main.player.position
	main.save_path = ""
	main.queue_free()
	await process_frame

	GameSession.reset()
	GameSession.save_path = path
	GameSession.load_existing = true
	var main2: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main2)
	await main2.world_ready
	check(main2.world.tiles == tiles_before, "重新进入后世界和保存时一样")
	check(main2.world_name == "测试世界" and main2.day == 3 and main2.life_fruits == 2, "世界名、天数、生命果恢复")
	check(main2.inventory.slots == slots_before, "背包原样恢复")
	check(main2.inventory.accessories == acc_before, "饰品栏原样恢复")
	var pick: Dictionary = main2.inventory.slots[7]
	check(pick.affix == "星选" and int(pick.xp) == 321, "工具的词缀和熟练度恢复（%s）" % ItemDB.display_name(pick))
	check(main2.buffs.has("采掘"), "药水增益恢复")
	check(int(main2.bosses.get("mud_colossus", 0)) == 1 and int(main2.kills.get("mudling", 0)) >= 1, "Boss 击败记录和击杀数恢复")
	check(main2.player.position.distance_to(pos_before) < 0.5, "玩家位置恢复")
	check(main2.player.max_hp == 100 + 2 * 20, "生命上限按生命果重新计算（%d）" % main2.player.max_hp)
	main2.save_path = ""
	main2.queue_free()
	await process_frame
	get_auto_accept_quit_reset()

	# 损坏的存档不能把游戏弄崩
	var bad := "user://test_saves/broken.sav"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("这不是存档")
	f.close()
	check(SaveSystem.read_header(bad).is_empty() and SaveSystem.load_full(bad).is_empty(), "损坏的存档会被识别出来")
	var trunc := "user://test_saves/truncated.sav"
	var whole := FileAccess.get_file_as_bytes(path)
	f = FileAccess.open(trunc, FileAccess.WRITE)
	f.store_buffer(whole.slice(0, whole.size() / 2))
	f.close()
	check(SaveSystem.load_full(trunc).is_empty(), "只写了一半的存档会被识别出来")
	SaveSystem.delete_save(bad)
	SaveSystem.delete_save(trunc)
	SaveSystem.delete_save(path)
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"), "能删除存档")
	GameSession.reset()

	# 标题界面能加载
	var title: Control = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	check(title.list_box != null, "标题界面能加载")
	check(title.seed_from_text("") == 0 and title.seed_from_text("123") == 123 and title.seed_from_text("hello") > 0, "种子文字转换正确")
	title.queue_free()
	await process_frame

	# 完整流程：标题界面 → 创建新世界 → 进入游戏 → 存档回到标题 → 列表里能看到
	var t2: Control = load("res://scenes/title.tscn").instantiate()
	root.add_child(t2)
	current_scene = t2
	await process_frame
	t2.name_edit.text = "冒烟测试世界"
	t2.size_option.select(0)
	t2._create_world()
	var m3: Node = null
	for i in 600:
		await process_frame
		var cs := current_scene
		if cs != null and cs.has_signal("world_ready") and cs.get("ready_done"):
			m3 = cs
			break
	check(m3 != null, "从标题界面创建新世界并进入游戏")
	if m3 == null:
		return
	var sp: String = m3.save_path
	check(sp != "" and FileAccess.file_exists(sp), "新世界创建后立即存档")
	check(m3.world.width == 1600 and m3.world_name == "冒烟测试世界", "按标题界面选的大小和名字生成")
	m3.return_to_title()
	for i in 5:
		await process_frame
	check(current_scene != null and current_scene.has_method("refresh_list"), "存档后回到标题界面")
	var found := false
	for e in SaveSystem.list_saves():
		if e.path == sp and String(e.header.get("name", "")) == "冒烟测试世界":
			found = true
	check(found, "标题界面的世界列表里有刚才的世界")
	SaveSystem.delete_save(sp)
	current_scene.queue_free()
	await process_frame
	GameSession.reset()


func get_auto_accept_quit_reset() -> void:
	set_auto_accept_quit(true)


func _find_recipe(result: String) -> Dictionary:
	for r in ItemDB.recipes():
		if r.result == result:
			return r
	return {}
