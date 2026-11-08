extends SceneTree
##
## 实机截图冒烟（非 CI · 窗口模式）：主菜单 keyart v1 背景目检
##   ① 菜单页（标题 + 三入口 + keyart 背景）
##   ② 图鉴页（背景不应抢卡片网格）
## 运行：<godot> --path . --script res://tools/shoot_main_menu.gd
## 产物：art/_review/smoke_menu_keyart.png / smoke_menu_library.png
##
const _MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")

var _f := 0
var _menu: CanvasLayer = null


func _initialize() -> void:
	_menu = _MainMenu.new()
	root.add_child(_menu)
	# 🔴 open() 必须在 _ready（第 1 帧把 visible=false）之后调用，否则会被覆盖回不可见


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_menu.open()
	if _f == 40:
		_shot("smoke_menu_keyart.png")
	if _f == 45:
		_menu.show_library()
	if _f == 70:
		_shot("smoke_menu_library.png")
		print("[info] keyart 生效 =", _menu._keyart)
	if _f >= 75:
		return true
	return false


func _shot(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://art/_review/" + fname)
	print("[shot] art/_review/", fname)
