extends Control
##
## 战场 HUD（**真 HUD** · P1 重做）—— CanvasLayer 10（GDD §2.4 分层表）
##
## 依据 blueprint `docs/phase3/ux-p0p1-spec.md` §B：
##   · 左上 L0 积分（辉金 #FFC94A，货币图标 + 等宽数字）
##   · 顶部中央 波次号 + 进度条（spawned/n）
##   · 底部 L3 快捷键提示
##   · **F3 可切换 debug 层（默认关闭）**：切片3/5 的全部验证读数**完整保留**（§B.4，不可删）
##
## 🔴 零玩法耦合：只读 `TimeDirector.snapshot()` / `Runtime.snapshot()` / `WaveDirector.snapshot()`；
##    不写任何玩法状态、不发玩法信号（control-manifest §5 / spec §C.4）。
## 🔴 布局：子控件用**绝对 position/size**（`_layout()`）—— 4.7.2 实测 `set_anchors_preset()`
##    对 `PRESET_CENTER_*` 会静默失效（见 `battle_shop.tscn` 顶部说明），故不依赖锚点预设。
##

const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")

const C_GOLD := Color(1.000, 0.788, 0.290)      # #FFC94A 辉金
const C_ALERT := Color(1.000, 0.180, 0.306)     # #FF2E4E 警报红
const C_ENEMY := Color(1.000, 0.420, 0.239)     # #FF6B3D 熔橙（进度条）
const C_ALLY := Color(0.243, 0.816, 0.910)      # #3ED0E8 耀青
const C_TEXT := Color(0.784, 0.812, 0.855)      # #C8CFDA
const C_TEXT_DIM := Color(0.545, 0.580, 0.647)  # #8B94A5
const C_WHITE := Color(1.0, 1.0, 1.0)
const C_PANEL := Color(0.078, 0.090, 0.149, 0.92)
const C_PANEL_SOFT := Color(0.078, 0.090, 0.149, 0.85)

const WAVE_BAR_W := 320.0
const WAVE_BAR_H := 8.0
const BANNER_MS := 1200

var director: Node = null
var controller: Node = null

var _score_label: Label
var _wave_label: Label
var _hint_label: Label
var _start_wave_btn: Button
var _banner: Label
var _debug_panel: PanelContainer

# ---- F3 保留读数（§B.4：切片3/5 观测全部进 debug 层，不可删）----
var _battle_label: Label
var _run_label: Label
var _state_label: Label
var _clock_label: Label
var _budget_label: Label
var _gain_label: Label
var _layout_label: Label

# ---- 纯演出本地状态（非玩法）----
var _debug_visible: bool = false
var _wave_progress: float = 0.0
var _wave_elite: bool = false
var _banner_end_ms: int = 0

# ---- P1 增强：积分数字滚动 + 金色粒子（spec §5.2 / §C.2「增强」）----
#   🔴 纯本地 easing：只把**新版数字**缓动显示出来；**不改数据源、不改玩法数值**。
const SCORE_ROLL_SEC := 0.25         # 数字滚动时长（EASE_OUT）
const SCORE_PULSE_DECAY := 6.0       # 缩放脉冲衰减速率（/s）
const GOLD_ORIGIN := Vector2(64.0, 56.0)   # 硬币图标中心（粒子发射原点）
var _score_display: float = 0.0      # 当前**显示**值（缓动中）
var _score_from: float = 0.0
var _score_to: float = 0.0
var _score_t: float = 1.0            # >= SCORE_ROLL_SEC 表示动画已完成
var _score_init: bool = false
var _score_pulse: float = 0.0        # 缩放脉冲（1→0）
var _gold_parts: Array = []          # 一次性金色小粒子（纯画面）


func _ready() -> void:
	_build()
	_layout()
	if get_tree() != null:
		get_tree().root.size_changed.connect(_refresh_size)


func _refresh_size() -> void:
	_layout()
	queue_redraw()


## 子控件绝对布局（视口尺寸变化时重算）。
func _layout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	var vw := float(vs.x)
	var vh := float(vs.y)
	position = Vector2.ZERO
	size = vs
	if _score_label != null:
		_score_label.position = Vector2(104.0, 22.0)
		_score_label.size = Vector2(560.0, 74.0)
	if _wave_label != null:
		_wave_label.position = Vector2(vw * 0.5 - 200.0, 20.0)
		_wave_label.size = Vector2(400.0, 56.0)
	if _start_wave_btn != null:
		_start_wave_btn.position = Vector2(vw * 0.5 + WAVE_BAR_W * 0.5 + 14.0, 62.0)
		_start_wave_btn.size = Vector2(128.0, 40.0)
	if _hint_label != null:
		_hint_label.position = Vector2(24.0, vh - 44.0)
		_hint_label.size = Vector2(1300.0, 26.0)
	if _debug_panel != null:
		_debug_panel.position = Vector2(16.0, 108.0)
		_debug_panel.size = Vector2(584.0, 460.0)
	if _banner != null:
		_banner.position = Vector2.ZERO
		_banner.size = vs
		_banner.pivot_offset = Vector2(vw * 0.5, vh * 0.5)


func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	d.state_changed.connect(_on_state_changed)
	d.budget_changed.connect(_on_budget_changed)
	if d.has_signal("wave_started"):
		d.wave_started.connect(_on_wave_started)
	call_deferred("_on_state_changed", -1, int(d.sm.state))


func bind_controller(c: Node) -> void:
	controller = c
	if c == null:
		return
	if not c.is_connected("shop_changed", _on_run_changed):
		c.shop_changed.connect(_on_run_changed)
	if not c.is_connected("run_changed", _on_run_changed):
		c.run_changed.connect(_on_run_changed)
	call_deferred("_on_run_changed")


func _on_state_changed(_from: int, _to: int) -> void:
	queue_redraw()


func _on_budget_changed(_left: float, _max_: float) -> void:
	queue_redraw()


func _on_run_changed() -> void:
	queue_redraw()


## 波次开始 → 屏幕中央大字横幅（1.2s 动效，spec §B.2；精英/Boss 波改红描边）。
func _on_wave_started(w: int) -> void:
	if _banner == null:
		return
	if _wave_elite:
		_banner.text = "精英波 %d" % w
		_banner.add_theme_color_override("font_outline_color", C_ALERT)
	else:
		_banner.text = "WAVE %d" % w
		_banner.add_theme_color_override("font_outline_color", C_GOLD)
	_banner_end_ms = Time.get_ticks_msec() + BANNER_MS
	_banner.visible = true


# ---------------------------------------------------------------------------
#  构建
# ---------------------------------------------------------------------------
func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 积分（左上 L0 辉金）
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 52)
	_score_label.add_theme_color_override("font_color", C_GOLD)
	_score_label.text = "0"
	add_child(_score_label)

	# 波次（顶部中央 L0 白）
	_wave_label = Label.new()
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 44)
	_wave_label.add_theme_color_override("font_color", C_WHITE)
	_wave_label.text = "WAVE 1"
	add_child(_wave_label)

	# 开始下一波（波次条右端；仅 SafeWindow 可用 —— 保留按钮功能）
	_start_wave_btn = Button.new()
	_start_wave_btn.text = "开始下一波"
	_style_button(_start_wave_btn)
	_start_wave_btn.pressed.connect(func() -> void:
		if director != null:
			director.start_next_wave())
	add_child(_start_wave_btn)

	# 底部 L3 快捷键提示（「开关抽屉 / 放置」降级为提示文本；抽屉内已有放置入口）
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_hint_label.text = "Tab 商店 · Esc 关闭/取消 · R 刷新 · 1/2/3 选中即买 · Space 锁定焦点位 · F3 调试"
	add_child(_hint_label)

	# WAVE 大字横幅（层 10，1.2s 演出）
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 96)
	_banner.add_theme_color_override("font_color", C_WHITE)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.add_theme_color_override("font_outline_color", C_GOLD)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)

	_build_debug_panel()


func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL_SOFT
	sb.set_border_width_all(1)
	sb.border_color = Color(C_ALLY.r, C_ALLY.g, C_ALLY.b, 0.5)
	sb.set_corner_radius_all(4)
	_debug_panel.add_theme_stylebox_override("panel", sb)
	add_child(_debug_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_debug_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	margin.add_child(vb)

	var head := Label.new()
	head.text = "F3 调试读数（切片3/5 验证观测 · 默认隐藏）"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", C_TEXT_DIM)
	vb.add_child(head)

	_battle_label = _mk_dbg(vb)
	_run_label = _mk_dbg(vb)
	_state_label = _mk_dbg(vb)
	_clock_label = _mk_dbg(vb)
	_budget_label = _mk_dbg(vb)
	_gain_label = _mk_dbg(vb)
	_layout_label = _mk_dbg(vb)
	_debug_panel.visible = _debug_visible


func _mk_dbg(parent: Node) -> Label:
	var l := Label.new()
	l.text = "-"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", C_TEXT_DIM)
	parent.add_child(l)
	return l


func _style_button(b: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL
	normal.set_border_width_all(2)
	normal.border_color = C_ALLY
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0
	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.16, 0.22, 0.95)
	hover.border_color = C_GOLD
	var dis := normal.duplicate()
	dis.bg_color = Color(0.08, 0.09, 0.12, 0.7)
	dis.border_color = Color(0.35, 0.38, 0.42, 0.6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", C_WHITE)
	b.add_theme_color_override("font_color_disabled", C_TEXT_DIM)
	b.add_theme_font_size_override("font_size", 16)


# ---------------------------------------------------------------------------
#  每帧刷新（只读）
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# P1 增强：本地演出推进（数字缓动 + 金色粒子），与数据源无关。
	_advance_score(float(delta))
	_advance_particles(float(delta))
	if director == null:
		return
	var s: Dictionary = director.snapshot()
	_wave_label.text = "WAVE %d" % int(s["wave"])
	_refresh_score()
	_refresh_wave_progress()
	_start_wave_btn.disabled = (int(s["state"]) != _TSM.State.SAFE_WINDOW)
	if _debug_visible:
		_refresh_debug(s)
	_refresh_banner()
	queue_redraw()


## P1 增强：积分数字滚动（本地 easing）。读 `runtime.snapshot()["scrap"]` 只作**目标值**。
func _refresh_score() -> void:
	if controller == null or controller.runtime == null:
		return
	var target := float(controller.runtime.snapshot().get("scrap", 0))
	if not _score_init:
		_score_init = true
		_score_display = target
		_score_from = target
		_score_to = target
		_score_t = SCORE_ROLL_SEC
		_score_label.text = _fmt_int(int(round(target)))
		return
	if absf(target - _score_to) > 0.0001:
		_score_from = _score_display
		_score_to = target
		_score_t = 0.0
		if target > _score_from:      # 仅增长时给弹性反馈（花分不闪）
			_score_pulse = 1.0
			_spawn_gold()


## 数字缓动推进（0.25s · cubic EASE_OUT）。
func _advance_score(delta: float) -> void:
	if _score_t < SCORE_ROLL_SEC:
		_score_t = minf(SCORE_ROLL_SEC, _score_t + delta)
		var p := _score_t / SCORE_ROLL_SEC
		var e := 1.0 - pow(1.0 - p, 3.0)
		_score_display = _score_from + (_score_to - _score_from) * e
		if _score_label != null:
			_score_label.text = _fmt_int(int(round(_score_display)))
	if _score_pulse > 0.0:
		_score_pulse = maxf(0.0, _score_pulse - delta * SCORE_PULSE_DECAY)
		if _score_label != null:
			var k := 1.0 + 0.14 * _score_pulse
			_score_label.pivot_offset = Vector2(0.0, _score_label.size.y * 0.5)
			_score_label.scale = Vector2(k, k)


## 一次性金色小粒子（积分增长时，从硬币图标喷出；纯画面）。
func _spawn_gold() -> void:
	for i in 6:
		var a := -PI * 0.5 + randf_range(-0.9, 0.9)
		_gold_parts.append({
			"pos": GOLD_ORIGIN + Vector2(randf_range(-16.0, 16.0), randf_range(-10.0, 10.0)),
			"vel": Vector2(cos(a), sin(a)) * randf_range(60.0, 150.0),
			"life": 0.0,
			"max": randf_range(0.35, 0.60),
		})
	if _gold_parts.size() > 48:
		_gold_parts = _gold_parts.slice(_gold_parts.size() - 48)


func _advance_particles(delta: float) -> void:
	if _gold_parts.is_empty():
		return
	var keep: Array = []
	for pt in _gold_parts:
		pt["life"] = float(pt["life"]) + delta
		if float(pt["life"]) < float(pt["max"]):
			pt["pos"] = (pt["pos"] as Vector2) + (pt["vel"] as Vector2) * delta
			pt["vel"] = (pt["vel"] as Vector2) * (1.0 - 2.5 * delta)
			keep.append(pt)
	_gold_parts = keep


func _refresh_wave_progress() -> void:
	if controller == null or controller.wave_director == null:
		return
	var s: Dictionary = controller.wave_director.snapshot()
	var n := int(s.get("n", 0))
	_wave_progress = (float(s.get("spawned", 0)) / float(n)) if n > 0 else 0.0
	_wave_elite = bool(s.get("is_elite_wave", false))


func _refresh_debug(s: Dictionary) -> void:
	_refresh_battle_line()
	_refresh_run_line()
	_state_label.text = "态：%s (id=%d)" % [String(s["state_name"]), int(s["state"])]
	_clock_label.text = "time_scale=%.2f（引擎实测 %.2f）· paused=%s" % [
		float(s["time_scale"]), float(s["engine_time_scale"]),
		("true" if bool(s["paused"]) else "false")]
	_budget_label.text = "预算 %.2f / %.0f s · 本态消耗=%s" % [
		float(s["budget_left"]), float(s["budget_max"]),
		("是" if bool(s["consumes_budget"]) else "否")]
	var gain := 1.0
	if float(s["game_seconds"]) > 0.0:
		gain = float(s["real_seconds"]) / float(s["game_seconds"])
	_gain_label.text = "实时 %.2fs / 游戏 %.2fs → 思考增益 ×%.2f" % [
		float(s["real_seconds"]), float(s["game_seconds"]), gain]
	_refresh_layout_line()


## 切片5：真实刷怪读数（只读 `WaveDirector.snapshot()`）。
func _refresh_battle_line() -> void:
	if _battle_label == null:
		return
	if controller == null or controller.wave_director == null:
		_battle_label.text = "战斗 --（WaveDirector 未接线）"
		return
	var s: Dictionary = controller.wave_director.snapshot()
	_battle_label.text = "%s · t=%.1fs · 在场 %d · 已出 %d/%d · 杀 %d 漏 %d" % [
		controller.wave_director.state_name(), float(s["t_wave"]), int(s["alive"]),
		int(s["spawned"]), int(s["n"]), int(s["kills"]), int(s["leaked"])]


func _refresh_run_line() -> void:
	if _run_label == null:
		return
	if controller == null or controller.runtime == null:
		_run_label.text = "积分 -- · 核心 --（未接线）"
		return
	var r: Dictionary = controller.runtime.snapshot()
	_run_label.text = "积分 %.0f · 核心 %.0f/%.0f · 待放置 %d · 强化槽 %d/%d · 塔 %d/%d" % [
		float(r["scrap"]), float(r["core_hp"]), float(r["core_hp_max"]),
		(r["pending"] as Array).size(),
		int(r["cards"]), int(r["cards_max"]),
		int(r["towers"]), int(r["towers_max"])]
	# 🟢 终局状态行（胜负由 WaveDirector 判定）。
	#   🔴 [缺陷修复] 原 `bool(wd.run_won)` 对**信号**调 bool() → 结束帧报
	#      "Nonexistent 'bool' constructor"。改为读只读快照的 `won` 布尔字段。
	if bool(controller.over):
		var won := false
		var wd: Node = controller.wave_director
		if wd != null and wd.has_method("snapshot"):
			won = bool((wd.snapshot() as Dictionary).get("won", false))
		_run_label.text += ("   【通关胜利】" if won else "   【核心归零 · 失败】")


func _refresh_layout_line() -> void:
	if _layout_label == null:
		return
	var vw := float(get_viewport().get_visible_rect().size.x)
	var dw := _ShopLayout.drawer_width(vw)
	_layout_label.text = "布局：视口 %.0f · 抽屉 %.0f (%.1f%%) · 战场 %.0f" % [
		vw, dw, _ShopLayout.drawer_ratio(vw) * 100.0, vw - dw]


func _refresh_banner() -> void:
	if _banner == null or not _banner.visible:
		return
	var remain := _banner_end_ms - Time.get_ticks_msec()
	if remain <= 0:
		_banner.visible = false
		return
	var elapsed := float(BANNER_MS - remain) / 1000.0
	var k := 1.0
	var a := 1.0
	if elapsed < 0.28:
		var p := elapsed / 0.28
		k = 2.2 - 1.2 * p
		a = p
	elif elapsed < 0.95:
		k = 1.0
		a = 1.0
	else:
		var p2 := clampf((elapsed - 0.95) / 0.25, 0.0, 1.0)
		k = 1.0 - 0.08 * p2
		a = 1.0 - p2
	_banner.scale = Vector2(k, k)
	_banner.modulate = Color(1.0, 1.0, 1.0, a)


func _fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i != 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# ---------------------------------------------------------------------------
#  绘制（HUD chrome：硬币图标 + 波次进度条；文本走 Label 子节点）
# ---------------------------------------------------------------------------
func _draw() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	var cx := float(vs.x) * 0.5
	# 硬币图标（左上 L0）—— P1 增强：随积分脉冲轻微放大
	var coin_k := 1.0 + 0.10 * _score_pulse
	draw_circle(GOLD_ORIGIN, 32.0 * coin_k, C_GOLD)
	draw_circle(GOLD_ORIGIN, 22.0 * coin_k, Color(0.97, 0.66, 0.16, 1.0))
	draw_circle(GOLD_ORIGIN, 10.0 * coin_k, C_GOLD)
	# P1 增强：一次性金色小粒子（积分增长喷出）
	for pt in _gold_parts:
		var p := clampf(float(pt["life"]) / float(pt["max"]), 0.0, 1.0)
		draw_circle(pt["pos"], 1.0 + 4.0 * (1.0 - p),
			Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, (1.0 - p) * 0.9))
	# 波次进度条（顶部中央，波次数字之下）
	var bx := cx - WAVE_BAR_W * 0.5
	var by := 84.0
	draw_rect(Rect2(bx, by, WAVE_BAR_W, WAVE_BAR_H), Color(0.14, 0.16, 0.20, 0.9))
	if _wave_elite:
		draw_rect(Rect2(bx - 6.0, by - 6.0, WAVE_BAR_W + 12.0, WAVE_BAR_H + 12.0),
			Color(C_ALERT.r, C_ALERT.g, C_ALERT.b, 0.2))
	draw_rect(Rect2(bx, by, WAVE_BAR_W * clampf(_wave_progress, 0.0, 1.0), WAVE_BAR_H), C_ENEMY)
	var font := ThemeDB.fallback_font
	if font != null and _wave_elite:
		draw_string(font, Vector2(bx, by - 8.0), "精英波",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_ALERT)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var e := event as InputEventKey
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_F3:
		_debug_visible = not _debug_visible
		if _debug_panel != null:
			_debug_panel.visible = _debug_visible
		queue_redraw()
		get_viewport().set_input_as_handled()
