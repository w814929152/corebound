# -*- coding: utf-8 -*-
"""卡面插画色阶规整（黑场压到藏青、白场提到亮钢灰，保护高饱和能量色）。

用途：AI 出图的明度分布常与项目色板不符（主体过暗 → keyout 时被当成底色，
alpha 掉到 220 左右，描边发白）。本脚本对原图做「保色相亮度重映射」：
  1) 逐像素求亮度 L，按曲线 L' = clamp(floor + (L-black)/(white-black)*(ceil-floor))
  2) RGB 按 L'/L 等比缩放（保色相）——不用逐通道 LUT，否则颜色被压灰
  3) 高饱和像素（g-r>60 且 b-r>60，即青色能量色）跳过重映射，仅轻微提亮

用法：
  py -3.9 tools/card_tone_levels.py --src art/_review/batch2/raw_Cannon_front_v2.png \
      --out art/_review/batch2/raw_Cannon_front_v2_norm.png \
      --black 42 --white 115 --floor 23 --ceil 235
"""
import argparse

from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--black", type=float, default=42.0, help="黑场：该亮度及以下压到 floor")
    ap.add_argument("--white", type=float, default=115.0, help="白场：该亮度映射到 ceil")
    ap.add_argument("--floor", type=float, default=23.0, help="暗部落点（#141726 的亮度≈23）")
    ap.add_argument("--ceil", type=float, default=235.0, help="亮部落点")
    args = ap.parse_args()

    im = Image.open(args.src).convert("RGB")
    w, h = im.size
    px = im.load()
    span = max(1.0, args.white - args.black)
    touched = protected = 0

    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            # 高饱和能量色（青/橙）不参与重映射，避免被拉成灰白
            if (g - r > 60 and b - r > 60) or (r - g > 60 and r - b > 60):
                px[x, y] = (min(255, int(r * 1.06)), min(255, int(g * 1.06)), min(255, int(b * 1.06)))
                protected += 1
                continue
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            new = args.floor + (lum - args.black) / span * (args.ceil - args.floor)
            new = max(args.floor, min(args.ceil, new))
            k = new / lum if lum > 1e-3 else 0.0
            px[x, y] = (
                max(0, min(255, int(round(r * k)))),
                max(0, min(255, int(round(g * k)))),
                max(0, min(255, int(round(b * k)))),
            )
            touched += 1

    im.save(args.out)
    print("norm ok  touched=%d protected=%d -> %s" % (touched, protected, args.out))


if __name__ == "__main__":
    main()
