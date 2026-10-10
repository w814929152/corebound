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
## 🔴 收入口径（第四刀 proto-elite-golive 裁决 #2 · 改接实时结果）：
##    `_pending_result` 仍由金标本 `WaveSim.simulate_wave()` 在**波首**结算（R1：
##    本波打的是上波买出来的构筑）—— 但 `_on_wave_ended` 现**直接授予实时结果**
##    （`last_realtime_result`，与实机战斗同源），仅当实时结果缺失/波次不匹配才回落
##    `_pending_result`。三原型/Elite 开启时不再回落金标本、不再打印 `[WARN]`
##    → 「打的」与「算钱的」一致。🔴 MC 判据链不受影响（它走 `RunLoop`）。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 本文件**不写 `class_name`**，一律 preload。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _SalvageDialog := preload("res://scripts/ui/salvage_confirm_dialog.gd")
## 🔒 T1 修复入口：多塔处置弹窗（Disabled 塔三选一：修复/被动拆除/放着不管）
const _DisabledTowerDialog := preload("res://scripts/ui/disabled_tower_dialog.gd")
## 🟢 切片8续3（可玩 MVP）：一局结算覆盖层（胜负展示 + 重开/退出）
const _ResultOverlay := preload("res://scripts/ui/result_overlay.gd")

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
	# 🟡 切片8：把时钟权威注入 runtime，供重决策入口（salvage/discard/unequip）做 SafeWindow 守卫
	if runtime != null:
		runtime.director = d
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
	#  salvage_requested：切片8 拆除回收结算器 + I-9 二次确认弹窗
	if not d.is_connected("salvage_requested", _on_salvage_requested):
		d.salvage_requested.connect(_on_salvage_requested)
	# 🔒 T1 修复入口：重决策面板「处置受损塔」→ 多塔处置弹窗（修复/被动拆除/放着不管）
	if not d.is_connected("repair_requested", _on_repair_requested):
		d.repair_requested.connect(_on_repair_requested)
	#  I-7 塔位点选：MonsterLayer 点击塔 → runtime.select_tower
	if not d.is_connected("tower_select_requested", _on_tower_select_requested):
		d.tower_select_requested.connect(_on_tower_select_requested)


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
	# 🟢 切片8续3（可玩 MVP）：通关胜利信号
	if not wd.is_connected("run_won", _on_run_won):
		wd.run_won.connect(_on_run_won)
	if runtime != null:
		wd.bind_runtime(runtime)


func _on_wave_result(_w: int, res: Dictionary) -> void:
	last_realtime_result = res.duplicate()


func _on_run_lost(p_w: int) -> void:
	over = true
	print("[shop_controller] 核心 HP 归零（W%d）→ 停止推进（E-W3 立即失败）" % p_w)
	_emit_run()
	_show_result(false, p_w)


func _on_run_won(p_w: int) -> void:
	over = true
	print("[shop_controller] 通关胜利（打完 W%d 且核心未归零）" % p_w)
	_emit_run()
	_show_result(true, p_w)


## 🟢 切片8续3（可玩 MVP）：挂结算覆盖层（幂等——一局只弹一次，因为 over 已置位）。
func _show_result(p_won: bool, p_wave: int) -> void:
	if runtime == null:
		return
	var hp := float(runtime.player.core_hp) if runtime.player != null else 0.0
	var hp_max := float(runtime.player.core_hp_max) if runtime.player != null else 0.0
	var scrap := float(runtime.scrap)
	var ov = _ResultOverlay.new()
	add_child(ov)
	# 🔴 结算期间世界保持 paused（覆盖层 process_mode=ALWAYS 仍可点按钮）；
	#   重开 → 重新走 start_run；退出 → 退出场景树（headless 下仅打印）。
	ov.show_result(p_won, p_wave, hp, hp_max, scrap,
		Callable(self, "_on_restart_requested"), Callable(self, "_on_quit_requested"))


func _on_restart_requested() -> void:
	# 重开一局：复位 over → runtime 重建（清 scrap/core_hp/构筑/待放置）→
	#   刷新 WaveDirector 的 player 引用（setup 会 new_player）→ 重新开波 W1。
	over = false
	if runtime != null:
		runtime.setup("B", DEFAULT_RUN_SEED)
	if wave_director != null:
		wave_director.bind_runtime(runtime)   # 刷新 player / core_hp 引用
	_emit_run()
	print("[shop_controller] 再来一局 → 重新开波 W1")
	start_run(1)


func _on_quit_requested() -> void:
	print("[shop_controller] 退出本局（headless 下仅记录；图形端可 get_tree().quit()）")


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


## 🟡 切片8·I-7：战场塔位点选接线（MonsterLayer 点击塔 → runtime.select_tower）。
##   🔴 纯接线：改的是 runtime 的**点选状态**（UI 侧临时选择），不改构筑数值；
##      点选后 reinforce 卡的宿主由 `_reinforce_host()` 决定（点选合法→该塔，否则→主塔）。
func _on_tower_select_requested(slot: int) -> void:
	if runtime == null:
		return
	if runtime.select_tower(slot):
		print("[shop_controller] 点选塔位 %d（reinforce 将投此塔，若 Tag 合法）" % slot)
		_emit_shop()


func _on_salvage_requested() -> void:
	# 切片8 · 拆除回收 `Salvage`（I-9 二次确认弹窗，Q-C3 原文 / E8 / E15）
	if runtime == null:
		return
	# 🟡 MVP：salvage_requested 无参（I-7 塔位点选随 D-9 后续切片）→ 目标取**主塔**
	#    （与 reinforce 恒投 core_tower_slot 同口径）。有塔才可拆。
	var slot: int = runtime.core_tower_slot()
	if slot < 0:
		runtime.last_error = "场上无塔可拆除"
		_emit_shop()
		return
	var prev: Dictionary = runtime.preview_salvage(slot)
	if not bool(prev["ok"]):
		runtime.last_error = String(prev["reason"])
		_emit_shop()
		return
	# 🔴 I-9 二次确认弹窗（CanvasLayer 140，自定义 Control，禁 AcceptDialog）
	_show_salvage_confirm(slot, prev)


## 组装 I-9 弹窗文案（E8 确认项：返还 X 分 / 销毁 N 张（M 层）/ κ 不回升）并挂确认回调。
func _show_salvage_confirm(slot: int, prev: Dictionary) -> void:
	var dlg = _SalvageDialog.new()
	add_child(dlg)
	var body := "塔位 %d · 累计投入 %.0f 分\n返还 %.0f 分（50%%，向下取整）\n销毁 %d 张卡（共 %d 层）\nκ 不回升（兜底①，E11）" % [
		slot, float(prev["invested"]), float(prev["refund"]),
		int(prev["cards_destroyed"]), int(prev["layers_destroyed"])]
	# 🔴 E15：弹窗打开时世界仍 paused（dialog process_mode=ALWAYS，不解除暂停）
	dlg.show_confirm("拆除并回收 Salvage？", body, func() -> void:
		var res: Dictionary = runtime.salvage_tower(slot)
		if bool(res["ok"]):
			print("[shop_controller] 拆除塔位 %d：返还 %.0f 分 / 销毁 %d 张（%d 层）"
				% [slot, float(res["refund"]), int(res["cards_destroyed"]), int(res["layers_destroyed"])])
		else:
			runtime.last_error = String(res["reason"])
		_emit_shop()
		_emit_run()
	)


# ---------------------------------------------------------------------------
#  🔒 T1 修复入口（Q-T4 三选一 · E-T2 多塔列表 · E-T4 永不死锁）
# ---------------------------------------------------------------------------
## 「处置受损塔」按钮 → 读 list_disabled_towers() 组装多塔处置弹窗。
func _on_repair_requested() -> void:
	if runtime == null:
		return
	var rows: Array = runtime.list_disabled_towers()
	if rows.is_empty():
		runtime.last_error = "当前没有受损塔需要处置"
		_emit_shop()
		return
	_show_repair_dialog(rows)


## 组装多塔处置弹窗（E-T2：每座一行三选一）。
##   🔴 每座预计算 `can_repair`（积分是否够修），供弹窗置灰「修复」按钮（E-T4）。
##   🔴 E15：弹窗打开时世界仍 paused（dialog process_mode=ALWAYS，不解除暂停）。
func _show_repair_dialog(rows: Array) -> void:
	var dlg = _DisabledTowerDialog.new()
	add_child(dlg)
	# 组装行数据：加 can_repair 布尔（积分够不够修这一座）
	var scrap_now := float(runtime.scrap)
	var prepared: Array = []
	for row in rows:
		prepared.append({
			"slot": int(row["slot"]),
			"invested": float(row["invested"]),
			"repair_cost": int(row["repair_cost"]),
			"attach_layers": int(row["attach_layers"]),
			"can_repair": scrap_now >= float(row["repair_cost"]),
		})
	# 玩家点「修复」→ 结算 + 刷新剩余受损塔列表（可能修好后列表变短/空）
	dlg.tower_repair_requested.connect(func(slot: int) -> void:
		var res: Dictionary = runtime.repair_tower(slot)
		if bool(res["ok"]):
			print("[shop_controller] 修复塔位 %d：花 %.0f 分回满 HP（保留装配卡）"
				% [slot, float(res["cost"])])
		else:
			runtime.last_error = String(res["reason"])
		_emit_shop()
		_emit_run()
		# 重算剩余受损塔 → 刷新弹窗（空则自动关闭）
		dlg.refresh(_remaining_disabled_rows())
	)
	# 玩家点「被动拆除」→ 结算 + 刷新剩余列表
	dlg.tower_salvage_requested.connect(func(slot: int) -> void:
		var res: Dictionary = runtime.salvage_disabled_tower(slot)
		if bool(res["ok"]):
			print("[shop_controller] 被动拆除塔位 %d：销毁 %d 张卡（%d 层）· 返还 0%%"
				% [slot, int(res["cards_destroyed"]), int(res["layers_destroyed"])])
		else:
			runtime.last_error = String(res["reason"])
		_emit_shop()
		_emit_run()
		dlg.refresh(_remaining_disabled_rows())
	)
	# 「放着不管」/ 关闭 → 释放弹窗（no-op；下次安全窗仍在）
	dlg.closed.connect(func() -> void:
		dlg.queue_free()
	)
	dlg.show_towers(prepared)


## 🔴 只读：重算当前剩余受损塔的弹窗行数据（某座修复/拆除后供 refresh 用）。
func _remaining_disabled_rows() -> Array:
	if runtime == null:
		return []
	return runtime.list_disabled_towers()


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
	# 🔴 第四刀（proto-elite-golive 裁决 #2）：收入**直接接实时结果**（与实机战斗产出一致）。
	#    去回落、去 WARN —— 三原型/Elite 开启时不再把收入回落金标本口径。仅当实时结果为空
	#    或波次不匹配（异常路径：本波实时结算缺失）才回落 `_pending_result`（波首金标本结算）。
	if int(rt.get("w", -1)) == w:
		res = rt
	runtime.grant_wave_result(res)   # R3：击杀收入 × (1 + income_mult)
	# 🔴 切片8续3：核心 HP 单一数据源 → 读 player.core_hp（实时战斗已在漏怪当刻扣好）。
	#   失败判定主路由是 WaveDirector.run_lost → _on_run_lost（E-W3 实时）；此处仅作兜底。
	if runtime.player != null and float(runtime.player.core_hp) <= 0.0 and not over:
		over = true
		print("[shop_controller] 核心 HP 归零（W%d）→ 停止推进" % w)
	_emit_shop()
	_emit_run()


## 🟡 金标本等价口径判定（**保留作参考谓词，不再作为收入闸门**）。
##    第四刀（proto-elite-golive 裁决 #2）后，`_on_wave_ended` 已改为**直接接实时结果**
##    → 本函数不再是入账路径的一部分；保留仅为「实时结果是否与 `WaveSim` 逐位等价」的诊断用途。
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
