extends Node2D
##
## 怪物 / 路径 / 塔位 **占位渲染层**（Node2D，世界层）
##
## 🔴 MVP 只做**占位可视化**（主理人决策 5：**不做美术渲染**，那是后续切片）：
##    · 路径：5 段折线（灰褐色粗线）+ 6 个路径点；
##    · 核心：路径终点 (55,25) 的实心方块；
##    · 塔位：空心圆；`d_path ≤ 9.0` 的暴露位外圈画一圈红环（🔴 GDD：MVP 只登记数据，
##      不产出玩法 → 这里只是"把静态事实画出来"，不给任何推荐）；
##    · 怪物：按原型上色 / 尺寸的实心圆 —— **Rush 小快 / Swarm 中 / Tank 大慢**，
##      Elite 加一圈黄环。
##
## 🔴 分层纪律（control-manifest §5）：本节点**只读** `WaveDirector.snapshot()`，
##    不写任何玩法状态，也不发意图信号。process_mode = INHERIT（随暂停停 →
##    安全窗冻结画面，这正是 W-C3 想要的"完全静止"）。
##
## 坐标：世界 XZ 平面（x ∈ [0,55]，z ∈ [16,48]）→ 屏幕像素。
##   映射 = 等比缩放 + 居中（保比例，不拉伸），与 `art-bible` §6.1 的等距投影无关（占位）。
##
## ⚠️ G6：headless 无 global_script_class_cache → 不写 class_name。
##

const _FireParams := preload("res://scripts/data/building_card_params.gd")
const _PathGeometry := preload("res://scripts/geo/path_geometry.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")
const _Terrain := preload("res://scripts/ui/battlefield_terrain.gd")
const _BattlefieldCamera := preload("res://scripts/ui/battlefield_camera.gd")
const _PlacementTowerData := preload("res://scripts/data/tower_data.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _WD := preload("res://scripts/gameplay/wave_director.gd")   # 仅取 MState 枚举（AGGRO_TOWER）
## 🔴 P0（spec §A.6）：环境换装共享色表（纯静态助手，与 `Battlefield` 共用同款 preload）。
const _EnvPalette := preload("res://scripts/ui/env_palette.gd")
## 档间过渡时长（spec §A.5 / art-bible §2.4：3.0s 缓动，不得突变）。
const ENV_FADE_SEC := 3.0

const MARGIN := 48.0
const C_PATH := Color(0.34, 0.30, 0.22, 1.0)
const C_PATH_DOT := Color(0.55, 0.48, 0.32, 1.0)
const C_CORE := Color(0.35, 0.85, 0.95, 1.0)
const C_SLOT := Color(0.45, 0.50, 0.55, 0.85)
const C_EXPOSE := Color(0.95, 0.30, 0.25, 0.75)
# 🔒 T1 H10 暴露度显式图标（玩法①）：决策期在空塔位标"会挨打/安全"（只标事实，SR-R2）。
const C_EXPOSE_ICON := Color(0.98, 0.32, 0.28, 1.0)   # 暴露位 = 红 X（会挨打）
const C_SAFE_ICON := Color(0.42, 0.82, 0.55, 1.0)     # 安全位 = 绿盾（安全）
# 🔒 T1 肉盾塔可读性（R-T4 余光预警）：战斗态标"正在被仇恨锁定挨打的塔" = 橙色环。
#   与 H10 决策期暴露度图标互补：决策期看"会不会挨打"（红X/绿盾），战斗期看"正在挨打"。
const C_UNDER_ATTACK := Color(1.0, 0.55, 0.20, 0.95)  # 正在挨打 = 橙环（肉盾塔在扛伤）

# 🔒 V-8 肉盾循环 M-1「战斗内被动复活」可读性（GDD mechanics-bulwark-cycle §6.1）
#   🔴 T-E1③ / T-C2 红线：**零数字、零倒计时、零进度条**。
#      只允许两样东西：① 塔体动效（**运动 + 亮度**，余光可读、不依赖色相）；
#      ② 塔底「重启充能」**点亮/熄灭**二态（布尔，不是 "1/1"、不是进度条）。
#   🔴 因此本文件用 `draw_arc` / `draw_circle` 画，🈚 `draw_string`、🈚 Label。
const C_REVIVE_LIT := Color(1.0, 0.86, 0.35, 0.95)    # 充能还在 = 暖金亮点（这座塔还能爬一次）
const C_REVIVE_SPENT := Color(0.30, 0.31, 0.35, 0.55) # 充能用尽 = 熄灭暗点（本波不会再爬）
const C_REVIVE_FLASH := Color(1.0, 0.96, 0.78, 1.0)   # 爬起瞬间 = 高亮扩散环（运动 + 亮度）
## 爬起动效时长（秒）。🔴 它是**事后**演出（塔已经爬起来了才播），不是倒计时 ——
##   玩家无法据此预判任何时刻，不违反 T-E1③「零择时提示」。
const REVIVE_FLASH_SEC := 0.6

# 原型配色 / 半径（占位美术，无玩法含义）
# 🔴 T-P6-06 S4（art-bible §2.1 青橙双极）：PATH 分支**判定为保留**（= 金标本基线渲染路径，
#   `boot.gd` 一行可回退；`run_tests` / 多个 PATH 模式测试仍走它）→ 不删，只**修色**。
#   · Tank 原 `#598CDB`(蓝) 落在"玩家冷色极" → 改**暖色**（敌色系），与 Rush/Swarm 可辨。
const C_RUSH := Color(0.98, 0.45, 0.25, 1.0)
const C_SWARM := Color(0.82, 0.84, 0.88, 1.0)
const C_TANK := Color(0.72, 0.36, 0.16, 1.0)   # 暖（焦铜 #B85C29）—— 原蓝 #598CDB 违反敌我色域
const C_ELITE := Color(1.0, 0.92, 0.25, 1.0)
const R_RUSH := 5.0
const R_SWARM := 6.5
const R_TANK := 10.0

# ===========================================================================
#  🔴 P0 战场可读性 · 正交俯视 2D 落地（blueprint = `docs/phase3/ux-p0p1-spec.md`）
#  ---------------------------------------------------------------------------
#  · 本区块**只在 RADIAL 模式生效**；PATH 模式仍走 `_draw_legacy()`（逐位不变）。
#  · 只读 snapshot 渲染，零玩法写入、零新信号（spec §C.4 零扰动）。
#  · 配色严格取 spec §A.1 表（精确 hex 已换算为 Color）。
# ===========================================================================
# ---- 阵营配色（spec §A.1，精确 hex）----
const P_ALLY := Color(0.243, 0.816, 0.910)        # #3ED0E8 耀青（我方主体）
const P_ALLY_DARK := Color(0.102, 0.420, 0.490)   # #1A6B7D 深青（我方阴影层）
const P_ALLY_2 := Color(0.478, 0.361, 1.000)      # #7A5CFF 星紫（副色/主塔标记）
const P_CORE_HI := Color(0.918, 0.984, 1.000)     # #EAFBFF 核心内芯高光
const P_ENEMY := Color(1.000, 0.420, 0.239)       # #FF6B3D 熔橙（敌方主体）
const P_ENEMY_DARK := Color(0.541, 0.184, 0.110)  # #8A2F1C 焦褐（敌方阴影层/尖刺）
const P_ELITE := Color(0.910, 0.263, 0.498)       # #E8437F 噬品红（精英）
const P_SLOT := Color(0.604, 0.647, 0.694)        # #9AA5B1 钢灰（塔位空槽）
const P_GOLD := Color(1.000, 0.788, 0.290)        # #FFC94A 辉金（积分/合法宿主）
const P_ALERT := Color(1.000, 0.180, 0.306)       # #FF2E4E 警报红（受创/临界）
const P_FIELD := Color(0.137, 0.157, 0.220)       # #232838 场地圆填充
const P_RING := Color(0.106, 0.125, 0.188)        # #1B2030 同心环/放射刻度
const P_BG := Color(0.078, 0.090, 0.149)          # #141726 背景（雾底）
const P_SPAWN_EDGE := Color(0.227, 0.259, 0.341)  # #3A4257 出生环描边
const P_TOWER_EDGE := Color(0.055, 0.141, 0.188)  # #0E2430 塔描边（冷暗）
const P_MON_EDGE := Color(0.180, 0.063, 0.031)    # #2E1008 怪描边（暖暗）

# ---- 形状尺寸（世界单位 u；屏幕 px = u × sc，spec §A.5）----
const U_TOWER := 1.70          # 塔：八边形外接圆
const U_SLOT := 1.50           # 塔位空槽：八边形环
const U_CORE := 1.90           # 核心：最外环
const U_OUTLINE := 0.22        # 描边宽（恒定屏幕 2px @1080p）
const BODY_RUSH := 0.65        # 怪：Rush 细长
const BODY_SWARM := 0.85       # 怪：Swarm 中
const BODY_TANK := 1.30        # 怪：Tank 宽扁
const ELITE_SCALE := 1.35      # 精英体量修饰
const SPIKE_SPREAD := 0.40     # 尖刺扇相邻夹角（rad；spec 未钉值，取定性观感值）
const CONCENTRIC_U: Array = [15.0, 30.0, 45.0]     # 同心环半径 u（spec §A.7）
# 🆕 地图环带边界（u）：焦土 4–16 / 石板 16–30 / 荒原 30–44（`design/gdd/scene-map.md` §5.1）。
#   环带**只是材质**，不是规则；规则由阵地（`BuildGrid.SITES`）承担。
const MAP_BAND_R: Array = [16.0, 30.0, 44.0]
# 🆕 批次⑦：关卡地图地形贴图（`tools/gen_map_terrain_v1.py` 生成，10 张变体各一张）
#   · MAP_TEX_R   贴图覆盖半径（u）—— 与生成器 `R_TEX` 同值，改一处必须改两处；
#   · MAP_TEX_GAIN 灰度→档色的倍率 = 255/G_BAND_MID，与生成器 `G_BAND_MID` 同源：
#     贴图「基准档」烤的是灰度 161（= 生成器 `gr(1.00)`），乘 255/161 后正好还原成 `env.field`。
#   🔴 这两个数与生成器是**跨语言契约**，写死在两边并在
#      `design/art/asset-pack-v4-map-terrain.md` §3 登记；任一侧漂移 → 地形整体偏亮/偏暗。
const MAP_TEX_R := 60.0
const MAP_TEX_GAIN := 255.0 / 161.0
const MAP_TEX_DIR := "res://art/2d/maps/"
var _map_tex_cache: Dictionary = {}
# 确定性 12 边形扰动表（全员共享 → 帧间稳定，杜绝逐帧抖动；spec §A.2.2）
const BLOB_R12: Array = [1.00, 0.88, 1.06, 0.92, 1.02, 0.86, 1.04, 0.95, 1.00, 0.90, 1.05, 0.93]

# ===========================================================================
#  🔴 P0 增强集（第二刀 · spec §A.4 / §A.2.1 增强 / §A.2.3 受创）
#  ---------------------------------------------------------------------------
#  同架构、零扰动：仍**只读** snapshot；新增本地状态全是**纯演出计时器/差分缓存**
#  （与 `_revive_flash` / `_vfx_t` 同性质），不回写玩法、不新增信号（spec §C.4）。
# ===========================================================================
# ---- Rim Light 内发光（spec §A.4）：本体内侧再叠一圈阵营色细弧 ----
#   作用：同屏混乱时分离相邻单位。宽恒定 0.8px（屏幕空间），α 0.6。
const RIM_W := 0.8                                    # 内发光细弧宽（屏幕 px）
const RIM_ALLY := Color(0.243, 0.816, 0.910, 0.6)     # 塔：耀青 #3ED0E8 @α0.6
const RIM_ENEMY := Color(1.000, 0.420, 0.239, 0.6)    # 怪：熔橙 #FF6B3D @α0.6

# ---- 🔴 批次⑥（战场实体贴图化）：sp_* 贴图懒加载 ---------------------------------
##   art/2d/sprites/sp_<name>_v1.png；判空降级回程序化路径（headless / 资产缺失安全）。
##   贴图 = 各实体 draw 代码的**静态部分**逐像素复刻；动效（呼吸/摆动/闪白/状态环）
##   全部保留运行时——「贴图 + 变换」模式，与批次②按钮 modulate 同一渐进纪律。
const SPRITE_DIR := "res://art/2d/sprites/"
var _sprite_cache: Dictionary = {}


func _sprite(n: String) -> Texture2D:
	if _sprite_cache.has(n):
		return _sprite_cache[n]
	var p := SPRITE_DIR + n + "_v1.png"
	var t: Texture2D = null
	if ResourceLoader.exists(p):
		t = load(p)
	_sprite_cache[n] = t
	return t


## 🆕 批次⑦：关卡地图地形贴图（按 map_id 懒加载 + 缓存）。
##   🔴 `_draw` 每帧跑 → 禁止每帧 `exists + load`（与 `_sprite` / `hud._ht` 同一纪律）。
##   文件名把变体 id 的 `-` 换成 `_`（tri-fissure → map_terrain_tri_fissure_v1.png）。
##   判空返回 null → 调用方回落程序化路径（headless / 新变体未出图都安全）。
func _map_tex(map_id: String) -> Texture2D:
	if _map_tex_cache.has(map_id):
		return _map_tex_cache[map_id]
	var p := MAP_TEX_DIR + "map_terrain_" + map_id.replace("-", "_") + "_v1.png"
	var t: Texture2D = null
	if ResourceLoader.exists(p):
		t = load(p)
	_map_tex_cache[map_id] = t
	return t
# ---- 受击闪（spec §A.2.3 受创 / §8.1）：帧间差分触发，本地计时器衰减 ----
const CORE_FLASH_SEC := 0.12      # 核心外环闪 #FF2E4E @α0.8 持续 0.12s
const TOWER_FLASH_SEC := 0.15     # 塔受击一瞬白闪时长（本地演出）
# 塔升级「形态」递进 —— 护角长度上限 0.30u（红线：不超 R + 0.30u，不侵占相邻塔位）。
const TOWER_CORNER_MAX_U := 0.30

# ===========================================================================
#  🔴 体验层第三刀 · 视觉氛围刀（blueprint = `docs/phase3/ux-p0p1c-spec.md`）
#  ---------------------------------------------------------------------------
#  同架构、零扰动：仍**只读** snapshot；新增本地状态**仅**纯演出计时器
#  `_env_tier/_env_prev/_env_t`（环境换装过渡）。核心呼吸**复用既有 `_vfx_t`**、
#  怪摆动**纯由 `pos` 派生** → 均**零新增状态**。零玩法写入、零新信号（spec §C.4）。
# ===========================================================================
# ---- §B.3 怪 squash&stretch 摆动：空间频率（rad/unit，spec §B.3.3）----
const SWAY_K_RHO := 0.50
# ---- §B.2 核心呼吸：幅度 / 周期（盘级；内芯保留其原有更快一层，spec §B.2.2）----
const CORE_BREATH_AMP := 0.025
const CORE_BREATH_SEC := 2.4


var director: Node = null        # WaveDirector
var time_director: Node = null   # TimeDirector（读抽屉宽，决定战场可视宽）
## 🟡 切片8·I-7：商店控制器（读 runtime.snapshot() 画已建塔 + 点选/合法宿主高亮）。
##   🔴 只读，不写玩法状态（与 WaveDirector 一样是"画面事实"来源）。
var controller: Node = null
var placement_backpack: Control = null
var _slot_rows: Array = []
var _snap: Dictionary = {}
## 🔒 V-8：塔位 → 爬起动效**剩余秒数**（纯演出计时器，UI 本地状态）。
##   🔴 不是游戏状态（control-manifest §5 指的是玩法状态）：它只驱动画面衰减，
##      不回写任何玩法数据、不参与任何判定。
var _revive_flash: Dictionary = {}
## 🔴 P0：纯演出相位（驱动核心内芯呼吸等）。与 `_revive_flash` 同性质 ——
##   只是画面计时器，不回写任何玩法数据、不参与任何判定（spec §C.4 第 3 条）。
var _vfx_t: float = 0.0
## 🔴 P0 增强：受击闪演出计时器 + 帧间差分缓存（纯本地画面状态）。
##   `_core_hp_prev` / `_tower_hp_prev` 只是"上一帧读数"，用于检测**下降**；
##   计时器 `_core_flash` / `_tower_flash` 只驱动画面衰减 —— 均不回写玩法、不参与判定。
var _core_hp_prev: float = -1.0
var _core_flash: float = 0.0
var _tower_hp_prev: Dictionary = {}
var _tower_flash: Dictionary = {}
## 🔴 P0（spec §A.5/§A.6）：环境换装过渡计时器（**纯演出本地状态**，与 `_vfx_t` 同性质）。
##   `_env_tier` = 当前目标档；`_env_prev` = 过渡起点档；`_env_t` ∈ [0,1]（1 = 过渡完成）。
##   `-1` = 尚未落位（首帧直接落位，无过渡）。**不回写玩法、不参与任何判定。**
var _env_tier: int = -1
var _env_prev: int = -1
var _env_t: float = 1.0

## 🟠 T-P6-07 C3 几何缓存（静态径向几何按 `(c.x, c.y, sc)` 缓存为折线点；仅在签名变化时重建；`c` 含「视口 × 抽屉」信息、`sc` 覆盖 `rs`）。
##   🔴 纯演出/几何缓存，无玩法含义（与 `_vfx_t` 同性质）。
var _geo_sig: Vector3 = Vector3(-1.0, -1.0, -1.0)   # (c.x, c.y, sc) 签名
var _geo_map_sig: String = ""                        # 🆕 活动地图 id（换图重建缓存）
var _geo: Dictionary = {}

## 🆕 自由摆放：网格线段缓存（世界坐标，构建一次重复用）。
##   `_BuildGrid.grid_edges()` 只在首帧算一次 —— 整盘约 960 格、去重后约 3660 段边。
##   🔴 存**成对扁平数组**而不是 `Array<Array>`：一帧一次 `draw_multiline` 就画完，
##      逐段 `draw_line` 是 3660 次 draw call（改前方格版只有 68 条线才承受得起）。
##   🔴 纯几何缓存，无玩法含义（与 `_geo_sig` 同性质）。
var _grid_edges := PackedVector2Array()
## 🆕 上一份网格是在「阵地化」还是「整盘」口径下算的 —— 切模式（含测试切换）必须重算。
var _grid_sites_mode := false
var _grid_map_id: String = ""
## 网格的屏幕坐标缓存（同一 `(ox, oy, sc, 口径)` 下不重复换算 3660 个点）。签名口径同 `_geo_sig`。
var _grid_scr_sig := Vector4(-1.0, -1.0, -1.0, -1.0)
var _grid_scr := PackedVector2Array()

## 🔴 取证用悬停注入（**不是玩法状态**）：`null` = 跟随真实鼠标（正常游戏）。
##   仅 `tests/probe_placement.gd` 在截图前写入 —— 因为窗口模式下 `warp_mouse`
##   受 DPI / 窗口缩放影响（本工程视口 1920×1080、窗口 1600×900），
##   实测 warp 后 `get_mouse_position()` 落在完全无关的位置，截图会拍到"错的格子"。
##   语义等价于"把鼠标移到这个格上"，只影响 `_draw_placement_marks` 的高亮。
var probe_hover_world = null


func _ready() -> void:
	# 🔴 I-7：点选是商店期交互（安全窗 paused=true 下也要收点击）→ ALWAYS。
	#    本节点仍只读玩法状态、只发意图信号，process_mode 只影响"能否收输入"。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_recompute_slot_rows()


func bind_director(d: Node) -> void:
	director = d
	if d == null:
		return
	# 🔒 V-8：`tower_revived` 是**单向**通知（导演 → 画面）。渲染层只能订阅播动效，
	#   🔴 没有任何反向路径 —— 这是 T-E1 边界二「无玩家战斗内操作/择时」的画面侧保证。
	if not d.is_connected("tower_revived", _on_tower_revived):
		d.tower_revived.connect(_on_tower_revived)
	queue_redraw()


## 🔒 V-8：塔自动爬起 → 记录动效计时（**只写画面状态**）。
func _on_tower_revived(slot: int) -> void:
	_revive_flash[int(slot)] = REVIVE_FLASH_SEC
	queue_redraw()


func bind_time_director(d: Node) -> void:
	time_director = d
	if d == null:
		return
	if not d.is_connected("state_changed", _on_state_changed):
		d.state_changed.connect(_on_state_changed)
	queue_redraw()


## I-7：注入 ShopController（读 runtime 画已建塔 + 点选/合法宿主高亮）。
func bind_controller(c: Node) -> void:
	controller = c
	if c == null:
		return
	if not c.is_connected("shop_changed", _on_shop_run_changed):
		c.shop_changed.connect(_on_shop_run_changed)
	if not c.is_connected("run_changed", _on_shop_run_changed):
		c.run_changed.connect(_on_shop_run_changed)
	queue_redraw()


## state_changed（TimeDirector）携带 (from, to) 两参。
func _on_state_changed(_from: int, _to: int) -> void:
	queue_redraw()


## shop_changed / run_changed（ShopController）为 0 参信号，用无参回调避免参数不匹配报错。
func _on_shop_run_changed() -> void:
	# 🔴 阶段1 八槽：runtime 绑定后按实际 geo 重算暴露度（6/8 槽动态）。
	_recompute_slot_rows()
	queue_redraw()


## 🔴 阶段2 暴露度分派（D-3 定稿 EXPO_SAFE_MAX=0.15）：
##   PATH 模式 → 既有 slot_exposure（d_path ≤ 9 二值，逐位不变，金标本零扰动）。
##   RADIAL 模式 → 径向 slot_exposure_radial（expo_frac ≥ 0.15 二值，D-3 冻结阈值）。
## 🔴 红线：PATH 分支必须与现状逐位相同（金标本不消费暴露度，但 H10 UI 事实层不能变）。
func _recompute_slot_rows() -> void:
	var slots: Array = _slots_arr()
	if _SpaceModel.is_radial():
		_slot_rows = _PathGeometry.slot_exposure_radial(
			slots, _MonsterData.AGGRO_R, _SpaceModel.core_pos(),
			_PathGeometry.expo_safe_max_for(_BuildGrid.sites_active()))
	else:
		_slot_rows = _PathGeometry.slot_exposure(slots, _MonsterData.AGGRO_R)


## 🔴 阶段1 八槽接入：动态取当前槽位几何（6/8 槽）。
##   优先从 runtime.geo.slots 取（八槽时 = Geo8 坐标）；未绑定 runtime 时回退
##   `_Geo6.SLOTS6`（六槽方案 A，逐位不变）。
func _slots_arr() -> Array:
	if controller != null and controller.runtime != null and controller.runtime.geo != null:
		return controller.runtime.geo.slots
	return _Geo6.SLOTS6


func _process(delta: float) -> void:
	# 🔴 P0：演出相位累加（只驱动画面，纯本地状态）。
	var dt := clampf(float(delta), 0.0, 0.1)
	_vfx_t += dt
	# 🔴 P0 增强：受击闪演出计时衰减（纯画面；夹住 dt 防失焦跳变瞬间蒸发）。
	if _core_flash > 0.0:
		_core_flash = maxf(0.0, _core_flash - dt)
	if not _tower_flash.is_empty():
		for slot in _tower_flash.keys():
			var v := float(_tower_flash[slot]) - dt
			if v <= 0.0:
				_tower_flash.erase(slot)
			else:
				_tower_flash[slot] = v
	# 🔒 V-8：爬起动效计时衰减（纯画面）。🔴 夹住 delta：窗口失焦回来的巨大跳变
	#   会让动效瞬间蒸发（也不会卡住 —— 上限 clamp 只影响观感，不影响任何玩法数值）。
	if not _revive_flash.is_empty():
		var d := clampf(float(delta), 0.0, 0.1)
		var done: Array = []
		for slot in _revive_flash:
			var v := float(_revive_flash[slot]) - d
			if v <= 0.0:
				done.append(slot)
			else:
				_revive_flash[slot] = v
		for slot in done:
			_revive_flash.erase(slot)
	if director == null:
		return
	_snap = director.snapshot()
	# 🔴 P0（spec §A.5）：环境换装档位推进（纯演出；只读 `_snap["w"]`）。
	_update_env(dt)
	_detect_hits()
	queue_redraw()


## 🔴 P0 增强：帧间差分检测核心 / 塔**受击**（只读快照；仅写本地演出计时器）。
##   · 核心：`runtime.snapshot()["core_hp"]` 下降 → 外环闪 0.12s。
##   · 塔：`runtime.player.towers[slot].hp` 下降 → 该塔白闪（仅可见塔）。
##   🔴 无稳定怪物 id（第一刀已验证）→ 怪物命中闪**不做**（登记不做项）。
func _detect_hits() -> void:
	if controller == null or controller.runtime == null:
		return
	var rt = controller.runtime
	var chp := float(rt.snapshot().get("core_hp", 0.0))
	if _core_hp_prev >= 0.0 and chp < _core_hp_prev - 0.0001:
		_core_flash = CORE_FLASH_SEC
	_core_hp_prev = chp
	var cur: Dictionary = {}
	for tw in rt.player.towers:
		var s := int(tw.slot)
		var hp := float(tw.hp)
		cur[s] = hp
		var prev := float(_tower_hp_prev.get(s, -1.0))
		if prev >= 0.0 and hp < prev - 0.0001:
			_tower_flash[s] = TOWER_FLASH_SEC
	_tower_hp_prev = cur


# ---------------------------------------------------------------------------
#  坐标映射
# ---------------------------------------------------------------------------
func _field_width() -> float:
	var vw := float(get_viewport().get_visible_rect().size.x)
	var drawer_open := false
	if time_director != null:
		drawer_open = (int(time_director.sm.clock()["drawer"]) != 0)
	return _ShopLayout.battlefield_width(vw, drawer_open)


func _xform() -> Dictionary:
	var vw := _field_width()
	var vh := float(get_viewport().get_visible_rect().size.y)
	if _SpaceModel.uses_terrain():
		return _BattlefieldCamera.terrain_transform(Vector2(vw,vh))
	var x0: float
	var x1: float
	var z0: float
	var z1: float
	if _SpaceModel.mode == _SpaceModel.Mode.RADIAL:
		# 🔴 径向模式：包围盒以居中核心 (28,28) 为中心、容纳整圈出生环 R_s + 余量。
		#   环超出逻辑地图 [0,55] 是"怪物从场外涌入"的表现（草案 §2.3）。
		var core := _SpaceModel.RADIAL_CORE
		var span := float(_SpaceModel.SPAWN_RADIUS) + 3.0
		x0 = core.x - span
		x1 = core.x + span
		z0 = core.y - span
		z1 = core.y + span
	else:
		# PATH 模式：既有包围盒（路径 + 塔位 + 余量），逐位等价基准，一行不改。
		x0 = -3.0
		x1 = 58.0
		z0 = 13.0
		z1 = 51.0
	var ww := x1 - x0
	var wh := z1 - z0
	var sc := minf((vw - 2.0 * MARGIN) / ww, (vh - 2.0 * MARGIN) / wh)
	if sc <= 0.0:
		sc = 1.0
	var ox := (vw - ww * sc) * 0.5 - x0 * sc
	var oy := (vh - wh * sc) * 0.5 - z0 * sc
	return {"sc": sc, "ox": ox, "oy": oy}


func _to_screen(p: Vector2) -> Vector2:
	var t := _xform()
	return Vector2(float(t["ox"]) + p.x * float(t["sc"]), float(t["oy"]) + p.y * float(t["sc"]))


## 世界坐标 → 屏幕坐标（**公开别名**，供同类叠加层复用）。
##   地图与叠加层共用固定的视口坐标映射，商店浮层开关不改变地图位置。
##   两份换算只要漂移一点，叠加层就会和塔身/怪物错位
##      （本项目已踩过"手抄第二份网格数字"的坑）。需要世界坐标的叠加层一律走这里。
func world_to_screen(p: Vector2) -> Vector2:
	return _to_screen(p)


## 当前缩放（屏幕 px / 世界 u）—— 叠加层用它换算"塔身半径 / 字号"的屏幕尺寸。
func world_scale() -> float:
	return float(_xform()["sc"])


## I-7：屏幕坐标 → 世界坐标的逆映射。
##   当前**无调用者**：命中判定改走屏幕距离（`_hit_slot_screen`），比"转世界再比"少一次换算
##   且不受 `sc` 量纲混用影响。保留此函数是因为它是对称 API —— 悬停 tooltip /
##   世界坐标级的手势判定都要用；删掉将来还得原样写回来。
func _to_world(screen_p: Vector2) -> Vector2:
	var t := _xform()
	var sc := float(t["sc"])
	return Vector2((screen_p.x - float(t["ox"])) / sc, (screen_p.y - float(t["oy"])) / sc)


## Public screen-to-world transform for HUD drag placement.
func screen_to_world_position(screen_p: Vector2) -> Vector2:
	return _to_world(screen_p)


## 战场点击 → 只发**意图**信号，由 ShopController 接线（SR-5）。
##   · ⑤ 放置模式：抽屉按 GDD §2.1 **收起**（`drawer = CLOSED`）→ 判**状态机**而不是抽屉。
##     点击位置**吸附到网格格点**后发 `place_at_requested(pos)`；
##     不可落子的格（核心禁建区 / 战场外 / 塔数已满 / 已有别的原型）= **无操作**
##     （取消只认 Esc —— 误点就把玩家踢出放置模式，是最烦人的那种 bug）。
##   · 其余态：仅抽屉展开时可点选已建塔 → `tower_select_requested`。
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if controller == null or controller.runtime == null or time_director == null:
		return

	# ---- ⑤ 放置模式：点地图**任意格**落子（自由摆放）----
	# 🔴 坐标吸附在渲染层先做（它知道 `sc` 与鼠标位置），runtime 会再吸附一次 ——
	#    `snap()` 幂等，重复调用不会漂移，这样探针 / 键盘路径也能直接传裸坐标。
	if _in_placement():
		var wp := _BuildGrid.snap(_to_world(mb.global_position))
		var info: Dictionary = controller.runtime.placement_mode_at(wp)
		var mode := String(info["mode"])
		if mode != "new" and mode != "upgrade":
			return                                   # 不可落子的格不响应，也**不退出**放置模式
		time_director.emit_signal("place_at_requested", wp)
		get_viewport().set_input_as_handled()
		return

	# ---- 其余态：仅抽屉展开（商店期）可点选已建塔 ----
	if int(time_director.sm.clock()["drawer"]) == 0:
		return
	var hit := _hit_slot_screen(mb.global_position, true)
	if hit >= 0:
		# 🔴 发到 `time_director`（信号声明方）。改造前发到 `director`（= WaveDirector），
		#    该信号在 WaveDirector 上不存在 → 点选功能一直静默失效。
		time_director.emit_signal("tower_select_requested", hit)
		get_viewport().set_input_as_handled()


func _in_placement() -> bool:
	if time_director == null or time_director.sm == null:
		return false
	return int(time_director.sm.state) == _TSM.State.PLACEMENT_MODE


## 屏幕像素命中判定：找最近的塔位。
##   `only_built = true` → 只考虑已建塔（I-7 点选）；`false` → 全部塔位（I-8 落子，目标可能是空位）。
## 🔴 必须用**屏幕像素**比距离：`sc` 是"像素/世界单位"（径向 ≈36），
##    旧实现拿 `maxf(9.0, sc * 1.6)` 当**世界**半径 → 实际 300+ px，六个塔位互相串味。
func _hit_slot_screen(screen_p: Vector2, only_built: bool) -> int:
	if controller == null or controller.runtime == null:
		return -1
	var t := _xform()
	var sc := float(t["sc"])
	var hit_r := maxf(22.0, U_SLOT * sc)              # 塔位轮廓半径（像素）+ 少量宽容
	var built: Dictionary = {}
	if only_built:
		for tw in controller.runtime.player.towers:
			built[int(tw.slot)] = true
	var slots: Array = _slots_arr()
	var best := -1
	var best_d := INF
	for s in slots.size():
		if only_built and not built.has(s):
			continue
		var d := screen_p.distance_to(_to_screen(slots[s]))
		if d <= hit_r and d < best_d:
			best = s
			best_d = d
	return best


# ---------------------------------------------------------------------------
#  已建塔渲染（I-7）
# ---------------------------------------------------------------------------
# 塔原型配色（占位，与怪物区分：塔偏青绿系）
# 🔴 T-P6-06 S4：Cannon 原橙 `#F28C4D` 与敌橙 `#FF6B3D` 撞色 → 改**青系**（玩家冷色极）。
const C_TOWER_ARROW := Color(0.40, 0.80, 0.55, 1.0)   # 中性（Arrow）
const C_TOWER_CANNON := Color(0.24, 0.80, 0.88, 1.0)  # fire（Cannon）→ 青 #3DCCE0（原橙 #F28C4D 撞敌色）
const C_TOWER_FROST := Color(0.45, 0.70, 0.95, 1.0)   # frost（Frost）
## 🆕 扩展包两塔（2026-11-06）**不给独立色相** —— 这是刻意的，理由见下。
##   🔴 RADIAL 实机**根本不用本函数**：`_draw_radial_towers` 的塔身是统一 `P_ALLY`（青），
##      原型只走**内形通道**（`_draw_radial_tower_glyph` 的边数 3/4/6/5/7）。
##      本函数只服务 legacy PATH 模式。
##   🔴 为什么不给紫 / 黄：S4 的教训 —— Cannon 原本是橙 `#F28C4D`，与敌橙 `#FF6B3D` 撞色，
##      已改青。玩家塔必须整体待在**冷色极**（青蓝绿）做敌我识别；
##      紫贴近精英品红 `#E8437F`、黄贴近敌橙，都会把「自己的塔」读成「威胁」。
##      ⇒ 新塔沿用既有三塔配色：PATH 下回落到 `C_TOWER_ARROW`（与 Arrow 同色，可接受 —— legacy）。
const C_TOWER_CORE := Color(0.95, 0.85, 0.30, 1.0)    # 主塔描边
const C_SELECT := Color(0.35, 0.95, 0.95, 1.0)        # I-7 选中高亮
const C_HOST := Color(0.95, 0.75, 0.35, 0.9)          # D-TB-6 合法宿主高亮


func _tower_color(ctype: String) -> Color:
	match ctype:
		"Cannon":
			return C_TOWER_CANNON
		"Frost":
			return C_TOWER_FROST
		_:
			# 🔴 扩展塔（Lance / Tesla）刻意走这里 —— 见常量区说明：
			#    RADIAL 不用本函数，PATH 下与 Arrow 同色可接受。
			return C_TOWER_ARROW


## 画已建塔：塔原型色实心 + 层数刻度（h 个小点）+ 主塔描边 + 选中/合法宿主高亮。
func _draw_towers(sc: float) -> void:
	if controller == null or controller.runtime == null:
		return
	var snap: Dictionary = controller.runtime.snapshot()
	# 🔴 snapshot 里塔位列表键是 "slots"（含 ctype/h/empty）；"towers" 是数量 int。
	var towers: Array = snap.get("slots", [])
	var selected: int = int(snap.get("selected_tower_slot", -1))
	var core_slot: int = int(snap.get("core_tower_slot", -1))
	var hosts: Array = _forced_select_hosts(snap)

	for tw in towers:
		if bool(tw.get("empty", true)):
			continue
		var slot: int = int(tw.get("slot", -1))
		if slot < 0 or slot >= _slots_arr().size():
			continue
		var sp := _to_screen(_slots_arr()[slot])
		var h: int = int(tw.get("h", 1))
		var rad := maxf(7.0, sc * 1.1)

		# D-TB-6 合法宿主高亮（在塔身之下，作底圈）
		if hosts.has(slot):
			draw_arc(sp, rad + maxf(4.0, sc * 0.7), 0.0, TAU, 30, C_HOST, maxf(2.0, sc * 0.22), true)
		# 塔身
		draw_circle(sp, rad, _tower_color(String(tw.get("ctype", "Arrow"))))
		# 主塔描边
		if slot == core_slot:
			draw_arc(sp, rad + maxf(1.5, sc * 0.2), 0.0, TAU, 28, C_TOWER_CORE, maxf(1.5, sc * 0.18), true)
		# 选中高亮（最外圈，青）
		if slot == selected:
			draw_arc(sp, rad + maxf(4.0, sc * 0.6), 0.0, TAU, 30, C_SELECT, maxf(2.5, sc * 0.24), true)
		# 🔒 V-8 停机态：塔身压暗（"倒下了"）→ 爬起时由 `_draw_revive_flash` 重新点亮，
		#   形成「压暗 → 高亮扩散环 → 恢复常亮」的**运动 + 亮度**演出（T-C2 / §6.1）。
		#   🟢 T1 反制窗口解耦：门控改挂 `_aggro_ui()`（"挨打事实层"）—— 塔因仇恨停机就压暗，
		#      与"复活档位是否开"无关。🔴 aggro off → 逐像素不变（金标本回归零扰动）。
		if _aggro_ui() and _is_disabled(slot):
			draw_circle(sp, rad, Color(0.06, 0.07, 0.09, 0.62))
			draw_arc(sp, rad, 0.0, TAU, 28, Color(0.55, 0.57, 0.62, 0.55),
				maxf(1.0, sc * 0.10), true)
		# 🔒 V-8 塔底「重启充能」点亮（K 未用 = 亮 / 用尽 = 灭）。🔴 零数字、零文本。
		_draw_revive_charge(sp, slot, rad, sc)
		_draw_fire_charge(sp, slot, rad, sc)
		# 层数刻度（h 个白点，沿塔身底部排开）
		var n := mini(h, 8)
		for k in range(n):
			var ang := PI * (0.25 + 0.5 * float(k) / float(maxi(1, n - 1)))
			var dot := Vector2(sp.x + cos(ang) * rad * 0.5, sp.y + sin(ang) * rad * 0.5)
			draw_circle(dot, maxf(1.2, sc * 0.14), Color(1.0, 1.0, 1.0, 0.9))


## 只读战斗快照：橙色分段环显示充能，爆发环与实际半径一致。
func _draw_fire_charge(center: Vector2, slot: int, radius: float, sc: float) -> void:
	for tw in _snap.get("towers", []):
		if int(tw.get("slot", -1)) != slot or int(tw.get("fire_capacity", 0)) <= 0:
			continue
		var capacity := int(tw["fire_capacity"])
		var charge := int(tw.get("fire_charge", 0))
		for i in range(capacity):
			var angle := -PI * 0.5 + TAU * float(i) / float(capacity)
			var color := Color(1.0, 0.38, 0.12, 1.0) if i < charge else Color(0.45, 0.28, 0.20, 0.65)
			draw_arc(center, radius + 0.9 * sc, angle, angle + TAU * 0.7 / float(capacity), 5, color, maxf(2.0, sc * 0.2), true)


## 火焰层数用十段橙色环表达；只读快照，不在形状层添加文本。
func _draw_fire_stacks(sc: float) -> void:
	var capacity := int(_FireParams.FIRE_EFFECT["max_stacks"])
	for m in _snap.get("monsters", []):
		var stacks := int(m.get("burn_stacks", 0))
		if stacks <= 0 or float(m.get("hp", 0.0)) <= 0.0:
			continue
		var center := _to_screen(m["pos"])
		var r := maxf(8.0, sc * 2.0)
		for i in range(capacity):
			var angle := -PI * 0.5 + TAU * float(i) / float(capacity)
			var col := Color(1.0, 0.42, 0.08, 0.95) if i < stacks else Color(0.45, 0.25, 0.12, 0.35)
			draw_arc(center, r, angle, angle + TAU * 0.65 / float(capacity), 4, col, maxf(1.5, sc * 0.16), true)


## 冰冻：蓝色分段环 = 层数；完整冰晶轮廓 = 完全冻结。
func _draw_frost_states(sc: float) -> void:
	var capacity := int(_FireParams.FROST_EFFECT["max_stacks"])
	for m in _snap.get("monsters", []):
		var stacks := int(m.get("frost_stacks", 0))
		if stacks <= 0 or float(m.get("hp", 0.0)) <= 0.0:
			continue
		var center := _to_screen(m["pos"])
		var radius := maxf(9.0, sc * 2.4)
		if bool(m.get("frozen", false)):
			var crystal := _ngon(center, radius, 6, PI / 6.0)
			draw_colored_polygon(crystal, Color(0.35, 0.8, 1.0, 0.22))
			draw_polyline(_closed(crystal), Color(0.55, 0.9, 1.0, 0.95), maxf(1.5, sc * 0.18), true)
		else:
			for i in range(capacity):
				var angle := -PI * 0.5 + TAU * float(i) / float(capacity)
				var col := Color(0.4, 0.8, 1.0, 0.95) if i < stacks else Color(0.2, 0.4, 0.6, 0.35)
				draw_arc(center, radius, angle, angle + TAU * 0.65 / float(capacity), 4, col, maxf(1.5, sc * 0.16), true)
	for storm in _snap.get("ice_storms", []):
		var center := _to_screen(storm["pos"])
		var phase := 1.0 - float(storm["ttl"]) / 0.6
		var radius := float(storm["radius"]) * sc * clampf(phase * 2.0, 0.05, 1.0)
		draw_circle(center, radius, Color(0.4, 0.8, 1.0, (1.0 - phase) * 0.16))
		draw_arc(center, radius, 0.0, TAU, 48, Color(0.55, 0.9, 1.0, 1.0 - phase), maxf(2.0, sc * 0.28), true)


func _draw_fire_blasts(sc: float) -> void:
	for blast in _snap.get("fire_blasts", []):
		var center := _to_screen(blast["pos"])
		var phase := 1.0 - float(blast["ttl"]) / 0.6
		var r := float(blast["radius"]) * sc * clampf(phase * 2.0, 0.05, 1.0)
		draw_circle(center, r, Color(1.0, 0.30, 0.05, (1.0 - phase) * 0.12))
		draw_arc(center, r, 0.0, TAU, 80, Color(1.0, 0.55, 0.12, 1.0 - phase), maxf(2.0, sc * 0.35), true)


## 🔒 V-8 塔底「重启充能」点亮 —— 回答「这座塔**还能不能再爬一次**」。
##   🟢 表达方式：**一个亮点 / 一个暗点**（二态布尔），零文本、零数字、零进度条。
##   🔴 只在「仇恨开 + 复活档位开」且**战斗态**下画 —— 默认配置下 `_snap["revive_ui"]`
##      恒 false → 本函数零绘制，默认画面与改前**逐像素相同**（金标本回归零扰动）。
##   🔴 不显示 K 余量数字、不显示倒计时、不显示"还有几秒"（T-E1③ / §6.1）。
func _draw_revive_charge(sp: Vector2, slot: int, rad: float, sc: float) -> void:
	if not _revive_on():
		return
	# 仅战斗态（SPAWNING=1 / FIGHTING=2）：波次间不画，避免与商店抽屉互相干扰。
	if not (int(_snap.get("state", 0)) == 1 or int(_snap.get("state", 0)) == 2):
		return
	var lit := bool(_revive_charged().get(slot, false))
	var cr := maxf(1.8, sc * 0.20)
	var cp := Vector2(sp.x, sp.y + rad + maxf(4.5, sc * 0.62))
	if lit:
		draw_circle(cp, cr, C_REVIVE_LIT)
		# 亮度外晕（余光可读；不依赖色相 → 色觉可访问，§6.3）
		draw_arc(cp, cr + maxf(1.2, sc * 0.14), 0.0, TAU, 12,
			Color(C_REVIVE_LIT.r, C_REVIVE_LIT.g, C_REVIVE_LIT.b, 0.45),
			maxf(1.0, sc * 0.10), true)
	else:
		draw_circle(cp, cr, C_REVIVE_SPENT)


## 🔒 V-8 总闸：复活功能是否对**画面**生效（仇恨开 + `repair_on_disable >= 9`）。
##   🔴 默认恒 false → 下面的停机压暗 / 充能点亮 / 爬起动效**全部零绘制**，
##      默认画面与改前**逐像素相同**（金标本回归零扰动）。
func _revive_on() -> bool:
	return bool(_snap.get("revive_ui", false))


## 🟢 T1 反制窗口解耦：停机压暗 = "挨打模式开"这一**事实**的表达，与"复活档位开"解耦。
##   —— 塔因仇恨倒下就该看见它倒下（第五刀 C 轮已上线 aggro；本解耦修复产品可见性缺口：
##      原口径把"停机压暗"绑在 `revive_ui` 上 → aggro 开而复活关时，停机塔与活塔视觉无差别）。
##   🔴 只标事实（这座塔停机了），**不含任何择时读数**（T-E1③ / T-C2）。
func _aggro_ui() -> bool:
	return bool(_snap.get("aggro_ui", false))


## 塔位 → 本波「还能不能再爬一次」（布尔）。数据源 = 导演 snapshot 的每塔
##   `revive_charged`（🔴 布尔，非数字 —— 渲染层拿不到也无法画出任何读数）。
func _revive_charged() -> Dictionary:
	var out: Dictionary = {}
	for t in _snap.get("towers", []):
		out[int(t.get("slot", -1))] = bool(t.get("revive_charged", false))
	return out


## 塔位 → 是否处于停机态（`disabled`）。数据源同为导演 snapshot（只读）。
func _is_disabled(slot: int) -> bool:
	for t in _snap.get("towers", []):
		if int(t.get("slot", -1)) == slot:
			return bool(t.get("disabled", false))
	return false


## 🔒 V-8 塔体**重启动效**：一圈高亮环从塔身向外扩散并变暗（**运动 + 亮度**）。
##   🟢 它播在**爬起之后**（事后演出），不预告任何时刻 → 不构成倒计时/进度条。
##   🟢 不依赖色相（白/暖金的高亮环）→ 色觉可访问（§6.3 第 4 条）。
func _draw_revive_flash(sc: float) -> void:
	if _revive_flash.is_empty():
		return
	for slot in _revive_flash:
		var rem := float(_revive_flash[slot])
		if rem <= 0.0:
			continue
		var s := int(slot)
		if s < 0 or s >= _slots_arr().size():
			continue
		var sp := _to_screen(_slots_arr()[s])
		var p := clampf(rem / REVIVE_FLASH_SEC, 0.0, 1.0)   # 1 → 0（越晚越暗越大）
		var rad := maxf(7.0, sc * 1.1)
		var grow := (1.0 - p) * maxf(15.0, sc * 2.2)
		var col := Color(C_REVIVE_FLASH.r, C_REVIVE_FLASH.g, C_REVIVE_FLASH.b, p)
		draw_arc(sp, rad + grow, 0.0, TAU, 32, col, maxf(2.0, sc * 0.30), true)
		# 塔身一瞬提亮（亮度表达，与"重新点亮"同义）
		draw_circle(sp, rad, Color(1.0, 1.0, 1.0, 0.40 * p))


## D-TB-6：若当前商店焦点位是"需强制点选"的 reinforce 卡，返回其合法宿主塔位；否则空。
##   🔴 只读 runtime 的 offer + get_legal_hosts，不改任何状态。
func _forced_select_hosts(snap: Dictionary) -> Array:
	var offers: Array = snap.get("offers", [])
	var notes: Array = snap.get("notes", [])
	var kinds: Array = snap.get("kinds", [])
	for i in range(mini(offers.size(), notes.size())):
		if String(kinds[i]) == "单塔效果卡" and String(notes[i]) == "选择宿主塔":
			return controller.runtime.get_legal_hosts(String(offers[i]))
	return []


# ---------------------------------------------------------------------------
#  🔒 T1 H10 暴露度显式图标（玩法① · GDD mechanics-tower-life-death §3 玩法①）
#  ---------------------------------------------------------------------------
#  目的：把"这个塔位会不会挨打"从隐含红环升级为**显式可读事实**，让玩家在放塔/保塔
#    决策时一眼看懂 —— 兑现 V-2 定稿"把保塔决策交还玩家"（单核流保塔是 AI 做不到、
#    玩家能做到的事，可行性由暴露度 UI 支撑）。
#  🔴 只标事实（暴露/安全），**不标推荐**（SR-R2：不写"建议放这里"）—— 图标只回答
#    "会/不会挨打"，不回答"该不该放"。
#  显示时机：**决策期**（抽屉展开 = 商店/放置/安全窗，state != COMBAT）；战斗中不显示。
#  图标语义：暴露位（d_path ≤ 9.0）= 红 X「会挨打」；安全位 = 绿盾「安全」。
#  🟢 T1 反制窗口：**空塔位 + 占用塔位**都标（塔信息复用 ⚔/🛡）——占用塔位抬高 + 缩小避免叠图。
func _draw_exposure_icons(sc: float) -> void:
	if time_director == null or time_director.sm == null:
		return
	# 仅决策期（非战斗）显示；战斗中（COMBAT）保持观赏清爽
	if int(time_director.sm.state) == _TSM.State.COMBAT:
		return
	# 占用塔位：**也画**暴露度图标（🟢 T1 反制窗口：塔信息复用 ⚔/🛡，帮助玩家理解
	#   "这座塔为什么上次起来了"）；但偏移塔体上方 + 缩小尺寸，避免与塔身叠图。
	var occupied: Dictionary = {}
	if controller != null and controller.runtime != null:
		for tw in controller.runtime.player.towers:
			occupied[int(tw.slot)] = true
	for row in _slot_rows:
		var slot: int = int(row["slot"])
		var sp: Vector2 = _to_screen(row["pos"])
		var occ := occupied.has(slot)
		# 🔴 空塔位：原偏移/尺寸**逐像素不变**；占用塔位：抬高 + 缩小（避免叠塔身）。
		var icon_r := (maxf(5.0, sc * 0.62) * 0.8) if occ else maxf(5.0, sc * 0.62)
		var ip := Vector2(sp.x, sp.y - (maxf(18.0, sc * 2.4) if occ else maxf(11.0, sc * 1.5)))
		if bool(row["is_exposed"]):
			_draw_cross(ip, icon_r, C_EXPOSE_ICON)     # 暴露 = 红 X（会挨打）
		else:
			_draw_shield(ip, icon_r, C_SAFE_ICON)      # 安全 = 绿盾


## 画"会挨打"图标 = 红 X（两条交叉线，直观表达"此处会被攻击"）。
func _draw_cross(c: Vector2, r: float, col: Color) -> void:
	var d := r * 0.7
	draw_line(Vector2(c.x - d, c.y - d), Vector2(c.x + d, c.y + d), col, maxf(1.6, r * 0.28), true)
	draw_line(Vector2(c.x - d, c.y + d), Vector2(c.x + d, c.y - d), col, maxf(1.6, r * 0.28), true)


## 画"安全"图标 = 绿盾（圆顶 + 方底简化盾形，直观表达"此处挨不到"）。
func _draw_shield(c: Vector2, r: float, col: Color) -> void:
	var top := Vector2(c.x, c.y - r * 0.75)
	var right := Vector2(c.x + r * 0.7, c.y - r * 0.35)
	var br := Vector2(c.x + r * 0.55, c.y + r * 0.6)
	var bottom := Vector2(c.x, c.y + r * 0.95)
	var bl := Vector2(c.x - r * 0.55, c.y + r * 0.6)
	var left := Vector2(c.x - r * 0.7, c.y - r * 0.35)
	var pts: PackedVector2Array = [top, right, br, bottom, bl, left]
	draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.9))
	draw_polyline(pts, col, maxf(1.2, r * 0.2), true)


## 🔒 T1 肉盾塔可读性（R-T4 余光预警 · GDD mechanics-tower-life-death §5 R-T4）：
##   战斗态（有怪锁定塔时）在**正在被仇恨锁定挨打的塔**上标橙环——让玩家余光看懂
##   "哪座塔正在替后排扛伤"（肉盾塔的作用可视化）。
##   🔴 只标事实（正在挨打），不标推荐（SR-R2：不写"该保这座"）。
##   🔴 数据源 = WaveDirector.snapshot() 里 state==AGGRO_TOWER 的怪的 target_slot
##      （怪物锁定塔 → 停下打它，见 wave_director._apply_aggro）。
##   🔴 仅战斗态显示（决策期无怪锁定，_snap 里无 AGGRO_TOWER 怪 → 自然不画）。
##   🔴 MVP 金标本口径（tower_aggro_enabled=false）下无怪进 AGGRO_TOWER → 本函数零绘制，
##      对切片5 冒烟/金标本等价零扰动。
func _draw_under_attack(sc: float) -> void:
	if _snap.is_empty():
		return
	# 收集正在被仇恨锁定的塔位（有怪 state==AGGRO_TOWER 且 target_slot 有效）
	var attacked: Dictionary = {}
	var ms: Array = _snap.get("monsters", [])
	for m in ms:
		if int(m.get("state", 0)) == _WD.MState.AGGRO_TOWER:
			var ts: int = int(m.get("target_slot", -1))
			if ts >= 0:
				attacked[ts] = true
	if attacked.is_empty():
		return
	var ring_r := maxf(8.0, sc * 1.15)
	for slot in attacked:
		if slot < 0 or slot >= _slots_arr().size():
			continue
		var sp := _to_screen(_slots_arr()[slot])
		# 橙色攻击环（在塔身之上，醒目但不遮挡塔体损伤演出）
		draw_arc(sp, ring_r, 0.0, TAU, 32, C_UNDER_ATTACK, maxf(2.0, sc * 0.24), true)


# ---------------------------------------------------------------------------
#  绘制
# ---------------------------------------------------------------------------
func _draw() -> void:
	var t := _xform()
	var sc := float(t["sc"])
	# 🔴 双模分派：RADIAL 走 P0 分层绘制；PATH 走旧口径（逐位不变）。
	if _SpaceModel.mode == _SpaceModel.Mode.RADIAL:
		_draw_radial(sc)
		_draw_frost_states(sc)
		_draw_fire_stacks(sc)
		_draw_fire_blasts(sc)
		return
	_draw_legacy(sc)
	_draw_frost_states(sc)
	_draw_fire_stacks(sc)
	_draw_fire_blasts(sc)


## PATH 模式渲染 —— 🔴 与改前**逐位等价**（含路径/核心/塔位/暴露图标/被攻击环/塔/怪，一行未改）。
func _draw_legacy(sc: float) -> void:
	# ---- 路径 / 出生环 ----
	if _SpaceModel.mode == _SpaceModel.Mode.RADIAL:
		# 🔴 径向模式：路径消失（草案核心特征）。改画出生环（半径 R_s 的围攻圈），
		#   传达"怪物从这一圈涌入"。核心居中 → 环以核心为圆心。
		var ring_c := _to_screen(_SpaceModel.RADIAL_CORE)
		var ring_r := float(_SpaceModel.SPAWN_RADIUS) * sc
		draw_arc(ring_c, ring_r, 0.0, TAU, 96, C_PATH, maxf(2.0, sc * 0.35), true)
	else:
		# PATH 模式：既有 5 段折线 + 6 路径点（逐位等价基准，一行不改）。
		for i in range(_PathGeometry.N_SEG):
			var a := _to_screen(_PathGeometry.PATH[i])
			var b := _to_screen(_PathGeometry.PATH[i + 1])
			draw_line(a, b, C_PATH, maxf(3.0, sc * 0.55), true)
		for i in range(_PathGeometry.PATH.size()):
			draw_circle(_to_screen(_PathGeometry.PATH[i]), maxf(2.0, sc * 0.22), C_PATH_DOT)

	# ---- 核心 ----
	# PATH 模式：路径终点 (55,25)（逐位等价基准）；RADIAL 模式：居中核心 (28,28)。
	#   🔴 跟随 SpaceModel.core_pos() → 径向下核心居中，"塔全堆核心左侧"的视觉取舍消失。
	var cp := _to_screen(_SpaceModel.core_pos())
	var cs := maxf(8.0, sc * 1.6)
	draw_rect(Rect2(cp.x - cs * 0.5, cp.y - cs * 0.5, cs, cs), C_CORE)

	# ---- 塔位（空心圆 + 暴露红环）----
	for row in _slot_rows:
		var p: Vector2 = row["pos"]
		var sp := _to_screen(p)
		draw_arc(sp, maxf(5.0, sc * 0.7), 0.0, TAU, 24, C_SLOT, maxf(1.0, sc * 0.10), true)
		if bool(row["is_exposed"]):
			draw_arc(sp, maxf(7.0, sc * 1.05), 0.0, TAU, 28, C_EXPOSE, maxf(1.0, sc * 0.08), true)

	# ---- 🔒 T1 H10 暴露度显式图标（玩法①）：决策期在**空塔位**标"会挨打/安全" ----
	#    只标事实（暴露/安全），不标推荐（SR-R2）；战斗中（非决策期）不显示，保持观赏清爽。
	_draw_exposure_icons(sc)

	# ---- 🔒 T1 肉盾塔可读性（R-T4）：战斗态在**被仇恨锁定挨打的塔**上标橙环 ----
	#    只标事实（正在挨打），不标推荐（SR-R2）；仅战斗态（有怪锁定塔时）显示。
	_draw_under_attack(sc)

	# ---- 已建塔（I-7：按塔原型上色 + 层数刻度 + 选中/合法宿主高亮）----
	_draw_towers(sc)

	# ---- 🔒 V-8 塔体「重启动效」（画在塔体之上，事后演出 · 运动 + 亮度）----
	_draw_revive_flash(sc)

	# ---- 怪物 ----
	if _snap.is_empty():
		return
	var ms: Array = _snap.get("monsters", [])
	for m in ms:
		var p: Vector2 = m["pos"]
		var sp := _to_screen(p)
		var proto := String(m["proto"])
		var col := C_SWARM
		var rad := R_SWARM
		match proto:
			"Rush":
				col = C_RUSH
				rad = R_RUSH
			"Tank":
				col = C_TANK
				rad = R_TANK
			_:
				col = C_SWARM
				rad = R_SWARM
		rad = maxf(rad, sc * 0.55)
		draw_circle(sp, rad, col)
		if bool(m["elite"]):
			draw_arc(sp, rad + maxf(2.0, sc * 0.18), 0.0, TAU, 24, C_ELITE, maxf(1.5, sc * 0.16), true)


# ===========================================================================
#  P0 · RADIAL 分层绘制（spec §A.6 渲染顺序）
#  ---------------------------------------------------------------------------
#  层0/场地底由父节点 `Battlefield` 承担（bg #141726 + 场地圆 #232838，父先子后）。
#  本层：层1 地面 decal → 层2 出生环 → 层3 全部影 → 层4 塔位层 → 层5 核心 →
#        层6 塔 → 层7 怪 → 层8 投射物 → 层9 VFX。
#  🔴 只读 `_snap` / `controller.runtime.snapshot()`；无任何玩法写入。
# ===========================================================================
func _draw_radial(sc: float) -> void:
	_draw_radial_ground(sc)       # 层1 场地圆 + 同心环×3 + 放射刻度×8 + 层2 出生环
	_draw_all_shadows(sc)         # 层3：先画全部影（避免脏影，spec §A.3/§A.6）
	_draw_radial_slot_layer(sc)   # 层4：空槽八边形 + 威胁楔形 + 被攻击环 + 暴露图标
	_draw_placement_marks(sc, "bg")   # 层4.5：⑤ 自由摆放网格 + 可建区边界（塔之下）
	_draw_radial_core(sc)         # 层5：盘 + 8 刻齿（唯一轮廓）
	_draw_radial_towers(sc)       # 层6：双层八边形塔
	_draw_placement_marks(sc, "fg")   # 层6.5：⑤ 悬停格描边 + 徽标（塔之上）
	_draw_radial_monsters(sc)     # 层7：12 边不规则 + 朝核心尖刺扇
	_draw_structure_attacks(sc)
	_draw_minions(sc)             # 层7.5：召唤小兵（只读快照）
	_draw_projectiles(sc)         # 层8：字段缺失 → 零绘制（保留既有 hook）
	_draw_revive_flash(sc)        # 层9：爬起扩散环（沿用既有）
	# 🟠 T-P6-07 A 档 VFX（弹流/伤害数字/击杀反馈）由**兄弟节点** `VfxLayer` 绘制
	#   （见 `scripts/ui/vfx_layer.gd` 与 `battle_shop.tscn`）——🔴 本文件保持**零文本**
	#   （T-E1③ 源码级守：AC-T1-24「渲染层代码行无 draw_string/Label/phase」）。


# ---- 纯函数工具（spec §A.9；无状态、无随机、帧间稳定）----
func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


func _oct8(c: Vector2, r: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 8:
		pts.append(c + _dir(rot + TAU * float(k) / 8.0) * r)
	return pts


## 正 n 边形顶点（`_oct8` 的推广；供 S5 塔原型内形用）。纯几何、无状态。
func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		pts.append(c + _dir(rot + TAU * float(k) / float(n)) * r)
	return pts


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.is_empty():
		return pts
	var out := pts.duplicate()
	out.append(pts[0])
	return out


## 12 边不规则主体（共享扰动表；`out_dir` 为径向，“长轴/短轴”按 rs/ts 压伸）。
func _blob12(c: Vector2, r: float, out_dir: float, rs: float, ts: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var co := cos(out_dir)
	var si := sin(out_dir)
	for k in 12:
		var a := TAU * float(k) / 12.0
		var v := _dir(a) * (r * float(BLOB_R12[k]))
		var rad_c := (v.x * co + v.y * si) * rs
		var tan_c := (-v.x * si + v.y * co) * ts
		pts.append(c + Vector2(rad_c * co - tan_c * si, rad_c * si + tan_c * co))
	return pts


func _body_units(proto: String, elite: bool) -> float:
	var r := BODY_SWARM
	match proto:
		"Rush":
			r = BODY_RUSH
		"Tank":
			r = BODY_TANK
		_:
			r = BODY_SWARM
	if elite:
		r *= ELITE_SCALE
	return r


## 🔴 P0（spec §A.5 伪码）：环境换装档位推进。跨档边界触发 3s 过渡；首次直接落位（无过渡）。
##   `_snap["w"]` 是本刀**唯一**换装读数来源（只读；无其它字段）。
func _update_env(dt: float) -> void:
	var ti := _EnvPalette.tier_of(int(_snap.get("w", 0)))
	if _env_tier < 0:
		_env_tier = ti
		_env_prev = ti
		_env_t = 1.0
	elif ti != _env_tier:
		_env_prev = _env_tier
		_env_tier = ti
		_env_t = 0.0
	if _env_t < 1.0:
		_env_t = minf(1.0, _env_t + clampf(dt, 0.0, 0.1) / ENV_FADE_SEC)


## 🔴 P0（spec §A.5）：档间过渡取色 —— smoothstep `e(t)=t²(3−2t)` + 线性 RGB `Color.lerp`。
##   `key ∈ {"bg","field","ring"}`；`alpha` 由调用方施加（同心环 0.5 / 放射刻度 0.35）。
func _env_col(key: String, alpha: float) -> Color:
	var a: Color = _EnvPalette.get_color(_env_prev, key)
	var b: Color = _EnvPalette.get_color(_env_tier, key)
	var e := _env_t * _env_t * (3.0 - 2.0 * _env_t)
	var c := a.lerp(b, e)
	return Color(c.r, c.g, c.b, alpha)


## 🔴 P0（spec §B.2.2）：核心**盘级**极小幅呼吸（±2.5% @2.4s）。
##   内芯保留其原有更快一层（±6% @1.6s，见 `_draw_radial_core`）→ 两层不同频叠出有机感。
##   纯 `sin`，零新增状态（复用 `_vfx_t`）。
func _core_breath() -> float:
	return 1.0 + CORE_BREATH_AMP * sin(_vfx_t * TAU / CORE_BREATH_SEC)


# ---- §B.3 怪 squash&stretch 摆动（相位纯由 `pos` 派生 → 帧间稳定、零新增状态）----
## 径向拉伸幅度 A（spec §B.3.3：大原型阻尼递减，小怪更"活蹦"）。
func _sway_amp(proto: String) -> float:
	match proto:
		"Rush":
			return 0.10
		"Tank":
			return 0.04
		_:
			return 0.06      # Swarm（及回退）


## 原型相位偏移 φ_proto（spec §B.3.3：原型间错开，不同类型不同步）。
func _sway_phase(proto: String) -> float:
	match proto:
		"Rush":
			return 0.000
		"Tank":
			return 4.189     # 4π/3
		_:
			return 2.094     # 2π/3（Swarm）


## 体摆动幅 rot_amp（rad；spec §B.3.3）。
func _sway_rot(proto: String) -> float:
	match proto:
		"Rush":
			return 0.18
		"Tank":
			return 0.08
		_:
			return 0.12      # Swarm


## 圆形 blob 软影（双层同心圆近似，spec §A.3；光来自左上 → 影落右下）。
func _blob_shadow(c: Vector2, r: float, off: Vector2, a: float) -> void:
	var p := c + off
	draw_circle(p, r, Color(0.0, 0.0, 0.0, a * 0.35))
	draw_circle(p, r * 0.7, Color(0.0, 0.0, 0.0, a))


## 🔴 P0 增强 · Rim Light 内发光（spec §A.4）：本体内侧 `R − 0.55w` 叠一圈阵营色
##   细弧 —— 塔耀青 / 怪熔橙 @α0.6，宽恒定 0.8px。作用：混乱时分离相邻单位。
##   `w` = 该单位描边宽（屏幕 px）。
func _draw_rim(c: Vector2, r: float, w: float, col: Color) -> void:
	var rr := maxf(1.0, r - 0.55 * w)
	draw_arc(c, rr, 0.0, TAU, 32, col, RIM_W, true)


## 🔴 P0 增强 · 塔升级「形态」递进（spec §A.2.1 增强，**取代**"只堆层数白点"）。
##   约束（红线）：① 严格 8 次旋转对称 —— 所有附加件都落在八边形 8 个顶点/8 等分角；
##   ② 不超出 `R + 0.30u`（不侵占相邻塔位，最近塔间距仅 10.14u）；
##   ③ 零数字/文本（沿用 T-E1③ 口径）；④ 不改塔位坐标/原型语言。
##   递进（落地后一眼可辨「这座比那座强」）：
##     h≥2 内层细环 → h≥3 外圈规整护角×8（长度随等级增长）→
##     h≥5 星紫 `#7A5CFF` 顶点点缀 → h≥8 星紫外环（满级）。
func _draw_tower_form(c: Vector2, R: float, h: int, sc: float) -> void:
	# h≥2 内层细环：**深色**环叠在亮塔身（0.46R）→ 与亮体强对比，一眼可辨"多了一层"。
	if h >= 2:
		draw_arc(c, R * 0.46, 0.0, TAU, 28,
			Color(P_ALLY_DARK.r, P_ALLY_DARK.g, P_ALLY_DARK.b, 0.9),
			maxf(1.2, 0.12 * sc), true)
	# h≥3 外圈规整护角 ×8：**亮色**短三角落在八边形 8 顶点 → 严格 8 重对称、向外可辨。
	if h >= 3:
		var lv := clampf((float(h) - 3.0) / 5.0, 0.0, 1.0)
		var blen := (0.10 + (TOWER_CORNER_MAX_U - 0.10) * lv) * sc   # 0.10u → 0.30u
		var bhalf := 0.13 * sc
		for k in 8:
			var outn := _dir(TAU * float(k) / 8.0)
			var pv := c + outn * R
			var tan := Vector2(-outn.y, outn.x) * bhalf
			draw_colored_polygon(PackedVector2Array([
				pv - tan, pv + tan, pv + outn * blen]), P_ALLY)
	# h≥5 星紫 `#7A5CFF` 顶点点缀（8 重对称）→ 高等级副色标记。
	if h >= 5:
		for k in 8:
			draw_circle(c + _dir(PI / 8.0 + TAU * float(k) / 8.0) * (R * 0.60),
				maxf(1.5, 0.16 * sc), P_ALLY_2)
	# h≥8 星紫外环（满级）。
	if h >= 8:
		draw_arc(c, R + 0.16 * sc, 0.0, TAU, 32, P_ALLY_2, maxf(2.0, 0.20 * sc), true)


# ---- 层1/2：地面 decal + 出生环（spec §A.7；换装见 §A.6）----
func _draw_radial_ground(sc: float) -> void:
	var c := _to_screen(_SpaceModel.RADIAL_CORE)
	if _SpaceModel.uses_terrain():
		_Terrain.draw(self,c,sc)
		return
	var rs := float(_SpaceModel.SPAWN_RADIUS) * sc
	# 🔴 P0（spec §A.6）：场地 / 同心环 / 放射刻度**按档取色 + 3s 过渡**（同 `env_palette.gd`）。
	var col_ring := _env_col("ring", 0.5)     # 同心环 α=0.5（沿用现状，只换 RGB 基底）
	var col_spoke := _env_col("ring", 0.35)   # 放射刻度 α=0.35（同档 ring RGB）
	# 地面由父层绘制；商店浮层不再改变地图几何，无需重复覆盖场地圆。
	# 🟠 T-P6-07 C3（几何缓存 · perf §4）：静态径向几何（同心环×3 / 放射刻度×8 / 出生环+方位刻度）
	#   按 `(c.x, c.y, sc)` 缓存为折线点，仅在签名变化时重建 → 省掉每帧 ~500 顶点的三角重算
	#   （点数与直接 `draw_arc` 同分度数，视觉逐像素一致；缓存**只含几何**，颜色仍每帧取档）。
	var g := _radial_geo(sc, c, rs)
	# 🆕 地图层（scene-map.md §5）：三档材质 → 出怪口土带 → 岩脊 → 阵地。
	#   🔴 画在**同心环/刻度之下**：环是刻度线，压在地形上才是"量尺"，被地形压住就成了噪声。
	_draw_map_layer(sc, c, g)
	var w_ring := maxf(1.0, 0.15 * sc)
	draw_polyline(g["ring0"], col_ring, w_ring, true)   # 同心环 ×3（距离刻度）
	draw_polyline(g["ring1"], col_ring, w_ring, true)
	draw_polyline(g["ring2"], col_ring, w_ring, true)
	for s in g["spokes"]:                                # 放射刻度 ×8（方位锚）
		draw_line(s[0], s[1], col_spoke, maxf(1.0, 0.12 * sc), true)
	# 出生环（边界）+ 方位刻度 —— 🔴 **固定不换色**（spec §A.3 / 用户拍板②）
	draw_polyline(g["spawn"], P_SPAWN_EDGE, maxf(2.0, 0.28 * sc), true)
	for tk in g["ticks"]:
		draw_line(tk[0], tk[1], P_SPAWN_EDGE, maxf(1.5, 0.22 * sc), true)


## 抽屉是否展开（只读 TimeDirector；`_field_width()` 同源）。
func _drawer_open() -> bool:
	if time_director == null or time_director.sm == null:
		return false
	return int(time_director.sm.clock()["drawer"]) != 0


# ---- 地图层「三裂环」（scene-map.md §5）----
## 🔴 为什么地图要先于环/刻度画：环是**量尺**，量尺压在地形上才成立；
##   反过来地形压住环，玩家读到的是"地上有几段断掉的线"，不是"这个圈有 30u 远"。
##
## 三层信息，按"谁能站"排序（P-M3 一眼读懂，零文本）：
##   ① 三档材质 —— 明度阶梯（×1.18 / ×1.00 / ×0.84）⇒ 越靠核心越烫，不用标数字；
##   ② 出怪口   —— 熔橙低α土带 + 端头石柱 ⇒ "怪从这里进来"，且**只有三段**；
##   ③ 岩脊/阵地 —— 深色体块（不可建）vs 青色薄台（可建）⇒ "石头 vs 台子"的材质对立。
##
## 🔴 三档材质的颜色由**当前环境档基色**派生（不是写死 hex）：否则换装到 T2/T3 时
##   地形会与场地圆脱色，看起来像贴图没加载。
##
## 🆕 批次⑦（关卡地图地形贴图 · asset-pack v4）：三档材质 + 岩脊体块改为**位图**
##   （`art/2d/maps/map_terrain_<map_id>_v1.png`，见 `design/art/asset-pack-v4-map-terrain.md`）。
##   贴图是**灰度值图**，运行时乘 `field × MAP_TEX_GAIN`（= 255/161）还原：
##     · 灰度 134（外环 荒原）= field ×0.84 · 灰度 161（中环 石板）= field ×1.00
##       · 灰度 190（内环 焦土）= field ×1.18   ← 三档阶梯与改前逐位同源
##     · 岩脊 = 断崖裂缝：谷底灰度 90（×0.56）+ 崖唇高光灰度 255（×1.58，全场最亮地形元素）
##   ⇒ 4 档环境换装**自动跟随**（乘法与档位无关）；只有崖唇高光（灰度 255 = ×1.58）比底色亮。
##   🔴 判空降级：贴图缺失（headless / 资产被删 / 新加变体未出图）→ 逐字回落
##     原来的「三个 draw_circle + 岩脊多边形」路径，画面与改前逐位一致。
func _draw_map_layer(sc: float, c: Vector2, g: Dictionary) -> void:
	if not _SpaceModel.layout_enabled:
		return
	var base := _env_col("field", 1.0)
	var inner := Color(minf(base.r * 1.18, 1.0), minf(base.g * 1.18, 1.0),
		minf(base.b * 1.16, 1.0), 1.0)
	var outer := Color(base.r * 0.84, base.g * 0.84, base.b * 0.86, 1.0)
	var tex := _map_tex(_SpaceModel.active_map_id)
	if tex != null:
		# 贴图已烘焙「基准档 = 灰度 216」，故调制色 = field × (255/216)，内/外环由灰度自带
		var tint := Color(minf(base.r * MAP_TEX_GAIN, 1.0), minf(base.g * MAP_TEX_GAIN, 1.0),
			minf(base.b * MAP_TEX_GAIN, 1.0), 1.0)
		var rt := MAP_TEX_R * sc
		draw_texture_rect(tex, Rect2(c - Vector2(rt, rt), Vector2(rt * 2.0, rt * 2.0)), false, tint)
	else:
		draw_circle(c, float(MAP_BAND_R[2]) * sc, outer)
		draw_circle(c, float(MAP_BAND_R[1]) * sc, base)
		draw_circle(c, float(MAP_BAND_R[0]) * sc, inner)

	# ② 出怪口：磨损土带 + 端头石柱（熔橙低α = "地面被踩秃"，不是"发光路径"）
	var dirt := Color(P_ENEMY.r, P_ENEMY.g, P_ENEMY.b, 0.085)
	var post := Color(P_ENEMY.r, P_ENEMY.g, P_ENEMY.b, 0.32)
	var rs := float(_SpaceModel.SPAWN_RADIUS)
	for arc in _SpaceModel.active_spawn_arcs():
		var a0 := deg_to_rad(float(arc["a0"]))
		var a1 := deg_to_rad(float(arc["a1"]))
		draw_arc(c, (rs - 3.0) * sc, a0, a1,
			maxi(10, int((a1 - a0) * 12.0)), dirt, maxf(3.0, 1.8 * sc), true)
		for a in [a0, a1]:
			draw_line(c + _dir(a) * (rs - 6.0) * sc, c + _dir(a) * (rs - 1.0) * sc,
				post, maxf(2.0, 0.55 * sc), true)

	# ③ 岩脊：贴图生效时**已烘焙**（谷底 / 贴壁暗边 / 受光唇线 / 崖口碎石 / 落影）
	#   → 这里一行不画。🔴 也不要再描逻辑扇区边：烘焙轮廓是锯齿的（±0.45u），
	#   描在扇区上的亮线会有一段露在岩体外，读成"石头里埋了根亮线"（首版实测）。
	#   贴图缺失 → 回落原来的「深色多边形 + α0.75 冷描边」，与改前逐位一致。
	if tex == null:
		for poly in g.get("ridges", []):
			draw_colored_polygon(poly, Color(0.055, 0.063, 0.098, 0.94))
			draw_polyline(_closed(poly), Color(P_SPAWN_EDGE.r, P_SPAWN_EDGE.g, P_SPAWN_EDGE.b, 0.75),
				maxf(1.5, 0.12 * sc), true)

	# ④ 阵地薄台：**不再常驻绘制**（2026-11-09）。
	#   阵地已不限制摆塔；常驻的 17 个六边形会让玩家误以为"只有这些格子能建"。
	#   摆塔网格只在放置模式下画（`_draw_placement_marks`），平时战场上不出现格线。


## 环扇形（弧带）多边形：外弧正向 + 内弧反向 ⇒ 一个简单多边形（可直接三角化填充）。
##   用于岩脊：`a0/a1` 已按视觉 `pad` 内收（逻辑遮挡角比视觉宽 2°/边，给怪留路肩）。
func _sector_poly(c: Vector2, r0: float, r1: float, a0: float, a1: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(seg + 1):
		var a := a0 + (a1 - a0) * float(i) / float(seg)
		out.append(c + _dir(a) * r1)
	for i in range(seg + 1):
		var a := a1 + (a0 - a1) * float(i) / float(seg)
		out.append(c + _dir(a) * r0)
	return out


## 🟠 T-P6-07 C3：静态径向几何缓存（按 `(c.x, c.y, sc)` 签名；仅变化时重建）。
##   🔴 VFX-C3-01 修复（quality-lead `docs/phase6/vfx-verify.md`）：键**必须含几何中心的依赖**。
##   几何完全由 `(c, rs)` 决定，`rs = SPAWN_RADIUS · sc`；而 `c.x = _field_width()/2` **含「抽屉」维**
##   —— 抽屉展开使战场宽变窄 → `c.x` 左移，但 **1920×1080（高度受限）下 `sc` 逐位不变**
##   → 旧键 `Vector3(sc, vs.x, vs.y)` 漏了 `c.x` ⇒ 抽屉开合时缓存不失效 ⇒ 地面几何（环×3 /
##   放射刻度 / 出生环 / 方位刻度）**错位整局**。⇒ 键改 `(c.x, c.y, sc)`：`c` 已含视口 + 抽屉信息，
##   `sc` 覆盖 `rs`。守卫见 `tests/run_vfx_cache_guard.gd`（已入 `run_tests -- radial8`）。
func _radial_geo(sc: float, c: Vector2, rs: float) -> Dictionary:
	# 🆕 换图：缓存签名加入 active_map_id —— 地图几何由 (c, sc, map_id) 完全决定，
	#    换图不重建缓存会让岩脊/阵地继续画上一张图（错位整局）。
	var sig := Vector3(c.x, c.y, sc)
	var map_sig: String = _SpaceModel.active_map_id
	if sig != _geo_sig or map_sig != _geo_map_sig:
		_geo_sig = sig
		_geo_map_sig = map_sig
		var rings: Array = []
		for ru in CONCENTRIC_U:
			rings.append(_circle_pts(c, float(ru) * sc, 128))
		var spokes: Array = []
		var ticks: Array = []
		for k in 8:
			var a := TAU * float(k) / 8.0
			spokes.append([c, c + _dir(a) * rs])
			ticks.append([c + _dir(a) * (rs - 0.8 * sc), c + _dir(a) * (rs + 0.8 * sc)])
		# 🆕 地图几何（岩脊）：与环同一份缓存 —— 同由 `(c, sc)` 完全决定。
		#   🔴 世界→屏幕的换算自己算（`ox = c.x − core.x·sc`），不调 `_to_screen()`：
		#      后者每次重跑 `_xform()`，在缓存重建里调 17×7 次纯属浪费。
		#   🔴 2026-11-09：阵地「薄台」不再绘制 —— 阵地不限制摆塔后，常驻的 17 个六边形
		#      会被读成"只有这 17 格能建"的网格。网格改为**只在放置模式**由
		#      `_draw_placement_marks()` 画（见 `build_grid.gd` 文件头口径③）。
		var ridges: Array = []
		if _SpaceModel.layout_enabled:
			for rg in _SpaceModel.active_ridges():
				var vpad := float(rg.get("pad", 0.0))
				ridges.append(_sector_poly(c, float(rg["r0"]) * sc, float(rg["r1"]) * sc,
					deg_to_rad(float(rg["a0"]) + vpad), deg_to_rad(float(rg["a1"]) - vpad), 12))
		_geo = {"ring0": rings[0], "ring1": rings[1], "ring2": rings[2],
			"spawn": _circle_pts(c, rs, 160), "spokes": spokes, "ticks": ticks,
			"ridges": ridges}
	return _geo


## 建筑攻防的只读演出：攻击方向、核心受攻环，以及受损防御塔的生命条。
func _draw_structure_attacks(sc: float) -> void:
	if not bool(_snap.get("structure_attacks",false)):
		return
	var slots := _slots_arr()
	var core_attacked := false
	for monster in _snap.get("monsters",[]):
		if float(monster.get("hp",0.0))<=0.0 or bool(monster.get("frozen",false)):
			continue
		var state := int(monster.get("state",0))
		var target: Vector2
		if state==_WD.MState.AGGRO_CORE:
			target = _SpaceModel.core_pos()
			core_attacked = true
		elif state==_WD.MState.AGGRO_TOWER:
			var slot := int(monster.get("target_slot",-1))
			if slot<0 or slot>=slots.size():
				continue
			target = slots[slot]
		else:
			continue
		var phase := fposmod(_vfx_t*1.8+float(monster.get("index",0))*0.17,1.0)
		if phase>0.35:
			continue
		var source: Vector2 = monster["pos"]
		var a := _to_screen(source.lerp(target,0.25))
		var b := _to_screen(source.lerp(target,0.85))
		draw_line(a,b,Color(P_ENEMY,0.80*(1.0-phase/0.35)),maxf(2.0,0.16*sc),true)
	if core_attacked:
		draw_arc(_to_screen(_SpaceModel.core_pos()),3.3*sc,0.0,TAU,48,Color(P_ENEMY,0.75),2.0,true)
	for tower in _snap.get("towers",[]):
		var hp := float(tower.get("hp",0.0))
		var maximum := float(tower.get("hp_max",0.0))
		var slot := int(tower.get("slot",-1))
		if maximum<=0.0 or hp>=maximum or slot<0 or slot>=slots.size():
			continue
		var center := _to_screen(slots[slot])+Vector2(0.0,3.0*sc)
		var width := maxf(26.0,4.8*sc)
		var rect := Rect2(center-Vector2(width*0.5,0.0),Vector2(width,4.0))
		draw_rect(rect,Color(0.02,0.03,0.05,0.95))
		draw_rect(Rect2(rect.position,Vector2(width*clampf(hp/maximum,0.0,1.0),4.0)),P_ENEMY)


func _circle_pts(c: Vector2, r: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(seg + 1):
		pts.append(c + _dir(TAU * float(i) / float(seg)) * r)
	return pts


# ---- 层3：全单位投影（先画全部影，再画全部本体）----
func _draw_all_shadows(sc: float) -> void:
	# 核心影（🔴 P0 §B.2.3：半径随盘呼吸**同步缩放** → 避免"影浮于盘外"）
	_blob_shadow(_to_screen(_SpaceModel.core_pos()), 1.15 * U_CORE * sc * _core_breath(),
		Vector2(0.10, 0.16) * sc, 0.40)
	# 塔影（越高影越远）
	if controller != null and controller.runtime != null:
		var slots: Array = _slots_arr()
		var sn: Array = controller.runtime.snapshot().get("slots", [])
		for tw in sn:
			if bool(tw.get("empty", true)):
				continue
			var si := int(tw.get("slot", -1))
			if si < 0 or si >= slots.size():
				continue
			_blob_shadow(_to_screen(slots[si]), 1.20 * U_TOWER * sc,
				Vector2(0.26, 0.34) * sc, 0.36)
	# 怪影（精英偏移更大 = 体量更高的线索）
	var ms: Array = _snap.get("monsters", [])
	for m in ms:
		var pos: Vector2 = m["pos"]
		var elite := bool(m.get("elite", false))
		var ru := _body_units(String(m["proto"]), elite)
		var off := Vector2(0.20, 0.28) * sc if elite else Vector2(0.14, 0.20) * sc
		_blob_shadow(_to_screen(pos), 1.15 * ru * sc, off, 0.32 if elite else 0.28)


# ---- 层4：塔位层 ----
func _draw_radial_slot_layer(sc: float) -> void:
	_draw_threat_wedges(sc)
	var occupied: Dictionary = {}
	# 🆕 自由摆放：没有「虚位以待的空塔位」这回事 —— 槽位表只记已建塔的位置
	#   （拆塔会留下空槽，但那是历史痕迹，不该画成"这里可以建塔"）。
	var free_place := false
	if controller != null and controller.runtime != null:
		for tw in controller.runtime.player.towers:
			occupied[int(tw.slot)] = true
		free_place = bool(controller.runtime.free_placement)
	for row in _slot_rows:
		var slot: int = int(row["slot"])
		if occupied.has(slot):
			continue
		if free_place:
			continue                     # 自由摆放：不画空槽八边形（网格负责表达"哪里能建"）
		var sp := _to_screen(row["pos"])
		draw_polyline(_closed(_oct8(sp, U_SLOT * sc, PI / 8.0)),
			Color(P_SLOT.r, P_SLOT.g, P_SLOT.b, 0.85), maxf(1.0, 0.12 * sc), true)
	_draw_under_attack(sc)
	_draw_exposure_icons(sc)


## ---- 层4.5：自由摆放网格 + 落子标记（仅 ⑤ 态绘制）----
##
## 🔴 为什么必须有网格：改造前塔只能落在 6 个固定点，每个点自带八边形轮廓 →
##    玩家"看得见也点得到"。改成自由摆塔后，如果只画一片空地，玩家无法判断
##    "点哪里才算一格、哪里算建成了" —— 网格是把「自由」变成「可操作」的界面，
##    不是装饰。它同时承担三件事：可建区边界、格点吸附的视觉反馈、落子结果预览。
##
## 🆕 网格形状 = **正六边形蜂窝**（玩家要求从方格改过来）。理由见 `build_grid.gd` 文件头：
##    方格到 4 个斜角邻格的距离是 1.414a，塔阵会自发退化成对角条纹；六边形 6 邻格等距。
##
## 视觉两层（由弱到强，不抢战场戏）：
##   ① 网格线     α 0.11 —— 只暗示"这里有刻度"；**非可建格（岩脊/核心）不铺线**
##   ② 悬停格     六边形描边 + 呼吸 + 徽标 —— 回答"我点下去会怎样"
## 🔴 网格**只在放置模式**出现（`_in_placement()` 早退）—— 平时战场干净，不显示格线。
##
## 🔴 只对**鼠标所指那一格**查落子模式（O(塔数)），不遍历全盘 ~960 格。
## 🔴 零文本（AC-T1-24）：＋ / ↑ 全部 `draw_line` 画，不写 `draw_string`。
##
## 🆕 `phase` 两段式（同一个函数，两个绘制时机）：
##   · "bg"（默认）= 网格 + 可建区边界，在**塔之下**调用 —— 否则网格线横穿塔身。
##   · "fg"        = 悬停格描边 + 徽标，在**塔之上**调用 —— 升级态要圈住已有的塔，
##                   画在塔下面会被塔身整块盖住，玩家看不出"这一格可以升级"
##                   （实测截图取证确认过，不是推测）。
func _draw_placement_marks(sc: float, phase: String = "bg") -> void:
	if not _in_placement():
		return
	if controller == null or controller.runtime == null:
		return

	# ---- ① 网格线（正六边形蜂窝）----
	# 🔴 一次 `draw_multiline` 画完 ~3660 段边（逐段 draw_line 是不可接受的调用量）；
	#    屏幕坐标按 (ox, oy, sc) 缓存 —— 抽屉开合会改 `_field_width()` → 战场重新居中，
	#    签名一变必须重算，否则网格会和塔身错位（本项目踩过手抄坐标的坑）。
	var map_cache_key := _SpaceModel.active_map_id + (":terrain" if _SpaceModel.uses_terrain() else "")
	if (_grid_edges.is_empty() or _grid_sites_mode != _BuildGrid.sites_active()
			or _grid_map_id != map_cache_key):
		_grid_sites_mode = _BuildGrid.sites_active()
		_grid_map_id = map_cache_key
		_grid_edges = _BuildGrid.grid_edges()
		_grid_scr_sig = Vector4(-1.0, -1.0, -1.0, -1.0)
	var xf := _xform()
	var ox := float(xf["ox"])
	var oy := float(xf["oy"])
	var sig := Vector4(ox, oy, sc, 1.0 if _grid_sites_mode else 0.0)
	if sig != _grid_scr_sig:
		_grid_scr_sig = sig
		_grid_scr.resize(_grid_edges.size())
		for i in range(_grid_edges.size()):
			var v: Vector2 = _grid_edges[i]
			_grid_scr[i] = Vector2(ox + v.x * sc, oy + v.y * sc)
	if not _grid_scr.is_empty():
		var g_lw := maxf(1.0, 0.045 * sc)
		var g_col := Color(P_ALLY.r, P_ALLY.g, P_ALLY.b, 0.11)
		draw_multiline(_grid_scr, g_col, g_lw, true)

	# ---- ② 可建区边界 + 核心禁建区 ----
	var core := _to_screen(_BuildGrid.core())
	# 🔴 2026-11-09：可建区 = 出生环以内整盘，网格外沿本身就是边界（`grid_edges()` 已裁到
	#   `FIELD_R = 55 = 出生环`）→ 不再额外画一圈与出生环重叠的实线。
	#   岩脊障碍不铺网格（`buildable()` 过滤）—— "没有格线的地方就是石头/核心"。
	draw_circle(core, _BuildGrid.CORE_BAN_R * sc, Color(0.020, 0.030, 0.060, 0.60))
	draw_arc(core, _BuildGrid.CORE_BAN_R * sc, 0.0, TAU, 48,
		Color(P_ALERT.r, P_ALERT.g, P_ALERT.b, 0.45), maxf(1.5, 0.09 * sc), true)

	if phase == "bg":
		_draw_placement_range(sc)
		return                      # 背景段到此为止（塔之上还要再调一次 fg 段）

	# ---- ③ 悬停格预览 ----
	# 鼠标在商店浮层 / HUD 上时不高亮；命中区域与地图坐标映射分开。
	var hovered = _placement_hover_world()
	if hovered == null:
		return
	var wp: Vector2 = hovered
	var info: Dictionary = controller.runtime.placement_mode_at(wp)
	var mode := String(info["mode"])
	if mode == "":
		return
	var cellc := _BuildGrid.snap(wp)          # 吸附后的**世界格心**（六边形轮廓要它，不是鼠标点）
	var c := _to_screen(cellc)
	var pulse := 1.0 + 0.10 * sin(_vfx_t * TAU / 0.9)
	var col: Color
	var live := true                       # 这一格现在点下去会不会落子
	match mode:
		"new":
			col = P_ALLY                   # 耀青：可新建
		"upgrade":
			col = P_GOLD                   # 辉金：可升级（同格同原型）
		"blocked":
			col = Color(P_SLOT.r, P_SLOT.g, P_SLOT.b, 0.55)   # 钢灰：几何不可建
			live = false
		_:
			col = Color(P_SLOT.r, P_SLOT.g, P_SLOT.b, 0.40)   # 钢灰：塔数满 / 已有别的塔
			live = false
	# 高亮形状 = **这一格的六边形本身**（不是屏幕对齐的方框）。
	# 🔴 为什么必须跟着格子形状走：方框在对角方向会超出格界（把邻格也罩住），
	#    玩家看到的高亮范围和 `cell_of()` 的判定范围就对不上 —— 正是"看到能建、点下去不能建"的成因。
	var hex := PackedVector2Array()          # 开口（给三角化填充）
	var ring := PackedVector2Array()         # 闭合（给描边）
	for v in _BuildGrid.corners(cellc):
		var sv := _to_screen(v)
		hex.append(sv)
		ring.append(sv)
	ring.append(ring[0])
	if mode == "upgrade":
		# 升级态只描边不填充 —— 填充会把塔身整块染色，看不清原来那座塔是什么。
		draw_polyline(ring, col, maxf(3.0, 0.16 * sc), true)
	else:
		draw_colored_polygon(hex, Color(col.r, col.g, col.b, 0.26 if live else 0.10))
		draw_polyline(ring, col, maxf(2.0, 0.12 * sc), true)
	# 徽标：格子正上方（不压塔身），暗盘衬底保证深底 / 亮塔上都可读。
	#   偏移按六边形的**半高**（边心距）算 —— 用半宽会顶到邻格里去。
	if live:
		var br := _BuildGrid.HEX_R * 0.58 * pulse * sc
		_draw_place_badge(c + Vector2(0.0, -(_BuildGrid.HEX_HALF_H * sc + br * 1.30)), br, mode, col, sc)


## 放置预览与最终落子共用吸附坐标；鼠标回到背包或控件时不在地图上残留预览。
func _placement_hover_world(screen_point = null):
	if probe_hover_world != null:
		return _BuildGrid.snap(Vector2(probe_hover_world))
	var pointer: Vector2 = get_viewport().get_mouse_position() if screen_point == null else Vector2(screen_point)
	if placement_backpack != null and placement_backpack.is_visible_in_tree() and placement_backpack.get_global_rect().has_point(pointer):
		return null
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return null
	return _BuildGrid.snap(_to_world(pointer))


## 纯预览数据：射程读取战斗同一参数，中心为实际吸附落点。
func placement_range_preview() -> Dictionary:
	if not _in_placement() or controller == null or controller.runtime == null:
		return {}
	var name: String = controller.runtime.placing_card_name()
	if name == "" or _PlacementTowerData.tower_dps(name)<=0.0:
		return {}
	var radius := _PlacementTowerData.tower_rng(name)
	var point = _placement_hover_world()
	if radius<=0.0 or point == null:
		return {}
	var mode: String = controller.runtime.placement_mode_at(point)["mode"]
	return {"center":point,"radius":radius,"mode":mode,"valid":mode in ["new","upgrade"]}


func _draw_placement_range(sc: float) -> void:
	var preview := placement_range_preview()
	if preview.is_empty():
		return
	var center := _to_screen(preview["center"])
	var radius := float(preview["radius"])*sc
	var color := P_GOLD if String(preview["mode"])=="upgrade" else P_ALLY
	if not bool(preview["valid"]):
		color = P_ALERT
	draw_circle(center,radius,Color(color,0.07 if bool(preview["valid"]) else 0.025))
	draw_arc(center,radius,0.0,TAU,128,Color(color,0.80),2.0,true)
	# 四侧短刻度使边界在地面和网格上都容易辨认。
	for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		draw_line(center+direction*(radius-4.0),center+direction*(radius+4.0),Color(color,0.95),2.0,true)


## 落子徽标：圆盘衬底 + 几何符号（零文本）。`mode` ∈ {new, upgrade, invalid}。
func _draw_place_badge(c: Vector2, r: float, mode: String, col: Color, sc: float) -> void:
	draw_circle(c, r, Color(0.035, 0.045, 0.085, 0.90))
	draw_arc(c, r, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.95), maxf(1.0, 0.10 * sc), true)
	var k := r * 0.56
	# 🔴 线宽按 `sc` 走：1600×900 实机上 1.5px 的 ＋ 根本认不出（实测截图裁切放大才看见）。
	var lw := maxf(2.0, 0.16 * sc)
	match mode:
		"new":
			draw_line(c + Vector2(-k, 0.0), c + Vector2(k, 0.0), col, lw, true)
			draw_line(c + Vector2(0.0, -k), c + Vector2(0.0, k), col, lw, true)
		"upgrade":
			draw_line(c + Vector2(0.0, k), c + Vector2(0.0, -k), col, lw, true)
			draw_line(c + Vector2(0.0, -k), c + Vector2(-k * 0.72, -k * 0.10), col, lw, true)
			draw_line(c + Vector2(0.0, -k), c + Vector2(k * 0.72, -k * 0.10), col, lw, true)
		_:
			var d := k * 0.80
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), col, lw, true)
			draw_line(c + Vector2(d, -d), c + Vector2(-d, d), col, lw, true)


## 威胁方位楔形（spec §A.2.4 / **§B.1.3 扇区去重版**）：只标"哪个方位有怪"这一事实
##   （不标推荐，SR-R2）。把 N 只怪的方位**吸附到 8 个 45° 扇区**，每扇区只画 1 段弧，
##   α 随该扇区怪数递增（怪越多越亮，"这方位压力大"余光可读）→ 修掉"糊成一片" + **净减** draw call。
##   🔴 **≤ 8 段 `draw_arc`**（由 ≤N 降为 ≤8）；只用现有 `monsters[].pos`，无需新字段。
func _draw_threat_wedges(sc: float) -> void:
	var ms: Array = _snap.get("monsters", [])
	if ms.is_empty():
		return
	var core := _SpaceModel.RADIAL_CORE
	var c := _to_screen(core)
	var rs := float(_SpaceModel.SPAWN_RADIUS) * sc
	var sect: Dictionary = {}                      # idx(0..7) -> count
	for m in ms:
		var pos: Vector2 = m["pos"]
		var a := atan2(pos.y - core.y, pos.x - core.x)
		var idx := int(floor(fposmod(a, TAU) / (TAU / 8.0)))
		sect[idx] = int(sect.get(idx, 0)) + 1
	for idx in sect:
		var ac := TAU * float(idx) / 8.0 + TAU / 16.0     # 扇区中心
		var alpha := minf(0.60, 0.35 + 0.05 * float(mini(int(sect[idx]), 5)))
		if _SpaceModel.uses_terrain():
			var edge := PackedVector2Array()
			for k in range(9):
				var angle := ac+lerpf(-deg_to_rad(11.0),deg_to_rad(11.0),float(k)/8.0)
				var radius := _SpaceModel.BattlefieldMaps.entry_radius(_SpaceModel.active_map_id,angle)
				edge.append(c+Vector2.from_angle(angle)*radius*sc)
			draw_polyline(edge,Color(P_ENEMY,alpha),maxf(2.0,0.3*sc),true)
			continue
		draw_arc(c, rs, ac - deg_to_rad(11.0), ac + deg_to_rad(11.0), 8,
			Color(P_ENEMY.r, P_ENEMY.g, P_ENEMY.b, alpha), maxf(2.0, 0.30 * sc), true)


# ---- 层5：核心（盘 + 8 刻齿，全场唯一轮廓）----
func _draw_radial_core(sc: float) -> void:
	var c := _to_screen(_SpaceModel.core_pos())
	# 🔴 P0（spec §B.2.2）：**盘级**呼吸 ±2.5% @2.4s —— 外环/中盘/刻齿/描边/受击闪整体随缩。
	var rc := U_CORE * sc * _core_breath()
	# 🔴 批次⑥：核心盘贴图（外环+中盘+刻齿+外描边烘焙，半边 2.2u），盘级呼吸走缩放；
	#    缺失降级回程序化。内芯**第二频率**心跳保留运行时（贴图烘焙不了两层不同频）。
	var core_tex := _sprite("sp_core")
	if core_tex != null:
		var cs := U_CORE * sc * _core_breath() * (4.4 / U_CORE)
		draw_texture_rect(core_tex, Rect2(c - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false)
	else:
		draw_arc(c, rc, 0.0, TAU, 48, P_ALLY_DARK, maxf(2.0, 0.55 * sc), true)   # 外环
		draw_circle(c, rc * 0.72, P_ALLY)                                        # 中盘
		for k in 8:                                                              # 刻齿
			var a := TAU * float(k) / 8.0
			draw_line(c + _dir(a) * (rc * 0.86), c + _dir(a) * (rc * 1.06),
				P_ALLY_DARK, maxf(1.0, 0.18 * sc), true)
		draw_arc(c, rc + 0.11 * sc, 0.0, TAU, 48, P_TOWER_EDGE, maxf(1.5, 0.22 * sc), true)
	# 🔴 内芯保留其**原有更快一层**（±6% @1.6s，spec §B.2.2）→ 两层不同频叠出"心跳/有机感"。
	var breath := 1.0 + 0.06 * sin(_vfx_t * TAU / 1.6)                        # 呼吸内芯
	draw_circle(c, rc * 0.32 * breath, P_CORE_HI)
	# 🔴 P0 增强 · 受创闪（spec §A.2.3）：核心受击瞬间外环闪 #FF2E4E @α0.8，0.12s。
	#   本地演出计时器驱动衰减，只读 `core_hp` 帧间下降（不回写玩法）。
	if _core_flash > 0.0:
		var fp := clampf(_core_flash / CORE_FLASH_SEC, 0.0, 1.0)
		draw_arc(c, rc + 0.05 * sc, 0.0, TAU, 48,
			Color(P_ALERT.r, P_ALERT.g, P_ALERT.b, 0.8 * fp),
			maxf(2.0, 0.35 * sc), true)


# ---- 层6：塔（双层八边形 + 中心圆 + 左上高光 + 外扩描边 + 层数刻度）----
func _draw_radial_towers(sc: float) -> void:
	if controller == null or controller.runtime == null:
		return
	var snap: Dictionary = controller.runtime.snapshot()
	var towers: Array = snap.get("slots", [])
	var selected: int = int(snap.get("selected_tower_slot", -1))
	var core_slot: int = int(snap.get("core_tower_slot", -1))
	var hosts: Array = _forced_select_hosts(snap)
	var slots: Array = _slots_arr()
	for tw in towers:
		if bool(tw.get("empty", true)):
			continue
		var slot: int = int(tw.get("slot", -1))
		if slot < 0 or slot >= slots.size():
			continue
		var c := _to_screen(slots[slot])
		var R := U_TOWER * sc
		if hosts.has(slot):   # 合法宿主高亮（底圈）
			draw_arc(c, R + 0.5 * sc, 0.0, TAU, 32,
				Color(P_GOLD.r, P_GOLD.g, P_GOLD.b, 0.9), maxf(2.0, 0.22 * sc), true)
		# 🔴 批次⑥：塔身贴图（底座+塔身+中心圆+高光+徽记+外描边烘焙，半边 2.0u）；
		#    宿主环/主塔/选中/停机/复活/形态/闪白/rim 全部保留运行时。缺失降级回程序化。
		var tower_tex := _sprite("sp_tower_" + String(tw.get("ctype", "Arrow")).to_lower())
		if tower_tex != null:
			var tsize := 4.0 * sc
			draw_texture_rect(tower_tex, Rect2(c - Vector2(tsize, tsize) * 0.5, Vector2(tsize, tsize)), false)
		else:
			draw_colored_polygon(_oct8(c, R, 0.0), P_ALLY_DARK)          # 底座（暗）
			draw_colored_polygon(_oct8(c, R * 0.66, PI / 8.0), P_ALLY)   # 塔身（亮，旋转 22.5°）
			draw_circle(c, R * 0.30, P_ALLY_DARK)                        # 中心圆
			draw_circle(c + Vector2(-0.28 * R, -0.28 * R), R * 0.30, Color(1.0, 1.0, 1.0, 0.9))
			# 🔴 T-P6-06 S5：原型区分**内形**（只读 `ctype`，零新增字段/信号；不破 8 重对称剪影）。
			_draw_radial_tower_glyph(c, R, String(tw.get("ctype", "Arrow")), sc)
			draw_polyline(_closed(_oct8(c, R + 0.5 * U_OUTLINE * sc, 0.0)),
				P_TOWER_EDGE, maxf(1.5, U_OUTLINE * sc), true)          # 外扩描边
		_draw_rim(c, R, maxf(1.5, U_OUTLINE * sc), RIM_ALLY)         # P0 增强：内发光
		if slot == core_slot:   # 主塔标记（星紫）
			draw_arc(c, R + 0.5 * sc, 0.0, TAU, 28, P_ALLY_2, maxf(1.5, 0.16 * sc), true)
		if slot == selected:    # 选中高亮（耀青）
			draw_arc(c, R + 0.7 * sc, 0.0, TAU, 30, P_ALLY, maxf(2.0, 0.24 * sc), true)
		if _aggro_ui() and _is_disabled(slot):   # 停机态（🟢 反制窗口：门控挂 aggro 事实层，与复活解耦）
			draw_circle(c, R, Color(0.06, 0.07, 0.09, 0.62))
			draw_arc(c, R, 0.0, TAU, 28, Color(0.55, 0.57, 0.62, 0.55), maxf(1.0, 0.10 * sc), true)
		_draw_revive_charge(c, slot, R, sc)
		_draw_fire_charge(c, slot, R, sc)
		# 🔴 P0 增强：升级「形态」递进（h 越高越醒目；**取代**原"层数白点"）。
		_draw_tower_form(c, R, int(tw.get("h", 1)), sc)
		# 🔴 P0 增强：塔受击一瞬白闪（本地计时器；仅对可见塔）。
		if _tower_flash.has(slot):
			var tfp := clampf(float(_tower_flash[slot]) / TOWER_FLASH_SEC, 0.0, 1.0)
			draw_circle(c, R, Color(1.0, 1.0, 1.0, 0.6 * tfp))


## 🔴 T-P6-06 S5（锚点4-3「唯一剪影」/ art-bible §3.1 塔=严格 8 重对称）：RADIAL 三塔
##   补**原型区分**。约束：八边形轮廓保持**严格 8 重对称**（`_oct8` 红线，不改剪影）→
##   仅在**内芯**叠一个**居中徽记**，按**边数**区分原型（形状冗余，非色相，兼合 §9.2①）：
##     Arrow=三角(3) / Cannon=菱形(4) / Frost=六边形(6)。
##   🔴 只读 `ctype`（`runtime.snapshot().slots` 已含）→ **零新增 snapshot 字段、零新信号**。
##   🟠 T-P6-07 微调（选项 A · art-director `s2-s5-visual-review.md` §2）：徽记半径 **0.26R → 0.31R**
##     （+19%，落在 art-director 建议的 +15~20% 带内）——解 **Frost 六边形在 ~10px 下偏圆** 的可辨性
##     不足。🔴 配套红线（art-bible §3.1 v0.2 新登记）逐条遵守：
##       · **不改外框顶点数**（仍 3/4/6；本改仅动半径，`_ngon` 的 `n`/`rot` 一字未动）；
##       · **不突破塔位半径**（0.31R = 0.53u ≪ R = 1.70u，且 < h≥2 内层细环 0.46R → 不越内芯、不撞内环）；
##       · **与原型色冗余而非替代**（徽记仍为**形状**第二通道，色相语言未动）；
##       · 仍居中、仍严格 ≤ R → **外轮廓 8 重对称不受影响**（不改剪影）。
##   🚫 本轮**不采纳选项 C**（高光外移/减淡）——避免动到已确认的静态可读性成果（team-lead 裁定）。
func _draw_radial_tower_glyph(c: Vector2, R: float, ctype: String, sc: float) -> void:
	var n := 3
	var rot := -PI * 0.5          # 三角：顶点朝上
	match ctype:
		"Pyroclasm":
			n = 12
		"Cannon":
			n = 4
			rot = PI * 0.25       # 菱形
		"Frost":
			n = 6
			rot = 0.0             # 六边形
		# 🆕 扩展包两塔：继续「按边数区分原型」的既有约定（3/4/6 → 5/7）。
		# 🔴 只动内芯徽记的顶点数，**外框 8 重对称一字未动**（art-bible §3.1 红线）。
		"Lance":
			n = 5
			rot = -PI * 0.5       # 五边形（顶点朝上）
		"Tesla":
			n = 7
			rot = -PI * 0.5       # 七边形
		# 🆕 破甲塔（Sunder / Hex）：继续按边数区分（5/7 → 8/9），八/九边形。
		#   与 Lance/Tesla 同族处理：只动内芯徽记顶点数，外框 8 重对称不动。
		"Sunder":
			n = 8
			rot = PI * 0.125      # 八边形（顶点朝上）
		"Hex":
			n = 9
			rot = -PI * 0.5       # 九边形（顶点朝上）
		# 🆕 流派第二塔（card-packs v0.2）：继续按边数区分（10~15 边），
		#   与同 tag 主塔「同族但可辨」——第二塔边数 = 主塔边数 + 7（拉开间距避免混淆）。
		#   🔴 只动内芯徽记顶点数，外框 8 重对称一字未动（art-bible §3.1 红线）。
		"Ember":
			n = 10
			rot = PI * 0.1        # 十边形（火族，近 Cannon 菱形）
		"Icicle":
			n = 11
			rot = -PI * 0.5       # 十一边形（冰族，近 Frost 六边形）
		"Javelin":
			n = 12
			rot = -PI * 0.5       # 十二边形（穿甲族，近 Lance 五边形）
		"Bolt":
			n = 13
			rot = -PI * 0.5       # 十三边形（电族，近 Tesla 七边形）
		"Maul":
			n = 14
			rot = PI * 0.125      # 十四边形（破甲族，近 Sunder 八边形）
		"Rune":
			n = 15
			rot = -PI * 0.5       # 十五边形（咒术族，近 Hex 九边形）
		# 🔴 批次⑤修复：Oblivion / Void 原先**不在 match 里** → 落默认 3 边，与 Arrow 撞脸。
		"Oblivion":
			n = 16
			rot = -PI * 0.5       # 十六边形（湮灭族，边数顶格）
		"Void":
			n = 17
			rot = -PI * 0.5       # 十七边形（虚空族）
	# 亮内形 + 极深描边（自带边界，抗左上高光干扰）。纯几何、无随机、帧间稳定。
	# 🟠 0.31R（≈+19% vs 改前 0.26R）——见上「选项 A」说明。
	var pts := _ngon(c, R * 0.31, n, rot)
	draw_colored_polygon(pts, _tower_glyph_color(ctype))
	draw_polyline(_closed(pts), P_TOWER_EDGE, maxf(1.0, 0.06 * sc), true)
	# 🔴 批次⑤：内芯**符号**通道（1-2 笔粗几何，第二形状通道）——
	#    边数 ≥10 的塔在实机尺寸下视觉即圆，单靠边数不可辨；符号 + 色相双冗余（§9.2①）。
	_draw_glyph_mark(c, R * 0.31, ctype, sc)


## 🔴 批次⑤（塔辨识度强化）：徽记**填充色** = 原型 accent。
##   色源全部取自 §2.2 / RARITY 已登记色（不发明新色）；塔身仍统一 P_ALLY 青
##   （敌我识别由外框承担 —— S4 教训：塔身色相不可越冷极），内芯小面积点缀不破坏该通道。
##   同 tag 族共享色相（火=熔橙 / 冰=湖蓝 / 电=辉金 / 穿甲=耀青 / 破甲=钢灰 / 咒术=幽紫），
##   族内再靠边数 + 符号区分。
func _tower_glyph_color(ctype: String) -> Color:
	match ctype:
		"Cannon", "Maul":
			return P_SLOT                       # 钢灰（破甲/攻城族）
		"Frost", "Icicle":
			return Color(0.243, 0.659, 1.000)   # 湖蓝 #3EA8FF（冰族，RARITY rare 同源）
		"Tesla", "Bolt":
			return P_GOLD                       # 辉金（电族）
		"Hex", "Rune":
			return Color(0.706, 0.361, 1.000)   # 幽紫 #B45CFF（咒术族，RARITY epic 同源）
		"Ember", "Pyroclasm":
			return P_ENEMY                      # 熔橙（火族 · 内芯小面积点缀）
		"Oblivion":
			return P_ALLY_2                     # 星紫（湮灭）
		"Lance", "Javelin", "Void":
			return Color(0.97, 0.99, 1.0)       # 近白（穿甲/虚空：形不同色同，靠符号区分）
		_:
			return P_ALLY                       # Arrow（耀青，本命色）


## 🔴 批次⑤：内芯**符号**（第二形状通道）。全部 ≤2 笔粗几何（线宽 ≥0.10R），
##   实机 5-9px 内芯下仍可辨；色用 P_TOWER_EDGE（冷暗，在亮填充上足够对比）。
func _draw_glyph_mark(c: Vector2, r: float, ctype: String, sc: float) -> void:
	var w := maxf(1.2, 0.10 * sc)
	var col := P_TOWER_EDGE
	match ctype:
		"Pyroclasm": # 蓄能核心：中心圆 + 四向辐射
			draw_circle(c, r * 0.22, col)
			for i in range(4):
				var axis := Vector2.from_angle(TAU * float(i) / 4.0)
				draw_line(c + axis * r * 0.4, c + axis * r * 0.7, col, w, true)
		"Arrow":      # 上箭头 ∧
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, r * 0.3), c + Vector2(0, -r * 0.45), c + Vector2(r * 0.5, r * 0.3)]), col, w, true)
		"Cannon":     # 中心圆点
			draw_circle(c, r * 0.28, col)
		"Frost":      # 竖线 + 交叉（雪花三向）
			draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.5), col, w, true)
			draw_line(c + Vector2(-r * 0.42, -r * 0.26), c + Vector2(r * 0.42, r * 0.26), col, w * 0.8, true)
			draw_line(c + Vector2(-r * 0.42, r * 0.26), c + Vector2(r * 0.42, -r * 0.26), col, w * 0.8, true)
		"Lance":      # 贯穿竖线（细长）
			draw_line(c + Vector2(0, -r * 0.62), c + Vector2(0, r * 0.62), col, w * 0.9, true)
		"Tesla":      # 闪电折线
			draw_polyline(PackedVector2Array([c + Vector2(r * 0.1, -r * 0.55), c + Vector2(-r * 0.3, r * 0.05), c + Vector2(r * 0.05, r * 0.05), c + Vector2(-r * 0.1, r * 0.55)]), col, w, true)
		"Sunder":     # 裂纹 ✕
			draw_line(c + Vector2(-r * 0.45, -r * 0.45), c + Vector2(r * 0.45, r * 0.45), col, w, true)
			draw_line(c + Vector2(-r * 0.45, r * 0.45), c + Vector2(r * 0.45, -r * 0.45), col, w, true)
		"Hex":        # 中空环
			draw_arc(c, r * 0.42, 0.0, TAU, 20, col, w, true)
		"Ember":      # 火苗（小三角叠点）
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, r * 0.35), c + Vector2(0, -r * 0.45), c + Vector2(r * 0.4, r * 0.35)]), col, w, true)
			draw_circle(c + Vector2(0, r * 0.28), r * 0.14, col)
		"Icicle":     # 倒三角
			draw_polyline(_closed(PackedVector2Array([c + Vector2(-r * 0.42, -r * 0.35), c + Vector2(r * 0.42, -r * 0.35), c + Vector2(0, r * 0.5)])), col, w, true)
		"Javelin":    # 斜箭 ↗
			draw_line(c + Vector2(-r * 0.45, r * 0.45), c + Vector2(r * 0.45, -r * 0.45), col, w, true)
			draw_line(c + Vector2(r * 0.05, -r * 0.45), c + Vector2(r * 0.45, -r * 0.45), col, w * 0.9, true)
			draw_line(c + Vector2(r * 0.45, -r * 0.05), c + Vector2(r * 0.45, -r * 0.45), col, w * 0.9, true)
		"Bolt":       # 双折线（电弧二重）
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.5), c + Vector2(-r * 0.1, 0), c + Vector2(-r * 0.4, r * 0.1)]), col, w * 0.9, true)
			draw_polyline(PackedVector2Array([c + Vector2(r * 0.4, -r * 0.1), c + Vector2(r * 0.1, r * 0.4), c + Vector2(r * 0.4, r * 0.55)]), col, w * 0.9, true)
		"Maul":       # 方块（锤头）
			draw_rect(Rect2(c.x - r * 0.35, c.y - r * 0.35, r * 0.7, r * 0.7), col, false, w)
		"Rune":       # 同心环
			draw_arc(c, r * 0.48, 0.0, TAU, 18, col, w * 0.9, true)
			draw_circle(c, r * 0.16, col)
		"Oblivion":   # 实心深芯（吞光）
			draw_circle(c, r * 0.34, Color(0.05, 0.03, 0.09, 1.0))
		"Void":       # 同心双环（虫洞）
			draw_arc(c, r * 0.48, 0.0, TAU, 18, col, w * 0.8, true)
			draw_arc(c, r * 0.22, 0.0, TAU, 14, col, w * 0.8, true)


# ---- 层7：怪（12 边不规则 + 朝核心尖刺扇 + 外扩描边）----

## 🆕 召唤小兵（2026-11-07）：只读 `_snap["minions"]`，画成青蓝色小圆点 + 细环。
##   🔴 渲染层零文本 / 零玩法写入（AC-T1-24 同纪律）。
func _draw_minions(sc: float) -> void:
	if _snap.is_empty():
		return
	for mn in _snap.get("minions", []):
		var p: Vector2 = mn["pos"]
		var sp := _to_screen(p)
		var mtex := _sprite("sp_minion")
		if mtex != null:
			var msz := 1.5 * sc   # 贴图半边 0.75u（含细环余量）
			draw_texture_rect(mtex, Rect2(sp - Vector2(msz, msz) * 0.5, Vector2(msz, msz)), false)
		else:
			var r := maxf(3.0, sc * 0.45)
			draw_circle(sp, r, C_CORE)
			draw_arc(sp, r + maxf(2.0, sc * 0.12), 0.0, TAU, 12, C_CORE, 1.0, true)
func _draw_radial_monsters(sc: float) -> void:
	var ms: Array = _snap.get("monsters", [])
	if ms.is_empty():
		return
	var core := _SpaceModel.RADIAL_CORE
	var w := maxf(1.5, U_OUTLINE * sc)
	for m in ms:
		var pos: Vector2 = m["pos"]
		var c := _to_screen(pos)
		var proto := String(m["proto"])
		var elite := bool(m.get("elite", false))
		var R := _body_units(proto, elite) * sc
		var out_dir := atan2(pos.y - core.y, pos.x - core.x)
		var rs := 1.0
		var ts := 1.0
		var n_spike := 5
		var spike_len := 0.55
		var spike_half := 0.26
		match proto:
			"Rush":
				rs = 1.5; ts = 0.75; n_spike = 4; spike_len = 0.9; spike_half = 0.14
			"Tank":
				rs = 0.85; ts = 1.25; n_spike = 6; spike_len = 0.4; spike_half = 0.30
			_:
				rs = 1.0; ts = 1.0; n_spike = 5; spike_len = 0.55; spike_half = 0.26
		if elite:
			n_spike += 1
			spike_len *= 1.3
		# 🔴 P0（spec §B.3）：squash&stretch + 摆动 —— 相位**纯由 `pos` 派生**（零新增状态、帧间稳定）。
		#   ph = θ + (−ρ)·k_ρ + φ_proto；sw = sin(ph)。
		#   θ(=out_dir，方位) 天然给每只怪不同相位偏移；−ρ·k_ρ 随接近核心平滑推进 = "在走"。
		var rho := pos.distance_to(core)
		var ph := out_dir + (-rho) * SWAY_K_RHO + _sway_phase(proto)
		var sw := sin(ph)
		var amp := _sway_amp(proto)
		var rs2 := rs * (1.0 + amp * sw)     # 径向拉伸（朝核心轴）
		var ts2 := ts * (1.0 - amp * sw)     # 切向压扁（体积近似守恒）
		var rot2 := _sway_rot(proto) * cos(ph)   # 体摆动（绕中心小角度）
		# 🔴 批次⑥：怪体贴图（主体+tank内环+尖刺扇+外描边烘焙，半边 2.4u；精英独立变体）。
		#    基础 rs/ts 形变已烘焙，运行时 transform 只乘**摆动幅度**（squash&stretch 保留）；
		#    rim / 精英环保留运行时。缺失降级回程序化。
		var mon_tex := _sprite("sp_mon_" + proto.to_lower() + ("_elite" if elite else ""))
		if mon_tex != null:
			# 贴图尖刺朝上（-Y）→ 旋到 out_dir 轴（+rot2 体摆动）；Y=径向 / X=切向
			draw_set_transform(c, out_dir + rot2 + PI * 0.5,
				Vector2(1.0 - amp * sw, 1.0 + amp * sw))
			var msize := 4.8 * sc
			draw_texture_rect(mon_tex, Rect2(Vector2(-msize, -msize) * 0.5, Vector2(msize, msize)), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_draw_rim(c, R, w, RIM_ENEMY)   # P0 增强：内发光（混乱时分离相邻单位）
		else:
			draw_colored_polygon(_blob12(c, R, out_dir + rot2, rs2, ts2), P_ENEMY)   # 主体（随摆）
			if proto == "Tank":   # 内层焦褐环
				draw_arc(c, R * 0.55, 0.0, TAU, 20, P_ENEMY_DARK, maxf(1.5, 0.16 * sc), true)
			# 🔴 尖刺扇仍沿 `out_dir`（**朝核心，不随摆**）—— 尖刺语义 = "扑向核心"（spec §B.3.4）。
			for i in n_spike:    # 外张尖刺扇（沿"朝核心"方向）
				var a := out_dir + SPIKE_SPREAD * (float(i) - float(n_spike - 1) * 0.5)
				var tip := c + _dir(a) * (R + spike_len * sc)
				var bl := c + _dir(a - spike_half) * (R * 0.9)
				var br := c + _dir(a + spike_half) * (R * 0.9)
				draw_colored_polygon(PackedVector2Array([bl, tip, br]), P_ENEMY_DARK)
			# 🔴 外扩描边**必须与主体同参数**（`out_dir+rot2, rs2, ts2`），否则"描边错位"（spec §B.3.4）。
			draw_polyline(_closed(_blob12(c, R + w * 0.5, out_dir + rot2, rs2, ts2)),
				P_MON_EDGE, w, true)   # 外扩描边
			_draw_rim(c, R, w, RIM_ENEMY)   # P0 增强：内发光（混乱时分离相邻单位）
		if elite:   # 精英环（噬品红）
			draw_arc(c, R + 0.28 * sc, 0.0, TAU, 24, P_ELITE, maxf(2.0, 0.18 * sc), true)


# ---- 层8：投射物（spec §A.2.4；snapshot 无 `projectiles` 字段 → 零绘制）----
func _draw_projectiles(sc: float) -> void:
	var ps: Array = _snap.get("projectiles", [])
	for pr in ps:
		if not (pr is Dictionary):
			continue
		var d: Dictionary = pr
		if not d.has("pos"):
			continue
		var sp := _to_screen(d["pos"])
		if String(d.get("faction", "ally")) == "enemy":
			var dtex := _sprite("sp_proj_dot")
			if dtex != null:
				var dsz := 1.2 * sc   # 贴图半径 0.6u
				draw_texture_rect(dtex, Rect2(sp - Vector2(dsz, dsz) * 0.5, Vector2(dsz, dsz)), false)
			else:
				draw_circle(sp, maxf(2.0, 0.60 * sc), P_ENEMY)
		else:
			var ang := 0.0
			if d.has("vel"):
				var vv: Vector2 = d["vel"]
				ang = atan2(vv.y, vv.x)
			var btex := _sprite("sp_proj_bolt")
			if btex != null:
				draw_set_transform(sp, ang + PI * 0.5, Vector2.ONE)   # 贴图尖端朝上 → 旋到 vel 方向
				var bsz := 2.0 * sc   # 贴图半边 1.0u
				draw_texture_rect(btex, Rect2(Vector2(-bsz, -bsz) * 0.5, Vector2(bsz, bsz)), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				draw_colored_polygon(PackedVector2Array([
					sp + _dir(ang) * (0.8 * sc),
					sp + _dir(ang + PI * 0.5) * (0.25 * sc),
					sp + _dir(ang - PI * 0.5) * (0.25 * sc)]), P_ALLY)
