# 资产包 v5 · 卡组图鉴分组底板 —— 提案

**状态**：🟢 已落地（2026-11-08）
**范围**：主界面卡组图鉴页（`main_menu_overlay._build_library` / `_make_pack_block`）。
卡包选择页（`pack_select_overlay`）与战役 v2 屏由并行会话开发中，本包不碰。

## 1. 问题（基准 `art/_review/smoke_menu_library.png` 改前版）

图鉴 8 个分组（每组：标题行 + 10 卡网格）**没有任何底板**，直接浮在 keyart
蓝图遗迹上 —— 背景的六边形蜂巢从卡缝里穿透，视觉嘈杂、分组彼此难分。

## 2. 资产（2 件，`art/2d/ui/`）

| 资产 | 尺寸 | 说明 |
|---|---|---|
| `ui_lib_block_v1` | 48×48 | 分组底板 9-slice 源（corner 12）：中性深面板 `#0E111B` α242 + 1px 描边 `#262E42` + 四角 3px 刻线 `#3A4460`。🔴 **不染色**——必须衬全部 8 包主题色 |
| `ui_lib_head_bar_v1` | 640×40 | 分组标题条：**白烘焙**（modulate 乘色染主题色）——左端 5px 竖帽 + 斜切收头 + 主体 α205→26 右端渐隐 + 底部 1px 亮线（染后 = 主题色下划线） |

## 3. 包主题色表（`ui_style.pack_color(id)`，全部 art-bible §2.2 表内色）

| id | 包 | 色 |
|---|---|---|
| core | 泛用 | 钢灰 `#9AA5B1`（中性） |
| cinder | 熔炉 | 熔橙 `#FF6B3D` |
| rime | 霜序 | 耀青 `#3ED0E8` |
| pierce | 穿甲 | 辉金 `#FFC94A` |
| arc | 电弧 | 星紫 `#7A5CFF` |
| sunder | 破甲 | 噬品红 `#E8437F` |
| hex | 咒术 | 深青 `#1A6B7D` |
| true | 湮灭 | 警报红 `#FF2E4E` |

🔴 染色铁律：modulate 是**乘法**——只有白/灰烘焙件可染色，深底件会染黑。

## 4. 接入（`_make_pack_block`，判空降级）

- head 行 → `PanelContainer(StyleBoxTexture head_bar)` + `modulate = pack_color(pid)`
  + MarginContainer(left 20)；
- block（标题条 + 卡网格）→ `PanelContainer(StyleBoxTexture block 9-slice)` +
  MarginContainer(14/8/14/10)；
- 底板生效时原 `_Style.hline()` 让位（标题条自带下划线）；
- 任一贴图缺失 → 逐层回退到原裸 VBox 结构，headless 安全。

## 5. 教训区（落地后回填）

- **PanelContainer 不能叠绝对定位子控件**（所有子控件都进内容区排列）——
  accent 竖条因此烘焙进标题条左端，而不是独立件 + 锚定叠加。
- 染色模拟脚本先于实机验证（PIL 乘色预览三条），实机一次过。
