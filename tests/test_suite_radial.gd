extends RefCounted
##
## headless 自测套件 —— 径向核心围攻 · **阶段0 运动学**（`radial` 入口）
##
## 依据：`design/gdd/radial-core-siege-draft.md`
##   · §2.3（出生环 R_s=55 / 黄金角序列）· §2.5（极坐标运动学）
##   · §11.2 阶段0 验收：AC-R1 / AC-R3 / AC-R6 / AC-R7
##
## 🔴 本套件的第一性质：**证明径向迁移只改"位置派生"，不改"结算"**。
##    金标本 `WaveSim.simulate_wave` 里根本没有"位置"概念（怪物 = [hp, t_remain]）。
##    所以 RADIAL 模式下 `WaveDirector` 的 kills / leaked / scrap / dps 必须与金标本
##    **逐位相同** —— 若这一条破了，说明径向改动泄漏进了 t_remain 结算链。
##
## 判据（本套件自检项）：
##   E-R1  等价性：RADIAL 下 W1–W20 逐波 kills/leaked/scrap/dps == 金标本（AC-R3）
##   E-R2  v₀ = R_s/t_reach = 5.50（§2.5）
##   E-R3  单怪抵达核心 = 10.0s（AC-R6 · R-CS3）
##   E-R4  极径 ρ 单调减小、出生 ρ=R_s、抵达 ρ=0（§2.5 运动学）
##   E-R5  黄金角序列确定性 + 单波铺满 ≥300°（AC-R1 · §2.3.1）
##   E-R6  怪物世界坐标到核心距离 == ρ（pos 与 t_remain 共用同一状态量）
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- radial
##   （run_tests 会在跑前把 SpaceModel.mode 置 RADIAL，跑后置回 PATH）
##
## ⚠️ Godot 坑（与 test_suite_slice5 同源）：headless 无 global_script_class_cache
##    → 一律 preload；WaveDirector 是 Node → 用完 free() 避免 ObjectDB 泄漏噪声。
##

const TOL_EQ = 1e-9           # 等价性容差（实际应为 0）

const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _WaveSim = preload("res://scripts/engine/wave_sim.gd")
const _ShopAI = preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer = preload("res://scripts/engine/sim_player.gd")
const _Geo6 = preload("res://scripts/geo/geo6.gd")
const _PathGeometry = preload("res://scripts/geo/path_geometry.gd")
const _SpaceModel = preload("res://scripts/geo/space_model.gd")
const _MonsterData = preload("res://scripts/data/monster_data.gd")
const _Monster = preload("res://scripts/gameplay/monster.gd")
const _WaveDirector = preload("res://scripts/gameplay/wave_director.gd")

var _pass = 0
var _fail = 0
var _out: Array = []
var _nodes: Array = []


func _log(s: String) -> void:
	_out.append(s)
	print(s)


func _tally(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s" % ["PASS" if ok else "FAIL", name])


func _check(name: String, got: float, want: float, tol: float = TOL_EQ) -> void:
	var d = absf(got - want)
	var ok = (d <= 1e-300) or (d <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	# 🔴 G7：GDScript `String %` 不支持 `%e` → 用 %s + str() 打印差值。
	_log("   [%s] %s  got=%.10f want=%.10f |d|=%s"
			% ["PASS" if ok else "FAIL", name, got, want, str(d)])


func _check_int(name: String, got: int, want: int) -> void:
	_tally("%s  got=%d want=%d" % [name, got, want], got == want)


func _check_bool(name: String, got: bool, want: bool) -> void:
	_tally("%s  got=%s want=%s" % [name, str(got), str(want)], got == want)


func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》径向核心围攻 · 阶段0 运动学 —— 自测")
	_log("判据：radial-core-siege-draft §2.3/§2.5/§11.2 · AC-R1/R3/R6/R7")
	_log("SpaceModel.mode = %s（v₀=%.2f · 核心=(%.0f,%.0f) · R_s=%.1f）"
		% ["RADIAL" if _SpaceModel.mode == _SpaceModel.Mode.RADIAL else "PATH",
		   _SpaceModel.v0(), _SpaceModel.RADIAL_CORE.x, _SpaceModel.RADIAL_CORE.y,
		   _SpaceModel.SPAWN_RADIUS])
	_log("=".repeat(78))

	# 前置：确认本套件确实在 RADIAL 下跑（run_tests 负责切换 + 回退）
	_tally("前置：SpaceModel.mode == RADIAL",
		_SpaceModel.mode == _SpaceModel.Mode.RADIAL)

	_test_v0_and_kinematics()
	_test_spawn_theta_golden()
	_test_equivalence_vs_golden()

	_log("")
	_log("-".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 径向阶段0 运动学全过 —— 结算链零扰动，怪物从四面八方直插核心")
	else:
		_log("[!!] 有 %d 项失败，请检查径向改动是否泄漏进 t_remain 结算链" % _fail)
	_log("-".repeat(78))
	return _fail == 0


# ===========================================================================
#  E-R2 / E-R3 / E-R4：v₀ 派生 + 极坐标运动学
# ===========================================================================
func _test_v0_and_kinematics() -> void:
	_log("")
	_log("--- [运动学] v₀ 派生 / 极径 ρ / 抵达核心时间 ---")

	# E-R2：v₀ = R_s / t_reach = 55 / 10 = 5.50
	_check("E-R2 v₀ = R_s/t_reach = 5.50", _SpaceModel.v0(), 5.50)
	# 对照：PATH 口径 v₀ = 10.10（逐位等价基准，防止派生公式改错）
	var v0_path := _PathGeometry.TOTAL_LEN / _SpaceModel.T_REACH
	_check("对照 PATH v₀ = L/t_reach = 10.10", v0_path, 10.10)

	# E-R4：极径 ρ = R_s·m_spd·t_remain/t_reach
	#   t_remain = t_reach（出生）→ ρ = R_s·m_spd = 55（m_spd=1）
	_check("E-R4 出生（t_remain=10）ρ = R_s = 55.0",
		_SpaceModel.rho_of_t(10.0, 1.0), 55.0)
	#   t_remain 减半 → ρ 减半
	_check("E-R4 t_remain=5 → ρ = 27.5（走了一半）",
		_SpaceModel.rho_of_t(5.0, 1.0), 27.5)
	#   t_remain = 0（抵达核心）→ ρ = 0
	_check("E-R4 t_remain=0 → ρ = 0（抵达核心）",
		_SpaceModel.rho_of_t(0.0, 1.0), 0.0)
	#   Tank（m_spd=2/3）出生 → ρ = 55×2/3
	_check("E-R4 Tank(m_spd=2/3) 出生 ρ = 55×2/3",
		_SpaceModel.rho_of_t(15.0, 2.0 / 3.0), 55.0 * 2.0 / 3.0)

	# E-R3：单怪从出生到抵达核心 = t_reach = 10.0s（ρ 从 R_s 线性减到 0）
	var m = _Monster.new()
	m.setup(0, "Swarm", false, 100.0, 1.0, 10.0)   # t_remain=10 = t_reach
	_check("E-R3 出生时 t_remain = t_reach = 10.0", m.t_remain, 10.0)
	_check("E-R3 出生时 ρ = R_s = 55.0", m.arc_s(_SpaceModel.v0()), 55.0)
	m.t_remain = 0.0
	_check("E-R3 抵达核心 ρ = 0", m.arc_s(_SpaceModel.v0()), 0.0)
	_check_bool("E-R3 reached() == true（t_remain≤0 ⟺ ρ=0）", m.reached(), true)
	m.free()

	# E-R6：pos 到核心距离 == ρ（pos 与 t_remain 共用同一状态量）
	var m2 = _Monster.new()
	m2.setup(3, "Swarm", false, 100.0, 1.0, 10.0)
	m2.set_theta(PI / 4.0)     # 任意出生角
	for tr in [10.0, 7.5, 5.0, 2.5, 0.0]:
		m2.t_remain = tr
		var want_rho := _SpaceModel.rho_of_t(tr, 1.0)
		var got_dist := m2.pos(_SpaceModel.v0()).distance_to(_SpaceModel.core_pos())
		_check("E-R6 t_remain=%.1f：pos 到核心距离 == ρ" % tr, got_dist, want_rho, 1e-7)
	m2.free()


# ===========================================================================
#  E-R5：黄金角低差异序列（确定性 + 铺满 360°）
# ===========================================================================
func _test_spawn_theta_golden() -> void:
	_log("")
	_log("--- [出生角] 黄金角低差异序列（确定性 · 铺满 360°）---")

	# 确定性：同 (w, index) 恒得同一角度
	var a0 := _SpaceModel.spawn_theta(0, 7)
	var a1 := _SpaceModel.spawn_theta(0, 7)
	_check("E-R5 确定性：同 (w=7,index=0) 两次调用一致", a0, a1, 1e-12)

	# 不同 index → 不同角度（黄金角不重复）
	var a2 := _SpaceModel.spawn_theta(1, 7)
	_check_bool("E-R5 相邻 index 出生角不同", absf(a2 - a0) > 1e-9, true)

	# 逐波相位变化：同 index，不同 w → 角度不同（喂 P3）
	var a3 := _SpaceModel.spawn_theta(0, 8)
	_check_bool("E-R5 逐波换相位（w=7→8 同 index 角度变）", absf(a3 - a0) > 1e-9, true)

	# AC-R1：单波出生角的分布覆盖 ≥300°（N=40 只怪，黄金角铺满）
	var angles: Array = []
	for i in range(40):
		angles.append(rad_to_deg(_SpaceModel.spawn_theta(i, 7)))
	var span := _angular_span(angles)
	_log("   W7 前 40 只怪出生角覆盖跨度 = %.1f°（AC-R1 要求 ≥300°）" % span)
	_tally("E-R5 / AC-R1 单波出生角覆盖 ≥300°", span >= 300.0)


## 计算一组角度（度，[0,360)）在圆上的最大角空隙的补集 = 覆盖跨度。
func _angular_span(angles: Array) -> float:
	var sorted := angles.duplicate()
	sorted.sort()
	var max_gap := 0.0
	for i in range(sorted.size()):
		var cur := float(sorted[i])
		var nxt := float(sorted[(i + 1) % sorted.size()])
		var gap := fmod(nxt - cur + 360.0, 360.0)
		if gap > max_gap:
			max_gap = gap
	return 360.0 - max_gap


# ===========================================================================
#  E-R1：等价性 —— RADIAL 下实时 WaveDirector vs 金标本逐位（本套件最硬验收）
# ===========================================================================
func _test_equivalence_vs_golden() -> void:
	_log("")
	_log("--- [★★ 等价性] RADIAL 下实时 `WaveDirector` vs 金标本 `simulate_wave` ---")
	_log("   （金标本无几何 → 径向只改位置派生 → kills/leaked/scrap/dps 必须逐位相同）")

	var cfg = _Cfg.cfg_of("B")
	var geo = _Geo6.build()
	var player = _SimPlayer.new_player("B", cfg, geo)
	var cum = 0.0
	var grand_ok = true
	var non_trivial = 0

	for w in range(1, 21):
		# ---- 金标本（批处理 · 无几何）----
		var gold = _WaveSim.simulate_wave(player, w, cfg, geo)
		# ---- 实时（RADIAL · 同一构筑，逐 tick 展开）----
		var wd = _mk_director(w)
		wd.setup(player, cfg, geo)
		wd.start_wave(w)
		wd.core_hp = 1e12      # 等价性探针：核心无限血，只比战斗循环本身
		var rt = wd.run_to_end()

		var ok = int(rt["kills"]) == int(gold["kills"]) \
			and int(rt["leaked"]) == int(gold["leaked"]) \
			and absf(float(rt["scrap_earned"]) - float(gold["scrap_earned"])) <= TOL_EQ \
			and absf(float(rt["dps"]) - float(gold["dps"])) <= TOL_EQ \
			and absf(float(rt["core_damage"]) - float(gold["core_damage"])) <= TOL_EQ
		grand_ok = grand_ok and ok
		if int(gold["kills"]) > 0 and int(gold["kills"]) < int(gold["n"]):
			non_trivial += 1
		if w in [1, 5, 10, 15, 20]:
			_log("   W%-2d N=%-2d dps=%-12.2f | 金标本 杀%-2d 漏%-2d 分%-10.2f"
				% [w, int(gold["n"]), float(gold["dps"]), int(gold["kills"]),
					int(gold["leaked"]), float(gold["scrap_earned"])])
			_log("       %-2s         %-12s | 实时   杀%-2d 漏%-2d 分%-10.2f  %s"
				% ["", "", int(rt["kills"]), int(rt["leaked"]),
					float(rt["scrap_earned"]), "OK" if ok else "*** MISMATCH ***"])
			_check_int("W%d 等价 · kills" % w, int(rt["kills"]), int(gold["kills"]))
			_check_int("W%d 等价 · leaked" % w, int(rt["leaked"]), int(gold["leaked"]))
			_check("W%d 等价 · scrap_earned" % w, float(rt["scrap_earned"]),
				float(gold["scrap_earned"]), TOL_EQ)
			_check("W%d 等价 · dps" % w, float(rt["dps"]), float(gold["dps"]), TOL_EQ)
			_check("W%d 等价 · core_damage" % w, float(rt["core_damage"]),
				float(gold["core_damage"]), TOL_EQ)
		# 推进到下一波（贪心 AI 买东西，构造下一波的构筑）
		var income = float(gold["scrap_earned"]) * (1.0 + float(player.income_mult))
		cum += income
		var shop = _ShopAI.shop_phase(player, cum, w, cfg, geo, null)
		cum = float(shop[0])
		wd.free()

	_tally("★ [E-R1] RADIAL 下 W1–W20 全 20 波逐位等价（kills/leaked/scrap/dps）", grand_ok)
	_log("   非平凡波（0<kills<N）共 %d / 20 —— [A] 贪婪构筑雪崩太快，多为平凡等价" % non_trivial)

	# =======================================================================
	#  [B] DPS 扫描：低强度构筑制造**非平凡**区间（kills 既非 0 也非 N），
	#      让等价性探针真正落在"有漏怪、有击杀"的区间（对齐 slice5 [B]）。
	# =======================================================================
	_log("")
	_log("   [B] DPS 扫描（单塔 Arrow@S0 叠层 h）· W1/W5/W10/W15/W20 × 强度档")
	var hs = [1, 2, 3, 4, 6, 8, 11, 16, 23, 32, 45, 64, 90]
	var sweep_ok = true
	var sweep_cases = 0
	var sweep_nontrivial = 0
	for w in [1, 5, 10, 15, 20]:
		for h in hs:
			var p = _SimPlayer.new_player("B", cfg, geo)
			p.towers[0].h = h
			var g = _WaveSim.simulate_wave(p, w, cfg, geo)
			var wd2 = _mk_director(w)
			wd2.setup(p, cfg, geo)
			wd2.start_wave(w)
			wd2.core_hp = 1e12
			var r = wd2.run_to_end()
			var ok = int(r["kills"]) == int(g["kills"]) \
				and int(r["leaked"]) == int(g["leaked"]) \
				and absf(float(r["scrap_earned"]) - float(g["scrap_earned"])) <= TOL_EQ \
				and absf(float(r["dps"]) - float(g["dps"])) <= TOL_EQ
			sweep_ok = sweep_ok and ok
			sweep_cases += 1
			var nt = int(g["kills"]) > 0 and int(g["kills"]) < int(g["n"])
			if nt:
				sweep_nontrivial += 1
			if not ok:
				_log("   *** MISMATCH W%d h=%d：金标本 杀%d 漏%d / 实时 杀%d 漏%d"
					% [w, h, int(g["kills"]), int(g["leaked"]), int(r["kills"]), int(r["leaked"])])
			wd2.free()
	_tally("★ [E-R1·B] 非平凡 DPS 扫描 %d 档全逐位等价" % sweep_cases, sweep_ok)
	_log("   其中非平凡档（0<kills<N）共 %d / %d —— 探针真正落在有杀有漏区间"
		% [sweep_nontrivial, sweep_cases])


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
