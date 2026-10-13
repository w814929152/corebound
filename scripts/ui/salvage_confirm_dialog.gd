extends CanvasLayer
##
## 切片8 · I-9 重决策二次确认弹窗（`salvage_confirm_dialog.gd`）
##
## 🔴 口径来源：`shop-reroll` §2.9 / §E8 / E15 · `card-system` §4.3 / §7.2.2 / Q-C3（原文一字不改）
##   · 拆除回收 `Salvage` **必须二次确认**（不可逆），弹窗列出：
##       「返还 **X** 分 / 销毁 **N** 张卡（共 **M** 层）/ κ **不回升**（兜底①，E11）」
##   · 🔴 **CanvasLayer 140**（`shop-reroll` §2.4 分层表 / MT-1 / CS-7）；
##     **禁止 `AcceptDialog` 默认控件**（`shop-reroll` §11 / art-bible §5.1）→ 本文件用自定义 `Control`。
##   · 🔴 **E15**：弹窗打开时世界仍 `paused`（本节点 `process_mode = ALWAYS`，
##     但只关注意图确认，**不**解除暂停、不推进波次）。
##
## 🔴 通用性：本组件是**纯展示 + 意图确认**，不含任何玩法口径。
##    `show_confirm(title, body, on_confirm)` 接收**已渲染好的文案**与**确认回调**，
##    玩法结算（返还多少分、销毁几张）由 `ShopRuntime.salvage_tower()` 计算、
##    由 `ShopController` 组装文案后传入。组件本身不 import 任何 engine 逻辑。
##
## 用法（ShopController 侧）：
##   var dlg := SalvageConfirmDialog.new()
##   add_child(dlg)
##   dlg.show_confirm("拆除并回收 Salvage？", "返还 18 分\n销毁 3 张卡（共 5 层）\nκ 不回升（兜底①）",
##       func(): runtime.salvage_tower(slot))
##
## ⚠️ Godot 坑（control-manifest §4）：
##   G6 headless 无 global_script_class_cache → 不写 `class_name`，一律 preload 调用方处理；
##   本节点是 Node（CanvasLayer），由场景/控制器 `add_child`，不走 class_name 实例化。
##

signal confirmed()
signal cancelled()


var _on_confirm: Callable = Callable()
var _built: bool = false            # _build 幂等守卫（show_confirm 可能在 _ready 前被调）

var _panel: PanelContainer
var _title_label: Label
var _body_label: Label
var _confirm_btn: Button
var _cancel_btn: Button


func _init() -> void:
	# 🔴 layer 必须在 _init 就钉死（不能只靠 _ready —— show_confirm 可能在 _ready 前被调，
	#    如 controller 里 add_child 后立即 show_confirm，此时 _ready 尚未 flush）。
	layer = 140                          # 🔴 shop-reroll §2.4 分层表：确认弹窗 = 140


func _ready() -> void:
	# 🔴 E15：弹窗期间世界仍 paused；本节点必须 ALWAYS 才能收按钮点击
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


## 幂等构建：`show_confirm` 可能在 `_ready` 之前被调（headless / controller 同步调用），
##   所以这里兜底自建，保证文案控件已就绪。
func _build() -> void:
	if _built:
		return
	_built = true
	# 全屏半透明遮罩（点击空白处 = 取消，防误触）
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(360.0, 0.0)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_body_label = Label.new()
	# 🔴 T-P6-06 S1（§9.1 P0 最小字号 ≥16px）：15 → 16。
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body_label)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	_cancel_btn = Button.new()
	_cancel_btn.text = "取消"
	_cancel_btn.custom_minimum_size = Vector2(120.0, 40.0)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	hbox.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "确认拆除"
	_confirm_btn.custom_minimum_size = Vector2(120.0, 40.0)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	hbox.add_child(_confirm_btn)


## 展示确认弹窗。`body` 为已渲染好的多行文案（调用方负责数值口径）。
func show_confirm(title: String, body: String, on_confirm: Callable = Callable()) -> void:
	_build()                             # 兜底：headless / 同步调用时 _ready 可能未 flush
	_on_confirm = on_confirm
	_title_label.text = title
	_body_label.text = body
	visible = true


func _on_confirm_pressed() -> void:
	visible = false
	if _on_confirm.is_valid():
		_on_confirm.call()
	confirmed.emit()


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()


func _on_backdrop_input(event: InputEvent) -> void:
	# 点击遮罩空白 = 取消（🔴 不触发确认）
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_cancel_pressed()
