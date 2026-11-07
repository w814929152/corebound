extends SceneTree
##
## 换图实机探针 · `probe_variant_crash.gd`（诊断用，不进 CI）
##
## 背景：2026-11-07 实机选 1-2（variant-a）后数秒原生崩溃（0xc0000005），headless 复现不了。
## 做法：窗口模式装载真实 battle_shop 场景，注入 variant-a + 12 波，跑 900 帧。
##   · 崩溃 → 复现（会在 stderr 看到 SCRIPT ERROR / 进程直接消失）；
##   · 存活 → 说明该变体的几何 / 绘制链路无原生问题。
##
## 跑法：<godot> --path . --script res://tools/probe_variant_crash.gd
## 换变体：改下面的 MAP_ID（tri-fissure / variant-a..h / fusion）。
##

const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _BattleShop := preload("res://scenes/battle_shop.tscn")

const MAP_ID := "variant-a"
const FRAMES := 900


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	print("[probe] boot")
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	_SpaceModel.set_active_map(MAP_ID)
	print("[probe] map=", _SpaceModel.active_map_id,
		" open=", _SpaceModel.active_open_deg(),
		" ridges=", _SpaceModel.active_ridges().size(),
		" arcs=", _SpaceModel.active_spawn_arcs().size())

	var bs = _BattleShop.instantiate()
	bs.auto_start_run = false
	root.add_child(bs)
	await process_frame

	bs.wave_director.prototype_split_enabled = true
	bs.wave_director.elite_waves_enabled = true
	bs.wave_director.tower_aggro_enabled = true
	bs.wave_director.combat_revive_enabled = true
	bs.wave_director.combat_types_enabled = true
	bs.wave_director.set_max_wave(12)
	print("[probe] start run")
	bs.controller.start_new_run()
	print("[probe] run started")

	for i in range(FRAMES):
		await process_frame
		if i % 120 == 0:
			print("[probe] frame ", i)
	print("[probe] SURVIVED")
	quit(0)
