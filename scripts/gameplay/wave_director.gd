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
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
## 🆕 关卡波表（stage-waves.md）：每波「只数 / 单只 HP / 三原型构成 / 精英只数」的 SSOT。
##   🔴 只在 `stage_waves_enabled` 时被读（默认 false → 一次都不调）→ 金标本逐位不变。
const _StageWaves := preload("res://scripts/data/stage_waves.gd")
const _Monster := preload("res://scripts/gameplay/monster.gd")
## 🆕 战斗类型系统 —— 只在 combat_types_enabled 时按抗性分池结算（默认关 → 逐位不变）。
const _CombatTypes := preload("res://scripts/data/combat_types.gd")
## 🆕 触发型建筑（2026-11-07）：整备（每波）/ 阵亡 时给塔加等级。
const _TowerEffects := preload("res://scripts/engine/tower_effects.gd")
const _TD := preload("res://scripts/data/tower_data.gd")
const _TacticalCombat := preload("res://scripts/gameplay/tactical_combat.gd")
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
	AGGRO_CORE = 3,
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
## 正式关卡建筑攻防；默认关闭，保留历史模拟的漏怪结算。
var structure_attacks_enabled: bool = false
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
## 🆕 关卡波表（`scripts/data/stage_waves.gd` · `design/gdd/stage-waves.md`）。
##   🔴 **默认 false**。这是本项目所有新机制的入场条件：默认路径与改前**逐位相同**。
##   打开后：`start_wave()` 用波表覆盖本波 `n` / `hp_unit`，`_build_spawn_table()` 用波表的
##   三原型构成（后者仍需 `prototype_split_enabled` 才真正生效，见 §8.3 分层纪律）。
##   🔴 neutral 波（0-1）恒不覆盖 —— 它是与金标本逐位对齐的回归锚点。
var stage_waves_enabled: bool = false
## 🆕 当前关卡 id（`stage_waves.gd` 的键，如 "3-1"）。"" = 无波表 → 走基准曲线。
var stage_id: String = ""
## 🆕 难度加压档位 `S` = 已守地区数（campaign 注入）。
##   只做两件事：把最早的 k=floor(S/3) 个「试探」波升级为「潮涌」波；处刑波精英 +k。
##   🔴 **不加波数**：`hp` 是 16×1.42^(w−1)，+1 波末波就贵 42%，那是断崖不是斜坡。
var escalation: int = 0
## 🆕 本波波表结果（`start_wave` 内算一次，供 `_build_spawn_table` / `_elite_count_wave` 消费）。
##   {} = 无波表或越界；{"neutral": true} = 中性波 → 一切按金标本。
var cur_spec: Dictionary = {}
## 🆕 战斗类型系统（物理/魔法 × 物抗/魔抗）。🔴 默认 false = 旧聚合池口径逐位不变。
##   打开后：塔按攻击类型拆分 DPS 池，怪物按原型抗性分别结算（见 `_substep` ②）。
var combat_types_enabled: bool = false
## 仅玩家关卡开启；基准模拟与历史回归仍使用原聚合池。
var tactical_combat_enabled: bool = false

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
## 🆕 战斗类型：物攻 / 魔攻 / 真实 DPS 池（🔴 默认 combat_types_enabled=false → 恒 0，不消费）。
var _phys_dps: float = 0.0
var _magic_dps: float = 0.0
var _true_dps: float = 0.0
## 🆕 破甲光环：物抗 / 魔抗全局破甲量（🔴 默认关闭 → 恒 0，不消费；见 start_wave 计算）。
var _phys_reduct: float = 0.0
var _magic_reduct: float = 0.0
var hp_unit: float = 0.0
var spk: float = 0.0        # scrap_per_kill = 2 + 0.5w
var t_reach: float = 10.0
var v0_: float = 10.10
var limit: float = 0.0      # D + t_reach + 1e-9

var monsters: Array = []
## 🆕 召唤小兵（2026-11-07 · Necro 等）：会在战场上移动、攻击最近敌人的友方单位。
##   每项 = {pos: Vector2, ttl: float, dps: float, speed: float}；🔴 只在实时战斗里存在，
##   批处理镜像不生成 → 金标本 / MC 零扰动。
var minions: Array = []

# 焚星塔的波内状态；按塔位分别计数，开波清空。
var _fire_charge: Dictionary = {}
var _fire_attack_clock: Dictionary = {}
var _fire_blasts: Array = []
var _frost_attack_clock: Dictionary = {}
var _ice_storms: Array = []
var _ice_storm_queue: Array = []
var _resolving_ice_storms: bool = false
const _ChargePow := preload("res://scripts/engine/fp_pow.gd")
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

## 🆕 关卡推进（2026-11-07）：实例波数上限 `_max_wave`（默认 = MAX_WAVE）。
##    🔴 金标本零扰动：默认值 20 与 `MAX_WAVE` 逐位一致，胜利判定 `w >= _max_wave`
##       在不被覆盖时与 `w >= MAX_WAVE` 完全等价。只有关卡系统调用 `set_max_wave()`
##       才改变（此时已在玩家路线、非金标本路径）。
##    🔴 为什么用实例字段而非改 `const`：`MAX_WAVE` 被金标本 `run_loop`（max_wave=20）
##       隐式对齐，改常量会让 PATH 金标本全部错位。实例字段默认 20 = 逐位不变。
var _max_wave: int = MAX_WAVE


## 覆盖本局总波数（关卡系统注入；不调 = 20，与金标本等价）。
##   返回是否成功（拒绝 <=0 的非法值）。
func set_max_wave(w: int) -> bool:
	if w <= 0:
		return false
	_max_wave = w
	return true


## 🆕 注入「本局打的是哪一关 + 加压档位」。
##   · 波数**由波表长度决定**（不读 `CampaignData.STAGES[..].wave_count`）：
##     表长才是闭合力，两处不一致时以表为准，`StageWaves.validate()` 的 V-2 会红。
##   · 🔴 `stage_waves_enabled=false` 时只记录、不改 `_max_wave` → 完全惰性。
##   返回是否成功接管波数控制。
func set_stage(p_stage_id: String, p_escalation: int = 0) -> bool:
	stage_id = p_stage_id
	escalation = maxi(0, p_escalation)
	if not stage_waves_enabled or not _StageWaves.has_stage(p_stage_id):
		return false
	return set_max_wave(_StageWaves.wave_count(p_stage_id))


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

func recover_preparation_buildings() -> void:
	if runtime != null and runtime.recover_preparation_buildings():
		core_hp = float(player.core_hp)


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
	# 🆕 关卡波表：只重排「这一波长什么样」，**不改任何常量**（hp_growth / num_growth / wave_dur /
	#   spawn_window / t_reach / leak_damage 一个都不碰）。整关总血量守恒由 `stage_waves.gd` 保证。
	#   🔴 默认 stage_waves_enabled=false → cur_spec 恒 {} → 下面几行恒不执行 → 金标本逐位不变。
	#   🔴 `neutral` 波（0-1）**必须**跳过：它是「实时 == 金标本」的回归锚点（V-5）。
	cur_spec = {}
	if stage_waves_enabled and stage_id != "":
		cur_spec = _StageWaves.wave_spec(stage_id, w, cfg, escalation)
		if not cur_spec.is_empty() and not bool(cur_spec.get("neutral", false)):
			n = int(cur_spec["n"])
			hp_unit = float(cur_spec["hp"])
	spk = float(ms["scrap_per_kill"])
	t_reach = float(ms["t_reach"])
	var D := float(ms["D"])
	# 🔴 R1：本波打的是**上波买出来的构筑** → 波首算一次 DPS，波内恒定（与金标本同）
	# 🆕 触发型建筑 · 整备（`prepare`）：每波开始加等级 —— 🔴 必须在 `dps_only` **之前**，
	#    这样本波 dps 就能吃到「整备」升级。金标本路径不含触发塔 → 零扰动。
	_TowerEffects.apply_trigger(player, "prepare")
	dps = _DE.dps_only(player, cfg, geo)
	# 🆕 战斗类型：波首算一次按攻击类型拆分的 DPS 池（🔴 默认关 → 不消费，逐位不变）。
	_phys_dps = 0.0
	_magic_dps = 0.0
	_true_dps = 0.0
	_phys_reduct = 0.0
	_magic_reduct = 0.0
	if combat_types_enabled:
		var _byt: Dictionary = _DE.compute_dps(player, cfg, geo).get("dps_by_type", {})
		_phys_dps = float(_byt.get("physical", 0.0))
		_magic_dps = float(_byt.get("magic", 0.0))
		_true_dps = float(_byt.get("true", 0.0))
		# 🆕 破甲光环：从场上塔类型算物抗/魔抗破甲量（与批处理 wave_sim 同一 SSOT → 逐位等价）。
		var _ctypes: Array = []
		for _t in player.towers:
			_ctypes.append(String(_t.ctype))
		_phys_reduct = _CombatTypes.armor_reduction(_ctypes, _CombatTypes.PHYSICAL)
		_magic_reduct = _CombatTypes.armor_reduction(_ctypes, _CombatTypes.MAGIC)
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
	_fire_charge.clear()
	_fire_attack_clock.clear()
	_fire_blasts.clear()
	_frost_attack_clock.clear()
	_ice_storms.clear()
	_ice_storm_queue.clear()
	_resolving_ice_storms = false
	last_result_w = -1
	_build_spawn_table()
	# 🔒 T1（Q-T2 = ①）：仇恨开启时，波首把未 Disabled 的塔重置为满血。
	#   MVP 无修复机制 → 每波满血是最简口径（Disabled 塔保持 Disabled，
	#   留给后续批次的波次间「修复/拆除/放着不管」三选一）。
	#   🔴 仅 tower_aggro_enabled 时触碰 player.towers → 金标本等价口径零扰动。
	if tower_aggro_enabled or structure_attacks_enabled:
		_init_tower_hp()
	state = State.SPAWNING


## 🔒 T1：把未 Disabled 的塔按 `HP0 × h^0.6` 重置满血（Q-T2 = ①）。
func _init_tower_hp() -> void:
	if player == null:
		return
	var exp := float(cfg.get("tower_stack_exp", 0.6))
	# 🆕 防御光环：全场塔 max HP ×(1+Σ)。金标本无此类塔 → 1.0（逐位不变）。
	var def_mult := 1.0 + _TowerEffects.def_bonus(player)
	for t in player.towers:
		if not bool(t.disabled):
			t.hp_max = _MonsterData.tower_hp(int(t.h), exp) * def_mult
			t.hp = t.hp_max
	# 🆕 召唤：每波开始时按塔上的 summon 配置重新生成小兵。
	_spawn_summoned()


## 🆕 召唤小兵：在召唤塔的格心生成 N 个游魂（围绕塔身错开，避免完全重叠）。
func _spawn_summoned() -> void:
	minions.clear()
	if player == null:
		return
	for t in player.towers:
		if bool(t.disabled):
			continue
		var n := _TD.tower_summon_n(String(t.ctype))
		if n <= 0:
			continue
		var base := Vector2.ZERO
		if geo != null:
			var si := int(t.slot)
			if si >= 0 and si < geo.slots.size() and geo.slots[si] is Vector2:
				base = geo.slots[si]
		for k in range(n):
			var ang := TAU * float(k) / float(maxi(1, n))
			minions.append({
				"pos": base + Vector2(cos(ang), sin(ang)) * 0.9,
				"ttl": _TD.tower_summon_ttl(String(t.ctype)),
				"dps": _TD.tower_summon_dps(String(t.ctype)),
				"speed": _TD.tower_summon_speed(String(t.ctype)),
			})


## 本波出生表（纯确定性，无 RNG）
func _build_spawn_table() -> void:
	_proto_seq = []
	_elite_flags = []
	_hp_mults = []
	_spd_mults = []
	# 🆕 波表的三原型构成（{} = 无波表 / 中性波 → 走 `MonsterData` 基准构成）。
	#   🔴 分层纪律：`n/hp` 覆盖只需 `stage_waves_enabled`，`comp` 还要 `prototype_split_enabled`
	#      —— 因为三原型分化会破「实时↔批处理等价」(S5-D1)，只能在玩家路线开。
	var comp: Dictionary = {}
	if not cur_spec.is_empty() and not bool(cur_spec.get("neutral", false)):
		comp = cur_spec.get("comp", {})
	if not prototype_split_enabled:
		# 🔴 金标本口径：单一基准怪（m_hp = 1.00、m_spd = 1.00）
		for i in range(n):
			_proto_seq.append("Swarm")
			_elite_flags.append(false)
			_hp_mults.append(1.0)
			_spd_mults.append(1.0)
		return
	_proto_seq = _MonsterData.spawn_sequence(n) if comp.is_empty() else _StageWaves.spawn_sequence(n, comp)
	var n_e := _elite_count_wave()
	var c := _MonsterData.elite_conserve(n, n_e)
	var eidx := _MonsterData.elite_indices(n, n_e)
	# 单只乘数：基准构成时 `proto_mult` 短路返回 `MonsterData` 原值 → 与改前逐位一致。
	var pm: Dictionary = {"hp": _MonsterData.M_HP, "spd": _MonsterData.M_SPD} if comp.is_empty() else _StageWaves.proto_mult(comp)
	for i in range(n):
		var p := String(_proto_seq[i])
		var e := eidx.has(i)
		_elite_flags.append(e)
		_hp_mults.append(_MonsterData.ELITE_HP_MULT if e else float(pm["hp"][p]) * c)
		_spd_mults.append(float(pm["spd"][p]))


## 🆕 本波精英只数 —— **防漂移的单一入口**（`_build_spawn_table` / `_spawn_one` / `is_elite_wave` 共用）。
##   · 无波表 → `MonsterData.elite_count(w, n)`（金标本 w%5 周期，逐位不变）；
##   · 有波表 → 波表说了算（含 `S` 加压的 +k），且 **必须**仍满足
##     `elite_conserve(n, n_e)` 的合法性（n_e < n/2.5），由 `StageWaves.elite_for` 夹紧。
func _elite_count_wave() -> int:
	if not elite_waves_enabled:
		return 0
	if not cur_spec.is_empty() and not bool(cur_spec.get("neutral", false)):
		return int(cur_spec.get("elite", 0))
	return _MonsterData.elite_count(w, n)


## 🆕 任意波 `pw` 是否精英波（当前波 / 下一波预告共用同一判定，避免两处口径漂移）。
func _is_elite_wave_at(pw: int) -> bool:
	if not elite_waves_enabled:
		return false
	if stage_waves_enabled and stage_id != "":
		var sp := _StageWaves.wave_spec(stage_id, pw, cfg, escalation)
		if not sp.is_empty() and not bool(sp.get("neutral", false)):
			return int(sp.get("elite", 0)) > 0
	return _MonsterData.is_elite_wave(pw)


func is_elite_wave() -> bool:
	return _is_elite_wave_at(w)


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
	_tick_frost_effects(_WaveSim.DT)
	_tick_fire_effects(_WaveSim.DT)
	if tactical_combat_enabled:
		_TacticalCombat.apply(self, _WaveSim.DT)
	elif combat_types_enabled:
		# 🆕 类型分池：物攻池 / 魔攻池 / 真实池各自独立集火，每只怪按原型抗性减免；
		#   真实伤害无视抗性。🔴 与 `WaveSim._apply_pool` 语义同构（同 SSOT → 逐位等价）。
		var _phys_dmg := _phys_dps * _WaveSim.DT
		var _magic_dmg := _magic_dps * _WaveSim.DT
		var _true_dmg := _true_dps * _WaveSim.DT
		_apply_pool_live(_phys_dmg, _CombatTypes.PHYSICAL, _phys_reduct)
		_apply_pool_live(_magic_dmg, _CombatTypes.MAGIC, _magic_reduct)
		_apply_pool_live(_true_dmg, _CombatTypes.TRUE, 0.0)
	else:
		var dmg := dps * _WaveSim.DT
		for m in monsters:
			if float(m.hp) <= 0.0:
				continue
			if dmg <= 0.0:
				break
			if float(m.hp) <= dmg:
				dmg -= float(m.hp)
				m.hp = 0.0
				_record_monster_kill(m)
			else:
				m.hp = float(m.hp) - dmg
				dmg = 0.0

	# ---- ②b 🆕 持续掉血（DoT）：无视抗性的全场每秒伤害（Plague 等）。
	#   🔴 金标本无 dot 塔 → 0 → 本段不进入（逐位不变）。
	var _dot := _TowerEffects.dot_dps(player)
	if _dot > 0.0 and not tactical_combat_enabled:
		_apply_pool_live(_dot * _TowerEffects.debuff_damage_mult(player) * _WaveSim.DT,
			_CombatTypes.TRUE, 0.0)

	# ---- ②c 🆕 回复：每秒为塔恢复生命（Wither 等）；塔满血则无变化。
	_TowerEffects.regen(player, _WaveSim.DT)

	# ---- ③ 前进：判死 / 漏怪（原地压缩，保持相对顺序）----
	#   🔒 T1：AggroTower 态怪物**停下**（t_remain 冻结，不前进、不漏怪）。
	var frozen_this_step: Array = []
	var wpos := 0
	var leak_dmg := float(cfg.get("leak_damage", 50.0))
	for m2 in monsters:
		if float(m2.hp) <= 0.0:
			continue
		if float(m2.frozen_remaining) > 0.0:
			frozen_this_step.append(m2)
		var attacking_tower: bool = (tower_aggro_enabled or structure_attacks_enabled) and m2.state == MState.AGGRO_TOWER
		var attacking_core: bool = structure_attacks_enabled and m2.state == MState.AGGRO_CORE
		if attacking_tower or attacking_core:
			# 攻击建筑时冻结 t_remain，仍可被防御塔击杀。
			monsters[wpos] = m2
			wpos += 1
			continue
		var previous_time := float(m2.t_remain)
		var previous_distance: float = m2.pos(v0_).distance_to(_SpaceModel.core_pos()) if structure_attacks_enabled else 0.0
		var move_dt := _frost_move_dt(m2, _WaveSim.DT)
		m2.t_remain = float(m2.t_remain) - move_dt
		if structure_attacks_enabled and (m2.t_remain<=0.0 or m2.pos(v0_).distance_to(_SpaceModel.core_pos())<=_MonsterData.CORE_ATTACK_R):
			# 径向位移与剩余时间成正比，将位置钳在核心接触圈，避免穿入核心。
			if _SpaceModel.is_radial():
				m2.t_remain = maxf(0.0,previous_time*_MonsterData.CORE_ATTACK_R/maxf(previous_distance,_MonsterData.CORE_ATTACK_R))
			else:
				m2.t_remain = 0.0
			m2.state = MState.AGGRO_CORE
			m2.target_slot = -1
			monsters[wpos] = m2
			wpos += 1
			continue
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
	if structure_attacks_enabled:
		_apply_structure_attacks()
	elif tower_aggro_enabled and w > warmup_waves:
		_apply_aggro()

	# ---- ④b 🆕 召唤小兵（2026-11-07）：移动 + 攻击最近敌人。
	_update_minions(_WaveSim.DT)

	# ---- ⑤ 🔒 V-8 战斗中复活（M-1）：Disabled 塔累计 N 秒 → 系统自动重启 ----
	#   🔴 与批处理镜像同序（都在④仇恨之后）→ 死亡当子步就开始累计 `revive_t_disabled`。
	#   🔴 `repair_on_disable < 9`（默认 0）→ 函数首行 return，off 路径逐位不变。
	_tick_revive()
	_advance_frozen_timers(_WaveSim.DT, frozen_this_step)



## 叠层冰冻入口：来源共享层数，完全冻结期间不刷新冻结计时或积攒下轮层数。
func apply_frost_effect(target, stacks: int = 1) -> void:
	if player == null or target == null or stacks <= 0 or not monsters.has(target):
		return
	if state != State.SPAWNING and state != State.FIGHTING:
		return
	if float(target.hp) <= 0.0 or int(target.state) == MState.LEAKED or float(target.frozen_remaining) > 0.0:
		return
	target.frost_stacks = mini(int(_TD.FROST_EFFECT["max_stacks"]), int(target.frost_stacks) + stacks)
	if int(target.frost_stacks) >= int(_TD.FROST_EFFECT["max_stacks"]):
		target.frozen_remaining = float(_TD.FROST_EFFECT["freeze_duration"])


## 在子步末尾计时：本子步已经完整执行冻结，恰好冻结 2 秒而非少一 tick。
func _advance_frozen_timers(dt: float, targets: Array) -> void:
	for m in targets:
		if float(m.hp) <= 0.0 or float(m.frozen_remaining) <= 0.0:
			continue
		m.frozen_remaining = maxf(0.0, float(m.frozen_remaining) - dt)
		if float(m.frozen_remaining) <= 1e-9:
			m.frozen_remaining = 0.0
			m.frost_stacks = 0


func _frost_move_dt(m, dt: float) -> float:
	if float(m.frozen_remaining) > 0.0:
		return 0.0
	if int(m.frost_stacks) <= 0:
		return dt
	return dt * maxf(0.0, 1.0 - float(m.frost_stacks) * float(_TD.FROST_EFFECT["slow_per_stack"]))


func _tick_frost_effects(dt: float) -> void:
	for storm in _ice_storms:
		storm["ttl"] = float(storm["ttl"]) - dt
	_ice_storms = _ice_storms.filter(func(b): return float(b["ttl"]) > 0.0)
	if player == null or not bool(cfg.get("stacking_frost_enabled", false)):
		return
	var aspd := 0.0
	for t in player.towers:
		if not bool(t.disabled):
			aspd += _TD.tower_buff_aspd(String(t.ctype))
	for source in player.towers:
		var name := String(source.ctype)
		var slot := int(source.slot)
		# 原来具备减速的任何来源，统一改为每次附加一层 10% 冰冻。
		if bool(source.disabled) or _TD.tower_slow(name) <= 0.0 or _TD.tower_dps(name) <= 0.0:
			_frost_attack_clock.erase(slot)
			continue
		var targets: Array = []
		for m in monsters:
			if float(m.hp) > 0.0 and int(m.state) != MState.LEAKED and _tower_pos(source).distance_to(m.pos(v0_)) <= _TD.tower_rng(name):
				targets.append(m)
		if targets.is_empty():
			_frost_attack_clock.erase(slot)
			continue
		var period := 1.0 / (_TD.tower_attack_speed(name) * (1.0 + aspd))
		var elapsed := float(_frost_attack_clock.get(slot, 0.0)) + dt
		while elapsed + 1e-9 >= period:
			elapsed -= period
			var front = targets[0]
			for target in targets:
				if target != front and (not bool(_TD._tower_def(name).get("aoe", false)) or target.pos(v0_).distance_to(front.pos(v0_)) > 6.0):
					continue
				apply_frost_effect(target)
		_frost_attack_clock[slot] = maxf(0.0, elapsed)


## 所有死亡入口统一记账；冻结死亡的冰暴通过队列处理，避免连锁爆炸递归。
func _record_monster_kill(m) -> void:
	if bool(m.death_recorded) or float(m.hp) > 0.0:
		return
	m.death_recorded = true
	var shatter := float(m.frozen_remaining) > 0.0
	if shatter:
		_ice_storm_queue.append(m.pos(v0_))
		m.frozen_remaining = 0.0
		m.frost_stacks = 0
	kills += 1
	scrap_earned += spk
	emit_signal("monster_killed", m)
	_TowerEffects.on_kill(player)
	if _resolving_ice_storms or not shatter:
		return
	_resolving_ice_storms = true
	var cursor := 0
	while cursor < _ice_storm_queue.size():
		var center: Vector2 = _ice_storm_queue[cursor]
		cursor += 1
		_release_ice_storm(center)
	_ice_storm_queue.clear()
	_resolving_ice_storms = false


func _release_ice_storm(center: Vector2) -> void:
	var radius := float(_TD.FROST_EFFECT["storm_radius"])
	var damage := float(_TD.FROST_EFFECT["storm_damage"])
	_ice_storms.append({"pos": center, "radius": radius, "ttl": 0.6})
	for m in monsters:
		if float(m.hp) <= 0.0 or int(m.state) == MState.LEAKED or center.distance_squared_to(m.pos(v0_)) > radius * radius + 1e-6:
			continue
		# 先附两层再结算伤害；若因此满十层且被击杀，也会产生一次冰暴。
		apply_frost_effect(m, int(_TD.FROST_EFFECT["storm_stacks"]))
		var factor := 1.0
		if combat_types_enabled:
			factor -= clampf(_CombatTypes.effective_resist(String(m.proto), _CombatTypes.MAGIC, _magic_reduct), 0.0, 1.0)
		m.hp = maxf(0.0, float(m.hp) - damage * factor)
		if float(m.hp) <= 0.0:
			_record_monster_kill(m)


## 火系塔按攻速施加火焰。群攻以首个射程内目标为中心溅射；每个目标各计一次。
## 这是状态事件，不额外添加普攻伤害，也不把 DoT 每跳当作一次附加。
func _tick_fire_effects(dt: float) -> void:
	for blast in _fire_blasts:
		blast["ttl"] = float(blast["ttl"]) - dt
	_fire_blasts = _fire_blasts.filter(func(b): return float(b["ttl"]) > 0.0)
	for m in monsters:
		m.burn_remaining = maxf(0.0, float(m.burn_remaining) - dt)
		if float(m.burn_remaining) <= 0.0:
			m.burn_stacks = 0
	if player == null:
		return
	var aspd := 0.0
	for t in player.towers:
		if not bool(t.disabled):
			aspd += _TD.tower_buff_aspd(String(t.ctype))
	for source in player.towers:
		var name := String(source.ctype)
		if bool(source.disabled) or _TD.tower_tag(name) != "fire" or _TD.tower_dps(name) <= 0.0:
			_fire_attack_clock.erase(int(source.slot))
			continue
		var center := _tower_pos(source)
		var targets: Array = []
		for m in monsters:
			if float(m.hp) > 0.0 and center.distance_to(m.pos(v0_)) <= _TD.tower_rng(name):
				targets.append(m)
		if targets.is_empty():
			_fire_attack_clock.erase(int(source.slot))
			continue
		var period := 1.0 / (_TD.tower_attack_speed(name) * (1.0 + aspd))
		var elapsed := float(_fire_attack_clock.get(int(source.slot), 0.0)) + dt
		while elapsed + 1e-9 >= period:
			elapsed -= period
			var front = null
			for candidate in targets:
				if float(candidate.hp) > 0.0:
					front = candidate
					break
			if front == null:
				break
			var hit_pos: Vector2 = front.pos(v0_)
			for target in targets:
				if target != front and (not bool(_TD._tower_def(name).get("aoe", false)) or target.pos(v0_).distance_to(hit_pos) > 6.0):
					continue
				apply_fire_effect(target)
		_fire_attack_clock[int(source.slot)] = maxf(0.0, elapsed)


## 唯一火焰附加入口：同一敌人重复附加也充能；死亡、漏出、非战斗事件不计。
func apply_fire_effect(target) -> void:
	if player == null or target == null or not monsters.has(target):
		return
	if state != State.SPAWNING and state != State.FIGHTING:
		return
	if float(target.hp) <= 0.0 or int(target.state) == MState.LEAKED:
		return
	target.burn_remaining = float(_TD.FIRE_EFFECT["duration"])
	target.burn_stacks = int(target.burn_stacks) + 1
	var ignite := int(target.burn_stacks) >= int(_TD.FIRE_EFFECT["max_stacks"])
	var ignite_pos: Vector2 = target.pos(v0_)
	if ignite:
		target.burn_stacks = 0
		target.burn_remaining = 0.0
	var ready: Array = []
	# 先给所有塔结算同一次事件，再释放爆发，避免击杀/升级改变计数顺序。
	for tower in player.towers:
		var params := _TD.tower_fire_charge(String(tower.ctype))
		if bool(tower.disabled) or params.is_empty():
			continue
		var slot := int(tower.slot)
		var charge := int(_fire_charge.get(slot, 0)) + 1
		if charge >= int(params["capacity"]):
			_fire_charge[slot] = 0
			ready.append({"tower": tower, "params": params})
		else:
			_fire_charge[slot] = charge
	# 附加本身先给所有焚星塔充能，再处理这次附加触发的满层引爆。
	if ignite:
		_apply_fire_area_damage(ignite_pos, float(_TD.FIRE_EFFECT["blast_radius"]),
			float(_TD.FIRE_EFFECT["blast_damage"]), "ignition")
	for entry in ready:
		_release_fire_blast(entry["tower"], entry["params"])


## 全场寻优：枚举敌人位置及两敌人等半径圆的交点，找到覆盖活敌最多的爆心。
## 最优覆盖圆总可移动到一个敌人处或两个敌人的边界交点，不能只枚举敌人中心。
## 数量相同时保留先发现的位置（怪物稳定顺序），不引入随机抖动。
func _fire_blast_center(radius: float) -> Dictionary:
	var points := PackedVector2Array()
	for m in monsters:
		if float(m.hp) > 0.0 and int(m.state) != MState.LEAKED:
			points.append(m.pos(v0_))
	if points.is_empty():
		return {}
	var radius_sq := radius * radius
	var best := points[0]
	var best_count := 0
	for point in points:
		var count := _fire_coverage(point, points, radius_sq)
		if count > best_count:
			best = point
			best_count = count
		if best_count == points.size():
			return {"pos": best}
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			var delta := points[j] - points[i]
			var distance_sq := delta.length_squared()
			if distance_sq <= 1e-12 or distance_sq > 4.0 * radius_sq + 1e-6:
				continue
			var middle := (points[i] + points[j]) * 0.5
			var offset := Vector2(-delta.y, delta.x) / sqrt(distance_sq) * sqrt(maxf(0.0, radius_sq - distance_sq * 0.25))
			for candidate in [middle + offset, middle - offset]:
				var count := _fire_coverage(candidate, points, radius_sq)
				if count > best_count:
					best = candidate
					best_count = count
				if best_count == points.size():
					return {"pos": best}
	return {"pos": best}


func _fire_coverage(center: Vector2, points: PackedVector2Array, radius_sq: float) -> int:
	var count := 0
	for point in points:
		if center.distance_squared_to(point) <= radius_sq + 1e-6:
			count += 1
	return count


func _release_fire_blast(tower, params: Dictionary) -> void:
	var radius := float(params["radius"])
	var aim := _fire_blast_center(radius)
	if aim.is_empty():
		return
	var center: Vector2 = aim["pos"]
	var damage := float(params["damage"]) * _ChargePow.pow_py(float(tower.h), float(cfg.get("tower_stack_exp", 0.6)))
	damage *= 1.0 + _TowerEffects.atk_bonus(player)
	_apply_fire_area_damage(center, radius, damage, "pyroclasm")


## 两种火焰爆炸共享魔抗、击杀奖励与演出；爆炸不会再次附加火焰。
func _apply_fire_area_damage(center: Vector2, radius: float, damage: float, kind: String) -> void:
	_fire_blasts.append({"pos": center, "radius": radius, "ttl": 0.6, "kind": kind})
	for m in monsters:
		if float(m.hp) <= 0.0 or int(m.state) == MState.LEAKED or center.distance_squared_to(m.pos(v0_)) > radius * radius + 1e-6:
			continue
		var factor := 1.0
		if combat_types_enabled:
			factor -= clampf(_CombatTypes.effective_resist(String(m.proto), _CombatTypes.MAGIC, _magic_reduct), 0.0, 1.0)
		m.hp = maxf(0.0, float(m.hp) - damage * factor)
		if float(m.hp) <= 0.0:
			_record_monster_kill(m)


## 🆕 召唤小兵（2026-11-07）：移动 + 攻击最近敌人。
##   🔴 只有玩家路线会召唤（金标本 / 批处理不生成 minions）→ 零扰动。
func _update_minions(dt: float) -> void:
	if minions.is_empty():
		return
	var alive: Array = []
	for m in monsters:
		if m != null and float(m.hp) > 0.0:
			alive.append(m)
	for mi in range(minions.size() - 1, -1, -1):
		var mn: Dictionary = minions[mi]
		mn["ttl"] = float(mn["ttl"]) - dt
		if float(mn["ttl"]) <= 0.0:
			minions.remove_at(mi)
			continue
		if alive.is_empty():
			continue
		var mp: Vector2 = mn["pos"]
		var best = null
		var best_d := INF
		for m in alive:
			if float(m.hp) <= 0.0:
				continue
			var d: float = (m.pos(v0_) as Vector2).distance_to(mp)
			if d < best_d:
				best_d = d
				best = m
		if best == null:
			continue
		if best_d > 1.5:
			var dir: Vector2 = ((best.pos(v0_) as Vector2) - mp).normalized()
			mn["pos"] = mp + dir * float(mn["speed"]) * dt
		else:
			best.hp = maxf(0.0, float(best.hp) - float(mn["dps"]) * dt)
			if float(best.hp) <= 0.0:
				_record_monster_kill(best)
## 🔒 T1（Q-T3 = ① 机会型仇恨）：每子步的仇恨判定（GDD §2.6 状态机）。
##   · Marching 怪：当前位置与某座 **未 Disabled** 塔的距离 ≤ AGGRO_R → 转 AggroTower，
##     目标 = 最近的塔（迟滞带内锁定）。
##   · AggroTower 怪：目标塔消失 / 已 Disabled / 距离 > AGGRO_EXIT（迟滞带退出）
##     → 回 Marching；否则对目标塔造成 `ATTRITION × HP0 × m_dps` 伤害。
##     塔 hp 归零 → 进入 Disabled 中间态（断输出不断链）→ 发 tower_destroyed。
##   🔴 迟滞带（AGGRO_R=9.0 进 / AGGRO_EXIT=10.8 出）防边界抖动（Q-T3 R4）。
## 实机关卡从第一波开始攻击建筑。锁塔怪也必须进入攻击范围，不能隔图扣血。
func _apply_structure_attacks() -> void:
	if player == null or run_failed:
		return
	for monster in monsters:
		if float(monster.hp)<=0.0 or float(monster.frozen_remaining)>0.0 or monster.state==MState.LEAKED:
			continue
		if monster.state==MState.AGGRO_TOWER:
			var target = _tower_by_slot(int(monster.target_slot))
			if target==null or bool(target.disabled) or monster.pos(v0_).distance_to(_tower_pos(target))>_MonsterData.AGGRO_EXIT:
				monster.state = MState.MARCHING
				monster.target_slot = -1
				continue
			_damage_tower(monster,_MonsterData.sapper_dmg_mult(w))
			continue
		var slot := _nearest_exposed_tower(monster,v0_)
		if slot>=0:
			monster.state = MState.AGGRO_TOWER
			monster.target_slot = slot
			_damage_tower(monster,_MonsterData.sapper_dmg_mult(w))
		elif monster.state==MState.AGGRO_CORE:
			core_hp = maxf(0.0,core_hp-_MonsterData.STRUCTURE_ATTACK_DPS*float(monster.m_dps)*_WaveSim.DT)
			player.core_hp = core_hp
			if core_hp<=0.0:
				run_failed = true
				emit_signal("run_lost",w)
				break


func _apply_aggro() -> void:
	if player == null:
		return
	var v0x := v0_
	# 🟠 P2-Sapper（路线 A · 波级预计算贯穿）：同一 `w`、同一 SSOT 函数 → 与批处理镜像逐位等价。
	var sapper_mult := _MonsterData.sapper_dmg_mult(w)
	for m in monsters:
		if m == null or float(m.hp) <= 0.0 or float(m.frozen_remaining) > 0.0:
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
					_damage_tower(m, sapper_mult)


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
## 🟠 P2-Sapper：`sapper_mult` = 本波的 `sapper_dmg_mult(w)`（由 `_apply_aggro` 贯穿）。
func _damage_tower(m, sapper_mult: float) -> void:
	if float(m.hp) <= 0.0 or float(m.frozen_remaining) > 0.0:
		return
	var t = _tower_by_slot(m.target_slot)
	if t == null or bool(t.disabled):
		return
	# 对塔 DPS = ATTRITION × HP0 × m_dps(proto)（V-1 复合比口径；attrition_override>=0 时覆盖）
	# 🔒 T1 ⑤ Sapper：对塔伤害 ×`sapper_mult`（= SSOT `sapper_dmg_mult(w)`；中性 g≡1 ⇒ 逐位 = 3.0）。
	var mdps: float = float(m.m_dps) * (sapper_mult if m.sapper else 1.0)
	var base_dps := _MonsterData.STRUCTURE_ATTACK_DPS if structure_attacks_enabled else _MonsterData.resolve_attrition(attrition_override) * _MonsterData.HP0
	var dmg := base_dps * mdps * _WaveSim.DT
	t.hp = float(t.hp) - dmg
	if float(t.hp) <= 0.0:
		t.hp = 0.0
		# 🔒 V-8：死亡时刻资格快照（F-1）→ 🔴 必须在 `disabled = true` **之前**取
		#   （此时本塔尚属"未 Disabled"，carry 判定与批处理镜像同口径）。
		#   🔴 默认 repair_on_disable=0 → 不触发，零开销零扰动。
		if _revive_mode() >= 9:
			_death_snapshot(t)
		t.disabled = true          # 进入 Disabled 中间态（断输出不断链）
		# 🆕 触发型建筑 · 阵亡（`death`）：本塔死亡时给其它塔加等级。
		#   🔴 放在 dps 重算**之前** → 后续子步立刻吃到新等级（不用等下一波）。
		_TowerEffects.apply_trigger(player, "death", {"tower": t})
		# 🆕 死亡爆炸（Pyre 等）：对周围敌人造成一次大额真实伤害。
		_death_explode(t)
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
		t.hp_max = _MonsterData.tower_hp(int(t.h), exp) * (1.0 + _TowerEffects.def_bonus(player))
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
				_PathGeometry.expo_safe_max_for(_BuildGrid.sites_active()))
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


## 准备阶段只读预告，与实际生成共享角度、波表数量和地形边界；不推进波次或 RNG。
func spawn_angle(idx: int, wave: int) -> float:
	return _TacticalCombat.spawn_theta(idx, wave, stage_id) if tactical_combat_enabled else _SpaceModel.spawn_theta(idx, wave)


func preview_spawn_positions(wave: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not _SpaceModel.is_radial() or wave < 1:
		return points
	if stage_waves_enabled and stage_id != "" and wave > _StageWaves.wave_count(stage_id):
		return points
	var count := int(_WaveSim.monster_stats(wave, cfg)["n"])
	if stage_waves_enabled and stage_id != "":
		var spec := _StageWaves.wave_spec(stage_id, wave, cfg, escalation)
		if not spec.is_empty() and not bool(spec.get("neutral", false)):
			count = int(spec["n"])
	for i in range(count):
		points.append(_SpaceModel.radial_pos_of_t(_SpaceModel.T_REACH, 1.0, spawn_angle(i, wave)))
	return points


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
		m.set_theta(spawn_angle(idx, w))
	# 🔒 T1 ⑤ Sapper：Elite 波（每5波）里沿波次均匀铺开的精英怪 = Sapper（锁塔 ×3 增伤）。
	#   与批处理镜像 WaveSimAggro._build_sapper_flags 逐位对齐（同一 elite_indices 算法）。
	#   🔴 金标本零改动：elite_waves_enabled=false → 不标记任何 sapper。
	#   🔴 不依赖 `elite`（_elite_flags 在 MVP prototype_split_enabled=false 下恒 false）——
	#      Sapper 由 elite_waves_enabled 独立驱动，与批处理镜像同口径（直接判 is_elite_wave）。
	if _is_elite_wave_at(w):
		var n_e := _elite_count_wave()
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


## 🆕 战斗类型：单一类型伤害池的实时集火（🔴 仅 combat_types_enabled 时调用）。
##   🔴 与 `WaveSim._apply_pool` 语义同构（同 SSOT `CombatTypes` → 实时↔批处理逐位等价）。
## 🆕 死亡爆炸（2026-11-07）：塔阵亡时对半径内敌人造成一次真实伤害（无视抗性）。
##   🔴 只有玩家路线会出现带 `death_blast` 的塔；金标本无此字段 → 不触发（逐位不变）。
func _death_explode(t) -> void:
	var blast := _TD.tower_death_blast(String(t.ctype))
	if blast <= 0.0:
		return
	var radius := _TD.tower_death_blast_r(String(t.ctype))
	var tp := Vector2.ZERO
	var has_pos := false
	if geo != null:
		var slots: Array = geo.slots
		var si := int(t.slot)
		if si >= 0 and si < slots.size() and slots[si] is Vector2:
			tp = slots[si]
			has_pos = true
	for m in monsters:
		if float(m.hp) <= 0.0:
			continue
		if has_pos:
			var mp: Vector2 = m.pos(v0_)
			if mp.distance_to(tp) > radius:
				continue
		m.hp = maxf(0.0, float(m.hp) - blast)
		if float(m.hp) <= 0.0:
			_record_monster_kill(m)

##   每只怪按**有效抗性**（静态抗性 − 破甲量）减免，溢出结转；击杀走 `monster_killed` 信号。
func _apply_pool_live(dmg: float, dmg_type: String, reduction: float = 0.0) -> void:
	if dmg <= 0.0:
		return
	for m in monsters:
		if dmg <= 0.0:
			break
		if float(m.hp) <= 0.0:
			continue
		var resist := _CombatTypes.effective_resist(String(m.proto), dmg_type, reduction)
		var factor := 1.0 - clampf(resist, 0.0, 1.0)
		if factor <= 0.0:
			continue                       # 免伤：该类型打不动这只，伤害不消耗
		var eff := dmg * factor
		if float(m.hp) <= eff:
			dmg -= float(m.hp) / factor
			m.hp = 0.0
			_record_monster_kill(m)
		else:
			m.hp = float(m.hp) - eff
			dmg = 0.0


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
	if w >= _max_wave and not run_failed and not victory:
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

## 🆕 快照用：只导出渲染需要的两个字段（位置 / 剩余时长），不做任何状态复制。
func _snapshot_minions() -> Array:
	var out: Array = []
	for mn in minions:
		out.append({"pos": mn["pos"], "ttl": float(mn["ttl"])})
	return out
func snapshot() -> Dictionary:
	var live: Array = []
	for m in monsters:
		live.append({
			# 🟠 T-P6-07 R1（唯一 gameplay 触碰 · additive 只读键）：导出本波出生序号
			#   `index`（源 = `monster.gd:35` 既有字段）。供渲染层帧间差分做**逐怪伤害数字**
			#   （A2 需稳定 id：快照每帧重排 → 无 id 无法把"上一帧的它"对上"这一帧的它"）。
			#   🔴 与既有 `sapper` / `revive_charged` / `aggro_ui` 同族：additive、只读、
			#      不动任何值/口径/信号、不引入随机。`index` 波内唯一（0-based）、波间重置。
			"index": int(m.index),
			"proto": String(m.proto),
			"elite": bool(m.elite),
			"hp": float(m.hp),
			"hp_max": float(m.hp_max),
			"burning": int(m.burn_stacks) > 0 and float(m.burn_remaining) > 0.0,
			"burn_stacks": int(m.burn_stacks),
			"frost_stacks": int(m.frost_stacks),
			"frozen": float(m.frozen_remaining) > 0.0,
			"slow_ratio": minf(1.0, float(m.frost_stacks) * float(_TD.FROST_EFFECT["slow_per_stack"])),
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
				"fire_charge": int(_fire_charge.get(int(t.slot), 0)),
				"fire_capacity": int(_TD.tower_fire_charge(String(t.ctype)).get("capacity", 0)),
			})
	return {
		"w": w,
		"stage_id": stage_id,
		"tactical_combat": tactical_combat_enabled,
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
		# 🆕 召唤小兵（只读、additive）：渲染层据此画游魂；无召唤物时为空数组。
		"minions": _snapshot_minions(),
		"fire_blasts": _fire_blasts.duplicate(true),
		"ice_storms": _ice_storms.duplicate(true),
		"towers": towers,
		"towers_disabled": _count_disabled_towers(),
		# 🔒 V-8 渲染层总闸（**布尔**）：只有「仇恨开 + 复活档位开」时渲染层才画
		#   塔底充能点亮 / 重启动效。🔴 默认恒 false → 默认画面与改前**逐像素相同**。
		"revive_ui": tower_aggro_enabled and _revive_mode() >= 9,
		"prototype_split_enabled": prototype_split_enabled,
		"elite_waves_enabled": elite_waves_enabled,
		"tower_aggro_enabled": tower_aggro_enabled,
		"combat_types_enabled": combat_types_enabled,
		"is_elite_wave": is_elite_wave(),
		# 🔒 T1 反制窗口 UI 数据源（🔴 只**增**只读键，不改既有键语义）：
		#   `aggro_ui` = "塔会挨打"这一**事实层总闸**（= 仇恨开关本身，与复活档位解耦）→
		#                供渲染层门控"停机压暗"（塔因仇恨倒下就该看见它倒下）。
		#   `next_is_elite_wave` = **下一波**是否精英波（供 HUD 安全窗"预告"，区别于"当前波"）。
		"aggro_ui": tower_aggro_enabled or structure_attacks_enabled,
		"structure_attacks": structure_attacks_enabled,
		"next_is_elite_wave": _is_elite_wave_at(w + 1),
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
