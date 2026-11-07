extends SceneTree
##
## headless 场景地图「三裂环」MC 对照（scene-map.md §11 步 5 · 发版前置闸门）
##
## 🔴 为什么单独一个脚本、不复用 geo8_mc：
##   `run_slice_geo8_mc.gd` 比的是「八槽 vs 六槽」，且 sim 的塔位几何由 `_Geo6.build_by_slots`
##   给出 —— 它**不认识阵地**。本脚本要回答的问题是：
##
##     「把可建格从 6 个固定槽 / 965 格空盘，收敛到 17 格阵地（且塔上限 10），
##       实机起飞难度变了多少？」
##
##   所以必须**注入阵地几何**：`geo = _Geo.new(_BuildGrid.site_points())`，
##   让 `damage_engine` 的共鸣 `links()` 按阵地真实格距断链/连链，
##   让 `ShopAI.free_map_slots` 在 0..16 的槽号空间上选塔位（槽号 == 阵地格索引）。
##
## 🔴 三臂（同 seed，控制变量）：
##   · ARM 1 = PATH 六槽      —— 金标本基线（n_slots=6，SLOTS6 几何，逐位不变）
##   · ARM 2 = RADIAL 六槽    —— 径向对照（n_slots=6，SLOTS6 几何，无阵地）
##   · ARM 3 = RADIAL 阵地 17 —— 新改动（n_slots=17，SITES 几何，B 塔上限 10）
##
## 判读：
##   · Δ(3−2) = 阵地化本身的净效果（把「自由摆放 + 阵地」vs「固定六槽」的差异量化出来）；
##   · 若 ARM3 起飞率 ≥ 0.80 → 阵地化不破坏起飞可行性，可发版；
##   · 若剧烈下滑 → 需要按 scene-map.md §10 的补偿顺序（tower_cap 10→12 ＞ 岩脊 40°→30°）。
##
## ⚠️ 已知口径差异（必须写进判读，不能假装对齐）：
##   · sim 的覆盖走 `coverage_mode="path"` 常量（不读几何），实机 RADIAL 同理（未接 V-5 几何）。
##     所以「岩脊带来的 +12.5% 挨打税」在 sim 里**不体现** —— sim 的仇恨几何用 SLOTS6 曝光，
##     与阵地格心的真实曝光是两套。本脚本只测「共鸣拓扑 + 塔位稀缺」这两条已接线的轴。
##   · 曝光税（360/320）是实机专属、sim 不可测的轴，必须靠 probe_radial_aggro 目检，
##     不能靠 MC。
##
## 跑法：
##   <godot> --headless --path . --script res://tests/run_scene_map_mc.gd -- 300
##   🔴 `--` 分隔符必须写，否则 `300` 不会被当作 user arg（脚本恒跑默认 300）。
##   headless 下 stdout 全缓冲（退出才 flush），进度看退出时一次性输出。
##

const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _RunLoopAggro = preload("res://scripts/engine/run_loop_aggro.gd")
const _PyRandom = preload("res://scripts/engine/py_random.gd")
const _SpaceModel = preload("res://scripts/geo/space_model.gd")
const _BuildGrid = preload("res://scripts/geo/build_grid.gd")
const _Geo = preload("res://scripts/geo/geo.gd")
const _Geo6 = preload("res://scripts/geo/geo6.gd")
const _Stats = preload("res://scripts/engine/stats.gd")

const W_MAX := 20
const WARMUP := 2
const ATTRITION := 1.5
const SEED := 20260930


func _fmt(v: float) -> String:
	return "%.3f" % v


## 跑 runs 局，注入指定 geo + 塔上限。返回 {rate, surv, med}。
func _run_geo(path: String, geo, runs: int, max_towers_b: int, rng) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)
	cfg["n_slots"] = geo.n
	cfg["max_actions"] = 12
	# 阵地臂：塔上限必须钉住（否则 B 的 AI 会把 17 格摆满，超过实机 tower_cap=10）。
	cfg["max_towers"] = {"A": 2, "B": max_towers_b}
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		cx["max_actions"] = 12
		var out := _RunLoopAggro.run(path, cx, W_MAX, geo, rng, true, 0.6, ATTRITION, WARMUP, false, false, false)
		var rows: Array = out["rows"]
		var alive := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		if alive:
			survives += 1
		var tw := _Stats.takeoff_wave(rows)
		if alive and tw >= 0:
			takeoffs += 1
			hits.append(tw)
	return {
		"rate": _Stats.pround(float(takeoffs) / float(runs), 3),
		"surv": _Stats.pround(float(survives) / float(runs), 3),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
	}


func _arm(name: String, path: String, geo, runs: int, max_towers_b: int, rng) -> Dictionary:
	var r := _run_geo(path, geo, runs, max_towers_b, rng)
	print("  %s：起飞率 = %s  存活 = %s  中位波 = %s" % [name, _fmt(r["rate"]), _fmt(r["surv"]), str(r["med"])])
	return r


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  场景地图「三裂环」MC 对照（scene-map.md 步5 · 发版前置）")
	print("  每点 %d 局 · ATTRITION=%.1f · 起手保护 W1-%d · seed=%d" % [runs, ATTRITION, WARMUP, SEED])
	print("  三臂（B）+ 一臂（A）：PATH六槽 · RADIAL六槽 · RADIAL阵地17 · A阵地17")
	print("===============================================================")

	# ---- ARM 1：PATH 六槽（金标本基线）----
	print("\n  === [ARM 1] PATH 六槽（SLOTS6 几何 · 逐位不变基线）===")
	var g6 = _Geo6.build()
	var rng1 = _PyRandom.new(SEED)
	var p := _arm("PATH 六槽", "B", g6, runs, 6, rng1)

	# ---- ARM 2：RADIAL 六槽（径向对照，无阵地）----
	print("\n  === [ARM 2] RADIAL 六槽（SLOTS6 几何 · 无阵地）===")
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var rng2 = _PyRandom.new(SEED)
	var r := _arm("RADIAL 六槽", "B", g6, runs, 6, rng2)

	# ---- ARM 3：RADIAL 阵地 17 格（新改动）----
	print("\n  === [ARM 3] RADIAL 阵地 17 格（SITES 几何 · 塔上限 10）===")
	var pts: Array = _BuildGrid.site_points()
	var g17 := _Geo.new(pts)
	var rng3 = _PyRandom.new(SEED)
	var m := _arm("RADIAL 阵地17", "B", g17, runs, 10, rng3)

	# ---- ARM 4：A 路径 · RADIAL 阵地 17 格（另一条玩家路线，A 恒 2 塔）----
	print("\n  === [ARM 4] A 路径 · RADIAL 阵地 17 格（塔上限 2，验证 A 路线）===")
	var rng4 = _PyRandom.new(SEED)
	var ma := _arm("A · RADIAL 阵地17", "A", g17, runs, 2, rng4)

	# ---- 回退防污染 ----
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	# ---- 对照 ----
	print("\n===============================================================")
	print("  对照（同 seed · 控制变量）：")
	print("    阵地化净效果 Δ(3−2) = %s" % _fmt(float(m["rate"]) - float(r["rate"])))
	print("    阵地 vs PATH 基线 Δ(3−1) = %s" % _fmt(float(m["rate"]) - float(p["rate"])))
	print("    径向(无阵地) vs PATH Δ(2−1) = %s" % _fmt(float(r["rate"]) - float(p["rate"])))
	print("    A 路径 · 阵地17 起飞率 = %s" % _fmt(float(ma["rate"])))
	print("  判读：ARM3 起飞率 ≥ 0.80 → 可发版；< 0.80 → 按 scene-map §10 补偿")
	print("  ⚠️ 曝光税(+12.5%)在 sim 不可测，只测共鸣拓扑+塔位稀缺两条已接线轴")
	print("===============================================================")
	quit(0)
