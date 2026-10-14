# T-P6-06 S 档两提交 · 独立复核报告（polish-s-verify）

> 复核人：**严守真（quality-lead）** · 日期：2026-10-13
> 对象：`6d3596a`（S3）+ `5304edd`（S1/S2/S4/S5）—— **未 push**
> 方法：**独立复跑**（不复用工程自验会话）· headless 全量回归 + 窗口真实帧 + 静态通读。
> 只读复核：**未改任何生产代码、未 push**。
> 判定词：**证实 / 证伪 / 存疑（无法确认）** + 独立数字。

---

## §0 结论速览

| 项 | 内容 | 判定 | 关键独立证据 |
|---|---|---|---|
| **S3** | BUG-1 胜利结算积分（`run_won` 延后到入账后） | 🟢 **证实** | 窗口跑 `[run_won] scrap=960`；覆盖层正文「本局积分 **960**」（原 0）；失败路径仍 80 |
| S3-c | 🔴 新增依赖：`wave_end` 链是否与 `_show_result` 时序打架 | 🟢 **证实（无冲突）** | 抽屉确在覆盖层**之前**开，但覆盖层 `layer=150` 盖住并**拦截**抽屉；无重复 pause；无 z 序冲突 |
| **S4** | PATH 遗留怪/塔色修正（2 个 `const Color`） | 🟢 **证实** | 仅 2 处 `const` 变更；golden/slice2 **逐位**不变；全量回归 EXIT=0 |
| **S5** | RADIAL 塔原型内形徽记（三角/方/六边） | 🟢 **证实**（附 1 项 🟡 待 art 裁定） | 干净帧：slot0 三角 / slot1 方 / slot2 六边**可辨**；`_oct8` 剪影未动；零新增字段/信号 |
| **S1** | 最小字号 ≥16px | 🟢 **证实** | 全仓 `font_size` 扫描：仅 F3 调试面板 2 行 <16px（dev-only 隐藏层） |
| **S2** | 商店买得起/买不起非色彩冗余（✓/✗） | 🟢 **证实** | 一帧同现 `✓ 9 分`（辉金）/`✗ 12 分`（灰）；判据/配色一字未改 |
| **提交洁净度** | 2 提交只含 7 脚本 | 🟢 **证实** | `6d3596a`=1 文件；`5304edd`=6 文件；无 `design/`·`.workbuddy/`·测试残留 |
| **回归** | 全量 headless | 🟢 **全绿** | **PASS=1157 / FAIL=0 / EXIT=0** |

**总判定：🟢 2 项提交均证实 · 0 阻项 · 1 项 🟡 待 art-director 裁定（S5 8 重对称解释）· 1 项 OBS（S3 结算时抽屉仍在覆盖层后可见，观感项）。**

---

## §1 S3（最高风险）· `run_won` 时序 + `wave_ended` 链依赖

### 1.1 变更事实（读码确认）
`scripts/gameplay/wave_director.gd::_end_wave()`：
```
var won_now := false
if w >= MAX_WAVE and not run_failed and not victory:
    victory = true; last_result["won"] = true; won_now = true
...
emit_signal("wave_result", w, last_result)
if director != null:
    director.wave_end(w)              # ← 入账链在此
if won_now:
    emit_signal("run_won", w)         # ← 由「之前」挪到「之后」
```
🔴 只改 emit 位置；**未动** `victory`/`last_result` 置位、数值、结算公式。`won_now` 幂等（`victory` 已置位 → 再入 `_end_wave` 也不复发）。✅

### 1.2 为什么这是 BUG-1 的根因（独立复算）
入账链 = `director.wave_end(w)` → `TimeDirector.wave_end`（`emit wave_ended`）→ `ShopController._on_wave_ended`（`:357-367`）→ `runtime.grant_wave_result(res)`（`scrap += scrap_earned×(1+income_mult)`）。
`_show_result`（`:140-151`）在 `:145` 读 `float(runtime.scrap)`。
→ **旧序**（`run_won` 早于 `wave_end`）：`_show_result` 读到**本波入账前**余额 = **0**（T-P6-01 仪器：`[run_won] w=20 runtime.scrap=0`，`VICTORY.png` 显示「本局积分 0」）。
→ **新序**：`run_won` 晚于入账 → 读到 **960**。**根因判定成立。**

### 1.3 独立复跑（窗口真实帧，非复算）
命令：`godot --path D:/roguedemo --script res://tests/_qa_s3_victory.gd`（产品口径全开，贪心建造+修复）
```
[QA-S3][run_won] w=20 runtime.scrap=960 (入账后)      # ← 原 0
[QA-S3] W20 结束: core=850 scrap=960 victory=true failed=false
[QA-S3] overlay.visible=true
[QA-S3] overlay.title = <通 关 胜 利>
[QA-S3] overlay.body  = <守核成功！
                          打完 W1 → W20 全部波次
                          核心 HP 剩余 850 / 1000
                          本局积分 960>                 # ← 原「0」
```
✅ **(a) 覆盖层读到 960（非 0）**，与 `VICTORY.png` 口径一致（修正后）。证据帧 `_s3-victory-after.png`（正文可见「本局积分 960」）。

### 1.4 🔴 (c) 新增依赖检查：`wave_ended` 链 vs `_show_result` 覆盖层
**读码判定**：
- `TimeDirector.wave_end(w)`（`time_director.gd:160-163`）= `sm.wave_end(w)` → `_apply_clock(true)` → `emit wave_ended`。
- `sm.wave_end`（`time_state_machine.gd:246-248`）置 `_shop_open_pref=true` + `state=SAFE_WINDOW` → `clock()` 返回 `paused=true`、`drawer=HEAVY`。
- `_apply_clock` **确会先开抽屉**（发 `drawer_mode_changed(HEAVY)`）→ `ShopOverlay._refresh_mode` 置 `visible=true`。
- `ShopController._on_wave_ended`（`:357-374`）**不**开抽屉、**不**重复 pause、**不**碰 `over`（仅入账 + `_emit_shop/run`）。
- **因此新序下抽屉确在覆盖层之前打开**（旧序是覆盖层先建、抽屉后开）。

**是否冲突？（逐条排除）**
| 风险 | 判定 | 依据 |
|---|---|---|
| 抽屉抢焦点 / 盖住结算 | ❌ 无 | `ResultOverlay` = `CanvasLayer layer=150`（`result_overlay.gd:_init`）；商店抽屉 = 默认层 0 → 覆盖层**恒在其上**；全屏 `_backdrop`（`ColorRect` alpha 0.72，默认 `MOUSE_FILTER_STOP`）拦截输入 → 抽屉按钮**点不到** |
| 重复 pause / unpause | ❌ 无 | `_apply_clock` 仅在值变化时写 `paused`；覆盖层 `process_mode=ALWAYS`，**不写** `paused`；结算期间世界保持 `paused`（设计如此） |
| 覆盖层被抽屉盖 / z 序打架 | ❌ 无 | 见上：layer 150 ≫ 0；窗口帧实证：抽屉在覆盖层**之后被压暗** |
| `_show_result` 与抽屉竞态 | ❌ 无 | 二者同帧**顺序执行**（同一条信号回调链），无异步竞态；`over` 幂等，覆盖层只弹一次 |

**窗口实证**（`_s3-victory-after.png`）：商店抽屉（「重决策模式（安全窗）」）确已展开，但被结算覆盖层的暗背板**压暗并遮住**；玩家只能点「再来一局 / 退出」。**结论：`wave_ended` 链与 `_show_result` 无时序冲突**（🟡 仅观感：结算时抽屉仍在覆盖层后可见，非缺陷）。

### 1.5 (b) 失败路径不变（独立复跑）
命令：`... _qa_s3_victory.gd -- loss`（不建塔）
```
[QA-S3][run_lost] w=4 runtime.scrap=80 (入账前 · 与 HUD 一致)   # ← 与 T-P6-01 同值
[QA-S3] W4 结束: core=0 scrap=80 victory=false failed=true
[QA-S3] overlay.title = <核 心 归 零 · 失 败>
                        本局积分 80>
```
读码：`run_lost` 在 `_substep`（`:409-411`）发，**早于** `_end_wave`/入账 → 覆盖层读**入账前**余额 = 80 = HUD（同屏 HUD 亦显示 80）。✅ **失败路径原子未动**；`run_lost` 与 `run_won` 互斥（`run_failed` 守卫）。证据帧 `_s3-defeat-after.png`。

### 1.6 (d) AC-S8-10 互斥测试
`test_suite_slice8.gd::_test_run_lost/_test_run_won`（`:475-525`）断言 `run_won` 发 1 次 / `run_lost` 发 0 次（胜负互斥）。
复跑结果：**切片8 合计 PASS=92 / FAIL=0** → ✅ **仍通过**。（测试中 `wd` 无 `director` → `wave_end` 被 `if director != null` 跳过 → `won_now` 分支照发 1 次，语义一致。）

> **S3 判定：🟢 证实**（修正有效 + 无时序副作用）。附 **OBS-S3-1**（观感，非缺陷）：结算时抽屉仍在覆盖层后可见。

---

## §2 S4 · PATH 遗留怪/塔色 · 逐位等价

### 2.1 变更事实（读码确认，全仓比对）
仅 `scripts/ui/monster_layer.gd` 两处 `const Color`：
- `C_TANK` `(0.35,0.55,0.95)`(#598CDB 蓝) → `(0.72,0.36,0.16)`(#B85C29 暖铜) — `:63`
- `C_TOWER_CANNON` `(0.95,0.55,0.30)`(#F28C4D 橙) → `(0.24,0.80,0.88)`(#3DCCE0 青) — `:413`
✅ **无其它源码改动**（`git show 5304edd -- scripts/ui/monster_layer.gd` 其余 diff 仅为 S5 的 `_ngon`/`_draw_radial_tower_glyph` 新增 + 1 行调用，见 §3）。

### 2.2 是否进入 headless 逻辑？（读码）
两常量均定义于 **渲染层** `monster_layer.gd`（`Control`/绘制节点），仅被 `draw_*` 调用消费；**不**读入 `snapshot`、**不**参与 DPS/伤害/经济。headless MC 不实例化渲染层。→ 结构上**不可能**扰动。

### 2.3 逐位等价 · 独立复跑（关键，非仅 EXIT=0）
| 门槛 | 独立结果 |
|---|---|
| slice1 金标本（伤害引擎逐位对齐） | `汇总：通过 222 项 / 失败 0 项` · **「全部对齐 —— GDScript 引擎与 Python 金标本逐位一致」** · 逐波原始列最大相对偏差 **1.712e-16 @ tierB W17**（验收线 1e-6） |
| slice2 战斗/商店/主循环逐位 | `汇总：通过 2228 项 / 失败 0 项` · **「全部对齐 … 定稿判据链全部复现」** |
| slice2 **MC 逐位**（`[7]`） | A 起飞率 **69.3%** / 中位 **W8**；B 起飞率 **91.3%**（=**274/300**）/ 中位 **W13** |
| slice2 **MC_TRACE 前 20 局逐局逐位**（`[7b]`） | `A got == A want`（前 20）· `B got == B want`（前 20）· **分歧局数 = 0** |
| 金标本文件本身 | `git diff HEAD -- tests/golden_reference.gd test_suite_slice2.gd run_tests.gd` = **空**（与 HEAD 逐字节相同）→ 比对基准未动 |

> **S4 判定：🟢 证实**——渲染层常量变更，headless 逐位基线（golden / slice2 MC）**零扰动**。

---

## §3 S5 · RADIAL 塔原型内形徽记

### 3.1 变更事实（读码确认）
新增 `_ngon(c, r, n, rot)`（`:776-786`，`_oct8` 的推广）+ `_draw_radial_tower_glyph(c, R, ctype, sc)`（`:1108+`）；在 `_draw_radial_towers` 内、中心圆之后插入 1 行调用（`:1083`）。
- 形：Arrow=三角(3) / Cannon=菱形(4) / Frost=六边形(6)，`R*0.26` 居中 + 极深描边。
- 🔴 **只读 `tw.get("ctype", "Arrow")`**；`ctype` 系 `shop_runtime.snapshot()` 既有字段（`shop_runtime.gd:1210`）→ **零新增 snapshot 字段**。
- **零新增信号**（`_draw_radial_tower_glyph` 为纯绘制函数，无 `emit_signal`）。
- `_oct8` / 八边形剪影 / 外扩描边 / rim 均**未改**（diff 仅新增）。

### 3.2 ① `_oct8` 剪影严格 8 重对称 · 保持不变
读码：`_oct8`（`:772`）未被触碰；新增徽记绘制在**中心圆之后、rim/描边之前**，为**内芯叠加**，不改外轮廓顶点。✅

### 3.3 ② 零新增字段/信号 · 证实
见 3.1（`ctype` 已存在；无新 signal）。snapshot 契约（`control-manifest §5`：UI 只读）未破。✅

### 3.4 ③ 塔位 0/1/2 徽记**屏上可辨** · 独立重截（原 `_s5-proto.png` 被起始横幅遮挡）
复跑 `tests/_qa_s5s2_capture.gd`（建 Arrow@0 / Cannon@1 / Frost@2）→ `_s5-towers-clean.png`。
放大取证（`ci-logs/qa-s-verify/s5-clean-zoom.png`，3× 最近邻）：**slot0 = 三角形（Arrow） · slot1 = 方形/菱形（Cannon） · slot2 = 六边形（Frost）**，均清晰可辨；八边形轮廓（外环）完好。✅

### 3.5 🟡 待 art-director 裁定：内形徽记 vs §3.1「严格 8 重对称」
`art-bible §3.1`：「玩家侧 对称性 = **严格 8 重旋转对称**（八边形）」；§3.5：「塔 = 八边形、硬折角、8 重对称」。
S5 的内芯徽记是 **3/4/6 重**——**塔体整体**（八边形 + 三角/方/六边内芯）已非严格 8 重对称。
- **支持方**：§3.2 剪影测试针对**轮廓/剪影**（八边形未变，仍过「归入我方」测试）；art-bible 行 156 明列「**唯一缺口：RADIAL 塔未按原型分化**」→ S5 正是补此缺口；内芯小（`R*0.26`）不破剪影。
- **风险**：§3.1 措辞未限定「仅轮廓」；若 art 解释为「整塔严格 8 重」则属**轻微偏离**。
> 建议：**交 art-director（林绘澄）一句话裁定**是否将 §3.1 的 8 重对称限定为「**外轮廓/剪影**」（并登记内芯原型徽记为允许的第二编码）。**非代码缺陷**。

> **S5 判定：🟢 证实**（剪影未破 / 只读既有字段 / 徽记可辨）。附 1 项 🟡 待 art 裁定（8 重对称的解释边界）。

---

## §4 S1 · 最小字号 ≥16px（全仓覆盖）

### 4.1 独立扫描（`scripts/` 全量）
`add_theme_font_size_override("font_size", N)` 全出现：
- **≥16px**：18/52/44/16/96/26/18/18/18/16×N —— 全部玩家可见正文与标题。
- **<16px（仅 2 处）**：`hud.gd:249`（"F3 调试读数…默认隐藏" 标题，13px）+ `hud.gd:266`（`_mk_dbg` 读数，13px）—— **两处均在 `_debug_panel` 内**（`hud.gd:260` `visible=_debug_visible`，默认 `false`）。
- 无「非字面量」字号覆盖；无 `add_theme_default_font_size`。→ Godot 默认 Label(16) 未降。

### 4.2 F3 面板豁免是否成立？
- 依据 `docs/phase3/ux-p0p1-spec.md` **§B.4**「调试信息去留」：F3 层为 **dev-only、默认关闭**的验证读数层（`hud.gd:9/45` 显式引用 §B.4）。
- 判读：§9.1「最小字号」红线针对**玩家可见正文**；F3 层非玩家常态可见 → **豁免合理**。
- 🟡 **小注**：art-bible §9.1 **未显式**豁免调试层；「§B.4 允许豁免」系**解释性引用**（指向另一文档）。建议 art-director 在 §9.1 补一句「dev-only 调试层豁免」以免歧义。**非缺陷**。

> **S1 判定：🟢 证实**——玩家可见正文全部 ≥16px；仅 dev-only F3 层 2 行 <16px，豁免成立。

---

## §5 S2 · 商店买得起/买不起 · 非色彩冗余

### 5.1 变更事实（读码确认）
`shop_overlay.gd::_refresh_shop`（`:347-356`）：价格文本由 `"%.0f 分"` → `"%s %.0f 分" % [("✓" if _aff else "✗"), price]`。
- `_aff := bool(s["affordable"][i])` —— **判据不变**（同 key）。
- 配色 `C_ACCENT if _aff else C_DIM` —— **配色一字未改**。
- 纯加法（前缀字形），未改卡片可见性（X6）、未改布局尺寸。

### 5.2 窗上实证（`_s2-affordable-mix.png`）
一帧内同现两态：
- 商品位2：**`✓ 9 分`**（辉金/琥珀 = 买得起）
- 商品位1/3：**`✗ 12 分`**（灰 = 买不起）
✓/✗ 为**字形差**，灰度/色盲下亦可辨。✅

> **S2 判定：🟢 证实**——满足 `art-bible §9.2 红线①`「任何游戏状态不得仅靠颜色传达」。

---

## §6 提交洁净度

`git show --name-only`：
- **`6d3596a`** = `scripts/gameplay/wave_director.gd`（1 文件，+11/−1）
- **`5304edd`** = `scripts/ui/{disabled_tower_dialog,hud,monster_layer,result_overlay,salvage_confirm_dialog,shop_overlay}.gd`（6 文件，+70/−18）
- **合计 7 脚本**，与声称一致。✅
- **无** `design/`、`.workbuddy/`、`ci-logs/`、测试残留、`.import`、`.uid` 混入。✅
- 工作树对上述 7 脚本 + `tests/golden_reference.gd` 相对 HEAD **无差异**（`git diff HEAD` 空）→ 提交后**未再改动**。✅

---

## §7 回归证据（独立复跑，headless）

- 命令：`godot --path D:/roguedemo --headless --script res://tests/run_tests.gd`
- 结果：**EXIT=0 · PASS=1157 / FAIL=0**
| 套件 | 结果 |
|---|---|
| slice1（伤害引擎金标本） | 222 / 0 · 全部对齐 |
| slice2（战斗/商店/AI + MC 300） | 2228 / 0 · 全部对齐 |
| slice3（五态时钟） | 142 / 0 |
| slice4（商店接线） | 123 / 0 |
| slice5（真实刷怪战斗） | 302 / 0 |
| slice6（暴露度地基） | 41 / 0 |
| slice7（三原型+Elite 闸门） | 31 / 0 |
| slice8（拆除回收/胜负结算） | 92 / 0 |
| t1aggro（仇恨） | 234 / 0 |

> 退出时 `RID/TextServer` 泄漏告警为 headless 字体渲染**既有噪声**（非断言失败）。

---

## §8 证据帧 / 日志清单（本次新产，均在 `docs/phase6/shots/` 与 `ci-logs/qa-s-verify/`）

| 文件 | 用途 |
|---|---|
| `docs/phase6/shots/_s3-victory-after.png` | **S3 胜利覆盖层「本局积分 960」**；抽屉在覆盖层后 |
| `docs/phase6/shots/_s3-defeat-after.png` | **S3 失败覆盖层「本局积分 80」**（与 HUD 一致） |
| `docs/phase6/shots/_s5-towers-clean.png` | S5 三塔原型干净帧（三角/方/六边） |
| `docs/phase6/shots/_s2-affordable-mix.png` | S2 一帧同现 `✓`（辉金）/`✗`（灰） |
| `ci-logs/qa-s-verify/s5-clean-zoom.png` | S5 徽记 3× 放大取证 |
| `ci-logs/qa-s-verify/VICTORY-before-S3.png` | 修正前 `VICTORY.png` 备份（对照） |
| `ci-logs/qa-s-verify/{run_tests-full,s5s2-capture,s3-victory,s3-loss}.log` | 原始日志 |
| `tests/_qa_s5s2_capture.gd` · `tests/_qa_s3_victory.gd` | 临时 QA 驱动（untracked，零生产改动） |

---

## §9 待裁定 / 建议（建议性质量门 · 最终放行由用户）

1. 🟡 **S5 · 需 art-director 一句裁定**：`art-bible §3.1`「严格 8 重对称」是否**限定为外轮廓/剪影**？若是 → 内芯三/四/六边徽记合规，建议在 §3.1/§3.4 登记为允许的第二编码；若否 → 需回退或改法（**当前判为可接受**）。
2. 🟡 **S1 · 建议 art-director 补登豁免**：§9.1 增注「dev-only 调试层（F3）豁免最小字号」，消除「§B.4 引用」歧义。
3. ⚪ **OBS-S3-1（观感）**：终局结算时商店抽屉仍在覆盖层后可见（被压暗）——无功能影响；如追求干净，可在终局时收起抽屉（可选）。
4. ⚪ **OBS（非本次变更）**：HUD 左上积分是**补间动画值**（结算同帧显示 944，收敛后 960），与商店面板/覆盖层「即时值」瞬时不一致——非缺陷（数字缓动），但与 T-P6-01「HUD 605 vs 960」现象同源，供后续文案/口径参考。

> **本报告为建议性质量门**：S3/S1/S2/S4/S5 与提交洁净度**全部证实**、回归**全绿**、**无阻项**；仅 1 项 🟡（S5 解释边界）待 art 裁定。**可放行**。

---

## §10 复现

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
# 全量回归（含 golden + slice2 MC 逐位）
"$GODOT" --path D:/roguedemo --headless --script res://tests/run_tests.gd
# S3 胜利 / 失败（窗口真实帧）
"$GODOT" --path D:/roguedemo --script res://tests/_qa_s3_victory.gd
"$GODOT" --path D:/roguedemo --script res://tests/_qa_s3_victory.gd -- loss
# S5/S2 干净帧
"$GODOT" --path D:/roguedemo --script res://tests/_qa_s5s2_capture.gd
```

*报告结束 · 严守真（quality-lead）· T-P6-06 S 档独立复核 · 🟢 证实*
