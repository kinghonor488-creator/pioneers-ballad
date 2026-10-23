class_name EnemyDB
extends RefCounted
## 敌人定义表。想加新敌人：在 DEFS 里加一项，art 选一种画法（见 Enemy._draw），ai 选一种行为：
##   hopper  原地蓄力，朝玩家跳过去
##   walker  在地上走，追玩家，被挡住会跳
##   flyer   慢慢飘向玩家（phase = true 时能穿墙）
##   bat     飞行，路线忽左忽右，撞墙会弹开
##   shooter 和玩家保持距离，定时发射火球
## spawn.layers 用的是 WorldData.layer_name() 返回的层名；time 是 "any" / "day" / "night"。
## drops: [道具 id, 最少, 最多, 几率]
## Boss（boss = true）不会自然刷出，只能用召唤道具叫出来；choice 里的武器会随机掉一把。

const DEFS := {
	"mudling": {
		"name": "泥团怪", "ai": "hopper", "art": "blob", "color": Color(0.55, 0.4, 0.25),
		"hp": 22, "damage": 8, "defense": 0, "size": Vector2(14, 10), "speed": 75.0, "jump": 330.0,
		"drops": [["mud_core", 1, 2, 1.0]],
		"spawn": {"layers": ["地表"], "time": "any", "weight": 10},
	},
	"wisp": {
		"name": "游魂", "ai": "flyer", "art": "wisp", "color": Color(0.6, 0.9, 1.0), "phase": true, "glow": 3.0,
		"hp": 30, "damage": 12, "defense": 2, "size": Vector2(12, 12), "speed": 70.0, "kb_resist": 0.3,
		"drops": [["wisp_dust", 1, 2, 0.8]],
		"spawn": {"layers": ["地表", "天空"], "time": "night", "weight": 9},
	},
	"cave_bat": {
		"name": "洞穴蝠", "ai": "bat", "art": "bat", "color": Color(0.42, 0.32, 0.48),
		"hp": 18, "damage": 10, "defense": 0, "size": Vector2(14, 8), "speed": 115.0,
		"drops": [["bat_wing", 1, 1, 0.5]],
		"spawn": {"layers": ["地下", "洞穴层"], "time": "any", "weight": 10},
	},
	"rock_beetle": {
		"name": "岩甲虫", "ai": "walker", "art": "beetle", "color": Color(0.45, 0.46, 0.52),
		"hp": 45, "damage": 14, "defense": 6, "size": Vector2(18, 12), "speed": 45.0, "kb_resist": 0.6,
		"drops": [["chitin", 1, 2, 0.9]],
		"spawn": {"layers": ["地下", "洞穴层"], "time": "any", "weight": 7},
	},
	"crystal_golem": {
		"name": "灵晶傀儡", "ai": "walker", "art": "golem", "color": Color(0.45, 1.0, 0.9), "glow": 2.5,
		"hp": 95, "damage": 22, "defense": 10, "size": Vector2(16, 24), "speed": 38.0, "kb_resist": 0.8,
		"drops": [["crystal_shard", 2, 4, 1.0]],
		"spawn": {"layers": ["洞穴层"], "time": "any", "weight": 4},
	},
	"ember_imp": {
		"name": "余烬魔", "ai": "shooter", "art": "imp", "color": Color(1.0, 0.45, 0.2), "phase": true, "glow": 2.5,
		"hp": 70, "damage": 20, "defense": 8, "size": Vector2(14, 16), "speed": 75.0, "kb_resist": 0.4,
		"shoot": {"damage": 18, "speed": 190.0, "cooldown": 2.8},
		"drops": [["ember_core", 1, 1, 0.35]],
		"spawn": {"layers": ["深渊"], "time": "any", "weight": 10},
	},
	# ---------------- Boss ----------------
	"mud_colossus": {
		"name": "泥沼巨像", "boss": true, "ai": "boss_mud", "art": "colossus", "color": Color(0.45, 0.33, 0.2),
		"hp": 900, "damage": 22, "defense": 4, "size": Vector2(44, 36), "speed": 160.0, "kb_resist": 1.0,
		"wave_damage": 16, "summon_layers": ["地表"],
		"intro": "大地在震动……泥沼巨像苏醒了！",
		"drops": [["mud_heart", 1, 1, 1.0], ["colossus_shard", 6, 10, 1.0], ["heal_potion", 2, 4, 1.0]],
		"choice": ["mud_hammer", "sludge_staff"],
		"spawn": {"layers": [], "time": "any", "weight": 0},
	},
	"crystal_warden": {
		"name": "灵晶守望者", "boss": true, "ai": "boss_warden", "art": "warden", "color": Color(0.45, 1.0, 0.9), "phase": true, "glow": 6.0,
		"hp": 2600, "damage": 30, "defense": 10, "size": Vector2(34, 34), "speed": 260.0, "kb_resist": 1.0,
		"shard_damage": 20, "summon_layers": ["洞穴层", "深渊"],
		"intro": "洞穴深处亮起冰冷的光……灵晶守望者降临了！",
		"drops": [["warden_eye", 1, 1, 1.0], ["warden_prism", 3, 5, 1.0], ["heal_potion", 3, 5, 1.0]],
		"choice": ["prism_staff", "prism_crossbow"],
		"spawn": {"layers": [], "time": "any", "weight": 0},
	},
}

## 所有敌人都有的稀有掉落
const COMMON_DROPS := [["heal_potion", 1, 1, 0.03], ["arrow", 3, 8, 0.08]]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func is_flying(id: String) -> bool:
	return String(get_def(id).get("ai", "")) in ["flyer", "bat", "shooter", "boss_warden"]


static func is_boss(id: String) -> bool:
	return bool(get_def(id).get("boss", false))


## 某一层、某个时间能刷出来的敌人：[[id, 权重], ...]
static func candidates(layer: String, night: bool) -> Array:
	var out := []
	for id in DEFS:
		var sp: Dictionary = DEFS[id].spawn
		if not layer in sp.layers:
			continue
		var t := String(sp.get("time", "any"))
		if t == "any" or (t == "night" and night) or (t == "day" and not night):
			out.append([id, float(sp.weight)])
	return out


static func roll_drops(id: String, rng: RandomNumberGenerator) -> Array:
	var out := []
	for d in get_def(id).get("drops", []) + COMMON_DROPS:
		if rng.randf() < float(d[3]):
			out.append(ItemDB.make(d[0], rng.randi_range(d[1], d[2])))
	return out
