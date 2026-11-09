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
##   E-5   批处理镜像位置 == 实时 monster.pos（RADIAL 下同用同一 R_s）· 🔴 R-9 补
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
const _BuildGrid = preload("res://scripts/geo/build_grid.gd")
const _MonsterData = preload("res://scripts/data/monster_data.gd")
const _Geo8 = preload("res://scripts/geo/geo8.gd")
const _Monster = preload("res://scripts/gameplay/monster.gd")
const _WaveDirector = preload("res://scripts/gameplay/wave_director.gd")
const _WaveSimAggro = preload("res://scripts/engine/wave_sim_aggro.gd")

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
	_test_map_layout()
	_test_batch_mirror_alignment()
	_test_equivalence_vs_golden()
	_test_site_exposure_dispatch()

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
	#   Tank（m_spd=2/3）出生 t_remain=15 → 上钳参照 1/m_spd=1.5 → frac=1.5 → ρ = R_s = 55.0（归环）
	#   🔴 第四刀 proto-elite-golive 裁决 #1：旧式上钳 1.0 误把 Tank 钳到 36.67（环内侧 + 静止 5s）；
	#      修 `space_model.rho_of_t` 上钳为 1/m_spd 后，Tank 正确出生在出生环上。
	_check("E-R4 Tank(m_spd=2/3) 出生 ρ = 55.0（Tank 归环）",
		_SpaceModel.rho_of_t(15.0, 2.0 / 3.0), 55.0)

	# E-R3：单怪从出生到抵达核心 = t_reach = 10.0s（ρ 从 R_s 线性减到 0）
	var m = _Monster.new()
	m.setup(0, "Swarm", false, 100.0, 1.0, 10.0)   # t_remain=10 = t_reach
	_check("E-R3 出生时 t_remain = t_reach = 10.0", m.t_remain, 10.0)
	_check("E-R3 出生时 ρ = R_s = 55.0", m.arc_s(_SpaceModel.v0()), 55.0)
	m.t_remain = 0.0
	_check("E-R3 抵达核心 ρ = 0", m.arc_s(_SpaceModel.v0()), 0.0)
	_check_bool("E-R3 reached() == true（t_remain≤0 ⟺ ρ=0）", m.reached(), true)
	# 🔴 `_Monster` 是 RefCounted（自动回收）→ 不调 `free()`（否则打印
	#   "Can't free a RefCounted object" 污染 stderr）。原 `m.free()` 已移除。

	# E-R6：pos 到核心距离 == ρ（pos 与 t_remain 共用同一状态量）
	# 🔴 容差 1e-5（原 1e-7 过紧）：Godot `Vector2` 为 **float32** → `pos = core + ρ·(cosθ,sinθ)`
	#   再经 `distance_to` 的 `sqrt(cos²+sin²)` 回读，精度 ~1e-7 相对 → ρ≈55 时 |d|≈3.8e-6。
	#   这是 float32 极坐标恒等式的固有残差，非 bug（同款口径见 `run_slice_radial_smoke.gd` ⑤）。
	#   🟡 本断言原被上一行的 `m.free()` 错误（`_Monster` 是 RefCounted）静默中止 → 从未真正跑过
	#      （R-9 卫生修复移除 free() 后暴露；生产 `pos` 无回归）。
	var m2 = _Monster.new()
	m2.setup(3, "Swarm", false, 100.0, 1.0, 10.0)
	m2.set_theta(PI / 4.0)     # 任意出生角
	for tr in [10.0, 7.5, 5.0, 2.5, 0.0]:
		m2.t_remain = tr
		var want_rho := _SpaceModel.rho_of_t(tr, 1.0)
		var got_dist := m2.pos(_SpaceModel.v0()).distance_to(_SpaceModel.core_pos())
		_check("E-R6 t_remain=%.1f：pos 到核心距离 == ρ" % tr, got_dist, want_rho, 1e-5)
	# 🔴 `m2` 是 RefCounted → 不调 free()（原 `m2.free()` 已移除，消除 stderr 噪声）。


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
#  E-M1..E-M8：地图「三裂环」（`design/gdd/scene-map.md` §5 / §11 步4）
# ===========================================================================
## 一句话：**地图的可玩性 = 可建格从 965 收敛到 17，而结算链一位不动。**
##   所以这组断言只验两件事：
##     ① 收敛真的发生了（格数 / 开口 / 跨台断链）—— 否则地图只是画了张背景；
##     ② 收敛没有偷偷改路（`G` 只做角向映射 · 出生角永不落在脊里 · 关掉开关逐位回退）。
func _test_map_layout() -> void:
	_log("")
	_log("--- [E-M] 地图三裂环：障碍区禁建 · 开口 320° · G 保序保测度 · 跨台断链 ---")
	_check_bool("前置：layout_enabled == true", _SpaceModel.layout_enabled, true)

	# ---- E-M1 全盘自由建造，岩脊障碍除外 ----
	var cells: Array = _BuildGrid.all_cells()
	_check_bool("E-M1 可建格覆盖全盘（>500）", cells.size() > 500, true)
	var all_in := false
	for c in cells:
		if _BuildGrid.site_id_of(c).is_empty():
			all_in = true
			break
	_tally("E-M1 阵地外非障碍格可建", all_in)
	var outside: Vector2 = _BuildGrid.snap(_SpaceModel.polar_pos(deg_to_rad(27.0), 40.0))
	_check_bool("E-M1 岩脊障碍格不可建", _BuildGrid.buildable(outside), false)
	_check_bool("E-M1 离盘面很远的点不可建", _BuildGrid.buildable(Vector2(-500.0, -500.0)), false)
	_check_bool("E-M1 核心禁建区仍不可建", _BuildGrid.buildable(_SpaceModel.RADIAL_CORE), false)

	# ---- E-M2 开口 = 320°，脊 = 40° ----
	var open := 0.0
	for a in _SpaceModel.SPAWN_ARCS:
		open += float(a["a1"]) - float(a["a0"])
	_check("E-M2 开口总角宽 = 320°（AC-R1 下限 300°）", open, 320.0, 1e-9)
	var blocked := 0.0
	for rg in _SpaceModel.RIDGES:
		blocked += float(rg["a1"]) - float(rg["a0"])
	_check("E-M2 岩脊合计遮挡 = 360 − 开口 = 40°", blocked, 360.0 - open, 1e-9)

	# ---- E-M3 G 保序 + 保测度 ----
	# 🔴 按**圆周增量**判序（不是比裸值）：C 口跨 0°（262→378），裸值会在 340° 附近
	#   从 ~360 掉回 ~0 —— 那是绕圈不是回退。真实增量恒 > 0 且 ≤ 0.089°/0.1° 输入。
	var mono := true
	var prev := _SpaceModel.map_theta_deg(0.0)
	var worst_delta := 999.0
	for i in range(1, 3600):
		var cur := _SpaceModel.map_theta_deg(float(i) * 0.1)
		var delta := fposmod(cur - prev + 180.0, 360.0) - 180.0
		if delta < -1e-9:
			mono = false
			break
		worst_delta = minf(worst_delta, delta)
		prev = cur
	_tally("E-M3 G 保序（全周 0.1° 步进，无回退；最差增量 %.4f°）" % worst_delta, mono)
	_check("E-M3 输入 0° → 输出 36°（A 口起点）", _SpaceModel.map_theta_deg(0.0), 36.0, 1e-6)
	_check("E-M3 输入 128.25° → 输出 150°（A 口终点）", _SpaceModel.map_theta_deg(128.25), 150.0, 1e-6)
	_check("E-M3 输入 229.5° → 输出 254°（B 口终点）", _SpaceModel.map_theta_deg(229.5), 254.0, 1e-6)
	var tail := _SpaceModel.map_theta_deg(359.9999)
	_check("E-M3 输入 360°⁻ → 输出 18°（C 口绕回，接 G1 起点）", tail, 18.0, 1e-3)
	# 保测度：均匀输入下每段输出占比必须 = 该段弧长占比（114/90/116 of 320）
	var counts: Array = [0, 0, 0]
	const N_MEAS := 3600
	for i in range(N_MEAS):
		var d := _SpaceModel.map_theta_deg(float(i) * 0.1)
		for k in range(_SpaceModel.SPAWN_ARCS.size()):
			var arc: Dictionary = _SpaceModel.SPAWN_ARCS[k]
			var a0 := float(arc["a0"])
			var a1 := float(arc["a1"])
			var hit := (d >= a0 and d < a1) if a1 <= 360.0 else (d >= a0 or d < a1 - 360.0)
			if hit:
				counts[k] = int(counts[k]) + 1
	var meas := true
	var meas_txt := ""
	for k in range(_SpaceModel.SPAWN_ARCS.size()):
		var arc2: Dictionary = _SpaceModel.SPAWN_ARCS[k]
		var want := (float(arc2["a1"]) - float(arc2["a0"])) / 320.0
		var got := float(counts[k]) / float(N_MEAS)
		meas_txt += "%s:%.3f/%.3f " % [String(arc2["id"]), got, want]
		if absf(got - want) > 0.002:
			meas = false
	_tally("E-M3 保测度：三段输出占比 = 弧长占比（%s）" % meas_txt, meas)

	# ---- E-M4 出生角永不落进岩脊（400 次跨 8 个波号）----
	var in_ridge := 0
	for i in range(400):
		var d := rad_to_deg(_SpaceModel.spawn_theta(i, 3 + i % 8))
		if _SpaceModel.is_ridge_deg(d):
			in_ridge += 1
	_check_int("E-M4 400 次出生角落进岩脊的次数", in_ridge, 0)

	# ---- E-M5 跨台断链（按**最近格距**验，阈值 = Lance 0.65·(Ri+Rj) 上限 28.6u）----
	var min_d := 1e9
	var pair := ""
	var ids: Array = []
	for s in _BuildGrid.SITES:
		ids.append(String(s["id"]))
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			for a in _BuildGrid.site_cells(ids[i]):
				for b in _BuildGrid.site_cells(ids[j]):
					var dd: float = (a as Vector2).distance_to(b)
					if dd < min_d:
						min_d = dd
						pair = String(ids[i]) + "–" + String(ids[j])
	_log("   跨台最近格距 = %.2fu（最紧一对 %s）" % [min_d, pair])
	_tally("E-M5 跨台最近格距 ≥ 28.6u（否则三台连成一片，E 飙回 n−1）", min_d >= 28.6)

	# ---- E-M6 每格都在可建外径内 + 起手锚点属于 P1 ----
	var in_field := true
	for c in _BuildGrid.site_points():
		if (c as Vector2).distance_to(_SpaceModel.RADIAL_CORE) > _BuildGrid.FIELD_R:
			in_field = false
	_tally("E-M6 17 格全部落在可建外径 44u 内", in_field)
	_check_bool("E-M6 起手锚点（P1 首格）可建", _BuildGrid.buildable(_BuildGrid.site_anchor("P1")), true)
	_check_bool("E-M6 起手锚点属于 P1",
		_BuildGrid.site_id_of(_BuildGrid.site_anchor("P1")) == "P1", true)

	# ---- E-M7 全局难度税（地图唯一旋钮，必须显式记账）----
	_check("E-M7 全局曝光税 = 360/320 = 1.125", 360.0 / _SpaceModel.OPEN_DEG, 1.125, 1e-12)

	# ---- E-M8 一键回退：关掉开关必须逐位回到「空圆盘 + 整圈出生」----
	_SpaceModel.layout_enabled = false
	var n_off: int = _BuildGrid.all_cells().size()
	var th_off := rad_to_deg(_SpaceModel.spawn_theta(5, 3))
	_SpaceModel.layout_enabled = true
	_log("   布局关闭后：可建格 %d（改前口径 ~965）· θ(5,3) = %.4f°" % [n_off, th_off])
	_tally("E-M8 关闭开关 → 可建格回到整盘量级（>500）", n_off > 500)
	_check("E-M8 关闭开关 → 出生角回到黄金角原值（111 + 687.54 mod 360）",
		th_off, fmod(3.0 * 37.0 + 5.0 * 137.508, 360.0), 1e-9)


# ===========================================================================
#  E-5（🔴 R-9 补）：批处理镜像位置 == 实时 monster.pos
# ===========================================================================
## 依据 `radial-core-siege-draft.md` §7.1 E-5：实时版与批处理镜像 `WaveSimAggro` 必须用
##   同一个 `R_s`。两边在 RADIAL 下都应走 `SpaceModel.radial_pos_of_t(t_remain, m_spd, θ)`。
##   🔴 这里直接比对"批处镜像 `_monster_pos`"与"实时 `Monster.pos`"的**世界坐标逐位相等**
##   —— 若任一边换了位置函数 / 换了 R_s，本断言立即翻红（原质量门 §2.4(d) 缺此直接断言）。
func _test_batch_mirror_alignment() -> void:
	_log("")
	_log("--- [E-5] 批处理镜像位置 == 实时 monster.pos（RADIAL 同 R_s）---")

	var m = _Monster.new()
	m.setup(0, "Swarm", false, 100.0, 1.0, 10.0)   # 镜像恒用基准怪 m_spd=1.0
	var worst := 0.0
	var cases := 0
	for theta in [0.0, PI / 4.0, PI / 2.0, 2.0 * PI / 3.0, 5.0 * PI / 4.0]:
		for tr in [10.0, 7.5, 5.0, 2.5, 0.0]:
			m.set_theta(theta)
			m.t_remain = tr
			var rt_pos: Vector2 = m.pos(_SpaceModel.v0())
			# 批处镜像结构：[hp, t_remain, state, target_slot, m_dps, sapper, theta, reverb]
			var batch: Array = [100.0, tr, 0, -1, 0.6, false, theta, false]
			var batch_pos: Vector2 = _WaveSimAggro._monster_pos(batch, _SpaceModel.v0())
			var d: float = rt_pos.distance_to(batch_pos)
			if d > worst:
				worst = d
			cases += 1
	# 🔴 `_Monster` 是 RefCounted（自动回收）→ 不调 free()。
	_log("   %d 组 (θ,t_remain) 比对 · 最大 |d| = %s（容差 1e-12）" % [cases, str(worst)])
	_check("E-5 批处镜像 pos == 实时 monster.pos（最大 |d|）", worst, 0.0, 1e-12)


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


## 🆕 阵地化（17 格）暴露位分派 —— 2026-11-09
##   为什么必须门禁：`is_exposed` 是「战斗内复活」的资格闸门（`death_valid ∧ is_exposed ∧ ¬is_carry`）。
##   17 格阵地的 `expo_frac` 全挤在 0.073–0.159，用 8 槽的 0.15 判只剩 **1/17** 格算暴露位
##   → 实机 94% 格子永远不可复活（`revive_fired=0`），6-1 W14 十塔全灭、核心 1000→0。
##   本组三条：① 两套口径常量都不许漂；② 阵地口径下内圈暴露、孤台安全；③ 8 槽口径一字不动。
func _test_site_exposure_dispatch() -> void:
	_log("")
	_log("[阵地暴露位] · 阈值分派与 17 格二值化")
	_tally("E-S1 8 槽阈值冻结 0.15", absf(_PathGeometry.EXPO_SAFE_MAX - 0.15) <= TOL_EQ)
	_tally("E-S2 阵地阈值 0.085（落在内圈 0.099 与孤台 0.073 之间）",
		absf(_PathGeometry.EXPO_SAFE_MAX_SITES - 0.085) <= TOL_EQ)
	_tally("E-S3 分派：阵地开 → 0.085 / 阵地关 → 0.15",
		absf(_PathGeometry.expo_safe_max_for(true) - _PathGeometry.EXPO_SAFE_MAX_SITES) <= TOL_EQ
		and absf(_PathGeometry.expo_safe_max_for(false) - _PathGeometry.EXPO_SAFE_MAX) <= TOL_EQ)
	var pts: Array = _BuildGrid.site_points()
	var rows: Array = _PathGeometry.slot_exposure_radial(pts, _MonsterData.AGGRO_R,
		_SpaceModel.core_pos(), _PathGeometry.expo_safe_max_for(true))
	var n_exp := 0
	var n_safe_outer := 0
	for r in rows:
		var p: Vector2 = r["pos"]
		var d: float = _PathGeometry.dist_to_core(p, _SpaceModel.core_pos())
		if bool(r["is_exposed"]):
			n_exp += 1
		elif d >= 39.0:
			n_safe_outer += 1          # 孤台（N1–N3 · r≈39.6/41.7）应恰好是安全位
	_tally("E-S4 17 格阵地 → 暴露 14 / 安全 3", n_exp == 14 and rows.size() == 17)
	_tally("E-S5 安全位全是孤台（r ≥ 39）· 内圈三台无一被漏判", n_safe_outer == 3)
	# 8 槽口径回归：必须仍是 4 暴露 / 4 安全（AC-S6-3 红线）
	var rows8: Array = _PathGeometry.slot_exposure_radial(_Geo8.SLOTS8, _MonsterData.AGGRO_R,
		_SpaceModel.core_pos(), _PathGeometry.expo_safe_max_for(false))
	var e8 := 0
	for r8 in rows8:
		if bool(r8["is_exposed"]):
			e8 += 1
	_tally("E-S6 8 槽口径仍 4 暴露 / 4 安全（AC-S6-3 · 阵地阈值不得外溢）", e8 == 4)


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
