extends RefCounted
##
## headless 断言 —— 关卡推进系统（`scripts/data/campaign_data.gd` + `scripts/gameplay/campaign.gd`）
##
## 背景：把「单局随机跑」升级为「章节推进 + 卡组解锁 + 地图变体」的 meta 骨架
##   （design/gdd/campaign-progression.md v0.1）。本套件把四条纪律钉成可回归断言：
##     · 推进链 = **首次通关**（不挂累计击杀/时长）；
##     · 卡组解锁 = 「可选」入口，不是「更强」（解锁不改任何数值）；
##     · Ember = 局外货币，只买选择、绝不买强度；
##     · 金标本零扰动（本系统只在玩家路线被读，金标本引擎不引用它）。
##
## 🔴 与卡包系统的分工（`docs/phase6/card-packs.md` §3）：本套件只测「关卡推进」这条线
##   （campaign.gd / campaign_data.gd），不碰「卡包」那条线（run_meta.gd / card_packs.gd）。
##
## 🔴 判据设计原则：全部用**纯函数 / 纯数据**验证，不依赖场景树、不依赖 headless 之外的
##   任何环境。存档读写用 `user://save.json`（与 run_meta 的 `card_packs.json` 隔离），
##   测完清理，不污染真实存档。
##
## 跑法：
##   <godot> --headless --path . --script res://tests/run_tests.gd -- campaign
##
## ⚠️ Godot 坑（test_suite.gd 头注）：
##   G6 headless 无 global_script_class_cache → 一律 preload；
##   G1 int/int 整数除法 → 浮点除法两侧显式 float()。
##

const _CampaignData := preload("res://scripts/data/campaign_data.gd")
const _Campaign := preload("res://scripts/gameplay/campaign.gd")
const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _MapVariants := preload("res://scripts/data/map_variants.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")

var _pass := 0
var _fail := 0


func run_all() -> bool:
	_log("")
	_log("=".repeat(78))
	_log("关卡推进系统（campaign：推进链 / 解锁 / Ember / 存档 / 可变波数 / 地图变体）")
	_log("基准：campaign-progression §0（首次通关 · 可选解锁 · 局外货币 · 换表不换引擎）")
	_log("=".repeat(78))

	_test_data_integrity()
	_test_progression_chain()
	_test_deck_unlock()
	_test_ember_economy()
	_test_save_roundtrip()
	_test_max_wave()
	_test_map_variants()
	_test_map_switching()

	_log("")
	_log("-".repeat(78))
	_log("关卡推进：PASS=%d  FAIL=%d" % [_pass, _fail])
	return _fail == 0


# ---------------------------------------------------------------------------
#  [1] 数据表完整性：关卡序 / 唯一性 / 回退
# ---------------------------------------------------------------------------
func _test_data_integrity() -> void:
	_log("")
	_log("--- [1] 数据表完整性 ---")
	_check_int("关卡总数 = 10（三章 × 3 + 终局）", _CampaignData.STAGE_ORDER.size(), 10)
	_check("STAGES 与 STAGE_ORDER 一一对应（无孤儿 / 无缺失）",
		_STAGES_match_order())
	_check("终局是最后一关（4-1 之后无 next）", _CampaignData.next_stage("4-1") == "")
	_check("第 1 关 1-1 是起点（index 0）", _CampaignData.stage_index("1-1") == 0)
	_check("1-1 绑定三裂环（基准图）", _CampaignData.resolve_map_id("1-1") == "tri-fissure")
	_check("2-2 绑定 variant-d（换图已落地，原样返回）",
		_CampaignData.resolve_map_id("2-2") == "variant-d")
	_check("未知关卡回落到三裂环", _CampaignData.resolve_map_id("9-9") == "tri-fissure")


## STAGES 的键集合 == STAGE_ORDER 的元素集合（且无重复）。
func _STAGES_match_order() -> bool:
	var order_size := _CampaignData.STAGE_ORDER.size()
	var seen := {}
	for sid in _CampaignData.STAGE_ORDER:
		if seen.has(sid):
			return false
		seen[sid] = true
		if not _CampaignData.STAGES.has(sid):
			return false
	return _CampaignData.STAGES.size() == order_size


# ---------------------------------------------------------------------------
#  [2] 推进链：首次通关解锁下一关（幂等）
# ---------------------------------------------------------------------------
func _test_progression_chain() -> void:
	_log("")
	_log("--- [2] 推进链 = 首次通关 ---")
	var c = _Campaign.new()
	# 起点：1-1 恒解锁，其余全锁
	_check("初始：1-1 解锁", c.is_unlocked("1-1"))
	_check("初始：1-2 锁定", not c.is_unlocked("1-2"))
	_check("初始：2-1 锁定（跨章不可跳）", not c.is_unlocked("2-1"))

	# 通关 1-1 → 解锁 1-2
	var r: Dictionary = c.on_cleared("1-1")
	_check("通关 1-1：ok", bool(r["ok"]))
	_check("通关 1-1：首次", bool(r["first"]))
	_check("通关 1-1：解锁 1-2", String(r["unlocked_stage"]) == "1-2")
	_check("1-2 现已解锁", c.is_unlocked("1-2"))
	_check("2-1 仍锁定", not c.is_unlocked("2-1"))

	# 重复通关 1-1 → 幂等，不再解锁新东西
	var r2: Dictionary = c.on_cleared("1-1")
	_check("重复通关 1-1：非首次", not bool(r2["first"]))
	_check("重复通关 1-1：不重复解锁", String(r2["unlocked_stage"]) == "")
	_check("重复通关 1-1：Ember 递减", int(r2["ember_gained"]) == _CampaignData.EMBER_REPLAY)

	# 未知关卡 → 拒绝
	var r3: Dictionary = c.on_cleared("9-9")
	_check("未知关卡拒绝", not bool(r3["ok"]))


# ---------------------------------------------------------------------------
#  [3] 卡组解锁：通关对应关卡 → 可选入口（不改数值）
# ---------------------------------------------------------------------------
func _test_deck_unlock() -> void:
	_log("")
	_log("--- [3] 卡组解锁 = 可选入口 ---")
	var c = _Campaign.new()
	_check("初始：熔炉进阶未解锁", not c.deck_unlocked("cinder-adv"))
	_check("卡组 → 关卡映射正确", _CampaignData.deck_unlock_stage("cinder-adv") == "1-3")

	# 通关 1-3 才解锁熔炉进阶
	c.on_cleared("1-1")
	c.on_cleared("1-2")
	_check("1-3 通关前：熔炉进阶仍锁", not c.deck_unlocked("cinder-adv"))
	var r: Dictionary = c.on_cleared("1-3")
	_check("通关 1-3：解锁熔炉进阶", String(r["unlocked_deck"]) == "cinder-adv")
	_check("熔炉进阶现已解锁", c.deck_unlocked("cinder-adv"))
	_check("解锁不影响其他卡组", not c.deck_unlocked("rime-adv"))

	# 未登记卡组 → 永远不解锁
	_check("未登记卡组不存在", not _CampaignData.deck_exists("fake-deck"))


# ---------------------------------------------------------------------------
#  [4] Ember 经济：只买选择、绝不买强度；失败也给但递减
# ---------------------------------------------------------------------------
func _test_ember_economy() -> void:
	_log("")
	_log("--- [4] Ember 局外货币 ---")
	var c = _Campaign.new()
	_check_int("初始 Ember = 0", c.ember(), 0)

	# 通关 → 满额
	c.on_cleared("1-1")
	_check_int("通关 +%d" % _CampaignData.EMBER_CLEAR, c.ember(), _CampaignData.EMBER_CLEAR)

	# 失败 → 也发，且随到达波次线性（cap 内）
	var fail_ember := _CampaignData.ember_on_fail(5, 10)
	_check("失败按波次线性（0.5 进度）",
		fail_ember == int(roundf(_CampaignData.EMBER_FAIL_BASE + 0.5 * (_CampaignData.EMBER_FAIL_CAP - _CampaignData.EMBER_FAIL_BASE))))
	_check("失败奖励封顶 cap", _CampaignData.ember_on_fail(999, 10) <= _CampaignData.EMBER_FAIL_CAP)

	# 提前解锁：花钱解锁，Ember 扣减
	var before: int = c.ember()
	var u: Dictionary = c.unlock_stage_with_ember("1-3", 5)
	if bool(u["ok"]):
		_check("提前解锁扣 Ember", c.ember() == before - 5)
		_check("提前解锁后 1-3 解锁", c.is_unlocked("1-3"))


# ---------------------------------------------------------------------------
#  [5] 存档：写盘 → 读盘 → 逐位一致（隔离，不污染真实存档）
# ---------------------------------------------------------------------------
func _test_save_roundtrip() -> void:
	_log("")
	_log("--- [5] 存档往返 ---")
	var c = _Campaign.new()
	c.on_cleared("1-1")
	c.on_cleared("1-2")
	c.on_cleared("1-3")     # 解锁熔炉进阶
	var snap_before: Dictionary = c.snapshot()

	var c2 = _Campaign.new()
	c2.load_save()
	var snap_after: Dictionary = c2.snapshot()
	_check("存档往返：cleared 一致",
		_dict_eq(snap_before["cleared"], snap_after["cleared"]))
	_check("存档往返：decks 一致",
		_dict_eq(snap_before["decks"], snap_after["decks"]))
	_check_int("存档往返：ember 一致", int(snap_after["ember"]), int(snap_before["ember"]))

	# 清理：清空测试存档，避免污染后续真实运行（首次启动语义）
	_wipe_save()
	var c3 = _Campaign.new()
	c3.load_save()
	_check("清空后回到空状态（首次启动语义）",
		c3.ember() == 0 and not c3.is_unlocked("1-2") and c3.current_stage() == "1-1")


# ---------------------------------------------------------------------------
#  [6] 可变波数：默认 20 零扰动 / 覆盖生效 / 拒绝非法
# ---------------------------------------------------------------------------
func _test_max_wave() -> void:
	_log("")
	_log("--- [6] 可变波数注入（wave_director.set_max_wave）---")
	var wd = _WaveDirector.new()
	_check("默认 _max_wave = MAX_WAVE（20，金标本等价）",
		wd._max_wave == _WaveDirector.MAX_WAVE)
	_check("默认即 20", wd._max_wave == 20)
	_check("覆盖：set_max_wave(10) 返回 true", wd.set_max_wave(10))
	_check("覆盖后 _max_wave = 10", wd._max_wave == 10)
	_check("覆盖：set_max_wave(15) 返回 true", wd.set_max_wave(15))
	_check("覆盖后 _max_wave = 15", wd._max_wave == 15)
	_check("非法：set_max_wave(0) 返回 false", not wd.set_max_wave(0))
	_check("非法：set_max_wave(-3) 返回 false", not wd.set_max_wave(-3))
	_check("非法值不改变 _max_wave", wd._max_wave == 15)
	wd.free()


# ---------------------------------------------------------------------------
#  [7] 地图变体：数据完整性 + 脊-弧互补 + 红线守护
# ---------------------------------------------------------------------------
func _test_map_variants() -> void:
	_log("")
	_log("--- [7] 地图变体（map_variants：换表不换引擎 · 数据先行）---")
	# 数据表完整性：10 张变体全登记，且与 campaign_data 的 map_id 一一对应
	var expected_maps := [
		"tri-fissure", "variant-a", "variant-b", "variant-c", "variant-d",
		"variant-e", "variant-f", "variant-g", "variant-h", "fusion",
	]
	for mid in expected_maps:
		_check("变体已登记：%s" % mid, _MapVariants.exists(mid))

	# 每个关卡绑定的 map_id 都在变体表里登记过
	var all_mapped := true
	for sid in _CampaignData.STAGE_ORDER:
		var st: Dictionary = _CampaignData.STAGES[sid]
		var mid := String(st.get("map_id", ""))
		if not _MapVariants.exists(mid):
			all_mapped = false
			_log("   [FAIL] 关卡 %s 的 map_id %s 未在变体表登记" % [sid, mid])
	_check("每个关卡的 map_id 都已在变体表登记", all_mapped)

	# 基准表与现有 const 表逐位一致（对照锚点，不覆盖运行时）
	var base_ridges: Array = _MapVariants.ridges("tri-fissure")
	_check("基准表脊数 = 3", base_ridges.size() == 3)
	_check("基准表开口 = 320°", absf(_MapVariants.open_deg("tri-fissure") - 320.0) < 1e-6)

	# 每张变体都过「脊-弧互补」红线自检（开口≥300 / 脊宽+弧宽=360 / 端点无缝）
	var all_valid := true
	for mid in expected_maps:
		var r: Dictionary = _MapVariants.validate_arcs(mid)
		if not bool(r["ok"]):
			all_valid = false
			_log("   [FAIL] 变体 %s 脊-弧自检失败：%s" % [mid, String(r.get("reason", ""))])
	_check("全部 %d 张变体过脊-弧互补红线自检" % expected_maps.size(), all_valid)

	# 红线：开口恒 ≥ 300°（AC-R1 下限），fusion 恰好卡在下限
	for mid in expected_maps:
		var op: float = _MapVariants.open_deg(mid)
		if op < 300.0 - 1e-6:
			_check("变体 %s 开口 %.1f ≥ 300°" % [mid, op], false)
	_check("fusion 开口 = 300°（红线下限）", absf(_MapVariants.open_deg("fusion") - 300.0) < 1e-6)

	# 红线：岩脊 r1 恒 ≤ 58（不越出生环 55 + 路肩）
	var r1_ok := true
	for mid in expected_maps:
		for rg in _MapVariants.ridges(mid):
			if float(rg.get("r1", 0.0)) > 58.0:
				r1_ok = false
	_check("全部变体岩脊 r1 ≤ 58（不越出生环）", r1_ok)

	# 阵地变体：variant-b 18 格、variant-h 18 格，其余复用基准（sites == null）
	_check("variant-b 阵地 = 18 格（孤台 +1）", _count_sites(_MapVariants.sites("variant-b")) == 18)
	_check("variant-h 阵地 = 18 格（主力台 +1）", _count_sites(_MapVariants.sites("variant-h")) == 18)
	_check("variant-a 复用基准阵地（sites=null）", _MapVariants.sites("variant-a") == null)
	_check("fusion 复用基准阵地（sites=null）", _MapVariants.sites("fusion") == null)


## 阵地表的格子总数。
func _count_sites(sites) -> int:
	if sites == null:
		return 0
	var n := 0
	for s in sites:
		n += (s["cells"] as Array).size()
	return n


# ---------------------------------------------------------------------------
#  [8] 运行时换图：默认逐位等价 / 切图生效 / 未知回落（碰金标本路径，逐位守护）
# ---------------------------------------------------------------------------
func _test_map_switching() -> void:
	_log("")
	_log("--- [8] 运行时换图（SpaceModel.active_map_id · 换表不换引擎）---")

	# 🔴 前提：本套件运行在 RADIAL + layout 下才消费活动表；先设回确定性基线。
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	_SpaceModel.layout_enabled = true

	# ① 默认 = tri-fissure，访问器逐位返回 const 表
	_SpaceModel.active_map_id = "tri-fissure"
	_check("默认 active_map_id = tri-fissure", _SpaceModel.active_map_id == "tri-fissure")
	_check("默认 active_ridges() 逐位 = const RIDGES",
		_SpaceModel.active_ridges() == _SpaceModel.RIDGES)
	_check("默认 active_spawn_arcs() 逐位 = const SPAWN_ARCS",
		_SpaceModel.active_spawn_arcs() == _SpaceModel.SPAWN_ARCS)
	_check("默认 active_open_deg() = 320", absf(_SpaceModel.active_open_deg() - 320.0) < 1e-9)
	_check("默认 active_sites() 逐位 = const SITES",
		_BuildGrid.active_sites() == _BuildGrid.SITES)

	# ② 默认下 map_theta_deg 输出与切图前一致（金标本锚点：0° → 36°）
	_check_close("默认 G(0°) = 36°（三裂环 A 口起点）", _SpaceModel.map_theta_deg(0.0), 36.0, 1e-6)
	_check_close("默认 G(360°⁻) = 18°（C 口绕回接 G1）", _SpaceModel.map_theta_deg(359.9999), 18.0, 1e-3)

	# ③ 切到 variant-a（开口 306°）：访问器返回变体表
	_SpaceModel.set_active_map("variant-a")
	_check("切图后 active_map_id = variant-a", _SpaceModel.active_map_id == "variant-a")
	_check("切图后 active_open_deg() = 306", absf(_SpaceModel.active_open_deg() - 306.0) < 1e-9)
	_check("切图后 active_ridges() = 变体表",
		_SpaceModel.active_ridges() == _MapVariants.ridges("variant-a"))
	_check("切图后 active_spawn_arcs() = 变体表",
		_SpaceModel.active_spawn_arcs() == _MapVariants.spawn_arcs("variant-a"))

	# ④ 切图后 map_theta_deg 映射改变（variant-a A 口 a0=39°，故 G(0°)=39°）
	_check_close("切图后 G(0°) = 39°（variant-a A 口起点）", _SpaceModel.map_theta_deg(0.0), 39.0, 1e-6)
	_check("切图后 is_ridge_deg 用变体脊（G1 15~39，30° 在脊内）",
		_SpaceModel.is_ridge_deg(30.0))

	# ⑤ 阵地变体：variant-b 有 18 格阵地（孤台 +1），active_sites 返回变体表
	_SpaceModel.set_active_map("variant-b")
	_check("variant-b active_sites 为变体（非 null）", _BuildGrid.active_sites() != null)
	var vb_cells: Array = _BuildGrid.site_points()
	_check("variant-b 可建阵地格 = 18", vb_cells.size() == 18)
	# 换图后 site_index 缓存按 map_id 失效重建（N2 变双格）
	_check("variant-b 的 site_index 含新增格（-1,-14）",
		_BuildGrid.site_index().has(Vector2i(-1, -14)))

	# ⑥ 未知 id → 回落 tri-fissure（不崩、逐位回 const）
	_SpaceModel.set_active_map("no-such-map")
	_check("未知 id 回落 tri-fissure", _SpaceModel.active_map_id == "tri-fissure")
	_check("回落后 active_open_deg() = 320", absf(_SpaceModel.active_open_deg() - 320.0) < 1e-9)

	# 🔴 收尾：设回默认，避免污染其他套件 / 金标本。
	_SpaceModel.active_map_id = "tri-fissure"
	_SpaceModel.layout_enabled = true


# ---------------------------------------------------------------------------
#  工具
# ---------------------------------------------------------------------------
func _wipe_save() -> void:
	var d := {
		"version": _Campaign.SAVE_VERSION,
		"cleared": {}, "decks": {}, "ember": 0, "current_stage": "1-1",
	}
	var f := FileAccess.open(_Campaign.SAVE_PATH, FileAccess.WRITE)
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


## 带容差的浮点检查。
func _check_close(name: String, got: float, want: float, tol: float) -> void:
	_check("%s（got=%.6f want=%.6f）" % [name, got, want], absf(got - want) <= tol)


func _log(s: String) -> void:
	print(s)
