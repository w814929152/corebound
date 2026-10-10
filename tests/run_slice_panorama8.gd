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
##   P-G8-5  🔴 R-10：三原型出生极径 R_s×m_spd × 包围盒校验（按 proto 开关分档，见下）
##
## 🔴 R-10：`rho_of_t` 出生极径 = R_s×m_spd。Rush m_spd=4/3 → 出生 ρ=73.3 远超 span=58。
##    MVP `prototype_split_enabled` 默认 false → 未激活；proto 一旦开启，Rush 会出生在
##    相机包围盒外。本探针登记该待办（proto 开启前须钳制出生 ρ 或扩大 span）。
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

	# ---- P-G8-5 R-10 三原型出生极径 × 相机包围盒校验 ----
	# 出生极径 ρ_0 = R_s × m_spd（SpaceModel.rho_of_t(t_reach, m_spd)）。
	#   基准怪 m_spd=1 → ρ_0 = 55（盒内）；Rush m_spd=4/3 → ρ_0 = 73.3 > span=58
	#   （轴向来袭出生在包围盒外 → 相机看不到）。
	# 🔴 三原型分化由 WaveDirector.prototype_split_enabled 控制，MVP 默认 **false**
	#   → 影响未激活。本断言按该生产默认分档（读真身，非影子常量）：
	#     · proto 关 → 断言"当前生效出生 ρ（基准怪 m_spd=1）在盒内"，并打印待办登记；
	#     · proto 开 → 断言"三原型最大出生 ρ 在盒内"（真实闸门；几何未钳制前必红）。
	print("\n---- [P-G8-5] 三原型出生极径 × 相机包围盒（R-10）----")
	var max_m_spd := 0.0
	for k in _MonsterData.M_SPD:
		max_m_spd = maxf(max_m_spd, float(_MonsterData.M_SPD[k]))
	var spawn_rho_max := float(_SpaceModel.SPAWN_RADIUS) * max_m_spd
	_check("Rush m_spd == 4/3", float(_MonsterData.M_SPD["Rush"]), 4.0 / 3.0, 1e-12)
	_check("Swarm m_spd == 1", float(_MonsterData.M_SPD["Swarm"]), 1.0, 1e-12)
	_check("Tank m_spd == 2/3", float(_MonsterData.M_SPD["Tank"]), 2.0 / 3.0, 1e-12)
	var _probe = _WaveDirector.new()
	var proto_on := bool(_probe.prototype_split_enabled)
	_probe.free()
	print("   最大 m_spd=%.4f（Rush）→ 三原型最大出生极径 R_s×m_spd=%.2f · 包围盒内切半径 span=%.2f"
		% [max_m_spd, spawn_rho_max, span])
	print("   prototype_split_enabled（生产默认）= %s" % str(proto_on))
	if proto_on:
		_ok("P-G8-5 (proto ON) 三原型出生极径 %.2f ≤ span %.2f" % [spawn_rho_max, span],
			spawn_rho_max <= span)
	else:
		_ok("P-G8-5 (proto OFF) 生效出生极径 R_s=%.0f ≤ span=%.0f（仅基准怪 m_spd=1）"
			% [float(_SpaceModel.SPAWN_RADIUS), span],
			float(_SpaceModel.SPAWN_RADIUS) <= span)
		print("   [TODO-R10] 三原型开启后 Rush 出生极径 = %.1f > span = %.1f"
			% [spawn_rho_max, span])
		print("              → proto 开启前必须钳制出生 ρ（≤ %.1f）或扩大 span（≥ %.1f）"
			% [span, spawn_rho_max])

	print("\n===================================================================")
	print("八槽全景几何自洽汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)
