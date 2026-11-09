class_name PathGeometry
extends RefCounted
##
## 路径几何 `PathGeometry` —— 🔴 **F-3 关闭**（GDD `wave-spawner` v0.2 §2.2 / §3.1）
##
## 权威来源（一字不改）：sim 真身 `corebound_sim_v03.py:69`
##   PATH = [(0,25), (12,25), (12,48), (35,48), (35,25), (55,25)]
##   L = 101.0 · 5 段 12/23/23/23/20 · 核心 (55,25) = 路径终点（方案 A，core-defense §5.4.1）
##
## 🔴 三条硬性纪律：
##   1. **静态**：本文件全是 `static` 纯函数 / const。路径与暴露度在**地图加载时算一次**，
##      存进 `Slot` 的 `d_path` / `exposure_arc` / `exposure_intervals` 三字段，
##      **运行时零开销、不进帧循环**（W-C3 红线，GDD §2.6.3）。
##   2. 🔴 **不用 `PathFollow2D`**：它是 2D-only，本项目是 3D 正交相机 + XZ 地面
##      （`art-bible` §6.1）。`s`（沿路径弧长）是**权威状态量**。
##   3. 距离一律 `sqrt(dx*dx + dy*dy)`，与 v03 的 `_pt_seg_dist` 同式
##      （`Vector2.distance_to()` 与 Python `math.dist` 可能差 1 ULP）。
##
## 暴露度两张表（`AGGRO_R = 9.0`，GDD §5.3，可直接抄进单测）：
##   d_path       6.00 / 8.00 / 5.00 / 8.00 / 10.82 / 13.00
##   ExposureArc 21.67 / 8.25 / 14.96 / 8.25 /    0  /    0   · union = 53.13（52.6%）
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → 插值 / 归一化一律显式 `float()`。
##   G3 `static var` 跨场景共享 → 本文件只放 const 与 static 纯函数，无可变状态。
##   G5 `maxf/minf/clampf` 的返回值必须显式 `: float` 或就地使用。
##

const _FpSum := preload("res://scripts/engine/fp_sum.gd")

# ---- GDD §2.2.1 权威路径（sim 真身 corebound_sim_v03.py:69）----
const PATH: Array = [
	Vector2(0.0, 25.0), Vector2(12.0, 25.0), Vector2(12.0, 48.0),
	Vector2(35.0, 48.0), Vector2(35.0, 25.0), Vector2(55.0, 25.0),
]

const SEG_LEN: Array = [12.0, 23.0, 23.0, 23.0, 20.0]
const CUM_LEN: Array = [0.0, 12.0, 35.0, 58.0, 81.0, 101.0]
const TOTAL_LEN: float = 101.0
const CORE_POS := Vector2(55.0, 25.0)

const N_SEG: int = 5


# ---------------------------------------------------------------------------
#  I-1 `sample(s) -> Vector2` —— 弧长参数化，O(log n) 二分
# ---------------------------------------------------------------------------
## 由弧长 `s ∈ [0, TOTAL_LEN]` 反查世界坐标（XZ 平面，Vector2.x = X, .y = Z）。
## 超出两端**夹住**（s<0 → 起点；s>L → 核心）。
static func sample(s: float) -> Vector2:
	var t := clampf(float(s), 0.0, TOTAL_LEN)
	# 二分：找最大的 i 使 CUM_LEN[i] <= t
	var lo := 0
	var hi := N_SEG - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(CUM_LEN[mid]) <= t:
			lo = mid
		else:
			hi = mid - 1
	var seg := lo
	if seg >= N_SEG:
		return Vector2(PATH[N_SEG])
	var a: Vector2 = PATH[seg]
	var b: Vector2 = PATH[seg + 1]
	var L := float(SEG_LEN[seg])
	var u := 0.0
	if L > 0.0:
		u = (t - float(CUM_LEN[seg])) / L
	return Vector2(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)


# ---------------------------------------------------------------------------
#  §3.2 `d_path` —— 塔位到路径的**最短距离**（暴露度第一手数据）
# ---------------------------------------------------------------------------
static func dist_to_path(p: Vector2) -> float:
	var best := INF
	for i in range(N_SEG):
		var d := pt_seg_dist(p, PATH[i], PATH[i + 1])
		if d < best:
			best = d
	return best


## v03 `_pt_seg_dist` 同式：点到线段的最短距离（含端点）
static func pt_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var vx := b.x - a.x
	var vy := b.y - a.y
	var wx := p.x - a.x
	var wy := p.y - a.y
	var l2 := vx * vx + vy * vy
	var t := 0.0
	if l2 > 0.0:
		t = clampf((wx * vx + wy * vy) / l2, 0.0, 1.0)
	var dx := wx - vx * t
	var dy := wy - vy * t
	return sqrt(dx * dx + dy * dy)


# ---------------------------------------------------------------------------
#  §2.2.3 `ExposureArc` —— 路径上落入 `R` 圆内的弧长（可能不连续）
# ---------------------------------------------------------------------------
## 返回暴露段的 `s` 区间数组 `Array[Vector2]`（每个 `Vector2.x/.y` = 起讫弧长）。
##
## 解析解（逐段）：沿段方向 u，段内偏移 d 处的点到 P 的距离平方
##   |a + u·d − P|² = d² − 2·d·c + |v|² ,   c = u·v, v = P − a
##   ≤ R²  ⟺  d ∈ [c − √disc, c + √disc]，disc = R² − (|v|² − c²) = R² − perp²
## 再把区间与 [0, L] 求交，最后整体加上 `CUM_LEN[seg]` 平移到全局弧长。
static func exposure_intervals(p: Vector2, R: float) -> Array:
	var out: Array = []
	var r2 := R * R
	for i in range(N_SEG):
		var a: Vector2 = PATH[i]
		var b: Vector2 = PATH[i + 1]
		var L := float(SEG_LEN[i])
		if L <= 0.0:
			continue
		var ux := (b.x - a.x) / L
		var uy := (b.y - a.y) / L
		var vx := p.x - a.x
		var vy := p.y - a.y
		var c := ux * vx + uy * vy
		var perp2 := (vx * vx + vy * vy) - c * c
		if perp2 < 0.0:
			perp2 = 0.0                       # 浮点残差（点恰在段的延长线上）
		var disc := r2 - perp2
		if disc < 0.0:
			continue                           # 整段都在圆外
		var rt := sqrt(disc)
		var d0 := maxf(c - rt, 0.0)
		var d1 := minf(c + rt, L)
		if d1 <= d0:
			continue
		out.append(Vector2(float(CUM_LEN[i]) + d0, float(CUM_LEN[i]) + d1))
	return out


## 暴露弧长 = Σ 各暴露段长度。🔴 N2：float 序列求和走 `FpSum.sum_py()`。
static func exposure_arc(p: Vector2, R: float) -> float:
	var iv := exposure_intervals(p, R)
	if iv.is_empty():
		return 0.0
	var lens: Array = []
	for seg in iv:
		var v: Vector2 = seg
		lens.append(v.y - v.x)
	return _FpSum.sum_py(lens)


## 🔴 区间并集长度（多塔位 union 用）：先按起点排序，再线性合并。
##    注意与「各塔位弧长直接相加」不同 —— 方案 A 的四个暴露段两两不重叠，
##    故 union 53.1217 与「四舍五入后相加」53.13 只在末位有差（GDD 表是后者）。
static func union_arc(intervals: Array) -> float:
	if intervals.is_empty():
		return 0.0
	var iv: Array = intervals.duplicate()
	iv.sort_custom(func(a, b): return float(a.x) < float(b.x))
	var total := 0.0
	var cur: Vector2 = iv[0]
	var lens: Array = []
	for i in range(1, iv.size()):
		var nx: Vector2 = iv[i]
		if float(nx.x) > float(cur.y):
			lens.append(cur.y - cur.x)
			cur = nx
		else:
			cur = Vector2(cur.x, maxf(cur.y, nx.y))
	lens.append(cur.y - cur.x)
	total = _FpSum.sum_py(lens)
	return total


# ---------------------------------------------------------------------------
#  静态预计算：地图加载时算一次，写进 Slot（GDD §7 交接点 ①）
# ---------------------------------------------------------------------------
## `slots`: Array[Vector2]（XZ 平面塔位坐标，= `Geo6.SLOTS6`）
## 返回 Array[Dictionary]：{ slot, d_path, exposure_arc, exposure_intervals, is_exposed }
static func slot_exposure(slots: Array, R: float = 9.0) -> Array:
	var out: Array = []
	for i in range(slots.size()):
		var p: Vector2 = slots[i]
		var iv := exposure_intervals(p, R)
		out.append({
			"slot": i,
			"pos": p,
			"d_path": dist_to_path(p),
			"exposure_arc": exposure_arc(p, R),
			"exposure_intervals": iv,
			# 🔒 T1 才需要（GDD §3.2）：`<=` 含等号（E-W6 / E-T10，避免浮点抖动）
			"is_exposed": dist_to_path(p) <= R,
		})
	return out


## 派生：给定 `t_remain` 与速度乘数，反查当前弧长 s。
##   s = L − v₀·m_spd·t_remain
##   （推导：s = v₀·m_spd·已行进时间 = v₀·m_spd·(t_reach/m_spd − t_remain) = L − v₀·m_spd·t_remain）
## 🔴 这样「t_remain 递减」与「s 递增」共用同一个状态量，不会出现两套时钟。
static func arc_of_t(t_remain: float, m_spd: float, v0_: float, total_len: float = TOTAL_LEN) -> float:
	return total_len - v0_ * m_spd * t_remain


# ===========================================================================
#  🆕 径向暴露度解析解（阶段2 · P4 暴露度地基 · tech-assessment §7.1）
# ---------------------------------------------------------------------------
#  🔴 纯增量：以下函数与既有 PATH 口径（dist_to_path/exposure_arc/slot_exposure）
#     **并存**，不改动任何既有函数。PATH 模式逐位不变。
#
#  径向模型下「路径」消失，暴露度从「塔到路径的弧长」改为「方向覆盖率」：
#    怪从出生环各方向直插核心，塔位 P 距核心 d，只有来向一侧（|Δ|≤π/2）的怪会
#    经过 P 附近，且最近距离 = d·|sinΔ|。积分得方向覆盖率：
#      d ≤ R  →  expo_frac = 1.000（所有方向的怪都进入 R）
#      d > R  →  expo_frac = asin(R/d) / π
#  与 PATH 的 exposure_arc（弧长）不同，这是**无量纲覆盖率** ∈ (0,1]。
#
#  ⚠️ 本文件只给**解析闭式**（可单测逐位）；D-3 阈值 EXPO_SAFE_MAX（连续量→二值）
#     是设计参数，须文策渊定稿，不在本文件冻结。
# ===========================================================================

## 🔴 D-3 定稿阈值（2026-10-08 · 文策渊拍板）：连续暴露度 → 二值「会挨打/安全」。
##   is_exposed = expo_frac >= EXPO_SAFE_MAX。
##   八槽 E8-A 下：0.15 → 安全位 = [S3,S5,S6,S7]（4 暴露 + 4 安全）。
##   🔴 八槽红线：0.10 会给 0 个安全位（最外 S5=0.107 也 >0.10）→ AC-S6-3 破产，
##      故八槽下此值必须 ≥0.15。此常量即冻结口径，改动须重新过 AC-S6-3 硬约束。
const EXPO_SAFE_MAX: float = 0.15

## 🆕 阵地化（17 格 · `BuildGrid.sites_active()`）专用阈值 —— **与 8 槽红线分开冻结**。
##
## 🔴 为什么必须分开（2026-11-09 实测）：`expo_frac = asin(R/d)/π` 在 8 槽布局里天然二分
##   （近环 d≈6–9 → 1.0；深位 d≈40+ → ≈0.05），0.15 正好切在中间。
##   但 17 格阵地的 r 全落在 **18–42**，`expo_frac` 全挤在 **0.073–0.159** —— 用 0.15 判，
##   17 个格心只有 **1 个**算「暴露位」。
##   而「战斗内复活」的资格闸门硬依赖 `is_exposed`（`wave_director.gd:861`：
##   `death_valid ∧ is_exposed ∧ ¬is_carry`）→ 实机 94% 的格子**永远不可复活**，
##   产品开关 `combat_revive_enabled` 在实机上等于没开。
##   实测取证：`6-1` W14 处刑波十塔全灭，`revive_diag = {fired:0, elig:0, refused:10,
##   nonexp_death:7, carry_death:3}` → 核心 1000→0，一波穿核。
##
## 标定口径（不是随手取数）：让**内圈三台 P1–P3（r 18–32 · d ≤ 34）** 成为暴露位/肉盾位，
##   **孤台 N1–N3（r 39–42 · d ≥ 39）** 保持安全位（低风险高单价位，见 scene-map §9）。
##   实测 `expo_frac`：内圈最远格 0.099 / 孤台最近格 0.073 → 阈值取 **0.085** 落在这条缝里。
##   🔴 8 槽口径 `EXPO_SAFE_MAX = 0.15` **一字不动** → AC-S6-3（4 暴露 / 4 安全）仍成立；
##      本常量只在阵地化开启时经 `expo_safe_max_for()` 生效。
const EXPO_SAFE_MAX_SITES: float = 0.085

## 按几何口径取阈值：阵地化（17 格）用新标定，8 槽 / PATH 用冻结的 0.15。
## 🔴 唯一分派点：调用方**不要**自己写三元表达式，否则"哪套几何用哪档"会散落成多份。
static func expo_safe_max_for(sites_active: bool) -> float:
	return EXPO_SAFE_MAX_SITES if sites_active else EXPO_SAFE_MAX

## 塔位 P 到核心的距离（径向暴露度第一手数据，对应 PATH 的 d_path）。
static func dist_to_core(p: Vector2, core: Vector2) -> float:
	var dx: float = p.x - core.x
	var dy: float = p.y - core.y
	return sqrt(dx * dx + dy * dy)


## 方向覆盖率 expo_frac ∈ (0,1]（对应 PATH 的 exposure_arc，但无量纲）。
##   d ≤ R  → 1.000；d > R → asin(R/d)/π。
## 🔴 纯闭式，可单测逐位（tech-assessment §7.1 实测表可抄）。
static func expo_frac_of(p: Vector2, core: Vector2, R: float) -> float:
	var d: float = dist_to_core(p, core)
	if d <= R:
		return 1.0
	# asin(R/d) / π：R/d ∈ (0,1)，asin 返回 (0, π/2)，除 π 得 (0, 0.5]
	return asin(clampf(R / d, 0.0, 1.0)) / PI


## 径向暴露度表（对应 PATH 的 slot_exposure，径向口径）。
##   返回 Array[Dictionary]：{ slot, pos, d_core, expo_frac, is_exposed }
##   is_exposed = expo_frac >= EXPO_SAFE_MAX（阈值由调用方传入，本文件不冻结）。
## 🔴 EXPO_SAFE_MAX 是设计参数（D-3）：调用方传 NaN 表示不定稿二值（is_exposed 恒 false），
##    只登记连续量 d_core / expo_frac（事实层，SR-R2 只标事实）。
static func slot_exposure_radial(slots: Array, R: float, core: Vector2,
		expo_safe_max: float = NAN) -> Array:
	var out: Array = []
	for i in range(slots.size()):
		var p: Vector2 = slots[i]
		var d: float = dist_to_core(p, core)
		var f: float = expo_frac_of(p, core, R)
		var row: Dictionary = {
			"slot": i,
			"pos": p,
			"d_core": d,
			"expo_frac": f,
			"is_exposed": false,
		}
		# 仅当阈值有效（非 NaN）时才二值化
		if not is_nan(expo_safe_max):
			row["is_exposed"] = (f >= expo_safe_max)
		out.append(row)
	return out
