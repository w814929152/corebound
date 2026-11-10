extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")
const Style := preload("res://scripts/ui/ui_style.gd")
const Packs := preload("res://scripts/data/card_packs.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var backdrops: Array = []
	for tier in Style.RARITY:
		var backdrop := Style.card_backdrop(tier)
		assert(backdrop == Style.card_backdrop(tier))
		assert(backdrop != null)
		backdrops.append(backdrop)
	assert(Style.card_backdrop("missing") == Style.card_backdrop("common"))
	var pack_textures: Array = []
	for pack in Packs.PACKS:
		var first_name := String(pack["cards"][0])
		var texture := Style.card_backdrop("common", first_name)
		assert(texture is ImageTexture)
		assert(not pack_textures.has(texture))
		pack_textures.append(texture)
		for card_name in pack["cards"]:
			assert(Style.card_pack_id(String(card_name)) == String(pack["id"]))
			assert(Style.card_backdrop("rare", String(card_name)) == texture)
	assert(Style.card_pack_id("unknown-card") == "core")
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
			await process_frame
			await process_frame
			await process_frame
			var viewport: Vector2 = root.get_visible_rect().size
			assert(is_equal_approx(shop.get_global_rect().get_center().x, viewport.x * 0.5))
			assert(shop._panel.get_theme_stylebox("panel") is StyleBoxEmpty)
			assert(not shop._title.is_visible_in_tree())
			assert(not shop._budget_row.is_visible_in_tree())
			assert(not shop._heavy_panel.is_visible_in_tree())
			var first_size: Vector2 = shop._slots[0].size
			shop._set_hovered_slot(0)
			for index in shop._slots.size():
				var tier: String = shop._slots[index].get_meta("rarity", "")
				if tier != "":
					var backdrop: TextureRect = shop._slot_art[index].get_meta("rarity_backdrop")
					var names: Array = scene.controller.runtime.offers
					assert(backdrop.texture == Style.card_backdrop(tier, String(names[index])))
					var box: StyleBoxFlat = shop._slots[index].get_theme_stylebox("panel")
					assert(box.border_color.is_equal_approx(Color(Style.rarity_color(tier), 0.85 if index == 0 else 0.48)))
			assert(first_size.y > first_size.x)
			for card in shop._slots:
				assert(absf(card.size.x - first_size.x) <= 1.0)
				assert(is_equal_approx(card.size.y, first_size.y))
				assert(card.get_global_rect().position.x >= shop.position.x)
				assert(card.get_global_rect().end.x <= shop.position.x + shop.size.x)

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
