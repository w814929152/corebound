extends SceneTree
##
## T-P6-07 音频框架回归断言（audio-spec-a §7 五条 · 独立入口，不改默认 run_tests.gd）
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_audio_asserts.gd
##
## 断言：
##   ① 只读性：audio_director.gd 不出现任何 emit_signal 调用 / signal 声明
##   ② T-E1③：_on_tower_revived 只播单次重启音，源码与资产名无择时 token
##   ③ 并发：池规模 = 24 + 4；active_voice_count ≤ 24；击杀个体 ≤ 8
##   ④ 两坑：所有音频节点 process_mode = ALWAYS；聚焦用低通（非 pitch）
##   ⑤ 零新信号：wave_director / time_director / shop_controller 信号数与基线一致
##
## ⚠️ G6：headless `--script` 无 global_script_class_cache → 一律 preload，无 class_name。
## ⚠️ autoload 的 `_ready` 在 `--script` 模式下要到首帧才执行 → 断言延后到第 3 帧。
##

const AUDIO_SRC := "res://scripts/audio/audio_director.gd"

## 当前玩法基线包含自由落子/取消信号，以及战局结束通知；音频层不增加玩法信号。
const SIG_BASELINE := {
	"res://scripts/gameplay/wave_director.gd": 8,
	"res://scripts/ui/time_director.gd": 17,
	"res://scripts/gameplay/shop_controller.gd": 3,
}

var _pass := 0
var _fail := 0
var _frame := 0


func _initialize() -> void:
	pass  # 等 autoload `_ready` 跑完


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_run()
	return true


func _run() -> void:
	print("=== T-P6-07 音频框架回归断言（audio-spec-a §7）===")

	# ---------- ① 只读性 ----------
	var src := _read(AUDIO_SRC)
	_ok("① audio_director.gd 可读", src != "")
	var emits := 0
	var decls := 0
	for line in src.split("\n"):
		var ls := String(line).strip_edges()
		if ls.begins_with("signal "):
			decls += 1
		if ls.find("emit_signal(") >= 0:
			emits += 1
	_ok("① 无 signal 声明", decls == 0, "decls=%d" % decls)
	_ok("① 无 emit_signal 调用", emits == 0, "emits=%d" % emits)

	# ---------- ② T-E1③ ----------
	var body := _func_body(src, "_on_tower_revived")
	_ok("② 找到 _on_tower_revived", body != "")
	var bad_tokens := ["tick", "countdown", "charge", "3..2..1", "3.2.1"]
	var hits: Array = []
	for t in bad_tokens:
		if body.to_lower().find(t.to_lower()) >= 0:
			hits.append(t)
	_ok("② _on_tower_revived 无择时 token", hits.is_empty(), "hits=%s" % str(hits))
	_ok("② _on_tower_revived 播单次重启音", body.find("snd_combat_tower_up") >= 0)
	var play_calls := body.count("play_sfx(")
	_ok("② 单次播放（play_sfx 调用数 = 1）", play_calls == 1, "calls=%d" % play_calls)

	# ---------- ③ / ④ 运行时（autoload = AudioDirector）----------
	var ad: Node = root.get_node_or_null("AudioDirector")
	_ok("autoload AudioDirector 存在", ad != null)
	if ad == null:
		print("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
		quit(1)
		return

	var pool: Array = ad.get("_pool")
	var pool2d: Array = ad.get("_pool_2d")
	_ok("③ 非定位池 = 24", pool != null and pool.size() == 24, "n=%d" % (pool.size() if pool != null else -1))
	_ok("③ 定位池 = 4", pool2d != null and pool2d.size() == 4, "n=%d" % (pool2d.size() if pool2d != null else -1))
	_ok("③ active_voice_count ≤ 24", int(ad.call("active_voice_count")) <= 24,
		"n=%d" % int(ad.call("active_voice_count")))
	_ok("③ kill_voice_count ≤ 8", int(ad.call("kill_voice_count")) <= 8,
		"n=%d" % int(ad.call("kill_voice_count")))

	# ④ 全部音频节点 ALWAYS
	var all_always := true
	var n_nodes := 0
	for c in ad.get_children():
		n_nodes += 1
		if (c as Node).process_mode != Node.PROCESS_MODE_ALWAYS:
			all_always = false
	_ok("④ AudioDirector 自身 ALWAYS", ad.process_mode == Node.PROCESS_MODE_ALWAYS)
	_ok("④ 全部音频子节点 ALWAYS", all_always, "children=%d" % n_nodes)

	# ④ 总线建立
	var buses: Array = ad.call("bus_names")
	var need := ["Master", "Music", "SFX", "UI", "Voice"]
	var missing: Array = []
	for b in need:
		if not buses.has(b):
			missing.append(b)
	_ok("④ 总线 Master/Music/SFX/UI/Voice 齐备", missing.is_empty(), "buses=%s" % str(buses))

	# ④ 聚焦 = 低通（非 pitch）
	var lpf_m = ad.get("_music_lpf")
	var lpf_s = ad.get("_sfx_lpf")
	_ok("④ Music 聚焦低通存在", lpf_m != null)
	_ok("④ SFX 聚焦低通存在", lpf_s != null)
	var pitch_untouched := true
	var stems: Array = ad.get("_stems")
	if stems != null:
		for s in stems:
			if not is_equal_approx(float((s as AudioStreamPlayer).pitch_scale), 1.0):
				pitch_untouched = false
	ad.call("set_focus_filter", 1.0)
	if stems != null:
		for s in stems:
			if not is_equal_approx(float((s as AudioStreamPlayer).pitch_scale), 1.0):
				pitch_untouched = false
	_ok("④ 聚焦不改 stem pitch", pitch_untouched)

	# ④ 音乐 stem = 4
	_ok("④ 音乐 stem = 4", stems != null and stems.size() == 4, "n=%d" % (stems.size() if stems != null else -1))

	# ④ 安全窗机制：paused=true 下音频节点仍 ALWAYS（音乐不被 paused 停）
	paused = true
	var still_always := ad.process_mode == Node.PROCESS_MODE_ALWAYS
	paused = false
	_ok("④ paused 下音频仍 ALWAYS（音乐不断）", still_always)
	ad.call("set_focus_filter", 0.0)

	# ---------- ⑤ 零新信号 ----------
	for path in SIG_BASELINE.keys():
		var s := _read(path)
		var cnt := 0
		for line in s.split("\n"):
			if String(line).strip_edges().begins_with("signal "):
				cnt += 1
		_ok("⑤ %s 信号数不变" % path.get_file(), cnt == int(SIG_BASELINE[path]),
			"got=%d want=%d" % [cnt, int(SIG_BASELINE[path])])

	print("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("[FAIL] ", name, ("  " + detail) if detail != "" else "")


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


func _func_body(src: String, fname: String) -> String:
	var key := "func " + fname
	var i := src.find(key)
	if i < 0:
		return ""
	var rest := src.substr(i)
	var lines := rest.split("\n")
	var out := ""
	for k in range(lines.size()):
		if k > 0 and String(lines[k]).begins_with("func "):
			break
		out += String(lines[k]) + "\n"
	return out
