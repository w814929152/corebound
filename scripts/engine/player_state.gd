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
	## 🟡 切片8 · 逐塔累计投入（拆除回收 `Salvage` 的数据前提，card-system §4.3 / §7.2.2 / Q-C3）：
	##   记录**这座塔**累计吃掉的分数（建筑卡 build/upgrade 分 + 装配卡 reinforce 分）。
	##   `salvage_tower()` 据此返还 **50% 累计投入**（向下取整）。
	##   🔴 只在**玩家手动路线**（`shop_runtime.gd`）侧记录与维护；金标本 AI 路线
	##      （`shop_ai.gd apply_action`）**不读不写**此字段 → 金标本零改动、MC 判据链不受影响。
	##   🔴 MVP 默认不触发拆除（入口置灰），本字段恒 0.0；单测里主动写入以验证结算器。
	var invested: float = 0.0


var path: String = "B"
var towers: Array = []        # Array[TowerState]
var n_hist_max: int = 0       # 兜底①：本局历史最大塔数（只增不减）
var income_mult: float = 0.0
var reroll_disc: float = 0.0
var cards: Dictionary = {}


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
