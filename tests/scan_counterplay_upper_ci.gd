extends SceneTree
##
## headless 反制窗口 · **上限/下限 CI 收紧**（T-CP-05 · ② · N=1000）
##
## 🔴 使命：C-9（N=300）的「上限达标」不稳健（`T1=0.813` vs 门禁 0.80 仅 `+0.59 SE`）。
##   本测量把 C-9 的 **T0 地板 / T1 上限** 两臂放大 **N=1000**（其余口径不变），报告
##   **SE + 95% CI**，判定：
##     · 地板 vs 0.80：是否仍**稳健破线**（预期：是）；
##     · 上限 vs 0.80：是否**真正触线**，还是 CI **跨 0.80**（预期：跨 → 悬案）。
##
## 🔴 口径：**逐字复刻** `tests/scan_counterplay_player_arm.gd`（RADIAL 八槽 · proto+elite+aggro
##   全开 · `run_loop_proto_aggro` · seed=20261002 · WARMUP=2 · max_actions=12 · repair=0），
##   仅改两处：① 只跑 B 的 T0/T1 两臂（省时）；② N=1000。
##
## 臂（沿用 C-9 命名）：
##   · T0 AI 地板  （protect_core=false）→ C-9 八槽点估计 0.747
##   · T1 保主力塔 （protect_core=true ）→ C-9 八槽点估计 0.813
##
## 统计（比例标准误）：
##   · 单比例 SE = √(p(1-p)/n)；z vs 0.80 = (p−0.80)/SE；95% CI = p ± 1.96·SE
##   · 两比例 SE_diff = √(p1(1-p1)/n1 + p2(1-p2)/n2)；可对 T1 vs T0
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_counterplay_upper_ci.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 push_error(stderr 不缓冲)。
##

const _RunLoopPA := preload("res://scripts/engine/run_loop_proto_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_MAX := 20
const ACTIONS := 12
const WARMUP := 2
const N_SLOTS := 8              # 🔴 实机几何：RADIAL 八槽（与 C-9 同口径）
const SEED := 20261002          # 与 C-9 同 seed
const GATE_B := 0.80
const Z_95 := 1.96


func _fmt(v: float, nd: int = 3) -> String:
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)


## 跑一个臂（RADIAL 八槽 · proto+elite+aggro 全开 · N=runs）—— 逐字复刻 C-9 的 _arm。
func _arm(path: String, protect_core: bool, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["n_slots"] = N_SLOTS
	cfg["max_actions"] = ACTIONS
	cfg["repair_on_disable"] = 0
	var rng := _PyRandom.new(SEED)
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		var per_diag: Array = [0, 0, 0, 0.0, 0, 0]
		var out := _RunLoopPA.run(path, cx, W_MAX, null, rng,
			true, true, true, 0.6, -1.0, WARMUP, protect_core, false, per_diag)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := _Stats.takeoff_wave(rows)
		if alive and tw >= 0:
			takeoffs += 1
			hits.append(tw)
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
		"n": runs,
	}


func _se_single(p: float, n: int) -> float:
	return sqrt(p * (1.0 - p) / float(n))


func _report_arm(tag: String, r: Dictionary) -> void:
	var p := float(r["rate"])
	var n := int(r["n"])
	var se := _se_single(p, n)
	var z := (p - GATE_B) / se
	var lo := p - Z_95 * se
	var hi := p + Z_95 * se
	print("  %s" % tag)
	print("    点估计 = %s（起飞 %d/%d）· 存活率 = %s · 中位起飞波 = %s"
		% [_fmt(p), int(r["n_takeoff"]), n, _fmt(float(r["surv"])), str(r["med"])])
	print("    SE = %s · 95%% CI = [%s, %s] · z( vs 门禁 %.2f ) = %s"
		% [_fmt(se), _fmt(lo), _fmt(hi), GATE_B, _fmt(z, 2)])
	print("    CI 是否跨门禁 %.2f：%s" % [GATE_B, ("🔴 跨（不稳健）" if (lo < GATE_B and GATE_B < hi) else "✅ 不跨（稳健）")])


func _initialize() -> void:
	var runs := 1000
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  反制窗口 · 上限/下限 CI 收紧（T-CP-05 · ② · N=%d）" % runs)
	print("  RADIAL 八槽 · proto+elite+aggro 全开 · seed=%d · WARMUP=%d · repair=0"
		% [SEED, WARMUP])
	print("  臂：T0 AI 地板（protect=false）/ T1 保主力塔（protect=true）· B 多塔")
	print("  门禁 = %.2f（八槽参考臂口径）" % GATE_B)
	print("===============================================================")

	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	push_error("[CI] running T0 (N=%d) ..." % runs)
	var t0 := _arm("B", false, runs)
	push_error("[CI] running T1 (N=%d) ..." % runs)
	var t1 := _arm("B", true, runs)

	_SpaceModel.mode = prev_mode

	print("")
	print("---- B 多塔（RADIAL 八槽 · N=%d）----" % runs)
	_report_arm("T0 AI 地板：", t0)
	print("")
	_report_arm("T1 保主力塔：", t1)

	# ---- T1 vs T0（两比例）----
	var p0 := float(t0["rate"])
	var p1v := float(t1["rate"])
	var n := int(t0["n"])
	var se_diff := sqrt(p0 * (1.0 - p0) / float(n) + p1v * (1.0 - p1v) / float(n))
	var d := p1v - p0
	var z_arm := d / se_diff
	print("")
	print("  ▶ T1 − T0：Δ = %s · SE_diff = %s · z = %s（95%% CI = [%s, %s]）"
		% [_fmt(d), _fmt(se_diff), _fmt(z_arm, 2),
			_fmt(d - Z_95 * se_diff), _fmt(d + Z_95 * se_diff)])

	print("")
	print("===============================================================")
	print("  判定")
	print("===============================================================")
	# 地板
	var se0 := _se_single(p0, n)
	var z0 := (p0 - GATE_B) / se0
	# 上限
	var se1 := _se_single(p1v, n)
	var z1 := (p1v - GATE_B) / se1
	var lo1 := p1v - Z_95 * se1
	var hi1 := p1v + Z_95 * se1
	print("  · 地板 T0 = %s（z vs %.2f = %s）→ %s"
		% [_fmt(p0), GATE_B, _fmt(z0, 2),
			("🟢 稳健破线" if z0 < -Z_95 else ("🟡 破线但不显著" if p0 < GATE_B else "❌ 未破线"))])
	if lo1 < GATE_B and GATE_B < hi1:
		print("  · 上限 T1 = %s（z vs %.2f = %s · 95%% CI [%s, %s] **跨 %.2f**）→ 🔴 **不稳健（悬案）**"
			% [_fmt(p1v), GATE_B, _fmt(z1, 2), _fmt(lo1), _fmt(hi1), GATE_B])
	elif p1v >= GATE_B:
		print("  · 上限 T1 = %s（z vs %.2f = %s · CI 下界 %s ≥ %.2f）→ 🟢 **稳健触线**"
			% [_fmt(p1v), GATE_B, _fmt(z1, 2), _fmt(lo1), GATE_B])
	else:
		print("  · 上限 T1 = %s（z vs %.2f = %s）→ 🔴 未触线" % [_fmt(p1v), GATE_B, _fmt(z1, 2)])
	print("===============================================================")
	quit(0)
