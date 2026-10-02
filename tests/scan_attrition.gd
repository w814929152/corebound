extends SceneTree
##
## 🔒 T1 V-1 扫参：定稿 ATTRITION（怪物对塔 DPS ÷ HP0 复合比）。
##
## 判据（GDD `mechanics-tower-life-death` §4.2 V-1，定稿数值零改动只定新参数）：
##   · T-A 苟活期 W1–5   ：平均每局 **≥1** 座塔进 Disabled（机制可感知，不能形同虚设）
##   · T-B 成型期 W6–12  ：平均每局 Disabled **≤2** 次（不失控）
##   · T-C 雪崩期 W13–20 ：Disabled **≈0** 次（机制自然退场，保住 Submission 美学）
##   · 附带守护起飞率红线（V-2）：B 起飞率 ≥80% / A ≥60%（定稿数值不破线）
##
## 方法论（godot-param-sim-to-slice 扫参纪律）：
##   · 单参数扫描：只动 ATTRITION，其余定稿常量一字不改（HP0=120 / AGGRO_R=9.0 / exp=0.6）。
##   · 每点同 seed rng 跑 300 局 MC（build 序列一致，只变战斗口径）→ 逐点可比。
##   · 扫参走批处理镜像 `RunLoopAggro.run(..., attrition)`（金标本零改动：
##     `attrition < 0` 默认退化为读定稿常量，本脚本显式传覆盖值）。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_attrition.gd
##   （可选：末尾加 -- 覆盖 runs，如 `-- 60` = 每点 60 局快速试跑）
##

const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")


# ---------------------------------------------------------------------------
# 阶段划分（判据 T-A / T-B / T-C 的波次边界）
# ---------------------------------------------------------------------------
const W_SURVIVE_END := 5       # 苟活期 W1–5
const W_FORM_END := 12         # 成型期 W6–12（W13 起雪崩）
const W_MAX := 20
## 🔒 T1 起手保护波数（与 simulate_wave_aggro 的 warmup_waves 一致）：W1..WARMUP 仇恨不激活，
##   让起手单暴露塔金标本有喘息期。机制从 W(WARMUP+1)=W3 起才致命。扫参显式启用（可回退）。
const WARMUP := 2


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])
	# 第二个参数：网格步长（默认 0.5；诊断时可用 2.0 粗扫快速定位有效区间）
	var step := 0.5
	if user_args.size() > 1:
		step = float(user_args[1])

	print("")
	print("===============================================================")
	print("  T1 V-1 扫参：ATTRITION（怪物对塔 DPS ÷ HP0）")
	print("  每点 %d 局 MC · 路径 B（多塔金标本）· 判据 T-A/T-B/T-C" % runs)
	print("  起手保护 W1–%d 仇恨不激活（机制 W%d+ 生效）· exp=0.6" % [WARMUP, WARMUP + 1])
	print("  定稿常量：HP0=%.0f · AGGRO_R=%.1f（一字不改）" % [_MonsterData.HP0, _MonsterData.AGGRO_R])
	print("===============================================================")
	print("")

	# 扫参网格：[0.5, 1.0, ..., 8.0]（步长可配，默认 0.5 = 16 点）
	var grid: Array = []
	var v := 0.5
	while v <= 8.0 + 1e-9:
		grid.append(roundf(v * 2.0) / 2.0)
		v += step

	print("  %-7s | %-9s %-9s %-9s | %-8s %-8s %-8s | %s" % [
		"ATTRITION", "T-A 苟活", "T-B 成型", "T-C 雪崩", "起飞B", "起飞A", "存活B", "判定"])
	print("  " + "-".join(["---------", "---------", "---------", "---------", "--------", "--------", "--------", "------"]))

	var best: Dictionary = {}
	for at in grid:
		var r := _scan_point(at, runs)
		var verdict := _verdict(r)
		print("  %7.2f | %9s %9s %9s | %8s %8s %8s | %s" % [
			float(at),
			_fmt(r["ta"]), _fmt(r["tb"]), _fmt(r["tc"]),
			_fmt(r["rate"], 3), _fmt(r["rate_a"], 3), _fmt(r["surv"], 3),
			verdict])
		# 🔴 逐点进度走 stderr（push_error 不缓冲）：即使中途被杀，stderr 日志也能保住
		#    已算出的点（headless stdout 全缓冲，退出才 flush）。
		push_error("[scan] ATTRITION=%.2f TA=%s TB=%s TC=%s rateB=%s rateA=%s %s" % [
			float(at), _fmt(r["ta"]), _fmt(r["tb"]), _fmt(r["tc"]),
			_fmt(r["rate"]), _fmt(r["rate_a"]), verdict])
		# 记录满足判据且两条金标本起飞率都不破线的候选（供定稿推荐）
		if r["ok"] and (best.is_empty() or (not best.has("at"))):
			best = {"at": float(at), "r": r}

	print("")
	if best.has("at"):
		print("  ▶ 推荐定稿 ATTRITION = %.2f（首个全判据通过点）" % float(best["at"]))
		print("     T-A=%.3f  T-B=%.3f  T-C=%.3f  起飞B=%.3f  起飞A=%.3f  存活B=%.3f" % [
			float(best["r"]["ta"]), float(best["r"]["tb"]), float(best["r"]["tc"]),
			float(best["r"]["rate"]), float(best["r"]["rate_a"]), float(best["r"]["surv"])])
	else:
		print("  ▶ 无点全通过判据 —— 需回看 GDD 判据阈值或 HP0/AGGRO_R（R-T2 缓解方向）")
	print("")
	quit(0)


# ---------------------------------------------------------------------------
# 单点扫参：同 seed rng 跑 runs 局，累积三阶段新增 Disabled + 起飞
# ---------------------------------------------------------------------------
func _scan_point(attrition: float, runs: int) -> Dictionary:
	var cfgB := _Cfg.cfg_of("B")
	# 🔴 A/B 各用**独立** PyRandom（同 seed 20261002）：金标本 takeoff_rate 是单路径 +
	#    rng 跨局连续消费。扫参要同时看两条金标本，若共用一个 rng 会互相污染消费序列
	#    → B 序列不再逐位等于金标本 B。故 rngB / rngA 独立，各自与金标本单路径逐位一致。
	var rngB := _PyRandom.new(20261002)
	var rngA := _PyRandom.new(20261002)

	var dis_s1 := 0            # 苟活期 W1–5 累计新增 Disabled（跨所有局）
	var dis_s2 := 0            # 成型期 W6–12
	var dis_s3 := 0            # 雪崩期 W13–20
	var takeoffs := 0
	var survives := 0
	# A 路径（单核金标本）起飞率：塔死亡对两条金标本的冲击都可见（§4.2 起飞率 A 余量仅 +9.3pp，
	# 是最可能破线的一条 → 扫参必须同时看 A，否则定稿可能只保 B 破了 A）。
	var takeoffs_a := 0

	for _i in range(runs):
		var cx: Dictionary = cfgB.duplicate(true)
		cx["max_actions"] = 12
		var out := _RunLoopAggro.run("B", cx, W_MAX, null, rngB, true, 0.6, attrition, WARMUP)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := -1
		for r in rows:
			if float(r["ratio"]) >= 1.0 and tw < 0:
				tw = int(r["w"])
			# 累积各阶段本波新增 Disabled
			var wn: int = int(r["w"])
			var dn: int = int(r.get("dis_new", 0))
			if wn <= W_SURVIVE_END:
				dis_s1 += dn
			elif wn <= W_FORM_END:
				dis_s2 += dn
			else:
				dis_s3 += dn
		if alive and tw >= 0:
			takeoffs += 1

		# A 路径：同 seed 连续消费（PyRandom 状态延续，与金标本 MC 一致），只换路径标 "A"
		var cxa: Dictionary = _Cfg.cfg_of("A")
		cxa["max_actions"] = 12
		var outa := _RunLoopAggro.run("A", cxa, W_MAX, null, rngA, true, 0.6, attrition, WARMUP)
		var rowsa: Array = outa["rows"]
		var alivea := (not rowsa.is_empty()) and float(rowsa[-1]["core_hp"]) > 0.0
		var twa := -1
		for r in rowsa:
			if float(r["ratio"]) >= 1.0 and twa < 0:
				twa = int(r["w"])
		if alivea and twa >= 0:
			takeoffs_a += 1

	return {
		"ta": float(dis_s1) / float(runs),
		"tb": float(dis_s2) / float(runs),
		"tc": float(dis_s3) / float(runs),
		"rate": float(takeoffs) / float(runs),
		"rate_a": float(takeoffs_a) / float(runs),
		"surv": float(survives) / float(runs),
		"ok": _passes(float(dis_s1) / float(runs), float(dis_s2) / float(runs),
				float(dis_s3) / float(runs), float(takeoffs) / float(runs)),
	}


## 判据（§4.2 V-1）：T-A ≥1 · T-B ≤2 · T-C ≈0（容差 0.5）· 起飞率 B ≥0.80
func _passes(ta: float, tb: float, tc: float, rate: float) -> bool:
	return ta >= 1.0 and tb <= 2.0 and tc <= 0.5 and rate >= 0.80


func _verdict(r: Dictionary) -> String:
	if bool(r["ok"]):
		return "✅ PASS"
	var why: Array = []
	if float(r["ta"]) < 1.0:
		why.append("T-A不足(机制无感)")
	if float(r["tb"]) > 2.0:
		why.append("T-B失控")
	if float(r["tc"]) > 0.5:
		why.append("T-C未退场")
	if float(r["rate"]) < 0.80:
		why.append("起飞率破线")
	return "❌ " + "/".join(why)


func _fmt(v: float, nd: int = 3) -> String:
	# 简单定点打印（避免 pround 依赖；扫参表只需可读）
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)
