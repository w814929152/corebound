extends SceneTree
##
## 视觉取证 · 卡面描述块（非 CI · 手动跑 · **必须非 headless**）
##
## 目的：证明商品位现在真的回答了「这张卡干什么」——
##   改造前卡上只有「卡名 + 卡种」，玩家分不清 Cannon 和 FireUp 的区别。
##
## 三张卡**强制指定**（不走随机发牌），保证三类描述形态都入镜：
##   ① 主表池：`Cannon`（建筑卡 · 溅射）/ `FireUp`（强化卡 · 点火） / `ScrapUp`（全局卡）
##   ② 扩展包：`Lance` / `Tesla`（新塔，名字最长、数值行最满）
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理）：
##   <godot> --path . --script res://tests/probe_card_desc.gd
##
## 产物：G:/AI Demo/shots_uifinal/card-desc-01/02.png
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

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
	print("[card-desc] %s err=%d size=%s" % [p, err, str(img.get_size())])
	return err == OK


## 强制发牌：直接写 `runtime.offers`（UI 只读快照，无法从 UI 侧注入）
func _force(scn: Node, names: Array) -> void:
	var rt = scn.controller.runtime
	rt.offers = names
	_shop(scn)._refresh_shop()


func _shop(scn: Node) -> Node:
	return scn.get_node_or_null("ShopLayer/ShopOverlay")


## 打印每个位的描述，便于在日志里直接核对文案（不用看图也能验内容）
func _dump(scn: Node, tag: String) -> void:
	var shop = _shop(scn)
	for i in shop.SLOT_COUNT:
		var card: Control = shop._slots[i]
		var lb: Label = shop._slot_desc[i]
		var nm := String(shop._slot_name[i].text)
		var d := String(lb.text).replace("\n", " ⏎ ")
		# 实际几何：卡片被容器压了多少、描述块真实占多高（换行数 ≈ 高度 / 行高）
		var lines := lb.size.y / 21.0 if lb.size.y > 0.0 else 0.0
		print("[card-desc] %s slot%d 卡=%.0fx%.0f 文字宽=%.1f 描述高=%.1f (~%.1f 行)  %s → %s" % [
			tag, i, card.size.x, card.size.y, lb.size.x, lb.size.y, lines, nm, d])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_ShopRuntime.set_extended_pack(true)
	# 🔴 必须显式注入 RADIAL（SpaceModel 全局默认 PATH，只有 boot.gd 窗口分支才切）
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var scn = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scn)
	for _i in range(4):
		await process_frame

	var wd = scn.wave_director
	var director = scn.get_node_or_null("TimeDirector")
	var rt = scn.controller.runtime

	# 进安全窗（进商店前必须先跑完本波，否则 open_shop 被状态机拒绝）
	await _sleep(1.8)
	if wd != null:
		wd.run_to_end()
	await _sleep(0.6)
	rt.scrap = 120.0
	if director != null and director.has_method("open_shop"):
		director.open_shop()
	await _sleep(0.5)

	# ① 三类卡各一张：建筑 / 强化 / 全局
	_force(scn, ["Cannon", "FireUp", "ScrapUp"])
	await _sleep(0.3)
	_dump(scn, "主表")
	var ok1: bool = await _shot("card-desc-01-core")

	# ② 扩展包最长的两张 + 一张新强化（名字最长 / 数值行最满 → 压迫换行）
	_force(scn, ["Lance", "Tesla", "PirUp"])
	await _sleep(0.3)
	_dump(scn, "扩展")
	var ok2: bool = await _shot("card-desc-02-ext")

	# ③ 放置模式（抽屉里最挤的一态：多出图例 + 6 个塔位按钮）——
	#    验证加了描述块与流程提示后，抽屉内容**仍不超出屏底**。
	_force(scn, ["Cannon", "FireUp", "ScrapUp"])
	await _sleep(0.2)
	scn.controller._on_buy_requested(0)
	await _sleep(0.3)
	scn.controller.request_placement(0)
	await _sleep(0.5)
	var ok3: bool = await _shot("card-desc-03-placement")

	print("[card-desc] ALL = %s" % str(ok1 and ok2 and ok3))
	quit(0 if (ok1 and ok2 and ok3) else 1)
