extends SceneTree
##
## headless 反制窗口 **2×2 因子定因扫描**（T-CP-07 · 2026-10-12 用户批准）
##
## 🔴 使命：把「T2/T4 反向（`B+bulwark < AI 地板`）」的归因**钉死** ——
##   隔离现有 confound 的两根轴：**几何** 与 **elite/Sapper**。
##
## 现有 confound（已核实）：六槽臂走 `run_loop_aggro`（无 proto/elite/Sapper）·
##   八槽臂走 `run_loop_proto_aggro`（proto+elite+Sapper×3）→ 差异混淆
##   {几何 · n_slots · proto · elite · Sapper · runner}。
##
## 本扫描设计（2×2×2 = 8 臂 × 300 局）：
##   · **几何** ∈ {六槽 PATH（n_slots=6）, 八槽 RADIAL（n_slots=8）}
##   · **elite/Sapper** ∈ {全开, 全关}（Sapper 由 elite 驱动）
##   · **臂** ∈ {B 地板（无保护）, B+bulwark（理想肉盾）}
##   · 🔴 **固定常量**：runner=`run_loop_proto_aggro`（统一，隔离 runner 变量）·
##     `proto_enabled=true`（三原型分化 = 实机口径）· `aggro_enabled=true` ·
##     `repair_on_disable=0` · seed=**20261002** · N=300 · W_MAX=20 · warmup=2 · actions=12。
##   🔴 每臂独立 `PyRandom(SEED)`（与 C-9 / scan_bulwark 同纪律，fresh rng）。
##
## 🔒 口径锚点（自证 harness 未走样）：
##   · 八槽 RADIAL × elite 全开 × B 地板 → 应复现 **C-9 T0 = 0.747**（±0）
##   · 八槽 RADIAL × elite 全开 × B+bulwark → 应复现 **C-9 T2 = 0.680**
##   （C-9 同为 proto/elite/aggro 全开 · RADIAL 八槽 · seed 20261002 · N=300）
##
## 判据（**纯符号方向提示** · 逐对比另报 Δ/SE/z）：
##   · 反向在 **两种几何 × 两种 elite 设置下都成立（4/4 负）** → 🟡 **方向一致 · 倾向结构成因（未达显著）**；
##   · 反向**仅在 elite 全开时出现**（两种几何） → 🟡 **Sapper×bulwark 交互方向提示**（config 驱动 · 未达显著）；
##   · 反向**仅在一侧几何出现** → 🟡 **几何方向提示**（未达显著）。
##   🔴 本判据只做**符号方向**分类；**显著性一律以每格 Δ/SE/z 与 95%CI 为准**
##      （勿把"方向一致（4/4 负）"读作"结构成因坐实 / 方向确凿"）。
##
## 🔴 纯测量 · 零生产代码改动（仅 tests/ + 本测量文档）· 诊断件恒 quit(0)。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_counterplay_factorial.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 push_error(stderr 不缓冲)。
##

const _RunLoopPA := preload("res://scripts/engine/run_loop_proto_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_MAX := 20
const ACTIONS := 12
const WARMUP := 2
const SEED := 20261002
const GATE_B := 0.80

# 几何档：label → {n_slots, mode}
const GEOMETRIES := [
	{"key": "PATH6", "label": "六槽 PATH", "n_slots": 6, "radial": false},
	{"key": "RADIAL8", "label": "八槽 RADIAL", "n_slots": 8, "radial": true},
]
const ELITES := [
	{"key": "on", "label": "elite/Sapper 全开", "on": true},
	{"key": "off", "label": "elite/Sapper 全关", "on": false},
]

# 独立-seed 变体（T-CP-08 追加 · 消除共-seed 非独立）：
#   4 格各用**不同 seed**（**格内** floor vs bulwark 同 seed = 配对；**格间**独立）。
const INDEP_SEEDS := {
	"PATH6|on": 20261002,
	"PATH6|off": 20261003,
	"RADIAL8|on": 20261004,
	"RADIAL8|off": 20261005,
}


func _fmt(v: float, nd: int = 3) -> String:
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)


## 跑一个单元（几何 × elite × 臂）。返回 {rate, surv, n_takeoff, n_surv, n, med}。
##   seed_value 缺省 SEED（主读共用 seed）；独立-seed 变体传入各格专属 seed。
func _cell(n_slots: int, radial: bool, elite_on: bool, bulwark: bool, runs: int, seed_value: int = SEED) -> Dictionary:
	var cfg := _Cfg.cfg_of("B")
	cfg["n_slots"] = n_slots
	cfg["max_actions"] = ACTIONS
	cfg["repair_on_disable"] = 0          # 诊断枚举恒 OFF（本扫描只看 bulwark，不看复活）
	var rng := _PyRandom.new(seed_value)  # 🔴 每臂独立 fresh rng（与 C-9 同纪律）
	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL if radial else _SpaceModel.Mode.PATH
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		var per_diag: Array = [0, 0, 0, 0.0, 0, 0]
		# run(path, cfg, max_wave, geo, rng, proto, elite, aggro, exp, attrition, warmup, protect_core, bulwark, diag)
		var out := _RunLoopPA.run("B", cx, W_MAX, null, rng,
			true, elite_on, true, 0.6, -1.0, WARMUP, false, bulwark, per_diag)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := _Stats.takeoff_wave(rows)
		if alive and tw >= 0:
			takeoffs += 1
			hits.append(tw)
	_SpaceModel.mode = prev_mode
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
		"n": runs,
	}


## 两比例差 Δ 的 SE（独立样本）：SE_diff = √(p1(1−p1)/n1 + p2(1−p2)/n2)。
func _se_diff(p1: float, n1: int, p2: float, n2: int) -> float:
	return sqrt(p1 * (1.0 - p1) / float(n1) + p2 * (1.0 - p2) / float(n2))


## 单比例 SE：√(p(1−p)/n)。
func _se1(p: float, n: int) -> float:
	return sqrt(p * (1.0 - p) / float(n))


## 打印一个 (几何 × elite) 组合的两臂对比 + Δ/SE/z。
##   返回 Δ（bulwark − floor）供上层判读。
func _report_combo(geo: Dictionary, el: Dictionary, floor: Dictionary, bulwark: Dictionary) -> float:
	var pf := float(floor["rate"])
	var pb := float(bulwark["rate"])
	var n := int(floor["n"])
	var d := pb - pf
	var se := _se_diff(pb, n, pf, n)
	var z := d / se if se > 0.0 else 0.0
	var lo := d - 1.96 * se
	var hi := d + 1.96 * se
	var sign := "反向（bulwark 更差）" if d < 0.0 else "正向（bulwark 更好）"
	print("")
	print("  ▶ [%s × %s]" % [String(geo["label"]), String(el["label"])])
	print("      B 地板      = %s  (%d/%d · 存活 %.3f)"
		% [_fmt(pf), int(floor["n_takeoff"]), n, float(floor["surv"])])
	print("      B+bulwark   = %s  (%d/%d · 存活 %.3f)"
		% [_fmt(pb), int(bulwark["n_takeoff"]), n, float(bulwark["surv"])])
	print("      Δ(bulwark−floor) = %s  · SE_diff = %s  · z = %s  · 95%%CI [%s, %s]  → %s"
		% [_fmt(d), _fmt(se), _fmt(z), _fmt(lo), _fmt(hi), sign])
	push_error("[Factorial] %s x %s : floor=%s bulwark=%s d=%s z=%s"
		% [String(geo["key"]), String(el["key"]), _fmt(pf), _fmt(pb), _fmt(d), _fmt(z)])
	return d


## 独立-seed 复现（T-CP-08 追加）：4 格各用不同 seed（格内配对 · 格间独立）。
##   报：4 格 Δ/SE/z/95%CI + **是否仍 4/4 负** + **合并 z**（4 独立对比 → Σz/√4）。
func _independent_seed(runs: int) -> void:
	print("")
	print("===============================================================")
	print("  §独立-seed 复现（T-CP-08 · 4 格各不同 seed · 格内 floor/bulwark 同 seed 配对）")
	print("     seeds: PATH6|on=%d · PATH6|off=%d · RADIAL8|on=%d · RADIAL8|off=%d"
		% [INDEP_SEEDS["PATH6|on"], INDEP_SEEDS["PATH6|off"], INDEP_SEEDS["RADIAL8|on"], INDEP_SEEDS["RADIAL8|off"]])
	print("     口径不变：runner=run_loop_proto_aggro · proto/aggro 恒开 · N=%d · W_MAX=%d · warmup=%d"
		% [runs, W_MAX, WARMUP])
	print("===============================================================")
	var zs: Array = []
	var neg_count := 0
	var cells := 0
	print("  %-16s %-14s %8s %10s %8s %8s  %-24s" % ["几何", "elite/Sapper", "seed", "Δ", "SE_diff", "z", "95% CI"])
	for geo in GEOMETRIES:
		for el in ELITES:
			var key := "%s|%s" % [geo["key"], el["key"]]
			var sd := int(INDEP_SEEDS[key])
			var floor := _cell(int(geo["n_slots"]), bool(geo["radial"]), bool(el["on"]), false, runs, sd)
			var bul := _cell(int(geo["n_slots"]), bool(geo["radial"]), bool(el["on"]), true, runs, sd)
			var pf := float(floor["rate"])
			var pb := float(bul["rate"])
			var n := int(floor["n"])
			var d := pb - pf
			var se := _se_diff(pb, n, pf, n)
			var z := d / se if se > 0.0 else 0.0
			var lo := d - 1.96 * se
			var hi := d + 1.96 * se
			zs.append(z)
			cells += 1
			if d < 0.0:
				neg_count += 1
			print("  %-16s %-14s %8d %10s %8s %8s  [%s, %s]"
				% [String(geo["label"]), String(el["label"]), sd, _fmt(d), _fmt(se), _fmt(z), _fmt(lo), _fmt(hi)])
			push_error("[IndepSeed] %s : floor=%s bulwark=%s d=%s z=%s"
				% [key, _fmt(pf), _fmt(pb), _fmt(d), _fmt(z)])
	# 合并 z：4 个**独立**对比 → Σz/√4（格内配对、格间独立）
	var sum_z := 0.0
	for z in zs:
		sum_z += float(z)
	var combined_z := sum_z / sqrt(float(zs.size()))
	print("")
	print("  ▶ 独立-seed 汇总：")
	print("     负向格数 = %d/%d  %s" % [neg_count, cells,
		"（仍 4/4 负 ✅）" if neg_count == cells else "（⚠ 出现非负 → 方向不齐）"])
	print("     合并 z（Σz/√%d） = %s  %s" % [zs.size(), _fmt(combined_z),
		"（|z|≥1.96 → 4 独立对比合并显著）" if absf(combined_z) >= 1.96 else "（|z|<1.96 → 合并亦未达显著）"])
	print("     🔴 判读以合并 z 为准；措辞升级/保持 = team-lead 拍板，本扫描只测量。")
	print("===============================================================")


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  反制窗口 2×2 因子定因扫描（T-CP-07 · B 多塔）")
	print("  几何 {六槽 PATH, 八槽 RADIAL} × elite/Sapper {全开, 全关} × 臂 {地板, bulwark}")
	print("  固定：runner=run_loop_proto_aggro · proto/aggro 恒开 · seed=%d · N=%d · W_MAX=%d · warmup=%d"
		% [SEED, runs, W_MAX, WARMUP])
	print("  🔒 锚点：八槽×elite全开 应复现 C-9 T0=0.747 / T2=0.680")
	print("===============================================================")

	var t0 := Time.get_ticks_msec()
	var deltas: Dictionary = {}   # key "GEO|ELITE" → Δ
	var rates: Dictionary = {}    # key "GEO|ELITE|ARM" → rate
	var counts: Dictionary = {}   # key "GEO|ELITE|ARM" → n_takeoff（锚点精确比对用）

	for geo in GEOMETRIES:
		for el in ELITES:
			var floor := _cell(int(geo["n_slots"]), bool(geo["radial"]), bool(el["on"]), false, runs)
			var bul := _cell(int(geo["n_slots"]), bool(geo["radial"]), bool(el["on"]), true, runs)
			rates["%s|%s|floor" % [geo["key"], el["key"]]] = float(floor["rate"])
			rates["%s|%s|bulwark" % [geo["key"], el["key"]]] = float(bul["rate"])
			counts["%s|%s|floor" % [geo["key"], el["key"]]] = int(floor["n_takeoff"])
			counts["%s|%s|bulwark" % [geo["key"], el["key"]]] = int(bul["n_takeoff"])
			var d := _report_combo(geo, el, floor, bul)
			deltas["%s|%s" % [geo["key"], el["key"]]] = d

	var dt := Time.get_ticks_msec() - t0
	print("")
	print("  总耗时 = %d ms（8 臂 × %d 局 = %d 局）" % [dt, runs, 8 * runs])

	# ---- 锚点自证 ----
	print("")
	print("===============================================================")
	print("  §锚点自证（harness 未走样）")
	print("===============================================================")
	var a_floor_n := int(counts.get("RADIAL8|on|floor", -1))
	var a_bul_n := int(counts.get("RADIAL8|on|bulwark", -1))
	var a_floor := float(rates.get("RADIAL8|on|floor", -1.0))
	var a_bul := float(rates.get("RADIAL8|on|bulwark", -1.0))
	print("  八槽×elite全开 地板 = %s（%d/300 · C-9 T0 = 224/300 = 0.747）%s"
		% [_fmt(a_floor), a_floor_n, "✅" if a_floor_n == 224 else "⚠ 偏差"])
	print("  八槽×elite全开 bulwark = %s（%d/300 · C-9 T2 = 204/300 = 0.680）%s"
		% [_fmt(a_bul), a_bul_n, "✅" if a_bul_n == 204 else "⚠ 偏差"])

	# ---- 判读矩阵 ----
	print("")
	print("===============================================================")
	print("  判读矩阵（Δ = bulwark − floor · Δ<0 = 反向）")
	print("===============================================================")
	print("  %-16s %-20s %10s" % ["几何", "elite/Sapper", "Δ"])
	for geo in GEOMETRIES:
		for el in ELITES:
			var d: float = float(deltas["%s|%s" % [geo["key"], el["key"]]])
			var mark := "🟢反向" if d < 0.0 else "🔴正向"
			print("  %-16s %-20s %10s  %s" % [String(geo["label"]), String(el["label"]), _fmt(d), mark])

	var d_p_on: float = float(deltas["PATH6|on"])
	var d_p_off: float = float(deltas["PATH6|off"])
	var d_r_on: float = float(deltas["RADIAL8|on"])
	var d_r_off: float = float(deltas["RADIAL8|off"])
	var all_neg := d_p_on < 0.0 and d_p_off < 0.0 and d_r_on < 0.0 and d_r_off < 0.0
	var elite_only := d_p_on < 0.0 and d_r_on < 0.0 and (d_p_off >= 0.0 or d_r_off >= 0.0)
	var geom_only := (d_p_on < 0.0 and d_p_off < 0.0 and (d_r_on >= 0.0 or d_r_off >= 0.0)) \
		or (d_r_on < 0.0 and d_r_off < 0.0 and (d_p_on >= 0.0 or d_p_off >= 0.0))

	print("")
	print("  ▶ 结论（🟡 纯符号**方向提示** · 非显著性结论）：")
	if all_neg:
		print("     🟡 **方向一致（4/4 负）· 倾向结构成因（未达显著）** —— 反向在 2 几何 × 2 elite 下符号全负（方向提示；显著性见逐格 SE/z）。")
	elif elite_only:
		print("     🟡 **Sapper×bulwark 交互（方向提示）** —— 反向**仅在 elite/Sapper 全开**时出现，非纯结构（未达显著）。")
	elif geom_only:
		print("     🟡 **几何成因（方向提示）** —— 反向**仅在一侧几何**出现（槽位相关 · 未达显著）。")
	else:
		print("     🟠 **混合/不整齐** —— 反向的成立模式不落在三档纯型（见矩阵，逐格 Δ/SE/z）→ 如实上报。")
	print("     （N=%d 纪律：判读以 Δ 的 SE/z 为准，勿只看点估计；" % runs)
	print("      本自动判据为**符号方向规则**，未经显著性检验 —— 只作方向提示。）")
	print("===============================================================")

	# ---- 独立-seed 复现（T-CP-08）----
	_independent_seed(runs)

	quit(0)
