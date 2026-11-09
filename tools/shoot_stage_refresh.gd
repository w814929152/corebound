extends SceneTree
## 选关页改版的实机截图与排版检查；进度只在内存中构造，不读写玩家存档。
## godot --path . --script res://tools/shoot_stage_refresh.gd
const Stage := preload("res://scripts/ui/stage_select_overlay.gd")
const Campaign := preload("res://scripts/gameplay/campaign.gd")
const Data := preload("res://scripts/data/campaign_data.gd")
const OUT := "res://art/_review/stage_refresh/"
var _stage: CanvasLayer
var _frame := 0
var _index := 0
var _errors := 0
var _jobs := [
	{"name": "01_start_1600", "size": Vector2i(1600, 900), "cleared": [], "focus": "0-1"},
	{"name": "02_progress_1600", "size": Vector2i(1600, 900), "cleared": ["0-1", "1-1", "2-1"], "focus": "4-1"},
	{"name": "03_locked_1600", "size": Vector2i(1600, 900), "cleared": [], "focus": "9-1"},
	{"name": "04_locked_1280", "size": Vector2i(1280, 720), "cleared": [], "focus": "9-1"},
	{"name": "05_complete_1920", "size": Vector2i(1920, 1080), "cleared": Data.STAGE_ORDER, "focus": "9-1"},
]

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_build_job()
	if _frame == 28:
		_check_layout(_stage)
		var job: Dictionary = _jobs[_index]
		if DisplayServer.get_name() != "headless":
			var image := root.get_texture().get_image()
			if image.get_pixel(10, 10).is_equal_approx(Color(0.3, 0.3, 0.3, 1.0)):
				_frame = 20
				return false
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
			image.save_png(OUT + String(job.name) + ".png")
		print("[checked] ", job.name, " logical viewport=", _stage._canvas.size,
			" button_disabled=", _stage._enter_button.disabled)
		_stage.free()
		_index += 1
		_frame = 0
		if _index == _jobs.size():
			print("[done] stage layout errors=", _errors)
			quit(0 if _errors == 0 else 1)
	return false

func _build_job() -> void:
	var job: Dictionary = _jobs[_index]
	root.size = job.size
	var campaign := Campaign.new()
	for sid in job.cleared:
		campaign.mark_cleared(String(sid))
	_stage = Stage.new()
	root.add_child(_stage)
	_stage.open(campaign)
	_stage._hovered = String(job.focus)
	_stage._refresh_detail()
	_stage._canvas.queue_redraw()

func _check_layout(node: Node) -> void:
	if node is Control and node.is_visible_in_tree():
		var control := node as Control
		var minimum := control.get_combined_minimum_size()
		if control.size.x + 1.0 < minimum.x or control.size.y + 1.0 < minimum.y:
			_errors += 1
			push_error("Squeezed %s: size=%s minimum=%s" % [node, control.size, minimum])
		if node is Label or node is Button:
			var bounds := Rect2(Vector2.ZERO, _stage._canvas.size)
			var rect := control.get_global_rect()
			if not bounds.encloses(rect):
				_errors += 1
				push_error("Outside viewport: %s" % node)
	for child in node.get_children():
		_check_layout(child)
