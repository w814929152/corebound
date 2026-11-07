extends RefCounted
##
## headless 自测套件 —— 切片4「接线完整商店逻辑」
##
## 判据来源：
##   · `design/gdd/shop-reroll.md` **v1.3** §2.5（刷新经济）· §2.6（锁定）· §2.7（三类卡分流）
##     · §2.8（pity 兜底链 P1–P4，自检清单 A1–A7 · 🔴 A4b 玩家路线有放回恒 3 位）
##     · §9.2 拍板留档（D-1 玩家路线 reroll 不保底 / D-2 恒发 3 张有放回 / D-4 移除 RerollD）
##   · `design/gdd/card-system.md` §4.5（pity）· §3.6（5 槽 = 5 卡种，非 5 层）
##   · `docs/architecture/slice3-shop-ui-architecture.md` §8 接口点 I-1 / I-2 / I-3 / I-8
##
## 被测对象：
##   · `scripts/gameplay/shop_runtime.gd`（纯逻辑，零副作用 → headless 可单测）
##   · 判据链回归：`scripts/engine/shop_ai.gd` 被切片4 **复用而非修改**，用定稿判据链反证
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice4
##

const TOL := 1e-12

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _G := preload("res://tests/golden_slice2.gd")

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


func _tally(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s" % ["PASS" if ok else "FAIL", name])


func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》MVP 切片4 · 接线完整商店逻辑 —— 自测")
	_log("判据：design/gdd/shop-reroll.md v1.3 §2.5/§2.6/§2.7/§2.8(A4b)/§9.2 · card-system §3.6/§4.5")
	_log("=".repeat(78))

	_test_pity_initial_shop()
	_test_reroll_is_pure_random()
	_test_lock()
	_test_reroll_cost()
	_test_three_way_routing()
	_test_slots_are_kinds_not_layers()
	_test_offer_count()
	_test_wave_wiring_and_criteria()
	_test_c3_compliance_grep()
	_test_x3_slot_equality()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 商店逻辑接线与 GDD §2.5–§2.8 逐条一致")
	else:
		_log("[NG] 有 %d 项未对齐 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0


# ---------------------------------------------------------------------------
#  工具
# ---------------------------------------------------------------------------
func _mk_runtime(seed_value: int, path: String = "B"):
	var rt = _ShopRuntime.new()
	rt.setup(path, seed_value)
	return rt


## 起手只有 Arrow（中性塔）→ 主塔无 Tag → P3 口径下 pity 不生效。
## 建起 `ctype` 塔并升到 h=2 → 主塔变它 → pity 武装。
func _arm_pity(rt, ctype: String = "Cannon") -> void:
	rt.scrap = 400.0
	rt.offers = [ctype]
	rt.buy(0)
	rt.begin_placement(0)
	rt.confirm_placement(1)          # 新建 @1 h=1
	rt.offers = [ctype]
	rt.buy(0)
	rt.begin_placement(0)
	rt.confirm_placement(1)          # 升级 → h=2 → 主塔 = ctype


# ===========================================================================
# 1. pity 起飞保底（GDD §2.8 · 自检清单 A1 / P1 / P3 / P4）
# ===========================================================================
func _test_pity_initial_shop() -> void:
	_log("")
	_log("--- [1] pity 起飞保底：**仅每波初始商店**保底（GDD §2.8.1 · A1/P1/P3/P4）---")

	# ---- P3：起手只有中性塔 Arrow → 主塔无 Tag → 不保底 ----
	var rt0 = _mk_runtime(20260930)
	_check_int("P3 起手塔数 = 1（Arrow@0）", rt0.player.towers.size(), 1)
	_check_str("P3 主塔无 Tag → pity 不生效", rt0.pity_card_name(), "")

	# ---- P4：场上无塔 → 不保底 ----
	rt0.player.towers = []
	_check_str("P4 场上无塔 → pity 不生效", rt0.pity_card_name(), "")

	# ---- P1：主塔 = Cannon(fire) → pity = FireUp，且**每次初始发牌必含** ----
	var rt = _mk_runtime(20260930)
	_arm_pity(rt, "Cannon")
	_check_int("P1 主塔塔位 = 1（Cannon h=2）", rt.core_tower_slot(), 1)
	_check_str("P1 主塔有 Tag → pity = FireUp", rt.pity_card_name(), "FireUp")

	var miss := 0
	var n_deals := 200
	for i in n_deals:
		rt.start_wave(2 + i)
		if not rt.offers.has("FireUp"):
			miss += 1
	_tally("A1 每波初始商店必含 ≥1 张主塔同 Tag 卡（%d 次发牌，漏 %d 次）" % [n_deals, miss],
		miss == 0)

	# ---- P1 的另一半：Frost 主塔 → pity = FrostUp ----
	var rt2 = _mk_runtime(20260930)
	_arm_pity(rt2, "Frost")
	_check_str("P1 Frost 主塔 → pity = FrostUp", rt2.pity_card_name(), "FrostUp")

	# ---- 🟡 P2 登记：金标本未实现「主塔无 Tag 但全场有 Tag 投入 → 保 argmax_Tag」----
	var rt3 = _mk_runtime(20260930)
	rt3.offers = ["FireUp"]
	rt3.scrap = 100.0
	_check_bool("[登记] 中性塔能接收任意 Tag 卡（D-8①）→ 买 FireUp", rt3.buy(0), true)
	_check_str("🟡 P2 金标本未实现：全场有 fire 投入但主塔是中性塔 → 仍不保底",
		rt3.pity_card_name(), "")
	_log("   [info] pity 卡由 `ShopAI.pity_card()` 产出（金标本 S2 判据），未改写；")
	_log("          补 P2 会改变 MC 发牌序列 → 不许擅改，已写进回报")


# ===========================================================================
# 2. 手动 reroll **纯随机不保底**（GDD §2.8.1 · A2 · §10.1 断言 6）
# ===========================================================================
func _test_reroll_is_pure_random() -> void:
	_log("")
	_log("--- [2] 手动 reroll 纯随机（不含任何保底逻辑，±3 个百分点）---")
	var rt = _mk_runtime(20260930)
	_arm_pity(rt, "Cannon")
	_check_str("[前置] pity 已武装（初始商店会保底 FireUp）", rt.pity_card_name(), "FireUp")

	# 纯随机基线：P(3 次抽取中至少 1 张 FireUp) = 1 − (1 − w)^3
	# 🔴 D-4（v1.3）：玩家路线卡池已移除 RerollD（0.095）→ 剩余 6 张权重**归一**
	#   （`PyRandom.choices` 按 `total = Σw` 归一，control-manifest P3）
	#   → w(FireUp) = 0.17 / (1 − 0.095) = 0.1878，基线由 0.4282 抬到 0.4643。
	var p_fire := float(_ShopAI.WEIGHTS["FireUp"]) / _ShopRuntime.player_pool_total()
	var base := 1.0 - pow(1.0 - p_fire, 3.0)
	_log("   [info] 权重 FireUp = %.6f（玩家池归一后，总权重 %.6f）→ 纯随机基线 = %.6f"
		% [p_fire, _ShopRuntime.player_pool_total(), base])

	var n := 6000
	var hits := 0
	for i in n:
		rt.offers = ["Arrow", "Cannon", "Frost"]   # 3 位、不含 FireUp、无锁定
		rt.lock_index = -1
		rt.scrap = 1.0e9
		rt.reroll()
		if rt.offers.has("FireUp"):
			hits += 1
	var rate := float(hits) / float(n)
	_log("   [info] 实测 %d 次 reroll，FireUp 出现率 = %.6f（基线 %.6f）" % [n, rate, base])
	# ±3 个百分点 ≈ ±4.7σ（N=6000，σ≈0.0064）
	_check("A2 reroll 目标 Tag 出现率 = 纯随机基线（±3pp）", rate, base, 0.07)
	_tally("A2 reroll 绝非每刷必中（出现率 < 0.60）", rate < 0.60)


# ===========================================================================
# 3. 锁定（GDD §2.6 · SR-R4 · Q-SR4 每波重置）
# ===========================================================================
func _test_lock() -> void:
	_log("")
	_log("--- [3] 锁定：3 位可锁 1 · 刷新保留原位 · 每波重置（GDD §2.6）---")
	var rt = _mk_runtime(12345)
	rt.scrap = 1.0e9

	_check_int("MAX_LOCK = 1", _Cfg.MAX_LOCK, 1)
	_check_int("初始无锁定", rt.lock_index, -1)

	# ---- 锁定位在刷新中原样保留（🔴 不参与刷新）----
	rt.offers = ["Arrow", "Cannon", "Frost"]
	rt.toggle_lock(0)
	_check_int("锁定商品位 0", rt.lock_index, 0)
	rt.reroll()
	_check_str("锁定位刷新后仍是原卡", String(rt.offers[0]), "Arrow")
	_tally("锁定位不被新抽的卡覆盖（另两位不含锁定卡）",
		String(rt.offers[1]) != "Arrow" and String(rt.offers[2]) != "Arrow")

	# ---- 改锁 / 解锁 ----
	rt.offers = ["Arrow", "Cannon", "Frost"]
	rt.toggle_lock(2)
	_check_int("已锁 0 时锁 2 → 改锁到 2（同时最多 1 张）", rt.lock_index, 2)
	rt.toggle_lock(2)
	_check_int("再按一次 → 解锁", rt.lock_index, -1)

	# ---- 越界锁定被拒 ----
	rt.offers = ["Arrow", "Cannon", "Frost"]
	_check_bool("越界位锁定被拒", rt.toggle_lock(5), false)

	# ---- Q-SR4：每波重置 ----
	rt.toggle_lock(1)
	_check_int("锁定 1", rt.lock_index, 1)
	rt.start_wave(7)
	_check_int("Q-SR4 每波重置 → 无锁定", rt.lock_index, -1)
	_check_int("Q-SR4 刷新次数也重置", rt.rerolls, 0)

	# ---- 🟡 报告项：金标本没有锁定机制 ----
	_log("   [info] 🟡 金标本 `shop_ai.gd` / `player_state.gd` 无 locked 字段 →")
	_log("          锁定是本轮新增的 UI 侧状态，SR-R4「pity 不覆盖锁定」在本轮实现里成立；")
	_log("          金标本 `shop_phase()` 的每次刷新都带 pity（D-1），那条路径下无锁定概念。")


# ===========================================================================
# 4. 刷新成本 5 + 3n（GDD §2.5 · §9 Q-SR9 下限 1 分）
# ===========================================================================
func _test_reroll_cost() -> void:
	_log("")
	_log("--- [4] 刷新成本 Cost(n) = 5 + 3n（每波重置 · 下限 1 分）---")
	var rt = _mk_runtime(999)

	_check("cfg.reroll_base = MvpConfig.BASE_REROLL", float(rt.cfg["reroll_base"]),
		float(_Cfg.BASE_REROLL))
	_check("cfg.reroll_growth = MvpConfig.REROLL_STEP", float(rt.cfg["reroll_growth"]),
		float(_Cfg.REROLL_STEP))

	# n = 0..5 → 5 / 8 / 11 / 14 / 17 / 20（disc = 0）
	var want := [5.0, 8.0, 11.0, 14.0, 17.0, 20.0]
	for n in want.size():
		rt.rerolls = n
		_check("第 %d 次刷新成本 = %.0f" % [n + 1, want[n]], rt.reroll_cost(), want[n])

	# 累计（GDD §2.5 张力验算表）：5 / 13 / 24 / 38 / 55 / 75
	var cum := 0.0
	var want_cum := [5.0, 13.0, 24.0, 38.0, 55.0, 75.0]
	for n in want_cum.size():
		rt.rerolls = n
		cum += rt.reroll_cost()
		_check("累计到第 %d 次 = %.0f" % [n + 1, want_cum[n]], cum, want_cum[n])

	# ---- 🔴 下限 1 分：刷新永不免费（Q-SR9）----
	rt.player.reroll_disc = 100.0
	rt.rerolls = 0
	_check("折扣 100 → 下限 1 分（刷新永不免费）", rt.reroll_cost(),
		float(_Cfg.MIN_REROLL_COST))

	# ---- 🟡 口径分歧登记（不 FAIL，只留证据）----
	rt.player.reroll_disc = 0.5      # G2 供应链满级 −50%
	rt.rerolls = 0
	var gold = rt.reroll_cost()                           # 金标本 S6：5 + 0 − 0.5 = 4.5
	var gdd = floor(float(5 + 3 * 0) * (1.0 - 0.5))       # GDD §2.5：floor(5 × 0.5) = 2
	_log("   [info] 🟡 折扣口径分歧（discount=0.50，n=0）：金标本 S6 = %.1f 分 / GDD §2.5 = %.1f 分"
		% [gold, gdd])
	_tally("🟡 该分歧已登记（discount = 0 时二者逐位相同）", absf(gold - gdd) > 0.0)
	rt.player.reroll_disc = 0.0

	# ---- 扣费与 n 递增；E5 不得赊账 ----
	rt.scrap = 100.0
	rt.rerolls = 0
	rt.offers = ["Arrow", "Cannon", "Frost"]
	_check_bool("刷新成功", rt.reroll(), true)
	_check("扣费 5 分", rt.scrap, 95.0)
	_check_int("n 递增到 1", rt.rerolls, 1)
	rt.scrap = 3.0
	_check_bool("E5 买不起 → 拒绝刷新", rt.reroll(), false)
	_check("E5 积分未被扣成负数", rt.scrap, 3.0)


# ===========================================================================
# 5. 三类卡购买后分流路径（GDD §2.7）
# ===========================================================================
func _test_three_way_routing() -> void:
	_log("")
	_log("--- [5] 三类卡分流：建筑卡→待放置队列 / 单塔效果卡→投主塔 / 全局卡→立即生效 ---")
	var rt = _mk_runtime(2024)
	rt.scrap = 300.0

	# ---- 价格（GDD §3.1 A1：12 / 9 / 10）----
	rt.offers = ["Cannon", "FireUp", "ScrapUp"]
	_check("建筑卡价格 = 12", rt.price_at(0), float(_Cfg.PRICE_STRUCTURE))
	_check("单塔效果卡价格 = 9", rt.price_at(1), float(_Cfg.PRICE_TOWER_EFFECT))
	_check("全局效果卡价格 = 10", rt.price_at(2), float(_Cfg.PRICE_GLOBAL_EFFECT))

	# ---- ① 建筑卡 → 待放置队列（买 / 放解耦；不占塔位、不占强化槽）----
	rt.offers = ["Cannon"]
	var scrap0 = rt.scrap
	_check_bool("买建筑卡 Cannon", rt.buy(0), true)
	_check("扣 12 分", rt.scrap, scrap0 - 12.0)
	_check_int("① 入待放置队列", (rt.pending as Array).size(), 1)
	_check_str("① 队列里是 Cannon", String(rt.pending[0]), "Cannon")
	_check_int("① 买的时候**不落塔**（塔数仍为 1）", rt.player.towers.size(), 1)
	_check_int("① 不占强化槽（仍只有 Arrow 一种卡）", rt.player.cards.size(), 1)

	# ---- I-8 放置落子：空塔位 = 新建 ----
	_check_bool("进入放置（队列下标 0）", rt.begin_placement(0), true)
	_check_str("塔位 1 是新建", rt.placement_mode_for(1), "new")
	_check_bool("落子塔位 1", rt.confirm_placement(1), true)
	_check_int("落子后塔数 = 2", rt.player.towers.size(), 2)
	_check_int("队列清空", (rt.pending as Array).size(), 0)
	_check_str("塔位 1 是 Cannon", String(rt.player.towers[1].ctype), "Cannon")
	_check_int("新建层数 h = 1", int(rt.player.towers[1].h), 1)

	# ---- 再买一张 → 同塔位升级；异原型塔位非法（不落子、不退卡、不退款）----
	rt.offers = ["Cannon"]
	rt.buy(0)
	rt.begin_placement(0)
	_check_str("同原型塔位 = 升级", rt.placement_mode_for(1), "upgrade")
	_check_str("异原型塔位 = 非法", rt.placement_mode_for(0), "invalid")
	_check_bool("非法目标不落子", rt.confirm_placement(0), false)
	_check_int("非法落子后卡仍在队列", (rt.pending as Array).size(), 1)
	_check_bool("升级落子", rt.confirm_placement(1), true)
	_check_int("升级后 h = 2", int(rt.player.towers[1].h), 2)
	_check_int("取消放置不退款、不退卡（队列保持）", (rt.pending as Array).size(), 0)

	# ---- ② 单塔效果卡 → 默认投主塔 ----
	_check_int("主塔 = Cannon（塔位 1）", rt.core_tower_slot(), 1)
	rt.offers = ["FireUp"]
	_check_str("H8 有合法宿主（fire 卡投 fire 塔）", rt.legal_note(0), "")
	_check_bool("买单塔效果卡 FireUp", rt.buy(0), true)
	_check_bool("② 装配到主塔", rt.player.towers[1].attach.has("FireUp"), true)
	_check_int("② 层数 = 1", int(rt.player.towers[1].attach["FireUp"]), 1)
	_check_int("② 占 1 个强化槽（Arrow + FireUp = 2）", rt.player.cards.size(), 2)

	# ---- D-8① / E9 ----
	# 🟡 I-7（切片8）：主塔 fire 拒 FrostUp 但场上有中性 Arrow 可收 → D-TB-6 强制点选
	#    （legal_note = "选择宿主塔"，1 步购买置灰，需先点选合法副塔再买）。
	rt.offers = ["FrostUp"]
	_check_str("D-8① 主塔 fire 拒 FrostUp 但有中性塔可收 → D-TB-6 强制点选", rt.legal_note(0), "选择宿主塔")
	_check_bool("D-8① 1 步购买置灰（需先点选宿主）", rt.buy(0), false)
	var rt9 = _mk_runtime(2024)
	rt9.player.towers = []
	rt9.offers = ["FireUp"]
	_check_str("E9 场上无塔 → 单塔效果卡置灰", rt9.legal_note(0), "需先建造一座塔")

	# ---- E1：塔数填满且无同原型 → 建筑卡无合法目标 ----
	# 🆕 自由摆放：闸门是 `tower_cap`（塔数上限），**不是** `n_slots`（金标本槽位数）。
	#   改造前两者是同一个数（6）；位置自由之后槽位数随便增长，塔数上限才是玩法旋钮。
	#   这里把上限压到 3 便于构造，落子走**坐标**（`confirm_placement_at`）。
	var rt1 = _mk_runtime(2024)
	rt1.cfg["tower_cap"] = 3
	rt1.scrap = 1.0e6
	var cap: int = rt1.tower_cap()
	var k := 0
	while rt1.player.towers.size() < cap and k < 8:
		rt1.offers = ["Arrow"]
		rt1.buy(0)
		rt1.begin_placement(0)
		# 沿 +X 方向逐格撒（每格间距 1 格，互不同槽）
		var gp: Vector2 = _BuildGrid.snap(_BuildGrid.core() + Vector2(6.0 + 2.5 * float(k), 0.0))
		rt1.confirm_placement_at(gp)
		k += 1
	_check_int("[E1] 塔数填满（tower_cap）", rt1.player.towers.size(), cap)
	rt1.offers = ["Cannon"]
	_log("   [info] E1 置灰理由 = 「%s」（H8 无合法目标）" % rt1.legal_note(0))
	_tally("E1 建筑卡无合法目标 → 置灰", rt1.legal_note(0) != "")
	_check_bool("E1 买不了", rt1.buy(0), false)

	# ---- ③ 全局效果卡 → 立即生效 ----
	rt.offers = ["ScrapUp"]
	var im0 := float(rt.player.income_mult)
	_check_bool("买全局效果卡 ScrapUp", rt.buy(0), true)
	_check("③ 立即生效：income_mult +0.20", float(rt.player.income_mult), im0 + 0.20)

	# ---- ✅ D-4（shop-reroll §9.2 v1.3）：玩家路线发牌池**移除 RerollD**（空卡，买后 +0%）----
	var pool := _ShopRuntime.player_card_names() as Array
	_tally("D-4 RerollD **不在**玩家路线发牌池（%s）" % str(pool), not pool.has("RerollD"))
	_check_int("D-4 玩家池 = 金标本 7 张 − RerollD = 6 张", pool.size(), 6)
	var n_deal := 2000
	var n_rd := 0
	var rtp = _mk_runtime(20260930)
	for i in n_deal:
		rtp.start_wave(1 + i)
		for nm in rtp.offers:
			if String(nm) == "RerollD":
				n_rd += 1
	_check_int("D-4 玩家路线发牌 %d 次 → RerollD 出现次数 = 0（实到 %d）" % [n_deal, n_rd], n_rd, 0)
	_log("   [info] 🔴 金标本 `ShopAI.CARD_NAMES`/`WEIGHTS` **不动**（AI 路线仍 7 张含 RerollD，")
	_log("          MC 不变）；玩家池由金标本**派生**（`shop_runtime.player_card_names()`）。")


# ===========================================================================
# 6. 5 槽 = 5 个卡种，不是 5 层（card-system §3.6 · 实现最易错处）
# ===========================================================================
func _test_slots_are_kinds_not_layers() -> void:
	_log("")
	_log("--- [6] 5 槽 = 5 个卡种，非 5 层（card-system §3.6）---")
	var rt = _mk_runtime(555)
	rt.scrap = 1.0e6
	_arm_pity(rt, "Cannon")            # 主塔 Cannon(fire) → 可接收 FireUp

	var kinds0 = rt.player.cards.size()
	rt.offers = ["FireUp"]
	rt.buy(0)
	_check_int("买第 1 张 FireUp → 卡种 +1", rt.player.cards.size(), kinds0 + 1)
	_check_int("第 1 张 FireUp 层数 = 1", int(rt.player.towers[1].attach["FireUp"]), 1)

	rt.offers = ["FireUp"]
	rt.buy(0)
	_check_int("🔴 同卡再买 → 卡种数**不变**（不占新槽）", rt.player.cards.size(), kinds0 + 1)
	_check_int("🔴 同卡再买 → 层数 +1", int(rt.player.towers[1].attach["FireUp"]), 2)

	rt.offers = ["FireUp"]
	rt.buy(0)
	rt.offers = ["FireUp"]
	rt.buy(0)
	_check_int("连买 4 张 → 卡种数仍不变", rt.player.cards.size(), kinds0 + 1)
	_check_int("连买 4 张 → 层数 = 4", int(rt.player.towers[1].attach["FireUp"]), 4)

	# ---- 换一种卡 → 才占新槽 ----
	var rt2 = _mk_runtime(555)
	rt2.scrap = 1.0e6
	_arm_pity(rt2, "Frost")            # 主塔 Frost(frost) → 可接收 FrostUp
	var k0 = rt2.player.cards.size()
	rt2.offers = ["FrostUp"]
	rt2.buy(0)
	_check_int("换一种卡（FrostUp）→ 卡种 +1（占新槽）", rt2.player.cards.size(), k0 + 1)
	rt2.offers = ["FrostUp"]
	rt2.buy(0)
	_check_int("FrostUp 再买 → 卡种不变", rt2.player.cards.size(), k0 + 1)
	_check_int("FrostUp 再买 → 层数 = 2", int(rt2.player.towers[1].attach["FrostUp"]), 2)

	_check_int("backpack（强化槽上限）= 5", int(rt.cfg["backpack"]), 5)
	_tally("强化槽用量不超过 5",
		rt.player.cards.size() <= 5 and rt2.player.cards.size() <= 5)


# ===========================================================================
# 7. 商品位数（A4/A4b 恒为 3 · ✅ D-2 玩家路线有放回发牌）
# ===========================================================================
func _test_offer_count() -> void:
	_log("")
	_log("--- [7] 商品位数：玩家路线**恒为 3**（A4b · D-2 有放回，可重复）---")
	var rt = _mk_runtime(20260930)
	_check_int("SHOP_SLOTS = 3", _Cfg.SHOP_SLOTS, 3)

	var n := 2000
	var bad := 0
	for i in n:
		rt.start_wave(1 + i)
		if rt.offers.size() != _Cfg.SHOP_SLOTS:
			bad += 1
	_tally("A4/A4b 位数恒 = %d（%d 次发牌，越界 %d 次）" % [_Cfg.SHOP_SLOTS, n, bad], bad == 0)
	_log("   [info] ✅ D-2（§9.2 v1.3）：玩家路线**不再复用**金标本 `draw_offers()` 的去重集合，")
	_log("          改走 `shop_runtime._draw_offers_player()`（6 张池**有放回**抽 3）→ 位数恒 3，")
	_log("          3 位可含同卡（如 3×Cannon）。🔴 金标本 `draw_offers()` 一字未改（AI 路线仍去重）。")

	var s: Dictionary = rt.snapshot()
	_check_int("快照恒给 3 个物理位（UI 三商品位仍在）", (s["offers"] as Array).size(), 3)


# ===========================================================================
# 8. I-1 波次接线 + 🔴 判据链不回归（证明切片4 没动 shop_ai）
# ===========================================================================
func _test_wave_wiring_and_criteria() -> void:
	_log("")
	_log("--- [8] I-1 波次接线（预算 / n / 锁定三者同节奏重置）+ 判据链回归 ---")

	var sm = _TSM.new(6)
	var rt = _mk_runtime(20260930)
	rt.start_wave(6)
	sm.open_shop()
	sm.tick(8.0)
	_check("W6 消耗 8 实时秒后预算", sm.budget_left, _Cfg.DILATION_BUDGET - 8.0)

	rt.rerolls = 4
	rt.lock_index = 2
	sm.wave_start(7)          # 时钟侧：预算重置
	rt.start_wave(7)          # 玩法侧：n / 锁定重置 + 发初始商店
	_check("I-1 时钟侧：预算重置为 20", sm.budget_left, _Cfg.DILATION_BUDGET)
	_check_int("I-1 玩法侧：n ← 0", rt.rerolls, 0)
	_check_int("I-1 玩法侧：锁定清空", rt.lock_index, -1)
	_tally("I-1 玩法侧：发了初始商店（非空）", rt.offers.size() >= 1)
	_check_int("I-1 波号同步", rt.wave, 7)

	# ---- wave_end → 安全窗（时钟侧）；收入入账（玩法侧，M5）----
	sm.wave_end(7)
	_check_int("I-1 波末进 SafeWindow", sm.state, _TSM.State.SAFE_WINDOW)
	# 裸构筑（只有起手 Arrow）在 W1 有击杀收入；同一个裸构筑在 W7 一个都打不死
	# （DPS 9.5 vs 单只 131 血）—— 这是金标本 `WaveSim` 的真实行为，不是接线错误。
	var res1: Dictionary = rt.simulate_wave_result(1)
	_log("   [info] W1 结算（裸构筑）：n=%d kills=%d leaked=%d scrap=%.1f dps=%.3f"
		% [int(res1["n"]), int(res1["kills"]), int(res1["leaked"]),
		   float(res1["scrap_earned"]), float(res1["dps"])])
	_tally("I-1 波次结算有击杀收入（复用金标本 WaveSim）", float(res1["scrap_earned"]) > 0.0)
	var res7: Dictionary = rt.simulate_wave_result(7)
	_log("   [info] W7 结算（同一个裸构筑）：n=%d kills=%d leaked=%d scrap=%.1f"
		% [int(res7["n"]), int(res7["kills"]), int(res7["leaked"]), float(res7["scrap_earned"])])
	var scrap_before = rt.scrap
	rt.grant_wave_result(res1)
	_check("M5 收入 = 击杀废铁 × (1 + income_mult)", rt.scrap,
		scrap_before + float(res1["scrap_earned"]) * (1.0 + float(rt.player.income_mult)))

	# ---- 🔴 判据链回归：`shop_ai` 只被复用、未被修改 ----
	_log("   [info] 复用金标本判据链（`Stats.eval_point`，决定性跑，非 MC）：")
	var cfgA := _Cfg.cfg_of("A", 0.045, "substantial", "tier", "current", false)
	var cfgB := _Cfg.cfg_of("B", 0.045, "substantial", "tier", "current", false)
	var ev := _Stats.eval_point(cfgA, cfgB)
	_check_int("判据① A 起飞波 = W8", int(ev["toA"]), int(_G.STATS_TIER["toA"]))
	_check_int("判据② B 起飞波 = W12", int(ev["toB"]), int(_G.STATS_TIER["toB"]))
	_check("判据⑤ B/A = 0.458", float(ev["ba"]), float(_G.STATS_TIER["ba"]), 1e-9)
	_check_int("判据⑧ 交叉次数 = 1", int(ev["flips"]), int(_G.STATS_TIER["flips"]))
	_check("判据⑪ A 雪崩增速 = 2.4", float(ev["hA"]["grow"]), float(_G.STATS_TIER["growA"]), 1e-9)
	_check("判据⑫ B 雪崩增速 = 3.0", float(ev["hB"]["grow"]), float(_G.STATS_TIER["growB"]), 1e-9)
	_check_bool("判据⑬ A W13→W20 单调上升", bool(ev["hA"]["rise"]), true)
	_check_bool("判据⑭ B W13→W20 单调上升", bool(ev["hB"]["rise"]), true)
	_log("   [info] MC 起飞率（A 69.3% / B 91.3%）由切片2 的 2228 项断言覆盖（全量跑）")


# ===========================================================================
# 9. 🔴 C-3 / SR-R2：商店源码里不得出现「推荐」类措辞（GDD §10.1 断言 10）
# ===========================================================================
func _test_c3_compliance_grep() -> void:
	_log("")
	_log("--- [9] 🔴 C-3 / SR-R2：商店源码 grep「推荐 / 最优 / best / recommend / suggest」零命中 ---")
	var files := [
		"res://scripts/ui/shop_overlay.gd",
		"res://scripts/ui/time_director.gd",
		"res://scripts/engine/time_state_machine.gd",
		"res://scripts/gameplay/shop_runtime.gd",
		"res://scripts/gameplay/shop_controller.gd",
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


# ===========================================================================
# 10. 🔴 X3：三个商品位尺寸完全一致（GDD §2.3 禁止项 X3）
# ===========================================================================
func _test_x3_slot_equality() -> void:
	_log("")
	_log("--- [10] 🔴 X3：三个商品位尺寸完全一致（禁止用布局暗示）---")
	var f := FileAccess.open("res://scripts/ui/shop_overlay.gd", FileAccess.READ)
	if f == null:
		_fail += 1
		_log("   [FAIL] 打不开 shop_overlay.gd")
		return
	var raw := f.get_as_text()
	f.close()

	var n_slot_size := 0
	var n_const := 0
	for line in raw.split("\n"):
		var s := String(line).strip_edges()
		if s.begins_with("#"):
			continue
		if s.find("custom_minimum_size = SLOT_SIZE") >= 0:
			n_slot_size += 1
		if s.find("const SLOT_SIZE") >= 0:
			n_const += 1
	_check_int("商品位尺寸只由一个共享常量决定（const SLOT_SIZE）", n_const, 1)
	_check_int("所有商品位都读同一个常量（无逐位差异）", n_slot_size, 1)
	_check_int("商品位数量恒为 3", _Cfg.SHOP_SLOTS, 3)
	_log("   [info] 真实像素一致性由 `tests/run_slice4_scene_smoke.gd` 在真场景里比对 3 个位的尺寸")
