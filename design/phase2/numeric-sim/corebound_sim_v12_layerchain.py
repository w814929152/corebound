# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.12：P6「换货币」链路（产物 = 层数，不是等级）**

================================================================================
它要回答的一个问题
================================================================================
v0.11 判死了三条 `h` 链，死因是**货币过期**：
    复利层边际 = κ−1 = 常数 10%        （每分效恒定）
    `h` 边际   = 0.6/h                 （倒数衰减，经济寿命 ≈ 4）
⇒ 若把链的产物从「`h` 增量」换成「**层数增量**」，它就直接插进同一台复利引擎，
  与 FireUp 层同频。这样能不能活？

================================================================================
三条链的共同骨架（沿用 chain-packs 的三角色位）
================================================================================
    成员 `Temper`  (9 分) 装配 → 该塔「同 Tag 层数最高的卡」+1 层
    发动机 `Bellows`(9 分) 装配 → 重触发该塔全部 `Temper`（每层再 +1 层）
    场景 `Kiln`   (10 分) 装配 → 立即 +1 层；此后每波开始 +1 层，每局共 2 次
    链深锁 1（重触发不再触发任何重触发）—— 唯一一条防循环规则

设计意图：28 分 → 净 **+4 层**（1 + 1 + 2）。同样 28 分直接买 FireUp = 3.11 层。
⇒ 账面倍率 1.29x，与 `v11-chain-report.md` §5 的换货币建议一致。

================================================================================
两个必须分开测的变量
================================================================================
**V1 槽位税**：链卡要占 3 个「卡种位」（`player.cards`），而买 3 张 FireUp 只占 0 个。
    P0 普查说定稿 A 只用了 2/5 个卡种 → 槽位闲置 → 税可能为零。用 `v12_slotfree` 隔离。

**V2 贪心近视**：`Kiln` 的收益有一半在**未来波**。逐次贪心的 AI 只看得见装配那一下，
    会把它估成「10 分买 1 层」→ 永远不买 → 链永远凑不齐。
    这是 v0.11 `Conduit` 被买 0.00 次的同一种病（发动机单独看没价值）。
    用 `v12_look` ∈ {0, 1} 对照：0 = 完全近视，1 = 按剩余触发次数折算。

================================================================================
用法
================================================================================
  python corebound_sim_v12_layerchain.py det      # 决定性对照（秒级）
  python corebound_sim_v12_layerchain.py sweep    # 净层数横截面（找盈亏平衡点）
  python corebound_sim_v12_layerchain.py mc 300   # 蒙特卡洛
  python corebound_sim_v12_layerchain.py seeds    # 3 seed × 300
"""
from __future__ import annotations

import os
import sys
import time
import random
import statistics

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6          # noqa: F401
import corebound_sim_v07_mapA as v7             # noqa: F401
import corebound_sim_v08_salvage as v8
import corebound_sim_v09_trigger as v9
import corebound_sim_v11_chain as v11

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 0. 链卡定义（全部 [PLACEHOLDER]）
# =============================================================================
L12_CARDS = {
    "Temper":  dict(price=9.0,  w=0.13, role="member"),
    "Bellows": dict(price=9.0,  w=0.13, role="engine"),
    "Kiln":    dict(price=10.0, w=0.10, role="scene"),
}
L12_NON_STACK = set(L12_CARDS)
v9.V9_NON_STACK |= L12_NON_STACK        # 链卡自身不计入 stack 层数（它们是转换器）

# 🔴 v11 在导入时把对照探针 `FireUp2` 注册进了全局卡表 → 会污染 v12 的动作空间。
# 必须在导入后立即摘掉，否则 base 格也会偷偷买到一张「与 FireUp 等价的第二卡种」。
sv.ALL_CARDS.pop(v11.PROBE_CARD, None)
sv.REINF.pop(v11.PROBE_CARD, None)
for _p in ("A", "B"):
    sv.ALLOWED[_p] = set(sv.ALLOWED[_p]) - {v11.PROBE_CARD}

KILN_TOTAL = 2          # Kiln 每局总共触发 2 次（含装配那次）


# =============================================================================
# 1. 层数货币：找「该塔要把层加到哪张卡上」
# =============================================================================
def stack_cards(t):
    """该塔上计入 stack 的同 Tag 效果卡，按层数降序。"""
    tag = sv.TOWERS[t.ctype]["tag"]
    if tag is None:
        return []
    out = []
    for rn, lv in t.attach.items():
        if lv <= 0 or rn in v9.V9_NON_STACK:
            continue
        if sv.REINF.get(rn, {}).get("tag") != tag:
            continue
        out.append((lv, rn))
    return sorted(out, reverse=True)


def dom_card(t):
    """该塔「同 Tag 层数最高」的卡名；没有则 None（链在这座塔上完全无效）。"""
    s = stack_cards(t)
    return s[0][1] if s else None


def grant_layer(t, k, cap, st):
    """给该塔的主卡 +k 层，受全局层数预算 cap 约束。返回实际给了几层。"""
    got = 0
    for _ in range(k):
        if st["granted"] >= cap:
            break
        nm = dom_card(t)
        if nm is None:
            break
        t.attach[nm] = t.attach.get(nm, 0) + 1
        st["granted"] += 1
        got += 1
    return got


def retrigger_temper(t, cap, st):
    """重触发该塔上的 Temper：每层 Temper 再给 1 层。链深锁 1（不再触发 Bellows）。"""
    lv = t.attach.get("Temper", 0)
    if lv <= 0:
        return 0
    return grant_layer(t, lv, cap, st)


def per_layer_gain(player, cfg, geo, t):
    """该塔 +1 层主卡的 ΔDPS（解析式，不改状态）。"""
    nm = dom_card(t)
    if nm is None:
        return 0.0
    d0, _ = v11.compute_dps_v11(player, cfg, geo)
    old = t.attach[nm]
    t.attach[nm] = old + 1
    d1, _ = v11.compute_dps_v11(player, cfg, geo)
    t.attach[nm] = old
    return d1 - d0


# =============================================================================
# 2. 动作
# =============================================================================
def action_cost_v12(act, cfg, counts):
    kind, name, slot, extra = act
    if name in L12_CARDS:
        base = L12_CARDS[name]["price"] * cfg.get("v12_pmult", 1.0)
        return base + cfg.get("wave_price_step", 0.0) * counts.get(name, 0)
    return sv.action_cost(act, cfg, counts)


def apply_action_v12(player, act, cfg, geo, st):
    kind, name, slot, extra = act
    if name not in L12_CARDS:
        return sv.apply_action(player, act, cfg)
    if kind == "reinf_swap":
        sv.drop_from(player, extra)
        player.cards.add(name)
    elif kind == "reinf_new":
        if len(player.cards) >= cfg["backpack"]:
            return None
        player.cards.add(name)
    elif name not in player.cards:
        return None
    t = next((x for x in player.towers if x.slot == slot), None)
    if t is None:
        return None
    cap = cfg.get("v12_cap", 6)
    t.attach[name] = t.attach.get(name, 0) + 1
    if name == "Temper":
        grant_layer(t, 1, cap, st)
    elif name == "Bellows":
        if cfg.get("v12_selfsuff"):
            grant_layer(t, 1, cap, st)          # 自足：单独买也给 1 层（不依赖 Temper）
        retrigger_temper(t, cap, st)            # 凑齐奖励：重触发该塔的 Temper
    elif name == "Kiln":
        grant_layer(t, 1, cap, st)          # 装配即触发
        st["kiln_left"] -= 1
    return L12_CARDS[name]["price"]


def action_value_v12(player, act, cfg, geo, st, wave):
    """链卡用「解析估值」，把未来触发按 `v12_look` 折进来。

    v12_look = 0 → 完全近视（只看装配那一下）→ 复现 v0.11 Conduit 的病
    v12_look = 1 → 按剩余触发次数折算（理性玩家）
    """
    kind, name, slot, extra = act
    if name not in L12_CARDS:
        return v11.action_value_v11(player, act, cfg, geo)
    t = next((x for x in player.towers if x.slot == slot), None)
    if t is None:
        return None
    if len(player.cards) >= cfg["backpack"] and kind == "reinf_new":
        return None
    g = per_layer_gain(player, cfg, geo, t)
    if g <= 0:
        return 0.0, L12_CARDS[name]["price"]
    cap = cfg.get("v12_cap", 6)
    left = max(0, cap - st["granted"])          # 全局层数预算还剩几层
    if left <= 0:
        return 0.0, L12_CARDS[name]["price"]    # 预算耗尽 → 边际收益为零（不得虚估）
    look = cfg.get("v12_look", 1.0)
    if name == "Temper":
        layers = 1
    elif name == "Bellows":
        layers = (1 if cfg.get("v12_selfsuff") else 0) + t.attach.get("Temper", 0)
    else:                                            # Kiln
        if st["kiln_left"] <= 0:
            return 0.0, L12_CARDS[name]["price"]
        future = max(0, min(st["kiln_left"] - 1, max(0, 20 - wave)))
        layers = 1 + look * future
    return g * min(layers, left), L12_CARDS[name]["price"]


def enumerate_actions_v12(player, cfg, fire_bought, offers=None, geo=None, unlocked=False):
    acts = list(v9.enumerate_actions_v9(player, cfg, fire_bought, offers, geo))
    if not cfg.get("v12_chain"):
        return acts
    for name in L12_CARDS:
        if name != "Temper" and not unlocked:       # 链内解锁：先见成员卡
            continue
        if offers is not None and name not in offers:
            continue
        for t in player.towers:
            if name in player.cards:
                acts.append(("reinf", name, t.slot, None))
            elif len(player.cards) < cfg["backpack"]:
                acts.append(("reinf_new", name, t.slot, None))
            elif not cfg.get("v12_slotfree"):
                drop = sv.weakest_card(player, cfg, geo)
                if drop is not None and drop != name:
                    acts.append(("reinf_swap", name, t.slot, drop))
            else:
                acts.append(("reinf_new", name, t.slot, None))
    return acts


# =============================================================================
# 3. 商店
# =============================================================================
def _unlocked(cfg, player):
    """链卡是否解锁。v12_early 时恒真（W1 起就能买全部链卡）；
    否则维持链内解锁（先买到成员卡 Temper 才开放发动机/场景）。"""
    if cfg.get("v12_early"):
        return True
    return "Temper" in player.cards


def pool_weights_v12(cfg, unlocked=False):
    w = dict(v9.pool_weights(cfg))
    if cfg.get("v12_chain"):
        w["Temper"] = L12_CARDS["Temper"]["w"]
        if unlocked:
            w["Bellows"] = L12_CARDS["Bellows"]["w"]
            w["Kiln"] = L12_CARDS["Kiln"]["w"]
    return w


def draw_offers_v12(rng, cfg, k=3, force=None, unlocked=False, chain_force=None):
    """chain_force：链内保底 —— 指定一张链卡强制进入本波 offers（P7）。"""
    w = pool_weights_v12(cfg, unlocked)
    names = list(w)                                  # 保序：RNG 契约
    s = set(rng.choices(names, weights=[w[n] for n in names], k=k))
    if force:
        s.add(force)
    if chain_force:
        s.add(chain_force)
    while len(s) > k:
        s.discard(rng.choice(sorted(s - ({force} if force else set())
                                   - ({chain_force} if chain_force else set()))))
    return s


def _chain_force(st, player, cfg, w):
    """链内保底（P7）：买到成员卡后，接下来 v12_pitywindow 波内，
    每波强制注入一张尚未拥有的链卡（优先发动机，其次场景）。
    返回本波要强制出的链卡名，或 None。"""
    if not cfg.get("v12_pitychain"):
        return None
    if "Temper" not in player.cards:
        return None
    win = cfg.get("v12_pitywindow", 2)
    first = st.get("chain_first_buy_wave")
    if first is None:
        return None
    if w - first > win:
        return None
    for name in ("Bellows", "Kiln"):
        if name not in player.cards:
            return name
    return None


def shop_phase_v12(player, budget, w, cfg, geo, rng, st):
    fl = st["free_layers"]
    rerolls = 0
    actions = 0
    fire_bought = 0
    counts = {}
    offers = None
    unlocked = _unlocked(cfg, player)
    chain_force = _chain_force(st, player, cfg, w)
    if rng is not None:
        offers = draw_offers_v12(rng, cfg, cfg["shop_offers"],
                                 sv.pity_card(player) if cfg.get("pity") else None,
                                 unlocked=unlocked, chain_force=chain_force)
    while budget > 0:
        if cfg["max_actions"] is not None and actions >= cfg["max_actions"]:
            break
        cands = enumerate_actions_v12(player, cfg, fire_bought, offers, geo, unlocked)
        scored = []
        for act in cands:
            v = action_value_v12(player, act, cfg, geo, st, w)
            if v is None:
                continue
            gain, _ = v
            cost = action_cost_v12(act, cfg, counts)
            if gain <= 0 or budget < cost:
                continue
            scored.append((gain / cost, act, cost))
        if scored:
            if rng is not None and cfg["skill"] < 1.0 and rng.random() > cfg["skill"]:
                pick = scored[rng.randrange(len(scored))]
            else:
                pick = max(scored, key=lambda x: x[0])
            _, act, cost = pick
            if apply_action_v12(player, act, cfg, geo, st) is None:
                break
            if sv.ALL_CARDS.get(act[1], {}).get("tag") == "fire":
                fire_bought += 1
            counts[act[1]] = counts.get(act[1], 0) + 1
            budget -= cost
            actions += 1
            st["spent"] = st.get("spent", 0.0) + cost
            st["acts"] = st.get("acts", 0) + 1
            if act[1] in L12_CARDS:
                st["bought"][act[1]] = st["bought"].get(act[1], 0) + 1
                st["buy_log"].append((w, act[1]))
                if act[1] == "Temper" and st.get("chain_first_buy_wave") is None:
                    st["chain_first_buy_wave"] = w
            v8._sync_free_layers(player, fl)
            st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
            player.n_hist_max = st["n_hist_max"]
            unlocked = _unlocked(cfg, player)
            continue
        rc = max(1.0, cfg["reroll_base"] + cfg["reroll_growth"] * rerolls - player.reroll_disc)
        if rc > budget:
            break
        if cfg["max_actions"] is not None and actions + 1 > cfg["max_actions"]:
            break
        budget -= rc
        rerolls += 1
        actions += 1
        if rng is not None:
            offers = draw_offers_v12(rng, cfg, cfg["shop_offers"],
                                     sv.pity_card(player) if cfg.get("pity") else None,
                                     unlocked=unlocked, chain_force=chain_force)
        elif rerolls > 400:
            break
    return budget, rerolls


# =============================================================================
# 4. 主循环
# =============================================================================
def run_v12(path, cfg, max_wave=20, geo=None, rng=None):
    cfg = dict(cfg)
    if geo is None:
        geo = sv.GEO6 if cfg["n_slots"] >= 6 else sv.GEO4
    player = sv.new_player(path, cfg, geo)
    player.charge_cond = {}
    player.last_share = {}
    st = dict(free_layers={0: 1}, n_hist_max=len(player.towers), log=[],
              granted=0, kiln_left=KILN_TOTAL, bought={}, buy_log=[], spent=0.0, acts=0,
              kiln_fired=0, bellows_fired=0, chain_first_buy_wave=None)
    player.n_hist_max = st["n_hist_max"]
    core_hp = cfg["core_hp"]
    rows = []
    cum = 0.0
    cum_rerolls = 0
    cap = cfg.get("v12_cap", 6)

    for w in range(1, max_wave + 1):
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]

        # ---- 波开始：Kiln 的场景触发（每局限 2 次，含装配那次）----
        if cfg.get("v12_chain") and st["kiln_left"] > 0:
            for t in player.towers:
                if t.attach.get("Kiln", 0) <= 0:
                    continue
                if st["kiln_left"] <= 0:
                    break
                if retrigger_temper(t, cap, st) > 0:
                    st["kiln_fired"] += 1
                    st["kiln_left"] -= 1

        res = sv.simulate_wave(player, w, cfg, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income

        budget, rr = shop_phase_v12(player, cum, w, cfg, geo, rng, st)
        cum = budget
        cum_rerolls += rr
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]
        dps, _ = v11.compute_dps_v11(player, cfg, geo)
        ratio = dps / res["total_hp"] if res["total_hp"] > 0 else 0.0
        rows.append(dict(
            w=w, n=res["n"], hp_each=round(res["hp_each"], 1),
            total_hp=round(res["total_hp"], 1), eff_dps=round(dps, 1),
            ratio=round(ratio, 3), core_hp=round(max(0.0, core_hp), 1),
            income=round(income, 1), rerolls=rr, cum_rerolls=cum_rerolls,
            towers=len(player.towers), slots=len(player.cards),
            build=player.build_str(),
        ))
        if core_hp <= 0:
            break
    return rows, player, st


# =============================================================================
# 5. 实验格
# =============================================================================
BASE_KW = dict(v9_charge=False, v9_relay=False, v9_pad=0)

CELLS = [
    ("base",      dict(BASE_KW)),
    ("chain4",    dict(BASE_KW, v12_chain=True, v12_cap=6)),
    ("chain_myo", dict(BASE_KW, v12_chain=True, v12_cap=6, v12_look=0.0)),
    ("chain_free", dict(BASE_KW, v12_chain=True, v12_cap=6, v12_slotfree=True)),
    ("chain12",   dict(BASE_KW, v12_chain=True, v12_cap=12)),
]

# P7 实验格：改获取，不改数值（数值沿用 cap=6 的 chain4）
P7_CELLS = [
    ("base",       dict(BASE_KW)),
    ("chain4",     dict(BASE_KW, v12_chain=True, v12_cap=6)),
    ("early",      dict(BASE_KW, v12_chain=True, v12_cap=6, v12_early=True)),
    ("pitychain",  dict(BASE_KW, v12_chain=True, v12_cap=6, v12_pitychain=True)),
    ("early+pity", dict(BASE_KW, v12_chain=True, v12_cap=6, v12_early=True, v12_pitychain=True)),
]


def make_cfg(path, kw, **over):
    c = v8.cfg_of(path)
    for k, v in kw.items():
        c[k] = v
    c.update(over)
    return c


def eval_cell(name, kw, runs_mc=0, seed=v8.SEED1):
    out = dict(cell=name, kw=dict(kw))
    sts = {}
    for path in ("A", "B"):
        rows, player, st = run_v12(path, make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        s = v6.summarize(rows)
        sts[path] = dict(rows=rows, s=s, player=player, st=st)
    sA, sB = sts["A"]["s"], sts["B"]["s"]
    w20A, w20B = sA["w20"] or 0.0, sB["w20"] or 0.0
    out.update(toA=sA["takeoff"], toB=sB["takeoff"], w20A=round(w20A, 2),
               w20B=round(w20B, 2), ba=round(w20B / w20A, 3) if w20A else 0.0,
               grantedA=sts["A"]["st"]["granted"], grantedB=sts["B"]["st"]["granted"],
               st=sts)
    if runs_mc:
        mc = {}
        for path in ("A", "B"):
            rng = random.Random(seed)
            cfg = make_cfg(path, kw)
            cfg["max_actions"] = cfg.get("max_actions") or 12
            ok = hits = 0
            tos = []
            agg = dict(granted=0)
            buys = {k: 0 for k in L12_CARDS}
            for _ in range(runs_mc):
                rows, player, st = run_v12(path, cfg, 20, geo=sv.GEO6, rng=rng)
                alive = bool(rows) and rows[-1]["core_hp"] > 0
                tw = sv.takeoff_wave(rows)
                if alive:
                    ok += 1
                    if tw is not None:
                        hits += 1
                        tos.append(tw)
                agg["granted"] += st["granted"]
                for k in L12_CARDS:
                    buys[k] += st["bought"].get(k, 0)
            mc[path] = dict(rate=round(hits / runs_mc, 3), surv=round(ok / runs_mc, 3),
                            med=statistics.median(tos) if tos else None,
                            granted=round(agg["granted"] / runs_mc, 2),
                            buys={k: round(v / runs_mc, 2) for k, v in buys.items()})
        out["mc"] = mc
    return out


# =============================================================================
# 6. 输出
# =============================================================================
HDR = ("| 实验格     | toA  | toB  |   W20-A  |   W20-B  |  B/A   | A率   | B率   | 净层A | 净层B |\n"
       "|------------|------|------|----------|----------|--------|-------|-------|-------|-------|")


def fmt_row(r):
    def n(v):
        return "—" if v is None else str(v)
    mc = r.get("mc") or {}
    a, b = mc.get("A", {}), mc.get("B", {})
    return (f"| {r['cell']:<10} | {n(r['toA']):>4} | {n(r['toB']):>4} | "
            f"{r['w20A']:>8.2f} | {r['w20B']:>8.2f} | {r['ba']:>6.3f} | "
            f"{n(a.get('rate')):>6} | {n(b.get('rate')):>6} | "
            f"{r['grantedA']:>5} | {r['grantedB']:>5} |")


def selfcheck():
    """链关掉时必须与 v9 逐位一致。"""
    worst = 0.0
    for path in ("A", "B"):
        kw = dict(BASE_KW, v10_pity2=False)
        r9, _, _ = v9.run_v9(path, v9.make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        r12, _, _ = run_v12(path, make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        if len(r9) != len(r12):
            return float("inf")
        for x, y in zip(r9, r12):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


def run_det():
    print("=" * 112)
    print("v0.12 决定性对照（rng=None，理性 AI，GEO6，20 波）—— 产物 = 层数")
    print("=" * 112)
    rowsk = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw)
        rowsk.append(r)
        print(f"[{name}] {time.time()-t0:.1f}s")
    print()
    print(HDR)
    for r in rowsk:
        print(fmt_row(r))
    base = rowsk[0]
    print()
    print("相对 base 的偏移：")
    for r in rowsk[1:]:
        b = r["st"]["B"]["st"]["bought"]
        print(f"  {r['cell']:<11} W20A {r['w20A']-base['w20A']:+9.2f}"
              f"  W20B {r['w20B']-base['w20B']:+9.2f}"
              f"  B/A {r['ba']-base['ba']:+.3f}"
              f"   购入 A {r['st']['A']['st']['bought']}")
    print()
    print("终局塔配置：")
    for r in rowsk:
        pa = r["st"]["A"]["player"]
        pb = r["st"]["B"]["player"]
        print(f"  {r['cell']:<11} A: {pa.build_str()}")
        print(f"  {'':<11} B: {pb.build_str()}")
    return rowsk


def sweep():
    """净层数横截面：cap 从 0 扫到 14，找「链打平/打赢」的盈亏平衡点。"""
    print("=" * 112)
    print("净层数横截面（cap = 每局链最多给几层；28 分成本固定）")
    print("=" * 112)
    print("| cap | 净层A | 净层B |  W20-A  |  W20-B  | 相对base A | 相对base B | B/A |")
    print("|-----|-------|-------|---------|---------|------------|------------|-----|")
    b = eval_cell("base", dict(BASE_KW))
    for cap in (0, 2, 4, 6, 8, 10, 12, 14):
        r = eval_cell(f"cap{cap}", dict(BASE_KW, v12_chain=True, v12_cap=cap))
        print(f"| {cap:<3} | {r['grantedA']:>5} | {r['grantedB']:>5} | "
              f"{r['w20A']:>7.2f} | {r['w20B']:>7.2f} | "
              f"{r['w20A']-b['w20A']:>+10.2f} | {r['w20B']-b['w20B']:>+10.2f} | "
              f"{r['ba']:>5.3f} |")
    print()
    print("参照：同样 28 分直接买 FireUp = 3.11 层；cap=4 即账面 1.29x。")


def price_sweep():
    """价格横截面：cap 固定 4 / 8，把链卡价格整体乘 0.75→3.0，看它什么时候不被买。

    「首购率」是判定定价是否合理的唯一硬指标（chain-packs §9 失败信号 A/B）：
      全买 → 太便宜；一个不买 → 太贵；落在 40%~80% 才是「要权衡」的区间。
    """
    print("=" * 112)
    print("价格横截面（cap=4 / cap=8，价格乘数 0.75→3.0）")
    print("=" * 112)
    print("| pmult | cap | 链卡总价 | 净层A | 净层B |  W20-A  |  W20-B  | 购入明细(A) |")
    print("|-------|-----|----------|-------|-------|---------|---------|-------------|")
    b = eval_cell("base", dict(BASE_KW))
    for cap in (4, 8):
        for pm in (0.75, 1.0, 1.5, 2.0, 2.5, 3.0):
            kw = dict(BASE_KW, v12_chain=True, v12_cap=cap, v12_pmult=pm)
            r = eval_cell(f"p{pm}c{cap}", kw)
            tot = round(sum(L12_CARDS[k]["price"] for k in L12_CARDS) * pm, 1)
            bu = r["st"]["A"]["st"]["bought"]
            print(f"| {pm:<5} | {cap:<3} | {tot:>8} | {r['grantedA']:>5} | {r['grantedB']:>5} | "
                  f"{r['w20A']:>7.2f} | {r['w20B']:>7.2f} | {bu} |")
    print()
    print(f"参照 base：W20-A {b['w20A']} / W20-B {b['w20B']} / B/A {b['ba']}")


def probe():
    """在真实 W12 状态上给一条「每层值多少分」的标尺。"""
    print("=" * 112)
    print("层数货币标尺（W12 停留态，主塔）")
    print("=" * 112)
    for path in ("A", "B"):
        cfg = make_cfg(path, dict(BASE_KW))
        p = sv.new_player(path, cfg, sv.GEO6)
        st = dict(free_layers={0: 1}, n_hist_max=1, granted=0, kiln_left=KILN_TOTAL,
                  bought={}, buy_log=[], kiln_fired=0, bellows_fired=0)
        p.n_hist_max = 1
        cum = 0.0
        for w in range(1, 13):
            res = sv.simulate_wave(p, w, cfg, sv.GEO6)
            cum += res["scrap_earned"] * (1.0 + p.income_mult)
            cum, _ = shop_phase_v12(p, cum, w, cfg, sv.GEO6, None, st)
        d0, _ = v11.compute_dps_v11(p, cfg, sv.GEO6)
        tg = max(p.towers, key=lambda t: v11._pt_dps(p, cfg, sv.GEO6).get(t.slot, 0.0))
        g = per_layer_gain(p, cfg, sv.GEO6, tg)
        print(f"\n--- 路径 {path} · 主塔 塔{tg.slot} {tg.ctype} h={tg.h}"
              f" · 主卡 {dom_card(tg)} ×{tg.attach.get(dom_card(tg) or '', 0)}"
              f" · DPS {d0:.0f} ---")
        print(f"  +1 层 = {g:>10.1f} DPS  ({g/d0*100:.2f}%)   每分效 {g/9:>8.1f}")
        print(f"  +1 h  = {_h_gain(p, cfg, tg):>10.1f} DPS   每分效 {_h_gain(p, cfg, tg)/12:>8.1f}")
        print(f"  ⇒ 层 / h 每分效比 = {(g/9)/(_h_gain(p, cfg, tg)/12):.2f}x（>1 说明层数是正确货币）")


def _h_gain(p, cfg, t):
    d0, _ = v11.compute_dps_v11(p, cfg, sv.GEO6)
    t.h += 1
    d1, _ = v11.compute_dps_v11(p, cfg, sv.GEO6)
    t.h -= 1
    return d1 - d0


def run_mc(runs=300):
    print("=" * 112)
    print(f"v0.12 蒙特卡洛（{runs} 局/路径，seed={v8.SEED1}）")
    print("=" * 112)
    rows = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw, runs_mc=runs)
        rows.append(r)
        a, b = r["mc"]["A"], r["mc"]["B"]
        print(f"[{name}] {time.time()-t0:.0f}s  A率 {a['rate']} B率 {b['rate']}  "
              f"净层A {a['granted']} 购入A {a['buys']}")
    print()
    print(HDR)
    for r in rows:
        print(fmt_row(r))
    print()
    print("每局平均购入（A / B）：")
    print("| 实验格     | Temper A | Bellows A | Kiln A | Temper B | Bellows B | Kiln B |")
    print("|------------|----------|-----------|--------|----------|-----------|--------|")
    for r in rows:
        a, b = r["mc"]["A"]["buys"], r["mc"]["B"]["buys"]
        print(f"| {r['cell']:<10} | {a['Temper']:>8} | {a['Bellows']:>9} | "
              f"{a['Kiln']:>6} | {b['Temper']:>8} | {b['Bellows']:>9} | {b['Kiln']:>6} |")
    return rows


def run_seeds(seeds, runs=300):
    print("=" * 112)
    print(f"v0.12 多种子（{len(seeds)} seeds × {runs} 局/路径）")
    print("=" * 112)
    res = {}
    for name, kw in CELLS:
        res[name] = []
        for sd in seeds:
            r = eval_cell(name, kw, runs_mc=runs, seed=sd)
            res[name].append((r["mc"]["A"]["rate"], r["mc"]["B"]["rate"]))
    print("| 实验格     | A率(逐 seed)              | A均值 | B率(逐 seed)              | B均值 | ΔA |")
    print("|------------|---------------------------|-------|---------------------------|-------|----|")
    a0 = statistics.mean([x[0] for x in res["base"]])
    for name, _ in CELLS:
        a = [x[0] for x in res[name]]
        b = [x[1] for x in res[name]]
        print(f"| {name:<10} | {' '.join(f'{v:.3f}' for v in a):<25} | "
              f"{statistics.mean(a):>5.3f} | {' '.join(f'{v:.3f}' for v in b):<25} | "
              f"{statistics.mean(b):>5.3f} | {statistics.mean(a)-a0:+.3f} |")
    return res


def run_p7(seeds, runs=300):
    """P7 实验：改获取（v12_early / v12_pitychain），数值沿用 cap=6。"""
    print("=" * 112)
    print(f"P7 获取改造对照（{len(seeds)} seeds × {runs} 局/路径，数值沿用 cap=6）")
    print("=" * 112)
    res = {}
    for name, kw in P7_CELLS:
        res[name] = []
        for sd in seeds:
            r = eval_cell(name, kw, runs_mc=runs, seed=sd)
            res[name].append((r["mc"]["A"]["rate"], r["mc"]["B"]["rate"]))
    print("| 实验格      | A率(逐 seed)              | A均值  | B率(逐 seed)              | B均值  | ΔA      | ΔB      |")
    print("|-------------|---------------------------|--------|---------------------------|--------|---------|---------|")
    a0 = statistics.mean([x[0] for x in res["base"]])
    b0 = statistics.mean([x[1] for x in res["base"]])
    for name, _ in P7_CELLS:
        a = [x[0] for x in res[name]]
        b = [x[1] for x in res[name]]
        print(f"| {name:<11} | {' '.join(f'{v:.3f}' for v in a):<25} | "
              f"{statistics.mean(a):>6.3f} | {' '.join(f'{v:.3f}' for v in b):<25} | "
              f"{statistics.mean(b):>6.3f} | {statistics.mean(a)-a0:>+7.3f} | "
              f"{statistics.mean(b)-b0:>+7.3f} |")
    print()
    print("每局平均购入链卡（A / B）：")
    print("| 实验格      | Temper A | Bellows A | Kiln A | Temper B | Bellows B | Kiln B | 净层A | 净层B |")
    print("|-------------|----------|-----------|--------|----------|-----------|--------|-------|-------|")
    for name, kw in P7_CELLS:
        r = eval_cell(name, kw, runs_mc=runs, seed=seeds[0])
        a, b = r["mc"]["A"]["buys"], r["mc"]["B"]["buys"]
        print(f"| {name:<11} | {a['Temper']:>8} | {a['Bellows']:>9} | {a['Kiln']:>6} | "
              f"{b['Temper']:>8} | {b['Bellows']:>9} | {b['Kiln']:>6} | "
              f"{r['mc']['A']['granted']:>5} | {r['mc']['B']['granted']:>5} |")
    return res


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "det"
    t0 = time.time()
    d = selfcheck()
    print(f"[selfcheck] 链关闭时 v12 vs v9 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）\n")
    if mode == "det":
        run_det()
    elif mode == "sweep":
        sweep()
    elif mode == "price":
        price_sweep()
    elif mode == "probe":
        probe()
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    elif mode == "seeds":
        run_seeds([v8.SEED1 + i for i in range(3)],
                  int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    elif mode == "p7":
        run_p7([v8.SEED1 + i for i in range(3)],
               int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
