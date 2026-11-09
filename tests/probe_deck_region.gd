extends SceneTree
##
## 视觉取证（非 CI · 手动跑 · **必须非 headless**）—— v2 地区主线：航图 + 科技包
##
## 目的：把「玩家从开局到守下第一个地区」看到的三块界面逐态截图，供人工判读：
##   ① 航图·初期   —— 只通了中枢 0-1：外环三区可选，中环全锁，内环门槛关灰显
##   ② 航图·中期   —— 守下外环 3 区 + 中环 1 区：链/环的解锁关系在图上是否读得出来
##   ③ 选包·借用   —— region 口径下只有 core 可用 + cinder 本关借用（金框文案）
##   ④ 选包·守满   —— 守住 3 区后回到「必须选 3 包」
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理）：
##   <godot> --path . --script res://tests/probe_deck_region.gd
##
## 产物：G:/AI Demo/shots_v2_region/*.png
##

const _Campaign := preload("res://scripts/gameplay/campaign.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")
const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const _Packs := preload("res://scripts/data/card_packs.gd")
const _PackUI := preload("res://scripts/ui/pack_select_overlay.gd")
const _StageUI := preload("res://scripts/ui/stage_select_overlay.gd")

const OUT_DIR := "G:/AI Demo/shots_v2_region"


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
	print("[region-visual] %s err=%d size=%s" % [p, err, str(img.get_size())])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# 🔴 两条线都必须关掉落盘：探针不是玩局，不能污染真实存档。
	_RunMeta.set_save_enabled(false)
	_Packs.unlock_by_region = true

	# ---- ① 航图 · 初期（只通了中枢）----
	var c1 = _Campaign.new()
	c1.mark_cleared(_CampaignData.START_STAGE)
	c1.set_current_stage("1-1")
	var ss1 = _StageUI.new()
	root.add_child(ss1)
	await process_frame
	ss1.open(c1)
	await _sleep(0.35)
	await _shot("01-map-early")
	ss1.free()

	# ---- ② 航图 · 中期（外环 3 区 + 中环电弧区已守）----
	var c2 = _Campaign.new()
	for sid in ["0-1", "1-1", "2-1", "3-1", "4-1"]:
		c2.mark_cleared(sid)
	c2.set_current_stage("5-1")
	var ss2 = _StageUI.new()
	root.add_child(ss2)
	await process_frame
	ss2.open(c2)
	await _sleep(0.35)
	await _shot("02-map-mid")
	ss2.free()

	# ---- ③ 选包 · 借用（0 区已守，进 1-1 → cinder 借用）----
	_Packs.set_region_progress([], "cinder")
	_RunMeta.reset_progress()
	var ov1 = _PackUI.new()
	root.add_child(ov1)
	await process_frame
	ov1.open()
	await _sleep(0.3)
	await _shot("03-pack-borrow")
	ov1.free()

	# ---- ④ 选包 · 守满 3 区（core + 3 区包 → 回到「必须选 3」）----
	_Packs.set_region_progress(["cinder", "rime", "pierce"], "")
	var ov2 = _PackUI.new()
	root.add_child(ov2)
	await process_frame
	ov2.open()
	await _sleep(0.3)
	ov2._on_tile_pressed("cinder")
	ov2._on_tile_pressed("rime")
	await _sleep(0.15)
	await _shot("04-pack-three")
	ov2.free()

	# 收尾：注入态是静态的，跑完必须还原（否则同进程后续探针读到幽灵解锁）
	_Packs.set_region_progress([], "")
	_Packs.unlock_by_region = false
	quit(0)
