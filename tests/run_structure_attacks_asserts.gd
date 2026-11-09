extends SceneTree
const WD := preload("res://scripts/gameplay/wave_director.gd")
const RT := preload("res://scripts/gameplay/shop_runtime.gd")
const PS := preload("res://scripts/engine/player_state.gd")
const Space := preload("res://scripts/geo/space_model.gd")
const MD := preload("res://scripts/data/monster_data.gd")
const Camera := preload("res://scripts/ui/battlefield_camera.gd")
const Boot := preload("res://scripts/ui/boot.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func battle(with_tower: bool = false):
	var rt = RT.new()
	rt.setup("B",1234)
	if with_tower:
		var point := Space.radial_pos_of_t(5.0,1.0,0.0)
		var slot: int = rt.geo.add_slot(point)
		rt.player.towers.append(PS.make_tower(slot,"Foundry",1))
	var d := WD.new()
	d.structure_attacks_enabled = true
	d.bind_runtime(rt)
	d.start_wave(1)
	d.debug_set_monsters([5.0 if with_tower else 0.01],10000.0)
	return d

func run() -> void:
	Space.mode = Space.Mode.RADIAL
	Space.terrain_enabled = true
	Space.set_active_map("tri-fissure")
	var d = battle(true)
	var tower = d.player.towers[0]
	var maximum := float(tower.hp)
	d.advance(0.1)
	check(d.monsters[0].state==WD.MState.AGGRO_TOWER and tower.hp<maximum,"第一波附近怪物即能锁塔并扣血")
	var stopped := float(d.monsters[0].t_remain)
	var hp := float(tower.hp)
	d.advance(0.1)
	check(is_equal_approx(d.monsters[0].t_remain,stopped) and tower.hp<hp,"攻塔时停止前进，持续造成伤害")
	check(is_equal_approx(hp-tower.hp,MD.STRUCTURE_ATTACK_DPS*MD.M_DPS.Swarm*0.1),"伤害按秒结算并应用原型倍率")
	d.monsters[0].frozen_remaining = 1.0
	hp = tower.hp
	d.advance(0.1)
	check(is_equal_approx(tower.hp,hp),"冻结时无法攻塔")
	d.monsters[0].frozen_remaining = 0.0
	tower.hp = 0.1
	d.advance(0.1)
	check(tower.disabled and is_zero_approx(tower.hp),"防御塔血量归零进入停机")
	d.advance(0.1)
	check(d.monsters[0].state==WD.MState.MARCHING and d.monsters[0].target_slot==-1,"目标停机后解除锁定")
	d.advance(0.1)
	check(d.monsters[0].t_remain<stopped,"停机后继续向核心推进")
	d.free()
	d = battle(true)
	d.monsters[0].sapper = true
	d.geo.slots[d.player.towers[0].slot] = Space.RADIAL_CORE+Vector2(-60,0)
	hp = d.player.towers[0].hp
	d.advance(0.1)
	check(d.monsters[0].state==WD.MState.MARCHING and d.player.towers[0].hp==hp,"锁塔精英不能隔图攻击")
	d.free()
	d = battle()
	var initial := float(d.core_hp)
	d.advance(0.1)
	check(d.monsters.size()==1 and d.monsters[0].state==WD.MState.AGGRO_CORE,"接触核心后保留怪物并进入攻核状态")
	check(d.leaked_count==0 and d.core_hp<initial,"持续攻核替代一次性漏怪扣血")
	check(d.player.core_hp==d.core_hp,"核心生命与 HUD 读取来源同步")
	var position: Vector2 = d.monsters[0].pos(d.v0_)
	hp = d.core_hp
	d.advance(0.1)
	check(d.monsters[0].pos(d.v0_)==position and d.core_hp<hp,"攻核时保持位置并连续扣血")
	d.monsters[0].frozen_remaining = 1.0
	hp = d.core_hp
	d.advance(0.1)
	check(d.core_hp==hp,"冻结时无法攻核")
	d.monsters[0].frozen_remaining = 0.0
	d.monsters[0].hp = 0.0
	d.advance(0.1)
	check(d.monsters.is_empty() and d.core_hp==hp and d.state==WD.State.SAFE_WINDOW,"攻核怪死亡后停止伤害并正常结束波次")
	d.free()
	d = battle()
	var losses: Array = []
	d.run_lost.connect(func(wave): losses.append(wave))
	d.core_hp = 0.1
	d.player.core_hp = 0.1
	d.advance(0.1)
	d.advance(1.0)
	check(d.run_failed and is_zero_approx(d.core_hp) and losses.size()==1,"核心归零仅触发一次失败")
	d.free()
	# 从接触圈外进入，检查不会穿过核心或提前漏掉。
	d = battle()
	var radius := Space.BattlefieldMaps.entry_radius(Space.active_map_id,0.0)
	d.monsters[0].t_remain = Space.T_REACH*(MD.CORE_ATTACK_R+0.3)/radius
	d.advance(0.1)
	check(is_equal_approx(d.monsters[0].pos(d.v0_).distance_to(Space.RADIAL_CORE),MD.CORE_ATTACK_R),"行进怪停在核心攻击接触圈")
	check(not d._check_end(),"仍有攻核怪时不会提前结算胜利")
	var slot: int = d.geo.add_slot(Space.RADIAL_CORE+Vector2(7,0))
	d.player.towers.append(PS.make_tower(slot,"Foundry",1))
	d._init_tower_hp()
	hp = d.core_hp
	d.advance(0.1)
	check(d.monsters[0].state==WD.MState.AGGRO_TOWER and d.core_hp==hp,"核心附近新建塔可吸引怪物攻击")
	d.free()
	# 关闭新模式保留原先的漏怪模拟。
	d = battle()
	d.structure_attacks_enabled = false
	d.advance(0.1)
	check(d.monsters.is_empty() and d.leaked_count==1,"旧模拟开关关闭时仍按原规则漏怪")
	d.free()
	if DisplayServer.get_name()!="headless":
		await preview_scene()
	Space.terrain_enabled = false
	Camera.reset()
	print("Structure attacks: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func preview_scene() -> void:
	root.size = Vector2i(1600,900)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	scene.auto_start_run = false
	root.add_child(scene)
	var d = scene.wave_director
	d.structure_attacks_enabled = true
	d.stage_waves_enabled = true
	d.set_stage("0-1")
	scene.controller.start_new_run()
	scene.director.close_shop()
	scene.get_node("TutorialLayer/TutorialOverlay")._on_skip_pressed()
	var rt = scene.controller.runtime
	var point := Space.RADIAL_CORE+Vector2(22,0)
	rt.pending = ["Foundry"]
	rt.pending_cost = [12.0]
	rt.begin_placement(0)
	rt.confirm_placement_at(point)
	scene.director.start_next_wave()
	d.set_process(false)
	var radius := Space.BattlefieldMaps.entry_radius(Space.active_map_id,0.0)
	d.debug_set_monsters([Space.T_REACH*25.0/radius,Space.T_REACH*3.1/radius],1000.0)
	d.advance(0.5)
	var ml = scene.get_node("Battlefield/MonsterLayer")
	await process_frame
	check(d.monsters.size()==2 and d.core_hp<1000.0 and rt.player.towers[0].hp<rt.player.towers[0].hp_max,"实机场景同时显示攻塔与攻核")
	ml._vfx_t = 0.0
	ml.queue_redraw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art/_review/monster-structure-attacks.png")
	scene.queue_free()
	paused = false
	await process_frame
