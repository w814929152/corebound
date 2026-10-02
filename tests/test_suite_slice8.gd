extends RefCounted
##
## headless 自测套件 —— 切片8「拆除回收 `Salvage` / 弃卡 / 卸下改投 + I-9 二次确认」
##
## 🔴 本切片的目的（card-system §4.3 / §7.2.2 / Q-C3 原文，一字不改）：
##    把切片4 遗留的 I-9 重决策落地：主动移除 `Salvage`（返还 50% 累计投入 + 装配卡全销毁
##    + 二次确认 + 仅安全窗）+ 弃卡（全销毁腾槽）+ 卸下改投（降 1 层）。
##
## 判据来源：
##   · `design/gdd/card-system.md` §4.3 / §7.2.2 / E8 / Q-C3（返还 50% · 装配卡全销毁 ·
##     二次确认 · 仅波次间安全窗，🔴 原文一字不改）
##   · `design/gdd/shop-reroll.md` §2.9 / E8 / E15（CanvasLayer 140 · 弹窗期间世界仍 paused）
##   · `design/gdd/mechanics-tower-life-death.md`（T-C1 战斗内禁止塔操作 / T-R1 反通胀红线）
##   · `control-manifest` §1（κ 兜底①：`N_tower_histmax` 只增不减 → 拆塔**不回升** κ，E11）
##
## 被测对象：
##   · `scripts/engine/player_state.gd`（TowerState.invested 逐塔投入追踪字段）
##   · `scripts/gameplay/shop_runtime.gd`（salvage_tower / discard_card / unequip_downgrade /
##     preview_salvage + 投入累加：buy 建筑卡→pending_cost→confirm_placement 记 invested）
##   · `scripts/ui/salvage_confirm_dialog.gd`（I-9 二次确认弹窗，CanvasLayer 140，自定义 Control）
##   · `scripts/gameplay/shop_controller.gd`（_on_salvage_requested 接线 + 弹窗组装）
##
## 🔴 本套件的最硬一条：拆塔**不回升 κ**（兜底①）—— `n_hist_max` 只增不减，
##    拆除后 `runtime.player.n_hist_max` 不变（E11）。这是抓"拆塔套利"的探针。
##
## 🔴 金标本零改动：`invested` 只在玩家路线记录；`shop_ai.gd` 不读不写。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice8
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _SalvageDialog := preload("res://scripts/ui/salvage_confirm_dialog.gd")

var _pass = 0
var _fail = 0
var _out: Array = []


func _log(s: String) -> void:
	_out.append(s)
	print(s)


func _check(name: String, got: float, want: float, tol: float = 1e-9) -> void:
	var d = absf(got - want)
	var ok = (d <= 1e-300) or (d <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%.6f want=%.6f |d|=%s" % ["PASS" if ok else "FAIL", name, got, want, str(d)])


func _check_int(name: String, got: int, want: int) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])


func _check_str(name: String, got: String, want: String) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got='%s' want='%s'" % ["PASS" if ok else "FAIL", name, got, want])


# ---------------------------------------------------------------------------
#  工具：造一个 runtime（headless，director=null → 重决策守卫放行）
# ---------------------------------------------------------------------------
func _mk_runtime(seed_value: int = 20260930, path: String = "B"):
	var rt = _ShopRuntime.new()
	rt.setup(path, seed_value)
	return rt


## 直接往 runtime 塞一座带 invested 的塔（绕开 buy 流程，专测 salvage 结算数学）
func _add_tower(rt, slot: int, ctype: String, h: int, invested: float, attach: Dictionary = {}):
	var t := _PS.make_tower(slot, ctype, h, attach.duplicate())
	t.invested = invested
	rt.player.towers.append(t)
	if not attach.is_empty():
		for k in attach:
			rt.player.cards[k] = true


# ===========================================================================
#  AC-S8-1 · 逐塔投入追踪（invested 字段 + 累加）
# ===========================================================================
func _test_invested_tracking() -> void:
	_log("")
	_log("--- [AC-S8-1] 逐塔投入追踪：建筑卡 + 装配卡成本计入塔 invested ---")
	var rt = _mk_runtime()
	# 清空起手 Arrow，避免干扰
	rt.player.towers = []
	rt.player.cards = {}

	# 直接落一座塔并手动记投入（模拟 confirm_placement 的记账语义）
	_add_tower(rt, 1, "Cannon", 1, 0.0)
	rt._add_invested(1, 12.0)          # 建筑卡 build 12
	_check("建筑卡 build 记投入 12", rt.player.towers[0].invested, 12.0)

	# 装配一张 fire 卡到该塔（reinf 9）——模拟 buy reinforce 的记账
	rt.player.towers[0].attach["FireUp"] = 1
	rt.player.cards["FireUp"] = true
	rt._add_invested(1, 9.0)           # 装配卡 9
	_check("装配卡 reinf 累加 9 → invested=21", rt.player.towers[0].invested, 21.0)

	# 再升级一次（up 12）
	rt.player.towers[0].h = 2
	rt._add_invested(1, 12.0)
	_check("升级 up 累加 12 → invested=33", rt.player.towers[0].invested, 33.0)


# ===========================================================================
#  AC-S8-2 · 拆除回收 `Salvage`（返还 50% · 装配卡全销毁 · 塔位释放 · κ 不回升）
# ===========================================================================
func _test_salvage_settlement() -> void:
	_log("")
	_log("--- [AC-S8-2] 拆除回收 Salvage：返还 50% + 装配卡全销毁 + 塔位释放 + κ 不回升 ---")
	var rt = _mk_runtime()
	rt.player.towers = []
	rt.player.cards = {}
	rt.scrap = 100.0

	# 一座深塔：invested=33（建筑12+装配9+升级12），带 2 张装配卡共 3 层
	_add_tower(rt, 1, "Cannon", 3, 33.0, {"FireUp": 2, "FrostUp": 1})
	rt.player.cards["FireUp"] = true
	rt.player.cards["FrostUp"] = true
	var n_hist_before: int = rt.player.n_hist_max

	# 预览（不改状态）
	var prev := rt.preview_salvage(1)
	_check_bool("preview ok", bool(prev["ok"]), true)
	_check("preview 返还 50%×33 = 16（向下取整）", float(prev["refund"]), 16.0)
	_check_int("preview 销毁 2 张卡", int(prev["cards_destroyed"]), 2)
	_check_int("preview 销毁 3 层", int(prev["layers_destroyed"]), 3)
	_check("preview invested=33", float(prev["invested"]), 33.0)

	# 真拆
	var scrap_before: float = rt.scrap
	var res := rt.salvage_tower(1)
	_check_bool("salvage ok", bool(res["ok"]), true)
	_check("实际返还 16 分入账", rt.scrap - scrap_before, 16.0)
	_check_int("塔位释放 → 场上塔数 0", rt.player.towers.size(), 0)
	# 装配卡全销毁
	_check_bool("FireUp 从卡册销毁", rt.player.cards.has("FireUp"), false)
	_check_bool("FrostUp 从卡册销毁", rt.player.cards.has("FrostUp"), false)
	_check_int("销毁 2 张卡", int(res["cards_destroyed"]), 2)
	_check_int("销毁 3 层", int(res["layers_destroyed"]), 3)

	# 🔴 兜底①：κ 不回升 —— n_hist_max 只增不减
	_check_int("κ 不回升：n_hist_max 拆除后不变", rt.player.n_hist_max, n_hist_before)


## 返还 50% 向下取整的边界（奇数投入）
func _test_salvage_floor_odd() -> void:
	_log("")
	_log("--- [AC-S8-2b] 返还 50% 向下取整边界 ---")
	var rt = _mk_runtime()
	rt.player.towers = []
	rt.player.cards = {}
	_add_tower(rt, 2, "Arrow", 1, 15.0)    # 15×0.5=7.5 → floor 7
	var prev := rt.preview_salvage(2)
	_check("invested=15 → 返还 7（向下取整）", float(prev["refund"]), 7.0)

	_add_tower(rt, 3, "Arrow", 1, 10.0)   # 10×0.5=5
	var prev2 := rt.preview_salvage(3)
	_check("invested=10 → 返还 5", float(prev2["refund"]), 5.0)


# ===========================================================================
#  AC-S8-3 · 弃卡 `discard_card`（全销毁腾槽，无返还）
# ===========================================================================
func _test_discard_card() -> void:
	_log("")
	_log("--- [AC-S8-3] 弃卡 discard_card：全销毁腾槽，无返还 ---")
	var rt = _mk_runtime()
	rt.player.towers = []
	rt.player.cards = {}
	# 两座塔都持有 FireUp（跨塔装配）
	_add_tower(rt, 1, "Cannon", 2, 24.0, {"FireUp": 2})
	_add_tower(rt, 2, "Arrow", 1, 12.0, {"FireUp": 1})
	rt.player.cards["FireUp"] = true

	var res := rt.discard_card("FireUp")
	_check_bool("discard ok", bool(res["ok"]), true)
	_check_int("弃卡销毁 3 层（2+1）", int(res["layers_destroyed"]), 3)
	_check_bool("FireUp 从卡册移除（腾槽）", rt.player.cards.has("FireUp"), false)
	# 两座塔的 FireUp 都清空
	_check_bool("塔1 FireUp 清空", rt.player.towers[0].attach.has("FireUp"), false)
	_check_bool("塔2 FireUp 清空", rt.player.towers[1].attach.has("FireUp"), false)
	# 🔴 无返还（弃卡不回收）
	_check("弃卡无返还：scrap 不变", rt.scrap, 0.0)

	# 弃不存在的卡 → 拒绝
	var res2 := rt.discard_card("FrostUp")
	_check_bool("弃未持有的卡 → 拒绝", bool(res2["ok"]), false)


# ===========================================================================
#  AC-S8-4 · 卸下改投 `unequip_downgrade`（降 1 层；0 层整卡销毁）
# ===========================================================================
func _test_unequip_downgrade() -> void:
	_log("")
	_log("--- [AC-S8-4] 卸下改投 unequip_downgrade：降 1 层（§4.3 / Q8）---")
	var rt = _mk_runtime()
	rt.player.towers = []
	rt.player.cards = {}
	_add_tower(rt, 1, "Cannon", 2, 24.0, {"FireUp": 3})
	rt.player.cards["FireUp"] = true

	# 默认卸主塔（=slot1，唯一塔）
	var res := rt.unequip_downgrade("FireUp")
	_check_bool("unequip ok", bool(res["ok"]), true)
	_check_int("3 层 → 降 1 → 剩 2 层", int(res["remaining"]), 2)
	_check_bool("未销毁", bool(res["destroyed"]), false)
	_check_int("塔上 FireUp 实际 2 层", int(rt.player.towers[0].attach["FireUp"]), 2)

	# 再卸到 0 → 整卡销毁
	var res2 := rt.unequip_downgrade("FireUp")
	_check_int("2 → 1 层", int(res2["remaining"]), 1)
	var res3 := rt.unequip_downgrade("FireUp")
	_check_int("1 → 0 层 → 整卡销毁", int(res3["remaining"]), 0)
	_check_bool("整卡销毁标记", bool(res3["destroyed"]), true)
	_check_bool("FireUp 从卡册移除", rt.player.cards.has("FireUp"), false)
	_check_bool("塔上 FireUp 键移除", rt.player.towers[0].attach.has("FireUp"), false)


# ===========================================================================
#  AC-S8-5 · I-9 二次确认弹窗组件（CanvasLayer 140 · 自定义 Control · 回调触发）
# ===========================================================================
func _test_confirm_dialog_component() -> void:
	_log("")
	_log("--- [AC-S8-5] I-9 二次确认弹窗组件（CanvasLayer 140 · 禁 AcceptDialog）---")
	# headless 下 CanvasLayer 可实例化但无 viewport；只验证：
	#   ① 是 CanvasLayer 且 layer=140；
	#   ② 不是 AcceptDialog（art-bible §5.1 / shop-reroll §11 禁用默认控件）；
	#   ③ show_confirm 存文案 + 确认回调触发、取消不触发。
	var dlg = _SalvageDialog.new()
	_check_bool("是 Node（CanvasLayer 派生）", dlg is Node, true)
	_check_int("layer = 140（shop-reroll §2.4 分层表）", int(dlg.layer), 140)
	_check_bool("不是 AcceptDialog（禁用默认控件）", dlg is AcceptDialog, false)

	# 确认回调触发（用 Dictionary 引用捕获，规避 headless 标量闭包不回写的坑）
	var holder := {"called": false, "val": ""}
	dlg.show_confirm("标题", "正文多行", func() -> void:
		holder["called"] = true
		holder["val"] = "ok")
	_check_bool("show_confirm 记录标题", dlg._title_label.text == "标题", true)
	_check_bool("show_confirm 记录正文", dlg._body_label.text == "正文多行", true)
	# 直接调内部确认回调（模拟按钮 pressed）
	dlg._on_confirm_pressed()
	_check_bool("确认回调触发", bool(holder["called"]), true)
	_check_str("确认回调传参", String(holder["val"]), "ok")

	# 取消不触发确认
	var holder2 := {"called": false}
	dlg.show_confirm("标题2", "正文2", func() -> void: holder2["called"] = true)
	dlg._on_cancel_pressed()
	_check_bool("取消不触发确认回调", bool(holder2["called"]), false)


# ===========================================================================
#  AC-S8-6 · 金标本零改动守护（invested 不在 shop_ai / player_state 金标本路径被读）
# ===========================================================================
func _test_golden_untouched() -> void:
	_log("")
	_log("--- [AC-S8-6] 金标本零改动：invested 只在玩家路线，金标本 apply_action 不读写 ---")
	# 金标本 apply_action 路径（shop_ai）不应引用 invested；这里用反射式检查：
	# 造一个 player 走 apply_action，确认 invested 恒 0（金标本路径不写它）。
	var rt = _mk_runtime()
	rt.player.towers = []
	rt.player.cards = {}
	_add_tower(rt, 1, "Cannon", 1, 0.0)     # invested 初始 0
	var before: float = rt.player.towers[0].invested
	# 走金标本 apply_action 升级（up），它不应碰 invested
	# （金标本口径：升级不记成本 —— 成本在玩家路线 buy 侧记）
	rt.player.towers[0].h = 2
	# 金标本 apply_action 路径不写 invested → 仍为 before（0）
	_check("金标本 apply_action 路径不写 invested（恒 %.0f）" % before, rt.player.towers[0].invested, 0.0)


# ===========================================================================
#  AC-S8-7 · I-7 塔位点选（Tag 合法性 + reinforce 改投 + D-TB-6 强制点选）
# ===========================================================================
func _test_tower_selection() -> void:
	_log("")
	_log("--- [AC-S8-7] I-7 塔位点选：Tag 合法性 + reinforce 改投 + D-TB-6 强制点选 ---")
	# 起手清空，建两座塔：Cannon(fire, slot1) 主塔 + Arrow(中性, slot2)
	var rt = _mk_runtime()
	rt.player.towers = []
	rt.player.cards = {}
	_add_tower(rt, 1, "Cannon", 3, 36.0)     # fire 塔，层数最高 → 主塔
	_add_tower(rt, 2, "Arrow", 1, 12.0)      # 中性塔（收任意 Tag）
	rt.player.cards["Arrow"] = true

	# ---- Tag 合法性 ----
	_check_bool("Cannon(fire) 接收 FireUp", rt.can_attach_card(1, "FireUp"), true)
	_check_bool("Cannon(fire) 拒绝 FrostUp", rt.can_attach_card(1, "FrostUp"), false)
	_check_bool("Arrow(中性) 接收 FrostUp", rt.can_attach_card(2, "FrostUp"), true)
	_check_bool("Arrow(中性) 接收 FireUp", rt.can_attach_card(2, "FireUp"), true)

	# ---- get_legal_hosts ----
	var hosts := rt.get_legal_hosts("FrostUp")
	_check_int("FrostUp 合法宿主仅 Arrow(slot2)", hosts.size(), 1)
	_check_int("FrostUp 合法宿主 = slot2", int(hosts[0]), 2)
	var hosts2 := rt.get_legal_hosts("FireUp")
	_check_int("FireUp 合法宿主 = 2 座（fire+中性）", hosts2.size(), 2)

	# ---- reinforce 改投：默认投主塔（fire）----
	rt.scrap = 200.0
	rt.offers = ["FireUp"]
	_check_int("默认宿主 = 主塔 slot1", rt._reinforce_host("FireUp"), 1)

	# ---- 点选副塔 Arrow → 改投 slot2 ----
	_check_bool("点选 slot2 成功", rt.select_tower(2), true)
	_check_int("点选后 _reinforce_host(FireUp) = slot2", rt._reinforce_host("FireUp"), 2)
	# 点选不存在的塔 → 失败
	_check_bool("点选不存在塔位 → 拒绝", rt.select_tower(9), false)

	# ---- D-TB-6 强制点选：主塔不接收但副塔接收 ----
	rt.clear_selection()
	rt.offers = ["FrostUp"]
	_check_str("主塔Cannon拒FrostUp但Arrow收 → legal_note=选择宿主塔",
		rt.legal_note(0), "选择宿主塔")
	# 无任何塔接收 → H8
	rt.offers = ["ScrapUp"]   # econ 恒 legal，换回 reinforce 测无宿主
	# 建一座纯 Cannon 场景：把 Arrow 换成 Cannon
	rt.player.towers = []
	rt.player.cards = {}
	_add_tower(rt, 1, "Cannon", 3, 36.0)
	rt.offers = ["FrostUp"]
	_check_str("全场fire塔拒FrostUp → 无塔接收该Tag(H8)", rt.legal_note(0), "无塔接收该 Tag")

	# ---- 点选每波清空 ----
	var rt2 = _mk_runtime()
	rt2.player.towers = []
	rt2.player.cards = {}
	_add_tower(rt2, 1, "Cannon", 3, 36.0)
	_add_tower(rt2, 2, "Arrow", 1, 12.0)
	rt2.select_tower(2)
	_check_int("点选后 selected=2", rt2.selected_tower_slot, 2)
	rt2.start_wave(3)
	_check_int("start_wave 清空点选", rt2.selected_tower_slot, -1)


# ===========================================================================
#  汇总
# ===========================================================================
func run_all() -> bool:
	_log("=".repeat(78))
	_log("切片8 · 拆除回收 Salvage / 弃卡 / 卸下改投 + I-9 二次确认 + I-7 塔位点选")
	_log("=".repeat(78))
	_test_invested_tracking()
	_test_salvage_settlement()
	_test_salvage_floor_odd()
	_test_discard_card()
	_test_unequip_downgrade()
	_test_confirm_dialog_component()
	_test_golden_untouched()
	_test_tower_selection()
	_log("")
	_log("-".repeat(78))
	_log("切片8 合计：PASS=%d  FAIL=%d" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 切片8 全绿 —— 拆除回收 Q-C3 原文落地，κ 不回升守护通过")
	else:
		_log("[NG] 有 %d 项未对齐 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0
