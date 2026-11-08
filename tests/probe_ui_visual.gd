extends SceneTree
##
## 视觉取证（非 CI · 手动跑 · **必须非 headless**）—— UI 优化轮四态截图
##
## 目的：把「改造后的玩家可见界面」逐态截图存档，供人工判读与文档引用：
##   ① 战斗态（HUD：积分卡 / 波次条 / 核心血条 / 引导浮层）
##   ② 安全窗（商店抽屉：面板 / 商品卡 / 按钮）
##   ③ 一局结算（胜利）
##   ④ 受损塔处置弹窗
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理）：
##   <godot> --path . --script res://tests/probe_ui_visual.gd
##
## 产物：G:/AI Demo/shots_uifinal/*.png
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _Result := preload("res://scripts/ui/result_overlay.gd")
const _DisabledDialog := preload("res://scripts/ui/disabled_tower_dialog.gd")

const OUT_DIR := "G:/AI Demo/shots_uifinal"


func _initialize() -> void:
	_run()


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> bool:
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var p := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(p)
	print("[ui-visual] %s err=%d size=%s" % [p, err, str(img.get_size())])
	return err == OK


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_ShopRuntime.set_extended_pack(true)
	# 🔴 必须显式注入 RADIAL（SpaceModel 全局默认 PATH，只有 boot.gd 窗口分支才切）
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var scn = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scn)
	for _i in range(4):
		await process_frame

	var rt = scn.controller.runtime
	var wd = scn.wave_director
	var director = scn.get_node_or_null("TimeDirector")

	# ① 战斗态：等 WAVE 大字横幅散场（1.2s）后再截，否则 HUD 被横幅压住。
	await _sleep(1.8)
	var ok1: bool = await _shot("01-hud-combat")

	# ② 安全窗 + 商店：攒够废料 → 开商店 → 截抽屉。
	await _sleep(0.1)
	if wd != null:
		wd.run_to_end()
	await _sleep(0.6)
	rt.scrap = 120.0
	if director != null and director.has_method("open_shop"):
		director.open_shop()
	await _sleep(0.5)
	var ok2: bool = await _shot("02-shop-safewindow")

	# ③ 结算（胜利）
	var res: CanvasLayer = _Result.new()
	root.add_child(res)
	res.show_result(true, 20, 640.0, 1000.0, 318.0)
	await _sleep(0.3)
	var ok3: bool = await _shot("03-result-win")
	root.remove_child(res)
	res.free()

	# ③b 结算（失败 · 警报红 accent）—— 🆕 战报行 + 刻线 accent 随胜负切换
	var res2: CanvasLayer = _Result.new()
	root.add_child(res2)
	res2.show_result(false, 14, 0.0, 1000.0, 207.0)
	await _sleep(0.3)
	var ok3b: bool = await _shot("03b-result-lose")
	root.remove_child(res2)
	res2.free()

	# ④ 受损塔处置弹窗
	var dlg: CanvasLayer = _DisabledDialog.new()
	root.add_child(dlg)
	dlg.show_towers([
		{"slot": 2, "invested": 84.0, "repair_cost": 26, "attach_layers": 3, "can_repair": true},
		{"slot": 5, "invested": 36.0, "repair_cost": 11, "attach_layers": 0, "can_repair": false},
	])
	await _sleep(0.3)
	var ok4: bool = await _shot("04-disabled-dialog")

	print("[ui-visual] ALL = %s" % str(ok1 and ok2 and ok3 and ok3b and ok4))
	quit(0 if (ok1 and ok2 and ok3 and ok3b and ok4) else 1)
