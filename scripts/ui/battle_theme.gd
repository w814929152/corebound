extends RefCounted
## 战斗界面专用视觉，不影响主菜单和关卡选择。
const Style := preload("res://scripts/ui/ui_style.gd")
const INK := Color(0.045, 0.062, 0.09, 0.98)
const SURFACE := Color(0.075, 0.10, 0.14, 0.98)

static func panel(accent: Color = Style.C_ALLY, padding: float = 16.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = INK
	box.border_color = Color(accent, 0.32)
	box.set_border_width_all(1)
	box.border_width_top = 2
	box.set_corner_radius_all(12)
	box.set_content_margin_all(padding)
	box.shadow_color = Color(0, 0, 0, 0.38)
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 6)
	return box

static func card(active: bool = false, rarity: String = "") -> StyleBoxFlat:
	var box := panel(Style.C_ALLY if active else Style.C_STEEL, 12.0)
	box.bg_color = SURFACE.lightened(0.035) if active else SURFACE
	box.border_color.a = 0.7 if active else 0.22
	box.border_width_top = 1
	box.shadow_size = 0
	box.set_corner_radius_all(8)
	if rarity != "":
		var accent := Style.rarity_color(rarity)
		box.bg_color = box.bg_color.lerp(accent, 0.16 if active else 0.10)
		box.border_color = Color(accent, 0.85 if active else 0.48)
	return box

static func well() -> StyleBoxFlat:
	var box := card()
	box.bg_color = Color(0.025, 0.04, 0.06, 0.8)
	box.border_color = Color(Style.C_ALLY, 0.12)
	box.set_content_margin_all(6.0)
	return box

static func button(b: Button, primary: bool = false) -> void:
	Style.button(b, "primary" if primary else "normal")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := card(state == "hover")
		box.set_content_margin_all(10.0)
		box.set_corner_radius_all(6)
		if primary:
			box.bg_color = Style.C_GOLD.darkened(0.18 if state == "pressed" else 0.0)
			box.border_color = Style.C_GOLD
		if state == "disabled":
			box.bg_color = SURFACE
			box.border_color = Color(Style.C_STEEL, 0.1)
		b.add_theme_stylebox_override(state, box)
		b.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), INK if primary and state != "disabled" else Style.C_TEXT)
	b.add_theme_color_override("font_disabled_color", Style.C_TEXT_DIM)
