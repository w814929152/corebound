# -*- coding: utf-8 -*-
"""卡面插画批处理后处理（通用批次版 · 2026-11-09）。

文件名沿用 batch3，实际支持任意批次：自动扫描 art/_review/<batch>/raw_*.png，
逐张执行：
  1) card_tone_levels.py 同款保色相色阶拉伸（黑场 35 / 白场 155 / floor 26 / ceil 235）
  2) 擦除图像边框 6px（残留渐变会把 trim box 撑到全图）
  3) card_keyout.py --connectivity-only 抠图（描边色接近底色，颜色阈值法不可用）
  4) 指标自检：p50/p85 明度 + alpha p10 + **包色装甲板覆盖率**（§2.1 区分度检查）
  5) 落盘 art/2d/cards/card_{name}_v1_t.png / _460.png（文件名不变，Godot/manifest 免改）

用法：
  py -3.9 tools/card_batch3_process.py --batch batch5 --dominant  # v1.2 包色主色调批次
  py -3.9 tools/card_batch3_process.py --batch batch4             # v1.1 / 蓝钢灰族（默认口径）
  py -3.9 tools/card_batch3_process.py --batch batch5 Ember Blaze --dominant  # 指定若干张
  py -3.9 tools/card_batch3_process.py                           # 默认 batch3（向后兼容）
  py -3.9 tools/card_batch3_process.py --batch batch6 --dominant --bright-pack  # 亮色相包
  py -3.9 tools/card_batch3_process.py --batch batch8 --dominant --mid-pack     # 中明度包色
  py -3.9 tools/card_batch3_process.py --batch batch9 --dominant --lift-pack    # 暗板占比高的中明度包
  py -3.9 tools/card_batch3_process.py --batch batch10 --dominant --lift-pack   # v1.6 低明度深青（复用同档）
  py -3.9 tools/card_batch3_process.py --batch batch11 --dominant --lift-pack   # v1.7 真红收官（第三次复用，80/80）

--dominant 做三件事：色阶拉伸透传 --protect-mode remap（整机高饱和不再被当成小点缀
跳过重映射）、包色覆盖率门槛 2%→40%、p50 门槛 90-160→80-185（主色靠色相对比）。

--bright-pack（v1.3）：亮色相包（青 / 金等 L>155 的高明度主色）专用档位。
冻结白场 155 会把 L>=155 的像素全部顶到 ceil 235，加上 L>170 高饱和保护，
整张卡被额外提亮一档（批次⑥首跑 p50 167-198 / p85 至 227，5 张过检失败）。
该档改为 --white 230 --bright-threshold 250，只做温和映射、不再白场饱和，
实测 p50 113-165 / p85 165-205，覆盖率不变。不得逐张微调，整包统一使用。

--mid-pack（v1.4）：中明度包色（星紫 #7A5CFF 等 L≈90-140 的紫 / 品红 / 深青 / 红）专用档位。
这类主色不吃 --bright-pack（白场 230 反而把 p50 压到 61），但默认白场 155 又让
暗板占比高的卡 p50 跌破 80（批次⑧首跑 10 张里 4 张 71-75）。该档改为
--white 145 --floor 42：小幅压白场 + 抬暗部落点，抬亮暗板却不把高光顶到饱和，
实测整包 p50 87-151 / p85 ≤181 / cov 45.6-71.3%，描边仍保持深藏青。
与 --bright-pack 互斥，同样整包统一使用，不得逐张微调。

--lift-pack（v1.5）：中明度但暗板占比更高的包色（sunder 噬品红 #E8437F 等）专用档位。
批次⑨ 首跑 --mid-pack（145/42）仍有 4 张 p50 74-79 跌破 80；整包 10 张 x 6 组探测
发现关键不是压白场（压到 135-140 会把 Ruin 覆盖率压破 40%、p85 顶到 210-216），
而是继续抬 floor。该档改为 --white 145 --floor 58：白场与 mid-pack 一致，只把暗板
落点再抬 16，整包 p50 87-127 / p85 ≤197 / cov 41.6-69.5%，10 张全过检；
人工复核 floor 58 后深藏青描边依旧扎实、暗板层次未糊。批次⑩ 低明度深青 hex
（#1A6B7D, L≈91）四档试点 73 / 55 / 89 / 101，确认复用本档而非新增第五档，整包 10 张
p50 101-138 / cov 88.5-99.6% 全过检。批次⑪ 警报红 true（#FF2E4E, L≈93）四档试点
72 / 55 / 89 / 101，同样复用本档，整包 10 张 p50 88-108 / cov 64.3-81.7% 全过检；
至此 --lift-pack 共 30 张验证通过，8 包 80 张卡面全部完成。三档互斥，整包统一使用。
"""
import argparse
import colorsys
import json
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
CARDS_DIR = os.path.join(ROOT, "art", "2d", "cards")
BANK = os.path.join(ROOT, "design", "art", "card-prompt-bank-v2.json")
PY = sys.executable

# 中间产物 / 留档图不参与后处理
SKIP_SUFFIXES = ("_norm", "_lit", "_rejected", "_prepack")


def discover(batch_dir):
    """扫描 raw_*.png；prev_*.png 等留档图不以 raw_ 开头，天然排除。"""
    out = []
    if not os.path.isdir(batch_dir):
        return out
    for fn in sorted(os.listdir(batch_dir)):
        if not (fn.startswith("raw_") and fn.endswith(".png")):
            continue
        stem = fn[4:-4]
        if any(stem.endswith(s) for s in SKIP_SUFFIXES):
            continue
        out.append(stem)
    return out


def load_pack(name):
    """卡名 → (pack_id, 包色 hex)；包色真源 = card-prompt-bank-v2.json。"""
    if not os.path.exists(BANK):
        return None, None
    with open(BANK, encoding="utf-8") as f:
        d = json.load(f)
    c = d["cards"].get(name)
    if not c:
        return None, None
    return c["pack"], d["accent_by_pack"].get(c["pack"])


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


def pack_coverage(path, hex_color):
    """不透明像素中「色相接近包色且有一定饱和度」的占比（%）。

    用来自动发现「包色装甲板没画出来 / 只留了一处小点缀」的退化：
    §2.1 要求包色占机身约 20%，落到整卡不透明面积通常 >= 2%。
    色阶拉伸保色相，所以按 HSV 色相判定而非 RGB 距离。
    中性包色（钢灰等 S < 0.25）无法判色相，返回 None。
    """
    if not hex_color:
        return None
    target = tuple(int(hex_color[i:i + 2], 16) for i in (1, 3, 5))
    th, ts, _ = colorsys.rgb_to_hsv(*(v / 255.0 for v in target))
    if ts < 0.25:
        return None
    im = Image.open(path).convert("RGBA")
    px = im.load()
    w, h = im.size
    total = hit = 0
    for y in range(0, h, 3):
        for x in range(0, w, 3):
            r, g, b, a = px[x, y]
            if a < 200:
                continue
            total += 1
            hh, ss, _ = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if ss < 0.25:
                continue
            dh = min(abs(hh - th), 1.0 - abs(hh - th))
            if dh < 0.055:
                hit += 1
    return 100.0 * hit / total if total else None


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise SystemExit("步骤失败：%s" % " ".join(cmd))
    return r.stdout.strip()


def main():
    ap = argparse.ArgumentParser(description="卡面插画批处理后处理（校色→擦边→抠图→自检）")
    ap.add_argument("--batch", default="batch3", help="art/_review 下的批次目录名，默认 batch3")
    ap.add_argument("--dominant", action="store_true",
                    help="v1.2 包色主色调模式：色阶拉伸改用 remap（整机高饱和也要拉明度），"
                         "包色覆盖率门槛 40%%（旧版小点缀口径为 2%%）")
    ap.add_argument("--bright-pack", action="store_true",
                    help="v1.3 亮色相包档位（青/金等高明度主色）：--white 230 + "
                         "--bright-threshold 250，避免白场饱和把整卡顶到过曝；需与 --dominant 同用")
    ap.add_argument("--mid-pack", action="store_true",
                    help="v1.4 中明度包色档位（星紫等 L≈90-140）：--white 145 --floor 42，"
                         "抬暗板而不顶高光，避免默认档 p50 跌破 80；需与 --dominant 同用，"
                         "与另两档互斥")
    ap.add_argument("--lift-pack", action="store_true",
                    help="v1.5 高抬暗板档位（暗板占比高的中明度包，如 sunder 噬品红）："
                         "--white 145 --floor 58，整包统一；需与 --dominant 同用，与另两档互斥")
    ap.add_argument("names", nargs="*", help="指定卡名；缺省自动扫描该批次的 raw_*.png")
    args = ap.parse_args()
    if sum(bool(x) for x in (args.bright_pack, args.mid_pack, args.lift_pack)) > 1:
        ap.error("--bright-pack / --mid-pack / --lift-pack 三者互斥，一个批次只能用一个档位")

    batch_dir = os.path.join(ROOT, "art", "_review", args.batch)
    os.makedirs(batch_dir, exist_ok=True)
    names = args.names or discover(batch_dir)
    print("== card_batch3_process · batch=%s · %d 张 ==" % (args.batch, len(names)))
    for name in names:
        raw = os.path.join(batch_dir, "raw_%s.png" % name)
        norm = os.path.join(batch_dir, "raw_%s_norm.png" % name)
        if not os.path.exists(raw):
            print("!! 缺原图：", raw)
            continue
        # 1) 色阶拉伸（幂等：每次从 raw 重算）
        white = "230" if args.bright_pack else ("145" if (args.mid_pack or args.lift_pack) else "155")
        floor = "58" if args.lift_pack else ("42" if args.mid_pack else "26")
        tone_cmd = [PY, os.path.join(HERE, "card_tone_levels.py"), "--src", raw, "--out", norm,
                    "--black", "35", "--white", white, "--floor", floor, "--ceil", "235"]
        if args.dominant:
            tone_cmd += ["--protect-mode", "remap"]
            if args.bright_pack:
                tone_cmd += ["--bright-threshold", "250"]
        run(tone_cmd)
        # 2) 擦边
        wipe_border(norm)
        # 3) 抠图 → 正式资产
        out_base = os.path.join(CARDS_DIR, "card_%s_v1.png" % name.lower())
        info = run([PY, os.path.join(HERE, "card_keyout.py"), "--src", norm, "--out", out_base,
                    "--connectivity-only"])
        # 4) 自检
        out_460 = os.path.join(CARDS_DIR, "card_%s_v1_460.png" % name.lower())
        m = measure(out_460)
        pack_id, hex_color = load_pack(name)
        cov = pack_coverage(out_460, hex_color)
        if m:
            p50, p85, a50, a10 = m
            warn = []
            # 蓝钢灰族靠明度拉开与深底的距离，基准 90–160；
            # 包色主色调靠色相提供对比，明度分布天然更宽（实测 83–175 观感均达标）。
            p50_lo, p50_hi = (80.0, 185.0) if args.dominant else (90.0, 160.0)
            if not (p50_lo <= p50 <= p50_hi):
                warn.append("p50 偏离")
            if p85 > 215:
                warn.append("p85 过曝")
            if a10 < 250:
                warn.append("alpha 不足")
            cov_min = 40.0 if args.dominant else 2.0
            if cov is not None and cov < cov_min:
                warn.append("包色主色调不足" if args.dominant else "包色面板偏少")
            tag = (" ⚠ " + "、".join(warn)) if warn else " ✓"
            if cov is None:
                cov_s = "pack=%s 中性色免检" % (pack_id or "?")
            else:
                cov_s = "pack=%s cov=%.1f%%" % (pack_id or "?", cov)
            print("%-9s p50=%.0f p85=%.0f a10=%d %s%s | %s"
                  % (name, p50, p85, a10, cov_s, tag, info))
        else:
            print("%-9s 量测失败（无不透明像素）" % name)
    print("== 完成 ==")


if __name__ == "__main__":
    main()
