extends RefCounted
##
## 关卡进度管理 `Campaign` —— 推进状态 + 存档（关卡推进那半条线）
##
## 🔴 定位：这是「关卡推进」系统的**状态权威**。持有：
##   · 已通关关卡集合（推进链 = 首次通关）
##   · 已解锁卡组集合（方向反转：可选，不是更强）
##   · Ember 余额（局外货币，只解锁选择）
##   持久化到 `user://save.json`（单文件 dict，P0 基础设施）。
##
## 🔴 与卡包系统的分工（`docs/phase6/card-packs.md` §3）：本文件与 `run_meta.gd`
##   是**两条线**，当前**不合并**、互不读写对方的存档。收敛点在「解锁判据」一个函数
##   （`RunMeta.unlocked_ids()`）—— 关卡系统接进 `boot.gd` 后，把 `unlock_wave` 换成
##   「已通关关卡」即可，卡包表与 UI 不用动。**当前不合并，是为了不让任一系统卡在
##   对方的半成品上。**
##
## 🔴 金标本零扰动：本文件只在**玩家路线的关卡系统**里被读写；金标本引擎
##   （run_loop / wave_sim / shop_ai + MC）从不引用 → 逐位不变。
##   · 未通关任何关时，`current_stage()` 返回 "1-1"，且所有解锁为空 → 与「无 meta」等价。
##
## 🔴 设计纪律（campaign-progression §0）：
##   · 关卡推进挂「首次通关」，不挂累计击杀/时长；
##   · 卡组解锁 = 池子扩容的「可选入口」，不是「更强的卡」；
##   · Ember 只买选择、绝不买强度。
##
## ⚠️ Godot 坑
##   G6 headless 无 global_script_class_cache → 不写 class_name，一律 preload。
##   G1 int/int 整数除法 → 浮点除法两侧显式 float()。
##

const _CampaignData := preload("res://scripts/data/campaign_data.gd")

const SAVE_PATH := "user://save.json"

## 存档 schema 版本。
##   v1 = 旧「三章 × 3 关 + 终局」的 10 关（id 1-1..4-1）；
##   v2 = 世界主线十关（id 0-1..9-1，**同名不同义**）+ 图状解锁 + 地区计数。
##   🔴 必须迁移，不能"版本不符就空档"：v1 的 "1-1" 与 v2 的 "1-1" 是两张完全不同的图，
##      但玩家的 Ember 与『他已经打过一段』这件事是真实投入，清掉等于惩罚老玩家。
const SAVE_VERSION := 2


# ---- 运行时状态（唯一持有处）----
var _cleared: Dictionary = {}     # stage_id -> true（已通关）
var _decks: Dictionary = {}       # deck_id -> true（已解锁）
var _ember: int = 0               # Ember 余额
var _current_stage: String = _CampaignData.START_STAGE  # 当前选中的关卡（默认起点关）


# ---------------------------------------------------------------------------
#  加载 / 保存
# ---------------------------------------------------------------------------
## 从磁盘加载（无存档 / 解析失败 → 空状态，不崩、不报错向上抛）。
func load_save() -> void:
	_cleared = {}
	_decks = {}
	_ember = 0
	_current_stage = _CampaignData.START_STAGE
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return                       # 首次启动，无存档
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return                       # 解析失败 → 空状态（防坏档崩溃）
	var d: Dictionary = parsed
	var ver := int(d.get("version", 0))
	if ver == 1:
		d = _migrate_v1_to_v2(d)     # 旧十关 → 世界主线十关（见函数头注）
	elif ver != SAVE_VERSION:
		return                       # 未知版本 → 空状态（保守，不迁移坏数据）
	_cleared = _as_dict(d.get("cleared", {}))
	_decks = _as_dict(d.get("decks", {}))
	_ember = int(d.get("ember", 0))
	var cs := String(d.get("current_stage", _CampaignData.START_STAGE))
	if _CampaignData.STAGE_ORDER.has(cs):
		_current_stage = cs


## 写盘（覆盖写）。返回是否成功。
func save() -> bool:
	var d := {
		"version": SAVE_VERSION,
		"cleared": _cleared,
		"decks": _decks,
		"ember": _ember,
		"current_stage": _current_stage,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	return true


# ---------------------------------------------------------------------------
#  推进：首次通关记账
# ---------------------------------------------------------------------------
## 记录某关**首次**通关（幂等：重复通关不重复解锁）。返回本次是否发生了新解锁。
func mark_cleared(stage_id: String) -> bool:
	var sid := String(stage_id)
	if not _CampaignData.has_stage(sid):
		return false
	var was_new := not _cleared.has(sid)
	_cleared[sid] = true
	return was_new


## 通关后结算：记通关 → 解锁下一关 → 解锁本关绑定的卡组 → 发 Ember。
##   返回本次通关的收益摘要（供 UI 展示「解锁了什么」）。
##   🔴 只有「首次」通关才发满额 Ember；重复通关发 `EMBER_REPLAY`。
func on_cleared(stage_id: String) -> Dictionary:
	var sid := String(stage_id)
	if not _CampaignData.has_stage(sid):
		return {"ok": false, "reason": "未知关卡 %s" % sid}
	# 🔴 图状解锁下「这一关通了会开哪些」不是单数（一关可能同时开 0~2 关）。
	#    做法：通关前先拍一份「解锁态快照」，通关后再比一遍 → 差集就是本次新开的。
	#    这样不必为每条边写反向索引，改了 `prereq` 表也不会漏算。
	var before := {}
	for s in _CampaignData.STAGE_ORDER:
		before[String(s)] = is_unlocked(String(s))
	var first := mark_cleared(sid)
	var newly: Array = []
	if first:
		for s in _CampaignData.STAGE_ORDER:
			var ss := String(s)
			if not bool(before[ss]) and is_unlocked(ss):
				newly.append(ss)
	var unlocked_stage := "" if newly.is_empty() else String(newly[0])
	# 解锁本关绑定的卡组
	var unlocked_deck := ""
	var st: Dictionary = _CampaignData.STAGES.get(sid, {})
	var dk := String(st.get("unlock_deck", ""))
	if dk != "" and _CampaignData.deck_exists(dk):
		_decks[dk] = true
		unlocked_deck = dk
	# Ember：首次满额 / 重复递减
	var gained := _CampaignData.EMBER_CLEAR if first else _CampaignData.EMBER_REPLAY
	_ember += gained
	save()
	return {
		"ok": true,
		"first": first,
		"ember_gained": gained,
		"unlocked_stage": unlocked_stage,       # 兼容旧调用：新开的第一关
		"unlocked_stages": newly,               # 图状解锁的真实结果（0~2 个）
		"unlocked_deck": unlocked_deck,
		"regions_cleared": regions_cleared(),
	}


## 失败结算：发 Ember（按到达波次线性，cap）。不产生任何解锁。
func on_failed(stage_id: String, reached_wave: int) -> Dictionary:
	var sid := String(stage_id)
	if not _CampaignData.has_stage(sid):
		return {"ok": false, "reason": "未知关卡 %s" % sid}
	var wc := _CampaignData.wave_count(sid)
	var gained := _CampaignData.ember_on_fail(reached_wave, wc)
	_ember += gained
	save()
	return {"ok": true, "ember_gained": gained}


# ---------------------------------------------------------------------------
#  查询（只读）
# ---------------------------------------------------------------------------
func is_cleared(stage_id: String) -> bool:
	return _cleared.has(String(stage_id))


## 解锁判定（图 + 两道门槛）。
##   ① 起点关恒解锁；
##   ② 某关必须已通关（`need_cleared`）；
##   ③ 已守地区数 ≥ N（`need_regions`）；
##   ④ 前置关**任一**通关（`prereq`）。
##   🔴 顺序不能换：门槛先判，前置后判 —— 否则 8-1 会在只守了 1 区时就因为
##      "prereq 为空"被当成起点关放行。
func is_unlocked(stage_id: String) -> bool:
	var sid := String(stage_id)
	if not _CampaignData.has_stage(sid):
		return false
	if _CampaignData.is_start(sid):
		return true
	var need := _CampaignData.need_cleared(sid)
	if need != "" and not is_cleared(need):
		return false
	var nr := _CampaignData.need_regions(sid)
	if nr > 0 and regions_cleared() < nr:
		return false
	var pre: Array = _CampaignData.prereqs(sid)
	if pre.is_empty():
		return true                  # 纯门槛关：门槛都过了就开
	for p in pre:
		if is_cleared(String(p)):
			return true
	return false


## 已守地区数 = 难度自变量 `S`（只数 `region != ""` 的关卡）。
##   🔴 内环 8-1 / 9-1 的 `region` 故意为空：它们是"打穿智械腹地"，不算"救了一个地区"，
##      否则玩家会在决战前把 `S` 推到自己打不过的档位。
func regions_cleared() -> int:
	var n := 0
	for s in _CampaignData.STAGE_ORDER:
		var sid := String(s)
		if _CampaignData.region_of(sid) != "" and is_cleared(sid):
			n += 1
	return n


func deck_unlocked(deck_id: String) -> bool:
	return _decks.has(String(deck_id))


## 已守住的地区 id 列表（按 `REGION_ORDER` 序）—— 科技包解锁判据的唯一数据源。
##   🔴 用 `DECK_UNLOCK_STAGE` 反查（而不是遍历关卡看 `region` 字段）：解锁的是**科技**，
##      判据就该是"哪一关打出这个科技"。两处口径若漂移，`run_card_pack_asserts` V-6 会红。
func cleared_regions() -> Array:
	var out: Array = []
	for r in _CampaignData.REGION_ORDER:
		var rid := String(r)
		var st := _CampaignData.deck_unlock_stage(rid)
		if st != "" and is_cleared(st):
			out.append(rid)
	return out


func ember() -> int:
	return _ember


func current_stage() -> String:
	return _current_stage


func set_current_stage(stage_id: String) -> bool:
	var sid := String(stage_id)
	if not _CampaignData.has_stage(sid):
		return false
	_current_stage = sid
	return true


## 用 Ember「提前解锁」某关（卡关旁路，campaign-progression §3.2）。
##   返回 {ok, cost}。🔴 已解锁则 no-op；Ember 不足则拒绝。
func unlock_stage_with_ember(stage_id: String, cost: int) -> Dictionary:
	var sid := String(stage_id)
	if not _CampaignData.has_stage(sid):
		return {"ok": false, "cost": cost, "reason": "未知关卡"}
	if is_unlocked(sid):
		return {"ok": true, "cost": 0}
	# 🔴 门槛关（内环）**不可**用 Ember 跳过：它挡的是剧情进度，不是难度。
	#    允许买通会让"守了 3 区就去打主脑"，把 `S` 的分层意义整个抹掉。
	if _CampaignData.need_regions(sid) > 0 or _CampaignData.need_cleared(sid) != "":
		return {"ok": false, "cost": cost, "reason": "门槛关不可跳过"}
	# 提前解锁 = 把它的一条前置「记为已通关」（图的等价操作）
	var via := ""
	for p in _CampaignData.prereqs(sid):
		if not is_cleared(String(p)):
			via = String(p)
			break
	if via == "":
		return {"ok": false, "cost": cost, "reason": "无可用前置"}
	if _ember < cost:
		return {"ok": false, "cost": cost}
	_ember -= cost
	_cleared[via] = true
	save()
	return {"ok": true, "cost": cost, "via": via}


## 全部状态快照（UI 读这个，不改内部状态）。
func snapshot() -> Dictionary:
	return {
		"current_stage": _current_stage,
		"cleared": _cleared.duplicate(),
		"decks": _decks.duplicate(),
		"ember": _ember,
		# 🆕 v2 只读键（additive，不改变既有键语义）：难度自变量 S 与解锁态
		"regions_cleared": regions_cleared(),
		"escalation": regions_cleared(),
	}


# ---------------------------------------------------------------------------
#  存档迁移 v1 → v2
# ---------------------------------------------------------------------------
## v1 = 旧「三章 × 3 关 + 终局」线性十关；v2 = 世界主线十关（图状解锁）。
##
## 🔴 v1 的关卡**无法逐关映射**到 v2：两套 id 在 "1-1" / "2-1" / "3-1" / "4-1" 上**同名不同义**
##    （v1 的 1-1 是"余烬·初燃"三裂环，v2 的 1-1 是"灰烬熔炉"窄口图）。硬映射会让老玩家
##    的进度条跳到一张他从没打过的图上，而且"已通关"会让它直接跳过。
##
## 取舍（保守且不惩罚）：
##   · **Ember 全额保留** —— 那是真实投入，且只买"选择"不买"强度"，保留不会破坏平衡；
##   · **卡组解锁保留** —— 旧 id（`cinder-adv` 等）在新表里不存在，`deck_exists()` 恒 false，
##     所以它既不生效也不报错，留着比删掉更安全（万一将来做包别名）；
##   · **关卡进度归零为「只通了中枢 0-1」** —— 不假装他打过 v2 的任何一个地区。
##     这样老玩家从外环三区重新选路，但一开局就有 Ember、有中枢作起点。
##   · `current_stage` 一律回中枢：旧 current_stage 指向的是一张语义不同的图。
static func _migrate_v1_to_v2(d: Dictionary) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"cleared": {_CampaignData.START_STAGE: true},
		"decks": _as_dict(d.get("decks", {})),
		"ember": int(d.get("ember", 0)),
		"current_stage": _CampaignData.START_STAGE,
	}


# ---------------------------------------------------------------------------
#  工具
# ---------------------------------------------------------------------------
static func _as_dict(v) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v
