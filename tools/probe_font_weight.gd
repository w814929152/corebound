extends SceneTree
##
## 字重验证冒烟：`FontVariation.variation_opentype` 的字符串键 "wght" 是否真被 Godot 接受。
## 三行同文字同字号：raw ttf(=400) / font_body()(应 500) / font_medium()(应 700)。
## 输出三行渲染区域的墨量（非背景像素数）→ 粗者墨量显著更大。
## 产物：art/_review/_tmp_weight_probe.png（临时，验证后可删）。

const _Style := preload("res://scripts/ui/ui_style.gd")

var _f := 0
var _labels: Array[Label] = []


func _initialize() -> void:
	var root_ctl := Control.new()
	root_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_ctl)
	var texts := ["守核 开始游戏 COREBOUND 888", "守核 开始游戏 COREBOUND 888", "守核 开始游戏 COREBOUND 888"]
	var fonts: Array = [
		load("res://assets/fonts/NotoSansSC.ttf"),   # 裸 ttf = 默认 400 基准
		_Style.font_body(),                            # 应为 500
		_Style.font_medium(),                          # 应为 700
	]
	for i in 3:
		var l := Label.new()
		l.text = texts[i]
		l.position = Vector2(20, 20 + i * 90)
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		var f: Font = fonts[i]
		if f != null:
			l.add_theme_font_override("font", f)
		root_ctl.add_child(l)
		_labels.append(l)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://art/_review/_tmp_weight_probe.png")
		for i in 3:
			var rect := Rect2i(0, 20 + i * 90, 1200, 85)
			var ink := 0
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					if img.get_pixel(x, y).r > 0.4:
						ink += 1
			print("[probe] row ", i, " ink=", ink)
		return true
	return false
