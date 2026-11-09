class_name SpaceModel
extends RefCounted
##
## 空间模型 `SpaceModel` —— 🔴 **径向核心围攻迁移 · 阶段0 运动学**
##
## 依据：`design/gdd/radial-core-siege-draft.md` §2.3 / §2.5 / §11.2（阶段0）。
##
## 🔴 定位：全局**诊断开关**，与 `prototype_split_enabled` / `elite_waves_enabled` /
##    `tower_aggro_enabled` 同款哲学（GDD §7.1 E-8 / Q-R8）：
##      · 结构完整落地（path / radial 双模）；
##      · 默认 PATH = 既有金标本等价口径（**零扰动**）；
##      · 开关切到 RADIAL 才生效，可一键回退。
##
## 🔴 金标本对齐铁律（改这个文件前必读）：
##   1) **`t_reach = 10.0s` 恒定**（R-CS3）—— 它是 `threshold(w)` 的分母，一动即改难度。
##      出生环半径 `R_s` 与 `v₀` 随之派生：`v₀ = R_s / t_reach`。改 `R_s` **不构成重扫**。
##   2) **`t_remain` 仍是唯一权威状态量**（E-2）—— 径向只改"位置派生函数"，
##      `t_remain` 的递减 / 判漏 / 稳定排序**一行不动**（金标本 sim 里根本没有"位置"）。
##   3) **出生角零 RNG 消费**（E-4 / Q-R6）—— 黄金角低差异序列（确定性），
##      不碰商店发牌的 RNG 流，否则 `run_loop` 逐位对齐当场失效。
##   4) **PATH 模式逐位等价**（AC-R3）—— PATH 分支的 `v₀` / 位置必须与现状逐位相同。
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → 角度 / 半径运算一律显式 `float()`。
##   G3 `static var` 跨场景共享 → 本文件只放**模式开关 + 常量 + 纯函数**；
##      可变状态只有 `mode`（诊断开关，测试用完须设回 PATH）。
##
## 坐标：世界 XZ 平面（Vector2.x = X, .y = Z），与 `PathGeometry` / `Geo` 同口径。
##

# ---------------------------------------------------------------------------
#  模式枚举
# ---------------------------------------------------------------------------
enum Mode {
	PATH = 0,     # 既有定稿：怪物沿 PATH 折线 (L=101) 冲核心 (55,25)
	RADIAL = 1,   # 🆕 径向核心围攻：怪物从出生环直插居中核心 (28,28)
}

# 🔴 全局开关（诊断，默认 PATH = 金标本等价口径）。测试注入 RADIAL 后须设回。
static var mode: int = Mode.PATH


# ---------------------------------------------------------------------------
#  路径模式（既有定稿，逐位等价基准）
# ---------------------------------------------------------------------------
const PATH_TOTAL_LEN: float = 101.0          # = PathGeometry.TOTAL_LEN
const PATH_CORE := Vector2(55.0, 25.0)       # = PathGeometry.CORE_POS（路径终点）


# ---------------------------------------------------------------------------
#  径向模式（🆕 阶段0 运动学参数 · 草案 §2.2 / §2.3）
# ---------------------------------------------------------------------------
## 🔴 核心 = 逻辑地图 55×55 的几何中心（§2.2）。核心居中 → "塔全堆核心左侧"的
##    视觉取舍自动消失，叙事回到"守一座被环抱的核心"。
const RADIAL_CORE := Vector2(28.0, 28.0)
## 出生环半径（§2.3 · Q-R2 = ② 推荐 55.0）。纯演出参数，不进 sim；
## 出生点刚好落在可视区外一点点（吸血鬼幸存者"从屏幕边缘涌入"的手感）。
const SPAWN_RADIUS: float = 55.0
## 🔴 t_reach 恒定（R-CS3）—— 与金标本 / 路径模式同一来源。
const T_REACH: float = 10.0

# ---- 出生角黄金角低差异序列（§2.3.1 方案① · 确定性 · 零 RNG）----
#   θ_i = (θ₀ + i × 137.508°) mod 360°
#   θ₀  = (w × 37°) mod 360°        （每波换起始相位，喂 P3「每局一个新解」）
const GOLDEN_ANGLE_DEG: float = 137.508       # 黄金角（低差异铺满 360°）
const PHASE_STEP_DEG: float = 37.0            # 逐波相位步进
const _TWO_PI: float = 6.283185307179586      # 2π


# ---------------------------------------------------------------------------
#  地图布局「三裂环」（design/gdd/scene-map.md v1.0）
# ---------------------------------------------------------------------------
## 🔴 总开关（诊断）：false = 回到「整圈可建 + 整圈出生」的空圆盘，一键回退。
##   与 `mode` 同款哲学：只在 RADIAL 下被读，PATH 模式一行不受影响。
static var layout_enabled: bool = true

## 岩脊 3 座：**只封出生角，不改路**。
##   🔴 为什么不挡路：`radial-core-siege-tech-assessment.md` §4.2 已把寻路/避障列为架构红线
##      （改到核时间 → 金标本等价破产）。本图的地形只做「角向遮挡」——`ρ` 一行不动，
##      `t_remain` 语义零变更 ⇒ `t_reach` / 到核时间 / 金标本全部不动。
##   `a0/a1` = 逻辑遮挡角（度，顺时针、y 向下、0° = +x）；`pad` = 视觉每边内收（度）。
##   合计遮挡 B = (36−18) + (164−150) + (262−254) = 18 + 14 + 8 = **40°**。
const RIDGES: Array = [
	{"id": "G1", "name": "东南断崖", "a0": 18.0, "a1": 36.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
	{"id": "G2", "name": "西断墙", "a0": 150.0, "a1": 164.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
	{"id": "G3", "name": "北短脊", "a0": 254.0, "a1": 262.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
]
## 出怪口 3 段：合计 320°，宽度 114 / 90 / 116 —— **刻意不对称**（三等宽 = 没有选项）。
const SPAWN_ARCS: Array = [
	{"id": "A", "name": "南口", "a0": 36.0, "a1": 150.0},
	{"id": "B", "name": "西北口", "a0": 164.0, "a1": 254.0},
	{"id": "C", "name": "东北口", "a0": 262.0, "a1": 378.0},
]
## 开口总角宽 = 360 − Σ岩脊。AC-R1 下限 300°，本图取 320°（留 20° 余量给映射均匀度与变体图）。
const OPEN_DEG: float = 320.0


# ---------------------------------------------------------------------------
#  活动地图选择器（🆕 关卡推进 · 运行时换图）
# ---------------------------------------------------------------------------
## 🔴 「换表不换引擎」落地：三张 const 表仍是基准（"tri-fissure"），本选择器在
##    `map_theta_deg` / `is_ridge_deg` 里**按需**把「活动表」替换为变体表。
##    · 默认 `active_map_id == "tri-fissure"` → 访问器返回 const 表，**逐位等价**（零扰动）；
##    · 切到其他 id → 从 `MapVariants`（`scripts/data/map_variants.gd`）取对应表；
##    · 未知 id / 空 → 回落 "tri-fissure"（const 表）。
## 🔴 金标本铁律：`active_map_id` 只在 `RADIAL + layout_enabled` 下才被消费，
##    PATH 模式 / 布局关闭时一行不受影响；测试用完须设回 "tri-fissure"。
static var active_map_id: String = "tri-fissure"

const _MapVariants := preload("res://scripts/data/map_variants.gd")
const BattlefieldMaps := preload("res://scripts/data/battlefield_maps.gd")
## 玩家路线的非圆形场景地面；默认关闭，基准模拟保留原有空间口径。
static var terrain_enabled: bool = false

static func uses_terrain() -> bool:
	return terrain_enabled and mode == Mode.RADIAL and layout_enabled


## 设置活动地图（关卡系统在开局前注入；未知 id 自动回落 "tri-fissure"）。
static func set_active_map(map_id: String) -> void:
	if _MapVariants.exists(map_id):
		active_map_id = map_id
	else:
		active_map_id = "tri-fissure"


## 活动岩脊表（默认 = const RIDGES，切图 = 变体表）。
static func active_ridges() -> Array:
	if active_map_id == "tri-fissure":
		return RIDGES
	var r: Array = _MapVariants.ridges(active_map_id)
	return r if not r.is_empty() else RIDGES


## 活动出怪口表（默认 = const SPAWN_ARCS）。
static func active_spawn_arcs() -> Array:
	if active_map_id == "tri-fissure":
		return SPAWN_ARCS
	var a: Array = _MapVariants.spawn_arcs(active_map_id)
	return a if not a.is_empty() else SPAWN_ARCS


## 活动开口总角宽（默认 = const OPEN_DEG）。
static func active_open_deg() -> float:
	if active_map_id == "tri-fissure":
		return OPEN_DEG
	var d := _MapVariants.open_deg(active_map_id)
	return d if d > 0.0 else OPEN_DEG


# ---------------------------------------------------------------------------
#  派生量
# ---------------------------------------------------------------------------
## v₀（u/s）= 行程 / t_reach。
##   PATH   → L / t_reach = 101 / 10 = 10.10（逐位等价基准）
##   RADIAL → R_s / t_reach = 55 / 10 = 5.50
static func v0(t_reach: float = T_REACH) -> float:
	if mode == Mode.RADIAL:
		return SPAWN_RADIUS / t_reach
	return PATH_TOTAL_LEN / t_reach


## 核心坐标（随模式）。
static func core_pos() -> Vector2:
	return RADIAL_CORE if mode == Mode.RADIAL else PATH_CORE


## 当前是否径向模式。
static func is_radial() -> bool:
	return mode == Mode.RADIAL


# ---------------------------------------------------------------------------
#  出生角（§2.3.1 方案① · 黄金角低差异序列 · 确定性 · 零 RNG）
# ---------------------------------------------------------------------------
## 第 `index` 只怪（本波出生序号，0-based）在波次 `w` 下的出生角（弧度，[0, 2π)）。
##   θ₀  = (w × 37°) mod 360°
##   θ_i = (θ₀ + i × 137.508°) mod 360°
## 🔴 纯确定性：同 (w, index) 恒得同一角度 → 金标本零扰动（不消费任何 RNG 流）。
##    PATH 模式下本函数不被调用（路径模型无"出生角"概念），但保留可用以便对照。
## 🔴 地图布局开启时，序列末尾再过一层 `map_theta_deg()`（保序保测度 → 不聚堆、不开窗）。
##    **改在函数内而不是三个调用点**：`wave_director` 与两个批处理镜像（`wave_sim_aggro` /
##    `wave_sim_proto_aggro`）必须拿到同一个角，否则实时↔镜像当场失配。
static func spawn_theta(index: int, w: int) -> float:
	var theta0_deg: float = fmod(float(w) * PHASE_STEP_DEG, 360.0)
	var theta_deg: float = fmod(theta0_deg + float(index) * GOLDEN_ANGLE_DEG, 360.0)
	if mode == Mode.RADIAL:
		theta_deg = map_theta_deg(theta_deg)
	return theta_deg * PI / 180.0


## 出生角映射 `G`：360° 输入 → 320° 开口，**分段线性 · 保序 · 保测度**。
##   每段输入配额按该开口的弧长分配（`1/0.889 = span_out × 360/320`），段内斜率恒 = 320/360。
##   · 保序   ⇒ 同 (w, index) 恒得同一 θ'，确定性照旧；
##   · 保测度 ⇒ 黄金角的三项分布性质不变（不开窗、不聚堆）；
##   · 连续   ⇒ 段末 378° ≡ 18°，正好接上 G1 的起点，跨 0° 无缝。
## 🔴 零 RNG、零状态、零转向：怪物依然只沿半径走直线。
static func map_theta_deg(deg_in: float) -> float:
	var d := fposmod(deg_in, 360.0)
	if not layout_enabled:
		return d
	var arcs: Array = active_spawn_arcs()
	var open: float = active_open_deg()
	var acc := 0.0
	for arc in arcs:
		var span_out: float = float(arc["a1"]) - float(arc["a0"])
		var span_in: float = span_out * 360.0 / open
		# 🔴 `<=` 而不是 `<`：段边界（128.25° / 229.5°）必须归**前一段的终点**。
		#   否则输入恰好等于边界时会跳到下一口的起点（150 → 164），
		#   `G` 在那里多出一个 14° 的台阶 —— 怪物会在一条看不见的线上成排断开。
		if d <= acc + span_in:
			var t := (d - acc) / span_in
			return fposmod(float(arc["a0"]) + t * span_out, 360.0)
		acc += span_in
	# 浮点兜底：落在最后一段末端（d 极接近 360）→ 归到末段终点（= 18°，接 G1）。
	var last: Dictionary = arcs[arcs.size() - 1]
	return fposmod(float(last["a1"]), 360.0)


## 该角度是否落在岩脊**内部**（度，任意实数；边界角算"口"不算"脊"）。
##   供断言 / 调试用；运行时不做角度判定（映射本身已保证不出脊）。
static func is_ridge_deg(deg_in: float) -> bool:
	var d := fposmod(deg_in, 360.0)
	for rg in active_ridges():
		if d > float(rg["a0"]) and d < float(rg["a1"]):
			return true
	return false


# ---------------------------------------------------------------------------
#  径向运动学（§2.5）—— 与路径模型同构，只是把"弧长 s"换成"极径 ρ"
# ---------------------------------------------------------------------------
## 极径 ρ（到核心的距离，unit）。与 `PathGeometry.arc_of_t` 同构：
##   ρ = R_s × (m_spd × t_remain / t_reach)
## 🔴 `t_remain` 递减 → ρ 单调减小 → 直插核心；`t_remain ≤ 0` ⟺ `ρ = 0`（抵达核心）。
##    与路径模型 `s = L − v₀·m_spd·t_remain` 逐字同构（只是方向与零点不同）。
## 🔴 上钳参照 = `t_remain_max / t_reach = 1.0 / m_spd`（**不是**常数 `1.0`）：
##   · 出生 `t_remain = t_reach / m_spd`（`wave_director._spawn_one:722`）→ 归一上限 `1/m_spd`；
##   · `m_spd == 1.0` 时 `1.0/m_spd ≡ 1.0` → 与旧式 `clampf(...,0,1.0)` **逐位恒等**
##     （PATH / 默认口径全 Swarm m_spd=1 → 金标本零扰动）；
##   · `m_spd < 1`（如 Tank 2/3）→ 旧上钳 1.0 会把出生瞬间的 `frac` 误钳到 1 →
##     Tank 出生在出生环**内侧**且 `t_remain∈(t_reach, t_reach/m_spd]` 期间**原地静止**
##     （第四刀 proto-elite-golive 裁决 #1 定位的几何异常）。新上钳让 Tank 归环、匀速内插。
##   · 防除零：`m_spd` 极端小时 `maxf(m_spd, 1e-9)`；`m_spd ≥ 2/3` 时逐位不变。
static func rho_of_t(t_remain: float, m_spd: float, t_reach: float = T_REACH) -> float:
	var denom: float = maxf(m_spd, 1e-9)
	var frac: float = clampf(float(t_remain) / t_reach, 0.0, 1.0 / denom)
	return SPAWN_RADIUS * m_spd * frac


## 极坐标 → 世界坐标（XZ 平面）。
##   pos = Core + ρ × (cos θ, sin θ)
## 🔴 一次乘加（比路径模型的"二分查折线 + 线性插值"更省）。
static func polar_pos(theta: float, rho: float) -> Vector2:
	var c := cos(theta)
	var s := sin(theta)
	return Vector2(RADIAL_CORE.x + rho * c, RADIAL_CORE.y + rho * s)


## 由 (t_remain, m_spd, theta) 一步得到世界坐标（供 Monster.pos_radial 调用）。
static func radial_pos_of_t(t_remain: float, m_spd: float, theta: float,
		t_reach: float = T_REACH) -> Vector2:
	var rho := rho_of_t(t_remain, m_spd, t_reach)
	if uses_terrain():
		rho *= BattlefieldMaps.entry_radius(active_map_id, theta) / SPAWN_RADIUS
	return polar_pos(theta, rho)
