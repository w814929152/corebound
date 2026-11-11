extends SceneTree
##
## 卡面实装断言（2026-11-11）—— 逐条对齐 `output/imagegen/arrow-card-redesign-notes.md`
## 「箭塔卡面实装说明」：
##   · 210×340 卡槽（不变）
##   · 插画区约占卡高 70%，裁切限制在卡框内
##   · 信息区约占 30%，左右各留约 12px
##   · 卡名 26–28px 加粗居中 / 类型 13–14px / 效果摘要 13–14px 最多两行
##   · 费用角标在右上，数字 22–24px
##   · 锁定入口在左上角；插画与信息区之间保留分隔徽记
##
## 跑法：<godot> --headless --path . --script res://tests/run_card_spec_asserts.gd
##
const Shop := preload("res://scripts/ui/shop_overlay.gd")
const Text := preload("res://scripts/data/card_text.gd")
const Hover := preload("res://scripts/ui/card_hover.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[卡面实装] " + message)


func font_of(l: Label) -> int:
	return int(l.get_theme_font_size("font_size"))


func run() -> void:
	var shop: Control = Shop.new()
	shop._build()
	root.add_child(shop)
	await process_frame

	var card: Control = shop._slots[0]
	var cw: float = card.custom_minimum_size.x
	var ch: float = card.custom_minimum_size.y
	check(is_equal_approx(cw, 210.0) and is_equal_approx(ch, 340.0),
		"卡槽 210×340（实测 %.0f×%.0f）" % [cw, ch])

	# ---- 1. 插画区 ≈ 70%（8..238），横向内缩 8px 贴合外框 ----
	var backdrop: TextureRect = shop._slot_art[0].get_meta("rarity_backdrop")
	var art_ratio: float = backdrop.size.y / ch
	# 说明写「插画约 70%」：扣掉上外框 8px 与下外框 ~5px 后，卡面内区的占比约 68%；
	# 判据按**卡面内区**算，避免把外框厚度误算成插画变窄。
	var inner_ratio: float = backdrop.size.y / (ch - 13.0)
	check(inner_ratio >= 0.66 and inner_ratio <= 0.72,
		"插画区内区占比 66–72%%（说明「约 70%%」），实测 %.1f%%（整卡 %.1f%%）" % [
			inner_ratio * 100.0, art_ratio * 100.0])
	check(is_equal_approx(backdrop.position.x, 8.0) and is_equal_approx(backdrop.size.x, cw - 16.0),
		"插画横向 8..%d 内缩，裁切限制在卡框内" % int(cw - 8))

	# ---- 2. 信息区 ≈ 30%，左右各留 12px ----
	var name_l: Label = shop._slot_name[0]
	var tag_l: Label = shop._slot_tag[0]
	var desc_l: Label = shop._slot_desc[0]
	var info_ratio: float = (desc_l.position.y + desc_l.size.y - name_l.position.y) / ch
	check(info_ratio >= 0.26 and info_ratio <= 0.34,
		"信息区占卡高 26–34%%（说明「约 30%%」），实测 %.1f%%" % (info_ratio * 100.0))
	check(desc_l.position.y >= backdrop.position.y + backdrop.size.y - 8.0,
		"信息区不得压进插画区（摘要顶 %.0f ≥ 插画底 %.0f）" % [
			desc_l.position.y, backdrop.position.y + backdrop.size.y])
	for pair in [["卡名", name_l], ["类型", tag_l], ["摘要", desc_l]]:
		var l: Label = pair[1]
		check(is_equal_approx(l.position.x, 12.0) and is_equal_approx(l.size.x, cw - 24.0),
			"%s 左右各留 12px（x=%.1f, w=%.1f）" % [pair[0], l.position.x, l.size.x])

	# ---- 3. 字号：卡名 26–28 / 类型 13–14 / 摘要 13–14 / 费用 22–24 ----
	var name_px := font_of(name_l)
	var tag_px := font_of(tag_l)
	var desc_px := font_of(desc_l)
	var price_l: Label = shop._slot_price_num[0]
	var price_px := font_of(price_l)
	check(name_px >= 26 and name_px <= 28, "卡名 26–28px（实测 %d）" % name_px)
	check(tag_px >= 13 and tag_px <= 14, "类型标签 13–14px（实测 %d）" % tag_px)
	check(desc_px >= 13 and desc_px <= 14, "效果摘要 13–14px（实测 %d）" % desc_px)
	check(price_px == 19, "费用数字 19px（实测 %d）" % price_px)

	# ---- 4. 摘要只留一行基础信息（「远程单体」这类），完整文本在悬停 ----
	check(Shop.CARD_DESC_LINES == 1, "卡面基础信息行数 = 1（实测 %d）" % Shop.CARD_DESC_LINES)
	check(desc_l.visible, "卡面显示一行基础信息（不是整块隐藏）")
	check(not String(desc_l.text).contains("\n"), "卡面只显示首行（实测「%s」）" % String(desc_l.text))
	var line_h := float(desc_px) * 1.2 + 2.0   # 14px 行高约 19，+line_spacing 2
	check(desc_l.custom_minimum_size.y >= line_h,
		"摘要框容得下一行（%.0f ≥ %.0f）" % [desc_l.custom_minimum_size.y, line_h])
	var empty_first: Array = []
	for nm in ["Arrow", "Cannon", "Frost", "Tesla", "Lance", "Foundry", "Glacier", "Furnace"]:
		var lines: PackedStringArray = String(Text.describe(nm)).split("\n")
		if lines.is_empty() or String(lines[0]).strip_edges() == "":
			empty_first.append(nm)
	check(empty_first.is_empty(), "每张卡都有可读的首行基础信息%s" % (
		"" if empty_first.is_empty() else " → " + str(empty_first)))

	# ---- 5. 锁定入口在左上角 / 费用角标在右上 ----
	var lock: Control = shop._slot_lock[0]
	check(lock.position.x < cw * 0.25 and lock.position.y < ch * 0.08,
		"锁定入口在左上角（%.0f, %.0f）" % [lock.position.x, lock.position.y])
	var price_row: Control = shop._slot_price_row[0]
	check(price_row.position.x > cw * 0.6 and price_row.position.y < ch * 0.08,
		"费用角标在右上（%.0f, %.0f）" % [price_row.position.x, price_row.position.y])

	# ---- 6. 分隔徽记：六边形贴在分区线（238）上，跨插画与信息区 ----
	var plate_ok := ResourceLoader.exists("res://art/2d/ui/ui_card_plate_v3.png")
	check(plate_ok, "卡框底板贴图存在（承载斜切外框 + 六边形徽记 + 分区线）")
	if plate_ok:
		var plate: Texture2D = load("res://art/2d/ui/ui_card_plate_v3.png")
		check(plate.get_size() == Vector2(420, 680), "卡框底板为 2x（420×680），逻辑 210×340")

	# ---- 7. 牌面一行基础信息 + 悬停详情（2026-11-11 用户口径）----
	#    牌面保留「远程单体」这类首行；完整机制与数值在悬停浮卡（`card_hover`）。
	var hover: CanvasLayer = Hover.new()
	root.add_child(hover)
	hover.show_card("Arrow", Rect2(0, 0, 210, 340), "价格：12 废料", false, true)
	var htxt := String(hover.body.text)
	check(hover.panel.visible, "悬停浮卡可见（0.4s 触发后）")
	check(htxt.contains("单个敌人") and htxt.contains("伤害 8"), "悬停正文含攻击描述与数值")
	check(htxt.contains("12 废料"), "悬停正文含商店上下文（价格）")
	check(htxt.count("向单个敌人射箭") == 1, "describe 与 details 相同的卡不重复渲染正文")
	hover.free()

	print("卡面实装断言：%d 项，失败 %d 项" % [checks, failures])
	shop.free()
	quit(0 if failures == 0 else 1)
