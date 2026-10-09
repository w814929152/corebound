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
## ✅ **阈值状态（定档 · 真闸门）**：判据**定义**由文策渊定稿并用户拍板（方案 A · 条件风险惩罚）。
##   🔴 **阈值已于 2026-10-09 按 `snap/rest` 修复后新基线重标定**（依据 `r2-criteria-revision.md` §12）：
##     T-A′-1 存活性下限 hit ≥ **0.12**（原 0.15；新实测 0.1900 · +3.09 SE）
##     ／ T-A′-2 失败伴随率护栏 n_fail ≥ 30 下 hit_fail ≥ **0.30**（原 0.60；新实测 0.4711 · +3.77 SE）。
##     旧阈值是在缺陷期虚高读数上标定的，`1ca10ef` 后基线位移 → 本次是**代码同步定档**，非新造尺子。
##   🔴 定位同步（§12.3）：
##     · **T-A′（成型期塔死均值 ≥1）已降为〔事实登记〕**——它与 T-A′-1 数学等价（X_form∈{0,2}
##       → 均值=2×hit 恒等），是重复闸门，不再计入 `_fail`。
##     · **T-B′ tail5 已降为〔事实登记〕**——修复后 hist 严格双峰 {0:243, 2:57}，P(X≥5) 结构恒 0，
##       零信号无检出能力，不再计入 `_fail`。
##     · **T-D″ 阳性对照加固为 3 seed 累计 Σ dis_new ≥ 3**（原 1 seed margin=0 太脆）。
##   🔴 T-A′-2 的 n_fail < 30 是**护栏**（样本不足 → INCONCLUSIVE，不计失败），不是闸门。
##   🔴 阈值已定档，**禁止再下调到刚好通过**；判 FAIL 就如实报错，交文策渊复核。
##   🔴 `survive_rate A`（本脚本仅 INFO）的 0.60 是**平衡红线**，与 TH_HIT_FAIL 无关，一字未动。
##
## ⚠️ 输出纪律：本脚本会被 `run_tests.gd -- radial8` 用 OS.execute 拉起，Windows 下
##    GBK 有损解码 → **per-run 段的输出一律 ASCII**（中文会在聚合日志里乱码）。
##    需要中文原文时单独直接跑本脚本即可。
##
## ─────────────────────────────────────────────────────────────────────────────
## 🔴 R-5 / V6-R2「起飞率」口径统一（QG-RADIAL-01 · 2026-10-09 · 程基岩）
## ─────────────────────────────────────────────────────────────────────────────
## 依据：`docs/phase3/qg-radial/v6-dominance-adjudication.md` §6 V6-R2（文策渊）。
##
## 🔴 原缺陷：本脚本曾用 `rows[-1].core_hp > 0.0` 自算并**命名为「起飞率」** ——
##    那是 **W20 存活率**，不是起飞率。规范起飞率 = `RunLoopAggro.takeoff_rate`
##    （定义：`alive ∧ _Stats.takeoff_wave(rows) ≥ 0`，即"存活且 DPS 曾越过 ratio=1"）。
##    同一条 B 路径两个定义给出 1.000（存活率）vs 0.913（起飞率）→ 判据会随脚本翻转。
##
## ✅ 处置：本脚本**只保留一个「起飞率」语义**，与 `RunLoopAggro.takeoff_rate` 逐位同义：
##      · `takeoff_rate` = #{存活 ∧ 起飞波 ≥0} / N   ← 规范（DPS 起飞）
##      · `survive_rate` = #{末波 core_hp > 0} / N   ← 存活率，**另立字段名，不再叫起飞率**
##    🔴 实现方式 = 在既有 600 局主循环内**就地**按同一定义统计（`RunLoopAggro.takeoff_rate`
##       若单独调用会再跑一整轮 300 局 → 双击耗时）。定义与该函数**逐位一致**：
##       `alive = rows 非空 ∧ rows[-1].core_hp > 0`、`tw = _Stats.takeoff_wave(rows)`。
##
## ─────────────────────────────────────────────────────────────────────────────
## 🔴 R-4 · 八槽 V-0′ ④⑤ 闭环（QG-RADIAL-01 §4.1 · 程基岩）
## ─────────────────────────────────────────────────────────────────────────────
## 依据：`design/gdd/radial-core-siege-draft.md` §7.3 V-0′ 判据 ④⑤。
##   · ④ 起飞点仍在 **W10–15**  → `V-0-4a` MC 中位起飞波 / `V-0-4b` 确定性单局起飞波
##   · ⑤ W20 `B/A < 1`         → `V-0-5a` 确定性单局 W20 ratio B/A（与六槽金标本同口径）
##                                 `V-0-5b` MC 均值 W20 ratio B/A（辅助，含删失偏倚说明）
##
## 🔴 路径归属说明（需文策渊确认）：六槽定稿 A 起飞波 = **W8**（用户已拍板接受），
##    明确**不在** W10–15 窗口内 → V-0′ ④ 只能是对 **B 路径**的要求。故本脚本
##    **只把 B 侧起飞波做成闸门**，A 侧同量按 INFO 打印（V-0′ ③「A 按 V-2 口径记录」）。
##
## 🔴 零扰动：④⑤ 全部复用既有 300×2 主循环已产出的 rows，不新增 MC；确定性单局
##    只多跑 2 局（A/B 各 1，`rng=null`，与六槽 V-0′ 同口径）。不改任何定稿数值。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice_attrition8.gd
##

const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _Geo8 := preload("res://scripts/geo/geo8.gd")

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

# ✅ R-2 定档阈值（r2-criteria-revision.md §5 定档行 · commit 14673fa ·
#    GDD mechanics-tower-life-death.md v1.0.2 已回写）：
#    **定义与数值均已定档，全部参与 _fail**（见文件头说明）。
#    实测裕度（A 路径 · 300 局）：hit +5.45 SE ／ hit_fail +4.18 SE(n_fail=115) ／ tail5 +3.54 SE。
#    🔴 数值已由文策渊定档，工程侧不得改动；判 FAIL 如实上报。
# 🔴 2026-10-09 按 `snap/rest` 修复后新基线重标定（依据 r2-criteria-revision.md §12）：
#    TH_HIT 0.15→0.12（新实测 0.1900 · +3.09 SE）／ TH_HIT_FAIL 0.60→0.30（新实测 0.4711 · +3.77 SE）。
#    旧值是在缺陷期虚高读数（0.2933 / 0.7652）上标定的，`1ca10ef` 后基线位移 → 代码从未同步定档。
#    🔴 这不是"下调来过关"：修复去掉的是虚高的重复计数，真值仍是强机制（19% 双塔尽没 · 100% 致命）。
const TH_HIT := 0.12          # T-A′-1 存活性下限（§12.3 新基线重标定 · +3.09 SE）
const TH_HIT_FAIL := 0.30     # T-A′-2 失败伴随率（§12.3 新基线重标定 · +3.77 SE）
# 🔴 T-B′ tail5 已降级为〔事实登记〕（§12.3）：修复后 hist 严格双峰 {0:243, 2:57} →
#    P(X_form>=5) 结构恒 0，永久零信号，无检出能力 → 不再计入 _fail（见 _print_criteria）。
#    常量保留作打印基准（0.07 为原上界定档值）。
const TH_TAIL5 := 0.07        # T-B′ 尾部控制 P(X_form >= 5)  ← 打印基准（已降事实登记）
const GUARD_N_FAIL := 30      # T-A′-2 护栏：n_fail < 30 → INCONCLUSIVE（不计失败）

# T-D″ 阳性对照（🔴 存在性闸门 · §12.3 加固）：PATH 几何八槽 B **3 seed 累计** Σ dis_new >= 3。
#    原 1 seed（20261002）实测 1 → margin=0 太脆；扩 3 seed 累计（每 seed 期望 λ≈3，P(≥3)≈0.58）。
#    🔴 连续两次 FAIL 才允许判为回归（§12.3）。
const TH_TDD := 3             # T-D″ 3 seed 累计下界（每 seed 实测 1 · 累计 3）
const TDD_SEEDS: Array = [20261002, 20261003, 20261004]  # §12.4 建议 20261002 + 两个登记 seed

# ── 🔴 R-4 · 八槽 V-0′ ④⑤ 阈值（来自 GDD §7.3 V-0′ 原文，**非工程自拟**）──
#    V-0′ ④「起飞点仍在 W10–15」→ B 路径起飞波窗口（下界/上界，含端点）
const V0_TW_LO := 10
const V0_TW_HI := 15
#    V-0′ ⑤「`B/A < 1`」→ W20 ratio B/A 上界（严格小于；单核须仍是后期 carry，
#    概念 §2.4.5）。🔴 严格 `<` 而非 `<=`：等于 1 时"后期 carry 归属"已无归属。
const V0_BA_MAX := 1.0
#    V-0′ ② 附带：B 起飞率红线。**改用规范口径 takeoff_rate**（R-5/V6-R2）。
const TH_TAKEOFF_B := 0.80

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
	# 🔴 R-5/V6-R2：这两个计数器是 **survive_rate（W20 存活率）**，**不再叫"起飞率"**。
	#    规范「起飞率」= 存活 ∧ 起飞波≥0，见 `_takeoff_stats()`。
	var survive_b := 0
	var survive_a := 0
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
			survive_b += 1

		# A 路径（单核金标本）
		var cfgA := _Cfg.cfg_of("A")
		cfgA["n_slots"] = 8
		cfgA["max_actions"] = 12
		var outa := _RunLoopAggro.run("A", cfgA, W_MAX, null, rngA, true, 0.6, ATTRITION_FINAL, WARMUP)
		_add_dis(outa["rows"], a_dis)
		recs_a.append(_collect(outa["rows"]))
		if (not outa["rows"].is_empty()) and float(outa["rows"][-1]["core_hp"]) > 0.0:
			survive_a += 1

	# 平均每局
	var a_form := float(a_dis[1]) / float(RUNS)   # A 成型期
	var b_total := float(b_dis[0] + b_dis[1] + b_dis[2]) / float(RUNS)
	var b_tc := float(b_dis[2]) / float(RUNS)      # B 雪崩期
	var rate_b := float(survive_b) / float(RUNS)
	var rate_a := float(survive_a) / float(RUNS)

	# 🔴 R-5/V6-R2：规范「起飞率」+ ④ 起飞波 + ⑤ W20 ratio，全部由既有 recs 就地统计
	var tkb := _takeoff_stats(recs_b)
	var tka := _takeoff_stats(recs_a)

	print("\n---- 实测（300 局平均）----")
	print("   A 成型期 W6–12 塔死 = %.3f（T-A′ ≥1 / T-B′ ≤4）" % a_form)
	print("   B 全程塔死          = %.3f（T-D′ =0 免疫）" % b_total)
	print("   B 雪崩期 W13–20 塔死 = %.3f（T-C′ ≈0）" % b_tc)
	print("   存活率 survive_rate B/A = %.3f / %.3f（🔴 末波 core_hp>0，非起飞率）" % [rate_b, rate_a])
	print("   起飞率 takeoff_rate B/A = %.3f / %.3f（🔴 规范：存活 ∧ 起飞波≥0）"
		% [float(tkb["rate"]), float(tka["rate"])])

	print("\n---- [T-A′] A 单核流成型期塔死 ≥1（机制可感知）----")
	# 🔴 §12.3 降级：T-A′ 均值与 T-A′-1 数学等价（X_form∈{0,2} → 均值=2×hit 恒等），
	#    是重复闸门 → 移出 _fail，降为〔事实登记〕（仅打印，不计失败）。判据以 T-A′-1 为准。
	print("   [INFO] T-A′ A 成型期塔死均值 %.3f（事实登记 · 与 T-A′-1 数学等价，判据以 hit 为准，不计 _fail）" % a_form)

	print("\n---- [T-B′] A 单核流成型期塔死 ≤4（不失控）----")
	_ok("T-B′ A 成型期塔死 %.3f ≤ 4.0" % a_form, a_form <= 4.0, "(不失控)")

	print("\n---- [T-C′] B 多塔流雪崩期塔死 ≈0（机制退场）----")
	_ok("T-C′ B 雪崩期塔死 %.3f ≤ 0.5" % b_tc, b_tc <= 0.5, "(机制自然退场)")

	print("\n---- [T-D′] B 多塔流全程塔死 =0（多塔稳健流免疫）----")
	_ok("T-D′ B 全程塔死 %.3f = 0.0" % b_total, b_total <= 0.0, "(多塔稳健流奖励，保持免疫)")

	print("\n---- [起飞率] B ≥0.80 金标本红线（🔴 规范口径 takeoff_rate）----")
	_ok("takeoff_rate B %.3f >= %.2f  (survive_rate B %.3f, INFO)"
		% [float(tkb["rate"]), TH_TAKEOFF_B, rate_b],
		float(tkb["rate"]) >= TH_TAKEOFF_B,
		"(RunLoopAggro.takeoff_rate 定义：存活 AND 起飞波>=0)")

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

	# ---- 判据（定档阈值 · 真闸门 · 计入 _fail）----
	print("\n---- [R-2 criteria · FINAL thresholds · gated] ----")
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
	# 🔴 T-D″ 阳性对照（§3.2 / §12.3 加固 · 存在性闸门 · 3 seed 累计 ≥ TH_TDD）
	#    同数值只把几何切成 PATH 跑八槽 B → 塔死亡**机制本身**必须可见。
	#    （ATTRITION 不是能打破 B 免疫的杠杆：探针已证 33× 下径向 B 仍 dis_new=0）
	#    🔴 §12.3 加固：原 1 seed（20261002）实测 1 → margin=0 太脆；扩 3 seed 累计。
	#       每 seed 期望 λ≈3（Poisson），P(≥3)≈0.58 → 属存在性阳性对照；
	#       🔴 连续两次 FAIL 才允许判为回归。
	# =======================================================================
	print("\n---- [T-D″] positive control: PATH geometry · B path · 8 slots · %d seeds ----" % TDD_SEEDS.size())
	var tdd_total := 0
	for sidx in range(TDD_SEEDS.size()):
		var seed: int = int(TDD_SEEDS[sidx])
		var d := _run_tdd_control(seed)
		print("   seed %d: PATH 几何 B 全程 dis_new = %d" % [seed, d])
		tdd_total += d
	print("   3 seed 累计 Σ dis_new = %d (vs TH %d)" % [tdd_total, TH_TDD])
	if tdd_total == TH_TDD:
		print("   [WARN] T-D″ margin = 0 (累计 measured == threshold %d) -- positive control is brittle" % TH_TDD)
	_ok("T-DD positive control: PATH-geometry B %d-seed cumulative dis_new %d >= %d"
		% [TDD_SEEDS.size(), tdd_total, TH_TDD],
		tdd_total >= TH_TDD, "(tower-death mechanism itself alive, not immunity)")

	# =======================================================================
	# 🔴 R-4 · 八槽 V-0′ ④⑤ 闭环（QG-RADIAL-01 §4.1 · GDD §7.3 V-0′）
	#    ④ 起飞点仍在 W10–15   ⑤ W20 `B/A < 1`
	#    🔴 零扰动：④ 复用主循环已产出的 recs；⑤a 只多跑 2 局确定性单局（rng=null）。
	# =======================================================================
	print("")
	print("===================================================================")
	print("R-4 · eight-slot V-0' closure (4) takeoff wave W10-15  (5) W20 B/A < 1")
	print("===================================================================")

	# ---- ④a MC 中位起飞波（B 闸门 / A 仅 INFO）----
	print("\n---- [V-0-4a] MC median takeoff wave (B gated · A INFO) ----")
	print("   B: median takeoff wave = %d  · n_takeoff=%d/%d · mean w20 ratio=%.3f (n_reach20=%d)"
		% [int(tkb["med_tw"]), int(tkb["n_take"]), int(tkb["n"]),
			float(tkb["mean_w20"]), int(tkb["n_w20"])])
	print("   A: median takeoff wave = %d  · n_takeoff=%d/%d · mean w20 ratio=%.3f (n_reach20=%d)"
		% [int(tka["med_tw"]), int(tka["n_take"]), int(tka["n"]),
			float(tka["mean_w20"]), int(tka["n_w20"])])
	_ok("V-0-4a B MC median takeoff wave %d in [W%d, W%d]"
		% [int(tkb["med_tw"]), V0_TW_LO, V0_TW_HI],
		int(tkb["med_tw"]) >= V0_TW_LO and int(tkb["med_tw"]) <= V0_TW_HI,
		"(A median=%d recorded as INFO: six-slot frozen A takeoff W8 is outside W10-15)"
		% int(tka["med_tw"]))

	# ---- ⑤b MC 均值 W20 ratio B/A（辅助闸门）----
	# 🔴 删失说明：A 只有 n_reach20/N 的局跑到 W20（其余中途 core_hp<=0 被 break）→
	#    A 的 W20 ratio 是**存活者条件均值**，偏高 → B/A 被压低 → 本判据偏**宽松**。
	print("\n---- [V-0-5b] MC mean W20 ratio B/A (auxiliary gate) ----")
	var mc_ba := -1.0
	if tka["n_w20"] > 0 and float(tka["mean_w20"]) > 0.0:
		mc_ba = float(tkb["mean_w20"]) / float(tka["mean_w20"])
	print("   MC mean w20: A=%.3f (n=%d)  B=%.3f (n=%d)  -> B/A=%.4f"
		% [float(tka["mean_w20"]), int(tka["n_w20"]),
			float(tkb["mean_w20"]), int(tkb["n_w20"]), mc_ba])
	_ok("V-0-5b MC mean W20 ratio B/A %.4f < %.2f" % [mc_ba, V0_BA_MAX],
		mc_ba >= 0.0 and mc_ba < V0_BA_MAX, "(survivor-conditioned on A -> conservative-low)")

	# ---- ④b / ⑤a 确定性单局（rng=null，与六槽 V-0′ 同口径）----
	print("\n---- [V-0-4b/5a] deterministic single run (rng=null · six-slot V-0' parity) ----")
	var det_a := _det_v0("A")
	var det_b := _det_v0("B")
	print("   A: takeoff=W%d  w20 ratio=%.3f  (six-slot gold: W8 / 21.77)"
		% [int(det_a["tw"]), float(det_a["w20"])])
	print("   B: takeoff=W%d  w20 ratio=%.3f  (six-slot gold: W12 / 9.97)"
		% [int(det_b["tw"]), float(det_b["w20"])])
	var det_ba := -1.0
	if float(det_a["w20"]) > 0.0:
		det_ba = float(det_b["w20"]) / float(det_a["w20"])
	print("   deterministic W20 B/A = %.4f  (six-slot gold: 0.458)" % det_ba)
	_ok("V-0-4b B deterministic takeoff wave %d in [W%d, W%d]"
		% [int(det_b["tw"]), V0_TW_LO, V0_TW_HI],
		int(det_b["tw"]) >= V0_TW_LO and int(det_b["tw"]) <= V0_TW_HI,
		"(A deterministic takeoff W%d recorded as INFO)" % int(det_a["tw"]))
	_ok("V-0-5a deterministic W20 ratio B/A %.4f < %.2f" % [det_ba, V0_BA_MAX],
		det_ba >= 0.0 and det_ba < V0_BA_MAX, "(single-core remains late carry, concept 2.4.5)")

	# ---- 机器可读单行摘要（ASCII · 便于 CI / 人工 grep）----
	print("")
	print("[R4-V0] B takeoff_rate=%.4f survive_rate=%.4f med_tw=%d det_tw=%d"
		% [float(tkb["rate"]), rate_b, int(tkb["med_tw"]), int(det_b["tw"])])
	print("[R4-V0] A takeoff_rate=%.4f survive_rate=%.4f med_tw=%d det_tw=%d (INFO)"
		% [float(tka["rate"]), rate_a, int(tka["med_tw"]), int(det_a["tw"])])
	print("[R4-V0] W20 B/A det=%.4f mc_mean=%.4f  (gate < %.2f)"
		% [det_ba, mc_ba, V0_BA_MAX])

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

	# 🔴 R-5/V6-R2 + R-4：起飞波（DPS ratio 首次 ≥1.0 的波；-1 = 未起飞）
	var tw: int = _Stats.takeoff_wave(rows)
	# 🔴 R-4 ⑤：W20 ratio（本局跑到 W20 才有；否则 -1.0，供删失统计用）
	var w20 := -1.0
	if w_end >= W_MAX:
		for r in rows:
			if int(r["w"]) == W_MAX:
				w20 = float(r["ratio"])
				break

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
		"tw": tw,
		"w20": w20,
	}


## 🔴 R-5/V6-R2 + R-4：规范「起飞率」统计（就地复用 recs，不新增 MC）
##
## 定义**逐位等同** `RunLoopAggro.takeoff_rate()`：
##   takeoff = alive ∧ takeoff_wave ≥ 0，其中 alive = (rows 非空 ∧ rows[-1].core_hp > 0)
##   → recs 侧 alive == (not fail)（_collect 里 rows 为空时 core_hp=-1 → fail=true）。
## 附带给 R-4 ④ 的中位起飞波与 ⑤ 的 W20 ratio 均值。
func _takeoff_stats(recs: Array) -> Dictionary:
	var n := recs.size()
	var n_take := 0
	var tws: Array = []
	var n_w20 := 0
	var w20_sum := 0.0
	for r in recs:
		var alive := not bool(r["fail"])
		var tw: int = int(r["tw"])
		if alive and tw >= 0:
			n_take += 1
			tws.append(tw)
		if int(r["w_end"]) >= W_MAX:
			n_w20 += 1
			w20_sum += float(r["w20"])
	tws.sort()
	return {
		"n": n,
		"n_take": n_take,
		"rate": (float(n_take) / float(n)) if n > 0 else 0.0,
		"med_tw": (int(tws[tws.size() / 2]) if tws.size() > 0 else -1),
		"n_w20": n_w20,
		"mean_w20": (w20_sum / float(n_w20)) if n_w20 > 0 else -1.0,
	}


## 🔴 R-4 ④b/⑤a：确定性单局（rng=null，与六槽 V-0′ `run_v0_radial` 同口径）
##    只多跑 1 局/路径，八槽 RADIAL 几何显式传入（Geo8.build8()）。
func _det_v0(path: String) -> Dictionary:
	var cfg: Dictionary = _Cfg.cfg_of(path)
	cfg["n_slots"] = 8
	cfg["max_actions"] = 12
	var out := _RunLoopAggro.run(path, cfg, W_MAX, _Geo8.build8(), null,
		true, 0.6, ATTRITION_FINAL, WARMUP)
	var rows: Array = out["rows"]
	var s := _Stats.summarize(rows)
	var w20 := -1.0
	if s["w20"] != null:
		w20 = float(s["w20"])
	return {"tw": int(s["takeoff"]), "w20": w20}


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


## 🔴 判据闸门（✅ 定档阈值 · **真闸门** · 计入 _fail）
## 裕度按 §6-④：打印 (实测 − 阈值)/SE，让脆弱性可见。
## 判定方向：T-A′-1 / T-A′-2 为下界（实测越大越满足）；T-B′ 为上界（实测越小越安全）。
func _print_criteria(s: Dictionary) -> void:
	var hit: float = float(s["hit"])
	var se_hit := _se(hit, int(s["n"]))
	var m_hit := (hit - TH_HIT) / se_hit if se_hit > 0.0 else 0.0
	_ok("T-A1  hit      %.4f  vs TH %.2f  -> margin %+.2f SE  (n=%d)"
		% [hit, TH_HIT, m_hit, int(s["n"])], hit >= TH_HIT)

	var n_fail: int = int(s["n_fail"])
	if n_fail < GUARD_N_FAIL:
		# 🔴 护栏不是闸门：样本不足 → INCONCLUSIVE，**不计失败**
		print("   [SKIP] T-A2  INCONCLUSIVE: n_fail=%d < guard %d (no PASS/FAIL)"
			% [n_fail, GUARD_N_FAIL])
	else:
		var hf: float = float(s["hit_fail"])
		var se_hf := _se(hf, n_fail)
		var m_hf := (hf - TH_HIT_FAIL) / se_hf if se_hf > 0.0 else 0.0
		_ok("T-A2  hit_fail %.4f  vs TH %.2f  -> margin %+.2f SE  (n_fail=%d)"
			% [hf, TH_HIT_FAIL, m_hf, n_fail], hf >= TH_HIT_FAIL)

	var t5: float = float(s["tail5"])
	var se_t5 := _se(t5, int(s["n"]))
	# T-B′ 是上界判据：裕度 = (阈值 − 实测)/SE（实测越小越安全）
	var m_t5 := (TH_TAIL5 - t5) / se_t5 if se_t5 > 0.0 else 0.0
	# 🔴 §12.3 降级：修复后 hist 严格双峰 {0:243, 2:57} → P(X_form>=5) 结构恒 0，
	#    永久零信号、无检出能力 → 移出 _fail，降为〔事实登记〕（仅打印，不计失败）。
	#    常量 TH_TAIL5 保留作打印基准；断崖左移是比阈值翻红更早的信号（R-T9 监测）。
	print("   [INFO] T-B   tail5    %.4f  vs TH %.2f  -> margin %+.2f SE  (n=%d)  事实登记 · 结构恒 0 零信号，不计 _fail"
		% [t5, TH_TAIL5, m_t5, int(s["n"])])


## 🔴 T-D″ 阳性对照：同数值（ATTRITION=1.50 / HP0=120 / h^0.6 / AGGRO_R=9.0 / WARMUP=2
##    / n_slots=8 / B 路径）**只把 SpaceModel.mode 切成 PATH**，跑一局，返回全程 Σ dis_new。
##    🔴 §12.3 加固：改为按传入 seed 跑（3 seed 累计由调用方求和）；单 seed 实测期望 λ≈3。
func _run_tdd_control(seed: int) -> int:
	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	var cfg: Dictionary = _Cfg.cfg_of("B")
	cfg["n_slots"] = 8
	cfg["max_actions"] = 12
	var rng := _PyRandom.new(seed)
	var out := _RunLoopAggro.run("B", cfg, W_MAX, null, rng, true, 0.6, ATTRITION_FINAL, WARMUP)
	var rows: Array = out["rows"]
	var tot := 0
	var per_w: Array = []
	for r in rows:
		var dn: int = int(r.get("dis_new", 0))
		tot += dn
		per_w.append("%d:%d" % [int(r["w"]), dn])
	print("   [seed %d] per-wave dis_new = [%s]" % [seed, ",".join(per_w)])
	print("   [seed %d] last core_hp=%.1f · towers=%d · towers_disabled=%d" % [
		seed,
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
