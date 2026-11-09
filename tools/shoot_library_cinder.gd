extends SceneTree
##
## 图鉴·熔炉包段截图（非 CI · 窗口模式）
##   目的：第 81 张卡面（cinder 额外卡位 Pyroclasm）落到图鉴后，用实机截图确认
##   它不再是「纯文字卡条」，且与同包 10 张的插画密度、包色一致。
##   滚动位置由 _pack_blocks 里 cinder 块的真实矩形算，不靠手调像素。
## 运行：<godot> --path . --script res://tools/shoot_library_cinder.gd
## 产物：art/_review/smoke_library_cinder.png
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
		_menu.open()
	if _f == 30:
		_menu.show_library()
	if _f == 55:
		_scroll_to_cinder()
	if _f == 85:
		_shot("smoke_library_cinder.png")
	if _f >= 90:
		return true
	return false


func _scroll_to_cinder() -> void:
	var sc: ScrollContainer = _menu._lib_scroll
	if sc == null:
		push_error("[shot] 找不到 _lib_scroll")
		return
	for blk in _menu._pack_blocks:
		if String(blk["id"]) != "cinder":
			continue
		var cards: Array = blk["cards"]
		if cards.is_empty():
			continue
		var first: Control = cards[0]
		var last: Control = cards[cards.size() - 1]
		print("[shot] cinder 卡数 =", cards.size(),
			" 首张 y =", first.get_global_rect().position.y,
			" 末张 y =", last.get_global_rect().position.y)
		# 把 cinder 块的第一行顶到滚动区上方 40px 处
		var target := first.get_global_rect().position.y - sc.get_global_rect().position.y - 40.0
		sc.scroll_vertical = int(maxf(0.0, target + float(sc.scroll_vertical)))
		return
	push_error("[shot] 找不到 cinder 块")


func _shot(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://art/_review/" + fname)
	print("[shot] art/_review/", fname)
