extends RefCounted
##
## 自由摆放网格 —— 逻辑层（落子判定）与渲染层（网格绘制 / 命中）**共用的唯一几何来源**。
##
## 🔴 为什么单独一个文件：
##   网格参数一旦在 UI 和 runtime 里各写一份就会漂移。上一轮 `run_slice4_scene_smoke.gd`
##   的 `SLOT_W/SLOT_H` 是手抄的第二份数字，实现改成 244 时忘了改测试 → 静默 45/46。
##   这里把「格距 / 可建区 / 吸附规则」收敛成常量 + 纯函数，两边都调它。
##
## 设计口径（玩家已拍板的三条）：
##   ① 保留径向竞技场（核心居中、怪从外沿直插）—— 不推翻 GDD 的空间设计；
##   ② 塔位置自由，但**吸附格点** —— 视觉对齐、判定无歧义、不会出现两塔半重叠；
##   ③ 圆盘内除核心禁建区皆可建；塔数上限与「槽位数」解耦（`cfg["tower_cap"]`）。
##
## 🔴 径向模式下**不需要路径避让**：怪走的是「出生点 → 核心」的直线，不是 PATH 折线，
##   且 MVP 无碰撞体积（怪穿塔而过）。照搬 PATH 模式的 `dist_to_path` 会让半个盘都不可建 ——
##   那是路径模型的遗留约束，不是这个战场的事实。
##
## ⚠️ GDScript 坑：
##   · 不写 `class_name` —— headless `--script` 不先做编辑器导入，全局类名表可能没生成。
##     一律 `preload`。
##   · `int / int` 是整数除法 → 格数换算一律 `float()` 或 `ceilf`。
##

const _SpaceModel := preload("res://scripts/geo/space_model.gd")

# ---------------------------------------------------------------------------
#  网格参数
# ---------------------------------------------------------------------------
## 格距（世界单位 u）。55×55 逻辑图 / 出生环 55 → 一格约等于「半个塔身」，
## 既不会碎到点不准，也不会粗到失去"自由"的观感。
const CELL := 2.5
## 核心禁建半径（u）。核心本体外接圆 1.90u，留 2u 余量 → 贴脸堆塔不是"自由"而是"唯一解"。
const CORE_BAN_R := 4.0
## 可建外径（u）。出生环 55 − 11：让玩家能在中圈布防，但不给"怪一出生就挨打"的白嫖位。
const FIELD_R := 44.0


## 战场核心（径向模式的几何中心）。网格以它为原点对齐 → 左右上下对称。
static func core() -> Vector2:
	return _SpaceModel.RADIAL_CORE


## 世界坐标 → 最近格点。以核心为原点取整，保证核心落在格点上、图案对称。
static func snap(p: Vector2) -> Vector2:
	var c := core()
	return Vector2(
		c.x + roundf((p.x - c.x) / CELL) * CELL,
		c.y + roundf((p.y - c.y) / CELL) * CELL,
	)


## 该格点能否建塔（只看几何；塔数上限 / 同格占用由 runtime 判）。
static func buildable(p: Vector2) -> bool:
	var d := p.distance_to(core())
	return d >= CORE_BAN_R and d <= FIELD_R


## 两个格点是否同格（判定"这一格已有塔"）。容差取 1/4 格 —— 吸附之后实际总是 0，
## 留余量只为防御浮点直接比较。
static func same_cell(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) <= CELL * 0.25


## 网格线（世界坐标线段 `[Vector2, Vector2]` 的数组），已裁剪到可建圆内。
## 🔴 返回**线段**而不是逐格矩形：整盘约 900 格，逐格 draw_rect 每帧 900 次调用太贵；
##    34 + 34 条线画完整个网格，且线条在圆外自动截断。
static func grid_segments() -> Array:
	var out: Array = []
	var c := core()
	var n := int(ceilf(FIELD_R / CELL))
	var r := FIELD_R
	for k in range(-n, n + 1):
		var off := float(k) * CELL
		# 竖线 x = c.x + off → 与可建圆的两个交点
		var dx := off
		if absf(dx) < r:
			var dy := sqrt(r * r - dx * dx)
			out.append([Vector2(c.x + dx, c.y - dy), Vector2(c.x + dx, c.y + dy)])
		# 横线 y = c.y + off
		if absf(off) < r:
			var dx2 := sqrt(r * r - off * off)
			out.append([Vector2(c.x - dx2, c.y + off), Vector2(c.x + dx2, c.y + off)])
	return out


## 网格覆盖半径（供 UI 定包围盒余量，避免网格描边被裁）。
static func extent() -> float:
	return FIELD_R


## 全部合法格点（世界坐标）。仅测试与探针用 —— 运行时不会遍历全盘：
## 落子是「点哪判哪」（O(1) 吸附 + O(塔数) 查重），不做全盘枚举。
static func all_cells() -> Array:
	var out: Array = []
	var c := core()
	var n := int(ceilf(FIELD_R / CELL))
	for gy in range(-n, n + 1):
		for gx in range(-n, n + 1):
			var p := Vector2(c.x + float(gx) * CELL, c.y + float(gy) * CELL)
			if buildable(p):
				out.append(p)
	return out
