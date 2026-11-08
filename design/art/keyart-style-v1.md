# 守核 Corebound · 主菜单背景与宣传图风格提案 v1

> 状态：🟢 **已拍板并落地**（2026-11-08 用户确认方案 B / menu 亮度 / 品红精英环保留）。
> 纪律同 `card-illustration-style-v1.md`：锚点确认前**只生成 2 张基准**，确认后才批量。
> 上游依据：`design/art/art-bible.md` v0.2 §2.2 色板 / §2.5 克制底色 / §3 形状语言 / §5.5 蓝图风 / §1.3 风格红线。
> 落点：主菜单背景层（`scripts/ui/main_menu_overlay.gd` 背景绘制的贴图化）+ 商店页宣传主视觉。

---

## 1. 结论（先说拍什么）

**推荐方案：AI 生成「蓝图风景插画」双层交付** —— 背景与宣传图同族不同强度。

| 方案 | 说明 | 判断 |
|---|---|---|
| A 纯程序化（现状） | `main_menu_overlay.gd` 已有零 RNG 程序化背景（核心遗迹 + 导线 + 来袭剪影） | ✅ 保留为**降级路径** |
| **B AI 蓝图风景 + 程序化叠加** | 背景与 key art 用同一冻结锚点生成；主菜单背景**低对比度**（信息层级 §5.2），宣传图**满强度**（青橙双极） | ✅ **推荐** |
| C 手绘厚涂 | 与 `draw_*` 渲染、蓝图卡面均不同族 | ❌ 否（同卡面提案 §1 理由） |

**核心论据**：主菜单是玩家第一屏，背景必须同时做到①与战场/卡面的蓝图语言同族（一眼认出是同一个游戏），②压低对比让 `开始游戏 / 卡组图鉴` 按钮与标题保持第一层级。B 方案把「强度差」设计进锚点（同一张构图，两个曝光档），而不是两张画各画各的。

---

## 2. 风格锚点（冻结块 · 生成时整段复制，禁止凭记忆改写）

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

### 两档曝光（变量 = 只改这一段）

| 用途 | 追加段 | 强度 |
|---|---|---|
| **主菜单背景** `menu` | `Very low contrast, dimmed like an unlit blueprint: all accents at 30-40% brightness, large calm empty areas in the left third and upper third for UI overlay, no focal highlights.` | 30–40% |
| **宣传主视觉** `hero` | `High contrast hero image: vivid accents, the core at maximum radiance, dense converging enemy swarms with magenta #E8437F elite rings, sense of imminent collision.` | 100% |

**禁忌清单**（生成负面词 + 人工评审红线）：
- ❌ 等距 / 3/4 透视（与卡面基准同一条实锤红线）
- ❌ 厚涂 / 渐变物体 / 空气柔光 / 镜头光晕
- ❌ 文字、数字、可识别 IP、人物角色
- ❌ 超过 青/橙/金(+品红精英环) 的强调色
- ❌ 主菜单背景抢 UI（左侧菜单区/顶部标题区不得有高亮点）

---

## 3. 变量槽位表

| 资产 | 尺寸 | 曝光档 | 用途 / 落点 |
|---|---|---|---|
| `keyart_menu_bg_v1` | 1920×1080（生成 16:9 后裁） | `menu` | **现行主菜单背景层**（2026-11-08 晚用户拍板换回）：30-40% 低强度档，左侧文字柱天然干净；TextureRect 判空降级回程序化绘制 |
| `keyart_menu_hero_v1` | 1920×1080 | `hero` + 功能性压暗 | （备用，未删）满强度 hero + 平台式左暗带（0.16 倍恒定压至 0.30W，0.58W 恢复满强度）+ 底部 0.42 倍带，由 `tools/keyart_menu_hero_v1.py` 派生 |
| `keyart_hero_v1` | 3840×2160 目标（先生成 16:9 放大） | `hero` | Steam 胶囊 / 宣传底图（不再直接用于菜单） |
| `keyart_stage_bg_v1` | 1920×1080（hero 派生：模糊 r3 + 降饱和 0.80 + 径向渐晕 0.30→0.16） | `stage` | 选关航图背景层（2026-11-08 追加）：中心金核呼应 4-1 核心节点；`stage_select_overlay.gd` TextureRect 判空降级回纯色底 |
| `keyart_capsule_v1` | 由 hero 裁 1232×456 / 616×353 | `hero` | Steam 胶囊（上线前再裁，本批不产出） |

> 命名按 §10.2 四段式进 `art/2d/ui/`（背景）与 `art/_review/`（基准/评审产物不入引擎）。

## 4. 交付管线

```
生成 16:9（menu / hero 各按锚点+曝光段）→ art/_review/ 基准评审
  → 拍板 → hero 放大重生成 + menu 裁 1920×1080
  → 主菜单背景接入：TextureRect 全屏置底，缺失降级回现有 draw（批次④ 范式）
  → uistyle 断言 + 全量回归 + 实机截图目检
```

- 🔴 主菜单背景接入**零 UI 结构改动**：只替换 `main_menu_overlay.gd` 背景层最底一节，程序化遗迹绘制保留为降级与叠加装饰。
- 可读性门禁：基准图上叠 `开始游戏` 16px 文字实测可读（对比度 ≥ 4.5:1 区域覆盖菜单列）。
- 🆕 2026-11-08 用户拍板：菜单背景升级为 **hero 满强度档 + 平台式压暗**（不再是低强度 menu 档）。
  反复目检结论：① ramp 直起会在按钮柱后漏亮橙塔群 → 平台段恒定 0.16 倍压满整个文字柱（0.30W）再爬升；
  ② 换图后 `--import` 可能不重导（ctex 命中旧 md5）→ 派生后须删 `.godot/imported/<name>*` 强制重导，
  否则实机永远是第一版图。

## 5. 基准图（2 张，见 `art/_review/`）

- `bench_keyart_menu_v1.png` —— `menu` 档：验证压暗后蓝图网格是否尚存、左侧留白是否够 UI。
- `bench_keyart_hero_v1.png` —— `hero` 档：验证满强度下青橙双极是否守住、径向围攻拓扑是否读得出。

**基准评审结论（2026-11-08 · 六维自检）**：

| 基准 | 剪影 | 明度 | 构图 | 一致性 | 技术 | 结论 |
|---|---|---|---|---|---|---|
| `bench_keyart_menu_v1.png` | ✓ 核心可认 | ✓ 已压暗 | ⚠️ **左侧 1/3 未留净**（角落电路装饰偏多，会与菜单列打架） | ✓ 与战场/卡框同族 | ⚠️ 底色偏灰蓝（非 #141726）、右下水印需裁 | **小改** |
| `bench_keyart_hero_v1.png` | ✓ 围攻拓扑读得出 | ✓ 三层拉开（暗紫底→青防线→橙潮+金核） | ✓ 中心放射 | ✓ 扁平无渐变 | ⚠️ 右下水印需裁；品红精英环仅左上一簇（克制，可接受） | **小改** |

- 两档锚点均未被违反（无等距 / 无厚涂 / 无文字）：方案 B 成立；
- 水印处理沿用卡面提案口径：批量时统一裁切或 `revise` 压制；
- menu 档回写补强锚点：`the left third and top band must be empty dark blueprint grid only, all decorative circuit clusters pushed to the right half.`（已并入 §2 追加段执行版）

## 6. 接入记录（已完成 · 2026-11-08）

| 改动 | 落点 | 说明 |
|---|---|---|
| 正式资产 ×2 | `art/2d/ui/keyart_menu_bg_v1.png` / `keyart_hero_v1.png`（1920×1080 PNG-32） | 由 `_review/` 原图经 `tools/keyart_postprocess_v1.py` 处理：水印补丁修补 → 16:9 cover 裁切 → LANCZOS 1.25× 放大；manifest 已登记 |
| hero 返工 ×1 | `_review/`（不入引擎） | 首版 hero 违反锚点（星芒/光晕 + 品红喧宾），补强负面词后重出通过 |
| 主菜单接入 | `scripts/ui/main_menu_overlay.gd` | `_build()` 背景层加 `TextureRect`（`STRETCH_KEEP_ASPECT_COVERED` 全屏置底，`ResourceLoader.exists` 判空）；生效时 `_paint_backdrop` 让位（贴图已含遗迹构图，避免双重绘制），贴图缺失整体降级回程序化遗迹（headless 安全） |
| 可读性自检 | `_review/mock_menu_with_ui.png` | menu 列区域（x 0–640）平均亮度 43.7/255，对正文 #C8CFDA 对比度 ≈ 8.8:1（门禁 ≥4.5）✓ |

**遗留 / 待办**：
- hero 4K（3840×2160）未产出：1536 生成图直接放大 2.5× 会糊，需专业升频工具或分段重绘，上线前处理；
- Steam 胶囊裁切（1232×456 / 616×353）上线前从 hero 裁。

### 6.1 验证记录（2026-11-08 · 本机 Godot 4.7.2.stable 实测）

| 项 | 结果 |
|---|---|
| 资产导入 | `--headless --import` 通过，两张 keyart `.import` 已生成 |
| 全量回归 | 与 HEAD 基线**逐字零扰动**（FAIL 集合 849 项完全一致，汇总各套件 PASS/FAIL 全同）——改动前仓库即存在大量金标本/文案断言失败（CI 本就红），与本次改动无关 |
| uistyle 套件 | 135 过 / 2 失败（失败为卡面文案 ≤9 汉字，改动前已存在）；**【L] 主界面 12 项断言全绿** |
| 实机截图 | `tools/shoot_main_menu.gd`（窗口模式）：`smoke_menu_keyart.png` / `smoke_menu_library.png` —— keyart 生效、标题/按钮可读、图鉴页不抢卡面 |
| 顺手修复 | `tests/run_card_pack_asserts.gd:629` 循环变量 `p` 遮蔽函数级 `var p`（HEAD 即存在的解析错误，导致回归根本无法加载）→ 改名 `pk` |
