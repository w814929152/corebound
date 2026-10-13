extends Node
##
## AudioDirector —— 《守核 Corebound》音频表现层（autoload · autoload 名 `AudioDirector`）
##
## 依据：`docs/phase6/audio-spec-a.md §4`（实现契约）+ `§5`（两坑）+ `§7`（回归断言）
##       `docs/phase6/audio-audit.md §3/§4` · `docs/phase6/audio-assets-build.md §3`（stem 归一）
##       分层契约：`docs/architecture/control-manifest.md §5`
##
## =============================================================================
## 🔴 只读表现层（control-manifest §5）
## =============================================================================
##   · 全文件**不发任何信号**（无 signal 声明、无 emit 调用）→ 永不发 gameplay 信号。
##   · 不写任何玩法状态：唯一对外读数是既有 `snapshot()` / 既有信号参数（只读）。
##   · 订阅点全部是**既有信号**（TimeDirector / WaveDirector / ShopController），零新增信号。
##
## =============================================================================
## 🔴 两坑（audio-spec-a §5）
## =============================================================================
##   ① 安全窗 `get_tree().paused = true` → 所有音频节点 `process_mode = ALWAYS`，
##      音乐继续（情绪不断）；需要静默只用 `stream_paused`，**不靠** paused。
##   ② 战术减速 `Engine.time_scale = 0.35`（引擎不改音频速度）→ 商店开门用**谐振低通**
##      表达「聚焦」（`set_focus_filter`），**禁** pitch-bend。
##
## =============================================================================
## 🔴 R-d / T-E1③（塔复活禁择时提示）
## =============================================================================
##   `_on_tower_revived` **只播单次 `snd_combat_tower_up`**；不播任何节拍/进度语义音。
##
## =============================================================================
## ⚠️ headless 兼容（本工程 CI/回归的现实：无 editor 导入）
## =============================================================================
##   `--headless --script` **不触发资源导入**（实测 `ResourceLoader.exists(.wav) == false`），
##   而 `preload()` 一个未导入的音频文件是**解析期硬错误**（EXIT=1）。
##   → 故本文件**不在解析期 preload 音频**，改为「首次使用时按需 `load()` + 字典缓存」：
##     每个资产**只在首次播放时加载一次**，之后走缓存（等价于 preload 的"零重复加载"意图），
##     且在无导入环境下**优雅降级为静音**（headless = dummy 驱动，本就不出声），不报错、不中断 CI。
##     🔴 与 `audio-spec-a §4.6`「全部 preload」的偏差已在交付报告显式登记。
##

# ---------------------------------------------------------------------------
#  常量（audio-spec-a §4.1）
# ---------------------------------------------------------------------------
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"
const BUS_VOICE := "Voice"

const POOL_SIZE := 24          # 非定位 AudioStreamPlayer
const POOL_SIZE_2D := 4        # 定位 AudioStreamPlayer2D
const POLL_HZ := 10            # 派生轮询频率
const KILL_VOICE_CAP := 8      # 击杀个体音并发上限
const SWARM_THRESHOLD := 10.0  # kill/s：超过转洪流层

const POLL_INTERVAL := 1.0 / float(POLL_HZ)
const MUSIC_CROSSFADE := 1.5   # stem 增删 crossfade（§2.3）
const FOCUS_TIME := 1.5        # 聚焦低通缓动（§5）
const FOCUS_CUTOFF_OPEN := 20500.0
const FOCUS_CUTOFF_CLOSED := 700.0
const FOCUS_RESONANCE := 1.5
const SILENT_DB := -80.0
const SWARM_QUIET_HOLD := 0.4  # kill/s 跌破阈值后延迟退出洪流（防抖）
const SWARM_PAN_2D := 600.0

const AUDIO_DIR := "res://assets/audio/"

## §4.6：id（StringName）= 文件名同构 → 相对 `assets/audio/` 的路径
const SFX_FILES := {
	# ---- 战斗（C-02 / C-03 / C-04 / C-05）----
	&"snd_combat_kill_01": "sfx/snd_combat_kill_01.wav",
	&"snd_combat_kill_02": "sfx/snd_combat_kill_02.wav",
	&"snd_combat_kill_03": "sfx/snd_combat_kill_03.wav",
	&"snd_combat_kill_04": "sfx/snd_combat_kill_04.wav",
	&"snd_combat_kill_swarm": "sfx/snd_combat_kill_swarm.wav",
	&"snd_combat_leak": "sfx/snd_combat_leak.wav",
	&"snd_combat_tower_down": "sfx/snd_combat_tower_down.wav",
	&"snd_combat_tower_up": "sfx/snd_combat_tower_up.wav",
	# ---- 波次 / 乐句（L-02 / L-05 / L-06）----
	&"snd_wave_start_early": "sfx/snd_wave_start_early.wav",
	&"snd_wave_start_mid": "sfx/snd_wave_start_mid.wav",
	&"snd_wave_start_late": "sfx/snd_wave_start_late.wav",
	&"snd_sting_victory": "sfx/snd_sting_victory.wav",
	&"snd_sting_defeat": "sfx/snd_sting_defeat.wav",
	# ---- UI（S-02 / S-03）----
	&"snd_ui_reroll_01": "ui/snd_ui_reroll_01.wav",
	&"snd_ui_reroll_02": "ui/snd_ui_reroll_02.wav",
	&"snd_ui_reroll_03": "ui/snd_ui_reroll_03.wav",
	&"snd_ui_buy_01": "ui/snd_ui_buy_01.wav",
	&"snd_ui_buy_02": "ui/snd_ui_buy_02.wav",
	&"snd_ui_buy_03": "ui/snd_ui_buy_03.wav",
	&"snd_ui_buy_04": "ui/snd_ui_buy_04.wav",
	&"snd_ui_buy_05": "ui/snd_ui_buy_05.wav",
}

## 音乐 stem 顺序（§2.1 MVP 4 条 · 均应常驻播放、逐 stem 淡入）
const STEM_FILES := [
	"music/music_sub_drone.ogg",   # 0 低频地基
	"music/music_pulse.ogg",       # 1 节拍/心跳
	"music/music_harmony_pad.ogg", # 2 和声/主题点亮
	"music/music_rhythm.ogg",      # 3 工业节奏件
]

## 三阶段编配（§2.2）：每 stem 目标 volume_db
const STAGE_VOL := [
	[0.0, -8.0, -6.0, SILENT_DB],  # A 苟活 W1-5：drone+pulse+pad
	[0.0, 0.0, 0.0, -10.0],        # B 成型 W6-12：+ rhythm
	[2.0, 0.0, 0.0, 0.0],          # C 雪崩 W13+：全开
]

## 波次 → stem 变体分段（§3.2④）
const WAVE_START_MID := 6
const WAVE_START_LATE := 13

# ---------------------------------------------------------------------------
#  状态
# ---------------------------------------------------------------------------
var _wave_director: Node = null
var _time_director: Node = null
var _shop_controller: Node = null

var _pool: Array = []          # AudioStreamPlayer × 24
var _pool_rank: Array = []     # 每实例当前优先级（数值小 = 更该保住）
var _pool_started: Array = []  # 每实例本次起播时刻（_clock 秒）
var _pool_is_kill: Array = []  # 每实例是否击杀个体音（供 ≤8 并发门禁）
var _pool_2d: Array = []       # AudioStreamPlayer2D × 4

var _stems: Array = []         # AudioStreamPlayer × 4（音乐）
var _stem_tweens: Array = []
var _music_lpf: AudioEffectLowPassFilter = null
var _sfx_lpf: AudioEffectLowPassFilter = null
var _swarm_player: AudioStreamPlayer = null
var _swarm_active := false
var _swarm_quiet := 0.0

var _stream_cache := {}        # id/路径 → AudioStream（首次加载后缓存）

var _clock := 0.0
var _accum := 0.0

var _stage := -1
var _theme := 0
var _audio_scale := 0.5
var _focus_amount := 0.0
var _elite_active := false
var _last_wave := 0

var _kill_times: Array = []    # 最近 1.0s 内的击杀时刻（滑动窗口）
var _kill_seq := 0
var _buy_seq := 0
var _reroll_seq := 0

var _shop_base: Dictionary = {}  # shop_changed diff 基线
var _have_shop_base := false
var _duck_tweens := {}
var _focus_tween: Tween = null


# ---------------------------------------------------------------------------
#  生命周期
# ---------------------------------------------------------------------------
func _ready() -> void:
	# 🔴 坑①：安全窗 paused=true 下音频必须继续
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_grab_bus_effects()
	_build_pools()
	_build_music()
	_build_swarm()
	set_process(true)
	# 🔴 首波 `wave_started` 早于 10Hz 发现会漏音 → 立刻 + 延迟各扫一次（deferred 在主场景装配后执行）
	_auto_discover()
	call_deferred("_auto_discover")


func _process(delta: float) -> void:
	_clock += delta

	# ---- 容器发现（打不开 battle_shop.gd 接线 → 只读扫描场景树兜底）----
	if not _all_bound():
		_auto_discover()

	# ---- ~10Hz 派生轮询（clamp 单帧，防失焦跳变刷爆）----
	if _wave_director != null and is_instance_valid(_wave_director):
		_accum += minf(delta, 0.25)
		if _accum >= POLL_INTERVAL:
			_accum = 0.0
			_poll()

	_trim_kill_times()
	_update_swarm(delta)
	_check_stems_playing()


# ---------------------------------------------------------------------------
#  接线（§4.2 公开 API + 场景树兜底发现）
# ---------------------------------------------------------------------------
## 显式接线（audio-spec-a §4.2）。三个容器任一可为 null（缺省走场景树兜底发现）。
func bind(wave_director: Node, time_director: Node, shop_controller: Node) -> void:
	_bind_wave(wave_director)
	_bind_time(time_director)
	_bind_shop(shop_controller)


func _all_bound() -> bool:
	return (_wave_director != null and is_instance_valid(_wave_director)
		and _time_director != null and is_instance_valid(_time_director)
		and _shop_controller != null and is_instance_valid(_shop_controller))


func _auto_discover() -> void:
	var root := get_tree().root
	if root != null:
		_walk(root)


func _walk(n: Node) -> void:
	if n != self and n is Node:
		if _wave_director == null and n.has_signal("monster_killed") and n.has_method("snapshot"):
			_bind_wave(n)
		if _time_director == null and n.has_signal("wave_started") and n.has_signal("drawer_mode_changed"):
			_bind_time(n)
		if _shop_controller == null and n.has_signal("shop_changed") and n.has_signal("run_changed"):
			_bind_shop(n)
	for c in n.get_children():
		_walk(c)


func _bind_wave(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	_wave_director = n
	_connect(n, "wave_result", _on_wave_result)
	_connect(n, "monster_spawned", _on_spawn)
	_connect(n, "monster_killed", _on_kill)
	_connect(n, "monster_leaked", _on_leak)
	_connect(n, "tower_destroyed", _on_tower_destroyed)
	_connect(n, "tower_revived", _on_tower_revived)
	_connect(n, "run_won", _on_win)
	_connect(n, "run_lost", _on_lose)


func _bind_time(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	_time_director = n
	_connect(n, "wave_started", _on_wave_started)
	_connect(n, "wave_ended", _on_wave_ended)
	_connect(n, "drawer_mode_changed", _on_drawer)
	_connect(n, "budget_drained", _on_budget_drained)
	_connect(n, "placement_confirmed", _on_placement_confirmed)
	_connect(n, "placement_cancelled", _on_placement_cancelled)
	_connect(n, "tower_select_requested", _on_tower_select)


func _bind_shop(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	_shop_controller = n
	_connect(n, "shop_changed", _on_shop_changed)
	_connect(n, "run_changed", _on_run_changed)


func _connect(n: Node, sig: String, handler: Callable) -> void:
	if not n.has_signal(sig):
		return
	if not n.is_connected(sig, handler):
		n.connect(sig, handler)


# ---------------------------------------------------------------------------
#  公开 API —— 播放（§4.2）
# ---------------------------------------------------------------------------
## opts：priority:int(0..2 小=重要) · volume_db · pitch · pitch_jitter · pan · position · bus
func play_sfx(id: StringName, opts := {}) -> void:
	var stream: AudioStream = _get_stream(String(id))
	if stream == null:
		return
	var p_rank := int(opts.get("priority", 0))
	var want_pos: bool = opts.has("position") or absf(float(opts.get("pan", 0.0))) > 0.001
	if want_pos:
		var pos := Vector2.ZERO
		if opts.has("position"):
			pos = opts["position"]
		else:
			pos = Vector2(clampf(float(opts["pan"]), -1.0, 1.0) * SWARM_PAN_2D, 0.0)
		if _play_2d(stream, pos, opts):
			return
	# 非定位池
	var pl := _acquire_pool(p_rank, bool(opts.get("kill", false)))
	if pl == null:
		return
	_apply_and_play(pl, stream, opts)


func _apply_and_play(pl: AudioStreamPlayer, stream: AudioStream, opts: Dictionary) -> void:
	var pitch := float(opts.get("pitch", 1.0))
	var jitter := float(opts.get("pitch_jitter", 0.0))
	if jitter > 0.0:
		pitch *= _jitter_ratio(jitter)
	pl.stream = stream
	pl.bus = String(opts.get("bus", BUS_SFX))
	pl.volume_db = float(opts.get("volume_db", 0.0))
	pl.pitch_scale = clampf(pitch, 0.05, 4.0)
	pl.play()


## 定位播放（2D 池）。无空闲即失败（交由调用方回落非定位池）。
func _play_2d(stream: AudioStream, pos: Vector2, opts: Dictionary) -> bool:
	var pl: AudioStreamPlayer2D = null
	for cand in _pool_2d:
		if not cand.playing:
			pl = cand
			break
	if pl == null:
		return false
	pl.stream = stream
	pl.global_position = pos
	pl.bus = String(opts.get("bus", BUS_SFX))
	pl.volume_db = float(opts.get("volume_db", 0.0))
	var pitch := float(opts.get("pitch", 1.0))
	if float(opts.get("pitch_jitter", 0.0)) > 0.0:
		pitch *= _jitter_ratio(float(opts["pitch_jitter"]))
	pl.pitch_scale = clampf(pitch, 0.05, 4.0)
	pl.play()
	return true


func _acquire_pool(p_rank: int, is_kill: bool) -> AudioStreamPlayer:
	for i in range(_pool.size()):
		var pl: AudioStreamPlayer = _pool[i]
		if not pl.playing:
			_pool_rank[i] = p_rank
			_pool_started[i] = _clock
			_pool_is_kill[i] = is_kill
			return pl
	# 池满 → 抢占：优先级数值最大（最不重要）+ 已播最久者
	var victim := -1
	var worst := -1
	var earliest := 0.0
	for i in range(_pool.size()):
		var r := int(_pool_rank[i])
		if victim < 0 or r > worst or (r == worst and float(_pool_started[i]) < earliest):
			victim = i
			worst = r
			earliest = float(_pool_started[i])
	if victim >= 0 and worst > p_rank:
		var pl: AudioStreamPlayer = _pool[victim]
		pl.stop()
		_pool_rank[victim] = p_rank
		_pool_started[victim] = _clock
		_pool_is_kill[victim] = is_kill
		return pl
	return null


# ---------------------------------------------------------------------------
#  公开 API —— 音乐 / 混音 / 参数（§4.2）
# ---------------------------------------------------------------------------
func set_music_stage(stage: int) -> void:
	var s := clampi(stage, 0, 2)
	if s == _stage:
		return
	_stage = s
	for i in range(_stems.size()):
		_fade_stem(i, float(STAGE_VOL[s][i]))


## MVP 只有单一主题（4 stem 同曲）→ 记录档位即可；6.3 接音色层时在此切换附加层。
func set_music_theme(theme: int) -> void:
	_theme = theme


func play_stinger(id: StringName) -> void:
	match String(id):
		"victory":
			_duck_all(0.15)
			play_sfx(&"snd_sting_victory", {"priority": 0, "bus": BUS_SFX})
		"defeat":
			_duck_all(0.15)
			play_sfx(&"snd_sting_defeat", {"priority": 0, "bus": BUS_SFX})
		"elite":
			# 精英插段：常规音乐 duck −4 dB（§2.3）
			duck(BUS_MUSIC, -4.0, 0.3, 1.0)
		_:
			# 其余（takeoff / overload / 6.3 充能资产）尚未就绪 → 静默占位
			pass


## bus 音量包络 duck（attack 下压 → release 回弹到 0）
func duck(bus: String, db: float, attack: float, release: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	if _duck_tweens.has(bus):
		var old = _duck_tweens[bus]
		if old != null and old.is_valid():
			old.kill()
	var cb := func(v: float) -> void:
		AudioServer.set_bus_volume_db(idx, v)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(cb, AudioServer.get_bus_volume_db(idx), float(db), maxf(0.001, float(attack)))
	tw.tween_method(cb, float(db), 0.0, maxf(0.001, float(release)))
	_duck_tweens[bus] = tw


## 商店开门「聚焦」：Music + SFX 谐振低通（§5，代替 pitch-bend）
func set_focus_filter(amount: float) -> void:
	_focus_amount = clampf(amount, 0.0, 1.0)
	var cutoff := lerpf(FOCUS_CUTOFF_OPEN, FOCUS_CUTOFF_CLOSED, _focus_amount)
	var res := lerpf(0.0, FOCUS_RESONANCE, _focus_amount)
	if _music_lpf == null and _sfx_lpf == null:
		return
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	# 🔴 单 tween 并行驱动两条总线的 cutoff/resonance（分两个 tween 会互相 kill）
	var t := create_tween().set_ignore_time_scale(true)
	t.set_parallel(true)
	if _music_lpf != null:
		t.tween_property(_music_lpf, "cutoff_hz", cutoff, FOCUS_TIME)
		t.tween_property(_music_lpf, "resonance", res, FOCUS_TIME)
	if _sfx_lpf != null:
		t.tween_property(_sfx_lpf, "cutoff_hz", cutoff, FOCUS_TIME)
		t.tween_property(_sfx_lpf, "resonance", res, FOCUS_TIME)
	_focus_tween = t


func set_bus_volume_db(bus: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, float(db))


func set_master_mute(muted: bool) -> void:
	var idx := AudioServer.get_bus_index(BUS_MASTER)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, bool(muted))


## JuiceScale → AudioScale（0..1）：驱动击杀强度 / 动态
func set_audio_scale(s: float) -> void:
	_audio_scale = clampf(s, 0.0, 1.0)


# ---------------------------------------------------------------------------
#  高密度聚合（§4.2 / §3.2①）
# ---------------------------------------------------------------------------
func notify_kill(strength: float) -> void:
	_trim_kill_times()
	_kill_times.append(_clock)
	var rate := float(_kill_times.size())  # 窗口 = 1.0s → 直接是 kill/s
	if rate >= SWARM_THRESHOLD:
		_enter_swarm(rate)
	else:
		if _kill_voices() < KILL_VOICE_CAP:
			var v := _kill_seq % 4
			_kill_seq += 1
			var id := StringName("snd_combat_kill_0%d" % (v + 1))
			play_sfx(id, {
				"priority": 0, "bus": BUS_SFX, "kill": true,
				"pitch_jitter": 2.0,
				"volume_db": lerpf(-6.0, 2.0, clampf(strength, 0.0, 1.0)),
			})
		_update_swarm_volume(rate)


# ---------------------------------------------------------------------------
#  既有信号 handler（§4.3 · 全为既有信号，零新增）
# ---------------------------------------------------------------------------
func _on_wave_started(w: int) -> void:
	_last_wave = w
	var id := &"snd_wave_start_early"
	if w >= WAVE_START_LATE:
		id = &"snd_wave_start_late"
	elif w >= WAVE_START_MID:
		id = &"snd_wave_start_mid"
	play_sfx(id, {"priority": 0, "bus": BUS_SFX})
	_kill_times.clear()
	_exit_swarm(true)


func _on_wave_ended(_w: int) -> void:
	# 进安全窗：淡出洪流层（音乐继续 = 坑①）
	_exit_swarm(true)


func _on_drawer(mode: int) -> void:
	# 抽屉开（LIGHT/HEAVY）→ 聚焦低通；关 → 复原（§5）
	set_focus_filter(1.0 if mode != 0 else 0.0)


func _on_budget_drained() -> void:
	pass  # S-12 资产不在 MVP 范围


func _on_placement_confirmed(_slot: int) -> void:
	pass  # S-06 资产不在 MVP 范围


func _on_placement_cancelled() -> void:
	pass  # S-07 资产不在 MVP 范围


func _on_tower_select(_slot: int) -> void:
	pass  # S-11 资产不在 MVP 范围


func _on_wave_result(_w: int, _res: Dictionary) -> void:
	pass  # L-03 资产不在 MVP 范围


func _on_spawn(_m) -> void:
	pass  # C-01 出生聚合层 → 6.3


func _on_kill(_m) -> void:
	# 击杀个体音**只走非定位池**（保证 §7.3「击杀个体并发 ≤ 8」门禁可数）：
	# AudioStreamPlayer 无 `pan` 属性（实测），屏幕 x 声像需 2D 池，与池规模/并发上限冲突 → MVP 从简。
	notify_kill(_audio_scale)


func _on_leak(_m) -> void:
	# C-03 漏怪 / 核心受创：定位至核心（RADIAL 核心 = 原点）
	play_sfx(&"snd_combat_leak", {"priority": 0, "bus": BUS_SFX, "position": Vector2.ZERO})


func _on_tower_destroyed(slot: int) -> void:
	play_sfx(&"snd_combat_tower_down", {"priority": 0, "bus": BUS_SFX, "position": _slot_pos(slot)})


## 🔴 R-d / T-E1③：只播**单次**「重启」音，无任何节拍 / 进度 / 择时语义。
func _on_tower_revived(slot: int) -> void:
	play_sfx(&"snd_combat_tower_up", {"priority": 0, "bus": BUS_SFX, "position": _slot_pos(slot)})


func _on_win(_w: int) -> void:
	play_stinger(&"victory")


func _on_lose(_w: int) -> void:
	play_stinger(&"defeat")


## §3.2②：成交判定必须 **diff 快照**（不可用先于校验的意图信号）
func _on_shop_changed() -> void:
	var snap: Dictionary = _shop_snapshot()
	if snap.is_empty():
		return
	if not _have_shop_base:
		_shop_base = _shop_fingerprint(snap)
		_have_shop_base = true
		return
	var cur := _shop_fingerprint(snap)
	var prev := _shop_base
	_shop_base = cur
	var scrap_drop := float(prev.get("scrap", 0.0)) - float(cur.get("scrap", 0.0))
	var reroll_up := int(cur.get("rerolls", 0)) > int(prev.get("rerolls", 0))
	if reroll_up:
		var v := _reroll_seq % 3
		_reroll_seq += 1
		play_sfx(StringName("snd_ui_reroll_0%d" % (v + 1)), {"priority": 0, "bus": BUS_UI})
	elif scrap_drop > 0.0:
		var b := _buy_seq % 5
		_buy_seq += 1
		play_sfx(StringName("snd_ui_buy_0%d" % (b + 1)), {"priority": 0, "bus": BUS_UI})


func _on_run_changed() -> void:
	pass  # S-08/S-09/S-10 资产不在 MVP 范围（diff 派生预留）


# ---------------------------------------------------------------------------
#  ~10Hz 派生轮询（§4.4 · 只读 snapshot）
# ---------------------------------------------------------------------------
func _poll() -> void:
	var wd: Dictionary = _safe_snapshot(_wave_director)
	if wd.is_empty():
		return
	var w := int(wd.get("w", 0))
	# 阶段：A(W1-5)/B(W6-12)/C(W13+)
	var s := 0
	if w >= WAVE_START_LATE:
		s = 2
	elif w >= WAVE_START_MID:
		s = 1
	set_music_stage(s)
	# 精英波插段（W-01 预告 / 当前精英波 duck）
	var elite := bool(wd.get("is_elite_wave", false))
	if elite and not _elite_active:
		_elite_active = true
		play_stinger(&"elite")
	elif not elite and _elite_active:
		_elite_active = false


# ---------------------------------------------------------------------------
#  总线 / 池 / 音乐 构建
# ---------------------------------------------------------------------------
func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_UI, BUS_VOICE]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus(AudioServer.bus_count)
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)


func _grab_bus_effects() -> void:
	_music_lpf = _find_lpf(AudioServer.get_bus_index(BUS_MUSIC))
	_sfx_lpf = _find_lpf(AudioServer.get_bus_index(BUS_SFX))


func _find_lpf(bus_idx: int) -> AudioEffectLowPassFilter:
	if bus_idx < 0:
		return null
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var e := AudioServer.get_bus_effect(bus_idx, i)
		if e is AudioEffectLowPassFilter:
			return e
	return null


func _build_pools() -> void:
	for i in range(POOL_SIZE):
		var pl := AudioStreamPlayer.new()
		pl.name = "SfxPool%02d" % i
		pl.bus = BUS_SFX
		pl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(pl)
		_pool.append(pl)
		_pool_rank.append(0)
		_pool_started.append(0.0)
		_pool_is_kill.append(false)
	for i in range(POOL_SIZE_2D):
		var p2 := AudioStreamPlayer2D.new()
		p2.name = "Sfx2D%02d" % i
		p2.bus = BUS_SFX
		p2.max_distance = 2200.0
		p2.attenuation = 0.8
		p2.panning_strength = 1.0
		p2.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p2)
		_pool_2d.append(p2)


func _build_music() -> void:
	for i in range(STEM_FILES.size()):
		var pl := AudioStreamPlayer.new()
		pl.name = "MusicStem%d" % i
		pl.bus = BUS_MUSIC
		pl.volume_db = SILENT_DB
		pl.process_mode = Node.PROCESS_MODE_ALWAYS
		var st := _get_stream(STEM_FILES[i], true)
		if st != null:
			pl.stream = st
		add_child(pl)
		_stems.append(pl)
		_stem_tweens.append(null)
	# 同帧同起 → 4 stem 播放位对齐（L-3）；随后逐 stem 淡入
	for pl in _stems:
		if pl.stream != null:
			pl.play()
	# 首帧直接落 A 阶段音量（不淡入，避免"从静音爬升"）
	_stage = 0
	for i in range(_stems.size()):
		_stems[i].volume_db = float(STAGE_VOL[0][i])


func _build_swarm() -> void:
	_swarm_player = AudioStreamPlayer.new()
	_swarm_player.name = "KillSwarm"
	_swarm_player.bus = BUS_SFX
	_swarm_player.volume_db = SILENT_DB
	_swarm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_swarm_player.stream = _get_stream(String(&"snd_combat_kill_swarm"))
	_swarm_player.finished.connect(_on_swarm_finished)
	add_child(_swarm_player)


func _on_swarm_finished() -> void:
	if _swarm_active:
		_swarm_player.play()


# ---------------------------------------------------------------------------
#  内部工具
# ---------------------------------------------------------------------------
## 首次使用时加载 + 缓存（等价 preload 意图；无导入时返回 null 优雅降级）
func _get_stream(rel_or_id: String, is_music: bool = false) -> AudioStream:
	if _stream_cache.has(rel_or_id):
		return _stream_cache[rel_or_id]
	var rel := rel_or_id
	if not is_music:
		rel = String(SFX_FILES.get(StringName(rel_or_id), ""))
	var st: AudioStream = null
	if rel != "":
		var path := AUDIO_DIR + rel
		if ResourceLoader.exists(path):
			st = ResourceLoader.load(path)
		if st != null and (st is AudioStreamOggVorbis):
			st.loop = true
	_stream_cache[rel_or_id] = st
	return st


func _fade_stem(i: int, db: float) -> void:
	var tw = _stem_tweens[i]
	if tw != null and tw.is_valid():
		tw.kill()
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(_stems[i], "volume_db", db, MUSIC_CROSSFADE)
	_stem_tweens[i] = t


func _check_stems_playing() -> void:
	# 若某 stem 掉队（意外停止）→ 以最长播放位者为准重新对齐（L-3 稳健性）
	if _stems.is_empty():
		return
	var leader := -1
	var best := -1.0
	var any_stopped := false
	for i in range(_stems.size()):
		var pl: AudioStreamPlayer = _stems[i]
		if pl.stream == null:
			continue
		if not pl.playing:
			any_stopped = true
		var p: float = pl.get_playback_position()
		if p > best:
			best = p
			leader = i
	if not any_stopped or leader < 0:
		return
	for i in range(_stems.size()):
		var pl: AudioStreamPlayer = _stems[i]
		if pl.stream == null:
			continue
		if not pl.playing:
			pl.play()
			pl.seek(best)


func _enter_swarm(rate: float) -> void:
	_swarm_quiet = 0.0
	if _swarm_player == null or _swarm_player.stream == null:
		return
	if not _swarm_active:
		_swarm_active = true
		_swarm_player.volume_db = SILENT_DB
		_swarm_player.play()
	_update_swarm_volume(rate)


func _update_swarm_volume(rate: float) -> void:
	if _swarm_player == null:
		return
	var t := clampf((rate - SWARM_THRESHOLD) / 20.0, 0.0, 1.0)
	_swarm_player.volume_db = lerpf(-14.0, -3.0, t)


func _exit_swarm(force: bool) -> void:
	if not _swarm_active:
		return
	if force:
		_swarm_active = false
		_swarm_quiet = 0.0
		if _swarm_player != null:
			_swarm_player.stop()
			_swarm_player.volume_db = SILENT_DB


func _update_swarm(delta: float) -> void:
	if not _swarm_active:
		return
	var rate := float(_kill_times.size())
	if rate >= SWARM_THRESHOLD:
		_swarm_quiet = 0.0
		_update_swarm_volume(rate)
		return
	_swarm_quiet += delta
	if _swarm_quiet >= SWARM_QUIET_HOLD:
		_swarm_active = false
		_swarm_quiet = 0.0
		if _swarm_player != null:
			_swarm_player.stop()
			_swarm_player.volume_db = SILENT_DB


func _trim_kill_times() -> void:
	var cutoff := _clock - 1.0
	while not _kill_times.is_empty() and float(_kill_times[0]) < cutoff:
		_kill_times.pop_front()


func _kill_voices() -> int:
	var n := 0
	for i in range(_pool.size()):
		if bool(_pool_is_kill[i]) and (_pool[i] as AudioStreamPlayer).playing:
			n += 1
	return n


func _jitter_ratio(semitones: float) -> float:
	# ±semitones → 频率比（确定性来源：sin 哈希，不用 RNG 以免污染玩法随机流）
	var x: float = sin(_clock * 12.9898 + float(_kill_seq) * 78.233) * 43758.5453
	var r: float = x - floor(x)          # 0..1
	return pow(2.0, ((r * 2.0 - 1.0) * semitones) / 12.0)


func _slot_pos(slot: int) -> Vector2:
	# 只读取座标（`_slot_positions()` 是既有私有只读方法）；非 Vector2 / 越界 → 退回原点（核心）
	if _wave_director != null and is_instance_valid(_wave_director) and _wave_director.has_method("_slot_positions"):
		var arr = _wave_director._slot_positions()
		if arr is Array and slot >= 0 and slot < arr.size():
			var p = arr[slot]
			if p is Vector2:
				return p
	return Vector2.ZERO


func _safe_snapshot(n: Node) -> Dictionary:
	if n == null or not is_instance_valid(n) or not n.has_method("snapshot"):
		return {}
	var s = n.snapshot()
	if s is Dictionary:
		return s
	return {}


## 商店快照：`ShopController` 本身无 `snapshot()`（快照在它的 `runtime` 上）→ 只读取值。
func _shop_snapshot() -> Dictionary:
	if _shop_controller == null or not is_instance_valid(_shop_controller):
		return {}
	if _shop_controller.has_method("snapshot"):
		return _safe_snapshot(_shop_controller)
	var rt = _shop_controller.get("runtime")
	if rt != null and rt.has_method("snapshot"):
		var s = rt.snapshot()
		if s is Dictionary:
			return s
	return {}


## diff 指纹：只取需要判成交的最少只读键
func _shop_fingerprint(snap: Dictionary) -> Dictionary:
	return {
		"scrap": float(snap.get("scrap", 0.0)),
		"rerolls": int(snap.get("rerolls", 0)),
		"offer_count": int(snap.get("offer_count", 0)),
	}


func _duck_all(attack: float) -> void:
	duck(BUS_MUSIC, -8.0, attack, 0.6)
	duck(BUS_SFX, -6.0, attack, 0.6)


# ---------------------------------------------------------------------------
#  只读自检钩子（§7 回归断言用）
# ---------------------------------------------------------------------------
func active_voice_count() -> int:
	var n := 0
	for pl in _pool:
		if (pl as AudioStreamPlayer).playing:
			n += 1
	return n


func kill_voice_count() -> int:
	return _kill_voices()


func music_stage() -> int:
	return _stage


func focus_amount() -> float:
	return _focus_amount


func music_playing_count() -> int:
	var n := 0
	for pl in _stems:
		if (pl as AudioStreamPlayer).playing:
			n += 1
	return n


func bus_names() -> Array:
	var out: Array = []
	for i in range(AudioServer.bus_count):
		out.append(AudioServer.get_bus_name(i))
	return out
