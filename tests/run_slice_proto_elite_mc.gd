extends SceneTree
##
## headless 实机口径 MC（第四刀 · 原型/精英波上线门禁）—— S5-D1 校准闸门
##
## 🔴 使命：为「原型/精英波上线」补上**实机口径**的 300 局 MC 读数。
##    现有诊断（`run_slice_geo8_mc.gd`）只跑 PATH/RADIAL 且 `proto 恒 OFF` → **未覆盖三原型+Elite**；
##    上线后的真实起飞率此前**无读数**（spec §4.2）。
##
## 口径（= 实机首次装载口径 · `boot.gd` 窗口分支注入，spec §2.2 / 附录 C-5）：
##   · `SpaceModel.mode = RADIAL`
##   · `prototype_split_enabled = true`（三原型分化）
##   · `elite_waves_enabled     = true`（Elite 波 · W5/10/15/20）
##   · `tower_aggro_enabled     = false`（本轮只上原型/精英；aggro 属 T1，Sapper 仅标记不杀伤）
##   · `n_slots = 6`（`ShopRuntime.setup` 实机默认 `cfg_of` → n_slots=6）
##   · `cfg = MvpConfig.cfg_of(path)` 实机默认（κ_r = KR_FINAL = 0.050）
##   · 战斗结算 = `RunLoopProto`（`wave_sim_proto` 批处理镜像 `WaveDirector._substep`），
##     `shop_ai` 金标本一字不改 → 300 局 build 序列与金标本一致，只换每波战斗口径
##   · rng seed = 20260930（与 S5-D1 / geo8_mc 同 seed，可对拍）
##
## 判据（S5-D1 校准闸门 · `docs/phase3/slice5-verify.md` §5）：
##   · **多塔 B 起飞率 ≥ 80%（MC 300）← 本脚本硬门禁**
##   · 起飞点 ∈ W10–15、B/A < 1 ← 由 `test_suite_slice7` 守护；本脚本附打印中位起飞波供人工判读
##
## 🔴 破 80% 红线 → **不得上线**，如实上报（本脚本 `exit 1`）；**禁止自行改任何数值**。
## 🔴 本入口**不进**默认 `run_tests.gd` 无参回归（300 局 × 4 臂耗时长，会拖慢默认回归）；
##    如需纳入聚合请**单列**（如 `-- radial8diag` 或独立入口）。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice_proto_elite_mc.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度可视需要自行加 stderr 打印。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _RunLoopProto := preload("res://scripts/engine/run_loop_proto.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_MAX := 20
const ACTIONS := 12
const SEED := 20260930
const TH_TAKEOFF_B := 0.80   # 🔴 S5-D1 红线（禁下调）
const N_SLOTS_MAIN := 6      # 实机默认（门禁臂）
const N_SLOTS_ALT := 8       # 八槽径向（参考臂 · Q-R9 未批准为出货配置）

var _fail := 0


func _fmt(v: float) -> String:
	return "%.3f" % v


## 核心 HP 分箱（末波 core_hp）：0 = 失守；5 = 满血。
func _hp_bin(hp: float) -> int:
	if hp <= 0.0:
		return 0
	if hp <= 250.0:
		return 1
	if hp <= 500.0:
		return 2
	if hp <= 750.0:
		return 3
	if hp < 1000.0:
		return 4
	return 5


## 就地镜像 `RunLoopProto.takeoff_rate` 的定义（alive ∧ takeoff_wave ≥ 0），
## 额外采集「平均结算波次」与「末波核心 HP 分布」。
func _mc(path: String, n_slots: int, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)          # 实机默认（κ_r=KR_FINAL=0.050 / substantial / tier / current）
	cfg["n_slots"] = n_slots
	cfg["max_actions"] = ACTIONS
	var rng := _PyRandom.new(SEED)         # rng 跨所有 run 连续使用（与 S5-D1 同纪律）
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	var wsum := 0
	var hp_hist: Array = [0, 0, 0, 0, 0, 0]
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		var out := _RunLoopProto.run(path, cx, W_MAX, null, rng, true, true)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := _Stats.takeoff_wave(rows)
		if alive and tw >= 0:
			takeoffs += 1
			hits.append(tw)
		var w_end := int(rows[-1]["w"]) if not rows.is_empty() else 0
		wsum += w_end
		var hp := float(rows[-1]["core_hp"]) if not rows.is_empty() else 0.0
		var b := _hp_bin(hp)
		hp_hist[b] = int(hp_hist[b]) + 1
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
		"n": runs,
		"mean_w_end": float(wsum) / float(runs),
		"hp_hist": hp_hist,
	}


func _print_arm(tag: String, r: Dictionary) -> void:
	print("  [%s] 起飞率=%s  存活率=%s  中位起飞波=%s  平均结算波=%.2f  (起飞 %d/%d)"
		% [tag, _fmt(float(r["rate"])), _fmt(float(r["surv"])), str(r["med"]),
			float(r["mean_w_end"]), int(r["n_takeoff"]), int(r["n"])])
	var h: Array = r["hp_hist"]
	var labels := ["0(失守)", "0<hp<=250", "250<hp<=500", "500<hp<=750", "750<hp<1000", "hp==1000(满)"]
	var parts: Array = []
	for i in range(h.size()):
		parts.append("%s:%d" % [labels[i], int(h[i])])
	print("       核心 HP 分布  %s" % "  ".join(parts))


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  实机口径 MC · 三原型 + Elite（RADIAL · proto/elite ON · aggro OFF）")
	print("  每点 %d 局 · seed=%d · κ_r=KR_FINAL=%.3f · W_MAX=%d · actions=%d"
		% [runs, SEED, float(_Cfg.KR_FINAL), W_MAX, ACTIONS])
	print("  (S5-D1 校准闸门：多塔 B 起飞率 ≥ %.2f → 硬门禁)" % TH_TAKEOFF_B)
	print("===============================================================")

	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	print("\n---- n_slots=%d（实机默认 · 门禁臂）----" % N_SLOTS_MAIN)
	var a6 := _mc("A", N_SLOTS_MAIN, runs)
	var b6 := _mc("B", N_SLOTS_MAIN, runs)
	_print_arm("A 单核", a6)
	_print_arm("B 多塔", b6)

	print("\n---- n_slots=%d（八槽径向 · 参考臂 · Q-R9 未批准为出货配置）----" % N_SLOTS_ALT)
	var a8 := _mc("A", N_SLOTS_ALT, runs)
	var b8 := _mc("B", N_SLOTS_ALT, runs)
	_print_arm("A 单核", a8)
	_print_arm("B 多塔", b8)

	_SpaceModel.mode = prev_mode   # 🔴 回退防污染（全局开关）

	print("")
	print("===============================================================")
	print("  门禁判定（S5-D1 · 多塔 B 起飞率 ≥ %.2f）" % TH_TAKEOFF_B)
	var b_rate := float(b6["rate"])
	if b_rate >= TH_TAKEOFF_B:
		print("  [PASS] B(n_slots=%d) 起飞率 %s ≥ %.2f"
			% [N_SLOTS_MAIN, _fmt(b_rate), TH_TAKEOFF_B])
	else:
		print("  [FAIL] B(n_slots=%d) 起飞率 %s < %.2f  🔴 破线 → 不得上线，如实上报，禁止自行改数值"
			% [N_SLOTS_MAIN, _fmt(b_rate), TH_TAKEOFF_B])
		_fail += 1
	print("  [INFO] B(n_slots=%d) 起飞率 %s / A 起飞率 %s（八槽参考臂）"
		% [N_SLOTS_ALT, _fmt(float(b8["rate"])), _fmt(float(a8["rate"]))])
	print("===============================================================")
	quit(0 if _fail == 0 else 1)
