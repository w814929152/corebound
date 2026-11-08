class_name CombatTypes
extends RefCounted
##
## 战斗类型系统 —— 攻击类型（物理 / 魔法）× 防御抗性（物抗 / 魔抗）的 SSOT
##
## =============================================================================
## 🔴 设计目标：给游戏引入「物理攻击 / 魔法攻击 / 物理抗性 / 魔法抗性」这套
##    RPG 式的攻防属性，让「打什么怪用什么塔」成为新的构筑决策维度。
##
## 🔴 零扰动铁律（与 `tower_data.gd` 扩展塔 / `monster_data.gd` 三原型同款哲学）：
##    本文件**只登记数据 + 派生函数**，所有默认值都保证「关掉就是旧行为」：
##      · 塔的攻击类型：默认全部 → "physical"（物理），但这**不影响**伤害——因为
##        只有在 `combat_types_enabled` 开关打开时，类型才会进入结算。
##      · 怪的抗性：默认物抗/魔抗全部 = 0.0 → 伤害 ×(1−0) 恒等 → 逐位不变。
##      · 伤害修正公式 `apply_resist(dmg, resist) = dmg × (1 − clamp(resist, 0, 1))`
##        在 resist = 0 时恒等于 `dmg`（浮点乘法 ×1.0 精确）→ 零扰动。
##
## 🔴 SSOT 定位（control-manifest §5）：`scripts/data/` = 唯一登记处。工程层禁止
##    就地写这些字面量，一律 `CombatTypes.*` 读取。
## =============================================================================
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → 所有期望 float 的除法两侧显式 float()。
##   G2 `**` 不是运算符，本文件无幂运算。
##


# ---------------------------------------------------------------------------
# 攻击类型枚举（字符串常量，便于序列化 / 打印 / 单测断言）
# ---------------------------------------------------------------------------
const PHYSICAL := "physical"   # 物理：箭矢 / 炮击 / 长枪穿刺 —— 直伤，吃物理抗性
const MAGIC := "magic"         # 魔法：冰霜 / 电弧 —— 法术伤害，吃魔法抗性
const TRUE := "true"           # 🆕 真实：无视一切抗性 —— 打谁都全额结算（克制高抗性怪）

## 全部合法攻击类型（单测断言用）
const DAMAGE_TYPES: Array = [PHYSICAL, MAGIC, TRUE]


# ---------------------------------------------------------------------------
# 塔 → 攻击类型 映射表（🔴 SSOT）
# ---------------------------------------------------------------------------
## 设计意图（见 design/gdd/combat-types.md §2）：
##   · Arrow（箭）→ 物理：穿刺直伤。
##   · Cannon（炮）→ 物理：爆炸冲击（群伤，但物理属性）。
##   · Frost（冰）→ 魔法：霜冻法术（既有减速，天然魔法定位）。
##   · Lance（长枪·扩展包）→ 物理：远程穿刺。
##   · Tesla（电弧·扩展包）→ 魔法：雷电法术（既有 shock tag + 减速，魔法定位）。
##
## 🔴 默认全物理不影响结算：类型只有在 `combat_types_enabled` 时被消费。
const TOWER_DMG_TYPE := {
	"Arrow":  PHYSICAL,
	"Cannon": PHYSICAL,
	"Frost":  MAGIC,
	"Lance":  PHYSICAL,
	"Tesla":  MAGIC,
	"Sunder": PHYSICAL,   # 🆕 破甲炮：物理攻击（自身吃物抗）+ 减物抗光环
	"Hex":    MAGIC,      # 🆕 诅咒塔：魔法攻击（自身吃魔抗）+ 减魔抗光环
	# 🆕 流派第二塔（card-packs v0.2）：按 tag 归属补攻击类型，与主塔对齐。
	"Ember":  PHYSICAL,   # 火·第二塔：物理（灼烧冲击，同 Cannon）
	"Icicle": MAGIC,      # 冰·第二塔：魔法（同 Frost）
	"Javelin": PHYSICAL,  # 穿甲·第二塔：物理（同 Lance）
	"Bolt":   MAGIC,      # 电·第二塔：魔法（同 Tesla）
	"Maul":   PHYSICAL,   # 破甲·第二塔：物理（同 Sunder）
	"Rune":   MAGIC,      # 咒术·第二塔：魔法（同 Hex）
	# 🆕 真实伤害（combat-types GDD v0.3）：无视一切抗性。
	"Oblivion": TRUE,     # 湮灭：真实伤害主塔（无视物抗/魔抗）
	"Void":     TRUE,     # 虚无：真实伤害第二塔（aoe，无视抗性）
	# 🆕 卡包扩充（2026-11-07 · 48 张卡）：按 tag 归属补攻击类型，与同系主塔对齐。
	"Blaze": PHYSICAL, "Cinder": PHYSICAL, "Pyre": PHYSICAL,
	"Glacier": MAGIC, "Hail": MAGIC, "Permafrost": MAGIC,
	"Storm": MAGIC, "Arc": MAGIC, "Spark": MAGIC, "Thunder": MAGIC,
	"Breaker": PHYSICAL, "Shatter": PHYSICAL, "Ruin": PHYSICAL,
	"Drummer": PHYSICAL, "Quake": PHYSICAL,
	"Curse": MAGIC, "Plague": MAGIC, "Wither": MAGIC, "Omen": MAGIC,
	"Exile": TRUE, "Null": TRUE, "Rift": TRUE, "Necro": TRUE,
	"Scout": PHYSICAL,
	# 🆕 相位塔（伤害类型转换）：自身不攻击，类型取默认物理；转换在 damage_engine 里结算。
	"Kinetic": PHYSICAL, "Arcane": PHYSICAL, "Purity": PHYSICAL,
	# Card pack expansion: classify new towers by their attack archetype.
	"Ranger": PHYSICAL, "Sentry": PHYSICAL, "Catapult": PHYSICAL, "Harrier": PHYSICAL,
	"Furnace": PHYSICAL, "Wildfire": PHYSICAL, "Ashen": PHYSICAL, "Hellfire": PHYSICAL,
	"Snowfall": MAGIC, "Shard": MAGIC, "Whiteout": MAGIC, "Avalanche": MAGIC,
	"Longbow": PHYSICAL, "Needle": PHYSICAL, "Hemorrhage": PHYSICAL, "Impaler": PHYSICAL,
	"Coil": MAGIC, "Overcharge": MAGIC, "Thunderhead": MAGIC, "Circuit": MAGIC,
	"Rend": PHYSICAL, "Crusher": PHYSICAL, "Bastion": PHYSICAL, "Siege": PHYSICAL,
	"Executioner": MAGIC, "Blight": MAGIC, "Malison": MAGIC, "Hexer": MAGIC,
	"Eraser": TRUE, "Obliterator": TRUE, "Soulpiercer": TRUE, "Wraith": TRUE,
}

## 塔的攻击类型查表。未知塔兜底 = 物理（保守，且与「默认无类型影响」一致）。
static func tower_dmg_type(ctype: String) -> String:
	return String(TOWER_DMG_TYPE.get(ctype, PHYSICAL))


# ---------------------------------------------------------------------------
# 怪物原型 → 抗性（物抗 / 魔抗）映射表（🔴 SSOT）
# ---------------------------------------------------------------------------
## 抗性 = 百分比减伤，`伤害 = 基础 × (1 − 抗性)`，抗性 ∈ [0.0, 1.0]。
##   0.00 = 不减免；0.30 = 减免 30%（伤害 ×0.70）；0.50 = 减免 50%。
##
## 🔴 守恒约束（design/gdd/combat-types.md §3 · W-C1 同族）：
##    原型分化必须**不改变总 HP 预算的有效难度**。基准怪（Swarm）双抗恒 0，
##    其他原型「物抗 + 魔抗」的加权和按只数占比归一，使**平均减免 ≈ 0**——
##    即：新增抗性 = 重新分配"哪种塔更擅长打哪种怪"，而不是整体加难度。
##    这样「起飞点 / 起飞率」判据链不被抗性整体抬高（只有类型错配的构筑才变慢）。
##
## 定稿构成（design/gdd/combat-types.md §3 验算）：
##   · Rush   快速低血：物抗 0.00 / 魔抗 0.20 —— 快而脆，怕魔法（法师克制）。
##   · Swarm  集群基准：物抗 0.00 / 魔抗 0.00 —— 基准怪，双抗零（金标本等价）。
##   · Tank   高血慢速：物抗 0.30 / 魔抗 0.00 —— 铁甲重盾，怕魔法（物攻刮痧）。
##   · Elite  词缀放大：沿用宿主原型抗性（不加额外抗性，只放大 HP）。
##
## 加权平均减免（按 p = 0.40/0.40/0.20）：
##   物抗：0.40×0.00 + 0.40×0.00 + 0.20×0.30 = 0.06
##   魔抗：0.40×0.20 + 0.40×0.00 + 0.20×0.00 = 0.08
##   → 物攻平均少打 6%、魔攻平均少打 8%：轻微、可读，且「错配」惩罚有限。
##   → 纯物攻构筑打 Tank 会刮痧（Tank 物抗 0.30），纯魔攻构筑打 Rush 会刮痧
##      （Rush 魔抗 0.20）→ 逼玩家混合两种塔，兑现「构筑深度」。
const MONSTER_RESIST := {
	"Rush":  {"physical": 0.00, "magic": 0.20, "true": 0.00},
	"Swarm": {"physical": 0.00, "magic": 0.00, "true": 0.00},
	"Tank":  {"physical": 0.30, "magic": 0.00, "true": 0.00},
}

## 怪物某类型抗性查表。未知原型兜底 = 0.0（零扰动，与基准怪 Swarm 一致）。
static func monster_resist(proto: String, dmg_type: String) -> float:
	var row: Dictionary = MONSTER_RESIST.get(proto, {})
	return float(row.get(dmg_type, 0.0))


# ---------------------------------------------------------------------------
# 伤害修正公式（🔴 唯一消费点 = 伤害引擎 / 波次结算）
# ---------------------------------------------------------------------------
## `apply_resist(dmg, resist) = dmg × (1 − clamp(resist, 0, 1))`
##   · resist = 0.0 → 恒等（`dmg × 1.0`，浮点精确）→ 零扰动。
##   · resist 夹到 [0, 1]：抗性不能超过 100%（负值当作无减免，>1 当作免伤）。
static func apply_resist(dmg: float, resist: float) -> float:
	if resist <= 0.0:
		return dmg
	if resist >= 1.0:
		return 0.0
	return dmg * (1.0 - clampf(resist, 0.0, 1.0))


## 便捷：一次算「怪物的某个原型受某种类型伤害」的减免后值。
static func resist_damage(dmg: float, proto: String, dmg_type: String) -> float:
	return apply_resist(dmg, monster_resist(proto, dmg_type))


# ---------------------------------------------------------------------------
# 🆕 破甲光环（Sunder / Hex）—— 减抗 SSOT（combat-types GDD v0.2）
# ---------------------------------------------------------------------------
## 机制：破甲塔在场时，给**全场怪物**叠加一个「减抗光环」——每座破甲塔把对应类型的
##   抗性**降低固定量**（可叠层、封顶）。结算时：
##     有效抗性 = clamp(静态抗性 − 破甲量, 0, 1)
##   即破甲只**削弱**抗性，不能把抗性压成负值（负抗性 = 增伤，超出本系统设计边界）。
##
## 🔴 零扰动保证（与抗性表同族）：
##   · 破甲量只有在 `combat_types_enabled` 开关打开时被波次结算消费；
##   · 默认场上无破甲塔 → 破甲量 = 0 → `有效抗性 == 静态抗性` → 逐位不变。
##   · 破甲塔本身是扩展表新卡（TOWERS_EXT），默认不进 AI 池 → 金标本判据链零扰动。
##
## 设计意图：破甲塔是「物攻 build / 魔攻 build」的**核心件**——它自己不靠 dps 打怪，
##   而是放大同类型塔的输出，让「打什么怪用什么塔」的决策进一步深化为
##   「这局是纯物攻（带 Sunder 打穿 Tank）还是纯魔攻（带 Hex 打穿 Rush）」。
##
## 数值（待拍板 D-CT4）：
##   · 单座破甲塔减抗量 = 0.10（百分比点，不是 10% 相对值）。
##   · 叠层封顶 = 0.30（3 座破甲塔叠满，恰好抵消 Tank 物抗 0.30 / 超越 Rush 魔抗 0.20）。
##     封顶即「抗性归零」上限——破甲到 0 就不能再往下（不产生负抗性增伤）。
const ARMOR_REDUCT_PER_TOWER := 0.10   # 单座破甲塔减抗量（百分比点）
const ARMOR_REDUCT_CAP := 0.30         # 破甲量封顶（= Tank 物抗 0.30，天然对齐）

## 破甲塔 → 减抗的目标类型（Sunder 减物抗 / Hex 减魔抗）。
##   🆕 卡包扩充：同 tag 的破甲系建筑一并计入（Breaker/Shatter/Ruin 减物抗，
##   Curse/Plague 减魔抗）—— 光环量仍受 `ARMOR_REDUCT_CAP` 封顶，不会叠爆。
const SUNDER_TYPES := {
	"Sunder": PHYSICAL,
	"Hex":    MAGIC,
	"Breaker": PHYSICAL,
	"Shatter": PHYSICAL,
	"Ruin":    PHYSICAL,
	"Curse":   MAGIC,
	"Plague":  MAGIC,
}

## 某塔是否为破甲塔（否则返回空串 ""）。
static func armor_reduct_type(ctype: String) -> String:
	return String(SUNDER_TYPES.get(ctype, ""))


## 由场上塔类型列表，计算某攻击类型的**全局破甲量**（百分比点，∈ [0, cap]）。
##   `tower_ctypes`: Array[String]，场上所有塔的 ctype（含升级后的同名塔，重复计数 = 叠层）。
##   只统计「减该类型抗性」的破甲塔；破甲量 = min(数量 × 单塔值, 封顶)。
## 🔴 纯派生，无副作用；默认无破甲塔 → 返回 0 → 结算退化为静态抗性（零扰动）。
static func armor_reduction(tower_ctypes: Array, dmg_type: String) -> float:
	var count := 0
	for c in tower_ctypes:
		var s := String(c)
		if String(SUNDER_TYPES.get(s, "")) == dmg_type:
			count += 1
	return minf(float(count) * ARMOR_REDUCT_PER_TOWER, ARMOR_REDUCT_CAP)


## 结算核心：有效抗性 = clamp(静态抗性 − 破甲量, 0, 1)。
##   `proto` / `dmg_type` 查静态抗性；`reduction` 是 `armor_reduction()` 的结果。
##   🔴 reduction = 0 时返回静态抗性（逐位不变）；>0 时削弱抗性、下限 0。
static func effective_resist(proto: String, dmg_type: String, reduction: float) -> float:
	var base := monster_resist(proto, dmg_type)
	if reduction <= 0.0 or base <= 0.0:
		return base
	return clampf(base - reduction, 0.0, 1.0)
