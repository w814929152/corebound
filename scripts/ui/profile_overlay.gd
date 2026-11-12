extends CanvasLayer

const Style := preload("res://scripts/ui/ui_style.gd")
const Profiles := preload("res://scripts/gameplay/profile_store.gd")
const Campaign := preload("res://scripts/gameplay/campaign.gd")

signal closed
signal selected(slot: int)
signal save_requested(slot: int)
signal delete_requested(slot: int)

var _active_slot := -1
var _rows: VBoxContainer
var _notice: Label
var _confirm: CanvasLayer
var _back: Button


func _ready() -> void:
	layer = 201
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size.x = 880.0
	panel.add_theme_stylebox_override("panel", Style.panel(Style.C_ALLY, 2, 28, 24))
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	panel.add_child(body)
	body.add_child(Style.label("存档管理", 32, Style.C_GOLD))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	body.add_child(_rows)
	_notice = Style.label("", 18, Style.C_GOLD)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_notice)
	_back = _button("返回主菜单", "ghost", _close)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_END
	body.add_child(_back)
	_confirm = preload("res://scripts/ui/salvage_confirm_dialog.gd").new()
	add_child(_confirm)
	_confirm.layer = layer + 1
	_confirm.cancelled.connect(func(): _back.grab_focus())
	hide()


func open(store: Profiles, notice: String = "") -> void:
	_active_slot = store.active
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for slot in Profiles.SLOT_COUNT:
		_add_slot(slot, store)
	_notice.text = notice
	if store.load_error != OK:
		_notice.text = "无法读取存档文件。请检查存档目录后重新启动。"
	_notice.visible = not _notice.text.is_empty()
	show()
	_back.grab_focus()


func _add_slot(slot: int, store: Profiles) -> void:
	var profile := store.get_slot(slot)
	var occupied := not profile.is_empty()
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 72
	row.add_theme_constant_override("separation", 12)
	_rows.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var suffix := "   当前存档" if slot == store.active else ""
	info.add_child(Style.label("存档 %d%s" % [slot + 1, suffix], 23, Style.C_GOLD if slot == store.active else Style.C_TEXT))
	var summary := "空槽位"
	if occupied:
		var campaign := Campaign.new()
		campaign.restore_progress(profile.campaign)
		summary = "已守 %d / 7 地区 · %d 余烬 · %d 局" % [
			campaign.regions_cleared(), campaign.ember(), int(profile.meta.get("runs", 0))]
		if not profile.run.is_empty():
			summary += " · 有待续关卡"
	info.add_child(Style.label(summary, 18, Style.C_TEXT_DIM))
	var pick := _button("读取" if occupied else "新建", "primary", func(): selected.emit(slot))
	pick.disabled = slot == store.active or store.load_error != OK
	row.add_child(pick)
	var save := _button("保存到此槽", "normal", _ask_save.bind(slot, occupied))
	save.disabled = store.active < 0 or store.load_error != OK
	row.add_child(save)
	var delete := _button("删除", "danger", _ask_delete.bind(slot))
	delete.disabled = not occupied or store.load_error != OK
	row.add_child(delete)


func _button(title: String, role: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(116, 46)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Style.button(button, role)
	button.pressed.connect(action)
	return button


func _ask_save(slot: int, occupied: bool) -> void:
	if not occupied or slot == _active_slot:
		save_requested.emit(slot)
		return
	_confirm.show_confirm("覆盖存档 %d？" % (slot + 1),
		"该槽原有的游戏进度和续玩记录会被替换。", func(): save_requested.emit(slot), "确认覆盖")


func _ask_delete(slot: int) -> void:
	_confirm.show_confirm("删除存档 %d？" % (slot + 1),
		"该槽的关卡进度、余烬和续玩记录将被删除。", func(): delete_requested.emit(slot), "确认删除")


func _close() -> void:
	hide()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and not _confirm.visible and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
