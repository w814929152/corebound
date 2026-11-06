# 扩展包（Extended Pack）— 新塔 / 新强化 / 玩家卡池扩充

> **归属**：数据层（`scripts/data/`）+ 商店层（`scripts/gameplay/`）+ 呈现层（`scripts/ui/`）
> **切入口**：`shop_runtime.extended_pack`（默认 `false`）· **一行可回滚**
> **提交**：2026-11-06 · 承接用户「丰富更多玩法」需求
> 🔴 **金标本 `TOWERS` / `ShopAI.CARD_NAMES` / `WEIGHTS` 一字未动**，默认路径逐位不变。

---

## 1. 为什么不能直接往 `TOWERS` 里加卡

这是本次最关键的一次判断，值得写清楚。

`TOWERS` 与 `ShopAI.CARD_NAMES` / `WEIGHTS` 是 **Python 金标本的逐位对齐对象**（control-manifest §1「塔数值表」= SSOT）。抽卡走：

```gdscript
var picks = rng.choices(CARD_NAMES, _card_w(), k)
```

`PyRandom.choices()` 是「累积权重 + `bisect_right`」，**卡池里多一个元素，权重总和就变，随后每一局的每一次抽卡落点全部平移**。后果不是"略微不同"，而是：

- 300 局 MC 的起飞率、中位波次全变 → ⑤ 门禁（B ≥ 0.80）读数作废
- slice1/2 的金标本逐位断言直接翻红
- 项目所有已签字的基线（如 `B@6 = 0.850`）失去意义

按 control-manifest 的规矩，这种改动要走 **ADR + 用户重签基线 + 重跑 300 局 MC**——为一个 demo 期的内容扩充，代价不成比例。

## 2. 采用的姿势：扩展表 + 玩家池派生

关键发现：**实机玩家商店早就和 AI 池分离了**。

`shop_runtime.gd` 里：

```gdscript
static func player_card_names() -> Array:   # 玩家路线（实机）
    return _pool_names                       # 由 ShopAI.CARD_NAMES 派生，排除 RerollD

static func _build_player_pool() -> void:
    for nm in _ShopAI.CARD_NAMES: ...        # 只读金标本，不写
```

这段是切片4 时代为「D-4 排除 RerollD」建的，注释明确写着 *「金标本 CARD_NAMES / WEIGHTS 一字不动（AI 路线仍 7 张含 RerollD，MC 不变）」*。

于是扩展包的全部改动收敛为：

```
TowerData.TOWERS_EXT / REINF_EXT / EXT_WEIGHTS      ← 独立表，主表不动
        ↓
ShopRuntime._build_player_pool()  末尾追加         ← 仅 extended_pack = true 时
        ↓
实机商店（玩家）拿到 10 张卡                        ← AI / MC / 金标本仍走原 7 张
```

### 三个必须配套的兼容点

| 点 | 不做的后果 |
|---|---|
| `TowerData._tower_def()`：先查主表、再查扩展表 | `tower_dps("Lance")` 直接 KeyError 崩溃（`geo.gd` / `damage_engine.gd` 都调它） |
| `ShopRuntime._card_kind()`：先查扩展表、回落金标本 | `Lance` 被判成 `"econ"` → 买建筑卡走全局卡分支：**扣 12 分、不落塔** |
| `_build_player_pool()` 的静态缓存清理 | `set_extended_pack()` 静默失效（`if not _pool_names.is_empty(): return` 提前返回） |

## 3. 新内容设计

现有三塔构成「泛用 / 群伤 / 控制」，缺两个轴：**射程**与**贴身**。

| 卡 | 类型 | dps | tag | rng | slow | aoe | 定位 |
|---|---|---|---|---|---|---|---|
| **Lance** | 塔 | **11.0** | `pierce` | **26.0** | 0 | ✗ | 远程狙击：射程与 dps 双高 |
| **Tesla** | 塔 | 6.0 | `shock` | **16.0** | 0.10 | ✓ | 贴身通电：全塔最低 dps，换群伤 + 微减速 |
| **PirUp** | 强化 | — | `pierce` | — | — | — | Lance 专属 |
| **ShkUp** | 强化 | — | `shock` | — | — | — | Tesla 专属 |

对照既有三塔：Arrow `10/22/无tag`、Cannon `7/18/fire`、Frost `5/20/frost`。

### 平衡的取舍在哪

新塔**不是**旧卡的上位替代，靠两点撑住：

1. **独立 tag** ⇒ 协同投资（`tag_invest` / κ）与旧流派完全不共享。想让 Lance 吃到 κ 折扣，得从零堆 pierce 投入，这期间它是"裸塔"。
2. **权重要稀**：Lance `0.09`（≈ Arrow 0.17 的一半）、Tesla `0.10`、强化 `0.075`。池变大后老卡概率等比下降，但新卡本身也不容易刷到。

🔴 **代价要说清**：这是**玩家侧**的玩法扩充，AI 侧（MC 门禁）看不到这些卡。所以「扩展包口径的平衡性」**没有 MC 数据支撑**——它是设计直觉 + 既有机制复用，不是跑过 300 局的结论。真要把它做成出货口径，仍必须走 §1 那套 ADR + 重签基线流程。

## 4. 渲染

**新塔不引入新色相**——这是刻意的，中间改过一版又退回来了，过程值得记一笔。

最初的方案是给 Lance 紫 `#AD8FFA`、Tesla 电黄 `#EDE059`。截完图才发现：

> **RADIAL 实机根本不走 `_tower_color()`。** `_draw_radial_towers` 里塔身是硬编码的 `P_ALLY`（统一青）+ `P_ALLY_DARK`，原型区分**只走内形通道**（`_draw_radial_tower_glyph` 的边数）。

也就是说 S5 当年做「三塔原型区分」时，选的就是「统一色 + 内形边数」，而不是「每塔一色」。而且这和 S4 的教训一致：Cannon 原本是橙 `#F28C4D`，与敌橙 `#FF6B3D` 撞色被改成青——**玩家塔必须整体待在冷色极**做敌我识别，紫（近精英品红 `#E8437F`）、黄（近敌橙）都会把「自己的塔」读成「威胁」。

所以最终：

| 卡 | 塔身色 | 内形边数 |
|---|---|---|
| Lance | 统一青 `P_ALLY` | 五边形（5） |
| Tesla | 统一青 `P_ALLY` | 七边形（7） |

- 外轮廓 8 重对称**一字未动**（`_oct8` 红线），只改内芯徽记的 `n`/`rot`
- `_tower_color()` 里扩展塔回落到 `C_TOWER_ARROW` —— 该函数**只服务 legacy PATH 模式**，PATH 下同色可接受

### ⚠️ 一个诚实的可辨性风险

放大实机截图判读过：内芯徽记半径 0.31R（≈5px），而左上白色高光半径 0.30R 就压在旁边，**五边形 / 七边形在这个尺寸下与六边形、甚至圆形都不易分辨**。

这是 S5 就已存在的天花板（当时为「六边形在 ~10px 下偏圆」把徽记从 0.26R 放大到 0.31R，+19%）。再往上放大就会撞内环（h≥2 细环 0.46R），高光外移方案（选项 C）已被 team-lead 明确否决。

> 🔴 结论：**新塔的可辨性没有真正解决，只是没有变得更糟**。若要把扩展塔做成出货内容，需要 art-director 重新裁定径向塔的原型通道（例如外轮廓角标、环层数、或引入第三种形状语言）。这是视觉设计决策，本任务不越权处理。

## 5. 开关与回滚

```gdscript
# scripts/ui/boot.gd · 窗口模式分支
ShopRuntime.set_extended_pack(true)
```

- **默认 `false`**：玩家池 6 张，与改动前逐位一致
- **`true`**：玩家池 10 张
- **回滚**：改成 `false` 或删掉该行（无需改动任何数据表）
- **headless / `--script` 路径永不进入该分支** ⇒ 任何测试读数不受影响

## 6. 验收

| 项 | 结果 |
|---|---|
| `tests/run_ext_pack_asserts.gd` | **54 项全过**（A 表结构 / B 新塔数值 / C 老塔逐位不变 / D 强化 tag / E 卡种判定 / F 池开关 / G 追加顺序） |
| `tests/probe_ext_pack_e2e.gd` | 真场景真链路：卡种=tower、定价 12、买入入 pending、落子后 `towers` 含 Lance/Tesla、`dps_only()` 不崩 |
| 切片4（商店核心） | 123 项全过 |
| 默认全量回归 | 见下方实测记录 |
| 金标本 `CARD_NAMES` | 仍 7 张、不含扩展卡（断言 F14/F15 钉住） |

## 7. 已知边界

| # | 边界 | 说明 |
|---|---|---|
| 1 | **AI 侧用不到新卡** | MC 门禁不覆盖扩展包口径，其平衡性无数据支撑（见 §3 末） |
| 2 | **aoe 字段的实际效力** | `TOWERS[x]["aoe"]` 是移植自金标本的标记位，战斗侧的 AoE 走 `damage_engine` 的全局乘区；Cannon 的 `aoe=true` 与 Tesla 一样，**不额外展开为多目标**。新塔沿用同一语义，未新增机制 |
| 3 | 未加**新机制**（穿透 / 链电 / 光环） | 表结构只有 `dps/tag/aoe/slow/rng` 五个维度；新机制需要动 `damage_engine` 与金标本，超出"不破默认口径"的边界 |
| 4 | 权重未经 MC 调优 | 见 §3 |

> 如果后续要把扩展包做成出货口径，最小改动路径是：把这四个条目并入 `TOWERS` / `CARD_NAMES`，同步改写 `design/phase2/numeric-sim/corebound_sim_v03.py`，重跑 300 局 MC，然后由用户重签基线。**那是一次独立的、需要拍板的工程，不在本次范围内。**
