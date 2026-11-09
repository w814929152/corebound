# 守核 Corebound · 卡面插画生成标准 v1（3/4 视角图生图产线）

> 状态：🟢 **当前生效 · v1.7**（2026-11-09 立 / 同日八次更新）。适用于 `art/2d/cards/card_*_v1_{t,460}.png` 的全部新增与重绘。当前进度 **80 / 80 张（8 包全部完成）**，见 §7。
> 🆕 **v1.7 变更（批次⑪收官）**：最后一包 `true` 警报红 `#FF2E4E` 按铁律 5 先出 `Oblivion` 试点，四档实测默认 72 / `--bright-pack` 55 / `--mid-pack` 89 / **`--lift-pack` 101**，第三次复用该档；整包 10 张全过检（p50 88–108 / cov 64.3–81.7%）。新增**真红防串色补句** `NOT pink, NOT magenta, NOT crimson`，`sunder`↔`true` 近色对并排复核解除；`Eraser` 因锚点带出青色炮口重出 1 张。**档位参数、门槛、包色一律未动**。详见 §3.1 注、§4.5、§5.11。
> 🆕 **v1.6 变更（批次⑩低明度包色）**：`hex` 深青 `#1A6B7D`（L≈91，8 包里最低明度）按铁律 5 先出 `Hex` 试点，四档实测默认 73 / `--bright-pack` 55 / `--mid-pack` 89 / **`--lift-pack` 101**，确认**复用 v1.5 的 `--lift-pack`**（不新增第五档、不改任何参数）。整包 10 张一次过检（p50 101–138 / cov 88.5–99.6%），并完成 `rime`↔`hex` 近色对并排复核。**门槛、提示词模板、包色一律未动**。详见 §4.5、§5.10。
> 🆕 **v1.5 变更（批次⑨暗板占比高的包色）**：新增第四个整包后处理档位 `--lift-pack`。噬品红 `#E8437F` 用 `--mid-pack` 仍有 4 张 p50 74–79 跌破 80；整包 10 张 × 6 组探测后改 `--white 145 --floor 58`（白场不变、只再抬暗板落点），10 张全过检且描边仍深藏青。**仍只动后处理**：冻结提示词、主色调口径、质检门槛一律不变。详见 §4.4。
> 🆕 **v1.4 变更（批次⑧中明度包色）**：新增第三个整包后处理档位 `--mid-pack`。星紫等 L≈90–140 的主色既不吃 `--bright-pack`（白场 230 反把 p50 压到 61），默认白场 155 又让暗板占比高的卡 p50 跌破 80；改 `--white 145 --floor 42` 后整包全过检。**仍只动后处理**：冻结提示词、主色调口径、质检门槛一律不变。详见 §4.3。
> 🆕 **v1.3 变更（批次⑥亮色相包）**：**只加后处理档位，不动生成口径** —— 青 / 金等高明度主色用 `--bright-pack`（白场 230 + `--bright-threshold 250`），避免白场 155 把整卡顶到过曝；冻结提示词模板、主色调口径、质检门槛一律不变。`core` 蓝钢灰族、`cinder` 熔橙族及后续暗色包继续用白场 155。详见 §4.2。
> 🆕 **v1.2 变更（用户拍板「将不同色板当作主色调重新绘制」）**：包色从「约 20% 装甲板」升级为**整张卡的主色调** —— 机身 60%+ 用包色三阶平涂（中间调主板 / 浅调斜切高光 / 深调暗板），蓝钢灰只留少量结构件；`core` 保留为中性基准族不重出。相应改动：冻结提示词模板、色阶拉伸 `--protect-mode remap`、批量 `--dominant`、质检门槛（p50 80–185 / 包色覆盖率 ≥40%）。
> v1.1 的「20% 装甲板」口径**已被取代**，仅作为演进留档（§5.4、§8）。
> 定稿依据：2026-11-08 用户拍板「用 3/4 视角」并以 Cannon 定稿图为同族样板；泛用包 core 10 张已按本标准全部落地并接入 UI。
> 唯一风格源：`art/_review/batch2/raw_Cannon_flat_v2.png` → 校色后 `raw_Cannon_flat_v2_norm.png`。
> 范围边界：只管**卡面插画**。主视觉（`keyart-style-v1.md`）、地图、HUD 图标各有独立规范，不适用本标准。
>
> 🔴 **与旧文档的关系**：`card-illustration-style-v1.md` 的 v4/v4b 体系是「正面微仰视立面 + 中密度无装甲细节」口径，
> 与本文的「3/4 视角 + 分层装甲板」口径**冲突**。旧文档留档不删（含沿革与批次①②记录），
> 但**新卡一律以本文为准**；其 `card-prompt-bank-v2.json` 仅作为「对象 / 特征 / 主色」的数据源使用，锚点段不再引用。

---

## 0. 一页速查

| 环节 | 固定做法 | 工具 |
|---|---|---|
| 风格 | **Cannon 定稿图作 image1，低保真度图生图** | ImageGen |
| 包色 | **8 包一色**（UI `PACK_COLORS` 为 SSOT），**整机 60%+ 包色三阶平涂** + 同色能量点缀；蓝钢灰仅少量结构件 | `card-prompt-bank-v2.json::pack_palette`（§2.1） |
| 主体 | 换 `{对象}/{特征}/{主色块}`，其余提示词整段冻结 | `design/art/card-prompt-bank-v2.json` |
| 校色 | `--black 35 --white 155 --floor 26 --ceil 235` **＋ `--protect-mode remap`**；**亮色相包（青/金）改 `--white 230 --bright-threshold 250`**；**中明度包（星紫）改 `--white 145 --floor 42`**；**暗板占比高 / 低明度包（噬品红、深青、警报红）改 `--white 145 --floor 58`** | `tools/card_tone_levels.py` |
| 擦边 | 边框 6px 刷成底色 | `tools/card_batch3_process.py` |
| 抠图 | `--connectivity-only` | `tools/card_keyout.py` |
| 自检 | **主色调模式 `--dominant`**：p50 80–185 / p85 ≤215 / alpha p10 ≥250 / 水印区 0 / **包色覆盖率 ≥40%**（旧蓝钢灰族 p50 90–160 / cov ≥2%）；按包色明度四选一：默认 / `--bright-pack` / `--mid-pack` / `--lift-pack`（互斥） | `tools/card_batch3_process.py --batch <批次> --dominant [--bright-pack \| --mid-pack \| --lift-pack]` |
| 复核 | 卡框合成 + 接触表人工过眼 | `card_mock_card.py` / `card_contact_sheet.py` |
| 落盘 | 覆盖同名 `card_<name>_v1{_t,_460}.png`，manifest / Godot 引用免改 | — |

---

## 1. 五条铁律（违反即返工）

1. **风格来自参考图，不来自文字。** 纯文字提示词哪怕逐字复制风格锚点，出图也会变成细线条极简等距风（批次③首轮 Foundry / Arrow / Frost 实测判废）。原因是 Cannon 的风格语言来自用户手绘素描图生图，并没有被文字完整描述出来。
2. **所有卡共用同一张风格参考图。** 禁止拿上一张新生成卡当 `image1` —— 风格误差会逐张累积漂移。参考图永远是 `raw_Cannon_flat_v2.png`。
3. **视角冻结为 3/4，主体居中。** 单主体、无场景，占画幅高度 74%，四周 8% 安全边距，任何部件不得裁切。
4. **文件名恒定。** 重绘时覆盖同名资产、新卡则按同一命名规则首次创建；两者都不需要改 `art/manifest.json` 或任何 `.gd` / `.tscn` 引用。
5. **先出 1 张同族比对，通过后再放量。** 沿用批次②节奏，禁止整包盲并发出图。

---

## 2. 风格基准（生成与评审共用的判据）

| 维度 | 标准 |
|---|---|
| 描边 | 粗、均匀、深藏青；每个形状块都要有描边，不是只有外轮廓（**换主色调后描边不变**） |
| 机身 | **包色三阶分层装甲板**（中间调主板 / 浅调斜切高光 / 深调暗板）+ 面板缝 + 铆钉 + 斜切高光；哑光平涂；蓝钢灰只留少量结构件。`core` 中性基准族整族仍为蓝钢灰 |
| 点缀 | **单一主色相**：包色占可见机身 60%+，1 处高饱和同色能量点缀；禁止第二色相 |
| 配色 | 深夜幕紫底 `#141726`；主色按 `card-prompt-bank-v2.json` 的 `pack_palette` 取（熔橙 `#FF6B3D` / 耀青 `#3ED0E8` / 辉金 `#FFC94A` 等），色名词见 `hue_word` / `shadow_word` |
| 视角 | 3/4 玩具模型感，可见正面与一个侧面；不做严格左右对称 |
| 背景 | 纯色、无网格、无纹理、无地面线、无暗角、无投影 |

**负面清单**（写进提示词 + 人工评审红线）：

- ❌ 渐变 / 喷枪柔光 / 厚涂笔触 / 外发光 / 半透明边缘
- ❌ 蓝图网格、辅助线、工程尺寸标注（会破坏 flood fill 抠图）
- ❌ 文字、数字、水印、Logo、角色、场景、地面
- ❌ **脸化**：两个圆件并排容易被读成眼睛（Harrier 待复核项）；出现「像脸」即重出
- ❌ 细线极简等距风（风格漂移的典型症状）
- ❌ 超过一种强调色相；**蓝钢灰重新变回机身主色**（v1.2 典型的风格回退）
- ❌ 包色只做成一块装甲板 / 一条能量缝（v1.1 口径已废）

---

## 2.1 包色 SSOT（2026-11-09 · 8 包一色）

**问题诊断**：旧 `accent_by_pack` 与 UI 图鉴分组色 `ui_style.PACK_COLORS` 两套并存、7/8 包对不上；`core` 与 `rime` 撞同一个青色，`hex` 与 `true` 同为紫系；逐卡 `accent` 还混用 2–4 种色。更致命的是包色只落在**一处小点缀**（≈2% 面积），十张卡摆一起几乎全是蓝钢灰 —— 换包根本看不出来。

**v1.1 → v1.2**：加了约 20% 包色装甲板后，实测覆盖率仍只有 7.4–23.1%，机身主体依旧是蓝钢灰；用户据此拍板「把不同色板当作主色调」，改为整机换色（实测 65–97%）。三代并排见 `art/_review/batch5/compare_dominant_color.png`。

**决议**：以**已在 UI 落地**的 `scripts/ui/ui_style.gd::PACK_COLORS` 为唯一真源（8 色全部取自 `art-bible.md` §2.2 已登记色），卡面插画与图鉴分组标题条共用同一套编码。不发明新色、不改 UI。

| 包 | 名称 | 新包色 | 色名 | 旧 `accent_by_pack`（废弃） |
|---|---|---|---|---|
| `core` | 泛用 | `#9AA5B1` | neutral steel grey 钢灰 | `#3ED0E8`（与 rime 撞色） |
| `cinder` | 熔炉 | `#FF6B3D` | molten forge-orange 熔橙 | `#FF6B3D`（唯一原本就一致的） |
| `rime` | 霜序 | `#3ED0E8` | bright lake-cyan 耀青 | `#3ED0E8`（与 core 撞色） |
| `pierce` | 穿甲 | `#FFC94A` | forge-gold 辉金 | `#3EA8FF` |
| `arc` | 电弧 | `#7A5CFF` | star-violet 星紫 | `#FFC94A` |
| `sunder` | 破甲 | `#E8437F` | magenta-crimson 噬品红 | `#9AA5B1` |
| `hex` | 咒术 | `#1A6B7D` | deep teal 深青 | `#B45CFF`（与 true 同为紫系） |
| `true` | 湮灭 | `#FF2E4E` | alert red 警报红 | `#7A5CFF` |

**四条硬规则**：

1. **包内 10 张同色，禁止逐卡 override。** `card-prompt-bank-v2.json` 的 `accent_by_pack` / `pack_palette` / `cards[*].accent` 三处必须一致；镜像常量在 `tools/build_card_prompt_bank_v2.py::PACK_ACCENT`（🔴 勿运行该脚本重建，会把 80 张手工补强的 `structure` 回退，见文件头警告）。
2. **包色就是整张卡的主色调（v1.2）。** 机身 **60%+ 可见面积**用包色的**三阶平涂**：中间调主板 / 浅调斜切高光 / 深调暗板，三阶**同一色相**（`hue_word` / `shadow_word`，见 `pack_palette`）；只允许少量结构件保留中性蓝钢灰，粗深藏青描边一律不变。外加 1 处高饱和同色能量点缀。**禁止第二色相、禁止渐变**。`20% 装甲板` 是 v1.1 的过渡口径，已废。
3. **`core` 是中性基准族，不重出。** 它的包色钢灰与现有 10 张卡的蓝钢灰机身几乎一致，整机换色不会带来区分度；`core` 保持蓝钢灰作为全组视觉基准。其余各包一律按 v1.2 主色调出图。若日后要求全组严格统一，再单独重出 core 10 张。
4. **同族性靠结构，不靠颜色。** 换主色调后仍需保留粗描边、分层装甲板、面板缝、铆钉、斜切高光、3/4 玩具模型构图 —— 这六项是「看着像同一套卡」的判据；颜色只负责区分卡包。

**近色 / 暗色处理**：`hex` 深青 `#1A6B7D` 明度低、整机铺开会发闷，主色要提亮到中明度可读、能量点缀用原色高饱和；`sunder` 品红与 `true` 警报红、`rime` 耀青与 `hex` 深青属近色系，靠**剪影 + 明度差**再拉开，评审时按缩略图并排复核。

---

## 3. 生成参数（固定值，不许逐张微调）

| 参数 | 值 | 理由 |
|---|---|---|
| `image1` | `art/_review/batch2/raw_Cannon_flat_v2.png` | 唯一风格源 |
| `input_fidelity` | `low` | 只传风格、不传造型；`high` 会把炮塔造型带进新卡 |
| `size` | `1024x1024` | 下游 `_460.png` 安全区的输入规格 |
| `background` | `opaque` | 纯色底方便连通域抠图 |
| `style` | `flat vector illustration` | — |
| `footnote` | `""`（空） | 减少题注；平台仍可能加右下角「AI生成 WORKBUDDY>」水印，见 §4.1 |
| `output_dir` | `art/_review/batch<N>/` | 原图留档，不直接进 `art/2d/` |
| 成本 | 约 5–10 积分 / 张 | 放量前先报总量 |

### 3.1 冻结提示词模板（整段复制，只替换 `{}` 槽位）

```
Keep the EXACT same structural art style as the reference image: flat vector game
card illustration in engineering blueprint style, same thick dark-navy outline weight
on every shape, same layered armour plating with panel seams, rivets and bevelled
edge highlights, same matte flat three-tone shading treatment, same plain dark
background. But REPLACE the subject with a completely different tower: {SUBJECT},
with layered armour plating, panel seams, rivets and two small round ports on the
base. {FEATURE}. COLOUR RULE - the ENTIRE body is dominated by the pack color
{PACK_COLOR_NAME} {PACK_HEX}: about 60 percent or more of the visible body surface is
painted in this hue, using three flat tonal steps of the SAME hue (a mid-tone {HUE}
main plate, a lighter {HUE} bevel highlight, a darker {SHADOW_HUE} shadow plate),
no gradients. Keep only a few small structural parts in neutral blue-grey steel;
the thick dark-navy outlines stay unchanged. Accent color {PACK_COLOR_NAME}
{PACK_HEX}: {ACCENT_BLOCK}, plus one small round {HUE} port on the base face, one
small high-saturation detail of the same hue. Blue-grey must NOT be the main body
color. No second colour hue. Same three-quarter view, subject centered, fills 74%
of frame height with 8% safe margin, nothing cropped. No gradients, no soft shading,
no glow, no blueprint grid, no face-like layout, no characters, no scene, no ground
line, no text, no watermark, no logo.
```

> 🔴 与 v1.1 模板的两处关键差别：① 风格锚点句删掉 `same blue-grey steel panels` / `same muted desaturated grey palette`，改成只锁**结构**（描边 / 装甲板 / 三阶平涂），否则参考图的蓝钢灰会把主色调拉回去；② 新增 `COLOUR RULE` 整段 + `Blue-grey must NOT be the main body color` 反向否定。
> 青色系包（`rime` / `hex`）与蓝钢灰色相接近，需在 COLOUR RULE 里补一句 `clearly brighter and more saturated than neutral blue-grey steel`（批次⑤ Glacier 实测有效）；**低明度包（`hex` / `true`）再加一句 `Lift the {hue} main plate to a readable mid-tone brightness`**（批次⑩ `Hex` / 批次⑪ `Oblivion` 试点实测有效，见 §4.5）；**真红包再加防串色句 `Keep the red a pure signal red, NOT pink, NOT magenta, NOT crimson`**（批次⑪ 实测有效，见 §5.11）。以上均只改 COLOUR RULE 段内的描述句，模板其余部分冻结。

槽位取值来自 `design/art/card-prompt-bank-v2.json`：

- `{SUBJECT}` / `{FEATURE}` / `{ACCENT_BLOCK}` ← `cards[Name]` 的 `structure` / `feature` / `accent_block`；
- `{PACK_HEX}` / `{PACK_COLOR_NAME}` / `{HUE}` / `{SHADOW_HUE}` ← 该包在 `pack_palette` 里的 `hex` / `name` / `hue_word` / `shadow_word`（v2.2 新增后两个字段）。

| 包 | `hue_word` | `shadow_word` |
|---|---|---|
| `core` | neutral grey | charcoal grey |
| `cinder` | orange | burnt-orange |
| `rime` | cyan | deep teal |
| `pierce` | gold | burnt amber |
| `arc` | violet | deep indigo |
| `sunder` | magenta | deep wine |
| `hex` | teal | deep ocean teal |
| `true` | red | deep crimson |

同一包内 10 张的四个颜色槽**逐字相同**，只有主体与功能件变化 —— 这是「靠颜色认卡包」能成立的前提。

> 🔴 **必须做 3/4 转译**：提示词库是 v4 **正面立面**口径，字段里有 `perfectly level` / `on the FRONT` / `facing the viewer` 等限定，直接套用会把 3/4 视角拉回正面。按下表改写后再填入：

| 库里的正面口径 | 3/4 改写 |
|---|---|
| `perfectly level` / `strictly horizontal` | 允许轻微透视倾斜，保留「一根横杆」的识别性即可 |
| `on the FRONT` / `facing the viewer` | `on the front-left face visible in three-quarter view` |
| `perfectly symmetrical` | 主体居中，两侧撑脚/装甲允许透视不等宽 |
| 炮管朝前 → 同心圆炮口（§2.3 正面铁律） | 3/4 视角下**直接画侧向炮管**，能读出长度与炮口 |
| 竖立投臂 / 正对观众六角盾（正面替代形状） | 用物件本来形态即可，不必换等价平面形状 |

`card-prompt-bank-v2.json` 的 `anchor_ref` 仍指向旧文档 v4 锚点，**不要按它拼提示词**；只取对象与主色数据。

---

## 4. 后处理管线（固定四步，顺序不可换）

```bash
# 在 corebound/ 根目录执行（Python 3.9 + Pillow）
# 1) 保色相色阶拉伸：把 AI 出图明度拉进卡组基准
#    🔴 v1.2 主色调批次必须加 --protect-mode remap（见 §4.1）
#    🔴 v1.3 亮色相包（青/金）改 --white 230 --bright-threshold 250（见 §4.2）
#    🔴 v1.4 中明度包（星紫等）改 --white 145 --floor 42（见 §4.3）
#    🔴 v1.5 暗板占比高的中明度包（噬品红）改 --white 145 --floor 58（见 §4.4）
py -3.9 tools/card_tone_levels.py \
  --src art/_review/batch5/raw_Vanguard.png \
  --out art/_review/batch5/raw_Vanguard_norm.png \
  --black 35 --white 155 --floor 26 --ceil 235 --protect-mode remap

# 2) 擦除边框 6px 残留渐变（走批量脚本时自动做，可跳过）
py -3.9 - <<'PY'
from PIL import Image
p = "art/_review/batch5/raw_Vanguard_norm.png"
im = Image.open(p).convert("RGB")
px = im.load(); w, h = im.size; bg = px[2, 2]
for y in range(h):
    for x in range(w):
        if x < 6 or y < 6 or x >= w - 6 or y >= h - 6:
            px[x, y] = bg
im.save(p)
PY

# 3) 连通域抠图 → 一次性产出 _t.png / _460.png
py -3.9 tools/card_keyout.py \
  --src art/_review/batch5/raw_Vanguard_norm.png \
  --out art/2d/cards/card_vanguard_v1.png --connectivity-only

# 4) 卡框合成 + 全批接触表
py -3.9 tools/card_mock_card.py --card art/2d/cards/card_vanguard_v1_460.png \
  --out art/_review/batch5/mock_vanguard.png
py -3.9 tools/card_contact_sheet.py --dir art/_review/batch5 \
  --out art/_review/batch5/contact.png --cell 300 --cols 5
```

**批量一键**（校色 → 擦边 → 抠图 → 指标自检 + 包色覆盖率 → 落盘）：

```bash
py -3.9 tools/card_batch3_process.py --batch batch5 --dominant    # v1.2 主色调批次（橙 / 默认档）
py -3.9 tools/card_batch3_process.py --batch batch6 --dominant --bright-pack  # v1.3 亮色相包（青 / 金）
py -3.9 tools/card_batch3_process.py --batch batch8 --dominant --mid-pack     # v1.4 中明度包色（星紫）
py -3.9 tools/card_batch3_process.py --batch batch9 --dominant --lift-pack    # v1.5 高抬暗板（噬品红）
py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）
py -3.9 tools/card_batch3_process.py --batch batch11 --dominant --lift-pack   # v1.7 真红收官（第三次复用）
py -3.9 tools/card_batch3_process.py --batch batch4                # v1.1 旧口径 / core 蓝钢灰族
py -3.9 tools/card_batch3_process.py --batch batch5 Ember Blaze --dominant  # 指定若干张
py -3.9 tools/card_batch3_process.py                               # 默认 batch3（向后兼容）
```

> **通用批次版（2026-11-09）**：自动扫 `raw_*.png`，排除 `_norm` / `_lit` / `_rejected` / `_prepack` 等中间产物；
> `prev_*.png` 留档图不以 `raw_` 开头，天然不入选。
> **`--dominant`（v1.2）** 做三件事：① 色阶拉伸透传 `--protect-mode remap`；② 包色覆盖率门槛 2% → **40%**；③ p50 门槛 90–160 → **80–185**。缺省不带该参数时行为与 v1.1 完全一致，旧批次可安全复跑。

### 4.1 每一步为什么必须做

| 步骤 | 不做的后果（实测） |
|---|---|
| 色阶拉伸 | AI 出图主体普遍偏暗：Cannon 原始 p50=85，卡组基准为 96–149；合成进深色卡底后内部结构线糊成一团。`--white 125` 会过曝（p85=228、机身发白），**155 是收敛值** |
| **`--protect-mode remap`**（v1.2 主色调批次） | `card_tone_levels.py` 旧逻辑把「高饱和橙/青」当**小面积能量点缀**跳过亮度重映射、只 ×1.06。整机换色后 70%+ 像素命中该条件 → 明度完全没被拉进基准：批次⑤首跑 p50 只有 72–122（Vanguard 72 / Maul 84），4 张报警。`remap` 只保护「极亮」高饱和像素（L>170，即能量点缀），其余参与重映射，p50 回到 83–175、卡框复核暗部细节仍清晰。**蓝钢灰族继续用默认 `skip`，两种模式互不干扰** |
| 擦边 6px | 图像边框有极淡渐变残留，flood fill 的 trim box 被撑到整张 1024²，主体在 460 安全区里缩小一圈 |
| `--connectivity-only` | 深藏青描边与深夜幕紫底明度太接近，颜色距离法把描边削成半透明（实测 alpha≈80 / 202，白底预览里描边发白、像浅色线）。连通域模式只按「背景是否可达」判定，描边保持实心；代价是主体内部封闭暗区保留为不透明，在暗卡面上读作阴影，可接受 |
| 水印区补丁 | 平台水印固定落在右下 `x≥74%, y≥90%`，`card_keyout.py` 的 `patch_watermark()` 会自动用底色覆盖该矩形；**因此构图必须保证主体不进入该区域**，否则会被抹掉一块 |

> 背景色**不要写死**：`sample_bg()` 从图像四边取中位数自适应采样。AI 并不遵守提示词里的 `#141726`，实测同批出图底部分别落在 `#1E2229` / `#313A46` / `#060402`。

### 4.2 亮色相包档位 `--bright-pack`（v1.3 · 2026-11-09）

**问题**：批次⑥ 首跑按 v1.2 冻结参数处理 `rime` 耀青 / `pierce` 辉金，11 张里 5 张 p50 偏离（最高 198）、2 张 p85 过曝（最高 227），卡框里青色发荧光、内部面板层次被高光吃掉。原因是连锁的两条：

1. `--white 155` 意味着 **L≥155 的像素全部 clamp 到 ceil 235**。橙 / 蓝钢灰机身大多在 L<155，映射是「提亮暗部」；但耀青 `#3ED0E8` 本身 L≈179、辉金 `#FFC94A` L≈202，主板整片撞上白场饱和。
2. `--protect-mode remap` 只保护 **L>170 的高饱和像素**（原意是保住小面积能量点缀）；整机换色后青色主板几乎全 >170，等于整卡只 ×1.06、完全没被重映射。

**决议**：新增 `--bright-pack` 整包开关（**不是逐张微调**），与 `--dominant` 同用，内部等价于 `--white 230 --bright-threshold 250`：

- 白场 230 → 只有 L≥230 才触顶，主板走温和等比映射，暗部层次保留；
- 阈值 250 → 基本取消高亮保护，所有像素参与保色相等比缩放，不褪色、不偏灰；
- `--black 35 / --floor 26 / --ceil 235 / --protect-mode remap` 均不变。

参数探测（4 张代表图 × 5 组）实测：白场 155 → p50 167–198 / p85 205–227；**230 → p50 113–165 / p85 165–205**；250 → 105–151 / 152–182；280 → 96–136 / 137–163。取 230 是「达标且保住耀青辨识度」的折中，250 以上会把青色压暗到接近 core 蓝钢灰。

**适用范围**：`rime`、`pierce` 等高明度包（批次⑥ 11 张 + 批次⑦ 10 张，**共 21 张验证通过**）。**不追溯重出** `core`（蓝钢灰，中性基准族）与 `cinder`（熔橙，已按白场 155 达标）；同一包内必须整包统一档位 —— 批次⑥ 因此把批次⑤ 的 `Glacier` 沿用原图按新档重出，避免包内明度两套；批次⑦ 同理把批次⑥ 的 `Martyr` 随包重跑（数值不变）。**中明度包不要用这个档位**，批次⑧ 实测星紫走 `--bright-pack` 会把 p50 压到 61，见 §4.3。

### 4.3 中明度包色档位 `--mid-pack`（v1.4 · 2026-11-09）

**问题**：批次⑧ 按铁律 5 先出 `Thunder` 试点。星紫 `#7A5CFF` 的 L≈110 属中等明度，两个既有档位都不适用：

- 套 `--bright-pack`（白场 230）：试点 p50 反而掉到 **61**、p85 只有 113 —— 白场放大等于温和压暗，方向完全反了；
- 套默认白场 155：试点 p50=83 / p85=167 / cov 72.0% 达标，但**只余 3 点裕度**。整包 10 张放量后 `Coil` 73 / `Overcharge` 71 / `Storm` 75 / `Thunderhead` 75 共 **4 张 p50 跌破 80**。

根因不是过曝，而是紫色三阶里的 `deep indigo` 暗板 + 深藏青描边占了一半以上像素；`card_tone_levels.py` 的高饱和保护判据（`(g-r>60 & b-r>60)` 或 `(r-g>60 & r-b>60)`）**对紫色完全不命中**，所有像素都参与映射，暗板被压到 L≈45。

**决议**：新增 `--mid-pack` 整包开关（与 `--bright-pack` / `--lift-pack` 三档互斥，均需配 `--dominant`），内部等价于 `--white 145 --floor 42`：

- 小幅压白场 155→145，抬高映射斜率，把中间调紫板提亮；
- **抬 `--floor` 26→42 是关键**：直接抬高暗板落点而不把高光顶到 ceil 235，包色饱和度几乎不掉（一味压白场到 135 会让 cov 从 72% 掉到 55%）；
- `--black 35 / --ceil 235 / --protect-mode remap` 均不变；描边仍保持深藏青，三档并排见 `art/_review/batch8/compare_tone_batch8.png`。

参数探测（整包 10 张 × 8 组）：

| 档位（白场 / floor） | p50 范围 | p85 最大 | cov 范围 | 未过检 |
|---|---|---|---|---|
| 默认 155 / 26 | 71–135 | 167 | 46.4–74.7% | **4** |
| 145 / 26 | 74–144 | 178 | 46.0–73.1% | **4** |
| 140 / 26 | 77–150 | 184 | 45.9–72.0% | 2 |
| 135 / 26 | 79–155 | 191 | 45.5–71.0% | 1 |
| **145 / 42** | **87–151** | **181** | **45.6–71.3%** | **0** |
| 140 / 40 | 87–155 | 187 | 45.3–70.6% | 0 |
| 135 / 36 | 87–159 | 193 | 45.2–70.2% | 0 |

取 **145 / floor 42**：p50 下限 87（余量 7），p85 与 cov 损失最小。**门槛未放宽、未逐张微调、未重出任何 AI 图**（从 `raw_*.png` 幂等重跑即可）。

**适用范围**：`arc` 星紫已验证 10 张。`sunder` 噬品红试点证实**不能用同档**（整包 4 张跌破 80，见 §4.4）；`true` 警报红 / `hex` 深青仍须按铁律 5 各出 1 张试点测 p50 再定，`hex` 低饱和暗色尤其要复核是否需单独提亮。`core` / `cinder` 继续默认档，`rime` / `pierce` 继续 `--bright-pack`，互不干扰。

### 4.4 高抬暗板档位 `--lift-pack`（v1.5 · 2026-11-09）

**问题**：批次⑨ 按铁律 5 先出 `Sunder` 试点。噬品红 `#E8437F` 的 L≈150，试点单张在 `--mid-pack` 下 p50=91 / p85=138 / cov 69.6% 达标，但整包 10 张放量后 `Drummer` 74 / `Shatter` 77 / `Rend` 78 / `Breaker` 79 共 **4 张跌破 80**。根因与星紫同源但更重：三阶里的 `deep wine` 暗板 + 深藏青描边占比更高，且品红同样不命中 `card_tone_levels.py` 的高饱和保护判据，暗板被压得更低。

**决议**：新增 `--lift-pack` 整包开关（与 `--bright-pack` / `--mid-pack` **三者互斥**，均需配 `--dominant`），内部等价于 `--white 145 --floor 58`：

- **白场保持 145 不变**，只把 `--floor` 从 42 再抬到 58，暗板落点继续上移；
- `--black 35 / --ceil 235 / --protect-mode remap` 均不变；`--bright-threshold` 不启用；
- floor 58 后人工四档并排复核：深藏青描边依旧清晰、品红鲜明、暗板层次未被吃掉（见 `art/_review/batch9/compare_tone_lift_batch9.png`）。

参数探测（整包 10 张 × 6 组）：

| 档位（白场 / floor） | p50 范围 | p85 最大 | cov 范围 | 未过检 |
|---|---|---|---|---|
| 145 / 42（`--mid-pack`） | 74–119 | 195 | 41.9–69.6% | **4** |
| 140 / 48 | 80–125 | 202 | 39.8–69.5% | 2（Drummer 80 贴线、Ruin cov 39.8） |
| 140 / 55 | 86–128 | 203 | 39.6–69.4% | 1（Ruin cov） |
| 135 / 52 | 85–130 | 210 | 39.3–69.3% | 1（Ruin cov） |
| **145 / 58** | **87–127** | **197** | **41.6–69.5%** | **0** |
| 130 / 50 | 85–132 | 216 | 39.4–69.2% | 1（Ruin cov + p85） |

关键结论：**压白场是错的方向** —— 135–140 那几组虽把 p50 抬起来，却把 `Ruin` 的包色覆盖率压破 40%、p85 顶到 210–216；只有「白场不动 + 继续抬 floor」能让 10 张同时达标。取 145 / 58 后门槛未放宽、未逐张微调、未重出任何 AI 图（从 `raw_*.png` 幂等重跑）。

**适用范围**：`sunder` 噬品红已验证 10 张；`hex` 深青（批次⑩）与 `true` 警报红（批次⑪）均按同一方法验证并复用本档（见 §4.5 / §5.11），至此 8 包全部定档完毕。`core` / `cinder` 默认档、`rime` / `pierce` `--bright-pack`、`arc` `--mid-pack` 互不干扰。

### 4.5 低明度包色复用 `--lift-pack`（v1.6 · 批次⑩）

**问题**：`hex` 深青 `#1A6B7D` 的 L≈91 是 8 包里最低，§2.1 早已预警「整机铺开会发闷」。按铁律 5 先出 `Hex` 试点，四档逐档实测：

| 档位（白场 / floor） | p50 | p85 | cov | 判定 |
|---|---|---|---|---|
| 默认 155 / 26 | 73 | 144 | 97.1% | ✗ 偏离 |
| `--bright-pack` 230 / 26 | 55 | 99 | 97.6% | ✗ 偏离（方向相反，见 §4.3） |
| `--mid-pack` 145 / 42 | 89 | 161 | 97.9% | ✓ 但仅余 9 点裕度 |
| **`--lift-pack` 145 / 58** | **101** | **167** | **98.2%** | **✓ 采用** |

**决议**：不新增第五档、不逐卡微调，直接复用 `--lift-pack`。深青与噬品红明度差约 60，但根因相同（三阶里的 `deep ocean teal` 暗板 + 深藏青描边占比高），floor 58 已足够；整包 10 张放量后 p50 101–138，最低值仍高出下界 21 点，档位有余量。四档并排见 `art/_review/batch10/compare_tone_batch10.png`：lift 档描边仍深藏青、暗板层次未糊、无发灰或过曝。

**适用范围更新（收官）**：`--lift-pack` 已在 `sunder` + `hex` + `true` 共 30 张上验证通过（批次⑪ `Oblivion` 四档试点 72 / 55 / 89 / 101，整包 p50 88–108）；`--mid-pack` 仅 `arc`、`--bright-pack` 仅 `rime` / `pierce`、默认档仅 `core` / `cinder`。8 包全部完成，无剩余待定档包。

---

## 5. 质检标准（自动 + 人工，两道都过才算交付）

### 5.1 量化门槛

| 指标 | 蓝钢灰族（默认） | **主色调族（`--dominant`）** | 说明 |
|---|---|---|---|
| 主体明度 p50 | **90–160**（目标 96–149） | **80–185** | 主色调靠**色相**与深底拉开对比，明度分布天然更宽；实测 83（Vanguard 熔橙）/ 175（Glacier 耀青）卡框复核均清晰，不必强行拉齐 |
| 主体明度 p85 | **≤215** | **≤215** | 防过曝；🟡 Sentry 例外（235，主色即亮抛光钢 `#C8D2DC`，刻意） |
| alpha p10 | **≥250**（理想全 255） | 同左 | 描边实心，不发虚、不发白 |
| 水印区残留 | **0** | 同左 | 扫 `x≥70% & y≥90%` 区 `alpha>100` 的像素数 |
| **包色覆盖率 cov** | **≥2%**（小点缀口径） | **≥40%** | 不透明像素中「色相接近包色且 S≥0.25」占比；中性包色（钢灰）免检。批次⑤实测 65.4–96.5% |
| 安全区 / 尺寸 | 无裁切、四周留白均匀；`_t` 1024²、`_460` 460² RGBA | 同左 | 由 `card_keyout.py` 保证 |
| **包色一致性** | 包内 10 张同色 | 同左 + **整机换色后仍是同一套卡** | 见 §2.1 硬规则 4：靠描边 / 装甲板 / 面板缝 / 铆钉 / 斜切高光 / 构图判同族，人工接触表复核 |

> 🔴 **v1.3 → v1.7 的门槛始终没有放宽**：亮色相包走 `--bright-pack`、中明度 / 低明度包走 `--mid-pack` / `--lift-pack` 后，仍按「主色调族」这一列（p50 80–185 / p85 ≤215 / cov ≥40%）验收。批次⑥ 11 张、批次⑧ 10 张、批次⑨ 10 张、批次⑩ 10 张、批次⑪ 10 张全部达标，靠的都是修后处理（或复用已验证档位）而不是调门槛。禁止为了过检改阈值、禁止逐张单独换档。

### 5.2 人工评审（接触表过眼）

缩到 64×64 能读出「这是塔 / 这是炮 / 这是熔炉」→ 十张摆一起像同一套（描边粗细、面板密度、明度、底色一致）→ 剪影互不重复 → 无脸化 / 无文字 / 无网格残留 → 卡框合成后炮管、撑脚、顶件不被边框压住。

### 5.3 core 中性基准族实测（2026-11-09 · 蓝钢灰口径，不重出）

| 卡 | p50 | p85 | alpha p10 | 水印 | 判定 |
|---|---|---|---|---|---|
| Cannon | 112 | 179 | 255 | 0 | ✅ 风格样板 |
| Foundry | 124 | 171 | 255 | 0 | ✅ |
| Arrow | 119 | 209 | 255 | 0 | ✅ |
| Frost | 141 | 211 | 255 | 0 | ✅ |
| Scout | 91 | 188 | 255 | 0 | ✅ 略偏暗，可接受 |
| Kinetic | 102 | 177 | 255 | 0 | ✅ |
| Ranger | 104 | 191 | 255 | 0 | ✅ |
| Sentry | 118 | 235 | 255 | 0 | 🟡 p85 例外（亮钢主色） |
| Catapult | 95 | 185 | 255 | 0 | ✅ |
| Harrier | 104 | 173 | 255 | 0 | 🟡 造型待复核（脸化风险） |
| ~~Vanguard~~ | ~~94~~ | ~~180~~ | ~~255~~ | ~~0~~ | ⏭ 批次④ 数值（留档）；该卡属 `cinder`，已按 v1.2 主色调重出，现行数据见 §5.5 |

### 5.4 批次④ · 熔炉包实测（2026-11-09 · 包色装甲板版）

| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印 | 判定 |
|---|---|---|---|---|---|---|
| Vanguard | 94 | 180 | 255 | 7.4% | 0 | ✅ |
| Ember | 100 | 172 | 255 | 23.1% | 0 | ✅ |
| Blaze | 103 | 183 | 255 | 9.1% | 0 | ✅ |
| Cinder | 108 | 186 | 255 | 15.7% | 0 | ✅ |
| Pyre | 99 | 186 | 255 | 10.9% | 0 | ✅ |
| Maul | 100 | 181 | 255 | 18.3% | 0 | ✅ |
| Furnace | 125 | 176 | 255 | 17.4% | 0 | ✅ |
| Wildfire | 120 | 170 | 255 | 17.1% | 0 | ✅ |
| Ashen | 111 | 174 | 255 | 14.8% | 0 | ✅ |
| Hellfire | 116 | 176 | 255 | 22.5% | 0 | ✅ |

> **包色覆盖率（cov）** = 不透明像素中「色相接近包色且 S≥0.25」的占比，由 `card_batch3_process.py` 自动计算，<2% 判「包色面板偏少」。
> 旧版只有小点缀时约 1–2%，本批 **7.4–23.1%**，跨包区分度提升一档。前后并排见 `art/_review/batch4/compare_pack_color.png`。
> 旧 v4b 的 Vanguard（p50=186 / alpha p10=11 / 水印残留 476）已作废，原图留档 `prev_Vanguard_prepack.png`。

### 5.5 批次⑤ · 包色主色调实测（2026-11-09 · **现行口径**）

`py -3.9 tools/card_batch3_process.py --batch batch5 --dominant` 一次跑完 11 张：

| 卡 | 包 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印 | 判定 |
|---|---|---|---|---|---|---|---|
| Vanguard | cinder | 83 | 142 | 255 | 80.0% | 0 | ✅ 试点，暗部细节清晰 |
| Ember | cinder | 147 | 156 | 255 | 78.2% | 0 | ✅ |
| Blaze | cinder | 115 | 180 | 255 | 68.6% | 0 | ✅ |
| Cinder | cinder | 112 | 183 | 255 | 65.4% | 0 | ✅ |
| Pyre | cinder | 143 | 171 | 255 | 75.5% | 0 | ✅ |
| Maul | cinder | 103 | 159 | 255 | 77.1% | 0 | ✅ |
| Furnace | cinder | 142 | 163 | 255 | 78.6% | 0 | ✅ |
| Wildfire | cinder | 105 | 167 | 255 | 76.2% | 0 | ✅ |
| Ashen | cinder | 130 | 181 | 255 | 76.3% | 0 | ✅ |
| Hellfire | cinder | 110 | 166 | 255 | 83.4% | 0 | ✅ |
| **Glacier** | **rime** | 175 | 205 | 255 | 96.5% | 0 | ✅ **跨包试点**（耀青主调，与熔橙一眼可分） |

> 覆盖率从批次④的 **7.4–23.1%** 提升到 **65.4–96.5%**；alpha 全 255；水印区 11 张全 0 残留。
> 对比图：`art/_review/batch5/compare_dominant_color.png`（Vanguard 三代演进 + 跨包并排 + 8 包色板）；
> 总览：`art/_review/batch5/contact_batch5_cards.png`。

### 5.6 批次⑥ · 霜序包补齐 + 穿甲包试点（2026-11-09 · **亮色相包档位**）

`py -3.9 tools/card_batch3_process.py --batch batch6 --dominant --bright-pack` 一次跑完 11 张：

| 卡 | 包 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |
|---|---|---|---|---|---|---|---|
| Avalanche | rime | 113 | 165 | 255 | 94.4% | 0 | ✅ |
| Drillmaster | rime | 133 | 176 | 255 | 97.4% | 0 | ✅ |
| Glacier | rime | 118 | 194 | 255 | 96.2% | 0 | ✅ 沿用批次⑤ 原图按新档重出，保包内一致 |
| Hail | rime | 112 | 180 | 255 | 96.7% | 0 | ✅ |
| Icicle | rime | 118 | 196 | 255 | 89.9% | 0 | ✅ |
| **Martyr** | **pierce** | 133 | 177 | 255 | 81.1% | 0 | ✅ **跨包试点**（辉金主调） |
| Permafrost | rime | 165 | 205 | 255 | 98.1% | 0 | ✅ 本批最亮，仍在上界内 |
| Purity | rime | 112 | 174 | 255 | 82.6% | 0 | ✅ |
| Shard | rime | 133 | 196 | 255 | 85.0% | 0 | ✅ |
| Snowfall | rime | 143 | 186 | 255 | 96.1% | 0 | ✅ |
| Whiteout | rime | 144 | 188 | 255 | 92.7% | 🟡 37 | ✅ 人工复核为**底座右撑脚**，非水印文字，见 §8 #9 |

> 首跑（白场 155）5 张 p50 偏离、2 张 p85 过曝，按 §4.2 换档后 11 张全过检，覆盖率 81.1–98.1%，alpha 全 255。
> 样张：`art/_review/batch6/contact_batch6_cards.png`、`contact_batch6_64.png`、`compare_pack_color_batch6.png`、`contact_batch6_raw.png`。

### 5.7 批次⑦ · 穿甲包整包落地（2026-11-09 · **v1.3 档位第二批验证**）

`py -3.9 tools/card_batch3_process.py --batch batch7 --dominant --bright-pack` 一次跑完 10 张（9 张新图 + 批次⑥ 的 `Martyr` 沿用原图随包重跑，数值不变）：

| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |
|---|---|---|---|---|---|---|
| Arcane | 120 | 190 | 255 | 70.8% | 0 | ✅ |
| Ballista | 111 | 180 | 255 | 84.7% | 0 | ✅ |
| Hemorrhage | 139 | 178 | 255 | 78.5% | 0 | ✅ |
| Impaler | 119 | 184 | 255 | 69.5% | 0 | ✅ |
| Javelin | 103 | 190 | 255 | 63.0% | 0 | ✅ |
| Lance | 97 | 180 | 255 | 51.5% | 0 | ✅ 本批最暗 / 覆盖率最低，仍在上界内 |
| Longbow | 105 | 178 | 255 | 52.4% | 0 | ✅ |
| Martyr | 133 | 177 | 255 | 81.1% | 0 | ✅ 批次⑥ 试点，随包重跑 |
| Needle | 126 | 180 | 255 | 70.1% | 0 | ✅ |
| Sniper | 115 | 165 | 255 | 78.9% | 0 | ✅ |

> 10 张全过检：p50 97–139 / p85 165–190 / cov 51.5–84.7% / alpha 全 255 / 水印区全 0。辉金覆盖率整体低于耀青（约低 15–20 个百分点），原因是金色三阶里「burnt amber 暗板」偏棕，色相判定更容易出界，但**机身仍为整机金色**，人工接触表确认无回退到蓝钢灰。
> **`--bright-pack` 至此在两个包（rime / pierce）共 21 张上验证通过**，档位可视为稳定；`core` / `cinder` 继续用默认白场 155，互不干扰。
> 样张：`art/_review/batch7/contact_batch7_cards.png`、`contact_batch7_64.png`、`contact_batch7_raw.png`、`compare_pack_progress_batch7.png`（8 包进度 40/80）。

### 5.8 批次⑧ · 电弧包整包落地（2026-11-09 · **v1.4 中明度档位**）

`py -3.9 tools/card_batch3_process.py --batch batch8 --dominant --mid-pack` 从 `raw_*.png` 幂等重跑 10 张（首跑默认档 4 张报警，换档后全过，未重出任何 AI 图）：

| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |
|---|---|---|---|---|---|---|
| Arc | 100 | 170 | 255 | 63.9% | 🟡 5 | ✅ 5 px 为抗锯齿边缘 |
| Bolt | 98 | 155 | 255 | 67.4% | 0 | ✅ |
| Circuit | 98 | 161 | 255 | 58.9% | 0 | ✅ |
| Coil | 89 | 164 | 255 | 71.3% | 0 | ✅ 首跑 73 → 89 |
| Overcharge | 87 | 148 | 255 | 63.0% | 0 | ✅ 首跑 71 → 87，本批最暗 |
| Spark | 106 | 149 | 255 | 62.1% | 0 | ✅ |
| Storm | 92 | 165 | 255 | 45.6% | 🟡 393 | ✅ 底座撑脚，见下 |
| Tesla | 151 | 162 | 255 | 58.5% | 0 | ✅ 本批最亮 |
| Thunder | 100 | 181 | 255 | 65.5% | 0 | ✅ 试点 |
| Thunderhead | 91 | 147 | 255 | 54.6% | 🟡 256 | ✅ 底座撑脚，见下 |

> 10 张全过检：p50 87–151 / p85 147–181 / cov 45.6–71.3% / alpha 全 255。三张水印区非零经 `watermark_check_batch8.png` 放大复核均为**主体部件边缘色块**（Storm / Thunderhead 是底座撑脚，Arc 是抗锯齿），无任何文字笔画，属构图边界例外而非水印残留。
> 覆盖率整体低于耀青 / 熔橙，原因是星紫三阶里 `deep indigo` 暗板 + 蓝钢灰底座占比偏高；人工接触表确认机身仍是整机紫色，无回退到蓝钢灰。
> 样张：`art/_review/batch8/contact_batch8_cards.png`、`contact_batch8_64.png`、`contact_batch8_raw.png`、`compare_pack_color_batch8.png`（5 包并排）、`compare_pack_progress_batch8.png`（50/80）、`compare_tone_batch8.png`（三档描边对比）、`watermark_check_batch8.png`。

### 5.9 批次⑨ · 破甲包整包落地（2026-11-09 · **v1.5 高抬暗板档位**）

`py -3.9 tools/card_batch3_process.py --batch batch9 --dominant --lift-pack` 从 `raw_*.png` 幂等重跑 10 张（首跑 `--mid-pack` 4 张报警，整包换档后全过，未重出任何 AI 图）：

| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |
|---|---|---|---|---|---|---|
| Bastion | 97 | 132 | 255 | 67.5% | 0 | ✅ |
| Breaker | 92 | 136 | 255 | 65.8% | 🟡 304 | ✅ 钻杆尖端伸入检查区，见下 |
| Crusher | 103 | 156 | 255 | 63.7% | 0 | ✅ |
| Drummer | 87 | 148 | 255 | 59.8% | 0 | ✅ 首跑 74 → 87，本批最暗 |
| Quake | 127 | 160 | 255 | 67.9% | 0 | ✅ 本批最亮 |
| Rend | 91 | 146 | 255 | 56.6% | 0 | ✅ 首跑 78 → 91 |
| Ruin | 115 | 197 | 255 | 41.6% | 0 | ✅ 覆盖率最低 / p85 最高，仍在上界内 |
| Shatter | 90 | 148 | 255 | 62.4% | 0 | ✅ 首跑 77 → 90 |
| Siege | 107 | 164 | 255 | 59.8% | 0 | ✅ |
| Sunder | 104 | 143 | 255 | 69.5% | 0 | ✅ 试点 |

> 10 张全过检：p50 87–127 / p85 132–197 / cov 41.6–69.5% / alpha 全 255。`Breaker` 检查区 304 个不透明像素经 `watermark_check_batch9.png` 放大复核为**向下伸出的钻杆尖端**（红色锥形机械部件），非文字笔画，属构图边界例外。
> 样张：`art/_review/batch9/contact_batch9_cards.png`、`contact_batch9_64.png`、`contact_batch9_raw.png`、`compare_pack_color_batch9.png`（6 包并排）、`compare_pack_progress_batch9.png`（60/80）、`compare_tone_batch9.png`（试点四档）、`compare_tone_lift_batch9.png`（floor 抬升描边复核）、`watermark_check_batch9.png`。

### 5.10 批次⑩ · 咒术包整包落地（2026-11-09 · **v1.6 低明度深青**）

`py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack` 一次跑完 10 张（按铁律 5 先出 `Hex` 试点、通过后才放量其余 9 张；从 `raw_*.png` 幂等重跑，未重出任何 AI 图）：

| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |
|---|---|---|---|---|---|---|
| Blight | 121 | 166 | 255 | 95.7% | 0 | ✅ |
| Curse | 105 | 180 | 255 | 99.6% | 0 | ✅ |
| Executioner | 101 | 176 | 255 | 88.5% | 0 | ✅ |
| Hex | 101 | 167 | 255 | 98.2% | 0 | ✅ 试点 |
| Hexer | 108 | 177 | 255 | 92.6% | 0 | ✅ |
| Malison | 102 | 161 | 255 | 99.4% | 0 | ✅ |
| Omen | 109 | 182 | 255 | 92.5% | 0 | ✅ |
| Plague | 109 | 161 | 255 | 96.1% | 0 | ✅ |
| Rune | 138 | 179 | 255 | 97.8% | 0 | ✅ 本批最亮 |
| Wither | 103 | 164 | 255 | 94.3% | 🟡 245 | ✅ 底座撑脚，见下 |

> 10 张全过检：p50 101–138 / p85 161–182 / cov 88.5–99.6% / alpha 全 255。深青覆盖率是历批最高（此前最高为耀青 98.1%），原因是低明度高饱和青绿几乎铺满机身，色相判定极少出界。
> 人工复核：接触表 10 张同族（粗描边 / 分层装甲板 / 面板缝 / 铆钉 / 3/4 构图一致），剪影互不重复；64px 仍能读出穹顶、悬臂、铡刀架、阶梯基座、笼柱等轮廓；卡框合成无部件被边框压住。`Omen` 的 eye-shaped sigil 是提示词库原设功能件，属单眼几何徽记而非「两个圆件并排」的脸化布局；量化色相直方图显示各卡饱和像素 79–99% 落在深青主色及相邻分箱，**无第二色相**（拱门 / 笼柱内的暗紫为低饱和内部阴影）。
> `Wither` 检查区 245 px 经 `watermark_check_batch10.png` 放大复核为**底座右撑脚的青色斜面**，非文字笔画，属构图边界例外。
> 近色对复核：`compare_nearhue_batch10.png` 把 rime 耀青 3 张与 hex 深青 3 张并排，耀青 L≈179、深青 L≈91，明度差近一倍，一眼可分；`sunder`↔`true` 仍待 `true` 出图后复核。
> 样张：`art/_review/batch10/contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`。

### 5.11 批次⑪ · 湮灭包整包落地与收官（2026-11-09 · **v1.7 真红防串色**）

按铁律 5 先出 `Oblivion` 试点，四档实测 p50 = 默认 72 / `--bright-pack` 55 / `--mid-pack` 89 / **`--lift-pack` 101**，与深青包同型 → 第三次复用 `--lift-pack`（`--white 145 --floor 58`），不新增第五档、不放宽门槛。放量 9 张后 `py -3.9 tools/card_batch3_process.py --batch batch11 --dominant --lift-pack` 整包 10 张全过检（Eraser 重出后从 `raw_*.png` 幂等重跑）：

| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |
|---|---|---|---|---|---|---|
| Eraser | 100 | 126 | 255 | 73.0% | 0 | ✅ 重出 1 张，见下 |
| Exile | 94 | 134 | 255 | 64.3% | 0 | ✅ |
| Necro | 107 | 150 | 255 | 68.6% | 0 | ✅ |
| Null | 101 | 128 | 255 | 78.0% | 0 | ✅ |
| Obliterator | 108 | 135 | 255 | 78.3% | 0 | ✅ 防脸化转译 |
| Oblivion | 101 | 124 | 255 | 81.7% | 0 | ✅ 试点 |
| Rift | 96 | 118 | 255 | 77.6% | 0 | ✅ |
| Soulpiercer | 100 | 131 | 255 | 71.5% | 🟡 1 | ✅ 抗锯齿单点 |
| Void | 105 | 132 | 255 | 66.3% | 0 | ✅ |
| Wraith | 88 | 125 | 255 | 74.7% | 0 | ✅ 本批最暗 / 防脸化转译 |

> 10 张全过检：p50 88–108 / p85 118–150 / cov 64.3–81.7% / alpha 全 255。红色在亮度公式里权重仅 0.2126，p85 天然低于青/金（118–150 vs 160–205），但 p50 达标、卡框复核机身醒目且暗板层次清楚，属正常，**不因此调门槛**。
> **真红防串色**：`true` 警报红 `#FF2E4E` 与 `sunder` 噬品红 `#E8437F` 是 8 包里色相最近的一对。模板补 `Keep the red a pure signal red, NOT pink, NOT magenta, NOT crimson`（§3.1 注）；`compare_nearhue_batch11.png` 并排复核上排噬品红偏粉紫、下排纯正红，一眼可分，**该近色对风险解除**。加上批次⑩ 的 `rime`↔`hex`，至此全部近色对复核完毕。
> **Eraser 重出**：首版被 `image1` 的 Cannon 锚点带出高饱和青色圆形炮口（第二色相），且矮圆炮台剪影与 `Obliterator` 撞型。按标准重出该张 AI 图（本批唯一一次重出），3/4 转译里明确 `tall upright rectangular body with a wide flat rectangular head` 与 `no circular muzzle, no round lens, no cyan or blue light, no cannon shape, no rounded turret body`；旧图留档 `art/_review/batch11/prev_Eraser_rejected.png`。重出后亮青能量点缀占比 **0.50% → 0.11%**（余量为蓝钢灰高光抗锯齿），整机纯红、剪影改竖直方塔，与其余 9 张互不重复；后处理仍走整包 `--lift-pack`，未逐张换档。
> **防脸化转译**：`Obliterator` 的双冲头由「两个圆面」改为 `blunt square ram plates ... not round, no eyes`，`Wraith` 面具改为 `abstract geometric tapered shield ... no eyes and no mouth, not a face`；人工复核两张均读作机械件而非脸。
> 人工复核：接触表 10 张同族（粗描边 / 分层装甲板 / 面板缝 / 铆钉 / 3/4 构图一致），剪影互不重复；64px 可读；卡框合成无部件被边框压住；`watermark_check_batch11.png` 9 张为 0、`Soulpiercer` 1 px 为抗锯齿单点，无文字笔画。
> 样张：`art/_review/batch11/contact_batch11_cards.png`、`contact_batch11_64.png`、`contact_batch11_raw.png`、`compare_pack_color_batch11.png`（8 包并排）、`compare_pack_progress_batch11.png`（80/80）、`compare_tone_batch11.png`（试点四档）、`compare_nearhue_batch11.png`（sunder↔true）、`watermark_check_batch11.png`。

---

## 6. 落盘与游戏接线

- 正式资产：`art/2d/cards/card_<name小写>_v1_t.png`（1024² 透明底）与 `card_<name小写>_v1_460.png`（460² 安全区透明底）。
- `art/manifest.json` 与 `.gd` / `.tscn` **无需改动**：文件名恒定，Godot 打开项目时自动重导入 PNG。**新卡首次落盘不会自带 `.import`**，需按项目规则补齐（`uid://` 唯一、`path` = `md5(res:// 路径)`，见 §8 #10），否则编辑器打开前资源无法 `load()`。
- UI 侧由 `scripts/ui/ui_style.gd` 的 `card_art(card_name)` 懒加载，资产缺失 / headless 返回 `null` 时降级为无图版式：
  - 商店 `shop_overlay.gd`：`SLOT_SIZE` 424px，顶部 72px 插画横带，纹理由 `_refresh_shop()` 按卡名填充（**构建时卡名还是占位符**）；
  - 主菜单 `main_menu_overlay.gd`：图鉴 278×126 卡条改「左 96×96 插画 + 右文字」。
- 战斗内塔身是 `Node2D` 程序化绘制，**不走贴图**；换卡面不影响战场表现。

---

## 7. 收官：8 包 80 张全部完成

卡池共 8 包 × 10 张 = 80 张（`scripts/data/card_packs.gd` 的 `PACKS`，与提示词库逐字对齐）。
**资产盘点（2026-11-09 · 批次⑪ 收官）**：`art/2d/cards/` 已有 **80 张**正式卡面（8 包各 10 张），`_v1_t.png` / `_v1_460.png` 各 80 个、`.import` 160 个且 uid 全唯一，**无待建卡面**；批次① 的 10 张原图只留在 `art/_review/batch1/`，从未进入正式目录。进度总览见 `art/_review/batch11/compare_pack_progress_batch11.png`。后续只剩 Godot 重导入 / export 与 UI 实机验证。

| 包 id | 名称 | 包色 | 张数 | 卡面状态 |
|---|---|---|---|---|
| `core` | 泛用包 | 钢灰 `#9AA5B1` | 10 | ✅ 已落地（**中性基准族，不重出**，见 §2.1） |
| `cinder` | 熔炉包 | 熔橙 `#FF6B3D` | 10 | ✅ **批次⑤ 按 v1.2 整机主色调重绘**，cov 65.4–83.4% |
| `rime` | 霜序包 | 耀青 `#3ED0E8` | 10 | ✅ **批次⑥ 补齐**（含 Glacier 按亮色相档重出），cov 82.6–98.1% |
| `pierce` | 穿甲包 | 辉金 `#FFC94A` | 10 | ✅ **批次⑦ 整包落地**（`--bright-pack`），cov 51.5–84.7% |
| `arc` | 电弧包 | 星紫 `#7A5CFF` | 10 | ✅ **批次⑧ 整包落地**（`--mid-pack`，v1.4 首个验证包），cov 45.6–71.3% |
| `sunder` | 破甲包 | 噬品红 `#E8437F` | 10 | ✅ **批次⑨ 整包落地**（`--lift-pack`，v1.5 首个验证包），cov 41.6–69.5% |
| `hex` | 咒术包 | 深青 `#1A6B7D` | 10 | ✅ **批次⑩ 整包落地**（`--lift-pack` 复用，v1.6 低明度验证包），cov 88.5–99.6% |
| `true` | 湮灭包 | 警报红 `#FF2E4E` | 10 | ✅ **批次⑪ 整包落地**（`--lift-pack` 第三次复用，v1.7 真红防串色包），cov 64.3–81.7% |

**每包流程（8 包已全部走完）**：从 `card-prompt-bank-v2.json` 取 10 张的 `structure/feature/accent_block` + 该包的 `pack_palette`（`hex/name/hue_word/shadow_word`）→ 按 §3.1 做 3/4 转译 → **先出 1 张**同族比对 → 通过后出剩余 9 张 → `card_batch3_process.py --batch <批次> --dominant [档位]` 批量后处理 → 接触表 + 量化自检 → 按同名规则落盘 → 卡框样张归档。单包约 10 张 × 5–10 积分；批次⑪ 实际 11 次生图（10 张 + `Eraser` 重出 1 张）。**后续没有新包要建**。
**后处理档位四选一**（整包统一、互斥，先出 1 张试点测 p50 再定）：默认档白场 155（`core` / `cinder`）｜ `--bright-pack`（青 / 金，§4.2）｜ `--mid-pack`（星紫等 L≈90–140，§4.3）｜ `--lift-pack`（暗板占比高的中明度包 + 低明度包，§4.4 / §4.5）。收官统计：`rime` / `pierce` 21 张、`arc` 10 张、`sunder` + `hex` + `true` 30 张、`core` / `cinder` 20 张，合计 **80 张全部过检**。
**青色系包**（`rime` / `hex`）模板里补 `clearly brighter and more saturated than neutral blue-grey steel`；**低明度包**（`hex` / `true`）再加主色提亮句，别整机糊成一团；**真红包**（`true`）再加防串色句 `NOT pink, NOT magenta, NOT crimson`。两对近色对 `rime`↔`hex`（`compare_nearhue_batch10.png`）与 `sunder`↔`true`（`compare_nearhue_batch11.png`）均已并排复核解除。

---

## 8. 已知问题与待办

| # | 问题 | 处理 |
|---|---|---|
| 1 | ~~`Vanguard` 旧 v4b 产物不同族（p50=186 / alpha 11 / 水印 476）~~ | ✅ **已修复**（批次④→⑤）：按 3/4 产线重出后又按 v1.2 整机换色，现 p50=83 / alpha 255 / 水印 0 / 包色覆盖 80.0%；旧图留档 `prev_Vanguard_prepack.png` |
| 2 | `Harrier` 双垂直发射鼓略像双筒望远镜 / 眼睛 | 待用户复核，必要时重出（提示词加 `no face-like layout`） |
| 3 | 旧文档 `card-illustration-style-v1.md` 的「禁 3/4 / 正面立面冻结」条款与本文冲突 | 已在旧文档头部挂状态指针；正文留档不改 |
| 4 | 美术圣经 §11 开放问题 #3 曾记「当前无卡面资产」 | 已同步更新为「✅ 已定：AI 扁平插画 · 3/4 图生图产线」 |
| 5 | 本机无 Godot 编辑器（只有导出的 `Corebound.exe`，embed_pck 无法热更），UI 接线**未实机验证** | 用 Godot 4.7.2 打开项目重导入 → F5 看商店 / 图鉴 → 需要出包时重新 `--export-release` |
| 6 | 80 张卡面**已全部落盘**（8 包各 10 张），无待建卡 | ✅ 批次⑪ 收官解除；后续只做 Godot 4.7.2 重导入与 export，不再出图 |
| 7 | 近色对风险**全部解除**；中性色在覆盖率自检中免检 | ✅ `rime`↔`hex` 于批次⑩、`sunder`↔`true` 于批次⑪ 并排复核通过（真红防串色补句生效）；若日后调整包色，须重新并排复核 |
| 8 | **`core` 10 张仍是蓝钢灰族，与其余 7 包的整机主色调是两种口径并存** | 用户 2026-11-09 拍板「core 作中性基准族不重出」。若日后要求全组严格统一，单独重出 core 10 张（用 `--dominant`，包色 `neutral grey / charcoal grey`） |
| 9 | `Whiteout` 在 `x≥70% & y≥90%` 检查区有 37 个不透明像素；批次⑧ 的 `Storm` 393 / `Thunderhead` 256 / `Arc` 5、批次⑨ 的 `Breaker` 304、批次⑩ 的 `Wither` 245、批次⑪ 的 `Soulpiercer` 1 同理 | 均人工放大复核为**主体部件边缘色块 / 抗锯齿单点**（底座撑脚 / 钻杆尖端），透明底图上无「AI生成 WORKBUDDY>」文字，属构图边界例外而非水印残留。留档 `art/_review/batch8/watermark_check_batch8.png`、`art/_review/batch9/watermark_check_batch9.png`、`art/_review/batch10/watermark_check_batch10.png`、`art/_review/batch11/watermark_check_batch11.png`；若日后统一卡面尺寸，优先重出偏宽偏低 / 部件伸出的卡并加 `compact narrow base` |
| 10 | **新增卡面的 `.import` 不会自动出现**（本机无 Godot 编辑器） | 批次⑥ 补 20 个、批次⑦ 补 18 个、批次⑧ 补 20 个、批次⑨ 补 20 个、批次⑩ 补 20 个、批次⑪ 补 20 个，现 `art/2d/cards/` 共 **160 个 `.import` 且 uid 全唯一**（`uid://` 随机唯一，`path` = `md5(res:// 路径)`），全部新卡已补齐；最终仍需 Godot 4.7.2 打开项目重导入生成 `.ctex` 并重新 export |

---

## 9. 相关文件

| 用途 | 路径 |
|---|---|
| 风格样板 | `art/_review/batch2/raw_Cannon_flat_v2.png`、`raw_Cannon_flat_v2_norm.png` |
| 泛用包原图 / 样张 | `art/_review/batch3/raw_*.png`、`mock_*_v2.png`、`contact_batch3_cards.png` |
| 熔炉包 v1.1 原图 / 样张 / 对比（留档） | `art/_review/batch4/raw_*.png`、`mock_*.png`、`contact_batch4_cards.png`、`compare_pack_color.png`、`prev_*_prepack.png` |
| **主色调 v1.2 原图 / 样张 / 对比** | `art/_review/batch5/raw_*.png`、`mock_*.png`、`contact_batch5_cards.png`、`compare_dominant_color.png` |
| **亮色相包 v1.3 原图 / 样张 / 对比** | `art/_review/batch6/raw_*.png`、`mock_*.png`、`contact_batch6_cards.png`、`contact_batch6_64.png`、`compare_pack_color_batch6.png`、`contact_batch6_raw.png`；`art/_review/batch7/raw_*.png`、`mock_*.png`、`contact_batch7_cards.png`、`contact_batch7_64.png`、`compare_pack_progress_batch7.png`（8 包进度 40/80） |
| **中明度包 v1.4 原图 / 样张 / 对比** | `art/_review/batch8/raw_*.png`、`mock_*.png`、`contact_batch8_cards.png`、`contact_batch8_64.png`、`contact_batch8_raw.png`、`compare_pack_color_batch8.png`（5 包并排）、`compare_pack_progress_batch8.png`（50/80）、`compare_tone_batch8.png`（三档描边对比）、`watermark_check_batch8.png` |
| 高抬暗板 v1.5 原图 / 样张 / 对比 | `art/_review/batch9/raw_*.png`、`mock_*.png`、`contact_batch9_cards.png`、`contact_batch9_64.png`、`contact_batch9_raw.png`、`compare_pack_color_batch9.png`（6 包并排）、`compare_pack_progress_batch9.png`（60/80）、`compare_tone_batch9.png`（试点四档）、`compare_tone_lift_batch9.png`（floor 抬升描边复核）、`watermark_check_batch9.png` |
| 低明度深青 v1.6 原图 / 样张 / 对比 | `art/_review/batch10/raw_*.png`、`mock_*.png`、`contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`；复核留档脚本 `make_review_batch10.py`、`update_standard_batch10.py` |
| **真红收官 v1.7 原图 / 样张 / 对比（现行）** | `art/_review/batch11/raw_*.png`、`prev_Eraser_rejected.png`（重出留档）、`mock_*.png`、`contact_batch11_cards.png`、`contact_batch11_64.png`、`contact_batch11_raw.png`、`compare_pack_color_batch11.png`（8 包并排）、`compare_pack_progress_batch11.png`（80/80）、`compare_tone_batch11.png`（试点四档）、`compare_nearhue_batch11.png`（sunder↔true）、`watermark_check_batch11.png`；复核留档脚本 `make_review_batch11.py`、`update_standard_batch11.py` |
| 对象 / 主色 / **包色真源** | `design/art/card-prompt-bank-v2.json` **v2.7**（`pack_palette` 的 `hex/name/hue_word/shadow_word`、`pack_color_rule`、`accent_by_pack`、`cards[*].accent`、`postprocess_hint.bright_pack` / `.mid_pack` / `.lift_pack` / `.completion`）；镜像常量 `tools/build_card_prompt_bank_v2.py::PACK_ACCENT`（🔴 勿运行重建）；UI 侧 `scripts/ui/ui_style.gd::PACK_COLORS` |
| 旧口径体系（正面立面 v4/v4b · 留档） | `design/art/card-illustration-style-v1.md`、`design/art/card-prompts-batch2.json` |
| 后处理工具 | `tools/card_tone_levels.py`、`card_keyout.py`、`card_batch3_process.py`、`card_mock_card.py`、`card_contact_sheet.py` |
| 总纲 | `design/art/art-bible.md` §2.2 / §5.5 / §6.5 / §11 |

---

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-08 | 以用户手绘炮塔素描图生图定稿 Cannon（3/4 扁平蓝图 + 手绘层次）；中途出过一版正面微仰视立面（`raw_Cannon_front_v2.png`），用户最终选回 3/4 |
| 2026-11-08 | 沉淀 `card_tone_levels.py` 与 `card_keyout.py --connectivity-only`；定稿参数 `--black 35 --white 155` |
| 2026-11-08 | 泛用包其余 9 张批量重绘；首轮纯文字生成判废，改「Cannon 作风格参考图」方案后全部达标 |
| 2026-11-08 | 卡面插画首次接入游戏 UI（`ui_style.card_art()` / 商店 / 图鉴） |
| 2026-11-09 | 立本文为卡面插画生成标准；同步旧文档状态指针、美术圣经开放问题 #3、图鉴文档过时描述 |
| 2026-11-09 | **v1.1 包色区分度**：诊断出两套包色并存 / core·rime 撞色 / 包内 4 色混用 / 包色仅占 2% 面积；改以 UI `PACK_COLORS` 为 SSOT，8 包一色、包内统一，冻结模板加入约 20% 包色装甲板；`card-prompt-bank-v2.json` 升 v2.1 |
| 2026-11-09 | **批次④ 熔炉包** cinder 10 张按新规出图并落地（含 Vanguard 按本标准重出，旧 v4b 不同族问题关闭）；`card_batch3_process.py` 升级通用批次版（`--batch`）+ 包色覆盖率自检；10 张 cov 7.4–23.1%、水印 0 残留 |
| 2026-11-09 | **v1.2 包色即主色调**（用户拍板）：包色从 20% 装甲板升级为整机 60%+ 三阶平涂；冻结模板改锁「结构」而非「灰调」+ `COLOUR RULE`；`card-prompt-bank-v2.json` 升 v2.2（新增 `hue_word/shadow_word/pack_color_mode/postprocess_hint`）；`card_tone_levels.py` 加 `--protect-mode remap`（修整机高饱和被当小点缀跳过重映射的 bug）；`card_batch3_process.py` 加 `--dominant`（cov ≥40% / p50 80–185） |
| 2026-11-09 | **批次⑤** cinder 10 张整机熔橙重绘 + rime `Glacier` 耀青跨包试点，11 张全过检（cov 65.4–96.5% / alpha 全 255 / 水印 0）；核心交付 `art/_review/batch5/compare_dominant_color.png`、`contact_batch5_cards.png` |
| 2026-11-09 | **v1.3 亮色相包档位**：批次⑥ 首跑发现青 / 金主色撞白场 155 饱和 + `L>170` 保护，5 张 p50 偏离、2 张 p85 过曝；参数探测后固化 `card_batch3_process.py --bright-pack`（白场 230 / 阈值 250），门槛不放宽、提示词模板不动；`card-prompt-bank-v2.json` 升 **v2.3**（`postprocess_hint.bright_pack`），`anchor_ref` 同步 v1.3 |
| 2026-11-09 | **批次⑥** rime 剩 9 张补齐 + pierce `Martyr` 辉金试点 + `Glacier` 按新档重出，11 张全过检（p50 112–165 / p85 165–205 / cov 81.1–98.1% / alpha 全 255）；补齐 20 个新卡 `.import`；正式卡面达 **31 张**。交付 `art/_review/batch6/contact_batch6_cards.png`、`compare_pack_color_batch6.png` |
| 2026-11-09 | **批次⑦** pierce 剩 9 张放量（`--bright-pack` 第二批验证），整包 10 张全过检（p50 97–139 / p85 165–190 / cov 51.5–84.7% / alpha 全 255 / 水印全 0）；补 18 个 `.import`（共 80 个 uid 唯一）；正式卡面达 **40 张 / 80（4 包完成）**。交付 `art/_review/batch7/contact_batch7_cards.png`、`compare_pack_progress_batch7.png` |
| 2026-11-09 | **v1.4 中明度包色档位**：批次⑧ 试点发现星紫 L≈110 两头不靠（`--bright-pack` 把 p50 压到 61、默认档整包 4 张跌破 80）；整包 10 张 × 8 组参数探测后固化 `card_batch3_process.py --mid-pack`（`--white 145 --floor 42`，与 `--bright-pack` 互斥），门槛 / 提示词 / 质检口径一律不动；`card-prompt-bank-v2.json` 升 **v2.4**（`postprocess_hint.mid_pack`），`anchor_ref` 同步 v1.4 |
| 2026-11-09 | **批次⑧** arc 电弧包 10 张整包落地（星紫 `#7A5CFF`），换 `--mid-pack` 幂等重跑后全过检（p50 87–151 / p85 147–181 / cov 45.6–71.3% / alpha 全 255）；补 20 个 `.import`（共 100 个 uid 唯一）；正式卡面达 **50 张 / 80（5 包完成）**。交付 `art/_review/batch8/contact_batch8_cards.png`、`compare_pack_color_batch8.png`、`compare_pack_progress_batch8.png` |
| 2026-11-09 | **v1.5 高抬暗板档位**：批次⑨ 试点发现噬品红 L≈150 用 `--mid-pack` 整包仍有 4 张 p50 74–79 跌破 80；整包 10 张 × 6 组探测证实「压白场」会把 `Ruin` 的 cov 压破 40% / p85 顶到 216，只有「白场不动 + floor 42→58」能让 10 张同时达标。固化 `card_batch3_process.py --lift-pack`（`--white 145 --floor 58`，三档互斥），门槛 / 提示词 / 质检口径一律不动；`card-prompt-bank-v2.json` 升 **v2.5**（`postprocess_hint.lift_pack`），`anchor_ref` 同步 v1.5 |
| 2026-11-09 | **批次⑨** sunder 破甲包 10 张整包落地（噬品红 `#E8437F`），换 `--lift-pack` 幂等重跑后全过检（p50 87–127 / p85 132–197 / cov 41.6–69.5% / alpha 全 255）；`Breaker` 检查区 304 px 复核为钻杆尖端而非水印；补 20 个 `.import`（共 120 个 uid 唯一）；正式卡面达 **60 张 / 80（6 包完成）**。交付 `art/_review/batch9/contact_batch9_cards.png`、`compare_pack_color_batch9.png`、`compare_pack_progress_batch9.png` |
| 2026-11-09 | **v1.6 低明度包色验证**：批次⑩ `Hex` 试点四档实测默认 73 / bright 55 / mid 89 / **lift 101**，确认深青 `#1A6B7D`（L≈91）**复用 v1.5 的 `--lift-pack`**，不新增第五档、不改参数、不放宽门槛；青色系模板按 §3.1 补主色提亮句。`card-prompt-bank-v2.json` 升 **v2.6**（`postprocess_hint.lift_pack.applies_to` 加 `hex`），`anchor_ref` 同步 v1.6 |
| 2026-11-09 | **批次⑩** hex 咒术包 10 张整包落地（深青 `#1A6B7D`），`--lift-pack` 一次过检（p50 101–138 / p85 161–182 / cov 88.5–99.6% / alpha 全 255）；量化色相直方图确认无第二色相；`Wither` 检查区 245 px 复核为底座撑脚；`rime`↔`hex` 近色对并排复核解除；补 20 个 `.import`（共 140 个 uid 唯一）；正式卡面达 **70 张 / 80（7 包完成）**。交付 `art/_review/batch10/contact_batch10_cards.png`、`compare_pack_color_batch10.png`、`compare_pack_progress_batch10.png`、`compare_nearhue_batch10.png` |
| 2026-11-09 | **v1.7 真红防串色 + 第三次复用 lift-pack**：批次⑪ `Oblivion` 试点四档 72 / 55 / 89 / 101，确认警报红 `#FF2E4E`（L≈93）同样复用 `--lift-pack`，不新增第五档、不放宽门槛；§3.1 注把低明度主色提亮句通用化为 `Lift the {hue} main plate`，并新增 `NOT pink, NOT magenta, NOT crimson` 防串色句。`card-prompt-bank-v2.json` 升 **v2.7**（`lift_pack.applies_to` 加 `true`、`postprocess_hint.completion`），`anchor_ref` 同步 v1.7 |
| 2026-11-09 | **批次⑪ 收官** true 湮灭包 10 张整包落地（警报红 `#FF2E4E`），`--lift-pack` 全过检（p50 88–108 / p85 118–150 / cov 64.3–81.7% / alpha 全 255）；`Eraser` 因锚点带出青色炮口重出 1 张（亮青点缀 0.50%→0.11%，剪影改竖直方塔）；`Obliterator` / `Wraith` 防脸化转译通过；`sunder`↔`true` 近色对并排复核解除，至此全部近色对已复核；补 20 个 `.import`（共 160 个 uid 唯一）。**正式卡面 80 / 80，8 包全部完成**。交付 `art/_review/batch11/contact_batch11_cards.png`、`compare_pack_color_batch11.png`、`compare_pack_progress_batch11.png`、`compare_nearhue_batch11.png` |
