extends SceneTree
##
## 🟠 T-P6-07 `VFX-C3-01` **永久回归守卫** —— C3 径向几何缓存「抽屉开合」cross-state 断言
##   （headless · `SubViewport` 钉住视口尺寸 · 桩 `time_director` 切 drawer）
##
## 缺陷（quality-lead `docs/phase6/vfx-verify.md` §`VFX-C3-01`）：C3 缓存键曾漏「几何中心 c」维 → 
##   **1920×1080（高度受限）** 下抽屉开合 `sc` 逐位不变、仅 `c.x` 左移（−307.2px）→ 键不变 ⇒
##   `_radial_geo` 返回旧几何 ⇒ 地面几何（环×3 / 放射刻度 / 出生环 / 方位刻度）**错位整局**。
##   旧键 `Vector3(sc, vs.x, vs.y)`；修复后键 = `(c.x, c.y, sc)`（`monster_layer.gd` `_radial_geo`）。
##
## 🔴 为什么是 **cross-state**（open vs closed）：同状态对照是自证 —— 缺陷恰恰只在**状态切换**时显形，
##   同状态永远 hit。故本守卫必须比较**两个抽屉态**。
##
## 断言（两档视口各跑一遍）：
##   [G0 场景有效] 该档的 sc 行为符合预期（1080=高度受限→sc 不变「复现条件」；1920=宽度受限→sc 变）
##   [G1 中心跟随] 抽屉开合 → 几何中心 c.x 左移
##   [G2 缓存失效] 抽屉开合 → 缓存 **miss**（sig 变）AND 返回几何的 spokes 基点 **跟随新 c**（非停在旧 c）
##   [G3 命中不破] 同状态重复调用 → 缓存 **hit**（sig 不变）且几何逐位稳定（防「每帧重建」回归）
##
## 跑法： <godot> --headless --path . --script res://tests/run_vfx_cache_guard.gd
##   （亦为 `run_tests -- radial8` 的门禁件之一 → 见 `tests/run_tests.gd` RADIAL8_GATES）
##

const SPAWN_RADIUS := 55.0

# 桩：只提供 `clock()["drawer"]`（`_field_width()` 唯一读取的抽屉来源）。
class StubSM:
	var drawer: int = 0
	func _init(d: int) -> void:
		drawer = d
	func clock() -> Dictionary:
		# 只补 `_field_width()` 读取的 `drawer`；`state` 供潜在绘制路径容错（本件不绘制）。
		return {"drawer": drawer, "state": 0}

class StubTD extends Node:
	var sm: StubSM
	func _init(s: StubSM) -> void:
		sm = s


var _pass := 0
var _fail := 0
var _done := false


func _ok(name: String, cond: bool) -> void:
	print("   [%s] %s" % ["PASS" if cond else "FAIL", name])
	if cond:
		_pass += 1
	else:
		_fail += 1


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var SM = load("res://scripts/geo/space_model.gd")
	var ML = load("res://scripts/ui/monster_layer.gd")
	var prev_mode = SM.mode
	SM.mode = 1   # RADIAL
	print("=" .repeat(92))
	print("VFX-C3-01 守卫 · C3 缓存键「几何中心」cross-state 断言（headless · SubViewport 钉尺寸）")
	print("=" .repeat(92))
	# 1080：高度受限 → sc 不随抽屉变（复现缺陷条件）；1920：宽度受限 → sc 随抽屉变（对照）。
	_case(SM, ML, Vector2i(1920, 1080), true)
	_case(SM, ML, Vector2i(1920, 1920), false)
	SM.mode = prev_mode   # 防御性回退（本件通常由 run_tests 以子进程拉起，无同进程污染）
	print("")
	print("=" .repeat(92))
	print("VFX-C3-01 守卫汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	print("=" .repeat(92))
	quit(0 if _fail == 0 else 1)
	return true


func _case(SM, ML, sz: Vector2i, expect_sc_equal: bool) -> void:
	var tag := "%dx%d" % [sz.x, sz.y]
	print("\n---- [viewport %s] ----" % tag)
	var sv := SubViewport.new()
	sv.size = sz
	root.add_child(sv)
	var ml = ML.new()
	sv.add_child(ml)
	ml.visible = false   # 只测几何/缓存逻辑 → 隐藏节点以抑制 `_draw`（headless 亦会派发 _draw）

	# ---- 抽屉收起（state 0）----
	ml.time_director = StubTD.new(StubSM.new(0))
	ml._geo_sig = Vector3(-1.0, -1.0, -1.0)   # 清缓存
	var c0: Vector2 = ml._to_screen(SM.RADIAL_CORE)
	var sc0 := float(ml._xform()["sc"])
	var g0: Dictionary = ml._radial_geo(sc0, c0, SPAWN_RADIUS * sc0)
	var sig0: Vector3 = ml._geo_sig
	var spoke0: Vector2 = g0["spokes"][0][0]

	# ---- 抽屉展开（state 1 · cross-state）----
	ml.time_director = StubTD.new(StubSM.new(1))
	var c1: Vector2 = ml._to_screen(SM.RADIAL_CORE)
	var sc1 := float(ml._xform()["sc"])
	var g1: Dictionary = ml._radial_geo(sc1, c1, SPAWN_RADIUS * sc1)
	var sig1: Vector3 = ml._geo_sig
	var spoke1: Vector2 = g1["spokes"][0][0]

	print("   drawer0: sc=%.10f c=(%.4f,%.4f) sig=%s" % [sc0, c0.x, c0.y, str(sig0)])
	print("   drawer1: sc=%.10f c=(%.4f,%.4f) sig=%s" % [sc1, c1.x, c1.y, str(sig1)])
	print("   Δc.x=%.4f  sc逐位相等=%s  缓存miss(sig变)=%s  spokes跟c1=%s 停c0=%s"
		% [c1.x - c0.x, str(sc0 == sc1), str(sig1 != sig0), str(spoke1 == c1), str(spoke1 == c0)])

	# [G0] 场景有效性：本档 sc 行为符合预期（防「该档没复现缺陷条件」的假绿）。
	_ok("[%s] G0 场景有效：sc 随抽屉 %s（%s档）"
		% [tag, "不变（复现缺陷条件）" if expect_sc_equal else "改变（对照）",
		   "高度受限" if expect_sc_equal else "宽度受限"],
		(sc0 == sc1) == expect_sc_equal)
	# [G1] 几何中心 c.x 左移（抽屉占宽 → 战场变窄）
	_ok("[%s] G1 抽屉开合 → 几何中心 c.x 左移    Δc.x=%.4f" % [tag, c1.x - c0.x], c1.x < c0.x - 1.0)
	# [G2] 缓存 miss + 几何跟随新中心（缺陷核心：旧键在此会「miss=False / 停在 c0」）
	_ok("[%s] G2 抽屉开合 → 缓存 miss（sig 变）" % tag, sig1 != sig0)
	_ok("[%s] G2 几何跟随新中心（spokes 基点==c1，非停在 c0）" % tag,
		spoke1 == c1 and spoke1 != c0)
	# [G3] 同状态重复调用 → hit（sig 不变）且几何逐位稳定
	var g1b: Dictionary = ml._radial_geo(sc1, c1, SPAWN_RADIUS * sc1)
	_ok("[%s] G3 同状态重复调用 → 缓存 hit（sig 不变）" % tag, ml._geo_sig == sig1)
	_ok("[%s] G3 同状态几何逐位稳定（无随机/无漂移）" % tag,
		PackedVector2Array(g1["spawn"]) == PackedVector2Array(g1b["spawn"]))

	sv.queue_free()
