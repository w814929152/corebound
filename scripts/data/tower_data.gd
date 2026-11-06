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
	"Lance": {"dps": 11.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 26.0},
	# 贴身电弧：rng 16 < Cannon 18，dps 6（全场最低），换 aoe + 0.10 减速。
	# 定位 = 堵在暴露位的近身清场，与「肉盾流」站位天然互补。
	"Tesla": {"dps": 6.0, "tag": "shock", "aoe": true, "slow": 0.10, "rng": 16.0},
}

## 扩展强化卡：只对**同 tag** 的塔生效（语义与 FireUp/FrostUp 完全一致）。
const REINF_EXT := {
	"PirUp": {"tag": "pierce"},
	"ShkUp": {"tag": "shock"},
}

## 扩展卡相对权重。🔴 只影响**相对概率**（`PyRandom.choices()` 内部按总和归一），
##   不参与任何数值口径。取值逻辑：更强的卡更稀有 ——
##   Lance 0.09 ≈ Arrow 0.17 的一半；Tesla 0.10 ≈ Frost 0.13 的八成；
##   强化卡 0.075 ≈ FireUp 0.17 的四成半（新流派起步更慢，逼玩家做取舍）。
const EXT_WEIGHTS := {
	"Lance": 0.09,
	"Tesla": 0.10,
	"PirUp": 0.075,
	"ShkUp": 0.075,
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


## 强化卡 tag 查表：先主表、再扩展表（同 `_tower_def` 的兼容策略）。
static func reinf_tag(name: String) -> String:
	if REINF.has(name):
		return String(REINF[name]["tag"])
	return String(REINF_EXT[name]["tag"])
