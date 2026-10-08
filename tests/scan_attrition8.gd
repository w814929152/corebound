extends SceneTree
##
## 🔒 T1 V-1′ 扫参（八槽径向）：重定稿 ATTRITION（怪物对塔 DPS ÷ HP0 复合比）。
##
## 依据：`design/gdd/radial-core-siege-draft.md` §6.3 / F-R2 / V-1′（阶段3 T1 数值重扫）。
##   径向模型下塔挨打总量被稀释（怪物沿射线直插核心，只在塔的危险楔形内停留），
##   六槽定稿 ATTRITION=1.50 在径向 + 八槽新暴露度下会让塔死亡频率掉档 → V-1 判据
##   T-A（苟活期 ≥1 座/局）大概率破线 → **必须按八槽几何重新扫参，不套用六槽结论**。
##
## 判据（沿用 V-1 §4.2，八槽下重新定稿）：
##   · T-A 苟活期 W1–5   ：平均每局 **≥1** 座塔进 Disabled（机制可感知）
##   · T-B 成型期 W6–12  ：平均每局 Disabled **≤2** 次（不失控）
##   · T-C 雪崩期 W13–20 ：Disabled **≈0** 次（机制自然退场）
##   · 附带起飞率红线：B 起飞率 ≥0.80（定稿数值不破线）；A 记录（V-2 单核高风险画像）
##
## 方法论（godot-param-sim-to-slice 扫参纪律）：
##   · 单参数扫描：只动 ATTRITION，其余定稿常量一字不改（HP0=120 / AGGRO_R=9.0 / exp=0.6）。
##   · 每点同 seed rng 跑 N 局 MC（build 序列一致，只变战斗口径）→ 逐点可比。
##   · 🔴 八槽径向：cfg.n_slots=8（走 Geo8 工厂）+ SpaceModel.mode=RADIAL
##     （战斗镜像 wave_sim_aggro 按模式分派怪物位置派生，与实时版 monster.pos 逐位对齐）。
##   · 扫参走批处理镜像 RunLoopAggro.run(..., attrition)（金标本零改动：attrition<0 默认
##     退化为读定稿常量；本脚本显式传覆盖值）。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_attrition8.gd
##   （可选：`-- 60` = 每点 60 局快速试跑；`-- 60 1.0` = 60 局 + 步长 1.0 粗扫）
##
## ⚠️ 与六槽 scan_attrition.gd 的差异（务必分清）：
##   · 六槽版默认 PATH 模式 + n_slots=6 → 定稿 ATTRITION=1.50（V-1）。
##   · 本版 RADIAL 模式 + n_slots=8 → 全新扫描，落点与六槽**不可互推**（八槽多两座外环
##     相对安全哨 S6/S7，玩家可把主力塔放安全位 → 挨打总量进一步下降 → ATTRITION 需更高）。
##

const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")


# ---------------------------------------------------------------------------
# 阶段划分（判据 T-A / T-B / T-C 的波次边界）
# ---------------------------------------------------------------------------
const W_SURVIVE_END := 5       # 苟活期 W1–5
const W_FORM_END := 12         # 成型期 W6–12（W13 起雪崩）
const W_MAX := 20
## 🔒 T1 起手保护波数（与 simulate_wave_aggro 的 warmup_waves 一致）：W1..WARMUP 仇恨不激活。
const WARMUP := 2


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])
	# 第二个参数：网格步长（默认 0.5；粗扫可用 1.0 快速定位有效区间）
	var step := 0.5
	if user_args.size() > 1:
		step = float(user_args[1])

	# 🔴 切径向模式（本扫描专用，跑后回退 PATH）：战斗镜像 wave_sim_aggro 据此刻分派
	#    怪物位置派生（radial_pos_of_t），与实时版 monster.pos 逐位对齐（E-5）。
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	print("")
	print("===============================================================")
	print("  T1 V-1′ 扫参（八槽径向）：ATTRITION（怪物对塔 DPS ÷ HP0）")
	print("  每点 %d 局 MC · 路径 B（多塔金标本）· n_slots=8 · RADIAL 模式" % runs)
	print("  判据 T-A/T-B/T-C · 起手保护 W1–%d 仇恨不激活（机制 W%d+ 生效）" % [WARMUP, WARMUP + 1])
	print("  定稿常量：HP0=%.0f · AGGRO_R=%.1f · exp=0.6（一字不改）" % [_MonsterData.HP0, _MonsterData.AGGRO_R])
	print("  扫描区间 [1.0, 6.0]（六槽定稿 1.50 仅作参考起点，八槽径向不可互推）")
	print("===============================================================")
	print("")

	# 扫参网格：[1.0, 1.5, ..., 6.0]（步长可配）
	var grid: Array = []
	var v := 1.0
	while v <= 6.0 + 1e-9:
		grid.append(roundf(v * 2.0) / 2.0)
		v += step

	# 🔒 V-1′ 分列口径表头：A 成型期（T-A′/T-B′ 基准）· B 全程（T-D′ 免疫）· B 雪崩（T-C′ 退场）
	# 🟡 R-2（§4.2 末段）：新增 **命中A** 列 —— A 路径单局 X_form≥1 的**无条件命中率**。
	#    均值对 ATTRITION 已被证伪「无鉴别力」（1.0→6.0 只在 1.000~1.483 非单调浮动），
	#    命中率是否更有鉴别力值得一测（若单调且跨度大 → §3.3-② 可被部分翻案）。
	#    🔴 本列纯诊断，**不进 `_passes()` 判据**（阈值待 R-2 per-run 实测回填后定档）。
	print("  %-7s | %-9s %-8s %-9s %-9s | %-8s %-8s %-8s | %s" % [
		"ATTRITION", "A成型T-A′", "命中A", "B全程T-D′", "B雪崩T-C′", "起飞B", "起飞A", "存活B", "判定"])
	print("  " + "-".join(["---------", "---------", "--------", "---------", "---------", "--------", "--------", "--------", "------"]))
	print("  （判据：A成型 1~4 · B全程 0 · B雪崩 ≈0 · 起飞B ≥0.80；命中A 为 R-2 诊断列，不入判据）")

	var best: Dictionary = {}
	for at in grid:
		var r := _scan_point(float(at), runs)
		var verdict := _verdict(r)
		print("  %7.2f | %9s %8s %9s %9s | %8s %8s %8s | %s" % [
			float(at),
			_fmt(r["a_form"]), _fmt(r["hit"], 3), _fmt(r["b_total"]), _fmt(r["b_tc"]),
			_fmt(r["rate"], 3), _fmt(r["rate_a"], 3), _fmt(r["surv"], 3),
			verdict])
		# 🔴 逐点进度走 stderr（push_error 不缓冲）：即使中途被杀，stderr 日志也能保住
		#    已算出的点（headless stdout 全缓冲，退出才 flush）。
		push_error("[scan8] ATTRITION=%.2f Aform=%s hit=%s Btotal=%s Btc=%s rateB=%s rateA=%s %s" % [
			float(at), _fmt(r["a_form"]), _fmt(r["hit"], 3), _fmt(r["b_total"]), _fmt(r["b_tc"]),
			_fmt(r["rate"]), _fmt(r["rate_a"]), verdict])
		# 记录满足 V-1′ 全判据的候选（供定稿推荐）
		if r["ok"] and (best.is_empty() or (not best.has("at"))):
			best = {"at": float(at), "r": r}

	print("")
	if best.has("at"):
		print("  ▶ 推荐定稿 ATTRITION（八槽径向 V-1′）= %.2f（首个全判据通过点）" % float(best["at"]))
		print("     A成型=%.3f  命中A=%.3f  B全程=%.3f  B雪崩=%.3f  起飞B=%.3f  起飞A=%.3f  存活B=%.3f" % [
			float(best["r"]["a_form"]), float(best["r"]["hit"]), float(best["r"]["b_total"]),
			float(best["r"]["b_tc"]),
			float(best["r"]["rate"]), float(best["r"]["rate_a"]), float(best["r"]["surv"])])
	else:
		print("  ▶ 无点全通过 V-1′ 判据 —— 需回看判据阈值或八槽暴露度/AGGRO_R（R-R3 缓解方向）")
	print("")

	# 回退 PATH 模式（诊断开关用完复位，避免污染后续测试）
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	quit(0)


# ---------------------------------------------------------------------------
# 单点扫参：同 seed rng 跑 runs 局，累积三阶段新增 Disabled + 起飞
# ---------------------------------------------------------------------------
func _scan_point(attrition: float, runs: int) -> Dictionary:
	# 🔴 八槽 cfg：先取 B 路径定稿 cfg，再改 n_slots=8（n_slots 非冻结项）。
	#    run() 内 geo=null → 走 build_by_slots(cfg.n_slots=8) → Geo8。
	var cfgB := _Cfg.cfg_of("B")
	cfgB["n_slots"] = 8
	# A/B 各用**独立** PyRandom（同 seed 20261002）：金标本 takeoff_rate 是单路径 +
	# rng 跨局连续消费。扫参要同时看两条金标本，若共用一个 rng 会互相污染消费序列。
	var rngB := _PyRandom.new(20261002)
	var rngA := _PyRandom.new(20261002)

	var dis_s1 := 0            # 苟活期 W1–5 累计新增 Disabled（跨所有局）
	var dis_s2 := 0            # 成型期 W6–12
	var dis_s3 := 0            # 雪崩期 W13–20
	var takeoffs := 0
	var survives := 0
	# A 路径（单核金标本）起飞率：塔死亡对两条金标本的冲击都可见。
	var takeoffs_a := 0
	# 🔒 V-1′：A 单核流三阶段塔死累积（机制验收基准 = A 成型期 W6–12）
	var a_dis_s1 := 0          # A 苟活期 W1–5
	var a_dis_s2 := 0          # A 成型期 W6–12（T-A′/T-B′ 判据量）
	var a_dis_s3 := 0          # A 雪崩期 W13–20
	# 🟡 R-2（§4.2）：A 路径 per-run **无条件命中率** hit = #{i : X_form[i] >= 1} / runs
	#    （判据量从「300 局均值」升级为「单局命中率」的候选统计量；本列仅诊断，不入判据）
	var a_hit := 0

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
		# 🔒 V-1′ 关键：A 单核流是机制验收基准，须独立累积其三阶段 dis_new。
		var cxa: Dictionary = _Cfg.cfg_of("A")
		cxa["n_slots"] = 8
		cxa["max_actions"] = 12
		var outa := _RunLoopAggro.run("A", cxa, W_MAX, null, rngA, true, 0.6, attrition, WARMUP)
		var rowsa: Array = outa["rows"]
		var alivea := (not rowsa.is_empty()) and float(rowsa[-1]["core_hp"]) > 0.0
		var twa := -1
		var xa_form := 0       # 本局 A 成型期 X_form（R-2 per-run 命中率分子）
		for r in rowsa:
			if float(r["ratio"]) >= 1.0 and twa < 0:
				twa = int(r["w"])
			# 累积 A 路径各阶段本波新增 Disabled（V-1′ T-A′/T-B′ 以 A 成型期为基准）
			var wn: int = int(r["w"])
			var dn: int = int(r.get("dis_new", 0))
			if wn <= W_SURVIVE_END:
				a_dis_s1 += dn
			elif wn <= W_FORM_END:
				a_dis_s2 += dn
				xa_form += dn
			else:
				a_dis_s3 += dn
		if xa_form >= 1:
			a_hit += 1
		if alivea and twa >= 0:
			takeoffs_a += 1

	# 🔒 V-1′ 判据量：
	#   a_form  = A 成型期 W6–12 平均每局塔死（T-A′ ≥1 可感知 / T-B′ ≤4 不失控）
	#   b_total = B 多塔流全程平均每局塔死（T-D′ =0 须保持免疫）
	#   b_tc    = B 雪崩期 W13–20 平均每局塔死（T-C′ ≈0 机制退场）
	var a_form := float(a_dis_s2) / float(runs)
	var b_total := (float(dis_s1) + float(dis_s2) + float(dis_s3)) / float(runs)
	var b_tc := float(dis_s3) / float(runs)
	return {
		"a_form": a_form,
		"hit": float(a_hit) / float(runs),          # 🟡 R-2：A 单局命中率（诊断列，不入判据）
		"a_surv": float(a_dis_s1) / float(runs),   # A 苟活期（参考，不入判据）
		"a_snow": a_dis_s3 / float(runs),          # A 雪崩期（参考）
		"b_total": b_total,
		"b_tc": b_tc,
		"rate": float(takeoffs) / float(runs),
		"rate_a": float(takeoffs_a) / float(runs),
		"surv": float(survives) / float(runs),
		"ok": _passes(a_form, b_total, b_tc, float(takeoffs) / float(runs)),
	}


## 🔒 V-1′ 判据（八槽径向 · 按路径分列，以 A 单核流为机制验收基准）：
##   T-A′  A 成型期 W6–12 塔死 ≥1（机制对高风险画像可感知）
##   T-B′  A 成型期 W6–12 塔死 ≤4（不失控，A 实测 =4 临界）
##   T-C′  B 雪崩期 W13–20 塔死 ≈0（机制退场，容差 0.5）
##   T-D′  B 多塔流全程塔死 =0（多塔稳健流奖励，须保持免疫）
##   + 起飞率 B ≥0.80（金标本红线不破）
func _passes(a_form: float, b_total: float, b_tc: float, rate: float) -> bool:
	return a_form >= 1.0 and a_form <= 4.0 and b_tc <= 0.5 and b_total <= 0.0 and rate >= 0.80


func _verdict(r: Dictionary) -> String:
	if bool(r["ok"]):
		return "✅ PASS"
	var why: Array = []
	if float(r["a_form"]) < 1.0:
		why.append("T-A′不足(A成型期塔死<1,机制无感)")
	if float(r["a_form"]) > 4.0:
		why.append("T-B′失控(A成型期塔死>4)")
	if float(r["b_tc"]) > 0.5:
		why.append("T-C′未退场(B雪崩期塔死>0.5)")
	if float(r["b_total"]) > 0.0:
		why.append("T-D′破免疫(B多塔流塔死>0)")
	if float(r["rate"]) < 0.80:
		why.append("起飞率破线")
	return "❌ " + "/".join(why)


func _fmt(v: float, nd: int = 3) -> String:
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)
