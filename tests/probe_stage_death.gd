extends SceneTree
##
## 探针 · 单关死因解剖（默认 6-1）：
##   「通关率 0%」只说了结果，没说是**哪条通道**杀的人。本工具逐局打印
##   失守那一波（及前两波）的 kills / leaked / towers_disabled / dis_new / scrap，
##   以及**本波的波型与只数** —— 用来区分：
##     · 漏怪型（leaked 高、disabled 0）→ 单只太厚，DPS 不足（涓流/铁壁的厚血侧）
##     · 拆塔型（dis_new 高、leaked 随之上升）→ 对塔伤害通道（铁壁/涓流的 Tank 侧）
##     · 经济型（scrap 远低于同波基准）→ 塔立不起来
##
## 跑法：
##   <godot> --headless --path . --script res://tests/probe_stage_death.gd [stage] [runs]
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _RunLoopPA := preload("res://scripts/engine/run_loop_proto_aggro.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
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


func _initialize() -> void:
	var sid := "6-1"
	var runs := 12
	var ua: Array = OS.get_cmdline_user_args()
	if ua.size() > 0:
		sid = String(ua[0])
	if ua.size() > 1:
		runs = int(ua[1])

	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var cfg0: Dictionary = _Cfg.cfg_of("B")
	var wc := _StageWaves.wave_count(sid)
	var S := _CampaignData.min_regions_on_arrival(sid)

	print("")
	print("=".repeat(96))
	print("  死因解剖 · %s（%d 波 · S=%d · %d 局 · 产品口径）" % [sid, wc, S, runs])
	print("=".repeat(96))
	print("  %-4s %-4s %-6s %-7s %-9s %-8s %-8s %-7s" %
		["局", "死波", "波型", "本波只数", "kills", "leaked", "dis_new", "末残血"])

	var hist := {}
	# 🔴 rng 必须建在循环**外**：建在里面 = 每局同一条随机流 = 同一局跑 N 次，
	#    「N 局通过率」会变成 1 局的 N 次重复。这个坑本项目已经踩过一次（见 §11 note）。
	var rng := _PyRandom.new(SEED)
	for i in range(runs):
		var cx: Dictionary = cfg0.duplicate(true)
		cx["n_slots"] = N_SLOTS
		cx["max_actions"] = ACTIONS
		cx["repair_on_disable"] = 9
		cx["combat_types_enabled"] = true
		var out := _RunLoopPA.run("B", cx, wc, null, rng,
			true, true, true, EXP, ATTRITION, WARMUP, false, false, [], sid, S)
		var rows: Array = out["rows"]
		var die_w := 0
		var last: Dictionary = {}
		for r in rows:
			if float(r.get("core_hp", 0.0)) <= 0.0:
				die_w = int(r["w"])
				last = r
				break
		if die_w == 0 and not rows.is_empty():
			die_w = int(rows[-1]["w"])
			last = rows[-1]
		var code := _StageWaves.code_at(sid, die_w)
		var sp: Dictionary = _StageWaves.wave_spec(sid, die_w, cx, S)
		var nn := int(sp.get("n", 0)) if not sp.is_empty() and not bool(sp.get("neutral", false)) else 0
		hist[die_w] = int(hist.get(die_w, 0)) + 1
		print("  %-4d %-4d %-6s %-7d %-9d %-8d %-8d %-7.0f" % [
			i, die_w, code, nn, int(last.get("kills", 0)), int(last.get("leaked", 0)),
			int(last.get("dis_new", 0)), float(last.get("core_hp", 0.0))])

	print("")
	print("  失守波分布：" + str(hist))
	print("=".repeat(96))
	quit(0)
