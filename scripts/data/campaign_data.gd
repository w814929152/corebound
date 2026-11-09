extends RefCounted
##
## 关卡数据表 `CampaignData` —— 关卡推进系统的**唯一登记处**（SSOT）
##
## 🔴 定位（control-manifest §5）：`scripts/data/` = SSOT。工程层禁止就地写关卡字面量，
##    一律 `CampaignData.*` 读取。本文件只登记「世界主线 × 十关」的结构与进度口径，
##    不新增任何伤害/经济数值（那些仍由 `mvp_config` / 金标本定义）。
##
## 🔴 来源：`design/gdd/campaign-v2-overseer.md`（世界主线重做 · 2026-11-08）
##   世界观：世界被**统序**（智械）侵略；玩家作为**守核者**逐地区守卫中继站，
##   守住即获得该地区科技（= 卡包），统序随玩家战果变强，最终在 9-1 击退。
##
##   · 结构 = 「中枢 1 + 外环 3 + 中环 4 + 内环 2」，共 10 关；
##   · 解锁 = **图**，不是链：外环三区任选起点，中环四区各有两条来路（选错顺序不会卡死）；
##   · 门槛：已守 ≥5 区 → 8-1（主脑外围）；集齐 7 区 **且** 通关 8-1 → 9-1（主脑核心）；
##   · 7 个地区 ↔ 7 个卡包一一对应（`core` 是中枢的起点科技，不占地区名额）。
##
## 🔴 难度自变量 `S` = **已守地区数**（`regions_cleared()`）。它只做两件事：
##    ① 把该关最早的 `k = floor(S/3)` 个「试探」波升级为「潮涌」波；
##    ② 处刑波精英 `+k`。
##    🔴 **不加波数**：`hp = 16 × 1.42^(w−1)`，+1 波末波就贵 42%，那是断崖不是斜坡
##       （详见 `design/gdd/stage-waves.md` §5）。波数 = 波表长度，**固定且封顶 20**。
##
## 🔴 与卡包系统的分工（`docs/phase6/card-packs.md` §3）：
##   本文件是「关卡推进」那一半（`campaign.gd` / `campaign_data.gd`），与「卡包」那一半
##   （`card_packs.gd` / `run_meta.gd`）**存档不合并**。两者的收敛点仍是「解锁判据」：
##   `unlock_deck` 字段登记了每个地区守住后该给哪个包，何时把它当成解锁判据由 boot 决定。
##
## 🔴 金标本零扰动：本文件**只被玩家路线的关卡系统读取**；金标本引擎
##   （`run_loop` / `wave_sim` / `shop_ai` + 300 局 MC）从不引用本文件 → 逐位不变。
##
## ⚠️ Godot 坑
##   G6 headless 无 global_script_class_cache → 不写 `class_name`，一律 preload。
##   G1 int/int 整数除法 → 浮点除法两侧显式 float()。
##

# ---------------------------------------------------------------------------
#  关卡结构（中枢 1 · 外环 3 · 中环 4 · 内环 2）
# ---------------------------------------------------------------------------
## 关卡 ID 的稳定序（Array 保证顺序确定，可测；不用 Dictionary 遍历顺序）。
##   🔴 顺序 = **展示序 / 航图螺旋序**，不是解锁序（解锁是图，见 `prereq`）。
const STAGE_ORDER: Array = [
	"0-1",
	"1-1", "2-1", "3-1",
	"4-1", "5-1", "6-1", "7-1",
	"8-1", "9-1",
]

## 每关的静态定义。字段：
##   · chapter       环（1 中枢 / 2 外环 / 3 中环 / 4 内环）—— 航图按它分环
##   · name          关卡名（= 地区名 + 守备点）
##   · map_id        绑定的战场（`scripts/data/map_variants.gd` 的键）
##   · wave_count    通关所需波数。🔴 必须 == `StageWaves.wave_count(id)`（表长为准，
##                   不一致由 `tests/run_campaign_asserts.gd` 直接判红）
##   · region        地区 id（"" = 中枢，不占 7 区名额）；`S` 只数它
##   · unlock_deck   守住该地区后入手的科技包（"" = 无）
##   · prereq        解锁前置（**任一**通关即解锁；空 = 无前置）
##   · need_regions  解锁门槛：已守地区数 ≥ N（0 = 无门槛）
##   · need_cleared  解锁门槛：某关必须已通关（"" = 无）
const STAGES: Dictionary = {
	# ── 中枢：起点，不占地区名额。战场 = 三裂环（基准图，逐位等于金标本）──
	"0-1": {
		"chapter": 1, "name": "铁砧·中继站", "map_id": "tri-fissure", "wave_count": 10,
		"region": "", "unlock_deck": "",
		"prereq": [], "need_regions": 0, "need_cleared": "",
	},
	# ── 外环：人类残存区，三区任选起点 ──
	"1-1": {
		"chapter": 2, "name": "灰烬熔炉", "map_id": "cinder-forge", "wave_count": 12,
		"region": "cinder", "unlock_deck": "cinder",
		"prereq": ["0-1"], "need_regions": 0, "need_cleared": "",
	},
	"2-1": {
		"chapter": 2, "name": "永冻科考站", "map_id": "rime-station", "wave_count": 12,
		"region": "rime", "unlock_deck": "rime",
		"prereq": ["0-1"], "need_regions": 0, "need_cleared": "",
	},
	"3-1": {
		"chapter": 2, "name": "磁轨长廊", "map_id": "rail-corridor", "wave_count": 13,
		"region": "pierce", "unlock_deck": "pierce",
		"prereq": ["0-1"], "need_regions": 0, "need_cleared": "",
	},
	# ── 中环：争夺区。每区两条来路 —— 选错顺序不会卡死（这是"图状解锁"的意义）──
	"4-1": {
		"chapter": 3, "name": "雷暴电网", "map_id": "arc-grid", "wave_count": 15,
		"region": "arc", "unlock_deck": "arc",
		"prereq": ["1-1"], "need_regions": 0, "need_cleared": "",
	},
	"5-1": {
		"chapter": 3, "name": "锻造联合体", "map_id": "forge-union", "wave_count": 15,
		"region": "sunder", "unlock_deck": "sunder",
		"prereq": ["1-1", "2-1"], "need_regions": 0, "need_cleared": "",
	},
	"6-1": {
		"chapter": 3, "name": "生物研究所", "map_id": "bio-lab", "wave_count": 16,
		"region": "hex", "unlock_deck": "hex",
		"prereq": ["2-1", "3-1"], "need_regions": 0, "need_cleared": "",
	},
	"7-1": {
		"chapter": 3, "name": "湮灭实验场", "map_id": "void-range", "wave_count": 17,
		"region": "true", "unlock_deck": "true",
		"prereq": ["3-1"], "need_regions": 0, "need_cleared": "",
	},
	# ── 内环：智械腹地。两道门槛：≥5 区进外围；7 区 + 通关外围 才能决战 ──
	"8-1": {
		"chapter": 4, "name": "主脑·外围", "map_id": "overseer-ring", "wave_count": 19,
		"region": "", "unlock_deck": "",
		"prereq": [], "need_regions": 5, "need_cleared": "",
	},
	"9-1": {
		"chapter": 5, "name": "主脑·核心", "map_id": "overseer-core", "wave_count": 20,
		"region": "", "unlock_deck": "",
		"prereq": [], "need_regions": 7, "need_cleared": "8-1",
	},
}

## 起点关（恒解锁）：无前置 + 无门槛。
const START_STAGE := "0-1"

## 地区的固定序（= 卡包序；`S` 与「7 区齐了没」都按它算，保证可测）。
const REGION_ORDER: Array = ["cinder", "rime", "pierce", "arc", "sunder", "hex", "true"]

## 地区 id → 中文名（叙事用；卡包名在 `card_packs.gd`）。
const REGION_NAMES: Dictionary = {
	"cinder": "灰烬熔炉",
	"rime": "永冻科考站",
	"pierce": "磁轨长廊",
	"arc": "雷暴电网",
	"sunder": "锻造联合体",
	"hex": "生物研究所",
	"true": "湮灭实验场",
}

## 环 → 章名（航图分组标题）。
const CHAPTER_TITLES: Dictionary = {
	1: "中枢 · 铁砧",
	2: "外环 · 残存区",
	3: "中环 · 争夺区",
	4: "内环 · 主脑外围",
	5: "主脑 · 核心",
}


# ---------------------------------------------------------------------------
#  地图变体 → 是否已实现
# ---------------------------------------------------------------------------
## 已实现的地图 id。未实现的变体在运行时**回落**到 "tri-fissure"（不报错、不崩）。
##   · `tri-fissure` = 基准（= 现有 const 表，逐位）；
##   · `variant-a..h` / `fusion` = v1 遗留（保留：旧存档的 map_id 仍可解析，且是几何对照）；
##   · 其余 9 张 = v2 世界主线的战场（`campaign-v2-overseer.md`）。
const IMPLEMENTED_MAPS: Array = [
	"tri-fissure", "variant-a", "variant-b", "variant-c", "variant-d",
	"variant-e", "variant-f", "variant-g", "variant-h", "fusion",
	"cinder-forge", "rime-station", "rail-corridor", "arc-grid", "forge-union",
	"bio-lab", "void-range", "overseer-ring", "overseer-core",
]

## 变体 id → 回落 map id（未实现时）。
const MAP_FALLBACK := "tri-fissure"


## 某关绑定的地图是否已实现（未实现则运行时应回落）。
static func map_implemented(map_id: String) -> bool:
	return IMPLEMENTED_MAPS.has(map_id)


## 解析某关实际使用的地图 id（未实现 → 回落三裂环）。
static func resolve_map_id(stage_id: String) -> String:
	var st: Dictionary = STAGES.get(stage_id, {})
	if st.is_empty():
		return MAP_FALLBACK
	var mid := String(st.get("map_id", MAP_FALLBACK))
	return mid if map_implemented(mid) else MAP_FALLBACK


# ---------------------------------------------------------------------------
#  结构查询
# ---------------------------------------------------------------------------
## 指定关卡在 STAGE_ORDER 里的下标（-1 = 未知）。
static func stage_index(stage_id: String) -> int:
	return STAGE_ORDER.find(stage_id)


## 关卡是否已登记。
static func has_stage(stage_id: String) -> bool:
	return STAGES.has(stage_id)


## 该关属于哪个地区（"" = 中枢 / 内环，不占 7 区名额）。
static func region_of(stage_id: String) -> String:
	return String((STAGES.get(stage_id, {}) as Dictionary).get("region", ""))


## 该关打出的是哪个科技包（"" = 无）。
static func deck_of(stage_id: String) -> String:
	return String((STAGES.get(stage_id, {}) as Dictionary).get("unlock_deck", ""))


## 该关的前置关（**任一**通关即解锁；空 = 无前置）。
static func prereqs(stage_id: String) -> Array:
	return (STAGES.get(stage_id, {}) as Dictionary).get("prereq", [])


## 该关的地区门槛（已守地区数 ≥ N；0 = 无门槛）。
static func need_regions(stage_id: String) -> int:
	return int((STAGES.get(stage_id, {}) as Dictionary).get("need_regions", 0))


## 该关的指定关门槛（某关必须已通关；"" = 无）。
static func need_cleared(stage_id: String) -> String:
	return String((STAGES.get(stage_id, {}) as Dictionary).get("need_cleared", ""))


## 是否是「起点关」（无前置 + 无门槛）→ 恒解锁。
static func is_start(stage_id: String) -> bool:
	if not STAGES.has(stage_id):
		return false
	return prereqs(stage_id).is_empty() \
		and need_regions(stage_id) == 0 \
		and need_cleared(stage_id) == ""


## 该关的波数（**以波表长度为准**，见 `StageWaves.wave_count`）。
static func wave_count(stage_id: String) -> int:
	return int((STAGES.get(stage_id, {}) as Dictionary).get("wave_count", 0))


## 抵达该关时**最少**已守几个地区 —— 即该关首次进入时的难度自变量 `S`。
##
## 🔴 为什么需要它：`S` = `regions_cleared()`，是**动态**值（老玩家重打会更高）。
##    但「这一关首次抵达时该多难」是个**静态**问题，MC 定难度必须用静态值，
##    否则同一张表在不同进度下读数不同，无法对拍。
##
## 递推（图是 DAG，`prereq` 只会指向更早的关）：
##   `min_S(关) = max( need_regions , min over p ∈ prereq( min_S(p) + [p 是地区关] ) )`
##   · `prereq` 为空 → 只剩 `need_regions` 抬底；
##   · `0-1` 这种「无地区」的关不贡献 +1（它不占 7 区名额）。
##
## 实算（v2 十关）：0-1 / 三外环 = 0；四中环 = 1；8-1 = 5；9-1 = 7。
##   → `escalation_k = floor(S/3)` 依次是 0…0 / 1 / 2（见 `StageWaves.escalation_k`）。
static func min_regions_on_arrival(stage_id: String) -> int:
	return _min_region_rec(stage_id, {})


static func _min_region_rec(stage_id: String, memo: Dictionary) -> int:
	if memo.has(stage_id):
		return int(memo[stage_id])
	if not STAGES.has(stage_id):
		return 0
	var best := 2147483647
	for p in prereqs(stage_id):
		var sub := _min_region_rec(String(p), memo)
		if region_of(String(p)) != "":
			sub += 1
		best = mini(best, sub)
	if best == 2147483647:
		best = 0
	best = maxi(best, need_regions(stage_id))
	memo[stage_id] = best
	return best


# ---------------------------------------------------------------------------
#  推进货币 `Ember`（余烬）—— 局外货币，只解锁「选择」，绝不购买「强度」
# ---------------------------------------------------------------------------
## 奖励口径（campaign-progression §3.1）。🔴 `[PLACEHOLDER]`，未拍板。
const EMBER_CLEAR := 10          # 通关任意关卡
const EMBER_FAIL_BASE := 3       # 失败基础
const EMBER_FAIL_CAP := 6        # 失败上限（按到达波次线性加，封顶）
const EMBER_REPLAY := 2          # 重复通关已通关卡（递减，防刷币）

## 失败奖励：按到达波次线性插值，cap EMBER_FAIL_CAP。
##   `reached_wave` = 阵亡波；`wave_count` = 该关总波数。
static func ember_on_fail(reached_wave: int, wave_count: int) -> int:
	if wave_count <= 0:
		return EMBER_FAIL_BASE
	var ratio := clampf(float(reached_wave) / float(wave_count), 0.0, 1.0)
	var v := float(EMBER_FAIL_BASE) + ratio * float(EMBER_FAIL_CAP - EMBER_FAIL_BASE)
	return int(roundf(v))


# ---------------------------------------------------------------------------
#  科技包解锁（方向反转：解锁的是「可选」，不是「更强」）
# ---------------------------------------------------------------------------
## 包 id 列表（SSOT）。与 `card_packs.gd` 的 7 个地区包一一对应；
##   `core`（泛用包）是中枢的起点科技，**不占地区名额**，故不在此表。
const DECK_ORDER: Array = ["cinder", "rime", "pierce", "arc", "sunder", "hex", "true"]

## 包 id → 打出它的关卡（守住该地区即入手）。
const DECK_UNLOCK_STAGE: Dictionary = {
	"cinder": "1-1",
	"rime": "2-1",
	"pierce": "3-1",
	"arc": "4-1",
	"sunder": "5-1",
	"hex": "6-1",
	"true": "7-1",
}

## 包 id → 中文名（= 地区名 + 的科技）。
const DECK_NAMES: Dictionary = {
	"cinder": "熔炉科技",
	"rime": "霜序科技",
	"pierce": "磁轨科技",
	"arc": "电弧科技",
	"sunder": "锻造科技",
	"hex": "生物科技",
	"true": "湮灭科技",
}


## 某卡包由哪一关解锁（"" = 无 / 未登记）。
static func deck_unlock_stage(deck_id: String) -> String:
	return String(DECK_UNLOCK_STAGE.get(deck_id, ""))


## 该卡包是否已登记（SSOT 内存在）。
static func deck_exists(deck_id: String) -> bool:
	return DECK_ORDER.has(deck_id)
