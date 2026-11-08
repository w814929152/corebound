class_name TestSuite
extends RefCounted
##
## headless 自测套件 —— 断言 GDScript 伤害引擎与 Python 金标本逐位对齐。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd
##   <godot> --headless --path D:/roguedemo --quit        （main scene 在 headless 下自动跑）
##
## 断言口径：派生量 / 总 DPS 一律用**相对误差 ≤ 1e-12**（双精度同运算序下应当是 0 ULP 差）。
##
## ⚠️ Godot 坑（写这个文件时踩到的，改前必读）：
##   T1 headless `--script` 启动**不会**先做编辑器导入 → `.godot/global_script_class_cache.cfg`
##      可能不存在 → 所有 `class_name` 全局类型解析失败（"Could not find type X"）。
##      → 跨脚本引用一律用 `const X := preload("res://...")`；
##        返回值/变量用**无类型声明**（`var x = f()`），否则 `:=` 会因推不出类型而报错。
##   T2 GDScript 的 `String % …` **不支持 `%e` / `%g`**，只支持 s/d/x/o/f/v。
##      科学计数法自己写 `_sci()`；超长浮点用 `%.17f`。
##   T3 `String * int` 不合法 → 用 `String.repeat(n)`。
##

const TOL := 1e-12
const TOL_GEO := 1e-12

const _DamageEngine := preload("res://scripts/engine/damage_engine.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _PlayerState := preload("res://scripts/engine/player_state.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Softcap := preload("res://scripts/engine/softcap.gd")
const G := preload("res://tests/golden_reference.gd")

var _pass := 0
var _fail := 0
var _out: Array = []
var _geo = null


# ---------------------------------------------------------------------------
# 格式化 / 断言工具
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
	_log("   [%s] %s\n         got = %.17f\n         want= %.17f\n         |rel| = %s"
		% ["PASS" if ok else "FAIL", name, got, want, _sci(rel)])


func _check_int(name: String, got: int, want: int) -> void:
	var ok := (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	var ok := (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])


# 「最大相对误差 ≤ tol」型断言（want 恒为 0，不能用 _check 的相对口径，会恒过）
func _check_le(name: String, got: float, tol: float) -> void:
	var ok := (got <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  max_rel=%s  (tol=%s)" % ["PASS" if ok else "FAIL", name, _sci(got), _sci(tol)])


# ---------------------------------------------------------------------------
# 构筑工厂（返回无类型 —— 见 T1）
# ---------------------------------------------------------------------------
func _mkplayer(path_: String, towers_: Array, n_hist_max_: int = 0):
	var p = _PlayerState.new()
	p.path = path_
	p.towers = towers_
	p.n_hist_max = n_hist_max_ if n_hist_max_ > 0 else towers_.size()
	return p


func _build_a():
	return _mkplayer("A", [
		_PlayerState.make_tower(0, "Arrow", 1, {}),
		_PlayerState.make_tower(1, "Cannon", 10, {"FireUp": 100}),
	])


func _build_b():
	return _mkplayer("B", [
		_PlayerState.make_tower(0, "Arrow", 133, {}),
		_PlayerState.make_tower(1, "Arrow", 1, {}),
		_PlayerState.make_tower(2, "Cannon", 8, {"FireUp": 47}),
		_PlayerState.make_tower(3, "Cannon", 1, {}),
		_PlayerState.make_tower(4, "Cannon", 1, {}),
		_PlayerState.make_tower(5, "Cannon", 1, {}),
	])


# ===========================================================================
# 0. 几何 GEO6（方案 A）
# ===========================================================================
func _test_geo() -> void:
	_log("")
	_log("---- [0] GEO6 几何（方案 A · SLOTS6）----")
	_geo = _Geo6.build()
	_check_int("路径采样点数 n_path_pts", int(_geo.n_path_pts), G.GEO6_PATH_PTS)
	_check("路径总长 path_len", float(_geo.path_len), G.GEO6_PATH_LEN, TOL_GEO)

	var dist_max_rel := 0.0
	for i in range(6):
		for j in range(6):
			var want := float(G.GEO6_DIST[i][j])
			if want > 0.0:
				dist_max_rel = maxf(dist_max_rel, absf(float(_geo.dist[i][j]) - want) / want)
	_check_le("距离矩阵 6x6 最大相对误差", dist_max_rel, TOL_GEO)

	var cov_max_rel := 0.0
	for key in G.GEO6_COV:
		var parts = String(key).split("|")
		var got := float(_geo.cov_at(int(parts[0]), String(parts[1])))
		var w := float(G.GEO6_COV[key])
		cov_max_rel = maxf(cov_max_rel, absf(got - w) / w)
	_check_le("CoverageScore 18 项 最大相对误差", cov_max_rel, TOL_GEO)
	_log("       cov(S0,Arrow)=%.17f  cov(S2,Arrow)=%.17f  cov(S2,Cannon)=%.17f"
		% [float(_geo.cov_at(0, "Arrow")), float(_geo.cov_at(2, "Arrow")), float(_geo.cov_at(2, "Cannon"))])

	var types := ["Arrow", "Arrow", "Cannon", "Cannon", "Cannon", "Cannon"]
	var adj = _geo.links(types, "substantial")
	var adj_any = _geo.links(types, "any")
	_log("       links(0.65)[0]=%s  links(0.65)[2]=%s" % [str(adj[0]), str(adj[2])])
	_log("       links(1.00)[0]=%s  links(1.00)[2]=%s" % [str(adj_any[0]), str(adj_any[2])])
	_check_bool("0.65 口径下 S0<->S2 相连（喂出 E=134 的那条边）", adj[0].has(2), true)
	_check_bool("0.65 口径下 S2<->S0 相连（双向）", adj[2].has(0), true)
	_check("S0<->S2 距离 = 24.00（< 0.65x(22+18)=26.00 存活）", float(_geo.dist[0][2]), 24.0, TOL_GEO)


# ===========================================================================
# 1. softcap 陷阱
# ===========================================================================
func _test_softcap() -> void:
	_log("")
	_log("---- [1] softcap 陷阱（damage-pipeline §10.1 验收 3）----")
	_check("softcap_pow(101, 1.10, 100, 1.03)",
		_Softcap.pow_sc(101.0, 1.10, 100.0, 1.03), G.SOFTCAP_101)
	_check("softcap_pow(100, 1.10, 100, 1.03) == 1.10^100",
		_Softcap.pow_sc(100.0, 1.10, 100.0, 1.03), pow(1.10, 100.0))
	_check("softcap_pow(150, 1.10, 100, 1.03) == 1.10^100 x 1.03^50",
		_Softcap.pow_sc(150.0, 1.10, 100.0, 1.03), pow(1.10, 100.0) * pow(1.03, 50.0))


# ===========================================================================
# 2/3/4. 路径 A / B 全量对照
# ===========================================================================
func _run_case(tag: String, path: String, player, kr_mode: String) -> Dictionary:
	var cfg := _MvpConfig.cfg_of(path, _MvpConfig.KR_FINAL, _MvpConfig.LINK_RULE, kr_mode, "current")
	var r: Dictionary = _DamageEngine.compute_dps(player, cfg, _geo)
	_log("")
	_log("---- [%s] 路径 %s · kr_mode=%s ----" % [tag, path, kr_mode])
	_log("       N=%d  disc=%.4f  n_for_kappa=%d  core=%d  Ltot=%.0f  syn_hits=%d"
		% [player.towers.size(), float(r["info"]["disc"]),
		   int(r["info"]["n_for_kappa"]), int(r["info"]["core"]),
		   float(r["info"]["Ltot"]), int(r["info"]["syn_hits"])])
	_log("       E      = %s" % str(r["info"]["E"]))
	_log("       kappa  = %s" % str(r["info"]["kappa"]))
	_log("       kr     = %s" % str(r["info"]["kr"]))
	for i in range(r["info"]["per_tower"].size()):
		var p: Dictionary = r["info"]["per_tower"][i]
		_log("       #%d %s h=%d L=%.0f  base=%.12f  stack=%.10f  res=%.10f  focus=%.4f  allin=%.2f  cov=%.2f  syn=%.2f  dps=%.6f"
			% [i, String(player.towers[i].ctype), int(player.towers[i].h), float(r["info"]["L"][i]),
			   float(p["base"]), float(p["stack"]), float(p["res"]), float(p["focus"]),
			   float(p["allin"]), float(p["cov"]), float(p["syn"]), float(p["dps"])])
	_log("       subtotal=%.6f  AoE=%.6f  Crossfire=%.4f  Aux=%.6f  Empower=%.4f"
		% [float(r["info"]["subtotal"]), float(r["info"]["aoe"]), float(r["info"]["crossfire"]),
		   float(r["info"]["aux"]), float(r["info"]["empower"])])
	_log("       TOTAL DPS = %.6f" % float(r["total"]))
	return r


func _assert_case(r: Dictionary, want_total: float, want_subtotal: float,
		want_aoe: float, want_cf: float, want_e: Array, want_kappa: Array,
		want_kr: Array, want_per: Array, want_core: int, want_ltot: float,
		want_disc: float, prefix: String) -> void:
	_check(prefix + " TOTAL DPS", float(r["total"]), want_total)
	_check(prefix + " subtotal (ΣRaw)", float(r["info"]["subtotal"]), want_subtotal)
	_check(prefix + " AoE", float(r["info"]["aoe"]), want_aoe)
	_check(prefix + " Crossfire", float(r["info"]["crossfire"]), want_cf)
	_check(prefix + " Aux", float(r["info"]["aux"]), 1.0)
	_check(prefix + " Empowerment", float(r["info"]["empower"]), 1.0)
	_check_int(prefix + " CoreTower index", int(r["info"]["core"]), want_core)
	_check(prefix + " ΣL", float(r["info"]["Ltot"]), want_ltot)
	_check(prefix + " κ 广度折价 disc", float(r["info"]["disc"]), want_disc)
	for i in range(want_e.size()):
		_check(prefix + " E[%d]" % i, float(r["info"]["E"][i]), float(want_e[i]))
		_check(prefix + " κ[%d] (含 1+)" % i, float(r["info"]["kappa"][i]), float(want_kappa[i]))
		_check(prefix + " κ_r[%d]" % i, float(r["info"]["kr"][i]), float(want_kr[i]))
		var p: Dictionary = r["info"]["per_tower"][i]
		var w: Dictionary = want_per[i]
		_check(prefix + " base[%d]  = dps·h^0.6" % i, float(p["base"]), float(w["base"]))
		_check(prefix + " stack[%d]" % i, float(p["stack"]), float(w["stack"]))
		_check(prefix + " res[%d]    = (1+κ_r)^E" % i, float(p["res"]), float(w["res"]))
		_check(prefix + " focus[%d]  = 1+0.06·L·min(1,h/8)" % i, float(p["focus"]), float(w["focus"]))
		_check(prefix + " allin[%d]" % i, float(p["allin"]), float(w["allin"]))
		_check(prefix + " cov[%d]" % i, float(p["cov"]), float(w["cov"]))
		_check(prefix + " dps[%d]" % i, float(p["dps"]), float(w["dps"]))
		_check(prefix + " syn[%d]（Syn 已摘除 → 恒 1.0）" % i, float(p["syn"]), 1.0)
	_check_int(prefix + " syn_hits（Syn 已摘除 → 恒 0）", int(r["info"]["syn_hits"]), 0)


func _test_path_a() -> void:
	var r := _run_case("2", "A", _build_a(), "tier")
	_assert_case(r, G.A_TOTAL, G.A_SUBTOTAL, G.A_AOE, G.A_CF, G.A_E, G.A_KAPPA,
		G.A_KR_TIER, G.A_PER_TOWER, G.A_CORE, G.A_LTOT, G.A_DISC, "A")
	# 🔴 2026-11-08 口径变更：有效 DPS = 伤害 × 攻速。GDD §10.1 的 10,903,440 是 aspeed=1.0
	#    时代的定稿值（文档未改）。故这里比对「文档值 × 攻速加权折算」，折算系数由金标本
	#    按该构筑各塔攻速推出（A: Arrow 0.80 / Cannon 0.70）——口径再动一次就会红，不会静默漂移。
	var want_a := G.GDD_A_TOTAL * G.AS_WEIGHT_A
	var rel_gdd := absf(float(r["total"]) - want_a) / want_a
	_log("       vs GDD §10.1 文档值 10,903,440 × 攻速折算 %.6f → 相对差 %s"
		% [G.AS_WEIGHT_A, _sci(rel_gdd)])
	_check("A vs GDD §10.1 × 攻速折算", float(r["total"]), want_a, 1e-12)


func _test_path_b_tier() -> void:
	var r := _run_case("3", "B", _build_b(), "tier")
	_assert_case(r, G.B_TIER_TOTAL, G.B_TIER_SUBTOTAL, G.B_AOE, G.B_CF, G.B_E, G.B_KAPPA,
		G.B_KR_TIER, G.B_TIER_PER_TOWER, G.B_CORE, G.B_LTOT, G.B_DISC, "B/tier")
	var want_b := G.GDD_B_TOTAL * G.AS_WEIGHT_B
	var rel_gdd := absf(float(r["total"]) - want_b) / want_b
	_log("       vs GDD §10.1 文档值 4,991,136 × 攻速折算 %.6f → 相对差 %s"
		% [G.AS_WEIGHT_B, _sci(rel_gdd)])
	_check("B/tier vs GDD §10.1 × 攻速折算", float(r["total"]), want_b, 1e-12)
	_log("       ⚠️ GDD 手算写 Resonance = %s；引擎真值 = %.17f（1.05^134）"
		% [str(G.GDD_B_RESONANCE_HANDCALC), float(r["info"]["per_tower"][2]["res"])])


func _test_path_b_flat() -> void:
	var r := _run_case("4", "B", _build_b(), "flat")
	_assert_case(r, G.B_FLAT_TOTAL, G.B_FLAT_SUBTOTAL, G.B_AOE, G.B_CF, G.B_E, G.B_KAPPA,
		G.B_KR_FLAT, G.B_FLAT_PER_TOWER, G.B_CORE, G.B_LTOT, G.B_DISC, "B/flat")
	var want_b := G.GDD_B_TOTAL * G.AS_WEIGHT_B
	var rel_gdd := absf(float(r["total"]) - want_b) / want_b
	_log("       vs GDD §10.1 文档值 4,991,136 × 攻速折算 → 相对差 %s（flat 口径差在 Arrow 的 E=9）" % _sci(rel_gdd))
	_log("       差额 %.4f 全部来自无 Tag 的 Arrow：1.05^9=%.12f vs 1.045^9=%.12f（E=9）"
		% [G.B_FLAT_TOTAL - G.B_TIER_TOTAL, pow(1.05, 9.0), pow(1.045, 9.0)])


# ===========================================================================
# 5. 兜底①：ntower_mode = "max"（N_tower 取本局历史最大值）
# ===========================================================================
func _test_ntower_max() -> void:
	_log("")
	_log("---- [5] 兜底①：ntower_mode = max（N_tower_histmax）----")
	var pa = _build_a()
	pa.n_hist_max = 6      # 曾经铺到 6 塔，如今只剩 2 塔
	var cfg := _MvpConfig.cfg_of("A", _MvpConfig.KR_FINAL, _MvpConfig.LINK_RULE, "tier", "max")
	var r: Dictionary = _DamageEngine.compute_dps(pa, cfg, _geo)
	_check("n_for_kappa 读历史最大值", float(r["info"]["n_for_kappa"]), 6.0)
	_check("disc = 0.01·clamp(6−2,0,4)", float(r["info"]["disc"]), 0.04)
	_check("主塔 κ = 0.10 − 0.04 = 0.06", float(r["info"]["kappa"][1]), 1.06)
	_check("主塔 Stack = 1.06^100", float(r["info"]["per_tower"][1]["stack"]), pow(1.06, 100.0))
	_log("       兜底① 下 A 的 DPS = %.6f（定稿口径 %.6f，比值 %.6f）"
		% [float(r["total"]), G.A_TOTAL, float(r["total"]) / G.A_TOTAL])

	var cfg2 := _MvpConfig.cfg_of("A", _MvpConfig.KR_FINAL, _MvpConfig.LINK_RULE, "tier", "current")
	var r2: Dictionary = _DamageEngine.compute_dps(_build_a(), cfg2, _geo)
	_check("current 口径 n_for_kappa", float(r2["info"]["n_for_kappa"]), 2.0)
	_check("current 口径 disc", float(r2["info"]["disc"]), 0.0)
	_check("current 口径主塔 κ = 0.10", float(r2["info"]["kappa"][1]), 1.10)

	var pb = _build_b()
	var cfg3 := _MvpConfig.cfg_of("B", _MvpConfig.KR_FINAL, _MvpConfig.LINK_RULE, "tier", "max")
	var r3: Dictionary = _DamageEngine.compute_dps(pb, cfg3, _geo)
	_check("B: ntower_mode=max 与 current 逐位相同", float(r3["total"]), G.B_TIER_TOTAL)


# ===========================================================================
# 6. 边缘 / 红线单测
# ===========================================================================
func _test_traps() -> void:
	_log("")
	_log("---- [6] 红线单测（§10.1 验收 3 / 红线 R-4·R-5·R-7·R-8·R-10）----")
	var cfg := _MvpConfig.cfg_of("B", _MvpConfig.KR_FINAL, _MvpConfig.LINK_RULE, "tier", "current")

	# (a) 孤塔 h=133，无链接 → Resonance 必须 1.0（不是 1.05^133）
	var solo = _mkplayer("B", [_PlayerState.make_tower(0, "Arrow", 133, {})])
	var r: Dictionary = _DamageEngine.compute_dps(solo, cfg, _geo)
	_check("孤塔 E[0]", float(r["info"]["E"][0]), 0.0)
	_check("孤塔 Resonance == 1.0（不是 1.05^133）", float(r["info"]["per_tower"][0]["res"]), 1.0)

	# (b) 双向门槛：h=1 的塔，邻居 h=133 也不给它 E
	var pair = _mkplayer("B", [
		_PlayerState.make_tower(0, "Arrow", 133, {}),
		_PlayerState.make_tower(2, "Cannon", 1, {}),
	])
	var r2: Dictionary = _DamageEngine.compute_dps(pair, cfg, _geo)
	_check("h=1 塔的 E（邻居 h=133 也不给）", float(r2["info"]["E"][1]), 0.0)
	_check("h=133 塔的 E（邻居 h=1 不供）", float(r2["info"]["E"][0]), 0.0)
	_check("h=1 塔 Resonance", float(r2["info"]["per_tower"][1]["res"]), 1.0)

	# (c) R-4：只建塔不投卡 → L=0 → Focus 恒 1.00（L 与 h 解耦）
	var notank = _mkplayer("B", [_PlayerState.make_tower(2, "Cannon", 10, {})])
	var r3: Dictionary = _DamageEngine.compute_dps(notank, cfg, _geo)
	_check("Cannon h=10 但 L=0 → Focus == 1.00", float(r3["info"]["per_tower"][0]["focus"]), 1.0)
	_check("Cannon h=10 但 L=0 → AllIn == 1.00（ΣL=0）", float(r3["info"]["per_tower"][0]["allin"]), 1.0)

	# (d) R-4：Focus 预热门槛 min(1, h/8)
	var warm = _mkplayer("B", [_PlayerState.make_tower(2, "Cannon", 4, {"FireUp": 10})])
	var r4: Dictionary = _DamageEngine.compute_dps(warm, cfg, _geo)
	_check("h=4,L=10 → Focus = 1+0.06·10·(4/8) = 1.30", float(r4["info"]["per_tower"][0]["focus"]), 1.30)
	var warm8 = _mkplayer("B", [_PlayerState.make_tower(2, "Cannon", 8, {"FireUp": 10})])
	var r5: Dictionary = _DamageEngine.compute_dps(warm8, cfg, _geo)
	_check("h=8,L=10 → Focus 全额 = 1.60", float(r5["info"]["per_tower"][0]["focus"]), 1.60)
	var warm99 = _mkplayer("B", [_PlayerState.make_tower(2, "Cannon", 99, {"FireUp": 10})])
	var r6: Dictionary = _DamageEngine.compute_dps(warm99, cfg, _geo)
	_check("h=99（>8）→ ramp 夹取，Focus 仍 = 1.60", float(r6["info"]["per_tower"][0]["focus"]), 1.60)

	# (e) R-10：异 Tag 卡不计入 Stack
	var mis = _mkplayer("B", [_PlayerState.make_tower(2, "Cannon", 8, {"FrostUp": 47})])
	var r7: Dictionary = _DamageEngine.compute_dps(mis, cfg, _geo)
	_check("Cannon 挂 FrostUp×47 → Stack == 1.0（异 Tag 跳过）",
		float(r7["info"]["per_tower"][0]["stack"]), 1.0)

	# (f) R-7：Crossfire 阶梯
	var n1 = _mkplayer("B", [_PlayerState.make_tower(0, "Arrow", 5, {})])
	var r1: Dictionary = _DamageEngine.compute_dps(n1, cfg, _geo)
	_check("N=1 → Crossfire = 1.00", float(r1["info"]["crossfire"]), 1.0)
	var r2b: Dictionary = _DamageEngine.compute_dps(_build_a(), cfg, _geo)
	_check("N=2 → Crossfire = 1.25", float(r2b["info"]["crossfire"]), 1.25)
	var rb: Dictionary = _DamageEngine.compute_dps(_build_b(), cfg, _geo)
	_check("N=6 → Crossfire = 1.50", float(rb["info"]["crossfire"]), 1.5)

	# (g) R-8：Aux
	var frost = _mkplayer("B", [
		_PlayerState.make_tower(2, "Cannon", 8, {"FireUp": 47}),
		_PlayerState.make_tower(4, "Frost", 8, {}),
	])
	var r8: Dictionary = _DamageEngine.compute_dps(frost, cfg, _geo)
	var eff := 0.30 * (8.0 / (8.0 + 8.0))
	_check("Frost h=8 → eff_slow = 0.30·8/16 = 0.15", eff, 0.15)
	_check("Aux = 1/(1−eff_slow)", float(r8["info"]["aux"]), 1.0 / (1.0 - eff))
	_check("无 Frost 时 Aux == 1.0", float(rb["info"]["aux"]), 1.0)

	# (h) 空塔列表
	var empty = _mkplayer("B", [])
	var r9: Dictionary = _DamageEngine.compute_dps(empty, cfg, _geo)
	_check("空塔列表 → DPS = 0", float(r9["total"]), 0.0)


# ===========================================================================
# 7. 汇总
# ===========================================================================
## V-0′ 六槽候选：沿用原 Python 金标本构筑，只替换注入的几何。
## 不调用 _test_geo()：新布局的距离 / 逐塔 CoverageScore 本来就与旧路径布局不同；
## MVP 走聚合 Coverage 常量，真正必须保住的是 E、七区 DPS 与总输出。
func run_radial_golden(geo) -> bool:
	_geo = geo
	_log("[V-0′] 六槽候选金标本 A/B：相同塔位编号、塔型、等级，验证 E 和全部 DPS 乘区")
	_test_path_a()
	_test_path_b_tier()
	_test_path_b_flat()
	_log("[V-0′ DPS] 通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	return _fail == 0


func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》MVP 切片1 · 伤害引擎 headless 逐位对齐自测")
	_log("金标本：design/phase2/numeric-sim/corebound_sim_v08_salvage.py :: compute_dps_v8")
	_log("=".repeat(78))

	_test_geo()
	_test_softcap()
	_test_path_a()
	_test_path_b_tier()
	_test_path_b_flat()
	_test_ntower_max()
	_test_traps()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 全部对齐 —— GDScript 引擎与 Python 金标本逐位一致")
	else:
		_log("[NG] 有 %d 项未对齐 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0
