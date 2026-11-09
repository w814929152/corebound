extends SceneTree
##
## 生成器 · `design/gdd/stage-waves.md` §6 附录 A（十关总览 + 149 波逐波表）
##
## 🔴 为什么要生成而不是手写：
##   波型串（`stage_waves.PATTERN`）一改，149 行逐波表的只数 / 单只 HP / 间隔 / 塔损
##   **全部同时失效**。手改表格必然漏行、必然算错 `k` —— 文档就会变成"看起来对、
##   实际和代码不一致"的假证据。本工具从 SSOT 直接算出 markdown，文档只负责粘贴。
##
## 跑法：
##   <godot> --headless --path . --script res://tools/gen_stage_waves_md.gd > /tmp/sec6.md
##
## 输出：`### A.1` + `### A.2` 两节（不含 §6 的说明段，那两段是人工写的）。
##

const _StageWaves := preload("res://scripts/data/stage_waves.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _CampaignData := preload("res://scripts/data/campaign_data.gd")

var _cfg: Dictionary = {}


func _initialize() -> void:
	_cfg = _MvpConfig.cfg_of()
	_sec_a1()
	_sec_a2()
	quit(0)


## A.1 三通道总览。
func _sec_a1() -> void:
	print("### A.1 三通道总览")
	print("")
	print("| 关 | 波数 | 经济(废料) | 峰值波全漏伤害 | 峰值塔损倍率 | 峰值只数 | 峰值单只HP | 潮/铁/涓/探/刑 |")
	print("|---|---|---|---|---|---|---|---|")
	for sid in _StageWaves.STAGE_ORDER:
		var wc := _StageWaves.wave_count(sid)
		var S := _CampaignData.min_regions_on_arrival(sid)
		var scrap := 0.0
		var scrap_base := 0.0
		var peak_leak := 0.0
		var peak_td := 0.0
		var peak_n := 0
		var peak_hp := 0.0
		var cnt := {"s": 0, "b": 0, "t": 0, "p": 0, "e": 0, "E": 0}
		for w in range(1, wc + 1):
			var ms := _WaveSim.monster_stats(w, _cfg)
			var bn := int(ms["n"])
			var bhp := float(ms["hp"])
			scrap_base += float(bn) * float(ms["scrap_per_kill"])
			var sp: Dictionary = _StageWaves.wave_spec(sid, w, _cfg, S)
			if sp.is_empty() or bool(sp.get("neutral", false)):
				scrap += float(bn) * float(ms["scrap_per_kill"])
				peak_leak = maxf(peak_leak, float(bn) * 50.0)
				peak_td = maxf(peak_td, 1.0)
				peak_n = maxi(peak_n, bn)
				peak_hp = maxf(peak_hp, bhp)
				# 🔴 0-1 的 `E` 是处刑·基准：血量中性但形态是处刑，必须计入构成统计。
				if _StageWaves.code_at(sid, w) == "E":
					cnt["E"] = int(cnt.get("E", 0)) + 1
				else:
					cnt["n"] = int(cnt.get("n", 0)) + 1
				continue
			var n := int(sp["n"])
			scrap += float(n) * float(ms["scrap_per_kill"])
			peak_leak = maxf(peak_leak, float(n) * 50.0)
			peak_td = maxf(peak_td, _tower_dps_mult(sp.get("comp", {})))
			peak_n = maxi(peak_n, n)
			peak_hp = maxf(peak_hp, float(sp["hp"]))
			var code := String(sp["code"])
			if cnt.has(code):
				cnt[code] = int(cnt[code]) + 1
		var econ := (scrap / scrap_base) if scrap_base > 0.0 else 1.0
		print("| %s | %d | %.2f× | %d | %.2f× | %d | %s | %d/%d/%d/%d/%d |" % [
			sid, wc, econ, int(round(peak_leak)), peak_td, peak_n,
			_fmt_hp(peak_hp),
			int(cnt.get("s", 0)), int(cnt.get("b", 0)), int(cnt.get("t", 0)),
			int(cnt.get("p", 0)), int(cnt.get("e", 0)) + int(cnt.get("E", 0))])


## A.2 逐波表。
func _sec_a2() -> void:
	print("")
	print("### A.2 逐波")
	for sid in _StageWaves.STAGE_ORDER:
		var wc := _StageWaves.wave_count(sid)
		var S := _CampaignData.min_regions_on_arrival(sid)
		var st: Dictionary = _CampaignData.STAGES.get(sid, {})
		var mid := _CampaignData.resolve_map_id(sid)
		print("")
		print("#### %s · %s（`%s`，%d 波）" % [sid, String(st.get("name", "")), mid, wc])
		print("")
		print("| 波 | 型 | 只数 | 单只HP | 本波总HP | 偏离基准 | 精英 | 间隔 | 塔损 |")
		print("|---|---|---|---|---|---|---|---|---|")
		for w in range(1, wc + 1):
			var ms := _WaveSim.monster_stats(w, _cfg)
			var bn := int(ms["n"])
			var bhp := float(ms["hp"])
			var base := float(bn) * bhp
			var sp: Dictionary = _StageWaves.wave_spec(sid, w, _cfg, S)
			if sp.is_empty() or bool(sp.get("neutral", false)):
				var win := _MvpConfig.spawn_window(w)
				var D := float(ms["D"])
				var iv := D * win / float(maxi(1, bn))
				# 🔴 中性关（0-1）也可能有 `E`（处刑·基准）：它血量中性，但**有精英**。
				#    若一律印「常规 / —」，文档就会谎报 0-1 没有处刑波。
				var code_n := _StageWaves.code_at(sid, w)
				var is_e := code_n == "E"
				var e_n := _MonsterData.elite_count(w, bn) if is_e else 0
				print("| %s | %s | %d | %s | %d | +0%% | %s | %.2fs | 1.00× |" % [
					("**W%d**" % w) if is_e else ("W%d" % w),
					"处刑·基准" if is_e else "常规",
					bn, _fmt_hp(bhp), int(round(base)),
					("**%d**" % e_n) if e_n > 0 else "—", iv])
				continue
			var n := int(sp["n"])
			var hp := float(sp["hp"])
			var tot := float(sp["total"])
			var dev := (tot / base - 1.0) * 100.0
			var win2 := _MvpConfig.spawn_window(w)
			var D2 := float(ms["D"])
			var iv2 := D2 * win2 / float(maxi(1, n))
			var elite := int(sp.get("elite", 0))
			var code := String(sp["code"])
			var bold := code == "s" or code == "e" or code == "E"
			var wtxt := String(sp["label"])
			var devs := ("+%d%%" % int(round(dev))) if dev >= -0.5 else ("%d%%" % int(round(dev)))
			print("| %s | %s | %d | %s | %d | %s | %s | %.2fs | %.2f× |" % [
				("**W%d**" % w) if bold else ("W%d" % w),
				wtxt, n, _fmt_hp(hp), int(round(tot)), devs,
				("**%d**" % elite) if elite > 0 else "—",
				iv2, _tower_dps_mult(sp.get("comp", {}))])


## 本波三原型构成的对塔伤害复合比（基准 40/40/20 → 1.00）。
func _tower_dps_mult(comp) -> float:
	var c: Dictionary = comp if comp is Dictionary else {}
	if c.is_empty():
		return 1.0
	var tot := 0.0
	for p in ["R", "S", "T"]:
		tot += float(c.get(p, 0.0)) * float(_MonsterData.M_DPS[_StageWaves.PROTO_OF[p]])
	return tot


func _fmt_hp(hp: float) -> String:
	if hp >= 1000.0:
		return "%d" % int(round(hp))
	if hp >= 100.0:
		return "%.0f" % hp
	return "%.1f" % hp
