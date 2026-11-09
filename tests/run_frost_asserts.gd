extends SceneTree
const FireTests = preload("res://tests/run_fire_charge_asserts.gd")
const TD = preload("res://scripts/data/tower_data.gd")
const DE = preload("res://scripts/engine/damage_engine.gd")
const CT = preload("res://scripts/data/combat_types.gd")
const RT = preload("res://scripts/gameplay/shop_runtime.gd")
const TEXT = preload("res://scripts/data/card_text.gd")
var passed := 0
var failed := 0
var helper
func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("[PASS] ", label)
	else:
		failed += 1
		print("[FAIL] ", label)
func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001
func battle(types: Array = ["Pyroclasm"]):
	var d = helper.make_battle(types)
	d.cfg["stacking_frost_enabled"] = true
	d.dps = 0.0
	return d
func _initialize() -> void:
	quit(0 if run_all() else 1)
func run_all() -> bool:
	helper = FireTests.new()
	var d = battle()
	var m = d.monsters[0]
	for layer in range(1, 10):
		d.apply_frost_effect(m)
		check("第 %d 层统一减速 %d%%" % [layer, layer * 10], m.frost_stacks == layer and near(d._frost_move_dt(m, 1.0), 1.0 - float(layer) * 0.1))
	d._tick_frost_effects(20.0)
	check("十层前的冰冻层数不会随时间自行消失", m.frost_stacks == 9)
	d.apply_frost_effect(m)
	check("第十层进入完全冻结两秒", m.frost_stacks == 10 and near(m.frozen_remaining, 2.0) and near(d._frost_move_dt(m, 1.0), 0.0))
	d._advance_frozen_timers(0.5, [m])
	d.apply_frost_effect(m, 2)
	check("冻结中再次命中不会刷新或延长冻结", m.frost_stacks == 10 and near(m.frozen_remaining, 1.5))
	d._advance_frozen_timers(1.5, [m])
	check("两秒后存活则清空所有冰冻状态", m.frost_stacks == 0 and near(m.frozen_remaining, 0.0) and d._ice_storms.is_empty())
	d.apply_frost_effect(m, 2)
	check("解冻后可重新附加两层并减速百分之二十", m.frost_stacks == 2 and near(d._frost_move_dt(m, 1.0), 0.8))
	check("战斗快照导出层数、冻结与实际减速", d.snapshot()["monsters"][0]["frost_stacks"] == 2 and near(d.snapshot()["monsters"][0]["slow_ratio"], 0.2) and not d.snapshot()["monsters"][0]["frozen"])
	d.free()

	d = battle()
	m = d.monsters[0]
	d.apply_frost_effect(m)
	var before := float(m.t_remain)
	d._substep()
	check("减速真实作用于移动而非仅增加伤害", near(before - float(m.t_remain), 0.09))
	d.apply_frost_effect(m, 9)
	before = float(m.t_remain)
	for i in 19:
		d._substep()
	check("冻结一秒九后仍不移动且未提前解冻", near(m.t_remain, before) and near(m.frozen_remaining, 0.1))
	d._substep()
	check("完整两秒内始终停止移动，第二十步末清空", near(m.t_remain, before) and m.frost_stacks == 0 and near(m.frozen_remaining, 0.0))
	d._substep()
	check("第二十一子步恢复正常移动速度", near(before - float(m.t_remain), 0.1))
	d.player.towers[0].hp = 1000.0
	m.target_slot = 0
	d.apply_frost_effect(m, 10)
	d._damage_tower(m, 1.0)
	check("完全冻结时无法攻击塔", near(d.player.towers[0].hp, 1000.0))
	d.free()

	for name in ["Frost", "Icicle", "Glacier", "Hail", "Permafrost", "Whiteout", "Tesla", "Wildfire"]:
		d = battle([name])
		d._tick_frost_effects(1.0 / TD.tower_attack_speed(name))
		check("%s 命中统一仅叠一层百分之十" % name, d.monsters[0].frost_stacks == 1 and near(d._frost_move_dt(d.monsters[0], 1.0), 0.9))
		d.free()
	d = battle(["Icicle", "Glacier"])
	d._tick_frost_effects(1.0)
	check("多个来源共享目标冰冻层数", d.monsters[0].frost_stacks == 2)
	d.player.towers[0].disabled = true
	d.player.towers[1].disabled = true
	d._tick_frost_effects(1.0)
	check("停机来源不附加冰冻", d.monsters[0].frost_stacks == 2)
	d.free()
	d = battle(["Glacier"])
	d.geo.slots[0] = Vector2(1000.0, 1000.0)
	d._tick_frost_effects(1.0)
	check("射程外不会叠冰冻", d.monsters[0].frost_stacks == 0)
	d.free()

	d = battle()
	helper.set_positions(d, [Vector2.ZERO, Vector2(6, 0), Vector2(6.01, 0)])
	m = d.monsters[0]
	m.hp = 1.0
	d.apply_frost_effect(m, 10)
	d._apply_pool_live(1.0, CT.TRUE)
	check("冻结死亡时以死亡位置释放一次冰暴", d.kills == 1 and d._ice_storms.size() == 1 and d._ice_storms[0]["pos"] == Vector2.ZERO)
	check("冰暴边界敌人受到四十伤害并附两层", near(d.monsters[1].hp, 960.0) and d.monsters[1].frost_stacks == 2)
	check("冰暴范围外不受伤也不附冰冻", near(d.monsters[2].hp, 1000.0) and d.monsters[2].frost_stacks == 0)
	check("冰暴不附加火焰也不为焚星塔充能", d._fire_charge.is_empty() and d.monsters[1].burn_stacks == 0)
	d._record_monster_kill(m)
	check("同一死亡不会重复奖励或重复冰暴", d.kills == 1 and near(d.scrap_earned, d.spk) and d._ice_storms.size() == 1)
	d._tick_frost_effects(0.7)
	check("冰暴演出结束不清除附加的两层", d._ice_storms.is_empty() and d.monsters[1].frost_stacks == 2)
	d.free()

	d = battle()
	m = d.monsters[0]
	m.hp = 1.0
	d.apply_frost_effect(m, 10)
	d._advance_frozen_timers(2.0, [m])
	d._apply_pool_live(1.0, CT.TRUE)
	check("解冻后再死亡不产生冰暴", d.kills == 1 and d._ice_storms.is_empty())
	d.free()

	d = battle()
	helper.set_positions(d, [Vector2.ZERO, Vector2(5, 0), Vector2(10, 0)])
	d.monsters[0].hp = 1.0
	d.monsters[1].hp = 40.0
	d.apply_frost_effect(d.monsters[0], 10)
	d.apply_frost_effect(d.monsters[1], 8)
	d._apply_pool_live(1.0, CT.TRUE)
	check("冰暴使八层邻居满层并致死时继续连锁", d.kills == 2 and d._ice_storms.size() == 2)
	check("第二次冰暴伤及首爆范围外敌人并附两层", near(d.monsters[2].hp, 960.0) and d.monsters[2].frost_stacks == 2)
	check("连锁击杀逐个正确记账且队列清空", near(d.scrap_earned, d.spk * 2.0) and d._ice_storm_queue.is_empty() and not d._resolving_ice_storms)
	d.free()

	d = battle()
	d.combat_types_enabled = true
	d.monsters[0].hp = 1.0
	d.monsters[1].proto = "Rush"
	d.apply_frost_effect(d.monsters[0], 10)
	d._apply_pool_live(1.0, CT.TRUE)
	check("冰暴魔法伤害受魔抗影响但两层照常附加", near(d.monsters[1].hp, 968.0) and d.monsters[1].frost_stacks == 2)
	d.free()

	d = battle()
	m = d.monsters[0]
	m.burn_stacks = 4
	m.burn_remaining = 2.0
	d.apply_frost_effect(m, 10)
	d._advance_frozen_timers(2.0, [m])
	check("解冻只清除冰冻，不清除火焰效果", m.burn_stacks == 4 and near(m.burn_remaining, 2.0))
	m.setup(0, "Swarm", false, 1000.0, 1.0, 10.0)
	check("怪物初始化清空冰冻及死亡结算标记", m.frost_stacks == 0 and near(m.frozen_remaining, 0.0) and not m.death_recorded)
	d.free()

	d = battle(["Glacier"])
	var current := DE.compute_dps(d.player, d.cfg)
	var old: Dictionary = d.cfg.duplicate(true)
	old["stacking_frost_enabled"] = false
	var legacy := DE.compute_dps(d.player, old)
	check("新冰冻模式禁用旧减速转增伤机制", near(current["info"]["aux"], 1.0) and float(legacy["info"]["aux"]) > 1.0)
	d.free()
	var rt = RT.new()
	rt.setup("B", 1234)
	check("实际玩家路线默认开启叠层冰冻", bool(rt.cfg.get("stacking_frost_enabled", false)))
	rt = null
	check("冰系卡面明确每层百分之十及十层冻结两秒", TEXT.describe("Frost").contains("10%") and TEXT.describe("Frost").contains("2 秒") and not TEXT.describe("Frost").contains("30%"))
	test_death_paths_and_limits()
	helper.free()
	print("Frost: %d PASS, %d FAIL" % [passed, failed])
	return failed == 0

func test_death_paths_and_limits() -> void:
	var d = battle()
	var m = d.monsters[0]
	m.hp = 1.0
	d.apply_frost_effect(m, 10)
	d.dps = 10.0
	d._substep()
	check("普通聚合伤害击杀冻结敌人也会触发冰暴", d.kills == 1 and d._ice_storms.size() == 1)
	d.free()

	d = battle()
	m = d.monsters[0]
	m.hp = 1.0
	d.apply_frost_effect(m, 10)
	d._apply_fire_area_damage(Vector2.ZERO, 1.0, 2.0, "ignition")
	check("火焰引爆击杀冻结敌人会触发冰暴", d.kills == 1 and d._ice_storms.size() == 1 and d.monsters[1].frost_stacks == 2)
	d.free()

	d = battle()
	helper.set_positions(d, [Vector2.ZERO, Vector2(5, 0), Vector2(50, 0)])
	d.monsters[0].hp = 1.0
	d.apply_frost_effect(d.monsters[0], 10)
	d.apply_frost_effect(d.monsters[1], 8)
	d.minions = [{"pos": Vector2.ZERO, "ttl": 10.0, "dps": 20.0, "speed": 1.0}]
	d._substep()
	check("召唤物击杀冻结单位同样触发冰暴", d.kills == 1 and d._ice_storms.size() == 1)
	check("子步末尾冰暴新冻结的敌人保留完整两秒", d.monsters[1].frost_stacks == 10 and near(d.monsters[1].frozen_remaining, 2.0))
	d.free()

	d = battle()
	m = d.monsters[0]
	d.apply_frost_effect(m, 9)
	d.apply_frost_effect(m, 2)
	check("九层加两层封顶十层，不溢出到下一轮", m.frost_stacks == 10 and near(m.frozen_remaining, 2.0))
	var other = preload("res://scripts/gameplay/monster.gd").new()
	other.setup(99, "Swarm", false, 1000.0, 1.0, 10.0)
	d.apply_frost_effect(other, 2)
	d.apply_frost_effect(null, 2)
	check("无效或不在战场的目标不被附加冰冻", other.frost_stacks == 0)
	d.monsters[1].state = d.MState.LEAKED
	d.apply_frost_effect(d.monsters[1], 2)
	check("已经漏出的敌人不能被冰冻", d.monsters[1].frost_stacks == 0)
	d.monsters[2].hp = 0.0
	d.apply_frost_effect(d.monsters[2], 2)
	check("已死亡敌人不能被冰冻", d.monsters[2].frost_stacks == 0)
	var frozen_time := float(m.frozen_remaining)
	d.advance(0.0)
	check("零时间推进不会消耗冻结时间", near(m.frozen_remaining, frozen_time))
	d.free()

	d = battle()
	var points: Array = []
	for i in 200:
		points.append(Vector2(float(i) * 5.0, 0.0))
	helper.set_positions(d, points, 40.0)
	for target in d.monsters:
		d.apply_frost_effect(target, 8)
	d.apply_frost_effect(d.monsters[0], 2)
	d._apply_pool_live(40.0, CT.TRUE)
	check("两百个敌人的冰暴链使用队列安全完成", d.kills == 200 and d._ice_storms.size() == 200 and d._ice_storm_queue.is_empty())
	check("大规模连锁没有重复奖励", near(d.scrap_earned, d.spk * 200.0))
	d.free()
