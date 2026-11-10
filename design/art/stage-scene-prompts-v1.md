# 守核 Corebound · 关卡场景图提示词包 v1（选关航图用）

> 状态：🟡 v1 已产出，**待基准评审后接入引擎**（锚点部分沿用已拍板的 `keyart-style-v1.md`，无需重新拍板）。
> 上游依据：`keyart-style-v1.md` §2 风格锚点（冻结）· `art-bible.md` §2.2 主色板 · `campaign_data.gd` STAGES 十关定义。
> 用途：裂隙航图（`stage_select_overlay.gd`）每关一张场景图，作关卡详情/悬停预览位。
> 规格：1536×1024 生成（近 3:2 横版），接入时按详情卡槽位裁切；命名 `stage_scene_<关ID下划线>_v1.png`，落 `art/2d/stages/`。

---

## 1. 结论

10 关 × 1 张，全部沿用 **COREBOUND KEYART v1 冻结锚点**，只换「场景槽位」一个变量；曝光档默认 **hero 满强度**（关卡详情卡是玩家注视焦点，非背景层）。

---

## 2. 冻结锚点（生成时整段复制，禁止凭记忆改写）

```
【风格锚点 · COREBOUND KEYART · v1 逐字冻结】
Flat vector sci-fi illustration in engineering blueprint style, wide 16:9.
Bold dark-navy structural outlines (uniform stroke weight), matte flat colors,
no gradients within objects, no soft airbrush shading, no painterly texture.
Composition: radial siege topology — a glowing fortified CORE at the center of
concentric defense rings, enemy swarms converging inward along radial vectors
from the outer spawn ring. Clean polygons, hexagons, gear rings, circuit lines
and thin cyan technical guide-lines, like an engineering top-down siege diagram.
Background: solid dark night-purple #141726 with faint blueprint grid lines.
Dual accent palette only: lake-cyan #3ED0E8 for ally structures and energy,
forge-orange #FF6B3D for incoming enemies, gold #FFC94A for the core; all other
colors muted steel and desaturated. Top-down flat 2D, NOT isometric, NOT 3/4
perspective, no characters, no text, no watermark, no logo, no outer glow
halos, no lens flares, no particles haze.
```

## 3. 通用后缀（每条提示词末尾统一追加）

```
High contrast scene card: vivid accents, the core clearly radiant, sense of
imminent collision at the defense line.
```

**禁忌清单**（继承 keyart v1）：❌ 等距 / 3/4 透视；❌ 厚涂 / 物体内渐变 / 柔光 / 镜头光晕；❌ 文字、可识别 IP、人物；❌ 超出 青/橙/金(+品红精英) 的强调色。

## 4. 每关场景槽位（变量 = 只改这一段）

| 关卡 | 名称 | 场景槽位（接在锚点后） |
|---|---|---|
| 0-1 | 铁砧·中继站 | `Scene: the neutral relay hub Anvil Relay — a symmetrical three-fissure junction arena, plain steel hex platforms and thin cyan guide lines only, calm and orderly, a small gold core at center, minimal enemy presence.` |
| 1-1 | 灰烬熔炉 | `Scene: Cinder Forge — an industrial foundry arena with glowing forge-orange vents and ember cracks radiating outward across the floor, dark steel gantries, dense orange swarms surging inward.` |
| 2-1 | 永冻科考站 | `Scene: Rime Station — a frozen research outpost, pale desaturated ice-steel platforms with frost crack lines and broken antenna arrays, a thin cyan defense ring holding against orange swarms.` |
| 3-1 | 磁轨长廊 | `Scene: Rail Corridor — long parallel magnetic rail lines crossing the arena, linear EM launch tracks with thin cyan aiming lines, orange swarms funneled along the rails toward the core.` |
| 4-1 | 雷暴电网 | `Scene: Arc Grid — a lightning substation arena, jagged cyan electric arc lines leaping between pylon nodes, storm coils ringing the defense line, orange swarms pressing beneath the grid.` |
| 5-1 | 锻造联合体 | `Scene: Forge Union — massive gear rings and piston hammers encircling the arena, heavy industrial machinery silhouettes in dark steel, molten channels glowing forge-orange, a rising swarm tide.` |
| 6-1 | 生物研究所 | `Scene: Bio Lab — organic hexagonal culture cells and specimen pods surrounding the arena, thin magenta #E8437F bio-veins creeping along the floor, a cyan containment ring barely holding.` |
| 7-1 | 湮灭实验场 | `Scene: Void Range — an annihilation test field, dark void rifts tearing the floor into floating fragments, pale gray-purple debris shards drifting, a cold gold core defended against a dense orange tide.` |
| 8-1 | 主脑·外围 | `Scene: Overseer Outer Ring — a colossal machine ring structure dwarfing the arena, ranked sentinel pylons in dark steel, overwhelming scale, a thin cyan defense line against a vast orange horde.` |
| 9-1 | 主脑·核心 | `Scene: Overseer Core — the final core chamber, the gold core at maximum radiance at the center, the densest converging enemy swarms with magenta #E8437F elite rings, high contrast, imminent collision.` |

## 5. 产出与评审记录（2026-11-10 · 六维自检）

落点 `art/2d/stages/`（1536×1024 生成 → 统一裁掉底部 64px 水印带 → **1536×960 成品**）；原始含水印版备份于 `art/_review/raw_stage_scene_*_v*.png`。

| 文件 | 自检摘要 | 结论 |
|---|---|---|
| `stage_scene_0_1_v1.png` | 三裂放射对称、钢灰六边平台、金核居中；双极守住 | ✅ 通过 |
| `stage_scene_1_1_v1.png` | 熔炉场景完整、橙潮到位；轻微厚涂感/透视感 | 🟡 小改（可接受，接入时看槽位效果） |
| `stage_scene_2_1_v1.png` | 冰钢浅色环带、橙潮偏小但主题可读 | ✅ 通过 |
| `stage_scene_3_1_v1.png` | 径向放射读得出、偏暗但三层仍拉开 | ✅ 通过 |
| `stage_scene_4_1_v1.png` | 青电弧环 + 橙潮围压，全套最强一张 | ✅ 通过 |
| `stage_scene_5_1_v1.png` | 齿轮环 + 橙红机械、金核清晰 | ✅ 通过 |
| `stage_scene_6_1_v1.png` | 六边培养舱 + 品红生物脉络 + 右侧橙潮 | ✅ 通过 |
| `stage_scene_7_1_v1.png` | 裂片地板 + 品红/橙箭头汇聚、虚空感成立 | ✅ 通过 |
| `stage_scene_8_1_v1.png` | 巨环结构可读；橙潮偏弱（小簇火花） | 🟡 小改（可接受） |
| `stage_scene_9_1_v2.png` | v1 橙潮缺失判重出；v2 金核满辉 + 橙色尖刺潮主导 + 品红精英环 | ✅ 通过（v1 已移入 `_review`） |

> 接入引擎前过门禁：① 剪影 10% 缩放可认；② 明度三层（暗紫底→青防线→橙潮）；③ 锚点红线；④ 十张同族。`_v2` 之后的重出沿用同一锚点、只改场景槽位措辞。

## 6. 引擎接入记录（2026-11-10 · 已落地）

**落点：`scripts/ui/stage_select_overlay.gd` —— 裂隙航图节点 = 该关场景图缩略卡。**

| 项 | 实现 |
|---|---|
| 映射表 | `STAGE_SCENE_TEX`（stage_id → 文件名；9-1 指向 `_v2`） |
| 加载 | `_ht_stage()`：判空降级 + 缓存（与 `_ht` 同纪律），路径 `res://art/2d/stages/` |
| 尺寸 | `SCENE_W 88 × SCENE_H 55`（1.6:1 同比例缩自 1536×960）；命中半径 `HIT_R 38 → 46` |
| 三通道状态（§9.2 红线 1） | 颜色 = 卡片描边（金通关 / 章节色可挑战 / 钢灰锁定）；形状 = 卡心符号（勾 / 锁 / 三角，先垫深色底衬）；文字 = 关卡名 chip 不变 |
| 锁定态 | 整卡 modulate 压灰（0.40,0.43,0.50）——贴图自身不透明，无旧路径「减 α 透星点」问题 |
| 悬停 / 当前 | halo 贴图随卡片尺寸放大（half×2+18）；缺贴图回落 draw_arc |
| 降级 | 场景图缺失（headless / 未导入）→ 逐节点回落六边形 + 机械装甲旧路径，逐位一致 |
| 底座 | chapter≥4 的核心底座贴图保持在卡片层之下，未动 |

**验证**：`uistyle` 138/138 PASS · `campaign` 148/148 PASS · `shoot_stage_node_art.gd` 4 场景 node/hit 0 错误并出截图（`art/_review/stage_nodes/`）目检通过。

**遗留（待定）**：左下详情卡尚未放场景大图（节点缩略 88×55 偏小，可考虑详情卡加 200×125 预览位）；`art/manifest.json` 未登记本批（该文件由生成器产出，格式 `indent=1` 无末换行，勿手改）。

## 7. 航图布局二次重排（2026-11-10 · 解锁链路平面嵌入）

场景卡上航图后做了**布局随链路重排**（`stage_select_overlay.gd` `STAGE_ANGLES` v2）：
v1 角度表的 0-1→3-1 长弦从 6-1 卡片底下穿过、与 2-1 的两条子边视觉纠缠（被误读成「6-1 解锁 3-1」）。v2 按解锁 DAG 平面嵌入手工排布：0-1 居顶 → 3-1 径向贴下（0→3 只剩短竖线）；1-1 居左 / 2-1 右下，5-1 夹中间落底部中央；4-1 / 7-1 径向贴各自父节点；6-1 收进 0→2 航线内侧；8-1 左内环，8→9 短斜线进核心。`RING_FRAC` 同步放宽为 **0.42 / 0.31 / 0.20 / 0.10 / 0**（同角度相邻环的卡片+标签占位 ≈97px，环距 118.8px 才留得出 22px 空隙）。
验证：campaign 148/148 PASS · 全量回归 exit 0 · 节点截图 4 场景目检零交叉 / 零穿卡 / 零重叠。
