class_name Stats
extends RefCounted
##
## 判据统计 —— 起飞波 / 交叉领先 / 三阶段健康 / 蒙特卡洛起飞率
##
## 金标本：
##   corebound_sim_v03.py :: `takeoff_wave()` (L748) / `tail_min()` (L755) / `summarize()` (L1288)
##   corebound_sim_v06_synergy.py :: `summarize()` (L276) / `cross_lead()` (L309-332) /
##                                   `stage_health()` (L335-343) / `takeoff_rate()` (L346)
##   corebound_sim_v07_mapA.py :: `eval_point()` (L252-295)
##
## 🔴 判据红线（mapA-kappaR-sweep.md §0 / §4）
##   · 多塔 B 决定性起飞 ∈ W10–W15
##   · 单核 A 起飞率 ≥ 60%   /   多塔 B 起飞率 ≥ 80%（MC 300）
##   · B/A（W20 ratio 比） < 1（概念 §2.4.5：单核必须是后期 carry）
##   · 交叉领先 ≥ 1 次
##   · 三阶段健康：W1-9 存活 + W13→20 ratio 单调上升 + 雪崩期增速 > 1
##

const _RunLoop := preload("res://scripts/engine/run_loop.gd")
const _FpPow := preload("res://scripts/engine/fp_pow.gd")


# ---------------------------------------------------------------------------
# Python 兼容的 round(x, nd)：**半值取偶**（banker's rounding）
#   GDScript 的 `round()` 是四舍五入远离零，且与 `snapped()` 一样有 step 误差。
#   ⚠️ 本实现在"十进制恰好落在 .5"时与 CPython 一致（CPython 用 _Py_dg_dtoa
#      对十进制做正确舍入）；非 .5 情形两边必然一致。
# ---------------------------------------------------------------------------
static func pround(x: float, nd: int) -> float:
	if is_nan(x) or is_inf(x) or x == 0.0:
		return x
	var sgn: float = -1.0 if x < 0.0 else 1.0
	var a: float = absf(x)
	var p := _FpPow.pow_int(10.0, nd)
	var y: float = a * p
	var fl: float = floor(y)
	var frac: float = y - fl
	# `a * p` 本身有 ≤0.5ULP 的舍入误差。只有当结果**贴近半值**时，
	# 这个误差才可能把真值翻到 .5 的另一侧（经典例子 round(2.675,2)）：
	#   2.675 的真实 double = 2.67499999999999982… → Python 给 2.67；
	#   但 2.675*100 在 IEEE 下**恰好** = 267.5 → 朴素半值取偶会给 2.68。
	# → 远离 .5 时走快路径；贴近 .5 时走 `_round_exact()` 的整数比精确判定。
	var ulp: float = maxf(absf(y), 1.0) * _FpPow.pow_int(2.0, -52)
	if absf(frac - 0.5) > 4.0 * ulp:
		return sgn * (fl + (1.0 if frac > 0.5 else 0.0)) / p
	return sgn * _round_exact(a, nd, p)


# ---------------------------------------------------------------------------
# 精确路径：把 a 化成 **M / 2^K**（M 为整数），于是 a·10^nd = (M·10^nd) / 2^K
#   → 用整数除法 + 余数比较做无误差的半值判定（2·rem 与 2^K 比大小）。
#   只在 nd ∈ [0,3] 且 M 不越 int64 时成立；否则退回朴素路径（MVP 用不到）。
# ---------------------------------------------------------------------------
static func _round_exact(a: float, nd: int, p: float) -> float:
	if nd < 0 or nd > 3:
		return _round_half_even(a * p) / p
	var m: float = a
	var k := 0
	while m != floor(m) and k < 1100:
		m *= 2.0
		k += 1
	if k > 60:
		return _round_half_even(a * p) / p
	var mi := int(m)
	if mi > 4000000000000000:      # mi·1000 必须留在 int64 内（< 9.22e18）
		return _round_half_even(a * p) / p
	var pp := int(round(p))
	var num := mi * pp
	var den: int = 1 << k
	var q := num / den
	var rem := num - q * den
	var twice := rem * 2
	var r := q
	if twice > den:
		r = q + 1
	elif twice == den:
		r = q if (q % 2 == 0) else q + 1
	return float(r) / p


static func _round_half_even(y: float) -> float:
	if is_nan(y) or is_inf(y):
		return y
	# ⚠️ Godot 坑：`absf()`/`floor()` 的返回类型静态分析推不出来 → 必须显式标 float
	var sgn: float = -1.0 if y < 0.0 else 1.0
	var a: float = absf(y)
	var fl: float = floor(a)
	var frac: float = a - fl
	var r: float = fl
	if frac > 0.5:
		r = fl + 1.0
	elif frac < 0.5:
		r = fl
	else:
		# 半值 → 取偶
		r = fl if fmod(fl, 2.0) == 0.0 else fl + 1.0
	return sgn * r


# ---------------------------------------------------------------------------
# v03 `takeoff_wave()` (L748-752)
# ---------------------------------------------------------------------------
static func takeoff_wave(rows: Array) -> int:
	for r in rows:
		if float(r["ratio"]) >= 1.0:
			return int(r["w"])
	return -1      # GDScript 无 None：用 -1 表示"不起飞"


# ---------------------------------------------------------------------------
# v03 `tail_min()` (L755-757)
# ---------------------------------------------------------------------------
static func tail_min(rows: Array, w0: int = 13) -> float:
	var got := false
	var mn := 0.0
	for r in rows:
		if int(r["w"]) < w0:
			continue
		var v := float(r["ratio"])
		if not got or v < mn:
			mn = v
			got = true
	return mn


# ---------------------------------------------------------------------------
# v06 `summarize()` (L276-282)
# ---------------------------------------------------------------------------
static func summarize(rows: Array, w0: int = 13) -> Dictionary:
	var d := {}
	for r in rows:
		d[int(r["w"])] = float(r["ratio"])
	return {
		"takeoff": takeoff_wave(rows),
		"w10": d.get(10, null), "w13": d.get(13, null),
		"w16": d.get(16, null), "w20": d.get(20, null),
		"tail_min": pround(tail_min(rows, w0), 2),
		"core_hp": float(rows[-1]["core_hp"]) if not rows.is_empty() else 0.0,
		"towers": int(rows[-1]["towers"]) if not rows.is_empty() else 0,
	}


# ---------------------------------------------------------------------------
# v06 `cross_lead()` (L309-332)
#   返回 [cross_rows, lead{A,B}, flips, firstA, firstB]
# ---------------------------------------------------------------------------
static func cross_lead(rowsA: Array, rowsB: Array) -> Array:
	var dA := {}
	var dB := {}
	for r in rowsA:
		dA[int(r["w"])] = float(r["ratio"])
	for r in rowsB:
		dB[int(r["w"])] = float(r["ratio"])
	var lead := {"A": 0, "B": 0}
	var flips := 0
	var prev = null
	var cross: Array = []
	var firstA = null
	var firstB = null
	for w in range(1, 21):
		if not dA.has(w) or not dB.has(w):
			continue
		var a := float(dA[w])
		var b := float(dB[w])
		var who := "A" if a > b else ("B" if b > a else "=")
		if who == "A" or who == "B":
			lead[who] = int(lead[who]) + 1
			if who == "A" and firstA == null:
				firstA = w
			if who == "B" and firstB == null:
				firstB = w
			if prev != null and prev != who:
				flips += 1
			prev = who
		cross.append([w, pround(a, 3), pround(b, 3), who])
	return [cross, lead, flips, firstA, firstB]


# ---------------------------------------------------------------------------
# v06 `stage_health()` (L335-343)
# ---------------------------------------------------------------------------
static func stage_health(rows: Array) -> Dictionary:
	var d := {}
	for r in rows:
		d[int(r["w"])] = r
	var survive := true
	for w in range(1, 10):
		if d.has(w) and float(d[w]["core_hp"]) <= 0.0:
			survive = false
	var r16 = d.get(16, null)
	var r20 = d.get(20, null)
	var grow := 0.0
	if r16 != null and r20 != null and float(r16["ratio"]) > 0.0:
		grow = float(r20["ratio"]) / float(r16["ratio"])
	var tail: Array = []
	for w2 in range(13, 21):
		if d.has(w2):
			tail.append(float(d[w2]["ratio"]))
	var rise := true
	for i in range(tail.size() - 1):
		if float(tail[i]) > float(tail[i + 1]) + 1e-9:
			rise = false
	return {
		"survive": survive,
		"grow": pround(grow, 2),
		"rise": rise,
		"healthy": survive and grow > 1.0,
	}


# ---------------------------------------------------------------------------
# v06 `takeoff_rate()` (L346-361)
#   ⚠️ rng 必须在**所有 run 之间连续使用**（Python 的 `takeoff_rate` 只建一次
#      Random(seed)，300 局共用同一条序列）—— 每次 run 新建 rng 会得到不同的分布。
# ---------------------------------------------------------------------------
static func takeoff_rate(path: String, cfg: Dictionary, runs: int = 300,
		max_wave: int = 20, actions: int = 12, rng = null) -> Dictionary:
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = actions
		var out := _RunLoop.run(path, cx, max_wave, null, rng)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := takeoff_wave(rows)
		if alive and tw >= 0:
			takeoffs += 1
			hits.append(tw)
	return {
		"rate": pround(float(takeoffs) / float(runs), 3),
		"surv": pround(float(survives) / float(runs), 3),
		"med": _median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
	}


static func _median(a: Array) -> float:
	if a.is_empty():
		return -1.0
	var b: Array = a.duplicate()
	b.sort()
	var n := b.size()
	if n % 2 == 1:
		return float(b[(n - 1) / 2])
	return (float(b[n / 2 - 1]) + float(b[n / 2])) / 2.0


# ---------------------------------------------------------------------------
# v07 `eval_point()` (L252-295) 的判据装配：一条龙给齐 6 条判据的实测值
# ---------------------------------------------------------------------------
static func eval_point(cfgA: Dictionary, cfgB: Dictionary) -> Dictionary:
	var stA := _RunLoop.run("A", cfgA, 20)
	var stB := _RunLoop.run("B", cfgB, 20)
	var sA := summarize(stA["rows"])
	var sB := summarize(stB["rows"])
	var cl := cross_lead(stA["rows"], stB["rows"])
	var w20A := float(sA["w20"]) if sA["w20"] != null else 0.0
	var w20B := float(sB["w20"]) if sB["w20"] != null else 0.0
	var ba := pround(w20B / w20A, 3) if w20A != 0.0 else 0.0
	var hA := stage_health(stA["rows"])
	var hB := stage_health(stB["rows"])
	return {
		"rowsA": stA["rows"], "rowsB": stB["rows"],
		"playerA": stA["player"], "playerB": stB["player"],
		"sA": sA, "sB": sB,
		"toA": int(sA["takeoff"]), "toB": int(sB["takeoff"]),
		"w20A": pround(w20A, 2), "w20B": pround(w20B, 2), "ba": ba,
		"cross": cl[0], "lead": cl[1], "flips": cl[2],
		"firstA": cl[3], "firstB": cl[4],
		"hA": hA, "hB": hB,
		"c_win": int(sB["takeoff"]) >= 10 and int(sB["takeoff"]) <= 15,
		"c_ba": ba < 1.0,
		"c_flips": int(cl[2]) >= 1,
		"c_health": bool(hA["healthy"]) and bool(hB["healthy"]),
	}
