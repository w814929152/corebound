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
## 四组对照 × 两口径（各 300 局 MC，同 seed PyRandom）：
##   · A 六槽（n_slots=6）  · A 八槽（n_slots=8）
##   · B 六槽（n_slots=6）  · B 八槽（n_slots=8）
##   🔴 ARM 1 = PATH（既有基线）· ARM 2 = RADIAL（真径向 · R-8 新增）
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
## 🔴 R-8（质量门 QG-RADIAL-01 §2.4(b)）：原脚本头自称"径向"，却从未设 `SpaceModel.mode`
##    → 实为"八槽 × PATH"。现补 **RADIAL 臂**做**真径向对照**（同一 seed，控制变量）：
##      · ARM 1 = PATH（既有基线，逐位不变）
##      · ARM 2 = RADIAL（怪物从出生环 s=55 直插核心 · 新增）
##    跑完务必把 `SpaceModel.mode` 设回 PATH（全局开关，防污染）。
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 stderr。
##

const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _RunLoopAggro = preload("res://scripts/engine/run_loop_aggro.gd")
const _PyRandom = preload("res://scripts/engine/py_random.gd")
const _SpaceModel = preload("res://scripts/geo/space_model.gd")

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


## 在**当前** `SpaceModel.mode` 下跑 A六/A八/B六/B八 四组，打印并返回起飞率对照。
func _arm(runs: int) -> Dictionary:
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
	return {"a6": float(a6["rate"]), "a8": float(a8["rate"]), "dA": dA,
			"b6": float(b6["rate"]), "b8": float(b8["rate"]), "dB": dB}


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  径向 · 八槽 MC 起飞率对照（闸门② · κ_r=0.050 起点）")
	print("  每点 %d 局 MC · ATTRITION=%.1f · 起手保护 W1-%d" % [runs, ATTRITION, WARMUP])
	print("  四组 × 两口径：PATH（既有基线）+ RADIAL（真径向 · R-8 新增）")
	print("===============================================================")

	# ---- ARM 1：PATH 口径（既有基线，逐位不变）----
	print("\n  === [ARM 1] PATH 口径（怪物走折线 · 既有基线）===")
	var p := _arm(runs)

	# ---- ARM 2：RADIAL 口径（真径向对照 · R-8 新增）----
	print("\n  === [ARM 2] RADIAL 口径（怪物从出生环 R_s=55 直插核心）===")
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var r := _arm(runs)
	_SpaceModel.mode = _SpaceModel.Mode.PATH   # 🔴 回退防污染

	# ---- 对照：RADIAL vs PATH（同 seed，控制变量）----
	print("\n===============================================================")
	print("  对照（RADIAL - PATH · 同 seed）：")
	print("    A 六槽：RADIAL %s - PATH %s = %s"
		% [_fmt(r["a6"]), _fmt(p["a6"]), _fmt(float(r["a6"]) - float(p["a6"]))])
	print("    A 八槽：RADIAL %s - PATH %s = %s"
		% [_fmt(r["a8"]), _fmt(p["a8"]), _fmt(float(r["a8"]) - float(p["a8"]))])
	print("    B 六槽：RADIAL %s - PATH %s = %s"
		% [_fmt(r["b6"]), _fmt(p["b6"]), _fmt(float(r["b6"]) - float(p["b6"]))])
	print("    B 八槽：RADIAL %s - PATH %s = %s"
		% [_fmt(r["b8"]), _fmt(p["b8"]), _fmt(float(r["b8"]) - float(p["b8"]))])
	print("  PATH 内 ΔA=%s ΔB=%s ｜ RADIAL 内 ΔA=%s ΔB=%s"
		% [_fmt(p["dA"]), _fmt(p["dB"]), _fmt(r["dA"]), _fmt(r["dB"])])
	print("  判读：Δ 温和(≥ -0.05) → 八槽不破坏起飞；剧烈为负 → 需 κ_r 重扫")
	print("===============================================================")
	# 诊断探针：始终 exit 0（结果供人工判读，非自动闸门）
	quit(0)
