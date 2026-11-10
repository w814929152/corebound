extends SceneTree

const TD := preload("res://scripts/ui/time_director.gd")
const SC := preload("res://scripts/gameplay/shop_controller.gd")
const WD := preload("res://scripts/gameplay/wave_director.gd")
const TSM := preload("res://scripts/engine/time_state_machine.gd")
const Grid := preload("res://scripts/geo/build_grid.gd")
const Layer := preload("res://scripts/ui/monster_layer.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var td = TD.new()
	root.add_child(td)
	var sc = SC.new()
	root.add_child(sc)
	sc.setup()
	sc.bind_director(td)
	var wd = WD.new()
	root.add_child(wd)
	wd.bind_director(td)
	sc.bind_wave_director(wd)
	sc.start_new_run()
	assert(td.sm.state == TSM.State.SAFE_WINDOW)
	assert(td.sm.wave == 0)
	assert(wd.state == WD.State.IDLE)
	wd.advance(120.0)
	assert(wd.spawned == 0)
	var rt = sc.runtime
	var slot := -1
	for i in rt.offers.size():
		if rt._card_kind(String(rt.offers[i])) == "tower":
			slot = i
			break
	assert(slot >= 0 and rt.buy(slot))
	assert(rt.begin_placement(0))
	assert(rt.confirm_placement_at(Vector2(6, 33)))
	var offers: Array = rt.offers.duplicate()
	var gold: float = rt.scrap
	td.start_next_wave()
	assert(td.sm.wave == 1)
	assert(wd.state != WD.State.IDLE)
	assert(rt.offers == offers and rt.scrap == gold)
	assert(rt.player.towers.size() == 1)
	wd.advance(2.0)
	assert(wd.spawned > 0)
	sc.start_new_run()
	assert(td.sm.wave == 0 and wd.state == WD.State.IDLE)
	assert(sc.runtime.player.towers.is_empty())
	test_recovery_and_relocation(sc, td, wd)
	print("Preparation passed: no spawn before confirmation, purchase/place, first wave, restart")
	paused = false
	quit()

func test_recovery_and_relocation(sc, td, wd) -> void:
	var runtime = sc.runtime
	runtime.preparation_actions_enabled = true
	for position in [Vector2(6, 33), Vector2(10, 33)]:
		runtime.pending.append("Arrow")
		runtime.pending_cost.append(0.0)
		assert(runtime.begin_placement(0))
		assert(runtime.confirm_placement_at(position))
	var tower = runtime.player.towers[0]
	var other = runtime.player.towers[1]
	tower.h = 3
	tower.disabled = true
	tower.hp = 0.0
	other.hp = 1.0
	runtime.player.core_hp = 200.0
	wd.core_hp = 200.0
	var scrap: float = runtime.scrap
	td.wave_end(1)
	assert(not tower.disabled and tower.hp == tower.hp_max and tower.hp > 0.0)
	assert(other.hp == other.hp_max)
	assert(runtime.player.core_hp == runtime.player.core_hp_max)
	assert(wd.core_hp == runtime.player.core_hp)
	assert(runtime.scrap >= scrap and tower.h == 3)
	scrap = runtime.scrap
	var origin: Vector2 = runtime.geo.slots[tower.slot]
	var destination := Grid.snap(Vector2(14, 33))
	assert(not runtime.relocate_tower(tower.slot, Grid.core()))
	assert(not runtime.relocate_tower(tower.slot, Vector2(10000, 10000)))
	assert(not runtime.relocate_tower(tower.slot, runtime.geo.slots[other.slot]))
	assert(not runtime.relocate_tower(-1, destination))
	assert(runtime.geo.slots[tower.slot] == origin)
	assert(runtime.relocate_tower(tower.slot, destination))
	assert(runtime.geo.slots[tower.slot] == destination and tower.h == 3)
	assert(runtime.player.towers.size() == 2 and runtime.scrap == scrap)
	var empty_position := Grid.snap(Vector2(18, 33))
	var empty_slot: int = runtime.geo.slots.size()
	runtime.geo.slots.append(empty_position)
	assert(runtime.relocate_tower(tower.slot, empty_position))
	assert(runtime.geo.slots[empty_slot] == destination)
	var layer = Layer.new()
	layer.visible = false
	layer.controller = sc
	layer.bind_time_director(td)
	root.add_child(layer)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = layer.world_to_screen(empty_position)
	press.global_position = press.position
	layer._unhandled_input(press)
	assert(layer._moving_slot == tower.slot)
	var motion := InputEventMouseMotion.new()
	motion.position = layer.world_to_screen(origin)
	layer._input(motion)
	assert(layer._move_dragging)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	layer._input(release)
	assert(runtime.geo.slots[tower.slot] == origin and layer._moving_slot == -1)
	assert(not layer._begin_tower_drag(layer.world_to_screen(Grid.core())))
	assert(layer._begin_tower_drag(layer.world_to_screen(origin)))
	motion.position = layer.world_to_screen(destination)
	layer._input(motion)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	layer._input(escape)
	assert(layer._moving_slot == -1 and runtime.geo.slots[tower.slot] == origin)
	assert(layer._begin_tower_drag(layer.world_to_screen(origin)))
	td.wave_start(2)
	assert(layer._moving_slot == -1)
	assert(not runtime.relocate_tower(tower.slot, destination))
	tower.hp = 1.0
	assert(not runtime.recover_preparation_buildings() and tower.hp == 1.0)
	td.wave_end(2)
	assert(tower.hp == tower.hp_max)
	td.set_external_pause(true)
	assert(not runtime.relocate_tower(tower.slot, destination))
	td.set_external_pause(false)
	sc.over = true
	runtime.player.core_hp = 0.0
	tower.disabled = true
	tower.hp = 0.0
	td.wave_end(3)
	assert(tower.disabled and tower.hp == 0.0 and runtime.player.core_hp == 0.0)
	layer.queue_free()
	print("Preparation recovery/relocation passed: full HP, core sync, drag, occupancy, invalid targets and combat guards")
