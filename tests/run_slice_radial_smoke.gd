extends SceneTree
##
## 径向核心围攻 · **阶段0 场景冒烟**（真实场景树 + 真实帧 + RADIAL 模式）
##
## `tests/test_suite_radial.gd` 断言的是**纯逻辑**（WaveDirector.run_to_end 喂子步）。
## 本脚本补另一半：把 `scenes/battle_shop.tscn` 在 **SpaceModel.RADIAL** 下真的跑起来，
## 用真实帧证明径向迁移在渲染层不崩溃且语义正确：
##   ① 场景正常实例化（MonsterLayer 引用 SpaceModel 不崩）；
##   ② v₀ = 5.50（R_s/t_reach）、核心 = (28,28)；
##   ③ 怪物**朝核心移动**（到核心距离单调减小，而非沿折线弧长递增）；
##   ④ 出生角 θ 已按黄金角序列注入（不同 index 角度不同）；
##   ⑤ 怪物世界坐标到核心距离 == 派生极径 ρ（pos 与 t_remain 同状态量）；
##   ⑥ 波次能自己打完进安全窗（径向不破坏波次循环）。
##
## 跑法（headless）：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice_radial_smoke.gd
##
## 🔴 跑前把 SpaceModel.mode 置 RADIAL，跑完设回 PATH（全局开关，防污染）。
##

const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")


class Driver extends Node:
	var root_scene: Node = null
	var director: Node = null
	var controller: Node = null
	var wd: Node = null
	var _pass := 0
	var _fail := 0


	func _ready() -> void:
		call_deferred("run")


	func run() -> void:
		# 🔴 切到径向模式（跑完在 _finalize 里设回 PATH）
		_SpaceModel.mode = _SpaceModel.Mode.RADIAL
		print("=" .repeat(100))
		print("径向核心围攻 · 阶段0 场景冒烟 · SpaceModel.mode = RADIAL")
		print("  v₀=%.2f · 核心=(%.0f,%.0f) · R_s=%.1f"
			% [_SpaceModel.v0(), _SpaceModel.RADIAL_CORE.x,
			   _SpaceModel.RADIAL_CORE.y, _SpaceModel.SPAWN_RADIUS])
		print("=" .repeat(100))

		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		director = root_scene.get_node_or_null("TimeDirector")
		controller = root_scene.get_node_or_null("ShopController")
		wd = root_scene.get_node_or_null("WaveDirector")
		var ml := root_scene.get_node_or_null("Battlefield/MonsterLayer")

		# ---- 前置：场景与接线 ----
		_tally("场景实例化 · WaveDirector 存在", wd != null)
		_tally("场景实例化 · MonsterLayer 存在", ml != null)
		if wd == null or ml == null:
			print("[FATAL] 场景缺 WaveDirector / MonsterLayer")
			_finalize(1)
			return
		if controller == null or controller.runtime == null:
			print("[FATAL] ShopController / runtime 未初始化")
			_finalize(1)
			return

		# ---- ② 派生量：v₀ / 核心 ----
		_tally("② RADIAL v₀ = 5.50", absf(float(wd.v0_) - 5.50) < 1e-9)
		print("  实时 v0_=%.4f（期望 5.50）" % float(wd.v0_))

		# 🔴 关掉伤害 → 怪物不死 → 移动探针干净（只看推进）
		wd.dps = 0.0
		# 开局已在场景 _ready 发出 W1；确保在跑
		if int(wd.state) != 1:
			director.start_next_wave()
		await _real_wait(0.4)

		# =====================================================================
		# ③ 怪物朝核心移动（到核心距离单调减小）
		# =====================================================================
		print("")
		print("---- [③] 径向：怪物朝核心移动（到核心距离递减）----")
		var d0 := _min_dist_to_core()
		var t0 := float(wd.t_wave)
		await _real_wait(1.6)
		var d1 := _min_dist_to_core()
		var t1 := float(wd.t_wave)
		print("  采样 A：t_wave=%.2f · 最近怪到核心距离=%.2f" % [t0, d0])
		print("  采样 B：t_wave=%.2f · 最近怪到核心距离=%.2f" % [t1, d1])
		_tally("③ 波次时钟在走（t_wave 递增）", t1 > t0)
		_tally("③ 怪物朝核心移动（最近距离随时间减小）", d1 < d0 - 0.5)

		# =====================================================================
		# ④ 出生角 θ 已按黄金角序列注入
		# =====================================================================
		print("")
		print("---- [④] 出生角 θ（黄金角低差异序列）----")
		var thetas: Array = []
		for m in wd.monsters:
			thetas.append(float(m.theta))
		var distinct := _count_distinct(thetas)
		print("  已出 %d 只 · 不同 θ 数 = %d" % [thetas.size(), distinct])
		_tally("④ 至少刷出 3 只怪", thetas.size() >= 3)
		_tally("④ 出生角互不相同（黄金角确定性铺满）", distinct >= 3)

		# =====================================================================
		# ⑤ pos 到核心距离 == 派生极径 ρ（同一状态量）
		# =====================================================================
		print("")
		print("---- [⑤] pos 与 t_remain 共用同一状态量（距离 == ρ）----")
		var checked := 0
		var maxd := 0.0
		for m in wd.monsters:
			if checked >= 5:
				break
			var want_rho: float = _SpaceModel.rho_of_t(float(m.t_remain), float(m.m_spd))
			var got_dist: float = m.pos(float(wd.v0_)).distance_to(_SpaceModel.core_pos())
			var d: float = absf(got_dist - want_rho)
			maxd = maxf(maxd, d)
			print("   怪#%d t_remain=%.3f m_spd=%.3f θ=%.2f → ρ=%.4f 距离=%.4f |d|=%s"
				% [int(m.index), float(m.t_remain), float(m.m_spd), float(m.theta),
				   want_rho, got_dist, str(d)])
			checked += 1
		print("   最大 |d| = %s（容差 1e-5）" % str(maxd))
		# 🔴 容差 1e-5：`sqrt(cos²θ+sin²θ)` 对某些 θ 不严格 = 1（浮点噪声 ~1e-6），
		#   乘上 ρ(~50) 后 ~2e-6。这是极坐标恒等式的固有残差，非 bug（逻辑冒烟用 1e-7
		#   是因为那里 t_remain 是干净值、噪声更小）。
		_tally("⑤ 前 %d 只怪：pos 到核心距离 == ρ（1e-5 · sqrt 浮点噪声）" % checked,
			maxd <= 1e-5)

		# =====================================================================
		# ⑦ 截帧（窗口模式真出图；headless 跳过）—— 视觉验收 AC-R1
		#   🔴 放在 run_to_end 之前：此时 damage=0、怪还在场上从四面涌入，画面最满。
		# =====================================================================
		print("")
		print("---- [⑦] 截帧：径向战斗实机（怪物从四面涌入）----")
		await _real_wait(0.6)
		await _screenshot()

		# =====================================================================
		# ⑥ 波次能自己打完进安全窗（径向不破坏波次循环）
		# =====================================================================
		print("")
		print("---- [⑥] 波次循环：径向下能自己打完进 SafeWindow ----")
		wd.run_to_end()
		await _frames(6)
		_tally("⑥ 打完进 SafeWindow", int(wd.state) == 3)
		print("  态 = %s · 击杀 %d · 漏怪 %d"
			% [wd.state_name(), int(wd.kills), int(wd.leaked_count)])

		_finalize(0 if _fail == 0 else 1)


	func _min_dist_to_core() -> float:
		var best: float = INF
		for m in wd.monsters:
			var d: float = m.pos(float(wd.v0_)).distance_to(_SpaceModel.core_pos())
			best = minf(best, d)
		return best if best < INF else 0.0


	func _count_distinct(arr: Array) -> int:
		var seen: Array = []
		for v in arr:
			var found := false
			for s in seen:
				if absf(float(s) - float(v)) < 1e-6:
					found = true
					break
			if not found:
				seen.append(v)
		return seen.size()


	func _frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame


	func _real_wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout


	func _tally(name: String, ok: bool) -> void:
		if ok:
			_pass += 1
		else:
			_fail += 1
		print("   [%s] %s" % ["PASS" if ok else "FAIL", name])


	## 截帧：窗口模式真出图（headless 无渲染后端 → 跳过并提示）。
	func _screenshot() -> void:
		if DisplayServer.get_name() == "headless":
			print("  headless 无渲染后端 → 跳过截帧（窗口模式跑本脚本会真出图）")
			return
		await RenderingServer.frame_post_draw
		var img = get_tree().root.get_texture().get_image()
		if img == null or img.get_width() == 0:
			print("  取不到视口纹理 → 跳过截帧")
			return
		var out := ProjectSettings.globalize_path("res://docs/phase3/radial-stage0-siege.png")
		var err := img.save_png(out)
		print("  截帧 → %s（%s）" % [out, ("已保存" if err == 0 else "保存失败 err=" + str(err))])


	func _finalize(code: int) -> void:
		# 🔴 回退全局开关，避免污染后续默认回归
		_SpaceModel.mode = _SpaceModel.Mode.PATH
		Engine.time_scale = 1.0
		get_tree().paused = false
		print("")
		print("=" .repeat(100))
		print("径向阶段0 场景冒烟汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
		print("=" .repeat(100))
		get_tree().quit(code)


func _initialize() -> void:
	# 🔴 关键时机：mode 必须在场景**开波前**设定（v0_ / theta 在 start_wave 时按 mode 算）。
	#   真实集成中径向开关应在游戏启动最早期置位；这里在实例化场景前切，模拟"开局即径向"。
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var scene: Node = load("res://scenes/battle_shop.tscn").instantiate()
	scene.name = "BattleShop"
	root.add_child(scene)
	var d := Driver.new()
	d.name = "RadialSmokeDriver"
	d.root_scene = scene
	root.add_child(d)
