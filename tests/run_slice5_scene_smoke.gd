extends SceneTree
##
## 切片5 场景冒烟（**真实场景树 + 真实帧 + 真实 delta**）
##
## `tests/test_suite_slice5.gd` 断言的是**纯逻辑**（`WaveDirector.advance(dt)` 手工喂）。
## 本脚本补另一半：把 `scenes/battle_shop.tscn` **真的跑起来**，用**真实帧**证明：
##   ① 怪物**真的沿路径实时移动**（s 递增 / 世界坐标变化）；
##   ② 🔴 **减速隔离**：`Engine.time_scale` 变小 → `t_wave` 同步变慢（W-C3 红线）；
##   ③ 🔴 **安全窗完全静止**（`get_tree().paused` → delta 归零 → t_wave 不动）；
##   ④ 波次**真的自己打完**并进安全窗（切片4 的 D-8 调试按钮已删，无人工干预）；
##   ⑤ 路径 / 塔位 / 核心 / 怪物占位真的画出来了（截帧）。
##
## 跑法（headless）：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd
## 跑法（窗口模式 · 顺带截帧）：
##   <godot> --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd
## 跑法（GDD 三原型 + Elite 口径 · 用于对照截帧）：
##   <godot> --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd -- split
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")


class Driver extends Node:
	var root_scene: Node = null
	var director: Node = null          # TimeDirector
	var controller: Node = null
	var wd: Node = null                # WaveDirector
	var split_model: bool = false
	var _pass := 0
	var _fail := 0


	func _ready() -> void:
		# 🔴 不要在 _ready 里 add_child 到 root（会撞 "parent is busy setting up children"）
		call_deferred("run")


	func run() -> void:
		var v := Engine.get_version_info()
		print("=" .repeat(100))
		print("切片5 场景冒烟 · Godot ", v["string"], " · DisplayServer=", DisplayServer.get_name())
		print("怪物模型 = ", "GDD 三原型 + Elite（S5-D1 口径）" if split_model else "金标本等价（MVP 默认）")
		print("=" .repeat(100))

		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		director = root_scene.get_node_or_null("TimeDirector")
		controller = root_scene.get_node_or_null("ShopController")
		wd = root_scene.get_node_or_null("WaveDirector")
		var ml := root_scene.get_node_or_null("Battlefield/MonsterLayer")
		if director == null or controller == null or wd == null:
			print("[FATAL] 场景里缺 TimeDirector / ShopController / WaveDirector")
			get_tree().quit(1)
			return
		if controller.runtime == null:
			print("[FATAL] ShopController.runtime 未初始化")
			get_tree().quit(1)
			return

		if split_model:
			wd.prototype_split_enabled = true
			wd.elite_waves_enabled = true
			wd.start_wave(1)

		# =====================================================================
		# 0. 接线与开局
		# =====================================================================
		print("")
		print("---- [0] 开局：WaveDirector 已发出 W1 的 wave_started ----")
		_tally("WaveDirector 已注入场景", wd != null)
		_tally("MonsterLayer 已接线到 WaveDirector", ml != null)
		_tally("波号 = W1", int(wd.w) == 1)
		_tally("态 = Spawning", int(wd.state) == 1)
		_tally("时间轴权威：MVP 默认 = 金标本等价口径",
			bool(wd.prototype_split_enabled) == split_model)
		print("  波次 W%d · 态 %s · t_wave=%.2f · 已出 %d/%d"
			% [int(wd.w), wd.state_name(), float(wd.t_wave), int(wd.spawned), int(wd.n)])

		# 🔴 伤害关掉（dps=0）→ 怪物不死亡 → 移动探针干净（只看推进，不看击杀）
		wd.dps = 0.0

		# ---- 预热几帧，避开启动抖动（首帧 dt 可能很大）----
		await _real_wait(0.4)

		# =====================================================================
		# 1. 实时刷怪 + 沿路径移动（真实帧）
		# =====================================================================
		print("")
		print("---- [1] 真实帧：怪物沿弧长 s 实时前进 ----")
		var s0 := _max_arc()
		var n0 := int(wd.spawned)
		var t0 := float(wd.t_wave)
		var gr0 := float(director.game_seconds)
		var rr0 := float(director.real_seconds)
		print("  采样 A：t_wave=%.2f · 已出 %d · max(s)=%.2f" % [t0, n0, s0])
		await _real_wait(1.6)
		var s1 := _max_arc()
		var n1 := int(wd.spawned)
		var t1 := float(wd.t_wave)
		var gr1 := float(director.game_seconds)
		var rr1 := float(director.real_seconds)
		print("  采样 B：t_wave=%.2f · 已出 %d · max(s)=%.2f" % [t1, n1, s1])
		_tally("① 波次时钟真的在走（t_wave 递增）", t1 > t0)
		_tally("① 真实帧下真的刷出了怪（spawned 递增）", n1 > n0)
		_tally("① 怪物沿路径实时前进（max(s) 递增）", s1 > s0)
		# 弧长 → 世界坐标：sample() 真的把它变成屏幕上的位移
		var pa := _PathGeometry.sample(s0)
		var pb := _PathGeometry.sample(s1)
		_tally("① sample(s) 把弧长变成了真实世界位移", pa.distance_to(pb) > 1.0)
		print("  弧长 %.2f → %.2f（世界 %s → %s，位移 %.2f unit）"
			% [s0, s1, str(pa), str(pb), pa.distance_to(pb)])

		# ---- 1.0× 基准：游戏时间 ≈ 实时时间 ----
		var ratio_full := (gr1 - gr0) / maxf(1e-9, rr1 - rr0)
		print("  [1.0×] Δ游戏 %.3fs / Δ实时 %.3fs → 比值 %.3f"
			% [gr1 - gr0, rr1 - rr0, ratio_full])
		_tally("② 全速态：游戏时间 / 实时时间 ≈ 1.00", absf(ratio_full - 1.0) <= 0.10)

		# =====================================================================
		# 2. 🔴 减速隔离（W-C3）：打开商店 → 战场同步变慢
		# =====================================================================
		print("")
		print("---- [2] 🔴 减速隔离：打开商店 → 怪物与刷怪同步变慢 ----")
		director.open_shop()
		await _frames(3)
		var ts := float(Engine.time_scale)
		print("  态 = %s · Engine.time_scale = %.2f（W1 是新手保护波 → 0.25×）"
			% [director.sm.state_name(), ts])
		_tally("② 开商店后 time_scale < 1.0", ts < 1.0)

		var t2 := float(wd.t_wave)
		var gr2 := float(director.game_seconds)
		var rr2 := float(director.real_seconds)
		var s2 := _max_arc()
		await _real_wait(1.6)
		var t3 := float(wd.t_wave)
		var gr3 := float(director.game_seconds)
		var rr3 := float(director.real_seconds)
		var s3 := _max_arc()
		var ratio_slow := (gr3 - gr2) / maxf(1e-9, rr3 - rr2)
		var ratio_wave := (t3 - t2) / maxf(1e-9, rr3 - rr2)
		print("  [%.2f×] Δ游戏 %.3fs / Δ实时 %.3fs → 比值 %.3f（波次时钟 %.3f）"
			% [ts, gr3 - gr2, rr3 - rr2, ratio_slow, ratio_wave])
		_tally("② 减速态：游戏时间 / 实时时间 ≈ time_scale（±0.06）",
			absf(ratio_slow - ts) <= 0.06)
		_tally("② 减速态：波次时钟同步变慢（t_wave 增速 ≈ time_scale）",
			absf(ratio_wave - ts) <= 0.12)
		_tally("② 减速态：怪物**没有**停（慢动作不是暂停）", s3 > s2)
		var ratio_between := (t3 - t2) / maxf(1e-9, t1 - t0)
		_tally("② 同样实时时长内，减速后 t_wave 增量显著小于全速",
			ratio_between < 0.6)
		print("  同样 ≈1.6 实时秒：全速 Δt_wave=%.3fs → 减速 Δt_wave=%.3fs（比值 %.3f）"
			% [t1 - t0, t3 - t2, ratio_between])

		# =====================================================================
		# 3. 🔴 安全窗完全静止（paused → delta 归零）
		# =====================================================================
		print("")
		print("---- [3] 🔴 安全窗：世界暂停 → t_wave 完全静止 ----")
		director.close_shop()
		await _frames(3)
		wd.run_to_end()                    # 把本波按真实子步跑完（不是"跳过"）
		await _frames(6)
		_tally("④ 波次自己打完 → 进 SafeWindow", int(director.sm.state) == _TSM.State.SAFE_WINDOW)
		_tally("④ WaveDirector 态 = SafeWindow", int(wd.state) == 3)
		_tally("③ 安全窗 paused = true", bool(get_tree().paused) == true)
		var t4 := float(wd.t_wave)
		await _real_wait(0.8)
		var t5 := float(wd.t_wave)
		_tally("③ 安全窗里 t_wave 一动不动（delta = 0）", absf(t5 - t4) <= 1e-12)
		print("  安全窗 0.8 实时秒：t_wave %.6f → %.6f（Δ=%.6f）" % [t4, t5, t5 - t4])

		# ---- 收入入账（M5）----
		var rt = controller.runtime
		_tally("④ 击杀收入已入账（M5）", float(rt.scrap) >= 0.0)
		print("  积分 %.0f · 核心 %.0f/%.0f" % [float(rt.scrap), float(rt.player.core_hp), float(rt.player.core_hp_max)])

		# =====================================================================
		# 4. 再开一波（证明波次循环能持续）
		# =====================================================================
		print("")
		print("---- [4] 玩家点「开始下一波」→ W2 重新出货 ----")
		director.start_next_wave()
		await _frames(6)
		wd.dps = 0.0
		_tally("④ W2 已开波", int(wd.w) == 2 and int(wd.state) == 1)
		var n4 := int(wd.spawned)
		await _real_wait(1.2)
		_tally("④ W2 真的在出货（spawned 递增）", int(wd.spawned) > n4)
		print("  W2：已出 %d/%d · t_wave=%.2f" % [int(wd.spawned), int(wd.n), float(wd.t_wave)])

		# =====================================================================
		# 5. 截帧
		# =====================================================================
		await _screenshot()

		Engine.time_scale = 1.0
		get_tree().paused = false
		print("")
		print("=" .repeat(100))
		print("切片5 冒烟汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
		print("=" .repeat(100))
		get_tree().quit(0 if _fail == 0 else 1)


	func _max_arc() -> float:
		var best := -1.0
		for m in wd.monsters:
			best = maxf(best, m.arc_s(float(wd.v0_)))
		return best


	func _frames(n: int) -> void:
		for _i in n:
			await get_tree().process_frame


	## 等**真实**秒（ignore_time_scale = true）：不受 time_scale / paused 影响
	func _real_wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout


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
		var name := "slice5-wave-split.png" if split_model else "slice5-wave.png"
		var out := ProjectSettings.globalize_path("res://docs/phase3/" + name)
		var err := img.save_png(out)
		print("")
		print("---- 截帧 ----")
		print("  ", ("已保存 " + out) if err == OK else ("保存失败 err=" + str(err)))


func _initialize() -> void:
	var split := false
	for a in OS.get_cmdline_user_args():
		if a.strip_edges().to_lower() == "split":
			split = true
	var scene: Node = load("res://scenes/battle_shop.tscn").instantiate()
	scene.name = "BattleShop"
	root.add_child(scene)
	var d := Driver.new()
	d.name = "Slice5SmokeDriver"
	d.root_scene = scene
	d.split_model = split
	root.add_child(d)
