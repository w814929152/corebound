extends SceneTree
##
## headless 八槽径向 V-1′ 判据验收（`attrition8` 入口）—— 阶段3 T1 数值重扫定稿
##
## 🔴 使命：按 V-1′ 新判据（按路径分列，以 A 单核流为机制验收基准）验收
##    八槽径向下的塔死亡机制，确认 ATTRITION=1.50（六槽定稿值）在径向下仍满足：
##      · T-A′  A 单核流成型期 W6–12 累计塔死 ≥1（机制对高风险画像可感知）
##      · T-B′  A 单核流成型期 W6–12 累计塔死 ≤4（不失控）
##      · T-C′  B 多塔流雪崩期 W13–20 塔死 ≈0（机制自然退场）
##      · T-D′  B 多塔流全程塔死 =0（多塔稳健流奖励，须保持免疫）
##      · 起飞率 B ≥0.80（金标本红线不破）
##
## 依据：`design/gdd/mechanics-tower-life-death.md` §4.2 V-1′ 定稿行（2026-10-08）。
##   旧判据 T-A/T-B/T-C（全场均匀口径）在八槽径向失效（结构性碰撞，非数值失衡）：
##   怪在塔群外被金标本多塔 DPS 全秒，B 路径塔天然免疫。V-1′ 按路径分列修正。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice_attrition8.gd
##

const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const W_FORM_END := 12         # 成型期 W6–12
const W_MAX := 20
const WARMUP := 2
const RUNS := 300
const ATTRITION_FINAL := 1.5   # ✅ V-1′ 定稿（六槽值沿用，径向 A 路径下满足）

var _fail = 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print("   [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("  " + detail) if detail != "" else ""])
	if not cond:
		_fail += 1


func _initialize() -> void:
	print("===================================================================")
	print("径向阶段3 · 八槽 V-1′ 判据验收（ATTRITION=%.2f · 300 局 × A/B）" % ATTRITION_FINAL)
	print("===================================================================")

	# 切径向模式（本验收专用，跑后回退）
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	# ---- 累积 A/B 两路径三阶段塔死 + 起飞 ----
	var rngB := _PyRandom.new(20261002)
	var rngA := _PyRandom.new(20261002)
	var b_dis := [0, 0, 0]       # B 苟活/成型/雪崩
	var a_dis := [0, 0, 0]       # A 苟活/成型/雪崩
	var takeoff_b := 0
	var takeoff_a := 0

	for _i in range(RUNS):
		# B 路径（多塔金标本）
		var cfgB := _Cfg.cfg_of("B")
		cfgB["n_slots"] = 8
		cfgB["max_actions"] = 12
		var out := _RunLoopAggro.run("B", cfgB, W_MAX, null, rngB, true, 0.6, ATTRITION_FINAL, WARMUP)
		_add_dis(out["rows"], b_dis)
		if (not out["rows"].is_empty()) and float(out["rows"][-1]["core_hp"]) > 0.0:
			takeoff_b += 1

		# A 路径（单核金标本）
		var cfgA := _Cfg.cfg_of("A")
		cfgA["n_slots"] = 8
		cfgA["max_actions"] = 12
		var outa := _RunLoopAggro.run("A", cfgA, W_MAX, null, rngA, true, 0.6, ATTRITION_FINAL, WARMUP)
		_add_dis(outa["rows"], a_dis)
		if (not outa["rows"].is_empty()) and float(outa["rows"][-1]["core_hp"]) > 0.0:
			takeoff_a += 1

	# 平均每局
	var a_form := float(a_dis[1]) / float(RUNS)   # A 成型期
	var b_total := float(b_dis[0] + b_dis[1] + b_dis[2]) / float(RUNS)
	var b_tc := float(b_dis[2]) / float(RUNS)      # B 雪崩期
	var rate_b := float(takeoff_b) / float(RUNS)
	var rate_a := float(takeoff_a) / float(RUNS)

	print("\n---- 实测（300 局平均）----")
	print("   A 成型期 W6–12 塔死 = %.3f（T-A′ ≥1 / T-B′ ≤4）" % a_form)
	print("   B 全程塔死          = %.3f（T-D′ =0 免疫）" % b_total)
	print("   B 雪崩期 W13–20 塔死 = %.3f（T-C′ ≈0）" % b_tc)
	print("   起飞率 B/A = %.3f / %.3f（B ≥0.80 红线）" % [rate_b, rate_a])

	print("\n---- [T-A′] A 单核流成型期塔死 ≥1（机制可感知）----")
	_ok("T-A′ A 成型期塔死 %.3f ≥ 1.0" % a_form, a_form >= 1.0, "(机制对高风险画像可感知)")

	print("\n---- [T-B′] A 单核流成型期塔死 ≤4（不失控）----")
	_ok("T-B′ A 成型期塔死 %.3f ≤ 4.0" % a_form, a_form <= 4.0, "(不失控)")

	print("\n---- [T-C′] B 多塔流雪崩期塔死 ≈0（机制退场）----")
	_ok("T-C′ B 雪崩期塔死 %.3f ≤ 0.5" % b_tc, b_tc <= 0.5, "(机制自然退场)")

	print("\n---- [T-D′] B 多塔流全程塔死 =0（多塔稳健流免疫）----")
	_ok("T-D′ B 全程塔死 %.3f = 0.0" % b_total, b_total <= 0.0, "(多塔稳健流奖励，保持免疫)")

	print("\n---- [起飞率] B ≥0.80 金标本红线 ----")
	_ok("起飞率 B %.3f ≥ 0.80" % rate_b, rate_b >= 0.80, "(金标本红线不破)")

	# 回退 PATH 模式
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	print("\n===================================================================")
	print("八槽径向 V-1′ 判据验收汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)


## 把一行 rows 的三阶段 dis_new 累加进 dis[3]（Array 传引用，直接 mutate）
func _add_dis(rows: Array, dis: Array) -> void:
	for r in rows:
		var wn: int = int(r["w"])
		var dn: int = int(r.get("dis_new", 0))
		if wn <= 5:
			dis[0] = int(dis[0]) + dn
		elif wn <= W_FORM_END:
			dis[1] = int(dis[1]) + dn
		else:
			dis[2] = int(dis[2]) + dn
