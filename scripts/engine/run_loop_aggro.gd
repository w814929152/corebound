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
		warmup_waves: int = 0, protect_core: bool = false, bulwark: bool = false,
		sapper: bool = false, rite_bonus: float = 0.0, diag_out: Array = []) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	# 🔒 V-7 诊断容器注入（OFF 之外的两个臂）：diag_out 由调用方传入的可变 Array（引用），
	#   shop_phase / enumerate_actions 往里累加计数器。🔴 只在 repair_on_disable != 0 时注入
	#   → OFF 臂 c 里无 diag 键 → shop_ai 读到 null → 逐位不变（零扰动）。
	#   🟢 2026-10-09 加跑：放宽到 FREE 臂（原只 PRICED 有），以便把「修复成交次数」这个
	#      §3.7 计数器也打到 FREE 臂上（区分「修了也白修」vs「压根没修」）。
	#      🔴 零扰动仍然成立：OFF(0) 不注入；diag 是**只写**容器，不参与任何决策 →
	#      FREE/PRICED 的决策序列与 RNG 消费序列逐位不变（shop_ai 只在 ==2 分支读 diag）。
	# 🔒 防御：diag 容器必须是 6 槽 shape（`run()` 内会索引 diag[1]/[4]/[5]）。
	#    默认参数 `[]` 在 repair_on_disable != 0 时会越界 → 显式要求长度 ≥ 6。
	if int(c.get("repair_on_disable", 0)) != 0 and diag_out != null and diag_out.size() >= 6:
		c["diag"] = diag_out
	if geo == null:
		geo = _Geo6.build_by_slots(int(c["n_slots"]))

	var player = _SimPlayer.new_player(path, c, geo)
	# 🔒 T1 玩法③ 献祭诊断：注入 player.stackcap_bonus（模拟玩家已献祭累积的 StackCap+）。
	#   必须在波次循环**之前**设定 → 每波 dps_only 读到 bonus → 逐位反映增益。
	#   🔴 金标本零改动：默认 0.0 → stackcap_bonus 恒 0 → DPS 逐位不变。
	player.stackcap_bonus = rite_bonus
	var core_hp := float(c["core_hp"])
	var rows: Array = []
	var cum := 0.0
	var cum_rerolls := 0
	# 🔒 V-7 诊断追踪（仅 PRICED 臂 diag 非 null）：last_repair_wave 供 then_redied 判定。
	#   🔴 不加类型标注：OFF/FREE 臂 c.get 返回 null，标注 Array 会报 Nil→Array 错。
	var diag = c.get("diag", null)
	var last_repair_wave := 0
	# 🔒 V-8 肉盾循环：跨波累计诊断量（bulwark_uptime / gap_leak / reverb_* / revive_*）。
	#   🔴 纯累加，不参与任何决策 → 不进 rows、不改 row 形状 → 金标本零扰动。
	var v8_tot: Dictionary = {}

	for w in range(1, max_wave + 1):
		var res := _WaveSimAggro.simulate_wave_aggro(player, w, c, geo, aggro_enabled, exp, attrition, warmup_waves, protect_core, bulwark, sapper)
		var vd = res.get("v8_diag", null)
		if vd != null:
			for k in vd:
				v8_tot[k] = float(v8_tot.get(k, 0.0)) + float(vd[k])
		core_hp -= float(res["core_damage"])
		# 🔒 V-7 计数 [4]=n_repair_eligible（幂等）：本波有塔被打停 → 本局出现过 Disabled 塔。
		if diag != null and int(res["dis_new"]) > 0:
			diag[4] = 1
		# 🔒 V-7 计数 [5]=n_repair_then_redied（每局幂等）：本局**修复成交过**且**后续波
		#   又有塔被打停**（E-V3「修了也白修」证据）。🔴 每局最多 +1（用 diag[5] 标记位
		#   语义：只要本局满足过一次就置 1）——A 路径 2 塔，dis_new 不区分哪座塔，逐波累加
		#   会虚高（几乎每波 dis_new>0），故收敛为"每局是否发生过"的幂等标记。
		if diag != null and last_repair_wave > 0 and int(res["dis_new"]) > 0 and w > last_repair_wave:
			diag[5] = 1
		var income := float(res["scrap_earned"]) * (1.0 + float(player.income_mult))
		cum += income
		var fired_before := int(diag[1]) if diag != null else 0
		var shop := _ShopAI.shop_phase(player, cum, w, c, geo, rng)
		cum = float(shop[0])
		cum_rerolls += int(shop[1])
		# 🔒 V-7：记录本波修复成交的波次（供 then_redied：修复后又在后续波被打停）。
		if diag != null and int(diag[1]) > fired_before:
			last_repair_wave = w

		# 🔒 V-7 repair_on_disable · FREE 臂（QG-RADIAL-01 · §5-5 / E-V7）：
		#   波次间安全窗**无条件**把所有 Disabled 塔清标记 + 回满 HP，🔴 **不扣预算、
		#   不计 actions**（FREE = 结构探针，不参与预算竞争，否则"免费"会挤占 max_actions
		#   → 变成有代价的，E-V7）。挂在 shop_phase **之外**（镜像循环里）→ shop_ai.gd
		#   对 FREE 臂零改动（B-8）。
		#   🔴 金标本零改动：默认 repair_on_disable=0（OFF）→ 本段永不触及 → 逐位不变。
		if int(c.get("repair_on_disable", 0)) == 1:
			# 🔒 [1]=n_repair_fired 在 FREE 臂的语义 = **实际修复成交次数**（每次清掉一座
			#   Disabled 塔 +1；与 PRICED 臂同义）。🔴 只写计数器，不改任何决策 → 逐位不变。
			var n_cleared: int = _WaveSimAggro._clear_all_disabled(player)
			if diag != null:
				diag[1] = int(diag[1]) + n_cleared
				# 🔒 记录 FREE 臂修复成交波次（供 [5]=then_redied：修完下一波又被打停）。
				#    🔴 FREE 的成交发生在 shop_phase **之后**，上面 fired_before 快照抓不到，
				#       故在这里直接置位。只写计数器，不改决策 → 逐位不变。
				if n_cleared > 0:
					last_repair_wave = w

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

	return {"rows": rows, "player": player, "v8": v8_tot}


# ---------------------------------------------------------------------------
# 镜像 Stats.takeoff_rate（MC 300，rng 跨所有 run 连续使用）
# ---------------------------------------------------------------------------
static func takeoff_rate(path: String, cfg: Dictionary, runs: int = 300,
		max_wave: int = 20, actions: int = 12, rng = null,
		aggro_enabled: bool = true, exp: float = 0.6, attrition: float = -1.0,
		warmup_waves: int = 0, protect_core: bool = false, bulwark: bool = false,
		sapper: bool = false) -> Dictionary:
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = actions
		var out := run(path, cx, max_wave, null, rng, aggro_enabled, exp, attrition, warmup_waves, protect_core, bulwark, sapper)
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
