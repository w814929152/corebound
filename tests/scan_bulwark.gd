extends SceneTree
##
## 🔒 T1 肉盾塔 Bulwark 有效性诊断（玩法② · Q-T11 顺序2 · 「按推荐」= 涌现策略 + ①理想肉盾建模）。
##
## 背景：肉盾塔 = 涌现策略（机制已存在：仇恨选最近未 Disabled 塔 → 暴露位塔天然先挨打，
##   怪物锁定后停下打它、不前进不漏怪 → 锁住仇恨保住后排）。缺口在"肉盾身份"（HP/DPS 脱钩），
##   涌现策略下不新增卡种（金标本零改动）。本诊断验证"保塔策略"对起飞率的真实效果。
##
## 建模：金标本 AI（shop_ai）不玩保塔（纯 DPS 贪心，主力塔必落暴露枢纽位 S1/S2）→
##   肉盾塔是**玩家策略**。用诊断参数模拟"玩家保塔"，隔离"保命 vs 降 DPS"净效果：
##     · protect_core（V-2 已诊断）：主力塔隐身，怪物跳过它（塔仍在暴露位，E 不变）→ A 0.583 仍破线
##     · bulwark（本诊断）：主力塔**真挪到安全位 S4/S5**（打不到，但 E 降 → DPS 降），
##       原安全位的塔换到暴露位充当肉盾。更贴近玩家真实保塔操作。
##
## 四组对照（各 300 局 MC，同 seed PyRandom，与金标本逐位一致）：
##   · A 无保护      （protect_core=false, bulwark=false）→ 复现起飞率 A 0.277（破 60% 红线）
##   · A 主力塔隐身  （protect_core=true,  bulwark=false）→ 复现 V-2 的 0.580（仍破线）
##   · A 理想肉盾    （protect_core=false, bulwark=true） → 主力塔放安全位（本诊断核心）
##   · B 无保护      （protect_core=false, bulwark=false）→ 复现起飞率 B 0.817（通过）
##
## 🔴 口径自证（防跨口径串味，见 a-side-balance-adjudication.md §1.4/§4）：
##   本脚本 = 六槽 PATH（cfg_of 默认 n_slots=6 · SpaceModel.mode=PATH），**非**八槽 RADIAL。
##   其输出与「八槽 survive_rate 0.60 红线」**不可直接比**（红线归属 = A 起飞率 × 六槽定稿）。
##
## 判读：
##   · 若 A 理想肉盾 ≥ 0.60 → 保塔策略对单核流有效，肉盾塔玩法成立（玩家能救 A）；
##     但 GDD §3.6 预判"肉盾对单核流是纯成本"（牺牲输出塔当肉盾 + 安全位 DPS 不足）→
##     若仍破线则印证预判：单核流天生不适合肉盾，多塔流才是肉盾主场（对接 V-4）。
##   · 对比 A 隐身(0.580) vs A 理想肉盾：量化"真放安全位"相对"隐身"的 DPS 代价。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_bulwark.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 push_error(stderr 不缓冲)。
##
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")

const W_MAX := 20
const WARMUP := 2           # ✅ V-1 定稿起手保护（与 scan_protect_core/scan_attrition 一致）
const ATTRITION := 1.5      # ✅ V-1 定稿（扫参已定，此处固定）


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  T1 肉盾塔 Bulwark 有效性诊断（玩法② 涌现策略 + ①理想肉盾建模）")
	print("  每点 %d 局 MC · ATTRITION=%.1f · 起手保护 W1–%d" % [runs, ATTRITION, WARMUP])
	print("  四组对照：A无保护 / A主力塔隐身 / A理想肉盾 / B无保护")
	print("===============================================================")
	print("")

	# A 无保护（复现破线）
	var rA := _run_path("A", false, false, runs)
	print("  A 无保护        ：起飞率 = %s  存活 = %s" % [_fmt(rA["rate"]), _fmt(rA["surv"])])
	push_error("[Bulwark] A 无保护 rate=%s surv=%s" % [_fmt(rA["rate"]), _fmt(rA["surv"])])

	# A 主力塔隐身（复现 V-2 0.583）
	var rAp := _run_path("A", true, false, runs)
	print("  A 主力塔隐身    ：起飞率 = %s  存活 = %s" % [_fmt(rAp["rate"]), _fmt(rAp["surv"])])
	push_error("[Bulwark] A 隐身 rate=%s surv=%s" % [_fmt(rAp["rate"]), _fmt(rAp["surv"])])

	# A 理想肉盾（本诊断核心：主力塔真放安全位）
	var rAb := _run_path("A", false, true, runs)
	print("  A 理想肉盾      ：起飞率 = %s  存活 = %s" % [_fmt(rAb["rate"]), _fmt(rAb["surv"])])
	push_error("[Bulwark] A 理想肉盾 rate=%s surv=%s" % [_fmt(rAb["rate"]), _fmt(rAb["surv"])])

	# B 无保护（复现通过）
	var rB := _run_path("B", false, false, runs)
	print("  B 无保护        ：起飞率 = %s  存活 = %s" % [_fmt(rB["rate"]), _fmt(rB["surv"])])
	push_error("[Bulwark] B 无保护 rate=%s surv=%s" % [_fmt(rB["rate"]), _fmt(rB["surv"])])

	print("")
	print("  ▶ 判读：")
	print("     · A 破线复现：%s（预期 ≈0.28 < 0.60）" % ("✅" if float(rA["rate"]) < 0.60 else "❌"))
	print("     · B 通过复现：%s（预期 ≥0.80）" % ("✅" if float(rB["rate"]) >= 0.80 else "❌"))
	print("     · A 隐身复现：%s（预期 ≈0.580，V-2 基线）" % ("✅" if absf(float(rAp["rate"]) - 0.580) < 0.05 else "⚠ %.3f" % float(rAp["rate"])))
	print("")
	if float(rAb["rate"]) >= 0.60:
		print("     · A 理想肉盾回升至 %s ≥ 0.60 → 保塔策略对单核流有效，肉盾塔玩法成立（玩家能救 A）✓" % _fmt(rAb["rate"]))
	elif float(rAb["rate"]) > float(rAp["rate"]) + 0.05:
		print("     · A 理想肉盾小幅回升至 %s（仍破线）→ 保塔有益但单核流 DPS 代价过大，印证 GDD「肉盾对单核是纯成本」" % _fmt(rAb["rate"]))
	elif float(rAb["rate"]) > float(rA["rate"]) + 0.05:
		print("     · A 理想肉盾略回升至 %s（仍破线）→ 保塔收益有限，肉盾主场在多塔流（对接 V-4）" % _fmt(rAb["rate"]))
	else:
		print("     · A 理想肉盾几乎不变 %s → 安全位 DPS 严重不足，单核流保塔无意义（肉盾纯成本成立）" % _fmt(rAb["rate"]))
	# 隐身 vs 理想肉盾：量化"真放安全位"相对"隐身"的 DPS 代价
	var delta := float(rAb["rate"]) - float(rAp["rate"])
	print("     · 理想肉盾 vs 隐身：Δ起飞率 = %s（%s → 真放安全位的 DPS 代价%s）"
		% [_fmt(delta), ("隐身更高" if delta < 0 else "肉盾更高"), ("明显" if absf(delta) > 0.05 else "有限")])
	print("")
	quit(0)


## 跑指定路径 runs 局。protect_core / bulwark 贯穿到战斗镜像。
func _run_path(path: String, protect_core: bool, bulwark: bool, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	var takeoffs := 0
	var survives := 0
	# 🔴 独立 PyRandom（同 seed 20261002）：与金标本 MC 逐位一致（rng 跨局连续消费）。
	#    四组各自独立 rng，避免互相污染消费序列（与 scan_protect_core 同口径）。
	var rng := _PyRandom.new(20261002)
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = 12
		var out := _RunLoopAggro.run(path, cx, W_MAX, null, rng, true, 0.6, ATTRITION, WARMUP, protect_core, bulwark)
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
