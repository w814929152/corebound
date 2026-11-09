extends SceneTree
##
## 资产包 v6 实机截图冒烟（窗口模式 · 2026-11-09）
##   ① 卡包选择页：8 个瓦片顶部的包色顶条（复用 v5 ui_lib_head_bar_v1）
##   ② 战斗商店：三个商品位的中性 9-slice 承托板（ui_shop_slot_plate_v1）
##   🔴 除截屏外，统计场景里真正实例化了贴图的两类控件数量作为接线硬证据；
##      资产缺失时数量会是 0 —— 这正是判空降级链路的验收点。
## 运行：<godot> --path . --script res://tools/shoot_ui_plate_smoke.gd
## 产物：art/_review/smoke_v6_pack_select.png / smoke_v6_shop_slots.png
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
		# open() 必须在 _ready（第 1 帧把 visible=false）之后调用
		_pack.open()
	if _f == 30:
		_shot("smoke_v6_pack_select.png")
		print("[info] 包色顶条 TextureRect 数 = ", _count_tex(root, "ui_lib_head_bar_v1", false), "（期望 8）")
	if _f == 35:
		_clear_root()
	if _f == 40:
		var ps: PackedScene = load("res://scenes/battle_shop.tscn")
		root.add_child(ps.instantiate())
	if _f == 55:
		var director := _find_with_method(root, "open_shop")
		if director != null:
			director.call("open_shop")
		else:
			print("[WARN] 未找到 open_shop —— 商店帧可能未开抽屉")
	if _f == 100:
		_shot("smoke_v6_shop_slots.png")
		print("[info] 承托板 NinePatchRect 数 = ", _count_tex(root, "ui_shop_slot_plate_v1", true), "（期望 3）")
	if _f >= 105:
		return true
	return false


func _count_tex(n: Node, needle: String, nine_only: bool) -> int:
	var c := 0
	if nine_only and n is NinePatchRect:
		var np := n as NinePatchRect
		if np.texture != null and np.texture.resource_path.contains(needle):
			c += 1
	elif not nine_only and n is TextureRect and not (n is NinePatchRect):
		var tr := n as TextureRect
		if tr.texture != null and tr.texture.resource_path.contains(needle):
			c += 1
	for ch in n.get_children():
		c += _count_tex(ch, needle, nine_only)
	return c


func _clear_root() -> void:
	for ch in root.get_children():
		root.remove_child(ch)
		ch.free()


func _find_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for ch in n.get_children():
		var r := _find_with_method(ch, m)
		if r != null:
			return r
	return null


func _shot(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://art/_review/" + fname)
	print("[shot] art/_review/", fname)
