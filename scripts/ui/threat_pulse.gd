extends Control
##
## 边缘红光脉冲（占位）—— CanvasLayer **120**（GDD §2.4 分层表）
##
## 🔴 两条硬约束（锚点 4 第 4 条 / 交接点 10）：
##   ① **必须用动效（运动 + 亮度），禁止文字/数字** —— 人眼余光对形状与文字不敏感；
##   ② **必须用 unscaled 时钟** —— 若在 scaled 时钟下做脉冲，游戏缩放低于 1.0× 时脉冲频率
##      会跟着降低 → 余光告警在最需要它的时刻失效。
##
## 骨架实现：用 `Time.get_ticks_msec()` 差值手算相位（实测不受 time_scale / paused 影响）。
## 正式实现可直接换 `Tween` + `set_ignore_time_scale(true)`（4.7.2 实测有此方法，见探针日志）。
##
## 后续切片：alpha 由 `wave-spawner` 的 `threat_level_changed(level)` 驱动（契约 WS-4）。
##

const C_RED := Color(0.92, 0.16, 0.16, 1.0)
const EDGE := 56.0               # 边缘光带厚度
const PULSE_HZ := 1.6            # 脉冲频率（🔴 实时 Hz，不随游戏缩放变）
const BASE_ALPHA := 0.22         # 骨架阶段的固定威胁度（等 WS-4 供数）

var _threat: float = 0.5         # [接口] 威胁度 0..1，后续由 WS-4 写入
var _phase: float = 0.0
var _last_msec: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS     # 安全窗下也要保持可见（虽然世界停了）
	_last_msec = Time.get_ticks_msec()


func bind_director(_d: Node) -> void:
	pass    # 骨架阶段不依赖状态机；占位实现


func set_threat(t: float) -> void:
	# [接口] WS-4：wave-spawner 把威胁度喂进来
	_threat = clampf(t, 0.0, 1.0)


func _process(_delta: float) -> void:
	# 🔴 unscaled：用 Time 差值，不用 delta
	var now := Time.get_ticks_msec()
	var dt_real := float(now - _last_msec) / 1000.0
	_last_msec = now
	if dt_real > 0.25:
		dt_real = 0.25
	_phase += dt_real * PULSE_HZ * TAU
	queue_redraw()


func _draw() -> void:
	if _threat <= 0.0:
		return
	var r: Rect2 = get_viewport().get_visible_rect()
	var w := float(r.size.x)
	var h := float(r.size.y)
	# 亮度（呼吸）+ 运动（相位推进）双通道，不用文字
	var pulse: float = 0.5 + 0.5 * sin(_phase)
	var a: float = BASE_ALPHA * _threat * (0.45 + 0.55 * pulse)
	var c := Color(C_RED.r, C_RED.g, C_RED.b, a)
	draw_rect(Rect2(0.0, 0.0, w, EDGE), c)
	draw_rect(Rect2(0.0, h - EDGE, w, EDGE), c)
	draw_rect(Rect2(0.0, EDGE, EDGE, h - EDGE * 2.0), c)
	draw_rect(Rect2(w - EDGE, EDGE, EDGE, h - EDGE * 2.0), c)
