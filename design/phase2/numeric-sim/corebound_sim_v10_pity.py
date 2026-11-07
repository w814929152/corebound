# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.10：P-1 pity 覆盖率改造（唯一变量）**

================================================================================
回答一个问题
================================================================================
v0.9 证明了一号风险不是新卡，是**卡池稀释**：7 张 → 10 张（+3 张零效果白板），
A 起飞率 0.693 → 0.613（−8.0pp）、B 0.910 → 0.800（−11.0pp）。
机制：`pity` 只保证「≥1 张主塔同 Tag 卡」，另外两个商品位可以是死牌。

本脚本只验证一件事：**P-1（保底 2 个「有用」商品位）能不能把这段损失补回来。**

================================================================================
为什么这一版可以只改抽卡
================================================================================
v0.9 的 Charge / Relay 已被判负，v0.10 **不启用任何新卡**，只把 v0.9 的
`compute_dps_v9` 原样沿用（开关全关时 v0.9 已自检与 v0.8 逐位一致）。
于是"引擎"与"抽卡"解耦，P-1 的效果不会被卡效能污染 —— 这是唯一变量原则。

================================================================================
P-1 的确切定义（写死，避免跑完再解释）
================================================================================
**P-1 = 每波的商品位中，至少 2 个必须是「非死牌」。**
· 死牌 = 进了商店但 AI 永远不会买的卡（本脚本用 `_pad*` 空牌代表）。
· 只补「数量」，不改「权重」、不改「同 Tag」判定、不动 `rng.choices` 的主抽。
· 挤占顺序：先挤死牌；若没有死牌可挤（len(s) < k），直接补位而不挤。
· 🔴 **当卡池里不含死牌时，P-1 必然不改变任何一次抽取** —— 这一点由
  `pity2` 开关 + `base7` 对照格双向验证：`base7` 必须逐位等于 v0.8 金标本。

================================================================================
实验格（2×2 因子 + 压力档）
================================================================================
  因子 1：卡池规模    7 张原池 / 10 张（+3 死牌）/ 12 张（+5 死牌）
  因子 2：P-1         off / on

  base7      pad=0 pity2=off   ← 金标本锚点，必须 = v0.8（0.693 / 0.910）
  base7p1    pad=0 pity2=on    ← P-1 对原池的影响（理论上应≈0，实测见分晓）
  pad10      pad=3 pity2=off   ← 复现 v0.9 的稀释成本
  pad10p1    pad=3 pity2=on    ← 核心格：P-1 能否抵消稀释
  pad12      pad=5 pity2=off   ← 压力：+5 死牌
  pad12p1    pad=5 pity2=on    ← 压力格：P-1 的失效边界在哪

================================================================================
附加：门单调性定理的数值核对（gate_census）
================================================================================
v0.9 的 F1（Charge 触发恒真）不是"K 没调好"，而是结构问题。本脚本用真实
`n(w)` 序列核对一遍：**怪物数是单调递增的，所以任何"绝对量"门槛都只能产生
一次性开关，不可能产生周期性触发。** 这条决定了 C-1 该怎么重设计。

================================================================================
不做的事
================================================================================
★ 不改 v03–v09 任何原文件。
★ 不启用 Charge / Relay / Overdraft / Brittle。
★ 不改任何定稿数值。

用法：
  python corebound_sim_v10_pity.py det        # 决定性 6 格（秒级）
  python corebound_sim_v10_pity.py mc 300     # 蒙特卡洛（~2.5 分钟）
  python corebound_sim_v10_pity.py census     # 门单调性核对（秒级）
  python corebound_sim_v10_pity.py all
"""
from __future__ import annotations

import os
import sys
import time
import random
import statistics

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6
import corebound_sim_v07_mapA as v7          # noqa: F401  （链式打补丁）
import corebound_sim_v08_salvage as v8
import corebound_sim_v09_trigger as v9

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 0. 抽卡统计（只用于诊断，不参与决策）
# =============================================================================
DRAW_STAT = dict(shops=0, pads=0, boosted=0)

PITY_MIN_USEFUL = 2          # P-1 保底的有用商品位数
_PAD_PREFIX = "_pad"


def _reset_draw_stat():
    DRAW_STAT["shops"] = 0
    DRAW_STAT["pads"] = 0
    DRAW_STAT["boosted"] = 0


def _is_pad(name):
    return name.startswith(_PAD_PREFIX)


# =============================================================================
# 1. 抽卡：v0.9 原样 + P-1 保底
# =============================================================================
def draw_offers_v10(rng, cfg, k=3, force=None):
    """🔴 卡名顺序 = `WEIGHTS` 的插入序（RNG 契约，见 v0.9 §1.1）。
    `pity2 = False` 时代码路径与 v0.9 **逐条相同**，保证 base7 锚点不漂。"""
    w = v9.pool_weights(cfg)
    names = list(w)                            # 不用 sorted：保序
    s = set(rng.choices(names, weights=[w[n] for n in names], k=k))
    if force:
        s.add(force)
        while len(s) > k:
            s.discard(rng.choice(sorted(s - {force})))

    if cfg.get("v10_pity2"):
        n_useful = sum(1 for n in s if not _is_pad(n))
        if n_useful < PITY_MIN_USEFUL:
            DRAW_STAT["boosted"] += 1
            useful = [n for n in names if not _is_pad(n)]
            guard = 0
            while n_useful < PITY_MIN_USEFUL and guard < 8:
                guard += 1
                cand = [n for n in useful if n not in s]
                if not cand:
                    break
                pick = rng.choices(cand, weights=[w[n] for n in cand], k=1)[0]
                pads = [n for n in s if _is_pad(n)]
                if pads:
                    s.discard(pads[0])             # 优先挤死牌
                elif len(s) >= k:
                    pool = sorted(s - {force}) if force else sorted(s)
                    if not pool:
                        break
                    s.discard(rng.choice(pool))    # 没死牌可挤 → 挤一张真卡（保位数）
                s.add(pick)
                n_useful = sum(1 for n in s if not _is_pad(n))

    DRAW_STAT["shops"] += 1
    DRAW_STAT["pads"] += sum(1 for n in s if _is_pad(n))
    return s


v9.draw_offers_v9 = draw_offers_v10           # shop_phase_v9 按模块全局名解析 → 生效


# =============================================================================
# 2. 自检：P-1 关闭时必须与 v0.9 抽卡逐位相同
# =============================================================================
def selfcheck_draw(trials=400):
    """同一 seed 下，v10(pity2=off) 的抽取序列必须与 v0.9 的原始实现完全相同，
    否则 base7 锚点（0.693 / 0.910）就不再可比。"""
    worst = 0
    for path in ("A", "B"):
        cfg9 = v9.make_cfg(path, dict(v9_charge=False, v9_relay=False, v9_pad=3))
        cfg10 = dict(cfg9)
        cfg10["v10_pity2"] = False
        r1, r2 = random.Random(7), random.Random(7)
        for _ in range(trials):
            a = _orig_draw(r1, cfg9, 3)
            b = draw_offers_v10(r2, cfg10, 3)
            if a != b:
                worst += 1
    return worst


def _orig_draw(rng, cfg, k=3, force=None):
    """v0.9 的原始抽卡（拷贝一份，用于自检对照）。"""
    w = v9.pool_weights(cfg)
    names = list(w)
    s = set(rng.choices(names, weights=[w[n] for n in names], k=k))
    if force:
        s.add(force)
        while len(s) > k:
            s.discard(rng.choice(sorted(s - {force})))
    return s


# =============================================================================
# 3. 实验格
# =============================================================================
CELLS = [
    ("base7",   dict(v9_charge=False, v9_relay=False, v9_pad=0, v10_pity2=False)),
    ("base7p1", dict(v9_charge=False, v9_relay=False, v9_pad=0, v10_pity2=True)),
    ("pad10",   dict(v9_charge=False, v9_relay=False, v9_pad=3, v10_pity2=False)),
    ("pad10p1", dict(v9_charge=False, v9_relay=False, v9_pad=3, v10_pity2=True)),
    ("pad12",   dict(v9_charge=False, v9_relay=False, v9_pad=5, v10_pity2=False)),
    ("pad12p1", dict(v9_charge=False, v9_relay=False, v9_pad=5, v10_pity2=True)),
]


def make_cfg(path, cell_kw, **over):
    c = v8.cfg_of(path)
    for k, v in cell_kw.items():
        c[k] = v
    c.update(over)
    return c


def eval_cell(name, kw, runs_mc=0, seed=v8.SEED1):
    out = dict(cell=name, kw=dict(kw))
    sts = {}
    for path in ("A", "B"):
        _reset_draw_stat()
        rows, player, st = v9.run_v9(path, make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        s = v6.summarize(rows)
        sts[path] = dict(rows=rows, s=s, player=player, st=st,
                         shop_stat=dict(DRAW_STAT))
    sA, sB = sts["A"]["s"], sts["B"]["s"]
    w20A, w20B = sA["w20"] or 0.0, sB["w20"] or 0.0
    _, lead, flips, _, _ = v6.cross_lead(sts["A"]["rows"], sts["B"]["rows"])
    out.update(toA=sA["takeoff"], toB=sB["takeoff"], w20A=round(w20A, 2),
               w20B=round(w20B, 2), ba=round(w20B / w20A, 3) if w20A else 0.0,
               hpA=sA["core_hp"], hpB=sB["core_hp"], flips=flips, st=sts)

    if runs_mc:
        mc = {}
        for path in ("A", "B"):
            rng = random.Random(seed)
            cfg = make_cfg(path, kw)
            cfg["max_actions"] = cfg.get("max_actions") or 12
            _reset_draw_stat()
            ok = hits = 0
            tos = []
            pads_per_shop = []
            for _ in range(runs_mc):
                before = DRAW_STAT["shops"]
                rows, player, st = v9.run_v9(path, cfg, 20, geo=sv.GEO6, rng=rng)
                alive = bool(rows) and rows[-1]["core_hp"] > 0
                tw = sv.takeoff_wave(rows)
                if alive:
                    ok += 1
                    if tw is not None:
                        hits += 1
                        tos.append(tw)
            shops = max(1, DRAW_STAT["shops"])
            pads_per_shop.append(DRAW_STAT["pads"] / shops)
            mc[path] = dict(rate=round(hits / runs_mc, 3), surv=round(ok / runs_mc, 3),
                            med=statistics.median(tos) if tos else None,
                            pads_per_shop=round(DRAW_STAT["pads"] / shops, 3),
                            boost_rate=round(DRAW_STAT["boosted"] / shops, 3))
        out["mc"] = mc
    return out


# =============================================================================
# 4. 门单调性核对
# =============================================================================
def gate_census():
    """在锚点路径上取真实 n(w)，核对「绝对门槛只能一次性开启」。

    结论若成立，则 F1 不是参数问题：`n(w) = 8 + 1.6w` 单调递增，
    `kill_share × n(w)` 也单调递增（share ≈ 1），于是任何 `≥ K` 的门
    只会在某一波永久打开 —— 也就是"从某波起恒真"，不存在周期性触发。
    """
    print("=" * 100)
    print("门单调性核对：绝对门槛 vs 相对门槛（锚点 base7，A/B 两条路径）")
    print("=" * 100)
    data = {}
    for path in ("A", "B"):
        kw = dict(v9_charge=False, v9_relay=False, v9_pad=0, v10_pity2=False)
        rows, player, _ = v9.run_v9(path, make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        data[path] = rows

    rows = data["A"]
    print("\n[A · 单核] 逐波怪物数与「门槛开启波」（假设主塔击杀份额 = rows 推算值）")
    print("| 波 | n(w) | 阈值 K=8 开启? | K=16 | K=24 | K=32 |")
    print("|----|------|----------------|------|------|------|")
    for r in rows:
        n = r["n"]
        cells = []
        for K in (8, 16, 24, 32):
            cells.append("✅" if n * 0.97 >= K else "❌")
        print(f"| {r['w']:>2} | {n:>4} | {cells[0]:>14} | {cells[1]:>4} | {cells[2]:>4} | {cells[3]:>4} |")

    print("\n[B · 多塔] 同上（B 的塔多，主塔份额低 → 门槛更难满足，但仍是单调的）")
    for r in data["B"][:6]:
        print(f"   W{r['w']:>2}  n={r['n']:>3}  towers={r['towers']}")

    print()
    print("定理核对：")
    print("  n(w) 单调递增 → 0.97·n(w) 单调递增 → {w : 0.97·n(w) ≥ K} 是一个后缀区间 [w_K, 20]。")
    print("  也就是说：**任何绝对门槛都只有一次「开」，之后永久为真**，不可能周期性触发。")
    print("  要周期性触发，门必须是相对量（占比 / 排名 / 比率）—— 而单塔流里占比恒 ≈ 1。")
    print("  ⇒ 这就是 F1 的结构性根因，也是 C-1 不能再走「条件触发」的原因。")


# =============================================================================
# 5. 输出
# =============================================================================
HDR = ("| 实验格    | toA  | toB  |   W20-A  |   W20-B  |  B/A   | A率   | B率   |\n"
       "|-----------|------|------|----------|----------|--------|-------|-------|")


def fmt_row(r):
    def n(v):
        return "—" if v is None else str(v)
    mc = r.get("mc") or {}
    a, b = mc.get("A", {}), mc.get("B", {})
    return (f"| {r['cell']:<9} | {n(r['toA']):>4} | {n(r['toB']):>4} | "
            f"{r['w20A']:>8.2f} | {r['w20B']:>8.2f} | {r['ba']:>6.3f} | "
            f"{n(a.get('rate')):>6} | {n(b.get('rate')):>6} |")


def run_det():
    print("=" * 100)
    print("v0.10 决定性对照（rng=None，理性 AI，GEO6，20 波）")
    print("=" * 100)
    rows = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw)
        rows.append(r)
        sa = r["st"]["A"]["shop_stat"]
        print(f"[{name}] {time.time()-t0:.1f}s  店数={sa['shops']} "
              f"死牌/店={sa['pads']/max(1,sa['shops']):.2f} 补位率={sa['boosted']/max(1,sa['shops']):.3f}")
    print()
    print(HDR)
    for r in rows:
        print(fmt_row(r))
    print()
    base = next(r for r in rows if r["cell"] == "base7")
    print("相对 base7 的偏移：")
    for r in rows:
        if r["cell"] == "base7":
            continue
        dA = (r["toA"] - base["toA"]) if (r["toA"] and base["toA"]) else None
        dB = (r["toB"] - base["toB"]) if (r["toB"] and base["toB"]) else None
        print(f"  {r['cell']:<9} toA {dA if dA is None else format(dA,'+d')}"
              f"  toB {dB if dB is None else format(dB,'+d')}"
              f"  W20A {'+' if r['w20A']>=base['w20A'] else ''}{r['w20A']-base['w20A']:.2f}"
              f"  B/A {r['ba']-base['ba']:+.3f}")
    return rows


def run_mc(runs=300):
    print("=" * 100)
    print(f"v0.10 蒙特卡洛（{runs} 局/路径，seed={v8.SEED1}）")
    print("=" * 100)
    rows = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw, runs_mc=runs)
        rows.append(r)
        a, b = r["mc"]["A"], r["mc"]["B"]
        print(f"[{name}] {time.time()-t0:.1f}s  A率 {a['rate']}  B率 {b['rate']}  "
              f"A死牌/店 {a['pads_per_shop']}  补位率 {a['boost_rate']}")
    print()
    print(HDR)
    for r in rows:
        print(fmt_row(r))
    print()
    print("诊断：死牌/店 与补位率（A 路径）")
    print("| 实验格    | 死牌/店 | P-1 补位率 |")
    print("|-----------|---------|------------|")
    for r in rows:
        a = r["mc"]["A"]
        print(f"| {r['cell']:<9} | {a['pads_per_shop']:>7} | {a['boost_rate']:>10} |")
    return rows


def run_mc_multi(seeds, runs=300, cells=None):
    """🔴 方法学必需：P-1 会改变 `rng` 的消耗次数，所以单 seed 对照实际上
    "换了一条轨迹"，1σ≈2.7pp 的噪声足以掩盖 1–4pp 的真实效应。
    这里用多种子重复同一格，报告逐 seed 读数与跨 seed 均值，才敢说"抵消了多少"。"""
    cells = cells or CELLS
    print("=" * 100)
    print(f"v0.10 多种子蒙特卡洛（{len(seeds)} seeds × {runs} 局/路径）")
    print("=" * 100)
    res = {}
    for name, kw in cells:
        res[name] = []
        for sd in seeds:
            r = eval_cell(name, kw, runs_mc=runs, seed=sd)
            res[name].append((r["mc"]["A"]["rate"], r["mc"]["B"]["rate"]))
        ar = [x[0] for x in res[name]]
        br = [x[1] for x in res[name]]
        print(f"[{name}] A {ar} mean={statistics.mean(ar):.3f}  "
              f"B {br} mean={statistics.mean(br):.3f}")
    print()
    print("| 实验格    | A率(逐 seed)              | A均值 | B率(逐 seed)              | B均值 |")
    print("|-----------|---------------------------|-------|---------------------------|-------|")
    for name, _ in cells:
        a = [x[0] for x in res[name]]
        b = [x[1] for x in res[name]]
        print(f"| {name:<9} | {' '.join(f'{v:.3f}' for v in a):<25} | "
              f"{statistics.mean(a):>5.3f} | {' '.join(f'{v:.3f}' for v in b):<25} | "
              f"{statistics.mean(b):>5.3f} |")
    print()
    if "base7" not in res:
        return res
    a0 = statistics.mean([x[0] for x in res["base7"]])
    print()
    print("相对 base7 的净变化（跨 seed 均值）：")
    b0 = statistics.mean([x[1] for x in res["base7"]])
    for name, _ in cells:
        if name == "base7":
            continue
        a = statistics.mean([x[0] for x in res[name]])
        b = statistics.mean([x[1] for x in res[name]])
        print(f"  {name:<9} A {(a-a0)*100:+6.1f}pp   B {(b-b0)*100:+6.1f}pp")
    print()
    print("P-1 的抵消率（同一池子内，P-1 on 相对 off 挽回了几成）：")
    for base_cell, p1_cell in (("base7", "base7p1"), ("pad8", "pad8p1"),
                               ("pad9", "pad9p1"), ("pad10", "pad10p1"),
                               ("pad12", "pad12p1")):
        if base_cell not in res or p1_cell not in res:
            continue
        a_off = statistics.mean([x[0] for x in res[base_cell]])
        a_on = statistics.mean([x[0] for x in res[p1_cell]])
        loss = a0 - a_off                       # 相对无死牌锚点的损失
        rec = a_on - a_off
        pct = (rec / loss * 100) if abs(loss) > 1e-9 else 0.0
        print(f"  {base_cell:<8} A 损失 {loss*100:+6.1f}pp  P-1 挽回 {rec*100:+6.1f}pp  "
              f"= {pct:>5.0f}%")
    return res


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "det"
    t0 = time.time()

    bad = selfcheck_draw()
    print(f"[selfcheck] P-1 关闭时 v10 抽卡 vs v0.9 原始实现：差异 {bad} 次（必须为 0）\n")

    if mode == "det":
        run_det()
    elif mode == "mc":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 300
        run_mc(n)
    elif mode == "census":
        gate_census()
    elif mode == "seeds":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 300
        run_mc_multi([v8.SEED1 + i for i in range(3)], n)
    elif mode == "all":
        run_det()
        print()
        gate_census()
        print()
        run_mc(300)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
