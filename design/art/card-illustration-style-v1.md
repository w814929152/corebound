# 守核 Corebound · 卡面插画风格提案与提示词包 v4（中密度）

> ⚪ **状态（2026-11-09 更新）：本文留档，不再是新卡生成依据。**
> 用户已拍板 3/4 视角图生图产线，泛用包 10 张按新标准落地并接入 UI。
> 🔴 **新卡一律执行 `design/art/card-art-generation-standard-v1.md` 现行 v1.2**（3/4 视角 + Cannon 定稿图作风格参考
> + 分层装甲板 + **包色即整机主色调** + 色阶校准 + 连通域抠图）。本文的「正面微仰视立面冻结 / 禁 3/4 / 禁装甲板密细节」条款
> 与新标准冲突，仅作沿革与批次①②记录保留；`card-prompt-bank-v2.json` 仍可用作「对象 / 特征 / 主色」数据源。
>
> 以下为原文状态（留档）：
> 状态：🟡 **待拍板**（圣经开放问题 #3 的落地方案）。
> 纪律：锚点确认前**只生成 2 张基准**，确认后才批量。本文档即拍板材料。
> 🟢 **v4（2026-11-08 · 中密度）**：两次拍板收敛出最终密度——v2 太碎（~15 元素）、v3 太空（3 元素），
> v4 取中间：**大剪影切 2–3 段 + 一个同尺度识别部件 + 一处能量色**，单张 6–8 个形状块。详见 **§2.2（当前生效锚点）**。
> v3 的底线（背景纯色/禁碎件/正面立面/单主色相）全部继承；§2.1 与 §2 保留作沿革记录，**生成时不得使用**。
> 🆕 **v2（2026-11-08）**：卡池已扩至 **8 包 × 10 张 = 80 张建筑卡**（`card_packs.gd` v0.4），
> 本文档 §3 的 31 张旧槽位表**由 `design/art/card-prompt-bank-v1.json` 取代**（80 张 · 与卡池逐字对齐 · 含 {对象}/{主色}，脚本可读）。
> §5 基准图已按 2026-11-07 评审结论重出 v2（箭塔校色 + 湮灭重做）。

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

## 2.1 简化锚点 v3（⚪ 已由 §2.2 v4 取代 · 留档）

> 🔴 2026-11-08 二次拍板：**v3 过简**——画面只剩一个剪影+一块色，卡面显得空、没有机械感，不值得 7 积分/张。
> v3 的「背景纯色、禁碎件、单剪影」保留为**底线**；在此之上按 §2.2 加回**结构化细节**（不是碎件）。

**简化决议**：v1/v2 锚点里的「gears, hexagons, circuit lines, thin cyan technical guide-lines」是画面复杂度的全部来源——
它们在单张图里会繁殖成齿轮群、螺栓排、层叠装甲板、细碎管线，导致：① 画面碎、缩到 460×460 后糊成一团；② 剪影可认度下降；
③ 每张的"细节指纹"都不一样，80 张放一起不像同一套。v3 把这些**全部列入负面词**。

```
【风格锚点 · COREBOUND CARD ILLUSTRATION · v3 极简冻结】
Flat vector game card illustration, extreme geometric minimalism.
Exactly ONE large solid geometric silhouette as the subject, centered,
like a single bold pictogram or a stencil cut-out.
At most ONE secondary feature (one notch, one slit, one cap, one protrusion).
Interior detail limited to two structure lines maximum.
ONLY the outer silhouette carries a bold thick uniform dark-navy outline.
Matte flat colors, three tones maximum: dark navy body, one muted steel
mid-tone, one accent block.
The accent color appears as ONE single solid shape, nowhere else.
Background: solid flat #141726, completely plain — NO grid, NO guide lines,
NO technical lines, NO texture, NO vignette, NO drop shadow.
Strict frontal elevation view, symmetrical. NOT isometric, NOT 3/4
perspective, NOT top-down.
No gradients, no shading, no glow, no halo, no lens flare, no painterly
texture, no stippling, no hatching.
No gear trains, no rivet rows, no layered plating, no circuitry, no
ornaments, no small part clusters, no mechanical greebles.
No text, no numbers, no watermark, no logo, no characters, no scene,
no environment.
1024x1024, the silhouette fills 72% of frame height, 10% safe margin on all
sides, nothing cropped at edges.
```

**v2 → v3 到底砍了什么**（逐条可对照）：

| 维度 | v2（复杂） | v3（简化） | 影响 |
|---|---|---|---|
| 装饰线 | 细青色工程辅助线、蓝图网格 | **全砍**，背景纯色 | 缩略图不再糊 |
| 机械细节 | 齿轮/六角/电路/装甲层叠 | **全砍**，禁止小零件簇 | 剪影可认度 ↑ |
| 内部线 | 不限 | **≤2 条**结构线 | 每个形状都能一笔画出 |
| 描边 | 全物体厚描边 | **仅外轮廓**厚描边 | 更像图标，更同族 |
| 明度 | 三层+强调色散布 | **3 个色阶**，主色只占**一整块** | 单卡信息量降到最低 |
| 主体特征 | 「塔 + 飞檐 + 稳定翼 + 宝石…」 | **主形 + 最多一个特征** | 描述可控、生成稳定 |

**简化主体描述三段式**（写提示词时只填这两格，不许加第三格）：

```
主形：一个什么几何体（矩形/梯形/三角/椭球/方尖碑…）；占位 70%。
一个特征：最能让这张卡被认出的那一个东西（一条横杆 / 一个开口 / 一处断口 / 一顶盖）。
主色块：主色落在哪个单一形状上（一根横杆 / 核心 / 顶盖 / 断口内壁），只此一处。
```

> 判据：**把这张图缩到 32×32，还能认出是哪张卡**——认不出说明特征塞多了。

**v3 新增禁忌**：
- ❌ 任何一个描述里出现 3 个以上部件名（出现即拆，只留最像的那个）
- ❌ 背景网格 / 辅助线 / 任何"工程感纹路"（工程感由**几何形状本身**承担，不靠纹理）
- ❌ 主色出现在两处以上（第二处即违规）

---

## 2.2 中密度锚点 v4（🟢 当前生效 · 生成时整段复制）

**定位**：v2（~15 元素，碎）→ **v4（6–8 元素，中）** ← v3（3 元素，空）。
细节不是靠"多画零件"加回来的，是靠**结构化分层**加回来的——同一个剪影内部切成 2–3 段、加一条分段线、
加一个与主体同尺度的识别部件。这样画面有机械感，但每个形状仍然能一眼读出来。

```
【风格锚点 · COREBOUND CARD ILLUSTRATION · v4 中密度冻结】
Flat vector game card illustration in engineering blueprint style,
medium detail density.
Exactly ONE large geometric silhouette as the subject, centered,
readable at thumbnail size.
The silhouette is divided into two or three stacked structural segments
(base plinth, main body, top cap) separated by one or two horizontal seams.
ONE recognisable structural part at the same scale as the body
(a crossbar, an opening, a barrel, a spire), never a cluster of small parts.
Interior structure lines: four maximum.
Bold thick uniform dark-navy outline on the outer silhouette and along each
structural segment.
Matte flat colors, four tones maximum: dark navy, two muted steel greys,
one accent.
The accent color appears on ONE main energy block plus at most two small
matching accents of the same hue — nowhere else.
Optional: one very faint single-layer blueprint grid on the background,
under 10% contrast, and no other texture.
Background: solid flat #141726.
Strict frontal elevation view, symmetrical. NOT isometric, NOT 3/4
perspective, NOT top-down.
No gradients, no shading, no glow, no halo, no lens flare, no painterly
texture, no stippling, no hatching.
No gear trains, no rivet rows, no layered armour plates, no circuitry,
no ornament, no small mechanical greebles, no text, no numbers,
no watermark, no logo, no characters, no scene, no environment.
1024x1024, the silhouette fills 74% of frame height, 8% safe margin on all
sides, nothing cropped at edges.
```

**中密度的四条加法**（v3 → v4 具体加了什么）：

| 加什么 | 怎么加 | 上限 |
|---|---|---|
| 结构分层 | 剪影内部用**水平分段线**切成 基座 / 主体 / 顶冠 | 2–3 段，缝 ≤2 条 |
| 识别部件 | 一个与主体同尺度的功能件（横杆 / 炮管 / 开口 / 尖刺） | 1 个，不许成簇 |
| 灰阶层次 | 暗蓝主体 + 2 个哑钢灰段（明度差 ≥15%） | 4 色封顶 |
| 能量色 | 1 个主色块 + ≤2 处同色小点缀 | 同色系，不许第二色 |
| 背景 | 可选一层**极淡**网格（对比 <10%） | 1 层，不许辅助线 |

**v4 判据（比 v3 放宽一档，仍防碎）**：
- 缩到 64×64 能读出"这是塔/这是碑/这是炮"；
- 单张图的形状块数 **6–8 个**（v3 是 3，v2 是 15+）；
- 任何一个形状块都能用一句话说出它是什么——说不出就是碎件，删。

**v4 禁忌（继承 v3 底线）**：
- ❌ 齿轮组、螺栓排、层叠装甲板、电路、装饰纹样（碎件四大来源）
- ❌ 渐变 / 厚涂 / 外发光 / 半透明边缘
- ❌ 等距 / 3/4 / 俯视（视角全项目冻结为正面立面）
- ❌ 主色出现第二种色相（深紫卡就只能紫，不许掺青）
- ❌ 背景辅助线 / 工程纹路（只允许 ≤10% 对比的极淡单层网格）

---

## 2.3 正面可见性铁律（批次① 实锤 · 写提示词前必读）

正面立面视角下，**朝向观众的功能件是不可见的**：炮管朝前 = 一个圆，投石臂向前挥 = 一个点。
AI 不会拒绝，它会自行把它压成一条横杆或直接丢掉 —— 批次① 里「炮塔变扁担、投石车变矮墩」都是这个原因，
4 张卡返工两轮才收敛。

**规则：功能件必须能在这个视角的平面内用二维轮廓读出来，不依赖透视。**

| 原始意图 | 正面能读吗 | 改写后的可读语言 |
|---|---|---|
| 炮管朝前伸出 | ✗ 只剩一个圆 | 正面炮盾 + **同心圆炮口**（内圈上主色） |
| 投石臂向前上方抛 | ✗ 只剩一个点 | **中线竖立**的梯形投臂 + 顶端 U 形石篮 |
| 塔顶水平放置的六角盘 | ✗ 看到的是侧棱 | **正对观众**的六角盾板 |
| 横杆两端各挂一个鼓 | 🟡 易读成"眼睛/脸" | 顶部**并排两只正面朝前的圆鼓** |

判据：写出功能件后自问一句「这东西在正视图里长什么样」——答不上来就是在赌。

> 附带教训：`no rounded corners / purely flat` 这类"减法"指令会把主体压扁。
> 正确做法不是删掉体积，而是**换成平面内可读的等价形状**（炮管→炮口）。

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

## 5. 基准图与批次（见 `art/_review/`）

### 批次① 泛用包 core 10 张（2026-11-08 · 🟡 待验收）

产出：`art/2d/cards/card_<name>_v1_t.png`（1024 透明底）+ `card_<name>_v1_460.png`（460 安全区），已登记 `art/manifest.json`（122 项）。

| 卡 | 结果 | 备注 |
|---|---|---|
| Arrow 箭塔 | ✅ | 复用 v4b 基准 |
| Cannon 炮塔 | ✅（2 次返工） | 首版"家电感/俯视"→ 二版压成扁担 → 三版改**正面炮盾+同心圆炮口**成立 |
| Catapult 投石车 | ✅（2 次返工） | 首版 3/4 侧视 → 二版压成矮墩 → 三版改**中线竖立投臂+U形篮**成立 |
| Foundry 熔炉 | ✅ | 一次通过，金色熔池口 |
| Frost 霜塔 | ✅（1 次返工） | 首版过暗、青几乎不可见 → 强化"最亮最饱和的青色槽"后成立 |
| Harrier 鹞式 | 🟡 边缘 | 顶部正面双鼓读作"双联发射器"成立，但整体仍略像机器人胸甲 |
| Kinetic 动能 | ✅ | 钢灰主色，背景偏近黑（生成未守 #141726，keyout 已自适应） |
| Ranger 游侠 | ✅ | 侧视长炮管，识别性强（非严格对称，与锚点有偏差但保留） |
| Scout 斥候 | ✅ | 金色光学横条 |
| Sentry 哨戒 | ✅（2 次返工） | 水平六角盘在正面看不到 → 改**正面六角盾板**成立 |

**通过 9/10，边缘 1 张（Harrier）。**

### 管线验证结论（批次① 的真正目的）

| 环节 | 结论 |
|---|---|
| 批量提示词 | `tools/card_batch_prompt.py` 由 bank 拼装，整批落 `design/art/card-prompts-batch1.json` 可复现 ✓ |
| 底色 | 🔴 **AI 不守 #141726**：同批 10 张背景落在 #1E2128 / #303845 / #060401 等位置。`tools/card_keyout.py` 已改为**自适应采样底色**（边缘中位数 + 90 分位容差） |
| 抠图 | 背景细网格会阻断 flood fill → 先做 5px 中值滤波再连通；背景渐变残留会留淡矩形 → 按距离渐变淡出。现透明率 65–88%，边缘无黑边 |
| 安全区 | 460×460 等比装入 88%，主体不触边 ✓ |
| 卡框集成 | `tools/card_mock_card.py` 模拟合成（插画区垫卡框采样的实色底）——主体比例合适、无网格穿透 |

### v4 中密度基准（2026-11-08 · 按 §2.2 生成 · 🟢 当前）

| 基准 | 评审结论 |
|---|---|
| `bench_card_arrow_v4b.png` | ✅ **通过**——底座/塔身/顶冠三段 + 水平弩臂 + 底部能量口，形状块 ≈8 个；青色仅两处（弩臂 + 能量口）✓ 背景极淡网格（<6% 对比）✓ 正面立面 ✓ 32×32 可认 ✓；遗留：塔身略像图标，弩臂是唯一"箭塔"语义来源，属可接受 |
| `bench_card_oblivion_v4.png` | ✅ **通过**——顶盖/碑身/底座三段 + 方孔 + 底部凹槽，紫色落在方孔内壁 + 凹槽描边 + 基座细线（1 主 + 2 点缀，合规）✓；遗留：背景多了一圈极淡外框线，批量时裁掉或加 `no frame border` |

**v4a 废弃记录**：首版箭塔把弩臂生成成 **X 形斜交叉**，整体读作"国际象棋棋子/灯塔"——语义丢失。
修正方式：描述里把功能件写死为 `strictly HORIZONTAL ballista arm`，并加负面词 `no diagonal arms, no X shape, not a chess piece, not a lighthouse`。
→ **结论：v4 的识别性主要靠"那个功能件"，描述里必须写死方向与形态，否则 AI 会自由发挥成装饰纹样。**（已回写 §2.2 判据）

### 密度三档对照（拍板依据）

| 版本 | 形状块数 | 观感 | 判定 |
|---|---|---|---|
| v2 复杂 | 15+ | 碎，缩略图糊 | ❌ 废弃 |
| v3 极简 | 3 | 空，没有机械感 | ❌ 废弃 |
| **v4 中密度** | **6–8** | 有结构，仍可一眼读 | ✅ **采用** |

### v3 极简基准（2026-11-08 · 已废弃，留档）

| 基准 | 评审结论 |
|---|---|
| `bench_card_arrow_v3.png` | ⚪ 过简——单三角 + 一条横杆，画面空 |
| `bench_card_oblivion_v3.png` | ⚪ 过简——单碑 + 一个方孔，画面空 |

### v2 基准（2026-11-08 · 复杂版，已被 v3 取代，留档）

| 基准 | 评审结论 |
|---|---|
| `bench_card_arrow_v2.png` | ✅ 通过（小改）——细节密度高，缩略图糊 |
| `bench_card_oblivion_v2.png` | 🟡 边缘——顶部微俯视残留 |

**拍板问题（批次① 验收）**：
1. **批次① 9/10 是否通过？** Harrier 那张（顶部正面双鼓、整体略像机器人胸甲）放行还是重出？
2. **继续其余 7 包 70 张**（≈490 积分 + 按批次① 的返工率约 30% 再留 150 积分）？建议按 2 包一批推进，每批出接触表复核后再继续。
3. **卡面接入 Godot**：需要在卡面绘制里按卡 id 挂 `TextureRect`（判空降级回现有程序化卡面），这一步属于代码改动，要不要现在做？

**密度微调旋钮**（不必重跑整套流程，直接说"再密一点/再简一点"即可）：
- 觉得还空 → 加第 3 段分割线 + 第 2 个功能件（形状块 → 10–12）
- 觉得还碎 → 砍到 2 段、功能件只留 1 个（形状块 → 5–6）
- 觉得形状"不像那座塔" → 只改那 1 张的功能件描述（写死方向/形态，见 §5 v4a 教训），不动锚点

---

## 批次② · 单张先行验收（2026-11-08）

**节奏变更**：用户拍板「先出一张」——不再整包并行出图，先出 1 张做同族比对，通过后再放量。

### 锚点补强 v4b（只加约束，不改密度档）

首张 Vanguard 按 v4 锚点生成后**严重漂移**：暗色镂空斜楔、主体几乎无亮灰填充、背景画了网格，
与批次① 的「亮钢灰实心竖塔」完全不同族 → 判废，留档
`art/_review/batch2/raw_Vanguard_v1_rejected.png`（不进 `art/2d/`、不进 manifest）。

补进 `tools/card_batch_prompt.py` ANCHOR 的两条硬约束：

1. `The silhouette MUST be solid-filled: the two LIGHT muted steel greys cover at least 70 percent of its area, with a tall upright tower-like proportion. Never a hollow outline, never a thin frame, never a dark body, never a flat horizontal wedge.`
2. `Background: solid flat #141726 ONLY, absolutely no grid lines, no texture, no frame border, no other pattern.`（原来 "optional single-layer grid under 6% contrast" 是漂移源头）

同步把 `card-prompt-bank-v2.json` 里 Vanguard 的 structure 写死成
「tall upright rectangular tower body on a low stepped base … prow plate mounted on the FRONT」。
`design/art/card-prompts-batch2.json` 已按新锚点重建（10 张）。

### 工具：`card_keyout.py --degrid`

AI 背景网格线会因与底色有色差而被 flood fill 当成前景保留，合成到卡面上是一层游离方格。
新增 `degrid()`：alpha 二值 → 两遍 5×5 开运算（抹掉连到主体的细线）→ 膨胀 1px 作掩膜
→ 与原 alpha 相乘（保住抗锯齿过渡）→ 按清理后 alpha 重算包围盒。
**默认关闭**，只在出现网格残留时显式开启；批次① 产物不受影响。
修正版 Vanguard 因锚点已禁网格、背景干净，正式产物未启用 degrid。

### 修正版验收（待用户拍板）

| 项 | 结论 |
|---|---|
| 同族一致性 | ✅ 亮灰实心、竖向塔体、厚深蓝描边、单一橙色细缝，与批次① 同族 |
| 去底 | ✅ 无网格残留、无黑晕；C 形夹内的暗区是透明，落到暗卡面上读作凹槽 |
| 边缘瑕疵 | 🟡 ① 顶部功能件被画成 C 形夹而非明确斜板；② 底座与主塔之间有一道分离缝。均为可接受级，是否重出由用户定 |

产物：`art/2d/cards/card_vanguard_v1_{t,460}.png`（manifest 163 项）。
中断前并行调用还产出 `Ember` 原图，按旧锚点生成、**未验收未落地**，待确认后按 v4b 重出。
