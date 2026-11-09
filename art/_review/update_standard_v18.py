# -*- coding: utf-8 -*-
"""v1.8 / v2.8 同步：把 Godot 4.7.2（Steam 版）实机验收结果写进标准文档与提示词库。

只改文档状态、待办、留档索引与版本引用；**不改任何生成参数 / 提示词 / 质检门槛**。
运行：py -3.9 art/_review/update_standard_v18.py
"""
import io
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOC = os.path.join(ROOT, "design", "art", "card-art-generation-standard-v1.md")
BANK = os.path.join(ROOT, "design", "art", "card-prompt-bank-v2.json")


def load(p):
    with io.open(p, "r", encoding="utf-8", newline="") as f:
        raw = f.read()
    crlf = "\r\n" in raw
    return raw.replace("\r\n", "\n"), crlf


def save(p, text, crlf):
    out = text.replace("\n", "\r\n") if crlf else text
    with io.open(p, "w", encoding="utf-8", newline="") as f:
        f.write(out)


SEC_5_12 = """### 5.12 引擎实机验收（2026-11-09 · **v1.8 · Godot 4.7.2 Steam 版**）

> 前提更正：此前 §8 #5 / #10 记「本机无 Godot 编辑器」有误。编辑器位于 Steam 库 `C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`，版本 `4.7.2.stable.steam.ed1daf0bf`，与 `project.godot` 的 `config/features=4.7` 一致；自带导出模板 `editor_data/export_templates/4.7.2.stable/`（含 `windows_release_x86_64.exe`）。以下四条均在真引擎上跑通，**未改任何生成参数 / 提示词 / 质检门槛**。

| 步骤 | 命令 / 脚本 | 结果 |
|---|---|---|
| ① 重导入 | `godot --headless --path . --import` | exit 0、日志 0 error；按内容 md5 重新导入 `card_eraser_v1_{460,t}.png`（11:15 幂等复跑过色阶），`.godot/imported/card_*.ctex` 共 **160 个**（80×`_460` + 80×`_t`），缓存与最新 PNG 对齐 |
| ② 全量加载探针 | `godot --headless --path . --script res://tools/probe_card_art_all.gd` | **80 / 80 张** `card_art()` 加载成功、纹理尺寸全为 460²、缺图仍降级返回 `null`；`PASS · 失败项 = 0`（退出时 ObjectDB / resources-in-use 是 `--script` 模式通用清理噪声，非加载失败） |
| ③ 重新导出 | `godot --headless --path . --export-release "Windows Desktop" build/windows/Corebound.exe` | `[ DONE ] savepack`、exit 0；产物 **196,623,600 B**（旧版 132,145,144 B，+64.5 MB 为 160 张卡面资源），时间戳 2026-11-09 11:35，已替换旧 exe |
| ④ 主场景自测 | 编辑器 `--headless --path . --quit-after 5` / 导出 exe 同参数 | 项目模式 **123 项全通过 / 0 失败**；导出版 115 通过 / 6 失败，6 项全是「打不开 `res://scripts/**/*.gd`」—— pck 内脚本已编译为 `.gdc` + `.remap`，源码 grep 类断言在导出版读不到文本，**与卡面 / 导出完整性无关，非回归** |

**UI 实机截图**（`godot --path . --script res://tools/shoot_card_art_smoke.gd`，窗口模式 / OpenGL 3.3 兼容）：
- `art/_review/godot_smoke_library_cards.png`：主菜单「卡组图鉴」页，脚本内统计 **80 张**来自 `art/2d/cards/` 的 TextureRect 全部实例化；core 钢灰 / cinder 熔橙等包色一眼可分，96×96 插画未裁切、未压住文字。
- `art/_review/godot_smoke_shop_cards.png`：战斗商店三个商品位，`Frost` / `Cannon` 两张建筑卡显示 72px 插画带；中间 `FireUp` 是单塔效果卡、不在 80 张建筑卡里 → `card_art()` 返回 `null` → 插画带整带隐藏，版式回落无图（§6 的判空降级在真机上生效），**2 / 3 属预期而非缺图**。

**新发现的边界**：图鉴标题写「共 81 张卡」——`scripts/data/card_packs.gd` 的 cinder 熔炉包除 10 张外额外收录 **`Pyroclasm`**（焚星塔，11 张/包）。它不在 8×10 的 80 张卡面清单里，图鉴按 §6 降级显示为纯文字卡条。当前按「80 张收官、不再出图」的口径保留；若要求图鉴零空白，需单独补 1 张卡面（见 §8 #11）。

---

"""

PAIRS = [
    (
        "> 状态：🟢 **当前生效 · v1.7**（2026-11-09 立 / 同日八次更新）。适用于 `art/2d/cards/card_*_v1_{t,460}.png` 的全部新增与重绘。当前进度 **80 / 80 张（8 包全部完成）**，见 §7。\n"
        "> 🆕 **v1.7 变更（批次⑪收官）**：",
        "> 状态：🟢 **当前生效 · v1.8**（2026-11-09 立 / 同日九次更新）。适用于 `art/2d/cards/card_*_v1_{t,460}.png` 的全部新增与重绘。当前进度 **80 / 80 张（8 包全部完成）**，见 §7；**引擎实机验收见 §5.12**。\n"
        "> 🆕 **v1.8 变更（引擎实机验收）**：此前「本机无 Godot 编辑器」的判断有误 —— 编辑器在 Steam 库，正是 **4.7.2.stable.steam** 且自带 `4.7.2.stable` Windows 导出模板。已完成 `--import` 重导入、80 张卡面全量加载探针、重新 `--export-release`、图鉴 / 商店实机截图复核；**未改任何生成参数、提示词或质检门槛**。新增探针 / 截图脚本与两张实机样张，详见 §5.12、§9。\n"
        "> 🆕 **v1.7 变更（批次⑪收官）**：",
    ),
    (
        "---\n\n## 6. 落盘与游戏接线",
        "---\n\n" + SEC_5_12 + "## 6. 落盘与游戏接线",
    ),
    (
        "进度总览见 `art/_review/batch11/compare_pack_progress_batch11.png`。后续只剩 Godot 重导入 / export 与 UI 实机验证。",
        "进度总览见 `art/_review/batch11/compare_pack_progress_batch11.png`。**Godot 重导入 / export / UI 实机验证已于 v1.8 全部完成**（§5.12）；当前唯一边界是 cinder 包额外第 81 卡位 `Pyroclasm` 无卡面（§8 #11）。",
    ),
    (
        "| 5 | 本机无 Godot 编辑器（只有导出的 `Corebound.exe`，embed_pck 无法热更），UI 接线**未实机验证** | 用 Godot 4.7.2 打开项目重导入 → F5 看商店 / 图鉴 → 需要出包时重新 `--export-release` |",
        "| 5 | ~~本机无 Godot 编辑器，UI 接线未实机验证~~ | ✅ **v1.8 解除**：编辑器在 Steam 库，为 `4.7.2.stable.steam` 且自带导出模板；`--import` / 全量探针 / `--export-release` / 图鉴+商店截图四项全跑通，详见 §5.12 |",
    ),
    (
        "| 6 | 80 张卡面**已全部落盘**（8 包各 10 张），无待建卡 | ✅ 批次⑪ 收官解除；后续只做 Godot 4.7.2 重导入与 export，不再出图 |",
        "| 6 | 80 张卡面**已全部落盘**（8 包各 10 张），无待建卡 | ✅ 批次⑪ 收官解除；Godot 4.7.2 重导入与 export 已于 v1.8 完成，不再出图（唯一例外见 #11） |",
    ),
    (
        "全部新卡已补齐；最终仍需 Godot 4.7.2 打开项目重导入生成 `.ctex` 并重新 export |",
        "全部新卡已补齐；✅ 最终已由 Godot 4.7.2 `--import` 校验：160 个 `card_*.ctex` 生成无误、80 张全部可 `load()`（§5.12）。仓库约定 `*.import` / `*.uid` 不入库，由引擎按需重生成 |\n"
        "| 11 | 图鉴共 **81 个卡位**：cinder 熔炉包额外收录 `Pyroclasm`，无对应卡面 → 图鉴显示纯文字卡条 | 当前按「80 张收官」保留（§5.12）；若要零空白，单独补 1 张 `card_pyroclasm_v1_{t,460}.png`（`--dominant` + cinder 默认档）并按 §6 补 `.import`，需用户拍板 |\n"
        "| 12 | 导出的 `Corebound.exe` 无头自测固定 6 项失败（「打不开 `res://scripts/**/*.gd`」） | 非回归：pck 内 `.gd` 已编译为 `.gdc` + `.remap`，源码 grep 类断言在导出版读不到文本；项目模式同套件 123/0 全通过（§5.12）。若要求导出版自测全绿，须把这些断言改为读编译产物或仅在编辑器模式运行 |",
    ),
    (
        "| 后处理工具 | `tools/card_tone_levels.py`、`card_keyout.py`、`card_batch3_process.py`、`card_mock_card.py`、`card_contact_sheet.py` |",
        "| 后处理工具 | `tools/card_tone_levels.py`、`card_keyout.py`、`card_batch3_process.py`、`card_mock_card.py`、`card_contact_sheet.py` |\n"
        "| **v1.8 引擎实机验收** | `tools/probe_card_art_all.gd`（80 张 headless 加载探针）、`tools/shoot_card_art_smoke.gd`（图鉴 + 商店窗口截图）、`art/_review/godot_smoke_library_cards.png`、`art/_review/godot_smoke_shop_cards.png`、`art/_review/update_standard_v18.py`；`build/windows/Corebound.exe`（导出产物，`build/` 不入库） |",
    ),
    (
        "| 2026-11-09 | **批次⑪ 收官** true 湮灭包 10 张整包落地",
        "| 2026-11-09 | **v1.8 引擎实机验收（更正「本机无编辑器」）**：确认 Steam 库内 Godot `4.7.2.stable.steam` + 自带 `4.7.2.stable` 导出模板可用；`--headless --import` 重导入（160 个 `card_*.ctex`）、`probe_card_art_all.gd` 80/80 全通过、`--export-release` 更新 `build/windows/Corebound.exe`（196,623,600 B）、窗口模式截图确认图鉴 80 张 / 商店 2 张（效果卡降级）接线生效；项目模式主场景自测 123/0。`card-prompt-bank-v2.json` 升 **v2.8**（仅同步 `anchor_ref` / `completion` 状态，**不改任何生成参数**） |\n"
        "| 2026-11-09 | **v1.8 新发现的边界**：图鉴 81 个卡位中 cinder 额外卡 `Pyroclasm` 无卡面（§8 #11）；导出版自测 6 项「源码 grep 读不到 .gd」失败属 pck 编译产物的测试设计限制、非回归（§8 #12） |\n"
        "| 2026-11-09 | **批次⑪ 收官** true 湮灭包 10 张整包落地",
    ),
]


def apply():
    text, crlf = load(DOC)
    for old, new in PAIRS:
        n = text.count(old)
        if n != 1:
            raise SystemExit("DOC 命中 %d 次（应为 1）: %s" % (n, old[:70]))
        text = text.replace(old, new, 1)
    save(DOC, text, crlf)
    print("DOC 已更新:", len(PAIRS), "处替换 | 换行:", "CRLF" if crlf else "LF")

    bank, bcrlf = load(BANK)
    json.loads(bank)  # 替换前合法性预检
    anchor_new = (
        "design/art/card-art-generation-standard-v1.md v1.8 (3/4 image-to-image, pack color as dominant tone; "
        "bright-pack / mid-pack / lift-pack tone variants by pack color luminance; lift-pack validated on sunder/hex/true; "
        "all 8 packs complete, 80/80 cards; engine-verified with Godot 4.7.2 Steam: import + 80-card load probe + export + UI screenshots)"
    )
    completion_new = (
        "80/80 cards, 8/8 packs validated (2026-11-09); no pending pack; "
        "engine-verified with Godot 4.7.2 (Steam) on 2026-11-09; "
        "extra 81st card slot Pyroclasm has no card art (by design, pending user decision)"
    )
    m_anchor = re.search(r'"anchor_ref": "[^"]*"', bank)
    m_completion = re.search(r'"completion": "[^"]*"', bank)
    if m_anchor is None or m_completion is None:
        raise SystemExit("BANK 未找到 anchor_ref / completion 字段")
    repl = [
        ('"version": "v2.7"', '"version": "v2.8"'),
        (m_anchor.group(0), '"anchor_ref": "%s"' % anchor_new),
        (m_completion.group(0), '"completion": "%s"' % completion_new),
    ]
    for old, new in repl:
        n = bank.count(old)
        if n != 1:
            raise SystemExit("BANK 命中 %d 次（应为 1）: %s" % (n, old[:60]))
        bank = bank.replace(old, new, 1)
    json.loads(bank)  # 替换后合法性复核
    save(BANK, bank, bcrlf)
    print("BANK 已更新: v2.8 / anchor_ref v1.8 / completion 追加实机验收状态")


if __name__ == "__main__":
    apply()
