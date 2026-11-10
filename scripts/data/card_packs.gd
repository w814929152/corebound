extends RefCounted
##
## 卡包（Card Pack）—— 玩家路线卡池的**流派编排单位**
## ---------------------------------------------------------------------------
## 需求（2026-11-07 v0.3）：卡包 = 玩家路线卡池的**建筑调色板**
##   （选包 = 选这局能造哪几座塔，而不是选几张效果卡）。
##   · v0.1：5 包 × 2 张（塔 + 强化），选 3 包 = 6 张 —— 卡太少。
##   · v0.2：7 包 × 6 张（塔 + 强化 + 经济），选 3 包 = 18 张 —— build 完整，但效果卡占半壁。
##   · v0.4（本版）：8 包 × 10 张，**全部是建筑卡** —— 每包可独立组成流派 build。
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
##   ③ 刷新保底的「骨架卡」= 每包**第 1 张**（成长引擎）——整包都是塔时若全算骨架，
##      保底永远命中 = 等于没有保底。
##
## 🔴 卡池稀释（实测依据，见 keyword-adaptation §0/§7.4）：
##   池 7→10 张（+43% 零效果白板）实测 A −8.0pp / B −11.0pp，pity 只是止损阀不是扩容许可。
##   每局池 = 所选 3 包共 30 张；熔炉包和霜序包各额外增加 1 张（最多 32 张）。
##
## 🔴 数据边界（control-manifest §5）：数值只在 `tower_data.gd` / `shop_ai.gd` 定义一次。
##   本文件只回答「谁和谁一包」「几包可用」「几波解锁」，**不写任何数值**；
##   权重一律现查（`card_weight()`），所以不会出现「卡包表写 0.17、金标本写 0.13」的漂移。
##
## 🆕 v2 地区口径（2026-11-08）：解锁判据从「历史最佳波次」改为「**守住该地区**」
##   （`design/gdd/campaign-v2-overseer.md` · §9 接线清单第 4 项）。由开关
##   `unlock_by_region` 控制，**默认 false = 老口径逐位不变**；`boot.gd` 在玩家路线打开。
##   7 个地区包 ↔ 7 个地区 1:1（`REGION_ORDER`），`core` 是中枢起点科技不占名额。
##   🔴 「用该地区原生科技守该地区」由此成立：`stage_region` 让该包**本关借用**可用，
##      通关后进 `owned_regions` 才永久入手 —— 不用"通关前就把奖励发给你"，
##      也不用"没打过就永远打不过"（那会让首关无科技可用）。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → **不写 `class_name`**，调用方 preload。
##

const _TD := preload("res://scripts/data/tower_data.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
## 🆕 v2 地区口径（2026-11-08）：`lock_hint()` 要读地区中文名与「哪一关打出这个包」。
##   🔴 只读常量（`REGION_NAMES` / `DECK_UNLOCK_STAGE`），不引用 `campaign.gd` 的状态 →
##      本文件仍是纯数据 + 纯函数，无循环依赖（`campaign_data.gd` 不反向 preload 本文件）。
const _CampaignData := preload("res://scripts/data/campaign_data.gd")

## 🔴 每局可携带的卡包数：3 包 × 10 张**建筑** = **30 张卡**（一卡一包，无需去重）。
const PICKS_PER_RUN := 3

## 卡包基础张数；熔炉包和霜序包各额外收录一座专属塔，共 11 张。UI 按实际卡池计数。
##   🔴 10 = 80 张卡 ÷ 8 包 的结果，见 `PACKS` 上方注释。
const CARDS_PER_PACK := 10

## 🔴 2026-11-07 用户拍板（B 方案）：**全部卡包开局即开放** —— 选包 = 选流派，
##   不再用「历史最佳波次」逐包解锁（那是早期为了「失败也有产出」设计的节奏阀）。
##   · 打开：8 包全部可选，每局任选 3 包（build 自由组合，内容一次全可见）；
##   · 关闭（改 false）：回到「最佳波次解锁」老口径，`unlock_wave` 数据原样保留；
##   · `unlock_wave` 字段**不删**——它是设计资产，也是老口径回滚的依据；
##     只有 `unlocked_ids()` / `next_unlock_wave()` 认这个开关。
##   ⚠️ 用 `static var` 而非 const：headless 断言需要临时切回老口径验一遍解锁曲线。
static var all_packs_open: bool = true

## 🔴 解锁判据 v2（2026-11-08）：**守住地区 → 入手该地区科技**。
##   剧情口径（`design/gdd/campaign-v2-overseer.md`）：玩家逐地区守卫中继站，
##   用**该地区原生科技**守该地区，守住后那份科技才永久入手。
##   · 关闭（默认 false）：老口径原样 —— `all_packs_open` / `unlock_wave` 两条分支逐位不变；
##   · 打开：`unlocked_ids()` 改读 `owned_regions`（已守地区）∪ `stage_region`（本关借用）。
##     `unlock_wave` 字段仍**不读、不删**（设计资产 + 老口径回滚依据）。
##   🔴 与 `all_packs_open` 的关系：**region 口径优先**。两者同时为真会打架
##      （「全部开放」 vs 「守住才有」），所以一旦打开 region 口径就完全接管。
static var unlock_by_region: bool = false

## 已守住地区的 id（按 `REGION_ORDER` 序）。由 `boot.gd` 从 `Campaign.cleared_regions()` 注入。
static var owned_regions: Array = []

## 本关地区 id（**借用**：用该地区原生科技守卫该地区，通关后才永久入手）。
static var stage_region: String = ""

## 地区 → 卡包是 1:1（`card_packs.PACKS` 的 id 与 `campaign_data.REGION_ORDER` 同名）。
##   `core`（泛用包）= 中枢起点科技，**不占地区名额**，故不在此表。
const REGION_ORDER: Array = ["cinder", "rime", "pierce", "arc", "sunder", "hex", "true"]

## 卡包定义。
##   顺序 = UI 从左到右 = 卡池内卡序（`PyRandom.choices()` 的累积权重按此顺序拼）。
##   `unlock_wave` = 历史最佳波次达到该值即解锁（局外进度见 `run_meta.gd`）。
##     🔴 用「最佳波次」而不是「通关次数」：打不过也应该有推进（campaign-progression §3
##        「失败即产出」）—— 否则首次通关前的内容永远看不见。
##
## 每包 10 张 = 一条完整**建筑线**（卡包只收建筑 + **一张卡只属于一个包**）：
##   · 全部是塔：没有强化卡、没有经济卡、没有全局卡。
##   · 🔴 **每张卡只出现在一个卡包里**（`is_shared_card` 恒 false，`validate()` 会拦重复）。
##     80 张卡 / 每包 10 张 = 8 包，正好一卡一包、不重不漏。
##   · 8 包 × 10 张 = 80 个卡位 = 全部塔。每局选 3 包 = **30 张卡**。
##   · 在原有 48 张基础上新增 32 张（每包补 4 张），覆盖输出、控制、DoT 与流派成长。
##   · 🔴 包的身份 = **伤害构成 + 升级触发**：物理 / 魔法 / 真实，配合单体 / 群伤 / 减速 /
##     削抗 / 登场·整备·阵亡。tag 只影响 Sunder / Hex 的破抗光环。
##   · ⚠️ 强化卡 / 经济卡（FireUp… / ScrapUp）**暂时退出玩家池**，效果层后续再加：
##      代码与数据保留（金标本路径仍在用），只是不再进任何卡包。
const PACKS: Array = [
	{
		"id": "core", "name": "泛用包", "tag_line": "泛用输出 · 赏金 · 类型转换",
		"cards": ["Foundry", "Arrow", "Cannon", "Frost", "Scout", "Kinetic", "Ranger", "Sentry", "Catapult", "Harrier"],
		"unlock_wave": 0,
	},
	{
		"id": "cinder", "name": "熔炉包", "tag_line": "火：灼烧 · 充能爆发 · 自爆",
		"cards": ["Vanguard", "Ember", "Blaze", "Cinder", "Pyre", "Maul", "Furnace", "Wildfire", "Ashen", "Hellfire", "Pyroclasm"],
		"unlock_wave": 0,
	},
	{
		"id": "rime", "name": "霜序包", "tag_line": "冰：整备升级 · 减速控场",
		"cards": ["Drillmaster", "Icicle", "Glacier", "Hail", "Permafrost", "Purity", "Snowfall", "Shard", "Whiteout", "Avalanche", "Icehunter"],
		"unlock_wave": 0,
	},
	{
		"id": "pierce", "name": "穿甲包", "tag_line": "远射贯穿 · 流血 · 阵亡升级",
		"cards": ["Martyr", "Lance", "Javelin", "Ballista", "Sniper", "Arcane", "Longbow", "Needle", "Hemorrhage", "Impaler"],
		"unlock_wave": 6,
	},
	{
		"id": "arc", "name": "电弧包", "tag_line": "电：弹射链 · 减速 · 击杀升级",
		"cards": ["Thunder", "Tesla", "Bolt", "Storm", "Arc", "Spark", "Coil", "Overcharge", "Thunderhead", "Circuit"],
		"unlock_wave": 12,
	},
	{
		"id": "sunder", "name": "破甲包", "tag_line": "削物抗 · 流血 · 攻防光环",
		"cards": ["Drummer", "Sunder", "Breaker", "Shatter", "Ruin", "Quake", "Rend", "Crusher", "Bastion", "Siege"],
		"unlock_wave": 18,
	},
	{
		"id": "hex", "name": "咒术包", "tag_line": "debuff 易伤 +20% · 削魔抗 · DoT",
		"cards": ["Omen", "Hex", "Rune", "Curse", "Plague", "Wither", "Executioner", "Blight", "Malison", "Hexer"],
		"unlock_wave": 24,
	},
	{
		"id": "true", "name": "湮灭包", "tag_line": "真实 · 击杀升级 · 召唤 · 觉醒",
		"cards": ["Null", "Oblivion", "Void", "Exile", "Rift", "Necro", "Eraser", "Obliterator", "Soulpiercer", "Wraith"],
		"unlock_wave": 30,
	},
]


## 🔴 2026-11-07 用户拍板：**一张卡只能出现在一个卡包里**。
##   所以这里恒返回 false；`validate()` 会把任何跨包重复判成结构错误。
static func is_shared_card(nm: String) -> bool:
	# 保留函数签名（调用点不变），但建筑-only + 一卡一包口径下不存在共享卡。
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


## 该包是否属于「地区科技包」（`core` 不是：它是中枢起点科技）。
static func is_region_pack(pack_id: String) -> bool:
	return REGION_ORDER.has(String(pack_id))


## 🔴 region 口径的唯一注入点（玩家路线专用）。
##   `owned` = 已守地区 id（乱序 / 含未知 id 都会被规整成 `REGION_ORDER` 序）；
##   `borrowed_region` = 本关地区（"" = 不借用）。
##   🔴 关掉 region 口径时**必须**调 `set_region_progress([], "")` 把残留清干净 ——
##      否则静态变量跨局残留，测试里的"老口径"会读到上一局注入的地区。
static func set_region_progress(owned: Array, borrowed_region: String = "") -> void:
	var arr: Array = []
	for r in REGION_ORDER:
		if owned.has(String(r)):
			arr.append(String(r))
	owned_regions = arr
	var br := String(borrowed_region)
	stage_region = br if REGION_ORDER.has(br) else ""


## 本关「借用」该包（地区科技：守此地时可用，守住后才永久入手）。
##   🔴 已入手就不算借用 —— 否则重打已守地区时 UI 会一直显示"本关借用"，
##      玩家会以为这包还没到手（而它其实早就在池子里了）。
static func is_borrowed(pack_id: String) -> bool:
	if not unlock_by_region or stage_region == "":
		return false
	var pid := String(pack_id)
	return pid == stage_region and not owned_regions.has(pid)


## 单包解锁判定 —— **所有查询的唯一入口**（`unlocked_ids` / `lock_hint` 共用，防漂移）。
##   分支顺序：region 口径 → 全开 → 最佳波次。
static func is_pack_open(pack_id: String, best_wave: int) -> bool:
	var pid := String(pack_id)
	if not has_pack(pid):
		return false
	if unlock_by_region:
		# 泛用包 = 中枢起点科技：不靠任何地区，恒开（否则开局 0 包，直接卡死）。
		if not is_region_pack(pid):
			return true
		return owned_regions.has(pid) or is_borrowed(pid)
	if all_packs_open:
		return true
	return best_wave >= unlock_wave(pid)


## 历史最佳波次 → 已解锁的包 id（保持包序）。
##   🔴 `all_packs_open` = true 时**不看最佳波次**，8 包全给（见文件头的拍板注释）。
##   🔴 `unlock_by_region` = true 时**不看最佳波次**，看「已守地区 ∪ 本关借用」。
static func unlocked_ids(best_wave: int) -> Array:
	var out: Array = []
	for p in PACKS:
		var pid := String(p["id"])
		if is_pack_open(pid, best_wave):
			out.append(pid)
	return out


## 锁定态提示文案（UI 专用）。已解锁 / 借用中 / 无锁 → ""。
##   🔴 两种口径的文案必须分开：region 口径下说「到达 W6」是**错的**，会误导玩家去刷波次。
static func lock_hint(pack_id: String, best_wave: int) -> String:
	if is_pack_open(pack_id, best_wave):
		return ""
	if unlock_by_region:
		var st := _CampaignData.deck_unlock_stage(String(pack_id))
		if st == "":
			return "未登记解锁关卡"
		var nm := String(_CampaignData.REGION_NAMES.get(String(pack_id), String(pack_id)))
		# 🔴 不写「解锁」两个字：选包瓦片只有 156px 可用宽（16px 字 ≈ 9 字上限），
		#    「守住「永冻科考站」解锁」= 11 字会被裁掉后半截（实测）。地区名本身
		#    就是"还没到手"的含义，省掉动词反而更短更清楚。
		return "守住 %s" % nm
	return "到达 W%d 解锁" % unlock_wave(pack_id)


## 借用态提示文案（UI 专用）：本关可用的「该地区原生科技」。非借用 → ""。
static func borrow_hint(pack_id: String) -> String:
	if not is_borrowed(pack_id):
		return ""
	return "本关借用以守卫此地 · 守住后永久入手"


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
	if _TD.CARD_PACK_WEIGHTS.has(card):
		return float(_TD.CARD_PACK_WEIGHTS[card])
	return 0.0


## 🆕 本局「骨架卡」= 所选包里每包的**第 1 张**（流派核心塔）。
##   刷新保底（`shop_runtime._apply_reroll_pity`）用这个集合判定：手动刷新若 3 张里
##   一张骨架卡都没有，强制补一张，保证「本局主打的塔」不被稀释。
##   🔴 取每包第 1 张 = 包的成长引擎（见 PACKS 注释）。
static func skeleton_cards(sel: Array) -> Array:
	var out: Array = []
	for pid in sel:
		var cards := cards_of(String(pid))
		if cards.is_empty():
			continue
		var s := String(cards[0])
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
##   ① 基础张数 = CARDS_PER_PACK，熔炉包和霜序包各另加一张专属塔；
##   ② 🔴 **每张卡都必须是建筑**（`TOWERS` / `TOWERS_EXT`）—— 强化卡 / 经济卡 /
##      全局卡混进卡包直接判错（2026-11-07 拍板：卡包只收建筑）；
##   ③ 每张卡都能查到权重（= 不是幽灵卡）；
##   ④ 不含 RerollD（空卡，玩家池历来排除）；
##   ⑤ 每座塔都要有包可归（否则它永远抽不到 = 死内容）；
##   ⑥ unlock_wave 按包序单调不降（UI 的"第 N 包起解锁"读起来才顺）；
##   ⑦ 🔴 **一张卡只能出现在一个卡包里**（2026-11-07 拍板 —— 包的身份由此成立）。
static func validate() -> Array:
	var errs: Array = []
	var seen := {}                      # 卡 → 所属包 id
	var prev_unlock := -1
	for p in PACKS:
		var pid := String(p.get("id", ""))
		if pid == "":
			errs.append("存在缺 id 的卡包")
			continue
		var cards: Array = p.get("cards", [])
		var expected := CARDS_PER_PACK + (1 if pid in ["cinder", "rime"] else 0)
		if cards.size() != expected:
			errs.append("卡包 %s 张数 = %d（应为 %d）" % [pid, cards.size(), expected])
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
			# ⑦ 一卡一包
			if seen.has(s):
				errs.append("卡 %s 同时出现在 %s 与 %s（一张卡只能属于一个包）" % [
					s, String(seen[s]), pid])
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
	# ⑧ 🆕 v2 地区口径（2026-11-08）：地区包 ↔ 地区必须 1:1，且都登记了「哪一关打出」。
	#   🔴 为什么放进 validate：这类错误**不会崩**，只会让某个瓦片永远锁着或永远拿不到 ——
	#      UI 上看起来"正常"，玩家却少了整个流派。必须由数据自检拦住。
	if _CampaignData.REGION_ORDER.size() != REGION_ORDER.size():
		errs.append("地区表长度不一致：CardPacks.REGION_ORDER=%d / CampaignData.REGION_ORDER=%d" % [
			REGION_ORDER.size(), _CampaignData.REGION_ORDER.size()])
	else:
		for i in REGION_ORDER.size():
			if String(_CampaignData.REGION_ORDER[i]) != String(REGION_ORDER[i]):
				errs.append("地区表顺序不一致：第 %d 位 %s ≠ %s" % [
					i, String(REGION_ORDER[i]), String(_CampaignData.REGION_ORDER[i])])
	for rid in REGION_ORDER:
		var r := String(rid)
		if not has_pack(r):
			errs.append("地区 %s 没有对应卡包（region 口径下玩家永远拿不到它）" % r)
			continue
		if _CampaignData.deck_unlock_stage(r) == "":
			errs.append("地区包 %s 未在 CampaignData.DECK_UNLOCK_STAGE 登记解锁关卡" % r)
	# ⑨ 每个包都必须有解锁途径：要么是中枢起点科技 `core`，要么是某个地区包。
	for p in PACKS:
		var pid2 := String(p.get("id", ""))
		if pid2 != "" and pid2 != "core" and not is_region_pack(pid2):
			errs.append("卡包 %s 既不是 core 也不在 REGION_ORDER（没有解锁途径）" % pid2)
	return errs
