# 守核 Corebound · 卡面插画风格提案与提示词包 v1

> 状态：🟡 **待拍板**（圣经开放问题 #3 的落地方案）。
> 纪律：锚点确认前**只生成 2 张基准**，确认后才批量。本文档即拍板材料。

---

## 1. 结论（先说拍什么）

**推荐方案：B「工程蓝图扁平插画」**——AI 生成 + 人工精修线稿，不是 3D 转描。

| 方案 | 说明 | 判断 |
|---|---|---|
| A 3D 截图转 2D | 需先建 3D 模型再渲染——项目零 3D 管线，成本倒挂 | ❌ 否 |
| **B 工程蓝图扁平插画** | 与 §5.5「卡牌 = 机械蓝图」同族；厚描边平面几何与现有 `draw_*` 渲染同语言 | ✅ **推荐** |
| C 手绘外包 | 质量上限最高，但 31 张卡成本高、周期长 | 备选（B 失败再走） |

**核心论据**：卡面插画必须和**卡片框架（已落地的蓝图卡面）+ 战场程序化绘制**看起来是同一个游戏。B 方案的风格锚点直接从圣经 §2.2/§5.5 派生，同族性是设计出来的，不是碰运气。

---

## 2. 风格锚点（冻结块 · 生成时整段复制，禁止凭记忆改写）

```
【风格锚点 · COREBOUND CARD ILLUSTRATION · v1 逐字冻结】
Flat vector game card illustration in engineering blueprint style.
Bold thick dark-navy outlines (uniform stroke weight), matte flat colors,
no gradients, no soft shading, no painterly texture.
Geometric construction: subject built from clean polygons, gears, hexagons,
circuit lines and thin cyan technical guide-lines (like engineering drawings).
Background: solid dark night-purple #141726 with faint blueprint grid lines.
Dual accent palette only: glowing lake-cyan #3ED0E8 and forge-orange #FF6B3D,
plus gold #FFC94A for energy cores; all other colors muted steel/desaturated.
Strict frontal view from slightly below (looking up at a fortress tower),
NOT isometric, NOT 3/4 perspective, NOT top-down, flat 2D elevation like an
engineering front-view drawing. Single centered subject, symmetrical
composition, no scene, no environment, no characters, no text, no watermark,
no logo, no glow effects, no luminous halos.
Clean crisp edges, no outer glow, no semi-transparent edges.
```

**锚点来源对照**（每条可溯源）：

| 锚点句 | 来源 |
|---|---|
| 厚描边平面几何 / 无渐变 | art-bible §3.1 视觉语言 |
| 深夜幕紫底 #141726 + 蓝图网格 | §2.2 C_BG + §5.5 蓝图风 |
| 青橙双极 #3ED0E8 / #FF6B3D、辉金 #FFC94A | §2.2 逐字色号 |
| 微仰视单主体居中 | §6.1 仰视径向坐标系的卡面转译 |
| 细青色工程辅助线 | §5.5「细线描边 / 工程图语言」 |
| 无环境无角色 | 卡面 460×460 插画安全区构图约束 |

**禁忌清单**（生成负面词 + 人工评审红线）：
- ❌ 奇幻塔罗 / 扑克牌质感（《小丑牌》区隔，§5.5 明令）
- ❌ 渐变、喷枪柔光、厚涂笔触（破坏与 `draw_*` 同族性）
- ❌ 超过 3 个强调色出现（青/橙/金之外全压灰）
- ❌ 文字、数字、可识别 IP 元素
- ❌ 外发光 / 半透明边缘（抠图破坏，keyout 失败）
- ❌ **等距 / 3/4 俯视视角**（基准评审实锤：湮灭基准出成了 isometric，与箭塔正面仰视不同族——视角必须全项目冻结为「正面微仰视立面图」）
- ❌ 主色喧宾夺主（湮灭基准青色齿轮占比压过紫色主色——每张卡 {主色} 占强调色面积 ≥60%）

---

## 3. 变量槽位表（31 张卡 · 一次只变 `{对象}` 与 `{主色}`）

规格：生成 1024×1024 纯色底 → keyout 透明底 → 集成时缩放进卡框 460×460 安全区（2x 留 920）。

### 3.1 基石包（core · 主体 = 塔，主色 = 钢青系）

| 卡 | {对象}（主体描述） | {主色} |
|---|---|---|
| Arrow 箭塔 | slender arrow tower with a single long ballista bolt on top, triangular stabilizer fins | #3ED0E8 |
| Cannon 炮塔 | squat heavy cannon turret with thick short barrel and octagonal armor plates | #3ED0E8 |
| Frost 霜塔 | frost tower with three curved frost emitter prongs and a hexagonal coolant core | #3ED0E8 |

### 3.2 进阶塔（forge/arc/pierce/hex 包 · 12 张）

| 卡 | {对象} | {主色} |
|---|---|---|
| Lance 长枪 | needle-point lance tower, extremely tall thin spire on a wide tripod base | #3ED0E8 |
| Tesla 特斯拉 | tesla coil tower with stacked torus rings and a crackling sphere on top | #FFC94A |
| Sunder 破甲 | demolition tower with a massive blunt ram head and cracked armor plating | #FF6B3D |
| Hex 咒术 | hex tower with a floating rotating hexagram sigil above an obsidian pedestal | #B45CFF |
| Ember 余烬 | ember brazier tower with a burning core in a cage of iron ribs | #FF6B3D |
| Icicle 冰锥 | icicle tower with downward-pointing crystal spikes under an ice canopy | #3ED0E8 |
| Javelin 标枪 | javelin tower with exposed rack of guided spears, rail-launch gantry | #3ED0E8 |
| Bolt 电弧 | arc pylon with twin parallel electrodes and a lightning gap between them | #FFC94A |
| Maul 战锤 | siege hammer tower with piston-driven hammer head and steam vents | #FF6B3D |
| Rune 符文 | rune tower with carved glowing glyph slabs stacked in offset layers | #B45CFF |
| Oblivion 湮灭 | oblivion obelisk with a void-black core that bends the blueprint grid around it | #B45CFF |
| Void 虚空 | void antenna tower with inverted pyramid emitter and orbiting fragments | #B45CFF |

### 3.3 强化 / 事件卡（强化 = 组件特写，非塔）

| 卡 | {对象} |
|---|---|
| FireUp/FireUp2 燃烧强化 | close-up of a flame amplifier module: orange catalyst coil in a steel bracket |
| FrostUp/FrostUp2 霜强化 | close-up of a coolant injector: cyan cryo flask with frost vents |
| PirUp/PirUp2 穿甲强化 | close-up of an armor-piercing drill bit with spiral flutes |
| ShkUp/ShkUp2 震击强化 | close-up of a shock capacitor bank with dual electrodes |
| SunUp/SunUp2 灼日强化 | close-up of a solar focus lens in a gold gimbal ring |
| HexUp/TrueUp2 等咒术强化 | close-up of a spell-etch clamp holding a glowing rune wafer |
| ScrapUp 废料强化 | close-up of a scrap magnet claw gripping hex nuts and plates |
| RerollD 重掷 | close-up of a carousel dispenser with three card slots mid-rotation |

> 强化卡全部「组件特写 + 钢支架」同构：与塔卡拉开层级，又彼此同族（X3 同构原则的插画版）。

### 3.4 画布与构图段（每张固定，接在锚点后）

```
【画布与构图】1024x1024, subject centered filling 70% of frame,
8% safe margin on all sides, symmetrical, nothing cropped at edges.
【技术约束】solid flat #141726 background with faint grid, no vignette,
no drop shadow on background, crisp vector-like edges, matte finish.
```

### 3.5 完整拼装示例（Arrow 箭塔）

```
Flat vector game card illustration in engineering blueprint style.
Bold thick dark-navy outlines (uniform stroke weight), matte flat colors,
no gradients, no soft shading, no painterly texture.
Geometric construction: subject built from clean polygons, gears, hexagons,
circuit lines and thin cyan technical guide-lines (like engineering drawings).
Background: solid dark night-purple #141726 with faint blueprint grid lines.
Dual accent palette only: glowing lake-cyan #3ED0E8 and forge-orange #FF6B3D,
plus gold #FFC94A for energy cores; all other colors muted steel/desaturated.
Strict frontal view from slightly below (looking up at a fortress tower),
NOT isometric, NOT 3/4 perspective, NOT top-down, flat 2D elevation like an
engineering front-view drawing. Single centered subject, symmetrical
composition, no scene, no environment, no characters, no text, no watermark,
no logo, no glow effects, no luminous halos.
Clean crisp edges, no outer glow, no semi-transparent edges.
Slender arrow tower with a single long ballista bolt on top, triangular
stabilizer fins, main accent color lake-cyan #3ED0E8 on energy parts.
1024x1024, subject centered filling 70% of frame, 8% safe margin on all
sides, symmetrical, nothing cropped at edges.
Solid flat #141726 background with faint grid, no vignette, no drop shadow
on background, crisp vector-like edges, matte finish.
```

---

## 4. 交付管线

```
生成（纯色底 1024²）→ art_asset_tools.py keyout --color "#141726"
  → 透明底 → 人工修边/精修（必须，不谎报可直接商用）
  → 缩放 460×460 入卡框安全区 → contact sheet 全批复核
```

- 🔴 keyout 用 **#141726 底**而非品红：卡面插画自带深底色场景语义，深底 keyout 边缘更干净（主体色与底色明度差大）；
- 每张双版本：`card_<name>_v1.png`（纯色底）+ `card_<name>_v1_t.png`（透明底）；
- 评审按专家六维：剪影（10% 缩略测试）/ 明度三层 / 构图 / 同族一致性 / 技术合规 / 可用性。

## 5. 基准图（2 张，见 art/_review/）

- `bench_card_arrow.png` —— 基础塔代表（基石包，验证「塔类仰视构图 + 青色主色」）
- `bench_card_oblivion.png` —— 高阶塔代表（湮灭包，验证「紫色系 + 虚空核心 + 网格弯曲」是否破坏蓝图感）

**基准评审结论（2026-11-07 · 专家六维）**：

| 基准 | 剪影 | 明度 | 构图 | 一致性 | 技术 | 结论 |
|---|---|---|---|---|---|---|
| `bench_card_arrow.png` | ✓ 10% 可认 | ✓ 三层拉开 | ✓ 居中仰视 | ✓ 与蓝图卡框同族 | ⚠️ 底色偏暖紫（非精确 #141726）、右下 AI 水印需裁 | **小改** |
| `bench_card_oblivion.png` | ✓ | ⚠️ 青色喧宾 | ✗ **等距俯视违反锚点** | ✗ 与箭塔视角不同族 | ✗ 齿轮外发光 | **重做** |

- 箭塔基准证明方案 B 成立：厚描边扁平几何 + 蓝图底与已落地卡框同族性良好；
- 湮灭基准的失败点已全部回写为锚点补强（禁等距 / 禁发光 / 主色占比），重出基准按新锚点执行；
- 水印处理：生成图右下角平台水印，批量时统一裁切或用 revise 参数压制。

**拍板问题（拍完即批量）**：
1. 方案 B 是否通过？（A/C 否决理由见 §1）
2. 箭塔基准的线宽 / 明度方向是否符合预期？确认后按补强锚点重出 2 张基准（湮灭重做 + 箭塔校色）再批量；
3. 强化卡「组件特写」同构方案是否接受？
