# -*- coding: utf-8 -*-
"""批次⑪ true 湮灭包（警报红 #FF2E4E）复核样张 + 导入元数据生成器。

从 raw_*.png / 正式 _460.png 幂等重建：
  接触表（原图 / 64px / 卡框）、水印区放大复核、7 包色板并排、
  8 包进度、rime↔hex 近色对并排、试点四档对比，并补齐 20 个 .import。
"""
import hashlib
import json
import os
import random
import string
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
CARDS = os.path.join(ROOT, "art", "2d", "cards")
FONT = os.path.join(ROOT, "assets", "fonts", "NotoSansSC.ttf")
PY = sys.executable
BG = (11, 13, 22)
FG = (206, 213, 224)
PAD = 12

NAMES = ["Eraser", "Exile", "Necro", "Null", "Obliterator",
         "Oblivion", "Rift", "Soulpiercer", "Void", "Wraith"]

PACKS = [
    ("core", "#9AA5B1", "Cannon"),
    ("cinder", "#FF6B3D", "Vanguard"),
    ("rime", "#3ED0E8", "Glacier"),
    ("pierce", "#FFC94A", "Martyr"),
    ("arc", "#7A5CFF", "Thunder"),
    ("sunder", "#E8437F", "Sunder"),
    ("hex", "#1A6B7D", "Hex"),
    ("true", "#FF2E4E", "Oblivion"),
]


def ft(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return None


def rgb(hexs):
    return tuple(int(hexs[i:i + 2], 16) for i in (1, 3, 5))


def art(name):
    return Image.open(os.path.join(CARDS, "card_%s_v1_460.png" % name.lower())).convert("RGBA")


def raw(name):
    return Image.open(os.path.join(HERE, "raw_%s.png" % name)).convert("RGB")


def paste(canvas, im, x, y):
    """把 RGBA 贴到 RGB 画布（深色底）。"""
    if im.mode == "RGBA":
        base = Image.new("RGBA", im.size, BG + (255,))
        base.alpha_composite(im)
        im = base.convert("RGB")
    canvas.paste(im, (x, y))


def grid(out, items, cell, cols, label_h=26, label_size=15, head=None):
    """items = [(label, PIL.Image), ...]；cell 为正方形格边长。"""
    rows = (len(items) + cols - 1) // cols
    head_h = 30 if head else 0
    W = cols * cell + (cols + 1) * PAD
    H = head_h + rows * (cell + label_h) + (rows + 1) * PAD
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    f = ft(label_size)
    fh = ft(17)
    if head:
        d.text((PAD, 6), head, font=fh, fill=FG)
    for i, (label, im) in enumerate(items):
        r, c = divmod(i, cols)
        x = PAD + c * (cell + PAD)
        y = head_h + PAD + r * (cell + label_h + PAD)
        thumb = im.resize((cell, cell), Image.LANCZOS)
        paste(sheet, thumb, x, y)
        d.text((x + 2, y + cell + 4), label, font=f, fill=FG)
    sheet.save(out)
    print("saved", os.path.relpath(out, ROOT), sheet.size)


def contact_raw():
    grid(os.path.join(HERE, "contact_batch11_raw.png"),
         [(n, raw(n)) for n in NAMES], 300, 5, 26, 15,
         "batch11 / true 湮灭包 · 原图 10 张（alert red #FF2E4E）")


def contact_64():
    grid(os.path.join(HERE, "contact_batch11_64.png"),
         [(n, art(n)) for n in NAMES], 64, 10, 22, 9,
         "64px 可读性复核 · 10 张")


def contact_cards():
    items = []
    for n in NAMES:
        p = os.path.join(HERE, "mock_%s.png" % n.lower())
        subprocess.run([PY, os.path.join(ROOT, "tools", "card_mock_card.py"),
                        "--card", os.path.join(CARDS, "card_%s_v1_460.png" % n.lower()),
                        "--out", p, "--label", n],
                       cwd=ROOT, check=True, capture_output=True)
        items.append((n, Image.open(p).convert("RGB")))
    # 卡框是 512x716 竖版，单独走竖版拼图
    cols, cw = 5, 220
    ch = int(cw * 716 / 512)
    label_h = 24
    rows = (len(items) + cols - 1) // cols
    W = cols * cw + (cols + 1) * PAD
    H = 34 + rows * (ch + label_h) + (rows + 1) * PAD
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 6), "batch11 · 卡框合成复核（10 张）", font=ft(17), fill=FG)
    for i, (label, im) in enumerate(items):
        r, c = divmod(i, cols)
        x = PAD + c * (cw + PAD)
        y = 34 + PAD + r * (ch + label_h + PAD)
        sheet.paste(im.resize((cw, ch), Image.LANCZOS), (x, y))
        d.text((x + 4, y + ch + 4), label, font=ft(14), fill=FG)
    out = os.path.join(HERE, "contact_batch11_cards.png")
    sheet.save(out)
    print("saved", os.path.relpath(out, ROOT), sheet.size)


def watermark_check():
    """右下水印检查区放大拼图 + 计数标注。"""
    cw, chh, cols = 276, 83, 5
    items = []
    for n in NAMES:
        im = art(n)
        w, h = im.size
        crop = im.crop((int(w * 0.7), int(h * 0.9), w, h))
        cnt = sum(1 for p in crop.getdata() if p[3] > 100)
        big = crop.resize((cw - 4, chh), Image.LANCZOS)
        items.append(("%s  %d px" % (n, cnt), big))
    W = cols * cw + (cols + 1) * PAD
    H = 34 + 2 * (chh + 26) + 3 * PAD
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 6), "水印区 x>=70%%, y>=90%% 放大复核（alpha>100 像素数）", font=ft(17), fill=FG)
    for i, (label, im) in enumerate(items):
        r, c = divmod(i, cols)
        x = PAD + c * (cw + PAD)
        y = 34 + PAD + r * (chh + 26 + PAD)
        paste(sheet, im, x, y)
        d.text((x + 2, y + chh + 4), label, font=ft(13), fill=FG)
    out = os.path.join(HERE, "watermark_check_batch11.png")
    sheet.save(out)
    print("saved", os.path.relpath(out, ROOT), sheet.size)


def compare_pack_color():
    items = []
    for pack, hexs, rep in PACKS:
        im = art(rep) if rep else Image.new("RGBA", (460, 460), (0, 0, 0, 0))
        # 顶部色条
        tile = Image.new("RGBA", (460, 460), BG + (255,))
        dd = ImageDraw.Draw(tile)
        dd.rectangle((0, 0, 459, 46), fill=rgb(hexs) + (255,))
        dd.text((10, 12), "%s  %s" % (pack, hexs), font=ft(22), fill=(12, 14, 24, 255))
        tile.alpha_composite(im.resize((420, 390), Image.LANCZOS), (20, 56))
        items.append((("%s / %s" % (pack, rep or "待出图")), tile))
    grid(os.path.join(HERE, "compare_pack_color_batch11.png"),
         items, 260, 4, 26, 13,
         "8 包色板并排 · 批次⑪ 全 8 包完成（alert red 为新增）")


def compare_progress():
    W, H = 900, 460
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    d.text((24, 18), "卡面资产进度 80 / 80（批次⑪ true 湮灭包落地 · 全部完成）", font=ft(24), fill=FG)
    for i, (pack, hexs, rep) in enumerate(PACKS):
        y = 74 + i * 44
        d.text((24, y + 4), pack, font=ft(17), fill=FG)
        d.text((150, y + 4), hexs, font=ft(15), fill=FG)
        for j in range(10):
            x = 260 + j * 40
            fill = rgb(hexs) if rep else (58, 62, 76)
            d.rectangle((x, y, x + 32, y + 28), fill=fill, outline=(80, 86, 100))
        d.text((680, y + 4), "10 / 10  ✓" if rep else "0 / 10  待出图", font=ft(15), fill=FG)
    d.text((24, 434), "core 中性基准族 / cinder 默认档 / rime·pierce bright-pack / arc mid-pack / sunder·hex·true lift-pack",
           font=ft(13), fill=FG)
    out = os.path.join(HERE, "compare_pack_progress_batch11.png")
    sheet.save(out)
    print("saved", os.path.relpath(out, ROOT), sheet.size)


def compare_nearhue():
    """sunder 噬品红 ↔ true 警报红 近色对并排复核。"""
    a = ["Sunder", "Drummer", "Crusher"]
    b = ["Oblivion", "Null", "Obliterator"]
    items = []
    for n in a:
        items.append(("sunder / " + n, art(n)))
    for n in b:
        items.append(("true / " + n, art(n)))
    grid(os.path.join(HERE, "compare_nearhue_batch11.png"),
         items, 240, 3, 26, 14,
         "近色对复核：sunder #E8437F（上排） vs true #FF2E4E（下排）")


def compare_tone():
    """Hex 试点四档并排；跑完恢复 --lift-pack 正式资产。"""
    flags = [("默认 155/26", [], "p50 72 / p85 109 / cov 82.0%  ✗"),
             ("bright 230/250", ["--bright-pack"], "p50 55 / p85 85 / cov 82.6%  ✗"),
             ("mid 145/42", ["--mid-pack"], "p50 89 / p85 117 / cov 81.5%  ✓"),
             ("lift 145/58", ["--lift-pack"], "p50 101 / p85 124 / cov 81.7%  ✓ 采用")]
    items = []
    for label, flag, _ in flags:
        cmd = [PY, os.path.join(ROOT, "tools", "card_batch3_process.py"),
               "--batch", "batch11", "Oblivion", "--dominant"] + flag
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit(r.stdout + r.stderr)
        items.append((label, art("Oblivion").copy()))
    # 恢复正式档（整包幂等重跑）
    subprocess.run([PY, os.path.join(ROOT, "tools", "card_batch3_process.py"),
                    "--batch", "batch11", "--dominant", "--lift-pack"],
                   cwd=ROOT, check=True, capture_output=True)
    W, H = 4 * 230 + 5 * PAD, 34 + 230 + 60 + 2 * PAD
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    d.text((PAD, 6), "Oblivion 试点 · 四档后处理对比（选取 lift-pack）", font=ft(17), fill=FG)
    for i, ((label, im), (_, _, stat)) in enumerate(zip(items, flags)):
        x = PAD + i * (230 + PAD)
        y = 34 + PAD
        paste(sheet, im.resize((230, 230), Image.LANCZOS), x, y)
        d.text((x + 2, y + 234), label, font=ft(14), fill=FG)
        d.text((x + 2, y + 252), stat, font=ft(11), fill=FG)
    out = os.path.join(HERE, "compare_tone_batch11.png")
    sheet.save(out)
    print("saved", os.path.relpath(out, ROOT), sheet.size)


IMPORT_TPL = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="{path}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{src}"
dest_files=["{path}"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def make_imports():
    """按 Godot 规则为 20 个新 PNG 补 .import：uid 唯一，path=md5(res:// 路径)。"""
    import glob
    existing = set()
    for p in glob.glob(os.path.join(CARDS, "*.import")):
        for line in open(p, encoding="utf-8"):
            if line.startswith("uid="):
                existing.add(line.strip().split('"')[1])
    rng = random.Random(20261111)
    made, uids = 0, set(existing)
    for n in NAMES:
        for suffix in ("_v1_t.png", "_v1_460.png"):
            fn = "card_%s%s" % (n.lower(), suffix)
            dst = os.path.join(CARDS, fn + ".import")
            if os.path.exists(dst):
                continue
            while True:
                uid = "uid://" + "".join(rng.choice(string.ascii_lowercase + string.digits)
                                         for _ in range(12))
                if uid not in uids:
                    uids.add(uid)
                    break
            res = "res://art/2d/cards/" + fn
            h = hashlib.md5(res.encode()).hexdigest()
            path = "res://.godot/imported/%s-%s.ctex" % (fn, h)
            with open(dst, "w", encoding="utf-8") as f:
                f.write(IMPORT_TPL.format(uid=uid, path=path, src=res))
            made += 1
    total = len(glob.glob(os.path.join(CARDS, "*.import")))
    print(".import 新增 %d 个，累计 %d 个，uid 唯一数 %d" % (made, total, len(uids)))
    return made, total


def main():
    contact_raw()
    contact_64()
    contact_cards()
    watermark_check()
    compare_pack_color()
    compare_progress()
    compare_nearhue()
    compare_tone()
    made, total = make_imports()
    print("== batch11 复核产物完成（新增 .import %d / 累计 %d）==" % (made, total))


if __name__ == "__main__":
    main()
