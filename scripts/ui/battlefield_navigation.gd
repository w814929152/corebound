extends CanvasLayer
## 战场镜头输入与小型控制条。只改变视角，不改变游戏时钟或放置状态。
const Camera := preload("res://scripts/ui/battlefield_camera.gd")
const Space := preload("res://scripts/geo/space_model.gd")
const Battle := preload("res://scripts/ui/battle_theme.gd")

var battle: Node
var _bar: HBoxContainer
var _percent: Label
var _drag_button := 0
var _drag_origin := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _dragging := false
var _player_id := 0
var _last_transform: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	Camera.reset()
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation",6)
	add_child(_bar)
	_add_button("−",func(): _zoom(1.0/1.15,_viewport_size()*0.5),"缩小地图")
	_percent = Label.new()
	_percent.custom_minimum_size.x = 54
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_percent)
	_add_button("+",func(): _zoom(1.15,_viewport_size()*0.5),"放大地图")
	_add_button("总览",func(): Camera.overview(); _refresh(),"查看完整地图")
	_add_button("回到核心",func(): reset_view(),"恢复初始视角 · F")
	get_viewport().size_changed.connect(_refresh)
	if battle != null and battle.controller != null:
		battle.controller.run_changed.connect(_on_run_changed)
	_refresh()

func _add_button(caption: String, action: Callable, hint: String) -> void:
	var button := Button.new()
	button.text = caption
	button.tooltip_text = hint
	button.custom_minimum_size = Vector2(40,38)
	Battle.button(button)
	button.pressed.connect(action)
	_bar.add_child(button)

func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _on_run_changed() -> void:
	var player = battle.controller.runtime.player
	if player != null and player.get_instance_id() != _player_id:
		_player_id = player.get_instance_id()
		reset_view()

func reset_view() -> void:
	_end_drag()
	Camera.reset()
	_refresh()

func _refresh() -> void:
	if _bar == null:
		return
	_bar.visible = Space.uses_terrain()
	_bar.position = Vector2(maxf(16.0,_viewport_size().x-370.0),_viewport_size().y-239.0)
	_percent.text = "%d%%" % int(round(Camera.zoom*100.0))
	var current := Camera.terrain_transform(_viewport_size())
	if battle != null:
		var vfx := battle.get_node("Battlefield/VfxLayer")
		if not _last_transform.is_empty() and Space.uses_terrain():
			vfx.reproject_camera(_last_transform,current)
		for path in ["Battlefield/MonsterLayer","Battlefield/TowerLevelLayer","Battlefield/VfxLayer"]:
			battle.get_node(path).queue_redraw()
		if battle.tower_backpack != null:
			battle.tower_backpack.queue_redraw()
	_last_transform = current

func _zoom(factor: float, anchor: Vector2) -> void:
	Camera.zoom_at(factor,anchor,_viewport_size())
	_refresh()

func _can_navigate(point: Vector2) -> bool:
	if not Space.uses_terrain() or battle == null or battle.controller.over:
		return false
	if not Camera.view_rect(_viewport_size()).has_point(point):
		return false
	if _bar.get_global_rect().has_point(point):
		return false
	var backpack = battle.tower_backpack
	if backpack != null and backpack.is_visible_in_tree() and backpack.get_global_rect().has_point(point):
		return false
	# Controls with GUI input own their wheel/drag gestures, including the shop.
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered == null or hovered.mouse_filter == Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	if not Space.uses_terrain():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		reset_view()
		get_viewport().set_input_as_handled()
	if not (event is InputEventMouseButton) or not event.pressed or not _can_navigate(event.position):
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var factor := pow(1.15,maxf(event.factor,0.01))
		_zoom(factor if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/factor,event.position)
		get_viewport().set_input_as_handled()
	elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
		var world = battle.get_node("Battlefield/MonsterLayer")
		if event.button_index == MOUSE_BUTTON_LEFT:
			if world._in_placement() or world._hit_slot_screen(event.position,true)>=0:
				return
		_drag_button = event.button_index
		_drag_origin = event.position
		_last_pointer = event.position
		_dragging = event.button_index == MOUSE_BUTTON_MIDDLE
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _drag_button == 0:
		return
	if event is InputEventMouseMotion:
		if not _dragging and event.position.distance_to(_drag_origin)>=5.0:
			_dragging = true
		if _dragging:
			Camera.pan(event.position-_last_pointer,_viewport_size())
			_last_pointer = event.position
			_refresh()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == _drag_button:
		_end_drag()
		get_viewport().set_input_as_handled()

func _end_drag() -> void:
	_drag_button = 0
	_dragging = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end_drag()
