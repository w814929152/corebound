# 守核 Corebound · 正式美术资产包 v1（Art Asset Pack v1）

> 版本：**v1** · 日期：2026-11-07 · 产出方式：程序化生成（PIL 4× 超采样，`tools/gen_art_pack_v1.py` 可复现）
> 上游依据：`design/art/art-bible.md` **v0.2**（§2.2 色板逐字取用 / §2.3 稀有度色阶 / §3.4+§5.5 卡牌蓝图风 / §6.5 UI 资产规格 / §9 非色彩冗余 / §10 命名与目录）
> 对口缺口：**P1-6（稀有度五级色阶 + 卡蓝图风）**、图标体系（原为 0）、九宫格 UI 资产（原为 0）
> 清单 SSOT：`art/manifest.json`（74 项，含九宫格边距）· 视觉复核：`art/_review/contact_sheet_v1.png`

---

## 0. 结论先行

1. **73 张 PNG 已落盘**（`art/2d/ui` 11 张 + `art/2d/icons` 62 张），全部透明底、色号逐字取自 §2.2/§2.3、命名按 §10.2 四段式，可直接入 Godot 4.7 工程。
2. **卡框五档稀有度已按 §2.3 全量落地**：色相 + 边框粗细（2/4/4/6/6 px）+ 角标箭头数（1–5）+ 底纹密度四重冗余，满足 §9「稀有度不可只靠颜色」。
3. **合规校验（专家工具 `art_asset_tools.py check`）无失败项**；全部警告为「工具默认规范 vs 本项目冻结规范」的口径差（见 §5），已逐条给出保留理由，**不做 trim / 不改命名**。
4. **卡面插画（人物/场景）本包不含** —— 属美术圣经开放问题 #3（风格未拍板），见 §6 待定项。

---

## 1. 交付清单

### 1.1 UI 九宫格（`art/2d/ui/`，PNG-32 透明底）

| 资产 | 尺寸 | 九宫格边距 L/T/R/B | 用途 |
|---|---|---|---|
| `ui_panel_9slice_v1.png` | 512×512 | 32/32/32/32 | 商店抽屉 / 弹窗底座（替代 StyleBoxFlat 渐进方案） |
| `ui_btn_primary_v1.png` | 240×88 | 24/24/24/24 | 主操作（辉金描边，§5.1） |
| `ui_btn_normal_v1.png` | 240×88 | 24/24/24/24 | 常规按钮（钢灰描边） |
| `ui_btn_ghost_v1.png` | 240×88 | 24/24/24/24 | 次级操作（半透明底 + 细边） |
| `ui_btn_danger_v1.png` | 240×88 | 24/24/24/24 | 危险操作（警报红） |
| `ui_btn_unavail_v1.png` | 240×88 | 24/24/24/24 | 不可用态（暗灰） |

### 1.2 稀有度卡框（`art/2d/ui/`，512×716，对应 §6.5 卡牌整卡规格）

| 资产 | 边框 | 角标箭头 | 特效（静态基底） |
|---|---|---|---|
| `ui_card_frame_common_v1.png` | 石灰 2px | ▲×1 | — |
| `ui_card_frame_uncommon_v1.png` | 苔绿 4px | ▲×2 | — |
| `ui_card_frame_rare_v1.png` | 湖蓝 4px | ▲×3 | 内发光（已烘焙） |
| `ui_card_frame_epic_v1.png` | 幽紫 6px | ▲×4 | 外发光（已烘焙，**脉冲须引擎 Tween 补**） |
| `ui_card_frame_legendary_v1.png` | 鎏金 6px 渐变 | ▲×5 | 流光渐变（已烘焙，**流动须引擎 shader/UV 补**） |

卡框内部结构（引擎渲染文本，图内零文字）：插图区内板 **460×460 安全区**（§6.5）+ 中心准星 + 四角括号；左上 **辉金六边费用槽**（费用数字由代码渲染）；文字区三行导轨线；底部稀有度条带（底纹密度 1–5 档递增）。边距 40/40/40/40 可九宫格。

### 1.3 图标（`art/2d/icons/`，128 主尺寸 + 64 `_small` 双份，主体占 80%、统一 6px 深描边 `#10131C`）

| 组 | 资产 | 配色 |
|---|---|---|
| 功能 | `ic_scrap`（废料货币·八边螺母）/ `ic_core`（核心）/ `ic_wave`（波次·来袭双弧）/ `ic_tower`（塔位）/ `ic_elite`（精英·品红尖刺环）/ `ic_salvage`（献祭回收）/ `ic_check` / `ic_cross`（可购性形状冗余，§9.2①）/ `ic_lock` / `ic_repair` / `ic_timer`（安全窗）/ `ic_reroll`（刷新） | 耀青 / 辉金 / 熔橙 / 钢灰 / 警报红 |
| 元素标记 | `ic_tag_fire`（焰）/ `ic_tag_frost`（雪晶）/ `ic_tag_pierce`（三重 chevron）/ `ic_tag_shock`（闪电）/ `ic_tag_phys`（锤）/ `ic_tag_magic`（符印菱）/ `ic_tag_true`（虚空斜切环）/ `ic_tag_econ`（币堆） | 火=熔橙 冰=耀青 穿=湖蓝 电=辉金 物=钢灰 魔=幽紫 真=星紫 济=苔绿 |
| 原型徽记 | `ic_proto_arrow`（三角）/ `ic_proto_cannon`（方形）/ `ic_proto_frost`（六边）——与 §3.1 S5 内芯徽记同形 | 耀青 |
| 卡包徽记 | `ic_pack_core`（基石）/ `ic_pack_cinder`（熔炉）/ `ic_pack_rime`（霜序）/ `ic_pack_pierce`（穿甲）/ `ic_pack_arc`（电弧）/ `ic_pack_sunder`（破甲）/ `ic_pack_hex`（咒术）/ `ic_pack_true`（湮灭）—— 文件名与 `card_packs.PACKS` 的 **id 逐字对齐**（v1.1 修订：初版 foundation/forge/frost/oblivion 已改名） | 各包主题色，统一八边底盘 + 深描边 |

> 状态图标（燃烧/减速/眩晕）暂不产出：状态效果系统未实现（圣经 §9.1 ⚪ T1），避免无主资产。

---

## 2. Godot 4.7.2 导入设置（gl_compatibility）

| 项 | 设置 | 理由 |
|---|---|---|
| Compress / Mode | **Lossless**（PNG 原样） | UI 资产带 alpha 与细线，VRAM 压缩会糊边；包体影响可忽略（全套 <1 MB） |
| Filter | **Linear**（默认） | 非像素风；`canvas_items` 缩放下平滑 |
| Mipmaps | **Off** | UI 按 1:1 或整倍缩放，mipmap 致糊 |
| 预乘 alpha | Off | Godot 默认即可 |
| `art/_review/` | 已放 `.gdignore` | 接触表/评审产物不入引擎 |

**九宫格接入示例**（边距已写入 `art/manifest.json`，程序可读）：

```gdscript
# 按钮：StyleBoxTexture 承接 ui_style.gd 的五变体
var sb := StyleBoxTexture.new()
sb.texture = preload("res://art/2d/ui/ui_btn_primary_v1.png")
sb.texture_margin_left = 24; sb.texture_margin_top = 24
sb.texture_margin_right = 24; sb.texture_margin_bottom = 24

# 卡框：NinePatchRect（边距 40），稀有度换 5 张框即可
var card := NinePatchRect.new()
card.texture = preload("res://art/2d/ui/ui_card_frame_rare_v1.png")
card.patch_margin_left = 40; card.patch_margin_top = 40
card.patch_margin_right = 40; card.patch_margin_bottom = 40
```

**与 `scripts/ui/ui_style.gd` 的关系**：`ui_style.gd` 仍是样式 SSOT（README 红线：界面不得二次发明颜色）。v1 贴图与现有 StyleBoxFlat **色值逐字同源**，属渐进替换层：卡框/图标直接可用；按钮与面板迁移时只在 `_base()` 工厂内换 `StyleBoxTexture` 实现，调用方零改动。

---

## 3. 生成与复现

```bash
# 全量重生成（幂等，覆盖 v1）
python tools/gen_art_pack_v1.py        # Python 3.9 + Pillow 11.3
# 合规校验
python <expert>/art_asset_tools.py check art/
# 接触表（视觉回归）
#   见 art/_review/contact_sheet_v1.png；改版后重生成对比
```

关键参数：4× 超采样 LANCZOS 降采样；蓝图网格 32px α12；卡框圆角 = 宽 6%（§3.4）；图标统一 80% 主体 + 6px 描边（§切图规范「统一视觉重量」）。

---

## 4. 需人工精修 / 引擎补动效（不谎报"可直接商用"）

| 项 | 现状 | 补什么 |
|---|---|---|
| 卡面插画 | **未产出**（开放问题 #3 未拍板） | 风格定稿后按提示词包批量生成 + 精修 |
| epic 外发光脉冲 | 静态烘焙 | 引擎 Tween 透明度 0.55↔0.9，1.2s 循环 |
| legendary 流光 | 静态渐变基底 | 引擎 shader UV 流动（或 `TextureRect` 双层错位） |
| `ic_salvage` / `ic_reroll` 弧形箭头 | 程序化折线近似 | 如感生硬，人工补贝塞尔弧（唯一建议精修的图标） |
| 按钮悬停/按下 | 单态贴图 | 沿用 §5.1 代码动效（1.05 / 0.97 / 0.12s），不加贴图态 |

## 5. 合规校验警告的保留理由（逐条）

| 工具警告 | 判定 | 理由 |
|---|---|---|
| `ic_*` 命名不符 | **保留** | 工具默认 `icon_` 前缀；本项目美术圣经 §10.2 冻结为 `ic_`，且 README 要求样式单一来源——不引入第二套命名 |
| 按钮/卡框尺寸非 2 的幂 | **保留** | §6.5 明确卡=512×716（1:1.4）、按钮 240×88；UI 非平铺纹理，Lossless 导入无 POT 要求 |
| 图标"残留透明边可裁" | **保留** | 统一画布 + 主体 80% 是图标体系的硬规则，trim 会破坏同套视觉重量与 64px 缩放对位 |
| "边缘半透明像素" | **保留** | 4× 超采样的圆角抗锯齿，非抠图残留 |

## 6. 接入记录（批次① 已完成 · 2026-11-07）

**P1-6 稀有度五级色阶 + 卡包徽记已进实机**，全量默认回归全绿（2228+222+142+123+302+… 全部 FAIL=0，含 UI 样式 119 项断言）：

| 改动 | 落点 | 说明 |
|---|---|---|
| 稀有度派生 | `scripts/data/card_text.gd` `rarity()` / `weight_of()` | **只读** `shop_ai.WEIGHTS` + `tower_data.EXT_WEIGHTS` 机械映射（≥0.13 普通 / ≥0.095 精良 / <0.095 稀有），改权重卡面自动跟随；金标本零改动 |
| 稀有度色阶 | `scripts/ui/ui_style.gd` `RARITY` + `card_blueprint(state, rarity)` | 色号逐字 §2.3；边框=稀有度，可购性仍走 ✓/✗ + 价格色 + 角刻线（§9.2 双通道不回退） |
| 商品位角标 | `scripts/ui/shop_overlay.gd` | 序号行右侧 ▲×1–5 + 稀有度色边框；X3 三位同构不变 |
| 卡包徽记 | `scripts/ui/pack_select_overlay.gd` + `ui_style.pack_emblem()` | 徽记**内联卡名行**（28px 零增高；首版 56px 独立行实测把 6 卡列表推出瓦片边界，已回改）；`ResourceLoader.exists` 判空，headless 无导入时纯文本降级 |
| 实机目检 | `tools/shoot_rarity_smoke.gd`（非 CI） | 产物 `art/_review/smoke_rarity_shop.png` / `smoke_pack_emblems.png` |

遗留观察：选包瓦片 6 卡列表在 292px 固定高内本就贴边（**改动前已存在**，与徽记无关）——如需收敛属 UX 排期项，不在资产包范围。

## 7. 待定项（需拍板，不擅自改动）

1. **卡面插画风格**（开放问题 #3）：3D 截图转 2D vs 手绘/AI 扁平插画 —— 拍板后我出 30 张卡的提示词包（蓝图风锚点逐字复用，先出 2 张基准）。
2. **字体选型**（开放问题 #5）：✅ 已接入（Noto Sans SC + JetBrains Mono，OFL）；上线前在文档登记授权来源即可。
3. **稀有度档位口径**：当前映射（0.13 / 0.095 两道阈值）是展示层约定，史诗/传说暂空缺 —— 若数值侧后续为高阶卡单独定档，只需改 `card_text.rarity()` 一处。
4. **接入批次②**：✅ 已完成（2026-11-07）——
   - **九宫格按钮**：`ui_style.button()` 内部替换为 `StyleBoxTexture`（5 变体，边距 24，圆角对齐实机 RADIUS=6 重生成）；hover/pressed 用 `modulate_color` 提亮/压暗复刻动态明度差；ghost 全透明保留旧路径；资产缺失整体降级回 StyleBoxFlat（headless 安全）。41 个按钮调用点零改动全量受益。
   - **图标切口**：商店重掷按钮挂 `ic_reroll`、三商品位价格行挂 `ic_scrap`（18px，判空降级纯文本）。`icon()` 收口版本段：调用方可不带 `_v1`（`ends_with("_v1")` 智能补段，`pack_emblem` 两种习惯均兼容）。
   - **关卡锁定态**：✅ 批次③完成——状态行上方 16px 状态图标（锁定→`ic_lock` 灰 / 已通关→`ic_check` 苔绿 / 可挑战→隐藏），🔒/✓ 字符退役（icon 缺失时降级回字形文本，双通道不缺席）。
   - **HUD 金币读数**未动：金币为程序化绘制 + 粒子发射原点（`GOLD_ORIGIN`）耦合，圣经未列缺口，替换收益低风险高 → 待定。
   - **批次⑥（2026-11-08）· 战场实体贴图化**：`art/2d/sprites/` 新增 25 张 `sp_*`（核心 256 / 塔×15 / 怪×3×普通精英 / 投射物×2 / 仆从）+ `ic_coin` 金币，全部由生成器**逐像素复刻**原 draw 代码静态部分（色号逐字取 monster_layer 常量）。`monster_layer.gd` 六处接入：核心（呼吸走缩放、内芯第二频率保留运行时）/ 塔（宿主·选中·停机·复活·形态·闪白保留）/ 怪（`draw_set_transform` rot+scale 承接 squash&stretch 与体摆动，基础 rs/ts 形变烘焙；精英独立变体+品红环保留）/ 投射物（bolt 随 vel 旋转）/ 仆从；`hud.gd` 金币贴图化（脉冲缩放保留）。**全部判空降级**回程序化路径。manifest 100 项。验证：全量回归全绿 + 冒烟帧目检（塔/怪/精英环/仆从/投射物/金币全部生效）。
   - **批次④（2026-11-07）· 九宫格面板接入**：`ui_style.panel()` 内部替换 StyleBoxTexture——描边色映射登记色（耀青→`ui_panel_9slice` / 警报红→新增 `ui_panel_alert_9slice`），7 个调用点零改动（选包/结算/选关底座走青、回收确认/受损塔弹窗走红）；border alpha < 0.9（HUD 积分卡 0.28 / 血条槽 0.75）或未知色自动回落 StyleBoxFlat（透明叠加语义贴图表达不了）；content padding 仍由调用方 h/v 参数控制。验证：uistyle 119 / 全量回归全绿 / 冒烟目检面板网格纹理与描边无接缝。
   - 验证：uistyle 119 项 / 全量默认回归全部 FAIL=0；实机截图目检（按钮九宫格质感 + 两处图标均生效）。

---

*生成标注：本包全部资产为程序化生成（AI 辅助 · PIL 矢量绘制），来源/版本/参数见 §3，可逐字复现与替换。*
