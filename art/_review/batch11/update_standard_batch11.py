# -*- coding: utf-8 -*-
"""批次⑪ 收官：文档 / 提示词库 / 工具说明同步（v1.6 -> v1.7, v2.6 -> v2.7）。

一次性精确替换：每处 old 必须恰好命中一次，否则整体失败不写盘。
"""
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
DOC = os.path.join(ROOT, "design", "art", "card-art-generation-standard-v1.md")
BANK = os.path.join(ROOT, "design", "art", "card-prompt-bank-v2.json")
TOOL = os.path.join(ROOT, "tools", "card_batch3_process.py")


def apply(path, pairs):
    with io.open(path, encoding="utf-8") as f:
        text = f.read()
    for i, (old, new) in enumerate(pairs):
        n = text.count(old)
        if n != 1:
            raise SystemExit("!! %s 第 %d 处命中 %d 次（应为 1）：%s"
                             % (os.path.relpath(path, ROOT), i + 1, n, old[:80]))
        text = text.replace(old, new, 1)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("updated", os.path.relpath(path, ROOT), "|", len(pairs), "处")


DOC_PAIRS = [
    ("> 状态：🟢 **当前生效 · v1.6**（2026-11-09 立 / 同日七次更新）。适用于 `art/2d/cards/card_*_v1_{t,460}.png` 的全部新增与重绘。当前进度 **70 / 80 张（7 包完成）**，见 §7。",
     "> 状态：🟢 **当前生效 · v1.7**（2026-11-09 立 / 同日八次更新）。适用于 `art/2d/cards/card_*_v1_{t,460}.png` 的全部新增与重绘。当前进度 **80 / 80 张（8 包全部完成）**，见 §7。\n"
     "> 🆕 **v1.7 变更（批次⑪收官）**：最后一包 `true` 警报红 `#FF2E4E` 按铁律 5 先出 `Oblivion` 试点，四档实测默认 72 / `--bright-pack` 55 / `--mid-pack` 89 / **`--lift-pack` 101**，第三次复用该档；整包 10 张全过检（p50 88–108 / cov 64.3–81.7%）。新增**真红防串色补句** `NOT pink, NOT magenta, NOT crimson`，`sunder`↔`true` 近色对并排复核解除；`Eraser` 因锚点带出青色炮口重出 1 张。**档位参数、门槛、包色一律未动**。详见 §3.1 注、§4.5、§5.11。"),

    ("| 校色 | `--black 35 --white 155 --floor 26 --ceil 235` **＋ `--protect-mode remap`**；**亮色相包（青/金）改 `--white 230 --bright-threshold 250`**；**中明度包（星紫）改 `--white 145 --floor 42`**；**暗板占比高 / 低明度包（噬品红、深青）改 `--white 145 --floor 58`** | `tools/card_tone_levels.py` |",
     "| 校色 | `--black 35 --white 155 --floor 26 --ceil 235` **＋ `--protect-mode remap`**；**亮色相包（青/金）改 `--white 230 --bright-threshold 250`**；**中明度包（星紫）改 `--white 145 --floor 42`**；**暗板占比高 / 低明度包（噬品红、深青、警报红）改 `--white 145 --floor 58`** | `tools/card_tone_levels.py` |"),

    ("> 青色系包（`rime` / `hex`）与蓝钢灰色相接近，需在 COLOUR RULE 里补一句 `clearly brighter and more saturated than neutral blue-grey steel`（批次⑤ Glacier 实测有效）；**低明度深青包再加一句 `Lift the teal main plate to a readable mid-tone brightness`**（批次⑩ `Hex` 试点实测有效，见 §4.5），模板其余部分冻结。",
     "> 青色系包（`rime` / `hex`）与蓝钢灰色相接近，需在 COLOUR RULE 里补一句 `clearly brighter and more saturated than neutral blue-grey steel`（批次⑤ Glacier 实测有效）；**低明度包（`hex` / `true`）再加一句 `Lift the {hue} main plate to a readable mid-tone brightness`**（批次⑩ `Hex` / 批次⑪ `Oblivion` 试点实测有效，见 §4.5）；**真红包再加防串色句 `Keep the red a pure signal red, NOT pink, NOT magenta, NOT crimson`**（批次⑪ 实测有效，见 §5.11）。以上均只改 COLOUR RULE 段内的描述句，模板其余部分冻结。"),

    ("py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）",
     "py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）\n"
     "py -3.9 tools/card_batch3_process.py --batch batch11 --dominant --lift-pack   # v1.7 真红收官（第三次复用）"),

    ("**适用范围**：`sunder` 噬品红已验证 10 张；`hex` 深青在批次⑩ 按同一方法验证并复用本档（见 §4.5）；`true` 警报红仍须先出 1 张试点再定档。`core` / `cinder` 默认档、`rime` / `pierce` `--bright-pack`、`arc` `--mid-pack` 互不干扰。",
     "**适用范围**：`sunder` 噬品红已验证 10 张；`hex` 深青（批次⑩）与 `true` 警报红（批次⑪）均按同一方法验证并复用本档（见 §4.5 / §5.11），至此 8 包全部定档完毕。`core` / `cinder` 默认档、`rime` / `pierce` `--bright-pack`、`arc` `--mid-pack` 互不干扰。"),

    ("**适用范围更新**：`--lift-pack` 现已在 `sunder`（10 张）+ `hex`（10 张）共 20 张上验证通过；`--mid-pack` 仅 `arc`、`--bright-pack` 仅 `rime` / `pierce`。剩余 `true` 警报红 `#FF2E4E` 仍按铁律 5 出 1 张试点在四档里定档，不预设。",
     "**适用范围更新（收官）**：`--lift-pack` 已在 `sunder` + `hex` + `true` 共 30 张上验证通过（批次⑪ `Oblivion` 四档试点 72 / 55 / 89 / 101，整包 p50 88–108）；`--mid-pack` 仅 `arc`、`--bright-pack` 仅 `rime` / `pierce`、默认档仅 `core` / `cinder`。8 包全部完成，无剩余待定档包。"),

    ("> 🔴 **v1.3 / v1.4 / v1.5 / v1.6 的门槛都没有放宽**：亮色相包走 `--bright-pack`、中明度 / 低明度包走 `--mid-pack` / `--lift-pack` 后，仍按「主色调族」这一列（p50 80–185 / p85 ≤215 / cov ≥40%）验收。批次⑥ 11 张、批次⑧ 10 张、批次⑨ 10 张、批次⑩ 10 张全部达标，靠的都是修后处理（或复用已验证档位）而不是调门槛。禁止为了过检改阈值、禁止逐张单独换档。",
     "> 🔴 **v1.3 → v1.7 的门槛始终没有放宽**：亮色相包走 `--bright-pack`、中明度 / 低明度包走 `--mid-pack` / `--lift-pack` 后，仍按「主色调族」这一列（p50 80–185 / p85 ≤215 / cov ≥40%）验收。批次⑥ 11 张、批次⑧ 10 张、批次⑨ 10 张、批次⑩ 10 张、批次⑪ 10 张全部达标，靠的都是修后处理（或复用已验证档位）而不是调门槛。禁止为了过检改阈值、禁止逐张单独换档。"),

    ("> 样张：`art/_review/batch10/contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`。\n\n---",
     "> 样张：`art/_review/batch10/contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`。\n\n"
     "### 5.11 批次⑪ · 湮灭包整包落地与收官（2026-11-09 · **v1.7 真红防串色**）\n\n"
     "按铁律 5 先出 `Oblivion` 试点，四档实测 p50 = 默认 72 / `--bright-pack` 55 / `--mid-pack` 89 / **`--lift-pack` 101**，与深青包同型 → 第三次复用 `--lift-pack`（`--white 145 --floor 58`），不新增第五档、不放宽门槛。放量 9 张后 `py -3.9 tools/card_batch3_process.py --batch batch11 --dominant --lift-pack` 整包 10 张全过检（Eraser 重出后从 `raw_*.png` 幂等重跑）：\n\n"
     "| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |\n|---|---|---|---|---|---|---|\n"
     "| Eraser | 100 | 126 | 255 | 73.0% | 0 | ✅ 重出 1 张，见下 |\n"
     "| Exile | 94 | 134 | 255 | 64.3% | 0 | ✅ |\n"
     "| Necro | 107 | 150 | 255 | 68.6% | 0 | ✅ |\n"
     "| Null | 101 | 128 | 255 | 78.0% | 0 | ✅ |\n"
     "| Obliterator | 108 | 135 | 255 | 78.3% | 0 | ✅ 防脸化转译 |\n"
     "| Oblivion | 101 | 124 | 255 | 81.7% | 0 | ✅ 试点 |\n"
     "| Rift | 96 | 118 | 255 | 77.6% | 0 | ✅ |\n"
     "| Soulpiercer | 100 | 131 | 255 | 71.5% | 🟡 1 | ✅ 抗锯齿单点 |\n"
     "| Void | 105 | 132 | 255 | 66.3% | 0 | ✅ |\n"
     "| Wraith | 88 | 125 | 255 | 74.7% | 0 | ✅ 本批最暗 / 防脸化转译 |\n\n"
     "> 10 张全过检：p50 88–108 / p85 118–150 / cov 64.3–81.7% / alpha 全 255。红色在亮度公式里权重仅 0.2126，p85 天然低于青/金（118–150 vs 160–205），但 p50 达标、卡框复核机身醒目且暗板层次清楚，属正常，**不因此调门槛**。\n"
     "> **真红防串色**：`true` 警报红 `#FF2E4E` 与 `sunder` 噬品红 `#E8437F` 是 8 包里色相最近的一对。模板补 `Keep the red a pure signal red, NOT pink, NOT magenta, NOT crimson`（§3.1 注）；`compare_nearhue_batch11.png` 并排复核上排噬品红偏粉紫、下排纯正红，一眼可分，**该近色对风险解除**。加上批次⑩ 的 `rime`↔`hex`，至此全部近色对复核完毕。\n"
     "> **Eraser 重出**：首版被 `image1` 的 Cannon 锚点带出高饱和青色圆形炮口（第二色相），且矮圆炮台剪影与 `Obliterator` 撞型。按标准重出该张 AI 图（本批唯一一次重出），3/4 转译里明确 `tall upright rectangular body with a wide flat rectangular head` 与 `no circular muzzle, no round lens, no cyan or blue light, no cannon shape, no rounded turret body`；旧图留档 `art/_review/batch11/prev_Eraser_rejected.png`。重出后亮青能量点缀占比 **0.50% → 0.11%**（余量为蓝钢灰高光抗锯齿），整机纯红、剪影改竖直方塔，与其余 9 张互不重复；后处理仍走整包 `--lift-pack`，未逐张换档。\n"
     "> **防脸化转译**：`Obliterator` 的双冲头由「两个圆面」改为 `blunt square ram plates ... not round, no eyes`，`Wraith` 面具改为 `abstract geometric tapered shield ... no eyes and no mouth, not a face`；人工复核两张均读作机械件而非脸。\n"
     "> 人工复核：接触表 10 张同族（粗描边 / 分层装甲板 / 面板缝 / 铆钉 / 3/4 构图一致），剪影互不重复；64px 可读；卡框合成无部件被边框压住；`watermark_check_batch11.png` 9 张为 0、`Soulpiercer` 1 px 为抗锯齿单点，无文字笔画。\n"
     "> 样张：`art/_review/batch11/contact_batch11_cards.png`、`contact_batch11_64.png`、`contact_batch11_raw.png`、`compare_pack_color_batch11.png`（8 包并排）、`compare_pack_progress_batch11.png`（80/80）、`compare_tone_batch11.png`（试点四档）、`compare_nearhue_batch11.png`（sunder↔true）、`watermark_check_batch11.png`。\n\n---"),

    ("## 7. 收尾：最后 1 包（10 张待建）", "## 7. 收官：8 包 80 张全部完成"),

    ("**资产盘点（2026-11-09 · 批次⑩ 后）**：`art/2d/cards/` 已有 **70 张**正式卡面（core / cinder / rime / pierce / arc / sunder / hex 各 10 张），其余 **10 张（`true`）尚未生成**；批次① 的 10 张原图只留在 `art/_review/batch1/`，从未进入正式目录。后续是「新建」而非重绘旧图。进度总览见 `art/_review/batch10/compare_pack_progress_batch10.png`。",
     "**资产盘点（2026-11-09 · 批次⑪ 收官）**：`art/2d/cards/` 已有 **80 张**正式卡面（8 包各 10 张），`_v1_t.png` / `_v1_460.png` 各 80 个、`.import` 160 个且 uid 全唯一，**无待建卡面**；批次① 的 10 张原图只留在 `art/_review/batch1/`，从未进入正式目录。进度总览见 `art/_review/batch11/compare_pack_progress_batch11.png`。后续只剩 Godot 重导入 / export 与 UI 实机验证。"),

    ("| `true` | 湮灭包 | 警报红 `#FF2E4E` | 10 | ⚪ 无卡面资产 |",
     "| `true` | 湮灭包 | 警报红 `#FF2E4E` | 10 | ✅ **批次⑪ 整包落地**（`--lift-pack` 第三次复用，v1.7 真红防串色包），cov 64.3–81.7% |"),

    ("**每包流程**：从 `card-prompt-bank-v2.json` 取 10 张的 `structure/feature/accent_block` + 该包的 `pack_palette`（`hex/name/hue_word/shadow_word`）→ 按 §3.1 做 3/4 转译 → **先出 1 张**同族比对 → 通过后出剩余 9 张 → `card_batch3_process.py --batch <批次> --dominant [档位]` 批量后处理 → 接触表 + 量化自检 → 按同名规则落盘 → 卡框样张归档。单包约 10 张 × 5–10 积分；批次⑩ 实际 10 张一次过检、未重出任何 AI 图。",
     "**每包流程（8 包已全部走完）**：从 `card-prompt-bank-v2.json` 取 10 张的 `structure/feature/accent_block` + 该包的 `pack_palette`（`hex/name/hue_word/shadow_word`）→ 按 §3.1 做 3/4 转译 → **先出 1 张**同族比对 → 通过后出剩余 9 张 → `card_batch3_process.py --batch <批次> --dominant [档位]` 批量后处理 → 接触表 + 量化自检 → 按同名规则落盘 → 卡框样张归档。单包约 10 张 × 5–10 积分；批次⑪ 实际 11 次生图（10 张 + `Eraser` 重出 1 张）。**后续没有新包要建**。"),

    ("**后处理档位四选一**（整包统一、互斥，先出 1 张试点测 p50 再定）：默认档白场 155（`core` / `cinder`）｜ `--bright-pack`（青 / 金，§4.2）｜ `--mid-pack`（星紫等 L≈90–140，§4.3）｜ `--lift-pack`（暗板占比高的中明度包 + 低明度包，§4.4 / §4.5）。`rime` / `pierce` 已验证 21 张、`arc` 10 张、`sunder` + `hex` 共 20 张。",
     "**后处理档位四选一**（整包统一、互斥，先出 1 张试点测 p50 再定）：默认档白场 155（`core` / `cinder`）｜ `--bright-pack`（青 / 金，§4.2）｜ `--mid-pack`（星紫等 L≈90–140，§4.3）｜ `--lift-pack`（暗板占比高的中明度包 + 低明度包，§4.4 / §4.5）。收官统计：`rime` / `pierce` 21 张、`arc` 10 张、`sunder` + `hex` + `true` 30 张、`core` / `cinder` 20 张，合计 **80 张全部过检**。"),

    ("**青色系包**（`rime` / `hex` 均已验证）模板里补 `clearly brighter and more saturated than neutral blue-grey steel`；**低明度暗包色**（`hex`）再加主色提亮句，别整机糊成一团。`rime`↔`hex` 近色对已在 `compare_nearhue_batch10.png` 并排复核解除。剩余 `true` 推进时仍按铁律 5 出 1 张试点测 p50 再定档位，不预设。",
     "**青色系包**（`rime` / `hex`）模板里补 `clearly brighter and more saturated than neutral blue-grey steel`；**低明度包**（`hex` / `true`）再加主色提亮句，别整机糊成一团；**真红包**（`true`）再加防串色句 `NOT pink, NOT magenta, NOT crimson`。两对近色对 `rime`↔`hex`（`compare_nearhue_batch10.png`）与 `sunder`↔`true`（`compare_nearhue_batch11.png`）均已并排复核解除。"),

    ("| 6 | 80 张卡中已有 **70 张**正式卡面（core / cinder / rime / pierce / arc / sunder / hex 各 10），其余 **10 张（`true`）尚未生成** | 按 §7 推进最后一包 `true` 警报红 `#FF2E4E`，仍按铁律 5 先出 1 张同族试点，测 p50 后在四档里定一个整包档位 |",
     "| 6 | 80 张卡面**已全部落盘**（8 包各 10 张），无待建卡 | ✅ 批次⑪ 收官解除；后续只做 Godot 4.7.2 重导入与 export，不再出图 |"),

    ("| 7 | 最后 1 包 `true` 警报红**尚未出图验证**；近色对 `sunder`↔`true` 的风险未解除；中性色在覆盖率自检中免检 | 低明度 `hex` 深青已在批次⑩ 验证（`--lift-pack` 复用）且 `rime`↔`hex` 已并排复核解除；`true` 出图后仍需与 `sunder` 并排复核剪影与明度差（`#FF2E4E` 与 `#E8437F` 是最近的一对） |",
     "| 7 | 近色对风险**全部解除**；中性色在覆盖率自检中免检 | ✅ `rime`↔`hex` 于批次⑩、`sunder`↔`true` 于批次⑪ 并排复核通过（真红防串色补句生效）；若日后调整包色，须重新并排复核 |"),

    ("| 9 | `Whiteout` 在 `x≥70% & y≥90%` 检查区有 37 个不透明像素；批次⑧ 的 `Storm` 393 / `Thunderhead` 256 / `Arc` 5、批次⑨ 的 `Breaker` 304、批次⑩ 的 `Wither` 245 同理 | 均人工放大复核为**主体部件边缘色块**（底座撑脚 / 钻杆尖端 / 抗锯齿），透明底图上无「AI生成 WORKBUDDY>」文字，属构图边界例外而非水印残留。留档 `art/_review/batch8/watermark_check_batch8.png`、`art/_review/batch9/watermark_check_batch9.png`、`art/_review/batch10/watermark_check_batch10.png`；若日后统一卡面尺寸，优先重出偏宽偏低 / 部件伸出的卡并加 `compact narrow base` |",
     "| 9 | `Whiteout` 在 `x≥70% & y≥90%` 检查区有 37 个不透明像素；批次⑧ 的 `Storm` 393 / `Thunderhead` 256 / `Arc` 5、批次⑨ 的 `Breaker` 304、批次⑩ 的 `Wither` 245、批次⑪ 的 `Soulpiercer` 1 同理 | 均人工放大复核为**主体部件边缘色块 / 抗锯齿单点**（底座撑脚 / 钻杆尖端），透明底图上无「AI生成 WORKBUDDY>」文字，属构图边界例外而非水印残留。留档 `art/_review/batch8/watermark_check_batch8.png`、`art/_review/batch9/watermark_check_batch9.png`、`art/_review/batch10/watermark_check_batch10.png`、`art/_review/batch11/watermark_check_batch11.png`；若日后统一卡面尺寸，优先重出偏宽偏低 / 部件伸出的卡并加 `compact narrow base` |"),

    ("| 10 | **新增卡面的 `.import` 不会自动出现**（本机无 Godot 编辑器） | 批次⑥ 补 20 个、批次⑦ 补 18 个、批次⑧ 补 20 个、批次⑨ 补 20 个、批次⑩ 补 20 个，现 `art/2d/cards/` 共 **140 个 `.import` 且 uid 全唯一**（`uid://` 随机唯一，`path` = `md5(res:// 路径)`）。最后一包新卡同样要补；最终仍需 Godot 4.7.2 打开项目重导入生成 `.ctex` 并重新 export |",
     "| 10 | **新增卡面的 `.import` 不会自动出现**（本机无 Godot 编辑器） | 批次⑥ 补 20 个、批次⑦ 补 18 个、批次⑧ 补 20 个、批次⑨ 补 20 个、批次⑩ 补 20 个、批次⑪ 补 20 个，现 `art/2d/cards/` 共 **160 个 `.import` 且 uid 全唯一**（`uid://` 随机唯一，`path` = `md5(res:// 路径)`），全部新卡已补齐；最终仍需 Godot 4.7.2 打开项目重导入生成 `.ctex` 并重新 export |"),

    ("| **低明度深青 v1.6 原图 / 样张 / 对比（现行）** | `art/_review/batch10/raw_*.png`、`mock_*.png`、`contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`；复核留档脚本 `make_review_batch10.py`、`update_standard_batch10.py` |",
     "| 低明度深青 v1.6 原图 / 样张 / 对比 | `art/_review/batch10/raw_*.png`、`mock_*.png`、`contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`；复核留档脚本 `make_review_batch10.py`、`update_standard_batch10.py` |\n"
     "| **真红收官 v1.7 原图 / 样张 / 对比（现行）** | `art/_review/batch11/raw_*.png`、`prev_Eraser_rejected.png`（重出留档）、`mock_*.png`、`contact_batch11_cards.png`、`contact_batch11_64.png`、`contact_batch11_raw.png`、`compare_pack_color_batch11.png`（8 包并排）、`compare_pack_progress_batch11.png`（80/80）、`compare_tone_batch11.png`（试点四档）、`compare_nearhue_batch11.png`（sunder↔true）、`watermark_check_batch11.png`；复核留档脚本 `make_review_batch11.py`、`update_standard_batch11.py` |"),

    ("| 对象 / 主色 / **包色真源** | `design/art/card-prompt-bank-v2.json` **v2.6**（`pack_palette` 的 `hex/name/hue_word/shadow_word`、`pack_color_rule`、`accent_by_pack`、`cards[*].accent`、`postprocess_hint.bright_pack` / `.mid_pack` / `.lift_pack`）；镜像常量 `tools/build_card_prompt_bank_v2.py::PACK_ACCENT`（🔴 勿运行重建）；UI 侧 `scripts/ui/ui_style.gd::PACK_COLORS` |",
     "| 对象 / 主色 / **包色真源** | `design/art/card-prompt-bank-v2.json` **v2.7**（`pack_palette` 的 `hex/name/hue_word/shadow_word`、`pack_color_rule`、`accent_by_pack`、`cards[*].accent`、`postprocess_hint.bright_pack` / `.mid_pack` / `.lift_pack` / `.completion`）；镜像常量 `tools/build_card_prompt_bank_v2.py::PACK_ACCENT`（🔴 勿运行重建）；UI 侧 `scripts/ui/ui_style.gd::PACK_COLORS` |"),

    ("| 2026-11-09 | **批次⑩** hex 咒术包 10 张整包落地（深青 `#1A6B7D`），`--lift-pack` 一次过检（p50 101–138 / p85 161–182 / cov 88.5–99.6% / alpha 全 255）；量化色相直方图确认无第二色相；`Wither` 检查区 245 px 复核为底座撑脚；`rime`↔`hex` 近色对并排复核解除；补 20 个 `.import`（共 140 个 uid 唯一）；正式卡面达 **70 张 / 80（7 包完成）**。交付 `art/_review/batch10/contact_batch10_cards.png`、`compare_pack_color_batch10.png`、`compare_pack_progress_batch10.png`、`compare_nearhue_batch10.png` |",
     "| 2026-11-09 | **批次⑩** hex 咒术包 10 张整包落地（深青 `#1A6B7D`），`--lift-pack` 一次过检（p50 101–138 / p85 161–182 / cov 88.5–99.6% / alpha 全 255）；量化色相直方图确认无第二色相；`Wither` 检查区 245 px 复核为底座撑脚；`rime`↔`hex` 近色对并排复核解除；补 20 个 `.import`（共 140 个 uid 唯一）；正式卡面达 **70 张 / 80（7 包完成）**。交付 `art/_review/batch10/contact_batch10_cards.png`、`compare_pack_color_batch10.png`、`compare_pack_progress_batch10.png`、`compare_nearhue_batch10.png` |\n"
     "| 2026-11-09 | **v1.7 真红防串色 + 第三次复用 lift-pack**：批次⑪ `Oblivion` 试点四档 72 / 55 / 89 / 101，确认警报红 `#FF2E4E`（L≈93）同样复用 `--lift-pack`，不新增第五档、不放宽门槛；§3.1 注把低明度主色提亮句通用化为 `Lift the {hue} main plate`，并新增 `NOT pink, NOT magenta, NOT crimson` 防串色句。`card-prompt-bank-v2.json` 升 **v2.7**（`lift_pack.applies_to` 加 `true`、`postprocess_hint.completion`），`anchor_ref` 同步 v1.7 |\n"
     "| 2026-11-09 | **批次⑪ 收官** true 湮灭包 10 张整包落地（警报红 `#FF2E4E`），`--lift-pack` 全过检（p50 88–108 / p85 118–150 / cov 64.3–81.7% / alpha 全 255）；`Eraser` 因锚点带出青色炮口重出 1 张（亮青点缀 0.50%→0.11%，剪影改竖直方塔）；`Obliterator` / `Wraith` 防脸化转译通过；`sunder`↔`true` 近色对并排复核解除，至此全部近色对已复核；补 20 个 `.import`（共 160 个 uid 唯一）。**正式卡面 80 / 80，8 包全部完成**。交付 `art/_review/batch11/contact_batch11_cards.png`、`compare_pack_color_batch11.png`、`compare_pack_progress_batch11.png`、`compare_nearhue_batch11.png` |"),
]

BANK_PAIRS = [
    ('"version": "v2.6",', '"version": "v2.7",'),
    ('"anchor_ref": "design/art/card-art-generation-standard-v1.md v1.6 (3/4 image-to-image, pack color as dominant tone; bright-pack / mid-pack / lift-pack tone variants by pack color luminance; lift-pack also validated on low-luminance hex deep teal)",',
     '"anchor_ref": "design/art/card-art-generation-standard-v1.md v1.7 (3/4 image-to-image, pack color as dominant tone; bright-pack / mid-pack / lift-pack tone variants by pack color luminance; lift-pack validated on sunder/hex/true; all 8 packs complete, 80/80 cards)",'),
    ('  "pack_color_coverage_min_percent": 40,',
     '  "pack_color_coverage_min_percent": 40,\n  "completion": "80/80 cards, 8/8 packs validated (2026-11-09); no pending pack",'),
    ('   "note": "v1.4: mid-luminance pack colors (L about 90-140, e.g. star-violet) are too dark under default white 155 and get darker under --bright-pack; lift the shadow floor instead of pushing highlights. Mutually exclusive with the other tone flags; use with --dominant, whole pack only, never per card. sunder needs the higher --lift-pack floor (v1.5); hex deep teal is validated with --lift-pack (v1.6); only true still needs a 1-card pilot before adopting."',
     '   "note": "v1.4: mid-luminance pack colors (L about 90-140, e.g. star-violet) are too dark under default white 155 and get darker under --bright-pack; lift the shadow floor instead of pushing highlights. Mutually exclusive with the other tone flags; use with --dominant, whole pack only, never per card. sunder needs the higher --lift-pack floor (v1.5); hex deep teal (v1.6) and true alert red (v1.7) are validated with --lift-pack. All 8 packs complete."'),
    ('   "applies_to": ["sunder", "hex"],', '   "applies_to": ["sunder", "hex", "true"],'),
    ('   "note": "v1.5 + v1.6: packs with a very high share of dark shadow plates (sunder magenta-crimson #E8437F) or a low-luminance pack color (hex deep teal #1A6B7D, L about 91) fail p50 under --mid-pack; four-tier pilot on Hex: default 73 / bright-pack 55 / mid-pack 89 / lift-pack 101, so reuse 145/58 rather than adding a fifth tier. Whole 10-card hex pack passed at p50 101-138, cov 88.5-99.6%. Mutually exclusive with --bright-pack / --mid-pack; use with --dominant, whole pack only, never per card. Only true still needs a 1-card pilot."',
     '   "note": "v1.5 + v1.6 + v1.7: packs with a very high share of dark shadow plates (sunder magenta-crimson #E8437F) or a low-luminance pack color (hex deep teal #1A6B7D L about 91, true alert red #FF2E4E L about 93) fail p50 under --mid-pack. Four-tier pilots: Hex 73/55/89/101, Oblivion 72/55/89/101 -> reuse 145/58 rather than adding a fifth tier. Whole packs passed: sunder p50 87-127, hex 101-138, true 88-108 (true p85 is naturally lower because red has only 0.2126 luminance weight). Mutually exclusive with --bright-pack / --mid-pack; use with --dominant, whole pack only, never per card. All 8 packs complete."'),
]

TOOL_PAIRS = [
    ("  py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）",
     "  py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）\n"
     "  py -3.9 tools/card_batch3_process.py --batch batch11 --dominant --lift-pack   # v1.7 真红收官（第三次复用，80/80）"),
    ("p50 101-138 / cov 88.5-99.6% 全过检。三档互斥，同样整包统一使用。",
     "p50 101-138 / cov 88.5-99.6% 全过检。批次⑪ 警报红 true（#FF2E4E, L≈93）四档试点\n"
     "72 / 55 / 89 / 101，同样复用本档，整包 10 张 p50 88-108 / cov 64.3-81.7% 全过检；\n"
     "至此 --lift-pack 共 30 张验证通过，8 包 80 张卡面全部完成。三档互斥，整包统一使用。"),
]

if __name__ == "__main__":
    apply(DOC, DOC_PAIRS)
    apply(BANK, BANK_PAIRS)
    apply(TOOL, TOOL_PAIRS)
    print("== v1.7 / v2.7 收官同步完成 ==")
