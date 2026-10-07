extends SceneTree
##
## 🔒 T1 ⑤ Sapper 精英有效性诊断（玩法⑤ · Q-T11 顺序3 · 「锁定增伤流」）。
##
## 背景：Sapper = Elite 波（每5波）里的一种精英怪：**无视距离直奔最近的塔并锁定攻击、
##   对塔伤害 ×3**。它是玩法①（暴露度 UI 预警）的"主动威胁版"——把塔死亡从"随机运气"
##   变成"Elite 波可预判的决策点"（下波有 Sapper → 提前给塔升 HP / 插肉盾 / 卖副塔换钱）。
##
## 建模：金标本 AI（shop_ai）不玩反 Sapper 策略（纯 DPS 贪心，不提前保塔）→ Sapper 是
##   **玩家策略压力测试**。用诊断参数模拟"Elite 波有 Sapper"，量化它对起飞率 / 塔死亡的
##   冲击，验证两件事：
##     ① Sapper 是否造成"一击致死"式崩塌（灾难 B）——塔死不应让 DPS 断崖到必输；
##     ② Sapper 的惩罚是否在"可预判、可应对"范围内（配合玩法①暴露度 UI，玩家能提前准备）。
##
## 四组对照（各 300 局 MC，同 seed PyRandom，与金标本逐位一致）：
##   · A 无 Sapper   （sapper=false）→ 复现起飞率 A（单核流基线）
##   · A 有 Sapper   （sapper=true） → Elite 波锁塔 ×3（本诊断核心）
##   · B 无 Sapper   （sapper=false）→ 复现起飞率 B（多塔流基线）
##   · B 有 Sapper   （sapper=true） → Elite 波锁塔 ×3
##
## 判读：
##   · Δ起飞率(A) = A有 - A无；Δ起飞率(B) = B有 - B无。
##   · 若 Δ 温和（≥ -0.15）→ Sapper 惩罚在可应对范围，玩法成立（配合暴露度 UI 玩家能救）；
##   · 若 Δ 剧烈（< -0.30）→ Sapper 对金标本 AI 过猛，需下调 ×3 倍率或加反制窗口（对接 V-4）。
##   · 对比 A vs B 的 Δ：多塔流更能扛 Sapper（肉盾/冗余塔吸收），单核流更脆 → 印证"多塔流是
##     肉盾主场"（与玩法②肉盾塔结论联动）。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_sapper.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 push_error(stderr 不缓冲)。
##
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")

const W_MAX := 20
const WARMUP := 2           # ✅ V-1 定稿起手保护（与 scan_bulwark/scan_attrition 一致）
const ATTRITION := 1.5      # ✅ V-1 定稿（扫参已定，此处固定）


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  T1 ⑤ Sapper 精英有效性诊断（玩法⑤ 锁定增伤流 · Elite 波锁塔×3）")
	print("  每点 %d 局 MC · ATTRITION=%.1f · 起手保护 W1–%d" % [runs, ATTRITION, WARMUP])
	print("  四组对照：A无Sapper / A有Sapper / B无Sapper / B有Sapper")
	print("===============================================================")
	print("")

	# A 无 Sapper（单核流基线）
	var rA := _run_path("A", false, runs)
	print("  A 无 Sapper     ：起飞率 = %s  存活 = %s" % [_fmt(rA["rate"]), _fmt(rA["surv"])])
	push_error("[Sapper] A 无Sapper rate=%s surv=%s towers_disabled=%s"
		% [_fmt(rA["rate"]), _fmt(rA["surv"]), _fmt(rA["td"], 1)])

	# A 有 Sapper（本诊断核心：Elite 波锁塔 ×3）
	var rAs := _run_path("A", true, runs)
	print("  A 有 Sapper     ：起飞率 = %s  存活 = %s" % [_fmt(rAs["rate"]), _fmt(rAs["surv"])])
	push_error("[Sapper] A 有Sapper rate=%s surv=%s towers_disabled=%s"
		% [_fmt(rAs["rate"]), _fmt(rAs["surv"]), _fmt(rAs["td"], 1)])

	# B 无 Sapper（多塔流基线）
	var rB := _run_path("B", false, runs)
	print("  B 无 Sapper     ：起飞率 = %s  存活 = %s" % [_fmt(rB["rate"]), _fmt(rB["surv"])])
	push_error("[Sapper] B 无Sapper rate=%s surv=%s towers_disabled=%s"
		% [_fmt(rB["rate"]), _fmt(rB["surv"]), _fmt(rB["td"], 1)])

	# B 有 Sapper
	var rBs := _run_path("B", true, runs)
	print("  B 有 Sapper     ：起飞率 = %s  存活 = %s" % [_fmt(rBs["rate"]), _fmt(rBs["surv"])])
	push_error("[Sapper] B 有Sapper rate=%s surv=%s towers_disabled=%s"
		% [_fmt(rBs["rate"]), _fmt(rBs["surv"]), _fmt(rBs["td"], 1)])

	var dA := float(rAs["rate"]) - float(rA["rate"])
	var dB := float(rBs["rate"]) - float(rB["rate"])
	print("")
	print("  ▶ 判读：")
	print("     · Δ起飞率(A) = %s   Δ起飞率(B) = %s" % [_fmt(dA), _fmt(dB)])
	print("     · A 单核流脆度：%s（Sapper 对单核流冲击%s）"
		% ["%.3f" % dA, ("较大" if dA < -0.15 else "温和")])
	print("     · B 多塔流韧性：%s（Sapper 对多塔流冲击%s）"
		% ["%.3f" % dB, ("较大" if dB < -0.15 else "温和")])
	print("")
	if dA >= -0.10 and dB >= -0.10:
		print("     · ✅ Sapper 惩罚温和（Δ ≥ -0.10）→ 配合暴露度 UI 玩家能预判应对，玩法成立，定稿数值零改动。")
	elif dA >= -0.25 and dB >= -0.15:
		print("     · 🟡 Sapper 惩罚中等 → 玩法有压力但可应对；建议保留 ×3、靠暴露度 UI 给玩家反制窗口。")
	else:
		print("     · ⚠ Sapper 惩罚偏重 → 金标本 AI 不保塔时被 Elite 波打崩；需下调 ×3 或加反制窗口（对接 V-4）。")
	print("     · 多塔流 vs 单核流扛 Sapper：%s（印证「多塔流是肉盾主场」）"
		% ("B 更扛" if dB > dA + 0.05 else ("A 更扛" if dA > dB + 0.05 else "相当")))
	print("")
	quit(0)


## 跑指定路径 runs 局。sapper 贯穿到战斗镜像（仅 Elite 波生效）。
## 返回起飞率 + 存活率 + 平均塔死数（末波存量差代理，负值=净修复）。
func _run_path(path: String, sapper: bool, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	var takeoffs := 0
	var survives := 0
	var td_sum := 0
	# 🔴 独立 PyRandom（同 seed 20261002）：与金标本 MC 逐位一致（rng 跨局连续消费）。
	var rng := _PyRandom.new(20261002)
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = 12
		var out := _RunLoopAggro.run(path, cx, W_MAX, null, rng, true, 0.6, ATTRITION, WARMUP, false, false, sapper)
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
		# 末波塔死存量（代理 Sapper 造成的塔损耗；负值=玩家波次间净修复了塔）
		if not rows.is_empty():
			td_sum += int(rows[-1].get("towers_disabled", 0))
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"td": float(td_sum) / float(runs),
		"n_takeoff": takeoffs,
		"n_surv": survives,
	}


func _fmt(v: float, nd: int = 3) -> String:
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)
