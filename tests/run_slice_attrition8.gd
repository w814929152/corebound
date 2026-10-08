extends SceneTree
##
## headless 八槽径向 V-1′ 判据验收（`attrition8` 入口）—— 阶段3 T1 数值重扫定稿
##
## 🔴 使命：按 V-1′ 新判据（按路径分列，以 A 单核流为机制验收基准）验收
##    八槽径向下的塔死亡机制，确认 ATTRITION=1.50（六槽定稿值）在径向下仍满足：
##      · T-A′  A 单核流成型期 W6–12 累计塔死 ≥1（机制对高风险画像可感知）
##      · T-B′  A 单核流成型期 W6–12 累计塔死 ≤4（不失控）
##      · T-C′  B 多塔流雪崩期 W13–20 塔死 ≈0（机制自然退场）
##      · T-D′  B 多塔流全程塔死 =0（多塔稳健流奖励，须保持免疫）
##      · 起飞率 B ≥0.80（金标本红线不破）
##
## 依据：`design/gdd/mechanics-tower-life-death.md` §4.2 V-1′ 定稿行（2026-10-08）。
##   旧判据 T-A/T-B/T-C（全场均匀口径）在八槽径向失效（结构性碰撞，非数值失衡）：
##   怪在塔群外被金标本多塔 DPS 全秒，B 路径塔天然免疫。V-1′ 按路径分列修正。
##
## ─────────────────────────────────────────────────────────────────────────────
## 🔴 R-2 per-run 采集（QG-RADIAL-01 · 2026-10-08 · 程基岩）
## ─────────────────────────────────────────────────────────────────────────────
## 依据：`docs/phase3/qg-radial/r2-criteria-revision.md` §4（采集/聚合/输出规格）
##        + §4.3（`dis_new` 语义定稿 · R-T7 结案）。
##
## `dis_new` 是「塔被打停**事件**」的**毛流量**（flow），不是 Disabled 塔数的存量（stock）
##   —— `shop_ai.drop_from()`（`reinf_swap` 换宿主塔）会把 Disabled 塔移出 `player.towers`
##   → 存量降、流量留。🔴 **不要把 `Σ dis_new == towers_disabled` 当断言**（会假 FAIL）。
##   弱不变量（本脚本做 sanity check）：`X_all >= towers_disabled`（流量 ≥ 存量）。
##
## 每局采集字段（§4.1，A/B 两条路径各一份）：
##   X_surv = Σ_{w≤5} dis_new   苟活期
##   X_form = Σ_{6≤w≤12} dis_new 成型期 ← 🔴 **主判据量（整数 · 单位=次/局）**
##   X_snow = Σ_{w≥13} dis_new  雪崩期（A 侧有删失偏倚：失败局 W11 break，无 W13+ 数据）
##   X_all  = X_surv+X_form+X_snow
##   w_end  = rows[-1].w        实际跑到第几波
##   fail   = rows[-1].core_hp <= 0.0   🔴 存活口径（不用 scan 的"存活 AND ratio≥1.0"）
##   reached_w10 = w_end >= 10
##   act13  = w_end>=13 ? rows[12].towers − rows[12].towers_disabled : -1
##
## 聚合输出（§4.2）：hist[0..8]/[9+] · mean/median/p90/max · hit/hit_w10/hit_fail/hit_surv
##                   · tail5 · n_fail · n_reach10 · 各判据裕度 (实测−阈值)/SE
##
## 🔄 **阈值状态（务必读）**：判据**定义**已由文策渊定稿并用户拍板（方案 A · 条件风险惩罚），
##   但**阈值数值**是 `*️⃣` 暂定值，须按 §6「阈值标定纪律」等本脚本实测回填后定档。
##   → 故 T-A′-1 / T-A′-2 / T-B′ 三条在本脚本里**只做 INFO 输出，不计入 `_fail`**
##     （🔴 禁止用未标定阈值当闸门；也禁止把阈值下调到刚好通过）。
##     定档后由文策渊回写为闸门（r2-criteria-revision.md §8-#3）。
##     唯一**已是真闸门**的新判据是 **T-D″ 阳性对照**（阈值 ≥1 已定档，实测 3）。
##
## ⚠️ 输出纪律：本脚本会被 `run_tests.gd -- radial8` 用 OS.execute 拉起，Windows 下
##    GBK 有损解码 → **per-run 段的输出一律 ASCII**（中文会在聚合日志里乱码）。
##    需要中文原文时单独直接跑本脚本即可。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice_attrition8.gd
##

const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_SURV_END := 5        # 苟活期 W1–5
const W_FORM_LO := 6         # 成型期 W6–12（🔴 X_form 窗口，主判据量）
const W_FORM_END := 12
const W_SNOW_LO := 13        # 雪崩期 W13–20
const W_MAX := 20
const WARMUP := 2
const RUNS := 300
const ATTRITION_FINAL := 1.5   # ✅ V-1′ 定稿（六槽值沿用，径向 A 路径下满足）

# R-2 per-run 直方图分箱：0..8 各一格，>=9 合并为 "9+"
const HIST_MAX := 8

# 🔄 R-2 暂定阈值（*️⃣ · r2-criteria-revision.md §5）：
#    **定义已定稿，数值待 per-run 实测回填后按 §6 标定纪律定档**。
#    本脚本只把它们当作「对照打印」的参照线，不参与 _fail（见文件头说明）。
const TH_HIT := 0.15          # T-A′-1 存活性下限
const TH_HIT_FAIL := 0.60     # T-A′-2 失败伴随率
const TH_TAIL5 := 0.05        # T-B′ 尾部控制 P(X_form >= 5)
const GUARD_N_FAIL := 30      # T-A′-2 护栏：n_fail < 30 → INCONCLUSIVE

# T-D″ 阳性对照（🔴 真闸门 · 阈值已定档，非暂定）：PATH 几何八槽 B 单局 Σ dis_new >= 1
const TH_TDD := 1

var _fail = 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("  " + detail) if detail != "" else ""])
	if not cond:
		_fail += 1


func _initialize() -> void:
	print("===================================================================")
	print("径向阶段3 · 八槽 V-1′ 判据验收（ATTRITION=%.2f · 300 局 × A/B）" % ATTRITION_FINAL)
	print("R-2 per-run 采集 · X_form = per-run W6-12 dis_new EVENT COUNT (flow)")
	print("===================================================================")

	# 切径向模式（本验收专用，跑后回退）
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	# ---- 累积 A/B 两路径三阶段塔死 + 起飞 ----
	var rngB := _PyRandom.new(20261002)
	var rngA := _PyRandom.new(20261002)
	var b_dis := [0, 0, 0]       # B 苟活/成型/雪崩
	var a_dis := [0, 0, 0]       # A 苟活/成型/雪崩
	var takeoff_b := 0
	var takeoff_a := 0
	# 🔴 R-2 per-run 记录（§4.1）：每局一条，A/B 各一份，供 §4.2 聚合
	var recs_a: Array = []
	var recs_b: Array = []

	for _i in range(RUNS):
		# B 路径（多塔金标本）
		var cfgB := _Cfg.cfg_of("B")
		cfgB["n_slots"] = 8
		cfgB["max_actions"] = 12
		var out := _RunLoopAggro.run("B", cfgB, W_MAX, null, rngB, true, 0.6, ATTRITION_FINAL, WARMUP)
		_add_dis(out["rows"], b_dis)
		recs_b.append(_collect(out["rows"]))
		if (not out["rows"].is_empty()) and float(out["rows"][-1]["core_hp"]) > 0.0:
			takeoff_b += 1

		# A 路径（单核金标本）
		var cfgA := _Cfg.cfg_of("A")
		cfgA["n_slots"] = 8
		cfgA["max_actions"] = 12
		var outa := _RunLoopAggro.run("A", cfgA, W_MAX, null, rngA, true, 0.6, ATTRITION_FINAL, WARMUP)
		_add_dis(outa["rows"], a_dis)
		recs_a.append(_collect(outa["rows"]))
		if (not outa["rows"].is_empty()) and float(outa["rows"][-1]["core_hp"]) > 0.0:
			takeoff_a += 1

	# 平均每局
	var a_form := float(a_dis[1]) / float(RUNS)   # A 成型期
	var b_total := float(b_dis[0] + b_dis[1] + b_dis[2]) / float(RUNS)
	var b_tc := float(b_dis[2]) / float(RUNS)      # B 雪崩期
	var rate_b := float(takeoff_b) / float(RUNS)
	var rate_a := float(takeoff_a) / float(RUNS)

	print("\n---- 实测（300 局平均）----")
	print("   A 成型期 W6–12 塔死 = %.3f（T-A′ ≥1 / T-B′ ≤4）" % a_form)
	print("   B 全程塔死          = %.3f（T-D′ =0 免疫）" % b_total)
	print("   B 雪崩期 W13–20 塔死 = %.3f（T-C′ ≈0）" % b_tc)
	print("   起飞率 B/A = %.3f / %.3f（B ≥0.80 红线）" % [rate_b, rate_a])

	print("\n---- [T-A′] A 单核流成型期塔死 ≥1（机制可感知）----")
	_ok("T-A′ A 成型期塔死 %.3f ≥ 1.0" % a_form, a_form >= 1.0, "(机制对高风险画像可感知)")

	print("\n---- [T-B′] A 单核流成型期塔死 ≤4（不失控）----")
	_ok("T-B′ A 成型期塔死 %.3f ≤ 4.0" % a_form, a_form <= 4.0, "(不失控)")

	print("\n---- [T-C′] B 多塔流雪崩期塔死 ≈0（机制退场）----")
	_ok("T-C′ B 雪崩期塔死 %.3f ≤ 0.5" % b_tc, b_tc <= 0.5, "(机制自然退场)")

	print("\n---- [T-D′] B 多塔流全程塔死 =0（多塔稳健流免疫）----")
	_ok("T-D′ B 全程塔死 %.3f = 0.0" % b_total, b_total <= 0.0, "(多塔稳健流奖励，保持免疫)")

	print("\n---- [起飞率] B ≥0.80 金标本红线 ----")
	_ok("起飞率 B %.3f ≥ 0.80" % rate_b, rate_b >= 0.80, "(金标本红线不破)")

	# =======================================================================
	# 🔴 R-2 per-run 分布采集（§4.1 / §4.2 / §4.3）
	# =======================================================================
	print("")
	print("===================================================================")
	print("R-2 per-run distribution  X_form = W6-12 dis_new events (N=%d)" % RUNS)
	print("===================================================================")

	var sa := _summarize(recs_a)
	var sb := _summarize(recs_b)

	print("\n---- [A-PATH] X_form per-run dist (N=%d) ----" % RUNS)
	_print_hist(sa)
	_print_stats("A", sa)

	print("\n---- [B-PATH] X_form per-run dist (N=%d · T-D′ baseline) ----" % RUNS)
	_print_hist(sb)
	_print_stats("B", sb)

	# ---- §4.3 弱不变量 sanity check（诊断，非闸门）----
	_check_invariant("A", recs_a)
	_check_invariant("B", recs_b)

	# ---- 判据（暂定阈值 · INFO · 不计入 _fail）----
	print("\n---- [R-2 criteria · PROVISIONAL thresholds · INFO only] ----")
	_print_criteria(sa)

	# ---- 机器可读单行摘要（ASCII · 便于 CI / 人工 grep）----
	print("")
	print("[R2-PERRUN] A N=%d mean=%.3f median=%d p90=%d max=%d hit=%.4f n_hit=%d "
		% [sa["n"], sa["mean"], sa["median"], sa["p90"], sa["max"], sa["hit"], sa["n_hit"]])
	print("[R2-PERRUN] A n_fail=%d hit_fail=%.4f n_fail_hit=%d | n_surv=%d hit_surv=%.4f "
		% [sa["n_fail"], sa["hit_fail"], sa["n_fail_hit"], sa["n_surv"], sa["hit_surv"]])
	print("[R2-PERRUN] A n_reach10=%d hit_w10=%.4f | tail5=%.4f n_tail5=%d"
		% [sa["n_reach10"], sa["hit_w10"], sa["tail5"], sa["n_tail5"]])
	print("[R2-PERRUN] A hist0..8,9+ = %s" % ",".join(_hist_strs(sa)))
	print("[R2-PERRUN] B N=%d mean=%.3f hit=%.4f n_fail=%d hit_fail=%.4f tail5=%.4f hist=%s"
		% [sb["n"], sb["mean"], sb["hit"], sb["n_fail"], sb["hit_fail"], sb["tail5"],
			",".join(_hist_strs(sb))])

	# =======================================================================
	# 🔴 T-D″ 阳性对照（§3.2 · 真闸门 · 阈值 >=1 已定档）
	#    同数值只把几何切成 PATH 跑八槽 B 单局 → 塔死亡**机制本身**必须可见。
	#    （ATTRITION 不是能打破 B 免疫的杠杆：探针已证 33× 下径向 B 仍 dis_new=0）
	# =======================================================================
	print("\n---- [T-D″] positive control: PATH geometry · B path · 8 slots · 1 run ----")
	var tdd_dis := _run_tdd_control()
	print("   PATH 几何 B 全程 dis_new = %d" % tdd_dis)
	if tdd_dis == TH_TDD:
		print("   [WARN] T-D″ margin = 0 (measured == threshold) -- positive control is brittle")
	_ok("T-DD positive control: PATH-geometry B whole-run dis_new %d >= %d" % [tdd_dis, TH_TDD],
		tdd_dis >= TH_TDD, "(tower-death mechanism itself alive, not immunity)")

	# 回退 PATH 模式
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	# ---- 附录：每局原始三元组（§4.3 · 供人工/离线复核）----
	_dump_per_run("A", recs_a)
	_dump_per_run("B", recs_b)

	print("\n===================================================================")
	print("八槽径向 V-1′ 判据验收汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)


## 把一行 rows 的三阶段 dis_new 累加进 dis[3]（Array 传引用，直接 mutate）
func _add_dis(rows: Array, dis: Array) -> void:
	for r in rows:
		var wn: int = int(r["w"])
		var dn: int = int(r.get("dis_new", 0))
		if wn <= W_SURV_END:
			dis[0] = int(dis[0]) + dn
		elif wn <= W_FORM_END:
			dis[1] = int(dis[1]) + dn
		else:
			dis[2] = int(dis[2]) + dn


# ─────────────────────────────────────────────────────────────────────────────
# R-2 per-run 采集 / 聚合（§4.1 / §4.2）
# ─────────────────────────────────────────────────────────────────────────────

## 单局 → 一条 per-run 记录（§4.1 字段表）
func _collect(rows: Array) -> Dictionary:
	var xs := 0
	var xf := 0
	var xn := 0
	for r in rows:
		var wn: int = int(r["w"])
		var dn: int = int(r.get("dis_new", 0))
		if wn <= W_SURV_END:
			xs += dn
		elif wn <= W_FORM_END:
			xf += dn
		else:
			xn += dn

	var w_end := 0
	var core_hp := -1.0
	var stock := 0
	var towers := 0
	if not rows.is_empty():
		var last: Dictionary = rows[-1]
		w_end = int(last["w"])
		core_hp = float(last["core_hp"])
		stock = int(last.get("towers_disabled", 0))
		towers = int(last.get("towers", 0))

	# act13：W13 时仍存活的塔数（供 T-C′ 分层诊断；未跑到 W13 记 -1）
	var act13 := -1
	if w_end >= W_SNOW_LO and rows.size() >= W_SNOW_LO:
		var r13: Dictionary = rows[W_SNOW_LO - 1]
		act13 = int(r13.get("towers", 0)) - int(r13.get("towers_disabled", 0))

	return {
		"xs": xs,
		"xf": xf,
		"xn": xn,
		"xa": xs + xf + xn,
		"w_end": w_end,
		"fail": core_hp <= 0.0,
		"reached_w10": w_end >= 10,
		"act13": act13,
		"stock": stock,
		"towers": towers,
		"core_hp": core_hp,
	}


## 聚合（§4.2）
func _summarize(recs: Array) -> Dictionary:
	var n := recs.size()
	var hist: Array = []
	for _k in range(HIST_MAX + 2):
		hist.append(0)

	var xs: Array = []
	var tot := 0
	var n_hit := 0
	var n_hit_w10 := 0
	var n_fail := 0
	var n_fail_hit := 0
	var n_surv := 0
	var n_surv_hit := 0
	var n_reach10 := 0
	var n_tail5 := 0

	for r in recs:
		var x: int = int(r["xf"])
		xs.append(x)
		tot += x
		var k: int = x if x <= HIST_MAX else HIST_MAX + 1
		hist[k] = int(hist[k]) + 1
		var is_fail := bool(r["fail"])
		var reached := bool(r["reached_w10"])
		if x >= 1:
			n_hit += 1
			if reached:
				n_hit_w10 += 1
			if is_fail:
				n_fail_hit += 1
			else:
				n_surv_hit += 1
		if x >= 5:
			n_tail5 += 1
		if is_fail:
			n_fail += 1
		else:
			n_surv += 1
		if reached:
			n_reach10 += 1

	xs.sort()
	var median := 0
	var p90 := 0
	var mx := 0
	if n > 0:
		median = int(xs[n / 2])
		var i90: int = clampi(int(ceil(0.9 * float(n))) - 1, 0, n - 1)
		p90 = int(xs[i90])
		mx = int(xs[n - 1])

	return {
		"n": n,
		"hist": hist,
		"mean": (float(tot) / float(n)) if n > 0 else 0.0,
		"median": median,
		"p90": p90,
		"max": mx,
		"sum": tot,
		"n_hit": n_hit,
		"hit": (float(n_hit) / float(n)) if n > 0 else 0.0,
		"n_reach10": n_reach10,
		"n_hit_w10": n_hit_w10,
		"hit_w10": (float(n_hit_w10) / float(n_reach10)) if n_reach10 > 0 else 0.0,
		"n_fail": n_fail,
		"n_fail_hit": n_fail_hit,
		"hit_fail": (float(n_fail_hit) / float(n_fail)) if n_fail > 0 else 0.0,
		"n_surv": n_surv,
		"n_surv_hit": n_surv_hit,
		"hit_surv": (float(n_surv_hit) / float(n_surv)) if n_surv > 0 else 0.0,
		"n_tail5": n_tail5,
		"tail5": (float(n_tail5) / float(n)) if n > 0 else 0.0,
	}


## 比例型统计量的标准误 SE = sqrt(p(1-p)/n)
func _se(p: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return sqrt(maxf(0.0, p * (1.0 - p)) / float(n))


func _hist_strs(s: Dictionary) -> Array:
	var out: Array = []
	for v in s["hist"]:
		out.append(str(int(v)))
	return out


func _print_hist(s: Dictionary) -> void:
	var hist: Array = s["hist"]
	var peak := 1
	for v in hist:
		peak = maxi(peak, int(v))
	for k in range(HIST_MAX + 2):
		var cnt: int = int(hist[k])
		var label := str(k) if k <= HIST_MAX else "9+"
		var bars := int(float(cnt) / float(peak) * 40.0)
		print("  hist[%3s] (%4d) %s" % [label, cnt, "#".repeat(bars)])


func _print_stats(tag: String, s: Dictionary) -> void:
	print("  mean=%.3f  median=%d  p90=%d  max=%d  sum=%d" % [
		float(s["mean"]), int(s["median"]), int(s["p90"]), int(s["max"]), int(s["sum"])])
	print("  hit     =%.4f  (%3d/%3d)   SE=%.4f" % [
		float(s["hit"]), int(s["n_hit"]), int(s["n"]), _se(float(s["hit"]), int(s["n"]))])
	print("  hit_w10 =%.4f  (%3d/%3d)   n_reach10=%d" % [
		float(s["hit_w10"]), int(s["n_hit_w10"]), int(s["n_reach10"]), int(s["n_reach10"])])
	print("  hit_fail=%.4f  (%3d/%3d)   n_fail=%d  SE=%.4f" % [
		float(s["hit_fail"]), int(s["n_fail_hit"]), int(s["n_fail"]), int(s["n_fail"]),
		_se(float(s["hit_fail"]), int(s["n_fail"]))])
	print("  hit_surv=%.4f  (%3d/%3d)   n_surv=%d" % [
		float(s["hit_surv"]), int(s["n_surv_hit"]), int(s["n_surv"]), int(s["n_surv"])])
	print("  tail5(>=5)=%.4f  (%3d/%3d)" % [
		float(s["tail5"]), int(s["n_tail5"]), int(s["n"])])


## §4.3 弱不变量（诊断，非闸门）：X_all >= towers_disabled（流量 ≥ 存量）
## 🔴 不要断言 X_all == towers_disabled —— 有 reinf_swap 的局会假 FAIL。
func _check_invariant(tag: String, recs: Array) -> void:
	var bad_flow := 0
	var bad_stock := 0
	var drift_total := 0
	for r in recs:
		var xa: int = int(r["xa"])
		var stock: int = int(r["stock"])
		var towers: int = int(r["towers"])
		if xa < stock:
			bad_flow += 1
		if stock > towers:
			bad_stock += 1
		drift_total += xa - stock
	print("  [%s] sanity: X_all>=stock violated in %d/%d runs · stock>towers in %d · "
		% [tag, bad_flow, recs.size(), bad_stock]
		+ "total drift (flow-stock)=%d" % drift_total)


## 判据打印（🔄 暂定阈值 · INFO · 不计入 _fail）
## 裕度按 §6-④：打印 (实测 − 阈值)/SE，让脆弱性可见。
func _print_criteria(s: Dictionary) -> void:
	var hit: float = float(s["hit"])
	var se_hit := _se(hit, int(s["n"]))
	var m_hit := (hit - TH_HIT) / se_hit if se_hit > 0.0 else 0.0
	print("  [INFO] T-A1  hit      %.4f  vs TH %.2f  -> margin %+.2f SE  (n=%d)"
		% [hit, TH_HIT, m_hit, int(s["n"])])

	var n_fail: int = int(s["n_fail"])
	if n_fail < GUARD_N_FAIL:
		print("  [SKIP] T-A2  INCONCLUSIVE: n_fail=%d < guard %d (no PASS/FAIL)"
			% [n_fail, GUARD_N_FAIL])
	else:
		var hf: float = float(s["hit_fail"])
		var se_hf := _se(hf, n_fail)
		var m_hf := (hf - TH_HIT_FAIL) / se_hf if se_hf > 0.0 else 0.0
		print("  [INFO] T-A2  hit_fail %.4f  vs TH %.2f  -> margin %+.2f SE  (n_fail=%d)"
			% [hf, TH_HIT_FAIL, m_hf, n_fail])

	var t5: float = float(s["tail5"])
	var se_t5 := _se(t5, int(s["n"]))
	# T-B′ 是上界判据：裕度 = (阈值 − 实测)/SE（实测越小越安全）
	var m_t5 := (TH_TAIL5 - t5) / se_t5 if se_t5 > 0.0 else 0.0
	print("  [INFO] T-B   tail5    %.4f  vs TH %.2f  -> margin %+.2f SE  (n=%d)"
		% [t5, TH_TAIL5, m_t5, int(s["n"])])
	print("  [INFO] ^ provisional thresholds (r2-criteria-revision.md §5 *️⃣) -- "
		+ "NOT gated, pending calibration by design-strategist")


## 🔴 T-D″ 阳性对照：同数值（ATTRITION=1.50 / HP0=120 / h^0.6 / AGGRO_R=9.0 / WARMUP=2
##    / seed 20261002 / n_slots=8 / B 路径）**只把 SpaceModel.mode 切成 PATH**，
##    跑一局，返回全程 Σ dis_new。实测 = 3（3× margin vs 阈值 1）。
func _run_tdd_control() -> int:
	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	var cfg: Dictionary = _Cfg.cfg_of("B")
	cfg["n_slots"] = 8
	cfg["max_actions"] = 12
	var rng := _PyRandom.new(20261002)
	var out := _RunLoopAggro.run("B", cfg, W_MAX, null, rng, true, 0.6, ATTRITION_FINAL, WARMUP)
	var rows: Array = out["rows"]
	var tot := 0
	var per_w: Array = []
	for r in rows:
		var dn: int = int(r.get("dis_new", 0))
		tot += dn
		per_w.append("%d:%d" % [int(r["w"]), dn])
	print("   per-wave dis_new = [%s]" % ",".join(per_w))
	print("   last core_hp=%.1f · towers=%d · towers_disabled=%d" % [
		float(rows[-1]["core_hp"]) if not rows.is_empty() else -1.0,
		int(rows[-1].get("towers", 0)) if not rows.is_empty() else -1,
		int(rows[-1].get("towers_disabled", 0)) if not rows.is_empty() else -1])
	_SpaceModel.mode = prev_mode
	return tot


## 附录：每局原始三元组（§4.3）
func _dump_per_run(tag: String, recs: Array) -> void:
	print("\n---- [per-run raw] %s · X_all / X_form / stock / towers / w_end / fail ----" % tag)
	for i in range(recs.size()):
		var r: Dictionary = recs[i]
		print("  [%s] i=%3d X_all=%2d X_form=%2d X_surv=%2d X_snow=%2d stock=%2d towers=%2d "
			% [tag, i, int(r["xa"]), int(r["xf"]), int(r["xs"]), int(r["xn"]),
				int(r["stock"]), int(r["towers"])]
			+ "w_end=%2d fail=%d act13=%2d" % [int(r["w_end"]), 1 if bool(r["fail"]) else 0,
				int(r["act13"])])
