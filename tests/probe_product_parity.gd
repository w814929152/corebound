extends SceneTree
##
## 探针 · 真身 ↔ 批处理镜像：**产品实机口径**下的逐位对拍
##
## 🔴 为什么需要这个探针：
##   上一轮 MC 的三张表里，表 3（产品实机）是把 `cfg.repair_on_disable = 9` +
##   `cfg.combat_types_enabled = true` 塞给镜像算出来的。但镜像族
##   （`wave_sim_proto_aggro` / `wave_sim_aggro`）**从未实现战斗类型**，
##   而产品复活在真身走的是 `combat_revive_enabled` 这个 bool（`_revive_mode()` 视同档 9）。
##   两处都只是「我以为等价」—— 没有对拍就没有证据。
##
## 本探针分三组，逐字段比：
##   P1 · 复活档 9 等价性：真身 `combat_revive_enabled=true` vs 镜像 `repair_on_disable=9`
##   P2 · 战斗类型等价性：真身 `combat_types_enabled=true` vs 镜像（无实现 → 预期分岔）
##   P3 · 组合（产品实机）：真身两开关全开 vs 镜像（若能对上，表 3 才可信）
##
## 跑法：
##   <godot> --headless --path . --script res://tests/probe_product_parity.gd
## 恒 exit 0（诊断用）。
##

const _StageWaves := preload("res://scripts/data/stage_waves.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _WaveSimProtoAggro := preload("res://scripts/engine/wave_sim_proto_aggro.gd")
const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const BIG_CORE := 1000000.0
const KEYS := ["kills", "leaked", "core_hp", "scrap_earned"]

var _cfg: Dictionary = {}
## 本次探针里复活真的发生了几次（0 = 「复活等价」是平凡成立，不能当证据）
var _rev_total := 0


func _initialize() -> void:
	_cfg = _MvpConfig.cfg_of("B")
	_cfg["n_slots"] = 6
	_cfg["max_actions"] = 12
	var prev = _SpaceModel.mode
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var geo = _Geo6.build_by_slots(6)

	print("")
	print("=".repeat(88))
	print("  产品实机口径 · 真身 ↔ 镜像 逐位对拍（BIG_CORE · n_slots=6 · RADIAL）")
	print("=".repeat(88))

	# 探针组合：**十关全覆盖**，每关取「早 / 中 / 末」三波（首波常是 neutral 锚点，故从 W2 起）。
	#   🔴 只测 8 组时，1-1 / 6-1 这类「整关 25~32 个百分点」的跳变缺乏直接证据 ——
	#      波级逐位一致才是「读数可信」的唯一地基，样点越多地基越硬。
	var probes: Array = []
	var sids: Array = _CampaignData.STAGES.keys()
	sids.sort()
	for sid_v in sids:
		var sid := String(sid_v)
		var wc: int = int(_CampaignData.STAGES[sid]["wave_count"])
		var mid: int = maxi(2, int(wc / 2))
		for w in [2, mid, wc]:
			if int(w) >= 2 and int(w) <= wc and not probes.has([sid, int(w)]):
				probes.append([sid, int(w)])

	_parity_group("P1 · 复活档 9（真身 combat_revive_enabled vs 镜像 repair_on_disable=9）",
		geo, probes, false, true, false)
	_parity_group("P2 · 战斗类型（真身 combat_types_enabled vs 镜像 cfg 同名开关）",
		geo, probes, true, false, false)
	_parity_group("P3 · 组合（产品实机两开关全开）",
		geo, probes, true, true, false)

	_effect_group(geo, probes)

	print("")
	print("-".repeat(88))
	print("  读法：|d| = 0 表示该字段逐位一致；分岔字段会打印两侧值。")
	print("=".repeat(88))
	quit(0)


## 一组对拍：live_types / live_revive 控制真身开关；镜像侧同口径映射
## （战斗类型 → `cfg.combat_types_enabled`；复活 → `cfg.repair_on_disable = 9`）。
func _parity_group(title: String, geo, probes: Array,
		live_types: bool, live_revive: bool, _unused: bool) -> void:
	print("")
	print("-".repeat(88))
	print("  " + title)
	print("-".repeat(88))
	print("  %-8s %-4s | %-8s %-8s %-11s %-8s | %-6s %-6s | 判定"
		% ["关", "波", "kills", "leaked", "core_hp", "scrap", "dis", "rev"])

	var n_ok := 0
	var n_bad := 0
	for pr in probes:
		var sid: String = pr[0]
		var w: int = int(pr[1])
		var S: int = _CampaignData.min_regions_on_arrival(sid)
		var rt := _rt(geo, sid, S, w, live_types, live_revive)
		var mg := _mg(geo, sid, S, w, live_revive, live_types)
		# 🔴 镜像不返回 core_hp，只返回 core_damage（= leaked × leak_damage）
		#    → 这里统一折算成 core_hp，否则探针会误报「全部 DIFF」。
		var d_k := int(rt.get("kills", -1)) - int(mg.get("kills", -1))
		var d_l := int(rt.get("leaked", -1)) - int(mg.get("leaked", -1))
		var h_rt := float(rt.get("core_hp", -1.0))
		var h_mg := BIG_CORE - float(mg.get("core_damage", -1.0))
		var d_h := h_rt - h_mg
		var d_s := float(rt.get("scrap_earned", -1.0)) - float(mg.get("scrap_earned", -1.0))
		# 🔴 复活是否真的触发过：真身 `run_to_end()` 不返 `dis_new`/`towers_disabled`，
		#    改从 player 侧读同一份事实（`_count_disabled` + `revive_used_w` 求和）。
		var d_d := _count_disabled(rt["_player"]) - _count_disabled(mg["_player"])
		var d_r := _revive_used(rt["_player"]) - _revive_used(mg["_player"])
		var ok := (d_k == 0) and (d_l == 0) and (d_h == 0.0) and (d_s == 0.0) \
			and (d_d == 0) and (d_r == 0)
		if ok:
			n_ok += 1
		else:
			n_bad += 1
		print("  %-8s %-4d | %+8d %+8d %+11.1f %+8.3f | %+6d %+6d | %s"
			% [sid, w, d_k, d_l, d_h, d_s, d_d, d_r, "OK" if ok else "DIFF"])
		_rev_total += _revive_used(rt["_player"])

	print("  ↳ 合计：逐位一致 %d / 分岔 %d · 本组复活实际触发 %d 次%s"
		% [n_ok, n_bad, _rev_total,
			"（= 0 → 本组的『复活等价』是平凡成立，不足为证）" if _rev_total == 0 else ""])


func _rt(geo, sid: String, S: int, w: int, types_on: bool, revive_on: bool) -> Dictionary:
	var cfg: Dictionary = _cfg.duplicate(true)
	cfg["core_hp"] = BIG_CORE
	var p = _SimPlayer.new_player("B", cfg, geo)
	var wd = _WaveDirector.new()
	wd.prototype_split_enabled = true
	wd.elite_waves_enabled = true
	wd.tower_aggro_enabled = true
	wd.combat_revive_enabled = revive_on
	wd.combat_types_enabled = types_on
	wd.warmup_waves = _MonsterData.WARMUP
	wd.stage_waves_enabled = true
	wd.setup(p, cfg, geo)
	wd.set_stage(sid, S)
	wd.start_wave(w)
	var r: Dictionary = wd.run_to_end()
	# 🔴 真身 `run_to_end()` 不导出 Disabled 计数 → 把 player 挂回返回字典，由探针自行读。
	r["_player"] = p
	wd.free()
	return r


func _mg(geo, sid: String, S: int, w: int, revive_on: bool, types_on: bool) -> Dictionary:
	var cfg: Dictionary = _cfg.duplicate(true)
	cfg["core_hp"] = BIG_CORE
	if revive_on:
		cfg["repair_on_disable"] = 9
	if types_on:
		cfg["combat_types_enabled"] = true
	var p = _SimPlayer.new_player("B", cfg, geo)
	var r: Dictionary = _WaveSimProtoAggro.simulate_wave_proto_aggro(p, w, cfg, geo,
		true, true, true, 0.6, -1.0, _MonsterData.WARMUP, false, false, sid, S)
	r["_player"] = p
	return r


## P4 · 效果量：同一**真身**在 types OFF / ON 下的单波读数差。
##   🔴 目的：把「战斗类型对单波到底改了多大」量出来。镜像读数若与真身逐位一致，
##      而整关通过率仍大幅变化，那变化就**只能**来自多波累积（复仇/仇恨/经济环），
##      不能来自「单波被悄悄改了数值」。这里给的正是那个分界证据。
func _effect_group(geo, probes: Array) -> void:
	print("")
	print("-".repeat(88))
	print("  P4 · 效果量（真身 types OFF → ON · 单波读数差）")
	print("-".repeat(88))
	print("  %-8s %-4s | %+8s %+8s %+11s" % ["关", "波", "Δkills", "Δleaked", "Δcore_hp"])
	var nz := 0
	for pr in probes:
		var sid: String = pr[0]
		var w: int = int(pr[1])
		var S: int = _CampaignData.min_regions_on_arrival(sid)
		var a := _rt(geo, sid, S, w, false, false)
		var b := _rt(geo, sid, S, w, true, false)
		var d_k := int(b.get("kills", 0)) - int(a.get("kills", 0))
		var d_l := int(b.get("leaked", 0)) - int(a.get("leaked", 0))
		var d_h := float(b.get("core_hp", 0.0)) - float(a.get("core_hp", 0.0))
		if d_k != 0 or d_l != 0:
			nz += 1
		print("  %-8s %-4d | %+8d %+8d %+11.1f" % [sid, w, d_k, d_l, d_h])
	print("  ↳ %d / %d 个探针的单波读数被改变（其余 = 该波无抗性差异，如全 Swarm）"
		% [nz, probes.size()])


## 当前 Disabled 塔数（真身 / 镜像同口径，两者都调同一个 helper）。
func _count_disabled(p) -> int:
	return _WaveSimAggro._count_disabled(p)


## 本波「已用掉的复活次数」总和 —— 复活真的发生过的**直接证据**。
func _revive_used(p) -> int:
	var n := 0
	if p == null:
		return 0
	for t in p.towers:
		n += int(t.revive_used_w)
	return n
