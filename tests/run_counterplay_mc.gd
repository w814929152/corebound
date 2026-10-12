extends SceneTree
##
## headless 反制窗口（T-CP-02 · C-8）· **M-1 复活上线门禁 MC**
##
## 🔴 使命：为「反制窗口 M-1（战斗中即时被动复活）上线」补上**实机全开口径**的 MC 读数。
##   产品口径（`boot.gd`）本轮新增 `combat_revive_enabled = true`（= 战斗中即时被动复活）。
##   🔴 **重要口径说明（批处理 ↔ 产品开关的映射）**：
##     · 产品路径 = 实时版 `WaveDirector`（读 `combat_revive_enabled` 成员）；
##     · 本 MC = **批处理镜像** `run_loop_proto_aggro` / `wave_sim_proto_aggro`，**不认识**该成员
##       → 只能经 `cfg["repair_on_disable"] = 9`（战斗内即时复活档）驱动同一套 M-1 逻辑。
##     🟡 因此本脚本的 "revive ON" 臂 = `repair_on_disable = 9`（**战斗复活，不含安全窗修复**）。
##        ⚠️ 批处理**无法表达** 「PRICED(2) 安全窗修复 + 9 战斗复活」的组合 → 组合口径留待试玩。
##
## 口径矩阵（= 实机全开 · `boot.gd` 窗口分支 + C-2 新增 revive）：
##   · `SpaceModel.mode = RADIAL` · `prototype/elite/tower_aggro = true`
##   · `repair_on_disable ∈ {0 OFF(基线·下界), 1 FREE(上界), 2 PRICED(安全窗修复), 9 REVIVE(M-1)}`
##   · `warmup_waves = MonsterData.WARMUP = 2` · `n_slots = 6`（门禁）/`8`（参考）
##
## 判据（team-lead · C-8）：
##   · **主判**：REVIVE(9) 臂 B(n_slots=6) 起飞率 ≥ 0.80 → 保留 C-2 上行；< 0.80 → 破线不上线。
##   · **自检**：OFF(0) 臂 B@6 必须复现既有基线 203/300=0.677（revive 接线零扰动证据）。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_counterplay_mc.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _RunLoopPA := preload("res://scripts/engine/run_loop_proto_aggro.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_MAX := 20
const ACTIONS := 12
const SEED := 20260930
const TH_TAKEOFF_B := 0.80      # 🔴 team-lead C-8 门禁红线（禁下调）
const WARMUP := 2
const N_SLOTS_MAIN := 6
const N_SLOTS_ALT := 8
const BASE_B6_N_TAKEOFF := 203  # 既有基线 OFF B@6 = 203/300 = 0.677（自检复现）
const MODES: Array = [0, 1, 2, 9]
const LABELS: Array = [
	"repair=0 OFF(基线·下界)",
	"repair=1 FREE(上界)",
	"repair=2 PRICED(安全窗修复)",
	"repair=9 REVIVE(M-1·战斗内复活)",
]

var _fail := 0


func _fmt(v: float) -> String:
	return "%.3f" % v


func _mc(path: String, n_slots: int, repair_mode: int, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["n_slots"] = n_slots
	cfg["max_actions"] = ACTIONS
	cfg["repair_on_disable"] = repair_mode
	var rng := _PyRandom.new(SEED)
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		var per_diag: Array = [0, 0, 0, 0.0, 0, 0]
		var out := _RunLoopPA.run(path, cx, W_MAX, null, rng,
			true, true, true, 0.6, -1.0, WARMUP, false, false, per_diag)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := _Stats.takeoff_wave(rows)
		if alive and tw >= 0:
			takeoffs += 1
			hits.append(tw)
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
	print("  反制窗口 M-1 上线门禁 MC（C-8 · RADIAL + 三原型 + Elite + 仇恨全开）")
	print("  repair_on_disable ∈ {0 OFF, 1 FREE, 2 PRICED, 9 REVIVE(M-1)}")
	print("  每臂 %d 局 · seed=%d · κ_r=KR_FINAL=%.3f · W_MAX=%d · warmup=%d"
		% [runs, SEED, float(_Cfg.KR_FINAL), W_MAX, WARMUP])
	print("  主判：REVIVE(9) 多塔 B@%d 起飞率 ≥ %.2f" % [N_SLOTS_MAIN, TH_TAKEOFF_B])
	print("===============================================================")

	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var m6: Dictionary = {}
	var m8: Dictionary = {}
	for mode in MODES:
		var a := _mc("A", N_SLOTS_MAIN, int(mode), runs)
		var b := _mc("B", N_SLOTS_MAIN, int(mode), runs)
		m6[int(mode)] = {"A": a, "B": b}
	for mode in [0, 9]:
		var a8 := _mc("A", N_SLOTS_ALT, int(mode), runs)
		var b8 := _mc("B", N_SLOTS_ALT, int(mode), runs)
		m8[int(mode)] = {"A": a8, "B": b8}

	_SpaceModel.mode = prev_mode

	print("")
	print("---- n_slots=%d（实机默认 · 门禁臂）----" % N_SLOTS_MAIN)
	for ri in range(MODES.size()):
		_print_arm("%s · A 单核" % String(LABELS[ri]), m6[int(MODES[ri])]["A"])
		_print_arm("%s · B 多塔" % String(LABELS[ri]), m6[int(MODES[ri])]["B"])
	print("")
	print("---- n_slots=%d（八槽径向 · 参考臂）----" % N_SLOTS_ALT)
	for ri in [0, 3]:
		_print_arm("%s · B 多塔" % String(LABELS[ri]), m8[int(MODES[ri])]["B"])

	print("")
	print("===============================================================")
	print("  门禁判定（主判 = REVIVE(9) 多塔 B@%d 起飞率 ≥ %.2f）" % [N_SLOTS_MAIN, TH_TAKEOFF_B])
	print("===============================================================")
	print("  B@%d 跨档位：" % N_SLOTS_MAIN)
	for ri in range(MODES.size()):
		var b6: Dictionary = m6[int(MODES[ri])]["B"]
		print("    %-34s B@%d = %s  (起飞 %d/%d · 存活 %d/%d)"
			% [String(LABELS[ri]), N_SLOTS_MAIN, _fmt(float(b6["rate"])),
				int(b6["n_takeoff"]), int(b6["n"]), int(b6["n_surv"]), int(b6["n"])])

	# ---- 自检：OFF 臂 B@6 复现基线 203/300 ----
	var off_takeoff := int(m6[0]["B"]["n_takeoff"])
	if off_takeoff == BASE_B6_N_TAKEOFF:
		print("  [自检] OFF B@%d 复现基线 %d/%d=0.677 ✅（M-1 接线零扰动）"
			% [N_SLOTS_MAIN, off_takeoff, int(m6[0]["B"]["n"])])
	else:
		print("  [自检] 🔴 OFF B@%d = %d/%d（期望 %d/300）→ 偏差 = 红旗（0 档被污染？）"
			% [N_SLOTS_MAIN, off_takeoff, int(m6[0]["B"]["n"]), BASE_B6_N_TAKEOFF])
		_fail += 1

	# ---- 主判：REVIVE(9) B@6 ≥ 0.80 ----
	var rv_rate := float(m6[9]["B"]["rate"])
	if rv_rate >= TH_TAKEOFF_B:
		print("  [PASS] 主判 · REVIVE(9) B@%d 起飞率 %s ≥ %.2f → 达标（🔴 不得自行上线，待用户呈请）"
			% [N_SLOTS_MAIN, _fmt(rv_rate), TH_TAKEOFF_B])
	else:
		print("  [FAIL] 主判 · REVIVE(9) B@%d 起飞率 %s < %.2f 🔴 破线 → C-2 应改回 false，如实上报（禁改数值）"
			% [N_SLOTS_MAIN, _fmt(rv_rate), TH_TAKEOFF_B])
		_fail += 1
	print("  [INFO] 参考：OFF=%s ／ FREE=%s ／ PRICED=%s ／ REVIVE=%s（B@%d）"
		% [_fmt(float(m6[0]["B"]["rate"])), _fmt(float(m6[1]["B"]["rate"])),
			_fmt(float(m6[2]["B"]["rate"])), _fmt(rv_rate), N_SLOTS_MAIN])
	print("  [INFO] 八槽参考：OFF B@%d=%s ／ REVIVE B@%d=%s"
		% [N_SLOTS_ALT, _fmt(float(m8[0]["B"]["rate"])),
			N_SLOTS_ALT, _fmt(float(m8[9]["B"]["rate"]))])
	print("  ⚠️ 口径注：批处理无法表达「PRICED 安全窗修复 + REVIVE 战斗复活」组合；"
		+ "REVIVE 臂 = 仅战斗复活。")
	print("===============================================================")
	quit(0 if _fail == 0 else 1)
