# -*- coding: utf-8 -*-
"""
守核 Corebound · 正式美术资产包 v1 生成器
------------------------------------------------------------
依据 design/art/art-bible.md：
  · §2.2 主色板 —— 色号逐字取用，不二次发明颜色
  · §2.3 稀有度五级色阶 —— P1-6 对口资产
  · §3.4 / §5.5 卡牌 = 机械蓝图 —— 细线描边 / 角标 / 电路装饰
  · §6.5 2D UI 资产规格 —— 卡 512x716 / 插图区 460 安全区 / 图标 128+64 / 九宫格 512 边距 32
  · §9 稀有度非色彩冗余 —— 角标箭头数 1..5 + 底纹密度
  · §10.2 命名 —— snake_case 四段式，_v1 版本后缀
生成方式：PIL 矢量绘制 + 4x 超采样，输出 PNG-32（UI 带 alpha）。
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 4  # 超采样倍率

# ---------------------------------------------------------------------------
# 调色板（art-bible §2.2 逐字 + §2.3 稀有度）
# ---------------------------------------------------------------------------
P_BG = "#141726"          # 夜幕紫（面板底）
P_CARD = "#1E2332"        # 卡片浮起底（ui_style.gd card bg 0.118,0.137,0.196）
P_ALLY = "#3ED0E8"        # 耀青
P_ALLY_2 = "#7A5CFF"      # 星紫
P_ALLY_DARK = "#1A6B7D"   # 深青
P_ENEMY = "#FF6B3D"       # 熔橙
P_ELITE = "#E8437F"       # 噬品红
P_ENEMY_DARK = "#8A2F1C"  # 焦褐
P_GOLD = "#FFC94A"        # 辉金
P_GOLD_HI = "#FFE38A"     # 淡金（§8.3 10-30% 档）
P_STEEL = "#9AA5B1"       # 钢灰
P_ALERT = "#FF2E4E"       # 警报红
P_EDGE = "#0E2430"        # 冷暗描边（塔/UI）
P_ICON_EDGE = "#10131C"   # 图标通用深描边
P_TEXT = "#C8CFDA"        # 正文
P_DIM = "#4A5160"         # 暗钢灰（unavail）

RARITY = {  # §2.3
    "common":    {"hex": "#9AA5B1", "w": 2, "pips": 1},
    "uncommon":  {"hex": "#4FD98A", "w": 4, "pips": 2},
    "rare":      {"hex": "#3EA8FF", "w": 4, "pips": 3},
    "epic":      {"hex": "#B45CFF", "w": 6, "pips": 4},
    "legendary": {"hex": "#FFB020", "w": 6, "pips": 5},
}

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "2d")


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


# ---------------------------------------------------------------------------
# 几何助手（全部在世界坐标 * S 下工作）
# ---------------------------------------------------------------------------
def reg_points(cx, cy, r, n, rot_deg):
    pts = []
    for i in range(n):
        a = math.radians(rot_deg + i * 360.0 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def poly(d, pts, fill=None, outline=None, width=0):
    if fill:
        d.polygon(pts, fill=fill)
    if outline:
        d.line(list(pts) + [pts[0]], fill=outline, width=width, joint="curve")


def rrect(d, box, radius, fill=None, outline=None, width=0):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def outline_mask(size, radius, width):
    """生成圆角矩形描边的 alpha 蒙版（用于渐变描边 / 发光）。"""
    m = Image.new("L", size, 0)
    dm = ImageDraw.Draw(m)
    dm.rounded_rectangle([width // 2, width // 2, size[0] - width // 2 - 1, size[1] - width // 2 - 1],
                         radius=radius, outline=255, width=width)
    return m


def apply_gradient_border(img, size, radius, width, c1, c2):
    """水平渐变描边（传说流光的静态基底）。size 为已乘 S 的像素尺寸。"""
    mask = outline_mask(size, radius, width)
    grad = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    dg = ImageDraw.Draw(grad)
    c1, c2 = hx(c1), hx(c2)
    for x in range(mask.size[0]):
        t = x / max(1, mask.size[0] - 1)
        # 两段往复，近似"流光"来回
        tt = 1 - abs(1 - 2 * t)
        col = tuple(int(c1[i] + (c2[i] - c1[i]) * tt) for i in range(3)) + (255,)
        dg.line([(x, 0), (x, mask.size[1])], fill=col)
    img.paste(grad, (0, 0), mask)


def soft_glow(img, size, radius, width, color, blur, alpha):
    """外发光：描边蒙版模糊后垫底。size 为已乘 S 的像素尺寸。"""
    mask = outline_mask(size, radius, width)
    glow = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    glow.paste(Image.new("RGBA", mask.size, hx(color, 255)), (0, 0), mask)
    glow = glow.filter(ImageFilter.GaussianBlur(blur * S))
    a = glow.getchannel("A").point(lambda v: int(v * alpha))
    glow.putalpha(a)
    base = Image.alpha_composite(glow, img)
    img.paste(base, (0, 0))


def grid_lines(d, box, step, color, width=1):
    x0, y0, x1, y1 = box
    x = x0 + step
    while x < x1:
        d.line([(x, y0), (x, y1)], fill=color, width=width)
        x += step
    y = y0 + step
    while y < y1:
        d.line([(x0, y), (x1, y)], fill=color, width=width)
        y += step


def bracket(d, cx, cy, arm, gap, color, w):
    """四角括号（蓝图风角标）。"""
    for sx in (-1, 1):
        for sy in (-1, 1):
            x = cx + sx * gap
            y = cy + sy * gap
            d.line([(x, y + sy * arm), (x, y), (x + sx * arm, y)], fill=color, width=w, joint="curve")


# ===========================================================================
# A. 九宫格面板（§6.5：512x512 边距 32）
# ===========================================================================
def gen_panel():
    img, d = canvas(512, 512)
    rrect(d, [2 * S, 2 * S, 510 * S, 510 * S], 12 * S, fill=hx(P_BG, 240))
    # 内部高光顶边（§5.1 有重量的物件）
    d.line([(26 * S, 8 * S), (486 * S, 8 * S)], fill=hx(P_ALLY, 26), width=2 * S)
    rrect(d, [2 * S, 2 * S, 510 * S, 510 * S], 12 * S, outline=hx(P_ALLY), width=2 * S)
    save(img, 512, 512, "ui/ui_panel_9slice_v1.png")
    # 🔴 警报变体（批次④）：红描边弹窗（回收确认 / 受损塔处置）——同底同构只换描边色
    #    （高光顶边同步换警报红，属描边同族，不算发明新色：色号 = §2.2 P_ALERT）
    img, d = canvas(512, 512)
    rrect(d, [2 * S, 2 * S, 510 * S, 510 * S], 12 * S, fill=hx(P_BG, 240))
    d.line([(26 * S, 8 * S), (486 * S, 8 * S)], fill=hx(P_ALERT, 26), width=2 * S)
    rrect(d, [2 * S, 2 * S, 510 * S, 510 * S], 12 * S, outline=hx(P_ALERT), width=2 * S)
    save(img, 512, 512, "ui/ui_panel_alert_9slice_v1.png")


# ===========================================================================
# B. 按钮五变体（§5.1 primary/normal/ghost/danger/unavail，240x88 边距 24）
# ===========================================================================
BTN_SPEC = {
    "primary": {"bg": "#26281E", "bg_a": 255, "bd": P_GOLD, "bw": 3, "hi": hx(P_GOLD, 40)},
    "normal":  {"bg": P_CARD,   "bg_a": 255, "bd": P_STEEL, "bw": 2, "hi": hx("#FFFFFF", 18)},
    "ghost":   {"bg": P_BG,     "bg_a": 70,  "bd": P_STEEL, "bw": 1, "hi": hx("#FFFFFF", 10)},
    "danger":  {"bg": "#2A141D", "bg_a": 255, "bd": P_ALERT, "bw": 2, "hi": hx(P_ALERT, 36)},
    "unavail": {"bg": "#171B26", "bg_a": 220, "bd": P_DIM,  "bw": 1, "hi": hx("#000000", 0)},
}


def gen_buttons():
    for name, sp in BTN_SPEC.items():
        img, d = canvas(240, 88)
        # 🔴 圆角 = 6：对齐 ui_style.gd RADIUS（圣经未冻结按钮圆角，实机 SSOT 优先，防接入跳变）
        rrect(d, [2 * S, 2 * S, 238 * S, 86 * S], 6 * S, fill=hx(sp["bg"], sp["bg_a"]))
        d.line([(30 * S, 8 * S), (210 * S, 8 * S)], fill=sp["hi"], width=2 * S)
        rrect(d, [2 * S, 2 * S, 238 * S, 86 * S], 6 * S, outline=hx(sp["bd"]), width=sp["bw"] * S)
        save(img, 240, 88, f"ui/ui_btn_{name}_v1.png")


# ===========================================================================
# C. 稀有度卡框 x5（512x716 · §3.4 / §5.5 / §2.3）
# ===========================================================================
CARD_W, CARD_H = 512, 716
ART_R = 26          # 插图区内板边距 → 内板 460x460（§6.5 安全区）
RADIUS = 30         # 圆角 = 宽 6%（§3.4）


def gen_card_frame(rar):
    sp = RARITY[rar]
    col = sp["hex"]
    img, d = canvas(CARD_W, CARD_H)

    # 底 + 蓝图网格
    rrect(d, [0, 0, (CARD_W - 1) * S, (CARD_H - 1) * S], RADIUS * S, fill=hx(P_CARD))
    grid_lines(d, (8 * S, 8 * S, (CARD_W - 8) * S, (CARD_H - 8) * S), 32 * S, hx(P_ALLY, 12), S)

    # ---- 插图区（顶部 512 方区，内板 460x460 安全区）----
    ax0, ay0, ax1, ay1 = ART_R * S, ART_R * S, (CARD_W - ART_R) * S, (512 - ART_R) * S
    d.rectangle([ax0, ay0, ax1, ay1], fill=hx("#171B2A"))
    grid_lines(d, (ax0, ay0, ax1, ay1), 46 * S, hx(P_ALLY, 16), S)
    # 中心十字准星（蓝图定位符）
    cxc, cyc = (ax0 + ax1) // 2, (ay0 + ay1) // 2
    d.line([(cxc - 14 * S, cyc), (cxc + 14 * S, cyc)], fill=hx(col, 90), width=2 * S)
    d.line([(cxc, cyc - 14 * S), (cxc, cyc + 14 * S)], fill=hx(col, 90), width=2 * S)
    d.ellipse([cxc - 4 * S, cyc - 4 * S, cxc + 4 * S, cyc + 4 * S], outline=hx(col, 120), width=S)
    # 安全区角标括号
    bracket(d, cxc, cyc, 16 * S, 210 * S, hx(col, 150), 2 * S)
    # 费用六边槽（左上，数字由引擎渲染）
    hx_pts = reg_points(70 * S, 70 * S, 30 * S, 6, 90)
    poly(d, hx_pts, fill=hx("#12151F"), outline=hx(P_GOLD), width=3 * S)
    # 电路装饰线（槽 → 角落）
    d.line([(70 * S, 40 * S), (70 * S, 18 * S), (120 * S, 18 * S)], fill=hx(P_GOLD, 110), width=2 * S, joint="curve")

    # ---- 文字区（y 512..716）----
    ty0 = 512 * S
    d.line([(24 * S, ty0), ((CARD_W - 24) * S, ty0)], fill=hx(col, 170), width=2 * S)
    # 三行文案槽导轨（引擎渲染文本，不入图）
    for i, ry in enumerate((76, 152, 190)):
        y = ty0 + ry * S
        w半 = (CARD_W - 96) * S if i == 0 else (CARD_W - 140) * S
        x0 = 48 * S
        d.line([(x0, y), (x0 + w半, y)], fill=hx("#FFFFFF", 16), width=2 * S)
    # 角落十字
    for cx2 in (24 * S, (CARD_W - 24) * S):
        d.line([(cx2 - 6 * S, ty0 + 22 * S), (cx2 + 6 * S, ty0 + 22 * S)], fill=hx(col, 110), width=S)
    # 稀有度横条（底纹密度随稀有度递增 → 非色彩冗余 §9）
    strip_y = (CARD_H - 26) * S
    fill_a = 60 + sp["pips"] * 18
    d.rectangle([24 * S, strip_y, (CARD_W - 24) * S, strip_y + 8 * S], fill=hx(col, fill_a))
    if sp["pips"] >= 3:
        for x in range(24 * S, (CARD_W - 24) * S, 12 * S):
            d.line([(x, strip_y + 8 * S), (x + 6 * S, strip_y)], fill=hx("#0B0E18", 120), width=S)

    # ---- 稀有度角标：1..5 折线箭头（§2.3 角标 + §9 非色彩冗余）----
    px = (CARD_W - 44) * S
    py = ty0 + 40 * S
    for i in range(sp["pips"]):
        x = px - i * 20 * S
        poly(d, [(x - 7 * S, py + 7 * S), (x, py - 7 * S), (x + 7 * S, py + 7 * S)],
             outline=hx(col, 230), width=2 * S)

    # ---- 外框（稀有度描边 + 特效）----
    bw = sp["w"]
    if rar == "epic":     # 外发光（静态基底；脉冲由引擎 Tween）
        soft_glow(img, ((CARD_W) * S, (CARD_H) * S), RADIUS * S, bw * S, col, 10, 0.55)
        d = ImageDraw.Draw(img)
    if rar == "legendary":  # 流光渐变描边（静态基底；流动由引擎 shader/UV）
        apply_gradient_border(img, ((CARD_W) * S, (CARD_H) * S), RADIUS * S, bw * S, P_GOLD, P_GOLD_HI)
        d = ImageDraw.Draw(img)
    elif rar == "rare":   # 内发光
        rrect(d, [bw * S, bw * S, (CARD_W - 1 - bw) * S, (CARD_H - 1 - bw) * S],
              (RADIUS - 4) * S, outline=hx(col, 70), width=6 * S)
    rrect(d, [bw * S // 2, bw * S // 2, (CARD_W - 1 - bw * S // 2 // S) * S, (CARD_H - 1 - bw * S // 2 // S) * S],
          RADIUS * S, outline=hx(col), width=bw * S)

    save(img, CARD_W, CARD_H, f"ui/ui_card_frame_{rar}_v1.png")


# ===========================================================================
# D. 图标体系（128 主体 + 64 small；厚描边平涂，主体 80%）
# ===========================================================================
IC = 128
EDGE = hx(P_ICON_EDGE)
EW = 6  # 描边宽


def _ic_base():
    img, d = canvas(IC, IC)
    return img, d


def _finish(img, rel):
    save(img, IC, IC, f"icons/{rel}")
    small = img.resize((64, 64), Image.LANCZOS)
    p = os.path.join(OUT, "icons", rel.replace("_v1.png", "_small_v1.png"))
    small.save(p)
    print("  + icons/" + os.path.basename(p), "64x64")


def _oct(d, cx, cy, r, fill, rot=22.5, outline=EDGE, w=EW):
    poly(d, reg_points(cx * S, cy * S, r * S, 8, rot), fill=fill, outline=outline, width=w * S)


def icon_scrap():
    img, d = _ic_base()
    _oct(d, 64, 64, 48, hx(P_GOLD))                       # 螺母外八边
    _oct(d, 64, 64, 24, hx("#12151F"), outline=hx(P_GOLD), w=3)  # 中孔
    _finish(img, "ic_scrap_v1.png")


def icon_core():
    img, d = _ic_base()
    _oct(d, 64, 64, 48, hx(P_ALLY))
    for i in range(8):                                     # 8 刻齿
        a = math.radians(22.5 + i * 45)
        x1, y1 = 64 + 48 * math.cos(a), 64 + 48 * math.sin(a)
        x2, y2 = 64 + 58 * math.cos(a), 64 + 58 * math.sin(a)
        d.line([(x1 * S, y1 * S), (x2 * S, y2 * S)], fill=EDGE, width=(EW - 1) * S)
    d.ellipse([(64 - 14) * S, (64 - 14) * S, (64 + 14) * S, (64 + 14) * S],
              fill=hx("#EAFBFF"), outline=EDGE, width=3 * S)
    _finish(img, "ic_core_v1.png")


def icon_wave():
    img, d = _ic_base()
    for r, w in ((20, 6), (34, 6), (48, 6)):               # 三层来袭弧（敌人极）
        d.arc([(64 - r) * S, (64 - r) * S, (64 + r) * S, (64 + r) * S],
              start=-50, end=50, fill=hx(P_ENEMY), width=w * S)
        d.arc([(64 - r) * S, (64 - r) * S, (64 + r) * S, (64 + r) * S],
              start=130, end=230, fill=hx(P_ENEMY), width=w * S)
    d.ellipse([(64 - 7) * S, (64 - 7) * S, (64 + 7) * S, (64 + 7) * S], fill=hx(P_ENEMY))
    _finish(img, "ic_wave_v1.png")


def icon_tower():
    img, d = _ic_base()
    rrect(d, [20 * S, 88 * S, 108 * S, 104 * S], 6 * S, fill=hx(P_ALLY_DARK), outline=EDGE, width=EW * S)  # 底座横台
    _oct(d, 64, 60, 34, hx(P_ALLY))                        # 塔身
    d.rectangle([(64 - 10) * S, 22 * S, (64 + 10) * S, 40 * S], fill=hx(P_ALLY_2), outline=EDGE, width=3 * S)  # 顶结构
    d.ellipse([(64 - 8) * S, (60 - 8) * S, (64 + 8) * S, (60 + 8) * S], fill=hx("#EAFBFF"), outline=EDGE, width=2 * S)
    _finish(img, "ic_tower_v1.png")


def icon_elite():
    img, d = _ic_base()
    for i in range(12):                                    # 尖刺环（有机）
        a = math.radians(i * 30)
        x1, y1 = 64 + 34 * math.cos(a), 64 + 34 * math.sin(a)
        x2, y2 = 64 + 52 * math.cos(a), 64 + 52 * math.sin(a)
        d.line([(x1 * S, y1 * S), (x2 * S, y2 * S)], fill=EDGE, width=5 * S)
    d.ellipse([30 * S, 30 * S, 98 * S, 98 * S], fill=hx(P_ELITE), outline=EDGE, width=EW * S)
    d.ellipse([48 * S, 48 * S, 80 * S, 80 * S], outline=hx("#2E1008"), width=4 * S)
    _finish(img, "ic_elite_v1.png")


def icon_salvage():
    img, d = _ic_base()
    for rot in (0, 120, 240):                              # 三角循环箭头
        pts = []
        for t in range(0, 91, 30):
            a = math.radians(rot + t - 90)
            r = 44 if t in (0, 90) else 38
            pts.append((64 + r * math.cos(a), 64 + r * math.sin(a)))
        pts = [(x * S, y * S) for x, y in pts]
        d.line(pts, fill=hx(P_GOLD), width=6 * S, joint="curve")
        a = math.radians(rot)
        tx, ty = 64 + 46 * math.cos(a), 64 + 46 * math.sin(a)
        poly(d, reg_points(tx * S, ty * S, 11 * S, 3, math.degrees(a) + 90), fill=hx(P_GOLD))
    _finish(img, "ic_salvage_v1.png")


def icon_check():
    img, d = _ic_base()
    d.line([(34 * S, 68 * S), (56 * S, 92 * S), (96 * S, 38 * S)],
           fill=hx("#F2F5FA"), width=11 * S, joint="curve")  # 白本体：modulate 着色
    _finish(img, "ic_check_v1.png")


def icon_cross():
    img, d = _ic_base()
    for pts in ([(40, 40), (88, 88)], [(88, 40), (40, 88)]):
        d.line([(x * S, y * S) for x, y in pts], fill=hx("#F2F5FA"), width=11 * S)  # 白本体
    _finish(img, "ic_cross_v1.png")


def icon_lock():
    img, d = _ic_base()
    d.arc([40 * S, 22 * S, 88 * S, 74 * S], start=180, end=360, fill=hx(P_STEEL), width=9 * S)
    d.rounded_rectangle([32 * S, 52 * S, 96 * S, 100 * S], radius=8 * S,
                        fill=hx(P_STEEL), outline=EDGE, width=EW * S)
    d.ellipse([(64 - 6) * S, 68 * S, (64 + 6) * S, 80 * S], fill=hx("#12151F"))
    _finish(img, "ic_lock_v1.png")


def icon_repair():
    img, d = _ic_base()
    d.line([(44 * S, 84 * S), (84 * S, 44 * S)], fill=hx(P_STEEL), width=12 * S)  # 柄
    poly(d, reg_points(78 * S, 34 * S, 22 * S, 8, 22.5), fill=hx(P_STEEL))  # 八边头
    d.ellipse([(78 - 8) * S, (34 - 8) * S, (78 + 8) * S, (34 + 8) * S], fill=hx("#12151F"))
    _finish(img, "ic_repair_v1.png")


def icon_timer():
    img, d = _ic_base()
    d.ellipse([28 * S, 28 * S, 100 * S, 100 * S], fill=hx("#12151F"), outline=hx(P_GOLD), width=6 * S)
    d.line([(64 * S, 64 * S), (64 * S, 38 * S)], fill=hx(P_GOLD), width=5 * S)
    d.line([(64 * S, 64 * S), (82 * S, 74 * S)], fill=hx(P_GOLD), width=5 * S)
    d.line([(52 * S, 16 * S), (76 * S, 16 * S)], fill=EDGE, width=6 * S)
    _finish(img, "ic_timer_v1.png")


def icon_reroll():
    img, d = _ic_base()
    for rot in (0, 180):
        pts = []
        for t in range(0, 151, 25):
            a = math.radians(rot + t)
            r = 40
            pts.append((64 + r * math.cos(a), 64 + r * math.sin(a) * 0.92))
        pts = [(x * S, y * S) for x, y in pts]
        d.line(pts, fill=hx(P_GOLD), width=7 * S, joint="curve")
        a = math.radians(rot + 150)
        tx, ty = 64 + 40 * math.cos(a), 64 + 40 * math.sin(a) * 0.92
        poly(d, reg_points(tx * S, ty * S, 12 * S, 3, math.degrees(a) + 90), fill=hx(P_GOLD))
    _finish(img, "ic_reroll_v1.png")


# ---- 元素 tag 图标（卡面标记；形状即编码）----
def icon_fire():
    img, d = _ic_base()
    flame = [(64, 18), (80, 44), (94, 60), (92, 84), (74, 104), (54, 104), (36, 84), (34, 60), (48, 44), (56, 58), (64, 40)]
    poly(d, [(x * S, y * S) for x, y in flame], fill=hx(P_ENEMY), outline=EDGE, width=EW * S)
    inner = [(64, 58), (76, 80), (70, 94), (58, 94), (52, 80)]
    poly(d, [(x * S, y * S) for x, y in inner], fill=hx(P_GOLD))
    _finish(img, "ic_tag_fire_v1.png")


def icon_frost():
    img, d = _ic_base()
    for i in range(6):
        a = math.radians(i * 60)
        x2, y2 = 64 + 44 * math.cos(a), 64 + 44 * math.sin(a)
        d.line([(64 * S, 64 * S), (x2 * S, y2 * S)], fill=hx(P_ALLY), width=7 * S)
        for t in (0.62,):
            bx, by = 64 + 44 * t * math.cos(a), 64 + 44 * t * math.sin(a)
            for da in (35, -35):
                b = a + math.radians(da)
                d.line([(bx * S, by * S), ((bx + 12 * math.cos(b)) * S, (by + 12 * math.sin(b)) * S)],
                       fill=hx(P_ALLY), width=5 * S)
    d.ellipse([(64 - 8) * S, (64 - 8) * S, (64 + 8) * S, (64 + 8) * S], fill=hx(P_ALLY), outline=EDGE, width=3 * S)
    _finish(img, "ic_tag_frost_v1.png")


def icon_pierce():
    img, d = _ic_base()
    for i, y in enumerate((30, 56, 82)):                   # 三重 chevron 穿透
        off = i * 6
        poly(d, [(28 * S, y * S), ((62 + off) * S, (y - 14) * S), ((62 + off) * S, (y + 14) * S)],
             fill=hx("#3EA8FF"), outline=EDGE, width=4 * S)
    d.line([(92 * S, 20 * S), (92 * S, 108 * S)], fill=hx("#3EA8FF"), width=5 * S)
    _finish(img, "ic_tag_pierce_v1.png")


def icon_shock():
    img, d = _ic_base()
    bolt = [(70, 12), (42, 62), (60, 62), (50, 112), (92, 50), (70, 50), (86, 12)]
    poly(d, [(x * S, y * S) for x, y in bolt], fill=hx(P_GOLD), outline=EDGE, width=EW * S)
    _finish(img, "ic_tag_shock_v1.png")


def icon_phys():
    img, d = _ic_base()
    d.rectangle([26 * S, 34 * S, 74 * S, 62 * S], fill=hx(P_STEEL), outline=EDGE, width=EW * S)  # 锤头
    d.line([(70 * S, 58 * S), (98 * S, 100 * S)], fill=hx(P_ENEMY_DARK), width=13 * S)                   # 柄
    _finish(img, "ic_tag_phys_v1.png")


def icon_magic():
    img, d = _ic_base()
    d.ellipse([24 * S, 24 * S, 104 * S, 104 * S], outline=hx("#B45CFF"), width=6 * S)
    poly(d, reg_points(64 * S, 64 * S, 30 * S, 4, 0), fill=hx("#B45CFF"), outline=EDGE, width=4 * S)
    d.ellipse([(64 - 6) * S, (64 - 6) * S, (64 + 6) * S, (64 + 6) * S], fill=hx("#12151F"))
    _finish(img, "ic_tag_magic_v1.png")


def icon_true():
    img, d = _ic_base()
    d.ellipse([24 * S, 24 * S, 104 * S, 104 * S], fill=hx("#12151F"), outline=hx(P_ALLY_2), width=6 * S)
    d.ellipse([44 * S, 44 * S, 84 * S, 84 * S], outline=hx(P_ALLY_2), width=4 * S)
    d.line([(40, 92), (92, 36)], fill=hx(P_ALLY_2), width=6 * S)   # 无视抗性斜切
    _finish(img, "ic_tag_true_v1.png")


def icon_econ():
    img, d = _ic_base()
    for i, y in enumerate((76, 62, 48)):                   # 金币堆
        d.ellipse([34 * S, y * S, 94 * S, (y + 22) * S], fill=hx(P_GOLD), outline=EDGE, width=4 * S)
    d.ellipse([48 * S, 30 * S, 80 * S, 56 * S], fill=hx(P_GOLD), outline=EDGE, width=4 * S)
    _finish(img, "ic_tag_econ_v1.png")


# ---- 原型徽记（§3.1 S5 内芯徽记同形）----
def icon_proto(shape, n, rot, color):
    img, d = _ic_base()
    _oct(d, 64, 64, 50, hx("#12151F"), outline=hx(P_ALLY), w=4)
    poly(d, reg_points(64 * S, 64 * S, 30 * S, n, rot), fill=hx(color), outline=EDGE, width=4 * S)
    return img


# ---- 卡包徽记（8 包，§README 卡包表；徽记 = 底盘 + 主题符）----
def pack_plate(color):
    img, d = _ic_base()
    _oct(d, 64, 64, 52, hx("#12151F"), outline=hx(color), w=5)
    return img, d


def pack_core():
    img, d = pack_plate(P_STEEL)
    _oct(d, 64, 64, 30, hx(P_STEEL), outline=EDGE, w=4)
    poly(d, reg_points(64 * S, 68 * S, 14 * S, 3, -90), fill=hx("#12151F"))
    _finish(img, "ic_pack_core_v1.png")


def pack_cinder():
    img, d = pack_plate(P_ENEMY)
    poly(d, reg_points(64 * S, 60 * S, 26 * S, 4, 0), fill=hx(P_ENEMY), outline=EDGE, width=4 * S)
    flame = [(64, 40), (74, 58), (80, 68), (76, 82), (64, 88), (52, 82), (48, 68), (54, 58)]
    poly(d, [(x * S, y * S) for x, y in flame], fill=hx(P_GOLD))
    _finish(img, "ic_pack_cinder_v1.png")


def pack_rime():
    img, d = pack_plate(P_ALLY)
    poly(d, reg_points(64 * S, 64 * S, 30 * S, 6, 0), fill=hx(P_ALLY), outline=EDGE, width=4 * S)
    d.line([(64 * S, 44 * S), (64 * S, 84 * S)], fill=hx("#0E2430"), width=4 * S)
    d.line([(48 * S, 54 * S), (80 * S, 74 * S)], fill=hx("#0E2430"), width=4 * S)
    d.line([(48 * S, 74 * S), (80 * S, 54 * S)], fill=hx("#0E2430"), width=4 * S)
    _finish(img, "ic_pack_rime_v1.png")


def pack_pierce():
    img, d = pack_plate("#3EA8FF")
    for i, x in enumerate((40, 58, 76)):
        poly(d, [(x * S, 36 * S), ((x + 16) * S, 64 * S), (x * S, 92 * S)],
             outline=hx("#3EA8FF"), width=5 * S)
    _finish(img, "ic_pack_pierce_v1.png")


def pack_arc():
    img, d = pack_plate(P_GOLD)
    bolt = [(72, 34), (50, 68), (62, 68), (56, 96), (84, 58), (70, 58), (80, 34)]
    poly(d, [(x * S, y * S) for x, y in bolt], fill=hx(P_GOLD), outline=EDGE, width=4 * S)
    _finish(img, "ic_pack_arc_v1.png")


def pack_sunder():
    img, d = pack_plate(P_STEEL)
    d.rectangle([40 * S, 38 * S, 88 * S, 60 * S], fill=hx(P_STEEL), outline=EDGE, width=4 * S)
    d.line([(64 * S, 62 * S), (64 * S, 96 * S)], fill=hx(P_ENEMY_DARK), width=10 * S)
    _finish(img, "ic_pack_sunder_v1.png")


def pack_hex():
    img, d = pack_plate("#B45CFF")
    d.ellipse([36 * S, 36 * S, 92 * S, 92 * S], outline=hx("#B45CFF"), width=5 * S)
    poly(d, reg_points(64 * S, 64 * S, 18 * S, 4, 45), fill=hx("#B45CFF"), outline=EDGE, width=3 * S)
    _finish(img, "ic_pack_hex_v1.png")


def pack_true():
    img, d = pack_plate(P_ALLY_2)
    d.ellipse([32 * S, 32 * S, 96 * S, 96 * S], fill=hx("#12151F"), outline=hx(P_ALLY_2), width=5 * S)
    d.ellipse([48 * S, 48 * S, 80 * S, 80 * S], outline=hx(P_ALLY_2), width=4 * S)
    d.ellipse([(64 - 4) * S, (64 - 4) * S, (64 + 4) * S, (64 + 4) * S], fill=hx("#EADFFF"))
    _finish(img, "ic_pack_true_v1.png")


# ===========================================================================
# 主流程
# ===========================================================================
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    os.chdir(os.path.join(here, ".."))
    print("[1/4] 九宫格与按钮…")
    gen_panel()
    gen_buttons()
    print("[2/4] 稀有度卡框 x5…")
    for rar in RARITY:
        gen_card_frame(rar)
    print("[3/4] 图标体系…")
    icon_scrap(); icon_core(); icon_wave(); icon_tower(); icon_elite()
    icon_salvage(); icon_check(); icon_cross(); icon_lock(); icon_repair()
    icon_timer(); icon_reroll()
    icon_fire(); icon_frost(); icon_pierce(); icon_shock(); icon_phys()
    icon_magic(); icon_true(); icon_econ()
    for name, n, rot, col in (("arrow", 3, -90, P_ALLY), ("cannon", 4, 45, P_ALLY), ("frost", 6, 0, P_ALLY)):
        img = icon_proto(name, n, rot, col)
        _finish(img, f"ic_proto_{name}_v1.png")
    pack_core(); pack_cinder(); pack_rime(); pack_pierce()
    pack_arc(); pack_sunder(); pack_hex(); pack_true()
    print("[4/4] manifest…")
    write_manifest()
    print("done.")


def write_manifest():
    entries = []
    for root, _dirs, files in os.walk(OUT):
        for f in sorted(files):
            if f.endswith(".png"):
                p = os.path.join(root, f)
                rel = os.path.relpath(p, OUT).replace("\\", "/")
                from PIL import Image as I2
                w, h = I2.open(p).size
                e = {"file": rel, "size": [w, h]}
                if f.startswith("ui_panel_9slice"):
                    e["nine_slice"] = {"left": 32, "top": 32, "right": 32, "bottom": 32}
                elif f.startswith("ui_btn_"):
                    e["nine_slice"] = {"left": 24, "top": 24, "right": 24, "bottom": 24}
                elif f.startswith("ui_card_frame_"):
                    e["nine_slice"] = {"left": 40, "top": 40, "right": 40, "bottom": 40}
                    e["rarity"] = f.split("_")[3]
                entries.append(e)
    man = {
        "pack": "corebound-art-pack",
        "version": "v1",
        "generated": "procedural(PIL 4x supersample)",
        "palette_source": "design/art/art-bible.md §2.2/§2.3",
        "naming": "art-bible §10.2 snake_case",
        "assets": entries,
    }
    with open(os.path.join(OUT, "..", "manifest.json"), "w", encoding="utf-8") as fp:
        json.dump(man, fp, ensure_ascii=False, indent=2)
    print(f"  manifest.json：{len(entries)} 项")


if __name__ == "__main__":
    sys.exit(main())
