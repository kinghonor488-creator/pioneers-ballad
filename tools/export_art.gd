extends SceneTree
## 把程序生成的像素美术导出成 PNG，方便查看或以后交给美术重画：
##   godot --headless --path . -s res://tools/export_art.gd
## 输出到 assets/generated/：tiles.png（图块图集）、walls.png（墙壁图集）、items.png（所有道具图标）
## 游戏运行时并不读取这些文件，而是每次启动时现场生成同样的图。


func _initialize() -> void:
	var dir := "res://assets/generated"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_save(TileArt.build_tile_atlas(), dir + "/tiles.png")
	_save(TileArt.build_wall_atlas(), dir + "/walls.png")
	var ids := ItemDB.items().keys()
	var cols := 10
	var sheet := Image.create_empty(cols * 16, ceili(float(ids.size()) / cols) * 16, false, Image.FORMAT_RGBA8)
	for i in ids.size():
		var icon := TileArt.icon(ids[i]).get_image()
		icon.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(icon, Rect2i(0, 0, 16, 16), Vector2i((i % cols) * 16, (i / cols) * 16))
	_save(sheet, dir + "/items.png")
	quit(0)


func _save(img: Image, path: String) -> void:
	var big := img.duplicate() as Image
	big.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png(ProjectSettings.globalize_path(path))
	print("已导出 ", path, "（放大 4 倍）")
