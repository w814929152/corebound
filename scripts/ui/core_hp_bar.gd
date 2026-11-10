extends Control
##
## 🔴 穿透式核心 HP 条 —— 底部中央 **20 段 × 50 点** 分段血条（CanvasLayer **130**）
##
## P1 重做（spec `docs/phase3/ux-p0p1-spec.md` §B.1a/§B.3）：
##   · 位置：**屏幕底部中央**（spec §5.3 明定；原顶部右伸已迁走）。
##   · 形态：20 段分段血条（段高 22 · 段宽 28 · 间距 3 → 总宽 616）。
##   · 口径裁决（spec §B.1a / §D-4）：核心 HP=1000、漏怪伤害=50 →
##     **每段 = 50 点 × 20 段 → 每碎一段 = 漏一只怪**，20 段见底 = 失败。因果直连、可读性最强。
##   · 数据源：**只读** `runtime.player.core_hp`（单一数据源）。
##
## 🔴 保留 **CanvasLayer 130**（唯一穿透 UI，横跨抽屉上方，GDD §10.1 断言 12 仍可验）。
## 🔴 零玩法耦合：只读快照，不写任何状态、不发玩法信号（control-manifest §5）。
##

const _Layout := preload("res://scripts/ui/shop_layout.gd")

const C_BG := Color(0.078, 0.090, 0.149, 0.92)      # #141726 @92%
const C_BORDER := Color(0.243, 0.816, 0.910)        # #3ED0E8 描边（§5.1）
const C_FILL := Color(0.243, 0.816, 0.910)          # #3ED0E8 段填充
const C_FILL_LOW := Color(1.000, 0.180, 0.306)      # #FF2E4E ≤25% 告警
const C_TEXT := Color(0.784, 0.812, 0.855)          # #C8CFDA 数字（对比度 ≥4.5:1）

const SEG_COUNT := 20          # 20 段
const SEG_W := 10.0
const SEG_H := 10.0
const SEG_GAP := 3.0           # 🆕 3 → 4：1600×900 缩放下 2.5px 的缝几乎看不出"分段"
const BOTTOM_MARGIN := 26.0    # 🆕 28 → 46：原设计贴屏幕底边（1080p 下仅 18px），显得"被裁掉"
const PAD := 10.0
const SEG_RADIUS := 3          # 🆕 段圆角（直角方块在暗底上过于生硬）
const CORE_CAP := "核心"       # 🆕 血条左侧说明（原来只有一串裸数字，读不出是什么）
# P1 增强（spec §C.2）：段碎裂演出时长（满→空时短促闪红再隐没）。
# 🆕 2026-11-10 设计稿 v1 对齐：闪色由白改**警报红**（受击因果更直读）、时长 0.18 → 0.30。
const SHATTER_SEC := 0.30

const _Battle := preload("res://scripts/ui/battle_theme.gd")
var _box_health: StyleBoxFlat

const _Style := preload("res://scripts/ui/ui_style.gd")

var _director: Node = null
var _controller: Node = null   # 读 runtime.player.core_hp（单一数据源）
var _hp: float = 1000.0
var _hp_max: float = 1000.0
## 🔴 P1 增强本地状态（纯演出）：段索引 → 剩余碎裂动画秒数；`_prev_filled` = 上一帧满段数。
##   只驱动画面衰减，不回写数据源、不参与任何判定（与 monster_layer 的 `_revive_flash` 同性质）。
var _prev_filled: int = -1
var _shatter: Dictionary = {}
## 🆕 缓存 StyleBox（`_draw` 每帧跑，不得在绘制里 new）
var _box_slot: StyleBox
var _box_seg: StyleBoxFlat
var _box_seg_low: StyleBoxFlat
var _box_seg_empty: StyleBoxFlat


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_boxes()
	_box_health = _Battle.panel(_Style.C_ALLY, 0.0)
	if get_tree() != null:
		get_tree().root.size_changed.connect(_refresh_size)


func _build_boxes() -> void:
	# 底槽：深色底 + 亮色描边 + 圆角（§5.1「面板 = 深底 + 亮描边」）
	_box_slot = _Style.panel(Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.75), 2, 0.0, 0.0)
	# 🆕 v4 统一关卡内风格：底槽承托块取消（透明），段位本身即数据编码
	_box_slot.bg_color = Color(C_BG.r, C_BG.g, C_BG.b, 0.0)
	_box_slot.set_corner_radius_all(SEG_RADIUS + 4)
	_box_seg = _seg_box(C_FILL)
	_box_seg_low = _seg_box(C_FILL_LOW)
	_box_seg_empty = _seg_box(Color(C_FILL.r, C_FILL.g, C_FILL.b, 0.16))


func _seg_box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(SEG_RADIUS)
	return sb


func _refresh_size() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func bind_director(d: Node) -> void:
	_director = d


## 🟢 注入 controller，读 runtime.player.core_hp 实时刷新（只读）。
func bind_controller(c: Node) -> void:
	_controller = c
	if c == null:
		return
	if not c.is_connected("run_changed", _on_run_changed):
		c.run_changed.connect(_on_run_changed)
	call_deferred("_on_run_changed")


func _on_run_changed() -> void:
	_refresh_hp()


## [接口] 直接设定（兼容后续 wave-spawner 的 WS-5 调用）。
## 🟢 P1 增强：段数下降 → 逐段登记碎裂演出（本地计时器，只驱动画面）。
func set_hp(hp: float, hp_max: float) -> void:
	var prev_filled := _filled_count()
	_hp = float(hp)
	_hp_max = maxf(1.0, float(hp_max))
	var now_filled := _filled_count()
	if _prev_filled >= 0 and now_filled < _prev_filled:
		for i in range(now_filled, _prev_filled):
			_shatter[i] = SHATTER_SEC
	_prev_filled = now_filled
	queue_redraw()


## 当前满段数（口径与 `_draw()` 逐位一致：ceil(frac × 20)）。
func _filled_count() -> int:
	var frac := clampf(_hp / maxf(1.0, _hp_max), 0.0, 1.0)
	return int(ceil(frac * float(SEG_COUNT)))


## 从 runtime.player 读核心 HP 单一数据源实时刷新（只读）。
func _refresh_hp() -> void:
	if _controller == null or _controller.runtime == null:
		return
	var p = _controller.runtime.player
	if p == null:
		return
	set_hp(float(p.core_hp), float(p.core_hp_max))


func _process(delta: float) -> void:
	# 只读刷新（低开销；HP 变化也会经 run_changed 触发 set_hp）。
	_refresh_hp()
	# P1 增强：碎裂演出衰减（纯画面计时器）。
	if not _shatter.is_empty():
		for i in _shatter.keys():
			var v := float(_shatter[i]) - float(delta)
			if v <= 0.0:
				_shatter.erase(i)
			else:
				_shatter[i] = v


## HUD 仪表层贴图缓存（判空降级：缺失时退回 StyleBoxFlat / draw_rect 旧路径）。
var _tex_cache := {}


func _ht(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := "res://art/2d/ui/" + name
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[name] = t
	return t


func _draw() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	var total_w := float(SEG_COUNT) * SEG_W + float(SEG_COUNT - 1) * SEG_GAP
	var x0 := 40.0
	var y0 := 168.0

	draw_style_box(_box_health, Rect2(x0 - 16.0, y0 - 52.0, total_w + 32.0, 80.0))
	# 底槽（深色 + 亮色描边 + 圆角，§5.1）
	#   🆕 段贴图生效时**让位**：每个段自带槽/填充的轮廓，再套一层整块底座会读成
	#      "双层盒子"（实机截图确认）。贴图缺失时仍走旧底座，画面与改前一致。
	var t_seg_any: Texture2D = null
	var slot := Rect2(x0 - PAD, y0 - PAD, total_w + 2.0 * PAD, SEG_H + 2.0 * PAD)
	if _box_slot != null and t_seg_any == null:
		draw_style_box(_box_slot, slot)

	# 分段
	var frac := clampf(_hp / maxf(1.0, _hp_max), 0.0, 1.0)
	var filled := int(ceil(frac * float(SEG_COUNT)))
	var seg_box := _box_seg_low if frac <= 0.25 else _box_seg
	# 🆕 仪表段贴图（28x22 与 SEG_W/SEG_H 逐像素对齐，缺失时各段自动走旧路径）
	var t_seg: Texture2D = null
	for i in SEG_COUNT:
		var r := Rect2(x0 + float(i) * (SEG_W + SEG_GAP), y0, SEG_W, SEG_H)
		if i < filled:
			if t_seg != null:
				draw_texture(t_seg, r.position)
			elif seg_box != null:
				draw_style_box(seg_box, r)
			else:
				draw_rect(r, C_FILL_LOW if frac <= 0.25 else C_FILL)
		elif t_seg_any != null:
			draw_texture(t_seg_any, r.position)
		elif _box_seg_empty != null:
			draw_style_box(_box_seg_empty, r)
		else:
			draw_rect(r, Color(C_FILL.r, C_FILL.g, C_FILL.b, 0.16))

	# P1 增强：段碎裂演出 —— 由满→空的段短促闪**警报红**（#FF2E4E）再隐没（不参与玩法）。
	#   🆕 2026-11-10 设计稿 v1：白 → 警报红，与 ≤25% 告警同色（危险语义一致）。
	for i in _shatter:
		if i < 0 or i >= SEG_COUNT:
			continue
		var sp := clampf(float(_shatter[i]) / SHATTER_SEC, 0.0, 1.0)
		var grow := (1.0 - sp) * SEG_GAP * 1.5
		var sr := Rect2(x0 + float(i) * (SEG_W + SEG_GAP), y0, SEG_W, SEG_H)
		var gr := Rect2(sr.position.x - grow, sr.position.y - grow,
			sr.size.x + 2.0 * grow, sr.size.y + 2.0 * grow)
		# 闪红用直角矩形（碎裂瞬间），避免每帧 duplicate StyleBox 产生分配
		draw_rect(gr, Color(C_FILL_LOW.r, C_FILL_LOW.g, C_FILL_LOW.b, 0.90 * sp))

	# 数字（L0）：720 / 1000 —— 🆕 字号 30 → 22，抬到血条上方留白区，不再压住条顶
	#   🔴 §5.4：血量读数 = 等宽数字字体（受击抖动时不再左右跳）；「核心」= Medium
	var font := _Style.font_num()
	var font_cjk := _Style.font_medium()
	if font != null:
		var txt := "%d / %d" % [int(round(_hp)), int(round(_hp_max))]
		var fs := 18
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(x0 + total_w - tw, y0 - 16.0),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)
		# 🆕 左侧说明「核心」：右对齐贴在底槽左沿外，垂直居中于条
		if font_cjk != null:
			var cw: float = font_cjk.get_string_size(CORE_CAP, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font_cjk, Vector2(x0, y0 - 16.0),
				CORE_CAP, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)
