extends SceneTree
##
## 视觉取证（非 CI · 手动跑 · **必须非 headless**）—— 扩展包新塔在真实战场上的可辨性
##
## 目的：art-bible §3.1 / §9.2① 要求「形状是第一通道、颜色是第二通道」。
##   本脚本把五塔直接注入战场（绕过商店抽卡，纯视觉取证），截一张 PNG 供人工判读：
##     · Lance（紫 / 五边形）与 Tesla（电黄 / 七边形）能否**一眼**与既有三塔区分
##     · 是否与敌橙 `#FF6B3D`、精英品红 `#E8437F` 撞色
##     · 八边形外轮廓是否仍是严格 8 重对称
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理）：
##   <godot> --path . --script res://tests/probe_ext_visual.gd
##
## 产物：G:/AI Demo/shots_ext/ext-towers.png
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const OUT_PATH := "G:/AI Demo/shots_ext/ext-towers.png"


func _initialize() -> void:
	_run()


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	_ShopRuntime.set_extended_pack(true)
	# 🔴 必须显式注入 RADIAL —— `SpaceModel.mode` 全局默认是 PATH，
	#    只有 `boot.gd` 的窗口分支会切到 RADIAL。本探针直接装载 `battle_shop.tscn`，
	#    不设这一行就会截到「方形折线路径」而不是产品真正的径向战场。
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var scn = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scn)
	for _i in range(4):
		await process_frame

	var rt = scn.controller.runtime
	var wd = scn.wave_director

	# 直接注入五塔到不同塔位（绕过商店，纯视觉取证）。
	rt.player.towers.clear()
	rt.player.towers.append(_PS.make_tower(0, "Arrow", 2, {}))
	rt.player.towers.append(_PS.make_tower(1, "Cannon", 2, {}))
	rt.player.towers.append(_PS.make_tower(2, "Frost", 2, {}))
	rt.player.towers.append(_PS.make_tower(3, "Lance", 2, {}))
	rt.player.towers.append(_PS.make_tower(4, "Tesla", 2, {}))

	# 跑完本波 → 进安全窗（无怪干扰、无「WAVE 1」大字横幅遮挡）。
	if wd != null:
		wd.run_to_end()
	# 🔴 WAVE 横幅是 1.2s 演出，必须等它散场，否则正好盖住塔位。
	await _sleep(1.8)
	for _i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = root.get_texture().get_image()
	var err := img.save_png(OUT_PATH)
	print("[visual] save_png err=%d path=%s size=%s" % [err, OUT_PATH, str(img.get_size())])

	# 裁剪塔区放大 3 倍 —— 塔在 1600×900 下仅约 15px，必须放大才能判读
	# 「内形边数」这个第一通道是否真的可辨（art-bible §9.2①）。
	# 🔴 不能用 viewport 中心：商店抽屉占右侧 32%，战场中心被推到偏左。
	#    这里直接框住实测塔区（核心周围 460×340）。
	var rect := Rect2i(330, 300, 460, 340)
	var zoom: Image = img.get_region(rect)
	zoom.resize(rect.size.x * 3, rect.size.y * 3, Image.INTERPOLATE_NEAREST)
	var err2 := zoom.save_png("G:/AI Demo/shots_ext/ext-towers-zoom.png")
	print("[visual] zoom save_png err=%d size=%s" % [err2, str(zoom.get_size())])

	print("[visual] towers = Arrow(slot0) Cannon(1) Frost(2) Lance(3) Tesla(4)")
	quit(0 if (err == OK and err2 == OK) else 1)
