extends Node2D
##
## 怪物 / 路径 / 塔位 **占位渲染层**（Node2D，世界层）
##
## 🔴 MVP 只做**占位可视化**（主理人决策 5：**不做美术渲染**，那是后续切片）：
##    · 路径：5 段折线（灰褐色粗线）+ 6 个路径点；
##    · 核心：路径终点 (55,25) 的实心方块；
##    · 塔位：空心圆；`d_path ≤ 9.0` 的暴露位外圈画一圈红环（🔴 GDD：MVP 只登记数据，
##      不产出玩法 → 这里只是"把静态事实画出来"，不给任何推荐）；
##    · 怪物：按原型上色 / 尺寸的实心圆 —— **Rush 小快 / Swarm 中 / Tank 大慢**，
##      Elite 加一圈黄环。
##
## 🔴 分层纪律（control-manifest §5）：本节点**只读** `WaveDirector.snapshot()`，
##    不写任何玩法状态，也不发意图信号。process_mode = INHERIT（随暂停停 →
##    安全窗冻结画面，这正是 W-C3 想要的"完全静止"）。
##
## 坐标：世界 XZ 平面（x ∈ [0,55]，z ∈ [16,48]）→ 屏幕像素。
##   映射 = 等比缩放 + 居中（保比例，不拉伸），与 `art-bible` §6.1 的等距投影无关（占位）。
##
## ⚠️ G6：headless 无 global_script_class_cache → 不写 class_name。
##

const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")

const MARGIN := 48.0
const C_PATH := Color(0.34, 0.30, 0.22, 1.0)
const C_PATH_DOT := Color(0.55, 0.48, 0.32, 1.0)
const C_CORE := Color(0.35, 0.85, 0.95, 1.0)
const C_SLOT := Color(0.45, 0.50, 0.55, 0.85)
const C_EXPOSE := Color(0.95, 0.30, 0.25, 0.75)
# 🔒 T1 H10 暴露度显式图标（玩法①）：决策期在空塔位标"会挨打/安全"（只标事实，SR-R2）。
const C_EXPOSE_ICON := Color(0.98, 0.32, 0.28, 1.0)   # 暴露位 = 红 X（会挨打）
const C_SAFE_ICON := Color(0.42, 0.82, 0.55, 1.0)     # 安全位 = 绿盾（安全）

# 原型配色 / 半径（占位美术，无玩法含义）
const C_RUSH := Color(0.98, 0.45, 0.25, 1.0)
const C_SWARM := Color(0.82, 0.84, 0.88, 1.0)
const C_TANK := Color(0.35, 0.55, 0.95, 1.0)
const C_ELITE := Color(1.0, 0.92, 0.25, 1.0)
const R_RUSH := 5.0
const R_SWARM := 6.5
const R_TANK := 10.0


var director: Node = null        # WaveDirector
var time_director: Node = null   # TimeDirector（读抽屉宽，决定战场可视宽）
## 🟡 切片8·I-7：商店控制器（读 runtime.snapshot() 画已建塔 + 点选/合法宿主高亮）。
##   🔴 只读，不写玩法状态（与 WaveDirector 一样是"画面事实"来源）。
var controller: Node = null
var _slot_rows: Array = []
var _snap: Dictionary = {}


func _ready() -> void:
	# 🔴 I-7：点选是商店期交互（安全窗 paused=true 下也要收点击）→ ALWAYS。
	#    本节点仍只读玩法状态、只发意图信号，process_mode 只影响"能否收输入"。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_slot_rows = _PathGeometry.slot_exposure(_Geo6.SLOTS6, 9.0)


func bind_director(d: Node) -> void:
	director = d
	queue_redraw()


func bind_time_director(d: Node) -> void:
	time_director = d
	if d == null:
		return
	if not d.is_connected("state_changed", _on_state_changed):
		d.state_changed.connect(_on_state_changed)
	queue_redraw()


## I-7：注入 ShopController（读 runtime 画已建塔 + 点选/合法宿主高亮）。
func bind_controller(c: Node) -> void:
	controller = c
	if c == null:
		return
	if not c.is_connected("shop_changed", _on_shop_run_changed):
		c.shop_changed.connect(_on_shop_run_changed)
	if not c.is_connected("run_changed", _on_shop_run_changed):
		c.run_changed.connect(_on_shop_run_changed)
	queue_redraw()


## state_changed（TimeDirector）携带 (from, to) 两参。
func _on_state_changed(_from: int, _to: int) -> void:
	queue_redraw()


## shop_changed / run_changed（ShopController）为 0 参信号，用无参回调避免参数不匹配报错。
func _on_shop_run_changed() -> void:
	queue_redraw()


func _process(_delta: float) -> void:
	if director == null:
		return
	_snap = director.snapshot()
	queue_redraw()


# ---------------------------------------------------------------------------
#  坐标映射
# ---------------------------------------------------------------------------
func _field_width() -> float:
	var vw := float(get_viewport().get_visible_rect().size.x)
	var drawer_open := false
	if time_director != null:
		drawer_open = (int(time_director.sm.clock()["drawer"]) != 0)
	return _ShopLayout.battlefield_width(vw, drawer_open)


func _xform() -> Dictionary:
	var vw := _field_width()
	var vh := float(get_viewport().get_visible_rect().size.y)
	# 世界包围盒（路径 + 塔位 + 余量）
	var x0 := -3.0
	var x1 := 58.0
	var z0 := 13.0
	var z1 := 51.0
	var ww := x1 - x0
	var wh := z1 - z0
	var sc := minf((vw - 2.0 * MARGIN) / ww, (vh - 2.0 * MARGIN) / wh)
	if sc <= 0.0:
		sc = 1.0
	var ox := (vw - ww * sc) * 0.5 - x0 * sc
	var oy := (vh - wh * sc) * 0.5 - z0 * sc
	return {"sc": sc, "ox": ox, "oy": oy}


func _to_screen(p: Vector2) -> Vector2:
	var t := _xform()
	return Vector2(float(t["ox"]) + p.x * float(t["sc"]), float(t["oy"]) + p.y * float(t["sc"]))


## I-7：屏幕坐标 → 塔位世界坐标的逆映射（点击命中判定用）。
func _to_world(screen_p: Vector2) -> Vector2:
	var t := _xform()
	var sc := float(t["sc"])
	return Vector2((screen_p.x - float(t["ox"])) / sc, (screen_p.y - float(t["oy"])) / sc)


## I-7：点击战场上的塔 → 发 `tower_select_requested(slot)`（由 ShopController 接 runtime.select_tower）。
##   · 只发意图、不改状态（SR-5）；命中半径 = 塔身半径 + 余量（像素级宽容）。
##   · 🔴 仅商店抽屉展开时响应（战斗/收拢时点击战场不该改点选）。
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if controller == null or controller.runtime == null:
		return
	# 仅抽屉展开（商店期）可点选塔
	var drawer_open := false
	if time_director != null:
		drawer_open = (int(time_director.sm.clock()["drawer"]) != 0)
	if not drawer_open:
		return
	var hit := _hit_tower_slot(mb.global_position)
	if hit >= 0:
		# 交给 ShopController 接线（不直接调 runtime，守 SR-5 依赖方向）
		if director != null:
			director.emit_signal("tower_select_requested", hit)
		get_viewport().set_input_as_handled()


## 命中判定：找最近的**已建塔**塔位（世界坐标距离 < 命中半径）。返回 slot 或 -1。
func _hit_tower_slot(screen_p: Vector2) -> int:
	var wp := _to_world(screen_p)
	var t := _xform()
	var sc := float(t["sc"])
	var hit_radius_world := maxf(9.0, sc * 1.6)     # 塔身半径 + 余量
	var best := -1
	var best_d := INF
	if controller == null or controller.runtime == null:
		return -1
	for tw in controller.runtime.player.towers:
		var s := int(tw.slot)
		if s < 0 or s >= _Geo6.SLOTS6.size():
			continue
		var d := wp.distance_to(_Geo6.SLOTS6[s])
		if d < hit_radius_world and d < best_d:
			best = s
			best_d = d
	return best


# ---------------------------------------------------------------------------
#  已建塔渲染（I-7）
# ---------------------------------------------------------------------------
# 塔原型配色（占位，与怪物区分：塔偏青绿系）
const C_TOWER_ARROW := Color(0.40, 0.80, 0.55, 1.0)   # 中性（Arrow）
const C_TOWER_CANNON := Color(0.95, 0.55, 0.30, 1.0)  # fire（Cannon）
const C_TOWER_FROST := Color(0.45, 0.70, 0.95, 1.0)   # frost（Frost）
const C_TOWER_CORE := Color(0.95, 0.85, 0.30, 1.0)    # 主塔描边
const C_SELECT := Color(0.35, 0.95, 0.95, 1.0)        # I-7 选中高亮
const C_HOST := Color(0.95, 0.75, 0.35, 0.9)          # D-TB-6 合法宿主高亮


func _tower_color(ctype: String) -> Color:
	match ctype:
		"Cannon":
			return C_TOWER_CANNON
		"Frost":
			return C_TOWER_FROST
		_:
			return C_TOWER_ARROW


## 画已建塔：塔原型色实心 + 层数刻度（h 个小点）+ 主塔描边 + 选中/合法宿主高亮。
func _draw_towers(sc: float) -> void:
	if controller == null or controller.runtime == null:
		return
	var snap: Dictionary = controller.runtime.snapshot()
	# 🔴 snapshot 里塔位列表键是 "slots"（含 ctype/h/empty）；"towers" 是数量 int。
	var towers: Array = snap.get("slots", [])
	var selected: int = int(snap.get("selected_tower_slot", -1))
	var core_slot: int = int(snap.get("core_tower_slot", -1))
	var hosts: Array = _forced_select_hosts(snap)

	for tw in towers:
		if bool(tw.get("empty", true)):
			continue
		var slot: int = int(tw.get("slot", -1))
		if slot < 0 or slot >= _Geo6.SLOTS6.size():
			continue
		var sp := _to_screen(_Geo6.SLOTS6[slot])
		var h: int = int(tw.get("h", 1))
		var rad := maxf(7.0, sc * 1.1)

		# D-TB-6 合法宿主高亮（在塔身之下，作底圈）
		if hosts.has(slot):
			draw_arc(sp, rad + maxf(4.0, sc * 0.7), 0.0, TAU, 30, C_HOST, maxf(2.0, sc * 0.22), true)
		# 塔身
		draw_circle(sp, rad, _tower_color(String(tw.get("ctype", "Arrow"))))
		# 主塔描边
		if slot == core_slot:
			draw_arc(sp, rad + maxf(1.5, sc * 0.2), 0.0, TAU, 28, C_TOWER_CORE, maxf(1.5, sc * 0.18), true)
		# 选中高亮（最外圈，青）
		if slot == selected:
			draw_arc(sp, rad + maxf(4.0, sc * 0.6), 0.0, TAU, 30, C_SELECT, maxf(2.5, sc * 0.24), true)
		# 层数刻度（h 个白点，沿塔身底部排开）
		var n := mini(h, 8)
		for k in range(n):
			var ang := PI * (0.25 + 0.5 * float(k) / float(maxi(1, n - 1)))
			var dot := Vector2(sp.x + cos(ang) * rad * 0.5, sp.y + sin(ang) * rad * 0.5)
			draw_circle(dot, maxf(1.2, sc * 0.14), Color(1.0, 1.0, 1.0, 0.9))


## D-TB-6：若当前商店焦点位是"需强制点选"的 reinforce 卡，返回其合法宿主塔位；否则空。
##   🔴 只读 runtime 的 offer + get_legal_hosts，不改任何状态。
func _forced_select_hosts(snap: Dictionary) -> Array:
	var offers: Array = snap.get("offers", [])
	var notes: Array = snap.get("notes", [])
	var kinds: Array = snap.get("kinds", [])
	for i in range(mini(offers.size(), notes.size())):
		if String(kinds[i]) == "单塔效果卡" and String(notes[i]) == "选择宿主塔":
			return controller.runtime.get_legal_hosts(String(offers[i]))
	return []


# ---------------------------------------------------------------------------
#  🔒 T1 H10 暴露度显式图标（玩法① · GDD mechanics-tower-life-death §3 玩法①）
#  ---------------------------------------------------------------------------
#  目的：把"这个塔位会不会挨打"从隐含红环升级为**显式可读事实**，让玩家在放塔/保塔
#    决策时一眼看懂 —— 兑现 V-2 定稿"把保塔决策交还玩家"（单核流保塔是 AI 做不到、
#    玩家能做到的事，可行性由暴露度 UI 支撑）。
#  🔴 只标事实（暴露/安全），**不标推荐**（SR-R2：不写"建议放这里"）—— 图标只回答
#    "会/不会挨打"，不回答"该不该放"。
#  显示时机：**决策期**（抽屉展开 = 商店/放置/安全窗，state != COMBAT）；战斗中不显示。
#  图标语义：暴露位（d_path ≤ 9.0）= 红 X「会挨打」；安全位 = 绿盾「安全」。
#  🔴 只标**空塔位**（已建塔的暴露度由塔身 + 红环已表达，避免叠图干扰）。
func _draw_exposure_icons(sc: float) -> void:
	if time_director == null or time_director.sm == null:
		return
	# 仅决策期（非战斗）显示；战斗中（COMBAT）保持观赏清爽
	if int(time_director.sm.state) == _TSM.State.COMBAT:
		return
	# 已建塔塔位不叠加图标（塔身 + 红环已表达暴露事实）
	var occupied: Dictionary = {}
	if controller != null and controller.runtime != null:
		for tw in controller.runtime.player.towers:
			occupied[int(tw.slot)] = true
	var icon_r := maxf(5.0, sc * 0.62)
	for row in _slot_rows:
		var slot: int = int(row["slot"])
		if occupied.has(slot):
			continue
		var sp: Vector2 = _to_screen(row["pos"])
		# 图标画在塔位上方（避开塔位圆环）
		var ip := Vector2(sp.x, sp.y - maxf(11.0, sc * 1.5))
		if bool(row["is_exposed"]):
			_draw_cross(ip, icon_r, C_EXPOSE_ICON)     # 暴露 = 红 X（会挨打）
		else:
			_draw_shield(ip, icon_r, C_SAFE_ICON)      # 安全 = 绿盾


## 画"会挨打"图标 = 红 X（两条交叉线，直观表达"此处会被攻击"）。
func _draw_cross(c: Vector2, r: float, col: Color) -> void:
	var d := r * 0.7
	draw_line(Vector2(c.x - d, c.y - d), Vector2(c.x + d, c.y + d), col, maxf(1.6, r * 0.28), true)
	draw_line(Vector2(c.x - d, c.y + d), Vector2(c.x + d, c.y - d), col, maxf(1.6, r * 0.28), true)


## 画"安全"图标 = 绿盾（圆顶 + 方底简化盾形，直观表达"此处挨不到"）。
func _draw_shield(c: Vector2, r: float, col: Color) -> void:
	var top := Vector2(c.x, c.y - r * 0.75)
	var right := Vector2(c.x + r * 0.7, c.y - r * 0.35)
	var br := Vector2(c.x + r * 0.55, c.y + r * 0.6)
	var bottom := Vector2(c.x, c.y + r * 0.95)
	var bl := Vector2(c.x - r * 0.55, c.y + r * 0.6)
	var left := Vector2(c.x - r * 0.7, c.y - r * 0.35)
	var pts: PackedVector2Array = [top, right, br, bottom, bl, left]
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.9))
	draw_polyline(pts, col, maxf(1.2, r * 0.2), true)


# ---------------------------------------------------------------------------
#  绘制
# ---------------------------------------------------------------------------
func _draw() -> void:
	var t := _xform()
	var sc := float(t["sc"])

	# ---- 路径 ----
	for i in range(_PathGeometry.N_SEG):
		var a := _to_screen(_PathGeometry.PATH[i])
		var b := _to_screen(_PathGeometry.PATH[i + 1])
		draw_line(a, b, C_PATH, maxf(3.0, sc * 0.55), true)
	for i in range(_PathGeometry.PATH.size()):
		draw_circle(_to_screen(_PathGeometry.PATH[i]), maxf(2.0, sc * 0.22), C_PATH_DOT)

	# ---- 核心（路径终点）----
	var cp := _to_screen(_PathGeometry.CORE_POS)
	var cs := maxf(8.0, sc * 1.6)
	draw_rect(Rect2(cp.x - cs * 0.5, cp.y - cs * 0.5, cs, cs), C_CORE)

	# ---- 塔位（空心圆 + 暴露红环）----
	for row in _slot_rows:
		var p: Vector2 = row["pos"]
		var sp := _to_screen(p)
		draw_arc(sp, maxf(5.0, sc * 0.7), 0.0, TAU, 24, C_SLOT, maxf(1.0, sc * 0.10), true)
		if bool(row["is_exposed"]):
			draw_arc(sp, maxf(7.0, sc * 1.05), 0.0, TAU, 28, C_EXPOSE, maxf(1.0, sc * 0.08), true)

	# ---- 🔒 T1 H10 暴露度显式图标（玩法①）：决策期在**空塔位**标"会挨打/安全" ----
	#    只标事实（暴露/安全），不标推荐（SR-R2）；战斗中（非决策期）不显示，保持观赏清爽。
	_draw_exposure_icons(sc)

	# ---- 已建塔（I-7：按塔原型上色 + 层数刻度 + 选中/合法宿主高亮）----
	_draw_towers(sc)

	# ---- 怪物 ----
	if _snap.is_empty():
		return
	var ms: Array = _snap.get("monsters", [])
	for m in ms:
		var p: Vector2 = m["pos"]
		var sp := _to_screen(p)
		var proto := String(m["proto"])
		var col := C_SWARM
		var rad := R_SWARM
		match proto:
			"Rush":
				col = C_RUSH
				rad = R_RUSH
			"Tank":
				col = C_TANK
				rad = R_TANK
			_:
				col = C_SWARM
				rad = R_SWARM
		rad = maxf(rad, sc * 0.55)
		draw_circle(sp, rad, col)
		if bool(m["elite"]):
			draw_arc(sp, rad + maxf(2.0, sc * 0.18), 0.0, TAU, 24, C_ELITE, maxf(1.5, sc * 0.16), true)
