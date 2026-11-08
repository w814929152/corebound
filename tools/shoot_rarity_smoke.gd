extends SceneTree
##
## 实机截图冒烟（非 CI · 窗口模式）：资产包 v1 接入目检
##   ① battle_shop —— 稀有度卡面（边框色 + ▲ 角标，§2.3 / P1-6）
##   ② 选包覆盖层 —— 卡包徽记（art/2d/icons/ic_pack_*_v1）
## 运行：<godot> --path . --script res://tools/shoot_rarity_smoke.gd
## 产物：art/_review/smoke_rarity_shop.png / smoke_pack_emblems.png
##
const _PackSelect := preload("res://scripts/ui/pack_select_overlay.gd")
const _StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")

var _f := 0

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/battle_shop.tscn")
	root.add_child(ps.instantiate())

func _process(_d: float) -> bool:
	_f += 1
	if _f == 15:
		var director := _find_with_method(root, "open_shop")
		if director != null:
			director.call("open_shop")
		else:
			print("[WARN] 未找到 open_shop —— 商店帧可能未开抽屉")
	if _f == 60:
		_shot("smoke_rarity_shop.png")
	if _f == 65:
		for c in root.get_children():
			root.remove_child(c)
			c.free()
	if _f == 70:
		var pk := _PackSelect.new()
		root.add_child(pk)
		pk.call("open")
	if _f == 130:
		_shot("smoke_pack_emblems.png")
	if _f == 135:
		for c in root.get_children():
			root.remove_child(c)
			c.free()
	if _f == 140:
		var camp: RefCounted = load("res://scripts/gameplay/campaign.gd").new()
		var ss := _StageSelect.new()
		root.add_child(ss)
		ss.call("open", camp)
	if _f == 200:
		_shot("smoke_stage_lock.png")
		return true   # 退出
	return false

func _find_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for c in n.get_children():
		var r := _find_with_method(c, m)
		if r != null:
			return r
	return null

func _shot(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://art/_review/" + fname)
	print("[shot] art/_review/", fname)
