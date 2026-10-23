class_name GameSession
extends RefCounted
## 在场景之间传递"这次要玩哪个世界"：标题界面写入，游戏主场景读取。

static var save_path := ""            ## 存档文件路径；空字符串 = 不存档（自动测试用）
static var load_existing := false     ## true = 读取已有存档；false = 新建世界
static var world_name := ""
static var world_seed := 0            ## 0 = 随机
static var world_size := Vector2i(4200, 1200)
static var message := ""              ## 回到标题界面时要显示的提示（例如读档失败）


## 屏幕适配：
##   窗口比 1280×720 大 → 整体放大（字和图标都变大）；
##   窗口比 1280×720 小 → 最多缩到 85%，再小就不缩了，改成"画布变小"，界面自己重新排版。
##   这样小窗口、小屏幕上字也不会小到看不清。窗口最小 800×500。
const BASE_SIZE := Vector2i(1280, 720)
const MIN_SCALE := 0.85
const MIN_WINDOW := Vector2i(800, 500)
static var _screen_ready := false


static func setup_screen(tree: SceneTree) -> void:
	if _screen_ready:
		return
	_screen_ready = true
	var root := tree.root
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(MIN_WINDOW)
	root.size_changed.connect(func(): apply_screen_scale(root))
	apply_screen_scale(root)


## 按窗口大小决定画布大小（测试也会直接调用）
static func content_size_for(window: Vector2) -> Vector2i:
	var s := minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y)
	if s >= MIN_SCALE:
		return BASE_SIZE
	return Vector2i(ceili(window.x / MIN_SCALE), ceili(window.y / MIN_SCALE))


static func apply_screen_scale(root: Window) -> void:
	var want := content_size_for(Vector2(root.size))
	if root.content_scale_size != want:
		root.content_scale_size = want


## 全屏快捷键：F11、Alt+Enter，或者 macOS 习惯的 Ctrl+Cmd+F
static func is_fullscreen_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var k: int = event.physical_keycode
	return k == KEY_F11 or (k == KEY_ENTER and event.alt_pressed) or (k == KEY_F and event.ctrl_pressed and event.meta_pressed)


static func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


static func reset() -> void:
	save_path = ""
	load_existing = false
	world_name = ""
	world_seed = 0
	world_size = Vector2i(4200, 1200)
