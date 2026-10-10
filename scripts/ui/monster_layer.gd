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
## 🔴 P0（spec §A.6）：环境换装共享色表（纯静态助手，与 `Battlefield` 共用同款 preload）。
const _EnvPalette := preload("res://scripts/ui/env_palette.gd")
## 档间过渡时长（spec §A.5 / art-bible §2.4：3.0s 缓动，不得突变）。
const ENV_FADE_SEC := 3.0

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

# ===========================================================================
#  🔴 P0 战场可读性 · 正交俯视 2D 落地（blueprint = `docs/phase3/ux-p0p1-spec.md`）
#  ---------------------------------------------------------------------------
#  · 本区块**只在 RADIAL 模式生效**；PATH 模式仍走 `_draw_legacy()`（逐位不变）。
#  · 只读 snapshot 渲染，零玩法写入、零新信号（spec §C.4 零扰动）。
#  · 配色严格取 spec §A.1 表（精确 hex 已换算为 Color）。
# ===========================================================================
# ---- 阵营配色（spec §A.1，精确 hex）----
const P_ALLY := Color(0.243, 0.816, 0.910)        # #3ED0E8 耀青（我方主体）
const P_ALLY_DARK := Color(0.102, 0.420, 0.490)   # #1A6B7D 深青（我方阴影层）
const P_ALLY_2 := Color(0.478, 0.361, 1.000)      # #7A5CFF 星紫（副色/主塔标记）
const P_CORE_HI := Color(0.918, 0.984, 1.000)     # #EAFBFF 核心内芯高光
const P_ENEMY := Color(1.000, 0.420, 0.239)       # #FF6B3D 熔橙（敌方主体）
const P_ENEMY_DARK := Color(0.541, 0.184, 0.110)  # #8A2F1C 焦褐（敌方阴影层/尖刺）
const P_ELITE := Color(0.910, 0.263, 0.498)       # #E8437F 噬品红（精英）
const P_SLOT := Color(0.604, 0.647, 0.694)        # #9AA5B1 钢灰（塔位空槽）
const P_GOLD := Color(1.000, 0.788, 0.290)        # #FFC94A 辉金（积分/合法宿主）
const P_ALERT := Color(1.000, 0.180, 0.306)       # #FF2E4E 警报红（受创/临界）
const P_FIELD := Color(0.137, 0.157, 0.220)       # #232838 场地圆填充
const P_RING := Color(0.106, 0.125, 0.188)        # #1B2030 同心环/放射刻度
const P_BG := Color(0.078, 0.090, 0.149)          # #141726 背景（雾底）
const P_SPAWN_EDGE := Color(0.227, 0.259, 0.341)  # #3A4257 出生环描边
const P_TOWER_EDGE := Color(0.055, 0.141, 0.188)  # #0E2430 塔描边（冷暗）
const P_MON_EDGE := Color(0.180, 0.063, 0.031)    # #2E1008 怪描边（暖暗）

# ---- 形状尺寸（世界单位 u；屏幕 px = u × sc，spec §A.5）----
const U_TOWER := 1.70          # 塔：八边形外接圆
const U_SLOT := 1.50           # 塔位空槽：八边形环
const U_CORE := 1.90           # 核心：最外环
const U_OUTLINE := 0.22        # 描边宽（恒定屏幕 2px @1080p）
const BODY_RUSH := 0.65        # 怪：Rush 细长
const BODY_SWARM := 0.85       # 怪：Swarm 中
const BODY_TANK := 1.30        # 怪：Tank 宽扁
const ELITE_SCALE := 1.35      # 精英体量修饰
const SPIKE_SPREAD := 0.40     # 尖刺扇相邻夹角（rad；spec 未钉值，取定性观感值）
const CONCENTRIC_U: Array = [15.0, 30.0, 45.0]     # 同心环半径 u（spec §A.7）
# 确定性 12 边形扰动表（全员共享 → 帧间稳定，杜绝逐帧抖动；spec §A.2.2）
const BLOB_R12: Array = [1.00, 0.88, 1.06, 0.92, 1.02, 0.86, 1.04, 0.95, 1.00, 0.90, 1.05, 0.93]

# ===========================================================================
#  🔴 P0 增强集（第二刀 · spec §A.4 / §A.2.1 增强 / §A.2.3 受创）
#  ---------------------------------------------------------------------------
#  同架构、零扰动：仍**只读** snapshot；新增本地状态全是**纯演出计时器/差分缓存**
#  （与 `_revive_flash` / `_vfx_t` 同性质），不回写玩法、不新增信号（spec §C.4）。
# ===========================================================================
# ---- Rim Light 内发光（spec §A.4）：本体内侧再叠一圈阵营色细弧 ----
#   作用：同屏混乱时分离相邻单位。宽恒定 0.8px（屏幕空间），α 0.6。
const RIM_W := 0.8                                    # 内发光细弧宽（屏幕 px）
const RIM_ALLY := Color(0.243, 0.816, 0.910, 0.6)     # 塔：耀青 #3ED0E8 @α0.6
const RIM_ENEMY := Color(1.000, 0.420, 0.239, 0.6)    # 怪：熔橙 #FF6B3D @α0.6
# ---- 受击闪（spec §A.2.3 受创 / §8.1）：帧间差分触发，本地计时器衰减 ----
const CORE_FLASH_SEC := 0.12      # 核心外环闪 #FF2E4E @α0.8 持续 0.12s
const TOWER_FLASH_SEC := 0.15     # 塔受击一瞬白闪时长（本地演出）
# 塔升级「形态」递进 —— 护角长度上限 0.30u（红线：不超 R + 0.30u，不侵占相邻塔位）。
const TOWER_CORNER_MAX_U := 0.30

# ===========================================================================
#  🔴 体验层第三刀 · 视觉氛围刀（blueprint = `docs/phase3/ux-p0p1c-spec.md`）
#  ---------------------------------------------------------------------------
#  同架构、零扰动：仍**只读** snapshot；新增本地状态**仅**纯演出计时器
#  `_env_tier/_env_prev/_env_t`（环境换装过渡）。核心呼吸**复用既有 `_vfx_t`**、
#  怪摆动**纯由 `pos` 派生** → 均**零新增状态**。零玩法写入、零新信号（spec §C.4）。
# ===========================================================================
# ---- §B.3 怪 squash&stretch 摆动：空间频率（rad/unit，spec §B.3.3）----
const SWAY_K_RHO := 0.50
# ---- §B.2 核心呼吸：幅度 / 周期（盘级；内芯保留其原有更快一层，spec §B.2.2）----
const CORE_BREATH_AMP := 0.025
const CORE_BREATH_SEC := 2.4


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
## 🔴 P0：纯演出相位（驱动核心内芯呼吸等）。与 `_revive_flash` 同性质 ——
##   只是画面计时器，不回写任何玩法数据、不参与任何判定（spec §C.4 第 3 条）。
var _vfx_t: float = 0.0
## 🔴 P0 增强：受击闪演出计时器 + 帧间差分缓存（纯本地画面状态）。
##   `_core_hp_prev` / `_tower_hp_prev` 只是"上一帧读数"，用于检测**下降**；
##   计时器 `_core_flash` / `_tower_flash` 只驱动画面衰减 —— 均不回写玩法、不参与判定。
var _core_hp_prev: float = -1.0
var _core_flash: float = 0.0
var _tower_hp_prev: Dictionary = {}
var _tower_flash: Dictionary = {}
## 🔴 P0（spec §A.5/§A.6）：环境换装过渡计时器（**纯演出本地状态**，与 `_vfx_t` 同性质）。
##   `_env_tier` = 当前目标档；`_env_prev` = 过渡起点档；`_env_t` ∈ [0,1]（1 = 过渡完成）。
##   `-1` = 尚未落位（首帧直接落位，无过渡）。**不回写玩法、不参与任何判定。**
var _env_tier: int = -1
var _env_prev: int = -1
var _env_t: float = 1.0


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
	# 🔴 P0：演出相位累加（只驱动画面，纯本地状态）。
	var dt := clampf(float(delta), 0.0, 0.1)
	_vfx_t += dt
	# 🔴 P0 增强：受击闪演出计时衰减（纯画面；夹住 dt 防失焦跳变瞬间蒸发）。
	if _core_flash > 0.0:
		_core_flash = maxf(0.0, _core_flash - dt)
	if not _tower_flash.is_empty():
		for slot in _tower_flash.keys():
			var v := float(_tower_flash[slot]) - dt
			if v <= 0.0:
				_tower_flash.erase(slot)
			else:
				_tower_flash[slot] = v
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
	# 🔴 P0（spec §A.5）：环境换装档位推进（纯演出；只读 `_snap["w"]`）。
	_update_env(dt)
	_detect_hits()
	queue_redraw()


## 🔴 P0 增强：帧间差分检测核心 / 塔**受击**（只读快照；仅写本地演出计时器）。
##   · 核心：`runtime.snapshot()["core_hp"]` 下降 → 外环闪 0.12s。
##   · 塔：`runtime.player.towers[slot].hp` 下降 → 该塔白闪（仅可见塔）。
##   🔴 无稳定怪物 id（第一刀已验证）→ 怪物命中闪**不做**（登记不做项）。
func _detect_hits() -> void:
	if controller == null or controller.runtime == null:
		return
	var rt = controller.runtime
	var chp := float(rt.snapshot().get("core_hp", 0.0))
	if _core_hp_prev >= 0.0 and chp < _core_hp_prev - 0.0001:
		_core_flash = CORE_FLASH_SEC
	_core_hp_prev = chp
	var cur: Dictionary = {}
	for tw in rt.player.towers:
		var s := int(tw.slot)
		var hp := float(tw.hp)
		cur[s] = hp
		var prev := float(_tower_hp_prev.get(s, -1.0))
		if prev >= 0.0 and hp < prev - 0.0001:
			_tower_flash[s] = TOWER_FLASH_SEC
	_tower_hp_prev = cur


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
	# 🔴 双模分派：RADIAL 走 P0 分层绘制；PATH 走旧口径（逐位不变）。
	if _SpaceModel.mode == _SpaceModel.Mode.RADIAL:
		_draw_radial(sc)
		return
	_draw_legacy(sc)


## PATH 模式渲染 —— 🔴 与改前**逐位等价**（含路径/核心/塔位/暴露图标/被攻击环/塔/怪，一行未改）。
func _draw_legacy(sc: float) -> void:
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


# ===========================================================================
#  P0 · RADIAL 分层绘制（spec §A.6 渲染顺序）
#  ---------------------------------------------------------------------------
#  层0/场地底由父节点 `Battlefield` 承担（bg #141726 + 场地圆 #232838，父先子后）。
#  本层：层1 地面 decal → 层2 出生环 → 层3 全部影 → 层4 塔位层 → 层5 核心 →
#        层6 塔 → 层7 怪 → 层8 投射物 → 层9 VFX。
#  🔴 只读 `_snap` / `controller.runtime.snapshot()`；无任何玩法写入。
# ===========================================================================
func _draw_radial(sc: float) -> void:
	_draw_radial_ground(sc)       # 层1 场地圆 + 同心环×3 + 放射刻度×8 + 层2 出生环
	_draw_all_shadows(sc)         # 层3：先画全部影（避免脏影，spec §A.3/§A.6）
	_draw_radial_slot_layer(sc)   # 层4：空槽八边形 + 威胁楔形 + 被攻击环 + 暴露图标
	_draw_radial_core(sc)         # 层5：盘 + 8 刻齿（唯一轮廓）
	_draw_radial_towers(sc)       # 层6：双层八边形塔
	_draw_radial_monsters(sc)     # 层7：12 边不规则 + 朝核心尖刺扇
	_draw_projectiles(sc)         # 层8：字段缺失 → 零绘制
	_draw_revive_flash(sc)        # 层9：爬起扩散环（沿用既有）


# ---- 纯函数工具（spec §A.9；无状态、无随机、帧间稳定）----
func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


func _oct8(c: Vector2, r: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 8:
		pts.append(c + _dir(rot + TAU * float(k) / 8.0) * r)
	return pts


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.is_empty():
		return pts
	var out := pts.duplicate()
	out.append(pts[0])
	return out


## 12 边不规则主体（共享扰动表；`out_dir` 为径向，“长轴/短轴”按 rs/ts 压伸）。
func _blob12(c: Vector2, r: float, out_dir: float, rs: float, ts: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var co := cos(out_dir)
	var si := sin(out_dir)
	for k in 12:
		var a := TAU * float(k) / 12.0
		var v := _dir(a) * (r * float(BLOB_R12[k]))
		var rad_c := (v.x * co + v.y * si) * rs
		var tan_c := (-v.x * si + v.y * co) * ts
		pts.append(c + Vector2(rad_c * co - tan_c * si, rad_c * si + tan_c * co))
	return pts


func _body_units(proto: String, elite: bool) -> float:
	var r := BODY_SWARM
	match proto:
		"Rush":
			r = BODY_RUSH
		"Tank":
			r = BODY_TANK
		_:
			r = BODY_SWARM
	if elite:
		r *= ELITE_SCALE
	return r


## 🔴 P0（spec §A.5 伪码）：环境换装档位推进。跨档边界触发 3s 过渡；首次直接落位（无过渡）。
##   `_snap["w"]` 是本刀**唯一**换装读数来源（只读；无其它字段）。
func _update_env(dt: float) -> void:
	var ti := _EnvPalette.tier_of(int(_snap.get("w", 0)))
	if _env_tier < 0:
		_env_tier = ti
		_env_prev = ti
		_env_t = 1.0
	elif ti != _env_tier:
		_env_prev = _env_tier
		_env_tier = ti
		_env_t = 0.0
	if _env_t < 1.0:
		_env_t = minf(1.0, _env_t + clampf(dt, 0.0, 0.1) / ENV_FADE_SEC)


## 🔴 P0（spec §A.5）：档间过渡取色 —— smoothstep `e(t)=t²(3−2t)` + 线性 RGB `Color.lerp`。
##   `key ∈ {"bg","field","ring"}`；`alpha` 由调用方施加（同心环 0.5 / 放射刻度 0.35）。
func _env_col(key: String, alpha: float) -> Color:
	var a: Color = _EnvPalette.get_color(_env_prev, key)
	var b: Color = _EnvPalette.get_color(_env_tier, key)
	var e := _env_t * _env_t * (3.0 - 2.0 * _env_t)
	var c := a.lerp(b, e)
	return Color(c.r, c.g, c.b, alpha)


## 🔴 P0（spec §B.2.2）：核心**盘级**极小幅呼吸（±2.5% @2.4s）。
##   内芯保留其原有更快一层（±6% @1.6s，见 `_draw_radial_core`）→ 两层不同频叠出有机感。
##   纯 `sin`，零新增状态（复用 `_vfx_t`）。
func _core_breath() -> float:
	return 1.0 + CORE_BREATH_AMP * sin(_vfx_t * TAU / CORE_BREATH_SEC)


# ---- §B.3 怪 squash&stretch 摆动（相位纯由 `pos` 派生 → 帧间稳定、零新增状态）----
## 径向拉伸幅度 A（spec §B.3.3：大原型阻尼递减，小怪更"活蹦"）。
func _sway_amp(proto: String) -> float:
	match proto:
		"Rush":
			return 0.10
		"Tank":
			return 0.04
		_:
			return 0.06      # Swarm（及回退）


## 原型相位偏移 φ_proto（spec §B.3.3：原型间错开，不同类型不同步）。
func _sway_phase(proto: String) -> float:
	match proto:
		"Rush":
			return 0.000
		"Tank":
			return 4.189     # 4π/3
		_:
			return 2.094     # 2π/3（Swarm）


## 体摆动幅 rot_amp（rad；spec §B.3.3）。
func _sway_rot(proto: String) -> float:
	match proto:
		"Rush":
			return 0.18
		"Tank":
			return 0.08
		_:
			return 0.12      # Swarm


## 圆形 blob 软影（双层同心圆近似，spec §A.3；光来自左上 → 影落右下）。
func _blob_shadow(c: Vector2, r: float, off: Vector2, a: float) -> void:
	var p := c + off
	draw_circle(p, r, Color(0.0, 0.0, 0.0, a * 0.35))
	draw_circle(p, r * 0.7, Color(0.0, 0.0, 0.0, a))


## 🔴 P0 增强 · Rim Light 内发光（spec §A.4）：本体内侧 `R − 0.55w` 叠一圈阵营色
##   细弧 —— 塔耀青 / 怪熔橙 @α0.6，宽恒定 0.8px。作用：混乱时分离相邻单位。
##   `w` = 该单位描边宽（屏幕 px）。
func _draw_rim(c: Vector2, r: float, w: float, col: Color) -> void:
	var rr := maxf(1.0, r - 0.55 * w)
	draw_arc(c, rr, 0.0, TAU, 32, col, RIM_W, true)


## 🔴 P0 增强 · 塔升级「形态」递进（spec §A.2.1 增强，**取代**"只堆层数白点"）。
##   约束（红线）：① 严格 8 次旋转对称 —— 所有附加件都落在八边形 8 个顶点/8 等分角；
##   ② 不超出 `R + 0.30u`（不侵占相邻塔位，最近塔间距仅 10.14u）；
##   ③ 零数字/文本（沿用 T-E1③ 口径）；④ 不改塔位坐标/原型语言。
##   递进（落地后一眼可辨「这座比那座强」）：
##     h≥2 内层细环 → h≥3 外圈规整护角×8（长度随等级增长）→
##     h≥5 星紫 `#7A5CFF` 顶点点缀 → h≥8 星紫外环（满级）。
func _draw_tower_form(c: Vector2, R: float, h: int, sc: float) -> void:
	# h≥2 内层细环：**深色**环叠在亮塔身（0.46R）→ 与亮体强对比，一眼可辨"多了一层"。
	if h >= 2:
		draw_arc(c, R * 0.46, 0.0, TAU, 28,
			Color(P_ALLY_DARK.r, P_ALLY_DARK.g, P_ALLY_DARK.b, 0.9),
			maxf(1.2, 0.12 * sc), true)
	# h≥3 外圈规整护角 ×8：**亮色**短三角落在八边形 8 顶点 → 严格 8 重对称、向外可辨。
	if h >= 3:
		var lv := clampf((float(h) - 3.0) / 5.0, 0.0, 1.0)
		var blen := (0.10 + (TOWER_CORNER_MAX_U - 0.10) * lv) * sc   # 0.10u → 0.30u
		var bhalf := 0.13 * sc
		for k in 8:
			var outn := _dir(TAU * float(k) / 8.0)
			var pv := c + outn * R
			var tan := Vector2(-outn.y, outn.x) * bhalf
			draw_colored_polygon(PackedVector2Array([
				pv - tan, pv + tan, pv + outn * blen]), P_ALLY)
	# h≥5 星紫 `#7A5CFF` 顶点点缀（8 重对称）→ 高等级副色标记。
	if h >= 5:
		for k in 8:
			draw_circle(c + _dir(PI / 8.0 + TAU * float(k) / 8.0) * (R * 0.60),
				maxf(1.5, 0.16 * sc), P_ALLY_2)
	# h≥8 星紫外环（满级）。
	if h >= 8:
		draw_arc(c, R + 0.16 * sc, 0.0, TAU, 32, P_ALLY_2, maxf(2.0, 0.20 * sc), true)


# ---- 层1/2：地面 decal + 出生环（spec §A.7；换装见 §A.6）----
func _draw_radial_ground(sc: float) -> void:
	var c := _to_screen(_SpaceModel.RADIAL_CORE)
	var rs := float(_SpaceModel.SPAWN_RADIUS) * sc
	# 🔴 P0（spec §A.6）：场地 / 同心环 / 放射刻度**按档取色 + 3s 过渡**（同 `env_palette.gd`）。
	var col_field := _env_col("field", 1.0)
	var col_ring := _env_col("ring", 0.5)     # 同心环 α=0.5（沿用现状，只换 RGB 基底）
	var col_spoke := _env_col("ring", 0.35)   # 放射刻度 α=0.35（同档 ring RGB）
	# 场地圆（地面基 A）—— 与父节点 Battlefield 幂等同色，保证本层自足
	draw_circle(c, (float(_SpaceModel.SPAWN_RADIUS) + 2.0) * sc, col_field)
	# 同心环 ×3（距离刻度）
	for ru in CONCENTRIC_U:
		draw_arc(c, float(ru) * sc, 0.0, TAU, 128, col_ring, maxf(1.0, 0.15 * sc), true)
	# 放射刻度 ×8（方位锚）
	for k in 8:
		var a := TAU * float(k) / 8.0
		draw_line(c, c + _dir(a) * rs, col_spoke, maxf(1.0, 0.12 * sc), true)
	# 出生环（边界）+ 方位刻度 —— 🔴 **固定不换色**（spec §A.3 / 用户拍板②）
	draw_arc(c, rs, 0.0, TAU, 160, P_SPAWN_EDGE, maxf(2.0, 0.28 * sc), true)
	for k in 8:
		var a2 := TAU * float(k) / 8.0
		draw_line(c + _dir(a2) * (rs - 0.8 * sc), c + _dir(a2) * (rs + 0.8 * sc),
			P_SPAWN_EDGE, maxf(1.5, 0.22 * sc), true)


# ---- 层3：全单位投影（先画全部影，再画全部本体）----
func _draw_all_shadows(sc: float) -> void:
	# 核心影（🔴 P0 §B.2.3：半径随盘呼吸**同步缩放** → 避免"影浮于盘外"）
	_blob_shadow(_to_screen(_SpaceModel.core_pos()), 1.15 * U_CORE * sc * _core_breath(),
		Vector2(0.10, 0.16) * sc, 0.40)
	# 塔影（越高影越远）
	if controller != null and controller.runtime != null:
		var slots: Array = _slots_arr()
		var sn: Array = controller.runtime.snapshot().get("slots", [])
		for tw in sn:
			if bool(tw.get("empty", true)):
				continue
			var si := int(tw.get("slot", -1))
			if si < 0 or si >= slots.size():
				continue
			_blob_shadow(_to_screen(slots[si]), 1.20 * U_TOWER * sc,
				Vector2(0.26, 0.34) * sc, 0.36)
	# 怪影（精英偏移更大 = 体量更高的线索）
	var ms: Array = _snap.get("monsters", [])
	for m in ms:
		var pos: Vector2 = m["pos"]
		var elite := bool(m.get("elite", false))
		var ru := _body_units(String(m["proto"]), elite)
		var off := Vector2(0.20, 0.28) * sc if elite else Vector2(0.14, 0.20) * sc
		_blob_shadow(_to_screen(pos), 1.15 * ru * sc, off, 0.32 if elite else 0.28)


# ---- 层4：塔位层 ----
func _draw_radial_slot_layer(sc: float) -> void:
	_draw_threat_wedges(sc)
	var occupied: Dictionary = {}
	if controller != null and controller.runtime != null:
		for tw in controller.runtime.player.towers:
			occupied[int(tw.slot)] = true
	for row in _slot_rows:
		var slot: int = int(row["slot"])
		if occupied.has(slot):
			continue
		var sp := _to_screen(row["pos"])
		draw_polyline(_closed(_oct8(sp, U_SLOT * sc, PI / 8.0)),
			Color(P_SLOT.r, P_SLOT.g, P_SLOT.b, 0.85), maxf(1.0, 0.12 * sc), true)
	_draw_under_attack(sc)
	_draw_exposure_icons(sc)


## 威胁方位楔形（spec §A.2.4 / **§B.1.3 扇区去重版**）：只标"哪个方位有怪"这一事实
##   （不标推荐，SR-R2）。把 N 只怪的方位**吸附到 8 个 45° 扇区**，每扇区只画 1 段弧，
##   α 随该扇区怪数递增（怪越多越亮，"这方位压力大"余光可读）→ 修掉"糊成一片" + **净减** draw call。
##   🔴 **≤ 8 段 `draw_arc`**（由 ≤N 降为 ≤8）；只用现有 `monsters[].pos`，无需新字段。
func _draw_threat_wedges(sc: float) -> void:
	var ms: Array = _snap.get("monsters", [])
	if ms.is_empty():
		return
	var core := _SpaceModel.RADIAL_CORE
	var c := _to_screen(core)
	var rs := float(_SpaceModel.SPAWN_RADIUS) * sc
	var sect: Dictionary = {}                      # idx(0..7) -> count
	for m in ms:
		var pos: Vector2 = m["pos"]
		var a := atan2(pos.y - core.y, pos.x - core.x)
		var idx := int(floor(fposmod(a, TAU) / (TAU / 8.0)))
		sect[idx] = int(sect.get(idx, 0)) + 1
	for idx in sect:
		var ac := TAU * float(idx) / 8.0 + TAU / 16.0     # 扇区中心
		var alpha := minf(0.60, 0.35 + 0.05 * float(mini(int(sect[idx]), 5)))
		draw_arc(c, rs, ac - deg_to_rad(11.0), ac + deg_to_rad(11.0), 8,
			Color(P_ENEMY.r, P_ENEMY.g, P_ENEMY.b, alpha), maxf(2.0, 0.30 * sc), true)


# ---- 层5：核心（盘 + 8 刻齿，全场唯一轮廓）----
func _draw_radial_core(sc: float) -> void:
	var c := _to_screen(_SpaceModel.core_pos())
	# 🔴 P0（spec §B.2.2）：**盘级**呼吸 ±2.5% @2.4s —— 外环/中盘/刻齿/描边/受击闪整体随缩。
	var rc := U_CORE * sc * _core_breath()
	draw_arc(c, rc, 0.0, TAU, 48, P_ALLY_DARK, maxf(2.0, 0.55 * sc), true)   # 外环
	draw_circle(c, rc * 0.72, P_ALLY)                                        # 中盘
	for k in 8:                                                              # 刻齿
		var a := TAU * float(k) / 8.0
		draw_line(c + _dir(a) * (rc * 0.86), c + _dir(a) * (rc * 1.06),
			P_ALLY_DARK, maxf(1.0, 0.18 * sc), true)
	# 🔴 内芯保留其**原有更快一层**（±6% @1.6s，spec §B.2.2）→ 两层不同频叠出"心跳/有机感"。
	var breath := 1.0 + 0.06 * sin(_vfx_t * TAU / 1.6)                        # 呼吸内芯
	draw_circle(c, rc * 0.32 * breath, P_CORE_HI)
	draw_arc(c, rc + 0.11 * sc, 0.0, TAU, 48, P_TOWER_EDGE, maxf(1.5, 0.22 * sc), true)
	# 🔴 P0 增强 · 受创闪（spec §A.2.3）：核心受击瞬间外环闪 #FF2E4E @α0.8，0.12s。
	#   本地演出计时器驱动衰减，只读 `core_hp` 帧间下降（不回写玩法）。
	if _core_flash > 0.0:
		var fp := clampf(_core_flash / CORE_FLASH_SEC, 0.0, 1.0)
		draw_arc(c, rc + 0.05 * sc, 0.0, TAU, 48,
			Color(P_ALERT.r, P_ALERT.g, P_ALERT.b, 0.8 * fp),
			maxf(2.0, 0.35 * sc), true)


# ---- 层6：塔（双层八边形 + 中心圆 + 左上高光 + 外扩描边 + 层数刻度）----
func _draw_radial_towers(sc: float) -> void:
	if controller == null or controller.runtime == null:
		return
	var snap: Dictionary = controller.runtime.snapshot()
	var towers: Array = snap.get("slots", [])
	var selected: int = int(snap.get("selected_tower_slot", -1))
	var core_slot: int = int(snap.get("core_tower_slot", -1))
	var hosts: Array = _forced_select_hosts(snap)
	var slots: Array = _slots_arr()
	for tw in towers:
		if bool(tw.get("empty", true)):
			continue
		var slot: int = int(tw.get("slot", -1))
		if slot < 0 or slot >= slots.size():
			continue
		var c := _to_screen(slots[slot])
		var R := U_TOWER * sc
		if hosts.has(slot):   # 合法宿主高亮（底圈）
			draw_arc(c, R + 0.5 * sc, 0.0, TAU, 32,
				Color(P_GOLD.r, P_GOLD.g, P_GOLD.b, 0.9), maxf(2.0, 0.22 * sc), true)
		draw_colored_polygon(_oct8(c, R, 0.0), P_ALLY_DARK)          # 底座（暗）
		draw_colored_polygon(_oct8(c, R * 0.66, PI / 8.0), P_ALLY)   # 塔身（亮，旋转 22.5°）
		draw_circle(c, R * 0.30, P_ALLY_DARK)                        # 中心圆
		draw_circle(c + Vector2(-0.28 * R, -0.28 * R), R * 0.30, Color(1.0, 1.0, 1.0, 0.9))
		_draw_rim(c, R, maxf(1.5, U_OUTLINE * sc), RIM_ALLY)         # P0 增强：内发光
		draw_polyline(_closed(_oct8(c, R + 0.5 * U_OUTLINE * sc, 0.0)),
			P_TOWER_EDGE, maxf(1.5, U_OUTLINE * sc), true)          # 外扩描边
		if slot == core_slot:   # 主塔标记（星紫）
			draw_arc(c, R + 0.5 * sc, 0.0, TAU, 28, P_ALLY_2, maxf(1.5, 0.16 * sc), true)
		if slot == selected:    # 选中高亮（耀青）
			draw_arc(c, R + 0.7 * sc, 0.0, TAU, 30, P_ALLY, maxf(2.0, 0.24 * sc), true)
		if _revive_on() and _is_disabled(slot):   # 停机态（V-8，沿用既有口径）
			draw_circle(c, R, Color(0.06, 0.07, 0.09, 0.62))
			draw_arc(c, R, 0.0, TAU, 28, Color(0.55, 0.57, 0.62, 0.55), maxf(1.0, 0.10 * sc), true)
		_draw_revive_charge(c, slot, R, sc)
		# 🔴 P0 增强：升级「形态」递进（h 越高越醒目；**取代**原"层数白点"）。
		_draw_tower_form(c, R, int(tw.get("h", 1)), sc)
		# 🔴 P0 增强：塔受击一瞬白闪（本地计时器；仅对可见塔）。
		if _tower_flash.has(slot):
			var tfp := clampf(float(_tower_flash[slot]) / TOWER_FLASH_SEC, 0.0, 1.0)
			draw_circle(c, R, Color(1.0, 1.0, 1.0, 0.6 * tfp))


# ---- 层7：怪（12 边不规则 + 朝核心尖刺扇 + 外扩描边）----
func _draw_radial_monsters(sc: float) -> void:
	var ms: Array = _snap.get("monsters", [])
	if ms.is_empty():
		return
	var core := _SpaceModel.RADIAL_CORE
	var w := maxf(1.5, U_OUTLINE * sc)
	for m in ms:
		var pos: Vector2 = m["pos"]
		var c := _to_screen(pos)
		var proto := String(m["proto"])
		var elite := bool(m.get("elite", false))
		var R := _body_units(proto, elite) * sc
		var out_dir := atan2(pos.y - core.y, pos.x - core.x)
		var rs := 1.0
		var ts := 1.0
		var n_spike := 5
		var spike_len := 0.55
		var spike_half := 0.26
		match proto:
			"Rush":
				rs = 1.5; ts = 0.75; n_spike = 4; spike_len = 0.9; spike_half = 0.14
			"Tank":
				rs = 0.85; ts = 1.25; n_spike = 6; spike_len = 0.4; spike_half = 0.30
			_:
				rs = 1.0; ts = 1.0; n_spike = 5; spike_len = 0.55; spike_half = 0.26
		if elite:
			n_spike += 1
			spike_len *= 1.3
		# 🔴 P0（spec §B.3）：squash&stretch + 摆动 —— 相位**纯由 `pos` 派生**（零新增状态、帧间稳定）。
		#   ph = θ + (−ρ)·k_ρ + φ_proto；sw = sin(ph)。
		#   θ(=out_dir，方位) 天然给每只怪不同相位偏移；−ρ·k_ρ 随接近核心平滑推进 = "在走"。
		var rho := pos.distance_to(core)
		var ph := out_dir + (-rho) * SWAY_K_RHO + _sway_phase(proto)
		var sw := sin(ph)
		var amp := _sway_amp(proto)
		var rs2 := rs * (1.0 + amp * sw)     # 径向拉伸（朝核心轴）
		var ts2 := ts * (1.0 - amp * sw)     # 切向压扁（体积近似守恒）
		var rot2 := _sway_rot(proto) * cos(ph)   # 体摆动（绕中心小角度）
		draw_colored_polygon(_blob12(c, R, out_dir + rot2, rs2, ts2), P_ENEMY)   # 主体（随摆）
		if proto == "Tank":   # 内层焦褐环
			draw_arc(c, R * 0.55, 0.0, TAU, 20, P_ENEMY_DARK, maxf(1.5, 0.16 * sc), true)
		_draw_rim(c, R, w, RIM_ENEMY)   # P0 增强：内发光（混乱时分离相邻单位）
		# 🔴 尖刺扇仍沿 `out_dir`（**朝核心，不随摆**）—— 尖刺语义 = "扑向核心"（spec §B.3.4）。
		for i in n_spike:    # 外张尖刺扇（沿"朝核心"方向）
			var a := out_dir + SPIKE_SPREAD * (float(i) - float(n_spike - 1) * 0.5)
			var tip := c + _dir(a) * (R + spike_len * sc)
			var bl := c + _dir(a - spike_half) * (R * 0.9)
			var br := c + _dir(a + spike_half) * (R * 0.9)
			draw_colored_polygon(PackedVector2Array([bl, tip, br]), P_ENEMY_DARK)
		# 🔴 外扩描边**必须与主体同参数**（`out_dir+rot2, rs2, ts2`），否则"描边错位"（spec §B.3.4）。
		draw_polyline(_closed(_blob12(c, R + w * 0.5, out_dir + rot2, rs2, ts2)),
			P_MON_EDGE, w, true)   # 外扩描边
		if elite:   # 精英环（噬品红）
			draw_arc(c, R + 0.28 * sc, 0.0, TAU, 24, P_ELITE, maxf(2.0, 0.18 * sc), true)


# ---- 层8：投射物（spec §A.2.4；snapshot 无 `projectiles` 字段 → 零绘制）----
func _draw_projectiles(sc: float) -> void:
	var ps: Array = _snap.get("projectiles", [])
	for pr in ps:
		if not (pr is Dictionary):
			continue
		var d: Dictionary = pr
		if not d.has("pos"):
			continue
		var sp := _to_screen(d["pos"])
		if String(d.get("faction", "ally")) == "enemy":
			draw_circle(sp, maxf(2.0, 0.60 * sc), P_ENEMY)
		else:
			var ang := 0.0
			if d.has("vel"):
				var vv: Vector2 = d["vel"]
				ang = atan2(vv.y, vv.x)
			draw_colored_polygon(PackedVector2Array([
				sp + _dir(ang) * (0.8 * sc),
				sp + _dir(ang + PI * 0.5) * (0.25 * sc),
				sp + _dir(ang - PI * 0.5) * (0.25 * sc)]), P_ALLY)
