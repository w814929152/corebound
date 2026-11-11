extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")
var scene: Node
var frame := 0

func _initialize() -> void:
	DisplayServer.window_set_title("Corebound — 箭塔卡面预览")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	Space.mode = 1
	Space.terrain_enabled = true
	Space.set_active_map("tri-fissure")
	scene = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scene)

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 20:
		scene.controller.runtime.offers = ["Arrow", "Frost", "Oblivion"]
		scene.director.open_shop()
		scene.get_node("ShopLayer/ShopOverlay")._refresh_shop()
	return false
