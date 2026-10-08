extends SceneTree
##
## headless 径向暴露度解析解单测（`expo` 入口）—— 阶段2 P4 暴露度地基
##
## 🔴 使命：验证 path_geometry.gd 新增的径向暴露度闭式解
##    （dist_to_core / expo_frac_of / slot_exposure_radial）与 tech-assessment §7.1
##    实测表**逐位一致**。这是暴露度语义重建的数值地基（纯增量、PATH 逐位不变）。
##
## 判据（对照 §7.1 实测表，AGGRO_R=9）：
##   d_core = 6→1.000  9→1.000  10→0.356  12→0.270  15→0.205
##            18→0.167  20→0.149  22→0.134  26→0.113  30→0.097  40→0.072
##   + 八槽 E8-A 8 个槽位的 d_core / expo_frac 登记（事实层，不定稿二值）
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script tests/run_slice_expo.gd
##

const _PathGeometry = preload("res://scripts/geo/path_geometry.gd")
const _Geo8 = preload("res://scripts/geo/geo8.gd")

const R := 9.0
const CORE := Vector2(28.0, 28.0)

# §7.1 实测表（AGGRO_R=9，可抄进单测）
const EXPO_TABLE := {
	6.0: 1.000, 9.0: 1.000, 10.0: 0.356, 12.0: 0.270, 15.0: 0.205,
	18.0: 0.167, 20.0: 0.149, 22.0: 0.134, 26.0: 0.113, 30.0: 0.097, 40.0: 0.072,
}

var _fail = 0


func _ok(name: String, cond: bool) -> void:
	print("   [%s] %s" % ["PASS" if cond else "FAIL", name])
	if not cond:
		_fail += 1


func _check(name: String, got: float, want: float, tol: float = 1e-4) -> void:
	var d: float = absf(got - want)
	# 🔴 G7：GDScript `String %` 不支持 `%e` → 用 %s + str() 打印差值。
	_ok("%s  got=%.6f want=%.6f |d|=%s" % [name, got, want, str(d)], d <= tol)


func _initialize() -> void:
	print("===================================================================")
	print("径向阶段2 · 暴露度解析解单测（P4 地基 · §7.1 实测表）")
	print("===================================================================")

	# ---- ① §7.1 实测表逐位对照 ----
	print("\n---- [①] §7.1 expo_frac 实测表（AGGRO_R=9）----")
	for d_core in [6.0, 9.0, 10.0, 12.0, 15.0, 18.0, 20.0, 22.0, 26.0, 30.0, 40.0]:
		# 构造一个距核心恰好 d_core 的塔位（放在核心正上方，方向角 90°）
		var p := Vector2(CORE.x, CORE.y + d_core)
		var got := _PathGeometry.expo_frac_of(p, CORE, R)
		_check("d_core=%.0f → expo_frac=%.3f" % [d_core, float(EXPO_TABLE[d_core])],
				got, float(EXPO_TABLE[d_core]), 5e-4)

	# ---- ② 边界：d=R 时 expo_frac=1.000（恒挨打）----
	print("\n---- [②] 边界 d=R → 1.000 ----")
	var pR := Vector2(CORE.x + R, CORE.y)   # 恰在 R 圆上
	_check("d_core=R=9 → expo_frac=1.000", _PathGeometry.expo_frac_of(pR, CORE, R), 1.0, 1e-9)
	var pJustOut := Vector2(CORE.x + R + 0.001, CORE.y)
	var fJustOut := _PathGeometry.expo_frac_of(pJustOut, CORE, R)
	# 定性断言：刚出圆即 expo_frac < 1.0（连续下降，非突变）。
	# 🔴 不写"≈0.495"的定量 _check——那会与闭式解自己比自己、纯浮点重排无意义。
	_ok("d_core=R+0.001 expo_frac=%.6f < 1.0（刚出圆即 <1，连续下降）" % fJustOut,
		fJustOut < 1.0 and fJustOut > 0.49)

	# ---- ③ 八槽 E8-A 8 槽位暴露度登记（事实层，不定稿二值）----
	print("\n---- [③] 八槽 E8-A 暴露度表（d_core / expo_frac，事实层）----")
	var geo8 = _Geo8.build8()
	var rows: Array = _PathGeometry.slot_exposure_radial(geo8.slots, R, CORE, NAN)
	print("   槽号 | d_core  | expo_frac | 读感")
	for row in rows:
		var f: float = float(row["expo_frac"])
		var tag: String
		if f >= 1.0:
			tag = "恒挨打（在来向圆内）"
		elif f >= 0.27:
			tag = "高暴露（内环枢纽）"
		elif f >= 0.15:
			tag = "中暴露"
		else:
			tag = "相对安全（外环哨位）"
		print("   S%d   | %.3f  | %.4f  | %s"
			% [int(row["slot"]), float(row["d_core"]), f, tag])

	# ③-a 断言：S6/S7 外哨 expo_frac ≈ 0.113（r=26）
	var s6 := _PathGeometry.expo_frac_of(geo8.slots[6], CORE, R)
	var s7 := _PathGeometry.expo_frac_of(geo8.slots[7], CORE, R)
	_check("S6 外哨 expo_frac ≈ 0.113", s6, 0.113, 5e-4)
	_check("S7 外哨 expo_frac ≈ 0.113", s7, 0.113, 5e-4)
	# ③-b 断言：内环 S1(r=11.565) expo_frac ≈ 0.284（最高暴露）
	var s1 := _PathGeometry.expo_frac_of(geo8.slots[1], CORE, R)
	_check("S1 内环 expo_frac ≈ 0.284（最高暴露）", s1, 0.284, 5e-4)
	# ③-c R-CS4：外圈 expo_frac ≤ 内圈 1/2
	var s5 := _PathGeometry.expo_frac_of(geo8.slots[5], CORE, R)  # S5 r=27.38 最外
	var ratio: float = s5 / s1 if s1 > 0.0 else 0.0
	_ok("R-CS4 外圈S5/内圈S1 = %.4f ≤ 0.5" % ratio, ratio <= 0.5)
	print("   S1(内)=%.4f · S5(外)=%.4f · S6(外哨)=%.4f · S7(外哨)=%.4f"
		% [s1, s5, s6, s7])

	# ---- ④ 阈值扫描（供 D-3 定稿参考，不冻结）----
	print("\n---- [④] EXPO_SAFE_MAX 阈值扫描（供 D-3 定稿，本探针不冻结）----")
	for thr in [0.10, 0.15, 0.20]:
		var rows2: Array = _PathGeometry.slot_exposure_radial(geo8.slots, R, CORE, thr)
		var safe: Array = []
		for row in rows2:
			if not bool(row["is_exposed"]):
				safe.append(int(row["slot"]))
		print("   EXPO_SAFE_MAX=%.2f → 安全位 = %s（%d 个）" % [thr, str(safe), safe.size()])

	print("\n===================================================================")
	print("径向暴露度解析解单测汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)
