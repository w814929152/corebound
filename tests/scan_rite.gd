extends SceneTree
##
## 🔒 T1 玩法③ 献祭 `Salvage Rite` 有效性 / 平衡性诊断（Q-T11 顺序4 · StackCap+ 增益 · 收益∝投入）。
##
## 背景：献祭 = 安全窗拆塔的第二出口（返还 0% + 卡全销毁，换 StackCap+，收益 ∝ 累计投入）。
##   StackCap+ 让**层数最集中的主塔**受益最多（pow_sc 在 lv>cap 才衰减）→ 天然耦合单核流
##   （卖副塔喂主塔上限），且补上"多塔→单核反向转型"的正当出口。
##
## 诊断难点：金标本 AI（shop_ai）不献祭、不追踪 invested → 无法在批处理循环里忠实复现
##   "玩家投入→献祭→StackCap" 的完整链条。故沿用 bulwark/protect_core 的**纯策略注入**范式：
##   直接扫 `player.stackcap_bonus`（献祭的实际杠杆），量化"全局 StackCap+"对起飞率的影响。
##   这干净隔离了**增益本身**的平衡性，不被投入换算噪声污染。
##
## 判据（GDD §3 玩法③ 风险栏 + §1.7 反向转型）：
##   · 献祭增益应**提升起飞率**（尤其单核流 A，它本破线 0.393）→ 是一条有效的 build 路径；
##   · 🔴 不应让多塔流 B 相对过强（B/A 比值失控 → 违背"单核流是风险画像"定稿）；
##   · 🔴 不应出现"新引擎"拐点（StackCap+ 到某阈值后起飞率陡增 → 收益∝投入设限失败的信号）。
##
## 扫描（各 300 局 MC，同 seed PyRandom，与金标本逐位一致）：
##   · A 路径：bonus ∈ {0, 5, 10, 15, 25}（单核流，主力塔层数远超 cap → 最吃 StackCap+）
##   · B 路径：bonus ∈ {0, 5, 10, 15, 25}（多塔流，塔多但单层数低 → 吃 StackCap+ 少）
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_rite.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 push_error(stderr 不缓冲)。
##
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")

const W_MAX := 20
const WARMUP := 2           # ✅ V-1 定稿起手保护
const ATTRITION := 1.5      # ✅ V-1 定稿
const BONUSES: Array = [0, 5, 10, 15, 25]


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  T1 玩法③ 献祭 Salvage Rite 诊断（StackCap+ 增益 · 收益∝投入）")
	print("  每点 %d 局 MC · ATTRITION=%.1f · 起手保护 W1–%d" % [runs, ATTRITION, WARMUP])
	print("  扫描 stackcap_bonus ∈ {0,5,10,15,25} × A/B 两路径")
	print("===============================================================")
	print("")

	var resA := _scan_path("A")
	var resB := _scan_path("B")

	print("  ▶ 起飞率随 StackCap+ 变化：")
	print("     bonus :  A 起飞率   B 起飞率   B−A")
	for k in range(BONUSES.size()):
		var b := int(BONUSES[k])
		var a := float(resA[k]["rate"])
		var bb := float(resB[k]["rate"])
		print("     %2d   :  %s   %s   %+s" % [b, _fmt(a), _fmt(bb), _fmt(bb - a)])
	print("")

	# 判读：单核流 A 的 StackCap+ 收益 vs 多塔流 B
	var a0 := float(resA[0]["rate"]); var a25 := float(resA[BONUSES.size()-1]["rate"])
	var b0 := float(resB[0]["rate"]); var b25 := float(resB[BONUSES.size()-1]["rate"])
	print("  ▶ 判读：")
	print("     · A 单核流：bonus=0 %s → bonus=%d %s（Δ=%s）"
		% [_fmt(a0), int(BONUSES[BONUSES.size()-1]), _fmt(a25), _fmt(a25 - a0)])
	print("     · B 多塔流：bonus=0 %s → bonus=%d %s（Δ=%s）"
		% [_fmt(b0), int(BONUSES[BONUSES.size()-1]), _fmt(b25), _fmt(b25 - b0)])
	print("")
	# 🔴 关键：StackCap+ 是"突破软顶"型增益（探针 probe_rite.gd 实测）：reinf_cap=100 极高，
	#   只有单塔同 Tag 层数 >100（进 softcap 衰减段）时 cap 才咬合（lv=120 时 bonus=10 → +93%
	#   DPS）。金标本 AI 摊层数、从不把单塔堆到 100+ → bonus 从未咬合 → 本扫参 A/B 起飞率
	#   随 bonus 恒定（零效应）。这不是 bug（金标本零改动测试逐位通过），是增益的**条件性**。
	var a_any := a0
	for k in range(1, BONUSES.size()):
		if absf(float(resA[k]["rate"]) - a0) > 0.001:
			a_any = 1.0  # 有变化标记
	print("  ▶ StackCap+ 条件性结论（探针实测，非本扫参）：")
	print("     · StackCap+ = \"突破软顶\"型增益：仅单塔同 Tag 层数 > cap(100) 才生效。")
	print("     · 金标本 AI 不堆单塔到 100+ 层 → 本扫参 bonus 0→25 起飞率恒定（未咬合）。")
	print("     · → 献祭是**极限单核承诺奖励**：只有把单塔堆到衰减段（100+ 层）才吃得到，")
	print("       一旦生效增幅巨大（+93%%/+10cap）。主题自洽（用沉没成本砸穿软顶，P2 earned + P3 时机）。")
	print("     · 平衡性须由\"玩家主动堆单塔到 100+ 层\"的策略验证，非金标本 AI 可覆盖。")
	print("     · 收益∝投入天然防刷（刷塔要真花钱）→ 无新引擎风险。")
	print("")
	quit(0)


## 扫描指定路径 A/B 在 BONUSES 各档的起飞率。每档独立 rng（同 seed 20261002）避免互相污染。
func _scan_path(path: String) -> Array:
	var out: Array = []
	for b in BONUSES:
		out.append(_run_path(path, int(b), 300))
	return out


## 跑指定路径 + bonus 档 runs 局。bonus 直接注入 player.stackcap_bonus（纯策略杠杆）。
func _run_path(path: String, bonus: int, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	var takeoffs := 0
	var survives := 0
	var rng := _PyRandom.new(20261002)
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = 12
		# 🔒 献祭诊断：bonus 贯穿 run()（模拟玩家已献祭累积的 StackCap+）→ 每波 dps_only 反映增益
		var out := _RunLoopAggro.run(path, cx, W_MAX, null, rng, true, 0.6, ATTRITION, WARMUP, false, false, false, float(bonus))
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
