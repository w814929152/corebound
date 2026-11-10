extends CanvasLayer
## 商店和背包共用的只读卡牌详情；不参与鼠标命中。
const Battle := preload("res://scripts/ui/battle_theme.gd")
const Style := preload("res://scripts/ui/ui_style.gd")
const Text := preload("res://scripts/data/card_text.gd")
var panel: PanelContainer
var title: Label
var body: Label
var _key := ""

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
		var floating: StyleBoxFlat = Battle.card(false, Text.rarity(nm))
		floating.bg_color = Color(0, 0, 0, 0)
		panel.add_theme_stylebox_override("panel", floating)
		title.text = Text.display_name(nm)
		var tag := Text.tag_of(nm)
		body.text = "建筑卡 · %s\n\n%s" % [Text.tag_cn(tag), Text.details(nm)]
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
