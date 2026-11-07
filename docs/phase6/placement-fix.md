# 放置模式修复：为什么「买了建筑卡却放不下塔」

> 报告症状：**无法放置防御塔**。
> 结论：不是玩家操作错，是**落子入口根本不可达** —— 两条输入路径同时是死的。
> 这是主循环断链（买卡 → 落子 → 构筑），严重等级等同「游戏玩不下去」。

---

## 1. 根因：两条路径同时断

### 路径 A：抽屉里的 6 个塔位按钮（死代码）

`shop_overlay.gd` 的 `_refresh_placement()` 会在 ⑤ `PlacementMode` 下建 6 个塔位按钮，
点击 → `director.exit_placement(true, slot)`。看起来是完整实现。

但同一个文件里：

```gdscript
func _refresh_mode(drawer: int) -> void:
    visible = (drawer != _TSM.Drawer.CLOSED)
```

而状态机给 ⑤ 的档位是 **`Drawer.CLOSED`**（GDD `shop-reroll` §2.1 表格：⑤ 态「抽屉收起，战场全屏」）。
`visible = false` 会隐藏**整棵控件树**，包括那 6 个按钮。

实际取证（`tests/probe_placement.gd` 改造前）：

```
[place] sm.state         = 4 (PlacementMode)
[place] clock.drawer     = 0
[place] shop.visible     = false
[place] 塔位按钮数 = 6，第 0 个 is_visible_in_tree = false
```

⇒ 按钮存在、信号连好、逻辑正确，但**玩家永远点不到**。这是典型的「写了但没接进可达路径」：
单元层面每一块都对，拼起来没有入口。

### 路径 B：战场点击（两道闸都关着）

`monster_layer.gd` 的 `_unhandled_input()`：

```gdscript
var drawer_open := (int(time_director.sm.clock()["drawer"]) != 0)
if not drawer_open:
    return                                   # ① ⑤ 态 drawer = CLOSED → 直接返回
var hit := _hit_tower_slot(mb.global_position)   # ② 只遍历已建塔
```

- **闸①**：要求抽屉展开。⑤ 态抽屉恰恰是收起的 ⇒ 点战场什么都不发生。
- **闸②**：命中判定只遍历 `runtime.player.towers`（已建塔）。而落子的目标通常是**空塔位** ⇒
  就算过了闸①，「新建」也永远不可能被点中。

### 顺带发现的第三个 bug：信号发错了对象

同一段代码：

```gdscript
if director != null:
    director.emit_signal("tower_select_requested", hit)
```

`battle_shop.gd` 的注入是：

```gdscript
ml.bind_director(wave_director)      # → layer.director = WaveDirector
ml.bind_time_director(director)      # → layer.time_director = TimeDirector
```

`tower_select_requested` 声明在 **TimeDirector** 上，却发给了 **WaveDirector**
⇒ 「点选塔」功能（强化卡指定宿主）也一直是静默失效的。这条不在本轮报告里，
但同源、同函数、同一次修复。

### 第四个：命中半径量纲混用

```gdscript
var hit_radius_world := maxf(9.0, sc * 1.6)     # 注释说"塔身半径 + 余量"
```

`sc` 是**像素/世界单位**（径向模式 ≈ 28）。`sc * 1.6 ≈ 45` 被当成**世界**半径，
换算到屏幕是 `45 × 28 = 1260 px` —— 六个塔位全在半径内，点哪都命中最近的一个。
正确写法要么 `1.6 / sc`（像素 → 世界），要么干脆用屏幕距离（本轮采用后者）。

---

## 2. 修复：落子主路径回到 GDD 原意

GDD `shop-reroll` §2.1 对 ⑤ 的定义一直是「**点塔位落子 / Esc**，抽屉收起，战场全屏」。
战场点击本来就是设计原意，抽屉里那排按钮是工程侧的二次发明 —— 而且不可达。

### 2.1 状态机侧：新增意图信号

`time_director.gd`：

```gdscript
## 与 placement_confirmed 分工：本信号是**意图**（谁想落在哪），
## placement_confirmed 是**决定**（退出放置模式并执行）。
signal slot_place_requested(slot: int)
```

### 2.2 渲染层：⑤ 态画高亮、发意图

`monster_layer.gd` 新增层 4.5 `_draw_placement_marks()`，按 `snapshot.place_modes` 逐位绘制：

| 模式 | 颜色 | 塔位圈 | 徽标符号 |
|---|---|---|---|
| `new`（可新建） | 耀青 `#3ED0E8` | 比空槽大 20%、加粗、半透明填充、±10% 呼吸外环 | ＋ |
| `upgrade`（可升级，同原型叠层） | 辉金 `#FFC94A` | 同上 | ↑ |
| `invalid`（不可用） | 钢灰 α0.40 | 与空槽同尺寸、细线 | ✕ |

- **零文本**（AC-T1-24：渲染层代码行无 `draw_string`）：符号全部用 `draw_line` 画。
  「＋」= 两条正交线段，「↑」= 竖杆 + 两斜边，「✕」= 两条对角线。
- 徽标画在塔位**正上方**（`-rr * 1.40`），不压塔身；暗盘衬底保证在深底和亮塔上都可读。
- 线宽随 `sc` 走（`maxf(3.0, 0.30 * sc)`）。第一版写死 1.5px，1600×900 实机上根本认不出 ＋。

输入侧：

```gdscript
if _in_placement():
    var hit_any := _hit_slot_screen(mb.global_position, false)   # 全部塔位，不是只有已建塔
    if hit_any < 0:
        return
    var mode := String(controller.runtime.placement_mode_for(hit_any))
    if mode != "new" and mode != "upgrade":
        return                                    # 灰显位不响应，也不退出放置
    time_director.emit_signal("slot_place_requested", hit_any)
```

命中判定改为**屏幕距离**（`_hit_slot_screen`），半径 = 塔位轮廓半径 `U_SLOT * sc`（≈42px），
不再做世界坐标换算。

**点错不踢人**：点空地、点灰显位都只是「无反应」，退出只认 Esc。
误点就把玩家踢出放置模式（卡退回队列、要重新点「放置」）是最烦人的那种 bug。

### 2.3 接线层：非 ⑤ 态丢弃

`shop_controller.gd`：

```gdscript
func _on_slot_place_requested(slot: int) -> void:
    if int(director.sm.state) != _TSM.State.PLACEMENT_MODE:
        return                                      # T-C1 / E16：战斗内禁止塔操作
    if String(runtime.placement_mode_for(slot)) == "invalid":
        return
    director.exit_placement(true, slot)
```

渲染层先挡一次非法位，这里再兜一次 —— 两道闸，任何一侧被误改都不会让非法落子通过。

### 2.4 删除死代码

`shop_overlay.gd` 删掉 `_place_box` 字段、构建块、`_refresh_placement()`（共约 50 行）。
保留它只会让后来人以为「有入口」。

### 2.5 提示文案

| 位置 | 改造前 | 现在 |
|---|---|---|
| HUD 键位行 | ⑤ 态仍写「Tab 商店 · R 刷新」——这两个键在 ⑤ 态根本不响应 | 「放置模式：点亮光的塔位落子（＋ 新建 · ↑ 升级）· Esc 取消（卡退回队列，不退款）」 |
| 引导浮层 PLACE 步 | 「点「放置」→ 再点一个塔位落子」——进了 ⑤ 还让玩家点「放置」 | ⑤ 态切换为「点亮的塔位即可落子（＋ 新建 · ↑ 升级）· Esc 取消」 |

---

## 3. 验收

### 3.1 端到端（`tests/probe_placement.gd`，需窗口，非 CI）

模拟真实鼠标事件跑完整链路，18 项全绿：

```
[place] PASS 进入放置模式
[place] PASS 抽屉收起（GDD §2.1：⑤ 态战场全屏）—— 落子不再依赖抽屉按钮
[place] PASS 每个塔位都有放置模式（6 个）
[place] PASS 存在可新建的塔位（new）
[place] PASS 主塔所在塔位对建筑卡报 invalid（不可覆盖主塔）
[place] PASS 落子后待放置队列清空
[place] PASS 落子后场上 2 座塔（主塔 + 1）
[place] PASS 落子后自动退出 ⑤
[place] PASS 已有 Cannon 的塔位对 Frost 报 invalid
[place] PASS 点非法位**不**退出放置模式
[place] PASS 点非法位**不**消耗卡片
[place] PASS 点空地**不**退出放置模式
[place] PASS 点错之后仍能正常落子（3 座塔）
[place] PASS 已有 Cannon 的塔位对 Cannon 报 upgrade
[place] PASS 升级不新增塔（3 座）
[place] PASS 升级消耗掉那张卡
```

### 3.2 结构断言（`uistyle` §J，11 项，进默认回归）

源码级钉住，防止有人再把入口改回抽屉：

- TimeDirector 声明 `slot_place_requested`
- ShopController 连接 + 非 ⑤ 态丢弃
- MonsterLayer 由**状态机**判定放置态（不是抽屉）
- MonsterLayer 点选发到 `time_director`（不是 `director`）
- MonsterLayer 命中走屏幕距离、无 `_hit_tower_slot` 残留
- MonsterLayer 无 `draw_string` 调用（AC-T1-24）
- ShopOverlay 无 `_place_box` / `_refresh_placement`（死代码清除）
- HUD 有放置专属文案

### 3.3 回归

| 项 | 结果 |
|---|---|
| 默认全量回归 | **12 段 3,574 项 0 失败**（`uistyle` 69 → 80） |
| 切片4 场景冒烟 | 46 / 46 |
| 金标本读数 | 逐位不变（本轮零 gameplay 改动） |

### 3.4 截图

| 文件 | 内容 |
|---|---|
| `shots/place-01-enter.png` | ⑤ 态全景：5 个青色 `＋` 位 + 主塔灰 `✕` 位，底部引导已切文案 |
| `shots/place-03-upgrade.png` | 升级态：已建 Cannon 的塔位变辉金 + `↑` |

---

## 4. 教训

**「写好了」≠「玩家点得到」。** 这次四个 bug 里有三个是「逻辑正确但入口不可达」：

1. 按钮建在会隐藏的容器里
2. 输入回调要求的前置条件与该态的实际情况相反
3. 信号发给了没声明它的对象（GDScript 的 `emit_signal` 是 Object 方法，**发错对象不报错**）

这三类的共同点：**单元测试全绿，实机全废**。

所以本轮的验收顺序是固定的：
**先实机取证（截图 + 逐层日志）确认现象 → 再改代码 → 再用模拟输入跑端到端 → 最后才写结构断言钉死。**
反过来做（先写断言再改）会得到一堆「断言通过但玩家还是放不下」的假绿。

具体到探针，有一个坑值得记：

```
root.push_input(ev)        # ❌ 参数被当窗口坐标，再乘 stretch 缩放（本工程 1.2×）
root.push_input(ev, true)  # ✅ in_local_coords = true，按 canvas 坐标
```

第一版探针传 canvas 坐标 `(909, 642)`，到达 `_unhandled_input` 变成 `(1091, 770)`
——看起来像「点击没反应」，白查了一轮。
