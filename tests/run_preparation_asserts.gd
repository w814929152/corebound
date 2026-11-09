extends SceneTree

const TD := preload("res://scripts/ui/time_director.gd")
const SC := preload("res://scripts/gameplay/shop_controller.gd")
const WD := preload("res://scripts/gameplay/wave_director.gd")
const TSM := preload("res://scripts/engine/time_state_machine.gd")

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
	print("Preparation passed: no spawn before confirmation, purchase/place, first wave, restart")
	paused = false
	quit()
