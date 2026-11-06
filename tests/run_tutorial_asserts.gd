extends RefCounted
##
## headless 断言 —— B-1 零教学浮层（`scripts/ui/tutorial_overlay.gd`）
##
## 规格：`docs/phase6/b1-tutorial-spec.md` §9「headless 断言（状态机可测，不依赖绘制）」
##
## 🔴 被测面只有 `advance_with(S, W)` 这一个**纯函数式入口**：
##    两个入参就是 `runtime.snapshot()` 与 `wave_director.snapshot()` 的**字典子集**，
##    不装载场景、不建树、不渲染 ⇒ headless 可跑、秒级完成。
##
## 🔴 **实测口径修正（2026-11-06 · 探针 `probe_tutorial_visible`）**：
##    实机开局状态**不是**"空手 W1 未开波"，而是：
##      · W1 已由 `start_run(1)` 自动开波（`wave_director.state = SPAWNING`）；
##      · 玩家自带 1 座塔 + 1 张卡（`towers=1 / cards=1`）。
##    因此四步判定一律改成「比**进入本步时**多了什么」的相对基线，而非绝对阈值；
##    否则首帧就会 BUY→PLACE→RUN→REPAIR 一路级联、引导根本来不及显示。
##
## 🔴 断言口径：
##    A0 初始态 OFF（未轮询前不显示任何东西）
##    A1 开局快照（自带 1 塔 1 卡）→ 停在 BUY（不因"有塔有卡"误判为已买）
##    A2 `pending` 非空 → PLACE；卡没落地（塔数不变）→ 维持 PLACE
##    A3 塔数 +1（落子成功）→ RUN
##    A4 波次未前进（W1 是自动开的）→ 维持 RUN；波次 +1 → REPAIR
##    A5 REPAIR 且无受损塔 → 停在本步（不因"空 REPAIR"直接 DONE）
##    A6 出现 `disabled` → 记下"见过"，清空后 → DONE
##    A7 跳过 → 立即 DONE，且后续快照不再推进
##    A8 兜底：过 W8 且全程无受损塔（打得干净）→ 自动 DONE
##    A9 单向性：DONE / REPAIR 后回喂"会推进"的快照，步数不回退
##
## 跑法：
##   <godot> --headless --path . --script res://tests/run_tests.gd -- tutorial
##

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _Tut := preload("res://scripts/ui/tutorial_overlay.gd")

var _pass := 0
var _fail := 0


func _log(s: String) -> void:
	print(s)


func _check_int(name: String, got: int, want: int) -> void:
	var ok := got == want
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	var ok := got == want
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])


# ---------------------------------------------------------------------------
#  快照构造器（模拟 `runtime.snapshot()` / `wave_director.snapshot()` 的相关子集）
# ---------------------------------------------------------------------------
## `disabled` = 各塔位的受损标记数组（长度不限，按 slots 逐项读）。
func _S(towers: int = 1, pending: int = 0, cards: int = 1,
		disabled: Array = [], wave: int = 1) -> Dictionary:
	var slots: Array = []
	for i in range(disabled.size()):
		slots.append({"slot": i, "disabled": bool(disabled[i])})
	return {
		"wave": wave,
		"towers": towers,
		"pending": range(pending),
		"cards": cards,
		"slots": slots,
	}


func _W(w: int = 1, state: int = 1) -> Dictionary:
	# state 默认 1 = SPAWNING（开局 W1 已自动开波的真实口径）
	return {"state": state, "w": w}


# ---------------------------------------------------------------------------
#  用例
# ---------------------------------------------------------------------------
func _test_a0_a1_initial() -> void:
	_log("[A0/A1] 初始态与首帧停在 BUY")
	var t = _Tut.new()
	_check_int("A0 未轮询前 step", int(t.step), int(_Tut.Step.OFF))
	# 开局真实口径：自带 1 塔 1 卡、W1 已开波
	t.advance_with(_S(1, 0, 1), _W(1))
	_check_int("A1 开局快照 → 停在 BUY", int(t.step), int(_Tut.Step.BUY))
	t.advance_with(_S(1, 0, 1), _W(1))
	_check_int("A1b 反复轮询仍 BUY", int(t.step), int(_Tut.Step.BUY))
	t.free()


func _test_a2_a3_buy_place() -> void:
	_log("[A2/A3] 买 → 放 的两段式")
	var t = _Tut.new()
	t.advance_with(_S(1, 0, 1), _W(1))
	# 买了建筑卡（入 pending），但还没落地 → 必须停 PLACE
	t.advance_with(_S(1, 1, 1), _W(1))
	_check_int("A2 pending 非空 → PLACE", int(t.step), int(_Tut.Step.PLACE))
	# 仍没落地（塔数没变）→ 保持 PLACE（不回退、不误进 RUN）
	t.advance_with(_S(1, 1, 1), _W(1))
	_check_int("A2b 持续未落地 → 仍 PLACE", int(t.step), int(_Tut.Step.PLACE))
	# 再买一张仍未落地 → 仍 PLACE
	t.advance_with(_S(1, 2, 1), _W(1))
	_check_int("A2c 再买一张仍未落地 → 仍 PLACE", int(t.step), int(_Tut.Step.PLACE))
	# 塔落地（1 → 2）→ 越过 PLACE 进 RUN
	t.advance_with(_S(2, 1, 1), _W(1))
	_check_int("A3 塔 +1 → RUN", int(t.step), int(_Tut.Step.RUN))
	t.free()


func _test_a4_run() -> void:
	_log("[A4] 开下一波 → REPAIR")
	var t = _Tut.new()
	t.advance_with(_S(1, 0, 1), _W(1))
	t.advance_with(_S(1, 1, 1), _W(1))
	t.advance_with(_S(2, 0, 1), _W(1))
	_check_int("A4a 前置 RUN", int(t.step), int(_Tut.Step.RUN))
	# W1 还在打（波次没前进）→ 不能算"已开波"
	t.advance_with(_S(2, 0, 1), _W(1))
	_check_int("A4b 波次未前进 → 仍 RUN", int(t.step), int(_Tut.Step.RUN))
	# W2 开波 → REPAIR
	t.advance_with(_S(2, 0, 1, [], 2), _W(2))
	_check_int("A4c 波次 +1 → REPAIR", int(t.step), int(_Tut.Step.REPAIR))
	t.free()


func _test_a5_a6_repair() -> void:
	_log("[A5/A6] 修：无事不推进、修完才结束")
	var t = _Tut.new()
	t.advance_with(_S(1, 0, 1), _W(1))
	t.advance_with(_S(1, 1, 1), _W(1))
	t.advance_with(_S(2, 0, 1), _W(1))
	t.advance_with(_S(2, 0, 1, [], 2), _W(2))
	_check_int("A5 前置 REPAIR", int(t.step), int(_Tut.Step.REPAIR))
	# 尚无受损塔（未过 W8 兜底）→ 停在 REPAIR，不直接 DONE
	t.advance_with(_S(2, 0, 1, [false, false], 2), _W(2, 3))
	_check_int("A5b 无受损塔 & 未过 W8 → 仍 REPAIR", int(t.step), int(_Tut.Step.REPAIR))
	# 出现受损塔 → 仍在 REPAIR（教"怎么修"）
	t.advance_with(_S(2, 0, 1, [true, false], 2), _W(2, 3))
	_check_int("A6a 受损塔出现 → 仍 REPAIR", int(t.step), int(_Tut.Step.REPAIR))
	# 修好后清空 → DONE
	t.advance_with(_S(2, 0, 1, [false, false], 2), _W(2, 3))
	_check_int("A6b 受损塔清空 → DONE", int(t.step), int(_Tut.Step.DONE))
	t.free()


func _test_a7_skip() -> void:
	_log("[A7] 跳过")
	var t = _Tut.new()
	t.advance_with(_S(1, 0, 1), _W(1))
	_check_bool("A7a 跳过前 skipped", bool(t.skipped), false)
	t.skip()
	_check_int("A7b 跳过 → DONE", int(t.step), int(_Tut.Step.DONE))
	_check_bool("A7c skipped 标记", bool(t.skipped), true)
	t.advance_with(_S(3, 2, 2), _W(5, 2))
	_check_int("A7d 跳过后不再推进", int(t.step), int(_Tut.Step.DONE))
	t.free()


func _test_a8_fallback() -> void:
	_log("[A8] W8 兜底（打得干净也要能收尾）")
	var t = _Tut.new()
	t.advance_with(_S(1, 0, 1), _W(1))
	t.advance_with(_S(1, 1, 1), _W(1))
	t.advance_with(_S(2, 0, 1), _W(1))
	t.advance_with(_S(2, 0, 1, [], 2), _W(2))
	_check_int("A8a 前置 REPAIR", int(t.step), int(_Tut.Step.REPAIR))
	# W8 结束前：继续挂着
	t.advance_with(_S(2, 0, 1, [false], 8), _W(8, 3))
	_check_int("A8b W8 未过 → 仍 REPAIR", int(t.step), int(_Tut.Step.REPAIR))
	# 过了 W8（W9）且从未见受损塔 → 自动 DONE
	t.advance_with(_S(2, 0, 1, [false], 9), _W(9, 3))
	_check_int("A8c 过 W8 无受损塔 → DONE", int(t.step), int(_Tut.Step.DONE))
	t.free()


func _test_a9_monotonic() -> void:
	_log("[A9] 单向性：永不回退")
	var t = _Tut.new()
	t.advance_with(_S(1, 0, 1), _W(1))
	t.advance_with(_S(1, 1, 1), _W(1))
	t.advance_with(_S(2, 0, 1), _W(1))
	t.advance_with(_S(2, 0, 1, [], 2), _W(2))
	_check_int("A9a 到达 REPAIR", int(t.step), int(_Tut.Step.REPAIR))
	t.advance_with(_S(2, 0, 1, [true], 2), _W(2, 2))
	_check_int("A9b 回喂受损快照不回退", int(t.step), int(_Tut.Step.REPAIR))
	t.advance_with(_S(2, 0, 1, [false], 2), _W(2, 3))
	_check_int("A9c 修完 → DONE", int(t.step), int(_Tut.Step.DONE))
	# DONE 后再喂"看起来会推进"的快照：仍 DONE
	t.advance_with(_S(5, 0, 3), _W(7, 2))
	_check_int("A9d DONE 后不回退", int(t.step), int(_Tut.Step.DONE))
	t.free()


# ---------------------------------------------------------------------------
#  汇总
# ---------------------------------------------------------------------------
func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》B-1 零教学浮层 · 状态机断言（headless · 不依赖绘制）")
	_log("规格：docs/phase6/b1-tutorial-spec.md §9 · 判据 OFF→BUY→PLACE→RUN→REPAIR→DONE 单向")
	_log("口径：相对进入基线（开局自带 1 塔 1 卡 + W1 已自动开波，见 §4.1）")
	_log("=".repeat(78))

	_test_a0_a1_initial()
	_test_a2_a3_buy_place()
	_test_a4_run()
	_test_a5_a6_repair()
	_test_a7_skip()
	_test_a8_fallback()
	_test_a9_monotonic()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] B-1 引导状态机 —— 四步可推进、可跳过、W8 可兜底，且零玩法写入")
	else:
		_log("[NG] 有 %d 项未过 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0
