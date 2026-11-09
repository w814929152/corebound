extends Node
##
## 五态时钟「适配层」—— 把 `TimeStateMachine` 的纯口径**落地**到 Godot 引擎。
##
## 🔴 职责边界（control-manifest §5：UI 层不持有游戏状态；这里持的是**时钟状态**，不是玩法状态）：
##   · 唯一允许写 `Engine.time_scale` / `get_tree().paused` 的地方（SSOT）；
##   · 每帧用 **unscaled 时钟**（`Time.get_ticks_msec()`）算 dt，喂给状态机扣预算；
##   · 把状态变化广播成信号，UI 订阅（高亮 / 抽屉 / 预算条 / 红光脉冲）。
##
## 🔴 process_mode = ALWAYS：安全窗（④）下世界全停，但商店与时钟必须继续跑。
##    实测依据见 `docs/phase3/slice3-godot47-api-probe.log`。
##
## 后续切片要接的**意图信号**已在下方声明（骨架阶段只发不实现）：
##   reroll_requested / buy_requested / lock_toggled / placement_confirmed / salvage_requested / repair_requested
##

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")


signal state_changed(from_state: int, to_state: int)
signal clock_applied(time_scale: float, paused: bool)
signal budget_changed(left: float, budget_max: float)
signal budget_drained()
signal drawer_mode_changed(mode: int)
signal wave_started(wave: int)
signal wave_ended(wave: int)

# ---- 后续切片的意图信号（🔴 商店只发意图，不改卡牌/管线状态，SR-5 / CD-E）----
signal reroll_requested()
signal buy_requested(slot: int)
signal lock_toggled(slot: int)
signal placement_confirmed(slot: int)
signal salvage_requested()
## 🔒 T1 修复入口 UI（Q-T4 三选一）：安全窗重决策面板「处置受损塔」按钮 →
##   ShopController 读 runtime.list_disabled_towers() 弹出多塔处置弹窗（修复/被动拆除/放着不管）。
signal repair_requested()
## 🟡 切片8·I-7：战场塔位点选请求（MonsterLayer 点击塔 → 本信号 → ShopController 接 runtime.select_tower）
signal tower_select_requested(slot: int)
## 🟡 放置模式落子请求（MonsterLayer 点**高亮塔位** → 本信号 → ShopController 落子）。
##   🔴 与 `placement_confirmed` 分工：本信号是**意图**（谁想落在哪），
##      `placement_confirmed` 是**决定**（退出放置模式并执行）。渲染层只发意图、不碰状态机。
signal slot_place_requested(slot: int)
## 🆕 自由摆放：战场坐标落子意图（MonsterLayer 点**地图任意格** → 本信号）。
##   🔴 与 `slot_place_requested` 并存：旧信号按「槽位号」提交，只在槽位已知时可用
##      （回归对照 / 探针）；玩家自由摆放走这条，带的是**吸附后的格点世界坐标**。
##      吸附由渲染层做（它知道 `sc` 和鼠标位置），runtime 会再吸附一次（幂等，防手抖）。
signal place_at_requested(pos: Vector2)
signal placement_cancelled()


var sm = null                 # TimeStateMachine 实例（纯逻辑）
var focus_index: int = 0      # 焦点位 ∈ {0,1,2}（§2.4「有且仅有 1 个焦点位」）

var real_seconds: float = 0.0   # 实时秒累计（unscaled）—— 玩家实际思考时间
var game_seconds: float = 0.0   # 游戏时间累计（scaled）—— 战场实际推进量

var _last_msec: int = 0
var _emitted_state: int = -1
var _emitted_budget: float = -1.0
var _emitted_drawer: int = -1


func _ready() -> void:
	# 🔴 安全窗下世界暂停，但商店/时钟必须继续 → ALWAYS
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	sm = _TSM.new()
	sm.wave = 1
	_last_msec = Time.get_ticks_msec()
	_apply_clock(true)


func _process(delta: float) -> void:
	# ---- unscaled 实时秒（🔴 不受 time_scale / paused 影响，实测见探针日志）----
	var now := Time.get_ticks_msec()
	var dt_real := float(now - _last_msec) / 1000.0
	_last_msec = now
	if dt_real < 0.0:
		dt_real = 0.0
	# 🟡 工程夹子（Q-S3-B 待拍板）：窗口失焦 / 断点回来时差值会是一次巨大跳变，
	#    不夹住就会把整段预算一次性吃掉。
	if dt_real > _Cfg.MAX_FRAME_REAL_DT:
		dt_real = _Cfg.MAX_FRAME_REAL_DT

	real_seconds += dt_real
	game_seconds += float(delta)          # scaled：战场真实推进量

	sm.tick(dt_real)
	_apply_clock(false)


# ---------------------------------------------------------------------------
#  把纯口径写进引擎（SSOT）
# ---------------------------------------------------------------------------
func _apply_clock(force: bool) -> void:
	var c: Dictionary = sm.clock()
	var ts := float(c["time_scale"])

	# 🔴 SR-R5：`Engine.time_scale` 永不为 0。真出现 0 就当场炸，别静默跑飞。
	assert(ts > 0.0, "SR-R5 违反：time_scale 不得为 0（安全窗改用 get_tree().paused）")

	if not is_equal_approx(float(Engine.time_scale), ts):
		Engine.time_scale = ts
	if get_tree().paused != bool(c["paused"]):
		get_tree().paused = bool(c["paused"])

	if force or sm.state != _emitted_state:
		var from_state := _emitted_state
		_emitted_state = sm.state
		emit_signal("state_changed", from_state, sm.state)
		emit_signal("clock_applied", ts, bool(c["paused"]))
	var dr: int = int(c["drawer"])
	if force or dr != _emitted_drawer:
		_emitted_drawer = dr
		emit_signal("drawer_mode_changed", dr)
	if force or not is_equal_approx(sm.budget_left, _emitted_budget):
		var was_drained := _emitted_budget > 0.0
		_emitted_budget = sm.budget_left
		emit_signal("budget_changed", sm.budget_left, sm.budget_max)
		if was_drained and sm.budget_left <= 0.0:
			emit_signal("budget_drained")


# ---------------------------------------------------------------------------
#  语义化入口（供 UI 按钮 / 输入 / 后续 wave-spawner 调用）
# ---------------------------------------------------------------------------

func open_shop() -> void:
	if sm.open_shop():
		_apply_clock(false)


func close_shop() -> void:
	if sm.close_shop():
		_apply_clock(false)


func toggle_shop() -> void:
	if sm.toggle_shop():
		_apply_clock(false)


func enter_placement() -> void:
	if sm.enter_placement():
		_apply_clock(false)


## 落子 / Esc 取消（🔴 取消不退款）。
## `slot` = 落子的塔位（I-8，切片4 接线用）；-1 = 未指定（骨架阶段的默认行为）。
func exit_placement(confirmed: bool, slot: int = -1) -> void:
	if confirmed:
		emit_signal("placement_confirmed", slot)
	else:
		emit_signal("placement_cancelled")
	finish_placement()


## 已由世界坐标入口提交的放置，只退出模式，不再次提交/取消卡牌。
func finish_placement() -> void:
	if sm.exit_placement():
		_apply_clock(false)


## 波次开始（WS-1）：n ← 0、预算 ← 20.0、发初始商店（pity 由下游做）
## 开局准备不发 wave_started，刷怪器保持 IDLE。
func prepare_run(first_wave: int = 1) -> void:
	sm.wave = first_wave - 1
	sm.budget_left = sm.budget_max
	sm.wave_end(sm.wave)
	_apply_clock(true)


func wave_start(w: int) -> void:
	sm.wave_start(w)
	_apply_clock(true)
	emit_signal("wave_started", w)


## 波次结束（WS-2）：进安全窗 + 商店自动展开为「重决策模式」
func wave_end(w: int) -> void:
	sm.wave_end(w)
	_apply_clock(true)
	emit_signal("wave_ended", w)


func start_next_wave() -> void:
	if sm.start_next_wave():
		_apply_clock(true)
		emit_signal("wave_started", sm.wave)


# ---------------------------------------------------------------------------
#  输入（🔴 本节点 process_mode = ALWAYS → 安全窗下也能收；实测见探针日志 G 段）
#  用 `_unhandled_key_input`：让 UI 控件先吃事件，避免商店里的按钮被全局热键抢走。
# ---------------------------------------------------------------------------
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var e := event as InputEventKey
	if not e.pressed or e.echo:
		return

	match e.keycode:
		KEY_TAB:
			toggle_shop()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if sm.state == _TSM.State.PLACEMENT_MODE:
				exit_placement(false)          # Esc 取消（🔴 取消不退款）
			else:
				close_shop()
			get_viewport().set_input_as_handled()
		KEY_R:
			if _shop_open():
				emit_signal("reroll_requested")
				get_viewport().set_input_as_handled()
		KEY_1, KEY_2, KEY_3:
			if _shop_open():
				focus_index = e.keycode - KEY_1
				emit_signal("buy_requested", focus_index)   # 「选中即买」（§4.2）
				get_viewport().set_input_as_handled()
		KEY_SPACE:
			if _shop_open():
				emit_signal("lock_toggled", focus_index)    # 永远作用于**焦点位**
				get_viewport().set_input_as_handled()
		_:
			pass


func _shop_open() -> bool:
	var dr: int = int(sm.clock()["drawer"])
	return dr != _TSM.Drawer.CLOSED


# ---------------------------------------------------------------------------
#  只读快照（给 HUD / 自测 / 冒烟打印用）
# ---------------------------------------------------------------------------
func snapshot() -> Dictionary:
	var c: Dictionary = sm.clock()
	return {
		"state": sm.state,
		"state_name": sm.state_name(),
		"wave": sm.wave,
		"time_scale": float(c["time_scale"]),
		"paused": bool(c["paused"]),
		"consumes_budget": bool(c["consumes_budget"]),
		"drawer": int(c["drawer"]),
		"budget_left": sm.budget_left,
		"budget_max": sm.budget_max,
		"engine_time_scale": float(Engine.time_scale),
		"tree_paused": get_tree().paused,
		"real_seconds": real_seconds,
		"game_seconds": game_seconds,
		"focus_index": focus_index,
		"last_error": sm.last_error(),
	}


## Tab 是全局商店开关，先于 GUI 焦点导航处理，购买后按钮获焦也能关闭。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed and not event.echo:
		if sm != null and sm.state != _TSM.State.PLACEMENT_MODE:
			toggle_shop()
			get_viewport().set_input_as_handled()
