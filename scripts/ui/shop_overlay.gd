extends Control
##
## 商店抽屉覆盖层 —— GDD §2.4 C3 双焦点界面
##
## 切片3：双焦点布局 / 抽屉形态跟随五态 / 预算条常驻。
## 切片4：商品位填真实卡面 + 意图接线（I-2 / I-3）。
## 🆕 UI 优化轮：**视觉全部收敛到 `ui_style.gd`**（改造前本文件一个 StyleBox 都没有，
##   抽屉透明、商品位无边框、十余个按钮走 Godot 默认主题 → 违反 art-bible §5.1
##   「禁止使用系统默认控件」）。
##
## 🔴 C-3 / SR-R2 合规（骨架阶段就把**结构**钉死，后续填内容不得破）：
##   · 三个商品位**尺寸完全一致**（同一 custom_minimum_size、同一配色、同一字号）
##     → 杜绝 X3「用布局暗示推荐」；
##   · 源码内**禁止**出现 推荐 / 最优 / best / recommend / suggest 之类文案
##     （GDD §10.1 断言 10 会 grep 商店源码；切片4 自测 §9 会 grep 本文件与 gameplay 层）。
##
## 🔴 UI 不持有游戏状态（control-manifest §5）：本文件只读 `runtime.snapshot()`，
##    所有改动一律通过 `TimeDirector` 的意图信号发出，由 `ShopController` 接线。
##

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _Battle := preload("res://scripts/ui/battle_theme.gd")
var _hovered_slot := -1
var _hover_time := 0.0

const _Runtime := preload("res://scripts/gameplay/shop_runtime.gd")
const _Hover := preload("res://scripts/ui/card_hover.gd")
var _inner: VBoxContainer
var _info_row: HBoxContainer
var _hover: CanvasLayer
var _pointer := Vector2(-1000.0, -1000.0)

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")
const _Style := preload("res://scripts/ui/ui_style.gd")
const _CardText := preload("res://scripts/data/card_text.gd")

const SLOT_COUNT := 3        # 恒为 3（A4：保底不新增第 4 位）

# ---- 配色（青橙双极，art-bible §2.1）----
const C_BG := Color(0.07, 0.09, 0.12, 0.94)
const C_SLOT := Color(0.13, 0.17, 0.22, 1.0)   # 🔴 三个商品位完全一致（X3）
const C_ACCENT := Color(0.95, 0.62, 0.18, 1.0) # 橙（H1 买得起：价格辉金）
const C_CYAN := Color(0.24, 0.78, 0.83, 1.0)   # 青
const C_BUDGET := Color(0.24, 0.78, 0.83, 1.0)
const C_BUDGET_DRAINED := Color(0.86, 0.20, 0.20, 1.0)
const C_DIM := Color(0.55, 0.57, 0.60, 1.0)    # H1 买不起：价格灰（🔴 卡片本身不隐藏，X6）
const C_TEXT := Color(0.88, 0.90, 0.92, 1.0)
const C_WARN := Color(0.86, 0.20, 0.20, 1.0)   # E5：刷新买不起 → 价格标红

# 三张竖版商品卡共用尺寸；🆕 2026-11-10 参考图布局重排：卡是主角，整体放大
# （184×306 → 210×340），仍恒 3 位同尺寸（X3），窄屏保留滚动，购买与锁定入口始终可达。
const SLOT_SIZE := Vector2(210.0, 340.0)       # 🔴 三个位完全一致（X3）
## 描述块行数（恒 3 行 → 三个位等高同构）；
## 16px 字号实测行高 25px（Godot 默认字体 ascent+descent），3 行 = 75px。
const DESC_LINES := 3
const DESC_LINE_H := 25.0

## 顶部数值区（原为一行超长拼接串，改为 3 列网格 → 可扫读）
const STAT_KEYS: Array = ["废料", "主塔塔位", "塔位", "强化槽", "全局槽"]

var director: Node = null
var controller: Node = null   # ShopController（只读它的 runtime.snapshot()）

var _panel: PanelContainer
var _title: Label
var _mode_tag: Label
var _slots: Array = []        # Array[PanelContainer]
var _slot_chrome: Array = []  # 🆕 蓝图角标刻线（§5.5）：Array[Control]，accent 随可购性重绘
var _slot_name: Array = []    # Array[Label]
var _slot_art: Array = []     # 🆕 插画带（art/2d/cards）：Array[TextureRect]，刷新时按卡名填充
var _slot_tag: Array = []     # 🆕 Tag 电路符号芯片（§5.5）：Array[Label]
var _slot_rarity: Array = []  # 🆕 稀有度角标 ▲（art-bible §2.3 · P1-6）：Array[Label]
var _slot_kind: Array = []
var _slot_price_mark: Array = []   # 🆕 ✓/✗ 字形（§9.2 双通道）
var _slot_price_num: Array = []    # 🆕 价格数字（等宽字体 §5.5）
var _slot_price_unit: Array = []   # 🆕 「分」单位
var _slot_price_row: Array = []    # 价格 HBox（颜色统一改写用）
var _slot_desc: Array = []    # 🆕 效果描述块（恒 3 行，`card_text.gd` 派生）
var _slot_note: Array = []
var _slot_can_buy: Array = [] # 牌面购买可用状态
var _slot_lock: Array = []
var _stat_vals: Array = []    # Array[Label]
var _budget_fill: Panel
var _budget_label: Label
var _reroll_btn: Button
var _heavy_panel: VBoxContainer      # 重决策入口组（仅 SafeWindow 露出）
var _salvage_btn: Button
var _discard_btn: Button
var _detach_btn: Button
var _repair_btn: Button              # 🔒 T1 修复入口：处置受损塔（有 disabled 塔才亮 + 红点计数）
var _pending_label: Label
var _pending_box: VBoxContainer
var _no_scrap_label: Label           # 未接线兜底提示（替代原 `_scrap_label` 长串）


func _ready() -> void:
	_build()
	_refresh_size()
	var tree := get_tree()
	if tree != null:
		tree.root.size_changed.connect(_refresh_size)
		_bind_director_deferred()


func _bind_director_deferred() -> void:
	# 由 battle_shop.gd 显式注入；若没注入（单独跑本场景）就按 group 找
	if director == null:
		director = get_tree().get_first_node_in_group("time_director")
	if director != null and not director.is_connected("drawer_mode_changed", _on_drawer_mode_changed):
		director.state_changed.connect(_on_state_changed)
		director.budget_changed.connect(_on_budget_changed)
		director.drawer_mode_changed.connect(_on_drawer_mode_changed)
	_on_drawer_mode_changed(-1)
	if director != null:
		_on_budget_changed(director.sm.budget_left, director.sm.budget_max)
		_on_state_changed(-1, director.sm.state)


func bind_director(d: Node) -> void:
	director = d
	call_deferred("_bind_director_deferred")


func bind_controller(c: Node) -> void:
	controller = c
	if c == null:
		return
	if not c.is_connected("shop_changed", _refresh_shop):
		c.shop_changed.connect(_refresh_shop)
	if not c.is_connected("run_changed", _refresh_shop):
		c.run_changed.connect(_refresh_shop)
	call_deferred("_refresh_shop")


func _runtime_snapshot() -> Dictionary:
	if controller == null or controller.runtime == null:
		return {}
	return controller.runtime.snapshot()


# ---------------------------------------------------------------------------
#  布局
# ---------------------------------------------------------------------------
func _refresh_size() -> void:
	var vs := get_viewport().get_visible_rect().size
	# 🆕 2026-11-10 参考图布局：大卡横排顶部居中，战场保持可见可玩；
	#   卡组加宽（700 容 3×210 卡），上移贴顶（104 → 88）给下方提示行与信息带留白。
	var w := minf(700.0, vs.x - 32.0)
	var height := 394.0
	if _inner != null:
		height = _inner.get_combined_minimum_size().y + 20.0
	height = minf(height, maxf(220.0, vs.y - 276.0))
	position = Vector2((vs.x - w) * 0.5, 88.0)
	size = Vector2(w, height)



func _build() -> void:
	_hover = _Hover.new()
	add_child(_hover)
	# 🔴 离树构造（`tests/run_ui_style_asserts.gd` 只调 `_build()`）时 get_viewport() 为 null。
	var vp := get_viewport()
	if vp != null:
		vp.mouse_exited.connect(func() -> void: _pointer = Vector2(-1000.0, -1000.0))
	# 外层仅承载布局，空样式去除商店底板和边框。
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var inner := VBoxContainer.new()
	_inner = inner
	inner.add_theme_constant_override("separation", 10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	# ---- 标题行：标题 + 右侧模式徽标（层级 §5.2：文字 L2）----
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	inner.add_child(title_row)
	title_row.hide()
	_title = _Style.label("建筑商店", 24, _Style.C_WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	var close := Button.new()
	close.text = "收起 · Tab"
	_Battle.button(close)
	close.pressed.connect(func() -> void:
		if director != null:
			director.close_shop())
	title_row.add_child(close)



	# （🆕 2026-11-10）决策预算 / 刷新 / 模式徽标收拢进卡组下方信息带 —— 见 slots_row 之后。

	# ---- 槽位占用读数（3 列网格；原为一行 5 组数字拼接，难以扫读）----
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	inner.add_child(grid)
	grid.hide()
	for key in STAT_KEYS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(_Style.label("建筑" if key == "塔位" else String(key), _Style.FONT_MIN, _Style.C_TEXT_DIM))
		var val := _Style.label("--", _Style.FONT_MIN, _Style.C_TEXT)
		cell.add_child(val)
		_stat_vals.append(val)
		grid.add_child(cell)
		if key in ["废料", "主塔塔位"] or (not _Runtime.EFFECT_CARDS_ENABLED and key in ["强化槽", "全局槽"]):
			cell.hide()

	_no_scrap_label = _Style.label("", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	_no_scrap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_scrap_label.visible = false
	inner.add_child(_no_scrap_label)



	# ---- 3 个商品位（🔴 尺寸/亮度完全一致，X3 合规）----
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	inner.add_child(slots_row)
	for i in SLOT_COUNT:
		var slot := _make_slot(i)
		slots_row.add_child(slot)
		_slots.append(slot)

	# ---- 🆕 2026-11-10 参考图布局：卡组下方一行选牌提示（居中 · L2 辅助）----
	#    对齐参考图「请选择 N 张卡牌」的语言：提示收拢成一行，不再堆叠多段说明。
	var prompt := _Style.label("点击卡牌购买 · 1 / 2 / 3 快捷购买 · 建筑卡进入待放置队列，拖上战场落子",
		_Style.FONT_MIN, _Style.C_TEXT_DIM)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(prompt)

	# ---- 🆕 信息带：刷新 · 决策预算 · 模式徽标（原先三者两个隐藏一个在标题行，可见性混乱）----
	var info_row := HBoxContainer.new()
	_info_row = info_row
	info_row.add_theme_constant_override("separation", 14)
	inner.add_child(info_row)

	# 刷新按钮（E5：买不起置灰 + 价格标红）
	_reroll_btn = Button.new()
	_reroll_btn.text = "刷新"
	_reroll_btn.tooltip_text = "R 刷新商店"
	_Battle.button(_reroll_btn)
	# 🆕 重掷图标（资产包 v1 批次②）：缺失时降级为纯文本（icon() 判空）
	var reroll_tex := _Style.icon("ic_reroll")
	if reroll_tex != null:
		_reroll_btn.icon = reroll_tex
		_reroll_btn.add_theme_constant_override("icon_max_width", 20)
	_reroll_btn.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("reroll_requested"))
	info_row.add_child(_reroll_btn)

	# 决策预算（减速预算）—— 只读 TimeDirector 快照的呈现，恢复可见（参考图：信息一行收拢）
	var budget_bg := Panel.new()
	budget_bg.custom_minimum_size = Vector2(240.0, 14.0)
	budget_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	budget_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	budget_bg.add_theme_stylebox_override("panel", _Style.inset())
	info_row.add_child(budget_bg)
	_budget_fill = Panel.new()
	_budget_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_budget_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_budget_fill.add_theme_stylebox_override("panel", _Style.bar_fill(C_BUDGET))
	budget_bg.add_child(_budget_fill)
	_budget_label = _Style.label("--", _Style.FONT_MIN, _Style.C_TEXT)
	_budget_label.custom_minimum_size = Vector2(96.0, 0.0)
	_budget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_row.add_child(_budget_label)

	# 模式徽标（轻决策 / 重决策 · 安全窗）—— 靠右收尾
	_mode_tag = _Style.label("轻决策", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	_mode_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(_mode_tag)

	# ---- 待放置队列（Q-SR5 跨波保留 · E2 角标持续提醒）----
	_pending_label = _Style.label("待放置队列（0）", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	inner.add_child(_pending_label)
	_pending_box = VBoxContainer.new()
	_pending_box.add_theme_constant_override("separation", 4)
	inner.add_child(_pending_box)

	# 🆕 放置模式**不在这里出按钮**：GDD §2.1 规定 ⑤ 态抽屉收起、战场全屏，
	#    `_refresh_mode()` 的 `visible = drawer != CLOSED` 会把整棵控件树隐藏 ⇒
	#    改造前这里的 6 个塔位按钮是**永远的死代码**，这正是「买了建筑卡放不下」的根因。
	#    落子改走战场：`monster_layer._draw_placement_marks()` 画 ＋/↑/✕ 高亮，
	#    点击 → `slot_place_requested`（见 `time_director.gd` / `shop_controller.gd`）。

	# ---- 重决策入口组（🔴 仅 SafeWindow 露出；战斗中置灰且不响应，T-C1 / E16）----
	_heavy_panel = VBoxContainer.new()
	_heavy_panel.add_theme_constant_override("separation", 6)
	inner.add_child(_heavy_panel)
	_heavy_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER


	var heavy_grid := GridContainer.new()
	heavy_grid.columns = 4
	heavy_grid.add_theme_constant_override("h_separation", 8)
	heavy_grid.add_theme_constant_override("v_separation", 6)
	_heavy_panel.add_child(heavy_grid)

	_discard_btn = _mk_heavy_btn("弃卡", "unavail")
	_detach_btn = _mk_heavy_btn("卸下改投", "unavail")
	_salvage_btn = _mk_heavy_btn("拆除回收", "normal")
	_repair_btn = _mk_heavy_btn("处置受损塔", "danger")
	for b in [_discard_btn, _detach_btn, _salvage_btn, _repair_btn]:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heavy_grid.add_child(b)
		if not _Runtime.EFFECT_CARDS_ENABLED and b in [_discard_btn, _detach_btn]:
			b.hide()
	_salvage_btn.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("salvage_requested"))
	_repair_btn.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("repair_requested"))

	# ---- 留白撑开 ----
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)


func _mk_heavy_btn(text: String, variant: String) -> Button:
	var b := Button.new()
	b.text = text
	_Battle.button(b)
	return b


## 单个商品位。🔴 三个位**逐字同构**：同一 SLOT_SIZE、同一字号、同一按钮变体 ——
##   任何逐位差异都会构成 X3「用布局暗示」。
## 🆕 蓝图卡面（art-bible §5.5 · 2026-11-07）：直角细描边底座 + 四角刻线 chrome +
##   Tag 电路符号芯片 + 等宽数字价格。
func _make_slot(_i: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = SLOT_SIZE            # 🔴 三个位完全一致
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _Battle.card())
	p.clip_contents = true
	# 背景独立于插画带，铺满整张卡；内容仍保留原有内边距。
	var background_layer := Control.new()
	background_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(background_layer)
	var backdrop := TextureRect.new()
	backdrop.self_modulate = _Style.CARD_BACKDROP_TINT
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.visible = false
	background_layer.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 抵消容器内边距，让背景覆盖整框，文字排版仍使用原边距。
	var card_style := p.get_theme_stylebox("panel")
	backdrop.offset_left = -card_style.get_content_margin(SIDE_LEFT)
	backdrop.offset_top = -card_style.get_content_margin(SIDE_TOP)
	backdrop.offset_right = card_style.get_content_margin(SIDE_RIGHT)
	backdrop.offset_bottom = card_style.get_content_margin(SIDE_BOTTOM)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	p.add_child(vb)

	# 序号（L3 辅助，钢灰）+ 稀有度角标（§2.3 · P1-6：▲ 数 1–5 + 边框色 = 双通道冗余）
	var idx_row := HBoxContainer.new()
	idx_row.add_theme_constant_override("separation", 6)
	vb.add_child(idx_row)
	var idx := _Style.label("%d" % (_i + 1), _Style.FONT_MIN, _Style.C_TEXT_DIM)
	idx.tooltip_text = "快捷键 %d 购买" % (_i + 1)
	idx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idx_row.add_child(idx)
	var pips := _Style.label("", _Style.FONT_MIN, _Style.C_STEEL)
	pips.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	idx_row.add_child(pips)
	_slot_rarity.append(pips)

	# 卡名行：卡名（L1，Black 展示字重）+ 右侧 Tag 电路符号芯片（§5.5）
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	vb.add_child(name_row)
	var nm := _Style.label("—", 20, _Style.C_WHITE)
	_Style.apply_font(nm, "display")              # §5.4：卡名 = Black 展示字重（L1 主信息）
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	_slot_name.append(nm)
	var tag_chip := _Style.label("", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	tag_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vb.add_child(tag_chip)
	_slot_tag.append(tag_chip)

	# 竖版卡面的插画区：透明底素材保持比例，缺图时使用空底座。
	#    资产缺失 / headless 未导入 → card_art() 返回 null → 整带隐藏（版式回落无图）。
	#    🔴 构建时只建空带：卡名在 `_refresh_shop` 刷新时才落到槽位（此处 `nm` 是占位
	#    Label，不是卡名字符串），纹理由刷新链路按卡名填充（`_slot_art`）。
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0.0, 136.0)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.visible = false
	var art_frame := PanelContainer.new()
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	vb.add_child(art_frame)
	art.set_meta("rarity_backdrop", backdrop)
	art_frame.add_child(art)
	_slot_art.append(art)

	# 卡种（L2 常规）
	var kind := _Style.label("—", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(kind)
	kind.max_lines_visible = 1
	kind.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_slot_kind.append(kind)

	# 价格行（L1 重要）：✓/✗ 标记（§9.2 双通道）+ **等宽数字**（§5.5）+ 单位
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 4)
	vb.add_child(price_row)
	price_row.hide()
	_slot_price_row.append(price_row)
	# 🆕 批次③：✓/✗ 从 Unicode 字形升级为 ic_check/ic_cross 图标（资产包 v1）——
	#    形状通道不变（§9.2 红线①），颜色跟随价格（_set_price_color 改 modulate）；
	#    图标缺失（headless）→ 回落 Unicode 字形 Label，双通道不缺席。
	var check_tex := _Style.icon("ic_check")
	var cross_tex := _Style.icon("ic_cross")
	var price_mark: Control
	if check_tex != null and cross_tex != null:
		var mark_ic := TextureRect.new()
		mark_ic.custom_minimum_size = Vector2(16.0, 16.0)
		mark_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark_ic.visible = false
		mark_ic.set_meta("check", check_tex)
		mark_ic.set_meta("cross", cross_tex)
		price_row.add_child(mark_ic)
		price_mark = mark_ic
	else:
		var mark_lb := _Style.label("", _Style.FONT_MIN, C_DIM)
		price_row.add_child(mark_lb)
		price_mark = mark_lb
	_slot_price_mark.append(price_mark)
	# 🆕 废料图标（资产包 v1 批次②）：missing 时降级为纯文本（icon() 判空返回 null）
	var scrap_tex := _Style.icon("ic_scrap")
	if scrap_tex != null:
		var scrap_ic := TextureRect.new()
		scrap_ic.texture = scrap_tex
		scrap_ic.custom_minimum_size = Vector2(18.0, 18.0)
		scrap_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scrap_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		scrap_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scrap_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		price_row.add_child(scrap_ic)
	var price_num := _Style.label("--", 22, C_DIM)
	_Style.apply_font(price_num, "num")           # §5.5：价格数字等宽（蓝图仪表读数）
	price_row.add_child(price_num)
	_slot_price_num.append(price_num)
	var price_unit := _Style.label("分", _Style.FONT_MIN, C_DIM)
	price_row.add_child(price_unit)
	_slot_price_unit.append(price_unit)



	# 🆕 效果描述块（§5.2 L2 文字；比备注亮一档 —— 它是「这张卡干什么」的正面信息，
	#   备注只是条件事实）。🔴 高度固定 DESC_LINES 行：三个位的描述块**等高同构**（X3）。
	var desc := _Style.label("", _Style.FONT_MIN, _Style.C_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0.0, DESC_LINE_H * float(DESC_LINES))
	vb.add_child(desc)
	desc.hide()
	_slot_desc.append(desc)

	# 事实备注（H2/H3/H4/H5/H6/H9）—— 只在有事实时占位（min 0），否则不占高度
	var note := _Style.label("", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	note.hide()
	_slot_note.append(note)

	# 撑开 → 三位等高时按钮对齐底部（不靠 padding 凑）
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(gap)

	# 锁头是卡面上的独立图标热区，不占底部按钮行。
	var lock := Control.new()
	lock.custom_minimum_size = Vector2(28.0, 28.0)
	lock.mouse_filter = Control.MOUSE_FILTER_STOP
	lock.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lock.set_meta("enabled", false)
	lock.set_meta("locked", false)
	lock.draw.connect(func() -> void: _draw_lock(lock))
	lock.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			lock.accept_event()
			if director != null and bool(lock.get_meta("enabled", false)):
				director.emit_signal("lock_toggled", _i))
	idx_row.add_child(lock)
	_slot_lock.append(lock)
	_slot_can_buy.append(false)
	_ignore_card_content(vb, lock)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			p.accept_event()
			if director != null and _slot_can_buy[_i]:
				director.emit_signal("buy_requested", _i))

	# 🆕 蓝图 chrome（§5.5）：四角刻线，**后于** vb 加入 → 画在内容之上。
	#    accent 存 meta，`_refresh_shop` 按可购性改写并 queue_redraw（不在 _draw 里 new）。
	var chrome := Control.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	chrome.set_meta("accent", "normal")
	chrome.draw.connect(func() -> void: _draw_slot_chrome(chrome))
	p.add_child(chrome)
	chrome.hide()
	_slot_chrome.append(chrome)
	return p


func _ignore_card_content(node: Control, lock: Control) -> void:
	if node == lock:
		return
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_ignore_card_content(child, lock)


func _draw_lock(icon: Control) -> void:
	var locked := bool(icon.get_meta("locked", false))
	var color := C_ACCENT if locked else C_TEXT
	if not bool(icon.get_meta("enabled", false)):
		color = C_DIM
	# 闭合 / 打开的锁梁以形状区分状态，避免依赖字体字形。
	var center := Vector2(14.0, 11.0) if locked else Vector2(19.0, 8.0)
	icon.draw_arc(center, 5.0, PI, TAU, 20, color, 2.0, true)
	icon.draw_line(center + Vector2(-5, 0), Vector2(center.x - 5, 15), color, 2.0, true)
	icon.draw_line(center + Vector2(5, 0), center + Vector2(5, 4), color, 2.0, true)
	icon.draw_rect(Rect2(7, 14, 14, 11), color, false, 2.0)
	icon.draw_circle(Vector2(14, 19), 1.5, color)


## §5.5 蓝图 chrome：四角 L 形刻线（工程图角标语言）。
##   accent：normal = 钢灰 / affordable = 耀青（与描边第二通道同源）/ dim = 压暗。
func _draw_slot_chrome(c: Control) -> void:
	var accent: String = String(c.get_meta("accent", "normal"))
	var col := Color(_Style.C_STEEL.r, _Style.C_STEEL.g, _Style.C_STEEL.b, 0.55)
	if accent == "affordable":
		col = Color(_Style.C_ALLY.r, _Style.C_ALLY.g, _Style.C_ALLY.b, 0.90)
	elif accent == "dim":
		col = Color(_Style.C_STEEL.r, _Style.C_STEEL.g, _Style.C_STEEL.b, 0.30)
	var leg := 9.0
	var t := 2.0
	var r := c.size
	# 左上
	c.draw_line(Vector2(0.0, 0.0), Vector2(leg, 0.0), col, t)
	c.draw_line(Vector2(0.0, 0.0), Vector2(0.0, leg), col, t)
	# 右上
	c.draw_line(Vector2(r.x - leg, 0.0), Vector2(r.x, 0.0), col, t)
	c.draw_line(Vector2(r.x, 0.0), Vector2(r.x, leg), col, t)
	# 左下
	c.draw_line(Vector2(0.0, r.y - leg), Vector2(0.0, r.y), col, t)
	c.draw_line(Vector2(0.0, r.y), Vector2(leg, r.y), col, t)
	# 右下
	c.draw_line(Vector2(r.x - leg, r.y), Vector2(r.x, r.y), col, t)
	c.draw_line(Vector2(r.x, r.y - leg), Vector2(r.x, r.y), col, t)


# ---------------------------------------------------------------------------
#  商品位刷新（事件驱动：controller.shop_changed / run_changed，🔴 不每帧重算，SR-6）
# ---------------------------------------------------------------------------
func _refresh_shop() -> void:
	call_deferred("_refresh_size")
	var s := _runtime_snapshot()
	if s.is_empty():
		_no_scrap_label.visible = true
		_no_scrap_label.text = "未接线：读不到运行时快照"
		for i in STAT_KEYS.size():
			_stat_vals[i].text = "--"
		for i in SLOT_COUNT:
			_slot_name[i].text = "—"
			_slot_art[i].visible = false
			_slot_art[i].get_parent().hide()
			_slot_art[i].get_meta("rarity_backdrop").hide()
			_slots[i].set_meta("rarity", "")
			_slot_tag[i].text = ""
			_slot_rarity[i].text = ""
			_slot_kind[i].text = "—"
			if _slot_price_mark[i] is TextureRect:
				_slot_price_mark[i].visible = false
			else:
				_slot_price_mark[i].text = ""
			_slot_price_num[i].text = "--"
			_slot_price_unit[i].text = ""
			_slot_price_row[i].hide()
			_set_price_color(i, C_DIM)
			_slot_desc[i].text = ""
			_slot_note[i].text = ""
			_slots[i].add_theme_stylebox_override("panel", _Battle.card())
			_set_chrome_accent(i, "dim")
			_slot_can_buy[i] = false
			_slot_lock[i].set_meta("enabled", false)
		_reroll_btn.disabled = true
		_clear_children(_pending_box)
		return
	_no_scrap_label.visible = false

	# ---- 槽位占用事实（H7）：3 列网格 ----
	var su: Dictionary = s.get("slot_usage", {})
	_stat_vals[0].text = "%.0f" % float(s["scrap"])
	_stat_vals[1].text = str(int(s["core_tower_slot"]))
	_stat_vals[2].text = "%d / %d" % [int(su.get("tower", 0)), int(su.get("tower_max", 6))]
	_stat_vals[3].text = "%d / %d" % [int(su.get("enh", 0)), int(su.get("enh_max", 5))]
	_stat_vals[4].text = "%d / %d" % [int(su.get("global", 0)), int(su.get("global_max", 3))]

	for i in SLOT_COUNT:
		var nm := String(s["offers"][i])
		var price := float(s["prices"][i])
		var ok := bool(s["affordable"][i]) and bool(s["legal"][i])
		# C2 高亮事实（H2/H3/H5/H6/H9；H1/H4/H8 已在 affordable/at_cap/notes）
		var hl: Dictionary = s.get("highlights", {}).get(str(i), {})
		if nm == "":
			_slot_name[i].text = "—"
			_slot_art[i].visible = false
			_slot_art[i].get_parent().hide()
			_slot_art[i].get_meta("rarity_backdrop").hide()
			_slots[i].set_meta("rarity", "")
			_slot_tag[i].text = ""
			_slot_rarity[i].text = ""
			_slot_kind[i].text = "此位无卡"
			if _slot_price_mark[i] is TextureRect:
				_slot_price_mark[i].visible = false
			else:
				_slot_price_mark[i].text = ""
			_slot_price_num[i].text = "--"
			_slot_price_unit[i].text = ""
			_slot_price_row[i].hide()
			_set_price_color(i, C_DIM)
			_slot_desc[i].text = ""
			_slot_note[i].text = String(s["notes"][i])
			_slots[i].add_theme_stylebox_override("panel", _Battle.card())
			_set_chrome_accent(i, "dim")
		else:
			_slot_name[i].text = _CardText.display_name(nm)
			# 🆕 插画带按卡名取图：缺失（未出图 / headless）→ 隐藏整带，版式回落
			var art_tex := _Style.card_art(nm)
			_slot_art[i].texture = art_tex
			_slot_art[i].visible = art_tex != null
			_slot_art[i].get_parent().visible = art_tex != null
			# 🆕 稀有度（§2.3 · P1-6）：边框色/粗细 + ▲ 角标数 —— 双通道，不只靠颜色。
			#    稀有度由 card_text 只读派生自抽取权重（SSOT），改权重卡面自动跟随。
			var rar := _CardText.rarity(nm)
			_slots[i].set_meta("rarity", rar)
			var backdrop: TextureRect = _slot_art[i].get_meta("rarity_backdrop")
			backdrop.texture = _Style.card_backdrop(rar, nm)
			backdrop.visible = true
			_slot_rarity[i].text = "▲".repeat(_Style.rarity_pips(rar))
			_slot_rarity[i].add_theme_color_override("font_color", _Style.rarity_color(rar))
			# 🆕 蓝图卡面（§5.5）：Tag 电路符号芯片（字形 + 颜色双通道，§9.2①）
			var tg := _CardText.tag_of(nm)
			if tg != "":
				_slot_tag[i].text = "%s %s" % [_Style.tag_glyph(tg), _CardText.tag_cn(tg)]
				_slot_tag[i].add_theme_color_override("font_color", _Style.tag_color(tg))
			else:
				_slot_tag[i].text = ""
			# 🆕 效果描述块：卡名 + 卡种之外，告诉玩家「这张卡干什么」（恒 3 行）
			_slot_desc[i].text = _CardText.describe(nm)
			# H2：Tag 协同 → 卡种行加标记（视觉编码不写推荐类词）
			var kind_txt := String(s["kinds"][i])
			if bool(hl.get("tag_synergy", false)):
				kind_txt += "  ◈协同"
			_slot_kind[i].text = kind_txt
			# H1：价格数字用辉金 vs 灰（🔴 卡片本身始终可见，X6）
			# 🔴 T-P6-06 S2（art-bible §9.2 红线①「任何游戏状态不得仅靠颜色传达」）：
			#   买得起/买不起除**颜色**外，价格前加 **✓/✗ 字形冗余**（纯加法；配色判据一字不改）。
			var _aff := bool(s["affordable"][i])
			if _slot_price_mark[i] is TextureRect:
				_slot_price_mark[i].texture = _slot_price_mark[i].get_meta("cross" if not _aff else "check")
				_slot_price_mark[i].visible = true
			else:
				_slot_price_mark[i].text = "✓" if _aff else "✗"
			_slot_price_num[i].text = "%.0f" % price
			_slot_price_unit[i].text = "分"
			# 🆕 2026-11-10 接手修：价格行在 _make_slot 里默认隐藏，取消底部「购买」按钮后
			#    卡面必须自己显示价格（原点击式布局漏了 show()，实机卡面完全看不到售价）。
			_slot_price_row[i].show()
			_set_price_color(i, C_ACCENT if _aff else C_DIM)
			# 卡片描边 = 稀有度色（§2.3）；可购性由 ✓/✗ + 价格色 + 角刻线表达（第二通道）
			_slots[i].add_theme_stylebox_override("panel",
				_Battle.card(i == _hovered_slot, rar))
			_set_chrome_accent(i, "affordable" if _aff else "normal")
			var note := String(s["notes"][i])
			if note == "" and bool(s["at_cap"][i]):
				note = "已达上限 (+0%)"        # H4
			# C2 高亮事实拼接（🔴 只标事实，SR-R2；顺序：H5 层数 / H3 +1档 / H6 κ / H9 ΔDPS）
			var extra: Array = []
			if String(hl.get("layer_next", "")) != "":
				extra.append(String(hl["layer_next"]))          # H5
			if bool(hl.get("plus_one", false)):
				extra.append("+1 档位")                          # H3
			if String(hl.get("kappa_preview", "")) != "":
				extra.append(String(hl["kappa_preview"]))       # H6
			if float(hl.get("delta_pct", 0.0)) > 0.0001:
				extra.append("主塔秒伤 +%.0f%%" % (float(hl["delta_pct"]) * 100.0))  # H9
			if not extra.is_empty():
				note = (note + " · " if note != "" else "") + " · ".join(extra)
			_slot_note[i].text = note
		_slot_can_buy[i] = ok and nm != ""
		_slots[i].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _slot_can_buy[i] else Control.CURSOR_ARROW
		# 锁定：3 位中可锁 1；锁定位显示"已锁"
		var locked := (int(s["lock_index"]) == i)
		_slot_lock[i].set_meta("locked", locked)
		_slot_lock[i].queue_redraw()
		_slot_lock[i].set_meta("enabled", nm != "")
		_slot_lock[i].tooltip_text = "已锁定，点击解锁" if locked else "点击锁定：下次刷新保留此商品"

	# ---- 刷新按钮：显示 5+3n 的实时成本（E5：买不起置灰 + 标红）----
	var rc := float(s["reroll_cost"])
	_reroll_btn.text = "刷新 · %.0f" % rc
	var can_reroll := float(s["scrap"]) >= rc
	_reroll_btn.disabled = not can_reroll
	_reroll_btn.add_theme_color_override("font_color", C_TEXT if can_reroll else C_WARN)

	# ---- 🔒 T1 修复入口：统计受损塔（disabled）数，更新「处置受损塔」按钮（红点计数）----
	_refresh_repair_btn(s)

	_refresh_pending(s)


## 价格行统一着色（✓/✗ 与数字同色；「分」单位恒辅助灰 —— 数字才是主通道 §5.2）。
func _set_price_color(i: int, col: Color) -> void:
	if _slot_price_mark[i] is TextureRect:
		_slot_price_mark[i].modulate = col
	else:
		_slot_price_mark[i].add_theme_color_override("font_color", col)
	_slot_price_num[i].add_theme_color_override("font_color", col)
	_slot_price_unit[i].add_theme_color_override("font_color", C_DIM)


## 蓝图 chrome accent 改写 + 重绘（🔴 只改 meta，不在刷新路径 new StyleBox）。
func _set_chrome_accent(i: int, accent: String) -> void:
	var c: Control = _slot_chrome[i]
	if String(c.get_meta("accent", "")) == accent:
		return
	c.set_meta("accent", accent)
	c.queue_redraw()


## 🔒 T1 修复入口 UI（Q-T4 三选一 · SR-R2 只标事实）：
##   · 统计 snapshot `slots` 里 `disabled=true` 的塔数；
##   · 有受损塔 → 按钮显示计数（"处置受损塔 (N)"）；无 → 文案回落"处置受损塔"。
##   · 🔴 可否点 = 有受损塔 **且** 安全窗（heavy_on）——非安全窗一律置灰（T-C1 / E16）。
##   · 🔴 只标事实（有几座受损），不指示该修还是该拆。
func _refresh_repair_btn(s: Dictionary) -> void:
	var n := 0
	for row in s.get("slots", []):
		if bool(row.get("disabled", false)):
			n += 1
	var heavy_on := false
	if director != null:
		heavy_on = (int(director.sm.clock()["drawer"]) == _TSM.Drawer.HEAVY)
	if n > 0:
		_repair_btn.text = "处置受损塔 (%d)" % n
		_repair_btn.add_theme_color_override("font_color", C_WARN)
	else:
		_repair_btn.text = "处置受损塔"
		_repair_btn.add_theme_color_override("font_color", C_DIM)
	# 🔴 可否点 = 有受损塔 且 安全窗（两者缺一不可）
	_repair_btn.disabled = not (n > 0 and heavy_on)
	_repair_btn.visible = n > 0
	_heavy_panel.hide()


func _refresh_pending(s: Dictionary) -> void:
	# 已购买建筑统一在底部背包展示，商店不再重复列队列。
	_clear_children(_pending_box)
	_pending_label.hide()
	_pending_box.hide()


## 🔴 放置模式（⑤）只能从 ②③④ 进入（GDD §2.1 转换表）；战斗态 ① 下不响应。
func _can_enter_placement() -> bool:
	if director == null or director.sm == null:
		return false
	return int(director.sm.state) in [
		_TSM.State.SHOP_DILATED, _TSM.State.SHOP_REAL_TIME, _TSM.State.SAFE_WINDOW]


func _clear_children(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------------------
#  状态响应
# ---------------------------------------------------------------------------
func _on_state_changed(_from_state: int, _to_state: int) -> void:
	if director == null:
		return
	_refresh_mode(int(director.sm.clock()["drawer"]))
	_refresh_shop()


func _on_drawer_mode_changed(_mode: int) -> void:
	if director == null:
		_refresh_mode(_TSM.Drawer.CLOSED)
		return
	_refresh_mode(int(director.sm.clock()["drawer"]))


func _refresh_mode(drawer: int) -> void:
	if drawer < 0:
		drawer = _TSM.Drawer.CLOSED
	visible = (drawer != _TSM.Drawer.CLOSED)
	if not visible:
		return
	match drawer:
		_TSM.Drawer.LIGHT:
			_mode_tag.text = "轻决策"
			_mode_tag.add_theme_color_override("font_color", _Style.C_ALLY)
		_TSM.Drawer.HEAVY:
			_mode_tag.text = "重决策 · 安全窗"
			_mode_tag.add_theme_color_override("font_color", _Style.C_GOLD)
	# 🔴 T-C1 / E16：重决策入口**仅**安全窗可用，其余态置灰 + 不响应
	var heavy_on := (drawer == _TSM.Drawer.HEAVY)
	_heavy_panel.hide()
	_discard_btn.disabled = not heavy_on
	_detach_btn.disabled = not heavy_on
	_salvage_btn.disabled = not heavy_on
	# 🔒 T1 修复入口：基础置灰跟随安全窗；具体「有受损塔才亮 + 计数」在 _refresh_shop 里按 snapshot 更新
	_repair_btn.disabled = not heavy_on


func _on_budget_changed(left: float, budget_max: float) -> void:
	var ratio: float = 0.0
	if budget_max > 0.0:
		ratio = clampf(left / budget_max, 0.0, 1.0)
	_budget_fill.anchor_right = ratio
	var col := C_BUDGET_DRAINED if left <= 0.0 else C_BUDGET
	_budget_fill.add_theme_stylebox_override("panel", _Style.bar_fill(col))
	_budget_label.text = "%.1f / %.0f s" % [left, budget_max]
	if left <= 0.0:
		_budget_label.text += " 已耗尽"


func _process(delta: float) -> void:
	if _hover == null:
		return
	if is_visible_in_tree() and controller != null and controller.runtime != null:
		var mouse := _pointer
		for i in _slots.size():
			var card: Control = _slots[i]
			if card.get_global_rect().has_point(mouse):
				if _hovered_slot != i:
					_set_hovered_slot(i)
				_hover_time += delta
				if _hover_time < 0.4:
					return
				var nm: String = controller.runtime.offer_at(i)
				var info := "价格：%.0f 废料" % controller.runtime.price_at(i)
				if _slot_note[i].text != "":
					info += "\n" + _slot_note[i].text
				_hover.show_card(nm, card.get_global_rect(), info)
				return
	_hover.clear()
	_set_hovered_slot(-1)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer = event.position


func _set_hovered_slot(index: int) -> void:
	if _hovered_slot == index:
		return
	_hovered_slot = index
	_hover_time = 0.0
	if _hover != null:
		_hover.clear()
	for i in _slots.size():
		_slots[i].add_theme_stylebox_override("panel", _Battle.card(i == index, String(_slots[i].get_meta("rarity", ""))))
