extends Node2D
##
## 🟠 T-P6-07 · A 档 VFX 层（装饰/爽点层）—— 投射物 / 伤害数字 / 击杀反馈
##
## 依据：`docs/phase6/vfx-art-spec.md`（美术规格）+ `docs/phase6/vfx-contract-feasibility.md`
##    （契约可行性，程基岩）。落在**独立节点**（兄弟于 `MonsterLayer`，在其之上绘制）。
##
## 🔴 为什么单独成层（而非并入 `monster_layer.gd`）：
##   `monster_layer.gd` 受 **T-E1③ 源码级硬约束**（`AC-T1-24`：渲染层代码行**不得**出现
##   `draw_string` / `Label` / `progress` —— 保证"塔底充能"等零择时读数）。
##   伤害数字（A2）**必须**用文字 → 若并入 `monster_layer.gd` 会破坏该守护。
##   → 故 A 档 VFX（含文字）独立成层：`monster_layer.gd` 保持**零文本**，本层承载文字表现。
##
## 🔴 分层纪律（control-manifest §5 / spec §C.4 —— 本层全文适用）：
##   · 只读 `WaveDirector.snapshot()` / `controller.runtime.snapshot()`；
##   · **零玩法写入、零新信号**（唯一 gameplay 触碰 = R1 一行只读键 `index`，见 `wave_director.snapshot()`）；
##   · 订阅既有 `monster_killed(m)`（**单向**通知）做击杀反馈 —— 与 `monster_layer` 订阅
##     `tower_revived` 同性质，🈚 任何反向路径；
##   · **不引入任何随机** —— 碎片方向 = 确定性黄金角 + 查表（不消费 RNG，帧间稳定）；
##   · **不改任何定稿数值**；**禁碰 `Engine.time_scale`**（hitstop / 超杀慢动作**不做**，已单列 ADR）；
##   · ⚠️ **仅 RADIAL 模式绘制**（PATH 为金标本逐位等价基准，本层恒不生效）。
##
## 🔴 诚实边界（spec §1.4）：玩法是 **hitscan 瞬时聚合**（`wave_director._substep` ②）——
##   不存在"某塔发射一发弹 × 命中某怪 × 造成 N 伤"的因果链 → 本层**全部为装饰性派生**：
##     · A1 投射物 = 氛围/爽点**装饰弹**，与真实伤害无因果（密度只由 `dps`/`h` 近似调制）；
##     · A2 伤害数字 = 帧间 `Δhp` **差分**（击杀帧显示"最后一击"= 上一帧残留 hp）；
##     · A3 击杀反馈 = 订阅既有 `monster_killed(m)` 事件。
##
## ⚠️ G6：headless 无 global_script_class_cache → 不写 class_name。
##

const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")

const MARGIN := 48.0

# ---- 阵营配色（与 `monster_layer.gd` 同源 hex，误差 0）----
const P_ALLY := Color(0.243, 0.816, 0.910)        # #3ED0E8 耀青
const P_ENEMY := Color(1.000, 0.420, 0.239)       # #FF6B3D 熔橙
const P_ENEMY_DARK := Color(0.541, 0.184, 0.110)  # #8A2F1C 焦褐
const P_ELITE := Color(0.910, 0.263, 0.498)       # #E8437F 噬品红

# ---- 通用护栏（art-bible §8.5 · 全部对象池化，禁运行时 instantiate）----
const VFX_MAX_BOLTS := 300         # 同屏投射物上限（触顶降发射频率，不堆积）
const VFX_MAX_DMG := 40            # 同屏伤害数字上限（超出聚合）
const VFX_MAX_KF_RINGS := 48       # 击杀冲击环上限（≈ 同屏 VFX 系统数上限）
const VFX_MAX_KF_PARTS := 288      # 击杀碎片总量硬上限

# ---- A1 投射物（§1）----
const BOLT_DUR_MIN := 0.10                 # 固定滞空下限（s，与距离无关）
const BOLT_DUR_MAX := 0.15                 # 固定滞空上限（s）
const BOLT_LEN := 19.0                     # 梭形长（px，16–22；屏幕空间恒定）
const BOLT_WID := 6.0                      # 梭形宽（px，5–7；长宽比 ≈3.2 ≥ 2）
const BOLT_TAIL := 8.0                     # 尾迹长（px，6–10）
const BOLT_TIP := Color(0.918, 0.984, 1.000)   # 尖端高光 #EAFBFF
const DPS_FULL := 300.0                    # dps 归一化满标（放缩 ×1→×3）

# ---- A2 伤害数字（§2）----
const DMG_CELL := Vector2(96.0, 48.0)      # 固定网格单元（§2.2）
const DMG_LIFE := 0.7                      # 数字动画时长（s，约 0.5–0.8）
const DMG_RISE := 18.0                     # 上浮像素（px，基准档；高档按档位递增）
# 🔴 同怪续喂（本层增强，治「每 tick 铺一格」）：
#   玩法是 hitscan 连续结算（每 `_WaveSim.DT`=0.1s 分配一次），每 tick 单怪都会掉血。
#   若每 tick 都新建数字，0.7s 寿命内同一只怪会铺出 7 个同值数字、按网格排成一片
#   （实测 `shots_dmg/before-02.png`：7×「2」占满 3×3）——读不出信息，只剩噪点。
#   → 同怪只保留**一个**数字：窗口内新伤害累加进它（主文本=累计伤害，右上 `×N`=次数）。
const DMG_FEED_WINDOW := 0.45              # 续喂窗口（s，自上次累加起）
const DMG_MAX_AGE := 1.0                   # 单数字最长存活（s）→ 超时断代，跟到怪的新位置
const DMG_PULSE := 0.10                    # 续喂脉冲时长（s，文本瞬间放大后回落）
const DMG_MERGE_RANGE := 140.0             # 池满合并的最大距离（px；更远宁可丢弃，不许跳格）
# 五档（§2.1）：字号 px / 颜色；档 4（超杀）= 彩虹（运行时按寿命置色）。
const DMG_TIER_SIZE: Array = [20, 26, 34, 44, 60]
const DMG_TIER_COL: Array = [
	Color(1.0, 1.0, 1.0, 1.0),           # <10%    白
	Color(1.0, 0.890, 0.541, 1.0),       # 10–30%  淡金 #FFE38A
	Color(1.0, 0.788, 0.290, 1.0),       # 30–60%  辉金 #FFC94A
	Color(1.0, 0.541, 0.169, 1.0),       # 60–100% 橙金 #FF8A2B
	Color(1.0, 1.0, 1.0, 1.0),           # 超杀    彩虹（占位，绘制时覆盖）
]

# ---- A3 击杀反馈（§3）----
const KF_LIFE := 0.3                       # 碎片 / 冲击环寿命（s）
const KF_RING_U0 := 0.5                    # 冲击环起始半径（u）
const KF_RING_U1 := 2.0                    # 冲击环终止半径（u）
const KF_SPD_TABLE: Array = [6.2, 3.4, 5.6, 4.1, 6.8, 3.7, 5.0, 4.6]   # 碎片初速（u/s，3–7 区间）
const KF_SIDES_TABLE: Array = [3, 4, 3, 4] # 碎片边数（3–4，非圆 = "有机黏腻"）
const KF_DRAG := 2.5                       # 阻力系数（v *= 1 − KF_DRAG·dt，同 `hud._gold_parts`）


# ---- 注入 ----
var director: Node = null        # WaveDirector
var time_director: Node = null   # TimeDirector（读抽屉宽）
var controller: Node = null      # ShopController（读 runtime.snapshot() 的塔位）

# ---- 纯演出本地状态（池 + 计时器 + 帧间差分缓存；**无玩法含义**）----
var _snap: Dictionary = {}
var _vfx_t: float = 0.0
var _hp_cache: Dictionary = {}         # index → {"hp","hp_max","pos"}（帧间差分）
var _hp_cache_w: int = -1              # 缓存所属波号（变化即清）
var _kill_set: Dictionary = {}         # index → true（本帧被击杀；区分"击杀消失"vs"漏怪/收尾消失"）
var _bolts: Array = []                 # A1 装饰弹池（world 坐标）
var _bolt_t: Dictionary = {}           # slot → 发射计时累积（s）
var _dmg: Array = []                   # A2 伤害数字池（screen 坐标）
var _dmg_grid: Dictionary = {}         # Vector2i 网格单元 → 失效时刻（`_vfx_t`）
var _dmg_by_owner: Dictionary = {}     # 怪 index → 活跃数字条目（同怪续喂；每帧重建）
var _kf_parts: Array = []              # A3 碎片池（world 坐标）
var _kf_rings: Array = []              # A3 冲击环池（world 坐标）


func _ready() -> void:
	# 🔴 与 MonsterLayer 一致：ALWAYS —— 安全窗 paused 下也能让碎片/数字自然衰减退场。
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()


func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	# 🔴 A3：订阅既有 `monster_killed(m)`（**单向**通知 · 携带存活 Monster 对象）。
	#   与 `monster_layer` 订阅 `tower_revived` 同性质 —— 🈚 反向路径，不回写玩法。
	if not d.is_connected("monster_killed", _on_monster_killed):
		d.monster_killed.connect(_on_monster_killed)
	queue_redraw()


func bind_time_director(d: Node) -> void:
	time_director = d
	if d == null:
		return
	if not d.is_connected("state_changed", _on_state_changed):
		d.state_changed.connect(_on_state_changed)
	queue_redraw()


func bind_controller(c: Node) -> void:
	controller = c
	if c == null:
		return
	if not c.is_connected("shop_changed", _on_redraw):
		c.shop_changed.connect(_on_redraw)
	if not c.is_connected("run_changed", _on_redraw):
		c.run_changed.connect(_on_redraw)
	queue_redraw()


func _on_state_changed(_from: int, _to: int) -> void:
	queue_redraw()


func _on_redraw() -> void:
	queue_redraw()


## 🟠 A3：击杀事件 → ① 记录击杀帧（供 A2 把"击杀消失"与"漏怪消失"分开）；
##   ② 在怪位生成击杀反馈（碎片 + 冲击环）。🔴 只读 `m`（存活对象），不回写玩法。
func _on_monster_killed(m) -> void:
	if m == null:
		return
	_kill_set[int(m.index)] = true
	if not _SpaceModel.is_radial():
		return
	var v0 := float(director.v0_) if director != null else 10.10
	_spawn_kill_fx(m.pos(v0), String(m.proto), bool(m.elite))
	queue_redraw()


func _process(delta: float) -> void:
	var dt := clampf(float(delta), 0.0, 0.1)
	_vfx_t += dt
	# ⚠️ PATH 模式：本层恒不生效（金标本逐位等价基准）。清空残留并直接返回。
	if not _SpaceModel.is_radial():
		# 🔴 VFX-PATH-01 修复（quality-lead 边界探察）：守卫**必须与下方清理动作逐一对应**。
		#   此前守卫只测 5 个容器、动作实清 7 个 → `_dmg_grid` / `_kill_set` **非空时守卫不触发**
		#   → 二者残留（`_kill_set` 在 PATH 下由 `_on_monster_killed` 逐杀写入 :150、却从不被清）。
		#   现按清理动作的**同序 8 个容器**判据，判据 ≡ 动作（新增 `_dmg_by_owner` 一并纳入）。
		if not (_bolts.is_empty() and _dmg.is_empty() and _dmg_grid.is_empty()
				and _dmg_by_owner.is_empty()
				and _kf_parts.is_empty() and _kf_rings.is_empty()
				and _hp_cache.is_empty() and _kill_set.is_empty()):
			_bolts = []
			_dmg = []
			_dmg_grid = {}
			_dmg_by_owner = {}
			_kf_parts = []
			_kf_rings = []
			_hp_cache = {}
			_kill_set = {}
			queue_redraw()
		return
	if director != null:
		_snap = director.snapshot()
	_update_dmg(dt)
	_update_bolts(dt)
	_update_kill_fx(dt)
	queue_redraw()


# ---------------------------------------------------------------------------
#  坐标映射（径向专用；🔴 与 `monster_layer._xform()` 径向分支**逐位等价**）
# ---------------------------------------------------------------------------
func _field_width() -> float:
	var vw := float(get_viewport().get_visible_rect().size.x)
	var drawer_open := false
	if time_director != null and time_director.sm != null:
		drawer_open = (int(time_director.sm.clock()["drawer"]) != 0)
	return _ShopLayout.battlefield_width(vw, drawer_open)


func _sc() -> float:
	var vw := _field_width()
	var vh := float(get_viewport().get_visible_rect().size.y)
	var span := float(_SpaceModel.SPAWN_RADIUS) + 3.0
	var sc := minf((vw - 2.0 * MARGIN) / (2.0 * span), (vh - 2.0 * MARGIN) / (2.0 * span))
	return sc if sc > 0.0 else 1.0


func _to_screen(p: Vector2) -> Vector2:
	# 径向映射：中心在视口/战场中心；`screen = center + (world − RADIAL_CORE) · sc`。
	var vw := _field_width()
	var vh := float(get_viewport().get_visible_rect().size.y)
	return Vector2(vw * 0.5, vh * 0.5) + (p - _SpaceModel.RADIAL_CORE) * _sc()


func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if n < 3:
		n = 3
	for k in n:
		pts.append(c + _dir(rot + TAU * float(k) / float(n)) * r)
	return pts


# ---------------------------------------------------------------------------
#  A2 伤害数字（§2）
# ---------------------------------------------------------------------------
## 帧间差分（§2.4）：本帧 `Δhp = 上一帧 hp − 本帧 hp`（>0 即伤害）→ 弹数字；
##   消失的怪若在击杀集 → 弹"最后一击"（= 上一帧残留 hp）；漏怪/波末收尾消失 → 不弹。
##   波号变化时清缓存（`index` 波内唯一、波间重置 → 无跨波错配）。
func _update_dmg(dt: float) -> void:
	# 🟠 寿命推进 + 过期回收：数字的"上浮 → 淡出"由此驱动（`_draw_dmg_numbers` 读 `life`/`DMG_LIFE`）。
	#   🔴 与下方 `_dmg_grid`（网格占用释放）**分开**：网格按 `_vfx_t` 释放，数字按自身 `life` 回收。
	#   `age` = 自创建的总存活（只用于"是否还允许续喂"）；`pulse` = 续喂脉冲余量。
	var live_cells: Dictionary = {}
	if not _dmg.is_empty():
		var alive: Array = []
		for e in _dmg:
			e["life"] = float(e["life"]) + dt
			e["age"] = float(e.get("age", 0.0)) + dt
			e["pulse"] = maxf(0.0, float(e.get("pulse", 0.0)) - dt / DMG_PULSE)
			if float(e["life"]) < DMG_LIFE:
				alive.append(e)
				if e.has("cell"):
					live_cells[e["cell"]] = true
			elif e.has("cell"):
				_dmg_grid.erase(e["cell"])
		_dmg = alive
	# 🔴 精确释放：数字一死就腾出它的格子（此前靠 `_vfx_t + DMG_LIFE` 批量过期，
	#   续喂会延长数字寿命 → 旧口径下格子会比数字先空出来，导致同格重叠）。
	#   兜底：`_dmg` 已空但仍有孤儿格（历史 slice/异常路径）时也要能过期清理 → 不放在上面的 if 内。
	if not _dmg_grid.is_empty():
		for k in _dmg_grid.keys():
			if not live_cells.has(k) and float(_dmg_grid[k]) <= _vfx_t:
				_dmg_grid.erase(k)
	# 同怪索引：重建（条目会被回收/slice 丢弃 → 引用必须每帧刷新，不能长期持有）
	_rebuild_dmg_owner()
	var w := int(_snap.get("w", 0))
	if w != _hp_cache_w:
		_hp_cache = {}
		_kill_set = {}
		_hp_cache_w = w
	var new_cache: Dictionary = {}
	for m in _snap.get("monsters", []):
		var idx := int(m.get("index", -1))
		if idx < 0:
			continue
		var hp := float(m.get("hp", 0.0))
		var ppos: Vector2 = m.get("pos", Vector2.ZERO)
		var old = _hp_cache.get(idx, null)
		if old != null:
			var dmg := float(old["hp"]) - hp
			if dmg > 0.0001:
				_spawn_dmg(ppos, dmg, float(m.get("hp_max", 1.0)), false, idx)
		new_cache[idx] = {"hp": hp, "hp_max": float(m.get("hp_max", 1.0)), "pos": ppos}
	for idx in _hp_cache.keys():
		if new_cache.has(idx):
			continue
		if _kill_set.has(idx):
			var old2: Dictionary = _hp_cache[idx]
			var death_dmg := float(old2["hp"])
			if death_dmg > 0.0001:
				# 击杀 → 升一档；若该怪已有活跃数字则续喂进去（一个数字收尾，不另起一格）
				_spawn_dmg(old2["pos"], death_dmg, float(old2["hp_max"]), true, idx)
			_kill_set.erase(idx)
	_hp_cache = new_cache


func _tier_of(frac: float) -> int:
	if frac > 1.0:
		return 4
	if frac >= 0.60:
		return 3
	if frac >= 0.30:
		return 2
	if frac >= 0.10:
		return 1
	return 0


## 生成一个伤害数字（分档 §2.1 · 网格吸附 §2.2 · ≤40 聚合 §2.3）。
##   `escalate`：击杀帧的"最后一击"用 —— 升一档（击杀 = 超杀档）→ 大额击杀出彩虹（§2.1）。
##   `owner_idx`：怪 index —— 有它才能做**同怪续喂**（同怪只占一格）。
##   🔴 注：玩法是贪心 hitscan（伤害按怪封顶，超杀溢出**结转下一只**）→ 单怪 `Δhp ≤ hp_max`，
##      故"超杀档"无法由 `frac>1` 直接触发；此处以"**击杀**"定义超杀（= 结束该单位的一击）。
func _spawn_dmg(world_p: Vector2, dmg: float, hp_max: float, escalate: bool = false,
		owner_idx: int = -1) -> void:
	if hp_max <= 0.0:
		return
	var sp := _to_screen(world_p)
	var tier := _tier_of(dmg / hp_max)
	if escalate:
		tier = mini(tier + 1, 4)
	# —— 同怪续喂：窗口内同一只怪的新伤害累加进原数字（不新建、不换格）——
	if owner_idx >= 0:
		var ex = _dmg_by_owner.get(owner_idx, null)
		if ex != null and float(ex["life"]) <= DMG_FEED_WINDOW \
				and float(ex.get("age", 0.0)) <= DMG_MAX_AGE:
			_feed_dmg(ex, dmg, tier)
			return
	if _dmg.size() >= VFX_MAX_DMG:
		_merge_dmg(sp, dmg, tier)
		return
	var cell := _find_free_cell(sp)
	if cell.x == -99999:
		_merge_dmg(sp, dmg, tier)
		return
	var e := {
		"base": Vector2((float(cell.x) + 0.5) * DMG_CELL.x, (float(cell.y) + 0.5) * DMG_CELL.y),
		"text": _fmt_dmg(dmg), "tier": tier, "life": 0.0, "age": 0.0, "pulse": 1.0,
		"count": 1, "amount": dmg, "owner": owner_idx, "cell": cell,
		"jitter": fmod(float(cell.x * 7 + cell.y * 13) * 0.1, TAU),
	}
	_dmg_grid[cell] = _vfx_t + DMG_LIFE
	_dmg.append(e)
	if owner_idx >= 0:
		_dmg_by_owner[owner_idx] = e
	if _dmg.size() > VFX_MAX_DMG:
		# 硬上限：丢最旧的（并精准腾出它的格子，避免"格子在、字没了"造成空等症状）
		var drop := _dmg.size() - VFX_MAX_DMG
		for i in drop:
			if _dmg[i].has("cell"):
				_dmg_grid.erase(_dmg[i]["cell"])
		_dmg = _dmg.slice(drop)
		_rebuild_dmg_owner()


## 建立 `怪index → 活跃数字` 索引（同怪续喂用；条目引用会失效 → 每帧重建）。
func _rebuild_dmg_owner() -> void:
	_dmg_by_owner.clear()
	for e in _dmg:
		var o := int(e.get("owner", -1))
		if o >= 0:
			_dmg_by_owner[o] = e


## 续喂：同怪新伤害并入已有条目 → 主文本 = 累计伤害、`count` = 次数、脉冲 + 寿命续期。
##   🔴 网格位置**不动**（§2.2 禁"乱飞"）；档位只升不降。
func _feed_dmg(e: Dictionary, dmg: float, tier: int) -> void:
	e["amount"] = float(e.get("amount", 0.0)) + dmg
	e["count"] = int(e.get("count", 1)) + 1
	e["text"] = _fmt_dmg(float(e["amount"]))
	e["tier"] = maxi(int(e["tier"]), tier)
	e["life"] = 0.0
	e["pulse"] = 1.0
	if e.has("cell"):
		_dmg_grid[e["cell"]] = _vfx_t + DMG_LIFE


## 固定网格找最近空闲单元（§2.2）。🔴 候选顺序 = **上方优先**（固定偏移表，无随机）：
##   数字优先落在怪的正上方，其次斜上、两侧，最后才是下方 ——
##   既保持"一格一字不重叠"，又让数字与怪的视觉关联稳定（此前纯螺旋外扩会让数字
##   均匀铺满怪的四周，看起来像数字在场上"散开"）。
func _find_free_cell(sp: Vector2) -> Vector2i:
	var base := Vector2i(int(floor(sp.x / DMG_CELL.x)), int(floor(sp.y / DMG_CELL.y)))
	for o in _cell_order():
		var cc := Vector2i(base.x + int(o.x), base.y + int(o.y))
		if not _dmg_grid.has(cc):
			return cc
	return Vector2i(-99999, -99999)


## 上方优先的候选偏移表（懒构建 · 排序键固定 → 帧间/进程间可复现）。
static var _CELL_ORDER: Array = []

func _cell_order() -> Array:
	if not _CELL_ORDER.is_empty():
		return _CELL_ORDER
	var arr: Array = []
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var man := absi(dx) + absi(dy)
			var pen := man
			if dy > 0:
				pen += 6          # 下方最差
			elif dy == 0 and man > 0:
				pen += 3          # 正侧次之（(0,0) 自身不罚，必须排第一）
			arr.append({"o": Vector2i(dx, dy), "k": pen * 1000 + man * 10 + absi(dx)})
	arr.sort_custom(func(a, b): return int(a["k"]) < int(b["k"]))
	for it in arr:
		_CELL_ORDER.append(it["o"])
	return _CELL_ORDER


## 聚合（§2.3）：并入**最近的**现有数字 → 累计伤害 + `×N`、升一档、重置寿命。
##   🔴 三点修正：① 不再把 `base` 改成新伤害点（否则聚合数字会"跳格"，违反 §2.2）；
##   ② 文本保留**累计伤害值**而不是只留 `×N`（原口径丢掉了唯一的数值信息）；
##   ③ 超过 `DMG_MERGE_RANGE` 宁可丢弃也不合并（避免数字跨半个屏幕"瞬移"）。
func _merge_dmg(sp: Vector2, dmg: float, tier: int) -> void:
	if _dmg.is_empty():
		return
	var best := 0
	var bd := INF
	for i in _dmg.size():
		var d: float = Vector2(_dmg[i]["base"]).distance_squared_to(sp)
		if d < bd:
			bd = d
			best = i
	if bd > DMG_MERGE_RANGE * DMG_MERGE_RANGE:
		return
	var e: Dictionary = _dmg[best]
	e["amount"] = float(e.get("amount", 0.0)) + dmg
	e["count"] = int(e.get("count", 1)) + 1
	e["text"] = _fmt_dmg(float(e["amount"]))
	# 档位随次数阶梯上升（每 4 次一档）→ 比"每合并一次升一档"稳定，不会瞬间刷成彩虹
	e["tier"] = mini(maxi(maxi(int(e["tier"]), tier), 1 + int(float(e["count"]) / 4.0)), 4)
	e["life"] = 0.0
	e["pulse"] = 1.0
	if e.has("cell"):
		_dmg_grid[e["cell"]] = _vfx_t + DMG_LIFE


func _fmt_dmg(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 10000.0:
		return "%.0fk" % (v / 1000.0)
	if v >= 1000.0:
		var s := "%.1f" % (v / 1000.0)
		if s.ends_with(".0"):
			s = s.substr(0, s.length() - 2)
		return s + "k"
	# 🔴 保底 1：低 dps 下单 tick 伤害可能 <0.5（原 `round` 会显示「0」，读起来像没打中）
	return "%d" % maxi(1, int(round(v)))


# ---------------------------------------------------------------------------
#  A1 投射物（§1）
# ---------------------------------------------------------------------------
## 装饰弹流：每塔按 `fire_hz = clamp(2+0.5h,2,12) × dps 放缩(×1→×3)` 朝**最前活怪**发一视觉弹，
##   固定滞空 0.10–0.15s；目标消失则**重定向**到新的最前怪。🔴 纯装饰，与真实伤害无因果（§1.4）。
func _update_bolts(dt: float) -> void:
	if not _bolts.is_empty():
		var front := _front_monster()
		var front_idx := int(front.get("index", -1))
		var front_pos: Vector2 = front.get("pos", Vector2.ZERO)
		var keep: Array = []
		for b in _bolts:
			b["t"] = float(b["t"]) + dt / maxf(0.0001, float(b["dur"]))
			var tp := _monster_pos_by_index(int(b["tgt"]))
			if tp == Vector2.INF:
				if front_idx >= 0:
					b["tgt"] = front_idx
					b["to"] = front_pos
			else:
				b["to"] = tp
			if float(b["t"]) < 1.0:
				keep.append(b)
		_bolts = keep
	if controller == null or controller.runtime == null:
		return
	var front2 := _front_monster()
	if front2.is_empty():
		return
	var front_pos2: Vector2 = front2.get("pos", Vector2.ZERO)
	var front_idx2 := int(front2.get("index", -1))
	var gscale := clampf(1.0 + float(_snap.get("dps", 0.0)) / DPS_FULL, 1.0, 3.0)
	var slot_pos: Array = _slots_arr()
	for tw in controller.runtime.snapshot().get("slots", []):
		if bool(tw.get("empty", true)):
			continue
		var slot := int(tw.get("slot", -1))
		if slot < 0 or slot >= slot_pos.size():
			continue
		var hz := clampf(2.0 + 0.5 * float(int(tw.get("h", 1))), 2.0, 12.0) * gscale
		var interval := 1.0 / maxf(0.5, hz)
		var acc := float(_bolt_t.get(slot, _bolt_phase(slot))) + dt
		var guard := 0
		while acc >= interval and _bolts.size() < VFX_MAX_BOLTS and guard < 4:
			guard += 1
			acc -= interval
			_spawn_bolt(slot, slot_pos[slot], front_pos2, front_idx2)
		_bolt_t[slot] = acc


func _slots_arr() -> Array:
	if controller != null and controller.runtime != null and controller.runtime.geo != null:
		return controller.runtime.geo.slots
	return []


func _front_monster() -> Dictionary:
	var best: Dictionary = {}
	var bt := INF
	for m in _snap.get("monsters", []):
		var tr := float(m.get("t_remain", INF))
		if tr < bt:
			bt = tr
			best = m
	return best


func _monster_pos_by_index(idx: int) -> Vector2:
	if idx < 0:
		return Vector2.INF
	for m in _snap.get("monsters", []):
		if int(m.get("index", -1)) == idx:
			return m.get("pos", Vector2.ZERO)
	return Vector2.INF


func _bolt_phase(slot: int) -> float:
	return fmod(float(slot) * 0.083, 1.0)


func _spawn_bolt(slot: int, tower_world: Vector2, to_world: Vector2, tgt_idx: int) -> void:
	var d := to_world - tower_world
	var dir := d.normalized() if d.length_squared() > 1e-9 else Vector2(1.0, 0.0)
	# 🔴 起点取塔缘外（§1.4「不得遮塔轮廓」）→ 弹体出生即离开塔体。
	var from := tower_world + dir * (1.70 + 0.30)      # 1.70u = U_TOWER（塔半径）
	var dur := BOLT_DUR_MIN + (BOLT_DUR_MAX - BOLT_DUR_MIN) * fmod(float(slot) * 0.37, 1.0)
	_bolts.append({"from": from, "to": to_world, "t": 0.0, "dur": dur, "tgt": tgt_idx})


# ---------------------------------------------------------------------------
#  A3 击杀反馈（§3）
# ---------------------------------------------------------------------------
func _update_kill_fx(dt: float) -> void:
	if not _kf_parts.is_empty():
		var keep: Array = []
		for pt in _kf_parts:
			pt["life"] = float(pt["life"]) + dt
			if float(pt["life"]) < KF_LIFE:
				pt["pos"] = (pt["pos"] as Vector2) + (pt["vel"] as Vector2) * dt
				pt["vel"] = (pt["vel"] as Vector2) * (1.0 - KF_DRAG * dt)
				keep.append(pt)
		_kf_parts = keep
	if not _kf_rings.is_empty():
		var keep2: Array = []
		for rg in _kf_rings:
			rg["life"] = float(rg["life"]) + dt
			if float(rg["life"]) < KF_LIFE:
				keep2.append(rg)
		_kf_rings = keep2


## 生成击杀反馈：碎片（按体量 5/12/24）+ 地面冲击环。定位 = 怪位（world）。
func _spawn_kill_fx(world_p: Vector2, proto: String, elite: bool) -> void:
	var count := 12
	var col := P_ENEMY
	match proto:
		"Rush":
			count = 5
		"Tank":
			count = 24
			col = P_ENEMY.lerp(P_ENEMY_DARK, 0.45)   # 大怪混焦褐
	if elite:
		col = P_ELITE
	# 碎片：确定性黄金角散开 + 查表速度/边数（🔴 不消费任何 RNG → 帧间可复现）。
	for k in count:
		if _kf_parts.size() >= VFX_MAX_KF_PARTS:
			break
		var ang := TAU * float(k) / float(count) + _kill_phase(world_p)
		var spd := float(KF_SPD_TABLE[k % KF_SPD_TABLE.size()])
		_kf_parts.append({
			"pos": world_p, "vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": 0.0, "col": col, "sides": int(KF_SIDES_TABLE[k % KF_SIDES_TABLE.size()]),
			"rot": ang, "spin": (3.0 if (k % 2 == 0) else -3.0),
		})
	if _kf_rings.size() >= VFX_MAX_KF_RINGS:
		_kf_rings = _kf_rings.slice(_kf_rings.size() - (VFX_MAX_KF_RINGS - 1))
	var r1 := KF_RING_U1 * (1.35 if elite else 1.0)
	_kf_rings.append({"pos": world_p, "life": 0.0, "col": col, "r1": r1})


func _kill_phase(p: Vector2) -> float:
	return fmod(absf(p.x) * 0.7 + absf(p.y) * 1.3, TAU)


# ---------------------------------------------------------------------------
#  绘制（层8 弹流 → 层9 碎片环 → 文字层数字，自上而下）
# ---------------------------------------------------------------------------
func _draw() -> void:
	if not _SpaceModel.is_radial():
		return
	var sc := _sc()
	_draw_bolts()
	_draw_kill_rings(sc)
	_draw_kill_fragments(sc)
	_draw_dmg_numbers()


func _draw_bolts() -> void:
	for b in _bolts:
		var sf := _to_screen(b["from"])
		var st := _to_screen(b["to"])
		var p := clampf(float(b["t"]), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - p, 2.0)          # EASE_OUT（"干脆"）
		var fp := sf.lerp(st, e)
		var d := st - sf
		var dir := d.normalized() if d.length_squared() > 1e-6 else Vector2(1.0, 0.0)
		var perp := Vector2(-dir.y, dir.x)
		var half_l := BOLT_LEN * 0.5
		var half_w := BOLT_WID * 0.5
		# 尾迹（沿速度反向 6–10px 渐隐）
		draw_line(fp - dir * half_l, fp - dir * (half_l + BOLT_TAIL),
			Color(P_ALLY.r, P_ALLY.g, P_ALLY.b, 0.55 * (1.0 - p)), maxf(1.0, half_w * 0.5), true)
		# 梭形（尖端朝飞行方向；长:宽 ≈ 3.2 ≥ 2）
		draw_colored_polygon(PackedVector2Array([
			fp + dir * half_l, fp + perp * half_w, fp - dir * half_l, fp - perp * half_w]), P_ALLY)
		# 尖端高光（"读得动"的关键）
		draw_circle(fp + dir * half_l, maxf(1.0, BOLT_WID * 0.35), BOLT_TIP)


func _draw_kill_rings(sc: float) -> void:
	for rg in _kf_rings:
		var p := clampf(float(rg["life"]) / KF_LIFE, 0.0, 1.0)
		var r := lerpf(KF_RING_U0 * sc, float(rg["r1"]) * sc, p)
		var col: Color = rg["col"]
		draw_arc(_to_screen(rg["pos"]), r, 0.0, TAU, 28,
			Color(col.r, col.g, col.b, 0.7 * (1.0 - p)), maxf(1.5, 0.18 * sc), true)


func _draw_kill_fragments(sc: float) -> void:
	for pt in _kf_parts:
		var p := clampf(float(pt["life"]) / KF_LIFE, 0.0, 1.0)
		var col: Color = pt["col"]
		# 🔴 屏幕空间恒定尺寸（§1.1 同口径）：本作径向场缩放较大 → 给足最小像素保证可辨。
		var r := maxf(2.5, 0.35 * sc) * (1.0 - 0.4 * p)
		var rot := float(pt["rot"]) + float(pt["spin"]) * float(pt["life"])
		draw_colored_polygon(_ngon(_to_screen(pt["pos"]), r, int(pt["sides"]), rot),
			Color(col.r, col.g, col.b, 1.0 - p))


## A2 伤害数字绘制（独立文字层 · 压在所有世界元素之上）。
##   本帧的视觉口径：
##     · 弹入：低档轻弹（×1.06，别让"每一下命中"都毫无反馈），高档强弹（×1.35）；
##     · 续喂脉冲：同一数字被累加时瞬间放大 5% 后回落 → "又打到了"的手感（幅度低于闪烁红线）；
##     · 上浮距离随档位递增（大数字飘更远，减少压怪/压塔）；
##     · 基线按**基准档**字号固定 → 升档时数字不会整体往下跳；
##     · `count>1` 时右上角补小号 `×N`（累计次数），主文本始终是**伤害值**。
func _draw_dmg_numbers() -> void:
	if _dmg.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var base_line := float(DMG_TIER_SIZE[0]) * 0.35
	for e in _dmg:
		var p := clampf(float(e["life"]) / DMG_LIFE, 0.0, 1.0)
		var tier := clampi(int(e["tier"]), 0, 4)
		var size := int(DMG_TIER_SIZE[tier])
		var col: Color = DMG_TIER_COL[tier]
		if tier == 4:   # 超杀"彩虹流光" = 2D 替代（🔴 不用 time_scale / 色差，§2.1）
			col = Color.from_hsv(fmod(_vfx_t * 0.6 + float(e["jitter"]) * 0.05, 1.0), 0.85, 1.0)
		var pop := 1.0
		if tier >= 1:   # 弹出（前 25% 起始放大）
			pop = 1.0 + 0.35 * pow(1.0 - minf(1.0, p / 0.25), 2.0)
		else:
			pop = 1.0 + 0.06 * pow(1.0 - minf(1.0, p / 0.18), 2.0)
		var pulse := float(e.get("pulse", 0.0))
		size = int(round(float(size) * pop * (1.0 + 0.05 * pulse)))
		var rise := DMG_RISE * (1.0 + 0.28 * float(tier)) * (1.0 - pow(1.0 - p, 2.0))
		var alpha := 1.0 if p <= 0.62 else clampf(1.0 - (p - 0.62) / 0.38, 0.0, 1.0)
		var base: Vector2 = e["base"]
		var jit := 0.0
		if tier == 2:   # 近似"旋转抖动"的 2D 安全替代（不碰 transform）
			jit = sin(_vfx_t * 42.0 + float(e["jitter"])) * 2.0
		var text := String(e["text"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var dp := Vector2(base.x - tw * 0.5 + jit, base.y + base_line - rise)
		var outline := clampi(int(float(size) * 0.13), 2, 6)
		draw_string_outline(font, dp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			outline, Color(0.02, 0.02, 0.04, alpha))
		draw_string(font, dp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			Color(col.r, col.g, col.b, alpha))
		# `×N`：累计次数小标（主文本是伤害值，次数交给上标 —— 信息不丢、主次分明）
		var cnt := int(e.get("count", 1))
		if cnt > 1:
			var sup := "×%d" % cnt
			var ss := maxi(14, int(float(size) * 0.60))
			var sp_ := Vector2(base.x + tw * 0.5 + 3.0 + jit, dp.y - float(size) * 0.34)
			draw_string_outline(font, sp_, sup, HORIZONTAL_ALIGNMENT_LEFT, -1, ss,
				maxi(2, int(float(ss) * 0.16)), Color(0.02, 0.02, 0.04, alpha))
			draw_string(font, sp_, sup, HORIZONTAL_ALIGNMENT_LEFT, -1, ss,
				Color(col.r, col.g, col.b, alpha * 0.95))
		if tier >= 3 and p < 0.3:   # 一次性亮环（替代不可关震屏 / 不可用色差，§2.1）
			var rp := p / 0.3
			draw_arc(Vector2(base.x, base.y - rise), 8.0 + 26.0 * rp, 0.0, TAU, 24,
				Color(col.r, col.g, col.b, 0.6 * (1.0 - rp)), 2.0, true)
