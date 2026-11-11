# -*- coding: utf-8 -*-
"""
守核 Corebound · 卡牌重制 v3 卡框产线 · 2026-11-11
------------------------------------------------------------
依据 design/art/card-redesign-2026-11-11.md：
  · 风格锚点 v3：斜切八角金属外框 / 深蓝黑插画区 / 米白信息区 / 单一能量青
  · 逻辑卡 210×340，资源 2x（420×680），8x 超采样矢量绘制后 LANCZOS 收缩
  · 文字一律不进贴图（由 Godot 字体渲染）
  · 与引擎无关：只产 PNG-32 RGBA，导入口径写在设计文档 §4.2

用法（需 Pillow >= 9）：
  python tools/gen_card_frame_v3.py

产出（v3.1 · 2026-11-11 细修）：
  art/2d/ui/ui_card_plate_v3.png     420×680
  art/2d/ui/ui_card_edge_v3_{1,2,3}.png  420×680（三档线宽 = 稀有度第二通道）
  art/2d/ui/ui_card_cost_v3.png      120×50
  art/2d/ui/ui_card_badge_v3.png     388×40（194×20 逻辑，横线贯穿面板）
  art/_review/card-redesign-baseline-v3.png   基准合成效果图（不含文字进资源）
  art/_review/card-redesign-thumbs-v3.png     10% / 25% 缩略图测试接触表
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_DIR = os.path.join(ROOT, "art", "2d", "ui")
REVIEW_DIR = os.path.join(ROOT, "art", "_review")
FONT_DIR = os.path.join(ROOT, "assets", "fonts")
CARD_DIR = os.path.join(ROOT, "art", "2d", "cards")
CARD_REFERENCE = os.path.join(ROOT, "output", "imagegen", "arrow-card-redesign-preview.png")
PACK_BADGE_COLORS = {
    "core": "#54EEE7",
    "cinder": "#FF8059",
    "rime": "#65E4F4",
    "pierce": "#FFD670",
    "arc": "#AD94FF",
    "sunder": "#F670A1",
    "hex": "#62C4B9",
    "true": "#FF637B",
}

# ---------------------------------------------------------------------------
# 色板（design/art/card-redesign-2026-11-11.md §3，唯一来源）
# ---------------------------------------------------------------------------
CREAM = "#FAEEE1"       # 主色 · 米白
INK = "#1E222B"         # 背景 · 深蓝黑
FRAME = "#23262F"       # 框体 · 深蓝灰
CYAN = "#00F2E4"        # 强调 · 能量青
STEEL = "#4C5059"       # 辅色 · 钢灰
BLACK = "#10131A"       # 阴影 / 文字黑

# 逻辑尺寸与超采样
W, H = 210, 340
SCALE = 2               # 资源倍率
SS = 4                  # 超采样倍率（相对 2x）→ 总 8x
U = SCALE * SS          # 每逻辑像素的超采样像素数

CARD_W, CARD_H = W * U, H * U
OUT_W, OUT_H = W * SCALE, H * SCALE


def rgba(hex_color: str, alpha: int = 255):
    h = hex_color.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def sc(pts):
    """逻辑坐标 → 超采样画布坐标"""
    return [(round(x * U), round(y * U)) for x, y in pts]


def cut_rect(x, y, w, h, c):
    """45° 斜切八角矩形"""
    return [
        (x + c, y), (x + w - c, y), (x + w, y + c), (x + w, y + h - c),
        (x + w - c, y + h), (x + c, y + h), (x, y + h - c), (x, y + c),
    ]


def hex_h(x, y, w, h, c):
    """水平尖角六边形（左右各一个尖）"""
    return [
        (x + c, y), (x + w - c, y), (x + w, y + h * 0.5),
        (x + w - c, y + h), (x + c, y + h), (x, y + h * 0.5),
    ]


def fill_poly(d, pts, color, alpha=255):
    d.polygon(sc(pts), fill=rgba(color, alpha))


def stroke_poly(d, pts, color, width=1, alpha=255, joint="curve"):
    p = sc(pts)
    d.line(p + [p[0]], fill=rgba(color, alpha), width=max(1, round(width * U)), joint=joint)


def line(d, a, b, color, width=1, alpha=255):
    d.line([(round(a[0] * U), round(a[1] * U)), (round(b[0] * U), round(b[1] * U))],
           fill=rgba(color, alpha), width=max(1, round(width * U)))


def diamond(d, cx, cy, rx, ry, color, alpha=255):
    fill_poly(d, [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)], color, alpha)


def new_canvas(w=CARD_W, h=CARD_H):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def down(img, size=(OUT_W, OUT_H)):
    return img.resize(size, Image.LANCZOS)


def reference_emblem(bounds, outline, clear_number=False):
    """提取已确认的 AI 预览元件，裁掉周围插画。"""
    with Image.open(CARD_REFERENCE) as reference:
        art = reference.crop(bounds).convert("RGBA")
    x, y = bounds[:2]
    mask = Image.new("L", art.size)
    ImageDraw.Draw(mask).polygon([(px - x, py - y) for px, py in outline], fill=255)
    if clear_number:
        # 抹掉示例价格，数字由 Godot 实时绘制。
        ImageDraw.Draw(art).rectangle((133, 22, 221, 87), fill=(33, 35, 44, 255))
    art.putalpha(mask)
    return art


# ---------------------------------------------------------------------------
# 1. 卡框底板：外框 + 分区 + 中缝六边形 + 底部箭头（插画区保持透明）
# ---------------------------------------------------------------------------
def gen_plate():
    im = new_canvas()
    d = ImageDraw.Draw(im)

    # ---- 1. 外框实体：斜切八角，深蓝灰；左上亮边 / 右下暗边模拟金属倒角 ----
    outer = cut_rect(2.5, 2.5, 205, 335, 8)
    fill_poly(d, outer, FRAME)
    stroke_poly(d, cut_rect(3.6, 3.6, 202.8, 331.8, 7.4), STEEL, 0.9, alpha=105)
    stroke_poly(d, cut_rect(4.6, 4.6, 200.8, 328.8, 6.6), BLACK, 0.7, alpha=90)

    # 🔴 插画区必须挖成透明，让下层的卡包背景 / 全幅插画透出来。
    #    挖空后再画描边与装饰，否则会被一并擦掉。
    d.rectangle([round(8 * U), round(8 * U), round(202 * U), round(228 * U)],
                fill=(0, 0, 0, 0))

    # 🔴 顶部功能芯片（**只覆盖左半**，右缘做透明度渐隐 —— 参考图顶部是整幅插画，
    #    编号 / ▲ / 锁头 / ✓ 需要深底才可读，但不该变成一条硬边横带）。
    _header_chip(im, d)

    # ---- 2. 米白双层细描边（外淡内亮，参考图的「框中有框」）----
    stroke_poly(d, outer, CREAM, 0.9, alpha=155)
    inner = cut_rect(6.6, 6.6, 196.8, 326.8, 6.4)
    stroke_poly(d, inner, CREAM, 1.0, alpha=210)

    # ---- 3. 四角 L 形双刻线（参考图角部的「台阶」细节）----
    _corner_ticks(d)

    # ---- 4. 侧边双斜纹（参考图中段左右各两道青斜杠）----
    for yy in (100.0, 111.0):
        fill_poly(d, [(2.9, yy + 7.4), (7.2, yy), (7.2, yy + 2.7), (2.9, yy + 10.1)], CYAN, alpha=245)
        fill_poly(d, [(207.1, yy + 7.4), (202.8, yy), (202.8, yy + 2.7), (207.1, yy + 10.1)], CYAN, alpha=245)

    # ---- 5. 顶部正中青色刻口（参考图顶边的能量缺口）----
    fill_poly(d, [(96.0, 2.6), (114.0, 2.6), (110.4, 7.6), (99.6, 7.6)], CYAN)
    fill_poly(d, [(99.0, 3.3), (111.0, 3.3), (109.0, 6.2), (101.0, 6.2)], BLACK, alpha=110)

    # ---- 6. 分区线 + 米白信息面板（内缩细边，四角斜切）----
    line(d, (8, 228), (202, 228), BLACK, 1.2, alpha=235)
    band = cut_rect(8, 230, 194, 102, 6)
    fill_poly(d, band, CREAM)
    stroke_poly(d, band, FRAME, 0.8, alpha=195)
    stroke_poly(d, cut_rect(12.4, 234.4, 185.2, 93.2, 4.6), FRAME, 0.6, alpha=90)

    # ---- 7. 底部青色刻口（参考图跨在「面板下沿 / 框带」之间的梯形）----
    fill_poly(d, [(98.0, 330.4), (112.0, 330.4), (116.0, 336.2), (94.0, 336.2)], CYAN)
    stroke_poly(d, cut_rect(2.5, 2.5, 205, 335, 8), BLACK, 0.5, alpha=120)
    return down(im)


def gen_pack_badge(pack_id):
    """复用预览徽章外壳和游戏内卡包图标，输出 2x 接缝徽记。"""
    emblem = reference_emblem(
        (389, 1008, 615, 1107),
        [(389, 1060), (443, 1010), (553, 1010), (614, 1059),
         (556, 1105), (451, 1105)],
    )
    if pack_id != "core":
        color = rgba(PACK_BADGE_COLORS[pack_id])
        for y in range(emblem.height):
            for x in range(emblem.width):
                r, g, b, a = emblem.getpixel((x, y))
                if a and g > r + 35 and b > r + 30:
                    emblem.putpixel((x, y), (*color[:3], a))
        ImageDraw.Draw(emblem).polygon(
            [(75, 11), (157, 11), (170, 29), (152, 87), (65, 87), (52, 67)],
            fill=rgba(FRAME),
        )
        icon_path = os.path.join(ROOT, "art", "2d", "icons", f"ic_pack_{pack_id}_small_v1.png")
        with Image.open(icon_path) as icon:
            inset = icon.convert("RGB").crop((16, 16, 48, 48))
        # 卡包图标的底色本身不透明。用亮度范围保留中央符号及其抗锯齿边缘。
        alpha = Image.new("L", inset.size)
        alpha.putdata([max(0, min(255, round((max(pixel) - 65) * 255 / 75)))
                       for pixel in inset.getdata()])
        alpha = alpha.crop(alpha.getbbox())
        ratio = 62 / max(alpha.size)
        alpha = alpha.resize(tuple(round(side * ratio) for side in alpha.size), Image.LANCZOS)
        glyph = Image.new("RGBA", alpha.size, color)
        glyph.putalpha(alpha)
        emblem.alpha_composite(glyph, ((emblem.width - glyph.width) // 2,
                                       (emblem.height - glyph.height) // 2))
    return emblem.resize((98, 44), Image.LANCZOS)


def _header_chip(im, d):
    """顶部功能芯片：92×24 斜切块，右缘 30px 透明度渐隐，避免在插画上出现硬边。"""
    gw, gh = 92 * U, 24 * U
    grad = Image.new("RGBA", (gw, gh), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for x in range(gw):
        t = x / float(gw)
        a = 232 if t < 0.66 else int(232 * (1.0 - (t - 0.66) / 0.34))
        gd.line([(x, 0), (x, gh - 1)], fill=rgba(INK, max(0, a)))
    mask = Image.new("L", (gw, gh), 0)
    ImageDraw.Draw(mask).polygon(sc(cut_rect(0, 0, 92, 24, 4)), fill=255)
    im.paste(grad, (round(8 * U), round(8 * U)), mask)
    # 下沿一条极淡钢线（只覆盖不渐隐的前 92px，避免变成横贯线）
    line(d, (9.2, 31.2), (66.0, 31.2), STEEL, 0.6, alpha=110)


def _corner_ticks(d):
    """四角 L 形双刻线：沿斜切边向内偏移两条平行线，还原参考图的角部台阶。"""
    ticks = [
        # (起点, 终点) × 内外两档；坐标按 45° 斜切手工给出
        ((13.6, 5.4), (5.4, 13.6), 118),
        ((16.4, 8.2), (8.2, 16.4), 88),
        ((196.4, 5.4), (204.6, 13.6), 118),
        ((193.6, 8.2), (201.8, 16.4), 88),
        ((5.4, 326.4), (13.6, 334.6), 118),
        ((8.2, 323.6), (16.4, 331.8), 88),
        ((204.6, 326.4), (196.4, 334.6), 118),
        ((201.8, 323.6), (193.6, 331.8), 88),
    ]
    for a, b, al in ticks:
        line(d, a, b, CREAM, 0.7, alpha=al)


# ---------------------------------------------------------------------------
# 2. 可染色描边层：纯白单通道，Godot 侧 modulate = 稀有度色 / 悬停青
# ---------------------------------------------------------------------------
def gen_edge(bw: float = 2):
    """可染色描边层：纯白单通道，Godot 侧 modulate = 稀有度色 / 悬停青。

    🆕 v3.1：**线的粗细承担稀有度第二通道** —— 参考图顶部没有角标位，
    因此把「稀有度 = 颜色 + 数量」改为「稀有度 = 颜色 + 描边粗细」（art-bible §2.3 的 bw 1/2/3），
    顶栏只留锁头与费用胶囊，贴近参考图。
    """
    im = new_canvas()
    d = ImageDraw.Draw(im)
    white = "#FFFFFF"
    w_outer = {1: 1.4, 2: 2.2, 3: 3.2}.get(int(bw), 2.2)
    stroke_poly(d, cut_rect(2.5, 2.5, 205, 335, 8), white, w_outer, alpha=240)
    stroke_poly(d, cut_rect(6.6, 6.6, 196.8, 326.8, 6.4), white, 0.9, alpha=165)
    # 🔴 中缝徽章已改为 AI 生图元件（自带米白描边），描边层不再画六边形：
    #    否则稀有度色会在徽章外面再套一圈蓝/紫/金，和参考图不符。
    # 底部刻口（梯形）轮廓：与外框同色，供稀有度 / 悬停染色
    stroke_poly(d, [(98.0, 330.4), (112.0, 330.4), (116.0, 336.2), (94.0, 336.2)], white, 0.8, alpha=190)
    return down(im)


# ---------------------------------------------------------------------------
# 3. 费用角标（120×50 @2x = 逻辑 60×25，不含数字）
# ---------------------------------------------------------------------------
def gen_cost():
    """从预览提取费用角标，输出 120×50，数字由 Godot 绘制。"""
    emblem = reference_emblem(
        (689, 37, 960, 150),
        [(690, 91), (730, 40), (922, 38), (959, 82),
         (955, 131), (945, 149), (727, 149), (690, 98)],
        clear_number=True,
    )
    return emblem.resize((120, 50), Image.LANCZOS)


# ---------------------------------------------------------------------------
# 4. 类型徽章（284×36 @2x = 逻辑 142×18，不含文字）
# ---------------------------------------------------------------------------
def gen_badge():
    im = new_canvas(194 * U, 20 * U)
    d = ImageDraw.Draw(im)
    # 中央深色类型条（斜切端）—— 116px 逻辑宽 × 18px 高：16px 文字 89px + 左右各 13px 呼吸
    cap = cut_rect(36, 1, 122, 18, 5)
    fill_poly(d, cap, FRAME)
    stroke_poly(d, cap, INK, 0.6, alpha=185)
    # 两侧横向细线一直延伸到面板内边（参考图最长的一条横向结构线）
    line(d, (1.4, 10), (29.0, 10), FRAME, 0.9, alpha=225)
    line(d, (165.0, 10), (192.6, 10), FRAME, 0.9, alpha=225)
    # 端部青色双斜纹「//」（左右镜像，alpha 拉满才在米白上立得住）
    for i in range(2):
        x = 29.6 + i * 3.0
        fill_poly(d, [(x, 13.6), (x + 2.2, 6.4), (x + 3.7, 6.4), (x + 1.5, 13.6)], CYAN, alpha=252)
        xr = 194.0 - x - 3.7
        fill_poly(d, [(xr + 3.7, 6.4), (xr + 1.5, 6.4), (xr, 13.6), (xr + 2.2, 13.6)], CYAN, alpha=252)
    return down(im, (388, 40))


# ---------------------------------------------------------------------------
# 5. 基准合成效果图（仅评审用，不进游戏资源）
# ---------------------------------------------------------------------------
def load_font(name, size, weight=None):
    path = os.path.join(FONT_DIR, name)
    try:
        f = ImageFont.truetype(path, size)
        if weight is not None:
            try:
                f.set_variation_by_axes([weight])
            except Exception:
                pass
        return f
    except Exception:
        return ImageFont.load_default()


def cover(img, box_w, box_h):
    """等比覆盖裁切"""
    iw, ih = img.size
    scale = max(box_w / iw, box_h / ih)
    nw, nh = int(iw * scale + 0.5), int(ih * scale + 0.5)
    r = img.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - box_w) // 2, (nh - box_h) // 2
    return r.crop((left, top, left + box_w, top + box_h))


def text_center(d, xy, text, font, color, anchor="mm"):
    d.text(xy, text, font=font, fill=rgba(color), anchor=anchor)


def gen_baseline(plate, edge, cost, badge):
    K = 2  # 合成图按 2x 资源尺寸
    im = Image.new("RGBA", (W * K, H * K), rgba(FRAME))
    # 插画区
    art_path = os.path.join(CARD_DIR, "card_arrow_illustration_v2.png")
    art = Image.open(art_path).convert("RGBA")
    ax, ay, aw, ah = 8 * K, 8 * K, 194 * K, 220 * K
    im.paste(cover(art, aw, ah), (ax, ay))
    # 框 / 边线（常态用钢灰，示意稀有度染色）
    im.alpha_composite(plate)
    e = edge.copy()
    e.putalpha(Image.eval(e.getchannel("A"), lambda v: int(v * 0.55)))
    tint = Image.new("RGBA", e.size, rgba(STEEL))
    tint.putalpha(e.getchannel("A"))
    im.alpha_composite(tint)
    im.alpha_composite(gen_pack_badge("core"), (round(80.5 * K), 217 * K))
    # 费用胶囊 + 数字
    im.alpha_composite(cost, (146 * K, 4 * K))
    # 类型徽章（加长横线版：194 宽，从面板左边到右边）
    im.alpha_composite(badge, (8 * K, 270 * K))

    d = ImageDraw.Draw(im)
    # 卡名 28、类型与摘要 14、费用 19，和实机卡面一致。
    f_title = load_font("NotoSansSC.ttf", 28 * K, 900)
    f_type = load_font("NotoSansSC.ttf", 14 * K, 700)
    f_desc = load_font("NotoSansSC.ttf", 14 * K, 500)
    f_num = load_font("JetBrainsMono.ttf", 19 * K, 700)
    f_small = load_font("JetBrainsMono.ttf", 16 * K, 700)
    text_center(d, (105 * K, 250 * K), "箭塔", f_title, BLACK)
    text_center(d, (105 * K, 279 * K), "建筑 · 泛用", f_type, CREAM)
    # 实机文案取 card_text.describe(nm) 前两行；Arrow = 「单体，无附加／伤害…」
    text_center(d, (105 * K, 302 * K), "单体，无附加", f_desc, BLACK)
    text_center(d, (105 * K, 322 * K), "伤害 12 · 攻速 80%", f_desc, BLACK)
    text_center(d, (round(187.5 * K), round(16.5 * K)), "12", f_num, CREAM)
    # v3.1：卡面已无编号 01（快捷购买移除），基准图同步去掉
    return im


def gen_thumbs(baseline):
    a = baseline.resize((max(1, baseline.width // 10), max(1, baseline.height // 10)), Image.LANCZOS)
    b = baseline.resize((max(1, baseline.width // 4), max(1, baseline.height // 4)), Image.LANCZOS)
    pad, label_h = 16, 28
    cw = a.width + b.width + baseline.width + pad * 4
    ch = baseline.height + label_h + pad * 2
    out = Image.new("RGB", (cw, ch), rgba(FRAME)[:3])
    d = ImageDraw.Draw(out)
    f = load_font("NotoSansSC.ttf", 15, 700)
    x = pad
    for img, label in ((a, "10%"), (b, "25%"), (baseline, "100% / 210x340 @2x")):
        if img.mode == "RGBA":
            out.paste(img, (x, label_h + pad), img)
        else:
            out.paste(img, (x, label_h + pad))
        d.text((x, pad), label, font=f, fill=rgba(CREAM)[:3])
        x += img.width + pad
    return out


def main():
    for directory in (UI_DIR, REVIEW_DIR):
        os.makedirs(directory, exist_ok=True)
    for name in ("NotoSansSC.ttf", "JetBrainsMono.ttf"):
        if not os.path.exists(os.path.join(FONT_DIR, name)):
            print("WARN: missing font", name)

    plate = gen_plate()
    edges = {bw: gen_edge(bw) for bw in (1, 2, 3)}
    cost = gen_cost()
    badge = gen_badge()
    outputs = [
        (os.path.join(UI_DIR, "ui_card_plate_v3.png"), plate),
        (os.path.join(UI_DIR, "ui_card_cost_v3.png"), cost),
        (os.path.join(UI_DIR, "ui_card_badge_v3.png"), badge),
    ]
    for bw, img in edges.items():
        outputs.append((os.path.join(UI_DIR, "ui_card_edge_v3_%d.png" % bw), img))
    for pack_id in PACK_BADGE_COLORS:
        outputs.append((os.path.join(UI_DIR, f"ui_card_pack_{pack_id}.png"), gen_pack_badge(pack_id)))
    for path, img in outputs:
        img.save(path, "PNG")
        print("WROTE", os.path.relpath(path, ROOT), img.size)

    baseline = gen_baseline(plate, edges[2], cost, badge)
    bp = os.path.join(REVIEW_DIR, "card-redesign-baseline-v3.png")
    baseline.save(bp, "PNG")
    print("WROTE", os.path.relpath(bp, ROOT), baseline.size)
    tp = os.path.join(REVIEW_DIR, "card-redesign-thumbs-v3.png")
    gen_thumbs(baseline).save(tp, "PNG")
    print("WROTE", os.path.relpath(tp, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
