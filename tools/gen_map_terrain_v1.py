#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
守核 Corebound · 关卡地图地形贴图 v1 生成器
===============================================================================
为什么做这一包
  战场地形此前 100% 程序化：三档材质 = 三个 draw_circle、岩脊 = 深色多边形、
  出怪口 = 一条低α弧。整张地图读起来是「三个同心色块 + 几块黑板」，
  10 张变体（tri-fissure / variant-a..h / fusion）除了轮廓不同，**没有任何材质**。
  本包把「地表材质 + 岩脊体块」烘焙成位图，**不动任何几何与布局**：
  贴图按 `scripts/data/map_variants.gd` 的岩脊表出图，运行时只换一层填充。

数据结构（🔴 本包唯一的真相来源）
  岩脊 / 出怪口数据**从 GDScript SSOT 解析**，不手抄：
      scripts/data/map_variants.gd  →  VARIANTS[*].ridges / spawn_arcs / open_deg
  解析后做算术自检（Σ脊宽 == 360 − open_deg），与 `MapVariants.validate_arcs()`
  同一口径。对不上直接报错退出 —— 宁可不出图，不出错图。

调色纪律（🔴 本包最关键的决定：灰度 × 环境档色）
  贴图是**灰度值图**（R=G=B），运行时 `draw_texture_rect(..., modulate)` 乘
  当前环境档的场地色 `env.field × (255 / G_BAND_MID)`：
      · 三档材质 = 灰度 134 / 161 / 190 ⇒ 乘完正好等于 field ×0.84 / ×1.00 / ×1.18
        （与 `_draw_map_layer` 原有明度阶梯逐位等价，4 档换装自动生效）；
      · 岩脊 = 断崖裂缝：谷底 ×0.56 + 崖唇高光 ×1.52（全场最亮的地形元素）；
      · 8bit 有上限 ⇒ 所有灰度**按「场地底色倍数」声明**（`gr(ratio)`），
        想画比底色更亮的元素（崖唇），必须先把基准档压到 161 而不是 255。
  🔴 所以本文件里没有"随手取的灰度值"：每个数字都是 `gr(倍率)` 算出来的。

坐标契约（🔴 改任何一侧都必须同步改另一侧）
  R_TEX   = 60.0 u     贴图覆盖半径（战场材质到 44u，岩脊 r1 ≤ 58u，留 2u 余量）
  TEX_PX  = 1024       1024 / 120u = 8.53 px/u ≈ 1080p 实机 sc(≈8.5) 的 1:1
  MAP_BAND_R = [16, 30, 44]   ← `monster_layer.gd` 的常量，改那边要改这里
  角度口径 = 引擎同款：0° = +x（东），顺时针（y 向下为正），与 `_dir(a)` 一致

分层（生成 → 运行时）
  ① 地表：三档材质（软边 0.3u）+ 细颗粒 + 同心岩层纹理 + 三档各自的材质特征
     （内环热裂 / 中环石板缝+錾边 / 外环碎砾）
  ② 岩脊：落影（光来自左上 §4.1）→ 谷底 → 贴壁暗边 → 受光唇线 → 崖口碎石 → 谷底裂纹
  ③ 散石：46.6u 近场 + 57.4u 远景（避开岩脊扇区）
  🔴 出怪口土带 / 阵地台**不进贴图** —— 它们由玩法数据驱动（换图、建塔状态），
     烘焙会把「状态」焊死在图里。

用法（⚠️ 本机默认 python 无 PIL，出图请指定带 Pillow 的解释器）：
  <py-with-PIL> tools/gen_map_terrain_v1.py            # 出图 + 登记 manifest + 接触表
  <py-with-PIL> tools/gen_map_terrain_v1.py --check    # 只做数据自检，不出图
"""
import json
import math
import os
import random
import re
import sys
import zlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "art", "2d", "maps")
REVIEW = os.path.join(ROOT, "art", "_review")
MANIFEST = os.path.join(ROOT, "art", "manifest.json")
VARIANTS_GD = os.path.join(ROOT, "scripts", "data", "map_variants.gd")

# ---------------------------------------------------------------------------
# 几何 / 分辨率
# ---------------------------------------------------------------------------
R_TEX = 60.0            # 贴图覆盖半径（u）
TEX_PX = 1024           # 最终边长
SS = 4                  # 矢量层超采样倍率（岩脊在 4096² 上画，再降采样）
PPU = TEX_PX / (2.0 * R_TEX)      # 8.5333 px/u（最终图）
PPU_SS = PPU * SS                 # 34.13 px/u（超采样画布）

MAP_BAND_R = [16.0, 30.0, 44.0]   # 🔴 必须与 monster_layer.gd 常量一致

# ---------------------------------------------------------------------------
# 灰度：**一律按「场地底色的倍数」声明**，再换算成 0~255
# ---------------------------------------------------------------------------
## 🔴 为什么要这样写：整套地形是「灰度 × 场地档色」的乘法结果，唯一有意义的是
##   「这个像素相当于底色的多少倍」。直接写灰度值，改一处不知道别处会变成几倍；
##   而 8bit 有上限 —— 想要比底色更亮的元素（崖唇高光 1.5×），必须先把基准压下来。
##   G_MAX_RATIO = 255 灰度对应的倍数；基准档 1.00× ⇒ 灰度 161 ⇒ 运行时倍率 255/161。
##   🔴 运行时 `monster_layer.MAP_TEX_GAIN` 必须等于 `255 / G_BAND_MID`（生成时会打印）。
G_MAX_RATIO = 1.58


def gr(ratio):
    """场地底色倍数 → 8bit 灰度（超过 G_MAX_RATIO 一律压到 255）。"""
    return max(0, min(255, int(round(255.0 * ratio / G_MAX_RATIO))))


G_BAND_OUT = gr(0.84)      # 外环「荒原」
G_BAND_MID = gr(1.00)      # 中环「石板」（基准档 = 场地底色）
G_BAND_IN = gr(1.18)       # 内环「焦土」
G_FIELD = gr(1.00)         # 44u 以外的空地（与基准同灰 → 与父层场地圆无缝）

# 三档材质特征
G_SLAB_SEAM = gr(0.80)     # 中环石板缝主笔
G_SLAB_LIP = gr(1.06)      # 石板缝左上錾边
G_HEAT_CRACK = gr(1.05)    # 内环热裂
G_RUBBLE_D = 16            # 外环碎砾相对外环基色的明暗偏移（灰度差，±）

# 🔴 岩脊 = **断崖裂缝**（设计里就叫「东南断崖 / 西断墙 / 北短脊」），不是"隆起的高台"。
#   俯视下最省事、最不会读错的做法：深底 + 一圈**受光的唇线** ⇒ 一眼看出"这里有深度、不能站"。
#   试过"分块岩面 + 棱线"（想画成石头），实机读作"折起来的铁皮/木板"——已废弃。
G_RIFT_FLOOR = gr(0.56)    # 裂谷底（能看清里边，但不是黑洞）
G_RIFT_DEEP = gr(0.30)     # 谷底贴壁暗边（投影）
G_RIFT_LIP = gr(1.52)      # 崖唇受光线（全场最亮的地形元素，> 中环地面 ⇒ 读作"棱"）
G_RIFT_CRACK = gr(0.34)    # 谷底短裂纹（比谷底更暗 ⇒ 凹进去）
G_DEBRIS = gr(0.78)        # 崖口崩落碎石
G_BOULDER = gr(0.55)       # 散石体
G_BOULDER_LIP = gr(1.30)   # 散石受光唇线

SHADOW_A = 118          # 岩脊落影 alpha（在透明底上，运行时压在地表上）
BOULDER_SHADOW_A = 96

LIGHT = (-0.707, -0.707)   # 光来自左上（art-bible §4.1：影落右下）


# ---------------------------------------------------------------------------
#  ① 数据解析（从 GDScript SSOT 读，不手抄）
# ---------------------------------------------------------------------------
_RE_VARIANT = re.compile(r'^\t"([A-Za-z0-9_\-]+)": \{\s*$')
_RE_GROUP = re.compile(r'^\t\t"(ridges|spawn_arcs|sites)": \[')
_RE_ARC = re.compile(
    r'\{"id": "(\w+)", "name": "([^"]*)", "a0": ([-\d.]+), "a1": ([-\d.]+)'
    r'(?:, "r0": ([-\d.]+), "r1": ([-\d.]+), "pad": ([-\d.]+))?\}')
_RE_OPEN = re.compile(r'^\t\t"open_deg": ([-\d.]+),')
_RE_GROUP_END = re.compile(r'^\t\t\],')
_RE_VARIANT_END = re.compile(r'^\t\},')


def parse_variants(path=VARIANTS_GD):
    """解析 `map_variants.gd` 的 VARIANTS 字面量 → {id: {open_deg, ridges, arcs}}。"""
    out = {}
    cur = None
    group = None
    with open(path, encoding="utf-8") as fp:
        for raw in fp:
            line = raw.rstrip("\n")
            m = _RE_VARIANT.match(line)
            if m:
                cur = m.group(1)
                out[cur] = {"open_deg": None, "ridges": [], "arcs": []}
                group = None
                continue
            if cur is None:
                continue
            m = _RE_OPEN.match(line)
            if m:
                out[cur]["open_deg"] = float(m.group(1))
                continue
            m = _RE_GROUP.match(line)
            if m:
                group = m.group(1)
                continue
            if _RE_GROUP_END.match(line):
                group = None
                continue
            if _RE_VARIANT_END.match(line):
                cur = None
                group = None
                continue
            if group in ("ridges", "spawn_arcs"):
                m = _RE_ARC.search(line)
                if m:
                    rid, name, a0, a1 = m.group(1), m.group(2), float(m.group(3)), float(m.group(4))
                    if group == "ridges":
                        out[cur]["ridges"].append({
                            "id": rid, "name": name, "a0": a0, "a1": a1,
                            "r0": float(m.group(5)), "r1": float(m.group(6)),
                            "pad": float(m.group(7))})
                    else:
                        out[cur]["arcs"].append({"id": rid, "name": name, "a0": a0, "a1": a1})
    return out


def check_variants(v):
    """算术自检：与 `MapVariants.validate_arcs()` 同口径（脊宽和 = 360 − 开口）。"""
    ok = True
    for mid, d in v.items():
        if d["open_deg"] is None or not d["ridges"] or not d["arcs"]:
            print(f"  ! {mid}: 缺 open_deg / 脊 / 弧")
            ok = False
            continue
        rsum = sum(r["a1"] - r["a0"] for r in d["ridges"])
        asum = 0.0
        for a in d["arcs"]:
            a0 = a["a0"] % 360.0
            a1 = a["a1"] % 360.0
            if a1 <= a0:
                a1 += 360.0
            asum += a1 - a0
        e1 = abs(360.0 - d["open_deg"] - rsum)
        e2 = abs(d["open_deg"] - asum)
        bad = e1 > 1e-6 or e2 > 1e-6 or d["open_deg"] < 300.0 - 1e-6
        ok = ok and not bad
        print(f"  {'!' if bad else '+'} {mid:<13} 脊 {len(d['ridges'])} 段 Σ{rsum:5.1f}° · "
              f"弧 {len(d['arcs'])} 段 Σ{asum:5.1f}° · 开口 {d['open_deg']:5.1f}°"
              f"{'  ← 不合口径' if bad else ''}")
    return ok


# ---------------------------------------------------------------------------
#  ② 地表层（三档材质 + 颗粒 + 岩层纹理）
# ---------------------------------------------------------------------------
def _noise(size, cell, rng):
    small = Image.new("L", (cell, cell))
    small.putdata([rng.randrange(256) for _ in range(cell * cell)])
    return small.resize((size, size), Image.BICUBIC)


def _weighted_noise(size, rng, octaves):
    """多倍频噪声的加权平均（Image.blend 连乘，免逐像素循环）。"""
    acc = None
    wsum = 0.0
    for cell, w in octaves:
        oct_img = _noise(size, cell, rng)
        if acc is None:
            acc = oct_img
            wsum = w
        else:
            wsum += w
            acc = Image.blend(acc, oct_img, w / wsum)
    return acc


def _band_base():
    """三档材质圆（512 原生 + BILINEAR 放大 ⇒ 0.3u 软边，比原来的硬圆边更像地面）。"""
    low = 512
    ppu = low / (2.0 * R_TEX)
    cx = cy = low * 0.5
    img = Image.new("L", (low, low), 0)

    def disc(r_u, fill):
        r = r_u * ppu
        ImageDraw.Draw(img).ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)

    disc(MAP_BAND_R[2], G_BAND_OUT)
    disc(MAP_BAND_R[1], G_BAND_MID)
    disc(MAP_BAND_R[0], G_BAND_IN)

    # 同心岩层纹理（很淡：±1.2%，呼应同心环的语言，但不与刻度线抢）—— 在 512 上算，省 4 倍时间
    px = img.load()
    r_lim = MAP_BAND_R[2] * ppu
    for y in range(low):
        dy = y - cy
        for x in range(low):
            dx = x - cx
            r = math.hypot(dx, dy)
            if r > r_lim:
                continue
            s = 1.0 + 0.012 * math.sin(r / ppu * 2.1 + 0.7) * math.sin(math.atan2(dy, dx) * 3.0)
            px[x, y] = max(0, min(255, int(px[x, y] * s)))

    img = img.resize((TEX_PX, TEX_PX), Image.BILINEAR)

    # 🔴 三档若只有明度差、没有**材质特征**，远看仍是"三个同心色块"。
    #    按环带各自的语义加特征（全部是 5~20% 的灰度差，不做花纹）：
    #      内环 0–16u  焦土：放射状热裂纹 + 焦斑
    #      中环 16–30u 石板：大块石板缝（这条最值钱 —— 可建区读作"铺装地面"）
    #      外环 30–44u 荒原：碎砾 + 稀疏长裂缝，越靠边越碎
    _ground_features(img)

    # 颗粒：先用 field 灰铺满整张（44u 外也是地面），再用噪声明暗乘一遍
    field = Image.new("L", (TEX_PX, TEX_PX), G_FIELD)
    # 🔴 颗粒要**细而均匀**：粗噪声（40 格 ≈ 3u 一团）在俯视下会糊成「云斑 / 水渍」，
    #    最细噪声（2px）会变成"电视雪花"。实测 160 / 420 格两档、±4% 最像岩面。
    grain = _weighted_noise(TEX_PX, random.Random(0xC0DE), [(160, 1.0), (420, 0.7)])
    grain = grain.point(lambda x: min(255, int(240 + (x - 128) * 0.18)))
    img = Image.composite(img, field, img.point(lambda x: 255 if x > 0 else 0))
    img = ImageChops.multiply(img, grain)

    # 归一：把「基准档」实测灰度拉回 G_BAND_MID → 运行时倍率恒定（见文件头「调色纪律」）
    g = _measure_band(img, 23.0, [])
    k = G_BAND_MID / max(1.0, g)
    img = img.point(lambda x: min(255, int(round(x * k))))
    return img, k


def _measure_band(img, r_u, ridges, samples=96):
    """在半径 r_u 上采样平均灰度（跳过岩脊扇区，只量裸露地表）。"""
    px = img.load()
    cx = cy = TEX_PX * 0.5
    tot, n = 0, 0
    for i in range(samples):
        a = math.tau * i / samples
        if any(_in_sector(r_u, a, rg, -1.0) for rg in ridges):
            continue
        x = int(cx + math.cos(a) * r_u * PPU)
        y = int(cy + math.sin(a) * r_u * PPU)
        if not (0 <= x < TEX_PX and 0 <= y < TEX_PX):
            continue
        v = px[x, y]
        tot += v[0] if isinstance(v, tuple) else v
        n += 1
    return tot / max(1, n)


## 环带内的一段直线裁剪：返回 [(t0, t1), ...]，t ∈ [0,1] 沿 p0→p1（采样足够密，
##   只用于贴图绘制，不追求解析精度）。
def _clip_to_band(p0, p1, r0, r1, seg=64):
    out, run = [], None
    for i in range(seg + 1):
        t = i / seg
        x = p0[0] + (p1[0] - p0[0]) * t
        y = p0[1] + (p1[1] - p0[1]) * t
        r = math.hypot(x - TEX_PX * 0.5, y - TEX_PX * 0.5) / PPU
        inside = r0 <= r <= r1
        if inside and run is None:
            run = t
        elif not inside and run is not None:
            out.append((run, t))
            run = None
    if run is not None:
        out.append((run, 1.0))
    return out


def _ground_features(img):
    """三档材质特征：石板缝（中环）/ 热裂纹与焦斑（内环）/ 碎砾（外环）。"""
    d = ImageDraw.Draw(img)
    rng = random.Random(0x5EED1)
    cx = cy = TEX_PX * 0.5

    def pt(a, r):
        return (cx + math.cos(a) * r * PPU, cy + math.sin(a) * r * PPU)

    # ① 中环石板缝：随机方向的长弦，只留环带内的段（灰 −13%）
    for _ in range(22):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(MAP_BAND_R[0] + 3.0, MAP_BAND_R[1] - 2.0)
        p0 = pt(a, r)
        ln = rng.uniform(7.0, 17.0)
        da = a + rng.uniform(-0.9, 0.9)
        p1 = (p0[0] + math.cos(da) * ln * PPU, p0[1] + math.sin(da) * ln * PPU)
        for t0, t1 in _clip_to_band(p0, p1, MAP_BAND_R[0] + 0.4, MAP_BAND_R[1] - 0.4):
            seg = [(p0[0] + (p1[0] - p0[0]) * t0, p0[1] + (p1[1] - p0[1]) * t0),
                   (p0[0] + (p1[0] - p0[0]) * t1, p0[1] + (p1[1] - p0[1]) * t1)]
            # 錾边：暗缝 + 左上 1px 亮线（光来自左上）⇒ 板与板之间读出"台阶"
            d.line([(x - 0.6, y - 0.6) for x, y in seg], fill=G_SLAB_LIP,
                   width=max(1, int(0.13 * PPU)))
            d.line(seg, fill=G_BAND_MID - 34, width=max(2, int(0.22 * PPU)))
    # ② 内环热裂：2~3 段折线（短、有拐点 —— 直长线会被读成"划痕"）
    for _ in range(9):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(2.5, MAP_BAND_R[0] - 2.0)
        pts = [pt(a, r)]
        for _seg in range(rng.randint(2, 3)):
            ln = rng.uniform(0.9, 2.0)
            a += rng.uniform(-0.5, 0.5)
            r += ln
            if r > MAP_BAND_R[0] - 0.8:
                break
            pts.append(pt(a, r))
        if len(pts) >= 2:
            d.line(pts, fill=G_HEAT_CRACK, width=max(1, int(0.12 * PPU)), joint="curve")
    # ③ 外环碎砾：细小多边形，明暗交替（越靠外越密）
    for _ in range(150):
        a = rng.uniform(0, math.tau)
        r = MAP_BAND_R[1] + (MAP_BAND_R[2] - MAP_BAND_R[1]) * rng.uniform(0.06, 0.99)
        rad = rng.uniform(0.16, 0.5)
        n = rng.randint(4, 6)
        pts = [pt(a + math.tau * j / n, r) for j in range(n)] if rad < 0.01 else [
            (cx + math.cos(a) * r * PPU + math.cos(math.tau * j / n) * rad * PPU * rng.uniform(0.8, 1.15),
             cy + math.sin(a) * r * PPU + math.sin(math.tau * j / n) * rad * PPU * rng.uniform(0.8, 1.15))
            for j in range(n)]
        g = G_BAND_OUT + rng.choice((-G_RUBBLE_D, -10, 8, 14))
        d.polygon(pts, fill=max(0, min(255, g)))


def _base_alpha():
    """地表透明度：44u 内不透明，外沿 0.5u 内软化到 0（外侧是父层场地圆）。
    🔴 直接在 1024 上画：从 512 放大硬边会得到一圈毛边（首版实测像"锯齿环"）。"""
    cx = cy = TEX_PX * 0.5
    m = Image.new("L", (TEX_PX, TEX_PX), 0)
    r = (MAP_BAND_R[2] + 0.5) * PPU
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return m.filter(ImageFilter.GaussianBlur(0.35 * PPU))


# ---------------------------------------------------------------------------
#  ③ 矢量层（岩脊 / 散石），在 4096² 画布上画，再降采样
# ---------------------------------------------------------------------------
def _sector(r0, r1, a0, a1, seg=64):
    """环扇形多边形（与 `monster_layer._sector_poly` 同构）：外弧正向 + 内弧反向。"""
    c = TEX_PX * SS * 0.5

    def pt(r, a):
        return (c + math.cos(a) * r * PPU_SS, c + math.sin(a) * r * PPU_SS)

    pts = [pt(r1, a0 + (a1 - a0) * i / seg) for i in range(seg + 1)]
    pts += [pt(r0, a1 + (a0 - a1) * i / seg) for i in range(seg + 1)]
    return pts


def _offset(pts, dx_u, dy_u):
    return [(x + dx_u * PPU_SS, y + dy_u * PPU_SS) for x, y in pts]


def _lit_rim(d, pts, g, w_u, thresh=0.35, alpha=235, light=LIGHT):
    """只描「朝光」的边（窄、亮）：岩脊的受光棱线。背光侧交给体块暗轮廓，不另描。"""
    n = len(pts)
    w = max(1, int(w_u * PPU_SS))
    cx = cy = TEX_PX * SS * 0.5
    for i in range(n):
        p0, p1 = pts[i], pts[(i + 1) % n]
        mx, my = (p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5
        vx, vy = mx - cx, my - cy
        ln = math.hypot(vx, vy) or 1.0
        if (vx * light[0] + vy * light[1]) / ln <= thresh:
            continue
        # alpha 按段起伏（0.55~1.0）：连续等亮的细线会被读成"金属包边"
        k = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(i * 2.7))
        d.line([p0, p1], fill=(g, g, g, int(alpha * k)), width=w)


def _in_sector(r, a, rg, pad=0.0):
    a0 = math.radians(rg["a0"] + pad)
    a1 = math.radians(rg["a1"] - pad)
    aa = math.atan2(math.sin(a), math.cos(a))
    lo, hi = a0, a1
    while hi < lo:
        hi += math.tau
    while aa < lo:
        aa += math.tau
    return (rg["r0"] + 0.6) <= r <= (rg["r1"] - 0.6) and lo <= aa <= hi


def _jagged(rg, seed):
    """岩脊轮廓：在真实扇区上做**确定性**抖动 —— 四条边全抖（外弧 / 内弧 / 两侧端墙）。

    🔴 只抖圆弧不抖端墙 = 一条直溜溜的长边，实机读作「折起来的铁皮」而不是石头（首版实测）。
      所以端墙也按 t 抖 ±0.5u、圆弧抖 ±0.55u，并且叠两个频率（长波起伏 + 短波碎边）。
    🔴 只允许向外多一点：美术看起来比逻辑遮挡略大 = 玩家宁可不建，方向安全；
      反过来（画得比实际小）会出现「看着能站、点了不能站」——那是可读性事故。
    """
    a0 = math.radians(rg["a0"] + rg["pad"])
    a1 = math.radians(rg["a1"] - rg["pad"])
    n = max(14, int((rg["a1"] - rg["a0"]) * 1.8))
    c = TEX_PX * SS * 0.5

    def wob(a, k):
        return (0.34 * math.sin(a * 8.3 + seed) + 0.21 * math.sin(a * 19.1 + seed * 1.7)) * k

    def P(a, r):
        return (c + math.cos(a) * r * PPU_SS, c + math.sin(a) * r * PPU_SS)

    pts = []
    for i in range(n + 1):                       # 外弧
        a = a0 + (a1 - a0) * i / n
        pts.append(P(a, rg["r1"] + 0.55 + wob(a, 1.0)))
    m = 6
    for i in range(1, m):                        # a1 端墙（r 从外到内，角度微抖）
        t = i / m
        pts.append(P(a1 + 0.006 * math.sin(t * 7.0 + seed), rg["r1"] + (rg["r0"] - rg["r1"]) * t))
    for i in range(n + 1):                       # 内弧
        a = a1 + (a0 - a1) * i / n
        pts.append(P(a, rg["r0"] - 0.18 + wob(a, -0.8)))
    for i in range(1, m):                        # a0 端墙
        t = i / m
        pts.append(P(a0 - 0.006 * math.sin(t * 7.0 + seed * 2.3), rg["r0"] + (rg["r1"] - rg["r0"]) * t))
    return pts


def _ridge_body(rg, rng, seed):
    """单座岩脊 = 一道断崖裂缝：深谷底 → 贴壁暗边 → 受光唇线 → 崖口碎石 → 谷底短裂纹。

    🔴 为什么是「裂缝」而不是「岩体」：岩脊在数据上是一条**又长又薄的环扇**（宽 2~28°、
      长 24~58u）。按"石头表面"画，无论怎么分块，实机都是一块木板（首版实测）。
      按"地上裂开的口子"画，深底 + 亮唇天然带出深度，且与「断崖 / 断墙」的命名一致。
    """
    img = Image.new("RGBA", (TEX_PX * SS, TEX_PX * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    body = _jagged(rg, seed)

    # ① 谷底
    d.polygon(body, fill=(G_RIFT_FLOOR,) * 3 + (255,))

    # ② 贴壁暗边：沿轮廓向内压一圈 1.1u 的暗带（近壁最暗 ⇒ 深度）
    d.line(body + [body[0]], fill=(G_RIFT_DEEP,) * 3 + (200,),
           width=max(2, int(1.1 * PPU_SS)), joint="curve")

    # ③ 受光唇线：整圈一条细亮线（≈ 场地底色的 1.1 倍），是"这里有个坎"的唯一强信号
    d.line(body + [body[0]], fill=(G_RIFT_LIP,) * 3 + (235,),
           width=max(2, int(0.28 * PPU_SS)), joint="curve")

    # ④ 崖口碎石：唇线外 0.3~1.3u 甩几块 0.35~0.9u 的角砾（打断笔直剪影）
    c = TEX_PX * SS * 0.5
    for _ in range(rng.randint(6, 10)):
        a = math.radians(rng.uniform(rg["a0"] + rg["pad"] - 1.2, rg["a1"] - rg["pad"] + 1.2))
        r = rng.choice([rg["r0"] - rng.uniform(0.3, 1.2), rg["r1"] + rng.uniform(0.3, 1.3)])
        rad = rng.uniform(0.3, 0.85)
        n2 = rng.randint(5, 7)
        pts2 = [(c + math.cos(a) * r * PPU_SS + math.cos(math.tau * j / n2) * rad * PPU_SS * rng.uniform(0.75, 1.15),
                 c + math.sin(a) * r * PPU_SS + math.sin(math.tau * j / n2) * rad * PPU_SS * rng.uniform(0.75, 1.15))
                for j in range(n2)]
        d.polygon(pts2, fill=(G_DEBRIS - rng.randint(0, 40),) * 3 + (255,))
        _lit_rim(d, pts2, G_BOULDER_LIP, 0.12, alpha=190)

    # ⑤ 谷底短裂纹：逐点步进（🔴 角度步必须小：r≈50u 时 20° 的弦长就是 18u，
    #    一步跨出去就画成一条横穿岩脊、扎到外面的长直线 —— 首版实机伪影就是这么来的）
    for _ in range(rng.randint(2, 4)):
        a = math.radians(rng.uniform(rg["a0"] + rg["pad"] + 1.0, rg["a1"] - rg["pad"] - 1.0))
        r = rng.uniform(rg["r0"] + 2.0, rg["r1"] - 2.0)
        pts = [(c + math.cos(a) * r * PPU_SS, c + math.sin(a) * r * PPU_SS)]
        for _k in range(rng.randint(2, 4)):
            a += math.radians(rng.uniform(-4.0, 4.0))
            r += rng.uniform(0.7, 1.6)
            if not (rg["r0"] + 0.8 <= r <= rg["r1"] - 0.8):
                break
            if not _in_sector(r, a, rg, rg["pad"] + 1.0):
                break
            pts.append((c + math.cos(a) * r * PPU_SS, c + math.sin(a) * r * PPU_SS))
        if len(pts) >= 2:
            d.line(pts, fill=(G_RIFT_CRACK,) * 3 + (170,),
                   width=max(1, int(0.13 * PPU_SS)), joint="curve")
    return img


def _rock_layer(variants, mid):
    """整张图的岩脊层：先合体块，再统一画落影（影在体块下）。"""
    body = Image.new("RGBA", (TEX_PX * SS, TEX_PX * SS), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (TEX_PX * SS, TEX_PX * SS), (0, 0, 0, 0))
    ds = ImageDraw.Draw(shadow)
    rng = random.Random(zlib.crc32(mid.encode()) & 0xFFFF)
    for i, rg in enumerate(variants[mid]["ridges"]):
        seed = float(i * 3.7 + 1.3)
        ds.polygon(_offset(_jagged(rg, seed), 0.85, 1.0), fill=(0, 0, 0, SHADOW_A))
        body = Image.alpha_composite(body, _ridge_body(rg, rng, seed))
    shadow = shadow.filter(ImageFilter.GaussianBlur(0.55 * PPU_SS))
    return Image.alpha_composite(shadow, body)


def _boulders(variants, mid):
    """零散石块：45~48.5u 近场 + 56.5u 外远景；避开岩脊扇区。"""
    img = Image.new("RGBA", (TEX_PX * SS, TEX_PX * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shadow = Image.new("RGBA", (TEX_PX * SS, TEX_PX * SS), (0, 0, 0, 0))
    ds = ImageDraw.Draw(shadow)
    rng = random.Random((zlib.crc32(mid.encode()) >> 5) & 0xFFFF)
    c = TEX_PX * SS * 0.5
    placed = []
    for band_r, count, rad_rng in ((46.6, 7, (1.0, 1.9)), (57.4, 5, (2.0, 3.4))):
        got = 0
        for _try in range(80):
            if got >= count:
                break
            a = rng.uniform(0, math.tau)
            r = band_r + rng.uniform(-1.1, 1.1)
            if any(_in_sector(r, a, rg, rg["pad"] - 1.0) for rg in variants[mid]["ridges"]):
                continue
            if any(math.hypot(math.cos(a) * r - math.cos(b) * rr,
                              math.sin(a) * r - math.sin(b) * rr) < 4.6 for b, rr in placed):
                continue
            placed.append((a, r))
            got += 1
            rad = rng.uniform(*rad_rng)
            n = rng.randint(7, 9)
            pts = []
            for k in range(n):
                aa = math.tau * k / n
                rr = rad * rng.uniform(0.82, 1.12)
                pts.append((c + (math.cos(a) * r + math.cos(aa) * rr) * PPU_SS,
                            c + (math.sin(a) * r + math.sin(aa) * rr) * PPU_SS))
            ds.polygon(_offset(pts, 0.5, 0.62), fill=(0, 0, 0, BOULDER_SHADOW_A))
            d.polygon(pts, fill=(G_BOULDER,) * 3 + (255,))
            _lit_rim(d, pts, G_BOULDER_LIP, 0.16, alpha=215)
    shadow = shadow.filter(ImageFilter.GaussianBlur(0.4 * PPU_SS))
    return Image.alpha_composite(shadow, img)


# ---------------------------------------------------------------------------
#  ④ 合成
# ---------------------------------------------------------------------------
def build_variant(variants, mid):
    base, k = _band_base()
    alpha = _base_alpha()
    base_rgba = Image.merge("RGBA", (base, base, base, alpha))
    rock = _rock_layer(variants, mid).resize((TEX_PX, TEX_PX), Image.LANCZOS)
    stone = _boulders(variants, mid).resize((TEX_PX, TEX_PX), Image.LANCZOS)
    img = Image.alpha_composite(Image.alpha_composite(base_rgba, stone), rock)
    # 自检：三档材质与岩脊的实测灰度（写进文档，也防「图对了但倍率错了」）
    rg = variants[mid]["ridges"]
    m = {"in": _measure_band(img, 8.0, rg), "mid": _measure_band(img, 23.0, rg),
         "out": _measure_band(img, 37.0, rg)}
    return img, k, m


def _fname(mid):
    return "map_terrain_" + mid.replace("-", "_") + "_v1.png"


def _register(entries):
    """登记 art/manifest.json（按 file 排序，幂等）。"""
    with open(MANIFEST, encoding="utf-8") as fp:
        mf = json.load(fp)
    keep = [a for a in mf["assets"] if not a["file"].startswith("maps/")]
    merged = keep + [{"file": f"maps/{f}", "size": list(sz)} for f, sz in entries]
    merged.sort(key=lambda a: a["file"])
    mf["assets"] = merged
    with open(MANIFEST, "w", encoding="utf-8") as fp:
        json.dump(mf, fp, ensure_ascii=False, indent=1)
    print(f"  manifest.json：{len(merged)} 项（本包 {len(entries)}）")


def _on_field(tex, size=None):
    """把灰度贴图按**实机调制**（× 场地档色）叠到场地底色上 —— 预览必须走乘法，
    直接 alpha 贴图会显示成一张发白的银盘，与实机完全不是一回事。"""
    if size:
        tex = tex.resize((size, size), Image.LANCZOS)
    r, g, b, a = tex.split()
    field = (35, 40, 56)                       # #232838 场地底色
    gain = 255.0 / G_BAND_MID                  # 运行时倍率（见文件头「调色纪律」）
    col = tuple(min(255, int(round(c * gain))) for c in field)
    ch = []
    for band, k in ((r, col[0]), (g, col[1]), (b, col[2])):
        ch.append(ImageChops.multiply(band, Image.new("L", tex.size, k)))
    lit = Image.merge("RGB", ch)
    out = Image.new("RGB", tex.size, col)
    out.paste(lit, (0, 0), a)
    return out


def _contact_sheet(paths):
    """接触表：全部变体 256px 缩略，叠在场地底色上目检（同 card_contact_sheet 手法）。"""
    cols, cell, pad = 5, 256, 8
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cell + pad) + pad, rows * (cell + pad) + pad), (20, 23, 38))
    for i, p in enumerate(paths):
        sheet.paste(_on_field(Image.open(p).convert("RGBA"), cell),
                    (pad + (i % cols) * (cell + pad), pad + (i // cols) * (cell + pad)))
    out = os.path.join(REVIEW, "map_terrain_contact_v1.png")
    sheet.save(out)
    print("  + art/_review/map_terrain_contact_v1.png")


def main():
    print("== 解析 scripts/data/map_variants.gd ==")
    variants = parse_variants()
    print(f"  变体 {len(variants)} 张")
    if not check_variants(variants):
        print("🔴 数据不合口径，停止出图")
        return 1
    if "--check" in sys.argv:
        return 0

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REVIEW, exist_ok=True)
    print("== 出图 ==")
    entries, paths = [], []
    for mid in variants:
        img, k, m = build_variant(variants, mid)
        fn = _fname(mid)
        p = os.path.join(OUT, fn)
        img.save(p)
        entries.append((fn, (TEX_PX, TEX_PX)))
        paths.append(p)
        kb = os.path.getsize(p) / 1024
        print(f"  + maps/{fn}  归一×{k:.3f}  实测灰度 内{m['in']:.0f} / 中{m['mid']:.0f} / "
              f"外{m['out']:.0f}  {kb:.0f}KB")
    _register(entries)
    _contact_sheet(paths)
    return 0


if __name__ == "__main__":
    sys.exit(main())
