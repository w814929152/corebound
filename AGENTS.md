# AGENTS.md — 代理入口（Codex / 其他编码代理）

> 这是**工程交接契约**，不是玩家文档。项目全貌见 `README.md`；
> 工程红线见 `docs/architecture/control-manifest.md`；
> 最近一次交接的完整状态见 `docs/phase6/handoff-2026-11-09.md`。

## 硬约束（违反 = 回归红）

1. **金标本是唯一真理**：`scripts/engine/wave_sim*.gd`、`shop_ai.gd`、`run_loop*.gd` 与 300 局 MC 一口不许动；
   玩家路线的差异只允许落在 `shop_runtime.gd` / `wave_director.gd` 的开关后面。
2. **数值口径冻结**：`ATTRITION` / `κ_r` / `AGGRO_R` / 塔位 / `SPAWN_RADIUS` / 核心 HP / `hp_growth` / 三原型表，
   改动必须走 ADR 并拍板，禁止为了让断言变绿而改。
3. **一律 `preload`，不写 `class_name`**：`--headless --script` 没有 `global_script_class_cache`；
   `--script` 指向的文件必须 `extends SceneTree` / `MainLoop`。
4. **浮点**：整数指数走 `FpPow.pow_int()`，移植 Python `sum()` 走 `FpSum.sum_py()`。
5. **提交前必须**：`run_tests.gd` 退出码 0（现在默认包含 `world` 11 套，约 4 分钟）。

## 环境

- 引擎：Godot `4.7.2-stable`（Steam 版）
  `C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`
- 仓库：`G:\AI Demo\corebound`（`G:\AI Demo` 根目录是空仓库）

## 常用命令

```bash
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

"$GODOT" --headless --path . --script res://tests/run_tests.gd          # 全量回归（含 world）
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- world # 关卡实装 11 套（~20s）
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- radial8
"$GODOT" --path .                                                       # 窗口试玩
```

## 当前状态（2026-11-09）

- 功能提交 `bb1e18f`（其上是本交接的 docs 提交），`master` 领先 origin **36 个提交未推送**，工作区干净。
- 默认回归 **exit 0 全绿**；`world` 11/11 PASS；radial8 **8/9**。
- 🔴 **已知红**：`attrition8` 的 `T-D′`（0.0 应 0.150）/ `T-A1`（0.0600 vs 0.12）/ `T-A2`（0.0845 vs 0.30）。
  已在干净 `HEAD 7b3ffe4` 复现 → 非本轮引入，属数值再平衡后的漂移；**阈值未下调**，待平衡拍板。
- 玩家路线口径：商店只卖建筑卡（`EFFECT_CARDS_ENABLED=false`）、开局无起手塔 + 30 废料。
- `build/windows/Corebound.exe` 是 14:24 旧包，**不含**本轮地形/结构攻防。

## 下一步（建议顺序）

1. 处理 `attrition8`（先查数值，再考虑 ADR 重标定）。
2. 跑 CI 第 6–9 步 MC 门禁，确认数值漂移影响面。
3. 用 Steam 版 Godot 重导出 Windows 包。
4. 推送 36 个提交（需用户确认）。

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
| 交接全文 | `docs/phase6/handoff-2026-11-09.md`（§9 = 龙娘回执，接手后勾选） |
