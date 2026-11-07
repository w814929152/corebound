extends Control
##
## B-1 零教学浮层 —— 4 步单向状态机（买 → 放 → 跑 → 修）
##
## 规格：`docs/phase6/b1-tutorial-spec.md`（2026-11-06 立项 · backlog ⑭）
## 归属：UI 呈现层 · **零玩法影响 / 零数值变更 / 零基线迁移**
##
## 🔴 只读契约：全部判定来自 `runtime.snapshot()`（记 `S`）+ `wave_director.snapshot()`（记 `W`）
##    —— `pending` / `towers` / `slots[].disabled` / `w` / `wave` 均已导出
##    ⇒ **零新 snapshot 键、零玩法信号订阅、不读私有字段**。
## 🔴 不遮挡：本节点 `mouse_filter = IGNORE`，**只有**「跳过」子按钮 STOP。
## 🔴 不抢键：`Esc` 仅在「抽屉收起 + 非放置模式」时跳过（规格 §5）；其余归既有语义。
## 🔴 层号 `LAYER_TUTORIAL`（135）写在**本文件内**，**不改 `mvp_config.gd`**（零 cfg-shape 变更）。
##   135 = 高于商店 100 / 核心 HP 130，低于二次确认弹窗 140 ⇒ 弹窗仍可压住引导。
##
## 状态机（单向，永不回退）：
##
##   OFF ─首帧→ BUY ─买到建筑卡(pending>0)→ PLACE ─塔数+1→ RUN ─波次+1→ REPAIR ─受损塔清空→ DONE
##                  └──────────────── 跳过（Esc / 按钮）────────────────┘
##
##   🔴 四项判据都是**相对进入该步时的基线**（"比那时多了什么"），不是绝对阈值 ——
##      实测开局即 W1 自动开波 + 自带 1 塔 1 卡，用绝对阈值会在首帧全部级联通过（见规格 §4.1）。
##   · REPAIR 只在**真的有受损塔**时露出（无事时不刷屏），`_saw_disabled` 记录"见过受损塔"；
##     若到 W8 结束仍未出现任何 Disabled（玩家打得干净）→ 自动 DONE（规格 §7-A(a) 兜底）。
##   · DONE 后本进程内不再出现（无持久化，刻意如此）。
##

const _TSM := preload("res://scripts/engine/time_state_machine.gd")
## 🔴 只读卡价表（纯数据脚本，无副作用）：用于「买不起」时的兜底判定，
##    避免把 12.0 这类价格魔数写死在 UI 层。
const _TD := preload("res://scripts/data/tower_data.gd")

## 🔴 层号常量写在本文件（不落 `mvp_config.gd`，保持零 cfg-shape 变更）。
const LAYER_TUTORIAL := 135

enum Step {
	OFF = 0,     # 首帧前（未开始轮询）
	BUY = 1,     # 买一张卡
	PLACE = 2,   # 点「放置」→ 点塔位落子
	RUN = 3,     # 开始本波
	REPAIR = 4,  # 安全窗修复受损塔
	DONE = 5,    # 教学结束（本进程不再出现）
}

## 配色复用 `hud.gd` 既有常量（同值，不引入新色）。
## 🔴 本文件不 preload `hud.gd`（UI 层互不引用，避免循环依赖 / 加载顺序耦合）。
const C_TEXT := Color(0.784, 0.812, 0.855)      # #C8CFDA
const C_TEXT_DIM := Color(0.545, 0.580, 0.647)  # #8B94A5
const C_PANEL_BG := Color(0.05, 0.06, 0.08, 0.82)

## 几何（规格 §6）：底部上方 96px、宽 720、高 40；避开 `hud.gd` 底部 44px 键位行。
const PANEL_W := 720.0
const PANEL_H := 40.0
## 🆕 96 → 120：核心血条在 UI 优化轮里上移了（BOTTOM_MARGIN 28 → 46），
##    浮层底沿需同步抬升，避免与血条数字行贴死。
const PANEL_BOTTOM_GAP := 120.0
const SKIP_W := 96.0
## 🔴 字号 ≥16px 无障碍下限（S1 定稿）；本浮层取 18。
const FONT_SIZE := 18
const SKIP_FONT_SIZE := 16

const FADE_SEC := 0.12      # 淡入 120ms（步进切换复用同一淡入）
const POLL_HZ := 10.0       # 判定节流 ≤10Hz（不每帧重算）
const REPAIR_FALLBACK_WAVE := 8   # 规格 §7-A(a)：W8 结束仍无受损塔 → 自动 DONE

const STEP_TEXT := {
	Step.PLACE: "点「放置」→ 再点一个塔位落子",
	Step.RUN: "Space 开始下一波 —— 守住核心",
	Step.REPAIR: "安全窗可修复受损塔（点塔位 → 修复 / 拆除）",
}
## PLACE 步的「已进 ⑤」态文案：此刻抽屉已收起，场上只有亮起来的塔位可点。
const PLACE_TEXT_ARMED := "点亮的塔位即可落子（＋ 新建 · ↑ 升级）· Esc 取消"

## BUY 步按「买不买得起 + 商店开没开」分三态（🔴 实测口径，见文件头）：
##   开局 `scrap = 0`，而卡价 12 ⇒ 首波结束前商店里全是灰的。若一律提示"买一张卡"，
##   玩家照做会撞见买不起的货架，首局直接卡在第一步。
const BUY_TEXT_POOR := "守住这一波 —— 击杀敌人换废料，波间才能建塔"
const BUY_TEXT_TAB := "Tab 打开商店 · 1/2/3 买一张建筑卡"
const BUY_TEXT_RICH := "1/2/3 买一张建筑卡"

# ---- 依赖注入（对齐既有 `bind_*` 风格，不用 get_node 满天飞）----
var controller: Node = null       # ShopController（只读 runtime.snapshot()）
var director: Node = null         # TimeDirector（只读 drawer / state，用于 Esc 不抢键判定）
var wave_director: Node = null    # WaveDirector（只读 state / w）
var hud: Node = null              # 仅用于 §7-B(b)：引导未结束前隐藏常驻键位行

# ---- 引导本地状态（纯 UI，非玩法）----
var step: int = Step.OFF
var skipped: bool = false         # true = 玩家主动跳过（区别于自然完成）

var _panel: Panel
var _label: Label
var _skip_btn: Button
var _alpha: float = 0.0
var _poll_accum: float = 0.0
var _saw_disabled: bool = false   # 本局是否见过受损塔（REPAIR 的"见过才教"闸门）
var _cur_has_disabled: bool = false
var _hint_hidden: bool = false
# 🔴 相对基线（进入该步那一刻的读数）——不假设"开局一张卡都没有"：
#    实测开局 W1 已自动开波，且玩家自带 1 座塔 + 1 张卡（见 probe_tutorial_visible）。
#    故判定一律用「比进入本步时**多**了什么」，而不是绝对阈值。
var _place_towers: int = -1       # 进入 PLACE 时的塔数
var _run_wave: int = -1           # 进入 RUN 时的波次
# 🔴 BUY 步文案分态用的两个只读读数（仅影响**文字**，不影响任何判据 / 推进）：
var _buy_can_afford: bool = false # 货架上是否有买得起的卡（快照 `affordable` 任一为真）
var _drawer_open: bool = false    # 商店抽屉是否已开（开着就不必再提示按 Tab）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_layout):
		vp.size_changed.connect(_layout)
	_layout()
	_sync_hud_hint()


# ---------------------------------------------------------------------------
#  依赖注入
# ---------------------------------------------------------------------------
func bind_controller(c: Node) -> void:
	controller = c


func bind_director(d: Node) -> void:
	director = d


func bind_wave_director(wd: Node) -> void:
	wave_director = wd


## §7-B(b)：引导未 DONE 前隐藏 `hud.gd` 的常驻键位行（首屏不与步骤提示互相稀释）。
func bind_hud(h: Node) -> void:
	hud = h
	_sync_hud_hint()


# ---------------------------------------------------------------------------
#  主循环：节流轮询 + 淡入
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum >= 1.0 / POLL_HZ:
		_poll_accum = 0.0
		_poll()
	if visible and _alpha < 1.0:
		_alpha = minf(1.0, _alpha + delta / FADE_SEC)
		modulate = Color(1.0, 1.0, 1.0, _alpha)


func _poll() -> void:
	if step == Step.DONE:
		return
	var s: Dictionary = {}
	if controller != null and controller.runtime != null:
		s = controller.runtime.snapshot()
	var w: Dictionary = {}
	if wave_director != null:
		w = wave_director.snapshot()
	# 仅用于 BUY 文案分态（不改判定）：抽屉开合走 TimeDirector 只读快照。
	if director != null:
		var ds: Dictionary = director.snapshot()
		_drawer_open = int(ds.get("drawer", _TSM.Drawer.CLOSED)) != _TSM.Drawer.CLOSED
	advance_with(s, w)
	_refresh_visual()


# ---------------------------------------------------------------------------
#  状态机（🔴 纯函数化：只吃两个只读快照字典，headless 可直接测）
# ---------------------------------------------------------------------------
## 依据快照推进（单向，永不回退）。返回推进后的 `step`。
func advance_with(s: Dictionary, w: Dictionary) -> int:
	if step == Step.DONE:
		return step
	if step == Step.OFF:
		step = Step.BUY

	var pend: Array = s.get("pending", [])
	var towers := int(s.get("towers", 0))
	_cur_has_disabled = _has_disabled(s)
	_buy_can_afford = _can_afford_any(s)
	var wave_now := _wave_now(s, w)

	# 一次 tick 内允许级联（例：买到即落地 ⇒ BUY → PLACE → RUN）。
	for _i in range(int(Step.DONE)):
		var prev := step
		match step:
			Step.BUY:
				# 🔴 完成判据 = **真的买了建筑卡**（入 pending），不是"背包里有卡"。
				#    实测开局自带 1 张卡 + 1 座塔，用绝对阈值会让这一步在首帧就被跳过。
				if pend.size() > 0:
					_place_towers = towers
					step = Step.PLACE
			Step.PLACE:
				# 相对进入本步时的塔数：多出 1 座 ⇒ 已落子。
				# （取消放置会把卡退回 pending、塔数不变 ⇒ 不会误判）
				if towers > _place_towers:
					_run_wave = wave_now
					step = Step.RUN
			Step.RUN:
				# 🔴 教的是「开**下一**波」：开局 W1 由 `start_run(1)` 自动开波，
				#    玩家真正要学的是安全窗里按 Space 开下一波 ⇒ 波次必须**超过**进入时的波次。
				if wave_now > _run_wave:
					step = Step.REPAIR
			Step.REPAIR:
				if _cur_has_disabled:
					_saw_disabled = true
				if _saw_disabled and not _cur_has_disabled:
					step = Step.DONE
				elif not _saw_disabled and wave_now > REPAIR_FALLBACK_WAVE:
					# 兜底：打到 W8 结束都没有受损塔（打得干净）→ 不把"必须挨打"当前置条件。
					step = Step.DONE
			_:
				pass
		if step == prev:
			break

	_sync_hud_hint()
	return step


func _has_disabled(s: Dictionary) -> bool:
	var slots: Array = s.get("slots", [])
	for row in slots:
		if row is Dictionary and bool(row.get("disabled", false)):
			return true
	return false


## 货架上是否至少有 1 张买得起（快照 `affordable` 已由 `shop_runtime.snapshot()` 导出）。
## 商店尚未发牌（affordable 为空）时退回「废料 ≥ 裸塔价」判定 —— 价格取自 `tower_data.PRICE`。
func _can_afford_any(s: Dictionary) -> bool:
	var aff: Array = s.get("affordable", [])
	if aff.size() > 0:
		for a in aff:
			if bool(a):
				return true
		return false
	return float(s.get("scrap", 0.0)) >= float(_TD.PRICE["tower"])


func _wave_now(s: Dictionary, w: Dictionary) -> int:
	return maxi(int(w.get("w", 0)), int(s.get("wave", 0)))


# ---------------------------------------------------------------------------
#  关闭 / 跳过（规格 §5）
# ---------------------------------------------------------------------------
## 立即 DONE，本进程不再出现。`skipped=true` 只用于区分"跳过"与"自然完成"。
func skip() -> void:
	if step == Step.DONE:
		return
	step = Step.DONE
	skipped = true
	visible = false
	_sync_hud_hint()


func _on_skip_pressed() -> void:
	skip()


## Esc 跳过——🔴 仅当「抽屉收起 + 非放置模式」，否则归既有语义（关抽屉 / 取消放置），不抢键。
func _input(event: InputEvent) -> void:
	if step == Step.DONE or step == Step.OFF:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode != KEY_ESCAPE:
		return
	if not _esc_is_free():
		return
	skip()
	get_viewport().set_input_as_handled()


func _esc_is_free() -> bool:
	if director == null:
		return true
	var sn: Dictionary = director.snapshot()
	if int(sn.get("drawer", _TSM.Drawer.CLOSED)) != _TSM.Drawer.CLOSED:
		return false
	if int(sn.get("state", _TSM.State.COMBAT)) == _TSM.State.PLACEMENT_MODE:
		return false
	return true


# ---------------------------------------------------------------------------
#  呈现
# ---------------------------------------------------------------------------
func _build() -> void:
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL_BG
	sb.set_border_width_all(1)
	# 🆕 补描边（art-bible §5.1「面板 = 深色底 + 亮色描边」）；原浮层只有纯色底、无边界，
	#    压在暗战场上时边缘糊在一起。
	sb.border_color = Color(0.243, 0.816, 0.910, 0.32)
	sb.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", C_TEXT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过"
	_skip_btn.flat = true
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.add_theme_font_size_override("font_size", SKIP_FONT_SIZE)
	_skip_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	_skip_btn.add_theme_color_override("font_hover_color", C_TEXT)
	# 🔴 唯一可交互子控件：只有它 STOP，面板与文案一律 IGNORE ⇒ 绝不遮挡塔位点击。
	_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip_btn.pressed.connect(_on_skip_pressed)
	_panel.add_child(_skip_btn)


func _layout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	position = Vector2.ZERO
	size = vs
	if _panel == null:
		return
	_panel.position = Vector2((float(vs.x) - PANEL_W) * 0.5, float(vs.y) - PANEL_BOTTOM_GAP - PANEL_H)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	if _label != null:
		_label.position = Vector2(16.0, 0.0)
		_label.size = Vector2(PANEL_W - SKIP_W - 32.0, PANEL_H)
	if _skip_btn != null:
		_skip_btn.position = Vector2(PANEL_W - SKIP_W - 8.0, 2.0)
		_skip_btn.size = Vector2(SKIP_W, PANEL_H - 4.0)


func _refresh_visual() -> void:
	# 不可见态：未开始 / 已结束 / REPAIR 但当前没有受损塔（无事不刷屏）。
	var want_show := step != Step.OFF and step != Step.DONE
	if want_show and step == Step.REPAIR and not _cur_has_disabled:
		want_show = false
	if not want_show:
		visible = false
		_alpha = 0.0
		modulate = Color(1.0, 1.0, 1.0, 0.0)
		return
	_label.text = _text_for(step)
	if not visible:
		# 步进切换 / 首次出现：从头淡入。
		_alpha = 0.0
		modulate = Color(1.0, 1.0, 1.0, 0.0)
	visible = true


## 当前步文案。BUY 步按「买不买得起 + 抽屉开没开」分三态（判据不受影响，只换字）。
##   PLACE 步同理分两态：已进 ⑤（抽屉收起、战场全屏）时，再让玩家「点「放置」」就是胡说 ——
##   那一刻他能做的只有**点战场上亮起来的塔位**。
func _text_for(s: int) -> String:
	if s == Step.PLACE:
		return String(STEP_TEXT[s]) if not _in_placement() else PLACE_TEXT_ARMED
	if s != Step.BUY:
		return String(STEP_TEXT.get(s, ""))
	if not _buy_can_afford:
		return BUY_TEXT_POOR
	return BUY_TEXT_RICH if _drawer_open else BUY_TEXT_TAB


func _in_placement() -> bool:
	if director == null or director.sm == null:
		return false
	return int(director.sm.state) == _TSM.State.PLACEMENT_MODE


func _sync_hud_hint() -> void:
	if hud == null:
		return
	var want_hidden := step != Step.DONE
	if want_hidden == _hint_hidden:
		return
	_hint_hidden = want_hidden
	if hud.has_method("set_hint_visible"):
		hud.set_hint_visible(not want_hidden)
