extends SceneTree
##
## 视觉取证（非 CI · 手动跑 · **必须非 headless**）—— 开局选包界面
##
## 目的：把「玩家开局前看到的卡包选择」逐态截图，供人工判读：
##   ① 全解锁（5 包 · 选 3）—— 正常构局
##   ② 部分解锁（4 包 · 电弧锁定）—— 解锁进度怎么读
##   ③ 未选满（0 选）—— 开始按钮禁用态
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理）：
##   <godot> --path . --script res://tests/probe_pack_select.gd
##
## 产物：G:/AI Demo/shots_pack/*.png
##

const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const _PackUI := preload("res://scripts/ui/pack_select_overlay.gd")

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
	var err := img.save_png(p)
	print("[pack-visual] %s err=%d size=%s" % [p, err, str(img.get_size())])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_RunMeta.set_save_enabled(false)

	# ① 全解锁（最佳波次 14 → 5 包）
	_RunMeta.reset_progress()
	_RunMeta.record_run(false, 14)
	var ov = _PackUI.new()
	root.add_child(ov)
	await process_frame
	ov.open()
	await _sleep(0.3)
	await _shot("01-all-unlocked-empty")
	ov._on_tile_pressed("core")
	ov._on_tile_pressed("cinder")
	ov._on_tile_pressed("pierce")
	await _sleep(0.2)
	await _shot("02-all-unlocked-selected")
	ov.free()

	# ② 部分解锁（最佳波次 6 → 4 包，电弧锁定）
	_RunMeta.reset_progress()
	_RunMeta.record_run(false, 6)
	var ov2 = _PackUI.new()
	root.add_child(ov2)
	await process_frame
	ov2.open()
	await _sleep(0.3)
	await _shot("03-partial-unlock")

	print("[pack-visual] done")
	quit(0)
