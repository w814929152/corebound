# -*- coding: utf-8 -*-
"""卡面插画批处理后处理（2026-11-08 · 3/4 扁平蓝图风批次）。

对 art/_review/batch3/ 下的 raw_{Name}.png 逐张执行：
  1) card_tone_levels.py 同款保色相色阶拉伸（黑场 35 / 白场 155 / floor 26 / ceil 235）
  2) 擦除图像边框 6px（残留渐变会把 trim box 撑到全图）
  3) card_keyout.py --connectivity-only 抠图（描边色接近底色，颜色阈值法不可用）
  4) 指标自检：p50/p85 明度（基准 96–149 / 180±30）+ alpha p10（应 255）
  5) 落盘 art/2d/cards/card_{name}_v1_t.png / _460.png（文件名不变，Godot/manifest 免改）

用法：
  py -3.9 tools/card_batch3_process.py            # 全部 9 张
  py -3.9 tools/card_batch3_process.py Arrow Frost # 指定若干张
"""
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
BATCH = os.path.join(ROOT, "art", "_review", "batch3")
CARDS_DIR = os.path.join(ROOT, "art", "2d", "cards")
PY = sys.executable

# 泛用包其余 9 张（Cannon 已定稿，不在此列）
ALL = ["Foundry", "Arrow", "Frost", "Scout", "Kinetic", "Ranger", "Sentry", "Catapult", "Harrier"]


def wipe_border(path, n=6):
    im = Image.open(path).convert("RGB")
    px = im.load()
    w, h = im.size
    bg = px[2, 2]
    for y in range(h):
        for x in range(w):
            if x < n or y < n or x >= w - n or y >= h - n:
                px[x, y] = bg
    im.save(path)


def measure(path):
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size
    vals, alphas = [], []
    for y in range(0, h, 3):
        for x in range(0, w, 3):
            r, g, b, a = px[x, y]
            if a > 0:
                alphas.append(a)
            if a > 200:
                vals.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
    vals.sort()
    alphas.sort()
    if not vals:
        return None
    return (
        vals[len(vals) // 2],
        vals[int(len(vals) * 0.85)],
        alphas[len(alphas) // 2],
        alphas[int(len(alphas) * 0.1)],
    )


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise SystemExit("步骤失败：%s" % " ".join(cmd))
    return r.stdout.strip()


def main():
    names = sys.argv[1:] or ALL
    os.makedirs(BATCH, exist_ok=True)
    print("== card_batch3_process · %d 张 ==" % len(names))
    for name in names:
        raw = os.path.join(BATCH, "raw_%s.png" % name)
        norm = os.path.join(BATCH, "raw_%s_norm.png" % name)
        if not os.path.exists(raw):
            print("!! 缺原图：", raw)
            continue
        # 1) 色阶拉伸（幂等：每次从 raw 重算）
        run([PY, os.path.join(HERE, "card_tone_levels.py"), "--src", raw, "--out", norm,
             "--black", "35", "--white", "155", "--floor", "26", "--ceil", "235"])
        # 2) 擦边
        wipe_border(norm)
        # 3) 抠图 → 正式资产
        out_base = os.path.join(CARDS_DIR, "card_%s_v1.png" % name.lower())
        info = run([PY, os.path.join(HERE, "card_keyout.py"), "--src", norm, "--out", out_base,
                    "--connectivity-only"])
        # 4) 自检
        m = measure(os.path.join(CARDS_DIR, "card_%s_v1_460.png" % name.lower()))
        tag = ""
        if m:
            p50, p85, a50, a10 = m
            warn = []
            if not (90 <= p50 <= 160):
                warn.append("p50 偏离")
            if p85 > 215:
                warn.append("p85 过曝")
            if a10 < 250:
                warn.append("alpha 不足")
            tag = (" ⚠ " + "、".join(warn)) if warn else " ✓"
            print("%-9s p50=%.0f p85=%.0f a10=%d%s | %s"
                  % (name, p50, p85, a10, tag, info))
        else:
            print("%-9s 量测失败（无不透明像素）" % name)
    print("== 完成 ==")


if __name__ == "__main__":
    main()
