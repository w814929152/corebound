# 资产包 v6 · 界面承托件与遗留件定性（asset-pack-v6-ui-plate）

> 状态：🟢 已落地 · 2026-11-09 11:53 起 · 生成器 `tools/gen_ui_plate_pack_v1.py`
> 触发：用户「填补界面 UI 继续」→「按推荐」，接 `asset-inventory-2026-11-09.md` §11 的推荐顺序。
> 前置：资产包 v1（界面件）/ v2（HUD）/ v3（航图）/ v4（地形、结算）/ v5（图鉴分组底板）。
> 现行卡面口径 `card-art-generation-standard-v1.md` v1.8 **不受本包影响**（本包只管界面承托）。

---

## 1. 先做对账：哪些界面是真空白

盘点结论（11:45 快照复核）与「看起来像空白」的直觉不同，先划清边界，避免板中板 / 反复贴图化：

| 界面 | 现状 | 判定 |
|---|---|---|
| 主菜单 / 图鉴 | `keyart_menu_bg` + v5 分组底板与包色标题条 | ✅ 已贴图 |
| 选关航图 | `keyart_stage_bg` + 节点四件 + 章节徽记 | ✅ 已贴图 |
| HUD / 核心血条 / 波次条 | v2 十件 | ✅ 已贴图 |
| 结算页 | 胜负情绪背景 + 横幅 | ✅ 已贴图 |
| 卡包选择页**主面板** | `_Style.panel(C_ALLY)` → `ui_panel_9slice_v1` | ✅ 已贴图 |
| 卡包选择页**瓦片** | `_Style.button("normal")` → `ui_btn_normal_v1` | ✅ 已贴图（但**缺包色识别**） |
| 两个确认弹窗 | `_Style.panel(C_ALERT)` → `ui_panel_alert_9slice_v1` | ✅ 已贴图 |
| **商店商品位** | `card_blueprint()` 纯 `StyleBoxFlat` + 四角 L 刻线 | 🔴 **真空白**：v2-hud §7 #2 遗留 |
| **卡包选择页卡列表** | 瓦片内 `GridContainer` 裸卡名，无包色编码 | 🟡 识别空白（不加高） |
| 教学遮罩 | `StyleBoxFlat` 半透明底 | ⚪ **按纪律保留**：`ui_style` 红线①「透出下层语义走 StyleBoxFlat」，贴图表达不了 |

**本包只动两处真空白，不碰已贴图界面。**

---

## 2. 产物（1 件新图 + 1 件复用）

| 文件 | 规格 | 用途 |
|---|---|---|
| `ui_shop_slot_plate_v1.png` | 48×48, 9-slice corner 12 | 商店商品位中性承托板（**新增**） |
| `ui_lib_head_bar_v1.png` | 640×40, 白烘焙 | 卡包页瓦片包色顶条（**复用 v5**，运行时 `modulate = pack_color(pid)`） |

### 承托板设计约束

- **不染色**：稀有度边框 / 可购性 accent 由 `card_blueprint()` + `_draw_slot_chrome()` 承担，承托板带色会和 5 级稀有度串色。
- **不做四角刻线**：chrome 已画四角 L，重复会叠成脏角。
- **只在 corner 之间画水平亮线**：9-slice 的 top-middle 水平拉伸后仍是线；任何「铺满中心」的横向纹理会被垂直拉伸成粗条，一律禁止。
- 色值：底 `#242B3E`（比 `card_blueprint` 的 `#1E2332` 亮一档）、描边 `#4C5A76`、顶亮线 `#9FB0CC`、底暗线 `#0B0F1A`、左右内阴影 `#1A2030`。逐字取 art-bible §2.2 / 对齐 v1~v5 承托件色阶。
- 🔴 首版顶亮线用 `#6B7A94/150` + 1px，**4× LANCZOS 降采样后混进底色完全不可见**；改为 2px + `#9FB0CC/205` 后才读出层次（模拟图 `art/_review/plate_9slice_sim_v1.png`）。

---

## 3. 接入设计（判空降级，逐字回落）

### 3.1 商店商品位 —— `scripts/ui/shop_overlay.gd::_make_slot()`

`PanelContainer` 会把**每个子节点铺满 content rect**（现有 `chrome` 就是靠「最后加入 → 画在最上」生效的）。利用这一点，把 `NinePatchRect` 承托层插在 `VBoxContainer` **之前**：

```
PanelContainer  (card_blueprint: 稀有度边框 + padding，保持不变)
├─ NinePatchRect  ← 新增，9-slice 承托，画在内容之下
├─ VBoxContainer  ← 原有全部内容，逐字不动
└─ Control chrome  ← 原有四角刻线，仍是最上层
```

- `patch_margin_* = 12`，`mouse_filter = IGNORE`。
- `ui_style.gd` 新增 `slot_plate_tex()`，与 `lib_tex()` / `icon()` 同一套 `ResourceLoader.exists` + 静态缓存管法。
- **缺贴图则不创建该子节点**，版式与改前逐位一致（headless / 资产未导入安全）。
- 🔴 `_refresh_shop()` 对 `_slots[i]` 的 `card_blueprint("dim" / "normal", rar)` 覆盖全部保留，本包不改任何状态逻辑。

### 3.2 卡包选择页瓦片 —— `scripts/ui/pack_select_overlay.gd::_make_tile()`

复用 v5 白烘焙标题条，绝对定位成 8px 高的包色顶条：

- `modulate = _Style.pack_color(pid)` → 与卡面主色调、图鉴分组标题条**共用同一包色编码**（§2.1 SSOT）。
- `PRESET_TOP_WIDE` + `offset_top/bottom`，**不占布局高度**。瓦片 336px 预算紧（内容最小 266px，历史上有 539px 溢出教训），任何增高都会压住底栏。
- `mouse_filter = IGNORE`；贴图缺失 → 整条不建，回落纯文本瓦片。
- 不加第二层底板：瓦片已有 `ui_btn_normal_v1` 9-slice，板中板会破坏层次。

### 3.3 明确不改

- 两个确认弹窗、卡包页主面板、教学遮罩（§1 已贴图 / 半透明纪律），一律不动。
- `card_blueprint()` 的稀有度五级色阶与双通道冗余（P1-6）不动。

---

## 4. 闲置件定性（接 `asset-inventory-2026-11-09.md` §11 #6）

11:45 梳理出的 8 件「未被字面引用」贴图，逐件判定，**不再当作待接入缺口**：

| 件 | 判定 | 理由 |
|---|---|---|
| `ui_card_frame_common/uncommon/rare/epic/legendary_v1.png` (5) | ⚪ **留档，不接入** | 512×716 整卡蓝图网格 + 自带稀有度角标；现有卡位是商店 168×424 竖条、图鉴 278×126 横条（v1.9 起 320×126），比例差约 1.8×，拉伸必变形；且自带角标会与 `card_blueprint()` 的稀有度边框 / `▲` pips 形成第三重语义。**仅用于 `card_mock_card.py` 生成样张**，定位是评审工具素材，不是运行时资产。 |
| `ui_btn_ghost_v1.png` (1) | ⚪ **生成器冗余** | `_btn_tex("ghost")` 第一行就 `return null`，明确走 `StyleBoxFlat` 全透明路径；贴图永不会被加载。保留供未来换口径，不删。 |
| `keyart_hero_v1.png` (1) | ⚪ **源图留档** | 派生链上游（`keyart_menu_bg` / `keyart_menu_hero` / `keyart_stage_bg` 都从它派生），不是 UI 层贴图。4K 升频时作为底稿。 |
| `keyart_menu_hero_v1.png` (1) | ⚪ **备用派生** | 用户 11-08 拍板主菜单换回 `menu` 档后留作备用；`main_menu_overlay.gd` 注释已标明。选关仍用 `keyart_stage_bg_v1`。 |

→ 清单里的 43 件 UI 贴图从此分为：**接线 35 件（字面 25 + 拼接 10）/ 留档 8 件**，不再有「状态不明」项。

---

## 5. 验证

| 项 | 结果 |
|---|---|
| 生成器复现 | `py -3.9 tools/gen_ui_plate_pack_v1.py`，1 件 48×48，manifest 自动登记 |
| 9-slice 模拟 | `art/_review/plate_9slice_sim_v1.png`：168×424 拉伸下边框均匀、顶亮线清晰、圆角完好、无中心拉伸失真 |
| 资产清单 | `tools/sync_art_manifest.py` 把 163 → 301 项（138 个卡面文件补登），再 +1 件承托板 = **302**，孤儿 0 / size 不符 0 |
| 引擎导入 | 见 §6 执行结果 |
| 全量回归 | 见 §6 执行结果 |
| 实机截图 | 见 §6 执行结果 |

---

## 6. 执行记录（2026-11-09 12:14 完成）

| 环节 | 结果 |
|---|---|
| GDScript 语法 | `ui_style.gd` / `shop_overlay.gd` / `pack_select_overlay.gd` 三个 `--check-only --script` 全部无报错 |
| 资产导入 | Godot 4.7.2.stable.steam `--headless --path . --import` → 新图生成 `uid://b40c64vo2m3vg` 的 `.import`，exit 0 |
| 全量回归 | `res://tests/run_tests.gd` exit 0，`[PASS] 54 [FAIL] 0`；关卡波表 101/0、关卡推进 146/0、切片8 92/0、塔等级牌 26/0，与改动前逐项一致 |
| 实机截图 | `tools/shoot_ui_plate_smoke.gd`（窗口模式 1600×900）→ `smoke_v6_pack_select.png` / `smoke_v6_shop_slots.png` |
| 接线硬证据 | 包色顶条 `TextureRect` **8/8**、承托板 `NinePatchRect` **3/3**，均由截图脚本遍历场景树计数 |
| 观感复核 | 商店三位承托板逐位同构、暗底细亮边框 + 顶部亮线清晰；稀有度青 / 红边框仍可读，承托板不抢戏；`FireUp`（无卡面）整条插画带隐藏但承托仍在，降级正确。卡包页 8 条顶条呈灰 / 橙 / 青 / 金 / 紫 / 品红 / 深青 / 红，与卡面、图鉴同色编码 |

**两条验收备注（均非本包回归）**

1. 截图进程有一条 `hud.gd::_layout` 的「non-equal opposite anchors」WARNING，backtrace 指向商店场景既有的 `_ready → _layout`，与本包改动无关。
2. ~~`smoke_v6_pack_select.png` 显示 8 包 ×10 卡时代的既有布局缺陷~~ → **已于 12:19 修复，见 §7。**

**改动文件清单**

- 新增：`tools/gen_ui_plate_pack_v1.py`、`tools/sync_art_manifest.py`、`tools/shoot_ui_plate_smoke.gd`、`tools/probe_pack_layout.gd`、`design/art/asset-pack-v6-ui-plate.md`、`art/2d/ui/ui_shop_slot_plate_v1.png`（+ `.import`）
- 修改：`scripts/ui/ui_style.gd`（`slot_plate_tex()`）、`scripts/ui/shop_overlay.gd`（承托层）、`scripts/ui/pack_select_overlay.gd`（包色顶条 + §7 布局修正）、`art/manifest.json`（302 项）、`design/art/asset-inventory-2026-11-09.md`（增量指针 + §11 状态）、`tools/card_batch_prompt.py` 与 `design/art/card-prompts-batch2.json`（旧锚点 DEPRECATED 标注）

---

## 7. 布局修正：卡包页瓦片（2026-11-09 12:19）

§6 备注 2 记的「瓦片行横向超出、卡名溢出」本轮修完。用新写的 `tools/probe_pack_layout.gd` 打印真实矩形后，拆出**三个独立问题**——其中第 1 个是 v6 自己引入的。

| # | 现象 | 真因 | 处理 |
|---|---|---|---|
| 1 | 一条暗红带从第 8 个瓦片一路画到屏幕外 | 包色顶条首版只设 `anchors/offsets`：瓦片尺寸还没算出时 `TextureRect` 被贴图原始尺寸 **640×40** 钉住（`min size` 恒等于贴图尺寸），而瓦片没开 `clip_contents` | 顶条改 `EXPAND_IGNORE_SIZE` 解除最小宽 + `resized` 回调按瓦片宽重铺（`b.size.x − 24`）；瓦片 `clip_contents = true` 兜底 |
| 2 | `Hemorrhage` / `Thunderhead` 等长卡名横向穿到隔壁瓦片 | 双列网格的列宽由**最长卡名**撑开，网格真实宽 **200px** > 瓦片内容区 156px | 卡列表改**单列**（10 行；内容区 156px 能完整放下最长 `Thunderhead` 95px）；卡名标签加 `clip_text + OVERRUN_TRIM_ELLIPSIS`，将来出现更长名字用省略号收尾而不是画出瓦片 |
| 3 | 熔炉包 11 张卡的末行几乎贴着状态行 | 瓦片高是 6 卡时代的预算 | 高度按实测内容定 **480**（10 卡包内容高 449 / 熔炉包 475），X3 同构 → 全部瓦片统一 480，余量由底部 spacer 吸收 |

🔴 **一个差点改错的判断**：探针第一版把面板「1590 宽、x=165」读成溢出屏幕，实际逻辑视口是 **1920×1080**（`window/size/viewport_*`），1600×900 只是 `canvas_items` 等比缩放的**窗口**尺寸（×0.833）。若按 1600 预算把瓦片改窄，会把本来正确的居中布局改坏 —— 已把这条钉进 `pack_select_overlay.gd::TILE_SIZE` 上方注释。

顺带把面板居中从 `set_anchors_and_offsets_preset(PRESET_CENTER) + grow` 换成 `CenterContainer`，宽度由 `PACKS.size()` 推导（加包不再手改常量），实测位置与改前一致（1590 @ x=165 不变）。

**复验**：`probe_pack_layout.gd` → 8 个瓦片全 180×480、`margin min_h` ≤ 480、顶条 156×8；`--check-only` 无报错；全量回归 `[PASS] 54 [FAIL] 0`（波表 101/0、推进 146/0、切片8 92/0、塔等级牌 26/0）；重截 `smoke_v6_pack_select.png` 逐格复核：单列卡名全在瓦片内、8 条顶条不再外溢、面板左右留白对称。

---

*生成标注：本包新资产为程序化生成（PIL 矢量绘制 · 4× 超采样 LANCZOS 降采样），色号逐字取 art-bible §2.2，可通过 `tools/gen_ui_plate_pack_v1.py` 逐字复现。*
