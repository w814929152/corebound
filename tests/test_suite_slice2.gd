class_name TestSuiteSlice2
extends RefCounted
##
## 切片2 自测套件 —— 断言 GDScript「战斗循环 + 商店/贪心AI + 主循环 + 判据统计」
## 与 Python 金标本（v03 / v06 / v07）**逐位对齐**，并跑出定稿判据链。
##
## 金标本期望值：`tests/golden_slice2.gd`（由 tools/export_golden_slice2.py 实跑导出）
##
## ⚠️ Godot 坑（与 test_suite.gd 同源，改前必读）
##   T1 headless `--script` 不做编辑器导入 → 无 global_script_class_cache.cfg
##      → 所有 `class_name` 全局类型解析失败。跨脚本一律 `preload`，
##        变量/返回值用无类型声明或显式 `float()`。
##   T2 `String % …` 不支持 `%e/%g` → 科学计数法自己写 `_sci()`。
##   T3 `absf()/floor()` 等全局函数返回值推不出类型 → 必须显式标 float/bool。
##

const TOL := 1e-12

## 逐波原始列的容差：1e-15（≈4~5 ULP）。
## 🔴 为什么不是"逐位判等"：Godot 的**浮点字面量解析不是正确舍入**。
##    实测（本机 Godot 4.7.2 / Windows）：
##      Python float('186.26806084384762') = 0x1.74893f455b53dp+7
##      Godot  字面量 186.26806084384762   = 0x1.74893f455b53cp+7   ← 低 1ULP
##      Godot  字面量 186.268060843847620  = 0x1.74893f455b53dp+7   ← 加一位就对了
##      Godot  字面量 3.07925140603429918e+03 ≠ 3079.251406034299   ← 换 18 位反而错
##    即：能否解析正确**与位数不成单调关系**，改生成器格式无法根除。
##    而金标本是生成物，不能"挑一个能跟实现对上的写法"——那等于拿实现污染金标本。
##    → 这里用 1e-15（比验收要求的 1e-6 严 9 个数量级）。
##    → 真正对末位敏感的量（MC 起飞率、前 20 局起飞波、整数列、build 串、round 后各列）
##      仍然是**逐位**判等，那些才是能抓出 1ULP bug 的探针。
const TOL_ROW := 1e-15

const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _RunLoop := preload("res://scripts/engine/run_loop.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _DamageEngine := preload("res://scripts/engine/damage_engine.gd")
const _FpPow := preload("res://scripts/engine/fp_pow.gd")
const _FpSum := preload("res://scripts/engine/fp_sum.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const G := preload("res://tests/golden_slice2.gd")

var _pass := 0
var _fail := 0
var _out: Array = []
var _geo = null
var _worst_row_rel := 0.0
var _worst_row_at := ""


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------
static func _sci(v: float) -> String:
	if v == 0.0:
		return "0.000e+00"
	var e := int(floor(log(absf(v)) / log(10.0)))
	var m := absf(v) / pow(10.0, float(e))
	return "%s%.3fe%s%02d" % ["-" if v < 0.0 else "", m, "+" if e >= 0 else "-", absi(e)]


func _log(s: String) -> void:
	_out.append(s)
	print(s)


func _check(name: String, got: float, want: float, tol: float = TOL) -> void:
	var d := absf(got - want)
	var rel := 0.0
	if absf(want) > 1e-300:
		rel = d / absf(want)
	var ok := (d <= 1e-300) or (rel <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
		_log("   [FAIL] %s\n         got = %.17f\n         want= %.17f\n         |rel| = %s"
			% [name, got, want, _sci(rel)])


## 逐位（bit-exact）断言 —— 浮点末位对齐只能用它，`_check()` 的 1e-12 容差太粗
func _check_exact(name: String, got: float, want: float) -> void:
	if got == want:
		_pass += 1
	else:
		_fail += 1
		_log("   [FAIL] %s\n         got = %.17f\n         want= %.17f\n         ΔULP ≈ %s"
			% [name, got, want, _sci(absf(got - want) / maxf(absf(want), 1e-300))])


func _check_int(name: String, got: int, want: int) -> void:
	if got == want:
		_pass += 1
	else:
		_fail += 1
		_log("   [FAIL] %s  got=%d want=%d" % [name, got, want])


func _check_str(name: String, got: String, want: String) -> void:
	if got == want:
		_pass += 1
	else:
		_fail += 1
		_log("   [FAIL] %s\n         got = %s\n         want= %s" % [name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	if got == want:
		_pass += 1
	else:
		_fail += 1
		_log("   [FAIL] %s  got=%s want=%s" % [name, str(got), str(want)])


func _cfg(path: String, kr_mode: String, rule: String = "substantial", kappa_r: float = 0.045) -> Dictionary:
	# 🔴 定稿口径：kr_mode="tier" / rule="substantial"(f=0.65) / ntower_mode="current" / salvage 关
	return _MvpConfig.cfg_of(path, kappa_r, rule, kr_mode, "current", false)


# ===========================================================================
# 0. 浮点末位对齐 —— 切片2 联调挖出的两个 1ULP 陷阱
#
#    🔴 这两条不是"锦上添花"，是 MC 起飞率能不能对上的**充要条件**：
#       修好 pow_int  → B 起飞率 89.3% → 89.7%
#       再修好 sum_py → B 起飞率 89.7% → 91.3%（金标本值）
#    两者都是"并列候选被末位噪声翻转选择"型的 bug：决定性跑看不出来，只有 MC 能抓到。
# ===========================================================================
func _test_fp_alignment() -> void:
	_log("")
	_log("--- [0] 浮点末位对齐：pow_int（正确舍入） / sum_py（Neumaier 补偿求和）---")

	# ---- (a) pow_int 与 Python `x ** n` 逐位一致 ----
	# 1.06^6 的真值恰好 = 1418519112256 / 10^12 = 1.418519112256（有限小数），
	# 是"谁对谁错"一目了然的样本点。
	_check_exact("pow_int(1.06, 6)  == Python 1.06**6", _FpPow.pow_int(1.06, 6), 1.4185191122560004)
	_check_exact("pow_int(1.03, 7)  == Python 1.03**7（软 cap 衰减）",
		_FpPow.pow_int(1.03, 7), 1.2298738654248702)
	_check_exact("pow_int(1.42, 19) == Python 1.42**19（W20 血量）",
		_FpPow.pow_int(1.42, 19), 782.4895444894507)
	_check_exact("pow_int(1.045, 11) == Python 1.045**11（共振 (1+κ_r)^E）",
		_FpPow.pow_int(1.045, 11), 1.6228530457108763)
	_check_exact("pow_int(1.10, 23) == Python 1.10**23",
		_FpPow.pow_int(1.10, 23), 8.95430243255239)
	_check_exact("pow_int(1.02, 50) == Python 1.02**50", _FpPow.pow_int(1.02, 50), 2.691588029073608)
	_check_exact("pow_int(10.0, 3)  == 1000.0", _FpPow.pow_int(10.0, 3), 1000.0)
	_check_exact("pow_int(2.0, -52) == 2^-52（ULP 标度）",
		_FpPow.pow_int(2.0, -52), 2.220446049250313e-16)
	# 非整数指数必须退回原生 pow（两者在这些点上本来就一致）
	_check_exact("pow_py(3.0, 0.6) == Python 3**0.6", _FpPow.pow_py(3.0, 0.6), 1.9331820449317627)

	_log("      [参考] Godot 原生 pow(1.06,6.0) = %s；正确舍入值 = %s"
		% [String.num(pow(1.06, 6.0), 17), String.num(_FpPow.pow_int(1.06, 6), 17)])
	_log("             两者若相同，说明本平台 libm 已与 Python 对齐（pow_int 仍是保险）")

	# ---- (b) sum_py 与 Python `sum()` 逐位一致，且**对置换不敏感** ----
	# 这是 B 局第 18 局 W4 step2 的四个并列候选：同一多重集，只换了 14.399… 的位置。
	const BIG := 14.39930738184878
	const C1 := 15.772230305352018
	const C2 := 6.6499999999999995
	const S := 9.5
	var want_sum := 65.3215376872008
	# 只测 slot0/3/4/5：slot1 是 Cannon（C1）、slot2 是第二座 Cannon（C2），
	# 把 BIG 塞进去就换了多重集，不是"同一集合换位置"了。
	for slot in [0, 3, 4, 5]:
		var arr: Array = [S, C1, C2, S, S, S]
		arr[slot] = BIG
		_check_exact("sum_py：14.399… 放在 slot%d 时 == Python sum()" % slot,
			_FpSum.sum_py(arr), want_sum)
	# 朴素累加对照：slot 0/3/4 会得到 65.32153768720079（比补偿求和小 1ULP）——
	# 这正是"升级 S3"与"升级 S5"被判成不等价的根因。
	var naive0 := 0.0
	for v in [BIG, C1, C2, S, S, S]:
		naive0 += float(v)
	_check_bool("朴素累加确实与补偿求和不同（否则 sum_py 就是多余的）",
		naive0 != want_sum, true)
	_log("      [参考] 朴素累加 slot0 = %s；补偿求和 = %s"
		% [String.num(naive0, 17), String.num(want_sum, 17)])

	# ---- (c) Godot 的浮点**字面量解析**不是正确舍入（TOL_ROW 的由来，见文件头）----
	#      16 * 1.42^7 的真值（Python） = 0x1.74893f455b53dp+7
	var hp_ref := 16.0 * _FpPow.pow_int(1.42, 7)
	_check_exact("Godot 能正确解析 18 位写法 186.268060843847620", 186.268060843847620, hp_ref)
	# 下面这条**只做记录不做断言**：若未来 Godot 修好了解释器，它会自然翻转，
	# 那时 TOL_ROW 就可以收紧回逐位判等（请把这一段注释一起改掉）。
	_log("      [参考] 17 位写法 186.26806084384762 解析正确? %s（false = 低 1ULP）"
		% str(186.26806084384762 == hp_ref))
	_log("             20 位写法 3.07925140603429917974e+03 解析正确? %s"
		% str(3.07925140603429917974e+03 == 16.0 * _FpPow.pow_int(1.42, 15)))
	_log("             → 成败与位数不成单调关系，故金标本逐波原始列用 1e-15 而非逐位判等")


# ===========================================================================
# 1. PyRandom（MT19937）—— 蒙特卡洛可复现的地基
# ===========================================================================
func _test_pyrandom() -> void:
	_log("")
	_log("--- [1] PyRandom：MT19937 是否与 Python random.Random 逐位同序列 ---")
	var r := _PyRandom.new(20260930)
	for i in range(G.RNG_RANDOM.size()):
		_check("random()#%d" % i, r.random(), float(G.RNG_RANDOM[i]))

	var r2 := _PyRandom.new(20260930)
	for i in range(G.RNG_OFFERS.size()):
		var s := _ShopAI.draw_offers(r2, 3, null)
		var ks: Array = s.keys()
		ks.sort()
		_check_str("draw_offers(force=null)#%d" % i,
			",".join(ks), ",".join(G.RNG_OFFERS[i]))

	var r3 := _PyRandom.new(20260930)
	for i in range(G.RNG_OFFERS_FORCED.size()):
		var s3 := _ShopAI.draw_offers(r3, 3, "FireUp")
		var ks3: Array = s3.keys()
		ks3.sort()
		_check_str("draw_offers(force=FireUp)#%d" % i,
			",".join(ks3), ",".join(G.RNG_OFFERS_FORCED[i]))
		# 保底卡必须**始终**在商品里
		_check_bool("保底卡不被挤掉#%d" % i, s3.has("FireUp"), true)

	# randrange（CPython 的拒绝采样 _randbelow，**不是** int(random()*n)）
	var r4 := _PyRandom.new(20260930)
	for i in range(G.RNG_RANDRANGE7.size()):
		_check_int("randrange(7)#%d" % i, r4.randrange(7), int(G.RNG_RANDRANGE7[i]))


# ===========================================================================
# 2. pround —— Python 兼容的 banker's rounding
# ===========================================================================
func _test_pround() -> void:
	_log("")
	_log("--- [2] pround：与 Python round(x, nd) 逐位同值（含半值取偶）---")
	for c in G.ROUND_CASES:
		var x := float(c[0])
		var nd := int(c[1])
		var want := float(c[2])
		_check("round(%.6f, %d)" % [x, nd], _Stats.pround(x, nd), want)


# ===========================================================================
# 3. monster_stats / 波次时长
# ===========================================================================
func _test_monster_stats() -> void:
	_log("")
	_log("--- [3] monster_stats：与金标本 rows 里的 n / hp_each / total_hp 对照 ---")
	var cfg := _cfg("A", "tier")
	for i in range(G.ROWS_TIER_A.size()):
		var g: Dictionary = G.ROWS_TIER_A[i]
		var ms := _WaveSim.monster_stats(int(g["w"]), cfg)
		_check_int("W%d 怪物数 n" % int(g["w"]), int(ms["n"]), int(g["n"]))
		_check("W%d hp_each" % int(g["w"]), float(ms["hp"]), float(g["hp_each"]))
		_check("W%d total_hp" % int(g["w"]), float(ms["total_hp"]), float(g["total_hp"]))
	# 波次时长（v03 make_cfg 的两个 lambda）
	_check("wave_dur(1)  = 28.0+2.2", _MvpConfig.wave_dur(1), 30.2)
	_check("wave_dur(20) = 28.0+44", _MvpConfig.wave_dur(20), 72.0)
	_check("spawn_window(5)  = 0.30", _MvpConfig.spawn_window(5), 0.30)
	_check("spawn_window(6)  = 0.60", _MvpConfig.spawn_window(6), 0.60)
	_check("spawn_window(12) = 0.60", _MvpConfig.spawn_window(12), 0.60)
	_check("spawn_window(13) = 1.00", _MvpConfig.spawn_window(13), 1.00)


# ===========================================================================
# 4. simulate_wave：正序遍历 ≡ 稳定排序（性能等价改写的守护测试）
# ===========================================================================
func _test_wave_equivalence() -> void:
	_log("")
	_log("--- [4] simulate_wave：正序遍历 ≡ Python 的稳定排序（等价改写守护）---")
	# 手工造几种构筑，跑 W1..W20，两种实现必须逐位相同
	var builds := [
		["A", [[0, "Arrow", 1, {}], [1, "Cannon", 8, {"FireUp": 47}]]],
		["B", [[0, "Arrow", 133, {}], [2, "Cannon", 8, {"FireUp": 47}]]],
		["B", [[0, "Arrow", 3, {}], [1, "Arrow", 3, {}], [2, "Cannon", 3, {"FireUp": 5}]]],
		["A", [[0, "Arrow", 1, {}]]],
	]
	for bd in builds:
		var path := String(bd[0])
		var cfg := _cfg(path, "tier")
		var pl = _SimPlayer.new_player(path, cfg, _geo)
		pl.towers = []
		for row in bd[1]:
			pl.towers.append(_PS_tower(int(row[0]), String(row[1]), int(row[2]), row[3]))
		var worst := 0
		var tot_k := 0
		var tot_l := 0
		for w in range(1, 21):
			var a := _WaveSim.simulate_wave(pl, w, cfg, _geo)
			var b := _WaveSim.simulate_wave_naive(pl, w, cfg, _geo)
			if int(a["kills"]) != int(b["kills"]) or int(a["leaked"]) != int(b["leaked"]):
				worst += 1
			if absf(float(a["scrap_earned"]) - float(b["scrap_earned"])) > 1e-9:
				worst += 1
			tot_k += int(a["kills"])
			tot_l += int(a["leaked"])
		_check_int("%s 构筑：20 波两种实现分歧数（应为 0）" % path, worst, 0)
		_log("      %s 构筑 20 波合计 kills=%d leaked=%d" % [path, tot_k, tot_l])


func _PS_tower(slot: int, ctype: String, h: int, attach: Dictionary):
	const _PS := preload("res://scripts/engine/player_state.gd")
	return _PS.make_tower(slot, ctype, h, attach)


# ===========================================================================
# 5. 决定性跑逐波 rows（全精度 + round 后的列）
# ===========================================================================
func _check_rows(label: String, path: String, rows: Array, gold: Array) -> void:
	_log("")
	_log("--- [5] 决定性跑逐波对照：%s / 路径 %s（rng=null，贪心AI 确定性）---" % [label, path])
	_check_int("%s%s 波数" % [label, path], rows.size(), gold.size())
	var n := mini(rows.size(), gold.size())
	for i in range(n):
		var r: Dictionary = rows[i]
		var g: Dictionary = gold[i]
		var w := int(g["w"])
		var tag := "%s%s W%d" % [label, path, w]
		_check_int("%s n" % tag, int(r["n"]), int(g["n"]))
		# 原始列走 TOL_ROW（1e-15）—— 见文件头说明：金标本字面量本身可能带 1ULP 解析误差。
		# 同时记录本路径的最大相对偏差，供 slice2-headless-verify.md 引用。
		for k in ["hp_each", "total_hp", "eff_dps", "ratio", "core_hp", "income"]:
			var gv := float(g[k])
			var rv := float(r[k + "_raw"])
			_check("%s %s" % [tag, k], rv, gv, TOL_ROW)
			if absf(gv) > 1e-300:
				var rel2 := absf(rv - gv) / absf(gv)
				if rel2 > _worst_row_rel:
					_worst_row_rel = rel2
					_worst_row_at = "%s %s" % [tag, k]
		_check_int("%s kills" % tag, int(r["kills"]), int(g["kills"]))
		_check_int("%s leaked" % tag, int(r["leaked"]), int(g["leaked"]))
		_check_int("%s rerolls" % tag, int(r["rerolls"]), int(g["rerolls"]))
		_check_int("%s cum_rerolls" % tag, int(r["cum_rerolls"]), int(g["cum_rerolls"]))
		_check_int("%s towers" % tag, int(r["towers"]), int(g["towers"]))
		_check_int("%s slots" % tag, int(r["slots"]), int(g["slots"]))
		_check_str("%s build" % tag, String(r["build"]), String(g["build"]))
		# round 后的列（校验 pround 与 Python round 同值）
		_check("%s eff_dps(round1)" % tag, float(r["eff_dps"]), float(g["eff_dps_r"]))
		_check("%s ratio(round3)" % tag, float(r["ratio"]), float(g["ratio_r"]))
		_check("%s hp_each(round1)" % tag, float(r["hp_each"]), float(g["hp_each_r"]))
		_check("%s total_hp(round1)" % tag, float(r["total_hp"]), float(g["total_hp_r"]))
		_check("%s core_hp(round1)" % tag, float(r["core_hp"]), float(g["core_hp_r"]))
		_check("%s income(round1)" % tag, float(r["income"]), float(g["income_r"]))


func _test_decisive() -> void:
	var outA := _RunLoop.run("A", _cfg("A", "tier"), 20, _geo, null)
	var outB := _RunLoop.run("B", _cfg("B", "tier"), 20, _geo, null)
	_check_rows("tier", "A", outA["rows"], G.ROWS_TIER_A)
	_check_rows("tier", "B", outB["rows"], G.ROWS_TIER_B)
	var fA := _RunLoop.run("A", _cfg("A", "flat"), 20, _geo, null)
	var fB := _RunLoop.run("B", _cfg("B", "flat"), 20, _geo, null)
	_check_rows("flat", "A", fA["rows"], G.ROWS_FLAT045_A)
	_check_rows("flat", "B", fB["rows"], G.ROWS_FLAT045_B)
	_log("")
	_log("--- [5] 定稿 tier 口径 A/B 逐波速览（eff_dps 取 round1，与金标本 CSV 同口径）---")
	_log("   W |   A ratio |   B ratio |      A dps |      B dps | A core | B core | A 构筑")
	_log("  ---+----------+-----------+------------+------------+--------+--------+----------------------")
	for i in range(mini(outA["rows"].size(), outB["rows"].size())):
		var a: Dictionary = outA["rows"][i]
		var b: Dictionary = outB["rows"][i]
		_log("  %2d | %8.3f | %9.3f | %10.1f | %10.1f | %6.1f | %6.1f | %s"
			% [int(a["w"]), float(a["ratio"]), float(b["ratio"]),
			   float(a["eff_dps"]), float(b["eff_dps"]),
			   float(a["core_hp"]), float(b["core_hp"]), String(a["build"])])


# ===========================================================================
# 6. 定稿判据链（★ 本切片的核心交付）
# ===========================================================================
func _test_criteria() -> void:
	_log("")
	_log("--- [6] 定稿判据链（mapA-kappaR-sweep.md §2 「新口径·κ_r档位(不动)」行）---")
	_log("      [逐波] 原始列最大相对偏差 = %s  @ %s（验收线 1e-6）"
		% [_sci(_worst_row_rel), _worst_row_at])
	var ev := _Stats.eval_point(_cfg("A", "tier"), _cfg("B", "tier"))

	_check_int("① 单核 A 起飞波次 = W8", int(ev["toA"]), int(G.STATS_TIER["toA"]))
	_check_int("② 多塔 B 起飞波次 = W12", int(ev["toB"]), int(G.STATS_TIER["toB"]))
	_check("③ A 的 W20 ratio = 21.77", float(ev["w20A"]), float(G.STATS_TIER["w20A"]))
	_check("④ B 的 W20 ratio = 9.97", float(ev["w20B"]), float(G.STATS_TIER["w20B"]))
	_check("⑤ B/A = 0.458", float(ev["ba"]), float(G.STATS_TIER["ba"]))
	_check_int("⑥ A 领先波数 = 16", int(ev["lead"]["A"]), int(G.STATS_TIER["leadA"]))
	_check_int("⑦ B 领先波数 = 4", int(ev["lead"]["B"]), int(G.STATS_TIER["leadB"]))
	_check_int("⑧ 交叉次数 = 1", int(ev["flips"]), int(G.STATS_TIER["flips"]))
	_check_int("⑨ B 首领先 = W1", int(ev["firstB"]), int(G.STATS_TIER["firstB"]))
	_check_int("⑩ A 首领先 = W5", int(ev["firstA"]), int(G.STATS_TIER["firstA"]))
	_check("⑪ A 雪崩期增速（W16→W20）= 2.4", float(ev["hA"]["grow"]), float(G.STATS_TIER["growA"]))
	_check("⑫ B 雪崩期增速（W16→W20）= 3.0", float(ev["hB"]["grow"]), float(G.STATS_TIER["growB"]))
	_check_bool("⑬ A W13→W20 单调上升", bool(ev["hA"]["rise"]), true)
	_check_bool("⑭ B W13→W20 单调上升", bool(ev["hB"]["rise"]), true)
	_check_bool("⑮ A 苟活期 W1-9 存活", bool(ev["hA"]["survive"]), true)
	_check_bool("⑯ B 苟活期 W1-9 存活", bool(ev["hB"]["survive"]), true)

	# ---- 6 条红线 ----
	_check_bool("判据·B起飞 ∈ W10-15", bool(ev["c_win"]), true)
	_check_bool("判据·B/A < 1（概念 §2.4.5 单核后期 carry）", bool(ev["c_ba"]), true)
	_check_bool("判据·交叉领先 ≥ 1", bool(ev["c_flips"]), true)
	_check_bool("判据·三阶段健康（双路径）", bool(ev["c_health"]), true)

	# ---- 逐波领先表（20 行）----
	var cross: Array = ev["cross"]
	_check_int("逐波领先表行数 = 20", cross.size(), 20)
	for i in range(mini(cross.size(), G.CROSS_TIER.size())):
		var row: Array = cross[i]
		var gr: Array = G.CROSS_TIER[i]
		_check_int("W%d A ratio" % int(row[0]), int(round(float(row[1]) * 1000.0)),
			int(round(float(gr[1]) * 1000.0)))
		_check_int("W%d B ratio" % int(row[0]), int(round(float(row[2]) * 1000.0)),
			int(round(float(gr[2]) * 1000.0)))
		_check_str("W%d 领先方" % int(row[0]), String(row[3]), String(gr[3]))

	# ---- flat 0.045 对照口径（确认 tier/flat 两条口径真的不同）----
	_log("")
	_log("      [对照] flat κ_r=0.045 口径（非定稿口径，仅作敏感性对照）")
	var evf := _Stats.eval_point(_cfg("A", "flat"), _cfg("B", "flat"))
	_check_int("flat B 起飞 = W13", int(evf["toB"]), int(G.STATS_FLAT045["toB"]))
	_check("flat B/A = 0.242", float(evf["ba"]), float(G.STATS_FLAT045["ba"]))
	_check_int("flat A 起飞 = W8", int(evf["toA"]), int(G.STATS_FLAT045["toA"]))


# ===========================================================================
# 7. 蒙特卡洛起飞率（MC 300，seed=20260930）
# ===========================================================================
func _test_mc() -> void:
	_log("")
	_log("--- [7] 蒙特卡洛起飞率（MC 300 局 / seed=20260930 / 定稿 tier 口径）---")
	var t0 := Time.get_ticks_msec()
	var rngA := _PyRandom.new(20260930)
	var ra := _Stats.takeoff_rate("A", _cfg("A", "tier"), 300, 20, 12, rngA)
	_log("      A：起飞率 %.1f%%  存活率 %.1f%%  中位起飞 W%.1f  （%d ms）"
		% [float(ra["rate"]) * 100.0, float(ra["surv"]) * 100.0, float(ra["med"]),
		   Time.get_ticks_msec() - t0])
	_check("A 起飞率 = 69.3%", float(ra["rate"]), float(G.MC_TIER["A"]["rate"]))
	_check("A 存活率 = 69.3%", float(ra["surv"]), float(G.MC_TIER["A"]["surv"]))
	_check_int("A 起飞局数 = 208/300", int(ra["n_takeoff"]), int(G.MC_TIER["A"]["n_takeoff"]))
	_check("A 中位起飞波 = W8", float(ra["med"]), 8.0)

	var t1 := Time.get_ticks_msec()
	var rngB := _PyRandom.new(20260930)
	var rb := _Stats.takeoff_rate("B", _cfg("B", "tier"), 300, 20, 12, rngB)
	_log("      B：起飞率 %.1f%%  存活率 %.1f%%  中位起飞 W%.1f  （%d ms）"
		% [float(rb["rate"]) * 100.0, float(rb["surv"]) * 100.0, float(rb["med"]),
		   Time.get_ticks_msec() - t1])
	_check("B 起飞率 = 91.3%", float(rb["rate"]), float(G.MC_TIER["B"]["rate"]))
	_check("B 存活率 = 100.0%", float(rb["surv"]), float(G.MC_TIER["B"]["surv"]))
	_check_int("B 起飞局数 = 274/300", int(rb["n_takeoff"]), int(G.MC_TIER["B"]["n_takeoff"]))
	_check("B 中位起飞波 = W13", float(rb["med"]), 13.0)

	# 红线
	_check_bool("判据·A 起飞率 ≥ 60%", float(ra["rate"]) >= 0.60, true)
	_check_bool("判据·B 起飞率 ≥ 80%", float(rb["rate"]) >= 0.80, true)


# ---------------------------------------------------------------------------
# 7b. MC 前 20 局逐局对照 —— 定位端口发散点（比只看总起飞率有用得多）
# ---------------------------------------------------------------------------
func _test_mc_trace() -> void:
	_log("")
	_log("--- [7b] MC 前 20 局逐局起飞波 + 第 1 局逐波 rows（定位发散点）---")
	for path in ["A", "B"]:
		var rng := _PyRandom.new(20260930)
		var cfg := _cfg(String(path), "tier")
		var got: Array = []
		var run1: Array = []
		for i in range(20):
			var cx: Dictionary = cfg.duplicate(true)
			cx["max_actions"] = 12
			var out := _RunLoop.run(String(path), cx, 20, _geo, rng)
			var rows: Array = out["rows"]
			var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
			var tw := _Stats.takeoff_wave(rows)
			got.append(tw if (alive and tw >= 0) else -1)
			if i == 0:
				run1 = rows
		var want: Array = G.MC_TRACE_A if path == "A" else G.MC_TRACE_B
		var ndiff := 0
		for i in range(mini(got.size(), want.size())):
			if int(got[i]) != int(want[i]):
				ndiff += 1
		_check_int("%s：前 20 局起飞波与金标本分歧局数（应为 0）" % String(path), ndiff, 0)
		_log("      %s got  = %s" % [path, str(got)])
		_log("      %s want = %s" % [path, str(want)])

		# 第 1 局逐波全精度对照
		var gold: Array = G.MC_RUN1_A if path == "A" else G.MC_RUN1_B
		_check_int("%s：第 1 局波数" % String(path), run1.size(), gold.size())
		for i in range(mini(run1.size(), gold.size())):
			var r: Dictionary = run1[i]
			var g: Dictionary = gold[i]
			var tag := "%s 第1局 W%d" % [String(path), int(g["w"])]
			_check("%s eff_dps" % tag, float(r["eff_dps_raw"]), float(g["eff_dps"]))
			_check("%s ratio" % tag, float(r["ratio_raw"]), float(g["ratio"]))
			_check_int("%s kills" % tag, int(r["kills"]), int(g["kills"]))
			_check_int("%s leaked" % tag, int(r["leaked"]), int(g["leaked"]))
			_check_int("%s towers" % tag, int(r["towers"]), int(g["towers"]))
			_check_int("%s slots" % tag, int(r["slots"]), int(g["slots"]))
			_check_str("%s build" % tag, String(r["build"]), String(g["build"]))


# ===========================================================================
# 8. 商店 / 贪心AI 的红线与陷阱
# ===========================================================================
func _test_shop_traps() -> void:
	_log("")
	_log("--- [8] 商店 / 贪心AI 红线与陷阱 ---")
	var cfgB := _cfg("B", "tier")

	# (a) 起手：Arrow@slot0 且卡册 = {Arrow}
	var p = _SimPlayer.new_player("B", cfgB, _geo)
	_check_int("起手塔数 = 1", p.towers.size(), 1)
	_check_int("起手塔位 = slot0", int(p.towers[0].slot), 0)
	_check_str("起手塔类型 = Arrow", String(p.towers[0].ctype), "Arrow")
	_check_int("起手卡册 = {Arrow}", p.cards.size(), 1)
	_check_bool("起手卡册含 Arrow", p.cards.has("Arrow"), true)

	# (b) pity_card：主塔 = (Σattach, h) 最大者；Arrow 无 Tag → 返回 null
	_check("pity_card(只有 Arrow) = null", 0.0 if _ShopAI.pity_card(p) == null else 1.0, 0.0)
	var p2 = _SimPlayer.new_player("B", cfgB, _geo)
	p2.towers.append(_PS_tower(1, "Cannon", 3, {"FireUp": 4}))
	_check_str("pity_card(Cannon 主塔) = FireUp", String(_ShopAI.pity_card(p2)), "FireUp")
	var p3 = _SimPlayer.new_player("B", cfgB, _geo)
	p3.towers.append(_PS_tower(1, "Frost", 3, {}))
	_check_str("pity_card(Frost 主塔) = FrostUp", String(_ShopAI.pity_card(p3)), "FrostUp")

	# (c) fire_stock 火焰库存摩擦（A=6 / B=3）：拉满后本波不再出现 fire 类动作
	var pB = _SimPlayer.new_player("B", cfgB, _geo)
	pB.towers.append(_PS_tower(1, "Cannon", 3, {}))
	var a0 := _ShopAI.enumerate_actions(pB, cfgB, 0, null, _geo)
	var a3 := _ShopAI.enumerate_actions(pB, cfgB, 3, null, _geo)
	var nfire0 := 0
	var nfire3 := 0
	for act in a0:
		if _ShopAI.card_tag(String(act[1])) == "fire":
			nfire0 += 1
	for act in a3:
		if _ShopAI.card_tag(String(act[1])) == "fire":
			nfire3 += 1
	_check_bool("B：fire_bought=0 时有 fire 类动作", nfire0 > 0, true)
	_check_int("B：fire_bought=3（=fire_stock）时 fire 类动作清空", nfire3, 0)

	var cfgA := _cfg("A", "tier")
	var pA = _SimPlayer.new_player("A", cfgA, _geo)
	pA.towers.append(_PS_tower(1, "Cannon", 3, {}))
	var aA0 := _ShopAI.enumerate_actions(pA, cfgA, 0, null, _geo)
	var aA6 := _ShopAI.enumerate_actions(pA, cfgA, 6, null, _geo)
	var nf0 := 0
	var nf6 := 0
	for act in aA0:
		if _ShopAI.card_tag(String(act[1])) == "fire":
			nf0 += 1
	for act in aA6:
		if _ShopAI.card_tag(String(act[1])) == "fire":
			nf6 += 1
	_check_bool("A：fire_bought=0 时有 fire 类动作", nf0 > 0, true)
	_check_int("A：fire_bought=6（=fire_stock）时 fire 类动作清空", nf6, 0)

	# (d) max_actions=12 是否真生效
	#     ⚠️ 这里有个反直觉点：砍到 6 **不会**掉 DPS —— 6 次动作全花在"买"上，
	#     买完就没划算动作了，多出来的 6 次动作只是在烧 reroll（决定性跑 offers=None，
	#     刷新刷不出新卡）。所以要用 cum_rerolls 验上限，用 max_actions=3 验购买配额。
	var tight6: Dictionary = _cfg("A", "tier").duplicate(true)
	tight6["max_actions"] = 6
	var tight3: Dictionary = _cfg("A", "tier").duplicate(true)
	tight3["max_actions"] = 3
	var r12 := _RunLoop.run("A", _cfg("A", "tier"), 20, _geo, null)
	var r6 := _RunLoop.run("A", tight6, 20, _geo, null)
	var r3 := _RunLoop.run("A", tight3, 20, _geo, null)
	var d12 := float(r12["rows"][19]["eff_dps_raw"])
	var d6 := float(r6["rows"][19]["eff_dps_raw"])
	var d3 := float(r3["rows"][19]["eff_dps_raw"])
	_check_int("A：max_actions=12 → 20 波累计刷新 89", int(r12["rows"][19]["cum_rerolls"]), 89)
	# 🔴 金标本实测：6 → 累计刷新 **1** 次（不是 0）。
	#    有 1 波买完 6 个动作后还剩钱、且没有划算动作 → 触发 1 次 reroll。
	#    （踩过：早先写成 0，是因为没区分「动作配额」与「刷新配额」——
	#     max_actions 同时管两者，买 6 次后若还有第 7 个动作位才轮得到刷新。）
	_check_int("A：max_actions=6  → 20 波累计刷新 1（几乎全花在买）",
		int(r6["rows"][19]["cum_rerolls"]), 1)
	_check_bool("max_actions 上限真生效（12 与 6 的刷新次数不同）",
		int(r12["rows"][19]["cum_rerolls"]) != int(r6["rows"][19]["cum_rerolls"]), true)
	_check_bool("购买配额真生效（砍到 3 后 W20 DPS 显著下降）", d3 < d12 * 0.5, true)
	_log("      A：max_actions=12 → DPS %.2f（刷新 %d 次）；6 → %.2f（刷新 %d 次）；3 → %.2f"
		% [d12, int(r12["rows"][19]["cum_rerolls"]), d6,
		   int(r6["rows"][19]["cum_rerolls"]), d3])
	var cr12 := int(r12["rows"][19]["cum_rerolls"])
	_check_int("A：20 波累计刷新次数 = 89（12 动作上限的产物）", cr12,
		int(G.ROWS_TIER_A[19]["cum_rerolls"]))

	# (e) drop_from / snap-rest / weakest_card
	#     ⚠️ 构造要**避开 AllIn 的副作用**：若场上还有另一个"装配层数够多"的塔，
	#     丢掉 FireUp 反而会让那座塔拿到 AllIn ×1.6 → DPS 不降反升（真实机制，非 bug）。
	var p4 = _SimPlayer.new_player("B", cfgB, _geo)
	p4.cards = {"Arrow": true, "FireUp": true}
	p4.towers.append(_PS_tower(1, "Cannon", 3, {"FireUp": 5}))
	var before4 := _DamageEngine.dps_only(p4, cfgB, _geo)
	var s4 := _SimPlayer.snap(p4)
	_ShopAI.drop_from(p4, "FireUp")
	var after4 := _DamageEngine.dps_only(p4, cfgB, _geo)
	# ⚠️ 必须在 rest() **之前**检查被丢弃后的状态
	_check_bool("drop_from(FireUp) 真的降 DPS", after4 < before4, true)
	_check_bool("drop_from 后卡册移除 FireUp", not p4.cards.has("FireUp"), true)
	_check_int("drop_from 后 Cannon 的装配层清空", int(p4.towers[1].attach.size()), 0)
	_SimPlayer.rest(p4, s4)
	_check("snap/rest 回滚后 DPS 复原", _DamageEngine.dps_only(p4, cfgB, _geo), before4)
	_check_bool("snap/rest 回滚后卡册复原", p4.cards.has("FireUp"), true)

	# (e2) AllIn 副作用：丢掉主塔的卡 → 核心塔转移 → DPS 可能**上升**
	var p4b = _SimPlayer.new_player("B", cfgB, _geo)
	p4b.cards = {"Arrow": true, "FireUp": true, "FrostUp": true}
	p4b.towers.append(_PS_tower(1, "Cannon", 3, {"FireUp": 5}))
	p4b.towers.append(_PS_tower(2, "Frost", 3, {"FrostUp": 5}))
	var b4b := _DamageEngine.dps_only(p4b, cfgB, _geo)
	var s4b := _SimPlayer.snap(p4b)
	_ShopAI.drop_from(p4b, "FireUp")
	var a4b := _DamageEngine.dps_only(p4b, cfgB, _geo)
	_SimPlayer.rest(p4b, s4b)
	_check_bool("丢主塔卡后核心塔转移（AllIn 转移，DPS 未必下降）",
		absf(a4b - b4b) > 1e-12, true)
	_log("      AllIn 副作用：丢 FireUp 前 DPS %.4f → 丢后 %.4f（核心塔从 Cannon 转到 Frost）"
		% [b4b, a4b])

	# (e3) weakest_card：取"边际损失最小"的那张（并列取插入序第一个）
	var p4c = _SimPlayer.new_player("B", cfgB, _geo)
	p4c.cards = {"Arrow": true, "FireUp": true, "FrostUp": true}
	p4c.towers.append(_PS_tower(1, "Cannon", 8, {"FireUp": 20}))
	p4c.towers.append(_PS_tower(2, "Frost", 8, {"FrostUp": 3}))
	var cur4c := _DamageEngine.dps_only(p4c, cfgB, _geo)
	var losses := {}
	for nm in p4c.cards:
		var s := _SimPlayer.snap(p4c)
		_ShopAI.drop_from(p4c, String(nm))
		losses[String(nm)] = cur4c - _DamageEngine.dps_only(p4c, cfgB, _geo)
		_SimPlayer.rest(p4c, s)
	var wcard = _ShopAI.weakest_card(p4c, cfgB, _geo)
	var want_min = null
	var want_loss := 1e300
	for nm2 in losses:
		if float(losses[nm2]) < want_loss:
			want_loss = float(losses[nm2])
			want_min = String(nm2)
	_check_str("weakest_card = 边际损失最小者", String(wcard), String(want_min))
	_log("      边际损失：%s" % str(losses))
	# 塔卡被 drop 时整类塔一起消失
	var p5 = _SimPlayer.new_player("B", cfgB, _geo)
	p5.cards["Arrow"] = true
	p5.towers.append(_PS_tower(1, "Arrow", 9, {}))
	_ShopAI.drop_from(p5, "Arrow")
	_check_int("drop_from(Arrow) → 所有 Arrow 塔被移除", p5.towers.size(), 0)

	# (f) 卡价（wave_price_step=0.0 → 无递增）
	var counts := {}
	_check("action_cost(build)=12", _ShopAI.action_cost(["build", "Cannon", 1, null], cfgB, counts), 12.0)
	_check("action_cost(up)=12", _ShopAI.action_cost(["up", "Cannon", 1, null], cfgB, counts), 12.0)
	_check("action_cost(reinf)=9", _ShopAI.action_cost(["reinf", "FireUp", 1, null], cfgB, counts), 9.0)
	_check("action_cost(econ)=10", _ShopAI.action_cost(["econ", "ScrapUp", null, null], cfgB, counts), 10.0)

	# (g) 经济卡：income_mult 封顶 1.0（5 张 ×0.20）
	var p6 = _SimPlayer.new_player("B", cfgB, _geo)
	for _i in range(5):
		_ShopAI.apply_action(p6, ["econ", "ScrapUp", null, null], cfgB)
	_check("econ ×5 → income_mult = 1.00", float(p6.income_mult), 1.0)
	_check_bool("income_mult=1.0 后不再出现 econ 动作",
		not _has_econ(_ShopAI.enumerate_actions(p6, cfgB, 0, null, _geo)), true)

	# (h) 塔位上限：B=6（铺满），A=2（单核 + 1 挂件）
	var p7 = _SimPlayer.new_player("B", cfgB, _geo)
	for s in [1, 2, 3, 4, 5]:
		p7.towers.append(_PS_tower(s, "Cannon", 1, {}))
	var acts7 := _ShopAI.enumerate_actions(p7, cfgB, 0, null, _geo)
	var nbuild := 0
	for act in acts7:
		if String(act[0]) == "build":
			nbuild += 1
	_check_int("B 铺满 6 塔位后不再有 build 动作", nbuild, 0)
	var p8 = _SimPlayer.new_player("A", cfgA, _geo)
	p8.towers.append(_PS_tower(1, "Cannon", 1, {}))
	var acts8 := _ShopAI.enumerate_actions(p8, cfgA, 0, null, _geo)
	var nbuild8 := 0
	for act in acts8:
		if String(act[0]) == "build":
			nbuild8 += 1
	_check_int("A 塔数上限 2 → 满 2 塔后不再有 build 动作", nbuild8, 0)


func _has_econ(acts: Array) -> bool:
	for act in acts:
		if String(act[0]) == "econ":
			return true
	return false


# ===========================================================================
# 9. 汇总
# ===========================================================================
## V-0′：六槽径向候选只注入 geo，默认金标本入口仍使用 Geo6。
## 注意：此处仅验证无仇恨的 MVP 数值层；T1 仇恨 / ATTRITION 必须等径向运动学落地后另跑。
func run_v0_radial(geo) -> bool:
	_geo = geo
	_log("[V-0′] 六槽 R2：75链接阈值、含空槽4096组合、逐波金标本、300局 MC")
	_test_radial_links()
	_test_decisive()
	_test_mc_trace()
	_test_radial_criteria()
	_test_radial_mc()
	_log("[V-0′ 数值] 通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	return _fail == 0


func _test_radial_links() -> void:
	var old_geo = _Geo6.build()
	var mismatch := 0
	var min_margin := INF
	for i in range(6):
		for j in range(i + 1, 6):
			for threshold in [23.4, 24.7, 26.0, 27.3, 28.6]:
				var old_hit: bool = float(old_geo.dist[i][j]) <= float(threshold)
				var new_hit: bool = float(_geo.dist[i][j]) <= float(threshold)
				if old_hit != new_hit:
					mismatch += 1
				min_margin = minf(min_margin, absf(float(_geo.dist[i][j]) - float(threshold)))
	_check_int("V-0′ 15对×5阈值逐对失配", mismatch, 0)
	_check_bool("V-0′ 链接阈值最小余量 ≥0.5", min_margin >= 0.5, true)
	var full_match := 0
	var with_empty_match := 0
	var choices: Array = ["", "Cannon", "Frost", "Arrow"]
	for number in range(4096):
		var code := number
		var types: Array = []
		for _slot in range(6):
			types.append(choices[code % 4])
			code = code / 4
		var same: bool = old_geo.links(types, "substantial") == _geo.links(types, "substantial")
		if same:
			with_empty_match += 1
			if not types.has(""):
				full_match += 1
	_check_int("V-0′ 满槽729种塔型组合全等", full_match, 729)
	_check_int("V-0′ 含空槽4096种构筑全等", with_empty_match, 4096)
	_log("[V-0′ 链接] 75阈值失配=%d，729/729、4096/4096，最小安全余量=%.6f"
		% [mismatch, min_margin])


func _test_radial_criteria() -> void:
	var a: Dictionary = _RunLoop.run("A", _cfg("A", "tier"), 20, _geo, null)
	var b: Dictionary = _RunLoop.run("B", _cfg("B", "tier"), 20, _geo, null)
	var sa: Dictionary = _Stats.summarize(a["rows"])
	var sb: Dictionary = _Stats.summarize(b["rows"])
	var cl: Array = _Stats.cross_lead(a["rows"], b["rows"])
	var ha: Dictionary = _Stats.stage_health(a["rows"])
	var hb: Dictionary = _Stats.stage_health(b["rows"])
	var wa := float(sa["w20"])
	var wb := float(sb["w20"])
	_check_int("V-0′ A 起飞波", int(sa["takeoff"]), int(G.STATS_TIER["toA"]))
	_check_int("V-0′ B 起飞波", int(sb["takeoff"]), int(G.STATS_TIER["toB"]))
	_check("V-0′ W20 A ratio (金标本保留2位)", _Stats.pround(wa, 2), float(G.STATS_TIER["w20A"]))
	_check("V-0′ W20 B ratio (金标本保留2位)", _Stats.pround(wb, 2), float(G.STATS_TIER["w20B"]))
	_check("V-0′ B/A", _Stats.pround(wb / wa, 3), float(G.STATS_TIER["ba"]))
	_check_int("V-0′ A 领先波数", int(cl[1]["A"]), int(G.STATS_TIER["leadA"]))
	_check_int("V-0′ B 领先波数", int(cl[1]["B"]), int(G.STATS_TIER["leadB"]))
	_check_int("V-0′ 领先翻转", int(cl[2]), int(G.STATS_TIER["flips"]))
	_check_int("V-0′ A 首领先", int(cl[3]), int(G.STATS_TIER["firstA"]))
	_check_int("V-0′ B 首领先", int(cl[4]), int(G.STATS_TIER["firstB"]))
	_check("V-0′ A 雪崩期增速", float(ha["grow"]), float(G.STATS_TIER["growA"]))
	_check("V-0′ B 雪崩期增速", float(hb["grow"]), float(G.STATS_TIER["growB"]))
	_check_bool("V-0′ A W13–20 上升", bool(ha["rise"]), true)
	_check_bool("V-0′ B W13–20 上升", bool(hb["rise"]), true)
	_check_bool("V-0′ A 苟活期", bool(ha["survive"]), true)
	_check_bool("V-0′ B 苟活期", bool(hb["survive"]), true)
	_log("[V-0′ 判据] 起飞 A=W%d B=W%d；B/A=%.3f；领先=%s；翻转=%d"
		% [int(sa["takeoff"]), int(sb["takeoff"]), wb / wa, str(cl[1]), int(cl[2])])


func _test_radial_mc() -> void:
	for path in ["A", "B"]:
		var rng := _PyRandom.new(20260930)
		var cfg := _cfg(String(path), "tier")
		var trace: Array = []
		var takeoffs := 0
		var survives := 0
		var hits: Array = []
		for i in range(300):
			var cx: Dictionary = cfg.duplicate(true)
			cx["max_actions"] = 12
			var result: Dictionary = _RunLoop.run(String(path), cx, 20, _geo, rng)
			var rows: Array = result["rows"]
			var alive: bool = not rows.is_empty() and float(rows[-1]["core_hp"]) > 0.0
			var wave: int = _Stats.takeoff_wave(rows)
			if alive:
				survives += 1
			if alive and wave >= 0:
				takeoffs += 1
				hits.append(wave)
			if i < 25:
				trace.append(wave if alive and wave >= 0 else -1)
		var want: Dictionary = G.MC_TIER[String(path)]
		var golden_trace: Array = G.MC_TRACE_A if path == "A" else G.MC_TRACE_B
		_check_int("V-0′ %s 300局起飞" % path, takeoffs, int(want["n_takeoff"]))
		_check_int("V-0′ %s 300局存活" % path, survives, int(want["n_surv"]))
		_check("V-0′ %s 中位起飞波" % path, _Stats._median(hits), 8.0 if path == "A" else 13.0)
		_check_int("V-0′ %s 前25局逐局分歧" % path, _trace_diff(trace, golden_trace), 0)
		_log("[V-0′ MC] %s：%d/300 起飞，%d/300 存活，前25局分歧 %d"
			% [path, takeoffs, survives, _trace_diff(trace, golden_trace)])


static func _trace_diff(got: Array, want: Array) -> int:
	var diff := absi(got.size() - want.size())
	for i in range(mini(got.size(), want.size())):
		if int(got[i]) != int(want[i]):
			diff += 1
	return diff


func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》MVP 切片2 · 战斗循环 + 商店/贪心AI headless 逐位对齐自测")
	_log("金标本：corebound_sim_v03.py（战斗/商店/主循环） + v06（判据统计） + v07（0.65 口径）")
	_log("口径：kr_mode=tier / link_rule=substantial(f=0.65) / ntower_mode=current / salvage 关")
	_log("=".repeat(78))

	_geo = _Geo6.build()
	_test_fp_alignment()
	_test_pyrandom()
	_test_pround()
	_test_monster_stats()
	_test_wave_equivalence()
	_test_decisive()
	_test_criteria()
	_test_mc()
	_test_mc_trace()
	_test_shop_traps()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 全部对齐 —— GDScript 与 Python 金标本逐位一致，定稿判据链全部复现")
	else:
		_log("[NG] 有 %d 项未对齐 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0
