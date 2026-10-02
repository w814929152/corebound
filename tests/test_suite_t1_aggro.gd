extends RefCounted
##
## headless 自测套件 —— T1「塔死亡玩法批次」仇恨激活（Q-T2/Q-T3/Q-T4 定稿）
##
## 🔴 本套件的目的（design/gdd/mechanics-tower-life-death §2 + wave-spawner §2.6）：
##    验证「机会型仇恨（AGGRO_R=9.0）+ 塔 HP（HP0×h^0.6）+ Disabled 中间态」
##    在 tower_aggro_enabled=true 时按定稿工作，且 **false 时与金标本逐位等价**。
##
## 判据来源（一字不改的定稿）：
##   · Q-T2 = ①：塔 HP = HP0 × h^0.6（HP0=120，指数复用 tower_stack_exp=0.6）
##   · Q-T3 = ①：机会型仇恨（AGGRO_R=9.0 进 / AGGRO_EXIT=10.8 迟滞带退出）
##   · Q-T4 = ①：塔归零 → Disabled 中间态（断输出不断链，仍占塔位供 h_j）
##   · 硬约束 T-C1：战斗内零可操作（塔死不在战斗内结算售卖/修复）
##
## 🔴 最硬的两条：
##   1) **等价性守护**：tower_aggro_enabled=false → 实时版/批处理版与金标本
##      `WaveSim.simulate_wave` **逐位一致**（金标本零改动，判据链不变）。
##   2) **仇恨只改路径不改 DPS 分配**：仇恨开启后 DPS 分配口径不变（全场池→t_remain
##      排序→填满→结转），只改怪物态（Marching↔AggroTower）与塔损耗。
##
## 🔴 金标本零改动：`wave_sim.gd` / `run_loop.gd` 一字不改；本套件测的是
##    新建镜像 `wave_sim_aggro.gd` / `run_loop_aggro.gd` + `WaveDirector` 仇恨分支。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- t1aggro
##

const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _Monster := preload("res://scripts/gameplay/monster.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")

var _pass = 0
var _fail = 0
var _out: Array = []


func _log(s: String) -> void:
	_out.append(s)
	print(s)


func _check(name: String, got: float, want: float, tol: float = 1e-9) -> void:
	var d = absf(got - want)
	var ok = (d <= 1e-300) or (d <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%.6f want=%.6f |d|=%s" % ["PASS" if ok else "FAIL", name, got, want, str(d)])


func _check_int(name: String, got: int, want: int) -> void:
	if got == want:
		_pass += 1
		_log("   [PASS] %s  got=%d want=%d" % [name, got, want])
	else:
		_fail += 1
		_log("   [FAIL] %s  got=%d want=%d" % [name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	if got == want:
		_pass += 1
		_log("   [PASS] %s  got=%s want=%s" % [name, str(got), str(want)])
	else:
		_fail += 1
		_log("   [FAIL] %s  got=%s want=%s" % [name, str(got), str(want)])


# ---------------------------------------------------------------------------
#  工具：造一个 player（B 路线，起手塔），可指定只在某 slot 留一座塔
# ---------------------------------------------------------------------------
func _mk_player_with_tower(slot: int, ctype: String, h: int):
	var p = _SimPlayer.new_player("B", _Cfg.cfg_of("B"), _Geo6.build())
	p.towers = []
	p.towers.append(_PS.make_tower(slot, ctype, h, {}))
	return p


func _mk_director(player, aggro: bool):
	var cfg = _Cfg.cfg_of("B")
	var geo = _Geo6.build()
	var wd = _WaveDirector.new()
	wd.tower_aggro_enabled = aggro
	wd.setup(player, cfg, geo)
	return wd


# ===========================================================================
#  AC-T1-1 · 塔 HP 派生数学（Q-T2 = ①：HP0 × h^0.6）
# ===========================================================================
func _test_tower_hp_derivation() -> void:
	_log("")
	_log("--- [AC-T1-1] 塔 HP 派生：HP0 × h^0.6（复用 tower_stack_exp）---")
	_check("HP0 = 120（全场统一，Q-T2）", _MonsterData.HP0, 120.0)
	_check("h=1 → HP=120", _MonsterData.tower_hp(1), 120.0)
	# h=133 → 133^0.6 ≈ 18.79 → HP ≈ 2255（次线性：深塔更难死但仍会死）
	var hp133 := _MonsterData.tower_hp(133)
	_check("h=133 → HP≈2255（次线性 ∝ h^0.6）", hp133, 120.0 * pow(133.0, 0.6), 1.0)
	# 与 damage_engine 的 Base 用同一指数（tower_stack_exp=0.6）→ 逐位同口径
	var cfg := _Cfg.cfg_of("B")
	_check("指数复用 tower_stack_exp=0.6", float(cfg["tower_stack_exp"]), 0.6)


# ===========================================================================
#  AC-T1-2 · 仇恨常量登记（Q-T3 = ① 定稿值）
# ===========================================================================
func _test_aggro_constants() -> void:
	_log("")
	_log("--- [AC-T1-2] 仇恨常量登记（Q-T3 定稿值，一字不改）---")
	_check("AGGRO_R = 9.0（转向半径）", _MonsterData.AGGRO_R, 9.0)
	_check("AGGRO_EXIT = 10.8（迟滞带退出 = 9.0×1.2）", _MonsterData.AGGRO_EXIT, 10.8)
	_check("AGGRO_TICK = 0.10（判定频率 = sim dt）", _MonsterData.AGGRO_TICK, 0.10)
	# ATTRITION 是 PLACEHOLDER（V-1 扫参基比），登记但待重扫
	_check("ATTRITION 已登记（PLACEHOLDER · V-1 扫参基比）", _MonsterData.ATTRITION, 0.5)


# ===========================================================================
#  AC-T1-3 · 等价性守护（实时版）：aggro=false == 金标本 simulate_wave
# ===========================================================================
func _test_golden_equiv_realtime() -> void:
	_log("")
	_log("--- [AC-T1-3] 等价守护（实时版）：aggro=false == 金标本 simulate_wave ---")
	var geo = _Geo6.build()
	# 用一个有起手塔的普通 player（B 路线）
	var p = _SimPlayer.new_player("B", _Cfg.cfg_of("B"), geo)
	var cfg = _Cfg.cfg_of("B")
	# 金标本
	var golden := _WaveSim.simulate_wave(p, 1, cfg, geo)
	# 实时版 aggro=false
	var wd = _mk_director(p, false)
	wd.start_wave(1)
	var res = wd.run_to_end()
	_check("W1 击杀数一致（实时 vs 金标本）", float(res["kills"]), float(golden["kills"]))
	_check("W1 漏怪数一致", float(res["leaked"]), float(golden["leaked"]))
	_check("W1 scrap 一致", float(res["scrap_earned"]), float(golden["scrap_earned"]))
	_check("W1 core_damage 一致", float(res["core_damage"]), float(golden["core_damage"]))


# ===========================================================================
#  AC-T1-4 · 等价性守护（批处理镜像）：aggro=false == 金标本
# ===========================================================================
func _test_golden_equiv_batch() -> void:
	_log("")
	_log("--- [AC-T1-4] 等价守护（批处理镜像）：aggro=false == 金标本 simulate_wave ---")
	var geo = _Geo6.build()
	var p = _SimPlayer.new_player("B", _Cfg.cfg_of("B"), geo)
	var cfg = _Cfg.cfg_of("B")
	var golden := _WaveSim.simulate_wave(p, 1, cfg, geo)
	var aggro := _WaveSimAggro.simulate_wave_aggro(p, 1, cfg, geo, false)
	_check("W1 击杀数一致（批处理 aggro=false vs 金标本）", float(aggro["kills"]), float(golden["kills"]))
	_check("W1 漏怪数一致", float(aggro["leaked"]), float(golden["leaked"]))
	_check("W1 scrap 一致", float(aggro["scrap_earned"]), float(golden["scrap_earned"]))
	_check("W1 无塔死亡（aggro=false → towers_disabled=0）", float(aggro["towers_disabled"]), 0.0)


# ===========================================================================
#  AC-T1-5 · 仇恨状态机：暴露位塔 → 怪转 AggroTower（单元测，不依赖战斗平衡）
# ===========================================================================
func _test_aggro_state_machine() -> void:
	_log("")
	_log("--- [AC-T1-5] 仇恨状态机：暴露位塔(S0) → 怪转 AggroTower ---")
	# 只在 S0（暴露位，d_path=6.00 ≤ 9.0）放一座 h=1 塔
	var p = _mk_player_with_tower(0, "Arrow", 1)
	var wd = _mk_director(p, true)   # aggro=true
	wd.start_wave(1)
	# 摆一只高血怪在路径起点（t_remain≈9.4 → s≈6，距 S0 塔 8.0 ≤ 9.0）
	# 🔴 高血（hp=10000）保证怪不被集火秒杀，能转 AggroTower
	wd.debug_set_monsters([9.4], 10000.0)
	# 推进一个子步（0.1s）
	wd.advance(_WaveSim.DT)
	var snap := wd.snapshot()
	_check_bool("W1 有怪进入 AggroTower 态（暴露位 S0 触发仇恨）",
		_snap_has_state(snap, _Monster.State.AGGRO_TOWER), true)
	# 该怪的目标塔应是 S0
	var targeting_s0 := _snap_monster_targeting(snap, 0)
	_check_bool("AggroTower 怪锁定目标塔 = S0（最近暴露塔）", targeting_s0, true)


# ===========================================================================
#  AC-T1-6 · 塔死亡：暴露位塔被持续攻击 → Disabled 中间态
# ===========================================================================
func _test_aggro_tower_destroyed() -> void:
	_log("")
	_log("--- [AC-T1-6] 塔死亡：暴露位塔(S0) 被 AggroTower 怪打死 → Disabled ---")
	var p = _mk_player_with_tower(0, "Arrow", 1)   # h=1 → HP=120
	var wd = _mk_director(p, true)
	wd.start_wave(1)
	# 高血怪在路径起点（持续 AggroTower 打 S0 塔）
	wd.debug_set_monsters([9.4], 10000.0)
	# 🔴 Godot 坑：用 Dictionary 引用捕获 tower_destroyed 信号
	var box := { "n": 0, "slot": -1 }
	wd.tower_destroyed.connect(func(slot: int) -> void:
		box["n"] = int(box["n"]) + 1
		box["slot"] = int(slot))
	# 推进足够子步让塔死（对塔 DPS = ATTRITION×HP0×m_dps = 0.5×120×0.60 = 36 → 120/36 ≈ 3.33s）
	# advance 5.0s = 50 子步，足够打死（留余量）
	wd.advance(5.0)
	_check_int("tower_destroyed 信号发过一次", int(box["n"]), 1)
	_check_int("死亡的是 S0 塔", int(box["slot"]), 0)
	_check_bool("S0 塔进入 Disabled 中间态（断输出不断链）",
		bool(p.towers[0].disabled), true)
	_check("S0 塔 hp 归零", float(p.towers[0].hp), 0.0)


# ===========================================================================
#  AC-T1-7 · 安全位塔免疫：S4（d_path=10.82 > 9.0）不被仇恨
# ===========================================================================
func _test_safe_slot_immune() -> void:
	_log("")
	_log("--- [AC-T1-7] 安全位免疫：S4 塔(d_path>9.0) aggro=true 不被打死 ---")
	# 验证 S4 确实是安全位（d_path > AGGRO_R）——S4 坐标 = SLOTS6[4] = (18,16)
	var s4_pos := _Geo6.SLOTS6[4]
	var s4_dist := _PathGeometry.dist_to_path(s4_pos)
	_check("S4 d_path > AGGRO_R=9.0（安全位，不被仇恨）", s4_dist, 10.82, 0.5)
	# 只在 S4 放塔，aggro=true 跑完整波 → 塔不死
	var p = _mk_player_with_tower(4, "Arrow", 1)
	var wd = _mk_director(p, true)
	wd.start_wave(1)
	wd.run_to_end()
	_check("S4 塔 aggro=true 全程未被仇恨（towers_disabled=0）",
		float(wd.last_result.get("towers_disabled", 0)), 0.0)
	_check_bool("S4 塔未进入 Disabled", bool(p.towers[0].disabled), false)


# ===========================================================================
#  AC-T1-8 · 仇恨效果：aggro=true 出现塔死亡（vs aggro=false 无塔死）
# ===========================================================================
func _test_aggro_effect_batch() -> void:
	_log("")
	_log("--- [AC-T1-8] 仇恨效果（批处理）：aggro=true 有塔死，aggro=false 无 ---")
	var geo = _Geo6.build()
	# 在暴露位 S0 放塔，让仇恨能打中
	var p = _mk_player_with_tower(0, "Arrow", 1)
	var cfg = _Cfg.cfg_of("B")
	var off := _WaveSimAggro.simulate_wave_aggro(p, 1, cfg, geo, false)
	# 重新造 player（塔满血）测 aggro=true
	var p2 = _mk_player_with_tower(0, "Arrow", 1)
	var on := _WaveSimAggro.simulate_wave_aggro(p2, 1, cfg, geo, true)
	_check("aggro=false → 无塔死", float(off["towers_disabled"]), 0.0)
	_check_bool("aggro=true → 出现塔死（暴露位 S0 被打中）",
		int(on["towers_disabled"]) > 0, true)


# ===========================================================================
#  AC-T1-9 · 实时版 ↔ 批处理镜像一致性（aggro=true）
# ===========================================================================
func _test_realtime_batch_consistency() -> void:
	_log("")
	_log("--- [AC-T1-9] 实时↔批处理一致（aggro=true）：kills/leaked/scrap 逐位相同 ---")
	var geo = _Geo6.build()
	var cfg = _Cfg.cfg_of("B")
	# 暴露位 S0 放塔
	var p_rt = _mk_player_with_tower(0, "Arrow", 1)
	var wd = _mk_director(p_rt, true)
	wd.start_wave(1)
	var rt := wd.run_to_end()
	# 批处理镜像（重新造 player）
	var p_b = _mk_player_with_tower(0, "Arrow", 1)
	var b := _WaveSimAggro.simulate_wave_aggro(p_b, 1, cfg, geo, true)
	_check("W1 击杀 实时==批处理", float(rt["kills"]), float(b["kills"]))
	_check("W1 漏怪 实时==批处理", float(rt["leaked"]), float(b["leaked"]))
	_check("W1 scrap 实时==批处理", float(rt["scrap_earned"]), float(b["scrap_earned"]))
	_check("W1 塔死数 实时==批处理",
		float(rt.get("towers_disabled", 0)), float(b["towers_disabled"]))


# ---------------------------------------------------------------------------
#  snapshot 辅助
# ---------------------------------------------------------------------------
func _snap_has_state(snap: Dictionary, st: int) -> bool:
	for m in snap["monsters"]:
		if int(m["state"]) == st:
			return true
	return false


func _snap_monster_targeting(snap: Dictionary, slot: int) -> bool:
	for m in snap["monsters"]:
		if int(m["state"]) == _Monster.State.AGGRO_TOWER and int(m["target_slot"]) == slot:
			return true
	return false


func run_all() -> bool:
	_test_tower_hp_derivation()
	_test_aggro_constants()
	_test_golden_equiv_realtime()
	_test_golden_equiv_batch()
	_test_aggro_state_machine()
	_test_aggro_tower_destroyed()
	_test_safe_slot_immune()
	_test_aggro_effect_batch()
	_test_realtime_batch_consistency()
	_log("")
	_log("T1 仇恨 汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	return _fail == 0
