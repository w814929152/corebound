extends RefCounted

const TD := preload("res://scripts/data/tower_data.gd")

static func profile(card: String, merges: int = 0, enabled: bool = true) -> Vector2:
	if enabled:
		match card:
			"Sniper":
				return Vector2(minf(56.0, 44.0 + 3.0 * merges), deg_to_rad(40.0))
			"Ember":
				return Vector2(14.0, deg_to_rad(minf(150.0, 100.0 + 10.0 * merges)))
			"Arrow":
				return Vector2(TD.tower_rng(card) + minf(4.0, float(merges)), TAU)
	return Vector2(TD.tower_rng(card), TAU)

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
