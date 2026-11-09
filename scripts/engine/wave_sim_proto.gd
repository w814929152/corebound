class_name WaveSimProto
extends RefCounted
##
## 🔒 切片7 · S5-D1 校准闸门：三原型+Elite 批处理版战斗结算
##
## 🔴 定位（**不动金标本** `wave_sim.gd`）：
##   本文件是 `WaveDirector._substep` 的**批处理 static 镜像**，供 MC 300 局重扫用
##   （让 `shop_ai` 金标本不变 → build 一致，只换战斗结算口径）。
##   与金标本 `WaveSim.simulate_wave` 的唯一差异：
##     · 每只怪 hp = hp_unit × hp_mult(proto,elite,c)、t_remain = t_reach / m_spd(proto)
##       （金标本是全体 hp_each / t_reach，即 m_hp=1.00 / m_spd=1.00 的单一基准怪）
##     · 集火**必须真排序**（按 t_remain 升序 = 距核心最近优先）—— 因多原型 t_remain 不再全相等
##   🔴 proto_enabled=false → 完全退化为金标本口径（m_hp=1.00/m_spd=1.00 + 免排序），
##      与 `simulate_wave` 逐位等价（由单测守护）。
##
## 判据来源：`design/gdd/wave-spawner.md` v0.3 §2.5（W-C1 三守恒 / 三原型 / Elite）
## 数据来源：`scripts/data/monster_data.gd`（composition / spawn_sequence / elite_* / hp_mult）
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → interval 显式 float。
##   G6 headless `--script` 无 global_script_class_cache → 本文件写 class_name 但
##      调用方一律 preload（与 wave_sim.gd 同纪律）。
##

const _DE := preload("res://scripts/engine/damage_engine.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
## 🆕 关卡波表（v2 世界主线）。🔴 只在这里被**读**，不进任何常量。
const _StageWaves := preload("res://scripts/data/stage_waves.gd")

const DT := 0.1


# ---------------------------------------------------------------------------
# 三原型+Elite 批处理版战斗结算（镜像 WaveDirector._substep）
#   proto_enabled : 三原型分化（m_hp/m_spd 生效）
#   elite_enabled : Elite 波词缀（每 5 波，n_e=max(2,round(0.10N))，m_hp=2.5）
#   stage_id      : 🆕 关卡 id（"" = 无波表 → 金标本口径，逐位不变）
#   escalation    : 🆕 已守地区数 `S`（只影响波表，不影响任何常量）
# ---------------------------------------------------------------------------
static func simulate_wave_proto(player, w: int, cfg: Dictionary, geo = null,
		proto_enabled: bool = false, elite_enabled: bool = false,
		stage_id: String = "", escalation: int = 0) -> Dictionary:
	var ms := _WaveSim.monster_stats(w, cfg)
	var D := float(ms["D"])
	var n := int(ms["n"])
	var hp_unit := float(ms["hp"])
	var spk := float(ms["scrap_per_kill"])
	var t_reach := float(ms["t_reach"])
	# 🆕 关卡波表：只重排「这一波长什么样」，**不改任何常量**（hp_growth / num_growth /
	#   wave_dur / spawn_window / t_reach / leak_damage 一个都不碰）。
	#   🔴 `stage_id == ""` → spec 恒 {} → 下面恒不执行 → 旧读数逐位不变。
	#   🔴 `neutral` 波（0-1）必须跳过：它是「实时 == 批处理」的回归锚点（V-5）。
	var spec: Dictionary = {}
	if stage_id != "":
		spec = _StageWaves.wave_spec(stage_id, w, cfg, escalation)
	var has_spec := not spec.is_empty() and not bool(spec.get("neutral", false))
	var comp: Dictionary = {}
	if has_spec:
		n = int(spec["n"])
		hp_unit = float(spec["hp"])
		comp = spec.get("comp", {})
	var dps := _DE.dps_only(player, cfg, geo)
	var spawn_span := D * _MvpConfig.spawn_window(w)
	var interval := spawn_span / float(maxi(1, n))

	# ---- 出生表（镜像 WaveDirector._build_spawn_table）----
	var hp_mults: Array = []
	var spd_mults: Array = []
	if not proto_enabled:
		for i in range(n):
			hp_mults.append(1.0)
			spd_mults.append(1.0)
	else:
		var seq: Array = _MonsterData.spawn_sequence(n) if comp.is_empty() else _StageWaves.spawn_sequence(n, comp)
		# 🔴 分层纪律（与 `WaveDirector._elite_count_wave` 同）：有波表 → 波表说了算
		#   （含 `S` 加压的 +k）；无波表 → 金标本 `w % 5` 周期。
		var n_e: int = 0
		if elite_enabled:
			n_e = int(spec.get("elite", 0)) if has_spec else _MonsterData.elite_count(w, n)
		var c := _MonsterData.elite_conserve(n, n_e)
		var eidx: Array = _MonsterData.elite_indices(n, n_e)
		# 单只乘数：基准构成时 `proto_mult` 短路返回 `MonsterData` 原值 → 与改前逐位一致。
		var pm: Dictionary = {"hp": _MonsterData.M_HP, "spd": _MonsterData.M_SPD} if comp.is_empty() else _StageWaves.proto_mult(comp)
		for i in range(n):
			var p := String(seq[i])
			var e := eidx.has(i)
			hp_mults.append(_MonsterData.ELITE_HP_MULT if e else float(pm["hp"][p]) * c)
			spd_mults.append(float(pm["spd"][p]))

	# ---- 守恒口径的总 HP（多原型 Σhp 与金标本 N×hp_each 不同）----
	var total_hp := 0.0
	for i in range(n):
		total_hp += hp_unit * float(hp_mults[i])

	var time := 0.0
	var spawned := 0
	var monsters: Array = []      # 每项 = [hp_remaining, t_remain]
	var kills := 0
	var leaked := 0
	var scrap := 0.0
	var limit := D + t_reach + 1e-9

	while time <= limit:
		# ---- 刷新 ----
		while spawned < n and time >= float(spawned) * interval - 1e-9:
			var tr := t_reach / float(spd_mults[spawned])
			monsters.append([hp_unit * float(hp_mults[spawned]), tr])
			spawned += 1

		# ---- 集火（按 t_remain 升序 = 距核心最近优先；多原型必须真排序）----
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

		# ---- 前进：判死 / 漏怪 ----
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
		"threshold": total_hp / (D + t_reach), "total_hp": total_hp,
		"n": n, "hp_each": hp_unit,
	}


## 稳定排序（插入排序）：按剩余时间升序 = 距核心最近优先（W-A2）。
## 🔴 必须稳定：同 tick 出生的并列怪保持插入序（与金标本 list.sort 稳定同口径）。
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
