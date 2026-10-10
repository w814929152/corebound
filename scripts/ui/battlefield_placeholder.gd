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
## 🔴 P0（spec §A.6）：环境换装共享色表（纯静态助手，与 `MonsterLayer` 共用同款 preload）。
const _EnvPalette := preload("res://scripts/ui/env_palette.gd")
## 档间过渡时长（spec §A.5 / art-bible §2.4：3.0s 缓动，不得突变）。
const ENV_FADE_SEC := 3.0

const ENEMY_COUNT := 5
const SPEED := 90.0                      # px/s（游戏时间）
const C_FIELD := Color(0.10, 0.14, 0.12, 1.0)
const C_FIELD_DIM := Color(0.055, 0.075, 0.065, 1.0)
const C_PATH := Color(0.22, 0.20, 0.16, 1.0)
const C_ENEMY := Color(0.90, 0.35, 0.28, 1.0)
# 🔴 P0（spec §A.7）：RADIAL 场地底配色。
#   ⚠️ 第三刀（spec §A.6）：绘制已改为**按档取色**（`_env_col()` ← `env_palette.gd`），
#     下面两条保留为 **T0 夜幕基线参考值**（= `env_palette.gd` 的 T0 行，w≤0 零变化）。
const C_BG_R := Color(0.078, 0.090, 0.149, 1.0)     # #141726 背景（雾底）
const C_FIELD_R := Color(0.137, 0.157, 0.220, 1.0)  # #232838 场地圆填充
const MARGIN := 48.0                                # 与 MonsterLayer._xform 同口径


var director: Node = null

var _t: float = 0.0
var _enemies: Array = []
## 🔴 P0（spec §A.5/§A.6）：环境换装过渡计时器（**纯演出本地状态**，无回写、无玩法耦合）。
##   `_env_tier` = 当前目标档；`_env_prev` = 过渡起点档；`_env_t` ∈ [0,1]（1 = 过渡完成）。
##   `-1` = 尚未落位（首帧直接落位，无过渡）。
var _env_tier: int = -1
var _env_prev: int = -1
var _env_t: float = 1.0
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
	# 🔴 P0（spec §A.5）：环境换装档位推进（纯演出；只读 director 快照的波号）。
	_update_env(delta)
	for e in _enemies:
		e["x"] = float(e["x"]) + SPEED * float(delta)
		var limit: float = _battlefield_width()
		if float(e["x"]) > limit + 80.0:
			e["x"] = -80.0
	queue_redraw()


# ---------------------------------------------------------------------------
#  环境换装（spec §A.2/§A.3/§A.5/§A.6）—— 纯演出，零玩法写入
# ---------------------------------------------------------------------------
## 🔴 当前波号（**只读** director 快照）。TimeDirector 快照键 = `"wave"`，
##   WaveDirector 快照键 = `"w"`；两者同源（同一 `sm.wave`、同一帧同步）→ 兼容取。
func _current_wave() -> int:
	if director == null or not director.has_method("snapshot"):
		return 0
	var s: Dictionary = director.snapshot()
	return int(s.get("w", s.get("wave", 0)))


## 环境换装档位推进（spec §A.5 伪码）：跨档边界触发 3s 过渡；首次直接落位（无过渡）。
func _update_env(delta: float) -> void:
	var ti := _EnvPalette.tier_of(_current_wave())
	if _env_tier < 0:
		_env_tier = ti
		_env_prev = ti
		_env_t = 1.0
	elif ti != _env_tier:
		_env_prev = _env_tier
		_env_tier = ti
		_env_t = 0.0
	if _env_t < 1.0:
		_env_t = minf(1.0, _env_t + clampf(float(delta), 0.0, 0.1) / ENV_FADE_SEC)


## 档间过渡取色（spec §A.5）：smoothstep `e(t)=t²(3−2t)` + 线性 RGB `Color.lerp`。
##   `key ∈ {"bg","field","ring"}`；`alpha` 由调用方施加（同心环 0.5 / 放射刻度 0.35）。
func _env_col(key: String, alpha: float) -> Color:
	var a: Color = _EnvPalette.get_color(_env_prev, key)
	var b: Color = _EnvPalette.get_color(_env_tier, key)
	var e := _env_t * _env_t * (3.0 - 2.0 * _env_t)
	var c := a.lerp(b, e)
	return Color(c.r, c.g, c.b, alpha)


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


## 🔴 P0（spec §A.7 / §A.6）：径向场地底 = 全屏背景 + 场地圆。
##   · 颜色**按档取色 + 3s smoothstep 过渡**（spec §A.5；色表见 `env_palette.gd`）。
##   · 核心恒在屏幕正中（径向包围盒对称）→ 场地圆圆心 = 视口中心。
##   · 缩放 `sc` 与 `MonsterLayer._xform()` 径向分支逐字一致（只读、无副作用）。
func _draw_radial_ground() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var vw := float(vs.x)
	var vh := float(vs.y)
	draw_rect(Rect2(0.0, 0.0, vw, vh), _env_col("bg", 1.0))
	var span := float(_SpaceModel.SPAWN_RADIUS) + 3.0
	var sc := minf((vw - 2.0 * MARGIN) / (2.0 * span), (vh - 2.0 * MARGIN) / (2.0 * span))
	if sc <= 0.0:
		sc = 1.0
	var c := Vector2(vw * 0.5, vh * 0.5)
	draw_circle(c, (float(_SpaceModel.SPAWN_RADIUS) + 2.0) * sc, _env_col("field", 1.0))
