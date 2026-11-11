extends RefCounted
## 图鉴卡面（v3.2 规格的只读版）：210×340 竖版卡，与商店商品位同一套卡框贴图与字阶。
##
## 与 `shop_overlay._make_slot()` 的关系：
##   · 共用 `art/2d/ui/ui_card_plate_v3.png` / `ui_card_edge_v3_{1,2,3}.png` /
##     `ui_card_badge_v3.png` 与同一组字号（卡名 28 / 类型 14 / 摘要 14×2）；
##   · 这里**不接玩家状态**：没有价格胶囊、锁头、悬停、购买与稀有度描边动画 ——
##     图鉴是"看这张卡长什么样"，不是"买不买得起"。
##   · 右上角空出来的费用位改放稀有度 ▲（图鉴里价格无意义），描边色仍走 `rarity_color()`。
##
## 规格来源：`design/art/card-redesign-2026-11-11.md` §11（v3.2）。

const Style := preload("res://scripts/ui/ui_style.gd")
const CardText := preload("res://scripts/data/card_text.gd")

const SIZE := Vector2(210.0, 340.0)
const FRAME_DIR := "res://art/2d/ui/"
const DESC_LINES := 2

## 与 shop_overlay 同值（信息区米白 / 卡名近黑 / 摘要柔黑）。
const C_CREAM := Color(0.980, 0.933, 0.882, 1.0)
const C_BLACK := Color(0.063, 0.075, 0.102, 1.0)
const C_DESC := Color(0.157, 0.176, 0.216, 1.0)


## 生成一张图鉴卡面。返回值带 `desc_label` meta（图鉴断言用它检查说明非空）。
static func build(nm: String) -> Control:
	var root := Control.new()
	root.custom_minimum_size = SIZE
	root.size = SIZE
	root.clip_contents = true
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rar := CardText.rarity(nm)

	# ---- 1. 插画区（8,8,194,220）：全幅竖版插画铺满，方形旧插画叠包背景 ----
	var holder := Control.new()
	holder.position = Vector2(8.0, 8.0)
	holder.size = Vector2(194.0, 220.0)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)

	var art_tex := Style.card_art(nm)
	var full_illustration := Style.is_full_card_art(art_tex)
	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if full_illustration:
		backdrop.texture = art_tex
		backdrop.self_modulate = Color.WHITE
	else:
		backdrop.texture = Style.card_backdrop(rar, nm)
		backdrop.self_modulate = Style.CARD_BACKDROP_TINT
	holder.add_child(backdrop)

	if not full_illustration and art_tex != null:
		var art := TextureRect.new()
		art.texture = art_tex
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(art)

	# ---- 2. 框体：底板 → 稀有度描边（颜色 + 线宽双通道）→ 类型条 ----
	_picture(root, "ui_card_plate_v3.png", 0.0, 0.0, 210.0, 340.0)
	var row: Dictionary = Style.RARITY.get(rar, Style.RARITY["common"])
	var edge := _picture(root, "ui_card_edge_v3_%d.png" % clampi(int(row.get("bw", 2)), 1, 3),
		0.0, 0.0, 210.0, 340.0)
	edge.modulate = Style.rarity_color(rar)
	_picture(root, "ui_card_badge_v3.png", 8.0, 268.0, 194.0, 20.0)

	# ---- 3. 右上：图鉴没有价格，改放稀有度 ▲（描边保证压在插画上也读得出）----
	var pips := Style.label("▲".repeat(Style.rarity_pips(rar)), 14, Style.rarity_color(rar))
	pips.position = Vector2(112.0, 12.0)
	pips.size = Vector2(84.0, 20.0)
	pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pips.add_theme_constant_override("outline_size", 5)
	pips.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.85))
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pips)

	# ---- 4. 信息区：卡名 28 / 类型 14 / 摘要 14×2（→ 悬停/商店看完整 3 行）----
	_label(root, CardText.display_name(nm), 28, C_BLACK, 12.0, 229.0, 186.0, 36.0, "display")
	var tag := CardText.tag_of(nm)
	# 类型条文案与商店卡面逐字同口径（`shop_overlay` L747–749）：有 Tag 用「建筑 · 火」，
	# 通用卡用「建筑 · 常规」；图鉴没有购买语境，所以不写价格、也不写"种别"。
	var tag_txt := "建筑 · 常规" if tag == "" else "建筑 · %s" % CardText.tag_cn(tag)
	var tag_l := _label(root, tag_txt, 14, C_CREAM, 12.0, 265.0, 186.0, 20.0, "medium")
	# 标记卡面小字（类型 / 摘要）：与商店卡面同一例外，供字号断言识别（§9.1 唯一豁免）。
	tag_l.set_meta("card_face_small", true)
	var lines: PackedStringArray = CardText.describe(nm).split("\n")
	var shown := "\n".join(lines.slice(0, mini(DESC_LINES, lines.size())))
	var desc := _label(root, shown, 14, C_DESC, 12.0, 286.0, 186.0, 42.0, "body")
	desc.add_theme_constant_override("line_spacing", -4)
	desc.set_meta("card_face_small", true)
	root.set_meta("desc_label", desc)
	return root


static func _picture(parent: Control, file: String, x: float, y: float, w: float, h: float) -> TextureRect:
	var t := TextureRect.new()
	t.position = Vector2(x, y)
	t.size = Vector2(w, h)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := FRAME_DIR + file
	if ResourceLoader.exists(path):
		t.texture = load(path)
	parent.add_child(t)
	return t


static func _label(parent: Control, text: String, size: int, col: Color,
		x: float, y: float, w: float, h: float, variant: String) -> Label:
	var l := Style.label(text, size, col)
	# 🔴 卡面字号例外：类型 / 摘要 14px、费用 22–24px 属印刷面口径，
	#    不被 `Style.label()` 的 FONT_MIN(16) 抬升（与 shop_overlay 同一处置）。
	if size < Style.FONT_MIN:
		l.add_theme_font_size_override("font_size", size)
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.apply_font(l, variant)
	parent.add_child(l)
	return l
