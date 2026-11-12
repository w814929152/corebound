extends CanvasLayer
## 关卡内退出确认，只发意图；暂停由 TimeDirector 统一应用。
const Style := preload("res://scripts/ui/ui_style.gd")
signal exit_confirmed()
signal save_requested()
var can_save: Callable
var _message: Label
var _save_button: Button
var director: Node
var active := false
var confirming := false
var exit_button: Button
var modal: Control
var panel: PanelContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 150
	exit_button = Button.new()
	exit_button.text = "退出关卡"
	Style.button(exit_button, "ghost")
	exit_button.pressed.connect(request_exit)
	add_child(exit_button)
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.panel())
	modal.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(Style.label("退出当前关卡？", 26))
	_message = Style.label("", 18)
	box.add_child(_message)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	for title in ["继续游戏", "保存并退出", "放弃本局"]:
		var button := Button.new()
		button.text = title
		button.custom_minimum_size = Vector2(140, 44)
		match title:
			"继续游戏":
				Style.button(button, "normal")
				button.pressed.connect(cancel_exit)
			"保存并退出":
				Style.button(button, "primary")
				button.pressed.connect(_request_save)
				_save_button = button
			"放弃本局":
				Style.button(button, "danger")
				button.pressed.connect(confirm_exit)
		buttons.add_child(button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	set_active(false)

func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	exit_button.position = Vector2(size.x - 150, 80)
	exit_button.size = Vector2(126, 44)
	panel.size = Vector2(560, 190)
	panel.position = (size - panel.size) * 0.5

func set_active(value: bool) -> void:
	active = value
	confirming = false
	visible = value
	if modal != null:
		modal.hide()

func request_exit() -> void:
	if not active or confirming:
		return
	confirming = true
	director.set_external_pause(true)
	var available := can_save.is_valid() and bool(can_save.call())
	_save_button.visible = available
	_message.text = "保存后可从主菜单继续。放弃本局将丢失当前进度。" if available else \
		"可在准备阶段保存。放弃本局将丢失当前进度。"
	modal.show()


func _request_save() -> void:
	if confirming and _save_button.visible:
		save_requested.emit()


func show_error(message: String) -> void:
	_message.text = message

func cancel_exit() -> void:
	if not confirming:
		return
	confirming = false
	modal.hide()
	director.set_external_pause(false)

func confirm_exit() -> void:
	if not confirming:
		return
	set_active(false)
	exit_confirmed.emit()

func _input(event: InputEvent) -> void:
	if not confirming or not (event is InputEventKey):
		return
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_exit()
	get_viewport().set_input_as_handled()
