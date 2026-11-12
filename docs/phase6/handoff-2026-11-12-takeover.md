# 交接 · 2026-11-12 收口（存档系统与玩法口径批次）

> 本棒：大肥鱼（DSH）。上一会话在 09:28 起跑 `run_shop_interaction_asserts.gd` 时卡住并停摆
> （进程成孤儿、27 分钟满负载），本棒终止该进程、验证并收口其未提交工作。
> 上游：`handoff-2026-11-12-progress.md`（同日进度快照）、`handoff-2026-11-11-card-spec.md`（卡面 v3.2/v3.3）。

## 1. 接手时的现场

| 项 | 状态 |
|---|---|
| HEAD | `1dea4c7 feat(combat): 实装逐塔射程与卡包攻击特效`（**未推送**，本棒推送） |
| 工作区 | 31 个已跟踪改动 + 5 个新文件未提交（约 +743/−228） |
| 停摆点 | `run_shop_interaction_asserts.gd` 09:28 启动后不退出；09:29 后无任何文件改动 |
| 处理 | 确认父进程已消失后 `Stop-Process` 终止；**未改动任何源码逻辑** |

## 2. 本轮验证（收口后工作区）

| 检查 | 结果 |
|---|---|
| 默认回归 `res://tests/run_tests.gd` | **exit 0**（约 4 分 20 秒），各切片失败 0 项 |
| `world` | **15/15 PASS（22.2 s）**，新增 `run_save` 门禁 exit=0 |
| `-- towersprites` | **85/85 PASS** |
| `-- radial8` | **未复跑**；`attrition8` 三条已知红不变，阈值未动 |

日志：`output/takeover-full-2026-11-12.log`（不入库）。
唯一日志噪音是 `shop_interaction` 里 `grab_focus()` 的既有 warning，测试本身通过。

## 3. 提交边界

| 提交 | 内容 |
|---|---|
| `1dea4c7` | 逐塔射程（`tower_range_profiles.gd`）+ 扇形攻击波 / 卡包弹丸演出（前一棒提交，本棒推送） |
| 收口提交 A | 焚祭改「友军阵亡引爆」、机械围城、满塔位仍可购卡、解除触发升级 8 级封顶、逐塔射程文案 |
| 收口提交 B | 卡面稀有度徽记、合成目标高亮（placement marks） |
| 收口提交 C | 三存档位 + 待续关卡 + 主菜单存档管理 + 双击快速合成 + 文档/门禁 |

拆分按依赖顺序：A（玩法/数据）→ B（UI）→ C（存档，依赖 A 的 `restore_preparation` 与 `RunSave`）。

## 4. 存档系统口径

- **三个存档槽** + 当前槽一并写入 `user://profiles.save`；写入先生成同目录临时文件再替换（防半截档）。
- 存档内容：关卡解锁 / 余烬 / 卡包解锁 / 战绩（`campaign` + `run_meta`）。
- **待续关卡**：每个槽一份，`user://suspended_run.save`（槽内嵌 `run` 字段），保存关卡、下一波、所选卡包、
  波表难度、几何槽位、防御塔、背包、废料、商店与随机数状态。**准备阶段保存并退出；战斗中需打完当前波**。
- 入口：主菜单「继续游戏」（显示关卡 + 第 N/M 波，无存档时隐藏）/「存档管理」（新建 / 读取 / 保存 / 删除，
  覆盖与删除走 `salvage_confirm_dialog` 确认）；准备阶段「退出关卡 → 保存并退出」。
- 首次升级：旧版进度（`save.json` + `card_packs.json` + 旧待续记录）导入**存档 1**。
- 门禁：`tests/run_run_save.gd`（写入失败兜底、界面入口、波次恢复）已进 `WORLD_GATES`。

## 5. ⚠️ 待平衡拍板的口径变更

| # | 变更 | 落点 |
|---|---|---|
| 1 | 取消 `TowerEffects.LEVEL_CAP = 8`：登场 / 整备 / 阵亡 / 击杀升级**可无限叠加** | `tower_effects.gd`、`tower-triggers.md` |
| 2 | **机械围城**：波 1–4 怪物数量 ×1.25 / 1.4 / 1.5 / 1.75，单怪 HP ×0.55、攻击 ×0.45，废料预算守恒 | `wave_director.gd::mechanical_siege_enabled` |
| 3 | 逐卡普攻基础半径较首轮配置 **+≈20%**（基准模拟仍用原始射程表） | `tower_range_profiles.gd` |

三条都不是金标本口径（金标本 `wave_sim` / `shop_ai` 未动），但属玩家路线数值；不认可时按提交单独 revert。

## 6. 已知限制

- 准备阶段的拖拽、悬停与选择在恢复时会重置（只恢复数据状态，不恢复输入态）。
- 存档槽切换会重载 campaign / meta；连续切槽未做压力测试，窗口模式手测待做。
- `docs/phase6/tower-range-profiles.md` 与 README / `stage-exit.md` 已同步，但**尚未窗口实机截图验收**。

## 7. 下一步

1. 窗口手测三存档位、存档管理、连续“继续游戏 → 保存并退出”、双击合成。
2. 拍板 §5 的三项口径；处理 `attrition8` 三条已知红（优先修数值）。
3. 跑 CI 第 6–9 步 MC 门禁，确认围城与射程改动的影响面。
4. 重导出 `build/windows/Corebound.exe`（仍是 2026-11-09 旧包）。
