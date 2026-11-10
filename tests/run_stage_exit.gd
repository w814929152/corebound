extends SceneTree
const Boot = preload("res://scripts/ui/boot.gd")
const Battle = preload("res://scenes/battle_shop.tscn")
const Exit = preload("res://scripts/ui/stage_exit_overlay.gd")
const Campaign = preload("res://scripts/gameplay/campaign.gd")
class Map extends CanvasLayer:
	var opened := false
	func open(_campaign) -> void:
		opened = true
var failed := 0
var rewards := 0
func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failed += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var bs = Battle.instantiate()
	bs.auto_start_run = false
	root.add_child(bs)
	var boot = Boot.new()
	boot._bs = bs
	boot._campaign = Campaign.new()
	var map = Map.new()
	root.add_child(map)
	boot._stage_select = map
	var overlay = Exit.new()
	overlay.director = bs.director
	root.add_child(overlay)
	boot._stage_exit = overlay
	overlay.exit_confirmed.connect(boot._on_stage_exit)
	bs.controller.run_finished.connect(func(_won, _wave): rewards += 1)
	check("hidden before level", not overlay.visible)
	boot._begin_run(["core"])
	check("available during preparation", overlay.visible and overlay.active)
	overlay.request_exit()
	check("confirmation pauses", overlay.confirming and paused and bs.director.external_pause)
	var budget = bs.director.sm.budget_left
	bs.director._process(1.0)
	check("pause preserves budget", bs.director.sm.budget_left == budget)
	overlay.cancel_exit()
	check("cancel restores safe-window pause", not overlay.confirming and not bs.director.external_pause and paused)
	bs.director.start_next_wave()
	check("combat starts", not paused)
	overlay.request_exit()
	var acc = bs.wave_director.acc
	bs.wave_director._process(1.0)
	check("confirmation stops combat", paused and bs.wave_director.acc == acc)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._input(esc)
	check("escape resumes combat", not overlay.confirming and not paused)
	overlay.request_exit()
	overlay.confirm_exit()
	check("exit returns to map and stops run", map.opened and bs.controller.over and bs.wave_director.state == bs.wave_director.State.IDLE and not overlay.visible)
	check("abandon does not award result", rewards == 0 and bs.controller.campaign_result.is_empty())
	boot._begin_run(["core"])
	check("next run resets abandonment", not bs.controller.over and overlay.active and not bs.director.external_pause and bs.wave_director.w == 1)
	overlay.queue_free()
	map.queue_free()
	bs.queue_free()
	boot.free()
	await process_frame
	paused = false
	quit(0 if failed == 0 else 1)
