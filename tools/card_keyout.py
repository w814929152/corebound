# -*- coding: utf-8 -*-
"""卡面插画 keyout（去底色）+ 安全区缩放。

背景是纯 #141726，主体是厚描边扁平几何 —— 用「四边 flood fill 求背景连通区」而不是
全图色差阈值，避免主体内部深色块（如 #1B2030）被误抠成透明。

处理顺序：
  1. 右下角平台水印补丁（用底色覆盖，水印不在主体区）
  2. flood fill from edges -> 背景 mask
  3. 边缘 1px 抗锯齿（按与底色的距离给半透明 alpha）
  4. 裁到主体包围盒（留 margin），等比缩放塞进 460x460 安全区
  5. 输出 _t.png（1024 透明底原尺寸）+ _460.png（安全区尺寸）

用法：
  py -3.9 tools/card_keyout.py --src art/_review/batch1/raw_Arrow.png \
      --out art/2d/cards/card_arrow_v1.png
"""
import argparse
import os
from collections import deque

from PIL import Image, ImageChops, ImageFilter

BG = (20, 23, 38)          # #141726
SAFE = 460                 # 卡框插画安全区边长
MARGIN_RATIO = 0.06        # 主体占安全区的比例留白


def _dist2(p, q):
    return (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2


def sample_bg(im):
    """自适应采样背景色。

    🔴 实测教训：AI 出图**不遵守**提示词里的 #141726 —— 同一批 10 张的背景色
    分别落在 #1E2229 / #313A46 / #060402 等位置。写死底色 keyout 会整批失败，
    所以底色必须从图像边缘采样。取中位数抗噪（边缘可能被主体侵占一部分）。
    """
    w, h = im.size
    px = im.load()
    pts = []
    for x in range(0, w, 6):
        pts.append(px[x, 1]); pts.append(px[x, h - 2])
    for y in range(0, h, 6):
        pts.append(px[1, y]); pts.append(px[w - 2, y])
    med = tuple(sorted(p[i] for p in pts)[len(pts) // 2] for i in range(3))
    # 用 90 分位距离当容差，兼容轻微暗角/渐变
    dists = sorted(_dist2(p[:3], med) ** 0.5 for p in pts)
    p90 = dists[int(len(dists) * 0.90)]
    return med, max(24, min(60, p90 * 1.6))


def patch_watermark(im, bg):
    """右下角水印区用底色覆盖（该区域按构图约定不含主体）。"""
    w, h = im.size
    x0, y0 = int(w * 0.74), int(h * 0.90)
    px = im.load()
    for y in range(y0, h):
        for x in range(x0, w):
            px[x, y] = bg + (255,) if im.mode == "RGBA" else bg
    return im


def degrid(im: Image.Image, strength: int = 5, passes: int = 2) -> Image.Image:
    """抹掉 AI 背景网格线在 keyout 后留下的 1-2px 细线前景。

    🔴 第二批实测教训：锚点允许「optional single-layer grid」，AI 会把网格画成
    2-3px 的浅灰线。flood fill 只吃掉格子里与底色同色的区域，网格线本身因为
    与底色有色差被当成前景保留 —— 合成到卡面上就是一层游离的方格，非常脏。
    处理：alpha 二值 → 开运算（先侵蚀后膨胀）抹掉细线 → 膨胀 1px 作保留掩膜
    → 与原 alpha 相乘（保留原抗锯齿过渡，不把边缘削成硬锯齿）。主体描边 >8px，
    5×5 开运算不会伤到；合法的内部结构线也都在 4px 以上。
    """
    a = im.getchannel("A")
    binary = a.point(lambda v: 255 if v >= 48 else 0)
    # 单遍 5×5 只能抹掉独立细线；网格线两端往往连着主体描边，会被膨胀回来。
    # 多遍开运算等价于「只保留 >= 2*passes px 厚的块」，连线结构一并断开。
    opened = binary
    for _ in range(passes):
        opened = opened.filter(ImageFilter.MinFilter(strength))
    for _ in range(passes):
        opened = opened.filter(ImageFilter.MaxFilter(strength))
    keep = opened.filter(ImageFilter.MaxFilter(3))
    im.putalpha(ImageChops.multiply(a, keep))
    return im


def keyout(path, tol=0, edge_tol=64, connectivity_only=False, do_degrid=False):
    """connectivity_only：只按「背景连通区」判定透明，不做颜色距离杀像素 / 距离衰减。

    适用：主体描边色与底色接近的暗色调图（如深藏青描边 + 深夜幕紫底）。
    此时任何基于颜色距离的 alpha 判定都会把描边削成半透明（实测 alpha 掉到 ~80，
    白底预览里描边发白），只能靠 flood fill 的连通性来分。
    代价：主体内部的封闭暗区（炮口阴影、件间缝隙）会保留为不透明 —— 在暗色卡面上
    这些区域读作阴影，可接受。
    """
    im = Image.open(path).convert("RGBA")
    base, auto_tol = sample_bg(im)
    tol = tol if tol > 0 else auto_tol
    im = patch_watermark(im, base)
    w, h = im.size
    px = im.load()
    tol2 = tol * tol

    # 0) 中值滤波抹掉背景上 1-2px 的极淡网格线 —— 否则 flood fill 被网格隔绝，
    #    背景无法从四边连通（实测 trim box 变成整图 1024x1024）。
    #    主体是有厚描边的粗块（>5px），中值滤波不会伤到它。
    filt = im.convert("RGB").filter(ImageFilter.MedianFilter(5))
    fp = filt.load()

    # 1) 背景连通区（四边起 flood fill，跑在滤波图上）
    mask = bytearray(w * h)
    dq = deque()
    seeds = []
    for x in range(w):
        seeds.append((x, 0)); seeds.append((x, h - 1))
    for y in range(h):
        seeds.append((0, y)); seeds.append((w - 1, y))
    for x, y in seeds:
        i = y * w + x
        if not mask[i] and _dist2(fp[x, y], base) <= tol2:
            mask[i] = 1
            dq.append((x, y))
    while dq:
        x, y = dq.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if not mask[i] and _dist2(fp[nx, ny], base) <= tol2:
                    mask[i] = 1
                    dq.append((nx, ny))

    # 2) 写 alpha：背景连通区全透；与底色几乎同色的孤立小块（被网格围住的背景）也透；
    #    背景邻接像素按距离给半透明（抗锯齿边）
    edge2 = edge_tol * edge_tol
    transparent = 0
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            i = y * w + x
            r, g, b, _ = px[x, y]
            d2 = _dist2((r, g, b), base)
            if mask[i] or (not connectivity_only and d2 <= tol2):
                px[x, y] = (r, g, b, 0)
                transparent += 1
                continue
            if connectivity_only:
                # 连通域模式：主体一律全不透明，只对紧邻透明区的 1px 做轻微羽化
                near_bg = (
                    (x > 0 and mask[i - 1]) or (x < w - 1 and mask[i + 1])
                    or (y > 0 and mask[i - w]) or (y < h - 1 and mask[i + w])
                )
                px[x, y] = (r, g, b, 235 if near_bg else 255)
                if x < minx: minx = x
                if y < miny: miny = y
                if x > maxx: maxx = x
                if y > maxy: maxy = y
                continue
            near = (
                (x > 0 and mask[i - 1]) or (x < w - 1 and mask[i + 1])
                or (y > 0 and mask[i - w]) or (y < h - 1 and mask[i + w])
            )
            if near:
                a = 255 if d2 >= edge2 else int(255 * (d2 / edge2) ** 0.5)
                px[x, y] = (r, g, b, max(0, a))
            else:
                # 远离背景区但颜色仍接近底色（背景渐变/暗角的残留）→ 渐变淡出，
                # 否则会在插画区留下一个淡淡的矩形色块（实测第一版合成图的矩形残影）
                d = d2 ** 0.5
                if d < edge_tol:
                    a = int(255 * ((d - tol) / max(1.0, edge_tol - tol)))
                    px[x, y] = (r, g, b, max(0, min(255, a)))
            if x < minx: minx = x
            if y < miny: miny = y
            if x > maxx: maxx = x
            if y > maxy: maxy = y

    if maxx < 0:
        raise SystemExit("keyout 失败：整图被识别为背景 " + path)

    if do_degrid:
        im = degrid(im)
        # 细线被抹掉后包围盒会收缩（原来是被外围网格线撑开的），必须按
        # 清理后的 alpha 重算，否则插画会在安全区里缩小一圈。
        box = im.getchannel("A").getbbox()
        if box is None:
            raise SystemExit("degrid 失败：主体被整块抹掉 " + path)
    else:
        box = (minx, miny, maxx + 1, maxy + 1)
    trimmed = im.crop(box)

    # 3) 等比塞进安全区
    inner = int(SAFE * (1 - MARGIN_RATIO * 2))
    tw, th = trimmed.size
    scale = min(inner / tw, inner / th)
    new = trimmed.resize((max(1, int(tw * scale)), max(1, int(th * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (SAFE, SAFE), (0, 0, 0, 0))
    canvas.paste(new, ((SAFE - new.width) // 2, (SAFE - new.height) // 2), new)
    info = "bg=%s tol=%d transparent=%.1f%%" % (
        "#%02X%02X%02X" % base, tol, 100.0 * transparent / (w * h))
    return im, canvas, box, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True, help="正式资产路径，会另存 <out>_t.png 与 <out>_460.png")
    ap.add_argument("--tol", type=int, default=26)
    ap.add_argument(
        "--connectivity-only",
        action="store_true",
        help="只按背景连通域抠图（描边色接近底色时用；不做颜色距离杀像素）",
    )
    ap.add_argument(
        "--degrid",
        action="store_true",
        help="清理 AI 背景网格线残留（第二批起默认开启，见 degrid() 说明）",
    )
    args = ap.parse_args()

    full, safe, box, info = keyout(
        args.src, tol=args.tol, connectivity_only=args.connectivity_only,
        do_degrid=args.degrid
    )
    base = args.out[:-4] if args.out.lower().endswith(".png") else args.out
    p1 = base + "_t.png"
    p2 = base + "_460.png"
    os.makedirs(os.path.dirname(os.path.abspath(p1)), exist_ok=True)
    full.save(p1)
    safe.save(p2)
    print("trim", box, "|", info, "->", os.path.basename(p1), os.path.basename(p2))


if __name__ == "__main__":
    main()
