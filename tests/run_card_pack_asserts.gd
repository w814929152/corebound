extends RefCounted
##
## headless 断言 —— 卡包（Card Pack）· 分池 / 选包 / 解锁 / 发牌
##
## 背景（2026-11-07 用户需求）：把卡牌整理成不同卡包；解锁全部卡包后，开局前选择若干卡包，
##   避免卡池过大刷不到想要的卡，同时把「这局养什么」变成开局决策。
##
## 🔴 设计约束（`design/gdd/keyword-adaptation.md` §7.4 实测）：
##   玩家池 7 → 10 张 → A 起飞率 −8.0pp / B −11.0pp（且单张"能用但弱"的卡更狠，−10.3pp/张）。
##   ⇒ 分池后**每局卡池恒为 6 张**（3 包 × 2 张），张数不涨，构成由玩家选。
##
## 断言口径（v0.2 · 每包 6 张 = 完整 build）：
##   A 数据表结构：7 包 × 6 张，无 RerollD、每张都能查到权重、现有池无漏卡、
##     每包至少 1 塔、包内强化卡的 tag 有对应塔；泛用卡（Arrow/ScrapUp）允许跨包共享
##   B 解锁口径：最佳波次 → 已解锁包数 → 必须选几包（≤3 全带，>3 才需要选）
##   C 选择规整：未知 / 未解锁 / 重复 / 超量 一律被剔除，顺序按包序
##   D 卡池派生：所选包并集 = 卡池（顺序、权重、总和都对得上）；骨架卡 = 塔+强化
##   E 老口径不破：`set_active_packs([])` 时仍是 6 张 / 0.905，扩展包开关仍是 10 张 / 1.245
##   F 发牌：真 runtime 连开 8 波，offers **必须全部**落在所选池内；pity 卡不得越池
##   G 界面结构：7 个卡包位、同尺寸（X3）、按钮四态自定义、文本 ≥16px、锁定态禁用
##
## 跑法：
##   <godot> --headless --path . --script res://tests/run_tests.gd -- cardpack
##

const _Packs := preload("res://scripts/data/card_packs.gd")
const _RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _TD := preload("res://scripts/data/tower_data.gd")
const _CardText := preload("res://scripts/data/card_text.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
## 🆕 触发型建筑（登场 / 整备 / 阵亡 加等级）
const _TowerEffects := preload("res://scripts/engine/tower_effects.gd")
const _PackUI := preload("res://scripts/ui/pack_select_overlay.gd")

## 老口径常量（与 `run_ext_pack_asserts.gd` 同值，改动前基线）
const POOL_TOTAL_6 := 0.905
const POOL_TOTAL_14 := 1.575
const FONT_MIN := 16

var _pass := 0
var _fail := 0


func _log(s: String) -> void:
	print(s)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
	var tail := "" if detail == "" else "  " + detail
	_log("   [%s] %s%s" % ["PASS" if cond else "FAIL", name, tail])


func _eq_int(name: String, got: int, want: int) -> void:
	_ok(name, got == want, "got=%d want=%d" % [got, want])


func _eq_float(name: String, got: float, want: float, eps: float = 1e-9) -> void:
	_ok(name, absf(got - want) <= eps, "got=%.12f want=%.12f" % [got, want])


func _eq_arr(name: String, got: Array, want: Array) -> void:
	var same := got.size() == want.size()
	if same:
		for i in got.size():
			if String(got[i]) != String(want[i]):
				same = false
				break
	_ok(name, same, "got=%s want=%s" % [str(got), str(want)])


func run_all() -> bool:
	# 🔴 测试环境：不读不写真实存档（`user://card_packs.json`）
	_RunMeta.set_save_enabled(false)
	_RunMeta.reset_progress()
	_ShopRuntime.set_active_packs([])
	_ShopRuntime.set_extended_pack(false)

	_log("")
	_log("=".repeat(78))
	_log("卡包（Card Pack）· 分池 / 选包 / 解锁 / 发牌")
	_log("基准：每包 6 张建筑卡 · 每局 3 包 · 解锁按最佳波次")
	_log("=".repeat(78))

	_test_a_table()
	_test_b_unlock()
	_test_c_normalize()
	_test_d_pool()
	_test_e_legacy()
	_test_f_deal()
	_test_g_ui()
	_test_h_triggers()
	_test_i_bounty()
	_test_j_bounce()
	_test_k_pierce()
	_test_l_splash()
	_test_m_aspd()
	_test_n_convert()
	_test_o_death_blast()
	_test_p_summon()

	# 🔴 收尾：把静态状态还原成默认，避免污染同进程内的后续套件
	_ShopRuntime.set_active_packs([])
	_ShopRuntime.set_extended_pack(false)
	_RunMeta.reset_progress()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 卡包分池 —— 张数恒定、选择有约束、老口径逐位不变")
	else:
		_log("[NG] 有 %d 项未过 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0


# ---------------------------------------------------------------------------
#  A 数据表结构
# ---------------------------------------------------------------------------
func _test_a_table() -> void:
	_log("")
	_log("--- [A] 数据表：8 包 × 6 张**建筑卡**，一卡一包 / 无漏塔 / 无效果卡 ---")
	var errs := _Packs.validate()
	_ok("A1 validate() 无错误", errs.is_empty(), str(errs))
	_eq_int("A2 卡包数", _Packs.PACKS.size(), 8)
	_eq_int("A3 每局携带包数", _Packs.PICKS_PER_RUN, 3)
	_eq_int("A4 每包张数", _Packs.CARDS_PER_PACK, 6)
	# 并集 = 全部塔（建筑-only 口径：卡包里不再有强化 / 经济卡）
	var all := _Packs.all_cards()
	var towers_n := _TD.TOWERS.size() + _TD.TOWERS_EXT.size()
	_eq_int("A5 并集张数 = 全部塔数", all.size(), towers_n)
	var missing: Array = []
	for nm in _TD.TOWERS.keys():
		if not all.has(String(nm)):
			missing.append(String(nm))
	for nm in _TD.TOWERS_EXT.keys():
		if not all.has(String(nm)):
			missing.append(String(nm))
	_ok("A6 每座塔都有卡包归属", missing.is_empty(), str(missing))
	# 🔴 本次改动的核心红线：卡包内**只有建筑卡**
	var non_tower: Array = []
	for p in _Packs.PACKS:
		for nm in (p["cards"] as Array):
			var s := String(nm)
			if not (_TD.TOWERS.has(s) or _TD.TOWERS_EXT.has(s)):
				non_tower.append("%s/%s" % [String(p["id"]), s])
	_ok("A6b 卡包内 0 张效果卡（强化 / 经济 / 全局都不许进包）",
		non_tower.is_empty(), str(non_tower))
	# 🔴 一卡一包：同一张卡不得出现在两个包里
	var seen_pack := {}
	var dup: Array = []
	for p in _Packs.PACKS:
		for nm in (p["cards"] as Array):
			var s := String(nm)
			if seen_pack.has(s):
				dup.append("%s@%s/%s" % [s, String(seen_pack[s]), String(p["id"])])
			else:
				seen_pack[s] = String(p["id"])
	_ok("A6c 一张卡只属于一个包%s" % ("" if dup.is_empty() else " → " + str(dup)), dup.is_empty())
	_eq_int("A6d 卡位总数 = 8 包 × 6 张", seen_pack.size(), 48)
	_ok("A7 不含 RerollD", not all.has("RerollD"))
	# 塔与强化成对（每个包内至少有一座塔）
	var bad_pairs: Array = []
	for p in _Packs.PACKS:
		var has_tower := false
		for nm in (p["cards"] as Array):
			if _TD.TOWERS.has(String(nm)) or _TD.TOWERS_EXT.has(String(nm)):
				has_tower = true
		if not has_tower:
			bad_pairs.append(String(p["id"]))
	_ok("A8 每包至少含 1 座塔（否则整包都是「投不出去的强化」）", bad_pairs.is_empty(), str(bad_pairs))
	# 权重可查（现查，不在卡包表里二次定义）
	var bad_w: Array = []
	for nm in all:
		if _Packs.card_weight(String(nm)) <= 0.0:
			bad_w.append(String(nm))
	_ok("A9 每张卡权重 > 0（金标本 / 扩展表现查）", bad_w.is_empty(), str(bad_w))


# ---------------------------------------------------------------------------
#  B 解锁口径
# ---------------------------------------------------------------------------
func _test_b_unlock() -> void:
	_log("")
	_log("--- [B] 解锁口径：默认全开（2026-11-07 拍板）· 回滚开关下按最佳波次 ---")
	# ① 默认口径：8 包全开，W0 就能任选 3 包（内容一次全可见，选包 = 选流派）
	_Packs.all_packs_open = true
	_eq_int("B1 全开：W0 已解锁 8 包", _Packs.unlocked_ids(0).size(), 8)
	_eq_int("B2 全开：W0「必须选」= 3", _Packs.required_picks(0), 3)
	_ok("B3 全开：开局需要弹选包界面", _Packs.needs_selection(0))
	_ok("B4 全开：任意波次都是 8 包",
		_Packs.unlocked_ids(7).size() == 8 and _Packs.unlocked_ids(20).size() == 8)
	_eq_int("B5 全开：没有「下一个解锁波次」", _RunMeta.next_unlock_wave(), -1)

	# ② 老口径（开关关闭）：数据曲线与判定原样保留，一行回滚即可复活
	_Packs.all_packs_open = false
	_eq_int("B6 老口径 W0 解锁 3 包", _Packs.unlocked_ids(0).size(), 3)
	_eq_int("B7 老口径 W6 → 4 包（穿甲）", _Packs.unlocked_ids(6).size(), 4)
	_eq_int("B8 老口径 W12 → 5 包（电弧）", _Packs.unlocked_ids(12).size(), 5)
	_eq_int("B9 老口径 W18 → 6 包（破甲）", _Packs.unlocked_ids(18).size(), 6)
	_eq_int("B10 老口径 W24 → 7 包（咒术）", _Packs.unlocked_ids(24).size(), 7)
	_eq_int("B11 老口径 W30 → 8 包（湮灭）", _Packs.unlocked_ids(30).size(), 8)
	_ok("B12 老口径 3 包时不用选", not _Packs.needs_selection(0))
	_ok("B13 老口径 4 包时需要选", _Packs.needs_selection(6))
	_eq_int("B14 老口径 5 包时「必须选」仍是 3", _Packs.required_picks(12), 3)
	_Packs.all_packs_open = true

	# ③ 进度层：record_run 只升不降；全开下不再产生「新解锁卡包」
	_RunMeta.reset_progress()
	_RunMeta.record_run(false, 7)
	_eq_int("B15 失败也推进：最佳波次 = 7", _RunMeta.best_wave(), 7)
	_RunMeta.record_run(false, 3)
	_eq_int("B16 最佳波次只升不降", _RunMeta.best_wave(), 7)
	var fresh: Array = _RunMeta.record_run(true, 12)
	_eq_int("B17 胜场累计", _RunMeta.wins(), 1)
	_eq_int("B18 全开下不再有「新解锁卡包」", fresh.size(), 0)


# ---------------------------------------------------------------------------
#  C 选择规整
# ---------------------------------------------------------------------------
func _test_c_normalize() -> void:
	_log("")
	_log("--- [C] 选择规整：未知 / 未解锁 / 重复 / 超量 ---")
	var n1 := _Packs.normalize(["rime", "core", "cinder"], 0)
	_eq_arr("C1 顺序按包序（core→cinder→rime）", n1, ["core", "cinder", "rime"])
	var n2 := _Packs.normalize(["core", "nope", "core", "cinder"], 0)
	_eq_arr("C2 丢弃未知 / 重复", n2, ["core", "cinder"])
	# 「未解锁剔除」只在老口径下有意义（默认全开时 8 包都合法）
	_Packs.all_packs_open = false
	var n3 := _Packs.normalize(["core", "cinder", "rime", "pierce", "arc"], 0)
	_eq_int("C3 未解锁的包被剔除（老口径 W0 只有 3 包）", n3.size(), 3)
	_ok("C8 含未解锁包不合法（老口径）",
		not _Packs.is_valid_selection(["pierce", "core", "cinder"], 0))
	_Packs.all_packs_open = true
	var n4 := _Packs.normalize(["core", "cinder", "rime", "pierce"], 12)
	_eq_int("C4 超量截断到 required=3", n4.size(), 3)
	_eq_arr("C5 截断按包序（留下前 3 个）", n4, ["core", "cinder", "rime"])
	_ok("C6 合法选择通过校验", _Packs.is_valid_selection(["core", "cinder", "rime"], 0))
	_ok("C7 不足 3 包不合法", not _Packs.is_valid_selection(["core", "cinder"], 0))
	_ok("C9 全开：任意 3 包都合法（含原本锁定的穿甲包）",
		_Packs.is_valid_selection(["core", "cinder", "pierce"], 0))


# ---------------------------------------------------------------------------
#  D 卡池派生
# ---------------------------------------------------------------------------
func _test_d_pool() -> void:
	_log("")
	_log("--- [D] 卡池 = 所选包并集（顺序 / 权重 / 总和 / 骨架卡）---")
	_ShopRuntime.set_active_packs(["core", "cinder", "arc"])
	var names: Array = _ShopRuntime.player_card_names()
	# core   = [Arrow,Cannon,Frost,Scout,Kinetic,Foundry]
	# cinder = [Ember,Maul,Vanguard,Blaze,Cinder,Pyre]
	# arc    = [Tesla,Bolt,Storm,Arc,Spark,Thunder]
	_eq_arr("D1 卡池顺序 = 包序 → 包内序（一卡一包，无需去重）",
		names,
		["Arrow", "Cannon", "Frost", "Scout", "Kinetic", "Foundry",
		 "Ember", "Maul", "Vanguard", "Blaze", "Cinder", "Pyre",
		 "Tesla", "Bolt", "Storm", "Arc", "Spark", "Thunder"])
	_eq_int("D2 卡池张数 = 3 包 × 6 张 = 18", names.size(), 18)
	# 权重和 = 各卡权重之和（现查，不硬编码）
	var want := 0.0
	for nm in names:
		want += _Packs.card_weight(String(nm))
	_eq_float("D3 权重和 = 各卡权重之和", _ShopRuntime.player_pool_total(), want)
	_eq_int("D4 权重条数与卡数一致", _ShopRuntime.player_card_weights().size(), names.size())
	# 换包必须立即生效（静态缓存清理）；顺序只跟包序走，不跟"点选顺序"走
	_ShopRuntime.set_active_packs(["pierce", "arc", "core"])
	_eq_arr("D7 换包后卡池立即变化（按包序）", _ShopRuntime.player_card_names(),
		["Arrow", "Cannon", "Frost", "Scout", "Kinetic", "Foundry",
		 "Lance", "Javelin", "Martyr", "Ballista", "Sniper", "Arcane",
		 "Tesla", "Bolt", "Storm", "Arc", "Spark", "Thunder"])
	# 与扩展包开关同时开：卡包模式优先，扩展包不叠加（卡包表已含全部卡）
	_ShopRuntime.set_extended_pack(true)
	var n_ext_on := _ShopRuntime.player_card_names().size()
	_ShopRuntime.set_extended_pack(false)
	var n_ext_off := _ShopRuntime.player_card_names().size()
	_eq_int("D8 卡包模式下 extended_pack 不影响卡池（开/关一致）", n_ext_on, n_ext_off)
	_ShopRuntime.set_active_packs([])
	# 骨架卡 = 每包第 1 张（流派身份塔）
	var skel := _Packs.skeleton_cards(["cinder"])
	_eq_arr("D9 骨架卡 = 包内第 1 张（熔炉包 = Ember）", skel,
		["Ember"])
	var skel3 := _Packs.skeleton_cards(["core", "rime"])
	_eq_int("D10 骨架卡跨包去重（2 包 × 1 张）", skel3.size(), 2)


# ---------------------------------------------------------------------------
#  E 老口径不破（默认 / 扩展包）
# ---------------------------------------------------------------------------
func _test_e_legacy() -> void:
	_log("")
	_log("--- [E] 未选包（老口径）：6 张 / 0.905 · 扩展包 14 张 / 1.575 ---")
	_ShopRuntime.set_active_packs([])
	_eq_int("E1 默认玩家池 6 张", _ShopRuntime.player_card_names().size(), 6)
	_eq_float("E2 默认权重和 0.905", _ShopRuntime.player_pool_total(), POOL_TOTAL_6)
	_ShopRuntime.set_extended_pack(true)
	# 🔴 扩展包张数 = 6 基础 + EXT_CARD_ORDER 条数（并行会话可能继续扩，动态现查不自燃）
	var exp_n := 6 + _ShopRuntime.EXT_CARD_ORDER.size()
	var exp_total := 0.905
	for nm in _ShopRuntime.EXT_CARD_ORDER:
		exp_total += _Packs.card_weight(String(nm))
	_eq_int("E3 扩展包张数 = 6 + 扩展卡序", _ShopRuntime.player_card_names().size(), exp_n)
	_eq_float("E4 扩展包权重和 = 0.905 + Σ扩展卡权重", _ShopRuntime.player_pool_total(), exp_total)
	_ShopRuntime.set_extended_pack(false)
	_eq_int("E5 关掉扩展包回 6 张", _ShopRuntime.player_card_names().size(), 6)


# ---------------------------------------------------------------------------
#  F 发牌：offers 必须落在所选池内
# ---------------------------------------------------------------------------
func _test_f_deal() -> void:
	_log("")
	_log("--- [F] 真 runtime 连开 8 波：offers ⊆ 所选池；pity 不越池；刷新保底 ---")
	_ShopRuntime.set_active_packs(["core", "cinder", "rime"])
	var rt = _ShopRuntime.new()
	rt.setup("B", 20260930)
	var pool: Array = _ShopRuntime.player_card_names().duplicate()
	var bad: Array = []
	for w in range(1, 9):
		rt.start_wave(w)
		for nm in rt.offers:
			var s := String(nm)
			if s == "":
				continue
			if not pool.has(s):
				bad.append("W%d:%s" % [w, s])
	_ok("F1 8 波商品位全部在所选池内", bad.is_empty(), str(bad))
	_eq_int("F2 每波恒 3 位", rt.offers.size(), 3)

	# pity 越池：选不含真实塔的包组合（cinder+rime+arc），即便主塔是 Oblivion 也不得把 Void 写进商店
	_ShopRuntime.set_active_packs(["cinder", "rime", "arc"])
	var rt2 = _ShopRuntime.new()
	rt2.setup("B", 20260930)
	var shop: Array = ["Arrow", "Arrow", "Arrow"]
	rt2._apply_pity(shop, "Void")
	_ok("F3 池外保底卡不写入商店（Void 不在本局池）", not shop.has("Void"), str(shop))
	# 池内保底：选含真实塔的包（true），Void 在池内应照常写入
	_ShopRuntime.set_active_packs(["true", "cinder", "rime"])
	var rt3 = _ShopRuntime.new()
	rt3.setup("B", 20260930)
	var shop2: Array = ["Arrow", "Arrow", "Arrow"]
	rt3._apply_pity(shop2, "Void")
	_ok("F4 池内保底卡照常写入", shop2.has("Void"), str(shop2))

	# 刷新保底：卡包模式下，若刷新 3 张里无骨架卡，强制补一张骨架卡（每包前 2 张）
	_ShopRuntime.set_active_packs(["cinder"])
	var rt4 = _ShopRuntime.new()
	rt4.setup("B", 20260930)
	var skel := _Packs.skeleton_cards(["cinder"])
	rt4.offers = ["Maul", "Vanguard", "Blaze"]  # 全是非骨架卡（骨架 = Ember）
	rt4.scrap = 1000.0
	rt4.rerolls = 0
	var ok_reroll: bool = rt4.reroll()
	_ok("F5 卡包模式刷新成功", ok_reroll)
	var has_skel := false
	for nm in rt4.offers:
		if skel.has(String(nm)):
			has_skel = true
	_ok("F6 刷新保底补入骨架卡", has_skel, str(rt4.offers))
	_ShopRuntime.set_active_packs([])


# ---------------------------------------------------------------------------
#  G 界面结构
# ---------------------------------------------------------------------------
func _collect(n: Node, out: Array, type_check: String) -> Array:
	for ch in n.get_children():
		if type_check == "button" and ch is Button:
			out.append(ch)
		elif type_check == "label" and ch is Label:
			out.append(ch)
		_collect(ch, out, type_check)
	return out


func _test_g_ui() -> void:
	_log("")
	_log("--- [G] 选包界面：8 位同尺寸 / 四态自定义 / ≥16px / 锁定态禁用 ---")
	_RunMeta.reset_progress()
	_RunMeta.record_run(false, 6)          # 最佳波次 6 → 解锁 4 包（需要选择）
	var ov = _PackUI.new()
	ov._build()
	_eq_int("G1 卡包位数量", ov._tiles.size(), 8)
	ov.open()
	_eq_int("G2 打开后需要选 3 包", _Packs.required_picks(_RunMeta.best_wave()), 3)

	var sizes: Array = []
	for t in ov._tiles:
		sizes.append((t["btn"] as Button).custom_minimum_size)
	var same := true
	for s in sizes:
		if s != sizes[0]:
			same = false
	_ok("G3 8 个卡包位尺寸完全一致（X3）", same, str(sizes))

	var btns: Array = _collect(ov, [], "button")
	_eq_int("G4 卡包位 + 开始按钮", btns.size(), 9)
	var missing: Array = []
	for b in btns:
		for st in ["normal", "hover", "pressed", "disabled"]:
			if not (b as Button).has_theme_stylebox_override(st):
				missing.append("%s/%s" % [String((b as Button).text), st])
	_ok("G5 全部按钮 × 4 态均自定义（无系统默认控件）", missing.is_empty(), str(missing))

	var small: Array = []
	for l in _collect(ov, [], "label"):
		var fs := int((l as Label).get_theme_font_size("font_size"))
		if fs > 0 and fs < FONT_MIN:
			small.append("%s=%d" % [String((l as Label).text).substr(0, 8), fs])
	_ok("G6 文本 ≥16px", small.is_empty(), str(small))

	# 默认口径：8 包全开 → 全部可用
	var any_locked := false
	for t in ov._tiles:
		if (t["btn"] as Button).disabled:
			any_locked = true
	_ok("G7 全开：8 个卡包位全部可用", not any_locked)

	# 老口径回滚：锁定态仍然禁用（最佳波次 6 → 4 包可用）
	_Packs.all_packs_open = false
	ov._refresh()
	var locked_ok := true
	var locked_n := 0
	for t in ov._tiles:
		var pid := String(t["id"])
		var unlocked: Array = _Packs.unlocked_ids(_RunMeta.best_wave())
		var b: Button = t["btn"]
		if not unlocked.has(pid):
			locked_n += 1
			if not b.disabled:
				locked_ok = false
		elif b.disabled:
			locked_ok = false
	_eq_int("G7b 老口径：锁定的包数 = 4（电弧/破甲/咒术/湮灭）", locked_n, 4)
	_ok("G8 老口径：锁定态禁用 / 解锁态可用", locked_ok)
	_Packs.all_packs_open = true
	ov._refresh()

	# 交互：选满 3 包才能开始；第 4 个被拒绝
	ov._sel = []
	ov._on_tile_pressed("core")
	ov._on_tile_pressed("cinder")
	ov._on_tile_pressed("rime")
	_eq_int("G9 点 3 个包 → 选中 3", ov._sel.size(), 3)
	_ok("G10 选满后开始按钮可用", not ov._start.disabled)
	ov._on_tile_pressed("pierce")
	_eq_int("G11 第 4 个包被拒绝（仍 3 个）", ov._sel.size(), 3)
	ov._on_tile_pressed("core")
	_eq_int("G12 再点一次取消（2 个）", ov._sel.size(), 2)
	_ok("G13 不足 3 包时开始按钮禁用", ov._start.disabled)

	# 确认 → 落盘到内存 → 发出信号
	ov._on_tile_pressed("core")
	var got: Array = []
	ov.packs_confirmed.connect(func(p: Array) -> void: got.append_array(p))
	ov._on_start_pressed()
	_eq_int("G14 确认后发出 selected 3 包", got.size(), 3)
	_eq_arr("G15 记忆上次选包", _RunMeta.selection(), ["core", "cinder", "rime"])
	_ok("G16 确认后界面隐藏", not ov.visible)
	ov.free()
	_RunMeta.reset_progress()

# ---------------------------------------------------------------------------
#  H 触发型建筑：登场 / 整备 / 阵亡 加等级（2026-11-07）
# ---------------------------------------------------------------------------
## 🔴 用户口径：「类似塔的效果 —— 回合开始时 / 防御塔上场时 / 防御塔死亡时增加等级」。
##   本段钉住四件事：①三种时机各自触发；②只影响该影响的塔；③等级封顶 8；
##   ④上限常量为 8（形态满级 / Focus 预热满额同档）。
func _test_h_triggers() -> void:
	_log("")
	_log("--- [H] 触发型建筑：登场 / 整备 / 阵亡 加等级（封顶 8）---")
	_eq_int("H0 触发升级上限 = 8（形态满级）", _TowerEffects.LEVEL_CAP, 8)

	var p = _PS.new()
	p.path = "B"
	p.towers = []
	p.towers.append(_PS.make_tower(0, "Vanguard", 1, {}))
	p.towers.append(_PS.make_tower(1, "Arrow", 1, {}))
	p.towers.append(_PS.make_tower(2, "Drillmaster", 1, {}))

	# ① 登场：只加自己
	var n1 := _TowerEffects.apply_trigger(p, "enter", {"tower": p.towers[0]})
	_eq_int("H1 登场只触发 1 座塔", n1, 1)
	_eq_int("H2 先锋升到 2 级", int(p.towers[0].h), 2)
	_eq_int("H3 登场不影响其它塔", int(p.towers[1].h), 1)

	# ② 整备：每波开始全场 +1
	var n2 := _TowerEffects.apply_trigger(p, "prepare")
	_eq_int("H4 整备触发全场 3 座", n2, 3)
	_eq_int("H5 整备后先锋升到 3 级", int(p.towers[0].h), 3)
	_eq_int("H6 整备后箭塔 2 级", int(p.towers[1].h), 2)

	# ③ 封顶：继续整备到 8 级，再触发不再升
	var n3 := _TowerEffects.apply_trigger(p, "prepare")
	_eq_int("H7 第二次整备全场 3 座都升", n3, 3)
	_eq_int("H8 箭塔升到 3 级", int(p.towers[1].h), 3)
	var guard := 0
	while _TowerEffects.apply_trigger(p, "prepare") > 0 and guard < 64:
		guard += 1
	_eq_int("H9 先锋封顶 8 级", int(p.towers[0].h), 8)
	_eq_int("H10 箭塔封顶 8 级", int(p.towers[1].h), 8)
	_eq_int("H11 封顶后再整备 0 座变化", _TowerEffects.apply_trigger(p, "prepare"), 0)

	# ④ 阵亡：只升其它塔，死者自己不吃
	var p2 = _PS.new()
	p2.path = "B"
	p2.towers = []
	p2.towers.append(_PS.make_tower(0, "Martyr", 1, {}))
	p2.towers.append(_PS.make_tower(1, "Arrow", 1, {}))
	var n4 := _TowerEffects.apply_trigger(p2, "death", {"tower": p2.towers[0]})
	_eq_int("H12 阵亡触发 1 座其它塔", n4, 1)
	_eq_int("H13 箭塔升到 2 级", int(p2.towers[1].h), 2)
	_eq_int("H14 阵亡的塔自身不加级", int(p2.towers[0].h), 1)

# ---------------------------------------------------------------------------
#  I 赏金塔：存活时全队累计击杀到阈值 → 发废料（2026-11-07）
# ---------------------------------------------------------------------------
func _test_i_bounty() -> void:
	_log("")
	_log("--- [I] 赏金塔：存活时全队累计击杀 → 发废料 ---")
	var p = _PS.new()
	p.path = "B"
	p.towers = []
	p.towers.append(_PS.make_tower(0, "Scout", 1, {}))
	p.towers.append(_PS.make_tower(1, "Arrow", 1, {}))
	_eq_int("I1 起始赏金 0", int(p.bounty_scrap), 0)
	for _i in range(9):
		_TowerEffects.on_kill(p)
	_eq_int("I2 9 杀未达阈值（10）", int(p.bounty_scrap), 0)
	_TowerEffects.on_kill(p)
	_eq_int("I3 第 10 杀发 6 废料", int(p.bounty_scrap), 6)
	for _i in range(10):
		_TowerEffects.on_kill(p)
	_eq_int("I4 再 10 杀再发一次（累计 12）", int(p.bounty_scrap), 12)
	p.towers[0].disabled = true
	var before := float(p.bounty_scrap)
	for _i in range(20):
		_TowerEffects.on_kill(p)
	_eq_int("I5 赏金塔阵亡后不再产出", int(p.bounty_scrap), int(before))

# ---------------------------------------------------------------------------
#  J 弹射：子弹跳数 + 等效输出倍率（2026-11-07）
# ---------------------------------------------------------------------------
func _test_j_bounce() -> void:
	_log("")
	_log("--- [J] 弹射：电弧系带跳弹次数，卡面写明 ---")
	_eq_int("J1 Arc 弹射 2 次", _TD.tower_bounce("Arc"), 2)
	_eq_int("J2 Storm 弹射 2 次", _TD.tower_bounce("Storm"), 2)
	_eq_int("J3 Tesla 弹射 1 次", _TD.tower_bounce("Tesla"), 1)
	_eq_int("J4 非电弧塔无弹射（Arrow）", _TD.tower_bounce("Arrow"), 0)
	_ok("J5 Arc 卡面写明「弹射 2 次」", _CardText.describe("Arc").find("弹射 2 次") >= 0)
	_ok("J6 无弹射塔卡面不出现「弹射」", _CardText.describe("Arrow").find("弹射") < 0)

# ---------------------------------------------------------------------------
#  K 贯穿：穿刺系子弹可穿透 N 个敌人（2026-11-07）
# ---------------------------------------------------------------------------
func _test_k_pierce() -> void:
	_log("")
	_log("--- [K] 贯穿：穿刺系子弹穿透敌人数 ---")
	_eq_int("K1 Ballista 贯穿 3 个", _TD.tower_pierce("Ballista"), 3)
	_eq_int("K2 Lance 贯穿 2 个", _TD.tower_pierce("Lance"), 2)
	_eq_int("K3 Javelin 贯穿 1 个", _TD.tower_pierce("Javelin"), 1)
	_eq_int("K4 非穿刺塔无贯穿（Arrow）", _TD.tower_pierce("Arrow"), 0)
	_ok("K5 Ballista 卡面写明「贯穿 3 个」", _CardText.describe("Ballista").find("贯穿 3 个") >= 0)
	_ok("K6 无贯穿塔卡面不出现「贯穿」", _CardText.describe("Arrow").find("贯穿") < 0)

# ---------------------------------------------------------------------------
#  L 溅射：命中后对周围一定范围内的敌人造成伤害（2026-11-07）
# ---------------------------------------------------------------------------
func _test_l_splash() -> void:
	_log("")
	_log("--- [L] 溅射：命中后波及周围 N 个敌人 ---")
	_eq_int("L1 Cinder 溅射 2 个", _TD.tower_splash("Cinder"), 2)
	_eq_int("L2 Omen 溅射 2 个", _TD.tower_splash("Omen"), 2)
	_eq_int("L3 Curse 溅射 1 个", _TD.tower_splash("Curse"), 1)
	_eq_int("L4 非溅射塔（Arrow）", _TD.tower_splash("Arrow"), 0)
	_ok("L5 Cinder 卡面写明「溅射 2 个」", _CardText.describe("Cinder").find("溅射 2 个") >= 0)
	_ok("L6 基础塔 Frost 不带溅射（金标本口径不动）", _TD.tower_splash("Frost") == 0)

# ---------------------------------------------------------------------------
#  M 攻速光环：增加附近塔的攻击速度（2026-11-07）
# ---------------------------------------------------------------------------
func _test_m_aspd() -> void:
	_log("")
	_log("--- [M] 攻速光环：附近塔攻击速度 +20% ---")
	_ok("M1 Drummer 攻速光环 = 0.20", absf(_TD.tower_buff_aspd("Drummer") - 0.20) < 1e-9)
	_ok("M2 普通塔无攻速光环（Arrow）", absf(_TD.tower_buff_aspd("Arrow")) < 1e-9)
	_ok("M3 Drummer 卡面写明「攻速光环」", _CardText.describe("Drummer").find("攻速光环") >= 0)
	var names: Array = []
	for p in _Packs.PACKS:
		for nm in (p["cards"] as Array):
			names.append(String(nm))
	_ok("M4 Drummer 在卡包里（破甲包）", names.has("Drummer"))
	_ok("M5 旧的 Cleave 已不存在于任何卡包", not names.has("Cleave"))

# ---------------------------------------------------------------------------
#  N 相位塔：把最近的塔转成物理 / 魔法 / 纯粹（2026-11-07）
# ---------------------------------------------------------------------------
func _test_n_convert() -> void:
	_log("")
	_log("--- [N] 相位塔：最近塔的伤害类型转换 ---")
	_ok("N1 Kinetic 转物理", _TD.tower_convert("Kinetic") == "physical")
	_ok("N2 Arcane 转魔法", _TD.tower_convert("Arcane") == "magic")
	_ok("N3 Purity 转纯粹", _TD.tower_convert("Purity") == "true")
	_ok("N4 普通塔无转换（Arrow）", _TD.tower_convert("Arrow") == "")
	_ok("N5 Arcane 卡面写明「最近塔转魔法」", _CardText.describe("Arcane").find("最近塔转魔法") >= 0)

	# 功能：Arrow（默认物理）+ Arcane → Arrow 的伤害应计入魔法池
	var geo = _Geo6.build_by_slots(6)
	var cfg: Dictionary = _Cfg.cfg_of("B")
	var p = _PS.new()
	p.path = "B"
	p.towers = []
	p.towers.append(_PS.make_tower(0, "Arrow", 1, {}))
	p.towers.append(_PS.make_tower(1, "Arcane", 1, {}))
	p.n_hist_max = 2
	var byt: Dictionary = _DE.compute_dps(p, cfg, geo).get("dps_by_type", {})
	_ok("N6 转换后物理池归零", absf(float(byt.get("physical", 0.0))) < 1e-9)
	_ok("N7 转换后魔法池 > 0（吃 Arrow 的 dps）", float(byt.get("magic", 0.0)) > 0.0)

	# 无相位塔时：Arrow 仍是物理（零扰动）
	var p2 = _PS.new()
	p2.path = "B"
	p2.towers = []
	p2.towers.append(_PS.make_tower(0, "Arrow", 1, {}))
	p2.n_hist_max = 1
	var byt2: Dictionary = _DE.compute_dps(p2, cfg, geo).get("dps_by_type", {})
	_ok("N8 无相位塔时物理池 > 0", float(byt2.get("physical", 0.0)) > 0.0)

# ---------------------------------------------------------------------------
#  O 死亡爆炸：塔阵亡时对周围敌人造成大额伤害（2026-11-07）
# ---------------------------------------------------------------------------
func _test_o_death_blast() -> void:
	_log("")
	_log("--- [O] 死亡爆炸：阵亡时对周围造成大量伤害 ---")
	_ok("O1 Pyre 爆炸伤害 = 40", absf(_TD.tower_death_blast("Pyre") - 40.0) < 1e-9)
	_ok("O2 Pyre 爆炸半径 = 6.0", absf(_TD.tower_death_blast_r("Pyre") - 6.0) < 1e-9)
	_ok("O3 普通塔无爆炸（Arrow）", absf(_TD.tower_death_blast("Arrow")) < 1e-9)
	_ok("O4 Rift 不带爆炸（只有 Pyre 有）", absf(_TD.tower_death_blast("Rift")) < 1e-9)
	_ok("O5 Pyre 卡面写明「阵亡：爆炸 40」", _CardText.describe("Pyre").find("阵亡：爆炸 40") >= 0)

# ---------------------------------------------------------------------------
#  P 召唤小兵：塔每波召唤可移动单位攻击敌人（2026-11-07）
# ---------------------------------------------------------------------------
func _test_p_summon() -> void:
	_log("")
	_log("--- [P] 召唤小兵：Necro 每波召唤 2 个游魂 ---")
	_eq_int("P1 Necro 召唤数量 = 2", _TD.tower_summon_n("Necro"), 2)
	_ok("P2 Necro 小兵 dps = 8", absf(_TD.tower_summon_dps("Necro") - 8.0) < 1e-9)
	_ok("P3 Necro 小兵存活 10s", absf(_TD.tower_summon_ttl("Necro") - 10.0) < 1e-9)
	_ok("P4 Necro 小兵移动速度 6", absf(_TD.tower_summon_speed("Necro") - 6.0) < 1e-9)
	_eq_int("P5 普通塔不召唤（Arrow）", _TD.tower_summon_n("Arrow"), 0)
	_ok("P6 Necro 卡面写明「召唤游魂作战」", _CardText.describe("Necro").find("召唤游魂作战") >= 0)
	var names: Array = []
	for p in _Packs.PACKS:
		for nm in (p["cards"] as Array):
			names.append(String(nm))
	_ok("P7 Necro 在湮灭包", names.has("Necro"))
	_ok("P8 旧的 Abyss 已不在任何卡包", not names.has("Abyss"))
