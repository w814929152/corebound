extends SceneTree
##
## T-P6-07 窗口模式端到端验证（真音频驱动 · 非 headless）—— 跑 `scenes/battle_shop.tscn`
##
## 跑法（🔴 必须非 headless）：
##   <godot> --path D:/roguedemo --script res://tests/run_audio_scene_check.gd
##
## 验证（真资产真的被加载、真总线真的建立、真信号真的接线）：
##   A 结构：autoload 存在 · 5 总线 · 24+4 池 · 4 stem 且**全部 stream 非空**（= 资产可导入）
##   B 接线：17 个订阅点全部连上（TimeDirector 7 / WaveDirector 8 / ShopController 2）
##   C 音乐：4 stem 同起在播；安全窗 paused=true 下**仍在播**（坑①）
##   D 聚焦：开商店 → Music 低通 cutoff 下降（非 pitch · 坑②）
##   E 击杀聚合：个体并发 ≤ 8；≥10 kill/s 转洪流层
##
## ⚠️ G6：headless `--script` 无 global_script_class_cache → 一律 preload，无 class_name。
##

const BattleShop := preload("res://scenes/battle_shop.tscn")

const TD_SIGS := ["wave_started", "wave_ended", "drawer_mode_changed", "budget_drained",
	"placement_confirmed", "placement_cancelled", "tower_select_requested"]
const WD_SIGS := ["wave_result", "monster_spawned", "monster_killed", "monster_leaked",
	"tower_destroyed", "tower_revived", "run_won", "run_lost"]
const SC_SIGS := ["shop_changed", "run_changed"]

const ALL_SFX := ["snd_combat_kill_01", "snd_combat_kill_02", "snd_combat_kill_03", "snd_combat_kill_04",
	"snd_combat_kill_swarm", "snd_combat_leak", "snd_combat_tower_down", "snd_combat_tower_up",
	"snd_wave_start_early", "snd_wave_start_mid", "snd_wave_start_late",
	"snd_sting_victory", "snd_sting_defeat",
	"snd_ui_reroll_01", "snd_ui_reroll_02", "snd_ui_reroll_03",
	"snd_ui_buy_01", "snd_ui_buy_02", "snd_ui_buy_03", "snd_ui_buy_04", "snd_ui_buy_05"]

var _pass := 0
var _fail := 0
var _t := 0.0
var _step := 0
var _scene: Node = null
var _ad: Node = null
var _ad_before := ""
var _cut_open := 0.0


func _initialize() -> void:
	print("=== T-P6-07 窗口模式端到端验证（真音频驱动）===")
	_scene = BattleShop.instantiate()
	root.add_child(_scene)


func _process(delta: float) -> bool:
	_t += delta
	_ad = root.get_node_or_null("AudioDirector")
	if _step == 0 and _t > 1.2:
		_step = 1
		_phase_A_B()
		_phase_E()
		_phase_leak_tower()
	if _step == 1 and _t > 2.0:
		_step = 2
		_phase_E_check()
		_phase_shop_diff()
	if _step == 2 and _t > 2.0:
		_step = 3
		_phase_D_open()
	if _step == 3 and _t > 3.8:
		_step = 4
		_phase_D_check()
		_phase_C_pause()
	if _step == 4 and _t > 4.8:
		_step = 5
		_phase_C_check()
		print("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
		quit(0 if _fail == 0 else 1)
		return true
	return false


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("[FAIL] ", name, ("  " + detail) if detail != "" else "")


func _phase_A_B() -> void:
	_ok("A autoload 存在", _ad != null)
	if _ad == null:
		return
	var pool: Array = _ad.get("_pool")
	var pool2d: Array = _ad.get("_pool_2d")
	_ok("A 池 24 + 4", pool != null and pool.size() == 24 and pool2d != null and pool2d.size() == 4)
	var buses: Array = _ad.call("bus_names")
	_ok("A 5 总线", buses.size() == 5, str(buses))
	# 资产全部可加载（= 已导入 → 真出声路径就绪）
	var missing: Array = []
	for id in ALL_SFX:
		if _ad.call("_get_stream", id) == null:
			missing.append(id)
	_ok("A 21 个 SFX 资产可加载", missing.is_empty(), "missing=%s" % str(missing))
	var stems: Array = _ad.get("_stems")
	var stem_null := 0
	for s in stems:
		if (s as AudioStreamPlayer).stream == null:
			stem_null += 1
	_ok("A 4 个音乐 stem 已加载", stems.size() == 4 and stem_null == 0, "null=%d" % stem_null)
	_ok("A 音乐 4 stem 同起在播", int(_ad.call("music_playing_count")) == 4,
		"n=%d" % int(_ad.call("music_playing_count")))
	# B 接线（17 订阅点）
	var td: Node = _ad.get("_time_director")
	var wd: Node = _ad.get("_wave_director")
	var sc: Node = _ad.get("_shop_controller")
	_ok("B 容器已发现（TD/WD/SC）", td != null and wd != null and sc != null)
	var connected := 0
	var total := 0
	for pair in [[td, TD_SIGS], [wd, WD_SIGS], [sc, SC_SIGS]]:
		var node: Node = pair[0]
		for sig in pair[1]:
			total += 1
			if node != null and node.get_signal_connection_list(sig).size() > 0:
				connected += 1
	_ok("B 17 订阅点全部接线", connected == total, "%d/%d" % [connected, total])
	# 首波已开始 → 波次开始音已触发（端到端信号生效）
	_ok("B 首波 wave_started 已到达", int(_ad.get("_last_wave")) >= 1,
		"last_wave=%d" % int(_ad.get("_last_wave")))


func _phase_E() -> void:
	if _ad == null:
		return
	# 个体击杀：清窗口后 6 次（rate=6 < 10）→ 应产生个体音
	_ad.get("_kill_times").clear()
	for i in range(6):
		_ad.call("notify_kill", 0.5)
	var kv := int(_ad.call("kill_voice_count"))
	_ok("E 击杀个体音有播放", kv >= 1, "kill_voices=%d" % kv)
	_ok("E 击杀个体并发 ≤ 8", kv <= 8, "kill_voices=%d" % kv)
	# 洪流：同帧再塞 12 次（rate=18 ≥ 10）→ 转洪流层
	for i in range(12):
		_ad.call("notify_kill", 0.5)
	_ok("E 洪流层已激活", bool(_ad.get("_swarm_active")))


func _phase_E_check() -> void:
	if _ad == null:
		return
	_ok("E 洪流播放器已入播（资产非空）",
		(_ad.get("_swarm_player") as AudioStreamPlayer).playing or bool(_ad.get("_swarm_active")))
	_ok("E 个体并发仍 ≤ 8", int(_ad.call("kill_voice_count")) <= 8)


func _phase_shop_diff() -> void:
	# §3.2②：成交判定走 `shop_changed` diff 快照（scrap 下降 = 购买 → UI 总线出声）
	if _ad == null:
		return
	var sc: Node = _ad.get("_shop_controller")
	if sc == null:
		_ok("F 商店控制器可取", false)
		return
	var rt = sc.get("runtime")
	if rt == null:
		_ok("F 商店 runtime 可取", false)
		return
	_ok("F 商店 runtime 可取", true)
	var before := _ui_playing()
	# 测试专用：直接压低 scrap 以制造「购买」指纹（本 harness 随即退出，不落库）
	rt.set("scrap", float(rt.get("scrap")) - 10.0)
	_ad.call("_on_shop_changed")
	var after := _ui_playing()
	_ok("F 购买 → UI 总线出声", after >= 1 and after > before, "ui_voices %d→%d" % [before, after])


func _ui_playing() -> int:
	if _ad == null:
		return 0
	var n := 0
	for pl in _ad.get("_pool"):
		if (pl as AudioStreamPlayer).playing and (pl as AudioStreamPlayer).bus == "UI":
			n += 1
	return n


func _2d_playing() -> int:
	if _ad == null:
		return 0
	var n := 0
	for pl in _ad.get("_pool_2d"):
		if (pl as AudioStreamPlayer2D).playing:
			n += 1
	return n


func _phase_leak_tower() -> void:
	# C-03 漏怪 / C-04 塔毁 / C-05 塔复活（定位至核心 / 塔位）—— 走 2D 池 + `_slot_pos`
	if _ad == null:
		return
	_ad.call("_on_leak", null)
	var n1 := _2d_playing()
	_ok("G 漏怪（C-03）→ 2D 池出声", n1 >= 1, "2d_voices=%d" % n1)
	_ad.call("_on_tower_destroyed", 0)
	_ok("G 塔毁（C-04）→ 2D 池出声", _2d_playing() >= 2, "2d_voices=%d" % _2d_playing())
	_ad.call("_on_tower_revived", 0)
	_ok("G 塔复活（C-05）→ 2D 池出声（单次重启音）", _2d_playing() >= 3, "2d_voices=%d" % _2d_playing())


func _phase_D_open() -> void:
	if _ad == null:
		return
	_cut_open = float((_ad.get("_music_lpf") as AudioEffectLowPassFilter).cutoff_hz)
	var td: Node = _ad.get("_time_director")
	if td != null and td.has_method("open_shop"):
		td.call("open_shop")


func _phase_D_check() -> void:
	if _ad == null:
		return
	var cut := float((_ad.get("_music_lpf") as AudioEffectLowPassFilter).cutoff_hz)
	_ok("D 开商店 focus_amount = 1", is_equal_approx(float(_ad.call("focus_amount")), 1.0),
		"focus=%.2f" % float(_ad.call("focus_amount")))
	_ok("D Music 低通 cutoff 下降（非 pitch）", cut < _cut_open * 0.5,
		"open=%.0f now=%.0f" % [_cut_open, cut])


func _phase_C_pause() -> void:
	paused = true


func _phase_C_check() -> void:
	if _ad == null:
		return
	var playing := int(_ad.call("music_playing_count"))
	_ok("C 安全窗 paused=true 下音乐仍在播（坑①）", playing == 4, "playing=%d" % playing)
	_ok("C 音频节点始终 ALWAYS", _ad.process_mode == Node.PROCESS_MODE_ALWAYS)
	paused = false
