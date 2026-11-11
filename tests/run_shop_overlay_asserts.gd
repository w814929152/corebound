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
			# 🆕 2026-11-10 参考图布局：预算读数从隐藏的独立行收进可见信息带（刷新/预算/模式徽标）
			assert(shop._info_row.is_visible_in_tree())
			assert(not shop._heavy_panel.is_visible_in_tree())
			var first_size: Vector2 = shop._slots[0].size
			# 🆕 v3：每位都有一层可染色描边（稀有度 / 悬停双通道）
			assert(shop._slot_edge.size() == shop._slots.size())
			shop._set_hovered_slot(0)
			for index in shop._slots.size():
				var tier: String = shop._slots[index].get_meta("rarity", "")
				if tier != "":
					var backdrop: TextureRect = shop._slot_art[index].get_meta("rarity_backdrop")
					var names: Array = scene.controller.runtime.offers
					var art := Style.card_art(String(names[index]))
					var full_illustration := Style.is_full_card_art(art)
					if full_illustration:
						assert(backdrop.texture == art)
						assert(shop._slot_art[index].texture == null)
						assert(backdrop.self_modulate == Color.WHITE)
					else:
						assert(backdrop.texture == Style.card_backdrop(tier, String(names[index])))
					assert(backdrop.get_meta("illustration_shade").visible)
					# 🆕 v3：标题位于米白信息区，价格位于右上费用胶囊；两者不得重叠或越框。
					var title_rect: Rect2 = shop._slot_name[index].get_global_rect()
					var price_rect: Rect2 = shop._slot_price_row[index].get_global_rect()
					var card_rect: Rect2 = shop._slots[index].get_global_rect()
					assert(title_rect.position.y > card_rect.get_center().y)
					# 🆕 v3 参考图口径：价格落在右上费用胶囊，不再要求位于标题下方。
					#   改为钉「不与标题重叠 + 在卡框内 + 位于卡片右半区」，判据更严。
					assert(not price_rect.intersects(title_rect))
					assert(price_rect.position.y >= card_rect.position.y)
					assert(price_rect.end.x <= card_rect.end.x)
					assert(price_rect.end.y <= card_rect.end.y)
					assert(price_rect.position.x > card_rect.position.x + card_rect.size.x * 0.5)
					assert(shop._slot_edge[index] is TextureRect)
					# 🆕 v3.1：稀有度第二通道 = 描边线宽（1/2/3），顶栏不再有角标节点
					var edge_tex: Texture2D = shop._slot_edge[index].texture
					var bw := clampi(int(Style.RARITY[tier]["bw"]), 1, 3)
					assert(edge_tex != null)
					assert(edge_tex.resource_path.ends_with("ui_card_edge_v3_%d.png" % bw))
					var box: StyleBoxFlat = shop._slots[index].get_theme_stylebox("panel")
					# 🆕 2026-11-10 v4「仅文字」：底色透明，稀有度由描边色 + 线宽承担
					assert(box.bg_color.a < 0.01)
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
	# 实际 GUI 派发：点锁头只切换锁定，点插画穿透到牌面且只买一次。
	td.open_shop()
	await process_frame
	await process_frame
	var intents := {"buy": 0, "lock": 0}
	td.buy_requested.connect(func(_index: int) -> void: intents["buy"] += 1)
	td.lock_toggled.connect(func(_index: int) -> void: intents["lock"] += 1)
	# 🆕 2026-11-11：1/2/3 快捷购买已移除 —— 商店开着时按数字键不得再发出 buy_requested
	for key in [KEY_1, KEY_2, KEY_3]:
		var key_ev := InputEventKey.new()
		key_ev.keycode = key
		key_ev.pressed = true
		td._unhandled_key_input(key_ev)
	assert(intents["buy"] == 0)
	var lock_point: Vector2 = shop._slot_lock[0].get_global_rect().get_center()
	_click(lock_point)
	assert(intents["lock"] == 1 and intents["buy"] == 0)
	_click(lock_point)
	assert(intents["lock"] == 2 and intents["buy"] == 0)
	scene.controller.runtime.scrap = 1000.0
	shop._refresh_shop()
	var art_point: Vector2 = shop._slot_art[0].get_global_rect().get_center()
	_click(art_point)
	assert(intents["buy"] == 1 and intents["lock"] == 2)
	scene.controller.runtime.scrap = 0.0
	shop._refresh_shop()
	_click(art_point)
	assert(intents["buy"] == 1)
	print("Shop overlay passed: 3 window sizes, PATH/RADIAL, buttons, placement, map/VFX positions and scale")
	paused = false
	quit()


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)

