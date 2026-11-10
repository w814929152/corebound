extends CanvasLayer
##
## T1 · 修复入口多塔处置弹窗（`disabled_tower_dialog.gd`）
##
## 🔴 口径来源：`mechanics-tower-life-death` §2.3 / Q-T4（三选一）/ Q-T8（数值）/ E-T2 / E-T4 / E-T6（原文一字不改）
##   · Disabled 塔在**波次间安全窗**玩家三选一：
##       ① **修复** `Repair`：花 `ceil(0.30×累计投入)` 分 → HP 回满 → 恢复输出（装配卡全保留，E-T6 层数不变）；
##       ② **被动拆除** `Salvage(Disabled)`：返还 **0%**、装配卡全销毁、释放塔位；
##       ③ **放着不管**：no-op（继续占塔位、不输出、仍吃 κ 折价）→ 本弹窗里 = 关闭（下次安全窗仍在）。
##   · E-T2：多座同时停机**合并为一个列表弹窗**（每座一行三选一）。
##   · E-T4：积分不足修不起 → 「修复」按钮**置灰**（玩家可改「放着不管」或「被动拆除」→ 永不死锁）。
##
## 🔴 分层：CanvasLayer 140（shop-reroll §2.4 分层表，同 salvage_confirm_dialog）；
##    **禁止 `AcceptDialog` 默认控件** → 本文件用自定义 `Control`。
## 🔴 E15：弹窗打开时世界仍 `paused`（本节点 `process_mode = ALWAYS`，只关注意图，不解除暂停）。
##
## 🔴 通用性（同 salvage_confirm_dialog）：本组件是**纯展示 + 意图确认**，不含任何玩法口径。
##    `show_towers(rows)` 接收 **controller 已组装好的行数据**（含 `can_repair` 布尔），
##    玩法结算（修花费多少、拆销毁几张）由 `ShopRuntime` 计算、由 `ShopController` 组装后传入。
##    组件本身不 import 任何 engine 逻辑，只把玩家点选的 slot + 动作通过信号回传。
##
## 用法（ShopController 侧）：
##   var dlg := DisabledTowerDialog.new()
##   add_child(dlg)
##   dlg.tower_repair_requested.connect(func(slot): runtime.repair_tower(slot); ...)
##   dlg.tower_salvage_requested.connect(func(slot): runtime.salvage_disabled_tower(slot); ...)
##   dlg.closed.connect(func(): dlg.queue_free())
##   dlg.show_towers(runtime.list_disabled_towers())   # rows: [{slot, invested, repair_cost, attach_layers, can_repair}]
##
## ⚠️ Godot 坑（control-manifest §4）：
##   G6 headless 无 global_script_class_cache → 不写 `class_name`，一律 preload 调用方处理；
##   本节点是 Node（CanvasLayer），由 controller `add_child`，不走 class_name 实例化。
##

## 玩家在弹窗里点「修复」某座塔（携带塔位 slot）。
signal tower_repair_requested(slot: int)
## 玩家在弹窗里点「被动拆除」某座塔（携带塔位 slot）。
signal tower_salvage_requested(slot: int)
## 弹窗关闭（「放着不管」= no-op 关闭，或全部处置完毕自动关闭）。
signal closed()

const _Style := preload("res://scripts/ui/ui_style.gd")


var _built: bool = false
var _on_close: Callable = Callable()

var _panel: PanelContainer
var _title_label: Label
var _rows_box: VBoxContainer
var _close_btn: Button


func _init() -> void:
	# 🔴 layer 必须在 _init 就钉死（show_towers 可能在 _ready 前被调）
	layer = 140                          # shop-reroll §2.4 分层表：确认弹窗 = 140


func _ready() -> void:
	# 🔴 E15：弹窗期间世界仍 paused；本节点必须 ALWAYS 才能收按钮点击
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


## 幂等构建（show_towers 可能在 _ready 之前被调，兜底自建）。
func _build() -> void:
	if _built:
		return
	_built = true
	# 全屏半透明遮罩（点击空白处 = 关闭，防误触；等价「放着不管」）
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	# 🔴 居中关键：锚点放中心还不够，增长方向默认 END 会让控件从中心往右下长（整体偏移半个面板）。
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(460.0, 0.0)
	# 补面板样式（原先走 Godot 默认主题 → 无描边灰块，与战场语言断裂）
	_panel.add_theme_stylebox_override("panel", _Style.panel(_Style.C_ALERT, 2, 20.0, 16.0))
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_Style.apply_font(_title_label, "medium")     # §5.4：弹窗标题 = Medium
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 10)
	vbox.add_child(_rows_box)

	_close_btn = Button.new()
	_close_btn.text = "放着不管（关闭）"
	_close_btn.custom_minimum_size = Vector2(0.0, 42.0)
	_Style.button(_close_btn, "normal")
	_close_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(_close_btn)


## 展示多塔处置弹窗。`rows` = controller 组装好的 Array[Dictionary]：
##   { slot:int, invested:float, repair_cost:int, attach_layers:int, can_repair:bool }
func show_towers(rows: Array) -> void:
	_build()
	var n := rows.size()
	_title_label.text = "受损塔处置（%d 座 · 波次间安全窗）" % n
	_clear_rows()
	for row in rows:
		_rows_box.add_child(_make_row(row))
	# 无可修塔时把关闭按钮文案强调为唯一出口（E-T4：放不管 / 拆，永不死锁）
	_close_btn.text = "放着不管（关闭）"
	visible = true


## 刷新行数据（controller 在某座塔处置后重算剩余受损塔列表 → 重新填充；空则关闭）。
func refresh(rows: Array) -> void:
	if rows.is_empty():
		_dismiss()
		return
	show_towers(rows)


func _clear_rows() -> void:
	for ch in _rows_box.get_children():
		_rows_box.remove_child(ch)
		ch.queue_free()


## 组装单座塔的行：信息行 + 三选一按钮（修复 / 被动拆除）。
##   🔴 修复按钮 `can_repair=false` 时置灰（E-T4：修不起 → 只能「放着不管」或「被动拆除」）。
func _make_row(row: Dictionary) -> Control:
	var slot: int = int(row["slot"])
	var invested := float(row["invested"])
	var repair_cost := int(row["repair_cost"])
	var n_layers := int(row["attach_layers"])
	var can_repair := bool(row["can_repair"])

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var info := Label.new()
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：14 → 16。
	info.add_theme_font_size_override("font_size", 16)
	info.text = "塔位 %d · 累计投入 %.0f 分 · 装配 %d 层" % [slot, invested, n_layers]
	box.add_child(info)

	var hint := Label.new()
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：12 → 16。
	hint.add_theme_font_size_override("font_size", 16)
	# 🔴 字面 `0%` 在 `String % [...]` 里会被当格式符 → 必须转义为 `0%%`（否则整串格式化失败，
	#    `%d` 原样残留 + 运行时 `ERROR: String formatting error: unsupported format character`）。
	hint.text = "修复 %d 分（恢复全部生命 · 保留装配卡）｜ 被动拆除（返还 0%% · 销毁 %d 层）" % [repair_cost, n_layers]
	hint.add_theme_color_override("font_color", Color(0.55, 0.57, 0.60, 1.0))
	box.add_child(hint)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	box.add_child(hbox)

	var repair_btn := Button.new()
	repair_btn.text = "修复 %.0f 分" % float(repair_cost)
	repair_btn.custom_minimum_size = Vector2(150.0, 38.0)
	_Style.button(repair_btn, "primary")
	repair_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repair_btn.disabled = not can_repair
	if not can_repair:
		repair_btn.text = "积分不足 · 修不起"
	repair_btn.pressed.connect(func() -> void:
		tower_repair_requested.emit(slot))
	hbox.add_child(repair_btn)

	var salvage_btn := Button.new()
	salvage_btn.text = "被动拆除"
	salvage_btn.custom_minimum_size = Vector2(124.0, 38.0)
	_Style.button(salvage_btn, "danger")
	salvage_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	salvage_btn.pressed.connect(func() -> void:
		tower_salvage_requested.emit(slot))
	hbox.add_child(salvage_btn)

	return box


func _on_close_pressed() -> void:
	_dismiss()


## 「放着不管」/ 点遮罩空白 → 关闭（no-op；下次安全窗仍在）。
func _dismiss() -> void:
	visible = false
	closed.emit()


func _on_backdrop_input(event: InputEvent) -> void:
	# 点击遮罩空白 = 关闭（🔴 不触发任何处置动作 = 「放着不管」）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_dismiss()
