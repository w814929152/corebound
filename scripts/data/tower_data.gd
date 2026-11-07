class_name TowerData
extends RefCounted
##
## 塔原型 / 强化卡 / 价格 —— 移植自 design/phase2/numeric-sim/corebound_sim_v03.py
##   TOWERS (L41-45) / REINF (L46) / PRICE (L57)
##
## 🔴 SSOT：这些数字必须与金标本逐位一致，禁止在引擎侧二次定义。
##    Python 的 `tag=None` 在此用空字符串 "" 表示（GDScript 无 None 可用于字典值类型统一）。
##

const TOWERS := {
	"Arrow":  {"dps": 10.0, "tag": "",      "aoe": false, "slow": 0.00, "rng": 22.0},
	"Cannon": {"dps": 7.0,  "tag": "fire",  "aoe": true,  "slow": 0.00, "rng": 18.0},
	"Frost":  {"dps": 5.0,  "tag": "frost", "aoe": false, "slow": 0.30, "rng": 20.0},
}

const REINF := {
	"FireUp":  {"tag": "fire"},
	"FrostUp": {"tag": "frost"},
}

const ECON := {
	"ScrapUp": {},
	"RerollD": {},
}

const PRICE := {"tower": 12.0, "reinforce": 9.0, "econ": 10.0}

# 路径优先级去重后的「会被考虑」的卡（v2 legacy 回归用）
const ALLOWED := {
	"A": ["Cannon", "Frost", "FireUp", "ScrapUp"],
	"B": ["Cannon", "Arrow", "Frost", "FireUp", "FrostUp", "ScrapUp"],
}


# ---------------------------------------------------------------------------
#  🆕 扩展包（Extended Pack）· 2026-11-06
# ---------------------------------------------------------------------------
## 🔴 为什么**单列一张表**而不是往 `TOWERS` 里加条目：
##      `TOWERS` 是金标本逐位对齐的 SSOT（control-manifest §1「塔数值表」）。
##      往 `TOWERS` / `ShopAI.CARD_NAMES` 里塞新卡，会改变 `PyRandom.choices()` 的
##      抽卡序列 ⇒ **MC 金标本全盘偏移**（起飞率、300 局读数全变）⇒ 必须走 ADR + 重签基线。
##      故扩展塔**独立成表**，且只进「玩家路线卡池」
##      （`shop_runtime.player_card_names()` 拼装）——AI 路线 `ShopAI.CARD_NAMES`
##      一字不动 ⇒ **默认金标本零扰动**，连分支都不经过。
##
## 🔴 开关：`shop_runtime.extended_pack`（默认 `false` = 产品未启用口径）。
##      关闭时，下面 6 个查表函数的返回值与改动前**逐位一致**
##      （仅多一次 `has()` 判定，不参与任何浮点运算）。
##
## 🎯 设计意图：现有三塔是「泛用 / 群伤 / 控制」，
##      扩展补上**射程轴**（Lance：最远最强，但独立 tag ⇒ 协同从头攒）
##      与**贴身轴**（Tesla：最近最弱，换 aoe + 微减速）。
##      新塔各带**独立 tag** ⇒ 天然形成新构筑流派，而不是旧卡的上位替代。
const TOWERS_EXT := {
	# 远程狙击：rng 26 > Arrow 22，dps 11 > Arrow 10。
	# 代价 = 独立 tag "pierce" ⇒ 不与 fire / frost 共享 tag 投资，κ 只能靠自己堆。
	"Lance": {"dps": 11.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 26.0, "pierce": 2},
	# 贴身电弧：rng 16 < Cannon 18，dps 6（全场最低），换 aoe + 0.10 减速。
	# 定位 = 堵在暴露位的近身清场，与「肉盾流」站位天然互补。
	"Tesla": {"dps": 6.0, "tag": "shock", "aoe": true, "slow": 0.10, "rng": 16.0, "bounce": 1},
	# 🆕 破甲炮（2026-11-07 · combat-types GDD v0.2）：物理攻击 + 破甲光环（每座减全场物抗）。
	# 定位 = 物攻 build 核心：自身物理直伤，光环放大所有物理塔对 Tank（物抗 0.30）的输出。
	# dps 8 < Cannon 7? 否 —— 刻意压到 8（介于 Arrow 10 与 Cannon 7 之间），因为光环本身
	# 是「团队增益」，单塔面板不能太强，否则纯堆破甲塔自身就能扛，失去「混搭」的构筑意义。
	"Sunder": {"dps": 8.0, "tag": "sunder", "aoe": false, "slow": 0.00, "rng": 19.0},
	# 🆕 诅咒塔（2026-11-07 · combat-types GDD v0.2）：魔法攻击 + 破魔光环（每座减全场魔抗）。
	# 定位 = 魔攻 build 核心：自身魔法伤害，光环放大所有魔法塔对 Rush（魔抗 0.20）的输出。
	# 与 Sunder 对称：dps 6（魔法塔偏低面）、tag "hex"、减魔抗。
	"Hex": {"dps": 6.0, "tag": "hex", "aoe": false, "slow": 0.00, "rng": 18.0},

	# ═══════════════════════════════════════════════════════════════════════════
	# 🆕 流派卡包 · 第二塔（2026-11-07 · card-packs v0.2）：为每个流派包补「第二座同 tag 塔」，
	#    让单个卡包自身能凑齐「2 塔 + 2 强化」的完整 build（王者万象棋 / 梦符祭的羁绊式编排）。
	#   🔴 设计约束（零引擎改动）：全部复用「塔（build/up）」这一种卡种，tag 必须落在
	#      **已有**的 7 个 tag 内（fire/frost/pierce/shock/sunder/hex），否则新塔的强化卡
	#      找不到宿主 = 死牌（`card_text.hosts_of_tag` 会判「无同类塔」）。
	#   🔴 平衡基准：第二塔 dps 刻意**低于**同 tag 主塔（避免上位替代），用 aoe / rng / slow
	#      换差异，让「主塔 + 第二塔」形成互补站位（一近一远 / 一单体一群伤）。
	# ═══════════════════════════════════════════════════════════════════════════
	# 火 · 第二塔：近身喷火，aoe，慢速小怪群（Cannon 是远程溅射，这是贴身灼烧）。
	"Ember": {"dps": 6.0, "tag": "fire", "aoe": true, "slow": 0.00, "rng": 14.0},
	# 冰 · 第二塔：单体强减速，射程近（Frost 是远程减速，这是贴身冰封）。
	"Icicle": {"dps": 4.0, "tag": "frost", "aoe": false, "slow": 0.45, "rng": 15.0},
	# 穿甲 · 第二塔：短程连射，dps 高但射程短（Lance 是远程狙击，这是近身扫射）。
	"Javelin": {"dps": 9.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 17.0, "pierce": 1},
	# 电 · 第二塔：单体高爆发（Tesla 是近身 aoe，这是单体电弧直击）。
	"Bolt": {"dps": 8.0, "tag": "shock", "aoe": false, "slow": 0.00, "rng": 19.0, "bounce": 1},
	# 破甲 · 第二塔：aoe 物理群伤（Sunder 是单体破甲光环，这是群体物理压制）。
	"Maul": {"dps": 7.0, "tag": "sunder", "aoe": true, "slow": 0.00, "rng": 16.0},
	# 咒术 · 第二塔：aoe 魔法（Hex 是单体破魔光环，这是群体魔法清场）。
	"Rune": {"dps": 5.0, "tag": "hex", "aoe": true, "slow": 0.00, "rng": 17.0},

	# ═══════════════════════════════════════════════════════════════════════════
	# 🆕 卡包扩充（2026-11-07 · 「一卡一包」）：48 张卡铺满 8 包 × 6 张。
	#   机制取自 `mechanic-source-index.md` 已整理的两作机制，挑**能落地**的：
	#     登场 / 整备 / 牺牲（见下方触发建筑）、觉醒、经济建筑、减抗光环扩展。
	#   🔴 全部只进玩家路线（卡包），金标本只读 `TOWERS` → 逐位零扰动。
	# ═══════════════════════════════════════════════════════════════════════════
	# ---- 泛用包补位（快 / 远 / 经济）----
	"Scout": {"dps": 6.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 24.0,
		"bounty_kills": 10, "bounty_scrap": 6.0},
	"Mortar": {"dps": 9.0, "tag": "", "aoe": true, "slow": 0.10, "rng": 30.0},
	# 经济建筑（梦符祭「收益」位）：自己不攻击，每波结算时按比例补贴废料。
	"Foundry": {"dps": 0.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 0.0,
		"income": 0.15},
	# ---- 熔炉包补位（火：燃烧 / 尸爆 / 觉醒）----
	"Blaze": {"dps": 7.0, "tag": "fire", "aoe": true, "slow": 0.05, "rng": 15.0},
	"Cinder": {"dps": 9.0, "tag": "fire", "aoe": false, "slow": 0.00, "rng": 17.0, "splash": 2},
	# 觉醒：升到 3 级后伤害 +30%（梦符祭「觉醒」的可落地版本）。
	"Pyre": {"dps": 6.0, "tag": "fire", "aoe": true, "slow": 0.00, "rng": 16.0,
		"awaken": true},
	# ---- 霜序包补位（冰：减速梯度）----
	"Glacier": {"dps": 5.0, "tag": "frost", "aoe": false, "slow": 0.50, "rng": 18.0},
	"Hail": {"dps": 4.0, "tag": "frost", "aoe": true, "slow": 0.25, "rng": 20.0},
	"Permafrost": {"dps": 3.0, "tag": "frost", "aoe": true, "slow": 0.35, "rng": 22.0},
	"Frostbite": {"dps": 7.0, "tag": "frost", "aoe": false, "slow": 0.20, "rng": 14.0, "splash": 1},
	# ---- 电弧包补位（电：从单体到群伤）----
	"Storm": {"dps": 7.0, "tag": "shock", "aoe": true, "slow": 0.05, "rng": 18.0, "bounce": 2},
	"Arc": {"dps": 9.0, "tag": "shock", "aoe": true, "slow": 0.00, "rng": 17.0, "bounce": 2},
	"Spark": {"dps": 8.0, "tag": "shock", "aoe": false, "slow": 0.00, "rng": 20.0, "bounce": 1, "splash": 1},
	"Thunder": {"dps": 10.0, "tag": "shock", "aoe": false, "slow": 0.00, "rng": 22.0, "bounce": 1},
	# ---- 穿甲包补位（远程梯度）----
	"Ballista": {"dps": 12.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 30.0, "pierce": 3},
	"Sniper": {"dps": 10.0, "tag": "pierce", "aoe": false, "slow": 0.10, "rng": 34.0, "pierce": 2},
	"Harpoon": {"dps": 9.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 15.0, "pierce": 1, "splash": 1},
	# ---- 破甲包补位（削物抗光环扩展：tag=sunder 自动计入 `SUNDER_TYPES`）----
	"Breaker": {"dps": 8.0, "tag": "sunder", "aoe": true, "slow": 0.00, "rng": 18.0},
	"Shatter": {"dps": 7.0, "tag": "sunder", "aoe": false, "slow": 0.00, "rng": 20.0},
	"Ruin": {"dps": 9.0, "tag": "sunder", "aoe": true, "slow": 0.00, "rng": 16.0},
	"Cleave": {"dps": 8.0, "tag": "", "aoe": true, "slow": 0.00, "rng": 15.0},
	"Quake": {"dps": 5.0, "tag": "", "aoe": true, "slow": 0.15, "rng": 18.0,
		"buff_def": 0.15},
	# ---- 咒术包补位（削魔抗光环扩展：tag=hex 自动计入 `SUNDER_TYPES`）----
	"Curse": {"dps": 7.0, "tag": "hex", "aoe": false, "slow": 0.00, "rng": 19.0, "splash": 1},
	"Plague": {"dps": 4.0, "tag": "hex", "aoe": true, "slow": 0.00, "rng": 20.0,
		"dot": 4.0},
	"Wither": {"dps": 5.0, "tag": "", "aoe": true, "slow": 0.00, "rng": 17.0,
		"heal": 1.5, "splash": 2},
	"Omen": {"dps": 5.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 21.0,
		"buff_atk": 0.10, "splash": 2},
	# ---- 湮灭包补位（真实伤害）----
	"Exile": {"dps": 7.0, "tag": "true", "aoe": false, "slow": 0.00, "rng": 18.0, "splash": 1},
	"Null": {"dps": 6.0, "tag": "true", "aoe": true, "slow": 0.00, "rng": 16.0,
		"on_kill_lv": true},
	"Rift": {"dps": 8.0, "tag": "true", "aoe": false, "slow": 0.00, "rng": 22.0,
		"awaken": true},
	"Abyss": {"dps": 5.0, "tag": "true", "aoe": true, "slow": 0.10, "rng": 20.0},

	# ═══════════════════════════════════════════════════════════════════════════
	# 🆕 触发型建筑（2026-11-07 · 卡包只收建筑后的升级路线）
	#   用户口径：「类似塔的效果 —— **回合开始时** / **防御塔上场时** / **防御塔死亡时** 增加等级」。
	#   （明确否掉两种做法：光环被动加等级、三合一升星。）
	#   实现 = 事件触发的一次性 +等级，`effect.on` 三选一，`effect.scope` = self / all。
	#   🔴 等级封顶 `TowerEffects.LEVEL_CAP = 8`（触发不会无限叠；合成升级仍无硬上限）。
	#   🔴 只走**玩家路线**（`wave_director` / `shop_runtime`）；金标本走 `wave_sim` 且
	#      只买 `TOWERS` 基础塔 → 本表不进金标本 → 逐位零扰动。
	#   🔴 死亡触发在**当波不生效**（dps 在波首已算死）→ 下一波吃到，见 `tower_effects.gd`。
	# 登场：自身 +1 级（落子即比同名塔高一级，抢开局节奏）。
	"Vanguard": {"dps": 8.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 18.0,
		"effect": {"on": "enter", "lv": 1, "scope": "self"}},
	# 整备：每波开始全场 +1 级（慢速滚雪球，逼玩家先立教官再开波）。
	"Drillmaster": {"dps": 5.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 17.0,
		"effect": {"on": "prepare", "lv": 1, "scope": "all"}},
	# 阵亡：本塔死亡时全场 +1 级（用塔位换等级，下一波生效）。
	"Martyr": {"dps": 6.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 16.0,
		"effect": {"on": "death", "lv": 1, "scope": "all"}},

	# ═══════════════════════════════════════════════════════════════════════════
	# 🆕 真实伤害（2026-11-07 · combat-types GDD v0.3）：第三种攻击类型「真实」。
	#   真实伤害**无视一切抗性**（不吃物抗/魔抗，也不受破甲影响），打谁都全额结算。
	#   定位 = 克制「高抗性怪」（Tank 物抗 0.30 / Rush 魔抗 0.20）的通用解。
	#   🔴 平衡代价：真实伤害塔 dps **刻意压低**——无视抗性本身就是巨大优势，面板若与
	#      物/魔塔持平，会变成无脑上位替代（放弃「打什么怪用什么塔」的构筑决策）。
	#      → dps 低于同 rng 的物/魔塔，只有面对高抗性怪时才划算。
	# ═══════════════════════════════════════════════════════════════════════════
	# 湮灭：真实伤害主塔。单体、dps 6（低于 Arrow 10 / Cannon 7 的真实解），
	#   但无视 Tank 物抗 0.30 / Rush 魔抗 0.20 —— 打高抗怪时等效 dps 反而最高。
	"Oblivion": {"dps": 6.0, "tag": "true", "aoe": false, "slow": 0.00, "rng": 20.0},
	# 虚无：真实伤害第二塔。aoe 群伤、dps 5（真实伤害 aoe 的面板最低），
	#   换「一片怪都吃全额真实伤害」，是真实 build 的清场位。
	"Void": {"dps": 5.0, "tag": "true", "aoe": true, "slow": 0.00, "rng": 15.0},
}

## 扩展强化卡：只对**同 tag** 的塔生效（语义与 FireUp/FrostUp 完全一致）。
const REINF_EXT := {
	"PirUp": {"tag": "pierce"},
	"ShkUp": {"tag": "shock"},
	# 🆕 破甲塔的强化卡：语义与 FireUp/FrostUp 完全一致，只对同 tag 塔生效。
	"SunUp": {"tag": "sunder"},
	"HexUp": {"tag": "hex"},
	# 🆕 真实伤害第一强化卡（combat-types GDD v0.3）。
	"TrueUp": {"tag": "true"},
}

## 🆕 流派卡包 · 第二强化（2026-11-07 · card-packs v0.2）：为每个 tag 补第二张
##    **同 tag** 强化卡，让单个卡包能同时给「主塔 + 第二塔」各叠一层强化（完整 build 的
##    双强化需求）。语义与 FireUp/FrostUp 完全一致（`reinf` 卡种，同卡再买叠层）。
##   🔴 命名规则：`<tag 缩写>Up2`，与既有 `<tag>Up` 并列，不改变任何 tag 归属。
const REINF_EXT2 := {
	"FireUp2": {"tag": "fire"},
	"FrostUp2": {"tag": "frost"},
	"PirUp2": {"tag": "pierce"},
	"ShkUp2": {"tag": "shock"},
	"SunUp2": {"tag": "sunder"},
	"HexUp2": {"tag": "hex"},
	# 🆕 真实伤害第二强化卡（combat-types GDD v0.3）。
	"TrueUp2": {"tag": "true"},
}

## 扩展卡相对权重。🔴 只影响**相对概率**（`PyRandom.choices()` 内部按总和归一），
##   不参与任何数值口径。取值逻辑：更强的卡更稀有 ——
##   Lance 0.09 ≈ Arrow 0.17 的一半；Tesla 0.10 ≈ Frost 0.13 的八成；
##   强化卡 0.075 ≈ FireUp 0.17 的四成半（新流派起步更慢，逼玩家做取舍）。
##   🆕 破甲塔（Sunder/Hex）与 Lance/Tesla 同级稀有（0.09/0.10），强化卡 0.075。
const EXT_WEIGHTS := {
	"Lance": 0.09,
	"Tesla": 0.10,
	"PirUp": 0.075,
	"ShkUp": 0.075,
	"Sunder": 0.09,
	"Hex": 0.09,
	"SunUp": 0.075,
	"HexUp": 0.075,
	# 🆕 流派卡包 · 第二塔 + 第二强化（2026-11-07）：第二塔 0.10（与 Tesla 同级，
	#   略低于主塔稀有度，让主塔更容易先到手）；第二强化 0.075（与第一强化同稀有度）。
	"Ember": 0.10,
	"Icicle": 0.10,
	"Javelin": 0.10,
	"Bolt": 0.10,
	"Maul": 0.10,
	"Rune": 0.10,
	"FireUp2": 0.075,
	"FrostUp2": 0.075,
	"PirUp2": 0.075,
	"ShkUp2": 0.075,
	"SunUp2": 0.075,
	"HexUp2": 0.075,
	# 🆕 真实伤害（combat-types GDD v0.3）：塔 0.09（与破甲塔同级稀有），强化 0.075。
	"Oblivion": 0.09,
	"Void": 0.09,
	"TrueUp": 0.075,
	"TrueUp2": 0.075,
	# 🆕 触发型建筑（2026-11-07）：0.09（与真实塔同级，稀有度偏高 —— 是构筑支点）。
	"Vanguard": 0.09,
	"Drillmaster": 0.09,
	"Martyr": 0.09,
	# 🆕 卡包扩充（48 张卡 · 一卡一包）：按「越万金油越常见、越极端越稀有」排。
	"Scout": 0.11,
	"Mortar": 0.08,
	"Foundry": 0.07,
	"Blaze": 0.10,
	"Cinder": 0.10,
	"Pyre": 0.08,
	"Glacier": 0.09,
	"Hail": 0.10,
	"Permafrost": 0.09,
	"Frostbite": 0.11,
	"Storm": 0.10,
	"Arc": 0.09,
	"Spark": 0.11,
	"Thunder": 0.09,
	"Ballista": 0.08,
	"Sniper": 0.07,
	"Harpoon": 0.11,
	"Breaker": 0.09,
	"Shatter": 0.10,
	"Ruin": 0.08,
	"Cleave": 0.10,
	"Quake": 0.10,
	"Curse": 0.09,
	"Plague": 0.09,
	"Wither": 0.10,
	"Omen": 0.09,
	"Exile": 0.09,
	"Null": 0.09,
	"Rift": 0.08,
	"Abyss": 0.08,
}


## 塔定义查表：**先主表、再扩展表**。
##   🔴 默认路径（3 张老塔）走第一个分支，结果与改动前逐位一致。
static func _tower_def(ctype: String) -> Dictionary:
	if TOWERS.has(ctype):
		return TOWERS[ctype]
	return TOWERS_EXT[ctype]


static func tower_dps(ctype: String) -> float:
	return float(_tower_def(ctype)["dps"])


static func tower_tag(ctype: String) -> String:
	return String(_tower_def(ctype)["tag"])


static func tower_slow(ctype: String) -> float:
	return float(_tower_def(ctype)["slow"])


static func tower_rng(ctype: String) -> float:
	return float(_tower_def(ctype)["rng"])


## 🆕 触发型建筑：返回 `{"on": enter|prepare|death, "lv": int, "scope": self|all}`；
##   普通塔 / 未知塔返回 `{}`（调用方据此跳过，零开销）。
static func tower_effect(ctype: String) -> Dictionary:
	if not TOWERS_EXT.has(ctype):
		return {}
	var e = TOWERS_EXT[ctype].get("effect", {})
	return e if e is Dictionary else {}


## 🆕 经济建筑：每波额外补贴的废料比例（0 = 不产出）。
static func tower_income(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("income", 0.0))


## 🆕 觉醒：升到 3 级后伤害 +30%（见 `damage_engine` 的 B7 之后）。
static func tower_awaken(ctype: String) -> bool:
	if not TOWERS_EXT.has(ctype):
		return false
	return bool(TOWERS_EXT[ctype].get("awaken", false))


## 🆕 攻击光环：全场塔 dps +X（累加，封顶在 `TowerEffects`）。
static func tower_buff_atk(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("buff_atk", 0.0))


## 🆕 防御光环：全场塔最大生命 +X。
static func tower_buff_def(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("buff_def", 0.0))


## 🆕 回复：每秒为全场塔恢复的生命（0 = 不回复）。
static func tower_heal(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("heal", 0.0))


## 🆕 持续掉血：每秒对全场怪物造成的无视抗性伤害。
static func tower_dot(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("dot", 0.0))


## 🆕 击杀升级：任意怪物被击杀时，本塔 +1 级（封顶 `TowerEffects.LEVEL_CAP` = 8）。
static func tower_on_kill_lv(ctype: String) -> bool:
	if not TOWERS_EXT.has(ctype):
		return false
	return bool(TOWERS_EXT[ctype].get("on_kill_lv", false))


## 🆕 弹射：bullet 命中后可以继续弹跳的次数（每次 +20% 等效输出，见 damage_engine）。
static func tower_bounce(ctype: String) -> int:
	if not TOWERS_EXT.has(ctype):
		return 0
	return int(TOWERS_EXT[ctype].get("bounce", 0))


## 🆕 贯穿：子弹可以贯穿的敌人数（每次 +25% 等效输出，见 damage_engine）。
static func tower_pierce(ctype: String) -> int:
	if not TOWERS_EXT.has(ctype):
		return 0
	return int(TOWERS_EXT[ctype].get("pierce", 0))


## 🆕 溅射：命中后波及的敌人数（每个 +40% 等效输出，见 damage_engine）。
static func tower_splash(ctype: String) -> int:
	if not TOWERS_EXT.has(ctype):
		return 0
	return int(TOWERS_EXT[ctype].get("splash", 0))


## 🆕 赏金：存活时全队累计击杀 N 只 → 获得 X 废料（可重复触发）。
static func tower_bounty_kills(ctype: String) -> int:
	if not TOWERS_EXT.has(ctype):
		return 0
	return int(TOWERS_EXT[ctype].get("bounty_kills", 0))


static func tower_bounty_scrap(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("bounty_scrap", 0.0))


## 强化卡 tag 查表：先主表、再扩展表（同 `_tower_def` 的兼容策略）。
##   🔴 三层：REINF（金标本主表）→ REINF_EXT（扩展第一强化）→ REINF_EXT2（流派第二强化）。
static func reinf_tag(name: String) -> String:
	if REINF.has(name):
		return String(REINF[name]["tag"])
	if REINF_EXT.has(name):
		return String(REINF_EXT[name]["tag"])
	return String(REINF_EXT2[name]["tag"])
