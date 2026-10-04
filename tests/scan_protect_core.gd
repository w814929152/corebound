extends SceneTree
##
## 🔒 T1 V-2 诊断：起飞率 A 破线根因确认（「按推荐」= 方案① 前置诊断）。
##
## 目的：隔离"主力塔被打停"这单一变量，一锤定音确认 A 破线根因 =
##   「单核零冗余下主力塔被仇恨打停即崩」，而非数值失衡。
##
## 三组对照（各 300 局 MC，同 seed PyRandom，与金标本逐位一致）：
##   · A 无保护   （protect_core=false）→ 复现起飞率 A 0.29–0.46（破 60% 红线）
##   · A 保护主力塔（protect_core=true）→ 怪物跳过 h 最高主力塔、专打副塔
##   · B 无保护   （protect_core=false）→ 复现起飞率 B 0.883（通过）
##
## 判读：
##   · 若 A 保护后起飞率显著回升（≥0.60）→ 根因确认 = 主力塔被打停，
##     方案①（给单核流保塔策略）可行，V-2 判据维持 60% 不动。
##   · 若 A 保护后仍破线 → 根因不只是主力塔被打停（副塔也被打停/经济崩），
##     需重新评估方案① 或考虑方案②/③。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_protect_core.gd
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 push_error(stderr 不缓冲)。
##
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")

const W_MAX := 20
const WARMUP := 2           # ✅ V-1 定稿起手保护（与 scan_attrition 一致）
const ATTRITION := 1.5      # ✅ V-1 定稿（扫参已定，此处固定）


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  T1 V-2 诊断：起飞率 A 破线根因（主力塔被打停 vs 数值失衡）")
	print("  每点 %d 局 MC · ATTRITION=%.1f · 起手保护 W1–%d" % [runs, ATTRITION, WARMUP])
	print("  三组对照：A无保护 / A保护主力塔 / B无保护")
	print("===============================================================")
	print("")

	# A 无保护
	var rA := _run_path("A", false, runs)
	print("  A 无保护     ：起飞率 = %s  存活 = %s" % [_fmt(rA["rate"]), _fmt(rA["surv"])])
	push_error("[V2] A 无保护 rate=%s surv=%s" % [_fmt(rA["rate"]), _fmt(rA["surv"])])

	# A 保护主力塔
	var rAp := _run_path("A", true, runs)
	print("  A 保护主力塔 ：起飞率 = %s  存活 = %s" % [_fmt(rAp["rate"]), _fmt(rAp["surv"])])
	push_error("[V2] A 保护主力塔 rate=%s surv=%s" % [_fmt(rAp["rate"]), _fmt(rAp["surv"])])

	# B 无保护（复现基线）
	var rB := _run_path("B", false, runs)
	print("  B 无保护     ：起飞率 = %s  存活 = %s" % [_fmt(rB["rate"]), _fmt(rB["surv"])])
	push_error("[V2] B 无保护 rate=%s surv=%s" % [_fmt(rB["rate"]), _fmt(rB["surv"])])

	print("")
	print("  ▶ 判读：")
	print("     · A 破线复现：%s（预期 0.29–0.46 < 0.60）" % ("✅" if float(rA["rate"]) < 0.60 else "❌"))
	print("     · B 通过复现：%s（预期 ≥0.80）" % ("✅" if float(rB["rate"]) >= 0.80 else "❌"))
	if float(rAp["rate"]) >= 0.60:
		print("     · A 保护后回升至 %s ≥ 0.60 → 根因确认 = 主力塔被打停，方案① 可行 ✓" % _fmt(rAp["rate"]))
	elif float(rAp["rate"]) > float(rA["rate"]) + 0.05:
		print("     · A 保护后小幅回升至 %s（仍破线）→ 主力塔被打停是主因但非唯一，需重估方案" % _fmt(rAp["rate"]))
	else:
		print("     · A 保护后几乎不变 %s → 根因不只是主力塔被打停，方案① 存疑" % _fmt(rAp["rate"]))
	print("")
	quit(0)


## 跑指定路径 runs 局，返回起飞率 + 存活率。protect_core 贯穿到战斗镜像。
func _run_path(path: String, protect_core: bool, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	var takeoffs := 0
	var survives := 0
	# 🔴 独立 PyRandom（同 seed 20261002）：与金标本 MC 逐位一致（rng 跨局连续消费）。
	#    A/B/保护三组各自独立 rng，避免互相污染消费序列。
	var rng := _PyRandom.new(20261002)
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = 12
		var out := _RunLoopAggro.run(path, cx, W_MAX, null, rng, true, 0.6, ATTRITION, WARMUP, protect_core)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := -1
		for r in rows:
			if float(r["ratio"]) >= 1.0 and tw < 0:
				tw = int(r["w"])
		if alive and tw >= 0:
			takeoffs += 1
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"n_takeoff": takeoffs,
		"n_surv": survives,
	}


func _fmt(v: float, nd: int = 3) -> String:
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)
