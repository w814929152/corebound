#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
守核 Corebound · HUD 仪表层贴图包 v1 生成器
===============================================================================
为什么做这一包
  资产包 v1（gen_art_pack_v1.py）只覆盖了「静态界面件」：按钮 / 面板 / 卡框 / 图标。
  **HUD 层一件贴图都没有**——战斗信息全是 draw_* 裸画：一个 StyleBoxFlat 方块当
  金币卡、一根 300x10 悬空细条当波次条、20 个直角方块当核心血条。
  这一包把 HUD 从「浮在战场上的字」变成「一台仪表的读数面板」，且**不动任何布局**：
  贴图按 hud.gd / core_hp_bar.gd 既有常量出图，接入时只加绘制不挪控件。

规格纪律（art-bible）
  · §2.2 色号逐字取用，禁止二次发明颜色 —— 面板底 #141726 / 耀青 #3ED0E8 /
    熔橙 #FF6B3D / 噬品红 #E8437F / 警报红 #FF2E4E / 钢灰 #9AA5B1
  · §10.2 命名四段式：<域>_<物>_<用途>_v1.png
  · 4x 超采样 + LANCZOS 降采样（与 v1 同工艺，1px 细节不糊）
  · 视觉语言与资产包 v1 同族：切角 + 冷暗描边 + 极淡蓝图网格 + 顶边高光

坐标契约（🔴 改这两个脚本里任何常量都必须同步改本文件顶部注释）
  hud.gd            SCORE_BOX = Rect2(26, 12, 214, 86)   金币/积分读数
                    WAVE_BAR_W/H = 300 / 10, by = 90.0   波次进度条
  core_hp_bar.gd    SEG_COUNT=20, SEG_W=28, SEG_H=22, SEG_GAP=4, BOTTOM_MARGIN=46
  → 本包出图尺寸即上列常量的**外扩承托尺寸**，接入时按「以内容框中心对齐」摆放。
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 4  # 超采样倍率

# ---------------------------------------------------------------------------
# 调色板（art-bible §2.2 逐字）
# ---------------------------------------------------------------------------
P_BG = "#141726"        # 夜幕紫（面板底）
P_CARD = "#1E2332"      # 卡片浮起底
P_HUD = "#242B3E"       # HUD 承托板底（战场实测 #111A2B/#231B2B，面板底同色会隐形）
P_ALLY = "#3ED0E8"      # 耀青
P_ALLY_HI = "#9BEDF7"   # 青高光（青的同族提亮，非新色相）
P_ALLY_DARK = "#1A6B7D" # 深青
P_ENEMY = "#FF6B3D"     # 熔橙
P_ENEMY_HI = "#FF9A6B"  # 熔橙高光
P_ENEMY_DK = "#B23A17"  # 熔橙暗部
P_ELITE = "#E8437F"     # 噬品红
P_ELITE_HI = "#FF8AB0"  # 品红高光
P_ELITE_DK = "#8E1E45"  # 品红暗部
P_ALERT = "#FF2E4E"     # 警报红
P_ALERT_HI = "#FF8195"  # 警报红高光
P_ALERT_DK = "#8E0B1F"  # 警报红暗部
P_STEEL = "#9AA5B1"     # 钢灰
P_INK = "#05070E"       # 槽底墨黑（比面板更深一档，制造凹陷）
P_EDGE = "#0E2430"      # 冷暗描边

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


def P(x, y):
    """世界坐标 -> 超采样坐标。"""
    return (x * S, y * S)


def chamfer_pts(x0, y0, x1, y1, tl=0, tr=0, br=0, bl=0):
    """切角矩形路径（顺时针）。切角 = 工程图零件语言，与 v1 面板的圆角并置也不打架。"""
    pts = []
    pts.append((x0 + tl, y0))                      # 上边起点
    pts.append((x1 - tr, y0))
    if tr:
        pts.append((x1, y0 + tr))
    pts.append((x1, y1 - br))
    if br:
        pts.append((x1 - br, y1))
    pts.append((x0 + bl, y1))
    if bl:
        pts.append((x0, y1 - bl))
    pts.append((x0, y0 + tl))
    return pts


def sc(pts):
    """路径坐标统一乘 S。"""
    return [(x * S, y * S) for x, y in pts]


def plate(img, d, box, chamfer, fill, border=None, bw=1, hi_top=True):
    """切角承托板：底填充 + 冷暗描边 + 顶边高光 + 底边压暗。"""
    x0, y0, x1, y1 = box
    pts = sc(chamfer_pts(x0, y0, x1, y1, *chamfer))
    d.polygon(pts, fill=fill)
    if border is not None:
        d.line(pts + [pts[0]], fill=border, width=max(1, int(bw * S)), joint="curve")
    if hi_top:
        # 顶边 1px 高光（§5.1 有重量的物件），只在直线段内缩 2px，避开切角
        d.line([P(x0 + chamfer[0] + 2, y0 + 0.5), P(x1 - chamfer[1] - 2, y0 + 0.5)],
               fill=(255, 255, 255, 16), width=1 * S)
        # 底边 1px 压暗，制造厚度
        d.line([P(x0 + chamfer[3] + 2, y1 - 0.5), P(x1 - chamfer[2] - 2, y1 - 0.5)],
               fill=(0, 0, 0, 90), width=1 * S)
    return pts


def clip_grid(img, d, pts, box, step=16, color=(62, 208, 232, 7)):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    x = x0 + step
    while x < x1:
        dl.line([P(x, y0), P(x, y1)], fill=color, width=1 * S)
        x += step
    y = y0 + step
    while y < y1:
        dl.line([P(x0, y), P(x1, y)], fill=color, width=1 * S)
        y += step
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    img.paste(layer, (0, 0), mask)


def vgrad(box, top, bot):
    """纵向渐变条（用于条状物上下高光/压暗），返回 RGBA 图层。"""
    x0, y0, x1, y1 = box
    w, h = int((x1 - x0) * S), int((y1 - y0) * S)
    img = Image.new("RGBA", (max(1, w), max(1, h)))
    d = ImageDraw.Draw(img)
    for yy in range(h):
        t = yy / max(1, h - 1)
        col = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(4))
        d.line([(0, yy), (w, yy)], fill=col)
    return img


def rrect(d, box, radius, fill=None, outline=None, width=0):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


# ===========================================================================
# 1. 金币/积分读数承托板（232x104）
#    原 hud.gd SCORE_BOX = 214x86 —— 四周各让 9px 呼吸，接入时画在 (18, 4)。
#    视觉：切角左上 / 右下（对角呼应），青色切角边 = 工程图"零件切口"强调。
# ===========================================================================
def gen_score_plate():
    W, H = 232, 104
    img, d = canvas(W, H)
    cham = (18, 3, 18, 3)
    # 🔴 承托板必须比战场"亮一档"才立得住：战场实测底色 #231B2B / #111A2B，
    #    面板底 #141726 叠上去几乎不可见（首版实测就是隐形）。改用已登记的
    #    浮起色 P_CARD #1E2332 + 钢灰描边，靠明度差分离，不靠发光。
    pts = plate(img, d, (1, 1, W - 1, H - 1), cham, hx(P_HUD, 250),
                border=hx(P_STEEL, 150), bw=1)
    clip_grid(img, d, pts, (3, 3, W - 3, H - 3), step=24, color=(62, 208, 232, 5))
    # 切角边染青：被"切"出来的两个斜面 = 本件最锋利的识别点
    d.line([P(1, 19), P(19, 1)], fill=hx(P_ALLY, 180), width=2 * S)
    d.line([P(W - 1, H - 19), P(W - 19, H - 1)], fill=hx(P_ALLY, 180), width=2 * S)
    # 顶边内侧一道青呼吸线（只做"设备在通电"的暗示）
    d.line([P(26, 6), P(W - 26, 6)], fill=hx(P_ALLY, 40), width=1 * S)
    save(img, W, H, "ui/ui_hud_plate_score_v1.png")


# ===========================================================================
# 2. 波次仪表导轨（348x56）
#    槽位契约：纹理内 (28, 23, 300, 12) —— 接入时导轨画在 (bx-28, by-23)。
#    🔴 高度只到 36（= by+13 收底）：`已出/总数` 读数的字顶约在 by+14，
#       首版 56 高把读数整个罩进导轨里，实机截图里读成"被压住的暗字"。
#    🔴 右端只外扩 20：`_start_wave_btn` 在 bx+326 起（vw/2+150+26），
#       首版 392 宽会压到按钮上，实测量过才收窄。
# ===========================================================================
def gen_wave_rail():
    W, H = 348, 36
    img, d = canvas(W, H)
    cham = (8, 3, 8, 3)
    pts = plate(img, d, (1, 1, W - 1, H - 1), cham, hx(P_HUD, 248),
                border=hx(P_STEEL, 130), bw=1)
    clip_grid(img, d, pts, (3, 3, W - 3, H - 3), step=16, color=(62, 208, 232, 7))
    # 凹槽：外圈 1px 暗缝 → 内圈墨黑 → 底部 1px 反光（凹陷的三段式）
    sx, sy, sw, sh = 28, 23, 300, 12
    d.rectangle([P(sx - 1, sy - 1), P(sx + sw, sy + sh)], fill=hx("#000000", 130))
    d.rectangle([P(sx, sy), P(sx + sw - 1, sy + sh - 1)], fill=hx(P_INK, 255))
    d.line([P(sx + 1, sy + sh), P(sx + sw - 2, sy + sh)], fill=(255, 255, 255, 14), width=1 * S)
    # 槽两端定位角（量程起止，2px 青）
    d.line([P(sx - 1, sy - 2), P(sx - 1, sy + sh + 1)], fill=hx(P_ALLY, 120), width=2 * S)
    d.line([P(sx + sw, sy - 2), P(sx + sw, sy + sh + 1)], fill=hx(P_ALLY, 120), width=2 * S)
    # 槽上方刻度尺：与填充的 12 格同相位（每 25px），第 4/8/12 格加长加深
    for k in range(1, 12):
        x = sx + k * 25
        major = (k % 4 == 0)
        top = 11 if major else 14
        d.line([P(x, top), P(x, sy - 3)],
               fill=hx(P_ALLY, 70) if major else hx(P_STEEL, 46), width=1 * S)
    save(img, W, H, "ui/ui_hud_plate_wave_v1.png")


# ===========================================================================
# 3. 四角角标（72x72 · 左上基准，运行时翻转复用四角）
#    工程图框语言：L 形 + 内端 45° 收口 + 内侧短刻度。
# ===========================================================================
def gen_corner():
    W = H = 72
    img, d = canvas(W, H)
    ins, arm, ch = 2, 56, 12
    # L 形主臂：竖 → 45° 内收口 → 横（收口让直角不死板，是工程图"零件圆角"的直边版）
    path = [(ins, ins + arm), (ins, ins + ch), (ins + ch, ins), (ins + arm, ins)]
    # 先垫 1px 暗描边，保证在亮战场上也分离得开
    d.line([P(x, y) for x, y in path], fill=(0, 0, 0, 110), width=4 * S, joint="curve")
    d.line([P(x, y) for x, y in path], fill=hx(P_ALLY, 185), width=2 * S, joint="curve")
    # 臂端各一个 3px 方点（收头，避免线"断在空中"）
    d.rectangle([P(ins - 1, ins + arm - 3), P(ins + 2, ins + arm)], fill=hx(P_ALLY, 230))
    d.rectangle([P(ins + arm - 3, ins - 1), P(ins + arm, ins + 2)], fill=hx(P_ALLY, 230))
    # 🔴 内侧不再加刻度对：2x 放大下读成两道"游离短划"（首版实测），
    #    角标的全部信息量压进"一条 L + 两个收头点"即可。
    save(img, W, H, "ui/ui_hud_corner_v1.png")


# ===========================================================================
# 4-6. 核心血条段（28x22，与 SEG_W/SEG_H 逐 pixel 对齐）
# ===========================================================================
def gen_core_seg_slot():
    W, H = 28, 22
    img, d = canvas(W, H)
    # 🔴 槽底不做纯黑：低血时 16 个空槽会连成一条黑带（实机截图确认"太重"）。
    #    α170 让战场底色透一点进来 → 读作"空插座"而不是"黑洞"。
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 3 * S, fill=hx("#0A0E18", 178),
          outline=hx(P_STEEL, 120), width=1 * S)
    # 凹槽顶边内阴影 + 底边反光
    d.line([P(2, 1.5), P(W - 2, 1.5)], fill=(0, 0, 0, 150), width=1 * S)
    d.line([P(2, H - 2), P(W - 2, H - 2)], fill=(255, 255, 255, 12), width=1 * S)
    save(img, W, H, "ui/ui_core_seg_slot_v1.png")


def _seg_fill(name, base, hi, hi2, dk):
    W, H = 28, 22
    img, d = canvas(W, H)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 3 * S, fill=hx(base))
    # 🔴 只用 1px 亮顶 + 2px 暗底表达"受光"，不做渐变高光带：
    #    首版 4px 高光带把 22px 的段做成了钢琴键（实机 20 段连排后尤其明显）。
    d.line([P(2, 1.5), P(W - 2, 1.5)], fill=hx(hi2, 210), width=1 * S)
    d.line([P(2, H - 2), P(W - 2, H - 2)], fill=hx(dk, 220), width=2 * S)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 3 * S, outline=hx(dk, 240), width=1 * S)
    save(img, W, H, name)


def gen_core_seg_fill():
    _seg_fill("ui/ui_core_seg_fill_v1.png", P_ALLY, P_ALLY, P_ALLY_HI, P_ALLY_DARK)


def gen_core_seg_fill_low():
    W, H = 28, 22
    img, d = canvas(W, H)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 3 * S, fill=hx(P_ALERT))
    # 45° 斜纹（受损/告警的通用图形语言，不靠纯色区分——§9.2 双通道）
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dl = ImageDraw.Draw(layer)
    for k in range(-H, W + H, 6):
        dl.line([P(k, H), P(k + H, 0)], fill=hx(P_ALERT_DK, 120), width=1 * S)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([P(0.5, 0.5), P(W - 0.5, H - 0.5)], radius=3 * S, fill=255)
    img.paste(layer, (0, 0), mask)
    d.line([P(2, 2), P(W - 2, 2)], fill=hx(P_ALERT_HI, 200), width=1 * S)
    d.line([P(2, H - 2), P(W - 2, H - 2)], fill=hx(P_ALERT_DK, 235), width=2 * S)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 3 * S, outline=hx(P_ALERT_DK, 235), width=1 * S)
    save(img, W, H, "ui/ui_core_seg_fill_low_v1.png")


# ===========================================================================
# 7-9. 波次条（300x10 · 轨道 / 填充 / 精英填充）
# ===========================================================================
def gen_wave_track():
    W, H = 300, 10
    img, d = canvas(W, H)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 2 * S, fill=hx(P_INK))
    # 每 25px 一根刻度（12 格），格子在"填充之下也要看得见"→ 画在轨道层
    for k in range(1, 12):
        x = k * 25
        d.line([P(x, 1.5), P(x, H - 1.5)], fill=hx(P_STEEL, 30), width=1 * S)
    d.line([P(1, 1), P(W - 1, 1)], fill=(0, 0, 0, 170), width=1 * S)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 2 * S, outline=hx(P_STEEL, 78), width=1 * S)
    save(img, W, H, "ui/ui_wave_track_v1.png")


def _wave_fill(name, base, hi, hi2, dk):
    W, H = 300, 10
    img, d = canvas(W, H)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 2 * S, fill=hx(base))
    band = vgrad((2, 1.5, W - 2, 4.5), hx(hi2), hx(hi))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([P(0.5, 0.5), P(W - 0.5, H - 0.5)], radius=2 * S, fill=255)
    sub = Image.new("L", img.size, 0)
    ImageDraw.Draw(sub).rectangle([P(2, 1.5), P(W - 2, 4.5)], fill=255)
    m = Image.composite(mask, Image.new("L", img.size, 0), sub)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    layer.paste(band, (int(2 * S), int(1.5 * S)))
    img.paste(layer, (0, 0), m)
    d.line([P(2, H - 1.5), P(W - 2, H - 1.5)], fill=hx(dk, 230), width=1 * S)
    # 格缝（与轨道刻度同位，填充后仍读得出"分格量表"）
    for k in range(1, 12):
        x = k * 25
        d.line([P(x, 1.5), P(x, H - 1.5)], fill=hx(dk, 80), width=1 * S)
    rrect(d, [P(0.5, 0.5), P(W - 0.5, H - 0.5)], 2 * S, outline=hx(dk, 200), width=1 * S)
    save(img, W, H, name)


def gen_wave_fill():
    _wave_fill("ui/ui_wave_fill_v1.png", P_ENEMY, P_ENEMY, P_ENEMY_HI, P_ENEMY_DK)


def gen_wave_fill_elite():
    _wave_fill("ui/ui_wave_fill_elite_v1.png", P_ELITE, P_ELITE, P_ELITE_HI, P_ELITE_DK)


# ===========================================================================
# 10. 波次条游标（8x18 · 填充右端的"指针"，让读数有活气）
# ===========================================================================
def gen_wave_cap():
    W, H = 8, 18
    img, d = canvas(W, H)
    # 竖向亮针：外套 1px 暗描边保证在亮填充上也分离得开
    d.rectangle([P(3, 0), P(5, H - 1)], fill=(0, 0, 0, 120))
    d.rectangle([P(3.5, 0.5), P(4.5, H - 1.5)], fill=(255, 255, 255, 225))
    # 上下小三角（指针头），指向条内
    d.polygon(sc([(2, 0), (6, 0), (4, 3)]), fill=hx(P_STEEL, 190))
    d.polygon(sc([(2, H - 1), (6, H - 1), (4, H - 4)]), fill=hx(P_STEEL, 190))
    save(img, W, H, "ui/ui_wave_cap_v1.png")


# ===========================================================================
def main():
    print("[HUD 仪表层贴图包 v1] -> art/2d/ui/")
    gen_score_plate()
    gen_wave_rail()
    gen_corner()
    gen_core_seg_slot()
    gen_core_seg_fill()
    gen_core_seg_fill_low()
    gen_wave_track()
    gen_wave_fill()
    gen_wave_fill_elite()
    gen_wave_cap()
    print("done. 10 files")


if __name__ == "__main__":
    main()
