class_name ShopAI
extends RefCounted
##
## 商店 + 贪心 AI —— 每轮枚举全部动作 → 算 ΔDPS/cost 性价比 → 取最大；
## 无划算动作则刷新（reroll）。
##
## 金标本：corebound_sim_v03.py
##   WEIGHTS (L458) / `draw_offers()` (L464) / `pity_card()` (L473) /
##   `_free_map_slots()` (L487) / `enumerate_actions()` (L492-546) /
##   `weakest_card()` (L549) / `drop_from()` (L565) / `apply_action()` (L575-612) /
##   `action_value()` (L615) / `action_cost()` (L627) / `shop_phase()` (L639-690)
##
## 🔴 逐字对齐点
##   S1 `draw_offers` 的保底：先 `set(choices(...))`，再 `add(force)`，
##      然后 `while len(s) > k: s.discard(rng.choice(sorted(s - {force})))`
##      —— 挤掉的是**除保底卡外**的随机一张；`sorted()` 是字典序，必须照做。
##   S2 `pity_card` 的主塔 = `max(towers, key=(Σattach, h))`，并列取靠前。
##   S3 动作枚举顺序：econ → 塔卡（TOWERS 插入序）→ 强化卡（REINF 插入序）。
##      这决定了 `max(scored, key=gain/cost)` 在**并列时取谁**（Python `max` 取第一个）。
##   S4 火焰库存摩擦 `fire_bought`：tag=="fire" 的卡（Cannon / FireUp）每买一次 +1，
##      达到 `fire_stock[path]`（A=6 / B=3）后本波不再出现该类动作。**每波重置**。
##   S5 `shop_phase` 的 max_actions 检查有两处：
##        · 循环顶 `actions >= max_actions` → break
##        · 要刷新前 `actions + 1 > max_actions` → break
##   S6 刷新价 `rc = max(1.0, reroll_base + reroll_growth*rerolls - reroll_disc)`；
##      `rc > budget` 直接 break（钱不够刷新就收工）。
##   S7 决定性跑（rng == null）时 `offers` 恒为 None → 枚举**全部**允许动作，
##      刷新只是烧钱；12 次动作上限就是"6 次购买 + 6 次刷新"的来源。
##
## ⚠️ Godot 坑
##   G1 `max(scored, key=...)` → 严格 `>` 实现（并列取靠前）。
##   G2 Python `set` → 这里用 Dictionary（name → true），只用于成员判定，语义等价。
##   G3 `apply_action` 返回 None（失败）在 GDScript 里用 `null`。
##

const _TD := preload("res://scripts/data/tower_data.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")

# ---- 卡池权重（v03 L458-461）----
const WEIGHTS := {
	"Arrow": 0.17, "Cannon": 0.17, "Frost": 0.13,
	"FireUp": 0.17, "FrostUp": 0.17, "ScrapUp": 0.095, "RerollD": 0.095,
}
const CARD_NAMES: Array = ["Arrow", "Cannon", "Frost", "FireUp", "FrostUp", "ScrapUp", "RerollD"]


static func _card_w() -> Array:
	var out: Array = []
	for nm in CARD_NAMES:
		out.append(float(WEIGHTS[nm]))
	return out


# ---- v03 ALL_CARDS（L49-55）：kind + tag；econ 类无 tag（Python 无该键 → None）----
static func card_kind(name: String) -> String:
	if _TD.TOWERS.has(name):
		return "tower"
	if _TD.REINF.has(name):
		return "reinforce"
	return "econ"


static func card_tag(name: String) -> String:
	if _TD.TOWERS.has(name):
		return _TD.tower_tag(name)
	if _TD.REINF.has(name):
		return _TD.reinf_tag(name)
	return ""


# ---------------------------------------------------------------------------
# v03 `draw_offers()` (L464-470)
# ---------------------------------------------------------------------------
static func draw_offers(rng, k: int, force) -> Dictionary:
	var s := {}
	var picks = rng.choices(CARD_NAMES, _card_w(), k)
	for nm in picks:
		s[String(nm)] = true
	if force != null and String(force) != "":
		s[String(force)] = true
		while s.size() > k:
			var rest: Array = []
			for nm2 in s:
				if String(nm2) != String(force):
					rest.append(String(nm2))
			rest.sort()
			var victim = rng.choice(rest)
			s.erase(String(victim))
	return s


# ---------------------------------------------------------------------------
# v03 `pity_card()` (L473-484)
# ---------------------------------------------------------------------------
static func pity_card(player):
	if player.towers.is_empty():
		return null
	# max(key=(Σattach, h))，并列取靠前（严格 >）
	var best = null
	var best_l := -1.0
	var best_h := -1.0
	for t in player.towers:
		var li := _SimPlayer.layers_of(t)
		var hi := float(t.h)
		if best == null or li > best_l or (li == best_l and hi > best_h):
			best = t
			best_l = li
			best_h = hi
	var tg := _TD.tower_tag(String(best.ctype))
	if tg == "":
		return null
	for rn in _TD.REINF:
		if _TD.reinf_tag(String(rn)) == tg:
			return String(rn)
	return null


# ---------------------------------------------------------------------------
# v03 `_free_map_slots()` (L487-489)
# ---------------------------------------------------------------------------
static func free_map_slots(player, cfg: Dictionary) -> Array:
	var used := {}
	for t in player.towers:
		used[int(t.slot)] = true
	var out: Array = []
	for s in range(int(cfg["n_slots"])):
		if not used.has(s):
			out.append(s)
	return out


# ---------------------------------------------------------------------------
# v03 `enumerate_actions()` (L492-546)
#   fire_bought: 本波已买的 tag=="fire" 卡数；offers: null = 决定性（不受商店限制）
# ---------------------------------------------------------------------------
static func enumerate_actions(player, cfg: Dictionary, fire_bought: int, offers, geo = null) -> Array:
	var acts: Array = []
	var path := String(player.path)
	var allowed: Array = _TD.ALLOWED[path]
	var fcap := float(cfg["fire_stock"][path])
	assert(String(cfg["tower_card_mode"]) == "map", "MVP 只用 map 模式（塔卡落塔位）")

	# 注：S3 —— 两个判定的内联版本（不用 lambda：GDScript 闭包捕获语义不如 Python 稳）
	var fire_bought_f := float(fire_bought)

	# ---- 经济（全局升级，不占卡位）----
	if (offers == null or offers.has("ScrapUp")) and float(player.income_mult) < 1.0:
		acts.append(["econ", "ScrapUp", null, null])

	# ---- 塔卡 ----
	var mt = cfg.get("max_towers")
	if mt == null:
		mt = {"A": 2, "B": int(cfg["n_slots"])}
	# ⚠️ player 是无类型 Variant → `.size()` 推不出来，必须显式 bool
	var can_build: bool = player.towers.size() < int(mt[path])
	for tname in _TD.TOWERS:
		var tn := String(tname)
		if not allowed.has(tn):
			continue
		if card_tag(tn) == "fire" and fire_bought_f >= fcap:
			continue
		if not (offers == null or offers.has(tn)):
			continue
		if can_build:
			for s in free_map_slots(player, cfg):
				acts.append(["build", tn, s, null])
		for t in player.towers:
			if String(t.ctype) == tn:
				acts.append(["up", tn, int(t.slot), null])

	# ---- 强化卡（只对该 Tag 的塔生效）----
	for rname in _TD.REINF:
		var rn := String(rname)
		if not allowed.has(rn):
			continue
		if card_tag(rn) == "fire" and fire_bought_f >= fcap:
			continue
		if not (offers == null or offers.has(rn)):
			continue
		for t in player.towers:
			if _TD.tower_tag(String(t.ctype)) != _TD.reinf_tag(rn):
				continue
			if player.cards.has(rn):
				acts.append(["reinf", rn, int(t.slot), null])
			elif player.cards.size() < int(cfg["backpack"]):
				acts.append(["reinf_new", rn, int(t.slot), null])
			else:
				var drop = weakest_card(player, cfg, geo)
				if drop != null and String(drop) != rn:
					acts.append(["reinf_swap", rn, int(t.slot), String(drop)])
	return acts


# ---------------------------------------------------------------------------
# v03 `weakest_card()` (L549-562)：丢弃后 DPS 损失最小的那张卡
# ---------------------------------------------------------------------------
static func weakest_card(player, cfg: Dictionary, geo = null):
	if player.cards.is_empty():
		return null
	var cur := _DE.dps_only(player, cfg, geo)
	var best = null
	var best_loss = null
	for name in player.cards:
		var s := _SimPlayer.snap(player)
		drop_from(player, String(name))
		var new_dps := _DE.dps_only(player, cfg, geo)
		_SimPlayer.rest(player, s)
		var loss := cur - new_dps
		if best_loss == null or loss < float(best_loss):
			best = String(name)
			best_loss = loss
	return best


# ---------------------------------------------------------------------------
# v03 `drop_from()` (L565-572)
# ---------------------------------------------------------------------------
static func drop_from(player, name: String) -> void:
	if _TD.TOWERS.has(name):
		player.cards.erase(name)
		var keep: Array = []
		for t in player.towers:
			if String(t.ctype) != name:
				keep.append(t)
		player.towers = keep
	else:
		player.cards.erase(name)
		for t in player.towers:
			t.attach.erase(name)


# ---------------------------------------------------------------------------
# v03 `apply_action()` (L575-612)：返回花费（float），失败返回 null
# ---------------------------------------------------------------------------
static func apply_action(player, act: Array, cfg: Dictionary):
	var kind := String(act[0])
	var name := String(act[1])
	var slot = act[2]
	var extra = act[3]

	if kind == "econ":
		player.income_mult = float(player.income_mult) + 0.20
		return float(_TD.PRICE["econ"])

	if kind == "build":
		var s = slot
		if s == null:
			var free := free_map_slots(player, cfg)
			if free.is_empty():
				return null
			s = free[0]
		if String(cfg["tower_card_mode"]) == "backpack":
			player.cards[name] = true
		player.towers.append(_PS.make_tower(int(s), name, 1, {}))
		return float(_TD.PRICE["tower"])

	if kind == "up":
		for t in player.towers:
			if int(t.slot) == int(slot):
				t.h = int(t.h) + 1
				return float(_TD.PRICE["tower"])
		return null

	if kind == "reinf" or kind == "reinf_new" or kind == "reinf_swap":
		if kind == "reinf_swap":
			drop_from(player, String(extra))
			player.cards[name] = true
		elif kind == "reinf_new":
			if player.cards.size() >= int(cfg["backpack"]):
				return null
			player.cards[name] = true
		elif not player.cards.has(name):
			return null
		for t in player.towers:
			if int(t.slot) == int(slot):
				t.attach[name] = int(t.attach.get(name, 0)) + 1
				return float(_TD.PRICE["reinforce"])
		return null
	return null


# ---------------------------------------------------------------------------
# v03 `action_value()` (L615-624)：(ΔDPS, cost)；失败 null
# ---------------------------------------------------------------------------
static func action_value(player, act: Array, cfg: Dictionary, geo = null):
	var before := _DE.dps_only(player, cfg, geo)
	var s := _SimPlayer.snap(player)
	var cost = apply_action(player, act, cfg)
	if cost == null:
		_SimPlayer.rest(player, s)
		return null
	var after := _DE.dps_only(player, cfg, geo)
	_SimPlayer.rest(player, s)
	return [after - before, float(cost)]


# ---------------------------------------------------------------------------
# v03 `action_cost()` (L627-636)
# ---------------------------------------------------------------------------
static func action_cost(act: Array, cfg: Dictionary, counts: Dictionary) -> float:
	var kind := String(act[0])
	var name := String(act[1])
	var base := 0.0
	if kind == "econ":
		base = float(_TD.PRICE["econ"])
	elif kind == "build" or kind == "up":
		base = float(_TD.PRICE["tower"])
	else:
		base = float(_TD.PRICE["reinforce"])
	return base + float(cfg.get("wave_price_step", 0.0)) * float(counts.get(name, 0))


# ---------------------------------------------------------------------------
# v03 `shop_phase()` (L639-690)：返回 [剩余预算, 本波刷新次数]
# ---------------------------------------------------------------------------
static func shop_phase(player, budget: float, w: int, cfg: Dictionary, geo = null, rng = null) -> Array:
	var rerolls := 0
	var actions := 0
	var fire_bought := 0
	var counts := {}
	var offers = null
	if rng != null:
		offers = draw_offers(rng, int(cfg["shop_offers"]),
			pity_card(player) if bool(cfg.get("pity", false)) else null)

	while budget > 0.0:
		var max_act = cfg.get("max_actions")
		if max_act != null and actions >= int(max_act):
			break
		var cands := enumerate_actions(player, cfg, fire_bought, offers, geo)
		var scored: Array = []
		for act in cands:
			var v = action_value(player, act, cfg, geo)
			if v == null:
				continue
			var gain := float(v[0])
			var cost := action_cost(act, cfg, counts)
			if gain <= 0.0 or budget < cost:
				continue
			scored.append([gain / cost, act, cost])
		if not scored.is_empty():
			var pick = scored[0]
			if rng != null and float(cfg.get("skill", 1.0)) < 1.0 and rng.random() > float(cfg["skill"]):
				pick = scored[rng.randrange(scored.size())]
			else:
				# Python max(key=第一个最大值)：严格 > 才替换
				for cand in scored:
					if float(cand[0]) > float(pick[0]):
						pick = cand
			var act2: Array = pick[1]
			var cost2 := float(pick[2])
			apply_action(player, act2, cfg)
			if card_tag(String(act2[1])) == "fire":
				fire_bought += 1
			counts[String(act2[1])] = int(counts.get(String(act2[1]), 0)) + 1
			budget -= cost2
			actions += 1
			continue

		# ---- 无划算动作 → 刷新 ----
		var rc := maxf(1.0, float(cfg["reroll_base"]) + float(cfg["reroll_growth"]) * float(rerolls)
			- float(player.reroll_disc))
		if rc > budget:
			break
		if max_act != null and actions + 1 > int(max_act):
			break
		budget -= rc
		rerolls += 1
		actions += 1
		if rng != null:
			offers = draw_offers(rng, int(cfg["shop_offers"]),
				pity_card(player) if bool(cfg.get("pity", false)) else null)
		elif rerolls > 400:
			break
	return [budget, rerolls]
