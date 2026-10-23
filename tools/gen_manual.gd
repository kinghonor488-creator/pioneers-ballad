extends SceneTree
## 根据游戏里的真实数据，生成游戏手册里的速查表（配方、道具、敌人、方块、工具、词缀）。
##   godot --headless --path . -s res://tools/gen_manual.gd
## 会把 docs/游戏手册.md 里 <!-- AUTO:名字 --> 和 <!-- /AUTO:名字 --> 之间的内容替换成最新的表格。
## 改了道具或敌人以后重新运行一次，手册就和游戏保持一致了。

const MANUAL := "res://docs/游戏手册.md"


func _initialize() -> void:
	var path := ProjectSettings.globalize_path(MANUAL)
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		printerr("找不到 ", path)
		quit(1)
		return
	var sources := _sources()
	var blocks := {
		"RECIPES": _recipes(),
		"ITEMS": _items(sources),
		"ENEMIES": _enemies(),
		"TILES": _tiles(),
		"TOOLS": _tools(sources),
		"AFFIXES": _affixes(),
		"MASTERY": _mastery(),
		"COUNTS": "目前游戏里一共有 **%d 种道具**、**%d 个配方**、**%d 种敌人**（含 2 个 Boss）、**%d 种方块**。" % [
			ItemDB.items().size(), ItemDB.recipes().size(), EnemyDB.DEFS.size(), TileDB.COUNT - 1],
	}
	for key in blocks:
		var open := "<!-- AUTO:%s -->" % key
		var close := "<!-- /AUTO:%s -->" % key
		var a := text.find(open)
		var b := text.find(close)
		if a < 0 or b < 0:
			printerr("手册里缺少标记 ", open)
			continue
		text = text.substr(0, a + open.length()) + "\n" + String(blocks[key]).strip_edges() + "\n" + text.substr(b)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("手册速查表已更新：", path)
	quit(0)


func _n(id: String) -> String:
	return String(ItemDB.get_def(id).get("name", id))


func _cell(s: String) -> String:
	return s.replace("|", "／").replace("\n", " ")


## 每种道具从哪里来：配方、方块掉落、敌人掉落、宝匣
func _sources() -> Dictionary:
	var src := {}
	var add := func(id: String, how: String) -> void:
		if not src.has(id):
			src[id] = []
		if not how in src[id]:
			src[id].append(how)
	for r in ItemDB.recipes():
		add.call(r.result, "制作（%s）" % ItemDB.STATION_NAMES[r.station])
	for t in range(1, TileDB.COUNT):
		var drop := String(TileDB.prop(t, "drop", ""))
		if drop != "":
			add.call(drop, "挖%s" % TileDB.tile_name(t))
	add.call("apple", "砍树（树叶）")
	add.call("wood", "砍树")
	for eid in EnemyDB.DEFS:
		var d: Dictionary = EnemyDB.DEFS[eid]
		for dr in d.get("drops", []):
			add.call(dr[0], "打%s" % d.name)
		for c in d.get("choice", []):
			add.call(c, "打%s（随机一把）" % d.name)
	# 宝匣：大量抽样，看看都能开出什么
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for biome in ["", "snow", "jungle", "crystal"]:
		for i in 4000:
			for inst in ItemDB.roll_chest_loot(rng, float(i % 3) * 0.5, biome):
				add.call(inst.id, "遗迹宝匣" if biome == "" else "遗迹宝匣（%s）" % WorldData.BIOME_NAMES[biome])
	for id in ["flint_pickaxe", "flint_axe", "flint_dagger", "torch", "apple"]:
		add.call(id, "开局自带")
	for id in ["water_bucket", "lava_bucket"]:
		add.call(id, "用空桶装")
	add.call("obsidian", "水碰到熔岩")
	return src


func _recipes() -> String:
	var out := ""
	for st in ["", "workbench", "furnace", "anvil"]:
		out += "\n#### %s\n\n| 做出 | 数量 | 需要的材料 |\n| --- | --- | --- |\n" % ("徒手（随时随地）" if st == "" else ItemDB.STATION_NAMES[st] + "旁边")
		for r in ItemDB.recipes():
			if r.station != st:
				continue
			var mats := []
			for id in r.ingredients:
				mats.append("%s ×%d" % [_n(id), int(r.ingredients[id])])
			out += "| %s | %d | %s |\n" % [_n(r.result), int(r.count), "、".join(mats)]
	return out


func _items(src: Dictionary) -> String:
	var order := ["tool", "weapon", "ammo", "accessory", "consumable", "throwable", "utility", "furniture", "block", "material"]
	var out := ""
	for cat in order:
		out += "\n#### %s\n\n| 道具 | 稀有度 | 效果 / 说明 | 怎么得到 |\n| --- | --- | --- | --- |\n" % ItemDB.CATEGORY_NAMES[cat]
		for id in ItemDB.items():
			if ItemDB.category(id) != cat:
				continue
			var inst := ItemDB.make(id)
			var lines := ItemDB.tooltip(inst)
			var info := []
			for i in range(2, lines.size()):
				var t := String(lines[i][0]).strip_edges()
				if t.begins_with("熟练度 Lv") or t == "放进饰品栏后生效" or t == "可以放置":
					continue
				info.append(t)
			var how: Array = src.get(id, ["—"])
			out += "| %s | %s | %s | %s |\n" % [_n(id), ItemDB.RARITY_NAMES[ItemDB.rarity(inst)], _cell("；".join(info)), _cell("、".join(how))]
	return out


func _enemies() -> String:
	var ai_names := {
		"hopper": "蓄力后跳向你", "walker": "在地上追你，被挡住会跳", "flyer": "慢慢飘向你",
		"bat": "忽左忽右乱飞", "shooter": "停在斜上方发射火球", "turret": "长在地上不动，朝你吐毒种子",
		"boss_mud": "Boss（见第 11 章）", "boss_warden": "Boss（见第 11 章）",
	}
	var out := "| 敌人 | 出没地点 | 生命 | 伤害 | 防御 | 行为 | 附加效果 | 掉落 |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n"
	for eid in EnemyDB.DEFS:
		var d: Dictionary = EnemyDB.DEFS[eid]
		var sp: Dictionary = d.spawn
		var where := "召唤出现"
		if not Array(sp.layers).is_empty():
			var biomes := []
			for b in sp.get("biomes", []):
				biomes.append(WorldData.BIOME_NAMES[b])
			where = ("、".join(biomes) + "的" if not biomes.is_empty() else "") + "、".join(sp.layers)
			if sp.get("time", "any") == "night":
				where += "（只在夜晚）"
		var traits: String = ai_names.get(d.ai, d.ai)
		if d.get("phase", false):
			traits += "，能穿墙"
		if d.get("surface_only", false):
			traits += "，但钻不进地下（躲到地下它会放弃离开）"
		if d.has("glow"):
			traits += "，会发光"
		var inflict := "—"
		if d.has("inflict"):
			inflict = "%d%% 几率%s %d 秒" % [roundi(float(d.inflict[2]) * 100), d.inflict[0], int(d.inflict[1])]
		elif d.has("shoot") and d.shoot.has("inflict"):
			inflict = "种子 %d%% 几率%s" % [roundi(float(d.shoot.inflict[2]) * 100), d.shoot.inflict[0]]
		var drops := []
		for dr in d.get("drops", []):
			var amount := str(dr[1]) if dr[1] == dr[2] else "%d~%d" % [dr[1], dr[2]]
			drops.append("%s ×%s（%d%%）" % [_n(dr[0]), amount, roundi(float(dr[3]) * 100)])
		for c in d.get("choice", []):
			drops.append(_n(c) + "（二选一）")
		out += "| %s | %s | %d | %d | %d | %s | %s | %s |\n" % [d.name, where, int(d.hp), int(d.damage), int(d.defense), traits, inflict, _cell("、".join(drops))]
	out += "\n所有敌人还有 3% 几率掉治疗药水、8% 几率掉几支箭矢。\n"
	return out


func _tiles() -> String:
	var out := "| 方块 | 硬度 | 需要镐等级 | 挖到得到 | 备注 |\n| --- | --- | --- | --- | --- |\n"
	for t in range(1, TileDB.COUNT):
		var d := TileDB.def(t)
		var notes := []
		if not d.get("solid", true):
			notes.append("可以穿过")
		if float(d.get("light", 0.0)) > 0.0:
			notes.append("会发光")
		if d.get("kind", "earth") == "wood":
			notes.append("用斧更快")
		if d.get("slippery", false):
			notes.append("很滑")
		match String(d.get("support", "")):
			"floor":
				notes.append("下面要有方块托着")
			"any":
				notes.append("要贴着方块或背景墙")
			"ceiling":
				notes.append("挂在上面的东西下面")
		var tier := int(d.get("tier", 1))
		var drop := String(d.get("drop", ""))
		if t == TileDB.RELIC_CHEST:
			drop = "宝物"
		elif t == TileDB.TRUNK:
			drop = "wood"
		out += "| %s | %s | %s | %s | %s |\n" % [
			d.name, "—" if tier >= TileDB.UNBREAKABLE_TIER else "%.1f" % float(d.get("hardness", 1.0)),
			"无法破坏" if tier >= TileDB.UNBREAKABLE_TIER else str(tier),
			"宝物（见 7.6）" if drop == "宝物" else (_n(drop) if drop != "" else "—"), "、".join(notes) if not notes.is_empty() else ""]
	return out


func _tools(src: Dictionary) -> String:
	var out := "| 工具 | 镐力 | 镐等级 | 斧力 | 额外触及 | 怎么得到 |\n| --- | --- | --- | --- | --- | --- |\n"
	for id in ItemDB.items():
		if ItemDB.category(id) != "tool":
			continue
		var d := ItemDB.get_def(id)
		out += "| %s | %s | %s | %s | %s | %s |\n" % [_n(id), "%.1f" % float(d.pick) if d.has("pick") else "—",
			str(int(d.tier)) if d.has("pick") else "—", "%.1f" % float(d.axe) if d.has("axe") else "—",
			("+%d 格" % int(d.reach)) if d.has("reach") else "—", "、".join(src.get(id, ["—"]))]
	return out


func _affixes() -> String:
	var out := ""
	for pair in [["工具词缀（镐、斧）", ItemDB.TOOL_AFFIXES], ["武器词缀（剑、弓、法杖）", ItemDB.WEAPON_AFFIXES]]:
		var table: Dictionary = pair[1]
		var total := float(ItemDB.NO_AFFIX_WEIGHT)
		for k in table:
			total += float(table[k].weight)
		out += "\n#### %s\n\n| 词缀 | 效果 | 稀有度 | 出现几率 |\n| --- | --- | --- | --- |\n" % pair[0]
		out += "| （没有词缀） | — | 不变 | %d%% |\n" % roundi(ItemDB.NO_AFFIX_WEIGHT / total * 100.0)
		for k in table:
			var a: Dictionary = table[k]
			var fx := []
			for key in ["power", "reach", "luck", "damage", "speed", "crit", "knockback"]:
				if a.has(key):
					var v := float(a[key])
					fx.append(("%s %+d 格" % [ItemDB.EFFECT_NAMES[key], int(v)]) if key == "reach" else ("%s %+d%%" % [ItemDB.EFFECT_NAMES[key], roundi(v * 100.0)]))
			var r := int(a.rarity)
			out += "| %s的 | %s | %s | %.1f%% |\n" % [k, "、".join(fx), ("+%d 档" % r) if r > 0 else ("%d 档" % r), float(a.weight) / total * 100.0]
	return out


func _mastery() -> String:
	var out := "| 等级 | 需要的经验 | 挖掘力 / 伤害加成 |\n| --- | --- | --- |\n"
	for i in ItemDB.MASTERY_XP.size():
		out += "| Lv%d | %d | +%d%% |\n" % [i, ItemDB.MASTERY_XP[i], roundi(i * ItemDB.MASTERY_BONUS * 100)]
	return out
