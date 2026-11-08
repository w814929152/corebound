extends SceneTree
##
## 实机截图冒烟（非 CI · 窗口模式）：HUD 仪表层贴图目检
##   ① 常态战斗 —— 金币读数板 / 波次导轨 + 62% 填充 + 游标 / 14 段核心血条 / 四角角标
##   ② 低血    —— frac ≤ 0.25 走告警段（斜纹）
##   ③ 精英波  —— 品红填充 + 警报红光
## 运行：<godot> --path . --script res://tools/shoot_hud_smoke.gd
## 产物：art/_review/smoke_hud_battle.png / smoke_hud_lowhp.png / smoke_hud_elite.png
##
## 🔴 hud.gd 的 `_refresh_wave_progress()` 在 controller 为空时**直接 return**，
##    所以这里直接写私有字段不会被下一帧覆盖（无需造 wave_director 假快照）。
##
const _Hud := preload("res://scripts/ui/hud.gd")
const _CoreBar := preload("res://scripts/ui/core_hp_bar.gd")
const _MonsterLayer := preload("res://scripts/ui/monster_layer.gd")


class _MockPlayer:
	extends RefCounted
	var towers: Array = []


class _MockRt:
	extends RefCounted
	var geo = null
	var player = null
	var free_placement: bool = false
	var data: Dictionary = {}

	func snapshot() -> Dictionary:
		return data


class _MockCtl:
	extends Node
	var runtime: RefCounted


var _f := 0
var _hud: Node
var _bar: Node


func _initialize() -> void:
	load("res://scripts/geo/space_model.gd").mode = 1   # Mode.RADIAL（boot 外默认 PATH）
	var ml = _MonsterLayer.new()
	var holder := _MockCtl.new()
	var rt := _MockRt.new()
	rt.player = _MockPlayer.new()
	holder.runtime = rt
	ml.controller = holder
	rt.data = {
		"slots": [
			{"slot": 0, "ctype": "Arrow", "h": 2, "empty": false},
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
	root.add_child(ml)
	_hud = _Hud.new()
	root.add_child(_hud)
	_bar = _CoreBar.new()
	root.add_child(_bar)


func _set_wave(progress: float, elite: bool, spawned: int, total: int) -> void:
	_hud.set("_wave_progress", progress)
	_hud.set("_wave_spawned", spawned)
	_hud.set("_wave_total", total)
	_hud.set("_wave_elite", elite)
	_hud.set("_wave_in_combat", true)
	_hud.queue_redraw()


func _process(_d: float) -> bool:
	_f += 1
	# 🔴 血条平时靠 `_refresh_hp → set_hp` 触发重绘；本冒烟没绑 controller，
	#    不手动重绘就会把"碎段闪白"那一帧冻在屏上（实测血条一片惨白）。
	if _bar != null:
		_bar.queue_redraw()
	if _f == 20:
		_set_wave(0.62, false, 8, 13)
		_bar.call("set_hp", 720.0, 1000.0)
	if _f == 24:
		_hud.call("_on_wave_started", 3)
	if _f == 30:
		_shot("smoke_hud_battle.png")
	# 🔴 低血帧要等碎段闪白（SHATTER_SEC 0.18s ≈ 11 帧）演完再截，否则拍到的是白光
	if _f == 34:
		_bar.call("set_hp", 180.0, 1000.0)
	if _f == 58:
		_shot("smoke_hud_lowhp.png")
	if _f == 62:
		_bar.call("set_hp", 720.0, 1000.0)
		_set_wave(0.34, true, 5, 15)
		_hud.call("_on_wave_started", 4)
	if _f == 84:
		_shot("smoke_hud_elite.png")
	if _f == 88:
		return true
	return false


func _shot(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://art/_review/" + fname)
	print("[shot] art/_review/", fname)
