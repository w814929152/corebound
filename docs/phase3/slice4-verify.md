# Phase 3 · 切片4：接线完整商店逻辑 — 验证报告

- **作者**：程基岩（工程主理人）
- **引擎**：Godot `v4.7.2.stable.official.ed1daf0bf`（沿用切片3 实测结论，本轮无新引擎风险）
- **判据**：`design/gdd/shop-reroll.md` **v1.2**（§2.5 刷新经济 · §2.6 锁定 · §2.7 三类卡分流 · §2.8 pity P1–P4）· `design/gdd/card-system.md`（§4.5 pity · §3.6 **5 槽 = 5 卡种非 5 层** · §7.2.2）· `design/gdd/wave-spawner.md`（§7 I-4/I-5 · §2.9 安全窗）· `docs/architecture/control-manifest.md`（冻结口径 / N1-N2 / P1-P8 / G1-G8）
- **结论**：🟢 **验收全达成，切片1/2/3 零回归**
  - 全量回归 **222 + 2228 + 142 + 123 = 2715 项断言 / 0 失败 / 退出码 0**
  - 切片4 场景冒烟 **46 项 / 0 失败**（headless + 窗口模式各跑一遍，窗口截帧 `slice4-shop.png`）
  - 切片3 场景冒烟回归 **25 项 / 0 失败**
  - **`scripts/engine/shop_ai.gd` 一行未改**（"接线，不是重写"）；MC 判据链逐位不变（A 69.3% / B 91.3%）
- **架构文档（主交付）**：`docs/architecture/slice4-shop-wiring-architecture.md`
  - 🔴 **9 项真实冲突（D-1…D-9）**已登记未擅改，~~待主理人拍板~~ → ✅ **已全部拍板（2026-09-30）**，见本报告 §6 与 `shop-reroll` §9.2（v1.3）。**全部零连锁重跑 MC。**

---

## 1. 接线清单（本轮交付了什么）

### I-1 波次信号接线 ✅

| 信号 | 落点 | 证据 |
|---|---|---|
| `wave_started(w)` | `simulate_wave_result(w)` 存战前结算 → `start_wave(w)`：n←0 / 锁定清空 / `draw_offers(rng, k, pity_force())` 发初始商店 | 单测 §8 + 冒烟 §0/§3 |
| `wave_ended(w)` | `grant_wave_result()`：击杀收入 ×(1+income_mult) 入积分、漏怪扣核心 HP → 进 SafeWindow | 冒烟 §2：W1 = 25 分入账 |
| 🟡 最小波次驱动器 | `ShopController._process`：`wave_dur(w)` 游戏时钟计时到点 `director.wave_end(w)`；复用 `WaveSim.simulate_wave` 结算（不新造数值） | 无真实刷怪（后续切片），`[调试] 结束本波` 按钮可手动收波（D-8） |

**同节奏重置三连**（冒烟 §3 实测）：下一波 预算 20 / n←0 / 锁定清空，三者一次到位。

### I-2 商店意图接线 ✅（`ShopController` = 唯一的桥）

| `TimeDirector` 信号 | `ShopRuntime` 行为 | 实测 |
|---|---|---|
| `reroll_requested()` | 扣 `max(1, 5+3n−disc)` → n+1 → `draw_offers(rng, k, null)` **纯随机不保底**，锁定位保留 | 成本 5/8/11/14/17/20；6000 次出现率 0.432 vs 纯随机基线 0.428（Δ0.4pp）；E5 买不起拒绝且积分不为负 |
| `buy_requested(slot)` | 扣费 → **三类分流**（见 §3） | 冒烟 §4：建筑卡 −12 / 单塔卡 −9 / 全局卡 −10 逐条对上 |
| `lock_toggled(slot)` | 3 位锁 1（MAX_LOCK=1）；同位再按=解锁；已锁 A 再锁 B=改锁 B；每波重置 | 单测 §3 共 10 项；SR-R4 成立（手动路线本就不发 pity，锁定位刷新保留原卡） |
| `placement_confirmed(slot)` | `apply_action(["build"/"up", …])`：空位=新建 h=1 / 同原型=升级 h+1 / 异原型=Invalid 不落子不退卡 | 单测 §5 + 冒烟 §5 |
| `placement_cancelled` | 卡退回队列、不退款 | 单测 §5 |

### I-3 商品位真实卡面 ✅（🔴 X3 合规）

- 卡名 / 卡种标签 / 价格 / H1 可买性（价格色 C_ACCENT↔C_DIM、买按钮 disabled）/ H8 置灰理由 / H4「已达上限 (+0%)」全部真数据渲染；
- 🔴 **三商品位尺寸完全一致**：单一 `const SLOT_SIZE := Vector2(150, 190)`（grep 测试：恰 1 处定义、1 处引用）；真场景实测三位 `custom_minimum_size` 均为 `(150.0, 190.0)`；截帧肉眼可验三位同宽同亮（无布局暗示推荐，C-3/SR-R2 grep 五文件零命中）；
- 事件驱动刷新（`shop_changed`/`run_changed` → `_refresh_shop()`），**非逐帧轮询**（SR-6）。

### I-8 放置确认 + 待放置队列 HUD ✅（第二优先级，本轮一并交付）

队列 HUD（蓝图名 + 张数 + 「放置」按钮）→ `request_placement(idx)` → `enter_placement()`（**先调用后验证实际态**，`void` 返回值不误判）→ 抽屉收起 → 点塔位 `exit_placement(true, slot)` 落子。冒烟 §5 全过。

---

## 2. 三类卡分流验证 ✅（任务点名必答）

| 卡种 | 价格 | 分流落点 | 实测证据 |
|---|---|---|---|
| **建筑卡** Cannon/Arrow/Frost | 12 | ① 买→**待放置队列**（塔数不变、不占强化槽）；放置时 空位新建 / 同原型升级 / 异原型拒 | 单测 §5：买后塔数仍 1 → 落子后 2；升级 h=2；非法目标不落子、卡留队列 |
| **单塔效果卡** FireUp/FrostUp | 9 | ② **立即投主塔**（宿主判据 = `core_tower_slot()`，与 pity_card 的 S2 同款）→ `apply_action` 层数+1，**强化槽计卡种** | 单测 §5/§6：装配后强化槽 2；D-8① 主塔 fire 拒 frost（"主塔不接收该 Tag"置灰）；E9 无塔置灰 |
| **全局效果卡** ScrapUp/RerollD | 10 | ③ **立即生效**：ScrapUp `income_mult += 0.20`；RerollD +0%（空卡，见 D-4） | 单测 §5：income_mult 0→0.20；H4 RerollD 仍可购买（不新增第三种植灰理由，X6） |

**置灰只有两种理由（X6）**：H1 买不起 / H8 无合法目标（E1 塔位满且无同原型、E9 无塔、D-8① 异 Tag）。E1 实测：塔位 6/6 时建筑卡理由="塔位已满"。

**5 槽 = 5 卡种非 5 层（card-system §3.6）** ✅：同卡（FireUp）连买 4 张 → `player.cards` 卡种数**不变**、`attach` 层数 = 4；换 FrostUp 才占新槽。

---

## 3. 验收标准逐条对照

### ① 窗口模式可交互 ✅

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --path D:/roguedemo --script res://tests/run_slice4_scene_smoke.gd   # EXIT=0，46/0，截帧
"$GODOT" --path D:/roguedemo                                                   # 人工试玩入口
```

| 跑法 | 退出码 | 结果 |
|---|---|---|
| 场景冒烟 · headless | **0** | 46 项 / 0 失败 |
| 场景冒烟 · **窗口模式** | **0** | 46 项 / 0 失败 + 截帧 `docs/phase3/slice4-shop.png`（1920×1080） |
| 人工试玩 | — | Tab 开店 · R 刷 · 1/2/3 买 · Space 锁 · 点「放置」→ 点塔位落子 · `[调试] 结束本波` 收波 |

截帧可验（见 `slice4-shop.png`）：三商品位 Cannon 12 分 / FireUp 9 分 / ScrapUp 10 分同尺寸同亮度；`刷新 R（11 分 · 已刷 2 次）`递增口径；待放置队列 (0)；重决策三按钮在非安全窗置灰（T-C1/E16，可见不隐藏）；HUD 积分/待放置/强化槽 2/5/塔 2/6 实时读数。

### ② headless 不回归 ✅

```
$ "$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- all
919:  汇总：通过 222 项 / 失败 0 项        ← 切片1（原样）
1001: 汇总：通过 2228 项 / 失败 0 项      ← 切片2（原样，含 MC 300 局）
1146: 汇总：通过 142 项 / 失败 0 项       ← 切片3（原样）
1315: 汇总：通过 123 项 / 失败 0 项       ← 切片4（新增）
EXIT=0
```

完整输出：`docs/phase3/slice4-full-run.log`（基线对照 `slice4-baseline-run.log`：改动前后汇总行号、断言数完全一致）。

### ③ pity / reroll / 锁定 / 成本 / 分流 / 5 槽 断言 ✅（新增 123 项）

| 段 | 内容 | 项数 |
|---|---|---|
| 1 | pity 只在**每波初始商店**：P3 起手无塔不保底、P4 中性主塔不保底、P1 fire/frost 主塔保对应 Tag 卡、A1 200 次发牌 100% 含保底卡；🟡 P2 登记未实现 | 9 |
| 2 | 手动 reroll 纯随机：6000 次出现率 0.432 vs 基线 0.428（±3pp 内）、绝非每刷必中（<0.60） | 2+前置 |
| 3 | 锁定：MAX_LOCK=1 / 保留原位 / 改锁 / 解锁 / 越界拒 / Q-SR4 每波重置（锁定+次数） | 10 |
| 4 | 刷新成本 5/8/11/14/17/20、累计 5/13/24/38/55/75、折扣下限 1 分、E5 拒刷不扣负 | 25 |
| 5 | 三类分流全链 + 价格 12/9/10 + I-8 放置三态 + D-8①/E9/E1 置灰 + H4 | 38 |
| 6 | 5 槽 = 5 卡种：同卡 4 连买层数 4 卡种不变；换卡才占槽；backpack=5 | 10 |
| 7 | 商品位数恒 ≤3（2000 次发牌越界 0）+ 🟡 去重分布实测登记（D-2） | 3 |
| 8 | I-1 波次接线（预算/n/锁定同节奏）+ W1 结算收入 25 分（M5）+ **决定性判据链复现** | 22 |
| 9 | 🔴 C-3/SR-R2 grep「推荐/最优/best/recommend/suggest」五文件零命中 | 5 |
| 10 | 🔴 X3 尺寸常量 grep（恰 1 处定义、1 处引用、恒 3 位） | 3 |
| | **合计** | **123** |

另：场景冒烟 `tests/run_slice4_scene_smoke.gd` 46 项（真场景树 + 真信号，覆盖单元测试够不着的 I-1 事件链 / X3 真实像素 / T-C1 置灰 / UI 文本）。

### ④ MC 判据链不回归 ✅（任务点名必答）

`shop_ai.gd` **零修改**（diff 为空），且两条独立证据：

1. **全量 MC**（改动前后各一次）：A 起飞率 **69.3%** / 中位 W8.0；B 起飞率 **91.3%** / 中位 W13.0 —— 与基线逐字相同；
2. **决定性判据链**（`Stats.eval_point`，切片4 单测 §8 逐位断言）：判据① A 起飞波 **W8** ② B **W12** ⑤ B/A = **0.458** ⑧ 交叉 **1** 次 ⑪⑫ 雪崩增速 **2.4 / 3.0** ⑬⑭ W13→W20 单调上升 —— 全部逐位复现；切片2 逐波对照最大相对偏差 **1.712e-16**（验收线 1e-6，纯浮点表示误差）。

### ⑤ 产出落盘 ✅

`docs/phase3/slice4-baseline-run.log` · `slice4-full-run.log` · `slice4-unit-run.log` · `slice4-scene-smoke.log` · `slice4-scene-smoke-windowed.log` · `slice4-slice3-smoke-regression.log` · `slice4-shop.png` · 本报告。

---

## 4. 分层与数据流（详见架构文档 §2）

```
ui/（无游戏状态）  shop_overlay / hud 只读 snapshot() 渲染；time_director 只发意图信号
        │ reroll_requested / buy_requested / lock_toggled / placement_confirmed|cancelled / wave_started|ended
        ▼
gameplay/shop_controller.gd（Node·ALWAYS，唯一的桥 + 🟡 最小波次驱动器）
        ▼
gameplay/shop_runtime.gd（RefCounted，持有一局状态；复用 ShopAI / WaveSim / SimPlayer / PyRandom）
```

- `scripts/engine/shop_ai.gd` 零修改（金标本逐位对齐产物，改一字要重跑 MC）；
- 新状态落 `scripts/gameplay/`（control-manifest §5 预留层），数值只读 `MvpConfig` / `TowerData`，层内零硬编码口径；
- `time_director.exit_placement(confirmed, slot=-1)` 仅加可选参（向后兼容切片3）。

---

## 5. 本轮工程决策（详见架构文档 §4）

1. **只接线不重写**：发牌/保底/扣费/执行/结算全部走 `ShopAI` 现成函数；`pity_card()` 即 P1/P3/P4 兜底链。
2. **手动 reroll = `draw_offers(rng, k, null)`**（force=null）→ 落实 GDD §2.8.1「手动刷新不保底」；金标本 `shop_phase()` 那条 AI 路径未动 → MC 不受影响（分歧本身见 D-1）。
3. **商品位按实际去重位数渲染（≤3），3 个物理位恒在**——金标本 `draw_offers` 是去重集合（D-2，未擅改）。
4. **波次结算复用 `WaveSim.simulate_wave`**（R1 口径，本波打的是上波买出来的构筑），收入/漏怪与金标本同公式，不新造数值。
5. **放置模式进入采用"先调用后验证实际态"**（`enter_placement()` 返回 void，4.7.2 实测不能拿返回值判成功）。

---

## 6. 🔴 待主理人拍板（9 项冲突，全部未擅改）

> ✅ **拍板完成（2026-09-30，主理人）**：9 项全部裁决，留档见 `design/gdd/shop-reroll.md` **§9.2**（v1.3）。**核心原则：凡改金标本口径的抉择一律不采纳 → MC 判据链零回归（A 69.3% / B 91.3% 逐位不变）。** 下表每项补「✅ 拍板」列，原分歧描述保留作留痕。

| # | 分歧 | 现状 / 影响 | 可选出路 | ✅ **拍板（v1.3）** |
|---|---|---|---|---|
| **D-1** | GDD §2.8「手动 reroll 不保底」vs 金标本 `shop_phase()` **每次刷新都带 pity** | 本轮玩家路线按 GDD；AI 路径未动 → MC 不变。**两条路线发牌口径不一致** | 让 `shop_phase()` 也仅初始保底 → **需重跑 MC** | ✅ **玩家路线不保底**（严守 §2.8.1）；金标本 AI pity 是 AI 特化，**不回溯**（§2.8.1 补「两条发牌路线分工」） |
| **D-2** | GDD A4「商品位恒为 3」vs 金标本 `draw_offers` **去重集合**（实测 2000 次：1 位 2.1% / 2 位 38.0% / 3 位 59.9%，约 40% 波次不足 3 位） | UI 按实际位数渲染，不改金标本 | ① 改 GDD 允许 ≤3；② 金标本不去重（改 RNG 消耗 → 重跑 MC）；③ 补位显示 | ✅ **玩家路线 A4 恒发 3 张（有放回，可重复）**；金标本去重属 AI 侧，玩家路线不效仿（§2.8.4 新增 A4b） |
| **D-3** | 刷新折扣口径：金标本 S6 `max(1, 5+3n−disc)` vs GDD §2.5 `max(1, floor((5+3n)×(1−disc)))` | disc=0 逐位相同；disc=0.50、n=0 时 **4.5 分 vs 2.0 分**。MVP 无折扣来源时无影响 | 统一口径（涉及未来折扣卡数值） | ✅ **统一为乘法** `floor((5+3n)×(1−disc))`；金标本减法是旧实现遗留（§2.5/§5.1 补注锁定未来方向） |
| **D-4** | **RerollD 是空卡**：金标本 `reroll_disc` 恒 0（全工程无增加路径） | 本轮按 H4：可购买、扣 10 分、+0%，标「已达上限 (+0%)」（不新增置灰理由，X6） | 补 G2 供应链数值（需设计侧给）或从池中移除 | ✅ **MVP 从玩家路线卡池移除 RerollD（=G2 `SupplyChain`）**；卡池 13→12 张（§7.2 · card-system A4/§7.3 回写） |
| **D-5** | pity **P2 未实现**（金标本只有 P1/P3/P4）：中性主塔的局永远吃不到保底 | 已断言登记现状 | 补 P2 = 改 MC 发牌序列 → **重跑 MC** | ✅ **MVP 不补 P2**（保留为 T1 扩展位，登记现状） |
| **D-6** | **金标本没有锁定机制**（无 locked 字段） | 锁定为本轮新增 UI 侧状态；SR-R4 在本轮实现内成立 | 确认锁定只作用于玩家路线即可 | ✅ **知会**：锁定只作用玩家路线（AI 路线无锁定，SR-R4 在玩家路线内成立） |
| **D-7** | 金标本有**火焰库存摩擦**（`fire_stock` A=6/B=3 每波），GDD 未定义 | 玩家路线未实现该上限（GDD 无此规则） | 玩家路线要不要同样限流，待拍板 | ✅ **玩家路线不实现**（AI 搜刮约束，玩家路线豁免；新增 E17） |
| **D-8** | `[调试] 结束本波` 按钮 + `debug_end_wave()` 为本轮新增调试入口 | 非游戏机制、不产生新数值；**wave-spawner 落地即删** | 知会即可 | ✅ **知会**：随真实刷怪切片删除 |
| **D-9** | GDD §2.7「单塔效果卡先点选副塔再买（2 次输入）」未实现 | 依赖战场塔点选（I-7 SubViewport 未做）；本轮主塔不接收异 Tag 时直接 H8 置灰 | 随 I-7 切片补 | ✅ **随 I-7 切片补**（MVP 主塔不接收异 Tag 时 H8 置灰） |

> ✅ **拍板影响速查（复核）**：D-1 / D-2 / D-3 / D-5 / D-7 均**不改金标本口径** → MC 判据链逐位不变；D-4 只改玩家路线卡池（金标本 `WEIGHTS`/`CARD_NAMES` 不动）→ MC 不变；D-6 / D-8 / D-9 知会。**全部 9 项零连锁重跑 MC。**

---

## 7. 遗留与后续建议

1. **真实刷怪战斗循环**（wave-spawner）：当前波次=「空转的时长 + 战前 DPS 结算」，落子塔的真实 DPS 参与战斗要等刷怪切片；届时删 D-8 调试按钮、补 I-4/I-5 剩余交接点。
2. **弃卡 / 卸下改投 / 拆除回收**：按钮已按 T-C1 置灰占位（冒烟 §6），机制本体 + I-9 二次确认弹窗随后续切片。
3. **C2 高亮 H2–H9**：本轮只做了 H1（可买性）+ H8（合法目标）+ H4（上限标注），其余占位。
4. control-manifest §8 证据索引可补入切片4 条目（未动，等拍板后一并）。

## 8. 证据与产物索引

| 产物 | 路径 |
|---|---|
| 架构文档（主交付） | `docs/architecture/slice4-shop-wiring-architecture.md` |
| 切片4 自测套件 | `tests/test_suite_slice4.gd`（123 项） |
| 切片4 场景冒烟 | `tests/run_slice4_scene_smoke.gd`（46 项） |
| 基线 / 全量回归日志 | `docs/phase3/slice4-baseline-run.log` / `slice4-full-run.log` |
| 切片4 单测 / 冒烟日志 | `docs/phase3/slice4-unit-run.log` / `slice4-scene-smoke.log` / `slice4-scene-smoke-windowed.log` |
| 切片3 冒烟回归日志 | `docs/phase3/slice4-slice3-smoke-regression.log` |
| 商店截帧（1920×1080） | `docs/phase3/slice4-shop.png` |
| 商店运行时 / 接线层 | `scripts/gameplay/shop_runtime.gd` / `shop_controller.gd` |
| UI 改动 | `scripts/ui/shop_overlay.gd` / `hud.gd` / `battle_shop.gd` / `time_director.gd`（可选参） |
| 金标本（本轮零修改） | `scripts/engine/shop_ai.gd` |

---

## 9. ✅ D-4 / D-2 代码落地复核（拍板回写 · `shop-reroll` §9.2 v1.3）

> **背景**：切片4 交付后主理人对 D-2 / D-4 两项拍板（玩家路线恒发 3 张有放回 + 卡池移除 RerollD）。
> 两项共用同一条发牌路径 → 一并在 `scripts/gameplay/shop_runtime.gd` 落地。
> 🔴 **金标本 `scripts/engine/shop_ai.gd` 一字未改**（`CARD_NAMES` / `WEIGHTS` / `draw_offers()` / `shop_phase()` / `pity_card()` 全部原样），所有发牌分歧**收敛在玩家路线侧**。

### 9.1 改了哪些行

**`scripts/gameplay/shop_runtime.gd`（共 7 处）**

| # | 位置 | 改动 |
|---|---|---|
| 1 | 头注释（原 3–27 行区） | 「三件新事」→ **四件新事**（新增 ④ 玩家路线自己的发牌）；GDD 版本 v1.2 → **v1.3**；分歧段 **D-3 → D-4 重新编号**（RerollD 空卡在 GDD 里是 D-4）；D-2 由「保留金标本来单、UI 按实际位数渲染」改为「✅ 已落地：不再复用 `draw_offers()`，改走 `_draw_offers_player()`」；D-4 由「H4 买得起扣 10 分 +0%」改为「✅ 已落地：玩家池排除 RerollD」；D-1 原样保留。**注明「拍板留档见 `design/gdd/shop-reroll.md` §9.2 v1.3」** |
| 2 | 第 35 行 | 新增 `const _FpSum := preload("res://scripts/engine/fp_sum.gd")`（N2：float 序列求和走 `FpSum.sum_py()`） |
| 3 | **新增 51–92 行** | 玩家路线卡池：`PLAYER_EXCLUDED_CARDS = ["RerollD"]` + `player_card_names()` / `player_card_weights()` / `player_pool_total()` / `_build_player_pool()`。🔴 玩家池是**金标本周 `CARD_NAMES`/`WEIGHTS` 的派生**（去掉 RerollD 后的 6 张），**不在本层二次定义**（control-manifest §5）；`static var` 缓存，非热路径 |
| 4 | 第 109 行 | `offers` 注释：长度 ≤ SHOP_SLOTS（金标本去重口径）→ **恒 = SHOP_SLOTS（D-2 有放回抽 3，可重复）** |
| 5 | **新增 156–199 行** | **发牌核心**：`_draw_offers_player(k)`（6 张池 · `_PyRandom.choices()` · 有放回 · 恒 k 个卡名）+ `_apply_pity(shop, force)`（GDD §2.8.3 语义：已含 force → 不干预；否则改写 **1 个未锁定**位，🔴 不新增第 4 位、🔴 不覆盖锁定位 SR-R4/E15；`rng.choice()` = Python `pick_random` 的 PyRandom 等价物）+ `deal_initial_shop()`（先抽 3 张再 `_apply_pity`）。**不再调用 `ShopAI.draw_offers()`** |
| 6 | 第 243 行 | `reroll()`：来单从 `_ShopAI.draw_offers(rng, k, null)` 改为 **`_draw_offers_player(k)`**（有放回 3 张 · 无 RerollD）；`force` 仍恒为 `null`（D-1 不保底不变）；`_merge_with_lock` 锁定位保留逻辑**原样保留** |
| 7 | `buy()` / `at_cap()` 注释 | 补注「RerollD 已在 D-4 从玩家池移除，商店永不发它」；`at_cap()` 函数体保留给 ScrapUp 的 `income_mult` 饱和判定（H4） |

**`tests/test_suite_slice4.gd`（共 5 处，断言总数仍 = **123**）**

| # | 位置 | 改动 |
|---|---|---|
| 1 | 第 5–8 行 | 判据来源 `shop-reroll.md` **v1.2 → v1.3**，补 §2.8(A4b) 与 §9.2 拍板留档 |
| 2 | 第 101 行 | `run_all()` 打印的判据串同步到 v1.3 / A4b / §9.2 |
| 3 | §2（原 205–208 行区） | 🔴 **纯随机基线重算**（见 §9.5）：`p_fire = WEIGHTS["FireUp"] / ShopRuntime.player_pool_total()`（0.17 / 0.905 = 0.187845） |
| 4 | §5（原 410–417 行） | RerollD 旧断言（`can_buy` / `at_cap` / 买后 +0%）**整体作废** → 换成 D-4 三条：① `RerollD 不在玩家池` ② `玩家池 = 6 张` ③ `玩家路线发牌 2000 次 → RerollD 出现 0 次`。`at_cap()` 函数保留（ScrapUp 用） |
| 5 | §7（原 469–495 行） | 「位数恒 ≤ SHOP_SLOTS + 金标本去重分布」→ **「玩家路线恒 = 3」（2000 次发牌越界 0 次）**；删除金标本去重分布 info 日志（旧口径）；保留「快照恒给 3 个物理位」 |

> 断言数守恒：§5 删 3 补 **3**（多补了「玩家池 = 6 张」一条，否则总数 122）→ 与 §7（3→3）合计 **123 项不变**。

### 9.2 全量回归（改动后）

```
$ GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
$ "$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd
919: 汇总：通过 222 项 / 失败 0 项        ← 切片1
1001:汇总：通过 2228 项 / 失败 0 项      ← 切片2（含 MC 300 局）
1146:汇总：通过 142 项 / 失败 0 项       ← 切片3
1317:汇总：通过 123 项 / 失败 0 项       ← 切片4
EXIT=0
```

完整输出：`docs/phase3/slice4-d2d4-full-run.log`（改动前基线对照：`slice4-d2d4-baseline-run.log`）。

### 9.3 🔴 MC 逐位不变（最灵敏探针）

| 指标 | 改动前基线 | 改动后 | 结论 |
|---|---|---|---|
| A 起飞率 | **69.3%**（208/300） | **69.3%** | 逐位相同 |
| A 中位起飞波 | **W8.0** | **W8.0** | 逐位相同 |
| B 起飞率 | **91.3%**（274/300） | **91.3%** | 逐位相同 |
| B 中位起飞波 | **W13.0** | **W13.0** | 逐位相同 |
| MC 前 20 局逐局起飞波 A/B | `[8,-1,8,13,…]` / `[16,8,8,9,…]` | **完全相同** | 逐位相同 |
| 逐波原始列最大相对偏差 | 1.712e-16 | **1.712e-16** | 逐位相同 |

判据链 16 条全对（切片2 ⑥⑦⑨⑩ 等 + 切片4 §8 决定性跑 `Stats.eval_point`，逐条对 `_G.STATS_TIER`）：

| 判据 | 期望 | 覆盖位置 |
|---|---|---|
| ① A 起飞波 / ② B 起飞波 | **W8 / W12** | 切片4 §8 + 切片2 |
| ⑤ B÷A | **0.458** | 切片4 §8 + 切片2 |
| ⑥ A 领先波数 / ⑦ B 领先波数（= cross **16-4**） | **16 / 4** | 切片2（`test_suite_slice2.gd` 383–384 行） |
| ⑧ 交叉次数 flips | **1** | 切片4 §8 + 切片2 |
| ⑨ A 首领先 | **W5** | 切片2（387 行） |
| ⑪⑫ 雪崩增速 A / B | **2.4 / 3.0** | 切片4 §8 + 切片2 |
| ⑬⑭ W13→W20 单调上升 | **true / true** | 切片4 §8 |

全部 PASS（切片2 2228 项 / 切片4 123 项，0 失败）。

### 9.4 🔴 金标本零修改 + 场景冒烟

- **`shop_ai.gd` 零修改**：本工程**不是 git 仓库**（`git status` → `fatal: not a git repository`），改用双证据替代 `git diff`：
  1. **md5 前后一致** `9763dcf3056c8dfd8f7137f39cb8fecc`（改动前后各算一次）；
  2. **`diff` 对改动前副本**：`diff /tmp/shop_ai.baseline.gd scripts/engine/shop_ai.gd` → **空**（`SHOP_AI_DIFF_EMPTY`）。
  → 金标本 `CARD_NAMES` 仍 **7 张（含 RerollD）**、`WEIGHTS` 仍含 `RerollD: 0.095`、`draw_offers()` 仍去重；AI 路线（MC）不受玩家路线任何改动影响。
- **切片4 场景冒烟**：`run_slice4_scene_smoke.gd` → **46 项 / 0 失败 / EXIT=0**（`docs/phase3/slice4-d2d4-scene-smoke.log`），窗口模式不崩（手动设置 offers 的三类卡分流路径与 `offers.size() >= 1` 断言均不受影响）。

### 9.5 🟡 一处**偏离原指令**的必改项（上报）

> 指令要求「§2 reroll 纯随机段**不改**且继续全绿」。实测**做不到**，原因不是实现偏差，而是 **D-4 的连带数学后果**：

- §2 的「纯随机基线」原按 **7 张池**算：`1 − (1 − 0.17)³ = 0.428213`；
- D-4 从玩家池移除 RerollD（权重 0.095）后，`PyRandom.choices()` 按 `total = Σw = 0.905` 归一（control-manifest P3 = Python `random.choices` 口径）
  → `w(FireUp) = 0.17 / 0.905 = 0.187845` → 基线抬到 `1 − (1 − 0.187845)³ = 0.464307`；
- 实测 6000 次 reroll 出现率 = **0.463500**（与 0.464307 差 0.13σ）→ 对新基线 `|rel| = 1.7e-03` ✅；
  对旧基线 0.428213 则 `|rel| = 8.2e-02 > 7e-02` → **FAIL**（首次跑即复现：122 通过 / 1 失败）。

**处理**：只改了基线**推导式**（`p_fire` 除以 `player_pool_total()`），**断言语义完全没动**（仍是「reroll 出现率 = 纯随机基线 ±3pp」且「< 0.60」—— 这条正是 A2「reroll 不保底」的判据，实测 0.4635 仍远低于「每刷必中」）。这是 D-4 的**必然连带**，不是新口径分歧：**要么改这条基线，要么承认 D-4 不成立**。已按前者处理并在此留档，请主理人知悉。

### 9.6 本轮自检（control-manifest §7）

- [x] 退出码 **0**，四段汇总 `222 / 2228 / 142 / 123` 齐全、0 失败（**2715 项**）
- [x] MC **A 69.3% / B 91.3%**，中位 A W8.0 / B W13.0，前 20 局逐局逐位相同
- [x] 判据链 16 条逐条对上
- [x] `shop_ai.gd` **零修改**（md5 一致 + diff 空）
- [x] 切片4 场景冒烟 46/0
- [x] 新代码无裸 `pow(`（整数指数）、无 float 序列 `+=` 求和（玩家池总权重走 `_FpSum.sum_py()`）、无裸 `RandomNumberGenerator`（全部走 `_PyRandom.choices()` / `_PyRandom.choice()`）
- [x] 玩家路线卡池 **6 张**（金标本 7 − RerollD），金标本 `CARD_NAMES`/`WEIGHTS` 仍 **7 张不动**
- [ ] control-manifest §8 证据索引补入本轮日志（待主理人确认后一并回写）
