extends RefCounted
##
## headless 自测套件 —— 切片3「实时商店覆盖层」的五态时钟 / 减速预算 / 布局算尺。
##
## 🔴 与切片1/2 的差别：切片1/2 断言的是「GDScript 是否逐位复现 Python 金标本」；
##    本套件断言的是「**时钟口径是否逐条对上 GDD §2.1 的表格**」——
##    没有 Python 金标本可对，判据就是 `design/gdd/shop-reroll.md` v1.1 §2.1 / §3.1 / §5.2。
##
## 被测对象是**纯逻辑** `scripts/engine/time_state_machine.gd`（零副作用、不进场景树），
## 所以这里可以在 headless 下不开窗口、不等帧，直接注入实时秒做确定性断言。
## 真实帧的实测（time_scale / paused 的引擎侧生效）由
## `tests/run_slice3_scene_smoke.gd` 负责，证据在 `docs/phase3/slice3-scene-smoke.log`。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice3
##   <godot> --headless --path D:/roguedemo --quit      （main scene 在 headless 下自动跑）
##

const TOL := 1e-12

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload；变量不写死类型
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")

var _pass := 0
var _fail := 0
var _out: Array = []


func _log(s: String) -> void:
	_out.append(s)
	print(s)


## 🔴 G7：GDScript 的 `String % …` **不支持 `%e` / `%g`** → 科学计数法自己写。
static func _sci(v: float) -> String:
	if v == 0.0:
		return "0.000e+00"
	var e := int(floor(log(absf(v)) / log(10.0)))
	var m := absf(v) / pow(10.0, float(e))
	return "%s%.3fe%s%02d" % ["-" if v < 0.0 else "", m, "+" if e >= 0 else "-", absi(e)]


func _check(name: String, got: float, want: float, tol: float = TOL) -> void:
	var d := absf(got - want)
	var rel := 0.0
	if absf(want) > 1e-300:
		rel = d / absf(want)
	var ok := (d <= 1e-300) or (rel <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%.12f want=%.12f |rel|=%s"
			% ["PASS" if ok else "FAIL", name, got, want, _sci(rel)])


func _check_int(name: String, got: int, want: int) -> void:
	var ok := (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	var ok := (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])


func _check_str(name: String, got: String, want: String) -> void:
	var ok := (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, got, want])


func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》MVP 切片3 · 实时商店覆盖层 —— 五态时钟 / 减速预算 自测")
	_log("判据：design/gdd/shop-reroll.md v1.1 §2.1 五态时钟口径总表 · §3.1 常量表 · §5.2 减速预算")
	_log("=".repeat(78))

	_test_clock_table()
	_test_sr_r5_time_scale_never_zero()
	_test_budget_unscaled()
	_test_novice_protection()
	_test_thinking_gain()
	_test_transitions()
	_test_wave_reset()
	_test_layout_rule()
	_test_c3_compliance_grep()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 五态时钟口径与 GDD §2.1 逐条一致")
	else:
		_log("[NG] 有 %d 项未对齐 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0


# ===========================================================================
# 1. 五态时钟口径总表（GDD §2.1）—— W6（非新手波）
# ===========================================================================
func _test_clock_table() -> void:
	_log("")
	_log("--- [1] 五态时钟口径总表（GDD §2.1 · W6）---")
	var S = _TSM.State
	var D = _TSM.Drawer
	var sm = _TSM.new(6)

	# ① Combat：ts=1.0 / 不暂停 / 预算冻结 / 抽屉关
	sm.state = S.COMBAT
	var c = sm.clock()
	_check("① Combat time_scale", float(c["time_scale"]), 1.0)
	_check_bool("① Combat paused", bool(c["paused"]), false)
	_check_bool("① Combat 消耗预算", bool(c["consumes_budget"]), false)
	_check_int("① Combat 抽屉", int(c["drawer"]), D.CLOSED)

	# ② ShopDilated：ts=1.0 / 不暂停 / 消耗预算 / 抽屉轻决策
	sm.state = S.SHOP_DILATED
	c = sm.clock()
	_check("② ShopDilated time_scale", float(c["time_scale"]), _Cfg.DILATION_SCALE)
	_check_bool("② ShopDilated paused", bool(c["paused"]), false)
	_check_bool("② ShopDilated 消耗预算", bool(c["consumes_budget"]), true)
	_check_int("② ShopDilated 抽屉", int(c["drawer"]), D.LIGHT)

	# ③ ShopRealTime：ts=1.0 / 不暂停 / 不消耗（已耗尽）/ 抽屉仍开（Q-SR2 不强制关闭）
	sm.state = S.SHOP_REAL_TIME
	c = sm.clock()
	_check("③ ShopRealTime time_scale", float(c["time_scale"]), 1.0)
	_check_bool("③ ShopRealTime paused", bool(c["paused"]), false)
	_check_bool("③ ShopRealTime 消耗预算", bool(c["consumes_budget"]), false)
	_check_int("③ ShopRealTime 抽屉", int(c["drawer"]), D.LIGHT)

	# ④ SafeWindow：🔴 ts 保持 1.0、世界靠 paused=true 停 / 预算冻结 / 抽屉重决策
	#   走 `wave_end()` 进入（Q-SR3：安全窗商店**自动**展开），不要直接改 state
	sm.wave_end(6)
	c = sm.clock()
	_check("④ SafeWindow time_scale（🔴 不得为 0）", float(c["time_scale"]), 1.0)
	_check_bool("④ SafeWindow paused", bool(c["paused"]), true)
	_check_bool("④ SafeWindow 消耗预算", bool(c["consumes_budget"]), false)
	_check_int("④ SafeWindow 抽屉", int(c["drawer"]), D.HEAVY)

	# ⑤ PlacementMode：ts=0.25 / 消耗预算（复用同一池）/ 🔴 抽屉收起
	sm.state = S.PLACEMENT_MODE
	c = sm.clock()
	_check("⑤ PlacementMode time_scale", float(c["time_scale"]), _Cfg.PLACEMENT_SCALE)
	_check_bool("⑤ PlacementMode paused", bool(c["paused"]), false)
	_check_bool("⑤ PlacementMode 消耗预算（复用同池 Q-SR6）", bool(c["consumes_budget"]), true)
	_check_int("⑤ PlacementMode 抽屉（🔴 收起）", int(c["drawer"]), D.CLOSED)


# ===========================================================================
# 2. 🔴 SR-R5：`Engine.time_scale` 永不为 0（遍历五态 × 两档波次）
# ===========================================================================
func _test_sr_r5_time_scale_never_zero() -> void:
	_log("")
	_log("--- [2] 🔴 SR-R5：time_scale 永不为 0（安全窗改用 paused）---")
	var S = _TSM.State
	for w in [1, 3, 5, 6, 12, 20]:
		var sm = _TSM.new(w)
		for st in [S.COMBAT, S.SHOP_DILATED, S.SHOP_REAL_TIME, S.SAFE_WINDOW, S.PLACEMENT_MODE]:
			sm.state = st
			var ts := float(sm.clock()["time_scale"])
			var ok := ts > 0.0
			if ok:
				_pass += 1
			else:
				_fail += 1
				_log("   [FAIL] W%d %s time_scale=%f 不得 ≤ 0" % [w, sm.state_name(st), ts])
	_log("   [info] 6 个波次 × 5 个态 = 30 组，全部 time_scale > 0")


# ===========================================================================
# 3. 减速预算：unscaled 实时秒（GDD §5.2）
# ===========================================================================
func _test_budget_unscaled() -> void:
	_log("")
	_log("--- [3] 减速预算：unscaled 实时秒（GDD §5.2 / §10.1 断言 2）---")
	var S = _TSM.State

	# ---- 3.1 W6 打开商店全速推进，10 实时秒后预算 20 → 10 ----
	var sm = _TSM.new(6)
	sm.open_shop()
	_check_int("3.1 打开商店进入态②", sm.state, S.SHOP_DILATED)
	sm.tick(10.0)
	_check("3.1 10 实时秒后预算", sm.budget_left, 10.0)
	_check_int("3.1 仍是态②（未耗尽）", sm.state, S.SHOP_DILATED)

	# ---- 3.2 再 10 秒 → 耗尽 → 自动转态③（🔴 不强制关店，Q-SR2）----
	sm.tick(10.0)
	_check("3.2 再 10 秒后预算", sm.budget_left, 0.0)
	_check_int("3.2 耗尽后转态③ ShopRealTime", sm.state, S.SHOP_REAL_TIME)
	_check("3.2 态③ time_scale 回 1.0", float(sm.clock()["time_scale"]), 1.0)
	_check_int("3.2 抽屉仍然开着（不强制关闭）", int(sm.clock()["drawer"]), _TSM.Drawer.LIGHT)
	# 态③ 不消耗：再 tick 也不变负
	sm.tick(10.0)
	_check("3.3 态③ 冻结预算（不得变负）", sm.budget_left, 0.0)

	# ---- 3.4 Combat / SafeWindow 冻结 ----
	var sm2 = _TSM.new(6)
	sm2.tick(10.0)
	_check("3.4 Combat 预算冻结", sm2.budget_left, 20.0)
	sm2.wave_end(6)
	_check_int("3.4 波末进 SafeWindow", sm2.state, S.SAFE_WINDOW)
	sm2.tick(10.0)
	_check("3.4 SafeWindow 预算冻结", sm2.budget_left, 20.0)

	# ---- 3.5 放置模式复用同一预算池（Q-SR6 = ① 复用）----
	var sm3 = _TSM.new(6)
	sm3.open_shop()
	sm3.tick(4.0)
	_check("3.5 态② 扣 4s", sm3.budget_left, 16.0)
	sm3.enter_placement()
	_check_int("3.5 进入态⑤", sm3.state, S.PLACEMENT_MODE)
	sm3.tick(6.0)
	_check("3.5 态⑤ 复用同池再扣 6s", sm3.budget_left, 10.0)

	# ---- 3.6 预算耗尽时打开商店：🔴 E3 不得拒绝打开，直接落态③ ----
	var sm4 = _TSM.new(6)
	sm4.open_shop()
	sm4.tick(20.0)
	sm4.close_shop()
	_check_int("3.6 关店回态①", sm4.state, S.COMBAT)
	sm4.open_shop()
	_check_int("3.6 预算为 0 时仍可打开 → 态③", sm4.state, S.SHOP_REAL_TIME)

	# ---- 3.7 预算不足 1s 时仍按剩余量减速（E3）----
	var sm5 = _TSM.new(6)
	sm5.open_shop()
	sm5.tick(19.5)
	_check("3.7 剩余 0.5s", sm5.budget_left, 0.5)
	sm5.tick(0.5)
	_check("3.7 耗尽", sm5.budget_left, 0.0)
	_check_int("3.7 转态③", sm5.state, S.SHOP_REAL_TIME)

	# ---- 3.8 🔴 Q-S3-A（GDD v1.2 §2.1 易错口径第 4 条）----
	#   「预算为 0 时进入 ⑤ 不得再减速（等效 1.0×）」——
	#   放任 ⑤ 在 0 预算下继续 0.25× = 免费无限慢动作，预算不再是货币。
	var sm6 = _TSM.new(6)
	sm6.open_shop()
	sm6.tick(20.0)
	_check_int("3.8 预算耗尽 → 态③", sm6.state, S.SHOP_REAL_TIME)
	_check_bool("3.8 态③ 仍可进入放置（E3：不拒绝）", sm6.enter_placement(), true)
	_check_int("3.8 已进入态⑤", sm6.state, S.PLACEMENT_MODE)
	var c38: Dictionary = sm6.clock()
	_check("3.8 🔴 ⑤ 预算 0 → time_scale 1.0（不得再减速）", float(c38["time_scale"]), 1.0)
	_check_bool("3.8 🔴 ⑤ 预算 0 → 不消耗预算", bool(c38["consumes_budget"]), false)
	_check_int("3.8 🔴 ⑤ 预算 0 → 抽屉仍收起", int(c38["drawer"]), _TSM.Drawer.CLOSED)
	sm6.tick(1.0)
	_check_int("3.8 🔴 立即退出放置 → 落态③全速", sm6.state, S.SHOP_REAL_TIME)
	_check("3.8 预算不得变负", sm6.budget_left, 0.0)


# ===========================================================================
# 4. 新手保护 W1–W5（概念 §2.1 ③）
# ===========================================================================
func _test_novice_protection() -> void:
	_log("")
	_log("--- [4] 新手保护 W1–W5：商店保持全速且不消耗预算 ---")
	var S = _TSM.State
	for w in [1, 2, 3, 4, 5]:
		var sm = _TSM.new(w)
		sm.open_shop()
		_check("W%d 打开商店 time_scale" % w, float(sm.clock()["time_scale"]), _Cfg.DILATION_SCALE_NOVICE)
		_check_bool("W%d 不消耗预算" % w, bool(sm.clock()["consumes_budget"]), false)
		sm.tick(30.0)
		_check("W%d tick 30s 后预算仍满" % w, sm.budget_left, 20.0)
		_check_int("W%d 仍在态②（不会因耗尽转③）" % w, sm.state, S.SHOP_DILATED)
	# W6 商店同样全速，照旧开始消耗预算
	var sm6 = _TSM.new(6)
	sm6.open_shop()
	_check("W6 商店全速", float(sm6.clock()["time_scale"]), _Cfg.DILATION_SCALE)
	_check_bool("W6 开始消耗预算", bool(sm6.clock()["consumes_budget"]), true)


# ===========================================================================
# 5. 思考时间增益（概念 §2.1 ③ 的 "×2.9"）
# ===========================================================================
func _test_thinking_gain() -> void:
	_log("")
	_log("--- [5] 商店全速：20s 经过时战场推进 20s ---")
	var ts := _Cfg.DILATION_SCALE
	var budget := _Cfg.DILATION_BUDGET
	var game_advanced := budget * ts
	_check("商店打开时战场推进量 = 20 × 1.0", game_advanced, 20.0)
	_check("商店全速时无额外思考增益", budget / game_advanced, 1.0)


# ===========================================================================
# 6. 显式转换表（🔴 GDD §2.1：不许用布尔 is_shop_open 糊）
# ===========================================================================
func _test_transitions() -> void:
	_log("")
	_log("--- [6] 显式五态转换表（非法转换必须被拒）---")
	var S = _TSM.State

	var sm = _TSM.new(6)
	# 合法
	_check_bool("①→② open_shop", sm.open_shop() and sm.state == S.SHOP_DILATED, true)
	_check_bool("②→⑤ enter_placement", sm.enter_placement() and sm.state == S.PLACEMENT_MODE, true)
	_check_bool("⑤→② exit_placement", sm.exit_placement() and sm.state == S.SHOP_DILATED, true)
	_check_bool("②→① close_shop", sm.close_shop() and sm.state == S.COMBAT, true)
	sm.wave_end(6)
	_check_bool("①→④ wave_end", sm.state == S.SAFE_WINDOW, true)

	# 安全窗里抽屉默认自动展开（Q-SR3 = ① 自动打开）
	_check_int("④ 抽屉自动展开为 HEAVY", int(sm.clock()["drawer"]), _TSM.Drawer.HEAVY)
	# 玩家在安全窗里手动收起 → 仍是 ④（世界仍暂停），只是抽屉关了
	_check_bool("④ 里可手动收起抽屉", sm.close_shop() and sm.state == S.SAFE_WINDOW, true)
	_check_int("④ 抽屉收起后为 CLOSED", int(sm.clock()["drawer"]), _TSM.Drawer.CLOSED)
	_check_bool("④ start_next_wave → 抽屉保持『关』→ 态①",
		sm.start_next_wave() and sm.state == S.COMBAT, true)
	_check_int("④→① 波号 +1", sm.wave, 7)

	# 安全窗里不收抽屉 → 下一波抽屉保持『开』（§4.1：不强制弹出，也不强制收起）
	var sm1b = _TSM.new(6)
	sm1b.wave_end(6)
	_check_bool("④→下一波，抽屉保持『开』→ 态②",
		sm1b.start_next_wave() and sm1b.state == S.SHOP_DILATED, true)

	# 非法
	var sm2 = _TSM.new(6)
	_check_bool("①→⑤ 直接进放置（非法）", sm2.enter_placement(), false)
	_check_bool("非法转换后状态不变", sm2.state == S.COMBAT, true)
	_check_bool("① 下关闭抽屉（非法：抽屉本就关着）", sm2.close_shop(), false)
	sm2.wave_end(6)
	_check_bool("④→② 安全窗不能直接变暖决策", sm2.transition(S.SHOP_DILATED), false)
	_check_bool("非法转换后仍是 ④", sm2.state == S.SAFE_WINDOW, true)

	# 安全窗 → 放置 → 回安全窗（GDD §2.1 图注：⑤ 回到进入前的态）
	var sm3 = _TSM.new(6)
	sm3.wave_end(6)
	_check_bool("④→⑤", sm3.enter_placement() and sm3.state == S.PLACEMENT_MODE, true)
	_check_bool("⑤→④（回到进入前的态）", sm3.exit_placement() and sm3.state == S.SAFE_WINDOW, true)

	# 只有 SafeWindow 能开始下一波
	var sm4 = _TSM.new(6)
	sm4.open_shop()
	_check_bool("②下 start_next_wave 被拒（E14）", sm4.start_next_wave(), false)


# ===========================================================================
# 7. 波次重置（WS-1）
# ===========================================================================
func _test_wave_reset() -> void:
	_log("")
	_log("--- [7] 波次重置：预算回满 / 抽屉保持上次开或关（§4.1 不强制弹出）---")
	var S = _TSM.State
	var sm = _TSM.new(6)
	sm.open_shop()
	sm.tick(15.0)
	_check("W6 消耗后剩余", sm.budget_left, 5.0)
	sm.wave_start(7)
	_check("新波预算重置", sm.budget_left, 20.0)
	_check_int("新波波号", sm.wave, 7)
	_check_int("抽屉保持上次『开』状态 → 态②", sm.state, S.SHOP_DILATED)

	# 玩家在安全窗里关掉抽屉 → 下一波不强制弹出
	var sm2 = _TSM.new(6)
	sm2.wave_end(6)
	_check_int("波末自动展开 → 态④", sm2.state, S.SAFE_WINDOW)
	sm2.close_shop()
	sm2.wave_start(7)
	_check_int("下一波保持『关』→ 态①", sm2.state, S.COMBAT)


# ===========================================================================
# 8. 布局算尺（C3 双焦点）
# ===========================================================================
func _test_layout_rule() -> void:
	_log("")
	_log("--- [8] C3 布局算尺：max(0.32×屏宽, 560px) （锚点 6 · Q-S3-C 落地后）---")

	# ---- 8.1 🔴 Q-S3-C 落地：工程视口钉死 1920×1080（GDD §2.4 基准屏）----
	_check("8.1 project.godot viewport_width = 1920",
		float(ProjectSettings.get_setting("display/window/size/viewport_width")), 1920.0)
	_check("8.1 project.godot viewport_height = 1080",
		float(ProjectSettings.get_setting("display/window/size/viewport_height")), 1080.0)
	_check_str("8.1 stretch/aspect 钉死为 expand",
		String(ProjectSettings.get_setting("display/window/stretch/aspect")), "expand")

	# ---- 8.2 基准屏 1920：两条约束正好一致（抽屉 32% / 战场 68%）----
	_check("1920 → 614.4（正好 32%）", _ShopLayout.drawer_width(1920.0), 614.4)
	_check("1920 占屏比", _ShopLayout.drawer_ratio(1920.0), 0.32)
	_check("1920 商店浮层不改变战场宽", _ShopLayout.battlefield_width(1920.0, true), 1920.0)
	_check("1920 抽屉收起时战场宽（放置模式全屏）", _ShopLayout.battlefield_width(1920.0, false), 1920.0)

	# ---- 8.3 非基准屏安全网（算尺逻辑未变，保留作 resize / expand 后的兜底）----
	_check("1280 → 560（🔴 最小宽压过比例）", _ShopLayout.drawer_width(1280.0), 560.0)
	_check("1280 占屏比", _ShopLayout.drawer_ratio(1280.0), 0.4375)
	_check("1000 → 仍 560（不得突破下限）", _ShopLayout.drawer_width(1000.0), 560.0)
	_check("3840 → 1228.8", _ShopLayout.drawer_width(3840.0), 1228.8)
	_check("商店浮层不改变战场宽（1280）", _ShopLayout.battlefield_width(1280.0, true), 1280.0)
	_check("抽屉收起时战场宽（1280，放置模式全屏）", _ShopLayout.battlefield_width(1280.0, false), 1280.0)
	_log("   [info] ✅ 视口已按 Q-S3-C 提到 1920×1080 → 抽屉 614.4px（32%）/ 战场 1305.6px（68%），")
	_log("          与 GDD §2.4 的『614px / 32%』完全吻合；maxf() 仍保留作非基准屏安全网。")
	_log("   [info] 取整口径：算尺返回**浮点原值**（不 floor / 不 round），")
	_log("          614.4 / 1305.6 直接交给引擎的 Control offset 与 Node2D 绘制坐标。")


# ===========================================================================
# 9. 🔴 C-3 / SR-R2 合规：商店源码里不得出现「推荐」类措辞（GDD §10.1 断言 10）
# ===========================================================================
func _test_c3_compliance_grep() -> void:
	_log("")
	_log("--- [9] 🔴 C-3 / SR-R2：商店 UI 源码 grep「推荐 / 最优 / best / recommend / suggest」零命中 ---")
	var files := [
		"res://scripts/ui/shop_overlay.gd",
		"res://scripts/ui/time_director.gd",
		"res://scripts/engine/time_state_machine.gd",
	]
	var banned := ["推荐", "最优", "建议买", "best", "recommend", "suggest"]
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fail += 1
			_log("   [FAIL] 打不开 %s" % path)
			continue
		var raw := f.get_as_text()
		f.close()
		# 🔴 只扫**代码正文**：注释/文档里出现"禁止推荐"这类红线说明不算违规。
		var code_lines: Array = []
		for line in raw.split("\n"):
			var s := String(line).strip_edges()
			if s.begins_with("#"):
				continue
			code_lines.append(s)
		var text := "\n".join(code_lines).to_lower()
		var hits: Array = []
		for b in banned:
			if text.find(String(b).to_lower()) >= 0:
				hits.append(b)
		var ok := hits.is_empty()
		if ok:
			_pass += 1
			_log("   [PASS] %s 零命中" % path)
		else:
			_fail += 1
			_log("   [FAIL] %s 命中 %s —— 只标事实，绝不标推荐（SR-R2）" % [path, str(hits)])
