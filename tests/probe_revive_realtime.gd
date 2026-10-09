extends SceneTree
##
## 🔒 V-8 肉盾循环 M-1「实机可见性」探针
##
##   证明**实时版** `WaveDirector` 真的会把死掉的肉盾塔在 `N = 0.5s` 后**自动扶起来**
##   —— 而不只是批处理镜像 `wave_sim_aggro.gd` 里的一个数。
##
## 它回答三件事（对应验收「实机能否看到肉盾塔爬起」）：
##   ① 塔**什么时候死**（子步 / 时刻）；
##   ② 塔**什么时候爬起**，与死亡相隔多久（应 = N=0.5s 的累计口径）；
##   ③ 渲染层能拿到的**数据源**（`snapshot()` 的 `revive_ui` / 每塔 `revive_charged`）
##      是否在爬起瞬间正确翻转 —— 即「塔底充能点亮 → 熄灭」是否真的有数据支撑。
##
## 🔴 本探针是**诊断件**（恒 quit(0)，判读留人）—— 与 `probe_radial_aggro.gd` 同款定位。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/probe_revive_realtime.gd
##
## ⚠️ G6：headless `--script` 无 global_script_class_cache → 一律 preload，不写 class_name。
##

const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Geo8 := preload("res://scripts/geo/geo8.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const REVIVE_MODE := 9      # 9 = 战斗内即时复活（默认恒 0 → 实机默认看不到，需显式开）


func _mk_cfg(mode: int) -> Dictionary:
	return _Cfg.cfg_of("B", _Cfg.KR_FINAL, _Cfg.LINK_RULE, "tier", "current", false,
		{"repair_on_disable": mode})


## 肉盾（低 h，暴露位） + carry（高 h，安全位）。🔴 carry 必须**严格**更高。
func _mk_player(geo, slot_bulwark: int, slot_carry: int, h_b: int, h_c: int):
	var p = _SimPlayer.new_player("B", _mk_cfg(REVIVE_MODE), geo)
	p.towers = []
	p.towers.append(_PS.make_tower(slot_bulwark, "Arrow", h_b, {}))  # 肉盾：会挨打、会死
	p.towers.append(_PS.make_tower(slot_carry, "Arrow", h_c, {}))    # carry：被闸门保护
	return p


func _mk_director(player, cfg: Dictionary, geo):
	var wd = _WaveDirector.new()
	wd.tower_aggro_enabled = true
	wd.warmup_waves = 0          # 探针：让 W1 就能死塔（不测激活时机）
	wd.setup(player, cfg, geo)
	return wd


# ---------------------------------------------------------------------------
#  主探针：逐子步跑一波，打印「死亡 → 爬起」窗口
# ---------------------------------------------------------------------------
func _probe(tag: String, geo, slot_bulwark: int, slot_carry: int, wave: int) -> void:
	var cfg := _mk_cfg(REVIVE_MODE)
	var p = _mk_player(geo, slot_bulwark, slot_carry, 1, 2)
	var wd = _mk_director(p, cfg, geo)

	var events: Array = []      # 爬起事件（子步 / slot / hp / charged）
	wd.tower_revived.connect(func(slot: int) -> void:
		var sn := wd.snapshot()
		var charged := false
		for t in sn.get("towers", []):
			if int(t.get("slot", -1)) == int(slot):
				charged = bool(t.get("revive_charged", false))
		events.append({
			"step": _step, "slot": int(slot), "hp": float(p.towers[0].hp),
			"charged": charged, "ui": bool(sn.get("revive_ui", false)),
		}))

	print("")
	print("===================================================================")
	print("%s · repair_on_disable=%d · N=%s s · K=%s"
		% [tag, REVIVE_MODE, str(cfg["revive_n_seconds"]), str(cfg["revive_k_per_wave"])])
	print("===================================================================")

	wd.start_wave(wave)
	var rows: Array = []
	_step = 0
	var death_step := -1
	var guard := 0
	while (int(wd.state) == 1 or int(wd.state) == 2) and guard < 100000:
		guard += 1
		wd.advance(_WaveSim.DT)
		var t0 = p.towers[0]
		var dis := bool(t0.disabled)
		if death_step < 0 and dis:
			death_step = _step
		rows.append({
			"step": _step, "t": _step * _WaveSim.DT,
			"dis": dis, "hp": float(t0.hp),
			"acc": float(t0.revive_t_disabled),
			"used": int(t0.revive_used_w),
		})
		_step += 1

	var d: Dictionary = wd.last_result.get("v8_diag", {})
	print("波次结果：kills=%d leaked=%d towers_disabled=%d"
		% [int(wd.last_result["kills"]), int(wd.last_result["leaked"]),
			int(wd.last_result.get("towers_disabled", 0))])
	print("复活诊断：fired=%d elig=%d refused=%d redied=%d carry_death=%d misq=%d"
		% [int(float(d.get("revive_fired", 0.0))), int(float(d.get("revive_elig", 0.0))),
			int(float(d.get("revive_refused", 0.0))), int(float(d.get("revive_redied", 0.0))),
			int(float(d.get("carry_death", 0.0))), int(float(d.get("revive_misq", 0.0)))])

	if death_step < 0:
		print("")
		print("⚠️ 本场景**没有塔死亡** → 无法演示爬起（换波次/换塔位再试）。")
		return
	if events.is_empty():
		print("")
		print("⚠️ 塔死了但**没有爬起** → 检查资格闸门（本塔是不是 carry / 是不是安全位）。")
		return

	var rev_step: int = int(events[0]["step"])
	var lo := maxi(0, death_step - 1)
	var hi := mini(rows.size() - 1, rev_step + 1)
	print("")
	print("── 逐子步（肉盾塔 · 从死亡前 1 步到爬起后 1 步）──")
	print("  step     t(s)   disabled   hp      revive_t_disabled   used_w")
	for i in range(lo, hi + 1):
		var r: Dictionary = rows[i]
		var mark := ""
		if i == death_step:
			mark = "   <<< 塔倒下（disabled=true）"
		elif i == rev_step:
			mark = "   >>> 🟢 塔自己爬起来了（disabled=false, hp=hp_max）"
		print("  %4d  %6.2f   %-8s  %7.2f   %10.2f        %d%s"
			% [int(r["step"]), float(r["t"]), str(bool(r["dis"])), float(r["hp"]),
				float(r["acc"]), int(r["used"]), mark])
	print("")
	print("✅ 结论：死亡子步 %d（t=%.2fs） → 爬起子步 %d（t=%.2fs）"
		% [death_step, death_step * _WaveSim.DT, rev_step, rev_step * _WaveSim.DT])
	print("   间隔 = %d 子步；`revive_t_disabled` 累计到第 5 次 DT = %.1fs = N → 触发"
		% [rev_step - death_step, 5.0 * _WaveSim.DT])
	print("   爬起瞬间：slot=%d  hp=%.2f  revive_charged=%s（塔底充能点亮应已熄灭）  revive_ui=%s"
		% [int(events[0]["slot"]), float(events[0]["hp"]),
			str(bool(events[0]["charged"])), str(bool(events[0]["ui"]))])
	print("   hard assert: revive_misq=%d（🔴 必须 0）" % int(float(d.get("revive_misq", 0.0))))


var _step: int = 0


func _initialize() -> void:
	print("🔒 V-8 肉盾循环 M-1 · 实时版「肉盾爬起」可见性探针")

	# ---- ① PATH / 六槽（回归口径，与单测 AC-T1-20 同一场景）----
	_probe("① PATH 六槽 · W1", _Geo6.build(), 0, 4, 1)

	# ---- ② RADIAL / 八槽（🔴 实机运行时口径：boot.gd 窗口模式切 RADIAL）----
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var hits := 0
	for w in range(1, 16):
		if hits >= 2:
			break
		var cfg := _mk_cfg(REVIVE_MODE)
		var geo8 = _Geo8.build8()
		var p = _mk_player(geo8, 0, 5, 1, 2)
		var wd = _mk_director(p, cfg, geo8)
		wd.start_wave(w)
		wd.run_to_end()
		var d: Dictionary = wd.last_result.get("v8_diag", {})
		if int(float(d.get("revive_fired", 0.0))) > 0:
			hits += 1
			_probe("② RADIAL 八槽（实机口径）· W%d" % w, _Geo8.build8(), 0, 5, w)
	if hits == 0:
		print("")
		print("⚠️ RADIAL 口径下 W1..W15 均未出现复活（径向几何下塔本就极少死，")
		print("   与 V-1′ 结论一致：A 路径成型期均值 0.38 次/局）→ 本口径无可演示样本。")
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	quit(0)
