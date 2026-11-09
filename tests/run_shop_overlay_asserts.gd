extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var td = scene.director
	var ml = scene.get_node("Battlefield/MonsterLayer")
	var fx = scene.get_node("Battlefield/VfxLayer")
	var bg = scene.get_node("Battlefield")
	var hud = scene.get_node("HudLayer/Hud")
	var shop = scene.get_node("ShopLayer/ShopOverlay")
	for viewport_size in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await process_frame
		for mode in [Space.Mode.PATH, Space.Mode.RADIAL]:
			Space.mode = mode
			td.close_shop()
			var baseline: Dictionary = ml._xform()
			var effect_origin: Vector2 = fx._to_screen(Vector2(28, 28))
			var point: Vector2 = ml.world_to_screen(Vector2(6, 33))
			var background_width: float = bg._battlefield_width()
			assert(hud._shop_btn.visible)
			hud._shop_btn.pressed.emit()
			assert(shop.visible and not hud._shop_btn.visible)
			assert(ml._xform() == baseline)
			assert(fx._to_screen(Vector2(28, 28)).is_equal_approx(effect_origin))
			assert(bg._battlefield_width() == background_width)
			assert(ml.world_to_screen(Vector2(6, 33)).is_equal_approx(point))
			assert(ml.screen_to_world_position(point).is_equal_approx(Vector2(6, 33)))
			td.enter_placement()
			assert(not shop.visible)
			assert(ml._xform() == baseline)
			td.exit_placement(false)
			assert(ml._xform() == baseline)
			td.close_shop()
			assert(ml._xform() == baseline)
	print("Shop overlay passed: 3 window sizes, PATH/RADIAL, buttons, placement, map/VFX positions and scale")
	paused = false
	quit()
