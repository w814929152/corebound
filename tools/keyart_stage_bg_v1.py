#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
守核 Corebound · 选关航图背景派生（keyart-style-v1.md §4 追加档 · 2026-11-08）
===============================================================================
需求：选关航图（stage_select_overlay）此前只有纯色底（#080A10），用户要求
  「关卡选择界面也加上背景图」。hero 满强度图的**金色核心恰在画面中心**，
  与航图中心的核心节点（4-1）天然同构 —— 直接派生一张航图专用底：
  hero + 大幅压暗 + 轻微失焦 + 边缘渐晕，让节点 / 标签 / 面板浮在氛围层上。
  原 hero 不动（继续留给 Steam 胶囊 / 宣传图）。

工艺
  · 高斯模糊 r=3.0（1920 下约 0.16% 视宽 —— 可辨氛围、不抢细节）
  · 饱和度 ×0.80（把橙/青压向深夜紫，避免与章节色打架）
  · 径向渐晕：中心 0.30 倍（金色核心微微透出，呼应 4-1）→ 半径 0.55 起
    平滑压到边缘 0.16 倍（四周橙塔群全退成暗纹）
  · 🔴 输入必须是 16:9 1920×1080（keyart_postprocess_v1.py 已裁好）
运行：py -3.x tools/keyart_stage_bg_v1.py
产物：art/2d/ui/keyart_stage_bg_v1.png（登记 manifest）
"""
import json
import math
import os

from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "art", "2d", "ui", "keyart_hero_v1.png")
OUT = os.path.join(ROOT, "art", "2d", "ui", "keyart_stage_bg_v1.png")
MANIFEST = os.path.join(ROOT, "art", "manifest.json")

BLUR_R = 3.0         # 高斯模糊半径（px）
SAT = 0.80           # 饱和度倍率
CENTER_XY = (0.5, 0.47)   # 渐晕中心（= 航图核心节点位置 sz.y*0.47，逐字对齐）
CENTER_MUL = 0.30    # 中心最亮倍率
EDGE_MUL = 0.16      # 边缘最暗倍率
VIGN_START = 0.22    # 渐晕起点（归一化半径）
VIGN_END = 0.62      # 渐晕终点（此后恒为 EDGE_MUL）


def smooth(t: float) -> float:
    """平滑插值曲线（三次缓入缓出），避免 ramp 出现带状。"""
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def main():
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    if w != 1920 or h != 1080:
        raise SystemExit(f"输入必须是 1920x1080，实测 {w}x{h} —— 先跑 keyart_postprocess_v1.py")

    # ① 失焦 + 降饱和（背景层退后，节点 / 文字浮前）
    im = im.filter(ImageFilter.GaussianBlur(BLUR_R))
    gray = im.convert("L")
    im = Image.merge("RGBA", (
        Image.blend(gray, im.getchannel("R"), SAT),
        Image.blend(gray, im.getchannel("G"), SAT),
        Image.blend(gray, im.getchannel("B"), SAT),
        im.getchannel("A"),
    ))

    # ② 径向渐晕压暗
    px = im.load()
    cx, cy = w * CENTER_XY[0], h * CENTER_XY[1]
    rmax = math.hypot(max(cx, w - cx), max(cy, h - cy))
    for y in range(h):
        dy = y - cy
        for x in range(w):
            r = math.hypot(x - cx, dy) / rmax
            if r <= VIGN_START:
                m = CENTER_MUL
            elif r >= VIGN_END:
                m = EDGE_MUL
            else:
                m = CENTER_MUL + (EDGE_MUL - CENTER_MUL) * smooth((r - VIGN_START) / (VIGN_END - VIGN_START))
            r8, g8, b8, a8 = px[x, y]
            px[x, y] = (int(r8 * m), int(g8 * m), int(b8 * m), a8)

    im.save(OUT)
    print("  +", "ui/keyart_stage_bg_v1.png", f"{w}x{h}")

    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    entry = {"file": "ui/keyart_stage_bg_v1.png", "size": [w, h]}
    m["assets"] = [a for a in m["assets"] if a["file"] != entry["file"]]
    m["assets"].append(entry)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=1)
    print("  manifest ->", len(m["assets"]), "assets")


if __name__ == "__main__":
    main()
