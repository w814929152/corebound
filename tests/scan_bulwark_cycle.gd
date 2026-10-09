extends SceneTree
##
## 🔒 V-8 · 肉盾循环（残响 Reverb）6 臂扫描器（QG-RADIAL-01）
##
## 规格来源（🔴 全部照抄，跑前写死、跑后不改）：
##   `docs/phase3/qg-radial/corebound-bulwark-death-cycle-v3.md` §6.2 臂设计 / §6.3 判据 /
##   §6.4 预注册判读线 / §6.5 UPTIME_CAP / §10 实现交接点
##   `docs/phase3/qg-radial/corebound-bulwark-death-cycle-v2.md` §7.2-§7.5（4 臂口径来源）
##
## 6 臂（🔴 B0–B3 必须残响 OFF —— 残响时长 = disabled 时长 = N，开残响会让 N 扫描被混淆）：
##   B0  复活 off  残响 off  -> V-4 肉盾基线复现（预期 surv_A ≈ 0.580）；Δ 的分母
##   B1  即时 N_short(0.5s) 残响 off -> N 档1（纯净）
##   B2  即时 N_long (2.0s) 残响 off -> N 档2（纯净）
##   B3  波首（N→∞ 极限）   残响 off -> 时点符号实证
##   B4  复活 off           残响 on  -> 残响净效应 = R-B3 直接实证
##   B5  即时 N_short       残响 on  -> 完整机制臂（真判读对象）
##
## 参数锁死（v3 §6.2）：八槽 RADIAL · n_slots=8 · aggro=true · exp=0.6 · attrition=1.50
##   · warmup=2 · max_actions=12 · max_wave=20 · seed PyRandom(20261002) · A 路径(max_towers=2)
##   · R_reverb = 1.0 × AGGRO_R = 9.0 · s_reverb = 0.30（v3 §11.2 起步值）
##   · N_short = 5% × t_reach = 0.5s · N_long = 20% × t_reach = 2.0s（t_reach = 10.0）
##
## 🔴 判据（v3 §6.3 / §6.4）：
##   主判据    Δ_surv 双侧 95% CI（独立两比例 SE），判读线 ±0.035
##   机制主判据 bulwark_uptime ↑ · gap_leak ↓
##   残响主判据 reverb_slow_seconds > 0 · gap_leak(B4) < gap_leak(B0) 显著
##   预注册否决 ① gap_leak(B4) → 0 = 残响退化成嘲讽等价物（不得采纳）
##              ② n_td_form → 0 或 bulwark_uptime ≥ UPTIME_CAP(0.90绝对 +40pp相对，取严) = 过度
##   硬断言     reverb_aggro_disturb = 0 · revive_misqualify = 0
##
## ⚠ 输出纪律：ASCII only（Windows GBK 控制台会把 CJK 打烂）。
##
## ══════════════════════════════════════════════════════════════════════════
## 🆕 V-8b · 残响剂量扫描（按住"离线时长"混淆 · 纯净边际）
##
## 规格来源（`docs/phase3/qg-radial/v8-adjudication.md` §2 / §7.3 选项 A）：
##   V-8 的 B4 是**混淆臂**（残响时长 = disabled 时长 = N ⇒ 残响全程在场 与
##   "肉盾整波离线"焊死）→ B4 的负面 Δ 无法归因于残响。残响的真实边际（B5−B1）
##   是小幅正向但**次感知**（剂量太弱：覆盖 4.6 只/局、挽回 0.65 只/局）。
##
## 🔴 V-8b 口径（去混淆）：
##   ① **全部臂复活 ON**（repair_on_disable=9 · N=0.5s · K=1 逐位相同）
##      → 按住"离线时长"这个混淆变量，所有臂肉盾离线时长一致。
##   ② 只变残响的 (s_reverb, R_reverb) → 差值 = 残响净贡献（纯净边际）。
##   ③ 主判读 **Δ(剂量臂 vs C0)**：C0 = 复活ON + 残响OFF（= V-8 的 B1，对照分母）。
##
## 4 臂（剂量阶梯，R 优先 —— V-8 已证覆盖太薄，半径是疑似瓶颈约束）：
##   C0  复活ON  残响OFF                    -> 对照分母（= V-8 B1）
##   V1  复活ON  残响ON  s=0.30 R=1.0x(9.0) -> V-8 剂量锚点（= V-8 B5，同批复现）
##   V2  复活ON  残响ON  s=0.30 R=1.5x(13.5)-> 只抬半径（覆盖率 ×2.25 面积）
##   V3  复活ON  残响ON  s=0.50 R=1.5x(13.5)-> 半径+减速双抬（上界剂量）
##   🟡 未填格 (s=0.50, R=1.0×)：若 V3 出信号而需把效应归因到 s 还是 R，再补 1 臂。
##
## 判据（沿用 V-8，文策渊终审调整）：
##   主判据    Δ_surv 双侧 95% CI（独立两比例 SE），判读线 ±0.035
##   机制量    reverb_slow_seconds（上游直接读数）· gap_leak（🟡 降级为机制活动量，
##             **不作胜率代理** —— B3 悖论已证 gap_leak↓ ≠ 胜率↑）· bulwark_uptime
##             · n_td_form（护栏，唯一度量"塔死亡还有没有牙齿"的量）
##   预注册否决 ① gap_leak(最强剂量臂) → 0 = 残响退化成嘲讽等价物（不采纳）
##               ② n_td_form → 0 或 bulwark_uptime ≥ UPTIME_CAP = 过度
##   硬断言    reverb_aggro_disturb = 0 · revive_misq = 0（revive_refused 是"闸门
##             正确拒绝"= 诊断量，不算断言 —— V-8 已拆分）
## ══════════════════════════════════════════════════════════════════════════
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_bulwark_cycle.gd
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_bulwark_cycle.gd RUNS=1480
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_bulwark_cycle.gd RUNS=1480 ARMS=4
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_bulwark_cycle.gd RUNS=1480 ARMS=V8B
##
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const RUNS_DEFAULT := 300
const ARMS_DEFAULT := 6
const MAX_WAVE := 20
const ATTRITION := 1.50
const WARMUP := 2
const SEED := 20261002
const Z_CRIT := 1.959964        # two-sided alpha=0.05
const ALPHA := 0.05
# v3 §6.3 判读线：Δ_surv 双侧 CI 判读线 ±0.035
const DELTA_LINE := 0.035
# tower-death 口径（run_slice_attrition8 / v7：W6..W12）= X_form，主口径
const W_SURV_END := 5
const W_FORM_END := 12
# v3 §6.5 UPTIME_CAP（跑前写死的双判据，取严）
const UPTIME_CAP_ABS := 0.90
const UPTIME_GAIN_CAP := 0.40    # +40pp 相对
# v3 §6.3 护栏：支柱漂移 / 反向（刷死亡）
const SURV_DRIFT_CAP := 0.817
const TD_GAIN_CAP := 0.26        # n_td_form 涨幅 < +26%
# v3 §6.2 护栏②：B0 前 300 局须复现 V-4 的 0.580
const BASE_N := 300
const BASE_SURV_V4 := 174        # 0.580 × 300
# v3 §6.2 护栏③：n_revive_eligible >= 200/臂，否则 INCONCLUSIVE
const ELIG_MIN := 200
# 残响过度否决（v3 §6.4）：gap_leak(B4) → 0
const GAP_LEAK_ZERO_EPS := 0.02  # 每局均值 < 0.02 视为 "→ 0"

# ---- 臂定义： [tag, repair_on_disable, revive_n_seconds, reverb_enabled] ----
const ARM_DEFS := [
	["B0", 0, 0.5, false],
	["B1", 9, 0.5, false],
	["B2", 9, 2.0, false],
	["B3", 11, 0.5, false],
	["B4", 0, 0.5, true],
	["B5", 9, 0.5, true],
]

# ---- 🆕 V-8b 臂定义：[tag, repair_on_disable, N, reverb_enabled, s_reverb, R_reverb] ----
#   🔴 复活参数（repair=9 / N=0.5 / K=1）**四臂逐位相同** —— 按住离线时长混淆。
#   🔴 只允许 s_reverb / R_reverb 变化 → 任何 Δ 都是残响的纯净边际。
const ARM_DEFS_V8B := [
	["C0", 9, 0.5, false, 0.30, 9.0],    # 对照分母（= V-8 B1）
	["V1", 9, 0.5, true, 0.30, 9.0],     # 剂量锚点（= V-8 B5）
	["V2", 9, 0.5, true, 0.30, 13.5],    # 只抬半径 R=1.5 × AGGRO_R
	["V3", 9, 0.5, true, 0.50, 13.5],    # 半径 + 减速双抬（上界剂量）
]

var RUNS := RUNS_DEFAULT
var N_ARMS := ARMS_DEFAULT
var ARM_SET := "V8"                     # "V8" | "V8B"
var ARM_DEFS_ACTIVE: Array = ARM_DEFS    # 当前生效臂表（V-8 / V-8b 二选一）


# ─────────────────────────────────────────────────────────────────────────────
# 一臂 = RUNS 局 A 路径
# ─────────────────────────────────────────────────────────────────────────────
func _run_arm(tag: String, repair_mode: int, n_sec: float, reverb_on: bool,
		s_rev := 0.30, r_rev := 9.0) -> Dictionary:
	var rng := _PyRandom.new(SEED)
	var cfgA := _Cfg.cfg_of("A")
	cfgA["n_slots"] = 8
	cfgA["max_actions"] = 12
	cfgA["repair_on_disable"] = repair_mode
	cfgA["revive_n_seconds"] = n_sec
	cfgA["revive_k_per_wave"] = 1
	cfgA["reverb_enabled"] = reverb_on
	cfgA["reverb_radius"] = r_rev    # V-8: 1.0 × AGGRO_R = 9.0；V-8b: 9.0 / 13.5
	cfgA["reverb_slow"] = s_rev      # V-8: 0.30；V-8b: 0.30 / 0.50
	cfgA["bulwark_diag"] = true      # 🔴 仅埋点开关；不影响任何战斗浮点
	var n_surv := 0
	var n_td := 0                    # X_form >= 1（主口径）
	var b_surv := 0                  # 前 BASE_N 局存活数（B0 基线护栏）
	# 累计诊断量（跨局求和）
	var S := {
		"bulw_alive": 0.0, "bulw_total": 0.0, "gap_leak": 0.0, "gap_unlocked": 0.0,
		"rev_slow": 0.0, "rev_up": 0.0, "rev_cov": 0.0, "rev_cov_leak": 0.0, "rev_disturb": 0.0,
		"bulw_alive_a": 0.0, "bulw_total_a": 0.0, "ticks_a": 0.0,
		"revive_fired": 0.0, "revive_elig": 0.0, "revive_redied": 0.0, "revive_misq": 0.0,
		"revive_refused": 0.0, "carry_death": 0.0, "nonexp_death": 0.0, "nosnap_death": 0.0,
		"ticks": 0.0,
	}
	var per_gap: Array = []
	var per_revslow: Array = []
	for i in range(RUNS):
		# 🔴 diag_out 必须给足 6 槽（V-7 的 shape）：`repair_on_disable != 0` 时
		#    run_loop_aggro 会把它注入 c["diag"] 并索引 diag[1]/[4]/[5]。
		#    🟢 这里只是占位（V-8 的重启不走 shop_ai），不给足长度会 Index 越界。
		var per_diag := [0, 0, 0, 0.0, 0, 0]
		var out := _RunLoopAggro.run("A", cfgA, MAX_WAVE, null, rng, true, 0.6, ATTRITION,
			WARMUP, false, true, false, 0.0, per_diag)
		var rows: Array = out["rows"]
		var survived := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		var xf := _run_xform(rows)
		if survived:
			n_surv += 1
		if xf > 0:
			n_td += 1
		if i < BASE_N and survived:
			b_surv += 1
		var v8 = out.get("v8", {})
		for k in S.keys():
			S[k] = float(S[k]) + float(v8.get(k, 0.0))
		per_gap.append(float(v8.get("gap_leak", 0.0)))
		per_revslow.append(float(v8.get("rev_slow", 0.0)))
		if (i + 1) % 200 == 0:
			push_error("[V-8][%s] %d/%d" % [tag, i + 1, RUNS])
	return {
		"tag": tag,
		"surv": float(n_surv) / float(RUNS),
		"n_surv": n_surv,
		"n_td": n_td,
		"b_surv": b_surv,
		"S": S,
		"per_gap": per_gap,
		"per_revslow": per_revslow,
		"gap_leak_mean": _mean(per_gap),
		"reverb_slow_mean": _mean(per_revslow),
		"bulwark_uptime": (float(S["bulw_alive"]) / float(S["bulw_total"])) if float(S["bulw_total"]) > 0.0 else -1.0,
		"bulwark_uptime_act": (float(S["bulw_alive_a"]) / float(S["bulw_total_a"])) if float(S["bulw_total_a"]) > 0.0 else -1.0,
		"reverb_uptime": (float(S["rev_up"]) / float(S["ticks"])) if float(S["ticks"]) > 0.0 else 0.0,
		"reverb_covered": float(S["rev_cov"]) / float(RUNS),
		"reverb_leak_save": (float(S["rev_cov"]) - float(S["rev_cov_leak"])) / float(RUNS),
	}


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _sd(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := _mean(a)
	var s := 0.0
	for v in a:
		var d: float = float(v) - m
		s += d * d
	return sqrt(s / float(a.size() - 1))


## X_form：W6..W12 窗口内的塔死亡数（基线口径）
func _run_xform(rows: Array) -> int:
	var xf := 0
	for r in rows:
		var wn: int = int(r["w"])
		if wn > W_SURV_END and wn <= W_FORM_END:
			xf += int(r.get("dis_new", 0))
	return xf


# ─────────────────────────────────────────────────────────────────────────────
# 统计：独立两比例 SE 的双侧 z / 95% CI
# ─────────────────────────────────────────────────────────────────────────────
func _se_indep(p0: float, p1: float, n: int) -> float:
	return sqrt(maxf(0.0, p0 * (1.0 - p0) + p1 * (1.0 - p1)) / float(maxi(1, n)))


## 两均值差的 Welch SE（用于 gap_leak 这类连续量）
func _se_mean_diff(a: Array, b: Array) -> float:
	var na: int = a.size()
	var nb: int = b.size()
	if na < 2 or nb < 2:
		return 0.0
	var va: float = _sd(a)
	var vb: float = _sd(b)
	return sqrt(va * va / float(na) + vb * vb / float(nb))


func _pflag(p: float) -> String:
	return "sig" if p < ALPHA else "ns"


func _zflag(z: float) -> String:
	return "sig" if absf(z) >= Z_CRIT else "ns"


## 双侧 p = P(|Z| >= |z|) = erfc(|z| / sqrt(2))（A&S 7.1.26 近似，|err| < 1.5e-7）
func _p_from_z(z: float) -> float:
	var x: float = absf(z) / sqrt(2.0)
	var t: float = 1.0 / (1.0 + 0.3275911 * x)
	var poly: float = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741
		+ t * (-1.453152027 + t * 1.061405429))))
	return clampf(poly * exp(-x * x), 0.0, 1.0)


func _parse_str(key: String, dflt: String) -> String:
	var v: String = dflt
	for a in OS.get_cmdline_args():
		var s := String(a)
		if s.begins_with(key + "="):
			v = s.substr(key.length() + 1).strip_edges().to_upper()
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with(key + "="):
			v = s.substr(key.length() + 1).strip_edges().to_upper()
	return v


func _parse_int(key: String, dflt: int) -> int:
	var v: int = dflt
	for a in OS.get_cmdline_args():
		var s := String(a)
		if s.begins_with(key + "="):
			v = int(s.substr(key.length() + 1))
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with(key + "="):
			v = int(s.substr(key.length() + 1))
	return v


func _initialize() -> void:
	RUNS = _parse_int("RUNS", RUNS_DEFAULT)
	# 🆕 ARMS 可是整数（V-8 臂数）或 "V8B"（切到 V-8b 剂量扫描臂表）
	var arms_arg := _parse_str("ARMS", "")
	if arms_arg == "V8B":
		ARM_SET = "V8B"
		ARM_DEFS_ACTIVE = ARM_DEFS_V8B
		N_ARMS = ARM_DEFS_V8B.size()
	else:
		N_ARMS = _parse_int("ARMS", ARMS_DEFAULT)
		if N_ARMS < 1 or N_ARMS > ARM_DEFS.size():
			N_ARMS = ARM_DEFS.size()
		ARM_DEFS_ACTIVE = ARM_DEFS
	if ARM_SET == "V8B":
		_init_v8b()
		return

	print("===================================================================")
	print("V-8 BULWARK DEATH CYCLE (REVERB) -- %d arms x %d runs | seed %d | TWO-SIDED"
		% [N_ARMS, RUNS, SEED])
	print("RADIAL n_slots=8 | aggro=true | exp=0.6 | attrition=%.2f | warmup=%d | max_wave=%d"
		% [ATTRITION, WARMUP, MAX_WAVE])
	print("R_reverb=9.0 (1.0x AGGRO_R) | s_reverb=0.30 | N_short=0.5s | N_long=2.0s | K=1")
	print("primary: delta_surv two-sided 95%% CI (line +/-%.3f) | mech: bulwark_uptime UP + gap_leak DOWN"
		% DELTA_LINE)
	print("  [self-check] _p_from_z(1.96)=%.5f (expect ~0.05000) | _p_from_z(0.0)=%.5f (expect 1.00000)"
		% [_p_from_z(1.96), _p_from_z(0.0)])
	print("===================================================================")

	# RADIAL only for this scan; restored to PATH afterwards
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var arms: Array = []
	for i in range(N_ARMS):
		var d: Array = ARM_DEFS_ACTIVE[i]
		print("  [arm %s] repair_on_disable=%d  N=%.1fs  reverb=%s"
			% [String(d[0]), int(d[1]), float(d[2]), ("ON" if bool(d[3]) else "off")])
		var a := _run_arm(String(d[0]), int(d[1]), float(d[2]), bool(d[3]))
		arms.append(a)
		print("     -> surv=%.4f (%d/%d)  n_td_form=%d" % [float(a["surv"]), int(a["n_surv"]), RUNS, int(a["n_td"])])

	var b0: Dictionary = arms[0]

	# ───────────── ① 主判据：Δ_surv 双侧 CI ─────────────
	print("")
	print("---- (1) PRIMARY: delta_surv vs B0 (two-sided, independent two-proportion SE) ----")
	print("  arm   surv      n_surv | delta     SE       z       p       95%% CI              | vs +/-%.3f line"
		% DELTA_LINE)
	var delta_list: Array = []
	for i in range(arms.size()):
		var a: Dictionary = arms[i]
		if i == 0:
			delta_list.append({"lo": 0.0, "hi": 0.0, "d": 0.0, "z": 0.0, "p": 1.0})
			print("  %s  %.4f  %5d |   (ref)                                                       |"
				% [String(a["tag"]), float(a["surv"]), int(a["n_surv"])])
			continue
		var d: float = float(a["surv"]) - float(b0["surv"])
		var se: float = _se_indep(float(b0["surv"]), float(a["surv"]), RUNS)
		var z: float = d / se if se > 0.0 else 0.0
		var p: float = _p_from_z(z)
		var lo: float = d - Z_CRIT * se
		var hi: float = d + Z_CRIT * se
		delta_list.append({"lo": lo, "hi": hi, "d": d, "z": z, "p": p})
		var line := "CI contains 0"
		if lo > 0.0:
			line = "CI lower > 0 (POS)"
		elif hi < 0.0:
			line = "CI upper < 0 (NEG)"
		if absf(d) >= DELTA_LINE:
			line += " | crosses line"
		print("  %s  %.4f  %5d | %+.5f  %.5f  %+6.2f  %.5f  [%+.5f, %+.5f]  %s"
			% [String(a["tag"]), float(a["surv"]), int(a["n_surv"]), d, se, z, p, lo, hi, line])

	# ───────────── ② 机制判据 ─────────────
	print("")
	print("---- (2) MECHANISM: bulwark_uptime / gap_leak / n_td_form ----")
	print("  arm   uptime(full)  uptime(active)  gap_leak/run  gap_unlock/run  n_td_form  td_gain_vs_B0")
	for i in range(arms.size()):
		var a2: Dictionary = arms[i]
		var up: float = float(a2["bulwark_uptime"])
		var upa: float = float(a2["bulwark_uptime_act"])
		var tg: float = 0.0
		if i > 0 and int(b0["n_td"]) > 0:
			tg = (float(int(a2["n_td"])) - float(int(b0["n_td"]))) / float(int(b0["n_td"]))
		print("  %s  %s  %s  %s  %s  %8d  %s"
			% [String(a2["tag"]),
				("%11.4f" % up) if up >= 0.0 else "        n/a",
				("%13.4f" % upa) if upa >= 0.0 else "          n/a",
				"%9.4f" % float(a2["gap_leak_mean"]),
				"%9.4f" % (float(a2["S"]["gap_unlocked"]) / float(RUNS)),
				int(a2["n_td"]),
				("%+.2f%%" % (tg * 100.0)) if i > 0 else "   (ref)"])

	# ───────────── ③ 残响读数 ─────────────
	print("")
	print("---- (3) REVERB readings (reverb_slow_seconds is the upstream direct read) ----")
	print("  arm   reverb  reverb_slow_s/run  reverb_uptime  covered/run  leak_save/run  aggro_disturb")
	for i in range(arms.size()):
		var a3: Dictionary = arms[i]
		var on: bool = bool(ARM_DEFS_ACTIVE[i][3])
		print("  %s  %s  %s  %s  %s  %s  %s"
			% [String(a3["tag"]), ("ON " if on else "off"),
				"%13.4f" % float(a3["reverb_slow_mean"]),
				"%12.4f" % float(a3["reverb_uptime"]),
				"%11.4f" % float(a3["reverb_covered"]),
				"%12.4f" % float(a3["reverb_leak_save"]),
				"%13.0f" % float(a3["S"]["rev_disturb"])])

	# ───────────── ④ 复活读数 + 硬断言 ─────────────
	print("")
	print("---- (4) REVIVE readings + HARD ASSERTIONS ----")
	print("  arm   fired/run  eligible/run  redied/run  refused/run  carry_death/run  nonexp_death/run  misq(TOTAL)")
	var hard_ok := true
	for i in range(arms.size()):
		var a4: Dictionary = arms[i]
		var misq: float = float(a4["S"]["revive_misq"])
		var dis: float = float(a4["S"]["rev_disturb"])
		var nos: float = float(a4["S"]["nosnap_death"])
		if misq > 0.0 or dis > 0.0 or nos > 0.0:
			hard_ok = false
		print("  %s  %s  %s  %s  %s  %s  %s  %8.0f  %s"
			% [String(a4["tag"]),
				"%9.4f" % (float(a4["S"]["revive_fired"]) / float(RUNS)),
				"%12.4f" % (float(a4["S"]["revive_elig"]) / float(RUNS)),
				"%10.4f" % (float(a4["S"]["revive_redied"]) / float(RUNS)),
				"%11.4f" % (float(a4["S"]["revive_refused"]) / float(RUNS)),
				"%15.4f" % (float(a4["S"]["carry_death"]) / float(RUNS)),
				"%16.4f" % (float(a4["S"]["nonexp_death"]) / float(RUNS)),
				misq,
				("FAIL" if misq > 0.0 else "PASS=0")])
	print("  [hard] revive_misqualify == 0 on every arm : %s" % ("PASS" if _all_zero(arms, "revive_misq") else "FAIL -> arm void, fix and re-run"))
	print("  [hard] reverb_aggro_disturb == 0 on every arm: %s" % ("PASS" if _all_zero(arms, "rev_disturb") else "FAIL -> reverb touched the aggro pool"))
	print("  [hard] nosnap_death == 0 (no revive judged without a death snapshot): %s"
		% ("PASS" if _all_zero(arms, "nosnap_death") else "FAIL"))
	print("  [diag] hard_ok_inputs: misq=%s disturb=%s nosnap=%s"
		% [_tot(arms, "revive_misq"), _tot(arms, "rev_disturb"), _tot(arms, "nosnap_death")])

	# ───────────── ⑤ gap_leak(B4) vs gap_leak(B0) 显著性 ─────────────
	print("")
	print("---- (5) gap_leak: B4 vs B0 (Welch two-sided, the R-B3 direct read) ----")
	var b4_idx := _arm_index("B4")
	var b5_idx := _arm_index("B5")
	var b1_idx := _arm_index("B1")
	for idx in [b4_idx, b5_idx, b1_idx, _arm_index("B2"), _arm_index("B3")]:
		if idx < 0 or idx >= arms.size():
			continue
		var ax: Dictionary = arms[idx]
		var d: float = float(ax["gap_leak_mean"]) - float(b0["gap_leak_mean"])
		var se: float = _se_mean_diff(b0["per_gap"], ax["per_gap"])
		var z: float = d / se if se > 0.0 else 0.0
		print("  [%s] gap_leak %.4f vs B0 %.4f -> d=%+.4f  SE=%.4f  z=%+.2f [%s]  95%%CI [%+.4f, %+.4f]"
			% [String(ax["tag"]), float(ax["gap_leak_mean"]), float(b0["gap_leak_mean"]),
				d, se, z, _zflag(z), d - Z_CRIT * se, d + Z_CRIT * se])

	# ───────────── ⑥ 护栏 ─────────────
	print("")
	print("---- (6) GUARDRAILS (pre-registered, v3 §6.3 / §6.5) ----")
	var guard_ok := true
	var g_surv_ok := true
	for i in range(arms.size()):
		var a6: Dictionary = arms[i]
		if float(a6["surv"]) >= SURV_DRIFT_CAP:
			g_surv_ok = false
	print("  [G1] pillar drift  surv_A < %.3f on every arm : %s" % [SURV_DRIFT_CAP, "PASS" if g_surv_ok else "FAIL"])
	if not g_surv_ok:
		guard_ok = false
	var g_td_ok := true
	for i in range(1, arms.size()):
		var a7: Dictionary = arms[i]
		var tg: float = 0.0
		if int(b0["n_td"]) > 0:
			tg = (float(int(a7["n_td"])) - float(int(b0["n_td"]))) / float(int(b0["n_td"]))
		if tg >= TD_GAIN_CAP:
			g_td_ok = false
		if int(a7["n_td"]) <= 0:
			g_td_ok = false
	print("  [G2] n_td_form gain < +%.0f%% and never -> 0 : %s" % [TD_GAIN_CAP * 100.0, "PASS" if g_td_ok else "FAIL"])
	if not g_td_ok:
		guard_ok = false
	# 🔴 v3 §6.5 双判据取严。阈值跑前写死、跑后不由我改 —— 若 B0 基线本身就已越过
	#    绝对线，只**登记**"绝对阈值在本口径下不可用"，判读改用相对判据（+40pp）。
	var g_up_rel_ok := true
	var g_up_abs_ok := true
	var base_abs_breach := false
	if float(b0["bulwark_uptime"]) >= UPTIME_CAP_ABS:
		base_abs_breach = true
	for i in range(arms.size()):
		var a8: Dictionary = arms[i]
		var up: float = float(a8["bulwark_uptime"])
		if up < 0.0:
			continue
		if up >= UPTIME_CAP_ABS:
			g_up_abs_ok = false
		if i > 0 and float(b0["bulwark_uptime"]) >= 0.0:
			if (up - float(b0["bulwark_uptime"])) > UPTIME_GAIN_CAP:
				g_up_rel_ok = false
	print("  [G3a] bulwark_uptime gain <= +%.0fpp vs B0 (relative) : %s"
		% [UPTIME_GAIN_CAP * 100.0, "PASS" if g_up_rel_ok else "FAIL (OVERPOWERED -> tower death lost its teeth)"])
	print("  [G3b] bulwark_uptime < %.2f absolute : %s%s"
		% [UPTIME_CAP_ABS, ("PASS" if g_up_abs_ok else "BREACHED"),
			"   [!] B0 baseline itself >= cap -> absolute line NOT usable in this caliber (registered, not changed by me)" if base_abs_breach else ""])
	if not g_up_rel_ok:
		guard_ok = false
	# 残响过度否决（v3 §6.4）：gap_leak(B4) → 0
	var reverb_over := false
	if b4_idx >= 0 and b4_idx < arms.size():
		if float(arms[b4_idx]["gap_leak_mean"]) < GAP_LEAK_ZERO_EPS:
			reverb_over = true
	print("  [G4] reverb degeneracy  gap_leak(B4) not -> 0 : %s"
		% ("PASS" if not reverb_over else "FAIL (reverb became a taunt equivalent -> NOT adoptable)"))
	# INCONCLUSIVE
	var elig_ok := true
	for i in range(1, arms.size()):
		if int(ARM_DEFS_ACTIVE[i][1]) == 0:
			continue
		if float(arms[i]["S"]["revive_elig"]) < float(ELIG_MIN):
			elig_ok = false
	print("  [G5] n_revive_eligible >= %d per revive arm : %s" % [ELIG_MIN, "PASS" if elig_ok else "INCONCLUSIVE"])
	# B0 基线护栏
	if RUNS >= BASE_N:
		var ok: bool = (int(b0["b_surv"]) == BASE_SURV_V4)
		print("  [G6] B0 first %d games survive=%d vs V-4 0.580x300=%d : %s"
			% [BASE_N, int(b0["b_surv"]), BASE_SURV_V4,
				"PASS" if ok else "MISMATCH (register 'seed not prefix-compatible'; delta already uses same-batch B0)"])
	else:
		print("  [G6] SKIPPED (RUNS=%d < %d)" % [RUNS, BASE_N])
	print("  [G7] reverb_off_parity  B0..B3 reverb must be off : %s"
		% ("PASS" if _reverb_off_parity() else "FAIL"))

	# ───────────── ⑦ 预注册判读 ─────────────
	print("")
	print("---- (7) PRE-REGISTERED READING (v3 §6.4; final adjudication: design-strategist) ----")
	var up0: float = float(b0["bulwark_uptime"])
	for idx in [b1_idx, b4_idx, b5_idx]:
		if idx < 0 or idx >= arms.size():
			continue
		var a9: Dictionary = arms[idx]
		var dl: Dictionary = delta_list[idx]
		var upx: float = float(a9["bulwark_uptime"])
		var up_up := (up0 < 0.0 or upx < 0.0) or (upx > up0)
		var gl_down := float(a9["gap_leak_mean"]) < float(b0["gap_leak_mean"])
		var rev_ok: bool = true
		if bool(ARM_DEFS_ACTIVE[idx][3]):
			rev_ok = float(a9["reverb_slow_mean"]) > 0.0 and _all_zero([a9], "rev_disturb")
		var ok_all: bool = (float(dl["lo"]) > 0.0) and up_up and gl_down and (float(a9["surv"]) < SURV_DRIFT_CAP) \
			and _all_zero([a9], "revive_misq") and rev_ok and (int(a9["n_td"]) > 0)
		var verdict := "ESTABLISHED (all conditions met)"
		if float(dl["hi"]) < 0.0:
			verdict = "HARMFUL (CI upper < 0) -> reject"
		elif float(dl["lo"]) > 0.0 and ((upx >= UPTIME_CAP_ABS) or (int(a9["n_td"]) <= 0)):
			verdict = "OVERPOWERED (tower death cancelled) -> reject, tighten K / raise N / lower s_reverb"
		elif absf(float(dl["z"])) < Z_CRIT:
			verdict = "NEUTRAL (CI contains 0; mechanic moved but win-rate did not) -> user call"
		elif not ok_all:
			verdict = "NOT ESTABLISHED (some condition unmet)"
		print("  [%s] delta=%+.5f CI[%+.5f,%+.5f] | uptime %.4f->%.4f (%s) | uptime_act %.4f->%.4f | gap_leak %.4f->%.4f (%s) | reverb_slow=%.4f | -> %s"
			% [String(a9["tag"]), float(dl["d"]), float(dl["lo"]), float(dl["hi"]),
				maxf(0.0, up0), maxf(0.0, upx), ("UP" if up_up else "not-up"),
				maxf(0.0, float(b0["bulwark_uptime_act"])), maxf(0.0, float(a9["bulwark_uptime_act"])),
				float(b0["gap_leak_mean"]), float(a9["gap_leak_mean"]), ("DOWN" if gl_down else "not-down"),
				float(a9["reverb_slow_mean"]), verdict])

	print("")
	print("  [SUMMARY] hard_assertions=%s  guardrails=%s  reverb_degeneracy=%s  elig=%s"
		% [("PASS" if hard_ok else "FAIL"), ("PASS" if guard_ok else "FAIL"),
			("none" if not reverb_over else "TRIGGERED"), ("PASS" if elig_ok else "INCONCLUSIVE")])
	print("  [NOTE] Reserved: N_long vs N_short (B1/B2), B3 timing-sign evidence -- read off the table above.")
	if b1_idx >= 0 and _arm_index("B2") >= 0:
		var d1: float = float(delta_list[b1_idx]["d"])
		var d2: float = float(delta_list[_arm_index("B2")]["d"])
		print("  [N-SCAN] delta(B1,N_short)=%+.5f  delta(B2,N_long)=%+.5f  -> %s"
			% [d1, d2, ("N matters (|diff| >= %.3f)" % DELTA_LINE) if absf(d1 - d2) >= DELTA_LINE else "N shows no material difference at this line"])

	# restore PATH mode
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	print("")
	print("===================================================================")
	print("V-8 done (diagnostic artifact | always exit 0 | final call: design-strategist)")
	print("===================================================================")
	quit(0)


func _tot(arms: Array, key: String) -> String:
	var s := 0.0
	for a in arms:
		s += float(a["S"][key])
	return "%.0f" % s


func _all_zero(arms: Array, key: String) -> bool:
	for a in arms:
		if float(a["S"][key]) > 0.0:
			return false
	return true


func _arm_index(tag: String) -> int:
	for i in range(ARM_DEFS_ACTIVE.size()):
		if String(ARM_DEFS_ACTIVE[i][0]) == tag:
			return i
	return -1


## v3 §6.2 护栏⑦：B0..B3 的残响开关必须逐位 = off
func _reverb_off_parity() -> bool:
	for i in range(mini(4, ARM_DEFS_ACTIVE.size())):
		if bool(ARM_DEFS_ACTIVE[i][3]):
			return false
	return true


# ═════════════════════════════════════════════════════════════════════════════
# 🆕 V-8b · 残响剂量扫描（按住离线时长混淆 · 纯净边际）
#
#   全部臂复活 ON 且复活参数逐位相同（repair=9 / N=0.5 / K=1）→ 按住"离线时长"
#   这个混淆变量；只有 s_reverb / R_reverb 在变 → Δ(剂量臂 vs C0) = 残响纯净边际。
# ═════════════════════════════════════════════════════════════════════════════
func _init_v8b() -> void:
	print("===================================================================")
	print("V-8b REVERB DOSE SCAN (offline-duration held constant) -- %d arms x %d runs | seed %d | TWO-SIDED"
		% [N_ARMS, RUNS, SEED])
	print("RADIAL n_slots=8 | aggro=true | exp=0.6 | attrition=%.2f | warmup=%d | max_wave=%d"
		% [ATTRITION, WARMUP, MAX_WAVE])
	print("CONFOUND HELD: revive ON on EVERY arm (repair_on_disable=9, N=0.5s, K=1)")
	print("ONLY s_reverb x R_reverb vary -> delta(dose vs C0) = PURE reverb margin")
	print("primary: delta_surv two-sided 95%% CI (line +/-%.3f) | mech: reverb_slow_seconds / gap_leak(ACTIVITY, not win-rate proxy) / uptime / n_td_form"
		% DELTA_LINE)
	print("  [self-check] _p_from_z(1.96)=%.5f (expect ~0.05000) | _p_from_z(0.0)=%.5f (expect 1.00000)"
		% [_p_from_z(1.96), _p_from_z(0.0)])
	print("===================================================================")

	# ───────── ⓪ 结构不变量：复活参数逐位相同（这是 V-8b 去混淆的生命线） ─────────
	var struct_ok := true
	for i in range(1, ARM_DEFS_ACTIVE.size()):
		if int(ARM_DEFS_ACTIVE[i][1]) != int(ARM_DEFS_ACTIVE[0][1]) \
			or absf(float(ARM_DEFS_ACTIVE[i][2]) - float(ARM_DEFS_ACTIVE[0][2])) > 1e-12:
			struct_ok = false
	# C0 必须残响 off（对照分母），其余臂必须残响 ON
	if bool(ARM_DEFS_ACTIVE[0][3]):
		struct_ok = false
	for i in range(1, ARM_DEFS_ACTIVE.size()):
		if not bool(ARM_DEFS_ACTIVE[i][3]):
			struct_ok = false
	print("[0] STRUCTURAL INVARIANT (V-8b confound control)")
	for i in range(ARM_DEFS_ACTIVE.size()):
		var d0: Array = ARM_DEFS_ACTIVE[i]
		print("    [%s] revive(repair=%d N=%.1f K=1)  reverb=%s  s=%.2f  R=%.1f (%.1fx AGGRO_R)"
			% [String(d0[0]), int(d0[1]), float(d0[2]), ("ON" if bool(d0[3]) else "off"),
				float(d0[4]), float(d0[5]), float(d0[5]) / 9.0])
	print("    [invariant] revive params identical on every arm + C0 reverb OFF + dose arms reverb ON : %s"
		% ("PASS" if struct_ok else "FAIL -> confound NOT held, scan void"))

	# RADIAL only for this scan; restored to PATH afterwards
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var arms: Array = []
	for i in range(N_ARMS):
		var d: Array = ARM_DEFS_ACTIVE[i]
		var a := _run_arm(String(d[0]), int(d[1]), float(d[2]), bool(d[3]), float(d[4]), float(d[5]))
		arms.append(a)
		print("  [arm %s] %s s=%.2f R=%.1f -> surv=%.4f (%d/%d)  n_td_form=%d"
			% [String(d[0]), ("reverb ON " if bool(d[3]) else "reverb off"), float(d[4]), float(d[5]),
				float(a["surv"]), int(a["n_surv"]), RUNS, int(a["n_td"])])

	var c0: Dictionary = arms[0]

	# ───────── ① 主判据：Δ_surv vs C0（残响纯净边际） ─────────
	print("")
	print("---- (1) PRIMARY: delta_surv vs C0 = PURE REVERB MARGIN (two-sided, independent two-proportion SE) ----")
	print("  arm  s     R     surv      n_surv | delta     SE       z       p       95%% CI              | vs +/-%.3f line"
		% DELTA_LINE)
	var delta_list: Array = []
	for i in range(arms.size()):
		var a: Dictionary = arms[i]
		if i == 0:
			delta_list.append({"lo": 0.0, "hi": 0.0, "d": 0.0, "z": 0.0, "p": 1.0})
			print("  %s  -     -     %.4f  %5d |   (ref = revive ON, reverb OFF)                        |"
				% [String(a["tag"]), float(a["surv"]), int(a["n_surv"])])
			continue
		var dd: Array = ARM_DEFS_ACTIVE[i]
		var dv: float = float(a["surv"]) - float(c0["surv"])
		var se: float = _se_indep(float(c0["surv"]), float(a["surv"]), RUNS)
		var z: float = dv / se if se > 0.0 else 0.0
		var p: float = _p_from_z(z)
		var lo: float = dv - Z_CRIT * se
		var hi: float = dv + Z_CRIT * se
		delta_list.append({"lo": lo, "hi": hi, "d": dv, "z": z, "p": p})
		var line := "CI contains 0"
		if lo > 0.0:
			line = "CI lower > 0 (POS)"
		elif hi < 0.0:
			line = "CI upper < 0 (NEG)"
		if absf(dv) >= DELTA_LINE:
			line += " | crosses line"
		print("  %s  %.2f  %.1f  %.4f  %5d | %+.5f  %.5f  %+6.2f  %.5f  [%+.5f, %+.5f]  %s"
			% [String(a["tag"]), float(dd[4]), float(dd[5]), float(a["surv"]), int(a["n_surv"]),
				dv, se, z, p, lo, hi, line])

	# ───────── ② 机制量 ─────────
	print("")
	print("---- (2) MECHANISM: reverb_slow_seconds / gap_leak(ACTIVITY) / bulwark_uptime / n_td_form ----")
	print("  arm   reverb_slow_s/run  dose_x_vs_V1  covered/run  leak_save/run  reverb_uptime  gap_leak/run  gap_unlock/run  uptime(full)  uptime(active)  n_td_form  td_gain_vs_C0")
	var v1_slow: float = float(arms[1]["reverb_slow_mean"]) if arms.size() > 1 else 0.0
	for i in range(arms.size()):
		var a2: Dictionary = arms[i]
		var tg: float = 0.0
		if i > 0 and int(c0["n_td"]) > 0:
			tg = (float(int(a2["n_td"])) - float(int(c0["n_td"]))) / float(int(c0["n_td"]))
		var dose_x: String = "   (ref)" if i == 0 else ("%8.2fx" % (float(a2["reverb_slow_mean"]) / v1_slow if v1_slow > 0.0 else 0.0))
		print("  %s  %s  %s  %s  %s  %s  %s  %s  %s  %s  %8d  %s"
			% [String(a2["tag"]),
				"%16.4f" % float(a2["reverb_slow_mean"]),
				dose_x,
				"%11.4f" % float(a2["reverb_covered"]),
				"%13.4f" % float(a2["reverb_leak_save"]),
				"%13.4f" % float(a2["reverb_uptime"]),
				"%11.4f" % float(a2["gap_leak_mean"]),
				"%13.4f" % (float(a2["S"]["gap_unlocked"]) / float(RUNS)),
				("%11.4f" % float(a2["bulwark_uptime"])) if float(a2["bulwark_uptime"]) >= 0.0 else "        n/a",
				("%13.4f" % float(a2["bulwark_uptime_act"])) if float(a2["bulwark_uptime_act"]) >= 0.0 else "          n/a",
				int(a2["n_td"]),
				("%+.2f%%" % (tg * 100.0)) if i > 0 else "   (ref)"])

	# ───────── ③ gap_leak 显著性（Welch；🟡 仅作机制活动量，不作胜率代理） ─────────
	print("")
	print("---- (3) gap_leak vs C0 (Welch two-sided | MECHANISM ACTIVITY ONLY -- B3 paradox: gap_leak DOWN != win-rate UP) ----")
	for i in range(1, arms.size()):
		var ax: Dictionary = arms[i]
		var dg: float = float(ax["gap_leak_mean"]) - float(c0["gap_leak_mean"])
		var seg: float = _se_mean_diff(c0["per_gap"], ax["per_gap"])
		var zg: float = dg / seg if seg > 0.0 else 0.0
		print("  [%s] gap_leak %.4f vs C0 %.4f -> d=%+.4f  SE=%.4f  z=%+.2f [%s]  95%%CI [%+.4f, %+.4f]"
			% [String(ax["tag"]), float(ax["gap_leak_mean"]), float(c0["gap_leak_mean"]),
				dg, seg, zg, _zflag(zg), dg - Z_CRIT * seg, dg + Z_CRIT * seg])

	# ───────── ④ 复活读数 + 硬断言 ─────────
	print("")
	print("---- (4) REVIVE readings + HARD ASSERTIONS ----")
	print("  arm   fired/run  eligible/run  redied/run  refused/run  carry_death/run  nonexp_death/run  misq(TOTAL)  aggro_disturb(TOTAL)")
	var hard_ok := true
	for i in range(arms.size()):
		var a4: Dictionary = arms[i]
		var misq: float = float(a4["S"]["revive_misq"])
		var dis: float = float(a4["S"]["rev_disturb"])
		var nos: float = float(a4["S"]["nosnap_death"])
		if misq > 0.0 or dis > 0.0 or nos > 0.0:
			hard_ok = false
		print("  %s  %s  %s  %s  %s  %s  %s  %8.0f  %8.0f  %s"
			% [String(a4["tag"]),
				"%9.4f" % (float(a4["S"]["revive_fired"]) / float(RUNS)),
				"%12.4f" % (float(a4["S"]["revive_elig"]) / float(RUNS)),
				"%10.4f" % (float(a4["S"]["revive_redied"]) / float(RUNS)),
				"%11.4f" % (float(a4["S"]["revive_refused"]) / float(RUNS)),
				"%15.4f" % (float(a4["S"]["carry_death"]) / float(RUNS)),
				"%16.4f" % (float(a4["S"]["nonexp_death"]) / float(RUNS)),
				misq, dis, ("FAIL" if (misq > 0.0 or dis > 0.0) else "PASS=0")])
	print("  [hard] revive_misqualify == 0 on every arm  : %s" % ("PASS" if _all_zero(arms, "revive_misq") else "FAIL -> arm void, fix and re-run"))
	print("  [hard] reverb_aggro_disturb == 0 on every arm: %s" % ("PASS" if _all_zero(arms, "rev_disturb") else "FAIL -> reverb touched the aggro pool"))
	print("  [hard] nosnap_death == 0 (no revive judged without a death snapshot): %s"
		% ("PASS" if _all_zero(arms, "nosnap_death") else "FAIL"))
	print("  [hard] structural invariant (revive params identical across arms): %s"
		% ("PASS" if struct_ok else "FAIL"))
	if not struct_ok:
		hard_ok = false
	print("  [diag] totals: misq=%s disturb=%s nosnap=%s"
		% [_tot(arms, "revive_misq"), _tot(arms, "rev_disturb"), _tot(arms, "nosnap_death")])

	# ───────── ⑤ 护栏 + 预注册否决 ─────────
	print("")
	print("---- (5) GUARDRAILS + PRE-REGISTERED VETOES (carried over from V-8) ----")
	var guard_ok := true
	var g_surv_ok := true
	for i in range(arms.size()):
		if float(arms[i]["surv"]) >= SURV_DRIFT_CAP:
			g_surv_ok = false
	print("  [G1] pillar drift  surv_A < %.3f on every arm : %s" % [SURV_DRIFT_CAP, "PASS" if g_surv_ok else "FAIL"])
	if not g_surv_ok:
		guard_ok = false
	var g_td_ok := true
	for i in range(1, arms.size()):
		var a7: Dictionary = arms[i]
		var tg: float = 0.0
		if int(c0["n_td"]) > 0:
			tg = (float(int(a7["n_td"])) - float(int(c0["n_td"]))) / float(int(c0["n_td"]))
		if tg >= TD_GAIN_CAP:
			g_td_ok = false
		if int(a7["n_td"]) <= 0:
			g_td_ok = false
	print("  [G2] n_td_form gain < +%.0f%% and never -> 0 : %s" % [TD_GAIN_CAP * 100.0, "PASS" if g_td_ok else "FAIL"])
	if not g_td_ok:
		guard_ok = false
	var g_up_rel_ok := true
	var g_up_abs_ok := true
	var base_abs_breach := false
	if float(c0["bulwark_uptime"]) >= UPTIME_CAP_ABS:
		base_abs_breach = true
	for i in range(arms.size()):
		var up: float = float(arms[i]["bulwark_uptime"])
		if up < 0.0:
			continue
		if up >= UPTIME_CAP_ABS:
			g_up_abs_ok = false
		if i > 0 and float(c0["bulwark_uptime"]) >= 0.0:
			if (up - float(c0["bulwark_uptime"])) > UPTIME_GAIN_CAP:
				g_up_rel_ok = false
	print("  [G3a] bulwark_uptime gain <= +%.0fpp vs C0 (relative) : %s"
		% [UPTIME_GAIN_CAP * 100.0, "PASS" if g_up_rel_ok else "FAIL (OVERPOWERED -> tower death lost its teeth)"])
	print("  [G3b] bulwark_uptime < %.2f absolute : %s%s"
		% [UPTIME_CAP_ABS, ("PASS" if g_up_abs_ok else "BREACHED"),
			"   [!] C0 baseline itself >= cap -> absolute line NOT usable in this caliber (registered, not changed by me)" if base_abs_breach else ""])
	if not g_up_rel_ok:
		guard_ok = false
	# VETO ①：残响退化成嘲讽等价物（gap_leak → 0）—— 取**最强剂量臂**（末尾臂）为主，并全臂登记
	var reverb_over := false
	var max_idx: int = arms.size() - 1
	if float(arms[max_idx]["gap_leak_mean"]) < GAP_LEAK_ZERO_EPS:
		reverb_over = true
	for i in range(1, arms.size()):
		if float(arms[i]["gap_leak_mean"]) < GAP_LEAK_ZERO_EPS:
			reverb_over = true
	print("  [G4] reverb degeneracy  gap_leak(dose arms) not -> 0 : %s   [strongest dose = %s, gap_leak=%.4f]"
		% [("PASS" if not reverb_over else "FAIL (reverb became a taunt equivalent -> NOT adoptable)"),
			String(arms[max_idx]["tag"]), float(arms[max_idx]["gap_leak_mean"])])
	# INCONCLUSIVE
	var elig_ok := true
	for i in range(arms.size()):
		if float(arms[i]["S"]["revive_elig"]) < float(ELIG_MIN):
			elig_ok = false
	print("  [G5] n_revive_eligible >= %d per arm : %s" % [ELIG_MIN, "PASS" if elig_ok else "INCONCLUSIVE"])
	# 口径连续性：C0 配置 = V-8 的 B1（同 seed / 同 RUNS）→ 必须逐位复现 V-8 B1
	if RUNS == 1480:
		print("  [G6] caliber continuity  C0 n_surv=%d vs V-8 B1 n_surv=864 (same seed %d, same RUNS) : %s"
			% [int(c0["n_surv"]), SEED,
				"PASS (bit-identical -> V-8b batch is comparable with V-8)" if int(c0["n_surv"]) == 864 else "MISMATCH (register; delta uses same-batch C0)"])
	else:
		print("  [G6] SKIPPED (RUNS=%d != 1480; V-8 B1 reference only defined at 1480)" % RUNS)

	# ───────── ⑥ 剂量阶梯：逐因子对照 ─────────
	print("")
	print("---- (6) DOSE STAIRCASE: one-factor-at-a-time contrasts (surv, independent two-proportion SE) ----")
	var pairs := [["V1", "V2", "R 1.0x -> 1.5x at s=0.30 (radius lever)"],
		["V2", "V3", "s 0.30 -> 0.50 at R=1.5x (slow lever)"],
		["V1", "V3", "full dose escalation (anchor -> upper bound)"]]
	for pr in pairs:
		var ia: int = _arm_index(String(pr[0]))
		var ib: int = _arm_index(String(pr[1]))
		if ia < 0 or ib < 0:
			continue
		var aa: Dictionary = arms[ia]
		var ab: Dictionary = arms[ib]
		var dd2: float = float(ab["surv"]) - float(aa["surv"])
		var se2: float = _se_indep(float(aa["surv"]), float(ab["surv"]), RUNS)
		var z2: float = dd2 / se2 if se2 > 0.0 else 0.0
		print("  [%s -> %s] %s : d=%+.5f  SE=%.5f  z=%+.2f [%s]  95%%CI [%+.5f, %+.5f]  p=%.5f"
			% [String(pr[0]), String(pr[1]), String(pr[2]), dd2, se2, z2, _zflag(z2),
				dd2 - Z_CRIT * se2, dd2 + Z_CRIT * se2, _p_from_z(z2)])

	# ───────── ⑦ 预注册判读 ─────────
	print("")
	print("---- (7) PRE-REGISTERED READING (final adjudication: design-strategist) ----")
	var up0: float = float(c0["bulwark_uptime"])
	var any_sig := false
	for i in range(1, arms.size()):
		var a9: Dictionary = arms[i]
		var dl: Dictionary = delta_list[i]
		var upx: float = float(a9["bulwark_uptime"])
		var rev_ok: bool = float(a9["reverb_slow_mean"]) > 0.0 and _all_zero([a9], "rev_disturb")
		var over: bool = (upx >= UPTIME_CAP_ABS) or (int(a9["n_td"]) <= 0)
		var verdict := "ESTABLISHED at this dose"
		if float(dl["hi"]) < 0.0:
			verdict = "HARMFUL (CI upper < 0) -> reject this dose"
		elif float(dl["lo"]) > 0.0 and over:
			verdict = "OVERPOWERED (tower death cancelled) -> reject, tighten K / raise N / lower dose"
		elif absf(float(dl["z"])) < Z_CRIT:
			verdict = "NEUTRAL / SUB-PERCEPTUAL (CI contains 0; dose moved the mechanism but not the win-rate)"
		if float(dl["lo"]) > 0.0 and not over:
			any_sig = true
		print("  [%s] s=%.2f R=%.1f | delta=%+.5f CI[%+.5f,%+.5f] | reverb_slow=%.4fs/run | covered=%.2f/run | gap_leak %.4f->%.4f | uptime %.4f->%.4f | n_td=%d | -> %s"
			% [String(a9["tag"]), float(ARM_DEFS_ACTIVE[i][4]), float(ARM_DEFS_ACTIVE[i][5]),
				float(dl["d"]), float(dl["lo"]), float(dl["hi"]),
				float(a9["reverb_slow_mean"]), float(a9["reverb_covered"]),
				float(c0["gap_leak_mean"]), float(a9["gap_leak_mean"]),
				maxf(0.0, up0), maxf(0.0, upx), int(a9["n_td"]), verdict])
	print("")
	var headline := "NO dose cell crossed the +/-%.3f line -> reverb appears sub-perceptual up to the upper-bound dose (s=0.50, R=1.5x)" % DELTA_LINE
	if any_sig:
		headline = "AT LEAST ONE dose cell has CI lower > 0 (reverb margin POSITIVE and significant)"
	print("  [HEADLINE] %s" % headline)
	print("  [SUMMARY] hard_assertions=%s  guardrails=%s  veto_reverb_degeneracy=%s  veto_overpowered=%s  elig=%s  structural=%s"
		% [("PASS" if hard_ok else "FAIL"), ("PASS" if guard_ok else "FAIL"),
			("none" if not reverb_over else "TRIGGERED"),
			("none" if g_up_rel_ok else "TRIGGERED"), ("PASS" if elig_ok else "INCONCLUSIVE"),
			("PASS" if struct_ok else "FAIL")])
	print("  [GAP] unfilled dose cell (s=0.50, R=1.0x): if V3 shows signal and s-vs-R attribution is needed, add 1 arm.")

	# restore PATH mode
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	print("")
	print("===================================================================")
	print("V-8b done (diagnostic artifact | always exit 0 | final call: design-strategist)")
	print("===================================================================")
	quit(0)
