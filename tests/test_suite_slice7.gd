extends RefCounted
##
## headless 自测套件 —— 切片7「三原型+Elite MC 重扫（S5-D1 校准闸门）」
##
## 🔴 本切片的**目的**（S5-D1 校准闸门的激活前置）：
##    三原型+Elite 已实现但未激活（双开关默认 false）。激活前必须用真实 build 跑
##    300 局 MC，确认起飞率仍 ≥80%、起飞点 ∈ W10–15、B/A < 1。本套件就是这道闸门。
##
## 判据来源：`docs/phase3/slice5-verify.md` §5 S5-D1 校准闸门
##   · 多塔 B 起飞率 ≥ 80%（MC 300）
##   · 起飞点 ∈ W10–15
##   · B/A（W20 ratio 比）< 1
##
## 被测对象：
##   · `scripts/engine/wave_sim_proto.gd`（三原型+Elite 批处理战斗结算）
##   · `scripts/engine/run_loop_proto.gd`（MC 重扫运行器，shop_ai 金标本不变）
##
## 🔴 本套件**不动金标本**：`wave_sim.gd` / `run_loop.gd` / `shop_ai.gd` 一字不改。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice7
##

const TOL = 1e-12

# 🔴 G6：headless 无 global_script_class_cache → 一律 preload
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")
const _RunLoop := preload("res://scripts/engine/run_loop.gd")
const _RunLoopProto := preload("res://scripts/engine/run_loop_proto.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _WaveSimProto := preload("res://scripts/engine/wave_sim_proto.gd")
const _Stats := preload("res://scripts/engine/stats.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")

var _pass = 0
var _fail = 0
var _out: Array = []
var _geo = null


func _log(s: String) -> void:
	_out.append(s)
	print(s)


func _check(name: String, got: float, want: float, tol: float = TOL) -> void:
	var d = absf(got - want)
	var rel = 0.0
	if absf(want) > 1e-300:
		rel = d / absf(want)
	var ok = (d <= 1e-300) or (d <= tol) or (rel <= tol)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%.12f want=%.12f |d|=%s" % ["PASS" if ok else "FAIL", name, got, want, str(d)])


func _check_int(name: String, got: int, want: int) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _check_bool(name: String, got: bool, want: bool) -> void:
	var ok = (got == want)
	if ok:
		_pass += 1
	else:
		_fail += 1
	_log("   [%s] %s  got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])


# 定稿 tier 口径 cfg（与切片2 _cfg 同口径，不二次定义数值）
func _cfg(path: String) -> Dictionary:
	return _MvpConfig.cfg_of(path, 0.045, "substantial", "tier", "current", false)


# ---------------------------------------------------------------------------
#  AC-S7-1 · proto_enabled=false 退化为金标本口径（逐位等价守护）
# ---------------------------------------------------------------------------
func _test_proto_disabled_equals_golden() -> void:
	_log("--- [AC-S7-1] proto_enabled=false → 与金标本 simulate_wave 逐位等价 ---")
	var cfg := _cfg("B")
	# 用弱构筑探针遍历全波次（近阈值波次才是真正考验逐位等价的探针）
	var player = _make_weak_probe_player("B")
	for w in [1, 3, 5, 8, 10, 12, 15, 18, 20]:
		var golden := _WaveSim.simulate_wave(player, w, cfg, _geo)
		var proto_off := _WaveSimProto.simulate_wave_proto(player, w, cfg, _geo, false, false)
		_check("W%d kills（proto=false ≡ 金标本）" % w, float(proto_off["kills"]), float(golden["kills"]))
		_check("W%d leaked（proto=false ≡ 金标本）" % w, float(proto_off["leaked"]), float(golden["leaked"]))
		_check("W%d scrap（proto=false ≡ 金标本）" % w, float(proto_off["scrap_earned"]), float(golden["scrap_earned"]))


# ---------------------------------------------------------------------------
#  AC-S7-2 · 三原型+Elite 与金标本**确实不同**（校准闸门的前提：换口径=换难度曲线）
# ---------------------------------------------------------------------------
func _test_proto_enabled_differs() -> void:
	_log("--- [AC-S7-2] proto_enabled=true → 与金标本不同（换难度曲线，需 MC 校准）---")
	var cfg := _cfg("B")
	# 🔴 用**弱构筑**探针（近阈值）：强构筑后期全清看不出差异，阈值附近分布差异才显现
	var player = _make_weak_probe_player("B")
	# 遍历波次找差异（金标本单一基准怪 vs 三原型分化，漏怪分布不同）
	var diff_w := -1
	for w in range(1, 21):
		var golden := _WaveSim.simulate_wave(player, w, cfg, _geo)
		var proto_on := _WaveSimProto.simulate_wave_proto(player, w, cfg, _geo, true, true)
		if int(proto_on["kills"]) != int(golden["kills"]) or int(proto_on["leaked"]) != int(golden["leaked"]):
			diff_w = w
			_log("      首个差异波 W%d：金标本 杀%d 漏%d · 三原型+Elite 杀%d 漏%d"
				% [w, int(golden["kills"]), int(golden["leaked"]),
				   int(proto_on["kills"]), int(proto_on["leaked"])])
			break
	_check_bool("存在波次使三原型+Elite 与金标本不同（确实换了口径）", diff_w >= 0, true)


# ---------------------------------------------------------------------------
#  AC-S7-3 · S5-D1 校准闸门：三原型+Elite MC 300 局
# ---------------------------------------------------------------------------
func _test_s5d1_calibration_gate() -> void:
	_log("--- [AC-S7-3] S5-D1 校准闸门：三原型+Elite MC 300 局 ---")
	var t0 := Time.get_ticks_msec()
	# 🔴 rng 跨所有 run 连续使用（与切片2 takeoff_rate 同纪律）
	var rngA := _PyRandom.new(20260930)
	var ra := _RunLoopProto.takeoff_rate("A", _cfg("A"), 300, 20, 12, rngA, true, true)
	var rngB := _PyRandom.new(20260930)
	var rb := _RunLoopProto.takeoff_rate("B", _cfg("B"), 300, 20, 12, rngB, true, true)
	_log("      A：起飞率 %.1f%%  存活率 %.1f%%  中位起飞 W%.1f  （%d ms）"
		% [float(ra["rate"]) * 100.0, float(ra["surv"]) * 100.0, float(ra["med"]),
		   Time.get_ticks_msec() - t0])
	_log("      B：起飞率 %.1f%%  存活率 %.1f%%  中位起飞 W%.1f"
		% [float(rb["rate"]) * 100.0, float(rb["surv"]) * 100.0, float(rb["med"])])

	# 闸门①：多塔 B 起飞率 ≥ 80%
	_check_bool("闸门① B 起飞率 ≥ 80%（三原型+Elite 下仍守住）",
		float(rb["rate"]) >= 0.80, true)
	# 闸门②：起飞点 ∈ W10–15
	var medB := int(rb["med"])
	_check_bool("闸门② B 起飞点 ∈ W10–15（三原型+Elite 下仍落区间）",
		medB >= 10 and medB <= 15, true)
	# 闸门③：B/A（W20 ratio 比）< 1 —— 用决定性跑取 W20 ratio
	var outA := _RunLoopProto.run("A", _cfg("A"), 20, _geo, null, true, true)
	var outB := _RunLoopProto.run("B", _cfg("B"), 20, _geo, null, true, true)
	var w20A := _w20_ratio(outA["rows"])
	var w20B := _w20_ratio(outB["rows"])
	var ba := w20B / w20A if w20A > 0.0 else 0.0
	_log("      W20 ratio: A=%.3f  B=%.3f  → B/A=%.3f" % [w20A, w20B, ba])
	_check_bool("闸门③ B/A < 1（单核 A 仍是后期 carry）", ba < 1.0, true)


func _w20_ratio(rows: Array) -> float:
	for r in rows:
		if int(r["w"]) == 20:
			return float(r["ratio"])
	return 0.0


# ---------------------------------------------------------------------------
#  探针构筑：与切片2 决定性跑同口径的深叠主塔（保证 DPS 非平凡）
# ---------------------------------------------------------------------------
func _make_probe_player(path: String):
	var PS := preload("res://scripts/engine/player_state.gd")
	var p = PS.new()
	p.path = path
	# 单核深叠 Cannon（h=133）+ 副塔，与切片2 _build_b 同型
	p.towers = [
		PS.make_tower(0, "Arrow", 133, {}),
		PS.make_tower(1, "Arrow", 1, {}),
		PS.make_tower(2, "Cannon", 8, {"FireUp": 47}),
		PS.make_tower(3, "Cannon", 8, {"FireUp": 47}),
		PS.make_tower(4, "Frost", 8, {}),
		PS.make_tower(5, "Frost", 8, {}),
	]
	p.n_hist_max = p.towers.size()
	return p


## 弱构筑探针（近阈值）：AC-S7-2 用——强构筑后期全清看不出 golden/proto 差异，
## 阈值附近（W12/W15）漏怪分布差异才显现（金标本单一基准怪 vs 三原型分化）。
func _make_weak_probe_player(path: String):
	var PS := preload("res://scripts/engine/player_state.gd")
	var p = PS.new()
	p.path = path
	p.towers = [
		PS.make_tower(2, "Cannon", 5, {"FireUp": 10}),
		PS.make_tower(3, "Cannon", 5, {"FireUp": 10}),
	]
	p.n_hist_max = p.towers.size()
	return p


# ---------------------------------------------------------------------------
#  汇总
# ---------------------------------------------------------------------------
func run_all() -> bool:
	_log("=".repeat(78))
	_log("《守核 Corebound》MVP 切片7 · 三原型+Elite MC 重扫（S5-D1 校准闸门）—— 自测")
	_log("判据：slice5-verify §5 S5-D1 · 闸门①B起飞率≥80% ②起飞点W10-15 ③B/A<1")
	_log("=".repeat(78))

	_geo = _Geo6.build()

	_test_proto_disabled_equals_golden()
	_test_proto_enabled_differs()
	_test_s5d1_calibration_gate()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] 切片7 S5-D1 校准闸门 —— 三原型+Elite 口径过闸门，金标本零改动")
	else:
		_log("[NG] 有 %d 项未过 —— 见上方 FAIL 行（若闸门①②③破线，按兜底砍 Elite 或重扫 m_hp/m_spd）" % _fail)
	_log("=".repeat(78))
	return _fail == 0
