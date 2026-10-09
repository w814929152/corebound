class_name WaveSimAggro
extends RefCounted
##
## 🔒 T1 · 仇恨版批处理战斗结算（镜像 `WaveDirector._substep`）
##
## 🔴 定位（**不动金标本** `wave_sim.gd` / `wave_sim_proto.gd`）：
##   本文件是 `WaveDirector._substep` 在 `tower_aggro_enabled = true` 时的
##   **批处理 static 镜像**，供 T1 仇恨激活后的 MC 重扫用（让 `shop_ai` 金标本
##   不变 → build 一致，只换战斗结算口径：加入机会型仇恨 + 塔 HP + 塔死亡 DPS 下降）。
##
##   与金标本 `simulate_wave` / `wave_sim_proto` 的差异（全部来自 Q-T2/Q-T3 定稿）：
##     · 每只怪携带 state / target_slot / m_dps（三态机会型仇恨）
##     · 塔有 HP（`HP0 × h^0.6`，波首满血）；AggroTower 怪对目标塔造成
##       `ATTRITION × HP0 × m_dps` 伤害；塔归零 → disabled → 本波 dps 重算下降
##     · AggroTower 怪**停下**（t_remain 冻结、不漏怪、不前进）
##
##   🔴 **tower_aggro_enabled = false → 完全退化为金标本口径**：无怪进 AggroTower、
##      塔 hp 恒满、dps 恒不重算 → 与 `simulate_wave` 逐位等价（由单测守护）。
##
## 🔴 逐位一致的保证（关键）：
##   ① 循环体**逐行复制** `WaveDirector._substep`（①刷新 ②集火 ③前进含仇恨怪冻结 ④仇恨）。
##   ② **塔状态单一数据源 = `player.towers`**（与实时版同）——塔 hp/disabled 直接写在
##      `player.towers[i]` 上（TowerState.hp/hp_max/disabled 字段，切片 T1 已加），
##      **不再维护独立 tower_hp 副本**。这样 `dps_only(player,...)` 重算读到的 disabled
##      与实时版一致 → 塔死后 DPS 下降逐位相同（曾踩"双份塔状态"坑：改副本 disabled
##      但 dps_only 读 player.towers → DPS 不降，AC-T1-9 kills 1 vs 10，已修）。
##   ③ 塔死亡重算 dps 的时机与实时版一致（`_damage_tower` 内重算写 dps_box）。
##
## 判据来源：`design/gdd/wave-spawner.md` v0.3 §2.6（仇恨状态机）
##          + `mechanics-tower-life-death.md` §2（HP0/AGGRO_R/Disabled）
## 数据来源：`scripts/data/monster_data.gd`（AGGRO_R/AGGRO_EXIT/ATTRITION/HP0/m_dps）
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → interval 显式 float。
##   G4 headless 闭包捕获标量局部变量不回写外层 → dps 用单元素 Array 可变容器（引用捕获）。
##   G6 headless `--script` 无 global_script_class_cache → 调用方一律 preload。
##

const _DE := preload("res://scripts/engine/damage_engine.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const DT := 0.1


# ---------------------------------------------------------------------------
# 仇恨版批处理战斗结算（镜像 WaveDirector._substep）
#   aggro_enabled : Q-T3 机会型仇恨（AGGRO_R = 9.0）
#   geo           : 🔴 仇恨开启时必传（提供塔位坐标做 dist 判定）
#   exp           : 塔 HP 指数（tower_stack_exp = 0.6）
# 怪物本地结构：[hp, t_remain, state, target_slot, m_dps]
#   state: 0=Marching 1=AggroTower
# ---------------------------------------------------------------------------
static func simulate_wave_aggro(player, w: int, cfg: Dictionary, geo,
		aggro_enabled: bool = true, exp: float = 0.6, attrition: float = -1.0,
		warmup_waves: int = 0, protect_core: bool = false, bulwark: bool = false,
		sapper: bool = false, trace_box = null) -> Dictionary:
	# 🔒 V-8 实时↔批处理逐位对照钩子（**纯诊断，零玩法语义**）：
	#   `trace_box` 传入**一个 Array**（非 null）时，每个子步末尾把「各塔 disabled 位」压成
	#   一个位掩码 append 进去 → 单测可拿它与实时版 `WaveDirector` 的逐子步快照**逐位比对**，
	#   证明两边的「塔死亡 / 复活时机」在同一子步上完全一致。
	#   🔴 默认 `null`（既有 11 参调用全部不传）→ `if trace_box != null` 守卫整段跳过 →
	#      **逐位零扰动**（不写任何塔状态、不改任何浮点、不改变循环次数）。仅单测显式传容器才生效。
	# 🔒 T1 肉盾塔诊断（bulwark）：模拟"玩家把主力塔放安全位"（理想肉盾策略）。
	#   必须在塔 HP 初始化 / 战斗结算**之前**重定位 → dps_only 重算读到新 slot 的 E。
	if bulwark and player != null and w > warmup_waves:
		_relocate_carry_to_safe(player, geo)
	# ---- 🔒 V-8 肉盾循环（`corebound-bulwark-death-cycle-v3`）----
	#   🔴 默认 `repair_on_disable=0` / `reverb_enabled=false` / `bulwark_diag=false`
	#      → 下面三件事**一个都不触发**，逐位不变（金标本零改动）。
	var revive_mode: int = int(cfg.get("repair_on_disable", 0))
	var v8: Array = [_new_v8_diag()]
	var D8: Dictionary = v8[0]
	if player != null and revive_mode >= 9:
		# 波首复位：每波每塔 K 次配额重来（v3 §3.1「每波两条命」）
		for t in player.towers:
			t.revive_t_disabled = 0.0
			t.revive_used_w = 0
		# B3 = 波首复活（`N → ∞` 极限档）。🔴 必须落在 `_init_tower_hp` 与 dps 重算**之前**
		#   → 复活的塔当波满血、且 `dps_only` 读到它已恢复输出。
		if revive_mode == 11 and w > warmup_waves:
			_wave_start_revive(player, cfg, geo, D8)
	var ms := _WaveSim.monster_stats(w, cfg)
	var D := float(ms["D"])
	var n := int(ms["n"])
	var hp_unit := float(ms["hp"])
	var spk := float(ms["scrap_per_kill"])
	var t_reach := float(ms["t_reach"])
	var dps := _DE.dps_only(player, cfg, geo)
	var spawn_span := D * _MvpConfig.spawn_window(w)
	var interval := spawn_span / float(maxi(1, n))
	var v0_ := _MonsterData.v0(_PathGeometry.TOTAL_LEN, t_reach)

	# ---- 塔 HP（波首满血，未 Disabled 的塔）——直接写 player.towers（单一数据源）----
	if player != null:
		_init_tower_hp(player, exp)
	var slot_positions: Array = _slot_positions(geo)
	# ---- V-8 埋点前置：残响开关 / 埋点开关 / 肉盾集合 ----
	# 🔴🔴🔴 残响（reverb_on / s_reverb / r2_reverb）属被砍机制，默认恒 false → 下方
	#    所有残响分支跳过。见文件头 + `mvp_config.gd` reverb_* 标注 / v8b-final-adjudication §2。
	var reverb_on: bool = bool(cfg.get("reverb_enabled", false))
	var diag_on: bool = bool(cfg.get("bulwark_diag", false))
	var s_reverb: float = float(cfg.get("reverb_slow", 0.30))
	var slow_dt: float = DT * (1.0 - s_reverb)
	var r2_reverb: float = float(cfg.get("reverb_radius", 9.0))
	r2_reverb = r2_reverb * r2_reverb
	var bulw_set: Array = []
	if diag_on:
		bulw_set = _bulwark_set(player, geo)

	# ---- 出生表（单一基准怪 = 金标本口径；仇恨版不含三原型分化）----
	# 🔒 T1 ⑤ Sapper 诊断：Elite 波里沿波次均匀铺开的精英怪 = Sapper（锁塔 ×3 增伤）。
	#   与实时版 WaveDirector._spawn_one 逐位对齐（同一 elite_indices 确定性算法）。
	#   🔴 金标本零改动：sapper=false → _sapper_flags 全 false → 行为完全不变。
	var _sapper_flags: Array = _build_sapper_flags(n, w, sapper)
	var time := 0.0
	var spawned := 0
	# 🔴 每项 = [hp, t_remain, state, target_slot, m_dps, sapper, theta]
	#   theta = 径向出生角（RADIAL 模式由黄金角序列派生；PATH 模式恒 0.0、不使用）。
	#   🔴 只影响"位置派生"，不碰 t_remain 递减 / 判漏 / 排序（金标本零扰动）。
	var monsters: Array = []
	var kills := 0
	var leaked := 0
	var scrap := 0.0
	var limit := D + t_reach + 1e-9
	# 🔴 Godot 坑（control-manifest §4）：headless 下内联 func() 捕获标量局部变量
	#    **不回写外层** → dps 用**单元素 Array 可变容器**（引用捕获）传递/回写。
	var dps_box: Array = [dps]
	# 🔒 T1 V-1：本波**毛新增** Disabled 塔数（塔在本波被打停的转换次数）。用单元素
	#    Array 计数器（同 dps_box，绕开 headless 闭包标量不回写坑）。区别于存量差：
	#    玩家波次间会修复 Disabled 塔 → 存量差可为负，毛新增恒 ≥0 才是判据要的量。
	var dis_new_box: Array = [0]

	while time <= limit:
		# ---- ① 刷新 ----
		while spawned < n and time >= float(spawned) * interval - 1e-9:
			var tr := t_reach / 1.0    # 单一基准怪 m_spd = 1.00
			# [hp, t_remain, state(Marching=0), target_slot(-1), m_dps(Swarm=0.60), sapper, theta]
			# 🔴 用 == true 取值（headless 下 bool() 构造器对 Array 元素 Variant 报错，
			#    == true 走比较运算不触发构造器，逐位安全）。
			# 🔴 theta：RADIAL 模式由黄金角序列派生（对齐实时版 wave_director._spawn_one），
			#    PATH 模式 spawn_theta 不被使用（位置走折线），恒 0.0。
			var th := 0.0
			if _SpaceModel.is_radial():
				th = _SpaceModel.spawn_theta(spawned, w)
			# 🔒 V-8：m[7] = 残响覆盖标记（是否被残响减速过）。🔴 只被残响块读写，
			#    reverb_enabled=false 时恒 false → 不参与任何判定 → 金标本零扰动。
			monsters.append([hp_unit, tr, 0, -1, float(_MonsterData.M_DPS["Swarm"]),
				_sapper_flags[spawned] == true, th, false])
			spawned += 1

		# ---- 🔒 V-8 埋点：本子步塔状态扫描（bulwark_uptime / gap 窗口 / reverb_uptime）----
		#   🔴 纯计数，不写任何塔状态、不改任何浮点 → 零扰动。diag_on=false 且
		#      reverb_on=false 时整段跳过（默认回归零开销）。
		var gap_on := false
		if diag_on or reverb_on:
			if player != null:
				var n_dis := 0
				for t in player.towers:
					if bool(t.disabled):
						n_dis += 1
				if reverb_on and n_dis > 0:
					D8["rev_up"] += 1.0
				# 🆕 `*_a` 系列只统计**场上有怪**的子步：`limit = D + t_reach` 让波次
				#    尾部有一段"场上无人"的空转，会把 uptime 系统性抬高。两个口径都打。
				var act: bool = monsters.size() > 0
				if diag_on and bulw_set.size() > 0:
					var all_down := true
					for ti in bulw_set:
						var tt = player.towers[ti]
						D8["bulw_total"] += 1.0
						if not bool(tt.disabled):
							D8["bulw_alive"] += 1.0
							all_down = false
						if act:
							D8["bulw_total_a"] += 1.0
							if not bool(tt.disabled):
								D8["bulw_alive_a"] += 1.0
					# 空窗期 = 肉盾线**整体**下线（全部暴露位非 carry 塔都 Disabled）
					gap_on = all_down
				D8["ticks"] += 1.0
				if act:
					D8["ticks_a"] += 1.0

		# ---- ② 集火（按 t_remain 升序 = 距核心最近优先；金标本口径恒正序）----
		_stable_sort_by_time(monsters)
		var dmg := float(dps_box[0]) * DT
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

		# ---- ③ 前进：判死 / 漏怪（AggroTower 冻结）----
		var alive: Array = []
		for m in monsters:
			if float(m[0]) <= 0.0:
				continue
			if int(m[2]) == 1:   # AggroTower：停下，冻结 t_remain，不漏怪
				alive.append(m)
				continue
			# 🔒 V-8 残响（`Reverb`）：Disabled 塔半径 `R_reverb` 内的**行进中**怪物
			#   `t_remain -= DT × (1 − s_reverb)`（怪照常前进，只是变慢）。
			#   🔴 只作用于 state=0（Marching）：AggroTower 怪是**冻结**在塔前的，
			#      对它施加减速 = 让它往前爬 → 那是"位移"不是"减速"，与 v3 §4.2 定性不符。
			#   🔴🔴🔴 残响已被砍（不采纳勿启用）：整段被 `if reverb_on:` 守卫，
			#      `reverb_enabled=false`（默认/回归恒值）时**逐行跳过** → 金标本零扰动。
			#      见文件头 + `mvp_config.gd` reverb_* 标注 / v8b-final-adjudication.md §2。
			var step_dt := DT
			if reverb_on:
				var st0 := int(m[2])
				var tg0 := int(m[3])
				if _in_reverb(m, v0_, slot_positions, player, r2_reverb):
					step_dt = slow_dt
					D8["rev_slow"] += DT * s_reverb
					if not bool(m[7]):
						m[7] = true
						D8["rev_cov"] += 1.0
				# 🔴 硬断言运行时守卫：残响**只许写 m[1] / m[7]**，绝不得触碰仇恨锁定
				#   （`reverb_aggro_disturb` 必须恒 0 —— v3 §6.2 护栏 ⑧ / §10-6）
				if int(m[2]) != st0 or int(m[3]) != tg0:
					D8["rev_disturb"] += 1.0
			m[1] = float(m[1]) - step_dt
			if float(m[1]) <= 0.0:
				leaked += 1
				if bool(m[7]):
					D8["rev_cov_leak"] += 1.0
				if gap_on:
					D8["gap_leak"] += 1.0
			else:
				alive.append(m)
		monsters = alive

		# ---- ④ 仇恨行为（Q-T3 机会型仇恨）----
		#   🔒 T1 起手保护（warmup_waves，默认 0 = 不保护，金标本零改动）：
		#   当 >0 时，W1..warmup 期间仇恨不激活（塔不会被打死），让"起手单暴露塔"
		#   金标本配置有喘息期——否则起手塔 W1 必死、机制在玩家有冗余塔之前就造成崩盘
		#   （对照诊断证实 aggro=true 无保护时起飞率 0%）。机制从 W(warmup+1) 起才致命，
		#   贴合 GDD「苟活期可感知、成型期才致命」的意图。🔴 仅扫参显式启用（可回退）。
		if aggro_enabled and w > warmup_waves:
			_apply_aggro(monsters, v0_, slot_positions, cfg, player, geo, dps_box,
				_MonsterData.resolve_attrition(attrition), dis_new_box, protect_core, sapper, v8)
		# ---- ⑤ 战斗中复活（v3 §3 · 被动/系统发起 · 波内 `N` 秒后自动重启）----
		#   🔴 默认 repair_on_disable=0 → 不触发。
		if revive_mode >= 9 and revive_mode != 11 and w > warmup_waves:
			_tick_revive(player, cfg, geo, dps_box, D8, exp)

		# ---- ⑥ 逐位对照钩子（纯诊断）---- `trace_box` 为 null 时整行跳过。
		if trace_box != null:
			trace_box.append(_disabled_mask(player))

		time += DT

	var core_dmg := float(leaked) * float(cfg.get("leak_damage", 50.0))
	return {
		"w": w, "kills": kills, "leaked": leaked, "scrap_earned": scrap,
		"core_damage": core_dmg, "dps": float(dps_box[0]),
		"threshold": hp_unit * float(n) / (D + t_reach),
		"n": n, "hp_each": hp_unit,
		"towers_disabled": _count_disabled(player),
		"dis_new": int(dis_new_box[0]),
		# 🔒 V-8 诊断量（本波）。🔴 纯计数，不参与战斗结算 → 金标本零扰动。
		"v8_diag": D8,
	}


# ---------------------------------------------------------------------------
# 🔒 T1 肉盾塔诊断（bulwark）：把主力塔重定位到安全位（模拟"玩家理想保塔"）
# ---------------------------------------------------------------------------
## 把 h 最高的主力塔移到**安全位**（d_path > AGGRO_R，打不到），量化"保命 vs 降 E/DPS"
##   的净效果。若目标安全位已有塔，则把它换到主力塔**旧的暴露位**充当肉盾（扛伤）。
##   🔴 纯 slot 交换：塔数、h 值、装配卡都不变，只改各塔落位 → dps_only 重算读到新 E。
##   🔴 与 protect_core 的差异：protect_core = 主力塔隐身（怪物跳过它，塔仍在暴露位、
##      E 不变）；bulwark = 主力塔**真挪到安全位**（E 会变，因为安全位 S4/S5 度 3、
##      非枢纽 → 共鸣下降），更贴近玩家真实保塔操作，代价是 DPS 下降。
##   🔴 金标本零改动：默认不启用（bulwark=false），运行时/扫参不传则行为完全不变。
##   🔴 仅在 w > warmup_waves 时调用（与仇恨激活同门槛，起手保护期不重定位）。
static func _relocate_carry_to_safe(player, geo) -> void:
	if player == null or geo == null:
		return
	var slots: Array = []
	for p in geo.slots:
		slots.append(p)
	# 找主力塔 = h 最高的**未 Disabled** 塔（金标本 AI 认定的 carry；单核流 A 全押这一座）。
	#   🔴 跳过已 Disabled 塔：死塔无需保（保它无意义），且避免把活塔换到死塔位。
	var carry_idx := -1
	var carry_h := -1
	for i in range(player.towers.size()):
		var t = player.towers[i]
		if bool(t.disabled):
			continue
		if int(t.h) > carry_h:
			carry_h = int(t.h)
			carry_idx = i
	if carry_idx < 0:
		return
	var carry_slot := int(player.towers[carry_idx].slot)
	# 安全位：PATH = d_path > AGGRO_R（S4/S5）；RADIAL = expo_frac < EXPO_SAFE_MAX（D-3 定稿 0.15）。
	# 🔴 按模式分派：PATH 逐位不变（金标本默认 bulwark=false 不触发，但事实层不能变）。
	var rows: Array
	if _SpaceModel.is_radial():
		rows = _PathGeometry.slot_exposure_radial(
			slots, _MonsterData.AGGRO_R, _SpaceModel.core_pos(),
			_PathGeometry.EXPO_SAFE_MAX)
	else:
		rows = _PathGeometry.slot_exposure(slots, _MonsterData.AGGRO_R)
	var safe_slots: Array = []
	for r in rows:
		if not bool(r["is_exposed"]):
			safe_slots.append(int(r["slot"]))
	# 主力塔已在安全位 → 无需动（玩家已保塔）
	if safe_slots.has(carry_slot):
		return
	# 目标安全位：优先未被占的；否则占一个安全位并把它的塔换到 carry 旧暴露位（肉盾）
	var target_safe := -1
	for s in safe_slots:
		if not _slot_has_tower(player, s):
			target_safe = s
			break
	if target_safe < 0:
		target_safe = int(safe_slots[0])   # 全被占 → 取第一个安全位（交换）
	var occupant_idx := _tower_index_at(player, target_safe)
	if occupant_idx >= 0:
		# 交换：安全位的塔 → carry 旧的暴露位（充当肉盾，扛伤）
		player.towers[occupant_idx].slot = carry_slot
	# 主力塔 → 安全位
	player.towers[carry_idx].slot = target_safe


## 某塔位是否有塔。
static func _slot_has_tower(player, slot: int) -> bool:
	for t in player.towers:
		if int(t.slot) == slot:
			return true
	return false


## 取某塔位上的塔在 player.towers 的下标，无则 -1。
static func _tower_index_at(player, slot: int) -> int:
	for i in range(player.towers.size()):
		if int(player.towers[i].slot) == slot:
			return i
	return -1


# ---------------------------------------------------------------------------
# 塔 HP 初始化（波首满血，未 Disabled 的塔）——直接写 player.towers（单一数据源）
# ---------------------------------------------------------------------------
static func _init_tower_hp(player, exp: float) -> void:
	if player == null:
		return
	for t in player.towers:
		if not bool(t.disabled):
			t.hp_max = _MonsterData.tower_hp(int(t.h), exp)
			t.hp = t.hp_max


static func _slot_positions(geo) -> Array:
	var out: Array = []
	if geo != null and "slots" in geo:
		for p in geo.slots:
			out.append(p)
	return out


static func _count_disabled(player) -> int:
	if player == null:
		return 0
	var c := 0
	for t in player.towers:
		if bool(t.disabled):
			c += 1
	return c


# ---------------------------------------------------------------------------
# 🔒 V-7 repair_on_disable（QG-RADIAL-01 · 诊断开关）：清 Disabled 标记 + 回满 HP
# ---------------------------------------------------------------------------
## 把指定塔位（slot）上处于 Disabled 的塔**恢复为可用**：清 `disabled` 标记 +
##   `hp = hp_max`。🔴 **不动 `h`、不动 `attach`、不动 `n_hist_max`**（E-T6 / §2.3
##   口径：修复只恢复 HP 与输出，不改任何层数/装配/历史最大塔数）。
##
## 🔴 与实时版 `shop_runtime.repair_tower()`（:989）同式：清 disabled + hp = hp_max。
##   批处镜像里 `hp_max` 由 `_init_tower_hp` 在波首按 `HP0 × h^0.6` 设定，修复时
##   直接回满到该 hp_max 即可（下一波波首也会自动回满，修复的真正意义是**清
##   disabled 标记恢复 DPS**，不是补 HP 数值 —— §2.4）。
##
## 🔴 金标本零改动：本 helper 只在 `repair_on_disable != 0` 的臂里被调用（FREE 臂
##   在 run_loop_aggro、PRICED 臂在 shop_ai apply_action），OFF 臂永不触及 → 逐位不变。
##
## 返回 true = 确实清了一座 Disabled 塔；false = 该槽位无塔或本就未 Disabled。
static func _clear_disabled(player, slot: int) -> bool:
	if player == null:
		return false
	for t in player.towers:
		if int(t.slot) == slot:
			if not bool(t.disabled):
				return false
			t.disabled = false
			t.hp = t.hp_max
			return true
	return false


## 清 player 上**所有** Disabled 塔（FREE 臂专用：波次间无条件全修，不占预算）。
## 返回被清掉的塔数。🔴 同样不动 h / attach / n_hist_max。
static func _clear_all_disabled(player) -> int:
	if player == null:
		return 0
	var n := 0
	for t in player.towers:
		if bool(t.disabled):
			t.disabled = false
			t.hp = t.hp_max
			n += 1
	return n


# ===========================================================================
# 🔒 V-8 肉盾循环（`corebound-bulwark-death-cycle-v3`）
#    🆕 战斗中复活（M-1）+ 残响减速场（M-1b / `Reverb`）
#    🔴 全部挂诊断开关，默认 off，off 时逐位不变（金标本零改动）
#
# 🔴🔴🔴 残响 `Reverb`（下方 M-1b 相关代码：`_in_reverb` / ③前进段减速 / reverb_* 计数）
#   **已被砍，不采纳，默认不得启用**。依据 `docs/phase3/qg-radial/v8b-final-adjudication.md`
#   §2：去混淆实证全剂量域无正向胜率边际 → 裁决砍（默认）。保留代码供复现 / 未来
#   「纯体验层重启评估」（§2.4 ① 世界观同源论证未被推翻）。🔴 只许在显式扫参臂里打开
#   `reverb_enabled`，任何默认 / 回归 / golden_reference 路径下必须恒 false → 逐位不变。
#   🟢 复活 M-1（下方 `_try_revive` / `_tick_revive` / `_wave_start_revive` / `_death_snapshot`）
#   是采纳项，独立于残响，不受此标注影响。
# ===========================================================================

## V-8 诊断量容器（单波）。🔴 全部用 float 计数（headless 下 Array 元素 Variant
##   类型不稳，float 最不容易踩 Nil/int 混用坑），只在打印时按需取整。
static func _new_v8_diag() -> Dictionary:
	return {
		"bulw_alive": 0.0,   # 肉盾线未 Disabled 的「塔·子步」数（bulwark_uptime 分子）
		"bulw_total": 0.0,   # 肉盾线「塔·子步」总数（bulwark_uptime 分母）
		"gap_leak": 0.0,     # 空窗期（肉盾线整体 Disabled）内新产生的漏怪数
		"gap_unlocked": 0.0, # 因目标塔 Disabled 而被解锁的怪物次数
		"rev_slow": 0.0,     # reverb_slow_seconds（残响拖住的秒数 = s×步数×DT）
		"rev_up": 0.0,       # 残响生效子步数（reverb_uptime 分子）
		"rev_cov": 0.0,      # reverb_covered_monsters（入过场的怪物数）
		"rev_cov_leak": 0.0, # 入过场但最终漏掉的怪物数
		"rev_disturb": 0.0,  # 🔴 reverb_aggro_disturb（硬断言，必须恒 0）
		"bulw_alive_a": 0.0, # 同上，但只统计**场上有怪**的子步（战斗在线率）
		"bulw_total_a": 0.0,
		"ticks_a": 0.0,
		"revive_fired": 0.0, # 战斗内/波首重启成交次数
		"revive_elig": 0.0,  # 合格死亡事件数（暴露位 & 非 carry）
		"revive_redied": 0.0,# 重启后又死（履职证明，不判负）
		"revive_refused": 0.0, # 🆕 闸门口**正确拒绝**的次数（carry 死 / 非暴露位死）
		"carry_death": 0.0,  # 🆕 死亡时刻是 carry 的死亡事件数（v2 §7.3-5 故障护栏量）
		"nonexp_death": 0.0, # 🆕 死亡时刻在非暴露位的死亡事件数
		"nosnap_death": 0.0, # 🆕 无死亡快照却进入重启判定的次数（应恒 0）
		"revive_misq": 0.0,  # 🔴 revive_misqualify（硬断言：已落地的重启违反资格，必须恒 0）
		"ticks": 0.0,        # 本波子步总数（uptime 类分母）
	}


## 肉盾集合 = **暴露位 & 非 carry** 的塔（在 `player.towers` 里的下标）。
##   🔴 与 `_relocate_carry_to_safe` / `protect_core` 同一 carry 口径（h 最高的未 Disabled 塔）。
static func _bulwark_set(player, geo) -> Array:
	var out: Array = []
	if player == null or geo == null:
		return out
	var slots: Array = _slot_positions(geo)
	var rows: Array
	if _SpaceModel.is_radial():
		rows = _PathGeometry.slot_exposure_radial(
			slots, _MonsterData.AGGRO_R, _SpaceModel.core_pos(),
			_PathGeometry.EXPO_SAFE_MAX)
	else:
		rows = _PathGeometry.slot_exposure(slots, _MonsterData.AGGRO_R)
	var expo: Dictionary = {}
	for r in rows:
		expo[int(r["slot"])] = bool(r["is_exposed"])
	var carry_idx := -1
	var carry_h := -1
	for i in range(player.towers.size()):
		var t = player.towers[i]
		if bool(t.disabled):
			continue
		if int(t.h) > carry_h:
			carry_h = int(t.h)
			carry_idx = i
	for i in range(player.towers.size()):
		if i == carry_idx:
			continue
		if bool(expo.get(int(player.towers[i].slot), false)):
			out.append(i)
	return out


## 死亡时刻资格快照（v3 §3.3 安全红线）：`is_exposed` + 非 carry。
##   🔴 必须在 `t.disabled = true` **之前**取（此时本塔尚属"未 Disabled"，
##      carry 判定与 `_relocate_carry_to_safe` 同口径）。
static func _death_snapshot(t, player, geo, D8: Dictionary, revive_mode: int) -> void:
	var slot: int = int(t.slot)
	var exposed := false
	if geo != null:
		var slots: Array = _slot_positions(geo)
		var rows: Array
		if _SpaceModel.is_radial():
			rows = _PathGeometry.slot_exposure_radial(
				slots, _MonsterData.AGGRO_R, _SpaceModel.core_pos(),
				_PathGeometry.EXPO_SAFE_MAX)
		else:
			rows = _PathGeometry.slot_exposure(slots, _MonsterData.AGGRO_R)
		for r in rows:
			if int(r["slot"]) == slot:
				exposed = bool(r["is_exposed"])
				break
	var carry_h := -1
	if player != null:
		for o in player.towers:
			if bool(o.disabled):
				continue
			if int(o.h) > carry_h:
				carry_h = int(o.h)
	var is_carry := (carry_h >= 0 and int(t.h) >= carry_h)
	t.death_exposed = exposed
	t.death_carry = is_carry
	t.death_valid = true
	# 死亡事件分类（v2 §7.3-5 `carry_exposure_time` 故障护栏的等价读数）
	if is_carry:
		D8["carry_death"] += 1.0
	elif not exposed:
		D8["nonexp_death"] += 1.0
	# 合格死亡事件计数（v3 §6.2 护栏 ③：`n_revive_eligible >= 200`/臂）
	if revive_mode >= 9 and exposed and (not is_carry):
		D8["revive_elig"] += 1.0
	# 重启后又死（v3 §7.3-8：`revive_then_redied`，语义 = 履职证明，不判负）
	if int(t.revived_ever) > 0:
		D8["revive_redied"] += 1.0


## 战斗内复活资格判定 + 成交（共用于 B1/B2/B5 与 B3）。
##   🔴 硬断言：不合格 → `revive_misqualify += 1` 且**跳过重启**（并把本波配额打满，
##      避免同一座塔每子步重复计数把断言数刷爆）。
static func _try_revive(t, player, cfg: Dictionary, geo, dps_box: Array,
		D8: Dictionary, exp: float) -> bool:
	var k_max: int = int(cfg.get("revive_k_per_wave", 1))
	if bool(t.death_valid) and bool(t.death_exposed) and (not bool(t.death_carry)):
		t.hp_max = _MonsterData.tower_hp(int(t.h), exp)
		if _clear_disabled(player, int(t.slot)):
			t.revive_used_w = int(t.revive_used_w) + 1
			t.revived_ever = int(t.revived_ever) + 1
			D8["revive_fired"] += 1.0
			# 🔴 硬断言（v3 §3.3 / §6.2 护栏⑥）：**已落地**的重启必须仍然满足死亡快照资格。
			#    这里是闸门的后置守卫 —— 只要上面的 `if` 被改动/绕过，它就会炸。
			#    🟡 与「闸门**正确拒绝**」是两件事：拒绝数走 `revive_refused`（诊断量，不是断言）。
			if (not bool(t.death_exposed)) or bool(t.death_carry) or (not bool(t.death_valid)):
				D8["revive_misq"] += 1.0
			# 🔴 塔恢复输出 → 全场 DPS 立即重算（与塔死亡时重算同一条纪律）
			dps_box[0] = _DE.dps_only(player, cfg, geo)
			return true
		return false
	# ---- 闸门口**正确拒绝**：不合格（carry 死 或 非暴露位死）→ 不重启 ----
	if not bool(t.death_valid):
		D8["nosnap_death"] += 1.0
	D8["revive_refused"] += 1.0
	# 🔴 打满本波配额 → 同一座塔不会被每子步重复判定（否则拒绝计数会被刷爆）
	t.revive_used_w = k_max
	return false


## B3 · 波首复活（`N → ∞` 极限档）：波首把合格的 Disabled 塔一次性清标记 + 回满。
##   🟢 落在 `dps_only` 重算**之前**调用 → 本波 dps 直接读到已恢复的塔。
##   🟢 落在 `_init_tower_hp` **之前**调用 → 复活的塔当波按 `HP0 × h^0.6` 满血。
static func _wave_start_revive(player, cfg: Dictionary, geo, D8: Dictionary) -> void:
	if player == null:
		return
	var exp: float = float(cfg.get("tower_stack_exp", 0.6))
	var k_max: int = int(cfg.get("revive_k_per_wave", 1))
	var dps_box: Array = [0.0]
	for t in player.towers:
		if not bool(t.disabled):
			continue
		if int(t.revive_used_w) >= k_max:
			continue
		_try_revive(t, player, cfg, geo, dps_box, D8, exp)


## B1/B2/B5 · 战斗内即时复活：Disabled 塔累计 `N` 秒后自动重启，每波每塔最多 `K` 次。
##   🔴 `K` 用尽 → 保持 Disabled 到波末（v3 §2 段③）。
static func _tick_revive(player, cfg: Dictionary, geo, dps_box: Array,
		D8: Dictionary, exp: float) -> void:
	if player == null:
		return
	var n_sec: float = float(cfg.get("revive_n_seconds", 0.5))
	var k_max: int = int(cfg.get("revive_k_per_wave", 1))
	for t in player.towers:
		if not bool(t.disabled):
			continue
		t.revive_t_disabled = float(t.revive_t_disabled) + DT
		if int(t.revive_used_w) >= k_max:
			continue
		if float(t.revive_t_disabled) + 1e-9 < n_sec:
			continue
		_try_revive(t, player, cfg, geo, dps_box, D8, exp)


## 🔒 V-8 逐位对照钩子：把 `player.towers` 的 `disabled` 位压成一个位掩码（塔序 = 列表序）。
##   🔴 纯读取，不写任何状态。仅供 `trace_box` 非空时调用（单测逐位比对实时版）。
static func _disabled_mask(player) -> int:
	if player == null:
		return 0
	var mask := 0
	var i := 0
	for t in player.towers:
		if bool(t.disabled):
			mask |= (1 << i)
		i += 1
	return mask


## 残响场内判定：怪物是否落在**任一 Disabled 塔**的 `R_reverb` 半径内。
##   🟢 零新几何代码：复用 `_monster_pos` + `distance_squared_to`
##      （与 `_nearest_exposed_tower` 同款距离判定，v3 §10-5）。
##
## 🔴🔴🔴 本函数属于**已被砍的残响机制**（不采纳，勿启用）。见文件头与
##   `mvp_config.gd` 的 `reverb_*` 标注 / `docs/phase3/qg-radial/v8b-final-adjudication.md` §2。
##   仅在显式扫参臂打开 `reverb_enabled` 时被调用（`simulate_wave_aggro` ③前进段的
##   `if reverb_on:` 守卫内）；默认回归路径 `reverb_on=false` → 本函数**永不被调用**。
##   保留供复现 / 未来纯体验层重启评估，不得并入任何默认口径。
static func _in_reverb(m: Array, v0_: float, slot_positions: Array, player,
		r2: float) -> bool:
	if player == null:
		return false
	var mpos: Vector2 = _monster_pos(m, v0_)
	for t in player.towers:
		if not bool(t.disabled):
			continue
		var slot: int = int(t.slot)
		if slot < 0 or slot >= slot_positions.size():
			continue
		if mpos.distance_squared_to(slot_positions[slot]) <= r2:
			return true
	return false


# ---------------------------------------------------------------------------
# 仇恨行为（逐行镜像 WaveDirector._apply_aggro）
#   dps_box : 单元素 Array 可变容器 [dps]（塔死亡时重算写回 → 引用捕获，与实时版
#             dps 成员变量重算逐位一致）
# ---------------------------------------------------------------------------
static func _apply_aggro(monsters: Array, v0_: float, slot_positions: Array,
		cfg: Dictionary, player, geo, dps_box: Array, attrition: float = 0.5,
		dis_new_box: Array = [0], protect_core: bool = false,
		sapper: bool = false, v8_box: Array = []) -> void:
	var d8_on: bool = v8_box.size() > 0
	var D8: Dictionary = v8_box[0] if d8_on else {}
	for m in monsters:
		if float(m[0]) <= 0.0:
			continue
		var st: int = int(m[2])
		if st == 0:   # Marching → 找最近未 Disabled 塔
			var mpos: Vector2 = _monster_pos(m, v0_)
			# 🔒 T1 ⑤ Sapper：出生即锁最近塔，无视 AGGRO_R 距离门槛（直奔最近的塔）。
			#   protect_core 仍生效（跳过主力塔）。普通怪走 ≤ AGGRO_R 机会型门槛。
			var slot := -1
			if sapper and bool(m[5]):
				slot = _nearest_tower_any(mpos, player, slot_positions, protect_core)
			else:
				slot = _nearest_exposed_tower(mpos, player, slot_positions, protect_core)
			if slot >= 0:
				m[2] = 1
				m[3] = slot
		else:         # AggroTower → 目标失效则回 Marching，否则打塔
			if not _aggro_target_valid(m, v0_, player, slot_positions):
				m[2] = 0
				m[3] = -1
				# 🔒 V-8 `gap_unlocked_monsters`：肉盾倒下 → 原本被它锁住的怪解锁
				#   → 重新前进 → 这就是空窗期的真实危害（v2 §2.1）。纯计数。
				if d8_on:
					D8["gap_unlocked"] += 1.0
			else:
				_damage_tower(m, player, cfg, geo, dps_box, attrition, dis_new_box, v8_box)


static func _monster_pos(m: Array, v0_: float) -> Vector2:
	# 🔴 按模式分派位置派生（对齐实时版 monster.pos）：
	#   PATH   → 弧长 s = arc_of_t(t_remain)，再二分查折线 sample(s)（逐位等价基准，一行不改）。
	#   RADIAL → 极坐标一步乘加 radial_pos_of_t(t_remain, m_spd, theta)（ρ 由 t_remain 派生）。
	#   🔴 基础怪 m_spd = 1.00（tr = t_reach / 1.0）；theta = m[6]（PATH 恒 0.0 不使用）。
	if not _SpaceModel.is_radial():
		var s := _PathGeometry.arc_of_t(float(m[1]), 1.0, v0_, _PathGeometry.TOTAL_LEN)
		return _PathGeometry.sample(s)
	return _SpaceModel.radial_pos_of_t(float(m[1]), 1.0, float(m[6]))


## 🔒 T1 ⑤ Sapper：找全局最近的**未 Disabled** 塔（**无视 AGGRO_R** 距离门槛）。
##   Sapper「直奔最近的塔」→ 不论远近都锁。protect_core 仍生效（跳过主力塔）。
##   与实时版 WaveDirector._nearest_tower_any 逐位对齐。
static func _nearest_tower_any(mpos: Vector2, player, slot_positions: Array,
		protect_core: bool = false) -> int:
	if player == null:
		return -1
	var core_slot := -1
	var core_h := -1
	if protect_core:
		for t in player.towers:
			if bool(t.disabled):
				continue
			if int(t.h) > core_h:
				core_h = int(t.h)
				core_slot = int(t.slot)
	var best := -1
	var best_d2 := INF
	for t in player.towers:
		if bool(t.disabled):
			continue
		var slot: int = int(t.slot)
		if slot < 0 or slot >= slot_positions.size():
			continue
		if protect_core and slot == core_slot:
			continue
		var spos: Vector2 = slot_positions[slot]
		var d2 := mpos.distance_squared_to(spos)
		if d2 <= best_d2:
			best_d2 = d2
			best = slot
	return best


## 🔒 T1 ⑤ Sapper 出生表（镜像 WaveDirector._spawn_one 的 Sapper 判定）：
##   sapper=false → 全 false（金标本零改动）；sapper=true → 仅 Elite 波
##   （is_elite_wave）沿波次均匀铺开 elite_count 个 Sapper（与 elite_indices 同算法）。
static func _build_sapper_flags(n: int, w: int, sapper: bool) -> Array:
	var out: Array = []
	out.resize(n)
	if not sapper:
		return out
	if not _MonsterData.is_elite_wave(w):
		return out
	var n_e := _MonsterData.elite_count(w, n)
	var eidx: Array = _MonsterData.elite_indices(n, n_e)
	for idx in eidx:
		out[int(idx)] = true
	return out


## 找最近的**未 Disabled** 塔（距离 ≤ AGGRO_R）。返回塔位 slot，无则 -1。
## 🔴 直接读 player.towers（单一数据源）→ 与实时版一致。
## 🔒 T1 V-2 诊断（protect_core）：模拟"玩家保护主力塔"（肉盾吸引/放安全位）——
##   当 true 时**跳过 h 最高的主力塔**（= 金标本 AI 认定的 carry 塔），怪物转而
##   攻击副塔。这干净隔离"主力塔被打停"单一变量：不改 build/DPS，只改仇恨目标。
##   🔴 金标本零改动：默认 false，运行时/扫参不传则行为完全不变。
static func _nearest_exposed_tower(mpos: Vector2, player, slot_positions: Array,
		protect_core: bool = false) -> int:
	if player == null:
		return -1
	# 主力塔 = h 最高的那座（金标本 AI 的 carry 塔；单核流 A 全押这一座）
	var core_slot := -1
	var core_h := -1
	if protect_core:
		for t in player.towers:
			if bool(t.disabled):
				continue
			if int(t.h) > core_h:
				core_h = int(t.h)
				core_slot = int(t.slot)
	var best := -1
	var best_d2 := _MonsterData.AGGRO_R * _MonsterData.AGGRO_R
	for t in player.towers:
		if bool(t.disabled):
			continue
		var slot: int = int(t.slot)
		if slot < 0 or slot >= slot_positions.size():
			continue
		if protect_core and slot == core_slot:
			continue   # 保护主力塔：怪物不选它
		var spos: Vector2 = slot_positions[slot]
		var d2 := mpos.distance_squared_to(spos)
		if d2 <= best_d2:
			best_d2 = d2
			best = slot
	return best


## AggroTower 怪的目标塔是否仍合法（存在 + 未 Disabled + 在迟滞带内）。
static func _aggro_target_valid(m: Array, v0_: float, player, slot_positions: Array) -> bool:
	var slot: int = int(m[3])
	if slot < 0 or player == null:
		return false
	var t = _tower_by_slot(player, slot)
	if t == null or bool(t.disabled):
		return false
	if slot >= slot_positions.size():
		return false
	# 🔒 T1 ⑤ Sapper：锁定后**不因距离退出**（直奔最近的塔，committed 攻击）。
	if bool(m[5]):
		return true
	var mpos: Vector2 = _monster_pos(m, v0_)
	var spos: Vector2 = slot_positions[slot]
	# 🔴 用 AGGRO_EXIT（10.8 = 9.0×1.2）作退出阈值（迟滞带，防边界抖动）
	return mpos.distance_squared_to(spos) <= _MonsterData.AGGRO_EXIT * _MonsterData.AGGRO_EXIT


## AggroTower 怪对目标塔造成伤害；塔归零 → Disabled 中间态 → 重算 dps。
## 🔴 直接改 player.towers 的 hp/disabled（单一数据源）→ dps_only 重算读到新 disabled。
static func _damage_tower(m: Array, player, cfg: Dictionary, geo, dps_box: Array,
		attrition: float, dis_new_box: Array = [0], v8_box: Array = []) -> void:
	var slot: int = int(m[3])
	var t = _tower_by_slot(player, slot)
	if t == null or bool(t.disabled):
		return
	# 对塔 DPS = ATTRITION × HP0 × m_dps(proto)（V-1 复合比口径；attrition 经扫参覆盖解析）
	# 🔒 T1 ⑤ Sapper：对塔伤害 ×3（m[5]=sapper 标志）。
	var mdps: float = float(m[4]) * (float(_MonsterData.SAPPER_DMG_MULT) if bool(m[5]) else 1.0)
	var dmg := attrition * _MonsterData.HP0 * mdps * DT
	t.hp = float(t.hp) - dmg
	if float(t.hp) <= 0.0:
		t.hp = 0.0
		# 🔒 V-8：死亡时刻资格快照（v3 §3.3）→ 必须在 `disabled = true` **之前**取。
		#   🔴 默认 repair_on_disable=0 → 不触发，零开销零扰动。
		var rm: int = int(cfg.get("repair_on_disable", 0))
		if rm >= 9:
			var D8: Dictionary = v8_box[0] if v8_box.size() > 0 else _new_v8_diag()
			_death_snapshot(t, player, geo, D8, rm)
		t.disabled = true          # 进入 Disabled 中间态（断输出不断链）
		# 🔒 T1 V-1：本波毛新增 +1（塔在本子步被打停；每塔每次被打停计一次，
		#    修复后再次被打停会再计 → 毛流量语义，不受跨波修复干扰）。
		dis_new_box[0] = int(dis_new_box[0]) + 1
		# 🔴 塔死亡 → 全场 DPS 立即重算写回 dps_box[0]（引用捕获，与实时版 dps 成员
		#    变量重算逐位一致；🔴 不用闭包标量回写，headless 下不回写外层）。
		dps_box[0] = _DE.dps_only(player, cfg, geo)


## 按塔位取塔（player.towers 里查 slot）。
static func _tower_by_slot(player, slot: int):
	for t in player.towers:
		if int(t.slot) == slot:
			return t
	return null


## 稳定排序（插入排序）：按剩余时间升序 = 距核心最近优先（W-A2）。
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
