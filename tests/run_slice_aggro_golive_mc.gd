extends SceneTree
##
## headless 实机**全开**口径 MC **口径矩阵**（第五刀 · 仇恨上线门禁 · B 轮 2026-10-10）
##
## 🔴 使命：为「仇恨（tower_aggro）上线」补上**实机全开口径**的 300 局 MC 读数。
##   第五刀初版只跑了 `repair_on_disable=0`（AI **完全不修塔**）= "从不使用修复机制的玩家"
##   → 那是**真实玩家的下界**，不是产品体验（产品的塔死亡路径 = 安全窗三选一修复）。
##   本轮（B-3）补全"玩家会修塔"口径，回答：**玩家修塔时 B 起飞率是多少**。
##
## 口径矩阵（= 实机首次装载口径 · `boot.gd` 窗口分支，spec §2.1）：
##   · `SpaceModel.mode = RADIAL`
##   · `prototype_split_enabled = true`（三原型分化）
##   · `elite_waves_enabled     = true`（Elite 波 · W5/10/15/20 + Sapper）
##   · `tower_aggro_enabled     = true`（机会型仇恨 + 塔 HP + Disabled）
##   · `repair_on_disable ∈ {0 OFF(基线), 1 FREE(上界), 2 PRICED(最接近产品)}`
##   · `warmup_waves = MonsterData.WARMUP = 2`（起手保护：W1/W2 仇恨不激活）
##   · `n_slots = 6`（门禁臂）/ `8`（参考臂，Q-R9 未批准为出货配置）
##   · `cfg = MvpConfig.cfg_of(path)` 实机默认（κ_r = KR_FINAL = 0.050）
##   · 战斗结算 = `RunLoopProtoAggro`（`wave_sim_proto_aggro` 批处理镜像 `WaveDirector._substep`）
##   · rng seed = 20260930（与既有 MC / S5-D1 同 seed，可对拍）
##
## 判据（spec §4.2 + D7-③）：
##   · **主判**：PRICED 臂 B(n_slots=6) 起飞率 ≥ 0.80 ← 口径补全后的门禁
##   · **基线**：OFF 臂 B@6 = 0.683（既有读数，本脚本自检复现 → 零扰动证据）
##   · A 路径只作 INFO（H2 已裁决关闭；单核高风险为设计预期）← **不作门禁**
##   · 每臂输出：起飞率 / 存活率 / 中位起飞波 / 平均结算波 / 核心 HP 分布 / 末波 Disabled 塔数分布
##   · **修复成交次数**（PRICED/FREE 臂 · 确认修复机制确在起作用）
##
## 🔴 破 80% 红线 → **不得上线 / 不得自行上线**，如实上报（本脚本 `exit 1`）；
##    **禁止自行改任何数值 / 下调阈值 / 为过线挑口径**。CI 该步已转**非阻断诊断**（ci.yml B-2）。
## 🔴 本入口**不进**默认 `run_tests.gd` 无参回归（12 臂 × 300 局耗时长）；单列为门禁入口并纳入 CI。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_slice_aggro_golive_mc.gd [runs]
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
const TH_TAKEOFF_B := 0.80   # 🔴 spec §4.2 门禁红线（禁下调）
const WARMUP := 2            # = MonsterData.WARMUP（起手保护）
const N_SLOTS_MAIN := 6      # 实机默认（门禁臂）
const N_SLOTS_ALT := 8       # 八槽径向（参考臂 · Q-R9 未批准为出货配置）
## 基线读数（提交②翻参后 · repair=0 · n_slots=6 · B）—— 用于自检复现（守门一致证据）。
const BASE_B6_N_TAKEOFF := 205   # 起飞 205/300 → 0.683（提交②翻参后 · rng 再分岔 · 非行为改善）
## 口径矩阵：repair_on_disable 三档（标签用于打印）。
const REPAIR_MODES: Array = [0, 1, 2]
const REPAIR_LABELS: Array = ["repair=0 OFF(基线·下界)", "repair=1 FREE(上界)", "repair=2 PRICED(最接近产品)"]

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


## 实机全开 MC（RADIAL + proto + elite + aggro · 指定 repair_on_disable 档位）。
## 就地镜像 `RunLoopProtoAggro` 的 takeoff 定义（alive ∧ takeoff_wave ≥ 0），
## 额外采集「平均结算波次」「末波核心 HP 分布」「末波 Disabled 塔数分布」「修复成交次数」。
func _mc(path: String, n_slots: int, repair_mode: int, runs: int) -> Dictionary:
	var cfg := _Cfg.cfg_of(path)          # 实机默认（κ_r=KR_FINAL=0.050）
	cfg["n_slots"] = n_slots
	cfg["max_actions"] = ACTIONS
	cfg["repair_on_disable"] = repair_mode
	var rng := _PyRandom.new(SEED)         # rng 跨所有 run 连续使用（与 S5-D1 同纪律）
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	var wsum := 0
	var hp_hist: Array = [0, 0, 0, 0, 0, 0]
	var dis_hist: Array = []
	dis_hist.resize(n_slots + 1)
	for i in range(dis_hist.size()):
		dis_hist[i] = 0
	var dis_sum := 0
	var n_repair := 0          # 修复成交次数（跨局求和 · diag[1]）
	var spend_repair := 0.0    # 修复总花费（diag[3]）
	for _i in range(runs):
		var cx: Dictionary = cfg.duplicate(true)
		# 🔴 diag 容器 6 槽（V-7 shape）；repair=0 时 run() 不注入 → 零扰动（守护⑤已钉）。
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
		var w_end := int(rows[-1]["w"]) if not rows.is_empty() else 0
		wsum += w_end
		var hp := float(rows[-1]["core_hp"]) if not rows.is_empty() else 0.0
		hp_hist[_hp_bin(hp)] = int(hp_hist[_hp_bin(hp)]) + 1
		var nd := int(rows[-1].get("towers_disabled", 0)) if not rows.is_empty() else 0
		nd = clampi(nd, 0, n_slots)
		dis_hist[nd] = int(dis_hist[nd]) + 1
		dis_sum += nd
		n_repair += int(per_diag[1])
		spend_repair += float(per_diag[3])
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
		"n": runs,
		"mean_w_end": float(wsum) / float(runs),
		"hp_hist": hp_hist,
		"dis_hist": dis_hist,
		"dis_mean": float(dis_sum) / float(runs),
		"n_repair": n_repair,
		"spend_repair": spend_repair,
	}


func _print_arm(tag: String, r: Dictionary) -> void:
	print("  [%s] 起飞率=%s  存活率=%s  中位起飞波=%s  平均结算波=%.2f  (起飞 %d/%d · 修复成交 %d 次)"
		% [tag, _fmt(float(r["rate"])), _fmt(float(r["surv"])), str(r["med"]),
			float(r["mean_w_end"]), int(r["n_takeoff"]), int(r["n"]), int(r["n_repair"])])
	var h: Array = r["hp_hist"]
	var labels := ["0(失守)", "0<hp<=250", "250<hp<=500", "500<hp<=750", "750<hp<1000", "hp==1000(满)"]
	var parts: Array = []
	for i in range(h.size()):
		parts.append("%s:%d" % [labels[i], int(h[i])])
	print("       核心 HP 分布  %s" % "  ".join(parts))
	var d: Array = r["dis_hist"]
	var dparts: Array = []
	for i in range(d.size()):
		dparts.append("%d塔:%d" % [i, int(d[i])])
	print("       末波 Disabled 塔数分布  %s   均值=%.3f" % ["  ".join(dparts), float(r["dis_mean"])])


## 跑一个 n_slots 下的全矩阵（三 repair 档 × A/B），返回 {repair_mode: {"A":.., "B":..}}。
func _matrix_for(n_slots: int, runs: int) -> Dictionary:
	print("\n---- n_slots=%d %s----" % [n_slots,
		"（实机默认 · 门禁臂）" if n_slots == N_SLOTS_MAIN else "（八槽径向 · 参考臂 · Q-R9 未批准为出货配置）"])
	var res: Dictionary = {}
	for ri in range(REPAIR_MODES.size()):
		var mode := int(REPAIR_MODES[ri])
		var a := _mc("A", n_slots, mode, runs)
		var b := _mc("B", n_slots, mode, runs)
		res[mode] = {"A": a, "B": b}
		_print_arm("%s · A 单核" % String(REPAIR_LABELS[ri]), a)
		_print_arm("%s · B 多塔" % String(REPAIR_LABELS[ri]), b)
	return res


func _initialize() -> void:
	var runs := 300
	var user_args: Array = OS.get_cmdline_user_args()
	if user_args.size() > 0:
		runs = int(user_args[0])

	print("")
	print("===============================================================")
	print("  实机全开 MC · 口径矩阵（第五刀 · B 轮 2026-10-10）")
	print("  RADIAL + 三原型 + Elite + 仇恨（proto/elite/aggro 全 ON）")
	print("  repair_on_disable ∈ {0 OFF(基线·下界), 1 FREE(上界), 2 PRICED(最接近产品)}")
	print("  每臂 %d 局 · seed=%d · κ_r=KR_FINAL=%.3f · W_MAX=%d · actions=%d · warmup=%d"
		% [runs, SEED, float(_Cfg.KR_FINAL), W_MAX, ACTIONS, WARMUP])
	print("  (spec §4.2 主判：PRICED 多塔 B 起飞率 ≥ %.2f【n_slots=6】；A 只作 INFO)" % TH_TAKEOFF_B)
	print("  (ATTRITION=%.2f · 起手保护 W1–%d · shop_ai 修复候选 pricing = ceil(0.30×(12h+9L)))"
		% [float(_MonsterData.ATTRITION), WARMUP])
	print("===============================================================")

	var prev_mode = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var m6 := _matrix_for(N_SLOTS_MAIN, runs)
	var m8 := _matrix_for(N_SLOTS_ALT, runs)

	_SpaceModel.mode = prev_mode   # 🔴 回退防污染（全局开关）

	print("")
	print("===============================================================")
	print("  门禁判定（spec §4.2 + D7-③ · 主判 = 口径补全后 PRICED 多塔 B 起飞率 ≥ %.2f · n_slots=%d）"
		% [TH_TAKEOFF_B, N_SLOTS_MAIN])
	print("===============================================================")
	# ---- 口径矩阵 B@6 对比（主判口径）----
	print("  B@%d 跨 repair 档位：" % N_SLOTS_MAIN)
	for ri in range(REPAIR_MODES.size()):
		var mode := int(REPAIR_MODES[ri])
		var b6: Dictionary = m6[mode]["B"]
		print("    %-32s B@%d = %s  (起飞 %d/%d · 存活 %d/%d)"
			% [String(REPAIR_LABELS[ri]), N_SLOTS_MAIN, _fmt(float(b6["rate"])),
				int(b6["n_takeoff"]), int(b6["n"]), int(b6["n_surv"]), int(b6["n"])])

	# ---- 自检：OFF 臂 B@6 必须复现既有基线 0.683（零扰动证据）----
	var off_b6: Dictionary = m6[0]["B"]
	var off_takeoff := int(off_b6["n_takeoff"])
	if off_takeoff == BASE_B6_N_TAKEOFF:
		print("  [自检] OFF B@%d 复现基线 %d/%d=0.683 ✅（repair 接线零扰动）"
			% [N_SLOTS_MAIN, off_takeoff, int(off_b6["n"])])
	else:
		print("  [自检] 🔴 OFF B@%d = %d/%d（期望基线 %d/300=0.683）→ 偏差 = 红旗（0 档被污染？）"
			% [N_SLOTS_MAIN, off_takeoff, int(off_b6["n"]), BASE_B6_N_TAKEOFF])
		_fail += 1

	# ---- 主判：PRICED B@6 ≥ 0.80 ----
	var priced_rate := float(m6[2]["B"]["rate"])
	if priced_rate >= TH_TAKEOFF_B:
		print("  [PASS] 主判 · PRICED B@%d 起飞率 %s ≥ %.2f  → 口径补全后达标（🔴 不得自行上线，待主理人呈请用户）"
			% [N_SLOTS_MAIN, _fmt(priced_rate), TH_TAKEOFF_B])
	else:
		print("  [FAIL] 主判 · PRICED B@%d 起飞率 %s < %.2f  🔴 仍破线 → 真实平衡问题（非口径伪影），如实上报，禁止自行改数值"
			% [N_SLOTS_MAIN, _fmt(priced_rate), TH_TAKEOFF_B])
		_fail += 1
	print("  [INFO] FREE   B@%d = %s ／ OFF B@%d = %s（口径上/下界）"
		% [N_SLOTS_MAIN, _fmt(float(m6[1]["B"]["rate"])), N_SLOTS_MAIN, _fmt(float(m6[0]["B"]["rate"]))])
	print("  [INFO] PRICED B@%d = %s ／ A@%d = %s（八槽参考臂）"
		% [N_SLOTS_ALT, _fmt(float(m8[2]["B"]["rate"])), N_SLOTS_ALT, _fmt(float(m8[2]["A"]["rate"]))])
	print("===============================================================")
	quit(0 if _fail == 0 else 1)
