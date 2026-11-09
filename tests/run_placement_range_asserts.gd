extends SceneTree
const Space := preload("res://scripts/geo/space_model.gd")
const Grid := preload("res://scripts/geo/build_grid.gd")
const Camera := preload("res://scripts/ui/battlefield_camera.gd")
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
	if DisplayServer.get_name()!="headless":
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
	scene.queue_free()
	paused = false
	Space.terrain_enabled = false
	Camera.reset()
	await process_frame
	print("Placement range: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
