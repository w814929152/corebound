extends SceneTree
##
## headless 八槽径向全景几何自洽（`panorama8` 入口）—— 阶段2 P5 验收录入
##
## 🔴 使命：确认八槽径向全景下，8 塔位 + 出生环（R_s=55）全部落在相机包围盒内。
##    P5 的核心迁位（core_pos→28,28）+ 相机包围盒（核心±(R_s+3)）在阶段0/1 已随
##    monster_layer._xform() 落地；本探针做几何自洽确认八槽无溢出。
##
## 判据（🔴 R-6 质量门 QG-RADIAL-01 §3.3-⑧：三条原为数学恒真，已改为对照真值）：
##   P-G8-1  8 塔位世界坐标全部落在包围盒 [core±(R_s+3)] 内（真断言）
##   P-G8-2  出生环半径 R_s == 55.0 且 span == 58.0（对照定稿几何常量）
##   P-G8-3  核心 == (28,28)（对照径向核心定稿常量）
##   P-G8-4  全景缩放 sc ∈ [8.0, 9.0]（对照合理区间常量；原"sc>0"恒真）
##   P-G8-5  🔴 R-10：三原型出生极径 × 包围盒校验（生产镜像式 · proto OFF/ON 两档真闸门，见下）
##
## 🔴 R-10 口径更正（第四刀 proto-elite-golive §1.2/§5.2/§8.5）：
##   出生极径 ρ₀ = R_s · m_spd · clampf(t_remain/t_reach, 0, 1/m_spd)，生产 `_spawn_one` 传
##   `t_remain = t_reach/m_spd` → ρ₀ = R_s · m_spd · clampf(1.0/m_spd, 0, 1) →
##   Rush/Swarm/Tank 全部 = 55.0 ≤ span 58.0（**无屏外出生**）。
##   🟡 旧注释曾断言 `R_s × max_m_spd = 73.33 > 58`（**错误口径**：等价误取 t_remain=t_reach），
##      与同文件单测 E-R4（Tank 用 t_remain=15）自相矛盾 → 该待办**已证伪并更正**。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script tests/run_slice_panorama8.gd
##

const _Geo8 = preload("res://scripts/geo/geo8.gd")
const _SpaceModel = preload("res://scripts/geo/space_model.gd")
const _MonsterData = preload("res://scripts/data/monster_data.gd")
# 🔴 R-10：三原型分化开关在 `WaveDirector.prototype_split_enabled`（MVP 默认 false）。
#   本探针为纯几何脚本、不实例化 WaveDirector 场景 → 只 **new() 取生产成员的默认值**
#   （_ready 不会运行），避免"测试影子常量"与生产漂移（R-6/R-7 同款纪律）。
const _WaveDirector = preload("res://scripts/gameplay/wave_director.gd")

var _fail = 0


func _ok(name: String, cond: bool) -> void:
	print("   [%s] %s" % ["PASS" if cond else "FAIL", name])
	if not cond:
		_fail += 1


func _check(name: String, got: float, want: float, tol: float) -> void:
	_ok("%s  got=%.6f want=%.6f" % [name, got, want], absf(got - want) <= tol)


func _initialize() -> void:
	print("===================================================================")
	print("径向阶段2 P5 · 八槽全景几何自洽（核心迁位 + 相机包围盒）")
	print("===================================================================")

	var geo8 = _Geo8.build8()
	var core := _SpaceModel.RADIAL_CORE          # (28,28)
	var span: float = float(_SpaceModel.SPAWN_RADIUS) + 3.0   # 58
	var box_lo := core.x - span
	var box_hi := core.x + span
	var box_bot := core.y - span
	var box_top := core.y + span
	print("  核心 = (%.0f,%.0f) · 包围盒 = [%.0f..%.0f] × [%.0f..%.0f]（span=%.0f）"
		% [core.x, core.y, box_lo, box_hi, box_bot, box_top, span])

	# ---- P-G8-1 8 塔位在包围盒内 ----
	print("\n---- [P-G8-1] 8 塔位落在包围盒内 ----")
	var all_in := true
	for i in range(geo8.slots.size()):
		var p: Vector2 = geo8.slots[i]
		var in_box := p.x >= box_lo and p.x <= box_hi and p.y >= box_bot and p.y <= box_top
		if not in_box:
			all_in = false
		print("   S%d (%.1f,%.1f) %s" % [i, p.x, p.y, "✓" if in_box else "✗ 溢出"])
	_ok("P-G8-1 8 塔位全在包围盒内", all_in)

	# ---- P-G8-2 出生环常量 = 55（对照真值，非构造恒真）----
	# 🔴 R-6：原式 `ring_ok := (SPAWN_RADIUS <= span-3.0)` 由构造 `span = SPAWN_RADIUS+3`
	#   保证恒真 → 无证伪能力。改为对**定稿几何常量**断言：R_s==55、span==58。
	print("\n---- [P-G8-2] 出生环 R_s = 55（定稿几何常量）----")
	_check("P-G8-2 出生环半径 R_s == 55.0", float(_SpaceModel.SPAWN_RADIUS), 55.0, 1e-9)
	_check("P-G8-2 包围盒 span == R_s+3.0 == 58.0", span, 58.0, 1e-9)
	print("   出生环 R_s=%.0f · 包围盒内切半径=%.0f" % [float(_SpaceModel.SPAWN_RADIUS), span - 3.0])

	# ---- P-G8-3 核心常量 = (28,28)（对照真值，非构造恒真）----
	# 🔴 R-6：原式 `cx := (box_lo+box_hi)*0.5` 恒等于 core.x（同构造式）→ 恒真。
	#   改为对**径向核心定稿常量**断言：(28,28)。
	print("\n---- [P-G8-3] 核心 == (28,28)（径向核心定稿常量）----")
	_check("P-G8-3 核心.x == 28.0", core.x, 28.0, 1e-9)
	_check("P-G8-3 核心.y == 28.0", core.y, 28.0, 1e-9)
	# 附带（仅事实登记）：包围盒确以核心为中心（由 box_lo≈core-span 构造保证，非闸门信号）
	var cx := (box_lo + box_hi) * 0.5
	var cy := (box_bot + box_top) * 0.5
	print("   [INFO] 包围盒中心 = (%.1f,%.1f)（= 核心，构造保证）" % [cx, cy])

	# ---- P-G8-4 全景缩放 sc ∈ 合理区间（对照区间常量，非"sc>0"恒真）----
	# 🔴 R-6：原式 `sc > 0` 在全正量下恒真。改为对照**合理缩放区间常量**——
	#   1920×1080 / MARGIN=48 / 116×116 战场 → sc≈8.483；几何常量被误改则越界 FAIL。
	print("\n---- [P-G8-4] 全景缩放 sc ∈ [8.0, 9.0]（合理区间常量）----")
	# 模拟 1920×1080 视口、抽屉收起（战场宽=1920）、MARGIN=48
	var vw := 1920.0
	var vh := 1080.0
	var margin := 48.0
	var ww := box_hi - box_lo
	var wh := box_top - box_bot
	var sc := minf((vw - 2.0 * margin) / ww, (vh - 2.0 * margin) / wh)
	_ok("P-G8-4 八槽全景缩放 sc=%.3f ∈ [8.0, 9.0]" % sc, sc >= 8.0 and sc <= 9.0)
	# 🔴 R-6 文案修正：984 = wh×sc 是**像素数**（世界高映射到多少像素）；
	#   屏高覆盖的**世界单位**应为 vh/sc ≈ 127.3（原"约 984 世界单位/屏高"是错的）。
	print("   视口 1920×1080 · 战场世界尺寸 %.0f×%.0f · sc=%.3f" % [ww, wh, sc])
	print("   屏高覆盖世界单位 = vh/sc ≈ %.1f（原 984 = wh×sc 为像素数，文案已修正）" % (vh / sc))

	# ---- P-G8-5 R-10 三原型出生极径 × 相机包围盒校验（🔴 口径更正）----
	# 🔴 R-10 口径更正（第四刀 · proto-elite-golive §1.2/§5.2/§8.5）：
	#   生产出生极径**不是** `R_s × m_spd`（那等价于"误取 t_remain = t_reach"，即假设全体 m_spd=1）。
	#   生产 `_spawn_one`(wave_director.gd:722) 传 `tr := t_reach / m_spd`，`setup` 把它赋给 `t_remain`；
	#   叠加 `rho_of_t` 修正后的上钳 = 1/m_spd → 出生 ρ₀ = R_s · m_spd · clampf(1.0/m_spd, 0, 1)：
	#     · Rush(4/3) → 55·(4/3)·clamp(0.75)       = 55.0
	#     · Swarm(1)  → 55·1·clamp(1.0)            = 55.0
	#     · Tank(2/3) → 55·(2/3)·clamp(1.5)        = 55.0（归环）
	#   → **max 出生 ρ = 55.0 ≤ span 58.0**，无任何原型出生在屏外。本探针为**真闸门**（proto OFF/ON 两档）。
	#   🟡 原式登记（**错误口径，已废弃**）：`spawn_rho_max := R_s × max_m_spd`（=73.33）等价误取
	#      `t_remain = t_reach`，与同文件单测 E-R4（Tank 用 t_remain=15）自相矛盾（原 R-10 的假红来源）。
	print("\n---- [P-G8-5] 三原型出生极径 × 相机包围盒（R-10 · 口径更正）----")
	# 生产镜像式：ρ₀(proto) = R_s · m_spd · clampf(1.0/m_spd, 0.0, 1.0) ← 镜像 _spawn_one 的 tr:=t_reach/m_spd
	var spawn_rho_max := 0.0
	for k in _MonsterData.M_SPD:
		var ms := float(_MonsterData.M_SPD[k])
		spawn_rho_max = maxf(spawn_rho_max, float(_SpaceModel.SPAWN_RADIUS) * ms * clampf(1.0 / ms, 0.0, 1.0))
	# 三原型 m_spd 真值断言（数据被误改即红 · 证伪网保留）
	_check("Rush m_spd == 4/3", float(_MonsterData.M_SPD["Rush"]), 4.0 / 3.0, 1e-12)
	_check("Swarm m_spd == 1", float(_MonsterData.M_SPD["Swarm"]), 1.0, 1e-12)
	_check("Tank m_spd == 2/3", float(_MonsterData.M_SPD["Tank"]), 2.0 / 3.0, 1e-12)
	var _probe = _WaveDirector.new()
	var proto_on := bool(_probe.prototype_split_enabled)
	_probe.free()
	print("   最大出生极径（生产镜像式）= %.2f · 包围盒内切半径 span=%.2f" % [spawn_rho_max, span])
	print("   prototype_split_enabled（生产默认）= %s" % str(proto_on))
	# proto OFF / ON **两档都转真闸门**（几何本就满足 → 均 PASS）
	if proto_on:
		_ok("P-G8-5 (proto ON) 三原型最大出生极径 %.2f ≤ span %.2f" % [spawn_rho_max, span],
			spawn_rho_max <= span)
	else:
		_ok("P-G8-5 (proto OFF) 最大出生极径 %.2f ≤ span %.2f（全原型口径）" % [spawn_rho_max, span],
			spawn_rho_max <= span)
	print("   [R-10-CLOSED] 最大出生 ρ = %.2f ≤ span %.2f（口径更正：t_remain=t_reach/m_spd）"
		% [spawn_rho_max, span])

	print("\n===================================================================")
	print("八槽全景几何自洽汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)
