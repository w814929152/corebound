extends RefCounted
## 有边界的场景地形：地块断面、铺装、道路、遗迹。纯绘制，地面/障碍共用玩法数据。
const Maps := preload("res://scripts/data/battlefield_maps.gd")
const Space := preload("res://scripts/geo/space_model.gd")
static var _cache: Dictionary = {}

class Painter extends RefCounted:
	var commands: Array = []
	var outline: PackedVector2Array
	var floor_color: Color
	var stone: Color
	var accent: Color
	var theme: String

	func polygon(points: PackedVector2Array, color: Color, clip: bool = true) -> void:
		if clip:
			for fragment in Geometry2D.intersect_polygons(points, outline):
				if fragment.size() >= 3:
					commands.append([0, fragment, color, 0.0])
		else:
			commands.append([0, points, color, 0.0])

	func line(points: PackedVector2Array, color: Color, width: float = 0.12) -> void:
		commands.append([1, points, color, width])

	func box(rect: Rect2, color: Color, cut: float = 0.0) -> void:
		var p := rect.position
		var e := rect.end
		polygon(PackedVector2Array([p + Vector2(cut,0),Vector2(e.x-cut,p.y),Vector2(e.x,p.y+cut),
			e-Vector2(0,cut),e-Vector2(cut,0),Vector2(p.x+cut,e.y),Vector2(p.x,e.y-cut),p+Vector2(0,cut)]), color)

	func shifted(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
		var result := PackedVector2Array()
		for p in points:
			result.append(p + offset)
		return result

	func closed(points: PackedVector2Array) -> PackedVector2Array:
		var result := points.duplicate()
		result.append(points[0])
		return result

	func road(end: Vector2, width: float) -> void:
		var direction := end.normalized()
		var normal := Vector2(-direction.y, direction.x)
		var start := direction * 10.0
		polygon(PackedVector2Array([start - normal * width, end - normal * width,
			end + normal * width, start + normal * width]), floor_color.darkened(0.29))
		polygon(PackedVector2Array([start - normal * (width-0.5), end - normal * (width-0.5),
			end + normal * (width-0.5), start + normal * (width-0.5)]), floor_color.darkened(0.15))
		for k in range(3, int(end.length()/4.0)):
			var a := direction * float(k) * 4.0
			line(PackedVector2Array([a-normal*0.12,a+direction*1.5-normal*0.12]), Color(stone,0.40),0.13)
		for side in [-1.0, 1.0]:
			var offset: Vector2 = normal * (width - 0.7) * float(side)
			line(PackedVector2Array([start+offset,end+offset]), Color(stone,0.34),0.13)

	func build(map_id: String) -> Array:
		var profile: Dictionary = Maps.profile(map_id)
		floor_color = Color.html(profile["ground"])
		stone = Color.html(profile["stone"])
		accent = Color.html(profile["accent"])
		theme = String(profile["theme"])
		outline = PackedVector2Array(profile["outline"])
		# 远处的断桥和遗构让地块位于环境中；不会成为可建地面。
		for k in range(outline.size()):
			var p: Vector2 = outline[k]
			var q: Vector2 = outline[(k+1)%outline.size()]
			if p.distance_to(q) < 18.0:
				continue
			var center := (p+q)*0.5
			var dir := (q-p).normalized()
			var normal := center.normalized()
			var a := center + normal*5.0
			var span := minf(12.0,p.distance_to(q)*0.30)
			polygon(PackedVector2Array([a-dir*span,a+dir*span,a+dir*span+normal*11.0,
				a-dir*span+normal*8.0]), floor_color.darkened(0.66),false)
			line(PackedVector2Array([a-dir*span,a+dir*span]),Color(stone,0.22),0.3)
			var apex := a+normal*5.0+Vector2(-2.0,-2.0)
			polygon(PackedVector2Array([a-dir*span,a+dir*span,apex]),floor_color.darkened(0.45),false)
			polygon(PackedVector2Array([a+dir*span,a+dir*span+normal*11.0,apex]),floor_color.darkened(0.58),false)
		# 地块的落影、垂直断面和顶沿，而非圆形底盘。
		polygon(shifted(outline,Vector2(1.5,5.0)),Color(0.0,0.0,0.0,0.27),false)
		polygon(shifted(outline,Vector2(0.0,2.8)),floor_color.darkened(0.66),false)
		polygon(outline,floor_color,false)
		for i in range(outline.size()):
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[(i+1)%outline.size()]
			if b.x < a.x:
				polygon(PackedVector2Array([a,b,b+Vector2(0,2.8),a+Vector2(0,2.8)]),floor_color.darkened(0.45),false)
		# 不规则板块的表面变化：低对比石板、破损接缝与泥土，不是永久摆塔网格。
		for y in range(-5,6):
			for x in range(-9,10):
				var n := fposmod(float(x*137+y*53),17.0)/17.0
				var p := Vector2(float(x)*8.0 + (3.0 if y%2 == 0 else 0.0),float(y)*8.0)
				var tint := floor_color.lerp(stone,0.06+n*0.10)
				box(Rect2(p,Vector2(7.75,7.7)),tint,0.35)
		for k in range(75):
			var p := Vector2(fposmod(float(k)*43.71,132.0)-66.0,fposmod(float(k)*23.17,80.0)-40.0)
			var size := 0.15 + fposmod(float(k)*0.37,0.65)
			if Geometry2D.is_point_in_polygon(p,outline):
				box(Rect2(p,Vector2(size*2.0,size)),floor_color.lerp(stone,0.18),0.1)
		# 入口道路止于真实边界；保持宽阔的自由布防地面。
		for arc in Space.active_spawn_arcs():
			var angle := deg_to_rad((float(arc["a0"])+float(arc["a1"]))*0.5)
			var end := Vector2.from_angle(angle)*(Maps.entry_radius(map_id,angle)/Maps.MAP_SCALE-1.2)
			road(end,3.2 if theme != "garden" else 4.3)
		add_theme_details()
		# 中央接线庭院，使用矩形装甲和四侧连接槽，不再围绕核心叠大圆环。
		box(Rect2(-12.0,-10.0,24.0,20.0),floor_color.darkened(0.45),2.5)
		box(Rect2(-10.8,-8.8,21.6,17.6),stone.darkened(0.25),2.0)
		box(Rect2(-9.7,-7.7,19.4,15.4),floor_color.lightened(0.035),1.5)
		for side in [-1.0,1.0]:
			for y in [-4.0,0.0,4.0]:
				box(Rect2(Vector2(side*10.4-0.22,y-0.7),Vector2(0.44,1.4)),Color(accent,0.65),0.1)
		# 石墙、设备外壳与崖体与玩法使用相同多边形，顶面不能摆塔。
		for world_poly in Maps.obstacles(map_id,Space.active_ridges()):
			var poly := PackedVector2Array()
			for point in world_poly:
				poly.append((point-Maps.CORE)/Maps.MAP_SCALE)
			var rock := stone.darkened(0.05)
			polygon(shifted(poly,Vector2(1.4,2.4)),Color(0,0,0,0.40))
			polygon(poly,rock.darkened(0.53))
			var top := shifted(poly,Vector2(-0.35,-1.0))
			polygon(top,rock)
			add_roof_details(top,rock)
			line(closed(top),Color(rock.lightened(0.22),0.75),0.22)
			if theme == "furnace" or theme == "void":
				line(PackedVector2Array([top[0],top[1]]),Color(accent,0.55),0.35)
			else:
				for i in range(poly.size()):
					var a: Vector2 = top[i]
					var b: Vector2 = top[(i+1)%poly.size()]
					if a.distance_to(b)>8.0:
						var mid := a.lerp(b,0.48)
						line(PackedVector2Array([mid,mid+Vector2(0.2,0.6),mid.lerp(a,0.15)+Vector2(0.1,0.8)]),Color(rock.darkened(0.6),0.65),0.18)
		# 低矮护沿使用断续石块，留出宽阔入口，没有完整的包围圈。
		for k in range(outline.size()):
			var a: Vector2 = outline[k]
			var b: Vector2 = outline[(k+1)%outline.size()]
			var length := a.distance_to(b)
			line(PackedVector2Array([a,b]),Color(stone.lightened(0.08),0.65),0.30)
			for j in range(1,int(length/4.0)):
				var p := a.lerp(b,float(j)*4.0/length)
				var inward := -p.normalized()*0.7
				var direction := (b-a).normalized()
				line(PackedVector2Array([p+inward,p+inward+direction*1.4]),Color(stone.lightened(0.22),0.6),0.5)
		# 设计坐标整体扩大；绘制与真实地块、障碍保持相同世界尺寸。
		for command in commands:
			var points: PackedVector2Array = command[1]
			for i in range(points.size()):
				points[i] *= Maps.MAP_SCALE
			command[1] = points
			command[3] = float(command[3]) * Maps.MAP_SCALE
		return commands

	## 遗迹有屋面接缝、通风格栅或岩层切面，区分于下方可建的平坦铺装。
	func add_roof_details(top: PackedVector2Array, roof: Color) -> void:
		var center := Vector2.ZERO
		var bounds := Rect2(top[0],Vector2.ZERO)
		for point in top:
			center += point
			bounds = bounds.expand(point)
		center /= float(top.size())
		var inner := PackedVector2Array()
		for point in top:
			inner.append(point.lerp(center,0.12))
		if theme == "ice" or theme == "void" or theme == "garden":
			for i in range(inner.size()):
				var shade := roof.lightened(0.13) if i%2 == 0 else roof.darkened(0.10)
				polygon(PackedVector2Array([inner[i],inner[(i+1)%inner.size()],center]),shade)
			if theme == "garden":
				polygon(inner,roof.lerp(accent,0.25))
				for k in range(4):
					var p := center.lerp(inner[k%inner.size()],0.5)
					polygon(PackedVector2Array([p+Vector2(-1.2,0),p+Vector2(0,-1),p+Vector2(1.3,0),p+Vector2(0,0.6)]),Color(accent,0.48))
			return
		polygon(inner,roof.darkened(0.16))
		line(closed(inner),Color(roof.lightened(0.28),0.5),0.14)
		var horizontal := bounds.size.x>bounds.size.y
		var direction := Vector2.RIGHT if horizontal else Vector2.DOWN
		var normal := Vector2.DOWN if horizontal else Vector2.RIGHT
		var length := maxf(bounds.size.x,bounds.size.y)*0.65
		for k in range(-int(length/3.2),int(length/3.2)+1):
			var p := center+direction*float(k)*1.6
			var panel := PackedVector2Array([p-direction*0.35-normal*2.0,p+direction*0.35-normal*2.0,
				p+direction*0.35+normal*2.0,p-direction*0.35+normal*2.0])
			for fragment in Geometry2D.intersect_polygons(panel,inner):
				polygon(fragment,roof.darkened(0.38))
		# 小型检修盖与暖色状态灯，不与塔的青色轮廓争夺注意力。
		var hatch := PackedVector2Array([center+Vector2(-1.7,-1.1),center+Vector2(1.7,-1.1),
			center+Vector2(1.7,1.1),center+Vector2(-1.7,1.1)])
		for fragment in Geometry2D.intersect_polygons(hatch,inner):
			polygon(fragment,roof.lightened(0.15))
		line(PackedVector2Array([center+Vector2(-0.7,0),center+Vector2(0.7,0)]),Color(accent,0.6),0.25)

	func add_theme_details() -> void:
		match theme:
			"relay":
				for x in [-36.0,29.0]:
					box(Rect2(x,-25,16,12),stone.darkened(0.35),1.3)
					box(Rect2(x+1,-24,14,10),floor_color.lightened(0.06),1.0)
					for k in range(3):
						box(Rect2(x+3+float(k)*3.7,-22,2.0,6),Color(accent,0.12),0.3)
				for y in [-18.0,20.0]:
					line(PackedVector2Array([Vector2(-43,y),Vector2(-17,y),Vector2(-17,y*0.5)]),Color(accent,0.32),0.26)
			"rail":
				for y in [-17.0,15.0]:
					box(Rect2(-68,y-3.2,136,6.4),floor_color.darkened(0.36),0.0)
					for x in range(-63,65,3):
						box(Rect2(float(x),y-2.9,0.65,5.8),stone.darkened(0.28))
					for offset in [-1.9,1.9]:
						box(Rect2(-66,y+offset-0.14,132,0.28),stone.lightened(0.28))
				for x in [-43.0,34.0]:
					box(Rect2(x,-9.5,12,19),stone.darkened(0.12),0.8)
					for k in range(6):
						box(Rect2(x+1+float(k)*1.8,-9,0.7,1.8),accent.darkened(0.2))
			"furnace":
				for x in [-42.0,35.0]:
					box(Rect2(x-3,-31,6,63),floor_color.darkened(0.55),0.8)
					box(Rect2(x-1.5,-30,3.0,61),Color(accent,0.20),0.3)
					box(Rect2(x-0.8,-30,1.6,61),Color(accent,0.70),0.3)
					box(Rect2(x-0.25,-29,0.50,59),Color(1.0,0.77,0.35,0.70),0.1)
					for y in range(-27,30,5):
						box(Rect2(x-3.5,float(y),7,0.8),stone.darkened(0.13))
				for y in [-27.0,27.0]:
					box(Rect2(-19,y-3,38,6),floor_color.darkened(0.3),0.5)
			"ice":
				for i in range(22):
					var x := fposmod(float(i)*23.7,130.0)-65.0
					var y := fposmod(float(i)*31.1,78.0)-39.0
					polygon(PackedVector2Array([Vector2(x,y),Vector2(x+9,y-2),Vector2(x+15,y+2),Vector2(x+5,y+6)]),Color(stone.lightened(0.15),0.33))
				for x in [-31.0,29.0]:
					line(PackedVector2Array([Vector2(x,-34),Vector2(x-7,-14),Vector2(x-3,0),Vector2(x-12,28)]),Color(accent,0.40),0.25)
			"electric":
				for x in [-43.0,39.0]:
					for y in [-27.0,22.0]:
						box(Rect2(x-6,y-4,12,8),stone.darkened(0.15),0.8)
						for k in range(4):
							box(Rect2(x-4+float(k)*2.4,y-2,0.8,4),Color(accent,0.33),0.2)
					line(PackedVector2Array([Vector2(x,-30),Vector2(x,0),Vector2(x*0.40,0)]),Color(accent,0.40),0.35)
			"factory":
				for x in [-49.0,33.0]:
					box(Rect2(x,-28,16,55),floor_color.darkened(0.3),0.5)
					for y in range(-23,26,6):
						box(Rect2(x+1,float(y),14,4.5),stone.darkened(0.17),0.4)
						box(Rect2(x+2,float(y)+0.5,1.0,3.5),accent.darkened(0.2))
				for y in [-31.0,31.0]:
					box(Rect2(-29,y-1.0,57,2),Color(accent,0.28),0.2)
			"garden":
				for i in range(18):
					var x := fposmod(float(i)*27.31,128.0)-64.0
					var y := fposmod(float(i)*19.7,74.0)-37.0
					polygon(PackedVector2Array([Vector2(x-5,y),Vector2(x,y-4),Vector2(x+8,y-1),Vector2(x+9,y+5),Vector2(x-3,y+7)]),Color(0.22,0.36,0.25,0.45))
				for x in [-40.0,29.0]:
					box(Rect2(x,-25,11,51),stone.darkened(0.3),0.8)
					for y in range(-21,25,8):
						box(Rect2(x+1,float(y),9,5.5),floor_color.lerp(accent,0.14),0.5)
						for k in range(4):
							box(Rect2(x+2+float(k)*1.9,float(y)+0.8,0.5,3.8),Color(accent,0.20),0.2)
			"void":
				for x in [-45.0,30.0]:
					polygon(PackedVector2Array([Vector2(x,-35),Vector2(x+8,-11),Vector2(x+2,8),Vector2(x+12,34),Vector2(x+8,35),Vector2(x-2,8),Vector2(x+4,-11)]),floor_color.darkened(0.55))
					line(PackedVector2Array([Vector2(x,-34),Vector2(x+6,-11),Vector2(x,8),Vector2(x+10,33)]),Color(accent,0.45),0.27)
				for y in [-24.0,22.0]:
					box(Rect2(-18,y-4,36,8),stone.darkened(0.20),2.0)
			"city":
				for x in [-48.0,26.0]:
					for y in [-28.0,15.0]:
						box(Rect2(x,y,22,14),stone.darkened(0.3),0.7)
						box(Rect2(x+1,y+1,20,12),floor_color.lightened(0.06),0.4)
						for k in range(4):
							box(Rect2(x+3+float(k)*4.2,y+3,2.5,7.0),stone.darkened(0.12),0.3)
				for y in [-9.0,9.0]:
					box(Rect2(-60,y-1,120,2),Color(accent,0.15),0.2)
			"citadel":
				for side in [-1.0,1.0]:
					for y in [-29.0,23.0]:
						box(Rect2(side*39-14,y-3,28,7),stone.darkened(0.18),1.5)
						box(Rect2(side*39-11,y-1.5,22,0.6),Color(accent,0.48),0.2)
					line(PackedVector2Array([Vector2(side*60,-22),Vector2(side*27,-22),Vector2(side*20,-14)]),Color(accent,0.4),0.5)

static func draw(canvas: Node2D, center: Vector2, scale: float) -> void:
	var map_id := Space.active_map_id
	if not _cache.has(map_id):
		_cache[map_id] = Painter.new().build(map_id)
	canvas.draw_set_transform(center,0.0,Vector2(scale,scale))
	for command in _cache[map_id]:
		if int(command[0]) == 0:
			canvas.draw_colored_polygon(command[1],command[2])
		else:
			canvas.draw_polyline(command[1],command[2],float(command[3]),true)
	canvas.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
