extends RefCounted
##
## 自由摆放网格（**正六边形 / flat-top 平顶**）—— 逻辑层（落子判定）与渲染层（网格绘制 / 命中）
## **共用的唯一几何来源**。
##
## 🔴 为什么单独一个文件：
##   网格参数一旦在 UI 和 runtime 里各写一份就会漂移。上一轮 `run_slice4_scene_smoke.gd`
##   的 `SLOT_W/SLOT_H` 是手抄的第二份数字，实现改成 244 时忘了改测试 → 静默 45/46。
##   这里把「格尺寸 / 可建区 / 吸附规则 / 顶点」收敛成常量 + 纯函数，两边都调它。
##
## 设计口径（玩家已拍板的三条）：
##   ① 保留径向竞技场（核心居中、怪从外沿直插）—— 不推翻 GDD 的空间设计；
##   ② 塔位置自由，但**吸附格点** —— 视觉对齐、判定无歧义、不会出现两塔半重叠；
##   ③ 可建范围由战场边界与活动地图岩脊共同决定；阵地表只描述视觉地形，不限制摆塔。
##      圆盘内除核心禁建区与岩脊障碍外均可建。
##
## 🔴 为什么是六边形而不是方格（玩家明确要求改掉方格）：
##   · **等距**：方格到 4 个邻格的距离是 a、到 4 个斜角邻格是 1.414a —— 斜向埋塔会"更便宜"，
##     玩家会**自发**只走对角线，塔阵退化成菱形条纹；六边形 6 个邻格距离全等（√3R），
##     不存在这个"免费的方向"。
##   · **各向同性**：径向战场上威胁来自 360°，方格自带 4 重方向偏好，六边形是 6 重 ——
##     更接近"圆形战场"的事实。
##   · 视觉上蜂窝状也与「能量格栅」的 SF 调性一致（art-bible §2.2 的耀青细线）。
##
## 🔴 尺寸怎么定的（这不是随手取的数）：
##   正六边形面积 = (3√3/2)·R²。取 R = 1.55 → 面积 6.242 u²，
##   与**改前的方格 2.5×2.5 = 6.25 u² 基本相等** → 全盘格数 ≈ 965 不变、平均塔距不变、
##   `tower_cap` 的可建空间不被这次改形偷偷改变。改格形 = 只改"方向的公平性"，不改"容量"。
##
## 🔴 径向模式下**不需要路径避让**：怪走的是「出生点 → 核心」的直线，不是 PATH 折线，
##   且 MVP 无碰撞体积（怪穿塔而过）。照搬 PATH 模式的 `dist_to_path` 会让半个盘都不可建 ——
##   那是路径模型的遗留约束，不是这个战场的事实。
##
## ⚠️ GDScript 坑：
##   · 不写 `class_name` —— headless `--script` 不先做编辑器导入，全局类名表可能没生成。
##     一律 `preload`。
##   · `int / int` 是整数除法 → 格数换算一律 `float()` 或 `ceilf`。
##   · **轴向坐标（axial q,r）不是世界坐标**：q 是"斜列号"，r 沿 60° 方向。
##     任何"看起来应该在正上方"的直觉在这里都不成立 —— 一律走 `cell()` / `cell_of()` 换算，
##     不要在调用处自己乘格距（那正是上一轮 SLOT_W/SLOT_H 踩的坑）。
##

const _SpaceModel := preload("res://scripts/geo/space_model.gd")

# ---------------------------------------------------------------------------
#  网格参数
# ---------------------------------------------------------------------------
## 外接圆半径（格心 → 顶点，u）。55×55 逻辑图 / 出生环 55 → 一格约等于「半个塔身」，
## 既不会碎到点不准，也不会粗到失去"自由"的观感。
const HEX_R := 1.55
## 半宽 = R（平顶六边形的左右**顶点**在 ±R）。
const HEX_HALF_W := HEX_R
## 半高 = 边心距 = (√3/2)R（平顶六边形的上下是**边**，不是顶点）。
const HEX_HALF_H := HEX_R * 0.8660254037844386
## 列距 = 1.5R（相邻两列格心的 x 差）。**不是 2R** —— 平顶六边形横向是交错的。
const COL_STEP := HEX_R * 1.5
## 行距 = √3R（相邻行格心的 y 差），同时等于「相邻格心距离」。
const ROW_STEP := HEX_R * 1.7320508075688772
## 单格面积 = (3√3/2)R² ≈ 6.242 u²（≈ 改前方格 2.5² = 6.25，见文件头）。
const CELL_AREA := 2.598076211353316 * HEX_R * HEX_R

## 核心禁建半径（u）。核心本体外接圆 1.90u，留 2u 余量 → 贴脸堆塔不是"自由"而是"唯一解"。
const CORE_BAN_R := 4.0
## 可建外径（u）。出生环 55 − 11：让玩家能在中圈布防，但不给"怪一出生就挨打"的白嫖位。
const FIELD_R := 44.0

# ---------------------------------------------------------------------------
#  阵地表「三裂环」（design/gdd/scene-map.md §5.5）
# ---------------------------------------------------------------------------
## 🔴 为什么要有阵地：改这个文件之前先读 scene-map.md §3 —— 塔的**输出与位置无关**
##   （`wave_director` 按 `t_remain` 聚合结算，覆盖走路径常量），所以「965 格空圆盘」
##   的最优解是**全堆最外圈挤成一团**（曝光 6.6% 最低 + E=9 最密，两个轴同时最优）。
##   把可建格收敛到 17 格，才是让"站哪"重新变成决策的唯一办法。
##
## 🔴 格子用**轴向坐标**写死（不是极坐标现算）：吸附后的真实格心必须可复现，
##   一旦用「锚点 + 半径筛格」在运行时推导，台间距会随吸附误差漂移。
##   下表已用 `BuildGrid.cell()` 反算并实测（见 §5.5 与 `tests/test_suite_radial.gd` §地图）。
##
## 🔴 跨台约束按**最近格距**（不是台中心距）验：Lance 链接阈值 = 0.65·(Ri+Rj) ≤ 28.6u。
##   实测最紧一对 P1–N1 = 30.25u（余量 1.65u）。按中心距验会漏掉 26.4u 的跨台邻格。
const SITES: Array = [
	{
		"id": "P1", "name": "南台", "shape": "2×3", "r": 26.0, "theta": 93.0,
		"cells": [
			Vector2i(-1, 9), Vector2i(0, 9), Vector2i(-1, 10), Vector2i(0, 10),
			Vector2i(-1, 11), Vector2i(0, 11),
		],
	},
	{
		"id": "P2", "name": "西台", "shape": "十字", "r": 22.0, "theta": 209.0,
		"cells": [
			Vector2i(-8, 0), Vector2i(-7, 0), Vector2i(-9, 0), Vector2i(-8, 1), Vector2i(-8, -1),
		],
	},
	{
		"id": "P3", "name": "北台", "shape": "1×3", "r": 30.0, "theta": 320.0,
		"cells": [Vector2i(10, -13), Vector2i(10, -12), Vector2i(10, -11)],
	},
	{
		"id": "N1", "name": "东孤台", "shape": "单格", "r": 40.0, "theta": 42.0,
		"cells": [Vector2i(13, 3)],
	},
	{
		"id": "N2", "name": "北孤台", "shape": "单格", "r": 41.7, "theta": 266.8,
		"cells": [Vector2i(-1, -15)],
	},
	{
		"id": "N3", "name": "西孤台", "shape": "单格", "r": 41.7, "theta": 146.8,
		"cells": [Vector2i(-15, 16)],
	},
]

## 格心 → 阵地 id 的缓存（纯函数结果，只读；`static var` 只在这里当 memo 用）。
##   🆕 换图时按 `active_map_id` 重建（缓存签名含 map_id，见 `site_index()`）。
static var _cell_site: Dictionary = {}
static var _cell_site_map: String = ""

const _SQRT3 := 1.7320508075688772


## 🆕 活动阵地表（默认 = const SITES；切图 = 变体表，`sites` 为 null 时复用基准）。
##   🔴 `sites()` 对「复用基准」的变体返回 **null** —— 不能直接赋给 `Array` 类型变量
##     （Godot 会抛 "Trying to assign Nil to Array"，函数中断并返回 null，调用方再拿到
##      null 继续画 → 实机原生崩溃 0xc0000005）。这里必须用 `typeof` 判空。
static func active_sites() -> Array:
	var mid: String = _SpaceModel.active_map_id
	if mid == "tri-fissure":
		return SITES
	var s = _SpaceModel._MapVariants.sites(mid)
	if typeof(s) != TYPE_ARRAY or s.is_empty():
		return SITES
	return s


## 战场核心（径向模式的几何中心）。网格以它为原点对齐 → 左右上下对称。
static func core() -> Vector2:
	return _SpaceModel.RADIAL_CORE


## 轴向坐标 (q, r) → 格心世界坐标（平顶布局）。
##   x = 1.5R·q
##   y = √3R·(r + q/2)
## 🔴 `q/2` 这一项就是"列交错"，漏掉它会得到一个歪掉的斜网格（顶点对不上边）。
static func cell(q: int, r: int) -> Vector2:
	var c := core()
	return Vector2(
		c.x + COL_STEP * float(q),
		c.y + ROW_STEP * (float(r) + 0.5 * float(q)),
	)


## 世界坐标 → 最近格的轴向坐标。立方坐标取整（cube round）：
## 先四舍五入三分量，再把**误差最大**的那个分量改成另外两个的相反数和 —— 保证 q+r+s = 0。
static func cell_of(p: Vector2) -> Vector2i:
	var x := p.x - core().x
	var y := p.y - core().y
	var fq := (2.0 / 3.0 * x) / HEX_R
	var fr := (-1.0 / 3.0 * x + (1.0 / _SQRT3) * y) / HEX_R
	return _round_axial(fq, fr)


static func _round_axial(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var q := roundf(fq)
	var r := roundf(fr)
	var s := roundf(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## 世界坐标 → 最近格心。
static func snap(p: Vector2) -> Vector2:
	var k := cell_of(p)
	return cell(k.x, k.y)


## 该格心能否建塔（只看几何；塔数上限 / 同格占用由 runtime 判）。
##   PATH 模式或布局关闭 → 圆盘规则（逐位回到改前口径）。
##   RADIAL + 布局开启  → 圆盘内除核心与活动地图岩脊外均可建。
static func buildable(p: Vector2) -> bool:
	var d := p.distance_to(core())
	if d < CORE_BAN_R or d > FIELD_R:
		return false
	if sites_active() and _is_obstacle(p):
		return false
	return true


static func _is_obstacle(p: Vector2) -> bool:
	var offset := p - core()
	var radius := offset.length()
	var angle := fposmod(rad_to_deg(offset.angle()), 360.0)
	for ridge in _SpaceModel.active_ridges():
		if radius < float(ridge["r0"]) or radius > float(ridge["r1"]):
			continue
		var a0 := float(ridge["a0"])
		var a1 := float(ridge["a1"])
		var test_angle := angle
		if a1 > 360.0 and test_angle < a0:
			test_angle += 360.0
		if test_angle >= a0 and test_angle <= a1:
			return true
	return false


## 阵地是否生效（RADIAL + 布局开关）。PATH 模式恒 false → 网格 / 可建区逐位不变。
static func sites_active() -> bool:
	return _SpaceModel.mode == _SpaceModel.Mode.RADIAL and _SpaceModel.layout_enabled


## 格心所属阵地 id（"" = 不在任何阵地）。吸附容差由格划分天然给出（同格即同阵地）。
static func site_id_of(p: Vector2) -> String:
	var idx := site_index()
	var k: Vector2i = cell_of(p)
	return String(idx.get(k, ""))


## 阵地 id → 该阵地的格心世界坐标（按表内顺序）。
static func site_cells(id: String) -> Array:
	var out: Array = []
	for s in active_sites():
		if String(s["id"]) != id:
			continue
		for c in s["cells"]:
			out.append(cell(c.x, c.y))
	return out


## 阵地 id → 落位锚点（表内第一格；起手塔用它）。
static func site_anchor(id: String) -> Vector2:
	var cs := site_cells(id)
	return cs[0] if not cs.is_empty() else snap(core())


## 全部阵地格心（世界坐标，17 个；布局关闭时返回空数组）。
static func site_points() -> Array:
	var out: Array = []
	for s in active_sites():
		for c in s["cells"]:
			out.append(cell(c.x, c.y))
	return out


## 格心 → 阵地 id 索引（惰性构建一次；按 `active_map_id` 签名，换图自动重建）。
static func site_index() -> Dictionary:
	var mid: String = _SpaceModel.active_map_id
	if _cell_site_map != mid:
		_cell_site_map = mid
		_cell_site = {}
		for s in active_sites():
			var id := String(s["id"])
			for c in s["cells"]:
				_cell_site[c] = id
	return _cell_site


## 两个位置是否同格。六边形有确定的格划分 → 直接比轴向取整，**不用距离容差**
## （容差法在六边形上会误判：格心距离 ROW_STEP，但格边界不是等距的）。
static func same_cell(a: Vector2, b: Vector2) -> bool:
	return cell_of(a) == cell_of(b)


## 格心的 6 个顶点（世界坐标，平顶：0° / 60° / … / 300°）。
## 顺序固定为逆时针 —— 渲染层与命中判定都靠它，不要各自再算一遍。
static func corners(p: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(6)
	for i in range(6):
		var a := TAU * float(i) / 6.0
		out[i] = p + Vector2(cos(a), sin(a)) * HEX_R
	return out


## 6 个相邻格的轴向偏移，供测试与探针验"6 个邻格距离全等"。
## 🔴 写成函数而不是 `const` 数组：headless 脚本对常量表达式的求值路径更迂回，
##   而这里只有测试会调，每次现造一个 6 元数组的代价可以忽略。
static func neighbors() -> Array:
	return [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
	]


# ---------------------------------------------------------------------------
#  网格绘制
# ---------------------------------------------------------------------------
## 网格线段（世界坐标，**成对** `[a0,b0, a1,b1, …]`，直接喂 `draw_multiline`）。
##
## 🔴 为什么返回扁平的 PackedVector2Array 而不是 `Array<Array<Vector2>>`：
##   整盘约 970 格 × 6 条边 ≈ 2900 段。逐段 `draw_line` 是每帧 2900 次 draw call；
##   `draw_multiline` 一次调用画完。**逐格 `draw_rect` 更不可行**（改前方格版本就是线段法）。
##
## 🔴 去重：一条边被两个相邻格各算一次 → 用「端点量化后排序」当 key 去重，避免叠画加深。
## 🔴 裁剪：每段裁到可建圆内 → 边缘是**被圆切断的半条边**，既不过界也不留空档。
static func grid_edges() -> PackedVector2Array:
	var out := PackedVector2Array()
	var seen := {}
	var c := core()
	var qn := _q_bound()
	var rn := _r_bound()
	for q in range(-qn, qn + 1):
		for r in range(-rn, rn + 1):
			var cc := cell(q, r)
			if not buildable(cc):
				continue                      # 非可建格不参与网格线绘制
			var cs := corners(cc)
			for i in range(6):
				var a: Vector2 = cs[i]
				var b: Vector2 = cs[(i + 1) % 6]
				var key := _edge_key(a, b)
				if seen.has(key):
					continue
				seen[key] = true
				var seg := _clip_disc(a, b, c, FIELD_R)
				if seg.is_empty():
					continue
				out.append(seg[0])
				out.append(seg[1])
	return out


## 阵地网格线：只画 17 个阵地格（含格间分隔线 + 外沿）。
##   17 格 × 6 边 ≈ 102 段，比整盘 3660 段少两个数量级 —— 这本身就是「收敛」的视觉证据。
static func _site_edges() -> PackedVector2Array:
	var out := PackedVector2Array()
	var seen := {}
	var c := core()
	for s in active_sites():
		for k in s["cells"]:
			var cc := cell(k.x, k.y)
			var cs := corners(cc)
			for i in range(6):
				var a: Vector2 = cs[i]
				var b: Vector2 = cs[(i + 1) % 6]
				var key := _edge_key(a, b)
				if seen.has(key):
					continue
				seen[key] = true
				var seg := _clip_disc(a, b, c, FIELD_R)
				if seg.is_empty():
					continue
				out.append(seg[0])
				out.append(seg[1])
	return out


## 网格覆盖半径（供 UI 定包围盒余量，避免网格描边被裁）。
static func extent() -> float:
	return FIELD_R


## 全部合法格心（世界坐标）。仅测试与探针用 —— 运行时不会遍历全盘：
## 落子是「点哪判哪」（O(1) 吸附 + O(塔数) 查重），不做全盘枚举。
static func all_cells() -> Array:
	var out: Array = []
	var qn := _q_bound()
	var rn := _r_bound()
	for q in range(-qn, qn + 1):
		for r in range(-rn, rn + 1):
			var p := cell(q, r)
			if buildable(p):
				out.append(p)
	return out


# ---------------------------------------------------------------------------
#  内部
# ---------------------------------------------------------------------------
static func _q_bound() -> int:
	return int(ceilf(FIELD_R / COL_STEP)) + 1


## r 的上界要额外加 `q_max/2`：y 的偏移是 √3R(r + q/2)，q 越大 r 的可取范围越偏。
static func _r_bound() -> int:
	return int(ceilf(FIELD_R / ROW_STEP + float(_q_bound()) * 0.5)) + 1


## 边的去重 key：两端点各自量化到 0.01u，再按字典序排好（与端点顺序无关）。
static func _edge_key(a: Vector2, b: Vector2) -> String:
	var ka := "%d:%d" % [int(roundf(a.x * 100.0)), int(roundf(a.y * 100.0))]
	var kb := "%d:%d" % [int(roundf(b.x * 100.0)), int(roundf(b.y * 100.0))]
	if ka < kb:
		return ka + "|" + kb
	return kb + "|" + ka


## 线段 [a,b] 裁剪到圆 (c, r) 内。无交且在外 → 空数组；全在内部 → 原样返回。
static func _clip_disc(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array:
	var d := b - a
	var f := a - c
	var aa := d.dot(d)
	if aa < 1e-9:
		return []
	var bb := 2.0 * f.dot(d)
	var cc := f.dot(f) - r * r
	var disc := bb * bb - 4.0 * aa * cc
	if disc <= 0.0:
		return []                   # 无交点（含相切）→ 不画
	var sq := sqrt(disc)
	var t0 := (-bb - sq) / (2.0 * aa)
	var t1 := (-bb + sq) / (2.0 * aa)
	t0 = maxf(t0, 0.0)
	t1 = minf(t1, 1.0)
	if t1 <= t0:
		return []
	return [a + d * t0, a + d * t1]
