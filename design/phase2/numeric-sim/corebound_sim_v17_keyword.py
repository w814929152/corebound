# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.17：keyword 关键词联动（Enter / Sacrifice）骨架 + 实测**

================================================================================
它要回答的问题（keyword-linkage.md P0）
================================================================================
keyword-linkage.md 的 P0：给卡牌定义加 `keyword` 字段，把「触发时机」从装饰升级为
一等属性，先落 `Enter`（装配触发）+ `Sacrifice`（拆塔触发）两个词。
价值主张：补 P4 缺失的「时机」维度 —— 让「什么时候买、买在哪、什么时候拆」成为
有差别的决策。

但在写数值之前，必须先认一个方法学事实（v11/v12 已用证据钉死）：
  - `+1 h` 类效果「效率对但通过率不涨」（P-E 原则，h 经济寿命 ≈ 4）。
  - 贪心 AI（max gain/cost）没有「时机」概念，只看当前波次的瞬时性价比。

所以 P0 的实测核心不是「词条强不强」，而是三个更根本的问题：
  Q1  Sacrifice（拆塔正反馈）能否提高 AI 的拆塔意愿（决策结构是否改变）？
  Q2  Enter（装配给 h）是否重复 v12 的「效率对但通过率不涨」？（把结论从
      「等级链」推广到「keyword 词条」）
  Q3  两者是否破坏金标本（默认关闭零偏移）？

================================================================================
★ 方法学前提
================================================================================
1. sim 只有 7 张卡，无 T1–T6/S1–S4 定稿卡。所以 keyword 挂载在现有卡上做最小探针，
   不是 16 张库的完整实现。
2. Sacrifice 的载体已存在：v08 的 apply_salvage / salvage_on（Q-C3 拆塔返还 50%）。
   Sacrifice 词条 = 在拆塔时**额外**触发一个效果，不是重复 Salvage。
3. Enter 的载体已存在：apply_action 的 build/reinf 就是「装配」事件。
4. 全部 monkey-patch，不改 v03–v16 任何原文件。默认关闭 → 与 v14/v13 逐位一致。
================================================================================
用法
================================================================================
  python corebound_sim_v17_keyword.py selfcheck   # 默认关闭 → 与 v14 逐位一致
  python corebound_sim_v17_keyword.py probes      # 打印 keyword 探针定义
  python corebound_sim_v17_keyword.py diag        # 根因诊断（决定性能终局）
  python corebound_sim_v17_keyword.py mc 200      # MC：keyword 对起飞率/拆塔意愿的影响
"""

from __future__ import annotations

import random
import statistics
import sys
import time

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6  # noqa: F401
import corebound_sim_v08_salvage as v8
import corebound_sim_v14_factionlock as v14

# =============================================================================
# 0. keyword 探针定义（最小，忠实 keyword-linkage.md §3.1）
# =============================================================================
# keyword 值域：Enter（装配触发）/ Sacrifice（拆塔触发）。首期每张卡最多 1 个词。
# 效果严格遵守 E-2：只改结构性量（h / 层数 / 返还），禁改伤害/κ/攻速。
#
# 探针 1 · Enter（挂 FireUp）：装配 FireUp 到 Cannon 时，若本塔 h≥3，本塔 h+1
#     （每塔位限 1 次）—— 对标 level-chains §4.1 `Overclock` 的 echo 正面。
# 探针 2 · Sacrifice（全局）：拆塔时，在 50% 基础上额外返还 +20% 投入
#     （floor(70% × 投入)）—— 对标 keyword-linkage §3.1「拆塔返还 20%」。

KEYWORDS = {
    # 卡名       (词, 效果说明, 生效函数)
    "FireUp": ("Enter", "装配 FireUp 到 Cannon，若该塔 h>=3，该塔 h+1（每塔位 1 次）", None),
    "__sac__": ("Sacrifice", "拆塔时额外返还 +20% 投入（50% -> 70%）", None),
}

# Enter 词条挂在哪张卡上（KEYWORDS 里 tag 为 Enter 的卡）
ENTER_CARDS = [n for n, (k, _d, _f) in KEYWORDS.items() if k == "Enter" and n != "__sac__"]
SACRIFICE_BONUS = 0.20   # 拆塔额外返还比例（在 50% 基础上加）

# 全局开关 + 触发记忆（E-5：记忆键 = 塔位，只增不减）
_KEYWORD_ON = False
_ENTER_FIRED = set()      # 已触发 Enter 的 (slot, 卡名)
_SAC_TRIGGERED = 0        # 累计 Sacrifice 触发次数（供诊断）

# =============================================================================
# 1. 钩子：monkey-patch（默认关闭 → 逐位一致）
# =============================================================================
_orig_apply_action = sv.apply_action
_orig_apply_salvage = v8.apply_salvage


def _hooked_apply_action(player, act, cfg):
    """装配动作结算后，触发 Enter 词条。默认关闭 → 原样。"""
    cost = _orig_apply_action(player, act, cfg)
    if not _KEYWORD_ON or cost is None:
        return cost
    kind, name, slot, extra = act
    # Enter：装配 FireUp 到 Cannon，本塔 h>=3 时 h+1（每塔位 1 次）
    if name in ENTER_CARDS:
        for t in player.towers:
            if t.slot == slot and t.ctype == "Cannon" and t.h >= 3:
                key = (slot, name)
                if key not in _ENTER_FIRED:
                    _ENTER_FIRED.add(key)
                    t.h += 1
                    break
    return cost


def _hooked_apply_salvage(player, slot, fl):
    """拆塔结算后，触发 Sacrifice 词条。默认关闭 → 原样。"""
    refund = _orig_apply_salvage(player, slot, fl)
    if not _KEYWORD_ON or refund is None:
        return refund
    # Sacrifice：额外返还 +20%（在 50% 基础上）→ 共 70%
    global _SAC_TRIGGERED
    _SAC_TRIGGERED += 1
    # 额外返还 = 原返还不含额外 → 需用原投入反推：refund = floor(50% × invest)
    # 额外 = floor(invest × 20%)。用 refund / 0.5 反推 invest 会引入取整误差，
    # 改在 apply_salvage 内部直接加。这里退化为：额外 = floor(refund × 0.4)（≈ 20% 投入）。
    bonus = int(refund * 0.4)
    return refund + bonus


sv.apply_action = _hooked_apply_action
v8.apply_salvage = _hooked_apply_salvage


def set_keyword(on):
    """切换 keyword 机制开关（False = 默认，金标本零偏移）。"""
    global _KEYWORD_ON, _ENTER_FIRED, _SAC_TRIGGERED
    _KEYWORD_ON = on
    _ENTER_FIRED = set()
    _SAC_TRIGGERED = 0


# =============================================================================
# 2. 主循环（复用 v14，只加 keyword 开关）
# =============================================================================
def run_v17(path, cfg, faction="freelance", keyword_on=False, max_wave=20, geo=None, rng=None,
            _keep_state=False):
    set_keyword(keyword_on)
    try:
        return v14.run_v14(path, cfg, faction, max_wave, geo=geo, rng=rng)
    finally:
        if not _keep_state:
            set_keyword(False)


# =============================================================================
# 3. 校验与实验
# =============================================================================
def selfcheck():
    """默认关闭 keyword 时，v17 必须与 v14 逐位一致。"""
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r17, _, _ = run_v17(path, cfg, "freelance", False, 20, geo=sv.GEO6, rng=None)
        r14, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        if len(r17) != len(r14):
            return float("inf")
        for x, y in zip(r17, r14):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


def probes():
    """打印 keyword 探针定义。"""
    print("=" * 96)
    print("P0 · keyword 探针定义（最小实现，忠实 keyword-linkage.md §3.1）")
    print("=" * 96)
    for n, (k, desc, _f) in KEYWORDS.items():
        print(f"  [{k:<10}] {n:<12} {desc}")
    print()
    print("硬约束（沿用 level-chains E 系列）：")
    print("  E-2 只改结构性量（h / 返还），禁改伤害/κ/攻速")
    print("  E-5 记忆键 = 塔位，只增不减（防拆了重建再触发）")
    print("  默认关闭 → 与 v14 逐位一致（金标本零偏移）")


def _det_build(path, faction, kw_on):
    """决定性终局（rng=None 无限商店）。"""
    cfg = v8.cfg_of(path)
    cfg["wave_tag_on"] = False
    cfg["max_actions"] = 12
    rows, p, st = run_v17(path, cfg, faction, kw_on, 20, geo=sv.GEO6, rng=None)
    towers = [(t.slot, t.ctype, t.h, dict(t.attach)) for t in p.towers]
    return towers, p.cards


def _mc_cell(path, faction, kw, runs, seed, kw_on):
    """单格 MC：返回 (起飞率, 起飞波列表, 拆塔次数)。"""
    rng = random.Random(seed)
    cfg = v8.cfg_of(path)
    cfg.update(kw)
    cfg["max_actions"] = cfg.get("max_actions") or 12
    hits = 0
    tos = []
    salv = []
    for _ in range(runs):
        set_keyword(kw_on)
        rows, p, st = run_v17(path, cfg, faction, kw_on, 20, geo=sv.GEO6, rng=rng)
        set_keyword(False)
        alive = bool(rows) and rows[-1]["core_hp"] > 0
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            hits += 1
            tos.append(tw)
        salv.append(st.get("salvages", 0))
    return hits / runs, tos, salv


def diag():
    """根因诊断：决定性终局下，Enter/Sacrifice 是否真的被触发、改变了什么。"""
    print("=" * 96)
    print("P0 diag · keyword 探针的决定性终局诊断")
    print("=" * 96)

    # Enter 探针：熔炉 A，开 keyword，看终局 FireUp 是否触发了 h+1
    cfg = v8.cfg_of("A")
    cfg["wave_tag_on"] = False
    cfg["max_actions"] = 12
    rows, p, st = run_v17("A", cfg, "cinder", True, 20, geo=sv.GEO6, rng=None,
                          _keep_state=True)
    n_fired = len(_ENTER_FIRED)
    fired_slots = sorted(_ENTER_FIRED)
    set_keyword(False)
    towers = [(t.slot, t.ctype, t.h, dict(t.attach)) for t in p.towers]
    print(f"熔炉 A（Enter on）：Enter 触发 {n_fired} 次 @ {fired_slots}")
    print(f"  终局塔: {towers}")
    print(f"  卡组: {p.cards}")

    # 对照：熔炉 A，关 keyword
    towers_off, cards_off = _det_build("A", "cinder", False)
    print(f"对照（Enter off）终局塔: {towers_off}")
    print(f"  卡组: {cards_off}")
    print()

    # Sacrifice 探针：开 salvage，看拆塔次数
    set_keyword(True)
    cfg2 = v8.cfg_of("B")
    cfg2["wave_tag_on"] = False
    cfg2["salvage_on"] = True
    cfg2["max_actions"] = 12
    rows2, p2, st2 = run_v17("B", cfg2, "freelance", True, 20, geo=sv.GEO6, rng=None)
    s_on = st2.get("salvages", 0)
    set_keyword(False)

    cfg3 = v8.cfg_of("B")
    cfg3["wave_tag_on"] = False
    cfg3["salvage_on"] = True
    cfg3["max_actions"] = 12
    rows3, p3, st3 = run_v17("B", cfg3, "freelance", False, 20, geo=sv.GEO6, rng=None)
    s_off = st3.get("salvages", 0)

    print(f"混编 B（salvage on）：Sacrifice on 拆塔 {s_on} 次 vs off {s_off} 次")
    print(f"  注：Salvage 本身返还 50%，Sacrifice 额外 +20%（共 70%）")


def run_mc(runs=200):
    """MC：keyword 对起飞率 / 拆塔意愿的影响（3 seed 均值）。"""
    seeds = [v8.SEED1, v8.SEED2, v8.SEED3]
    cells = [
        ("Enter 熔炉A", "A", "cinder", dict(wave_tag_on=False), True),
        ("Enter 熔炉A(off)", "A", "cinder", dict(wave_tag_on=False), False),
        ("Sac 混编B", "B", "freelance", dict(wave_tag_on=False, salvage_on=True), True),
        ("Sac 混编B(off)", "B", "freelance", dict(wave_tag_on=False, salvage_on=True), False),
    ]
    print(f"P0 MC（{runs} 局/格 × {len(seeds)} seed）—— keyword 对起飞率/拆塔意愿")
    print("=" * 96)
    print(f"{'实验格':<18} {'起飞率(3seed)':>14} {'拆塔均次':>10} {'中位起飞':>10}")
    print("-" * 96)
    for name, path, faction, kw, kw_on in cells:
        rates, to_all, salv_all = [], [], []
        for seed in seeds:
            r, tos, salv = _mc_cell(path, faction, kw, runs, seed, kw_on)
            rates.append(r)
            to_all.extend(tos)
            salv_all.extend(salv)
        mean = statistics.mean(rates)
        sd = statistics.stdev(rates) if len(rates) > 1 else 0.0
        s_mean = statistics.mean(salv_all)
        print(f"{name:<18} {mean:.3f}±{sd:.3f}  {s_mean:>9.2f}  "
              f"{statistics.median(to_all) if to_all else '—':>10}")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] 关闭 keyword 时 v17 vs v14 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "probes":
        probes()
    elif mode == "diag":
        diag()
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
