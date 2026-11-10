extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")
const Grid := preload("res://scripts/geo/build_grid.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1600, 900)
	Space.mode = Space.Mode.RADIAL
	Space.terrain_enabled = true
	Space.set_active_map("tri-fissure")
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	scene.auto_start_run = false
	root.add_child(scene)
	await process_frame
	scene.controller.start_new_run()
	scene.director.close_shop()
	scene.get_node("TutorialLayer/TutorialOverlay")._on_skip_pressed()
	var rt = scene.controller.runtime
	if not rt.buy(0) or not rt.begin_placement(0):
		quit(1)
		return
	if not rt.confirm_placement_at(Grid.cell(3,0)):
		quit(1)
		return
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art/_review/core-base-in-game.png")
	# Second preview keeps a card pending to show the exact reserved grid.
	rt.scrap = 100.0
	rt.buy(0)
	rt.begin_placement(0)
	scene.director.enter_placement()
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art/_review/core-base-clearance.png")
	quit()
