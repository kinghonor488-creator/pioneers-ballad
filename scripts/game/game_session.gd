class_name GameSession
extends RefCounted
## 在场景之间传递"这次要玩哪个世界"：标题界面写入，游戏主场景读取。

static var save_path := ""            ## 存档文件路径；空字符串 = 不存档（自动测试用）
static var load_existing := false     ## true = 读取已有存档；false = 新建世界
static var world_name := ""
static var world_seed := 0            ## 0 = 随机
static var world_size := Vector2i(4200, 1200)
static var message := ""              ## 回到标题界面时要显示的提示（例如读档失败）


static func reset() -> void:
	save_path = ""
	load_existing = false
	world_name = ""
	world_seed = 0
	world_size = Vector2i(4200, 1200)
