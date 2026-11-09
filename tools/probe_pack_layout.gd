extends SceneTree
##
## 卡包选择页布局探针（2026-11-09）
##   打印面板 / 瓦片 / 包色顶条的真实矩形，用于定位「瓦片溢出面板、卡名横穿」问题。
## 运行：<godot> --path . --script res://tools/probe_pack_layout.gd
##
const _PackSelect := preload("res://scripts/ui/pack_select_overlay.gd")

var _f := 0
var _pack: CanvasLayer = null


func _initialize() -> void:
	_pack = _PackSelect.new()
	root.add_child(_pack)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_pack.open()
	if _f == 30:
		print("[screen] ", root.size)
		var panel := _find_panel(_pack)
		if panel != null:
			var par: Control = panel.get_parent() as Control
			print("[holder] ", par.get_class(), " pos=", par.position, " size=", par.size,
				" anchors=", par.anchor_left, ",", par.anchor_top, ",", par.anchor_right, ",", par.anchor_bottom)
			print("[panel ] pos=", panel.position, " size=", panel.size,
				" min=", panel.get_combined_minimum_size())
			for ch in panel.get_children():
				print("   child ", ch.get_class(), " ", ch.name, " pos=", ch.position, " size=", ch.size)
				for g in ch.get_children():
					if g is HBoxContainer:
						print("   row size=", g.size, " min=", g.get_combined_minimum_size())
						for i in g.get_child_count():
							var t: Control = g.get_child(i)
							print("     tile#", i, " pos=", t.position, " size=", t.size,
								" min=", t.get_combined_minimum_size())
							for h in t.get_children():
								if h is TextureRect:
									var tr := h as TextureRect
									print("       tex ", tr.position, " size=", tr.size,
										" stretch=", tr.stretch_mode)
								elif h is MarginContainer:
									var mc := h as MarginContainer
									print("       margin min_h=", mc.get_combined_minimum_size().y,
										" tile_h=", t.size.y)
		_print_grids(_pack)
		return true
	return false


func _find_panel(n: Node) -> PanelContainer:
	if n is PanelContainer:
		return n as PanelContainer
	for ch in n.get_children():
		var r := _find_panel(ch)
		if r != null:
			return r
	return null


func _print_grids(n: Node) -> void:
	if n is GridContainer:
		var g := n as GridContainer
		print("  grid size=", g.size, " min=", g.get_combined_minimum_size(),
			" cols=", g.columns)
		for i in g.get_child_count():
			if i > 3:
				break
			var l: Label = g.get_child(i)
			print("    label ", l.text, " w=", l.size.x, " min=", l.get_combined_minimum_size())
	for ch in n.get_children():
		_print_grids(ch)
