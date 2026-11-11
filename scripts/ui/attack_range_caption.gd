extends Node2D

var _center := Vector2.ZERO
var _text := ""
var _color := Color.WHITE

func show_range(center: Vector2, caption: String, color: Color) -> void:
	if center == _center and caption == _text and color == _color:
		return
	_center = center
	_text = caption
	_color = color
	queue_redraw()

func _draw() -> void:
	if _text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var pos := _center + Vector2(-width * 0.5, 33.0)
	draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0.04, 0.06, 0.08))
	draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _color)
