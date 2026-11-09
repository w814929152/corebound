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

const _Style := preload("res://scripts/ui/ui_style.gd")

## 🆕 v4 结算情绪层 + 横幅（asset-pack-v4-result.md §3.1）
##    贴图缺失 → 不加层（回纯黑幕 + 纯色标题），判空降级 headless 安全。
const MOOD_WON_PATH := "res://art/2d/ui/ui_result_won_bg_v1.png"
const MOOD_LOST_PATH := "res://art/2d/ui/ui_result_lost_bg_v1.png"
const BANNER_WON_PATH := "res://art/2d/ui/ui_result_won_banner_v1.png"
const BANNER_LOST_PATH := "res://art/2d/ui/ui_result_lost_banner_v1.png"

var _built: bool = false
var _on_restart: Callable = Callable()
var _on_quit: Callable = Callable()

var _backdrop: ColorRect
var _mood: TextureRect = null        # 🆕 情绪背景层（黑幕之上、面板之下）
var _banner: TextureRect = null      # 🆕 面板顶部横幅带
var _panel: PanelContainer
var _title_label: Label
var _body_label: Label
var _restart_btn: Button
var _quit_btn: Button
# 🆕 战报读数（§5.2 数字优先：等宽数字仪表行，替代原正文里的埋数）
var _stat_core: Label        # 核心剩余 HP
var _stat_wave: Label        # 坚守波次
var _stat_scrap: Label       # 本局废料
var _tex_cache: Dictionary = {}      # path -> Texture2D|null（判空缓存）


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

	# 🆕 v4 情绪背景层：胜利金核辉光 / 失败红裂纹（盖黑幕之上；缺失 → 不加层）
	if _load_tex(MOOD_WON_PATH) != null:
		_mood = TextureRect.new()
		_mood.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_mood.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mood.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mood.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_mood)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	# 🔴 居中关键：`PRESET_CENTER` 只把锚点放中心，**增长方向默认是 END** ⇒ 控件从中心
	#    往右下长，整体偏到中心右下方半个面板。改成 BOTH 后从中心向两侧对称扩张 = 真正居中。
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(520.0, 0.0)
	# 🆕 补面板样式（原先走 Godot 默认主题 → 一块无描边的灰色方块，与战场语言断裂）
	_panel.add_theme_stylebox_override("panel", _Style.panel(_Style.C_ALLY, 2, 26.0, 22.0))
	# 🆕 §5.5 蓝图语言：外沿四角 L 刻线，accent 随胜负切换（show_result 内 set_chrome_accent）
	_Style.attach_corner_chrome(_panel)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# 🆕 v4 横幅带：标题上方（宽随面板拉伸；缺失 → 不加，标题直接顶上）
	if _load_tex(BANNER_WON_PATH) != null:
		_banner = TextureRect.new()
		_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_banner.stretch_mode = TextureRect.STRETCH_SCALE
		_banner.custom_minimum_size = Vector2(0.0, 64.0)
		vbox.add_child(_banner)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 40)
	_Style.apply_font(_title_label, "display")    # §5.4：结算标题 = Black 展示字重
	_title_label.add_theme_color_override("font_color", _Style.C_GOLD)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# 🆕 副题（L2 常规）：一句话定性，数字细节交给下面的战报行
	_body_label = Label.new()
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：15 → 16。
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", _Style.C_TEXT_DIM)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body_label)

	vbox.add_child(_Style.hline())

	# 🆕 战报块（§5.2「数字 > 文字」：终局数据用等宽读数仪表行，不再埋在正文里）
	_stat_core = _make_stat_row(vbox, "核心剩余")
	_stat_wave = _make_stat_row(vbox, "坚守波次")
	_stat_scrap = _make_stat_row(vbox, "本局废料")

	vbox.add_child(_Style.hline())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	_restart_btn = Button.new()
	_restart_btn.text = "再来一局"
	_restart_btn.custom_minimum_size = Vector2(160.0, 46.0)
	_Style.button(_restart_btn, "primary")
	_restart_btn.pressed.connect(_on_restart_pressed)
	hbox.add_child(_restart_btn)

	_quit_btn = Button.new()
	_quit_btn.text = "退出"
	_quit_btn.custom_minimum_size = Vector2(120.0, 46.0)
	_Style.button(_quit_btn, "normal")
	_quit_btn.pressed.connect(_on_quit_pressed)
	hbox.add_child(_quit_btn)


## 战报行：名称（L2 常规，左）+ 读数（L0 等宽数字 §5.2，右）。
##   返回读数 Label（show_result 里填数）。
func _make_stat_row(parent: VBoxContainer, name_text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var nm := _Style.label(name_text, 16, _Style.C_TEXT_DIM)
	row.add_child(nm)
	var val := _Style.label("--", 24, _Style.C_WHITE)
	_Style.apply_font(val, "num")                 # §5.2：数字必须等宽（滚动不抖）
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	return val


## 判空缓存加载（缺失返回 null 且不重复 load）。
func _load_tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex


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
		# 🆕 改用 art-bible §2.2 登记色：胜利 = 辉金（收益极），失败 = 警报红（危险极）。
		#    原来的 (0.30,0.90,0.55) 绿是表外色，与「青/橙双极」配色语言不一致。
		_title_label.add_theme_color_override("font_color", _Style.C_GOLD)
		_Style.set_chrome_accent(_panel, _Style.C_GOLD)   # 🆕 刻线 accent 随胜负切换
		# 🆕 v4 情绪层 / 横幅按胜负切换
		if _mood != null:
			_mood.texture = _load_tex(MOOD_WON_PATH)
		if _banner != null:
			_banner.texture = _load_tex(BANNER_WON_PATH)
		_stat_core.text = "%d / %d" % [int(p_core_hp), int(p_core_hp_max)]
		_stat_core.add_theme_color_override("font_color", _Style.C_WHITE)
		_stat_wave.text = "W%d" % p_wave
		_stat_wave.add_theme_color_override("font_color", _Style.C_WHITE)
		_stat_scrap.text = "%.0f" % float(p_scrap)
		_stat_scrap.add_theme_color_override("font_color", _Style.C_GOLD)  # §2.2 辉金 = 资源
		_body_label.text = "守核成功 —— 打完 W1 → W%d 全部波次" % p_wave
	else:
		_title_label.text = "核 心 归 零 · 失 败"
		_title_label.add_theme_color_override("font_color", _Style.C_ALERT)
		_Style.set_chrome_accent(_panel, _Style.C_ALERT)
		# 🆕 v4 情绪层 / 横幅按胜负切换
		if _mood != null:
			_mood.texture = _load_tex(MOOD_LOST_PATH)
		if _banner != null:
			_banner.texture = _load_tex(BANNER_LOST_PATH)
		_stat_core.text = "%d / %d" % [int(p_core_hp), int(p_core_hp_max)]
		_stat_core.add_theme_color_override("font_color", _Style.C_ALERT)
		_stat_wave.text = "W%d" % p_wave
		_stat_wave.add_theme_color_override("font_color", _Style.C_WHITE)
		_stat_scrap.text = "%.0f" % float(p_scrap)
		_stat_scrap.add_theme_color_override("font_color", _Style.C_GOLD)
		_body_label.text = "核心在 W%d 被击穿 —— 构筑强度不足，再试一次？" % p_wave
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
