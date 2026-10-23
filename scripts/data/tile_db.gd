class_name TileDB
extends RefCounted
## 图块（方块）定义表。
## 世界里每一格只存一个字节的图块 id，所以最多 256 种图块。
## 字段（没写的用默认值）：
##   solid    是否实心（会挡住玩家），默认 true
##   hardness 硬度：挖掘力为 1 时需要的秒数
##   tier     需要的镐等级，默认 1；99 表示无法破坏
##   kind     "earth"（用镐）或 "wood"（用斧更快）
##   drop     挖掉后得到的道具 id（见 ItemDB）
##   art      像素画风格（见 TileArt）
##   light    发光半径（图块数），0 表示不发光
##   support  "floor" 需要下方有实心方块，"any" 需要旁边有方块或墙

enum {
	AIR, DIRT, GRASS, STONE, SAND, CLAY,
	COPPER_ORE, IRON_ORE, MOONSILVER_ORE, STARSTONE_ORE, SULFUR,
	TRUNK, LEAVES, PLANKS, STONE_BRICK, GLASS,
	TORCH, WORKBENCH, FURNACE, ANVIL, RELIC_CHEST,
	MUSHROOM, CRYSTAL, BASALT, EMBER_ORE, BEDROCK,
	OBSIDIAN,  # 新图块只能加在这里（COUNT 前面），否则旧存档里的图块编号会错位
	COUNT,
}

enum { WALL_NONE, WALL_DIRT, WALL_STONE, WALL_COUNT }

const UNBREAKABLE_TIER := 99

const WALL_COLORS := [
	Color(0, 0, 0, 0),
	Color(0.24, 0.16, 0.1),
	Color(0.2, 0.2, 0.23),
]

const DEFS := {
	AIR: {"name": "空气", "solid": false, "hardness": 0.0, "tier": 0},
	DIRT: {"name": "泥土", "hardness": 0.5, "drop": "dirt", "color": Color(0.47, 0.32, 0.2)},
	GRASS: {"name": "草地", "hardness": 0.6, "drop": "dirt", "color": Color(0.47, 0.32, 0.2), "art": "grass"},
	STONE: {"name": "石头", "hardness": 1.2, "drop": "stone", "color": Color(0.46, 0.46, 0.5)},
	SAND: {"name": "沙子", "hardness": 0.4, "drop": "sand", "color": Color(0.87, 0.78, 0.5)},
	CLAY: {"name": "黏土", "hardness": 0.7, "drop": "clay", "color": Color(0.66, 0.38, 0.3)},
	COPPER_ORE: {"name": "赤铜矿", "hardness": 1.6, "drop": "copper_ore", "color": Color(0.9, 0.47, 0.24), "art": "ore"},
	IRON_ORE: {"name": "铁矿", "hardness": 2.0, "tier": 2, "drop": "iron_ore", "color": Color(0.8, 0.7, 0.62), "art": "ore"},
	MOONSILVER_ORE: {"name": "月银矿", "hardness": 2.6, "tier": 3, "drop": "moonsilver_ore", "color": Color(0.72, 0.9, 1.0), "art": "ore"},
	STARSTONE_ORE: {"name": "星辉矿", "hardness": 3.2, "tier": 4, "drop": "starstone_ore", "color": Color(0.66, 0.46, 1.0), "art": "ore"},
	SULFUR: {"name": "硫磺石", "hardness": 1.0, "drop": "sulfur", "color": Color(0.93, 0.86, 0.26), "art": "ore"},
	TRUNK: {"name": "树干", "solid": false, "hardness": 1.5, "kind": "wood", "drop": "wood", "color": Color(0.45, 0.29, 0.15), "art": "trunk"},
	LEAVES: {"name": "树叶", "solid": false, "hardness": 0.2, "kind": "wood", "drop": "", "color": Color(0.22, 0.52, 0.2), "art": "leaves"},
	PLANKS: {"name": "木板", "hardness": 1.0, "kind": "wood", "drop": "planks", "color": Color(0.72, 0.52, 0.3), "art": "planks"},
	STONE_BRICK: {"name": "石砖", "hardness": 1.6, "drop": "stone_brick", "color": Color(0.58, 0.58, 0.62), "art": "brick"},
	GLASS: {"name": "玻璃", "hardness": 0.5, "drop": "glass", "color": Color(0.75, 0.92, 1.0), "art": "glass"},
	TORCH: {"name": "火把", "solid": false, "hardness": 0.05, "drop": "torch", "art": "torch", "light": 7.0, "light_color": Color(1.0, 0.8, 0.5), "support": "any"},
	WORKBENCH: {"name": "工作台", "solid": false, "hardness": 0.6, "kind": "wood", "drop": "workbench", "color": Color(0.66, 0.45, 0.25), "art": "workbench", "support": "floor"},
	FURNACE: {"name": "熔炉", "solid": false, "hardness": 1.0, "drop": "furnace", "color": Color(0.5, 0.5, 0.54), "art": "furnace", "light": 3.0, "light_color": Color(1.0, 0.55, 0.25), "support": "floor"},
	ANVIL: {"name": "铁砧", "solid": false, "hardness": 1.5, "drop": "anvil", "color": Color(0.36, 0.38, 0.44), "art": "anvil", "support": "floor"},
	RELIC_CHEST: {"name": "遗迹宝匣", "solid": false, "hardness": 1.0, "drop": "", "color": Color(0.55, 0.33, 0.16), "art": "chest", "light": 2.5, "light_color": Color(1.0, 0.85, 0.4)},
	MUSHROOM: {"name": "蘑菇", "solid": false, "hardness": 0.05, "drop": "mushroom", "color": Color(0.85, 0.35, 0.22), "art": "mushroom", "support": "floor"},
	CRYSTAL: {"name": "灵晶簇", "solid": false, "hardness": 0.3, "drop": "crystal_shard", "color": Color(0.45, 1.0, 0.9), "art": "crystal", "light": 4.0, "light_color": Color(0.4, 1.0, 0.9), "support": "floor"},
	BASALT: {"name": "玄武岩", "hardness": 2.4, "tier": 3, "drop": "basalt", "color": Color(0.21, 0.19, 0.23), "art": "basalt"},
	EMBER_ORE: {"name": "熔晶矿", "hardness": 3.5, "tier": 5, "drop": "ember_ore", "color": Color(1.0, 0.45, 0.12), "art": "ore", "base": BASALT, "light": 2.5, "light_color": Color(1.0, 0.5, 0.2)},
	OBSIDIAN: {"name": "黑曜石", "hardness": 3.0, "tier": 3, "drop": "obsidian", "color": Color(0.2, 0.13, 0.3), "art": "obsidian"},
	BEDROCK: {"name": "深渊基岩", "hardness": 999.0, "tier": UNBREAKABLE_TIER, "drop": "", "color": Color(0.09, 0.08, 0.11), "art": "bedrock"},
}

static var _solid := PackedByteArray()


static func def(id: int) -> Dictionary:
	return DEFS.get(id, DEFS[AIR])


static func prop(id: int, key: String, default_value: Variant) -> Variant:
	return def(id).get(key, default_value)


static func is_solid(id: int) -> bool:
	if _solid.is_empty():
		_solid.resize(COUNT)
		for i in COUNT:
			_solid[i] = 1 if (i != AIR and bool(def(i).get("solid", true))) else 0
	return id < COUNT and _solid[id] == 1


static func tile_name(id: int) -> String:
	return String(def(id).get("name", "?"))


static func hardness(id: int) -> float:
	return float(def(id).get("hardness", 1.0))


static func tier(id: int) -> int:
	return int(def(id).get("tier", 1))


static func light_radius(id: int) -> float:
	return float(def(id).get("light", 0.0))
