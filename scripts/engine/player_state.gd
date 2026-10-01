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
