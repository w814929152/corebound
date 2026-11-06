extends SceneTree
##
## 集成探针（非 CI · 手动跑）—— B-1 引导浮层在**真实场景 + 真实信号**下走完四步
##
## 目的：`tests/run_tutorial_asserts.gd` 只验状态机（喂字典）。本探针补另一半：
##   把 `scenes/battle_shop.tscn` 真跑起来，用**玩家的真实操作路径**驱动
##   （开商店 → 买建筑卡 → 放置落子 → 跑完本波 → 开下一波），确认浮层确实逐步推进。
##
## 跑法（headless）：
##   <godot> --headless --path . --script res://tests/probe_tutorial_e2e.gd
##
## 期望输出：BUY → PLACE → RUN → REPAIR 四步各命中一次（step = 1/2/3/4）。
##

var _scn: Node = null
var _tut = null
var _c = null
var _d = null
var _rt = null
var _wd = null
var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _chk(name: String, got: int, want: int) -> void:
	var ok := got == want
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("   [%s] %s  step=%d want=%d" % ["PASS" if ok else "FAIL", name, got, want])


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	_scn = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(_scn)
	await process_frame
	await process_frame
	_tut = _scn.get_node_or_null("TutorialLayer/TutorialOverlay")
	_c = _scn.controller
	_d = _scn.director
	_rt = _c.runtime
	_wd = _scn.wave_director

	print("")
	print("---- [1] 开局：应停在 BUY（买一张建筑卡）----")
	await _sleep(0.25)
	_chk("开局 → BUY", int(_tut.step), 1)
	var hud = _scn.get_node_or_null("HudLayer/Hud")
	var hint_hidden: bool = hud != null and not hud._hint_label.visible
	print("   [%s] 引导期 HUD 常驻键位行已隐藏（§7-B(b)）" % ["PASS" if hint_hidden else "FAIL"])
	if hint_hidden:
		_pass += 1
	else:
		_fail += 1

	print("")
	print("---- [2] 开商店买建筑卡 → 应推进到 PLACE ----")
	_d.open_shop()
	await _sleep(0.05)
	_rt.scrap = 100.0
	_rt.offers = ["Cannon", "FireUp", "ScrapUp"]
	_d.emit_signal("buy_requested", 0)
	await _sleep(0.25)
	_chk("买卡（入 pending）→ PLACE", int(_tut.step), 2)
	print("   pending=%d towers=%d" % [(_rt.pending as Array).size(), _rt.player.towers.size()])

	print("")
	print("---- [3] 放置落子 → 应推进到 RUN ----")
	_c.request_placement(0)
	await _sleep(0.05)
	_d.exit_placement(true, 1)
	await _sleep(0.25)
	_chk("落子（塔数 +1）→ RUN", int(_tut.step), 3)
	print("   towers=%d" % _rt.player.towers.size())

	print("")
	print("---- [4] 跑完本波 + 开下一波 → 应推进到 REPAIR ----")
	_wd.run_to_end()
	await _sleep(0.15)
	_chk("本波跑完但波次未前进 → 仍 RUN", int(_tut.step), 3)
	_d.start_next_wave()
	await _sleep(0.25)
	_chk("W2 开波 → REPAIR", int(_tut.step), 4)

	print("")
	print("探针汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
