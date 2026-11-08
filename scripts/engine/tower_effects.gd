extends RefCounted
##
## 触发型塔效果（Tower Effects）—— 卡包只收建筑后的**升级路线**
## ---------------------------------------------------------------------------
## 用户口径（2026-11-07）：「类似塔的效果 —— 回合开始时 / 防御塔上场时 /
##   防御塔死亡时**增加等级**」。明确否掉两种做法：光环被动加等级、三合一升星。
##
## 🔴 三条触发时机（与 `tower_data.TOWERS_EXT[].effect.on` 一一对应）：
##   · `enter`   —— 塔被放到格子上（玩家落子）→ 一次性；
##   · `prepare` —— 每波开始（`WaveDirector.start_wave`）→ 每波一次；
##   · `death`   —— 塔 HP 归零进入 Disabled 中间态 → 一次性。
##
## 🔴 等级写在哪：直接改 `player.towers[i].h`（与合成 / 强化层同一字段），
##   因此伤害（`h^0.6`）、塔 HP（`h^0.6`）、共鸣门槛（h≥3）全部自动跟随。
##
## 🔴 封顶 `LEVEL_CAP = 8`：触发只把塔往上涨到 8 级（= 形态满级 / Focus 预热满额），
##   不会无限滚雪球。🆕 2026-11-07：3 → 8（用户口径「增加塔的等级上限」）。
##
## 🔴 为什么死亡触发**当波不生效**：`damage_engine` 的 dps 在波首算死（battle 循环
##   等价性的前提，见 `wave_director` 文件头）。阵亡加成写进 h → 下一波 dps 才读到。
##   这是刻意口径，不是 bug（见 §测试 H12–H14）。
##
## 🔴 金标本零扰动：金标本走 `wave_sim` + 只买 `TOWERS` 基础塔，本文件的触发塔
##   全在 `TOWERS_EXT`；且 `apply_trigger` 对没有 effect 的塔是纯 no-op。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 不写 `class_name`，调用方 preload。
##

const _TD := preload("res://scripts/data/tower_data.gd")
const _CombatTypes := preload("res://scripts/data/combat_types.gd")

## 触发加等级的封顶（塔等级上限）。
##   🔴 8 = 形态满级（`monster_layer` h≥8 外环）/ `Focus` 预热满额（h/8）同档；
##      合成升级（同格同名再落）**不受此限**，仍无硬上限 —— 本常量只封「触发加等级」。
const LEVEL_CAP := 8


## 结算一次触发。`trigger` ∈ {enter, prepare, death}。
##   `ctx.tower` = 事件源塔（enter/death 必须给；prepare 不需要）。
##   返回实际发生变化的塔数（0 = 没有触发源 / 全部已封顶）。
static func apply_trigger(player, trigger: String, ctx: Dictionary = {}) -> int:
	if player == null:
		return 0
	var towers: Array = player.towers
	if towers.is_empty():
		return 0

	var ev_tower = ctx.get("tower", null)
	var changed := 0
	for t in towers:
		var e: Dictionary = _TD.tower_effect(String(t.ctype))
		if e.is_empty() or String(e.get("on", "")) != trigger:
			continue
		# enter / death 只认「本次事件的那座塔」，避免同一波里互相触发
		if trigger != "prepare" and ev_tower != null and t != ev_tower:
			continue
		var lv := int(e.get("lv", 1))
		var scope := String(e.get("scope", "self"))
		if scope == "self":
			changed += _add_level(t, lv)
		else:
			for t2 in towers:
				if t2 == t and trigger == "death":
					continue                       # 阵亡的塔自己不再吃加成
				changed += _add_level(t2, lv)
	return changed


## 给单座塔加等级（封顶 LEVEL_CAP = 8；Disabled 塔不吃加成）。
static func _add_level(t, lv: int) -> int:
	if t == null or lv <= 0:
		return 0
	if bool(t.disabled):
		return 0
	var cur := int(t.h)
	if cur >= LEVEL_CAP:
		return 0
	t.h = mini(cur + lv, LEVEL_CAP)
	return 1


# ---------------------------------------------------------------------------
#  🆕 持续型团队增益（2026-11-07 第二批机制）
# ---------------------------------------------------------------------------
## 光环类加成封顶（攻击 / 防御各 60%，避免叠满后数值失控）。
const BUFF_CAP := 0.60


## 攻击光环：全场塔 dps 加成（累加，封顶 BUFF_CAP）。
static func atk_bonus(player) -> float:
	if player == null:
		return 0.0
	var s := 0.0
	for t in player.towers:
		s += _TD.tower_buff_atk(String(t.ctype))
	return minf(s, BUFF_CAP)


## 防御光环：全场塔最大生命加成（累加，封顶 BUFF_CAP）。
static func def_bonus(player) -> float:
	if player == null:
		return 0.0
	var s := 0.0
	for t in player.towers:
		s += _TD.tower_buff_def(String(t.ctype))
	return minf(s, BUFF_CAP)


## 持续掉血：全场每秒对怪物造成（无视抗性）的伤害总量。
static func dot_dps(player) -> float:
	if player == null:
		return 0.0
	var s := 0.0
	for t in player.towers:
		if bool(t.disabled):
			continue
		s += _TD.tower_dot(String(t.ctype))
	return s


## Debuff vulnerability multiplier. Debuffs currently resolve as global combat effects,
## so any active slow, resistance shred, or DoT source marks the wave's targets.
static func debuff_damage_mult(player) -> float:
	if player == null:
		return 1.0
	var has_debuff := false
	var bonus := 0.0
	for t in player.towers:
		if bool(t.disabled):
			continue
		var ctype := String(t.ctype)
		if _TD.tower_slow(ctype) > 0.0 or _TD.tower_dot(ctype) > 0.0 \
				or _CombatTypes.armor_reduct_type(ctype) != "":
			has_debuff = true
		bonus = maxf(bonus, _TD.tower_buff_debuff_dmg(ctype))
	return 1.0 + bonus if has_debuff else 1.0


## 回复：每秒为未 Disabled 的塔恢复生命（封顶 hp_max）。
static func regen(player, dt: float) -> void:
	if player == null or dt <= 0.0:
		return
	var heal := 0.0
	for t in player.towers:
		heal += _TD.tower_heal(String(t.ctype))
	if heal <= 0.0:
		return
	for t in player.towers:
		if bool(t.disabled):
			continue
		t.hp = minf(float(t.hp_max), float(t.hp) + heal * dt)


## 击杀升级：任意怪物被击杀 → 带 `on_kill_lv` 的塔 +1 级（封顶 LEVEL_CAP = 8）。
static func on_kill(player) -> int:
	if player == null:
		return 0
	var n := 0
	for t in player.towers:
		if _TD.tower_on_kill_lv(String(t.ctype)):
			n += _add_level(t, 1)
	# 🆕 赏金（2026-11-07）：存活时全队累计击杀到 N 只 → 发 X 废料，可重复。
	#   🔴 只能挂在玩家路线（`player.bounty_scrap` 在波末由 `grant_wave_result` 入账）；
	#      金标本没有赏金塔 → 字段恒 0。
	for t in player.towers:
		if bool(t.disabled):
			continue
		var need := _TD.tower_bounty_kills(String(t.ctype))
		if need <= 0:
			continue
		t.bounty_progress = int(t.bounty_progress) + 1
		while int(t.bounty_progress) >= need:
			t.bounty_progress = int(t.bounty_progress) - need
			player.bounty_scrap = float(player.bounty_scrap) + _TD.tower_bounty_scrap(String(t.ctype))
			n += 1
	return n
