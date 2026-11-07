extends SceneTree
##
## 处方探针 · 自由摆放（非 CI · 手动跑 · **必须非 headless**）
##
## 这一版测的是**自由摆放**：塔不再落在 6 个固定塔位上，而是落在网格的任意格点。
##   ① 进 ⑤ 后有网格（不是 6 个八边形）
##   ② 点地图任意合法格 → 落子成功，槽位表增长
##   ③ 点核心禁建区 / 战场外 / 同格异原型 → 不落子、**不退出** ⑤（点错不踢人）
##   ④ 同一张卡改落别处 → 成功
##   ⑤ 同格再落同原型 → 升级（不新增塔、不新增槽）
##
## 🔴 为什么必须走真实鼠标事件：改造史上最贵的一次 bug 就是「控件建好了、信号连好了，
##    但玩家永远点不到」。任何绕过 viewport 输入管线的测试都会漏掉这一类问题。
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理、也拿不到 viewport 输入）：
##   <godot> --path . --script res://tests/probe_placement.gd
##
## 产物：G:/AI Demo/shots_uifinal/place-01-enter.png / place-02-placed.png / place-03-upgrade.png
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")

const OUT_DIR := "G:/AI Demo/shots_uifinal"

var _fail := 0


func _initialize() -> void:
	_run()


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
	print("[place] %s %s" % ["PASS" if cond else "FAIL", msg])


func _shot(name: String) -> void:
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var p := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(p)
	print("[place] shot %s" % p)


## 取证：把悬停格钉在某个**世界坐标**上。
## 🔴 为什么不用 `warp_mouse`：本工程视口 1920×1080、窗口 1600×900，窗口模式下
##    `warp_mouse` 受 DPI / 缩放影响 —— 实测 warp 到 (870,450) 后
##    `get_mouse_position()` 读到 (73,775)，完全无关 → 截图会拍到"错的格子"。
##    `MonsterLayer.probe_hover_world` 是显式注入点（默认 null = 跟随真实鼠标）。
func _set_hover(layer, world: Vector2) -> void:
	layer.probe_hover_world = world
	await _sleep(0.20)


## 模拟一次完整的鼠标左键点击（按下 + 抬起），走真实 viewport 输入管线。
## 🔴 `push_input(ev, true)`：`in_local_coords = true`。
##    默认 false 会把参数当**窗口坐标**再乘 stretch 缩放（本工程 1920→1600，1.2×）
##    → 传 canvas 坐标会飘到别的位置，看起来完全像「点击没反应」。
func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev, true)
	await _sleep(0.35)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_ShopRuntime.set_extended_pack(true)
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var scn = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scn)
	for _i in range(4):
		await process_frame

	var wd = scn.wave_director
	var director = scn.get_node_or_null("TimeDirector")
	var shop = scn.get_node_or_null("ShopLayer/ShopOverlay")
	var layer = scn.find_child("MonsterLayer", true, false)
	var rt = scn.controller.runtime

	# 进安全窗（进商店前必须先跑完本波）
	await _sleep(1.8)
	if wd != null:
		wd.run_to_end()
	await _sleep(0.6)
	rt.scrap = 500.0
	if director != null and director.has_method("open_shop"):
		director.open_shop()
	await _sleep(0.5)
	print("[place] 安全窗 state=%d (%s)" % [int(director.sm.state), director.sm.state_name()])
	print("[place] 自由摆放 = %s  槽位表 = %d 个  塔数 = %d / %d" % [
		str(rt.free_placement), rt.geo.slots.size(), rt.player.towers.size(), rt.tower_cap()])

	# ---- 买一张建筑卡 → 入待放置队列 ----
	rt.offers = ["Cannon", "FireUp", "ScrapUp"]
	shop._refresh_shop()
	await _sleep(0.2)
	scn.controller._on_buy_requested(0)
	await _sleep(0.3)
	print("[place] 买后 pending=%s scrap=%.0f" % [str(rt.pending), rt.scrap])
	_ok(rt.pending.size() == 1, "建筑卡买入后进入待放置队列（%s）" % str(rt.pending))

	# ---- 进入 ⑤ ----
	var entered: bool = scn.controller.request_placement(0)
	await _sleep(0.6)
	var towers0: int = rt.player.towers.size()
	var slots0: int = rt.geo.slots.size()
	print("[place] ── 进入 ⑤ ── state=%d drawer=%d shop.visible=%s 塔数=%d 槽位=%d" % [
		int(director.sm.state), int(director.sm.clock()["drawer"]), str(shop.visible),
		towers0, slots0])
	_ok(entered and int(director.sm.state) == _TSM.State.PLACEMENT_MODE, "进入放置模式")
	_ok(not shop.visible, "抽屉收起（GDD §2.1：⑤ 态战场全屏）")

	# 网格必须真的铺出来（不然玩家不知道点哪算一格）
	_ok(not layer._grid_segs.is_empty(), "⑤ 态网格线段已构建（%d 条）" % layer._grid_segs.size())
	var cell_n: int = _BuildGrid.all_cells().size()
	_ok(cell_n > 500, "可建格点 %d 个 —— 位置自由，不是 6 个固定点" % cell_n)

	var core: Vector2 = _BuildGrid.core()
	# 目标格：核心右方 10 单位（距核心 10 ∈ [4, 44] → 合法）
	var target: Vector2 = _BuildGrid.snap(core + Vector2(10.0, 0.0))
	var tp: Vector2 = layer._to_screen(target)
	print("[place] 目标格 = %s → 屏幕 (%.0f, %.0f)  模式=%s" % [
		str(target), tp.x, tp.y, str(rt.placement_mode_at(target)["mode"])])
	_ok(String(rt.placement_mode_at(target)["mode"]) == "new", "目标格当前报 new（可新建）")

	await _set_hover(layer, target)        # 悬停格钉在目标格上（截图取证）
	await _shot("place-01-enter")

	# ---- ② 点合法格落子 ----
	await _click(tp)
	print("[place] 点击后 state=%d pending=%s towers=%d slots=%d err=%s" % [
		int(director.sm.state), str(rt.pending), rt.player.towers.size(),
		rt.geo.slots.size(), rt.last_error])
	_ok(rt.pending.is_empty(), "落子后待放置队列清空")
	_ok(rt.player.towers.size() == towers0 + 1, "落子后场上 %d 座塔（原 %d）" % [
		towers0 + 1, towers0])
	_ok(rt.geo.slots.size() == slots0 + 1, "落子后槽位表 %d → %d（新格即新槽）" % [
		slots0, rt.geo.slots.size()])
	_ok(int(director.sm.state) != _TSM.State.PLACEMENT_MODE, "落子后自动退出 ⑤")

	await _shot("place-02-placed")

	# ---- ③ 点核心禁建区 / 战场外 / 同格异原型 → 不落子、不退出 ----
	rt.scrap = 500.0
	rt.offers = ["Frost", "ScrapUp", "FireUp"]
	shop._refresh_shop()
	await _sleep(0.2)
	scn.controller._on_buy_requested(0)
	await _sleep(0.3)
	_ok(rt.pending.size() == 1, "第二张卡进入队列（%s）" % str(rt.pending))
	scn.controller.request_placement(0)
	await _sleep(0.5)

	var towers1: int = rt.player.towers.size()
	await _click(layer._to_screen(core))
	print("[place] 点核心后 state=%d pending=%s towers=%d" % [
		int(director.sm.state), str(rt.pending), rt.player.towers.size()])
	_ok(int(director.sm.state) == _TSM.State.PLACEMENT_MODE, "点核心禁建区**不**退出放置模式")
	_ok(rt.player.towers.size() == towers1, "点核心禁建区**不**落子")

	# 战场外（屏幕左上角，超出可建圆）
	await _click(Vector2(60.0, 60.0))
	_ok(int(director.sm.state) == _TSM.State.PLACEMENT_MODE, "点战场外**不**退出放置模式")

	# 同格异原型 → 拒绝（target 上已有 Cannon，现在手里是 Frost）
	await _click(tp)
	print("[place] 同格异原型后 state=%d pending=%s err=%s" % [
		int(director.sm.state), str(rt.pending), rt.last_error])
	_ok(int(director.sm.state) == _TSM.State.PLACEMENT_MODE, "同格异原型**不**退出放置模式")
	_ok(rt.pending.size() == 1, "同格异原型**不**消耗卡片")

	# ---- ④ 同一张卡改落别处 → 成功 ----
	var other: Vector2 = _BuildGrid.snap(core + Vector2(-10.0, 7.5))
	var op: Vector2 = layer._to_screen(other)
	print("[place] 改落另一格 %s → 屏幕 (%.0f, %.0f)" % [str(other), op.x, op.y])
	await _click(op)
	print("[place] 落子后 towers=%d slots=%d pending=%s" % [
		rt.player.towers.size(), rt.geo.slots.size(), str(rt.pending)])
	_ok(rt.player.towers.size() == towers1 + 1, "点错之后改落别处仍能成功（%d 座）" % (towers1 + 1))

	# ---- ⑤ 升级：同原型再买一张，落在同一格 ----
	rt.scrap = 500.0
	rt.offers = ["Cannon", "Cannon", "ScrapUp"]
	shop._refresh_shop()
	await _sleep(0.2)
	scn.controller._on_buy_requested(0)
	await _sleep(0.3)
	var pend_before: int = rt.pending.size()
	print("[place] 买第二张 Cannon 后 pending=%s" % str(rt.pending))
	if pend_before > 0:
		scn.controller.request_placement(pend_before - 1)
		await _sleep(0.4)
		print("[place] 升级预览 = %s" % str(rt.placement_mode_at(target)))
		_ok(String(rt.placement_mode_at(target)["mode"]) == "upgrade",
			"已有 Cannon 的格对未来 Cannon 报 upgrade")
		await _set_hover(layer, target)     # 悬停格钉在待升级格上（截图取证金色 ↑）
		await _shot("place-03-upgrade")
		var towers_before: int = rt.player.towers.size()
		var slots_before: int = rt.geo.slots.size()
		await _click(tp)
		print("[place] 升级落子后 towers=%d slots=%d pending=%s" % [
			rt.player.towers.size(), rt.geo.slots.size(), str(rt.pending)])
		_ok(rt.player.towers.size() == towers_before, "升级不新增塔（%d 座）" % towers_before)
		_ok(rt.geo.slots.size() == slots_before, "升级不新增槽（%d 个）" % slots_before)
		_ok(rt.pending.is_empty(), "升级消耗掉那张卡")

	# ---- 汇总 ----
	print("[place] 最终 塔数=%d 槽位=%d 塔上限=%d" % [
		rt.player.towers.size(), rt.geo.slots.size(), rt.tower_cap()])
	for i in rt.geo.slots.size():
		print("[place] 槽 %d @ %s" % [i, str(rt.geo.slots[i])])

	print("[place] 失败项 = %d" % _fail)
	print("[place] ALL = %s" % str(_fail == 0))
	quit(0 if _fail == 0 else 1)
