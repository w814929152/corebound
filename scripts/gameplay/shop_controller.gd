extends Node
##
## 切片4 · 接线层（**唯一**把 `TimeDirector` 的意图信号接到 `ShopRuntime` 的地方）
## 切片5 · 波次推进改由 `WaveDirector`（真实刷怪战斗循环）驱动
##
## 三个职责（🔴 全是"接线"，不含任何口径）：
##   ① **I-2 商店意图接线**：`reroll_requested` / `buy_requested` / `lock_toggled`
##        / `placement_confirmed` → `ShopRuntime` 的对应方法 → 广播 `shop_changed`；
##   ② **I-1 波次信号接线**：`wave_started(w)` → `runtime.start_wave(w)`（发初始商店 + pity）；
##        `wave_ended(w)` → `runtime.grant_wave_result()`（击杀收入入账，M5）；
##   ③ 🟢 **切片5：波次推进不再由本文件驱动** —— 删掉切片4 的"最小波次驱动器"
##        （`wave_elapsed` 空转计时）与 D-8 的 `debug_end_wave()` 调试按钮；
##        改由 `WaveDirector` 真实刷怪 + 打完判定 → 调 `TimeDirector.wave_end(w)`。
##
## 🔴 依赖方向（control-manifest §5 / SR-5）：UI 只发意图，不写玩法状态；
##    玩法状态只在 `ShopRuntime` / `WaveDirector` 里；本节点是二者之间**唯一**的桥。
##
## 🔴 收入口径（切片5 不动，见 `docs/phase3/slice5-verify.md` §5 S5-D1）：
##    `_pending_result` 仍由金标本 `WaveSim.simulate_wave()` 在**波首**结算（R1：
##    本波打的是上波买出来的构筑）。在「金标本等价口径」下（`prototype_split_enabled`
##    == false 且 `elite_waves_enabled` == false）实时结果与金标本**逐位相同**，
##    此时直接授予**实时结果**（它是真实战斗的产出）；否则回落到金标本，
##    并打一行 `[WARN]`（口径分歧待主理人拍板）。🔴 MC 判据链不受影响（它走 `RunLoop`）。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 本文件**不写 `class_name`**，一律 preload。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")

# 交互局 RNG 种子（= MC 定稿种子，便于复现；不是平衡参数）
const DEFAULT_RUN_SEED := 20260930


signal shop_changed()
signal run_changed()


var runtime = null
var director: Node = null            # TimeDirector（时钟权威）
var wave_director: Node = null       # WaveDirector（波次 / 刷怪权威，切片5）

var over: bool = false               # 核心 HP ≤ 0 → 不再推进
var _pending_result: Dictionary = {}
var last_realtime_result: Dictionary = {}


func _ready() -> void:
	# 🔴 安全窗（paused=true）下本节点仍要跑（意图接线不能停）
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func setup(p_path: String = "B", seed_value: int = DEFAULT_RUN_SEED) -> void:
	runtime = _ShopRuntime.new()
	runtime.setup(p_path, seed_value)
	over = false
	_pending_result = {}
	last_realtime_result = {}


# ---------------------------------------------------------------------------
#  接线：director 的意图 / 波次信号 → runtime
# ---------------------------------------------------------------------------
func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	if not d.is_connected("reroll_requested", _on_reroll_requested):
		d.reroll_requested.connect(_on_reroll_requested)
	if not d.is_connected("buy_requested", _on_buy_requested):
		d.buy_requested.connect(_on_buy_requested)
	if not d.is_connected("lock_toggled", _on_lock_toggled):
		d.lock_toggled.connect(_on_lock_toggled)
	if not d.is_connected("placement_confirmed", _on_placement_confirmed):
		d.placement_confirmed.connect(_on_placement_confirmed)
	if not d.is_connected("placement_cancelled", _on_placement_cancelled):
		d.placement_cancelled.connect(_on_placement_cancelled)
	if not d.is_connected("wave_started", _on_wave_started):
		d.wave_started.connect(_on_wave_started)
	if not d.is_connected("wave_ended", _on_wave_ended):
		d.wave_ended.connect(_on_wave_ended)
	#  salvage_requested：🟡 后续切片（拆除回收结算器），本轮只登记不实现
	if not d.is_connected("salvage_requested", _on_salvage_requested):
		d.salvage_requested.connect(_on_salvage_requested)


## 切片5：`WaveDirector` 注入。波次推进（刷怪 / 伤害 / 漏怪 / 结束判定）由它负责。
func bind_wave_director(wd: Node) -> void:
	wave_director = wd
	if wd == null:
		return
	# 🔴 `wave_result` 在 `TimeDirector.wave_ended` **之前**发出 →
	#    `_on_wave_ended` 里必然已拿到本波的实时结算。
	if not wd.is_connected("wave_result", _on_wave_result):
		wd.wave_result.connect(_on_wave_result)
	if not wd.is_connected("run_lost", _on_run_lost):
		wd.run_lost.connect(_on_run_lost)
	if runtime != null:
		wd.bind_runtime(runtime)


func _on_wave_result(_w: int, res: Dictionary) -> void:
	last_realtime_result = res.duplicate()


func _on_run_lost(p_w: int) -> void:
	over = true
	print("[shop_controller] 核心 HP 归零（W%d）→ 停止推进（E-W3 立即失败）" % p_w)
	_emit_run()


func _on_reroll_requested() -> void:
	if runtime == null:
		return
	if runtime.reroll():
		_emit_shop()


func _on_buy_requested(slot: int) -> void:
	if runtime == null:
		return
	if runtime.buy(slot):
		_emit_shop()


func _on_lock_toggled(slot: int) -> void:
	if runtime == null:
		return
	if runtime.toggle_lock(slot):
		_emit_shop()


func _on_placement_confirmed(slot: int) -> void:
	if runtime == null:
		return
	if runtime.confirm_placement(slot):
		_emit_shop()


func _on_placement_cancelled() -> void:
	if runtime == null:
		return
	runtime.cancel_placement()      # 🔴 取消不退款，卡留在待放置队列
	_emit_shop()


func _on_salvage_requested() -> void:
	# 🟡 后续切片：拆除回收（`TowerRemove` 结算器 + 二次确认弹窗，I-9 / §2.9）
	print("[shop_controller] salvage_requested 已收到，🟡 拆除回收未在切片4 实现")


# ---- 待放置队列 → 进入放置模式（I-8 的前半段）----
func request_placement(pending_index: int) -> bool:
	if runtime == null or director == null:
		return false
	if not runtime.begin_placement(pending_index):
		return false
	# 🔴 `TimeDirector.enter_placement()` 返回 void（适配层只写引擎时钟，不回传成功与否）
	#    → 用状态机的**实际态**判定进入是否成功，不要用返回值。
	director.enter_placement()
	if int(director.sm.state) != _TSM.State.PLACEMENT_MODE:
		runtime.cancel_placement()
		return false
	_emit_shop()
	return true


# ---------------------------------------------------------------------------
#  I-1 波次信号
# ---------------------------------------------------------------------------
func _on_wave_started(w: int) -> void:
	if runtime == null:
		return
	# 🔴 R1：本波打的是**上波买出来的构筑** → 战前先结算一次并存起来（波末才入账）
	_pending_result = runtime.simulate_wave_result(w)
	runtime.start_wave(w)            # n ← 0 · 锁定清空 · 发初始商店（pity）
	_emit_shop()
	_emit_run()


func _on_wave_ended(w: int) -> void:
	if runtime == null:
		return
	var res := _pending_result
	var rt := last_realtime_result
	if int(rt.get("w", -1)) == w and _realtime_is_golden_equivalent():
		res = rt
	elif not rt.is_empty() and int(rt.get("w", -1)) == w:
		print("[shop_controller][WARN] W%d 实时结果与金标本口径不一致（三原型/Elite 已开）"
			% w + " → 收入回落金标本（S5-D1 待拍板）")
	runtime.grant_wave_result(res)   # R3：击杀收入 × (1 + income_mult)
	if runtime.core_hp <= 0.0:
		over = true
		print("[shop_controller] 核心 HP 归零（W%d）→ 停止推进" % w)
	_emit_shop()
	_emit_run()


## 🔴 只有在「金标本等价口径」下才允许用实时结果入账：
##    三原型分化 / Elite 任一开启 → 实时结果与 `WaveSim` 不等价（S5-D1）。
func _realtime_is_golden_equivalent() -> bool:
	if wave_director == null:
		return false
	return (not bool(wave_director.prototype_split_enabled)) \
		and (not bool(wave_director.elite_waves_enabled)) \
		and (not bool(wave_director.tower_aggro_enabled))


## 开局：由 `WaveDirector` 发出第一波的 `wave_started`
func start_run(w: int = 1) -> void:
	if wave_director != null:
		wave_director.start_run(w)
		return
	if director != null:
		director.wave_start(w)


# ---------------------------------------------------------------------------
#  广播（UI 订阅后只读 `runtime.snapshot()`）
# ---------------------------------------------------------------------------
func _emit_shop() -> void:
	emit_signal("shop_changed")


func _emit_run() -> void:
	emit_signal("run_changed")
