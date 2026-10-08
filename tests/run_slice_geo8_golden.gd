extends SceneTree
##
## headless 八槽金标本对照（`geo8golden` 入口）—— 阶段1 #74 数值扫参·闸门①
##
## 🔴 使命：证明**八槽接入零污染既有数值层**。
##    金标本 A/B 构筑只用 slot 0-5（前六槽），S6/S7 空置。
##    E-G8-5 已证 Geo8 前六槽邻接 == Geo6（诱导子图守恒）
##    → 八槽下 A/B 的 DPS 应与六槽锚点**逐位相同**：
##      · A  TOTAL = 10,903,440.347229
##      · B/tier = 4,991,135.610234
##    若这一条破了，说明八槽 geo 泄漏进了前六槽的 E/共鸣/DPS 链。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script tests/run_slice_geo8_golden.gd
##

const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _DE = preload("res://scripts/engine/damage_engine.gd")
const _PS = preload("res://scripts/engine/player_state.gd")
const _Geo6 = preload("res://scripts/geo/geo6.gd")
const _Geo8 = preload("res://scripts/geo/geo8.gd")

# 六槽 V-0′ 锚点（来自 run_radial_golden 实跑，2026-10-08）
const A_TOTAL := 10903440.347229
const B_TIER_TOTAL := 4991135.610234
const B_E := [9.0, 0.0, 134.0, 0.0, 0.0, 0.0]

var _fail = 0


func _ok(name: String, cond: bool) -> void:
	print("   [%s] %s" % ["PASS" if cond else "FAIL", name])
	if not cond:
		_fail += 1


func _check(name: String, got: float, want: float, tol: float = 1e-6) -> void:
	var d: float = absf(got - want)
	_ok("%s  got=%.6f want=%.6f |d|=%s" % [name, got, want, str(d)], d <= tol)


func _mkplayer(path_: String, towers_: Array) -> Object:
	var p = _PS.new()
	p.path = path_
	p.towers = towers_
	p.n_hist_max = towers_.size()
	return p


func _build_a() -> Object:
	return _mkplayer("A", [
		_PS.make_tower(0, "Arrow", 1, {}),
		_PS.make_tower(1, "Cannon", 10, {"FireUp": 100}),
	])


func _build_b() -> Object:
	return _mkplayer("B", [
		_PS.make_tower(0, "Arrow", 133, {}),
		_PS.make_tower(1, "Arrow", 1, {}),
		_PS.make_tower(2, "Cannon", 8, {"FireUp": 47}),
		_PS.make_tower(3, "Cannon", 1, {}),
		_PS.make_tower(4, "Cannon", 1, {}),
		_PS.make_tower(5, "Cannon", 1, {}),
	])


func _initialize() -> void:
	print("===================================================================")
	print("径向阶段1 · 八槽金标本对照（闸门①：零污染既有数值层）")
	print("===================================================================")

	var geo8 = _Geo8.build8()
	var geo6 = _Geo6.build()
	print("  geo8.n=%d · geo6.n=%d" % [geo8.n, geo6.n])

	# ---- A 构筑（tier 口径，A 无 tier/flat 差异）----
	print("\n---- [A] 八槽 vs 六槽 ----")
	var cfgA := _Cfg.cfg_of("A", _Cfg.KR_FINAL, _Cfg.LINK_RULE, "tier", "current")
	var pa: Object = _build_a()
	var rA8: Dictionary = _DE.compute_dps(pa, cfgA, geo8)
	var rA6: Dictionary = _DE.compute_dps(pa, cfgA, geo6)
	print("   八槽 A TOTAL = %.6f" % float(rA8["total"]))
	print("   六槽 A TOTAL = %.6f" % float(rA6["total"]))
	_check("八槽 A TOTAL == 六槽锚点", float(rA8["total"]), A_TOTAL, 1e-4)
	_check("八槽 A == 六槽 A（逐位）", float(rA8["total"]), float(rA6["total"]), 1e-12)
	# E 向量逐位一致
	var e8: Array = rA8["info"]["E"]
	var e6: Array = rA6["info"]["E"]
	var e_ok := e8.size() == e6.size()
	for i in range(e8.size()):
		if absf(float(e8[i]) - float(e6[i])) > 1e-12:
			e_ok = false
	_ok("八槽 A E 向量 == 六槽 E 向量（逐位）", e_ok)

	# ---- B 构筑（tier）----
	print("\n---- [B/tier] 八槽 vs 六槽 ----")
	var cfgB := _Cfg.cfg_of("B", _Cfg.KR_FINAL, _Cfg.LINK_RULE, "tier", "current")
	var pb: Object = _build_b()
	var rB8: Dictionary = _DE.compute_dps(pb, cfgB, geo8)
	var rB6: Dictionary = _DE.compute_dps(pb, cfgB, geo6)
	print("   八槽 B/tier TOTAL = %.6f" % float(rB8["total"]))
	print("   六槽 B/tier TOTAL = %.6f" % float(rB6["total"]))
	_check("八槽 B/tier TOTAL == 六槽锚点", float(rB8["total"]), B_TIER_TOTAL, 1e-4)
	_check("八槽 B/tier == 六槽 B/tier（逐位）", float(rB8["total"]), float(rB6["total"]), 1e-12)
	# E 向量：B 有 6 塔，E 应含 [9,0,134,0,0,0]
	var eb8: Array = rB8["info"]["E"]
	print("   八槽 B E = %s" % str(eb8))
	# 前六槽 E 与六槽一致
	var eb6: Array = rB6["info"]["E"]
	var eb_ok := eb8.size() == eb6.size()
	for i in range(eb8.size()):
		if absf(float(eb8[i]) - float(eb6[i])) > 1e-12:
			eb_ok = false
	_ok("八槽 B E 向量（前六槽）== 六槽 E 向量（逐位）", eb_ok)

	# ---- B 构筑（flat）----
	print("\n---- [B/flat] 八槽 vs 六槽 ----")
	var cfgBf := _Cfg.cfg_of("B", _Cfg.KR_FINAL, _Cfg.LINK_RULE, "flat", "current")
	var rBf8: Dictionary = _DE.compute_dps(pb, cfgBf, geo8)
	var rBf6: Dictionary = _DE.compute_dps(pb, cfgBf, geo6)
	print("   八槽 B/flat TOTAL = %.6f" % float(rBf8["total"]))
	print("   六槽 B/flat TOTAL = %.6f" % float(rBf6["total"]))
	_check("八槽 B/flat == 六槽 B/flat（逐位）", float(rBf8["total"]), float(rBf6["total"]), 1e-12)

	print("\n===================================================================")
	print("八槽金标本对照汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)
