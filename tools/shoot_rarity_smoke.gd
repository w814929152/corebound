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
const _MonsterLayer := preload("res://scripts/ui/monster_layer.gd")

class _MockPlayer:
	extends RefCounted
	var towers: Array = []
class _MockRt:
	extends RefCounted
	var geo = null                # null → monster_layer 回退 _Geo6.SLOTS6 六槽坐标
	var player = null
	var free_placement: bool = false
	var data: Dictionary = {}
	func snapshot() -> Dictionary:
		return data
class _MockCtl:
	extends Node
	var runtime: RefCounted

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
	if _f == 205:
		for c in root.get_children():
			root.remove_child(c)
			c.free()
	if _f == 210:
		# 批次⑤：塔徽记辨识度冒烟 —— mock 快照 6 座代表塔（不进玩法）
		load("res://scripts/geo/space_model.gd").mode = 1   # Mode.RADIAL（boot 外默认 PATH）
		var ml = _MonsterLayer.new()
		var ctl := RefCounted.new()
		ctl.set_meta("rt", true)
		var holder := _MockCtl.new()
		var rt := _MockRt.new()
		rt.player = _MockPlayer.new()
		holder.runtime = rt
		ml.controller = holder
		rt.data = {
			"slots": [
				{"slot": 0, "ctype": "Arrow", "h": 1, "empty": false},
				{"slot": 1, "ctype": "Cannon", "h": 1, "empty": false},
				{"slot": 2, "ctype": "Frost", "h": 1, "empty": false},
				{"slot": 3, "ctype": "Tesla", "h": 1, "empty": false},
				{"slot": 4, "ctype": "Ember", "h": 1, "empty": false},
				{"slot": 5, "ctype": "Oblivion", "h": 1, "empty": false},
			],
			"towers": [], "minions": [],
			"selected_tower_slot": -1, "core_tower_slot": 0,
			"aggro_ui": false, "offers": [], "w": 0,
		}
		# 🔴 批次⑥：怪/仆从/投射物贴图化冒烟（世界坐标 = 径向核心 + 环带偏移）
		var sm = load("res://scripts/geo/space_model.gd")
		var cc: Vector2 = sm.RADIAL_CORE
		var mpos := func(a: float, r: float) -> Vector2:
			return cc + Vector2(cos(a), sin(a)) * r
		rt.data["monsters"] = [
			{"pos": mpos.call(0.0, 6.5), "proto": "Rush", "elite": false},
			{"pos": mpos.call(2.1, 7.0), "proto": "Swarm", "elite": false},
			{"pos": mpos.call(4.2, 7.5), "proto": "Tank", "elite": true},
			{"pos": mpos.call(5.5, 5.0), "proto": "Tank", "elite": false},
		]
		rt.data["minions"] = [{"pos": mpos.call(1.2, 3.2)}]
		rt.data["projectiles"] = [
			{"pos": mpos.call(0.9, 4.5), "vel": Vector2(-1.0, 0.4), "faction": "ally"},
			{"pos": mpos.call(3.0, 8.2), "vel": Vector2(0.5, -0.5), "faction": "enemy"},
		]
		ml._snap = rt.data
		root.add_child(ml)
	if _f == 280:
		_shot("smoke_towers_glyph.png")
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
