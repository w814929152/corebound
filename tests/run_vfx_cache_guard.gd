extends SceneTree
##
## 🟠 T-P6-07 VFX 永久回归守卫（headless）—— 两条 quality-lead 复核缺陷的锁定断言
##
## ── [A] `VFX-C3-01` · C3 径向几何缓存键 ──────────────────────────────────────────────
## 缺陷（`docs/phase6/vfx-verify.md` §`VFX-C3-01`）：C3 缓存键曾漏「几何中心 c」维 →
##   **1920×1080（高度受限）** 下抽屉开合 `sc` 逐位不变、仅 `c.x` 左移（−307.2px）→ 键不变 ⇒
##   `_radial_geo` 返回旧几何 ⇒ 地面几何（环×3 / 放射刻度 / 出生环 / 方位刻度）**错位整局**。
##   旧键 `Vector3(sc, vs.x, vs.y)`；修复后 `monster_layer._radial_geo` 键 = `(c.x, c.y, sc)`。
##
## 🔴 2026-11-09 布局口径变更：商店改为**覆盖在地图上的中部浮层**，`battlefield_width()`
##   恒返回完整视口 → 开关商店**不再**改变 `sc` / `c`（旧的「抽屉占宽 → 战场变窄」场景已消失）。
##   因此 [A] 改为钉两条现行契约：
##     ① 商店开合不移动地图坐标（sc / c / 缓存键都不变，几何逐位稳定）；
##     ② 缓存键**必须含中心**：直接断言 `_geo_sig == Vector3(c.x, c.y, sc)`（C3-01 的根因守卫）。
##   旧场景（跨抽屉态 miss）由「跨视口尺寸」覆盖：两档尺寸的 c 不同 → 各自独立建几何。
##
## ── [B] `VFX-PATH-01` · PATH 清池守卫「判据 ≡ 动作」────────────────────────────────
## 缺陷：`vfx_layer._process` PATH 分支的守卫曾只测 5 个容器，但清理动作实清 7 个
##   （漏 `_dmg_grid` / `_kill_set`）→ **仅二者非空时守卫不触发 → 残留**（`_kill_set` 在 PATH 下
##   由 `_on_monster_killed` 逐杀写入、却从不被清）。修复后守卫按同序 7 容器判定。
##
## ── 断言（两组均 cross-state / 逐项对照，非自证）────────────────────────────────────
##  [A] 两档视口各 6 项：G0 商店开合不改变缩放 / G1 不移动中心 / G2 缓存 hit + 几何跟随 /
##      G2b 缓存键含中心（C3-01 根因）/ G3 命中不破（防每帧重建）
##  [B] 7 个容器逐个「仅它非空」注入 → 步进 `_process`(PATH) → 断言 7 容器全空（=0）
##
## 🔴 有效性自证（负向验证 · 见提交信息/报告）：把键/守卫临时退回旧式 → 本守卫必须 FAIL 且
##   打印可定位信息；还原 → PASS。一条「新旧都 PASS」的守卫等于没有守卫。
##
## 跑法： <godot> --headless --path . --script res://tests/run_vfx_cache_guard.gd
##   （亦为 `run_tests -- radial8` 门禁件 → `tests/run_tests.gd` RADIAL8_GATES）
##

const SPAWN_RADIUS := 55.0

# 桩：`_field_width()` 唯一读取的抽屉来源（`clock()["drawer"]`）。
class StubSM:
	var drawer: int = 0
	func _init(d: int) -> void:
		drawer = d
	func clock() -> Dictionary:
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
	var VFX = load("res://scripts/ui/vfx_layer.gd")
	var prev_mode = SM.mode

	# ================= [A] VFX-C3-01：C3 缓存键 cross-state =================
	SM.mode = 1   # RADIAL
	print("=" .repeat(92))
	print("VFX 永久守卫 · [A] VFX-C3-01（C3 缓存键「几何中心」）+ [B] VFX-PATH-01（PATH 清池判据≡动作）")
	print("=" .repeat(92))
	print("\n[A] VFX-C3-01 · C3 缓存键「几何中心」+ 商店开合不影响地图坐标")
	# 1080（高度受限）/ 1920×1920（宽度受限）：两档尺寸覆盖 xform 的两条分支。
	_case(SM, ML, Vector2i(1920, 1080))
	_case(SM, ML, Vector2i(1920, 1920))

	# ================= [B] VFX-PATH-01：PATH 清池判据≡动作 =================
	SM.mode = 0   # PATH（触发 vfx_layer._process 的 PATH 分支）
	print("\n[B] VFX-PATH-01 · PATH 清池守卫「判据 ≡ 动作」（仅单容器非空 → 步进后必全空）")
	_path_clear_case(VFX)

	SM.mode = prev_mode   # 防御性回退（本件通常由 run_tests 以子进程拉起，无同进程污染）
	print("")
	print("=" .repeat(92))
	print("VFX 守卫汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	print("=" .repeat(92))
	quit(0 if _fail == 0 else 1)
	return true


# ---------------------------------------------------------------------------
#  [A] VFX-C3-01
# ---------------------------------------------------------------------------
func _case(SM, ML, sz: Vector2i) -> void:
	var tag := "%dx%d" % [sz.x, sz.y]
	print("\n---- [viewport %s] ----" % tag)
	var sv := SubViewport.new()
	sv.size = sz
	root.add_child(sv)
	var ml = ML.new()
	sv.add_child(ml)
	ml.visible = false   # 只测几何/缓存逻辑 → 隐藏节点以抑制 `_draw`（headless 亦会派发 _draw）

	# ---- 商店收起（state 0）----
	ml.time_director = StubTD.new(StubSM.new(0))
	ml._geo_sig = Vector3(-1.0, -1.0, -1.0)   # 清缓存
	var c0: Vector2 = ml._to_screen(SM.RADIAL_CORE)
	var sc0 := float(ml._xform()["sc"])
	var g0: Dictionary = ml._radial_geo(sc0, c0, SPAWN_RADIUS * sc0)
	var sig0: Vector3 = ml._geo_sig
	var spoke0: Vector2 = g0["spokes"][0][0]

	# ---- 商店展开（state 1 · cross-state）----
	ml.time_director = StubTD.new(StubSM.new(1))
	var c1: Vector2 = ml._to_screen(SM.RADIAL_CORE)
	var sc1 := float(ml._xform()["sc"])
	var g1: Dictionary = ml._radial_geo(sc1, c1, SPAWN_RADIUS * sc1)
	var sig1: Vector3 = ml._geo_sig
	var spoke1: Vector2 = g1["spokes"][0][0]

	print("   overlay0: sc=%.10f c=(%.4f,%.4f) sig=%s" % [sc0, c0.x, c0.y, str(sig0)])
	print("   overlay1: sc=%.10f c=(%.4f,%.4f) sig=%s" % [sc1, c1.x, c1.y, str(sig1)])
	print("   Δc=(%.4f,%.4f)  sc逐位相等=%s  sig相等=%s  spokes跟c1=%s"
		% [c1.x - c0.x, c1.y - c0.y, str(sc0 == sc1), str(sig1 == sig0), str(spoke1 == c1)])

	# [G0] 商店开合不改变缩放（地图按完整视口绘制）。
	_ok("[%s] G0 商店开合 → sc 逐位不变（覆盖式浮层）" % tag, sc0 == sc1)
	# [G1] 坐标映射不变：中心不移动。
	_ok("[%s] G1 商店开合 → 几何中心不变    Δc=(%.4f,%.4f)"
		% [tag, c1.x - c0.x, c1.y - c0.y], c1 == c0)
	# [G2] 同一几何 → 缓存命中（不因开关商店重建），几何基点仍是当前中心。
	_ok("[%s] G2 商店开合 → 缓存 hit（sig 不变）" % tag, sig1 == sig0)
	_ok("[%s] G2 几何基点 == 当前中心 c1" % tag, spoke1 == c1)
	# [G2b] 🔴 C3-01 根因守卫：缓存键必须由 (c.x, c.y, sc) 组成 —— 漏中心维会在这里翻红。
	_ok("[%s] G2b 缓存键 == Vector3(c.x, c.y, sc)（中心必须入键）" % tag,
		sig1 == Vector3(c1.x, c1.y, sc1))
	# [G3] 同状态重复调用 → hit（sig 不变）且几何逐位稳定
	var g1b: Dictionary = ml._radial_geo(sc1, c1, SPAWN_RADIUS * sc1)
	_ok("[%s] G3 同状态重复调用 → 缓存 hit（sig 不变）" % tag, ml._geo_sig == sig1)
	_ok("[%s] G3 同状态几何逐位稳定（无随机/无漂移）" % tag,
		PackedVector2Array(g1["spawn"]) == PackedVector2Array(g1b["spawn"]))

	sv.queue_free()


# ---------------------------------------------------------------------------
#  [B] VFX-PATH-01
# ---------------------------------------------------------------------------
## 对 8 个容器逐个「仅它非空」注入 → 步进 `_process`（PATH）→ 断言**8 容器全空**。
## 🔴 cross-state 精神：注入态（1）→ 步进后态（0）必须反转；旧守卫下 `_dmg_grid`/`_kill_set`
##   两例会停在 1（残留），即本组会对旧实现 FAIL。
func _path_clear_case(VFX) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1920, 1080)
	root.add_child(sv)
	var targets: Array = ["_bolts", "_dmg", "_dmg_grid", "_dmg_by_owner", "_kf_parts", "_kf_rings", "_hp_cache", "_kill_set"]
	for target in targets:
		var vx = VFX.new()
		sv.add_child(vx)
		vx.visible = false
		vx.set_process(false)   # 阻止引擎自动补调 → 注入→步进可控
		_inject_one(vx, String(target))
		var before := _count_nonempty(vx)
		vx._process(0.016)      # PATH 模式（SM.mode=0）
		var after := _count_nonempty(vx)
		print("   [%s] 注入前非空=%d → 步进 _process 后非空=%d" % [target, before, after])
		_ok("[PATH] 仅 `%s` 非空(=%d) → 步进后 8 容器全空(=%d)" % [target, before, after],
			before == 1 and after == 0)
	sv.queue_free()


func _inject_one(vx, which: String) -> void:
	match which:
		"_bolts":
			vx._bolts = [{"from": Vector2.ZERO, "to": Vector2.ONE, "t": 0.0, "dur": 1.0, "tgt": -1}]
		"_dmg":
			vx._dmg = [{"base": Vector2.ZERO, "text": "1", "tier": 0, "life": 0.0, "count": 1, "jitter": 0.0}]
		"_dmg_grid":
			vx._dmg_grid = {Vector2i(0, 0): 999.0}
		"_dmg_by_owner":
			vx._dmg_by_owner = {0: {"owner": 0, "amount": 1.0, "count": 1}}
		"_kf_parts":
			vx._kf_parts = [{"pos": Vector2.ZERO, "vel": Vector2.ZERO, "life": 0.0,
				"col": Color(1, 0, 0), "sides": 3, "rot": 0.0, "spin": 0.0}]
		"_kf_rings":
			vx._kf_rings = [{"pos": Vector2.ZERO, "life": 0.0, "col": Color(1, 0, 0), "r1": 2.0}]
		"_hp_cache":
			vx._hp_cache = {0: {"hp": 1.0, "hp_max": 1.0, "pos": Vector2.ZERO}}
		"_kill_set":
			vx._kill_set = {0: true}


func _count_nonempty(vx) -> int:
	var n := 0
	if not vx._bolts.is_empty():
		n += 1
	if not vx._dmg.is_empty():
		n += 1
	if not vx._dmg_grid.is_empty():
		n += 1
	if not vx._dmg_by_owner.is_empty():
		n += 1
	if not vx._kf_parts.is_empty():
		n += 1
	if not vx._kf_rings.is_empty():
		n += 1
	if not vx._hp_cache.is_empty():
		n += 1
	if not vx._kill_set.is_empty():
		n += 1
	return n
