extends RefCounted
##
## 统一 UI 样式层（**纯静态助手 / 无状态 / 无玩法耦合**）
## ---------------------------------------------------------------------------
## 依据：`design/art/art-bible.md`
##   · §2.2 主色板 —— 所有 hex **逐字取自**该表，不在此处二次发明颜色
##   · §5.1 总体风格 —— 「所有主要面板：深色底 + 亮色描边 + 内部细分隔线」；
##     「**禁止使用系统默认控件**；所有控件为自定义 Control 节点」；
##     「按钮/卡牌：默认微下沉，悬停抬起 + 缩放 1.05，点击下压 + 缩放 0.97，0.12s 弹性缓动」
##   · §5.2 信息层级 —— 数字 > 图标 > 文字 > 装饰
##   · §9.1 P0 —— 玩家可见文本最小字号 **≥ 16px**
##
## 🔴 为什么要有这一层（本次改造的根因）：
##    改造前 `shop_overlay.gd` **一个 StyleBox 都没有**（全工程只有 hud 的 F3 面板与引导浮层设过），
##    于是商店抽屉 = 透明背景 + 3 张无边框"漂浮文字卡" + 十余个 **Godot 默认灰色按钮**。
##    直接违反 §5.1「禁止使用系统默认控件」。本文件把样式收敛成单一来源，三处 UI 共用。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → **不写 `class_name`**；
##    调用方一律 `const _Style := preload("res://scripts/ui/ui_style.gd")`。
##

# ---------------------------------------------------------------------------
#  调色板（art-bible §2.2，逐字对齐；🔴 不得在此新增未登记色）
# ---------------------------------------------------------------------------
const C_BG := Color(0.078, 0.090, 0.149)        # #141726 夜幕紫（面板底）
const C_ALLY := Color(0.243, 0.816, 0.910)      # #3ED0E8 耀青（玩家极 / 描边）
const C_ALLY_DARK := Color(0.102, 0.420, 0.490) # #1A6B7D 深青（按下态底）
const C_GOLD := Color(1.000, 0.788, 0.290)      # #FFC94A 辉金（资源 / 收益）
const C_ENEMY := Color(1.000, 0.420, 0.239)     # #FF6B3D 熔橙（敌人极）
const C_ALERT := Color(1.000, 0.180, 0.306)     # #FF2E4E 警报红
const C_TEXT := Color(0.784, 0.812, 0.855)      # #C8CFDA 正文
const C_TEXT_DIM := Color(0.545, 0.580, 0.647)  # #8B94A5 辅助
const C_STEEL := Color(0.604, 0.647, 0.694)     # #9AA5B1 钢灰（非活动 / 空槽）
const C_WHITE := Color(1.0, 1.0, 1.0)

## 几何令牌（全局统一，避免各处硬编码打架）
const RADIUS := 6                    # 统一圆角
const BORDER_W := 1                  # 常规描边
const BORDER_W_EMPH := 2             # 强调描边
## §9.1 P0：玩家可见文本最小字号（F3 调试面板为 dev-only 豁免，不走本层）
const FONT_MIN := 16
## §5.1：悬停 / 按下缩放与时长
const SCALE_HOVER := 1.05
const SCALE_PRESS := 0.97
const MOTION_SEC := 0.12


# ---------------------------------------------------------------------------
#  StyleBox 工厂
# ---------------------------------------------------------------------------
static func _base(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	return sb


static func _pad(sb: StyleBoxFlat, h: float, v: float) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## 主面板（商店抽屉 / 弹窗底座）：深色底 + 亮色描边 + 圆角 + 内边距。
static func panel(border: Color = C_ALLY, border_w: int = BORDER_W_EMPH,
		h: float = 16.0, v: float = 14.0) -> StyleBoxFlat:
	var sb := _base(Color(C_BG.r, C_BG.g, C_BG.b, 0.94), border, border_w, RADIUS)
	return _pad(sb, h, v)


## 商品卡 / 信息卡：比面板略亮一档（层次 §5.6 双焦点），描边用钢灰（非活动）——
##   🔴 X3：三个商品位**必须**传同一个 state，样式永远一致。
static func card(state: String = "normal") -> StyleBoxFlat:
	var bg := Color(0.118, 0.137, 0.196, 1.0)     # 比面板底亮一档 → 卡片"浮起来"
	var border := Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.55)
	var bw := BORDER_W
	match state:
		"affordable":                              # 买得起：描边提亮（颜色**不是唯一通道**，
			border = C_ALLY                        #   可购性另有 ✓/✗ 字形冗余，见 §9.2 红线1）
			bw = BORDER_W_EMPH
		"dim":                                     # 买不起 / 无卡：整体压暗
			bg = Color(0.098, 0.113, 0.161, 1.0)
	return _pad(_base(bg, border, bw, RADIUS), 10.0, 10.0)


## 内嵌槽（预算条轨道 / 血条底槽）
static func inset() -> StyleBoxFlat:
	var sb := _base(Color(0.055, 0.063, 0.106, 1.0), Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.30),
		BORDER_W, 4)
	return _pad(sb, 0.0, 0.0)


## 填充条（预算条已用量 / 波次进度）——圆角由调用方按 rect 撑开
static func bar_fill(col: Color) -> StyleBoxFlat:
	var sb := _base(col, col, 0, 4)
	return _pad(sb, 0.0, 0.0)


## 细分隔线（§5.1「内部细分隔线」）：1px 极淡横线，用于分区
static func divider() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.18)
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


# ---------------------------------------------------------------------------
#  按钮（§5.1：自定义控件 + 悬停抬起 / 按下缩放）
# ---------------------------------------------------------------------------
## 变体：
##   `primary` 金描边 + 金字（安全窗推进类主操作）
##   `normal`  青描边 + 白字（常规操作）
##   `ghost`   无底无边 + 暗字（次级 / 跳过）
##   `danger`  红描边 + 红字（受损处置类）
##   `unavail` 钢灰 + 暗字（**明确不可用**，不用 emoji 占位说明）
static func button(b: Button, variant: String = "normal") -> void:
	if b == null:
		return
	var col := C_ALLY
	var font_col := C_TEXT
	var bg := Color(C_BG.r, C_BG.g, C_BG.b, 0.92)
	var bw := BORDER_W
	var radius := RADIUS
	match variant:
		"primary":
			col = C_GOLD
			font_col = C_GOLD
			bw = BORDER_W_EMPH
		"ghost":
			col = Color(0, 0, 0, 0)
			bw = 0
			bg = Color(0, 0, 0, 0)
			font_col = C_TEXT_DIM
		"danger":
			col = C_ALERT
			font_col = C_ALERT
		"unavail":
			col = Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.35)
			font_col = Color(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 0.85)
			bg = Color(C_BG.r, C_BG.g, C_BG.b, 0.55)

	var normal := _base(bg, col, bw, radius)
	_pad(normal, 12.0, 8.0)

	# 悬停：底提亮 + 描边加粗（沿 §5.1「悬停抬起」，位移由 _attach_motion 负责）
	var hover := _base(bg.lightened(0.08) if bg.a > 0.0 else Color(1, 1, 1, 0.06),
		col.lightened(0.12) if col.a > 0.0 else Color(0, 0, 0, 0), bw, radius)
	_pad(hover, 12.0, 8.0)

	# 按下：微下沉（视觉上压暗，配合 scale 0.97）
	var pressed := _base(bg.darkened(0.18) if bg.a > 0.0 else Color(0, 0, 0, 0.12),
		col, bw, radius)
	_pad(pressed, 12.0, 8.0)

	var dis := _base(Color(C_BG.r, C_BG.g, C_BG.b, 0.55),
		Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.30), BORDER_W, radius)
	_pad(dis, 12.0, 8.0)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())   # 去掉系统虚线焦点框
	b.add_theme_color_override("font_color", font_col)
	b.add_theme_color_override("font_hover_color", font_col.lightened(0.15))
	b.add_theme_color_override("font_pressed_color", font_col)
	b.add_theme_color_override("font_disabled_color",
		Color(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 0.75))
	b.add_theme_font_size_override("font_size", FONT_MIN)
	_attach_motion(b)


## §5.1 弹性缓动：悬停 1.05 / 按下 0.97 / 0.12s。
##   🔴 `scale` 不参与容器布局（容器按 size 排版）⇒ 仅视觉缩放，不会推动邻居。
static func _attach_motion(b: Button) -> void:
	if b.has_meta("ui_motion"):
		return
	b.set_meta("ui_motion", true)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			_scale_to(b, SCALE_HOVER))
	b.mouse_exited.connect(func() -> void:
		_scale_to(b, 1.0))
	b.button_down.connect(func() -> void:
		if not b.disabled:
			_scale_to(b, SCALE_PRESS))
	b.button_up.connect(func() -> void:
		if not b.disabled:
			_scale_to(b, SCALE_HOVER))


static func _scale_to(b: Button, k: float) -> void:
	if not is_instance_valid(b):
		return
	b.pivot_offset = b.size * 0.5
	if b.has_meta("ui_tw"):
		var old = b.get_meta("ui_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(k, k), MOTION_SEC).set_trans(Tween.TRANS_CUBIC)
	b.set_meta("ui_tw", tw)


# ---------------------------------------------------------------------------
#  Label 便捷设置（统一字号下限，§9.1 P0）
# ---------------------------------------------------------------------------
## 建 Label 并立刻套字号 / 颜色。`size` 低于 FONT_MIN 时**强制抬到 FONT_MIN**
##   —— 玩家可见文本不得低于 16px（art-bible §9.1 P0）。
static func label(text: String, size: int = FONT_MIN, col: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(size, FONT_MIN))
	l.add_theme_color_override("font_color", col)
	return l


## 横线分隔（§5.1）：返回一个 1px 高的 Control；容器里用 SIZE_EXPAND_FILL 撑满。
static func hline(alpha: float = 0.18) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, alpha)
	r.custom_minimum_size = Vector2(0.0, 1.0)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
