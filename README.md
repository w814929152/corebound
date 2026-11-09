# 守核 Corebound

[![CI](https://github.com/w814929152/corebound/actions/workflows/ci.yml/badge.svg)](https://github.com/w814929152/corebound/actions/workflows/ci.yml)

> 肉鸽塔防 + 卡牌构筑 · PC / Steam · Godot 4.7.2-stable
>
> 玩家在**径向战场**上围绕核心布置防御塔，每波之间用安全窗买卡、装配、改装构筑；
> 开局先在**裂隙航图**（大地图）上选关，打完该关要求的波数（10~20）且核心未归零即通关。

---

## 玩法一句话

怪物从**出生环**沿径向直插**核心**（径向核心围攻）。塔位分布在核心周围的暴露 / 安全环带上；玩家在波间安全窗内用**废料**买卡（建筑卡 / 单塔卡 / 全局卡）与刷新商店，构筑出一条能清场的防线。核心 HP 归零即失败，打完该关要求的波数（`campaign_data.STAGES[*].wave_count`）且核心未归零即通关。

## 核心机制

| 机制 | 说明 |
|---|---|
| **径向运动学** | `ρ = R_s · m_spd · clamp(t_remain/t_reach, 0, 1/m_spd)`；`t_remain` 为**唯一权威状态量**，出生角由黄金角派生的**确定性**序列给出（零 RNG） |
| **三原型分化** | Rush（快 / 高移速）/ Swarm（基准）/ Tank（慢 / 高 HP）——由 `prototype_split_enabled` 控制 |
| **精英波（Elite）** | 每 5 波（W5/10/15/20）出现精英单位（更高 HP + 品红环标识）；Sapper 精英锁塔增伤 |
| **塔死亡与处置** | 仇恨锁定 → 塔可被打到 `Disabled` 中间态（断输出不断链）→ 修复 / 被动拆除 / 放置不管 |
| **献祭（Salvage Rite）** | 安全窗内拆塔的第二个出口：返还 0%、卡全销毁，换取 `stackcap_bonus`（收益 ∝ 投入） |
| **肉盾流（Bulwark）** | 涌现策略：暴露位塔先挨打、怪物锁定后停下不漏怪 → 用站位换来后排输出 |

## 卡池与扩展包

玩家路线商店基础池 6 张：`Arrow` / `Cannon` / `Frost`（三塔）+ `FireUp` / `FrostUp`（强化）+ `ScrapUp`（经济）。

**扩展包**（实机默认开启，`shop_runtime.set_extended_pack()` 一行可关）再加 4 张：

| 卡 | 定位 | dps | tag | rng | 特点 |
|---|---|---|---|---|---|
| **Lance** | 远程狙击 | 11.0 | `pierce` | 26.0 | 射程与输出双高，代价是独立 tag（协同从头攒） |
| **Tesla** | 贴身通电 | 6.0 | `shock` | 16.0 | 全塔最低 dps，换群伤 + 0.10 减速 |
| **PirUp** / **ShkUp** | 强化 | — | `pierce` / `shock` | — | 分别只对 Lance / Tesla 生效 |

🔴 **扩展卡只进玩家池**：金标本 `TOWERS` / `ShopAI.CARD_NAMES` / `WEIGHTS` 一字未动，AI 路线与 300 局 MC 金标本完全不受影响。设计与取舍见 `docs/phase6/extended-pack.md`。

### 卡包（81 张建筑卡 · 每局最多选 3 包）

当前卡池共 **8 包、81 张建筑卡**：熔炉包 11 张，其余每包 10 张，一卡一包。选择 3 包时，本局卡池为 **30 张**，包含熔炉包时为 **31 张**；可用包不足 3 个时选择全部可用包。

| 卡包 | id | 张数 | 机制 |
|---|---|---|---|
| 泛用包 | `core` | 10 | 赏金、经济、物理类型转换 |
| 熔炉包 | `cinder` | 11 | 灼烧、火焰充能、登场升级、觉醒 |
| 霜序包 | `rime` | 10 | 冰系、减速、整备升级 |
| 穿甲包 | `pierce` | 10 | 贯穿、流血、阵亡升级 |
| 电弧包 | `arc` | 10 | 弹射链、减速、击杀升级 |
| 破甲包 | `sunder` | 10 | 削物抗、流血、攻防光环 |
| 咒术包 | `hex` | 10 | 削魔抗、易伤、持续伤害 |
| 湮灭包 | `true` | 10 | 真实伤害、击杀升级、召唤、觉醒 |

- 玩家路线按地区解锁科技包：泛用包常驻，已守地区的科技永久入手，当前地区的原生包可本关借用。
- 刷新保底：手动刷新后若没有所选包的身份塔，会替换一个未锁定位补入随机身份塔。
- 关卡选择后进入选包，再开始战斗；再来一局会先返回航图。
- 卡包与顺序以 `scripts/data/card_packs.gd` 为准；完整图鉴见 `docs/phase6/card-catalog.md`。
- 选择存档为 `user://card_packs.json`；空选包时保留旧测试口径。

设计推导、池序坑、刷新保底、与关卡推进的关系见 `docs/phase6/card-packs.md`。

- **金标本（golden reference）逐位对齐**：玩法数值以一套 Python 对照实现为金标本，headless 测试逐位（`%.17g` / `%.17e`）比对，任何 ULP 级偏差都会翻红。
- **浮点可移植性强制**（ADR-0002）：整数指数必须走 `FpPow.pow_int()`；移植 Python `sum()` 必须走 `FpSum.sum_py()`。
- **双空间模型**：`SpaceModel` 支持 PATH（折线路径）与 RADIAL（径向）双模，默认 PATH、窗口模式注入 RADIAL，一行可回滚。
- **渲染层只读**：UI 只读战斗快照（snapshot），零玩法写入、零新信号。

## 关卡推进与裂隙航图（大地图选关）

全屏裂隙航图采用**五层轨道、螺旋链式展示**，由中枢逐步向主脑核心推进。航线表示展示顺序，实际解锁按前置与已守地区数量判断。

| 区域 | 关卡 | 波数 |
|---|---|---|
| 中枢 · 铁砧 | 0-1 | 10 |
| 外环 · 残存区 | 1-1 / 2-1 / 3-1 | 12 / 12 / 13 |
| 中环 · 争夺区 | 4-1 / 5-1 / 6-1 / 7-1 | 15 / 15 / 16 / 17 |
| 主脑外围 | 8-1 | 19 |
| 主脑核心 | 9-1 | 20 |

- 点击已解锁节点选择关卡；`←→` 移动焦点，`Enter` 选择，`Esc` 返回主菜单（界面保留文字提示）。
- 守住中枢后开放外环三区，中环按各关前置解锁；守住至少 5 个地区可进外围，守住全部 7 区且通关外围后可挑战核心。
- 通关与失败按规则结算余烬，关卡通关还会永久解锁对应地区科技包。
- **换图不换引擎**：每关绑定一张 `map_variants` 变体图，切换只改
  `SpaceModel.active_map_id`，岩脊 / 出生弧 / 阵地表整套替换。
- **再来一局**回到航图（能看到刚解锁的关），再选卡包 → 开打。
- 🔴 三态用**形状 + 颜色 + 文字**三条通道表达（✓ 已通关 / ▶ 可挑战 / 🔒 未解锁），
  锁定节点点上去**无反应**，不弹错、不踢人。
- 当前关卡与波表以 `campaign_data.gd`、`stage_waves.gd` 为准；世界主线说明见 `design/gdd/campaign-v2-overseer.md`。
- 一行回滚：`boot.gd` 的 `CAMPAIGN_ENABLED = false` → 不弹航图、不注入波数、不记账，
  回到 20 波金标本口径（卡包流程照旧）。

设计与布局推导见 `docs/phase6/world-map.md`。

## UI 样式

所有玩家可见界面共用一层样式来源 `scripts/ui/ui_style.gd`（调色板 / **字体注册表** / StyleBox 工厂 / 按钮变体 / 悬停动效），
色值逐字取自 `design/art/art-bible.md` §2.2，**不允许在各界面里二次发明颜色或控件外观**。

- **字体（art-bible §5.4，2026-11-07 接入）**：正文 Noto Sans SC 400 / 强调 500 / 展示 900
  （思源黑体同源 · SIL OFL）+ JetBrains Mono 等宽数字 —— 统一经 `ui_style.gd` 的
  `font_body / font_medium / font_display / font_num` 取用；`project.godot` 的
  `gui/theme/custom_font` 做工程级兜底。数字读数（积分 / 血量 / 波次 / 等级牌 / 伤害数字）
  一律等宽，滚动不再抖动。两份字体均带 OFL 授权文件入库 `assets/fonts/`。

- 按钮五变体：`primary`（金描边，主操作）/ `normal` / `ghost` / `danger` / `unavail`，
  自带悬停抬起 1.05、按下 0.97、0.12s 弹性缓动（§5.1）。
- **蓝图 chrome 与仪表读数（2026-11-07 接入）**：`attach_corner_chrome()` 提供外沿四角
  L 刻线（accent 可运行时切换 —— 结算面板胜利辉金 / 失败警报红），选包 / 选关主面板共用；
  结算界面 = Black 标题 + 三行等宽战报（核心剩余 / 坚守波次 / 本局废料），
  选包 / 选关底栏数字读数（已选 N/M 包 · 卡池 K 张 / 余烬）一律拆「中文骨架 + 等宽数字」。
- 玩家可见文本最小 16px 由 `_Style.label()` 强制兜底（§9.1 P0）。
- 结构断言 `tests/run_ui_style_asserts.gd`（80 项，进默认回归）钉住：**不得出现系统默认控件**、
  三位商品位尺寸一致（X3）、文案零开发占位、调色板不漂移、卡面每行 ≤9 汉字、放置入口可达。

重构背景与逐条对照见 `docs/phase6/ui-polish.md`。

## 卡面信息

每张卡在商店里必须自己回答「这张卡干什么」，文案统一从 `scripts/data/card_text.gd` 取，
**对数值 SSOT 只读不写** —— 伤害 / 射程 / 可强化对象全部现场派生，改数值卡面自动跟随。

- 卡面视觉走**蓝图风**（art-bible §5.5，2026-11-07 落地）：直角细描边卡座 + 四角刻线
  （可购性提亮为耀青）+ Tag 电路符号芯片（`ui_style.TAG_COLORS`，颜色复用 §2.2 登记色）
  + 等宽数字价格。Tag 数据源 = `card_text.tag_of()`；**稀有度色阶不做**（GDD §7.1）。

- 商品位恒 3 行：`机制` / `伤害 7 · 射程 18` / `标记：火`（建筑卡）；
  `强化「火」系塔` / `可强化 Cannon` / `同卡再买叠层`（单塔效果卡）。
- 三张卡下方一行说清购买流程（建筑卡进待放置队列 / 单塔效果卡投给点选塔 / 全局卡立即生效）。
- 🔴 商品位内宽实测仅 **155px**，16px 下**一行只放得下约 9 个汉字** ——
  文案写超了会二次换行、把三张卡撑成不等高，`uistyle` §I 有断言拦这条。

设计与版式推导见 `docs/phase6/card-text.md`。

## 放置塔（自由摆放）

建筑卡买下后进「待放置队列」，点队列里的「放置」进入 ⑤ 放置模式（0.25× 减速、**抽屉收起、战场全屏**）。

**塔可以放在任意格点**，不再限于 6 个固定塔位：进入 ⑤ 后整片可建区铺开**正六边形网格**
（外接圆半径 1.55 单位，邻格间距 2.68 单位），鼠标所指的格子实时给出落子预览。

> **为什么是六边形**：方格到 4 个斜角邻格的距离是正邻的 1.414 倍 —— 斜向埋塔更便宜，
> 玩家会自发只走对角线、塔阵退化成菱形条纹。六边形 6 个邻格距离全等（√3R），
> 没有这个「免费的方向」。单格面积 6.24 u² ≈ 改前方格 2.5² = 6.25 u² → **单格容量不变**，
> 网格覆盖 960 个格心（改前 964）。

| 格子状态 | 战场表现 | 点击结果 |
|---|---|---|
| 可新建 | 耀青六边形 + 半透明填充 + `＋` 徽标 | 落子 |
| 可升级（同格同原型） | 辉金粗六边形框（只描边不填充，塔身不被染色）+ `↑` 徽标 | 叠层，不新增塔 |
| 核心禁建区 / 战场外 | 钢灰六边形，无徽标 | 无反应 |
| 塔数已满 / 该格已有别的原型 | 钢灰六边形，无徽标 | 无反应 |

- 可建区：核心周围 4 单位禁建，外径 44 单位封顶（出生环 55，不给"怪一出生就挨打"的白嫖位）。
- **塔数上限 10**（`cfg["tower_cap"]`），与金标本槽位数 `n_slots = 6` 语义分离。
  ⚠️ 10 是起点值、**未经 MC 校准**，见下一节。
- 可建位几何与判定共用 `scripts/geo/build_grid.gd` —— 逻辑层和渲染层不会各写一套参数。
- 🔴 **点错不踢人**：点禁建区 / 点灰显格都只是无反应，退出放置模式只认 `Esc`。
- 徽标符号全部用 `draw_line` 画，渲染层保持零文本（AC-T1-24）。
- 结构断言 `tests/run_ui_style_asserts.gd` §J（14 项）+ §K（27 项，进默认回归）钉住
  「落子入口可达」与「网格几何不变量（吸附幂等 / 核心禁建 / 塔数上限 / 同格升级）」。
- 端到端点击验证见 `tests/probe_placement.gd`（需窗口，非 CI）。

### ⚠️ 塔数上限 10 未经平衡验证

`n_slots = 6` 是 κ_r=0.050 / ATTRITION=1.50 / 300 局 MC 判据链的共同基准。放宽到 10 座后，
经济曲线、κ 收敛路径、每波掉塔期望都会变 —— 要变成可发布数值需重跑 10 槽口径 MC 并重标 κ_r。

一键回退：`ShopRuntime.free_placement = false` → 回到 6 个固定塔位（金标本口径）。

设计与取舍见 `docs/phase6/free-placement.md`；上一轮"落子入口不可达"的修复复盘见
`docs/phase6/placement-fix.md`。

## 本地运行与自测

需要 Godot **4.7.2-stable**。

```bash
GODOT="<你的 Godot 可执行文件>"

# 全量 headless 回归（切片 1–8 + T1 仇恨）
"$GODOT" --headless --path . --script res://tests/run_tests.gd

# 只跑某切片（参数必须以 slice 开头）
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- slice5

# 只跑某一套结构断言（uistyle / tlv / campaign / cardpack / combat_types / extpack / tutorial）
#   两种入口等价：单套件可直跑（`extends SceneTree`，中文输出不过 OS.execute 的 GBK 转换，不会乱码）
"$GODOT" --headless --path . --script res://tests/run_ui_style_asserts.gd
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- uistyle

# radial8 聚合闸门
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- radial8

# 实机口径 MC（RADIAL + 三原型 + Elite；B 起飞率 ≥ 0.80 门禁）
"$GODOT" --headless --path . --script res://tests/run_slice_proto_elite_mc.gd

# 窗口模式直接玩（真实帧）
"$GODOT" --path .
```

> ⚠️ `--headless --script` 路径下 Godot 没有 `global_script_class_cache`，因此工程内**一律 `preload`，不写 `class_name`**。
>
> ⚠️ `--script` 指向的文件**必须继承 `SceneTree` / `MainLoop`**（`--script` 是「换主循环」而非「加载模块」）。
> `tests/run_*_asserts.gd` 因此统一 `extends SceneTree` + `_initialize() -> quit(0/1)`；
> `run_tests.gd` 的进程内聚合走 `.new().run_all()` —— `.new()` 不触发 `_initialize()`，两条入口共用同一份断言。
> 若写成 `extends RefCounted`，直跑会被引擎拒载：「Can't load the script as it doesn't inherit from SceneTree or MainLoop」。

## 打包可玩版本

已配好 Windows Desktop 导出预设（`export_presets.cfg`，单文件 exe + 内嵌 pck）：

```bash
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/Corebound.exe
```

产物 `build/windows/Corebound.exe`（约 112 MB，pck 内嵌，双击即玩，无需安装 Godot 或联网）。`build/`、`*.exe` 已在 `.gitignore` 内，**二进制不入库**。

**操作**：开局在裂隙航图点节点选关（`←→` 移动 · `Enter` 进入）· `Tab` 商店 · `1/2/3` 买卡 · `R` 刷新 · `Space` 开下一波 · `Esc` 关抽屉/取消/跳过引导 · 鼠标点地图上的格子落子（自由摆放，见上文「放置塔」）。

详细打包流程、模板位置、验收记录与已知限制见 `docs/phase6/demo-build.md`。

## CI

`.github/workflows/ci.yml` 在 push / PR 时自动跑（`docs/**`、`**/*.md`、`.workbuddy/**` 的改动不触发），ubuntu-latest + Godot 4.7.2-stable，共 **9 步测试**：

1. **默认回归** —— 切片 1–8 + T1 仇恨 + B-1 引导状态机 + 扩展包/UI 样式/塔等级牌/卡包/关卡推进/战斗类型，多段汇总、退出码 0；
2. **音频资产 lint** —— 免导入的 `key → path` 兜底校验（关闭 G-6：音频 id 打错在运行时只会静默 null）；
3. **音频框架回归断言** —— audio-spec-a §7 五条（池 24+4 / 总线名 / 信号数 / 聚焦低通 / token 扫描）；
4. **radial8 聚合闸门** —— 9 个子套件：geo8 / radial / geo8_smoke / geo8_golden / expo / bulwark8 / panorama8 / attrition8 / vfx_cache_guard；
5. **aggro_golive 退化逐位守护** —— 三轴合并镜像（第五刀）；
6. **实机口径 MC** —— 三原型 + Elite，300 局，B 起飞率 ≥ 0.80；
7. **实机全开 MC** —— proto/elite/aggro 全 ON × `repair_on_disable` ∈ {0 OFF, 1 FREE, 2 PRICED}，PRICED 多塔 B@6 ≥ 0.80（第五刀上线门禁）；
8. **反制窗口 M-1 上线 MC（C-8）** —— REVIVE(9) 多塔 B@6 ≥ 0.80，并自检 OFF B@6 复现 203/300 = 0.677（M-1 接线零扰动）；
9. **反制窗口实时版 MC（R-1）** —— 真身 `WaveDirector` 直读产品开关 `combat_revive_enabled`，OFF B@6 守门 + PRODUCT B@6 ≥ 0.80。

任一步非零退出 = CI 红。日志无论成败都会作为 artifact 上传。

> 🔴 硬门禁请按**步骤名**引用，勿按序号引用：插步会使序号整体偏移（2026-10-13 音频两步插入，曾使原步 1–7 变步 1–9）。

## 目录结构

```
scripts/
  engine/    伤害引擎 / 战斗循环 / 金标本镜像（wave_sim、run_loop、shop_ai…）
  gameplay/  刷怪调度（wave_director）、怪物实体、商店桥接
  geo/       空间模型（径向 / 折线路径）与几何
  data/      怪物与塔的数值表（SSOT）
  ui/        战场渲染、HUD、商店覆盖层、启动场景
tests/       headless 断言套件 + 各切片冒烟 + 数值扫描 / MC 脚本
docs/
  architecture/  工程控制清单（红线与口径冻结）、ADR、各切片架构
  phase3/        各切片验收报告、质量门、径向迁移、体验层与玩法刀次规格
design/      设计稿（GDD、数值模拟）
```

## 文档索引

- **工程控制清单（总红线 + 口径冻结 + 提交前自检）**：`docs/architecture/control-manifest.md`
- **径向迁移质量门**：`docs/phase3/quality-gate-radial-migration.md`
- **各切片验收**：`docs/phase3/slice{1..8}-verify.md`
- **浮点可移植性决策**：`docs/architecture/adr-0002-float-portability.md`
- **UI 样式重构对照**：`docs/phase6/ui-polish.md`
- **卡面文案与版式推导**：`docs/phase6/card-text.md`
- **放置模式修复（四条 bug 复盘）**：`docs/phase6/placement-fix.md`
- **自由摆放（网格化 + 坐标落子 + 塔数上限）**：`docs/phase6/free-placement.md`
- **卡包（分池 + 开局选包 + 地区科技解锁）**：`docs/phase6/card-packs.md`
- **大地图选关（裂隙航图 + 关卡推进接线）**：`docs/phase6/world-map.md`

---

## 状态

Phase 3 MVP：切片 1–8 已交付（伤害引擎 → 战斗循环 → 商店 → 径向核心围攻 → 塔死亡玩法 → 可玩胜负）；
径向迁移收官（默认窗口即 RADIAL）；三原型 / 精英波已上线。
Phase 6：扩展包 / 卡包（8 包共 81 张，每局最多 3 包）/ 关卡推进 + 裂隙航图（10 关 × 10 张地图变体）/
战斗类型（物攻 · 魔攻 · 真实 × 双抗性）已落地并进默认回归。

> 🔴 数值口径为工程级冻结资产：`ATTRITION` / `κ_r` / `AGGRO_R` / 塔位 / `SPAWN_RADIUS` / 核心 HP / `hp_growth` / 三原型表等，改动一律走 ADR 并需拍板。
