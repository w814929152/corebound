extends CanvasLayer
##
## 开局卡包选择覆盖层 —— `pack_select_overlay.gd`
## ---------------------------------------------------------------------------
## 职责：**开打之前**让玩家从已解锁的卡包里挑 `PICKS_PER_RUN` 个（默认 3 个 = 6 张卡）。
##   本组件纯 UI：只读 `run_meta.gd`（已解锁 / 上次选包），只发 `packs_confirmed`。
##   卡池的**实际生效**由调用方（`boot.gd`）在确认后调 `ShopRuntime.set_active_packs()`。
##
## 🔴 为什么要有这一屏（不是"多一层菜单"）：
##   `keyword-adaptation.md` §7.4 实测：玩家池 7 → 10 张，A 路径起飞率 −8.0pp、
##   B 路径 −11.0pp。卡池张数是**难度旋钮**，不是容量。所以每局只带 3 包（6 张），
##   张数恒定、构成由玩家选 —— 选择本身就是构筑（P3「每局一个新解」）。
##
## 🔴 分层 160：高于结算 150 / 确认弹窗 140 / 教学 135。它出现在"开局前"，
##   必须压住所有战斗 UI；`process_mode = ALWAYS` 让安全窗（tree paused）下也能点。
##
## 🔴 art-bible §5.1 / §9.1 合规：全部控件走 `ui_style.gd`（无系统默认控件），
##   玩家可见文本 ≥16px；✓/已选 状态同时用**文字 + 描边色**双通道表达
##   （§9.2 红线1：颜色不得是唯一信息通道）。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 不写 `class_name`，调用方 preload。
##

signal packs_confirmed(packs: Array)

const _Style := preload("res://scripts/ui/ui_style.gd")
const _Packs := preload("res://scripts/data/card_packs.gd")
const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const _CardText := preload("res://scripts/data/card_text.gd")

## 单包卡面尺寸（全部卡包同一尺寸 —— X3「不得用布局差异暗示」）。
##   🔴 宽度从 208 → 180：卡包从 5 增到 7 个后，7×180 + 6×14 间距 ≈ 1344 < 1600 实际窗口，
##     横向不溢出；高度不变（内容用 autowrap 自适应，无需加高）。
const TILE_SIZE := Vector2(180.0, 292.0)

var _built: bool = false
var _tiles: Array = []          # Array[Dictionary]：{id, btn, status, name, tag, cards, roles}
var _sel: Array = []            # Array[String] 当前勾选
var _count: Label
var _hint: Label
var _start: Button
var _head: Label


func _init() -> void:
	# 🔴 layer 在 _init 钉死（open() 可能在 _ready 之前被调）
	layer = 160


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


# ---------------------------------------------------------------------------
#  构建
# ---------------------------------------------------------------------------
func _build() -> void:
	if _built:
		return
	_built = true

	var bg := ColorRect.new()
	bg.color = Color(0.043, 0.051, 0.086, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP     # 吃掉点击，防止穿透到战场
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1188.0, 0.0)
	panel.add_theme_stylebox_override("panel", _Style.panel(_Style.C_ALLY, 2, 26.0, 22.0))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := _Style.label("选 择 卡 包", 34, _Style.C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_head = _Style.label("", 16, _Style.C_TEXT_DIM)
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_head)

	vbox.add_child(_Style.hline())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	for p in _Packs.PACKS:
		row.add_child(_make_tile(p))

	vbox.add_child(_Style.hline())

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	vbox.add_child(foot)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(left)

	_count = _Style.label("", 20, _Style.C_TEXT)
	left.add_child(_count)

	_hint = _Style.label("", 16, _Style.C_TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_hint)

	_make_start_button(foot)


## 开始按钮（单独函数只为让 `_build()` 读起来短）
func _make_start_button(parent: HBoxContainer) -> void:
	_start = Button.new()
	_start.text = "开 始 关 卡"
	_start.custom_minimum_size = Vector2(240.0, 54.0)
	_Style.button(_start, "primary")
	_start.pressed.connect(_on_start_pressed)
	parent.add_child(_start)


func _make_tile(pack: Dictionary) -> Button:
	var pid := String(pack["id"])
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = TILE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	_Style.button(b, "normal")
	b.pressed.connect(_on_tile_pressed.bind(pid))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	b.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	var nm := _Style.label(String(pack["name"]), 22, _Style.C_WHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	var tag := _Style.label(String(pack["tag_line"]), 16, _Style.C_TEXT_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)

	v.add_child(_Style.hline())

	var card_names: Array = []
	var card_roles: Array = []
	for cnm in (pack["cards"] as Array):
		var s := String(cnm)
		var l1 := _Style.label(s, 18, _Style.C_TEXT)
		l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l1)
		var l2 := _Style.label(_CardText.role(s), 16, _Style.C_TEXT_DIM)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l2)
		card_names.append(l1)
		card_roles.append(l2)

	# 把状态行顶到底部（中间留白随卡片高度变化）
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	var status := _Style.label("", 16, _Style.C_TEXT_DIM)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(status)

	_tiles.append({
		"id": pid, "btn": b, "name": nm, "tag": tag, "status": status,
		"cards": card_names, "roles": card_roles,
	})
	return b


# ---------------------------------------------------------------------------
#  展示 / 刷新
# ---------------------------------------------------------------------------
## 由 `boot.gd` 调用：读进度 → 复位勾选 → 显示。
func open() -> void:
	_build()
	_sel = _RunMeta.selection()
	_refresh()
	visible = true


func close() -> void:
	visible = false


func _refresh() -> void:
	var best := _RunMeta.best_wave()
	var unlocked := _Packs.unlocked_ids(best)
	var req := _Packs.required_picks(best)
	var nxt := _RunMeta.next_unlock_wave()

	_head.text = "本局卡池 = 所选卡包的并集（每包 %d 张，选 %d 包 = %d 张）" % [
		_Packs.CARDS_PER_PACK, req, req * _Packs.CARDS_PER_PACK]
	if nxt > 0:
		_head.text += "\n最佳波次 W%d · 到达 W%d 解锁下一个卡包" % [best, nxt]
	elif nxt < 0:
		_head.text += "\n全部 %d 个卡包开放 · 本局任选 %d 包" % [unlocked.size(), req]
	else:
		_head.text += "\n最佳波次 W%d · 卡包已全部解锁" % best

	for t in _tiles:
		var pid := String(t["id"])
		var b: Button = t["btn"]
		var st: Label = t["status"]
		var locked := not unlocked.has(pid)
		var on := _sel.has(pid)
		b.disabled = locked
		if locked:
			_Style.button(b, "unavail")
			b.modulate = Color(1, 1, 1, 0.72)
			st.text = "到达 W%d 解锁" % _Packs.unlock_wave(pid)
			st.add_theme_color_override("font_color", _Style.C_TEXT_DIM)
		else:
			b.modulate = Color(1, 1, 1, 1)
			if on:
				_Style.button(b, "primary")
				st.text = "✓ 已选入本局"
				st.add_theme_color_override("font_color", _Style.C_GOLD)
			else:
				_Style.button(b, "normal")
				st.text = "点击选入"
				st.add_theme_color_override("font_color", _Style.C_TEXT_DIM)
		# 卡名 / 定位：锁定态压暗（只用透明度档位，不改色相 —— 不改动信息本身）
		#   🔴 两档颜色要分开：卡名是主信息（C_TEXT），定位是辅信息（C_TEXT_DIM）。
		for l in (t["cards"] as Array):
			(l as Label).add_theme_color_override("font_color",
				_Style.C_STEEL if locked else _Style.C_TEXT)
		for l in (t["roles"] as Array):
			(l as Label).add_theme_color_override("font_color",
				_Style.C_STEEL if locked else _Style.C_TEXT_DIM)

	_count.text = "已选 %d / %d 包 · 本局卡池 %d 张" % [
		_sel.size(), req, _sel.size() * _Packs.CARDS_PER_PACK]
	_start.disabled = _sel.size() != req
	if _start.disabled:
		_hint.text = "选满 %d 个卡包后才能开始（已解锁 %d 个）" % [req, unlocked.size()]
		_hint.add_theme_color_override("font_color", _Style.C_TEXT_DIM)
	else:
		_hint.text = "未选的卡包本局不会出现在商店里 —— 卡池越窄，越容易刷到想要的卡"
		_hint.add_theme_color_override("font_color", _Style.C_TEXT_DIM)


# ---------------------------------------------------------------------------
#  交互
# ---------------------------------------------------------------------------
func _on_tile_pressed(pid: String) -> void:
	var best := _RunMeta.best_wave()
	var unlocked := _Packs.unlocked_ids(best)
	if not unlocked.has(pid):
		return
	var req := _Packs.required_picks(best)
	if _sel.has(pid):
		_sel.erase(pid)
	elif _sel.size() < req:
		_sel.append(pid)
	else:
		_refresh()
		_hint.text = "最多 %d 个卡包 —— 先取消一个再选" % req
		_hint.add_theme_color_override("font_color", _Style.C_ALERT)
		return
	_sel = _Packs.normalize(_sel, best)
	_refresh()


func _on_start_pressed() -> void:
	var best := _RunMeta.best_wave()
	if not _Packs.is_valid_selection(_sel, best):
		return
	_RunMeta.set_selection(_sel)
	visible = false
	packs_confirmed.emit(_sel.duplicate())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_9:
		var idx := k - KEY_1
		if idx < _tiles.size():
			_on_tile_pressed(String(_tiles[idx]["id"]))
			get_viewport().set_input_as_handled()
		return
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		if not _start.disabled:
			_on_start_pressed()
			get_viewport().set_input_as_handled()
