# 十关关卡实装（2026-11-09）

主线沿用 `campaign-v2-overseer.md` 的十关图状推进、七地区卡包、149 波；不恢复已被取代的旧三章关卡表。

## 玩家路线

- `boot.gd` 开启 `WaveDirector.tactical_combat_enabled`；基准模拟器及默认导演仍使用原伤害池。
- 普通攻击逐塔寻找射程内距核心最近的敌人，溢出仅在同一射程内结转；没有目标时不存储伤害。
- 伤害继续复用 `DamageEngine` 的建筑等级、攻速、类型和构筑乘区。真实判距后移除平均 Coverage 折扣，避免重复计算覆盖损失。失能塔不输出。
- 持续伤害改为由各来源塔向射程内敌人结算；火焰与冰冻继续走现有的范围状态系统。
- 除教学关外，每个入口使用相同的来敌配额，窄入口因此有更高局部密度。映射确定性、不消耗 RNG，不改变怪物数量、血量和行进时钟。0-1 保留基准出生角。
- 地形约束建造区域；岩脊不额外阻挡射线，不引入绕路寻路。

## 关卡体验

- `stage_briefings.gd` 集中维护十关地形特点、战术提示与通关文案。
- 航图按真实前置绘制分支路线，显示战术说明，锁定提示读取真实的任一前置和地区数量门槛。
- 初始准备阶段显示关卡目标，玩家仍从核心与 30 金币开始，自行购买、放塔并确认开战。开战后收起战术正文。
- 胜利结算显示地区科技和本次解锁的全部区域，终局展示结局；重复通关不重复宣称获得新科技。
- 结算通过“返回航图”回到选关，关闭旧结算节点。

## 验证

`tests/run_stage_implementation_asserts.gd` 覆盖逐塔射程、抗性、溢出、失能、持续伤害、十关入口分配、真实场景准备与手动开战、科技奖励与解锁提示。

`tools/verify_stage_regression.gd` 包装现有聚合回归，并在测试后恢复玩家存档。

### 门禁读数（2026-11-09 复跑）

| 套件 | 读数 |
|---|---|
| `run_stage_implementation_asserts.gd` | 6140 checks / 0 failures |
| `run_battlefield_maps_asserts.gd` | 288450 checks / 0 failures（十关地面 / 障碍 / 建塔 / 入口 / 攻核路线） |
| `run_battlefield_navigation_asserts.gd` | 47 checks / 0 failures（三档视口缩放 / 拖动 / UI 手势隔离） |
| `run_structure_attacks_asserts.gd` | 19 checks / 0 failures |
| `run_preparation_asserts.gd` / `run_battle_start_asserts.gd` | 准备阶段 / 50 seeds 开局（核心 + 30 废料 → 买 → 落子） |
| `run_shop_overlay_asserts.gd` / `run_shop_interaction_asserts.gd` | 三档窗口商店覆盖层 / 键盘与拖放交互 |

以上 11 个脚本组成 `world` 组：`tests/run_tests.gd -- world` 可单跑，默认无参回归也会串行拉起（约 20 s）；任一子脚本非零退出 = 门禁红。

`world` 组接线时同步了两条旧契约：`run_ui_style_asserts.gd` 的放置入口改判底部背包、`run_vfx_cache_guard.gd` 的「抽屉占宽 → 中心左移」改为「浮层不移动地图坐标 + 缓存键必须含中心」。

> 🟡 **已知红（非本轮引入）**：`attrition8` 的 3 条 MC 判据在 `HEAD 7b3ffe4` 干净工作树上同样复现 —— `T-D′` 全程塔死 0.0（应 0.150）/ `T-A1` hit 0.0600（阈值 0.12）/ `T-A2` hit_fail 0.0845（阈值 0.30）。属数值再平衡后的镜像指标漂移，待平衡侧拍板（重标定或修数值），**未下调阈值**。

## 当前边界

普通攻击仍采用每 0.1 秒的连续伤害，投射物是视觉反馈。弹射、贯穿、溅射和团队光环仍复用原有构筑乘区，未改成逐个弹体碰撞或局部光环。此次实现改变了玩家关卡中的有效输出时间与敌人空间分布，旧 MC 胜率不再代表该玩家路线，需另行进行平衡测试。
