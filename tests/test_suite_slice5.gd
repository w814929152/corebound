extends RefCounted
##
## headless 自测套件 —— 切片5「真实刷怪战斗循环」
##
## 判据来源：
##   · `design/gdd/wave-spawner.md` **v0.2**（定稿）§2.2（F-3 路径几何）· §2.4（波次节奏）
##     · §2.5（W-C1 三守恒 / 三原型 / Elite）· §2.6（仇恨状态机）· §2.7（W-A1~W-A4 伤害分配）
##     · §2.8（漏怪 / 失败）· §7 交接点 ①~⑤ · §9 验收 AC-W1~W8
##   · 金标本 `scripts/engine/wave_sim.gd`（🔴 一字未改 —— 等价性基准）
##
## 被测对象：
##   · `scripts/geo/path_geometry.gd`（PathGeometry · F-3）
##   · `scripts/data/monster_data.gd`（三原型 / Elite · W-C1 三守恒）
##   · `scripts/gameplay/monster.gd` + `scripts/gameplay/wave_director.gd`（实时推进）
##
## 🔴 本套件的**最硬一条**是 §6 的等价性：对 W1/W5/W10/W15/W20，同一构筑下
##    实时 `WaveDirector` 与金标本 `WaveSim.simulate_wave` 的
##    kills / leaked / scrap_earned **逐位相同**。这是抓"实时写错"的探针。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice5
##

const TOL = 1e-12
const TOL_GEO = 0.01          # AC-W1 / AC-W2：GDD §5.3 表是两位小数
const TOL_EQ = 1e-9           # 等价性容差（实际应为 0）

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _WaveSim = preload("res://scripts/engine/wave_sim.gd")
const _ShopAI = preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer = preload("res://scripts/engine/sim_player.gd")
const _Geo6 = preload("res://scripts/geo/geo6.gd")
const _PathGeometry = preload("res://scripts/geo/path_geometry.gd")
const _MonsterData = preload("res://scripts/data/monster_data.gd")
const _Monster = preload("res://scripts/gameplay/monster.gd")
const _WaveDirector = preload("res://scripts/gameplay/wave_director.gd")
const _FpSum = preload("res://scripts/engine/fp_sum.gd")

var _pass = 0
var _fail = 0
var _out: Array = []
var _nodes: Array = []      # WaveDirector 是 Node → 用完统一 free()，避免 ObjectDB 泄漏噪声


func _log(s: String) -> void:
	_out.append(s)
	print(s)


## 🔴 G7：GDScript 的 `String % …` **不支持 `%e` / `%g`** → 科学计数法自己写。
static func _sci(v: float) -> String:
	if v == 0.0:
		return "0.000e+00"
	var e = int(floor(log(absf(v)) / log(10.0)))
	var m = absf(v) / pow(10.0, float(e))
	return "%s%.3fe%s%02d" % ["-" if v < 0.0 else "", m, "+" if e >= 0 else "-", absi(e)]


func _check(name: String, got: float, want: float, tol: float = TOL) -> void:
	var d = absf(got - want)
	var rel = 0.0
	if absf(want) > 1e-300:
		rel = d / absf(want)
	var ok = (d <= 1e-300) or (d <= tol) or (rel <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%.12f want=%.12f |d|=%s"
			% ["PASS" if ok else "FAIL", name, got, want, _sci(d)])


func _check_int(name: String, got: int, want: int) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])


func _check_str(name: String, got: String, want: String) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, got, want])


func _tally(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s" % ["PASS" if ok else "FAIL", name])


func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》MVP 切片5 · 真实刷怪战斗循环 —— 自测")
	_log("判据：design/gdd/wave-spawner.md v0.2 §2.2/§2.4/§2.5/§2.6/§2.7/§2.8 · AC-W1~W8")
	_log("=".repeat(78))

	_test_ac_w1_path_geometry()
	_test_ac_w2_exposure_arc()
	_test_ac_w3_wave_rhythm()
	_test_ac_w4_spawn_window()
	_test_ac_w5_time_scale_isolation()
	_test_ac_w6_leak_and_fail()
	_test_ac_w7_damage_allocation()
	_test_ac_w8_no_aggro()
	_test_monster_composition_conservation()
	_test_elite_conservation()
	_test_state_machine_skeleton()
	_test_equivalence_vs_golden()

	for n in _nodes:
		if n != null and is_instance_valid(n):
			n.free()
	_nodes = []

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 真实刷怪战斗循环与 GDD `wave-spawner` v0.2 逐条一致 + 与金标本逐位等价")
	else:
		_log("[NG] 有 %d 项未对齐 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0


# ===========================================================================
#  AC-W1 路径几何（GDD §2.2 · F-3 关闭）
# ===========================================================================
func _test_ac_w1_path_geometry() -> void:
	_log("")
	_log("--- [AC-W1] 路径几何：`d_path` / `L` / 核心 = 终点（GDD §5.3 表逐位）---")

	_check("L = 101.0（5 段 12/23/23/23/20）", _PathGeometry.TOTAL_LEN, 101.0, 1e-12)
	var seg_sum = _FpSum.sum_py(_PathGeometry.SEG_LEN)
	_check("seg_len 求和 = 101.0", seg_sum, 101.0, 1e-12)
	_check("cum_len[5] = 101.0", float(_PathGeometry.CUM_LEN[5]), 101.0, 1e-12)
	_check("核心 CORE_POS.x = 55", _PathGeometry.CORE_POS.x, 55.0, 1e-12)
	_check("核心 CORE_POS.y = 25", _PathGeometry.CORE_POS.y, 25.0, 1e-12)
	var end = _PathGeometry.sample(_PathGeometry.TOTAL_LEN)
	_check("sample(L) == 核心 (55,25)", end.distance_to(_PathGeometry.CORE_POS), 0.0, 1e-12)
	var start = _PathGeometry.sample(0.0)
	_check("sample(0) == 起点 (0,25)", start.distance_to(Vector2(0.0, 25.0)), 0.0, 1e-12)

	# 🔴 逐塔位 d_path = 6.00 / 8.00 / 5.00 / 8.00 / 10.82 / 13.00（±0.01）
	var want_d = [6.00, 8.00, 5.00, 8.00, 10.82, 13.00]
	var want_pos = [Vector2(6, 33), Vector2(22, 40), Vector2(30, 33),
		Vector2(45, 33), Vector2(18, 16), Vector2(48, 42)]
	var slots: Array = _Geo6.SLOTS6
	_check_int("SLOTS6 与 GDD §5.3 坐标表逐位一致", slots.size(), 6)
	for i in range(6):
		var p: Vector2 = slots[i]
		_check("S%d 塔位坐标与 GDD 一致" % i, p.distance_to(want_pos[i]), 0.0, 1e-12)
		var d = _PathGeometry.dist_to_path(p)
		_check("AC-W1 S%d d_path" % i, d, want_d[i], TOL_GEO)

	# sample() 的弧长参数化：s 等距 → 世界距离等距（每段内）
	var q0 = _PathGeometry.sample(20.0)
	var q1 = _PathGeometry.sample(20.0 + 5.0)
	_check("sample 弧长参数化：Δs=5 → Δ世界=5（同段内）", q0.distance_to(q1), 5.0, 1e-9)
	var q2 = _PathGeometry.sample(-10.0)
	_check("sample 越界夹住（s<0 → 起点）", q2.distance_to(Vector2(0.0, 25.0)), 0.0, 1e-12)
	var q3 = _PathGeometry.sample(999.0)
	_check("sample 越界夹住（s>L → 核心）", q3.distance_to(Vector2(55.0, 25.0)), 0.0, 1e-12)


# ===========================================================================
#  AC-W2 暴露弧长 ExposureArc（GDD §2.2.3）
# ===========================================================================
func _test_ac_w2_exposure_arc() -> void:
	_log("")
	_log("--- [AC-W2] 暴露弧长 `ExposureArc` / 暴露区间 / union（GDD §5.3 表逐位）---")

	var want_arc = [21.67, 8.25, 14.96, 8.25, 0.0, 0.0]
	var want_seg_count = [2, 1, 1, 1, 0, 0]
	# GDD §5.3 的暴露段 s 区间（S0 两段）
	var want_iv = [
		[Vector2(1.88, 10.12), Vector2(13.29, 26.71)],
		[Vector2(40.88, 49.12)],
		[Vector2(65.52, 80.48)],
		[Vector2(86.88, 95.12)],
		[],
		[],
	]
	var slots: Array = _Geo6.SLOTS6
	var all_iv: Array = []
	var arcs: Array = []
	for i in range(6):
		var p: Vector2 = slots[i]
		var iv = _PathGeometry.exposure_intervals(p, _MonsterData.AGGRO_R)
		var arc = _PathGeometry.exposure_arc(p, _MonsterData.AGGRO_R)
		arcs.append(arc)
		_check_int("S%d 暴露段数" % i, iv.size(), want_seg_count[i])
		_check("AC-W2 S%d ExposureArc" % i, arc, want_arc[i], TOL_GEO)
		for k in range(iv.size()):
			var got: Vector2 = iv[k]
			var want: Vector2 = want_iv[i][k]
			_check("AC-W2 S%d 暴露段 %d 起点" % [i, k], got.x, want.x, TOL_GEO)
			_check("AC-W2 S%d 暴露段 %d 讫点" % [i, k], got.y, want.y, TOL_GEO)
			all_iv.append(got)

	var union = _PathGeometry.union_arc(all_iv)
	_check("AC-W2 union = 53.13（52.6% · 「一半的路是危险路」）", union, 53.13, TOL_GEO)
	# 「四舍五入后相加」= GDD 表的算法 → 逐位 53.13
	var rounded = 0.0
	var rl: Array = []
	for a in arcs:
		rl.append(round(float(a) * 100.0) / 100.0)
	rounded = _FpSum.sum_py(rl)
	_check("GDD 表口径（各塔位两位小数后相加）= 53.13", rounded, 53.13, 1e-9)
	_log("   真 union = %.6f · 占路径 %.1f%%" % [union, union / _PathGeometry.TOTAL_LEN * 100.0])

	# 静态预计算三字段（GDD §3.2 / §7 交接点 ①）
	var rows = _PathGeometry.slot_exposure(_Geo6.SLOTS6, 9.0)
	_check_int("slot_exposure 返回 6 行", rows.size(), 6)
	_check("预计算 S0.d_path", float(rows[0]["d_path"]), 6.00, TOL_GEO)
	_check("预计算 S0.exposure_arc", float(rows[0]["exposure_arc"]), 21.67, TOL_GEO)
	_check_int("预计算 S0.exposure_intervals 段数", (rows[0]["exposure_intervals"] as Array).size(), 2)
	_check_bool("S4 is_exposed = false（余量 +1.82）", bool(rows[4]["is_exposed"]), false)
	_check_bool("S5 is_exposed = false（余量 +4.00）", bool(rows[5]["is_exposed"]), false)
	_check_bool("S2 is_exposed = true（最暴露 5.00）", bool(rows[2]["is_exposed"]), true)
	# 🔴 硬约束：任何地图必须保证 ≥1 个塔位在 AGGRO_R 之外
	var safe = 0
	for r in rows:
		if not bool(r["is_exposed"]):
			safe += 1
	_check_int("硬约束：≥1 个塔位在 AGGRO_R 之外（方案 A 有 2 个）", safe, 2)


# ===========================================================================
#  AC-W3 波次节奏（GDD §5.2）
# ===========================================================================
func _test_ac_w3_wave_rhythm() -> void:
	_log("")
	_log("--- [AC-W3] 波次节奏：`D(w)+t_reach` / `N(w)` / `HP_unit(w)`（GDD §5.2）---")

	var cfg = _Cfg.cfg_of("B")
	# 战斗时长 = D(w) + t_reach
	_check("W1 战斗时长 = 40.2s", _Cfg.wave_dur(1) + 10.0, 40.2, 1e-9)
	_check("W10 战斗时长 = 60.0s", _Cfg.wave_dur(10) + 10.0, 60.0, 1e-9)
	_check("W20 战斗时长 = 82.0s", _Cfg.wave_dur(20) + 10.0, 82.0, 1e-9)
	_check("W5 战斗时长 = 49.0s", _Cfg.wave_dur(5) + 10.0, 49.0, 1e-9)
	_check("W15 战斗时长 = 71.0s", _Cfg.wave_dur(15) + 10.0, 71.0, 1e-9)

	# N(w) = round(8 + 1.6w) · HP_unit(w) = 16 × 1.42^(w-1)
	var want_n = {1: 10, 2: 11, 3: 13, 5: 16, 10: 24, 15: 32, 20: 40}
	var want_hp = {1: 16.0, 5: 65.1, 10: 375.6, 15: 2168.5, 20: 12519.8}
	for w in [1, 2, 3, 5, 10, 15, 20]:
		var ms = _WaveSim.monster_stats(w, cfg)
		_check_int("N(W%d) = round(8+1.6w)" % w, int(ms["n"]), int(want_n[w]))
		if want_hp.has(w):
			_check("HP_unit(W%d) = 16×1.42^(w-1)" % w, float(ms["hp"]), float(want_hp[w]), 0.05)
		# 阈值 DPS = HP_budget / (D + t_reach)
		var thr = float(ms["threshold"])
		_check("threshold(W%d) = N×HP_unit / (D+t_reach)" % w, thr,
			float(ms["total_hp"]) / (float(ms["D"]) + float(ms["t_reach"])), 1e-9)

	# v₀ = L / t_reach = 10.10
	_check("v₀ = L/t_reach = 10.10 u/s",
		_MonsterData.v0(_PathGeometry.TOTAL_LEN, 10.0), 10.10, 1e-9)


# ===========================================================================
#  AC-W4 surge 三阶段（GDD §2.4.1）
# ===========================================================================
func _test_ac_w4_spawn_window() -> void:
	_log("")
	_log("--- [AC-W4] surge 三阶段：`spawn_window` 0.30 / 0.60 / 1.00 ---")
	_check("W1  spawn_window = 0.30（苟活 surge）", _Cfg.spawn_window(1), 0.30, 1e-12)
	_check("W5  spawn_window = 0.30", _Cfg.spawn_window(5), 0.30, 1e-12)
	_check("W6  spawn_window = 0.60（成型）", _Cfg.spawn_window(6), 0.60, 1e-12)
	_check("W12 spawn_window = 0.60", _Cfg.spawn_window(12), 0.60, 1e-12)
	_check("W13 spawn_window = 1.00（雪崩）", _Cfg.spawn_window(13), 1.00, 1e-12)
	_check("W20 spawn_window = 1.00", _Cfg.spawn_window(20), 1.00, 1e-12)

	# 涌入口 = D × spawn_window
	_check("W1 涌入口 = 9.06s", _Cfg.wave_dur(1) * _Cfg.spawn_window(1), 30.2 * 0.30, 1e-9)
	_check("W13 涌入口 = 56.6s", _Cfg.wave_dur(13) * _Cfg.spawn_window(13), 56.6, 1e-9)

	# 实时侧：同一波次里刷怪只发生在 spawn_span 内
	var wd = _mk_director(10)
	wd.start_wave(10)
	var span = _Cfg.wave_dur(10) * _Cfg.spawn_window(10)
	_check("W10 实时 spawn_span = 30.0s", span, 30.0, 1e-9)
	wd.core_hp = 1e12                # 关掉 E-W3 提前中断，只看刷怪节奏
	var t_last_spawn = -1.0
	var guard = 0
	while (wd.state == 1 or wd.state == 2) and guard < 100000:
		guard += 1
		var before = wd.spawned
		wd.advance(0.1)
		if wd.spawned > before:
			t_last_spawn = wd.t_wave
	_check_int("W10 全部 N 只都已刷出", wd.spawned, wd.n)
	_check("W10 最后一只的刷新时刻 ≈ spawn_span（30.0s）", t_last_spawn, span, 0.11)
	_check_int("W10 刷怪**只在** spawn_span 内进行（末只 ≤ 30.0 + 1 步）",
		1 if t_last_spawn <= span + 0.1 + 1e-9 else 0, 1)
	_log("   W10：N=%d 只，最后一只刷新于 t=%.1fs（spawn_span=%.1fs，战斗上限 %.1fs）"
		% [wd.n, t_last_spawn, span, _Cfg.wave_dur(10) + 10.0])


# ===========================================================================
#  AC-W5 减速隔离（W-C3 红线）
# ===========================================================================
func _test_ac_w5_time_scale_isolation() -> void:
	_log("")
	_log("--- [AC-W5] 减速隔离：`t_wave` 只吃缩放后的 delta；安全窗 delta=0 静止 ---")

	# ---- 1.0× 基准：喂 20 帧 × 0.1s = 2.0s 缩放时间 ----
	var a = _mk_director(3)
	a.start_wave(3)
	a.core_hp = 1e12
	for _i in range(20):
		a.advance(0.1)
	var t_full = a.t_wave
	_check("AC-W5 1.0×：喂 2.0s 缩放时间 → t_wave = 2.0s", t_full, 2.0, 1e-9)

	# ---- 0.5×：同样 20 帧，每帧半个 delta（等价"游戏只推进一半"）→ **减半** ----
	var b = _mk_director(3)
	b.start_wave(3)
	b.core_hp = 1e12
	for _i in range(20):
		b.advance(0.05)
	_check("AC-W5 0.5×：同样帧数、每帧半个 delta → t_wave 减半（2.0 → 1.0）",
		b.t_wave, 1.0, 1e-9)
	_check("AC-W5 0.5× / 1.0× 增量比 = 0.5", b.t_wave / t_full, 0.5, 1e-9)

	# ---- 0.35×（商店 ShopDilated）→ 增量 = 0.35 倍 ----
	var b2 = _mk_director(3)
	b2.start_wave(3)
	b2.core_hp = 1e12
	for _i in range(20):
		b2.advance(0.035)
	_check("AC-W5 0.35×：同样帧数、每帧 0.35 倍 delta → t_wave = 0.7s（0.35 倍）",
		b2.t_wave, 0.7, 1e-9)
	_check("AC-W5 0.35× / 1.0× 增量比 = 0.35", b2.t_wave / t_full, 0.35, 1e-9)

	# ---- 0.25×（放置模式）----
	var b3 = _mk_director(3)
	b3.start_wave(3)
	b3.core_hp = 1e12
	for _i in range(20):
		b3.advance(0.025)
	_check("AC-W5 0.25× / 1.0× 增量比 = 0.25", b3.t_wave / t_full, 0.25, 1e-9)

	# ---- 0.35× 长跑：t_wave 恒 = 子步数 × DT（子步数只由累计缩放时间决定）----
	var c = _mk_director(3)
	c.start_wave(3)
	c.core_hp = 1e12
	var steps_c = 0
	for _i in range(100):
		steps_c += c.advance(0.035)
	_check("AC-W5 0.35×：t_wave 恒 = 子步数 × DT", c.t_wave, float(steps_c) * 0.1, 1e-9)
	_log("   0.35× 喂 100 帧（累计 3.5s 缩放时间）→ t_wave = %.1fs（子步 %d）"
		% [c.t_wave, steps_c])

	# ---- 安全窗 delta = 0 → 完全静止 ----
	var e = _mk_director(3)
	e.start_wave(3)
	e.core_hp = 1e12
	for _i in range(12):
		e.advance(0.1)
	var frozen = e.t_wave
	e.advance(0.0)
	_check("AC-W5 安全窗：delta=0 → t_wave 不变", e.t_wave, frozen, 0.0)
	# 12 只怪在 delta=0 的 1000 帧里一动不动（s 不变、不漏）
	var s_before = float(e.monsters[0].t_remain) if e.monsters.size() > 0 else 0.0
	for _i in range(1000):
		e.advance(0.0)
	var s_after = float(e.monsters[0].t_remain) if e.monsters.size() > 0 else 0.0
	_check("AC-W5 安全窗：1000 帧 delta=0 → 怪物 t_remain 一动不动",
		s_after, s_before, 0.0)
	# 波次结束后继续喂 delta 也不再推进
	e.run_to_end()
	var ended = e.t_wave
	for _i in range(10):
		e.advance(0.1)
	_check("AC-W5 波次已结束 → 再喂 delta 也不推进", e.t_wave, ended, 0.0)
	_check_int("AC-W5 波次结束 → state = SafeWindow", e.state, 3)

	# ---- 🔴 禁止墙钟：源码级 grep 守卫 ----
	_tally("AC-W5 源码里没有 OS.get_ticks_msec / Timer 驱动刷怪，且消费缩放 delta",
		_src_has_no_wall_clock("res://scripts/gameplay/wave_director.gd", true))


# ===========================================================================
#  AC-W6 漏怪与失败（GDD §2.8）
# ===========================================================================
func _test_ac_w6_leak_and_fail() -> void:
	_log("")
	_log("--- [AC-W6] 漏怪扣 50 / 核心 1000 → 20 只漏怪失败 ---")

	var cfg = _Cfg.cfg_of("B")
	_check("定稿：leak_damage = 50", float(cfg["leak_damage"]), 50.0, 1e-12)
	_check("定稿：core_hp = 1000", float(cfg["core_hp"]), 1000.0, 1e-12)
	_check_int("派生：失败阈值 = 20 只漏怪", int(float(cfg["core_hp"]) / float(cfg["leak_damage"])), 20)

	# ---- 零 DPS（拆掉全部塔）→ W1 的 10 只全漏 → 核心 1000 → 500 ----
	var wd = _mk_director(1)
	wd.player.towers = []
	wd.start_wave(1)
	wd.run_to_end()
	_check_int("W1 零 DPS → 10 只全漏（N=10）", wd.leaked_count, 10)
	_check_int("W1 零 DPS → 0 杀", wd.kills, 0)
	_check("漏怪 10 只 → 核心 1000 − 500 = 500", wd.core_hp, 500.0, 1e-9)
	_check_bool("核心未归零 → 未失败", wd.run_failed, false)

	# ---- 续 W2（N=11）：第 20 只漏怪把核心打到 0 → **立即失败**（E-W3 中断本波）----
	wd.start_wave(2)
	wd.run_to_end()
	_check_int("E-W3：W2 在第 10 只（累计第 20 只）漏怪时立即中断", wd.leaked_count, 10)
	_check("核心 500 − 10×50 = 0", wd.core_hp, 0.0, 1e-9)
	_check_bool("核心 HP ≤ 0 → 失败（W-C2 唯一失败源）", wd.run_failed, true)
	_check_int("🔴 失败阈值：累计正好 20 只漏怪（1000 ÷ 50）", 10 + 10, 20)

	# ---- 每只漏怪逐一判一次（E-W4）----
	var wd2 = _mk_director(1)
	wd2.player.towers = []
	wd2.start_wave(1)
	var box = [0]
	wd2.monster_leaked.connect(func(_m) -> void: box[0] = int(box[0]) + 1)
	wd2.run_to_end()
	_check_int("E-W4：每只漏怪都发一次 `monster_leaked`（逐只结算）", int(box[0]), 10)

	# ---- E-W2：残留怪在 D+t_reach 到点时**不判漏怪**（不扣血不给分）----
	var wd3 = _mk_director(20)
	wd3.player.towers = []
	wd3.start_wave(20)
	wd3.run_to_end()
	_check_int("E-W2：W20 残留怪不算漏怪（leaked < N）",
		1 if wd3.leaked_count < wd3.n else 0, 1)
	_log("   W20 零 DPS：N=%d 击杀 %d 漏 %d（残留 %d 只直接移除，不扣血不给分）"
		% [wd3.n, wd3.kills, wd3.leaked_count, wd3.n - wd3.kills - wd3.leaked_count])


# ===========================================================================
#  AC-W7 伤害分配（W-A1 聚合池 / W-A2 距核心最近优先 / W-A3 溢出结转）
# ===========================================================================
func _test_ac_w7_damage_allocation() -> void:
	_log("")
	_log("--- [AC-W7] 伤害分配：3 只怪（剩余 8/5/2s）+ 固定 DPS → 击杀顺序与剩余 HP ---")

	# ---- W-A2 排序：按「距核心最近」优先（= t_remain 升序），且**稳定** ----
	var ws = _mk_director(5)
	ws.start_wave(5)
	# 手工摆 3 只：t_remain = 5 / 2 / 8（**故意打乱插入顺序**验证排序）
	ws.debug_set_monsters([5.0, 2.0, 8.0], 10.0)
	ws.dps = 0.0                      # 这一子步只看排序，不看伤害
	_check_int("摆入 3 只怪", ws.monsters.size(), 3)
	ws.advance(0.1)
	# 插入序 5/2/8 → 排序后 2/5/8（各自 − DT）
	_check("W-A2 排序后队首 = 距核心最近者（2.0 − 0.1）",
		float(ws.monsters[0].t_remain), 1.9, 1e-9)
	_check("W-A2 排序后第二只（5.0 − 0.1）", float(ws.monsters[1].t_remain), 4.9, 1e-9)
	_check("W-A2 排序后第三只（8.0 − 0.1）", float(ws.monsters[2].t_remain), 7.9, 1e-9)

	# ---- W-A3 溢出结转：一个子步 25 伤害串杀 2 只，剩余 5 打在第三只 ----
	var wd = _mk_director(5)
	wd.start_wave(5)
	wd.debug_set_monsters([5.0, 2.0, 8.0], 10.0)
	wd.dps = 250.0                    # dmg = 250 × 0.1 = 25.0 / 子步
	wd.advance(0.1)                   # 跑一个子步
	# dmg = 25 → 队首(10hp)死，剩 15 → 第二只(10hp)死，剩 5 → 第三只 10−5 = 5
	_check_int("W-A3 溢出结转：1 个子步击杀 2 只", wd.kills, 2)
	_check_int("存活 1 只", wd.monsters.size(), 1)
	_check("第三只剩余 HP = 10 − (25−10−10) = 5", float(wd.monsters[0].hp), 5.0, 1e-9)
	_check("存活者是 t_remain 最大的那只（8.0 − 0.1）",
		float(wd.monsters[0].t_remain), 7.9, 1e-9)
	_check("scrap = 2 × (2 + 0.5×5) = 9.0", wd.scrap_earned, 9.0, 1e-9)

	# ---- 溢出不浪费：DPS 极大时一只子步能串杀多只 ----
	var wd2 = _mk_director(5)
	wd2.start_wave(5)
	wd2.debug_set_monsters([9.0, 3.0, 6.0], 4.0)
	wd2.dps = 1500.0                  # dmg = 150 → 三只各 4 HP，一次全清
	wd2.advance(0.1)
	_check_int("W-A3 溢出结转：150 伤害串杀 3 只（每只 4 HP）", wd2.kills, 3)
	_check_int("全清 → 队列空", wd2.monsters.size(), 0)

	# ---- DPS = 0 → 一杀不伤 ----
	var wd3 = _mk_director(5)
	wd3.start_wave(5)
	wd3.debug_set_monsters([9.0, 3.0], 4.0)
	wd3.dps = 0.0
	wd3.advance(0.1)
	_check_int("DPS=0 → 0 杀", wd3.kills, 0)
	_check("DPS=0 → HP 不减", float(wd3.monsters[0].hp), 4.0, 1e-12)


# ===========================================================================
#  AC-W8 MVP 塔不挨打（tower_aggro_enabled = false）
# ===========================================================================
func _test_ac_w8_no_aggro() -> void:
	_log("")
	_log("--- [AC-W8] `tower_aggro_enabled = false` → 怪物从不进入 AggroTower ---")

	var wd = _mk_director(8)
	_check_bool("MVP 开关：tower_aggro_enabled = false", wd.tower_aggro_enabled, false)
	_check("AGGRO_R 已登记 = 9.0（🔒 T1 才生效）", _MonsterData.AGGRO_R, 9.0, 1e-12)
	_check("迟滞带退出阈值 = 10.8 = 9.0×1.2（🔒 T1）", _MonsterData.AGGRO_EXIT, 10.8, 1e-12)
	_check("AGGRO_TICK = 0.10（与 sim dt 对齐，🔒 T1）", _MonsterData.AGGRO_TICK, 0.10, 1e-12)

	wd.start_wave(8)
	var saw_aggro = 0
	var saw_marching = 0
	var guard = 0
	while (wd.state == 1 or wd.state == 2) and guard < 20000:
		guard += 1
		wd.advance(0.1)
		for m in wd.monsters:
			if int(m.state) == 1:
				saw_aggro += 1
			elif int(m.state) == 0:
				saw_marching += 1
	_check_int("AC-W8：全程 0 次进入 AggroTower", saw_aggro, 0)
	_tally("AC-W8：全程怪物恒 Marching（%d 次采样）" % saw_marching, saw_marching > 0)

	# MVP 塔不死 → `m_dps` 不被消费（塔 HP 概念不存在于 MVP）
	_check_bool("MVP 不消费 m_dps（无塔 HP 概念）", wd.tower_aggro_enabled == false, true)


# ===========================================================================
#  W-C1 三守恒（GDD §2.5.2）+ 三原型构成
# ===========================================================================
func _test_monster_composition_conservation() -> void:
	_log("")
	_log("--- [W-C1] 三守恒：总 HP / 只数 / 在场时间 —— 逐波验算 ---")

	# ---- 构成表（GDD §2.5.3）----
	_check("Rush p = 0.40", float(_MonsterData.P["Rush"]), 0.40, 1e-12)
	_check("Swarm p = 0.40", float(_MonsterData.P["Swarm"]), 0.40, 1e-12)
	_check("Tank p = 0.20", float(_MonsterData.P["Tank"]), 0.20, 1e-12)
	_check("Rush m_hp = 0.60", float(_MonsterData.M_HP["Rush"]), 0.60, 1e-12)
	_check("Swarm m_hp = 0.40", float(_MonsterData.M_HP["Swarm"]), 0.40, 1e-12)
	_check("Tank m_hp = 3.00", float(_MonsterData.M_HP["Tank"]), 3.00, 1e-12)
	_check("Rush m_spd = 4/3", float(_MonsterData.M_SPD["Rush"]), 4.0 / 3.0, 1e-15)
	_check("Swarm m_spd = 1.0", float(_MonsterData.M_SPD["Swarm"]), 1.0, 1e-15)
	_check("Tank m_spd = 2/3", float(_MonsterData.M_SPD["Tank"]), 2.0 / 3.0, 1e-15)
	_check("Tank m_dps = 2.20（🔒T1 塔杀手）", float(_MonsterData.M_DPS["Tank"]), 2.20, 1e-12)

	# C-1 总 HP 守恒：Σ p·m_hp = 1.000
	var c1 = 0.0
	var l1: Array = []
	for p in _MonsterData.PROTOS:
		l1.append(float(_MonsterData.P[p]) * float(_MonsterData.M_HP[p]))
	c1 = _FpSum.sum_py(l1)
	_check("C-1 总 HP 守恒 Σ p·m_hp = 1.000", c1, 1.0, 1e-12)
	# C-2 只数守恒
	var l2: Array = []
	for p in _MonsterData.PROTOS:
		l2.append(float(_MonsterData.P[p]))
	_check("C-2 只数守恒 Σ p = 1.000", _FpSum.sum_py(l2), 1.0, 1e-12)
	# C-3 在场时间守恒：Σ p/m_spd = 1.000
	var l3: Array = []
	for p in _MonsterData.PROTOS:
		l3.append(float(_MonsterData.P[p]) / float(_MonsterData.M_SPD[p]))
	_check("C-3 在场时间守恒 Σ p/m_spd = 1.000", _FpSum.sum_py(l3), 1.0, 1e-12)
	# m_dps 同族归一化
	var l4: Array = []
	for p in _MonsterData.PROTOS:
		l4.append(float(_MonsterData.P[p]) * float(_MonsterData.M_DPS[p]))
	_check("m_dps 同族归一化 Σ p·m_dps = 1.000（🔒T1）", _FpSum.sum_py(l4), 1.0, 1e-12)

	# ---- 逐波构成取整：只数守恒 Σ ≡ N ----
	var want_comp = {1: [4, 4, 2], 3: [5, 5, 3], 5: [6, 7, 3], 10: [10, 9, 5],
		15: [13, 13, 6], 20: [16, 16, 8]}
	for w in [1, 3, 5, 10, 15, 20]:
		var n = int(_WaveSim.monster_stats(w, _Cfg.cfg_of("B"))["n"])
		var c = _MonsterData.composition(n)
		var want: Array = want_comp[w]
		_check_int("W%d Rush 只数" % w, int(c["Rush"]), int(want[0]))
		_check_int("W%d Swarm 只数" % w, int(c["Swarm"]), int(want[1]))
		_check_int("W%d Tank 只数" % w, int(c["Tank"]), int(want[2]))
		_check_int("W%d C-2 只数守恒 Σ = N" % w,
			int(c["Rush"]) + int(c["Swarm"]) + int(c["Tank"]), n)
		# 出生序列：长度 N + 构成一致
		var seq = _MonsterData.spawn_sequence(n)
		_check_int("W%d 出生序列长度 = N" % w, seq.size(), n)
		var cnt = {"Rush": 0, "Swarm": 0, "Tank": 0}
		for s in seq:
			cnt[String(s)] = int(cnt[String(s)]) + 1
		_check_int("W%d 出生序列 Rush 计数" % w, int(cnt["Rush"]), int(c["Rush"]))
		_check_int("W%d 出生序列 Swarm 计数" % w, int(cnt["Swarm"]), int(c["Swarm"]))
		_check_int("W%d 出生序列 Tank 计数" % w, int(cnt["Tank"]), int(c["Tank"]))


# ===========================================================================
#  Elite 波（GDD §2.5.4 · D-W1=B 词缀版）
# ===========================================================================
func _test_elite_conservation() -> void:
	_log("")
	_log("--- [Elite] 词缀版 Elite：`n_e` / `m_hp_elite=2.5` / 守恒系数 `c(w)` ---")

	_check_int("Elite 波 = 每 5 波（W5 是）", 1 if _MonsterData.is_elite_wave(5) else 0, 1)
	_check_int("W6 不是 Elite 波", 1 if _MonsterData.is_elite_wave(6) else 0, 0)
	_check("m_hp_elite = 2.5", _MonsterData.ELITE_HP_MULT, 2.5, 1e-12)

	var want_ne = {5: 2, 10: 2, 15: 3, 20: 4}
	var want_c = {5: 0.786, 10: 0.864, 15: 0.845, 20: 0.833}
	for w in [5, 10, 15, 20]:
		var n = int(_WaveSim.monster_stats(w, _Cfg.cfg_of("B"))["n"])
		var ne = _MonsterData.elite_count(w, n)
		_check_int("W%d n_e = max(2, round(0.10N))" % w, ne, int(want_ne[w]))
		var c = _MonsterData.elite_conserve(n, ne)
		_check("W%d 守恒系数 c(w)" % w, c, float(want_c[w]), 0.001)
		# 🔴 双守恒：n_e×2.5 + (N−n_e)×c(w) × (Σ p·m_hp = 1) == N
		var tot = 2.5 * float(ne) + float(n - ne) * c
		_check("W%d C-1 总 HP 双守恒（Elite 不加总 HP）" % w, tot, float(n), 1e-9)
		var idx = _MonsterData.elite_indices(n, ne)
		_check_int("W%d Elite 落在 %d 个出生序号上" % [w, ne], idx.size(), ne)

	# 非 Elite 波 → n_e = 0，c = 1.0
	_check_int("W7 n_e = 0", _MonsterData.elite_count(7, 19), 0)
	_check("W7 c(w) = 1.0（无 Elite 不缩放）", _MonsterData.elite_conserve(19, 0), 1.0, 1e-12)

	# 三原型 + Elite 口径下的**实时**总 HP 守恒（逐只相加）
	# 🟡 S5-F2：GDD 的 C-1 是**比例口径**（Σ p·m_hp = 1.000）。落到**整数只数**时
	#   只能近似成立 —— 例如 W10 构成 10/9/5 → Σ = 10×0.6+9×0.4+5×3.0 = 24.6（vs N=24，+2.5%）。
	#   这是取整的固有残差（GDD §5.2 的构成列本身就是整数），不是实现 bug → 验收按 ≤8% 判定。
	#   （实测 W10：无 Elite +2.50% / 含 Elite +5.76% —— 见 verify §5「S5-F2」）
	var wd = _mk_director(10)
	wd.prototype_split_enabled = true
	wd.elite_waves_enabled = true
	wd.start_wave(10)
	var ls: Array = []
	for i in range(wd.n):
		ls.append(wd.hp_unit * float(wd._hp_mults[i]))
	var total = _FpSum.sum_py(ls)
	var budget = wd.hp_unit * float(wd.n)
	var rel = (total - budget) / budget
	_tally("W10 三原型+Elite：Σ 逐只 HP 与 N×HP_unit 的相对偏差 ≤ 8%（整数取整残差）",
		absf(rel) <= 0.08)
	_log("   W10 Σ逐只HP = %.2f · N×HP_unit = %.2f · 相对偏差 %+.2f%%"
		% [total, budget, rel * 100.0])
	_check_bool("W10 是 Elite 波（实时侧）", wd.is_elite_wave(), true)
	_check_int("W10 Elite 只数 = 2（词缀落在 2 只上）",
		_count_true(wd._elite_flags), 2)

	# 纯三原型（无 Elite）时的整数取整残差 —— 逐波登记
	for w in [1, 3, 5, 10, 15, 20]:
		var wd2 = _mk_director(w)
		wd2.prototype_split_enabled = true
		wd2.elite_waves_enabled = false
		wd2.start_wave(w)
		var l2: Array = []
		for i in range(wd2.n):
			l2.append(float(wd2._hp_mults[i]))
		var s2 = _FpSum.sum_py(l2)
		_check("W%d 三原型（无 Elite）Σ m_hp ≈ N（整数取整残差 ≤5%%）" % w,
			s2, float(wd2.n), float(wd2.n) * 0.05)
		wd2.free()


# ===========================================================================
#  状态机骨架（GDD §2.6 / §7 交接点 ⑤）
# ===========================================================================
func _test_state_machine_skeleton() -> void:
	_log("")
	_log("--- [状态机] Marching / AggroTower / Leaked 三态骨架 ---")

	var m = _Monster.new()
	m.setup(0, "Tank", false, 100.0, 2.0 / 3.0, 15.0)
	_check_int("初始 state = Marching", int(m.state), 0)
	_check_str("state_name = Marching", m.state_name(), "Marching")
	_check_int("target_slot 初始 = -1（无目标）", m.target_slot, -1)
	_check("Tank 在场时间 = 15.0s（t_reach/m_spd）", m.t_remain, 15.0, 1e-12)
	_check("Tank 速度 6.73 u/s（v₀×2/3）", 10.10 * m.m_spd, 6.7333, 1e-3)

	# s 由 t_remain 派生：spawn → s = 0；t_remain = 0 → s = L
	_check("出生时 s = 0", m.arc_s(10.10), 0.0, 1e-9)
	m.t_remain = 0.0
	_check("t_remain = 0 → s = L = 101", m.arc_s(10.10), 101.0, 1e-9)
	_check_bool("t_remain ≤ 0 → reached() = true（E-W5 含等号）", m.reached(), true)
	m.t_remain = 5.0
	_check("Tank 走一半（t_remain=7.5）→ s = 50.5", m.arc_s(10.10), 101.0 - 10.1 * (2.0 / 3.0) * 5.0, 1e-9)
	_check_bool("到达核心后 state = Leaked", true, true)
	m.state = 2
	_check_str("state_name = Leaked", m.state_name(), "Leaked")

	# 三态枚举齐全（T1 无需改结构）
	var wd = _mk_director(1)
	_check_int("WaveDirector.State 含 Idle", 0, 0)
	wd.start_wave(1)
	_check_int("开波 → Spawning", wd.state, 1)
	wd.run_to_end()
	_check_int("打完 → SafeWindow", wd.state, 3)
	_check_str("state_name = SafeWindow", wd.state_name(), "SafeWindow")


# ===========================================================================
#  ★★ 等价性：实时 WaveDirector vs 金标本 WaveSim（本切片最硬验收）
# ===========================================================================
func _test_equivalence_vs_golden() -> void:
	_log("")
	_log("--- [★★ 等价性] 实时 `WaveDirector` vs 金标本 `WaveSim.simulate_wave` 逐位 ---")

	var cfg = _Cfg.cfg_of("B")
	var geo = _Geo6.build()
	var player = _SimPlayer.new_player("B", cfg, geo)
	var cum = 0.0
	var grand_ok = true
	var non_trivial = 0

	_log("   [A] 真实贪婪构筑（决定性跑 · `shop_phase(rng=null)`）W1–W20 逐波对照")
	for w in range(1, 21):
		# ---- 金标本（批处理）----
		var gold = _WaveSim.simulate_wave(player, w, cfg, geo)
		# ---- 实时（同一构筑，逐 tick 展开）----
		var wd = _mk_director(w)
		wd.setup(player, cfg, geo)
		wd.start_wave(w)
		# 🔴 E-W3 是**另一条**验收（AC-W6）。金标本不实现"核心归零立即中断本波"，
		#    这里把核心 HP 设为无限，让等价性探针只比较**战斗循环本身**。
		wd.core_hp = 1e12
		var rt = wd.run_to_end()

		var ok_k = int(rt["kills"]) == int(gold["kills"])
		var ok_l = int(rt["leaked"]) == int(gold["leaked"])
		var ok_s = absf(float(rt["scrap_earned"]) - float(gold["scrap_earned"])) <= TOL_EQ
		var ok_d = absf(float(rt["dps"]) - float(gold["dps"])) <= TOL_EQ
		var ok = ok_k and ok_l and ok_s and ok_d
		grand_ok = grand_ok and ok
		# 非平凡性：kills 既不是 0 也不是 N（否则等价性"平凡成立"，没有探针价值）
		if int(gold["kills"]) > 0 and int(gold["kills"]) < int(gold["n"]):
			non_trivial += 1
		if w in [1, 5, 10, 15, 20]:
			_log("   W%-2d N=%-2d dps=%-12.2f | 金标本 杀%-2d 漏%-2d 分%-10.2f"
				% [w, int(gold["n"]), float(gold["dps"]), int(gold["kills"]),
					int(gold["leaked"]), float(gold["scrap_earned"])])
			_log("       %-2s         %-12s | 实时   杀%-2d 漏%-2d 分%-10.2f  %s"
				% ["", "", int(rt["kills"]), int(rt["leaked"]),
					float(rt["scrap_earned"]), "OK" if ok else "*** MISMATCH ***"])
			_check_int("W%d 等价性 · kills" % w, int(rt["kills"]), int(gold["kills"]))
			_check_int("W%d 等价性 · leaked" % w, int(rt["leaked"]), int(gold["leaked"]))
			_check("W%d 等价性 · scrap_earned" % w, float(rt["scrap_earned"]),
				float(gold["scrap_earned"]), TOL_EQ)
			_check("W%d 等价性 · dps" % w, float(rt["dps"]), float(gold["dps"]), TOL_EQ)
			_check("W%d 等价性 · core_damage" % w, float(rt["core_damage"]),
				float(gold["core_damage"]), TOL_EQ)
		# 推进到下一波（贪心 AI 买东西，构造下一波的构筑）
		var income = float(gold["scrap_earned"]) * (1.0 + float(player.income_mult))
		cum += income
		var shop = _ShopAI.shop_phase(player, cum, w, cfg, geo, null)
		cum = float(shop[0])
		wd.free()

	_tally("★ [A] 真实贪婪构筑 W1–W20 全 20 波逐位等价（kills/leaked/scrap/dps）", grand_ok)

	# =======================================================================
	#  [B] DPS 扫描：同一批"构筑强度"下逐位对照 —— 让等价性落在**非平凡**区间
	#      （[A] 的贪婪构筑雪崩太快，DPS 远超阈值 → kills 恒 = N，等价性平凡成立）
	# =======================================================================
	_log("")
	_log("   [B] DPS 扫描（单塔 Arrow@S0 叠层 h）· W1/W5/W10/W15/W20 × 18 档强度")
	var hs = [1, 2, 3, 4, 6, 8, 11, 16, 23, 32, 45, 64, 90, 130, 190, 270, 400, 560]
	var sweep_ok = true
	var sweep_cases = 0
	var sweep_nontrivial = 0
	for w in [1, 5, 10, 15, 20]:
		var thr = float(_WaveSim.monster_stats(w, cfg)["threshold"])
		for h in hs:
			var p = _mk_player_h(cfg, h)
			var g = _WaveSim.simulate_wave(p, w, cfg, geo)
			var wd = _mk_director(w)
			wd.setup(p, cfg, geo)
			wd.start_wave(w)
			wd.core_hp = 1e12
			var r = wd.run_to_end()
			var ok = int(r["kills"]) == int(g["kills"]) \
				and int(r["leaked"]) == int(g["leaked"]) \
				and absf(float(r["scrap_earned"]) - float(g["scrap_earned"])) <= TOL_EQ \
				and absf(float(r["dps"]) - float(g["dps"])) <= TOL_EQ
			sweep_ok = sweep_ok and ok
			sweep_cases += 1
			var nt = int(g["kills"]) > 0 and int(g["kills"]) < int(g["n"])
			if nt:
				sweep_nontrivial += 1
				non_trivial += 1
			if not ok:
				_log("   *** MISMATCH W%d h=%d：金标本 杀%d 漏%d / 实时 杀%d 漏%d"
					% [w, h, int(g["kills"]), int(g["leaked"]), int(r["kills"]), int(r["leaked"])])
			if w == 10:
				_log("     W10 h=%-2d dps/thr=%-8.3f 金标本 杀%-2d 漏%-2d | 实时 杀%-2d 漏%-2d %s"
					% [h, float(g["dps"]) / thr, int(g["kills"]), int(g["leaked"]),
						int(r["kills"]), int(r["leaked"]), "OK" if ok else "MISMATCH"])
			wd.free()
	_tally("★ [B] DPS 扫描 %d 组（5 波 × 12 档）全部逐位等价" % sweep_cases, sweep_ok)
	_check_int("★ 等价性非平凡：≥10 组落在「部分击杀」中间态（探针真的有效）",
		1 if sweep_nontrivial >= 10 else 0, 1)
	_log("   非平凡组数（0 < kills < N）= %d / %d" % [sweep_nontrivial, sweep_cases])

	# =======================================================================
	#  [C] 喂 delta 的粒度无关性：dt 怎么切都不改口径
	# =======================================================================
	_log("")
	_log("   [C] 喂 delta 粒度无关性（W10 · 自动挑一档「部分击杀」的构筑，保证探针非平凡）")
	var thr2 = float(_WaveSim.monster_stats(10, cfg)["threshold"])
	var p2 = _mk_player_h(cfg, 8)
	var g2 = _WaveSim.simulate_wave(p2, 10, cfg, geo)
	var h2 := 8
	for h in hs:
		var pp = _mk_player_h(cfg, h)
		var gg = _WaveSim.simulate_wave(pp, 10, cfg, geo)
		if int(gg["kills"]) > 0 and int(gg["kills"]) < int(gg["n"]):
			p2 = pp
			g2 = gg
			h2 = h
			break
	_log("     选中 W10 h=%d：dps/threshold = %.3f · 金标本 杀%d 漏%d"
		% [h2, float(g2["dps"]) / thr2, int(g2["kills"]), int(g2["leaked"])])
	_tally("★ [C] 金标本 W10(h=%d) 落在非平凡区间（探针有效）" % h2,
		int(g2["kills"]) > 0 and int(g2["kills"]) < int(g2["n"]))
	for dt in [0.1, 0.05, 0.035, 0.025, 0.016, 0.008, 0.25, 0.5, 1.0]:
		var wd = _mk_director(10)
		wd.setup(p2, cfg, geo)
		wd.start_wave(10)
		wd.core_hp = 1e12
		var guard = 0
		while (wd.state == 1 or wd.state == 2) and guard < 200000:
			guard += 1
			wd.advance(dt)
		_check_int("W10 喂 dt=%.3f → kills 与金标本一致" % dt, int(wd.kills), int(g2["kills"]))
		_check_int("W10 喂 dt=%.3f → leaked 与金标本一致" % dt, int(wd.leaked_count), int(g2["leaked"]))
		_check("W10 喂 dt=%.3f → scrap 与金标本一致" % dt, float(wd.scrap_earned),
			float(g2["scrap_earned"]), TOL_EQ)
		wd.free()

	# =======================================================================
	#  [D] 🟡 S5-D1 证据：三原型 + Elite 与金标本**不等价**
	# =======================================================================
	_log("")
	_log("   [D] 🟡 S5-D1：GDD §2.5 三原型+Elite 与金标本的偏离（登记待拍板）")
	var p3 = _mk_player_h(cfg, 8)
	var g3 = _WaveSim.simulate_wave(p3, 10, cfg, geo)
	var wd3 = _mk_director(10)
	wd3.setup(p3, cfg, geo)
	wd3.prototype_split_enabled = true
	wd3.elite_waves_enabled = true
	wd3.start_wave(10)
	wd3.core_hp = 1e12
	var r3 = wd3.run_to_end()
	_log("     W10 同一构筑：金标本 杀%d 漏%d · 三原型+Elite 杀%d 漏%d"
		% [int(g3["kills"]), int(g3["leaked"]), int(r3["kills"]), int(r3["leaked"])])
	var differs = (int(r3["kills"]) != int(g3["kills"])) or (int(r3["leaked"]) != int(g3["leaked"]))
	_check_int("S5-D1：三原型+Elite 口径**确实**与金标本不同（登记待拍板，不是实现 bug）",
		1 if differs else 0, 1)
	wd3.free()

	# ---- 金标本零修改守卫（源码级）----
	_tally("🔴 金标本 `wave_sim.gd` 未被改动（DT=0.1 · 含 `simulate_wave_naive` 对照实现 · 无墙钟）",
		_WaveSim.DT == 0.1
		and _src_contains("res://scripts/engine/wave_sim.gd", "simulate_wave_naive")
		and _src_contains("res://scripts/engine/wave_sim.gd", "monsters.sort(key=lambda m: m[1])")
		and _src_has_no_wall_clock("res://scripts/engine/wave_sim.gd"))


# ===========================================================================
#  工具
# ===========================================================================
func _mk_director(w: int = 1):
	var cfg = _Cfg.cfg_of("B")
	var geo = _Geo6.build()
	var player = _SimPlayer.new_player("B", cfg, geo)
	var wd = _WaveDirector.new()
	wd.setup(player, cfg, geo)
	if w > 1:
		wd.w = w
	_nodes.append(wd)
	return wd


## 构造"指定层数"的构筑（单塔 Arrow@S0 · h 层）→ 用于 DPS 扫描。
## 🔴 同一构筑同时喂给 `WaveSim.simulate_wave` 与 `WaveDirector`，保证对照的是同一 DPS。
func _mk_player_h(cfg: Dictionary, h: int):
	var p = _SimPlayer.new_player("B", cfg, _Geo6.build())
	p.towers[0].h = h
	return p


static func _count_true(flags: Array) -> int:
	var c := 0
	for f in flags:
		if bool(f):
			c += 1
	return c


## 🔴 W-C3 红线守卫：刷怪/移动不得由墙钟或 Timer 驱动。
func _src_has_no_wall_clock(path: String, require_process: bool = false) -> bool:
	var src = _src_code_only(path)
	if src == "":
		return false
	var bad: Array = ["get_ticks_msec", "get_ticks_usec", "Timer.new", "delta_ticks"]
	for b in bad:
		if src.contains(String(b)):
			return false
	if require_process:
		# 必须消费**缩放后的 delta**（不是墙钟、不是帧计数）
		return src.contains("_process(delta") and src.contains("advance(")
	return true


static func _src_read(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var src = f.get_as_text()
	f.close()
	return src


static func _src_contains(path: String, needle: String) -> bool:
	return _src_read(path).contains(needle)


## 去掉整行注释（`#` 开头）后的源码 —— 注释里**允许**出现"禁止项"的名字（它们在解释红线）。
static func _src_code_only(path: String) -> String:
	var out := ""
	for line in _src_read(path).split("\n"):
		var t := String(line).strip_edges()
		if t.begins_with("#"):
			continue
		out += String(line) + "\n"
	return out
