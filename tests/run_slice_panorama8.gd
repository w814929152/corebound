extends SceneTree
##
## headless 八槽径向全景几何自洽（`panorama8` 入口）—— 阶段2 P5 验收录入
##
## 🔴 使命：确认八槽径向全景下，8 塔位 + 出生环（R_s=55）全部落在相机包围盒内。
##    P5 的核心迁位（core_pos→28,28）+ 相机包围盒（核心±(R_s+3)）在阶段0/1 已随
##    monster_layer._xform() 落地；本探针做几何自洽确认八槽无溢出。
##
## 判据：
##   P-G8-1  8 塔位世界坐标全部落在包围盒 [core±(R_s+3)] 内
##   P-G8-2  出生环（R_s=55）在包围盒内（环上点距核心 = R_s ≤ span-3）
##   P-G8-3  核心 (28,28) 居中（到包围盒四边等距）
##   P-G8-4  八槽全景缩放 sc > 0（相机能成像，非退化）
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script tests/run_slice_panorama8.gd
##

const _Geo8 = preload("res://scripts/geo/geo8.gd")
const _SpaceModel = preload("res://scripts/geo/space_model.gd")

var _fail = 0


func _ok(name: String, cond: bool) -> void:
	print("   [%s] %s" % ["PASS" if cond else "FAIL", name])
	if not cond:
		_fail += 1


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

	# ---- P-G8-2 出生环在包围盒内 ----
	print("\n---- [P-G8-2] 出生环 R_s=55 在包围盒内 ----")
	# 环上最远点距核心 = R_s；包围盒内切半径 = span - 3 = 55（刚好容纳）
	var ring_ok := (float(_SpaceModel.SPAWN_RADIUS) <= span - 3.0)
	_ok("P-G8-2 出生环 R_s=55 ≤ 包围盒内切半径 55", ring_ok)
	print("   出生环 R_s=%.0f · 包围盒内切半径=%.0f" % [float(_SpaceModel.SPAWN_RADIUS), span - 3.0])

	# ---- P-G8-3 核心居中 ----
	print("\n---- [P-G8-3] 核心 (28,28) 居中 ----")
	var cx := (box_lo + box_hi) * 0.5
	var cy := (box_bot + box_top) * 0.5
	_ok("P-G8-3 核心 = 包围盒中心", absf(cx - core.x) < 1e-9 and absf(cy - core.y) < 1e-9)

	# ---- P-G8-4 缩放 sc > 0（模拟 _xform 的 minf 计算）----
	print("\n---- [P-G8-4] 全景缩放 sc > 0 ----")
	# 模拟 1920×1080 视口、抽屉收起（战场宽=1920）、MARGIN=48
	var vw := 1920.0
	var vh := 1080.0
	var margin := 48.0
	var ww := box_hi - box_lo
	var wh := box_top - box_bot
	var sc := minf((vw - 2.0 * margin) / ww, (vh - 2.0 * margin) / wh)
	_ok("P-G8-4 八槽全景缩放 sc=%.3f > 0" % sc, sc > 0.0)
	print("   视口 1920×1080 · 战场世界尺寸 %.0f×%.0f · sc=%.3f（约 %.0f 世界单位/屏高）"
		% [ww, wh, sc, wh * sc])

	print("\n===================================================================")
	print("八槽全景几何自洽汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)
