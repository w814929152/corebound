extends SceneTree
##
## 探针：验证 StackCap+ 增益的实际 DPS 效应（献祭玩法③ 落地校验）。
##   回答：cap=100 很高，StackCap+ 只在**单塔同 Tag 层数 > 100**（衰减段）才生效。
##   探测不同层数下 bonus=10/25 的 DPS 增幅，判定 StackCap+ 是否为有意义的增益。
##
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _PS := preload("res://scripts/engine/player_state.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")


func _initialize() -> void:
	var geo = _Geo6.build()
	var cfg = _Cfg.cfg_of("A")
	print("reinf_cap = ", cfg.get("reinf_cap"))
	print("softcap_decay = ", cfg.get("softcap_decay"))
	print("")
	print("Cannon(fire) + FireUp 层数 → DPS 随 StackCap+ 变化：")
	print("  lv  :  dps(bonus=0)  dps(bonus=10)  dps(bonus=25)  Δ10%  Δ25%")
	for lv in [20, 50, 100, 120, 150, 200]:
		var d0 := _dps(cfg, geo, lv, 0.0)
		var d10 := _dps(cfg, geo, lv, 10.0)
		var d25 := _dps(cfg, geo, lv, 25.0)
		var p10 := (d10 / d0 - 1.0) * 100.0 if d0 > 0.0 else 0.0
		var p25 := (d25 / d0 - 1.0) * 100.0 if d0 > 0.0 else 0.0
		print("  %3d :  %10.3f  %11.3f  %12.3f  %+6.2f  %+6.2f"
			% [lv, d0, d10, d25, p10, p25])
	print("")
	print("▶ 结论：StackCap+ 仅在单塔同 Tag 层数 > cap(100) 的衰减段才有 DPS 效应。")
	quit(0)


func _dps(cfg: Dictionary, geo, lv: int, bonus: float) -> float:
	var p = _SimPlayer.new_player("A", cfg, geo)
	p.towers = []
	var t := _PS.make_tower(0, "Cannon", lv, {})
	p.towers.append(t)
	p.stackcap_bonus = bonus
	# Cannon=fire tag；FireUp 是同 tag 强化卡 → 进 Stack 乘区（受 cap 约束）
	t.attach["FireUp"] = lv
	return float(_DE.dps_only(p, cfg, geo))
