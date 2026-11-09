extends CanvasLayer
##
## 关卡选择覆盖层（大地图版）—— `stage_select_overlay.gd`
## ---------------------------------------------------------------------------
## 职责：**开打之前**让玩家在一张「裂隙航图」大地图上选关进入。
##   本组件纯 UI：只读 `campaign.gd`（已通关 / 已解锁 / Ember），只发 `stage_selected`。
##   波数 / 地图 / 卡组解锁的**实际生效**由调用方（`boot.gd`）在选中后处理。
##
## 🔴 交互：
##   · 鼠标：悬停高亮 + 左下角详情；点击**已解锁**节点直接进入（无二次确认）；
##   · 🔴 锁定节点点击**无反应**（不弹错、不踢人），与放置模式的「点错不踢人」同纪律。
##
## 🔴 art-bible 合规：
##   · 全部文字控件走 `ui_style.gd`（字号 ≥16、调色板只用登记色）；
##   · 画布图形（环 / 连线 / 节点 / 星点）全部 `draw_*`，不引入任何系统默认控件；
##   · 资产包 v3（design/art/asset-pack-v3-map.md）：节点 / 核心底座 / 光环 /
##     章节徽记已贴图化 —— `_ht` 判空降级，缺贴图（headless / 文件丢失）逐项
##     回落到 `draw_*` 旧路径，画面与贴图前逐位一致；
##   · 锁定 / 已通关 / 当前 三态**同时**用形状（锁 / 勾 / 三角）+ 颜色 + 文字表达
##     （§9.2 红线 1：颜色不得是唯一信息通道）—— 状态符号始终由代码画在节点中心。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 不写 `class_name`，调用方 preload。
##

signal stage_selected(stage_id: String)
signal back_requested()

## Spiral display order is independent of campaign unlock rules.
## Escape returns to the main menu.

const _Style := preload("res://scripts/ui/ui_style.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")

## 设计基准（与 `project.godot` 的逻辑视口一致；无树的 headless 断言也用它算点）。
const DESIGN_SIZE := Vector2(1920.0, 1080.0)

const RING_FRAC: Array = [0.40, 0.31, 0.22, 0.14, 0.0]
const ANGLE_START := 200.0
const ANGLE_STEP := 66.0
const MAP_SPREAD := Vector2(1.25, 1.0)

const NODE_R := 27.0        # 六边形节点外接圆半径
const HIT_R := 38.0         # 点击 / 悬停命中半径（比视觉略大，手好点）
const LABEL_GAP := 30.0     # 节点 → 关卡名 的径向间距（留够空隙，标签不压六边形）

## 画布文字字号（🔴 全部 ≥16，与 UI 样式层的下限同口径；绘制侧不受 Label 兜底保护，
##   所以在这里单独钉成常量，`run_ui_style_asserts` §C 直接读这组值）。
const NODE_LABEL_FONT := 18
const CHAPTER_FONT := 18

## 环 → 标题。🔴 与 `CampaignData.CHAPTER_TITLES` 必须逐字一致
##   （`tests/run_campaign_asserts.gd` 的 [9] 会比对；此处的本地副本是为了绘制层
##   不依赖数据层的加载顺序，不是第二个真相源）。
const CHAPTER_TITLES := {
	1: "中枢 · 铁砧",
	2: "外环 · 残存区",
	3: "中环 · 争夺区",
	4: "内环 · 主脑外围",
	5: "主脑 · 核心",
}

var _built: bool = false
var _campaign_ref = null

var _canvas: Control = null
var _hovered: String = ""
var _points: Dictionary = {}       # stage_id -> Vector2（当前画布坐标）

var _ember_val: Label = null
var _clear_val: Label = null
var _detail_name: Label = null
var _detail_meta: Label = null
var _detail_state: Label = null
var _panel: PanelContainer = null

## 资产包 v3 纹理缓存（_draw 每帧跑，禁止每帧 load + exists；与 hud.gd 同款）。
var _tex_cache: Dictionary = {}


## 贴图判空加载：缺失（headless 无 .import / 文件丢失）→ null，调用方降级。
func _ht(fname: String) -> Texture2D:
	if _tex_cache.has(fname):
		return _tex_cache[fname]
	var path := "res://art/2d/ui/" + fname
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[fname] = t
	return t


## 画布：只做绘制与输入转发（CanvasLayer 本身不是 CanvasItem，画不了东西）。
class MapCanvas extends Control:
	var host = null

	func _draw() -> void:
		if host != null:
			host._paint(self)

	func _gui_input(event: InputEvent) -> void:
		if host != null:
			host._on_canvas_input(event, self)


func _init() -> void:
	# 🔴 layer 在 _init 钉死（open() 可能在 _ready 之前被调）。高于选包层 160。
	layer = 161


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


# ---------------------------------------------------------------------------
#  构建（纯节点树；与绘制解耦，headless 断言只调 `_build()` 即可）
# ---------------------------------------------------------------------------
func _build() -> void:
	if _built:
		return
	_built = true

	var bg := ColorRect.new()
	# 🔴 必须不透明：下面是战场场景（WAVE 横幅 / 核心血条），半透明会透出「幽灵 HUD」。
	bg.color = Color(0.031, 0.039, 0.063, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# 🆕 keyart 背景层（keyart-style-v1.md §4 航图档）：hero 派生底（模糊+降饱和+
	#    径向渐晕，中心金核呼应 4-1 核心节点）。资产缺失 → 保持上面的纯色底（headless 安全）。
	#    🔴 铺在最底（bg 之上、_canvas 之下）；STOP 不透传 —— 防止点到空白处落到战场。
	var keyart: Texture2D = _ht("keyart_stage_bg_v1.png")
	if keyart != null:
		var kb := TextureRect.new()
		kb.texture = keyart
		kb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		kb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		kb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		kb.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(kb)

	_canvas = MapCanvas.new()
	_canvas.host = self
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.focus_mode = Control.FOCUS_ALL
	_canvas.resized.connect(_on_canvas_resized)
	_canvas.mouse_exited.connect(_on_canvas_mouse_exited)
	add_child(_canvas)

	_build_header()
	_build_ember()
	_build_detail_panel()
	_build_back_hint()


func _build_back_hint() -> void:
	var hint := _Style.label("Esc 返回主菜单", 18, _Style.C_TEXT_DIM)
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -320.0
	hint.offset_right = -56.0
	hint.offset_top = -104.0
	hint.offset_bottom = -48.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


func return_to_menu() -> void:
	if not visible:
		return
	close()
	back_requested.emit()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		return_to_menu()


func _build_header() -> void:
	var head := VBoxContainer.new()
	head.position = Vector2(56.0, 34.0)
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)

	var title := _Style.label("裂 隙 航 图", 34, _Style.C_GOLD)
	_Style.apply_font(title, "display")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	var sub := _Style.label("点击已解锁关卡进入 · ←→ 选择 / Enter 进入 · 沿航线推进，突破主脑防线", 16, _Style.C_TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sub)

	# 章节目录（徽记 + 章节名双通道；放左上角，不占螺旋节点的位置）。
	#   资产包 v3：◆ 字形 → 章节徽记贴图（ui_map_badge_ch1..4）；缺贴图回落文字行。
	var legend_gap := Control.new()
	legend_gap.custom_minimum_size = Vector2(0.0, 14.0)
	legend_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(legend_gap)
	for ch in range(1, 6):
		var tex: Texture2D = _ht("ui_map_badge_ch%d_v1.png" % ch)
		var row: Control = null
		if tex != null:
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 8)
			hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var ic := TextureRect.new()
			ic.texture = tex
			ic.custom_minimum_size = Vector2(20.0, 20.0)
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(ic)
			var lab := _Style.label(String(CHAPTER_TITLES.get(ch, "")), CHAPTER_FONT, _chapter_color(ch))
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(lab)
			row = hb
		else:
			row = _Style.label("◆  %s" % String(CHAPTER_TITLES.get(ch, "")), CHAPTER_FONT, _chapter_color(ch))
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(row)


func _build_ember() -> void:
	# 右上角：余烬 + 已通关计数（数字优先，§5.2）
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -360.0
	box.offset_top = 34.0
	box.offset_right = -56.0
	box.offset_bottom = 140.0
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var ember_row := HBoxContainer.new()
	ember_row.alignment = BoxContainer.ALIGNMENT_END
	ember_row.add_theme_constant_override("separation", 8)
	ember_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ember_row)
	var ember_lab := _Style.label("余烬", 16, _Style.C_TEXT_DIM)
	ember_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ember_row.add_child(ember_lab)
	_ember_val = _Style.label("0", 28, _Style.C_GOLD)
	_Style.apply_font(_ember_val, "num")
	_ember_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ember_row.add_child(_ember_val)

	_clear_val = _Style.label("", 16, _Style.C_TEXT_DIM)
	_clear_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clear_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_clear_val)


func _build_detail_panel() -> void:
	# 左下角详情卡：悬停即读，不遮挡螺旋中下部的节点标签。
	var wrap := Control.new()
	wrap.anchor_top = 1.0
	wrap.anchor_bottom = 1.0
	wrap.offset_left = 56.0
	wrap.offset_top = -220.0
	wrap.offset_right = 660.0
	wrap.offset_bottom = -48.0
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _Style.panel(_Style.C_ALLY, 2, 20.0, 16.0))
	_Style.attach_corner_chrome(_panel)
	_Style.set_chrome_accent(_panel, _Style.C_GOLD)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)

	_detail_name = _Style.label("", 22, _Style.C_WHITE)
	_Style.apply_font(_detail_name, "display")
	_detail_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_detail_name)

	_detail_meta = _Style.label("", 16, _Style.C_TEXT_DIM)
	_detail_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_detail_meta)

	_detail_state = _Style.label("", 16, _Style.C_ALLY)
	_detail_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_detail_state)


# ---------------------------------------------------------------------------
#  布局：关卡 → 画布坐标（纯函数，可独立断言）
# ---------------------------------------------------------------------------
## 返回 {stage_id: Vector2}。`sz` = 画布尺寸。
func layout_points(sz: Vector2) -> Dictionary:
	var unit := minf(sz.y, sz.x * 0.62)
	var center := Vector2(sz.x * 0.59, sz.y * 0.48)
	var out: Dictionary = {}
	for i in range(_CampaignData.STAGE_ORDER.size()):
		var sid := String(_CampaignData.STAGE_ORDER[i])
		var ch := int(_CampaignData.STAGES[sid].get("chapter", 1))
		var angle := deg_to_rad(ANGLE_START + ANGLE_STEP * float(i))
		out[sid] = center + Vector2.from_angle(angle) * MAP_SPREAD * unit * float(RING_FRAC[ch - 1])
	return out


## 当前画布上的节点坐标（未布局过 → 用设计基准现算）。
func map_point(stage_id: String) -> Vector2:
	if _points.has(stage_id):
		return _points[stage_id]
	return layout_points(DESIGN_SIZE).get(stage_id, Vector2.ZERO)


func _on_canvas_resized() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _on_canvas_mouse_exited() -> void:
	if _hovered != "":
		_hovered = ""
		_refresh_detail()
		if _canvas != null:
			_canvas.queue_redraw()


# ---------------------------------------------------------------------------
#  展示 / 刷新
# ---------------------------------------------------------------------------
## 由 `boot.gd` 调用：读进度 → 刷新锁定态 → 显示。
func open(campaign) -> void:
	_build()
	_campaign_ref = campaign
	_hovered = ""
	if _campaign_ref != null:
		_hovered = String(_campaign_ref.current_stage())
	_refresh()
	visible = true
	if _canvas != null and _canvas.is_inside_tree():
		_canvas.grab_focus()
		_canvas.queue_redraw()


func close() -> void:
	visible = false


func hovered() -> String:
	return _hovered


func _refresh() -> void:
	if _campaign_ref == null:
		return
	_ember_val.text = "%d" % int(_campaign_ref.ember())
	var cleared: Dictionary = _campaign_ref.snapshot().get("cleared", {})
	_clear_val.text = "已通关 %d / %d" % [cleared.size(), _CampaignData.STAGE_ORDER.size()]
	_refresh_detail()
	if _canvas != null:
		_canvas.queue_redraw()


func _refresh_detail() -> void:
	if _campaign_ref == null:
		return
	var sid := _hovered
	if sid == "":
		sid = String(_campaign_ref.current_stage())
	var st: Dictionary = _CampaignData.STAGES.get(sid, {})
	var ch := int(st.get("chapter", 1))
	_detail_name.text = "%s · %s" % [sid, String(st.get("name", ""))]
	_detail_meta.text = "%d 波 · 地图 %s · %s" % [
		int(st.get("wave_count", 0)),
		_map_label(String(st.get("map_id", "tri-fissure"))),
		String(CHAPTER_TITLES.get(ch, "")),
	]
	var cleared: bool = _campaign_ref.is_cleared(sid)
	var unlocked: bool = _campaign_ref.is_unlocked(sid)
	if cleared:
		_detail_state.text = "✓ 已通关 · 点击可重复挑战"
		_detail_state.add_theme_color_override("font_color", _Style.C_GOLD)
	elif unlocked:
		_detail_state.text = "▶ 可挑战 · 点击进入"
		_detail_state.add_theme_color_override("font_color", _Style.C_ALLY)
	else:
		var prev := _prev_stage(sid)
		_detail_state.text = "🔒 未解锁 · 先通关 %s" % prev
		_detail_state.add_theme_color_override("font_color", _Style.C_TEXT_DIM)


func _prev_stage(sid: String) -> String:
	var i := _CampaignData.stage_index(sid)
	if i > 0:
		return String(_CampaignData.STAGE_ORDER[i - 1])
	return "—"


func _map_label(map_id: String) -> String:
	if _CampaignData.map_implemented(map_id):
		return map_id
	return "%s（回落）" % map_id


# ---------------------------------------------------------------------------
#  交互
# ---------------------------------------------------------------------------
## 进入某关。返回是否真的进入（未知 / 锁定 → false，不弹窗、不踢人）。
##   🔴 唯一写状态的地方：`set_current_stage` + 关界面 + 发信号。（测试直接调它）
func enter_stage(sid: String) -> bool:
	if _campaign_ref == null:
		return false
	if not _CampaignData.STAGE_ORDER.has(sid):
		return false
	if not _campaign_ref.is_unlocked(sid):
		return false
	_campaign_ref.set_current_stage(sid)
	visible = false
	stage_selected.emit(sid)
	return true


func _on_canvas_input(event: InputEvent, ci: Control) -> void:
	# 🔴 一律 `accept_event()`：航图压着尚未开局的战场，未消费的鼠标/按键会漏到
	#    battle_shop 的 `_unhandled_input`（空点地图 → 误落子；Esc → 误关抽屉）。
	if event is InputEventMouseMotion:
		ci.accept_event()
		var sid := _hit(_points, (event as InputEventMouseMotion).position)
		if sid != _hovered:
			_hovered = sid
			_refresh_detail()
			ci.queue_redraw()
		return
	if event is InputEventMouseButton:
		ci.accept_event()
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var sid := _hit(_points, mb.position)
			if sid != "":
				enter_stage(sid)
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		ci.accept_event()
		var k := (event as InputEventKey).keycode
		if k == KEY_LEFT or k == KEY_UP:
			_step_hover(-1)
		elif k == KEY_RIGHT or k == KEY_DOWN:
			_step_hover(1)
		elif k == KEY_ENTER or k == KEY_SPACE or k == KEY_KP_ENTER:
			if _hovered != "":
				enter_stage(_hovered)


## 沿推进链移动焦点（越界不循环，停在两端）。
func _step_hover(dir: int) -> void:
	if _campaign_ref == null:
		return
	var cur := _hovered
	if cur == "":
		cur = String(_campaign_ref.current_stage())
	var i := _CampaignData.stage_index(cur)
	if i < 0:
		i = 0
	var n := clampi(i + dir, 0, _CampaignData.STAGE_ORDER.size() - 1)
	var sid := String(_CampaignData.STAGE_ORDER[n])
	if sid != _hovered:
		_hovered = sid
		_refresh_detail()
		if _canvas != null:
			_canvas.queue_redraw()


## 命中测试：返回最近且在 HIT_R 内的节点 id，"" = 没点到。
func _hit(pts: Dictionary, p: Vector2) -> String:
	var best := ""
	var best_d := HIT_R
	for sid in _CampaignData.STAGE_ORDER:
		var k := String(sid)
		if not pts.has(k):
			continue
		var d := p.distance_to(Vector2(pts[k]))
		if d <= best_d:
			best_d = d
			best = k
	return best


# ---------------------------------------------------------------------------
#  绘制
# ---------------------------------------------------------------------------
func _paint(ci: Control) -> void:
	var sz := ci.size
	if sz.x < 2.0 or sz.y < 2.0:
		sz = DESIGN_SIZE
	_points = layout_points(sz)
	_draw_backdrop(ci, sz)
	_draw_tracks(ci, sz)
	_draw_paths(ci)
	_draw_nodes(ci, sz)


func _chapter_color(ch: int) -> Color:
	match ch:
		1:
			return _Style.C_ALLY                      # 中枢 · 己方青（这里是家）
		2:
			return _Style.C_ALLY.lerp(_Style.C_STEEL, 0.35)  # 外环 · 青偏钢
		3:
			return _Style.C_ENEMY.lerp(_Style.C_STEEL, 0.45) # 中环 · 争夺（橙钢混色）
		4:
			return _Style.C_ENEMY                     # 内环 · 敌境橙
	return _Style.C_ALERT                             # 主脑核心 · 警报红


func _draw_backdrop(ci: Control, sz: Vector2) -> void:
	# 1) 星点（确定性伪随机：黄金角散布，零 RNG）
	for i in range(120):
		var x := fmod(float(i) * 0.61803398875 + 0.11, 1.0) * sz.x
		var y := fmod(float(i) * 0.41421356237 + 0.07, 1.0) * sz.y
		var a := 0.05 + 0.07 * fmod(float(i) * 0.37, 1.0)
		ci.draw_circle(Vector2(x, y), 1.1, Color(0.78, 0.85, 1.0, a))

func _draw_tracks(ci: Control, sz: Vector2) -> void:
	var center := Vector2(sz.x * 0.59, sz.y * 0.48)
	var unit := minf(sz.y, sz.x * 0.62)
	for ch in range(1, 5):
		var orbit := PackedVector2Array()
		for k in range(129):
			orbit.append(center + Vector2.from_angle(TAU * float(k) / 128.0) * MAP_SPREAD * unit * float(RING_FRAC[ch - 1]))
		ci.draw_polyline(orbit, Color(_chapter_color(ch), 0.10), 1.0, true)


func _draw_paths(ci: Control) -> void:
	for i in range(_CampaignData.STAGE_ORDER.size() - 1):
		_draw_route(ci, String(_CampaignData.STAGE_ORDER[i]), String(_CampaignData.STAGE_ORDER[i + 1]), false)


func _draw_route(ci: Control, source: String, target: String, gate: bool) -> void:
	var direction: Vector2 = (_points[target] - _points[source]).normalized()
	var p0: Vector2 = _points[source] + direction * (NODE_R + 8.0)
	var p1: Vector2 = _points[target] - direction * (NODE_R + 8.0)
	var done: bool = _campaign_ref != null and _campaign_ref.is_cleared(source)
	var active: bool = _campaign_ref != null and _campaign_ref.is_unlocked(target)
	var col := _Style.C_GOLD if done else (_Style.C_ALLY if active else _Style.C_STEEL)
	var emphasis := source == _hovered or target == _hovered
	var alpha := 0.8 if done or emphasis else 0.30
	var curve := Curve2D.new()
	var bend := p0.distance_to(p1) * 0.18
	var normal := Vector2(-direction.y, direction.x)
	curve.add_point(p0, Vector2.ZERO, direction * bend - normal * bend)
	curve.add_point(p1, -direction * bend - normal * bend, Vector2.ZERO)
	var line := curve.get_baked_points()
	ci.draw_polyline(line, Color(_Style.C_BG, 0.9), 7.0, true)
	if done or emphasis:
		ci.draw_polyline(line, Color(col, 0.08), 9.0, true)
	if gate or not active:
		for k in range(line.size() - 1):
			if k % 4 < 2:
				ci.draw_line(line[k], line[k + 1], Color(col, alpha), 2.0, true)
	else:
		ci.draw_polyline(line, Color(col, alpha), 2.0, true)
	var tip := curve.sample_baked(curve.get_baked_length() * 0.60)
	var ahead := curve.sample_baked(curve.get_baked_length() * 0.60 + 2.0)
	var d := (ahead - tip).normalized()
	var n := Vector2(-d.y, d.x)
	ci.draw_polyline(PackedVector2Array([tip - d * 6 + n * 4, tip, tip - d * 6 - n * 4]), Color(col, alpha), 1.5, true)


func _draw_nodes(ci: Control, sz: Vector2) -> void:
	var node_tex: Texture2D = _ht("ui_map_node_v1.png")
	var node_lk_tex: Texture2D = _ht("ui_map_node_locked_v1.png")
	var halo_tex: Texture2D = _ht("ui_map_node_halo_v1.png")
	var core_tex: Texture2D = _ht("ui_map_node_core_v1.png")
	for i in range(_CampaignData.STAGE_ORDER.size()):
		var sid := String(_CampaignData.STAGE_ORDER[i])
		if not _points.has(sid):
			continue
		var p: Vector2 = _points[sid]
		var st: Dictionary = _CampaignData.STAGES.get(sid, {})
		var ch := int(st.get("chapter", 1))
		var col := _chapter_color(ch)
		var cleared: bool = _campaign_ref != null and _campaign_ref.is_cleared(sid)
		var unlocked: bool = _campaign_ref != null and _campaign_ref.is_unlocked(sid)
		var cur: bool = _campaign_ref != null and sid == String(_campaign_ref.current_stage())
		var hov: bool = sid == _hovered

		var r := NODE_R * (1.08 if hov else 1.0)
		var fill := Color(0.055, 0.063, 0.094, 0.97)
		var ring := col
		var ring_w := 2.0
		if cleared:
			ring = _Style.C_GOLD
			ring_w = 2.4
		elif not unlocked:
			ring = Color(_Style.C_STEEL.r, _Style.C_STEEL.g, _Style.C_STEEL.b, 0.45)
			ring_w = 1.6

		# 终局核心底座（资产包 v3）：画在本节点所有层之下，只给 chapter≥4 的节点。
		#   生成器锚点：底座外接圆 r=50（< 脉冲环 62，不抢脉冲）。
		if ch >= 4 and core_tex != null:
			var seat := 2.0 * 50.0
			ci.draw_texture_rect(core_tex, Rect2(p - Vector2(seat, seat) * 0.5, Vector2(seat, seat)), false)

		# 悬停 / 当前：外侧光环。贴图环 r=36 == 旧路径 NODE_R+9；悬停 tint 白 α0.65
		#   （0.40×0.65≈0.26）、当前 tint 章节色（0.40），与旧 draw_arc 同观感。
		if hov or cur:
			if halo_tex != null:
				var hs := (NODE_R + 9.0) * 2.0
				var tint := Color(1, 1, 1, 0.65) if hov else Color(col.r, col.g, col.b, 1.0)
				ci.draw_texture_rect(halo_tex, Rect2(p - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), false, tint)
			elif hov:
				ci.draw_arc(p, r + 9.0, 0.0, TAU, 48, Color(1, 1, 1, 0.26), 1.5, true)
			elif cur:
				ci.draw_arc(p, r + 7.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.40), 1.5, true)

		# 节点本体：贴图生效时按状态走主件（modulate 染章节色 / 辉金）或锁定专件
		#   （🔴 锁定不能给主件减 alpha —— 整图半透明会让填充透出星点；锁定专件
		#   缺失时直接落旧 _hex，不用主件凑数）；缺失 → 旧 _hex。
		var used_tex := false
		if not unlocked:
			if node_lk_tex != null:
				ci.draw_texture_rect(node_lk_tex, Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false)
				used_tex = true
		elif node_tex != null:
			ci.draw_texture_rect(node_tex, Rect2(p - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, ring)
			used_tex = true
		if not used_tex:
			_hex(ci, p, r, fill, ring, ring_w)

		# 保持节点坐标、贴图与命中范围不变，只叠加机械装甲细节。
		_draw_node_armor(ci, p, r, ring, unlocked, hov, cur)

		# 状态符号（形状通道）：可挑战节点不再空心。
		if cleared:
			_draw_check(ci, p, r * 0.40, _Style.C_GOLD)
		elif not unlocked:
			_draw_lock(ci, p + Vector2(0.0, -2.0), r * 0.35, Color(_Style.C_STEEL.r, _Style.C_STEEL.g, _Style.C_STEEL.b, 0.85))
		elif unlocked:
			_draw_play(ci, p + Vector2(1.0, 0.0), r * 0.38, _Style.C_GOLD if hov else col)

		# 标签统一位于节点下方，避免跨越线路；编号独立放在左侧。
		var name_pos := p + Vector2(0, r + 27.0)
		_draw_center_text(ci, p + Vector2(-r - 26.0, -12.0), sid, 16, ring)
		var label_width := 150.0
		ci.draw_style_box(_Style.panel(Color(ring, 0.25), 1, 8.0, 4.0),
			Rect2(name_pos - Vector2(label_width * 0.5, 15), Vector2(label_width, 30)))
		var name_col := _Style.C_WHITE
		if cleared:
			name_col = _Style.C_GOLD
		elif not unlocked:
			name_col = Color(_Style.C_STEEL.r, _Style.C_STEEL.g, _Style.C_STEEL.b, 0.72)
		_draw_center_text(ci, name_pos, String(st.get("name", "")), NODE_LABEL_FONT, name_col)


## 小尺寸机械站标：倒角装甲、内嵌面板、六向触点；均沿用原外接圆。
## 不改变任何关卡布局或状态判定，贴图缺失的 draw_* 路径也能获得同样细节。
func _draw_node_armor(ci: Control, p: Vector2, r: float, accent: Color,
		unlocked: bool, hovered_node: bool, current_node: bool) -> void:
	var steel := _Style.C_STEEL
	var ink := _Style.C_BG.darkened(0.65)
	var edge := accent if unlocked else Color(steel, 0.50)
	var face := _Style.C_BG.lerp(accent, 0.10 if unlocked else 0.025)
	# 遮住穿过节点的线路；实体面板不能随锁定状态变透明。
	_hex(ci, p + Vector2(0.0, 2.5), r + 2.0, ink, Color(steel, 0.25), 1.0)
	_hex(ci, p, r, face, edge, 2.0 if unlocked else 1.4)

	# 上亮下暗的六块倒角装甲，避免只有一圈细线的纸片感。
	for k in range(6):
		var a := deg_to_rad(60.0 * float(k) - 90.0)
		var b := deg_to_rad(60.0 * float(k + 1) - 90.0)
		var d0 := Vector2(cos(a), sin(a))
		var d1 := Vector2(cos(b), sin(b))
		var bevel := PackedVector2Array([
			p + d0 * (r - 2.0), p + d1 * (r - 2.0),
			p + d1 * (r - 6.5), p + d0 * (r - 6.5),
		])
		var lit := k == 0 or k == 4 or k == 5
		ci.draw_colored_polygon(bevel, Color(steel, (0.20 if lit else 0.065) if unlocked else (0.13 if lit else 0.045)))
		var contact := p + (d0 + d1).normalized() * (r - 3.0)
		ci.draw_line(contact - (d1 - d0).normalized() * 2.5,
			contact + (d1 - d0).normalized() * 2.5,
			Color(accent if unlocked else steel, 0.85 if unlocked else 0.32), 1.8, true)

	# 内框和深色凹槽衬托状态符号，保证小窗下锁头与勾仍清晰。
	_hex(ci, p, r * 0.67, ink, Color(edge, 0.58), 1.0)
	ci.draw_circle(p, r * 0.45, Color(accent if unlocked else steel, 0.07 if unlocked else 0.025))
	ci.draw_arc(p, r * 0.54, -PI * 0.85, -PI * 0.15, 20,
		Color(accent if unlocked else steel, 0.45 if unlocked else 0.16), 1.1, true)
	ci.draw_arc(p, r * 0.54, PI * 0.15, PI * 0.85, 20,
		Color(accent if unlocked else steel, 0.27 if unlocked else 0.10), 1.1, true)

	# 焦点只加强外侧短弧和定位刻度，不改变节点尺寸或邻居间距。
	if hovered_node or current_node:
		var focus_color := _Style.C_GOLD if hovered_node and unlocked else accent
		var intensity := 0.9 if hovered_node else 0.48
		for k in range(3):
			var a := deg_to_rad(-75.0 + 120.0 * float(k))
			ci.draw_arc(p, r + 5.0, a, a + deg_to_rad(38.0), 12,
				Color(focus_color, intensity), 2.0, true)
			var d := Vector2(cos(a), sin(a))
			ci.draw_line(p + d * (r + 5.0), p + d * (r + 8.0),
				Color(focus_color, intensity), 1.5, true)


## 标签落点：节点外接圆外再推「标签包围盒沿 dir 方向的半长」，保证不压六边形。
func _label_pos(p: Vector2, dir: Vector2, r: float, txt: String, fs: int) -> Vector2:
	var f: Font = _Style.font_medium()
	var w := 0.0
	if f != null:
		w = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ext := absf(dir.x) * w * 0.5 + absf(dir.y) * float(fs) * 0.5
	return p + dir * (r + 12.0 + ext)


func _chapter_indices(ch: int) -> Array:
	var out: Array = []
	for i in range(_CampaignData.STAGE_ORDER.size()):
		var sid := String(_CampaignData.STAGE_ORDER[i])
		var st: Dictionary = _CampaignData.STAGES[sid]
		if int(st.get("chapter", 1)) == ch:
			out.append(i)
	return out


func _hex(ci: Control, p: Vector2, r: float, fill: Color, border: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in range(6):
		var a := deg_to_rad(60.0 * float(k) - 90.0)
		pts.append(p + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, border, w, true)


func _draw_check(ci: Control, p: Vector2, s: float, col: Color) -> void:
	ci.draw_line(p + Vector2(-s, 0.0), p + Vector2(-s * 0.25, s * 0.72), col, 2.6, true)
	ci.draw_line(p + Vector2(-s * 0.25, s * 0.72), p + Vector2(s, -s * 0.70), col, 2.6, true)


func _draw_lock(ci: Control, p: Vector2, s: float, col: Color) -> void:
	var body := Rect2(p + Vector2(-s, -s * 0.05), Vector2(s * 2.0, s * 1.35))
	ci.draw_rect(body, col, false, 2.0)
	ci.draw_arc(p + Vector2(0.0, -s * 0.10), s * 0.62, PI, TAU, 20, col, 2.0, true)


func _draw_play(ci: Control, p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([
		p + Vector2(-s * 0.55, -s),
		p + Vector2(s * 0.85, 0.0),
		p + Vector2(-s * 0.55, s),
	])
	ci.draw_colored_polygon(pts, col)


## 以 `p` 为视觉中心画一行文字（y 按字高折半，避免基线下沉）。
func _draw_center_text(ci: Control, p: Vector2, txt: String, fs: int, col: Color) -> void:
	if txt == "":
		return
	var f: Font = _Style.font_medium()
	if f == null:
		return
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := p.y + float(fs) * 0.35
	var pos := Vector2(p.x - w * 0.5, y)
	# 深色投影：节点标签会压在轨道线上，没有底衬会糊
	ci.draw_string(f, pos + Vector2(1.5, 1.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55))
	ci.draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
