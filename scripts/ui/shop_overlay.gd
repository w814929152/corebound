extends Control
##
## 商店抽屉覆盖层 —— GDD §2.4 C3 双焦点界面
##
## 切片3：双焦点布局 / 抽屉形态跟随五态 / 预算条常驻。
## 切片4（本轮）：**商品位填真实卡面 + 意图接线**（I-2 / I-3）。
##   · 3 个商品位显示真实卡名 / 卡种 / 价格 / H1 买得起 / H8 无合法目标 / H4 已达上限；
##   · 刷新按钮显示 `5+3n` 的实时成本，买不起时置灰（E5）；
##   · 锁定按钮显示当前锁定位（3 位中可锁 1，每波重置）；
##   · 待放置队列（建筑卡买入后的蓝图图标 + 张数角标）与「放置」入口（I-8）；
##   · 放置模式下露出塔位按钮（New / Upgrade 由 `runtime` 判定，Invalid 置灰）。
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
## 后续切片要接的接口点见切片3 架构文档 §8。
##

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")

const SLOT_COUNT := 3        # 恒为 3（A4：保底不新增第 4 位）

# ---- 配色（青橙双极，art-bible §2.1；占位色，等林绘澄给真资产）----
const C_BG := Color(0.07, 0.09, 0.12, 0.94)
const C_SLOT := Color(0.13, 0.17, 0.22, 1.0)   # 🔴 三个商品位完全一致（X3）
const C_ACCENT := Color(0.95, 0.62, 0.18, 1.0) # 橙（H1 买得起：价格辉金）
const C_CYAN := Color(0.24, 0.78, 0.83, 1.0)   # 青
const C_BUDGET := Color(0.24, 0.78, 0.83, 1.0)
const C_BUDGET_DRAINED := Color(0.86, 0.20, 0.20, 1.0)
const C_DIM := Color(0.55, 0.57, 0.60, 1.0)    # H1 买不起：价格灰（🔴 卡片本身不隐藏，X6）
const C_TEXT := Color(0.88, 0.90, 0.92, 1.0)
const C_WARN := Color(0.86, 0.20, 0.20, 1.0)   # E5：刷新买不起 → 价格标红

const SLOT_SIZE := Vector2(150.0, 190.0)       # 🔴 三个位完全一致（X3）


var director: Node = null
var controller: Node = null   # ShopController（只读它的 runtime.snapshot()）

var _panel: PanelContainer
var _title: Label
var _slots: Array = []        # Array[PanelContainer]
var _slot_name: Array = []    # Array[Label]
var _slot_kind: Array = []
var _slot_price: Array = []
var _slot_note: Array = []
var _slot_buy: Array = []     # Array[Button]
var _slot_lock: Array = []
var _budget_fill: ColorRect
var _budget_label: Label
var _scrap_label: Label
var _reroll_btn: Button
var _heavy_panel: VBoxContainer      # 重决策入口组（仅 SafeWindow 露出）
var _salvage_btn: Button
var _discard_btn: Button
var _detach_btn: Button
var _repair_btn: Button              # 🔒 T1 修复入口：处置受损塔（有 disabled 塔才亮 + 红点计数）
var _pending_label: Label
var _pending_box: VBoxContainer
var _place_box: VBoxContainer


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
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(root_vbox)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	root_vbox.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	margin.add_child(inner)

	# ---- 标题 ----
	_title = Label.new()
	_title.text = "商店（骨架占位）"
	_title.add_theme_font_size_override("font_size", 18)
	inner.add_child(_title)

	# ---- 减速预算条（🔴 常驻可见，锚点 6 第 4 条）----
	var budget_row := HBoxContainer.new()
	budget_row.add_theme_constant_override("separation", 8)
	inner.add_child(budget_row)
	var budget_label_text := Label.new()
	budget_label_text.text = "减速预算"
	budget_label_text.custom_minimum_size = Vector2(80.0, 0.0)
	budget_row.add_child(budget_label_text)
	var budget_bg := Panel.new()
	budget_bg.custom_minimum_size = Vector2(0.0, 14.0)
	budget_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	budget_row.add_child(budget_bg)
	_budget_fill = ColorRect.new()
	_budget_fill.color = C_BUDGET
	_budget_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	budget_bg.add_child(_budget_fill)
	_budget_label = Label.new()
	_budget_label.custom_minimum_size = Vector2(84.0, 0.0)
	budget_row.add_child(_budget_label)

	# ---- 积分 / 波次读数（M5：仅击杀获得）----
	_scrap_label = Label.new()
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：13 → 16。
	_scrap_label.add_theme_font_size_override("font_size", 16)
	inner.add_child(_scrap_label)

	# ---- 3 个商品位（🔴 尺寸/亮度完全一致，X3 合规）----
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 10)
	inner.add_child(slots_row)
	for i in SLOT_COUNT:
		var slot := _make_slot(i)
		slots_row.add_child(slot)
		_slots.append(slot)

	# ---- 刷新按钮（E5：买不起置灰 + 价格标红）----
	_reroll_btn = Button.new()
	_reroll_btn.text = "刷新（骨架：仅发意图）"
	_reroll_btn.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("reroll_requested"))
	inner.add_child(_reroll_btn)

	# ---- 待放置队列（Q-SR5 跨波保留 · E2 角标持续提醒）----
	_pending_label = Label.new()
	_pending_label.text = "待放置队列"
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：14 → 16。
	_pending_label.add_theme_font_size_override("font_size", 16)
	inner.add_child(_pending_label)
	_pending_box = VBoxContainer.new()
	_pending_box.add_theme_constant_override("separation", 4)
	inner.add_child(_pending_box)

	# ---- 放置模式：塔位按钮（I-8；仅态⑤露出）----
	_place_box = VBoxContainer.new()
	_place_box.add_theme_constant_override("separation", 4)
	inner.add_child(_place_box)

	# ---- 重决策入口组（🔴 仅 SafeWindow 露出；战斗中置灰且不响应，T-C1 / E16）----
	_heavy_panel = VBoxContainer.new()
	_heavy_panel.add_theme_constant_override("separation", 6)
	inner.add_child(_heavy_panel)
	var heavy_title := Label.new()
	heavy_title.text = "重决策（仅安全窗）"
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：14 → 16。
	heavy_title.add_theme_font_size_override("font_size", 16)
	_heavy_panel.add_child(heavy_title)

	_discard_btn = Button.new(); _discard_btn.text = "弃卡（🟡 后续切片）"
	_detach_btn = Button.new(); _detach_btn.text = "卸下改投（🟡 后续切片）"
	_salvage_btn = Button.new(); _salvage_btn.text = "拆除并回收 Salvage（🟡 后续切片）"
	# 🔒 T1 修复入口（Q-T4 三选一）：处置受损塔。有 disabled 塔才亮 + 红点计数(N)。
	_repair_btn = Button.new(); _repair_btn.text = "处置受损塔"
	_heavy_panel.add_child(_discard_btn)
	_heavy_panel.add_child(_detach_btn)
	_heavy_panel.add_child(_salvage_btn)
	_heavy_panel.add_child(_repair_btn)
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


func _make_slot(i: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = SLOT_SIZE            # 🔴 三个位完全一致
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)

	var idx := Label.new()
	idx.text = "商品位 %d" % (i + 1)
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：12 → 16。
	idx.add_theme_font_size_override("font_size", 16)
	vb.add_child(idx)

	var nm := Label.new()
	nm.text = "[接口] 卡面"
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：15 → 16。
	nm.add_theme_font_size_override("font_size", 16)
	vb.add_child(nm)
	_slot_name.append(nm)

	var kind := Label.new()
	kind.text = "H1 买得起"
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：11 → 16。
	kind.add_theme_font_size_override("font_size", 16)
	vb.add_child(kind)
	_slot_kind.append(kind)

	var price := Label.new()
	price.text = "--"
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：13 → 16。
	price.add_theme_font_size_override("font_size", 16)
	vb.add_child(price)
	_slot_price.append(price)

	var note := Label.new()
	note.text = ""
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：11 → 16。
	note.add_theme_font_size_override("font_size", 16)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	_slot_note.append(note)

	var buy := Button.new()
	buy.text = "购买"
	buy.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("buy_requested", i))
	vb.add_child(buy)
	_slot_buy.append(buy)

	var lock := Button.new()
	lock.text = "锁定 / 解锁"
	lock.pressed.connect(func() -> void:
		if director != null:
			director.emit_signal("lock_toggled", i))
	vb.add_child(lock)
	_slot_lock.append(lock)
	return p


# ---------------------------------------------------------------------------
#  商品位刷新（事件驱动：controller.shop_changed / run_changed，🔴 不每帧重算，SR-6）
# ---------------------------------------------------------------------------
func _refresh_shop() -> void:
	var s := _runtime_snapshot()
	if s.is_empty():
		_scrap_label.text = "积分 --（未接线）"
		for i in SLOT_COUNT:
			_slot_name[i].text = "[接口] 卡面"
			_slot_kind[i].text = "H1 买得起"
			_slot_price[i].text = "--"
			_slot_note[i].text = ""
			_slot_buy[i].disabled = true
			_slot_lock[i].disabled = true
		_reroll_btn.disabled = true
		_clear_children(_pending_box)
		_clear_children(_place_box)
		return

	_scrap_label.text = "积分 %.0f · 主塔塔位 %d" % [
		float(s["scrap"]), int(s["core_tower_slot"])]

	for i in SLOT_COUNT:
		var nm := String(s["offers"][i])
		var price := float(s["prices"][i])
		var ok := bool(s["affordable"][i]) and bool(s["legal"][i])
		# C2 高亮事实（H2/H3/H5/H6/H9；H1/H4/H8 已在 affordable/at_cap/notes）
		var hl: Dictionary = s.get("highlights", {}).get(str(i), {})
		if nm == "":
			_slot_name[i].text = "—"
			_slot_kind[i].text = "此位无卡"
			_slot_price[i].text = ""
			_slot_note[i].text = String(s["notes"][i])
			_slot_price[i].add_theme_color_override("font_color", C_DIM)
		else:
			_slot_name[i].text = nm
			# H2：Tag 协同 → 卡种行加脉冲标记（橙🔥/青❄，视觉编码不写推荐词）
			var kind_txt := String(s["kinds"][i])
			if bool(hl.get("tag_synergy", false)):
				kind_txt += "  ◈协同"
			_slot_kind[i].text = kind_txt
			# H1：价格数字用辉金 vs 灰（🔴 卡片本身始终可见，X6）
			# 🔴 T-P6-06 S2（art-bible §9.2 红线①「任何游戏状态不得仅靠颜色传达」）：
			#   买得起/买不起除**颜色**外，价格前加 **✓/✗ 字形冗余**（纯加法；配色判据一字不改）。
			var _aff := bool(s["affordable"][i])
			_slot_price[i].text = "%s %.0f 分" % [("✓" if _aff else "✗"), price]
			_slot_price[i].add_theme_color_override("font_color",
				C_ACCENT if _aff else C_DIM)
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
		_slot_lock[i].text = "已锁（Space 解锁）" if locked else "锁定 / 解锁"
		_slot_lock[i].disabled = (nm == "")

	# ---- H7 槽位占用事实（强化槽 / 全局槽 / 塔位）----
	var su: Dictionary = s.get("slot_usage", {})
	if not su.is_empty():
		_scrap_label.text += " · 强化槽 %d/%d · 全局槽 %d/%d · 塔位 %d/%d" % [
			int(su.get("enh", 0)), int(su.get("enh_max", 5)),
			int(su.get("global", 0)), int(su.get("global_max", 3)),
			int(su.get("tower", 0)), int(su.get("tower_max", 6))]

	# ---- 刷新按钮：显示 5+3n 的实时成本（E5：买不起置灰 + 标红）----
	var rc := float(s["reroll_cost"])
	_reroll_btn.text = "刷新 R（%.0f 分 · 已刷 %d 次）" % [rc, int(s["rerolls"])]
	var can_reroll := float(s["scrap"]) >= rc
	_reroll_btn.disabled = not can_reroll
	_reroll_btn.add_theme_color_override("font_color", C_TEXT if can_reroll else C_WARN)

	# ---- 🔒 T1 修复入口：统计受损塔（disabled）数，更新「处置受损塔」按钮（红点计数）----
	_refresh_repair_btn(s)

	_refresh_pending(s)
	_refresh_placement(s)


## 🔒 T1 修复入口 UI（Q-T4 三选一 · SR-R2 只标事实）：
##   · 统计 snapshot `slots` 里 `disabled=true` 的塔数；
##   · 有受损塔 → 按钮显示计数（"处置受损塔 (N)"）+ 红点；无 → 文案回落"处置受损塔"。
##   · 🔴 可否点 = 有受损塔 **且** 安全窗（heavy_on）——非安全窗一律置灰（T-C1 / E16）。
##   · 🔴 只标事实（有几座受损），不标推荐（该修还是该拆由玩家判断）。
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
		_repair_btn.add_theme_color_override("font_color", C_WARN)   # 红点提示有待处置
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
		row.add_theme_constant_override("separation", 6)
		var lb := Label.new()
		lb.text = "蓝图 %d：%s" % [i + 1, String(pend[i])]
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		var btn := Button.new()
		btn.text = "放置"
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


func _refresh_placement(s: Dictionary) -> void:
	_clear_children(_place_box)
	if director == null or director.sm == null:
		return
	if int(director.sm.state) != _TSM.State.PLACEMENT_MODE:
		return
	var head := Label.new()
	head.text = "放置模式：点塔位落子（Esc 取消，🔴 取消不退款）"
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：13 → 16。
	head.add_theme_font_size_override("font_size", 16)
	_place_box.add_child(head)

	var slots: Array = s["slots"]
	var modes: Array = s["place_modes"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in slots.size():
		var d: Dictionary = slots[i]
		var b := Button.new()
		var txt := "塔位 %d " % i
		if bool(d["empty"]):
			txt += "（空）"
		else:
			txt += "%s L%d" % [String(d["ctype"]), int(d["h"])]
		var mode := String(modes[i]) if i < modes.size() else ""
		b.text = txt
		b.disabled = (mode == "invalid")
		if mode == "new":
			b.text += " ← 新建"
		elif mode == "upgrade":
			b.text += " ← 升级"
		elif mode == "invalid":
			b.text += " ✕"
		var slot_idx := i
		b.pressed.connect(func() -> void:
			if director != null:
				director.exit_placement(true, slot_idx))
		row.add_child(b)
	_place_box.add_child(row)


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
			_title.text = "商店 · 轻决策模式"
		_TSM.Drawer.HEAVY:
			_title.text = "商店 · 重决策模式（安全窗）"
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
	_budget_fill.color = C_BUDGET_DRAINED if left <= 0.0 else C_BUDGET
	_budget_label.text = "%.1f / %.0f s" % [left, budget_max]
	if left <= 0.0:
		_budget_label.text += " 已耗尽"
