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
	var spot := feet + Vector2i(2, 0)
	while main.world.get_tile(spot.x, spot.y) != TileDB.AIR and spot.y > 0:
		spot.y -= 1
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

	# 跑几帧游戏主循环，确认不报错
	for i in 30:
		await process_frame
	check(main.ready_done, "游戏主循环运行正常")
	main.queue_free()
	await process_frame


func _find_recipe(result: String) -> Dictionary:
	for r in ItemDB.recipes():
		if r.result == result:
			return r
	return {}
