class_name Hud
extends Control
## 游戏界面：快捷栏、背包、饰品栏、制作栏、悬停提示、生命条、增益、消息。
## 整个界面都用 _draw() 自己画，点击用矩形判定，这样不需要做一堆场景文件，也方便以后换皮。

const SLOT := 44.0
const GAP := 4.0
const ORIGIN := Vector2(16, 16)
const RECIPE_SIZE := 38.0
const RECIPE_STEP := RECIPE_SIZE + 4.0
const MAX_RECIPE_COLS := 15
const STATUS_WIDTH := 220.0      ## 右上角状态区的宽度
const MESSAGE_TIME := 4.0
const FONT_NAMES := ["PingFang SC", "Hiragino Sans GB", "Heiti SC", "Noto Sans CJK SC", "Source Han Sans SC", "Microsoft YaHei", "WenQuanYi Micro Hei"]

var game: Node = null
var font: Font
var loading_text := ""
var inventory_open := false
var menu_open := false
var cursor_item: Variant = null
var messages: Array = []    ## [{"text", "color", "time", "key", "count"}]

var _hint_cool := 0.0
var _banner_text := ""
var _banner_color := Color.WHITE
var _banner_t := 0.0
var _tip: Array = []
var _stations := {}
var _station_timer := 0.0
var craft_scroll := 0          ## 制作栏往下翻了几行


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(FONT_NAMES)
	font = sf


func setup(g: Node) -> void:
	game = g


func _process(delta: float) -> void:
	_hint_cool = maxf(0.0, _hint_cool - delta)
	_banner_t = maxf(0.0, _banner_t - delta)
	for m in messages:
		m.time -= delta
	messages = messages.filter(func(m): return m.time > 0.0)
	_station_timer -= delta
	if game != null and game.ready_done and inventory_open and _station_timer <= 0.0:
		_stations = game.stations_nearby()
		_station_timer = 0.25
	queue_redraw()


# ---------------------------------------------------------------- 消息

func notify(text: String, color: Color = Color.WHITE) -> void:
	messages.append({"text": text, "color": color, "time": MESSAGE_TIME, "key": "", "count": 0})
	if messages.size() > 8:
		messages.pop_front()


func notify_item(inst: Dictionary, count: int) -> void:
	var key := ItemDB.display_name(inst)
	for m in messages:
		if m.key == key and m.time > 1.0:
			m.count += count
			m.text = "+%d %s" % [m.count, key]
			m.time = MESSAGE_TIME
			return
	notify("+%d %s" % [count, key], ItemDB.rarity_color(inst))
	messages[messages.size() - 1].key = key
	messages[messages.size() - 1].count = count


## 屏幕中间的大字公告（Boss 出现、击败 Boss……），同时也记进消息列表
func banner(text: String, color: Color) -> void:
	_banner_text = text
	_banner_color = color
	_banner_t = 3.5
	notify(text, color)


## 有冷却的提示，避免按住鼠标时刷屏
func hint(text: String) -> void:
	if _hint_cool > 0.0:
		return
	_hint_cool = 1.5
	notify(text, Color(1, 0.75, 0.45))


# ---------------------------------------------------------------- 布局

func slot_rect(i: int) -> Rect2:
	var row := i / Inventory.HOTBAR_SIZE
	var col := i % Inventory.HOTBAR_SIZE
	return Rect2(ORIGIN + Vector2(col * (SLOT + GAP), row * (SLOT + GAP) + (10.0 if row > 0 else 0.0)), Vector2(SLOT, SLOT))


func acc_rect(j: int) -> Rect2:
	return Rect2(ORIGIN + Vector2(Inventory.HOTBAR_SIZE * (SLOT + GAP) + 16.0, 10.0 + (j + 1) * (SLOT + GAP)), Vector2(SLOT, SLOT))


## 制作栏的布局会跟着屏幕大小变：
##   屏幕够宽 → 放在背包右边；不够宽 → 放在背包下面。
##   能放几列就放几列，能放几行就放几行，放不下的用鼠标滚轮翻页。
func craft_layout(vs: Vector2 = Vector2.ZERO) -> Dictionary:
	if vs == Vector2.ZERO:
		vs = get_viewport_rect().size
	var total := ItemDB.recipes().size()
	var inv_right := acc_rect(0).end.x + 10.0
	var side_x := inv_right + 20.0
	# 右上角是生命/法力/时间（宽 STATUS_WIDTH），制作栏不能盖住它
	var side_cols := int((vs.x - STATUS_WIDTH - 40.0 - side_x - 26.0) / RECIPE_STEP)
	var origin: Vector2
	var cols: int
	var side := side_cols >= 8
	if side:
		origin = Vector2(side_x + 10.0, ORIGIN.y + 30.0)
		cols = mini(side_cols, MAX_RECIPE_COLS)
	else:
		origin = ORIGIN + Vector2(0, 5 * (SLOT + GAP) + 44.0)
		cols = clampi(int((vs.x - 2.0 * ORIGIN.x - 10.0) / RECIPE_STEP), 4, MAX_RECIPE_COLS)
	var total_rows := ceili(float(total) / cols)
	# 底下要留出重铸按钮、提示文字和消息的位置
	var room_rows := int((vs.y - origin.y - 110.0) / RECIPE_STEP)
	var rows := clampi(room_rows, 2, total_rows)
	var max_scroll := maxi(0, total_rows - rows)
	return {"origin": origin, "cols": cols, "rows": rows, "total_rows": total_rows, "max_scroll": max_scroll, "side": side}


func craft_origin() -> Vector2:
	return craft_layout().origin


## 第 k 个配方的格子；翻页后不在屏幕上的返回空矩形
func recipe_rect(k: int, lay: Dictionary = {}) -> Rect2:
	if lay.is_empty():
		lay = craft_layout()
	var cols: int = lay.cols
	var row := k / cols - mini(craft_scroll, lay.max_scroll)
	if row < 0 or row >= int(lay.rows):
		return Rect2()
	return Rect2(Vector2(lay.origin) + Vector2((k % cols) * RECIPE_STEP, row * RECIPE_STEP), Vector2(RECIPE_SIZE, RECIPE_SIZE))


func reforge_rect(lay: Dictionary = {}) -> Rect2:
	if lay.is_empty():
		lay = craft_layout()
	return Rect2(Vector2(lay.origin) + Vector2(0, int(lay.rows) * RECIPE_STEP + 8.0), Vector2(250, 30))


func craft_panel_rect(lay: Dictionary = {}) -> Rect2:
	if lay.is_empty():
		lay = craft_layout()
	var c0 := Vector2(lay.origin) - Vector2(10, 30)
	var r := reforge_rect(lay)
	var w := maxf(int(lay.cols) * RECIPE_STEP + 16.0, 270.0)
	return Rect2(c0, Vector2(w, r.end.y + 26.0 - c0.y))


func scroll_crafting(delta_rows: int) -> void:
	craft_scroll = clampi(craft_scroll + delta_rows, 0, int(craft_layout().max_scroll))


func _panel_rects() -> Array:
	var rects := [Rect2(ORIGIN - Vector2(6, 6), Vector2(Inventory.HOTBAR_SIZE * (SLOT + GAP) + 8, SLOT + 12))]
	if inventory_open:
		var a := slot_rect(0).position - Vector2(10, 10)
		var b := Vector2(acc_rect(0).end.x, slot_rect(Inventory.SIZE - 1).end.y) + Vector2(10, 10)
		rects.append(Rect2(a, b - a))
		rects.append(craft_panel_rect())
	return rects


## 鼠标是否在界面上（在界面上点击就不挖地）
func blocks_mouse() -> bool:
	if menu_open:
		return true
	if inventory_open and cursor_item != null:
		return true
	var m := get_viewport().get_mouse_position()
	for r in _panel_rects():
		if r.has_point(m):
			return true
	return false


# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if GameSession.is_fullscreen_key(event):
		GameSession.toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if game == null or not game.ready_done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_ESCAPE:
			if inventory_open:
				toggle_inventory()
			else:
				menu_open = not menu_open
			get_viewport().set_input_as_handled()
		elif menu_open:
			return
		elif k >= KEY_1 and k <= KEY_9:
			game.inventory.selected = k - KEY_1
		elif k == KEY_0:
			game.inventory.selected = 9
		elif k == KEY_Q:
			game.drop_selected(event.shift_pressed)   # Q 丢 1 个，Shift+Q 丢整堆
		elif k == KEY_E or k == KEY_TAB or k == KEY_I:
			toggle_inventory()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if menu_open:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_click_menu(mb.position)
			get_viewport().set_input_as_handled()
			return
		var wheel := mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if wheel and inventory_open and craft_panel_rect().has_point(mb.position):
			scroll_crafting(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)   # 滚轮翻制作栏
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.inventory.selected = posmod(game.inventory.selected - 1, Inventory.HOTBAR_SIZE)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.inventory.selected = posmod(game.inventory.selected + 1, Inventory.HOTBAR_SIZE)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if _click(mb.position, mb.button_index == MOUSE_BUTTON_RIGHT):
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				# 在世界里右键：把选中的东西丢出去（Shift+右键丢整堆）
				game.drop_selected(mb.shift_pressed)
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 暂停菜单

const MENU_BUTTONS := [
	["resume", "继续游戏"],
	["save", "保存游戏"],
	["title", "保存并回到标题界面"],
	["quit", "保存并退出游戏"],
]


func menu_button_rect(i: int) -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(vs.x * 0.5 - 150.0, vs.y * 0.5 - 70.0 + i * 52.0, 300.0, 42.0)


func _click_menu(pos: Vector2) -> void:
	for i in MENU_BUTTONS.size():
		if menu_button_rect(i).has_point(pos):
			match MENU_BUTTONS[i][0]:
				"resume":
					menu_open = false
				"save":
					if game.save_game(false):
						menu_open = false
					elif game.save_path == "":
						notify("这个世界没有存档文件（测试模式）。", Color(1, 0.75, 0.45))
				"title":
					game.return_to_title()
				"quit":
					game.save_and_quit()
			return


func _draw_menu(vs: Vector2, m: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var top := menu_button_rect(0).position - Vector2(30, 90)
	var bottom := menu_button_rect(MENU_BUTTONS.size() - 1).end + Vector2(30, 46)
	_panel(Rect2(top, bottom - top), 0.95)
	_text(top + Vector2(30, 44), "游戏暂停", 26, Color(1, 0.88, 0.5))
	_text(top + Vector2(30, 70), "世界：%s · 已游玩 %s" % [game.world_name, SaveSystem.format_duration(game.play_time)], 13, Color(0.75, 0.78, 0.88))
	var beaten := []
	for bid in game.bosses:
		beaten.append(String(EnemyDB.get_def(bid).get("name", bid)))
	if not beaten.is_empty():
		_text(top + Vector2(30, 86), "已击败：" + "、".join(beaten), 12, Color(1, 0.8, 0.35))
	for i in MENU_BUTTONS.size():
		var r := menu_button_rect(i)
		var hover := r.has_point(m)
		draw_rect(r, Color(0.25, 0.3, 0.5, 0.95) if hover else Color(0.14, 0.16, 0.26, 0.95))
		draw_rect(r, Color(1, 0.88, 0.5, 0.9) if hover else Color(0.45, 0.5, 0.7, 0.7), false, 1.5)
		var label: String = MENU_BUTTONS[i][1]
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		_text(Vector2(r.position.x + (r.size.x - tw) * 0.5, r.position.y + 28.0), label, 17)
	_text(Vector2(top.x + 30, bottom.y - 16), "每 5 分钟自动保存，关闭窗口时也会自动保存。", 12, Color(0.65, 0.68, 0.78))


func toggle_inventory() -> void:
	if inventory_open and cursor_item != null:
		var left: int = game.inventory.add_instance(cursor_item)
		if left > 0:
			cursor_item.count = left
			hint("背包满了，先把手上的东西放下。")
			return
		cursor_item = null
	inventory_open = not inventory_open
	_station_timer = 0.0
	game.recalc_stats()


func _click(pos: Vector2, right: bool) -> bool:
	var inv: Inventory = game.inventory
	var shown := Inventory.SIZE if inventory_open else Inventory.HOTBAR_SIZE
	for i in shown:
		if slot_rect(i).has_point(pos):
			if not inventory_open:
				inv.selected = i
			elif right:
				_quick_equip(i)
			else:
				_swap_with_cursor(inv.slots, i, false)
			return true
	if not inventory_open:
		return false
	for j in Inventory.ACCESSORY_SIZE:
		if acc_rect(j).has_point(pos):
			_swap_with_cursor(inv.accessories, j, true)
			return true
	var recipes := ItemDB.recipes()
	var lay := craft_layout()
	for k in recipes.size():
		if recipe_rect(k, lay).has_point(pos):
			game.craft(recipes[k])
			return true
	if reforge_rect(lay).has_point(pos):
		game.reforge_selected()
		return true
	for r in _panel_rects():
		if r.has_point(pos):
			return true
	if cursor_item != null and not right:
		# 拿着东西点背包外面：扔出去
		game.throw_instance(cursor_item)
		cursor_item = null
		return true
	return false


func _swap_with_cursor(arr: Array, i: int, accessory_slot: bool) -> void:
	var s: Variant = arr[i]
	if cursor_item == null:
		if s != null:
			cursor_item = s
			arr[i] = null
	else:
		if accessory_slot:
			if ItemDB.category(cursor_item.id) != "accessory":
				hint("饰品栏只能放饰品。")
				return
			if game.inventory.has_accessory(cursor_item.id) and (s == null or s.id != cursor_item.id):
				hint("同一种饰品只能戴一个。")
				return
		if s != null and ItemDB.can_stack(s, cursor_item):
			var mv := mini(ItemDB.max_stack(s.id) - int(s.count), int(cursor_item.count))
			s.count += mv
			cursor_item.count -= mv
			if cursor_item.count <= 0:
				cursor_item = null
		else:
			arr[i] = cursor_item
			cursor_item = s
	game.inventory.changed.emit()
	game.recalc_stats()


## 右键背包里的饰品：直接戴上（或和第一格交换）
func _quick_equip(i: int) -> void:
	var inv: Inventory = game.inventory
	var s: Variant = inv.slots[i]
	if s == null or ItemDB.category(s.id) != "accessory":
		return
	if inv.has_accessory(s.id):
		hint("同一种饰品只能戴一个。")
		return
	var target := inv.accessories.find(null)
	if target == -1:
		target = 0
	var old: Variant = inv.accessories[target]
	inv.accessories[target] = s
	inv.slots[i] = old
	notify("装备了 %s" % ItemDB.display_name(s), ItemDB.rarity_color(s))
	game.recalc_stats()


# ---------------------------------------------------------------- 绘制

func _text(pos: Vector2, s: String, size: int = 14, color: Color = Color.WHITE) -> void:
	draw_string(font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.75 * color.a))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _panel(r: Rect2, alpha: float = 0.72) -> void:
	draw_rect(r, Color(0.06, 0.07, 0.12, alpha))
	draw_rect(r, Color(0.45, 0.5, 0.7, 0.5), false, 1.0)


func _draw_slot(r: Rect2, inst: Variant, selected: bool, dim: bool = false) -> void:
	var bg := Color(0.12, 0.14, 0.22, 0.85) if not dim else Color(0.08, 0.08, 0.1, 0.8)
	draw_rect(r, bg)
	var border := Color(0.4, 0.45, 0.6, 0.8)
	if inst != null:
		border = ItemDB.rarity_color(inst).darkened(0.25)
	if selected:
		border = Color(1, 0.88, 0.35)
	draw_rect(r, border, false, 3.0 if selected else 1.5)
	if inst == null:
		return
	var icon := TileArt.icon(inst.id)
	var ir := r.grow(-8.0)
	draw_texture_rect(icon, ir, false, Color(1, 1, 1, 0.45) if dim else Color.WHITE)
	if int(inst.count) > 1:
		var s := str(inst.count)
		_text(r.position + Vector2(r.size.x - 8.0 * s.length() - 4.0, r.size.y - 4.0), s, 13)
	if ItemDB.has_affix_slot(inst):
		var lvl := ItemDB.mastery_level(inst)
		if lvl > 0:
			_text(r.position + Vector2(3, 13), "★%d" % lvl, 11, ItemDB.RARITY_COLORS[4])


func _draw() -> void:
	var vs := get_viewport_rect().size
	if loading_text != "":
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.03, 0.06))
		_text(vs * 0.5 - Vector2(160, 0), loading_text, 22)
		return
	if game == null or not game.ready_done:
		return
	var inv: Inventory = game.inventory
	var m := get_viewport().get_mouse_position()
	_tip = []

	# 快捷栏
	_panel(_panel_rects()[0])
	for i in Inventory.HOTBAR_SIZE:
		var r := slot_rect(i)
		_draw_slot(r, inv.slots[i], i == inv.selected)
		_text(r.position + Vector2(3, 12), str((i + 1) % 10), 10, Color(1, 1, 1, 0.6))
		if r.has_point(m):
			_tip = ItemDB.tooltip(inv.slots[i])
	var sel: Variant = inv.selected_item()
	if sel != null and not inventory_open:
		_text(ORIGIN + Vector2(0, SLOT + 26), ItemDB.display_name(sel), 15, ItemDB.rarity_color(sel))

	if inventory_open:
		_draw_inventory(inv, m)

	_draw_status(vs)
	_draw_messages(vs)
	_draw_boss_bar(vs)
	_draw_breath()
	if _banner_t > 0.0:
		var c := _banner_color
		c.a = clampf(_banner_t, 0.0, 1.0)
		var tw := font.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_text(Vector2((vs.x - tw) * 0.5, vs.y * 0.28), _banner_text, 30, c)

	if menu_open:
		_draw_menu(vs, m)
		return
	if not _tip.is_empty() and cursor_item == null:
		_draw_tooltip(m, _tip)
	if cursor_item != null:
		var r := Rect2(m - Vector2(14, 14), Vector2(28, 28))
		draw_texture_rect(TileArt.icon(cursor_item.id), r, false)
		if int(cursor_item.count) > 1:
			_text(m + Vector2(8, 18), str(cursor_item.count), 13)


func _draw_inventory(inv: Inventory, m: Vector2) -> void:
	var rects := _panel_rects()
	_panel(rects[1])
	for i in range(Inventory.HOTBAR_SIZE, Inventory.SIZE):
		var r := slot_rect(i)
		_draw_slot(r, inv.slots[i], false)
		if r.has_point(m):
			_tip = ItemDB.tooltip(inv.slots[i])
	_text(acc_rect(0).position + Vector2(0, -8), "饰品", 13, Color(0.75, 0.8, 1))
	for j in Inventory.ACCESSORY_SIZE:
		var r := acc_rect(j)
		_draw_slot(r, inv.accessories[j], false)
		if inv.accessories[j] == null:
			_text(r.position + Vector2(14, 28), "✦", 16, Color(1, 1, 1, 0.15))
		if r.has_point(m):
			_tip = ItemDB.tooltip(inv.accessories[j])

	# 制作栏
	_panel(rects[2])
	var names := []
	for st in ["workbench", "furnace", "anvil"]:
		if _stations.has(st):
			names.append(ItemDB.STATION_NAMES[st])
	var lay := craft_layout()
	craft_scroll = mini(craft_scroll, int(lay.max_scroll))
	var co: Vector2 = lay.origin
	_text(co + Vector2(0, -12), "制作 · 制作站：%s" % ("、".join(names) if not names.is_empty() else "徒手"), 14, Color(1, 0.9, 0.6))
	if int(lay.max_scroll) > 0:
		var page := "滚轮翻页  %d/%d 行" % [craft_scroll + int(lay.rows), int(lay.total_rows)]
		var pw := font.get_string_size(page, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text(co + Vector2(int(lay.cols) * RECIPE_STEP - pw - 4.0, -12), page, 12, Color(0.75, 0.8, 1))
		if craft_scroll > 0:
			_text(co + Vector2(int(lay.cols) * RECIPE_STEP * 0.5 - 4.0, -1), "▲", 10, Color(1, 1, 1, 0.6))
		if craft_scroll < int(lay.max_scroll):
			_text(co + Vector2(int(lay.cols) * RECIPE_STEP * 0.5 - 4.0, int(lay.rows) * RECIPE_STEP + 2.0), "▼", 10, Color(1, 1, 1, 0.6))
	var recipes := ItemDB.recipes()
	for k in recipes.size():
		var rc: Dictionary = recipes[k]
		var r := recipe_rect(k, lay)
		if r.size == Vector2.ZERO:
			continue
		var has_station := _stations.has(rc.station)
		var ok: bool = has_station and game.has_ingredients(rc)
		var preview := ItemDB.make(rc.result, int(rc.count))
		_draw_slot(r, preview, false, not ok)
		if not has_station:
			draw_rect(r, Color(0, 0, 0, 0.35))
		elif ok:
			draw_rect(r.grow(-1), Color(0.5, 1, 0.5, 0.6), false, 1.0)
		if r.has_point(m):
			_tip = _recipe_tip(rc, has_station)
	var rr := reforge_rect(lay)
	var sel: Variant = inv.selected_item()
	var can := _stations.has("anvil") and ItemDB.has_affix_slot(sel)
	draw_rect(rr, Color(0.3, 0.2, 0.45, 0.9) if can else Color(0.15, 0.15, 0.2, 0.8))
	draw_rect(rr, Color(0.8, 0.6, 1, 0.8) if can else Color(0.4, 0.4, 0.5, 0.6), false, 1.0)
	_text(rr.position + Vector2(10, 21), "重铸选中工具/武器的词缀（2 灵晶碎片）", 13, Color.WHITE if can else Color(0.6, 0.6, 0.65))
	if rr.has_point(m):
		_tip = [["重铸", Color(0.8, 0.6, 1)], ["站在铁砧旁，花 2 个灵晶碎片给快捷栏选中的工具或武器重新随机一个词缀。", Color(0.85, 0.85, 0.9)]]
		if sel != null and ItemDB.has_affix_slot(sel):
			_tip.append(["当前：" + ItemDB.display_name(sel), ItemDB.rarity_color(sel)])
	_text(rr.position + Vector2(0, 44), "左键拿起/放下 · 拿着东西点外面可丢出 · 右键饰品直接装备", 12, Color(0.7, 0.72, 0.8))


func _recipe_tip(rc: Dictionary, has_station: bool) -> Array:
	var lines := ItemDB.tooltip(ItemDB.make(rc.result, int(rc.count)))
	if int(rc.count) > 1:
		lines[0] = [lines[0][0] + " ×%d" % int(rc.count), lines[0][1]]
	lines.append(["—— 所需材料 ——", Color(1, 0.9, 0.6)])
	for id in rc.ingredients:
		var have: int = game.inventory.count_of(id)
		var need := int(rc.ingredients[id])
		lines.append(["%s  %d/%d" % [ItemDB.get_def(id).name, have, need], Color(0.55, 0.95, 0.6) if have >= need else Color(1, 0.45, 0.4)])
	lines.append(["制作站：%s%s" % [ItemDB.STATION_NAMES[rc.station], "" if has_station else "（不在附近）"], Color(0.8, 0.8, 0.85) if has_station else Color(1, 0.45, 0.4)])
	if ItemDB.category(rc.result) == "tool":
		lines.append(["制作出的工具会随机带上词缀！", Color(0.8, 0.6, 1)])
	return lines


func _draw_status(vs: Vector2) -> void:
	var p: Player = game.player
	var w := STATUS_WIDTH
	var x := vs.x - w - 16.0
	var r := Rect2(x, 16, w, 18)
	draw_rect(r, Color(0.15, 0.05, 0.07, 0.8))
	draw_rect(Rect2(r.position, Vector2(w * clampf(p.hp / p.max_hp, 0, 1), 18)), Color(0.85, 0.2, 0.25))
	draw_rect(r, Color(1, 1, 1, 0.4), false, 1.0)
	_text(r.position + Vector2(6, 14), "生命 %d / %d" % [ceili(p.hp), p.max_hp], 13)
	var mr := Rect2(x, 38, w, 12)
	draw_rect(mr, Color(0.05, 0.07, 0.18, 0.8))
	draw_rect(Rect2(mr.position, Vector2(w * clampf(p.mana / p.max_mana, 0, 1), 12)), Color(0.3, 0.5, 1.0))
	draw_rect(mr, Color(1, 1, 1, 0.35), false, 1.0)
	_text(mr.position + Vector2(6, 10), "法力 %d / %d" % [floori(p.mana), p.max_mana], 10)
	var defense := int(game.stats.get("defense", 0.0))
	if defense > 0:
		_text(Vector2(x - 70, 30), "防御 %d" % defense, 13, Color(0.8, 0.85, 1))
	var hours: float = game.time_of_day * 24.0
	var ty := int(p.center().y / 16.0)
	var depth_m: int = (int(game.world.layers.surface) - ty) / 2
	var depth_txt := ("海拔 %d 米" % depth_m) if depth_m >= 0 else ("深度 %d 米" % -depth_m)
	_text(Vector2(x, 70), "第 %d 天  %02d:%02d" % [game.day, int(hours), int(fmod(hours, 1.0) * 60.0)], 14)
	var tx := int(p.center().x / 16.0)
	var biome := String(WorldData.BIOME_NAMES.get(game.world.biome_at(tx, ty), ""))
	var layer: String = game.world.layer_name(ty)
	var where: String = layer if biome == "" or biome == layer else "%s · %s" % [biome, layer]
	_text(Vector2(x, 90), "%s · %s" % [where, depth_txt], 14, Color(0.8, 0.85, 1))
	var y := 114.0
	for buff_name in game.buffs:
		var b: Dictionary = game.buffs[buff_name]
		var debuff := bool(b.get("debuff", false))
		_text(Vector2(x, y), ("✖ %s  %d 秒" if debuff else "✧ %s  %d 秒") % [buff_name, ceili(b.time)], 13, Color(1, 0.5, 0.45) if debuff else Color(0.6, 0.9, 1))
		y += 18.0
	_text(Vector2(16, vs.y - 14), "A/D 移动 · 空格 跳 · 左键 挖/放/用/攻击 · 右键/Q 丢出 · 1-0/滚轮 选格 · E 背包 · Esc 菜单 · F11 全屏", 12, Color(1, 1, 1, 0.5))
	_text(Vector2(vs.x - 90, vs.y - 14), "FPS %d" % Engine.get_frames_per_second(), 12, Color(1, 1, 1, 0.4))


## 在水下憋气时，玩家头顶显示一排气泡
func _draw_breath() -> void:
	var mx: float = game.max_breath()
	if game.breath >= mx or game.dead:
		return
	var p: Player = game.player
	var head := p.get_global_transform_with_canvas() * Vector2(Player.W * 0.5, -10.0)
	var n := 10
	var left := ceili(game.breath / mx * n)
	for i in n:
		var pos := head + Vector2((i - (n - 1) * 0.5) * 11.0, 0)
		if i < left:
			draw_circle(pos, 4.5, Color(0.6, 0.85, 1.0, 0.9))
			draw_circle(pos + Vector2(-1.5, -1.5), 1.2, Color.WHITE)
		else:
			draw_arc(pos, 4.5, 0, TAU, 12, Color(0.6, 0.85, 1.0, 0.35), 1.0)


func _draw_boss_bar(vs: Vector2) -> void:
	var b: Variant = game.combat.boss
	if b == null or not is_instance_valid(b) or b.hp <= 0.0:
		return
	var w := 480.0
	var r := Rect2((vs.x - w) * 0.5, vs.y - 64.0, w, 16.0)
	_panel(r.grow(6.0), 0.8)
	draw_rect(r, Color(0.2, 0.05, 0.06))
	var k := clampf(b.hp / b.max_hp, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(w * k, r.size.y)), Color(0.85, 0.2, 0.25) if b.phase == 1 else Color(0.95, 0.35, 0.1))
	draw_line(r.position + Vector2(w * 0.5, 0), r.position + Vector2(w * 0.5, r.size.y), Color(1, 1, 1, 0.5), 1.0)
	draw_rect(r, Color(1, 0.85, 0.5, 0.8), false, 1.0)
	var label := "%s  %d / %d%s" % [b.def.name, ceili(b.hp), int(b.max_hp), "  · 二阶段" if b.phase == 2 else ""]
	_text(r.position + Vector2(8, 13), label, 13)
	if not b.visible:
		_text(r.position + Vector2(w - 90, 13), "（钻进了地里）", 12, Color(0.9, 0.8, 0.6))


func _draw_messages(vs: Vector2) -> void:
	var y := vs.y - 40.0
	for i in range(messages.size() - 1, -1, -1):
		var msg: Dictionary = messages[i]
		var c: Color = msg.color
		c.a = clampf(msg.time, 0.0, 1.0)
		_text(Vector2(16, y), msg.text, 15, c)
		y -= 22.0


func _draw_tooltip(m: Vector2, lines: Array) -> void:
	if lines.is_empty():
		return
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var h := lines.size() * 19.0 + 10.0
	var pos := m + Vector2(18, 18)
	var vs := get_viewport_rect().size
	pos.x = minf(pos.x, vs.x - w - 24.0)
	pos.y = minf(pos.y, vs.y - h - 8.0)
	_panel(Rect2(pos, Vector2(w + 16.0, h)), 0.92)
	var y := pos.y + 20.0
	for i in lines.size():
		_text(Vector2(pos.x + 8, y), String(lines[i][0]), 15 if i == 0 else 14, lines[i][1])
		y += 19.0
