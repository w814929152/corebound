# -*- coding: utf-8 -*-
"""
gen_ui_result_pack_v1.py —— 资产包 v4：结算页情绪背景/横幅 + 三态鼠标光标（7 件）

设计依据：design/art/asset-pack-v4-result.md（提案）· art-bible §2.2 色板
管线：PIL 程序化生成（锐利几何件 4× 超采样 LANCZOS 下采样；柔和辉光件 1× 直出）
色号（逐字 art-bible §2.2）：
    #FFC94A 辉金 / #FF2E4E 警报红 / #3ED0E8 耀青 / #141726 夜幕紫 / #0A0C14 深底
    #C8CFDA 正文钢白

产物（art/2d/ui/）：
    ui_result_won_bg_v1.png   1920x1080  胜利情绪背景（中心辉金放射）
    ui_result_lost_bg_v1.png  1920x1080  失败情绪背景（警报红 + 裂纹）
    ui_result_won_banner_v1.png  960x96  胜利横幅带（嵌面板标题上）
    ui_result_lost_banner_v1.png 960x96  失败横幅带
    ui_cursor_default_v1.png    48x48   默认箭头（hotspot 4,2）
    ui_cursor_place_v1.png      48x48   放置准星（hotspot 24,24）
    ui_cursor_deny_v1.png       48x48   禁止（hotspot 24,24）

用法：py -3.13 tools/gen_ui_result_pack_v1.py
"""

import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "2d", "ui")
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "manifest.json")

S = 4                     # 锐利几何件超采样倍率（🔴 坐标一律走 P() 统一放大）
C_GOLD = "#FFC94A"
C_ALERT = "#FF2E4E"
C_ALLY = "#3ED0E8"
C_INK = "#0A0C14"
C_STEEL = "#C8CFDA"


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


# ---------------------------------------------------------------------------
# 情绪背景（1× 直出：纯径向渐变 + 噪点，无需超采样）
# ---------------------------------------------------------------------------
def _radial_layer(size, cx_f, cy_f, radius_px, rgb, a_center):
    """径向 α 渐变层：中心 a_center → radius_px 处 0。（numpy 向量化）"""
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w * cx_f, h * cy_f
    dist = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
    t = np.clip(1.0 - dist / radius_px, 0.0, 1.0)
    a = (a_center * (t * t)).astype(np.uint8)
    layer = np.zeros((h, w, 4), dtype=np.uint8)
    layer[..., 0] = rgb[0]
    layer[..., 1] = rgb[1]
    layer[..., 2] = rgb[2]
    layer[..., 3] = a
    return Image.fromarray(layer, "RGBA")


def _noise(img, amp=3):
    """±amp 灰度噪点（破色带）。（numpy 向量化）"""
    arr = np.array(img, dtype=np.int16)
    rnd = random.Random(47)
    noise = np.array(
        Image.effect_noise(img.size, amp * 3.0), dtype=np.int16
    ) - 128                       # N(0, amp*3) 近似；再裁到 ±amp
    noise = np.clip(noise, -amp, amp)
    arr[..., :3] = np.clip(arr[..., :3] + noise[..., None], 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def gen_won_bg():
    """胜利背景：深底 + 中心辉金双环辉光（核心爆发）+ 噪点。"""
    w, h = 1920, 1080
    img = Image.new("RGBA", (w, h), hx(C_INK, 255))
    # 外圈柔光（大半径低强度）+ 内核（小半径高强度）双层
    img.alpha_composite(_radial_layer((w, h), 0.5, 0.42, 780, hx(C_GOLD)[:3], 66))
    img.alpha_composite(_radial_layer((w, h), 0.5, 0.42, 360, hx(C_GOLD)[:3], 120))
    # 中央一缕耀青冷光（青金对撞 = 蓝图语言的胜利）
    img.alpha_composite(_radial_layer((w, h), 0.5, 0.42, 200, hx(C_ALLY)[:3], 52))
    img = _noise(img.convert("RGBA"), 3)
    return save(img, w, h, "ui_result_won_bg_v1.png")


def gen_lost_bg():
    """失败背景：深底 + 警报红中心辉光 + 六向裂纹 + 噪点。"""
    w, h = 1920, 1080
    img = Image.new("RGBA", (w, h), hx(C_INK, 255))
    img.alpha_composite(_radial_layer((w, h), 0.5, 0.42, 720, hx(C_ALERT)[:3], 78))
    img.alpha_composite(_radial_layer((w, h), 0.5, 0.42, 320, hx(C_ALERT)[:3], 108))
    # 六向放射裂纹（从中心折向外的暗红线段，线宽随距离收窄）
    crack = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cd = ImageDraw.Draw(crack)
    cx, cy = w * 0.5, h * 0.42
    rnd = random.Random(11)
    for i in range(6):
        ang = math.radians(60 * i + rnd.uniform(-10, 10))
        segs = 4
        px_, py_ = cx, cy
        for s_ in range(segs):
            L = 120 + rnd.uniform(-30, 60) + s_ * 60
            nx_ = px_ + math.cos(ang) * L + rnd.uniform(-24, 24)
            ny_ = py_ + math.sin(ang) * L + rnd.uniform(-24, 24)
            wid = max(1, 4 - s_)
            a = max(20, 110 - s_ * 24)
            cd.line([(px_, py_), (nx_, ny_)], fill=hx(C_ALERT, a), width=wid)
            px_, py_ = nx_, ny_
    crack = crack.filter(ImageFilter.GaussianBlur(1.2))
    img.alpha_composite(crack)
    img = _noise(img.convert("RGBA"), 3)
    return save(img, w, h, "ui_result_lost_bg_v1.png")


# ---------------------------------------------------------------------------
# 横幅带（4× 超采样）
# ---------------------------------------------------------------------------
def _banner(color_hex):
    """960×96 辉光横幅带：两端斜切收头 + 中央高亮核 + 顶/底 1px 亮线。
    渐变用「水平条 × 垂直乘子 × 多边形 mask」三张 L 图相乘（避免逐像素循环）。"""
    from PIL import ImageChops
    w, h = 960, 96
    img, d = canvas(w, h)
    rgb = hx(color_hex)[:3]
    notch = 26.0
    # 1) 多边形 mask（带体：两端 45° 斜切）
    mask = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(mask).polygon(
        [P(notch, 6), P(w, 6), P(w - notch, h - 6), P(0, h - 6)], fill=255)
    # 2) 水平 α 渐变（两端暗 → 中央亮，core^1.6）
    xs = np.linspace(0.0, 1.0, w * S, dtype=np.float32)
    core = 1.0 - np.abs(xs - 0.5) / 0.5
    ha = (38 + 96 * (core ** 1.6)).astype(np.uint8)
    hbar = Image.fromarray(np.tile(ha, (h * S, 1)), "L")
    # 3) 垂直乘子（中间略亮的体积感）
    ys = np.linspace(0.0, 1.0, h * S, dtype=np.float32)
    vt = 1.0 - np.abs(ys - 0.5) / 0.5
    va = (0.72 + 0.28 * vt * 1.0).astype(np.float32)
    vbar = Image.fromarray(
        np.tile((va * 255).astype(np.uint8).reshape(-1, 1), (1, w * S)), "L")
    alpha = ImageChops.multiply(ImageChops.multiply(hbar, vbar), mask)
    solid = Image.new("RGBA", (w * S, h * S), (rgb[0], rgb[1], rgb[2], 255))
    solid.putalpha(alpha)
    img.alpha_composite(solid)
    # 4) 中央高亮核带（独立层 + 高斯模糊软化边界，标题压上面）
    core = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    ImageDraw.Draw(core).polygon(
        [P(w * 0.30, 6), P(w * 0.70, 6), P(w * 0.70 - notch, h - 6), P(w * 0.30 + notch, h - 6)],
        fill=(rgb[0], rgb[1], rgb[2], 52))
    core = core.filter(ImageFilter.GaussianBlur(36))   # 🔴 4× 画布：36px ≈ 1x 9px，够软
    img.alpha_composite(core)
    # 5) 顶/底 1px 亮线
    d.line([P(notch + 2, 7.5), P(w - 2, 7.5)], fill=(rgb[0], rgb[1], rgb[2], 235), width=S)
    d.line([P(2, h - 7.5), P(w - notch - 2, h - 7.5)], fill=(rgb[0], rgb[1], rgb[2], 150), width=S)
    return save(img, w, h, "ui_result_won_banner_v1.png" if color_hex == C_GOLD
                else "ui_result_lost_banner_v1.png")


def canvas(w, h):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


# ---------------------------------------------------------------------------
# 光标（4× 超采样 → 48×48；亮主体 + 深描边 = 亮/暗底都可辨）
# ---------------------------------------------------------------------------
def _outline(d, pts, width, color):
    d.line(pts + [pts[0]], fill=color, width=width, joint="curve")


def gen_cursor_default():
    """默认箭头：钢白主体 + 耀青描边 + 深衬边（hotspot 4,2）。
    🔴 箭头要撑满画布（系统箭头观感），48 画布中占 ~26×44。"""
    w = 48
    img, d = canvas(w, w)
    # 经典箭头 path（1x 逻辑坐标经 P() 放大，bbox ≈ 26×44）
    pts = [P(10, 2), P(10, 38), P(18.5, 31), P(24.5, 45), P(30.5, 42.5), P(24.5, 28), P(35, 28)]
    # 1) 深色衬边（放大 1.6px，保证亮底可辨）
    for dx in (-1.6, 0, 1.6):
        for dy in (-1.6, 0, 1.6):
            if dx or dy:
                d.polygon([(x + dx, y + dy) for x, y in pts], fill=hx(C_INK, 210))
    # 2) 主体
    d.polygon(pts, fill=hx(C_STEEL, 255))
    # 3) 耀青描边
    _outline(d, pts, S, hx(C_ALLY, 255))
    return save(img, w, w, "ui_cursor_default_v1.png")


def gen_cursor_place():
    """放置准星：四刻十字 + 中心圆点 + 细环，耀青；深衬底。hotspot 24,24。"""
    w = 48
    img, d = canvas(w, w)
    c = 24.0
    # 深衬底（整组符号放大 1.6px 的深色版，亮底可辨）
    for dx in (-1.5, 0, 1.5):
        for dy in (-1.5, 0, 1.5):
            if dx or dy:
                for ang in (0, 90, 180, 270):
                    a = math.radians(ang)
                    d.line([P(c + dx + math.cos(a) * 9, c + dy + math.sin(a) * 9),
                            P(c + dx + math.cos(a) * 20, c + dy + math.sin(a) * 20)],
                           fill=hx(C_INK, 220), width=S)
                d.ellipse([P(c + dx - 6, c + dy - 6), P(c + dx + 6, c + dy + 6)],
                          fill=hx(C_INK, 220))
    # 主体：四刻
    for ang in (0, 90, 180, 270):
        a = math.radians(ang)
        d.line([P(c + math.cos(a) * 9, c + math.sin(a) * 9),
                P(c + math.cos(a) * 20, c + math.sin(a) * 20)],
               fill=hx(C_ALLY, 255), width=2 * S)
    # 细环
    d.ellipse([P(c - 13, c - 13), P(c + 13, c + 13)], outline=hx(C_ALLY, 210), width=S)
    # 中心圆点
    d.ellipse([P(c - 3.5, c - 3.5), P(c + 3.5, c + 3.5)], fill=hx(C_ALLY, 255))
    return save(img, w, w, "ui_cursor_place_v1.png")


def gen_cursor_deny():
    """禁止：警报红圆环 + 45° 斜杠 + 内暗底。hotspot 24,24。"""
    w = 48
    img, d = canvas(w, w)
    c = 24.0
    r = 15.0
    # 内暗底圆（挡背景，保证环与杠可辨）
    d.ellipse([P(c - r, c - r), P(c + r, c + r)], fill=hx(C_INK, 185))
    # 外深衬环
    d.ellipse([P(c - r - 1.6, c - r - 1.6), P(c + r + 1.6, c + r + 1.6)],
              outline=hx(C_INK, 220), width=2 * S)
    # 红环
    d.ellipse([P(c - r, c - r), P(c + r, c + r)], outline=hx(C_ALERT, 255), width=2 * S + 2)
    # 斜杠（左上→右下）
    k = r * 0.7071
    d.line([P(c - k, c - k), P(c + k, c + k)], fill=hx(C_ALERT, 255), width=2 * S + 2)
    # 杠端深衬（保证杠在环内也可辨）
    return save(img, w, w, "ui_cursor_deny_v1.png")


# ---------------------------------------------------------------------------
# manifest 登记（幂等）
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
    print("[gen_ui_result_pack_v1] 结算页情绪背景/横幅 + 三态光标 · 7 件")
    done = [
        gen_won_bg(),
        gen_lost_bg(),
        _banner(C_GOLD),
        _banner(C_ALERT),
        gen_cursor_default(),
        gen_cursor_place(),
        gen_cursor_deny(),
    ]
    sizes = {
        "ui_result_won_bg_v1.png": [1920, 1080],
        "ui_result_lost_bg_v1.png": [1920, 1080],
        "ui_result_won_banner_v1.png": [960, 96],
        "ui_result_lost_banner_v1.png": [960, 96],
        "ui_cursor_default_v1.png": [48, 48],
        "ui_cursor_place_v1.png": [48, 48],
        "ui_cursor_deny_v1.png": [48, 48],
    }
    register([{"file": "ui/" + n, "size": sizes[n]} for n in done])
    print("[done] 7 assets -> art/2d/ui/")


if __name__ == "__main__":
    main()
