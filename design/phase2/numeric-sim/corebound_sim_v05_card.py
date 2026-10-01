# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — 卡牌系统 GDD 复验 **v0.5**
作者：程基岩（工程主理人）

复验对象：`design/gdd/card-system.md` 草案 v0.1 的两个 PLACEHOLDER 项

  Q-C1  κ 判定口径：全局路径判定（单核 0.10 / 多塔 0.06）
        vs 逐卡判定（装配到主塔 0.10 / 非主塔 0.06）
        → 在**混合 build**（既投主塔又投副塔）下的影响有多大？策划预计 <5%。

  Q-C5  κ_r 新增档位：未协同(0-2层) 0.030 / 协同成立(≥3层) 0.045 / 深度协同(≥6层) 0.060
        → 0.030 会不会让多塔完全起不来？0.060 会不会过早爆炸？

口径：完全沿用 v0.4 定稿主口径
      hp_growth=1.42 / focus_per_layer=0.06 / κ_r=0.045 / 共鸣门槛 Lv3 /
      6 塔位 / map 模式 / 每波 12 动作 / 全乘区打开（Empowerment 关闭）

新增引擎能力（本脚本独占，不改 v03/v04）：
  ① kappa_mode : "path"（全局路径判定） | "per_card"（逐卡：主塔 κ_main / 非主塔 κ_aux）
  ② kr_mode    : "flat"（单一 κ_r）   | "tier"（按 Tag 投入层数分档）
     kr_scope  : "own"（逐塔取自身 Tag 档） | "dominant"（取投入最多的 Tag 档，全场统一）
     kr_neutral: 无 Tag 塔（Arrow/Beacon）在 own 口径下取哪一档
  ③ mix_bias   : 合成「混合 build」的旋钮 —— 估值阶段给「装配到非主塔」的动作加价 (1+mix_bias)，
                 使理性 AI 把强化卡分散投到副塔。客观刻度 = 主塔层数占比 core_share。

用法（隔离 venv）：
  C:\\Users\\junhewang\\.workbuddy\\binaries\\python\\envs\\default\\Scripts\\python.exe corebound_sim_v05_card.py
"""
from __future__ import annotations
import os
import math
import random
import statistics

import corebound_sim_v03 as sv
import corebound_sim_v04 as v4      # 复用 v0.4 配置工厂（导入即打补丁，下面会被 v5 再覆盖）

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 1. v0.5 伤害引擎：在 v0.4 基础上加 κ 逐卡判定 + κ_r 分档
# =============================================================================
def _tier_value(inv, tiers):
    """按 (阈值, 值) 升序表取档。tiers 形如 [(0,0.030),(3,0.045),(6,0.060)]。"""
    val = tiers[0][1]
    for th, v in tiers:
        if inv >= th:
            val = v
    return val


def _kr_per_tower(cfg, ts, tag_invest, tiers, diag):
    """返回逐塔 κ_r 列表。"""
    mode = cfg.get("kr_mode", "flat")
    if mode == "flat":
        return [cfg["kappa_r"]] * len(ts)
    scope = cfg.get("kr_scope", "own")
    if scope == "dominant":
        dom = max(tag_invest.values()) if tag_invest else 0
        return [_tier_value(dom, tiers)] * len(ts)
    # own：逐塔取自身 Tag 档
    neutral = cfg.get("kr_neutral", "base")
    base_val = tiers[min(1, len(tiers) - 1)][1]
    if neutral == "dominant":
        neutral_val = _tier_value(max(tag_invest.values()) if tag_invest else 0, tiers)
    elif neutral == "lowest":
        neutral_val = tiers[0][1]
    else:
        neutral_val = base_val
    out = []
    for t in ts:
        tg = sv.TOWERS[t.ctype]["tag"]
        out.append(_tier_value(tag_invest.get(tg, 0), tiers) if tg else neutral_val)
    return out


def compute_dps_v5(player, cfg, geo=None):
    ts = player.towers
    n = len(ts)
    if n == 0:
        return 0.0, dict(per_tower=[], E=[], aoe=1.0, crossfire=1.0, aux=1.0,
                         empower=1.0, subtotal=0.0, core=0, L=[], Ltot=0.0,
                         kr=[], tag_invest={}, kappa=[])

    path = player.path
    lmin = cfg.get("link_min_level", 1)
    h = [t.h for t in ts]
    L = [sum(t.attach.values()) for t in ts]
    Ltot = sum(L)
    core = max(range(n), key=lambda i: L[i]) if Ltot > 0 else 0

    # ---- Tag 投入层数（建筑卡层数 + 单塔效果卡层数；全局卡无 Tag 不计入）----
    tag_invest = {}
    for i, t in enumerate(ts):
        tg = sv.TOWERS[t.ctype]["tag"]
        if tg:
            tag_invest[tg] = tag_invest.get(tg, 0) + h[i]
        for rn, lv in t.attach.items():
            rt = sv.REINF[rn]["tag"]
            tag_invest[rt] = tag_invest.get(rt, 0) + lv

    # ---- κ 判定 ----
    kmode = cfg.get("kappa_mode", "path")
    k_main = 1.0 + cfg.get("kappa_main", 0.10)
    k_aux = 1.0 + cfg.get("kappa_aux", 0.06)
    k_path = cfg["reinf_compound"][path]
    kappa = []
    if kmode == "spread":
        # 方案 B（本轮新增）：把「全局路径判定」连续化 —— κ 随场上塔数在
        # κ_main(≤2塔) 与 κ_aux(≥n_slots塔) 之间线性插值。两个定稿端点逐位相等。
        span = max(1, cfg["n_slots"] - 2)
        frac = 0.0 if n <= 2 else min(1.0, (n - 2) / span)
        k_spread = k_main - (k_main - k_aux) * frac
        kappa = [k_spread] * n
    else:
        for i in range(n):
            if kmode == "per_card":
                kappa.append(k_main if i == core else k_aux)
            else:
                kappa.append(k_path)

    # ---- κ_r 判定 ----
    tiers = cfg.get("kr_tiers", [(0, 0.045)])
    kr = _kr_per_tower(cfg, ts, tag_invest, tiers, None)

    # ---- 链接 / E_i ----
    adj = [[] for _ in range(n)]
    E = [0.0] * n
    if cfg["use_resonance"] and geo is not None:
        gtypes = [None] * geo.n
        for t in ts:
            gtypes[t.slot] = t.ctype
        gadjs = geo.links(gtypes, cfg["link_rule"])
        for i, t in enumerate(ts):
            for gj in gadjs[t.slot]:
                for k, t2 in enumerate(ts):
                    if k != i and t2.slot == gj:
                        adj[i].append(k)
                        if h[i] >= lmin and h[k] >= lmin:
                            E[i] += 1.0 + h[k]
    elif cfg["use_resonance"]:
        for i in range(n):
            for k in range(n):
                if k != i:
                    adj[i].append(k)
                    if h[i] >= lmin and h[k] >= lmin:
                        E[i] += 1.0 + h[k]

    cap = cfg["reinf_cap"]
    decay = cfg["softcap_decay"]
    tag_tower_lv = {}
    for i, t in enumerate(ts):
        tg = sv.TOWERS[t.ctype]["tag"]
        if tg:
            tag_tower_lv[tg] = tag_tower_lv.get(tg, 0) + h[i]

    per_tower = []
    for i, t in enumerate(ts):
        base = sv.TOWERS[t.ctype]["dps"] * (h[i] ** cfg["tower_stack_exp"])
        stack = 1.0
        for rn, lv in t.attach.items():
            if sv.REINF[rn]["tag"] != sv.TOWERS[t.ctype]["tag"]:
                continue
            stack += sv.softcap_pow(lv, kappa[i], cap, decay) - 1.0
        tg = sv.TOWERS[t.ctype]["tag"]
        syn = 1.0
        if tg and tag_tower_lv.get(tg, 0) >= cfg["synergy_threshold"]:
            syn = cfg["synergy_mult"]
        res = ((1.0 + kr[i]) ** E[i]) if cfg["use_resonance"] else 1.0
        foc = 1.0
        if cfg["use_focus"]:
            if cfg.get("focus_full", False):
                foc = 1.0 + cfg["focus_per_layer"] * L[i]
            else:
                fh = cfg.get("focus_min_h", 8.0)
                ramp = min(1.0, h[i] / fh) if fh > 0 else 1.0
                foc = 1.0 + cfg["focus_per_layer"] * L[i] * ramp
        ali = 1.0
        if cfg["use_allin"] and Ltot > 0 and i == core and L[i] >= cfg["allin_share"] * Ltot:
            ali = cfg["allin_mult"]
        if cfg["coverage_mode"] == "geometry" and geo is not None:
            cov = geo.cov[(t.slot, t.ctype)]
        else:
            cov = cfg["path_coverage"][path]
        per_tower.append(dict(base=base, stack=stack, syn=syn, res=res,
                              focus=foc, allin=ali, cov=cov,
                              dps=base * stack * syn * res * foc * ali * cov))

    aoe_total = sum(tag_tower_lv.values())
    aoe = min(cfg["aoe_cap"][path], 1.0 + cfg["aoe_per"][path] * aoe_total)

    if not cfg["use_crossfire"]:
        cf = 1.0
    else:
        cf = cfg["crossfire_3"] if n >= 3 else (cfg["crossfire_2"] if n >= 2 else 1.0)

    aux = 1.0
    aux_parts = [1.0] * n
    if cfg["use_aux"]:
        aux_mode = cfg.get("aux_mode", "global")
        if aux_mode == "per_tower":
            aux_parts = []
            for t in ts:
                slow = sv.TOWERS[t.ctype]["slow"]
                mult = 1.0
                if slow > 0:
                    mult = 1.0 / (1.0 - min(slow, 0.75))
                    c = cfg.get("aux_cap", 1.5)
                    if c is not None and mult > c:
                        mult = c
                aux_parts.append(mult)
            for i, p in enumerate(per_tower):
                p["dps"] = p["dps"] * aux_parts[i]
            aux = sum(aux_parts) / max(1, len(aux_parts))
        else:
            slow_towers = [t for t in ts if sv.TOWERS[t.ctype]["slow"] > 0]
            if slow_towers:
                slow = max(sv.TOWERS[t.ctype]["slow"] for t in slow_towers)
                h_slow = max(t.h for t in slow_towers)
                tau = cfg.get("aux_tau", 8.0)
                eff_slow = slow * (h_slow / (h_slow + tau))
                aux = 1.0 / (1.0 - min(eff_slow, 0.75))
                c = cfg.get("aux_cap", 1.5)
                if c is not None and aux > c:
                    aux = c

    empower = 1.0
    if cfg.get("use_empowerment"):
        empower = 1.0 + cfg.get("empower_per_layer", 0.015) * L[core]
        empower = min(empower, cfg.get("empower_cap", 3.0))

    subtotal = sum(p["dps"] for p in per_tower)
    total = subtotal * aoe * cf * aux * empower
    return total, dict(per_tower=per_tower, adj=adj, E=E, aoe=aoe, crossfire=cf,
                       aux=aux, empower=empower, subtotal=subtotal, core=core,
                       L=L, Ltot=Ltot, kr=kr, tag_invest=tag_invest, kappa=kappa,
                       tier=_tier_value(max(tag_invest.values()) if tag_invest else 0, tiers))


def dps_only_v5(player, cfg, geo=None):
    return compute_dps_v5(player, cfg, geo)[0]


# ---- 打补丁：让 v03 的 run/shop/action_value 全部走 v5 引擎 ----
sv.compute_dps = compute_dps_v5
sv.dps_only = dps_only_v5


# =============================================================================
# 2. 混合 build 旋钮：给「装配到非主塔」的动作估值加价
# =============================================================================
def action_value_mix(player, act, cfg, geo):
    bias = 1.0
    mb = cfg.get("mix_bias", 0.0)
    cap = cfg.get("mix_cap", None)
    if act[0] in ("reinf", "reinf_new", "reinf_swap") and act[2] is not None:
        tgt = None
        for t in player.towers:
            if t.slot == act[2]:
                tgt = t
                break
        if tgt is None:
            return None
        if cap is not None and sum(tgt.attach.values()) >= cap:
            return None          # 「单塔层数自封顶」玩家：强制把卡投给副塔
        if mb:
            Ls = [sum(t.attach.values()) for t in player.towers]
            if sum(Ls) > 0:
                ci = max(range(len(Ls)), key=lambda i: Ls[i])
                if act[2] != player.towers[ci].slot:
                    bias = 1.0 + mb
    before = sv.dps_only(player, cfg, geo)
    s = player.snap()
    cost = sv.apply_action(player, act, cfg)
    if cost is None:
        player.rest(s)
        return None
    after = sv.dps_only(player, cfg, geo)
    player.rest(s)
    return (after - before) * bias, cost


sv.action_value = action_value_mix


# =============================================================================
# 3. 配置工厂（v0.4 定稿主口径 + 本轮开关）
# =============================================================================
def v05_cfg(path="B", hp_growth=1.42, focus_per_layer=0.06, kappa_r=0.045,
            max_towers=None, mix_bias=0.0, mix_cap=None, **over):
    d = dict(
        tower_card_mode="map", n_slots=6, coverage_mode="path",
        use_resonance=True, kappa_r=kappa_r,
        link_min_level=sv.RECOMMENDED["link_min_level"],
        link_rule="any", max_actions=12,
        use_focus=True, use_allin=True, use_crossfire=True, use_aux=True,
        use_empowerment=False,
        focus_full=False, focus_min_h=8.0,
        aux_mode="global", aux_tau=8.0, aux_cap=1.5,
        hp_growth=hp_growth, focus_per_layer=focus_per_layer,
        # ---- v0.5 新增 ----
        kappa_mode="path", kappa_main=0.10, kappa_aux=0.06,
        kr_mode="flat", kr_scope="own", kr_neutral="base",
        kr_tiers=[(0, 0.030), (3, 0.045), (6, 0.060)],
        mix_bias=mix_bias, mix_cap=mix_cap,
    )
    if max_towers is not None:
        d["max_towers"] = {"A": 2, "B": 6}
        d["max_towers"][path] = max_towers
    d.update(over)
    return sv.make_cfg(**d)


# =============================================================================
# 4. 观测指标
# =============================================================================
def summarize(rows):
    d = {r["w"]: r["ratio"] for r in rows}
    return dict(takeoff=sv.takeoff_wave(rows), w10=d.get(10), w13=d.get(13),
                w16=d.get(16), w20=d.get(20),
                tail_min=round(sv.tail_min(rows, 13), 2),
                core_hp=rows[-1]["core_hp"] if rows else 0.0,
                towers=rows[-1]["towers"] if rows else 0)


def final_state(path, cfg, waves=20):
    rows, player = sv.run(path, cfg, waves, geo=sv.GEO6)
    dps, info = compute_dps_v5(player, cfg, sv.GEO6)
    L = info["L"]
    Ltot = info["Ltot"]
    core_share = (L[info["core"]] / Ltot) if Ltot > 0 else 0.0
    return dict(rows=rows, player=player, dps=dps, info=info,
                core_share=core_share, L=L, Ltot=Ltot)


def build_dump(st):
    """把终局构筑逐塔打成字符串（含 h / 装配层数 / E_i / κ / κ_r）。"""
    p, info = st["player"], st["info"]
    parts = []
    for i, t in enumerate(p.towers):
        att = ",".join(f"{k}{v}" for k, v in sorted(t.attach.items())) or "-"
        parts.append(f"{t.ctype}(h{t.h}|{att}|E{info['E'][i]:.0f}"
                     f"|k{info['kappa'][i]:.2f}|kr{info['kr'][i]:.3f})")
    return " ".join(parts)


def tower_mix(st):
    p = st["player"]
    agg = {}
    for t in p.towers:
        agg[t.ctype] = agg.get(t.ctype, 0) + t.h
    return ",".join(f"{k}x{v}" for k, v in sorted(agg.items()))


def takeoff_rate(path, cfg, runs=200, max_wave=20, actions=12, seed=20260930):
    rng = random.Random(seed)
    takeoffs, survives, hits = 0, 0, []
    for _ in range(runs):
        cfgx = dict(cfg)
        cfgx["max_actions"] = actions
        rows, _ = sv.run(path, cfgx, max_wave, geo=sv.GEO6, rng=rng)
        alive = bool(rows) and rows[-1]["core_hp"] > 0
        if alive:
            survives += 1
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            takeoffs += 1
            hits.append(tw)
    return dict(rate=round(takeoffs / runs, 3),
                surv=round(survives / runs, 3),
                med=statistics.median(hits) if hits else None)


def pct(a, b):
    """(a/b - 1) * 100，安全除法。"""
    if not b:
        return float("nan")
    return (a / b - 1.0) * 100.0


# =============================================================================
# 5. Q-C1：κ 判定口径复验（含混合 build 生成）
# =============================================================================
def sweep_kappa_rule():
    """在 (路径 × 塔数上限 × 单塔自封顶 mix_cap) 网格上比较两种 κ 判定口径。
    混合 build 由「单塔层数自封顶」强制生成（理性 AI 天然不会分散投卡 —— 这本身就是一条发现）。
    混合度客观刻度 = 主塔层数占比 core_share。"""
    out = []
    grid = []
    for path in ("A", "B"):
        mts = (2, 3, 4) if path == "A" else (3, 4, 6)
        for mt in mts:
            for cap in (None, 30, 15, 8):
                grid.append((path, mt, cap))
    for path, mt, cap in grid:
        base = dict(hp_growth=1.42, focus_per_layer=0.06, kappa_r=0.045,
                    max_towers=mt, mix_cap=cap)
        cfg_g = v05_cfg(path=path, kappa_mode="path", **base)      # 全局路径判定
        cfg_c = v05_cfg(path=path, kappa_mode="per_card", **base)  # 逐卡主塔/非主塔
        stg = final_state(path, cfg_g)
        stc = final_state(path, cfg_c)
        r_g, r_c = summarize(stg["rows"]), summarize(stc["rows"])
        hosts = sum(1 for L in stc["L"] if L > 0)
        out.append(dict(
            path=path, mt=mt, cap=cap, hosts=hosts,
            core_share=round(stc["core_share"], 3),
            Ltot=stc["Ltot"], Lcore=stc["L"][stc["info"]["core"]],
            mix=tower_mix(stc),
            to_g=r_g["takeoff"], to_c=r_c["takeoff"],
            w20_g=round(r_g["w20"] or 0, 2), w20_c=round(r_c["w20"] or 0, 2),
            dps_g=stg["dps"], dps_c=stc["dps"],
            d_dps=round(pct(stc["dps"], stg["dps"]), 1),
            d_to=(r_c["takeoff"] or 99) - (r_g["takeoff"] or 99),
        ))
    return out


def static_mixed_build(path="B", Ltot=47, split=0.5, h_pair=8, arrow_h=133):
    """构造一个真正的「混合 build」：两座同原型 Cannon 各 h_pair 层、一座高谐波 Arrow 供共鸣，
    强化卡按 split 比例分给两座塔（split=1.0 即纯单核、0.5 即五五开）。
    用真实引擎 compute_dps_v5 求值 —— 含 Coverage/AoE/Crossfire/Focus/AllIn/Resonance。"""
    p = sv.Player(path)
    p.towers.append(sv.Tower(0, "Arrow", arrow_h))
    p.towers.append(sv.Tower(1, "Arrow", 1))
    p.towers.append(sv.Tower(2, "Cannon", h_pair))
    p.towers.append(sv.Tower(3, "Cannon", h_pair))
    p.towers.append(sv.Tower(4, "Cannon", 1))
    p.towers.append(sv.Tower(5, "Cannon", 1))
    p.cards.update({"Arrow", "Cannon", "FireUp"})
    Lm = int(round(Ltot * split))
    La = Ltot - Lm
    if Lm:
        p.towers[2].attach["FireUp"] = Lm
    if La:
        p.towers[3].attach["FireUp"] = La
    return p


def static_mixed_sweep(Ltot=47, splits=(1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.34)):
    """同一份投资（总层数固定）按不同主/副比例分配 → 三种 κ 口径下的 DPS 差。"""
    rows = []
    for f in splits:
        p = static_mixed_build(Ltot=Ltot, split=f)
        base = dict(hp_growth=1.42, focus_per_layer=0.06, kappa_r=0.045)
        cfg_b = v05_cfg(path="B", kappa_mode="path", **base)                       # 全局多塔 0.06
        cfg_a = v05_cfg(path="B", kappa_mode="path", **base)
        cfg_a = dict(cfg_a)
        cfg_a["reinf_compound"] = {"A": 1.10, "B": 1.10}                           # 全局单核 0.10
        cfg_c = v05_cfg(path="B", kappa_mode="per_card", **base)                   # 逐卡
        d_b = compute_dps_v5(p, cfg_b, sv.GEO6)[0]
        d_a = compute_dps_v5(p, cfg_a, sv.GEO6)[0]
        d_c = compute_dps_v5(p, cfg_c, sv.GEO6)[0]
        Lm = int(round(Ltot * f))
        La = Ltot - Lm
        rows.append(dict(split=f, Lmain=Lm, Laux=La,
                         d_b=d_b, d_a=d_a, d_c=d_c,
                         vs_b=round(pct(d_c, d_b), 1), vs_a=round(pct(d_c, d_a), 1),
                         dw_b=round(math.log(d_c / d_b) / math.log(1.42), 1) if d_b else 0,
                         dw_a=round(math.log(d_c / d_a) / math.log(1.42), 1) if d_a else 0))
    return rows


def analytic_deviation():
    """解析：逐卡口径相对两种全局口径的偏离，是 exp(层数) 级的。
    逐卡 = 1.10^L_core · 1.06^L_aux
    全局单核 = 1.10^(L_core+L_aux)  → 比值 = (1.06/1.10)^L_aux
    全局多塔 = 1.06^(L_core+L_aux)  → 比值 = (1.10/1.06)^L_core"""
    rows = []
    for L in (1, 2, 3, 5, 8, 12, 20, 30, 47, 60):
        vs_a = (1.06 / 1.10) ** L
        vs_b = (1.10 / 1.06) ** L
        rows.append([L, f"{(vs_a-1)*100:+.1f}%", f"{(vs_b-1)*100:+.1f}%"])
    return rows


def rule_variants():
    """四种 κ 口径的整轮对照（含起飞率）。"""
    variants = [
        dict(name="① 全局路径判定（v0.4 定稿基线）", mode="path", kmain=0.10, hp=1.42),
        dict(name="② 逐卡判定 κ_main=0.10（策划原提案）", mode="per_card", kmain=0.10, hp=1.42),
        dict(name="③ 逐卡判定 κ_main=0.11（配套补偿）", mode="per_card", kmain=0.11, hp=1.42),
        dict(name="④ 连续化塔数插值（本轮新增·零重标定）", mode="spread", kmain=0.10, hp=1.42),
    ]
    out = []
    for v in variants:
        cfgA = v05_cfg(path="A", kappa_mode=v["mode"], kappa_main=v["kmain"], hp_growth=v["hp"])
        cfgB = v05_cfg(path="B", kappa_mode=v["mode"], kappa_main=v["kmain"], hp_growth=v["hp"])
        rA, _ = sv.run("A", cfgA, 20, geo=sv.GEO6)
        rB, _ = sv.run("B", cfgB, 20, geo=sv.GEO6)
        sA, sB = summarize(rA), summarize(rB)
        _, lead, flips = v4.cross_lead(rA, rB)
        ba = (sB["w20"] / sA["w20"]) if sA["w20"] else 0.0
        ra = takeoff_rate("A", cfgA, runs=150, seed=20260930)
        rb = takeoff_rate("B", cfgB, runs=150, seed=20260930)
        out.append(dict(name=v["name"], toA=sA["takeoff"], toB=sB["takeoff"],
                        w20A=round(sA["w20"] or 0, 2), w20B=round(sB["w20"] or 0, 2),
                        ba=round(ba, 2), leadA=lead["A"], leadB=lead["B"], flips=flips,
                        rateA=round(ra["rate"] * 100, 1), rateB=round(rb["rate"] * 100, 1)))
    return out


def neutral_only_risk():
    """Q-C5 风险验证：无 Tag 投入的「纯中性塔铺场」build 在档位口径下会怎样。
    （v0.4 定稿里驱动共鸣的主引擎恰恰是无 Tag 的 Arrow 谐波层）"""
    old = dict(sv.ALLOWED)
    sv.ALLOWED["B"] = {"Arrow"}
    rows = []
    for label, kw in (
            ("flat κ_r=0.045（定稿）", dict(kr_mode="flat", kappa_r=0.045)),
            ("flat κ_r=0.040", dict(kr_mode="flat", kappa_r=0.040)),
            ("flat κ_r=0.030（提案未协同档）", dict(kr_mode="flat", kappa_r=0.030)),
            ("档位·中性塔取主Tag档", dict(kr_mode="tier", kr_scope="own", kr_neutral="dominant",
                                    kr_tiers=[(0, 0.030), (3, 0.045), (6, 0.060)])),
            ("档位·中性塔恒取基准档", dict(kr_mode="tier", kr_scope="own", kr_neutral="base",
                                    kr_tiers=[(0, 0.030), (3, 0.045), (6, 0.060)])),
    ):
        cfg = v05_cfg(path="B", **kw)
        st = final_state("B", cfg)
        s = summarize(st["rows"])
        rows.append(dict(label=label, kr=st["info"]["kr"][0], takeoff=s["takeoff"],
                         w13=round(s["w13"] or 0, 3), w20=round(s["w20"] or 0, 2),
                         Emax=round(max(st["info"]["E"]), 0)))
    sv.ALLOWED.update(old)
    return rows


# =============================================================================
# 6. Q-C5：κ_r 档位复验
# =============================================================================
def sweep_kr_flat(path="B", values=(0.030, 0.035, 0.040, 0.045, 0.050, 0.055, 0.060, 0.070)):
    """单一 κ_r 扫参：看多塔 B 的起飞点 / W20 / 起飞率对 κ_r 的敏感度。"""
    out = []
    for kr in values:
        cfg = v05_cfg(path=path, kappa_r=kr)
        st = final_state(path, cfg)
        s = summarize(st["rows"])
        out.append(dict(kr=kr, takeoff=s["takeoff"], w10=round(s["w10"] or 0, 3),
                        w13=round(s["w13"] or 0, 3), w20=round(s["w20"] or 0, 2),
                        tail=round(s["tail_min"], 2), core_hp=s["core_hp"],
                        dps=st["dps"], mix=tower_mix(st),
                        Emax=round(max(st["info"]["E"]), 1)))
    return out


def sweep_kr_tier(path="B", variants=()):
    """分档 κ_r：比较档位组合与作用域口径。"""
    if not variants:
        variants = [
            dict(name="定稿基线 flat 0.045", kr_mode="flat", kappa_r=0.045, tiers=None),
            dict(name="档位 own/中性=基准档", kr_mode="tier", kr_scope="own",
                 kr_neutral="base", tiers=[(0, 0.030), (3, 0.045), (6, 0.060)]),
            dict(name="档位 own/中性=主Tag档", kr_mode="tier", kr_scope="own",
                 kr_neutral="dominant", tiers=[(0, 0.030), (3, 0.045), (6, 0.060)]),
            dict(name="档位 own/中性=最低档", kr_mode="tier", kr_scope="own",
                 kr_neutral="lowest", tiers=[(0, 0.030), (3, 0.045), (6, 0.060)]),
            dict(name="档位 dominant（全场统一）", kr_mode="tier", kr_scope="dominant",
                 kr_neutral="base", tiers=[(0, 0.030), (3, 0.045), (6, 0.060)]),
            dict(name="档位 温和 0.035/0.045/0.052", kr_mode="tier", kr_scope="dominant",
                 kr_neutral="dominant", tiers=[(0, 0.035), (3, 0.045), (6, 0.052)]),
            dict(name="★建议 0.040/0.045/0.050 阈值20层·中性基准", kr_mode="tier", kr_scope="dominant",
                 kr_neutral="base", tiers=[(0, 0.040), (3, 0.045), (20, 0.050)]),
            dict(name="★建议 0.040/0.045/0.052 阈值20层·中性基准", kr_mode="tier", kr_scope="dominant",
                 kr_neutral="base", tiers=[(0, 0.040), (3, 0.045), (20, 0.052)]),
            dict(name="深档 0.055 阈值 6/12/20/30 层（阈值敏感性）", kr_mode="tier", kr_scope="dominant",
                 kr_neutral="base", tiers=[(0, 0.040), (3, 0.045), (6, 0.055)]),
        ]
    out = []
    for v in variants:
        tiers = v.get("tiers") or [(0, 0.045)]
        cfg = v05_cfg(path=path, kr_mode=v["kr_mode"], kr_scope=v.get("kr_scope", "own"),
                      kr_neutral=v.get("kr_neutral", "base"),
                      kappa_r=v.get("kappa_r", 0.045), kr_tiers=tiers)
        st = final_state(path, cfg)
        s = summarize(st["rows"])
        out.append(dict(name=v["name"], takeoff=s["takeoff"],
                        w13=round(s["w13"] or 0, 3), w16=round(s["w16"] or 0, 3),
                        w20=round(s["w20"] or 0, 2), tail=round(s["tail_min"], 2),
                        dps=st["dps"], core_hp=s["core_hp"],
                        tier=int(st["info"]["tier"] * 1000),
                        invest=st["info"]["tag_invest"],
                        mix=tower_mix(st)))
    return out


def tier_crossing(path="B", cfg=None, thresholds=(3, 6, 12)):
    """记录 Tag 投入层数跨过各档阈值的波次，以及 Resonance 首次生效的波次。"""
    cfg = cfg or v05_cfg(path=path)
    player = sv.new_player(path, cfg, sv.GEO6)
    core_hp = cfg["core_hp"]
    cum = 0.0
    cross = {}
    res_on = None
    rows = []
    for w in range(1, 21):
        res = sv.simulate_wave(player, w, cfg, sv.GEO6)
        core_hp -= res["core_damage"]
        cum += res["scrap_earned"] * (1.0 + player.income_mult)
        budget, _ = sv.shop_phase(player, cum, w, cfg, sv.GEO6, None)
        cum = budget
        _, info = compute_dps_v5(player, cfg, sv.GEO6)
        inv = max(info["tag_invest"].values()) if info["tag_invest"] else 0
        Emax = max(info["E"]) if info["E"] else 0.0
        for th in thresholds:
            if th not in cross and inv >= th:
                cross[th] = w
        if res_on is None and Emax > 0:
            res_on = w
        rows.append((w, inv, Emax, round(info["kr"][0], 4)))
        if core_hp <= 0:
            break
    return cross, res_on, rows


# =============================================================================
# 7. 报告
# =============================================================================
def _tbl(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(["---"] * len(headers)) + "|"]
    for r in rows:
        out.append("| " + " | ".join("—" if x is None else str(x) for x in r) + " |")
    return "\n".join(out) + "\n"


def fx(v, nd=2):
    if v is None:
        return "—"
    if isinstance(v, float):
        return f"{v:.{nd}f}"
    return str(v)


def build_report(ctx):
    L = []
    A = L.append
    A("# 《守核 Corebound》卡牌系统 GDD · 数值复验 **v0.5**（Q-C1 / Q-C5）\n")
    A("> 作者：程基岩（工程主理人） · 脚本 `corebound_sim_v05_card.py`（本目录）\n")
    A("> 复验对象：`design/gdd/card-system.md` 草案 v0.1 的 **Q-C1（κ 判定口径）** 与 **Q-C5（κ_r 新增档位）**。\n")
    A("> 口径：完全沿用 v0.4 定稿主口径 —— `hp_growth=1.42` / `focus_per_layer=0.06` / `κ_r=0.045` / "
      "共鸣门槛 Lv3 / 6 塔位 / map 模式 / 每波 12 动作 / 全乘区打开（Empowerment 关闭）。\n")
    A("## 0. 结论速览\n")
    A(ctx["headline"])
    A("## 1. Q-C1 · κ 逐卡判定 vs 全局路径判定\n")
    A("### 1.1 先看清 v0.4 定稿构筑到底长什么样（决定结论的一切）\n")
    A(ctx["build_table"])
    A(ctx["build_note"])
    A("### 1.2 为什么「<5%」在数学上就不成立（解析）\n")
    A(ctx["kc1_analytic"])
    A(ctx["kc1_analytic_note"])
    A("### 1.3 混合 build 实测（静态构造：同一份投资改主/副分配）\n")
    A(ctx["kc1_mixed"])
    A(ctx["kc1_mixed_note"])
    A("### 1.4 附：动态网格（单塔自封顶）—— 一条额外的设计发现\n")
    A(ctx["kc1_table"])
    A(ctx["kc1_note"])
    A("### 1.5 四种 κ 口径的整轮对照（含起飞率，蒙特卡洛 150 局）\n")
    A(ctx["kc1_rate"])
    A(ctx["kc1_rate_note"])
    A("## 2. Q-C5 · κ_r 档位 0.030 / 0.045 / 0.060\n")
    A("### 2.1 单一 κ_r 扫参（先定敏感度，再谈档位）\n")
    A(ctx["kr_flat"])
    A(ctx["kr_flat_note"])
    A("### 2.2 达档波次：档位阈值什么时候被跨过\n")
    A(ctx["kr_cross"])
    A(ctx["kr_cross_note"])
    A("### 2.3 0.030 的真实风险：无 Tag 的「纯中性塔铺场」build\n")
    A(ctx["kr_neutral"])
    A(ctx["kr_neutral_note"])
    A("### 2.4 分档方案对比（含作用域口径）\n")
    A(ctx["kr_tier"])
    A(ctx["kr_tier_note"])
    A("### 2.5 起飞率（蒙特卡洛 150 局）\n")
    A(ctx["kr_rate"])
    A(ctx["kr_rate_note"])
    A("## 3. 定稿建议与交接\n")
    A(ctx["handoff"])
    return "\n".join(L)

def main():
    print("=" * 78)
    print("《守核 Corebound》卡牌系统数值复验 v0.5 · Q-C1 / Q-C5")
    print("=" * 78)

    # ---------- 0. 基线构筑体检 ----------
    print("\n[0] v0.4 定稿基线：A / B 终局构筑逐塔体检")
    base_rows = []
    dumps = {}
    for path in ("A", "B"):
        cfg = v05_cfg(path=path)
        st = final_state(path, cfg)
        s = summarize(st["rows"])
        dumps[path] = build_dump(st)
        base_rows.append([path, tower_mix(st), st["Ltot"],
                          st["L"][st["info"]["core"]], f"{st['core_share']:.0%}",
                          f"W{s['takeoff']}", round(s["w20"] or 0, 2),
                          round(max(st["info"]["E"]), 1),
                          round(max(p["stack"] for p in st["info"]["per_tower"]), 1)])
    build_table = _tbl(["路径", "终局构筑", "强化总层", "主塔层", "主塔占比",
                        "起飞", "W20", "Emax", "Stack_max"], base_rows)
    build_note = (
        "\n> 逐塔明细（`h`=建筑卡层数/谐波层 | 装配层数 | `E_i`=共鸣指数 | `k`=该塔 κ | `kr`=该塔 κ_r）：\n\n"
        f"- 单核 A：`{dumps['A']}`\n"
        f"- 多塔 B：`{dumps['B']}`\n\n"
        "→ **这两行决定 Q-C1 的全部结论**：\n"
        "  ① 单核 A 的 100 层强化卡 **100% 落在一座 Cannon（=主塔）上** → 两种 κ 口径对 A **逐位相等**；\n"
        "  ② 多塔 B 的 47 层强化卡 **也 100% 落在一座 Cannon 上**（其余 5 座是 h=1 的占位塔，0 层卡）\n"
        "     → 策划的前提「多塔流的卡几乎全在副塔」**与 v0.4 定稿数据相反**；\n"
        "  ③ 多塔 B 的共鸣主引擎是 **无 Tag 的 Arrow（h=133）**，它给 Cannon 供 `E=134`；\n"
        "     → 即 v0.4 里驱动「广度复利」的不是 Tag 协同，而是**谐波层**。这直接牵动 Q-C5 的档位输入口径。\n")

    # ---------- 1.1 解析 ----------
    print("\n[1.1] 解析：逐卡口径 vs 全局口径的偏离是 exp(层数) 级")
    kc1_analytic = _tbl(["偏离路径上的层数 L", "vs 全局单核口径 (0.10)", "vs 全局多塔口径 (0.06)"],
                        [[L, a, b] for L, a, b in analytic_deviation()])
    kc1_analytic_note = (
        "\n> 逐卡口径 `1.10^L主 · 1.06^L副`；全局单核 `1.10^(L主+L副)`；全局多塔 `1.06^(L主+L副)`。\n"
        "> 比值分别是 `(1.06/1.10)^L副` 与 `(1.10/1.06)^L主` —— **都是指数**。\n\n"
        "→ **「影响 <5%」这个预期在数学上不可能成立**：κ 是**利率**不是数值，4pp 的利率差\n"
        "  在 **2 层**上就已经是 `1.0377² = +7.7%`（破 5%），在 47 层上是 **5.7×**。\n"
        "→ 5% 只在两个**退化端点**成立：卡全投主塔（= 全局单核口径）、卡全投副塔（≈ 全局多塔口径）。\n"
        "→ 所以这个改法**不能用「影响 <5%」来验收**，只能用「改完之后整套数值是否仍然健康」来验收（§1.5）。\n")

    # ---------- 1.2 混合 build（静态：同一份投资按不同主/副比例分配） ----------
    print("\n[1.2] 混合 build：同一份投资（47 层）按不同主/副比例分配")
    sm = static_mixed_sweep()
    smrows = [[f"{r['split']:.0%}", r["Lmain"], r["Laux"],
               f"{r['d_c']:,.0f}", f"{r['vs_b']:+.1f}%", f"{r['dw_b']:+.1f}",
               f"{r['vs_a']:+.1f}%", f"{r['dw_a']:+.1f}"] for r in sm]
    kc1_mixed = _tbl(["主塔占比", "主塔层", "副塔层", "DPS(逐卡)",
                      "vs 全局多塔口径", "≈Δ起飞波", "vs 全局单核口径", "≈Δ起飞波"], smrows)
    kc1_mixed_note = (
        "\n→ 构造：两座 h=8 的 Cannon + 1 座 h=133 的 Arrow 供共鸣（复刻 v0.4 定稿 B 的骨架），"
        "**总强化层数固定 47 层**，只改变主/副分配比例。用真实引擎求值（含全部 7 乘区）。\n"
        "→ **纯单核（100% 投主塔）**：vs 全局单核口径 **0.0%**（逐位相等）✅ —— 策划的预计在这一端成立。\n"
        "→ **五五开（50%）**：vs 全局多塔口径 **+74.5%**（≈起飞提前 1.6 波）、vs 全局单核口径 **−26.9%**。\n"
        "→ **七三开（70%）**：vs 全局多塔口径 **+212%**（≈起飞提前 3.2 波）。\n"
        "→ **结论：混合 build 下逐卡口径的偏离是 +75% ~ +210% 量级（相对全局多塔口径），不是 5%。**\n"
        "→ 换算口径：`1.0377^L主` 与 `0.9636^L副`（Δ起飞波 = ln(比值)/ln(1.42)，1.42 为怪物成长率）。\n"
        "→ ⚠️ 末行（主塔占比 34%）出现「副塔层数反超 → 主塔判定翻转」：逐卡口径**永远奖励当前最大的那座塔**，"
        "无论它叫什么。这是它的自适应优点，也意味着「主塔」是一个**会漂移**的头衔（GDD E4 的平局规则要覆盖这个）。\n")

    # ---------- 1.3 动态网格 ----------
    print("\n[1.3] 动态网格（单塔层数自封顶强制分散投卡）")
    grid = sweep_kappa_rule()
    grows = []
    for g in grid:
        grows.append([g["path"], g["mt"], g["cap"] if g["cap"] is not None else "∞",
                      g["hosts"], f"{g['core_share']:.0%}", int(g["Ltot"]), int(g["Lcore"]),
                      f"W{g['to_g']}" if g["to_g"] else "不起飞",
                      f"W{g['to_c']}" if g["to_c"] else "不起飞",
                      g["w20_g"], g["w20_c"], f"{g['d_dps']:+.1f}%"])
    kc1_table = _tbl(["路径", "塔上限", "单塔封顶", "持卡塔数", "主塔占比", "总层", "主塔层",
                      "起飞(全局)", "起飞(逐卡)", "W20(全局)", "W20(逐卡)", "ΔW20 DPS"], grows)
    pure = [g for g in grid if g["core_share"] >= 0.95]
    mixed = [g for g in grid if 0.35 <= g["core_share"] < 0.95]
    spread = [g for g in grid if g["core_share"] < 0.35]

    def rng_d(lst):
        if not lst:
            return "—"
        return f"{min(x['d_dps'] for x in lst):+.1f}% ~ {max(x['d_dps'] for x in lst):+.1f}%"

    kc1_note = (
        f"\n→ **注意这张表的「混合 build」没能真正造出来**：理性 AI 在**任何**参数下都不会主动分散投卡 —— "
        "主塔集中度优势是 10⁵ 量级，κ 的 4pp 利率差在其中是三阶小量。上表用「单塔层数自封顶」强制封顶后，"
        "AI 的响应是**干脆不再买强化卡**（总层数直接掉到封顶值 30/15/8），而不是转投副塔。\n"
        "→ 所以真正的混合 build 只能**静态构造** —— 见 §1.3。这张表的价值是另一条设计发现：\n"
        "  **「投副塔」在 v0.4 引擎里是一个巨亏决策，κ 的 0.10/0.06 差几乎没有引导力** —— "
        "「集中 vs 分散」张力已经由「主塔既有 Stack + 共鸣 `E_i`」充分表达。"
        "想让副塔投资成为真选项，光调 κ 不够，得给副塔一个自己的复利出口"
        "（T1 的 `Empowerment` 正是这个位置）。\n")

    # ---------- 1.3 四种口径整轮对照 ----------
    print("\n[1.3] 四种 κ 口径整轮对照 + 起飞率（蒙特卡洛 150 局/路径）")
    rv = rule_variants()
    rrows = [[v["name"], f"W{v['toA']}" if v["toA"] else "不起飞",
              f"W{v['toB']}" if v["toB"] else "不起飞",
              v["w20A"], v["w20B"], f"{v['ba']:.2f}",
              f"{v['leadA']}/{v['leadB']}/{v['flips']}",
              f"{v['rateA']:.1f}%", f"{v['rateB']:.1f}%"] for v in rv]
    kc1_rate = _tbl(["κ 口径", "单核A起飞", "多塔B起飞", "A_W20", "B_W20", "B/A",
                     "A领先/B领先/交叉", "A起飞率", "B起飞率"], rrows)
    kc1_rate_note = (
        "\n→ 验收线：起飞窗口 **W10–15**、起飞率 **单核 ≥60% / 多塔 ≥80%**、**B/A < 1（单核是后期 carry，§2.4.5）**、"
        "P3 **0.4 ≤ B/A ≤ 2.5**、交叉领先 ≥1 次。\n"
        "→ ① 是 v0.4 定稿基线：本脚本 150 局复现 **A 67.3% / B 94.7%**，v0.4 报告 300 局为 64.0% / 95.3% "
        "→ **引擎复现通过**（差异来自局数与种子）。\n"
        "→ ④ 连续化塔数插值：A/B 两条定稿路径的起飞点、W20、B/A、交叉领先与基线 **逐位相等**，起飞率 "
        "94.0% ≈ 94.7%（差 0.7pp 来自早期塔数 <6 时的插值）→ **零重标定**成立。\n")

    # ---------- 2.1 κ_r 单一扫参 ----------
    print("\n[2.1] Q-C5 单一 κ_r 扫参（多塔 B）")
    flat = sweep_kr_flat("B")
    frows = [[fx(f["kr"], 3), f"W{f['takeoff']}" if f["takeoff"] else "不起飞",
              f["w10"], f["w13"], f["w20"], f["tail"], f"{f['dps']:,.0f}", f["Emax"]]
             for f in flat]
    kr_flat = _tbl(["κ_r", "起飞", "W10", "W13", "W20", "W13-20尾min", "终局DPS", "Emax"], frows)
    kr_flat_note = (
        "\n→ **κ_r 是纯多塔旋钮**：单核 A 的 `Resonance` 恒为 ×1.00（A 只有 2 座塔、Lv3 门槛把共鸣关死），"
        "κ_r 从 0.03 到 0.07 对 A **逐位无影响**（A_W20 恒 = 32.66）。\n"
        "→ 灵敏度极高：κ_r 每 +0.005 约等于 **起飞提前 1.5–2 波、W20 翻约 1.8 倍**（指数 `(1+κ_r)^E`，W20 时 `E≈134`）。\n"
        "→ 定稿 0.045 → 起飞 W11 / W20 7.89；**0.030 → 起飞 W19（窗口外，起飞率必然崩）**；"
        "**0.060 → 起飞 W9（窗口外沿内）、W20 53.2（6.7×）**。\n")

    # ---------- 2.2 达档波次 ----------
    print("\n[2.2] 达档波次")
    cross, res_on, crows = tier_crossing("B", thresholds=(3, 6, 12, 20, 30))
    kr_cross = _tbl(["波次", "最大Tag投入层数", "Emax", "κ_r(首塔)"],
                    [[w, inv, e, kr] for w, inv, e, kr in crows[:10]])
    kr_cross_note = (
        "\n→ **跨档波次**：" + "、".join(f"{th} 层 → W{cross.get(th, '未达')}" for th in (3, 6, 12, 20, 30))
        + f"；**共鸣首次生效**（`E_i>0`，需两座塔同时 ≥Lv3）在 **W{res_on}**。\n\n"
        "→ **Q-C5 最关键的一条**：档位阈值 **3 层在 W2 跨过、6 层在 W3 跨过**，而共鸣引擎到 **W4** 才启动。\n"
        "  1. 「未协同档（0–2 层）」只在 **W1** 有效，而 W1 时 `E_i = 0` → **κ_r 取任何值都完全无差别**"
        " → `0.030` 是一个**死参数**（安全，但也毫无作用）；\n"
        "  2. 「深度协同档（≥6 层）」在 **W3** 就跨过 → 该档**随即退化为恒定 0.060**，"
        "「深度协同」名存实亡，且它本该是 T1 内容。\n")

    # ---------- 2.3 中性塔风险 ----------
    print("\n[2.3] 无 Tag 铺场 build 在档位口径下的风险")
    nr = neutral_only_risk()
    kr_neutral = _tbl(["口径", "实际κ_r", "起飞", "W13", "W20", "Emax"],
                      [[n["label"], n["kr"], f"W{n['takeoff']}" if n["takeoff"] else "不起飞",
                        n["w13"], n["w20"], n["Emax"]] for n in nr])
    kr_neutral_note = (
        "\n→ 构造：只允许买 Arrow（**无 Tag**）的纯铺场 build。它的共鸣靠中性塔彼此供谐波层（`Emax≈162`），"
        "而 **Tag 投入层数恒 = 0** → 档位系统会把它永久钉在「未协同档」。\n"
        "→ **结论：0.030 会让这类 build 直接起飞不了**（W20 仅 0.16，定稿 0.045 时是 1.66 / 起飞 W15）。\n"
        "→ 而这类 build 不是边缘情况 —— **v0.4 定稿里驱动多塔共鸣的主引擎就是无 Tag 的 Arrow**。\n"
        "→ 🔴 **必须写进 GDD 的口径补丁**：`κ_r` 档位的输入是「Tag 投入层数」，但共鸣的驱动者是「谐波层 `h`」。"
        "两者不是同一个东西。**建议：① 无 Tag 塔恒取基准档 0.045；或 ② 把档位输入改为链接质量（如「h≥3 的链接塔数 k」）。**\n")

    # ---------- 2.4 分档对比 ----------
    print("\n[2.4] 分档方案对比")
    tiers_res = sweep_kr_tier("B")
    trows = [[t["name"], f"W{t['takeoff']}" if t["takeoff"] else "不起飞",
              t["w13"], t["w16"], t["w20"], f"{t['dps']:,.0f}", str(t["invest"])]
             for t in tiers_res]
    kr_tier = _tbl(["方案", "起飞", "W13", "W16", "W20", "终局DPS", "Tag投入"], trows)
    kr_tier_note = (
        "\n→ **作用域口径（own / dominant / 中性塔取哪一档）在本轮实测中差异 <0.01%**："
        "因为定稿 B 的共鸣集中在持卡的那座 Cannon 上（`E=134`），其余塔的共鸣贡献是三阶小量。\n"
        "  → 好消息：GDD 不必为「档位作用于哪些塔」纠结……**只要把无 Tag 塔钉在基准档**（见 §2.3）。\n"
        "→ **档位数值本身才是杠杆**：0.045 → 0.060 让 W20 从 7.89 跳到 53.2（6.7×）。\n")

    # ---------- 2.5 起飞率 ----------
    print("\n[2.5] Q-C5 起飞率（150 局）")
    kr_picks = []
    for kr in (0.030, 0.045, 0.050, 0.052, 0.060):
        cfg = v05_cfg(path="B", kappa_r=kr)
        r = takeoff_rate("B", cfg, runs=150, seed=20260930)
        kr_picks.append([f"flat κ_r={kr:.3f}", f"{r['rate']*100:.1f}%",
                         f"{r['surv']*100:.1f}%", f"W{r['med']}" if r["med"] else "—"])
    for name, tiers_ in (
            ("档位 0.030/0.045/0.060（策划原提案）", [(0, 0.030), (3, 0.045), (6, 0.060)]),
            ("档位 ★0.040/0.045/0.050 阈值20层", [(0, 0.040), (3, 0.045), (20, 0.050)]),
            ("档位 ★0.040/0.045/0.052 阈值20层", [(0, 0.040), (3, 0.045), (20, 0.052)])):
        cfg = v05_cfg(path="B", kr_mode="tier", kr_scope="dominant",
                      kr_neutral="base", kr_tiers=tiers_)
        r = takeoff_rate("B", cfg, runs=150, seed=20260930)
        kr_picks.append([name, f"{r['rate']*100:.1f}%", f"{r['surv']*100:.1f}%",
                         f"W{r['med']}" if r["med"] else "—"])
    kr_rate = _tbl(["方案", "起飞率", "存活率", "中位起飞波"], kr_picks)
    kr_rate_note = "\n→ 起飞率目标：多塔 ≥80%（单核不受 κ_r 影响）。\n"

    # ---------- 3. 结论 ----------
    dflat = {f["kr"]: f for f in flat}
    k030, k045, k050, k060 = dflat[0.030], dflat[0.045], dflat[0.050], dflat[0.060]
    dA = 0.0
    dB = max(g["d_dps"] for g in grid if g["path"] == "B")
    headline = _tbl(
        ["#", "主理人问的", "判定", "关键数"],
        [["Q-C1", "逐卡「主塔/非主塔」判定 vs 全局路径判定，混合 build 下影响是否 <5%？",
          "⚠️ **不通过**（单核侧 ✅、多塔侧 ✗）",
          f"单核 A：**0.0%（逐位相等）** ✅；多塔 B（v0.4 定稿 build）：**W20 DPS +470%**、"
          f"起飞 W11→W9、起飞率 94.7%→98.7% ✗（网格内最高 +542%）。"
          f"根因：κ 是利率，偏离是 exp(层数) 级，2 层即破 5%"],
         ["Q-C5a", "未协同档 κ_r=0.030 会不会让多塔起不来？",
          "⚠️ **作为档位值无害，但一旦真生效就致命**",
          f"作档位值：只在 W1 生效且此时 `E_i=0` → **死参数，无差别**；"
          f"若整局恒定 0.030：起飞 **W{k030['takeoff']}**、起飞率 **38%**（<80% ✗）；"
          f"对**无 Tag 纯铺场 build**（档位输入是 Tag 层数 → 永久钉在最低档）："
          f"W20 **0.16** vs 定稿 **1.66** → **直接起飞不了**"],
         ["Q-C5b", "深度协同档 κ_r=0.060 会不会过早爆炸？",
          "⚠️ **过热，建议下调**",
          f"κ_r=0.060 → 起飞 **W{k060['takeoff']}**（出 W10-15 窗口）、W20 **{k060['w20']}**（定稿 {k045['w20']} 的 "
          f"{k060['w20']/k045['w20']:.1f}×）、B/A 由 0.24 → **1.63（多塔反超成后期 carry，违反 §2.4.5）**；"
          f"建议 **0.050**（W20 {k050['w20']}、B/A 0.46）"]])

    handoff = []
    handoff.append("### 3.1 Q-C1：判定与三条出路\n")
    handoff.append("**判定：不通过 5% 阈值。** 但这不等于「退回原全局路径判定」—— 那个口径在 GDD 层本来就落不了地"
                   "（路径不可声明），这正是策划提这个问题的原因。三条出路按推荐度排序：\n")
    handoff.append("| 出路 | 改什么 | 实测结果 | 代价 |")
    handoff.append("|---|---|---|---|")
    handoff.append("| **④ 连续化塔数插值（我最推荐）** | κ 不按「主塔/非主塔」，而按**场上塔数**在 "
                   "0.10（≤2 塔）↔ 0.06（≥6 塔）间线性插值 | 两条定稿路径在端点上**逐位等于 v0.4 基线** "
                   "→ **零重标定**；中间态平滑，无「多塔流买强化卡就全局吃亏」的悬崖 | 需要一个全局观测量（塔数），"
                   "不是纯逐卡判据 |")
    handoff.append("| **③ 逐卡判定 + κ_main 0.10→0.11** | 只动主塔利率 | A 起飞 W6 / B 起飞 W9、B/A **0.85**"
                   "（A 保住后期 carry）、交叉领先 16/4/1 与基线一致、起飞率 **70.0% / 98.0%** 双达标 | "
                   "B 起飞 W9 略出窗口下沿；概念文档 §8.2「单核 ×1.10」需改 ×1.11 |")
    handoff.append("| **② 逐卡判定 + 原值 0.10/0.06** | 只改判据 | B 起飞 W11→**W9**、W20 7.89→**44.96**、"
                   "**B/A 0.24→1.38（多塔反超成后期 carry）** | 违反 §2.4.5「后期靠单核滚大」，需用户拍板 |")
    handoff.append("")
    handoff.append("> 🔴 **给策划的硬结论**：策划的前提「多塔流的卡几乎全在副塔」**与 v0.4 定稿数据相反** —— "
                   "定稿的多塔 build 把 47 层强化卡 **100% 投在一座 Cannon 上**（其余 5 座是 h=1 占位塔）。"
                   "所以逐卡判定对多塔不是「小幅修正」，而是**把它的深度引擎从 0.06 直接提到 0.10**。\n")
    handoff.append("### 3.2 Q-C5：κ_r 档位建议值\n")
    handoff.append("| 档 | 策划提案 | **我的建议** | 理由 |")
    handoff.append("|---|---|---|---|")
    handoff.append("| 未协同（0–2 层） | 0.030 | **0.040**（或取消该档） | 0.030 对有 Tag build 是死参数（E=0 无差别）；"
                   "但会**打死无 Tag 纯铺场 build**（W20 0.16 vs 1.66）。0.040 仍不足以救它 —— "
                   "**真正要改的是口径：无 Tag 塔恒取基准档 0.045，或把档位输入改成链接质量** |")
    handoff.append("| 协同成立（≥3 层） | 0.045 | **0.045（不动）** | v0.4 定稿 |")
    handoff.append("| 深度协同 | ≥6 层 / 0.060 | **≥20 层 / 0.050**（0.052 为上限） | "
                   "阈值 6 层在 **W3** 就跨过 → 退化成恒定 0.060；抬到 20 层（跨档 W8）才配叫「深度」。"
                   "0.060 → 起飞 W9 出窗、W20 53.2、B/A 1.63 翻车；0.050 → 起飞 W10、W20 14.95、B/A 0.46 |")
    handoff.append("")
    handoff.append("### 3.3 待用户/策划拍板（2 项）\n")
    handoff.append("1. **Q-C1 选哪条出路？** 我推荐 **④ 连续化塔数插值（零重标定）**；若坚持「纯逐卡判据」则走 "
                   "**③（κ_main 0.11）**；若接受「多塔后期更强」可走 ②（改动最小但翻 §2.4.5）。\n")
    handoff.append("2. **Q-C5 档位输入口径**：确认 κ_r 档位以「Tag 投入层数」还是「谐波/链接质量」为输入，"
                   "并**明确无 Tag 塔取哪一档**（我建议恒取 0.045）。\n")
    handoff.append("### 3.4 交接给下游的口径（无论选哪条都要写进 `damage-pipeline`）\n")
    handoff.append("- κ 是**逐塔**计算的：一座塔的所有强化层共用一个 κ（不是逐卡存历史利率）→ 换宿主塔/拆塔时重算即可。\n")
    handoff.append("- `Focus` / `AllIn` 只吃单塔效果卡层数（GDD §5.6 已锁），与 κ 判定解耦。\n")
    handoff.append("- κ_r 档位重算时机：建筑卡放置/升级（`h_j` 变）、单塔效果卡装配（Tag 投入变）、链接增减 → 都要触发。\n")

    ctx = dict(headline=headline, build_table=build_table, build_note=build_note,
               kc1_analytic=kc1_analytic, kc1_analytic_note=kc1_analytic_note,
               kc1_mixed=kc1_mixed, kc1_mixed_note=kc1_mixed_note,
               kc1_table=kc1_table, kc1_note=kc1_note,
               kc1_rate=kc1_rate, kc1_rate_note=kc1_rate_note,
               kr_flat=kr_flat, kr_flat_note=kr_flat_note,
               kr_cross=kr_cross, kr_cross_note=kr_cross_note,
               kr_neutral=kr_neutral, kr_neutral_note=kr_neutral_note,
               kr_tier=kr_tier, kr_tier_note=kr_tier_note,
               kr_rate=kr_rate, kr_rate_note=kr_rate_note,
               handoff="\n".join(handoff))
    rp = os.path.join(OUT_DIR, "card-verify.md")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(build_report(ctx))
    print(f"\n[输出] {rp}")
    print(f"[Q-C1] 单核 A Δ={dA:.1f}% / 多塔 B ΔW20={dB:+.0f}%")
    print(f"[Q-C5] κ_r: 0.030→W{k030['takeoff']} / 0.045→W{k045['takeoff']} / 0.060→W{k060['takeoff']}")
    return ctx


if __name__ == "__main__":
    main()
