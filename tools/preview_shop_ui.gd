extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.director.open_shop()
	for i in 12:
		await process_frame
	var shop = scene.get_node("ShopLayer/ShopOverlay")
	print("PANEL ", shop.get_global_rect())
	for slot in shop._slots:
		print("CARD ", slot.get_global_rect())
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://art/_review")
	var result := root.get_texture().get_image().save_png("res://art/_review/shop-portrait.png")
	quit(0 if result == OK else 1)
