extends RefCounted
## 战斗界面专用视觉，不影响主菜单和关卡选择。
## 🆕 2026-11-10 v4「仅文字」：底色块全部取消（alpha 0）、阴影随之移除——
##    层级与状态完全靠**文字颜色 / 字重 / 位移**表达。accent 等参数保留（API 兼容）。
const Style := preload("res://scripts/ui/ui_style.gd")
const INK := Color(0.045, 0.062, 0.09, 0.98)      # 保留：主按钮墨色字（如需实心态再用）
const SURFACE := Color(0.075, 0.10, 0.14, 0.98)   # 保留：结构断言 / 需承托处覆写用

static func panel(accent: Color = Style.C_ALLY, padding: float = 16.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(INK.r, INK.g, INK.b, 0.0)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(padding)
	return box

static func card(active: bool = false, rarity: String = "") -> StyleBoxFlat:
	var box := panel(Style.C_ALLY if active else Style.C_STEEL, 12.0)
	box.set_corner_radius_all(8)
	# 稀有度 = ▲ 数（1–5）+ 颜色（调用方渲染），底色不再染色。
	return box

static func well() -> StyleBoxFlat:
	var box := card()
	box.set_content_margin_all(6.0)
	return box

static func button(b: Button, primary: bool = false) -> void:
	Style.button(b, "primary" if primary else "normal")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := card(state == "hover")
		box.set_content_margin_all(10.0)
		box.set_corner_radius_all(6)
		# 🆕 v4：底色透明（Style.button v4 已透明，这里保持一致，主键不再出实心金块）
		box.bg_color = Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_disabled_color", Style.C_TEXT_DIM)
