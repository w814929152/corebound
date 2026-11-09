extends SceneTree
##
## 实机截图冒烟（窗口模式 · 2026-11-09 卡面产线收官验收）
##   ① 主菜单 → 卡组图鉴：每个卡包 10 张卡，卡片左侧 96×96 卡面插画
##   ② 战斗商店 → 三个商品位：72px 插画带（按真实卡名填 ui_style.card_art()）
##   🔴 与 shoot_main_menu / shoot_rarity_smoke 的区别：只截卡面相关两帧，
##      并统计场景中「来自 art/2d/cards 的 TextureRect」数量作为接线硬证据；
##      输出到新文件名，不覆盖既有留档样张。
## 运行：<godot> --path . --script res://tools/shoot_card_art_smoke.gd
## 产物：art/_review/godot_smoke_library_cards.png / godot_smoke_shop_cards.png
##
const _MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")

var _f := 0
var _menu: CanvasLayer = null


func _initialize() -> void:
	_menu = _MainMenu.new()
	root.add_child(_menu)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		# open() 必须在 _ready（第 1 帧把 visible=false）之后调用
		_menu.open()
	if _f == 40:
		_menu.show_library()
	if _f == 60:
		_shot("godot_smoke_library_cards.png")
		print("[info] 图鉴页卡面纹理数 = ", _count_card_art(root), "（期望 80）")
	if _f == 65:
		_clear_root()
	if _f == 70:
		var ps: PackedScene = load("res://scenes/battle_shop.tscn")
		root.add_child(ps.instantiate())
	if _f == 85:
		var director := _find_with_method(root, "open_shop")
		if director != null:
			director.call("open_shop")
		else:
			print("[WARN] 未找到 open_shop —— 商店帧可能未开抽屉")
	if _f == 130:
		_shot("godot_smoke_shop_cards.png")
		print("[info] 商店页卡面纹理数 = ", _count_card_art(root), "（期望 3）")
	if _f >= 135:
		return true
	return false


func _count_card_art(n: Node) -> int:
	var c := 0
	if n is TextureRect:
		var tr := n as TextureRect
		if tr.texture != null and tr.texture.resource_path.contains("/art/2d/cards/"):
			c += 1
	for ch in n.get_children():
		c += _count_card_art(ch)
	return c


func _clear_root() -> void:
	for ch in root.get_children():
		root.remove_child(ch)
		ch.free()


func _find_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for ch in n.get_children():
		var r := _find_with_method(ch, m)
		if r != null:
			return r
	return null


func _shot(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://art/_review/" + fname)
	print("[shot] art/_review/", fname)
