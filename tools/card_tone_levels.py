# -*- coding: utf-8 -*-
"""卡面插画色阶规整（黑场压到藏青、白场提到亮钢灰，保护高饱和能量色）。

用途：AI 出图的明度分布常与项目色板不符（主体过暗 → keyout 时被当成底色，
alpha 掉到 220 左右，描边发白）。本脚本对原图做「保色相亮度重映射」：
  1) 逐像素求亮度 L，按曲线 L' = clamp(floor + (L-black)/(white-black)*(ceil-floor))
  2) RGB 按 L'/L 等比缩放（保色相）——不用逐通道 LUT，否则颜色被压灰
  3) 高饱和像素按 --protect-mode 处理：
     skip   （默认，旧版小点缀口径）：跳过重映射，仅 ×1.06 轻微提亮。适合包色只占
             约 2% 面积的「蓝钢灰机身 + 小色块」卡面。
     remap  （v1.2 包色主色调口径）：整机高饱和时大部分像素都会命中保护条件，
             若仍跳过则明度完全没被拉进基准（实测 p50 只到 72–89）。改为只保护
             「极亮」的高饱和像素（L>170，即能量点缀），其余照常参与亮度重映射。

用法：
  py -3.9 tools/card_tone_levels.py --src art/_review/batch2/raw_Cannon_front_v2.png \
      --out art/_review/batch2/raw_Cannon_front_v2_norm.png \
      --black 42 --white 115 --floor 23 --ceil 235
  py -3.9 tools/card_tone_levels.py --src raw_Foo.png --out raw_Foo_norm.png \
      --black 35 --white 155 --floor 26 --ceil 235 --protect-mode remap
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
    ap.add_argument("--protect-mode", choices=["skip", "remap"], default="skip",
                    help="skip=高饱和像素只轻微提亮（旧版小点缀口径）；"
                         "remap=整机包色主色调口径，只保护极亮像素，其余参与重映射")
    ap.add_argument("--bright-threshold", type=float, default=170.0,
                    help="remap 模式下「极亮能量点缀」的亮度阈值，默认 170")
    args = ap.parse_args()

    im = Image.open(args.src).convert("RGB")
    w, h = im.size
    px = im.load()
    span = max(1.0, args.white - args.black)
    touched = protected = 0

    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            # 高饱和能量色（青/橙）默认不参与重映射，避免被拉成灰白
            saturated = (g - r > 60 and b - r > 60) or (r - g > 60 and r - b > 60)
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if saturated and (args.protect_mode == "skip" or
                              (args.protect_mode == "remap" and lum > args.bright_threshold)):
                px[x, y] = (min(255, int(r * 1.06)), min(255, int(g * 1.06)), min(255, int(b * 1.06)))
                protected += 1
                continue
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
