extends SceneTree
## 开发用截图工具（需要有窗口，不能 --headless）：
##   godot --path . -s res://tools/screenshot.gd -- <输出目录>
## 会截三张图：地表白天、打开背包和制作栏、地下洞穴。

var out_dir := "user://screenshots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("截图已保存: ", path)


func _run() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.world_seed = 2024
	root.add_child(main)
	await main.world_ready
	for i in 90:
		await process_frame
	await _shot("1_surface")

	var inv: Inventory = main.inventory
	for id in ["iron_pickaxe", "gale_boots", "heal_potion", "bomb", "wanderer_core", "crystal_shard", "copper_bar", "wood", "stone"]:
		inv.add_instance(ItemDB.make(id, 1 if ItemDB.max_stack(id) == 1 else 12, main.rng))
	inv.accessories[0] = ItemDB.make("feather_charm")
	main.hud.inventory_open = true
	main.hud._stations = main.stations_nearby()
	Input.warp_mouse(Vector2(150, 35))
	for i in 10:
		await process_frame
	await _shot("2_inventory")
	main.hud.inventory_open = false

	# 传送到地下一个洞穴里
	var w: WorldData = main.world
	var target := Vector2i(w.spawn.x, w.layers.cavern + 20)
	for dx in range(0, 400):
		var x := w.spawn.x + dx
		var found := false
		for y in range(w.layers.cavern, w.layers.underworld):
			if not w.is_solid(x, y) and not w.is_solid(x, y - 1) and w.is_solid(x, y + 1):
				target = Vector2i(x, y)
				found = true
				break
		if found:
			break
	main.player.teleport(Vector2(target.x * 16, (target.y + 1) * 16 - Player.H - 0.01))
	main.world.set_tile(target.x + 1, target.y, TileDB.TORCH)
	for i in 120:
		await process_frame
	await _shot("3_cave")
	quit(0)
