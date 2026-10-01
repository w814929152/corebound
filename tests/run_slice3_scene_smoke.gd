extends SceneTree
##
## 切片3 场景冒烟（**真实帧**下的证据采集）
##
## `tests/test_suite_slice3.gd` 断言的是**纯逻辑**（注入实时秒，确定性）。
## 本脚本补另一半：把骨架场景**真的跑起来**，在真机上读
##   `Engine.time_scale` / `get_tree().paused` / 减速预算，
## 逐条对照 GDD §2.1 的表格，并把证据打进日志。
##
## 跑法（headless）：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice3_scene_smoke.gd
## 跑法（窗口模式 · 顺带截帧）：
##   <godot> --path D:/roguedemo --script res://tests/run_slice3_scene_smoke.gd
##

const FRAMES_PER_STATE := 6
const REAL_WAIT_SEC := 10.0      # 验收标准 3：开商店 10 实时秒 → 预算 20 → 10

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")


class Driver extends Node:
	var root_scene: Node = null
	var director: Node = null
	var battlefield: Node = null
	var _pass := 0
	var _fail := 0
	var _rows: Array = []


	func _ready() -> void:
		# 🔴 不要在 _ready 里 add_child 到 root（会撞 "parent is busy setting up children"）
		call_deferred("run")


	func run() -> void:
		var v := Engine.get_version_info()
		print("=" .repeat(100))
		print("切片3 场景冒烟 · Godot ", v["string"], " · DisplayServer=", DisplayServer.get_name())
		print("=" .repeat(100))

		await get_tree().process_frame
		await get_tree().process_frame

		director = root_scene.get_node_or_null("TimeDirector")
		battlefield = root_scene.get_node_or_null("Battlefield")
		if director == null:
			print("[FATAL] 场景里找不到 TimeDirector")
			get_tree().quit(1)
			return

		# ---- 布局读数（🔴 Q-S3-C 落地：视口 1920×1080 = GDD §2.4 基准屏）----
		var vw := float(get_viewport().get_visible_rect().size.x)
		var dw := _ShopLayout.drawer_width(vw)
		var bw := _ShopLayout.battlefield_width(vw, true)
		print("")
		print("---- C3 双焦点布局 ----")
		print("  视口宽            = %.0f px" % vw)
		print("  抽屉宽（算尺）    = %.1f px  → 占屏 %.2f%%" % [dw, _ShopLayout.drawer_ratio(vw) * 100.0])
		print("  战场可视宽        = %.1f px  → 占屏 %.2f%%" % [bw, bw / vw * 100.0])
		print("  取整口径：算尺返回浮点原值（614.4 / 1305.6），不 floor 不 round")
		_tally("视口宽 = 1920（Q-S3-C 拍板）", is_equal_approx(vw, 1920.0))
		_tally("抽屉宽 = 614.4（0.32×1920）", is_equal_approx(dw, 614.4))
		_tally("抽屉占屏 ≈ 32%%", absf(_ShopLayout.drawer_ratio(vw) - 0.32) <= 1e-9)
		_tally("战场可视宽 = 1305.6（68%%）", is_equal_approx(bw, 1305.6))

		# ---- 五态巡游 ----
		print("")
		print("---- 五态时钟口径实测（真机读 Engine / SceneTree）----")
		print("态                |期望 ts|期望paused|实测 ts|实测paused|预算消耗|抽屉|预算剩余")
		print("-" .repeat(100))

		await _goto("Combat", func(): director.wave_start(6))
		await _goto("ShopDilated", func(): director.open_shop())
		await _goto("PlacementMode", func(): director.enter_placement())
		await _goto("ShopDilated(回)", func(): director.exit_placement(false))
		await _goto("ShopRealTime", func():
			director.sm.spend_budget(20.0))
		await _goto("Combat(回)", func(): director.close_shop())
		await _goto("SafeWindow", func(): director.wave_end(6))

		# ---- 暂停时战场真的停了吗 ----
		print("")
		print("---- 暂停验证：SafeWindow 下战场（PAUSABLE 节点）必须完全静止 ----")
		var t0 := float(battlefield._t)
		for _i in 30:
			await get_tree().process_frame
		var t1 := float(battlefield._t)
		var ok_stop := is_equal_approx(t0, t1)
		_tally("SafeWindow 战场时间不推进", ok_stop)
		print("  战场游戏时间：进入 SafeWindow 后 30 帧，%.6f → %.6f（%s）" % [
			t0, t1, "✅ 完全停止" if ok_stop else "❌ 仍在推进"])

		# ---- 新手保护 W3 ----
		print("")
		print("---- 新手保护 W1–W5：0.25× 且不消耗预算 ----")
		director.wave_start(3)
		await _frames(4)
		director.open_shop()
		await _frames(4)
		var s3: Dictionary = director.snapshot()
		_tally("W3 打开商店 ts=0.25", is_equal_approx(float(s3["time_scale"]), _Cfg.DILATION_SCALE_NOVICE))
		_tally("W3 不消耗预算", bool(s3["consumes_budget"]) == false)
		var b0 := float(s3["budget_left"])
		for _i in 40:
			await get_tree().process_frame
		var s3b: Dictionary = director.snapshot()
		_tally("W3 跑 40 帧后预算仍满", is_equal_approx(float(s3b["budget_left"]), b0))
		print("  W3：ts=%.2f · 预算 %.2f → %.2f（40 帧后）" % [
			float(s3["time_scale"]), b0, float(s3b["budget_left"])])

		# ---- 验收标准 3：10 实时秒 → 预算 20 → 10 ----
		print("")
		print("---- 验收标准 3：开商店 %0.0f 实时秒 → 预算 %.0f → %.0f ----" % [
			REAL_WAIT_SEC, _Cfg.DILATION_BUDGET, _Cfg.DILATION_BUDGET - REAL_WAIT_SEC])
		director.wave_start(8)
		await _frames(4)
		director.open_shop()
		await _frames(4)
		var before: Dictionary = director.snapshot()
		var msec0 := Time.get_ticks_msec()
		var game0 := float(before["game_seconds"])
		var real0 := float(before["real_seconds"])
		while (Time.get_ticks_msec() - msec0) < int(REAL_WAIT_SEC * 1000.0):
			await get_tree().process_frame
		var after: Dictionary = director.snapshot()
		var real_elapsed := float(after["real_seconds"]) - real0
		var game_elapsed := float(after["game_seconds"]) - game0
		var budget_used := float(before["budget_left"]) - float(after["budget_left"])

		print("  实时经过      = %.3f s（unscaled，Time 差值）" % real_elapsed)
		print("  战场推进      = %.3f s（scaled，Σdelta）" % game_elapsed)
		print("  预算消耗      = %.3f s" % budget_used)
		print("  预算剩余      = %.3f / %.0f s" % [float(after["budget_left"]), float(after["budget_max"])])
		print("  思考增益      = ×%.2f（实时 / 游戏）" % (real_elapsed / maxf(game_elapsed, 1e-9)))
		_tally("预算按实时秒消耗（|消耗 − 实时| ≤ 0.25s）",
			absf(budget_used - real_elapsed) <= 0.25)
		_tally("战场推进 ≈ 实时 × 0.35（|差| ≤ 0.5s）",
			absf(game_elapsed - real_elapsed * _Cfg.DILATION_SCALE) <= 0.5)
		_tally("预算剩余 ≈ 20 − 实时（|差| ≤ 0.25s）",
			absf(float(after["budget_left"]) - (_Cfg.DILATION_BUDGET - real_elapsed)) <= 0.25)

		# ---- 截帧（best effort）----
		await _screenshot()

		# ---- 收尾 ----
		Engine.time_scale = 1.0
		get_tree().paused = false
		print("")
		print("=" .repeat(100))
		print("冒烟汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
		print("=" .repeat(100))
		get_tree().quit(0 if _fail == 0 else 1)


	func _goto(label: String, action: Callable) -> void:
		action.call()
		await _frames(FRAMES_PER_STATE)
		var s: Dictionary = director.snapshot()
		var expect := _expect_for(int(s["state"]))
		var ok_ts := is_equal_approx(float(s["engine_time_scale"]), float(expect[0]))
		var ok_pause := bool(s["tree_paused"]) == bool(expect[1])
		_tally("%s time_scale" % label, ok_ts)
		_tally("%s paused" % label, ok_pause)
		print("%-17s | %6.2f | %9s | %6.2f | %9s | %7s | %2d | %.2f" % [
			label,
			float(expect[0]), str(bool(expect[1])),
			float(s["engine_time_scale"]), str(bool(s["tree_paused"])),
			("是" if bool(s["consumes_budget"]) else "否"),
			int(s["drawer"]), float(s["budget_left"]),
		])
		if not ok_ts:
			print("   ❌ %s：期望 ts=%.2f 实测 %.2f" % [label, float(expect[0]), float(s["engine_time_scale"])])
		if not ok_pause:
			print("   ❌ %s：期望 paused=%s 实测 %s" % [label, str(bool(expect[1])), str(bool(s["tree_paused"]))])


	## 期望值直接来自 GDD §2.1 表格（W≥6 口径）
	func _expect_for(st: int) -> Array:
		match st:
			_TSM.State.COMBAT:
				return [_Cfg.TIME_SCALE_COMBAT, false]
			_TSM.State.SHOP_DILATED:
				return [_Cfg.DILATION_SCALE, false]
			_TSM.State.SHOP_REAL_TIME:
				return [_Cfg.TIME_SCALE_COMBAT, false]
			_TSM.State.SAFE_WINDOW:
				return [_Cfg.TIME_SCALE_COMBAT, true]
			_TSM.State.PLACEMENT_MODE:
				return [_Cfg.PLACEMENT_SCALE, false]
		return [_Cfg.TIME_SCALE_COMBAT, false]


	func _frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame


	func _tally(name: String, ok: bool) -> void:
		if ok:
			_pass += 1
		else:
			_fail += 1
			print("   [FAIL] %s" % name)


	func _screenshot() -> void:
		# Best effort：headless 没有渲染后端，截出来是空的 → 直接跳过并说明。
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
		var out := ProjectSettings.globalize_path("res://docs/phase3/slice3-skeleton.png")
		var err := img.save_png(out)
		print("")
		print("---- 截帧 ----")
		print("  ", ("已保存 " + out) if err == OK else ("保存失败 err=" + str(err)))


func _initialize() -> void:
	var scene: Node = load("res://scenes/battle_shop.tscn").instantiate()
	scene.name = "BattleShop"
	root.add_child(scene)
	var d := Driver.new()
	d.name = "Slice3SmokeDriver"
	d.root_scene = scene
	root.add_child(d)
