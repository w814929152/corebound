class_name SimPlayer
extends RefCounted
##
## 战斗循环的**玩家运行时状态** —— 在 `PlayerState`（伤害引擎只读的那份）之上，
## 补上 v03 主循环真正会写的字段与工具函数。
##
## 金标本：corebound_sim_v03.py
##   `Tower` (L215-225) / `Player` (L228-253) / `new_player()` (L696-700)
##
## ⚠️ 口径差异（GDScript vs Python）
##   1) Python 的 `player.cards` 是 **set**（无序，且 str 哈希每进程随机化）；
##      这里用 Dictionary（name → true），迭代顺序 = **插入顺序**，是确定性的。
##      影响点只有 `weakest_card()` 在"边际损失并列"时取哪一张 —— 金标本自身
##      在并列情形下也是不确定的，这里取插入序第一个（与 Python 的"严格 < 取最小"同语义）。
##   2) `snap()` / `rest()` 必须**深拷贝** attach，否则 `action_value()` 的
##      "试算 → 回滚"会污染真实状态。
##
## ⚠️ Godot 坑（headless）
##   H1 `--script` 启动**不**做编辑器导入 → `.godot/global_script_class_cache.cfg`
##      不存在 → 所有 `class_name` 全局类型（`PlayerState` / `TowerState`）**解析失败**。
##      → 本文件**一律不写** `-> PlayerState` 这类返回类型标注，参数也不标注，
##        只用 `const _PS := preload(...)` 取工厂函数。（与 test_suite.gd 的 T1 同源）
##

const _PS := preload("res://scripts/engine/player_state.gd")


static func new_player(path: String, cfg: Dictionary, geo = null):
	var p = _PS.new()
	p.path = path
	p.towers = []
	p.cards = {}
	p.income_mult = 0.0
	p.reroll_disc = 0.0
	p.n_hist_max = 0
	# v03 L698-699：起手送 Arrow@slot0（h=1），且 Arrow 进卡册
	p.towers.append(_PS.make_tower(0, "Arrow", 1, {}))
	p.cards["Arrow"] = true
	return p


# ---------------------------------------------------------------------------
# snap / rest —— 对应 v03 `Player.snap()` (L245) / `Player.rest()` (L249)
# ---------------------------------------------------------------------------
static func snap(p) -> Dictionary:
	var ts: Array = []
	for t in p.towers:
		ts.append([int(t.slot), String(t.ctype), int(t.h), t.attach.duplicate()])
	return {
		"towers": ts,
		"cards": p.cards.duplicate(),
		"income_mult": float(p.income_mult),
		"reroll_disc": float(p.reroll_disc),
	}


static func rest(p, s: Dictionary) -> void:
	var ts: Array = []
	for row in s["towers"]:
		ts.append(_PS.make_tower(int(row[0]), String(row[1]), int(row[2]), row[3]))
	p.towers = ts
	p.cards = s["cards"].duplicate()
	p.income_mult = float(s["income_mult"])
	p.reroll_disc = float(s["reroll_disc"])


# ---------------------------------------------------------------------------
# build_str —— 对应 v03 `Player.build_str()` (L236-243)
#   塔按 ctype 聚合层数，再按强化卡名聚合装配层数，最后按**字典序**拼串
# ---------------------------------------------------------------------------
static func build_str(p) -> String:
	var agg := {}
	for t in p.towers:
		var k := String(t.ctype)
		agg[k] = int(agg.get(k, 0)) + int(t.h)
	for t in p.towers:
		for rn in t.attach:
			var k2 := String(rn)
			agg[k2] = int(agg.get(k2, 0)) + int(t.attach[rn])
	var keys: Array = agg.keys()
	keys.sort()
	var parts: Array = []
	for k3 in keys:
		parts.append("%sx%d" % [String(k3), int(agg[k3])])
	return ",".join(parts)


static func layers_of(t) -> float:
	var s := 0.0
	for _k in t.attach:
		s += float(t.attach[_k])
	return s
