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


static func tower_dps(ctype: String) -> float:
	return float(TOWERS[ctype]["dps"])


static func tower_tag(ctype: String) -> String:
	return String(TOWERS[ctype]["tag"])


static func tower_slow(ctype: String) -> float:
	return float(TOWERS[ctype]["slow"])


static func tower_rng(ctype: String) -> float:
	return float(TOWERS[ctype]["rng"])


static func reinf_tag(name: String) -> String:
	return String(REINF[name]["tag"])
