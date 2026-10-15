extends SceneTree
##
## headless 反制窗口 **实时版 MC**（R-1 · 2026-10-12 用户批准执行）
##
## 🔴 使命：把「产品开关 `combat_revive_enabled` ≡ 诊断档 9」从**仅 1 条单波断言**，
##   升级为**全 run（20 波 × shop AI × 300 局）· 产品代码路径**的读数。
##   · C-8/C-9 的 MC 全走**批处理镜像**（`run_loop_proto_aggro`/`wave_sim_proto_aggro`），
##     靠 `cfg["repair_on_disable"]=9` 驱动 M-1，**批处理不认识** `combat_revive_enabled`。
##   · 本脚本走**实时版 `WaveDirector`（真身）** —— 直接读产品成员 `combat_revive_enabled`
##     （`_revive_mode()` 打开时返回 9）→ 这是**产品实机路径**。
##
## 🔴 结构 = `RunLoopProtoAggro.run()` 的 run-level 镜像（逐行照搬其外层循环），
##   唯一差异：单波战斗从 `simulate_wave_proto_aggro(...)` 换成
##   `wd.start_wave(w); wd.run_to_end()`（真身子步）。其余（income / shop_phase /
##   core_hp 扣减 / rows 组装 / takeoff_wave 判定）逐行不变。
##
## 🔴 零扰动守门（team-lead 强约束 —— rng 消费序的最强守门）：
##   OFF 臂（`combat_revive_enabled=false` · `repair_on_disable=0` · RADIAL 六槽 ·
##   proto/elite/aggro 全开 · seed=20260930）**必须复现批处理基线 `205/300 = 0.683`**。
##   → 若 OFF 未复现 = 实时↔批处理分岔（rng 序 / 口径差异）→ **立即停手上报，禁硬调**。
##
## 口径（= C-8 实机全开 MC 同口径，便于对拍）：
##   · `SpaceModel.mode = RADIAL` · `n_slots = 6`（实机默认 · 门禁臂）
##   · `prototype_split_enabled = elite_waves_enabled = tower_aggro_enabled = true`
##   · `repair_on_disable = 0`（诊断枚举保持 OFF；产品开关经 `combat_revive_enabled` 表达）
##   · `warmup_waves = MonsterData.WARMUP = 2` · seed=20260930 · W_MAX=20 · actions=12
##
## 判据：
##   · **守门（硬）**：OFF B@6 == 205/300（实时↔批处理零分岔 → 实时版读数可信）
##   · **主判**：PRODUCT（`combat_revive_enabled=true`）B@6 起飞率 ≥ 0.80
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_realtime_counterplay_mc.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）。
## ⚠️ G6：headless `--script` 无 global_script_class_cache → 一律 preload，不写 class_name。
##

const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_MAX := 20
const ACTIONS := 12
const SEED := 20260930
const TH_TAKEOFF_B := 0.80      # 🔴 team-lead R-1 门禁红线（禁下调）
const WARMUP := 2               # = MonsterData.WARMUP
const N_SLOTS_MAIN := 6         # 实机默认（门禁臂）
const BASE_B6_N_TAKEOFF := 205  # 🔴 提交②翻参后批处理基线 OFF B@6=205/300=0.683（守门目标：必须复现）

var _fail := 0


func _fmt(v: float, nd: int = 3) -> String:
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)


## 跑一局（实时真身 · run-level 镜像 RunLoopProtoAggro.run）。
## 🔴 返回 {alive, takeoff, tw}；takeoff 定义与批处理一致（alive ∧ takeoff_wave ≥ 0）。
func _run_once(path: String, cfg: Dictionary, combat_revive: bool, rng) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	var n_slots := int(c["n_slots"])
	var geo = _Geo6.build_by_slots(n_slots)

	var player = _SimPlayer.new_player(path, c, geo)

	# 🔴 真身：产品开关 combat_revive_enabled（不占用诊断枚举 repair_on_disable）。
	var wd = _WaveDirector.new()
	wd.prototype_split_enabled = true
	wd.elite_waves_enabled = true
	wd.tower_aggro_enabled = true
	wd.warmup_waves = WARMUP
	wd.combat_revive_enabled = combat_revive
	wd.setup(player, c, geo)          # core_hp 初值取 player.core_hp（= cfg.core_hp）

	var rows: Array = []
	var cum := 0.0
	for w in range(1, W_MAX + 1):
		# ---- 单波战斗（真身子步）----
		wd.start_wave(w)
		wd.run_to_end()
		var lr: Dictionary = wd.last_result

		# ---- 收入（与批处理同序：先按 shop 前的 income_mult 结算，再进 shop）----
		var income := float(lr["scrap_earned"]) * (1.0 + float(player.income_mult))
		cum += income

		# ---- 商店（金标本 shop_ai 一字不改；rng 跨局连续消费）----
		var shop: Array = _ShopAI.shop_phase(player, cum, w, c, geo, rng)
		cum = float(shop[0])

		# ---- 起飞判据组装（🔴 与批处理逐行同口径）----
		#   POST-shop dps（批处理 row 亦用 shop 之后的 dps_only）。
		var dps := _DE.dps_only(player, c, geo)
		#   total_hp：批处理 = Σ hp_unit·hp_mults[i]（proto ON 口径）。
		#  真身不导出 total_hp → 用真身本波出生表 `_hp_mults` 同序重建（同一工厂 → 逐位相同）。
		var hp_unit := float(lr["hp_each"])
		var n := int(lr["n"])
		var total_hp := 0.0
		for i in range(n):
			total_hp += hp_unit * float(wd._hp_mults[i])
		var ratio := dps / total_hp if total_hp > 0.0 else 0.0
		var core_hp := maxf(0.0, float(wd.core_hp))

		rows.append({
			"w": w,
			"n": n,
			"dps": _Stats.pround(dps, 1),
			"ratio": _Stats.pround(ratio, 3),
			"core_hp": _Stats.pround(core_hp, 1),
			"core_hp_raw": core_hp,
		})
		if core_hp <= 0.0:
			break

	var alive := (not rows.is_empty()) and float(rows[-1]["core_hp_raw"]) > 0.0
	var tw := _Stats.takeoff_wave(rows)
	var res := {"alive": alive, "takeoff": (alive and tw >= 0), "tw": tw}
	wd.free()   # 🔴 真身是 Node（未入树）→ 显式释放，避免 ObjectDB 泄漏告警
	return res


## 跑一个臂（runs 局 · 独立 rng(SEED) —— 与 C-8 `_mc` 同纪律）。
func _arm(path: String, n_slots: int, combat_revive: bool, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["n_slots"] = n_slots
	cfg["max_actions"] = ACTIONS
	cfg["repair_on_disable"] = 0      # 🔴 诊断枚举保持 OFF；产品开关走 combat_revive
	var rng := _PyRandom.new(SEED)
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var r := _run_once(path, cfg, combat_revive, rng)
		if bool(r["alive"]):
			survives += 1
		if bool(r["takeoff"]):
			takeoffs += 1
			hits.append(int(r["tw"]))
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
		"n": runs,
	}


func _print_arm(tag: String, r: Dictionary) -> void:
	print("  [%s] 起飞率=%s  存活率=%s  中位起飞波=%s  (起飞 %d/%d)"
		% [tag, _fmt(float(r["rate"])), _fmt(float(r["surv"])), str(r["med"]),
			int(r["n_takeoff"]), int(r["n"])])


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  反制窗口 实时版 MC（R-1 · 真身 WaveDirector · 产品开关 combat_revive_enabled）")
	print("  RADIAL 六槽 · proto + elite + aggro 全开 · repair_on_disable=0")
	print("  每臂 %d 局 · seed=%d · κ_r=KR_FINAL=%.3f · W_MAX=%d · warmup=%d · actions=%d"
		% [runs, SEED, float(_Cfg.KR_FINAL), W_MAX, WARMUP, ACTIONS])
	print("  守门：OFF B@%d 必须 == %d/%d（实时↔批处理零分岔）" % [N_SLOTS_MAIN, BASE_B6_N_TAKEOFF, runs])
	print("  主判：PRODUCT(combat_revive=true) B@%d 起飞率 ≥ %.2f" % [N_SLOTS_MAIN, TH_TAKEOFF_B])
	print("===============================================================")

	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var t0 := Time.get_ticks_msec()
	var off_b := _arm("B", N_SLOTS_MAIN, false, runs)
	var t_off := Time.get_ticks_msec()
	var prd_b := _arm("B", N_SLOTS_MAIN, true, runs)
	var t_prd := Time.get_ticks_msec()
	var off_a := _arm("A", N_SLOTS_MAIN, false, runs)
	var prd_a := _arm("A", N_SLOTS_MAIN, true, runs)
	var t_all := Time.get_ticks_msec()

	_SpaceModel.mode = prev_mode   # 🔴 回退防污染（全局开关）

	print("")
	print("---- n_slots=%d（实机默认 · 门禁臂）----" % N_SLOTS_MAIN)
	_print_arm("OFF     · B 多塔", off_b)
	_print_arm("PRODUCT · B 多塔", prd_b)
	print("")
	print("---- n_slots=%d · A 单核（INFO）----" % N_SLOTS_MAIN)
	_print_arm("OFF     · A 单核", off_a)
	_print_arm("PRODUCT · A 单核", prd_a)
	print("")
	print("  耗时：OFF B = %d ms ／ PRODUCT B = %d ms ／ 全 4 臂 = %d ms（%d 局/臂）"
		% [int(t_off - t0), int(t_prd - t_off), int(t_all - t0), runs])
	print("  单局均耗时 ≈ %.1f ms（B 臂 %d 局）" % [float(t_off - t0) / float(runs), runs])

	print("")
	print("===============================================================")
	print("  判定")
	print("===============================================================")
	# ---- 守门：OFF B@6 == 205 ----
	var off_takeoff := int(off_b["n_takeoff"])
	if off_takeoff == BASE_B6_N_TAKEOFF:
		print("  [守门 PASS] OFF B@%d 复现批处理基线 %d/%d=0.683 ✅（实时↔批处理零分岔 · 实时读数可信）"
			% [N_SLOTS_MAIN, off_takeoff, int(off_b["n"])])
	else:
		print("  [守门 FAIL] OFF B@%d = %d/%d（期望 %d/%d）→ 🔴 实时↔批处理**分岔**（rng 序 / 口径差异）"
			% [N_SLOTS_MAIN, off_takeoff, int(off_b["n"]), BASE_B6_N_TAKEOFF, runs])
		print("             → 按约束**停手上报**，禁硬调；实时版读数**不可信** → 不推广。")
		_fail += 1

	# ---- 主判：PRODUCT B@6 ≥ 0.80 ----
	var prd_rate := float(prd_b["rate"])
	if off_takeoff != BASE_B6_N_TAKEOFF:
		print("  [主判 跳过] 守门未过 → 产品臂读数不作判据。")
	elif prd_rate >= TH_TAKEOFF_B:
		print("  [主判 PASS] PRODUCT B@%d 起飞率 %s ≥ %.2f → 产品路径达标（🔴 不得自行上线，待用户呈请）"
			% [N_SLOTS_MAIN, _fmt(prd_rate), TH_TAKEOFF_B])
	else:
		print("  [主判 FAIL] PRODUCT B@%d 起飞率 %s < %.2f 🔴 破线 → 如实上报（禁改数值）"
			% [N_SLOTS_MAIN, _fmt(prd_rate), TH_TAKEOFF_B])
		_fail += 1
	print("  [INFO] OFF B@%d=%s ／ PRODUCT B@%d=%s（Δ=%s）"
		% [N_SLOTS_MAIN, _fmt(float(off_b["rate"])), N_SLOTS_MAIN, _fmt(prd_rate),
			_fmt(prd_rate - float(off_b["rate"]))])
	print("  [INFO] A 单核：OFF=%s ／ PRODUCT=%s（INFO · 不作门禁）"
		% [_fmt(float(off_a["rate"])), _fmt(float(prd_a["rate"]))])
	print("===============================================================")
	quit(0 if _fail == 0 else 1)
