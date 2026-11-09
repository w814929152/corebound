extends SceneTree
## 焚星塔：事件计数、自动附加、独立充能、范围/抗性、击杀结算及跨波重置。
const WD = preload("res://scripts/gameplay/wave_director.gd")
const PS = preload("res://scripts/engine/player_state.gd")
const CFG = preload("res://scripts/engine/mvp_config.gd")
const DE = preload("res://scripts/engine/damage_engine.gd")
const TD = preload("res://scripts/data/tower_data.gd")
const TEXT = preload("res://scripts/data/card_text.gd")
const MonsterLayer = preload("res://scripts/ui/monster_layer.gd")
const ChargeLabels = preload("res://scripts/ui/tower_level_layer.gd")
const VfxLayer = preload("res://scripts/ui/vfx_layer.gd")
class Positions extends RefCounted:
	var slots: Array = []
class PositionedMonster extends "res://scripts/gameplay/monster.gd":
	var location := Vector2.ZERO
	func pos(_speed: float, _length: float = 101.0) -> Vector2:
		return location

func set_positions(d, points: Array, hp: float = 1000.0) -> void:
	d.monsters = []
	for i in points.size():
		var m = PositionedMonster.new()
		m.setup(i, "Swarm", false, hp, 1.0, 10.0)
		m.location = points[i]
		d.monsters.append(m)

var passed := 0
var failed := 0
func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("[PASS] ", label)
	else:
		failed += 1
		print("[FAIL] ", label)
func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001
func make_battle(types: Array = ["Pyroclasm"], hp: float = 1000.0):
	var p = PS.new()
	for i in types.size():
		p.towers.append(PS.make_tower(i, String(types[i]), 1))
	p.n_hist_max = p.towers.size()
	var d = WD.new()
	d.setup(p, CFG.cfg_of("B"))
	d.start_wave(1)
	d.debug_set_monsters([10.0, 9.99, 1.0], hp)
	# 固定几何距离：第三只确实远于爆发直径，不依赖弯曲路径的端点位置。
	set_positions(d, [Vector2.ZERO, Vector2(0.1, 0.0), Vector2(200.0, 0.0)], hp)
	var positions = Positions.new()
	for i in types.size():
		positions.slots.append(d.monsters[0].pos(d.v0_))
	d.geo = positions
	return d
func tower_blasts(d) -> Array:
	return d._fire_blasts.filter(func(b): return b.get("kind", "") == "pyroclasm")

func apply_many(d, target, count: int) -> void:
	for i in count:
		d.apply_fire_effect(target)
func _initialize() -> void:
	quit(0 if run_all() else 1)
func run_all() -> bool:
	var d = make_battle()
	check("普通攻击 DPS 为零", near(DE.dps_only(d.player, d.cfg), 0.0))
	d.advance(0.1)
	check("单独放置不自动攻击、不自行充能", near(d.monsters[0].hp, 1000.0) and d._fire_charge.is_empty())
	d.free()
	d = make_battle()
	var target = d.monsters[0]
	apply_many(d, target, 11)
	check("同一敌人重复附加每次 +1", d._fire_charge[0] == 11 and near(target.hp, 960.0))
	check("附加后目标具有火焰状态", target.burn_remaining > 0.0 and d.snapshot()["monsters"][0]["burning"])
	d.apply_fire_effect(target)
	check("满 12 点立即清空", d._fire_charge[0] == 0)
	check("爆发对范围内每只敌人各造成 120", near(target.hp, 840.0) and near(d.monsters[1].hp, 840.0))
	check("爆发不伤害范围外敌人", near(d.monsters[2].hp, 1000.0))
	check("爆发自身不施加火焰、不递归充能", d._fire_charge[0] == 0)
	check("快照导出容量及爆发演出", d.snapshot()["towers"][0]["fire_capacity"] == 12 and tower_blasts(d).size() == 1)
	d._tick_fire_effects(2.1)
	check("状态到期与持续跳数不充能", near(target.burn_remaining, 0.0) and d._fire_charge[0] == 0)
	check("爆发特效按战斗时间结束", d._fire_blasts.is_empty())
	d.player.towers[0].disabled = true
	d.apply_fire_effect(target)
	check("停机塔不充能", d._fire_charge[0] == 0)
	d.player.towers[0].disabled = false
	d.apply_fire_effect(target)
	check("恢复后继续接收事件", d._fire_charge[0] == 1)
	target.hp = 0.0
	d.apply_fire_effect(target)
	check("死亡敌人不产生附加事件", d._fire_charge[0] == 1)
	d.state = WD.State.IDLE
	d.apply_fire_effect(d.monsters[1])
	check("非战斗期间不能充能", d._fire_charge[0] == 1)
	d.geo = null
	d.start_wave(2)
	check("新波次清空充能、附加时钟和爆发", d._fire_charge.is_empty() and d._fire_attack_clock.is_empty() and d._fire_blasts.is_empty())
	d.free()

	d = make_battle(["Pyroclasm", "Pyroclasm"])
	apply_many(d, d.monsters[0], 12)
	check("多座充能塔独立计数且同时爆发", d._fire_charge[0] == 0 and d._fire_charge[1] == 0 and tower_blasts(d).size() == 2)
	check("多塔爆发分别结算", near(d.monsters[0].hp, 720.0))
	d.apply_fire_effect(d.monsters[0])
	check("充满后下一次从 1 点开始", d._fire_charge[0] == 1 and d._fire_charge[1] == 1)
	d.free()

	d = make_battle(["Pyroclasm", "Cinder"])
	d._tick_fire_effects(0.9)
	check("未到攻击间隔不施加火焰", d._fire_charge.is_empty())
	d._tick_fire_effects(0.1)
	check("单体火塔实际附加只充一次", d._fire_charge[0] == 1 and d.monsters[0].burn_remaining > 0.0 and near(d.monsters[1].burn_remaining, 0.0))
	d.player.towers[1].disabled = true
	d._tick_fire_effects(1.0)
	check("停机的火系来源不产生事件", d._fire_charge[0] == 1)
	d.free()

	d = make_battle(["Pyroclasm", "Ember"])
	d._tick_fire_effects(1.0)
	check("群体火焰按实际附加的敌人数充能", d._fire_charge[0] == 2)
	d._tick_fire_effects(1.0)
	check("群体重复附加继续充能", d._fire_charge[0] == 4)
	d.free()

	d = make_battle(["Pyroclasm", "Frost"])
	d._tick_fire_effects(2.0)
	check("非火系攻击不会充能", d._fire_charge.is_empty())
	d.free()

	d = make_battle(["Pyroclasm", "Cinder"], 100.0)
	d._fire_charge[0] = 11
	d._fire_attack_clock[1] = 0.9
	d._substep()
	check("爆发击杀各结算一次（普攻不重复记账）", d.kills == 2 and near(d.scrap_earned, d.spk * 2.0))
	check("爆发击杀后满充归零", d._fire_charge[0] == 0)
	d.free()

	d = make_battle()
	d.combat_types_enabled = true
	d.monsters[0].proto = "Rush"
	apply_many(d, d.monsters[0], 12)
	check("爆发魔法伤害正确计算魔抗", near(d.monsters[0].hp, 872.0))
	d.free()

	d = make_battle()
	d.player.towers[0].h = 4
	apply_many(d, d.monsters[0], 12)
	check("等级提升增加爆发伤害", d.monsters[0].hp < 880.0)
	d.free()
	d = make_battle()
	check("半径边界计入覆盖数量", d._fire_coverage(Vector2.ZERO, PackedVector2Array([Vector2(28.0, 0.0)]), 784.0) == 1)
	check("刚超过半径不计入覆盖数量", d._fire_coverage(Vector2.ZERO, PackedVector2Array([Vector2(28.01, 0.0)]), 784.0) == 0)
	apply_many(d, d.monsters[0], 12)
	var foreign = preload("res://scripts/gameplay/monster.gd").new()
	foreign.setup(99, "Swarm", false, 100.0, 1.0, 10.0)
	d.apply_fire_effect(foreign)
	d.apply_fire_effect(null)
	check("无效目标与战场外对象不充能", d._fire_charge[0] == 0)
	d.free()

	d = make_battle(["Pyroclasm", "Cinder"])
	d.geo.slots[1] += Vector2(1000.0, 0.0)
	d._tick_fire_effects(2.0)
	check("射程外的敌人不被附加火焰", d._fire_charge.is_empty())
	d.free()
	d = make_battle()
	set_positions(d, [Vector2.ZERO, Vector2(200, 200), Vector2(205, 200), Vector2(210, 205)])
	d.geo.slots[0] = Vector2.ZERO
	apply_many(d, d.monsters[0], 12)
	var cluster_center: Vector2 = tower_blasts(d)[0]["pos"]
	check("优先轰炸远处三人敌群，不以塔或触发目标为中心", cluster_center.distance_to(Vector2(205, 200)) <= 28.0 and near(d.monsters[0].hp, 960.0))
	check("密集区全部受伤，稀疏区不受伤", near(d.monsters[1].hp, 880.0) and near(d.monsters[2].hp, 880.0) and near(d.monsters[3].hp, 880.0))
	check("相同敌群选点确定且无随机漂移", d._fire_blast_center(28.0)["pos"] == cluster_center)
	d.free()

	d = make_battle()
	# 三角形的边长超过爆发半径，但可以用非敌人位置的爆心覆盖三人。
	set_positions(d, [Vector2.ZERO, Vector2(40, 0), Vector2(20, 34.641)])
	var optimal: Vector2 = d._fire_blast_center(28.0)["pos"]
	apply_many(d, d.monsters[0], 12)
	check("搜索敌人之间的区域，不仅以某个敌人为爆心", optimal != d.monsters[0].pos(0.0) and optimal != d.monsters[1].pos(0.0) and optimal != d.monsters[2].pos(0.0))
	check("最优圆同时命中三角形三名敌人", near(d.monsters[0].hp, 840.0) and near(d.monsters[1].hp, 880.0) and near(d.monsters[2].hp, 880.0))
	d.free()

	d = make_battle()
	set_positions(d, [Vector2.ZERO, Vector2(200, 0), Vector2(200, 0), Vector2(200, 0), Vector2(200, 0)])
	d.monsters[1].hp = 0.0
	d.monsters[2].hp = 0.0
	d.monsters[3].state = WD.MState.LEAKED
	d.monsters[4].state = WD.MState.LEAKED
	apply_many(d, d.monsters[0], 12)
	check("死亡和已漏出的敌人不影响最密集区域", tower_blasts(d)[0]["pos"] == Vector2.ZERO and near(d.monsters[0].hp, 840.0))
	check("已漏出的敌人不受到爆发", near(d.monsters[3].hp, 1000.0))
	d.monsters[0].hp = 0.0
	check("无有效敌人时没有目标区域", d._fire_blast_center(28.0).is_empty())
	d.free()

	d = make_battle(["Pyroclasm", "Pyroclasm"])
	set_positions(d, [Vector2.ZERO, Vector2(1, 0), Vector2(200, 0)])
	d.monsters[0].hp = 100.0
	d.monsters[1].hp = 100.0
	d.monsters[2].hp = 100.0
	apply_many(d, d.monsters[0], 12)
	check("多塔连续爆发会重新选取存活敌群", d.kills == 3 and tower_blasts(d).size() == 2 and tower_blasts(d)[0]["pos"].distance_to(tower_blasts(d)[1]["pos"]) > 28.0)
	d.free()
	check("卡面明确被动、充能次数和爆发伤害", TEXT.describe("Pyroclasm").contains("不自动攻击") and TEXT.describe("Pyroclasm").contains("12") and TEXT.describe("Pyroclasm").contains("120"))
	test_fire_stacks()
	print("Fire charge: %d PASS, %d FAIL" % [passed, failed])
	return failed == 0

func test_fire_stacks() -> void:
	var d = make_battle(["Arrow"])
	set_positions(d, [Vector2(100, 100), Vector2(106, 100), Vector2(106.01, 100)])
	var target = d.monsters[0]
	var edge = d.monsters[1]
	var outside = d.monsters[2]
	edge.burn_stacks = 3
	edge.burn_remaining = 2.0
	apply_many(d, target, 9)
	check("火焰可以累积到九层，未满层不爆炸", target.burn_stacks == 9 and near(target.hp, 1000.0) and d._fire_blasts.is_empty())
	check("快照导出实际火焰层数", d.snapshot()["monsters"][0]["burn_stacks"] == 9)
	d.apply_fire_effect(target)
	check("第十层立即清空层数和持续时间", target.burn_stacks == 0 and near(target.burn_remaining, 0.0) and not d.snapshot()["monsters"][0]["burning"])
	check("引爆以触发目标为中心而不是塔的位置", d._fire_blasts[0]["pos"] == Vector2(100, 100) and d._fire_blasts[0]["kind"] == "ignition")
	check("小爆炸伤及目标自身及半径六边界敌人", near(target.hp, 960.0) and near(edge.hp, 960.0))
	check("小爆炸不伤害刚超出范围的敌人", near(outside.hp, 1000.0))
	check("爆炸不清空或增加邻居的火焰层数", edge.burn_stacks == 3 and outside.burn_stacks == 0)
	check("小爆炸不是焚星塔爆发且不需要焚星塔", tower_blasts(d).is_empty() and d._fire_charge.is_empty())
	d.apply_fire_effect(target)
	check("引爆后可以重新从一层积累", target.burn_stacks == 1)
	apply_many(d, target, 9)
	check("二十次附加恰好引爆两次", target.burn_stacks == 0 and near(target.hp, 920.0) and d._fire_blasts.size() == 2)
	d.free()

	d = make_battle(["Arrow"])
	target = d.monsters[0]
	apply_many(d, target, 4)
	d._tick_fire_effects(1.5)
	check("火焰未到期时保留已有层数", target.burn_stacks == 4 and near(target.burn_remaining, 0.5))
	d.apply_fire_effect(target)
	check("再次附加增加一层并刷新两秒持续时间", target.burn_stacks == 5 and near(target.burn_remaining, 2.0))
	d._tick_fire_effects(2.1)
	check("火焰到期清除全部层数，不会触发爆炸", target.burn_stacks == 0 and near(target.burn_remaining, 0.0) and near(target.hp, 1000.0) and d._fire_blasts.is_empty())
	d.apply_fire_effect(target)
	check("到期后下一次从一层开始", target.burn_stacks == 1)
	target.setup(0, "Swarm", false, 1000.0, 1.0, 10.0)
	check("怪物重新初始化不保留上一轮火焰", target.burn_stacks == 0 and near(target.burn_remaining, 0.0))
	d.free()

	d = make_battle(["Cinder", "Cinder"])
	for i in 5:
		d._tick_fire_effects(1.0)
	check("不同火系来源共享同一敌人的层数", d.monsters[0].burn_stacks == 0 and near(d.monsters[0].hp, 960.0) and d._fire_blasts.size() == 1)
	d.free()

	d = make_battle()
	d.combat_types_enabled = true
	target = d.monsters[0]
	target.proto = "Rush"
	apply_many(d, target, 10)
	check("小爆炸魔法伤害受魔抗减免", near(target.hp, 968.0))
	check("十次附加给焚星塔十点充能，爆炸不额外充能", d._fire_charge[0] == 10 and tower_blasts(d).is_empty())
	d.free()

	d = make_battle()
	target = d.monsters[0]
	target.hp = 40.0
	d.monsters[1].hp = 40.0
	apply_many(d, target, 10)
	check("引爆击杀正常计入击杀及废料奖励", d.kills == 2 and near(d.scrap_earned, 2.0 * d.spk))
	check("致死的第十次附加仍然为焚星塔充能", d._fire_charge[0] == 10)
	d._substep()
	check("引爆击杀不会被后续普攻重复记账", d.kills == 2 and near(d.scrap_earned, 2.0 * d.spk))
	d.free()

	d = make_battle()
	target = d.monsters[0]
	target.burn_stacks = 9
	target.burn_remaining = 2.0
	target.hp = 40.0
	d.monsters[1].hp = 40.0
	d._fire_charge[0] = 11
	d.apply_fire_effect(target)
	check("同一次附加能同时触发十层引爆和满充爆发", target.burn_stacks == 0 and d._fire_charge[0] == 0 and d._fire_blasts.size() == 2)
	check("满层引爆后焚星塔选择剩余敌群", d.kills == 2 and near(d.monsters[2].hp, 880.0) and tower_blasts(d)[0]["pos"] == d.monsters[2].pos(d.v0_))
	d.free()
