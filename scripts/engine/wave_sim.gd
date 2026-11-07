class_name WaveSim
extends RefCounted
##
## 离散战斗 —— dt = 0.1s 时间步进
##
## 金标本：corebound_sim_v03.py
##   `monster_stats()` (L395-403) / `simulate_wave()` (L406-452)
##
## 🔴 逐字对齐点（改这个文件前必读）
##   1) `limit = D + t_reach + 1e-9`，循环条件 `time <= limit`；`time` 用 `+= dt`
##      累加（浮点累进误差两边一致 —— 都是 IEEE754 double，0.1 是同一个 double）。
##   2) 刷新条件 `time >= spawned * interval - 1e-9`（`spawned` 是**已刷数量**，
##      第 spawned 只的刷新时刻 = spawned·interval）。
##   3) 集火顺序：`monsters.sort(key=lambda m: m[1])` —— 按**剩余到达时间升序**
##      （最快到核心的先挨打，即**最先刷出来的先挨打**）。Python 的 sort 是稳定的。
##      ★ 等价改写（性能关键）：在时刻 t，刷新于 s 的怪剩余时间 = t_reach − (t − s)
##        = t_reach − t + s ⇒ **剩余时间随刷新时刻单调递增**。
##        所以「按剩余时间升序」≡「按刷新顺序升序」≡ 当前 `monsters` 列表的
##        **正序**（列表按刷新先后追加，且 alive 原地压缩保持相对顺序）。
##        同一 tick 刷出的怪剩余时间相同（并列），稳定排序保持其插入序，
##        而它们 hp/剩余时间都相同，互换不影响结果。
##      → 实现上直接**正序遍历**，不做排序 —— 每波省掉 ~400 次排序。
##        等价性由 test_suite_slice2 的「朴素排序 vs 正序」对照测试守护。
##      ⚠️ 曾经写反过（倒序）：那等于" newest first "，老怪不挨打先漏，
##         决定性跑 W1 的漏怪数 2 → 6，整条判据链崩。别再改回去。
##   4) 伤害分配是**贪心**：`dmg` 依次打到队列最前面的怪，直到 dmg 耗尽。
##   5) `alive` 筛选：先判死（hp<=0 → 移除），否则剩余时间 -= dt，<=0 即漏怪。
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → `interval` 必须显式 float。
##   G2 `round(x)` 返回 float 且是**四舍五入远离零**；Python 的 `round` 是
##      banker's rounding。本文件里 `n = round(8.0 + 1.6w)` 的小数部分只可能是
##      {0,.2,.4,.6,.8}，永远不落在 .5 → 两种语义一致，无需特判。
##

const _DE := preload("res://scripts/engine/damage_engine.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _FpPow := preload("res://scripts/engine/fp_pow.gd")
## 🆕 战斗类型系统 —— 只在 combat_types_enabled 时按抗性分池结算（默认关 → 逐位不变）。
const _CombatTypes := preload("res://scripts/data/combat_types.gd")

const DT := 0.1


# ---------------------------------------------------------------------------
# v03 `monster_stats()` (L395-403)
# ---------------------------------------------------------------------------
static func monster_stats(w: int, cfg: Dictionary) -> Dictionary:
	# w−1 是整数 → pow_py 会改道 pow_int（正确舍入）；Godot 原生 pow 在这里也可能差 1 ULP
	var hp := float(cfg["hp_base"]) * _FpPow.pow_py(float(cfg["hp_growth"]), float(w - 1))
	var n := int(round(float(cfg["num_base"]) + float(cfg["num_growth"]) * float(w)))
	var spk := float(cfg["scrap_base"]) + float(cfg["scrap_growth"]) * float(w)
	var total_hp := float(n) * hp
	var D := _MvpConfig.wave_dur(w)
	var t_reach := float(cfg["t_reach"])
	return {
		"w": w, "hp": hp, "n": n, "scrap_per_kill": spk,
		"total_hp": total_hp, "D": D, "t_reach": t_reach,
		"threshold": total_hp / (D + t_reach),
	}


# ---------------------------------------------------------------------------
# v03 `simulate_wave()` (L406-452)
# ---------------------------------------------------------------------------
static func simulate_wave(player, w: int, cfg: Dictionary, geo = null) -> Dictionary:
	var ms := monster_stats(w, cfg)
	var D := float(ms["D"])
	var n := int(ms["n"])
	var hp_each := float(ms["hp"])
	var spk := float(ms["scrap_per_kill"])
	var t_reach := float(ms["t_reach"])

	var dps := _DE.dps_only(player, cfg, geo)
	# 🆕 战斗类型：读按攻击类型拆分的 DPS 池（🔴 默认关闭 → 走旧聚合口径，逐位不变）。
	var combat_on := bool(cfg.get("combat_types_enabled", false))
	var phys_dps := 0.0
	var magic_dps := 0.0
	var true_dps := 0.0
	# 🆕 破甲光环：波首从玩家塔列表算物抗/魔抗的全局破甲量（🔴 默认关闭 → 恒 0，逐位不变）。
	var phys_reduct := 0.0
	var magic_reduct := 0.0
	if combat_on:
		var byt: Dictionary = _DE.compute_dps(player, cfg, geo).get("dps_by_type", {})
		phys_dps = float(byt.get("physical", 0.0))
		magic_dps = float(byt.get("magic", 0.0))
		true_dps = float(byt.get("true", 0.0))
		var _ctypes: Array = []
		for _t in player.towers:
			_ctypes.append(String(_t.ctype))
		phys_reduct = _CombatTypes.armor_reduction(_ctypes, _CombatTypes.PHYSICAL)
		magic_reduct = _CombatTypes.armor_reduction(_ctypes, _CombatTypes.MAGIC)

	var spawn_span := D * _MvpConfig.spawn_window(w)
	var interval := spawn_span / float(maxi(1, n))

	var time := 0.0
	var spawned := 0
	var monsters: Array = []      # 每项 = [hp_remaining, time_to_reach, proto]
	var kills := 0
	var leaked := 0
	var scrap := 0.0
	var limit := D + t_reach + 1e-9

	while time <= limit:
		# ---- 刷新 ----
		while spawned < n and time >= float(spawned) * interval - 1e-9:
			monsters.append([hp_each, t_reach, "Swarm"])
			spawned += 1

		# ---- 集火（正序 == 按剩余时间升序，见文件头注 3）----
		if combat_on:
			# 🆕 类型分池：物攻池 / 魔攻池 / 真实池各自独立按「最接近核心优先」集火 + 溢出结转，
			#    每只怪按自身对应抗性减免伤害（Rush 魔抗 / Tank 物抗）；真实伤害无视抗性。
			#   🔴 三个池独立遍历同一怪物列表，顺序（物→魔→真）不影响最终击杀结果，
			#      因为各池伤害是加性的；分多次填满与一次混合填满的击杀/漏怪数一致。
			var phys_res := _apply_pool(monsters, phys_dps * DT, _CombatTypes.PHYSICAL, spk, phys_reduct)
			var magic_res := _apply_pool(monsters, magic_dps * DT, _CombatTypes.MAGIC, spk, magic_reduct)
			var true_res := _apply_pool(monsters, true_dps * DT, _CombatTypes.TRUE, spk, 0.0)
			kills += int(phys_res[0]) + int(magic_res[0]) + int(true_res[0])
			scrap += float(phys_res[1]) + float(magic_res[1]) + float(true_res[1])
		else:
			var dmg := dps * DT
			for m in monsters:
				if dmg <= 0.0:
					break
				if float(m[0]) <= dmg:
					dmg -= float(m[0])
					m[0] = 0.0
					kills += 1
					scrap += spk
				else:
					m[0] = float(m[0]) - dmg
					dmg = 0.0

		# ---- 前进：判死 / 漏怪（原地压缩，保持相对顺序）----
		var wpos := 0
		for m2 in monsters:
			if float(m2[0]) <= 0.0:
				continue
			m2[1] = float(m2[1]) - DT
			if float(m2[1]) <= 0.0:
				leaked += 1
				continue
			monsters[wpos] = m2
			wpos += 1
		monsters.resize(wpos)

		time += DT

	return {
		"w": w, "kills": kills, "leaked": leaked, "scrap_earned": scrap,
		"core_damage": float(leaked) * float(cfg["leak_damage"]), "dps": dps,
		"threshold": float(ms["threshold"]), "total_hp": float(ms["total_hp"]),
		"n": n, "hp_each": hp_each,
	}


# ---------------------------------------------------------------------------
# 参考实现（只用于单测对照）：**真的排序**，验证"倒序 ≡ 升序排序"这一等价改写
# ---------------------------------------------------------------------------
static func simulate_wave_naive(player, w: int, cfg: Dictionary, geo = null) -> Dictionary:
	var ms := monster_stats(w, cfg)
	var D := float(ms["D"])
	var n := int(ms["n"])
	var hp_each := float(ms["hp"])
	var spk := float(ms["scrap_per_kill"])
	var t_reach := float(ms["t_reach"])
	var dps := _DE.dps_only(player, cfg, geo)
	var spawn_span := D * _MvpConfig.spawn_window(w)
	var interval := spawn_span / float(maxi(1, n))

	var time := 0.0
	var spawned := 0
	var monsters: Array = []
	var kills := 0
	var leaked := 0
	var scrap := 0.0
	var limit := D + t_reach + 1e-9

	while time <= limit:
		while spawned < n and time >= float(spawned) * interval - 1e-9:
			monsters.append([hp_each, t_reach])
			spawned += 1
		# ★ 稳定排序：按剩余时间升序（插入排序，稳定）
		monsters = _stable_sort_by_time(monsters)
		var dmg := dps * DT
		for m in monsters:
			if dmg <= 0.0:
				break
			if float(m[0]) <= dmg:
				dmg -= float(m[0])
				m[0] = 0.0
				kills += 1
				scrap += spk
			else:
				m[0] = float(m[0]) - dmg
				dmg = 0.0
		var alive: Array = []
		for m2 in monsters:
			if float(m2[0]) <= 0.0:
				continue
			m2[1] = float(m2[1]) - DT
			if float(m2[1]) <= 0.0:
				leaked += 1
			else:
				alive.append(m2)
		monsters = alive
		time += DT

	return {
		"w": w, "kills": kills, "leaked": leaked, "scrap_earned": scrap,
		"core_damage": float(leaked) * float(cfg["leak_damage"]), "dps": dps,
		"threshold": float(ms["threshold"]), "total_hp": float(ms["total_hp"]),
		"n": n, "hp_each": hp_each,
	}


static func _stable_sort_by_time(arr: Array) -> Array:
	var out: Array = arr.duplicate()
	var i := 1
	while i < out.size():
		var key = out[i]
		var j := i - 1
		while j >= 0 and float(out[j][1]) > float(key[1]):
			out[j + 1] = out[j]
			j -= 1
		out[j + 1] = key
		i += 1
	return out


# ---------------------------------------------------------------------------
# 🆕 战斗类型：单一类型伤害池的集火（🔴 仅在 combat_types_enabled 时调用）
# ---------------------------------------------------------------------------
## 用「类型为 dmg_type 的伤害池 dmg（原始伤害量）」按「最接近核心优先」顺序打怪。
##   每只怪的 HP 扣减 = 原始伤害 × (1 − 有效抗性)，溢出结转时**消耗的原始伤害** =
##   打死该怪所需 HP ÷ (1 − 有效抗性)。返回 [kills, scrap_earned]。
##   `reduction` = 该类型的破甲量（`CombatTypes.armor_reduction`）；有效抗性 =
##   clamp(静态抗性 − reduction, 0, 1)。🔴 reduction=0 时有效抗性 == 静态抗性 → 逐位不变。
## 🔴 零扰动保证：当该类型有效抗性全为 0（如 Swarm 双抗 0）时，`(1−resist)=1` → 本函数
##   与旧聚合池逻辑**逐位同构**（`eff = dmg`、消耗 = `怪hp`），浮点序列完全一致。
static func _apply_pool(monsters: Array, dmg: float, dmg_type: String, spk: float, reduction: float = 0.0) -> Array:
	var kills := 0
	var scrap := 0.0
	if dmg <= 0.0:
		return [kills, scrap]
	for m in monsters:
		if dmg <= 0.0:
			break
		var proto := String(m[2])
		var resist := _CombatTypes.effective_resist(proto, dmg_type, reduction)
		var factor := 1.0 - clampf(resist, 0.0, 1.0)
		if factor <= 0.0:
			# 免伤（有效抗性 100%）→ 该类型打不动这只，伤害不消耗，继续看下一只
			continue
		# 实际能造成的伤害（原始伤害 × (1−有效抗性)）
		var eff := dmg * factor
		if float(m[0]) <= eff:
			# 击杀：消耗的原始伤害 = 怪hp ÷ (1−有效抗性)
			dmg -= float(m[0]) / factor
			m[0] = 0.0
			kills += 1
			scrap += spk
		else:
			m[0] = float(m[0]) - eff
			dmg = 0.0
	return [kills, scrap]
