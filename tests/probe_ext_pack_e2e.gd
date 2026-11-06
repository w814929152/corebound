extends SceneTree
##
## 集成探针（非 CI · 手动跑）—— 扩展包在**真实场景 + 真实商店链路**下可买可落
##
## 目的：`tests/run_ext_pack_asserts.gd` 只验数据表与池开关（静态查表）。
##   本探针补另一半：把 `scenes/battle_shop.tscn` 真跑起来，强制货架刷出扩展卡，
##   走**玩家真实操作路径**（买 → 待放置 → 落子），确认：
##     · 卡种判定正确（tower，不是 econ）→ 否则买卡只扣钱不落塔
##     · 定价走建筑卡档 12 分
##     · 落子后 `player.towers` 里真的出现 ctype = "Lance" / "Tesla"
##     · `damage_engine.dps_only()` 能算（不因未知 ctype 崩）
##
## 跑法（headless）：
##   <godot> --headless --path . --script res://tests/probe_ext_pack_e2e.gd
##

const _ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _TD := preload("res://scripts/data/tower_data.gd")

var _scn: Node = null
var _c = null
var _d = null
var _rt = null
var _wd = null
var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _chk(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	var tail := ("  " + detail) if detail != "" else ""
	print("   [%s] %s%s" % ["PASS" if ok else "FAIL", name, tail])


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _tower_ctypes() -> Array:
	var out: Array = []
	for t in _rt.player.towers:
		out.append(String(t.ctype))
	return out


func _run() -> void:
	# 🔴 开关必须在首次 `player_card_names()` 之前设置（静态池带缓存）。
	_ShopRuntime.set_extended_pack(true)

	_scn = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(_scn)
	await process_frame
	await process_frame
	_c = _scn.controller
	_d = _scn.director
	_rt = _c.runtime
	_wd = _scn.wave_director

	print("")
	print("---- [1] 扩展包已开启 ----")
	_chk("玩家池 = 10 张", _ShopRuntime.player_card_names().size() == 10,
		"got=%d" % _ShopRuntime.player_card_names().size())

	print("")
	print("---- [2] 进安全窗 + 强制货架刷出扩展卡 ----")
	# 🔴 T-C1 / E16 红线：战斗内禁止任何塔操作 → 放置必须先处于安全窗（重决策模式）。
	#    缺这一步 `request_placement()` 会被状态机拒绝（`sm.state != PLACEMENT_MODE`）。
	_d.open_shop()
	await _sleep(0.1)
	_rt.scrap = 200.0
	_rt.offers = ["Lance", "Tesla", "PirUp"]
	await _sleep(0.1)
	_chk("Lance 卡种 = tower", String(_rt.card_kind(0)) == "tower", "got=%s" % _rt.card_kind(0))
	_chk("Tesla 卡种 = tower", String(_rt.card_kind(1)) == "tower", "got=%s" % _rt.card_kind(1))
	_chk("PirUp 卡种 = reinforce", String(_rt.card_kind(2)) == "reinforce", "got=%s" % _rt.card_kind(2))
	_chk("Lance 定价 = 12（建筑卡档）", absf(float(_rt.price_at(0)) - 12.0) < 1e-9,
		"got=%.1f" % _rt.price_at(0))
	_chk("PirUp 定价 = 9（单塔效果卡档）", absf(float(_rt.price_at(2)) - 9.0) < 1e-9,
		"got=%.1f" % _rt.price_at(2))

	print("")
	print("---- [3] 买 Lance → 入待放置队列 ----")
	var scrap_before := float(_rt.scrap)
	_d.emit_signal("buy_requested", 0)
	await _sleep(0.2)
	_chk("pending 含 Lance", (_rt.pending as Array).has("Lance"), "pending=%s" % str(_rt.pending))
	_chk("扣费 12", absf(scrap_before - float(_rt.scrap) - 12.0) < 1e-9,
		"before=%.1f after=%.1f" % [scrap_before, _rt.scrap])

	print("")
	print("---- [4] 落子 → 场上真的出现 Lance ----")
	var began: bool = _c.request_placement(0)
	if not began:
		print("   (诊断) request_placement 失败：%s" % String(_rt.last_error))
	await _sleep(0.05)
	_d.exit_placement(true, 1)
	await _sleep(0.2)
	var ct1 := _tower_ctypes()
	_chk("towers 含 Lance", ct1.has("Lance"),
		"towers=%s err=%s" % [str(ct1), String(_rt.last_error)])

	print("")
	print("---- [5] 买 Tesla 并落子 ----")
	_rt.offers = ["Lance", "Tesla", "PirUp"]
	await _sleep(0.1)
	_d.emit_signal("buy_requested", 1)
	await _sleep(0.2)
	var began2: bool = _c.request_placement(0)
	if not began2:
		print("   (诊断) request_placement 失败：%s" % String(_rt.last_error))
	await _sleep(0.05)
	_d.exit_placement(true, 2)
	await _sleep(0.2)
	var ct2 := _tower_ctypes()
	_chk("towers 含 Tesla", ct2.has("Tesla"),
		"towers=%s err=%s" % [str(ct2), String(_rt.last_error)])

	print("")
	print("---- [6] 战斗侧能算 dps（未知 ctype 不崩）----")
	var dps := float(_DE.dps_only(_rt.player, _rt.cfg, _rt.geo))
	_chk("dps_only > 0", dps > 0.0, "dps=%.6f" % dps)
	_chk("Lance dps 可查（11）", absf(_TD.tower_dps("Lance") - 11.0) < 1e-9)
	_chk("Tesla dps 可查（6）", absf(_TD.tower_dps("Tesla") - 6.0) < 1e-9)

	print("")
	print("---- [7] 关闭扩展包 → 池回 6 张（回滚可用）----")
	_ShopRuntime.set_extended_pack(false)
	_chk("关闭后池 = 6 张", _ShopRuntime.player_card_names().size() == 6,
		"got=%d" % _ShopRuntime.player_card_names().size())

	print("")
	print("探针汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
