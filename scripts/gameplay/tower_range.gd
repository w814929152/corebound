extends RefCounted

const TD := preload("res://scripts/data/tower_data.gd")

const Profiles := preload("res://scripts/data/tower_range_profiles.gd")

static func profile(card: String, merges: int = 0, enabled: bool = true) -> Vector2:
	var data: Array = Profiles.PROFILES.get(card, [])
	if not enabled or data.is_empty():
		return Vector2(TD.tower_rng(card), TAU)
	if float(data[0]) <= 0.0:
		return Vector2(0.0, TAU)
	var growth := clampi(merges, 0, int(data[4]))
	return Vector2(float(data[0]) + float(data[2]) * growth,
		deg_to_rad(float(data[1]) + float(data[3]) * growth))


static func maximum(card: String) -> Vector2:
	var data: Array = Profiles.PROFILES.get(card, [])
	return profile(card, int(data[4]) if not data.is_empty() else 0)


static func contains(offset: Vector2, radius: float, angle: float = TAU, facing: float = 0.0) -> bool:
	return offset.length_squared() <= radius * radius and (
		angle >= TAU or offset.is_zero_approx() or absf(angle_difference(facing, offset.angle())) <= angle * 0.5 + 0.000001)


static func active_auras(towers: Array, geometry, enabled: bool = true,
		moved_slot: int = -1, destination: Vector2 = Vector2.ZERO) -> Array:
	var auras: Array = []
	if not enabled or geometry == null:
		return auras
	for tower in towers:
		var slot := int(tower.slot)
		if tower.disabled or slot < 0 or slot >= geometry.slots.size():
			continue
		var aura := TD.tower_range_aura(String(tower.ctype))
		if aura.is_empty():
			continue
		var layers := int(tower.h)
		auras.append({
			"center": destination if slot == moved_slot else geometry.slots[slot],
			"radius": float(aura["radius"]),
			"bonus": Vector2(float(aura.get("attack_radius", 0.0)), deg_to_rad(float(aura.get("angle_degrees", 0.0)))) * layers,
		})
	return auras


static func with_auras(coverage: Vector2, center: Vector2, auras: Array) -> Vector2:
	if coverage.x <= 0.0:
		return coverage
	for aura in auras:
		var offset: Vector2 = center - aura["center"]
		if contains(offset, aura["radius"]):
			coverage += Vector2(aura["bonus"])
	coverage.y = minf(TAU, coverage.y)
	return coverage
