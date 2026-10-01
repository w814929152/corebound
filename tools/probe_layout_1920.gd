extends SceneTree
##
## 一次性布局探针 —— Q-S3-C 落地（视口 1920×1080）后，骨架场景的**真实像素**实测。
##
## 🔴 探针 = 一次性调研工具：不进自测、不进产品（control-manifest §6 建议 2）。
##    引擎升级 / 视口再变更时先重跑本探针再改文档。
##
## 跑法（窗口模式，证据重定向到 docs/phase3/slice3-layout-1920-probe.log）：
##   <godot> --path D:/roguedemo --script res://tools/probe_layout_1920.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var scene: Node = load("res://scenes/battle_shop.tscn").instantiate()
	scene.name = "BattleShop"
	root.add_child(scene)
	await process_frame
	await process_frame

	var vp: Rect2 = get_root().get_visible_rect()
	print("视口 visible_rect        = ", vp.size)
	var shop: Control = scene.get_node("ShopLayer/ShopOverlay")
	print("ShopOverlay offset_left  = ", shop.get_offset(SIDE_LEFT),
		"  → 宽 = ", -shop.get_offset(SIDE_LEFT))
	print("ShopOverlay size         = ", shop.size)
	var panel: Control = shop.get_child(0)
	print("  └ ShopPanel size       = ", panel.size)
	var hud: Control = scene.get_node("HudLayer/Hud")
	print("Hud size                 = ", hud.size)
	var hp: Control = scene.get_node("CoreHpLayer/CoreHpBar")
	print("CoreHpBar size（穿透条）  = ", hp.size)
	var bf: Node2D = scene.get_node("Battlefield")
	print("Battlefield 视口尺寸     = ", bf._viewport_size)

	quit(0)
