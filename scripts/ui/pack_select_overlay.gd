extends CanvasLayer
##
## 开局卡包选择覆盖层 —— `pack_select_overlay.gd`
## ---------------------------------------------------------------------------
## 职责：**开打之前**让玩家从已解锁的卡包里挑 `PICKS_PER_RUN` 个（默认 3 个 = 30 张卡）。
##   本组件纯 UI：只读 `run_meta.gd`（已解锁 / 上次选包），只发 `packs_confirmed`。
##   卡池的**实际生效**由调用方（`boot.gd`）在确认后调 `ShopRuntime.set_active_packs()`。
##
## 🔴 为什么要有这一屏（不是"多一层菜单"）：
##   当前每局选择 3 包（30 张），每包十张构成独立流派 build；商店仍以三件商品为一轮。
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

const _CardText := preload("res://scripts/data/card_text.gd")
const _Style := preload("res://scripts/ui/ui_style.gd")
const _Packs := preload("res://scripts/data/card_packs.gd")
const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")

## 单包卡面尺寸（全部卡包同一尺寸 —— X3「不得用布局差异暗示」）。
##   🔴 宽度 180：逻辑视口 1920（`window/size/viewport_*`），实际窗口 1600×900 是
##      `canvas_items` 等比缩放（0.833）—— 按 1920 排：8 包 ×180 + 7×14 = 1538，
##      面板 1590，左右各留 165。**别按 1600 预算**，那会把缩放误判成溢出。
##   🔴 高度 480（2026-11-09 修正）：卡列表改**单列**后 10 行 ×24 + 9×2 = 258px；
##      10 卡包实测内容高 449、熔炉包（11 卡）475 —— 统一取 480（X3：瓦片尺寸必须全同，
##      不能给熔炉包开小灶），余量由底部 spacer 吸收。
##      旧双列方案在 8 包 ×10 卡后失效：网格真实宽 200px（列宽由最长卡名撑开，
##      Thunderhead 95px），瓦片内容区只有 156px → 卡名横向穿到隔壁瓦片。
##      单列内容区 156px 能完整放下全部卡名（最长 95px）。
const TILE_SIZE := Vector2(180.0, 480.0)
## 瓦片间距 · 面板左右内边距（与 `_Style.panel(..., h, v)` 的 h 保持同值）。
const TILE_GAP := 14.0
const PANEL_PAD_X := 26.0

var _built: bool = false
var _tiles: Array = []          # Array[Dictionary]：{id, btn, status, name, tag, cards, roles}
var _sel: Array = []            # Array[String] 当前勾选
var _count_val: Label           # 🆕 已选读数（等宽数字）
var _count_pool: Label          # 🆕 卡池读数（等宽数字）
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

	# 🆕 2026-11-09：居中改由 CenterContainer 完成。
	#   🔴 旧写法 `panel.set_anchors_and_offsets_preset(PRESET_CENTER)` + grow BOTH 在
	#      CanvasLayer 下不可靠（实测 1590 宽的面板落在 x=165，右缘 1755 > 1600）。
	#      容器居中不吃布局时机，宽度也由内容决定。
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var panel := PanelContainer.new()
	# 面板宽 = 瓦片行最小宽 + 左右内边距 —— 由 PACKS 数量推导，加包不再手改。
	var n_packs: int = _Packs.PACKS.size()
	panel.custom_minimum_size = Vector2(
		n_packs * TILE_SIZE.x + (n_packs - 1) * TILE_GAP + PANEL_PAD_X * 2.0, 0.0)
	panel.add_theme_stylebox_override("panel", _Style.panel(_Style.C_ALLY, 2, PANEL_PAD_X, 22.0))
	# 🆕 2026-11-10 「少边框」：四角 L 刻线停用（原 attach_corner_chrome + 辉金 accent）
	holder.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := _Style.label("选 择 卡 包", 34, _Style.C_GOLD)
	_Style.apply_font(title, "display")           # §5.4：界面主标题 = Black 展示字重
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_head = _Style.label("", 16, _Style.C_TEXT_DIM)
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_head)

	vbox.add_child(_Style.hline())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(TILE_GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	for i in _Packs.PACKS.size():
		row.add_child(_make_tile(_Packs.PACKS[i], i))

	vbox.add_child(_Style.hline())

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	vbox.add_child(foot)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(left)

	# 🆕 已选读数（§5.2 数字优先）：「已选 N / M 包 · 卡池 K 张」拆成
	#   中文骨架 + 等宽数字读数 —— 数字跳变不再牵动整行基线（§5.2 等宽红线）。
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 6)
	left.add_child(count_row)
	count_row.add_child(_Style.label("已选", 16, _Style.C_TEXT_DIM))
	_count_val = _Style.label("0 / 0", 22, _Style.C_GOLD)
	_Style.apply_font(_count_val, "num")
	count_row.add_child(_count_val)
	count_row.add_child(_Style.label("包 · 本局卡池", 16, _Style.C_TEXT_DIM))
	_count_pool = _Style.label("0", 22, _Style.C_WHITE)
	_Style.apply_font(_count_pool, "num")
	count_row.add_child(_count_pool)
	count_row.add_child(_Style.label("张", 16, _Style.C_TEXT_DIM))

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


func _make_tile(pack: Dictionary, seq: int) -> Button:
	var pid := String(pack["id"])
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = TILE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	_Style.button(b, "normal")
	b.pressed.connect(_on_tile_pressed.bind(pid))

	# 🆕 资产包 v6：包色顶条（复用 v5 白烘焙标题条，运行时染包色）。
	#    🔴 绝对定位、**不占布局高度** —— 瓦片高度预算紧，任何增高都不允许。
	#    🔴 2026-11-09 修复：首版只设 anchors/offsets，瓦片尺寸还没算出时
	#       TextureRect 被贴图原始尺寸 640×40 钉住，结果一条红带从瓦片一路画到
	#       屏幕外（`clip_contents` 当时也是关的）。现在：EXPAND_IGNORE_SIZE 解除
	#       最小宽 + resized 回调按瓦片宽度重铺 + 瓦片开裁剪兜底。
	#    包色与卡面主色调、图鉴分组标题条共用 ui_style.pack_color()（§2.1 SSOT）。
	#    贴图缺失 / headless → 整条不建，回落纯文本瓦片。
	b.clip_contents = true
	var head_tex := _Style.lib_tex("head_bar")
	if head_tex != null:
		var head := TextureRect.new()
		head.texture = head_tex
		head.modulate = _Style.pack_color(pid)
		head.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		head.stretch_mode = TextureRect.STRETCH_SCALE
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(head)
		var lay_head := func() -> void:
			head.position = Vector2(12.0, 2.0)
			head.size = Vector2(maxf(b.size.x - 24.0, 0.0), 8.0)
		b.resized.connect(lay_head)
		lay_head.call()

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

	# 🆕 蓝图编号（§5.5）：等宽两位序号 —— 兼作数字键 1-9 快捷键提示（_unhandled_input 同序）。
	#    高度占位极小（spacer 吸收），不挤 6 卡列表（见下方徽记行的实测回归注释）。
	var idx := _Style.label("%02d" % (seq + 1), 16, _Style.C_STEEL)
	_Style.apply_font(idx, "num")
	v.add_child(idx)

	# 🆕 卡包徽记（art/2d/icons · 资产包 v1）：id 逐字对齐 PACKS。
	#    🔴 内联进卡名行（28px，**零增高**）—— 瓦片高度固定 292，独立成行会把
	#       6 卡列表推出按钮边界（2026-11-07 首版 56px 独立行的实测回归）。
	#    资产未导入 / 缺失时 `_Style.pack_emblem` 返回 null → 整块跳过（纯文本降级）。
	var emb_tex := _Style.pack_emblem(pid)
	var nm := _Style.label(String(pack["name"]), 22, _Style.C_WHITE)
	_Style.apply_font(nm, "display")              # §5.4：卡包名 = Black 展示字重（与商店卡名同极）
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if emb_tex != null:
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		name_row.alignment = BoxContainer.ALIGNMENT_CENTER
		name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var emb := TextureRect.new()
		emb.texture = emb_tex
		emb.custom_minimum_size = Vector2(28.0, 28.0)
		emb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(emb)
		name_row.add_child(nm)
		v.add_child(name_row)
	else:
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nm)

	var tag := _Style.label(String(pack["tag_line"]), 16, _Style.C_TEXT_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)

	v.add_child(_Style.hline())

	# 🆕 卡列表 = **单列**纯卡名网格（§5.2 数字/实体优先：瓦片是「货架标签」不是卡面——
	#    每卡定位由商店 describe / tag_line 承载）。
	#    🔴 2026-11-09：双列 → 单列。双列在 8 包 ×10 卡后失效：列宽由最长卡名撑开，
	#       网格真实宽 200px > 瓦片内容区 156px，卡名横向穿到隔壁瓦片（实测）。
	#       单列 148px 能完整放下全部 10 个卡名（最长 Thunderhead 95px）。
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grid)
	var card_names: Array = []
	for cnm in (pack["cards"] as Array):
		var l1 := _Style.label(_CardText.display_name(String(cnm)), 16, _Style.C_TEXT)
		l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 兜底：将来若出现更长的卡名，省略号收尾，绝不画到瓦片外（clip_text 同时把
		#   标签最小宽压到 0，列宽改由 EXPAND_FILL 分配，网格不会再被卡名撑宽）。
		l1.clip_text = true
		l1.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		grid.add_child(l1)
		card_names.append(l1)

	# 把状态行顶到底部（中间留白随卡片高度变化）
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)

	var status := _Style.label("", 16, _Style.C_TEXT_DIM)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 🔴 换行而不是裁字：瓦片可用宽只有 156px（180 − 左右各 12 的 margin），
	#    16px 字号放得下约 9 个汉字 —— 地区口径的「守住 永冻科考站」正好在边上，
	#    再长一个字就会被 `clip` 掉后半截。让它在 spacer 里折成两行更安全。
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(status)

	_tiles.append({
		"id": pid, "btn": b, "name": nm, "tag": tag, "status": status,
		"cards": card_names,
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


## 所选包的**并集去重**张数（建筑-only 口径：同一座塔可能出现在多个包里）。
func _pool_size(sel: Array) -> int:
	var seen := {}
	for pid in sel:
		for nm in _Packs.cards_of(String(pid)):
			seen[String(nm)] = true
	return seen.size()


func _refresh() -> void:
	var best := _RunMeta.best_wave()
	var unlocked := _Packs.unlocked_ids(best)
	var req := _Packs.required_picks(best)
	var nxt := _RunMeta.next_unlock_wave()

	# 🆕 2026-11-07：卡包只收建筑卡 → 同类塔会跨包共享，池子是**并集去重**后的张数，
	#   不能再直接拿「包数 × 6」当卡池读数（那会把重复的塔算两遍）。
	_head.text = "本局卡池 = 所选卡包的并集（每包 %d 张建筑卡，熔炉包额外含焚星塔，跨包重复的塔只算一张）" % \
		_Packs.CARDS_PER_PACK
	if _Packs.unlock_by_region:
		# 🆕 v2 地区口径（2026-11-08）：解锁靠「守住地区」，不靠波次 ——
		#    这里若还说「到达 W6 解锁」，等于把玩家骗去刷波次。
		#   🔴 文案说「可用」而不是「已入手」：借用包此刻能选，但守住之前不算你的。
		var borrow_n := 0
		for pid0 in unlocked:
			if _Packs.is_borrowed(String(pid0)):
				borrow_n += 1
		var tag := "" if borrow_n == 0 else "（含 %d 借用）" % borrow_n
		_head.text += "\n已守 %d / %d 地区 · 可用 %d 包%s · 本局任选 %d 包" % [
			_Packs.owned_regions.size(), _Packs.REGION_ORDER.size(),
			unlocked.size(), tag, req]
	elif nxt > 0:
		_head.text += "\n最佳波次 第%d波 · 到达第%d波 解锁下一个卡包" % [best, nxt]
	elif nxt < 0:
		_head.text += "\n全部 %d 个卡包开放 · 本局任选 %d 包" % [unlocked.size(), req]
	else:
		_head.text += "\n最佳波次 第%d波 · 卡包已全部解锁" % best

	for t in _tiles:
		var pid := String(t["id"])
		var b: Button = t["btn"]
		var st: Label = t["status"]
		var locked := not unlocked.has(pid)
		var on := _sel.has(pid)
		var borrowed := _Packs.is_borrowed(pid)
		b.disabled = locked
		if locked:
			_Style.button(b, "unavail")
			b.modulate = Color(1, 1, 1, 0.72)
			st.text = _Packs.lock_hint(pid, best)
			st.add_theme_color_override("font_color", _Style.C_TEXT_DIM)
		else:
			b.modulate = Color(1, 1, 1, 1)
			if on:
				_Style.button(b, "primary")
				st.text = "✓ 已选入本局（本关借用）" if borrowed else "✓ 已选入本局"
				st.add_theme_color_override("font_color", _Style.C_GOLD)
			else:
				_Style.button(b, "normal")
				# 🆕 借用包：本关能带，但守住之前不算"你的" —— 用金色区分于普通可选。
				st.text = "本关借用 · 点击选入" if borrowed else "点击选入"
				st.add_theme_color_override("font_color",
					_Style.C_GOLD if borrowed else _Style.C_TEXT_DIM)
		# 卡名：锁定态压暗（只用透明度档位，不改色相 —— 不改动信息本身）
		#   🔴 主信息（C_TEXT）/ 辅信息分档着色；角色定位已移出瓦片（见 _make_tile 网格注释）
		for l in (t["cards"] as Array):
			(l as Label).add_theme_color_override("font_color",
				_Style.C_STEEL if locked else _Style.C_TEXT)

	_count_val.text = "%d / %d" % [_sel.size(), req]
	_count_pool.text = "%d" % _pool_size(_sel)
	_start.disabled = _sel.size() != req
	if _start.disabled:
		# 🆕 「可用」而不是「已解锁」：region 口径下有"借用的"和"到手的"两种，
		#    说「已解锁」会和瓦片上「本关借用」的文案打架。
		_hint.text = "选满 %d 个卡包后才能开始（可用 %d 个）" % [req, unlocked.size()]
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
