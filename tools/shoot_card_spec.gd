extends SceneTree

## 2026-11-11 · 卡面实装验收截图（按「箭塔卡面实装说明」）
##   ① cards-spec-a.png：箭塔 + 铸造厂 + 冰川塔（短名 / 全幅插画）
##   ② cards-spec-b.png：长卡名 + 两行摘要（长枪塔 / 湮灭塔 / 咒术塔）
##   ③ cards-spec-hover.png：悬停详情
## 出图：output/imagegen/

const Space := preload("res://scripts/geo/space_model.gd")

var frame := 0
var scene: Node


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	Space.mode = 1
	Space.terrain_enabled = true
	Space.set_active_map("tri-fissure")
	scene = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 20:
		_show(["Arrow", "Foundry", "Glacier"])
	if frame == 60:
		_shot("cards-spec-a.png")
	if frame == 65:
		_show(["Lance", "Oblivion", "Hex"])
	if frame == 95:
		_shot("cards-spec-b.png")
	if frame >= 100 and frame < 150:
		# 悬停需要连续 0.4s 落在卡内（`_process` 累计 `_hover_time`），
		# 每帧把指针钉在首张卡中心，模拟真实悬停。
		var shop = scene.get_node("ShopLayer/ShopOverlay")
		shop._pointer = shop._slots[0].get_global_rect().get_center()
	if frame == 150:
		_shot("cards-spec-hover.png")
		return true
	return false


func _show(offers: Array) -> void:
	var controller = scene.controller
	controller.runtime.offers = offers
	scene.director.open_shop()
	var shop = scene.get_node("ShopLayer/ShopOverlay")
	shop._refresh_shop()
	shop._pointer = Vector2(-1000.0, -1000.0)
	shop._hover.clear()
	for i in shop._slots.size():
		print("[card] ", offers[i], " name=", shop._slot_name[i].text,
			" summary=", shop._slot_desc[i].text.replace("\n", " / "),
			" art=", shop._slot_art[i].get_meta("rarity_backdrop").texture.resource_path)


func _shot(fname: String) -> void:
	root.get_texture().get_image().save_png("res://output/imagegen/" + fname)
	print("[shot] ", fname)
