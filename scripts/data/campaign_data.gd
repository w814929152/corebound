extends RefCounted
##
## 关卡数据表 `CampaignData` —— 关卡推进系统的**唯一登记处**（SSOT）
##
## 🔴 定位（control-manifest §5）：`scripts/data/` = SSOT。工程层禁止就地写关卡字面量，
##    一律 `CampaignData.*` 读取。本文件只登记「三章 × 3 关 + 终局」的结构与进度口径，
##    不新增任何伤害/经济数值（那些仍由 `mvp_config` / 金标本定义）。
##
## 🔴 来源：`design/gdd/campaign-progression.md`（v0.1 草案 · 推荐形状）
##   · 关卡 = 一张地图 × 一套难度参数（波次构成）+ 一个通关条件；
##   · 卡组解锁 = 通关指定关卡后「可选」启用，不是「更强」；
##   · 地图变体 = 换 `SITES`/`RIDGES`/`SPAWN_ARCS` 数据表（scene-map §5），不换引擎。
##
## 🔴 与卡包系统的分工（见 `docs/phase6/card-packs.md` §3）：
##   本文件是「关卡推进」那一半（`campaign.gd` / `campaign_data.gd`），与「卡包」那一半
##   （`card_packs.gd` / `run_meta.gd`）**当前不合并**。两者的收敛点在「解锁判据」一个函数
##   （`RunMeta.unlocked_ids()`）：等关卡系统接进 `boot.gd` 后，把 `unlock_wave` 换成
##   「已通关关卡」即可，卡包表与 UI 不用动。
##
## 🔴 金标本零扰动：本文件**只被玩家路线的关卡系统读取**；金标本引擎
##   （`run_loop` / `wave_sim` / `shop_ai` + 300 局 MC）从不引用本文件 → 逐位不变。
##   · 第 0 关（默认态）= 混编 + 空地图 + 基础池，可逐位复现金标本。
##
## ⚠️ Godot 坑
##   G6 headless 无 global_script_class_cache → 不写 `class_name`，一律 preload。
##   G1 int/int 整数除法 → 浮点除法两侧显式 float()。
##

# ---------------------------------------------------------------------------
#  章节 / 关卡结构（推荐形状：三章 × 3 关 + 终局）
# ---------------------------------------------------------------------------
## 关卡 ID 的稳定序（Array 保证顺序确定，可测；不用 Dictionary 遍历顺序）。
const STAGE_ORDER: Array = [
	"1-1", "1-2", "1-3",
	"2-1", "2-2", "2-3",
	"3-1", "3-2", "3-3",
	"4-1",
]

## 每关的静态定义。🔴 全部数值为 `[PLACEHOLDER]`（campaign-progression §4），
##   仅结构与「哪些字段必须存在」是定稿。字段：
##   · chapter      章节号（1..4，4 = 终局）
##   · name         关卡名（世界观占位）
##   · map_id       绑定的地图变体（scene-map 数据表 id；"tri-fissure" = 现有三裂环）
##   · wave_count   通关所需波数（1-x 短、3-x 长、终局更长）
##   · wave_tag     本章主导的波次构成（复用 faction-decks §5.2 的 Swarm/Armor/Trickle）
##   · unlock_deck  通关后解锁的卡组（"": 无；卡组内容等 faction-decks 定稿回填）
const STAGES: Dictionary = {
	"1-1": {"chapter": 1, "name": "余烬·初燃", "map_id": "tri-fissure", "wave_count": 10, "wave_tag": "Swarm", "unlock_deck": ""},
	"1-2": {"chapter": 1, "name": "余烬·蔓延", "map_id": "variant-a", "wave_count": 12, "wave_tag": "Swarm", "unlock_deck": ""},
	"1-3": {"chapter": 1, "name": "余烬·成塔", "map_id": "variant-b", "wave_count": 15, "wave_tag": "Swarm", "unlock_deck": "cinder-adv"},
	"2-1": {"chapter": 2, "name": "霜线·初凝", "map_id": "variant-c", "wave_count": 12, "wave_tag": "Armor", "unlock_deck": ""},
	"2-2": {"chapter": 2, "name": "霜线·封冻", "map_id": "variant-d", "wave_count": 15, "wave_tag": "Armor", "unlock_deck": ""},
	"2-3": {"chapter": 2, "name": "霜线·永冬", "map_id": "variant-e", "wave_count": 18, "wave_tag": "Armor", "unlock_deck": "rime-adv"},
	"3-1": {"chapter": 3, "name": "晶格·初织", "map_id": "variant-f", "wave_count": 15, "wave_tag": "Trickle", "unlock_deck": ""},
	"3-2": {"chapter": 3, "name": "晶格·致密", "map_id": "variant-g", "wave_count": 18, "wave_tag": "Trickle", "unlock_deck": ""},
	"3-3": {"chapter": 3, "name": "晶格·满阵", "map_id": "variant-h", "wave_count": 20, "wave_tag": "Trickle", "unlock_deck": "lattice-adv"},
	"4-1": {"chapter": 4, "name": "核心·终局", "map_id": "fusion", "wave_count": 25, "wave_tag": "Mixed", "unlock_deck": ""},
}

# ---------------------------------------------------------------------------
#  地图变体 → 是否已实现（🆕 运行时换图已落地，全部 10 张变体生效）
# ---------------------------------------------------------------------------
## 已实现的地图 id。未实现的变体在运行时**回落**到 "tri-fissure"（不报错、不崩）。
##   🆕 2026-11-07：`SpaceModel.active_map_id` 运行时换图已落地（见
##   `scripts/geo/space_model.gd` §活动地图选择器），故全部 10 张变体标记为已实现。
const IMPLEMENTED_MAPS: Array = [
	"tri-fissure", "variant-a", "variant-b", "variant-c", "variant-d",
	"variant-e", "variant-f", "variant-g", "variant-h", "fusion",
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
#  关卡序 / 解锁（推进链 = 「首次通关」）
# ---------------------------------------------------------------------------
## 指定关卡的**下一关**（线性推进）。终局 "4-1" 之后无 → ""。
static func next_stage(stage_id: String) -> String:
	var i := STAGE_ORDER.find(stage_id)
	if i < 0 or i + 1 >= STAGE_ORDER.size():
		return ""
	return String(STAGE_ORDER[i + 1])


## 指定关卡在 STAGE_ORDER 里的下标（-1 = 未知）。
static func stage_index(stage_id: String) -> int:
	return STAGE_ORDER.find(stage_id)


## 通关某关后「自动解锁」的下一关（线性推进的核心判据）。
static func unlock_after_clear(stage_id: String) -> String:
	return next_stage(stage_id)


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
#  卡组解锁（方向反转：解锁的是「可选」，不是「更强」）
# ---------------------------------------------------------------------------
## 卡组 id 列表（SSOT）。内容等 `faction-decks.md` 定稿回填；现在先登记三个入口。
const DECK_ORDER: Array = ["cinder-adv", "rime-adv", "lattice-adv"]

## 卡组 id → 解锁它的关卡。
const DECK_UNLOCK_STAGE: Dictionary = {
	"cinder-adv": "1-3",
	"rime-adv": "2-3",
	"lattice-adv": "3-3",
}

## 卡组 id → 中文名（世界观占位）。
const DECK_NAMES: Dictionary = {
	"cinder-adv": "熔炉进阶",
	"rime-adv": "霜序进阶",
	"lattice-adv": "枢网进阶",
}


## 某卡组由哪一关解锁（"" = 无 / 未登记）。
static func deck_unlock_stage(deck_id: String) -> String:
	return String(DECK_UNLOCK_STAGE.get(deck_id, ""))


## 该卡组是否已登记（SSOT 内存在）。
static func deck_exists(deck_id: String) -> bool:
	return DECK_ORDER.has(deck_id)
