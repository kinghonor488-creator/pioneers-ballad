class_name EnemyDB
extends RefCounted
## 敌人定义表。想加新敌人：在 DEFS 里加一项，art 选一种画法（见 Enemy._draw），ai 选一种行为：
##   hopper  原地蓄力，朝玩家跳过去
##   walker  在地上走，追玩家，被挡住会跳
##   flyer   慢慢飘向玩家（phase = true 时能穿墙）
##   bat     飞行，路线忽左忽右，撞墙会弹开
##   shooter 和玩家保持距离，定时发射火球
##   turret  长在地上不动，玩家靠近就吐种子（毒刺花）
## spawn.biomes：只在这些生物群系出现（不写 = 哪里都可以，但在雪原/丛林/水晶洞里出现得少一些）
## inflict：碰到玩家时给玩家加的负面效果 [名字, 秒数, 几率]
## surface_only：只在地面附近活动（能穿过地面上的树和墙，但钻不进地下太深；玩家躲到地下它就会放弃离开）
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
		"name": "游魂", "ai": "flyer", "art": "wisp", "color": Color(0.6, 0.9, 1.0), "phase": true, "glow": 3.0, "surface_only": true,
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
	# ---------------- 雪原 ----------------
	"frost_wolf": {
		"name": "霜狼", "ai": "walker", "art": "wolf", "color": Color(0.82, 0.88, 0.95),
		"hp": 50, "damage": 16, "defense": 4, "size": Vector2(20, 12), "speed": 105.0, "kb_resist": 0.3,
		"inflict": ["冻伤", 3.0, 0.35],
		"drops": [["wolf_pelt", 1, 2, 0.7]],
		"spawn": {"layers": ["地表"], "biomes": ["snow"], "time": "any", "weight": 10},
	},
	"ice_wisp": {
		"name": "冰灵", "ai": "flyer", "art": "wisp", "color": Color(0.6, 0.85, 1.0), "phase": true, "glow": 3.0,
		"hp": 40, "damage": 18, "defense": 4, "size": Vector2(12, 12), "speed": 80.0, "kb_resist": 0.3,
		"inflict": ["冻伤", 4.0, 0.6],
		"drops": [["frost_shard", 1, 2, 0.75]],
		"spawn": {"layers": ["地表", "地下", "洞穴层"], "biomes": ["snow"], "time": "any", "weight": 8},
	},
	# ---------------- 丛林 ----------------
	"hornet": {
		"name": "丛林黄蜂", "ai": "bat", "art": "hornet", "color": Color(0.95, 0.75, 0.15),
		"hp": 35, "damage": 16, "defense": 3, "size": Vector2(14, 10), "speed": 135.0,
		"inflict": ["中毒", 5.0, 0.5],
		"drops": [["stinger", 1, 1, 0.6]],
		"spawn": {"layers": ["地表", "地下", "洞穴层"], "biomes": ["jungle"], "time": "any", "weight": 10},
	},
	"snapper": {
		"name": "毒刺花", "ai": "turret", "art": "plant", "color": Color(0.85, 0.25, 0.45),
		"hp": 60, "damage": 14, "defense": 6, "size": Vector2(16, 20), "speed": 0.0, "kb_resist": 1.0,
		"shoot": {"damage": 14, "speed": 210.0, "cooldown": 2.2, "kind": "seed", "inflict": ["中毒", 4.0, 0.6]},
		"drops": [["jungle_spore", 1, 3, 1.0]],
		"spawn": {"layers": ["地表", "地下", "洞穴层"], "biomes": ["jungle"], "time": "any", "weight": 6},
	},
	"bog_frog": {
		"name": "沼泽蛙", "ai": "hopper", "art": "frog", "color": Color(0.3, 0.6, 0.3),
		"hp": 45, "damage": 15, "defense": 4, "size": Vector2(14, 10), "speed": 120.0, "jump": 380.0,
		"drops": [["jungle_spore", 1, 2, 0.5]],
		"spawn": {"layers": ["地下", "洞穴层"], "biomes": ["jungle"], "time": "any", "weight": 8},
	},
	# ---------------- 水晶洞 ----------------
	"crystal_urchin": {
		"name": "晶刺刺猬", "ai": "walker", "art": "urchin", "color": Color(0.7, 0.6, 1.0), "glow": 2.5,
		"hp": 80, "damage": 24, "defense": 14, "size": Vector2(16, 12), "speed": 55.0, "kb_resist": 0.7,
		"drops": [["prism_ore", 1, 3, 0.6], ["crystal_shard", 1, 2, 0.6]],
		"spawn": {"layers": ["洞穴层"], "biomes": ["crystal"], "time": "any", "weight": 10},
	},
	"crystal_phantom": {
		"name": "水晶幽影", "ai": "flyer", "art": "phantom", "color": Color(0.85, 0.7, 1.0), "phase": true, "glow": 3.5,
		"hp": 65, "damage": 24, "defense": 8, "size": Vector2(14, 18), "speed": 85.0, "kb_resist": 0.4,
		"drops": [["crystal_shard", 2, 4, 0.8]],
		"spawn": {"layers": ["洞穴层"], "biomes": ["crystal"], "time": "any", "weight": 7},
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


## 某一层、某个时间、某个生物群系能刷出来的敌人：[[id, 权重], ...]
static func candidates(layer: String, night: bool, biome: String = "forest") -> Array:
	var out := []
	var special := biome in ["snow", "jungle", "crystal"]
	for id in DEFS:
		var sp: Dictionary = DEFS[id].spawn
		if not layer in sp.layers:
			continue
		var biomes: Array = sp.get("biomes", [])
		if not biomes.is_empty() and not biome in biomes:
			continue
		var t := String(sp.get("time", "any"))
		if t == "any" or (t == "night" and night) or (t == "day" and not night):
			var wgt := float(sp.weight)
			if biomes.is_empty() and special:
				wgt *= 0.25   # 特殊生物群系里，普通怪少一些
			out.append([id, wgt])
	return out


static func roll_drops(id: String, rng: RandomNumberGenerator) -> Array:
	var out := []
	for d in get_def(id).get("drops", []) + COMMON_DROPS:
		if rng.randf() < float(d[3]):
			out.append(ItemDB.make(d[0], rng.randi_range(d[1], d[2])))
	return out
