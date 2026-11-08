# -*- coding: utf-8 -*-
"""
守核 Corebound · keyart v1 后处理（menu 背景 / hero 主视觉 → 正式资产）
------------------------------------------------------------
输入：art/_review/ 下 AI 生成原图（1536x1024，右下角带平台水印）
步骤：
  1) 水印修补：右下角矩形用同图左侧等高 flat 背景补丁覆盖（蓝图底为纯色，无痕迹）
  2) 16:9 cover 裁切：1536x1024 → 1536x864（垂直居中偏上，保主体构图）
  3) LANCZOS 放大到 1920x1080（1.25x，扁平矢量风可接受）
  4) 落盘 art/2d/ui/keyart_menu_bg_v1.png / keyart_hero_v1.png（PNG-32）
  5) 登记 art/manifest.json（§ SSOT）
  6) 可读性自检：menu 左 1/3（菜单列区域）平均亮度打印，供人工比对 §5.2 门禁
运行：py -3.9 tools/keyart_postprocess_v1.py
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
REVIEW = os.path.join(ROOT, "art", "_review")
OUT_UI = os.path.join(ROOT, "art", "2d", "ui")
MANIFEST = os.path.join(ROOT, "art", "manifest.json")

# 水印区（按 1536x1024 原图实测：右下角 x>=1400, y>=955 有水印笔画）
WM_BOX = (1380, 945, 1536, 1024)
# 16:9 裁切窗口（垂直位置：保核心主体，上 40 / 下 120）
CROP_TOP = 40

JOBS = [
    ("Flat_vector_sci_fi_illustratio_2026-11-08T08-41-16.png", "keyart_menu_bg_v1.png"),
    ("Flat_vector_sci_fi_illustratio_2026-11-08T08-42-53.png", "keyart_hero_v1.png"),
]


def remove_watermark(img: Image.Image) -> Image.Image:
    """右下角水印：从同高度左侧取等尺寸 flat 背景补丁盖住。"""
    x0, y0, x1, y1 = WM_BOX
    w, h = x1 - x0, y1 - y0
    # 补丁源：水印框左侧 260px 处取同尺寸区域（该处为纯色蓝图底）
    patch = img.crop((x0 - w - 260, y0, x0 - 260, y1))
    img.paste(patch, (x0, y0))
    return img


def to_1080p(img: Image.Image) -> Image.Image:
    """16:9 cover 裁切 + 放大到 1920x1080。"""
    w, h = img.size
    ch = int(w * 9 / 16)                      # 1536 -> 864
    top = max(0, min(CROP_TOP, h - ch))
    img = img.crop((0, top, w, top + ch))
    return img.resize((1920, 1080), Image.LANCZOS)


def left_third_luma(img: Image.Image) -> float:
    """菜单列区域（x 0..640, y 200..900）平均亮度 0-255。"""
    region = img.crop((0, 200, 640, 900)).convert("L")
    hist = region.histogram()
    total = sum(hist)
    return sum(i * n for i, n in enumerate(hist)) / total


def main() -> int:
    for src, dst in JOBS:
        p = os.path.join(REVIEW, src)
        if not os.path.exists(p):
            print("!! 缺原图：", src)
            return 1
        img = Image.open(p).convert("RGBA")
        img = remove_watermark(img)
        img = to_1080p(img)
        out = os.path.join(OUT_UI, dst)
        img.save(out)
        print("  +", "art/2d/ui/" + dst, "1920x1080",
              "menu列均亮=%.1f" % left_third_luma(img) if "menu" in dst else "")

    # 登记 manifest（append-only，重复运行幂等）
    with open(MANIFEST, encoding="utf-8") as f:
        mf = json.load(f)
    files = {a["file"] for a in mf["assets"]}
    for _, dst in JOBS:
        rel = "2d/ui/" + dst
        if rel not in files:
            mf["assets"].append({"file": rel, "size": [1920, 1080]})
            print("  ~ manifest +", rel)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(mf, f, ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
