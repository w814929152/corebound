extends CanvasLayer
##
## 关卡选择覆盖层 —— `stage_select_overlay.gd`
## ---------------------------------------------------------------------------
## 职责：**开打之前**让玩家从已解锁的关卡里选一关（推进链 = 首次通关，线性解锁）。
##   本组件纯 UI：只读 `campaign.gd`（已通关 / 已解锁 / Ember），只发 `stage_selected`。
##   波数 / 地图 / 卡组解锁的**实际生效**由调用方（`boot.gd`）在选中后处理。
##
## 🔴 与卡包选择的分层：关卡选择在**卡包选择之前**（先选"打哪关"再选"带什么卡"）。
##   两者都是「开局前」覆盖层；本层 layer 161（略高于选包 160，先出现的压在下面）。
##
## 🔴 art-bible §5.1 / §9.1 合规：全部控件走 `ui_style.gd`；✓/已通关/锁定 状态
##   同时用**文字 + 描边色**双通道表达（§9.2 红线1：颜色不得是唯一信息通道）。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 不写 `class_name`，调用方 preload。
##

signal stage_selected(stage_id: String)

const _Style := preload("res://scripts/ui/ui_style.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")

## 单关卡牌尺寸
const TILE_SIZE := Vector2(196.0, 240.0)

var _built: bool = false
var _tiles: Array = []          # Array[Dictionary]：{id, btn, name, map, wave, status}
var _head: Label
var _ember: Label


func _init() -> void:
	# 🔴 layer 在 _init 钉死（open() 可能在 _ready 之前被调）。高于选包层 160。
	layer = 161


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
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1100.0, 0.0)
	panel.add_theme_stylebox_override("panel", _Style.panel(_Style.C_ALLY, 2, 26.0, 22.0))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := _Style.label("选 择 关 卡", 34, _Style.C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_head = _Style.label("", 16, _Style.C_TEXT_DIM)
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_head)

	_ember = _Style.label("", 20, _Style.C_GOLD)
	_ember.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_ember)

	vbox.add_child(_Style.hline())

	# 三章 + 终局，按行分组展示
	for chapter in [1, 2, 3, 4]:
		var chap_label := _Style.label(_chapter_title(chapter), 18, _Style.C_ALLY)
		chap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(chap_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(row)
		for sid in _CampaignData.STAGE_ORDER:
			if int(_CampaignData.STAGES[sid]["chapter"]) != chapter:
				continue
			row.add_child(_make_tile(String(sid)))

	vbox.add_child(_Style.hline())

	var foot_hint := _Style.label("点击已解锁关卡进入 · 通关解锁下一关 · Ember 只解锁选择、不购买强度", 16, _Style.C_TEXT_DIM)
	foot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(foot_hint)


func _chapter_title(ch: int) -> String:
	match ch:
		1: return "第一章 · 熔炉（Swarm）"
		2: return "第二章 · 霜序（Armor）"
		3: return "第三章 · 枢网（Trickle）"
		4: return "终局 · 核心（Mixed）"
	return ""


func _make_tile(sid: String) -> Button:
	var st: Dictionary = _CampaignData.STAGES[sid]
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = TILE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	_Style.button(b, "normal")
	b.pressed.connect(_on_tile_pressed.bind(sid))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	b.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	var nm := _Style.label(String(st["name"]), 20, _Style.C_WHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	var sub := _Style.label("%s · %d 波" % [sid, int(st["wave_count"])], 15, _Style.C_TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)

	var map_info := _Style.label(_map_label(String(st["map_id"])), 15, _Style.C_TEXT_DIM)
	map_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(map_info)

	# 状态行顶到底部
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	var status := _Style.label("", 16, _Style.C_TEXT_DIM)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(status)

	_tiles.append({"id": sid, "btn": b, "name": nm, "status": status})
	return b


func _map_label(map_id: String) -> String:
	# 未实现的地图变体 → 运行时回落三裂环（campaign_data.resolve_map_id 的展示侧提示）。
	if _CampaignData.map_implemented(map_id):
		return "地图：%s" % map_id
	return "地图：%s（回落）" % map_id


# ---------------------------------------------------------------------------
#  展示 / 刷新
# ---------------------------------------------------------------------------
## 由 `boot.gd` 调用：读进度 → 刷新锁定态 → 显示。
func open(campaign) -> void:
	_build()
	_campaign_ref = campaign
	_refresh()
	visible = true


func close() -> void:
	visible = false


var _campaign_ref = null


func _refresh() -> void:
	if _campaign_ref == null:
		return
	var cur: String = _campaign_ref.current_stage()
	_ember.text = "余烬 Ember：%d" % _campaign_ref.ember()
	_head.text = "当前关卡 %s · 已通关 %d / %d" % [
		cur, _campaign_ref.snapshot()["cleared"].size(), _CampaignData.STAGE_ORDER.size()]
	for t in _tiles:
		var sid := String(t["id"])
		var b: Button = t["btn"]
		var st: Label = t["status"]
		var cleared: bool = _campaign_ref.is_cleared(sid)
		var unlocked: bool = _campaign_ref.is_unlocked(sid)
		var is_cur: bool = sid == cur
		b.disabled = not unlocked
		if cleared:
			_Style.button(b, "primary")
			b.modulate = Color(1, 1, 1, 1)
			st.text = "✓ 已通关"
			st.add_theme_color_override("font_color", _Style.C_GOLD)
		elif is_cur:
			_Style.button(b, "normal")
			b.modulate = Color(1, 1, 1, 1)
			st.text = "▶ 当前"
			st.add_theme_color_override("font_color", _Style.C_ALLY)
		elif unlocked:
			_Style.button(b, "normal")
			b.modulate = Color(1, 1, 1, 1)
			st.text = "可挑战"
			st.add_theme_color_override("font_color", _Style.C_TEXT)
		else:
			_Style.button(b, "unavail")
			b.modulate = Color(1, 1, 1, 0.66)
			st.text = "🔒 未解锁"
			st.add_theme_color_override("font_color", _Style.C_TEXT_DIM)


# ---------------------------------------------------------------------------
#  交互
# ---------------------------------------------------------------------------
func _on_tile_pressed(sid: String) -> void:
	if _campaign_ref == null:
		return
	if not _campaign_ref.is_unlocked(sid):
		return
	_campaign_ref.set_current_stage(sid)
	visible = false
	stage_selected.emit(sid)
