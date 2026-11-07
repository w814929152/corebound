extends SceneTree
##
## 端到端取证（非 CI · 手动跑 · **必须非 headless**）—— 卡包从"选"到"开局"全链路
##
## 验证的不是单测口径，而是**接线**：
##   ① 进游戏 → 主场景 Boot 在窗口模式下**不自动开波**，先弹选包界面；
##   ② 点开始 → `ShopRuntime.set_active_packs()` 生效（卡池 = 6 张所选包并集）；
##   ③ 确认后 W1 真的开波（HUD / 战场有东西在跑）。
##
## 跑法：
##   <godot> --path . --script res://tests/probe_pack_flow.gd
##
## 产物：G:/AI Demo/shots_pack/1x-*.png
##

const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")

const OUT_DIR := "G:/AI Demo/shots_pack"


func _initialize() -> void:
	_run()


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var p := "%s/%s.png" % [OUT_DIR, name]
	print("[pack-flow] %s err=%d" % [p, img.save_png(p)])


func _run() -> void:
	# 🔴 确定态：不碰真实存档；最佳波次 14 → 5 包全解锁 → 必然弹选包界面
	_RunMeta.set_save_enabled(false)
	_RunMeta.reset_progress()
	_RunMeta.record_run(false, 14)

	var boot = load("res://scenes/main.tscn").instantiate()
	root.add_child(boot)
	await _sleep(0.8)

	print("[pack-flow] overlay visible = %s" % str(boot._pack_select.visible))
	print("[pack-flow] wave before confirm = %d" % int(boot._bs.controller.runtime.wave))
	await _shot("10-boot-pack-select")

	var sel: Array = ["core", "cinder", "arc"]
	boot._on_packs_confirmed(sel)
	await _sleep(0.2)
	print("[pack-flow] active packs = %s" % str(_ShopRuntime.active_pack_ids()))
	print("[pack-flow] pool = %s (%d)" % [
		str(_ShopRuntime.player_card_names()), _ShopRuntime.player_card_names().size()])
	print("[pack-flow] wave after confirm = %d" % int(boot._bs.controller.runtime.wave))
	print("[pack-flow] overlay visible after confirm = %s" % str(boot._pack_select.visible))
	await _sleep(1.6)
	await _shot("11-run-started")

	print("[pack-flow] done")
	quit(0)
