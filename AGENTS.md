# AGENTS.md — 代理入口（Codex / 其他编码代理）

> 这是**工程交接契约**，不是玩家文档。项目全貌见 `README.md`；
> 工程红线见 `docs/architecture/control-manifest.md`；
> 最新功能交接见 `docs/phase6/handoff-2026-11-10-gameplay.md`。
> 前一份 `handoff-2026-11-09.md` 含龙娘回执，保留勿覆盖。

## 硬约束（违反 = 回归红）

1. **金标本是唯一真理**：`scripts/engine/wave_sim*.gd`、`shop_ai.gd`、`run_loop*.gd` 与 300 局 MC 一口不许动；
   玩家路线的差异只允许落在 `shop_runtime.gd` / `wave_director.gd` 的开关后面。
2. **数值口径冻结**：`ATTRITION` / `κ_r` / `AGGRO_R` / 塔位 / `SPAWN_RADIUS` / 核心 HP / `hp_growth` / 三原型表，
   改动必须走 ADR 并拍板，禁止为了让断言变绿而改。
3. **一律 `preload`，不写 `class_name`**：`--headless --script` 没有 `global_script_class_cache`；
   `--script` 指向的文件必须 `extends SceneTree` / `MainLoop`。
4. **浮点**：整数指数走 `FpPow.pow_int()`，移植 Python `sum()` 走 `FpSum.sum_py()`。
5. **提交前按改动范围验证**：
   - 文档改动检查内容、链接和差异即可。
   - 图片等资源替换运行 Godot `--import`，并确认受影响的游戏界面或场景加载并显示正确。
   - 局部 UI 或资源加载改动运行对应专项，覆盖受影响的入口和交互；涉及贴图时同时验证导入与显示。
   - 涉及玩法、数值、模拟、存档、跨模块行为，或专项无法覆盖影响范围时，运行默认 `run_tests.gd`，要求退出码 0（含 `world`）。
   - 用户明确要求的检查照常执行。在提交说明或交接中记录实际运行的验证与结果。

## 环境

- 引擎：Godot `4.7.2-stable`（Steam 版）
  `C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`
- 仓库：`G:\AI Demo\corebound`（`G:\AI Demo` 根目录是空仓库）

## 常用命令

```bash
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

"$GODOT" --headless --path . --script res://tests/run_tests.gd             # 全量回归（含 world，约 4 分钟）
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- world      # 关卡实装套件（~15s）
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- towersprites  # 塔贴图资产守卫
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- radial8    # 含 attrition8 MC
"$GODOT" --headless --path . --import                                        # 改贴图后必须重建 .import
"$GODOT" --path .                                                            # 窗口试玩
```

## 当前状态（2026-11-12 快照，详见 handoff-2026-11-12-progress.md）

- **2026-11-12 快照**：HEAD `9f2d969` 与 `origin/master` 一致，**无待推送提交**；工作区无已跟踪改动，
  只剩未跟踪试稿（`output/`、`art/_review`、`art/2d/sprites_ai_v3`、AI 工具、`.appdata`），按约定不入库。
  本轮实跑默认回归 **exit 0**、`world` **14/14 PASS**（含 `stage_exit`、`card_spec`）、`towersprites` **85/85 PASS**。
  ⚠️ 本机 SSH 22 端口被代理拦截（`kex_exchange_identification`），推送 / 拉取走 HTTPS：
  `git push https://github.com/w814929152/corebound.git HEAD:master`。
- 2026-11-11 晚新增：熔币重炮（每发耗废料）、扇形射程 + 可叠加射程光环（展域塔 +10°/层、延程塔 +2 射程/层，
  光环半径 8）、背包完整展示卡面；卡面 v3.2 / v3.3（精简牌面 + 悬停浮卡）见 `handoff-2026-11-11-card-spec.md`。
  塔原型与贴图已达 **85**（`TOWERS`(3) + `TOWERS_EXT`(82)）。

- 卡面 v3.2（210×340 卡槽 / 插画 ≈70% / 信息区 ≈30% / 卡名 28 · 类型与摘要 14 / 锁左上 · 费用右上）+ 主菜单「怪物图鉴」+ 移除 `1/2/3` 快捷购买（购买只走点击整卡，焦点位随鼠标悬停）：见 `docs/phase6/handoff-2026-11-11-card-spec.md`、`monster-library.md`。默认全量回归 exit 0，`card_spec` 专项（20 项）已进默认回归。**卡组图鉴同步改用同一套竖版卡面**（`scripts/ui/card_face.gd`，7 列网格）。**牌面已精简为「插画 + 卡名 + 类型条 + 一行基础信息」**（如「远程单体」，商店另含价格/锁头），完整机制与数值改由**悬停浮卡**展示（`card_hover.gd` 深色实心面板，商店 0.4s / 图鉴 0.35s 触发）。⚠️ 卡面 14px 是 §9.1「玩家可见文本 ≥16px」的唯一例外，**待拍板**。

- 基地美术 / 十九格禁建区、准备阶段下一波出怪预告、商店背景铺满卡框：见 `docs/phase6/base-and-card-art-2026-11-10.md` 与 `spawn-preview.md`。出怪预告专项已加入默认 world 门禁；其他会话的界面与火焰数值改动继续单独保留。

- 界面「少边框」+ 商店参考图布局（整卡点击购买、210×340 三卡、信息带）+ 航图场景缩略卡，以及焚星塔充能口径（十层引爆计数、上限 10）：见 `docs/phase6/ui-flat-2026-11-10.md`。默认全量回归 **exit 0**、`world` **13 门 PASS（26.7 s）**；`fire_charge` 12 → 10 属数值口径，**待平衡拍板**。

- 准备阶段：玩家路线全塔复活回血、基地满血；可拖拽已部署防御塔免费移位，基地固定，非法落点/战斗/退出暂停拒绝移位。仅含本轮暂存文件的独立版本默认完整回归 exit 0，world PASS（22.6s）；见 `docs/phase6/preparation-recovery-relocation.md`。并行 UI、火焰、出生预告和基地美术未纳入本批。

- 本批美术：确认的俯视箭塔 + 八包独立卡面背景（含包色基座、暗化与轻虚化），卡面保留原版塔插图；接线、预览和验证见 `docs/phase6/arrow-art-rarity-2026-11-10.md`。其他会话的 UI / 关卡图及旧 AI 试稿仍保留未提交。
- 本批提交前验证：当前工作区与仅含暂存文件的独立快照均完成默认完整回归，退出码 0；world 分别 PASS（23.9s / 24.3s）。独立快照商店专项也通过，证明无未提交试稿依赖；退出仍有既有资源清理警告。未推送。

- 已提交商店 UI `2d443c5`；本批收口中文本地化、退出关卡与默认近景，提交号见 Git 日志。
- AI 塔身方案相关素材、工具与记录按用户要求保留未提交，**别 `git add -A`**。
- 本批代码已通过默认完整回归（**exit 0**），`world` **12/12 PASS（20.1 s）**。
- 塔贴图 lint 与 radial8 的历史结果见旧交接；radial8 本批未复跑。
- 🔴 **已知红**：`attrition8` 的 `T-D′`（0.150）/ `T-A1`（0.0600 vs 0.12）/ `T-A2`（0.0845 vs 0.30）。
  二分定位见 `docs/phase3/qg-radial/attrition8-drift-2026-11-10.md`：断点在**卡池扩容**（`1ef5487` → `c1e4c72`，48/80 张卡），
  非「数值再平衡漂移」（`cdf4fc1` 前后读数逐位相同）；**阈值未下调**，待平衡拍板（重标定 or 基准卡池）。
- 塔身现行产线 = `tools/gen_tower_sprites_v2.py`：`TOWERS`(3) + `TOWERS_EXT`(82) = **85 个原型 ↔ 85 张 128² 贴图**；
  新增原型必须重跑生成器 + `--import`。`art/manifest.json` 的 HEAD 格式是 **`indent=1` + 末尾无换行**，别改缩进。
- 玩家路线口径：商店只卖建筑卡（`EFFECT_CARDS_ENABLED=false`）、开局无起手塔 + 30 废料。
- `build/windows/Corebound.exe` 是 2026-11-09 14:24 旧包，**不含**地形/结构攻防，也不含新塔贴图。

## 下一步（建议顺序）

1. 处理 `attrition8`（先查数值，再考虑 ADR 重标定），跑 CI 第 4 步复验。
2. 跑 CI 第 6–9 步 MC 门禁，确认数值漂移影响面。
3. 窗口试玩中文界面、退出确认与 200% 近景。
4. 数值表稳定后全量重跑塔贴图生成器并刷新预览（当前总览是 81 张快照）。
5. 决定 AI 版是否落地；用 Steam 版 Godot 重导出 Windows 包。
6. 推送：2026-11-12 已与 origin 同步（HEAD `9f2d969`）；本机 SSH 22 被代理拦截，推送走
   `git push https://github.com/w814929152/corebound.git HEAD:master`。

## 关键文件

| 用途 | 路径 |
|---|---|
| 关卡数据（地块/障碍/入口） | `scripts/data/battlefield_maps.gd` |
| 地形 / 镜头 / 导航 | `scripts/ui/battlefield_terrain.gd`、`battlefield_camera.gd`、`battlefield_navigation.gd` |
| 怪物攻塔攻核 | `scripts/gameplay/wave_director.gd`（`structure_attacks_enabled`） |
| 逐塔判距 | `scripts/gameplay/tactical_combat.gd` |
| 商店口径 | `scripts/gameplay/shop_runtime.gd`（`EFFECT_CARDS_ENABLED`） |
| 开局废料 | `scripts/engine/mvp_config.gd`（`PLAYER_STARTING_SCRAP`） |
| 默认回归 + world | `tests/run_tests.gd`（`WORLD_GATES`） |
| 塔身贴图产线 / 守卫 | `tools/gen_tower_sprites_v2.py`、`tests/lint_tower_sprites.gd` |
| 最新功能交接 | `docs/phase6/handoff-2026-11-12-progress.md`（进度快照）；功能细节 `handoff-2026-11-11-card-spec.md`、`handoff-2026-11-10-gameplay.md`；旧文 `handoff-2026-11-09.md` 保留龙娘回执，勿覆盖 |
