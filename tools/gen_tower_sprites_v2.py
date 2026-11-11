#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""守核 Corebound - 战场塔身贴图 v2 生成器（可复现）。

目标：修复 v1「15 张塔贴图共用同一八边形模板、只有中心小徽记不同」的辨识度缺口。

设计红线（design/art/art-bible.md）：
  * §3.1 外轮廓必须严格 8 重对称（正八边形）——本生成器所有塔共用同一外框，不改剪影；
  * §2.1 玩家塔整体待在冷色极（青）做敌我识别——塔身/底盘恒为耀青+深青，
    tag 色只用于内圈装甲、武装部件与内芯，不越界到外框；
  * §9.2 游戏状态不得仅靠颜色传达——tag 同时用「形状符号」+「构型」冗余编码。

差异化通道（v2 新增，全部落在八边形内框，覆盖约 70% 塔面）：
  1. 武装构型 archetype（12 种：箭簇/重炮/冰晶/长枪/电极/破甲/符文环/虚空/卫星/转轮/双管/涡轮）；
  2. 扇区装甲片数量 arms 与旋转角 spin（同族不同塔也不同）；
  3. 内芯正 n 边形边数 sides（沿用 monster_layer._draw_radial_tower_glyph 的约定）；
  4. tag 符号（形状）+ tag 色（颜色）双通道；
  5. 刻度点 pips 与卫星数 sats（族内序号的第三形状通道）。

数据来源：scripts/data/building_card_params.gd 的 TOWERS / TOWERS_EXT 是唯一塔清单 SSOT，
本脚本运行时直接解析，不硬编码塔名单；新增塔原型后重跑本脚本即自动补齐贴图。

契约（scripts/ui/monster_layer.gd）：
  _sprite("sp_tower_" + ctype.to_lower()) -> res://art/2d/sprites/<name>_v1.png
  draw_texture_rect(..., Rect2(4.0*sc, 4.0*sc))  => 贴图恒 128x128，半边 2.0u。

用法：
  py -3 tools/gen_tower_sprites_v2.py                # 生成贴图 + 预览 + 更新 manifest
  py -3 tools/gen_tower_sprites_v2.py --only Arrow   # 只出一张，调试用
  py -3 tools/gen_tower_sprites_v2.py --no-preview --no-manifest

依赖：Pillow（本机 py -3 / Python 3.13 已装 11.3.0）。
"""
from __future__ import annotations

import argparse
import io
import json
import math
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SPRITE_DIR = ROOT / "art" / "2d" / "sprites"
MANIFEST = ROOT / "art" / "manifest.json"
PREVIEW_DIR = ROOT / "design" / "art" / "previews"
PARAMS = ROOT / "scripts" / "data" / "building_card_params.gd"
FONT_PATH = ROOT / "assets" / "fonts" / "JetBrainsMono.ttf"

SIZE = 128
S = 4                      # 超采样倍率
W = SIZE * S
U = W / 4.0                # 每世界单位 u 的像素（画布半边 = 2.0u）
R = 1.7                    # 塔八边形外接圆半径，单位 u（与 U_TOWER 一致）；所有几何函数入参均为 u
CX = CY = W / 2.0

# ---- art-bible §2.2 调色板（不发明新色） ----
C_ALLY = "#3ED0E8"         # 耀青（玩家主体）
C_ALLY_DARK = "#1A6B7D"    # 深青（阴影层）
C_ALLY_2 = "#7A5CFF"       # 星紫
C_EDGE = "#0E2430"         # 塔描边（冷暗）
C_STEEL = "#9AA5B1"        # 钢灰
C_GOLD = "#FFC94A"         # 辉金
C_WHITE = "#F7FCFF"        # 近白
C_ICY = "#3EA8FF"          # 湖蓝
C_ARCANE = "#B45CFF"       # 幽紫
C_ENEMY = "#FF6B3D"        # 熔橙（仅内芯/部件小面积）
C_VOID = "#0D0817"         # 深芯
C_BG = "#141726"           # 预览底色

# tag -> (主色, 暗色, 形状符号 id)
TAGS = {
    "":       (C_ALLY,   C_ALLY_DARK, "arrow"),
    "fire":   (C_ENEMY,  "#8A2F1C",  "diamond"),
    "frost":  (C_ICY,    "#1B5A8C",  "snow"),
    "pierce": (C_GOLD,   "#8A6A20",  "triangle"),
    "shock":  (C_GOLD,   "#8A6A20",  "bolt"),
    "sunder": (C_STEEL,  "#4A5560",  "cross"),
    "hex":    (C_ARCANE, "#5C2E85",  "rune"),
    "true":   (C_WHITE,  C_ALLY_2,   "void"),
}
TAG_ORDER = ["", "fire", "frost", "pierce", "shock", "sunder", "hex", "true"]
TAG_LABEL = {
    "": "PHYSICAL / BASE", "fire": "FIRE", "frost": "FROST", "pierce": "PIERCE",
    "shock": "SHOCK", "sunder": "SUNDER", "hex": "HEX", "true": "TRUE",
}
# tag 的形状冗余通道：装甲片外端的端帽形状（§9.2① 颜色不得是唯一通道）
TAG_CAP = {
    "": "arrow", "fire": "diamond", "frost": "fork", "pierce": "spike",
    "shock": "zig", "sunder": "bar", "hex": "dot", "true": "ring",
}
# 塔专属中心大符号：同 tag 族内也不共用，是族内辨识的主通道
GLYPHS = ["tri", "square", "diamond", "penta", "hexa", "star4",
          "star6", "x", "rings", "bolt", "snow", "chevron"]

# 12 种武装构型
ARCHS = [
    "arrow_cluster", "heavy_gun", "crystal", "lance", "tesla", "sunder",
    "rune_ring", "void_core", "orb_sat", "burst", "twin_barrel", "fan",
]
# 每个 tag 允许的构型循环（保证同族塔也不会全都长一个样）
TAG_ARCHS = {
    "":       ["arrow_cluster", "fan", "twin_barrel", "burst", "arrow_cluster", "lance"],
    "fire":   ["heavy_gun", "burst", "fan", "twin_barrel", "heavy_gun", "orb_sat"],
    "frost":  ["crystal", "orb_sat", "fan", "crystal", "burst", "void_core"],
    "pierce": ["lance", "arrow_cluster", "twin_barrel", "lance", "fan", "burst"],
    "shock":  ["tesla", "orb_sat", "fan", "tesla", "burst", "void_core"],
    "sunder": ["sunder", "heavy_gun", "fan", "sunder", "twin_barrel", "burst"],
    "hex":    ["rune_ring", "void_core", "orb_sat", "rune_ring", "fan", "tesla"],
    "true":   ["void_core", "orb_sat", "rune_ring", "void_core", "fan", "burst"],
}

# 主塔 / 第二塔 / 特殊塔：手工指定构型，保证最常用的 15+ 张差异最大。
# 字段：arch, arms(扇区/臂数), sides(内芯边数), rings, sats, spin(装甲旋转序号)
HERO = {
    "Arrow":      ("arrow_cluster", 3, 3, 0, 0, 0),
    "Cannon":     ("heavy_gun",     1, 4, 0, 0, 0),
    "Frost":      ("crystal",       6, 6, 1, 0, 0),
    "Lance":      ("lance",         2, 5, 0, 0, 0),
    "Tesla":      ("tesla",         4, 7, 0, 4, 0),
    "Sunder":     ("sunder",        4, 8, 0, 0, 0),
    "Hex":        ("rune_ring",     6, 9, 2, 6, 0),
    "Ember":      ("burst",         3, 10, 0, 3, 1),
    "Icicle":     ("crystal",       3, 11, 1, 0, 1),
    "Javelin":    ("lance",         3, 12, 0, 0, 1),
    "Bolt":       ("tesla",         2, 13, 0, 2, 1),
    "Maul":       ("heavy_gun",     2, 14, 0, 0, 1),
    "Rune":       ("rune_ring",     8, 15, 2, 8, 1),
    "Oblivion":   ("void_core",     8, 16, 2, 0, 0),
    "Void":       ("orb_sat",       8, 17, 1, 8, 1),
    "Pyroclasm":  ("burst",         8, 12, 1, 0, 2),
    "Scout":      ("arrow_cluster", 5, 3, 0, 0, 1),
    "Ballista":   ("twin_barrel",   2, 5, 0, 0, 1),
    "Catapult":   ("heavy_gun",     1, 4, 0, 0, 2),
    "Arcbeacon":  ("rune_ring",     6, 11, 2, 6, 1),
    "Rangebeacon": ("tesla",        5, 12, 1, 4, 1),
    "Scrapcannon": ("heavy_gun",    1, 9, 0, 0, 2),
    "Bastion":    ("heavy_gun",     8, 8, 1, 0, 2),
    "Wraith":     ("void_core",     6, 12, 2, 6, 2),
}


# ---------------------------------------------------------------- 基础工具
def hx(s: str, a: int = 255) -> tuple[int, int, int, int]:
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


def mix(c1, c2, t: float) -> tuple[int, int, int, int]:
    b = hx(c2) if isinstance(c2, str) else c2
    return tuple(int(c1[i] * (1 - t) + b[i] * t) for i in range(3)) + (255,)


def P(x: float, y: float) -> tuple[float, float]:
    return (CX + x * U, CY + y * U)


def LW(k: float) -> int:
    # 1.35 倍增益：v1 的 0.05u 描边缩到 128px 后不足 2px，小尺寸下会糊成一团
    return max(2, int(k * U * 1.35))


def reg(r: float, n: int, rot: float = 0.0,
        cx: float = 0.0, cy: float = 0.0) -> list[tuple[float, float]]:
    return [P(cx + r * math.cos(rot + 2 * math.pi * k / n),
              cy + r * math.sin(rot + 2 * math.pi * k / n)) for k in range(n)]


def poly(d: ImageDraw.ImageDraw, pts, fill, outline=None, width=2) -> None:
    d.polygon(pts, fill=fill)
    if outline is not None:
        d.line(list(pts) + [pts[0]], fill=outline, width=width, joint="curve")


def line(d: ImageDraw.ImageDraw, pts, fill, width=2) -> None:
    d.line(pts, fill=fill, width=width, joint="curve")


def circle(d: ImageDraw.ImageDraw, x: float, y: float, r: float,
           fill=None, outline=None, width=2) -> None:
    px, py = P(x, y)
    rr = r * U
    box = [px - rr, py - rr, px + rr, py + rr]
    if fill is not None:
        d.ellipse(box, fill=fill)
    if outline is not None:
        d.ellipse(box, outline=outline, width=width)


def wedge(d: ImageDraw.ImageDraw, r0: float, r1: float,
          a0: float, a1: float, fill, outline=None, width=2) -> None:
    steps = 8
    outer = [P(r1 * math.cos(a0 + (a1 - a0) * k / steps),
               r1 * math.sin(a0 + (a1 - a0) * k / steps)) for k in range(steps + 1)]
    inner = [P(r0 * math.cos(a1 - (a1 - a0) * k / steps),
               r0 * math.sin(a1 - (a1 - a0) * k / steps)) for k in range(steps + 1)]
    poly(d, outer + inner, fill, outline, width)


def barrel(d: ImageDraw.ImageDraw, a: float, r0: float, r1: float,
           w0: float, w1: float, fill, edge, muzzle=None) -> None:
    # 炮管最小视觉宽度：细于 0.095u（约 3px @128）的部件在实机缩放下不可辨
    w0, w1 = max(w0, 0.095), max(w1, 0.075)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    pts = [
        P(r0 * ux + w0 * px, r0 * uy + w0 * py),
        P(r1 * ux + w1 * px, r1 * uy + w1 * py),
        P(r1 * ux - w1 * px, r1 * uy - w1 * py),
        P(r0 * ux - w0 * px, r0 * uy - w0 * py),
    ]
    poly(d, pts, fill, edge, LW(0.035))
    if muzzle is not None:
        circle(d, r1 * ux, r1 * uy, w1 * 0.62, fill=muzzle, outline=edge, width=LW(0.03))


# ---------------------------------------------------------------- 塔清单解析
def load_towers() -> list[tuple[str, str]]:
    """从数值 SSOT 解析 (ctype, tag)；块内第一个 tag 为准（避免注释/嵌套干扰）。"""
    text = PARAMS.read_text(encoding="utf-8")
    a = text.index("const TOWERS :=")
    b = text.index("const TOWERS_EXT :=")
    blocks: dict[str, list[str]] = {}
    cur = None
    for chunk in (text[a:b], text[b:]):
        for ln in chunk.splitlines():
            m = re.match(r'\s*"([A-Z][A-Za-z0-9_]*)"\s*:\s*\{', ln)
            if m:
                cur = m.group(1)
                blocks[cur] = []
            if cur is not None:
                blocks[cur].append(ln)
    out = []
    for name, lines in blocks.items():
        m = re.search(r'"tag"\s*:\s*"([^"]*)"', "\n".join(lines))
        tag = m.group(1) if m else ""
        if tag not in TAGS:
            tag = ""
        out.append((name, tag))
    return out


def build_dna(towers: list[tuple[str, str]]) -> list[dict]:
    by_tag: dict[str, list[str]] = {t: [] for t in TAG_ORDER}
    for name, tag in towers:
        by_tag[tag].append(name)
    for t in by_tag:
        # Keep established sprite indices when adding the paid cannon.
        by_tag[t].sort(key=lambda name: (name in {"Scrapcannon", "Arcbeacon", "Rangebeacon"}, name))

    dna = []
    for name, tag in towers:
        idx = by_tag[tag].index(name)
        if name in HERO:
            arch, arms, sides, rings, sats, spin = HERO[name]
        else:
            arch = TAG_ARCHS[tag][idx % len(TAG_ARCHS[tag])]
            arms = 3 + (idx % 5)
            sides = 3 + ((idx * 3) % 9)
            rings = idx % 3
            sats = (idx // 3) % 5
            spin = idx % 3
        dna.append({
            "name": name, "tag": tag, "arch": arch, "arms": arms, "sides": sides,
            "rings": rings, "sats": sats, "spin": spin, "idx": idx,
            "pips": 1 + (idx % 4),
            "glyph": GLYPHS[(idx * 5 + TAG_ORDER.index(tag) * 3) % len(GLYPHS)],
            "shade": 0.10 + 0.09 * (idx % 4),
            "twin": bool(idx % 2),
        })
    return dna


def draw_cap(d: ImageDraw.ImageDraw, a: float, cap: str, fill, edge) -> None:
    """装甲片外端的 tag 形状端帽：颜色之外的第二编码通道（§9.2①）。"""
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    cx, cy = R * 0.70 * ux, R * 0.70 * uy
    # 端帽整体放大 1.8x：0.1u 的符号在 128px 贴图上只有 3px，肉眼不可辨
    q = lambda s, t: P(cx + 1.8 * s * px + 1.8 * t * ux,
                       cy + 1.8 * s * py + 1.8 * t * uy)
    if cap == "arrow":
        poly(d, [q(0, 0.15), q(0.11, -0.08), q(-0.11, -0.08)], fill, edge, LW(0.028))
    elif cap == "diamond":
        poly(d, [q(0, 0.14), q(0.10, 0), q(0, -0.14), q(-0.10, 0)], fill, edge, LW(0.028))
    elif cap == "spike":
        poly(d, [q(0, 0.19), q(0.055, -0.09), q(-0.055, -0.09)], fill, edge, LW(0.028))
    elif cap == "fork":
        line(d, [q(0, -0.08), q(0, 0.14)], edge, LW(0.032))
        line(d, [q(-0.09, 0.04), q(0, 0.14), q(0.09, 0.04)], edge, LW(0.032))
    elif cap == "zig":
        line(d, [q(0.06, 0.14), q(-0.07, 0.01), q(0.02, 0.01), q(-0.06, -0.13)], edge, LW(0.04))
    elif cap == "bar":
        poly(d, [q(-0.11, 0.03), q(0.11, 0.03), q(0.11, 0.10), q(-0.11, 0.10)],
             fill, edge, LW(0.028))
    elif cap == "dot":
        circle(d, cx, cy, 0.075, fill=fill, outline=edge, width=LW(0.028))
    elif cap == "ring":
        circle(d, cx, cy, 0.095, outline=edge, width=LW(0.035))
        circle(d, cx, cy, 0.035, fill=fill)


# ---------------------------------------------------------------- 底盘（统一，8 重对称）
def draw_chassis(d: ImageDraw.ImageDraw, dna: dict) -> None:
    tag = dna["tag"]
    tc, td, _ = TAGS[tag]
    edge = hx(C_EDGE)

    poly(d, reg(R + 0.11, 8), edge)                                    # 外描边（统一剪影）
    poly(d, reg(R, 8), hx(C_ALLY_DARK))                                # 深青底盘
    poly(d, reg(R * 0.90, 8), mix(hx(C_ALLY_DARK), hx(td), 0.42))      # tag 暗色内环
    poly(d, reg(R * 0.78, 8), hx(C_ALLY))                              # 耀青主盘（阵营锚点）
    poly(d, reg(R * 0.72, 8), mix(hx(C_ALLY), hx(td), 0.16))            # 内盘轻微 tag 染

    # 扇区装甲：数量/旋转随塔变化，块面更大更饱和 —— 覆盖塔面约 1/3 面积的第一辨识通道
    arms = max(1, dna["arms"])
    step = 2 * math.pi / arms
    rot = -math.pi / 2 + dna["spin"] * 0.13
    armor = mix(hx(C_ALLY), hx(tc), 0.78)
    cap = TAG_CAP[tag]
    for k in range(arms):
        a = rot + k * step
        half = step * 0.36
        wedge(d, R * 0.36, R * 0.72, a - half, a + half, armor, edge, LW(0.035))
        draw_cap(d, a, cap, hx(tc), edge)

    # 8 个铆钉（8 重对称，各塔一致，提供机械质感；小尺寸下刻意收细）
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        circle(d, R * 0.845 * math.cos(a), R * 0.845 * math.sin(a),
               0.038, fill=hx(C_STEEL), outline=edge, width=LW(0.018))


def add_glow(img: Image.Image, dna: dict) -> Image.Image:
    tc, _, _ = TAGS[dna["tag"]]
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    col = hx(tc)
    for k in range(28, 0, -1):
        rr = R * U * 0.66 * k / 28
        a = int(64 * (1 - k / 28) ** 1.6)
        g.ellipse([CX - rr, CY - rr, CX + rr, CY + rr], fill=(col[0], col[1], col[2], a))
    glow = glow.filter(ImageFilter.GaussianBlur(0.06 * U))
    return Image.alpha_composite(img, glow)


# ---------------------------------------------------------------- 武装构型
def draw_arch(d: ImageDraw.ImageDraw, dna: dict) -> None:
    tag = dna["tag"]
    tc, td, _ = TAGS[tag]
    edge = hx(C_EDGE)
    bright = mix(hx(tc), hx(C_WHITE), 0.30)
    dark = hx(td)
    arms = max(1, dna["arms"])
    arch = dna["arch"]

    if arch == "arrow_cluster":
        for k in range(arms):
            a = -math.pi / 2 + 2 * math.pi * k / arms
            ux, uy = math.cos(a), math.sin(a)
            px, py = -uy, ux
            barrel(d, a, R * 0.22, R * 0.80, 0.055, 0.028, bright, edge, muzzle=dark)
            tip = P(R * 0.95 * ux, R * 0.95 * uy)
            b1 = P(R * 0.78 * ux + 0.13 * px, R * 0.78 * uy + 0.13 * py)
            b2 = P(R * 0.78 * ux - 0.13 * px, R * 0.78 * uy - 0.13 * py)
            poly(d, [tip, b1, b2], bright, edge, LW(0.035))

    elif arch == "heavy_gun":
        offs = [0.0] if not dna["twin"] else [-0.22, 0.22]
        for o in offs:
            a = -math.pi / 2 + o
            barrel(d, a, R * 0.16, R * 0.90, 0.20, 0.155, bright, edge, muzzle=dark)
            # 炮管中段的散热刻线
            ux, uy = math.cos(a), math.sin(a)
            for f in (0.50, 0.62, 0.74):
                rr = R * f
                line(d, [P(rr * ux - 0.14 * uy, rr * uy + 0.14 * ux),
                         P(rr * ux + 0.14 * uy, rr * uy - 0.14 * ux)],
                     edge, LW(0.025))
        # 两侧耳轴
        for sx in (-1, 1):
            x, y = sx * 0.52, 0.10
            pts = [P(x - 0.16, y - 0.14), P(x + 0.16, y - 0.14),
                   P(x + 0.16, y + 0.14), P(x - 0.16, y + 0.14)]
            poly(d, pts, dark, edge, LW(0.03))

    elif arch == "crystal":
        for k in range(arms):
            a = -math.pi / 2 + 2 * math.pi * k / arms
            ux, uy = math.cos(a), math.sin(a)
            px, py = -uy, ux
            pts = [P(R * 0.92 * ux, R * 0.92 * uy),
                   P(R * 0.52 * ux + 0.15 * px, R * 0.52 * uy + 0.15 * py),
                   P(R * 0.20 * ux, R * 0.20 * uy),
                   P(R * 0.52 * ux - 0.15 * px, R * 0.52 * uy - 0.15 * py)]
            poly(d, pts, bright, edge, LW(0.032))
            line(d, [P(R * 0.20 * ux, R * 0.20 * uy), P(R * 0.92 * ux, R * 0.92 * uy)],
                 hx(C_WHITE), LW(0.022))

    elif arch == "lance":
        a = -math.pi / 2
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        pts = [P(R * 0.96 * ux, R * 0.96 * uy),
               P(R * 0.62 * ux + 0.16 * px, R * 0.62 * uy + 0.16 * py),
               P(-R * 0.68 * ux + 0.16 * px, -R * 0.68 * uy + 0.16 * py),
               P(-R * 0.68 * ux - 0.16 * px, -R * 0.68 * uy - 0.16 * py),
               P(R * 0.62 * ux - 0.16 * px, R * 0.62 * uy - 0.16 * py)]
        poly(d, pts, bright, edge, LW(0.035))
        for sx in (-1, 1):
            pts = [P(sx * 0.16, 0.32), P(sx * 0.46, 0.58), P(sx * 0.16, 0.52)]
            poly(d, pts, dark, edge, LW(0.03))

    elif arch == "tesla":
        for k in range(4):
            a = math.pi / 4 + math.pi * k / 2
            ux, uy = math.cos(a), math.sin(a)
            barrel(d, a, R * 0.40, R * 0.86, 0.075, 0.075, bright, edge)
            circle(d, R * 0.88 * ux, R * 0.88 * uy, 0.115, fill=hx(C_GOLD), outline=edge, width=LW(0.03))
        z = [P(-0.12, -0.52), P(0.16, -0.06), P(-0.02, -0.06), P(0.18, 0.50)]
        line(d, z, hx(C_WHITE), LW(0.075))
        line(d, z, edge, LW(0.025))

    elif arch == "sunder":
        for a in (-math.pi / 4, math.pi / 4):
            barrel(d, a, R * 0.10, R * 0.88, 0.145, 0.055, bright, edge)
            barrel(d, a + math.pi, R * 0.10, R * 0.88, 0.145, 0.055, bright, edge)
        for k in range(4):
            a = math.pi / 4 + math.pi * k / 2
            wedge(d, R * 0.58, R * 0.76, a - 0.24, a + 0.24, dark, edge, LW(0.03))

    elif arch == "rune_ring":
        for i in range(2 + dna["rings"]):
            rr = R * (0.46 + 0.16 * i)
            circle(d, 0, 0, rr, outline=bright if i % 2 == 0 else edge, width=LW(0.07))
        n = max(4, arms)
        for k in range(n):
            a = 2 * math.pi * k / n - math.pi / 2
            circle(d, R * 0.76 * math.cos(a), R * 0.76 * math.sin(a),
                   0.085, fill=hx(C_WHITE), outline=edge, width=LW(0.022))

    elif arch == "void_core":
        circle(d, 0, 0, R * 0.62, fill=hx(C_VOID), outline=hx(C_ALLY_2), width=LW(0.07))
        for i in range(2):
            circle(d, 0, 0, R * (0.74 + 0.12 * i), outline=hx(C_ALLY_2), width=LW(0.045))
        for k in range(max(6, arms)):
            a = 2 * math.pi * k / max(6, arms)
            line(d, [P(R * 0.66 * math.cos(a), R * 0.66 * math.sin(a)),
                     P(R * 0.88 * math.cos(a), R * 0.88 * math.sin(a))],
                 hx(C_ALLY_2), LW(0.045))

    elif arch == "orb_sat":
        n = max(3, dna["sats"] if dna["sats"] >= 3 else 3 + arms % 4)
        for k in range(n):
            a = 2 * math.pi * k / n - math.pi / 2
            x, y = R * 0.66 * math.cos(a), R * 0.66 * math.sin(a)
            line(d, [P(0, 0), P(x, y)], edge, LW(0.045))
            circle(d, x, y, 0.13, fill=bright, outline=edge, width=LW(0.03))
        circle(d, 0, 0, R * 0.30, fill=dark, outline=edge, width=LW(0.04))

    elif arch == "burst":
        for k in range(arms):
            a = 2 * math.pi * k / arms - math.pi / 2 + dna["spin"] * 0.08
            barrel(d, a, R * 0.24, R * 0.80, 0.125, 0.10, bright, edge, muzzle=dark)

    elif arch == "twin_barrel":
        for sx in (-1, 1):
            x = sx * 0.20
            pts = [P(x - 0.10, -R * 0.02), P(x + 0.10, -R * 0.02),
                   P(x + 0.10, -R * 0.86), P(x - 0.10, -R * 0.86)]
            poly(d, pts, bright, edge, LW(0.035))
            circle(d, x, -R * 0.86, 0.105, fill=dark, outline=edge, width=LW(0.028))
        pts = [P(-0.42, 0.18), P(0.42, 0.18), P(0.42, 0.40), P(-0.42, 0.40)]
        poly(d, pts, dark, edge, LW(0.035))

    elif arch == "fan":
        for k in range(arms):
            a = 2 * math.pi * k / arms + dna["spin"] * 0.15
            wedge(d, R * 0.30, R * 0.84, a + 0.06, a + (2 * math.pi / arms) * 0.72,
                  bright if k % 2 == 0 else dark, edge, LW(0.032))

    # 卫星点（族内序号的第三形状通道）
    if dna["sats"] and arch not in ("orb_sat",):
        for k in range(min(dna["sats"], 6)):
            a = 2 * math.pi * k / min(dna["sats"], 6) + math.pi / 7
            circle(d, R * 0.88 * math.cos(a), R * 0.88 * math.sin(a),
                   0.055, fill=hx(C_WHITE), outline=edge, width=LW(0.02))


# ---------------------------------------------------------------- 内芯徽记
def draw_core(d: ImageDraw.ImageDraw, dna: dict) -> None:
    """中心 = tag 色 + 正 n 边形边数 + 塔专属大符号 + 序号刻度点。

    大符号是本轮新增的族内主辨识通道：v1 同 tag 族共用同一个中心符号，
    导致同族 8~10 张塔在实机尺寸下完全撞脸。
    """
    tc, _, _ = TAGS[dna["tag"]]
    edge = hx(C_EDGE)
    c, w, rr = edge, LW(0.085), 0.35
    # 中心刻意做大：战场缩到 48px 时，外围细线会糊，中心符号是最后仍可读的通道
    circle(d, 0, 0, R * 0.43, fill=hx(C_ALLY_DARK), outline=edge, width=LW(0.05))
    pts = reg(R * 0.37, dna["sides"], -math.pi / 2)
    poly(d, pts, mix(hx(tc), hx(C_WHITE), dna["shade"]), edge, LW(0.05))

    g = dna["glyph"]
    if g == "tri":
        line(d, [P(0, -rr), P(rr * 0.9, rr * 0.72), P(-rr * 0.9, rr * 0.72), P(0, -rr)], c, w)
    elif g == "square":
        line(d, [P(-rr * 0.72, -rr * 0.72), P(rr * 0.72, -rr * 0.72),
                 P(rr * 0.72, rr * 0.72), P(-rr * 0.72, rr * 0.72), P(-rr * 0.72, -rr * 0.72)], c, w)
    elif g == "diamond":
        line(d, [P(0, -rr), P(rr * 0.78, 0), P(0, rr), P(-rr * 0.78, 0), P(0, -rr)], c, w)
    elif g in ("penta", "hexa"):
        n = 5 if g == "penta" else 6
        pp = [P(rr * math.cos(-math.pi / 2 + 2 * math.pi * k / n),
                rr * math.sin(-math.pi / 2 + 2 * math.pi * k / n)) for k in range(n)]
        line(d, pp + [pp[0]], c, w)
    elif g in ("star4", "star6"):
        n = 4 if g == "star4" else 6
        pp = []
        for k in range(2 * n):
            a = -math.pi / 2 + math.pi * k / n
            r2 = rr if k % 2 == 0 else rr * 0.42
            pp.append(P(r2 * math.cos(a), r2 * math.sin(a)))
        line(d, pp + [pp[0]], c, w)
    elif g == "x":
        line(d, [P(-rr * 0.72, -rr * 0.72), P(rr * 0.72, rr * 0.72)], c, w)
        line(d, [P(-rr * 0.72, rr * 0.72), P(rr * 0.72, -rr * 0.72)], c, w)
    elif g == "rings":
        circle(d, 0, 0, rr * 0.85, outline=c, width=w)
        circle(d, 0, 0, rr * 0.38, outline=c, width=w)
    elif g == "bolt":
        line(d, [P(rr * 0.28, -rr), P(-rr * 0.42, rr * 0.08),
                 P(rr * 0.06, rr * 0.08), P(-rr * 0.22, rr)], c, w)
    elif g == "snow":
        line(d, [P(0, -rr), P(0, rr)], c, w)
        line(d, [P(-rr * 0.82, -rr * 0.46), P(rr * 0.82, rr * 0.46)], c, w)
        line(d, [P(-rr * 0.82, rr * 0.46), P(rr * 0.82, -rr * 0.46)], c, w)
    elif g == "chevron":
        line(d, [P(-rr * 0.8, -rr * 0.2), P(0, rr * 0.35), P(rr * 0.8, -rr * 0.2)], c, w)
        line(d, [P(-rr * 0.8, -rr * 0.72), P(0, -rr * 0.17), P(rr * 0.8, -rr * 0.72)], c, w)

    # 刻度点：不使用文字即可区分同族同构型的塔
    pips = dna["pips"]
    for k in range(pips):
        x = (k - (pips - 1) / 2.0) * 0.16
        circle(d, x, R * 0.54, 0.042, fill=hx(C_WHITE), outline=edge, width=LW(0.018))


def draw_finish(d: ImageDraw.ImageDraw, dna: dict) -> None:
    hi = mix(hx(C_ALLY), hx(C_WHITE), 0.72)
    # 左上高光弧（贴边，不再像 v1 那样用大白圆遮住内芯）
    a0, a1 = math.radians(202), math.radians(268)
    steps = 14
    arc = [P((R + 0.02) * math.cos(a0 + (a1 - a0) * k / steps),
             (R + 0.02) * math.sin(a0 + (a1 - a0) * k / steps)) for k in range(steps + 1)]
    line(d, arc, hi, LW(0.075))
    # v1 的 8 条角刻线在 48px 缩放下只是噪点，且无信息量 —— v2 去掉，保留干净剪影


def clip_silhouette(img: Image.Image) -> Image.Image:
    """硬保证 §3.1：任何武装部件都不得越出八边形外轮廓（剪影恒 8 重对称）。"""
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(reg(R + 0.115, 8), fill=255)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


def render(dna: dict) -> Image.Image:
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_chassis(d, dna)
    img = add_glow(img, dna)
    d = ImageDraw.Draw(img)
    draw_arch(d, dna)
    draw_core(d, dna)
    draw_finish(d, dna)
    img = clip_silhouette(img)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


# ---------------------------------------------------------------- 预览
def font(size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(FONT_PATH), size)
    except OSError:
        return ImageFont.load_default()


def make_contact(dna_list: list[dict], images: dict[str, Image.Image]) -> Image.Image:
    cell_w, cell_h, pad, cols = 148, 172, 16, 8
    groups = [(t, [x for x in dna_list if x["tag"] == t]) for t in TAG_ORDER]
    width = pad * 2 + cols * cell_w
    height = 96 + sum(48 + math.ceil(len(g) / cols) * cell_h
                      for _, g in groups if g) + 30
    sheet = Image.new("RGBA", (width, height), hx(C_BG))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 22), "CORBOUND  /  TOWER SPRITES v2", font=font(30), fill=hx(C_WHITE))
    d.text((pad, 60), "%d archetypes  |  shared octagonal silhouette  |  distinct armament + tag glyph" % len(dna_list),
           font=font(14), fill=hx(C_STEEL))
    y = 96
    for tag, group in groups:
        if not group:
            continue
        d.text((pad, y), "%s  (%d)" % (TAG_LABEL[tag], len(group)),
               font=font(17), fill=hx(TAGS[tag][0]))
        y += 26
        for i, dna in enumerate(group):
            cx = pad + (i % cols) * cell_w
            cy = y + (i // cols) * cell_h
            sheet.alpha_composite(images[dna["name"]], (cx + 10, cy))
            d.text((cx + 10, cy + 132), dna["name"][:17], font=font(13), fill=hx(C_WHITE))
            d.text((cx + 10, cy + 150), dna["arch"][:17], font=font(11), fill=hx(C_STEEL))
        y += math.ceil(len(group) / cols) * cell_h + 22
    return sheet


def old_sprite_from_git(name: str) -> Image.Image | None:
    rel = "art/2d/sprites/sp_tower_%s_v1.png" % name.lower()
    p = subprocess.run(["git", "-C", str(ROOT), "show", "HEAD:" + rel],
                       capture_output=True)
    if p.returncode != 0:
        return None
    try:
        return Image.open(io.BytesIO(p.stdout)).convert("RGBA")
    except Exception:
        return None


def make_before_after(hero_names: list[str], images: dict[str, Image.Image]) -> Image.Image:
    cols, cell_w, cell_h = 5, 300, 152
    rows = math.ceil(len(hero_names) / cols)
    sheet = Image.new("RGBA", (40 + cols * cell_w, 100 + rows * cell_h), hx(C_BG))
    d = ImageDraw.Draw(sheet)
    d.text((20, 18), "BEFORE  /  v1 shared template", font=font(22), fill=hx(C_STEEL))
    d.text((20, 50), "AFTER   /  v2 distinct armament", font=font(22), fill=hx(C_ALLY))
    for i, name in enumerate(hero_names):
        x = 20 + (i % cols) * cell_w
        y = 96 + (i // cols) * cell_h
        old = old_sprite_from_git(name)
        if old is not None:
            sheet.alpha_composite(old, (x, y))
        new = images.get(name)
        if new is not None:
            sheet.alpha_composite(new, (x + 132, y))
        d.text((x, y + 130), name, font=font(14), fill=hx(C_WHITE))
        d.line([(x + 126, y), (x + 126, y + 128)], fill=hx(C_STEEL), width=1)
    return sheet


def make_battle_scale(hero_names: list[str], images: dict[str, Image.Image]) -> Image.Image:
    """实机缩放验收：战场里塔常被缩到 48~64px，预览必须在这个尺度下仍可分辨。"""
    cell_w, scales = 92, (48, 64)
    width = 32 + cell_w * len(hero_names)
    height = 80 + len(scales) * 108
    sheet = Image.new("RGBA", (width, height), hx(C_BG))
    d = ImageDraw.Draw(sheet)
    d.text((16, 14), "BATTLE-SCALE CHECK  /  shared silhouette, distinct armament",
           font=font(19), fill=hx(C_WHITE))
    for row, px in enumerate(scales):
        y = 62 + row * 108
        d.text((16, y + 18), "%dpx" % px, font=font(14), fill=hx(C_STEEL))
        for i, name in enumerate(hero_names):
            im = images[name].resize((px, px), Image.LANCZOS)
            x = 60 + i * cell_w
            sheet.alpha_composite(im, (x, y))
            d.text((x, y + px + 6), name[:11], font=font(11), fill=hx(C_WHITE))
    return sheet


# ---------------------------------------------------------------- manifest
def update_manifest(dna_list: list[dict]) -> None:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = data["assets"]
    is_tower = lambda a: str(a["file"]).startswith("sprites/sp_tower_")
    fresh = [{"file": "sprites/sp_tower_%s_v1.png" % d["name"].lower(),
              "size": [SIZE, SIZE]} for d in sorted(dna_list, key=lambda x: x["name"].lower())]
    out, inserted = [], False
    for a in assets:
        if is_tower(a):
            if not inserted:
                out.extend(fresh)
                inserted = True
            continue
        out.append(a)
    if not inserted:
        out.extend(fresh)
    data["assets"] = out
    # 与 art/manifest.json 的 HEAD 格式严格一致：indent=1、末尾无换行（否则整份重排，diff 噪音上千行）
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


# ---------------------------------------------------------------- 入口
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="只生成指定 ctype（调试）")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--no-manifest", action="store_true")
    args = ap.parse_args()

    towers = load_towers()
    dna_list = build_dna(towers)
    if args.only:
        dna_list = [d for d in dna_list if d["name"].lower() == args.only.lower()]
        if not dna_list:
            print("unknown ctype: %s" % args.only, file=sys.stderr)
            return 1
    SPRITE_DIR.mkdir(parents=True, exist_ok=True)
    images: dict[str, Image.Image] = {}
    for dna in dna_list:
        img = render(dna)
        path = SPRITE_DIR / ("sp_tower_%s_v1.png" % dna["name"].lower())
        img.save(path)
        images[dna["name"]] = img
    print("[v2] %d tower sprites -> %s" % (len(dna_list), SPRITE_DIR))

    if not args.no_manifest and not args.only:
        update_manifest(build_dna(towers))
        print("[v2] manifest updated -> %s" % MANIFEST)

    if not args.no_preview and not args.only:
        PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
        contact = make_contact(build_dna(towers), images)
        contact.convert("RGB").save(PREVIEW_DIR / "tower-sprites-v2-contact.png")
        heroes = [n for n in HERO if n in images][:15]
        ba = make_before_after(heroes, images)
        ba.convert("RGB").save(PREVIEW_DIR / "tower-sprites-v2-before-after.png")
        bs = make_battle_scale(heroes, images)
        bs.convert("RGB").save(PREVIEW_DIR / "tower-sprites-v2-battle-scale.png")
        print("[v2] previews -> %s" % PREVIEW_DIR)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
