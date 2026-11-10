extends SceneTree

const Camera := preload("res://scripts/ui/battlefield_camera.gd")
const Space := preload("res://scripts/geo/space_model.gd")

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
	for mode in ["close", "overview"]:
		if mode == "overview":
			Camera.zoom = Camera.MIN_ZOOM
		for i in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art/_review/spawn-preview-" + mode + ".png")
	quit()
