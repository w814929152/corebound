extends Control
##
## 战场 HUD（**骨架占位版**）—— CanvasLayer 10（GDD §2.4 分层表）
##
## 骨架阶段的双重身份：
##   ① 占位 HUD（波次 / 积分 / 状态名）；
##   ② **切片3 的实测读数面板** —— 直接把 `TimeDirector.snapshot()` 打在屏幕上，
##      于是「五态 time_scale 逐条对上」「预算按实时秒消耗」「2.86× 思考时间增益」
##      这三件事在**窗口模式下一眼可见**，不用看日志。
##
## 后续切片：读数面板换成真正的塔层数徽章 / 共鸣光弧 / 伤害数字（层 10）。
##

const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")


var director: Node = null
var controller: Node = null     # ShopController（只读它的 runtime.snapshot()）

var _state_label: Label
var _clock_label: Label
var _budget_label: Label
var _wave_label: Label
var _gain_label: Label
var _run_label: Label
var _layout_label: Label
var _hint_label: Label
var _start_wave_btn: Button
var _placement_btn: Button
var _open_shop_btn: Button
var _battle_label: Label      # 切片5：真实刷怪读数（实时推进 vs 金标本等价）


func _ready() -> void:
	_build()
	if get_tree() != null:
		get_tree().root.size_changed.connect(_refresh_size)


func _refresh_size() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # HUD 不吃点击（战场要点塔）


func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	d.state_changed.connect(_on_state_changed)
	d.budget_changed.connect(_on_budget_changed)
	call_deferred("_on_state_changed", -1, d.sm.state)
	call_deferred("_on_budget_changed", d.sm.budget_left, d.sm.budget_max)


func bind_controller(c: Node) -> void:
	controller = c
	if c == null:
		return
	if not c.is_connected("shop_changed", _on_run_changed):
		c.shop_changed.connect(_on_run_changed)
	if not c.is_connected("run_changed", _on_run_changed):
		c.run_changed.connect(_on_run_changed)
	call_deferred("_on_run_changed")


func _on_run_changed() -> void:
	_refresh()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.set_offset(SIDE_LEFT, 16.0)
	panel.set_offset(SIDE_TOP, 72.0)       # 给穿透式核心 HP 条让出顶部
	panel.set_offset(SIDE_RIGHT, 420.0)
	panel.set_offset(SIDE_BOTTOM, 300.0)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_child(vb)
	panel.add_child(margin)

	var head := Label.new()
	head.text = "HUD（骨架占位）· 切片3 实测读数"
	head.add_theme_font_size_override("font_size", 15)
	vb.add_child(head)

	_wave_label = _mk_line(vb)
	_battle_label = _mk_line(vb)
	_run_label = _mk_line(vb)
	_state_label = _mk_line(vb)
	_clock_label = _mk_line(vb)
	_budget_label = _mk_line(vb)
	_gain_label = _mk_line(vb)

	# ---- 骨架流程按钮（后续切片：开始下一波走 wave-spawner；放置走待放置队列图标）----
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	_open_shop_btn = Button.new(); _open_shop_btn.text = "开关抽屉 (Tab)"
	_placement_btn = Button.new(); _placement_btn.text = "放置模式"
	_start_wave_btn = Button.new(); _start_wave_btn.text = "开始下一波"
	row.add_child(_open_shop_btn)
	row.add_child(_placement_btn)
	row.add_child(_start_wave_btn)

	# 🔴 D-8（切片5 已删）：`[调试] 结束本波` 按钮与 `controller.debug_end_wave()`。
	#    波次推进改由 `WaveDirector` 真实刷怪驱动 —— 打完自然进安全窗，不需要调试跳过。
	_open_shop_btn.pressed.connect(func() -> void:
		if director != null: director.toggle_shop())
	_placement_btn.pressed.connect(func() -> void:
		if director != null:
			if director.sm.state == director.sm.State.PLACEMENT_MODE:
				director.exit_placement(false)
			else:
				director.enter_placement())
	_start_wave_btn.pressed.connect(func() -> void:
		if director != null: director.start_next_wave())

	_hint_label = Label.new()
	_hint_label.text = "Tab 开关 · Esc 关闭/取消 · R 刷新 · 1/2/3 选中即买 · Space 锁定焦点位"
	_hint_label.add_theme_font_size_override("font_size", 12)
	vb.add_child(_hint_label)

	# 战场/抽屉宽度读数（证明双焦点比例）
	_layout_label = _mk_line(vb)
	_refresh_layout_line()


func _refresh_layout_line() -> void:
	if _layout_label == null:
		return
	var vw := float(get_viewport().get_visible_rect().size.x)
	var dw := _ShopLayout.drawer_width(vw)
	_layout_label.text = "布局：视口 %.0f · 抽屉 %.0f (%.1f%%) · 战场 %.0f" % [
		vw, dw, _ShopLayout.drawer_ratio(vw) * 100.0, vw - dw]


func _mk_line(parent: Node) -> Label:
	var l := Label.new()
	l.text = "-"
	l.add_theme_font_size_override("font_size", 13)
	parent.add_child(l)
	return l


func _on_state_changed(_from_state: int, _to_state: int) -> void:
	_refresh()


func _on_budget_changed(_left: float, _max_: float) -> void:
	_refresh()


func _refresh() -> void:
	if director == null:
		return
	var s: Dictionary = director.snapshot()
	_wave_label.text = "波次 W%d" % int(s["wave"])
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
	_start_wave_btn.disabled = (int(s["state"]) != 3)   # 仅 SafeWindow(3)
	_placement_btn.disabled = not (int(s["state"]) in [1, 2, 3])
	_refresh_layout_line()


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


## 切片5：真实刷怪读数（**只读** `WaveDirector.snapshot()`，UI 不持有玩法状态）
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


func _process(_delta: float) -> void:
	# 读数面板每帧刷新（骨架阶段可接受；正式版改走信号 + dirty flag，SR-6）
	_refresh()
