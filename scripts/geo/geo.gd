class_name Geo
extends RefCounted
const _TowerData := preload("res://scripts/data/tower_data.gd")
##
## 地图几何：塔位坐标 → 覆盖值 / 距离矩阵 / 链接图
##   移植自 design/phase2/numeric-sim/corebound_sim_v03.py:69-144
##
## ⚠️ Godot 坑记录（这几条都会静默改结果，改这个文件前先读完）：
##   1) GDScript 的 `int / int` 是**整数除法**。路径采样里的 `t = k / m`、`int(samples*L/total)`
##      必须显式转 float，否则采样点数会变 → CoverageScore 全表偏移。
##   2) Python 的 `math.dist / math.hypot` 与 Godot 的 `Vector2.distance_to()` 未必逐位相同
##      （相差 1 ULP 级）。这里统一走 `sqrt(dx*dx+dy*dy)`，与 v03 的 `_pt_seg_dist` 同式。
##   3) Dictionary 的 key 用 String（`"slot|ctype"`），不用 Array —— Array 作 key 的
##      哈希/相等语义在 Godot 4 里不如 String 稳，且慢。
##

# ---- 路径（v03 L69-70）----
const PATH: Array = [
	Vector2(0.0, 25.0), Vector2(12.0, 25.0), Vector2(12.0, 48.0),
	Vector2(35.0, 48.0), Vector2(35.0, 25.0), Vector2(55.0, 25.0),
]
const COVERAGE_SAMPLES := 1500

var slots: Array = []      # Array[Vector2]
var n := 0
var dist: Array = []       # dist[i][j] : float
var cov: Dictionary = {}   # "slot|ctype" -> float
var n_path_pts := 0
var path_len := 0.0

var _path_pts: Array = []  # Array[Vector2]


func _init(p_slots: Array) -> void:
	slots = p_slots.duplicate()
	n = slots.size()
	_build_path_samples()
	_build_dist()
	_build_cov()


# ---------------------------------------------------------------------------
# 路径采样 —— 对应 v03 `_sample_path()` (L86-98)
# ---------------------------------------------------------------------------
func _build_path_samples() -> void:
	var segs: Array = []
	var total := 0.0
	for i in range(PATH.size() - 1):
		var a: Vector2 = PATH[i]
		var b: Vector2 = PATH[i + 1]
		var L := _dist(a, b)
		segs.append([a, b, L])
		total += L
	path_len = total

	_path_pts = []
	for seg in segs:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		# ★ int(1500.0 * L / total)：先 float 运算再截断（Python `int()` 同语义）
		var m: int = int(float(COVERAGE_SAMPLES) * float(seg[2]) / total)
		m = maxi(m, 2)
		for k in range(m):
			# ★ t = k / m 必须是 float 除法
			var t := float(k) / float(m)
			_path_pts.append(Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t))
	n_path_pts = _path_pts.size()


# ---------------------------------------------------------------------------
# 距离矩阵 —— 对应 v03 `Geo.__init__` (L116-119)
# ---------------------------------------------------------------------------
func _build_dist() -> void:
	dist = []
	for i in range(n):
		dist.append([])
		for j in range(n):
			dist[i].append(_dist(slots[i], slots[j]))


func _dist(a: Vector2, b: Vector2) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return sqrt(dx * dx + dy * dy)


## 🆕 自由摆放：运行时追加一个塔位坐标，返回新槽位索引。
##
## 🔴 为什么需要它：改造前塔位是编译期常量（`SLOTS6` 六个固定点），`t.slot` 既是主键
##    又是坐标索引。玩家要自由摆塔，就得让「槽位表」在运行时增长。
##
## 🔴 金标本零扰动：本方法**只有玩家路线**（`shop_runtime`）调用；金标本引擎
##    （`run_loop` / `wave_sim` / `shop_ai`）与 300 局 MC 从不追加槽位
##    → 默认的 6 槽 `dist` / `cov` / `links` 逐位不变。
##
## 增量维护三个派生结构，避免每次摆塔重建全表：
##   · `slots` / `n`  —— 追加一位
##   · `dist`         —— 追加一行一列（O(n)，不是 O(n²) 重建）
##   · `cov`          —— 只补新槽那一列（实机读不到 cov，纯粹为了一致性）
func add_slot(pos: Vector2) -> int:
	var idx := slots.size()
	slots.append(pos)
	n = slots.size()
	# dist：老行各补一格，再追加新行
	for i in range(dist.size()):
		dist[i].append(_dist(slots[i], pos))
	var row: Array = []
	for j in range(n):
		row.append(_dist(pos, slots[j]))
	dist.append(row)
	# cov：只补这个槽
	for ctype in _TowerData.TOWERS:
		cov[_cov_key(idx, ctype)] = coverage_of(pos, _TowerData.tower_rng(ctype))
	return idx


## 安全取距离：`dist` 若因历史原因短于 `n`（序列化 / 手工构造），退回现场计算。
## 正常路径不会走到兜底分支 —— 它只是让 `links()` 在槽位表增长后不会硬崩。
func _dist_at(i: int, j: int) -> float:
	if i < dist.size() and j < (dist[i] as Array).size():
		return float(dist[i][j])
	if i < slots.size() and j < slots.size():
		return _dist(slots[i], slots[j])
	return INF


# ---------------------------------------------------------------------------
# CoverageScore —— 对应 v03 `coverage_of()` (L104-107)
# ---------------------------------------------------------------------------
func _build_cov() -> void:
	cov = {}
	for ctype in _TowerData.TOWERS:
		var radius := _TowerData.tower_rng(ctype)
		for s in range(n):
			cov[_cov_key(s, ctype)] = coverage_of(slots[s], radius)


static func _cov_key(slot: int, ctype: String) -> String:
	return "%d|%s" % [slot, ctype]


func coverage_of(slot_xy: Vector2, radius: float) -> float:
	var hit := 0
	for p in _path_pts:
		if _dist(p, slot_xy) <= radius:
			hit += 1
	# ★ float 除法
	return float(hit) / float(_path_pts.size())


func cov_at(slot: int, ctype: String) -> float:
	return float(cov[_cov_key(slot, ctype)])


# ---------------------------------------------------------------------------
# 链接图 —— 对应 v03 `Geo.links()` (L125-140)
#   tower_types: 长度 = 塔位数，空位用 "" 表示（Python 用 None）
#   rule: "any"(f=1.0) | 其它(含 "substantial")(f=0.65)
# ---------------------------------------------------------------------------
func links(tower_types: Array, rule: String = "any") -> Array:
	var m := tower_types.size()
	var R: Array = []
	for i in range(m):
		var tname := String(tower_types[i])
		R.append(_TowerData.tower_rng(tname) if tname != "" else 0.0)

	var f := 1.0 if rule == "any" else 0.65

	var adj: Array = []
	for i in range(m):
		adj.append([])

	for i in range(m):
		if String(tower_types[i]) == "":
			continue
		for j in range(m):
			if i == j or String(tower_types[j]) == "":
				continue
			# 🆕 走 `_dist_at` 而不是 `dist[i][j]`：自由摆放后槽位表运行时增长，
			#    `links()` 的调用方（`damage_engine`）按 `geo.n` 建数组，两者可能短暂不同步。
			#    正常路径两者一致，`_dist_at` 直接读预计算值 → 逐位不变。
			if _dist_at(i, j) <= f * (float(R[i]) + float(R[j])):
				adj[i].append(j)
	return adj
