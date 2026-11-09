extends RefCounted
##
## 局外进度（Meta）—— 卡包的**解锁**与**上一局选包**
## ---------------------------------------------------------------------------
## 这一层是《卡包》功能的"记忆"：没有它，每次启动都退回"三个包全带"，
## 玩家在选包界面上做的构筑选择就白做了。
##
## 🔴 解锁口径：**历史最佳波次**（不是通关次数、不是累计击杀）。
##   依据 `design/gdd/campaign-progression.md` §3「失败也是产出」——
##   打不过也要有推进，否则「解锁 → 可选包变多」这条件永远在通关之后才生效，
##   而首次通关前的内容玩家一辈子看不见（除非他运气好）。
##   🆕 v2 地区口径（2026-11-08）：`card_packs.unlock_by_region` 打开后，解锁改由
##   「已守地区」驱动，本类的 `best_wave` **不再参与解锁判定**（只作为战绩与存档字段保留）。
##   `next_unlock_wave()` 在该口径下返回 -1。存档结构不变 → 关掉开关即可完全回滚。
##
## 🔴 存档是本次唯一新增的基础设施：`user://card_packs.json`（一个 dict）。
##   · 只存局外事实（最佳波次 / 局数 / 胜场 / 上次选包），**不存局内状态**；
##   · 局内经济、卡池权重、塔数值一律不落盘 —— 存档坏了最多回到"解锁进度归零"，
##     不会变成一个能改数值的作弊面。
##   · 读失败 / 文件损坏 → **静默回落默认值**（best_wave = 0），不阻塞开局。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → 不写 `class_name`，调用方 preload。
##

const _Packs := preload("res://scripts/data/card_packs.gd")

const SAVE_PATH := "user://card_packs.json"
const SAVE_VER := 1

## 静态状态（进程内唯一）：窗口模式下跨"再来一局"保持，重启进程后从文件恢复。
static var _loaded: bool = false
static var _best_wave: int = 0
static var _runs: int = 0
static var _wins: int = 0
static var _packs: Array = []          # 上次选包（Array[String]）
## 测试安全阀：headless 断言里把 record_* 全设 false，避免污染真实存档。
static var _save_enabled: bool = true


# ---------------------------------------------------------------------------
#  读取 / 落盘
# ---------------------------------------------------------------------------
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not _save_enabled:
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	_best_wave = maxi(0, int(d.get("best_wave", 0)))
	_runs = maxi(0, int(d.get("runs", 0)))
	_wins = maxi(0, int(d.get("wins", 0)))
	var arr: Array = []
	for nm in (d.get("packs", []) as Array):
		arr.append(String(nm))
	_packs = arr


static func save() -> void:
	if not _save_enabled:
		return
	var d := {
		"ver": SAVE_VER,
		"best_wave": _best_wave,
		"runs": _runs,
		"wins": _wins,
		"packs": _packs.duplicate(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()


## 测试用开关：关掉后本类**不读不写**磁盘（进程内状态照常可用）。
static func set_save_enabled(on: bool) -> void:
	_save_enabled = on
	if not on:
		_loaded = true            # 不再尝试读盘


# ---------------------------------------------------------------------------
#  查询
# ---------------------------------------------------------------------------
static func best_wave() -> int:
	_ensure_loaded()
	return _best_wave


static func runs() -> int:
	_ensure_loaded()
	return _runs


static func wins() -> int:
	_ensure_loaded()
	return _wins


static func unlocked_ids() -> Array:
	return _Packs.unlocked_ids(best_wave())


static func required_picks() -> int:
	return _Packs.required_picks(best_wave())


static func needs_selection() -> bool:
	return _Packs.needs_selection(best_wave())


## 上次选包（已按当前解锁状态规整）。未选过 / 已失效 → 空数组（UI 从"未选"起步）。
static func selection() -> Array:
	_ensure_loaded()
	var n := _Packs.normalize(_packs, best_wave())
	if n.size() != required_picks():
		return []
	return n


static func set_selection(sel: Array) -> void:
	_ensure_loaded()
	var n := _Packs.normalize(sel, best_wave())
	if n.size() != required_picks():
		return
	_packs = n
	save()


# ---------------------------------------------------------------------------
#  推进
# ---------------------------------------------------------------------------
## 一局结束写入进度。`wave` = 本局到达的波次（失败 = 阵亡波，胜利 = 通关波）。
##   返回本局新解锁的卡包 id（用于开局文案"新卡包已解锁"）。
static func record_run(won: bool, wave: int) -> Array:
	_ensure_loaded()
	var before: Array = _Packs.unlocked_ids(_best_wave)
	_runs += 1
	if won:
		_wins += 1
	_best_wave = maxi(_best_wave, maxi(0, wave))
	var after: Array = _Packs.unlocked_ids(_best_wave)
	save()
	var fresh: Array = []
	for pid in after:
		if not before.has(pid):
			fresh.append(String(pid))
	return fresh


## 清空进度（UI 上的"重置进度"，也是自测用的确定态入口）。
static func reset_progress() -> void:
	_best_wave = 0
	_runs = 0
	_wins = 0
	_packs = []
	_loaded = true
	if _save_enabled and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	save()


## 下一包还差多少波（UI 用；全部解锁 → -1）。
static func next_unlock_wave() -> int:
	_ensure_loaded()
	# 🔴 v2 地区口径：解锁不再由波次驱动 → 没有「下一个解锁波次」（-1 = UI 别说波次）。
	if _Packs.unlock_by_region:
		return -1
	# 🔴 全部卡包开放时没有「下一个解锁」→ -1（UI 据此显示「全部开放」而不是编个波次）。
	if _Packs.all_packs_open:
		return -1
	for p in _Packs.PACKS:
		var uw := int(p["unlock_wave"])
		if _best_wave < uw:
			return uw
	return -1
