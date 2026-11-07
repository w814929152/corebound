extends Node2D
##
## 塔等级牌（world 层 · **只读**渲染）
##
## 使命：把「这座塔几级」从**纯形态暗示**（`monster_layer._draw_tower_form` 的 h≥2/3/5/8
##   四档装饰）升级为**一眼可读的数字**。动机是一条已记录的可读性缺口：
##     · 形态只在 2/3/5/8 四个阈值跳变 → **h=9 和 h=99 画面完全一样**（满级形态封顶）；
##     · 形态是**冗余通道**（环/护角/星点），新玩家无法反解"这是几级"，只能感觉"更强"；
##     · 商店 H5 提示已经用文字写 `Lv 3 → 4`，但**战场上没有对应读数** → 买卡前后无法自证。
##
## 🔴 为什么**单开一层**而不是写进 `monster_layer.gd`：
##   1. `monster_layer.gd` 有一条已钉死的红线 **AC-T1-24「零文本」**
##      （`tests/run_ui_style_asserts.gd` + `test_suite_t1_aggro.gd` 都源码级断言
##      该文件**不含 `draw_string(` / 不含 `Label`**，用于守 T-E1③「零择时读数」）。
##      等级是**静态事实**（不随时间变化），不是择时读数 —— 但断言是文件级的，
##      所以**换一个文件**承载文本，比放宽红线安全得多。
##   2. 分层纪律：`monster_layer` 负责战场**形状**，本层负责战场**读数**，
##      与 `vfx_layer`（屏幕空间伤害数字）同族 —— 都是"只读快照 + 纯绘制"的叠加层。
##
## 🔴 只读纪律（control-manifest §5）：只读 `runtime.snapshot()` + `geo.slots`，
##   不写玩法状态、**不发**任何信号。订阅玩法信号是**单向**的（只为"该重绘了"这件事）：
##     · `ShopController.shop_changed / run_changed`（买卡/拆塔/换波 → 等级或归属变了）
##     · `TimeDirector.state_changed`（抽屉开合 → 战场变窄重新居中 → 全部塔位位移）
##   🔴 为什么信号是必需的、不能只靠 `_process` 轮询：安全窗里 `get_tree().paused`
##      会停掉本节点（PAUSABLE）的 `_process`，但信号回调照常触发 —— 抽屉正是在
##      暂停态里开合的。
##
## 🔴 数据源 = `snapshot().slots[]`（`{slot, ctype, h, empty, disabled}`）——
##   与 `monster_layer` 画塔用的是同一份，**零新增 snapshot 字段**。
##
## 坐标：复用 `MonsterLayer` 的世界→屏幕变换（`world_to_screen` / `world_scale`）。
##   🔴 不自己复写一份 `_xform`：抽屉展开会改可视宽 → 战场重新居中，
##      两份换算一旦漂移，等级牌就会和塔身错位（本项目已经踩过"手抄第二份网格数字"的坑）。
##

## 字号（相对 `sc` 的系数 + 上下限）。🔴 下限 14：本项目基准屏（1920×1080）下
##   sc ≈ 8.5px/u → 1.75×sc ≈ 15px；再小一档（12px）在 1600×900 窗口里会被压到
##   ≈10 物理 px，和最小档伤害数字（20px）差距过大、基本糊成一团（截帧实测）。
const FS_K := 1.75
const FS_MIN := 14
const FS_MAX := 17
## 文本与牌面的内边距（px，屏幕空间）。
const PAD_X := 5.0
const PAD_Y := 3.0
## 等级色阶（与形态语言对齐：h≥5 星紫点缀 / h≥8 星紫外环 → 这里用同色做"高等级"提示）。
##   🔴 色相只是**冗余通道**，数字本身才是主通道（色觉可访问，art-bible §9.2①）。
const C_TIER_LOW := Color(0.243, 0.816, 0.910)     # #3ED0E8 耀青（我方主体色）
const C_TIER_MID := Color(1.000, 0.788, 0.290)     # #FFC94A 辉金（h≥5）
const C_TIER_HIGH := Color(0.478, 0.361, 1.000)    # #7A5CFF 星紫（h≥8 = 形态满级）
const C_CHIP_BG := Color(0.063, 0.078, 0.137, 0.90)  # 深底（保证亮塔身 / 怪身上都可读）
const C_TEXT := Color(0.925, 0.980, 1.000, 0.96)     # #EAFBFF 近白（与核心内芯同族）
const C_DISABLED := Color(0.55, 0.57, 0.62, 0.60)    # 停机塔：整牌压暗（与塔身压暗同义）

## 轮询周期（s）。🔴 15Hz：等级只在买卡/拆塔/复活时变，没必要逐帧重排文字。
##   成本口径：一次 `snapshot()` ≈ `MonsterLayer._draw_radial_towers()` **每帧**已经在调的那次
##   → 15Hz 只是它的 1/4，可忽略（见 `docs/phase6/performance-profile.md` 的渲染占比）。
const POLL_SEC := 1.0 / 15.0

var controller: Node = null
## 世界层（`MonsterLayer`）—— 仅借用其 `world_to_screen` / `world_scale` 两个纯函数。
var world_layer: Node = null

var _poll: float = 0.0
## 上次绘制的条目签名（`slot:h:x:y` 串）—— 变了才 `queue_redraw()`。
var _sig: String = ""
## 已就绪的绘制条目（世界→屏幕坐标已在重建时算好）。
var _entries: Array = []


func bind_controller(c: Node) -> void:
	controller = c
	if c != null:
		# 🔴 必须走**信号**而不是只靠 `_process` 轮询：安全窗（`get_tree().paused`）里
		#    本节点是 PAUSABLE → `_process` 不跑，但信号回调照常触发。
		#    真实故障复现：抽屉展开 → 战场变窄重新居中 → 只靠轮询的旧实现把等级牌
		#    留在"抽屉还没开"的旧坐标上（截图里牌飘到塔右侧 500px 外）。
		for sig in ["shop_changed", "run_changed"]:
			if c.has_signal(sig) and not c.is_connected(sig, _on_refresh):
				c.connect(sig, _on_refresh)
	_rebuild()


func bind_world_layer(ml: Node) -> void:
	world_layer = ml
	_rebuild()


func bind_time_director(td: Node) -> void:
	if td == null:
		return
	# 抽屉开合会改战场可视宽（`MonsterLayer._field_width`）→ 全部塔位重新居中 → 必须重排。
	if td.has_signal("state_changed") and not td.is_connected("state_changed", _on_state_changed):
		td.state_changed.connect(_on_state_changed)
	_rebuild()


func _on_state_changed(_from: int, _to: int) -> void:
	_rebuild()


func _on_refresh() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if controller == null or world_layer == null:
		return
	_poll += clampf(float(delta), 0.0, 0.1)
	if _poll < POLL_SEC:
		return
	_poll = 0.0
	_rebuild()


## 重建绘制条目：读快照 → 算屏幕坐标 → 比对签名 → 变化才重绘。
##
## `silent = true`：只刷新内部条目，**不**发 `queue_redraw()` —— 供 `_draw()` 开头调用，
##   保证"画出来的坐标一定是**此刻**的变换"（信号漏接收时的兜底）。
func _rebuild(silent: bool = false) -> void:
	var fresh: Array = []
	if controller != null and controller.runtime != null and world_layer != null:
		var rt = controller.runtime
		var slots: Array = rt.geo.slots if rt.geo != null else []
		var snap: Dictionary = rt.snapshot()
		var core_slot: int = int(snap.get("core_tower_slot", -1))
		for tw in snap.get("slots", []):
			if bool(tw.get("empty", true)):
				continue
			var slot: int = int(tw.get("slot", -1))
			if slot < 0 or slot >= slots.size():
				continue
			var sp: Vector2 = world_layer.world_to_screen(slots[slot])
			fresh.append({
				"slot": slot,
				"h": int(tw.get("h", 1)),
				"pos": sp,
				"core": slot == core_slot,
				"disabled": bool(tw.get("disabled", false)),
			})
	var parts: PackedStringArray = []
	for e in fresh:
		parts.append("%d:%d:%d:%d:%s" % [
			int(e["slot"]), int(e["h"]), int(e["pos"].x), int(e["pos"].y),
			"1" if bool(e["disabled"]) else "0"])
	var s := "|".join(parts)
	if s == _sig:
		return
	_sig = s
	_entries = fresh
	if not silent:
		queue_redraw()


func _draw() -> void:
	# 🔴 先按**当前**变换重算一遍：`_draw` 可能由别的信号/重绘触发，
	#    而上一帧缓存的屏幕坐标可能属于"抽屉还没开"的旧战场宽度。
	_rebuild(true)
	if _entries.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var sc: float = world_layer.world_scale()
	var fs := clampi(int(round(FS_K * sc)), FS_MIN, FS_MAX)
	var R := 1.70 * sc                      # 与 `monster_layer.U_TOWER` 同口径（塔外接圆）
	for e in _entries:
		_draw_badge(font, e, R, fs)


## 单个等级牌（胶囊底 + 等级读数）。
##
## 排版：`Lv` 小号（0.62×，染等级色）+ 数字大号（近白）—— 两段共用一条基线。
##   🔴 为什么不是整串同字号：`Lv 120` 同字号在本项目基准屏（sc≈8.5px/u）下宽 ≈ 55px，
##      比塔身直径（≈29px）宽近一倍 → 密集摆塔时整块压在邻居塔上。拆成大小两段后
##      宽度 ≈ 34px，且"这是等级"这件事仍然一眼可读（`Lv` 就是标签）。
##
## 摆位：**塔身右上角外侧**（对角方向）。为什么不放正上方：
##   决策期 `_draw_exposure_icons` 正在占用"塔正上方"（⚔/🛡 徽标，y ≈ −R−5），
##   而"正上方"也是 ⑤ 态放置悬停徽标的位置 —— 三样东西抢同一块地。
##   对角外侧在**所有状态**下都空着（复活充能点在正下方、受击闪/橙环都是环绕塔身的，不外扩）。
func _draw_badge(font: Font, e: Dictionary, R: float, fs: int) -> void:
	var c: Vector2 = e["pos"]
	var h: int = int(e["h"])
	var lbl := "Lv"
	var num := str(h)
	var sub := maxi(9, int(round(float(fs) * 0.70)))
	var w_lbl := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, sub).x
	var w_num := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var gap := 1.0
	var cw := PAD_X * 2.0 + w_lbl + gap + w_num
	var ch := float(fs) + PAD_Y * 2.0
	# 底边左上角锚点：贴八边形"右上斜边"外侧（对角外 1.5px），向右上展开。
	#   🔴 用对角距离而不是"top-justify"：八边形本体在 −0.62R 处仍有 ≈0.79R 的半宽，
	#      只上移不右移会把牌压在塔身斜边上（实测截图里就是"牌贴着塔角"）。
	var ax := c.x + 0.72 * R + 1.5
	var ay := c.y - 0.72 * R - 1.5
	var rect := Rect2(ax, ay - ch, cw, ch)

	var dim := bool(e["disabled"])
	var accent := C_TIER_LOW
	if h >= 8:
		accent = C_TIER_HIGH
	elif h >= 5:
		accent = C_TIER_MID
	var bg := C_CHIP_BG
	var col := C_TEXT
	if dim:
		accent = C_DISABLED
		col = C_DISABLED
		bg = Color(C_CHIP_BG.r, C_CHIP_BG.g, C_CHIP_BG.b, 0.55)

	# 胶囊 = 中段矩形 + 两端半圆（Godot 无圆角矩形原语；5 次 draw call，边缘干净）。
	var rad := ch * 0.5
	draw_rect(Rect2(rect.position.x + rad, rect.position.y, rect.size.x - rad * 2.0, ch), bg)
	draw_circle(Vector2(rect.position.x + rad, rect.position.y + rad), rad, bg)
	draw_circle(Vector2(rect.end.x - rad, rect.position.y + rad), rad, bg)
	# 1px 描边（半圆 + 两条直边）—— 把"黑色贴纸"变成"有边界的 UI 铭牌"，
	#   在深底上不糊、在亮怪身上也不脏（与 HUD 面板同一种「暗底 + 细边」语言）。
	var bc := Color(accent.r, accent.g, accent.b, 0.45 if not dim else 0.20)
	draw_arc(Vector2(rect.position.x + rad, rect.position.y + rad), rad,
		PI * 0.5, PI * 1.5, 12, bc, 1.0, true)
	draw_arc(Vector2(rect.end.x - rad, rect.position.y + rad), rad,
		-PI * 0.5, PI * 0.5, 12, bc, 1.0, true)
	draw_line(Vector2(rect.position.x + rad, rect.position.y),
		Vector2(rect.end.x - rad, rect.position.y), bc, 1.0, true)
	draw_line(Vector2(rect.position.x + rad, rect.end.y),
		Vector2(rect.end.x - rad, rect.end.y), bc, 1.0, true)

	# 基线 = 画布中心 + (ascent − descent)/2 → 数字在胶囊里**几何居中**
	#   （不用"中心 + 0.36×字号"的经验值：那在小字号上会偏低 1–2px，密集同屏时看得出参差）。
	var base_y := rect.position.y + ch * 0.5 \
		+ (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var x := rect.position.x + PAD_X
	draw_string(font, Vector2(x, base_y), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, sub,
		Color(accent.r, accent.g, accent.b, 0.95 if not dim else 0.55))
	draw_string(font, Vector2(x + w_lbl + gap, base_y), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
