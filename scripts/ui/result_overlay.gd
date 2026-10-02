extends CanvasLayer
##
## 切片8续3（可玩 MVP）· 一局结算覆盖层 —— `result_overlay.gd`
##
## 职责：把「W1→W20 完整一局」的**终局**打在屏幕上 —— 胜利（通关）/ 失败（核心归零）。
##   这是把已验证系统串成「能玩起来的一局」的收口：胜负判定来自 `WaveDirector`
##   的 `run_won` / `run_lost` 信号，本组件**纯展示 + 提供重开/退出意图**，不含玩法口径。
##
## 🔴 分层：CanvasLayer **150**（高于确认弹窗 140 / 商店 100 / 核心 HP 130）——
##   结算时盖住一切，玩家必须点「再来一局」或「退出」才离开（防误触中途切走）。
##
## 🔴 口径来源：wave-spawner §2.8（E-W3 核心归零失败）+ 概念 §2.1（W1–W20 一局）。
##   · 胜利：打完 W20 且核心未归零（`run_won`）；
##   · 失败：核心 HP ≤ 0（`run_lost`，E-W3 立即失败）。
##
## 用法（ShopController 侧）：
##   var ov := ResultOverlay.new()
##   add_child(ov)
##   ov.show_result(true, 20, core_hp, core_hp_max, scrap)   # 或 show_result(false, w, ...)
##
## ⚠️ Godot 坑（control-manifest §4）：
##   G6 headless 无 global_script_class_cache → 不写 class_name，调用方 preload/实例化；
##   layer 必须在 `_init` 钉死（show_result 可能在 _ready 前被调）。
##

signal restart_requested()
signal quit_requested()

var _built: bool = false
var _on_restart: Callable = Callable()
var _on_quit: Callable = Callable()

var _backdrop: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _body_label: Label
var _restart_btn: Button
var _quit_btn: Button


func _init() -> void:
	# 🔴 layer 在 _init 钉死（show_result 可能在 _ready 前被调，见 salvage_confirm_dialog 同款坑）
	layer = 150


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	if _built:
		return
	_built = true

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(400.0, 0.0)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body_label)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	_restart_btn = Button.new()
	_restart_btn.text = "再来一局"
	_restart_btn.custom_minimum_size = Vector2(140.0, 44.0)
	_restart_btn.pressed.connect(_on_restart_pressed)
	hbox.add_child(_restart_btn)

	_quit_btn = Button.new()
	_quit_btn.text = "退出"
	_quit_btn.custom_minimum_size = Vector2(120.0, 44.0)
	_quit_btn.pressed.connect(_on_quit_pressed)
	hbox.add_child(_quit_btn)


## 展示结算。
##   p_won     ：true = 通关胜利，false = 核心归零失败
##   p_wave    ：终局所在波次（胜利 = W20，失败 = 阵亡波）
##   p_core_hp / p_core_hp_max：终局核心 HP（胜利展示剩余血量，失败展示 0）
##   p_scrap   ：终局累计积分（两态都展示，作为「本局构筑成果」）
func show_result(p_won: bool, p_wave: int, p_core_hp: float, p_core_hp_max: float,
		p_scrap: float, on_restart: Callable = Callable(),
		on_quit: Callable = Callable()) -> void:
	_build()
	_on_restart = on_restart
	_on_quit = on_quit
	if p_won:
		_title_label.text = "通 关 胜 利"
		_title_label.add_theme_color_override("font_color", Color(0.30, 0.90, 0.55, 1.0))
		_body_label.text = "守核成功！\n打完 W1 → W%d 全部波次\n核心 HP 剩余 %d / %d\n本局积分 %.0f" % [
			p_wave, int(p_core_hp), int(p_core_hp_max), float(p_scrap)]
	else:
		_title_label.text = "核 心 归 零 · 失 败"
		_title_label.add_theme_color_override("font_color", Color(0.95, 0.32, 0.28, 1.0))
		_body_label.text = "核心在 W%d 被击穿\n构筑强度不足 —— 再试一次？\n本局积分 %.0f" % [
			p_wave, float(p_scrap)]
	visible = true


func _on_restart_pressed() -> void:
	visible = false
	if _on_restart.is_valid():
		_on_restart.call()
	restart_requested.emit()


func _on_quit_pressed() -> void:
	if _on_quit.is_valid():
		_on_quit.call()
	quit_requested.emit()
