extends SceneTree
##
## 视觉取证（非 CI · 手动跑 · **必须非 headless**）—— 开局选包界面
##
## 目的：把「玩家开局前看到的卡包选择」逐态截图，供人工判读：
##   ① 全开（8 包 · 选 3 · 未选）—— 2026-11-07 起默认口径
##   ② 全开（8 包 · 已选 3）—— 选中态与开始按钮可用态
##   ③ 老口径回滚（all_packs_open=false · 4 包 · 电弧锁定）—— 锁定态仍然正确
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理）：
##   <godot> --path . --script res://tests/probe_pack_select.gd
##
## 产物：G:/AI Demo/shots_pack/*.png
##

const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const _PackUI := preload("res://scripts/ui/pack_select_overlay.gd")
const _Packs := preload("res://scripts/data/card_packs.gd")

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
	_Packs.all_packs_open = true

	# ① 全开（2026-11-07 起默认口径）：8 包 · 任选 3
	_RunMeta.reset_progress()
	var ov = _PackUI.new()
	root.add_child(ov)
	await process_frame
	ov.open()
	await _sleep(0.3)
	await _shot("01-all-open-empty")
	ov._on_tile_pressed("core")
	ov._on_tile_pressed("cinder")
	ov._on_tile_pressed("pierce")
	await _sleep(0.2)
	await _shot("02-all-open-selected")
	ov.free()

	# ② 老口径回滚（all_packs_open=false · 最佳波次 6 → 4 包，锁定态仍然正确）
	_Packs.all_packs_open = false
	_RunMeta.reset_progress()
	_RunMeta.record_run(false, 6)
	var ov2 = _PackUI.new()
	root.add_child(ov2)
	await process_frame
	ov2.open()
	await _sleep(0.3)
	await _shot("03-legacy-partial-unlock")
	ov2.free()
	_Packs.all_packs_open = true

	print("[pack-visual] done")
	quit(0)
