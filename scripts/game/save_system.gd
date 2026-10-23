class_name SaveSystem
extends RefCounted
## 存档读写。每个世界一个 .sav 文件，放在 user://saves/
## （macOS 上是 ~/Library/Application Support/PioneersBallad/saves/，文件夹名在 project.godot 里固定，不随游戏名变化）。
##
## 文件格式：
##   "STSV"（4 字节标记） + 版本号（4 字节）
##   三个数据块，每块前面都有 4 字节长度（文件被截断时能直接发现）：
##     头信息字典（世界名字、种子、尺寸、时间、玩家、背包……）—— 列出存档时只读这一块，很快
##     图块数组（zstd 压缩）
##     背景墙数组（zstd 压缩）
##     液体数组（zstd 压缩，版本 2 起才有；读旧存档时当作没有液体）
##
## 写入时先写到 .tmp，写完再改名覆盖；旧存档保留为 .bak，写到一半断电也不会丢档。

const SAVE_DIR := "user://saves"
const EXT := ".sav"
const MAGIC := "STSV"
const VERSION := 2
## 以前用临时名"星壤纪元"时的存档位置（相对于系统的应用数据目录），启动时会把那里的存档复制过来
const LEGACY_DIRS := ["Godot/app_userdata/星壤纪元 Starsoil/saves"]


static func new_save_path() -> String:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var stamp := int(Time.get_unix_time_from_system())
	var path := ""
	while path == "" or FileAccess.file_exists(path):
		path = SAVE_DIR.path_join("world_%d_%04d%s" % [stamp, randi() % 10000, EXT])
	return path


static func save(path: String, header: Dictionary, world: WorldData) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_32(VERSION)
	_store_block(f, var_to_bytes(header))
	_store_block(f, world.tiles.compress(FileAccess.COMPRESSION_ZSTD))
	_store_block(f, world.walls.compress(FileAccess.COMPRESSION_ZSTD))
	_store_block(f, world.liquid.compress(FileAccess.COMPRESSION_ZSTD))
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return err
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(tmp, path)


## 只读头信息。文件不存在、损坏或版本太新时返回空字典。
static func read_header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	return _read_header(f)


static func _read_header(f: FileAccess) -> Dictionary:
	if f.get_length() < 8 or f.get_buffer(4).get_string_from_ascii() != MAGIC:
		return {}
	var ver := f.get_32()
	if ver > VERSION:
		return {}
	var block := _read_block(f)
	if block.is_empty():
		return {}
	var h: Variant = bytes_to_var(block)
	if typeof(h) != TYPE_DICTIONARY or not h.has("width") or not h.has("player"):
		return {}
	h["_version"] = ver
	return h


## 读取完整存档，成功返回 {"header": 字典, "world": WorldData}，失败返回空字典
static func load_full(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var h := _read_header(f)
	if h.is_empty():
		return {}
	var version := int(h.get("_version", 1))
	var tiles_c := _read_block(f)
	var walls_c := _read_block(f)
	if tiles_c.is_empty() or walls_c.is_empty():
		return {}
	var w := WorldData.new()
	w.width = int(h.width)
	w.height = int(h.height)
	var n := w.width * w.height
	w.tiles = tiles_c.decompress(n, FileAccess.COMPRESSION_ZSTD)
	w.walls = walls_c.decompress(n, FileAccess.COMPRESSION_ZSTD)
	if n <= 0 or w.tiles.size() != n or w.walls.size() != n:
		return {}
	if version >= 2:
		var liq_c := _read_block(f)
		if liq_c.is_empty():
			return {}
		w.liquid = liq_c.decompress(n, FileAccess.COMPRESSION_ZSTD)
		if w.liquid.size() != n:
			return {}
	else:
		w.liquid.resize(n)
		w.liquid.fill(0)
	w.seed_value = int(h.get("seed", 0))
	w.spawn = h.get("spawn", Vector2i(w.width / 2, 0))
	w.layers = h.get("layers", {})
	w.surface = h.get("surface", PackedInt32Array())
	if w.surface.size() != w.width:
		return {}
	w.biome_cols = h.get("biomes", PackedByteArray())
	if w.biome_cols.size() != w.width:   # 旧存档没有生物群系信息：全当森林
		w.biome_cols.resize(w.width)
		w.biome_cols.fill(WorldData.B_FOREST)
	w.rebuild_sky()
	return {"header": h, "world": w}


static func _store_block(f: FileAccess, data: PackedByteArray) -> void:
	f.store_32(data.size())
	f.store_buffer(data)


## 读一个带长度的数据块；剩下的字节不够（文件被截断）就返回空数组
static func _read_block(f: FileAccess) -> PackedByteArray:
	if f.get_length() - f.get_position() < 4:
		return PackedByteArray()
	var n := f.get_32()
	if n == 0 or f.get_length() - f.get_position() < n:
		return PackedByteArray()
	return f.get_buffer(n)


## 所有存档，最近保存的排在前面。损坏的存档 header 为空字典。
## 把旧位置的存档复制到现在的存档文件夹（同名的不覆盖，旧文件原样保留）。返回复制了几个世界。
static func migrate_legacy_saves(dirs: Array = []) -> int:
	if dirs.is_empty():
		for rel in LEGACY_DIRS:
			dirs.append(OS.get_data_dir().path_join(rel))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var copied := 0
	for old_dir in dirs:
		var dir := DirAccess.open(old_dir)
		if dir == null:
			continue
		for f in dir.get_files():
			if not (f.ends_with(EXT) or f.ends_with(EXT + ".bak")):
				continue
			var dst := SAVE_DIR.path_join(f)
			if FileAccess.file_exists(dst):
				continue
			if DirAccess.copy_absolute(String(old_dir).path_join(f), ProjectSettings.globalize_path(dst)) == OK and f.ends_with(EXT):
				copied += 1
	return copied


static func list_saves() -> Array:
	var out := []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(EXT):
			var path := SAVE_DIR.path_join(file)
			out.append({"path": path, "header": read_header(path)})
	out.sort_custom(func(a, b): return int(a.header.get("saved_at", 0)) > int(b.header.get("saved_at", 0)))
	return out


static func delete_save(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func format_time(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]


static func format_duration(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d 小时 %d 分" % [s / 3600, (s % 3600) / 60]
	return "%d 分钟" % maxi(1, s / 60) if s >= 60 else "不到 1 分钟"
