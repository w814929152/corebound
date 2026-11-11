class_name TowerData
extends RefCounted
##
## 塔原型 / 强化卡 / 价格 —— 移植自 design/phase2/numeric-sim/corebound_sim_v03.py
##   TOWERS (L41-45) / REINF (L46) / PRICE (L57)
##
## 🔴 SSOT：这些数字必须与金标本逐位一致，禁止在引擎侧二次定义。
##    Python 的 `tag=None` 在此用空字符串 "" 表示（GDScript 无 None 可用于字典值类型统一）。
##

const _BuildingParams := preload("res://scripts/data/building_card_params.gd")
const FROST_EFFECT: Dictionary = _BuildingParams.FROST_EFFECT
const FIRE_EFFECT: Dictionary = _BuildingParams.FIRE_EFFECT
const TOWERS: Dictionary = _BuildingParams.TOWERS
const TOWERS_EXT: Dictionary = _BuildingParams.TOWERS_EXT
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
	"Kinetic": 0.08,
	"Foundry": 0.07,
	"Blaze": 0.10,
	"Cinder": 0.10,
	"Pyre": 0.08,
	"Glacier": 0.09,
	"Hail": 0.10,
	"Permafrost": 0.09,
	"Purity": 0.08,
	"Storm": 0.10,
	"Arc": 0.09,
	"Spark": 0.11,
	"Thunder": 0.09,
	"Ballista": 0.08,
	"Sniper": 0.07,
	"Arcane": 0.08,
	"Breaker": 0.09,
	"Shatter": 0.10,
	"Ruin": 0.08,
	"Drummer": 0.09,
	"Quake": 0.10,
	"Curse": 0.09,
	"Plague": 0.09,
	"Wither": 0.10,
	"Omen": 0.09,
	"Exile": 0.09,
	"Null": 0.09,
	"Rift": 0.08,
	"Necro": 0.08,
}

## Card-pack-only building weights; kept out of `EXT_WEIGHTS` so the legacy extended pack stays fixed.
const CARD_PACK_WEIGHTS := {
	"Scrapcannon": 0.07,
	"Icehunter": 0.08,
	"Pyroclasm": 0.07,
	"Ranger": 0.09, "Sentry": 0.08, "Catapult": 0.08, "Harrier": 0.09,
	"Furnace": 0.09, "Wildfire": 0.08, "Ashen": 0.09, "Hellfire": 0.07,
	"Snowfall": 0.09, "Shard": 0.09, "Whiteout": 0.07, "Avalanche": 0.08,
	"Longbow": 0.08, "Needle": 0.09, "Hemorrhage": 0.08, "Impaler": 0.08,
	"Coil": 0.09, "Overcharge": 0.08, "Thunderhead": 0.08, "Circuit": 0.08,
	"Rend": 0.09, "Crusher": 0.08, "Bastion": 0.08, "Siege": 0.08,
	"Executioner": 0.08, "Blight": 0.08, "Malison": 0.08, "Hexer": 0.09,
	"Eraser": 0.08, "Obliterator": 0.07, "Soulpiercer": 0.08, "Wraith": 0.08,
}


## 塔定义查表：**先主表、再扩展表**。
##   🔴 默认路径（3 张老塔）走第一个分支，结果与改动前逐位一致。
static func _tower_def(ctype: String) -> Dictionary:
	if TOWERS.has(ctype):
		return TOWERS[ctype]
	return TOWERS_EXT[ctype]


## 火焰充能建筑参数；非充能建筑返回空字典。
static func tower_fire_charge(ctype: String) -> Dictionary:
	var d := _tower_def(ctype)
	if int(d.get("fire_charge", 0)) <= 0:
		return {}
	return {"capacity": int(d["fire_charge"]), "damage": float(d["charge_blast"]),
		"radius": float(d["charge_radius"])}


static func tower_dps(ctype: String) -> float:
	return float(_tower_def(ctype)["dps"])


static func tower_attack_speed(ctype: String) -> float:
	return maxf(0.1, float(_tower_def(ctype).get("attack_speed", 1.0)))


static func tower_shot_scrap(ctype: String) -> int:
	return int(_tower_def(ctype).get("shot_scrap", 0))


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


## Debuff 易伤增伤（0 = 不提供）。
static func tower_buff_debuff_dmg(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("buff_debuff_dmg", 0.0))


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


## 🆕 攻速光环：附近塔的攻击速度加成（累加，与攻击光环同口径，见 `TowerEffects`）。
static func tower_buff_aspd(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("buff_aspd", 0.0))


## 🆕 伤害类型转换：把「最近的一座塔」转成该类型（"" = 不转换）。
##   物理 = physical / 魔法 = magic / 纯粹 = true（见 `damage_engine._apply_converters`）。
static func tower_convert(ctype: String) -> String:
	if not TOWERS_EXT.has(ctype):
		return ""
	return String(TOWERS_EXT[ctype].get("convert", ""))


## 🆕 死亡爆炸：塔阵亡时对周围敌人造成的伤害（0 = 无爆炸）。
static func tower_death_blast(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("death_blast", 0.0))


## 🆕 死亡爆炸半径（世界单位）。
static func tower_death_blast_r(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("death_blast_r", 0.0))


## 🆕 召唤：每波召唤的小兵数量（0 = 不召唤）。
static func tower_summon_n(ctype: String) -> int:
	if not TOWERS_EXT.has(ctype):
		return 0
	return int(TOWERS_EXT[ctype].get("summon_n", 0))


static func tower_summon_dps(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("summon_dps", 0.0))


static func tower_summon_ttl(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("summon_ttl", 0.0))


static func tower_summon_speed(ctype: String) -> float:
	if not TOWERS_EXT.has(ctype):
		return 0.0
	return float(TOWERS_EXT[ctype].get("summon_speed", 0.0))


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
