extends CanvasLayer
##
## 主界面（Main Menu）覆盖层 —— `main_menu_overlay.gd`
## ---------------------------------------------------------------------------
## 职责：游戏启动后的**第一屏**。三个入口：
##   · 开始游戏 → 交给 `boot.gd` 走现有「选关 → 选包 → 开局」流程；
##   · 卡组图鉴 → 在本层内切到「卡组图鉴」页，浏览**全部 8 个卡包的 80 个卡位**；
##   · 退出游戏 → 发 `quit_requested`（真正退出由调用方决定，本层不直接 quit）。
##
## 🔴 为什么图鉴要「一遍看到全部」而不是按解锁进度藏：
##   卡包解锁只是**节奏阀**，不是内容保密。玩家在选包界面只有 3 个格子，
##   如果连「有哪些流派、每包长什么样」都看不到，选包就退化成盲选。
##   图鉴把 8 包 × 10 张摊开（未解锁的包压暗但仍可见），玩家的选择才成立 ——
##   这与 `card_packs.gd` 文件头「选包 = 选一条 build」同一前提。
##
## 🔴 art-bible 合规（与 `pack_select_overlay.gd` 同一管法）：
##   · 全部控件走 `ui_style.gd`（禁止系统默认控件；按钮四态自定义）；
##   · 玩家可见文本 ≥16px（`_Style.label` 兜底）；
##   · 解锁 / 未解锁同时用**文字 + 明度 + ▲ 角标**表达，不把颜色当唯一通道。
##
## 🔴 分层 200：高于选关 161 / 选包 160 / 结算 150。主界面出现时压住一切战斗 UI；
##   `process_mode = ALWAYS` 让安全窗（tree paused）下也能点。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 不写 `class_name`，调用方 preload。
##

signal start_requested
signal quit_requested

const _Style := preload("res://scripts/ui/ui_style.gd")
const _Packs := preload("res://scripts/data/card_packs.gd")
const _CardText := preload("res://scripts/data/card_text.gd")
const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")

const LAYER := 200

const PAGE_MENU := 0
const PAGE_LIBRARY := 1

## 图鉴单卡尺寸。5 张一行：5 × 278 + 4 × 12 = 1430 ≤ 1776（1920 − 2×72）。
const CARD_SIZE := Vector2(278.0, 126.0)
const MENU_X := 140.0
const LIB_MARGIN_X := 72.0
const LIB_TOP := 148.0

var _built: bool = false
var _page: int = PAGE_MENU

var _menu_page: Control = null
var _library_page: Control = null

var _menu_buttons: Array = []      # Array[Button]
var _menu_markers: Array = []      # Array[Label]（▶ 焦点标记）
var _focus_idx: int = 0
var _status: Label = null

var _lib_head: Label = null
var _lib_scroll: ScrollContainer = null
var _lib_list: VBoxContainer = null
var _back_btn: Button = null
var _pack_blocks: Array = []       # Array[Dictionary]：{id, status, cards}
var _card_entries: Array = []      # Array[Dictionary]：{pack, card, panel, label}


## 背景绘制（CanvasLayer 本身不是 CanvasItem，画不了东西 → 包一层 Control）。
class Backdrop extends Control:
	var host = null

	func _draw() -> void:
		if host != null:
			host._paint_backdrop(self)


func _init() -> void:
	# 🔴 layer 在 _init 钉死（open() 可能在 _ready 之前被调）。
	layer = LAYER


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
	# 🔴 必须不透明：下面是战场场景（WAVE 横幅 / 核心血条），半透明会透出「幽灵 HUD」。
	bg.color = Color(0.031, 0.039, 0.063, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP     # 吃掉点击，防止穿透到战场
	add_child(bg)

	var bd := Backdrop.new()
	bd.host = self
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bd)

	_menu_page = _build_menu()
	_library_page = _build_library()
	_library_page.visible = false
	_refresh_focus()


# --- 页 1：主菜单 -----------------------------------------------------------
func _build_menu() -> Control:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

	var col := VBoxContainer.new()
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = MENU_X
	col.offset_right = MENU_X + 640.0
	col.offset_top = -340.0
	col.offset_bottom = 340.0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(col)

	var title := _Style.label("守 核", 72, _Style.C_GOLD)
	_Style.apply_font(title, "display")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	var en := _Style.label("C O R E B O U N D", 18, _Style.C_STEEL)
	_Style.apply_font(en, "medium")
	en.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(en)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 14.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	var rule := _Style.hline()
	rule.custom_minimum_size = Vector2(360.0, 1.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)

	var desc := _Style.label("肉鸽塔防 · 卡牌构筑 · 径向核心围攻", 18, _Style.C_TEXT)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0.0, 26.0)
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap2)

	# 三个入口（按钮 = 320×52，同一列左对齐；▶ 是键盘焦点标记，形状通道）
	var defs := [["开始游戏", "primary"], ["卡组图鉴", "normal"], ["退出游戏", "ghost"]]
	for i in defs.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mk := _Style.label("", 18, _Style.C_GOLD)
		mk.custom_minimum_size = Vector2(28.0, 0.0)
		mk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mk)
		var b := Button.new()
		b.text = String(defs[i][0])
		b.custom_minimum_size = Vector2(320.0, 52.0)
		b.focus_mode = Control.FOCUS_NONE
		_Style.button(b, String(defs[i][1]))
		b.pressed.connect(_activate.bind(i))
		b.mouse_entered.connect(_focus_on.bind(i))
		row.add_child(b)
		col.add_child(row)
		_menu_buttons.append(b)
		_menu_markers.append(mk)

	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0.0, 22.0)
	gap3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap3)

	_status = _Style.label("", 16, _Style.C_TEXT_DIM)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status)

	var foot := VBoxContainer.new()
	foot.anchor_left = 1.0
	foot.anchor_right = 1.0
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = -520.0
	foot.offset_right = -56.0
	foot.offset_top = -92.0
	foot.offset_bottom = -40.0
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(foot)

	var ver := _Style.label("v0.1.0 · Phase 6 · 点击或 ↑↓ + Enter", 16, _Style.C_STEEL)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(ver)

	return page


# --- 页 2：卡组图鉴 ---------------------------------------------------------
func _build_library() -> Control:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(page)

	var head := VBoxContainer.new()
	head.position = Vector2(LIB_MARGIN_X, 34.0)
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(head)

	var title := _Style.label("卡 组 图 鉴", 34, _Style.C_GOLD)
	_Style.apply_font(title, "display")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	_lib_head = _Style.label("", 16, _Style.C_TEXT_DIM)
	_lib_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_lib_head)

	_back_btn = Button.new()
	_back_btn.text = "返 回"
	_back_btn.custom_minimum_size = Vector2(180.0, 46.0)
	_back_btn.focus_mode = Control.FOCUS_NONE
	_Style.button(_back_btn, "ghost")
	_back_btn.anchor_left = 1.0
	_back_btn.anchor_right = 1.0
	_back_btn.offset_left = -LIB_MARGIN_X - 180.0
	_back_btn.offset_right = -LIB_MARGIN_X
	_back_btn.offset_top = 38.0
	_back_btn.offset_bottom = 84.0
	_back_btn.pressed.connect(back_to_menu)
	page.add_child(_back_btn)

	var hint := _Style.label("滚轮浏览 · Esc 返回主界面", 16, _Style.C_STEEL)
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = -LIB_MARGIN_X - 320.0
	hint.offset_right = -LIB_MARGIN_X
	hint.offset_top = 92.0
	hint.offset_bottom = 116.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(hint)

	_lib_scroll = ScrollContainer.new()
	_lib_scroll.anchor_right = 1.0
	_lib_scroll.anchor_bottom = 1.0
	_lib_scroll.offset_left = LIB_MARGIN_X
	_lib_scroll.offset_top = LIB_TOP
	_lib_scroll.offset_right = -LIB_MARGIN_X
	_lib_scroll.offset_bottom = -34.0
	_lib_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lib_scroll.follow_focus = false
	page.add_child(_lib_scroll)

	_lib_list = VBoxContainer.new()
	_lib_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_list.add_theme_constant_override("separation", 20)
	_lib_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lib_scroll.add_child(_lib_list)

	for i in _Packs.PACKS.size():
		_lib_list.add_child(_make_pack_block(_Packs.PACKS[i], i))

	return page


func _make_pack_block(pack: Dictionary, seq: int) -> Control:
	var pid := String(pack["id"])
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 8)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(head)

	var idx := _Style.label("%02d" % (seq + 1), 16, _Style.C_STEEL)
	_Style.apply_font(idx, "num")
	idx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(idx)

	var emb := _Style.pack_emblem(pid)
	if emb != null:
		var tr := TextureRect.new()
		tr.texture = emb
		tr.custom_minimum_size = Vector2(26.0, 26.0)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(tr)

	var nm := _Style.label(String(pack["name"]), 24, _Style.C_WHITE)
	_Style.apply_font(nm, "display")
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(nm)

	var tag := _Style.label(String(pack["tag_line"]), 16, _Style.C_TEXT_DIM)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tag)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)

	var status := _Style.label("", 16, _Style.C_TEXT_DIM)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(status)

	block.add_child(_Style.hline())

	var row := GridContainer.new()
	row.columns = 5
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(row)

	var cards: Array = []
	for cnm in (pack["cards"] as Array):
		var pc := _make_card(pid, String(cnm))
		row.add_child(pc)
		cards.append(pc)

	_pack_blocks.append({"id": pid, "status": status, "cards": cards})
	return block


func _make_card(pack_id: String, nm: String) -> Control:
	var rar := _CardText.rarity(nm)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = CARD_SIZE
	pc.add_theme_stylebox_override("panel", _Style.card_blueprint("normal", rar))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)

	var name_l := _Style.label(nm, 18, _Style.C_WHITE)
	_Style.apply_font(name_l, "medium")
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_l)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)

	# 稀有度 ▲ 角标（形状通道，与边框色双通道表达）
	var pips := _Style.label("▲".repeat(_Style.rarity_pips(rar)), 16, _Style.rarity_color(rar))
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pips)

	# Tag 电路符号（§5.5）：与商店卡面同一套字形 / 颜色
	var tg := _CardText.tag_of(nm)
	if tg != "":
		var gl := _Style.label(_Style.tag_glyph(tg), 16, _Style.tag_color(tg))
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(gl)

	var desc := _Style.label(_CardText.describe(nm), 16, _Style.C_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_OFF
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)

	_card_entries.append({"pack": pack_id, "card": nm, "panel": pc, "label": desc})
	return pc


# ---------------------------------------------------------------------------
#  展示 / 刷新
# ---------------------------------------------------------------------------
## 打开主界面（菜单页）。由 `boot.gd` 在启动时调用。
func open() -> void:
	_build()
	_page = PAGE_MENU
	_menu_page.visible = true
	_library_page.visible = false
	_refresh_dynamic()
	_refresh_focus()
	visible = true


## 直接打开图鉴页（主界面的「卡组图鉴」入口；也供 UI 截帧探针用）。
func show_library() -> void:
	_build()
	_page = PAGE_LIBRARY
	_menu_page.visible = false
	_library_page.visible = true
	_refresh_dynamic()
	visible = true
	if _lib_scroll != null:
		_lib_scroll.scroll_vertical = 0


func back_to_menu() -> void:
	_page = PAGE_MENU
	if _menu_page != null:
		_menu_page.visible = true
	if _library_page != null:
		_library_page.visible = false
	_refresh_focus()


func close() -> void:
	visible = false


func current_page() -> int:
	return _page


func _refresh_dynamic() -> void:
	var best := _RunMeta.best_wave()
	var unlocked := _Packs.unlocked_ids(best)
	if _status != null:
		_status.text = "最佳波次 W%d · 已解锁 %d / %d 包" % [
			best, unlocked.size(), _Packs.PACKS.size()]
	if _lib_head != null:
		_lib_head.text = "共 %d 张卡 · %d 个卡包 × 每包 %d 张（%d 个卡位）· 未解锁包压暗显示" % [
			_Packs.all_cards().size(), _Packs.PACKS.size(), _Packs.CARDS_PER_PACK,
			_Packs.PACKS.size() * _Packs.CARDS_PER_PACK]
	for blk in _pack_blocks:
		var pid := String((blk as Dictionary)["id"])
		var st: Label = (blk as Dictionary)["status"]
		var on := unlocked.has(pid)
		st.text = "已解锁 · 可带入本局" if on else "最佳波次 W%d 解锁" % _Packs.unlock_wave(pid)
		st.add_theme_color_override("font_color", _Style.C_GOLD if on else _Style.C_TEXT_DIM)
		# 未解锁：整块压暗（明度档位，不改色相 —— 信息仍可读，不是隐藏内容）
		for c in (blk as Dictionary)["cards"]:
			(c as Control).modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.62)


func _refresh_focus() -> void:
	for i in _menu_buttons.size():
		var on := i == _focus_idx
		if i < _menu_markers.size():
			(_menu_markers[i] as Label).text = "▶" if on else ""
		(_menu_buttons[i] as Button).modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.78)


# ---------------------------------------------------------------------------
#  交互
# ---------------------------------------------------------------------------
func _focus_on(i: int) -> void:
	if i < 0 or i >= _menu_buttons.size():
		return
	if _focus_idx != i:
		_focus_idx = i
		_refresh_focus()


func _move_focus(dir: int) -> void:
	if _menu_buttons.is_empty():
		return
	_focus_idx = wrapi(_focus_idx + dir, 0, _menu_buttons.size())
	_refresh_focus()


## 执行第 i 个菜单项。🔴 唯一写状态的地方（测试直接调它）。
func _activate(i: int) -> void:
	match i:
		0:
			start_requested.emit()
		1:
			show_library()
		2:
			quit_requested.emit()


## Esc：图鉴页 → 回菜单；菜单页 → 不响应（主界面没有「上一级」）。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if _page == PAGE_LIBRARY:
		if k == KEY_ESCAPE:
			back_to_menu()
			get_viewport().set_input_as_handled()
		else:
			get_viewport().set_input_as_handled()   # 图鉴期间吃掉按键，不漏到战场
		return
	if k == KEY_UP or k == KEY_W:
		_move_focus(-1)
		get_viewport().set_input_as_handled()
	elif k == KEY_DOWN or k == KEY_S:
		_move_focus(1)
		get_viewport().set_input_as_handled()
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		_activate(_focus_idx)
		get_viewport().set_input_as_handled()
	else:
		# 🔴 主界面压着一局尚未开始的战场：未消费的 Tab / R / 数字键会漏到
		#    `battle_shop._unhandled_input`（打开抽屉 / 刷新 / 买卡）—— 一律吃掉。
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
#  背景绘制（核心遗迹：断裂防线 + 能量导线 + 来袭剪影，零 RNG）
# ---------------------------------------------------------------------------
func _paint_backdrop(ci: Control) -> void:
	var sz := ci.size
	if sz.x < 2.0 or sz.y < 2.0:
		sz = Vector2(1920.0, 1080.0)

	var c := Vector2(sz.x * 0.73, sz.y * 0.51)
	var unit := minf(sz.y, sz.x * 0.58)
	var ally := _Style.C_ALLY
	var enemy := _Style.C_ENEMY
	var steel := _Style.C_STEEL

	ci.draw_circle(c, unit * 0.53, Color(0.035, 0.052, 0.069, 0.92))
	ci.draw_arc(c, unit * 0.53, 0.0, TAU, 160, Color(ally.r, ally.g, ally.b, 0.10), 2.0, true)

	# Three broken armor rings give the radial battlefield the silhouette of a ruined fortress.
	for k in range(3):
		var r := unit * (0.22 + 0.105 * float(k))
		var segs := 8 + k * 3
		for j in range(segs):
			if (j + k * 2) % 7 == 0:
				continue
			var a0 := TAU * float(j) / float(segs) + 0.08 * float(k)
			var a1 := TAU * (float(j) + 0.76) / float(segs) + 0.08 * float(k)
			var alpha := 0.12 - 0.022 * float(k)
			var col := Color(ally.r, ally.g, ally.b, alpha) if j % 3 == 0 else Color(steel.r, steel.g, steel.b, alpha * 0.65)
			ci.draw_arc(c, r, a0, a1, 24, col, 2.0 if k == 0 else 1.0, true)

	# Powered lanes and armored plates lead the eye toward the core.
	for i in range(3):
		var ang := -PI * 0.77 + TAU * float(i) / 3.0
		var dir := Vector2(cos(ang), sin(ang))
		var side := dir.rotated(PI * 0.5)
		ci.draw_line(c + dir * unit * 0.50, c + dir * unit * 0.13, Color(ally.r, ally.g, ally.b, 0.10), 1.0, true)
		for n in range(3):
			var p := c + dir * unit * (0.24 + float(n) * 0.105)
			var w := unit * 0.018
			var plate := PackedVector2Array([p - dir * w - side * w, p + dir * w - side * w, p + dir * w + side * w, p - dir * w + side * w])
			ci.draw_colored_polygon(plate, Color(ally.r, ally.g, ally.b, 0.14 if n == 1 else 0.075))

	# Small hostile wedges sit beyond the breach line.
	for i in range(5):
		var ang := -2.95 + float(i) * 0.46
		var dir := Vector2(cos(ang), sin(ang))
		var p := c + dir * unit * (0.60 + 0.035 * float(i % 2))
		var side := dir.rotated(PI * 0.5)
		var s := unit * (0.014 + 0.002 * float(i % 3))
		var shape := PackedVector2Array([p + dir * s * 1.8, p - dir * s - side * s, p - dir * s + side * s])
		ci.draw_colored_polygon(shape, Color(enemy.r, enemy.g, enemy.b, 0.22))
		ci.draw_polyline(PackedVector2Array([shape[0], shape[1], shape[2], shape[0]]), Color(enemy.r, enemy.g, enemy.b, 0.50), 1.0, true)
		ci.draw_line(p + dir * s * 2.5, p + dir * s * 6.0, Color(enemy.r, enemy.g, enemy.b, 0.20), 1.0, true)

	# Mechanical iris core with six shield contacts.
	ci.draw_circle(c, unit * 0.072, Color(ally.r, ally.g, ally.b, 0.06))
	ci.draw_arc(c, unit * 0.072, 0.0, TAU, 64, Color(ally.r, ally.g, ally.b, 0.48), 2.0, true)
	ci.draw_arc(c, unit * 0.052, 0.18, TAU - 0.22, 64, Color(steel.r, steel.g, steel.b, 0.24), 1.0, true)
	ci.draw_circle(c, unit * 0.026, Color(ally.r, ally.g, ally.b, 0.20))
	ci.draw_circle(c, unit * 0.012, Color(0.86, 0.98, 1.0, 0.88))
	for i in range(6):
		var ang := TAU * float(i) / 6.0
		var dir := Vector2(cos(ang), sin(ang))
		ci.draw_line(c + dir * unit * 0.078, c + dir * unit * 0.095, Color(ally.r, ally.g, ally.b, 0.38), 2.0, true)
