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

const C_BG := Color(0.078, 0.090, 0.149, 0.92)      # #141726 @92%
const C_BORDER := Color(0.243, 0.816, 0.910)        # #3ED0E8 描边（§5.1）
const C_FILL := Color(0.243, 0.816, 0.910)          # #3ED0E8 段填充
const C_FILL_LOW := Color(1.000, 0.180, 0.306)      # #FF2E4E ≤25% 告警
const C_TEXT := Color(0.784, 0.812, 0.855)          # #C8CFDA 数字（对比度 ≥4.5:1）

const SEG_COUNT := 20          # 20 段
const SEG_W := 28.0
const SEG_H := 22.0
const SEG_GAP := 3.0
const BOTTOM_MARGIN := 28.0
const PAD := 10.0

var _director: Node = null
var _controller: Node = null   # 读 runtime.player.core_hp（单一数据源）
var _hp: float = 1000.0
var _hp_max: float = 1000.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_tree() != null:
		get_tree().root.size_changed.connect(_refresh_size)


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
func set_hp(hp: float, hp_max: float) -> void:
	_hp = float(hp)
	_hp_max = maxf(1.0, float(hp_max))
	queue_redraw()


## 🟢 从 runtime.player 读核心 HP 单一数据源实时刷新（只读）。
func _refresh_hp() -> void:
	if _controller == null or _controller.runtime == null:
		return
	var p = _controller.runtime.player
	if p == null:
		return
	set_hp(float(p.core_hp), float(p.core_hp_max))


func _process(_delta: float) -> void:
	# 只读刷新（低开销；HP 变化也会经 run_changed 触发 set_hp）。
	_refresh_hp()


func _draw() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vs := vp.get_visible_rect().size
	var total_w := float(SEG_COUNT) * SEG_W + float(SEG_COUNT - 1) * SEG_GAP
	var x0 := (float(vs.x) - total_w) * 0.5
	var y0 := float(vs.y) - BOTTOM_MARGIN - SEG_H

	# 底槽（深色 + 亮色描边，§5.1）
	var slot := Rect2(x0 - PAD, y0 - PAD, total_w + 2.0 * PAD, SEG_H + 2.0 * PAD)
	draw_rect(slot, C_BG)
	draw_rect(slot, C_BORDER, false, 3.0, true)

	# 分段
	var frac := clampf(_hp / maxf(1.0, _hp_max), 0.0, 1.0)
	var filled := int(ceil(frac * float(SEG_COUNT)))
	var col := C_FILL_LOW if frac <= 0.25 else C_FILL
	for i in SEG_COUNT:
		var r := Rect2(x0 + float(i) * (SEG_W + SEG_GAP), y0, SEG_W, SEG_H)
		if i < filled:
			draw_rect(r, col)
		else:
			draw_rect(r, Color(col.r, col.g, col.b, 0.16))

	# 数字（L0）：720 / 1000
	var font := ThemeDB.fallback_font
	if font != null:
		var txt := "%d / %d" % [int(round(_hp)), int(round(_hp_max))]
		var fs := 30
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((float(vs.x) - tw) * 0.5, y0 - 14.0),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)
