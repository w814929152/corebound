# 美术资产缺口审计 · 2026-11-09 09:09 快照

> ⚪ **本文已过期作废（2026-11-09 11:45 标记）**：并行产线已于当日完成 **80/80 张卡面收官**（标准 v1.8）并提交 git；
> 本文所有卡面数字（31 张 / 缺 49 张 / v1.2 口径 / UI 未实机验证）均已失效。
> **请改读 `asset-inventory-2026-11-09.md`**（11:45 现状梳理），其 §10 列出了与本文的逐项差异。本文仅沿革留档。
>
> 🔴 **动态状态（原文，已失效）**：并行产线正在活跃落盘（08:31 熔炉包、09:05 前后霜序包 9 张 + 穿甲包试点 1 张）。
> 本文是 **09:09:04 的一次快照**，卡面数字会继续变化；对账方法见 §6，可随时重跑。
> 现行卡面口径以 `design/art/card-art-generation-standard-v1.md` **v1.2** 为准
> （3/4 视角图生图 + 包色即整机主色调）；本会话 07:47 的「按第一批 10 张风格」方向
> 已被 08:38 的拍板覆盖，`card-illustration-style-v1.md` 已挂留档指针。

## 1. 结论速览

| 类别 | 结论 |
|---|---|
| **真缺口（有定义、无资产）** | ① 卡面 **49 张**；② Steam 发行素材（4K hero / 胶囊 / 库图标 / 成就图标）；③ 少量 UI 质感增强件 |
| **交接缺口（文件已有、清单未收）** | `art/manifest.json` 163 项，磁盘 203 张 PNG，**40 个文件（20 张卡 ×2）未登记** |
| **进行中** | `art/_review/batch6/` 霜序包 9 张已落盘；穿甲包 `Martyr` 1 张试点已落盘，其余 9 张未出 |
| **有意程序化、不算缺口** | 战场塔身/怪物轮廓、VFX 特效、伤害数字、地形手绘层 —— art-bible §2.5 / §6 的 Solo 约束就是「零贴图」 |
| **待复核** | `Harrier` 双发射鼓像眼睛；`core` 蓝钢灰族与其余 7 包整机包色两口径并存（用户已拍板保留） |

## 2. 数量对账（09:09）

| 类别 | 应有 | 磁盘 PNG | manifest | 状态 |
|---|---|---|---|---|
| 卡面 `cards/` | 80 张（8 包 ×10） | 31 张 ×2 = 62 | 22（11 张 ×2） | 🔴 缺 49 张 + 40 文件未登记 |
| UI `ui/` | — | 43 | 43 | ✅ 齐 |
| 图标 `icons/` | 63 | 63 | 63 | ✅ 齐 |
| 地形 `maps/` | 10 | 10 | 10 | ✅ 齐（variant-a..h + fusion + tri_fissure） |
| 战场 `sprites/` | — | 25 | 25 | ✅ 齐（怪物 7 / 塔 15 / 投射物 2 / 核心 1） |
| 主视觉 `ui/keyart_*` | — | 4（均 1920×1080） | 4 | 🟡 4K / 胶囊未产出 |
| 代码字面引用 `res://art/…` | 13 条 | 12 条存在 | — | ✅ 唯一「缺失」是 `tools/probe_font_weight.gd` 的临时探针 `_tmp_weight_probe.png`（测试自产，非资产） |
| `.import` 缺失 | 0 | — | — | ✅ 全部 203 张都已被引擎导入 |

> 注：战场塔身贴图「齐」指资产齐，但 `card-art-generation-standard-v1.md` §6 明确
> **战斗内塔身是 Node2D 程序化绘制，不走贴图**；`sp_tower_*` 用于其它场合/后续。

## 3. 卡面缺口明细（49 张）

| 包 | 包色 | 已落盘 | 缺口 |
|---|---|---|---|
| `core` 泛用 | 钢灰 `#9AA5B1` | 10/10 | ✅ 中性基准族，v1.2 明确不重出 |
| `cinder` 熔炉 | 熔橙 `#FF6B3D` | 10/10 | ✅ 批次⑤整机主色调 |
| `rime` 霜序 | 耀青 `#3ED0E8` | 10/10 | ✅ 批次⑥已补齐（Glacier 试点 + 9 张） |
| `pierce` 穿甲 | 辉金 `#FFC94A` | **1/10**（Martyr） | 9 张：Lance / Javelin / Ballista / Sniper / Arcane / Longbow / Needle / Hemorrhage / Impaler |
| `arc` 电弧 | 星紫 `#7A5CFF` | 0/10 | 10 张全缺 |
| `sunder` 破甲 | 噬品红 `#E8437F` | 0/10 | 10 张全缺 |
| `hex` 咒术 | 深青 `#1A6B7D` | 0/10 | 10 张全缺 |
| `true` 湮灭 | 警报红 `#FF2E4E` | 0/10 | 10 张全缺 |

风险提示（现行标准 §8 #7）：`hex` 深青是低饱和暗包色、`sunder`/`true` 与 `rime`/`hex` 是近色对，
覆盖率自检与同族比对需先出 1 张验证；`pierce` 辉金与 `cinder` 熔橙也偏近。

## 4. 卡面以外的缺口

### 4.1 发行素材（`keyart-style-v1.md` §遗留）
- `keyart_hero_v1` 4K（3840×2160）：现为 1536 生成图放大到 1920×1080，直接 ×2.5 会糊，需专业升频或分段重绘。
- Steam 胶囊 1232×456 / 616×353（上线前从 hero 裁）。
- Steam 库图标 / 成就图标 / 应用图标：目录里完全没有。

### 4.2 UI 质感增强（可选，不是「缺了会坏」）
- 商店商品位 9-slice 承托贴图：现用 `_Style.card_blueprint()` 程序化样式 + 四角刻线；`asset-pack-v2-hud.md` §7 遗留第 2 条仍未做。
- 卡包选择页分组底板：`asset-pack-v5-lib.md` 明确「本包不碰」，现 `pack_select_overlay.gd` 只有 `_Style.panel()` + 徽记 TextureRect，可复用 `ui_lib_block/head_bar_v1`。
- 教学遮罩 `tutorial_overlay.gd`：1 个裸 `StyleBoxFlat`，无贴图。
- 状态效果图标（燃烧/减速）：`asset-pack-v2-hud.md` §7 判定 **暂不产出**（状态系统只有数值，属无主资产，art-bible §9.1）。

### 4.3 工具/文档一致性（交接债）
- `tools/card_batch_prompt.py` 的 ANCHOR 仍是本会话 07:5x 写的 **v4c 正视图蓝钢灰锚点**，
  与现行 v1.2（3/4 图生图 + 包色整机主色）冲突；`design/art/card-prompts-batch2.json` 同样过期。
  两者已不参与现行产线（现行走 `tools/card_batch3_process.py`），应标注废弃或回退，避免误用。
- `card-art-generation-standard-v1.md` §8 #5：本机无 Godot 编辑器（只有导出的 exe），
  **UI 接线未实机验证** —— 不是资产缺口，但会影响「已有资产是否真的显示」。

## 5. 建议优先级

1. **P0 · 交接**：把 40 个新卡面文件补进 `art/manifest.json`（163 → 203），并标注批次⑤/⑥来源。
2. **P0 · 收口**：处理 `card_batch_prompt.py` / `card-prompts-batch2.json` 与现行标准的冲突标记。
3. **P1 · 主缺口**：按 v1.2 逐包推进剩余 49 张 —— 先 `pierce` 余 9 张（已有 Martyr 试点），
   再 `arc` / `sunder` / `hex` / `true`；每包先出 1 张同族比对，通过后 `--dominant` 批量后处理。
4. **P2 · 质感**：商店商品位承托件、卡包选择页 v5 底板推广、教学遮罩。
5. **P3 · 上线前**：hero 4K 升频 + Steam 胶囊/图标。

## 6. 复跑方法

```bash
# 卡面缺口
py -3.9 -c "import os,json,collections; bank=json.load(open('design/art/card-prompt-bank-v2.json',encoding='utf-8'))['cards']; cards={f[5:-12] for f in os.listdir('art/2d/cards') if f.endswith('_v1_460.png')}; miss=[k for k in bank if k.lower() not in cards]; by=collections.defaultdict(list); [by[bank[k]['pack']].append(k) for k in miss]; print(len(miss),dict(by))"
# manifest 未登记
py -3.9 -c "import os,json; man={x['file'] for x in json.load(open('art/manifest.json',encoding='utf-8'))['assets']}; disk={os.path.relpath(os.path.join(dp,f),'art/2d').replace(os.sep,'/') for dp,_,fs in os.walk('art/2d') for f in fs if f.endswith('.png')}; print(len(disk-man),sorted(disk-man)[:5])"
```
