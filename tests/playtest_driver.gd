extends SceneTree
##
## QA 临时 Playtest 驱动（T-P6-01）· 窗口模式真实帧跑通 + 截帧。
## 🔴 临时件，验证后删除（零残留）。不改任何生产代码。
##
## 场景（user args）：
##   product : 产品全开（RADIAL + proto/elite/aggro/revive），贪心自动建造，打到 W20 或失败
##   fail    : 不建塔 → 核心被击穿 → 失败结算
##   uic4    : aggro 开 / revive 关 → 塔被打到 Disabled → 核验 C-4 停机压暗
##

const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")


class Driver extends Node:
	var scene: Node
	var director: Node
	var controller: Node
	var wd: Node
	var ml: Node
	var runtime
	var scenario := "product"
	var shots: Array = []

	func _ready() -> void:
		call_deferred("run")

	func _log(s: String) -> void:
		print(s)

	func _frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame

	func _real_wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout

	func _shot(name: String) -> void:
		if DisplayServer.get_name() == "headless":
			return
		await RenderingServer.frame_post_draw
		var img := get_tree().root.get_texture().get_image()
		if img == null or img.get_width() == 0:
			_log("[P6][shot] FAILED (no texture): %s" % name)
			return
		var out := ProjectSettings.globalize_path("res://docs/phase6/shots/" + name)
		var err := img.save_png(out)
		shots.append(name if err == OK else (name + "(ERR)"))
		_log("[P6][shot] %s %dx%d err=%d" % [name, img.get_width(), img.get_height(), err])

	func run() -> void:
		director = scene.get_node_or_null("TimeDirector")
		controller = scene.get_node_or_null("ShopController")
		wd = scene.get_node_or_null("WaveDirector")
		ml = scene.get_node_or_null("Battlefield/MonsterLayer")
		if director == null or controller == null or wd == null:
			_log("[P6][FATAL] 缺节点")
			get_tree().quit(2)
			return
		runtime = controller.runtime
		# 🔴 产品口径注入（必须在 scene._ready **之后**——WaveDirector 由 battle_shop._ready()
		#    动态 add_child，`_initialize()` 里 add_child(scene) 时它尚不存在 → 那次注入全被
		#    `if wd != null` 静默跳过，导致「产品局」实为默认口径（aggro/elite/revive 全 OFF）。
		#    这里 scene._ready 已跑完 → wd 为真节点 → 注入生效。
		wd.prototype_split_enabled = true
		wd.elite_waves_enabled = (scenario != "uic4")
		wd.tower_aggro_enabled = true
		wd.combat_revive_enabled = (scenario != "uic4")
		# 自动 `start_run(1)` 已用默认口径建过 W1 刷新表 → 用产品口径**重建 W1**（不发波信号、无副作用）。
		wd.start_wave(1)
		# 🔴 结算诊断挂钩：run_won/run_lost 在 shop_controller 之后触发 → 打印此刻 runtime.scrap
		wd.run_won.connect(_on_won_hook)
		wd.run_lost.connect(_on_lost_hook)
		_log("[P6] scenario=%s · DisplayServer=%s" % [scenario, DisplayServer.get_name()])
		_log("[P6] geo.slots=%d · is_radial=%s · proto=%s elite=%s aggro=%s revive=%s"
			% [runtime.geo.slots.size(), str(_SpaceModel.is_radial()),
				str(wd.prototype_split_enabled), str(wd.elite_waves_enabled),
				str(wd.tower_aggro_enabled), str(wd.combat_revive_enabled)])
		await _frames(5)
		if scenario == "fail":
			await _run_fail()
		elif scenario == "uic4":
			await _run_uic4()
		elif scenario == "revive":
			await _run_revive()
		else:
			await _run_product()
		_log("[P6] shots taken: %s" % str(shots))
		get_tree().quit(0)

	# ------------------------------------------------------------------
	# 自动建造：贪心买 + 落子（安全窗内）
	# ------------------------------------------------------------------
	func _autobuild() -> void:
		# ① 修复受损塔（真实玩家「修复 / 拆除 / 放着不管」三选一里的优先动作；
		#    对应 MC PRICED 臂 repair_on_disable=2 —— 「最接近产品」且 B@6=0.850）。
		var n_rep := 0
		for row in runtime.list_disabled_towers():
			var slot := int(row.get("slot", -1))
			if slot >= 0:
				var r: Dictionary = runtime.repair_tower(slot)
				if bool(r.get("ok", false)):
					n_rep += 1
		if n_rep > 0:
			_log("[P6]   修复 %d 座塔（scrap=%.0f）" % [n_rep, float(runtime.scrap)])
		# ② 贪心买 + 落子（安全窗内）
		var guard := 0
		while guard < 60:
			guard += 1
			var bought := false
			for s in range(3):
				if runtime.can_buy(s):
					var kind := String(runtime.card_kind(s))
					if runtime.buy(s):
						bought = true
						if kind == "tower":
							_place_pending()
			if not bought:
				break
		_place_pending()

	func _place_pending() -> void:
		var guard := 0
		while runtime.pending.size() > 0 and guard < 24:
			guard += 1
			if not runtime.begin_placement(0):
				break
			var ok := false
			for slot in range(0, runtime.geo.slots.size()):
				if runtime.confirm_placement(slot):
					ok = true
					break
			if not ok:
				runtime.cancel_placement()
				break

	# ------------------------------------------------------------------
	# 产品口径全流程
	# ------------------------------------------------------------------
	func _run_product() -> void:
		var cps := [1, 5, 10, 15, 20]
		for w in range(1, 21):
			if w > 1:
				director.start_next_wave()
				await _frames(4)
			director.close_shop()
			await _frames(3)
			# 战斗中截帧
			if cps.has(w):
				await _real_wait(0.6)
				await _shot("W%d-battle.png" % w)
				if w == 5 or w == 10:
					_dump_slots("product-W%d-battle" % w)
			wd.run_to_end()
			await _frames(5)
			var nd := int(wd._count_disabled_towers())
			_log("[P6] W%d 结束: core=%.0f/%.0f scrap=%.0f towers=%d disabled=%d failed=%s victory=%s"
				% [w, float(runtime.player.core_hp), float(runtime.player.core_hp_max),
					float(runtime.scrap), runtime.player.towers.size(), nd,
					str(wd.run_failed), str(wd.victory)])
			# 🔴 修正：`controller.over` 在 run_won / run_lost **都**置位 →
			#    必须先判 victory，否则 W20 胜利会被误判为失败。
			if bool(wd.victory):
				await _shot("VICTORY.png")
				_log("[P6] **WON at W%d**（victory=true）" % w)
				return
			if bool(wd.run_failed) or bool(controller.over):
				await _shot("DEFEAT-w%d.png" % w)
				_log("[P6] **LOST at W%d**" % w)
				return
			# 安全窗（商店自动展开）
			await _frames(4)
			if w == 4:
				await _shot("W4-safe-elite-preview.png")   # 下一波 W5 精英预告
			if cps.has(w) or w == 3:
				await _shot("W%d-safe-window.png" % w)
			_autobuild()
			await _frames(3)
			if w == 3:
				await _shot("W3-shop-open.png")
			_log("[P6] W%d 安全窗后: towers=%d pending=%d scrap=%.0f"
				% [w, runtime.player.towers.size(), runtime.pending.size(), float(runtime.scrap)])
			if bool(wd.victory):
				await _shot("VICTORY.png")
				_log("[P6] **WON at W%d**" % w)
				return

	# ------------------------------------------------------------------
	# 失败局：不建塔
	# ------------------------------------------------------------------
	func _run_fail() -> void:
		for w in range(1, 21):
			if w > 1:
				director.start_next_wave()
				await _frames(4)
			director.close_shop()
			await _frames(3)
			wd.run_to_end()
			await _frames(5)
			_log("[P6-fail] W%d: core=%.0f failed=%s" % [w, float(runtime.player.core_hp), str(wd.run_failed)])
			if bool(wd.run_failed) or bool(controller.over):
				await _real_wait(0.4)
				await _shot("DEFEAT-overlay.png")
				_log("[P6-fail] **LOST at W%d**（结算覆盖层应已弹出）" % w)
				return
		_log("[P6-fail] 未失败（20 波跑完）")
		await _shot("fail-loopend.png")

	# ------------------------------------------------------------------
	# C-4 专项：aggro 开 / revive 关 → 塔被打到 Disabled（压暗可见）
	# ------------------------------------------------------------------
	func _run_uic4() -> void:
		# 先在安全窗建 1 座塔（放第一个空位 = 暴露位）
		await _frames(3)
		_open_shop_and_build_first_tower()
		await _shot("uic4-tower-placed.png")
		# 跑波次，直到出现 Disabled 塔
		for w in range(1, 11):
			if w > 1:
				director.start_next_wave()
				await _frames(4)
			director.close_shop()
			await _frames(3)
			# 分帧推进战斗，边跑边查 Disabled
			var steps := 0
			while (int(wd.state) == 1 or int(wd.state) == 2) and steps < 6000:
				steps += 1
				wd.advance(1.0 / 60.0)
				if int(wd._count_disabled_towers()) > 0:
					await _frames(2)
					await _shot("uic4-w%d-tower-disabled.png" % w)
					_log("[P6-uic4] W%d: 捕获 Disabled 塔（steps=%d core=%.0f）"
						% [w, steps, float(runtime.player.core_hp)])
					_dump_slots("uic4-capture")
					get_tree().quit(0)
					return
			await _frames(4)
			_log("[P6-uic4] W%d 无 Disabled（towers=%d core=%.0f）"
				% [w, runtime.player.towers.size(), float(runtime.player.core_hp)])
			if bool(wd.run_failed) or bool(controller.over):
				_log("[P6-uic4] 失败于 W%d" % w)
				return
		_log("[P6-uic4] 10 波内未出现 Disabled 塔")

	# ------------------------------------------------------------------
	# 爬起环专项：revive ON，分帧推进到塔被仇恨打停并自动爬起 → 抓 `_revive_flash` 帧
	# ------------------------------------------------------------------
	func _run_revive() -> void:
		await _frames(3)
		_autobuild()                       # W1 安全窗先建塔
		for w in range(1, 11):
			if w > 1:
				director.start_next_wave()
				await _frames(4)
			director.close_shop()
			await _frames(3)
			# 🔴 用**真实帧**推进（不手动 advance）：HUD 横幅/动效随 _process 播放 → 横幅会自然退场，
			#    爬起环才不会被冻结的横幅盖住。逐帧轮询 `_revive_flash`。
			var guard := 0
			while (int(wd.state) == 1 or int(wd.state) == 2) and guard < 4000:
				guard += 1
				await _frames(1)
				if ml != null and not ml._revive_flash.is_empty():
					await _shot("revive-flash-ring.png")
					_log("[P6-revive] W%d: 捕获爬起环 flash_slots=%s frames=%d core=%.0f disabled=%d"
						% [w, str(ml._revive_flash.keys()), guard,
							float(runtime.player.core_hp), int(wd._count_disabled_towers())])
					get_tree().quit(0)
					return
			await _frames(4)
			_log("[P6-revive] W%d 无爬起环（towers=%d disabled=%d core=%.0f）"
				% [w, runtime.player.towers.size(), int(wd._count_disabled_towers()), float(runtime.player.core_hp)])
			if bool(wd.run_failed) or bool(controller.over):
				_log("[P6-revive] 失败于 W%d" % w)
				return
			_autobuild()
		_log("[P6-revive] 10 波内未捕获爬起环（如实报告：未覆盖）")

	func _open_shop_and_build_first_tower() -> void:
		# 直接落一座塔：买第一个建筑卡
		runtime.deal_initial_shop()
		for s in range(3):
			if String(runtime.card_kind(s)) == "tower" and runtime.can_buy(s):
				runtime.buy(s)
				_place_pending()
				break
		if runtime.player.towers.is_empty():
			# 没有建筑卡 → 直接经 apply_action 建一座（诊断用）
			var _ShopAI := load("res://scripts/engine/shop_ai.gd")
			_ShopAI.apply_action(runtime.player, ["build", "Arrow", 0, null], runtime.cfg)
		_log("[P6-uic4] 建塔后 towers=%d" % runtime.player.towers.size())

	func _on_won_hook(p_w: int) -> void:
		_log("[P6][run_won] w=%d runtime.scrap=%.0f core=%.0f scrap_earned(this)=%.0f"
			% [p_w, float(runtime.scrap), float(runtime.player.core_hp),
				float(wd.scrap_earned)])

	func _on_lost_hook(p_w: int) -> void:
		_log("[P6][run_lost] w=%d runtime.scrap=%.0f core=%.0f"
			% [p_w, float(runtime.scrap), float(runtime.player.core_hp)])

	func _dump_slots(tag: String) -> void:
		var snap: Dictionary = runtime.snapshot()
		var slots: Array = snap.get("slots", [])
		var line := ""
		for tw in slots:
			line += "[slot %d empty=%s ctype=%s h=%s disabled=%s] " % [
				int(tw.get("slot", -1)), str(tw.get("empty", true)),
				str(tw.get("ctype", "-")), str(tw.get("h", "-")),
				str(tw.get("disabled", "-"))]
		_log("[P6-uic4][%s] slots(%d): %s" % [tag, slots.size(), line])
		_log("[P6-uic4][%s] selected=%s core_slot=%s towers=%d disabled=%d"
			% [tag, str(snap.get("selected_tower_slot", -1)), str(snap.get("core_tower_slot", -1)),
				runtime.player.towers.size(), int(wd._count_disabled_towers())])


func _initialize() -> void:
	var scenario := "product"
	for a in OS.get_cmdline_user_args():
		var s := a.strip_edges().to_lower()
		if s in ["product", "fail", "uic4", "revive"]:
			scenario = s
	var scene: Node = load("res://scenes/battle_shop.tscn").instantiate()
	scene.name = "BattleShop"
	root.add_child(scene)
	# 🔴 产品口径（镜像 boot.gd 窗口分支）。`SpaceModel.mode` 是全局静态 → 此处设有效；
	#    但 proto/elite/aggro/revive 是 WaveDirector 实例开关，而该节点由 battle_shop._ready()
	#    动态创建、此刻尚不存在 → 开关注入必须挪到 Driver.run()（见上）。
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var d := Driver.new()
	d.name = "P6Driver"
	d.scene = scene
	d.scenario = scenario
	root.add_child(d)
