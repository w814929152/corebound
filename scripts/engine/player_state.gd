class_name PlayerState
extends RefCounted
##
## 玩家状态的最小可用切片 —— 只服务伤害引擎的逐位对齐验证。
## 对应 v03 的 `Player` / `Tower`（只取引擎真正读的字段：path / towers / n_hist_max）。
##
## 🔴 引擎不持有游戏状态：`DamageEngine.compute_dps()` 是纯函数，只读这些字段。
##

class TowerState extends RefCounted:
	var slot: int = 0
	var ctype: String = ""
	var h: int = 0                 # 建筑卡层数 h_i
	var attach: Dictionary = {}    # {强化卡名: 层数} → L_i = Σ 层数
	## 🔒 T1 占位（设计文档 mechanics-tower-life-death §0 / §4.3 交接点③）：
	##   塔死亡（进入 Disabled 中间态）时对 7 乘区管线的**唯一落点**。
	##   `damage_engine` 在 per_tower 末尾乘 `disabled ? 0.0 : 1.0`。
	##   🔴 MVP 恒 false → 该乘数恒 1.0 → 对定稿 DPS **逐位零影响**（金标本零改动、判据链不变）。
	##   塔死亡玩法（HP0/维修/暴露度实战）整体留后续批次 + 300 局 MC 重扫后上线。
	var disabled: bool = false
	## 🔒 T1（Q-T2 = ① 已定稿冻结）：塔的战斗运行时耐久。
	##   `hp_max = HP0 × h^0.6`（`MonsterData.tower_hp`，复用 tower_stack_exp=0.6）。
	##   波首由 `WaveDirector` 重置为满血（MVP 无修复机制 → 每波满血是最简口径；
	##   Disabled 塔在波次间由玩家三选一修复/拆除/放着，T1 后续批次实现修复入口）。
	##   🔴 金标本 AI 路线（`shop_ai.gd`）**不读不写** hp/hp_max → 金标本零改动。
	##   🔴 MVP 塔不死（tower_aggro_enabled=false）→ hp 恒不被扣减、恒等于 hp_max。
	var hp: float = 0.0
	var hp_max: float = 0.0
	## 🟡 切片8 · 逐塔累计投入（拆除回收 `Salvage` 的数据前提，card-system §4.3 / §7.2.2 / Q-C3）：
	##   记录**这座塔**累计吃掉的分数（建筑卡 build/upgrade 分 + 装配卡 reinforce 分）。
	##   `salvage_tower()` 据此返还 **50% 累计投入**（向下取整）。
	##   🔴 只在**玩家手动路线**（`shop_runtime.gd`）侧记录与维护；金标本 AI 路线
	##      （`shop_ai.gd apply_action`）**不读不写**此字段 → 金标本零改动、MC 判据链不受影响。
	##   🔴 MVP 默认不触发拆除（入口置灰），本字段恒 0.0；单测里主动写入以验证结算器。
	var invested: float = 0.0
	## 🔒 V-8 肉盾循环（`corebound-bulwark-death-cycle-v3` · 诊断字段 · 🔴 默认恒惰性）
	##   🔴 这五个字段**只被 `wave_sim_aggro.gd` 的 V-8 分支读写**；金标本 AI（`shop_ai`）、
	##      伤害引擎（`damage_engine`）、实时版（`wave_director`）**不读不写** → 默认零扰动。
	##   🔴 只有在 `repair_on_disable >= 9`（战斗内/波首重启）或 `bulwark_diag` 显式开启时
	##      才会被写入；默认情况下全部保持初值，不参与任何计算。
	var revive_t_disabled: float = 0.0   # 本波内已 Disabled 的秒数（波首清零）
	var revive_used_w: int = 0           # 本波内已战斗内重启次数（波首清零）
	var revived_ever: int = 0            # 本局累计重启次数（`revive_then_redied` 用）
	var death_exposed: bool = false      # 死亡时刻 `is_exposed` 快照（资格判定 A）
	var death_carry: bool = false        # 死亡时刻 是否 carry（h 最高）快照（资格判定 B）
	var death_valid: bool = false        # 是否已取过死亡快照（防"未取快照就重启"漏判）


var path: String = "B"
var towers: Array = []        # Array[TowerState]
var n_hist_max: int = 0       # 兜底①：本局历史最大塔数（只增不减）
var income_mult: float = 0.0
## 🔒 T1 玩法③ 献祭 `Salvage Rite`：本局累积的 **StackCap 增益**（献祭燃料变现）。
##   每次献祭 `stackcap_bonus += floor(被献祭塔累计投入 / 10)`（收益 ∝ 投入 = earned，
##   兑现 P2；刷塔要真花钱 → 天然防刷）。`damage_engine.dps_only` 把它加到每塔 `caps`
##   → 全局 StackCap 提升，层数最集中的主塔受益最多（pow_sc 在 lv>cap 才衰减）→
##   天然耦合单核流（卖副塔喂主塔上限）。
##   🔴 金标本零改动：金标本 AI 不献祭 → 本字段恒 0.0 → `caps` 逐位不变 → DPS 零影响。
##   🔴 只在玩家手动路线（shop_runtime.gd）侧写入；shop_ai.gd 不读不写。
var stackcap_bonus: float = 0.0
var reroll_disc: float = 0.0
var cards: Dictionary = {}
## 🔴 切片8续3（可玩 MVP）：核心 HP 单一数据源。
##   战斗侧（WaveDirector 漏怪扣血）与商店侧（ShopRuntime / HUD / 核心 HP 条）
##   一律读写这同一份，杜绝两份 core_hp 各扣各的、HUD 读数与真实战斗脱节。
##   初值在 `SimPlayer.new_player()` 里按 cfg.core_hp 设定（默认 1000）。
var core_hp_max: float = 1000.0
var core_hp: float = 1000.0


static func make_tower(slot: int, ctype: String, h: int, attach: Dictionary = {}) -> TowerState:
	var t := TowerState.new()
	t.slot = slot
	t.ctype = ctype
	t.h = h
	t.attach = attach.duplicate()
	return t


# ⚠️ Godot 坑：脚本**自己**的 `class_name` 不在本文件作用域内
#    （`PlayerState.new()` 在本文件里会报 "Identifier not found: PlayerState"）。
#    所以本类不提供 `static func make_player()` 自工厂 —— 调用方请
#    `const PS := preload("res://scripts/engine/player_state.gd")` 后 `PS.new()` 再赋值字段。

static func total_layers(t: TowerState) -> float:
	var s := 0.0
	for _k in t.attach:
		s += float(t.attach[_k])
	return s
