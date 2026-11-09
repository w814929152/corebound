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

# 卡片高度随内容重排后上调（原 150×190 放不下「卡名 26px + 价格 + 备注 + 双按钮」）。
#   🆕 197 → 340：卡面新增**效果描述块**（恒 3 行，见 `_slot_desc`）——
#      改造前卡上只有「卡名 + 卡种」，玩家看不出 FireUp 和 Cannon 分别干什么。
#      描述块用 `card_text.gd` 派生的 3 行文字（定位 / 数值 / 流程），
#      高度**固定**（三个位完全一致 → X3），不在运行时随文字长短伸缩。
#   🔴 X3：仍由**这一个常量**决定，三位共用；`tests/run_slice4_scene_smoke.gd` 的
#      SLOT_W/SLOT_H 必须同步（该冒烟按像素反查三个位）。
#   🆕 352 → 424（2026-11-08）：卡面新增**插画带**（art/2d/cards 批次②③，恒 72px 高）——
#      keyout 透明底插画经 `_Style.card_art()` 接入，缺失时整带隐藏（降级为无图版式）。
const SLOT_SIZE := Vector2(168.0, 424.0)       # 🔴 三个位完全一致（X3）
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
var _slot_buy: Array = []     # Array[Button]
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
	var vw := float(get_viewport().get_visible_rect().size.x)
	var w := _ShopLayout.drawer_width(vw)
	# PRESET_RIGHT_WIDE: L=1,T=0,R=1,B=1 → 靠右；再用 offset_left 拉出宽度
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	set_offset(SIDE_LEFT, -w)
	set_offset(SIDE_RIGHT, 0.0)
	set_offset(SIDE_TOP, 0.0)
	set_offset(SIDE_BOTTOM, 0.0)


func _build() -> void:
	# 🔴 抽屉底座：深色底 + 亮色描边（art-bible §5.1）。改造前此处无 StyleBox ⇒ 全透明。
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _Style.panel())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	margin.add_child(inner)

	# ---- 标题行：标题 + 右侧模式徽标（层级 §5.2：文字 L2）----
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	inner.add_child(title_row)
	_title = _Style.label("商店", 20, _Style.C_WHITE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	_mode_tag = _Style.label("轻决策", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	_mode_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(_mode_tag)

	inner.add_child(_Style.hline())

	# ---- 减速预算条（🔴 常驻可见，锚点 6 第 4 条）----
	var budget_row := HBoxContainer.new()
	budget_row.add_theme_constant_override("separation", 10)
	inner.add_child(budget_row)
	var budget_cap := _Style.label("减速预算", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	budget_cap.custom_minimum_size = Vector2(72.0, 0.0)
	budget_row.add_child(budget_cap)
	var budget_bg := Panel.new()
	budget_bg.custom_minimum_size = Vector2(0.0, 16.0)
	budget_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	budget_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	budget_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	budget_bg.add_theme_stylebox_override("panel", _Style.inset())
	budget_row.add_child(budget_bg)
	_budget_fill = Panel.new()
	_budget_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_budget_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_budget_fill.add_theme_stylebox_override("panel", _Style.bar_fill(C_BUDGET))
	budget_bg.add_child(_budget_fill)
	_budget_label = _Style.label("--", _Style.FONT_MIN, _Style.C_TEXT)
	_budget_label.custom_minimum_size = Vector2(96.0, 0.0)
	_budget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	budget_row.add_child(_budget_label)

	inner.add_child(_Style.hline())

	# ---- 槽位占用读数（3 列网格；原为一行 5 组数字拼接，难以扫读）----
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	inner.add_child(grid)
	for key in STAT_KEYS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(_Style.label(String(key), _Style.FONT_MIN, _Style.C_TEXT_DIM))
		var val := _Style.label("--", _Style.FONT_MIN, _Style.C_TEXT)
		cell.add_child(val)
		_stat_vals.append(val)
		grid.add_child(cell)

	_no_scrap_label = _Style.label("", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	_no_scrap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_scrap_label.visible = false
	inner.add_child(_no_scrap_label)

	inner.add_child(_Style.hline())

	# ---- 3 个商品位（🔴 尺寸/亮度完全一致，X3 合规）----
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	inner.add_child(slots_row)
	for i in SLOT_COUNT:
		var slot := _make_slot(i)
		slots_row.add_child(slot)
		_slots.append(slot)

	# 🆕 购买流程提示：**按卡种**说一次（三种卡各一行），不占卡面高度。
	#   改造前这类「买后要去哪」的信息完全缺失 —— 玩家买了建筑卡不知道要再进安全窗落子。
	var flow := _Style.label(_CardText.FLOW_HINT, _Style.FONT_MIN, _Style.C_TEXT_DIM)
	flow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(flow)

	# ---- 刷新按钮（E5：买不起置灰 + 价格标红）----
	_reroll_btn = Button.new()
	_reroll_btn.text = "刷新 R"
	_Style.button(_reroll_btn, "normal")
	# 🆕 重掷图标（资产包 v1 批次②）：缺失时降级为纯文本（icon() 判空）
	var reroll_tex := _Style.icon("ic_reroll")
	if reroll_tex != null:
		_reroll_btn.icon = reroll_tex
		_reroll_btn.add_theme_constant_override("icon_max_width", 20)
	_reroll_btn.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("reroll_requested"))
	inner.add_child(_reroll_btn)

	inner.add_child(_Style.hline())

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
	_heavy_panel.add_child(_Style.hline())
	_heavy_panel.add_child(_Style.label("重决策（仅安全窗）", _Style.FONT_MIN, _Style.C_TEXT_DIM))

	var heavy_grid := GridContainer.new()
	heavy_grid.columns = 2
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
	_Style.button(b, variant)
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
	p.add_theme_stylebox_override("panel", _Style.card_blueprint())
	# 🆕 资产包 v6：9-slice 中性承托板（v2-hud §7 #2 遗留件）。
	#    🔴 必须**先于** vb 加入 —— PanelContainer 会把每个子节点铺满 content rect，
	#       先加者画在下、后加者画在上；末尾的 chrome 仍保持最上层。
	#    缺贴图 / headless 未导入 → 整层不建，版式逐字回落改前状态。
	#    承托板不染色也不做四角刻线：稀有度由 card_blueprint 边框、四角由 chrome 承担。
	var plate_tex := _Style.slot_plate_tex()
	if plate_tex != null:
		var plate := NinePatchRect.new()
		plate.texture = plate_tex
		plate.patch_margin_left = 12
		plate.patch_margin_right = 12
		plate.patch_margin_top = 12
		plate.patch_margin_bottom = 12
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(plate)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	p.add_child(vb)

	# 序号（L3 辅助，钢灰）+ 稀有度角标（§2.3 · P1-6：▲ 数 1–5 + 边框色 = 双通道冗余）
	var idx_row := HBoxContainer.new()
	idx_row.add_theme_constant_override("separation", 6)
	vb.add_child(idx_row)
	var idx := _Style.label("商品位 %d" % (_i + 1), _Style.FONT_MIN, _Style.C_TEXT_DIM)
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
	var nm := _Style.label("—", 26, _Style.C_WHITE)
	_Style.apply_font(nm, "display")              # §5.4：卡名 = Black 展示字重（L1 主信息）
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	_slot_name.append(nm)
	var tag_chip := _Style.label("", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	tag_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_row.add_child(tag_chip)
	_slot_tag.append(tag_chip)

	# 🆕 插画带（2026-11-08 批次②③）：460 安全区透明底插画缩放进恒 72px 高的横带。
	#    资产缺失 / headless 未导入 → card_art() 返回 null → 整带隐藏（版式回落无图）。
	#    🔴 构建时只建空带：卡名在 `_refresh_shop` 刷新时才落到槽位（此处 `nm` 是占位
	#    Label，不是卡名字符串），纹理由刷新链路按卡名填充（`_slot_art`）。
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0.0, 72.0)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.visible = false
	vb.add_child(art)
	_slot_art.append(art)

	# 卡种（L2 常规）
	var kind := _Style.label("—", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(kind)
	_slot_kind.append(kind)

	# 价格行（L1 重要）：✓/✗ 标记（§9.2 双通道）+ **等宽数字**（§5.5）+ 单位
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 4)
	vb.add_child(price_row)
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

	vb.add_child(_Style.hline(0.12))

	# 🆕 效果描述块（§5.2 L2 文字；比备注亮一档 —— 它是「这张卡干什么」的正面信息，
	#   备注只是条件事实）。🔴 高度固定 DESC_LINES 行：三个位的描述块**等高同构**（X3）。
	var desc := _Style.label("", _Style.FONT_MIN, _Style.C_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0.0, DESC_LINE_H * float(DESC_LINES))
	vb.add_child(desc)
	_slot_desc.append(desc)

	# 事实备注（H2/H3/H4/H5/H6/H9）—— 只在有事实时占位（min 0），否则不占高度
	var note := _Style.label("", _Style.FONT_MIN, _Style.C_TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	_slot_note.append(note)

	# 撑开 → 三位等高时按钮对齐底部（不靠 padding 凑）
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(gap)

	var buy := Button.new()
	buy.text = "购买"
	_Style.button(buy, "primary")
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("buy_requested", _i))
	vb.add_child(buy)
	_slot_buy.append(buy)

	var lock := Button.new()
	lock.text = "锁定"
	_Style.button(lock, "ghost")
	lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("lock_toggled", _i))
	vb.add_child(lock)
	_slot_lock.append(lock)

	# 🆕 蓝图 chrome（§5.5）：四角刻线，**后于** vb 加入 → 画在内容之上。
	#    accent 存 meta，`_refresh_shop` 按可购性改写并 queue_redraw（不在 _draw 里 new）。
	var chrome := Control.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	chrome.set_meta("accent", "normal")
	chrome.draw.connect(func() -> void: _draw_slot_chrome(chrome))
	p.add_child(chrome)
	_slot_chrome.append(chrome)
	return p


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
	var s := _runtime_snapshot()
	if s.is_empty():
		_no_scrap_label.visible = true
		_no_scrap_label.text = "未接线：读不到运行时快照"
		for i in STAT_KEYS.size():
			_stat_vals[i].text = "--"
		for i in SLOT_COUNT:
			_slot_name[i].text = "—"
			_slot_art[i].visible = false
			_slot_tag[i].text = ""
			_slot_rarity[i].text = ""
			_slot_kind[i].text = "—"
			if _slot_price_mark[i] is TextureRect:
				_slot_price_mark[i].visible = false
			else:
				_slot_price_mark[i].text = ""
			_slot_price_num[i].text = "--"
			_slot_price_unit[i].text = ""
			_set_price_color(i, C_DIM)
			_slot_desc[i].text = ""
			_slot_note[i].text = ""
			_slots[i].add_theme_stylebox_override("panel", _Style.card_blueprint("dim"))
			_set_chrome_accent(i, "dim")
			_slot_buy[i].disabled = true
			_slot_lock[i].disabled = true
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
			_slot_tag[i].text = ""
			_slot_rarity[i].text = ""
			_slot_kind[i].text = "此位无卡"
			if _slot_price_mark[i] is TextureRect:
				_slot_price_mark[i].visible = false
			else:
				_slot_price_mark[i].text = ""
			_slot_price_num[i].text = "--"
			_slot_price_unit[i].text = ""
			_set_price_color(i, C_DIM)
			_slot_desc[i].text = ""
			_slot_note[i].text = String(s["notes"][i])
			_slots[i].add_theme_stylebox_override("panel", _Style.card_blueprint("dim"))
			_set_chrome_accent(i, "dim")
		else:
			_slot_name[i].text = nm
			# 🆕 插画带按卡名取图：缺失（未出图 / headless）→ 隐藏整带，版式回落
			var art_tex := _Style.card_art(nm)
			_slot_art[i].texture = art_tex
			_slot_art[i].visible = art_tex != null
			# 🆕 稀有度（§2.3 · P1-6）：边框色/粗细 + ▲ 角标数 —— 双通道，不只靠颜色。
			#    稀有度由 card_text 只读派生自抽取权重（SSOT），改权重卡面自动跟随。
			var rar := _CardText.rarity(nm)
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
			_set_price_color(i, C_ACCENT if _aff else C_DIM)
			# 卡片描边 = 稀有度色（§2.3）；可购性由 ✓/✗ + 价格色 + 角刻线表达（第二通道）
			_slots[i].add_theme_stylebox_override("panel",
				_Style.card_blueprint("normal", rar))
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
				extra.append("投主塔 DPS +%.0f%%" % (float(hl["delta_pct"]) * 100.0))  # H9
			if not extra.is_empty():
				note = (note + " · " if note != "" else "") + " · ".join(extra)
			_slot_note[i].text = note
		_slot_buy[i].disabled = not ok
		_slot_buy[i].text = "购买" if nm == "" else "购买 %.0f" % price
		# 锁定：3 位中可锁 1；锁定位显示"已锁"
		var locked := (int(s["lock_index"]) == i)
		_slot_lock[i].text = "已锁 · Space 解锁" if locked else "锁定"
		_slot_lock[i].disabled = (nm == "")

	# ---- 刷新按钮：显示 5+3n 的实时成本（E5：买不起置灰 + 标红）----
	var rc := float(s["reroll_cost"])
	_reroll_btn.text = "刷新 R（%.0f 分 · 已刷 %d 次）" % [rc, int(s["rerolls"])]
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


func _refresh_pending(s: Dictionary) -> void:
	_clear_children(_pending_box)
	var pend: Array = s["pending"]
	_pending_label.text = "待放置队列（%d）" % pend.size()
	var can_enter := _can_enter_placement()
	for i in pend.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lb := _Style.label("%d · %s" % [i + 1, String(pend[i])], _Style.FONT_MIN, _Style.C_TEXT)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		var btn := Button.new()
		btn.text = "放置"
		_Style.button(btn, "normal")
		btn.custom_minimum_size = Vector2(84.0, 0.0)
		btn.disabled = not can_enter
		var idx := i
		btn.pressed.connect(func() -> void:
			if controller != null:
				controller.request_placement(idx))
		row.add_child(btn)
		_pending_box.add_child(row)


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
	_heavy_panel.visible = true                       # 保持可见以展示"置灰"状态
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
