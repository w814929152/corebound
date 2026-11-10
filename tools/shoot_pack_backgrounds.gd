extends SceneTree

const Style := preload("res://scripts/ui/ui_style.gd")
const Packs := preload("res://scripts/data/card_packs.gd")
const Text := preload("res://scripts/data/card_text.gd")
const Battle := preload("res://scripts/ui/battle_theme.gd")

var frame := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/imagegen")
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = Vector2i(1600, 1000)
	var background := ColorRect.new()
	background.color = Style.C_BG
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for index in Packs.PACKS.size():
		var pack: Dictionary = Packs.PACKS[index]
		var card_name := String(pack["cards"][1])
		var card := PanelContainer.new()
		card.position = Vector2(30 + (index % 4) * 395, 25 + (index / 4) * 475)
		card.size = Vector2(365, 450)
		card.add_theme_stylebox_override("panel", Battle.card())
		root.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 12)
		card.add_child(column)
		column.add_child(Style.label(String(pack["name"]), 24, Style.pack_color(String(pack["id"]))))
		var art_frame := PanelContainer.new()
		art_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		column.add_child(art_frame)
		var backdrop := TextureRect.new()
		backdrop.texture = Style.card_backdrop(Text.rarity(card_name), card_name)
		backdrop.self_modulate = Style.CARD_BACKDROP_TINT
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_frame.add_child(backdrop)
		var art := TextureRect.new()
		art.texture = Style.card_art(card_name)
		art.custom_minimum_size = Vector2(0, 340)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_frame.add_child(art)
		column.add_child(Style.label(Text.display_name(card_name), 20, Style.C_TEXT))

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 40:
		root.get_texture().get_image().save_png("res://output/imagegen/pack-backgrounds-in-engine.png")
		return true
	return false
