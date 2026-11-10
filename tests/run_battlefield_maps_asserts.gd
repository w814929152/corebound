extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")
const Maps := preload("res://scripts/data/battlefield_maps.gd")
const Grid := preload("res://scripts/geo/build_grid.gd")
const Campaign := preload("res://scripts/data/campaign_data.gd")
const Monster := preload("res://scripts/gameplay/monster.gd")
const Tactical := preload("res://scripts/gameplay/tactical_combat.gd")
const Terrain := preload("res://scripts/ui/battlefield_terrain.gd")
const Boot := preload("res://scripts/ui/boot.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	Space.mode = Space.Mode.RADIAL
	Space.terrain_enabled = true
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1600,900)
		root.content_scale_size = Vector2i(1920,1080)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	scene.auto_start_run = false
	root.add_child(scene)
	await process_frame
	var themes: Dictionary = {}
	for sid in Campaign.STAGE_ORDER:
		var map_id: String = Campaign.resolve_map_id(sid)
		Space.set_active_map(map_id)
		var profile := Maps.profile(map_id)
		themes[profile.theme] = true
		check(Maps.contains(map_id,Space.RADIAL_CORE),sid+" 核心在地面内")
		check(not Grid.buildable(Space.RADIAL_CORE),sid+" 核心禁建")
		var reserved := 0
		for q in range(-2, 3):
			for r in range(-2, 3):
				if maxi(maxi(absi(q), absi(r)), absi(q+r)) <= 2:
					reserved += 1
					check(not Grid.buildable(Grid.cell(q,r)),sid+" 七格基地及外围十二格禁建")
		check(reserved == 19,sid+" 基地与外圈共十九格")
		for direction in Grid.neighbors():
			var outside: Vector2 = Grid.cell(direction.x*3,direction.y*3)
			check(Grid.buildable(outside),sid+" 外圈之外六方向恢复可建")
		check(not Grid.buildable(Space.RADIAL_CORE+Vector2(73,44)*Maps.MAP_SCALE),sid+" 地块外不能建塔")
		var cells: Array = Grid.all_cells()
		check(cells.size()>600,sid+" 保留足够布防空间")
		for cell in cells:
			check(Maps.contains(map_id,cell) and not Maps.blocked(map_id,cell,Space.active_ridges()),sid+" 格点与可见地形一致")
		for edge_point in Grid.grid_edges():
			check(Grid.buildable(edge_point),sid+" 放置网格不越过地块或墙体")
		var radii: Array = []
		for i in range(100):
			var theta := Tactical.spawn_theta(i,1,sid)
			var radius := Maps.entry_radius(map_id,theta)
			radii.append(radius)
			var m = Monster.new()
			m.setup(i,"Swarm",false,100.0,1.0,Space.T_REACH)
			m.set_theta(theta)
			var entry: Vector2 = m.pos(5.5)
			check(is_equal_approx(entry.distance_to(Space.RADIAL_CORE),radius),sid+" 从真实地块边缘出生")
			check(Maps.contains(map_id,entry.lerp(Space.RADIAL_CORE,0.001)),sid+" 出生点内侧是地面")
			for fraction in [0.1,0.3,0.5,0.7,0.9]:
				m.t_remain = Space.T_REACH*fraction
				var position: Vector2 = m.pos(5.5)
				check(Maps.contains(map_id,position),sid+" 进攻路线留在地面")
				check(not Maps.blocked(map_id,position,Space.active_ridges()),sid+" 进攻路线不穿障碍")
			m.t_remain = 0.0
			check(m.pos(5.5).distance_to(Space.RADIAL_CORE)<0.001,sid+" 最终抵达核心")
		check(float(radii.max())-float(radii.min())>15.0,sid+" 外沿并非圆形")
		var commands: Array = Terrain.Painter.new().build(map_id)
		check(commands.size()>200,sid+" 场景有铺装、道路和立体断面")
		scene.wave_director.stage_waves_enabled = true
		scene.wave_director.tactical_combat_enabled = true
		scene.wave_director.set_stage(sid)
		scene.controller.start_new_run()
		scene.director.close_shop()
		scene.get_node("TutorialLayer/TutorialOverlay")._on_skip_pressed()
		var ml = scene.get_node("Battlefield/MonsterLayer")
		var before: Dictionary = ml._xform()
		var vfx = scene.get_node("Battlefield/VfxLayer")
		for point in [Space.RADIAL_CORE, cells[0], cells.back()]:
			check(ml._to_screen(point).distance_to(vfx._to_screen(point))<0.001,sid+" 特效与单位坐标一致")
		scene.director.open_shop()
		check(before == ml._xform(),sid+" 商店开关不移动地图")
		scene.director.close_shop()
		var rt = scene.controller.runtime
		check(rt.buy(0) and rt.begin_placement(0),sid+" 可以购买并准备放置")
		for q in range(-2, 3):
			for r in range(-2, 3):
				if maxi(maxi(absi(q), absi(r)), absi(q+r)) <= 2:
					check(not rt.confirm_placement_at(Grid.cell(q,r)),sid+" 实际放置拒绝基地及外圈")
		check(not rt.pending.is_empty(),sid+" 禁建失败后保留背包建筑")
		var target: Vector2 = cells[int(cells.size()/2)]
		check(rt.confirm_placement_at(target),sid+" 可在场景地面放塔")
		check(rt.pending.is_empty(),sid+" 放置后从背包移除")
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://art/_review/terrain-"+map_id+".png")
	check(themes.size()==10,"十关主题互不重复")
	scene.queue_free()
	paused = false
	Space.terrain_enabled = false
	Space.set_active_map("tri-fissure")
	await process_frame
	print("Battlefield maps: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
