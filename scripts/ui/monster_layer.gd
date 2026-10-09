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
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _WD := preload("res://scripts/gameplay/wave_director.gd")   # 仅取 MState 枚举（AGGRO_TOWER）

const MARGIN := 48.0
const C_PATH := Color(0.34, 0.30, 0.22, 1.0)
const C_PATH_DOT := Color(0.55, 0.48, 0.32, 1.0)
const C_CORE := Color(0.35, 0.85, 0.95, 1.0)
const C_SLOT := Color(0.45, 0.50, 0.55, 0.85)
const C_EXPOSE := Color(0.95, 0.30, 0.25, 0.75)
# 🔒 T1 H10 暴露度显式图标（玩法①）：决策期在空塔位标"会挨打/安全"（只标事实，SR-R2）。
const C_EXPOSE_ICON := Color(0.98, 0.32, 0.28, 1.0)   # 暴露位 = 红 X（会挨打）
const C_SAFE_ICON := Color(0.42, 0.82, 0.55, 1.0)     # 安全位 = 绿盾（安全）
# 🔒 T1 肉盾塔可读性（R-T4 余光预警）：战斗态标"正在被仇恨锁定挨打的塔" = 橙色环。
#   与 H10 决策期暴露度图标互补：决策期看"会不会挨打"（红X/绿盾），战斗期看"正在挨打"。
const C_UNDER_ATTACK := Color(1.0, 0.55, 0.20, 0.95)  # 正在挨打 = 橙环（肉盾塔在扛伤）

# 🔒 V-8 肉盾循环 M-1「战斗内被动复活」可读性（GDD mechanics-bulwark-cycle §6.1）
#   🔴 T-E1③ / T-C2 红线：**零数字、零倒计时、零进度条**。
#      只允许两样东西：① 塔体动效（**运动 + 亮度**，余光可读、不依赖色相）；
#      ② 塔底「重启充能」**点亮/熄灭**二态（布尔，不是 "1/1"、不是进度条）。
#   🔴 因此本文件用 `draw_arc` / `draw_circle` 画，🈚 `draw_string`、🈚 Label。
const C_REVIVE_LIT := Color(1.0, 0.86, 0.35, 0.95)    # 充能还在 = 暖金亮点（这座塔还能爬一次）
const C_REVIVE_SPENT := Color(0.30, 0.31, 0.35, 0.55) # 充能用尽 = 熄灭暗点（本波不会再爬）
const C_REVIVE_FLASH := Color(1.0, 0.96, 0.78, 1.0)   # 爬起瞬间 = 高亮扩散环（运动 + 亮度）
## 爬起动效时长（秒）。🔴 它是**事后**演出（塔已经爬起来了才播），不是倒计时 ——
##   玩家无法据此预判任何时刻，不违反 T-E1③「零择时提示」。
const REVIVE_FLASH_SEC := 0.6

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
## 🔒 V-8：塔位 → 爬起动效**剩余秒数**（纯演出计时器，UI 本地状态）。
##   🔴 不是游戏状态（control-manifest §5 指的是玩法状态）：它只驱动画面衰减，
##      不回写任何玩法数据、不参与任何判定。
var _revive_flash: Dictionary = {}


func _ready() -> void:
	# 🔴 I-7：点选是商店期交互（安全窗 paused=true 下也要收点击）→ ALWAYS。
	#    本节点仍只读玩法状态、只发意图信号，process_mode 只影响"能否收输入"。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_recompute_slot_rows()


func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	# 🔒 V-8：`tower_revived` 是**单向**通知（导演 → 画面）。渲染层只能订阅播动效，
	#   🔴 没有任何反向路径 —— 这是 T-E1 边界二「无玩家战斗内操作/择时」的画面侧保证。
	if not d.is_connected("tower_revived", _on_tower_revived):
		d.tower_revived.connect(_on_tower_revived)
	queue_redraw()


## 🔒 V-8：塔自动爬起 → 记录动效计时（**只写画面状态**）。
func _on_tower_revived(slot: int) -> void:
	_revive_flash[int(slot)] = REVIVE_FLASH_SEC
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
	# 🔴 阶段1 八槽：runtime 绑定后按实际 geo 重算暴露度（6/8 槽动态）。
	_recompute_slot_rows()
	queue_redraw()


## 🔴 阶段2 暴露度分派（D-3 定稿 EXPO_SAFE_MAX=0.15）：
##   PATH 模式 → 既有 slot_exposure（d_path ≤ 9 二值，逐位不变，金标本零扰动）。
##   RADIAL 模式 → 径向 slot_exposure_radial（expo_frac ≥ 0.15 二值，D-3 冻结阈值）。
## 🔴 红线：PATH 分支必须与现状逐位相同（金标本不消费暴露度，但 H10 UI 事实层不能变）。
func _recompute_slot_rows() -> void:
	var slots: Array = _slots_arr()
	if _SpaceModel.is_radial():
		_slot_rows = _PathGeometry.slot_exposure_radial(
			slots, _MonsterData.AGGRO_R, _SpaceModel.core_pos(),
			_PathGeometry.EXPO_SAFE_MAX)
	else:
		_slot_rows = _PathGeometry.slot_exposure(slots, _MonsterData.AGGRO_R)


## 🔴 阶段1 八槽接入：动态取当前槽位几何（6/8 槽）。
##   优先从 runtime.geo.slots 取（八槽时 = Geo8 坐标）；未绑定 runtime 时回退
##   `_Geo6.SLOTS6`（六槽方案 A，逐位不变）。
func _slots_arr() -> Array:
	if controller != null and controller.runtime != null and controller.runtime.geo != null:
		return controller.runtime.geo.slots
	return _Geo6.SLOTS6


func _process(delta: float) -> void:
	# 🔒 V-8：爬起动效计时衰减（纯画面）。🔴 夹住 delta：窗口失焦回来的巨大跳变
	#   会让动效瞬间蒸发（也不会卡住 —— 上限 clamp 只影响观感，不影响任何玩法数值）。
	if not _revive_flash.is_empty():
		var d := clampf(float(delta), 0.0, 0.1)
		var done: Array = []
		for slot in _revive_flash:
			var v := float(_revive_flash[slot]) - d
			if v <= 0.0:
				done.append(slot)
			else:
				_revive_flash[slot] = v
		for slot in done:
			_revive_flash.erase(slot)
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
	var x0: float
	var x1: float
	var z0: float
	var z1: float
	if _SpaceModel.mode == _SpaceModel.Mode.RADIAL:
		# 🔴 径向模式：包围盒以居中核心 (28,28) 为中心、容纳整圈出生环 R_s + 余量。
		#   环超出逻辑地图 [0,55] 是"怪物从场外涌入"的表现（草案 §2.3）。
		var core := _SpaceModel.RADIAL_CORE
		var span := float(_SpaceModel.SPAWN_RADIUS) + 3.0
		x0 = core.x - span
		x1 = core.x + span
		z0 = core.y - span
		z1 = core.y + span
	else:
		# PATH 模式：既有包围盒（路径 + 塔位 + 余量），逐位等价基准，一行不改。
		x0 = -3.0
		x1 = 58.0
		z0 = 13.0
		z1 = 51.0
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
		if s < 0 or s >= _slots_arr().size():
			continue
		var d := wp.distance_to(_slots_arr()[s])
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
		if slot < 0 or slot >= _slots_arr().size():
			continue
		var sp := _to_screen(_slots_arr()[slot])
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
		# 🔒 V-8 停机态：塔身压暗（"倒下了"）→ 爬起时由 `_draw_revive_flash` 重新点亮，
		#   形成「压暗 → 高亮扩散环 → 恢复常亮」的**运动 + 亮度**演出（T-C2 / §6.1）。
		#   🔴 只在 revive 功能生效时画（默认 off → 默认画面逐像素不变）。
		if _revive_on() and _is_disabled(slot):
			draw_circle(sp, rad, Color(0.06, 0.07, 0.09, 0.62))
			draw_arc(sp, rad, 0.0, TAU, 28, Color(0.55, 0.57, 0.62, 0.55),
				maxf(1.0, sc * 0.10), true)
		# 🔒 V-8 塔底「重启充能」点亮（K 未用 = 亮 / 用尽 = 灭）。🔴 零数字、零文本。
		_draw_revive_charge(sp, slot, rad, sc)
		# 层数刻度（h 个白点，沿塔身底部排开）
		var n := mini(h, 8)
		for k in range(n):
			var ang := PI * (0.25 + 0.5 * float(k) / float(maxi(1, n - 1)))
			var dot := Vector2(sp.x + cos(ang) * rad * 0.5, sp.y + sin(ang) * rad * 0.5)
			draw_circle(dot, maxf(1.2, sc * 0.14), Color(1.0, 1.0, 1.0, 0.9))


## 🔒 V-8 塔底「重启充能」点亮 —— 回答「这座塔**还能不能再爬一次**」。
##   🟢 表达方式：**一个亮点 / 一个暗点**（二态布尔），零文本、零数字、零进度条。
##   🔴 只在「仇恨开 + 复活档位开」且**战斗态**下画 —— 默认配置下 `_snap["revive_ui"]`
##      恒 false → 本函数零绘制，默认画面与改前**逐像素相同**（金标本回归零扰动）。
##   🔴 不显示 K 余量数字、不显示倒计时、不显示"还有几秒"（T-E1③ / §6.1）。
func _draw_revive_charge(sp: Vector2, slot: int, rad: float, sc: float) -> void:
	if not _revive_on():
		return
	# 仅战斗态（SPAWNING=1 / FIGHTING=2）：波次间不画，避免与商店抽屉互相干扰。
	if not (int(_snap.get("state", 0)) == 1 or int(_snap.get("state", 0)) == 2):
		return
	var lit := bool(_revive_charged().get(slot, false))
	var cr := maxf(1.8, sc * 0.20)
	var cp := Vector2(sp.x, sp.y + rad + maxf(4.5, sc * 0.62))
	if lit:
		draw_circle(cp, cr, C_REVIVE_LIT)
		# 亮度外晕（余光可读；不依赖色相 → 色觉可访问，§6.3）
		draw_arc(cp, cr + maxf(1.2, sc * 0.14), 0.0, TAU, 12,
			Color(C_REVIVE_LIT.r, C_REVIVE_LIT.g, C_REVIVE_LIT.b, 0.45),
			maxf(1.0, sc * 0.10), true)
	else:
		draw_circle(cp, cr, C_REVIVE_SPENT)


## 🔒 V-8 总闸：复活功能是否对**画面**生效（仇恨开 + `repair_on_disable >= 9`）。
##   🔴 默认恒 false → 下面的停机压暗 / 充能点亮 / 爬起动效**全部零绘制**，
##      默认画面与改前**逐像素相同**（金标本回归零扰动）。
func _revive_on() -> bool:
	return bool(_snap.get("revive_ui", false))


## 塔位 → 本波「还能不能再爬一次」（布尔）。数据源 = 导演 snapshot 的每塔
##   `revive_charged`（🔴 布尔，非数字 —— 渲染层拿不到也无法画出任何读数）。
func _revive_charged() -> Dictionary:
	var out: Dictionary = {}
	for t in _snap.get("towers", []):
		out[int(t.get("slot", -1))] = bool(t.get("revive_charged", false))
	return out


## 塔位 → 是否处于停机态（`disabled`）。数据源同为导演 snapshot（只读）。
func _is_disabled(slot: int) -> bool:
	for t in _snap.get("towers", []):
		if int(t.get("slot", -1)) == slot:
			return bool(t.get("disabled", false))
	return false


## 🔒 V-8 塔体**重启动效**：一圈高亮环从塔身向外扩散并变暗（**运动 + 亮度**）。
##   🟢 它播在**爬起之后**（事后演出），不预告任何时刻 → 不构成倒计时/进度条。
##   🟢 不依赖色相（白/暖金的高亮环）→ 色觉可访问（§6.3 第 4 条）。
func _draw_revive_flash(sc: float) -> void:
	if _revive_flash.is_empty():
		return
	for slot in _revive_flash:
		var rem := float(_revive_flash[slot])
		if rem <= 0.0:
			continue
		var s := int(slot)
		if s < 0 or s >= _slots_arr().size():
			continue
		var sp := _to_screen(_slots_arr()[s])
		var p := clampf(rem / REVIVE_FLASH_SEC, 0.0, 1.0)   # 1 → 0（越晚越暗越大）
		var rad := maxf(7.0, sc * 1.1)
		var grow := (1.0 - p) * maxf(15.0, sc * 2.2)
		var col := Color(C_REVIVE_FLASH.r, C_REVIVE_FLASH.g, C_REVIVE_FLASH.b, p)
		draw_arc(sp, rad + grow, 0.0, TAU, 32, col, maxf(2.0, sc * 0.30), true)
		# 塔身一瞬提亮（亮度表达，与"重新点亮"同义）
		draw_circle(sp, rad, Color(1.0, 1.0, 1.0, 0.40 * p))


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


## 🔒 T1 肉盾塔可读性（R-T4 余光预警 · GDD mechanics-tower-life-death §5 R-T4）：
##   战斗态（有怪锁定塔时）在**正在被仇恨锁定挨打的塔**上标橙环——让玩家余光看懂
##   "哪座塔正在替后排扛伤"（肉盾塔的作用可视化）。
##   🔴 只标事实（正在挨打），不标推荐（SR-R2：不写"该保这座"）。
##   🔴 数据源 = WaveDirector.snapshot() 里 state==AGGRO_TOWER 的怪的 target_slot
##      （怪物锁定塔 → 停下打它，见 wave_director._apply_aggro）。
##   🔴 仅战斗态显示（决策期无怪锁定，_snap 里无 AGGRO_TOWER 怪 → 自然不画）。
##   🔴 MVP 金标本口径（tower_aggro_enabled=false）下无怪进 AGGRO_TOWER → 本函数零绘制，
##      对切片5 冒烟/金标本等价零扰动。
func _draw_under_attack(sc: float) -> void:
	if _snap.is_empty():
		return
	# 收集正在被仇恨锁定的塔位（有怪 state==AGGRO_TOWER 且 target_slot 有效）
	var attacked: Dictionary = {}
	var ms: Array = _snap.get("monsters", [])
	for m in ms:
		if int(m.get("state", 0)) == _WD.MState.AGGRO_TOWER:
			var ts: int = int(m.get("target_slot", -1))
			if ts >= 0:
				attacked[ts] = true
	if attacked.is_empty():
		return
	var ring_r := maxf(8.0, sc * 1.15)
	for slot in attacked:
		if slot < 0 or slot >= _slots_arr().size():
			continue
		var sp := _to_screen(_slots_arr()[slot])
		# 橙色攻击环（在塔身之上，醒目但不遮挡塔体损伤演出）
		draw_arc(sp, ring_r, 0.0, TAU, 32, C_UNDER_ATTACK, maxf(2.0, sc * 0.24), true)


# ---------------------------------------------------------------------------
#  绘制
# ---------------------------------------------------------------------------
func _draw() -> void:
	var t := _xform()
	var sc := float(t["sc"])

	# ---- 路径 / 出生环 ----
	if _SpaceModel.mode == _SpaceModel.Mode.RADIAL:
		# 🔴 径向模式：路径消失（草案核心特征）。改画出生环（半径 R_s 的围攻圈），
		#   传达"怪物从这一圈涌入"。核心居中 → 环以核心为圆心。
		var ring_c := _to_screen(_SpaceModel.RADIAL_CORE)
		var ring_r := float(_SpaceModel.SPAWN_RADIUS) * sc
		draw_arc(ring_c, ring_r, 0.0, TAU, 96, C_PATH, maxf(2.0, sc * 0.35), true)
	else:
		# PATH 模式：既有 5 段折线 + 6 路径点（逐位等价基准，一行不改）。
		for i in range(_PathGeometry.N_SEG):
			var a := _to_screen(_PathGeometry.PATH[i])
			var b := _to_screen(_PathGeometry.PATH[i + 1])
			draw_line(a, b, C_PATH, maxf(3.0, sc * 0.55), true)
		for i in range(_PathGeometry.PATH.size()):
			draw_circle(_to_screen(_PathGeometry.PATH[i]), maxf(2.0, sc * 0.22), C_PATH_DOT)

	# ---- 核心 ----
	# PATH 模式：路径终点 (55,25)（逐位等价基准）；RADIAL 模式：居中核心 (28,28)。
	#   🔴 跟随 SpaceModel.core_pos() → 径向下核心居中，"塔全堆核心左侧"的视觉取舍消失。
	var cp := _to_screen(_SpaceModel.core_pos())
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

	# ---- 🔒 T1 肉盾塔可读性（R-T4）：战斗态在**被仇恨锁定挨打的塔**上标橙环 ----
	#    只标事实（正在挨打），不标推荐（SR-R2）；仅战斗态（有怪锁定塔时）显示。
	_draw_under_attack(sc)

	# ---- 已建塔（I-7：按塔原型上色 + 层数刻度 + 选中/合法宿主高亮）----
	_draw_towers(sc)

	# ---- 🔒 V-8 塔体「重启动效」（画在塔体之上，事后演出 · 运动 + 亮度）----
	_draw_revive_flash(sc)

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
