extends SceneTree
##
## headless 断言 —— 关卡推进系统（`scripts/data/campaign_data.gd` + `scripts/gameplay/campaign.gd`）
##
## 背景：v2 世界主线（`design/gdd/campaign-v2-overseer.md`）——
##   世界被统序（智械）侵略，玩家逐地区守卫中继站，守住即获得该地区科技（= 卡包）。
##   结构 = 中枢 1 + 外环 3 + 中环 4 + 内环 2，共 10 关；**解锁是图，不是链**。
##
## 本套件把六条纪律钉成可回归断言：
##     · 推进 = **首次通关**，且解锁是**图**（一关可同时开 0~2 关）；
##     · 门槛关（≥5 区 / 集齐 7 区 + 通关外围）**不可用 Ember 跳过**；
##     · 科技包 = 守住该地区的产物（可选入口，不是"更强的卡"）;
##     · `S` = 已守地区数，内环两关**不计数**（否则决战前会把自己推到打不过的档）；
##     · v1 存档必须迁移（保留 Ember，进度归零到中枢）—— 不能清档惩罚老玩家；
##     · 金标本零扰动（本系统只在玩家路线被读，金标本引擎不引用它）。
##
## 🔴 判据设计原则：全部用**纯函数 / 纯数据**验证，不依赖场景树、不依赖 headless 之外的
##   任何环境。存档读写用按进程命名的临时文件，测完删除。
##
## 跑法（本文件 `extends SceneTree`，故两种入口等价）：
##   <godot> --headless --path . --script res://tests/run_campaign_asserts.gd      # 只跑本套件
##   <godot> --headless --path . --script res://tests/run_tests.gd                 # 聚合入口
##
## ⚠️ Godot 坑（test_suite.gd 头注）：
##   G6 headless 无 global_script_class_cache → 一律 preload；
##   G1 int/int 整数除法 → 浮点除法两侧显式 float()。
##

const _CampaignData := preload("res://scripts/data/campaign_data.gd")
const _Campaign := preload("res://scripts/gameplay/campaign.gd")
const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _MapVariants := preload("res://scripts/data/map_variants.gd")
const _StageWaves := preload("res://scripts/data/stage_waves.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")

var _pass := 0
var _fail := 0
var _save_path := "user://campaign-test-%d.json" % OS.get_process_id()


func _initialize() -> void:
	quit(0 if run_all() else 1)


func run_all() -> bool:
	_log("")
	_log("=".repeat(78))
	_log("关卡推进系统（campaign：图状解锁 / 门槛 / 科技包 / Ember / 存档迁移 / 航图）")
	_log("基准：campaign-v2-overseer（中枢 + 外环 3 + 中环 4 + 内环 2 · 守住地区 = 入手科技）")
	_log("=".repeat(78))

	_test_data_integrity()
	_test_progression_graph()
	_test_gates()
	_test_deck_unlock()
	_test_ember_economy()
	_test_save_roundtrip()
	_test_save_migration()
	_test_max_wave()
	_test_map_variants()
	_test_map_switching()
	_test_world_map()
	DirAccess.remove_absolute(_save_path)

	_log("")
	_log("-".repeat(78))
	_log("关卡推进：PASS=%d  FAIL=%d" % [_pass, _fail])
	return _fail == 0


# ---------------------------------------------------------------------------
#  [1] 数据表完整性
# ---------------------------------------------------------------------------
func _test_data_integrity() -> void:
	_log("")
	_log("--- [1] 数据表完整性 ---")
	_check_int("关卡总数 = 10（中枢 1 + 外环 3 + 中环 4 + 内环 2）", _CampaignData.STAGE_ORDER.size(), 10)
	_check("STAGES 与 STAGE_ORDER 一一对应（无孤儿 / 无缺失）", _STAGES_match_order())
	_check("起点关 = 0-1", _CampaignData.START_STAGE == "0-1")
	_check("0-1 是唯一的起点关（无前置无门槛）",
		_CampaignData.is_start("0-1") and not _CampaignData.is_start("1-1"))

	# 环分布：1 / 3 / 4 / 2
	var per_ring := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for sid in _CampaignData.STAGE_ORDER:
		var ch := int((_CampaignData.STAGES[String(sid)] as Dictionary).get("chapter", 0))
		per_ring[ch] = int(per_ring.get(ch, 0)) + 1
	_check("环分布 1/3/4/2/1（中枢/外环/中环/内环/主脑核）",
		per_ring[1] == 1 and per_ring[2] == 3 and per_ring[3] == 4 and per_ring[4] == 1 and per_ring[5] == 1)

	# 地区：7 个，且与 REGION_ORDER 一一对应（S 与「集齐 7 区」都按它算）
	var regions: Array = []
	for sid in _CampaignData.STAGE_ORDER:
		var r := _CampaignData.region_of(String(sid))
		if r != "":
			regions.append(r)
	_check_int("地区总数 = 7", regions.size(), 7)
	_check("地区 id 与 REGION_ORDER 集合一致", _same_set(regions, _CampaignData.REGION_ORDER))
	_check("内环两关不占地区名额",
		_CampaignData.region_of("8-1") == "" and _CampaignData.region_of("9-1") == "")

	# 🔴 波数必须与波表长度一致（两个 SSOT 之间唯一的硬连接；漂移会直接把关卡套错）
	var wc_ok := true
	for sid in _CampaignData.STAGE_ORDER:
		var s := String(sid)
		if _CampaignData.wave_count(s) != _StageWaves.wave_count(s):
			wc_ok = false
			_log("   [ERR] %s：campaign=%d 波表=%d" % [
				s, _CampaignData.wave_count(s), _StageWaves.wave_count(s)])
	_check("每关 wave_count == StageWaves.wave_count（波表为准）", wc_ok)
	_check("每关都有波表（无孤儿关卡）", _all_have_pattern())

	_check("未知关卡回落三裂环", _CampaignData.resolve_map_id("9-9") == "tri-fissure")
	_check("0-1 绑定三裂环（基准图，锚点）", _CampaignData.resolve_map_id("0-1") == "tri-fissure")
	_check("2-1 绑定 rime-station", _CampaignData.resolve_map_id("2-1") == "rime-station")


func _STAGES_match_order() -> bool:
	var seen := {}
	for sid in _CampaignData.STAGE_ORDER:
		if seen.has(sid):
			return false
		seen[sid] = true
		if not _CampaignData.STAGES.has(sid):
			return false
	return _CampaignData.STAGES.size() == seen.size()


func _all_have_pattern() -> bool:
	for sid in _CampaignData.STAGE_ORDER:
		if not _StageWaves.has_stage(String(sid)):
			return false
	return true


func _same_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not b.has(x):
			return false
	return true


# ---------------------------------------------------------------------------
#  [2] 图状解锁
# ---------------------------------------------------------------------------
func _test_progression_graph() -> void:
	_log("")
	_log("--- [2] 图状解锁（外环任选起点 / 中环两条来路）---")
	var c = _Campaign.new(_save_path)
	_check("初始：0-1 解锁", c.is_unlocked("0-1"))
	_check("初始：1-1 锁定（要先通中枢）", not c.is_unlocked("1-1"))
	_check("初始：8-1 锁定（地区门槛）", not c.is_unlocked("8-1"))

	# 通中枢 → 外环三区**同时**解锁（这是"图"而不是"链"的第一个证据）
	var r: Dictionary = c.on_cleared("0-1")
	_check("通关 0-1：ok", bool(r["ok"]))
	_check("通关 0-1：首次", bool(r["first"]))
	var newly: Array = r["unlocked_stages"]
	_check_int("通关 0-1 一次开 3 关", newly.size(), 3)
	_check("外环三区全开",
		c.is_unlocked("1-1") and c.is_unlocked("2-1") and c.is_unlocked("3-1"))
	_check("0-1 不占地区（S 仍 = 0）", c.regions_cleared() == 0)

	# 通 1-1 → 开 4-1；5-1 需要 1-1 **或** 2-1 → 也开（两条来路）
	var r2: Dictionary = c.on_cleared("1-1")
	_check("通关 1-1：开 2 关（4-1 + 5-1，因为 5-1 任一条来路即可）",
		(r2["unlocked_stages"] as Array).size() == 2)
	_check("4-1 已解锁", c.is_unlocked("4-1"))
	_check("5-1 已解锁（1-1 这条来路）", c.is_unlocked("5-1"))
	_check("6-1 仍锁（要 2-1 或 3-1）", not c.is_unlocked("6-1"))
	_check_int("已守地区 = 1（1-1）", c.regions_cleared(), 1)

	# 通 2-1 → 6-1 开（2-1 是它的第一条来路）
	c.on_cleared("2-1")
	_check("6-1 已解锁（2-1 这条来路）", c.is_unlocked("6-1"))
	_check_int("已守地区 = 2", c.regions_cleared(), 2)

	# 重复通关：幂等，不再开新东西
	var r3: Dictionary = c.on_cleared("1-1")
	_check("重复通关 1-1：非首次", not bool(r3["first"]))
	_check("重复通关 1-1：不重复解锁", (r3["unlocked_stages"] as Array).is_empty())
	_check("重复通关 1-1：Ember 递减", int(r3["ember_gained"]) == _CampaignData.EMBER_REPLAY)

	# 未知关卡 → 拒绝
	var cx = _Campaign.new(_save_path)
	_check("未知关卡拒绝", not bool(cx.on_cleared("9-9")["ok"]))


# ---------------------------------------------------------------------------
#  [3] 门槛：≥5 区进外围；7 区 + 通关外围 才能决战
# ---------------------------------------------------------------------------
func _test_gates() -> void:
	_log("")
	_log("--- [3] 内环门槛 ---")
	var c = _Campaign.new(_save_path)
	c.on_cleared("0-1")
	# 守 3 区（外环）
	for sid in ["1-1", "2-1", "3-1"]:
		c.on_cleared(String(sid))
	_check_int("已守 3 区", c.regions_cleared(), 3)
	_check("3 区时 8-1 仍锁（门槛 5 区）", not c.is_unlocked("8-1"))

	# 第 4 区
	c.on_cleared("4-1")
	_check_int("已守 4 区", c.regions_cleared(), 4)
	_check("4 区时 8-1 仍锁", not c.is_unlocked("8-1"))

	# 第 5 区 → 外围开
	c.on_cleared("5-1")
	_check_int("已守 5 区", c.regions_cleared(), 5)
	_check("5 区时 8-1 解锁", c.is_unlocked("8-1"))
	_check("但 9-1 仍锁（还需 7 区 + 通关 8-1）", not c.is_unlocked("9-1"))

	# 集齐 7 区，但没打 8-1 → 9-1 仍锁
	c.on_cleared("6-1")
	c.on_cleared("7-1")
	_check_int("已守 7 区（集齐）", c.regions_cleared(), 7)
	_check("7 区但未通 8-1：9-1 仍锁", not c.is_unlocked("9-1"))

	# 通 8-1 → 9-1 开
	c.on_cleared("8-1")
	_check("通关 8-1 后 9-1 解锁", c.is_unlocked("9-1"))
	_check("内环两关不增加地区数", c.regions_cleared() == 7)

	# 门槛关不可用 Ember 跳过
	var c2 = _Campaign.new(_save_path)
	c2.on_cleared("0-1")
	c2.on_cleared("1-1")
	var u: Dictionary = c2.unlock_stage_with_ember("8-1", 5)
	_check("门槛关拒绝 Ember 跳过", not bool(u["ok"]))
	_check("拒绝理由正确", String(u.get("reason", "")).contains("门槛"))


# ---------------------------------------------------------------------------
#  [4] 科技包：守住地区 → 入手该地区科技（可选入口）
# ---------------------------------------------------------------------------
func _test_deck_unlock() -> void:
	_log("")
	_log("--- [4] 科技包 = 守住地区的产物 ---")
	var c = _Campaign.new(_save_path)
	_check("初始：熔炉科技未解锁", not c.deck_unlocked("cinder"))
	_check("包 → 关卡映射：cinder 由 1-1 打出", _CampaignData.deck_unlock_stage("cinder") == "1-1")
	_check("包 → 关卡映射：true 由 7-1 打出", _CampaignData.deck_unlock_stage("true") == "7-1")
	_check("每个地区包都有归属关卡", _every_deck_has_stage())

	c.on_cleared("0-1")
	_check("通中枢不解锁任何科技包（core 是起点科技，不占名额）",
		not c.deck_unlocked("cinder"))
	var r: Dictionary = c.on_cleared("1-1")
	_check("通关 1-1：解锁熔炉科技", String(r["unlocked_deck"]) == "cinder")
	_check("熔炉科技现已解锁", c.deck_unlocked("cinder"))
	_check("解锁不影响其他包", not c.deck_unlocked("rime"))
	_check("未登记包不存在", not _CampaignData.deck_exists("fake-deck"))
	_check("core 不在地区包登记表里（起点科技不占名额）",
		not _CampaignData.deck_exists("core"))

	# 🆕 `cleared_regions()` = 卡包解锁判据的唯一数据源（2026-11-08 接线）。
	#   🔴 它和 `regions_cleared()` 必须同源同数：一个喂 `S`（波表加压），一个喂科技包，
	#      两者漂移就会出现「难度按 3 区算，但科技包只给了 2 个」这种玩家看不懂的状态。
	var c2 = _Campaign.new(_save_path)
	_check("初始：已守地区为空", c2.cleared_regions().is_empty())
	c2.on_cleared("0-1")
	_check("通中枢不算守住地区（region 为空）", c2.cleared_regions().is_empty())
	c2.on_cleared("1-1")
	c2.on_cleared("2-1")
	_check("守住 2 区：顺序 = 地区表序（cinder, rime）",
		str(c2.cleared_regions()) == str(["cinder", "rime"]))
	_check("已守地区列表大小 == regions_cleared()（同源同数）",
		c2.cleared_regions().size() == c2.regions_cleared())
	c2.on_cleared("8-1")
	_check("打穿内环不产生地区（不涨 S、不给科技包）",
		c2.cleared_regions().size() == 2)


func _every_deck_has_stage() -> bool:
	for d in _CampaignData.DECK_ORDER:
		var s := _CampaignData.deck_unlock_stage(String(d))
		if s == "" or not _CampaignData.has_stage(s):
			return false
	return true


# ---------------------------------------------------------------------------
#  [5] Ember 局外货币
# ---------------------------------------------------------------------------
func _test_ember_economy() -> void:
	_log("")
	_log("--- [5] Ember 局外货币 ---")
	var c = _Campaign.new(_save_path)
	_check_int("初始 Ember = 0", c.ember(), 0)

	c.on_cleared("0-1")
	_check_int("通关 +%d" % _CampaignData.EMBER_CLEAR, c.ember(), _CampaignData.EMBER_CLEAR)

	var fail_ember := _CampaignData.ember_on_fail(5, 10)
	_check("失败按波次线性（0.5 进度）",
		fail_ember == int(roundf(_CampaignData.EMBER_FAIL_BASE + 0.5 * (_CampaignData.EMBER_FAIL_CAP - _CampaignData.EMBER_FAIL_BASE))))
	_check("失败奖励封顶 cap", _CampaignData.ember_on_fail(999, 10) <= _CampaignData.EMBER_FAIL_CAP)

	# 提前解锁（非门槛关）：花钱把它的一条**前置**记为已通关。
	#   🔴 用 6-1 而不是 1-1：通 0-1 后 1-1 本来就已解锁，买它只会 "cost=0" 什么都不测到。
	#   6-1 的前置是 [2-1, 3-1] → 买它会先把 2-1 记为通关（这也是"图的等价操作"）。
	var before: int = c.ember()
	var u: Dictionary = c.unlock_stage_with_ember("6-1", 5)
	_check("提前解锁 6-1：ok", bool(u["ok"]))
	_check("提前解锁扣 Ember", c.ember() == before - 5)
	_check("提前解锁后 6-1 解锁", c.is_unlocked("6-1"))
	_check("提前解锁是「补前置」而非「直接跳关」",
		c.is_cleared("2-1") and not c.is_cleared("6-1"))


# ---------------------------------------------------------------------------
#  [6] 存档往返（隔离，不污染真实存档）
# ---------------------------------------------------------------------------
func _test_save_roundtrip() -> void:
	_log("")
	_log("--- [6] 存档往返 ---")
	var c = _Campaign.new(_save_path)
	c.on_cleared("0-1")
	c.on_cleared("1-1")
	c.on_cleared("2-1")
	var snap_before: Dictionary = c.snapshot()

	var c2 = _Campaign.new(_save_path)
	c2.load_save()
	var snap_after: Dictionary = c2.snapshot()
	_check("存档往返：cleared 一致", _dict_eq(snap_before["cleared"], snap_after["cleared"]))
	_check("存档往返：decks 一致", _dict_eq(snap_before["decks"], snap_after["decks"]))
	_check_int("存档往返：ember 一致", int(snap_after["ember"]), int(snap_before["ember"]))
	_check_int("存档往返：S 一致", int(snap_after["regions_cleared"]), int(snap_before["regions_cleared"]))

	_wipe_save()
	var c3 = _Campaign.new(_save_path)
	c3.load_save()
	_check("清空后回到空状态（首次启动语义）",
		c3.ember() == 0 and not c3.is_unlocked("1-1") and c3.current_stage() == _CampaignData.START_STAGE)


# ---------------------------------------------------------------------------
#  [7] 存档迁移 v1 → v2
# ---------------------------------------------------------------------------
## 🔴 这条是"老玩家不被惩罚"的唯一保障：v1 的关卡 id 与 v2 **同名不同义**，
##   所以进度不能逐关映射 —— 但 Ember 必须全额保留。
func _test_save_migration() -> void:
	_log("")
	_log("--- [7] 存档迁移 v1 → v2 ---")
	var v1 := {
		"version": 1,
		"cleared": {"1-1": true, "1-2": true, "1-3": true},
		"decks": {"cinder-adv": true},
		"ember": 42,
		"current_stage": "2-1",
	}
	var f := FileAccess.open(_save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(v1))
		f.close()
	_check("v1 存档已写入", FileAccess.file_exists(_save_path))

	var c = _Campaign.new(_save_path)
	c.load_save()
	_check_int("迁移后 Ember 全额保留（42）", c.ember(), 42)
	_check("迁移后进度归零为「只通中枢」", c.is_cleared("0-1") and not c.is_cleared("1-1"))
	_check("迁移后当前关 = 中枢", c.current_stage() == _CampaignData.START_STAGE)
	_check("迁移后外环三区可打", c.is_unlocked("1-1") and c.is_unlocked("2-1") and c.is_unlocked("3-1"))
	_check_int("迁移后 S = 0（不假装他打过 v2 的地区）", c.regions_cleared(), 0)

	_wipe_save()


# ---------------------------------------------------------------------------
#  [8] 可变波数：默认 20 零扰动 / 覆盖生效 / 拒绝非法
# ---------------------------------------------------------------------------
func _test_max_wave() -> void:
	_log("")
	_log("--- [8] 可变波数注入（wave_director.set_max_wave / set_stage）---")
	var wd = _WaveDirector.new()
	_check("默认 _max_wave = MAX_WAVE（20，金标本等价）", wd._max_wave == _WaveDirector.MAX_WAVE)
	_check("默认即 20", wd._max_wave == 20)
	_check("覆盖：set_max_wave(10) 返回 true", wd.set_max_wave(10))
	_check("覆盖后 _max_wave = 10", wd._max_wave == 10)
	_check("非法：set_max_wave(0) 返回 false", not wd.set_max_wave(0))
	_check("非法值不改变 _max_wave", wd._max_wave == 10)

	# 波表开关关着时 set_stage 不接管波数（纯记录）
	_check("开关关：set_stage 返回 false", not wd.set_stage("3-1", 0))
	_check("开关关：不按波表改波数", wd._max_wave == 10)
	# 开关打开 → 由波表长度接管
	wd.stage_waves_enabled = true
	_check("开关开：set_stage 返回 true", wd.set_stage("3-1", 4))
	_check_int("3-1 波数 = 13（由表长决定）", wd._max_wave, 13)
	_check_int("S 已注入", wd.escalation, 4)
	wd.free()


# ---------------------------------------------------------------------------
#  [9] 战场：数据完整性 + 脊-弧互补 + 红线
# ---------------------------------------------------------------------------
func _test_map_variants() -> void:
	_log("")
	_log("--- [9] 战场（map_variants：脊-弧互补 · 开口 ≥300° · r1 ≤58）---")
	var expected: Array = _CampaignData.IMPLEMENTED_MAPS
	_check_int("已登记战场 = 19（基准 1 + v1 遗留 9 + v2 九张）", expected.size(), 19)

	var all_registered := true
	for mid in expected:
		if not _MapVariants.exists(String(mid)):
			all_registered = false
			_log("   [ERR] 未登记：%s" % String(mid))
	_check("全部战场已登记", all_registered)

	# 每关绑定的 map_id 都在变体表里登记过
	var all_mapped := true
	for sid in _CampaignData.STAGE_ORDER:
		var mid := String((_CampaignData.STAGES[String(sid)] as Dictionary).get("map_id", ""))
		if not _MapVariants.exists(mid):
			all_mapped = false
			_log("   [ERR] 关卡 %s 的 map_id %s 未登记" % [String(sid), mid])
	_check("每关的 map_id 都已登记", all_mapped)

	# v2 九张战场必须是**互不相同**的几何（不是"换张皮"）
	var sig := {}
	var distinct := true
	for sid in _CampaignData.STAGE_ORDER:
		var mid := String((_CampaignData.STAGES[String(sid)] as Dictionary).get("map_id", ""))
		var s := _geom_sig(mid)
		if sig.has(s):
			distinct = false
			_log("   [ERR] %s 与 %s 几何完全相同" % [mid, String(sig[s])])
		sig[s] = mid
	_check("十关十张不同几何（同图 = 换皮，是本轮要修的病）", distinct)

	# 红线逐张自检
	var all_valid := true
	var r1_ok := true
	var open_ok := true
	for mid in expected:
		var m := String(mid)
		var r: Dictionary = _MapVariants.validate_arcs(m)
		if not bool(r["ok"]):
			all_valid = false
			_log("   [ERR] %s 脊-弧自检失败：%s" % [m, String(r.get("reason", ""))])
		if _MapVariants.open_deg(m) < 300.0 - 1e-6:
			open_ok = false
		for rg in _MapVariants.ridges(m):
			if float((rg as Dictionary).get("r1", 0.0)) > 58.0:
				r1_ok = false
	_check("全部战场过脊-弧互补自检（开口=360−Σ脊宽，弧端点无缝）", all_valid)
	_check("全部战场开口 ≥ 300°（AC-R1 红线）", open_ok)
	_check("全部战场岩脊 r1 ≤ 58（不越出生环）", r1_ok)

	# v2 战场的战术身份：窄口 / 中环壁 / 核心护壁 必须真的存在
	_check("1-1 有 56° 窄口（全链第一个密度爆点）", _has_arc_width("cinder-forge", 56.0))
	_check("3-1 有 44° 射击走廊", _has_arc_width("rail-corridor", 44.0))
	_check("5-1 是最大空地（开口 332°）", absf(_MapVariants.open_deg("forge-union") - 332.0) < 1e-6)
	_check("6-1 是单脊超宽口（开口 336°）", absf(_MapVariants.open_deg("bio-lab") - 336.0) < 1e-6)
	_check("2-1 有中环壁（r0=14 → 在可建环内切墙）", _has_mid_wall("rime-station"))
	_check("7-1 有核心护壁（r0=8）", _has_core_wall("void-range"))
	_check("9-1 有 36° 处刑口", _has_arc_width("overseer-core", 36.0))

	# 阵地：v2 九张全部复用基准（`sites: null`）→ 零断链风险
	var sites_ok := true
	for sid in _CampaignData.STAGE_ORDER:
		var mid := String((_CampaignData.STAGES[String(sid)] as Dictionary).get("map_id", ""))
		if mid == "tri-fissure":
			continue
		if _MapVariants.sites(mid) != null:
			sites_ok = false
	_check("v2 战场全部复用基准阵地（sites=null）", sites_ok)


## 几何签名：脊的 (宽度, r0, r1) 序列 + 弧的宽度序列 —— 相同 = 同一张图。
func _geom_sig(map_id: String) -> String:
	var parts: Array = []
	for rg in _MapVariants.ridges(map_id):
		var r: Dictionary = rg
		parts.append("%.1f@%.0f-%.0f" % [
			float(r["a1"]) - float(r["a0"]), float(r["r0"]), float(r["r1"])])
	for arc in _MapVariants.spawn_arcs(map_id):
		var a: Dictionary = arc
		parts.append("w%.1f" % (float(a["a1"]) - float(a["a0"])))
	return "|".join(parts)


func _has_arc_width(map_id: String, want: float) -> bool:
	for arc in _MapVariants.spawn_arcs(map_id):
		var a: Dictionary = arc
		if absf((float(a["a1"]) - float(a["a0"])) - want) < 1e-6:
			return true
	return false


func _has_mid_wall(map_id: String) -> bool:
	for rg in _MapVariants.ridges(map_id):
		var r: Dictionary = rg
		if absf(float(r["r0"]) - 14.0) < 1e-6 or absf(float(r["r0"]) - 16.0) < 1e-6:
			return true
	return false


func _has_core_wall(map_id: String) -> bool:
	for rg in _MapVariants.ridges(map_id):
		var r: Dictionary = rg
		if float(r["r0"]) <= 8.0 + 1e-6:
			return true
	return false


# ---------------------------------------------------------------------------
#  [10] 运行时换图：默认逐位等价 / 切图生效 / 未知回落
# ---------------------------------------------------------------------------
func _test_map_switching() -> void:
	_log("")
	_log("--- [10] 运行时换图（SpaceModel.active_map_id）---")
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	_SpaceModel.layout_enabled = true

	_SpaceModel.active_map_id = "tri-fissure"
	_check("默认 active_map_id = tri-fissure", _SpaceModel.active_map_id == "tri-fissure")
	_check("默认 active_ridges() 逐位 = const RIDGES",
		_SpaceModel.active_ridges() == _SpaceModel.RIDGES)
	_check("默认 active_spawn_arcs() 逐位 = const SPAWN_ARCS",
		_SpaceModel.active_spawn_arcs() == _SpaceModel.SPAWN_ARCS)
	_check("默认 active_open_deg() = 320", absf(_SpaceModel.active_open_deg() - 320.0) < 1e-9)
	_check("默认 active_sites() 逐位 = const SITES", _BuildGrid.active_sites() == _BuildGrid.SITES)
	_check_close("默认 G(0°) = 36°（三裂环 A 口起点）", _SpaceModel.map_theta_deg(0.0), 36.0, 1e-6)

	# 切到 v2 的图：访问器返回变体表 + 阵地回落成有效 Array（实机崩过一次）
	for mid in _CampaignData.IMPLEMENTED_MAPS:
		_SpaceModel.set_active_map(String(mid))
		var act = _BuildGrid.active_sites()
		if not (typeof(act) == TYPE_ARRAY and act.size() > 0):
			_check("战场 %s 的 active_sites() 是有效 Array" % String(mid), false)
	_check("19 张战场的 active_sites() 全部有效（非 null）", true)

	_SpaceModel.set_active_map("cinder-forge")
	_check("切图后 active_ridges() = 变体表",
		_SpaceModel.active_ridges() == _MapVariants.ridges("cinder-forge"))
	_check("切图后 active_open_deg() = 306", absf(_SpaceModel.active_open_deg() - 306.0) < 1e-9)
	_check_close("切图后 G(0°) = 18°（cinder-forge 首个脊终点）",
		_SpaceModel.map_theta_deg(0.0), 18.0, 1e-6)

	_SpaceModel.set_active_map("no-such-map")
	_check("未知 id 回落 tri-fissure", _SpaceModel.active_map_id == "tri-fissure")
	_check("回落后 active_open_deg() = 320", absf(_SpaceModel.active_open_deg() - 320.0) < 1e-9)

	_SpaceModel.active_map_id = "tri-fissure"
	_SpaceModel.layout_enabled = true


# ---------------------------------------------------------------------------
#  [11] 大地图选关（裂隙航图 · 五环）
# ---------------------------------------------------------------------------
func _test_world_map() -> void:
	_log("")
	_log("--- [11] 大地图选关（裂隙航图 · 五环向心）---")
	var ov = _StageSelect.new()
	ov._build()

	var pts: Dictionary = ov.layout_points(_StageSelect.DESIGN_SIZE)
	_check_int("航图节点数 = 关卡数", pts.size(), _CampaignData.STAGE_ORDER.size())

	var center := Vector2(_StageSelect.DESIGN_SIZE.x * 0.59, _StageSelect.DESIGN_SIZE.y * 0.48)
	_check("Spiral moves inward", pts["0-1"].distance_to(center) > pts["1-1"].distance_to(center)
		and pts["1-1"].distance_to(center) > pts["4-1"].distance_to(center)
		and pts["4-1"].distance_to(center) > pts["8-1"].distance_to(center))
	_check("Final stage at core", pts["9-1"].distance_to(center) < 0.5)

	_check_int("章标题 = 5 环", _StageSelect.CHAPTER_TITLES.size(), 5)
	_check("章标题与 CampaignData 逐字一致", _titles_match())
	_check("章色互不相同（形状外的第二通道）",
		ov._chapter_color(1) != ov._chapter_color(2)
		and ov._chapter_color(2) != ov._chapter_color(3)
		and ov._chapter_color(3) != ov._chapter_color(4))

	# 节点互不重合（10 个不同位置）
	var seen: Dictionary = {}
	for sid in _CampaignData.STAGE_ORDER:
		var p: Vector2 = pts[String(sid)]
		seen["%.3f,%.3f" % [p.x, p.y]] = true
	_check_int("节点位置互不重合", seen.size(), pts.size())

	# --- 交互：锁定关进不去 ---
	var c = _Campaign.new(_save_path)
	var got: Array = []
	ov.stage_selected.connect(func(sid: String) -> void: got.append(sid))
	ov.open(c)
	_check("开局焦点 = 当前关卡（中枢）", ov.hovered() == _CampaignData.START_STAGE)
	_check("锁定关卡 enter_stage 返回 false", not ov.enter_stage("2-1"))
	_check_int("锁定关卡不发 stage_selected", got.size(), 0)
	_check("锁定关卡不改当前关", c.current_stage() == _CampaignData.START_STAGE)
	var backs: Array = []
	ov.back_requested.connect(func(): backs.append(true))
	var before_back: String = c.current_stage()
	ov.return_to_menu()
	_check("Back closes map and emits signal", not ov.visible and backs.size() == 1)
	_check("Back preserves stage and progress", c.current_stage() == before_back and not c.is_cleared("0-1"))
	ov.return_to_menu()
	_check("Hidden map does not emit back again", backs.size() == 1)
	ov.open(c)

	ov._hovered = "2-1"
	ov._refresh_detail()
	_check("锁定关卡详情提示「未解锁 · 先通关」",
		ov._detail_state.text.contains("未解锁") and ov._detail_state.text.contains("先通关"))

	# --- 交互：已解锁关可进 ---
	_check("中枢可进入", ov.enter_stage("0-1"))
	_check_int("进入发 1 次 stage_selected", got.size(), 1)
	_check("进入后界面隐藏", not ov.visible)

	# 通中枢 → 外环三区解锁 → 打开即可进
	c.on_cleared("0-1")
	ov.open(c)
	_check("通关后焦点 = 当前关（中枢）", ov.hovered() == "0-1")
	_check("1-1 已解锁可进入", ov.enter_stage("1-1"))
	_check("进入后当前关 = 1-1", c.current_stage() == "1-1")
	_check_int("累计 2 次 stage_selected", got.size(), 2)
	_check("未知关卡拒绝", not ov.enter_stage("9-9"))

	# --- 键盘焦点：沿顺序移动，越界不循环 ---
	ov.open(c)
	ov._step_hover(1)
	_check("→ 焦点移到下一关", ov.hovered() == "2-1")
	ov._step_hover(-1)
	_check("← 焦点回到上一关", ov.hovered() == "1-1")
	ov._hovered = "0-1"
	ov._step_hover(-1)
	_check("链首再往前不越界", ov.hovered() == "0-1")

	# --- 鼠标：命中测试 → 悬停 / 点击进入 ---
	ov.open(c)
	ov._points = pts
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(pts["2-1"])
	ov._on_canvas_input(mv, ov._canvas)
	_check("鼠标悬停命中节点", ov.hovered() == "2-1")

	var before := got.size()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(pts["2-1"])
	ov._on_canvas_input(click, ov._canvas)
	_check("点击已解锁节点进入", got.size() == before + 1)
	_check("点击后当前关 = 2-1", c.current_stage() == "2-1")

	# 锁定节点：点了等于没点
	ov.open(c)
	ov._points = pts
	var before2 := got.size()
	var click_locked := InputEventMouseButton.new()
	click_locked.button_index = MOUSE_BUTTON_LEFT
	click_locked.pressed = true
	click_locked.position = Vector2(pts["8-1"])
	ov._on_canvas_input(click_locked, ov._canvas)
	_check("点击锁定节点无反应", got.size() == before2)
	_check("点击锁定节点不改当前关", c.current_stage() == "2-1")


func _titles_match() -> bool:
	if _StageSelect.CHAPTER_TITLES.size() != _CampaignData.CHAPTER_TITLES.size():
		return false
	for ch in _CampaignData.CHAPTER_TITLES:
		if String(_StageSelect.CHAPTER_TITLES.get(ch, "")) != String(_CampaignData.CHAPTER_TITLES[ch]):
			return false
	return true


# ---------------------------------------------------------------------------
#  工具
# ---------------------------------------------------------------------------
func _wipe_save() -> void:
	var d := {
		"version": _Campaign.SAVE_VERSION,
		"cleared": {}, "decks": {}, "ember": 0,
		"current_stage": _CampaignData.START_STAGE,
	}
	var f := FileAccess.open(_save_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


static func _dict_eq(a, b) -> bool:
	if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
		return false
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
		if bool(a[k]) != bool(b[k]):
			return false
	return true


func _check(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		_log("   [PASS] %s" % name)
	else:
		_fail += 1
		_log("   [FAIL] %s" % name)


func _check_int(name: String, got: int, want: int) -> void:
	_check("%s（got=%d want=%d）" % [name, got, want], got == want)


func _check_close(name: String, got: float, want: float, tol: float) -> void:
	_check("%s（got=%.6f want=%.6f）" % [name, got, want], absf(got - want) <= tol)


func _log(s: String) -> void:
	print(s)
