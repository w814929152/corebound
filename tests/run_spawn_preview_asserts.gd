extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")
const Campaign := preload("res://scripts/data/campaign_data.gd")
const WD := preload("res://scripts/gameplay/wave_director.gd")
const MonsterData := preload("res://scripts/data/monster_data.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	Space.mode = Space.Mode.RADIAL
	Space.terrain_enabled = true
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	scene.auto_start_run = false
	root.add_child(scene)
	await process_frame
	var wd = scene.wave_director
	var layer = scene.get_node("Battlefield/MonsterLayer")
	wd.stage_waves_enabled = true
	wd.tactical_combat_enabled = true
	for sid in Campaign.STAGE_ORDER:
		Space.set_active_map(Campaign.resolve_map_id(sid))
		wd.set_stage(sid)
		scene.controller.start_new_run()
		for wave in [1, 2, 3, 4]:
			wd.mechanical_siege_enabled = false
			wd.start_wave(wave)
			var baseline_count: int = wd.n
			var baseline_hp: float = wd.hp_unit
			var baseline_scrap: float = wd.spk * wd.n
			scene.director.sm.wave = wave - 1
			wd.state = WD.State.SAFE_WINDOW
			var baseline_points: PackedVector2Array = layer.next_spawn_preview()
			wd.mechanical_siege_enabled = true
			var old_spawned: int = wd.spawned
			var old_wave: int = wd.w
			var points: PackedVector2Array = layer.next_spawn_preview()
			check(not points.is_empty(), sid + " 准备阶段有出怪预告")
			check(points == layer.next_spawn_preview(), sid + " 重读稳定")
			check(wd.spawned == old_spawned and wd.w == old_wave, sid + " 预告不推进战斗")
			wd.start_wave(wave)
			check(wd.n > baseline_count and points.size() > baseline_points.size(), sid + " 围城波提高数量且刷新预告缓存")
			check(wd.hp_unit < baseline_hp, sid + " 围城波降低单怪血量")
			check(is_equal_approx(wd.spk * wd.n, baseline_scrap), sid + " 基础废料预算守恒")
			check(points.size() == wd.n, sid + " 预告数量对应实际波表")
			var entrances := {}
			for point in points:
				entrances[point] = true
			var expected_fronts := mini(1 if wave <= 2 else 2, Space.active_spawn_arcs().size())
			check(entrances.size() == expected_fronts if wave <= 3 else entrances.size() > expected_fronts,
				sid + " 前三波集中来袭，第四波开放多向进攻")
			check(layer.next_spawn_preview().is_empty(), sid + " 战斗隐藏预告")
			for index in [0, wd.n - 1]:
				wd._spawn_one(index)
				var monster = wd.monsters.back()
				check(monster.pos(wd.v0_).distance_to(points[index]) < 0.001, sid + " 预告与真实出生点一致")
				check(float(monster.m_dps) < float(MonsterData.M_DPS[monster.proto]), sid + " 单怪结构伤害下降")
			wd.monsters.clear()
		wd.state = WD.State.SAFE_WINDOW
		scene.controller.over = true
		check(layer.next_spawn_preview().is_empty(), sid + " 结算隐藏预告")
		scene.controller.over = false
	check(wd.preview_spawn_positions(10000).is_empty(), "关卡结束无下一波标记")
	scene.queue_free()
	paused = false
	await process_frame
	print("Spawn preview: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
