extends RefCounted
## 战场地面轮廓与环境主题。坐标相对核心；绘制、出生边界、放置共用同一份多边形。
const CORE := Vector2(28, 28)
const MAP_SCALE := 1.5
const CAMERA_EXTENT := Vector2(76, 48) * MAP_SCALE

const MAPS := {
	"tri-fissure": {"theme": "relay", "ground": "34424a", "stone": "52616a", "accent": "63c4bd", "void": "111c25",
		"outline": [Vector2(-66,-24),Vector2(-52,-39),Vector2(-18,-39),Vector2(-18,-44),Vector2(24,-44),Vector2(24,-33),Vector2(62,-33),Vector2(70,-20),Vector2(70,19),Vector2(48,19),Vector2(48,36),Vector2(10,36),Vector2(10,42),Vector2(-38,42),Vector2(-38,29),Vector2(-66,29)]},
	"cinder-forge": {"theme": "furnace", "ground": "4d3931", "stone": "685147", "accent": "f6a454", "void": "241a1a",
		"outline": [Vector2(-68,-27),Vector2(-45,-27),Vector2(-45,-43),Vector2(12,-43),Vector2(12,-34),Vector2(60,-34),Vector2(70,-14),Vector2(58,25),Vector2(32,25),Vector2(32,43),Vector2(-22,43),Vector2(-22,33),Vector2(-61,33),Vector2(-68,14)]},
	"rime-station": {"theme": "ice", "ground": "6a828c", "stone": "a3bac1", "accent": "b4f0f0", "void": "203543",
		"outline": [Vector2(-68,-18),Vector2(-49,-38),Vector2(-11,-43),Vector2(15,-37),Vector2(47,-43),Vector2(68,-21),Vector2(61,6),Vector2(69,27),Vector2(37,40),Vector2(10,35),Vector2(-26,44),Vector2(-47,32),Vector2(-67,28),Vector2(-59,4)]},
	"rail-corridor": {"theme": "rail", "ground": "3f4548", "stone": "60676a", "accent": "dbb96b", "void": "151f27",
		"outline": [Vector2(-72,-21),Vector2(-39,-21),Vector2(-39,-38),Vector2(46,-38),Vector2(46,-27),Vector2(72,-27),Vector2(72,22),Vector2(41,22),Vector2(41,37),Vector2(-40,37),Vector2(-40,27),Vector2(-72,27)]},
	"arc-grid": {"theme": "electric", "ground": "354653", "stone": "516779", "accent": "77cfeb", "void": "101c2b",
		"outline": [Vector2(-64,-33),Vector2(-24,-33),Vector2(-24,-44),Vector2(24,-44),Vector2(24,-33),Vector2(64,-33),Vector2(64,-12),Vector2(72,-12),Vector2(72,18),Vector2(52,18),Vector2(52,38),Vector2(20,38),Vector2(20,43),Vector2(-30,43),Vector2(-30,30),Vector2(-64,30)]},
	"forge-union": {"theme": "factory", "ground": "4a4540", "stone": "72675b", "accent": "e6b66c", "void": "211d1c",
		"outline": [Vector2(-72,-30),Vector2(-26,-30),Vector2(-26,-43),Vector2(35,-43),Vector2(35,-30),Vector2(69,-30),Vector2(69,31),Vector2(28,31),Vector2(28,43),Vector2(-38,43),Vector2(-38,32),Vector2(-72,32)]},
	"bio-lab": {"theme": "garden", "ground": "3c514a", "stone": "63756a", "accent": "a6d68c", "void": "172824",
		"outline": [Vector2(-65,-28),Vector2(-43,-40),Vector2(-18,-35),Vector2(13,-44),Vector2(44,-36),Vector2(66,-28),Vector2(70,0),Vector2(60,29),Vector2(34,40),Vector2(7,35),Vector2(-24,43),Vector2(-58,30),Vector2(-70,8)]},
	"void-range": {"theme": "void", "ground": "413e54", "stone": "676079", "accent": "b5a0ed", "void": "181524",
		"outline": [Vector2(-71,-19),Vector2(-49,-37),Vector2(-20,-32),Vector2(0,-45),Vector2(27,-33),Vector2(56,-38),Vector2(69,-14),Vector2(57,8),Vector2(66,28),Vector2(29,37),Vector2(7,32),Vector2(-16,44),Vector2(-46,31),Vector2(-68,25),Vector2(-58,1)]},
	"overseer-ring": {"theme": "city", "ground": "3f494e", "stone": "637078", "accent": "e99378", "void": "171f27",
		"outline": [Vector2(-70,-28),Vector2(-44,-28),Vector2(-44,-43),Vector2(22,-43),Vector2(22,-32),Vector2(69,-32),Vector2(69,14),Vector2(55,14),Vector2(55,39),Vector2(8,39),Vector2(8,44),Vector2(-40,44),Vector2(-40,29),Vector2(-70,29)]},
	"overseer-core": {"theme": "citadel", "ground": "433d43", "stone": "70616b", "accent": "f18c78", "void": "21151e",
		"outline": [Vector2(-70,-20),Vector2(-51,-39),Vector2(-20,-39),Vector2(-20,-45),Vector2(22,-45),Vector2(22,-37),Vector2(53,-37),Vector2(70,-20),Vector2(70,20),Vector2(50,38),Vector2(20,38),Vector2(20,44),Vector2(-23,44),Vector2(-23,37),Vector2(-51,37),Vector2(-70,18)]},
}

static var _boundaries: Dictionary = {}
static var _obstacles: Dictionary = {}

static func profile(map_id: String) -> Dictionary:
	return MAPS.get(map_id, MAPS["tri-fissure"])

static func boundary(map_id: String) -> PackedVector2Array:
	if not _boundaries.has(map_id):
		var points := PackedVector2Array()
		for p in profile(map_id)["outline"]:
			points.append(CORE + p * MAP_SCALE)
		_boundaries[map_id] = points
	return _boundaries[map_id]

static func contains(map_id: String, point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, boundary(map_id))

## 将旧扇区障碍改成有直边的墙体/岩体；障碍保持在原有来敌方向之外。
static func obstacles(map_id: String, ridges: Array) -> Array:
	if not _obstacles.has(map_id):
		var polygons: Array = []
		for ridge in ridges:
			var a0 := deg_to_rad(float(ridge["a0"]))
			var a1 := deg_to_rad(float(ridge["a1"]))
			var inner := float(ridge["r0"]) * MAP_SCALE
			var outer := float(ridge["r1"]) * MAP_SCALE
			var p := PackedVector2Array([CORE + Vector2.from_angle(a0) * inner,
				CORE + Vector2.from_angle(a0) * outer, CORE + Vector2.from_angle(a1) * outer,
				CORE + Vector2.from_angle(a1) * inner])
			for clipped in Geometry2D.intersect_polygons(p, boundary(map_id)):
				polygons.append(clipped)
		_obstacles[map_id] = polygons
	return _obstacles[map_id]

static func blocked(map_id: String, point: Vector2, ridges: Array) -> bool:
	for polygon in obstacles(map_id, ridges):
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

## 核心射线与地块外沿相交，敌人出生于真实的非圆形边界。
static func entry_radius(map_id: String, theta: float) -> float:
	var direction := Vector2.from_angle(theta)
	var points := boundary(map_id)
	var nearest := 1000.0
	for i in range(points.size()):
		var a := points[i] - CORE
		var b := points[(i + 1) % points.size()] - CORE
		var edge := b - a
		var denominator := direction.cross(edge)
		if absf(denominator) < 0.000001:
			continue
		var t := a.cross(edge) / denominator
		var u := a.cross(direction) / denominator
		if t > 0.0 and u >= -0.000001 and u <= 1.000001:
			nearest = minf(nearest, t)
	return nearest if nearest < 1000.0 else 55.0
