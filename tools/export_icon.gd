extends SceneTree
## 把 icon.svg 渲染成 1024×1024 的 PNG（像素风，最近邻放大），给启动器 .app 做图标用：
##   godot --headless --path . -s res://tools/export_icon.gd -- <输出路径.png>


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var img := Image.new()
	img.load_svg_from_buffer(FileAccess.get_file_as_bytes("res://icon.svg"), 1.0)
	img.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	print("图标已导出: ", out)
	quit()
