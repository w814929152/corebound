# 卡牌重制 v3 · 2026-11-11

> 按用户提供的「箭塔」整卡参考图重做游戏内商店卡牌。美术规格与验收口径在
> `design/art/card-redesign-2026-11-11.md`；本文只记起点、落地口径、验证与边界。

## 1. 起点（已同步的项目最新状态）

- HEAD **`1785b69`**（`feat(ui): add arrow card illustration and polish shop card layout`）。
- 今日已有两份交接：`handoff-2026-11-11-arrow-card.md`（箭塔全幅插画 `card_arrow_illustration_v2.png` 试装）、
  `handoff-2026-11-11-card-polish.md`（商店双层细线框 / 角刻线 / 文字整理 / 提交前全量回归）。
- `monster-library.md`（09:18）与 `art/2d/monsters/`、`art/2d/sprites_ai_v3/` 等属**另一会话未提交改动**，本批未纳入、未暂存。
- 参考图实测 1003×1568（比例 0.640），与游戏卡 210×340（0.618）一致 → **不改卡尺寸**。

## 2. 本轮落地

### 2.1 美术定调（先评审再产出）

当前商店卡六维评审结论 **重做**（剪影 2 / 明度 2 / 构图 2 / 一致性 2 / 技术 4 / 可用性 3）：
深底 + 白字压插画 + 直角细线框，靠调色无法变成参考图的「斜切八角金属框 + 深色插画区 + 米白信息区」三段结构。
据此冻结【风格锚点 v3】，色板逐像素取自参考图：`#FAEEE1` 米白 / `#1E222B` 深蓝黑 / `#23262F` 框体 /
`#00F2E4` 能量青 / `#4C5059` 钢灰 / `#10131A` 文字黑。文档含明度阶梯、6 条禁忌、几何规格表、
切图与导入设置、四段提示词包与变量槽位表（供后续八包插画批量生成复用）。

### 2.2 资源（程序化精确绘制，**非 AI 生成**）

| 文件 | 画布 | 用途 |
|---|---|---|
| `art/2d/ui/ui_card_plate_v3.png` | 420×680 RGBA | 斜切八角外框、双层描边、插画区挖空、米白信息区、中缝六边形、底部箭头、顶部功能带 |
| `art/2d/ui/ui_card_edge_v3.png` | 420×680 RGBA | 纯白单通道描边层 → 代码 `modulate` 成稀有度色 / 悬停青 |
| `art/2d/ui/ui_card_cost_v3.png` | 110×52 RGBA | 费用六边形胶囊（含废料图标，不含数字） |
| `art/2d/ui/ui_card_badge_v3.png` | 284×36 RGBA | 类型徽章（含延长线与青菱形，不含文字） |

产线 `tools/gen_card_frame_v3.py`（Pillow，8x 超采样 → 2x 输出，可复现）。四张按固定尺寸整张贴用，
**不进九宫格**；文字一律字体渲染。合计显存 2.35 MB（RGBA8、无 mipmap），PNG 落盘 28 KiB。
评审图：`art/_review/card-redesign-baseline-v3.png`、`card-redesign-thumbs-v3.png`（10% / 25% 缩略图测试）。

### 2.3 接线（`scripts/ui/shop_overlay.gd`）

- `_make_slot()` 重构为 **10 层固定层级**：透明卡底 → 插画背景（只占 8,8,194,224）→ 塔插图 →
  卡框底板 → 可染色边线 → 费用胶囊 / 徽章 → 信息区文字 → 顶部辅助 → 锁头 → 旧 chrome（停用绘制）。
- 新增 `_flat_card()`：把 `_Battle.card()` 的 12px content margin 清零，否则绝对定位子节点会被容器整体推移。
- 新增 `_fixed()` / `_picture()` / `_fixed_label()` 三个定位辅助；贴图走 `ResourceLoader.exists()` 判空降级。
- 卡名 28px 近黑 / 类型 16px 米白 / 描述 16px 近黑（取 `describe()` **首行**，完整 3 行机制仍在悬停 `details()`）。
- 价格移到右上费用胶囊（26px 等宽），✓/✗ 形状冗余保留；`◈协同` 高亮事实改挂到 note（悬停可读）。
- 稀有度 = 边线 `modulate` + ▲ 数（1–5）双通道；悬停 = 青色边线。
- 类型徽章文案用游戏现有数据源组合为「建筑 · `<tag_cn>`」，**未改 `card_text.gd`**。
- 保持 `SLOT_SIZE = 210×340`、三卡同构、整卡点击购买、锁头独立热区、金标本与全部数值不变。

### 2.4 实机评审后的修正

首版截图发现：箭塔插画顶部是米白箭头轨迹，编号「01」同为米白 → 完全不可读。
**改法**：`plate` 增绘 (8,8,194,28) 半透明深蓝黑功能带（α0.84 + 下沿青线），编号 / ▲ / 锁头 / ✓ / 费用统一压深底；
`illustration_shade` 顶部暗化 0.55 → 0.20 避免叠加过黑。重生成 → 重导入 → 重截图后全部辅助信息清晰可读。

## 3. 测试断言变更（如实记录，**未降数值阈值**）

| 文件 | 变更 | 理由 |
|---|---|---|
| `tests/run_shop_overlay_asserts.gd` | 「价格在标题下方」改为「价格不与标题相交 + 完全在卡框内 + 位于卡片右半区」；新增「每位都有描边层」 | 参考图把价格放右上费用胶囊；新判据更严（多两条约束） |
| `tests/run_ui_style_asserts.gd` | 「描述块预留 ≥ 3 行 × 25px」改为「≥ 单行字号 16px」 | v3 卡面描述按参考图只显示首行；三卡等高同构断言保留 |
| `tools/shoot_native_cards.gd` | 截图输出改 `native-cards-shop-v3.png` | 不覆盖历史验收图 |

`run_ui_style_asserts.gd` 其余 diff 属另一会话的怪物图鉴断言，本批未动。
`DESC_LINES` / `DESC_LINE_H` 常量保留（兼容），不再驱动布局。

## 4. 验证

- Godot `--headless --path . --import`：4 张 v3 贴图导入成功，退出码 0。
- `run_shop_overlay_asserts`：**PASS**（3 种窗口 × PATH/RADIAL、贴图归属、点击穿透、位置断言）。
- `run_shop_interaction_asserts`：**PASS**（替换 / Tab 聚焦 / 真实拖放 / 视图同步 / 非法落点 / 购买失败）。
- `run_ui_style_asserts`：**146 项通过 / 0 失败**。
- `run_card_description_asserts`：**232 checks / 0 failures**。
- 窗口实机截图 `output/imagegen/native-cards-shop-v3.png` + 放大裁剪 `...-crop.png`：框 / 插画 / 信息区 / 费用胶囊 / 徽章五要素齐全，三卡同尺寸同结构。
- 默认全量回归 `tests/run_tests.gd`：**exit 0**（6m50s，日志 `output/card-v3-full.log`），
  `world 结论：PASS（20.4 s）`；金标本 2228 / slice4 121 / slice8 92 / T1 234 / UI 142 等各切片汇总**失败 0 项**。
  测试进程 `APPDATA` 指向 `output/card-v3-appdata`，避开默认 `user://` 存档目录沙箱不可写的 6 项历史失败（未改存档代码或阈值）。
- 退出仍有既有 ObjectDB / RID / resource 清理警告，非本轮引入。

## 5. 边界

- 未改金标本模拟器、平衡数值、`card_text.gd` 文案源、八包归属表与 `ui_style.gd` 调色板。
- 未重绘 82 张塔插图；Arrow 沿用 `card_arrow_illustration_v2.png`（即参考图的插画部分）。
- **图鉴卡（320×126）与背包卡（120×132）尺寸不同族，本批只统一色板口径、未改结构**，列入第二批。
- 未整库暂存、未提交、未推送、未导出 Windows 包；`attrition8` 历史已知红未处理。
- 工作区 `output/` 下保留了替换前的脚本备份与补丁脚本，便于回溯。

## 6. 待确认（≤ 5 条假设）

1. 保持 210×340，不因参考图 0.640 比例改布局（可保住三卡同构与全部布局断言）。
2. 只重做商店三卡；图鉴 / 背包 / 悬停详情卡沿用现有结构。
3. 价格移到右上费用胶囊，底部不重复价格行；✓/✗ 与 ▲ 冗余保留。
4. 卡面描述只显示 `describe()` 首行，完整机制由悬停详情承载。
5. 稀有度沿用 `ui_style.RARITY` 五级色，未另定色阶。
