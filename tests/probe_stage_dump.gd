extends SceneTree
##
## 探针 · 单局逐波全量导出（诊断用，不再归纳）
##
## 跑法：<godot> --headless --path . --script res://tests/probe_stage_dump.gd [stage] [game_idx]
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
	var ua: Array = OS.get_cmdline_user_args()
	if ua.size() > 0:
		sid = String(ua[0])

	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var cfg0: Dictionary = _Cfg.cfg_of("B")
	var wc := _StageWaves.wave_count(sid)
	var S := _CampaignData.min_regions_on_arrival(sid)
	var cx: Dictionary = cfg0.duplicate(true)
	cx["n_slots"] = N_SLOTS
	cx["max_actions"] = ACTIONS
	cx["repair_on_disable"] = 9
	cx["combat_types_enabled"] = true

	print("")
	print("=".repeat(104))
	print("  逐波全量 · %s（%d 波 · S=%d）" % [sid, wc, S])
	print("=".repeat(104))

	# 复现 MC 的单局（同一个 seed 起手）——只跑第一局，与 MC 第 0 局同轨迹。
	var rng := _PyRandom.new(SEED)
	var out := _RunLoopPA.run("B", cx, wc, null, rng,
		true, true, true, EXP, ATTRITION, WARMUP, false, false, [], sid, S)
	var rows: Array = out["rows"]

	print("  %-3s %-4s %-6s %-4s %-9s %-8s %-7s %-8s %-7s %-9s %-8s" %
		["W", "型", "本波只数", "n0", "单只HP", "kills", "leaked", "dis_new", "塔数", "废料", "废料基准"])
	for r in rows:
		var w := int(r["w"])
		var code := _StageWaves.code_at(sid, w)
		var sp: Dictionary = _StageWaves.wave_spec(sid, w, cx, S)
		var nn := 0
		var hp := 0.0
		if not sp.is_empty() and not bool(sp.get("neutral", false)):
			nn = int(sp["n"])
			hp = float(sp["hp"])
		else:
			var ms: Dictionary = _WaveSim.monster_stats(w, cx)
			nn = int(ms["n"])
			hp = float(ms["hp"])
		var ms2: Dictionary = _WaveSim.monster_stats(w, cx)
		var sc_base := float(int(ms2["n"])) * float(ms2["scrap_per_kill"])
		print("  %-3d %-4s %-9d %-4d %-9.1f %-8d %-7d %-8d %-7d %-9.1f %-8.1f" % [
			w, code, nn, int(ms2["n"]), hp,
			int(r.get("kills", 0)), int(r.get("leaked", 0)), int(r.get("dis_new", 0)),
			int(r.get("towers", 0)), float(r.get("scrap_earned", 0.0)), sc_base])
		if float(r.get("core_hp", 1.0)) <= 0.0:
			print("  ↑ 本波核心归零")
			break

	print("=".repeat(104))
	quit(0)
