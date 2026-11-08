extends SceneTree
##
## 实机截图冒烟（非 CI · 窗口模式）：关卡地图地形贴图（资产包 v4）目检
##   每张变体：只有地形 + 核心（无塔无怪），用来单独判断地表材质 / 岩脊 / 阵地台。
## 运行：<godot> --path . --script res://tools/shoot_map_terrain_smoke.gd
## 产物：art/_review/smoke_map_<变体>.png
##
## 🔴 采图纪律（踩过的坑，见 asset-pack-v2 §5）：
##   ① 战场层没有 per-frame 重绘 → 截图前必须 `queue_redraw()`，否则截到空白/上一帧；
##   ② 首帧常截到残留场景 → 前 12 帧只等不拍；
##   ③ 每次换图要 `set_active_map()`，怪/塔坐标缓存按 map_id 失效。
##
const _MonsterLayer := preload("res://scripts/ui/monster_layer.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const IDS: Array = ["tri-fissure", "variant-f", "fusion"]

class _MockPlayer:
	extends RefCounted
	var towers: Array = []

class _MockRt:
	extends RefCounted
	var geo = null
	var player = null
	var free_placement: bool = false
	var data: Dictionary = {}
	func snapshot() -> Dictionary:
		return data

class _MockCtl:
	extends Node
	var runtime: RefCounted

var _f := 0
var _idx := -1
var _ml: Node = null


func _initialize() -> void:
	# 🔴 必须把窗口钉到 1080p：实机 sc = min((vw−2m)/116,(vh−2m)/116)，
	#    窗口被系统 DPI 缩放时 sc 会掉到 6~7 → 地形贴图被缩小 2.5 倍，细节全糊，目检失真。
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	_SpaceModel.mode = 1          # Mode.RADIAL（boot 之外默认 PATH）
	_next()


func _next() -> void:
	_idx += 1
	if _idx >= IDS.size():
		return
	var mid: String = IDS[_idx]
	_SpaceModel.set_active_map(mid)
	var holder := _MockCtl.new()
	var rt := _MockRt.new()
	rt.data = {
		"slots": [], "towers": [], "monsters": [], "minions": [], "projectiles": [],
		"selected_tower_slot": -1, "core_tower_slot": 0,
		"aggro_ui": false, "offers": [], "w": 0,
	}
	rt.player = _MockPlayer.new()
	holder.runtime = rt
	_ml = _MonsterLayer.new()
	_ml.controller = holder
	_ml._snap = rt.data
	root.add_child(_ml)


func _process(_d: float) -> bool:
	_f += 1
	if _idx >= IDS.size():
		return true
	if _ml != null:
		_ml.queue_redraw()
	if _f % 30 == 0:
		var mid: String = IDS[_idx]
		if _f == 30:
			var vs := root.get_viewport().get_visible_rect().size
			print("[diag] viewport=", vs, " field_w=", _ml._field_width() if _ml.has_method("_field_width") else -1.0)
		_shot("smoke_map_" + mid.replace("-", "_") + ".png")
		if _ml != null:
			root.remove_child(_ml)
			_ml.free()
			_ml = null
		_next()
	return false


func _shot(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://art/_review/" + fname)
	print("[shot] art/_review/", fname)
