class_name DamageEngine
extends RefCounted
##
## =============================================================================
## 《守核 Corebound》伤害引擎（7 乘区）— GDScript 移植
## =============================================================================
## 金标本：design/phase2/numeric-sim/corebound_sim_v08_salvage.py :: compute_dps_v8 (L100-266)
##         （v0.8 = v0.6 引擎 + 唯一 hook：κ 广度折价的 N_tower 口径）
##
## 🔴 结算顺序锁死（damage-pipeline §2.2 / §5.1，乘法次序不得调换——浮点确定性）
##     逐塔：Base(h^0.6) → Stack → [Syn 已摘除] → Resonance → Focus → AllIn → Coverage
##     全局：ΣRaw → AoE → Crossfire → Aux → Empowerment
##
## 🔴 10 条红线（逐条对应到下面的行内注释标记 R-1..R-10）
##   R-1  7 乘区顺序
##   R-2  Syn 摘除：不得出现 synergy_mult=1.5 的一次性 Tag 乘区
##   R-3  κ 广度折价 disc = 0.01·clamp(N_tower−2,0,4)；N_tower 读 current | histmax（兜底①）
##   R-4  Focus 预热门槛：foc = 1 + 0.06·L_i·min(1, h_i/8)；L_i 与 h_i 解耦
##        （只建塔不投卡 → L=0 → Focus=1.00）
##   R-5  共鸣双向门槛：E_i = Σ_{j 邻居, h_i≥3 ∧ h_j≥3}(1+h_j)；Resonance=(1+κ_r)^E_i
##   R-6  AllIn 仅 i==core 且 L_i ≥ 0.6·ΣL 时 ×1.6，逐塔不泄漏到全局
##   R-7  Crossfire：n<2→1.0 / n=2→1.25 / n≥3→1.5（读当前塔数 n）
##   R-8  Aux：eff_slow = slow·h/(h+tau)，Aux = min(1.5, 1/(1−min(eff_slow,0.75)))
##   R-9  softcap：≤100 层 ×1.10、>100 层 ×1.03（衰减不归零，见 softcap.gd）
##   R-10 Stack 分组：只统计与塔同 Tag 的强化卡（异 Tag 跳过）
##
## ⚠️ Godot 坑（改这个文件前必读）
##   G1 `int / int` 是整数除法 → 所有期望 float 的除法都显式 cast。
##   G2 `**` 不是运算符，用 `pow(a, b)`；底数/指数都转 float。
##      🔴 但**整数指数**必须用 `FpPow.pow_int()`：Godot 的 `pow()` 在这些点上比
##      Python 的 `**` 差 1 ULP（采样 1731/2025），而 Python 侧恒为正确舍入。
##      见 fp_pow.gd 文件头。本文件里 `h ** 0.6` 走 pow_py（指数非整数 → 退回 pow）。
##   G3 `argmax` 无内建：Python `max(range(n), key=...)` 取**第一个**最大值，
##      这里用严格 `>` 实现同样语义（并列时取靠前的塔）—— 影响 CoreTower 选择。
##   G4 Dictionary 迭代顺序 = 插入顺序（与 Python 3.7+ 一致），浮点加法次序因此可复现。
##   G5 `cfg`/`attach` 取出的值是 Variant，`+` 可能变整数运算 → 统一 `float()`。
## =============================================================================

const _Softcap := preload("res://scripts/engine/softcap.gd")
const _TowerData := preload("res://scripts/data/tower_data.gd")
const _FpPow := preload("res://scripts/engine/fp_pow.gd")
const _FpSum := preload("res://scripts/engine/fp_sum.gd")
## 🆕 战斗类型系统（物理/魔法 × 物抗/魔抗）—— 只读攻击类型标注，不参与默认结算。
##   🔴 只在 `combat_types_enabled` 开关打开时被消费；默认关闭 → 逐位不变（见文件尾）。
const _CombatTypes := preload("res://scripts/data/combat_types.gd")


# ---------------------------------------------------------------------------
# 档位取值 —— 对应 v08 `_tier()` (L85-90)
#   tiers: [[阈值, 值], ...]，升序；取最后一个 inv>=阈值 的档；表首项即兜底
# ---------------------------------------------------------------------------
static func tier_of(inv: float, tiers: Array) -> float:
	var val := float(tiers[0][1])
	for row in tiers:
		if inv >= float(row[0]):
			val = float(row[1])
	return val


# ---------------------------------------------------------------------------
# 主入口
#   player: PlayerState（需 .path / .towers / .n_hist_max）
#   cfg:    MvpConfig.cfg_of(...)
#   geo:    Geo（null 时若 coverage_mode=="geometry" 会退回路径常量）
#   返回 { "total": float, "info": Dictionary }  —— 与 v08 的 (total, info) 一一对应
# ---------------------------------------------------------------------------
static func compute_dps(player, cfg: Dictionary, geo = null) -> Dictionary:
	var ts: Array = player.towers
	var n := ts.size()
	if n == 0:
		return {
			"total": 0.0,
			"dps_by_type": {"physical": 0.0, "magic": 0.0, "true": 0.0},
			"info": {
				"per_tower": [], "adj": [], "E": [], "aoe": 1.0, "crossfire": 1.0,
				"aux": 1.0, "empower": 1.0, "subtotal": 0.0, "core": 0, "L": [],
				"Ltot": 0.0, "kr": [], "kappa": [], "caps": [], "tag_invest": {},
				"tag_tower_lv": {}, "syn_hits": 0, "n_for_kappa": 0, "disc": 0.0,
			},
		}

	var path: String = player.path
	var lmin := float(cfg.get("link_min_level", 1))

	# ---- A3/A4：h_i（建筑卡层数）/ L_i（装配层数）----
	var h: Array = []
	var L: Array = []
	var Ltot := 0.0
	for t in ts:
		h.append(float(t.h))
		var li := 0.0
		for _rn in t.attach:
			li += float(t.attach[_rn])
		L.append(li)
		Ltot += li

	# ---- A5：CoreTower ----
	# G3：并列取第一个最大值（Python max(key=) 语义）
	var core := 0
	if Ltot > 0.0:
		var best := float(L[0])
		for i in range(1, n):
			if float(L[i]) > best:
				best = float(L[i])
				core = i

	# ---- A6：Tag 投入层数（κ / κ_r / StackCap 三条路径都读它）----
	var tag_invest := {}
	var tag_tower_lv := {}
	for i in range(n):
		var t = ts[i]
		var tg: String = _TowerData.tower_tag(t.ctype)
		if tg != "":
			tag_invest[tg] = float(tag_invest.get(tg, 0.0)) + float(h[i])
			tag_tower_lv[tg] = float(tag_tower_lv.get(tg, 0.0)) + float(h[i])
		for rn in t.attach:
			var rt: String = _TowerData.reinf_tag(rn)
			tag_invest[rt] = float(tag_invest.get(rt, 0.0)) + float(t.attach[rn])

	# ---- κ 判定：κ = κ_tag − 广度折价，下限 0.02 ----  R-3
	var kmode: String = String(cfg.get("kappa_mode", "path"))
	var ktiers: Array = cfg.get("ktag_tiers", [[0.0, 0.06], [3.0, 0.10]])

	# ★ v0.8 唯一 hook：N_tower 口径
	var n_for_kappa := n
	if String(cfg.get("ntower_mode", "current")) == "max":
		n_for_kappa = maxi(int(player.n_hist_max), n)
	var disc := 0.01 * float(mini(maxi(n_for_kappa - 2, 0), 4))

	var kappa: Array = []
	var caps: Array = []
	for i in range(n):
		var tg: String = _TowerData.tower_tag(ts[i].ctype)
		if kmode == "tier":
			var inv := float(tag_invest.get(tg, 0.0)) if tg != "" else 0.0
			var k := maxf(0.02, tier_of(inv, ktiers) - disc)
			var cap_i := float(cfg["reinf_cap"])
			if bool(cfg.get("stackcap_tier", false)):
				cap_i = tier_of(inv, cfg.get("stackcap_tiers", [[0.0, 50.0]]))
			kappa.append(1.0 + k)
			caps.append(cap_i)
		else:
			kappa.append(1.0 + (float(cfg["reinf_compound"][path]) - 1.0))
			caps.append(float(cfg["reinf_cap"]))
	# 🔒 T1 玩法③ 献祭：全局 StackCap+ 增益（player.stackcap_bonus）加到每塔 cap。
	#   🔴 金标本零改动：AI 不献祭 → bonus=0.0 → caps 逐位不变 → DPS 零影响（判据链不受影响）。
	#   逐位对齐：bonus>0 时走同一 dps_only 路径，实时版与批处理镜像都读同一 player 字段 → 一致。
	var _rite_bonus := 0.0
	if player != null and "stackcap_bonus" in player:
		_rite_bonus = float(player.stackcap_bonus)
	if _rite_bonus != 0.0:
		for ci in range(caps.size()):
			caps[ci] = float(caps[ci]) + _rite_bonus

	# ---- κ_r 判定（GDD §5.4 + §5.4.1 中性塔恒取基准档）----
	var krmode: String = String(cfg.get("kr_mode", "flat"))
	var krtiers: Array = cfg.get("kr_tiers", [[0.0, 0.040], [3.0, 0.045], [20.0, 0.050]])
	var neutral := float(cfg.get("kr_neutral", 0.045))
	var kr: Array = []
	for i in range(n):
		var tg: String = _TowerData.tower_tag(ts[i].ctype)
		if krmode == "tier":
			kr.append(tier_of(float(tag_invest.get(tg, 0.0)), krtiers) if tg != "" else neutral)
		else:
			kr.append(float(cfg["kappa_r"]))

	# ---- A2 链接图 + E_i ----  R-5
	var adj: Array = []
	var E: Array = []
	for _i in range(n):
		adj.append([])
		E.append(0.0)

	if bool(cfg["use_resonance"]) and geo != null:
		# 🆕 自由摆放：`geo.n`（槽位表长度）与「塔的 slot 号」不再天然一致 ——
		#   商店的 ΔDPS 预览会**凭空造一个塔**探针（`apply_action(["build", nm, null])`
		#   用 `free_map_slots` 取一个号的槽位），那个槽位号还没进 `geo.slots`。
		#   按 `max(geo.n, max_slot+1)` 建索引表即可；越界的那些槽在 `links()` 里
		#   由 `_dist_at()` 兜底成 INF（无边），不会改变任何已有塔的共振结果。
		# 🔴 金标本零扰动：金标本的 slot 恒 < n_slots == geo.n → gsize 恒等于 geo.n。
		var gsize: int = geo.n
		for t in ts:
			gsize = maxi(gsize, int(t.slot) + 1)
		var gtypes: Array = []
		for _k in range(gsize):
			gtypes.append("")
		for t in ts:
			gtypes[int(t.slot)] = String(t.ctype)
		var gadjs: Array = geo.links(gtypes, String(cfg["link_rule"]))
		for i in range(n):
			var t = ts[i]
			for gj in gadjs[int(t.slot)]:
				for k in range(n):
					if k != i and int(ts[k].slot) == int(gj):
						adj[i].append(k)
						# ★ 双向门槛：h_i >= link_min_level 且 h_k >= link_min_level
						if float(h[i]) >= lmin and float(h[k]) >= lmin:
							E[i] = float(E[i]) + 1.0 + float(h[k])
	elif bool(cfg["use_resonance"]):
		# 无几何：退化为「全互连」上限（仅用于理论扫参，MVP 不触发）
		for i in range(n):
			for k in range(n):
				if k != i:
					adj[i].append(k)
					if float(h[i]) >= lmin and float(h[k]) >= lmin:
						E[i] = float(E[i]) + 1.0 + float(h[k])

	var decay := float(cfg["softcap_decay"])

	# -----------------------------------------------------------------------
	# 阶段 B：逐塔（顺序固定 —— R-1）
	# -----------------------------------------------------------------------
	var per_tower: Array = []
	var syn_hits := 0
	for i in range(n):
		var t = ts[i]
		var ctype: String = String(t.ctype)

		# B1 Base = TowerDPS × h_i^0.6
		var base := _TowerData.tower_dps(ctype) * _FpPow.pow_py(float(h[i]), float(cfg["tower_stack_exp"]))

		# B2 Stack = 1 + Σ_r [softcap_pow(lv, 1+κ, cap, decay) − 1]   R-9 / R-10
		var stack := 1.0
		for rn in t.attach:
			if _TowerData.reinf_tag(rn) != _TowerData.tower_tag(ctype):
				continue  # R-10：异 Tag 卡跳过
			stack += _Softcap.pow_sc(float(t.attach[rn]), float(kappa[i]), float(caps[i]), decay) - 1.0

		# B3 Synergy —— 🔴 R-2：Syn 已摘除，本乘区恒为 1.0
		var syn := 1.0
		if bool(cfg.get("synergy_on", true)):
			var tg: String = _TowerData.tower_tag(ctype)
			if tg != "" and float(tag_tower_lv.get(tg, 0.0)) >= float(cfg["synergy_threshold"]):
				syn = float(cfg["synergy_mult"])
				syn_hits += 1

		# B4 Resonance = (1+κ_r)^E_i     R-5
		# E_i = Σ(1 + h_j) 恒为整数 → pow_int（正确舍入）
		var res := _FpPow.pow_int(1.0 + float(kr[i]), int(E[i])) if bool(cfg["use_resonance"]) else 1.0

		# B5 Focus —— R-4：预热门槛 min(1, h_i/8)，L_i 与 h_i 解耦
		var foc := 1.0
		if bool(cfg["use_focus"]):
			if bool(cfg.get("focus_full", false)):
				foc = 1.0 + float(cfg["focus_per_layer"]) * float(L[i])
			else:
				var fh := float(cfg.get("focus_min_h", 8.0))
				var ramp := minf(1.0, float(h[i]) / fh) if fh > 0.0 else 1.0
				foc = 1.0 + float(cfg["focus_per_layer"]) * float(L[i]) * ramp

		# B6 AllIn —— R-6：仅核心塔，且 L_i ≥ 0.6·ΣL
		var ali := 1.0
		if bool(cfg["use_allin"]) and Ltot > 0.0 and i == core and float(L[i]) >= float(cfg["allin_share"]) * Ltot:
			ali = float(cfg["allin_mult"])

		# B7 Coverage
		var cov := 0.0
		if String(cfg["coverage_mode"]) == "geometry" and geo != null:
			cov = geo.cov_at(int(t.slot), ctype)
		else:
			cov = float(cfg["path_coverage"][path])

		# ★ 乘法次序与 v08 逐字一致（左结合）
		var dps_i := base * stack * syn * res * foc * ali * cov
		# 🔒 T1 占位（mechanics-tower-life-death §0 / §4.3 交接点③）：塔死亡唯一落点。
		#    塔进入 Disabled 中间态 → 断输出不断链（E-T 口径）→ 本塔 dps 归零。
		#    🔴 MVP `disabled` 恒 false → 该乘数恒 1.0 → 对定稿 DPS 逐位零影响。
		dps_i *= 0.0 if bool(t.disabled) else 1.0
		per_tower.append({
			"base": base, "stack": stack, "syn": syn, "res": res,
			"focus": foc, "allin": ali, "cov": cov, "dps": dps_i,
			"disabled": bool(t.disabled),
			# 🆕 战斗类型：本塔攻击类型标注（🔴 additive 只读键，不改 dps 值 / 口径）。
			#   仅在 `combat_types_enabled` 时被聚合为 `dps_by_type`（见阶段 C 后）。
			"dmg_type": _CombatTypes.tower_dmg_type(ctype),
		})

	# -----------------------------------------------------------------------
	# 阶段 C：全局聚合（顺序固定 —— R-1）
	# -----------------------------------------------------------------------
	# C1 AoE 密度效率（只统计有 Tag 的塔的建筑卡层数；Arrow 无 Tag 不计入）
	# Python `aoe_total = sum(tag_tower_lv.values())` → 补偿求和
	var tv: Array = []
	for _tg in tag_tower_lv:
		tv.append(float(tag_tower_lv[_tg]))
	var aoe_total := _FpSum.sum_py(tv)
	var aoe := minf(float(cfg["aoe_cap"][path]), 1.0 + float(cfg["aoe_per"][path]) * aoe_total)

	# C2 Crossfire —— R-7
	var cf := 1.0
	if bool(cfg["use_crossfire"]):
		if n >= 3:
			cf = float(cfg["crossfire_3"])
		elif n >= 2:
			cf = float(cfg["crossfire_2"])

	# C3 挂件 Aux —— R-8
	var aux := 1.0
	if bool(cfg["use_aux"]):
		var aux_mode: String = String(cfg.get("aux_mode", "global"))
		if aux_mode == "per_tower":
			var aux_parts: Array = []
			for t in ts:
				var slow := _TowerData.tower_slow(String(t.ctype))
				var mult := 1.0
				if slow > 0.0:
					mult = 1.0 / (1.0 - minf(slow, 0.75))
					var c := float(cfg.get("aux_cap", 1.5))
					if mult > c:
						mult = c
				aux_parts.append(mult)
			for i in range(per_tower.size()):
				per_tower[i]["dps"] = float(per_tower[i]["dps"]) * float(aux_parts[i])
			# Python `aux = sum(aux_parts) / max(1, len(aux_parts))`
			aux = _FpSum.sum_py(aux_parts) / float(maxi(aux_parts.size(), 1))
		else:
			var slow_max := 0.0
			var h_slow_max := 0.0
			var any_slow := false
			for t in ts:
				var slow := _TowerData.tower_slow(String(t.ctype))
				if slow > 0.0:
					any_slow = true
					slow_max = maxf(slow_max, slow)
					h_slow_max = maxf(h_slow_max, float(t.h))
			if any_slow:
				var tau := float(cfg.get("aux_tau", 8.0))
				var eff_slow := slow_max * (h_slow_max / (h_slow_max + tau))
				aux = 1.0 / (1.0 - minf(eff_slow, 0.75))
				var c := float(cfg.get("aux_cap", 1.5))
				if aux > c:
					aux = c

	# C4 Empowerment —— MVP 关闭
	var empower := 1.0
	if bool(cfg.get("use_empowerment", false)):
		empower = 1.0 + float(cfg.get("empower_per_layer", 0.015)) * float(L[core])
		empower = minf(empower, float(cfg.get("empower_cap", 3.0)))

	# 🔴 Python `subtotal = sum(p["dps"] for p in per_tower)` —— 必须走补偿求和。
	#    朴素 `+=` 会让「同一多重集、不同排列」的两种构筑给出不同 subtotal，
	#    进而在贪心 AI 的并列动作上翻转选择（见 fp_sum.gd 文件头）。
	var dps_list: Array = []
	for p in per_tower:
		dps_list.append(float(p["dps"]))
	var subtotal := _FpSum.sum_py(dps_list)

	var total := subtotal * aoe * cf * aux * empower

	# -----------------------------------------------------------------------
	# 🆕 战斗类型：按攻击类型拆分 DPS（🔴 只在 combat_types_enabled 时计算）
	# -----------------------------------------------------------------------
	#   逐塔 dps_i 已含全部 7 乘区（base..cov）与 disabled 折损，但**不含**阶段 C 的
	#   全局乘区（aoe/cf/aux/empower）。这些全局乘区是「类型无关」的标量 → 对物/魔
	#   两条池**同乘**，故可先按类型对「逐塔 dps」求和，再统一乘全局乘区：
	#     dps_by_type[t] = Σ_{塔i, type_i==t} per_tower[i].dps  ×  (aoe·cf·aux·empower)
	#   这样 `total` 仍 = `dps_by_type[physical] + dps_by_type[magic]`（补偿求和一致）。
	#   🔴 默认关闭：`dps_by_type` 键仍写入（值 = 各类型分量，未乘抗性），但不改变
	#      `total` 的既有口径 —— 单测可用它断言「物+魔 = total」的恒等关系。
	var global_mult := aoe * cf * aux * empower
	var dps_by_type := {
		"physical": 0.0,
		"magic": 0.0,
		"true": 0.0,
	}
	var _phys_parts: Array = []
	var _magic_parts: Array = []
	var _true_parts: Array = []
	for p in per_tower:
		var pt := String(p.get("dmg_type", "physical"))
		var pd := float(p["dps"])
		if pt == _CombatTypes.MAGIC:
			_magic_parts.append(pd)
		elif pt == _CombatTypes.TRUE:
			_true_parts.append(pd)
		else:
			_phys_parts.append(pd)
	dps_by_type["physical"] = _FpSum.sum_py(_phys_parts) * global_mult
	dps_by_type["magic"] = _FpSum.sum_py(_magic_parts) * global_mult
	dps_by_type["true"] = _FpSum.sum_py(_true_parts) * global_mult

	return {
		"total": total,
		"dps_by_type": dps_by_type,
		"info": {
			"per_tower": per_tower, "adj": adj, "E": E, "aoe": aoe,
			"crossfire": cf, "aux": aux, "empower": empower, "subtotal": subtotal,
			"core": core, "L": L, "Ltot": Ltot, "kr": kr, "kappa": kappa,
			"caps": caps, "tag_invest": tag_invest, "tag_tower_lv": tag_tower_lv,
			"syn_hits": syn_hits, "n_for_kappa": n_for_kappa, "disc": disc,
		},
	}


static func dps_only(player, cfg: Dictionary, geo = null) -> float:
	return float(compute_dps(player, cfg, geo)["total"])
