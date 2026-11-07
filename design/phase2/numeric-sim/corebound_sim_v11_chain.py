# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.11：Stack 分配结构实验 + 摄灵链**

================================================================================
它要回答的两个问题
================================================================================
**Q1（结构）** 定稿的 `B2 Stack` 是**和式**：
    stack = 1 + Σ_cards ( κ^lv − 1 )
    一张卡 100 层 → κ^100 = 13780；两张各 50 层 → 2·κ^50 − 1 = 234 = **1.7%**。
    ⇒ 和式严格惩罚「把层数分给第二张卡」。
    改成**积式** `stack = Π κ^lv = κ^ΣL` 后，分配完全中立（两张各 50 层 = 一张 100 层）。
    **单卡时两者恒等** → 对定稿零影响；只有出现第二张同 Tag 卡时才有差别。

**Q2（内容）** 摄灵链（Siphon + Conduit）能不能打过「再买一层 FireUp」？
    用真实 W12 状态枚举全部动作的 `gain/cost`，看连锁卡排第几。

================================================================================
为什么必须先问 Q1
================================================================================
P0 普查发现：定稿 A 在 W12 只持 **2 个卡种**（Arrow + FireUp），5 个强化槽**空着 3 个**。
FireUp 一张占 99.9% DPS。也就是说「槽位稀缺」这个 P1/P3 赖以成立的前提，
在当前卡池里**从未真正生效**。

原因是结构性的，不是玩家懒：和式下第二张同 Tag 卡的边际收益是
    Δ(新卡第 1 层) = κ^1 − 1 = 0.10     （相对 171.9 的 FireUp 栈 → **0.06%**）
    Δ(FireUp +1 层) = κ^55 − κ^54 = 17.2 （相对 → **10%**）
**同样 9 分，差 167 倍。** 任何「第二张火卡」在和式下都不可买。

⇒ 这不是 pity 稀释（概率问题），是**收益结构问题**。稀释会让新卡「有时看不到」，
   和式会让新卡「看到了也不该买」。

================================================================================
实现（最小侵入，全部可用开关关掉）
================================================================================
★ 不改 v03–v10 任何原文件（v9.V9_NON_STACK 的运行时扩充除外，见下）。
★ `v11_stack = "sum"`（默认）时 `compute_dps_v11` 直接返回 v9 的结果，逐位一致。
★ 对照卡 `FireUp2`：与 FireUp **完全等价**的纯火卡，只为测「第二张卡是否被买」。
   它不进任何生产卡池，只在 `v11_card2 = True` 时入场。
★ 摄灵：成员 `Siphon` 初始池；发动机 `Conduit` 在买到 Siphon 后才入场（链内解锁）。
   场景卡「中继」本版不建模（建塔事件每局 ≤6 次，上限太低，单独议）。

用法：
  python corebound_sim_v11_chain.py det        # 决定性对照（秒级）
  python corebound_sim_v11_chain.py probe      # W12 动作性价比排行（秒级）
  python corebound_sim_v11_chain.py mc 300     # 蒙特卡洛
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

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 0. 新卡 / 对照卡定义（全部 [PLACEHOLDER]）
# =============================================================================
V11_CARDS = {
    # 成员卡：装配时把「相邻 DPS 最高塔」的 1 点 h 搬到本塔
    "Siphon":  dict(price=9.0, w=0.13, role="member"),
    # 发动机：每波开始重触发「相邻塔上的 Siphon」一次（每塔位 3 次）
    "Conduit": dict(price=9.0, w=0.13, role="engine"),
}
V11_NON_STACK = set(V11_CARDS)
v9.V9_NON_STACK |= V11_NON_STACK        # 运行时接入 v9 的层数口径（v9 文件不改）

CONDUIT_PER_SLOT = 3        # 每塔位每局最多触发 3 次
SIPHON_MIN_DONOR = 2        # 血包塔 h 至少要 2 才抽得动

PROBE_CARD = "FireUp2"      # 对照探针：与 FireUp 完全等价
sv.REINF[PROBE_CARD] = dict(tag="fire")
sv.ALL_CARDS[PROBE_CARD] = dict(kind="reinforce", tag="fire")
for _p in ("A", "B"):
    sv.ALLOWED[_p] = set(sv.ALLOWED[_p]) | {PROBE_CARD}


# =============================================================================
# 1. 引擎：v9 + Stack 分配模式
# =============================================================================
def _stack_prod(t, kappa_i, cap, decay):
    """积式：Π softcap_pow(lv)。单卡时恒等于和式的那一项。"""
    s = 1.0
    for rn, lv in t.attach.items():
        if rn in v9.V9_NON_STACK:
            continue
        if sv.REINF[rn]["tag"] != sv.TOWERS[t.ctype]["tag"]:
            continue
        s *= sv.softcap_pow(lv, kappa_i, cap, decay)
    return s


def compute_dps_v11(player, cfg, geo=None):
    total, info = v9.compute_dps_v9(player, cfg, geo)
    if cfg.get("v11_stack", "sum") != "prod":
        return total, info
    per = info["per_tower"]
    if not per:
        return total, info
    sub = 0.0
    for i, t in enumerate(player.towers):
        ss = per[i]["stack"]
        sp = _stack_prod(t, info["kappa"][i], info["caps"][i], cfg["softcap_decay"])
        if ss > 0 and sp != ss:
            per[i]["dps"] *= sp / ss
        per[i]["stack"] = sp
        sub += per[i]["dps"]
    info["subtotal"] = sub
    return sub * info["aoe"] * info["crossfire"] * info["aux"] * info["empower"], info


def _pt_dps(player, cfg, geo):
    _, info = compute_dps_v11(player, cfg, geo)
    return {t.slot: info["per_tower"][i]["dps"] for i, t in enumerate(player.towers)}


# =============================================================================
# 2. 摄灵：邻接 + 搬运
# =============================================================================
def _adj_towers(player, cfg, geo, slot):
    gtypes = [None] * geo.n
    for t in player.towers:
        gtypes[t.slot] = t.ctype
    nbrs = geo.links(gtypes, cfg["link_rule"])[slot]
    return [t for t in player.towers if t.slot in nbrs and t.slot != slot]


def siphon_step(player, cfg, geo, dst_slot, pick="dps"):
    """把相邻「血包」的 1 点 h 搬到 dst。返回 (ok, src_slot, delta_h_used)。"""
    dst = next((t for t in player.towers if t.slot == dst_slot), None)
    if dst is None:
        return False
    cands = [t for t in _adj_towers(player, cfg, geo, dst_slot)
             if t.h >= SIPHON_MIN_DONOR]
    if not cands:
        return False
    if pick == "h":                      # GDD 原文口径：相邻 h 最高
        src = max(cands, key=lambda t: (t.h, -t.slot))
    else:                                # 数据口径：相邻 DPS 最高（h 最高 ≠ 输出最高）
        d = _pt_dps(player, cfg, geo)
        src = max(cands, key=lambda t: (d.get(t.slot, 0.0), t.h))
    src.h -= 1
    dst.h += 1
    return True


def trigger_siphons(player, cfg, geo, around_slot):
    """重触发 around_slot 的**相邻塔**上的 Siphon（每层触发一次）。"""
    n = 0
    for t in _adj_towers(player, cfg, geo, around_slot):
        lv = t.attach.get("Siphon", 0)
        for _ in range(lv):
            if siphon_step(player, cfg, geo, t.slot, cfg.get("v11_pick", "dps")):
                n += 1
    return n


# =============================================================================
# 3. 动作：装入 / 估值
# =============================================================================
def apply_action_v11(player, act, cfg, geo):
    kind, name, slot, extra = act
    if name not in V11_CARDS:
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
    t.attach[name] = t.attach.get(name, 0) + 1
    if name == "Siphon":
        siphon_step(player, cfg, geo, slot, cfg.get("v11_pick", "dps"))
    return V11_CARDS[name]["price"]


def action_value_v11(player, act, cfg, geo):
    kind, name, slot, extra = act
    if name in V11_CARDS:
        s = player.snap()
        before = compute_dps_v11(player, cfg, geo)[0]
        if apply_action_v11(player, act, cfg, geo) is None:
            player.rest(s)
            return None
        after = compute_dps_v11(player, cfg, geo)[0]
        player.rest(s)
        return after - before, V11_CARDS[name]["price"]
    return v9.action_value_v9(player, act, cfg, geo)


def enumerate_actions_v11(player, cfg, fire_bought, offers=None, geo=None, unlocked=False):
    acts = list(v9.enumerate_actions_v9(player, cfg, fire_bought, offers, geo))
    if not cfg.get("v11_card2"):
        acts = [a for a in acts if a[1] != PROBE_CARD]
    if not cfg.get("v11_siphon"):
        return acts
    for name, meta in V11_CARDS.items():
        if meta["role"] == "engine" and not unlocked:
            continue
        if offers is not None and name not in offers:
            continue
        for t in player.towers:
            if name in player.cards:
                acts.append(("reinf", name, t.slot, None))
            elif len(player.cards) < cfg["backpack"]:
                acts.append(("reinf_new", name, t.slot, None))
            else:
                drop = sv.weakest_card(player, cfg, geo)
                if drop is not None and drop != name:
                    acts.append(("reinf_swap", name, t.slot, drop))
    return acts


# =============================================================================
# 4. 商店
# =============================================================================
def pool_weights_v11(cfg, unlocked=False):
    w = dict(v9.pool_weights(cfg))
    if cfg.get("v11_card2"):
        w[PROBE_CARD] = sv.WEIGHTS["FireUp"]        # 与 FireUp 同权重 = 完全等价
    if cfg.get("v11_siphon"):
        w["Siphon"] = V11_CARDS["Siphon"]["w"]      # 成员卡：初始池
        if unlocked:
            w["Conduit"] = V11_CARDS["Conduit"]["w"]   # 发动机：链内解锁
    return w


def draw_offers_v11(rng, cfg, k=3, force=None, unlocked=False):
    w = pool_weights_v11(cfg, unlocked)
    names = list(w)                                  # 保序：RNG 契约
    s = set(rng.choices(names, weights=[w[n] for n in names], k=k))
    if force:
        s.add(force)
        while len(s) > k:
            s.discard(rng.choice(sorted(s - {force})))
    return s


def shop_phase_v11(player, budget, w, cfg, geo, rng, st):
    fl = st["free_layers"]
    rerolls = 0
    actions = 0
    fire_bought = 0
    counts = {}
    offers = None
    unlocked = "Siphon" in player.cards
    if rng is not None:
        offers = draw_offers_v11(rng, cfg, cfg["shop_offers"],
                                 sv.pity_card(player) if cfg.get("pity") else None,
                                 unlocked=unlocked)
    while budget > 0:
        if cfg["max_actions"] is not None and actions >= cfg["max_actions"]:
            break
        cands = enumerate_actions_v11(player, cfg, fire_bought, offers, geo, unlocked)
        scored = []
        for act in cands:
            v = action_value_v11(player, act, cfg, geo)
            if v is None:
                continue
            gain, _ = v
            cost = sv.action_cost(act, cfg, counts)
            if gain <= 0 or budget < cost:
                continue
            scored.append((gain / cost, act, cost))
        if scored:
            if rng is not None and cfg["skill"] < 1.0 and rng.random() > cfg["skill"]:
                pick = scored[rng.randrange(len(scored))]
            else:
                pick = max(scored, key=lambda x: x[0])
            _, act, cost = pick
            if apply_action_v11(player, act, cfg, geo) is None:
                break
            if sv.ALL_CARDS.get(act[1], {}).get("tag") == "fire":
                fire_bought += 1
            counts[act[1]] = counts.get(act[1], 0) + 1
            budget -= cost
            actions += 1
            if act[1] == "Siphon":
                st["siphon_bought"] += 1
                st["siphon_log"].append(w)
            elif act[1] == "Conduit":
                st["conduit_bought"] += 1
                st["conduit_log"].append(w)
            elif act[1] == PROBE_CARD:
                st["probe_bought"] += 1
                st["probe_log"].append(w)
            v8._sync_free_layers(player, fl)
            st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
            player.n_hist_max = st["n_hist_max"]
            unlocked = "Siphon" in player.cards
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
            offers = draw_offers_v11(rng, cfg, cfg["shop_offers"],
                                     sv.pity_card(player) if cfg.get("pity") else None,
                                     unlocked=unlocked)
        elif rerolls > 400:
            break
    return budget, rerolls


# =============================================================================
# 5. 主循环
# =============================================================================
def run_v11(path, cfg, max_wave=20, geo=None, rng=None):
    cfg = dict(cfg)
    if geo is None:
        geo = sv.GEO6 if cfg["n_slots"] >= 6 else sv.GEO4
    player = sv.new_player(path, cfg, geo)
    player.charge_cond = {}
    player.last_share = {}
    st = dict(free_layers={0: 1}, n_hist_max=len(player.towers), log=[],
              siphon_bought=0, conduit_bought=0, probe_bought=0,
              siphon_log=[], conduit_log=[], probe_log=[],
              conduit_fired=0, siphon_ok=0, siphon_fail=0)
    player.n_hist_max = st["n_hist_max"]
    core_hp = cfg["core_hp"]
    rows = []
    cum = 0.0
    cum_rerolls = 0
    conduit_used = {}

    for w in range(1, max_wave + 1):
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]

        # ---- 波开始：Conduit 重触发（每塔位每局 3 次）----
        if cfg.get("v11_siphon"):
            for t in player.towers:
                if t.attach.get("Conduit", 0) <= 0:
                    continue
                used = conduit_used.get(t.slot, 0)
                if used >= CONDUIT_PER_SLOT:
                    continue
                conduit_used[t.slot] = used + 1
                st["conduit_fired"] += 1
                trigger_siphons(player, cfg, geo, t.slot)

        res = sv.simulate_wave(player, w, cfg, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income

        budget, rr = shop_phase_v11(player, cum, w, cfg, geo, rng, st)
        cum = budget
        cum_rerolls += rr
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]
        dps, _ = compute_dps_v11(player, cfg, geo)
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
# 6. 实验格
# =============================================================================
def make_cfg(path, kw, **over):
    c = v8.cfg_of(path)
    for k, v in kw.items():
        c[k] = v
    c.update(over)
    return c


CELLS = [
    ("base",      dict(v9_charge=False, v9_relay=False, v9_pad=0)),
    ("prod",      dict(v9_charge=False, v9_relay=False, v9_pad=0, v11_stack="prod")),
    ("card2sum",  dict(v9_charge=False, v9_relay=False, v9_pad=0, v11_card2=True)),
    ("card2prod", dict(v9_charge=False, v9_relay=False, v9_pad=0, v11_card2=True,
                       v11_stack="prod")),
    ("siphon",    dict(v9_charge=False, v9_relay=False, v9_pad=0, v11_siphon=True)),
    ("siphprod",  dict(v9_charge=False, v9_relay=False, v9_pad=0, v11_siphon=True,
                       v11_stack="prod")),
]


def eval_cell(name, kw, runs_mc=0, seed=v8.SEED1):
    out = dict(cell=name, kw=dict(kw))
    sts = {}
    for path in ("A", "B"):
        rows, player, st = run_v11(path, make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        s = v6.summarize(rows)
        sts[path] = dict(rows=rows, s=s, player=player, st=st)
    sA, sB = sts["A"]["s"], sts["B"]["s"]
    w20A, w20B = sA["w20"] or 0.0, sB["w20"] or 0.0
    out.update(toA=sA["takeoff"], toB=sB["takeoff"], w20A=round(w20A, 2),
               w20B=round(w20B, 2), ba=round(w20B / w20A, 3) if w20A else 0.0,
               st=sts)
    if runs_mc:
        mc = {}
        for path in ("A", "B"):
            rng = random.Random(seed)
            cfg = make_cfg(path, kw)
            cfg["max_actions"] = cfg.get("max_actions") or 12
            ok = hits = 0
            tos = []
            agg = dict(siphon_bought=0, conduit_bought=0, probe_bought=0,
                       conduit_fired=0)
            for _ in range(runs_mc):
                rows, player, st = run_v11(path, cfg, 20, geo=sv.GEO6, rng=rng)
                alive = bool(rows) and rows[-1]["core_hp"] > 0
                tw = sv.takeoff_wave(rows)
                if alive:
                    ok += 1
                    if tw is not None:
                        hits += 1
                        tos.append(tw)
                for k in agg:
                    agg[k] += st.get(k, 0)
            mc[path] = dict(rate=round(hits / runs_mc, 3), surv=round(ok / runs_mc, 3),
                            med=statistics.median(tos) if tos else None,
                            per_run={k: round(v / runs_mc, 2) for k, v in agg.items()})
        out["mc"] = mc
    return out


# =============================================================================
# 7. 输出
# =============================================================================
HDR = ("| 实验格    | toA  | toB  |   W20-A  |   W20-B  |  B/A   | A率   | B率   | 备注\n"
       "|-----------|------|------|----------|----------|--------|-------|-------|-----")


def _note(r):
    stA = r["st"]["A"]["st"]
    stB = r["st"]["B"]["st"]
    bits = []
    for lbl, st in (("A", stA), ("B", stB)):
        if st.get("probe_bought"):
            bits.append(f"{lbl}探针{st['probe_bought']}次")
        if st.get("siphon_bought"):
            bits.append(f"{lbl}摄灵{st['siphon_bought']}/导管{st['conduit_bought']}"
                        f"@{st['siphon_log'][:1]}")
    return "；".join(bits) or "—"


def fmt_row(r):
    def n(v):
        return "—" if v is None else str(v)
    mc = r.get("mc") or {}
    a, b = mc.get("A", {}), mc.get("B", {})
    return (f"| {r['cell']:<9} | {n(r['toA']):>4} | {n(r['toB']):>4} | "
            f"{r['w20A']:>8.2f} | {r['w20B']:>8.2f} | {r['ba']:>6.3f} | "
            f"{n(a.get('rate')):>6} | {n(b.get('rate')):>6} | {_note(r)}")


def selfcheck():
    """v11 默认开关下必须与 v10 逐位一致（Stack 模式 = sum、无新卡）。"""
    worst = 0.0
    for path in ("A", "B"):
        kw = dict(v9_charge=False, v9_relay=False, v9_pad=0, v10_pity2=False)
        r9, _, _ = v9.run_v9(path, v9.make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        r11, _, _ = run_v11(path, make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        if len(r9) != len(r11):
            return float("inf")
        for a, b in zip(r9, r11):
            worst = max(worst, abs(a["eff_dps"] - b["eff_dps"]))
    return worst


def run_det():
    print("=" * 108)
    print("v0.11 决定性对照（rng=None，理性 AI，GEO6，20 波）")
    print("=" * 108)
    rows = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw)
        rows.append(r)
        print(f"[{name}] {time.time()-t0:.1f}s")
    print()
    print(HDR)
    for r in rows:
        print(fmt_row(r))
    base = next(r for r in rows if r["cell"] == "base")
    print()
    print("相对 base 的偏移：")
    for r in rows:
        if r["cell"] == "base":
            continue
        dA = (r["toA"] - base["toA"]) if (r["toA"] and base["toA"]) else None
        print(f"  {r['cell']:<9} toA {dA if dA is None else format(dA,'+d')}"
              f"  W20A {r['w20A']-base['w20A']:+10.2f}"
              f"  W20B {r['w20B']-base['w20B']:+10.2f}  B/A {r['ba']-base['ba']:+.3f}")
    return rows


def probe(wave_len=12):
    """在真实 W12 状态上枚举全部动作的 gain/cost，看摄灵排第几。"""
    print("=" * 108)
    print(f"动作性价比探针（W{wave_len} 停留态，理性 AI 视角）")
    print("=" * 108)
    for cell_name, kw in (("base", CELLS[0][1]),
                          ("siphon", dict(CELLS[0][1], v11_siphon=True)),
                          ("card2sum", dict(CELLS[0][1], v11_card2=True)),
                          ("card2prod", dict(CELLS[0][1], v11_card2=True, v11_stack="prod"))):
        for path in ("A", "B"):
            cfg = make_cfg(path, kw)
            p = sv.new_player(path, cfg, sv.GEO6)
            core_hp = cfg["core_hp"]
            cum = 0.0
            st = dict(free_layers={0: 1}, n_hist_max=1, siphon_bought=0, conduit_bought=0,
                      probe_bought=0, siphon_log=[], conduit_log=[], probe_log=[],
                      conduit_fired=0, siphon_ok=0, siphon_fail=0)
            p.n_hist_max = 1
            for w in range(1, wave_len + 1):
                res = sv.simulate_wave(p, w, cfg, sv.GEO6)
                core_hp -= res["core_damage"]
                cum += res["scrap_earned"] * (1.0 + p.income_mult)
                cum, _ = shop_phase_v11(p, cum, w, cfg, sv.GEO6, None, st)
            d0 = compute_dps_v11(p, cfg, sv.GEO6)[0]
            unlocked = "Siphon" in p.cards
            acts = enumerate_actions_v11(p, cfg, 0, None, sv.GEO6, unlocked)
            scored = []
            for act in acts:
                v = action_value_v11(p, act, cfg, sv.GEO6)
                if v is None:
                    continue
                gain, _ = v
                cost = sv.action_cost(act, cfg, {})
                scored.append((gain / cost if cost else 0, act, gain, cost))
            scored.sort(key=lambda x: -x[0])
            print(f"\n--- [{cell_name}] 路径 {path} · W{wave_len} · DPS {d0:.0f}"
                  f" · 卡种 {sorted(p.cards)} ---")
            print(f"  {'排名':<4}{'动作':<26}{'ΔDPS':>12}{'价':>6}{'ΔDPS/分':>11}")
            for i, (r, act, gain, cost) in enumerate(scored[:6], 1):
                lbl = f"{act[0]}:{act[1]}@{act[2]}"
                print(f"  {i:<4}{lbl:<26}{gain:>12.1f}{cost:>6.0f}{r:>11.1f}")
    print()


def run_mc(runs=300):
    print("=" * 108)
    print(f"v0.11 蒙特卡洛（{runs} 局/路径，seed={v8.SEED1}）")
    print("=" * 108)
    rows = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw, runs_mc=runs)
        rows.append(r)
        a, b = r["mc"]["A"], r["mc"]["B"]
        print(f"[{name}] {time.time()-t0:.0f}s  A率 {a['rate']} B率 {b['rate']}  "
              f"A探针/局 {a['per_run']['probe_bought']} A摄灵/局 {a['per_run']['siphon_bought']}")
    print()
    print(HDR)
    for r in rows:
        print(fmt_row(r))
    print()
    print("每局平均购入次数（A 路径 / B 路径）：")
    print("| 实验格    | 探针A | 探针B | 摄灵A | 导管A | 导管触发A |")
    print("|-----------|-------|-------|-------|-------|-----------|")
    for r in rows:
        a, b = r["mc"]["A"]["per_run"], r["mc"]["B"]["per_run"]
        print(f"| {r['cell']:<9} | {a['probe_bought']:>5} | {b['probe_bought']:>5} | "
              f"{a['siphon_bought']:>5} | {a['conduit_bought']:>5} | {a['conduit_fired']:>9} |")
    return rows


def run_seeds(seeds, runs=300):
    print("=" * 108)
    print(f"v0.11 多种子（{len(seeds)} seeds × {runs} 局/路径）")
    print("=" * 108)
    res = {}
    for name, kw in CELLS:
        res[name] = []
        for sd in seeds:
            r = eval_cell(name, kw, runs_mc=runs, seed=sd)
            res[name].append((r["mc"]["A"]["rate"], r["mc"]["B"]["rate"]))
    print("| 实验格    | A率(逐 seed)              | A均值 | B率(逐 seed)              | B均值 |")
    print("|-----------|---------------------------|-------|---------------------------|-------|")
    for name, _ in CELLS:
        a = [x[0] for x in res[name]]
        b = [x[1] for x in res[name]]
        print(f"| {name:<9} | {' '.join(f'{v:.3f}' for v in a):<25} | "
              f"{statistics.mean(a):>5.3f} | {' '.join(f'{v:.3f}' for v in b):<25} | "
              f"{statistics.mean(b):>5.3f} |")
    return res


def sweep():
    """「同价不同效」横截面：同样 9 分，各种买法的 ΔDPS 与每分效。

    对象 = 该路径 W 时刻 DPS 最高的塔（理性 AI 会把资源集中到它身上）。
    """
    print("=" * 108)
    print("定价横截面：同样 9 分，买什么最值")
    print("=" * 108)
    for path in ("A", "B"):
        for want in (8, 12, 16):
            cfg = make_cfg(path, dict(v9_charge=False, v9_relay=False, v9_pad=0,
                                      v11_card2=True))
            p = sv.new_player(path, cfg, sv.GEO6)
            st = dict(free_layers={0: 1}, n_hist_max=1, siphon_bought=0, conduit_bought=0,
                      probe_bought=0, siphon_log=[], conduit_log=[], probe_log=[],
                      conduit_fired=0, siphon_ok=0, siphon_fail=0)
            p.n_hist_max = 1
            core_hp = cfg["core_hp"]
            cum = 0.0
            for w in range(1, want + 1):
                res = sv.simulate_wave(p, w, cfg, sv.GEO6)
                core_hp -= res["core_damage"]
                cum += res["scrap_earned"] * (1.0 + p.income_mult)
                cum, _ = shop_phase_v11(p, cum, w, cfg, sv.GEO6, None, st)

            d0 = compute_dps_v11(p, cfg, sv.GEO6)[0]
            if d0 <= 0:
                continue
            tg = max(p.towers, key=lambda t: _pt_dps(p, cfg, sv.GEO6).get(t.slot, 0.0))
            fire_lv = tg.attach.get("FireUp", 0) if sv.TOWERS[tg.ctype]["tag"] == "fire" else 0
            d_fire = _marg_layer(p, cfg, tg, "FireUp")
            d_new_sum = _marg_layer(p, cfg, tg, PROBE_CARD)
            cfg_p = dict(cfg); cfg_p["v11_stack"] = "prod"
            p2 = sv.new_player(path, cfg_p, sv.GEO6)
            print(f"\n--- 路径 {path} · W{want} · 基准 DPS {d0:.0f} · 主塔 塔{tg.slot}"
                  f"（{tg.ctype} h={tg.h} FireUp×{fire_lv}）---")
            print(f"  {'买法':<26}{'ΔDPS':>12}{'Δ%':>8}{'每分效':>10}")
            print(f"  {'FireUp +1 层':<26}{d_fire:>12.1f}{d_fire/d0*100:>7.2f}%{d_fire/9:>10.1f}")
            print(f"  {'新火卡首层(和式)':<26}{d_new_sum:>12.1f}"
                  f"{d_new_sum/d0*100:>7.2f}%{d_new_sum/9:>10.1f}")
            # 摄灵：搬 k 点 h（从相邻 DPS 最高的塔）
            base_h = [(t.slot, t.h) for t in p.towers]
            row = []
            for k in (1, 2, 3, 4, 6, 8):
                for t in p.towers:
                    t.h = dict(base_h)[t.slot]
                ok = 0
                for _ in range(k):
                    if siphon_step(p, cfg, sv.GEO6, tg.slot, pick="dps"):
                        ok += 1
                if ok == 0:
                    continue
                dk = compute_dps_v11(p, cfg, sv.GEO6)[0] - d0
                row.append((k, ok, dk, dk / 9))
            for t in p.towers:
                t.h = dict(base_h)[t.slot]
            for k, ok, dk, eff in row:
                print(f"  {'摄灵搬 %d 点 h' % k:<26}{dk:>12.1f}{dk/d0*100:>7.2f}%{eff:>10.1f}")
            if row:
                need = next((k for k, ok, dk, e in row if e >= d_fire / 9), None)
                print(f"  ⇒ 摄灵要追平 FireUp 一层，每层需搬 **{need if need else '>8'}** 点 h"
                      f"（现设计 1 点）")
            if d_fire > 0:
                print(f"  ⇒ 新火卡首层 / FireUp 层 = {d_new_sum / d_fire:.3f}"
                      f"（<1 表示永不值得买）")


def _marg_layer(p, cfg, t, name):
    d0 = compute_dps_v11(p, cfg, sv.GEO6)[0]
    old = t.attach.get(name, 0)
    t.attach[name] = old + 1
    d1 = compute_dps_v11(p, cfg, sv.GEO6)[0]
    if old:
        t.attach[name] = old
    else:
        t.attach.pop(name, None)
    return d1 - d0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "det"
    t0 = time.time()
    d = selfcheck()
    print(f"[selfcheck] 默认开关下 v11 vs v9 逐波 DPS 最大绝对差：{d:.3e}"
          f"（必须 = 0.000e+00）\n")
    if mode == "det":
        run_det()
    elif mode == "probe":
        probe()
    elif mode == "sweep":
        sweep()
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    elif mode == "seeds":
        run_seeds([v8.SEED1 + i for i in range(3)],
                  int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    elif mode == "all":
        run_det()
        print()
        probe()
        print()
        run_mc(300)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
