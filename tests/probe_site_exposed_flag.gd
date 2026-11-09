extends SceneTree
##
## 阵地「暴露位」旗标自检 —— 只回答一件事：真身 `_PathGeometry.slot_exposure_radial`
## 对**17 格阵地**判出来的 `is_exposed` 是什么？
##
## 🔴 为什么必须查：复活资格（`death_exposed`）硬依赖这个旗标 ——
##   `要复活 ⟺ death_valid ∧ is_exposed ∧ ¬is_carry`（`wave_director.gd:861`）。
##   若 17 格全判 false，则产品开关 `combat_revive_enabled` 在实机**等于没开**，
##   而批处理镜像（`_Geo6.SLOTS6` 六槽）仍判 true → MC 产品臂与实机机制不同。
##
## 跑法：<godot> --headless --path . --script res://tests/probe_site_exposed_flag.gd
##

const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")


func _initialize() -> void:
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var R: float = _MonsterData.AGGRO_R
	var core: Vector2 = _SpaceModel.core_pos()
	print("===================================================================")
	print("暴露位旗标 · AGGRO_R=%.1f · EXPO_SAFE_MAX=%.2f · core=%s"
		% [R, _PathGeometry.EXPO_SAFE_MAX, str(core)])
	print("===================================================================")
	var pts: Array = _BuildGrid.site_points()
	var rows: Array = _PathGeometry.slot_exposure_radial(pts, R, core,
		_PathGeometry.EXPO_SAFE_MAX)
	var n_exposed := 0
	var out := ""
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		var exposed := bool(r["is_exposed"])
		if exposed:
			n_exposed += 1
		if i < 12 or exposed:
			out += "  #%-2d pos=(%.1f,%.1f) d=%.2f expo=%.3f exposed=%s\n" % [
				i, pts[i].x, pts[i].y,
				float(r.get("d_core", _PathGeometry.dist_to_core(pts[i], core))),
				float(r.get("expo_frac", -1.0)), str(exposed)]
	print("  阵地格心 %d 个 → 暴露 %d 个 / 安全 %d 个" % [pts.size(), n_exposed, pts.size() - n_exposed])
	print(out)
	# 对照：金标本六槽（镜像 MC 用的那套）
	var rows6: Array = _PathGeometry.slot_exposure_radial(_Geo6.SLOTS6, R, core,
		_PathGeometry.EXPO_SAFE_MAX)
	var e6 := 0
	for r6 in rows6:
		if bool(r6["is_exposed"]):
			e6 += 1
	print("  对照 · Geo6.SLOTS6（镜像 MC 口径）→ 暴露 %d / %d" % [e6, rows6.size()])
	# 🆕 现行分派：阵地化开启时用 EXPO_SAFE_MAX_SITES（0.085）
	var rows_s: Array = _PathGeometry.slot_exposure_radial(pts, R, core,
		_PathGeometry.expo_safe_max_for(true))
	var es := 0
	for rs in rows_s:
		if bool(rs["is_exposed"]):
			es += 1
	print("  现行分派（sites_active=true · 阈值 %.3f）→ 暴露 %d / %d"
		% [_PathGeometry.expo_safe_max_for(true), es, rows_s.size()])
	print("===================================================================")
	quit(0)
