extends SceneTree

const Boot := preload("res://scripts/ui/boot.gd")
const Battle := preload("res://scenes/battle_shop.tscn")
const Campaign := preload("res://scripts/gameplay/campaign.gd")
const CampaignData := preload("res://scripts/data/campaign_data.gd")
const Shop := preload("res://scripts/gameplay/shop_runtime.gd")
const Space := preload("res://scripts/geo/space_model.gd")
const Save := preload("res://scripts/gameplay/run_save.gd")
const RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const Profiles := preload("res://scripts/gameplay/profile_store.gd")

var failed := 0
var rewards := 0
var path := "user://run-save-test-%d.save" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("run")


func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failed += 1


func run() -> void:
	RunMeta.set_save_enabled(false)
	Space.mode = Space.Mode.RADIAL
	Space.terrain_enabled = true
	var battle = Battle.instantiate()
	battle.auto_start_run = false
	root.add_child(battle)
	var boot = Boot.new()
	boot._bs = battle
	boot._profiles = Profiles.new(path)
	boot._profiles.put(0, {"campaign": Campaign.new().progress_snapshot(), "meta": {}, "run": {}}, true)
	boot._load_active_profile()
	boot._main_menu = Boot.MainMenu.new()
	root.add_child(boot._main_menu)
	boot._main_menu.resume_requested.connect(boot._on_resume_run)
	boot._replace_dialog = Boot.Confirm.new()
	root.add_child(boot._replace_dialog)
	boot._replace_dialog.cancelled.connect(boot._open_main_menu)
	boot._stage_exit = Boot.StageExit.new()
	boot._stage_exit.director = battle.director
	boot._stage_exit.can_save = boot._can_save_run
	boot._stage_exit.save_requested.connect(boot._on_save_and_exit)
	root.add_child(boot._stage_exit)
	battle.controller.run_finished.connect(func(_won, _wave): rewards += 1)
	var overlay = boot._stage_exit
	var runtime = battle.controller.runtime

	boot._open_main_menu()
	check("no Continue before the first save", not boot._main_menu._menu_buttons[4].is_visible_in_tree())
	boot._begin_run(["core"])
	runtime.scrap = 1000.0
	check("buy tower", runtime.buy(0))
	var grid_position := Vector2.ZERO
	for x in range(4, 20):
		if runtime.placement_mode_at(Vector2(x, 0)).get("mode") == "place":
			grid_position = Vector2(x, 0)
			break
	check("place tower", runtime.begin_placement(0) and runtime.confirm_placement_at(grid_position))
	check("buy spare card", runtime.buy(0))
	check("reroll and lock", runtime.reroll() and runtime.toggle_lock(1))
	var tower = runtime.player.towers[0] if not runtime.player.towers.is_empty() else null
	if tower != null:
		tower.range_facing = 0.5
		tower.bounty_progress = 4

	# Exercise a write failure through the same modal, then save to a valid location.
	boot._profiles.load_error = ERR_FILE_CANT_WRITE
	overlay.request_exit()
	check("Save and Exit available in preparation", overlay._save_button.visible)
	overlay._save_button.pressed.emit()
	check("write failure keeps the run paused and the modal open",
		overlay.confirming and not battle.controller.over and "失败" in overlay._message.text)
	boot._profiles.load_error = OK
	overlay._save_button.pressed.emit()
	var first: Dictionary = boot._profiles.get_slot(0).run
	check("save exits to main menu and records no result", not first.is_empty()
		and battle.controller.over and boot._main_menu.visible and rewards == 0)
	check("Continue displays the stage and next wave",
		boot._main_menu._menu_buttons[4].is_visible_in_tree() and "第 1 /" in boot._main_menu._save_status.text)
	var reloaded := Profiles.new(path)
	reloaded.load_profiles(false)
	check("existing slot persists to disk", reloaded.get_slot(0).run == first)
	boot._on_main_start()
	check("new challenge asks before removing save", boot._replace_dialog.visible and FileAccess.file_exists(path))
	boot._replace_dialog._on_cancel_pressed()
	check("cancel leaves Continue available", boot._main_menu._menu_buttons[4].is_visible_in_tree())
	if first.is_empty():
		finish(boot, battle)
		return

	# Reset the session's gameplay objects before restoring from disk.
	battle.controller.start_new_run()
	boot._load_active_profile()
	boot._main_menu._activate(4)
	check("Continue opens the saved stage in preparation", not boot._main_menu.visible
		and overlay.active and not battle.controller.over and battle.director.sm.wave == 0 and paused
		and battle.wave_director.stage_id == first.stage
		and Space.active_map_id == CampaignData.resolve_map_id(first.stage))
	check("restored state round-trips exactly", Save.capture(runtime, first.stage,
		Shop.active_pack_ids(), 1, first.escalation) == first)
	check("Continue consumes the suspended slot", boot._profiles.get_slot(0).run.is_empty())
	battle.director.start_next_wave()
	check("starting restored W1 keeps its opening shop",
		runtime.wave == 1 and runtime.offers == first.shop.offers and runtime.rng.mt == first.rng)
	overlay.request_exit()
	check("Save and Exit hidden during battle", not overlay._save_button.visible)
	overlay.cancel_exit()
	battle.wave_director._end_wave()

	overlay.request_exit()
	overlay._save_button.pressed.emit()
	var second: Dictionary = boot._profiles.get_slot(0).run
	check("save after combat records the next wave", second.get("next_wave") == 2)
	if not second.is_empty():
		boot._main_menu._activate(4)
		check("restored wave-end shop retains its current offers", runtime.offers == second.shop.offers)
		battle.director.start_next_wave()
		check("W2 deals the next shop without replaying W1",
			battle.wave_director.w == 2 and runtime.wave == 2 and runtime.rng.mti != second.rng_index)

	check_profiles(boot, second)

	var corrupt := FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_var({"version": -1})
	corrupt.close()
	var broken := Profiles.new(path)
	broken.load_profiles(false)
	check("incompatible profile files cannot be overwritten",
		broken.load_error == ERR_FILE_CORRUPT and broken.erase(0) == ERR_FILE_CORRUPT)
	finish(boot, battle)


func check_profiles(boot, checkpoint: Dictionary) -> void:
	boot._profile_overlay = Boot.ProfileOverlay.new()
	root.add_child(boot._profile_overlay)
	boot._profile_overlay.selected.connect(boot._on_profile_selected)
	boot._profile_overlay.save_requested.connect(boot._on_profile_saved)
	boot._profile_overlay.delete_requested.connect(boot._on_profile_deleted)
	boot._profile_overlay.closed.connect(boot._open_main_menu)

	RunMeta.set_save_enabled(true)
	boot._on_run_finished(true, 10)
	boot._set_suspended_run(checkpoint)
	boot._open_main_menu()
	boot._open_profiles()
	var overlay = boot._profile_overlay
	check("three game save slots are displayed", overlay._rows.get_child_count() == 3)
	overlay._ask_save(1, false)
	var source: Dictionary = boot._profiles.get_slot(0)
	check("manual save copies progression and checkpoint to another slot", boot._profiles.get_slot(1) == source)
	overlay.selected.emit(2)
	check("creating an empty slot starts a clean profile", boot._profiles.active == 2
		and boot._campaign.ember() == 0 and RunMeta.runs() == 0 and boot._suspended_run.is_empty())
	boot._on_run_finished(false, 2)
	check("automatic saves affect only the selected profile",
		boot._profiles.get_slot(2).campaign.ember == boot._campaign.ember()
		and boot._profiles.get_slot(2).meta.runs == 1
		and boot._profiles.get_slot(0) == source and boot._profiles.get_slot(1) == source)
	boot._open_profiles()
	overlay._ask_save(1, true)
	check("overwriting another slot requires confirmation", overlay._confirm.visible
		and boot._profiles.get_slot(1) == source)
	overlay._confirm._on_cancel_pressed()
	check("cancelling overwrite preserves destination", boot._profiles.get_slot(1) == source)
	overlay._ask_save(1, true)
	overlay._confirm._on_confirm_pressed()
	check("confirmed overwrite replaces only its destination",
		boot._profiles.get_slot(1) == boot._profiles.get_slot(2) and boot._profiles.get_slot(0) == source)
	overlay.selected.emit(0)
	boot._open_profiles()
	overlay._ask_save(1, true)
	overlay._confirm._on_confirm_pressed()
	overlay.selected.emit(1)
	check("loading a profile switches campaign, run history and checkpoint",
		boot._profiles.active == 1 and boot._campaign.is_cleared("0-1")
		and RunMeta.wins() == 1 and boot._suspended_run == checkpoint)
	boot._open_profiles()
	overlay._ask_delete(1)
	check("deletion requires confirmation", overlay._confirm.visible and not boot._profiles.get_slot(1).is_empty())
	overlay._confirm._on_confirm_pressed()
	var reloaded := Profiles.new(path)
	reloaded.load_profiles(false)
	check("deleting the active slot clears selection and leaves other saves intact",
		reloaded.active == -1 and reloaded.get_slot(1).is_empty() and reloaded.get_slot(0) == source
		and not reloaded.get_slot(2).is_empty() and boot._campaign.ember() == 0 and RunMeta.wins() == 0)


func finish(boot, battle) -> void:
	if boot._profile_overlay != null:
		boot._profile_overlay.queue_free()
	Save.clear(path)
	boot._stage_exit.queue_free()
	boot._main_menu.queue_free()
	boot._replace_dialog.queue_free()
	battle.queue_free()
	boot.free()
	await process_frame
	paused = false
	quit(0 if failed == 0 else 1)
