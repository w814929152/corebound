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
5. **提交前必须**：`run_tests.gd` 退出码 0（现在默认包含 `world`，约 4 分钟）。

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

## 当前状态（2026-11-10，详见 handoff-2026-11-10-gameplay.md）

- 已提交商店 UI `2d443c5`；本批收口中文本地化、退出关卡与默认近景，提交号见 Git 日志。
- AI 塔身方案相关素材、工具与记录按用户要求保留未提交，**别 `git add -A`**。
- 本批代码已通过默认完整回归（**exit 0**），`world` **12/12 PASS（20.1 s）**。
- 塔贴图 lint 与 radial8 的历史结果见旧交接；radial8 本批未复跑。
- 🔴 **已知红**：`attrition8` 的 `T-D′`（0.0 应 0.150）/ `T-A1`（0.0600 vs 0.12）/ `T-A2`（0.0845 vs 0.30）。
  已在干净 `HEAD 7b3ffe4` 复现 → 非本轮引入，属数值再平衡后的漂移；**阈值未下调**，待平衡拍板。
- 塔身现行产线 = `tools/gen_tower_sprites_v2.py`：`TOWERS`(3) + `TOWERS_EXT`(79) = **82 个原型 ↔ 82 张 128² 贴图**；
  新增原型必须重跑生成器 + `--import`。`art/manifest.json` 的 HEAD 格式是 **`indent=1` + 末尾无换行**，别改缩进。
- 玩家路线口径：商店只卖建筑卡（`EFFECT_CARDS_ENABLED=false`）、开局无起手塔 + 30 废料。
- `build/windows/Corebound.exe` 是 2026-11-09 14:24 旧包，**不含**地形/结构攻防，也不含新塔贴图。

## 下一步（建议顺序）

1. 处理 `attrition8`（先查数值，再考虑 ADR 重标定），跑 CI 第 4 步复验。
2. 跑 CI 第 6–9 步 MC 门禁，确认数值漂移影响面。
3. 窗口试玩中文界面、退出确认与 200% 近景。
4. 数值表稳定后全量重跑塔贴图生成器并刷新预览（当前总览是 81 张快照）。
5. 决定 AI 版是否落地；用 Steam 版 Godot 重导出 Windows 包。
6. 推送本地提交（需用户明确要求；领先数量以 Git 为准）。

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
| 最新功能交接 | `docs/phase6/handoff-2026-11-10-gameplay.md`；旧文 `handoff-2026-11-09.md` 保留龙娘回执，勿覆盖 |
