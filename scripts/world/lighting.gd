class_name Lighting
extends Node
## 逐格光照。
##
## 每次计算摄像机附近一块区域（屏幕 + 四周各 MARGIN 格），每个图块得到一个 RGB 亮度：
##   1. 光源：天空直射（从世界顶部往下，碰到第一个实心方块之前都算露天）、
##      发光图块（火把、灵晶簇、熔炉……）、熔岩、会动的光源（玩家、发光的怪、法术弹、爆炸）
##   2. 扩散：横向、纵向来回扫几遍，每走一格亮度乘以衰减系数。
##      空气里衰减慢，实心方块里衰减快——所以光能照进洞口、照亮洞壁表面，但照不透厚岩层。
##      光是彩色的：灵晶簇是青色的，火把是暖黄色的，月光是蓝色的。
##   3. 结果写成一张小图（每格一个像素），交给 shaders/lighting.gdshader 乘到画面上。
##
## 计算放在后台线程里（WorkerThreadPool），主线程只负责拍"快照"和更新贴图，所以不会卡顿。

const MARGIN := 12
const AIR_DECAY := 0.82
const NONSOLID_DECAY := 0.78    ## 树叶、火把这类不挡路的图块
const SOLID_DECAY := 0.55
const WATER_DECAY := 0.72       ## 水会让光暗得快一点
const LAVA_LIGHT := Color(1.0, 0.45, 0.15)
const PASSES := 2
const MAX_HZ := 30.0
const SHADER := preload("res://shaders/lighting.gdshader")

var game: Node
var material: ShaderMaterial
var sun := Color.WHITE          ## 当前的天光颜色（由主控按昼夜设置）
var last_ms := 0.0              ## 最近一次计算用了多少毫秒
var last_image: Image
var last_origin := Vector2i.ZERO

var _tex: ImageTexture
var _task := -1
var _job := {}
var _cooldown := 0.0

static var _solid_tbl := PackedByteArray()
static var _light_str := PackedFloat32Array()
static var _light_col := PackedColorArray()


## 发光图块的亮度：半径 7 格（火把）= 1.0
static func strength_for_radius(radius: float) -> float:
	return clampf(radius / 7.0, 0.3, 1.3)


static func _build_tables() -> void:
	if not _solid_tbl.is_empty():
		return
	_solid_tbl.resize(256)
	_light_str.resize(256)
	_light_col.resize(256)
	for t in 256:
		_solid_tbl[t] = 1 if t >= TileDB.COUNT or TileDB.is_solid(t) else 0
		var r := TileDB.light_radius(t) if t < TileDB.COUNT else 0.0
		_light_str[t] = strength_for_radius(r) if r > 0.0 else 0.0
		_light_col[t] = TileDB.prop(t, "light_color", Color.WHITE) if t < TileDB.COUNT else Color.WHITE


func _init() -> void:
	_build_tables()
	material = ShaderMaterial.new()
	material.shader = SHADER


## 需要在世界、玩家、摄像机都建好之后调用
func setup(g: Node) -> void:
	game = g
	compute_now()


func set_enabled(on: bool) -> void:
	material.set_shader_parameter("enabled", on)


func _process(delta: float) -> void:
	if game == null or not game.ready_done:
		return
	_cooldown -= delta
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply(_job)
	if _task == -1 and _cooldown <= 0.0:
		_job = snapshot()
		_task = WorkerThreadPool.add_task(compute.bind(_job), false, "lighting")
		_cooldown = 1.0 / MAX_HZ


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## 在主线程里立刻算一次（刚进游戏、测试时用）。center 不填就以摄像机为中心，view 不填就用当前画面大小。
func compute_now(center: Vector2 = Vector2.INF, view: Vector2 = Vector2.ZERO) -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	var job := snapshot(center, view)
	compute(job)
	_apply(job)


## 某个图块现在的亮度（0~1，取三个通道的最大值），在最近一次算好的区域外返回 -1
func light_at(t: Vector2i) -> float:
	if last_image == null:
		return -1.0
	var p := t - last_origin
	if p.x < 0 or p.y < 0 or p.x >= last_image.get_width() or p.y >= last_image.get_height():
		return -1.0
	var c := last_image.get_pixelv(p)
	return maxf(c.r, maxf(c.g, c.b))


# ---------------------------------------------------------------- 主线程：拍快照

func snapshot(center: Vector2 = Vector2.INF, view: Vector2 = Vector2.ZERO) -> Dictionary:
	var w: WorldData = game.world
	if center == Vector2.INF:
		center = game.camera.get_screen_center_position() if game.camera != null else game.player.center()
	if view == Vector2.ZERO:
		view = game._view_size()
	var x0 := floori((center.x - view.x * 0.5) / 16.0) - MARGIN
	var y0 := floori((center.y - view.y * 0.5) / 16.0) - MARGIN
	var cols := ceili(view.x / 16.0) + MARGIN * 2 + 1
	var rows := ceili(view.y / 16.0) + MARGIN * 2 + 1
	var tiles := _slice(w, w.tiles, x0, y0, cols, rows, TileDB.AIR, TileDB.BEDROCK)
	var liquid := _slice(w, w.liquid, x0, y0, cols, rows, 0, 0)
	var sky := PackedInt32Array()
	sky.resize(cols)
	for i in cols:
		var x := x0 + i
		sky[i] = w.sky_y[x] if x >= 0 and x < w.width else 0
	var sources := []
	for n in game.get_tree().get_nodes_in_group("light"):
		if n.is_inside_tree() and n.visible:
			var s: Array = n.light_source()
			if not s.is_empty():
				var pos: Vector2 = s[0]
				sources.append([floori(pos.x / 16.0), floori(pos.y / 16.0), s[1], float(s[2])])
	return {"x0": x0, "y0": y0, "w": cols, "h": rows, "tiles": tiles, "liquid": liquid, "sky": sky, "sun": sun, "sources": sources}


## 从世界数组里切出一块矩形区域；世界上面用 above 填，下面用 below 填，左右两边用基岩/0 填
static func _slice(w: WorldData, arr: PackedByteArray, x0: int, y0: int, cols: int, rows: int, above: int, below: int) -> PackedByteArray:
	var out := PackedByteArray()
	var side := below
	for y in range(y0, y0 + rows):
		if y < 0 or y >= w.height:
			var row := PackedByteArray()
			row.resize(cols)
			row.fill(below if y >= w.height else above)
			out.append_array(row)
		elif x0 >= 0 and x0 + cols <= w.width:
			out.append_array(arr.slice(y * w.width + x0, y * w.width + x0 + cols))
		else:
			for x in range(x0, x0 + cols):
				out.append(arr[y * w.width + x] if x >= 0 and x < w.width else side)
	return out


# ---------------------------------------------------------------- 后台线程：传播

func compute(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var W: int = job.w
	var H: int = job.h
	var x0: int = job.x0
	var y0: int = job.y0
	var n := W * H
	var tiles: PackedByteArray = job.tiles
	var liquid: PackedByteArray = job.liquid
	var r := PackedFloat32Array()
	var g := PackedFloat32Array()
	var b := PackedFloat32Array()
	var decay := PackedFloat32Array()
	r.resize(n)
	g.resize(n)
	b.resize(n)
	decay.resize(n)
	r.fill(0.0)
	g.fill(0.0)
	b.fill(0.0)
	# 光源：图块
	for i in n:
		var t := tiles[i]
		decay[i] = SOLID_DECAY if _solid_tbl[t] == 1 else (AIR_DECAY if t == 0 else NONSOLID_DECAY)
		var s := _light_str[t]
		if s > 0.0:
			var c := _light_col[t]
			r[i] = c.r * s
			g[i] = c.g * s
			b[i] = c.b * s
		var lq := liquid[i]
		if lq != 0:
			if (lq >> 4) == WorldData.LIQ_LAVA:
				var k := 0.5 + 0.06 * (lq & 15)
				r[i] = maxf(r[i], LAVA_LIGHT.r * k)
				g[i] = maxf(g[i], LAVA_LIGHT.g * k)
				b[i] = maxf(b[i], LAVA_LIGHT.b * k)
			else:
				decay[i] = WATER_DECAY
	# 光源：天空
	var sun_c: Color = job.sun
	var sky: PackedInt32Array = job.sky
	for x in W:
		var top := mini(sky[x] - y0, H)
		for y in range(0, top):
			var i := y * W + x
			r[i] = maxf(r[i], sun_c.r)
			g[i] = maxf(g[i], sun_c.g)
			b[i] = maxf(b[i], sun_c.b)
	# 光源：会动的东西
	for s in job.sources:
		var sx: int = s[0] - x0
		var sy: int = s[1] - y0
		if sx < 0 or sy < 0 or sx >= W or sy >= H:
			continue
		var i := sy * W + sx
		var c: Color = s[2]
		var k: float = s[3]
		r[i] = maxf(r[i], c.r * k)
		g[i] = maxf(g[i], c.g * k)
		b[i] = maxf(b[i], c.b * k)
	# 扩散：横扫、竖扫，来回各一遍，重复 PASSES 次
	for pass_i in PASSES:
		for y in H:
			var row := y * W
			for x in range(1, W):
				_spread(r, g, b, decay, row + x - 1, row + x)
			for x in range(W - 2, -1, -1):
				_spread(r, g, b, decay, row + x + 1, row + x)
		for x in W:
			for y in range(1, H):
				_spread(r, g, b, decay, (y - 1) * W + x, y * W + x)
			for y in range(H - 2, -1, -1):
				_spread(r, g, b, decay, (y + 1) * W + x, y * W + x)
	# 写成 RGB8 图片
	var bytes := PackedByteArray()
	bytes.resize(n * 3)
	for i in n:
		bytes[i * 3] = mini(255, int(r[i] * 255.0))
		bytes[i * 3 + 1] = mini(255, int(g[i] * 255.0))
		bytes[i * 3 + 2] = mini(255, int(b[i] * 255.0))
	job["image"] = Image.create_from_data(W, H, false, Image.FORMAT_RGB8, bytes)
	job["ms"] = (Time.get_ticks_usec() - t0) / 1000.0


static func _spread(r: PackedFloat32Array, g: PackedFloat32Array, b: PackedFloat32Array, decay: PackedFloat32Array, from: int, to: int) -> void:
	var d := decay[to]
	var v := r[from] * d
	if v > r[to]:
		r[to] = v
	v = g[from] * d
	if v > g[to]:
		g[to] = v
	v = b[from] * d
	if v > b[to]:
		b[to] = v


# ---------------------------------------------------------------- 主线程：更新贴图

func _apply(job: Dictionary) -> void:
	if not job.has("image"):
		return
	var img: Image = job.image
	if _tex == null or Vector2i(_tex.get_size()) != img.get_size():
		_tex = ImageTexture.create_from_image(img)
		material.set_shader_parameter("lightmap", _tex)
	else:
		_tex.update(img)
	material.set_shader_parameter("lm_origin", Vector2(job.x0, job.y0) * 16.0)
	material.set_shader_parameter("lm_size", Vector2(job.w, job.h) * 16.0)
	last_image = img
	last_origin = Vector2i(job.x0, job.y0)
	last_ms = job.ms
