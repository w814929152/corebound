extends RefCounted
##
## headless 自测套件 —— 径向核心围攻 · **阶段1 八槽 E8-A 几何验收**（`geo8` 入口）
##
## 依据：`docs/architecture/radial-core-siege-tech-assessment.md` §验证附录 · E8-A
##      `design/gdd/radial-core-siege-draft.md` §2.4.1b / R-CS4
##
## 🔴 本套件的使命：**独立验证八槽几何**，绝不继承六槽 V-0′ 结论。
##    前六槽与 R2 逐位一致（便于六槽金标本作对照），新增 S6/S7 两外哨。
##    草案红线：八槽必须单独跑 shop AI/MC/共鸣/ATTRITION，不得拿六槽判据冒充。
##    本套件只验**几何自洽**（距离/链接/暴露/角空隙/半径梯度/R-CS4），
##    数值扫参另立（见 test_suite 后续 + 300 局 MC）。
##
## 判据（本套件自检项）：
##   E-G8-1  n=8，前六槽与 R2 逐位一致
##   E-G8-2  关键距离矩阵值（dist[6][7]=50.228 / dist[0][6]=18.483 / dist[5][7]=39.367）
##   E-G8-3  新边存在：S6↔S0/S1、S7↔S2/S4（substantial 规则下任意原型均接）
##   E-G8-4  新槽不连其余旧槽（S6 仅 S0/S1、S7 仅 S2/S4；距 > 最大阈值 28.6）
##   E-G8-5  六槽诱导子图守恒：Geo8 前六槽邻接 == Geo6.build() 同配置邻接（对照基线）
##   E-G8-6  暴露楔形 S6/S7 = 11.25%（§2.4.1b 外部真值 · 🔴 R-9：原自指式已修）
##   E-G8-7  R-CS4：最外圈暴露楔形 ≤ 最内圈的 1/2
##   E-G8-8  最小塔间距 ≥ 9.5（=10.144）
##   E-G8-9  最大角空隙 ≤ 90°（=74.165°，旧 S5→S1 之间）
##   E-G8-10 全部塔位落在 0..55 地图内，离出生环 R_s=55 有安全余量
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- geo8
##

const TOL_DIST = 1e-6
const AGGRO_R := 9.0                    # T1 仇恨半径（暴露楔形口径）
const MAP_LO := 0.0
const MAP_HI := 55.0
const SPAWN_RING := 55.0                # R_s（离出生环安全余量）
## 🔴 R-9：S6/S7 暴露楔形的**外部真值** —— 草案 `radial-core-siege-draft.md` §2.4.1b /
##   §2.6.2：S6/S7 远哨（r=26）暴露楔形各 **11.25%**（= asin(9/26)/π）。用于替代原
##   "用 asin(9/r6)/π 比自己" 的自指断言（后者恒真、无证伪能力）。
const WEDGE_S6_S7_EXT := 0.1125

const _Geo6 = preload("res://scripts/geo/geo6.gd")
const _Geo8 = preload("res://scripts/geo/geo8.gd")
const _TowerData = preload("res://scripts/data/tower_data.gd")

var _pass = 0
var _fail = 0


func _log(s: String) -> void:
	print(s)


func _tally(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s" % ["PASS" if ok else "FAIL", name])


func _check(name: String, got: float, want: float, tol: float = TOL_DIST) -> void:
	var d: float = absf(got - want)
	var ok := d <= tol
	# 🔴 G7：GDScript `String %` 不支持 `%e` → 用 %s + str() 打印差值。
	_tally("%s  got=%.6f want=%.6f |d|=%s" % [name, got, want, str(d)], ok)


func run_all() -> bool:
	_log("===================================================================")
	_log("径向阶段1 · 八槽 E8-A 几何验收")
	_log("===================================================================")

	var g8 = _Geo8.build8()
	var g6 = _Geo6.build()

	# ---- E-G8-1 槽数 + 前六槽逐位一致 ----
	_log("\n---- [E-G8-1] 槽数与前六槽逐位一致 ----")
	_check("八槽 n==8", float(g8.n), 8.0, 1e-9)
	var first6_ok := true
	for i in range(6):
		var a: Vector2 = g8.slots[i]
		var b: Vector2 = _Geo8.SLOTS8[i]
		if a.distance_to(b) > 1e-12:
			first6_ok = false
	_check("前六槽与 R2 逐位一致", 1.0 if first6_ok else 0.0, 1.0, 1e-12)

	# ---- E-G8-2 关键距离矩阵 ----
	_log("\n---- [E-G8-2] 关键距离矩阵值 ----")
	_check("dist[6][7] 两外哨间距", g8.dist[6][7], 50.2281366214266, TOL_DIST)
	_check("dist[0][6] S6↔S0", g8.dist[0][6], 18.4829726812979, TOL_DIST)
	_check("dist[1][6] S6↔S1", g8.dist[1][6], 18.835, 1e-3)
	_check("dist[2][7] S7↔S2", g8.dist[2][7], 18.600, 1e-3)
	_check("dist[4][7] S7↔S4", g8.dist[4][7], 18.589, 1e-3)
	_check("dist[5][7] S5↔S7", g8.dist[5][7], 39.3666907672377, TOL_DIST)

	# ---- E-G8-3 / E-G8-4 新边存在 + 不连其余旧槽（substantial 规则，全 Arrow）----
	_log("\n---- [E-G8-3/4] 新边接线（substantial · 全 Arrow rng22）----")
	var types8: Array = ["Arrow", "Arrow", "Arrow", "Arrow", "Arrow", "Arrow", "Arrow", "Arrow"]
	var adj: Array = g8.links(types8, "substantial")
	# S6(6) 应仅连 0,1
	var s6: Array = adj[6]
	_tally("S6 连 S0", s6.has(0))
	_tally("S6 连 S1", s6.has(1))
	_tally("S6 不连 S2", not s6.has(2))
	_tally("S6 不连 S3", not s6.has(3))
	_tally("S6 不连 S4", not s6.has(4))
	_tally("S6 不连 S5", not s6.has(5))
	_tally("S6 不连 S7", not s6.has(7))
	# S7(7) 应仅连 2,4
	var s7: Array = adj[7]
	_tally("S7 连 S2", s7.has(2))
	_tally("S7 连 S4", s7.has(4))
	_tally("S7 不连 S0", not s7.has(0))
	_tally("S7 不连 S1", not s7.has(1))
	_tally("S7 不连 S3", not s7.has(3))
	_tally("S7 不连 S5", not s7.has(5))
	_tally("S7 不连 S6", not s7.has(6))

	# ---- E-G8-5 六槽诱导子图守恒（Geo8 前六槽 == Geo6 同配置）----
	_log("\n---- [E-G8-5] 六槽诱导子图守恒（对照基线）----")
	var sub_ok := true
	for types in [["Arrow", "Arrow", "Arrow", "Arrow", "Arrow", "Arrow"],
				  ["Cannon", "Cannon", "Cannon", "Cannon", "Cannon", "Cannon"],
				  ["Frost", "Frost", "Frost", "Frost", "Frost", "Frost"],
				  ["Arrow", "Cannon", "Frost", "Arrow", "Cannon", "Frost"]]:
		var a6: Array = g6.links(types, "substantial")
		# Geo8 前六槽：构造 8 槽类型（后两槽空置），取前六邻接
		var t8: Array = types.duplicate()
		t8.append(""); t8.append("")
		var a8: Array = g8.links(t8, "substantial")
		for i in range(6):
			var la: Array = a6[i]
			var lb: Array = a8[i]
			if la.size() != lb.size():
				sub_ok = false
			else:
				la.sort(); lb.sort()
				for k in range(la.size()):
					if int(la[k]) != int(lb[k]):
						sub_ok = false
	_check("四种塔型下前六槽邻接 == Geo6", 1.0 if sub_ok else 0.0, 1.0, 1e-12)

	# ---- E-G8-6 暴露楔形（径向口径 asin(AGGRO_R/r)/π）----
	_log("\n---- [E-G8-6] 暴露楔形 ----")
	var core := Vector2(28.0, 28.0)
	var r6: float = _dist(core, g8.slots[6])
	var r7: float = _dist(core, g8.slots[7])
	var wedge6: float = asin(clampf(AGGRO_R / r6, 0.0, 1.0)) / PI
	var wedge7: float = asin(clampf(AGGRO_R / r7, 0.0, 1.0)) / PI
	# 先验半径 ≈ 26（附录标注值，坐标四舍五入后有 ~1e-3 偏差）
	_check("S6 半径 ≈ 26", r6, 26.0, 1e-2)
	_check("S7 半径 ≈ 26", r7, 26.0, 1e-2)
	# 🔴 R-9：对照**外部真值** 11.25%（§2.4.1b），而非用 asin(9/r6)/π 自己比自己。
	#   容差 5e-4（坐标四舍五入偏差）——几何常量被误改则翻红。
	_check("S6 暴露楔形 = 11.25%（§2.4.1b 外部真值）", wedge6, WEDGE_S6_S7_EXT, 5e-4)
	_check("S7 暴露楔形 = 11.25%（§2.4.1b 外部真值）", wedge7, WEDGE_S6_S7_EXT, 5e-4)
	# 附：S6/S7 两远哨对称（有意义的性质，独立于闭式解）
	_check("S6/S7 暴露楔形对称（|Δ| 容差）", wedge6, wedge7, 1e-4)
	_log("   S6/S7 半径 = %.4f / %.4f · 暴露楔形 = %.4f%% / %.4f%%（外部真值 %.2f%%）"
			% [r6, r7, wedge6 * 100.0, wedge7 * 100.0, WEDGE_S6_S7_EXT * 100.0])

	# ---- E-G8-7 R-CS4：最外圈 ≤ 最内圈 1/2 ----
	_log("\n---- [E-G8-7] R-CS4 相对安全（外圈 ≤ 内圈 1/2）----")
	var wedges: Array = []
	for i in range(8):
		var r: float = _dist(core, g8.slots[i])
		wedges.append({"i": i, "r": r, "w": asin(clampf(AGGRO_R / r, 0.0, 1.0)) / PI})
	var w_max: float = -1.0
	var w_min: float = 2.0
	for w in wedges:
		w_max = maxf(w_max, float(w["w"]))
		w_min = minf(w_min, float(w["w"]))
	var ratio: float = w_min / w_max if w_max > 0.0 else 0.0
	_tally("最外圈/最内圈 = %.4f ≤ 0.5" % ratio, ratio <= 0.5)

	# ---- E-G8-8 最小塔间距 ≥ 9.5 ----
	_log("\n---- [E-G8-8] 最小塔间距 ----")
	var min_sep: float = 1e9
	for i in range(8):
		for j in range(i + 1, 8):
			min_sep = minf(min_sep, g8.dist[i][j])
	_check("最小塔间距 ≥ 9.5", min_sep, 10.144, 1e-3)

	# ---- E-G8-9 最大角空隙 ≤ 90° ----
	_log("\n---- [E-G8-9] 最大角空隙 ----")
	var ang: Array = []
	for i in range(8):
		var d2: Vector2 = g8.slots[i] - core
		ang.append({"i": i, "a": atan2(d2.y, d2.x)})
	ang.sort_custom(func(x, y): return float(x["a"]) < float(y["a"]))
	var max_gap: float = 0.0
	for i in range(8):
		var a1: float = float(ang[i]["a"])
		var a2: float = float(ang[(i + 1) % 8]["a"])
		var gap: float = a2 - a1
		if i == 7:
			gap += 2.0 * PI          # 环绕
		max_gap = maxf(max_gap, gap)
	var max_gap_deg: float = rad_to_deg(max_gap)
	_check("最大角空隙 ≤ 90°", max_gap_deg, 74.165, 1.0)
	_log("   最大角空隙 = %.3f°" % max_gap_deg)

	# ---- E-G8-10 塔位在地图内 + 离出生环安全余量 ----
	_log("\n---- [E-G8-10] 地图边界与出生环余量 ----")
	var in_map_ok := true
	var min_ring_margin: float = 1e9
	for i in range(8):
		var p: Vector2 = g8.slots[i]
		if p.x < MAP_LO or p.x > MAP_HI or p.y < MAP_LO or p.y > MAP_HI:
			in_map_ok = false
		var r: float = _dist(core, p)
		min_ring_margin = minf(min_ring_margin, SPAWN_RING - r)
	_check("全部塔位落在 0..55 地图内", 1.0 if in_map_ok else 0.0, 1.0, 1e-12)
	_check("离出生环最小余量 ≥ 27", min_ring_margin, 27.62, 1e-3)

	_log("\n===================================================================")
	_log("八槽 E8-A 几何验收汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	_log("===================================================================")
	return _fail == 0


func _dist(a: Vector2, b: Vector2) -> float:
	var dx: float = a.x - b.x
	var dy: float = a.y - b.y
	return sqrt(dx * dx + dy * dy)
