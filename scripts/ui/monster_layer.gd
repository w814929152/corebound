extends Node2D
##
## 怪物 / 路径 / 塔位 **占位渲染层**（Node2D，世界层）
##
## 🔴 MVP 只做**占位可视化**（主理人决策 5：**不做美术渲染**，那是后续切片）：
##    · 路径：5 段折线（灰褐色粗线）+ 6 个路径点；
##    · 核心：路径终点 (55,25) 的实心方块；
##    · 塔位：空心圆；`d_path ≤ 9.0` 的暴露位外圈画一圈红环（🔴 GDD：MVP 只登记数据，
##      不产出玩法 → 这里只是"把静态事实画出来"，不给任何推荐）；
##    · 怪物：按原型上色 / 尺寸的实心圆 —— **Rush 小快 / Swarm 中 / Tank 大慢**，
##      Elite 加一圈黄环。
##
## 🔴 分层纪律（control-manifest §5）：本节点**只读** `WaveDirector.snapshot()`，
##    不写任何玩法状态，也不发意图信号。process_mode = INHERIT（随暂停停 →
##    安全窗冻结画面，这正是 W-C3 想要的"完全静止"）。
##
## 坐标：世界 XZ 平面（x ∈ [0,55]，z ∈ [16,48]）→ 屏幕像素。
##   映射 = 等比缩放 + 居中（保比例，不拉伸），与 `art-bible` §6.1 的等距投影无关（占位）。
##
## ⚠️ G6：headless 无 global_script_class_cache → 不写 class_name。
##

const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")

const MARGIN := 48.0
const C_PATH := Color(0.34, 0.30, 0.22, 1.0)
const C_PATH_DOT := Color(0.55, 0.48, 0.32, 1.0)
const C_CORE := Color(0.35, 0.85, 0.95, 1.0)
const C_SLOT := Color(0.45, 0.50, 0.55, 0.85)
const C_EXPOSE := Color(0.95, 0.30, 0.25, 0.75)

# 原型配色 / 半径（占位美术，无玩法含义）
const C_RUSH := Color(0.98, 0.45, 0.25, 1.0)
const C_SWARM := Color(0.82, 0.84, 0.88, 1.0)
const C_TANK := Color(0.35, 0.55, 0.95, 1.0)
const C_ELITE := Color(1.0, 0.92, 0.25, 1.0)
const R_RUSH := 5.0
const R_SWARM := 6.5
const R_TANK := 10.0


var director: Node = null        # WaveDirector
var time_director: Node = null   # TimeDirector（读抽屉宽，决定战场可视宽）
var _slot_rows: Array = []
var _snap: Dictionary = {}


func _ready() -> void:
	_slot_rows = _PathGeometry.slot_exposure(_Geo6.SLOTS6, 9.0)


func bind_director(d: Node) -> void:
	director = d
	queue_redraw()


func bind_time_director(d: Node) -> void:
	time_director = d
	if d == null:
		return
	if not d.is_connected("state_changed", _on_state_changed):
		d.state_changed.connect(_on_state_changed)
	queue_redraw()


func _on_state_changed(_from: int, _to: int) -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if director == null:
		return
	_snap = director.snapshot()
	queue_redraw()


# ---------------------------------------------------------------------------
#  坐标映射
# ---------------------------------------------------------------------------
func _field_width() -> float:
	var vw := float(get_viewport().get_visible_rect().size.x)
	var drawer_open := false
	if time_director != null:
		drawer_open = (int(time_director.sm.clock()["drawer"]) != 0)
	return _ShopLayout.battlefield_width(vw, drawer_open)


func _xform() -> Dictionary:
	var vw := _field_width()
	var vh := float(get_viewport().get_visible_rect().size.y)
	# 世界包围盒（路径 + 塔位 + 余量）
	var x0 := -3.0
	var x1 := 58.0
	var z0 := 13.0
	var z1 := 51.0
	var ww := x1 - x0
	var wh := z1 - z0
	var sc := minf((vw - 2.0 * MARGIN) / ww, (vh - 2.0 * MARGIN) / wh)
	if sc <= 0.0:
		sc = 1.0
	var ox := (vw - ww * sc) * 0.5 - x0 * sc
	var oy := (vh - wh * sc) * 0.5 - z0 * sc
	return {"sc": sc, "ox": ox, "oy": oy}


func _to_screen(p: Vector2) -> Vector2:
	var t := _xform()
	return Vector2(float(t["ox"]) + p.x * float(t["sc"]), float(t["oy"]) + p.y * float(t["sc"]))


# ---------------------------------------------------------------------------
#  绘制
# ---------------------------------------------------------------------------
func _draw() -> void:
	var t := _xform()
	var sc := float(t["sc"])

	# ---- 路径 ----
	for i in range(_PathGeometry.N_SEG):
		var a := _to_screen(_PathGeometry.PATH[i])
		var b := _to_screen(_PathGeometry.PATH[i + 1])
		draw_line(a, b, C_PATH, maxf(3.0, sc * 0.55), true)
	for i in range(_PathGeometry.PATH.size()):
		draw_circle(_to_screen(_PathGeometry.PATH[i]), maxf(2.0, sc * 0.22), C_PATH_DOT)

	# ---- 核心（路径终点）----
	var cp := _to_screen(_PathGeometry.CORE_POS)
	var cs := maxf(8.0, sc * 1.6)
	draw_rect(Rect2(cp.x - cs * 0.5, cp.y - cs * 0.5, cs, cs), C_CORE)

	# ---- 塔位（空心圆 + 暴露红环）----
	for row in _slot_rows:
		var p: Vector2 = row["pos"]
		var sp := _to_screen(p)
		draw_arc(sp, maxf(5.0, sc * 0.7), 0.0, TAU, 24, C_SLOT, maxf(1.0, sc * 0.10), true)
		if bool(row["is_exposed"]):
			draw_arc(sp, maxf(7.0, sc * 1.05), 0.0, TAU, 28, C_EXPOSE, maxf(1.0, sc * 0.08), true)

	# ---- 怪物 ----
	if _snap.is_empty():
		return
	var ms: Array = _snap.get("monsters", [])
	for m in ms:
		var p: Vector2 = m["pos"]
		var sp := _to_screen(p)
		var proto := String(m["proto"])
		var col := C_SWARM
		var rad := R_SWARM
		match proto:
			"Rush":
				col = C_RUSH
				rad = R_RUSH
			"Tank":
				col = C_TANK
				rad = R_TANK
			_:
				col = C_SWARM
				rad = R_SWARM
		rad = maxf(rad, sc * 0.55)
		draw_circle(sp, rad, col)
		if bool(m["elite"]):
			draw_arc(sp, rad + maxf(2.0, sc * 0.18), 0.0, TAU, 24, C_ELITE, maxf(1.5, sc * 0.16), true)
