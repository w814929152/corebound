extends SceneTree
##
## 切片4 场景冒烟（**真实场景树 + 真实信号**下的接线证据）
##
## `tests/test_suite_slice4.gd` 断言的是**纯逻辑**（`ShopRuntime`，不进场景树）。
## 本脚本补另一半：把 `scenes/battle_shop.tscn` **真的跑起来**，
##   ① 波次信号（I-1）真的驱动了发牌与预算重置；
##   ② 商店意图（I-2）真的驱动了扣费 / 发牌 / 三类卡分流；
##   ③ 商品位（I-3）真的显示了卡名与价格，且**三个位尺寸完全一致**（X3）；
##   ④ 放置确认（I-8）真的把建筑卡落到了塔位；
##   ⑤ 战斗内重决策入口**置灰且不响应**（T-C1 / E16）。
##
## 跑法（headless）：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice4_scene_smoke.gd
## 跑法（窗口模式 · 顺带截帧）：
##   <godot> --path D:/roguedemo --script res://tests/run_slice4_scene_smoke.gd
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")

# 商品位尺寸**直接取实现常量**（`shop_overlay.gd` 的 `SLOT_SIZE`）——
# 本冒烟按**像素**反查三个商品位，以前手抄两份常量，改了实现忘了改测试就静默 45/46。
# 🔴 现在单一来源：实现改了这里自动跟随，不再有第二份数字。
const _ShopUI := preload("res://scripts/ui/shop_overlay.gd")
const SLOT_W := _ShopUI.SLOT_SIZE.x
const SLOT_H := _ShopUI.SLOT_SIZE.y


class Driver extends Node:
	var root_scene: Node = null
	var director: Node = null
	var controller: Node = null
	var shop: Node = null
	var _pass := 0
	var _fail := 0


	func _ready() -> void:
		# 🔴 不要在 _ready 里 add_child 到 root（会撞 "parent is busy setting up children"）
		call_deferred("run")


	func run() -> void:
		var v := Engine.get_version_info()
		print("=" .repeat(100))
		print("切片4 场景冒烟 · Godot ", v["string"], " · DisplayServer=", DisplayServer.get_name())
		print("=" .repeat(100))

		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		director = root_scene.get_node_or_null("TimeDirector")
		controller = root_scene.get_node_or_null("ShopController")
		shop = root_scene.get_node_or_null("ShopLayer/ShopOverlay")
		if director == null or controller == null or shop == null:
			print("[FATAL] 场景里缺 TimeDirector / ShopController / ShopOverlay")
			get_tree().quit(1)
			return

		var rt = controller.runtime
		if rt == null:
			print("[FATAL] ShopController.runtime 未初始化")
			get_tree().quit(1)
			return

		# =====================================================================
		# 0. 开局：最小波次驱动器发出 W1 的 wave_started（I-1）
		# =====================================================================
		print("")
		print("---- [0] 开局：W1 已由最小波次驱动器启动 ----")
		_tally("runtime 已接线", rt != null)
		_tally("波号 = W1", int(rt.wave) == 1)
		_tally("已发初始商店（商品位非空）", rt.offers.size() >= 1)
		_tally("减速预算 = 20.0", is_equal_approx(float(director.sm.budget_left), _Cfg.DILATION_BUDGET))
		_tally("态 = Combat", int(director.sm.state) == _TSM.State.COMBAT)
		print("  波次 W%d · 商品 %s · 积分 %.0f · 预算 %.1f"
			% [int(rt.wave), str(rt.offers), float(rt.scrap), float(director.sm.budget_left)])

		# =====================================================================
		# 1. I-3：商品位填真实卡面 + 🔴 X3 三个位尺寸完全一致
		# =====================================================================
		print("")
		print("---- [1] I-3 商品位真实卡面 + 🔴 X3 三商品位尺寸完全一致 ----")
		var slots := _collect_slots(root_scene, [])
		_tally("找到 3 个商品位面板", slots.size() == 3)
		var same := true
		for i in slots.size():
			var sz: Vector2 = (slots[i] as Control).custom_minimum_size
			print("  商品位 %d：custom_minimum_size = %s" % [i + 1, str(sz)])
			if not (is_equal_approx(sz.x, SLOT_W) and is_equal_approx(sz.y, SLOT_H)):
				same = false
		_tally("🔴 X3 三个商品位尺寸完全相同（150×190）", same and slots.size() == 3)

		# =====================================================================
		# 2. I-1 波次信号：跑完 W1 → 安全窗 + 击杀收入入账（M5）
		#    🔴 切片5：D-8 的 `debug_end_wave()` 已删除。这里用 `WaveDirector.run_to_end()`
		#       把本波**按真实子步**跑完（不跳过任何结算），再进安全窗。
		# =====================================================================
		print("")
		print("---- [2] I-1 波次跑完（WaveDirector）→ 安全窗 + 收入入账 ----")
		var scrap_before := float(rt.scrap)
		var wd = root_scene.get_node_or_null("WaveDirector")
		if wd == null:
			print("[FATAL] 场景里缺 WaveDirector")
			get_tree().quit(1)
			return
		wd.run_to_end()
		await _frames(4)
		_tally("进入 SafeWindow", int(director.sm.state) == _TSM.State.SAFE_WINDOW)
		_tally("安全窗 paused = true", bool(director.get_tree().paused) == true)
		_tally("安全窗 time_scale 仍为 1.0（🔴 SR-R5）",
			is_equal_approx(float(Engine.time_scale), 1.0))
		_tally("M5：击杀收入已入账（W1 = 25 分）", float(rt.scrap) > scrap_before)
		print("  积分 %.0f → %.0f（W1 击杀收入）" % [scrap_before, float(rt.scrap)])

		# =====================================================================
		# 3. 下一波：预算 / n / 锁定 三者同节奏重置
		# =====================================================================
		print("")
		print("---- [3] 下一波：预算 / 刷新次数 / 锁定 三者同节奏重置 ----")
		rt.rerolls = 3
		rt.lock_index = 1
		director.start_next_wave()
		await _frames(4)
		_tally("波号 = W2", int(rt.wave) == 2)
		_tally("预算重置为 20", is_equal_approx(float(director.sm.budget_left), _Cfg.DILATION_BUDGET))
		_tally("n ← 0", int(rt.rerolls) == 0)
		_tally("锁定每波重置", int(rt.lock_index) == -1)

		# =====================================================================
		# 4. I-2 商店意图接线：买 / 刷 / 锁
		# =====================================================================
		print("")
		print("---- [4] I-2 商店意图接线：buy / reroll / lock ----")
		director.open_shop()
		await _frames(3)
		_tally("开商店 → ShopDilated", int(director.sm.state) == _TSM.State.SHOP_DILATED)

		# ---- 买：建筑卡 → 待放置队列（不落塔、不占槽）----
		rt.scrap = 100.0
		rt.offers = ["Cannon", "FireUp", "ScrapUp"]
		director.emit_signal("buy_requested", 0)
		await _frames(2)
		_tally("买建筑卡 → 入待放置队列", (rt.pending as Array).size() == 1)
		_tally("建筑卡扣 12 分", is_equal_approx(float(rt.scrap), 88.0))
		_tally("买的时候不落塔（塔数仍为 1）", rt.player.towers.size() == 1)

		# ---- 买：单塔效果卡 → 投主塔（起手主塔 = Arrow 中性塔，可接收任意 Tag）----
		var cards_before = rt.player.cards.size()
		director.emit_signal("buy_requested", 1)
		await _frames(2)
		_tally("单塔效果卡 → 投主塔（强化槽 +1）", rt.player.cards.size() == cards_before + 1)
		_tally("单塔效果卡扣 9 分", is_equal_approx(float(rt.scrap), 79.0))

		# ---- 买：全局效果卡 → 立即生效 ----
		var im_before := float(rt.player.income_mult)
		director.emit_signal("buy_requested", 2)
		await _frames(2)
		_tally("全局效果卡 → 立即生效（income_mult +0.20）",
			is_equal_approx(float(rt.player.income_mult), im_before + 0.20))
		_tally("全局效果卡扣 10 分", is_equal_approx(float(rt.scrap), 69.0))

		# ---- 刷：扣 5+3n ----
		rt.rerolls = 0
		rt.scrap = 100.0
		director.emit_signal("reroll_requested")
		await _frames(2)
		_tally("第 1 次刷新扣 5 分", is_equal_approx(float(rt.scrap), 95.0))
		director.emit_signal("reroll_requested")
		await _frames(2)
		_tally("第 2 次刷新扣 8 分（5+3n 递增）", is_equal_approx(float(rt.scrap), 87.0))
		_tally("n = 2", int(rt.rerolls) == 2)

		# ---- 锁：3 位可锁 1 ----
		director.emit_signal("lock_toggled", 0)
		await _frames(2)
		_tally("锁定商品位 0", int(rt.lock_index) == 0)
		director.emit_signal("lock_toggled", 2)
		await _frames(2)
		_tally("改锁到商品位 2（同时最多 1 张）", int(rt.lock_index) == 2)
		director.emit_signal("lock_toggled", 2)
		await _frames(2)
		_tally("再按一次解锁", int(rt.lock_index) == -1)

		# =====================================================================
		# 5. I-8 放置确认：点塔位落子
		# =====================================================================
		print("")
		print("---- [5] I-8 放置确认：待放置队列 → 放置模式 → 落子 ----")
		_tally("队列里有 1 张建筑卡", (rt.pending as Array).size() == 1)
		_tally("进入放置模式", controller.request_placement(0) == true)
		await _frames(3)
		_tally("态 = PlacementMode", int(director.sm.state) == _TSM.State.PLACEMENT_MODE)
		_tally("放置模式抽屉收起", int(director.sm.clock()["drawer"]) == _TSM.Drawer.CLOSED)
		director.exit_placement(true, 1)
		await _frames(3)
		_tally("落子后塔数 = 2", rt.player.towers.size() == 2)
		_tally("队列清空", (rt.pending as Array).size() == 0)
		_tally("塔位 1 是 Cannon", String(rt.player.towers[1].ctype) == "Cannon")
		print("  落子结果：塔位 1 = %s L%d"
			% [String(rt.player.towers[1].ctype), int(rt.player.towers[1].h)])

		# =====================================================================
		# 6. 🔴 T-C1 / E16：战斗内重决策入口置灰且不响应
		# =====================================================================
		print("")
		print("---- [6] 🔴 T-C1 / E16：战斗内（非安全窗）重决策入口置灰 ----")
		director.close_shop()
		await _frames(3)
		_tally("回到 Combat", int(director.sm.state) == _TSM.State.COMBAT)
		_tally("弃卡按钮置灰", bool(shop._discard_btn.disabled) == true)
		_tally("卸下改投按钮置灰", bool(shop._detach_btn.disabled) == true)
		_tally("拆除回收按钮置灰", bool(shop._salvage_btn.disabled) == true)
		# 置灰 ≠ 消失：入口仍然可见（GDD 只要求"不响应"）
		_tally("入口仍可见（置灰不是隐藏）", bool(shop._heavy_panel.visible) == true)

		# =====================================================================
		# 7. 商品位 UI 文本（H1 价格 / 卡名真的渲染出来了）
		# =====================================================================
		print("")
		print("---- [7] 商品位 UI 文本（真实卡名 / 价格 / H1）----")
		director.open_shop()
		await _frames(3)
		rt.scrap = 100.0
		rt.offers = ["Cannon", "FireUp", "ScrapUp"]
		controller._emit_shop()
		await _frames(3)
		for i in 3:
			print("  商品位 %d：%s / %s / %s（买按钮 disabled=%s）"
				% [i + 1, String(shop._slot_name[i].text), String(shop._slot_kind[i].text),
				   String(shop._slot_price[i].text), str(bool(shop._slot_buy[i].disabled))])
		_tally("商品位 1 显示真实卡名 Cannon", String(shop._slot_name[0].text) == "Cannon")
		# UI 优化轮：价格文案自 S2 起带 **✓/✗ 字形冗余**（art-bible §9.2 红线1 非色彩通道），
		# 本断言原期望 "12 分" 已与实现脱节（一直失败、且本脚本不在 CI 里，故无人发现）。
		_tally("商品位 1 显示价格 12 分（含 ✓ 冗余）", String(shop._slot_price[0].text) == "✓ 12 分")
		_tally("买得起 → 购买按钮可用", bool(shop._slot_buy[0].disabled) == false)
		rt.scrap = 1.0
		controller._emit_shop()
		await _frames(3)
		_tally("H1 买不起 → 购买按钮置灰（卡片本身不隐藏，X6）",
			bool(shop._slot_buy[0].disabled) == true)
		_tally("H1 买不起 → 卡片仍在（卡名未变）", String(shop._slot_name[0].text) == "Cannon")

		# =====================================================================
		# 8. 截帧（best effort）
		# =====================================================================
		await _screenshot()

		Engine.time_scale = 1.0
		get_tree().paused = false
		print("")
		print("=" .repeat(100))
		print("切片4 冒烟汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
		print("=" .repeat(100))
		get_tree().quit(0 if _fail == 0 else 1)


	func _collect_slots(n: Node, out: Array) -> Array:
		for c in n.get_children():
			if c is PanelContainer:
				var sz: Vector2 = (c as Control).custom_minimum_size
				if is_equal_approx(sz.x, SLOT_W) and is_equal_approx(sz.y, SLOT_H):
					out.append(c)
			_collect_slots(c, out)
		return out


	func _frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame


	func _tally(name: String, ok: bool) -> void:
		if ok:
			_pass += 1
		else:
			_fail += 1
		if ok:
			print("   [PASS] %s" % name)
		else:
			print("   [FAIL] %s" % name)


	func _screenshot() -> void:
		if DisplayServer.get_name() == "headless":
			print("")
			print("---- 截帧 ----")
			print("  headless 无渲染后端 → 跳过（窗口模式跑本脚本会真出图）")
			return
		await RenderingServer.frame_post_draw
		var img := get_tree().root.get_texture().get_image()
		if img == null or img.get_width() == 0:
			print("")
			print("---- 截帧 ----")
			print("  取不到视口纹理 → 跳过")
			return
		var out := ProjectSettings.globalize_path("res://docs/phase3/slice4-shop.png")
		var err := img.save_png(out)
		print("")
		print("---- 截帧 ----")
		print("  ", ("已保存 " + out) if err == OK else ("保存失败 err=" + str(err)))


func _initialize() -> void:
	var scene: Node = load("res://scenes/battle_shop.tscn").instantiate()
	scene.name = "BattleShop"
	root.add_child(scene)
	var d := Driver.new()
	d.name = "Slice4SmokeDriver"
	d.root_scene = scene
	root.add_child(d)
