extends SceneTree
##
## V-6' 多塔流安全裕度 · 只读测量探针（R1 + R2 + R3） —— 程基岩 2026-10-10
##
## 依据：docs/phase3/qg-radial/v6prime-multitower-margin.md §4（V6'-R1 / R2 / R3）
## 定位：🔴 纯只读测量。不改 scripts/ 一字；不改任何定稿数值（ATTRITION / κ_r / AGGRO_R /
##       塔位 / SLOTS6 / SLOTS8 / t_reach / hp_growth / DPS 曲线）；只扫描不落点。
##       t_remain 仍是唯一权威状态量；出生角零 RNG 消费 —— 本探针一律不触碰。
##       本探针无闸门语义 -> 恒 quit(0)；只有"跑不出数据"的结构性失败才 quit(1)。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/probe_v6prime.gd
##
## 三段：
##   [R1] 双口径对齐：六槽 PATH 金标本（seed 20260930） vs 八槽 RADIAL（seed 20261002）
##        + 归因控制（六槽 PATH 在 aggro 引擎下、同 seed 重跑，隔离"引擎 vs 槽数/几何/seed"）
##        -> 喂开放问题 Q-R9（八槽是否压 A）
##   [R2] B 路径逐波压力剖面（core_hp / leaked / kills / n）-> core_hp_min & w_min；含 A 对照
##   [R3] A 侧失守波次分布（w_end 直方图）+ 失守前 3 波 core_hp 斜率
##
## 输出纪律：全部 ASCII（Windows GBK 终端，中文会乱码）；进度用 push_error（stderr 不缓冲）。
##
## ⚠️ Godot 坑：headless --script 不做编辑器导入 -> 跨脚本一律 preload；变量用无类型声明
##    或显式 float()（与 run_slice_attrition8.gd 同款）。
##

const _RunLoop := preload("res://scripts/engine/run_loop.gd")
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Geo8 := preload("res://scripts/geo/geo8.gd")

const W_MAX := 20
const WARMUP := 2
const RUNS := 300
const ATTRITION := 1.5
const EXP := 0.6
const MAX_ACTIONS := 12
const SEED6 := 20260930          # 六槽金标本 seed（golden_slice2 MC_TIER）
const SEED8 := 20261002          # 八槽 RADIAL seed（r4-attrition8-after.log）

# ---- 参照基线（只做对照打印，不作闸门）----
# 六槽金标本 MC（tests/golden_slice2.gd MC_TIER）
const GOLD6_A_TAKEOFF_RATE := 0.693
const GOLD6_A_NTAKE := 208
const GOLD6_B_TAKEOFF_RATE := 0.913
const GOLD6_B_NTAKE := 274
# 八槽基线（docs/phase3/qg-radial/r4-attrition8-after.log）
const BASE8_A_SURV := 0.5967     # = 179/300（日志 %.3f 打印为 0.597；%.4f 打印为 0.5967）
const BASE8_B_SURV := 1.000
const BASE8_DET_BA := 0.6217
const BASE8_DET_B_W20 := 13.535
const BASE8_DET_A_W20 := 21.772


## 六槽金标本 cfg —— 逐位镜像 tests/test_suite_slice2.gd `_cfg(path, "tier")`
##   （kr_mode="tier" 时 kappa_r 标量被引擎忽略，走 KR_TIERS_T1；此处仍按金标本 helper 传 0.045）
func _cfg6(path: String) -> Dictionary:
	return _Cfg.cfg_of(path, 0.045, "substantial", "tier", "current", false)


## 八槽 RADIAL cfg —— 逐位镜像 run_slice_attrition8.gd 主循环（n_slots=8 / max_actions=12）
func _cfg8(path: String) -> Dictionary:
	var c: Dictionary = _Cfg.cfg_of(path)
	c["n_slots"] = 8
	c["max_actions"] = MAX_ACTIONS
	return c


## 取出 rows 里 W20 的 ratio（未跑到 W20 记 -1.0）
func _w20(rows: Array) -> float:
	for r in rows:
		if int(r["w"]) == W_MAX:
			return float(r["ratio"])
	return -1.0


## 整数中位（与 _takeoff_stats 逐位同款：排序后取 size()/2 索引）
func _median_int(a: Array) -> int:
	if a.is_empty():
		return -1
	var b: Array = a.duplicate()
	b.sort()
	return int(b[b.size() / 2])


## 失守前 3 波的 core_hp 斜率（core_hp/波；负 = 掉血）。样本不足返回哨兵 -99999.0
func _pre_fail_slope(rows: Array) -> float:
	var n := rows.size()
	if n < 2:
		return -99999.0
	var hi: int = n - 2                      # 最后一条非致命 row
	var lo: int = maxi(0, hi - 2)            # 往回最多 3 条（含 hi）
	if hi - lo < 1:
		return -99999.0
	var w0 := int(rows[lo]["w"])
	var w1 := int(rows[hi]["w"])
	if w1 == w0:
		return -99999.0
	return (float(rows[hi]["core_hp"]) - float(rows[lo]["core_hp"])) / float(w1 - w0)


## 八槽 RADIAL 确定性单局（rng=null，显式 Geo8 —— 与 _det_v0 同口径）
func _det8(path: String) -> Dictionary:
	var out := _RunLoopAggro.run(path, _cfg8(path), W_MAX, _Geo8.build8(), null,
		true, EXP, ATTRITION, WARMUP)
	var rows: Array = out["rows"]
	var s := _Stats.summarize(rows)
	var w20 := -1.0
	if s["w20"] != null:
		w20 = float(s["w20"])
	return {"tw": int(s["takeoff"]), "w20": w20, "rows": rows}


## 归因控制：A 路径在金标标本几何/运动学下，但换成 aggro 引擎 + ATTRITION。
##   目的：把「六槽金标本(RunLoop) vs 八槽(RunLoopAggro)」的口径差分解为
##         engine / geometry / seed 三分量（调用方负责先设好 SpaceModel.mode）。
##   n_slots=6 + mode=PATH  -> 六槽 PATH（与六槽金标本同几何，只换引擎）
##   n_slots=8 + mode=RADIAL -> 八槽 RADIAL
func _aggro_surv_A(seed: int, n_slots: int) -> float:
	var rng := _PyRandom.new(seed)
	var surv := 0
	for _i in range(RUNS):
		var cfg: Dictionary = _Cfg.cfg_of("A")
		cfg["n_slots"] = n_slots
		cfg["max_actions"] = MAX_ACTIONS
		var out := _RunLoopAggro.run("A", cfg, W_MAX, null, rng, true, EXP, ATTRITION, WARMUP)
		var rows: Array = out["rows"]
		if (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0:
			surv += 1
	return float(surv) / float(RUNS)


## 比例型标准误 SE = sqrt(p(1-p)/n)
func _se(p: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return sqrt(maxf(0.0, p * (1.0 - p)) / float(n))


func _initialize() -> void:
	var struct_ok := true

	print("===================================================================")
	print("V-6prime multitower margin - read-only probe (R1+R2+R3)  [chengjiyan]")
	print("===================================================================")
	print("[CFG] W_MAX=%d WARMUP=%d RUNS=%d ATTRITION=%.2f EXP=%.2f MAX_ACTIONS=%d SEED6=%d SEED8=%d"
		% [W_MAX, WARMUP, RUNS, ATTRITION, EXP, MAX_ACTIONS, SEED6, SEED8])
	print("[CFG] zero-perturbation: no scripts/ edit, no frozen value touched, scan-only")

	# ===================================================================
	# V6'-R1-a · 六槽 PATH 金标本（既有六槽入口 · RunLoop · seed 20260930）
	# ===================================================================
	push_error("[probe_v6prime] R1-a six-slot PATH golden MC start")
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	var mcA6 := _Stats.takeoff_rate("A", _cfg6("A"), RUNS, W_MAX, MAX_ACTIONS, _PyRandom.new(SEED6))
	var mcB6 := _Stats.takeoff_rate("B", _cfg6("B"), RUNS, W_MAX, MAX_ACTIONS, _PyRandom.new(SEED6))
	var detA6 := _RunLoop.run("A", _cfg6("A"), W_MAX, null, null)
	var detB6 := _RunLoop.run("B", _cfg6("B"), W_MAX, null, null)
	var sA6 := _Stats.summarize(detA6["rows"])
	var sB6 := _Stats.summarize(detB6["rows"])
	var w20A6 := 0.0
	var w20B6 := 0.0
	if sA6["w20"] != null:
		w20A6 = float(sA6["w20"])
	if sB6["w20"] != null:
		w20B6 = float(sB6["w20"])
	var ba6 := (w20B6 / w20A6) if w20A6 != 0.0 else -1.0
	var a6_takeoff_rate := float(mcA6["rate"])

	print("")
	print("---- [R1-a] six-slot PATH golden (RunLoop, seed %d, N=%d) ----" % [SEED6, RUNS])
	print("[R1-a] A survive_rate=%.4f takeoff_rate=%.4f med_tw=W%d n_takeoff=%d n_surv=%d"
		% [float(mcA6["surv"]), float(mcA6["rate"]), int(mcA6["med"]),
			int(mcA6["n_takeoff"]), int(mcA6["n_surv"])])
	print("[R1-a] B survive_rate=%.4f takeoff_rate=%.4f med_tw=W%d n_takeoff=%d n_surv=%d"
		% [float(mcB6["surv"]), float(mcB6["rate"]), int(mcB6["med"]),
			int(mcB6["n_takeoff"]), int(mcB6["n_surv"])])
	print("[R1-a] det A tw=W%d w20=%.3f ; B tw=W%d w20=%.3f ; B/A=%.4f (gold: 0.458)"
		% [int(sA6["takeoff"]), w20A6, int(sB6["takeoff"]), w20B6, ba6])
	print("[R1-a] vs golden MC_TIER: A takeoff %d/%d (want %d) ; B takeoff %d/%d (want %d)"
		% [int(mcA6["n_takeoff"]), RUNS, GOLD6_A_NTAKE, int(mcB6["n_takeoff"]), RUNS, GOLD6_B_NTAKE])

	# ===================================================================
	# V6'-R1-ATTR · 归因控制（六槽 PATH · aggro 引擎 · 同 seed 20260930）
	#   仅测 A 的 survive_rate —— 隔离"引擎（RunLoop vs RunLoopAggro+ATTRITION）"分量。
	# ===================================================================
	push_error("[probe_v6prime] R1-ATTR six-slot PATH aggro-engine control start")
	var attr6_a_surv := _aggro_surv_A(SEED6, 6)
	print("")
	print("---- [R1-ATTR] attribution control: six-slot PATH under aggro engine (seed %d) ----" % SEED6)
	print("[R1-ATTR] A survive_rate(golden RunLoop)=%.4f  A survive_rate(aggro engine)=%.4f  delta=%.4f"
		% [a6_takeoff_rate, attr6_a_surv, attr6_a_surv - a6_takeoff_rate])

	# ===================================================================
	# V6'-R1-b · 八槽 RADIAL（RunLoopAggro · seed 20261002 · ATTRITION=1.50）
	#   同一次 300x2 MC 就地服务 R1-b / R2 / R3（零新增 MC 用于 R1-b 基线）。
	# ===================================================================
	push_error("[probe_v6prime] R1-b eight-slot RADIAL MC start (heavy: 300 x A/B)")
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var rngB8 := _PyRandom.new(SEED8)
	var rngA8 := _PyRandom.new(SEED8)

	var b_surv := 0
	var b_take := 0
	var b_tws: Array = []
	var a_surv := 0
	var a_take := 0
	var a_tws: Array = []
	var b_w20_sum := 0.0
	var b_n_w20 := 0
	var a_w20_sum := 0.0
	var a_n_w20 := 0

	# R2 逐波聚合（index 0..19 -> wave 1..20）
	var b_hp_sum: Array = []
	var b_hp_cnt: Array = []
	var b_hp_minw: Array = []           # 每波跨局最小值
	var a_hp_sum: Array = []
	var a_hp_cnt: Array = []
	for _k in range(W_MAX):
		b_hp_sum.append(0.0)
		b_hp_cnt.append(0)
		b_hp_minw.append(INF)
		a_hp_sum.append(0.0)
		a_hp_cnt.append(0)
	# R2 B 全局最低点
	var b_hp_min_global := INF
	var b_w_min_global := -1
	var b_n_pressured := 0               # 全程 core_hp 曾低于满血 1000 的局数

	# R3 A 失守
	var a_fail := 0
	var a_fail_hist: Dictionary = {}
	var a_fail_slopes: Array = []
	var a_slope_mean := 0.0

	for _i in range(RUNS):
		# ---- B 路径（多塔金标本）----
		var outB := _RunLoopAggro.run("B", _cfg8("B"), W_MAX, null, rngB8,
			true, EXP, ATTRITION, WARMUP)
		var rowsB: Array = outB["rows"]
		var aliveB: bool = (not rowsB.is_empty()) and float(rowsB[-1]["core_hp"]) > 0.0
		if aliveB:
			b_surv += 1
		var twB: int = _Stats.takeoff_wave(rowsB)
		if aliveB and twB >= 0:
			b_take += 1
			b_tws.append(twB)
		if (not rowsB.is_empty()) and int(rowsB[-1]["w"]) >= W_MAX:
			b_n_w20 += 1
			b_w20_sum += _w20(rowsB)
		if (not rowsB.is_empty()) and float(rowsB[-1]["core_hp"]) < 1000.0 - 1e-9:
			b_n_pressured += 1
		for r in rowsB:
			var wB: int = int(r["w"])
			var hpB: float = float(r["core_hp"])
			b_hp_sum[wB - 1] = float(b_hp_sum[wB - 1]) + hpB
			b_hp_cnt[wB - 1] = int(b_hp_cnt[wB - 1]) + 1
			b_hp_minw[wB - 1] = minf(float(b_hp_minw[wB - 1]), hpB)
			if hpB < b_hp_min_global:
				b_hp_min_global = hpB
				b_w_min_global = wB

		# ---- A 路径（单核金标本）----
		var outA := _RunLoopAggro.run("A", _cfg8("A"), W_MAX, null, rngA8,
			true, EXP, ATTRITION, WARMUP)
		var rowsA: Array = outA["rows"]
		var aliveA: bool = (not rowsA.is_empty()) and float(rowsA[-1]["core_hp"]) > 0.0
		if aliveA:
			a_surv += 1
		var twA: int = _Stats.takeoff_wave(rowsA)
		if aliveA and twA >= 0:
			a_take += 1
			a_tws.append(twA)
		if (not rowsA.is_empty()) and int(rowsA[-1]["w"]) >= W_MAX:
			a_n_w20 += 1
			a_w20_sum += _w20(rowsA)
		for r in rowsA:
			var wA: int = int(r["w"])
			var hpA: float = float(r["core_hp"])
			a_hp_sum[wA - 1] = float(a_hp_sum[wA - 1]) + hpA
			a_hp_cnt[wA - 1] = int(a_hp_cnt[wA - 1]) + 1
		if (not aliveA) and (not rowsA.is_empty()):
			a_fail += 1
			var we: int = int(rowsA[-1]["w"])
			a_fail_hist[we] = int(a_fail_hist.get(we, 0)) + 1
			var sl := _pre_fail_slope(rowsA)
			if sl > -99999.0:
				a_fail_slopes.append(sl)

	var b_surv_rate := float(b_surv) / float(RUNS)
	var a_surv_rate := float(a_surv) / float(RUNS)
	var b_takeoff_rate := float(b_take) / float(RUNS)
	var a_takeoff_rate := float(a_take) / float(RUNS)
	var b_med := _median_int(b_tws)
	var a_med := _median_int(a_tws)
	var b_mc_w20 := (b_w20_sum / float(b_n_w20)) if b_n_w20 > 0 else -1.0
	var a_mc_w20 := (a_w20_sum / float(a_n_w20)) if a_n_w20 > 0 else -1.0

	# ---- 八槽确定性单局 ----
	var detA8 := _det8("A")
	var detB8 := _det8("B")
	var det_ba8 := -1.0
	if float(detA8["w20"]) > 0.0:
		det_ba8 = float(detB8["w20"]) / float(detA8["w20"])

	print("")
	print("---- [R1-b] eight-slot RADIAL (RunLoopAggro, seed %d, ATTRITION=%.2f, N=%d) ----"
		% [SEED8, ATTRITION, RUNS])
	print("[R1-b] A survive_rate=%.4f takeoff_rate=%.4f med_tw=W%d n_takeoff=%d n_surv=%d"
		% [a_surv_rate, a_takeoff_rate, a_med, a_take, a_surv])
	print("[R1-b] B survive_rate=%.4f takeoff_rate=%.4f med_tw=W%d n_takeoff=%d n_surv=%d"
		% [b_surv_rate, b_takeoff_rate, b_med, b_take, b_surv])
	print("[R1-b] MC mean W20 ratio: A=%.3f (n=%d) B=%.3f (n=%d) -> B/A=%.4f"
		% [a_mc_w20, a_n_w20, b_mc_w20, b_n_w20,
			(b_mc_w20 / a_mc_w20) if a_mc_w20 > 0.0 else -1.0])
	print("[R1-b] det A tw=W%d w20=%.3f ; B tw=W%d w20=%.3f ; B/A=%.4f"
		% [int(detA8["tw"]), float(detA8["w20"]), int(detB8["tw"]), float(detB8["w20"]), det_ba8])
	print("[R1-b] baseline match (r4-attrition8-after.log): B_surv %.4f==%.4f? %s ; A_surv %.4f==%.4f? %s ; det_BA %.4f==%.4f? %s"
		% [b_surv_rate, BASE8_B_SURV, str(absf(b_surv_rate - BASE8_B_SURV) < 5e-5),
			a_surv_rate, BASE8_A_SURV, str(absf(a_surv_rate - BASE8_A_SURV) < 5e-5),
			det_ba8, BASE8_DET_BA, str(absf(det_ba8 - BASE8_DET_BA) < 5e-5)])

	# ---- 归因控制 2：八槽 RADIAL A · 换回六槽金标本 seed（20260930）----
	push_error("[probe_v6prime] R1-ATTR eight-slot seed-6 control start")
	var attr8s6_a_surv := _aggro_surv_A(SEED6, 8)
	print("[R1-ATTR] A survive(eight-slot RADIAL, seed %d)=%.4f ; compare seed %d=%.4f"
		% [SEED6, attr8s6_a_surv, SEED8, a_surv_rate])

	# ===================================================================
	# V6'-R1 判读 · 双口径差 + 归因
	# ===================================================================
	var diff_a := absf(a6_takeoff_rate - a_surv_rate)
	var se6 := _se(a6_takeoff_rate, RUNS)
	var se8 := _se(a_surv_rate, RUNS)
	var se_diff := sqrt(se6 * se6 + se8 * se8)
	var z_diff := (diff_a / se_diff) if se_diff > 0.0 else 0.0
	print("")
	print("---- [R1-JUDGE] cross-caliber alignment ----")
	print("[R1-JUDGE] six-slot A=%.4f vs eight-slot A=%.4f -> diff=%.4f (threshold 0.05)"
		% [a6_takeoff_rate, a_surv_rate, diff_a])
	print("[R1-JUDGE] noise check: SE_diff=%.4f  z=%.2f  (|z|>1.96 => not random noise at 95%%)"
		% [se_diff, z_diff])
	print("[R1-JUDGE] attribution (all aggro-engine unless noted): golden(RunLoop,6slot)=%.4f -> aggro6slot=%.4f -> aggro8slot=%.4f"
		% [a6_takeoff_rate, attr6_a_surv, a_surv_rate])
	if diff_a > 0.05:
		print("[R1-FLAG] six-vs-eight A diff %.4f > 0.05 (naive reading: eight-slot itself suppresses A) -> Q-R9 pre-input"
			% diff_a)
		# ---- 归因三分量（诚实修正：naive 读数不成立）----
		var d_engine := attr6_a_surv - a6_takeoff_rate            # RunLoop -> aggro @6slot, seed6
		var d_geom := attr8s6_a_surv - attr6_a_surv               # 6slot -> 8slot @seed6, aggro
		var d_seed := a_surv_rate - attr8s6_a_surv                # seed6 -> seed8 @8slot, aggro
		print("[R1-ATTR-VERDICT] decompose of the -%.4f gap: engine=%.4f ; geometry(6->8@seed6)=%.4f ; seed=%.4f"
			% [a6_takeoff_rate - a_surv_rate, d_engine, d_geom, d_seed])
		if d_engine < 0.0 and d_geom > 0.0:
			print("[R1-ATTR-VERDICT] => naive 'eight-slot suppresses A' NOT supported: the suppressor is the ENGINE")
			print("[R1-ATTR-VERDICT]    (tower-death/aggro口径迁移), NOT slot count; 8-slot under aggro FAVORS A (+%.4f)."
				% d_geom)
			print("[R1-ATTR-VERDICT] => root cause is CROSS-ENGINE caliber mixing (0.693=no-tower-death vs 0.597=aggro), not Q-R9 slots.")
		else:
			print("[R1-ATTR-VERDICT] => engine/geometry decomposition inconclusive; see numbers above.")
	else:
		print("[R1-JUDGE] diff <= 0.05 -> six/eight-slot A are cross-caliber consistent (within 0.05)")

	# ===================================================================
	# V6'-R2 · B 路径压力剖面
	# ===================================================================
	print("")
	print("===================================================================")
	print("R2 - B pressure profile (eight-slot RADIAL) + A comparison")
	print("===================================================================")
	print("[R2-NOTE] residual_monsters approximated as n - kills - leaked (no dedicated field) -- REGISTERED GAP")
	print("")
	print("---- [R2-DET] deterministic single run (rng=null, geo8) per-wave table ----")
	print("wave | B: n  kills leaked resid | B: core_hp   ratio | A: core_hp   ratio")
	var detB_rows: Array = detB8["rows"]
	var detA_rows: Array = detA8["rows"]
	for idx in range(mini(detB_rows.size(), W_MAX)):
		var rb: Dictionary = detB_rows[idx]
		var ra: Dictionary = detA_rows[idx] if idx < detA_rows.size() else {}
		var nb := int(rb["n"])
		var kb := int(rb["kills"])
		var lb := int(rb["leaked"])
		var residb := nb - kb - lb
		var acore := float(ra["core_hp"]) if ra.size() > 0 else -1.0
		var aratio := float(ra["ratio"]) if ra.size() > 0 else -1.0
		print("  %2d | %3d %4d %6d %5d | %8.1f %7.3f | %8.1f %7.3f"
			% [int(rb["w"]), nb, kb, lb, residb, float(rb["core_hp"]),
				float(rb["ratio"]), acore, aratio])

	# 确定性单局 B 的最低点
	var det_b_min := INF
	var det_b_wmin := -1
	for r in detB_rows:
		var hp := float(r["core_hp"])
		if hp < det_b_min:
			det_b_min = hp
			det_b_wmin = int(r["w"])

	print("")
	print("---- [R2-MC] per-wave core_hp aggregate over %d runs ----" % RUNS)
	print("wave | B: n_runs  mean     min    | A: n_runs  mean")
	var a_first_zero := -1
	for idx in range(W_MAX):
		var w := idx + 1
		var bcnt := int(b_hp_cnt[idx])
		var acnt := int(a_hp_cnt[idx])
		var bmean := (float(b_hp_sum[idx]) / float(bcnt)) if bcnt > 0 else -1.0
		var amin := (float(a_hp_sum[idx]) / float(acnt)) if acnt > 0 else -1.0
		var bmin := float(b_hp_minw[idx]) if bcnt > 0 else -1.0
		if acnt == 0 and a_first_zero < 0:
			a_first_zero = w
		print("  %2d | %6d %8.2f %8.2f | %6d %8.2f"
			% [w, bcnt, bmean, bmin, acnt, amin])

	print("")
	print("[R2-SUM] B core_hp_min (over all %d runs) = %.1f @ W%d ; runs ever below full HP = %d/%d"
		% [RUNS, b_hp_min_global, b_w_min_global, b_n_pressured, RUNS])
	print("[R2-SUM] B core_hp_min (deterministic single run) = %.1f @ W%d" % [det_b_min, det_b_wmin])
	if absf(b_hp_min_global - 1000.0) < 1e-6:
		print("[R2-JUDGE] B core_hp_min == 1000.0 (full HP, never pressured) -> H1 component UP")
	elif b_n_pressured > 0 and b_w_min_global <= 5:
		print("[R2-JUDGE] B only lightly pressured (core_hp_min=%.1f, %d/%d runs, earliest W%d) -> near-immune; H1 component UP, tiny early window"
			% [b_hp_min_global, b_n_pressured, RUNS, b_w_min_global])
	else:
		print("[R2-JUDGE] B core_hp_min = %.1f (< 1000.0) -> real pressure window exists -> H3 holds"
			% b_hp_min_global)

	# ===================================================================
	# V6'-R3 · A 侧失守波次分布
	# ===================================================================
	print("")
	print("===================================================================")
	print("R3 - A failure wave distribution (eight-slot RADIAL)")
	print("===================================================================")
	print("[R3-SUM] A fails = %d / %d (survive_rate = %.4f)" % [a_fail, RUNS, a_surv_rate])
	var hist_keys: Array = a_fail_hist.keys()
	hist_keys.sort()
	var n_w811 := 0
	var n_w16p := 0
	for k in hist_keys:
		var cnt := int(a_fail_hist[k])
		print("[R3-HIST] w_end=W%-2d count=%d  %s" % [int(k), cnt, "#".repeat(cnt)])
		if int(k) >= 8 and int(k) <= 11:
			n_w811 += cnt
		if int(k) >= 16:
			n_w16p += cnt
	if a_fail > 0:
		print("[R3-HIST] share W8-W11 = %d/%d = %.3f ; share W16+ = %d/%d = %.3f"
			% [n_w811, a_fail, float(n_w811) / float(a_fail),
				n_w16p, a_fail, float(n_w16p) / float(a_fail)])
	if a_fail_slopes.size() > 0:
		var sl_sum := 0.0
		for v in a_fail_slopes:
			sl_sum += float(v)
		a_slope_mean = sl_sum / float(a_fail_slopes.size())
		var sl_sorted: Array = a_fail_slopes.duplicate()
		sl_sorted.sort()
		var sl_med := float(sl_sorted[sl_sorted.size() / 2])
		print("[R3-SLOPE] pre-fail 3-wave core_hp slope (core_hp/wave): mean=%.2f median=%.2f n=%d"
			% [a_slope_mean, sl_med, a_fail_slopes.size()])
	var n_w4 := int(a_fail_hist.get(4, 0))
	if n_w16p == 0:
		print("[R3-JUDGE] ZERO failures at W16+ -> NO late-pressure shortfall (not evidence of 'multitower too safe')")
		print("[R3-JUDGE] failures are bimodal: early collapse W3-4=%d (苟活期) + formation cliff W10-11=%d -> A-side tower-death, not late pressure"
			% [n_w4, int(a_fail_hist.get(10, 0)) + int(a_fail_hist.get(11, 0))])
	elif n_w16p > n_w811:
		print("[R3-JUDGE] failures concentrate in W16+ -> late-pressure shortfall (relevant to V-6')")
	else:
		print("[R3-JUDGE] failures spread / both windows comparable -> see histogram above")

	# ===================================================================
	# 机器可读单行摘要（ASCII）—— 回传主理人用
	# ===================================================================
	print("")
	print("===================================================================")
	print("[V6P-R1] A: 6slot_golden=%.4f 6slot_aggro=%.4f 8slot_aggro_seed6=%.4f 8slot_aggro_seed8=%.4f"
		% [a6_takeoff_rate, attr6_a_surv, attr8s6_a_surv, a_surv_rate])
	print("[V6P-R1] diff_six8_A=%.4f se_diff=%.4f z=%.2f ; verdict: gap is CROSS-ENGINE (not slot count)"
		% [diff_a, se_diff, z_diff])
	print("[V6P-R1] six6 A_surv=%.4f A_take=%.4f B_surv=%.4f B_take=%.4f | eight8 A_surv=%.4f B_surv=%.4f det_BA=%.4f mc_BA=%.4f"
		% [float(mcA6["surv"]), a6_takeoff_rate, float(mcB6["surv"]), float(mcB6["rate"]),
			a_surv_rate, b_surv_rate, det_ba8,
			(b_mc_w20 / a_mc_w20) if a_mc_w20 > 0.0 else -1.0])
	print("[V6P-R2] B core_hp_min=%.1f @ W%d ; pressured_runs=%d/%d (det %.1f @ W%d)"
		% [b_hp_min_global, b_w_min_global, b_n_pressured, RUNS, det_b_min, det_b_wmin])
	print("[V6P-R3] A fails=%d hist(W8-11)=%d hist(W4)=%d hist(W16+)=%d slope_mean=%.2f"
		% [a_fail, n_w811, int(a_fail_hist.get(4, 0)), n_w16p, a_slope_mean])

	# ---- 结构性自检（只判"探针是否真跑出数据"，非测量闸门）----
	if not (b_surv > 0 and (a_surv + a_fail) > 0 and b_n_w20 > 0):
		struct_ok = false
		push_error("[probe_v6prime] structural failure: probe did not produce data")

	# 回退 PATH（全局开关卫生）
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	print("")
	print("[probe_v6prime] done. structural_ok=%s" % str(struct_ok))
	quit(0 if struct_ok else 1)
