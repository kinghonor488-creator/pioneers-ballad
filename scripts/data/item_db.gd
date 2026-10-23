class_name ItemDB
extends RefCounted
## 道具数据库 —— 本作的特色系统都在这里：
##   · 6 档稀有度（普通 → 神话），道具名字的颜色随稀有度变化
##   · 工具词缀：制作或从宝匣里得到的工具会随机带一个词缀（迅捷的、幸运的、星选的……），
##     在铁砧旁可以花灵晶碎片"重铸"词缀
##   · 工具熟练度：工具挖得越多等级越高（最高 Lv5），每级挖掘力 +6%
##   · 武器：近战剑、弓（消耗箭矢）、法杖（消耗法力），同样有词缀、熟练度和重铸
##   · 饰品栏（3 格）+ 药水增益：移动、跳跃、挖掘、照明、触及距离、免疫摔伤等效果可以叠加
##   · 遗迹宝匣：散落在地下，越深掉落越好
## 想加新道具：在 _build_items() 里加一行 _add(...)；想加配方：在 _build_recipes() 里加一行 _r(...)。
##
## 道具"实例"（放在背包格子里的东西）是一个字典：
##   {"id": "iron_pickaxe", "count": 1, "affix": "迅捷", "xp": 35}

const RARITY_NAMES := ["普通", "优良", "稀有", "史诗", "传说", "神话"]
const RARITY_COLORS := [
	Color(0.92, 0.92, 0.92),
	Color(0.5, 0.92, 0.5),
	Color(0.45, 0.72, 1.0),
	Color(0.78, 0.5, 1.0),
	Color(1.0, 0.66, 0.22),
	Color(1.0, 0.38, 0.5),
]
const CATEGORY_NAMES := {
	"block": "方块", "material": "材料", "tool": "工具", "consumable": "消耗品",
	"accessory": "饰品", "furniture": "家具", "throwable": "投掷物",
	"weapon": "武器", "ammo": "弹药",
}
const WEAPON_TYPE_NAMES := {"melee": "近战", "bow": "远程", "staff": "魔法"}
const STATION_NAMES := {"": "徒手", "workbench": "工作台", "furnace": "熔炉", "anvil": "铁砧"}
const EFFECT_NAMES := {
	"move": "移动速度", "jump": "跳跃力", "mine": "挖掘速度", "reach": "触及距离",
	"light": "照明", "nofall": "免疫摔落伤害", "maxhp": "最大生命", "luck": "双倍掉落几率",
	"power": "挖掘力", "defense": "防御", "damage": "伤害", "crit": "暴击率",
	"mana": "法力上限", "speed": "攻击速度", "knockback": "击退",
}

## 熟练度：达到这些经验值就升级（Lv0 ~ Lv5）
const MASTERY_XP := [0, 40, 120, 300, 600, 1000]
const MASTERY_BONUS := 0.06
## 没拿工具（徒手）时的挖掘能力
const HAND_PICK := 0.35
const HAND_AXE := 0.35
const REFORGE_COST := {"crystal_shard": 2}

## 工具词缀。weight 越大越常见；rarity 会加到工具的稀有度上（负数会降低）
const TOOL_AFFIXES := {
	"迅捷": {"weight": 12, "rarity": 1, "power": 0.15},
	"狂热": {"weight": 4, "rarity": 2, "power": 0.3},
	"远触": {"weight": 10, "rarity": 1, "reach": 2},
	"幸运": {"weight": 8, "rarity": 1, "luck": 0.15},
	"精工": {"weight": 5, "rarity": 2, "power": 0.1, "reach": 1, "luck": 0.05},
	"星选": {"weight": 1, "rarity": 3, "power": 0.25, "reach": 2, "luck": 0.2},
	"笨重": {"weight": 8, "rarity": -1, "power": -0.12},
	"钝口": {"weight": 5, "rarity": -1, "power": -0.2},
}
const NO_AFFIX_WEIGHT := 30

## 武器词缀
const WEAPON_AFFIXES := {
	"锋利": {"weight": 12, "rarity": 1, "damage": 0.15},
	"迅疾": {"weight": 10, "rarity": 1, "speed": 0.15},
	"致命": {"weight": 8, "rarity": 1, "crit": 0.1},
	"沉重": {"weight": 8, "rarity": 1, "knockback": 0.5, "damage": 0.05},
	"狂暴": {"weight": 4, "rarity": 2, "damage": 0.2, "speed": 0.1},
	"传奇": {"weight": 1, "rarity": 3, "damage": 0.2, "speed": 0.1, "crit": 0.05, "knockback": 0.2},
	"钝": {"weight": 7, "rarity": -1, "damage": -0.15},
	"迟缓": {"weight": 6, "rarity": -1, "speed": -0.15},
}
const BASE_CRIT := 0.04

static var _items: Dictionary = {}
static var _recipes: Array = []


# ---------------------------------------------------------------- 查询

static func items() -> Dictionary:
	if _items.is_empty():
		_build_items()
		_build_recipes()
	return _items


static func recipes() -> Array:
	items()
	return _recipes


static func get_def(id: String) -> Dictionary:
	return items().get(id, {})


static func exists(id: String) -> bool:
	return items().has(id)


static func category(id: String) -> String:
	return String(get_def(id).get("category", ""))


static func max_stack(id: String) -> int:
	return int(get_def(id).get("stack", 1))


static func can_stack(a: Dictionary, b: Dictionary) -> bool:
	return a.id == b.id and max_stack(a.id) > 1


# ---------------------------------------------------------------- 道具实例

static func make(id: String, count: int = 1, rng: RandomNumberGenerator = null) -> Dictionary:
	var inst := {"id": id, "count": count}
	var d := get_def(id)
	var cat := String(d.get("category", ""))
	if cat == "tool" or cat == "weapon":
		inst["affix"] = roll_affix(rng, WEAPON_AFFIXES if cat == "weapon" else TOOL_AFFIXES) if rng != null else ""
		inst["xp"] = int(d.get("start_xp", 0))
	return inst


static func roll_affix(rng: RandomNumberGenerator, table: Dictionary = TOOL_AFFIXES) -> String:
	var pool := [["", NO_AFFIX_WEIGHT]]
	for affix_name in table:
		pool.append([affix_name, table[affix_name]["weight"]])
	return String(weighted_pick(pool, rng))


## 工具和武器才有词缀和熟练度，也才能重铸
static func has_affix_slot(inst: Variant) -> bool:
	return inst != null and category(inst.id) in ["tool", "weapon"]


static func affix_table(inst: Variant) -> Dictionary:
	return WEAPON_AFFIXES if inst != null and category(inst.id) == "weapon" else TOOL_AFFIXES


static func affix_def(affix: String) -> Dictionary:
	return TOOL_AFFIXES.get(affix, WEAPON_AFFIXES.get(affix, {}))


static func weighted_pick(pool: Array, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for e in pool:
		total += float(e[1])
	var r := rng.randf() * total
	for e in pool:
		r -= float(e[1])
		if r <= 0.0:
			return e[0]
	return pool[pool.size() - 1][0]


static func affix_value(inst: Variant, key: String) -> float:
	if inst == null or String(inst.get("affix", "")) == "":
		return 0.0
	return float(affix_def(inst.affix).get(key, 0.0))


static func mastery_level(inst: Variant) -> int:
	if inst == null:
		return 0
	var xp := int(inst.get("xp", 0))
	var lvl := 0
	for i in range(1, MASTERY_XP.size()):
		if xp >= MASTERY_XP[i]:
			lvl = i
	return lvl


static func display_name(inst: Variant) -> String:
	if inst == null:
		return ""
	var n := String(get_def(inst.id).get("name", inst.id))
	var affix := String(inst.get("affix", ""))
	return n if affix == "" else "%s的%s" % [affix, n]


static func rarity(inst: Variant) -> int:
	if inst == null:
		return 0
	var r := int(get_def(inst.id).get("rarity", 0))
	var affix := String(inst.get("affix", ""))
	if affix != "":
		r += int(affix_def(affix).get("rarity", 0))
	return clampi(r, 0, RARITY_NAMES.size() - 1)


static func rarity_color(inst: Variant) -> Color:
	return RARITY_COLORS[rarity(inst)]


# ---------------------------------------------------------------- 工具数值

static func is_tool_item(inst: Variant) -> bool:
	return inst != null and category(inst.id) == "tool"


static func tool_tier(inst: Variant) -> int:
	if is_tool_item(inst):
		return maxi(1, int(get_def(inst.id).get("tier", 1)))
	return 1


static func power_multiplier(inst: Variant) -> float:
	if not is_tool_item(inst):
		return 1.0
	return 1.0 + affix_value(inst, "power") + mastery_level(inst) * MASTERY_BONUS


## 对某种图块（"earth"/"wood"）每秒的挖掘量
static func mining_power(inst: Variant, kind: String) -> float:
	var pick := HAND_PICK
	var axe := HAND_AXE
	if is_tool_item(inst):
		var d := get_def(inst.id)
		var mult := power_multiplier(inst)
		pick = maxf(pick, float(d.get("pick", 0.0)) * mult)
		axe = maxf(axe, float(d.get("axe", 0.0)) * mult)
	if kind == "wood":
		return maxf(axe, pick * 0.5)
	return pick


static func tool_reach(inst: Variant) -> float:
	if not is_tool_item(inst):
		return 0.0
	return float(get_def(inst.id).get("reach", 0.0)) + affix_value(inst, "reach")


# ---------------------------------------------------------------- 武器数值

static func is_weapon(inst: Variant) -> bool:
	return inst != null and category(inst.id) == "weapon"


static func weapon_def(inst: Variant) -> Dictionary:
	return get_def(inst.id).get("weapon", {}) if inst != null else {}


## 不含饰品/增益加成的伤害；extra 是弹药附加伤害
static func weapon_damage(inst: Variant, extra: float = 0.0) -> float:
	var w := weapon_def(inst)
	return (float(w.get("damage", 1)) + extra) * (1.0 + affix_value(inst, "damage") + mastery_level(inst) * MASTERY_BONUS)


## 每秒攻击次数
static func weapon_speed(inst: Variant) -> float:
	return float(weapon_def(inst).get("speed", 2.0)) * maxf(0.2, 1.0 + affix_value(inst, "speed"))


static func weapon_crit(inst: Variant) -> float:
	return BASE_CRIT + float(weapon_def(inst).get("crit", 0.0)) + affix_value(inst, "crit")


static func weapon_knockback(inst: Variant) -> float:
	return float(weapon_def(inst).get("knockback", 3.0)) * (1.0 + affix_value(inst, "knockback"))


# ---------------------------------------------------------------- 文字说明

static func effects_lines(effects: Dictionary) -> Array:
	var out := []
	for k in effects:
		var v: Variant = effects[k]
		match k:
			"nofall":
				out.append("免疫摔落伤害")
			"light":
				out.append("照明 +%d 格" % int(v))
			"reach":
				out.append("触及距离 +%d 格" % int(v))
			"maxhp":
				out.append("最大生命 +%d" % int(v))
			"defense":
				out.append("防御 +%d" % int(v))
			"mana":
				out.append("法力上限 +%d" % int(v))
			_:
				out.append("%s +%d%%" % [EFFECT_NAMES.get(k, k), roundi(float(v) * 100.0)])
	return out


## 返回 [[文字, 颜色], ...]，界面用来画悬停提示
static func tooltip(inst: Variant) -> Array:
	var lines := []
	if inst == null:
		return lines
	var d := get_def(inst.id)
	var cat := String(d.get("category", ""))
	var grey := Color(0.7, 0.72, 0.78)
	var good := Color(0.55, 0.95, 0.6)
	var bad := Color(1.0, 0.45, 0.4)
	var blue := Color(0.6, 0.8, 1.0)
	lines.append([display_name(inst), rarity_color(inst)])
	lines.append(["%s · %s" % [RARITY_NAMES[rarity(inst)], CATEGORY_NAMES.get(cat, cat)], grey])
	if cat == "tool":
		var mult := power_multiplier(inst)
		if float(d.get("pick", 0.0)) > 0.0:
			lines.append(["镐力 %.2f    镐等级 %d" % [float(d.pick) * mult, int(d.get("tier", 1))], Color.WHITE])
		if float(d.get("axe", 0.0)) > 0.0:
			lines.append(["斧力 %.2f" % (float(d.axe) * mult), Color.WHITE])
		if float(d.get("reach", 0.0)) > 0.0:
			lines.append(["触及距离 +%d 格" % int(d.reach), blue])
	if cat == "weapon":
		var w: Dictionary = d.weapon
		lines.append(["%d 点%s伤害" % [roundi(weapon_damage(inst)), WEAPON_TYPE_NAMES.get(w.type, "")], Color.WHITE])
		lines.append(["攻击速度 %.1f 次/秒    暴击率 %d%%" % [weapon_speed(inst), roundi(weapon_crit(inst) * 100)], Color.WHITE])
		lines.append(["击退 %.1f" % weapon_knockback(inst), grey])
		if w.type == "bow":
			lines.append(["需要箭矢（放在背包里即可）", blue])
		elif w.type == "staff":
			lines.append(["每次消耗 %d 点法力" % int(w.mana), blue])
	if has_affix_slot(inst):
		var affix := String(inst.get("affix", ""))
		if affix != "":
			var a := affix_def(affix)
			for k in ["power", "reach", "luck", "damage", "speed", "crit", "knockback"]:
				if a.has(k):
					var v := float(a[k])
					var txt := ("%s %+d 格" % [EFFECT_NAMES[k], int(v)]) if k == "reach" else ("%s %+d%%" % [EFFECT_NAMES[k], roundi(v * 100.0)])
					lines.append(["【%s】%s" % [affix, txt], good if v > 0 else bad])
		var lvl := mastery_level(inst)
		var xp := int(inst.get("xp", 0))
		var what := "伤害" if cat == "weapon" else "挖掘力"
		if lvl >= MASTERY_XP.size() - 1:
			lines.append(["熟练度 Lv%d（已满，%s +%d%%）" % [lvl, what, roundi(lvl * MASTERY_BONUS * 100)], RARITY_COLORS[4]])
		else:
			lines.append(["熟练度 Lv%d  (%d/%d)  %s +%d%%" % [lvl, xp, MASTERY_XP[lvl + 1], what, roundi(lvl * MASTERY_BONUS * 100)], RARITY_COLORS[4]])
	if d.has("ammo"):
		lines.append(["弓用的箭矢，伤害 +%d%s" % [int(d.ammo.damage), ("，可穿透 %d 个敌人" % int(d.ammo.pierce)) if int(d.ammo.get("pierce", 1)) > 1 else ""], Color.WHITE])
	if d.has("effects"):
		for t in effects_lines(d.effects):
			lines.append([t, blue])
		lines.append(["放进饰品栏后生效", grey])
	if d.has("use"):
		var u: Dictionary = d.use
		if u.has("heal"):
			lines.append(["恢复 %d 点生命" % int(u.heal), good])
		if u.has("buff"):
			lines.append(["获得「%s」效果 %d 秒：" % [u.buff, int(u.time)], good])
			for t in effects_lines(u.effects):
				lines.append(["  " + t, blue])
		if u.has("teleport"):
			lines.append(["立刻传送回出生点", good])
		if u.has("summon"):
			lines.append(["召唤 Boss：%s" % EnemyDB.get_def(u.summon).name, Color(1.0, 0.5, 0.45)])
		if u.has("maxhp"):
			lines.append(["永久提升最大生命 %d（最多使用 5 次）" % int(u.maxhp), good])
	if d.has("throw"):
		lines.append(["扔出后 %.1f 秒爆炸，半径 %d 格" % [float(d.throw.fuse), int(d.throw.radius)], Color(1.0, 0.7, 0.4)])
	if d.has("place"):
		lines.append(["可以放置", grey])
	if String(d.get("desc", "")) != "":
		lines.append([d.desc, Color(0.85, 0.82, 0.7)])
	return lines


# ---------------------------------------------------------------- 遗迹宝匣掉落

## depth01：0 = 刚到地下，1 = 世界底部
static func roll_chest_loot(rng: RandomNumberGenerator, depth01: float) -> Array:
	var out := []
	if rng.randf() < 0.55 + 0.3 * depth01:
		var pool := [
			["feather_charm", 10], ["gale_boots", 10], ["spring_shoes", 10],
			["glowstone_necklace", 9], ["miner_gloves", 7], ["reach_bracer", 6],
			["vital_amulet", 8], ["ancient_pickaxe", 4], ["wanderer_core", 1.0 + depth01 * 3.0],
			["gale_dagger", 4], ["berserker_emblem", 5], ["hunter_goggles", 5], ["spring_pendant", 5],
			["starstone_bow", 1.0 + depth01 * 2.0],
		]
		out.append(make(String(weighted_pick(pool, rng)), 1, rng))
	else:
		var potions := ["heal_potion", "glow_potion", "miner_potion", "swift_potion", "leap_potion"]
		out.append(make(potions[rng.randi() % potions.size()], rng.randi_range(2, 3)))
	var extras := [
		[["torch", 6, 15], 10], [["heal_potion", 1, 3], 7], [["bomb", 2, 5], 6],
		[["crystal_shard", 2, 6], 6], [["return_scroll", 1, 2], 4], [["copper_bar", 3, 8], 7.0 * (1.0 - depth01)],
		[["iron_bar", 3, 8], 6], [["moonsilver_bar", 2, 6], 6.0 * depth01], [["life_fruit", 1, 1], 1.0 + 2.0 * depth01],
		[["glow_potion", 1, 2], 4], [["miner_potion", 1, 2], 4], [["big_bomb", 1, 2], 2.0 * depth01],
		[["arrow", 20, 50], 6], [["flame_arrow", 10, 30], 3.0 * depth01],
	]
	for i in rng.randi_range(2, 4):
		var e: Array = weighted_pick(extras, rng)
		out.append(make(e[0], rng.randi_range(e[1], e[2])))
	return out


# ---------------------------------------------------------------- 数据定义

static func _add(id: String, display: String, cat: String, rarity_value: int, props: Dictionary = {}) -> void:
	var stackable := cat in ["block", "material", "consumable", "throwable", "furniture"]
	var d := {"id": id, "name": display, "category": cat, "rarity": rarity_value, "stack": 999 if stackable else 1, "desc": ""}
	d.merge(props, true)
	_items[id] = d


static func _r(result: String, count: int, station: String, ingredients: Dictionary) -> void:
	_recipes.append({"result": result, "count": count, "station": station, "ingredients": ingredients})


static func _build_items() -> void:
	_build_weapons()
	var wood := Color(0.55, 0.36, 0.2)
	# —— 方块 ——
	_add("dirt", "泥土", "block", 0, {"place": TileDB.DIRT, "desc": "松软的泥土。"})
	_add("stone", "石块", "block", 0, {"place": TileDB.STONE, "desc": "最常见的建材，熔炉的原料。"})
	_add("sand", "沙子", "block", 0, {"place": TileDB.SAND, "desc": "在熔炉里能烧成玻璃。"})
	_add("clay", "黏土", "block", 0, {"place": TileDB.CLAY})
	_add("basalt", "玄武岩", "block", 1, {"place": TileDB.BASALT, "desc": "深渊里的黑色岩石，坚硬无比。"})
	_add("planks", "木板", "block", 0, {"place": TileDB.PLANKS})
	_add("stone_brick", "石砖", "block", 0, {"place": TileDB.STONE_BRICK})
	_add("glass", "玻璃", "block", 0, {"place": TileDB.GLASS})
	# —— 材料 ——
	_add("wood", "木材", "material", 0, {"icon": "log", "color": wood, "desc": "砍树得到。用途最广的材料。"})
	_add("copper_ore", "赤铜矿", "material", 0, {"place": TileDB.COPPER_ORE, "desc": "地表附近常见的红色矿石。"})
	_add("iron_ore", "铁矿", "material", 0, {"place": TileDB.IRON_ORE, "desc": "需要赤铜镐以上才能开采。"})
	_add("moonsilver_ore", "月银矿", "material", 1, {"place": TileDB.MOONSILVER_ORE, "desc": "洞穴层深处泛着冷光的矿石。"})
	_add("starstone_ore", "星辉矿", "material", 2, {"place": TileDB.STARSTONE_ORE, "desc": "传说是坠落的星星碎片。"})
	_add("ember_ore", "熔晶矿", "material", 3, {"place": TileDB.EMBER_ORE, "desc": "深渊之中，仍在发烫。"})
	_add("sulfur", "硫磺", "material", 0, {"place": TileDB.SULFUR, "desc": "易燃，可以做更亮的火把和炸弹。"})
	_add("crystal_shard", "灵晶碎片", "material", 1, {"icon": "shard", "color": Color(0.5, 1.0, 0.92), "desc": "深层洞穴里会发光的晶体碎片，蕴含奇妙的能量。"})
	_add("mushroom", "蘑菇", "material", 0, {"place": TileDB.MUSHROOM, "desc": "可以烤着吃，也是药水原料。"})
	_add("copper_bar", "赤铜锭", "material", 0, {"icon": "bar", "color": Color(0.9, 0.5, 0.28)})
	_add("iron_bar", "铁锭", "material", 0, {"icon": "bar", "color": Color(0.75, 0.75, 0.8)})
	_add("moonsilver_bar", "月银锭", "material", 1, {"icon": "bar", "color": Color(0.75, 0.92, 1.0)})
	_add("starstone_bar", "星辉锭", "material", 2, {"icon": "bar", "color": Color(0.68, 0.5, 1.0)})
	_add("ember_bar", "熔晶锭", "material", 3, {"icon": "bar", "color": Color(1.0, 0.5, 0.18)})
	_add("glass_bottle", "玻璃瓶", "material", 0, {"icon": "bottle", "color": Color(0.8, 0.95, 1.0), "desc": "装药水用。"})
	# —— 家具 / 照明 ——
	_add("torch", "火把", "furniture", 0, {"place": TileDB.TORCH, "desc": "照亮黑暗。可以插在墙上。"})
	_add("workbench", "工作台", "furniture", 0, {"place": TileDB.WORKBENCH, "desc": "站在附近可以制作更多东西。"})
	_add("furnace", "熔炉", "furniture", 0, {"place": TileDB.FURNACE, "desc": "冶炼矿石、烧制玻璃。"})
	_add("anvil", "铁砧", "furniture", 1, {"place": TileDB.ANVIL, "desc": "打造高级工具，也能重铸工具词缀。"})
	# —— 工具 ——
	_add("flint_pickaxe", "燧石镐", "tool", 0, {"icon": "pickaxe", "color": Color(0.55, 0.55, 0.6), "pick": 1.0, "tier": 1, "desc": "每个冒险者的第一把镐。"})
	_add("copper_pickaxe", "赤铜镐", "tool", 0, {"icon": "pickaxe", "color": Color(0.9, 0.5, 0.28), "pick": 1.4, "tier": 2})
	_add("iron_pickaxe", "铁镐", "tool", 1, {"icon": "pickaxe", "color": Color(0.78, 0.78, 0.84), "pick": 1.9, "tier": 3})
	_add("moonsilver_pickaxe", "月银镐", "tool", 2, {"icon": "pickaxe", "color": Color(0.75, 0.92, 1.0), "pick": 2.6, "tier": 4})
	_add("starstone_pickaxe", "星辉镐", "tool", 3, {"icon": "pickaxe", "color": Color(0.68, 0.5, 1.0), "pick": 3.4, "tier": 5, "reach": 1})
	_add("ember_drill", "熔晶钻头", "tool", 4, {"icon": "drill", "color": Color(1.0, 0.5, 0.18), "pick": 5.0, "tier": 6, "reach": 1, "desc": "能钻开世界上任何能被钻开的东西。"})
	_add("ancient_pickaxe", "古代遗镐", "tool", 3, {"icon": "pickaxe", "color": Color(0.95, 0.8, 0.35), "pick": 2.3, "tier": 4, "start_xp": 120, "desc": "在遗迹宝匣里找到的古老工具，似乎还记得前任主人的手感。"})
	_add("flint_axe", "燧石斧", "tool", 0, {"icon": "axe", "color": Color(0.55, 0.55, 0.6), "axe": 1.6, "desc": "砍树用。"})
	_add("copper_axe", "赤铜斧", "tool", 0, {"icon": "axe", "color": Color(0.9, 0.5, 0.28), "axe": 2.4})
	_add("iron_axe", "铁斧", "tool", 1, {"icon": "axe", "color": Color(0.78, 0.78, 0.84), "axe": 3.4})
	# —— 消耗品 ——
	_add("apple", "苹果", "consumable", 0, {"icon": "apple", "color": Color(0.88, 0.18, 0.18), "use": {"heal": 15}, "desc": "从树叶里偶尔掉下来。"})
	_add("roasted_mushroom", "烤蘑菇", "consumable", 0, {"icon": "roast", "color": Color(0.62, 0.36, 0.18), "use": {"heal": 30}})
	_add("heal_potion", "治疗药水", "consumable", 1, {"icon": "potion", "color": Color(0.95, 0.25, 0.35), "use": {"heal": 60}})
	_add("glow_potion", "萤光药水", "consumable", 1, {"icon": "potion", "color": Color(0.4, 1.0, 0.85), "use": {"buff": "萤光", "time": 240.0, "effects": {"light": 6.0}}})
	_add("swift_potion", "迅捷药水", "consumable", 1, {"icon": "potion", "color": Color(0.75, 1.0, 0.3), "use": {"buff": "迅捷", "time": 180.0, "effects": {"move": 0.3}}})
	_add("miner_potion", "采掘药水", "consumable", 1, {"icon": "potion", "color": Color(1.0, 0.6, 0.2), "use": {"buff": "采掘", "time": 240.0, "effects": {"mine": 0.35}}})
	_add("leap_potion", "跃升药水", "consumable", 1, {"icon": "potion", "color": Color(0.4, 0.6, 1.0), "use": {"buff": "跃升", "time": 180.0, "effects": {"jump": 0.35}}})
	_add("return_scroll", "回城卷轴", "consumable", 1, {"icon": "scroll", "color": Color(0.93, 0.85, 0.65), "use": {"teleport": true}, "desc": "迷路了？读一下就回家。"})
	_add("life_fruit", "生命果", "consumable", 3, {"icon": "fruit", "color": Color(1.0, 0.4, 0.62), "use": {"maxhp": 20}})
	# —— 投掷物 ——
	_add("bomb", "炸弹", "throwable", 0, {"icon": "bomb", "color": Color(0.22, 0.22, 0.26), "throw": {"radius": 3.0, "fuse": 2.0}, "desc": "炸开周围的方块（不会掉落东西）。小心别炸到自己！"})
	_add("big_bomb", "烈性炸药", "throwable", 2, {"icon": "bomb", "color": Color(0.55, 0.12, 0.12), "throw": {"radius": 5.0, "fuse": 2.5}})
	# —— 饰品 ——
	_add("feather_charm", "羽落护符", "accessory", 2, {"icon": "feather", "color": Color(0.95, 0.95, 1.0), "effects": {"nofall": true}})
	_add("gale_boots", "疾风靴", "accessory", 2, {"icon": "boots", "color": Color(0.3, 0.75, 0.9), "effects": {"move": 0.25}})
	_add("spring_shoes", "弹簧鞋", "accessory", 2, {"icon": "boots", "color": Color(0.9, 0.6, 0.2), "effects": {"jump": 0.3}})
	_add("glowstone_necklace", "萤石项链", "accessory", 2, {"icon": "amulet", "color": Color(0.5, 1.0, 0.8), "effects": {"light": 5.0}})
	_add("miner_gloves", "矿工手套", "accessory", 1, {"icon": "glove", "color": Color(0.75, 0.55, 0.3), "effects": {"mine": 0.2}})
	_add("reach_bracer", "延伸臂环", "accessory", 2, {"icon": "bracer", "color": Color(0.75, 0.85, 1.0), "effects": {"reach": 2}})
	_add("vital_amulet", "活力护符", "accessory", 2, {"icon": "amulet", "color": Color(1.0, 0.35, 0.4), "effects": {"maxhp": 25}})
	_add("chitin_charm", "甲壳护符", "accessory", 1, {"icon": "chitin", "color": Color(0.5, 0.55, 0.62), "effects": {"defense": 4}})
	_add("berserker_emblem", "狂战徽记", "accessory", 2, {"icon": "emblem", "color": Color(0.9, 0.3, 0.25), "effects": {"damage": 0.12}})
	_add("hunter_goggles", "猎手护目镜", "accessory", 2, {"icon": "goggles", "color": Color(0.45, 0.8, 0.5), "effects": {"crit": 0.08}})
	_add("spring_pendant", "灵泉坠饰", "accessory", 2, {"icon": "amulet", "color": Color(0.45, 0.6, 1.0), "effects": {"mana": 20}})
	_add("batwing_cloak", "蝠翼披风", "accessory", 2, {"icon": "wing", "color": Color(0.45, 0.32, 0.5), "effects": {"jump": 0.2, "move": 0.08}})
	_add("wanderer_core", "旅者星核", "accessory", 4, {"icon": "core", "color": Color(1.0, 0.85, 0.4), "effects": {"move": 0.12, "jump": 0.12, "mine": 0.15, "reach": 1, "light": 3.0}, "desc": "一颗温暖的小星星，似乎在为你指路。"})


static func _add_weapon(id: String, display: String, rarity_value: int, icon_shape: String, color: Color, weapon: Dictionary, desc: String = "") -> void:
	_add(id, display, "weapon", rarity_value, {"icon": icon_shape, "color": color, "weapon": weapon, "desc": desc})


static func _build_weapons() -> void:
	# 近战：range = 挥砍范围（像素）
	_add_weapon("flint_dagger", "燧石短剑", 0, "dagger", Color(0.55, 0.55, 0.6), {"type": "melee", "damage": 7, "speed": 2.6, "knockback": 2.0, "range": 22}, "削尖的燧石，聊胜于无。")
	_add_weapon("wooden_sword", "木剑", 0, "sword", Color(0.72, 0.52, 0.3), {"type": "melee", "damage": 8, "speed": 2.2, "knockback": 3.5, "range": 26})
	_add_weapon("copper_sword", "赤铜剑", 0, "sword", Color(0.9, 0.5, 0.28), {"type": "melee", "damage": 11, "speed": 2.2, "knockback": 4.0, "range": 28})
	_add_weapon("iron_sword", "铁剑", 1, "sword", Color(0.78, 0.78, 0.84), {"type": "melee", "damage": 15, "speed": 2.2, "knockback": 4.5, "range": 30})
	_add_weapon("moonsilver_sword", "月银剑", 2, "sword", Color(0.75, 0.92, 1.0), {"type": "melee", "damage": 21, "speed": 2.4, "knockback": 4.5, "range": 32})
	_add_weapon("starstone_sword", "星辉剑", 3, "sword", Color(0.68, 0.5, 1.0), {"type": "melee", "damage": 29, "speed": 2.5, "knockback": 5.0, "range": 34})
	_add_weapon("ember_greatsword", "熔晶大剑", 4, "greatsword", Color(1.0, 0.5, 0.18), {"type": "melee", "damage": 42, "speed": 1.8, "knockback": 7.0, "range": 42}, "沉重、灼热，一剑劈开深渊。")
	_add_weapon("gale_dagger", "风之短刃", 3, "dagger", Color(0.5, 1.0, 0.8), {"type": "melee", "damage": 14, "speed": 4.2, "knockback": 1.5, "range": 22, "crit": 0.06}, "快得像一阵风。只能在遗迹宝匣里找到。")
	# 弓：伤害 = 弓 + 箭
	_add_weapon("wooden_bow", "木弓", 0, "bow", Color(0.6, 0.4, 0.22), {"type": "bow", "damage": 6, "speed": 1.6, "knockback": 1.5, "shot_speed": 420.0})
	_add_weapon("iron_bow", "铁弓", 1, "bow", Color(0.78, 0.78, 0.84), {"type": "bow", "damage": 11, "speed": 1.9, "knockback": 2.0, "shot_speed": 480.0})
	_add_weapon("starstone_bow", "星辉长弓", 3, "bow", Color(0.68, 0.5, 1.0), {"type": "bow", "damage": 20, "speed": 2.2, "knockback": 2.5, "shot_speed": 560.0}, "射出的箭拖着星光。")
	# 法杖：消耗法力，弹道不受重力影响，可以穿透
	_add_weapon("wisp_staff", "幽光法杖", 2, "staff", Color(0.6, 0.9, 1.0), {"type": "staff", "damage": 14, "speed": 2.5, "knockback": 2.0, "mana": 5, "shot_speed": 330.0, "pierce": 2})
	_add_weapon("ember_staff", "炎爆法杖", 3, "staff", Color(1.0, 0.5, 0.2), {"type": "staff", "damage": 30, "speed": 1.5, "knockback": 5.0, "mana": 12, "shot_speed": 300.0, "pierce": 3})
	# 弹药
	_add("arrow", "箭矢", "ammo", 0, {"icon": "arrow", "color": Color(0.8, 0.8, 0.85), "ammo": {"type": "arrow", "damage": 2}})
	_add("flame_arrow", "火焰箭", "ammo", 1, {"icon": "arrow", "color": Color(1.0, 0.55, 0.2), "ammo": {"type": "arrow", "damage": 5}})
	_add("crystal_arrow", "灵晶箭", "ammo", 2, {"icon": "arrow", "color": Color(0.5, 1.0, 0.92), "ammo": {"type": "arrow", "damage": 7, "pierce": 3}})
	# Boss：召唤道具和战利品
	_add("mud_offering", "泥沼祭品", "consumable", 1, {"icon": "offering", "color": Color(0.55, 0.4, 0.25), "use": {"summon": "mud_colossus"}, "desc": "在地表使用，召唤泥沼巨像。"})
	_add("crystal_beacon", "灵晶信标", "consumable", 2, {"icon": "beacon", "color": Color(0.45, 1.0, 0.9), "use": {"summon": "crystal_warden"}, "desc": "在洞穴层或深渊使用，召唤灵晶守望者。"})
	_add("mud_heart", "泥王之心", "accessory", 3, {"icon": "heart", "color": Color(0.6, 0.42, 0.25), "effects": {"maxhp": 20, "defense": 3}, "desc": "击败泥沼巨像获得。仍在缓慢地跳动。"})
	_add("colossus_shard", "巨像碎片", "material", 2, {"icon": "chitin", "color": Color(0.5, 0.38, 0.26), "desc": "泥沼巨像身上剥落的硬块。"})
	_add("colossus_bulwark", "巨像壁垒", "accessory", 3, {"icon": "emblem", "color": Color(0.55, 0.42, 0.28), "effects": {"defense": 7}})
	_add("warden_eye", "守望之眼", "accessory", 4, {"icon": "eye", "color": Color(0.45, 1.0, 0.9), "effects": {"crit": 0.1, "light": 4.0}, "desc": "击败灵晶守望者获得。它还在看着什么。"})
	_add("warden_prism", "守望者棱晶", "material", 3, {"icon": "shard", "color": Color(0.85, 0.55, 1.0), "desc": "击败灵晶守望者获得。打造星辉镐和星辉剑必需。"})
	_add_weapon("mud_hammer", "泥沼战锤", 3, "hammer", Color(0.5, 0.38, 0.26), {"type": "melee", "damage": 26, "speed": 1.4, "knockback": 9.0, "range": 38}, "泥沼巨像的拳头做成的锤子。")
	_add_weapon("sludge_staff", "淤泥法杖", 3, "staff", Color(0.55, 0.42, 0.25), {"type": "staff", "damage": 18, "speed": 2.2, "knockback": 3.0, "mana": 6, "shot_speed": 300.0, "pierce": 2})
	_add_weapon("prism_staff", "棱晶法杖", 4, "staff", Color(0.85, 0.55, 1.0), {"type": "staff", "damage": 26, "speed": 2.4, "knockback": 3.0, "mana": 8, "shot_speed": 420.0, "pierce": 5}, "一道光能贯穿一排敌人。")
	_add_weapon("prism_crossbow", "棱光弩", 4, "bow", Color(0.85, 0.55, 1.0), {"type": "bow", "damage": 17, "speed": 3.2, "knockback": 2.0, "shot_speed": 620.0}, "连射如雨。")
	# 怪物掉落的材料
	_add("mud_core", "泥核", "material", 0, {"icon": "blob", "color": Color(0.55, 0.4, 0.25), "desc": "泥团怪身体里黏糊糊的核心。"})
	_add("bat_wing", "蝠翼膜", "material", 1, {"icon": "wing", "color": Color(0.45, 0.32, 0.5), "desc": "又薄又韧。"})
	_add("chitin", "甲壳片", "material", 1, {"icon": "chitin", "color": Color(0.5, 0.55, 0.62), "desc": "岩甲虫坚硬的背壳。"})
	_add("wisp_dust", "幽光尘", "material", 1, {"icon": "dust", "color": Color(0.6, 0.9, 1.0), "desc": "游魂消散后留下的微光。"})
	_add("ember_core", "余烬核心", "material", 3, {"icon": "core", "color": Color(1.0, 0.45, 0.15), "desc": "余烬魔体内永不熄灭的火种。"})


static func _build_recipes() -> void:
	# 武器和弹药
	_r("wooden_sword", 1, "", {"wood": 7})
	_r("wooden_bow", 1, "workbench", {"wood": 10})
	_r("arrow", 25, "workbench", {"wood": 1, "stone": 1})
	_r("flame_arrow", 25, "workbench", {"arrow": 25, "sulfur": 1})
	_r("crystal_arrow", 25, "anvil", {"arrow": 25, "crystal_shard": 1})
	_r("copper_sword", 1, "workbench", {"copper_bar": 7})
	_r("iron_sword", 1, "anvil", {"iron_bar": 9})
	_r("iron_bow", 1, "anvil", {"iron_bar": 8, "bat_wing": 2})
	_r("moonsilver_sword", 1, "anvil", {"moonsilver_bar": 11})
	_r("starstone_sword", 1, "anvil", {"starstone_bar": 11, "warden_prism": 1})
	_r("ember_greatsword", 1, "anvil", {"ember_bar": 14, "ember_core": 3})
	_r("wisp_staff", 1, "workbench", {"wisp_dust": 8, "crystal_shard": 4, "wood": 3})
	_r("ember_staff", 1, "anvil", {"ember_core": 4, "ember_bar": 8, "wisp_dust": 5})
	# Boss 召唤道具和 Boss 材料
	_r("mud_offering", 1, "workbench", {"mud_core": 15, "wood": 5})
	_r("crystal_beacon", 1, "anvil", {"crystal_shard": 15, "moonsilver_bar": 5, "wisp_dust": 3})
	_r("colossus_bulwark", 1, "anvil", {"colossus_shard": 12, "chitin": 6})
	# 怪物材料做的饰品和道具
	_r("spring_shoes", 1, "workbench", {"mud_core": 12, "iron_bar": 2})
	_r("chitin_charm", 1, "anvil", {"chitin": 8, "iron_bar": 2})
	_r("batwing_cloak", 1, "anvil", {"bat_wing": 8, "moonsilver_bar": 3})
	_r("glow_potion", 2, "workbench", {"wisp_dust": 2, "glass_bottle": 2})
	_r("heal_potion", 2, "workbench", {"mud_core": 3, "mushroom": 1, "glass_bottle": 2})
	# 徒手
	_r("workbench", 1, "", {"wood": 10})
	_r("torch", 3, "", {"wood": 1})
	_r("torch", 8, "", {"wood": 1, "sulfur": 1})
	_r("planks", 4, "", {"wood": 1})
	_r("flint_pickaxe", 1, "", {"wood": 4, "stone": 5})
	_r("flint_axe", 1, "", {"wood": 4, "stone": 3})
	# 工作台
	_r("furnace", 1, "workbench", {"stone": 20, "wood": 4, "torch": 3})
	_r("stone_brick", 2, "workbench", {"stone": 2})
	_r("copper_pickaxe", 1, "workbench", {"copper_bar": 8, "wood": 3})
	_r("copper_axe", 1, "workbench", {"copper_bar": 6, "wood": 3})
	_r("anvil", 1, "workbench", {"iron_bar": 5})
	_r("heal_potion", 1, "workbench", {"mushroom": 2, "glass_bottle": 1})
	_r("glow_potion", 1, "workbench", {"crystal_shard": 1, "mushroom": 1, "glass_bottle": 1})
	_r("swift_potion", 1, "workbench", {"apple": 2, "glass_bottle": 1})
	_r("miner_potion", 1, "workbench", {"copper_ore": 3, "mushroom": 1, "glass_bottle": 1})
	_r("leap_potion", 1, "workbench", {"apple": 1, "crystal_shard": 1, "glass_bottle": 1})
	_r("bomb", 3, "workbench", {"sulfur": 3, "wood": 1})
	_r("return_scroll", 1, "workbench", {"crystal_shard": 2, "wood": 2})
	# 熔炉
	_r("glass", 1, "furnace", {"sand": 2})
	_r("glass_bottle", 2, "furnace", {"glass": 1})
	_r("copper_bar", 1, "furnace", {"copper_ore": 3})
	_r("iron_bar", 1, "furnace", {"iron_ore": 3})
	_r("moonsilver_bar", 1, "furnace", {"moonsilver_ore": 4})
	_r("starstone_bar", 1, "furnace", {"starstone_ore": 4, "crystal_shard": 1})
	_r("ember_bar", 1, "furnace", {"ember_ore": 4})
	_r("roasted_mushroom", 1, "furnace", {"mushroom": 1})
	# 铁砧
	_r("iron_pickaxe", 1, "anvil", {"iron_bar": 10, "wood": 3})
	_r("iron_axe", 1, "anvil", {"iron_bar": 8, "wood": 3})
	_r("moonsilver_pickaxe", 1, "anvil", {"moonsilver_bar": 12})
	_r("starstone_pickaxe", 1, "anvil", {"starstone_bar": 12, "warden_prism": 2})
	_r("ember_drill", 1, "anvil", {"ember_bar": 15, "starstone_bar": 5})
	_r("big_bomb", 1, "anvil", {"bomb": 3, "iron_bar": 1})
	_r("life_fruit", 1, "anvil", {"crystal_shard": 8, "apple": 3})
	_r("miner_gloves", 1, "anvil", {"iron_bar": 6, "mushroom": 4})
	_r("reach_bracer", 1, "anvil", {"moonsilver_bar": 6, "crystal_shard": 2})
