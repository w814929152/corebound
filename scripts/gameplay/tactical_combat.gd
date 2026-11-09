extends RefCounted
## 玩家关卡的逐塔射程结算。复用伤害引擎的构筑乘区；不修改基准模拟器。
const DE := preload("res://scripts/engine/damage_engine.gd")
const TD := preload("res://scripts/data/tower_data.gd")
const CT := preload("res://scripts/data/combat_types.gd")
const Effects := preload("res://scripts/engine/tower_effects.gd")
const Space := preload("res://scripts/geo/space_model.gd")

## 每个入口分到相同的来敌配额，窄口才会形成密集来敌；不消耗商店 RNG。
## 0-1 保持基准出生布局，其余关卡仅在玩家战术模式调用。
static func spawn_theta(index: int, wave: int, stage_id: String) -> float:
	var arcs: Array = Space.active_spawn_arcs()
	if stage_id == "0-1" or stage_id == "" or not Space.layout_enabled or arcs.is_empty():
		return Space.spawn_theta(index, wave)
	var turn := fposmod(float(wave) * Space.PHASE_STEP_DEG + float(index) * Space.GOLDEN_ANGLE_DEG, 360.0) / 360.0
	var entry := turn * float(arcs.size())
	var arc: Dictionary = arcs[mini(int(entry), arcs.size() - 1)]
	return deg_to_rad(lerpf(float(arc["a0"]), float(arc["a1"]), entry - floor(entry)))

static func apply(wd, dt: float) -> void:
	if wd.player == null or wd.geo == null:
		return
	var result: Dictionary = DE.compute_dps(wd.player, wd.cfg, wd.geo)
	var info: Dictionary = result.get("info", {})
	var rows: Array = info.get("per_tower", [])
	var global_mult := float(info.get("aoe", 1.0)) * float(info.get("crossfire", 1.0)) \
		* float(info.get("aux", 1.0)) * float(info.get("empower", 1.0)) * float(info.get("debuff_mult", 1.0))
	wd.dps = float(result.get("total", 0.0))
	for i in range(mini(rows.size(), wd.player.towers.size())):
		var tower = wd.player.towers[i]
		var slot := int(tower.slot)
		if bool(tower.disabled) or slot < 0 or slot >= wd.geo.slots.size():
			continue
		var name := String(tower.ctype)
		var center: Vector2 = wd.geo.slots[slot]
		var radius := TD.tower_rng(name)
		var row: Dictionary = rows[i]
		# Coverage 原来是平均在射程内的时间比例。真实判距后移除该折扣，避免重复扣覆盖。
		var cov := float(row.get("cov", 0.0))
		var budget := float(row.get("dps", 0.0)) / cov * global_mult * dt if cov > 0.0 else 0.0
		var kind := String(row.get("dmg_type", CT.PHYSICAL))
		var reduction: float = float(wd._phys_reduct) if kind == CT.PHYSICAL else float(wd._magic_reduct)
		apply_in_range(wd, center, radius, budget, kind, float(reduction))
		var dot := TD.tower_dot(name) * Effects.debuff_damage_mult(wd.player) * dt
		if dot > 0.0:
			apply_in_range(wd, center, radius, dot, CT.TRUE, 0.0)


## 怪物已按距核心的剩余时间稳定排序；伤害仅在本塔射程内结转，未使用伤害不储存。
static func apply_in_range(wd, center: Vector2, radius: float, budget: float,
		kind: String, reduction: float) -> void:
	for m in wd.monsters:
		if budget <= 0.0:
			break
		if float(m.hp) <= 0.0 or center.distance_squared_to(m.pos(wd.v0_)) > radius * radius:
			continue
		var factor := 1.0
		if wd.combat_types_enabled:
			factor -= clampf(CT.effective_resist(String(m.proto), kind, reduction), 0.0, 1.0)
		if factor <= 0.0:
			continue
		var hit := minf(float(m.hp), budget * factor)
		m.hp = maxf(0.0, float(m.hp) - hit)
		budget -= hit / factor
		if float(m.hp) <= 0.0:
			wd._record_monster_kill(m)
