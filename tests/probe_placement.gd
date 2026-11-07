extends SceneTree
##
## 处方探针 · 放置模式（非 CI · 手动跑 · **必须非 headless**）
##
## 复现的 bug：「买了建筑卡，放不下塔」。
## 根因（本次修复前）：GDD §2.1 规定 ⑤ 态**抽屉收起、战场全屏**，而
##   `shop_overlay._refresh_mode()` 的 `visible = drawer != CLOSED` 会把整棵控件树隐藏
##   ⇒ 放置 UI 只有抽屉里那 6 个塔位按钮，**5 态下永远不可达**；
##   战场侧 `monster_layer._unhandled_input()` 又要求「抽屉展开」且只命中**已建塔** ⇒ 也是死路。
##   两条输入路径同时断掉 = 主循环断链。
##
## 本探针逐层取证 + 端到端验证修复：
##   A. ⑤ 态下 `shop.visible` 应为 false（符合 GDD，不再靠抽屉按钮）
##   B. `place_modes` 快照齐全（new / upgrade / invalid 三态）
##   C. 点**空塔位** → 落子成功：pending 清空、towers +1、状态退回安全窗
##   D. 点**非法位**（已有别的原型）→ 无反应、**仍留在 ⑤**（点错不该把玩家踢出放置）
##   E. 点空地 → 无反应、仍留在 ⑤
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理、也拿不到 viewport 输入）：
##   <godot> --path . --script res://tests/probe_placement.gd
##
## 产物：G:/AI Demo/shots_uifinal/place-01-enter.png / place-02-placed.png
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
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


## 模拟一次完整的鼠标左键点击（按下 + 抬起），走真实 viewport 输入管线。
## 🔴 `push_input(ev, true)`：`in_local_coords = true`。
##    默认 false 会把参数当**窗口坐标**再乘 stretch 缩放（本工程 1.2×）
##    → 传 canvas 坐标会飘到别的位置，看起来像「点击没反应」。
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
	rt.scrap = 200.0
	if director != null and director.has_method("open_shop"):
		director.open_shop()
	await _sleep(0.5)
	print("[place] 安全窗 state=%d (%s)" % [int(director.sm.state), director.sm.state_name()])

	# 买一张建筑卡 → 入待放置队列
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
	print("[place] ── 进入 ⑤ ── state=%d drawer=%d shop.visible=%s" % [
		int(director.sm.state), int(director.sm.clock()["drawer"]), str(shop.visible)])
	print("[place] 诊断: controller.director 同一实例=%s  _placing_index=%d  暂停=%s  layer.process_mode=%d" % [
		str(scn.controller.director == director), int(rt._placing_index),
		str(paused), int(layer.process_mode)])
	print("[place] 诊断: layer.controller 已注入=%s  layer.time_director 已注入=%s" % [
		str(layer.controller != null), str(layer.time_director != null)])
	print("[place] 诊断: 点击 (909,642) 命中塔位 = %d" % int(layer._hit_slot_screen(Vector2(909, 642), false)))
	_ok(entered and int(director.sm.state) == _TSM.State.PLACEMENT_MODE, "进入放置模式")
	_ok(not shop.visible, "抽屉收起（GDD §2.1：⑤ 态战场全屏）—— 落子不再依赖抽屉按钮")

	var snap: Dictionary = rt.snapshot()
	var modes: Array = snap["place_modes"]
	var towers0: int = rt.player.towers.size()      # 🔴 开局就有一记主塔（塔位 0 的 Arrow）
	print("[place] place_modes = %s（开局已有 %d 座塔：主塔）" % [str(modes), towers0])
	_ok(modes.size() == int(snap["slots"].size()), "每个塔位都有放置模式（%d 个）" % modes.size())
	_ok(modes.has("new"), "存在可新建的塔位（new）")
	_ok(modes.has("invalid"), "主塔所在塔位对建筑卡报 invalid（不可覆盖主塔）")

	var slots: Array = snap["slots"]
	for i in slots.size():
		var sp: Vector2 = layer._to_screen(layer._slots_arr()[i])
		print("[place] 塔位 %d %-6s → 屏幕 (%.0f, %.0f)  模式=%s" % [
			i, "空" if bool(slots[i]["empty"]) else String(slots[i]["ctype"]),
			sp.x, sp.y, String(modes[i])])

	await _shot("place-01-enter")

	# ---- C. 点空塔位落子 ----
	var target := -1
	for i in modes.size():
		if String(modes[i]) == "new":
			target = i
			break
	var tp: Vector2 = layer._to_screen(layer._slots_arr()[target])
	print("[place] ── 点击塔位 %d @ (%.0f, %.0f) ──" % [target, tp.x, tp.y])
	await _click(tp)
	var towers_after: int = rt.player.towers.size()
	print("[place] 点击后 state=%d pending=%s towers=%d" % [
		int(director.sm.state), str(rt.pending), towers_after])
	_ok(rt.pending.is_empty(), "落子后待放置队列清空")
	_ok(towers_after == towers0 + 1, "落子后场上 %d 座塔（主塔 + 1）" % (towers0 + 1))
	_ok(int(director.sm.state) != _TSM.State.PLACEMENT_MODE, "落子后自动退出 ⑤")

	# ---- D. 点非法位（同一塔位再买一张不同原型的卡）----
	var back_state := int(director.sm.state)
	print("[place] ── 第二张卡（不同原型）测非法位 ── 回退态=%d" % back_state)
	rt.offers = ["Frost", "ScrapUp", "FireUp"]
	shop._refresh_shop()
	await _sleep(0.2)
	scn.controller._on_buy_requested(0)
	await _sleep(0.3)
	print("[place] pending=%s" % str(rt.pending))
	if rt.pending.size() > 0:
		scn.controller.request_placement(0)
		await _sleep(0.5)
		var m2: Array = rt.snapshot()["place_modes"]
		print("[place] 第二次 place_modes = %s（塔位 %d 上已有 Cannon）" % [str(m2), target])
		_ok(String(m2[target]) == "invalid", "已有 Cannon 的塔位对 Frost 报 invalid")
		await _click(tp)
		print("[place] 点非法位后 state=%d pending=%s" % [
			int(director.sm.state), str(rt.pending)])
		_ok(int(director.sm.state) == _TSM.State.PLACEMENT_MODE, "点非法位**不**退出放置模式")
		_ok(rt.pending.size() == 1, "点非法位**不**消耗卡片")

		# ---- E. 点空地 ----
		var far := Vector2(300.0, 900.0)
		await _click(far)
		print("[place] 点空地后 state=%d" % int(director.sm.state))
		_ok(int(director.sm.state) == _TSM.State.PLACEMENT_MODE, "点空地**不**退出放置模式")

		# ---- 正常放过一张，验证「invalid 之后仍能放」 ----
		var t2 := -1
		for i in m2.size():
			if String(m2[i]) == "new":
				t2 = i
				break
		if t2 >= 0:
			var p2: Vector2 = layer._to_screen(layer._slots_arr()[t2])
			print("[place] 改点空位 %d @ (%.0f, %.0f)" % [t2, p2.x, p2.y])
			await _click(p2)
			print("[place] 落子后 towers=%d pending=%s" % [rt.player.towers.size(), str(rt.pending)])
			_ok(rt.player.towers.size() == towers0 + 2, "点错之后仍能正常落子（%d 座塔）" % (towers0 + 2))

	await _shot("place-02-placed")

	# ---- F. 升级位：同原型再买一张 → 已建塔位应报 upgrade（辉金 ↑）----
	print("[place] ── 升级路径（同原型叠层）──")
	rt.scrap = 200.0
	rt.offers = ["Cannon", "Cannon", "ScrapUp"]
	shop._refresh_shop()
	await _sleep(0.2)
	scn.controller._on_buy_requested(0)
	await _sleep(0.3)
	var pend_before: int = rt.pending.size()
	print("[place] 买第二张 Cannon 后 pending=%s" % str(rt.pending))
	if pend_before > 0:
		var idx: int = pend_before - 1
		scn.controller.request_placement(idx)
		await _sleep(0.5)
		var m3: Array = rt.snapshot()["place_modes"]
		print("[place] 升级态 place_modes = %s（塔位 %d 上已有 Cannon）" % [str(m3), target])
		_ok(String(m3[target]) == "upgrade", "已有 Cannon 的塔位对 Cannon 报 upgrade")
		await _shot("place-03-upgrade")
		var towers_before: int = rt.player.towers.size()
		var pt: Vector2 = layer._to_screen(layer._slots_arr()[target])
		await _click(pt)
		print("[place] 升级落子后 towers=%d（应不变）pending=%s" % [
			rt.player.towers.size(), str(rt.pending)])
		_ok(rt.player.towers.size() == towers_before, "升级不新增塔（%d 座）" % towers_before)
		_ok(rt.pending.is_empty(), "升级消耗掉那张卡")

	print("[place] 失败项 = %d" % _fail)
	print("[place] ALL = %s" % str(_fail == 0))
	quit(0 if _fail == 0 else 1)
