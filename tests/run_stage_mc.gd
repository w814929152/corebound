extends SceneTree
##
## headless 实测 · v2 十关难度曲线（MC）
##
## 🔴 使命：`design/gdd/stage-waves.md` 里所有难度与通过率此前都是 `[PLACEHOLDER]`。
##   本脚本用**实机口径的批处理镜像**逐关扫，把那张空表填上读数。
##
## 口径（三臂 · 见下「为什么分三张表」）：
##   · `SpaceModel.mode = RADIAL`（三臂共同）
##   · proto / elite 全 ON（三臂共同，`boot.gd:110-111`）
##   · `warmup_waves = MonsterData.WARMUP`（起手保护；🔴 真身字段默认就是它，
##      镜像侧必须显式对齐，否则 W1/W2 的仇恨一边开一边不开 → 读数失真）
##   · `attrition_override = -1.0`（走 `MonsterData.resolve_attrition` 默认）
##   · `n_slots = 6` · `cfg = MvpConfig.cfg_of("B")` · `actions = 12`
##   · 波数 = **波表长度**（`RunLoopProtoAggro.run(stage_id=...)` 接管 `max_wave`）
##   · `S` = `CampaignData.min_regions_on_arrival(stage)` —— **首次抵达**的静态已守数
##     （0-1/三外环 0、四中环 1、8-1 = 5、9-1 = 7）。用静态值而非当前存档值，
##     否则同一张表在不同进度下读数不同，无法对拍。
##
## 🔴 每关**重建同一个 seed 的 rng**：十关面对同一串发牌随机流 →
##   「这关更难」只能归因于波表与地图，不能归因于随机数漂移。
##
## 🔴 本入口**不进**默认 `run_tests.gd`（10 关 × N 局耗时长）；它是**读数工具**，不是门禁。
##   判定门槛（通过率该是多少）尚未拍板 → 本脚本恒返回 0，只打印。
##
## 跑法：
##   <godot> --headless --path . --script res://tests/run_stage_mc.gd [runs] [arm]
##     runs 默认 100；arm = b（多塔 · 默认）| a（单核）| both
##
## 🔴 为什么分三张表（门禁 / 仅仇恨 / 产品实机）：
##   ① **门禁口径**（aggro OFF）＝ 既有 S5-D1 校准闸门（`run_slice_proto_elite_mc.gd`，
##      B 起飞率 ≥ 80%）同口径 → 可与那条红线直接对拍，差异只来自波表。
##   ② **仅仇恨**（aggro ON，复活关）＝ 「塔被打停就永远停着」的下界，用来单独量
##      仇恨通道本身值多少个百分点。
##   ③ **产品实机**（aggro ON + 战斗内复活 + 战斗类型）＝ `boot.gd:110-118` 的**实际六个
##      开关**。这才是玩家真会遇到的口径，也是唯一可以拿来给十关定难度的口径。
##   ④ **同长度对照**（表 4）＝ 同一波数、**波型全中性**（`StageWaves.force_neutral`）。
##      用途：十关波数 10–19 不同，跟 20 波基准比是**跨长度**比较。把长度固定住，
##      「实机 − 对照」才是**纯形状效应**（正 = 这套波型比平铺更软，负 = 更硬）。
##   🔴 上一轮把 ② 当成实机口径，得出「基准仅 47%」并据此怀疑波表 —— 那是**漏了两个开关**
##      的错。真身的产品复活走 `combat_revive_enabled`（`_revive_mode()` 视同档 9），
##      不是诊断枚举 1/2；镜像侧无此 bool，故用 `cfg.repair_on_disable = 9` 等价表达
##      （🔴 这是镜像对齐，不是把诊断开关当产品开关用）。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _RunLoopPA := preload("res://scripts/engine/run_loop_proto_aggro.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")
const _StageWaves := preload("res://scripts/data/stage_waves.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")

const SEED := 20260930
const ACTIONS := 12
const N_SLOTS := 6
const EXP := 0.6
const ATTRITION := -1.0
const WARMUP := _MonsterData.WARMUP
const W_GOLD := 20        # 基准臂（无波表 · 20 波金标本）

# 三个口径臂（见文件头「为什么分三张表」）
const MODE_GATE := "g"    # 门禁：aggro OFF（= S5-D1 校准闸门口径）
const MODE_AGGRO := "a"   # 仅仇恨：aggro ON，复活/战斗类型全 OFF（下界）
const MODE_PROD := "p"    # 产品实机：aggro ON + 复活档 9 + 战斗类型 ON（= boot.gd）


func _initialize() -> void:
	var runs := 100
	var arm := "b"
	var ua: Array = OS.get_cmdline_user_args()
	if ua.size() > 0:
		runs = int(ua[0])
	if ua.size() > 1:
		arm = String(ua[1])

	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var cfg0: Dictionary = _Cfg.cfg_of("B")

	print("")
	print("=".repeat(96))
	print("  v2 十关难度曲线 · MC 实测（RADIAL · proto/elite ON · 每关 %d 局 · seed=%d）"
		% [runs, SEED])
	print("  口径：n_slots=%d · actions=%d · warmup=%d · attrition=%.1f（默认） · 波数=波表长度"
		% [N_SLOTS, ACTIONS, WARMUP, ATTRITION])
	print("=".repeat(96))

	# ---- 表 1 · 门禁口径（aggro OFF，可与 S5-D1 的 B 起飞率 ≥80% 直接对拍）----
	print("\n【表 1 · 门禁口径】aggro OFF —— 与既有 S5-D1 校准闸门同口径，差异只来自波表")
	var gold1 := _mc(cfg0, runs, "B", "", 0, W_GOLD, MODE_GATE)
	_print_row("基准 20 波（无波表）", "-", 0, W_GOLD, 1.0, gold1)
	_table(cfg0, runs, arm, MODE_GATE)

	# ---- 表 2 · 仅仇恨（复活关）＝ 下界，单独量仇恨通道的代价 ----
	print("\n【表 2 · 仅仇恨】aggro ON · 复活 OFF —— 「塔被打停就永远停着」的下界")
	var gold2 := _mc(cfg0, runs, "B", "", 0, W_GOLD, MODE_AGGRO)
	_print_row("基准 20 波（无波表）", "-", 0, W_GOLD, 1.0, gold2)
	_table(cfg0, runs, arm, MODE_AGGRO)

	# ---- 表 3 · 产品实机（= boot.gd 的六个开关）----
	print("\n【表 3 · 产品实机】aggro + 战斗内复活(档9) + 战斗类型 —— `boot.gd:110-118` 实际口径")
	print("  🔴 只有这张表能用来给十关定难度（玩家真遇到的是它）")
	var gold3 := _mc(cfg0, runs, "B", "", 0, W_GOLD, MODE_PROD)
	_print_row("基准 20 波（无波表）", "-", 0, W_GOLD, 1.0, gold3)
	_table(cfg0, runs, arm, MODE_PROD)

	# ---- 表 4 · 同长度对照臂（= 该关波数 × 全中性波）----
	#   🔴 十关波数 10–19 不同，直接跟 20 波基准比是**跨长度比较**（波少 = 血少 = 该好过）。
	#      本臂把「长度」与「形状」拆开：同一个波数、同一套产品开关，只把波型全换成中性。
	#      形状效应 = 产品实机 − 对照 → 正数 = 这关的波型比"平铺的同量怪"更**好过**。
	print("\n【表 4 · 形状效应】同长度中性对照 —— 拆掉「长度」这个混入变量")
	print("  🔴 形状效应 = 表 3（实机）− 表 4（对照）。>0 = 波型让它更软，<0 = 波型让它更硬")
	_table_control(cfg0, runs, arm)

	print("\n" + "-".repeat(96))
	print("  通关率 = 末波核心 HP > 0 的比例（打完该关全部波次）")
	print("  平均残血 = 末波核心 HP ÷ 满血（含失守局的 0）")
	print("  起飞率   = 通关 ∧ Stats.takeoff_wave ≥ 0（ratio 首次越过起飞阈）")
	print("  均结算波 = 平均实际跑了多少波（< 波数 = 有局中途失守）")
	print("  S = `CampaignData.min_regions_on_arrival`（首次抵达的静态已守数）")
	print("=".repeat(96))
	quit(0)


func _table(cfg0: Dictionary, runs: int, arm: String, mode: String) -> void:
	print("")
	print("  %-6s %-4s %-3s %-4s %-4s %-8s %-9s %-8s %-9s"
		% ["关卡", "章", "波", "S", "k", "通关率", "平均残血", "起飞率", "均结算波"])
	print("  " + "-".repeat(92))
	if arm == "a" or arm == "both":
		for sid in _StageWaves.STAGE_ORDER:
			_emit(cfg0, runs, "a", sid, mode)
	if arm != "a":
		for sid in _StageWaves.STAGE_ORDER:
			_emit(cfg0, runs, "b", sid, mode)


## 表 4 · 同长度对照臂（波数不变、波型全中性）。只跑产品口径（那是唯一可定难度的口径）。
##   🔴 `force_neutral` 是全局静态 → 必须**成对置位/复位**，否则后面的臂全被污染。
func _table_control(cfg0: Dictionary, runs: int, arm: String) -> void:
	print("")
	print("  %-6s %-3s %-4s %-9s %-9s %-9s"
		% ["关卡", "波", "S", "实机(表3)", "对照(中性)", "形状效应"])
	print("  " + "-".repeat(92))
	var used: Array = ["a"] if arm == "a" else ["b"]
	for a in used:
		for sid in _StageWaves.STAGE_ORDER:
			var wc := _StageWaves.wave_count(sid)
			var S := _CampaignData.min_regions_on_arrival(sid)
			var path := String(a).to_upper()
			var prod := _mc(cfg0, runs, path, sid, S, wc, MODE_PROD)
			_StageWaves.force_neutral = true
			var ctl := _mc(cfg0, runs, path, sid, S, wc, MODE_PROD)
			_StageWaves.force_neutral = false
			var p_rate := float(prod["surv"]) * 100.0
			var c_rate := float(ctl["surv"]) * 100.0
			var d := p_rate - c_rate
			print("  %-6s %-3d %-4d %-9s %-9s %-9s"
				% [sid + "(" + path + ")", wc, S,
					"%.0f%%" % p_rate, "%.0f%%" % c_rate,
					("%+.0f pt" % d) + (" 软" if d > 4.0 else (" 硬" if d < -4.0 else " ≈"))])


func _emit(cfg0: Dictionary, runs: int, arm: String, sid: String, mode: String) -> void:
	var wc := _StageWaves.wave_count(sid)
	var S := _CampaignData.min_regions_on_arrival(sid)
	var ch := int((_CampaignData.STAGES[sid] as Dictionary)["chapter"])
	# 🔴 臂名（a/b）与构筑路径（"A"/"B"）是两回事：`path_coverage` 的键是大写。
	var path := arm.to_upper()
	var r := _mc(cfg0, runs, path, sid, S, wc, mode)
	var ratio := _total_hp_ratio(sid, S, wc, cfg0)
	var tag := sid + ("(A)" if arm == "a" else "(B)")
	_print_row(tag, "第%d" % ch, S, wc, ratio, r)


## 一行读数。
func _print_row(tag: String, chapter: String, S: int, wc: int, ratio: float, r: Dictionary) -> void:
	print("  %-6s %-4s %-3d %-4d %-4d %-8s %-9s %-8s %-9s"
		% [tag, chapter, wc, S, _StageWaves.escalation_k(S),
			"%.0f%%" % (float(r["surv"]) * 100.0),
			"%.0f%%" % (float(r["hp_mean"]) * 100.0),
			"%.0f%%" % (float(r["rate"]) * 100.0),
			"%.2f" % float(r["mean_w_end"])])
	print("        ↳ 总血 %.3f× 基准 · 均结算波 %.2f/%d · 中位起飞波 %s · 核心HP %s"
		% [ratio, float(r["mean_w_end"]), wc, str(r["med"]), _hist_str(r["hp_hist"])])


func _hist_str(h: Array) -> String:
	var labels := ["失守", "<25%", "<50%", "<75%", "<100%", "满血"]
	var parts: Array = []
	for i in range(h.size()):
		if int(h[i]) > 0:
			parts.append("%s:%d" % [labels[i], int(h[i])])
	return " ".join(parts) if not parts.is_empty() else "-"


## 整关总血量（波表 Σ n×hp）÷ 基准（Σ monster_stats 的 n×hp）。
##   🔴 这是守恒律的现场读数：十关都必须 ≈ 1.00，否则「变难」就混进了「血变多」。
func _total_hp_ratio(sid: String, S: int, wc: int, cfg: Dictionary) -> float:
	if sid == "":
		return 1.0
	var tot_base := 0.0
	var tot_act := 0.0
	for w in range(1, wc + 1):
		var ms := _WaveSim.monster_stats(w, cfg)
		tot_base += float(int(ms["n"])) * float(ms["hp"])
		var sp: Dictionary = _StageWaves.wave_spec(sid, w, cfg, S)
		if sp.is_empty() or bool(sp.get("neutral", false)):
			tot_act += float(int(ms["n"])) * float(ms["hp"])
		else:
			tot_act += float(sp["n"]) * float(sp["hp"])
	if tot_base <= 0.0:
		return 0.0
	return tot_act / tot_base


## 单臂 MC。🔴 每关重建同一 seed 的 rng（见文件头）。
##   mode：MODE_GATE / MODE_AGGRO / MODE_PROD（见文件头「为什么分三张表」）
func _mc(cfg0: Dictionary, runs: int, path: String, sid: String, S: int, wc: int,
		mode: String) -> Dictionary:
	var rng := _PyRandom.new(SEED)
	var aggro := mode != MODE_GATE
	var takeoffs := 0
	var survives := 0
	var hits: Array = []
	var wsum := 0
	var hpsum := 0.0
	var hp_hist: Array = [0, 0, 0, 0, 0, 0]
	var core_max := 1.0
	for _i in range(runs):
		var cx: Dictionary = cfg0.duplicate(true)
		cx["n_slots"] = N_SLOTS
		cx["max_actions"] = ACTIONS
		# ---- 产品实机臂的两个额外开关 ----
		#   ① 战斗内复活：真身走 `wave_director.combat_revive_enabled`（`_revive_mode()`
		#      视同档 9）。镜像无此 bool → 用 cfg 的档 9 等价表达（N=0.5s / K=1）。
		#   ② 战斗类型：`combat_types_enabled` 在 `wave_sim.monster_stats` / `damage_engine`
		#      内被消费；🔴 不改 n / hp，只改伤害分池 → 守恒律不受影响。
		if mode == MODE_PROD:
			cx["repair_on_disable"] = 9
			cx["combat_types_enabled"] = true
		core_max = float(cx["core_hp"])
		var out := _RunLoopPA.run(path, cx, wc, null, rng,
			true, true, aggro, EXP, ATTRITION, WARMUP, false, false, [], sid, S)
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
		hpsum += hp / maxf(1.0, core_max)
		var b := _hp_bin(hp, core_max)
		hp_hist[b] = int(hp_hist[b]) + 1
	return {
		"rate": float(takeoffs) / float(runs),
		"surv": float(survives) / float(runs),
		"med": _Stats._median(hits),
		"n_takeoff": takeoffs,
		"n_surv": survives,
		"n": runs,
		"mean_w_end": float(wsum) / float(runs),
		"hp_mean": hpsum / float(runs),
		"hp_hist": hp_hist,
	}


## 核心 HP 分箱（末波）：0 = 失守；5 = 满血。
func _hp_bin(hp: float, core_max: float) -> int:
	if hp <= 0.0:
		return 0
	var q := hp / maxf(1.0, core_max)
	if q < 0.25:
		return 1
	if q < 0.5:
		return 2
	if q < 0.75:
		return 3
	if q < 1.0:
		return 4
	return 5
