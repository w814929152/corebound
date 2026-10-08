class_name RunLoopProto
extends RefCounted
##
## 🔒 切片7 · S5-D1 校准闸门：三原型+Elite 版 MC 重扫运行器
##
## 🔴 定位（**不动金标本** `run_loop.gd`）：
##   本文件是 `RunLoop.run` 的**镜像**，唯一差异 = 战斗结算调
##   `WaveSimProto.simulate_wave_proto`（三原型+Elite）而非金标本 `simulate_wave`。
##   `shop_ai.shop_phase` **一字不改**（金标本）→ 300 局 build 序列与金标本一致，
##   只换每波的战斗口径 → 得到"三原型+Elite 下的起飞率"，用于 S5-D1 校准闸门判定。
##
## 判据（S5-D1 校准闸门）：
##   · 多塔 B 起飞率 ≥ 80%（MC 300）
##   · 起飞点 ∈ W10–15
##   · B/A（W20 ratio 比） < 1
##
## ⚠️ Godot 坑：同 `run_loop.gd`（G1 整数除法 / G5 round banker's 走 Stats.pround）。
##

const _WaveSimProto := preload("res://scripts/engine/wave_sim_proto.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Stats := preload("res://scripts/engine/stats.gd")


# ---------------------------------------------------------------------------
# 镜像 RunLoop.run（唯一差异：simulate_wave → simulate_wave_proto）
# ---------------------------------------------------------------------------
static func run(path: String, cfg: Dictionary, max_wave: int = 20, geo = null, rng = null,
		proto_enabled: bool = true, elite_enabled: bool = true) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	if geo == null:
		geo = _Geo6.build_by_slots(int(c["n_slots"]))

	var player = _SimPlayer.new_player(path, c, geo)
	var core_hp := float(c["core_hp"])
	var rows: Array = []
	var cum := 0.0
	var cum_rerolls := 0

	for w in range(1, max_wave + 1):
		var res := _WaveSimProto.simulate_wave_proto(player, w, c, geo, proto_enabled, elite_enabled)
		core_hp -= float(res["core_damage"])
		var income := float(res["scrap_earned"]) * (1.0 + float(player.income_mult))
		cum += income
		var shop := _ShopAI.shop_phase(player, cum, w, c, geo, rng)
		cum = float(shop[0])
		cum_rerolls += int(shop[1])

		var dps := _DE.dps_only(player, c, geo)
		var total_hp := float(res["total_hp"])
		var ratio := dps / total_hp if total_hp > 0.0 else 0.0

		rows.append({
			"w": w, "n": int(res["n"]),
			"hp_each_raw": float(res["hp_each"]), "total_hp_raw": total_hp,
			"eff_dps_raw": dps, "ratio_raw": ratio,
			"core_hp_raw": maxf(0.0, core_hp), "income_raw": income,
			"hp_each": _Stats.pround(float(res["hp_each"]), 1),
			"total_hp": _Stats.pround(total_hp, 1),
			"eff_dps": _Stats.pround(dps, 1),
			"ratio": _Stats.pround(ratio, 3),
			"core_hp": _Stats.pround(maxf(0.0, core_hp), 1),
			"income": _Stats.pround(income, 1),
			"rerolls": int(shop[1]), "cum_rerolls": cum_rerolls,
			"towers": player.towers.size(), "slots": player.cards.size(),
			"build": _SimPlayer.build_str(player),
			"kills": int(res["kills"]), "leaked": int(res["leaked"]),
		})
		if core_hp <= 0.0:
			break

	return {"rows": rows, "player": player}


# ---------------------------------------------------------------------------
# 镜像 Stats.takeoff_rate（MC 300，rng 跨所有 run 连续使用）
# ---------------------------------------------------------------------------
static func takeoff_rate(path: String, cfg: Dictionary, runs: int = 300,
		max_wave: int = 20, actions: int = 12, rng = null,
		proto_enabled: bool = true, elite_enabled: bool = true) -> Dictionary:
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = actions
		var out := run(path, cx, max_wave, null, rng, proto_enabled, elite_enabled)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := _Stats.takeoff_wave(rows)
		if alive and tw >= 0:
			takeoffs += 1
			hits.append(tw)
	return {
		"rate": _Stats.pround(float(takeoffs) / float(runs), 3),
		"surv": _Stats.pround(float(survives) / float(runs), 3),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
	}
