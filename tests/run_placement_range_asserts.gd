extends SceneTree
const Space := preload("res://scripts/geo/space_model.gd")
const Grid := preload("res://scripts/geo/build_grid.gd")
const Camera := preload("res://scripts/ui/battlefield_camera.gd")
const TC := preload("res://scripts/gameplay/tactical_combat.gd")
const TowerRange := preload("res://scripts/gameplay/tower_range.gd")
const Battle := preload("res://tests/run_fire_charge_asserts.gd")
const TD := preload("res://scripts/data/tower_data.gd")
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
	root.size = Vector2i(1600,900)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	scene.auto_start_run = false
	root.add_child(scene)
	scene.wave_director.stage_waves_enabled = true
	scene.wave_director.set_stage("0-1")
	scene.controller.start_new_run()
	scene.director.close_shop()
	scene.get_node("TutorialLayer/TutorialOverlay")._on_skip_pressed()
	await process_frame
	var ml = scene.get_node("Battlefield/MonsterLayer")
	var rt = scene.controller.runtime
	if "--sector-playtest" in OS.get_cmdline_user_args():
		scene.wave_director.tactical_combat_enabled = true
		rt.pending = ["Sniper", "Ember", "Arcbeacon", "Arcbeacon", "Rangebeacon", "Rangebeacon"]
		rt.pending_cost = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		scene.controller.shop_changed.emit()
		Camera.overview()
		scene.get_node("BattlefieldNavigation")._refresh()
		return
	var target := Grid.snap(Space.RADIAL_CORE+Vector2(28,-5))
	check(Grid.buildable(target),"预览测试目标可建")
	ml.probe_hover_world = target+Vector2(0.3,0.4)
	check(ml.placement_range_preview().is_empty(),"平常不显示放置射程")
	rt.pending = ["Blaze","Lance","Foundry"]
	rt.pending_cost = [12.0,12.0,12.0]
	check(scene.controller.request_placement(1),"选择背包中第二张卡")
	var preview: Dictionary = ml.placement_range_preview()
	check(float(preview.radius)==TD.tower_rng("Lance"),"射程取自正在拖动的卡牌，而非第一张")
	check(preview.center==target and preview.valid,"圆心与合法吸附落点一致")
	var screen_center: Vector2 = ml.world_to_screen(preview.center)
	var screen_edge: Vector2 = ml.world_to_screen(preview.center+Vector2(preview.radius,0))
	check(is_equal_approx(screen_center.distance_to(screen_edge),TD.tower_rng("Lance")*ml.world_scale()),"屏幕半径与真实战斗射程一致")
	Camera.zoom_at(1.5,Vector2(960,500),root.get_visible_rect().size)
	Camera.pan(Vector2(-100,40),root.get_visible_rect().size)
	scene.get_node("BattlefieldNavigation")._refresh()
	preview = ml.placement_range_preview()
	check(preview.center==target and float(preview.radius)==TD.tower_rng("Lance"),"镜头拖动缩放不改变实际范围")
	check(ml.screen_to_world_position(ml.world_to_screen(target)).distance_to(target)<0.001,"拖放换算与预览一致")
	if DisplayServer.get_name()!="headless" and "--sector-preview" not in OS.get_cmdline_user_args() and "--aura-preview" not in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art/_review/placement-attack-range.png")
	ml.probe_hover_world = Space.RADIAL_CORE
	check(not bool(ml.placement_range_preview().valid),"禁建区域标为无效射程预览")
	ml.probe_hover_world = target
	scene.director.exit_placement(false)
	check(ml.placement_range_preview().is_empty(),"取消放置立即隐藏范围")
	check(scene.controller.request_placement(2),"可预览经济建筑")
	check(ml.placement_range_preview().is_empty(),"不攻击的经济建筑不显示攻击范围")
	scene.director.exit_placement(false)
	scene.controller.request_placement(1)
	scene.director.place_at_requested.emit(target)
	check(ml.placement_range_preview().is_empty(),"完成放置后隐藏范围")
	rt.pending.append("Lance")
	rt.pending_cost.append(12.0)
	scene.controller.request_placement(rt.pending.size()-1)
	preview = ml.placement_range_preview()
	check(preview.mode=="upgrade" and preview.valid and preview.center==target,"同类塔升级时也显示正确范围")
	scene.director.exit_placement(false)
	scene.controller.request_placement(0)
	check(not bool(ml.placement_range_preview().valid),"不同塔占用时范围显示无效")
	scene.director.exit_placement(false)
	# 真实鼠标回到背包时，不在背包下面绘制地图范围。
	ml.probe_hover_world = null
	scene.controller.request_placement(0)
	var over_bag: Vector2 = scene.tower_backpack.position+Vector2(160,50)
	check(ml._placement_hover_world(over_bag)==null,"背包区域不显示地图范围")
	scene.director.exit_placement(false)
	scene.wave_director.tactical_combat_enabled = true
	rt.pending = ["Sniper", "Sniper"]
	rt.pending_cost = [12.0, 12.0]
	var sniper_pos := Grid.snap(Space.RADIAL_CORE + Vector2(12, 3))
	ml.probe_hover_world = sniper_pos
	check(scene.controller.request_placement(0), "进入狙击塔放置")
	preview = ml.placement_range_preview()
	check(preview.valid and preview.radius == 44.0 and is_equal_approx(rad_to_deg(preview.angle), 40.0), "狙击塔显示 40 度、半径 44")
	var initial_facing: float = preview.facing
	var rotate := InputEventKey.new()
	rotate.keycode = KEY_E
	rotate.pressed = true
	ml._input(rotate)
	preview = ml.placement_range_preview()
	check(is_equal_approx(angle_difference(initial_facing, preview.facing), deg_to_rad(15)), "E 旋转预览 15 度")
	scene.director.place_at_requested.emit(sniper_pos)
	var sniper = rt.player.towers[rt._tower_index(rt.last_placed_slot)]
	check(is_equal_approx(angle_difference(sniper.range_facing, preview.facing), 0.0), "落子保留预览朝向")
	check(scene.controller.request_placement(0), "进入同卡合成")
	preview = ml.placement_range_preview()
	check(preview.mode == "upgrade" and preview.radius == 47.0 and preview.before.x == 44.0, "合成同时预览半径 44 和 47")
	check(is_equal_approx(angle_difference(sniper.range_facing, preview.facing), 0.0), "合成沿用塔的朝向")
	if DisplayServer.get_name() != "headless" and "--sector-preview" in OS.get_cmdline_user_args():
		Camera.overview()
		scene.get_node("BattlefieldNavigation")._refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/sector-merge.png")
	scene.director.place_at_requested.emit(sniper_pos)
	sniper = rt.player.towers[rt._tower_index(rt.last_placed_slot)]
	check(sniper.range_merges == 1 and sniper.h == 2, "同卡同时提升层数和攻击范围")
	scene.director.tower_select_requested.emit(int(sniper.slot))
	ml._input(rotate)
	sniper = rt.player.towers[rt._tower_index(rt.last_placed_slot)]
	check(is_equal_approx(angle_difference(preview.facing, sniper.range_facing), deg_to_rad(15.0)), "准备阶段可以转向已部署塔")
	Camera.overview()
	scene.get_node("BattlefieldNavigation")._refresh()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = ml.world_to_screen(target)
	press.global_position = press.position
	ml._unhandled_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = press.position
	ml._input(release)
	ml._update_tower_details()
	check(ml._tower_details.panel.visible and "射程" in ml._tower_details.body.text, "点击圆形射程塔时显示部署详情")
	ml._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = ml.world_to_screen(sniper_pos)
	ml._input(motion)
	ml._grid_edges.clear()
	await process_frame
	await process_frame
	check(ml._move_dragging and not ml._grid_edges.is_empty(), "移位拖动绘制六边形放置网格")
	check(not ml._tower_details.panel.visible, "拖动时隐藏塔详情")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ml._input(escape)
	ml._update_tower_details()
	check(not ml._move_dragging and ml._tower_details.panel.visible, "取消移位后恢复选中塔的详情")
	check(TowerRange.profile("Ember", 9).is_equal_approx(Vector2(14.0, deg_to_rad(150.0))), "余烬塔扩角封顶")
	check(TowerRange.profile("Arrow", 9).x == TD.tower_rng("Arrow") + 4.0, "箭塔射程成长封顶")
	var fixture := Battle.new()
	var battle = fixture.make_battle(["Sniper"])
	battle.geo = preload("res://scripts/geo/geo.gd").new([Vector2.ZERO])
	fixture.set_positions(battle, [Vector2(20, 21), Vector2(45, 0), Vector2(20, 0)])
	TC.apply(battle, 1.0)
	check(battle.monsters[0].hp == 1000.0 and battle.monsters[1].hp == 1000.0 and battle.monsters[2].hp < 1000.0,
		"战斗跳过扇外和超射程敌人，伤害扇内敌人")
	battle.player.towers[0].range_merges = 1
	TC.apply(battle, 1.0)
	check(battle.monsters[1].hp < 1000.0, "合成后实际命中新增射程里的敌人")
	battle.free()

	var support_pos := Grid.snap(sniper_pos + Vector2(0.0, 4.0))
	rt.pending = ["Rangebeacon", "Arcbeacon", "Sniper"]
	rt.pending_cost = [12.0, 12.0, 12.0]
	ml.probe_hover_world = support_pos
	check(scene.controller.request_placement(0), "可以部署延程塔")
	preview = ml.placement_range_preview()
	check(preview.valid and preview.radius == 8.0 and preview.aura.has("attack_radius"), "延程塔摆放时预览半径 8 的光环")
	scene.director.place_at_requested.emit(support_pos)
	ml.probe_hover_world = Grid.snap(sniper_pos + Vector2(4.0, 0.0))
	check(scene.controller.request_placement(0), "可以部署展域塔")
	preview = ml.placement_range_preview()
	check(preview.valid and preview.radius == 8.0 and preview.aura.has("angle_degrees"), "展域塔摆放时预览扩角光环")
	scene.director.place_at_requested.emit(preview.center)
	check(scene.controller.request_placement(0), "可预览受光环加成的同卡合成")
	ml.probe_hover_world = sniper_pos
	preview = ml.placement_range_preview()
	check(preview.before.x == 49.0 and preview.radius == 52.0 and is_equal_approx(rad_to_deg(preview.angle), 50.0),
		"合成预览同时计入既有叠层、两种光环和新增叠层")
	if DisplayServer.get_name() != "headless" and "--aura-preview" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/range-aura-preview.png")
	scene.director.exit_placement(false)

	battle = fixture.make_battle(["Sniper", "Arcbeacon", "Arcbeacon", "Rangebeacon"])
	battle.geo = preload("res://scripts/geo/geo.gd").new([Vector2.ZERO, Vector2(0, 8), Vector2(3, 0), Vector2(-3, 0)])
	battle.player.towers[3].h = 2
	var new_target := Vector2.from_angle(deg_to_rad(28)) * 47.0
	fixture.set_positions(battle, [new_target])
	var auras := TowerRange.active_auras(battle.player.towers, battle.geo)
	var arrow := TowerRange.with_auras(TowerRange.profile("Arrow"), Vector2.ZERO, auras)
	check(arrow.is_equal_approx(Vector2(TD.tower_rng("Arrow") + 4.0, TAU)), "圆形塔只获得射程加成")
	check(TowerRange.with_auras(TowerRange.profile("Sniper"), Vector2(20, 0), auras) == TowerRange.profile("Sniper"),
		"离开光环范围后无加成")
	TC.apply(battle, 1.0)
	check(battle.monsters[0].hp < 1000.0, "多座展域塔与多层延程塔叠加后，能命中原本同时超角度和超距离的目标")
	battle.monsters[0].hp = 1000.0
	battle.player.towers[1].disabled = true
	TC.apply(battle, 1.0)
	check(battle.monsters[0].hp == 1000.0, "停机后即时失去扩角，目标不再受击")
	battle.player.towers[1].disabled = false
	battle.player.towers[3].h = 1
	TC.apply(battle, 1.0)
	check(battle.monsters[0].hp == 1000.0, "少一层延程时，目标仍在射程外")
	battle.free()
	fixture.free()
	scene.queue_free()
	paused = false
	Space.terrain_enabled = false
	Camera.reset()
	await process_frame
	print("Placement range: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
