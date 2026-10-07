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
		warmup_waves: int = 0, protect_core: bool = false, bulwark: bool = false) -> Dictionary:
	# 🔒 T1 肉盾塔诊断（bulwark）：模拟"玩家把主力塔放安全位"（理想肉盾策略）。
	#   必须在塔 HP 初始化 / 战斗结算**之前**重定位 → dps_only 重算读到新 slot 的 E。
	if bulwark and player != null and w > warmup_waves:
		_relocate_carry_to_safe(player, geo)
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

	# ---- 出生表（单一基准怪 = 金标本口径；仇恨版不含三原型分化）----
	var time := 0.0
	var spawned := 0
	var monsters: Array = []      # 每项 = [hp, t_remain, state, target_slot, m_dps]
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
			# [hp, t_remain, state(Marching=0), target_slot(-1), m_dps(Swarm=0.60)]
			monsters.append([hp_unit, tr, 0, -1, float(_MonsterData.M_DPS["Swarm"])])
			spawned += 1

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
			m[1] = float(m[1]) - DT
			if float(m[1]) <= 0.0:
				leaked += 1
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
				_MonsterData.resolve_attrition(attrition), dis_new_box, protect_core)

		time += DT

	var core_dmg := float(leaked) * float(cfg.get("leak_damage", 50.0))
	return {
		"w": w, "kills": kills, "leaked": leaked, "scrap_earned": scrap,
		"core_damage": core_dmg, "dps": float(dps_box[0]),
		"threshold": hp_unit * float(n) / (D + t_reach),
		"n": n, "hp_each": hp_unit,
		"towers_disabled": _count_disabled(player),
		"dis_new": int(dis_new_box[0]),
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
	# 安全位 = d_path > AGGRO_R（S4/S5）；暴露位 = ≤ AGGRO_R
	var rows: Array = _PathGeometry.slot_exposure(slots, _MonsterData.AGGRO_R)
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
# 仇恨行为（逐行镜像 WaveDirector._apply_aggro）
#   dps_box : 单元素 Array 可变容器 [dps]（塔死亡时重算写回 → 引用捕获，与实时版
#             dps 成员变量重算逐位一致）
# ---------------------------------------------------------------------------
static func _apply_aggro(monsters: Array, v0_: float, slot_positions: Array,
		cfg: Dictionary, player, geo, dps_box: Array, attrition: float = 0.5,
		dis_new_box: Array = [0], protect_core: bool = false) -> void:
	for m in monsters:
		if float(m[0]) <= 0.0:
			continue
		var st: int = int(m[2])
		if st == 0:   # Marching → 找最近未 Disabled 塔（≤ AGGRO_R）
			var mpos: Vector2 = _monster_pos(m, v0_)
			var slot := _nearest_exposed_tower(mpos, player, slot_positions, protect_core)
			if slot >= 0:
				m[2] = 1
				m[3] = slot
		else:         # AggroTower → 目标失效则回 Marching，否则打塔
			if not _aggro_target_valid(m, v0_, player, slot_positions):
				m[2] = 0
				m[3] = -1
			else:
				_damage_tower(m, player, cfg, geo, dps_box, attrition, dis_new_box)


static func _monster_pos(m: Array, v0_: float) -> Vector2:
	var s := _PathGeometry.arc_of_t(float(m[1]), 1.0, v0_, _PathGeometry.TOTAL_LEN)
	return _PathGeometry.sample(s)


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
	var mpos: Vector2 = _monster_pos(m, v0_)
	var spos: Vector2 = slot_positions[slot]
	# 🔴 用 AGGRO_EXIT（10.8 = 9.0×1.2）作退出阈值（迟滞带，防边界抖动）
	return mpos.distance_squared_to(spos) <= _MonsterData.AGGRO_EXIT * _MonsterData.AGGRO_EXIT


## AggroTower 怪对目标塔造成伤害；塔归零 → Disabled 中间态 → 重算 dps。
## 🔴 直接改 player.towers 的 hp/disabled（单一数据源）→ dps_only 重算读到新 disabled。
static func _damage_tower(m: Array, player, cfg: Dictionary, geo, dps_box: Array,
		attrition: float, dis_new_box: Array = [0]) -> void:
	var slot: int = int(m[3])
	var t = _tower_by_slot(player, slot)
	if t == null or bool(t.disabled):
		return
	# 对塔 DPS = ATTRITION × HP0 × m_dps(proto)（V-1 复合比口径；attrition 经扫参覆盖解析）
	var dmg := attrition * _MonsterData.HP0 * float(m[4]) * DT
	t.hp = float(t.hp) - dmg
	if float(t.hp) <= 0.0:
		t.hp = 0.0
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
