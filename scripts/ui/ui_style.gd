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
	# 🆕 2026-11-10 「少边框」方向：所有面统一**零描边**，层级靠色块明度差 + 文字表达。
	#    border/border_w 参数保留（API 兼容，调用方无需改动），内部一律不画。
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(radius)
	return sb


static func _pad(sb: StyleBoxFlat, h: float, v: float) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## 三级入口专用底座：**全透明底 + 仅底部一条 2px 线**。
##   🔴 为什么不能四态全透明（改造前的写法）：按钮 `custom_minimum_size` 是 320×52，
##      但无底无边 ⇒ 玩家看到的只是一行 16px 灰字，视觉重心落在文字上，
##      于是「按钮 52 高 + 容器 separation 6」算出来的 6px 间距，看起来忽大忽小，
##      三个入口像三段散落的文字而不是一列控件。
##      下划线给出**可见的按钮体**（宽 = 按钮宽），仍比 normal 弱一档：
##      不填底、不描边、hover 不抬底，只把线点亮。
##   🔴 线必须 2px：逻辑视口 1920×1080 在 1600×900 窗口里是 ×0.833 缩放，
##      1px 逻辑线落到屏幕上只有 0.83px，被抗锯齿混进背景直接看不见
##      （和资产包 v6 承托板顶部亮线同一个坑）。
static func _ghost_box(line: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.border_width_bottom = 2
	sb.border_color = line
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


## 主面板（商店抽屉 / 弹窗底座）：深色底 + 亮色描边 + 圆角 + 内边距。
# ---------------------------------------------------------------------------
#  九宫格面板（art/2d/ui · 资产包 v1 批次④ · 渐进替换）
# ---------------------------------------------------------------------------
## 🔴 三条红线（与按钮同一管法）：
##   ① 描边色带**真透明**（alpha < 0.9）或底半透明叠加语义 → 走 StyleBoxFlat 旧路径
##      （HUD 积分卡 0.28 / 血条底槽 0.75 属「透出下层」语义，贴图表达不了）；
##   ② 描边色只认 §2.2 登记色映射（耀青→ui_panel_9slice / 警报红→ui_panel_alert_9slice），
##      其余颜色回落 StyleBoxFlat —— 不做运行时染色（modulate 会连底色一起染）；
##   ③ 资产缺失整体降级（headless 安全），content padding 仍由调用方的 h/v 参数决定。
const PANEL_TEX_DIR := "res://art/2d/ui/"
const PANEL_NINE_MARGIN := 32.0        # manifest.json：ui_panel_* 边距 32

static var _panel_tex_cache: Dictionary = {}

static func _panel_tex(border: Color) -> Texture2D:
	var variant := ""
	if _close(border, C_ALLY):
		variant = "ui_panel_9slice"
	elif _close(border, C_ALERT):
		variant = "ui_panel_alert_9slice"
	if variant == "":
		return null
	if _panel_tex_cache.has(variant):
		return _panel_tex_cache[variant]
	var path := PANEL_TEX_DIR + variant + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_panel_tex_cache[variant] = tex
	return tex


static func _panel_9slice(tex: Texture2D, h: float, v: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = PANEL_NINE_MARGIN
	sb.texture_margin_top = PANEL_NINE_MARGIN
	sb.texture_margin_right = PANEL_NINE_MARGIN
	sb.texture_margin_bottom = PANEL_NINE_MARGIN
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## 色值近似比较（面板贴图变体映射用；阈值 1/255 —— 同一登记色常量才命中）
static func _close(a: Color, b: Color, eps: float = 0.004) -> bool:
	return absf(a.r - b.r) < eps and absf(a.g - b.g) < eps and absf(a.b - b.b) < eps


static func panel(border: Color = C_ALLY, border_w: int = BORDER_W_EMPH,
		h: float = 16.0, v: float = 14.0) -> StyleBox:
	# 🆕 2026-11-10 v4 收敛：本层服务**菜单 / 选关 / 选包 / 结算 / 弹窗**，保持 v3 半透明
	#    深色块（零描边）；「仅文字」只作用于关卡内持久 UI（由 battle_theme 层承担）。
	var sb := _base(Color(C_BG.r, C_BG.g, C_BG.b, 0.94), border, border_w, RADIUS)
	return _pad(sb, h, v)


## 商品卡 / 信息卡：比面板略亮一档（层次 §5.6 双焦点）——
##   🔴 X3：三个商品位**必须**传同一个 state，样式永远一致。
static func card(state: String = "normal") -> StyleBoxFlat:
	# v3 色块（可购性 = 底色提亮 + ✓/✗ 字形 + 价格色）；关卡内卡片走 battle_theme（透明）。
	var bg := Color(0.118, 0.137, 0.196, 1.0)
	match state:
		"affordable":
			bg = bg.lightened(0.05)
		"dim":
			bg = Color(0.098, 0.113, 0.161, 1.0)
	return _pad(_base(bg, C_STEEL, BORDER_W, RADIUS), 10.0, 10.0)


# ---------------------------------------------------------------------------
#  Tag 电路符号（art-bible §5.5 卡牌蓝图风 · 2026-11-07 落地）
# ---------------------------------------------------------------------------
## 颜色**逐字复用** §2.2 已登记色（本表不发明任何新色）；同色 tag 靠**字形**区分
##   （§9.2 红线①：颜色不得是唯一通道）。字形取 Unicode 几何符号（Noto Sans SC 全覆盖）。
const TAG_COLORS := {
	"fire": C_ENEMY,      # 熔橙
	"frost": C_ALLY,      # 耀青
	"pierce": C_GOLD,     # 辉金
	"shock": C_ALERT,     # 警报红
	"sunder": C_STEEL,    # 钢灰
	"hex": C_TEXT,        # 正文
	"true": C_WHITE,      # 白
}
const TAG_GLYPHS := {
	"fire": "◇", "frost": "●", "pierce": "△", "shock": "≈",
	"sunder": "▽", "hex": "◐", "true": "◎",
}


static func tag_color(tag: String) -> Color:
	return TAG_COLORS.get(tag, C_STEEL)


static func tag_glyph(tag: String) -> String:
	return String(TAG_GLYPHS.get(tag, "—"))


## 蓝图卡面（§5.5「卡牌 = 机械蓝图」）：**直角**（圆角清零 → 工程图语言）+
##   细描边 + 与 card() 同族的底色档位。三态与 `card()` 一一对应（affordable / normal / dim）。
##   🔴 X3：三个商品位必须传同一 state；角标刻线由调用方的 chrome 控件绘制。
##   （实现见下方「稀有度五级色阶」节内的 `card_blueprint(state, rarity)` —— 支持稀有度边框。）


# ---------------------------------------------------------------------------
#  稀有度五级色阶（art-bible §2.3 逐字 · P1-6 落地 2026-11-07）
# ---------------------------------------------------------------------------
## 🔴 色号逐字取自 art-bible §2.3，本表不发明新色。稀有度**不可只靠颜色**（§9.2 红线①）：
##    边框粗细（1/2/2/3/3）与角标 ▲ 数（1–5，调用方渲染）同步变化。
##    可购性**不走边框**（边框=稀有度）：可购性仍由 ✓/✗ 字形 + 价格色 + 角刻线 accent 表达。
const RARITY := {
	"common":    {"col": Color(0.604, 0.647, 0.694), "bw": 1, "pips": 1},  # 石灰 #9AA5B1（= C_STEEL）
	"uncommon":  {"col": Color(0.310, 0.851, 0.541), "bw": 2, "pips": 2},  # 苔绿 #4FD98A
	"rare":      {"col": Color(0.243, 0.659, 1.000), "bw": 2, "pips": 3},  # 湖蓝 #3EA8FF
	"epic":      {"col": Color(0.706, 0.361, 1.000), "bw": 3, "pips": 4},  # 幽紫 #B45CFF
	"legendary": {"col": Color(1.000, 0.690, 0.125), "bw": 3, "pips": 5},  # 鎏金 #FFB020
}

static func rarity_color(tier: String) -> Color:
	var d: Dictionary = RARITY.get(tier, RARITY["common"])
	return d["col"]


static func rarity_pips(tier: String) -> int:
	var d: Dictionary = RARITY.get(tier, RARITY["common"])
	return int(d["pips"])


## 蓝图卡面 · 稀有度变体：`rarity` 非空时边框 = 稀有度色 / 粗细（§2.3），
##   `state` 仍管明暗（dim 压暗底色）。`rarity` 为空时行为与改前逐位一致（兼容）。
## 蓝图卡面 · 稀有度变体：🆕 2026-11-10 「少边框」后稀有度**不走边框**，
##   改为**底色微染稀有度色**（色块，lerp 0.08 保持可读）+ 角标 ▲ 数（调用方渲染）双通道。
##   `state` 仍管明暗（dim 压暗底色）。`rarity` 为空时行为与普通卡面一致（兼容）。
static func card_blueprint(state: String = "normal", rarity: String = "") -> StyleBoxFlat:
	# v3：稀有度 = 底色微染色块 + ▲ 数（1–5）双通道。
	var bg := Color(0.118, 0.137, 0.196, 1.0)
	if rarity != "":
		var rd: Dictionary = RARITY.get(rarity, RARITY["common"])
		bg = bg.lerp(rd["col"], 0.08)
	match state:
		"affordable":
			bg = bg.lightened(0.05)
		"dim":
			bg = Color(0.098, 0.113, 0.161, 1.0)
	return _pad(_base(bg, C_STEEL, BORDER_W, 2), 10.0, 10.0)


# ---------------------------------------------------------------------------
#  图标资产注册表（art/2d/icons · 资产包 v1 · 与字体同一管法）
# ---------------------------------------------------------------------------
## 🔴 lazy load + 判空兜底：资产缺失 / 未导入（headless 无 .import）时返回 null，
##    调用方降级为纯文本 —— 宁可无图也不能让 preload 炸掉 UI（含 headless 测试）。
const ICON_DIR := "res://art/2d/icons/"

static var _icon_cache: Dictionary = {}

static func icon(icon_name: String) -> Texture2D:
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	# 🔴 命名 §10.2 四段式含版本段 `_v1`：调用方可不带版本段（icon("ic_scrap")），
	#    已带则原样用（pack_emblem 传 "ic_pack_core_v1"）—— 两种习惯都命中同一文件。
	var stem := icon_name if icon_name.ends_with("_v1") else icon_name + "_v1"
	var path := ICON_DIR + stem + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_icon_cache[icon_name] = tex
	return tex


## 卡包徽记：`card_packs.PACKS` 的 id → `ic_pack_<id>_v1`（资产包 v1 与包 id 逐字对齐）。
static func pack_emblem(pack_id: String) -> Texture2D:
	return icon("ic_pack_" + pack_id + "_v1")


# ---------------------------------------------------------------------------
#  卡面插画注册表（art/2d/cards · 2026-11-08 批次②③）：卡名 → card_<name>_v1_460
# ---------------------------------------------------------------------------
## 🔴 与 icon() 同一管法：lazy load + 判空兜底（资产缺失 / 未导入时返回 null，
##    调用方降级为无图版式 —— 宁可无图也不能让 preload 炸掉 UI，含 headless 测试）。
##    插画是 460×460 安全区透明底（keyout 产物），由调用方用 KEEP_ASPECT_CENTERED 缩放。
const CARD_ART_DIR := "res://art/2d/cards/"

static var _card_art_cache: Dictionary = {}
static var _card_backdrop_cache: Dictionary = {}
const CARD_BACKDROP_TINT := Color(0.40, 0.44, 0.50, 1.0)
const _BackdropPacks := preload("res://scripts/data/card_packs.gd")
static var _card_pack_cache: Dictionary = {}

static func card_pack_id(card_name: String) -> String:
	if _card_pack_cache.has(card_name):
		return _card_pack_cache[card_name]
	for pack in _BackdropPacks.PACKS:
		if pack["cards"].has(card_name):
			_card_pack_cache[card_name] = String(pack["id"])
			return String(pack["id"])
	return "core"

static func card_backdrop(_tier: String, card_name: String = "") -> Texture2D:
	var pack_id := card_pack_id(card_name)
	var scenery_path := "res://art/2d/cards/card_background_%s_v1.png" % pack_id
	var cache_key := "pack:" + pack_id
	if _card_backdrop_cache.has(cache_key):
		return _card_backdrop_cache[cache_key]
	if ResourceLoader.exists(scenery_path):
		var scenery: Texture2D = load(scenery_path)
		if scenery != null:
			var image := scenery.get_image()
			if image != null and not image.is_empty():
				if image.is_compressed():
					image.decompress()
				image.resize(96, 96, Image.INTERPOLATE_LANCZOS)
				var accent := pack_color(pack_id)
				for pixel_y in range(64, 96):
					var amount := smoothstep(64.0, 82.0, float(pixel_y)) * 0.38
					for pixel_x in range(96):
						var pixel := image.get_pixel(pixel_x, pixel_y)
						var brightness := pixel.get_luminance()
						var tinted := Color(accent.r, accent.g, accent.b) * brightness * 1.6
						tinted.a = pixel.a
						image.set_pixel(pixel_x, pixel_y, pixel.lerp(tinted, amount))
				image.resize(256, 256, Image.INTERPOLATE_BILINEAR)
				scenery = ImageTexture.create_from_image(image)
			_card_backdrop_cache[cache_key] = scenery
			return scenery
	var key := "fallback:" + pack_id
	if _card_backdrop_cache.has(key):
		return _card_backdrop_cache[key]
	var accent := pack_color(pack_id)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.055, 0.075, 0.11).lerp(accent, 0.48),
		Color(0.045, 0.06, 0.09).lerp(accent, 0.20),
		Color(0.025, 0.035, 0.055),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.42)
	texture.fill_to = Vector2(1.0, 1.0)
	_card_backdrop_cache[key] = texture
	return texture

static func card_art(card_name: String) -> Texture2D:
	var key := card_name.to_lower()
	if _card_art_cache.has(key):
		return _card_art_cache[key]
	var path := CARD_ART_DIR + "card_%s_illustration_v2.png" % key
	if not ResourceLoader.exists(path):
		path = CARD_ART_DIR + "card_%s_v1_460.png" % key
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_card_art_cache[key] = tex
	return tex


static func is_full_card_art(texture: Texture2D) -> bool:
	return texture != null and texture.get_height() > texture.get_width()


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
# ---------------------------------------------------------------------------
#  九宫格按钮（art/2d/ui · 资产包 v1 批次② · 渐进替换）
# ---------------------------------------------------------------------------
## 🔴 三条红线：
##   ① 资产缺失（headless 无 .import / 文件丢失）→ 整块降级回 StyleBoxFlat 旧路径，
##      **宁可无图不可炸 UI**（与 icon()/pack_emblem() 同一管法）；
##   ② hover/pressed 不另出图：同一贴图 + `modulate_color` 提亮/压暗 —— 保留「动态状态」
##      手感，资产包只出 5 变体 ×1 态（§5.1 悬停抬起由 _attach_motion 的 scale 承担）；
##   ③ ghost 变体全透明 → 保留 StyleBoxEmpty 语义，不套贴图（套了也是全透，白采样）。
const BTN_TEX_DIR := "res://art/2d/ui/"
const BTN_NINE_MARGIN := 24.0          # manifest.json：ui_btn_* 边距 24

static var _btn_tex_cache: Dictionary = {}

static func _btn_tex(variant: String) -> Texture2D:
	if variant == "ghost":
		return null                      # ghost 全透明，走 StyleBoxFlat 旧路径即可
	if _btn_tex_cache.has(variant):
		return _btn_tex_cache[variant]
	var path := BTN_TEX_DIR + "ui_btn_" + variant + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_btn_tex_cache[variant] = tex
	return tex


static func _btn_9slice(tex: Texture2D, modulate: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = BTN_NINE_MARGIN
	sb.texture_margin_top = BTN_NINE_MARGIN
	sb.texture_margin_right = BTN_NINE_MARGIN
	sb.texture_margin_bottom = BTN_NINE_MARGIN
	sb.modulate_color = modulate
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


static func button(b: Button, variant: String = "normal") -> void:
	if b == null:
		return
	var col := C_ALLY
	var font_col := C_TEXT
	var bg := Color(C_BG.r, C_BG.g, C_BG.b, 0.92)
	var radius := RADIUS
	# 🆕 2026-11-10 v4 收敛：本层按钮保持 v3「底色块染色」——primary 金块金字 /
	#    normal 青块白字 / danger 红块红字 / unavail 暗块灰字 / ghost 下划线。
	#    「仅文字」按钮只在关卡内（battle_theme.button 覆写为透明）。
	match variant:
		"primary":
			col = C_GOLD
			font_col = C_GOLD
			bg = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.16)
		"ghost":
			col = Color(0, 0, 0, 0)
			bg = Color(0, 0, 0, 0)
			font_col = C_TEXT_DIM
		"danger":
			col = C_ALERT
			font_col = C_ALERT
			bg = Color(C_ALERT.r, C_ALERT.g, C_ALERT.b, 0.14)
		"unavail":
			col = Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.35)
			font_col = Color(C_TEXT_DIM.r, C_TEXT_DIM.g, C_TEXT_DIM.b, 0.85)
			bg = Color(C_BG.r, C_BG.g, C_BG.b, 0.55)
		"normal":
			col = C_ALLY
			bg = Color(C_ALLY.r, C_ALLY.g, C_ALLY.b, 0.12)

	var normal: StyleBox = _base(bg, col, 0, radius)
	_pad(normal, 12.0, 8.0)

	# 悬停：底色块提亮（沿 §5.1「悬停抬起」，位移由 _attach_motion 负责）
	var hover: StyleBox = _base(bg.lightened(0.06) if bg.a > 0.0 else Color(1, 1, 1, 0.06),
		col, 0, radius)
	_pad(hover, 12.0, 8.0)

	# 按下：微下沉（视觉上压暗，配合 scale 0.97）
	var pressed: StyleBox = _base(bg.darkened(0.18) if bg.a > 0.0 else Color(0, 0, 0, 0.12),
		col, 0, radius)
	_pad(pressed, 12.0, 8.0)

	var dis: StyleBox = _base(Color(C_BG.r, C_BG.g, C_BG.b, 0.55),
		Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.30), BORDER_W, radius)
	_pad(dis, 12.0, 8.0)

	# 🆕 ghost 四态改写为「下划线式次级入口」（理由见 _ghost_box 注释）。
	#    必须在九宫格替换**之前**，否则会被 StyleBoxTexture 覆盖（ghost 无贴图，实际不会，
	#    但保持顺序语义清晰）。
	if variant == "ghost":
		normal = _ghost_box(Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.62))
		hover = _ghost_box(Color(C_ALLY.r, C_ALLY.g, C_ALLY.b, 0.95))
		pressed = _ghost_box(Color(C_ALLY_DARK.r, C_ALLY_DARK.g, C_ALLY_DARK.b, 1.0))
		dis = _ghost_box(Color(C_STEEL.r, C_STEEL.g, C_STEEL.b, 0.22))

	# 🆕 2026-11-10 「少边框」：ui_btn_* 九宫格贴图自带烘焙描边 → 不再套用，
	#    四态全部走上面的色块 StyleBoxFlat（hover/pressed 用明度差保留动态手感）。
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
	var bf := font_medium()                      # §5.4：按钮文字 = Medium 字重
	if bf != null:
		b.add_theme_font_override("font", bf)
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
#  字体注册表（art-bible §5.4 · 单一来源，与调色板同一管法）
# ---------------------------------------------------------------------------
## 🆕 可读性调整（2026-11-08，用户反馈「文本有点看不清」）：全游戏字重整体抬档
##   · 正文 body：wght 400 → **500**（Medium）
##   · 按钮/小标题 medium：wght 500 → **700**（Bold）
##   · 等宽数字 num：JetBrains Mono 默认 400 → **700**（读数更实，等宽不变）
##   · 展示 display：wght 900 不动（已是最重档）
## 🔴 v0.2 缺口修复（2026-11-07）：字体**正式接入**，全工程不再依赖引擎 fallback 字体。
##   选型逐字对齐 art-bible §5.4，全部 SIL OFL 授权（商用安全）：
##   · 展示字体 = 思源黑体同源 Noto Sans SC 可变字体（`FontVariation` 按 wght 取字重）
##   · 正文字体 = 同上（wght 见上方「可读性调整」）
##   · 数字字体 = JetBrains Mono 可变字体 —— **等宽数字**（§5.2「数字必须等宽」；
##     积分滚动 / 血量读数 / 卡面价格不再抖动），等宽字形同时服务 §5.5 蓝图风
##   🔴 lazy load + 判空兜底：字体文件缺失时返回 null，调用方退回引擎默认 ——
##      宁可降级也不能让 preload 把整个 UI（含 headless 测试）炸掉。
const FONT_PATH_CJK := "res://assets/fonts/NotoSansSC.ttf"
const FONT_PATH_NUM := "res://assets/fonts/JetBrainsMono.ttf"

static var _font_cjk: Font = null
static var _font_num: Font = null
static var _cjk_variants: Dictionary = {}      # wght -> FontVariation（缓存，避免每帧 new）
static var _num_variation: FontVariation = null

## 🔴 OpenType tag 整数：`variation_opentype` 的键**必须是 tag 整数**（String 键如
##    "wght" 会被 Godot 静默忽略、字重永远落在默认 400 —— 2026-11-08 实机墨量探针实测）。
##    "wght" = 0x77676874 = 2003265652（与 TextServer.name_to_tag("wght") 一致）。
const OT_TAG_WGHT := 2003265652

static func _cjk_font() -> Font:
	if _font_cjk == null:
		_font_cjk = load(FONT_PATH_CJK)
	return _font_cjk


static func _num_font() -> Font:
	if _font_num == null:
		_font_num = load(FONT_PATH_NUM)
	return _font_num


## 正文字体（wght 500 —— 2026-11-08 可读性调整，原 400）。
static func font_body() -> Font:
	return _cjk_variant(500)


## 强调正文字体（wght 700 —— 2026-11-08 可读性调整，原 500；按钮 / 小标题）。
static func font_medium() -> Font:
	return _cjk_variant(700)


## 展示字体（wght 900，Black）—— 波次横幅 / 大标题 / L0 波次号。
static func font_display() -> Font:
	return _cjk_variant(900)


## 等宽数字字体（JetBrains Mono wght 700）—— 只用于**纯数字**读数。
##   🔴 中文不得走本字体（JBM 无 CJK 字形，会退到系统 fallback 造成混排不齐）。
static func font_num() -> Font:
	if _num_font() == null:
		return null
	if _num_variation == null:
		_num_variation = FontVariation.new()
		_num_variation.base_font = _font_num
		_num_variation.variation_opentype = {OT_TAG_WGHT: 700}   # 🔴 同上：整数 tag 键
	return _num_variation


static func _cjk_variant(wght: int) -> Font:
	if _cjk_font() == null:
		return null
	if not _cjk_variants.has(wght):
		var fv := FontVariation.new()
		fv.base_font = _font_cjk
		fv.variation_opentype = {OT_TAG_WGHT: wght}   # 🔴 整数 tag 键（String 键会被忽略）
		_cjk_variants[wght] = fv
	return _cjk_variants[wght]


## 给 Label 套注册表字体（`variant`: body / medium / display / num）。
##   字体缺失（文件被删 / 导入失败）时静默跳过 —— 引擎默认字体兜底。
static func apply_font(l: Label, variant: String = "body") -> void:
	if l == null:
		return
	var f: Font = null
	match variant:
		"medium": f = font_medium()
		"display": f = font_display()
		"num": f = font_num()
		_: f = font_body()
	if f != null:
		l.add_theme_font_override("font", f)


# ---------------------------------------------------------------------------
#  Label 便捷设置（统一字号下限，§9.1 P0）
# ---------------------------------------------------------------------------
## 建 Label 并立刻套字体 / 字号 / 颜色。`size` 低于 FONT_MIN 时**强制抬到 FONT_MIN**
##   —— 玩家可见文本不得低于 16px（art-bible §9.1 P0）。
static func label(text: String, size: int = FONT_MIN, col: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	apply_font(l, "body")
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


# ---------------------------------------------------------------------------
#  四角刻线 chrome（§5.5 蓝图语言 · 通用装饰，商店卡面同款推广）
# ---------------------------------------------------------------------------
## 在 host 的**外沿四角**画 L 形刻线（工程图角标）。accent 色存在 host meta
##   "chrome_accent"（默认钢灰），运行时改色走 `set_chrome_accent()`（内部重画）。
##   🔴 纯装饰层：不参与布局、不挡输入（在 host 自身绘制，位于子控件之下 ——
##      刻线只占描边留白区，不会压住内容）。
static func attach_corner_chrome(host: Control, leg: float = 10.0, thick: float = 2.0) -> void:
	if host == null or host.has_meta("chrome_accent"):
		return                                   # 防重复挂载
	host.set_meta("chrome_accent", C_STEEL)
	host.draw.connect(func() -> void:
		var col: Color = host.get_meta("chrome_accent", C_STEEL)
		var r := host.size
		# 左上
		host.draw_line(Vector2(1.0, 1.0), Vector2(leg, 1.0), col, thick)
		host.draw_line(Vector2(1.0, 1.0), Vector2(1.0, leg), col, thick)
		# 右上
		host.draw_line(Vector2(r.x - leg, 1.0), Vector2(r.x - 1.0, 1.0), col, thick)
		host.draw_line(Vector2(r.x - 1.0, 1.0), Vector2(r.x - 1.0, leg), col, thick)
		# 左下
		host.draw_line(Vector2(1.0, r.y - leg), Vector2(1.0, r.y - 1.0), col, thick)
		host.draw_line(Vector2(1.0, r.y - 1.0), Vector2(leg, r.y - 1.0), col, thick)
		# 右下
		host.draw_line(Vector2(r.x - leg, r.y - 1.0), Vector2(r.x - 1.0, r.y - 1.0), col, thick)
		host.draw_line(Vector2(r.x - 1.0, r.y - leg), Vector2(r.x - 1.0, r.y - 1.0), col, thick)
	)


## 运行时切换 chrome accent（如结算面板：胜利辉金 / 失败警报红）。
static func set_chrome_accent(host: Control, col: Color) -> void:
	if host == null or not host.has_meta("chrome_accent"):
		return
	host.set_meta("chrome_accent", col)
	host.queue_redraw()


# ---------------------------------------------------------------------------
# 🆕 三态鼠标光标（asset-pack-v4-result.md §3.2 · 2026-11-08）
# ---------------------------------------------------------------------------
## default = 蓝图箭头（全局）；place = 放置准星（拖卡中）；deny = 禁止（落点非法）。
##   🔴 判空降级：贴图缺失 → 不动光标（保持系统箭头），headless 安全。
const CURSOR_PATHS := {
	"default": "res://art/2d/ui/ui_cursor_default_v1.png",
	"place": "res://art/2d/ui/ui_cursor_place_v1.png",
	"deny": "res://art/2d/ui/ui_cursor_deny_v1.png",
}
const CURSOR_HOTSPOTS := {
	"default": Vector2(4.0, 2.0),
	"place": Vector2(24.0, 24.0),
	"deny": Vector2(24.0, 24.0),
}
static var _cursor_cache: Dictionary = {}    # mode -> Texture2D|null（判空缓存）


## 切换自定义光标。mode 之外传 "system" 恢复系统箭头。
static func set_cursor(mode: String) -> void:
	var path: String = String(CURSOR_PATHS.get(mode, ""))
	if path == "":
		return
	var tex: Texture2D = _cursor_cache.get(mode)
	if tex == null and not _cursor_cache.has(mode):
		tex = load(path) if ResourceLoader.exists(path) else null
		_cursor_cache[mode] = tex
	if tex == null:
		return                                 # 资产缺失 → 保持系统箭头
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, CURSOR_HOTSPOTS.get(mode))


# ---------------------------------------------------------------------------
# 🆕 卡包主题色（asset-pack-v5-lib · 2026-11-08）：8 包 modulate 染色表
# ---------------------------------------------------------------------------
## 🔴 全部 art-bible §2.2 表内色；未知 id 兜底钢灰。仅用于染白烘焙件
##    （ui_lib_head_bar 等）—— modulate 是乘法，深底件会被染黑。
const PACK_COLORS := {
	"core": Color(0.604, 0.647, 0.694),    # 钢灰 #9AA5B1（泛用 = 中性）
	"cinder": Color(1.0, 0.42, 0.239),     # 熔橙 #FF6B3D
	"rime": Color(0.243, 0.816, 0.910),    # 耀青 #3ED0E8
	"pierce": Color(1.0, 0.788, 0.29),     # 辉金 #FFC94A
	"arc": Color(0.478, 0.361, 1.0),       # 星紫 #7A5CFF
	"sunder": Color(0.91, 0.263, 0.498),   # 噬品红 #E8437F
	"hex": Color(0.102, 0.42, 0.49),       # 深青 #1A6B7D
	"true": Color(1.0, 0.18, 0.306),       # 警报红 #FF2E4E（湮灭 = 终极危险）
}


static func pack_color(pack_id: String) -> Color:
	return PACK_COLORS.get(pack_id, C_STEEL)


## 图鉴分组底板 / 标题条（asset-pack-v5-lib）：判空降级同 icon() 管法。
const LIB_BLOCK_PATH := "res://art/2d/ui/ui_lib_block_v1.png"
const LIB_HEAD_BAR_PATH := "res://art/2d/ui/ui_lib_head_bar_v1.png"
static var _lib_tex_cache: Dictionary = {}


static func lib_tex(kind: String) -> Texture2D:
	var path: String = LIB_BLOCK_PATH if kind == "block" else LIB_HEAD_BAR_PATH
	if _lib_tex_cache.has(path):
		return _lib_tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_lib_tex_cache[path] = tex
	return tex


## 商店商品位承托板（asset-pack-v6）：判空降级同 lib_tex() 管法。
##   🔴 中性不染色 —— 稀有度边框 / 可购性 accent 由 card_blueprint() + chrome 承担。
const SLOT_PLATE_PATH := "res://art/2d/ui/ui_shop_slot_plate_v1.png"
static var _slot_plate_checked := false
static var _slot_plate_cache: Texture2D = null


static func slot_plate_tex() -> Texture2D:
	if _slot_plate_checked:
		return _slot_plate_cache
	_slot_plate_checked = true
	if ResourceLoader.exists(SLOT_PLATE_PATH):
		_slot_plate_cache = load(SLOT_PLATE_PATH)
	return _slot_plate_cache
