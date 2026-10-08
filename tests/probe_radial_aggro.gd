extends SceneTree
##
## 径向战斗镜像诊断探针（`radialaggro` 入口）—— 阶段3 V-1′ 根因定位
##
## 🔴 使命：scan_attrition8 显示 ATTRITION 1.0→6.0 全程 T-A=0（塔零死亡），
##    与 §6.3 预期（1.50→T-A≈1.08）严重背离。本探针单波 W3 逐 tick 观察：
##      · 怪物是否进入 AggroTower（state==1）
##      · 有多少 tick 调用了 _damage_tower（塔实际挨打）
##      · 塔 HP 是否下降
##    以定位"塔零死亡"的根因（怪物位置派生 / 仇恨锁定 / DPS 秒杀前 / 其他）。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/probe_radial_aggro.gd
##

const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _Geo8 := preload("res://scripts/geo/geo8.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")


func _initialize() -> void:
	print("===================================================================")
	print("径向战斗镜像诊断 · W3 单波逐 tick（八槽径向）")
	print("===================================================================")

	# ---- 对照 A：PATH 模式（金标本口径，确认塔死亡机制本身工作）----
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	print("\n==== [对照] PATH 模式（六槽折线，怪物沿路径经过暴露塔）====")
	_run_probe("PATH", false)

	# ---- 对照 B：RADIAL 模式（八槽径向，怪物直插核心）----
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	print("\n==== [诊断] RADIAL 模式（八槽径向，怪物直插核心）====")
	_run_probe("RADIAL", true)

	# ---- 关键对照：A/B 路径多塔逐波（定位 scan8 全程 T-A=0 的根因 + 风险画像分化）----
	_run_multiwave("RADIAL 单核 A 路径 attrition=1.5", true, "A", 1.5)
	_run_multiwave("RADIAL 单核 A 路径 attrition=4.0", true, "A", 4.0)
	_run_multiwave("RADIAL 多塔 B 路径 attrition=1.5", true, "B", 1.5)
	_run_multiwave("RADIAL 多塔 B 路径 attrition=50（极端）", true, "B", 50.0)
	_run_multiwave("PATH 多塔 B 路径 attrition=1.5（对照）", false, "B", 1.5)

	# 回退
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	print("\n===================================================================")
	quit(0)


func _run_probe(label: String, radial: bool) -> void:
	# 八槽 cfg（n_slots=8）；单核 A 路径起手单塔，模拟"起手单暴露塔"
	var cfg: Dictionary = _Cfg.cfg_of("A")
	cfg["n_slots"] = 8

	var geo = _Geo8.build8()

	# 起手单塔（A 路径金标本口径：Arrow@slot0 h=1，由 SimPlayer.new_player 落塔）
	var player = _SimPlayer.new_player("A", cfg, geo)

	var w := 3
	var attrition: float = 1.5
	# 直接调战斗镜像（aggro_enabled=true, exp=0.6, attrition=1.5, warmup=0 让 W3 立即致命）
	var res := _WaveSimAggro.simulate_wave_aggro(
		player, w, cfg, geo, true, 0.6, attrition, 0, false, false, false)

	print("  [%s] W3 结果：" % label)
	print("    n(怪数)=%d · kills=%d · leaked=%d" % [
		int(res["n"]), int(res["kills"]), int(res["leaked"])])
	print("    towers_disabled=%d · dis_new=%d · dps=%.1f" % [
		int(res["towers_disabled"]), int(res["dis_new"]), float(res["dps"])])

	# 塔 HP 现状
	for t in player.towers:
		print("    塔 S%d h=%d hp=%.1f/%.1f disabled=%s" % [
			int(t.slot), int(t.h), float(t.hp), float(t.hp_max), str(bool(t.disabled))])

	# 径向模式下：打印怪物出生角与最近塔距离的几何自检
	if radial:
		print("  [%s] 几何自检（出生环 R_s=55 · 核心 28,28 · AGGRO_R=9）：" % label)
		var v0r := _SpaceModel.v0()
		print("    v0(radial)=%.2f u/s（=R_s/t_reach=55/10）" % v0r)
		# 取第一只怪的出生角，算它到最近塔的距离
		var theta0 := _SpaceModel.spawn_theta(0, w)
		var mpos := _SpaceModel.radial_pos_of_t(10.0, 1.0, theta0)  # t_remain=10 起始
		print("    怪#0 出生角 θ0=%.1f° · 起始 pos=(%.1f,%.1f)（rho=55）" % [
			rad_to_deg(theta0), mpos.x, mpos.y])
		# 找最近塔
		var best_d := 1e9
		var best_slot := -1
		for i in range(geo.slots.size()):
			var d := mpos.distance_to(geo.slots[i])
			if d < best_d:
				best_d = d
				best_slot = i
		print("    怪#0 起始时最近塔 = S%d · 距离=%.2f（AGGRO_R=9.0）" % [best_slot, best_d])
		# 怪行进到 rho=塔环半径时的最近距离：沿射线到核心的垂线距离 = r_t*sin(角差)
		print("    各塔到怪#0射线的最近距离（=r_t·sin|θ-θ_t|，≤9 才会 aggro）：")
		for i in range(geo.slots.size()):
			var sp: Vector2 = geo.slots[i]
			var r_t := sp.distance_to(_SpaceModel.core_pos())
			var ang_t := atan2(sp.y - _SpaceModel.core_pos().y, sp.x - _SpaceModel.core_pos().x)
			var ang_diff := fmod(ang_t - theta0, TAU)
			if ang_diff > PI:
				ang_diff -= TAU
			var perp: float = r_t * abs(sin(ang_diff))
			var mark := "  ← 可被怪#0锁定" if perp <= _MonsterData.AGGRO_R else ""
			print("      S%d r=%.1f 角差=%.0f° 垂距=%.2f%s" % [
				i, r_t, rad_to_deg(ang_diff), perp, mark])


# ---------------------------------------------------------------------------
# 多塔逐波诊断：用 RunLoopAggro.run 跑完整 B 路径，逐波打印塔死亡 / DPS / 秒杀情况
#   定位 scan8 全程 T-A=0 的根因（是否 B 多塔 DPS 过高 → 怪在接近塔前被全秒）。
# ---------------------------------------------------------------------------
func _run_multiwave(label: String, radial: bool, path: String, attrition: float = 1.5) -> void:
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL if radial else _SpaceModel.Mode.PATH

	var cfg: Dictionary = _Cfg.cfg_of(path)
	cfg["n_slots"] = 8
	cfg["max_actions"] = 12

	var rng := _PyRandom.new(20261002)
	var out := _RunLoopAggro.run(path, cfg, 20, null, rng, true, 0.6, attrition, 2)
	var rows: Array = out["rows"]

	print("\n  ---- [%s] B 路径逐波（attrition=%.1f, warmup=2）----" % [label, attrition])
	print("    %-3s %-6s %-9s %-7s %-7s %-7s %-4s" % [
		"W", "n", "dps", "kills", "leaked", "dis_new", "塔存"])
	for r in rows:
		print("    %-3d %-6d %-9.1f %-7d %-7d %-7d %-4d" % [
			int(r["w"]), int(r["n"]), float(r["eff_dps"]),
			int(r["kills"]), int(r["leaked"]), int(r.get("dis_new", 0)),
			int(r["towers"]) - int(r.get("towers_disabled", 0))])
	# 汇总
	var tot_dis := 0
	for r in rows:
		tot_dis += int(r.get("dis_new", 0))
	var last_core := float(rows[-1]["core_hp"]) if rows.size() > 0 else -1.0
	print("    → 全程累计 dis_new=%d · 末波 core_hp=%.1f · 塔死总数(存量)=%d" % [
		tot_dis, last_core, int(rows[-1].get("towers_disabled", 0)) if rows.size() > 0 else -1])
