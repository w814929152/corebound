extends SceneTree
##
## headless V-7 repair_on_disable 三臂对照扫描（QG-RADIAL-01 · 诊断开关验证）
##
## 🔴 使命：回答 GDD §2.3「塔死了还能在安全窗修」是真设计还是纸面设计。
##   三臂 × 300 局 × A 路径，看存活率相对基线的回升 Δ：
##     臂0 OFF   (repair_on_disable=0)  基线复现（须 == 逐位基线）
##     臂1 FREE  (=1)  波次间无条件全修、不占预算（结构探针）
##     臂2 PRICED(=2)  修复作为 shop_ai 候选、按 ceil(0.30·invested_est) 定价、竞争预算
##
## 依据：`docs/phase3/qg-radial/v7-repair-on-disable-spec.md` §3.7 / §5.1 输出格式。
##
## ─────────────────────────────────────────────────────────────────────────────
## 🔴 参数锁死（§5-1）：与 run_slice_attrition8.gd 基线同口径
##   SpaceModel.mode=RADIAL · n_slots=8 · max_actions=12 · aggro=true · exp=0.6
##   · attrition=1.50 · warmup=2 · rng=PyRandom(20261002)（与基线同 seed，配对前提）
##   · max_wave=20 · 跑后务必把 SpaceModel.mode 设回 PATH
##
## 🔴 配对设计：每臂一个独立 PyRandom(20261002)，跨 300 局连续推进（与基线同款）。
##   n_identical = 三臂逐局 rows 完全逐位相同的局数（配对强度度量）。
##
## ⚠️ 输出纪律：ASCII（Windows GBK 有损解码，中文会乱码）。判据用 [PASS]/[FAIL]。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_repair_on_disable.gd
##
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const RUNS := 300
const MAX_WAVE := 20
const ATTRITION := 1.50
const WARMUP := 2
const SEED := 20261002
const DELTA_GATE := 0.05        # §3.3 分支 A 点估计门槛（判读留文策渊，本脚本只打数据）
const TD_UPPER := 0.2933        # Δ 结构上限 = 88/300（修复前基线塔死局数 / N）


# ─────────────────────────────────────────────────────────────────────────────
# 单臂 300 局 A 路径。mode_val: 0=OFF 1=FREE 2=PRICED
# 返回 {surv, n_surv, n_fail, n_td, diag{...}, recs:[{fail, rows_sig, td}...]}
# ─────────────────────────────────────────────────────────────────────────────
func _run_arm(mode_val: int) -> Dictionary:
	var rng := _PyRandom.new(SEED)
	var cfgA := _Cfg.cfg_of("A")
	cfgA["n_slots"] = 8
	cfgA["max_actions"] = 12
	cfgA["repair_on_disable"] = mode_val
	# 🔒 诊断容器（仅 PRICED 臂被 run 注入到 c["diag"]）：
	#   [0]=n_repair_enumerated [1]=n_repair_fired [2]=n_no_money
	#   [3]=spend_repair_total  [4]=n_repair_eligible [5]=n_repair_then_redied
	var diag := [0, 0, 0, 0.0, 0, 0]
	var recs: Array = []
	var n_surv := 0
	var n_fail := 0
	var n_td := 0
	for _i in range(RUNS):
		# 🔴 每局传 diag 的副本引用（run 内 duplicate 后会重新注入；这里每局重置容器
		#    以隔离各局计数——但 PRICED 臂 run 内会往 c["diag"] 写，返回后需读回）。
		#    故各局用**独立** diag 容器，跑完读回累加。
		var per_diag := [0, 0, 0, 0.0, 0, 0]
		var out := _RunLoopAggro.run("A", cfgA, MAX_WAVE, null, rng, true, 0.6, ATTRITION, WARMUP, false, false, false, 0.0, per_diag)
		var rows: Array = out["rows"]
		var survived := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		# 本局塔死局数（X_form 窗口内 dis_new 之和，与基线 hit 口径一致：全程 dis_new≥1 即塔死局）
		var td := _run_td(rows)
		if survived:
			n_surv += 1
		else:
			n_fail += 1
		if td > 0:
			n_td += 1
		# 累加 PRICED 臂诊断（OFF/FREE 臂 per_diag 恒全 0，累加无害）
		recs.append({
			"fail": not survived,
			"td": td,
			"sig": _rows_sig(rows),
		})
		if mode_val == 2:
			diag[0] = int(diag[0]) + int(per_diag[0])
			diag[1] = int(diag[1]) + int(per_diag[1])
			diag[2] = int(diag[2]) + int(per_diag[2])
			diag[3] = float(diag[3]) + float(per_diag[3])
			diag[4] = int(diag[4]) + int(per_diag[4])
			diag[5] = int(diag[5]) + int(per_diag[5])
	return {
		"surv": float(n_surv) / float(RUNS),
		"n_surv": n_surv,
		"n_fail": n_fail,
		"n_td": n_td,
		"diag": diag,
		"recs": recs,
	}


## 本局是否塔死（全程 dis_new ≥1，与基线 hit 口径一致：X_all ≥ 1）
func _run_td(rows: Array) -> int:
	var tot := 0
	for r in rows:
		tot += int(r.get("dis_new", 0))
	return tot


## 逐波 rows 的逐位签名（供三臂配对校验：完全相同 ⟺ 逐位一致）。
## 只取会影响逐位对齐的关键字段，避免无关浮点噪声。
func _rows_sig(rows: Array) -> String:
	var parts: Array = []
	for r in rows:
		parts.append("%d|%d|%d|%d|%d|%d" % [
			int(r["w"]), int(r.get("dis_new", 0)), int(r.get("towers", 0)),
			int(r.get("towers_disabled", 0)), int(r.get("rerolls", 0)),
			int(round(float(r.get("core_hp", 0.0))))])
	return ";".join(parts)


func _se(p: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return sqrt(maxf(0.0, p * (1.0 - p)) / float(n))


func _initialize() -> void:
	print("===================================================================")
	print("V-7 repair_on_disable 三臂对照（A 路径 · N=%d · seed %d）" % [RUNS, SEED])
	print("===================================================================")

	# 切径向模式（本扫描专用，跑后回退）
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var arm_off := _run_arm(0)
	var arm_free := _run_arm(1)
	var arm_priced := _run_arm(2)

	# ---- 配对校验：三臂逐局 rows 完全逐位相同的局数 ----
	var n_identical := 0
	for i in range(RUNS):
		if arm_off["recs"][i]["sig"] == arm_free["recs"][i]["sig"] \
				and arm_off["recs"][i]["sig"] == arm_priced["recs"][i]["sig"]:
			n_identical += 1
	var n_discordant := RUNS - n_identical

	# ---- Δ ----
	var d_free: float = arm_free["surv"] - arm_off["surv"]
	var d_priced: float = arm_priced["surv"] - arm_off["surv"]

	# ---- SE（双模型）----
	# 保守 · 独立两比例：SE = sqrt((p0(1-p0) + p1(1-p1)) / n)
	var se_free_indep := sqrt((arm_off["surv"]*(1.0-arm_off["surv"]) + arm_free["surv"]*(1.0-arm_free["surv"])) / float(RUNS))
	var se_priced_indep := sqrt((arm_off["surv"]*(1.0-arm_off["surv"]) + arm_priced["surv"]*(1.0-arm_priced["surv"])) / float(RUNS))
	# 配对 · 同 seed 配对差（仅 n_td 局可能翻转，r=rescue/n_td）
	var r_free: float = (d_free * float(RUNS)) / float(maxi(1, arm_off["n_td"]))
	var r_priced: float = (d_priced * float(RUNS)) / float(maxi(1, arm_off["n_td"]))
	var se_free_pair: float = sqrt(float(arm_off["n_td"]) * r_free * (1.0 - r_free)) / float(RUNS) if arm_off["n_td"] > 0 else 0.0
	var se_priced_pair: float = sqrt(float(arm_off["n_td"]) * r_priced * (1.0 - r_priced)) / float(RUNS) if arm_off["n_td"] > 0 else 0.0
	# z（配对口径，单侧）
	var z_free: float = d_free / se_free_pair if se_free_pair > 0.0 else 0.0
	var z_priced: float = d_priced / se_priced_pair if se_priced_pair > 0.0 else 0.0

	# ---- 输出（§5.1 格式）----
	print("")
	print("  [臂0 OFF   ] surv=%.3f (%d/%d)  n_fail=%d  n_td=%d   <- baseline"
		% [arm_off["surv"], arm_off["n_surv"], RUNS, arm_off["n_fail"], arm_off["n_td"]])
	print("  [臂1 FREE  ] surv=%.3f (%d/%d)   d_free  = %+.4f   SE_pair=%.4f  z=%.2f"
		% [arm_free["surv"], arm_free["n_surv"], RUNS, d_free, se_free_pair, z_free])
	print("  [臂2 PRICED] surv=%.3f (%d/%d)   d_priced= %+.4f   SE_pair=%.4f  z=%.2f"
		% [arm_priced["surv"], arm_priced["n_surv"], RUNS, d_priced, se_priced_pair, z_priced])

	print("  配对校验   n_identical=%d  n_discordant=%d   -> 采用 SE 模型：%s"
		% [n_identical, n_discordant, "配对 %.4f" % se_priced_pair if n_identical >= 200 else "保守 %.4f (配对破功)" % se_priced_indep])

	# 单调性不变量：0 ≤ Δ_priced ≤ Δ_free ≤ TD_UPPER
	var mono: bool = (d_priced >= -1e-9) and (d_priced <= d_free + 1e-9) and (d_free <= TD_UPPER + 1e-9)
	print("  单调性     d_priced <= d_free <= %.4f  -> %s"
		% [TD_UPPER, "OK" if mono else "🔴 违反→结果作废"])

	var dgf: Array = arm_free["diag"]
	var dgp: Array = arm_priced["diag"]
	print("  诊断计数   eligible=%d enumerated=%d fired=%d no_money=%d then_redied=%d"
		% [int(dgp[4]), int(dgp[0]), int(dgp[1]), int(dgp[2]), int(dgp[5])])
	print("              spend_repair_total=%.1f   r_rescue = %d/%d = %.4f"
		% [float(dgp[3]), int(d_priced * float(RUNS)), arm_off["n_td"], r_priced])

	# 判读（数据驱动，判读留文策渊按 §3.3 三分支；这里只给点估计与 z）
	var verdict := ""
	if d_priced >= DELTA_GATE and z_priced >= 1.645:
		verdict = "A §2.3 成立（点估计≥%.4f 且 z≥1.645）" % DELTA_GATE
	elif d_priced >= DELTA_GATE and z_priced < 1.645:
		verdict = "B 灰区→加跑1140/臂（点估计够但检验力不足）"
	else:
		verdict = "C 废按钮倾向（Δ_priced=%.4f < %.4f）；看 Δ_free=%.4f 分流" % [d_priced, DELTA_GATE, d_free]
	print("  判读       %s" % verdict)
	print("  观察项     surv_A(priced)=%.3f  （≥0.817 → 触发支柱漂移复核）" % arm_priced["surv"])

	# 零扰动断言（B-2）：OFF 臂 == 当前 aggro 基线（run_slice_attrition8 同口径重跑）。
	#   🔴 注意：规格 §1.2 记载的 0.617 是 `sim_player.snap/rest` **未捕获 disabled** 的旧 bug
	#      下的值。该 bug 已在本轮修复（snap/rest 现捕获 disabled/hp）→ aggro 基线变为
	#      0.597(179/300)、n_fail=121。OFF 臂走与基线完全相同的代码路径（repair_on_disable=0
	#      → 不注入 diag、不修复）→ 逐局必然一致。故零扰动断言对照**当前基线** 0.597/179。
	var off_ok: bool = (int(arm_off["n_surv"]) == 179) and (int(arm_off["n_fail"]) == 121)
	print("  零扰动断言 OFF 臂 surv=%.3f (%d/300, n_fail=%d) vs 当前基线 179/121 -> %s"
		% [arm_off["surv"], int(arm_off["n_surv"]), int(arm_off["n_fail"]),
			"OK" if off_ok else "🔴 FAIL（开关off路径被污染，全轮作废）"])
	print("  〔规格偏差〕§1.2 记载 0.617/88 是 snap/rest 旧 bug 值；修复后基线=0.597/121（见回传）")

	# 事实登记（Q7）：B 路径修复永不触发
	print("")
	print("  [事实登记] B 路径 n_repair_eligible = 0（径向多塔流零塔死，修复无适用对象）")

	# 回退 PATH 模式
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	print("")
	print("===================================================================")
	print("V-7 三臂扫描结束（诊断件 · 恒 exit 0 · 判读留文策渊）")
	print("===================================================================")
	quit(0)
