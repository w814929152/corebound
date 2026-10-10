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
static func spawn_theta(index: int, w: int) -> float:
	var theta0_deg: float = fmod(float(w) * PHASE_STEP_DEG, 360.0)
	var theta_deg: float = fmod(theta0_deg + float(index) * GOLDEN_ANGLE_DEG, 360.0)
	return theta_deg * PI / 180.0


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
	return polar_pos(theta, rho_of_t(t_remain, m_spd, t_reach))
