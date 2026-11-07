extends RefCounted
##
## 卡包（Card Pack）—— 玩家路线卡池的**流派编排单位**
## ---------------------------------------------------------------------------
## 需求（2026-11-07 v0.3）：卡包 = 玩家路线卡池的**建筑调色板**
##   （选包 = 选这局能造哪几座塔，而不是选几张效果卡）。
##   · v0.1：5 包 × 2 张（塔 + 强化），选 3 包 = 6 张 —— 卡太少。
##   · v0.2：7 包 × 6 张（塔 + 强化 + 经济），选 3 包 = 18 张 —— build 完整，但效果卡占半壁。
##   · v0.3（本版）：8 包 × 6 张，**全部是建筑卡** —— 没有强化 / 经济 / 全局卡。
##
## 🔴 为什么本版只收建筑：
##   用户 2026-11-07 拍板「卡包内只有建筑卡，没有效果卡；先用建筑构建玩法，
##   其他效果后续再加」。⇒ 玩法深度必须来自**塔的类型 / 伤害类型 / 群伤单体 / 减速削抗**，
##   而不是从「给塔叠强化层数」里来。强化卡与经济卡的代码/数据**原样保留**
##   （金标本 `ShopAI` 路径仍在用），只是暂时不进任何卡包 ⇒ 玩家池里抽不到。
##
## 🔴 建筑-only 带来的三个直接后果（都已在代码里落地，不是待办）：
##   ① `validate()` 把「非建筑卡混进卡包」判成**结构错误**，防止效果卡被顺手加回来；
##   ② 同一座塔**允许跨包共享**（塔是建筑类型，不是一次性卡牌），跨包重复不再报错；
##   ③ 刷新保底的「骨架卡」= 每包**前 2 张**（流派身份塔）——整包都是塔时若全算骨架，
##      保底永远命中 = 等于没有保底。
##
## 🔴 卡池稀释（实测依据，见 keyword-adaptation §0/§7.4）：
##   池 7→10 张（+43% 零效果白板）实测 A −8.0pp / B −11.0pp，pity 只是止损阀不是扩容许可。
##   本版单池 = 3 包**并集去重**后约 9~12 张（塔跨包共享 ⇒ 比 v0.2 的 18 张更窄）。
##
## 🔴 数据边界（control-manifest §5）：数值只在 `tower_data.gd` / `shop_ai.gd` 定义一次。
##   本文件只回答「谁和谁一包」「几包可用」「几波解锁」，**不写任何数值**；
##   权重一律现查（`card_weight()`），所以不会出现「卡包表写 0.17、金标本写 0.13」的漂移。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → **不写 `class_name`**，调用方 preload。
##

const _TD := preload("res://scripts/data/tower_data.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")

## 🔴 每局可携带的卡包数：3 包 × 6 张**建筑**（并集去重后约 9~12 张塔）。
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
## 每包 6 张 = 一条**能独立成型的建筑线**（2026-11-07 调整：卡包**只收建筑卡**）：
##   · 全部 6 张都是塔：没有强化卡、没有经济卡、没有全局卡。
##   · 🔴 选包 = 选「塔的调色板」：决定本局能造哪几座塔，打法由**塔的类型 / 伤害类型 /
##      站位**决定，而不是靠强化卡叠数值。
##   · 🔴 一张塔可以出现在多个包里（`is_shared_card` 对所有塔返回 true）——
##      塔是「建筑类型」，不是「一次性卡牌」；跨包共享是刻意设计（基础塔人人可用）。
##   · 🔴 包的身份 = **伤害构成**：物理 / 魔法 / 真实，配合单体 / 群伤 / 减速 / 削抗。
##      tag 现在只影响 Sunder / Hex 的破抗光环（与 combat-types GDD 一致）。
##   · ⚠️ 强化卡 / 经济卡（FireUp… / ScrapUp）**暂时退出玩家池**，效果层后续再加：
##      代码与数据保留（金标本路径仍在用），只是不再进任何卡包。
const PACKS: Array = [
	{
		"id": "core", "name": "泛用包", "tag_line": "三类型基础 · 无流派承诺",
		"cards": ["Arrow", "Cannon", "Frost", "Lance", "Tesla", "Oblivion"],
		"unlock_wave": 0,
	},
	{
		"id": "cinder", "name": "熔炉包", "tag_line": "物理群伤 · 破甲收尾",
		"cards": ["Cannon", "Ember", "Maul", "Sunder", "Arrow", "Javelin"],
		"unlock_wave": 0,
	},
	{
		"id": "rime", "name": "霜序包", "tag_line": "魔法减速 · 控场清场",
		"cards": ["Frost", "Icicle", "Tesla", "Bolt", "Hex", "Rune"],
		"unlock_wave": 0,
	},
	{
		"id": "pierce", "name": "穿甲包", "tag_line": "远程单体 · 真实补刀",
		"cards": ["Lance", "Javelin", "Arrow", "Cannon", "Oblivion", "Void"],
		"unlock_wave": 6,
	},
	{
		"id": "arc", "name": "电弧包", "tag_line": "近身爆发 · 群伤压制",
		"cards": ["Tesla", "Bolt", "Ember", "Maul", "Icicle", "Frost"],
		"unlock_wave": 12,
	},
	{
		"id": "sunder", "name": "破甲包", "tag_line": "削物抗 · 物理倾泻",
		"cards": ["Sunder", "Maul", "Cannon", "Ember", "Javelin", "Hex"],
		"unlock_wave": 16,
	},
	{
		"id": "hex", "name": "咒术包", "tag_line": "魔法清场 · 真实收尾",
		"cards": ["Hex", "Rune", "Frost", "Icicle", "Oblivion", "Void"],
		"unlock_wave": 18,
	},
	{
		"id": "true", "name": "湮灭包", "tag_line": "真实穿透 · 克制高抗",
		"cards": ["Oblivion", "Void", "Arrow", "Frost", "Sunder", "Hex"],
		"unlock_wave": 20,
	},
]


## 跨包共享：**所有建筑卡都可以跨包重复**（塔是建筑类型，不是一次性卡牌）。
##   保留这个函数是为了让 `validate()` 与旧调用点的语义不变：
##   「卡跨包重复」在建筑-only 口径下不是错误，只有「非建筑卡混进卡包」才是错误。
static func is_shared_card(nm: String) -> bool:
	return _TD.TOWERS.has(nm) or _TD.TOWERS_EXT.has(nm)



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


## 🆕 本局「骨架卡」= 所选包里每包的**前 2 张**（流派核心塔 + 第二塔）。
##   刷新保底（`shop_runtime._apply_reroll_pity`）用这个集合判定：手动刷新若 3 张里
##   一张骨架卡都没有，强制补一张，保证「本局主打的塔」不被共享基础塔淹没。
##   🔴 为什么取「前 2 张」而不是全包：建筑-only 口径下整包都是塔，若全算骨架，
##      保底永远命中 = 等于没有保底。前 2 张是包的身份卡（见 PACKS 注释）。
static func skeleton_cards(sel: Array) -> Array:
	var out: Array = []
	for pid in sel:
		var cards := cards_of(String(pid))
		for i in mini(2, cards.size()):
			var s := String(cards[i])
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
## 返回错误串数组；空 = 结构合法。建筑-only 口径下的检查项：
##   ① 每包张数 = CARDS_PER_PACK；
##   ② 🔴 **每张卡都必须是建筑**（`TOWERS` / `TOWERS_EXT`）—— 强化卡 / 经济卡 /
##      全局卡混进卡包直接判错（2026-11-07 拍板：卡包只收建筑）；
##   ③ 每张卡都能查到权重（= 不是幽灵卡）；
##   ④ 不含 RerollD（空卡，玩家池历来排除）；
##   ⑤ 每座塔都要有包可归（否则它永远抽不到 = 死内容）；
##   ⑥ unlock_wave 按包序单调不降（UI 的"第 N 包起解锁"读起来才顺）。
##   🔴 跨包重复不再是错误：塔是建筑类型，同一座塔可以出现在多个包里
##      （见 `is_shared_card()`）。
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
		for nm in cards:
			var s := String(nm)
			if s == "RerollD":
				errs.append("卡包 %s 含 RerollD（空卡，玩家池不得出现）" % pid)
				continue
			if not (_TD.TOWERS.has(s) or _TD.TOWERS_EXT.has(s)):
				errs.append("卡包 %s 的 %s 不是建筑卡（卡包只收建筑）" % [pid, s])
				continue
			seen[s] = pid
			if card_weight(s) <= 0.0:
				errs.append("塔 %s 查不到权重（主表与扩展表都没有）" % s)
	# ⑤ 每座塔都要有包可归
	for nm in _TD.TOWERS.keys():
		if not seen.has(String(nm)):
			errs.append("塔 %s 不在任何卡包里（会变成永远抽不到）" % String(nm))
	for nm in _TD.TOWERS_EXT.keys():
		if not seen.has(String(nm)):
			errs.append("扩展塔 %s 不在任何卡包里" % String(nm))
	return errs
