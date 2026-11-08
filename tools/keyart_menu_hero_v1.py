#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
守核 Corebound · hero 满强度主菜单底派生（keyart-style-v1.md §4 追加档）
===============================================================================
需求：主菜单背景从「keyart_menu_bg_v1（30-40% 低强度档）」换成 hero 满强度
  核心构图。hero 直接铺满时左侧文字区（标题 / 按钮 / 版本信息）压不住高细节
  纹理 —— 本脚本派生一张**菜单专用底**：hero + 功能性压暗渐晕，原 hero
  不动（继续留给 Steam 胶囊 / 宣传图）。

工艺
  · 左侧 0→0.50W 平滑压暗到 0.28 倍（文字柱阴影，非装饰渐变 —— §5.1 可读性）
  · 底部 0.22H 轻压暗到 0.62 倍（左下进度 / 右下版本信息）
  · 整体 0.94 倍微压暗（按钮描边更跳）
  · 🔴 输入必须是 16:9 1920×1080（keyart_postprocess_v1.py 已裁好）
运行：py -3.x tools/keyart_menu_hero_v1.py
产物：art/2d/ui/keyart_menu_hero_v1.png（登记 manifest）
"""
import json
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "art", "2d", "ui", "keyart_hero_v1.png")
OUT = os.path.join(ROOT, "art", "2d", "ui", "keyart_menu_hero_v1.png")
MANIFEST = os.path.join(ROOT, "art", "manifest.json")

LEFT_END = 0.58      # 左侧压暗带恢复满强度的右边界（W 比例）
LEFT_HOLD = 0.30     # 平台段：文字/按钮柱宽度内恒定最暗（反复目检：ramp 直起会漏亮橙塔群）
LEFT_FLOOR = 0.16    # 左缘最暗倍率
BOT_START = 0.72     # 底部压暗带起点（H 比例）
BOT_FLOOR = 0.42     # 底缘最暗倍率
GLOBAL = 0.90        # 整体微压暗


def smooth(t: float) -> float:
    """平滑插值曲线（三次缓入缓出），避免 ramp 出现带状。"""
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def main():
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    if w != 1920 or h != 1080:
        raise SystemExit(f"输入必须是 1920x1080，实测 {w}x{h} —— 先跑 keyart_postprocess_v1.py")
    px = im.load()
    for y in range(h):
        vy = y / h
        bot = 1.0 - (1.0 - BOT_FLOOR) * smooth((vy - BOT_START) / (1.0 - BOT_START)) if vy > BOT_START else 1.0
        for x in range(w):
            vx = x / w
            if vx < LEFT_HOLD:
                left = LEFT_FLOOR
            elif vx < LEFT_END:
                # 平台段 → 满强度：平滑爬升（0 = 全暗，1 = 亮）
                left = LEFT_FLOOR + (1.0 - LEFT_FLOOR) * smooth((vx - LEFT_HOLD) / (LEFT_END - LEFT_HOLD))
            else:
                left = 1.0
            m = left * bot * GLOBAL
            if m >= 0.999:
                continue
            r, g, b, a = px[x, y]
            px[x, y] = (int(r * m), int(g * m), int(b * m), a)
    im.save(OUT)
    print("  +", "ui/keyart_menu_hero_v1.png", f"{w}x{h}")

    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    entry = {"file": "ui/keyart_menu_hero_v1.png", "size": [w, h]}
    m["assets"] = [a for a in m["assets"] if a["file"] != entry["file"]]
    m["assets"].append(entry)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=1)
    print("  manifest ->", len(m["assets"]), "assets")


if __name__ == "__main__":
    main()
