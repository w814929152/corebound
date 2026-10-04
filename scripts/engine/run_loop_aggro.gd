class_name RunLoopAggro
extends RefCounted
##
## 🔒 T1 · 仇恨版 MC 重扫运行器（镜像 `RunLoop.run` / `RunLoopProto.run`）
##
## 🔴 定位（**不动金标本** `run_loop.gd` / `run_loop_proto.gd`）：
##   本文件是 `RunLoop.run` 的**镜像**，唯一差异 = 战斗结算调
##   `WaveSimAggro.simulate_wave_aggro`（机会型仇恨 + 塔 HP + 塔死亡 DPS 下降）
##   而非金标本 `simulate_wave`。`shop_ai.shop_phase` **一字不改**（金标本）
##   → 300 局 build 序列与金标本一致，只换每波的战斗口径
##   → 得到"仇恨激活后的起飞率 / 塔死亡频率"，用于 T1 V-1~V-4 复验扫参。
##
## 判据（T1 复验 · Q-T12 = 定稿数值零改动只复验）：
##   · ATTRITION（复合比）扫参区间 [0.5, 8]（V-1）
##   · 塔死亡不应导致多塔流"一击致死"式崩塌（灾难 A）
##   · 雪崩期（W13+）塔死亡机制自然退场（DPS ≫ 怪物 HP）
##
## 🔴 塔死亡跨波延续：`player.towers` 的 `disabled` 状态跨波保留
##    （波首只重置未 Disabled 塔的 HP，Disabled 塔保持 Disabled，
##     留给后续批次的波次间「修复/拆除/放着不管」三选一）。
##
## ⚠️ Godot 坑：同 `run_loop.gd`（G1 整数除法 / G5 round banker's 走 Stats.pround）。
##

const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")


# ---------------------------------------------------------------------------
# 镜像 RunLoop.run（唯一差异：simulate_wave → simulate_wave_aggro）
# ---------------------------------------------------------------------------
static func run(path: String, cfg: Dictionary, max_wave: int = 20, geo = null, rng = null,
		aggro_enabled: bool = true, exp: float = 0.6, attrition: float = -1.0,
		warmup_waves: int = 0, protect_core: bool = false) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	if geo == null:
		geo = _Geo6.build() if int(c["n_slots"]) >= 6 else _Geo6.build4()

	var player = _SimPlayer.new_player(path, c, geo)
	var core_hp := float(c["core_hp"])
	var rows: Array = []
	var cum := 0.0
	var cum_rerolls := 0

	for w in range(1, max_wave + 1):
		var res := _WaveSimAggro.simulate_wave_aggro(player, w, c, geo, aggro_enabled, exp, attrition, warmup_waves, protect_core)
		core_hp -= float(res["core_damage"])
		var income := float(res["scrap_earned"]) * (1.0 + float(player.income_mult))
		cum += income
		var shop := _ShopAI.shop_phase(player, cum, w, c, geo, rng)
		cum = float(shop[0])
		cum_rerolls += int(shop[1])

		var dps := _DE.dps_only(player, c, geo)
		var total_hp := float(res["hp_each"]) * float(res["n"])
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
			"towers": player.towers.size(), "towers_disabled": int(res["towers_disabled"]),
			# 🔒 T1 V-1：本波**毛新增** Disabled 塔数（simulate_wave_aggro 内统计塔被打停
			#   次数，不受波次间修复干扰，恒 ≥0）→ 供判据 T-A/T-B/T-C 阶段平均。
			"dis_new": int(res["dis_new"]),
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
		aggro_enabled: bool = true, exp: float = 0.6, attrition: float = -1.0,
		warmup_waves: int = 0, protect_core: bool = false) -> Dictionary:
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = actions
		var out := run(path, cx, max_wave, null, rng, aggro_enabled, exp, attrition, warmup_waves, protect_core)
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
