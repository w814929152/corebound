# -*- coding: utf-8 -*-
"""批量生成用的提示词拼装器（v4 中密度）。

把"冻结锚点"和"单卡三段式描述"拼成一条完整 prompt，并把整批 prompt 落盘留档，
保证 80 张卡的生成可以按同一份文件复现。

用法：
  py -3.9 tools/card_batch_prompt.py --pack core --out design/art/card-prompts-batch1.json
  py -3.9 tools/card_batch_prompt.py --card Arrow          # 只打印一张
"""
import argparse
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
BANK = os.path.join(HERE, "..", "design", "art", "card-prompt-bank-v2.json")

# 冻结锚点（与 card-illustration-style-v1.md 2.2 同源；改锚点必须同步改文档）
ANCHOR = (
    "Flat vector game card illustration in engineering blueprint style, medium detail density. "
    "Exactly ONE large geometric silhouette as the subject, centered, readable at thumbnail size, "
    "divided into two or three stacked segments (base, body, cap) by one or two horizontal seams. "
    "Exactly ONE functional part, its orientation exactly as described, never a cluster of small parts. "
    "Interior structure lines: two to four panel seams, plus one or two small circular or rectangular ports; 6-8 shape blocks total. "
    "Bold thick uniform near-black navy #001830 outline, at least 6 px wide at 1024 resolution, on the outer silhouette and along every segment. "
    "Exact palette: #001830 outline, light steel grey #A0B8C8 as the dominant fill, mid steel grey #405868 for shadow panels, plus ONE accent. No neutral warm grey. "
    "The silhouette MUST be solid-filled: light steel grey covers at least 60 percent of its area, "
    "with a tall upright tower-like proportion, a clearly separated stepped base plinth and a distinct cap. "
    "Never a hollow outline, never a thin frame, never a dark body, never a C-shaped clamp, "
    "never detached floating parts, never a flat horizontal wedge. "
    "The accent color appears on ONE main block plus at most two small same-hue accents, nowhere else. "
    "Background: solid flat #141726 ONLY, absolutely no grid lines, no texture, no frame border, no other pattern. "
    "Strict frontal elevation view, symmetrical. NOT isometric, NOT 3/4 perspective, NOT top-down. "
    "No gradients, no shading, no glow, no halo, no lens flare, no painterly texture, no stippling, no hatching. "
    "No gear trains, no rivet rows, no layered armour plates, no circuitry, no ornament, "
    "no small mechanical greebles, no text, no numbers, no watermark, no logo, no characters, "
    "no scene, no environment, not a chess piece, not a lighthouse. "
    "1024x1024, the silhouette fills 74% of frame height and about 60 percent of frame width, 8% safe margin on all sides, nothing cropped at edges."
)

TAIL = (
    "Subject: {structure}; {feature}; the accent color {accent} {accent_block}, nothing else in {accent_name}."
)


def build(card, data):
    head = TAIL.format(
        structure=data["structure"],
        feature=data["feature"],
        accent=data["accent"],
        accent_block=data["accent_block"],
        accent_name=data["accent"],
    )
    return ANCHOR + " " + head


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack")
    ap.add_argument("--card")
    ap.add_argument("--out")
    args = ap.parse_args()

    bank = json.load(open(BANK, encoding="utf-8"))
    cards = bank["cards"]

    if args.card:
        print(build(args.card, cards[args.card]))
        return

    sel = {k: v for k, v in cards.items() if not args.pack or v["pack"] == args.pack}
    out = {
        "batch": args.pack or "all",
        "anchor_version": "v4",
        "anchor": ANCHOR,
        "size": "1024x1024",
        "prompts": {k: build(k, v) for k, v in sel.items()},
    }
    if args.out:
        path = os.path.join(HERE, "..", args.out)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
        print("written", os.path.abspath(path), "cards:", len(sel))
    else:
        for k in sel:
            print("=" * 8, k)
            print(out["prompts"][k])


if __name__ == "__main__":
    main()
