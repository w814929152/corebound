# GDD · `tower-build` 塔组建 / 装配系统（**v1.0 定稿**）

> **作者**：文策渊（设计主理人） · **状态**：🟢 **v1.0 定稿** —— **Phase 2 系统拆解的最后一份核心系统 GDD**（`card-system` → `core-defense` → `damage-pipeline` → `shop-reroll` → `wave-spawner` → `mechanics-tower-life-death` 之后收口）
> 🔴 **本 GDD 零新增定稿数值**：`Focus 0.06` / `AllIn 1.6 · 60%` / `Crossfire 1.0 · 1.25 · 1.5` / `κ` 公式与 `N_tower_histmax` 口径 / 返还 `50%` / 装配卡全销毁 / 软 cap `1.10→1.03` / 共鸣门槛 `h ≥ 3` / 装配合法性 TB-7 / 放置减速 `0.25×` —— **全部引用上游，一字不改**。
> 🔴 **本 GDD 不开放新拍板项**：撰写中发现的 **6 处口径缺口**全部落在 `tower-build` 自身职责边界内，已自行消化为 **§11.1 设计选择 D-TB-1 ~ D-TB-6**（每条给推荐 + 理由 + 兜底），✅ **2026-09-30 用户全批确认**。
> **上游（全部定稿）**：`card-system` **v1.1.5**（§5.8 锚点 A1–A18 为唯一数值权威）· `core-defense` **v0.5**（空间唯一写入方 · I1–I14 · §2.9 主塔涌现）· `damage-pipeline` **v1.0.5**（7 乘区 · §4.2 重算矩阵 · §8.2b TB-1~TB-7）· `shop-reroll` **v1.0**（五态状态机 · §8.6 契约）· `mechanics-tower-life-death` **v1.0**（塔移除结算器 · 🔒 T1 分支）· `game-concept` v0.4（四支柱 · R13）
> **下游**：`damage-pipeline`（供 `h_i` / `attached` / `L_i` / 五事件）· `core-defense`（转发 I9 写入请求）· `shop-reroll`（接装配 / 放置 / 拆除请求）· UI / 美术（林绘澄）· 音频（阮和鸣）
> **本 GDD 的使命（一句话）**：定义「**一座塔是怎么被组建起来的**」—— 单塔效果卡的**装配 / 卸下 / 弃卡**、建筑卡的**放置**、塔的**移除**四条操作链，以及它们如何驱动 **主塔涌现 `CoreTower`** 与 **`Focus` / `AllIn` / `Crossfire`** 三大乘区。**它是编排层，不是数据层。**

---

## 0. 结论前置（给赶时间的人）

1. **`tower-build` 不拥有任何数据实体。** `Tower` 实体归 `core-defense`（§3.3），卡牌分类与卡池归 `card-system`（§2.1 / §7.3），伤害计算归 `damage-pipeline`。本系统只做三件事：**① 编排四条操作链；② 维护两个"只有它能写"的量（`Tower.attached` 与 `N_tower_histmax`）；③ 发五个事件让下游失效重算。** 这条边界一旦被突破（UI 直接改 `attached`、管线自己算 `CoreTower`），立刻出现"文档定 A、引擎跑 B"的第三个 `Syn` 型问题。
2. 🔴🔴 **全文最重要的一条：`L_i` 与 `h_i` 解耦**（红线 **R-3**）。`L_i` = 装配到塔 i 的**单塔效果卡层数**，只喂 `Focus` / `AllIn` / `CoreTower`；`h_i` = 塔 i 的**建筑卡层数（塔等级）**，只喂 `Base(h^0.6)` / `E_i` 供能 / 共鸣门槛 `h ≥ 3` / `Focus` 的**预热门槛 ramp**。混淆二者 = "只建塔不投卡也能起飞" → 单核与多塔的分化当场消失（R9 复发）。**§2.2 给出了 R-3 的两种典型误读与回归判据。**
3. **主塔是涌现，不是声明。** `CoreTower = argmax_i(L_i, −reached_at_i)`，平局取**先达到该层数**者（稳定排序）。🔴 **全系统不存在、也不得存在任何 `set_core_tower()` 写入口** —— 玩家永远不能点按钮"设为主塔"（A18 / `core-defense` D-4）。
4. **三大乘区本系统只"供数"，不算值。** `Focus` / `AllIn` / `Crossfire` 的公式权威在 `damage-pipeline` §5.1（本文档不重新定义、不改一个数字）；本系统的职责是**说清每个乘区的输入从哪来、什么时候变、谁负责重算**（§2.4）。
5. **κ 的"折价不可逆"只锁折价项，不锁档位项。** 兜底①（`N_tower_histmax` 只增不减 → **拆塔不回退折价**）锁定的是 `clamp(N−2,0,4)` 这一项；拆塔销毁的装配层数会改变 `L_tag` → **`κ_tag` 档位仍可能掉档**（0.10 → 0.06）。这是两件不同的事，工程必须分开实现（§2.5 / §6）。
6. **四条操作链按"轻重"分时钟**：装配 / 放置 = **轻决策**（战斗内可做，`shop-reroll` 态 ①②③⑤）；卸下 / 弃卡 / 塔移除 = **重决策**（🔴 **仅波次间安全窗** 态 ④，红线 T-C1）。这是 `card-system` §4.3 职责切分铁律在塔侧的完整落地（§4）。
7. **6 处口径缺口已在本系统职责内消化**（§11.1）：`reached_at` 的序号来源、卸下的交互顺序、`N_tower_histmax` 的归属与唯一写入点、二次确认取消的代价、**`CoreTower` 未定义时单塔效果卡的默认宿主**、**默认宿主不合法时的降级路径**。全部给推荐、全部零新数值。

---

## 1. 系统目标（System Goal）

### 1.1 一句话

> 塔组建系统把玩家的**三次点击**（买卡 → 选塔 → 认赔）翻译成一个可被伤害管线唯一消费的 build 状态，并让"**哪座塔是我的主塔**"这件事**自己浮出来**，而不是让玩家去声明。

### 1.2 与支柱的兑现关系

| 支柱 | 本系统如何兑现 | 若不满足则 |
|---|---|---|
| **P1 不动如山** | 塔的四条操作链全部是**建造 / 投资**行为（放塔位、投给某塔），**没有任何一条涉及操作单位移动或释放技能** | 若出现"选中塔下指令" → 违反 P1 |
| **P2 雪崩无上限** | 装配链是深度引擎（`Stack ∝ (1+κ)^n`）的**唯一入口**；集中投给同一座塔才能吃满利率 → 雪崩是"投出来的"不是"送的" | 若分散投与集中投收益相同 → 起飞数学不成立 |
| **P3 每局一个新解** | 主塔由 `argmax` 涌现 → 每局"哪座塔成为主塔"不同；卸下 / 弃卡 / 拆塔让 build 有**转型**空间 | 若主塔可声明 → 每局解空间坍缩为固定套路 |
| **P4 决策而非动作** | 四条操作链全部**不可逆**（装配沉没、卸下降 1 层、弃卡全销毁、拆塔销毁装配卡返 50%）→ 每一次点击都是真取舍；轻 / 重决策分层让**战斗内只有轻决策** | 若塔可无痛重来 → 决策退化为假选择 |

### 1.3 本系统的四条设计红线（自检用）

| # | 红线 | 出处 |
|---|---|---|
| 🔴 **TB-R1** | **`L_i` 与 `h_i` 解耦**：`Focus` / `AllIn` / `CoreTower` 的**基数**只吃 `L_i`，`h_i` 只做 `Focus` 的预热门槛 ramp（∈[0,1]），不贡献层数增量 | `damage-pipeline` R-3 · `card-system` A10 |
| 🔴 **TB-R2** | **`CoreTower` 涌现非声明**：只暴露只读查询 + 信号，**禁止任何 `set_core_tower()` 写入口** | A18 · `core-defense` §2.9 / D-4 |
| 🔴 **TB-R3** | **`N_tower_histmax` 单调非减**：🔴 **拆塔 / 塔位释放 / 塔 `Disabled` 一律不得回退该计数器** | `card-system` v1.1.5 兜底① · A5 / E11 |
| 🔴 **TB-R4** | **重算事件驱动、时钟无关**：四条操作链只发事件 + 脏标记，**禁止挂在 `_process` / `Timer` 上**，也**禁止每帧 O(n²)** | `core-defense` C-2 · `damage-pipeline` §4.3 交接点 K |

### 1.4 🔴 边界声明：本系统**不拥有**什么（务必先读这一节，否则会重复实现）

| 数据 / 职责 | 归属 | 本系统的权限 |
|---|---|---|
| `Tower` 实体（空间字段：`slot_index` / `prototype` / `range` / `global_position` / `links` / `resonance_index`） | `core-defense` §3.3 | **只读** |
| `Slot` 与塔位几何、`CoverageScore`、`LinkGraph`、`E_i` | `core-defense` | **只读**（订阅 `links_changed` / `e_changed`） |
| 卡牌分类、卡池 13 张、`kind` / `tag` / `compound` / `price` | `card-system` §2.1 / §7.3 | **只读** |
| κ / `κ_r` / `StackCap` 档位与 7 乘区计算 | `damage-pipeline` §5 | **只读**（读 `DamageCache`，不得自算一遍） |
| 强化槽 / 全局槽的**容量** | `card-system` A2（5 / 3） | **只读 + 报占用**（H7） |
| 五态状态机、减速预算、`pity` | `shop-reroll` §2 | **只接受请求**，不决定时机 |
| 塔 HP / 仇恨 / `repair_cost` / 暴露度 | `mechanics-tower-life-death` v1.0 🔒 **T1** | **MVP 不承载任何数值**，仅预留 `Disabled_i ≡ 1.0` 占位 |

**本系统"只有它能写"的三个量（唯一写入权）**：

| 量 | 说明 | 唯一写入点 |
|---|---|---|
| `Tower.attached` | 装配到该塔的单塔效果卡种与层数（`Dict[card_id → layers]`） | 本系统的 `attach_` / `detach_` / `discard_` 三个函数（§9.2） |
| `Run.n_tower_histmax` | 本局历史最大塔数（**只增不减**） | 本系统在 `place_tower()` 成功返回后的一次递增（D-TB-3） |
| `Tower.reached_at` | 该塔最近一次 `L_i` 增加时的全局动作序号（平局稳定排序键） | 本系统在 `L_i` 变化时写入（D-TB-1） |

> 🔴 **工程实现要点**：`attached` / `reached_at` 虽挂在 `core-defense` 的 `Tower` 实体上，但**写入权归 `tower-build`**。请把这两个字段的 setter 收在本系统的三个函数里，`core-defense` 与 `damage-pipeline` 一律只读 + 订阅信号 —— 这是本 GDD 的接口约定，不是建议。

---

## 2. 核心机制（Core Mechanics）

### 2.1 系统定位：编排层（一张图看懂依赖方向）

```
        shop-reroll（唯一 UI 入口 · 五态状态机）
                │  买卡 / 点塔 / 点「拆除并回收」
                ▼
   ┌────────────────────────────────────────────┐
   │            tower-build（本系统）             │
   │  ① 装配 / 卸下 / 弃卡（写 attached）          │
   │  ② 建筑卡放置（转发 core-defense I9）         │
   │  ③ 塔移除 TowerRemove（转发 I9 scrap）        │
   │  ④ 维护 N_tower_histmax / reached_at        │
   │  ⑤ 发五个事件 → 下游失效重算                  │
   └───┬──────────────┬───────────────┬──────────┘
       │              │               │
       ▼              ▼               ▼
 core-defense    damage-pipeline   core-defense
 （I9 写入口）    （五事件→dirty）   （I11 读 CoreTower）
       │              │
       ▼              ▼
  LinkGraph       DamageCache ──→ UI / 商店预估（SSOT）
  Coverage/E_i
```

> 🔴 **依赖方向铁律**：`shop-reroll` 只发请求 → 本系统只编排 → `core-defense` 只认 I9 写入 → `damage-pipeline` 只算不算写。**任何系统都不得反向写别人的字段。**

### 2.2 🔴 核心数据流：`L_i` 与 `h_i` 的解耦（本文档最易出错的一处）

```
建筑卡 StructureCard ──放置/升级──→ h_i（塔等级 = 谐波层）
                                     ├─→ Base_i = base_dps × h_i^0.6      【次线性】
                                     ├─→ E_i 供能（喂邻居，双向门槛 h_i≥3 ∧ h_j≥3）
                                     ├─→ AoE / Aux 的部分输入
                                     └─→ 🔴 Focus 的【预热门槛 ramp】min(1, h_i/8)   ← 仅此一处进 Focus

单塔效果卡 TowerEffectCard ──装配──→ L_i = Σ attached.values()
                                     ├─→ Focus_i  = 1 + 0.06 × L_i × min(1, h_i/8)   【基数 = L_i】
                                     ├─→ AllIn_i  = 1.6 若 i==CoreTower 且 L_i ≥ 0.60·ΣL
                                     ├─→ CoreTower = argmax_i(L_i, −reached_at_i)
                                     └─→ Stack_i  = 复利/加法/饱和三组（各自逐卡 n_c）
```

| 量 | 全称 | 单位 | 谁写 | 喂什么 | 🔴 不喂什么 |
|---|---|---|---|---|---|
| **`L_i`** | 装配到塔 i 的**单塔效果卡**层数总和 | 层 | 本系统（attach/detach/discard） | `Focus`（基数）、`AllIn`、`CoreTower`、`Stack` | ❌ 不喂 `Base` / `E_i` / 共鸣门槛 |
| **`h_i`** | 塔 i 的**建筑卡**层数（= 塔等级 = 谐波层） | 层 | `core-defense` I9（place/upgrade） | `Base(h^0.6)`、`E_i` 供能、共鸣门槛 `h≥3`、`Focus` 的 ramp `min(1,h_i/8)`、AoE | ❌ 不喂 `Focus` 基数、`AllIn`、`CoreTower` |

#### 🔴 R-3 的两种典型误读（回归时重点查这两条）

| 误读 | 错在哪 | 回归判据（`damage-pipeline` §10.2 验收 5） |
|---|---|---|
| **误读 A**：把 `h_i` 当 `Focus` 的基数（`1 + 0.06 × (L_i + h_i)` 或 `1 + 0.06 × h_i`） | 只建塔不投卡（`L_i = 0`, `h_i = 133`）也能起飞 → 单核与多塔分化消失，R9 复发 | 只建塔不投卡 → 塔面板 `Focus = 1.00`、**无** `ALL-IN` 角标；投第 1 张单塔效果卡 → `Focus = 1.06` |
| **误读 B**：把 `h_i` 排除出 `Focus` 公式（写成 `1 + 0.06 × L_i`，摘除 ramp） | D-1 已定稿**保留**预热门槛（`focus_full=False`）；摘除会改变前中期曲线，与定稿扫描口径不一致 | 单测：`h_i < 8` 时 `Focus` 随 `h_i` 线性爬升；`h_i ≥ 8` → `ramp = 1`（终局逐位等于金标本） |

> ✅ **R-3 的准确读法（一句话）**：**`Focus` / `AllIn` 的"层数增量"只来自 `L_i`；`h_i` 只是 `Focus` 的一个 ∈[0,1] 的乘性 ramp，它决定"同一份 `L_i` 能兑现多少"，但**它自己不产生任何层数增量**。**
> 这就是为什么"只建塔不投卡"能拿到 `Base` 与 `Resonance`，却拿不到 `Focus` 与 `AllIn` —— 后者是**投资**的回报，不是**建造**的回报。

### 2.3 主塔涌现 `CoreTower`（完整引用 `core-defense` §2.9）

> **归属切分（`core-defense` D-4 已定稿，本系统照此实现）**：
> - **语义定义权**归 `card-system`（A18：`CoreTower = argmax(该塔的单塔效果卡层数)`，**涌现、非声明**）—— 本系统不改语义。
> - **实体与计算**归 `core-defense`（`L_i` 挂在 `Tower` 上，由其在 `L_i` 变化时派生并缓存）。
> - **编排与触发**归 `tower-build`（本系统负责：任何改变 `L_i` 的操作后，通知 `core-defense` 重跑一次 `argmax`；维护 `reached_at` 稳定排序键）。
> - 🔴 **不提供任何 `set_core_tower()` 写入口。**

#### 2.3.1 判定算法（逐字引用）

```
L_i        = Σ(装配到塔 i 的单塔效果卡 stack_n)         # card-system §3.3
reached_at = 该塔最近一次 L_i 增加时的全局动作序号        # 稳定排序键（E4 / D-TB-1）

CoreTower  = argmax_i ( L_i , −reached_at_i )          # 先取层数最大；并列取"先达到该层数"者
           = null  若 场上无塔 或 ΣL == 0               # card-system §4.5.2 P3/P4：pity 不生效
```

- **平局口径 = `card-system` E4「取先达到该层数者」** → 用单调非减的 `reached_at` 实现，**避免每帧徽章闪烁**（E4 原话：稳定排序）。
- 🔴 **禁止**用 `argmax` 的数组首个索引（那是 `max(range(n), key=...)` 的行为，会随塔数组顺序漂移 → 徽章闪烁）。
- **触发重算的事件**（本系统负责发出）：装配 / 卸下（降 1 层）/ 弃卡 / 拆塔（装配卡全销毁）→ 均走 §6 重算链。

#### 2.3.2 只读接口（`core-defense` I11，本系统只消费不生产）

| 接口 | 返回 | 本系统的用法 |
|---|---|---|
| `get_core_tower() -> Tower?` | 当前主塔（可能为 `null`） | 装配的**默认宿主**（D-TB-5）、UI 徽章绑定 |
| `get_core_tower_share() -> float` | `L_core / ΣL` | `AllIn` 的 60% 判据输入（**本系统不重算，只确保 `L` 已刷新**） |
| `signal core_tower_changed(new, old)` | 徽章 / 底座发光切换时发一次 | UI 订阅 → 徽章迁移演出（§8.1） |

#### 2.3.3 三种塔状态（沿用 `card-system` §2.3，零新增）

| 状态 | 判定 | 价值来源 |
|---|---|---|
| **主塔 `CoreTower`** | `argmax_i(L_i, −reached_at_i)` | `Stack` 深度复利 + `AllIn ×1.6` |
| **副塔** | `L_i > 0` 但非最高 | 多塔流的主体 |
| **挂件塔 `AuxTower`** | `L_i = 0`（或远低于主塔） | 基础功能（减速 / 光环 / 凑 Tag / 占位 / 供 `h_j`）+ `Aux` 饱和乘区 |

> 🎨 **卡面的"角色倾向"是塔原型的客观属性**（`card-system` §2.3：`主塔向` / `挂件向` / `通用`），**不是系统替玩家算出的最优解** → 不违反 C-3「只标事实不标推荐」。

### 2.4 三大乘区的触发与计算（本系统 = 供数方，**公式权威在 `damage-pipeline` §5.1，此处一字不改**）

| 乘区 | 作用域 | 定稿公式（引用） | 🔴 输入从哪来（本系统负责） | 何时重算（本系统触发） | 谁算 |
|---|---|---|---|---|---|
| **`Focus`** 专注 | 逐塔 | `1 + 0.06 × L_i × min(1, h_i/8)` | `L_i` ← `Tower.attached`（本系统写）<br>`h_i` ← 塔等级（`core-defense` I9 写） | `L_i` 变（装配 / 卸下 / 弃卡 / 拆塔）<br>`h_i` 变（放置新建 / 升级） | `damage-pipeline`（B5） |
| **`AllIn`** 孤注一掷 | 逐塔 | `1.6` 若 `i == CoreTower` 且 `L_i ≥ 0.60 × ΣL`，否则 `1.0` | `CoreTower` ← `core-defense` I11（`get_core_tower`）<br>`share` ← `get_core_tower_share()` | `L_i` 变 → `ΣL` 变 → `CoreTower` 与占比双双可能易主 | `damage-pipeline`（B6），占比由 `core-defense` 供 |
| **`Crossfire`** 交叉火力 | **全局** | `N<2 → 1.0`；`N=2 → 1.25`；`N≥3 → 1.5` | `N_tower` ← `core-defense` I12（**当前场上塔数**） | 建塔（`N+1`）· 拆塔（`N−1`） | `damage-pipeline`（C2） |

> 🔴 **一处必须分开记的口径（易错）**：
> - **`Crossfire` 读「当前场上塔数 `N_tower`」** —— 建塔升档、拆塔降档。
> - **κ 的广度折价读「本局历史最大塔数 `N_tower_histmax`」** —— **只增不减，拆塔不回退**（§2.5）。
> → **同一个"塔数"在两个乘区里是两个不同的量。** `damage-pipeline` §8.2b TB-5 把两者并列写在一行（`N_tower` 喂 κ 广度折价与 Crossfire），**阅读时需按 `card-system` v1.1.5 兜底①拆分**：κ 侧改读 `N_tower_histmax`。见 §12 一致性登记 C-1。

> 🔴 **`AllIn` 不得泄漏到全局段**：`AllIn` 是**逐塔**乘区（B6），只作用于 `CoreTower` 那一座塔。`damage-pipeline` §10.2 验收 6 要求：6 塔铺场局中非主塔的塔面板**不显示** `×1.6`。本系统只提供 `CoreTower` 索引 + 已刷新的 `L` 向量，不参与判据。

### 2.5 κ 与 `N_tower_histmax`（兜底①在本系统的落地）

```
κ = κ_tag(L_tag) − 0.01 × clamp(N_tower_histmax − 2, 0, 4)        下限 κ ≥ 0.02

  κ_tag            = Tag 档位基准利率（0.06 / 0.10；0.12 为 T1，MVP 不开）   ← card-system A6
  N_tower_histmax  = 本局历史最大塔数（座，含 h=1 的占位塔）🔴 只增不减      ← card-system A5 / E11
```

| 本局历史最大塔数 | ≤2 | 3 | 4 | 5 | ≥6 |
|---|---|---|---|---|---|
| 广度折价 | 0 | 0.01 | 0.02 | 0.03 | 0.04 |
| **κ（协同成立档 `κ_tag=0.10`）** | **0.10** | 0.09 | 0.08 | 0.07 | **0.06** |

> 🔴 **本表怎么读（兜底①，逐字引用 `card-system` §5.2）**：一旦建到 N 座塔，**即使后来拆到 2 座，κ 仍按 N 算（拆塔不回升 κ）**。单核 A 若全程只建 2 塔，`N_tower_histmax = 2`，κ 仍为 **0.10**，不受影响。
> 例：铺满 6 塔拿满 `Crossfire` / 共鸣后拆到 2 塔 → `N_tower_histmax = 6` → 折价仍锁在 `0.04`（κ = 0.06），**而 `Crossfire` 已降回 1.25**。

**本系统的三条实现铁律**

1. 🔴 **`N_tower_histmax` 是单调非减计数器**：唯一自增时机 = `place_tower()`（**新建**，非升级）成功返回后 `histmax = max(histmax, N_tower_now)`。**拆塔 / `Disabled` / 塔位释放一律不得回退它**（回退 = 重新开出 F-2 套利口）。
2. 🔴 **兜底①只锁"折价项"，不锁"档位项"**：拆塔销毁的装配层数会使 `L_tag` 下降 → `κ_tag` 档位**仍可能从 0.10 掉到 0.06**（档位侧回退是定稿行为，不是 bug）。**工程不得把"κ 不回退"实现成"κ 完全不变"** —— 那是过度实现，会让 `-0.04` 的折价与档位混淆。
3. 🔴 **κ 重算的触发条件已收窄**：只有 **① 新建塔刷新 `histmax`**、**② `L_tag` 变动导致档位跨档** 两种情况需要全场 κ 重算；**拆塔自身不触发折价重算**（但仍可能因 ① 触发档位重算）。

> 🟡 **遗留观察项（承接 `card-system` R-C1，本系统侧的可观察点）**：折价**永久生效** → 「不敢建第 3 座塔」的风险加剧。本系统的缓解手段是**在建塔前把折价预告做足**（§8.4 H6）。切换判据沿用 `card-system` §5.2：试玩 10 局「终局塔数 ≤2」占比 > 70% → 切兜底 ④b（逐层锁定），⚠️ 且须同步规定"拆塔只清除增量、不追溯已叠层利率"。

### 2.6 装配的合法性与槽位口径

#### 2.6.1 装配合法性（TB-7 / `damage-pipeline` §9 D-8① 定稿，一字不改）

```
can_attach(card, tower) := tag(tower) == None  or  tag(card) == tag(tower)
```

- **禁止「异 Tag」装配**（🔥卡 ❌ 装到 ❄塔），但**中性塔（`Arrow` / `Beacon`）可接收任意 Tag 卡**。
- 理由（`damage-pipeline` D-8①）：完全禁止跨 Tag 会误伤中性主塔 —— `card-system` §4.5.2 的 pity **P2 分支**明确要求"主塔 = `Arrow`/`Beacon` 且全场已有 Tag 投入 → 出 `argmax_Tag` 的单塔效果卡，**默认投主塔**"；若中性塔不能接收 Tag 卡，这条分支等于每波发一张废卡。
- 🟢 **中性塔同挂两张复利卡（T1 🔥 + T4 ❄）的可能后果**由 `damage-pipeline` §5.4 的**分组口径**（复利组**组内并联相加**）兜底 → 不产生双指数（红线 R-4）。本系统只需保证合法性判定正确。

#### 2.6.2 🔴 槽位口径：5 槽 = 5 个「卡种 × 宿主塔」组合，不是 5 层

> 沿用 `card-system` §3.5 / §3.6，本 GDD 补一条实现级澄清（**非新数值**）：

| 情况 | 占槽？ |
|---|---|
| 同一卡种 **反复购买 → 投同一座塔** | ❌ 不占新槽（层数 +1） |
| 同一卡种 **投另一座塔** | ✅ 占 1 个新槽（是一个新的「卡种 × 宿主塔」组合） |
| 装配一个**新卡种** | ✅ 占 1 个新槽 |

> 🔴 若误实现成"5 层就满"，复利根本叠不起来（`1.10^5 ≈ 1.6×`，与定稿目标 `1.10^100` 差 4 个数量级）—— 这是 `shop-reroll` §8.8 点名的实现陷阱。

### 2.7 `Disabled_i` 占位（🔒 T1，仅登记口径）

`mechanics-tower-life-death` v1.0 §4.3 要求：**MVP 在 `Raw_i` 末尾保留一个恒为 `1.0` 的 `Disabled_i` 因子占位**，T1 接管时无需改结构。

| 项 | MVP | T1（`Destroyed` 分支） |
|---|---|---|
| `Disabled_i` | 恒 `1.0` | `Disabled` 塔 → `0.0`（断输出不断链） |
| `CoreTower` 判定 | 不变 | 🔴 **判定不变**（`Disabled` 塔仍持有 `attached`、仍占 `N_tower`、仍供 `h_j`）→ `Raw=0` 使其自然失效，**零新分支** |
| 装配 / 卸下目标 | 只能是 `Active` 塔 | 🔒 T1 才需处理"目标塔为 `Disabled`"的分支（见 §7 TBE-11） |

---

## 3. 数据模型（Data Model）

### 3.1 本系统的运行时状态（唯一自有状态，全部挂在 `Run` 上）

```
Run {
  # ---- 归 card-system（本系统只读）----
  enh_slots:        Array<TowerEffect>   # ≤ 5（每格 = 1 个「卡种 × 宿主塔」+ 其层数）
  global_slots:     Array<GlobalEffect>  # ≤ 3
  pending_structure:Array[Card]          # 待放置建筑卡队列（无上限，E2）

  # ---- 归 core-defense（本系统只读）----
  slots:            Array<Slot>          # 6
  towers:           Array<Tower>         # ≤ 6

  # ---- 🆕 本系统唯一持有的三个量 ----
  n_tower_histmax:  Int                  # 本局历史最大塔数（只增不减）· 与 shop-reroll §3.2 同名字段
  action_seq:       Int                  # 全局单调动作序号（reached_at 的来源，D-TB-1）
  confirm_state:    Enum                 # Idle | PendingDetach | PendingDiscard | PendingRemove（二次确认）
}
```

### 3.2 `Tower` 上的字段分工（谁写 / 谁读，工程照此分权限）

| 字段 | 写方 | 读方 | 说明 |
|---|---|---|---|
| `slot_index` / `prototype` / `range` / `global_position` | `core-defense` I9 | 全体 | 空间侧 |
| `level`（= `h_i`） | `core-defense` I9（`place_tower` / `upgrade_tower`） | `damage-pipeline`（A2） | 建筑卡层数 = 塔等级 = 谐波层 |
| `links` / `resonance_index`（`E_i`） | `core-defense` `LinkGraph` | `damage-pipeline`（A5/A10） | 🔴 下游**只订阅信号**，禁止反写 |
| **`attached`: `Dict[card_id → layers]`** | 🔴 **本系统**（attach/detach/discard） | `damage-pipeline`（TB-2）、UI | 装配到本塔的单塔效果卡种与层数 |
| **`reached_at`: Int** | 🔴 **本系统**（`L_i` 增加时写） | `core-defense`（§2.9.1 平局排序） | 稳定排序键 |
| `L_i`（派生） | — | `damage-pipeline`（A3） | `= Σ attached.values()`，**不落盘、不缓存第二份** |

> 🔴 **SSOT 铁律**：`L_i` **不允许存在第二份副本**。UI 与商店一律读 `DamageCache`（`damage-pipeline` §3.2），本系统只在事件里说"`L_i` 变了"。

### 3.3 派生量字典（本系统视角）

| 标记 | 量 | 本系统的角色 | 失效触发（本系统发出的事件） |
|---|---|---|---|
| A2 | `h_i` | 触发者（转发 I9） | `tower_added` / `tower_level_changed` / `tower_removed` |
| A3 | `L_i` | **写者** | `effect_attached` / `effect_detached` / `tower_removed`（装配全销毁） |
| A11 | `CoreTower` | 触发者（`L_i` 变 → 通知重算） | 同上 + `Ltot == 0` 时置 `null` |
| A5/A10 | `LinkGraph` / `E_i` | 触发者（仅塔位 / 原型变动） | `tower_added` / `tower_removed`；🔴 **升级不触发**（CD-4） |
| B5/B6/C2 | `Focus` / `AllIn` / `Crossfire` | **只供数** | 经 `mark_dirty()`，由 `damage-pipeline` 算 |

---

## 4. 交互流程（Interaction Flow）— 四条操作链

### 4.0 总表：四条操作链的时机与代价（🔴 本 GDD 最该被反复引用的一页）

| # | 操作 | 输入次数 | 代价 / 后果 | 可用时机 | 二次确认 |
|---|---|---|---|---|---|
| ① | **装配**单塔效果卡 | **1 次**（默认投主塔）/ **2 次**（先点塔再买） | 占 1 强化槽（新「卡种×宿主塔」才占）；层数 +1 | ✅ **战斗内可做**（轻决策，态 ①②③⑤） | ❌ |
| ② | **卸下改投** | **2 次**（点槽位卡 → 点目标塔） | 🔴 **该卡降 1 层**（1→0 则释放槽） | 🔴 **仅安全窗**（态 ④，重决策） | 🟡 见下 |
| ③ | **弃卡** | **2 次**（点槽位卡 → 确认） | 🔴 **全销毁，0 返还**，槽位释放 | 🔴 **仅安全窗**（态 ④，重决策） | ✅ |
| ④ | **建筑卡放置** | **2 次**（点队列图标 → 点目标） | 新建占塔位 / 升级 `h+1`；新建可能刷新 `histmax` → κ 折价 | ✅ **战斗内可做**（放置模式 `0.25×`） | ❌ |
| ⑤ | **塔移除 `TowerRemove`**（= 拆塔 = 售卖 `Salvage`） | **2 次**（点塔 → 确认） | 返还 **50% 累计投入**（向下取整）；🔴 **装配卡全销毁**；塔位释放；🔴 **`histmax` 不回退** | 🔴 **仅安全窗**（态 ④） | ✅ **必须** |

> 🔴 **红线 T-C1（`mechanics-tower-life-death` v1.0 §2.2）**：**战斗内完全禁止任何与塔存活相关的操作**（不能修 / 不能卖 / 不能加固 / 不能撤退）。② ③ ⑤ 在态 ①②③⑤ **一律置灰且不响应点击**。

### 4.1 链 ①：装配单塔效果卡（轻决策）

```
[购买] 单塔效果卡（9 分）
   ├─ 宿主判定：
   │     ① 玩家已点选某座塔        → 目标 = 该塔（2 次输入）
   │     ② 未点选 且 CoreTower 存在 → 目标 = CoreTower（1 次输入）
   │     ③ 未点选 且 CoreTower 未定义（ΣL=0 或 无塔）→ 目标 = 【默认宿主】（D-TB-5）
   ├─ 合法性校验 can_attach（TB-7）：
   │     ✅ 通过 → 装配
   │     ❌ 不通过 → 【降级为强制点选】（D-TB-6），战场高亮所有合法塔
   ├─ 写入：
   │     tower.attached[card_id] += 1
   │     L_i += 1 → reached_at_i = ++action_seq        # 平局排序键（D-TB-1）
   │     若为新「卡种 × 宿主塔」→ enh_slots.append()
   └─ 发事件：effect_attached → mark_dirty()
           → Stack_i / Focus_i / CoreTower / AllIn / L_tag→κ/κ_r/StackCap 全场重算
```

| 边界 | 处置 |
|---|---|
| 场上无塔 | `card-system` E9：商店**不刷出**单塔效果卡（置灰标注"需先建造一座塔"）→ 本系统收不到请求 |
| 强化槽满（5 个组合） | 商店置灰 + H7 标注 `强化槽 5/5`；玩家须先**弃卡**（链 ③）腾槽 |
| 目标塔合法但 `can_attach` 不通过 | D-TB-6 降级为强制点选（见下） |

### 4.2 链 ②：卸下改投（重决策 · 仅安全窗）

```
[安全窗] 点强化槽位上的卡 → 点目标塔
   ├─ 校验：目标塔 can_attach(card, target)（TB-7）
   ├─ 代价：🔴 该卡的层数 − 1（这 1 层被销毁，不返还、不可回收）
   ├─ 写入：
   │     from.attached[card_id] -= 1
   │     if from.attached[card_id] == 0: 从 from 移除该键
   │     if 层数 1 → 0：🔴 该「卡种×宿主塔」组合从 enh_slots 移除 → 槽位释放（E3 / dp E14）
   │     to.attached[card_id] += 1；to.reached_at = ++action_seq
   └─ 发事件：effect_detached（+ effect_attached 若目标不同塔）→ mark_dirty()
```

> 🟡 **二次确认口径（D-TB-2 附带）**：卸下**不需要**二次确认弹窗 —— 它**可逆方向明确**（可以再卸回来，代价只是 1 层），且降层预览在悬停时可见。**只有 ③ 弃卡 与 ⑤ 塔移除 需要二次确认**（它们不可逆且损失大）。理由：给"中等代价"操作加弹窗会稀释"重度不可逆"操作的警示重量（认知过载 R10）。

### 4.3 链 ③：弃卡（重决策 · 仅安全窗）

```
[安全窗] 点强化槽位上的卡 → 点「弃掉」
   ├─ 二次确认弹窗（CanvasLayer 140）：
   │     「弃掉这张卡？
   │        销毁 N 层（🔴 不可回收，0 返还）
   │        释放 1 个强化槽」
   ├─ 写入：宿主塔 attached 移除该 card_id（全部层数）；enh_slots 移除该组合
   └─ 发事件：effect_detached → mark_dirty() → Stack / Focus / CoreTower / AllIn / L_tag 全场重算
```

> 🔴 **弃卡 0 返还**（`card-system` §5「满槽需弃卡（不可回收）」）：弃卡是**腾槽**操作，不是售卖。**只有拆塔（链 ⑤）才有 50% 返还。** 两件事的代价结构不同，UI 文案必须区分（§8.3）。

### 4.4 链 ④：建筑卡放置（买 / 放解耦 · 轻决策）

```
[购买] 建筑卡（12 分） → 入 HUD「待放置队列」（右下角蓝图图标 + 张数角标）
                          ↑ 不占塔位、不进战场、🔴 不触发管线重算（塔还没落地）
[放置] 玩家点队列图标 → 进入放置模式（态 ⑤）
        → 全局减速 0.25×（复用 DilationBudget 池，不新增资源）
        → 战场自动高亮所有合法目标：
              · 空塔位   → 绿光脉冲（= 新建，显示 Lv1）
              · 同原型塔 → 金光脉冲（= 升级，显示 Lv_n → Lv_n+1）
        → 单次点击落子 / Esc 取消（🔴 取消不退款，卡留队列）
        → 落子瞬间：
              新建 → core-defense.place_tower(slot, prototype)
                     → 🔴 n_tower_histmax = max(histmax, N_now)   ← 唯一自增点（D-TB-3）
                     → 🔴 6 连重算（含 LinkGraph 重建 + κ 全场重算）
              升级 → core-defense.upgrade_tower(slot)
                     → 5 连重算（🔴 Coverage / LinkGraph 【不触发】，CD-4）
```

| 边界 | 处置 |
|---|---|
| **E1**：塔位已满 且 场上无同原型塔 | 商店**停止刷出**该建筑卡；已购卡滞留队列，UI 显示"无可放置目标"并允许**以 50% 价格退回**（防死锁，= 6 分） |
| **E2**：队列积压 | 队列无上限；HUD 角标持续提醒；**安全窗强制提示一次**（图标弹跳 + 角标） |
| 放置模式减速 | `0.25×`，🔴 复用 `DilationBudget`（与商店同一池），W1–5 不消耗预算 |

### 4.5 链 ⑤：塔移除 `TowerRemove`（= 拆塔 = 售卖 `Salvage` · 重决策 · 仅安全窗）

> 🆕 **术语统一（`card-system` v1.1.4 · Q-T1 = A′）**：**售卖 ≡ 拆塔** —— 同一个动作、同一套规则、同一个确认弹窗，**UI 统一为「拆除并回收 `Salvage`」**。

```
[安全窗] 点战场上的塔 / 商店「拆除模式」→ 点塔
   ├─ 悬停预览：「返还 X 分 / 销毁 N 张装配卡（共 M 层）」
   ├─ 🔴 二次确认弹窗（CanvasLayer 140）：
   │     「拆除这座塔？
   │        返还 X 分（累计投入的 50%）
   │        销毁 N 张装配卡（共 M 层）🔴 不可回收
   │        κ 不会因拆除而回升」        ← 兜底①强制披露（H6）
   │        [取消] [确认拆除]
   ├─ 确认 → request_tower_remove(tower, source = Salvage)
   │     → 返还入账（🔴 M5 之外唯一的积分来源，且是**退币非铸币**）
   │     → 该塔 attached 全销毁（键与层数）
   │     → core-defense.scrap_tower(slot)  → 塔位释放
   │     → 🔴 n_tower_histmax 不变 → 折价不回退（TB-R3）
   └─ 发事件：tower_removed → mark_dirty()
           → Ltot 变 → CoreTower / Focus / AllIn / Stack 全场重算
           → LinkGraph 重建 + E_i + Coverage 重算
           → N_tower 变 → Crossfire 档位可能跳变（1.5 → 1.25）
           → L_tag 变 → κ_tag 档位可能掉档（🔴 折价不变，档位可变，§2.5）
```

**主动移除 `Salvage` 分支的定稿规则（Q-C3 原文，一字不改）**

| 项 | 定稿规则 |
|---|---|
| **返还** | 该塔**累计投入的 50%**（该塔花费的建筑卡分 + 其上装配的单塔效果卡分之和，**向下取整**） |
| **装配卡** | 🔴 **全部单塔效果卡及其层数全部销毁**（不可回收，与"弃卡"同口径） |
| **塔位** | 释放，可再建新塔 |
| **确认** | 🔴 **必须二次确认**（不可逆），弹窗列出"返还 **X** 分 / 销毁 **N** 张卡（共 **M** 层）" |
| **时机** | 🔴 **仅波次间安全窗** |
| **`histmax`** | 🔴 **不变** → κ 折价不回退（兜底①） |

> 🔒 **被动移除 `Destroyed` 分支（T1，本 GDD 仅登记口径，MVP 不实现）**：返还 **0%**；装配卡随 `Disabled` **冻结**（仍占强化槽）；塔位**不释放**；**不算失败**（沿用 Q5）。其全部参数（`HP0` / `AGGRO_R` / `repair_cost` 等）见 `mechanics-tower-life-death` v1.0 §2，本 GDD 不承载任何数值。
> 🔴 **反通胀红线 T-R1 / T-R2（登记）**：返还系数 ≤ 100%，禁止"买入折扣 × 移除返还"同时生效；🔴 **禁止任何"以移除塔为触发条件的铸币效果"**。

---

## 5. 数值（Numbers）

> 🔴 **口径声明：本 GDD 不新增任何定稿数值。** 下表全部引用 `card-system` §5.8 锚点 A1–A18 与 `damage-pipeline` §5.2 定稿常数表，供工程单点查阅；**凡冲突以 `card-system` §5.8 为准**。

| # | 参数 | 定稿值 | 出处 |
|---|---|---|---|
| A2 | 塔位 / 强化槽 / 全局槽 | **6 / 5（计「卡种×宿主塔」非层数）/ 3** | `card-system` A2 · §3.6 · 本 §2.6.2 |
| A1 | 卡价（建筑 / 单塔效果 / 全局） | **12 / 9 / 10** | `card-system` A1 |
| A5 | 实付复利率 κ | `κ = κ_tag − 0.01 × clamp(N_tower_histmax − 2, 0, 4)`，**下限 0.02**；`N_tower_histmax` **只增不减** | `card-system` A5 · 本 §2.5 |
| A6 | `κ_tag` 档位 | 0–2 层 **0.06** / ≥3 层 **0.10**；`0.12`（≥20 层）**T1，MVP 不开** | `card-system` A6 |
| A10 | `Focus` | `1 + 0.06 × L_i × min(1, h_i/8)`（`L_i` = 单塔效果卡层数；`h_i` = 该塔建筑卡层数，`focus_min_h = 8`） | `card-system` A10 · `damage-pipeline` B5 |
| — | `AllIn` | `×1.6`，判据 `i == CoreTower` 且 `L_i ≥ 0.60 × ΣL` | `damage-pipeline` P3 |
| — | `Crossfire` | `N<2 → 1.0` / `N=2 → 1.25` / `N≥3 → 1.5` | `damage-pipeline` P4 |
| A11 | 共鸣 | `E_i = Σ_{j∈N(i), h_i≥3 ∧ h_j≥3}(1+h_j)`；`Resonance = (1+κ_r)^{E_i}`；`κ_r` flat **0.050** | `card-system` A11 / A7 / A8 |
| A9 | 软 cap | ≤100 层 `×1.10`；>100 层 `×1.03`（**软 cap，禁止硬墙**）；`StackCap` = `100 + 15·n_G3`，上限 160 | `card-system` A9 · `damage-pipeline` P11 |
| A16 | 卸下 / 弃卡 / 塔移除 | 卸下**降 1 层** / 弃卡**全销毁 0 返还** / 主动移除 **返还 50% + 装配卡全销毁 + 二次确认 + 仅安全窗** | `card-system` A16 · 本 §4 |
| — | 装配合法性 | `tag(tower) == None or tag(card) == tag(tower)` | `damage-pipeline` TB-7 / D-8① |
| N11 | 放置模式减速 | **0.25×**（复用 `DilationBudget`） | `core-defense` N11 · `card-system` §4.2 |
| — | 共鸣门槛 | `h ≥ 3`（**双向** `h_i ≥ 3 ∧ h_j ≥ 3`，🔴 必须逐字实现） | `core-defense` §2.5.2 |
| — | 链接判定 | `d ≤ 0.65 × (R_i + R_j)` | `core-defense` N4 / C-1 |
| — | 射程 | **MVP 固定不随等级变**（Arrow 22 / Cannon 18 / Frost 20 / Beacon 20） | `core-defense` CD-4 / `damage-pipeline` P16 |
| — | `Empowerment` | **MVP 恒 `1.0`（关闭）**，乘法位保留 | `damage-pipeline` C4 |

> 🔴 **本 GDD 明确不承载的数值**：塔 HP / 仇恨半径 / 修复费用 / 暴露度（🔒 全部 T1，见 `mechanics-tower-life-death` v1.0 §2）。**实现时不得在本系统内出现这些常量。**

---

## 6. 🔴 重算编排矩阵（操作 → 谁失效 → 谁负责算）

> **给程基岩**：本表是 `card-system` §4.4 与 `damage-pipeline` §4.2 两张重算表的**塔侧合订本**。🔴 全部**事件驱动**（dirty flag，帧末全量重算一次），**禁止挂在 `_process` / `Timer`**，🔴 **MVP 禁止增量优化**（塔数 ≤ 6，全量 < 0.1ms）。

| 操作（本系统发起） | `N_tower` | `histmax` | `h_i` | `L_i` | `L_tag` | `Coverage` | `LinkGraph` | `E_i` | `κ/κ_r/StackCap` | `CoreTower` | `Crossfire` | `AoE` | `Aux` | 发出事件 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **① 装配**单塔效果卡 | — | — | — | ✅ | ✅ | — | — | — | ✅**全场**（档位可能跨档） | ✅ | — | — | — | `effect_attached` |
| **② 卸下改投** | — | — | — | ✅（−1） | ✅ | — | — | — | ✅**全场** | ✅ | — | — | — | `effect_detached`（+ `effect_attached`） |
| **③ 弃卡** | — | — | — | ✅（−n） | ✅ | — | — | — | ✅**全场** | ✅ | — | — | — | `effect_detached` |
| **④ 放置·新建** | ✅ +1 | ✅**可能刷新** | ✅ | — | ✅（若该原型有 Tag） | ✅ | ✅**重建** | ✅ | ✅**全场**（折价 + 档位） | — | ✅ | ✅ | — | `tower_added` |
| **④ 放置·升级** | — | — | ✅ +1 | — | ✅ | ❌**不触发** | ❌**不触发** | ✅**所有邻居** | ✅**全场**（档位） | — | — | ✅ | ✅（若挂件塔） | `tower_level_changed` |
| **⑤ 塔移除 `Salvage`** | ✅ −1 | 🔴**不变** | ✅ | ✅**全销毁** | ✅ | ✅ | ✅**重建** | ✅ | ✅**档位侧**（🔴 折价侧不变） | ✅ | ✅**可能跳档** | ✅ | ✅ | `tower_removed` |

**四条最易漏的（逐条写进代码注释）**

1. 🔴 **装配 / 卸下 / 弃卡都会改 `L_tag`** → `κ_tag` / `κ_r` / `StackCap` **三档位全场重算**（不只是 `Stack`）。漏了会出现"买了卡但利率没升档"。
2. 🔴 **升级塔（`h_j + 1`）不触发 `Coverage` / `LinkGraph`**（射程固定，CD-4 / D-10）—— 这是"**少做**"不是"少漏"。🔴 **保留 `mark_links_dirty()` 的调用点并注释掉**（`# T1 若射程随级变化，取消此行注释`），配套保留"`升级后 LinkGraph 逐位不变`"的断言。
3. 🔴 **`κ` 是逐塔当前值**：新建第 3 座塔 → 全场 κ 下降 0.01 → **已叠的 100 层利率被回溯下调**（定稿行为）。UI 必须在"建造"按钮上给出**折价预告 + 不可逆性披露**（H6）。
4. 🔴 **拆塔的两条 κ 路径要分开**：`histmax` 不动 → **折价不回退**；但装配卡全销毁 → `L_tag` 掉 → **档位可能从 0.10 掉到 0.06**（`StackCap` 亦可能 100 → 50，已叠层进入衰减区）。🔴 **不得**把"拆塔不回退"实现成"κ 完全不变"。

---

## 7. 边界与失败（Edge Cases & Failure Modes）

> 输出规范要求 ≥3 类；本节给 **15 类**（整合 `card-system` E1–E15 与 `damage-pipeline` E1–E20 中与装配 / 主塔 / 拆塔相关的全部条目，给出 **tower-build 视角的统一处置**，避免两处口径打架）。

| # | 边缘情况 | 统一处置（本系统负责的部分） | 上游出处 |
|---|---|---|---|
| **TBE-1** | **塔位已满 且 场上无同原型塔**（建筑卡无合法目标） | 商店**停止刷出**该卡（`core-defense` I8 `has_legal_target`）；已购卡滞留待放置队列，UI 显示"无可放置目标"并允许**以 50% 价格退回**（防死锁） | `card-system` E1 |
| **TBE-2** | **待放置队列积压** | 队列无上限；HUD 角标持续提醒；**安全窗强制提示一次** | `card-system` E2 |
| **TBE-3** | **卸下导致层数 1 → 0** | 该「卡种×宿主塔」组合从 `enh_slots` 移除 → **槽位释放**；`Stack` / `Focus` / `CoreTower` / `AllIn` 全部重算 | `card-system` E3 · `damage-pipeline` E14 |
| **TBE-4** | **主塔判定平局**（两塔 `L_i` 相同） | 取 **`reached_at` 更小者**（先达到该层数）。🔴 **禁止**用数组首个索引 → 徽章闪烁 | `card-system` E4 · `damage-pipeline` E7 · `core-defense` §2.9.1 |
| **TBE-5** | **全场 `L = 0`**（纯铺场 build，一座效果卡都没投） | `ΣL = 0` → `CoreTower = null` → 🔴 **`AllIn` 不触发**、`Focus` 全 `×1.00`、`Stack` 全 `×1.00`。**这是合法 build**（无 Tag 纯铺场），不得报错、不得降级为"取第一座塔当主塔" | `damage-pipeline` E8 · `card-system` §4.5.2 P3 |
| **TBE-6** | **场上 0 塔** | `CoreTower = null`；商店不刷出单塔效果卡（E9）；本系统装配入口无响应（无宿主） | `damage-pipeline` E1 · `card-system` E9 |
| **TBE-7** | **拆塔（`TowerRemove`）** | 二次确认 → 返还 50% → 装配卡全销毁 → 塔位释放 → 🔴 `histmax` 不回退 → 全场重算（§6 第 6 行）。**必须二次确认** | `card-system` E8 · `damage-pipeline` E13 |
| **TBE-8** | **新建塔刷新 `histmax` → κ 回溯下调** | 全场 κ 立即重算；商店与 HUD 同步刷新 κ 数字；建造按钮给出**折价预告 + 不可逆披露**；🔴 折价后 κ 不得归零（下限 0.02） | `card-system` E11 / E12 |
| **TBE-9** | **装配合法性冲突**（🔥卡 → ❄塔） | `can_attach` 返回 false → **降级为强制点选**（D-TB-6），战场高亮所有合法塔（含中性塔 `Arrow` / `Beacon`）；若无任何合法宿主 → 商店置灰（H8） | TB-7 · `damage-pipeline` D-8① |
| **TBE-10** | **强化槽满（5 个组合）** | 商店置灰 + H7 标注 `强化槽 5/5`；玩家须先**弃卡**（链 ③）腾槽。🔴 **禁止**自动弃卡 | `card-system` A2 · `shop-reroll` H7 |
| **TBE-11** | **装配 / 卸下目标为 `Disabled` 塔** 🔒 | **MVP 不发生**（无 `Disabled`）。T1 口径：🔴 **允许装配到 `Disabled` 塔**（它仍持有 `attached`、仍供 `h_j`、仍占 `N_tower`），但 UI 需标注"该塔已停机" | `mechanics-tower-life-death` §2.4 |
| **TBE-12** | **减速期间 / 同一帧多操作** | 重算走**事件时钟**（dirty flag，帧末一次）；🔴 `time_scale = 0.25 / 0.35` 下重算次数与 `1.0` 下**完全相同**，不漏帧、不卡顿 | `damage-pipeline` E20 · `core-defense` E8 |
| **TBE-13** | **升级塔后链接"应不应该"重算** | 🔴 **MVP 不重算**（射程固定 CD-4）。保留注释掉的调用点 + 一条"升级后 `LinkGraph` 逐位不变"的断言作安全网 | `damage-pipeline` 验收 9 · D-10 |
| **TBE-14** | **装配层数跨软 cap 边界**（100 → 101） | 由 `damage-pipeline` `softcap_pow` 内部夹取（`×1.10 → ×1.03`）；本系统只负责在徽章变色时给一次性 UI 提示"进入衰减区"。🔴 衰减不得归零 | `card-system` E5 · `damage-pipeline` E9 |
| **TBE-15** | **拆塔后主塔易主** | `CoreTower` 重算 → `core_tower_changed` 信号 → **徽章迁移演出**（旧塔徽章淡出 + 新塔徽章点亮，非静默切换）。若 `ΣL` 归 0 → `CoreTower = null`，徽章整体淡出 | `core-defense` §2.9.2 · 本 §8.1 |

**系统级失败模式**

| 失败模式 | 判据 | 兜底 |
|---|---|---|
| **主塔徽章抖动**（每帧闪烁 / 反复迁移） | 试玩中出现徽章在两塔间反复跳 | 根因几乎总是用了数组首个索引或未维护 `reached_at`。🔴 用 `reached_at` 稳定排序根治 |
| **缓存漏失效（幽灵数值）** | UI 显示的 DPS 与实际伤害不符 | 🔴 根因几乎总是"装配只重算了 `Stack`、漏了 `L_tag` → κ 档位"。用 §6 矩阵逐事件对照；禁止增量优化可根治 |
| **`AllIn` 泄漏到全局段** | 非主塔塔面板出现 `×1.6` | `AllIn` 是逐塔乘区（B6）。本系统只供 `CoreTower` 索引；若 UI 在全局条上显示 `×1.6` → UI 层错误 |
| **F-2 套利复发**（铺满拿 Crossfire/共鸣 → 后期拆光拿回 κ） | 终局塔数 ≤2 且 `histmax ≥ 4` 的局占比 > 70% | 🔴 根因 = `histmax` 被回退。计数器的唯一自增点见 D-TB-3；🔴 拆塔路径上**禁止任何对它的写操作** |
| **`Syn` 型问题第四例**（文档定 A、引擎跑 B） | 实现与纸面模拟对不上 | 🔴 本系统的三个"唯一写入权"字段（`attached` / `reached_at` / `n_tower_histmax`）必须只有一个写点；若出现第二处写 → 立即定位 |

---

## 8. UI / UX 编排（本系统交付给 UI 的规格）

### 8.1 主塔徽章与底座发光（🔴 A18 的可视化兑现）

| 项 | 规格 |
|---|---|
| 主塔标识 | **塔顶徽章** + **底座发光**（双通道编码，非色彩单通道 → 满足 art-bible §9 可访问性） |
| 徽章迁移 | `core_tower_changed` 触发**迁移演出**（旧塔淡出 + 新塔点亮），🔴 **禁止静默切换**（TBE-15） |
| 无主塔时 | `ΣL = 0` → 徽章整体不显示（🔴 **不是**显示在第一座塔上） |
| 🔴 硬约束 | **UI 中不得存在任何「设为主塔」按钮 / 右键菜单 / 拖拽设主塔入口**（A18 验收） |
| 挂件塔 | 不显示徽章；显示其**功能**（减速图标 / 光环圈） |

### 8.2 待放置队列与放置模式高亮

| 项 | 规格 |
|---|---|
| 队列图标 | HUD 右下角**蓝图图标** + 张数角标（无上限，E2） |
| 强制提示 | 安全窗进入时若队列非空 → **图标弹跳 + 角标**提示一次 |
| 放置模式 | 全局 `0.25×`；商店抽屉**收起**，战场全屏 |
| 空塔位 | **绿光脉冲**（= 新建），显示 `Lv1` 预览 |
| 同原型塔 | **金光脉冲**（= 升级），显示 `Lv_n → Lv_n+1` |
| 取消 | `Esc` 取消，🔴 **不退款**，卡留队列 |
| 无合法目标 | UI 显示"无可放置目标" + 允许以 50% 价格退回（TBE-1） |

### 8.3 卸卡 / 弃卡 / 拆塔的确认与文案

| 操作 | 确认级别 | 弹窗文案（可直接抄） |
|---|---|---|
| 卸下改投 | 🟡 **无弹窗**（悬停预览降 1 层即可，D-TB-2） | 悬停：`卸下改投 · 层数 12 → 11` |
| 弃卡 | ✅ 二次确认（`CanvasLayer 140`） | 「弃掉这张卡？<br>　销毁 **N 层**（🔴 不可回收，**0 返还**）<br>　释放 1 个强化槽」 |
| 拆除并回收 `Salvage` | ✅ **必须**二次确认 | 「拆除这座塔？<br>　返还 **X** 分（累计投入的 50%）<br>　销毁 **N** 张装配卡（共 **M** 层）🔴 不可回收<br>　**κ 不会因拆除而回升**」 |

> 🔴 **文案红线（C-3 / `shop-reroll` X7）**：**只标事实，不标推荐**。弹窗文案**以数字结尾，禁止出现劝阻词**（"不建议拆" / "会亏"）。事实是"会损失多少"，结论归玩家。
> 🔴 **弃卡 0 返还 vs 拆塔 50% 返还**必须在文案上明确区分（两者都是"销毁装配卡"，但经济后果不同）。

### 8.4 κ 折价预告（🔴 兜底①后的**强制披露项**）

| 项 | 规格 |
|---|---|
| 位置 | 商店"建造新塔"按钮上 + HUD κ 常驻数字 |
| 文案 | 「建造新塔：κ `0.10 → 0.09`（**拆除塔不会让 κ 回升**）」 |
| 🔴 为什么必须带后半句 | 兜底①把折价变成**永久生效**；只说"下降"不说"退不回来"是**不完整的事实披露**（`card-system` §11 验收 6 在 v1.1.5 后已加严为硬验收项） |
| 供数 | 由 `damage-pipeline` SR-2 供数（`evaluate_delta` **纯函数**，🔴 不得触发 `mark_dirty()`）；本系统只负责在建塔成功后保证 `histmax` 已刷新 |

### 8.5 三大乘区的暴露口径（🔴 R13：只暴露总倍率，不暴露公式）

| 项 | 规格 |
|---|---|
| 塔面板 | 显示**总倍率数字**（如 `×7.4`），🔴 **禁止**显示 `Focus` / `AllIn` / `Crossfire` 的公式或分项拆解 |
| `AllIn` | 主塔面板显示 `ALL-IN` 角标 + `×1.6`；🔴 **非主塔不得显示**（验收 6） |
| `Crossfire` | 全局段一个数字（如 `×1.5`），显示在 HUD 全局区；🔴 不得挂在单塔面板上 |
| 共鸣 | 链接光弧**亮度 / 粗细**编码 `E_i`；塔上只显示总倍率数字。🔴 玩家不需要会算 `E_i` |
| 跨软 cap | 徽章变色 + 一次性提示"进入衰减区"（TBE-14） |

### 8.6 给美术（林绘澄）/ 音频（阮和鸣）的交付

| 对象 | 交付 |
|---|---|
| 美术 | 主塔徽章 + 底座发光（双通道编码）；待放置队列蓝图图标；放置模式绿 / 金脉冲（复用塔位 `MeshInstance3D` 的 shader uniform，🔴 禁止每帧 new 节点）；二次确认弹窗（自定义 `Control`，禁用 `AcceptDialog` 默认值）；🔴 任何 VFX 不得遮挡塔轮廓与核心 HP 条（C-3 / 美术锚点 4） |
| 音频 | 装配 / 卸下 / 弃卡 / 拆除四类反馈需要**不同音效**（拆除 = 最重的一次）；🔴 UI 音效**不受 `time_scale` 影响** |

---

## 9. 与其他系统的接口契约（Dependencies）

### 9.1 依赖矩阵

| 依赖系统 | 本系统需要它提供 | 本系统向它提供 |
|---|---|---|
| **`core-defense`** ★强依赖 | I9 唯一写入口 `place_tower` / `upgrade_tower` / `scrap_tower`；I11 `get_core_tower()` / `get_core_tower_share()` / `core_tower_changed`；I1 `get_links` / I2 `get_E`；I5 `get_coverage_score`（逐塔几何，供默认宿主排序）；I7 `get_cover_count`；I8 `has_legal_target`；I10 `get_slot_states`；I12 `get_tower_count` | 建 / 升 / 拆的**编排请求**；`L_i` 变化通知（触发 `CoreTower` 重算）；`reached_at` 稳定排序键 |
| **`card-system`** | 卡定义（`kind` / `tag` / `compound` / `price`）；`enh_slots` / `global_slots` / `pending_structure`；A16 卸下 / 弃卡 / 塔移除规则；A5 κ 口径 | 装配 / 卸下 / 弃卡的**执行**；`TowerRemove` 请求；🔴 `n_tower_histmax` 单调保证 |
| **`damage-pipeline`** | `DamageCache`（读，不自算）；TB-1~TB-7 契约 | 🔴 `h_i` / `attached` / `L_i` 三个量；🔴 **五个事件**（`tower_added` / `tower_removed` / `tower_level_changed` / `effect_attached` / `effect_detached`）→ `mark_dirty()` |
| **`shop-reroll`** | 购买 / 点选 / 拆除的**请求**；五态时机约束；安全窗信号 | `can_attach`（TB-7 合法性）；`CoreTower`（默认宿主）；强化槽占用事实（H7）；放置目标合法性 |
| **`wave-spawner`** | 波次结束 → 安全窗 begin/end（决定重决策入口可用性） | 无 |
| **`mechanics-tower-life-death`** 🔒 T1 | 塔移除结算器触发源口径；红线 T-C1 / T-R1 / T-R2；`Disabled_i` 占位 | MVP 的 `TowerRemove(Salvage)` 分支落地；`Disabled_i ≡ 1.0` 占位保留 |

### 9.2 🔴 本系统的公开接口（工程实现清单 · 可直接照抄签名）

> 🔴 **编号冲突澄清**：`damage-pipeline` §8.2b 与 `shop-reroll` §8.6 **各自定义了一套 `TB-1~TB-x`**，编号撞车。本 GDD 统一采用前缀消歧：**`DP-TB-x`** = `damage-pipeline` 给本系统的契约（本系统→管线，供数）；**`SR-TB-x`** = `shop-reroll` 给本系统的契约（商店→本系统，请求）；**`TBA-x`** = 本系统对外公开的 API（下表）。见 §12 一致性登记 C-2。

| # | 接口 | 方向 | 签名 | 说明 |
|---|---|---|---|---|
| **TBA-1** | `attach_tower_effect` | 入 | `(card: CardDef, tower: Tower) -> bool` | 装配。商店默认传 `CoreTower`（`SR-TB-1`）。写 `attached` + `reached_at`；发 `effect_attached` |
| **TBA-2** | `can_attach` | 读 | `(card: CardDef, tower: Tower) -> bool` | `tag(tower) == None or tag(card) == tag(tower)`（`TB-7` / `SR-TB-2`） |
| **TBA-3** | `detach_tower_effect` | 入 | `(card: CardDef, from: Tower, to: Tower) -> bool` | 卸下改投。🔴 **降 1 层**；1→0 则释放槽。发 `effect_detached`（+ `effect_attached`） |
| **TBA-4** | `discard_tower_effect` | 入 | `(card: CardDef) -> void` | 弃卡。🔴 全销毁、0 返还、槽释放。发 `effect_detached` |
| **TBA-5** | `place_structure` | 入 | `(card: CardDef, slot: int, mode: Enum{New, Upgrade}) -> bool` | 放置（`SR-TB-3`）。转发 `core-defense` I9；新建时刷新 `histmax` |
| **TBA-6** | `request_tower_remove` | 入 | `(tower: Tower, source: Enum{Salvage}) -> bool` | 塔移除（`SR-TB-4` / `CS-7`）。🔴 校验"仅安全窗" + 二次确认已通过 → 转发 I9 `scrap_tower`。🔴 **不改 `histmax`** |
| **TBA-7** | `get_L` / `get_h` | 读 | `(tower: Tower) -> int` | `L_i = Σ attached.values()` / `h_i = tower.level`。🔴 **不缓存第二份** |
| **TBA-8** | `get_n_tower_histmax` | 读 | `() -> int` | 本局历史最大塔数（**只增不减**） |
| **TBA-9** | `get_default_host` | 读 | `(card: CardDef) -> Tower?` | 装配默认宿主（`CoreTower` → D-TB-5 回退 → `null`） |
| **TBA-10** | `get_legal_hosts` | 读 | `(card: CardDef) -> Array[Tower]` | 所有 `can_attach == true` 的塔（D-TB-6 强制点选时高亮用） |
| **TBA-11** | 事件 | 出 | `tower_added / tower_removed / tower_level_changed / effect_attached / effect_detached` | 🔴 **五个都必须被 `damage-pipeline` 订阅并 `mark_dirty()`**（`DP-TB-6`） |
| **TBA-12** | `get_enh_slot_usage` | 读 | `() -> (used: int, max: int)` | 强化槽占用事实（H7，`max = 5` 计组合非层数） |

### 9.3 🔴 三条实现铁律（写在代码文件头）

1. **单一写点**：`attached` / `reached_at` / `n_tower_histmax` 三个量**各自只有一个写点**，全部在本系统内。任何其它脚本出现对它们的赋值 = bug。
2. **事件驱动**：TBA-11 的五个事件是下游失效的**唯一**触发源。🔴 禁止在 `_process` 轮询、禁止用 `Timer`、禁止每帧 O(n²)。
3. **不重复计算**：本系统**不自算** `Focus` / `AllIn` / `Crossfire` / κ / `E_i` / `Delivered`。需要数字时读 `DamageCache`（SSOT）。

---

## 10. 验收清单（聚合上游相关条目 + 本系统专属）

> 前 11 条为**工程回归（硬性）**，后 5 条为**设计验收（试玩层）**。

**工程回归**

1. 🔴 **主塔涌现被看见 且 无"设为主塔"入口**：试玩中玩家能指出"那座塔是我的主塔"；🔴 代码库 `grep -rn "set_core_tower"` **无命中**；UI 无任何设主塔的按钮 / 菜单 / 拖拽入口。（`core-defense` 验收 11 · A18）
2. 🔴 **红线 R-3 回归（TB-R1）**：只建塔不投卡（`L_i = 0`，`h_i` 任意大）→ 塔面板 `Focus = 1.00`、**无** `ALL-IN` 角标；投第 1 张单塔效果卡 → `Focus = 1.06`。**若"只建塔不投卡"也能起飞 → 管线或本系统写错。**（`damage-pipeline` 验收 5）
3. 🔴 **`AllIn` 不泄漏到全局段**：6 塔铺场局中**非主塔**的塔面板**不显示** `×1.6`。（`damage-pipeline` 验收 6）
4. 🔴 **拆塔全场重算 + `histmax` 不回退**：拆塔后 `Ltot` / `CoreTower` / `Focus` / `AllIn` / `LinkGraph` / `Coverage` / `Crossfire` 全部正确刷新；🔴 `n_tower_histmax` **逐位不变**；κ 的**折价项**逐位不变（档位项可能因 `L_tag` 掉档而变化，两种都要断言）。（`card-system` E8 / 验收 10 · `damage-pipeline` E13）
5. 🔴 **卸下 1 → 0 释放槽**：卸下把某卡降到 0 层 → 该组合从 `enh_slots` 移除、`Stack` / `Focus` / `CoreTower` / `AllIn` 全部重算。（`card-system` E3 / `damage-pipeline` E14）
6. 🔴 **放置模式 `0.25×` 不漏帧**：`time_scale = 0.25` 下，重算次数与 `1.0` 下**完全相同**；`LinkGraph` / `Coverage` 重算不受 `time_scale` 影响。（`core-defense` 验收 3 / C-2）
7. 🔴 **升级塔不触发链接重算（CD-4 安全网）**：升级任意塔 +1 层 → `LinkGraph` 与 `CoverageScore` **逐位不变**；建塔 / 拆塔 → **必须变化**。（`damage-pipeline` 验收 9）
8. 🔴 **装配合法性单测（TB-7）**：🔥卡 → ❄塔 = `false`；🔥卡 → 🔥塔 = `true`；任意 Tag 卡 → `Arrow` / `Beacon`（中性塔）= `true`；无合法宿主时商店置灰。
9. 🔴 **主塔平局稳定（防徽章抖动）**：构造两塔 `L_i` 相同 → `CoreTower` 恒取 `reached_at` 更小者；连续 100 次无关操作（如刷新商店）后 `CoreTower` **不得变化**。
10. 🔴 **缓存一致性**：随机 1000 次操作序列（建 / 升 / 拆 / 装 / 卸 / 弃），每次操作后 `DamageCache` 与"从零全量重算"的结果**逐位相等**（相对误差 < `1e-9`）。（`damage-pipeline` 验收 4）
11. 🔴 **`histmax` 单调性单测**：任意操作序列后断言 `n_tower_histmax == max(历史 N_tower)`；🔴 拆塔序列**不得**使该值下降。

**设计验收（试玩层）**

12. ✅ **κ 折价是可感知的取舍，不是隐形陷阱**：玩家在建造第 3 座塔**之前**能说出"建塔会让我的复利率下降"，🔴 **并且知道拆除不会让它回升**。（`card-system` 验收 6 · H6 硬验收项）
13. ✅ **塔移除是可用但昂贵的反悔**：10 局试玩中至少出现 1 次塔移除，且玩家能说出"我认赔一半、换回一个塔位"；玩家能认出「拆除并回收 `Salvage`」这一个按钮**同时**是"卖"与"拆"（术语统一未造成认知分叉）。（`card-system` 验收 8）
14. ✅ **主塔可解释**：玩家能说出"我把效果卡都投给同一座塔，它就变成主塔了"（验证涌现被理解，而非被当成随机）。（`card-system` R-C2 的"先修 UI 再调数值"优先级）
15. ✅ **装配归属零误操作**：10 局试玩中**无一次**出现"我买了一张卡但不知道它投到哪座塔上"（验证 D-TB-5 默认宿主的可见性 + 战场高亮生效）。若出现 → 触发 D-TB-5 兜底（升级为首次装配强制点选）。
16. ✅ **轻重决策分层被遵守**：战斗内（态 ①②③⑤）卸卡 / 弃卡 / 拆除入口**一律置灰且不响应点击**；仅安全窗可用。（红线 T-C1）

---

## 11. T1 留口 与 本系统职责内的设计选择

### 11.1 🟢 设计选择（本系统职责内 · 我给推荐 · ✅ **2026-09-30 用户全批确认**）

> **为什么单独开这一节**：撰写中发现的 6 处口径缺口**全部落在 `tower-build` 自己的职责边界内**（编排 / 交互 / 归属），**零个新数值**，因此不需要用户拍板，主理人确认即可。
> ✅ **拍板留档**：D-TB-1 ~ D-TB-6 全部按推荐确认（用户 2026-09-30 全批）。其中 **D-TB-5（默认宿主）** 是最实质的一处，主理人已确认采纳"覆盖值最高的已建塔 + 可见可点选改投"。

| # | 设计选择 | ✅ 我的推荐 | 理由 / 代价 / 兜底 |
|---|---|---|---|
| **D-TB-1** | **`reached_at` 的序号从哪来？**（`core-defense` §2.9.1 只写了"全局动作序号"，未定义来源） | **全局单调计数器 `Run.action_seq`**：任何使 `L_i` 增加的操作（装配 / 卸下改投的落侧）`action_seq += 1`，并写 `tower.reached_at = action_seq`。🔴 **`action_seq` 只增不减，不随波次重置** | ① 它是**派生量不是新数值**，与 E4「取先达到该层数者」逐字同义；② 不随波次重置才能保证跨波平局仍稳定；③ 单塔数组的插入顺序变化不影响它。兜底：若出现 `reached_at` 相等（理论不可能，因每次 +1）→ 退化为 `slot_index` 升序（仍稳定） |
| **D-TB-2** | **卸下改投的交互顺序**（先点卡还是先点塔）？需要二次确认吗？ | **先点强化槽位上的卡 → 再点目标塔（2 次输入）**；点同一座塔 = 取消。🔴 **不需要二次确认弹窗**（降 1 层的预览在悬停时可见） | ① "先选物再选目标"与放置模式（先选卡再选塔位）**操作语法一致**，降低学习成本；② 卸下是**中等代价**（可再卸回，代价 1 层），给它加弹窗会稀释③⑤ 的警示重量（认知过载 R10）；③ 只有**不可逆且损失大**的 ③ 弃卡 / ⑤ 拆塔才配二次确认。兜底：若试玩出现"误卸"反馈 → 加一层"悬停 2 秒进度条"而非弹窗 |
| **D-TB-3** | **`n_tower_histmax` 归谁、在哪写？** | **挂 `Run.n_tower_histmax`**（与 `shop-reroll` §3.2 同名字段对齐）；🔴 **唯一自增点 = `place_tower()`（新建，非升级）成功返回后** `histmax = max(histmax, get_tower_count())`。🔴 拆塔 / `Disabled` / 塔位释放路径上**禁止出现任何对它的写语句** | ① 与 `shop-reroll` §3.2 的字段命名一致，避免两份状态；② "唯一写点"是防 F-2 复发的最强结构性手段（比在拆塔处写"不要回退"的注释可靠）；③ 新建才自增，升级不自增（`N` 不变）。兜底：§10 验收 11 的单调性单测 |
| **D-TB-4** | **二次确认弹窗点「取消」有代价吗？** | 🔴 **零代价**（纯取消，不消耗积分、不消耗减速预算、不改任何状态，回到弹窗前的态） | ① 取消是"我还没决定"，不该收费；② 若给取消加代价，玩家会因怕罚而盲选确认 → 违背"二次确认"的保护意图；③ 安全窗预算本就冻结（`shop-reroll` 态 ④），无预算可扣 |
| **D-TB-5** | 🔴 **`CoreTower` 未定义时（`ΣL = 0` 或 无塔），单塔效果卡默认投给谁？**（`card-system` §4.1 只写了"默认投主塔"，未定义主塔不存在的情况 —— 这是本次发现的**最实质的一处缺口**） | **默认宿主 = 覆盖值最高的已建塔**（`core-defense` I5 `get_coverage_score` 最大者）；**并列取 `creation_seq` 最早者**（与 E4 同族的稳定排序）。🔴 **并在商店卡面上把默认宿主塔的名字画出来 + 战场同步高亮该塔**，使"默认"完全可见 | ① `core-defense` §2.4.1 明写"**高覆盖位 = 天然主塔位**" → 与 P1 同向，且 `get_coverage_score` 是**静态关卡数据**、**不进伤害管线**（不受 §2.4.2 标定冲突影响）→ 零数值风险；② 保持 1 次输入可用（`card-system` §4.1 的硬指标）；③ "默认可见 + 可点选改投"使它不是"系统替玩家选路线"，而是一个**可覆盖的默认值**（H8 同源口径：只标事实）。<br>🟡 **诚实标注风险**：第一张效果卡落在哪，主塔就定在哪 → 默认值对"这局谁是主塔"有影响。<br>**兜底**：若试玩出现"玩家不知道卡投到哪了"（§10 验收 15 不达标）→ **升级为首次装配强制点选**（此时 2 次输入，仅首次），🔴 优先修 UI 不调数值 |
| **D-TB-6** | **默认宿主不合法（`can_attach == false`）时怎么办？**（例：主塔是 `Cannon` 🔥，玩家手上是 ❄ 卡） | **降级为「强制点选」**：卡面显示"选择宿主塔"，战场**只高亮 `get_legal_hosts()` 返回的合法塔**（含中性塔），点击落卡。仍是 2 次输入（与 `card-system` §4.1 的"点选塔 → 购买"分支同构）。若 `get_legal_hosts()` 为空 → 商店置灰（H8） | ① 沉默地改投到另一座塔 = 系统替玩家做归属决策（违反 P4）；② 报错拒绝 = 卡变成废卡（违反"买得到"）；③ 强制点选把决策交回玩家，且合法目标已高亮 → 认知成本极低。兜底：若玩家点空白处 → 视为取消，卡留在商店（🔴 不扣钱） |

### 11.2 🔒 T1 留口（仅登记口径，MVP 不实现）

| # | 项 | 登记口径 | 出处 |
|---|---|---|---|
| **T-TB-1** | **被动移除 `Destroyed` 分支** | 返还 **0%**；装配卡随 `Disabled` **冻结**（仍占强化槽）；塔位**不释放**；**不算失败**；战斗内零操作（T-C1）；波次间三选一：**修复 / 拆除（此时按 Q-C3 全销毁）/ 放着不管**。🔴 全部参数（`HP0` / `AGGRO_R` / `repair_cost`）本 GDD 不承载 | `mechanics-tower-life-death` v1.0 §2 · `card-system` E8-b |
| **T-TB-2** | **`Disabled_i` 因子** | MVP 恒 `1.0`，**乘法位必须保留**；T1 接管时只填 `0.0`，不改管线结构。🔴 `CoreTower` 判定在 `Disabled` 时**不变** | `mechanics-tower-life-death` §4.3 交接点 ③ |
| **T-TB-3** | **`Empowerment` 赋能乘区** | MVP 恒 `1.0`，**乘法位必须保留**（T1 直接填值）。它是"让副塔拥有自己的复利出口"的位置（Q11 已定 T1） | `damage-pipeline` C4 / 交接点 ⑨ |
| **T-TB-4** | **射程随等级成长 `R(L)`** | MVP 固定（`CD-4`）。T1 曲线 `R(L) = R₀ × (1 + 0.01 × min(L−1, 10))` 已由 `core-defense` §2.8.2 定死；🔴 启用时**必须取消 `mark_links_dirty()` 的注释**并重扫 κ_r | `core-defense` §2.8.2 / D-2 |
| **T-TB-5** | **装配到 `Disabled` 塔** | T1 口径：允许（`Disabled` 塔仍持有 `attached`、仍供 `h_j`、仍占 `N_tower`），UI 需标注"该塔已停机" | 本 §7 TBE-11 |
| **T-TB-6** | **修复 / 重建的成本关系** | 🔒 T1（`mechanics-tower-life-death` §4.1 点名需 `tower-build` 承载） | `mechanics-tower-life-death` §4.1 |

### 11.3 🟡 遗留风险（本系统侧，已知且接受）

| # | 风险 | 机理 | 触发条件 | 处置 |
|---|---|---|---|---|
| **R-TB-1** 🟡 | **「不敢建第 3 座塔」**（承接 `card-system` R-C1） | 兜底①让广度折价**永久生效**、建第 3 座的折价**不可逆** → 玩家可能把"建塔"归因为陷阱而非决策 | 试玩 10 局中「终局塔数 ≤2」占比 > **70%** | ① 本系统的缓解手段 = §8.4 的折价预告（**含不可逆披露**）；② 触发即切 `card-system` §5.2 兜底 ④b（逐层锁定），⚠️ 须同步规定"拆塔只清除增量、不追溯已叠层利率" |
| **R-TB-2** 🟡 | **默认宿主替玩家"定"了主塔**（D-TB-5 的诚实标注） | 第一张效果卡的落点决定 `CoreTower`，默认值若总落在同一类塔位上，会削弱 P3 的解空间 | §10 验收 15 不达标 | ① 优先修 UI（默认宿主可见化 + 战场高亮）；② 升级为**首次装配强制点选**；🔴 **不调数值** |
| **R-TB-3** 🟡 | **中性塔同挂两张复利卡**（T1🔥 + T4❄ 落在同一座 `Arrow`） | D-8① 允许中性塔接收任意 Tag 卡 → 复利组出现 2 项。由 `damage-pipeline` §5.4 **组内并联**兜底（不产生双指数），但该组合**引擎从未模拟过** | T1 或卡牌扩展时 | `damage-pipeline` D-3/D-8：建议补跑一次"双复利卡"build 确认不过热。本系统只需保证 `can_attach` 判定正确 |

---

## 12. 变更记录 与 一致性登记

### 12.1 跨文档一致性登记（本 GDD 撰写中发现，🔴 **均为文档回写项，非新拍板项**）

| # | 冲突 / 缺口 | 处置 | 需回写处 |
|---|---|---|---|
| **C-1** 🔴 | **κ 的 `N_tower` 口径**：`damage-pipeline` v1.0.5 §5.1 / §5.3 / §4.1 / §8.2b TB-5 仍写 `clamp(N_tower − 2, 0, 4)`（**当前塔数**），而 `card-system` v1.1.5 兜底①定稿为 **`N_tower_histmax`（本局历史最大塔数，只增不减）** | **以 `card-system` A5 / v1.1.5 为准（它是数值唯一权威）**：κ 折价读 `N_tower_histmax`；`Crossfire` 仍读**当前** `N_tower`（两个量不同，见 §2.4） | `damage-pipeline` §5.1 κ_i 行 / §5.3 公式块 / §4.1 伪码 `disc` 行 / §8.2b TB-5（拆成两行） |
| **C-2** 🟡 | **`TB-x` 编号撞车**：`damage-pipeline` §8.2b（TB-1~TB-7）与 `shop-reroll` §8.6（TB-1~TB-4）是两套不同的契约表，编号完全相同 | 本 GDD 用前缀消歧：**`DP-TB-x`** / **`SR-TB-x`**；本系统公开 API 用 **`TBA-x`**（§9.2） | 建议 `damage-pipeline` / `shop-reroll` 后续版本各加前缀 |
| **C-3** 🟡 | **射程随等级变化**：`card-system` §4.4 交接点 1 / E6 按"射程随等级变 → 链接重算"写；`core-defense` CD-4 / `damage-pipeline` D-10 已定 **MVP 射程固定** | **以 CD-4 为准**：本系统按固定射程编排（升级→5 连，`Coverage`/`LinkGraph` 不触发，§6） | `card-system` §4.4 / E6 回写（D-10 已列，此处同步确认） |
| **C-4** 🟡 | **`E_i` 漏写 `h_i ≥ 3`**：`card-system` §5.3 / A11 写 `Σ_{h_j≥3}`，实为**双向门槛** `h_i ≥ 3 ∧ h_j ≥ 3` | **按双向实现**（本 GDD §5 已按双向写）；🔴 它是本次免重扫 κ_r 的机理本身 | `card-system` §5.3 / A11（D-6 已列） |
| **C-5** 🟢 | **`n_tower_histmax` 的归属**：`card-system` §3.5 的 `Run` 未列该字段，`shop-reroll` §3.2 已列 | **统一挂 `Run.n_tower_histmax`**，唯一写点见 D-TB-3 | 建议 `card-system` §3.5 同步补该字段 |

### 12.2 变更记录

| 版本 | 变更摘要 |
|---|---|
| **v1.0**<br>（Phase 2 系统拆解 · 最后一份核心系统 GDD）<br>🔴 **零新增定稿数值 · 不开新待拍板项** | **① 系统定位（§1.4）**：明确本系统**不拥有任何数据实体**，只编排四条操作链 + 维护三个"唯一写入权"字段（`attached` / `reached_at` / `n_tower_histmax`）；给出完整权限边界表（谁写 / 谁读 / 谁只读订阅）。<br>**② §2.2 核心数据流**：`L_i` vs `h_i` 的解耦（红线 R-3）逐层展开，给出**两种典型误读**（A：把 `h_i` 当 `Focus` 基数；B：摘除预热门槛）与各自的回归判据。<br>**③ §2.3 主塔涌现**：逐字引用 `core-defense` §2.9 的 `argmax_i(L_i, −reached_at_i)` 算法 + 只读接口；🔴 全文不得出现 `set_core_tower()`。<br>**④ §2.4 三大乘区**：以"输入从哪来 / 何时重算 / 谁算"三列表呈现 `Focus` / `AllIn` / `Crossfire`；🔴 点明 **`Crossfire` 读当前 `N_tower`、κ 折价读 `N_tower_histmax`** 是两个不同的量。<br>**⑤ §2.5 κ 与兜底①**：κ 公式与折价表原样引用；🔴 明确"**兜底①只锁折价项、不锁档位项**"（拆塔销毁装配层 → `L_tag` 掉 → `κ_tag` 档位仍可变）。<br>**⑥ §4 四条操作链**：装配 / 卸下 / 弃卡 / 放置 / 塔移除的时机、输入次数、代价、二次确认级别总表 + 逐链流程；🔴 红线 T-C1 落地（重决策仅安全窗）。<br>**⑦ §6 重算编排矩阵**：`card-system` §4.4 + `damage-pipeline` §4.2 的塔侧合订本（6 行 × 14 列）+ 四条最易漏。<br>**⑧ §7 边缘情况 15 类**：整合 `card-system` E1–E15 与 `damage-pipeline` E1–E20 中与装配 / 主塔 / 拆塔相关的全部条目，统一处置口径。<br>**⑨ §8 UI/UX 编排**：主塔徽章 + 底座发光（无设主塔入口）、待放置队列、放置模式绿/金高亮、卸/弃/拆的确认级别与可直接抄的弹窗文案、κ 折价预告（含不可逆披露）、R13 只暴露总倍率。<br>**⑩ §9 接口契约**：依赖矩阵 + 本系统公开 API `TBA-1 ~ TBA-12`（含签名）+ 三条实现铁律；🔴 消解 `TB-x` 编号撞车（C-2）。<br>**⑪ §10 验收清单 16 条**：聚合上游相关条目 + 本系统专属（`histmax` 单调性单测、装配归属零误操作、轻重决策分层）。<br>**⑫ §11 设计选择 D-TB-1 ~ D-TB-6**：6 处口径缺口全部在职责内消化（🔴 其中 **D-TB-5「`CoreTower` 未定义时的默认宿主」是本次发现的实质缺口**，已给推荐 + 诚实标注风险 + 兜底）。<br>**⑬ §12 一致性登记 C-1 ~ C-5**：🔴 **C-1 = κ 的 `N_tower` 口径**（`damage-pipeline` v1.0.5 仍写当前塔数，须回写为 `N_tower_histmax`）。 |

---

*文档结束 · `tower-build` GDD **v1.0 定稿** · **Phase 2 系统拆解的最后一份核心系统 GDD** · 🔴 **零新增定稿数值**（`Focus 0.06` / `AllIn 1.6·60%` / `Crossfire 1.0·1.25·1.5` / κ 公式与 `N_tower_histmax` / 返还 50% / 装配卡全销毁 / 软 cap / 共鸣门槛 `h≥3` / 放置 `0.25×` 全部引用上游）· 🔴 **不开新待拍板项**（6 处缺口消化为 §11.1 D-TB-1~D-TB-6）· **本系统不拥有数据实体**（`Tower` 归 `core-defense`、卡池归 `card-system`、计算归 `damage-pipeline`），**只拥有三个量的唯一写入权**：`attached` / `reached_at` / `n_tower_histmax` · 下游必读：**§2.2 `L_i` 与 `h_i` 的解耦（R-3）** + **§6 重算编排矩阵** + **§9.2 公开接口 `TBA-1~TBA-12`** + **§10 验收清单** · 🔴 三条实现铁律：**单一写点 / 事件驱动（禁每帧 O(n²)）/ 不重复计算（不自算任何乘区）** · 🔴 一致性登记 **C-1（κ 的 `N_tower` 口径需回写 `damage-pipeline`）** · 遗留观察项：**R-TB-1（不敢建第 3 座塔，承接 `card-system` R-C1）/ R-TB-2（默认宿主影响主塔归属）/ R-TB-3（中性塔双复利卡，属 `damage-pipeline` D-8）** · T1 留口：**`Destroyed` 分支 / `Disabled_i` / `Empowerment` / `R(L)` / 装配到 `Disabled` 塔 / 修复成本关系***
