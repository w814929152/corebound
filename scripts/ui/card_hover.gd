extends CanvasLayer
## 商店和背包共用的只读卡牌详情；不参与鼠标命中。
const Battle := preload("res://scripts/ui/battle_theme.gd")
const Style := preload("res://scripts/ui/ui_style.gd")
const Text := preload("res://scripts/data/card_text.gd")
var panel: PanelContainer
var title: Label
var body: Label
var _key := ""
## 🆕 2026-11-11：卡面精简后，详细文本全部由悬停承担 —— 浮卡是**信息层**，
##   不是装饰，所以默认走深色实心面板（叠在战场 / 主视觉上也读得清）；
##   关卡内若需「仅文字」口径，可 `set_solid(false)`。
var _solid := true


## 菜单 / 图鉴用：实心深色浮卡（带稀有度色条），文字不再加描边。
func set_solid(on: bool) -> void:
	_solid = on
	_key = ""                     # 强制下次 show_card 重刷样式与正文
	if panel != null:
		_apply_panel("")


func _apply_panel(rar: String) -> void:
	if panel == null:             # 节点尚未进树（_ready 未跑）→ 样式由首次 show_card 补上
		return
	var box: StyleBoxFlat
	if _solid:
		box = StyleBoxFlat.new()
		box.bg_color = Color(0.078, 0.090, 0.149, 0.96)
		box.set_corner_radius_all(6)
		# 「少边框」：不画整圈描边，只留左侧 4px 稀有度色条作为卡片身份
		box.border_width_left = 4
		box.border_color = Style.rarity_color(rar) if rar != "" else Style.C_STEEL
	else:
		box = Battle.card(false, rar)
		box.bg_color = Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", box)
	for l: Label in [title, body]:
		l.add_theme_constant_override("outline_size", 0 if _solid else 6)
		l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))

func _ready() -> void:
	layer = 136
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 🆕 v4 统一关卡内风格：浮卡底块取消（纯文字）。可读性改由**深色文字描边**承担——
	#    描边只作用于字形周围，不产生任何面板块，与「仅文字」方向一致。
	var floating: StyleBoxFlat = Battle.panel()
	floating.bg_color = Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", floating)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)
	title = Style.label("", 24, Style.C_ALLY)
	title.custom_minimum_size.x = 284.0
	title.size.x = 284.0
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)
	body = Style.label("", 18, Style.C_TEXT)
	body.custom_minimum_size.x = 284.0
	body.size.x = 284.0
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(body)
	# 🆕 v4：深色描边保证文字压在战场/插画上仍可读（无底块的替代方案）
	for l: Label in [title, body]:
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.9))
	_apply_panel("")               # 默认实心面板（见 `_solid` 注释）
	panel.hide()

func clear() -> void:
	panel.hide()
	_key = ""

func show_card(nm: String, anchor: Rect2, context: String = "", above: bool = false, below: bool = false) -> void:
	if nm == "":
		clear()
		return
	var key := nm + context
	if key != _key:
		_key = key
		var rar := Text.rarity(nm)
		_apply_panel(rar)
		title.text = Text.display_name(nm)
		var tag := Text.tag_of(nm)
		# 🆕 2026-11-11：卡面只剩卡名 + 类型，完整机制与数值搬到这里。
		#    `describe()` 是卡面口径的 3 行（机制 / 数值 / 标记），`details()` 是补充说明；
		#    两张口径逐字相同的卡（如 Arrow）不重复渲染。
		var summary := Text.describe(nm)
		var detail := Text.details(nm)
		var tag_cn := "常规" if tag == "" else Text.tag_cn(tag)
		body.text = "建筑卡 · %s\n\n%s" % [tag_cn, summary]
		if detail != summary:
			body.text += "\n\n" + detail
		if context != "":
			body.text += "\n\n" + context
		panel.reset_size()
	panel.reset_size()
	panel.show()
	var vs := get_viewport().get_visible_rect().size
	var point := Vector2(anchor.position.x - panel.size.x - 14.0, anchor.position.y)
	if below:
		point = Vector2(anchor.get_center().x - panel.size.x * 0.5, anchor.end.y + 14.0)
	elif above:
		point = Vector2(anchor.position.x, anchor.position.y - panel.size.y - 14.0)
	elif point.x < 12.0:
		point.x = anchor.end.x + 14.0
	panel.position = Vector2(clampf(point.x, 12.0, maxf(12.0, vs.x - panel.size.x - 12.0)), clampf(point.y, 12.0, maxf(12.0, vs.y - panel.size.y - 12.0)))
