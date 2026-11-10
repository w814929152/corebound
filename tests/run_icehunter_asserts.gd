extends SceneTree
const Helper = preload("res://tests/run_fire_charge_asserts.gd")
const TC = preload("res://scripts/gameplay/tactical_combat.gd")
const CT = preload("res://scripts/data/combat_types.gd")
var failed := 0
func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failed += 1
func _initialize() -> void:
	quit(0 if run_all() else 1)
func run_all() -> bool:
	var h = Helper.new()
	var d = h.make_battle(["Icehunter"])
	d.combat_types_enabled = true
	d.monsters[1].proto = "Rush"
	d.monsters[1].frozen_remaining = 2.0
	TC.apply_in_range(d, Vector2.ZERO, 22.0, 10.0, CT.MAGIC, 0.0, true)
	check("frozen priority and magic resistance bypass", d.monsters[0].hp == 1000.0 and d.monsters[1].hp == 990.0)
	d.monsters[1].frozen_remaining = 0.0
	d.monsters[0].hp = 0.0
	TC.apply_in_range(d, Vector2.ZERO, 22.0, 10.0, CT.MAGIC, 0.0, true)
	check("thawed target uses resistance", d.monsters[1].hp == 982.0)
	d.monsters[1].frost_stacks = 9
	TC.apply_in_range(d, Vector2.ZERO, 22.0, 10.0, CT.MAGIC, 0.0, true)
	check("slow stacks alone do not bypass resistance", d.monsters[1].hp == 974.0)
	d.monsters[1].hp = 982.0
	d.monsters[1].frozen_remaining = 2.0
	d.monsters[1].proto = "Tank"
	TC.apply_in_range(d, Vector2.ZERO, 22.0, 10.0, CT.PHYSICAL, 0.0, true)
	check("physical conversion still bypasses resistance", d.monsters[1].hp == 972.0)
	d.monsters[1].location = Vector2(200, 0)
	TC.apply_in_range(d, Vector2.ZERO, 22.0, 10.0, CT.MAGIC, 0.0, true)
	check("frozen outside range cannot be hit", d.monsters[1].hp == 972.0)
	d.monsters[1].location = Vector2.ZERO
	d.monsters[0].hp = 1000.0
	d.monsters[1].hp = 5.0
	TC.apply_in_range(d, Vector2.ZERO, 22.0, 10.0, CT.MAGIC, 0.0, true)
	check("overflow returns to ordinary in-range target", d.monsters[1].hp == 0.0 and d.monsters[0].hp == 955.0)
	d.free()
	d = h.make_battle(["Icehunter"])
	d.geo = preload("res://scripts/geo/geo.gd").new([Vector2.ZERO])
	d.monsters[1].frozen_remaining = 2.0
	TC.apply(d, 1.0)
	check("real tower path prioritizes frozen", d.monsters[0].hp == 1000.0 and d.monsters[1].hp < 1000.0)
	d.free()
	h.free()
	return failed == 0
