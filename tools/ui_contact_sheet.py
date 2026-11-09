"""UI 全页面接触表 —— 把 `art/_review/ui_all/` 的截图拼成一张总览图。

用途：一眼看完全部界面，检查跨页面的**一致性**（字号阶梯、面板圆角、按钮形态、
留白比例）—— 单看一页看不出来的问题，并排一放就露。

用法：
    py -3.9 tools/ui_contact_sheet.py
输出：
    art/_review/ui_contact_sheet.png（1920×1080，3×3）
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "_review", "ui_all")
OUT = os.path.join(ROOT, "art", "_review", "ui_contact_sheet.png")

CELL_W, CELL_H = 640, 360
COLS, ROWS = 3, 3
GAP = 8
BG = (14, 16, 26)

TITLES = {
    "01_menu": "主菜单",
    "02_library": "卡组图鉴",
    "03_pack_select": "卡包选择",
    "04_battle_shop": "战斗商店",
    "05_stage_map": "选关航图",
    "06_result_won": "结算 · 胜",
    "07_result_lost": "结算 · 负",
    "08_dialog_disabled": "受损塔处置",
    "09_dialog_salvage": "拆除回收",
}


def main() -> int:
    if not os.path.isdir(SRC):
        print(f"[err] 缺截图目录：{SRC}\n      先跑 tools/shoot_ui_all.gd", file=sys.stderr)
        return 1
    files = sorted(f for f in os.listdir(SRC) if f.endswith(".png"))
    if not files:
        print(f"[err] {SRC} 里没有 PNG", file=sys.stderr)
        return 1

    W = COLS * CELL_W + (COLS + 1) * GAP
    H = ROWS * CELL_H + (ROWS + 1) * GAP
    sheet = Image.new("RGB", (W, H), BG)

    for i, name in enumerate(files[: COLS * ROWS]):
        im = Image.open(os.path.join(SRC, name)).convert("RGB")
        im = im.resize((CELL_W, CELL_H), Image.LANCZOS)
        cx = GAP + (i % COLS) * (CELL_W + GAP)
        cy = GAP + (i // COLS) * (CELL_H + GAP)
        sheet.paste(im, (cx, cy))
        key = os.path.splitext(name)[0]
        label = TITLES.get(key, key)
        d = ImageDraw.Draw(sheet)
        d.rectangle([cx, cy, cx + 118, cy + 24], fill=(6, 8, 14))
        d.text((cx + 8, cy + 6), label, fill=(255, 201, 74))
        print(f"  {i + 1}. {name} -> {label}")

    sheet.save(OUT)
    print(f"[ok] {OUT}  {W}x{H}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
