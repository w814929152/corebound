extends Node
##
## 波次导演 `WaveDirector` —— GDD `wave-spawner` v0.2 §3.4 · 🔴 **时间轴权威**
##
## =============================================================================
## 🔴 本切片最硬的一条验收：**实时推进 == 金标本 `WaveSim.simulate_wave` 逐位等价**
## =============================================================================
## 做法（主理人拍板）：累积**被 `Engine.time_scale` 缩放后的 delta**，每凑满
## `DT = 0.1s`（金标本的步长，`WaveSim.DT`）跑一个与 `simulate_wave` 循环体
## **逐行相同**的子步 —— 于是「实时推进」就是「批处理」的逐 tick 展开。
##
## 逐行对齐点（改这个文件前必读，与 `wave_sim.gd` 文件头一一对应）：
##   1) `t_wave` 就是金标本的 `time`，走**同一条 `+= DT` 累加序列**（不写 `k*DT`，
##      那会与累进误差分岔）。`limit = D + t_reach + 1e-9`。
##   2) 刷新条件 `t_wave >= spawned * interval - 1e-9`（`spawned` = 已刷数量）。
##   3) 集火顺序：**按 `t_remain` 升序的稳定排序**。
##      ★ 在「单一基准怪」口径下这**恒等于**金标本的正序遍历（出生越早 → t_remain 越小，
##        严格单调；同 tick 出生者并列，稳定排序保持插入序）→ 逐位等价。
##      在「三原型分化」口径下它就是 GDD §2.7 W-A2 的「距核心最近优先」。
##   4) 伤害分配是**贪心 + 溢出结转**（W-A3）：`dmg` 依次填满队首，耗尽即停。
##   5) 判死 / 漏怪：先判死（hp<=0 移除，不递减），否则 `t_remain -= DT`，`<=0` 即漏怪。
##
## 🔴 等价性的**唯一前提**：波内 `dps` 恒定（金标本在波首算一次 `dps_only`）。
##    MVP 塔不死（`tower_aggro_enabled = false`）→ 成立 → 等价性**严格**成立。
##
## =============================================================================
## 🟡 待拍板 **S5-D1**（见 `docs/phase3/slice5-verify.md` §5）
## =============================================================================
## GDD §2.5 三原型分化（`D-W2=B`）+ §2.5.4 Elite（`D-W1=B`）**破坏上述等价性**：
## 金标本是「单一基准怪」，三原型把 HP / 在场时间重新分配后，贪心集火的结果会变。
## 实测（W10 同一构筑）：金标本 杀0 漏24，三原型+Elite 杀1 漏23。
## → 本文件**两条口径都完整落地**，由两个开关控制：
##     `prototype_split_enabled`（D-W2 / GDD §2.5.3）
##     `elite_waves_enabled`    （D-W1 / GDD §2.5.4）
##   🔴 **MVP 二者恒 false**（= 金标本等价口径）—— 与「MVP 塔不死 / 仇恨不生效」
##      同款处理：结构完整落地，开关置 true 即生效，无需改结构（GDD §7 交接点 ⑤）。
##
## =============================================================================
## 🔴 W-C3 时间轴红线（GDD §1.3 / §2.6.3）
## =============================================================================
##  · 只消费**缩放后的 delta**；🔴 禁止 `OS.get_ticks_msec()` / 帧计数 / `Timer`。
##  · 安全窗：本项目用 `get_tree().paused = true`（🔴 SR-R5：`Engine.time_scale` 永不为 0）
##    → 本文件显式把 paused 帧的 dt 置 0（GDD 原文写的是 `time_scale = 0`，二者
##      在「世界完全静止」这一设计意图上同义；口径差异已登记为 **S5-D2**）。
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → `interval` 两侧显式 float()。
##   G4 热路径分配：`monsters` 原地压缩，不重建 Array。
##   G6 无 `class_name`，一律 preload。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _Monster := preload("res://scripts/gameplay/monster.gd")
## 🔒 V-8：复用批处理镜像的**诊断量容器工厂** —— 复活诊断字典与 `wave_sim_aggro` 共用
##   同一份 schema（键名/初值逐位相同）→ 实时↔批处理逐位比对才能直接对键取值，
##   也杜绝"两边各写一份 schema、改了一边忘了另一边"的漂移。🔴 只调它的 static 工厂，
##   不调用任何战斗结算函数（实时版从不走批处理路径）。
const _WaveSimAggro := preload("res://scripts/engine/wave_sim_aggro.gd")


enum State {
	IDLE = 0,          # 首波前 / 波间（未开波）
	SPAWNING = 1,      # 出货中（与 FIGHTING 并行：一边出怪一边打）
	FIGHTING = 2,      # 出货完毕，清剿残留
	SAFE_WINDOW = 3,   # 安全窗（本文件不再推进）
}

enum MState {
	MARCHING = 0,
	AGGRO_TOWER = 1,
	LEAKED = 2,
}


signal wave_result(w: int, result: Dictionary)   # 实时结算（本波结束瞬间发）
signal monster_spawned(m)                        # I-3 的运行时侧（渲染层订阅）
signal monster_killed(m)
signal monster_leaked(m)                         # → Core.hp -= 50
## 🔒 T1（Q-T4 = ① 已定稿）：塔被仇恨打死 → 进入 Disabled 中间态（断输出不断链）。
##   携带塔位 slot。渲染层订阅做「塔体损伤演出」（T-C2 余光编码，不做数字条）。
signal tower_destroyed(slot: int)
## 🔒 V-8 肉盾循环 M-1：塔**自动爬起**（系统发起）→ 供渲染层做「塔体重启动效」。
##   🔴 这是**单向通知**（导演 → 画面），🈚 任何反向输入路径：没有"手动触发/取消/加速"
##      的接口，渲染层只能订阅。🔴 T-E1 边界二的源码级保证（由单测 AC-T1-24 守）。
##   🔴 不携带任何择时读数（只有 slot）→ 渲染层无法据此画倒计时/进度条（T-E1③）。
signal tower_revived(slot: int)
signal run_lost(w: int)                          # E-W3：核心 HP ≤ 0 立即失败
## 🟢 切片8续3（可玩 MVP）：通关胜利 —— 打完最后一波（W_MAX_WAVE）且核心未归零。
##   与 `run_lost` 对称：`run_lost` = 核心归零失败，`run_won` = 全波次清空胜利。
signal run_won(w: int)


# ---------------------------------------------------------------------------
#  开关（🔴 MVP 默认全部 false = 金标本等价口径）
# ---------------------------------------------------------------------------
## 🔒 T1：Q-T3 机会型仇恨（AGGRO_R = 9.0）。MVP 恒 false → 怪物恒 MARCHING。
var tower_aggro_enabled: bool = false
## 🔒 T1 反制窗口 M-1：战斗内即时被动复活（**产品开关**，与 proto/elite/aggro 同族）。
##   MVP 默认 false → `_revive_mode()` 读 cfg（默认 0）→ off 路径逐位不变（金标本零扰动）。
##   🟢 与 `repair_on_disable` 解耦：那个枚举的 0/1/2 是 V-7 诊断臂、9/11 是 V-8 扫描档；
##      产品口径**不占用**它（保持扫描路径纯净），改由本成员表达。
##   🟢 打开时 `_revive_mode()` 视同档 9（战斗内即时复活 · N=0.5s / K=1）——
##      🔴 复位(:231) / 死亡快照(:525) / tick(:580) 三处**同读 `_revive_mode()`** → 自动一致。
##   一行回滚：删掉 `boot.gd` 里 `combat_revive_enabled = true` 即退回默认。
var combat_revive_enabled: bool = false
## 🔒 T1 V-1 扫参：ATTRITION 覆盖值。默认 -1 = 读定稿常量（金标本零改动）；
##   >= 0 时覆盖 `_damage_tower` 的对塔 DPS 复合比（供扫参脚本与实时↔批处理一致性
##   在扫参值下守护）。扫参定稿后回写 `MonsterData.ATTRITION`，此成员退回默认。
var attrition_override: float = -1.0
## 🔒 T1 V-1 定稿起手保护波数（默认 = MonsterData.WARMUP = 2）：W1..warmup 仇恨不激活。
##   测试机制能力本身（仇恨能否打死塔）时可设 0 绕过（AC-T1-5/6/8/9 用 W1 测能力）。
var warmup_waves: int = _MonsterData.WARMUP
## 🟡 S5-D1：GDD §2.5.3 三原型分化。MVP 恒 false（= 单一基准怪 = 金标本口径）。
var prototype_split_enabled: bool = false
## 🟡 S5-D1：GDD §2.5.4 词缀版 Elite 波。MVP 恒 false。
var elite_waves_enabled: bool = false

# ---- 运行时注入 ----
var runtime = null          # ShopRuntime（提供 player / cfg / geo）
var player = null
var cfg: Dictionary = {}
var geo = null
var director: Node = null   # TimeDirector（时钟权威；本文件只调 wave_start/wave_end）

# ---- 波次状态（GDD §3.4）----
var w: int = 0
var state: int = State.IDLE
var t_wave: float = 0.0     # ★ 波次时钟（= 金标本的 `time`）
var acc: float = 0.0        # 缩放 delta 累加器（凑满 DT 跑一个子步）
var spawned: int = 0
var n: int = 0
var interval: float = 0.0
var dps: float = 0.0
var hp_unit: float = 0.0
var spk: float = 0.0        # scrap_per_kill = 2 + 0.5w
var t_reach: float = 10.0
var v0_: float = 10.10
var limit: float = 0.0      # D + t_reach + 1e-9

var monsters: Array = []
var kills: int = 0
var leaked_count: int = 0
var scrap_earned: float = 0.0
var core_hp: float = 1000.0
var run_failed: bool = false
## 🟢 切片8续3：通关标志（打完 W_MAX_WAVE 且核心未归零）。与 run_failed 互斥。
##   🔴 变量名用 `victory`（不能与 signal `run_won` 同名 → Godot 解析冲突）。
var victory: bool = false

# ---- 本波出生表（静态预计算，波首算一次）----
var _proto_seq: Array = []
var _elite_flags: Array = []
var _hp_mults: Array = []
var _spd_mults: Array = []

var last_result: Dictionary = {}
var last_result_w: int = -1

## 🔒 V-8 肉盾循环 M-1 诊断量（本波）。🔴 纯计数，不参与战斗结算。
##   schema 与批处理镜像 `wave_sim_aggro._new_v8_diag()` 逐位相同（同一工厂），
##   → 单测可逐键比对实时/批处理。🔴 默认 `repair_on_disable=0` → 全零、零扰动。
var revive_diag: Dictionary = {}

# 🔴 工程夹子：单帧最多跑多少个子步（窗口失焦回来时 delta 会是一次巨大跳变）。
#    只影响"追赶速度"，不影响任何数值口径（子步总数由 `t_wave` 与 `limit` 决定）。
const MAX_SUBSTEPS_PER_FRAME := 64

## 🟢 切片8续3（可玩 MVP）：一局总波数（W1..W20）。与金标本 `run_loop` 的
##    `max_wave = 20` 默认值对齐。打完 W20 且核心未归零 → 通关（`run_won`）。
const MAX_WAVE := 20


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


# ---------------------------------------------------------------------------
#  注入
# ---------------------------------------------------------------------------
func setup(p_player, p_cfg: Dictionary, p_geo = null) -> void:
	player = p_player
	cfg = p_cfg
	geo = p_geo
	# 🔴 切片8续3：核心 HP 单一数据源 —— 若注入了 player，就以其为权威初值（跨波延续）；
	#   否则退回 cfg.core_hp（headless 单测里 setup 早于 player 建好的情形）。
	if player != null and "core_hp" in player:
		core_hp = float(player.core_hp)
	else:
		core_hp = float(cfg.get("core_hp", 1000.0))
	run_failed = false
	victory = false
	state = State.IDLE
	last_result_w = -1


func bind_runtime(rt) -> void:
	runtime = rt
	if rt == null:
		return
	setup(rt.player, rt.cfg, rt.geo)


func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	if not d.is_connected("wave_started", _on_wave_started):
		d.wave_started.connect(_on_wave_started)


## 开局：发第 w 波的 `wave_started`（真实游戏由玩家点「开始 Wave」触发）
func start_run(p_w: int = 1) -> void:
	if director == null:
		return
	director.wave_start(p_w)


func _on_wave_started(p_w: int) -> void:
	start_wave(p_w)


# ---------------------------------------------------------------------------
#  开波（GDD §4.1）
# ---------------------------------------------------------------------------
func start_wave(p_w: int) -> void:
	if player == null or cfg.is_empty():
		return
	w = p_w
	# ---- 🔒 V-8 波首复活档（`mechanics-bulwark-cycle` F-4 + mode 11）----
	#   🔴 必须落在 `dps_only` **之前**（与批处理镜像 `simulate_wave_aggro` 同序）：
	#      mode 11（波首对照臂）清掉的 disabled 要被本波 dps 读到，否则两边分岔。
	revive_diag = _WaveSimAggro._new_v8_diag()
	if _revive_mode() >= 9:
		for t in player.towers:
			t.revive_t_disabled = 0.0     # F-4：本波 disabled 累计秒数清零
			t.revive_used_w = 0           # F-4：K 是「每波」配额，不是每局
		# 🔴 revived_ever / death_* 不清（跨波语义：revived_ever 是本局波浪标记）
		if _revive_mode() == 11 and w > warmup_waves:
			_wave_start_revive()
	# 🔴 HP_unit / N / scrap_per_kill / D / t_reach 全部取**金标本** `monster_stats`
	#    （一字不改地复用，杜绝二次定义）
	var ms := _WaveSim.monster_stats(w, cfg)
	hp_unit = float(ms["hp"])
	n = int(ms["n"])
	spk = float(ms["scrap_per_kill"])
	t_reach = float(ms["t_reach"])
	var D := float(ms["D"])
	# 🔴 R1：本波打的是**上波买出来的构筑** → 波首算一次 DPS，波内恒定（与金标本同）
	dps = _DE.dps_only(player, cfg, geo)
	var spawn_span := D * _Cfg.spawn_window(w)
	interval = spawn_span / float(maxi(1, n))
	limit = D + t_reach + 1e-9
	# 🔴 v₀ 派生：PATH → L/t_reach = 10.10（逐位等价基准）；RADIAL → R_s/t_reach = 5.50。
	#   统一走 SpaceModel.v0（t_reach 恒 10.0，R-CS3）→ 两模各自正确，PATH 逐位不变。
	v0_ = _SpaceModel.v0(t_reach)

	t_wave = 0.0
	acc = 0.0
	spawned = 0
	kills = 0
	leaked_count = 0
	scrap_earned = 0.0
	monsters = []
	last_result_w = -1
	_build_spawn_table()
	# 🔒 T1（Q-T2 = ①）：仇恨开启时，波首把未 Disabled 的塔重置为满血。
	#   MVP 无修复机制 → 每波满血是最简口径（Disabled 塔保持 Disabled，
	#   留给后续批次的波次间「修复/拆除/放着不管」三选一）。
	#   🔴 仅 tower_aggro_enabled 时触碰 player.towers → 金标本等价口径零扰动。
	if tower_aggro_enabled:
		_init_tower_hp()
	state = State.SPAWNING


## 🔒 T1：把未 Disabled 的塔按 `HP0 × h^0.6` 重置满血（Q-T2 = ①）。
func _init_tower_hp() -> void:
	if player == null:
		return
	var exp := float(cfg.get("tower_stack_exp", 0.6))
	for t in player.towers:
		if not bool(t.disabled):
			t.hp_max = _MonsterData.tower_hp(int(t.h), exp)
			t.hp = t.hp_max


## 本波出生表（纯确定性，无 RNG）
func _build_spawn_table() -> void:
	_proto_seq = []
	_elite_flags = []
	_hp_mults = []
	_spd_mults = []
	if not prototype_split_enabled:
		# 🔴 金标本口径：单一基准怪（m_hp = 1.00、m_spd = 1.00）
		for i in range(n):
			_proto_seq.append("Swarm")
			_elite_flags.append(false)
			_hp_mults.append(1.0)
			_spd_mults.append(1.0)
		return
	_proto_seq = _MonsterData.spawn_sequence(n)
	var n_e := _MonsterData.elite_count(w, n) if elite_waves_enabled else 0
	var c := _MonsterData.elite_conserve(n, n_e)
	var eidx := _MonsterData.elite_indices(n, n_e)
	for i in range(n):
		var p := String(_proto_seq[i])
		var e := eidx.has(i)
		_elite_flags.append(e)
		_hp_mults.append(_MonsterData.hp_mult(p, e, c))
		_spd_mults.append(_MonsterData.spd_mult(p))


func is_elite_wave() -> bool:
	return elite_waves_enabled and _MonsterData.is_elite_wave(w)


# ---------------------------------------------------------------------------
#  🔴 时钟推进 —— W-C3 红线
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var dt := float(delta)
	# 🔴 安全窗 = `get_tree().paused`（SR-R5：time_scale 永不为 0）→ dt 置 0 → 完全静止
	if get_tree() != null and get_tree().paused:
		dt = 0.0
	advance(dt)


## 消费**被 time_scale 缩放后的 dt**。返回本帧实际跑了多少个子步。
func advance(dt: float) -> int:
	if state != State.SPAWNING and state != State.FIGHTING:
		return 0
	if dt <= 0.0:
		return 0
	acc += float(dt)
	var steps := 0
	while acc >= _WaveSim.DT and steps < MAX_SUBSTEPS_PER_FRAME:
		acc -= _WaveSim.DT
		steps += 1
		_substep()
		t_wave += _WaveSim.DT          # ★ 与金标本 `time += dt` 同一条累加序列
		if _check_end():
			break
	return steps


## 🟡 自测 / 冒烟用：把当前波**按真实子步**跑到结束（不跳过任何结算，只是不等帧）。
##    🔴 与 D-8 的「调试跳过」有本质区别 —— 这里跑的是**同一套子步**，结果一致。
func run_to_end(max_steps: int = 100000) -> Dictionary:
	var guard := 0
	while (state == State.SPAWNING or state == State.FIGHTING) and guard < max_steps:
		guard += 1
		advance(_WaveSim.DT)
	return last_result


# ---------------------------------------------------------------------------
#  ★ 子步 —— 与 `WaveSim.simulate_wave` 循环体逐行相同
# ---------------------------------------------------------------------------
func _substep() -> void:
	# ---- ① 刷新：`while spawned < n and time >= spawned*interval - 1e-9` ----
	while spawned < n and t_wave >= float(spawned) * interval - 1e-9:
		_spawn_one(spawned)
		spawned += 1
		if spawned >= n and state == State.SPAWNING:
			state = State.FIGHTING

	# ---- ② 集火（W-A1 聚合池 / W-A2 距核心最近优先 / W-A3 溢出结转 / W-A4 不判射程）----
	_stable_sort_by_remain()
	var dmg := dps * _WaveSim.DT
	for m in monsters:
		if dmg <= 0.0:
			break
		if float(m.hp) <= dmg:
			dmg -= float(m.hp)
			m.hp = 0.0
			kills += 1
			scrap_earned += spk
			emit_signal("monster_killed", m)
		else:
			m.hp = float(m.hp) - dmg
			dmg = 0.0

	# ---- ③ 前进：判死 / 漏怪（原地压缩，保持相对顺序）----
	#   🔒 T1：AggroTower 态怪物**停下**（t_remain 冻结，不前进、不漏怪）。
	var wpos := 0
	var leak_dmg := float(cfg.get("leak_damage", 50.0))
	for m2 in monsters:
		if float(m2.hp) <= 0.0:
			continue
		if tower_aggro_enabled and m2.state == MState.AGGRO_TOWER:
			# 停下攻塔：冻结 t_remain，仍留在队列（不漏怪、不前进）
			monsters[wpos] = m2
			wpos += 1
			continue
		m2.t_remain = float(m2.t_remain) - _WaveSim.DT
		if float(m2.t_remain) <= 0.0:
			m2.state = MState.LEAKED
			leaked_count += 1
			core_hp = maxf(0.0, core_hp - leak_dmg)
			# 🔴 切片8续3：核心 HP 单一数据源 → 同步写回 player（供 HUD/商店读同一份）。
			if player != null and "core_hp" in player:
				player.core_hp = core_hp
			emit_signal("monster_leaked", m2)
			if core_hp <= 0.0 and not run_failed:
				run_failed = true
				emit_signal("run_lost", w)
			continue
		monsters[wpos] = m2
		wpos += 1
	monsters.resize(wpos)

	# ---- ④ 🔒 T1 仇恨行为（Q-T3 机会型仇恨 · 仅 tower_aggro_enabled 时生效）----
	#   设计铁律「仇恨只改路径不改 DPS 分配」：本阶段只改怪物态（Marching↔AggroTower）
	#   与塔损耗，**不动** ② 的 DPS 分配口径（全场池→t_remain 排序→填满→结转）。
	#   🔒 T1 V-1 定稿起手保护：W1..WARMUP(=2) 仇恨不激活（与批处理镜像 simulate_wave_aggro
	#     对称 → 实时↔批处理逐位一致）。无此保护起手塔 W1 必死、起飞率 0%。
	if tower_aggro_enabled and w > warmup_waves:
		_apply_aggro()

	# ---- ⑤ 🔒 V-8 战斗中复活（M-1）：Disabled 塔累计 N 秒 → 系统自动重启 ----
	#   🔴 与批处理镜像同序（都在④仇恨之后）→ 死亡当子步就开始累计 `revive_t_disabled`。
	#   🔴 `repair_on_disable < 9`（默认 0）→ 函数首行 return，off 路径逐位不变。
	_tick_revive()


## 🔒 T1（Q-T3 = ① 机会型仇恨）：每子步的仇恨判定（GDD §2.6 状态机）。
##   · Marching 怪：当前位置与某座 **未 Disabled** 塔的距离 ≤ AGGRO_R → 转 AggroTower，
##     目标 = 最近的塔（迟滞带内锁定）。
##   · AggroTower 怪：目标塔消失 / 已 Disabled / 距离 > AGGRO_EXIT（迟滞带退出）
##     → 回 Marching；否则对目标塔造成 `ATTRITION × HP0 × m_dps` 伤害。
##     塔 hp 归零 → 进入 Disabled 中间态（断输出不断链）→ 发 tower_destroyed。
##   🔴 迟滞带（AGGRO_R=9.0 进 / AGGRO_EXIT=10.8 出）防边界抖动（Q-T3 R4）。
func _apply_aggro() -> void:
	if player == null:
		return
	var v0x := v0_
	for m in monsters:
		if m == null or float(m.hp) <= 0.0:
			continue
		match m.state:
			MState.MARCHING:
				# 🔒 T1 ⑤ Sapper：出生即锁最近塔，无视 AGGRO_R 距离门槛（直奔最近的塔）。
				#   普通怪走 ≤ AGGRO_R 机会型门槛。
				var slot := -1
				if m.sapper:
					slot = _nearest_tower_any(m, v0x)
				else:
					slot = _nearest_exposed_tower(m, v0x)
				if slot >= 0:
					m.state = MState.AGGRO_TOWER
					m.target_slot = slot
			MState.AGGRO_TOWER:
				if not _aggro_target_valid(m, v0x):
					m.state = MState.MARCHING
					m.target_slot = -1
				else:
					_damage_tower(m)


## 找最近的**未 Disabled** 塔（距离 ≤ AGGRO_R）。返回塔位 slot，无则 -1。
func _nearest_exposed_tower(m, v0x: float) -> int:
	if player == null:
		return -1
	var mpos: Vector2 = m.pos(v0x)
	var best := -1
	var best_d := _MonsterData.AGGRO_R
	for t in player.towers:
		if bool(t.disabled):
			continue
		var spos: Vector2 = _tower_pos(t)
		var d := mpos.distance_squared_to(spos)
		if d <= _MonsterData.AGGRO_R * _MonsterData.AGGRO_R and d < best_d * best_d:
			best_d = d
			best = int(t.slot)
	return best


## 🔒 T1 ⑤ Sapper：找全局最近的**未 Disabled** 塔（**无视 AGGRO_R** 距离门槛）。
##   Sapper「直奔最近的塔」→ 不论远近都锁。与批处理镜像 _nearest_tower_any 逐位对齐。
func _nearest_tower_any(m, v0x: float) -> int:
	if player == null:
		return -1
	var mpos: Vector2 = m.pos(v0x)
	var best := -1
	var best_d := INF
	for t in player.towers:
		if bool(t.disabled):
			continue
		var spos: Vector2 = _tower_pos(t)
		var d := mpos.distance_squared_to(spos)
		if d < best_d:
			best_d = d
			best = int(t.slot)
	return best


## AggroTower 怪的目标塔是否仍合法（存在 + 未 Disabled + 在迟滞带内）。
func _aggro_target_valid(m, v0x: float) -> bool:
	if player == null or m.target_slot < 0:
		return false
	var t = _tower_by_slot(m.target_slot)
	if t == null or bool(t.disabled):
		return false
	# 🔒 T1 ⑤ Sapper：锁定后**不因距离退出**（直奔最近的塔，committed 攻击）。
	if m.sapper:
		return true
	var mpos: Vector2 = m.pos(v0x)
	var spos: Vector2 = _tower_pos(t)
	# 🔴 用 AGGRO_EXIT（10.8 = 9.0×1.2）作退出阈值（迟滞带，防边界抖动）
	return mpos.distance_squared_to(spos) <= _MonsterData.AGGRO_EXIT * _MonsterData.AGGRO_EXIT


## AggroTower 怪对目标塔造成伤害；塔归零 → Disabled 中间态。
func _damage_tower(m) -> void:
	var t = _tower_by_slot(m.target_slot)
	if t == null or bool(t.disabled):
		return
	# 对塔 DPS = ATTRITION × HP0 × m_dps(proto)（V-1 复合比口径；attrition_override>=0 时覆盖）
	# 🔒 T1 ⑤ Sapper：对塔伤害 ×3（m.sapper 标志）。
	var mdps: float = float(m.m_dps) * (_MonsterData.SAPPER_DMG_MULT if m.sapper else 1.0)
	var dmg := _MonsterData.resolve_attrition(attrition_override) * _MonsterData.HP0 * mdps * _WaveSim.DT
	t.hp = float(t.hp) - dmg
	if float(t.hp) <= 0.0:
		t.hp = 0.0
		# 🔒 V-8：死亡时刻资格快照（F-1）→ 🔴 必须在 `disabled = true` **之前**取
		#   （此时本塔尚属"未 Disabled"，carry 判定与批处理镜像同口径）。
		#   🔴 默认 repair_on_disable=0 → 不触发，零开销零扰动。
		if _revive_mode() >= 9:
			_death_snapshot(t)
		t.disabled = true          # 进入 Disabled 中间态（断输出不断链）
		# 🔴 塔死亡 → 全场 DPS 立即下降（disabled 乘数生效）。本波 dps 是波首算的
		#    常量，此处重算让**下一子步**的集火用新 DPS（批处理镜像同处理 → 逐位一致）。
		dps = _DE.dps_only(player, cfg, geo)
		emit_signal("tower_destroyed", int(t.slot))


## 按塔位取塔（player.towers 里查 slot）。
func _tower_by_slot(slot: int):
	for t in player.towers:
		if int(t.slot) == slot:
			return t
	return null


## 塔的世界坐标（XZ 平面）：优先用 geo.slots，退回 PathGeometry 无此塔位则用 slot 索引兜底。
func _tower_pos(t) -> Vector2:
	if geo != null and int(t.slot) >= 0 and int(t.slot) < geo.slots.size():
		return geo.slots[int(t.slot)]
	# 兜底：塔位坐标缺失时返回核心（不会进仇恨判定，安全）
	return _PathGeometry.CORE_POS


# ===========================================================================
#  🔒 V-8 肉盾循环 · 机制 M-1「战斗中被动复活」
#    GDD `mechanics-bulwark-cycle` §2.2（定稿 N=0.5s / K=1 / 暴露位&非 carry / 满血 / 原地）
#    🔴 与批处理镜像 `wave_sim_aggro.gd`（`_death_snapshot`/`_try_revive`/`_tick_revive`/
#       `_clear_disabled`/`_wave_start_revive`）**逐位对称** —— 同一开关语义、同一子步序、
#       同一浮点累加式。差异只有"宿主"（player.towers 成员 vs static 参数）。
#
#  🔴 T-E1（`mechanics-tower-life-death` §2.2.1）三要件 —— 本段实现逐条兑现：
#     ① **系统发起** —— 只由 `_substep` ⑤ 自动调用；本文件没有任何玩家输入回调或
#        输入查询（无 `_input*` 系回调、无 Input 单例查询），也🈚 确认弹窗 /
#        手动触发 / 取消 / 加速接口（`tower_revived` 是**单向**信号，只能订阅）。
#        → 单测 AC-T1-24 源码级守（逐行扫**非注释**代码里的输入类 token）。
#     ② **对象 = 死亡时刻快照「暴露位 & 非 carry」** —— `_death_snapshot` 在
#        `disabled = true` **之前**一次性求值；carry / 非暴露位一律**拒绝**（不爬起），
#        硬断言 `revive_misq` 恒 0。
#     ③ **时机 = 战斗内被动**（Disabled 后 N=0.5s 自动）且**零择时提示** ——
#        `snapshot()` 只导出**布尔**（`revive_ui` / 每塔 `revive_charged`），
#        🔴 不导出任何倒计时 / 进度 / 余量数字 → 单测 AC-T1-24 快照级守。
#
#  🔴 默认 `repair_on_disable = 0` → 下面全部函数**一次都不会被调到**，off 路径逐位不变。
# ===========================================================================

## 复活开关档位（`mvp_config :: repair_on_disable`）：0=OFF / 1=FREE / 2=PRICED
##   （既有三档语义一字不改）/ 9=战斗内即时 / 11=波首（对照臂）。🔴 默认恒 0。
## 🔒 T1 反制窗口：产品开关 `combat_revive_enabled` 优先 —— 打开时视同档 9。
##   🟢 解耦点：产品开 M-1 **不再**等于"把诊断枚举设成 9"；扫描/测试仍走 cfg（不受影响）。
func _revive_mode() -> int:
	if combat_revive_enabled:
		return 9
	return int(cfg.get("repair_on_disable", 0))


## 战斗内即时复活（mode 9）：Disabled 塔累计 `N` 秒后自动重启，每波每塔最多 `K` 次。
##   🔴 `K` 用尽 → 保持 Disabled 到波末（GDD §2 段③ → 波次间交给玩家三选一）。
func _tick_revive() -> void:
	var rm := _revive_mode()
	if player == null or rm < 9 or rm == 11:
		return
	if w <= warmup_waves:          # E-B7：WARMUP 期间仇恨未激活 → 不触发
		return
	var n_sec := float(cfg.get("revive_n_seconds", 0.5))
	var k_max := int(cfg.get("revive_k_per_wave", 1))
	var exp := float(cfg.get("tower_stack_exp", 0.6))
	for t in player.towers:
		if not bool(t.disabled):
			continue
		t.revive_t_disabled = float(t.revive_t_disabled) + _WaveSim.DT
		if int(t.revive_used_w) >= k_max:
			continue
		if float(t.revive_t_disabled) + 1e-9 < n_sec:
			continue
		_try_revive(t, exp)


## 波首复活（mode 11 = 对照臂 B3，`N → ∞` 极限档）：波首一次性清合格的 Disabled 塔。
##   🟢 落在 `dps_only` 重算**之前**调用（start_wave 内）→ 本波 dps 直接读到已恢复的塔。
func _wave_start_revive() -> void:
	if player == null:
		return
	var exp := float(cfg.get("tower_stack_exp", 0.6))
	var k_max := int(cfg.get("revive_k_per_wave", 1))
	for t in player.towers:
		if not bool(t.disabled):
			continue
		if int(t.revive_used_w) >= k_max:
			continue
		_try_revive(t, exp)


## 资格判定 + 成交（与批处理镜像 `_try_revive` 逐位对称）。
##   🔴 硬断言：已落地的重启必须仍满足死亡快照资格（`revive_misq` 恒 0，AC-8）。
##   🟡 与「闸门**正确拒绝**」是两件事：拒绝数走 `revive_refused`（诊断量，不是断言）。
func _try_revive(t, exp: float) -> bool:
	var k_max := int(cfg.get("revive_k_per_wave", 1))
	if bool(t.death_valid) and bool(t.death_exposed) and (not bool(t.death_carry)):
		t.hp_max = _MonsterData.tower_hp(int(t.h), exp)
		if _clear_disabled(int(t.slot)):
			t.revive_used_w = int(t.revive_used_w) + 1
			t.revived_ever = int(t.revived_ever) + 1
			revive_diag["revive_fired"] = float(revive_diag["revive_fired"]) + 1.0
			if (not bool(t.death_exposed)) or bool(t.death_carry) or (not bool(t.death_valid)):
				revive_diag["revive_misq"] = float(revive_diag["revive_misq"]) + 1.0
			# 🔴 塔恢复输出 → 全场 DPS 立即重算（与塔死亡时重算同一条纪律）
			dps = _DE.dps_only(player, cfg, geo)
			emit_signal("tower_revived", int(t.slot))
			return true
		return false
	# ---- 闸门口**正确拒绝**：不合格（carry 死 / 非暴露位死）→ 不重启 ----
	if not bool(t.death_valid):
		revive_diag["nosnap_death"] = float(revive_diag["nosnap_death"]) + 1.0
	revive_diag["revive_refused"] = float(revive_diag["revive_refused"]) + 1.0
	# 🔴 打满本波配额 → 同一座塔不会被每子步重复判定（否则拒绝计数会被刷爆）
	t.revive_used_w = k_max
	return false


## 清指定塔位的 Disabled 标记 + 回满 HP（与批处理镜像 `_clear_disabled` 逐位对称，
##   与 §2.3 `Repair` 同口径 —— 只恢复 HP 与输出，不动 h / attach / 历史最大塔数）。
func _clear_disabled(slot: int) -> bool:
	if player == null:
		return false
	for t in player.towers:
		if int(t.slot) == slot:
			if not bool(t.disabled):
				return false
			t.disabled = false
			t.hp = t.hp_max
			return true
	return false


## 死亡时刻资格快照（F-1）：`is_exposed` + 非 carry。🔴 必须在 `disabled = true` **之前**取。
##   🟢 零新字段：复用 `_PathGeometry.slot_exposure[_radial]` 的既有 `is_exposed`。
func _death_snapshot(t) -> void:
	var rm := _revive_mode()
	var slot := int(t.slot)
	var exposed := false
	if geo != null:
		var slots: Array = _slot_positions()
		var rows: Array
		if _SpaceModel.is_radial():
			rows = _PathGeometry.slot_exposure_radial(
				slots, _MonsterData.AGGRO_R, _SpaceModel.core_pos(),
				_PathGeometry.EXPO_SAFE_MAX)
		else:
			rows = _PathGeometry.slot_exposure(slots, _MonsterData.AGGRO_R)
		for r in rows:
			if int(r["slot"]) == slot:
				exposed = bool(r["is_exposed"])
				break
	var carry_h := -1
	for o in player.towers:
		if bool(o.disabled):
			continue
		if int(o.h) > carry_h:
			carry_h = int(o.h)
	var is_carry := (carry_h >= 0 and int(t.h) >= carry_h)
	t.death_exposed = exposed
	t.death_carry = is_carry
	t.death_valid = true
	# 死亡事件分类（🟡 闸门**正确拒绝**约半数死亡事件是设计意图，不是 bug）
	if is_carry:
		revive_diag["carry_death"] = float(revive_diag["carry_death"]) + 1.0
	elif not exposed:
		revive_diag["nonexp_death"] = float(revive_diag["nonexp_death"]) + 1.0
	if rm >= 9 and exposed and (not is_carry):
		revive_diag["revive_elig"] = float(revive_diag["revive_elig"]) + 1.0
	# 重启后又死（履职证明，不判负）
	if int(t.revived_ever) > 0:
		revive_diag["revive_redied"] = float(revive_diag["revive_redied"]) + 1.0


func _slot_positions() -> Array:
	var out: Array = []
	if geo != null and "slots" in geo:
		for p in geo.slots:
			out.append(p)
	return out


## 🔒 T1：本局已 Disabled 的塔数（供 last_result / snapshot 断言塔死亡后果）。
func _count_disabled_towers() -> int:
	if player == null:
		return 0
	var c := 0
	for t in player.towers:
		if bool(t.disabled):
			c += 1
	return c


func _spawn_one(idx: int) -> void:
	var proto := String(_proto_seq[idx])
	var elite := bool(_elite_flags[idx])
	var hp := hp_unit * float(_hp_mults[idx])
	var mspd := float(_spd_mults[idx])
	var tr := t_reach / mspd
	var m = _Monster.new()
	m.setup(idx, proto, elite, hp, mspd, tr)
	# 🆕 径向模式：注入黄金角出生角（确定性 · 零 RNG · 不碰商店发牌流，E-4/Q-R6）。
	#   PATH 模式下 set_theta 被忽略（恒 0），位置仍走折线 → 逐位等价。
	if _SpaceModel.mode == _SpaceModel.Mode.RADIAL:
		m.set_theta(_SpaceModel.spawn_theta(idx, w))
	# 🔒 T1 ⑤ Sapper：Elite 波（每5波）里沿波次均匀铺开的精英怪 = Sapper（锁塔 ×3 增伤）。
	#   与批处理镜像 WaveSimAggro._build_sapper_flags 逐位对齐（同一 elite_indices 算法）。
	#   🔴 金标本零改动：elite_waves_enabled=false → 不标记任何 sapper。
	#   🔴 不依赖 `elite`（_elite_flags 在 MVP prototype_split_enabled=false 下恒 false）——
	#      Sapper 由 elite_waves_enabled 独立驱动，与批处理镜像同口径（直接判 is_elite_wave）。
	if elite_waves_enabled and _MonsterData.is_elite_wave(w):
		var n_e := _MonsterData.elite_count(w, n)
		var eidx: Array = _MonsterData.elite_indices(n, n_e)
		for e in eidx:
			if int(e) == idx:
				m.sapper = true
				break
	monsters.append(m)
	emit_signal("monster_spawned", m)


## 稳定排序（插入排序）：按 `t_remain` 升序 = 距核心最近优先（W-A2）。
## 🔴 必须**稳定**：金标本的 `list.sort` 是稳定的，同 tick 出生的并列怪必须保持插入序。
func _stable_sort_by_remain() -> void:
	var i := 1
	while i < monsters.size():
		var key = monsters[i]
		var j := i - 1
		while j >= 0 and float(monsters[j].t_remain) > float(key.t_remain):
			monsters[j + 1] = monsters[j]
			j -= 1
		monsters[j + 1] = key
		i += 1


# ---------------------------------------------------------------------------
#  波次结束（GDD §2.9 / E-W1 / E-W2 / E-W3）
# ---------------------------------------------------------------------------
func _check_end() -> bool:
	# E-W3：核心 HP ≤ 0 → **立即失败**，中断本波所有结算（Q5）
	if run_failed:
		_end_wave()
		return true
	# E-W1：全部怪物已结算（击杀 / 漏怪）→ 提前进安全窗（不等满 D + t_reach）
	if spawned >= n and monsters.is_empty():
		_end_wave()
		return true
	# E-W2：到达 `D + t_reach` → 残留怪**直接移除**（不扣血、不给分，与 sim 真身同口径）
	#   🔴 顺序关键：W20 也走这条"正常收尾"路径 → 先把真实 kills/scrap 记进 last_result，
	#      再由 _end_wave 内的胜利判定（w >= MAX_WAVE 且未失败）判胜。等价性零扰动。
	if t_wave > limit:
		_end_wave()
		return true
	return false


func _end_wave() -> void:
	# E-W2：残留怪物直接移除（不判漏怪）
	for m in monsters:
		if m != null and float(m.hp) > 0.0:
			m.state = MState.MARCHING
	monsters = []
	state = State.SAFE_WINDOW
	last_result = {
		"w": w,
		"kills": kills,
		"leaked": leaked_count,
		"scrap_earned": scrap_earned,
		"core_damage": float(leaked_count) * float(cfg.get("leak_damage", 50.0)),
		"dps": dps,
		"n": n,
		"hp_each": hp_unit,
		"t_wave": t_wave,
		"core_hp": core_hp,
		"failed": run_failed,
		"won": victory,
	}
	last_result_w = w
	# 🟢 切片8续3（可玩 MVP）：通关胜利判定放在 last_result 记录**之后** ——
	#   此时 kills/scrap_earned 已是本波真实值（W20 全清 = 40 杀），等价性零扰动。
	#   条件：打完最后一波（w >= MAX_WAVE）且核心未归零（not run_failed）。
	# 🔴 T-P6-06 S3（BUG-1）：胜负**标志位**在此置定，但 `run_won` 的 **emit 延后**到
	#   `wave_end` 之后（见下）—— 让结算覆盖层读到「本波积分已入账」后的余额。
	var won_now := false
	if w >= MAX_WAVE and not run_failed and not victory:
		victory = true
		last_result["won"] = true
		won_now = true
	# 🔒 T1：记录本波结束时已 Disabled 的塔数（供 UI/单测断言塔死亡后果）。
	last_result["towers_disabled"] = _count_disabled_towers()
	# 🔒 V-8：本波复活诊断量（schema 与批处理镜像逐位相同 → 单测可逐键比对）。
	#   🔴 纯计数，默认全零，不参与战斗结算 → 金标本零扰动。
	last_result["v8_diag"] = revive_diag
	emit_signal("wave_result", w, last_result)
	# 时钟侧：进安全窗（TimeDirector 会写 paused 并广播 wave_ended）
	if director != null:
		director.wave_end(w)
	# 🔴 T-P6-06 S3（BUG-1 修正）：`run_won` **延后到 `wave_end` 之后**发。
	#   入账链 = `wave_end` → TimeDirector `wave_ended` → ShopController `_on_wave_ended`
	#   → `ShopRuntime.grant_wave_result`（本波 scrap_earned × (1+income_mult) 才入账）。
	#   原先 `run_won` 早于入账 → 结算覆盖层读 `runtime.scrap` 得**入账前余额**（胜利局显 0）。
	#   🔴 只调 emit 时序，**不动任何数值 / 结算公式**；失败路径（run_lost 在子步发）不受影响。
	if won_now:
		emit_signal("run_won", w)


# ---------------------------------------------------------------------------
#  只读快照（UI / 自测；🔴 UI 不持有游戏状态，control-manifest §5）
# ---------------------------------------------------------------------------
func snapshot() -> Dictionary:
	var live: Array = []
	for m in monsters:
		live.append({
			"proto": String(m.proto),
			"elite": bool(m.elite),
			"hp": float(m.hp),
			"hp_max": float(m.hp_max),
			"t_remain": float(m.t_remain),
			"s": m.arc_s(v0_),
			"pos": m.pos(v0_),
			"state": int(m.state),
			"target_slot": int(m.target_slot),
			"sapper": bool(m.sapper),   # 🔒 T1 ⑤ Sapper：供渲染层做 Elite 锁塔怪标识（MVP 恒 false）
		})
	# 🔒 T1：每座塔的运行时耐久 + Disabled 态（供渲染层做塔体损伤演出，T-C2 余光编码）
	# 🔒 V-8：每座塔额外导出一个**布尔** `revive_charged`（本波还能不能再爬一次）。
	#   🔴 只给布尔、不给数字 —— T-E1③「零择时读数」：`K` 余量以「塔底点亮/熄灭」
	#      表达，玩家看不到 "1/1"、也看不到任何倒计时（GDD §6.1）。
	var k_max := int(cfg.get("revive_k_per_wave", 1))
	var towers: Array = []
	if player != null:
		for t in player.towers:
			towers.append({
				"slot": int(t.slot),
				"hp": float(t.hp),
				"hp_max": float(t.hp_max),
				"disabled": bool(t.disabled),
				"revive_charged": bool(int(t.revive_used_w) < k_max),
			})
	return {
		"w": w,
		"state": state,
		"t_wave": t_wave,
		"spawned": spawned,
		"n": n,
		"alive": monsters.size(),
		"kills": kills,
		"leaked": leaked_count,
		"scrap_earned": scrap_earned,
		"core_hp": core_hp,
		"failed": run_failed,
		"won": victory,
		"dps": dps,
		"interval": interval,
		"limit": limit,
		"hp_unit": hp_unit,
		"v0": v0_,
		"t_reach": t_reach,
		"monsters": live,
		"towers": towers,
		"towers_disabled": _count_disabled_towers(),
		# 🔒 V-8 渲染层总闸（**布尔**）：只有「仇恨开 + 复活档位开」时渲染层才画
		#   塔底充能点亮 / 重启动效。🔴 默认恒 false → 默认画面与改前**逐像素相同**。
		"revive_ui": tower_aggro_enabled and _revive_mode() >= 9,
		"prototype_split_enabled": prototype_split_enabled,
		"elite_waves_enabled": elite_waves_enabled,
		"tower_aggro_enabled": tower_aggro_enabled,
		"is_elite_wave": is_elite_wave(),
		# 🔒 T1 反制窗口 UI 数据源（🔴 只**增**只读键，不改既有键语义）：
		#   `aggro_ui` = "塔会挨打"这一**事实层总闸**（= 仇恨开关本身，与复活档位解耦）→
		#                供渲染层门控"停机压暗"（塔因仇恨倒下就该看见它倒下）。
		#   `next_is_elite_wave` = **下一波**是否精英波（供 HUD 安全窗"预告"，区别于"当前波"）。
		"aggro_ui": tower_aggro_enabled,
		"next_is_elite_wave": elite_waves_enabled and _MonsterData.is_elite_wave(w + 1),
	}


func state_name() -> String:
	match state:
		State.IDLE:
			return "Idle"
		State.SPAWNING:
			return "Spawning"
		State.FIGHTING:
			return "Fighting"
		State.SAFE_WINDOW:
			return "SafeWindow"
	return "?"


# ---------------------------------------------------------------------------
#  🟡 单测用：手工摆怪（AC-W7 伤害分配）
# ---------------------------------------------------------------------------
## 清空当前波次队列，手工摆入指定 `t_remain` 的怪（HP 固定），用于集火顺序断言。
func debug_set_monsters(pairs: Array, p_hp: float) -> void:
	monsters = []
	for i in range(pairs.size()):
		var m = _Monster.new()
		m.setup(i, "Swarm", false, float(p_hp), 1.0, float(pairs[i]))
		monsters.append(m)
	spawned = n            # 不再出货
	state = State.FIGHTING
