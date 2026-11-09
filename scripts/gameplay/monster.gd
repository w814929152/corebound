extends RefCounted
##
## 怪物运行时实体 —— GDD `wave-spawner` v0.2 §3.3
##
## 🔴 设计取舍：**RefCounted，不进场景树**。
##    · 逻辑与渲染分离（control-manifest §5：`scripts/gameplay/` 持玩法状态，
##      `scripts/ui/` 只读 + 画占位）→ headless 下可直接单测，无需 SceneTree；
##    · 渲染由 `scripts/ui/monster_layer.gd`（Node2D）每帧读 `WaveDirector.monsters` 画占位方块。
##
## 🔴 权威状态量 = **`t_remain`（剩余在场时间）**，不是 `s`。
##    为什么：`WaveSim.simulate_wave`（金标本）的循环体是
##      `m[1] -= DT; if m[1] <= 0: leaked += 1`
##    要让实时推进与它**逐位等价**，`t_remain` 必须走**同一条递减路径**（同一个 IEEE754
##    累加序列）。`s` 改由 `PathGeometry.arc_of_t()` 派生（纯几何，不影响结算）。
##    → 二者是同一个状态量的两种读法，不存在两套时钟（GDD §3.3 的 `t_remain` 与 `s` 均登记）。
##
## 🔒 T1：`state` 三态 + `target_slot`（Q-T3 机会型仇恨）。
##    MVP 因 `tower_aggro_enabled = false`，怪物恒 `MARCHING`（`s += v₀·m_spd·dt` 直冲核心）。
##
## ⚠️ G6：headless `--script` 无 global_script_class_cache → 本文件**不写 `class_name`**。
##

const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")


enum State {
	MARCHING = 0,      # 沿路径冲核心（MVP 恒此态）
	AGGRO_TOWER = 1,   # 🔒 T1：停下攻击最近的塔（v = 0）
	LEAKED = 2,        # 抵达核心 → Core.hp −= 50 → 移除
	AGGRO_CORE = 3,    # 正式关卡：停在核心附近，持续攻击
}


var index: int = 0          # 本波出生序号（0-based；= 分配排序的稳定次序来源）
var proto: String = "Swarm" # Rush / Swarm / Tank
var elite: bool = false     # 🔒 D-W1=B 词缀版 Elite（AI 不变，只放大 HP）

## 火焰附加状态：各来源共享层数；满层引爆或持续时间结束时清空。
var burn_stacks: int = 0
var burn_remaining: float = 0.0

## 冰冻层数不会在十层前自然消退；完全冻结结束后统一清空。
var frost_stacks: int = 0
var frozen_remaining: float = 0.0
var death_recorded: bool = false

var hp: float = 0.0
var hp_max: float = 0.0
var m_spd: float = 1.0      # 速度乘数（× v₀ = 10.10）
var m_dps: float = 1.0      # 🔒 T1 对塔伤害系数；MVP 塔不死 → 不消费

var t_remain: float = 10.0  # ★ 剩余在场时间（W-A2 分配排序键；仅 MARCHING 时递减）
var t_remain_max: float = 10.0

## 🆕 径向模式（SpaceModel.RADIAL）下的出生角 θ（弧度）。
##   · 由 `SpaceModel.spawn_theta(index, w)` 黄金角序列派生（确定性 · 零 RNG）。
##   · PATH 模式下**不使用**（路径模型无"出生角"概念），恒 0.0。
##   · 🔴 只影响"位置派生"，不碰 `t_remain` 的递减 / 判漏 / 排序（金标本零扰动）。
var theta: float = 0.0

var state: int = State.MARCHING
var target_slot: int = -1   # 当前攻击的塔位（-1 = 无）
## 🔒 T1 ⑤ Sapper 精英：Elite 波（每5波）里的一种精英怪 —— **无视距离直奔最近的塔
##   并锁定攻击、对塔伤害 ×3**（GDD Q-T11 顺序3「锁定增伤流」）。由 elite_waves_enabled
##   诊断开关控制，MVP 恒 false（金标本零改动）。
var sapper: bool = false


func setup(p_index: int, p_proto: String, p_elite: bool, p_hp: float, p_m_spd: float, p_t_remain: float) -> void:
	index = p_index
	proto = p_proto
	frost_stacks = 0
	frozen_remaining = 0.0
	death_recorded = false
	burn_stacks = 0
	burn_remaining = 0.0
	elite = p_elite
	hp = float(p_hp)
	hp_max = float(p_hp)
	m_spd = float(p_m_spd)
	m_dps = float(_MonsterData.M_DPS.get(p_proto, 1.0))
	t_remain = float(p_t_remain)
	t_remain_max = float(p_t_remain)
	state = State.MARCHING
	target_slot = -1
	sapper = false
	theta = 0.0


## 🆕 径向模式：设置出生角（由 WaveDirector 在 `_spawn_one` 时按黄金角序列注入）。
##   PATH 模式调用无意义（恒忽略），保留以便统一接线。
func set_theta(p_theta: float) -> void:
	theta = float(p_theta)


## 当前弧长 s（派生量，供渲染 / 仇恨判定用）
func arc_s(v0_: float, total_len: float = _PathGeometry.TOTAL_LEN) -> float:
	# 🔴 PATH 模式：逐位等价基准（`s = L − v₀·m_spd·t_remain`），一行不改。
	if _SpaceModel.mode != _SpaceModel.Mode.RADIAL:
		return _PathGeometry.arc_of_t(t_remain, m_spd, v0_, total_len)
	if _SpaceModel.uses_terrain():
		return _SpaceModel.radial_pos_of_t(t_remain,m_spd,theta).distance_to(_SpaceModel.RADIAL_CORE)
	# RADIAL：极径 ρ 与弧长 s 是同一状态量的两种读法（ρ = R_s·m_spd·t_remain/t_reach）。
	#   返回 ρ（到核心距离），供渲染 / 仇恨用；不影响 t_remain 结算。
	return _SpaceModel.rho_of_t(t_remain, m_spd)


## 当前世界坐标（XZ 平面）
func pos(v0_: float, total_len: float = _PathGeometry.TOTAL_LEN) -> Vector2:
	# 🔴 PATH 模式：逐位等价基准（二分查折线），一行不改。
	if _SpaceModel.mode != _SpaceModel.Mode.RADIAL:
		return _PathGeometry.sample(arc_s(v0_, total_len))
	# RADIAL：极坐标一步乘加（ρ 由 t_remain 派生，θ 为出生角）。
	return _SpaceModel.radial_pos_of_t(t_remain, m_spd, theta)


## 🔴 是否已抵达核心（E-W5：`s == 101` 判为**已抵达**，`>=` 含等号，与 core-defense E6 同口径）
##    等价于 `arc_s() >= L`：`s = L − v₀·m_spd·t_remain` ⟹ `s ≥ L` ⟺ `t_remain ≤ 0`。
func reached() -> bool:
	return t_remain <= 0.0


func is_alive() -> bool:
	return hp > 0.0 and state != State.LEAKED


func state_name() -> String:
	match state:
		State.MARCHING:
			return "Marching"
		State.AGGRO_TOWER:
			return "AggroTower"
		State.LEAKED:
			return "Leaked"
		State.AGGRO_CORE:
			return "AggroCore"
	return "?"
