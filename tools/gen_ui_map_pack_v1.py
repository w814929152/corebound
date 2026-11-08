#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
守核 Corebound · 选关航图节点体系贴图包 v1 生成器
===============================================================================
为什么做这一包
  `stage_select_overlay.gd` 是最后一个"零贴图整屏"：10 个关卡节点全是
  draw_colored_polygon + draw_polyline 裸画，终局核心节点与普通节点毫无区分，
  左上章节目录用文字字形「◆」。本包把航图节点件贴图化，**不动任何布局**：
  贴图按 stage_select_overlay.gd 既有常量出图（NODE_R=27 / 脉冲环 r=62）。

染色策略（🔴 本包最关键的决定）
  主节点件把"要变的环"烤成白色、填充烤成近黑 #0E1220 → 运行时 modulate 染
  章节色 / 辉金时，环精准命中登记色，填充只被轻微暖化（暗色×彩色仍是暗色）。
  锁定态**不能**用主件减 alpha：整图半透明会让填充透出背景星点 → 单独烘焙。

规格纪律（art-bible）
  · §2.2 色号逐字取用：耀青 #3ED0E8 / 熔橙 #FF6B3D / 警报红 #FF2E4E / 钢灰 #9AA5B1
  · §10.2 命名四段式：<域>_<物>_<用途>_v1.png
  · 4x 超采样 + LANCZOS 降采样；禁渐变 / 禁外发光（高光只允许 1-2px 描边级）

坐标纪律（🔴 全文件只允许 1x 逻辑坐标，绘制时统一过 P() / hex_pts() 放大）
  首版踩坑：六边形用 1x 坐标画在 4x 画布上（整体小 4 倍）；椭圆又把
  「中心 ± 半径*S」算成负坐标（画出画布 → 只剩一段 C 形弧）。
  规则：所有几何量一律 1x，P()/hex_pts()/stroke_hex() 内部统一乘 S。

坐标契约（🔴 改 stage_select_overlay.gd 任何布局常量都必须同步改本文件）
  NODE_R = 27.0        六边形节点外接圆半径 → 节点贴图 64×64（hex r=27 @ 中心）
  脉冲环 r = 62        核心底座外接圆 r=50 < 62，不抢脉冲环
  悬停缩放 ×1.08       运行时缩放贴图，与旧 draw 路径同系数
"""
import json
import math
import os

from PIL import Image, ImageDraw

S = 4  # 超采样倍率

# ---------------------------------------------------------------------------
# 调色板（art-bible §2.2 逐字）
# ---------------------------------------------------------------------------
P_ALLY = "#3ED0E8"      # 耀青（第二章 · 霜序）
P_ENEMY = "#FF6B3D"     # 熔橙（第一章 · 熔炉）
P_ALERT = "#FF2E4E"     # 警报红（终局 · 核心）
P_STEEL = "#9AA5B1"     # 钢灰（第三章 · 枢网 / 锁定态）
P_NODE_FILL = "#0E1220"  # 节点填充（近黑，modulate 染色安全）
P_NODE_FILL_LK = "#0B0E18"  # 锁定态填充（更暗一档）
P_INK = "#05070E"       # 内衬暗缝
P_CORE_PLATE = "#10131F"  # 核心底座盘
P_WHITE = "#FFFFFF"

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "2d", "ui")
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "manifest.json")


def hx(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def canvas(w, h):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, w, h, rel):
    img = img.resize((w, h), Image.LANCZOS)
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("  +", rel, f"{w}x{h}")
    return rel


def P(x, y):
    """1x 逻辑坐标 -> 超采样坐标（🔴 全文件唯一的坐标放大入口）。"""
    return (x * S, y * S)


def hex_pts(cx, cy, r):
    """尖顶六边形顶点（与 stage_select_overlay._hex 同向：60k-90°）。1x 进，4x 出。"""
    return [P(cx + math.cos(math.radians(60.0 * k - 90.0)) * r,
              cy + math.sin(math.radians(60.0 * k - 90.0)) * r) for k in range(6)]


def stroke_hex(d, cx, cy, r, col, w1x):
    pts = hex_pts(cx, cy, r)
    pts.append(pts[0])
    d.line(pts, fill=col, width=max(1, int(round(w1x * S))), joint="curve")


def dot(d, cx, cy, r1x, col):
    r = r1x * S
    d.ellipse([cx * S - r, cy * S - r, cx * S + r, cy * S + r], fill=col)


def ring(d, cx, cy, r1x, col, w1x):
    r = r1x * S
    w = max(1, int(round(w1x * S)))
    d.ellipse([cx * S - r, cy * S - r, cx * S + r, cy * S + r], outline=col, width=w)


# ---------------------------------------------------------------------------
# ① 关卡节点本体（64×64 · 白环可染色）
# ---------------------------------------------------------------------------
def gen_node():
    w = h = 64
    c = w / 2.0
    img, d = canvas(w, h)
    # 填充（近黑 —— modulate 染色时只被轻微暖化）
    d.polygon(hex_pts(c, c, 27.0), fill=hx(P_NODE_FILL, 247))
    # 内衬暗缝（凹陷语言：环内 1px 暗缝把描边和填充分开）
    stroke_hex(d, c, c, 23.6, hx(P_INK, 220), 1.0)
    # 白环（运行时 modulate 染章节色 / 辉金）
    stroke_hex(d, c, c, 27.0, hx(P_WHITE, 255), 2.2)
    # 顶边微高光（描边级，非发光）
    stroke_hex(d, c, c, 24.8, hx(P_WHITE, 34), 1.0)
    return save(img, w, h, "ui_map_node_v1.png")


# ---------------------------------------------------------------------------
# ② 锁定态节点（64×64 · 钢灰 α0.45 环烘焙，不染色）
# ---------------------------------------------------------------------------
def gen_node_locked():
    w = h = 64
    c = w / 2.0
    img, d = canvas(w, h)
    d.polygon(hex_pts(c, c, 27.0), fill=hx(P_NODE_FILL_LK, 235))
    stroke_hex(d, c, c, 23.6, hx(P_INK, 160), 1.0)
    # 环：钢灰 α0.45×255≈115，描边 1.6（与旧 draw 路径 ring_w 同值）
    stroke_hex(d, c, c, 27.0, hx(P_STEEL, 115), 1.6)
    return save(img, w, h, "ui_map_node_locked_v1.png")


# ---------------------------------------------------------------------------
# ③ 终局核心底座（112×112 · 透明中心，画在核心节点下层）
# ---------------------------------------------------------------------------
def gen_node_core():
    w = h = 112
    c = w / 2.0
    img, d = canvas(w, h)
    # 底盘（暗盘承托节点，让终局有"分量"但不抢脉冲环 r=62）
    d.polygon(hex_pts(c, c, 44.0), fill=hx(P_CORE_PLATE, 235))
    # 内环（警戒红 α0.30）
    stroke_hex(d, c, c, 44.0, hx(P_ALERT, 77), 1.5)
    # 外环（警戒红 α0.60）
    stroke_hex(d, c, c, 50.0, hx(P_ALERT, 153), 3.0)
    # 外环六顶点小圆点（航图语言：站标）
    for (px, py) in hex_pts(c, c, 50.0):
        d.ellipse([px - 2.4 * S, py - 2.4 * S, px + 2.4 * S, py + 2.4 * S],
                  fill=hx(P_ALERT, 210))
    return save(img, w, h, "ui_map_node_core_v1.png")


# ---------------------------------------------------------------------------
# ④ 悬停 / 当前光环（80×80 · 白环 α0.40 烘焙，modulate 控色）
#    当前态：tint 章节色（α 合成 0.40，与旧路径一致）
#    悬停态：tint 白 α0.65（0.40×0.65≈0.26，与旧路径一致）
# ---------------------------------------------------------------------------
def gen_node_halo():
    img, d = canvas(80, 80)
    ring(d, 40, 40, 33.5, hx(P_WHITE, 30), 1.0)
    ring(d, 40, 40, 36.0, hx(P_WHITE, 102), 2.0)
    return save(img, 80, 80, "ui_map_node_halo_v1.png")


# ---------------------------------------------------------------------------
# ⑤-⑧ 章节徽记（32×32 · 烘焙章节色 · 2-3 色封顶 · 平面无渐变）
# ---------------------------------------------------------------------------
def _badge_canvas():
    img, d = canvas(32, 32)
    return img, d, 16.0


def gen_badge_ch1():
    """第一章 · 熔炉：炉体梯形 + 暗炉口 + 火苗三角（熔橙）。"""
    img, d, c = _badge_canvas()
    d.polygon([P(c - 6, c + 0), P(c + 6, c + 0), P(c + 9, c + 12), P(c - 9, c + 12)],
              fill=hx(P_ENEMY, 255))
    d.polygon([P(c - 3.4, c + 5), P(c + 3.4, c + 5), P(c + 3.4, c + 11), P(c - 3.4, c + 11)],
              fill=hx(P_INK, 255))                                # 炉口
    # 火苗：底边压进炉体顶边 1px（首版悬空 5px 被读成字母 A）
    d.polygon([P(c, c - 9), P(c + 3.0, c + 1.0), P(c - 3.0, c + 1.0)],
              fill=hx(P_ENEMY, 255))                              # 火苗
    d.line([P(c - 10, c + 12), P(c + 10, c + 12)], fill=hx(P_ENEMY, 255), width=S)
    return save(img, 32, 32, "ui_map_badge_ch1_v1.png")


def gen_badge_ch2():
    """第二章 · 霜序：六向雪花（耀青）。"""
    img, d, c = _badge_canvas()
    L = 11.0
    for k in range(6):
        a = math.radians(60.0 * k)
        dx, dy = math.cos(a), math.sin(a)
        d.line([P(c - dx * L, c - dy * L), P(c + dx * L, c + dy * L)],
               fill=hx(P_ALLY, 255), width=2 * S)
        # 端叉：臂端向两侧张开的两根 4px 短线
        for sgn in (-1, 1):
            fa = a + sgn * math.radians(35.0)
            fx, fy = math.cos(fa), math.sin(fa)
            d.line([P(c + dx * (L - 4.5), c + dy * (L - 4.5)),
                    P(c + dx * (L - 4.5) + fx * 4.0, c + dy * (L - 4.5) + fy * 4.0)],
                   fill=hx(P_ALLY, 255), width=S)
    return save(img, 32, 32, "ui_map_badge_ch2_v1.png")


def gen_badge_ch3():
    """第三章 · 枢网：中心小六环 + 三向节点连线（青钢）。"""
    img, d, c = _badge_canvas()
    stroke_hex(d, c, c, 5.0, hx(P_STEEL, 255), 1.5)
    for k in range(3):
        a = math.radians(90.0 + 120.0 * k)
        ex, ey = c + math.cos(a) * 11.0, c + math.sin(a) * 11.0
        d.line([P(c + math.cos(a) * 5.0, c + math.sin(a) * 5.0), P(ex, ey)],
               fill=hx(P_STEEL, 255), width=max(1, int(1.5 * S)))
        dot(d, ex, ey, 2.6, hx(P_STEEL, 255))
    return save(img, 32, 32, "ui_map_badge_ch3_v1.png")


def gen_badge_ch4():
    """终局 · 核心：同心环 + 中心实点 + 四向刻度（警报红）。"""
    img, d, c = _badge_canvas()
    ring(d, c, c, 11.0, hx(P_ALERT, 255), 2.0)
    dot(d, c, c, 4.5, hx(P_ALERT, 255))
    for k in range(4):
        a = math.radians(90.0 * k)
        d.line([P(c + math.cos(a) * 12.5, c + math.sin(a) * 12.5),
                P(c + math.cos(a) * 15.0, c + math.sin(a) * 15.0)],
               fill=hx(P_ALERT, 220), width=max(1, int(1.5 * S)))
    return save(img, 32, 32, "ui_map_badge_ch4_v1.png")


# ---------------------------------------------------------------------------
# manifest 登记（幂等：同名条目先删再插）
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
    print("[gen_ui_map_pack_v1] 选关航图节点体系 · 8 件")
    done = [
        gen_node(),
        gen_node_locked(),
        gen_node_core(),
        gen_node_halo(),
        gen_badge_ch1(),
        gen_badge_ch2(),
        gen_badge_ch3(),
        gen_badge_ch4(),
    ]
    sizes = {
        "ui_map_node_v1.png": [64, 64],
        "ui_map_node_locked_v1.png": [64, 64],
        "ui_map_node_core_v1.png": [112, 112],
        "ui_map_node_halo_v1.png": [80, 80],
        "ui_map_badge_ch1_v1.png": [32, 32],
        "ui_map_badge_ch2_v1.png": [32, 32],
        "ui_map_badge_ch3_v1.png": [32, 32],
        "ui_map_badge_ch4_v1.png": [32, 32],
    }
    register([{"file": "ui/" + n, "size": sizes[n]} for n in done])
    print("[done] 8 assets -> art/2d/ui/")


if __name__ == "__main__":
    main()
