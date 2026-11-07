extends RefCounted
##
## 卡包（Card Pack）—— 玩家路线卡池的**流派编排单位**
## ---------------------------------------------------------------------------
## 需求（2026-11-07 v0.2）：每个卡包 = 一条**能独立成型的完整 build**
##   （王者万象棋 / 东方梦符祭的羁绊式编排：选包 = 选一套，而不是选几张卡名）。
##   · v0.1（上一版）：5 包 × 2 张（塔 + 强化），每局选 3 包 = 6 张 —— 卡太少，单包不成体系。
##   · v0.2（本版）：7 包 × 6 张，每局选 3 包 = 18 张 —— 每包含
##      核心塔 + 第二塔 + 强化×2 + 经济 + 泛用配塔，自成一个完整流派。
##
## 🔴 为什么每包 6 张（而不是 2 张 / 4 张）：
##   「完整 build」需要同时覆盖三阶段——开局（有塔可造）、中期（有强化可叠、第二塔可扩）、
##   成型（有经济滚动 + 兜底站位）。6 张 = 2 塔（核心 + 第二）+ 2 强化（双叠）+ 1 经济 + 1 泛用，
##   是最小的「自洽闭环」。少于 6 张必然缺一环，沦为「选几张卡」而不是「选一套流派」。
##
## 🔴 卡池稀释的对冲（实测依据，见 keyword-adaptation §0/§7.4）：
##   池 7→10 张（+43% 零效果白板）实测 A −8.0pp / B −11.0pp，pity 只是止损阀不是扩容许可。
##   本版池 18 张看似翻了近 3 倍，但稀释被**三件事**对冲：
##     ① 选包即筛池：未选的 4 包（24 张）根本不进池，池 = 3 包并集 = 18 张，
##        且这 18 张是**同主题自洽**的（不是 18 张散卡）；
##     ② 商店槽位随选包扩容（shop_runtime 动态 SHOP_SLOTS）：3 包时 3→4 位，
##        命中率不因池深而崩；
##     ③ 包内权重倾斜：经济/第二强化稀有，核心塔高频，build 骨架优先出现。
##
## 🔴 数据边界（control-manifest §5）：数值只在 `tower_data.gd` / `shop_ai.gd` 定义一次。
##   本文件只回答「谁和谁一包」「几包可用」「几波解锁」，**不写任何数值**；
##   权重一律现查（`card_weight()`），所以不会出现「卡包表写 0.17、金标本写 0.13」的漂移。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → **不写 `class_name`**，调用方 preload。
##

const _TD := preload("res://scripts/data/tower_data.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")

## 🔴 每局可携带的卡包数：3 包 × 6 张 = **18 张**。
##   （v0.1 是 3 包 × 2 张 = 6 张；本版扩容，但用「选包筛池 + 槽位扩容 + 权重倾斜」对冲稀释。）
const PICKS_PER_RUN := 3

## 每包固定张数（自测断言钉死；UI 按它算「本局卡池 N 张」）。
const CARDS_PER_PACK := 6

## 🔴 2026-11-07 用户拍板（B 方案）：**全部卡包开局即开放** —— 选包 = 选流派，
##   不再用「历史最佳波次」逐包解锁（那是早期为了「失败也有产出」设计的节奏阀）。
##   · 打开：8 包全部可选，每局任选 3 包（build 自由组合，内容一次全可见）；
##   · 关闭（改 false）：回到「最佳波次解锁」老口径，`unlock_wave` 数据原样保留；
##   · `unlock_wave` 字段**不删**——它是设计资产，也是老口径回滚的依据；
##     只有 `unlocked_ids()` / `next_unlock_wave()` 认这个开关。
##   ⚠️ 用 `static var` 而非 const：headless 断言需要临时切回老口径验一遍解锁曲线。
static var all_packs_open: bool = true

## 卡包定义。
##   顺序 = UI 从左到右 = 卡池内卡序（`PyRandom.choices()` 的累积权重按此顺序拼）。
##   `unlock_wave` = 历史最佳波次达到该值即解锁（局外进度见 `run_meta.gd`）。
##     🔴 用「最佳波次」而不是「通关次数」：打不过也应该有推进（campaign-progression §3
##        「失败即产出」）—— 否则首次通关前的内容永远看不见。
##
## 每包 6 张 = 一条**能独立成型的 build 路线**（万象棋 / 梦符祭的羁绊式编排）：
##   · [核心塔, 第二塔, 强化A, 强化B, 经济, 泛用配塔] —— 2 塔可造、2 强化可叠、1 经济滚动、1 兜底站位。
##   · 🔴 每包 = **单一流派**（一个 tag 一条线），不是大杂烩：选包 = 选这条流派。
##   · 🔴 泛用卡（Arrow / ScrapUp）**跨包共享**（多流派都要兜底塔 + 通用经济），
##      流派专属卡（塔 + 强化）只在本流派包出现一次 —— 这正是「羁绊共享」的编排。
##   · 🔴 基石包 = 「泛用 + 经济」路线（无标记塔无强化，靠经济滚雪球 + 多塔站位），
##      是所有流派的通用起点，而非第 8 条 tag 线。
const PACKS: Array = [
	{
		"id": "core", "name": "基石包", "tag_line": "泛用主塔 · 经济滚雪球",
		"cards": ["Arrow", "Cannon", "Frost", "ScrapUp", "FireUp", "FrostUp"],
		"unlock_wave": 0,
	},
	{
		"id": "cinder", "name": "熔炉包", "tag_line": "火：双塔灼烧 · 溅射清场",
		"cards": ["Cannon", "Ember", "FireUp", "FireUp2", "ScrapUp", "Arrow"],
		"unlock_wave": 0,
	},
	{
		"id": "rime", "name": "霜序包", "tag_line": "冰：双塔减速 · 冻结控场",
		"cards": ["Frost", "Icicle", "FrostUp", "FrostUp2", "ScrapUp", "Arrow"],
		"unlock_wave": 0,
	},
	{
		"id": "pierce", "name": "穿甲包", "tag_line": "穿甲：远程狙击 · 近身连射",
		"cards": ["Lance", "Javelin", "PirUp", "PirUp2", "ScrapUp", "Arrow"],
		"unlock_wave": 6,
	},
	{
		"id": "arc", "name": "电弧包", "tag_line": "电：近身溅射 · 单体爆发",
		"cards": ["Tesla", "Bolt", "ShkUp", "ShkUp2", "ScrapUp", "Arrow"],
		"unlock_wave": 12,
	},
	{
		"id": "sunder", "name": "破甲包", "tag_line": "破甲：削物抗 · 物理群伤",
		"cards": ["Sunder", "Maul", "SunUp", "SunUp2", "ScrapUp", "Arrow"],
		"unlock_wave": 16,
	},
	{
		"id": "hex", "name": "咒术包", "tag_line": "咒术：削魔抗 · 魔法清场",
		"cards": ["Hex", "Rune", "HexUp", "HexUp2", "ScrapUp", "Arrow"],
		"unlock_wave": 18,
	},
	{
		"id": "true", "name": "湮灭包", "tag_line": "真实：无视抗性 · 克制高抗怪",
		"cards": ["Oblivion", "Void", "TrueUp", "TrueUp2", "ScrapUp", "Arrow"],
		"unlock_wave": 20,
	},
]


## 🆕 跨包共享卡（「羁绊共享」编排，万象棋/梦符祭同款）：这些卡**允许**出现在多个包里。
##   · Arrow / ScrapUp：通用兜底塔 + 通用经济，所有流派都要。
##   · Cannon / Frost / FireUp / FrostUp：基石包作为「双流派入门」也会带上它们，
##     与各自专精包（cinder / rime）共享 —— 这是刻意设计（新手包 = 体验两种基础流派）。
##   validate() 的「卡跨包重复」检查对共享卡**豁免**；流派专精塔（Lance/Tesla/Sunder/Hex
##   及第二塔 Ember/Icicle/Javelin/Bolt/Maul/Rune）与第二强化卡仍只在本包出现。
static func is_shared_card(nm: String) -> bool:
	if nm == "Arrow" or nm == "ScrapUp":
		return true
	if nm == "Cannon" or nm == "Frost" or nm == "FireUp" or nm == "FrostUp":
		return true
	return false



# ---------------------------------------------------------------------------
#  查表
# ---------------------------------------------------------------------------
static func all_ids() -> Array:
	var out: Array = []
	for p in PACKS:
		out.append(String(p["id"]))
	return out


static func has_pack(pack_id: String) -> bool:
	return not get_pack(pack_id).is_empty()


## 未知 id 返回 `{}`（调用方据此判定"无此包"，不要静默当成空包）。
static func get_pack(pack_id: String) -> Dictionary:
	for p in PACKS:
		if String(p["id"]) == pack_id:
			return p
	return {}


static func pack_name(pack_id: String) -> String:
	var p := get_pack(pack_id)
	return "" if p.is_empty() else String(p["name"])


## 某包的卡（返回副本：调用方可以随意改，不会污染常量表）。
static func cards_of(pack_id: String) -> Array:
	var p := get_pack(pack_id)
	if p.is_empty():
		return []
	return (p["cards"] as Array).duplicate()


## 全部卡包的并集（顺序 = 包序 → 包内序）。自测用它校验"没有卡漏在包外"。
static func all_cards() -> Array:
	var out: Array = []
	for p in PACKS:
		for nm in (p["cards"] as Array):
			if not out.has(String(nm)):
				out.append(String(nm))
	return out


static func unlock_wave(pack_id: String) -> int:
	var p := get_pack(pack_id)
	return 0 if p.is_empty() else int(p["unlock_wave"])


## 历史最佳波次 → 已解锁的包 id（保持包序）。
##   🔴 `all_packs_open` = true 时**不看最佳波次**，8 包全给（见文件头的拍板注释）。
static func unlocked_ids(best_wave: int) -> Array:
	var out: Array = []
	for p in PACKS:
		if all_packs_open or best_wave >= int(p["unlock_wave"]):
			out.append(String(p["id"]))
	return out


## 本局"必须选几个包"：已解锁不足 3 包时全带（早期没有选择余地，也不该少带）。
static func required_picks(best_wave: int) -> int:
	return mini(PICKS_PER_RUN, unlocked_ids(best_wave).size())


## 是否需要玩家做选择（= 已解锁数 > 必须选的数）。UI 用它决定要不要弹选包界面。
static func needs_selection(best_wave: int) -> bool:
	return unlocked_ids(best_wave).size() > required_picks(best_wave)


## 卡的实际权重：先查金标本主表，再查扩展表。两张表都没有 → 0（自测会把它判成错）。
static func card_weight(card: String) -> float:
	if _ShopAI.WEIGHTS.has(card):
		return float(_ShopAI.WEIGHTS[card])
	if _TD.EXT_WEIGHTS.has(card):
		return float(_TD.EXT_WEIGHTS[card])
	return 0.0


## 🆕 本局「骨架卡」= 所选包里的**流派塔 + 强化卡**（build 成型的**关键卡**）。
##   刷新保底（`shop_runtime._apply_reroll_pity`）用这个集合判定：18 张池里，
##   玩家刷新若 3 张里一张骨架卡都没有，就强制补一张，保证 build 骨架不被稀释淹没。
##   🔴 排除经济卡（ScrapUp）与泛用配塔（Arrow）—— 它们不是「build 成型」的必要条件，
##      保底它们反而会让玩家拿不到真正的流派核心（流派塔 / 强化）。
##   🔴 派生识别（不靠固定下标）：凡查 `TOWERS` / `TOWERS_EXT` 是塔，凡查 `REINF*` 是强化。
static func skeleton_cards(sel: Array) -> Array:
	var out: Array = []
	for pid in sel:
		for nm in cards_of(String(pid)):
			var s := String(nm)
			if s == "Arrow" or s == "ScrapUp":
				continue                         # 泛用卡不算骨架（见上）
			if _TD.TOWERS.has(s) or _TD.TOWERS_EXT.has(s):
				if not out.has(s):
					out.append(s)
			elif _TD.REINF.has(s) or _TD.REINF_EXT.has(s) or _TD.REINF_EXT2.has(s):
				if not out.has(s):
					out.append(s)
	return out


## 按包序重排 id（不做过量 / 解锁过滤）。卡池顺序必须只由包序决定 —— 否则
##   玩家"先点哪个包"会改变 `PyRandom.choices()` 的累积区间，同一套包抽出不同结果。
static func sort_by_pack_order(ids: Array) -> Array:
	var out: Array = []
	for p in PACKS:
		var pid := String(p["id"])
		if ids.has(pid) and not out.has(pid):
			out.append(pid)
	return out


## 规整玩家选择：剔除未知 / 未解锁 / 重复，按包序重排，超量按包序截断。
##   不补齐（缺的包由 UI 要求玩家自己点）—— "默认帮你选满"会把选择变成走过场。
static func normalize(sel: Array, best_wave: int) -> Array:
	var unlocked := unlocked_ids(best_wave)
	var out: Array = []
	for p in PACKS:
		var pid := String(p["id"])
		if not unlocked.has(pid):
			continue
		if sel.has(pid) and not out.has(pid):
			out.append(pid)
	var req := required_picks(best_wave)
	while out.size() > req:
		out.remove_at(out.size() - 1)
	return out


static func is_valid_selection(sel: Array, best_wave: int) -> bool:
	var n := normalize(sel, best_wave)
	if n.size() != required_picks(best_wave):
		return false
	if n.size() != sel.size():
		return false
	for i in sel.size():
		if String(sel[i]) != String(n[i]):
			return false
	return true


# ---------------------------------------------------------------------------
#  自检（数据表自身的结构错误 —— 由 `tests/run_card_pack_asserts.gd` §A 调用）
# ---------------------------------------------------------------------------
## 返回错误串数组；空 = 结构合法。检查项：
##   ① 每包张数 = CARDS_PER_PACK；② 卡不跨包重复；③ 每张卡都能查到权重（= 不是幽灵卡）；
##   ④ 不含 RerollD（空卡，玩家池历来排除）；⑤ 现有玩家池全集都有归属（不漏卡）；
##   ⑥ unlock_wave 按包序单调不降（UI 的"第 N 包起解锁"读起来才顺）；
##   ⑦ 每包至少含 1 座塔（否则整包都是"投不出去的强化"）。
##   🆕 ⑧ 每包内强化卡的 tag 必须有对应塔（否则买了强化卡没塔可投 = 死牌）。
static func validate() -> Array:
	var errs: Array = []
	var seen := {}
	var prev_unlock := -1
	for p in PACKS:
		var pid := String(p.get("id", ""))
		if pid == "":
			errs.append("存在缺 id 的卡包")
			continue
		var cards: Array = p.get("cards", [])
		if cards.size() != CARDS_PER_PACK:
			errs.append("卡包 %s 张数 = %d（应为 %d）" % [pid, cards.size(), CARDS_PER_PACK])
		var uw := int(p.get("unlock_wave", 0))
		if uw < prev_unlock:
			errs.append("卡包 %s 的解锁波次 %d 小于前一包的 %d（应单调不降）" % [pid, uw, prev_unlock])
		prev_unlock = maxi(prev_unlock, uw)
		# ⑦ 每包至少 1 座塔
		var has_tower := false
		for nm in cards:
			var s := String(nm)
			if _TD.TOWERS.has(s) or _TD.TOWERS_EXT.has(s):
				has_tower = true
			if s == "RerollD":
				errs.append("卡包 %s 含 RerollD（空卡，玩家池不得出现）" % pid)
			if seen.has(s):
				# 🆕 泛用卡（Arrow/ScrapUp）允许跨包共享（「羁绊共享」编排）；
				#    流派专属卡跨包重复才是错误。
				if not is_shared_card(s):
					errs.append("卡 %s 同时在 %s 与 %s" % [s, String(seen[s]), pid])
				continue
			seen[s] = pid
			if card_weight(s) <= 0.0:
				errs.append("卡 %s 查不到权重（主表与扩展表都没有）" % s)
		if not has_tower:
			errs.append("卡包 %s 不含任何塔（整包都是投不出去的强化）" % pid)
		# ⑧ 包内强化卡的 tag 必须有对应塔
		for nm in cards:
			var s := String(nm)
			if _TD.REINF.has(s) or _TD.REINF_EXT.has(s) or _TD.REINF_EXT2.has(s):
				var tg := _TD.reinf_tag(s)
				var host_found := false
				for nm2 in cards:
					var s2 := String(nm2)
					if (_TD.TOWERS.has(s2) or _TD.TOWERS_EXT.has(s2)) \
							and _TD.tower_tag(s2) == tg:
						host_found = true
						break
				if not host_found:
					errs.append("卡包 %s 的强化卡 %s（tag %s）没有同包塔可投" % [pid, s, tg])
	# ⑤ 玩家池全集（排除 RerollD）必须全部有包可归
	for nm in _ShopAI.CARD_NAMES:
		var s := String(nm)
		if s == "RerollD":
			continue
		if not seen.has(s):
			errs.append("玩家池的卡 %s 不在任何卡包里（会变成永远抽不到）" % s)
	for nm in _TD.EXT_WEIGHTS.keys():
		if not seen.has(String(nm)):
			errs.append("扩展卡 %s 不在任何卡包里" % String(nm))
	for nm in _TD.TOWERS_EXT.keys():
		if not seen.has(String(nm)):
			errs.append("扩展塔 %s 不在任何卡包里" % String(nm))
	for nm in _TD.REINF_EXT2.keys():
		if not seen.has(String(nm)):
			errs.append("第二强化卡 %s 不在任何卡包里" % String(nm))
	return errs
