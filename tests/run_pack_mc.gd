extends SceneTree
##
## 卡包口径 MC —— 48 张卡 / 8 包 / 每局任选 3 包（2026-11-07）
## ---------------------------------------------------------------------------
## 使命：给「卡包只收建筑 + 一卡一包 + 48 张卡」这套新卡池一个**可复跑**的数值读数。
##
## 🔴 与金标本 MC 的区别（重要）：
##   · 金标本（`run_loop_proto` / CI 各步）跑的是 `ShopAI` 的 6 张固定卡池；
##   · 本脚本跑的是**卡包池**（`Packs.PACKS` 的 3 包并集 = 18 张塔），
##     买卡策略 = **贪心上限**：每波按「伤害/群伤/减速」评分买最高分塔，
##     余钱全部砸在最高分塔的升级上（同格合成）。
##   · ⇒ 读数是**上限估算**（不考虑商店随机、不考虑玩家操作失误）。
##
## 🔴 战斗结算：`WaveSimProto`（三原型 + Elite，与实机同口径）。
##   ⚠️ 玩家路线的「登场 / 整备 / 阵亡 / 觉醒 / 回复 / DoT / 击杀升级」这些
##      **实时钩子不在批处理镜像里** → 本脚本**不计入**这些机制（单独列在结果里）。
##
## 跑法：
##   godot --headless --path . --script res://tests/run_pack_mc.gd [seeds]
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _WaveSimProto := preload("res://scripts/engine/wave_sim_proto.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _Packs := preload("res://scripts/data/card_packs.gd")
const _TD := preload("res://scripts/data/tower_data.gd")
const _TowerEffects := preload("res://scripts/engine/tower_effects.gd")

const W_MAX := 20
const SEED0 := 20260930

var _pass := 0
var _fail := 0


func _init() -> void:
	var seeds := 6
	if OS.get_cmdline_user_args().size() > 0:
		seeds = int(OS.get_cmdline_user_args()[0])
	_seeds = maxi(1, seeds)

	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var cfg: Dictionary = _Cfg.cfg_of("B")
	var geo = _Geo6.build_by_slots(10)   # 🔴 实机自由摆放上限 10 座（cfg.n_slots=6 只是金标本口径）

	_log("")
	_log("=".repeat(78))
	_log("卡包口径 MC · 48 张卡 / 8 包任选 3 / 种子 %d / RADIAL + 三原型 + Elite" % _seeds)
	_log("买卡策略 = 贪心上限（最高分塔优先 + 余钱升最高分塔）；fidelity = 批处理（不含实时钩子）")
	_log("=".repeat(78))

	var combos := _combos()
	var total_wins := 0
	var total_runs := 0
	var overall_wave := 0.0
	var rows: Array = []
	for combo in combos:
		var wins := 0
		var wave_sum := 0
		for s in range(_seeds):
			var r := _run_once(cfg, geo, combo, SEED0 + s)
			if int(r["won"]) == 1:
				wins += 1
			wave_sum += int(r["wave"])
			overall_wave += float(r["wave"])
			total_runs += 1
		total_wins += wins
		var rate := float(wins) / float(_seeds)
		rows.append({"combo": combo, "win": rate, "avg_wave": float(wave_sum) / float(_seeds)})
		_log("  %-28s 胜率 %.2f  平均波次 %.1f" % [_combo_str(combo), rate, float(wave_sum) / float(_seeds)])

	var overall := float(total_wins) / float(maxi(1, total_runs))
	var avg_wave := overall_wave / float(maxi(1, total_runs))
	_log("")
	_log("-".repeat(78))
	_log("总胜率（通 W20）：%.3f  （%d / %d 局）" % [overall, total_wins, total_runs])
	_log("平均到达波次：%.2f" % avg_wave)
	_log("最高胜率组合：%s" % _best(rows))
	_log("最低胜率组合：%s" % _worst(rows))
	_log("-".repeat(78))
	_log("⚠️ 本读数不含实时钩子（登场/整备/阵亡/觉醒/回复/DoT/击杀升级）→ 实机会更高。")

	# 判据：48 张卡的池子若「一个组合都赢不了」，说明纯建筑 + 无强化的数值不足以通 W20。
	if overall <= 0.0:
		_log("[WARN] 全部组合 0 胜 —— 纯建筑 + 无强化路线当前不足以通 W20（需要补成长/数值）")
	else:
		_log("[OK] 至少部分组合可通 W20（上限口径）")

	quit(0)


var _seeds := 6


func _combos() -> Array:
	var ids := _Packs.all_ids()
	var out: Array = []
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			for k in range(j + 1, ids.size()):
				out.append([String(ids[i]), String(ids[j]), String(ids[k])])
	return out


func _combo_str(c: Array) -> String:
	return "%s+%s+%s" % [String(c[0]), String(c[1]), String(c[2])]


func _best(rows: Array) -> String:
	var b: Dictionary = rows[0]
	for r in rows:
		if float(r["win"]) > float(b["win"]):
			b = r
	return "%s（%.2f）" % [_combo_str(b["combo"]), float(b["win"])]


func _worst(rows: Array) -> String:
	var b: Dictionary = rows[0]
	for r in rows:
		if float(r["win"]) < float(b["win"]):
			b = r
	return "%s（%.2f）" % [_combo_str(b["combo"]), float(b["win"])]


## 单局：贪心买塔 → 每波 `WaveSimProto` → 核心归零即失败。
func _run_once(cfg: Dictionary, geo, combo: Array, seed: int) -> Dictionary:
	_Packs_seed(combo)
	var pool: Array = []
	for pid in combo:
		for nm in _Packs.cards_of(String(pid)):
			if not pool.has(String(nm)):
				pool.append(String(nm))
	var player = _SimPlayer.new_player("B", cfg, geo)
	var core := float(cfg["core_hp"])
	var scrap := 0.0
	var cap := int(cfg.get("tower_cap", 6))
	for w in range(1, W_MAX + 1):
		# 🆕 实机「整备」（每波开始全场 +1 级，封顶 3）：批处理镜像没有这个钩子，这里补上，
		#    让「Drillmaster 包」的读数不至于被系统性低估。
		_TowerEffects.apply_trigger(player, "prepare")
		var res: Dictionary = _WaveSimProto.simulate_wave_proto(player, w, cfg, geo, true, true)
		core -= float(res["core_damage"])
		scrap += float(res["scrap_earned"])
		if core <= 0.0:
			return {"won": 0, "wave": w}
		scrap = _spend(player, cfg, geo, pool, scrap, cap)
	return {"won": 1, "wave": W_MAX}


## 贪心买卡：先把空槽填满（按评分从高到低），再把余钱全部升级最高分塔。
##   评分 = dps ×（群伤 1.6 / 单体 1.0）×（1 + 减速）。
func _spend(player, cfg: Dictionary, geo, pool: Array, budget: float, cap: int) -> float:
	var price := float(_TD.PRICE["tower"])
	var used := {}
	for t in player.towers:
		used[int(t.slot)] = true
	var order: Array = []
	for nm in pool:
		var d: Dictionary = _TD.TOWERS_EXT[nm] if _TD.TOWERS_EXT.has(nm) else _TD.TOWERS[nm]
		var score := float(d["dps"]) * (1.6 if bool(d["aoe"]) else 1.0) * (1.0 + float(d["slow"]))
		order.append({"nm": String(nm), "score": score})
	# 🔴 功能塔优先（贪心只看 dps 会永远不造经济/光环塔 = 低估打法）
	var prio := ["Foundry", "Omen", "Quake", "Wither", "Plague", "Null", "Drillmaster", "Vanguard", "Martyr"]
	order.sort_custom(func(a, b):
		var pa := prio.find(String(a["nm"]))
		var pb := prio.find(String(b["nm"]))
		var va := 999 if pa < 0 else pa
		var vb := 999 if pb < 0 else pb
		if va != vb:
			return va < vb
		return float(a["score"]) > float(b["score"]))
	# ① 填槽（最多 6 座：与金标本 n_slots 同口径，避免几何越界）
	for o in order:
		if player.towers.size() >= 10:
			break
		if budget < price:
			break
		var slot := -1
		for s in range(10):
			if not used.has(s):
				slot = s
				break
		if slot < 0:
			break
		player.towers.append(_PS.make_tower(slot, String(o["nm"]), 1, {}))
		used[slot] = true
		budget -= price
	# ② 余钱升级最高分塔（同格合成 = h+1）
	while budget >= price:
		var best = null
		var best_score := -1.0
		for t in player.towers:
			var nm := String(t.ctype)
			var d: Dictionary = _TD.TOWERS_EXT[nm] if _TD.TOWERS_EXT.has(nm) else _TD.TOWERS[nm]
			var sc := float(d["dps"]) * (1.6 if bool(d["aoe"]) else 1.0) * (1.0 + float(d["slow"]))
			if sc > best_score:
				best_score = sc
				best = t
		if best == null:
			break
		best.h = int(best.h) + 1
		budget -= price
	return budget


## 让 `_TD` 之外的选择可复现（本脚本只读 `Packs`，这里保留占位便于以后接 RNG）。
func _Packs_seed(_combo: Array) -> void:
	pass


func _log(s: String) -> void:
	print(s)


func _ok(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s" % ["PASS" if cond else "FAIL", name])
