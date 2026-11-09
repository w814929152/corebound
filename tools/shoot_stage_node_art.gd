extends SceneTree
## 节点美术截图冒烟：只在内存中构造进度，不读写玩家存档。
## godot --path . --script res://tools/shoot_stage_node_art.gd
const Stage := preload("res://scripts/ui/stage_select_overlay.gd")
const Campaign := preload("res://scripts/gameplay/campaign.gd")
const Data := preload("res://scripts/data/campaign_data.gd")
const OUT := "res://art/_review/stage_nodes/"
var _frame := 0
var _job := 0
var _stage: CanvasLayer
var _failures := 0
var _scenes := [
	{"name": "01_start", "cleared": [], "focus": "0-1", "size": Vector2i(1600, 900)},
	{"name": "02_progress", "cleared": ["0-1"], "focus": "0-1", "size": Vector2i(1600, 900)},
	{"name": "03_locked", "cleared": ["0-1"], "focus": "9-1", "size": Vector2i(1280, 720)},
	{"name": "04_complete", "cleared": Data.STAGE_ORDER, "focus": "9-1", "size": Vector2i(1920, 1080)},
]

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var config: Dictionary = _scenes[_job]
		root.size = config.size
		var campaign := Campaign.new()
		for sid in config.cleared:
			campaign.mark_cleared(String(sid))
		_stage = Stage.new()
		root.add_child(_stage)
		_stage.open(campaign)
		_stage._hovered = String(config.focus)
		_stage._refresh_detail()
		_stage._canvas.queue_redraw()
	if _frame == 35:
		var config: Dictionary = _scenes[_job]
		var size: Vector2 = _stage._canvas.size
		var expected: Dictionary = _stage.layout_points(size)
		for sid in expected:
			var point: Vector2 = expected[sid]
			if _stage.map_point(String(sid)).distance_to(point) > 0.01 or _stage._hit(expected, point) != sid:
				push_error("Node position / hit mismatch: " + String(sid))
				_failures += 1
		if DisplayServer.get_name() != "headless":
			var image := root.get_texture().get_image()
			if image.get_pixel(10, 10).is_equal_approx(Color(0.3, 0.3, 0.3, 1.0)):
				_frame = 25
				return false
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
			image.save_png(OUT + String(config.name) + ".png")
			if _job == 1:
				image.get_region(Rect2i(410, 130, 780, 565)).save_png(OUT + "nodes_detail.png")
		print("[checked] ", config.name, " viewport=", size, " node/hit errors=", _failures)
		_stage.free()
		_job += 1
		_frame = 0
		if _job == _scenes.size():
			print("[done] node art scenarios=", _job, " failures=", _failures)
			quit(0 if _failures == 0 else 1)
	return false
