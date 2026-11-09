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

## 🆕 keyart v1 主菜单背景：**menu 低强度档**（30-40% 曝光，为左侧标题/按钮留可读性）。
##    2026-11-08 用户拍板：从 hero 派生底（keyart_menu_hero_v1）换回 menu 档
##    （hero 系派生件保留：keyart_menu_hero_v1 备用 / keyart_stage_bg_v1 用于选关航图）。
##    资产缺失 → 降级回程序化遗迹绘制
const KEYART_BG_PATH := "res://art/2d/ui/keyart_menu_bg_v1.png"

const PAGE_MENU := 0
const PAGE_LIBRARY := 1

## 图鉴单卡尺寸。5 张一行：5 × 320 + 4 × 12 = 1648 ≤ 1764（1920 − 2×72 − 滚动条）。
## 🔴 2026-11-09（第 81 卡）：宽度 278 → 320 是为了**名字行**，不是为了卡片观感。
##    278 时代单卡内宽 = 278 − 24(内边距) − 96(插画) − 8(间距) = 150，
##    名字行还要再让出 ▲▲▲ 与 tag 角标（合计约 50–68）→ 名字实得 82–102px；
##    而 `Thunderhead` 在 18px 下需 120px，`Hemorrhage` 112、`Executioner` 106
##    → 全库 **9 张卡名被省略号吃掉**（实测见 tools/probe_card_name_fit.gd）。
##    加宽 42 后名字实得 124–144，81 张全部不截断；图鉴区本来就富余 326px 没用上。
const CARD_SIZE := Vector2(320.0, 126.0)
const MENU_X := 140.0
const LIB_MARGIN_X := 72.0
const LIB_TOP := 148.0

var _built: bool = false
var _page: int = PAGE_MENU
var _keyart: bool = false        # keyart 贴图是否生效（决定 Backdrop 是否让位）

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
	_Style.set_cursor("default")               # 🆕 v4：全局默认光标（蓝图箭头；资产缺失自动保持系统箭头）


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

	# 🆕 keyart v1 背景层（keyart-style-v1.md §4）：贴图置底、覆盖裁切；
	#    生效时 Backdrop 让位（贴图已含遗迹构图，叠加会双重绘制）。
	if ResourceLoader.exists(KEYART_BG_PATH):
		var kt := TextureRect.new()
		kt.texture = load(KEYART_BG_PATH)
		kt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		kt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		kt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(kt)
		_keyart = true

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
	# 🆕 入口独立成 VBox（separation 10）：ghost 改成下划线式之后有了可见按钮体，
	#    沿用 `col` 的 6px 会把三个入口挤成一整块，与上方标题块失去分组感。
	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 10)
	btn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(btn_box)

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
		btn_box.add_child(row)
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
	# 🆕 180 → 76：ghost 现在带下划线，180 宽的线下面只挂 3 个字（居中），
	#    会变成「一条长线 + 中间一小撮字」。收到 ≈ 文字宽 + 内边距后，
	#    线 ≈ 词的宽度，右端与下方「滚轮浏览 · Esc 返回主界面」同一边界。
	_back_btn.custom_minimum_size = Vector2(76.0, 40.0)
	_back_btn.focus_mode = Control.FOCUS_NONE
	_Style.button(_back_btn, "ghost")
	_back_btn.anchor_left = 1.0
	_back_btn.anchor_right = 1.0
	_back_btn.offset_left = -LIB_MARGIN_X - 76.0
	_back_btn.offset_right = -LIB_MARGIN_X
	_back_btn.offset_top = 42.0
	_back_btn.offset_bottom = 82.0
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
	# 🆕 v5 分组底板（asset-pack-v5-lib）：PanelContainer 9-slice 暗面板把分组从
	#    keyart 背景上托出来（卡缝不再穿透蜂巢）；标题条白烘焙 → modulate 染
	#    包主题色（ui_style.pack_color）。贴图缺失 → 回裸 VBox 原样（判空降级）。
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 8)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	# 🆕 v5 组装：head → 染色标题条（缺失→裸 head+hline 原样）；最后 block → 9-slice 底板。
	var bar_tex := _Style.lib_tex("bar")
	if bar_tex != null:
		var bar := PanelContainer.new()
		var bsb := StyleBoxTexture.new()
		bsb.texture = bar_tex
		bsb.texture_margin_left = 10.0
		bsb.texture_margin_right = 10.0
		bsb.texture_margin_top = 8.0
		bsb.texture_margin_bottom = 8.0
		bar.add_theme_stylebox_override("panel", bsb)
		bar.modulate = _Style.pack_color(pid)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hmg := MarginContainer.new()
		hmg.add_theme_constant_override("margin_left", 20)
		hmg.add_theme_constant_override("margin_right", 12)
		hmg.add_theme_constant_override("margin_top", 4)
		hmg.add_theme_constant_override("margin_bottom", 6)
		hmg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(hmg)
		hmg.add_child(head)
		block.add_child(bar)
	else:
		block.add_child(head)
		block.add_child(_Style.hline())     # 无标题条时保留原分隔线

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
	# 🆕 v5 底板收口：block（标题条 + 卡网格）包进 9-slice 暗面板；缺失 → 裸 block。
	var block_tex := _Style.lib_tex("block")
	if block_tex == null:
		return block
	var plate := PanelContainer.new()
	var sb := StyleBoxTexture.new()
	sb.texture = block_tex
	sb.texture_margin_left = 12.0
	sb.texture_margin_right = 12.0
	sb.texture_margin_top = 12.0
	sb.texture_margin_bottom = 12.0
	plate.add_theme_stylebox_override("panel", sb)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mg := MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 14)
	mg.add_theme_constant_override("margin_right", 14)
	mg.add_theme_constant_override("margin_top", 8)
	mg.add_theme_constant_override("margin_bottom", 10)
	mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(mg)
	mg.add_child(block)
	return plate


func _make_card(pack_id: String, nm: String) -> Control:
	var rar := _CardText.rarity(nm)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = CARD_SIZE
	pc.add_theme_stylebox_override("panel", _Style.card_blueprint("normal", rar))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 🔴 卡宽必须锁死在 CARD_SIZE（现 320）：`custom_minimum_size` 只是**最小**值，
	#    PanelContainer 的实际最小宽还会被最长文本行顶大。实测（tools/probe_ui_rects.gd）
	#    278 时代 8 个包里有 6 个包卡宽不齐，278 / 282 / 304 / 308 / 318 / 326 混排，
	#    最右一列顶到 x=1618 —— 超出卡片网格公共右边界 1536，长卡名的卡直接
	#    压到隔壁格子。⇒ 文字一律 clip（min width 归 0），再加 clip_contents 兜底。
	pc.clip_contents = true

	# 🆕 插画（2026-11-08 批次②③）：左侧 96×96 方形安全区缩放。
	#    资产缺失 / headless 未导入 → card_art() 返回 null → 降级为纯文字条（占满整行）。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(row)
	var art_tex := _Style.card_art(nm)
	if art_tex != null:
		var art := TextureRect.new()
		art.texture = art_tex
		art.custom_minimum_size = Vector2(96.0, 96.0)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)

	var name_l := _Style.label(nm, 18, _Style.C_WHITE)
	_Style.apply_font(name_l, "medium")
	# 🔴 名字必须自己吃下剩余宽度（EXPAND_FILL），**不能**再靠一个 `sp` 占位来顶：
	#    一旦 clip_text = true，Label 的最小宽归 0，若旁边还有一个 EXPAND 的空白 Control，
	#    HBox 会把全部剩余宽度分给那个空白，名字直接拿到 0px 被裁干净（实测：
	#    32 张卡名整行消失）。clip 只在极端长名下才触发省略号。
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_l)

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
	desc.clip_text = true                         # 同上：3 行 `\n` 文本，行宽不参与最小宽
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
		# 🆕 v2 地区口径：状态行读「守住几个地区」而不是「最佳波次」——
		#    后者在 region 口径下已经不驱动任何解锁，摆在主界面上等于假进度条。
		if _Packs.unlock_by_region:
			_status.text = "已守 %d / %d 地区 · 已入手 %d / %d 科技包" % [
				_Packs.owned_regions.size(), _Packs.REGION_ORDER.size(),
				unlocked.size(), _Packs.PACKS.size()]
		else:
			_status.text = "最佳波次 W%d · 已解锁 %d / %d 包" % [
				best, unlocked.size(), _Packs.PACKS.size()]
	if _lib_head != null:
		# 🔴 旧文案「共 81 张卡 …（实际 81 个卡位）」把同一个数字说了两遍，
		#    「基础每包 10 张」又是开发者口径（熔炉包实际 11 张）。改成玩家口径：
		#    总数 + 包数 + 每包下限 + 锁定包的表现。
		_lib_head.text = "%d 张卡 · %d 个卡包 · 每包 %d 张起 · 未解锁包压暗显示" % [
			_Packs.all_cards().size(), _Packs.PACKS.size(), _Packs.CARDS_PER_PACK]
	for blk in _pack_blocks:
		var pid := String((blk as Dictionary)["id"])
		var st: Label = (blk as Dictionary)["status"]
		var on := unlocked.has(pid)
		# 🆕 锁定文案由 `card_packs.lock_hint()` 统一给：region 口径说「守住某地区解锁」，
		#    老口径说「到达 WN 解锁」。两处各写一份必然漂移。
		st.text = "已解锁 · 可带入本局" if on else _Packs.lock_hint(pid, best)
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
	if _keyart:
		return    # keyart 贴图已含完整构图，程序化遗迹仅在贴图缺失时兜底
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
