extends SceneTree
##
## 图鉴卡名可用宽度探针（headless）
##   目的：量化「卡名被省略号吃掉」到底是差多少 —— 输出每张卡的
##   ① 名称在 18px / 16px 下的文本像素宽；② 名字 Label 实得宽度。
##   判据：need > have ⇒ 必然出现 `…`。
## 运行：<godot> --headless --path . --script res://tools/probe_card_name_fit.gd
##
const _MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")

var _f := 0
var _menu: CanvasLayer = null


func _initialize() -> void:
	_menu = _MainMenu.new()
	root.add_child(_menu)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_menu.open()
	if _f == 20:
		_menu.show_library()
	if _f == 60:
		_report()
		return true
	return false


func _report() -> void:
	print("\n=== 卡名宽度（need@18 / need@16 / have / 结论）===")
	var bad := 0
	for blk in _menu._pack_blocks:
		for pc in blk["cards"]:
			var nl: Label = _find_name_label(pc)
			if nl == null:
				continue
			var f: Font = nl.get_theme_font("font")
			var need18: float = f.get_string_size(nl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			var need16: float = f.get_string_size(nl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var have: float = nl.size.x
			var clip := need18 > have + 0.5
			if clip:
				bad += 1
			print("  %-12s need18=%5.1f need16=%5.1f have=%5.1f %s"
				% [nl.text, need18, need16, have, "🔴 截断" if clip else "✅"])
	print("=== 会被截断的卡名 = %d 张 ===" % bad)


## 卡名 Label = 顶部 HBox 的第一个 Label（desc 在 VBox 里、pips/tag 是后续兄弟）
func _find_name_label(pc: Control) -> Label:
	for row in pc.get_children():
		for v in row.get_children():
			if v is VBoxContainer:
				for top in v.get_children():
					if top is HBoxContainer:
						for c in top.get_children():
							if c is Label:
								return c
	return null
