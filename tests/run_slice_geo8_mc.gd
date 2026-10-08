extends SceneTree
##
## headless 八槽 MC 起飞率对照（`geo8mc` 入口）—— 阶段1 #74 数值扫参·闸门②
##
## 🔴 使命：在 κ_r=0.050（六槽定稿起点）下，对照八槽 vs 六槽的 A/B 起飞率，
##    量化八槽（多两座外哨、共鸣拓扑变化）对**起飞难度**的影响。
##    这是八槽平衡定稿前的诊断基线，不是定稿证明。
##
##    草案红线：八槽不得继承六槽 V-0′ 结论；κ_r=0.050 只是扫参起点。
##    本探针回答："八槽在六槽 κ_r 下，起飞率是变易还是变难？幅度多大？"
##
## 四组对照（各 300 局 MC，同 seed PyRandom）：
##   · A 六槽（n_slots=6）  · A 八槽（n_slots=8）
##   · B 六槽（n_slots=6）  · B 八槽（n_slots=8）
##
## 判读：
##   · ΔA = A八槽 - A六槽；ΔB = B八槽 - B六槽
##   · 八槽多两座塔位 → 理论上 DPS 天花板更高，但新槽暴露度低（相对安全）
##     → 若 Δ 温和（≥ -0.05）→ 八槽不破坏起飞可行性；
##   · 若某路径 Δ 剧烈为负 → 八槽共鸣稀释/落位变化伤到该路径，需 κ_r 重扫补偿。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script tests/run_slice_geo8_mc.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 stderr。
##

const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _RunLoopAggro = preload("res://scripts/engine/run_loop_aggro.gd")
const _PyRandom = preload("res://scripts/engine/py_random.gd")

const W_MAX := 20
const WARMUP := 2
const ATTRITION := 1.5


func _fmt(v: float) -> String:
	return "%.3f" % v


func _run(path: String, n_slots: int, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["n_slots"] = n_slots
	cfg["max_actions"] = 12
	var rng := _PyRandom.new(20260930)
	return _RunLoopAggro.takeoff_rate(path, cfg, runs, W_MAX, 12, rng, true, 0.6, ATTRITION, WARMUP, false, false, false)


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  径向阶段1 · 八槽 MC 起飞率对照（闸门② · κ_r=0.050 起点）")
	print("  每点 %d 局 MC · ATTRITION=%.1f · 起手保护 W1-%d" % [runs, ATTRITION, WARMUP])
	print("  四组对照：A六槽 / A八槽 / B六槽 / B八槽")
	print("===============================================================")
	print("")

	var a6 := _run("A", 6, runs)
	print("  A 六槽 ：起飞率 = %s  存活 = %s  中位波 = %s"
		% [_fmt(a6["rate"]), _fmt(a6["surv"]), str(a6["med"])])
	var a8 := _run("A", 8, runs)
	print("  A 八槽 ：起飞率 = %s  存活 = %s  中位波 = %s"
		% [_fmt(a8["rate"]), _fmt(a8["surv"]), str(a8["med"])])
	var dA: float = float(a8["rate"]) - float(a6["rate"])
	print("  >> ΔA（八槽-六槽）= %s" % _fmt(dA))
	print("")

	var b6 := _run("B", 6, runs)
	print("  B 六槽 ：起飞率 = %s  存活 = %s  中位波 = %s"
		% [_fmt(b6["rate"]), _fmt(b6["surv"]), str(b6["med"])])
	var b8 := _run("B", 8, runs)
	print("  B 八槽 ：起飞率 = %s  存活 = %s  中位波 = %s"
		% [_fmt(b8["rate"]), _fmt(b8["surv"]), str(b8["med"])])
	var dB: float = float(b8["rate"]) - float(b6["rate"])
	print("  >> ΔB（八槽-六槽）= %s" % _fmt(dB))
	print("")

	print("===============================================================")
	print("  判读：Δ 温和(≥ -0.05) → 八槽不破坏起飞；剧烈为负 → 需 κ_r 重扫")
	print("  ΔA=%s  ΔB=%s" % [_fmt(dA), _fmt(dB)])
	print("===============================================================")
	# 诊断探针：始终 exit 0（结果供人工判读，非自动闸门）
	quit(0)
