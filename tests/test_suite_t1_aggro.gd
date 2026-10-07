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
const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")

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
	# 🔒 T1 V-1：测"仇恨机制能力本身"（能否转 AggroTower / 能否打死塔）→ warmup_waves=0
	#   绕过起手保护（AC-T1-5/6/8/9 在 W1 测能力，非测激活时机）。定稿运行时默认 WARMUP=2。
	wd.warmup_waves = 0
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
	# ATTRITION 已 V-1 定稿 = 1.50（300 局 MC，首个全判据通过点）
	_check("ATTRITION 已定稿 = 1.50（V-1 扫参，300 局 MC）", _MonsterData.ATTRITION, 1.5)
	# WARMUP 起手保护定稿 = 2（与 ATTRITION 成对生效）
	_check("WARMUP 起手保护 = 2（与 ATTRITION 成对，仇恨 W3 起生效）", _MonsterData.WARMUP, 2.0)


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


## 造一个 runtime 并塞一座 Disabled 塔（绕开战斗，专测修复/被动拆除结算数学）
func _mk_rt_with_disabled_tower(slot: int, h: int, invested: float, scrap: float):
	var rt = _ShopRuntime.new()
	rt.setup("B", 20261002)
	rt.player.towers = []
	rt.player.cards = {}
	var t := _PS.make_tower(slot, "Cannon", h, {})
	t.invested = invested
	t.disabled = true
	t.hp = 0.0
	t.hp_max = _MonsterData.tower_hp(h)
	rt.player.towers.append(t)
	rt.scrap = scrap
	return rt


# ===========================================================================
#  AC-T1-10 · 修复入口（Q-T8：repair_cost = ceil(0.30 × 累计投入)）
# ===========================================================================
func _test_repair_entry() -> void:
	_log("")
	_log("--- [AC-T1-10] 修复入口：repair_cost 数学 + 回满 HP + 保留装配卡 ---")
	# ① cost 数学：invested=100 → ceil(0.30×100)=30
	var rt = _mk_rt_with_disabled_tower(0, 1, 100.0, 500.0)
	var prev := rt.preview_repair(0)
	_check_bool("preview 修复费用 ceil(0.30×100)=30", int(prev["cost"]), 30)
	_check_bool("preview ok（Disabled 塔可修）", bool(prev["ok"]), true)
	# ② 执行修复：扣分 30、HP 回满、disabled=false、装配卡保留
	var r := rt.repair_tower(0)
	_check_bool("修复 ok", bool(r["ok"]), true)
	_check("实际花费 = 30", float(r["cost"]), 30.0)
	_check("修复后 scrap 500→470", rt.scrap, 470.0)
	_check_bool("修复后塔恢复输出（disabled=false）", bool(rt.player.towers[0].disabled), false)
	_check("修复后 HP 回满 = hp_max", float(rt.player.towers[0].hp), float(rt.player.towers[0].hp_max))
	# ③ 非 Disabled 塔拒绝修复
	var rt2 = _mk_rt_with_disabled_tower(1, 1, 100.0, 500.0)
	rt2.player.towers[0].disabled = false
	var bad := rt2.repair_tower(1)
	_check_bool("未受损塔拒绝修复", bool(bad["ok"]), false)
	# ④ 积分不足 → 拒绝（E-T4 永不死锁前提）
	var rt3 = _mk_rt_with_disabled_tower(2, 1, 100.0, 10.0)
	var poor := rt3.repair_tower(2)
	_check_bool("积分不足拒绝修复（E-T4）", bool(poor["ok"]), false)


# ===========================================================================
#  AC-T1-11 · 被动拆除（Q-T4/Q-T8：返还 0%，区别主动 50%）
# ===========================================================================
func _test_salvage_disabled() -> void:
	_log("")
	_log("--- [AC-T1-11] 被动拆除：返还 0% + 释放塔位 + 销毁装配卡 ---")
	# 带一张装配卡的 Disabled 塔
	var rt = _mk_rt_with_disabled_tower(0, 1, 100.0, 500.0)
	rt.player.towers[0].attach["FireUp"] = 2
	rt.player.cards["FireUp"] = true
	var before_towers: int = rt.player.towers.size()
	var before_cards: int = rt.player.cards.size()
	var r := rt.salvage_disabled_tower(0)
	_check_bool("被动拆除 ok", bool(r["ok"]), true)
	_check_int("销毁 1 张装配卡", int(r["cards_destroyed"]), 1)
	_check_int("销毁 2 层", int(r["layers_destroyed"]), 2)
	# 🔴 返还 0% → scrap 不变（区别主动拆除的 +50%）
	_check("被动拆除返还 0% → scrap 仍 500", rt.scrap, 500.0)
	_check_int("塔位释放（塔数 -1）", rt.player.towers.size(), before_towers - 1)
	_check_int("装配卡从 player.cards 移除", rt.player.cards.size(), before_cards - 1)
	# 对比：主动拆除同 invested=100 返还 50
	var rt2 = _ShopRuntime.new()
	rt2.setup("B", 20261002)
	rt2.player.towers = []
	rt2.player.cards = {}
	var t2 := _PS.make_tower(0, "Cannon", 1, {})
	t2.invested = 100.0
	rt2.player.towers.append(t2)
	rt2.scrap = 500.0
	var prev_active := rt2.preview_salvage(0)
	_check("主动拆除返还 50% = 50（对比被动 0%）", float(prev_active["refund"]), 50.0)
	# 非 Disabled 塔拒绝被动拆除
	var rt3 = _mk_rt_with_disabled_tower(1, 1, 100.0, 500.0)
	rt3.player.towers[0].disabled = false
	var bad := rt3.salvage_disabled_tower(1)
	_check_bool("未受损塔拒绝被动拆除", bool(bad["ok"]), false)


# ===========================================================================
#  AC-T1-12 · 放着不管（no-op）+ E-T4 永不死锁
# ===========================================================================
func _test_disabled_noop_never_deadlock() -> void:
	_log("")
	_log("--- [AC-T1-12] 放着不管（no-op）+ E-T4 永不死锁 ---")
	# 放着不管 = 塔保持 Disabled、占位、不输出（本方法不实现，验证塔状态不变）
	var rt = _mk_rt_with_disabled_tower(0, 1, 100.0, 500.0)
	var scrap_before: float = rt.scrap
	var disabled_before := bool(rt.player.towers[0].disabled)
	# 玩家选择「放着不管」→ 不调任何方法 → 塔仍 Disabled、scrap 不变
	_check_bool("放着不管：塔仍 Disabled", bool(rt.player.towers[0].disabled), disabled_before)
	_check("放着不管：scrap 不变", rt.scrap, scrap_before)
	# E-T4 永不死锁：即使没钱修复，也能「放着不管」（不崩）或「0 返还拆除」释放塔位
	var rt2 = _mk_rt_with_disabled_tower(0, 1, 100.0, 0.0)   # 身无分文
	var poor_repair := rt2.repair_tower(0)
	_check_bool("E-T4：没钱修复 → 拒绝（不扣负分）", bool(poor_repair["ok"]), false)
	_check("E-T4：没钱修复 → scrap 仍 0（不欠分）", rt2.scrap, 0.0)
	# 没钱也能 0 返还拆除 → 释放塔位，永不死锁
	var before: int = rt2.player.towers.size()
	var salv := rt2.salvage_disabled_tower(0)
	_check_bool("E-T4：没钱可 0 返还拆除 → 释放塔位", bool(salv["ok"]), true)
	_check_int("E-T4：拆除后塔位数 -1（永不死锁）", rt2.player.towers.size(), before - 1)
	# list_disabled_towers 供 E-T2 合并弹窗
	var rt3 = _mk_rt_with_disabled_tower(3, 2, 200.0, 500.0)
	var lst := rt3.list_disabled_towers()
	_check_int("list_disabled_towers 列出 1 座", lst.size(), 1)
	_check("list 修复费 ceil(0.30×200)=60", float(lst[0]["repair_cost"]), 60.0)


# ===========================================================================
#  AC-T1-15 · 修复入口 UI 数据源（snapshot slots.disabled 红点计数）
#  ---------------------------------------------------------------------------
#  H10 后续 · UI 层接修复弹窗（方案B 重决策面板入口）的数据地基：
#  shop_runtime.snapshot() 的 `slots` 每座带 `disabled` 布尔，供 shop_overlay
#  统计受损塔数 → 「处置受损塔 (N)」按钮红点计数（SR-R2 只标事实）。
#  🔴 本单测守护 snapshot 的 disabled 字段正确反映塔的真实状态（金标本零改动：
#     snapshot 是玩家路线 UI 数据，AI 路线不读）。
# ===========================================================================
func _test_repair_ui_snapshot_datasource() -> void:
	_log("")
	_log("--- [AC-T1-15] 修复入口 UI 数据源：snapshot slots.disabled 红点计数 ---")
	# ① 单座 Disabled 塔 → 该 slot 的 disabled=true
	var rt = _mk_rt_with_disabled_tower(0, 1, 100.0, 500.0)
	var snap: Dictionary = rt.snapshot()
	_check_bool("snapshot 有 slots 字段", snap.has("slots"), true)
	var rows: Array = snap["slots"]
	_check_bool("slots 每座带 disabled 字段", rows[0].has("disabled"), true)
	_check_bool("受损塔 slot 0 的 disabled=true", bool(rows[0]["disabled"]), true)
	# ② 修复后 → disabled=false（红点应消失）
	rt.repair_tower(0)
	var snap2: Dictionary = rt.snapshot()
	var rows2: Array = snap2["slots"]
	_check_bool("修复后 slot 0 的 disabled=false", bool(rows2[0]["disabled"]), false)
	# ③ 多塔混合：一座受损 + 一座正常 → 计数 = 1（只标事实，不标推荐）
	var rt3 = _ShopRuntime.new()
	rt3.setup("B", 20261002)
	rt3.player.towers = []
	var td := _PS.make_tower(0, "Cannon", 1, {})   # 受损
	td.invested = 100.0; td.disabled = true; td.hp = 0.0
	td.hp_max = _MonsterData.tower_hp(1)
	var tn := _PS.make_tower(1, "Arrow", 2, {})    # 正常
	tn.invested = 50.0; tn.disabled = false
	rt3.player.towers.append(td)
	rt3.player.towers.append(tn)
	rt3.scrap = 500.0
	var snap3: Dictionary = rt3.snapshot()
	var rows3: Array = snap3["slots"]
	var n_disabled := 0
	for r in rows3:
		if bool(r["disabled"]):
			n_disabled += 1
	_check_int("多塔混合：snapshot 受损塔计数 = 1", n_disabled, 1)
	_check_bool("slot 0（受损）disabled=true", bool(rows3[0]["disabled"]), true)
	_check_bool("slot 1（正常）disabled=false", bool(rows3[1]["disabled"]), false)


# ===========================================================================
#  AC-T1-13 · V-1 定稿：ATTRITION=1.50 + 起手保护 WARMUP=2（实时↔批处理对称）
# ===========================================================================
func _test_v1_finalized_attrition_and_warmup() -> void:
	_log("")
	_log("--- [AC-T1-13] V-1 定稿：ATTRITION=1.50 + 起手保护 WARMUP=2 ---")
	# ① resolve_attrition 覆盖逻辑：默认读定稿常量；传覆盖值用覆盖值
	_check("resolve_attrition(-1) 读定稿 1.50", _MonsterData.resolve_attrition(-1.0), 1.5)
	_check("resolve_attrition(4.0) 用覆盖值 4.0", _MonsterData.resolve_attrition(4.0), 4.0)
	# ② 起手保护（批处理镜像 warmup=2）：W1 暴露位 S0 塔**不应**被打死（仇恨 W3 才生效）
	var geo = _Geo6.build()
	var cfg = _Cfg.cfg_of("B")
	var p1 = _mk_player_with_tower(0, "Arrow", 1)   # h=1 暴露位 S0
	var on_warmup := _WaveSimAggro.simulate_wave_aggro(p1, 1, cfg, geo, true, 0.6, -1.0, 2)
	_check("W1 起手保护：暴露位 S0 塔不死（towers_disabled=0）",
		float(on_warmup["towers_disabled"]), 0.0)
	_check("W1 起手保护：本波毛新增 Disabled=0", float(on_warmup["dis_new"]), 0.0)
	# ③ 起手保护关闭（warmup=0）时 W1 暴露位塔**会**被打死（机制能力在，只是被保护期挡住）
	var p2 = _mk_player_with_tower(0, "Arrow", 1)
	var on_nowarmup := _WaveSimAggro.simulate_wave_aggro(p2, 1, cfg, geo, true, 0.6, -1.0, 0)
	_check_bool("warmup=0 时 W1 暴露位 S0 塔会被打死（机制能力在）",
		int(on_nowarmup["towers_disabled"]) > 0, true)
	# ④ 实时版门控：warmup_waves 成员**默认** = WARMUP=2（直接 new，不经 _mk_director
	#    否则会被设成 0）
	var wd_default := _WaveDirector.new()
	_check("实时版 warmup_waves 默认 = WARMUP=2", float(wd_default.warmup_waves), 2.0)


# ===========================================================================
#  AC-T1-14 · V-2 诊断留档：protect_core 主力塔保护干预（金标本零改动）
#  ---------------------------------------------------------------------------
#  V-2 定稿（2026-10-04，方案④）的根因诊断干预：protect_core=true 时怪物跳过
#  h 最高的主力塔、专打副塔。本单测守护两件事：
#    ① 干预生效：单塔场景 protect_core=true → 唯一塔（=主力塔）被跳过 → 不死；
#       protect_core=false → 暴露塔被打死。
#    ② 金标本零改动：protect_core 默认 false → 行为与不传完全一致（等价守护）。
#  🔴 这是诊断工具的存在性 + 零改动守护，不断言"起飞率"（那走 scan_protect_core.gd）。
# ===========================================================================
func _test_v2_diagnose_protect_core() -> void:
	_log("")
	_log("--- [AC-T1-14] V-2 诊断：protect_core 主力塔保护干预（金标本零改动）---")
	var geo = _Geo6.build()
	var cfg = _Cfg.cfg_of("B")
	# ① 默认 false == 不传（等价守护）：暴露位 S0 单塔，warmup=0，aggro=true → 塔死
	var p0 = _mk_player_with_tower(0, "Arrow", 1)   # h=1 暴露位 S0
	var off := _WaveSimAggro.simulate_wave_aggro(p0, 1, cfg, geo, true, 0.6, -1.0, 0, false)
	_check("protect_core=false（默认）：暴露位 S0 塔被打死（towers_disabled=1）",
		float(off["towers_disabled"]), 1.0)
	# ② protect_core=true：唯一塔 = 主力塔被跳过 → 无目标 → 塔不死
	var p1 = _mk_player_with_tower(0, "Arrow", 1)
	var on := _WaveSimAggro.simulate_wave_aggro(p1, 1, cfg, geo, true, 0.6, -1.0, 0, true)
	_check("protect_core=true：主力塔被跳过 → 无目标 → S0 塔不死（towers_disabled=0）",
		float(on["towers_disabled"]), 0.0)
	_check_bool("protect_core=true：S0 塔未进入 Disabled",
		bool(p1.towers[0].disabled), false)
	# ③ 金标本零改动：默认参数（不传 protect_core）与显式 false 逐位一致
	var p2 = _mk_player_with_tower(0, "Arrow", 1)
	var default := _WaveSimAggro.simulate_wave_aggro(p2, 1, cfg, geo, true)
	_check("金标本零改动：默认参数 == 显式 protect_core=false（towers_disabled 一致）",
		float(default["towers_disabled"]), float(off["towers_disabled"]))


# ===========================================================================
#  AC-T1-16 · 肉盾塔诊断（bulwark）：主力塔重定位到安全位（金标本零改动）
#  ---------------------------------------------------------------------------
#  V-2 后续 · 肉盾塔玩法② 定稿（2026-10-07，涌现策略 + ①理想肉盾建模）的诊断干预：
#  bulwark=true 时把 h 最高的**未 Disabled** 主力塔移到安全位（d_path > AGGRO_R），
#  原安全位的塔换到主力塔旧暴露位充当肉盾。本单测守护两件事：
#    ① 重定位生效：主力塔从暴露位 S0 移到安全位（S4/S5）；
#    ② 金标本零改动：bulwark 默认 false → 塔位与不传完全一致（等价守护）。
#  🔴 这是诊断工具的存在性 + 零改动守护，不断言"起飞率"（那走 scan_bulwark.gd）。
# ===========================================================================
func _test_bulwark_relocate() -> void:
	_log("")
	_log("--- [AC-T1-16] 肉盾塔诊断：bulwark 主力塔重定位到安全位（金标本零改动）---")
	var geo = _Geo6.build()
	var cfg = _Cfg.cfg_of("A")
	# 双塔：主力塔 h=50（超高 HP 打不死，确保重定位干净执行）在暴露位 S0，副塔 h=1 在安全位 S4
	var mk := func() -> Variant:
		var p = _SimPlayer.new_player("A", cfg, geo)
		p.towers = []
		var tc = _PS.make_tower(0, "Cannon", 50, {})  # 主力塔（h 最高，暴露位 S0；h=50 → HP≈1122 打不死）
		tc.invested = 100.0
		var tn = _PS.make_tower(4, "Arrow", 1, {})    # 副塔（安全位 S4）
		tn.invested = 20.0
		p.towers.append(tc)
		p.towers.append(tn)
		return p
	# ① bulwark=true：主力塔应移到安全位（S4 或 S5），S4 原副塔换到 S0（肉盾）
	var pb = mk.call()
	_WaveSimAggro.simulate_wave_aggro(pb, 3, cfg, geo, true, 0.6, -1.0, 0, false, true)
	var carry_slot := -1
	var carry_h := -1
	for t in pb.towers:
		if int(t.h) > carry_h:
			carry_h = int(t.h)
			carry_slot = int(t.slot)
	_check("bulwark：主力塔（h 最高）已移到安全位（S4/S5）",
		(carry_slot == 4 or carry_slot == 5), true)
	# ② 金标本零改动：bulwark=false（默认）→ 主力塔仍在暴露位 S0
	var pn = mk.call()
	_WaveSimAggro.simulate_wave_aggro(pn, 3, cfg, geo, true, 0.6, -1.0, 0, false, false)
	var carry_slot_n := -1
	var carry_h_n := -1
	for t in pn.towers:
		if int(t.h) > carry_h_n:
			carry_h_n = int(t.h)
			carry_slot_n = int(t.slot)
	_check("金标本零改动：bulwark=false 主力塔仍在暴露位 S0", carry_slot_n, 0)
	# ③ 金标本零改动：默认参数（不传 bulwark）== 显式 false（塔位一致）
	var pd = mk.call()
	_WaveSimAggro.simulate_wave_aggro(pd, 3, cfg, geo, true)
	var carry_slot_d := -1
	var carry_h_d := -1
	for t in pd.towers:
		if int(t.h) > carry_h_d:
			carry_h_d = int(t.h)
			carry_slot_d = int(t.slot)
	_check("金标本零改动：默认参数 == 显式 bulwark=false（主力塔位一致）",
		carry_slot_d, carry_slot_n)


# ===========================================================================
#  AC-T1-17 · ⑤ Sapper 精英（实时版）：Elite 波锁塔 ×3、无视距离、金标本零改动
#  ---------------------------------------------------------------------------
#  Sapper = Elite 波（每5波）里沿波次均匀铺开的精英怪：无视 AGGRO_R 距离门槛
#  直奔最近的塔并锁定攻击、对塔伤害 ×3。由 elite_waves_enabled 诊断开关控制，
#  MVP 恒 false（金标本零改动）。
# ===========================================================================
func _mk_director_sapper(player, aggro: bool, elite_on: bool):
	var cfg = _Cfg.cfg_of("B")
	var geo = _Geo6.build()
	var wd = _WaveDirector.new()
	wd.tower_aggro_enabled = aggro
	wd.elite_waves_enabled = elite_on
	wd.warmup_waves = 0    # 绕过起手保护，测能力本身
	wd.setup(player, cfg, geo)
	return wd


func _snap_monster_is_sapper(snap: Dictionary, slot: int) -> bool:
	for m in snap["monsters"]:
		if bool(m.get("sapper", false)) and int(m["target_slot"]) == slot:
			return true
	return false


func _snap_any_sapper(snap: Dictionary) -> bool:
	for m in snap["monsters"]:
		if bool(m.get("sapper", false)):
			return true
	return false


## 推进 wave 若干子步直到出现 sapper 怪（或跑完），返回是否出现过。
## 🔴 必须真正推进时间让怪出生（snapshot 在 t=0 时 monsters=[] 测不到）。
func _advance_until_sapper(wd, max_steps: int = 400) -> bool:
	for _i in range(max_steps):
		wd.advance(_WaveSim.DT)
		if _snap_any_sapper(wd.snapshot()):
			return true
	return false


func _test_sapper_realtime() -> void:
	_log("")
	_log("--- [AC-T1-17] ⑤ Sapper 精英（实时版）：Elite 波锁塔×3、无视距离、金标本零改动 ---")
	# ① 金标本零改动：elite_waves_enabled=false → W5 全程无任何 sapper 怪（推进整波验证）
	var p0 = _mk_player_with_tower(0, "Arrow", 1)
	var wd0 = _mk_director_sapper(p0, true, false)
	wd0.start_wave(5)
	wd0.run_to_end()
	_check_bool("金标本零改动：elite_waves_enabled=false → W5 全程无 sapper 怪",
		_snap_any_sapper(wd0.snapshot()), false)
	# ② 默认参数（不传 elite_waves_enabled）== 无 sapper（金标本零改动）
	var p0b = _mk_player_with_tower(0, "Arrow", 1)
	var wd0b = _mk_director(p0b, true)   # 未开 elite_waves_enabled
	wd0b.start_wave(5)
	wd0b.run_to_end()
	_check_bool("金标本零改动：默认 elite_waves_enabled=false → W5 全程无 sapper 怪",
		_snap_any_sapper(wd0b.snapshot()), false)
	# ③ Sapper 出生：elite_waves_enabled=true → W5（Elite 波）推进后至少出现一只 sapper 怪。
	#    无塔 → 怪不被塔击杀、sapper 标志可被观测（march 到核心漏掉）。
	var p1 = _mk_player_with_tower(0, "Arrow", 1)
	var wd1 = _mk_director_sapper(p1, true, true)
	wd1.start_wave(5)
	# 无塔配置：移除塔，让 sapper 怪存活以便观测（塔会击杀 sapper）
	wd1.player.towers = []
	_check_bool("Elite 波 W5：推进后至少出现一只 sapper 怪",
		_advance_until_sapper(wd1), true)
	# ④ Sapper 无视距离锁塔：唯一塔放在**安全位 S4**（d_path > AGGRO_R=9.0，普通怪够不到），
	#    sapper 怪仍应锁定它（直奔最近的塔，无视距离门槛）。塔用 h=100 高血扛住，避免被打死
	#    导致目标失效切换。
	var p2 = _mk_player_with_tower(4, "Arrow", 100)
	var wd2 = _mk_director_sapper(p2, true, true)
	wd2.start_wave(5)
	var found_lock := false
	for _i in range(400):
		wd2.advance(_WaveSim.DT)
		if _snap_monster_is_sapper(wd2.snapshot(), 4):
			found_lock = true
			break
	_check_bool("Sapper 无视距离：安全位 S4 的塔被 sapper 锁定（普通怪够不到）",
		found_lock, true)
	# ⑤ ×3 增伤效果：单座暴露位 h=1 塔，有 sapper 时塔死更快（towers_disabled 更多）。
	#    对照：同 W5 无 sapper（elite off）vs 有 sapper。
	var p3 = _mk_player_with_tower(0, "Arrow", 1)
	var wd3 = _mk_director_sapper(p3, true, true)
	wd3.start_wave(5)
	wd3.run_to_end()
	var td_sapper := int(wd3.last_result.get("towers_disabled", 0))
	var p4 = _mk_player_with_tower(0, "Arrow", 1)
	var wd4 = _mk_director_sapper(p4, true, false)
	wd4.start_wave(5)
	wd4.run_to_end()
	var td_plain := int(wd4.last_result.get("towers_disabled", 0))
	_check_bool("×3 增伤：有 sapper 时暴露位塔死数 ≥ 无 sapper（×3 加速打死）",
		td_sapper >= td_plain, true)
	# ⑥ 🔴 金标本逐位等价（最强守护）：Elite 波 W5 sapper=true 的**实时版 towers_disabled
	#    == 批处理镜像**。实时版与批处理镜像走同一 elite_indices 算法标记 sapper → 塔死数逐位相同。
	var p5 = _mk_player_with_tower(0, "Arrow", 1)
	var wd5 = _mk_director_sapper(p5, true, true)
	wd5.warmup_waves = 2    # 用定稿起手保护（W5 > WARMUP=2 仇恨生效），贴近真实运行
	wd5.start_wave(5)
	wd5.run_to_end()
	var td_rt := int(wd5.last_result.get("towers_disabled", 0))
	var p6 = _mk_player_with_tower(0, "Arrow", 1)
	var b5 := _WaveSimAggro.simulate_wave_aggro(p6, 5, _Cfg.cfg_of("B"), _Geo6.build(),
		true, 0.6, -1.0, 2, false, false, true)
	_check("金标本逐位等价：Elite 波 W5 sapper=true 塔死数 实时==批处理",
		float(td_rt), float(b5["towers_disabled"]))


# ===========================================================================
#  AC-T1-18 · ⑤ Sapper 精英（批处理镜像）：逐位对齐 + 金标本零改动
#  ---------------------------------------------------------------------------
#  镜像实时版：simulate_wave_aggro 的 sapper 参数贯穿，仅 Elite 波生效。
#  默认 false 退化为金标本口径（无 sapper、塔死不因 ×3 放大）。
# ===========================================================================
func _test_sapper_batch() -> void:
	_log("")
	_log("--- [AC-T1-18] ⑤ Sapper 精英（批处理镜像）：Elite 波锁塔×3 + 金标本零改动 ---")
	var geo = _Geo6.build()
	var cfg = _Cfg.cfg_of("B")
	# ① 金标本零改动：默认参数（不传 sapper）→ W5 塔死与显式 sapper=false 一致
	var pn1 = _mk_player_with_tower(0, "Arrow", 1)
	var bn_default := _WaveSimAggro.simulate_wave_aggro(pn1, 5, cfg, geo, true)
	var pn2 = _mk_player_with_tower(0, "Arrow", 1)
	var bn_false := _WaveSimAggro.simulate_wave_aggro(pn2, 5, cfg, geo, true, 0.6, -1.0, 0, false, false, false)
	_check("金标本零改动：默认 == sapper=false（W5 塔死数一致）",
		float(bn_default["towers_disabled"]), float(bn_false["towers_disabled"]))
	# ② 非 Elite 波（W4）：sapper=true 也不产生 sapper 怪 → 塔死与 false 一致
	var pn3 = _mk_player_with_tower(0, "Arrow", 1)
	var bn_w4 := _WaveSimAggro.simulate_wave_aggro(pn3, 4, cfg, geo, true, 0.6, -1.0, 0, false, false, true)
	var pn4 = _mk_player_with_tower(0, "Arrow", 1)
	var bn_w4_false := _WaveSimAggro.simulate_wave_aggro(pn4, 4, cfg, geo, true, 0.6, -1.0, 0, false, false, false)
	_check("金标本零改动：非 Elite 波 W4 sapper=true 不生效（塔死数 == false）",
		float(bn_w4["towers_disabled"]), float(bn_w4_false["towers_disabled"]))
	# ③ Elite 波 W5 · Sapper 无视距离：塔放**安全位 S4**（普通怪够不到），
	#    sapper=false → 塔不死（0）；sapper=true → sapper 锁安全位塔 ×3 打死（≥1）。
	var ps1 = _mk_player_with_tower(4, "Arrow", 1)
	var bs_false := _WaveSimAggro.simulate_wave_aggro(ps1, 5, cfg, geo, true, 0.6, -1.0, 0, false, false, false)
	var ps2 = _mk_player_with_tower(4, "Arrow", 1)
	var bs_true := _WaveSimAggro.simulate_wave_aggro(ps2, 5, cfg, geo, true, 0.6, -1.0, 0, false, false, true)
	_check("Elite 波 W5 安全位 S4：sapper=false 塔不死（普通怪够不到）",
		float(bs_false["towers_disabled"]), 0.0)
	_check_bool("Elite 波 W5 安全位 S4：sapper=true 锁塔打死（无视距离 ×3）",
		int(bs_true["towers_disabled"]) > 0, true)


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
	_test_repair_entry()
	_test_salvage_disabled()
	_test_disabled_noop_never_deadlock()
	_test_repair_ui_snapshot_datasource()
	_test_v1_finalized_attrition_and_warmup()
	_test_v2_diagnose_protect_core()
	_test_bulwark_relocate()
	_test_sapper_realtime()
	_test_sapper_batch()
	_log("")
	_log("T1 仇恨 汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	return _fail == 0
