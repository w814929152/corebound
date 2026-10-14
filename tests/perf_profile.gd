extends SceneTree
##
## 真实帧性能剖析（Phase 6 · T-P6-02 · **只读诊断件**）
##
## 🔴 只读：不改任何生产代码 / 数值 / 玩法口径。只加载**真实场景**跑**真实帧**并打印读数。
##    报告 → `docs/phase6/performance-profile.md`（由工程侧撰写）。
##
## 🔴 必须**窗口模式**跑（要有真实渲染后端 / GL 上下文）：
##     <godot> --path D:/roguedemo --script res://tests/perf_profile.gd
##   可选参数（用 `--` 传）：
##     第 1 个 = sample_sec（每检查点采样秒数，默认 4.0）
##     第 2 个 = mode ∈ all | waves | burst | ablate（默认 all）
##
## 口径对齐产品（镜像 `boot.gd` 窗口分支）：RADIAL 八槽 + 三原型 + Elite + 仇恨 + 战斗内复活 全 ON。
##   （battle_shop.tscn 直接实例化时这些开关是**默认值**，本件显式打开以对齐实机。）
##
## ⚠️ 已知边界（诚实标注）：本件**不建塔**（无玩家点选/购买）→ 塔位渲染与仇恨塔交互为 0；
##    怪物在场数由波次设计决定（见报告 §3）。仅作渲染/子步负载画像，不测经济。
##

const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _Monster := preload("res://scripts/gameplay/monster.gd")

const CHECKPOINTS: Array = [1, 5, 10, 15, 20]
const ABLATE_WAVE := 5                # 消融用 W5（观测在场怪最多 ~13）
const DT := 0.1                       # = WaveSim.DT（子步步长）
const SYNTH_MS: Array = [0, 10, 25, 50, 100, 200, 400]


class Driver extends Node:
	var scene: Node = null
	var director: Node = null
	var controller: Node = null
	var wd: Node = null
	var ml: Node = null
	var hud: Node = null
	var shop: Node = null
	var pulse: Node = null
	var hpbar: Node = null

	var sample_sec := 4.0
	var mode := "all"

	var _frt: Array = []          # 本窗口帧时间（ms）
	var _frm: Array = []          # 与 _frt 对齐的在场怪数
	var _prev_us := 0
	var _recording := false

	func _ready() -> void:
		call_deferred("run")

	func run() -> void:
		print("=" .repeat(96))
		print("真实帧性能剖析（T-P6-02）· Godot ", Engine.get_version_info()["string"], " · DisplayServer=", DisplayServer.get_name())
		print("CPU = ", OS.get_processor_name(), "（", OS.get_processor_count(), " 逻辑核）")
		print("GPU = ", RenderingServer.get_video_adapter_name(), " · API = ", RenderingServer.get_video_adapter_api_version())
		print("渲染器 = ", ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
		print("窗口 = ", DisplayServer.window_get_size(), " · 目标 = 1920x1080（product.godot）")
		print("=" .repeat(96))

		scene = load("res://scenes/battle_shop.tscn").instantiate()
		scene.name = "PerfScene"
		get_tree().root.add_child(scene)
		await _frames(6)

		director = scene.get_node_or_null("TimeDirector")
		controller = scene.get_node_or_null("ShopController")
		wd = scene.get_node_or_null("WaveDirector")
		ml = scene.get_node_or_null("Battlefield/MonsterLayer")
		hud = scene.get_node_or_null("HudLayer/Hud")
		shop = scene.get_node_or_null("ShopLayer/ShopOverlay")
		pulse = scene.get_node_or_null("PulseLayer/ThreatPulse")
		hpbar = scene.get_node_or_null("CoreHpLayer/CoreHpBar")
		if director == null or wd == null or controller == null:
			print("[FATAL] 缺 TimeDirector / WaveDirector / ShopController")
			get_tree().quit(1)
			return

		# ---- 对齐产品口径（镜像 boot.gd 窗口分支）----
		_SpaceModel.mode = _SpaceModel.Mode.RADIAL
		wd.prototype_split_enabled = true
		wd.elite_waves_enabled = true
		wd.tower_aggro_enabled = true
		wd.combat_revive_enabled = true
		print("口径 = RADIAL + proto + elite + aggro + revive（全 ON · 对齐实机）")

		# ---- 关 vsync + 解除帧率上限 → 帧时间 = 真实帧成本（非 60Hz 封顶）----
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		get_tree().process_frame.connect(_on_frame)

		if mode == "all" or mode == "waves":
			await _sweep_waves()
		if mode == "all" or mode == "burst":
			await _burst_probe()
		if mode == "all" or mode == "synth":
			await _synth_scaling()
		if mode == "all" or mode == "ablate":
			await _ablation()

		print("")
		print("=" .repeat(96))
		print("剖析完成（只读 · 未改任何生产代码/数值）")
		print("=" .repeat(96))
		get_tree().quit(0)

	# -----------------------------------------------------------------------
	#  帧记录
	# -----------------------------------------------------------------------
	func _on_frame() -> void:
		var now := Time.get_ticks_usec()
		if _recording and _prev_us > 0:
			_frt.append(float(now - _prev_us) / 1000.0)
			_frm.append(wd.monsters.size() if wd != null else 0)
		_prev_us = now

	func _rec_begin() -> void:
		_frt.clear()
		_frm.clear()
		_prev_us = 0
		_recording = true

	func _rec_end() -> float:
		_recording = false
		return float(_frt.size())

	# -----------------------------------------------------------------------
	#  1) 真实帧分布（W1/W5/W10/W15/W20）
	# -----------------------------------------------------------------------
	func _sweep_waves() -> void:
		print("")
		print("=" .repeat(96))
		print("【1】真实帧分布（vsync OFF · 帧时间 = 真实帧成本）")
		print("  检查点波 W1/W5/W10/W15/W20 · 每点采样 %.1f 实时秒" % sample_sec)
		print("=" .repeat(96))
		for w in CHECKPOINTS:
			_wave_start_clean(w)
			await _frames(6)
			await _real_wait(5.0)                    # 预热：让怪刷到代表性在场数（避开开波抖动）
			_rec_begin()
			var t0 := Time.get_ticks_usec()
			await _real_wait(sample_sec)
			var elapsed := float(Time.get_ticks_usec() - t0) / 1_000_000.0
			var nfr := _rec_end()
			var st := _stats(_frt)
			var fps := nfr / maxf(1e-9, elapsed)
			var peak_m := 0
			var peak_dt := 0.0
			for i in range(_frt.size()):
				if int(_frm[i]) > peak_m:
					peak_m = int(_frm[i])
				if float(_frt[i]) > peak_dt:
					peak_dt = float(_frt[i])
			# 生存怪数（采样结束时刻）
			var m_now: int = wd.monsters.size()
			print("  W%-2d | FPS ~%7.1f | 帧时间 ms: mean %.3f · p50 %.3f · p95 %.3f · p99 %.3f · max %.3f | 怪 max %d (~now %d) | 帧数 %d"
				% [w, fps, float(st["mean"]), float(st["p50"]), float(st["p95"]), float(st["p99"]), float(st["max"]), peak_m, m_now, int(nfr)])
			print("        核心 %.0f/%.0f · 已出 %d/%d · 杀 %d 漏 %d · t_wave %.1f · 态 %s"
				% [float(wd.core_hp), float(wd.cfg.get("core_hp", 0.0)), int(wd.spawned), int(wd.n),
					int(wd.kills), int(wd.leaked_count), float(wd.t_wave), wd.state_name()])

	# -----------------------------------------------------------------------
	#  2) 子步尖峰（MAX_SUBSTEPS_PER_FRAME=64）· 真实波负载
	# -----------------------------------------------------------------------
	func _burst_probe() -> void:
		print("")
		print("=" .repeat(96))
		print("【2】子步尖峰（MAX_SUBSTEPS_PER_FRAME=64 · 单帧最多追赶 64×DT=6.4 游戏秒）")
		print("  口径：advance(dt) 直接喂大 dt（模拟窗口失焦回来的一次跳变）")
		print("=" .repeat(96))
		for w in CHECKPOINTS:
			_wave_start_clean(w)
			await _frames(6)
			await _real_wait(8.0)                    # 让怪刷到代表性在场数
			_keep_alive()
			wd.acc = 0.0
			var m0: int = wd.monsters.size()
			# 单子步（acc 清零 → advance(DT) 恰走 1 步）
			var t1 := Time.get_ticks_usec()
			var s1: int = wd.advance(DT)
			var ms1 := float(Time.get_ticks_usec() - t1) / 1000.0
			var m1: int = wd.monsters.size()
			# 最坏追赶：64 子步（acc 清零 → advance(64×DT) 恰走 64 步）
			_keep_alive()
			wd.acc = 0.0
			var t2 := Time.get_ticks_usec()
			var s2: int = wd.advance(DT * 64.0)
			var ms2 := float(Time.get_ticks_usec() - t2) / 1000.0
			var m2: int = wd.monsters.size()
			print("  W%-2d | 1 子步 %.4f ms (%d 步) @M=%d | **64 子步追赶** → %d 步 · %.3f ms @M=%d→%d · 每子步 %.4f ms"
				% [w, ms1, s1, m0, s2, ms2, m1, m2, ms2 / maxf(1.0, float(s2))])
			# 复位本波（供下一点干净起跑）
			_director_force_combat()
			director.wave_start(w)                    # 重置

	# -----------------------------------------------------------------------
	#  3) 子步成本随在场怪数缩放（合成压力 · 解释"若怪更多会怎样"）
	# -----------------------------------------------------------------------
	func _synth_scaling() -> void:
		print("")
		print("=" .repeat(96))
		print("【3】子步成本 vs 在场怪数（合成填充 M 只怪 · hp/t_remain 设极大防死防漏）")
		print("  说明：真实波峰仅约 10-16 只（见报告 §3）；此处探「若 M 更大」的伸缩。")
		print("=" .repeat(96))
		# 用一个真实波做底（W20），保证 dps/n/aggro 口径真实
		_wave_start_clean(ABLATE_WAVE)
		await _frames(6)
		_keep_alive()
		wd.dps = 0.0                                  # 关伤害（不让合成怪被打死）
		# 🔴 阻止本波自动收尾（E-W1：spawned>=n 且 monsters 空 → 提前进安全窗）：
		#    n 抬高、spawned = n-1 → spawn 条件不满足（t_wave 远小于 spawned*interval）。
		wd.n = 1000000
		wd.spawned = 999999
		for M in SYNTH_MS:
			wd.t_wave = 0.0
			wd.acc = 0.0
			wd.monsters = []
			for i in range(int(M)):
				var m = _Monster.new()
				m.setup(i, "Swarm", false, 1.0e12, 1.0, 1.0e12)
				wd.monsters.append(m)
			# 单子步
			wd.acc = 0.0
			var t1 := Time.get_ticks_usec()
			var s1: int = wd.advance(DT)
			var ms1 := float(Time.get_ticks_usec() - t1) / 1000.0
			# 64 子步
			wd.acc = 0.0
			var t2 := Time.get_ticks_usec()
			var s2: int = wd.advance(DT * 64.0)
			var ms2 := float(Time.get_ticks_usec() - t2) / 1000.0
			print("  M=%-4d | 1 子步 %.4f ms (%d 步) | 64 子步 %.4f ms (%d 步) | 每子步 %.4f ms"
				% [M, ms1, s1, ms2, s2, ms2 / maxf(1.0, float(s2))])

	# -----------------------------------------------------------------------
	#  4) 热点分解（冻结模拟 · 消融法）
	# -----------------------------------------------------------------------
	func _ablation() -> void:
		print("")
		print("=" .repeat(96))
		print("【4】热点分解（W%d 稳态 · 冻结子步（wd.set_process(false)）后逐层消融）" % ABLATE_WAVE)
		print("  每次消融采样 1.2s · 帧时间 p50/p95（ms）· 与全开基线的差 = 该层占用")
		print("=" .repeat(96))
		_wave_start_clean(ABLATE_WAVE)
		await _frames(6)
		await _real_wait(10.0)                         # 刷到代表性在场数（W5 ~13）
		wd.set_process(false)                          # 🔴 冻结子步：怪物静止 → 消融间负载恒定
		await _frames(10)
		var mm: int = wd.monsters.size()
		print("  （冻结时在场怪数 M = %d）" % mm)

		var base := await _sample_frames(1.2)
		print("  [A] 全开（基线）                 p50 %.3f · p95 %.3f · max %.3f ms" % [base["p50"], base["p95"], base["max"]])

		var rB := await _ablate_one(ml, "MonsterLayer（逐怪/逐塔/场地/威胁楔）", base)
		var rC := await _ablate_one(hud, "HUD（积分/波次/横幅/进度条 + Label 文本）", base)
		var rD := await _ablate_one(shop, "ShopOverlay（商店抽屉）", base)
		var rE := await _ablate_one(pulse, "ThreatPulse（边缘红光脉冲）", base)
		var rF := await _ablate_one(hpbar, "CoreHpBar（核心 HP 条）", base)
		# 全部 UI 关（MonsterLayer 保留）
		_set_off(hud)
		_set_off(shop)
		_set_off(pulse)
		_set_off(hpbar)
		await _frames(8)
		var rG := await _sample_frames(1.2)
		print("  [G] 关全部 UI（留 MonsterLayer）    p50 %.3f · p95 %.3f · max %.3f ms  （Δp50 %+0.3f）"
			% [rG["p50"], rG["p95"], rG["max"], float(rG["p50"]) - float(base["p50"])])
		# 全关（连 MonsterLayer）
		_set_off(ml)
		await _frames(8)
		var rH := await _sample_frames(1.2)
		print("  [H] 关全部渲染层（空场）           p50 %.3f · p95 %.3f · max %.3f ms  （Δp50 %+0.3f）"
			% [rH["p50"], rH["p95"], rH["max"], float(rH["p50"]) - float(base["p50"])])
		print("")
		print("  ▶ 消融小结（Δp50 = 该层关掉后省下的帧时间）:")
		print("     MonsterLayer  Δp50 = %+.3f ms" % float(rB))
		print("     HUD           Δp50 = %+.3f ms" % float(rC))
		print("     ShopOverlay   Δp50 = %+.3f ms" % float(rD))
		print("     ThreatPulse   Δp50 = %+.3f ms" % float(rE))
		print("     CoreHpBar     Δp50 = %+.3f ms" % float(rF))
		print("     UI 合计(含HUD) Δp50 = %+.3f ms" % (float(rG["p50"]) - float(base["p50"])))
		print("     渲染层总占用   Δp50 = %+.3f ms（全开 → 空场）" % (float(rH["p50"]) - float(base["p50"])))
		# 复原
		_set_on(ml); _set_on(hud); _set_on(shop); _set_on(pulse); _set_on(hpbar)
		wd.set_process(true)

	func _ablate_one(node: Node, label: String, base: Dictionary) -> float:
		if node == null:
			return 0.0
		_set_off(node)
		await _frames(8)
		var s := await _sample_frames(1.2)
		_set_on(node)
		await _frames(4)
		print("  [关] %-34s p50 %.3f · p95 %.3f · max %.3f ms  （Δp50 %+0.3f）"
			% [label, s["p50"], s["p95"], s["max"], float(s["p50"]) - float(base["p50"])])
		return float(s["p50"]) - float(base["p50"])

	func _set_off(n: Node) -> void:
		if n == null:
			return
		n.visible = false
		n.set_process(false)
		if n is Node2D or n is Control:
			if n.has_method("queue_redraw"):
				n.queue_redraw()

	func _set_on(n: Node) -> void:
		if n == null:
			return
		n.visible = true
		n.set_process(true)
		if n.has_method("queue_redraw"):
			n.queue_redraw()

	func _sample_frames(sec: float) -> Dictionary:
		_rec_begin()
		await _real_wait(sec)
		_rec_end()
		return _stats(_frt)

	# -----------------------------------------------------------------------
	#  工具
	# -----------------------------------------------------------------------
	## 强制进入 COMBAT 并开波 w（跳过安全窗）。
	func _director_force_combat() -> void:
		if director.sm != null:
			director.sm._shop_open_pref = false
		if get_tree().paused:
			get_tree().paused = false

	func _wave_start_clean(w: int) -> void:
		_director_force_combat()
		director.wave_start(w)
		_keep_alive()

	## 🔴 诊断保持「一局不结束」：核心 HP 抬到极大 → 避免 W15/W20 因漏怪把核心打空、
	##    使后续检查点/合成/消融失去负载（对性能无影响：泄漏伤害与渲染/子步成本无关）。
	func _keep_alive() -> void:
		if wd != null:
			wd.core_hp = 1.0e9
			wd.run_failed = false
		if controller != null:
			controller.over = false
			if controller.runtime != null and controller.runtime.player != null:
				controller.runtime.player.core_hp = 1.0e9

	func _frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame

	## 等**真实**秒（ignore_time_scale）：不受 time_scale / paused 影响
	func _real_wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout

	func _stats(arr: Array) -> Dictionary:
		var out := {"mean": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
		if arr.is_empty():
			return out
		var s := arr.duplicate()
		s.sort()
		var sum := 0.0
		for v in s:
			sum += float(v)
		out["mean"] = sum / float(s.size())
		out["p50"] = _pct(s, 0.50)
		out["p95"] = _pct(s, 0.95)
		out["p99"] = _pct(s, 0.99)
		out["max"] = float(s[s.size() - 1])
		return out

	func _pct(sorted_arr: Array, p: float) -> float:
		var idx := int(ceil(p * float(sorted_arr.size()))) - 1
		idx = clampi(idx, 0, sorted_arr.size() - 1)
		return float(sorted_arr[idx])


func _initialize() -> void:
	var d := Driver.new()
	d.name = "PerfDriver"
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		d.sample_sec = float(args[0])
	if args.size() >= 2:
		d.mode = String(args[1])
	root.add_child(d)
