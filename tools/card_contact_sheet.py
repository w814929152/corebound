# -*- coding: utf-8 -*-
"""卡面接触表（contact sheet）生成器。

用途：批量生成后一次性目检整批卡的
  1) 同族一致性（同一批放一起像不像一套）
  2) 剪影可认度（缩到 64px 还能不能读出来）
  3) 主色是否按 pack 分配正确

用法：
  py -3.9 tools/card_contact_sheet.py --dir art/_review/batch1 --out art/_review/contact_batch1.png --cell 300 --cols 5
  py -3.9 tools/card_contact_sheet.py --dir art/_review/batch1 --out art/_review/contact_batch1_64.png --cell 64 --cols 10
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

FONT = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts", "NotoSansSC.ttf")
BG = (11, 13, 22)
FG = (200, 207, 218)
PAD = 10


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cell", type=int, default=300)
    ap.add_argument("--cols", type=int, default=5)
    ap.add_argument("--label", type=int, default=16)
    args = ap.parse_args()

    files = sorted(
        f for f in os.listdir(args.dir)
        if f.startswith("raw_") and f.lower().endswith(".png")
    )
    if not files:
        raise SystemExit("no raw_*.png in " + args.dir)

    cell = args.cell
    label_h = args.label + 8 if args.label > 0 else 0
    rows = (len(files) + args.cols - 1) // args.cols
    W = args.cols * cell + (args.cols + 1) * PAD
    H = rows * (cell + label_h) + (rows + 1) * PAD
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, args.label) if args.label > 0 else None

    for i, name in enumerate(files):
        r, c = divmod(i, args.cols)
        x = PAD + c * (cell + PAD)
        y = PAD + r * (cell + label_h + PAD)
        im = Image.open(os.path.join(args.dir, name)).convert("RGB")
        im = im.resize((cell, cell), Image.LANCZOS)
        sheet.paste(im, (x, y))
        if font:
            tag = name[len("raw_"):-len(".png")]
            d.text((x + 2, y + cell + 4), tag, font=font, fill=FG)

    sheet.save(args.out)
    print("saved", os.path.abspath(args.out), "| cards:", len(files), "| size:", sheet.size)


if __name__ == "__main__":
    main()
