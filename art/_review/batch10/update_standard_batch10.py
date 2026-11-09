# -*- coding: utf-8 -*-
"""批次⑩ 文档 / 提示词库 / 工具说明同步（v1.5 -> v1.6, v2.5 -> v2.6）。

一次性精确替换：每处 old 必须在文件中恰好命中一次，否则整体失败不写盘。
"""
import io
import os
import sys

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
            raise SystemExit("!! %s 第 %d 处替换命中 %d 次（应为 1）：%s"
                             % (os.path.relpath(path, ROOT), i + 1, n, old[:70]))
        text = text.replace(old, new, 1)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("updated", os.path.relpath(path, ROOT), "|", len(pairs), "处")


DOC_PAIRS = []

# 1) 状态头 + v1.6 变更说明
DOC_PAIRS.append((
    "> 状态：🟢 **当前生效 · v1.5**（2026-11-09 立 / 同日六次更新）。适用于 `art/2d/cards/card_*_v1_{t,460}.png` 的全部新增与重绘。当前进度 **60 / 80 张（6 包完成）**，见 §7。",
    "> 状态：🟢 **当前生效 · v1.6**（2026-11-09 立 / 同日七次更新）。适用于 `art/2d/cards/card_*_v1_{t,460}.png` 的全部新增与重绘。当前进度 **70 / 80 张（7 包完成）**，见 §7。\n"
    "> 🆕 **v1.6 变更（批次⑩低明度包色）**：`hex` 深青 `#1A6B7D`（L≈91，8 包里最低明度）按铁律 5 先出 `Hex` 试点，四档实测默认 73 / `--bright-pack` 55 / `--mid-pack` 89 / **`--lift-pack` 101**，确认**复用 v1.5 的 `--lift-pack`**（不新增第五档、不改任何参数）。整包 10 张一次过检（p50 101–138 / cov 88.5–99.6%），并完成 `rime`↔`hex` 近色对并排复核。**门槛、提示词模板、包色一律未动**。详见 §4.5、§5.10。"))

# 2) §0 速查表校色行
DOC_PAIRS.append((
    "| 校色 | `--black 35 --white 155 --floor 26 --ceil 235` **＋ `--protect-mode remap`**；**亮色相包（青/金）改 `--white 230 --bright-threshold 250`**；**中明度包（星紫）改 `--white 145 --floor 42`**；**暗板占比高的中明度包（噬品红）改 `--white 145 --floor 58`** | `tools/card_tone_levels.py` |",
    "| 校色 | `--black 35 --white 155 --floor 26 --ceil 235` **＋ `--protect-mode remap`**；**亮色相包（青/金）改 `--white 230 --bright-threshold 250`**；**中明度包（星紫）改 `--white 145 --floor 42`**；**暗板占比高 / 低明度包（噬品红、深青）改 `--white 145 --floor 58`** | `tools/card_tone_levels.py` |"))

# 3) §3.1 青色系包补句
DOC_PAIRS.append((
    "> 青色系包（`rime` / `hex`）与蓝钢灰色相接近，需在 COLOUR RULE 里补一句 `clearly brighter and more saturated than neutral blue-grey steel`（批次⑤ Glacier 实测有效）。",
    "> 青色系包（`rime` / `hex`）与蓝钢灰色相接近，需在 COLOUR RULE 里补一句 `clearly brighter and more saturated than neutral blue-grey steel`（批次⑤ Glacier 实测有效）；**低明度深青包再加一句 `Lift the teal main plate to a readable mid-tone brightness`**（批次⑩ `Hex` 试点实测有效，见 §4.5），模板其余部分冻结。"))

# 4) §4 批量命令示例
DOC_PAIRS.append((
    "py -3.9 tools/card_batch3_process.py --batch batch9 --dominant --lift-pack    # v1.5 高抬暗板（噬品红）",
    "py -3.9 tools/card_batch3_process.py --batch batch9 --dominant --lift-pack    # v1.5 高抬暗板（噬品红）\n"
    "py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）"))

# 5) §4.4 适用范围 -> 插入 §4.5 新小节
DOC_PAIRS.append((
    "**适用范围**：`sunder` 噬品红已验证 10 张；`true` 警报红 / `hex` 深青推进时按 §4.3 / §4.4 的探测方法先出 1 张试点，在四档里定一个整包档位，不预设。`core` / `cinder` 默认档、`rime` / `pierce` `--bright-pack`、`arc` `--mid-pack` 互不干扰。\n\n---",
    "**适用范围**：`sunder` 噬品红已验证 10 张；`hex` 深青在批次⑩ 按同一方法验证并复用本档（见 §4.5）；`true` 警报红仍须先出 1 张试点再定档。`core` / `cinder` 默认档、`rime` / `pierce` `--bright-pack`、`arc` `--mid-pack` 互不干扰。\n\n"
    "### 4.5 低明度包色复用 `--lift-pack`（v1.6 · 批次⑩）\n\n"
    "**问题**：`hex` 深青 `#1A6B7D` 的 L≈91 是 8 包里最低，§2.1 早已预警「整机铺开会发闷」。按铁律 5 先出 `Hex` 试点，四档逐档实测：\n\n"
    "| 档位（白场 / floor） | p50 | p85 | cov | 判定 |\n|---|---|---|---|---|\n"
    "| 默认 155 / 26 | 73 | 144 | 97.1% | ✗ 偏离 |\n"
    "| `--bright-pack` 230 / 26 | 55 | 99 | 97.6% | ✗ 偏离（方向相反，见 §4.3） |\n"
    "| `--mid-pack` 145 / 42 | 89 | 161 | 97.9% | ✓ 但仅余 9 点裕度 |\n"
    "| **`--lift-pack` 145 / 58** | **101** | **167** | **98.2%** | **✓ 采用** |\n\n"
    "**决议**：不新增第五档、不逐卡微调，直接复用 `--lift-pack`。深青与噬品红明度差约 60，但根因相同（三阶里的 `deep ocean teal` 暗板 + 深藏青描边占比高），floor 58 已足够；整包 10 张放量后 p50 101–138，最低值仍高出下界 21 点，档位有余量。四档并排见 `art/_review/batch10/compare_tone_batch10.png`：lift 档描边仍深藏青、暗板层次未糊、无发灰或过曝。\n\n"
    "**适用范围更新**：`--lift-pack` 现已在 `sunder`（10 张）+ `hex`（10 张）共 20 张上验证通过；`--mid-pack` 仅 `arc`、`--bright-pack` 仅 `rime` / `pierce`。剩余 `true` 警报红 `#FF2E4E` 仍按铁律 5 出 1 张试点在四档里定档，不预设。\n\n---"))

# 6) §5.1 门槛说明
DOC_PAIRS.append((
    "> 🔴 **v1.3 / v1.4 / v1.5 的门槛都没有放宽**：亮色相包走 `--bright-pack`、中明度包走 `--mid-pack` / `--lift-pack` 后，仍按「主色调族」这一列（p50 80–185 / p85 ≤215 / cov ≥40%）验收。批次⑥ 11 张、批次⑧ 10 张、批次⑨ 10 张全部达标，靠的都是修后处理而不是调门槛。禁止为了过检改阈值、禁止逐张单独换档。",
    "> 🔴 **v1.3 / v1.4 / v1.5 / v1.6 的门槛都没有放宽**：亮色相包走 `--bright-pack`、中明度 / 低明度包走 `--mid-pack` / `--lift-pack` 后，仍按「主色调族」这一列（p50 80–185 / p85 ≤215 / cov ≥40%）验收。批次⑥ 11 张、批次⑧ 10 张、批次⑨ 10 张、批次⑩ 10 张全部达标，靠的都是修后处理（或复用已验证档位）而不是调门槛。禁止为了过检改阈值、禁止逐张单独换档。"))

# 7) 插入 §5.10
DOC_PAIRS.append((
    "> 样张：`art/_review/batch9/contact_batch9_cards.png`、`contact_batch9_64.png`、`contact_batch9_raw.png`、`compare_pack_color_batch9.png`（6 包并排）、`compare_pack_progress_batch9.png`（60/80）、`compare_tone_batch9.png`（试点四档）、`compare_tone_lift_batch9.png`（floor 抬升描边复核）、`watermark_check_batch9.png`。\n\n---",
    "> 样张：`art/_review/batch9/contact_batch9_cards.png`、`contact_batch9_64.png`、`contact_batch9_raw.png`、`compare_pack_color_batch9.png`（6 包并排）、`compare_pack_progress_batch9.png`（60/80）、`compare_tone_batch9.png`（试点四档）、`compare_tone_lift_batch9.png`（floor 抬升描边复核）、`watermark_check_batch9.png`。\n\n"
    "### 5.10 批次⑩ · 咒术包整包落地（2026-11-09 · **v1.6 低明度深青**）\n\n"
    "`py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack` 一次跑完 10 张（按铁律 5 先出 `Hex` 试点、通过后才放量其余 9 张；从 `raw_*.png` 幂等重跑，未重出任何 AI 图）：\n\n"
    "| 卡 | p50 | p85 | alpha p10 | 包色覆盖率 | 水印区 | 判定 |\n|---|---|---|---|---|---|---|\n"
    "| Blight | 121 | 166 | 255 | 95.7% | 0 | ✅ |\n"
    "| Curse | 105 | 180 | 255 | 99.6% | 0 | ✅ |\n"
    "| Executioner | 101 | 176 | 255 | 88.5% | 0 | ✅ |\n"
    "| Hex | 101 | 167 | 255 | 98.2% | 0 | ✅ 试点 |\n"
    "| Hexer | 108 | 177 | 255 | 92.6% | 0 | ✅ |\n"
    "| Malison | 102 | 161 | 255 | 99.4% | 0 | ✅ |\n"
    "| Omen | 109 | 182 | 255 | 92.5% | 0 | ✅ |\n"
    "| Plague | 109 | 161 | 255 | 96.1% | 0 | ✅ |\n"
    "| Rune | 138 | 179 | 255 | 97.8% | 0 | ✅ 本批最亮 |\n"
    "| Wither | 103 | 164 | 255 | 94.3% | 🟡 245 | ✅ 底座撑脚，见下 |\n\n"
    "> 10 张全过检：p50 101–138 / p85 161–182 / cov 88.5–99.6% / alpha 全 255。深青覆盖率是历批最高（此前最高为耀青 98.1%），原因是低明度高饱和青绿几乎铺满机身，色相判定极少出界。\n"
    "> 人工复核：接触表 10 张同族（粗描边 / 分层装甲板 / 面板缝 / 铆钉 / 3/4 构图一致），剪影互不重复；64px 仍能读出穹顶、悬臂、铡刀架、阶梯基座、笼柱等轮廓；卡框合成无部件被边框压住。`Omen` 的 eye-shaped sigil 是提示词库原设功能件，属单眼几何徽记而非「两个圆件并排」的脸化布局；量化色相直方图显示各卡饱和像素 79–99% 落在深青主色及相邻分箱，**无第二色相**（拱门 / 笼柱内的暗紫为低饱和内部阴影）。\n"
    "> `Wither` 检查区 245 px 经 `watermark_check_batch10.png` 放大复核为**底座右撑脚的青色斜面**，非文字笔画，属构图边界例外。\n"
    "> 近色对复核：`compare_nearhue_batch10.png` 把 rime 耀青 3 张与 hex 深青 3 张并排，耀青 L≈179、深青 L≈91，明度差近一倍，一眼可分；`sunder`↔`true` 仍待 `true` 出图后复核。\n"
    "> 样张：`art/_review/batch10/contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`。\n\n---"))

# 8) §7 标题 + 盘点段
DOC_PAIRS.append((
    "## 7. 扩展到其余 2 包（20 张待建）",
    "## 7. 收尾：最后 1 包（10 张待建）"))
DOC_PAIRS.append((
    "**资产盘点（2026-11-09 · 批次⑨ 后）**：`art/2d/cards/` 已有 **60 张**正式卡面（core / cinder / rime / pierce / arc / sunder 各 10 张），其余 **20 张尚未生成**；批次① 的 10 张原图只留在 `art/_review/batch1/`，从未进入正式目录。后续是「新建」而非重绘旧图。进度总览见 `art/_review/batch9/compare_pack_progress_batch9.png`。",
    "**资产盘点（2026-11-09 · 批次⑩ 后）**：`art/2d/cards/` 已有 **70 张**正式卡面（core / cinder / rime / pierce / arc / sunder / hex 各 10 张），其余 **10 张（`true`）尚未生成**；批次① 的 10 张原图只留在 `art/_review/batch1/`，从未进入正式目录。后续是「新建」而非重绘旧图。进度总览见 `art/_review/batch10/compare_pack_progress_batch10.png`。"))

# 9) §7 状态表 hex / true 行
DOC_PAIRS.append((
    "| `hex` | 咒术包 | 深青 `#1A6B7D` | 10 | ⚪ 无卡面资产 |\n| `true` | 湮灭包 | 警报红 `#FF2E4E` | 10 | ⚪ 无卡面资产 |",
    "| `hex` | 咒术包 | 深青 `#1A6B7D` | 10 | ✅ **批次⑩ 整包落地**（`--lift-pack` 复用，v1.6 低明度验证包），cov 88.5–99.6% |\n| `true` | 湮灭包 | 警报红 `#FF2E4E` | 10 | ⚪ 无卡面资产 |"))

# 10) §7 流程段 / 档位段 / 青色系段
DOC_PAIRS.append((
    "单包约 10 张 × 5–10 积分。",
    "单包约 10 张 × 5–10 积分；批次⑩ 实际 10 张一次过检、未重出任何 AI 图。"))
DOC_PAIRS.append((
    "**后处理档位四选一**（整包统一、互斥，先出 1 张试点测 p50 再定）：默认档白场 155（`core` / `cinder`）｜ `--bright-pack`（青 / 金，§4.2）｜ `--mid-pack`（星紫等 L≈90–140，§4.3）｜ `--lift-pack`（暗板占比更高的中明度包，如噬品红，§4.4）。`rime` / `pierce` 已验证 21 张、`arc` 10 张、`sunder` 10 张。",
    "**后处理档位四选一**（整包统一、互斥，先出 1 张试点测 p50 再定）：默认档白场 155（`core` / `cinder`）｜ `--bright-pack`（青 / 金，§4.2）｜ `--mid-pack`（星紫等 L≈90–140，§4.3）｜ `--lift-pack`（暗板占比高的中明度包 + 低明度包，§4.4 / §4.5）。`rime` / `pierce` 已验证 21 张、`arc` 10 张、`sunder` + `hex` 共 20 张。"))
DOC_PAIRS.append((
    "**青色系包**（`rime` 已验证 / `hex` 待做）模板里补 `clearly brighter and more saturated than neutral blue-grey steel`；**暗包色**（`hex`）主色提亮到中明度，别整机糊成一团。剩余 `hex` / `true` 推进时先按铁律 5 出 1 张试点测 p50 再定档位，不预设。",
    "**青色系包**（`rime` / `hex` 均已验证）模板里补 `clearly brighter and more saturated than neutral blue-grey steel`；**低明度暗包色**（`hex`）再加主色提亮句，别整机糊成一团。`rime`↔`hex` 近色对已在 `compare_nearhue_batch10.png` 并排复核解除。剩余 `true` 推进时仍按铁律 5 出 1 张试点测 p50 再定档位，不预设。"))

# 11) §8 待办 #6 / #7 / #9 / #10
DOC_PAIRS.append((
    "| 6 | 80 张卡中已有 **60 张**正式卡面（core / cinder / rime / pierce / arc / sunder 各 10），其余 **20 张尚未生成** | 按 §7 逐包推进；下一批从 `hex` 深青 `#1A6B7D` 或 `true` 警报红 `#FF2E4E` 开始，仍按铁律 5 先出 1 张同族试点，测 p50 后在默认 / `--bright-pack` / `--mid-pack` / `--lift-pack` 四档里定一个整包档位 |",
    "| 6 | 80 张卡中已有 **70 张**正式卡面（core / cinder / rime / pierce / arc / sunder / hex 各 10），其余 **10 张（`true`）尚未生成** | 按 §7 推进最后一包 `true` 警报红 `#FF2E4E`，仍按铁律 5 先出 1 张同族试点，测 p50 后在四档里定一个整包档位 |"))
DOC_PAIRS.append((
    "| 7 | 剩余 2 包（`hex` 深青 / `true` 警报红）**尚未出图验证**；低饱和暗包色 `hex`、近色对 `sunder`↔`true`、`rime`↔`hex` 的风险未解除；中性色在覆盖率自检中免检 | `arc` / `sunder` 已分别验证 `--mid-pack` / `--lift-pack`，但两包仍须逐包试点；必要时按 §2.1 把整机主色提亮到中明度；`true` 出图后与 `sunder` 并排复核剪影与明度差（`#FF2E4E` 与 `#E8437F` 是剩余最近的一对） |",
    "| 7 | 最后 1 包 `true` 警报红**尚未出图验证**；近色对 `sunder`↔`true` 的风险未解除；中性色在覆盖率自检中免检 | 低明度 `hex` 深青已在批次⑩ 验证（`--lift-pack` 复用）且 `rime`↔`hex` 已并排复核解除；`true` 出图后仍需与 `sunder` 并排复核剪影与明度差（`#FF2E4E` 与 `#E8437F` 是最近的一对） |"))
DOC_PAIRS.append((
    "| 9 | `Whiteout` 在 `x≥70% & y≥90%` 检查区有 37 个不透明像素；批次⑧ 的 `Storm` 393 / `Thunderhead` 256 / `Arc` 5、批次⑨ 的 `Breaker` 304 同理 | 均人工放大复核为**主体部件边缘色块**（底座撑脚 / 钻杆尖端 / 抗锯齿），透明底图上无「AI生成 WORKBUDDY>」文字，属构图边界例外而非水印残留。留档 `art/_review/batch8/watermark_check_batch8.png`、`art/_review/batch9/watermark_check_batch9.png`；若日后统一卡面尺寸，优先重出偏宽偏低 / 部件伸出的卡并加 `compact narrow base` |",
    "| 9 | `Whiteout` 在 `x≥70% & y≥90%` 检查区有 37 个不透明像素；批次⑧ 的 `Storm` 393 / `Thunderhead` 256 / `Arc` 5、批次⑨ 的 `Breaker` 304、批次⑩ 的 `Wither` 245 同理 | 均人工放大复核为**主体部件边缘色块**（底座撑脚 / 钻杆尖端 / 抗锯齿），透明底图上无「AI生成 WORKBUDDY>」文字，属构图边界例外而非水印残留。留档 `art/_review/batch8/watermark_check_batch8.png`、`art/_review/batch9/watermark_check_batch9.png`、`art/_review/batch10/watermark_check_batch10.png`；若日后统一卡面尺寸，优先重出偏宽偏低 / 部件伸出的卡并加 `compact narrow base` |"))
DOC_PAIRS.append((
    "| 10 | **新增卡面的 `.import` 不会自动出现**（本机无 Godot 编辑器） | 批次⑥ 补 20 个、批次⑦ 补 18 个、批次⑧ 补 20 个、批次⑨ 补 20 个，现 `art/2d/cards/` 共 **120 个 `.import` 且 uid 全唯一**（`uid://` 随机唯一，`path` = `md5(res:// 路径)`）。后续新卡同样要补；最终仍需 Godot 4.7.2 打开项目重导入生成 `.ctex` 并重新 export |",
    "| 10 | **新增卡面的 `.import` 不会自动出现**（本机无 Godot 编辑器） | 批次⑥ 补 20 个、批次⑦ 补 18 个、批次⑧ 补 20 个、批次⑨ 补 20 个、批次⑩ 补 20 个，现 `art/2d/cards/` 共 **140 个 `.import` 且 uid 全唯一**（`uid://` 随机唯一，`path` = `md5(res:// 路径)`）。最后一包新卡同样要补；最终仍需 Godot 4.7.2 打开项目重导入生成 `.ctex` 并重新 export |"))

# 12) §9 相关文件
DOC_PAIRS.append((
    "| **高抬暗板 v1.5 原图 / 样张 / 对比（现行）** | `art/_review/batch9/raw_*.png`、`mock_*.png`、`contact_batch9_cards.png`、`contact_batch9_64.png`、`contact_batch9_raw.png`、`compare_pack_color_batch9.png`（6 包并排）、`compare_pack_progress_batch9.png`（60/80）、`compare_tone_batch9.png`（试点四档）、`compare_tone_lift_batch9.png`（floor 抬升描边复核）、`watermark_check_batch9.png` |",
    "| 高抬暗板 v1.5 原图 / 样张 / 对比 | `art/_review/batch9/raw_*.png`、`mock_*.png`、`contact_batch9_cards.png`、`contact_batch9_64.png`、`contact_batch9_raw.png`、`compare_pack_color_batch9.png`（6 包并排）、`compare_pack_progress_batch9.png`（60/80）、`compare_tone_batch9.png`（试点四档）、`compare_tone_lift_batch9.png`（floor 抬升描边复核）、`watermark_check_batch9.png` |\n"
    "| **低明度深青 v1.6 原图 / 样张 / 对比（现行）** | `art/_review/batch10/raw_*.png`、`mock_*.png`、`contact_batch10_cards.png`、`contact_batch10_64.png`、`contact_batch10_raw.png`、`compare_pack_color_batch10.png`（7 包并排）、`compare_pack_progress_batch10.png`（70/80）、`compare_tone_batch10.png`（试点四档）、`compare_nearhue_batch10.png`（rime↔hex）、`watermark_check_batch10.png`；复核留档脚本 `make_review_batch10.py`、`update_standard_batch10.py` |"))
DOC_PAIRS.append((
    "| 对象 / 主色 / **包色真源** | `design/art/card-prompt-bank-v2.json` **v2.5**（`pack_palette` 的 `hex/name/hue_word/shadow_word`、`pack_color_rule`、`accent_by_pack`、`cards[*].accent`、`postprocess_hint.bright_pack` / `.mid_pack` / `.lift_pack`）；镜像常量 `tools/build_card_prompt_bank_v2.py::PACK_ACCENT`（🔴 勿运行重建）；UI 侧 `scripts/ui/ui_style.gd::PACK_COLORS` |",
    "| 对象 / 主色 / **包色真源** | `design/art/card-prompt-bank-v2.json` **v2.6**（`pack_palette` 的 `hex/name/hue_word/shadow_word`、`pack_color_rule`、`accent_by_pack`、`cards[*].accent`、`postprocess_hint.bright_pack` / `.mid_pack` / `.lift_pack`）；镜像常量 `tools/build_card_prompt_bank_v2.py::PACK_ACCENT`（🔴 勿运行重建）；UI 侧 `scripts/ui/ui_style.gd::PACK_COLORS` |"))

# 13) §10 变更记录
DOC_PAIRS.append((
    "| 2026-11-09 | **批次⑨** sunder 破甲包 10 张整包落地（噬品红 `#E8437F`），换 `--lift-pack` 幂等重跑后全过检（p50 87–127 / p85 132–197 / cov 41.6–69.5% / alpha 全 255）；`Breaker` 检查区 304 px 复核为钻杆尖端而非水印；补 20 个 `.import`（共 120 个 uid 唯一）；正式卡面达 **60 张 / 80（6 包完成）**。交付 `art/_review/batch9/contact_batch9_cards.png`、`compare_pack_color_batch9.png`、`compare_pack_progress_batch9.png` |",
    "| 2026-11-09 | **批次⑨** sunder 破甲包 10 张整包落地（噬品红 `#E8437F`），换 `--lift-pack` 幂等重跑后全过检（p50 87–127 / p85 132–197 / cov 41.6–69.5% / alpha 全 255）；`Breaker` 检查区 304 px 复核为钻杆尖端而非水印；补 20 个 `.import`（共 120 个 uid 唯一）；正式卡面达 **60 张 / 80（6 包完成）**。交付 `art/_review/batch9/contact_batch9_cards.png`、`compare_pack_color_batch9.png`、`compare_pack_progress_batch9.png` |\n"
    "| 2026-11-09 | **v1.6 低明度包色验证**：批次⑩ `Hex` 试点四档实测默认 73 / bright 55 / mid 89 / **lift 101**，确认深青 `#1A6B7D`（L≈91）**复用 v1.5 的 `--lift-pack`**，不新增第五档、不改参数、不放宽门槛；青色系模板按 §3.1 补主色提亮句。`card-prompt-bank-v2.json` 升 **v2.6**（`postprocess_hint.lift_pack.applies_to` 加 `hex`），`anchor_ref` 同步 v1.6 |\n"
    "| 2026-11-09 | **批次⑩** hex 咒术包 10 张整包落地（深青 `#1A6B7D`），`--lift-pack` 一次过检（p50 101–138 / p85 161–182 / cov 88.5–99.6% / alpha 全 255）；量化色相直方图确认无第二色相；`Wither` 检查区 245 px 复核为底座撑脚；`rime`↔`hex` 近色对并排复核解除；补 20 个 `.import`（共 140 个 uid 唯一）；正式卡面达 **70 张 / 80（7 包完成）**。交付 `art/_review/batch10/contact_batch10_cards.png`、`compare_pack_color_batch10.png`、`compare_pack_progress_batch10.png`、`compare_nearhue_batch10.png` |"))

BANK_PAIRS = [
    ('"version": "v2.5",', '"version": "v2.6",'),
    ('"anchor_ref": "design/art/card-art-generation-standard-v1.md v1.5 (3/4 image-to-image, pack color as dominant tone; bright-pack / mid-pack / lift-pack tone variants by pack color luminance)",',
     '"anchor_ref": "design/art/card-art-generation-standard-v1.md v1.6 (3/4 image-to-image, pack color as dominant tone; bright-pack / mid-pack / lift-pack tone variants by pack color luminance; lift-pack also validated on low-luminance hex deep teal)",'),
    ('   "note": "v1.4: mid-luminance pack colors (L about 90-140, e.g. star-violet) are too dark under default white 155 and get darker under --bright-pack; lift the shadow floor instead of pushing highlights. Mutually exclusive with the other tone flags; use with --dominant, whole pack only, never per card. sunder needs the higher --lift-pack floor (v1.5); true/hex still need a 1-card pilot before adopting."',
     '   "note": "v1.4: mid-luminance pack colors (L about 90-140, e.g. star-violet) are too dark under default white 155 and get darker under --bright-pack; lift the shadow floor instead of pushing highlights. Mutually exclusive with the other tone flags; use with --dominant, whole pack only, never per card. sunder needs the higher --lift-pack floor (v1.5); hex deep teal is validated with --lift-pack (v1.6); only true still needs a 1-card pilot before adopting."'),
    ('   "applies_to": ["sunder"],', '   "applies_to": ["sunder", "hex"],'),
    ('   "note": "v1.5: mid-luminance packs with a very high share of dark shadow plates (magenta-crimson #E8437F) still fail p50 under --mid-pack (4 of 10 cards at 74-79). Keep white 145 and lift floor 42->58 instead; pushing white down to 135-140 breaks the 40% coverage gate on Ruin. Mutually exclusive with --bright-pack / --mid-pack; use with --dominant, whole pack only, never per card. true/hex still need a 1-card pilot."',
     '   "note": "v1.5 + v1.6: packs with a very high share of dark shadow plates (sunder magenta-crimson #E8437F) or a low-luminance pack color (hex deep teal #1A6B7D, L about 91) fail p50 under --mid-pack; four-tier pilot on Hex: default 73 / bright-pack 55 / mid-pack 89 / lift-pack 101, so reuse 145/58 rather than adding a fifth tier. Whole 10-card hex pack passed at p50 101-138, cov 88.5-99.6%. Mutually exclusive with --bright-pack / --mid-pack; use with --dominant, whole pack only, never per card. Only true still needs a 1-card pilot."'),
]

TOOL_PAIRS = [
    ("  py -3.9 tools/card_batch3_process.py --batch batch9 --dominant --lift-pack    # 暗板占比高的中明度包",
     "  py -3.9 tools/card_batch3_process.py --batch batch9 --dominant --lift-pack    # 暗板占比高的中明度包\n"
     "  py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）"),
    ("人工复核 floor 58 后深藏青描边依旧扎实、暗板层次未糊。三档互斥，同样整包统一使用。",
     "人工复核 floor 58 后深藏青描边依旧扎实、暗板层次未糊。批次⑩ 低明度深青 hex\n"
     "（#1A6B7D, L≈91）四档试点 73 / 55 / 89 / 101，确认复用本档而非新增第五档，整包 10 张\n"
     "p50 101-138 / cov 88.5-99.6% 全过检。三档互斥，同样整包统一使用。"),
]

if __name__ == "__main__":
    apply(DOC, DOC_PAIRS)
    apply(BANK, BANK_PAIRS)
    apply(TOOL, TOOL_PAIRS)
    print("== v1.6 / v2.6 同步完成 ==")
