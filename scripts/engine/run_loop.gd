class_name RunLoop
extends RefCounted
##
## 主循环：逐波 战斗 → 扣核心 HP → 结算收入 → 商店 → 记账
##
## 金标本：corebound_sim_v03.py `run()` (L703-738)
##
## 🔴 逐字对齐点
##   R1 `simulate_wave` 用的是**商店前**的 DPS（本波打的就是上波买出来的构筑）；
##      而记进 row 的 `eff_dps` 是**商店后**的 DPS —— 两者差一波，别合并。
##   R2 `ratio = dps / total_hp`，`total_hp` 是**本波**的总血量。
##   R3 收入 = 本波击杀废铁 × (1 + income_mult)；`cum` 是**跨波累积**的预算
##      （花不完留到下波，这就是为什么后期一路买爆）。
##   R4 核心 HP <= 0 立即 break（后面的波次 row 不存在）。
##   R5 row 里的绝大多数数值是 **round 过的**（与 v03 一致，CSV 也是 round 过的）；
##      本文件同时保留 `_raw` 全精度副本 —— 逐位对齐验证只看 `_raw`。
##
## ⚠️ Godot 坑
##   G1 `round()` 在 GDScript 里返回 float 且是四舍五入远离零；Python 是 banker's。
##      这里用 `pround()`（半值取偶）做等价，见 stats.gd。
##

const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Stats := preload("res://scripts/engine/stats.gd")


# ---------------------------------------------------------------------------
# v03 `run()` (L703-738)
#   返回 { "rows": Array[Dictionary], "player": PlayerState }
# ---------------------------------------------------------------------------
static func run(path: String, cfg: Dictionary, max_wave: int = 20, geo = null, rng = null) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	if geo == null:
		geo = _Geo6.build_by_slots(int(c["n_slots"]))

	var player = _SimPlayer.new_player(path, c, geo)
	var core_hp := float(c["core_hp"])
	var rows: Array = []
	var cum := 0.0
	var cum_rerolls := 0

	for w in range(1, max_wave + 1):
		var res := _WaveSim.simulate_wave(player, w, c, geo)
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
			# ---- 全精度（逐位对齐验证用）----
			"w": w, "n": int(res["n"]),
			"hp_each_raw": float(res["hp_each"]), "total_hp_raw": total_hp,
			"eff_dps_raw": dps, "ratio_raw": ratio,
			"core_hp_raw": maxf(0.0, core_hp), "income_raw": income,
			# ---- round 后的列（与 v03 / CSV 同名同值，判据统计只读这些）----
			"hp_each": _Stats.pround(float(res["hp_each"]), 1),
			"total_hp": _Stats.pround(total_hp, 1),
			"eff_dps": _Stats.pround(dps, 1),
			"ratio": _Stats.pround(ratio, 3),
			"core_hp": _Stats.pround(maxf(0.0, core_hp), 1),
			"income": _Stats.pround(income, 1),
			# ---- 计数 / 快照 ----
			"rerolls": int(shop[1]), "cum_rerolls": cum_rerolls,
			"towers": player.towers.size(), "slots": player.cards.size(),
			"build": _SimPlayer.build_str(player),
			"kills": int(res["kills"]), "leaked": int(res["leaked"]),
		})
		if core_hp <= 0.0:
			break

	return {"rows": rows, "player": player}
