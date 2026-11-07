extends SceneTree
##
## 塔等级牌视觉探针（**非 CI · 手动跑 · 必须非 headless**）
##
## 目的：同一套输入（8 座塔 · 等级 1/2/3/5/8/12/40/120）出两帧对照：
##   · `before` —— 隐藏 `TowerLevelLayer`（= 改前口径：等级只靠形态递进暗示）
##   · `after`  —— 显示等级牌
## 并额外截一张「安全窗/商店展开」帧，检查等级牌与决策期 ⚔/🛡 徽标是否抢位。
##
## 跑法：
##   <godot> --path . --script res://tests/probe_tower_level.gd -- after
##   <godot> --path . --script res://tests/probe_tower_level.gd -- before
##
## 产物：G:/AI Demo/shots_towerlevel/*.png
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _PS := preload("res://scripts/engine/player_state.gd")

const OUT_DIR := "G:/AI Demo/shots_towerlevel"
const LEVELS: Array = [1, 2, 3, 5, 8, 12, 40, 120]
const CTYPES: Array = ["Arrow", "Cannon", "Frost", "Lance", "Tesla", "Arrow", "Cannon", "Frost"]
const RING_U := 15.0

var _tag := "after"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		_tag = String(a)
	_run()


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var p := "%s/%s-%s.png" % [OUT_DIR, _tag, name]
	print("[tlv] %s err=%d size=%s" % [p, img.save_png(p), str(img.get_size())])


## 把塔群区域裁出来放大 4×（原图字太小，判读不了笔画/对齐）。
func _zoom(img_name: String, box: Rect2i) -> void:
	var img := Image.new()
	if img.load("%s/%s-%s.png" % [OUT_DIR, _tag, img_name]) != OK:
		return
	var r := box.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var c := img.get_region(r)
	c.resize(c.get_width() * 4, c.get_height() * 4, Image.INTERPOLATE_NEAREST)
	var p := "%s/%s-%s-zoom.png" % [OUT_DIR, _tag, img_name]
	print("[tlv] %s err=%d" % [p, c.save_png(p)])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_ShopRuntime.set_extended_pack(true)
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var scn = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scn)
	for _i in range(4):
		await process_frame

	var rt = scn.controller.runtime
	var ml = scn.get_node_or_null("Battlefield/MonsterLayer")
	var tlv = scn.get_node_or_null("Battlefield/TowerLevelLayer")
	var director = scn.get_node_or_null("TimeDirector")
	if tlv != null and _tag == "before":
		tlv.visible = false

	# ---- 造 8 座塔：等角分布在内圈，等级递进 ----
	rt.player.towers.clear()
	var core: Vector2 = _BuildGrid.core()
	for i in LEVELS.size():
		var a := TAU * float(i) / float(LEVELS.size()) - PI * 0.5
		var wp: Vector2 = _BuildGrid.snap(core + Vector2(cos(a), sin(a)) * RING_U)
		var slot: int = rt.geo.add_slot(wp)
		rt.player.towers.append(_PS.make_tower(slot, String(CTYPES[i]), int(LEVELS[i]), {}))
	rt.selected_tower_slot = 2
	if ml != null:
		ml.queue_redraw()
	# 让等级牌重建一次
	if tlv != null and tlv.has_method("bind_controller"):
		tlv.bind_controller(scn.controller)

	await _sleep(2.2)     # 战斗进行中（有怪、有受击闪）
	if ml != null:
		var sc: float = ml.world_scale()
		print("[tlv] sc=%.3f  towerR=%.1fpx  towers=%d" % [sc, 1.70 * sc, rt.player.towers.size()])
	await _shot("01-combat")
	# 塔群包围盒（±70px 余量）→ 4× 放大裁切，供人眼判读字迹/对齐
	if ml != null:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for t in rt.player.towers:
			var sp: Vector2 = ml.world_to_screen(rt.geo.slots[int(t.slot)])
			lo = Vector2(minf(lo.x, sp.x), minf(lo.y, sp.y))
			hi = Vector2(maxf(hi.x, sp.x), maxf(hi.y, sp.y))
		var pad := 70
		_zoom("01-combat", Rect2i(int(lo.x) - pad, int(lo.y) - pad,
			int(hi.x - lo.x) + pad * 2, int(hi.y - lo.y) + pad * 2))

	# ---- 决策期（抽屉展开）：检查与 ⚔/🛡 徽标抢位 ----
	await _sleep(0.1)
	scn.wave_director.run_to_end()
	await _sleep(0.8)
	rt.scrap = 200.0
	if director != null and director.has_method("open_shop"):
		director.open_shop()
	await _sleep(0.6)
	await _shot("02-shop-open")
	if ml != null:
		var lo2 := Vector2(1e9, 1e9)
		var hi2 := Vector2(-1e9, -1e9)
		for t in rt.player.towers:
			var sp2: Vector2 = ml.world_to_screen(rt.geo.slots[int(t.slot)])
			lo2 = Vector2(minf(lo2.x, sp2.x), minf(lo2.y, sp2.y))
			hi2 = Vector2(maxf(hi2.x, sp2.x), maxf(hi2.y, sp2.y))
		var pad2 := 70
		_zoom("02-shop-open", Rect2i(int(lo2.x) - pad2, int(lo2.y) - pad2,
			int(hi2.x - lo2.x) + pad2 * 2, int(hi2.y - lo2.y) + pad2 * 2))

	print("[tlv] DONE tag=%s" % _tag)
	quit(0)
