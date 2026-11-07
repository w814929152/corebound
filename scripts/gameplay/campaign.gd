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

## 存档 schema 版本（升级存档时用；当前 v1）。
const SAVE_VERSION := 1


# ---- 运行时状态（唯一持有处）----
var _cleared: Dictionary = {}     # stage_id -> true（已通关）
var _decks: Dictionary = {}       # deck_id -> true（已解锁）
var _ember: int = 0               # Ember 余额
var _current_stage: String = "1-1"  # 当前选中的关卡（默认第 1 关）


# ---------------------------------------------------------------------------
#  加载 / 保存
# ---------------------------------------------------------------------------
## 从磁盘加载（无存档 / 解析失败 → 空状态，不崩、不报错向上抛）。
func load_save() -> void:
	_cleared = {}
	_decks = {}
	_ember = 0
	_current_stage = "1-1"
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return                       # 首次启动，无存档
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return                       # 解析失败 → 空状态（防坏档崩溃）
	var d: Dictionary = parsed
	if int(d.get("version", 0)) != SAVE_VERSION:
		return                       # 版本不符 → 空状态（保守，不迁移坏数据）
	_cleared = _as_dict(d.get("cleared", {}))
	_decks = _as_dict(d.get("decks", {}))
	_ember = int(d.get("ember", 0))
	var cs := String(d.get("current_stage", "1-1"))
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
	if not _CampaignData.STAGE_ORDER.has(sid):
		return false
	var was_new := not _cleared.has(sid)
	_cleared[sid] = true
	return was_new


## 通关后结算：记通关 → 解锁下一关 → 解锁本关绑定的卡组 → 发 Ember。
##   返回本次通关的收益摘要（供 UI 展示「解锁了什么」）。
##   🔴 只有「首次」通关才发满额 Ember；重复通关发 `EMBER_REPLAY`。
func on_cleared(stage_id: String) -> Dictionary:
	var sid := String(stage_id)
	if not _CampaignData.STAGE_ORDER.has(sid):
		return {"ok": false, "reason": "未知关卡 %s" % sid}
	var first := mark_cleared(sid)
	# 解锁下一关（线性推进）
	var unlocked_stage := ""
	if first:
		unlocked_stage = _CampaignData.unlock_after_clear(sid)
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
		"unlocked_stage": unlocked_stage,
		"unlocked_deck": unlocked_deck,
	}


## 失败结算：发 Ember（按到达波次线性，cap）。不产生任何解锁。
func on_failed(stage_id: String, reached_wave: int) -> Dictionary:
	var sid := String(stage_id)
	if not _CampaignData.STAGE_ORDER.has(sid):
		return {"ok": false, "reason": "未知关卡 %s" % sid}
	var st: Dictionary = _CampaignData.STAGES.get(sid, {})
	var wc := int(st.get("wave_count", 20))
	var gained := _CampaignData.ember_on_fail(reached_wave, wc)
	_ember += gained
	save()
	return {"ok": true, "ember_gained": gained}


# ---------------------------------------------------------------------------
#  查询（只读）
# ---------------------------------------------------------------------------
func is_cleared(stage_id: String) -> bool:
	return _cleared.has(String(stage_id))


func is_unlocked(stage_id: String) -> bool:
	# 第 1 关恒解锁（起点）；其余 = 前一关已通关
	if String(stage_id) == "1-1":
		return true
	var i := _CampaignData.stage_index(String(stage_id))
	if i <= 0:
		return false
	return is_cleared(String(_CampaignData.STAGE_ORDER[i - 1]))


func deck_unlocked(deck_id: String) -> bool:
	return _decks.has(String(deck_id))


func ember() -> int:
	return _ember


func current_stage() -> String:
	return _current_stage


func set_current_stage(stage_id: String) -> bool:
	var sid := String(stage_id)
	if not _CampaignData.STAGE_ORDER.has(sid):
		return false
	_current_stage = sid
	return true


## 用 Ember「提前解锁」某关（卡关旁路，campaign-progression §3.2）。
##   返回 {ok, cost}。🔴 已解锁则 no-op；Ember 不足则拒绝。
func unlock_stage_with_ember(stage_id: String, cost: int) -> Dictionary:
	var sid := String(stage_id)
	if is_unlocked(sid):
		return {"ok": true, "cost": 0}
	if _ember < cost:
		return {"ok": false, "cost": cost}
	_ember -= cost
	# 提前解锁 = 把前一关标记为已通关（推进链的等价操作）
	var i := _CampaignData.stage_index(sid)
	if i > 0:
		_cleared[String(_CampaignData.STAGE_ORDER[i - 1])] = true
	save()
	return {"ok": true, "cost": cost}


## 全部状态快照（UI 读这个，不改内部状态）。
func snapshot() -> Dictionary:
	return {
		"current_stage": _current_stage,
		"cleared": _cleared.duplicate(),
		"decks": _decks.duplicate(),
		"ember": _ember,
	}


# ---------------------------------------------------------------------------
#  工具
# ---------------------------------------------------------------------------
static func _as_dict(v) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v
