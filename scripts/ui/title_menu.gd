extends Control
## 标题界面：列出已有世界（继续游戏 / 删除），或者创建新世界（名字、种子、大小）。

const MAIN_SCENE := "res://scenes/main.tscn"
const SIZES := [
	["小（1600 × 600）", Vector2i(1600, 600)],
	["中（2800 × 900）", Vector2i(2800, 900)],
	["大（4200 × 1200）", Vector2i(4200, 1200)],
]
const GOLD := Color(1, 0.86, 0.45)
const SOFT := Color(0.75, 0.78, 0.88)

var list_box: VBoxContainer
var name_edit: LineEdit
var seed_edit: LineEdit
var size_option: OptionButton
var status_label: Label
var confirm: ConfirmationDialog
var sky: SkyBackdrop
var panel: PanelContainer
var scroll: ScrollContainer
var _pending_delete := ""


func _ready() -> void:
	GameSession.setup_screen(get_tree())
	get_tree().set_auto_accept_quit(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()

	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	sky = SkyBackdrop.new()
	sky.time_of_day = 0.27
	sky_layer.add_child(sky)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	v.add_child(_label("拓荒者之歌", 44, GOLD, true))
	v.add_child(_label("Pioneer's Ballad · 原创 2D 沙盒冒险", 15, SOFT, true))
	v.add_child(HSeparator.new())

	v.add_child(_label("选择世界", 20, GOLD))
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	v.add_child(HSeparator.new())
	v.add_child(_label("创建新世界", 20, GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	grid.add_child(_label("名字", 16, SOFT))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "给你的世界起个名字"
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t): _create_world())
	grid.add_child(name_edit)
	grid.add_child(_label("种子", 16, SOFT))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "留空 = 随机（填数字或任意文字都行）"
	seed_edit.max_length = 32
	grid.add_child(seed_edit)
	grid.add_child(_label("大小", 16, SOFT))
	size_option = OptionButton.new()
	for s in SIZES:
		size_option.add_item(s[0])
	size_option.select(SIZES.size() - 1)
	grid.add_child(size_option)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	var create := Button.new()
	create.text = "创建并进入"
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(_create_world)
	buttons.add_child(create)
	var full_btn := Button.new()
	full_btn.text = "全屏"
	full_btn.tooltip_text = "也可以按 F11 / Ctrl+Cmd+F 切换"
	full_btn.pressed.connect(GameSession.toggle_fullscreen)
	buttons.add_child(full_btn)
	var quit_btn := Button.new()
	quit_btn.text = "退出游戏"
	quit_btn.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit_btn)

	var moved := SaveSystem.migrate_legacy_saves()
	if moved > 0:
		GameSession.message = ("已经把 %d 个旧世界搬到新的存档位置。" % moved) + ("\n" + GameSession.message if GameSession.message != "" else "")
	status_label = _label(GameSession.message, 14, Color(1, 0.6, 0.45), true)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_label)
	GameSession.message = ""

	confirm = ConfirmationDialog.new()
	confirm.title = "删除世界"
	confirm.ok_button_text = "删除"
	confirm.cancel_button_text = "取消"
	confirm.confirmed.connect(_do_delete)
	add_child(confirm)

	refresh_list()
	get_viewport().size_changed.connect(_fit_to_screen)
	_fit_to_screen()


## 小屏幕：面板变窄、世界列表变矮，保证整个界面放得下
func _fit_to_screen() -> void:
	var vs := get_viewport_rect().size
	panel.custom_minimum_size.x = minf(620.0, vs.x - 32.0)
	scroll.custom_minimum_size.y = clampf(vs.y - 500.0, 90.0, 230.0)


func _input(event: InputEvent) -> void:
	if GameSession.is_fullscreen_key(event):
		GameSession.toggle_fullscreen()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	sky.time_of_day = fposmod(sky.time_of_day + delta / 240.0, 1.0)  # 标题背景慢慢走过一天
	sky.horizon_y = get_viewport_rect().size.y * 0.75


func _make_theme() -> Theme:
	var th := Theme.new()
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(Hud.FONT_NAMES)
	th.default_font = sf
	th.default_font_size = 16
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.12, 0.88)
	bg.border_color = Color(0.45, 0.5, 0.7, 0.6)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(24)
	th.set_stylebox("panel", "PanelContainer", bg)
	var looks := {
		"normal": [Color(0.16, 0.19, 0.32), Color(0.45, 0.5, 0.7, 0.7)],
		"hover": [Color(0.25, 0.3, 0.5), Color(1, 0.86, 0.45, 0.9)],
		"pressed": [Color(0.12, 0.14, 0.24), Color(1, 0.86, 0.45, 0.9)],
		"disabled": [Color(0.12, 0.12, 0.15), Color(0.3, 0.3, 0.35, 0.6)],
		"focus": [Color(0, 0, 0, 0), Color(1, 0.86, 0.45, 0.5)],
	}
	for state in looks:
		var sb := StyleBoxFlat.new()
		sb.bg_color = looks[state][0]
		sb.border_color = looks[state][1]
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		th.set_stylebox(state, "Button", sb)
		if state in ["normal", "hover", "pressed", "disabled"]:
			th.set_stylebox(state, "OptionButton", sb)
	th.set_color("font_hover_color", "Button", Color(1, 0.92, 0.6))
	return th


func _label(text: String, size: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func refresh_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var saves := SaveSystem.list_saves()
	if saves.is_empty():
		list_box.add_child(_label("还没有世界。在下面创建一个吧！", 15, SOFT))
		return
	for s in saves:
		var h: Dictionary = s.header
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var play := Button.new()
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if h.is_empty():
			play.text = "（存档损坏，无法读取）%s" % s.path.get_file()
			play.disabled = true
		else:
			play.text = "%s\n第 %d 天 · %d×%d · 已游玩 %s · 保存于 %s" % [
				h.get("name", "未命名世界"), int(h.get("day", 1)), int(h.width), int(h.height),
				SaveSystem.format_duration(float(h.get("play_time", 0.0))), SaveSystem.format_time(int(h.get("saved_at", 0)))]
			play.pressed.connect(_play_world.bind(s.path))
		row.add_child(play)
		var del := Button.new()
		del.text = "删除"
		del.pressed.connect(_ask_delete.bind(s.path, String(h.get("name", s.path.get_file()))))
		row.add_child(del)
		list_box.add_child(row)


func _play_world(path: String) -> void:
	GameSession.reset()
	GameSession.save_path = path
	GameSession.load_existing = true
	get_tree().change_scene_to_file(MAIN_SCENE)


func _create_world() -> void:
	GameSession.reset()
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "新世界 %d" % (SaveSystem.list_saves().size() + 1)
	GameSession.world_name = n
	GameSession.world_seed = seed_from_text(seed_edit.text)
	GameSession.world_size = SIZES[size_option.selected][1]
	GameSession.save_path = SaveSystem.new_save_path()
	GameSession.load_existing = false
	get_tree().change_scene_to_file(MAIN_SCENE)


## 种子：纯数字就直接用；其他文字取哈希；留空返回 0（= 随机）
static func seed_from_text(t: String) -> int:
	t = t.strip_edges()
	if t == "":
		return 0
	if t.is_valid_int():
		return maxi(1, absi(t.to_int()) % 2000000000)
	return absi(t.hash()) % 2000000000 + 1


func _ask_delete(path: String, display: String) -> void:
	_pending_delete = path
	confirm.dialog_text = "确定要永久删除世界「%s」吗？\n删除后无法恢复。" % display
	confirm.popup_centered()


func _do_delete() -> void:
	if _pending_delete != "":
		SaveSystem.delete_save(_pending_delete)
		_pending_delete = ""
		refresh_list()
