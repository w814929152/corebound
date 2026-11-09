# -*- coding: utf-8 -*-
"""
gen_ui_plate_pack_v1.py —— 资产包 v6：商店商品位 9-slice 承托板（1 件）

设计依据：design/art/asset-pack-v6-ui-plate.md · art-bible §2.2 / §5.1 / §5.5
问题：shop_overlay.gd 的商品位只有 card_blueprint() 的 StyleBoxFlat 底 + 四角 L 刻线，
      三位并排时卡缝直接透出抽屉底；v2-hud §7 #2 明确列为遗留。
方案：加一张**中性** 9-slice 承托板，垫在文字/插画之下、card_blueprint 描边之内。
      🔴 三条约束：
        ① 不染色 —— 稀有度边框 / 可购性 accent 由 card_blueprint + chrome 承担，
           承托板一旦带色就会和 5 级稀有度串色；
        ② 不做四角刻线 —— chrome 已画四角 L，重复会叠成脏角；
        ③ 只在 9-slice 的 corner 之间画水平亮线 —— middle 区水平拉伸后仍是 1px 线，
           但任何「铺满中心」的横向纹理会被垂直拉伸成粗条，一律禁止。

色值：底 #242B3E（比 card_blueprint 的 #1E2332 亮一档，形成内衬层次），
      描边 #3A455C，顶亮线 #6B7A94，底暗线 #101522，左右内阴影 #171C2B。

产物（art/2d/ui/）：
    ui_shop_slot_plate_v1.png  48x48  中性 9-slice 承托（corner 12）

用法：py -3.9 tools/gen_ui_plate_pack_v1.py
"""

import json
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "2d", "ui")
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "manifest.json")
S = 4


def hx(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def P(x, y):
    """1x 逻辑坐标 -> 超采样坐标（全文件唯一的坐标放大入口）。"""
    return (int(x * S), int(y * S))


def canvas(w, h):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, w, h, rel):
    img = img.resize((w, h), Image.LANCZOS)
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("  +", rel, "%dx%d" % (w, h))
    return rel


def gen_slot_plate():
    w = 48
    img, d = canvas(w, w)
    box = [P(0, 0), P(w - 1, w - 1)]
    # 圆角底 + 1px 外描边（圆角落在 9-slice corner=12 内，拉伸不变形）
    d.rounded_rectangle(box, radius=4 * S, fill=hx("#242B3E"))
    d.rounded_rectangle(box, radius=4 * S, outline=hx("#4C5A76"), width=S)
    # 顶部 2px 亮线：只画 corner 之间的 middle 区，水平拉伸后仍是线。
    # 🔴 必须够亮 —— 4× LANCZOS 会把 1px 细线混进底色（首版 #6B7A94/150 实测不可见）。
    d.rectangle([P(12, 2), P(35, 3)], fill=hx("#9FB0CC", 205))
    # 底部 2px 暗线（收边，避免承托板下沿糊进抽屉底）
    d.rectangle([P(12, w - 4), P(35, w - 3)], fill=hx("#0B0F1A", 235))
    # 左右 1px 内阴影（竖直 middle 区，垂直拉伸后仍是线）
    d.rectangle([P(1, 12), P(1, 35)], fill=hx("#1A2030", 220))
    d.rectangle([P(w - 2, 12), P(w - 2, 35)], fill=hx("#1A2030", 220))
    return save(img, w, w, "ui_shop_slot_plate_v1.png")


def register(entries):
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    names = {e["file"] for e in entries}
    m["assets"] = [a for a in m["assets"] if a["file"] not in names]
    m["assets"].extend(entries)
    m["assets"].sort(key=lambda a: a["file"])
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=1)
    print("  manifest ->", len(m["assets"]), "assets")


def main():
    print("[gen_ui_plate_pack_v1] 界面承托板 · 1 件")
    done = [gen_slot_plate()]
    register([{"file": "ui/" + done[0], "size": [48, 48]}])
    print("[done] 1 asset -> art/2d/ui/")


if __name__ == "__main__":
    main()
