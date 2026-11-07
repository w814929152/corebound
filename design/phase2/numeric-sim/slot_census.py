# -*- coding: utf-8 -*-
"""
slot_census.py — P0 纸面推演的实测版（不新增卡，只做测量）

回答三个问题：
  1. W8 / W12 时，玩家的 5 个卡种位实际被什么占满？（R2 槽位饥荒的真实形态）
  2. 每张已持卡、每 1 层、每 1 点 h 的边际 DPS 是多少？（链要挤掉的那张卡值多少）
  3. 摄灵是零和搬运：把 1 点 h 从 A 塔搬到 B 塔，DPS 变化多少？（枚举所有有序对）

用法：
  python slot_census.py            # 打印 A / B 两条路径的普查表
  python slot_census.py pairs      # 只打印 h 搬运的价值矩阵
"""
import itertools
import sys

import corebound_sim_v03 as sv
import corebound_sim_v08_salvage as v8

CFG = {p: v8.cfg_of(p) for p in ("A", "B")}
GEO = {"A": sv.GEO6, "B": sv.GEO6}


# ---------------------------------------------------------------- 基础测量
def dps(p, cfg, geo):
    return sv.compute_dps(p, cfg, geo)[0]


def marg_card(p, cfg, geo, name):
    """整张卡消失（所有塔上该卡的全部层数）→ ΔDPS。返回值恒 <= 0。"""
    s = p.snap()
    before = dps(p, cfg, geo)
    for t in p.towers:
        t.attach.pop(name, None)
    p.cards.discard(name)
    after = dps(p, cfg, geo)
    p.rest(s)
    return after - before


def marg_layer(p, cfg, geo, name, slot=None):
    """给某座塔 +1 层该卡 → ΔDPS（取增益最大的塔，若未指定）。"""
    s = p.snap()
    before = dps(p, cfg, geo)
    best = None
    targets = [t for t in p.towers if slot is None or t.slot == slot]
    for t in targets:
        snap2 = t.attach.get(name, 0)
        t.attach[name] = snap2 + 1
        d = dps(p, cfg, geo) - before
        t.attach[name] = snap2
        if best is None or d > best[1]:
            best = (t.slot, d)
    p.rest(s)
    return best  # (slot, delta)


def marg_h(p, cfg, geo, slot):
    s = p.snap()
    before = dps(p, cfg, geo)
    for t in p.towers:
        if t.slot == slot:
            t.h += 1
    d = dps(p, cfg, geo) - before
    p.rest(s)
    return d


def h_move_matrix(p, cfg, geo):
    """枚举 (从塔 src 抢 1 点 h → 给塔 dst)，返回 DPS 变化矩阵与明细。"""
    before = dps(p, cfg, geo)
    out = []
    for src, dst in itertools.permutations(range(len(p.towers)), 2):
        s = p.snap()
        p.towers[src].h -= 1
        p.towers[dst].h += 1
        after = dps(p, cfg, geo)
        p.rest(s)
        out.append((src, dst, after - before))
    return before, out


# ---------------------------------------------------------------- 主流程
def census(path, max_wave=20):
    cfg, geo = CFG[path], GEO[path]
    p = sv.new_player(path, cfg, geo)
    marks = {}
    core_hp = cfg["core_hp"]
    cum = 0.0
    for w in range(1, max_wave + 1):
        res = sv.simulate_wave(p, w, cfg, geo)
        core_hp -= res["core_damage"]
        cum += res["scrap_earned"] * (1.0 + p.income_mult)
        cum, _ = sv.shop_phase(p, cum, w, cfg, geo, None)
        if w in (8, 12, 20):
            marks[w] = (
                [(t.slot, t.ctype, t.h, dict(t.attach)) for t in p.towers],
                sorted(p.cards),
                dps(p, cfg, geo),
            )
        if core_hp <= 0:
            break
    return marks


def show(path):
    cfg, geo = CFG[path], GEO[path]
    marks = census(path)
    print(f"\n{'='*78}\n路径 {path} · 卡种位上限 = {cfg['backpack']} · 塔数上限 = "
          f"{cfg.get('max_towers') or {'A':2,'B':cfg['n_slots']}}\n{'='*78}")
    for w in (8, 12, 20):
        if w not in marks:
            continue
        towers, cards, d0 = marks[w]
        print(f"\n--- W{w} · 总 DPS {d0:.2f} · 卡种 {len(cards)}/{cfg['backpack']} ---")
        print(f"  持有的卡种：{', '.join(cards)}")
        for slot, ctype, h, att in towers:
            a = ", ".join(f"{k}x{v}" for k, v in sorted(att.items())) or "—"
            print(f"  塔位{slot} {ctype:<7} h={h:<3} 装配: {a}")
    # 边际测量只在 W12 停留态做（重建一次，取该波快照）
    return marks


def marginal_report():
    for path in ("A", "B"):
        cfg, geo = CFG[path], GEO[path]
        p = sv.new_player(path, cfg, geo)
        core_hp = cfg["core_hp"]
        cum = 0.0
        snap12 = None
        for w in range(1, 21):
            res = sv.simulate_wave(p, w, cfg, geo)
            core_hp -= res["core_damage"]
            cum += res["scrap_earned"] * (1.0 + p.income_mult)
            cum, _ = sv.shop_phase(p, cum, w, cfg, geo, None)
            if w == 12:
                snap12 = p.snap()
            if core_hp <= 0:
                break
        if snap12 is None:
            print(f"路径 {path}: 未活到 W12"); continue
        p.rest(snap12)
        d0 = dps(p, cfg, geo)
        print(f"\n{'='*78}\n路径 {path} · W12 边际表 · 基准 DPS {d0:.2f}\n{'='*78}")
        print(f"{'卡种/塔':<16}{'层数':>6}{'整卡Δ':>10}{'占比':>8}{'+1层Δ':>10}{'每分效':>9}")
        reinf_held = [n for n in sorted(p.cards) if n in sv.REINF]
        tower_held = [n for n in sorted(p.cards) if n not in sv.REINF]
        if tower_held:
            print(f"  （建筑卡，层数即 h：{', '.join(tower_held)} —— 不占强化槽，单独计入 h 行）")
        for name in reinf_held:
            tot = sum(t.attach.get(name, 0) for t in p.towers)
            mc = marg_card(p, cfg, geo, name)
            slot, ml = marg_layer(p, cfg, geo, name)
            price = sv.PRICE.get("reinforce", 9)
            print(f"{name:<16}{tot:>6}{mc:>10.2f}{mc/d0*100 if d0 else 0:>7.1f}%"
                  f"{ml:>10.2f}{ml/price:>9.3f}")
        print(f"{'-'*60}")
        for t in p.towers:
            mh = marg_h(p, cfg, geo, t.slot)
            print(f"{'塔位%d %s h=%d' % (t.slot, t.ctype, t.h):<16}{'':>6}"
                  f"{'':>10}{'':>8}{mh:>10.2f}{mh/sv.PRICE.get('tower',10):>9.3f}   ← +1 h")
        # h 搬运矩阵
        before, mv = h_move_matrix(p, cfg, geo)
        pos = [(a, b, d) for a, b, d in mv if d > 1e-9]
        neg = [(a, b, d) for a, b, d in mv if d < -1e-9]
        print(f"\n  h 搬运（1 点）：有序对 {len(mv)} 个，正收益 {len(pos)} 个，负收益 {len(neg)} 个")
        for a, b, d in sorted(mv, key=lambda x: -x[2])[:6]:
            ha = [t.h for t in p.towers if t.slot == a][0]
            hb = [t.h for t in p.towers if t.slot == b][0]
            print(f"    塔{a}(h{ha}) → 塔{b}(h{hb}) : {d:+.2f}  ({d/before*100:+.2f}%)")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode in ("all", "census"):
        for path in ("A", "B"):
            show(path)
    if mode in ("all", "pairs", "marg"):
        marginal_report()
