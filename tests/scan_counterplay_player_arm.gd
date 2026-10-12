extends SceneTree
##
## headless 反制窗口 · **玩家反制臂测量**（T-CP-02 · C-9）
##
## 🔴 使命：补上 `sapper-balance-review.md` §4-处置 C 缺的「玩家反制臂」——
##   量化「**AI 地板**（金标本 AI 不保塔的存活率）vs **玩家上限**（玩家合理反制下的存活率）」区间。
##
## 🔴 口径（与既有诊断件对齐 + 补实机几何）：
##   · **RADIAL 八槽几何**（`n_slots=8` · `SpaceModel.mode=RADIAL`）—— `scan_sapper` 只覆盖六槽 PATH，
##     本测量补实机几何口径（Sapper 锁定/暴露度在径向下的实际影响）。
##   · **忠实镜像** = `run_loop_proto_aggro`（proto + elite + aggro 全开 = 实机口径）。
##   · N=300 · seed=20261002（与 scan_bulwark / scan_protect_core 同 seed，便于对拍）。
##
## 反制臂（玩家"合理反制"四人工具箱 · `mechanics-tower-life-death` §3）：
##   · T0 AI 地板      （无反制：金标本 AI 纯 DPS 贪心，主力塔落暴露枢纽位）
##   · T1 保主力塔     （protect_core：主力塔隐身，怪跳过它）           ← 升 HP / 保塔的近似
##   · T2 理想肉盾     （bulwark：主力塔真挪到安全位，安全位塔换暴露位扛伤）← 插肉盾
##   · T3 复活         （repair=9：战斗中即时被动复活）                ← 修复/复活
##   · T4 肉盾 + 复活  （bulwark + repair=9：组合上限）
##
## 产出：区间 [T0, max(T1..T4)]（B 多塔主口径；A 单核作 INFO）。
##   🔴 只读分析 · 零数值改动 · 零代码改动（诊断件恒 quit 0）。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_counterplay_player_arm.gd [runs]
##
## ⚠️ headless：stdout 全缓冲（退出才 flush）→ 进度走 push_error(stderr 不缓冲)。
##

const _RunLoopPA := preload("res://scripts/engine/run_loop_proto_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_MAX := 20
const ACTIONS := 12
const WARMUP := 2
const N_SLOTS := 8              # 🔴 实机几何：RADIAL 八槽
const SEED := 20261002          # 与 scan_bulwark / scan_protect_core 同 seed
const GATE_B := 0.80            # 实机门禁红线（B 多塔起飞率）


func _fmt(v: float, nd: int = 3) -> String:
	var m := 1.0
	for _k in range(nd):
		m *= 10.0
	return str(int(roundf(v * m)) / m)


## 跑一个反制臂（RADIAL 八槽 · proto+elite+aggro 全开 · N=runs）。
func _arm(path: String, protect_core: bool, bulwark: bool, revive: bool, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["n_slots"] = N_SLOTS
	cfg["max_actions"] = ACTIONS
	cfg["repair_on_disable"] = (9 if revive else 0)
	var rng := _PyRandom.new(SEED)
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		var per_diag: Array = [0, 0, 0, 0.0, 0, 0]
		var out := _RunLoopPA.run(path, cx, W_MAX, null, rng,
			true, true, true, 0.6, -1.0, WARMUP, protect_core, bulwark, per_diag)
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


func _line(tag: String, r: Dictionary) -> void:
	print("  %-22s 起飞率=%s  存活率=%s  中位起飞波=%s  (%d/%d)"
		% [tag, _fmt(float(r["rate"])), _fmt(float(r["surv"])), str(r["med"]),
			int(r["n_takeoff"]), int(r["n"])])


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  反制窗口 · 玩家反制臂测量（C-9 · RADIAL 八槽 · proto+elite+aggro 全开）")
	print("  每臂 %d 局 · seed=%d · n_slots=%d · WARMUP=%d · ATTRITION=%.2f"
		% [runs, SEED, N_SLOTS, WARMUP, 1.5])
	print("  臂：T0 AI地板 / T1 保主力塔 / T2 理想肉盾 / T3 复活 / T4 肉盾+复活")
	print("===============================================================")

	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var b0 := _arm("B", false, false, false, runs)
	var b1 := _arm("B", true, false, false, runs)
	var b2 := _arm("B", false, true, false, runs)
	var b3 := _arm("B", false, false, true, runs)
	var b4 := _arm("B", true, true, true, runs)
	var a0 := _arm("A", false, false, false, runs)
	var a4 := _arm("A", true, true, true, runs)

	_SpaceModel.mode = prev_mode

	print("")
	print("---- B 多塔（主口径 · RADIAL 八槽）----")
	_line("T0 AI 地板", b0)
	_line("T1 保主力塔", b1)
	_line("T2 理想肉盾", b2)
	_line("T3 复活", b3)
	_line("T4 肉盾+复活", b4)
	print("---- A 单核（INFO）----")
	_line("T0 AI 地板", a0)
	_line("T4 肉盾+复活", a4)

	# ---- 区间 ----
	var floor := float(b0["rate"])
	var ceiling := maxf(maxf(maxf(float(b1["rate"]), float(b2["rate"])), float(b3["rate"])), float(b4["rate"]))
	print("")
	print("  ▶ 玩家反制区间（B 多塔）：AI 地板 = %s  →  玩家上限 = %s   跨度 = +%s"
		% [_fmt(floor), _fmt(ceiling), _fmt(ceiling - floor)])
	print("     · T0 地板 ≥ 门禁 %s ：%s" % [_fmt(GATE_B), ("✅ 达标" if floor >= GATE_B else "❌ 破线（AI 地板不动红线，靠玩家反制抬升）")])
	print("     · 玩家上限 ≥ 门禁 %s ：%s" % [_fmt(GATE_B), ("✅ 达标" if ceiling >= GATE_B else "❌ 上限仍破线")])
	if ceiling >= GATE_B and floor < GATE_B:
		print("     · 结论：AI 地板破线、玩家上限达标 → **反制窗口是达标必要条件**（玩家反制确有价值）")
	elif ceiling >= GATE_B and floor >= GATE_B:
		print("     · 结论：地板/上限均达标 → 反制窗口是**冗余余量**（安全但非必要）")
	else:
		print("     · 结论：即便用满反制工具箱，上限仍破线 → 惩罚过重（对接 sapper-balance-review 处置 D）")
	print("  (A 单核 INFO：地板 %s → 上限 %s；单核高风险画像为设计预期)"
		% [_fmt(float(a0["rate"])), _fmt(float(a4["rate"]))])
	print("===============================================================")
	quit(0)
