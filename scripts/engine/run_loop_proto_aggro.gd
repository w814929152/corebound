class_name RunLoopProtoAggro
extends RefCounted
##
## 🔒 第五刀 · 三轴合并 MC 重扫运行器（镜像 `RunLoopProto.run` / `RunLoopAggro.run`）
##
## 🔴 定位（**不动**金标本 `run_loop.gd` / `run_loop_proto.gd` / `run_loop_aggro.gd`）：
##   本文件是 `RunLoop.run` 的**三轴合并镜像**，唯一差异 = 战斗结算调
##   `WaveSimProtoAggro.simulate_wave_proto_aggro`（三原型 + Elite + 仇恨）
##   而非金标本 `simulate_wave`。`shop_ai.shop_phase` **一字不改**（金标本）
##   → 300 局 build 序列与金标本一致，只换每波战斗口径
##   → 得到「实机全开口径（RADIAL + proto + elite + aggro）」的起飞率，用于第五刀上线门禁。
##
## 判据（第五刀 · 上线门禁 · `docs/phase3/tower-aggro-golive-spec.md` §4.2）：
##   · 多塔 B 起飞率 ≥ 0.80（MC 300）← 硬门禁
##   · A 路径只作 INFO（H2 已裁决关闭，单核高风险为设计预期）
##
## 🔒 B 轮（2026-10-10）· V-7 修复接线补全（`tower-aggro-golive-impl.md` §「B 轮」/ 工单 B-3）：
##   现有全开 MC 跑的是 `repair_on_disable=0`（AI 从不修塔）= 真实玩家的**下界**。补全口径：
##   · `repair_on_disable=1`（FREE · 上界）：波次间无条件全修，挂本文件 run-loop 层。
##   · `repair_on_disable=2`（PRICED · 最接近产品）：走 `shop_ai` 既有开关守卫内的修复候选。
##   🔴 `repair_on_disable=0` 时**零扰动**（不注入 diag、不挂 FREE 清塔）→ 与原跑序逐位一致
##      （由 `tests/test_suite_aggro_golive.gd` 守护⑤钉死）。
##   🔴 `shop_ai.gd` / `wave_sim.gd` / `run_loop.gd` / `wave_sim_aggro.gd` 一字不改。
##
## ⚠️ Godot 坑：同 `run_loop.gd`（G1 整数除法 / G5 round banker's 走 Stats.pround）。
##

const _WaveSimProtoAggro := preload("res://scripts/engine/wave_sim_proto_aggro.gd")
const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")
## 🆕 关卡波表：只用来取「本关几波」（长度接管 `max_wave`，与 `WaveDirector.set_stage` 同口径）。
const _StageWaves := preload("res://scripts/data/stage_waves.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Stats := preload("res://scripts/engine/stats.gd")


# ---------------------------------------------------------------------------
# 镜像 RunLoop.run（唯一差异：simulate_wave → simulate_wave_proto_aggro）
#   stage_id   🆕 "" = 旧口径（20 波金标本）；非空 → 波数由波表长度接管
#   escalation 🆕 已守地区数 `S`
# ---------------------------------------------------------------------------
static func run(path: String, cfg: Dictionary, max_wave: int = 20, geo = null, rng = null,
		proto_enabled: bool = true, elite_enabled: bool = true, aggro_enabled: bool = true,
		exp: float = 0.6, attrition: float = -1.0, warmup_waves: int = 0,
		protect_core: bool = false, bulwark: bool = false, diag_out: Array = [],
		stage_id: String = "", escalation: int = 0) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	# 🆕 波数接管：与 `WaveDirector.set_stage` 同一条纪律 —— 表在则表说了算，
	#   表不在（未知 id）才用调用方给的 `max_wave`。🔴 `stage_id == ""` → 恒不执行。
	if stage_id != "":
		var wc := _StageWaves.wave_count(stage_id)
		if wc > 0:
			max_wave = wc
	# 🔒 B 轮（2026-10-10）· V-7 修复接线（**逐字移植**自 `run_loop_aggro.gd:41-52`）：
	#   `repair_on_disable==1`（FREE）挂 run-loop 层（本波 shop_phase 之后无条件全修）；
	#   `==2`（PRICED）走 `shop_ai` 既有开关守卫内的候选动作（shop_ai.gd 一行不改）。
	#   🔴 diag 只在 `!= 0` 且给足 6 槽时注入 → OFF(0) 臂 `c` 里无 diag 键 → shop_ai 读到 null
	#      → 逐位不变（**零扰动**，由 `-- aggro_golive` 守护⑤钉死）。
	if int(c.get("repair_on_disable", 0)) != 0 and diag_out != null and diag_out.size() >= 6:
		c["diag"] = diag_out
	if geo == null:
		geo = _Geo6.build_by_slots(int(c["n_slots"]))

	var player = _SimPlayer.new_player(path, c, geo)
	var core_hp := float(c["core_hp"])
	var rows: Array = []
	var cum := 0.0
	var cum_rerolls := 0
	# 🔒 B 轮 · V-7 诊断追踪（仅非 OFF 臂 diag 非 null）：last_repair_wave 供 [5] then_redied 判定。
	#   🔴 不加类型标注：OFF 臂 c.get 返回 null，标注 Array 会报 Nil→Array 错。
	var diag = c.get("diag", null)
	var last_repair_wave := 0

	for w in range(1, max_wave + 1):
		var res := _WaveSimProtoAggro.simulate_wave_proto_aggro(player, w, c, geo,
			proto_enabled, elite_enabled, aggro_enabled, exp, attrition, warmup_waves,
			protect_core, bulwark, stage_id, escalation)
		core_hp -= float(res["core_damage"])
		# 🔒 B 轮 · V-7 计数 [4]=n_repair_eligible（幂等）：本波有塔被打停 → 本局出现过 Disabled 塔。
		if diag != null and int(res["dis_new"]) > 0:
			diag[4] = 1
		# 🔒 B 轮 · V-7 计数 [5]=n_repair_then_redied（每局幂等）：本局**修复成交过**且**后续波
		#   又有塔被打停**（E-V3「修了也白修」证据）。每局最多 +1（幂等标记语义）。
		if diag != null and last_repair_wave > 0 and int(res["dis_new"]) > 0 and w > last_repair_wave:
			diag[5] = 1
		var income := float(res["scrap_earned"]) * (1.0 + float(player.income_mult))
		cum += income
		var fired_before := int(diag[1]) if diag != null else 0
		var shop := _ShopAI.shop_phase(player, cum, w, c, geo, rng)
		cum = float(shop[0])
		cum_rerolls += int(shop[1])
		# 🔒 B 轮 · V-7：记录本波修复成交的波次（供 [5] then_redied：修复后又在后续波被打停）。
		if diag != null and int(diag[1]) > fired_before:
			last_repair_wave = w

		# 🔒 B 轮 · V-7 repair_on_disable · FREE 臂（==1）：波次间安全窗**无条件**把所有
		#   Disabled 塔清标记 + 回满 HP，🔴 **不扣预算、不计 actions**（结构探针，不参与预算竞争）。
		#   挂在 shop_phase **之外**（镜像循环里）→ shop_ai.gd 对 FREE 臂零改动。
		#   🔴 金标本零改动：默认 repair_on_disable=0（OFF）→ 本段永不触及 → 逐位不变。
		if int(c.get("repair_on_disable", 0)) == 1:
			var n_cleared: int = _WaveSimAggro._clear_all_disabled(player)
			if diag != null:
				diag[1] = int(diag[1]) + n_cleared
				if n_cleared > 0:
					last_repair_wave = w

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
			"towers_disabled": int(res["towers_disabled"]),
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
		proto_enabled: bool = true, elite_enabled: bool = true, aggro_enabled: bool = true,
		exp: float = 0.6, attrition: float = -1.0, warmup_waves: int = 0,
		protect_core: bool = false, bulwark: bool = false,
		stage_id: String = "", escalation: int = 0) -> Dictionary:
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = actions
		var out := run(path, cx, max_wave, null, rng, proto_enabled, elite_enabled,
			aggro_enabled, exp, attrition, warmup_waves, protect_core, bulwark, [],
			stage_id, escalation)
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
