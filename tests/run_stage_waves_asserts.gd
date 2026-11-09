extends SceneTree
##
## headless 断言 —— 关卡波表（`scripts/data/stage_waves.gd` + `WaveDirector` 接线）
##
## 背景：`design/gdd/stage-waves.md`（10 关 149 波逐波表）。本套件把那套设计里
##   **可以被代码证伪的部分**钉成断言 —— 不是测"好不好玩"，是测"有没有算错"：
##
##   SW0 数据完整性：10 关 / 波型串与设计波数闭合 / 合计 149 波 / 0-1 全中性
##   SW1 五条 validate() 断言（V-1..V-5）必须全过
##   SW2 守恒律：每关 Σ(n×hp) ≡ Σ基准(n×hp)（1e-9），单波偏离 ≤ 25%
##   SW3 `S` 加压：只把最早的 k 个「试探」升级为「潮涌」，**不改波数、不改总量**
##   SW4 精英：沿用 `MonsterData` 那条式子（0-1 的 W10 必须 = 2 只，不是 3）
##   SW5 三原型：基准构成**短路**回原值（1 ULP 差都不许有）；非基准构成归一化守恒
##   SW6 导演接线：开关默认关（逐位惰性）/ 打开后覆盖生效 / **0-1 锚点不被覆盖**
##   SW7 批处理镜像 ↔ 真身：`wave_sim_proto_aggro` 与 `WaveDirector` 在**有波表时**逐位等价
##       （MC 定难度用的就是镜像 —— 这条不绿，所有通过率读数都不可信）
##
## 跑法（`extends SceneTree`，两种入口等价）：
##   <godot> --headless --path . --script res://tests/run_stage_waves_asserts.gd
##   <godot> --headless --path . --script res://tests/run_tests.gd           # 聚合入口
##
## ⚠️ Godot 坑（沿用 test_suite.gd 头注）：
##   G6 headless 无 global_script_class_cache → 一律 preload，返回值不加类型标注；
##   G1 int/int 整数除法 → 浮点除法两侧显式 float()。
##

const _StageWaves := preload("res://scripts/data/stage_waves.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _WaveSimProtoAggro := preload("res://scripts/engine/wave_sim_proto_aggro.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

var _pass := 0
var _fail := 0
var _cfg: Dictionary = {}
## 对拍用的「打不烂的核心」：真身 / 镜像两侧同值 → 单波失败不影响读数可比性。
const BIG_CORE := 1000000.0


func _initialize() -> void:
	quit(0 if run_all() else 1)


func run_all() -> bool:
	_cfg = _MvpConfig.cfg_of("B")
	_log("")
	_log("=".repeat(78))
	_log("关卡波表（stage_waves：波型串 / 守恒律 / S 加压 / 精英 / 三原型 / 导演接线）")
	_log("基准：design/gdd/stage-waves.md v1（10 关 149 波 · 整关总血量守恒）")
	_log("=".repeat(78))

	_test_data_integrity()
	_test_validate()
	_test_conservation()
	_test_escalation()
	_test_elite()
	_test_proto_mult()
	_test_director()
	_test_mirror()

	_log("")
	_log("-".repeat(78))
	_log("关卡波表：PASS=%d  FAIL=%d" % [_pass, _fail])
	return _fail == 0


# ---------------------------------------------------------------------------
#  [0] 数据完整性
# ---------------------------------------------------------------------------
func _test_data_integrity() -> void:
	_log("")
	_log("--- [0] 数据完整性 ---")
	_check_int("关卡数 = 10", _StageWaves.STAGE_ORDER.size(), 10)
	_check("PATTERN 与 STAGE_ORDER 一一对应", _keys_match(_StageWaves.STAGE_ORDER, _StageWaves.PATTERN))
	_check("WAVES 与 STAGE_ORDER 一一对应", _keys_match(_StageWaves.STAGE_ORDER, _StageWaves.WAVES))

	var total := 0
	for sid in _StageWaves.STAGE_ORDER:
		total += _StageWaves.wave_count(String(sid))
	_check_int("十关合计 = 149 波", total, 149)

	_check("0-1 全中性（只有 n / E）", _StageWaves.is_neutral_stage("0-1"))
	_check("1-1 非中性", not _StageWaves.is_neutral_stage("1-1"))
	_check("未知关卡无波表", not _StageWaves.has_stage("9-9"))
	_check_int("未知关卡波数 = 0", _StageWaves.wave_count("9-9"), 0)


func _keys_match(order: Array, table: Dictionary) -> bool:
	if order.size() != table.size():
		return false
	for k in order:
		if not table.has(k):
			return false
	return true


# ---------------------------------------------------------------------------
#  [1] validate()：V-1..V-5
# ---------------------------------------------------------------------------
func _test_validate() -> void:
	_log("")
	_log("--- [1] validate() 五条断言 ---")
	var errs: Array = _StageWaves.validate(_cfg)
	if not errs.is_empty():
		for e in errs:
			_log("   [ERR] %s" % String(e))
	_check("V-1..V-5 全部通过（错误列表为空）", errs.is_empty())

	# 锚点：0-1 每一波都必须 neutral（V-5 的语义，不依赖 validate 实现）
	var all_neutral := true
	for i in _StageWaves.wave_count("0-1"):
		var sp: Dictionary = _StageWaves.wave_spec("0-1", i + 1, _cfg, 0)
		if not bool(sp.get("neutral", false)):
			all_neutral = false
	_check("0-1 的每一波 wave_spec 都是 neutral", all_neutral)

	# 越界 → {}
	_check("w=0 越界返回 {}", _StageWaves.wave_spec("1-1", 0, _cfg, 0).is_empty())
	_check("w=13 超 1-1 长度返回 {}", _StageWaves.wave_spec("1-1", 13, _cfg, 0).is_empty())


# ---------------------------------------------------------------------------
#  [2] 守恒律
# ---------------------------------------------------------------------------
func _test_conservation() -> void:
	_log("")
	_log("--- [2] 整关总血量守恒（单波 ±25% 峰谷 · 关内 1e-9）---")
	for sid in _StageWaves.STAGE_ORDER:
		var s := String(sid)
		var w := _StageWaves.wave_count(s)
		var tot_base := 0.0
		var tot_act := 0.0
		var worst := 0.0
		for i in w:
			var ms := _WaveSim.monster_stats(i + 1, _cfg)
			var base := float(int(ms["n"])) * float(ms["hp"])
			tot_base += base
			var sp: Dictionary = _StageWaves.wave_spec(s, i + 1, _cfg, 0)
			if bool(sp.get("neutral", false)):
				tot_act += base
				continue
			var act := float(sp["n"]) * float(sp["hp"])
			tot_act += act
			worst = maxf(worst, absf(act / base - 1.0))
		var rel := 0.0 if tot_base <= 0.0 else absf(tot_act / tot_base - 1.0)
		_check("守恒 %s：总血偏差 %s（须 ≤1e-9）· 单波峰值 %.1f%%（须 ≤25%%）" % [s, str(rel), worst * 100.0],
			rel <= 1e-9 and worst <= 0.25)


# ---------------------------------------------------------------------------
#  [3] S 加压：换形状，不换长度
# ---------------------------------------------------------------------------
func _test_escalation() -> void:
	_log("")
	_log("--- [3] S 加压（试探→潮涌，不加波数）---")
	_check_int("S=0 → k=0", _StageWaves.escalation_k(0), 0)
	_check_int("S=2 → k=0", _StageWaves.escalation_k(2), 0)
	_check_int("S=3 → k=1", _StageWaves.escalation_k(3), 1)
	_check_int("S=6 → k=2", _StageWaves.escalation_k(6), 2)
	_check_int("S=7 → k=2", _StageWaves.escalation_k(7), 2)
	_check_int("S=-5 → k=0（负数夹住）", _StageWaves.escalation_k(-5), 0)

	# 2-1 的波型串有两个 p（v2 重排后 = W1 / W2）→ k=1 只升 W1，k=2 才升到 W2
	#   🔴 断言的是**性质**（只升最早的 k 个），不是"W7"这个具体位置 ——
	#     位置随波表重排会变，性质不会。换 PATTERN 时只改这两行取址即可。
	_check("2-1 W1 原为试探", _StageWaves.code_at("2-1", 1) == "p")
	_check("2-1 W2 原为试探", _StageWaves.code_at("2-1", 2) == "p")
	_check("k=1：W1 升为潮涌", _StageWaves.upgraded_code("2-1", 1, 3) == "s")
	_check("k=1：W2 仍是试探（只升最早的）", _StageWaves.upgraded_code("2-1", 2, 3) == "p")
	_check("k=2：W2 也升为潮涌", _StageWaves.upgraded_code("2-1", 2, 6) == "s")
	_check("非试探波不受加压影响（W8 铁壁）", _StageWaves.upgraded_code("2-1", 8, 99) == "b")

	# 加压不改波数（这是与"加波数"那条错路的根本区别）
	_check_int("加压后 2-1 波数仍 12", _StageWaves.wave_count("2-1"), 12)

	# 加压不改整关总量（潮涌只换形状：n↑ 但 hp 按 target/n 反解）
	var tot_base := 0.0
	var tot_esc := 0.0
	for i in _StageWaves.wave_count("2-1"):
		var ms := _WaveSim.monster_stats(i + 1, _cfg)
		tot_base += float(int(ms["n"])) * float(ms["hp"])
		var sp: Dictionary = _StageWaves.wave_spec("2-1", i + 1, _cfg, 6)
		tot_esc += float(sp["n"]) * float(sp["hp"])
	_check("S=6 加压后 2-1 总血仍守恒",
		absf(tot_esc / tot_base - 1.0) <= 1e-9)

	# 潮涌 = 更多只数 = 更多废料（加压与加收益同源，这是信号 C 的机制解）
	var w1_p: Dictionary = _StageWaves.wave_spec("2-1", 1, _cfg, 0)
	var w1_s: Dictionary = _StageWaves.wave_spec("2-1", 1, _cfg, 3)
	_check("W1 升级后只数变多", int(w1_s["n"]) > int(w1_p["n"]))
	var spk := float(_WaveSim.monster_stats(1, _cfg)["scrap_per_kill"])
	_check("W1 升级后废料产出变多",
		float(int(w1_s["n"])) * spk > float(int(w1_p["n"])) * spk)


# ---------------------------------------------------------------------------
#  [4] 精英只数
# ---------------------------------------------------------------------------
func _test_elite() -> void:
	_log("")
	_log("--- [4] 精英只数（必须沿用 MonsterData 那条式子）---")
	# 0-1 的锚点：W10 n=24 → MonsterData 给 2 只。曾经的错解 2+floor((w-1)/7) 会给 3 只。
	var n10 := int(_WaveSim.monster_stats(10, _cfg)["n"])
	_check_int("0-1 W10 n = 24", n10, 24)
	_check_int("MonsterData.elite_count(10,24) = 2", _MonsterData.elite_count(10, 24), 2)
	_check_int("StageWaves.elite_for('E',24) = 2（与 MonsterData 同解）",
		_StageWaves.elite_for("E", 24, 0), 2)
	_check_int("处刑波 S=0 不加只数", _StageWaves.elite_for("e", 24, 0), 2)
	_check_int("处刑波 S=3 加 1 只", _StageWaves.elite_for("e", 24, 3), 3)
	_check("处刑波 S=99 不超过 floor(n/4)", _StageWaves.elite_for("e", 24, 99) <= 6)
	_check_int("非处刑波恒 0 精英", _StageWaves.elite_for("s", 40, 99), 0)

	# 守恒：加精英不破总血量（elite_conserve 对任意 n_e 都保 n_e·2.5 + (n−n_e)·c ≡ n）
	for ne in [0, 2, 3, 6]:
		var c := _MonsterData.elite_conserve(24, ne)
		var total := float(ne) * _MonsterData.ELITE_HP_MULT + float(24 - ne) * c
		_check_close("elite_conserve(24,%d) 保总血量" % ne, total, 24.0, 1e-9)
	# 上限的来源：n_e ≥ n/2.5 = 9.6 时 c 变负
	_check("n_e = 10 时 c 已为负（故上限取 floor(n/4)=6，远离 9.6）",
		_MonsterData.elite_conserve(24, 10) < 0.0)
	_check("n_e = 6 时 c 仍为正", _MonsterData.elite_conserve(24, 6) > 0.0)


# ---------------------------------------------------------------------------
#  [5] 三原型乘数
# ---------------------------------------------------------------------------
func _test_proto_mult() -> void:
	_log("")
	_log("--- [5] 三原型（基准构成短路 / 非基准归一化）---")
	var base_comp := {"R": 0.40, "S": 0.40, "T": 0.20}
	var pm: Dictionary = _StageWaves.proto_mult(base_comp)
	# 🔴 逐位相等（不是近似）：浮点下 0.4*0.6+0.4*0.4+0.2*3.0 = 1.0000000000000002，
	#    除下来会得 0.5999999999999999 —— 1 ULP 就够毁掉与 MonsterData 的逐位等价。
	_check("基准构成：Tank m_hp 逐位 = MonsterData",
		float(pm["hp"]["Tank"]) == float(_MonsterData.M_HP["Tank"]))
	_check("基准构成：Rush m_hp 逐位 = MonsterData",
		float(pm["hp"]["Rush"]) == float(_MonsterData.M_HP["Rush"]))
	_check("基准构成：Swarm m_spd 逐位 = MonsterData",
		float(pm["spd"]["Swarm"]) == float(_MonsterData.M_SPD["Swarm"]))

	# 非基准构成：C-1 总 HP 守恒（Σ p·m_hp ≡ 1）与 C-3 在场时间守恒（Σ p/m_spd ≡ 1）
	#   🔴 注意口径：`m_hp` 是**乘在 `HP_unit(w)` 上的那个乘数**（不是再乘一次 M_HP）。
	#      写成 Σ p·M_HP·m_hp 会多乘一层基数 —— 那是测试自身的错，不是数据的错。
	for code in ["s", "b", "t"]:
		var comp: Dictionary = _StageWaves.ARCH[code]["comp"]
		var m: Dictionary = _StageWaves.proto_mult(comp)
		var hp_sum := 0.0
		var spd_sum := 0.0
		for short in comp:
			var p := String(_StageWaves.PROTO_OF[short])
			hp_sum += float(comp[short]) * float(m["hp"][p])
			spd_sum += float(comp[short]) / float(m["spd"][p])
		_check_close("%s 型：C-1 总 HP 守恒" % code, hp_sum, 1.0, 1e-12)
		_check_close("%s 型：C-3 在场时间守恒" % code, spd_sum, 1.0, 1e-12)

	# 出生序列：基准构成委托 MonsterData（逐位一致）；非基准构成只数恒等
	var seq_base: Array = _StageWaves.spawn_sequence(20, base_comp)
	_check("基准构成出生序列逐位 = MonsterData", seq_base == _MonsterData.spawn_sequence(20))
	for code in ["s", "b", "t"]:
		var comp2: Dictionary = _StageWaves.ARCH[code]["comp"]
		var seq: Array = _StageWaves.spawn_sequence(20, comp2)
		var cnt := {"Rush": 0, "Swarm": 0, "Tank": 0}
		for p in seq:
			cnt[String(p)] = int(cnt[String(p)]) + 1
		_check_int("%s 型：序列长度 = 20" % code, seq.size(), 20)
		_check_int("%s 型：三原型计数和 = 20" % code,
			int(cnt["Rush"]) + int(cnt["Swarm"]) + int(cnt["Tank"]), 20)
		var want: Dictionary = _StageWaves.composition_counts(20, comp2)
		_check("%s 型：构成取整一致" % code,
			int(cnt["Rush"]) == int(want["Rush"]) and int(cnt["Tank"]) == int(want["Tank"]))


# ---------------------------------------------------------------------------
#  [6] 导演接线：默认惰性 / 打开生效 / 锚点不被覆盖
# ---------------------------------------------------------------------------
func _test_director() -> void:
	_log("")
	_log("--- [6] 导演接线（wave_director）---")
	var geo = _Geo6.build()
	var player = _SimPlayer.new_player("B", _cfg, geo)

	# ① 开关默认关 → 完全惰性（金标本路径）
	var wd = _WaveDirector.new()
	wd.setup(player, _cfg, geo)
	_check("默认 stage_waves_enabled = false", not wd.stage_waves_enabled)
	_check("默认 stage_id = \"\"", wd.stage_id == "")
	_check("默认 set_stage 不接管波数", not wd.set_stage("3-1", 0))
	_check_int("默认 _max_wave 仍 = 20", wd._max_wave, 20)
	wd.start_wave(1)
	var ms1 := _WaveSim.monster_stats(1, _cfg)
	_check_int("默认 W1 n 逐位 = 基准", wd.n, int(ms1["n"]))
	_check("默认 W1 hp 逐位 = 基准", wd.hp_unit == float(ms1["hp"]))
	_check("默认 W1 cur_spec 为空", wd.cur_spec.is_empty())

	# ② 打开 → 波表接管 n / hp 与波数
	var wd2 = _WaveDirector.new()
	wd2.setup(player, _cfg, geo)
	wd2.stage_waves_enabled = true
	wd2.prototype_split_enabled = false
	wd2.elite_waves_enabled = false
	wd2.tower_aggro_enabled = false
	_check("打开后 set_stage 接管波数", wd2.set_stage("3-1", 0))
	_check_int("3-1 波数 = 13（由表长决定）", wd2._max_wave, 13)
	wd2.start_wave(1)                       # 3-1 W1 = p（试探）
	var sp1: Dictionary = _StageWaves.wave_spec("3-1", 1, _cfg, 0)
	_check_int("W1 n = 波表 n", wd2.n, int(sp1["n"]))
	_check("W1 hp 逐位 = 波表 hp", wd2.hp_unit == float(sp1["hp"]))
	_check_int("W1 n 比基准少（试探波是 0.70×）", wd2.n, int(round(0.70 * float(int(ms1["n"])))))
	_check_int("W1 出生表长度 = n", wd2._proto_seq.size(), wd2.n)

	# ③ 锚点：0-1 恒 neutral → 一律不覆盖（F 信号：锚点污染是最贵的一条）
	wd2.set_stage("0-1", 0)
	_check_int("0-1 波数 = 10", wd2._max_wave, 10)
	for w in range(1, 11):
		wd2.start_wave(w)
		var msw := _WaveSim.monster_stats(w, _cfg)
		if wd2.n != int(msw["n"]) or wd2.hp_unit != float(msw["hp"]):
			_check("0-1 W%d 未被覆盖（逐位 = 基准）" % w, false)
			break
		if w == 10:
			_check("0-1 十波全部逐位 = 基准（锚点干净）", true)

	# ④ 锚点强化：0-1 即使开着三原型 + 精英，出生表也必须与 MonsterData 口径逐位一致
	var wd3 = _WaveDirector.new()
	wd3.setup(player, _cfg, geo)
	wd3.stage_waves_enabled = true
	wd3.prototype_split_enabled = true
	wd3.elite_waves_enabled = true
	wd3.tower_aggro_enabled = false
	wd3.set_stage("0-1", 0)
	wd3.start_wave(10)                      # 0-1 W10 = E（精英波）
	var n10: int = int(wd3.n)
	_check_int("0-1 W10 n 逐位 = 基准", n10, int(_WaveSim.monster_stats(10, _cfg)["n"]))
	var ne := _MonsterData.elite_count(10, n10)
	_check_int("0-1 W10 精英只数 = MonsterData 口径", wd3._elite_count_wave(), ne)
	var eidx: Array = _MonsterData.elite_indices(n10, ne)
	var c := _MonsterData.elite_conserve(n10, ne)
	# 🔴 期望值必须走 `MonsterData` 原口径（`spawn_sequence` 是三原型轮转，不是全 Swarm）：
	#    中性波的定义就是「和不开波表时**一模一样**」，任何一处换成"全 Swarm"都是错解。
	var want_seq: Array = _MonsterData.spawn_sequence(n10)
	var ok := true
	for i in n10:
		var p := String(want_seq[i])
		var e := eidx.has(i)
		var want_hp := _MonsterData.hp_mult(p, e, c)
		var want_spd := _MonsterData.spd_mult(p)
		var got_hp := float(wd3._hp_mults[i])
		var got_spd := float(wd3._spd_mults[i])
		var got_proto := String(wd3._proto_seq[i])
		if got_hp != want_hp or got_spd != want_spd or got_proto != p:
			ok = false
			_log("      idx=%d proto=%s/%s hp=%.17f want=%.17f spd=%.17f want=%.17f" % [
				i, got_proto, p, got_hp, want_hp, got_spd, want_spd])
			break
	_check("0-1 W10 出生表（hp/spd/原型）逐位 = MonsterData 口径", ok)

	# ⑤ 加压接到导演：S=3 时 2-1 的 W1 变潮涌（n 变 1.45×，hp 相应下调，总量不变）
	var wd4 = _WaveDirector.new()
	wd4.setup(player, _cfg, geo)
	wd4.stage_waves_enabled = true
	wd4.prototype_split_enabled = false
	wd4.elite_waves_enabled = false
	wd4.tower_aggro_enabled = false
	wd4.set_stage("2-1", 3)
	wd4.start_wave(1)
	var sp_s: Dictionary = _StageWaves.wave_spec("2-1", 1, _cfg, 3)
	_check_int("S=3：2-1 W1 n = 潮涌 n", wd4.n, int(sp_s["n"]))
	_check("S=3：2-1 W1 波型码 = s", String(wd4.cur_spec.get("code", "")) == "s")

	wd.free()
	wd2.free()
	wd3.free()
	wd4.free()


# ---------------------------------------------------------------------------
#  [7] 批处理镜像 ↔ 真身（有波表时逐位等价）
# ---------------------------------------------------------------------------
## 🔴 为什么这条最重要：MC 300 局定难度跑的是**批处理镜像** `wave_sim_proto_aggro`，
##   不是真身 `WaveDirector`。两者只要有一个字段对不上（只数 / 单只血量 / 精英只数 /
##   sapper 标记 / 构成乘数），MC 读数就与实机脱钩 —— 「这关通过率 62%」这种结论全部作废。
##   所以「波表接进镜像」这件事必须由真身对拍钉死，不能只测镜像自己内部自洽。
##
## 对拍口径 = 实机全开（`boot.gd` 的注入值）：proto / elite / aggro 全 ON，
##   `attrition_override = -1.0`（走 `MonsterData.resolve_attrition` 默认）、
##   `repair_on_disable = 0`（V-8 复活档全惰性）、`warmup_waves = 0`。
##   RADIAL 模式（实机口径）。
func _test_mirror() -> void:
	_log("--- [7] 批处理镜像 ↔ 真身（stage_waves 接线后的逐位等价 · RADIAL 全开）---")
	var prev: int = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var geo = _Geo6.build()
	# 逐位比较的键：真身 `last_result` 与镜像返回字典的公共键。
	var keys: Array = ["kills", "leaked", "scrap_earned", "n", "hp_each"]
	var bad := 0
	var pairs := 0
	var first := ""
	for sid in _StageWaves.STAGE_ORDER:
		var wc := _StageWaves.wave_count(sid)
		var s_arr := _CampaignData.min_regions_on_arrival(sid)
		var probes: Array = [1, int(round(float(wc) / 2.0)), wc]
		for w in probes:
			for path in ["A", "B"]:
				var rt := _rt_stage_wave(path, geo, sid, s_arr, w)
				var mg := _mg_stage_wave(path, geo, sid, s_arr, w)
				pairs += 1
				var diff := 0
				for k in keys:
					if float(rt.get(k, -1.0)) != float(mg.get(k, -1.0)):
						diff += 1
						if first == "":
							first = "%s W%d path=%s · %s 真身=%s 镜像=%s" % [
								sid, w, path, k, str(rt.get(k)), str(mg.get(k))]
				if diff > 0:
					bad += 1
	_SpaceModel.mode = prev
	_check_int("SW7-1 真身 == 批处理镜像（10 关 × 3 波 × 2 路径）", bad, 0)
	_check_int("SW7-2 比对组数（60 = 十关 × 3 探针波 × A/B）", pairs, 60)
	if first != "":
		_log("      · 首个分岔：%s" % first)

	# ---- SW7-3：0-1 是「实时 == 无波表」的锚点 —— 镜像也必须逐位不变 ----
	#   🔴 中性波（V-5）走的是 `neutral` 分支，**一个字段都不许被覆盖**。
	#   这里比的是「带 stage_id="0-1"」vs「stage_id=""（旧口径）」—— 两者必须逐位相等。
	var anchor_bad := 0
	for w in range(1, _StageWaves.wave_count("0-1") + 1):
		for path in ["A", "B"]:
			var a := _mg_stage_wave(path, geo, "0-1", 0, w)
			var b := _mg_stage_wave(path, geo, "", 0, w)
			for k in keys:
				if float(a.get(k, -1.0)) != float(b.get(k, -1.0)):
					anchor_bad += 1
					break
	_check_int("SW7-3 0-1 十波：带波表 == 无波表（中性锚点逐位不变）", anchor_bad, 0)

	# ---- SW7-4：波表**真的**改变了镜像读数（防「接线了但没生效」的假绿）----
	#   9-1 W20 是「处刑」波，`S=7`（k=2）→ 精英只数 = 基准 +2。金标本 W20 也是精英波，
	#   但只数按旧式子 → 两者必须不同，否则说明 `spec` 根本没被读到。
	var s91 := _CampaignData.min_regions_on_arrival("9-1")
	var sp91: Dictionary = _StageWaves.wave_spec("9-1", 20, _cfg, s91)
	var ms20 := _WaveSim.monster_stats(20, _cfg)
	var gold_e := _MonsterData.elite_count(20, int(ms20["n"]))
	_check_int("SW7-4a 9-1 首次抵达 S = 7（7 区全守才开决战）", s91, 7)
	_check("SW7-4b 9-1 W20 精英只数 > 金标本旧式子（%d > %d，波表真的生效了）"
		% [int(sp91.get("elite", 0)), gold_e], int(sp91.get("elite", 0)) > gold_e)

	# ---- SW7-5：抵达档位 `S` 的静态值（MC 难度表的输入）----
	#   图状解锁下「首次抵达」的最少已守地区：中枢/外环 0、中环 1、8-1 = 5、9-1 = 7。
	var s_map := {}
	for sid in _StageWaves.STAGE_ORDER:
		s_map[sid] = _CampaignData.min_regions_on_arrival(sid)
	_check_int("SW7-5a 0-1 / 三外环 首次抵达 S=0", int(s_map["0-1"]) + int(s_map["1-1"]) + int(s_map["2-1"]) + int(s_map["3-1"]), 0)
	_check_int("SW7-5b 四中环 首次抵达 S=1", int(s_map["4-1"]) + int(s_map["5-1"]) + int(s_map["6-1"]) + int(s_map["7-1"]), 4)
	_check_int("SW7-5c 8-1 首次抵达 S=5（门槛：已守 ≥5 区）", int(s_map["8-1"]), 5)

	# ---- SW8：**产品实机臂**（战斗类型 + 战斗内复活）的逐位对拍 ----
	#   🔴 为什么必须成一组门禁：MC 表 3（唯一用来定难度的表）跑的就是这两个开关。
	#      上一轮镜像**根本没实现战斗类型**，于是表 3 整张偏悲观（6-1 36% → 实为 68%），
	#      而当时所有断言都是绿的 —— 因为没人把这两个开关接进对拍。
	#   抽 4 关 × 2 波 = 8 组（含两处曾经分岔的 6-1 / 9-1），够便宜、够指认。
	var prev2: int = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var prod_geo = _Geo6.build()
	var bad2 := 0
	var pairs2 := 0
	var effect := 0
	for pr in [["0-1", 5], ["3-1", 6], ["6-1", 8], ["9-1", 7], ["6-1", 16], ["9-1", 20],
			["2-1", 6], ["5-1", 7]]:
		var psid: String = pr[0]
		var pw: int = int(pr[1])
		var pS: int = _CampaignData.min_regions_on_arrival(psid)
		var rt2 := _rt_prod(prod_geo, psid, pS, pw)
		var mg2 := _mg_prod(prod_geo, psid, pS, pw, true, true)
		var mg2_off := _mg_prod(prod_geo, psid, pS, pw, false, false)
		pairs2 += 1
		# 战斗类型**真的**生效了？（镜像 types ON ≠ OFF）—— 防「接了一半」的假绿
		if int(mg2.get("kills", 0)) != int(mg2_off.get("kills", 0)) \
				or int(mg2.get("leaked", 0)) != int(mg2_off.get("leaked", 0)):
			effect += 1
		# 真身只给 core_hp，镜像只给 core_damage → 统一折算成 core_hp 再比
		var d_core := float(rt2.get("core_hp", -1.0)) - (BIG_CORE - float(mg2.get("core_damage", -1.0)))
		if int(rt2.get("kills", -1)) != int(mg2.get("kills", -2)) \
				or int(rt2.get("leaked", -1)) != int(mg2.get("leaked", -2)) \
				or absf(float(rt2.get("scrap_earned", -1.0)) - float(mg2.get("scrap_earned", -2.0))) > 1e-9 \
				or absf(d_core) > 1e-6:
			bad2 += 1
	_SpaceModel.mode = prev2
	_check_int("SW8-1 产品臂（types+revive）真身 == 镜像（8 组）", bad2, 0)
	_check_int("SW8-2 比对组数", pairs2, 8)
	# 至少 3 组要被战斗类型改变 → 否则挡不住「接了但一直走空路径」的假绿
	_check("SW8-3 战斗类型在镜像里真的被消费（%d / 8 组读数改变，要求 ≥3）" % effect, effect >= 3)


## 真身单波（有波表）：headless 驱动真实 `WaveDirector`，逐子步跑到波末。
##   🔴 `warmup_waves` 必须显式写 = `MonsterData.WARMUP`：真身字段默认就是它（起手保护 W1..W2
##      仇恨不激活）。镜像侧若传 0，W1 会「一边开仇恨一边不开」→ 逐位对拍必红。
func _rt_stage_wave(path: String, geo, sid: String, S: int, w: int) -> Dictionary:
	var cfg: Dictionary = _cfg.duplicate(true)
	cfg["core_hp"] = BIG_CORE
	var p = _SimPlayer.new_player(path, cfg, geo)
	var wd = _WaveDirector.new()
	wd.prototype_split_enabled = true
	wd.elite_waves_enabled = true
	wd.tower_aggro_enabled = true
	wd.warmup_waves = _MonsterData.WARMUP
	wd.stage_waves_enabled = true
	wd.setup(p, cfg, geo)
	wd.set_stage(sid, S)
	wd.start_wave(w)
	var r: Dictionary = wd.run_to_end()
	wd.free()
	return r


## 合并镜像单波（同一确定性 player 初值 → 与真身逐位可对）。
func _mg_stage_wave(path: String, geo, sid: String, S: int, w: int) -> Dictionary:
	var cfg: Dictionary = _cfg.duplicate(true)
	cfg["core_hp"] = BIG_CORE
	var p = _SimPlayer.new_player(path, cfg, geo)
	return _WaveSimProtoAggro.simulate_wave_proto_aggro(p, w, cfg, geo,
		true, true, true, 0.6, -1.0, _MonsterData.WARMUP, false, false, sid, S)


## 产品实机臂 · 真身单波：`boot.gd` 的六个开关全开（含战斗类型 + 战斗内复活）。
func _rt_prod(geo, sid: String, S: int, w: int) -> Dictionary:
	var cfg: Dictionary = _cfg.duplicate(true)
	cfg["core_hp"] = BIG_CORE
	var p = _SimPlayer.new_player("B", cfg, geo)
	var wd = _WaveDirector.new()
	wd.prototype_split_enabled = true
	wd.elite_waves_enabled = true
	wd.tower_aggro_enabled = true
	wd.combat_revive_enabled = true
	wd.combat_types_enabled = true
	wd.warmup_waves = _MonsterData.WARMUP
	wd.stage_waves_enabled = true
	wd.setup(p, cfg, geo)
	wd.set_stage(sid, S)
	wd.start_wave(w)
	var r: Dictionary = wd.run_to_end()
	wd.free()
	return r


## 产品实机臂 · 镜像单波：`cfg.repair_on_disable = 9` ≡ 真身 `combat_revive_enabled`；
##   `cfg.combat_types_enabled` ≡ 真身同名 bool（`wave_sim_proto_aggro` 同名消费）。
func _mg_prod(geo, sid: String, S: int, w: int, types_on: bool, revive_on: bool) -> Dictionary:
	var cfg: Dictionary = _cfg.duplicate(true)
	cfg["core_hp"] = BIG_CORE
	if revive_on:
		cfg["repair_on_disable"] = 9
	if types_on:
		cfg["combat_types_enabled"] = true
	var p = _SimPlayer.new_player("B", cfg, geo)
	return _WaveSimProtoAggro.simulate_wave_proto_aggro(p, w, cfg, geo,
		true, true, true, 0.6, -1.0, _MonsterData.WARMUP, false, false, sid, S)


# ---------------------------------------------------------------------------
#  工具
# ---------------------------------------------------------------------------
func _check(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		_log("   [PASS] %s" % name)
	else:
		_fail += 1
		_log("   [FAIL] %s" % name)


func _check_int(name: String, got: int, want: int) -> void:
	_check("%s（got=%d want=%d）" % [name, got, want], got == want)


func _check_close(name: String, got: float, want: float, tol: float) -> void:
	_check("%s（got=%.12f want=%.12f）" % [name, got, want], absf(got - want) <= tol)


func _log(s: String) -> void:
	print(s)
