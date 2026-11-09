# -*- coding: utf-8 -*-
"""
gen_ui_lib_pack_v1.py —— 资产包 v5：卡组图鉴分组底板（2 件）

设计依据：asset-pack-v5-lib.md · art-bible §2.2 色板
问题：图鉴 8 个分组无底板，卡片直接浮在 keyart 蓝图遗迹上，卡缝穿透背景蜂巢。
方案：中性 9-slice 分组底板（不染色，衬所有主题色）+ 白烘焙标题条
     （左端竖帽 + 斜切主体 + 右端渐隐；运行时 modulate 染卡包主题色）。
     🔴 染色件必须白/灰烘焙 —— modulate 是乘法，深底会被染黑。

产物（art/2d/ui/）：
    ui_lib_block_v1.png     48x48   分组底板 9-slice 源（corner 12，中性）
    ui_lib_head_bar_v1.png  640x40  分组标题条（白烘焙，modulate 染色）

主题色表见 ui_style.gd pack_color()（全部 art-bible §2.2 表内色）。

用法：py -3.13 tools/gen_ui_lib_pack_v1.py
"""

import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "2d", "ui")
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "manifest.json")

S = 4


def hx(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def P(x, y):
    """1x 逻辑坐标 -> 超采样坐标（🔴 全文件唯一的坐标放大入口）。"""
    return (x * S, y * S)


def save(img, w, h, rel):
    img = img.resize((w, h), Image.LANCZOS)
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("  +", rel, f"{w}x{h}")
    return rel


def canvas(w, h):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


# ---------------------------------------------------------------------------
def gen_block():
    """分组底板 9-slice 源（48×48，corner 12）：中性深面板 + 1px 细描边。
    🔴 不带 accent 竖条 —— 染色由标题条承担，底板必须衬所有主题色。"""
    w = 48
    img, d = canvas(w, w)
    d.rectangle([P(0.5, 0.5), P(w - 0.5, w - 0.5)], fill=hx("#0E111B", 242))
    d.rectangle([P(1.5, 1.5), P(w - 1.5, w - 1.5)], outline=hx("#262E42", 255), width=S)
    # 四角 3px 亮刻线（蓝图角标语言，烘焙进 9-slice 角区不会随拉伸糊掉）
    for (x0, y0, dx, dy) in [(2, 2, 1, 1), (w - 2, 2, -1, 1), (2, w - 2, 1, -1), (w - 2, w - 2, -1, -1)]:
        d.line([P(x0, y0), P(x0 + dx * 5, y0)], fill=hx("#3A4460", 255), width=S)
        d.line([P(x0, y0), P(x0, y0 + dy * 5)], fill=hx("#3A4460", 255), width=S)
    return save(img, w, w, "ui_lib_block_v1.png")


def gen_head_bar():
    """分组标题条（640×40）：白烘焙 —— modulate 乘色染主题色。
    形状：左端 6×24 竖帽 + 斜切主体 + 右端 α 渐隐 + 底部 1px 亮线。"""
    w, h = 640, 40
    img, d = canvas(w, h)
    white = (255, 255, 255)
    notch = 10.0
    # 主体多边形（左端斜切、右端到头，渐隐由 alpha mask 承担）
    mask = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(mask).polygon(
        [P(0, 4), P(w, 4), P(w, h - 6), P(notch, h - 6)], fill=255)
    # 水平 α 渐变（左 205 → 右 26）
    xs = np.linspace(0.0, 1.0, w * S, dtype=np.float32)
    ha = (205.0 - 179.0 * xs).astype(np.uint8)
    hbar = Image.fromarray(np.tile(ha, (h * S, 1)), "L")
    # 垂直乘子（上亮下暗的薄片感）
    ys = np.linspace(0.0, 1.0, h * S, dtype=np.float32)
    va = (1.0 - 0.30 * ys).astype(np.float32)
    vbar = Image.fromarray(
        np.tile((va * 255).astype(np.uint8).reshape(-1, 1), (1, w * S)), "L")
    alpha = ImageChops.multiply(ImageChops.multiply(hbar, vbar), mask)
    solid = Image.new("RGBA", (w * S, h * S), (white[0], white[1], white[2], 255))
    solid.putalpha(alpha)
    img.alpha_composite(solid)
    # 左端竖帽（实心亮块，分组标记）
    d.rectangle([P(2, 4), P(7, h - 6)], fill=(white[0], white[1], white[2], 255))
    # 底部 1px 亮线（染色后 = 主题色下划线）
    d.line([P(notch + 4, h - 7), P(w - 4, h - 7)], fill=(255, 255, 255, 255), width=S)
    # 左端斜切补一条斜线收头
    d.line([P(7, h - 7), P(notch, 5)], fill=(255, 255, 255, 190), width=S)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    return save(img, w, h, "ui_lib_head_bar_v1.png")


# ---------------------------------------------------------------------------
def register(entries):
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    names = {e["file"] for e in entries}
    m["assets"] = [a for a in m["assets"] if a["file"] not in names]
    m["assets"].extend(entries)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=1)
    print("  manifest ->", len(m["assets"]), "assets")


def main():
    print("[gen_ui_lib_pack_v1] 图鉴分组底板 · 2 件")
    done = [gen_block(), gen_head_bar()]
    sizes = {
        "ui_lib_block_v1.png": [48, 48],
        "ui_lib_head_bar_v1.png": [640, 40],
    }
    register([{"file": "ui/" + n, "size": sizes[n]} for n in done])
    print("[done] 2 assets -> art/2d/ui/")


if __name__ == "__main__":
    main()
