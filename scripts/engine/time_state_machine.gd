extends RefCounted
##
## 五态时钟状态机 —— `design/gdd/shop-reroll.md` v1.1 §2.1 的**纯逻辑实现**
##
## 🔴 设计约束（为什么单独拆一层）：
##   1. **零副作用**：本文件**不碰** `Engine` / `SceneTree` / `Node` / 输入。
##      它只回答「当前态的时钟口径是什么」「预算该不该扣」「这次转换合不合法」。
##      → 因此可以在 headless 下**不建场景树**直接单测（见 `tests/test_suite_slice3.gd`）。
##   2. **状态机必须显式**：GDD §2.1 明写「不许用一个布尔 `is_shop_open` 去驱动」。
##      五个态的时钟口径各不相同，转换表在 `_TRANSITIONS` 里显式列举，非法转换返回 false。
##   3. **口径只读 `MvpConfig`**，本文件不定义任何数值。
##
## 副作用（写 `Engine.time_scale` / `get_tree().paused`）由 UI 适配层负责：
##   → `scripts/ui/time_director.gd`（Node，process_mode = ALWAYS）
##
## 时钟口径总表（GDD §2.1，逐条对应 `clock()` 的返回值）
##
## | 态 | Engine.time_scale | 战斗推进 | 减速预算 | 抽屉 |
## |---|---|---|---|---|
## | ① Combat        | 1.0            | ✅      | 冻结     | 关闭 |
## | ② ShopDilated   | 1.0            | ✅      | ✅ 消耗（W1–5 不消耗）| 轻决策 |
## | ③ ShopRealTime  | 1.0            | ✅      | ❌ 已耗尽 | 轻决策（预算条标红）|
## | ④ SafeWindow    | 1.0（世界暂停靠 paused）| ⏸ | 冻结 | 重决策 |
## | ⑤ PlacementMode | 0.25           | ✅      | ✅ 消耗（W1–5 不消耗）| 🔴 收起 |
##

# 🔴 G6：headless `--script` 没有 global_script_class_cache → 一律 preload，不用 class_name
const _Cfg := preload("res://scripts/engine/mvp_config.gd")


enum State {
	COMBAT = 0,          # ①
	SHOP_DILATED = 1,    # ②
	SHOP_REAL_TIME = 2,  # ③
	SAFE_WINDOW = 3,     # ④
	PLACEMENT_MODE = 4,  # ⑤
}

enum Drawer {
	CLOSED = 0,   # 抽屉收起（①⑤）
	LIGHT = 1,    # 轻决策模式（②③）
	HEAVY = 2,    # 重决策模式（④，额外露出弃卡/卸下改投/拆除回收）
}

const STATE_NAME := {
	State.COMBAT: "Combat",
	State.SHOP_DILATED: "ShopDilated",
	State.SHOP_REAL_TIME: "ShopRealTime",
	State.SAFE_WINDOW: "SafeWindow",
	State.PLACEMENT_MODE: "PlacementMode",
}

# 显式转换表：from -> 允许的 to 集合
const _TRANSITIONS := {
	State.COMBAT: [State.SHOP_DILATED, State.SHOP_REAL_TIME, State.SAFE_WINDOW],
	State.SHOP_DILATED: [State.COMBAT, State.SHOP_REAL_TIME, State.PLACEMENT_MODE, State.SAFE_WINDOW],
	State.SHOP_REAL_TIME: [State.COMBAT, State.PLACEMENT_MODE, State.SAFE_WINDOW],
	State.SAFE_WINDOW: [State.COMBAT, State.PLACEMENT_MODE],
	State.PLACEMENT_MODE: [State.SHOP_DILATED, State.SHOP_REAL_TIME, State.SAFE_WINDOW],
}


var state: int = State.COMBAT
var wave: int = 1
var budget_left: float
var budget_max: float

var _prev_state: int = State.COMBAT       # ⑤ 退出时要回到的态（GDD：② 或 ④）
var _shop_open_pref: bool = false         # 玩家上次的开/关偏好（§4.1：波次开始不强制弹出）
var _last_error: String = ""


func _init(w: int = 1) -> void:
	wave = w
	budget_max = float(_Cfg.DILATION_BUDGET)
	budget_left = budget_max


# ---------------------------------------------------------------------------
#  时钟口径（唯一真源）
# ---------------------------------------------------------------------------

## 返回某态（默认当前态）的时钟口径。
##   time_scale      —— 要写给 `Engine.time_scale` 的值（🔴 永不为 0，SR-R5）
##   paused          —— 要写给 `get_tree().paused` 的值
##   consumes_budget —— 本态是否消耗减速预算
##   drawer          —— 抽屉形态（Drawer 枚举）
func clock(st: int = -1) -> Dictionary:
	if st < 0:
		st = state
	var novice := _is_novice_wave()
	match st:
		State.COMBAT:
			return _mk(_Cfg.TIME_SCALE_COMBAT, false, false, Drawer.CLOSED)
		State.SHOP_DILATED:
			return _mk(
				_Cfg.DILATION_SCALE_NOVICE if novice else _Cfg.DILATION_SCALE,
				false, not novice, Drawer.LIGHT)
		State.SHOP_REAL_TIME:
			return _mk(_Cfg.TIME_SCALE_COMBAT, false, false, Drawer.LIGHT)
		State.SAFE_WINDOW:
			# 🔴 世界暂停靠 paused=true，time_scale **保持 1.0**（SR-R5）
			# 抽屉在安全窗里可被玩家手动收起（Tab/Esc 在 ④ 可用，§4.2），
			# 所以抽屉形态取决于玩家的开/关偏好，而不是写死 HEAVY。
			return _mk(_Cfg.TIME_SCALE_COMBAT, true, false,
				Drawer.HEAVY if _shop_open_pref else Drawer.CLOSED)
		State.PLACEMENT_MODE:
			# 🔴 Q-S3-A（GDD v1.2 §2.1 易错口径第 4 条）：
			#    **预算为 0 时进入 ⑤ 不得再减速（等效 1.0×）** ——
			#    否则 0.25× 会变成预算耗尽后的**免费无限慢动作**，"时间即货币"当场作废。
			#    （新手波 W1–5 预算恒满、不消耗，不会走到这个分支。）
			if is_budget_drained():
				return _mk(_Cfg.TIME_SCALE_COMBAT, false, false, Drawer.CLOSED)
			return _mk(_Cfg.PLACEMENT_SCALE, false, not novice, Drawer.CLOSED)
		_:
			push_error("TimeStateMachine: 未知态 %d" % st)
			return _mk(_Cfg.TIME_SCALE_COMBAT, false, false, Drawer.CLOSED)


func _mk(ts: float, paused_: bool, consume: bool, drawer: int) -> Dictionary:
	return {
		"time_scale": ts,
		"paused": paused_,
		"consumes_budget": consume,
		"drawer": drawer,
	}


func _is_novice_wave() -> bool:
	return wave <= _Cfg.NOVICE_WAVE_MAX


func is_budget_drained() -> bool:
	return budget_left <= 0.0


func state_name(st: int = -1) -> String:
	if st < 0:
		st = state
	return String(STATE_NAME.get(st, "?"))


# ---------------------------------------------------------------------------
#  转换
# ---------------------------------------------------------------------------

func can_transition(to: int) -> bool:
	if to == state:
		return true
	var allowed: Array = _TRANSITIONS.get(state, [])
	return allowed.has(to)


## 显式转换。非法转换返回 false 并把原因记进 `last_error()`（不抛异常 —— 输入噪声不该崩游戏）。
func transition(to: int) -> bool:
	if to == state:
		return true
	if not can_transition(to):
		_last_error = "非法转换 %s -> %s" % [state_name(), state_name(to)]
		return false
	_last_error = ""
	state = to
	return true


func last_error() -> String:
	return _last_error


# ---- 玩家动作（语义化入口；UI 只调这些，不直接写 state）----

## 打开商店抽屉。🔴 E3：预算不足 1s **不得**拒绝打开，仍按剩余量减速 → 耗尽转 ③。
func open_shop() -> bool:
	if state == State.SAFE_WINDOW:
		_shop_open_pref = true
		return true                      # 安全窗本就是展开态
	var target := State.SHOP_REAL_TIME if is_budget_drained() else State.SHOP_DILATED
	if not transition(target):
		return false
	_shop_open_pref = true
	return true


## 关闭抽屉（Tab / Esc）。Q-SR2：预算耗尽**不强制关闭**，只回 1.0×。
## ④ 里收起抽屉**不改变态**（仍是安全窗，世界仍暂停），只改玩家的开/关偏好。
func close_shop() -> bool:
	if state == State.SAFE_WINDOW:
		_last_error = ""
		_shop_open_pref = false
		return true
	if state != State.SHOP_DILATED and state != State.SHOP_REAL_TIME:
		_last_error = "当前态 %s 无法关闭抽屉" % state_name()
		return false
	_shop_open_pref = false
	return transition(State.COMBAT)


func toggle_shop() -> bool:
	if state == State.SAFE_WINDOW:
		return close_shop() if _shop_open_pref else open_shop()
	if state == State.SHOP_DILATED or state == State.SHOP_REAL_TIME:
		return close_shop()
	return open_shop()


## 进入放置模式（⑤）。记住进入前的态，退出时原路返回（GDD §2.1 图注）。
func enter_placement() -> bool:
	if state == State.PLACEMENT_MODE:
		return true
	if not (state == State.SHOP_DILATED or state == State.SHOP_REAL_TIME or state == State.SAFE_WINDOW):
		_last_error = "态 %s 不能进入放置模式" % state_name()
		return false
	_prev_state = state
	return transition(State.PLACEMENT_MODE)


## 落子 / Esc 取消（🔴 取消不退款）。返回到进入前的态。
func exit_placement() -> bool:
	if state != State.PLACEMENT_MODE:
		return true
	var back := _prev_state
	# 预算在放置期间被耗尽 → 回不了 ②（它已经没有减速额度了），落到 ③；
	# 从 ④ 进的放置 → 原路回 ④（世界本暂停，见 Q-S3-A v1.2 澄清）。
	if back == State.SHOP_DILATED and is_budget_drained():
		back = State.SHOP_REAL_TIME
	return transition(back)


# ---- 波次（对接 wave-spawner 的 WS-1 / WS-2 契约）----

## 波次开始：`n ← 0`、`budget_left ← 20.0`、`deal_initial_shop(w)`（🔴 走 pity，由下游做）。
## 抽屉**保持玩家上次开/关状态**（§4.1：不强制弹出）。
func wave_start(w: int) -> void:
	wave = w
	budget_left = budget_max
	_last_error = ""
	if state == State.SAFE_WINDOW:
		state = State.COMBAT
	if _shop_open_pref:
		state = State.SHOP_REAL_TIME if is_budget_drained() else State.SHOP_DILATED
	else:
		state = State.COMBAT


## 波次结束 → 安全窗（`paused=true`），商店自动展开为「重决策模式」（Q-SR3 = ① 自动打开）。
func wave_end(_w: int) -> void:
	_shop_open_pref = true
	state = State.SAFE_WINDOW


## 玩家点「开始下一波」（E14：安全窗**无超时**强制推进）。
func start_next_wave() -> bool:
	if state != State.SAFE_WINDOW:
		_last_error = "只有 SafeWindow 能开始下一波（当前 %s）" % state_name()
		return false
	wave_start(wave + 1)
	return true


# ---------------------------------------------------------------------------
#  unscaled 预算计时（🔴 单位 = 实时秒，不受 time_scale / paused 影响）
# ---------------------------------------------------------------------------

## 推进一帧。**dt_real 必须由调用方用 unscaled 时钟给出**
## （`Time.get_ticks_msec()` 差值，或 `delta / Engine.time_scale`）。
## 返回：本帧是否发生了状态变化。
func tick(dt_real: float) -> bool:
	var before := state

	# 🔴 Q-S3-A（GDD v1.2 §2.1 易错口径第 4 条，主理人 2026-10-01 澄清）：
	#    预算**已经**是 0 却仍在 ⑤ → **立即退出放置**（而不是继续用 0.25× 白嫖慢动作）。
	#    回落目标按进入来源分两种：
	#      · 从 ②/③ 进 ⑤ → 落 ③ 全速（回不了 ②，减速额度已尽）；
	#      · 从 ④ 进 ⑤ → 回 ④（世界本暂停、预算在 ④ 冻结，原路返回；
	#        🔴 不会造成免费慢动作——④ 里 paused=true 时间完全停止）。
	if state == State.PLACEMENT_MODE and is_budget_drained():
		var back := _prev_state
		if back != State.SAFE_WINDOW:
			back = State.SHOP_REAL_TIME
		state = back
		return state != before

	var c := clock()
	if not bool(c["consumes_budget"]):
		return false
	if dt_real <= 0.0:
		return false

	budget_left -= dt_real
	if budget_left <= 0.0:
		budget_left = 0.0
		match state:
			State.SHOP_DILATED:
				state = State.SHOP_REAL_TIME            # 耗尽 → 回 1.0×（Q-SR2：不强制关店）
			State.PLACEMENT_MODE:
				# ✅ Q-S3-A 已拍板（主理人 2026-10-01，GDD v1.2）：
				#   **立即退出放置、落 ③ 全速** —— 否则 0.25× 会变成预算耗尽后的
				#   **免费慢动作**，预算就不再是货币了。
				#   待放置的卡**退回队列**（不销毁、不退款），与 Esc 取消同口径
				#   （卡队列归 `tower-build` 管，本文件不持有玩法状态）。
				var back := _prev_state
				if back != State.SAFE_WINDOW:
					back = State.SHOP_REAL_TIME
				state = back
	return state != before


## 供自测/冒烟直接注入实时秒（等价于连续 tick），绕过真实帧。
func spend_budget(seconds: float) -> bool:
	return tick(seconds)


## 重置到出厂态（自测用）。
func reset(w: int = 1) -> void:
	state = State.COMBAT
	wave = w
	budget_max = _Cfg.DILATION_BUDGET
	budget_left = budget_max
	_prev_state = State.COMBAT
	_shop_open_pref = false
	_last_error = ""
