extends RefCounted
##
## headless 断言 —— 扩展包（Extended Pack）· 新塔 / 新强化 / 玩家卡池开关
##
## 背景：`docs/phase6/demo-build.md` 的后续需求「丰富玩法」。
##   🔴 硬约束（control-manifest §1）：`TOWERS` / `ShopAI.CARD_NAMES` 是金标本 SSOT，
##      往里加卡会让 `PyRandom.choices()` 抽卡序列整体偏移 ⇒ MC 金标本全盘作废。
##   故扩展卡**单列成表**（`TowerData.TOWERS_EXT` / `REINF_EXT`），
##   且只进**玩家路线卡池**（`ShopRuntime._build_player_pool()`）——
##   AI 路线仍用金标本原池 ⇒ 默认金标本零扰动。
##
## 断言口径：
##   A 数据表结构（表存在 / 条数 / 键集合一致）
##   B 新塔数值可查（dps / tag / rng / slow）
##   C 老塔数值**逐位不变**（改动前 = Arrow 10·22 / Cannon 7·18 / Frost 5·0.30）
##   D 强化 tag 匹配（新 tag 自成流派，老 tag 不受影响）
##   E 卡种判定（扩展卡必须被识别为 tower / reinforce，否则买卡会走错分支）
##   F 卡池开关（默认 6 张 → 开启 10 张 → 关闭回 6 张，含静态缓存清理）
##   G 追加顺序（扩展卡必须**追加在末尾**，不改变老卡的累积区间起点）
##
## 跑法：
##   <godot> --headless --path . --script res://tests/run_tests.gd -- extpack
##

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _TD := preload("res://scripts/data/tower_data.gd")
const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")

## 改动前的三塔读数（= 金标本 SSOT 原值，本断言用来钉住"老卡一位不动"）。
const OLD_ARROW_DPS := 10.0
const OLD_ARROW_RNG := 22.0
const OLD_CANNON_DPS := 7.0
const OLD_CANNON_RNG := 18.0
const OLD_FROST_DPS := 5.0
const OLD_FROST_SLOW := 0.30
## 玩家池权重和：6 张 = 1 − 0.095(RerollD) = 0.905；10 张 = 0.905 + 0.34 = 1.245
const POOL_TOTAL_6 := 0.905
const POOL_TOTAL_10 := 1.245
const EPS := 1e-9

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


func _check_str(name: String, got: String, want: String) -> void:
	var ok := got == want
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=\"%s\" want=\"%s\"" % ["PASS" if ok else "FAIL", name, got, want])


func _check_float(name: String, got: float, want: float) -> void:
	var ok := absf(got - want) < EPS
	if ok:
		_pass += 1
	else:
		_fail += 1
	# 🔴 GDScript 的 String `%` 不支持 `%g`（只有 f/e/s/d 等）→ 用 `%.17f` 打满精度。
	_log("   [%s] %s  got=%.17f want=%.17f" % ["PASS" if ok else "FAIL", name, got, want])


# ---------------------------------------------------------------------------
#  A · 数据表结构
# ---------------------------------------------------------------------------
func _test_a_tables() -> void:
	_log("---- A 数据表结构 ----")
	_check_int("A1 TOWERS_EXT 塔数", _TD.TOWERS_EXT.size(), 2)
	_check_int("A2 REINF_EXT 强化数", _TD.REINF_EXT.size(), 2)
	_check_int("A3 EXT_WEIGHTS 权重条数", _TD.EXT_WEIGHTS.size(), 4)
	# 卡序与权重表必须一一对应（漏一条 = 抽卡时权重查不到 → 崩）
	var missing := 0
	for nm in _ShopRuntime.EXT_CARD_ORDER:
		if not _TD.EXT_WEIGHTS.has(String(nm)):
			missing += 1
	_check_int("A4 EXT_CARD_ORDER ⊆ EXT_WEIGHTS", missing, 0)
	_check_int("A5 EXT_CARD_ORDER 条数", _ShopRuntime.EXT_CARD_ORDER.size(), 4)
	# 扩展表不得污染主表
	_check_bool("A6 TOWERS 未被写入扩展卡", _TD.TOWERS.has("Lance") or _TD.TOWERS.has("Tesla"), false)
	_check_int("A7 TOWERS 仍只有 3 塔", _TD.TOWERS.size(), 3)


# ---------------------------------------------------------------------------
#  B · 新塔数值可查
# ---------------------------------------------------------------------------
func _test_b_ext_values() -> void:
	_log("---- B 新塔数值可查 ----")
	_check_float("B1 Lance dps", _TD.tower_dps("Lance"), 11.0)
	_check_str("B2 Lance tag", _TD.tower_tag("Lance"), "pierce")
	_check_float("B3 Lance rng", _TD.tower_rng("Lance"), 26.0)
	_check_float("B4 Lance slow", _TD.tower_slow("Lance"), 0.0)
	_check_float("B5 Tesla dps", _TD.tower_dps("Tesla"), 6.0)
	_check_str("B6 Tesla tag", _TD.tower_tag("Tesla"), "shock")
	_check_float("B7 Tesla rng", _TD.tower_rng("Tesla"), 16.0)
	_check_float("B8 Tesla slow", _TD.tower_slow("Tesla"), 0.10)


# ---------------------------------------------------------------------------
#  C · 老塔逐位不变（本轮最关键的回归钉）
# ---------------------------------------------------------------------------
func _test_c_old_unchanged() -> void:
	_log("---- C 老塔数值逐位不变 ----")
	_check_float("C1 Arrow dps", _TD.tower_dps("Arrow"), OLD_ARROW_DPS)
	_check_float("C2 Arrow rng", _TD.tower_rng("Arrow"), OLD_ARROW_RNG)
	_check_str("C3 Arrow tag（无 tag）", _TD.tower_tag("Arrow"), "")
	_check_float("C4 Cannon dps", _TD.tower_dps("Cannon"), OLD_CANNON_DPS)
	_check_float("C5 Cannon rng", _TD.tower_rng("Cannon"), OLD_CANNON_RNG)
	_check_float("C6 Frost dps", _TD.tower_dps("Frost"), OLD_FROST_DPS)
	_check_float("C7 Frost slow", _TD.tower_slow("Frost"), OLD_FROST_SLOW)
	_check_str("C8 FireUp 强化 tag", _TD.reinf_tag("FireUp"), "fire")
	_check_str("C9 FrostUp 强化 tag", _TD.reinf_tag("FrostUp"), "frost")


# ---------------------------------------------------------------------------
#  D · 强化 tag 自成流派
# ---------------------------------------------------------------------------
func _test_d_reinf_tag() -> void:
	_log("---- D 扩展强化 tag ----")
	_check_str("D1 PirUp tag", _TD.reinf_tag("PirUp"), "pierce")
	_check_str("D2 ShkUp tag", _TD.reinf_tag("ShkUp"), "shock")
	# 🔴 强化只对同 tag 塔生效（damage_engine 的 reinf_tag != tower_tag 判定）
	_check_bool("D3 PirUp 对 Lance 生效", _TD.reinf_tag("PirUp") == _TD.tower_tag("Lance"), true)
	_check_bool("D4 ShkUp 对 Tesla 生效", _TD.reinf_tag("ShkUp") == _TD.tower_tag("Tesla"), true)
	_check_bool("D5 PirUp 对 Tesla 无效", _TD.reinf_tag("PirUp") == _TD.tower_tag("Tesla"), false)


# ---------------------------------------------------------------------------
#  E · 卡种判定（错判 = 买建筑卡走成全局卡分支：扣钱、不落塔）
# ---------------------------------------------------------------------------
func _test_e_card_kind() -> void:
	_log("---- E 卡种判定 ----")
	_check_str("E1 Lance → tower", _ShopRuntime._card_kind("Lance"), "tower")
	_check_str("E2 Tesla → tower", _ShopRuntime._card_kind("Tesla"), "tower")
	_check_str("E3 PirUp → reinforce", _ShopRuntime._card_kind("PirUp"), "reinforce")
	_check_str("E4 ShkUp → reinforce", _ShopRuntime._card_kind("ShkUp"), "reinforce")
	# 老卡判定不变（走金标本回落分支）
	_check_str("E5 Arrow → tower（回落）", _ShopRuntime._card_kind("Arrow"), "tower")
	_check_str("E6 FireUp → reinforce（回落）", _ShopRuntime._card_kind("FireUp"), "reinforce")
	_check_str("E7 ScrapUp → econ（回落）", _ShopRuntime._card_kind("ScrapUp"), "econ")


# ---------------------------------------------------------------------------
#  F · 卡池开关（含静态缓存清理）
# ---------------------------------------------------------------------------
func _test_f_pool_switch() -> void:
	_log("---- F 玩家卡池开关 ----")
	# 确保从默认态开始
	_ShopRuntime.set_extended_pack(false)

	var names6: Array = _ShopRuntime.player_card_names().duplicate()
	_check_int("F1 默认池卡数", names6.size(), 6)
	_check_bool("F2 默认池不含 Lance", names6.has("Lance"), false)
	_check_float("F3 默认池权重和", _ShopRuntime.player_pool_total(), POOL_TOTAL_6)
	_check_bool("F4 默认 extended_pack", _ShopRuntime.extended_pack, false)

	_ShopRuntime.set_extended_pack(true)
	var names10: Array = _ShopRuntime.player_card_names().duplicate()
	_check_int("F5 开启池卡数", names10.size(), 10)
	_check_bool("F6 开启池含 Lance", names10.has("Lance"), true)
	_check_bool("F7 开启池含 Tesla", names10.has("Tesla"), true)
	_check_bool("F8 开启池含 PirUp", names10.has("PirUp"), true)
	_check_bool("F9 开启池含 ShkUp", names10.has("ShkUp"), true)
	_check_float("F10 开启池权重和", _ShopRuntime.player_pool_total(), POOL_TOTAL_10)
	_check_int("F11 开启池权重条数一致", _ShopRuntime.player_card_weights().size(), 10)

	# 🔴 静态缓存清理：关闭后必须回 6 张（否则开关静默失效）
	_ShopRuntime.set_extended_pack(false)
	_check_int("F12 关闭后池卡数（缓存已清）", _ShopRuntime.player_card_names().size(), 6)
	_check_float("F13 关闭后权重和", _ShopRuntime.player_pool_total(), POOL_TOTAL_6)

	# 金标本 AI 池恒不受影响（这是"零扰动"的核心断言）
	_check_int("F14 金标本 CARD_NAMES 仍 7 张", _ShopAI.CARD_NAMES.size(), 7)
	_check_bool("F15 金标本池不含扩展卡", _ShopAI.CARD_NAMES.has("Lance"), false)


# ---------------------------------------------------------------------------
#  G · 追加顺序（扩展卡在末尾，老卡累积区间起点不变）
# ---------------------------------------------------------------------------
func _test_g_order() -> void:
	_log("---- G 追加顺序 ----")
	_ShopRuntime.set_extended_pack(false)
	var before: Array = _ShopRuntime.player_card_names().duplicate()
	_ShopRuntime.set_extended_pack(true)
	var after: Array = _ShopRuntime.player_card_names().duplicate()

	var same_prefix := true
	for i in range(before.size()):
		if String(before[i]) != String(after[i]):
			same_prefix = false
			break
	_check_bool("G1 前 6 张顺序不变（累积区间起点不动）", same_prefix, true)

	var tail_ok := true
	for i in range(_ShopRuntime.EXT_CARD_ORDER.size()):
		if String(after[before.size() + i]) != String(_ShopRuntime.EXT_CARD_ORDER[i]):
			tail_ok = false
			break
	_check_bool("G2 扩展卡按 EXT_CARD_ORDER 追加在末尾", tail_ok, true)

	# 权重与名字同序（错位 = 权重张冠李戴）
	var w: Array = _ShopRuntime.player_card_weights()
	_check_float("G3 扩展首卡权重对应 Lance", float(w[before.size()]), 0.09)

	# 复位，避免影响同一进程内后续套件
	_ShopRuntime.set_extended_pack(false)


# ---------------------------------------------------------------------------
#  汇总
# ---------------------------------------------------------------------------
func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》扩展包 · 新塔 / 新强化 / 玩家卡池断言（headless）")
	_log("约束：金标本 TOWERS / CARD_NAMES 一位不动；扩展卡只进玩家路线")
	_log("=".repeat(78))

	_test_a_tables()
	_test_b_ext_values()
	_test_c_old_unchanged()
	_test_d_reinf_tag()
	_test_e_card_kind()
	_test_f_pool_switch()
	_test_g_order()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 扩展包 —— 新塔可查、老塔逐位不变、卡池开关可逆、金标本池零污染")
	else:
		_log("[NG] 有 %d 项未过 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0
