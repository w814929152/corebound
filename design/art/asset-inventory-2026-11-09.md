# 守核 Corebound · 美术资源现状梳理

> 快照时间：**2026-11-09 11:45:16**（本地）。本文是「当时有什么」的清单，不是缺口审计；下文数字均为该时刻快照，不回改。
> 前一份 `asset-gap-audit-2026-11-09.md`（09:09 快照，31/80 卡面）**已过期作废**，仅留作沿革；差异见 §10。
> 现行卡面口径：`design/art/card-art-generation-standard-v1.md` **v1.8**（3/4 视角图生图 + 包色即整机主色调 + 引擎实机验收）。
> 复跑方法见 §12，任何数字都可重新对账。
>
> 🆕 **12:14 增量（资产包 v6 · 见 `asset-pack-v6-ui-plate.md`）**：§0 / §1 / §10 的「301 张 / manifest 163 项 / 138 未登记 / UI 43 件」已变化为
> **302 张 PNG / manifest 302 项 / 0 未登记 / UI 44 件**。§11 的 #1（manifest 补登）、#5（UI 质感）、#6（闲置件定性）已处理完毕，详见 §11 的 ✅ 标记。
>
> 🆕 **12:40 增量（资产包 v7 · 见 `asset-pack-v7-store.md`）**：新增 `art/store/` **12 件发行素材**
> （Steam 8 张店铺/库画幅 + 客户端图标 png/ico + 社区图标 + 4K 主视觉）。该目录带 `.gdignore`，
> **不进引擎、不计入上面 302 张**，是纯发行用图；§11 #4 已大部分收口。
>
> 🆕 **13:10 增量（UI 收口 v8 · 见 `ui-polish-v8.md`）**：本轮**没有新增素材**，修的是排版与形态：
> 图鉴卡宽从 278~326 六种混排锁死到 **278**（8 包中 6 包不齐，最右列溢出公共边界 82px）；
> ghost 三级入口从「一行灰字」改成 **2px 下划线式**；结算横幅 520→640 等比 + 退回标题底纹。
> 另新增 4 个可复跑脚本（2 个判据 + 截图 + 拼图），**9 页全量「内容被压」体检 0 问题**。

---

## 0. 一页速查

| 项 | 现状 |
|---|---|
| 正式位图资产 | **301 张 PNG**，`art/2d/` 下 5 个目录，全部有 `.import`（引擎已导入） |
| 卡面插画 | **80 / 80 张完成**，8 包各 10 张；每张 2 个文件 = **160 个 PNG** |
| UI / 图标 / 地形 / 战场 | 43 / 63 / 10 / 25 件，四组全部齐备且已接线 |
| 字体 | 2 个 TTF + 1 个 `.tres`（全局字重 500 / 700 / 900） |
| 版本状态 | 卡面收官与实机验收**已提交 git**（`ffbaabc`、`31e1634`）；工作区仅 1 处无关文档改动 |
| 主要遗留 | `manifest.json` 只登记 163 项，**138 个卡面文件未登记**；发行素材（4K / Steam 胶囊）未产出；图鉴第 81 卡位 `Pyroclasm` 无卡面 |
| 有意不做 | VFX 特效、伤害数字、状态效果图标、战场几何层 —— art-bible §2.5「程序化绘制、零贴图」Solo 约束 |

---

## 1. 总量对账

| 目录 | 磁盘 PNG | manifest 登记 | `.import` | 规格 |
|---|---:|---:|---:|---|
| `cards/` | 160 | 22 | 160 | 1024² 透明原图 + 460² 安全区件，各 80 |
| `ui/` | 43 | 43 | 43 | 8×18 ~ 1920×1080，含 4 张主视觉 |
| `icons/` | 63 | 63 | 63 | 64×64 / 128×128 两档 |
| `maps/` | 10 | 10 | 10 | 全部 1024×1024 |
| `sprites/` | 25 | 25 | 25 | 64 / 128 / 256 三档 |
| **合计** | **301** | **163** | **301** | 缺 `.import`：0 |

`art/_review/` 是评审留档（接触表、原图、样张、对比图、废案），**不进引擎、不进 manifest**；
`build/windows/Corebound.exe` 为导出产物，`build/` 不入库。

---

## 2. 卡面插画（80 张 · 收官）

**规格**：`card_<name小写>_v1_t.png`（1024² 透明底）+ `card_<name小写>_v1_460.png`（460² 安全区裁切件）。
UI 由 `scripts/ui/ui_style.gd::card_art(card_name)` 懒加载，缺图 / headless 降级为无图版式（商店 424px 卡位顶部 72px 插画带、图鉴 96×96 左图）。

**包色 SSOT**：`scripts/ui/ui_style.gd::PACK_COLORS` = `card-prompt-bank-v2.json::pack_palette`，卡面与图鉴分组标题条共用同一编码。

| 包 id | 名称 | 包色 | 张数 | 后处理档位 | 包色覆盖率 |
|---|---|---|---:|---|---|
| `core` | 泛用 | 钢灰 `#9AA5B1` | 10 | 默认（白场 155） | 中性基准族，不参与覆盖率自检 |
| `cinder` | 熔炉 | 熔橙 `#FF6B3D` | 10 | 默认 | 65.4–83.4% |
| `rime` | 霜序 | 耀青 `#3ED0E8` | 10 | `--bright-pack` | 82.6–98.1% |
| `pierce` | 穿甲 | 辉金 `#FFC94A` | 10 | `--bright-pack` | 51.5–84.7% |
| `arc` | 电弧 | 星紫 `#7A5CFF` | 10 | `--mid-pack` | 45.6–71.3% |
| `sunder` | 破甲 | 噬品红 `#E8437F` | 10 | `--lift-pack` | 41.6–69.5% |
| `hex` | 咒术 | 深青 `#1A6B7D` | 10 | `--lift-pack`（复用） | 88.5–99.6% |
| `true` | 湮灭 | 警报红 `#FF2E4E` | 10 | `--lift-pack`（复用） | 64.3–81.7% |

**同族判据（六项）**：粗深藏青描边 / 分层装甲板 / 面板缝 / 铆钉 / 斜切高光 / 3/4 玩具模型构图。颜色只负责区分卡包。
**两种口径并存（用户 11-09 拍板保留）**：`core` 10 张仍是蓝钢灰中性基准族，其余 7 包是整机包色主色调。若日后要全组严格统一，单独重出 `core`。
**近色对已解除**：`rime`↔`hex`（深青靠明度差）、`sunder`↔`true`（模板补 `NOT pink, NOT magenta, NOT crimson`），均有并排复核留档。

**逐包名单**（80）：
- core — Arrow, Cannon, Catapult, Foundry, Frost, Harrier, Kinetic, Ranger, Scout, Sentry
- cinder — Ashen, Blaze, Cinder, Ember, Furnace, Hellfire, Maul, Pyre, Vanguard, Wildfire
- rime — Avalanche, Drillmaster, Glacier, Hail, Icicle, Permafrost, Purity, Shard, Snowfall, Whiteout
- pierce — Arcane, Ballista, Hemorrhage, Impaler, Javelin, Lance, Longbow, Martyr, Needle, Sniper
- arc — Arc, Bolt, Circuit, Coil, Overcharge, Spark, Storm, Tesla, Thunder, Thunderhead
- sunder — Bastion, Breaker, Crusher, Drummer, Quake, Rend, Ruin, Shatter, Siege, Sunder
- hex — Blight, Curse, Executioner, Hex, Hexer, Malison, Omen, Plague, Rune, Wither
- true — Eraser, Exile, Necro, Null, Obliterator, Oblivion, Rift, Soulpiercer, Void, Wraith

全组视觉总览：`art/_review/asset_overview_cards_80.png`（8 行 × 10 列，包色色标在左）。
引擎验收（v1.8）：`--import` 重导入、80 张全量加载探针、重新 `--export-release`、图鉴 / 商店实机截图四项全通过。

---

## 3. UI 贴图（43 件 · 按组）

| 组 | 件数 | 规格 | 运行时接线 |
|---|---:|---|---|
| 主视觉 `keyart_*` | 4 | 1920×1080 | `keyart_menu_bg_v1` 主菜单现行；`keyart_stage_bg_v1` 选关航图现行；**`keyart_hero_v1`（源图）、`keyart_menu_hero_v1`（备用派生）闲置** |
| 按钮 `ui_btn_*` | 5 | 240×88, 9-slice 24 | `normal / primary / danger / unavail` 由 `_btn_tex()` 拼接加载；**`ghost` 明确走 StyleBoxFlat，贴图冗余** |
| 卡框 `ui_card_frame_*` | 5 | 512×716 | 🔴 **未接入运行时**：只出现在 `gen_art_pack_v1.py` 生成器与 `card_mock_card.py` 预览工具；实际卡框由 `card_blueprint()` 的 `StyleBoxFlat` 绘制 |
| 面板 `ui_panel_*` | 2 | 512×512, 9-slice 32 | `_panel_tex()` 按描边色拼接（耀青 / 警报红） |
| 核心血条 `ui_core_seg_*` | 3 | 348×36 等 | 字面引用，`core_hp_bar.gd` 缓存 |
| HUD 承托 `ui_hud_*` | 3 | 232×104 / 8×18 / 300×10 | 字面引用，`hud.gd` 缓存 |
| 波次条 `ui_wave_*` | 4 | 300×10 等 | 字面引用 |
| 航图节点 `ui_map_node_*` | 4 | 48×48 等 | 字面引用；锁定态强制用 `node_locked` 专件，不可减 alpha |
| 章节徽记 `ui_map_badge_ch1..4` | 4 | 32×32 | `_ht("ui_map_badge_ch%d_v1.png" % ch)` 拼接 |
| 结算 `ui_result_*` | 4 | 1920×1080 ×2 + 960×96 ×2 | 字面引用，胜负双套情绪背景 + 横幅 |
| 三态光标 `ui_cursor_*` | 3 | 28×22 / 64×64 | 字面引用，`ui_style.set_cursor()` 按拖卡状态切换 |
| 图鉴分组 `ui_lib_*` | 2 | 48×48 + 640×40 | 字面引用；9-slice 底板 + 运行时染包色的白烘焙标题条 |

**接线统计（11:45 快照）**：字面引用 25 件 + 路径拼接引用 10 件 + 闲置 / 冗余 8 件 = 43。
所有贴图接入都走 `ResourceLoader.exists()` 判空缓存，缺图一律回落到原程序化版式，不会白屏。

> 🆕 **v6 增量**：新增 `ui_shop_slot_plate_v1.png`（48×48 9-slice 承托板，商店商品位），UI 变 44 件；
> 那 8 件「闲置 / 冗余」已逐件定性为**留档件（不接入）**，理由见 `asset-pack-v6-ui-plate.md` §4 ——
> 从此接线 36 件（字面 25 + 拼接 10 + 承托 1）/ 留档 8 件，不再有状态不明项。

---

## 4. 图标（63 件）

`ui_style.gd::icon()` 懒加载，调用方可省版本段（`icon("ic_scrap")` 与 `icon("ic_scrap_v1")` 都命中同一文件）；`pack_emblem(pack_id)` 拼 `ic_pack_<id>_v1`。

| 组 | 件数 | 内容 |
|---|---:|---|
| 卡包徽记 `ic_pack_*` | 16 | 8 包 × 主/小两档，与 `card_packs.PACKS` 逐字对齐 |
| 标签 `ic_tag_*` | 16 | econ / fire / frost / magic / phys / pierce / shock / true × 两档 |
| 原型 `ic_proto_*` | 6 | arrow / cannon / frost × 两档 |
| 通用状态与资源 | 24 | check, cross, lock, elite, core, repair, reroll, salvage, scrap, tower, timer, wave × 两档 |
| 金币 `ic_coin_v1` | 1 | 单尺寸 |
| 合计 | 63 | 64×64 / 128×128 两档，`_small` 后缀 31 件 |

状态效果图标按 art-bible §6 明确「暂不产出（无主资产 / 无状态效果系统）」，不算缺口。

---

## 5. 地形（10 张）

`map_terrain_variant_a..h_v1.png` 8 张变体 + `map_terrain_fusion_v1.png` + `map_terrain_tri_fissure_v1.png`，全部 1024²。
由 `monster_layer.gd::_draw_map_layer()` 懒加载，是几何之上的**材质层**；地形几何仍由 `scripts/data/map_variants.gd`（SSOT）决定。
出怪口土带、阵地台、同心环 / 放射刻度、放置网格**刻意不烘焙**（状态驱动，烘焙会把状态焊死）。规范见 `asset-pack-v4-map-terrain.md`。

---

## 6. 战场实体（25 件）

| 组 | 件数 | 名单 |
|---|---:|---|
| 塔身 `sp_tower_*` | 15 | arrow, bolt, cannon, ember, frost, hex, icicle, javelin, lance, maul, oblivion, rune, sunder, tesla, void |
| 怪物 `sp_mon_*` | 6 | rush / swarm / tank 各含普通 + elite |
| 投射物 `sp_proj_*` | 2 | bolt, dot |
| 核心 / 杂兵 | 2 | `sp_core_v1`(256²), `sp_minion_v1` |
| 散布件 | — | 其余为 128² / 64² |

`monster_layer.gd::_sprite("sp_tower_" + ctype.to_lower())` 拼名加载，判空降级回程序化 `draw_*`。
VFX 特效、伤害数字、塔位空槽 / 威胁楔、同心环仍为纯代码绘制，Solo 约束下的有意选择。

---

## 7. 字体与其他视觉资源

`assets/fonts/`：`NotoSansSC.ttf`（中文可变字重）、`JetBrainsMono.ttf`（数字）、`notosans_sc_body.tres`（FontVariation wght 500，挂 `project.godot` 的 `theme/custom_font`）、两份 OFL 许可。
🔴 关键坑：`FontVariation.variation_opentype` 必须用 **OpenType tag 整数键**（`wght` → `2003265652`），字符串键会被 Godot 静默忽略导致字重一直是 400。见 `art-bible.md` §5.4。

---

## 8. 规范文档地图（`design/art/`）

| 文档 | 作用 | 状态 |
|---|---|---|
| `art-bible.md` | 总纲：色板 / 命名四段式 / 渲染管线 / 字体坑 | v0.2 现行 |
| `card-art-generation-standard-v1.md` | **卡面唯一现行标准** | 🟢 v1.8，80/80 收官 + 实机验收 |
| `keyart-style-v1.md` | 主视觉与派生件口径 | 现行，`menu` 为现行主菜单底 |
| `card-prompt-bank-v2.json` | 80 卡「对象 / 特征 / 主色 / 包色」数据 SSOT | v2.7，🔴 勿用 `build_card_prompt_bank_v2.py` 重建（会回退 80 张手工补强） |
| `asset-pack-v1/v2-hud/v3-map/v4-map-terrain/v4-result/v5-lib.md` | 六个资产包提案与接入记录 | 全部已落地 |
| `card-illustration-style-v1.md`、`card-prompts-batch1/2.json`、`tools/card_batch_prompt.py` | 旧正面立面 v4/v4b/v4c 口径 | ⚪ **留档 + 已挂 DEPRECATED 标注，与现行 3/4 口径冲突，勿用于新卡** |
| `asset-gap-audit-2026-11-09.md` | 09:09 缺口审计 | ⚪ **已过期作废**，见 §10 |

---

## 9. 产线工具（`tools/`）

| 环节 | 脚本 |
|---|---|
| 卡面出图后处理 | `card_tone_levels.py`（四档色阶）、`card_keyout.py`（自适应底色去底 + 可选 `--degrid`）、`card_batch3_process.py`（整包批量）、`card_mock_card.py`（卡框样张）、`card_contact_sheet.py` |
| 程序化贴图生成 | `gen_art_pack_v1.py`（v1 界面件）、`gen_ui_hud_pack_v1.py`、`gen_ui_map_pack_v1.py`、`gen_ui_result_pack_v1.py`、`gen_ui_lib_pack_v1.py`、`gen_map_terrain_v1.py` |
| 主视觉派生 | `keyart_postprocess_v1.py`、`keyart_menu_hero_v1.py`、`keyart_stage_bg_v1.py` |
| 引擎探针 / 截图 | `probe_card_art_all.gd`（80 张加载）、`shoot_card_art_smoke.gd`、`shoot_main_menu.gd`、`shoot_stage_smoke.gd`、`shoot_hud_smoke.gd`、`shoot_result_smoke.gd`、`shoot_map_terrain_smoke.gd`、`shoot_rarity_smoke.gd`、`probe_font_weight.gd` |
| 评审留档 | `art/_review/batch1..batch11/` 各含 `raw_*` 原图、`mock_*` 卡框样张、`contact_*` 接触表、`compare_*` 对比、`watermark_check_*` |

---

## 10. 与 09:09 审计的差异（那份已作废）

| 项 | 09:09 快照 | 11:45 快照 |
|---|---|---|
| 正式卡面 | 31 张 | **80 张（+49，全部收官）** |
| 磁盘 PNG | 203 | **301** |
| manifest 未登记 | 40 个文件 | **138 个文件**（全是新增卡面，未同步登记） |
| 现行标准 | v1.2 | **v1.8**（新增 4 个后处理档位 + 引擎实机验收） |
| UI 接线实机验证 | 「未验证」 | ✅ Steam 版 Godot 4.7.2 全项通过 |
| git | v4/v5 未提交 | ✅ `ffbaabc` + `31e1634` 已提交，工作区干净 |

---

## 11. 剩余事项（按优先级）

| # | 事项 | 说明 |
|---|---|---|
| 1 | ✅ **已解决（v6）** manifest 补登记 138 个卡面文件 | 新增 `tools/sync_art_manifest.py` 一键全量对账：163 → 301 项，孤儿 0 / size 不符 0；再加 1 件承托板 = **302 项**，磁盘 302 张逐一对齐 |
| 2 | ✅ **已解决（v6）** 过期锚点清理 | `tools/card_batch_prompt.py` 头部已挂 🔴 DEPRECATED 说明（指向现行 v1.8 标准、注明勿运行生成新卡）；`design/art/card-prompts-batch2.json` 顶层加 `_status` / `_superseded_by` 字段。JSON 解析与 10 条 prompts 校验通过 |
| 3 | 图鉴第 81 卡位 `Pyroclasm` | cinder 包额外收录但无卡面，图鉴显示纯文字卡条；补 1 张需用户拍板（标准 §8 #11） |
| 4 | 🟡 **大部分已解决（v7，12:40）** 发行素材 | Steam 8 张店铺画幅（460×215 / 231×87 / 616×353 / 748×896 / 1438×810 / 600×900 / 3840×1240 / 1280×720 logo）+ 客户端图标 png/ico + 社区图标 + 4K 主视觉，全部从 `keyart_hero_v1` 派生，见 `asset-pack-v7-store.md`。**仍缺**：游戏截图 1920×1080（要真机挑局）与成就图标 64×64（项目未接 Steamworks，无成就表） |
| 5 | ✅ **已解决（v6，按实际空白收敛）** UI 质感增强 | 商店商品位 9-slice 承托板已落地；卡包选择页改为复用 v5 白烘焙标题条做**包色顶条**（绝对定位不占高度）；教学遮罩按 `ui_style` 红线①「半透明透出下层走 StyleBoxFlat」**判定不该贴图化**。详见 `asset-pack-v6-ui-plate.md` §1 |
| 6 | ✅ **已解决（v6）** 闲置件处置 | 8 件逐件定性为留档：卡框 5 张是 512×716 整卡蓝图网格、与现有卡位比例差 1.8× 且自带稀有度角标会形成第三重语义，仅用于 `card_mock_card.py` 样张；`ui_btn_ghost_v1` 永不被加载；两张 keyart 是源图 / 备用派生 |
| 7 | 已知小瑕疵 | `Harrier` 双发射鼓像眼睛（待用户复核）；`Whiteout` 等 7 张在角落检查区有少量不透明像素，已人工确认是部件边缘 / 抗锯齿，非水印 |
| 8 | 导出版自测 | `Corebound.exe` 无头自测固定 6 项失败（pck 内 `.gd` 编译为 `.gdc`，源码 grep 断言读不到文本），属非回归；项目模式 123/0 全通过 |
| 9 | ✅ **已修（12:19）** | 卡包页瓦片：卡列表双列→单列、瓦片高 336→480、包色顶条按瓦片宽重铺 + 瓦片 `clip_contents`。三项真因与复验见 `asset-pack-v6-ui-plate.md` §7 |
| 10 | ✅ **已修（13:10 · v8）** | 图鉴卡宽不齐（278~326 六种，8 包中 6 包，最右列溢出 1536→1618）、ghost 三级入口在暗背景上不可见、结算横幅非等比拉伸 + 压过标题。真因与验证见 `ui-polish-v8.md` §1 |

---

## 12. 复跑对账

```bash
cd "G:/AI Demo/corebound"
py -3.9 -c "
import os,json,collections
man={x['file'] for x in json.load(open('art/manifest.json',encoding='utf-8'))['assets']}
disk={os.path.relpath(os.path.join(dp,f),'art/2d').replace(os.sep,'/')
      for dp,dn,fn in os.walk('art/2d') for f in fn if f.endswith('.png')}
print('manifest',len(man),'disk',len(disk),'unregistered',len(disk-man))
print(collections.Counter(x.split('/')[0] for x in disk))
bank=json.load(open('design/art/card-prompt-bank-v2.json',encoding='utf-8'))['cards']
cards={f[len('card_'):-len('_v1_460.png')] for f in os.listdir('art/2d/cards') if f.endswith('_v1_460.png')}
print('cards',len(cards),'missing',[k for k in bank if k.lower() not in cards])
"
```
