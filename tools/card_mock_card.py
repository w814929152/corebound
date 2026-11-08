# -*- coding: utf-8 -*-
"""卡框集成模拟：把 keyout 后的 460 安全区插画贴进卡框，出一张模拟样张。

用途：在不动 Godot 的前提下，先目检「插画 + 卡框」的合成观感
（主体是否过小/过大、与网格底色是否打架、安全区是否被边框压住）。

用法：
  py -3.9 tools/card_mock_card.py --card art/2d/cards/card_arrow_v1_460.png \
      --frame art/2d/ui/ui_card_frame_common_v1.png --out art/_review/mock_card_arrow.png
"""
import argparse
import os

from PIL import Image

FONT = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts", "NotoSansSC.ttf")

# 卡框 512x716 内的插画区（相对比例）：左侧留边 / 顶部留边 / 右留边 / 文字区上沿
INSET_L, INSET_T, INSET_R, INSET_B = 0.075, 0.075, 0.075, 0.655


def composite(card_png, frame_png, label=""):
    frame = Image.open(frame_png).convert("RGBA")
    W, H = frame.size
    x0, y0 = int(W * INSET_L), int(H * INSET_T)
    x1, y1 = int(W * (1 - INSET_R)), int(H * INSET_B)
    aw, ah = x1 - x0, y1 - y0

    art = Image.open(card_png).convert("RGBA")
    scale = min(aw / art.width, ah / art.height) * 0.94
    art = art.resize((max(1, int(art.width * scale)), max(1, int(art.height * scale))), Image.LANCZOS)

    # 插画区垫一层不透明暗底：实际接入时卡面 StyleBoxFlat 的底色就承担这一层，
    # 这里模拟出来是为了避免卡框网格线穿透主体（视觉上会显脏）。
    # 底色从卡框插画区内采样中位数取得 —— 写死颜色会和卡框对不上，出现一个深色矩形。
    samples = []
    for yy in range(y0 + 12, y1 - 12, 19):
        for xx in range(x0 + 12, x1 - 12, 23):
            samples.append(frame.getpixel((xx, yy))[:3])
    med = tuple(sorted(s[i] for s in samples)[len(samples) // 2] for i in range(3))
    pad = Image.new("RGBA", (aw, ah), med + (255,))
    pad.paste(art, ((aw - art.width) // 2, (ah - art.height) // 2), art)
    frame.alpha_composite(pad, (x0, y0))

    if label:
        from PIL import ImageDraw, ImageFont
        d = ImageDraw.Draw(frame)
        try:
            f = ImageFont.truetype(FONT, 26)
        except OSError:
            f = None
        d.text((x0 + 8, y1 + 18), label, font=f, fill=(200, 207, 218, 255))
    return frame


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--card", required=True)
    ap.add_argument("--frame", default="art/2d/ui/ui_card_frame_common_v1.png")
    ap.add_argument("--out", required=True)
    ap.add_argument("--label", default="")
    args = ap.parse_args()
    im = composite(args.card, args.frame, args.label)
    im.save(args.out)
    print("saved", os.path.abspath(args.out), im.size)


if __name__ == "__main__":
    main()
