extends RefCounted
##
## 🔒 第五刀 · 三轴合并镜像「退化逐位守护」+ 交叉一致性（`tower-aggro-golive-spec.md` §3.2 / A-3）
##
## 🔴 守护对象 = 新建三轴合并镜像 `run_loop_proto_aggro` / `wave_sim_proto_aggro`。
##   核心不变量：任一轴 OFF → 合并镜像退化为既有单轴口径；上线口径 → 忠实真身。**逐位一致**：
##     ① `aggro_enabled=false`             → 与 `run_loop_proto`（原型/精英）逐位一致
##     ② `proto/elite=false`（aggro=true） → 与**真身**（headless 驱动 WaveDirector）逐位一致
##     ③ 三轴全 OFF                         → 与金标本 `run_loop` 逐位一致
##     ④ 全开（proto+elite+aggro）          → 与**真身**逐位一致（上线门禁可信度地基）
##   另加交叉断言：Sapper（elite 驱动）轴、aggro 确有杀伤。
##   另登记（INFO·**不判等**）：旧镜像 `wave_sim_aggro` ② 为 no-op（既有缺陷）→ 与真身已知偏差。
##
## 🔴 守护②/④「对标真身」方法（主理人 2026-10-10 裁定 · 取代原「② == run_loop_aggro」）：
##   用**小场景逐波**比对 —— 以同一确定性初值造**同一 player**，一次喂 `WaveDirector`（真身，
##   headless `run_to_end`），一次喂合并镜像 `simulate_wave_proto_aggro`；逐位比 kills/leaked/
##   scrap_earned/dps/towers_disabled。
##   🔴 不跑整局 `run_loop`：真身「核心归零即中断本波」（run_failed → `_end_wave`）与批处理
##      「跑满本波」在**破局波**存在**run_loop 层**固有口径差 —— 那是记账层差异，非本刀战斗口径
##      差异 → 逐波隔离比对恰好避开它，直测战斗口径。
##
## 🔴 该套件**不进**默认无参回归（默认仍只跑 slice1~8 + t1aggro，九段聚合读数逐位不变）。
##   单列为 `-- aggro_golive` 入口，并纳入 CI。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- aggro_golive
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _RunLoop := preload("res://scripts/engine/run_loop.gd")
const _RunLoopProto := preload("res://scripts/engine/run_loop_proto.gd")
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _RunLoopPA := preload("res://scripts/engine/run_loop_proto_aggro.gd")
const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")
const _WaveSimPA := preload("res://scripts/engine/wave_sim_proto_aggro.gd")
const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Geo8 := preload("res://scripts/geo/geo8.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")

const W_MAX := 20
const RUNS := 40
const SEED := 20260930
const WARMUP := 2
const ATTRITION := 1.5
const EXP := 0.6
## 🔴 小场景把核心 HP 抬高：真身 `_substep` 在**核心归零时 `run_failed` → 中断本波**
##   （`_check_end`），而批处理/合并镜像**不跟踪核心**（只回 `core_damage`）→ 破局波会
##   出现"真身 leaked=20（=core/leak）vs 合并跑满"的 **run_loop 层**固有口径差。
##   抬高核心 → 两口径都跑满本波 → 直测**战斗口径**（kills/leaked/scrap/dps/towers_disabled）。
##   🔴 零战斗影响：`core_hp` 不参与 `dps_only` / 任何乘区（只用于漏怪扣血与 run_failed）。
const BIG_CORE := 1.0e9
## run-loop 行逐位比较字段（两口径的 row 共有字段；kills/leaked/scrap(income)/dps/core_hp 为主）。
const CMP := ["kills", "leaked", "core_hp_raw", "eff_dps_raw", "ratio_raw",
	"total_hp_raw", "income_raw", "hp_each_raw", "n"]
## 真身 `last_result` ↔ 合并/旧镜像返回 dict 的共有字段（逐波逐位比较）。
const RT_KEYS := ["kills", "leaked", "scrap_earned", "dps", "towers_disabled"]
## 逐波比对场景：(mode, geo_tag, path, wave) 组合由函数内枚举。
##   小场景 = 起手单塔（slot0 · h=1 · Arrow，`SimPlayer.new_player`）——
##   与 AC-T1-9 同款：PATH/六槽下怪必从 S0 近旁经过（垂距 8 < AGGRO_R=9）→ 仇恨必激活。

var _pass := 0
var _fail := 0
var _aggro_fired := false     # 场景是否真的触发过 aggro 杀伤（守护有效性自检）


func _log(s: String) -> void:
	print(s)


# ---------------------------------------------------------------------------
#  run-loop 行集逐位比较（守护①③ / 登记 INFO 用）
# ---------------------------------------------------------------------------
func _cmp_runsets(name: String, runs_a: Array, runs_b: Array) -> void:
	var diff := 0
	var first := ""
	if runs_a.size() != runs_b.size():
		diff += 1
		first = "run-count %d vs %d" % [runs_a.size(), runs_b.size()]
	for ri in range(mini(runs_a.size(), runs_b.size())):
		var ra: Array = runs_a[ri]
		var rb: Array = runs_b[ri]
		if ra.size() != rb.size():
			diff += 1
			if first == "":
				first = "run%d row-count %d vs %d" % [ri, ra.size(), rb.size()]
		for i in range(mini(ra.size(), rb.size())):
			for k in CMP:
				if float(ra[i].get(k, 0.0)) != float(rb[i].get(k, 0.0)):
					diff += 1
					if first == "":
						first = "run%d w%d %s %s vs %s" % [ri, int(ra[i]["w"]), k,
							str(ra[i].get(k)), str(rb[i].get(k))]
	if diff == 0:
		_pass += 1
		_log("   [PASS] %s（%d 局 × ≤%d 波 · 逐位 |d|=0）" % [name, runs_a.size(), W_MAX])
	else:
		_fail += 1
		_log("   [FAIL] %s  差异格=%d  首个=%s" % [name, diff, first])


## 只数差异格数（登记 INFO 用，不判等）。
func _count_runset_diffs(runs_a: Array, runs_b: Array) -> int:
	var diff := 0
	for ri in range(mini(runs_a.size(), runs_b.size())):
		var ra: Array = runs_a[ri]
		var rb: Array = runs_b[ri]
		for i in range(mini(ra.size(), rb.size())):
			for k in CMP:
				if float(ra[i].get(k, 0.0)) != float(rb[i].get(k, 0.0)):
					diff += 1
	return diff


## 跑 runs 局，返回每局的 rows（rng 跨局连续消费，双口径各用同 seed 的独立 rng）。
##   runner: 0=RunLoop(金标本) 1=RunLoopProto 2=RunLoopAggro(旧·②no-op) 3=RunLoopProtoAggro(合并)
func _collect(runner: int, path: String, runs: int,
		proto: bool, elite: bool, aggro: bool, sapper: bool, warmup: int) -> Array:
	var cfg := _Cfg.cfg_of(path)
	var rng := _PyRandom.new(SEED)
	var out: Array = []
	for _i in range(runs):
		var c: Dictionary = cfg.duplicate(true)
		c["max_actions"] = 12
		var o: Dictionary
		match runner:
			0:
				o = _RunLoop.run(path, c, W_MAX, null, rng)
			1:
				o = _RunLoopProto.run(path, c, W_MAX, null, rng, proto, elite)
			2:
				o = _RunLoopAggro.run(path, c, W_MAX, null, rng, aggro, EXP, ATTRITION, warmup,
					false, false, sapper)
			3:
				o = _RunLoopPA.run(path, c, W_MAX, null, rng, proto, elite, aggro, EXP,
					ATTRITION, warmup, false, false)
		out.append(o["rows"])
	return out


func _sum_dis_new(runs: Array) -> int:
	var s := 0
	for rows in runs:
		for r in rows:
			s += int(r.get("dis_new", 0))
	return s


# ---------------------------------------------------------------------------
#  真身/合并/旧镜像 · 单波（同一确定性 player 初值，逐波隔离）
# ---------------------------------------------------------------------------
func _geo_of(tag: String):
	return _Geo8.build8() if tag == "8" else _Geo6.build()


## 真身单波：headless 驱动真实 `WaveDirector`（run_to_end 逐子步，无跳步）。
func _rt_wave(path: String, geo, w: int, proto: bool, elite: bool, aggro: bool) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["core_hp"] = BIG_CORE
	var p = _SimPlayer.new_player(path, cfg, geo)
	var wd = _WaveDirector.new()
	wd.prototype_split_enabled = proto
	wd.elite_waves_enabled = elite
	wd.tower_aggro_enabled = aggro
	wd.warmup_waves = WARMUP
	wd.setup(p, cfg, geo)
	wd.start_wave(w)
	return wd.run_to_end()


## 合并镜像单波（同一 player 初值 → 与真身逐位可对）。
func _mg_wave(path: String, geo, w: int, proto: bool, elite: bool, aggro: bool) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["core_hp"] = BIG_CORE
	var p = _SimPlayer.new_player(path, cfg, geo)
	return _WaveSimPA.simulate_wave_proto_aggro(p, w, cfg, geo, proto, elite, aggro,
		EXP, ATTRITION, WARMUP, false, false)


## 旧 aggro 镜像单波（② no-op 既有缺陷；**仅登记 INFO 用**，不判等）。
func _old_aggro_wave(path: String, geo, w: int, sapper: bool) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["core_hp"] = BIG_CORE
	var p = _SimPlayer.new_player(path, cfg, geo)
	return _WaveSimAggro.simulate_wave_aggro(p, w, cfg, geo, true, EXP, ATTRITION, WARMUP,
		false, false, sapper)


func _count_wave_diffs(a: Dictionary, b: Dictionary) -> int:
	var d := 0
	for k in RT_KEYS:
		if float(a.get(k, 0.0)) != float(b.get(k, 0.0)):
			d += 1
	return d


## 逐波逐位比对：真身 `rt` == 合并 `mg`（RT_KEYS 全等）。
func _cmp_rt_wave(name: String, rt: Dictionary, mg: Dictionary) -> void:
	var diff := 0
	var first := ""
	for k in RT_KEYS:
		if float(rt.get(k, 0.0)) != float(mg.get(k, 0.0)):
			diff += 1
			if first == "":
				first = "%s 真身=%s 合并=%s" % [k, str(rt.get(k)), str(mg.get(k))]
	if diff == 0:
		_pass += 1
		_log("   [PASS] %s（真身 == 合并镜像 · 逐位 |d|=0）" % name)
	else:
		_fail += 1
		_log("   [FAIL] %s  差异键=%d  首个=%s" % [name, diff, first])


## 逐波场景枚举执行器：配置 (proto,elite,aggro) 固定，遍历 mode×geo×path×wave，逐位对真身。
func _run_wave_matrix(tag: String, proto: bool, elite: bool, aggro: bool) -> void:
	var prev: int = _SpaceModel.mode
	for scen in [["PATH", "6"], ["RADIAL", "6"], ["RADIAL", "8"]]:
		var mode := String(scen[0])
		var geo_tag := String(scen[1])
		_SpaceModel.mode = _SpaceModel.Mode.RADIAL if mode == "RADIAL" else _SpaceModel.Mode.PATH
		for path in ["A", "B"]:
			for w in [3, 5, 8]:
				var geo = _geo_of(geo_tag)
				var rt := _rt_wave(path, geo, w, proto, elite, aggro)
				var mg := _mg_wave(path, geo, w, proto, elite, aggro)
				_cmp_rt_wave("%s %s/%s geo%s W%d" % [tag, mode, path, geo_tag, w], rt, mg)
				if int(rt.get("towers_disabled", 0)) > 0:
					_aggro_fired = true
	_SpaceModel.mode = prev


# ---------------------------------------------------------------------------
#  守护① · aggro=false → 合并镜像 == run_loop_proto（逐位）
# ---------------------------------------------------------------------------
func _guard1_aggro_off() -> void:
	_log("")
	_log("--- [守护①] aggro_enabled=false → 合并镜像 == run_loop_proto（逐位）---")
	for path in ["A", "B"]:
		var a := _collect(3, path, RUNS, true, true, false, false, WARMUP)
		var b := _collect(1, path, RUNS, true, true, false, false, WARMUP)
		_cmp_runsets("守护① %s（proto/elite ON · aggro OFF）" % path, a, b)
		# 反向自检：aggro OFF → 合并镜像全程无塔受损（dis_new 恒 0）
		if _sum_dis_new(a) == 0:
			_pass += 1
			_log("   [PASS] 守护① %s：aggro OFF → 合并镜像 dis_new 合计=0（无塔受损）" % path)
		else:
			_fail += 1
			_log("   [FAIL] 守护① %s：aggro OFF 却出现塔受损 dis_new=%d" % [path, _sum_dis_new(a)])


# ---------------------------------------------------------------------------
#  守护② · proto/elite=false（aggro=true）→ 合并镜像 == 真身（逐波逐位）
#   （主理人 2026-10-10 裁定：取代原「== run_loop_aggro」—— 旧镜像② no-op 与真身不符）
# ---------------------------------------------------------------------------
func _guard2_proto_off() -> void:
	_log("")
	_log("--- [守护②] proto/elite=false（aggro=true）→ 合并镜像 == 真身（逐波逐位）---")
	_run_wave_matrix("守护②", false, false, true)


# ---------------------------------------------------------------------------
#  守护③ · 三轴全 OFF → 合并镜像 == 金标本 run_loop（逐位）
# ---------------------------------------------------------------------------
func _guard3_all_off() -> void:
	_log("")
	_log("--- [守护③] 三轴全 OFF → 合并镜像 == 金标本 run_loop（逐位）---")
	for path in ["A", "B"]:
		var a := _collect(3, path, RUNS, false, false, false, false, WARMUP)
		var b := _collect(0, path, RUNS, false, false, false, false, WARMUP)
		_cmp_runsets("守护③ %s（proto/elite/aggro 全 OFF）" % path, a, b)


# ---------------------------------------------------------------------------
#  守护④ · 全开（proto+elite+aggro）→ 合并镜像 == 真身（逐波逐位）· 最强守护
# ---------------------------------------------------------------------------
func _guard4_all_on() -> void:
	_log("")
	_log("--- [守护④] 全开（proto+elite+aggro）→ 合并镜像 == 真身（逐波逐位 · 上线口径地基）---")
	_run_wave_matrix("守护④", true, true, true)


# ---------------------------------------------------------------------------
#  守护⑤（B 轮 · 2026-10-10 新增）· repair 接线零扰动：repair_on_disable=0 → 合并镜像跑序逐位不变
#   背景：B-3 给合并镜像补了 V-7 修复接线（FREE 挂 run-loop / PRICED 走 shop_ai）。
#   钉死：`repair_on_disable=0` 时新接线**零扰动** —— 不注入 diag 容器、不挂 FREE 清塔 →
#         全开跑序与「无接线」逐位一致；且传入的 diag 容器全程零写入（注入守卫生效）。
# ---------------------------------------------------------------------------
## 合并镜像跑 `runs` 局（全开），可指定 repair 档位 + 传入 diag 容器（rng 跨局连续消费）。
func _collect_pa_repair(path: String, runs: int, repair_mode: int, diag: Array) -> Array:
	var cfg := _Cfg.cfg_of(path)
	cfg["repair_on_disable"] = repair_mode
	var rng := _PyRandom.new(SEED)
	var out: Array = []
	for _i in range(runs):
		var c: Dictionary = cfg.duplicate(true)
		c["max_actions"] = 12
		var o := _RunLoopPA.run(path, c, W_MAX, null, rng, true, true, true, EXP,
			ATTRITION, WARMUP, false, false, diag)
		out.append(o["rows"])
	return out


func _guard5_repair_zero_perturb() -> void:
	_log("")
	_log("--- [守护⑤] repair_on_disable=0 → 合并镜像跑序零扰动（不注入 diag / 不清塔 · B 轮）---")
	for path in ["A", "B"]:
		# 参考 = 原跑法（不传 diag 容器）；对照 = 传 diag 容器但 repair=0。
		var ref := _collect(3, path, RUNS, true, true, true, false, WARMUP)
		var diag: Array = [0, 0, 0, 0.0, 0, 0]
		var with_diag := _collect_pa_repair(path, RUNS, 0, diag)
		_cmp_runsets("守护⑤ %s（全开 · repair=0 · 传 diag 容器 vs 不传）" % path, with_diag, ref)
		# 注入守卫：repair=0 → diag 容器**全程零写入**（未注入 → 任何计数器不动）。
		var all_zero := true
		for v in diag:
			if float(v) != 0.0:
				all_zero = false
		if all_zero:
			_pass += 1
			_log("   [PASS] 守护⑤ %s：repair=0 → diag 容器全程零写入（注入守卫生效 · 0 档零扰动）" % path)
		else:
			_fail += 1
			_log("   [FAIL] 守护⑤ %s：repair=0 却写入了 diag=%s（0 档被污染）" % [path, str(diag)])



# ---------------------------------------------------------------------------
#  交叉一致性 · Sapper（elite 驱动）轴：合并(proto OFF · elite ON · aggro ON) == 真身
#              （elite 波 W5/W10 → 真身在 _spawn_one 标记 sapper）
# ---------------------------------------------------------------------------
func _cross_sapper() -> void:
	_log("")
	_log("--- [交叉] Sapper 轴：合并(proto OFF · elite ON · aggro ON) == 真身（elite 波 W5/W10）---")
	var prev: int = _SpaceModel.mode
	for scen in [["PATH", "6"], ["RADIAL", "8"]]:
		var mode := String(scen[0])
		var geo_tag := String(scen[1])
		_SpaceModel.mode = _SpaceModel.Mode.RADIAL if mode == "RADIAL" else _SpaceModel.Mode.PATH
		for path in ["A", "B"]:
			for w in [5, 10]:
				var geo = _geo_of(geo_tag)
				var rt := _rt_wave(path, geo, w, false, true, true)
				var mg := _mg_wave(path, geo, w, false, true, true)
				_cmp_rt_wave("交叉 Sapper %s/%s geo%s W%d" % [mode, path, geo_tag, w], rt, mg)
	_SpaceModel.mode = prev


# ---------------------------------------------------------------------------
#  交叉一致性 · aggro 确实生效：全开口径下 B 路径确有塔受损（dis_new > 0）
# ---------------------------------------------------------------------------
func _cross_aggro_active() -> void:
	_log("")
	_log("--- [交叉] aggro 生效自检：全开口径下 B 路径确有塔受损（dis_new > 0）---")
	var runs := _collect(3, "B", RUNS, true, true, true, false, WARMUP)
	var s := _sum_dis_new(runs)
	if s > 0:
		_pass += 1
		_log("   [PASS] 全开 B：%d 局内塔受损 gross 次数 dis_new 合计=%d（仇恨/塔损耗确在用）" % [RUNS, s])
	else:
		_fail += 1
		_log("   [FAIL] 全开 B：%d 局内 dis_new 合计=0（仇恨未生效？）" % RUNS)


# ---------------------------------------------------------------------------
#  守护有效性自检：逐波场景真的触发过 aggro 杀伤（否则守护②④是空转）
# ---------------------------------------------------------------------------
func _check_aggro_exercised() -> void:
	_log("")
	_log("--- [自检] 逐波场景确曾触发 aggro 杀伤（塔被打停 towers_disabled > 0）---")
	if _aggro_fired:
		_pass += 1
		_log("   [PASS] 守护②/④场景中真身/合并确出现过 towers_disabled > 0（非空转）")
	else:
		_fail += 1
		_log("   [FAIL] 守护②/④场景全程无塔被打停 → 守护是空转（场景未覆盖仇恨路径）")


# ---------------------------------------------------------------------------
#  登记（INFO·不判等）· 旧镜像 `wave_sim_aggro` ② 为 no-op 的既有缺陷
# ---------------------------------------------------------------------------
func _info_registry_old_mirror() -> void:
	_log("")
	_log("--- [登记·INFO] 旧镜像 ② 为 no-op 的既有缺陷（🔴 不判等 · 供 impl 记录登记）---")
	var prev: int = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	for path in ["A", "B"]:
		var geo = _Geo6.build()
		for w in [3, 5, 8]:
			var rt := _rt_wave(path, geo, w, false, false, true)
			var mg := _mg_wave(path, geo, w, false, false, true)
			var old := _old_aggro_wave(path, geo, w, false)
			_log("   %s geo6 W%d（普通）：真身↔合并(恒 assign) 差异键=%d（期望 0）；真身↔旧 aggro 差异键=%d（既有缺陷）"
				% [path, w, _count_wave_diffs(rt, mg), _count_wave_diffs(rt, old)])
		for w2 in [5, 10]:
			var rt2 := _rt_wave(path, geo, w2, false, true, true)
			var old2 := _old_aggro_wave(path, geo, w2, true)
			_log("   %s geo6 W%d（Sapper 开）：真身↔旧 aggro(sapper) 差异键=%d（既有缺陷）"
				% [path, w2, _count_wave_diffs(rt2, old2)])
	_SpaceModel.mode = prev
	# 整局 run-loop 层对拍（旧 aggro vs 合并 · 同配置 proto/elite OFF + aggro ON）
	_log("   -- 整局 run-loop 层：旧 run_loop_aggro(②no-op) vs 合并 run_loop_proto_aggro(②assign) --")
	for path in ["A", "B"]:
		var a := _collect(3, path, RUNS, false, false, true, false, WARMUP)
		var b := _collect(2, path, RUNS, false, false, true, false, WARMUP)
		_log("      %s：%d 局 × ≤%d 波，逐位差异格数=%d" % [path, RUNS, W_MAX, _count_runset_diffs(a, b)])
	var aS := _collect(3, "B", RUNS, false, true, true, false, WARMUP)
	var bS := _collect(2, "B", RUNS, false, false, true, true, WARMUP)
	_log("      B（Sapper 开）：逐位差异格数=%d" % _count_runset_diffs(aS, bS))


func run_all() -> bool:
	_log("")
	_log("=======================================================================")
	_log("第五刀 · 三轴合并镜像 退化逐位守护（spec §3.2 / A-3）")
	_log("  RUNS=%d · seed=%d · W_MAX=%d · WARMUP=%d" % [RUNS, SEED, W_MAX, WARMUP])
	_log("  守护①：aggro OFF → == run_loop_proto ；守护②：proto OFF+aggro → == 真身")
	_log("  守护③：全 OFF → == 金标本 run_loop ；守护④：全开 → == 真身（上线口径地基）")
	_log("=======================================================================")
	_guard1_aggro_off()
	_guard2_proto_off()
	_guard3_all_off()
	_guard4_all_on()
	_guard5_repair_zero_perturb()
	_cross_sapper()
	_cross_aggro_active()
	_check_aggro_exercised()
	_info_registry_old_mirror()
	_log("")
	_log("aggro_golive 退化守护 汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	return _fail == 0
