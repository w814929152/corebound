extends Node2D
##
## 战场占位（Node2D 世界层，process_mode = **PAUSABLE**）
##
## 骨架阶段的使命：**用眼睛证明三件事**
##   ① 商店打开 → 怪点变慢（因为 `_process(delta)` 的 delta 被 `time_scale` 缩放，实测见探针日志）；
##   ② 安全窗 → 怪点**完全静止**（`get_tree().paused` 生效，PAUSABLE 节点不再被调 `_process`）；
##   ③ 抽屉展开时战场被压暗（vignette 占位），抽屉收起时恢复。
##
## 🔴 这是唯一一个「必须随暂停停止」的节点 —— 所以它保持 PAUSABLE（继承根）。
##    后续切片：换成真实等距战场 SubViewport（GDD §2.4 分层表：战场 = SubViewport）。
##

const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const ENEMY_COUNT := 5
const SPEED := 90.0                      # px/s（游戏时间）
const C_FIELD := Color(0.10, 0.14, 0.12, 1.0)
const C_FIELD_DIM := Color(0.055, 0.075, 0.065, 1.0)
const C_PATH := Color(0.22, 0.20, 0.16, 1.0)
const C_ENEMY := Color(0.90, 0.35, 0.28, 1.0)


var director: Node = null

var _t: float = 0.0
var _enemies: Array = []
# Q-S3-C：工程视口钉死 1920×1080（project.godot）；`_ready()` 里会按真实视口覆盖，
# 这里只是没跑起来时的默认值（占位绘制用）。
var _viewport_size := Vector2(1920.0, 1080.0)


func _ready() -> void:
	for i in ENEMY_COUNT:
		_enemies.append({"x": -80.0 - 120.0 * float(i), "y": 120.0 + 90.0 * float(i)})
	_refresh_size()


func _refresh_size() -> void:
	var r: Rect2 = get_viewport().get_visible_rect()
	_viewport_size = r.size


func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	d.state_changed.connect(_on_state_changed)
	queue_redraw()


func _on_state_changed(_from_state: int, _to_state: int) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	# 🔴 scaled delta：time_scale=0.35 时战场只推进 0.35 倍 → 这就是"慢动作不是暂停"
	_t += float(delta)
	for e in _enemies:
		e["x"] = float(e["x"]) + SPEED * float(delta)
		var limit: float = _battlefield_width()
		if float(e["x"]) > limit + 80.0:
			e["x"] = -80.0
	queue_redraw()


func _battlefield_width() -> float:
	var drawer_open := false
	if director != null:
		drawer_open = (int(director.sm.clock()["drawer"]) != 0)
	return _ShopLayout.battlefield_width(float(_viewport_size.x), drawer_open)


func _draw() -> void:
	var h := float(_viewport_size.y)
	var w := _battlefield_width()

	# 战场底
	var dim := false
	if director != null:
		dim = (int(director.sm.clock()["drawer"]) != 0)
	draw_rect(Rect2(0.0, 0.0, w, h), C_FIELD_DIM if dim else C_FIELD)

	# 怪物路径（一条横带，占位）
	# 径向模式下路径概念消失，横带是旧「路径走廊」残留 → 跳过（PATH 逐位不变）
	if not _SpaceModel.is_radial():
		draw_rect(Rect2(0.0, h * 0.45, w, 56.0), C_PATH)

		# 怪点
		for e in _enemies:
			var x := float(e["x"])
			if x < -40.0 or x > w + 40.0:
				continue
			draw_circle(Vector2(x, h * 0.45 + 28.0), 9.0, C_ENEMY)

	# 抽屉收起时补上右侧战场（放置模式要全屏看高亮）
	if w < float(_viewport_size.x) - 0.5:
		draw_rect(Rect2(w, 0.0, float(_viewport_size.x) - w, h), C_FIELD)
