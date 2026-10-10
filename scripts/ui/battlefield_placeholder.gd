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
# 🔴 P0（spec §A.7）：RADIAL 场地底配色（精确 hex）。
const C_BG_R := Color(0.078, 0.090, 0.149, 1.0)     # #141726 背景（雾底）
const C_FIELD_R := Color(0.137, 0.157, 0.220, 1.0)  # #232838 场地圆填充
const MARGIN := 48.0                                # 与 MonsterLayer._xform 同口径


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
	# 🔴 P0（spec §A.7）：RADIAL 模式改画径向场地底（背景 + 场地圆）。
	#    父节点先绘制 → MonsterLayer 在其上画 decal/单位（不重复不透明全屏底）。
	if _SpaceModel.is_radial():
		_draw_radial_ground()
		return

	var h := float(_viewport_size.y)
	var w := _battlefield_width()

	# 战场底
	var dim := false
	if director != null:
		dim = (int(director.sm.clock()["drawer"]) != 0)
	draw_rect(Rect2(0.0, 0.0, w, h), C_FIELD_DIM if dim else C_FIELD)

	# 怪物路径（一条横带，占位）—— PATH 模式逐位不变
	draw_rect(Rect2(0.0, h * 0.45, w, 56.0), C_PATH)

	for e in _enemies:
		var x := float(e["x"])
		if x < -40.0 or x > w + 40.0:
			continue
		draw_circle(Vector2(x, h * 0.45 + 28.0), 9.0, C_ENEMY)

	# 抽屉收起时补上右侧战场（放置模式要全屏看高亮）
	if w < float(_viewport_size.x) - 0.5:
		draw_rect(Rect2(w, 0.0, float(_viewport_size.x) - w, h), C_FIELD)


## 🔴 P0（spec §A.7）：径向场地底 = 全屏背景 #141726 + 场地圆 #232838。
##   · 核心恒在屏幕正中（径向包围盒对称）→ 场地圆圆心 = 视口中心。
##   · 缩放 `sc` 与 `MonsterLayer._xform()` 径向分支逐字一致（只读、无副作用）。
func _draw_radial_ground() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var vw := float(vs.x)
	var vh := float(vs.y)
	draw_rect(Rect2(0.0, 0.0, vw, vh), C_BG_R)
	var span := float(_SpaceModel.SPAWN_RADIUS) + 3.0
	var sc := minf((vw - 2.0 * MARGIN) / (2.0 * span), (vh - 2.0 * MARGIN) / (2.0 * span))
	if sc <= 0.0:
		sc = 1.0
	var c := Vector2(vw * 0.5, vh * 0.5)
	draw_circle(c, (float(_SpaceModel.SPAWN_RADIUS) + 2.0) * sc, C_FIELD_R)
