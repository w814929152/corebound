extends SceneTree
##
## 阵地曝光静态自检（sim 盲区 · scene-map §11.2「曝光税」的几何真相）
##
## 🔴 为什么需要它：
##   sim（run_loop_aggro）的仇恨几何用 `_Geo6`/`_Geo8` 的 SLOTS6/8 曝光，**不认识 17 格阵地**。
##   所以「阵地化把曝光税抬了多少 / 孤台到底是不是低曝光」这条轴，300 局 MC 完全测不到。
##   本探针不跑战斗，只做**几何真相**：对全周 360° 密集采样出生角，
##   用 `probe_radial_aggro` 里已验证的锁定判据（垂距 = r_t·sin|θ−θ_t| ≤ AGGRO_R），
##   统计每个阵地「会被锁定的出生角弧长」= 曝光量。
##
## 回答两个问题：
##   Q1 孤台（r≈40–42）曝光是不是真的显著低于内圈台（r≈22–30）？低到「没人打」？
##   Q2 三座岩脊 + 出怪口映射（G）之后，曝光分布是否还合理（没有被岩脊「护」出一块免战区）？
##
## 跑法：
##   <godot> --headless --path . --script res://tests/probe_site_exposure.gd
##
## 判读口径：
##   · 曝光弧长越大 → 该台越危险（越容易被怪锁定 → 越常挨打）。
##   · 若孤台曝光 < 内圈台的 ~1/3，则 §9 失败信号 B（孤台无人问）成立 → 处方：孤台 1 格变 2 格
##     或造价 −2 废料（scene-map §9）。若差距 <2×，则孤台有正当存在理由（低风险高单价位）。

const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")


func _initialize() -> void:
	print("===================================================================")
	print("阵地曝光静态自检 · 17 格「三裂环」· 全周 360° 采样")
	print("===================================================================")

	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var core := _SpaceModel.core_pos()
	var agg_r: float = _MonsterData.AGGRO_R

	# 采样步长：0.25° → 1440 个出生角，弧长分辨率足够量化曝光。
	const STEP_DEG := 0.25
	const N := int(360.0 / STEP_DEG)

	# 每个阵地：被锁定采样点数（= 曝光弧长，单位 deg，N 点 × 0.25°）
	var exposure := {}          # id -> int（锁定采样数）
	var site_ids: Array = []
	for s in _BuildGrid.SITES:
		site_ids.append(String(s["id"]))

	# 采样：对每个出生角，找**所有**会被锁定的台（一只怪只锁定最近可达的塔，
	# 但曝光自检的语义是「这个角度的怪会不会打这个台」——这里统计「任一会被锁定」即可，
	# 与 probe_radial_aggro 的垂距判据一致）。
	for i in range(N):
		var deg: float = float(i) * STEP_DEG
		# 直接用**逻辑出生角**（未过 G 映射），因为锁定判据用的是几何角度差；
		# 岩脊/映射改变的是「哪个角会出生」，我们最后单独做「映射后」的口径。
		var th := deg * PI / 180.0
		for id in site_ids:
			var pts: Array = _BuildGrid.site_cells(id)
			# 一个阵地多格 → 取「该台内离射线最近的那格」的垂距，代表这座台的锁定条件
			var min_perp := 1e9
			for p in pts:
				var pp: Vector2 = p
				var r_t := pp.distance_to(core)
				var ang_t := atan2(pp.y - core.y, pp.x - core.x)
				var ang_diff := fmod(ang_t - th, TAU)
				if ang_diff > PI:
					ang_diff -= TAU
				var perp: float = r_t * abs(sin(ang_diff))
				if perp < min_perp:
					min_perp = perp
			if min_perp <= agg_r:
				exposure[id] = int(exposure.get(id, 0)) + 1

	# ---- 输出：每个阵地曝光弧长 + 归一化 ----
	print("\n  阵地曝光（全周 1440 采样 · 每点 0.25° · AGGRO_R=%.1f）：" % agg_r)
	print("  %-4s %-6s %-8s %-10s %-8s" % ["id", "格数", "r(格心距)", "曝光弧长°", "占比%"])
	var total := 0.0
	var rows: Array = []
	for id in site_ids:
		var n_pts: int = _BuildGrid.site_cells(id).size()
		var pts: Array = _BuildGrid.site_cells(id)
		var r_avg := 0.0
		for p in pts:
			var pp: Vector2 = p
			r_avg += pp.distance_to(core)
		r_avg /= float(pts.size())
		var exp: int = int(exposure.get(id, 0))
		total += float(exp)
		rows.append([id, n_pts, r_avg, exp])
	for r in rows:
		var pct := float(r[3]) / total * 100.0 if total > 0 else 0.0
		print("  %-4s %-6d %-8.2f %-10d %-7.1f%%" % [r[0], r[1], r[2], r[3], pct])

	# ---- Q1：孤台 vs 内圈台 ----
	print("\n  ---- Q1：孤台是不是低曝光「没人打」？ ----")
	var n_exp := float(exposure.get("N1", 0) + exposure.get("N2", 0) + exposure.get("N3", 0)) / 3.0
	var p_exp := float(exposure.get("P1", 0) + exposure.get("P2", 0) + exposure.get("P3", 0)) / 3.0
	print("    孤台(N1–N3) 平均曝光 = %.0f° · 内圈台(P1–P3) 平均曝光 = %.0f°" % [n_exp, p_exp])
	var ratio := n_exp / p_exp if p_exp > 0 else 0.0
	print("    孤台/内圈 曝光比 = %.2f（<0.33 → §9 信号 B「孤台无人问」成立；>0.5 → 正当低风险位）" % ratio)

	# ---- Q2：岩脊 + 映射后的真实出生分布 ----
	print("\n  ---- Q2：岩脊 + G 映射后，怪物实际会从哪些角出生？ ----")
	# 映射后：取 400 个黄金角（W1..W20 × index），统计落脊率 + 各口占比
	var ridge_hit := 0
	var total_spawn := 400
	var arc_hit := {"A": 0, "B": 0, "C": 0}
	for w in range(1, 21):
		for idx in range(20):
			var th_deg := _SpaceModel.map_theta_deg(
				fmod(float(w) * 37.0 + float(idx) * 137.508, 360.0))
			if _SpaceModel.is_ridge_deg(th_deg):
				ridge_hit += 1
			for arc in _SpaceModel.SPAWN_ARCS:
				var a0 := float(arc["a0"])
				var a1 := float(arc["a1"])
				if th_deg >= a0 and th_deg < a1:
					arc_hit[String(arc["id"])] = int(arc_hit[String(arc["id"])]) + 1
	print("    落脊率 = %d/%d = %.1f%%（应为 0）" % [ridge_hit, total_spawn, 100.0 * ridge_hit / total_spawn])
	for arc in _SpaceModel.SPAWN_ARCS:
		var id := String(arc["id"])
		var cnt := int(arc_hit[id])
		var span := float(arc["a1"]) - float(arc["a0"])
		var expected := total_spawn * span / 360.0
		print("    口 %s：实际 %d 只（%.1f%%）· 按弧长期望 %.0f 只（%.1f°）" % [
			id, cnt, 100.0 * cnt / total_spawn, expected, span])

	# 回退
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	print("\n===================================================================")
	quit(0)
