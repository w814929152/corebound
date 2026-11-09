extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")
const Data := preload("res://scripts/data/campaign_data.gd")
const Briefings := preload("res://scripts/data/stage_briefings.gd")
const Tactical := preload("res://scripts/gameplay/tactical_combat.gd")
const WD := preload("res://scripts/gameplay/wave_director.gd")
const Monster := preload("res://scripts/gameplay/monster.gd")
const PS := preload("res://scripts/engine/player_state.gd")
const Geo := preload("res://scripts/geo/geo.gd")
const Cfg := preload("res://scripts/engine/mvp_config.gd")
const Result := preload("res://scripts/ui/result_overlay.gd")
const StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")
# 编译真实启动入口，避免只测测试场景而漏掉产品接线。
const Boot := preload("res://scripts/ui/boot.gd")

class MemoryCampaign extends "res://scripts/gameplay/campaign.gd":
	func save() -> bool:
		return true

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func monster_at(point: Vector2, health: float = 100.0):
	var m = Monster.new()
	var rho := point.distance_to(Space.RADIAL_CORE)
	m.setup(0, "Swarm", false, health, 1.0, rho / Space.SPAWN_RADIUS * Space.T_REACH)
	m.set_theta((point - Space.RADIAL_CORE).angle())
	return m

func run() -> void:
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1600, 900)
		root.content_scale_size = Vector2i(1920, 1080)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	Space.mode = Space.Mode.RADIAL
	var p = PS.new()
	p.path = "B"
	p.towers = [PS.make_tower(0, "Arrow", 1)]
	var geo = Geo.new([Space.RADIAL_CORE + Vector2(20, 0)])
	var wd = WD.new()
	wd.setup(p, Cfg.cfg_of("B"), geo)
	wd.combat_types_enabled = true
	var far = monster_at(Space.RADIAL_CORE + Vector2(-20, 0))
	var near = monster_at(Space.RADIAL_CORE + Vector2(18, 0))
	wd.monsters = [far, near]
	Tactical.apply_in_range(wd, geo.slots[0], 22.0, 10.0, "physical", 0.0)
	check(far.hp == 100.0 and is_equal_approx(near.hp, 90.0), "射程外队首不能截走塔伤害")
	near.hp = 1.0
	var next = monster_at(Space.RADIAL_CORE + Vector2(17, 0))
	wd.monsters = [far, near, next]
	Tactical.apply_in_range(wd, geo.slots[0], 22.0, 10.0, "physical", 0.0)
	check(near.hp == 0.0 and next.hp == 91.0 and far.hp == 100.0, "溢出仅结转到射程内目标")
	check(wd.kills == 1, "射程击杀复用统一记账")
	next.proto = "Tank"
	next.hp = 100.0
	wd.monsters = [next]
	Tactical.apply_in_range(wd, geo.slots[0], 22.0, 10.0, "physical", 0.0)
	check(is_equal_approx(next.hp, 93.0), "物理抗性仍生效")
	next.hp = 100.0
	Tactical.apply_in_range(wd, geo.slots[0], 22.0, 10.0, "true", 0.0)
	check(is_equal_approx(next.hp, 90.0), "真实伤害仍无视抗性")
	p.towers[0].disabled = true
	next.hp = 100.0
	Tactical.apply(wd, 0.1)
	check(next.hp == 100.0, "失能塔不输出")
	p.towers[0].disabled = false
	Tactical.apply(wd, 0.1)
	check(next.hp < 100.0, "逐塔结算使用真实构筑输出")
	wd.monsters = [far]
	Tactical.apply(wd, 0.1)
	check(far.hp == 100.0, "整条逐塔路径不伤害远端敌人")
	p.towers = [PS.make_tower(0, "Plague", 1)]
	Tactical.apply(wd, 0.1)
	check(far.hp == 100.0, "持续伤害不再全场穿越射程")
	var baseline = WD.new()
	check(not baseline.tactical_combat_enabled, "基准导演默认关闭新规则")
	baseline.free()

	for sid in Data.STAGE_ORDER:
		var b := Briefings.get_briefing(sid)
		check(not b.is_empty() and b.has("hint") and b.has("clear"), sid + " 有战术与结局")
		Space.set_active_map(Data.resolve_map_id(sid))
		check(wd.set_stage(sid, 0) == false, "波表关闭时不能注入")
		wd.stage_waves_enabled = true
		check(wd.set_stage(sid, 0), sid + " 波表已接入")
		wd.start_wave(1)
		check(wd._max_wave == Data.wave_count(sid), sid + " 通关波数一致")
		var arcs: Array = Space.active_spawn_arcs()
		var counts: Array = []
		counts.resize(arcs.size())
		counts.fill(0)
		for i in range(600):
			var angle := fposmod(rad_to_deg(Tactical.spawn_theta(i, 1, sid)), 360.0)
			check(not Space.is_ridge_deg(angle), sid + " 出生不落在障碍角内")
			for j in range(arcs.size()):
				var a: Dictionary = arcs[j]
				var offset := fposmod(angle - float(a["a0"]), 360.0)
				if offset <= float(a["a1"]) - float(a["a0"]) + 0.000001:
					counts[j] += 1
		if sid != "0-1":
			check(int(counts.max()) - int(counts.min()) <= 4, sid + " 每入口分配相同来敌配额")
		else:
			check(Tactical.spawn_theta(3, 1, sid) == Space.spawn_theta(3, 1), "教学关保留基准布局")
		wd.tactical_combat_enabled = true
		wd._spawn_one(0)
		check(wd.monsters[0].theta == Tactical.spawn_theta(0, 1, sid), sid + " 真实刷怪使用关卡入口分配")
		wd.monsters.clear()
		wd.stage_waves_enabled = false
	wd.free()

	var campaign = MemoryCampaign.new()
	var first: Dictionary = campaign.on_cleared("0-1")
	check(first.unlocked_stages.size() == 3, "教学通关同时开放外环三关")
	var reward: Dictionary = campaign.on_cleared("1-1")
	check(reward.unlocked_deck == "cinder" and reward.unlocked_stages.size() == 2, "地区通关开放科技与相邻关卡")
	var again: Dictionary = campaign.on_cleared("1-1")
	check(again.unlocked_deck == "" and again.unlocked_stages.is_empty(), "重复通关不伪报新科技")
	check(Briefings.unlock_hint("5-1").contains("或"), "分支解锁明确任一前置")
	check(Briefings.unlock_hint("9-1").contains("7 个地区") and Briefings.unlock_hint("9-1").contains("8-1"), "终局提示完整门槛")
	var ov = Result.new()
	root.add_child(ov)
	ov.show_result(true, 12, 500, 1000, 30)
	ov.show_campaign_result("1-1", true, reward)
	check(ov._body_label.text.contains("熔炉包") and ov._body_label.text.contains("雷暴电网") and ov._body_label.text.contains("锻造联合体"), "结算展示全部解锁")
	check(ov._restart_btn.text == "返回航图", "结算返回选关")
	await capture("stage-implementation-result")
	ov.queue_free()
	await process_frame
	var selector = StageSelect.new()
	root.add_child(selector)
	selector.open(campaign)
	var edges: Array = selector.route_edges()
	check(edges.size() == 10, "航图展示九条分支路线与一条决战前置")
	var wrong_edge := false
	for edge in edges:
		if edge.source == "1-1" and edge.target == "2-1":
			wrong_edge = true
	check(not wrong_edge, "航图不把外环三关画成顺序链")
	selector._hovered = "9-1"
	selector._refresh_detail()
	check(selector._detail_state.text.contains("7 个地区") and selector._detail_state.text.contains("8-1"), "航图显示真实终局门槛")
	await capture("stage-implementation-map")
	selector.queue_free()
	await process_frame

	# 十关真实场景开局：换图、准备阶段、HUD、手动开波和总波数接线。
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	scene.auto_start_run = false
	root.add_child(scene)
	await process_frame
	scene.wave_director.tactical_combat_enabled = true
	scene.wave_director.stage_waves_enabled = true
	var progress = MemoryCampaign.new()
	scene.controller.run_finished.connect(func(won: bool, _wave: int) -> void:
		if won:
			scene.controller.campaign_result = progress.on_cleared(String(scene.wave_director.stage_id)))
	for sid in Data.STAGE_ORDER:
		Space.set_active_map(Data.resolve_map_id(sid))
		scene.wave_director.set_stage(sid, 0)
		scene.controller.start_new_run()
		await process_frame
		check(scene.wave_director.monsters.is_empty(), sid + " 等玩家确认才刷怪")
		var hud = scene.get_node("HudLayer/Hud")
		hud._refresh_wave_progress()
		check(hud._stage_label.text.contains(Data.STAGES[sid].name) and hud._stage_hint.visible, sid + " 准备阶段显示战术提示")
		if sid == "9-1":
			await capture("stage-implementation-preparation")
		scene.director.start_next_wave()
		check(scene.wave_director.w == 1, sid + " 手动开始第一波")
		hud._refresh_wave_progress()
		check(not hud._stage_hint.visible, sid + " 开战后收起战术正文")
		# 驱动真实最后一波的收尾，检查 controller 的胜利信号与结算接线。
		scene.wave_director.start_wave(Data.wave_count(sid))
		scene.wave_director.spawned = scene.wave_director.n
		scene.wave_director.monsters.clear()
		scene.wave_director._check_end()
		check(scene.wave_director.victory and scene.controller.over, sid + " 最后一波正确判胜")
		for child in scene.controller.get_children():
			if child.has_method("show_campaign_result"):
				check(child.visible and child._body_label.text.contains(Data.STAGES[sid].name), sid + " 真实结算显示当前关卡")
				child.queue_free()
		await process_frame
	scene.queue_free()
	paused = false
	Engine.time_scale = 1.0
	await process_frame
	print("Stage implementation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://art/_review/" + filename + ".png")
