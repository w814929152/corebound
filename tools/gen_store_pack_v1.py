# -*- coding: utf-8 -*-
"""发行素材包 v1 —— 从现有主视觉派生 Steam 店铺 / 库资产。

为什么是"派生"而不是"新画"
---------------------------------------------------------------------------
`keyart_hero_v1` 已经是居中的「核心 + 同心环」蓝图曼陀罗，构图对称，本身就是
为多比例裁切准备的。店铺素材要的是**同一张画的多个画幅**，另画一张只会让不同
尺寸看起来不属于同一个游戏（art-bible §2.1 家族一致性）。

🔴 版式：横幅式（画在上、暗带在下），不是"字压在画上"
  第一版把标题直接叠在画面上：标题正好压住金色核心（主体被挡），压暗蒙版又不够，
  字浮在亮环纹上——怎么调渐变都还是在跟环纹打架。
  现在改为：上半裁画 → 下半固定比例的暗带（压到近底色）→ 标题居暗带正中，
  两者之间一道钢灰发丝线（蓝图语汇）。核心完整留在画区，标题有真正的落位。

🔴 三条硬规则
  1. **不缩放本体**：裁切窗永远从 1920×1080 原图取，只在最后一步降采样，
     避免"先缩到 460 宽再裁"导致的糊边。
  2. **标题进安全区**：文字距画幅边缘 ≥ 4%，且整块落在暗带上。
  3. **2× 超采样**：小尺寸胶囊的笔画不超采样会发灰（与 `gen_ui_*_pack` 同纪律）；
     4K 画幅自动退 1×（内存预算，见 `_ss_for`）。

用法
  py -3.9 tools/gen_store_pack_v1.py                     # 生成全部
  py -3.9 tools/gen_store_pack_v1.py --check-legibility  # 缩到列表尺寸的墨量体检
产物：art/store/*.png + client_icon.ico（**不进引擎** —— art/store/.gdignore 已隔离）
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = "art/2d/ui/keyart_hero_v1.png"
FONT = "assets/fonts/NotoSansSC.ttf"
OUT = "art/store"

## 曼陀罗核心中心（2026-11-09 用金色核心密度窗口实测，非估计值）
CORE = (920, 540)

## 调色板 —— 逐字取 art-bible §2.2
GOLD = (255, 201, 74)
STEEL = (160, 184, 200)
BG = (20, 23, 38)

## 画幅表
##   name, w, h, mode, 标题px, 副标px, 字距, 锁版, 缩放, 下移, 暗带比例
##   mode : rgb 满幅 / rgba 透明底（logo）
##   锁版 : bc 居中 / bl 左下 / "" 无文字
##   缩放 : >1 裁得更紧（图标把核心放大才在 32px 下读得出）；0 = 整幅等比缩放不裁
##   下移 : 裁切窗相对核心下移的比例（核心在画里上抬）
##   暗带 : 0 = 不加暗带（满幅 / 图标）；>0 = 横幅式，底部这块高度放标题
SPECS = [
    ("store_header_capsule",   460,  215, "rgb",  44, 12,  5.0, "bc", 1.00, 0.00, 0.34),
    ("store_small_capsule",    231,   87, "rgb",  26,  0,  3.0, "bc", 1.00, 0.00, 0.36),
    ("store_main_capsule",     616,  353, "rgb",  56, 16,  6.0, "bc", 1.00, 0.00, 0.30),
    ("store_vertical_capsule", 748,  896, "rgb",  92, 26,  9.0, "bc", 1.10, 0.00, 0.19),
    ("store_page_bg",         1438,  810, "rgb",   0,  0,  0.0, "  ", 1.00, 0.00, 0.00),
    ("library_capsule",        600,  900, "rgb",  80, 23,  8.0, "bc", 1.20, 0.00, 0.19),
    ("library_hero",          3840, 1240, "rgb", 176, 52, 16.0, "bl", 1.00, 0.00, 0.26),
    ("library_logo",          1280,  720, "rgba", 250, 72, 24.0, "bc", 0.00, 0.00, 0.00),
    ("community_icon",         184,  184, "rgb",   0,  0,  0.0, "  ", 1.55, 0.00, 0.00),
    ("client_icon",            256,  256, "rgb",   0,  0,  0.0, "  ", 1.55, 0.00, 0.00),
    ## 4K 主视觉：整幅 2× 升频（媒体 / 新闻稿用，不裁）
    ("keyart_hero_4k",        3840, 2160, "rgb",   0,  0,  0.0, "  ", 0.00, 0.00, 0.00),
]

SS = 2
## 超采样上限：float32 中间数组是 O(4·w·h·ch)，2× 在 4K 上会吃掉数百 MB。
SS_BUDGET_PX = 12_000_000


def _ss_for(w: int, h: int) -> int:
    return SS if w * h * SS * SS <= SS_BUDGET_PX else 1


# ---------------------------------------------------------------------------
#  基础工序
# ---------------------------------------------------------------------------
def _font(px: int, weight: int = 700) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(FONT, max(1, px))
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def crop_window(w: int, h: int, zoom: float, bias: float = 0.0) -> Image.Image:
    """按目标比例取窗，窗心对齐核心（可下移 bias），夹在原图范围内。"""
    src = Image.open(SRC).convert("RGB")
    sw, sh = src.size
    ratio = w / h
    cw, ch = (sw, sw / ratio) if sw / ratio <= sh else (sh * ratio, sh)
    cw, ch = cw / zoom, ch / zoom
    cx, cy = CORE[0], CORE[1] + ch * bias
    left = min(max(cx - cw / 2, 0), sw - cw)
    top = min(max(cy - ch / 2, 0), sh - ch)
    return src.crop((int(left), int(top), int(left + cw), int(top + ch)))


def upscale(src: Image.Image, w: int, h: int) -> Image.Image:
    out = src.resize((w, h), Image.LANCZOS)
    if w > src.width * 1.5:
        out = out.filter(ImageFilter.UnsharpMask(radius=1.6, percent=55, threshold=2))
    return out


def vignette(im: Image.Image, strength: float = 0.48) -> Image.Image:
    """径向渐晕：压四角，让核心保持第一层级。"""
    w, h = im.size
    ys, xs = np.mgrid[0:h, 0:w]
    nx = (xs - w / 2) / (w / 2)
    ny = (ys - h / 2) / (h / 2)
    r = np.sqrt(nx ** 2 + ny ** 2) / 1.41
    mul = 1.0 - strength * np.clip(r, 0, 1) ** 2.2
    a = np.array(im).astype(np.float32) * mul[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def fade_bottom(im: Image.Image, ratio: float = 0.18) -> Image.Image:
    """把底边 alpha 渐隐到 0，使画与暗带之间是"沉入黑暗"而不是硬切边。"""
    w, h = im.size
    fade = max(1, int(h * ratio))
    mask = Image.new("L", (w, h), 255)
    d = ImageDraw.Draw(mask)
    for i in range(fade):
        y = h - fade + i
        d.line([(0, y), (w, y)], fill=int(255 * (1.0 - i / fade)))
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def draw_lockup(im: Image.Image, anchor: str, tpx: int, spx: int, tracking: float,
                ss: int, area_top: int = 0, pad_ratio: float = 0.04,
                center_v: bool = False) -> Image.Image:
    """写标题锁版。area_top>0 把整块**居中于** [area_top, h]；center_v 直接整幅垂直居中。"""
    if tpx <= 0 or anchor.strip() == "":
        return im
    S = ss
    w, h = im.size
    d = ImageDraw.Draw(im)
    f_main = _font(tpx * S, 900)
    f_sub = _font(spx * S, 700) if spx > 0 else None

    t_main = "守核"
    main_w = f_main.getlength(t_main)
    asc, desc = f_main.getmetrics()
    line_h = asc + desc

    sub_txt, sub_w, sub_h = None, 0.0, 0.0
    if f_sub is not None:
        sub_txt = "COREBOUND"
        sub_w = sum(f_sub.getlength(c) for c in sub_txt) + tracking * S * (len(sub_txt) - 1)
        sa, sd = f_sub.getmetrics()
        sub_h = (sa + sd) * 1.35

    block_w = max(main_w, sub_w)
    total_h = line_h + sub_h

    pad_x = int(w * pad_ratio)
    if center_v:
        y0 = (h - total_h) / 2
    elif area_top > 0:
        y0 = area_top + (h - area_top - total_h) / 2
    else:
        y0 = h - int(h * pad_ratio) - total_h
    x0 = pad_x if anchor == "bl" else (w - block_w) / 2

    tx = x0 if anchor == "bl" else x0 + (block_w - main_w) / 2
    d.text((tx, y0), t_main, font=f_main, fill=GOLD + (255,),
           stroke_width=max(1, int(1.1 * S)), stroke_fill=(0, 24, 48, 235))

    if f_sub is not None:
        sx = x0 if anchor == "bl" else x0 + (block_w - sub_w) / 2
        sy = y0 + line_h
        cx = sx
        for ch in sub_txt:
            d.text((cx, sy), ch, font=f_sub, fill=STEEL + (255,))
            cx += f_sub.getlength(ch) + tracking * S
    return im


def hairline(canvas: Image.Image, y: int, w: int, ss: int) -> None:
    """蓝图发丝分隔线：两端各留 8%，不画满 —— 满幅横线会像 UI 表格线。"""
    d = ImageDraw.Draw(canvas)
    d.line([(int(w * 0.08), y), (int(w * 0.92), y)],
           fill=(*STEEL, 64), width=max(1, ss))


# ---------------------------------------------------------------------------
#  两种版式
# ---------------------------------------------------------------------------
def compose_band(spec) -> Image.Image:
    """横幅式：上方画区 + 下方暗带（标题居暗带正中）。"""
    name, w, h, mode, tpx, spx, track, anchor, zoom, bias, band = spec
    ss = _ss_for(w, h)
    band_h = int(round(h * band))
    art_h = h - band_h

    art = crop_window(w, art_h, max(zoom, 1.0), bias).resize((w, art_h), Image.LANCZOS)
    art_big = art.resize((w * ss, art_h * ss), Image.LANCZOS)
    art_big = vignette(art_big, 0.45)
    art_big = fade_bottom(art_big, 0.18)

    canvas = Image.new("RGB", (w * ss, h * ss), BG)
    canvas.paste(art_big, (0, 0), art_big)
    hairline(canvas, art_h * ss - max(1, ss * 2), w * ss, ss)
    canvas = draw_lockup(canvas, anchor, tpx, spx, track, ss, area_top=art_h * ss)
    return canvas


def compose_full(spec) -> Image.Image:
    """满幅式：不裁 / 只裁比例，没有暗带（背景图、图标、4K）。"""
    name, w, h, mode, tpx, spx, track, anchor, zoom, bias, band = spec
    ss = _ss_for(w, h)
    if zoom <= 0:
        base = upscale(Image.open(SRC).convert("RGB"), w, h)
    else:
        base = crop_window(w, h, zoom, bias).resize((w, h), Image.LANCZOS)
        if zoom >= 1.5:
            base = base.filter(ImageFilter.UnsharpMask(radius=1.2, percent=45, threshold=3))
    big = base.resize((w * ss, h * ss), Image.LANCZOS) if ss > 1 else base
    big = vignette(big, 0.48)
    big = draw_lockup(big, anchor, tpx, spx, track, ss)
    return big


def compose_logo(spec) -> Image.Image:
    """库 Logo：**只有标题**，画布全透明。
    🔴 不能"画满再抠底"—— 第一版这么做，曼陀罗主体也留在 alpha 里，
       叠到库主视觉上等于叠了第二张画。"""
    name, w, h, mode, tpx, spx, track, anchor, zoom, bias, band = spec
    ss = _ss_for(w, h)
    canvas = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    return draw_lockup(canvas, anchor, tpx, spx, track, ss, center_v=True)


def build(spec) -> str:
    name, w, h, mode = spec[0], spec[1], spec[2], spec[3]
    band = spec[10]
    ss = _ss_for(w, h)
    if mode == "rgba":
        big = compose_logo(spec)
    else:
        big = compose_band(spec) if band > 0 else compose_full(spec)
    out = big.resize((w, h), Image.LANCZOS) if ss > 1 else big
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    out.save(path)
    print("  %-26s %4dx%-4d ss=%d %-4s %s" % (
        name, w, h, ss,
        "logo" if mode == "rgba" else ("band" if band > 0 else "full"), ""))
    return path


def make_ico() -> None:
    src = Image.open(os.path.join(OUT, "client_icon.png")).convert("RGBA")
    src.save(os.path.join(OUT, "client_icon.ico"),
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("  %-26s %s" % ("client_icon.ico", "16/24/32/48/64/128/256"))


# ---------------------------------------------------------------------------
#  体检
# ---------------------------------------------------------------------------
def check_legibility() -> None:
    """缩到 Steam 实际展示宽后，量标题带与背景的亮度对比。只报数，阈值供人工复核。"""
    rows = [("store_header_capsule", 120), ("store_small_capsule", 120),
            ("store_main_capsule", 192), ("library_capsule", 120)]
    print("\n[legibility] 缩到列表尺寸后的标题对比度（阈值 ≥3.0:1）")
    for name, target_w in rows:
        im = Image.open(os.path.join(OUT, name + ".png")).convert("RGB")
        k = target_w / im.width
        small = im.resize((target_w, max(1, round(im.height * k))), Image.LANCZOS)
        lum = np.array(small).astype(np.float32).mean(axis=2)
        band = lum[int(lum.shape[0] * 0.66):]        # 暗带在下方 34% 内
        p95, p20 = np.percentile(band, 95), np.percentile(band, 20)
        contrast = (p95 + 5.0) / (p20 + 5.0)
        print("  %-24s %3dx%-3d  p95=%.0f p20=%.0f  %.2f:1 %s"
              % (name, small.width, small.height, p95, p20, contrast,
                 "OK" if contrast >= 3.0 else "偏低"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-legibility", action="store_true")
    args = ap.parse_args()
    if not os.path.exists(SRC):
        sys.exit("缺主视觉：" + SRC)
    if args.check_legibility:
        check_legibility()
        return
    print("[gen] 源 = %s  核心 = %s" % (SRC, str(CORE)))
    for spec in SPECS:
        build(spec)
    make_ico()
    print("[done] %d 件 → %s/" % (len(SPECS) + 1, OUT))


if __name__ == "__main__":
    main()
