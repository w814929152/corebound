extends Control
## Bottom inventory for purchased tower cards; releases use the existing placement intent.

const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
## 🆕 字体注册表（art-bible §5.4）：面板文字不再走引擎默认字体（400 太细）。
const _Style := preload("res://scripts/ui/ui_style.gd")
const BAR_H := 104.0
const BAR_BOTTOM_GAP := 98.0
const CARD_W := 86.0
const CARD_H := 76.0
const GAP := 8.0
const C_TEXT := Color(0.784, 0.812, 0.855)
const C_DIM := Color(0.545, 0.580, 0.647)
const C_PANEL := Color(0.055, 0.071, 0.118, 0.94)
const C_CARD := Color(0.12, 0.16, 0.23, 0.96)
const C_ACTIVE := Color(0.243, 0.816, 0.910)

var controller: Node = null
var director: Node = null
var world_layer: Node = null
var _pending: Array = []
var _drag_index := -1
var _first_visible := 0
var _drag_name := ""
var _panel_box: StyleBoxFlat
var _card_box: StyleBoxFlat
var _active_box: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_box = _make_box(C_PANEL, Color(0.243, 0.816, 0.910, 0.35), 1, 6)
	_card_box = _make_box(C_CARD, Color(1.0, 1.0, 1.0, 0.14), 1, 4)
	_active_box = _make_box(Color(0.09, 0.20, 0.25, 0.98), C_ACTIVE, 2, 4)
	_layout()
	get_tree().root.size_changed.connect(_layout)

func _make_box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box

func bind_controller(c: Node) -> void:
	controller = c
	if controller != null and not controller.is_connected("shop_changed", _on_shop_changed):
		controller.shop_changed.connect(_on_shop_changed)
	_refresh_snapshot()

func bind_director(d: Node) -> void:
	director = d

func bind_world_layer(layer: Node) -> void:
	world_layer = layer

func _on_shop_changed() -> void:
	_refresh_snapshot()

func _refresh_snapshot() -> void:
	if controller != null and controller.runtime != null:
		_pending = controller.runtime.snapshot().get("pending", []).duplicate()
	_first_visible = mini(_first_visible, maxi(0, _pending.size() - _visible_count()))
	queue_redraw()

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	position = Vector2(18.0, vs.y - BAR_BOTTOM_GAP - BAR_H)
	size = Vector2(maxf(0.0, vs.x - 36.0), BAR_H)
	queue_redraw()

func _visible_count() -> int:
	return maxi(1, int(floor((size.x - 128.0 + GAP) / (CARD_W + GAP))))

func _bar_rect() -> Rect2:
	return Rect2(position, size)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _bar_rect().has_point(mb.global_position) and _pending.size() > _visible_count():
				var max_first := maxi(0, _pending.size() - _visible_count())
				_first_visible = clampi(_first_visible + (-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, max_first)
				queue_redraw()
				get_viewport().set_input_as_handled()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and _drag_index < 0:
			var local := mb.global_position - position
			var index := _card_at(local)
			if index >= 0 and controller != null and controller.request_placement(index):
				_drag_index = index
				_drag_name = String(_pending[index])
				_Style.set_cursor("place")     # 🆕 v4：拖起 → 放置准星
				queue_redraw()
				get_viewport().set_input_as_handled()
		elif not mb.pressed and _drag_index >= 0:
			_drop_at(mb.global_position)
			get_viewport().set_input_as_handled()
	elif _drag_index >= 0 and event is InputEventMouseMotion:
		queue_redraw()

## 🆕 v4 拖动中的光标态：复用 _drop_at 同款判定（placement_mode_at）。
##    🔴 只在 _draw（motion 驱动）里调，避免每帧多余查询。
func _drag_cursor_update() -> void:
	var g := get_global_mouse_position()
	if _bar_rect().has_point(g) or world_layer == null or controller == null:
		_Style.set_cursor("default")
		return
	var world: Vector2 = _BuildGrid.snap(world_layer.screen_to_world_position(g))
	var placement: Dictionary = controller.runtime.placement_mode_at(world)
	if String(placement.get("mode", "invalid")) in ["new", "upgrade"]:
		_Style.set_cursor("place")
	else:
		_Style.set_cursor("deny")


func _card_at(local_pos: Vector2) -> int:
	var slots := _visible_count()
	for offset in range(slots):
		var index := _first_visible + offset
		if index >= _pending.size():
			break
		if Rect2(112.0 + offset * (CARD_W + GAP), 16.0, CARD_W, CARD_H).has_point(local_pos):
			return index
	return -1

func _drop_at(screen_pos: Vector2) -> void:
	_drag_index = -1
	_drag_name = ""
	_Style.set_cursor("default")               # 🆕 v4：无论落点合法与否，松手即回默认箭头
	if director == null:
		queue_redraw()
		return
	if _bar_rect().has_point(screen_pos) or world_layer == null or controller == null:
		director.exit_placement(false)
		queue_redraw()
		return
	var world: Vector2 = _BuildGrid.snap(world_layer.screen_to_world_position(screen_pos))
	var placement: Dictionary = controller.runtime.placement_mode_at(world)
	if String(placement.get("mode", "invalid")) in ["new", "upgrade"]:
		director.emit_signal("place_at_requested", world)
	else:
		director.exit_placement(false)
	queue_redraw()

func _draw() -> void:
	draw_style_box(_panel_box, Rect2(Vector2.ZERO, size))
	# 🆕 §5.4 注册表字体（可读性：引擎 fallback 400 → medium 700）；缺失时退回 fallback。
	var font: Font = _Style.font_medium()
	if font == null:
		font = ThemeDB.fallback_font
	draw_string(font, Vector2(18.0, 39.0), "背包", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_TEXT)
	draw_string(font, Vector2(18.0, 65.0), "拖放 · 滚轮翻页", HORIZONTAL_ALIGNMENT_LEFT, 104.0, 16, C_DIM)
	var visible := _visible_count()
	for offset in range(visible):
		var index := _first_visible + offset
		if index >= _pending.size():
			break
		var rect := Rect2(112.0 + offset * (CARD_W + GAP), 16.0, CARD_W, CARD_H)
		var active := index == _drag_index
		draw_style_box(_active_box if active else _card_box, rect)
		draw_string(font, rect.position + Vector2(8.0, 29.0), String(_pending[index]).left(8), HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 16.0, 16, C_TEXT)
		draw_string(font, rect.position + Vector2(8.0, 57.0), "放置中" if active else "建筑塔", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_ACTIVE if active else C_DIM)
	if _pending.size() > visible:
		draw_string(font, Vector2(size.x - 70.0, 62.0), "%d/%d" % [_first_visible + 1, _pending.size() - visible + 1], HORIZONTAL_ALIGNMENT_RIGHT, 52.0, 16, C_DIM)
	if _drag_index >= 0:
		var mouse := get_local_mouse_position()
		draw_circle(mouse, 18.0, Color(C_ACTIVE.r, C_ACTIVE.g, C_ACTIVE.b, 0.45))
		draw_string(font, mouse + Vector2(24.0, 5.0), _drag_name.left(12), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)
		# 🆕 v4 光标三态：拖动中逐帧判定落点合法性（motion 每帧 redraw 驱动）
		#    落点非法 → deny 禁止光标；合法 → place 准星；拖回背包条 → default。
		_drag_cursor_update()
