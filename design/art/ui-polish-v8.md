# 守核 · UI 收口 v8（2026-11-09 13:xx）

> 本轮不是「再加一批新素材」，是把已有界面的**排版与形态缺陷**逐条钉死，并留下两个
> 可复跑的判据脚本。所有结论都有实测数字，不靠看截图猜。
> 前序：`asset-pack-v6-ui-plate.md`（承托件 + 卡包页瓦片）、`asset-pack-v7-store.md`（发行素材）。
> 🆕 **后续（2026-11-09 14:05 · v1.9 批次⑫）**：为放下第 81 张卡并消除长卡名截断，`CARD_SIZE`
> 已由本文的 **278** 再改为 **320**（5×320+4×12=1648 ≤ 1764）；`probe_card_name_fit.gd` 实测
> 81 张 0 截断。本文其余结论（clip_text + clip_contents 锁宽的必要性）仍然成立。

---

## 0. 一句话

图鉴卡宽从 **278~326 六种混排** 锁死到 **278 一种**；ghost 三级入口从「一行灰字」变成
**有可见底线的控件**；结算横幅从**压过标题的浅金碎块**退回**标题区底纹**。
9 个页面全部通过「内容被压」体检，字号全部 ≥16。

---

## 1. 缺陷 → 真因 → 修法

### 1.1 🔴 图鉴卡宽不齐（8 包中 6 包，真 bug）

**实测（修前）** `tools/probe_ui_rects.gd`：

| 包 | 卡宽集合 | 网格右边界 |
|---|---|---|
| core / cinder / sunder | `{278}` | 1536 ✅ |
| rime | `{278, 284, 288, 306}` | 1586 🔴 |
| pierce | `{278, 288, 318}` | 1586 🔴 |
| arc | `{278, 282, 308, 326}` | 1618 🔴 |
| hex | `{278, 312}` | 1570 🔴 |
| true | `{278, 282, 304, 308}` | 1596 🔴 |

公共右边界是 **1536**（5 列 × 278 + 4 × 12 + 容器边距）。超出的 50~82px 就是
「Thunderhead 这类长卡名压到隔壁格子」的来源。

**真因**：`pc.custom_minimum_size = CARD_SIZE(278×126)` 只是**最小值**。
描述 `desc` 是 `AUTOWRAP_OFF` 且含 `\n`（恒 3 行），Label 的**最小宽 = 最长那一行的宽**，
再加上卡名行（18px 粗体 + 3 个 ▲ 稀有度角标 + tag 字形），整卡最小宽被顶到 326。
GridContainer 按列取 max ⇒ 该列全部变宽，一路顶出公共边界。

**修法**（`main_menu_overlay.gd::_make_card`）：
- `name_l.clip_text = true` + `OVERRUN_TRIM_ELLIPSIS`
- `desc.clip_text = true` + `OVERRUN_TRIM_ELLIPSIS`
- `pc.clip_contents = true`（兜底，内容再长也不会画到卡片外）

**🔴 踩坑（必须记住）**：`clip_text = true` 会把 Label 的最小宽归 0。
如果旁边还留着一个 `SIZE_EXPAND_FILL` 的空白占位 `Control`，HBox 会把**全部剩余宽度
分给那个空白**，名字拿到 0px 被裁得干干净净 —— 第一版改完 32 张卡名整行消失。
所以名字必须**自己** `size_flags_horizontal = SIZE_EXPAND_FILL`，并把原来的 `sp` 占位删掉。

**验证（修后）**：8 包全部 `✅ 等宽 {278}`，右边界统一 1536。

### 1.2 ghost 变体在暗背景上不可见

**现象**：主菜单「退出游戏」、图鉴「返 回」、商店「锁定」三处 ghost 按钮，四态
（normal / hover / pressed / disabled）都是**全透明无描边**，只剩 `C_TEXT_DIM` 的一行字。
按钮 `custom_minimum_size` 是 320×52，但玩家看到的是文字 ⇒ 视觉重心落在文字上，
「52 高 + 6px 间距」算出来的间距看起来忽大忽小，三个入口像三段散落的字。

**修法**（`ui_style.gd`）：新增 `_ghost_box(line)` = **全透明底 + 仅底部 2px 线**。
- 保留三级入口语义：不填底、不描边、hover 不抬底，只把线点亮成耀青
- ghost 分支在九宫格替换**之前**改四态

**🔴 踩坑**：线必须 **2px**。逻辑视口 1920×1080 在 1600×900 窗口里是 ×0.833，
1px 逻辑线落到屏幕上只有 0.83px，被抗锯齿混进背景后**完全看不见**
（和 v6 承托板顶部亮线是同一个坑，第一次改 1px 时截图里找不到线）。

**配套**：
- 主菜单三入口独立成 `VBox(separation 10)`（原来共用 `col` 的 6，有了可见边界后会挤成一整块）
- 图鉴「返 回」180 → **76** 宽：下划线 ≈ 词宽，右端与下方「滚轮浏览 · Esc 返回主界面」同一边界

### 1.3 结算横幅变形 + 抢焦点

**现象**：标题上方一条「碎梯形」金块，亮度压过「通关胜利」。

**两层真因**：
1. `STRETCH_SCALE` 把 960×96 的横幅硬拉到 **面板宽 × 64**。面板 520 宽 ⇒ 横向 0.54、
   纵向 0.67，**非等比**，斜切边被拉变形。
2. 素材本身是「淡金色斜切条 + 中间一块更亮」的设计，不透明贴上去就是面板顶部贴了张浅色纸。

**修法**（`result_overlay.gd`）：
- 面板 520 → **640**：640 / 960 = 0.6667，96 × 0.6667 = **64**，宽高都整除，横幅天然等比
- `stretch_mode` → `STRETCH_KEEP_ASPECT_CENTERED`（比例再变也不变形）
- `_banner.modulate.a = 0.26`：退回标题区底纹，金 / 红两态色相仍可分辨

### 1.4 图鉴副标题文案

| | 文案 |
|---|---|
| 旧 | 共 81 张卡 · 8 个卡包 · 基础每包 10 张（实际 81 个卡位）· 未解锁包压暗显示 |
| 新 | 81 张卡 · 8 个卡包 · 每包 10 张起 · 未解锁包压暗显示 |

旧文案把 81 说了两遍，且「基础每包 10 张」是开发者口径（熔炉包实际 11 张）。

### 1.5 主菜单入口间距

`col` 的 6px 对三个 52 高的入口太紧（ghost 有了可见边界后尤其明显）→ 独立 VBox，separation **10**。

---

## 2. 新增工具（4 个，都可复跑）

| 脚本 | 作用 | 输出 |
|---|---|---|
| `tools/probe_ui_rects.gd` | 主菜单按钮矩形 / 图鉴逐卡矩形 / 字号清单 / 内容被压 | stdout |
| `tools/probe_ui_squeeze_all.gd` | **9 页全量「内容被压」判据体检** | stdout |
| `tools/shoot_ui_all.gd` | 9 页各拍一张 1600×900 | `art/_review/ui_all/` |
| `tools/ui_contact_sheet.py` | 3×3 总览拼图 | `art/_review/ui_contact_sheet.png` |

### 「内容被压」判据是什么

> 容器分配给子项的尺寸 **小于** 子项自身 `get_combined_minimum_size()`
> ⇒ 该子项的文本一定被裁或溢出到邻居。

这是 1.1 那类缺陷的**共同真因**，比肉眼看截图可靠得多（截图缩放后 4px 的差别根本看不出来，
但探针能精确报到 0.1px）。`ScrollContainer` 的内容天然超宽，遍历时跳过。

---

## 3. 体检结果

```
[✅] 主菜单
[✅] 图鉴
[✅] 卡包选择
[✅] 战斗商店
[✅] 选关航图
[✅] 结算·胜
[✅] 结算·负
[✅] 禁用塔弹窗
[✅] 拆除回收弹窗
================ 合计 0 / 9 页有问题 ================
```

字号阶梯（图鉴页实机统计）：`16px × 253`、`18px × 81`、`24px × 8`、`34px × 1` —— **无低于 16 的漏网**。
（`hud.gd` 里那两处 13px 是 F3 调试面板，默认隐藏，不计入。）

回归：`[PASS] 54 [FAIL] 0`，关卡波表 `PASS=101 FAIL=0`，十关合计 149 波。

---

## 4. 复跑

```bash
cd "G:/AI Demo/corebound"
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

"$GODOT" --path . --script res://tools/probe_ui_squeeze_all.gd   # 判据
"$GODOT" --path . --script res://tools/shoot_ui_all.gd            # 截图（需窗口模式）
py -3.9 tools/ui_contact_sheet.py                                  # 拼总览
```

---

## 5. 本轮没动的（附理由）

| 项 | 理由 |
|---|---|
| 图鉴第 81 卡位 `Pyroclasm` 无卡面 | 需 1 张出图额度，UI 层补占位只会掩盖问题 |
| 选关页节点名对比度偏低 | 属设计取舍（不抢航图），非排版缺陷；要改需重做航图信息层级 |
| 商店「待放置队列」空时下方留白 | 由 `spacer` 撑开抽屉底部，把重决策组推到上方，是版式意图 |
| 卡框 5 张仍不接入 | 理由见 `asset-pack-v6-ui-plate.md` §4（比例差 1.8× + 自带稀有度角标） |
| 教学遮罩不贴图化 | 红线①：半透明透出下层走 StyleBoxFlat |
| 拆除回收弹窗 380 宽偏窄 | 正文 36 字两行，断点在「塔/位」之间但不影响理解；加宽会让它变成空心的宽条 |

---

## 6. 改到的文件

```
scripts/ui/ui_style.gd             + _ghost_box()，ghost 四态改写
scripts/ui/main_menu_overlay.gd    卡宽锁定（clip + clip_contents）、入口 VBox、
                                   返回按钮 180→76、副标题文案
scripts/ui/result_overlay.gd       面板 520→640、横幅 KEEP_ASPECT + alpha 0.26
tools/probe_ui_rects.gd            新增
tools/probe_ui_squeeze_all.gd      新增
tools/shoot_ui_all.gd              新增
tools/ui_contact_sheet.py          新增
```
