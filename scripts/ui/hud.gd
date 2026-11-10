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

const _Battle := preload("res://scripts/ui/battle_theme.gd")
const _Briefings := preload("res://scripts/data/stage_briefings.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")
var _box_wave: StyleBoxFlat

const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _Style := preload("res://scripts/ui/ui_style.gd")

const C_GOLD := Color(1.000, 0.788, 0.290)      # #FFC94A 辉金
const C_ALERT := Color(1.000, 0.180, 0.306)     # #FF2E4E 警报红
const C_ENEMY := Color(1.000, 0.420, 0.239)     # #FF6B3D 熔橙（进度条）
const C_ALLY := Color(0.243, 0.816, 0.910)      # #3ED0E8 耀青
const C_TEXT := Color(0.784, 0.812, 0.855)      # #C8CFDA
const C_TEXT_DIM := Color(0.545, 0.580, 0.647)  # #8B94A5
const C_WHITE := Color(1.0, 1.0, 1.0)
const C_PANEL := Color(0.078, 0.090, 0.149, 0.92)
const C_PANEL_SOFT := Color(0.078, 0.090, 0.149, 0.85)

const WAVE_BAR_W := 300.0
const WAVE_BAR_H := 10.0
const BANNER_MS := 1200

## 底部键位行（默认态）。⑤ 放置模式会临时换成放置专属提示 —— 见 `_refresh_hint()`。
const HINT_DEFAULT := "Tab 商店   ·   拖动地图   ·   滚轮缩放   ·   F 回到核心"

## 🆕 UI 优化轮：积分卡（L0 区）几何。
##   改造前左上角只有一个硬币 + 裸数字，**没有任何文字说明它是什么**；而引导文案里叫
##   「废料」、商店里叫「废料」、debug 层又写「积分」—— 三处术语不一致，新手读不懂。
##   现统一为「废料」（与引导 / 商店文案一致），并给 L0 数字加面板承托（§5.3）。
const SCORE_BOX := Rect2(24.0, 22.0, 200.0, 78.0)
const SCORE_ICON := Vector2(60.0, 61.0)
const SCORE_ICON_R := 20.0
const SCORE_CAP_POS := Vector2(96.0, 28.0)
const SCORE_NUM_POS := Vector2(96.0, 43.0)

var director: Node = null
var controller: Node = null

var _score_label: Label
var _score_caption: Label
var _wave_label: Label
var _stage_label: Label
var _stage_hint: Label
var _hint_label: Label
var _shop_btn: Button
var _start_wave_btn: Button
var _banner: Label
var _debug_panel: PanelContainer
## 🆕 缓存 StyleBox（`_draw` 每帧调用，不得在绘制里 new StyleBoxFlat → 每帧分配）。
var _box_score: StyleBox
var _box_bar_track: StyleBoxFlat
var _box_bar_fill: StyleBoxFlat
var _box_bar_fill_elite: StyleBoxFlat

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
var _wave_spawned: int = 0          # 🆕 进度条读数：已出怪数
var _wave_total: int = 0            # 🆕 进度条读数：本波总数
var _wave_elite: bool = false
var _wave_in_combat: bool = false  # 🟢 反制窗口：波次条精英标记「分态取源」用（战斗 vs 决策期）
var _banner_end_ms: int = 0

# ---- P1 增强：积分数字滚动 + 金色粒子（spec §5.2 / §C.2「增强」）----
#   🔴 纯本地 easing：只把**新版数字**缓动显示出来；**不改数据源、不改玩法数值**。
const SCORE_ROLL_SEC := 0.25         # 数字滚动时长（EASE_OUT）
const SCORE_PULSE_DECAY := 6.0       # 缩放脉冲衰减速率（/s）
const GOLD_ORIGIN := SCORE_ICON            # 硬币图标中心（粒子发射原点）
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
	if _shop_btn != null and director != null and director.sm != null:
		_shop_btn.visible = int(director.sm.clock()["drawer"]) == _TSM.Drawer.CLOSED and int(director.sm.state) != _TSM.State.PLACEMENT_MODE
	var vp := get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	var vw := _ShopLayout.content_width(float(vs.x), director)
	var vh := float(vs.y)
	position = Vector2.ZERO
	size = vs
	if _score_label != null:
		_score_label.position = SCORE_NUM_POS
		_score_label.size = Vector2(130.0, 56.0)
	if _score_caption != null:
		_score_caption.position = SCORE_CAP_POS
		_score_caption.size = Vector2(140.0, 20.0)
	if _wave_label != null:
		_wave_label.position = Vector2(vw * 0.5 - 140.0, 24.0)
		_wave_label.size = Vector2(280.0, 46.0)
	if _stage_label != null:
		_stage_label.position = Vector2(24.0, 220.0)
		_stage_label.size = Vector2(280.0, 28.0)
	if _stage_hint != null:
		_stage_hint.position = Vector2(24.0, 260.0)
		_stage_hint.size = Vector2(264.0, 130.0)
	if _start_wave_btn != null:
		_start_wave_btn.position = Vector2(vw - (174.0 if _shop_btn == null or not _shop_btn.visible else 340.0), 22.0)
		_start_wave_btn.size = Vector2(150.0, 44.0)
	if _shop_btn != null:
		_shop_btn.position = Vector2(vw - 174.0, 22.0)
		_shop_btn.size = Vector2(150.0, 44.0)
	if _hint_label != null:
		# 🆕 上移到核心血条之上：原 `vh - 44` 正好落在血条底槽带（1002–1044）里，
		#    引导结束后露出键位行时会压住血条左端。
		_hint_label.position = Vector2(24.0, vh - 230.0)
		_hint_label.size = Vector2(maxf(0.0, vw - 48.0), 50.0)
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
	d.drawer_mode_changed.connect(func(_mode: int) -> void: _layout())
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


## 🔴 B-1 零教学（`docs/phase6/b1-tutorial-spec.md` §7-B(b) · 按 backlog 默认执行原则取推荐项 b）：
##    引导未 DONE 前隐藏底部常驻键位行 —— 首屏同时出现「键位表 + 步骤提示」会互相稀释；
##    `TutorialOverlay` 自然完成 / 跳过后再露出完整键位表。
##    🔴 纯显隐开关：不改文本内容、不动布局、不触碰任何快照读数。
func set_hint_visible(v: bool) -> void:
	if _hint_label == null:
		return
	_hint_label.visible = v


func _on_state_changed(_from: int, _to: int) -> void:
	_layout()
	_refresh_hint()
	queue_redraw()


## 底部键位行的**态相关**部分：⑤ 放置模式要换成本局的唯一操作提示。
## 🔴 依据：GDD §2.1 ⑤ 态**抽屉收起**、战场全屏，「点格子落子」是此态唯一的操作路径。
##    改造前这里还写着「Tab 商店 / R 刷新」，而那两个键在 ⑤ 态根本不响应 → 误导。
## 🆕 自由摆放：可建区铺满网格、核心周围有禁建圈，所以提示词从「点亮光的塔位」
##    改成「地图上的格子」—— 塔位不再是 6 个固定点，说「塔位」会让玩家去找那 6 个圈。
func _refresh_hint() -> void:
	if _hint_label == null:
		return
	var placing := (director != null and director.sm != null
		and int(director.sm.state) == _TSM.State.PLACEMENT_MODE)
	if placing:
		_hint_label.text = "点格子放置 · 中键拖动地图 · 滚轮缩放 · Esc 取消"
		_hint_label.add_theme_color_override("font_color", C_TEXT)
	elif director != null and director.sm != null and int(director.sm.state) == _TSM.State.SAFE_WINDOW:
		_hint_label.text = "准备阶段 · 拖拽防御塔调整位置 · 基地不可移动"
		_hint_label.add_theme_color_override("font_color", C_TEXT)
	else:
		_hint_label.text = HINT_DEFAULT
		_hint_label.add_theme_color_override("font_color", C_TEXT_DIM)


func _on_budget_changed(_left: float, _max_: float) -> void:
	queue_redraw()


func _on_run_changed() -> void:
	if director != null and director.sm != null and int(director.sm.wave) == 0 and _banner != null:
		_banner.visible = false
		_banner_end_ms = 0
	queue_redraw()


## 波次开始 → 屏幕中央大字横幅（1.2s 动效，spec §B.2；精英/Boss 波改红描边）。
func _on_wave_started(w: int) -> void:
	if _banner == null:
		return
	# 🔴 反制窗口 C-6：横幅用**入参 w** 判当前波精英态（不读上一帧残留 `_wave_elite`
	#   → 无刷新时序窗口）。`elite_waves_enabled` 取自 snapshot（只读，与 w 无关 → 无竞态）。
	var is_elite := false
	if controller != null and controller.wave_director != null:
		var ws: Dictionary = controller.wave_director.snapshot()
		is_elite = bool(ws.get("elite_waves_enabled", false)) and _MonsterData.is_elite_wave(w)
	if is_elite:
		_banner.text = "精英波 %d" % w
		_banner.add_theme_color_override("font_outline_color", C_ALERT)
	else:
		_banner.text = "第 %d 波" % w
		_banner.add_theme_color_override("font_outline_color", C_GOLD)
	_banner_end_ms = Time.get_ticks_msec() + BANNER_MS
	_banner.visible = true


# ---------------------------------------------------------------------------
#  构建
# ---------------------------------------------------------------------------
func _build() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 🆕 L0 区缓存样式：积分卡面板 + 波次条轨道 / 填充（避免 `_draw` 每帧 new）
	_box_score = _Battle.panel(C_GOLD, 0.0)
	_box_wave = _Battle.panel(C_ALLY, 0.0)
	# 🔴 轨道不能直接复用 `_Style.inset()`：它的底色（#0E111B）比场地圆（#1E2C46）更暗，
	#    叠在上面的结果就是「看不见轨道，只看见一条橙线」。改用半透明黑 + 细描边，深浅底都成立。
	_box_bar_track = StyleBoxFlat.new()
	_box_bar_track.bg_color = Color(0.0, 0.0, 0.0, 0.42)
	_box_bar_track.set_border_width_all(1)
	_box_bar_track.border_color = Color(1.0, 1.0, 1.0, 0.14)
	_box_bar_track.set_corner_radius_all(WAVE_BAR_H * 0.5)
	_box_bar_fill = _Style.bar_fill(C_ENEMY)
	_box_bar_fill_elite = _Style.bar_fill(C_ALERT)

	# 积分（左上 L0 辉金）—— 🆕 加「废料」说明行：裸数字读不出含义
	_score_caption = Label.new()
	_score_caption.text = "废料"
	_score_caption.add_theme_font_size_override("font_size", 16)
	_score_caption.add_theme_color_override("font_color", C_TEXT_DIM)
	_Style.apply_font(_score_caption, "medium")   # §5.4：小标题 = Medium
	add_child(_score_caption)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 36)
	_score_label.add_theme_color_override("font_color", C_GOLD)
	# §5.2「数字必须等宽」：积分 = 纯数字读数 → JetBrains Mono（滚动 / 脉冲时不再左右抖）
	_Style.apply_font(_score_label, "num")
	_score_label.text = "0"
	add_child(_score_label)

	# 波次（顶部中央 L0 白）
	_wave_label = Label.new()
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 30)
	_wave_label.add_theme_color_override("font_color", C_WHITE)
	_Style.apply_font(_wave_label, "display")     # §5.4：L0 波次号 = Black 展示字重
	_wave_label.text = "第 1 波"
	add_child(_wave_label)
	_stage_label = _Style.label("", 18, C_ALLY)
	_stage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage_label)
	_stage_hint = _Style.label("", 16, C_TEXT)
	_stage_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage_hint)

	_shop_btn = Button.new()
	_shop_btn.text = "商店 · Tab"
	_Battle.button(_shop_btn)
	_shop_btn.pressed.connect(func() -> void:
		if director != null:
			director.open_shop())
	add_child(_shop_btn)

	# 开始下一波（波次条右端；仅 SafeWindow 可用 —— 保留按钮功能）
	# 🆕 安全窗唯一的推进操作 → 用 primary（金描边）提升视觉重量，并走统一 hover/按下动效
	_start_wave_btn = Button.new()
	_start_wave_btn.text = "开始下一波"
	_Battle.button(_start_wave_btn, true)
	_start_wave_btn.pressed.connect(func() -> void:
		if director != null:
			director.start_next_wave())
	add_child(_start_wave_btn)

	# 底部 L3 快捷键提示（「开关抽屉 / 放置」降级为提示文本；抽屉内已有放置入口）
	_hint_label = Label.new()
	# 🔴 T-P6-06 S1（art-bible §9.1 P0 无障碍硬红线：最小字号 ≥16px）：14 → 16。
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_hint_label.text = HINT_DEFAULT
	add_child(_hint_label)

	# WAVE 大字横幅（层 10，1.2s 演出）
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 56)
	_banner.add_theme_color_override("font_color", C_WHITE)
	_Style.apply_font(_banner, "display")         # §5.4：波次横幅 = Black 展示字重
	_banner.add_theme_constant_override("outline_size", 3)
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
	_wave_label.text = "准备阶段" if int(s["wave"]) == 0 else "第 %d 波" % int(s["wave"])
	_start_wave_btn.text = "开始战斗" if int(s["wave"]) == 0 else "开始下一波"
	_refresh_score()
	_refresh_wave_progress()
	_start_wave_btn.disabled = (int(s["state"]) != _TSM.State.SAFE_WINDOW)
	_start_wave_btn.visible = not _start_wave_btn.disabled
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
	var sid := String(s.get("stage_id", ""))
	var briefing := _Briefings.get_briefing(sid)
	_stage_label.visible = not briefing.is_empty()
	_stage_hint.visible = not briefing.is_empty() and director != null and int(director.sm.wave) == 0
	if not briefing.is_empty():
		_stage_label.text = "%s · %s" % [sid, String(_CampaignData.STAGES[sid]["name"])]
		_stage_hint.text = "守住 %d 波\n%s" % [_CampaignData.wave_count(sid), String(briefing["hint"])]
		_stage_label.tooltip_text = String(briefing["hint"])
	var n := int(s.get("n", 0))
	_wave_spawned = int(s.get("spawned", 0))
	_wave_total = n
	_wave_progress = (float(_wave_spawned) / float(n)) if n > 0 else 0.0
	# 🟢 反制窗口 C-6「分态取源」：波次条**永远表达"玩家当下该准备的那一波"** ——
	#   战斗态(SPAWNING=1 / FIGHTING=2)用**当前波** `is_elite_wave`；安全窗 / IDLE(决策期)用
	#   **下一波** `next_is_elite_wave`。🔴 修 stale 隐患：`w` 在 `start_wave` 才自增 →
	#   安全窗期间若直接读 `is_elite_wave` 会显示**刚打完那波**的精英旗（residual）。
	var st := int(s.get("state", 0))
	_wave_in_combat = (st == 1 or st == 2)
	_wave_elite = (bool(s.get("is_elite_wave", false)) if _wave_in_combat
		else bool(s.get("next_is_elite_wave", false)))


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
## HUD 仪表层贴图缓存（`art/2d/ui/ui_hud_*` / `ui_core_*` / `ui_wave_*`）。
##   🔴 全部**判空降级**：资产缺失（headless 无 .import）时返回 null，
##      调用方退回原来的 StyleBoxFlat / draw_rect 路径，画面与改前一致。
##   🔴 只做"垫底 + 描边"绘制，**不移动任何控件**——布局常量仍是 SSOT。
var _tex_cache := {}


func _ht(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := "res://art/2d/ui/" + name
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[name] = t
	return t


## 在 rect 处镜像绘制贴图（四角角标只用一张资产，靠 transform 翻四个方向）。
##   🔴 画完必须把 transform 复位，否则同帧后续绘制全被镜像。
func _tex_flip(t: Texture2D, r: Rect2, fx: bool, fy: bool) -> void:
	if not fx and not fy:
		draw_texture_rect(t, r, false)
		return
	var origin := Vector2(
		r.position.x + (r.size.x if fx else 0.0),
		r.position.y + (r.size.y if fy else 0.0))
	draw_set_transform(origin, 0.0, Vector2(-1.0 if fx else 1.0, -1.0 if fy else 1.0))
	draw_texture_rect(t, Rect2(Vector2.ZERO, r.size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	var cx := _ShopLayout.content_width(float(vs.x), director) * 0.5
	# 战斗仪表使用统一的深色悬浮底座。
	draw_style_box(_box_score, SCORE_BOX)
	var preparing: bool = director != null and director.sm.wave == 0
	var plate := Rect2(cx - 170.0, 22.0, 340.0, 62.0 if preparing else 108.0)
	draw_style_box(_box_wave, plate)
	draw_line(Vector2(cx - 32.0, plate.end.y), Vector2(cx + 32.0, plate.end.y), C_ALLY, 2.0)
	# 硬币图标（左上 L0）—— P1 增强：随积分脉冲轻微放大
	var coin_k := 1.0 + 0.10 * _score_pulse
	# 🔴 批次⑥：金币贴图（ic_coin，烘焙三层同心圆 @R28 比例），脉冲缩放保留运行时；缺失降级。
	var coin_tex := _Style.icon("ic_coin")
	if coin_tex != null:
		var cr := SCORE_ICON_R * coin_k
		draw_texture_rect(coin_tex, Rect2(SCORE_ICON - Vector2(cr, cr), Vector2(cr * 2.0, cr * 2.0)), false)
	else:
		draw_circle(SCORE_ICON, SCORE_ICON_R * coin_k, C_GOLD)
		draw_circle(SCORE_ICON, (SCORE_ICON_R - 6.0) * coin_k, Color(0.97, 0.66, 0.16, 1.0))
		draw_circle(SCORE_ICON, (SCORE_ICON_R - 18.0) * coin_k, C_GOLD)
	# P1 增强：一次性金色小粒子（积分增长喷出）
	for pt in _gold_parts:
		var p := clampf(float(pt["life"]) / float(pt["max"]), 0.0, 1.0)
		draw_circle(pt["pos"], 1.0 + 4.0 * (1.0 - p),
			Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, (1.0 - p) * 0.9))
	# 准备阶段没有刷怪进度，不绘制空仪表。
	if director != null and director.sm.wave == 0:
		return
	# 波次进度条（顶部中央，波次数字之下）
	# 🆕 加轨道底 + 圆角 + 右端读数；与 WAVE 文字之间留出 20px 呼吸（原仅 8px，视觉贴死）
	var bx := cx - WAVE_BAR_W * 0.5
	var by := 90.0
	# 🆕 波次仪表导轨（348x36，槽位在纹理内 (28,23,300,12) → 画在 bx-28, by-23）
	#    🔴 高度只到 by+13：`已出/总数` 读数的字顶在 by+14，导轨不得盖到读数上。
	#    🔴 右端只外扩 20px：`_start_wave_btn` 起点在 bx+326，首版 392 宽会压到按钮。
	var t_rail: Texture2D = null
	if t_rail != null:
		draw_texture(t_rail, Vector2(bx - 28.0, by - 23.0))
	var t_track := _ht("ui_wave_track_v1.png")
	if t_track != null:
		draw_texture(t_track, Vector2(bx, by))
	elif _box_bar_track != null:
		draw_style_box(_box_bar_track, Rect2(bx, by, WAVE_BAR_W, WAVE_BAR_H))
	if _wave_elite:
		draw_rect(Rect2(bx - 6.0, by - 6.0, WAVE_BAR_W + 12.0, WAVE_BAR_H + 12.0),
			Color(C_ALERT.r, C_ALERT.g, C_ALERT.b, 0.2))
	var fill_w := WAVE_BAR_W * clampf(_wave_progress, 0.0, 1.0)
	if fill_w > 0.5:
		var t_fill := _ht("ui_wave_fill_elite_v1.png" if _wave_elite else "ui_wave_fill_v1.png")
		if t_fill != null:
			# 只取贴图左侧 fill_w 宽的一段（量程随进度增长，贴图不拉伸变形）
			draw_texture_rect_region(t_fill, Rect2(bx, by, fill_w, WAVE_BAR_H),
				Rect2(0.0, 0.0, fill_w, float(t_fill.get_height())))
			# 游标：填充右端的指针（8x18，上下各探出条外 4px）
			var t_cap := _ht("ui_wave_cap_v1.png")
			if t_cap != null:
				draw_texture(t_cap, Vector2(bx + fill_w - 4.0, by - 4.0))
		else:
			var fill_box := _box_bar_fill_elite if _wave_elite else _box_bar_fill
			draw_style_box(fill_box, Rect2(bx, by, fill_w, WAVE_BAR_H))
	# 🆕 进度读数（数字优先 §5.2）：`已出 / 总数`，居中于条下
	#   🔴 §5.4：读数 = 等宽数字字体；「精英波」提示 = Medium 正文字体（CJK）
	var font := _Style.font_num()
	var font_cjk := _Style.font_medium()
	if font != null:
		if _wave_total > 0:
			var cnt := "%d / %d" % [_wave_spawned, _wave_total]
			var cw: float = font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(cx - cw * 0.5, by + 26.0), cnt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT_DIM)
		# 🟢 T1 反制窗口（玩法②）：精英标记**分态取源**（战斗=当前波 / 决策期=下一波预告）。
		#   🔴 决策期文案 = "下一波：精英波"（预告，仅决策期）；战斗态 = "精英波"（当前状态）。
		#   无数字、无倒计时、无进度条（T-E1③ / E-B12 零择时读数）。
		#   🆕 位置改到进度条**左侧右对齐**，避免与 WAVE 大字／读数行叠压。
		if _wave_elite and font_cjk != null:
			var et := ("精英波" if _wave_in_combat else "下一波：精英波")
			var ew: float = font_cjk.get_string_size(et, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font_cjk, Vector2(bx - 12.0 - ew, by + 9.0), et,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_ALERT)


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
