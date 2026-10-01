# 切片4 · 接线完整商店逻辑 —— 架构与接线清单

- **作者**：程基岩（工程主理人）
- **引擎**：Godot `v4.7.2.stable.official.ed1daf0bf`（沿用切片3 实测结论）
- **上游**：`design/gdd/shop-reroll.md` **v1.2**（§2.5 刷新经济 · §2.6 锁定 · §2.7 三类卡分流 · §2.8 pity P1–P4）· `design/gdd/card-system.md` v1.1.5（§4.5 pity · §3.6 **5 槽 = 5 卡种非 5 层**）· `design/gdd/wave-spawner.md`（§7 交接点 I-4 / I-5 · §2.9 安全窗）
- **依赖**：切片2 `scripts/engine/shop_ai.gd`（**完整商店逻辑，本轮只复用、零修改**）· 切片3 五态时钟（`time_state_machine.gd` / `time_director.gd`）
- **状态**：🟢 全量自测 **222 + 2228 + 142 + 123 = 2715 项断言 / 0 失败 / 退出码 0**；场景冒烟 46 项全过（headless + 窗口）；切片3 冒烟 25 项回归全过；MC 判据链逐位不变（A 69.3% / B 91.3%）

---

## 0. 摘要（给赶时间的人）

| 验收项 | 结果 |
|---|---|
| 窗口模式可交互（开店 / 买 / 刷 / 锁 / 放置 / 波次推进） | ✅ 场景冒烟 46 项全过 + 截帧 `docs/phase3/slice4-shop.png` |
| headless 不回归 | ✅ 2715 项 / 0 失败 / 退出码 0 |
| pity 仅初始商店保底（P1）、手动 reroll 纯随机 | ✅ 200 次初始发牌 100% 含保底卡；6000 次 reroll 出现率 0.432 vs 纯随机基线 0.428（Δ0.4pp） |
| 锁定（3 位锁 1 · 刷新保留 · 每波重置） | ✅ |
| 刷新成本 5+3n 递增 + 下限 1 分 | ✅ 5/8/11/14/17/20，累计 5/13/24/38/55/75 |
| 三类卡分流 | ✅ 建筑卡→待放置队列 / 单塔效果卡→投主塔（层数+1 不占新槽）/ 全局卡→立即生效 |
| 5 槽 = 5 卡种非 5 层 | ✅ 同卡连买 4 张：卡种数不变、层数 4 |
| 判据链（MC 起飞率）不回归 | ✅ shop_ai **零修改**；决定性判据链逐位复现（A W8 / B W12 / B÷A 0.458 / flips 1） |

**本轮四个新发现的真实冲突（🔴 未擅改口径，待主理人拍板）**：见 §5 与 `docs/phase3/slice4-verify.md` §6。

---

## 1. 本轮范围

| 做 ✅ | 不做 ❌ |
|---|---|
| I-1 波次信号接线（`wave_started` → 发牌+pity；`wave_ended` → 收入入账） | 完整刷怪战斗循环（后续切片） |
| I-2 商店意图接线（buy / reroll / lock → `shop_ai` 的扣费/发牌/执行） | 美术资产 / 音效 / 存档 |
| I-3 商品位真实卡面（卡名 / 卡种 / 价格 / H1 / H8 / H4） | C2 高亮的 H2–H9（本轮只做 H1 + H8 + H4） |
| I-8 放置确认（待放置队列 → 放置模式 → 落子） | 弃卡 / 卸下改投 / 拆除回收（按钮已置灰占位，🟡 后续切片） |
| 待放置队列 HUD（蓝图 + 张数 + 放置入口） | 二次确认弹窗（I-9，随拆除回收一起做） |

---

## 2. 分层与数据流

```
┌─────────────────────────────────────────────────────────────────────┐
│  scripts/ui/（不持有游戏状态，control-manifest §5）                  │
│    shop_overlay.gd   只读 runtime.snapshot() → 渲染卡面/价格/H1      │
│    hud.gd            只读 runtime.snapshot() → 积分/核心HP/队列读数   │
│    time_director.gd  时钟 SSOT + 输入 → 发**意图信号**（切片3 原样）  │
└───────────────┬─────────────────────────────────────────────────────┘
                │ 意图：reroll_requested / buy_requested / lock_toggled
                │       placement_confirmed(slot) / placement_cancelled
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  scripts/gameplay/shop_controller.gd   (Node · ALWAYS)  ← 本轮新增   │
│    唯一的桥：意图信号 → ShopRuntime；Runtime 快照 → UI（shop_changed）│
│    + 🟡 最小波次驱动器（wave_dur(w) 游戏时钟计时 → wave_end(w)）      │
└───────────────┬─────────────────────────────────────────────────────┘
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  scripts/gameplay/shop_runtime.gd   (RefCounted · 零引擎副作用)      │
│    持有：cfg / player / rng / scrap / core_hp / offers / pending /   │
│          rerolls / lock_index / counts                               │
│    复用 ShopAI：draw_offers / pity_card / action_cost / apply_action │
│    复用 WaveSim：simulate_wave（战前 DPS 结算，R1 口径）             │
└─────────────────────────────────────────────────────────────────────┘
```

**为什么 `shop_runtime.gd` 放 `scripts/gameplay/` 而不是 `engine/`**：control-manifest §5 把 `engine/` 定义为"纯函数、不持有游戏状态"；本轮第一次出现了**持有一局状态**的代码，落进为它预留的 `gameplay/` 层（数据驱动：数值只读 `MvpConfig` / `TowerData`，层内零硬编码口径）。

### 2.1 信号接线表（I-2 逐条）

| `TimeDirector` 信号 | `ShopController` → `ShopRuntime` | 备注 |
|---|---|---|
| `wave_started(w)`（I-1） | `simulate_wave_result(w)` 存战前结算 → `start_wave(w)`（n←0 / 锁定清空 / 发初始商店+pity） | 🔴 R1：本波打的是上波买出来的构筑 |
| `wave_ended(w)`（I-1） | `grant_wave_result()`（击杀收入 ×(1+income_mult)、漏怪扣核心 HP） | M5：商店不产出积分 |
| `reroll_requested()` | `reroll()`：扣 `5+3n−disc` → n+1 → 纯随机重抽（锁定位保留） | 🔴 **不走 pity**（GDD §2.8.1） |
| `buy_requested(slot)` | `buy(slot)`：扣费 → 三类分流 | 见 §3 |
| `lock_toggled(slot)` | `toggle_lock(slot)` | 3 位锁 1（MAX_LOCK）；🟡 已锁 A 再锁 B = 改锁 B |
| `placement_confirmed(slot)` | `confirm_placement(slot)` → `apply_action(["build"/"up", …])` | CD-D：New/Upgrade/Invalid |
| `placement_cancelled` | `cancel_placement()` | 🔴 取消不退款，卡留队列 |

## 3. 三类卡分流（GDD §2.7 → 实现对照）

| 卡种 | 金标本动作 | 本轮落点 | 占用 |
|---|---|---|---|
| **建筑卡**（Arrow/Cannon/Frost，12 分） | `["build", nm, slot, null]` | 买 → `pending.append(nm)`（**不落塔**）；放置 → `confirm_placement(slot)` 时才 `apply_action`（空位=build 新建 h=1 / 同原型=up 层数+1 / 异原型=Invalid 不落子不退卡） | 不占塔位、不占强化槽（直到落子） |
| **单塔效果卡**（FireUp/FrostUp，9 分） | `["reinf" / "reinf_new" / "reinf_swap", …]` | 直接 `apply_action`，宿主 = 主塔（`core_tower_slot()`，与 `pity_card` 的 S2 同判据） | 强化槽计**卡种**（`player.cards` 字典 = 5 槽），层数走 `attach[name]` |
| **全局效果卡**（ScrapUp/RerollD，10 分） | `["econ", …]` | ScrapUp：`income_mult += 0.20`（`apply_action`）；RerollD：**+0%**（金标本 `reroll_disc` 无增加路径，见 §5 D-4） | 全局槽（E7/H4：饱和后仍可购买，标「已达上限 (+0%)」） |

**置灰只有两种理由（X6 合规）**：H1 买不起（`scrap < price`）与 H8 无合法目标（E1 塔位满且无同原型 / E9 场上无塔 / D-8① 主塔不接收异 Tag）。H4「已达上限 (+0%)」**不置灰**（GDD：仍可购买）。

## 4. 关键实现决策

| # | 决策 | 理由 |
|---|---|---|
| 1 | **`shop_ai.gd` 一行未改**，全部复用（发牌/保底/扣费/执行/结算） | 金标本逐位对齐产物；改一个字就要重跑 MC。判据链回归由自测 §8 直接反证 |
| 2 | 手动 reroll 用 `draw_offers(rng, k, null)`（force=null） | GDD §2.8.1「手动 reroll 不保底」。金标本 `shop_phase()` 的刷新带 pity（D-1）——那条路径本轮不动，MC 不受影响 |
| 3 | `pity_card()` 即兜底链 P1/P3/P4；**P2 未补** | 补 P2 会改 MC 发牌序列。已登记待拍板（D-5） |
| 4 | 商品位按**实际去重位数**渲染（≤3），3 个物理位恒在 | 金标本 `draw_offers` 返回去重集合，实测 40% 波次不足 3 位（D-2，待拍板） |
| 5 | 最小波次驱动器复用 `WaveSim.simulate_wave()` 结算收入 | 不新造数值：收入/漏怪与金标本同一套公式；波次时长用冻结的 `wave_dur(w)` |
| 6 | `time_director.exit_placement(confirmed, slot=-1)` 加可选参 | I-8 要把落子塔位带给 `placement_confirmed`；默认值 -1 保持切片3 调用兼容 |
| 7 | `[调试] 结束本波` 按钮（HUD）+ `controller.debug_end_wave()` | 战斗未实现前，波次只是"空转的时长"；收入仍按战前 DPS 结算。wave-spawner 落地即删（D-8） |
| 8 | 玩法状态只在 `ShopRuntime`；UI 只读 `snapshot()` | control-manifest §5：UI 不持有游戏状态；商店只发意图（SR-5 / CD-E） |

## 5. 🔴 与 GDD / 金标本的已知分歧（全部**未擅改**，待拍板）

| # | 分歧 | 现状与影响 |
|---|---|---|
| **D-1** | GDD §2.8「手动 reroll 不保底」vs 金标本 `shop_phase()` **每次刷新都带 pity**（`shop_ai.gd` L372-374） | 本轮手动路线按 GDD 走；`shop_phase()` 未动 → MC 判据链不变。**后果：AI 贪心路线与玩家手动路线的发牌口径不一致**。若拍板让 `shop_phase()` 也改仅初始保底 → 需重跑 MC |
| **D-2** | GDD A4「商品位恒为 3」vs 金标本 `draw_offers` 去重集合（实测 2000 次发牌：1 位 2.1% / 2 位 38.0% / 3 位 59.9%） | 本轮 UI 按实际位数渲染（≤3），不改金标本。出路：① 改 GDD 允许 ≤3 位；② 金标本改不去重（改 RNG 消耗 → 重跑 MC）；③ 补位显示 |
| **D-3** | 刷新折扣口径：金标本 S6 `max(1, 5+3n−disc)` vs GDD §2.5 `max(1, floor((5+3n)×(1−disc)))` | discount=0 时逐位相同；disc=0.50、n=0 时金标本 4.5 分 / GDD 2.0 分。MVP 无折扣来源时无影响 |
| **D-4** | **RerollD 是空卡**：金标本 `reroll_disc` 恒 0（全工程无任何增加路径） | 本轮按 H4「已达上限 (+0%)」：仍可购买、扣 10 分、效果 +0%（不新增第三种植灰理由，X6）。待拍板：补 G2 供应链数值（新数值，需设计侧给）或从池中移除 |
| **D-5** | pity 兜底链 **P2 未实现**（主塔中性但全场有 Tag 投入 → 应保 argmax_Tag 的卡） | 金标本只有 P1/P3/P4。中性塔主塔的局永远吃不到保底。补 = 改 MC，待拍板 |
| **D-6** | **金标本没有锁定机制**（`shop_ai`/`player_state` 无 locked 字段） | 锁定是本轮新增的 UI 侧状态；SR-R4 在本轮实现里成立（锁定位刷新保留、不被 pity 覆盖——因手动路线本就不发 pity） |
| **D-7** | 金标本有**火焰库存摩擦**（`fire_stock` A=6/B=3 每波），GDD 未定义 | 手动路线未实现该上限（GDD 无此规则）。待拍板：玩家路线要不要同样限流 |
| **D-8** | `[调试] 结束本波` 是本轮新增的调试入口 | 非游戏机制、不产生新数值；wave-spawner 落地即删 |
| **D-9** | GDD §2.7「单塔效果卡可先点选副塔再买（2 次输入）」未实现 | 依赖战场塔点选（I-7 SubViewport 未做）；本轮主塔不接收异 Tag 时直接 H8 置灰 |

## 6. 交付文件索引

| 文件 | 作用 |
|---|---|
| `scripts/gameplay/shop_runtime.gd` | 🆕 商店运行时（UI 侧商店状态 + 三类分流 + pity/锁定/刷新，复用 shop_ai） |
| `scripts/gameplay/shop_controller.gd` | 🆕 接线层（意图信号 → Runtime）+ 🟡 最小波次驱动器 |
| `scripts/ui/shop_overlay.gd` | 修改：商品位真实卡面（卡名/卡种/价格/H1/H8/H4）+ 待放置队列 + 放置塔位按钮 |
| `scripts/ui/hud.gd` | 修改：积分/核心HP/队列读数 + `[调试] 结束本波` |
| `scripts/ui/battle_shop.gd` | 修改：创建 `ShopController` 并注入 UI（依赖注入，延续切片3 模式） |
| `scripts/ui/time_director.gd` | 修改：`exit_placement(confirmed, slot=-1)` 加可选参（向后兼容） |
| `scripts/ui/boot.gd` / `tests/run_tests.gd` | 修改：接入切片4 自测 |
| `tests/test_suite_slice4.gd` | 🆕 切片4 自测（123 项） |
| `tests/run_slice4_scene_smoke.gd` | 🆕 真场景接线冒烟（46 项，headless + 窗口） |
| `docs/phase3/slice4-*.log` / `slice4-verify.md` / `slice4-shop.png` | 证据与验证报告 |

## 7. 跑法

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 全量自测（切片1+2+3+4，含 MC 300 局，约 1.5 分钟）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd
# 只跑切片4
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice4
# 切片4 场景冒烟（headless / 窗口均可，窗口会截帧到 docs/phase3/slice4-shop.png）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_slice4_scene_smoke.gd
# 窗口模式人工试玩（Tab 开店 · R 刷 · 1/2/3 买 · Space 锁 · 点「放置」→ 点塔位落子）
"$GODOT" --path D:/roguedemo
```
