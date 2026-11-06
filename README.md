# 守核 Corebound

[![CI](https://github.com/w814929152/corebound/actions/workflows/ci.yml/badge.svg)](https://github.com/w814929152/corebound/actions/workflows/ci.yml)

> 肉鸽塔防 + 卡牌构筑 · PC / Steam · Godot 4.7.2-stable
>
> 玩家在**径向战场**上围绕核心布置防御塔，每波之间用安全窗买卡、装配、改装构筑；活过 20 波即通关。

---

## 玩法一句话

怪物从**出生环**沿径向直插**核心**（径向核心围攻）。塔位分布在核心周围的暴露 / 安全环带上；玩家在波间安全窗内用**废料**买卡（建筑卡 / 单塔卡 / 全局卡）与刷新商店，构筑出一条能清场的防线。核心 HP 归零即失败，打完 W20 且核心未归零即通关。

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

- **金标本（golden reference）逐位对齐**：玩法数值以一套 Python 对照实现为金标本，headless 测试逐位（`%.17g` / `%.17e`）比对，任何 ULP 级偏差都会翻红。
- **浮点可移植性强制**（ADR-0002）：整数指数必须走 `FpPow.pow_int()`；移植 Python `sum()` 必须走 `FpSum.sum_py()`。
- **双空间模型**：`SpaceModel` 支持 PATH（折线路径）与 RADIAL（径向）双模，默认 PATH、窗口模式注入 RADIAL，一行可回滚。
- **渲染层只读**：UI 只读战斗快照（snapshot），零玩法写入、零新信号。

## 本地运行与自测

需要 Godot **4.7.2-stable**。

```bash
GODOT="<你的 Godot 可执行文件>"

# 全量 headless 回归（切片 1–8 + T1 仇恨）
"$GODOT" --headless --path . --script res://tests/run_tests.gd

# 只跑某切片（参数必须以 slice 开头）
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- slice5

# radial8 聚合闸门
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- radial8

# 实机口径 MC（RADIAL + 三原型 + Elite；B 起飞率 ≥ 0.80 门禁）
"$GODOT" --headless --path . --script res://tests/run_slice_proto_elite_mc.gd

# 窗口模式直接玩（真实帧）
"$GODOT" --path .
```

> ⚠️ `--headless --script` 路径下 Godot 没有 `global_script_class_cache`，因此工程内**一律 `preload`，不写 `class_name`**。

## 打包可玩版本

已配好 Windows Desktop 导出预设（`export_presets.cfg`，单文件 exe + 内嵌 pck）：

```bash
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/Corebound.exe
```

产物 `build/windows/Corebound.exe`（约 112 MB，pck 内嵌，双击即玩，无需安装 Godot 或联网）。`build/`、`*.exe` 已在 `.gitignore` 内，**二进制不入库**。

**操作**：`Tab` 商店 · `1/2/3` 买卡 · `R` 刷新 · `Space` 开下一波 · `Esc` 关抽屉/取消/跳过引导 · 鼠标点塔位落子。

详细打包流程、模板位置、验收记录与已知限制见 `docs/phase6/demo-build.md`。

## CI

`.github/workflows/ci.yml` 在 push / PR 时自动跑（`docs/**`、`**/*.md`、`.workbuddy/**` 的改动不触发），ubuntu-latest + Godot 4.7.2-stable，共 **9 步测试**：

1. **默认回归** —— 切片 1–8 + T1 仇恨 + B-1 引导状态机，十段汇总、退出码 0；
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

---

## 状态

Phase 3 MVP：切片 1–8 已交付（伤害引擎 → 战斗循环 → 商店 → 径向核心围攻 → 塔死亡玩法 → 可玩胜负）；
径向迁移收官（默认窗口即 RADIAL）；三原型 / 精英波已上线。

> 🔴 数值口径为工程级冻结资产：`ATTRITION` / `κ_r` / `AGGRO_R` / 塔位 / `SPAWN_RADIUS` / 核心 HP / `hp_growth` / 三原型表等，改动一律走 ADR 并需拍板。
