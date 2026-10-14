class_name WaveSimProtoAggro
extends RefCounted
##
## 🔒 第五刀 · 三轴合并批处理战斗结算（镜像 `WaveDirector._substep` 全相位）
##
## 🔴 定位（**不动**金标本 `wave_sim.gd` / `wave_sim_proto.gd` / `wave_sim_aggro.gd`）：
##   本文件 = `WaveDirector._substep` 的**三轴合并**（三原型+Elite+仇恨）批处理 static 镜像，
##   供「实机全开口径」（RADIAL + proto + elite + aggro）的 300 局 MC 上线门禁使用。
##   相位编排**逐相位与真身同序**：
##     ① 生成 → ② DPS 分配 → ③ 前进/漏怪/锁定即停 → ④ 仇恨 → ⑤ 复活 tick（默认 no-op）。
##
## 🔴 相位语义**逐字复用**既有镜像与真身（不重写公式、不新增/改任何数值常量）：
##   · ① 生成表 = `wave_sim_proto`（spawn_sequence / hp_mult / spd_mult / elite_conserve / elite_indices）。
##   · ② 集火 = 贪心 + 溢出结转（t_remain 升序稳定排序，复用 `wave_sim_aggro._stable_sort_by_time`）。
##   · ③ 前进 = `wave_sim_aggro`（AggroTower 冻结 t_remain，不前进不漏怪）。
##   · ④ 仇恨 = `wave_sim_aggro`（_nearest_exposed_tower / _nearest_tower_any / _damage_tower 逐字复用；
##      仅「怪物位置派生」按 per-proto m_spd 泛化，见下）。
##   · ⑤ 复活 = `wave_sim_aggro._tick_revive`（默认 `repair_on_disable=0` → no-op）。
##
## 🔴🔴🔴 ② 相位 = **恒大 assign**（忠实真身 `_substep` · 主理人 2026-10-10 裁定）：
##   修复前两镜像在共享相位 ② 上口径不一致（实测可观测，非理论分歧）—— 🔴 **2026-10-12 已统一**：
##     · `wave_sim_proto` : `monsters = _stable_sort_by_time(monsters)`（**赋值** → 真排序 = 真身）
##     · `wave_sim_aggro` : 🔴 **2026-10-12 已修复**（原 `_stable_sort_by_time(monsters)` 丢弃返回值 = no-op）
##       → 现为 `monsters = _stable_sort_by_time(monsters)`（**assign** = 真身语义）。
##       依据/证据：`docs/phase3/aggro-mirror-fidelity-impl.md`（本文件 ② 恒 assign 与之一致）。
##     · 真身 `_substep`   : `_stable_sort_by_remain()`（**原地排序** = assign 语义）
##   🔴 裁定（统一语义优先于凑守护）：本镜像 ② **恒 assign**，与真身 / `wave_sim_proto` 一致。
##     **不**按轴条件归约 —— 那会让 `proto_enabled=false` 配置下**静默复现** aggro 镜像的
##     错误 ② 语义（与真身不符 → 埋"某配置下悄悄算错"的地雷）。
##   → 守护（`tests/test_suite_aggro_golive.gd`）：
##     · ① `aggro=false`             → 与 `run_loop_proto` 逐位一致（② 均为 assign）
##     · ② `proto/elite=false`+aggro → 与**真身**（headless 驱动 WaveDirector）逐位一致
##     · ③ 三轴全 OFF                → 与金标本 `run_loop` 逐位一致（全 OFF 下 m_spd≡1、
##         插入序 ≡ 升序 → assign 为恒等变换，与金标本正序遍历逐位恒等）
##     · ④ 全开（proto+elite+aggro） → 与**真身**逐位一致（上线门禁可信度地基）
##   🔴 该归约**只决定「是否采用既有排序结果」**，不改任何数值 / 不改公式 / 不新增常量。
##
## 🔴 怪物位置派生按 per-proto m_spd 泛化（真身 `monster.pos(v0x)` 用 `m.m_spd`）：
##   `wave_sim_aggro._monster_pos` 为「单一基准怪」硬编码 `m_spd=1.0`；本镜像把 m_spd 存进
##   怪物数组末位（m[7]）并以之派生位置。proto OFF 时 m[7]≡1.0 → 与 `wave_sim_aggro` 逐位一致。
##   🔴 非残响分支：残响（reverb）已被砍（默认恒 false）且非本刀口径 → 本镜像不含残响分支；
##      m[7] 因此改作 m_spd 槽（不与 `wave_sim_aggro` 的 m[7]=reverb 标记冲突）。
##
## 判据来源：`design/gdd/wave-spawner.md` §2.5/§2.6 + `mechanics-tower-life-death.md` §2
## 数据来源：`scripts/data/monster_data.gd`（M_HP/M_SPD/M_DPS/ELITE_*/AGGRO_*/ATTRITION/HP0/SAPPER_*）
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
const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")

const DT := 0.1


# ---------------------------------------------------------------------------
# 三轴合并批处理战斗结算（镜像 WaveDirector._substep 全相位）
#   proto_enabled : 三原型分化（m_hp/m_spd 生效）
#   elite_enabled : Elite 波词缀（每 5 波）+ Sapper 标记（杀伤需 aggro 开）
#   aggro_enabled : Q-T3 机会型仇恨（AGGRO_R=9.0）+ 塔 HP + Disabled 中间态
# 怪物本地结构：[hp, t_remain, state, target_slot, m_dps, sapper, theta, m_spd]
#   state: 0=Marching 1=AggroTower
# ---------------------------------------------------------------------------
static func simulate_wave_proto_aggro(player, w: int, cfg: Dictionary, geo = null,
		proto_enabled: bool = true, elite_enabled: bool = true,
		aggro_enabled: bool = true, exp: float = 0.6, attrition: float = -1.0,
		warmup_waves: int = 0, protect_core: bool = false, bulwark: bool = false) -> Dictionary:
	# ---- 肉盾塔诊断（bulwark）：主力塔重定位到安全位（默认 false → 零扰动）----
	if bulwark and player != null and w > warmup_waves:
		_WaveSimAggro._relocate_carry_to_safe(player, geo)
	# ---- V-8 复活档位（默认 repair_on_disable=0 → 全不触发，逐位不变）----
	var revive_mode: int = int(cfg.get("repair_on_disable", 0))
	var D8: Dictionary = _WaveSimAggro._new_v8_diag()
	if player != null and revive_mode >= 9:
		for t in player.towers:
			t.revive_t_disabled = 0.0
			t.revive_used_w = 0
		if revive_mode == 11 and w > warmup_waves:
			_WaveSimAggro._wave_start_revive(player, cfg, geo, D8)
	var ms := _WaveSim.monster_stats(w, cfg)
	var D := float(ms["D"])
	var n := int(ms["n"])
	var hp_unit := float(ms["hp"])
	var spk := float(ms["scrap_per_kill"])
	var t_reach := float(ms["t_reach"])
	var spawn_span := D * _MvpConfig.spawn_window(w)
	var interval := spawn_span / float(maxi(1, n))
	var v0_ := _MonsterData.v0(_PathGeometry.TOTAL_LEN, t_reach)
	var dps := _DE.dps_only(player, cfg, geo)

	# ---- 塔 HP（波首满血，未 Disabled 的塔）——仅 aggro 开时重置（与真身 start_wave 同门槛）----
	if aggro_enabled and player != null:
		_WaveSimAggro._init_tower_hp(player, exp)
	var slot_positions: Array = _WaveSimAggro._slot_positions(geo)

	# ---- 出生表（逐字复用 wave_sim_proto 的三原型+Elite 口径）----
	var hp_mults: Array = []
	var spd_mults: Array = []
	var proto_seq: Array = []
	if not proto_enabled:
		# 🔴 金标本口径：单一基准怪（m_hp=1.00 / m_spd=1.00 / 宿主=Swarm）
		for i in range(n):
			hp_mults.append(1.0)
			spd_mults.append(1.0)
			proto_seq.append("Swarm")
	else:
		proto_seq = _MonsterData.spawn_sequence(n)
		var n_e := _MonsterData.elite_count(w, n) if elite_enabled else 0
		var c := _MonsterData.elite_conserve(n, n_e)
		var eidx: Array = _MonsterData.elite_indices(n, n_e)
		for i in range(n):
			var p := String(proto_seq[i])
			var e := eidx.has(i)
			hp_mults.append(_MonsterData.hp_mult(p, e, c))
			spd_mults.append(_MonsterData.spd_mult(p))
	# ---- 本波总 HP（用于 threshold / 汇报口径。🔴 不进战斗结算，零玩法影响）----
	#   🔴 **汇报口径**按轴归约（🔴 与 ② 无关 —— ② 已恒大 assign）：proto ON → Σ hp_unit·m_hp
	#      （= wave_sim_proto / 上线口径）；proto OFF → n·hp_unit（= 金标本 simulate_wave 口径）。
	#      二者在 proto OFF 下**语义相同但浮点不同**（n·hp vs Σhp·1.0 的累加误差）→
	#      按轴取才能让守护③（vs 金标本，比 total_hp_raw）逐位一致。🔴 纯汇报字段，零玩法影响。
	var total_hp := 0.0
	if proto_enabled:
		for i in range(n):
			total_hp += hp_unit * float(hp_mults[i])
	else:
		total_hp = hp_unit * float(n)

	# ---- Sapper 出生表（镜像真身 _spawn_one：由 elite_waves_enabled 独立驱动）----
	#   🔴 与真身同口径：sapper 标记由 elite 驱动、与 proto 无关；行为（锁塔×3）需 aggro 开才生效。
	var sapper_flags: Array = _WaveSimAggro._build_sapper_flags(n, w, elite_enabled)

	var time := 0.0
	var spawned := 0
	var monsters: Array = []
	var kills := 0
	var leaked := 0
	var scrap := 0.0
	var limit := D + t_reach + 1e-9
	var dps_box: Array = [dps]
	var dis_new_box: Array = [0]

	while time <= limit:
		# ---- ① 刷新 ----
		while spawned < n and time >= float(spawned) * interval - 1e-9:
			var mspd := float(spd_mults[spawned])
			var tr := t_reach / mspd
			var mdps := float(_MonsterData.M_DPS.get(String(proto_seq[spawned]), 1.0))
			var th := 0.0
			if _SpaceModel.is_radial():
				th = _SpaceModel.spawn_theta(spawned, w)
			monsters.append([hp_unit * float(hp_mults[spawned]), tr, 0, -1, mdps,
				sapper_flags[spawned] == true, th, mspd])
			spawned += 1

		# ---- ② 集火（🔴 恒大 assign = 真身 `_stable_sort_by_remain` 原地排序语义，见文件头）----
		monsters = _WaveSimAggro._stable_sort_by_time(monsters)
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

		# ---- ③ 前进：判死 / 漏怪（AggroTower 冻结 t_remain，不前进不漏怪）----
		var alive: Array = []
		for m in monsters:
			if float(m[0]) <= 0.0:
				continue
			if aggro_enabled and int(m[2]) == 1:
				alive.append(m)
				continue
			m[1] = float(m[1]) - DT
			if float(m[1]) <= 0.0:
				leaked += 1
			else:
				alive.append(m)
		monsters = alive

		# ---- ④ 仇恨行为（Q-T3 机会型仇恨 · 仅 aggro 开且过起手保护时生效）----
		if aggro_enabled and w > warmup_waves:
			_apply_aggro(monsters, v0_, slot_positions, cfg, player, geo, dps_box,
				_MonsterData.sapper_dmg_mult(w), _MonsterData.resolve_attrition(attrition),
				dis_new_box, protect_core, elite_enabled, [])
		# ---- ⑤ 战斗中复活（V-8 · 默认 repair_on_disable=0 → no-op）----
		if revive_mode >= 9 and revive_mode != 11 and w > warmup_waves:
			_WaveSimAggro._tick_revive(player, cfg, geo, dps_box, D8, exp)

		time += DT

	var core_dmg := float(leaked) * float(cfg.get("leak_damage", 50.0))
	return {
		"w": w, "kills": kills, "leaked": leaked, "scrap_earned": scrap,
		"core_damage": core_dmg, "dps": float(dps_box[0]),
		"threshold": total_hp / (D + t_reach),
		"total_hp": total_hp,
		"n": n, "hp_each": hp_unit,
		"towers_disabled": _WaveSimAggro._count_disabled(player),
		"dis_new": int(dis_new_box[0]),
		"v8_diag": D8,
	}


# ---------------------------------------------------------------------------
# 仇恨行为（逐字镜像 `wave_sim_aggro._apply_aggro` + 真身 `WaveDirector._apply_aggro`）
#   🔴 唯一差异：怪物位置派生按 per-proto m_spd（`_monster_pos` 读 m[7]），与真身 `m.pos()` 同口径。
#   其余（最近塔选择 / 迟滞带 / 塔伤害 / sapper×3）一律复用 `wave_sim_aggro` 的 static helper。
# ---------------------------------------------------------------------------
static func _apply_aggro(monsters: Array, v0_: float, slot_positions: Array,
		cfg: Dictionary, player, geo, dps_box: Array, sapper_mult: float,
		attrition: float = 0.5, dis_new_box: Array = [0], protect_core: bool = false,
		sapper: bool = false, v8_box: Array = []) -> void:
	var d8_on: bool = v8_box.size() > 0
	var D8: Dictionary = v8_box[0] if d8_on else {}
	for m in monsters:
		if float(m[0]) <= 0.0:
			continue
		var st: int = int(m[2])
		if st == 0:   # Marching → 找最近未 Disabled 塔
			var mpos: Vector2 = _monster_pos(m, v0_)
			var slot := -1
			if sapper and bool(m[5]):
				slot = _WaveSimAggro._nearest_tower_any(mpos, player, slot_positions, protect_core)
			else:
				slot = _WaveSimAggro._nearest_exposed_tower(mpos, player, slot_positions, protect_core)
			if slot >= 0:
				m[2] = 1
				m[3] = slot
		else:         # AggroTower → 目标失效则回 Marching，否则打塔
			if not _aggro_target_valid(m, v0_, player, slot_positions):
				m[2] = 0
				m[3] = -1
				if d8_on:
					D8["gap_unlocked"] += 1.0
			else:
				_WaveSimAggro._damage_tower(m, player, cfg, geo, dps_box, sapper_mult, attrition, dis_new_box, v8_box)


## 怪物世界坐标（按模式分派位置派生；🔴 m_spd 取怪物自身 m[7]，对齐真身 `monster.pos`）。
##   PATH   → 弧长 s = arc_of_t(t_remain, m_spd)，再二分查折线 sample(s)。
##   RADIAL → 极坐标 radial_pos_of_t(t_remain, m_spd, theta)。
##   🔴 proto OFF 时 m[7]≡1.0 → 与 `wave_sim_aggro._monster_pos`（硬编码 1.0）逐位一致。
static func _monster_pos(m: Array, v0_: float) -> Vector2:
	if not _SpaceModel.is_radial():
		var s := _PathGeometry.arc_of_t(float(m[1]), float(m[7]), v0_, _PathGeometry.TOTAL_LEN)
		return _PathGeometry.sample(s)
	return _SpaceModel.radial_pos_of_t(float(m[1]), float(m[7]), float(m[6]))


## AggroTower 怪的目标塔是否仍合法（存在 + 未 Disabled + 在迟滞带内）。
##   🔴 逐字镜像 `wave_sim_aggro._aggro_target_valid`，仅位置派生换为 `_monster_pos`（per-m_spd）。
static func _aggro_target_valid(m: Array, v0_: float, player, slot_positions: Array) -> bool:
	var slot: int = int(m[3])
	if slot < 0 or player == null:
		return false
	var t = _WaveSimAggro._tower_by_slot(player, slot)
	if t == null or bool(t.disabled):
		return false
	if slot >= slot_positions.size():
		return false
	if bool(m[5]):
		return true
	var mpos: Vector2 = _monster_pos(m, v0_)
	var spos: Vector2 = slot_positions[slot]
	return mpos.distance_squared_to(spos) <= _MonsterData.AGGRO_EXIT * _MonsterData.AGGRO_EXIT
