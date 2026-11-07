# 塔等级显示（2026-11-07）

> 范围：新增 `scripts/ui/tower_level_layer.gd`；接线 `scenes/battle_shop.tscn` + `scripts/ui/battle_shop.gd`；
> 世界层新增两个只读函数 `monster_layer.gd :: world_to_screen()` / `world_scale()`。
> 断言：新增 `tests/run_tower_level_asserts.gd`（26 项，入口 `-- tlv`）。
> 性质：**纯表现层**。零玩法写入、零新信号（只单向订阅）、零 snapshot 字段变更、不碰数值。

---

## 1. 症状（改前）

塔的「几级」**只靠形态暗示**：

| 等级 | 形态（`monster_layer._draw_tower_form`） |
|---|---|
| h ≥ 2 | 内环 |
| h ≥ 3 | 护角 |
| h ≥ 5 | 星点 |
| h ≥ 8 | 外环（满级形态） |

三条后果：

1. **h = 9 与 h = 99 画面完全一样** —— 形态在 8 级封顶，之后买卡没有任何视觉反馈；
2. 形态是**冗余通道**（环 / 护角 / 星点），新玩家无法反解"这是几级"，只能感觉"更强"；
3. 商店 H5 提示已经用文字写 `Lv 3 → 4`，**战场上却没有对应读数** —— 买卡前后无法自证。

## 2. 为什么单开一层（而不是写进 `monster_layer.gd`）

`monster_layer.gd` 有一条已经钉死的红线 **AC-T1-24「零文本」**：`run_ui_style_asserts.gd`
与 `test_suite_t1_aggro.gd` 都做**源码级**断言，要求该文件不含 `draw_string(` / 不含 `Label`
（用于守 T-E1③「零择时读数」）。

等级是**静态事实**（不随时间变），不是择时读数 —— 但断言是文件级的。
**换文件承载文本，比放宽红线安全得多**。于是新增 `tower_level_layer.gd`：
与 `vfx_layer.gd` 同族（只读快照 + 纯绘制的叠加层），分层清晰且不动既有红线。

层序（`battle_shop.tscn` 的 `Battlefield` 子节点顺序 = 绘制顺序）：

```
MonsterLayer     ← 塔身 / 怪物
TowerLevelLayer  ← 等级牌（本层）
VfxLayer         ← 伤害数字（战斗时可读性优先级：伤害 > 等级）
```

## 3. 版式决策

| 项 | 决定 | 理由 |
|---|---|---|
| 文本 | `Lv`（小号 0.70×，染等级色）+ 数字（大号近白） | 整串同字号时长 `Lv 120` 宽 ≈ 55px，比塔身直径（≈29px）还宽一倍 → 密集摆塔时压在邻居塔上；拆开后 ≈ 34px，且「这是等级」一眼可读 |
| 底色 | 深底胶囊 `#101423` 90% + 1px 等级色描边 | 亮塔身 / 怪身上都可读；与 HUD 面板同一种「暗底 + 细边」语言 |
| 位置 | **塔身右上角外侧**（对角外扩 `0.72R`） | 正上方已被占用：决策期是 `_draw_exposure_icons`（⚔/🛡），⑤ 态是放置悬停徽标 —— 三样东西抢同一块地。对角外侧在**所有状态**下都空着（复活充能点在下、受击闪/橙环环绕塔身不外扩） |
| 字号 | `1.75 × sc`，夹在 14–17px | 1080p 基准屏 `sc ≈ 8.5` → ≈15px；12px 在 1600×900 下会被压到 ≈10 物理 px，与最小档伤害数字（20px）差距过大、糊成一团（截帧实测） |
| 色阶 | 青 `#3ED0E8`（<5） / 金 `#FFC94A`（≥5） / 紫 `#7A5CFF`（≥8） | 与形态语言对齐；**色相只是冗余通道**，数字才是主通道（色觉可访问，art-bible §9.2①） |
| 停机塔 | 整牌压暗（`disabled` 透传） | 与塔身压暗同义，保留读数（"这塔还在，只是停了"） |

## 4. 实现要点

- **数据源**：`runtime.snapshot().slots[]`（`{slot, ctype, h, empty, disabled}`）——
  与 `monster_layer` 画塔同一份，**零新增 snapshot 字段**，空槽跳过。
- **坐标**：复用 `MonsterLayer.world_to_screen()` / `world_scale()`。
  🔴 不自己复写一份 `_xform`：抽屉展开会改可视宽 → 战场重新居中，两份换算一旦漂移，
  等级牌就会和塔身错位（本项目已经踩过"手抄第二份网格数字"的坑）。
- **重绘节流**：15Hz 轮询 + 条目签名（`slot:h:x:y:disabled`）比对，变了才 `queue_redraw()`。
  一次 `snapshot()` 的成本 ≈ `_draw_radial_towers()` **每帧**已经在调的那次 → 可忽略。

## 5. 踩到的坑：抽屉展开后等级牌飘到塔右侧 500px

**现象**：`-- after 02-shop-open` 帧里，牌全部停在"抽屉还没开"的旧坐标上。

**根因两条叠加**：

1. 抽屉在**安全窗**里展开，此时 `get_tree().paused == true`；本节点是默认 `PAUSABLE`
   → **`_process` 不跑**，轮询完全停摆；
2. 抽屉展开会改可视宽（`MonsterLayer._field_width`）→ 战场重新居中 → **所有塔位整体位移**，
   而缓存里的屏幕坐标还是旧的。

**修复**（三条一起上，缺一条都会复发）：

| # | 修复 | 作用 |
|---|---|---|
| 1 | 订阅 `ShopController.shop_changed / run_changed` + `TimeDirector.state_changed` | 暂停态下信号回调照常触发 → 轮询停摆也能更新 |
| 2 | `_draw()` 开头先 `_rebuild(true)` | 信号漏接时按**此刻**的变换兜底重算，不至于整局错位 |
| 3 | `_rebuild(silent)` 的 `silent` 分支不发 `queue_redraw()` | 避免「绘制中再触发绘制」 |

## 6. 验证

**截帧**（`tests/probe_tower_level.gd`，非 CI，真实窗口）：

```
G:/AI Demo/shots_towerlevel/before-01-combat.png        改前：一圈塔，无任何数字
G:/AI Demo/shots_towerlevel/after-01-combat.png         改后：每塔右上角一块等级牌
G:/AI Demo/shots_towerlevel/after-01-combat-zoom.png    3× 放大：字形锐利 / 垂直居中 / 不压塔身
G:/AI Demo/shots_towerlevel/after-02-shop-open-zoom.png 决策期：⚔/🛡 徽标与等级牌不抢位
```

**断言**（`-- tlv`，headless，26 项全绿）：

| 组 | 覆盖 |
|---|---|
| [1] 源码纪律 | 读 `snapshot()` 的 `slots[].h`；不摸 `player.towers`；`emit_signal` 不出现；`monster_layer` 仍零文本；坐标经 `world_to_screen`；锚点按 `R` 对角外扩；字号下限 ≥14 且封顶 ≤24 |
| [2] 场景接线 | tscn 挂载脚本；层序 `MonsterLayer < TowerLevelLayer < VfxLayer`；三绑齐 |
| [3] 条目语义 | 空槽跳过；`h` **逐位等于快照（h=12 原样显示，不被形态档位截断到 8）**；坐标来自世界层换算；`disabled` 透传；签名不变则不重绘；升级 / `shop_changed` 后签名必变 |
| [4] 抽屉开合 | 变换改变后按**新**变换重算（不留旧战场宽度坐标）；`_draw` 开头自愈 |
| [5] 退化态 | 未绑定 / 空快照不崩、条目为空 |

**负向验证**（证明断言有牙）：把 `_rebuild` 的 `h` 注入 `mini(h, 8)` → `座 1 等级…（got=8 want=12）`
**FAIL=1**；还原后 PASS。一条「新旧都过」的断言等于没有断言。

## 7. 未做 / 后续

- **无等级上限提示**：现在 h 是多少就显示多少（形态在 8 封顶，数字不封顶）。若后续引入
  `tower_h_cap`，这里应加「满级」标记（如 `Lv 12 MAX`），否则玩家会误以为还能升。
- **未做遮挡消解**：同屏塔极密（>12 座）时相邻等级牌可能重叠。当前布局下不会发生
  （自由摆放有最小间距），若上限放宽需要引入避让。
- **未改形态语言**：`_draw_tower_form` 的 2/3/5/8 四档完全没动 —— 等级牌是**叠加**的读数通道，
  不是替代。
