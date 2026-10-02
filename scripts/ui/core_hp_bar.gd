extends Control
##
## 🔴 穿透式核心 HP 条 —— CanvasLayer **130**（GDD §2.4 分层表 / 交接点 3）
##
## 这是**唯一豁免遮挡规则的 UI 元素**：层号 130 > 商店层 100，
## 所以抽屉展开时它**横跨整屏、压在抽屉之上**——骨架阶段故意让它盖住抽屉右上角，
## 于是"穿透绘制"这件事在截图里一眼可验（GDD §10.1 断言 12）。
##
## 后续切片：接 `wave-spawner` 的 `core_hp_changed(hp, max_hp)`（契约 WS-5）。
##

const C_BG := Color(0.04, 0.05, 0.07, 0.92)
const C_FILL := Color(0.24, 0.78, 0.83, 1.0)
const C_FILL_LOW := Color(0.86, 0.20, 0.20, 1.0)   # 🟢 切片8续3：核心 HP ≤ 25% 告警红
const C_TEXT := Color(1.0, 1.0, 1.0, 1.0)

const HP_MAX := 1000.0     # core-defense GDD v0.5：核心 HP 1000
const HP_NOW := 720.0      # 骨架占位初值（接线后由 runtime 单一数据源覆盖）


var _fill: ColorRect
var _label: Label
var _director: Node = null
var _controller: Node = null   # 🟢 切片8续3：读 runtime.player.core_hp（单一数据源）


func _ready() -> void:
	_build()
	if get_tree() != null:
		get_tree().root.size_changed.connect(_refresh_size)


func bind_director(d: Node) -> void:
	_director = d


## 🟢 切片8续3（可玩 MVP）：注入 controller，读 runtime.player.core_hp 实时刷新。
func bind_controller(c: Node) -> void:
	_controller = c
	if c == null:
		return
	if not c.is_connected("run_changed", _on_run_changed):
		c.run_changed.connect(_on_run_changed)
	call_deferred("_on_run_changed")


func _on_run_changed() -> void:
	_refresh_hp()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.set_offset(SIDE_TOP, 8.0)
	bg.set_offset(SIDE_BOTTOM, 46.0)
	bg.set_offset(SIDE_LEFT, 320.0)
	bg.set_offset(SIDE_RIGHT, -24.0)   # 🔴 故意伸到抽屉区域上方
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_fill = ColorRect.new()
	_fill.color = C_FILL
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fill.anchor_right = HP_NOW / HP_MAX
	bg.add_child(_fill)

	_label = Label.new()
	_label.text = "核心 HP %d / %d（骨架占位 · 穿透层 130）" % [int(HP_NOW), int(HP_MAX)]
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", C_TEXT)
	bg.add_child(_label)


func _refresh_size() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_hp(hp: float, hp_max: float) -> void:
	# [接口] 后续 `wave-spawner` 的 WS-5 直接调这里（骨架占位用；接线后走 _refresh_hp）
	var r: float = clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
	_fill.anchor_right = r
	_label.text = "核心 HP %d / %d（穿透层 130）" % [int(hp), int(hp_max)]


## 🟢 切片8续3（可玩 MVP）：从 runtime.player 读核心 HP 单一数据源实时刷新。
func _refresh_hp() -> void:
	if _controller == null or _controller.runtime == null:
		return
	var p = _controller.runtime.player
	if p == null:
		return
	var hp: float = float(p.core_hp)
	var hp_max: float = float(p.core_hp_max)
	set_hp(hp, hp_max)
	# 低血量告警红（≤ 25%）
	var r: float = clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)
	_fill.color = C_FILL_LOW if r <= 0.25 else C_FILL
