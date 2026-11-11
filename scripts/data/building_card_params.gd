extends RefCounted
## 建筑卡参数唯一来源。调整塔属性时只需修改本文件。

## 火焰状态：重复附加刷新持续时间；满层清空并在目标位置引爆。
## 实时冰冻统一按层减速；旧塔 slow 字段仅保留作来源标记和历史数值模拟。
const FROST_EFFECT := {"slow_per_stack": 0.10, "max_stacks": 10, "freeze_duration": 2.0,
	"storm_damage": 40.0, "storm_radius": 6.0, "storm_stacks": 2}

const FIRE_EFFECT := {"duration": 2.0, "max_stacks": 10, "blast_damage": 40.0, "blast_radius": 6.0}

const TOWERS := {
	"Arrow":  {"dps": 10.0, "attack_speed": 0.80, "tag": "",      "aoe": false, "slow": 0.00, "rng": 22.0},
	"Cannon": {"dps": 7.0,  "attack_speed": 0.70, "tag": "fire",  "aoe": true,  "slow": 0.00, "rng": 18.0},
	"Frost":  {"dps": 5.0,  "attack_speed": 0.65, "tag": "frost", "aoe": false, "slow": 0.30, "rng": 20.0},
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
	"Scrapcannon": {"dps": 36.0, "attack_speed": 0.50, "tag": "", "aoe": false, "slow": 0.0, "rng": 26.0,
		"shot_scrap": 2},
	"Icehunter": {"dps": 7.0, "attack_speed": 0.80, "tag": "frost", "aoe": false, "slow": 0.0, "rng": 22.0, "hunt_frozen": true},
	# 焚星塔：只由全场火焰十层引爆事件充能，不参与自动攻击。
	"Pyroclasm": {"dps": 0.0, "tag": "fire", "aoe": true, "slow": 0.0, "rng": 28.0,
		"fire_charge": 10, "charge_blast": 120.0, "charge_radius": 28.0},
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
	"Kinetic": {"dps": 0.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 0.0,
		"convert": "physical"},
	# 经济建筑（梦符祭「收益」位）：自己不攻击，每波结算时按比例补贴废料。
	"Foundry": {"dps": 0.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 0.0,
		"income": 0.15},
	# ---- 熔炉包补位（火：燃烧 / 尸爆 / 觉醒）----
	"Blaze": {"dps": 7.0, "tag": "fire", "aoe": true, "slow": 0.05, "rng": 15.0},
	"Cinder": {"dps": 9.0, "tag": "fire", "aoe": false, "slow": 0.00, "rng": 17.0, "splash": 2},
	# 觉醒：升到 3 级后伤害 +30%（梦符祭「觉醒」的可落地版本）。
	"Pyre": {"dps": 6.0, "tag": "fire", "aoe": true, "slow": 0.00, "rng": 16.0,
		"awaken": true, "death_blast": 40.0, "death_blast_r": 6.0},
	# ---- 霜序包补位（冰：减速梯度）----
	"Glacier": {"dps": 5.0, "tag": "frost", "aoe": false, "slow": 0.50, "rng": 18.0},
	"Hail": {"dps": 4.0, "tag": "frost", "aoe": true, "slow": 0.25, "rng": 20.0},
	"Permafrost": {"dps": 3.0, "tag": "frost", "aoe": true, "slow": 0.35, "rng": 22.0},
	"Purity": {"dps": 0.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 0.0,
		"convert": "true"},
	# ---- 电弧包补位（电：从单体到群伤）----
	"Storm": {"dps": 7.0, "tag": "shock", "aoe": true, "slow": 0.05, "rng": 18.0, "bounce": 2},
	"Arc": {"dps": 9.0, "tag": "shock", "aoe": true, "slow": 0.00, "rng": 17.0, "bounce": 2},
	"Spark": {"dps": 8.0, "tag": "shock", "aoe": false, "slow": 0.00, "rng": 20.0, "bounce": 1, "splash": 1},
	"Thunder": {"dps": 10.0, "tag": "shock", "aoe": false, "slow": 0.00, "rng": 22.0, "bounce": 1, "on_kill_lv": true},
	# ---- 穿甲包补位（远程梯度）----
	"Ballista": {"dps": 12.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 30.0, "pierce": 3},
	"Sniper": {"dps": 10.0, "tag": "pierce", "aoe": false, "slow": 0.10, "rng": 34.0, "pierce": 2},
	"Arcane": {"dps": 0.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 0.0,
		"convert": "magic"},
	# ---- 破甲包补位（削物抗光环扩展：tag=sunder 自动计入 `SUNDER_TYPES`）----
	"Breaker": {"dps": 8.0, "tag": "sunder", "aoe": true, "slow": 0.00, "rng": 18.0},
	"Shatter": {"dps": 7.0, "tag": "sunder", "aoe": false, "slow": 0.00, "rng": 20.0},
	"Ruin": {"dps": 9.0, "tag": "sunder", "aoe": true, "slow": 0.00, "rng": 16.0},
	"Drummer": {"dps": 4.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 15.0,
		"buff_aspd": 0.20},
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
	"Necro": {"dps": 3.0, "tag": "true", "aoe": false, "slow": 0.00, "rng": 18.0,
		"summon_n": 2, "summon_dps": 8.0, "summon_ttl": 10.0, "summon_speed": 6.0},

	# 🆕 卡包扩容（2026-11-08）：每个流派新增四张建筑卡，填满 8 包 × 10 张。
	# 泛用：补足远程、守护、群伤与高速输出位。
	"Ranger": {"dps": 8.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 27.0},
	"Sentry": {"dps": 5.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 20.0, "buff_def": 0.10},
	"Catapult": {"dps": 6.0, "tag": "", "aoe": true, "slow": 0.00, "rng": 23.0, "splash": 2},
	"Harrier": {"dps": 7.0, "tag": "", "aoe": false, "slow": 0.00, "rng": 19.0, "bounce": 1},
	# 熔炉：新增灼烧持续伤害、群体控场与爆发溅射。
	"Furnace": {"dps": 5.0, "tag": "fire", "aoe": true, "slow": 0.00, "rng": 16.0, "dot": 2.0},
	"Wildfire": {"dps": 4.0, "tag": "fire", "aoe": true, "slow": 0.20, "rng": 18.0, "dot": 1.0},
	"Ashen": {"dps": 8.0, "tag": "fire", "aoe": false, "slow": 0.00, "rng": 19.0, "splash": 1},
	"Hellfire": {"dps": 3.0, "tag": "fire", "aoe": true, "slow": 0.00, "rng": 22.0, "dot": 3.0},
	# 霜序：减速梯度覆盖单体、群体与远程控制。
	"Snowfall": {"dps": 4.0, "tag": "frost", "aoe": true, "slow": 0.20, "rng": 19.0},
	"Shard": {"dps": 7.0, "tag": "frost", "aoe": false, "slow": 0.15, "rng": 16.0, "pierce": 1},
	"Whiteout": {"dps": 3.0, "tag": "frost", "aoe": true, "slow": 0.40, "rng": 15.0},
	"Avalanche": {"dps": 5.0, "tag": "frost", "aoe": true, "slow": 0.10, "rng": 24.0, "splash": 1},
	# 穿甲：远射程、贯穿与流血持续伤害构成精英狙击线。
	"Longbow": {"dps": 9.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 32.0, "pierce": 1},
	"Needle": {"dps": 8.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 24.0, "pierce": 2},
	"Hemorrhage": {"dps": 5.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 21.0, "dot": 2.0},
	"Impaler": {"dps": 7.0, "tag": "pierce", "aoe": false, "slow": 0.00, "rng": 18.0, "pierce": 3},
	# 电弧：弹射、群控與击杀成长。
	"Coil": {"dps": 6.0, "tag": "shock", "aoe": true, "slow": 0.10, "rng": 21.0, "bounce": 2},
	"Overcharge": {"dps": 10.0, "tag": "shock", "aoe": false, "slow": 0.00, "rng": 15.0, "bounce": 1},
	"Thunderhead": {"dps": 5.0, "tag": "shock", "aoe": true, "slow": 0.15, "rng": 23.0, "bounce": 1},
	"Circuit": {"dps": 7.0, "tag": "shock", "aoe": false, "slow": 0.00, "rng": 20.0, "bounce": 2, "on_kill_lv": true},
	# 破甲：补流血 debuff 与团队耐久、重击输出。
	"Rend": {"dps": 6.0, "tag": "sunder", "aoe": false, "slow": 0.00, "rng": 20.0, "dot": 2.0},
	"Crusher": {"dps": 10.0, "tag": "sunder", "aoe": false, "slow": 0.00, "rng": 14.0, "splash": 1},
	"Bastion": {"dps": 4.0, "tag": "sunder", "aoe": true, "slow": 0.10, "rng": 18.0, "buff_def": 0.10},
	"Siege": {"dps": 7.0, "tag": "sunder", "aoe": true, "slow": 0.00, "rng": 22.0, "splash": 2},
	# 咒术：易伤支点叠加灼烧式 DoT、减速与破魔输出。
	"Executioner": {"dps": 5.0, "tag": "hex", "aoe": false, "slow": 0.00, "rng": 20.0, "buff_debuff_dmg": 0.20},
	"Blight": {"dps": 3.0, "tag": "hex", "aoe": true, "slow": 0.00, "rng": 22.0, "dot": 3.0},
	"Malison": {"dps": 4.0, "tag": "hex", "aoe": true, "slow": 0.15, "rng": 18.0, "dot": 1.0},
	"Hexer": {"dps": 8.0, "tag": "hex", "aoe": false, "slow": 0.00, "rng": 16.0, "splash": 1},
	# 湮灭：低面板真实伤害覆盖单体、群体、贯穿与击杀成长。
	"Eraser": {"dps": 4.0, "tag": "true", "aoe": true, "slow": 0.00, "rng": 21.0},
	"Obliterator": {"dps": 8.0, "tag": "true", "aoe": false, "slow": 0.00, "rng": 15.0, "splash": 1},
	"Soulpiercer": {"dps": 5.0, "tag": "true", "aoe": false, "slow": 0.00, "rng": 26.0, "pierce": 2},
	"Wraith": {"dps": 4.0, "tag": "true", "aoe": true, "slow": 0.00, "rng": 18.0, "on_kill_lv": true},

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
