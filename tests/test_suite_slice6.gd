extends RefCounted
##
## headless 自测套件 —— 切片6「T1 仇恨口径登记 + 暴露度数据地基」
##
## 🔴 本切片的**边界**（用户 2026-10-01 拍板：留到后续批次）：
##    · 只登记口径 + 核验数据地基 + 落地 MVP 占位，**不激活任何 T1 玩法**。
##    · 仇恨（怪物转向攻塔 → 塔会被打死 → 漏怪分布变）在物理上会破坏切片5
##      刚建立的「实时版与金标本逐位等价」基线 → 整体留后续批次 + 300 局 MC 重扫。
##    · 与 S5-D1（三原型+Elite 列校准闸门）同一哲学：设计已定稿，校准未过不默认开。
##
## 判据来源：
##   · `design/gdd/mechanics-tower-life-death.md` v1.0（§0 塔死亡定性 · §4.3 交接点③
##     `Disabled_i ≡ 1.0` 占位 · Q-T3 机会型仇恨 `AGGRO_R=9.0` · 三硬约束 T-C1/C2/C3）
##   · `design/gdd/wave-spawner.md` v0.3（§2.2 F-3 路径几何 · §2.6 仇恨状态机 · §5.3 暴露度表）
##   · `design/gdd/core-defense.md`（F-3 配套路径几何 · 硬约束「≥1 塔位在 AGGRO_R 之外」）
##
## 被测对象：
##   · `scripts/engine/player_state.gd`（TowerState.disabled 占位字段）
##   · `scripts/engine/damage_engine.gd`（per_tower 末尾 `disabled ? 0.0 : 1.0` 落点）
##   · `scripts/geo/path_geometry.gd`（F-3 暴露度数据地基）
##   · `scripts/data/monster_data.gd`（AGGRO_R / AGGRO_EXIT / AGGRO_TICK 登记）
##   · `scripts/gameplay/wave_director.gd`（tower_aggro_enabled 默认 false）
##
## 🔴 本套件的最硬一条：disabled 占位 **MVP 恒 false → 对定稿 DPS 逐位零影响**。
##    这是抓"占位写错破坏金标本对齐"的探针。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice6
##

const TOL = 1e-12
const TOL_GEO = 0.01          # GDD §5.3 暴露度表两位小数

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _DamageEngine = preload("res://scripts/engine/damage_engine.gd")
const _PlayerState = preload("res://scripts/engine/player_state.gd")
const _TowerData = preload("res://scripts/data/tower_data.gd")
const _PathGeometry = preload("res://scripts/geo/path_geometry.gd")
const _Geo6 = preload("res://scripts/geo/geo6.gd")
const _MonsterData = preload("res://scripts/data/monster_data.gd")
const _WaveDirector = preload("res://scripts/gameplay/wave_director.gd")

var _pass = 0
var _fail = 0
var _out: Array = []

# 复用切片1 的定稿构筑（与 test_suite.gd 的 _build_b 同口径，避免二次定义金标本）
# 🔴 只读引用定稿数值，不在此文件二次定义任何 DPS/HP/κ 参数。


func _log(s: String) -> void:
	_out.append(s)
	print(s)


func _check(name: String, got: float, want: float, tol: float = TOL) -> void:
	var d = absf(got - want)
	var rel = 0.0
	if absf(want) > 1e-300:
		rel = d / absf(want)
	var ok = (d <= 1e-300) or (d <= tol) or (rel <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%.12f want=%.12f |d|=%s" % ["PASS" if ok else "FAIL", name, got, want, str(d)])


func _check_int(name: String, got: int, want: int) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])


# ---------------------------------------------------------------------------
# 构造一个多塔定稿构筑（B 路径，含深叠主塔 + 若干副塔）
# 🔴 与 test_suite.gd::_build_b 同口径，但只服务本切片的"disabled 前后对比"，
#    不校验绝对 DPS 值（那是切片1 的职责）。
# ---------------------------------------------------------------------------
func _mkplayer(path: String, towers: Array) -> RefCounted:
	var p := _PlayerState.new()
	p.path = path
	p.towers = towers
	p.n_hist_max = towers.size()
	return p


func _build_probe() -> RefCounted:
	# 3 座塔：一座深叠主塔（h=133）+ 两座副塔，保证 per_tower 非平凡
	return _mkplayer("B", [
		_PlayerState.make_tower(2, "Cannon", 133, {"FireUp": 20}),
		_PlayerState.make_tower(0, "Arrow", 8, {}),
		_PlayerState.make_tower(4, "Frost", 8, {}),
	])


# ---------------------------------------------------------------------------
#  AC-S6-1 · disabled 占位：MVP 恒 false → 对定稿 DPS 逐位零影响
# ---------------------------------------------------------------------------
func _test_disabled_mvp_zero_effect() -> void:
	_log("--- [AC-S6-1] disabled 占位：MVP 恒 false → DPS 逐位零影响（§4.3 交接点③）---")
	var cfg := _Cfg.cfg_of("B", _Cfg.KR_FINAL, _Cfg.LINK_RULE, "tier", "current")
	var geo = _Geo6.build()

	# 全部 enabled（disabled 默认 false）
	var p_on := _build_probe()
	var r_on: Dictionary = _DamageEngine.compute_dps(p_on, cfg, geo)

	# 显式把每座塔 disabled 保持 false（模拟 MVP 常态），确认与默认一致
	var p_explicit := _build_probe()
	for t in p_explicit.towers:
		t.disabled = false
	var r_explicit: Dictionary = _DamageEngine.compute_dps(p_explicit, cfg, geo)

	_check("MVP：默认 vs 显式 disabled=false → TOTAL DPS 逐位相同",
		float(r_on["total"]), float(r_explicit["total"]))
	_check("MVP：默认 vs 显式 disabled=false → ΣRaw 逐位相同",
		float(r_on["info"]["subtotal"]), float(r_explicit["info"]["subtotal"]))

	# per_tower 逐塔 dps 逐位相同
	for i in range(r_on["info"]["per_tower"].size()):
		_check("MVP：塔[%d] dps 逐位相同（disabled 占位零影响）" % i,
			float(r_on["info"]["per_tower"][i]["dps"]),
			float(r_explicit["info"]["per_tower"][i]["dps"]))
		_check_bool("MVP：塔[%d] per_tower 记录 disabled=false" % i,
			bool(r_on["info"]["per_tower"][i].get("disabled", true)), false)


# ---------------------------------------------------------------------------
#  AC-S6-2 · disabled=true → 该塔 dps 归零（断输出），但不断链（E/κ/其他塔不变）
# ---------------------------------------------------------------------------
func _test_disabled_breaks_output_not_chain() -> void:
	_log("--- [AC-S6-2] disabled=true → 断输出不断链（E-T 口径：不重建拓扑、不重算 E）---")
	var cfg := _Cfg.cfg_of("B", _Cfg.KR_FINAL, _Cfg.LINK_RULE, "tier", "current")
	var geo = _Geo6.build()

	var p := _build_probe()
	var r_on := _DamageEngine.compute_dps(p, cfg, geo)

	# 把主塔（index 0，深叠 Cannon）打停机
	var p_off := _build_probe()
	p_off.towers[0].disabled = true
	var r_off := _DamageEngine.compute_dps(p_off, cfg, geo)

	# ① 该塔 dps 归零
	_check("disabled 塔[0] dps → 0.0（断输出）",
		float(r_off["info"]["per_tower"][0]["dps"]), 0.0)
	_check_bool("disabled 塔[0] per_tower 记录 disabled=true",
		bool(r_off["info"]["per_tower"][0]["disabled"]), true)

	# ② 其他塔 dps 不受影响（不断链：不重建拓扑）
	for i in range(1, r_on["info"]["per_tower"].size()):
		_check("未停机塔[%d] dps 不变（不断链）" % i,
			float(r_off["info"]["per_tower"][i]["dps"]),
			float(r_on["info"]["per_tower"][i]["dps"]))

	# ③ E / κ / κ_r 全部不变（停机不重建邻接、不重算共鸣 —— E-T 口径）
	for i in range(r_on["info"]["E"].size()):
		_check("E[%d] 不变（停机不重算拓扑）" % i,
			float(r_off["info"]["E"][i]), float(r_on["info"]["E"][i]))
		_check("κ[%d] 不变" % i,
			float(r_off["info"]["kappa"][i]), float(r_on["info"]["kappa"][i]))
		_check("κ_r[%d] 不变" % i,
			float(r_off["info"]["kr"][i]), float(r_on["info"]["kr"][i]))

	# ④ 线性可加、无连锁放大：TOTAL 减少量 == 停机塔对 TOTAL 的贡献。
	#    全局乘区（AoE×Crossfire×Aux×Empower）= total / ΣRaw，停机前后**不变**
	#    （因为 disabled 不触发拓扑重算 → tag_tower_lv / 塔数都不变）。
	#    → 减少量 = 停机塔 dps × 全局乘区（正比于单塔 dps，无 κ/E 连锁）。
	var global_mult := float(r_on["total"]) / float(r_on["info"]["subtotal"])
	var delta := float(r_on["total"]) - float(r_off["total"])
	var want_delta := float(r_on["info"]["per_tower"][0]["dps"]) * global_mult
	_check("TOTAL 减少量 == 停机塔 dps × 全局乘区（线性可加，无连锁放大）",
		delta, want_delta)
	_check("全局乘区停机前后不变（disabled 不重算拓扑）",
		float(r_off["total"]) / float(r_off["info"]["subtotal"]), global_mult)


# ---------------------------------------------------------------------------
#  AC-S6-3 · 暴露度数据地基：d_path 逐位 + 硬约束「≥1 安全位」
# ---------------------------------------------------------------------------
func _test_exposure_hard_constraint() -> void:
	_log("--- [AC-S6-3] 暴露度数据地基：d_path 逐位 + 硬约束「≥1 塔位在 AGGRO_R 之外」---")
	var rows: Array = _PathGeometry.slot_exposure(_Geo6.SLOTS6, _MonsterData.AGGRO_R)
	_check_int("slot_exposure 返回 6 行", rows.size(), 6)

	# 逐塔位 d_path 与 GDD §5.3 表逐位（Python 金标本交叉验证一致）
	var want_d: Array = [6.00, 8.00, 5.00, 8.00, 10.82, 13.00]
	for i in range(rows.size()):
		_check("S%d d_path（GDD §5.3 表逐位）" % i,
			float(rows[i]["d_path"]), want_d[i], TOL_GEO)

	# 🔴 硬约束（T-C）：任何地图必须保证 ≥1 个塔位在 AGGRO_R 之外
	var safe := 0
	for r in rows:
		if not bool(r["is_exposed"]):
			safe += 1
	_check_int("硬约束：≥1 个塔位在 AGGRO_R 之外（方案 A 有 2 个：S4/S5）", safe, 2)

	# 暴露位 = S0/S1/S2/S3（4 个），安全位 = S4/S5（2 个）
	_check_bool("S0 is_exposed = true（d_path 6.00 ≤ 9.0）", bool(rows[0]["is_exposed"]), true)
	_check_bool("S2 is_exposed = true（最暴露 5.00）", bool(rows[2]["is_exposed"]), true)
	_check_bool("S4 is_exposed = false（安全，余量 +1.82）", bool(rows[4]["is_exposed"]), false)
	_check_bool("S5 is_exposed = false（最安全 13.00）", bool(rows[5]["is_exposed"]), false)


# ---------------------------------------------------------------------------
#  AC-S6-4 · AGGRO 参数登记 + 仇恨开关默认关闭（金标本等价口径）
# ---------------------------------------------------------------------------
func _test_aggro_params_registered() -> void:
	_log("--- [AC-S6-4] AGGRO 参数登记 + tower_aggro_enabled 默认 false（金标本等价口径）---")
	# 参数登记（一字不改定稿数值）
	_check("AGGRO_R 已登记 = 9.0（🔒 T1 才生效）", _MonsterData.AGGRO_R, 9.0, 1e-12)
	_check("AGGRO_EXIT 迟滞带退出阈值 = 10.8 = 9.0×1.2（🔒 T1）", _MonsterData.AGGRO_EXIT, 10.8, 1e-12)
	_check("AGGRO_TICK = 0.10（与 sim dt 对齐，🔒 T1）", _MonsterData.AGGRO_TICK, 0.10, 1e-12)

	# 仇恨开关默认关闭 → MVP 走金标本等价口径
	# 🔴 WaveDirector 是 Node，但开关字段是声明时初始化的 → new() 后直接读，不进树、不 free
	var wd = _WaveDirector.new()
	_check_bool("tower_aggro_enabled 默认 false（MVP 金标本等价口径）", wd.tower_aggro_enabled, false)
	_check_bool("prototype_split_enabled 默认 false", wd.prototype_split_enabled, false)
	_check_bool("elite_waves_enabled 默认 false", wd.elite_waves_enabled, false)


# ---------------------------------------------------------------------------
#  汇总
# ---------------------------------------------------------------------------
func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》MVP 切片6 · T1 仇恨口径登记 + 暴露度数据地基 —— 自测")
	_log("判据：mechanics-tower-life-death v1.0 §0/§4.3 · wave-spawner v0.3 §2.2/§2.6 · 边界=口径登记不激活玩法")
	_log("=".repeat(78))

	_test_disabled_mvp_zero_effect()
	_test_disabled_breaks_output_not_chain()
	_test_exposure_hard_constraint()
	_test_aggro_params_registered()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 切片6 口径登记 + 暴露度数据地基 + disabled 占位逐位零影响 —— 金标本零改动")
	else:
		_log("[NG] 有 %d 项未过 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0
