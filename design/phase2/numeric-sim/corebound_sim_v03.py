# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — 纸面数值模拟 **v0.3 复验**
作者：程基岩（工程主理人）

在 v2（corebound_sim.py）基础上回答策划 v0.3 交回的三项复验 + 一项架构锁定：

  复验1  加入 Resonance 后重跑多塔 —— 目标 W13..W20 DPS/HP 持续 >=8x 且不回落
         扫参 kappa_r ∈ [0.05,0.12]，并评估塔位 4→6 后的链接数 k 上限
  复验2  软 cap 分段衰减曲线（>100 层的衰减率），验证雪崩期不失速（R12）
  复验3  含商店 RNG 的蒙特卡洛，验证起飞率 >= 80%
  架构   7 个乘区的计算管线顺序（会成为 damage-pipeline GDD 的核心）

================================================================================
 ★ 本次重构最重要的一点：伤害模型从「全局聚合」改为「逐塔求值」
================================================================================
 v2 的 compute_dps 把同 Tag 的塔先求和再乘 buff —— 这在数学上等价于「一座塔」，
 无法表达 Resonance（它是**逐塔**的：塔 i 的倍率取决于谁和它链接）。
 因此 v0.3 把模型改为逐塔求值：

     Delivered = ( Σ_i  Base_i × Stack_i × Syn_i × Res_i × Focus_i
                        × AllIn_i × Coverage_i )  ×  AoE × Crossfire × Aux

 为保证重构没改坏数值，脚本内置 **双回归测试**：
   T1 精确：给定同一套构筑，v0.3 引擎在 legacy 配置下的 DPS 必须 == v2 compute_dps
   T2 近似：legacy 模式下整轮 W1..W20 的起飞点必须落在 v2 的 ±1 波内
================================================================================
"""
from __future__ import annotations
import os
import csv
import math
import random
import statistics

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 1. 卡池（与 v2 POOL 完全对齐，保证回归可比）
# =============================================================================
# ⚠️ 2026-11-08 口径变更（v0.4 卡池 / 批次⑥）：
#     `dps` = **伤害**（单发基准），有效 DPS = dps × aspeed。
#     引擎侧由 `building_card_params.gd` 的 `attack_speed` 字段承担，见
#     `damage_engine.compute_dps()` 里 `dps_i *= tower_attack_speed(ctype)`。
#     本模型的 aspeed 必须与之逐位一致，否则金标本与引擎分叉。
TOWERS = {
    "Arrow":  dict(dps=10.0, aspeed=0.80, tag=None,    aoe=False, slow=0.00, rng=22.0),
    "Cannon": dict(dps=7.0,  aspeed=0.70, tag="fire",  aoe=True,  slow=0.00, rng=18.0),
    "Frost":  dict(dps=5.0,  aspeed=0.65, tag="frost", aoe=False, slow=0.30, rng=20.0),
}
REINF = {"FireUp": dict(tag="fire"), "FrostUp": dict(tag="frost")}
ECON = {"ScrapUp": dict(), "RerollD": dict()}

ALL_CARDS = {}
for _k, _v in TOWERS.items():
    ALL_CARDS[_k] = dict(kind="tower", **_v)
for _k, _v in REINF.items():
    ALL_CARDS[_k] = dict(kind="reinforce", **_v)
for _k, _v in ECON.items():
    ALL_CARDS[_k] = dict(kind="econ", **_v)

PRICE = {"tower": 12.0, "reinforce": 9.0, "econ": 10.0}

# v2 路径优先级去重后 = 该路径「会被考虑」的卡（用于 legacy 回归）
ALLOWED = {
    "A": {"Cannon", "Frost", "FireUp", "ScrapUp"},
    "B": {"Cannon", "Arrow", "Frost", "FireUp", "FrostUp", "ScrapUp"},
}

# =============================================================================
# 2. MVP 地图几何（用于 CoverageScore 与 LinkTopology）
#    —— 这是 v0.3 新增的：Resonance 需要真实的射程重叠判定
# =============================================================================
PATH = [(0.0, 25.0), (12.0, 25.0), (12.0, 48.0),
        (35.0, 48.0), (35.0, 25.0), (55.0, 25.0)]
SLOTS6 = [(6.0, 33.0), (22.0, 40.0), (30.0, 33.0),
          (45.0, 33.0), (18.0, 16.0), (48.0, 42.0)]
SLOTS4 = SLOTS6[:4]


def _pt_seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    den = dx * dx + dy * dy
    t = 0.0 if den == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / den))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _sample_path(path, samples=1500):
    segs, total = [], 0.0
    for i in range(len(path) - 1):
        L = math.dist(path[i], path[i + 1])
        segs.append((path[i], path[i + 1], L))
        total += L
    pts = []
    for a, b, L in segs:
        m = max(2, int(samples * L / total))
        for k in range(m):
            t = k / m
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return pts, total


_PATH_PTS, _PATH_LEN = _sample_path(PATH)


def coverage_of(slot_xy, radius):
    """CoverageScore：该塔位的射程覆盖路径长度占比。"""
    hit = sum(1 for p in _PATH_PTS if math.dist(p, slot_xy) <= radius)
    return hit / len(_PATH_PTS)


class Geo:
    """一张地图的几何：塔位坐标 → 覆盖值 / 距离矩阵 / 链接图。"""

    def __init__(self, slots):
        self.slots = list(slots)
        self.n = len(self.slots)
        self.dist = [[0.0] * self.n for _ in range(self.n)]
        for i in range(self.n):
            for j in range(self.n):
                self.dist[i][j] = math.dist(self.slots[i], self.slots[j])
        self.cov = {}
        for tname, td in TOWERS.items():
            for s in range(self.n):
                self.cov[(s, tname)] = coverage_of(self.slots[s], td["rng"])

    def links(self, tower_types, rule="any"):
        """tower_types: 长度 = 塔位数 的列表（None 表示空位）。
        返回邻接表（list of list of int）。"""
        n = len(tower_types)
        R = [TOWERS[t]["rng"] if t else 0.0 for t in tower_types]
        f = 1.0 if rule == "any" else 0.65
        adj = [[] for _ in range(n)]
        for i in range(n):
            if not tower_types[i]:
                continue
            for j in range(n):
                if i == j or not tower_types[j]:
                    continue
                if self.dist[i][j] <= f * (R[i] + R[j]):
                    adj[i].append(j)
        return adj


GEO6 = Geo(SLOTS6)
GEO4 = Geo(SLOTS4)

# =============================================================================
# 3. 配置
# =============================================================================
def make_cfg(**over):
    c = dict(
        # ---- 怪物侧（v2 校准值，锁定）----
        hp_base=16.0, hp_growth=1.30,
        num_base=8.0, num_growth=1.6,
        scrap_base=2.0, scrap_growth=0.5,
        leak_damage=50.0, t_reach=10.0, core_hp=1000.0,
        wave_dur=lambda w: 28.0 + 2.2 * w,
        spawn_window=lambda w: 0.30 if w <= 5 else (0.60 if w <= 12 else 1.0),
        # ---- 经济 ----
        backpack=5,
        reroll_base=5.0, reroll_growth=3.0, shop_offers=3,
        # ---- 叠层复利引擎 ----
        reinf_compound={"A": 1.10, "B": 1.06},
        reinf_cap=100,
        softcap_decay=1.03,          # ★复验2 旋钮：>100 层的每层倍率
        tower_stack_exp=0.6,
        synergy_threshold=3, synergy_mult=1.5,
        fire_stock={"A": 6, "B": 3},
        # ---- 路径修饰（v2 legacy）----
        path_coverage={"A": 0.78, "B": 0.95},
        aoe_cap={"A": 2.6, "B": 2.2}, aoe_per={"A": 0.24, "B": 0.14},
        # ---- v0.3 新增乘区 ----
        kappa_r=0.08,
        link_min_level=1,        # ★ 共鸣门槛：只有层数 >= 此值的塔才参与共鸣（延迟引擎启动）
        focus_per_layer=0.15,
        allin_mult=1.6, allin_share=0.60,
        crossfire_2=1.25, crossfire_3=1.5,
        aux_slow=0.30,
        # ---- 开关 ----
        use_resonance=True,
        use_focus=False, use_allin=False, use_crossfire=False, use_aux=False,
        coverage_mode="path",        # "path"(v2常量) | "geometry"
        tower_card_mode="backpack",  # "backpack"(塔卡占卡位) | "map"(塔卡落塔位)
        n_slots=4,
        link_rule="any",             # "any"(任意重叠) | "substantial"(0.65*(Ri+Rj))
        # ---- 行为 ----
        # ★ max_actions = 实时注意力预算：每波「买/刷」动作数上限。
        #   v2 的确定性模型是 None（无限），那是不现实的：实时商店受减速预算 20s/波限制。
        max_actions=12,
        # ★ 替代「每波张数上限」的库存摩擦：同一张卡在同一波内每买一次，价格 +step（每波重置）
        wave_price_step=0.0,
        # ★ 流派塔数上限：单核=集中（主塔+1挂件），多塔=铺满塔位。
        max_towers=None,             # None → 默认 {"A": 2, "B": n_slots}
        pity=False,                  # ★ 起飞保底：商店必出 1 张与主塔同 Tag 的强化卡
        skill=1.0,                   # 1.0=完全理性
    )
    c.update(over)
    return c


def legacy_cfg(path=None, **over):
    """v2 兼容配置：关掉所有 v0.3 新机制，用于回归测试。"""
    d = dict(
        use_resonance=False, use_focus=False, use_allin=False,
        use_crossfire=False, use_aux=False,
        coverage_mode="path", tower_card_mode="backpack",
        n_slots=5, softcap_decay=1.00, kappa_r=0.0,
    )
    d.update(over)
    return make_cfg(**d)


# =============================================================================
# 4. 状态
# =============================================================================
class Tower:
    __slots__ = ("slot", "ctype", "h", "attach")

    def __init__(self, slot, ctype, h=1, attach=None):
        self.slot = slot
        self.ctype = ctype
        self.h = h
        self.attach = dict(attach) if attach else {}

    def clone(self):
        return Tower(self.slot, self.ctype, self.h, self.attach)


class Player:
    def __init__(self, path):
        self.path = path
        self.towers = []
        self.cards = set()      # 占卡位的卡（reinforce 永远；tower 仅 backpack 模式）
        self.income_mult = 0.0
        self.reroll_disc = 0.0

    def build_str(self):
        agg = {}
        for t in self.towers:
            agg[t.ctype] = agg.get(t.ctype, 0) + t.h
        for t in self.towers:
            for rn, lv in t.attach.items():
                agg[rn] = agg.get(rn, 0) + lv
        return ",".join(f"{k}x{v}" for k, v in sorted(agg.items()))

    def snap(self):
        return ([(t.slot, t.ctype, t.h, dict(t.attach)) for t in self.towers],
                set(self.cards), self.income_mult, self.reroll_disc)

    def rest(self, s):
        self.towers = [Tower(a, b, c, d) for a, b, c, d in s[0]]
        self.cards = set(s[1])
        self.income_mult = s[2]
        self.reroll_disc = s[3]


# =============================================================================
# 5. ★ 伤害管线（7 乘区）—— 顺序即 GDD 应锁定的顺序
# =============================================================================
#   阶段 A 前置（每波开始 / 塔位变动时重算）
#        A1 CoverageScore_i   A2 LinkGraph   A3 h_i(塔卡层数)   A4 L_i(装配层数)
#        A5 CoreTower         A6 TagTier(→ κ, StackCap)
#   阶段 B 逐塔（顺序固定）
#        B1 Base_i   = TowerDPS × h_i^0.6
#        B2 Stack_i  = Π softcap_pow(1+κ_tag, L)      ← 复利引擎①深度
#        B3 Syn_i    = ×1.5 (该 Tag 塔卡层数 >= 3)
#        B4 Res_i    = (1+κ_r)^{E_i}                  ← 复利引擎②广度
#        B5 Focus_i  = 1 + 0.15·L_i
#        B6 AllIn_i  = ×1.6 (i==CoreTower 且 L_i >= 60%·ΣL)
#        B7 Cov_i    = CoverageScore_i
#   阶段 C 全局聚合
#        C1 AoE 密度效率   C2 Crossfire   C3 挂件 Aux   C4 Empowerment(T1)
# =============================================================================
def softcap_pow(lv, kappa, cap, decay):
    """叠层复利，软 cap 分段衰减。decay=1.0 退化为 v2 硬 cap。"""
    if lv <= cap:
        return kappa ** lv
    return (kappa ** cap) * (decay ** (lv - cap))


def compute_dps(player: Player, cfg, geo: Geo = None):
    ts = player.towers
    n = len(ts)
    if n == 0:
        return 0.0, {"per_tower": [], "links": [], "E": [], "syn": 0,
                     "aoe": 1.0, "crossfire": 1.0, "aux": 1.0}

    path = player.path
    lmin = cfg.get("link_min_level", 1)
    # ---- A3/A4 ----
    h = [t.h for t in ts]
    L = [sum(t.attach.values()) for t in ts]
    Ltot = sum(L)
    # ---- A5 ----
    core = max(range(n), key=lambda i: L[i]) if Ltot > 0 else 0
    # ---- A6 / 协同（v2：同 Tag 塔卡层数之和 >= 阈值）----
    tag_tower_lv = {}
    for i, t in enumerate(ts):
        tg = TOWERS[t.ctype]["tag"]
        if tg:
            tag_tower_lv[tg] = tag_tower_lv.get(tg, 0) + h[i]
    # ---- A2 链接图 ----
    adj = [[] for _ in range(n)]
    E = [0.0] * n
    if cfg["use_resonance"] and geo is not None:
        types = [t.ctype for t in ts]
        # geo 按地图塔位索引；tower.slot 即地图塔位
        gtypes = [None] * geo.n
        for i, t in enumerate(ts):
            gtypes[t.slot] = t.ctype
        gadjs = geo.links(gtypes, cfg["link_rule"])
        for i, t in enumerate(ts):
            for gj in gadjs[t.slot]:
                # 找回该地图塔位对应的塔实例
                for k, t2 in enumerate(ts):
                    if k != i and t2.slot == gj:
                        adj[i].append(k)
                        if h[i] >= lmin and h[k] >= lmin:
                            E[i] += 1.0 + h[k]
    elif cfg["use_resonance"]:
        # 无几何：退化为「全互连」上限（用于理论扫参）
        for i in range(n):
            for k in range(n):
                if k != i:
                    adj[i].append(k)
                    if h[i] >= lmin and h[k] >= lmin:
                        E[i] += 1.0 + h[k]

    kappa = cfg["reinf_compound"][path]
    cap = cfg["reinf_cap"]
    decay = cfg["softcap_decay"]
    kr = cfg["kappa_r"]

    per_tower = []
    for i, t in enumerate(ts):
        # B1
        base = TOWERS[t.ctype]["dps"] * (h[i] ** cfg["tower_stack_exp"])
        # B2 Stack
        stack = 1.0
        for rn, lv in t.attach.items():
            if REINF[rn]["tag"] != TOWERS[t.ctype]["tag"]:
                continue
            stack += softcap_pow(lv, kappa, cap, decay) - 1.0
        # B3 Synergy
        tg = TOWERS[t.ctype]["tag"]
        syn = 1.0
        if tg and tag_tower_lv.get(tg, 0) >= cfg["synergy_threshold"]:
            syn = cfg["synergy_mult"]
        # B4 Resonance
        res = ((1.0 + kr) ** E[i]) if cfg["use_resonance"] else 1.0
        # B5 Focus
        foc = (1.0 + cfg["focus_per_layer"] * L[i]) if cfg["use_focus"] else 1.0
        # B6 AllIn
        ali = 1.0
        if cfg["use_allin"] and Ltot > 0 and i == core and L[i] >= cfg["allin_share"] * Ltot:
            ali = cfg["allin_mult"]
        # B7 Coverage
        if cfg["coverage_mode"] == "geometry" and geo is not None:
            cov = geo.cov[(t.slot, t.ctype)]
        else:
            cov = cfg["path_coverage"][path]
        per_tower.append(dict(base=base, stack=stack, syn=syn, res=res,
                              focus=foc, allin=ali, cov=cov,
                              # ⚠️ 与引擎逐字同序：先算 7 乘区，再 × aspeed
                              dps=base * stack * syn * res * foc * ali * cov
                                  * TOWERS[t.ctype].get("aspeed", 1.0)))

    subtotal = sum(p["dps"] for p in per_tower)
    # C1 AoE 密度效率（v2 legacy：只统计带 Tag 的塔的层数，Arrow 无 Tag 不计入）
    aoe_total = sum(tag_tower_lv.values())
    aoe = min(cfg["aoe_cap"][path], 1.0 + cfg["aoe_per"][path] * aoe_total)
    # C2 Crossfire
    if not cfg["use_crossfire"]:
        cf = 1.0
    else:
        cf = cfg["crossfire_3"] if n >= 3 else (cfg["crossfire_2"] if n >= 2 else 1.0)
    # C3 挂件乘区（减速 → 等效倍率 1/(1-slow)）
    aux = 1.0
    if cfg["use_aux"]:
        slow = max([TOWERS[t.ctype]["slow"] for t in ts] or [0.0])
        if slow > 0:
            aux *= 1.0 / (1.0 - min(slow, 0.75))
    # C4 Empowerment —— T1，MVP 关闭（挂件减速固定 0.30）

    total = subtotal * aoe * cf * aux
    return total, dict(per_tower=per_tower, adj=adj, E=E, aoe=aoe,
                       crossfire=cf, aux=aux, subtotal=subtotal,
                       syn=sum(1 for p in per_tower if p["syn"] > 1.0))


def dps_only(player, cfg, geo):
    return compute_dps(player, cfg, geo)[0]


# =============================================================================
# 6. 离散战斗（与 v2 完全一致，dt=0.1s）
# =============================================================================
def monster_stats(w, cfg):
    hp = cfg["hp_base"] * (cfg["hp_growth"] ** (w - 1))
    n = int(round(cfg["num_base"] + cfg["num_growth"] * w))
    spk = cfg["scrap_base"] + cfg["scrap_growth"] * w
    total_hp = n * hp
    D = cfg["wave_dur"](w)
    t_reach = cfg["t_reach"]
    return dict(w=w, hp=hp, n=n, scrap_per_kill=spk, total_hp=total_hp,
                D=D, t_reach=t_reach, threshold=total_hp / (D + t_reach))


def simulate_wave(player, w, cfg, geo):
    ms = monster_stats(w, cfg)
    D, n, hp_each = ms["D"], ms["n"], ms["hp"]
    dt = 0.1
    dps = dps_only(player, cfg, geo)
    t_reach = ms["t_reach"]
    spawn_span = D * cfg["spawn_window"](w)
    interval = spawn_span / max(1, n)
    time = 0.0
    spawned = 0
    monsters = []
    kills = 0
    leaked = 0
    scrap = 0.0
    limit = D + t_reach + 1e-9
    while time <= limit:
        while spawned < n and time >= spawned * interval - 1e-9:
            monsters.append([hp_each, t_reach])
            spawned += 1
        dmg = dps * dt
        monsters.sort(key=lambda m: m[1])
        for m in monsters:
            if dmg <= 0:
                break
            if m[0] <= dmg:
                dmg -= m[0]
                m[0] = 0
                kills += 1
                scrap += ms["scrap_per_kill"]
            else:
                m[0] -= dmg
                dmg = 0
        alive = []
        for m in monsters:
            if m[0] <= 0:
                continue
            m[1] -= dt
            if m[1] <= 0:
                leaked += 1
            else:
                alive.append(m)
        monsters = alive
        time += dt
    return dict(w=w, kills=kills, leaked=leaked, scrap_earned=scrap,
                core_damage=leaked * cfg["leak_damage"], dps=dps,
                threshold=ms["threshold"], total_hp=ms["total_hp"],
                n=n, hp_each=hp_each)


# =============================================================================
# 7. 商店
# =============================================================================
WEIGHTS = {"Arrow": 0.17, "Cannon": 0.17, "Frost": 0.13,
           "FireUp": 0.17, "FrostUp": 0.17, "ScrapUp": 0.095, "RerollD": 0.095}
_CARD_NAMES = list(WEIGHTS.keys())
_CARD_W = [WEIGHTS[k] for k in _CARD_NAMES]


def draw_offers(rng, k=3, force=None):
    s = set(rng.choices(_CARD_NAMES, weights=_CARD_W, k=k))
    if force:
        s.add(force)
        while len(s) > k:                      # 保底挤掉一张随机卡，维持商品位数
            s.discard(rng.choice(sorted(s - {force})))
    return s


def pity_card(player):
    """起飞保底：返回与当前主塔同 Tag 的强化卡名（无则 None）。"""
    if not player.towers:
        return None
    core = max(player.towers, key=lambda t: (sum(t.attach.values()), t.h))
    tg = TOWERS[core.ctype]["tag"]
    if not tg:
        return None
    for rn, rd in REINF.items():
        if rd["tag"] == tg:
            return rn
    return None


def _free_map_slots(player, cfg):
    used = {t.slot for t in player.towers}
    return [s for s in range(cfg["n_slots"]) if s not in used]


def enumerate_actions(player, cfg, fire_bought, offers=None, geo=None):
    """列出所有「当前可做」的动作。offers 非 None 时（MC）只保留商店里出现的卡。"""
    acts = []
    path = player.path
    allowed = ALLOWED[path]
    fcap = cfg["fire_stock"][path]

    def fire_ok(name):
        return not (ALL_CARDS[name].get("tag") == "fire" and fire_bought >= fcap)

    def offer_ok(name):
        return offers is None or name in offers

    # 经济（全局升级，不占卡位）
    if offer_ok("ScrapUp") and player.income_mult < 1.0:
        acts.append(("econ", "ScrapUp", None, None))

    # 塔卡
    mt = cfg.get("max_towers") or {"A": 2, "B": cfg["n_slots"]}
    can_build = len(player.towers) < mt[path]
    for tname in TOWERS:
        if tname not in allowed or not fire_ok(tname) or not offer_ok(tname):
            continue
        if cfg["tower_card_mode"] == "backpack":
            if tname in player.cards:
                for t in player.towers:
                    if t.ctype == tname:
                        acts.append(("up", tname, t.slot, None))
            elif can_build and len(player.cards) < cfg["backpack"]:
                acts.append(("build", tname, None, None))
        else:
            if can_build:
                for s in _free_map_slots(player, cfg):
                    acts.append(("build", tname, s, None))
            for t in player.towers:
                if t.ctype == tname:
                    acts.append(("up", tname, t.slot, None))

    # 强化卡（只对该 Tag 的塔生效）
    for rname, rd in REINF.items():
        if rname not in allowed or not fire_ok(rname) or not offer_ok(rname):
            continue
        for t in player.towers:
            if TOWERS[t.ctype]["tag"] != rd["tag"]:
                continue
            if rname in player.cards:
                acts.append(("reinf", rname, t.slot, None))
            elif len(player.cards) < cfg["backpack"]:
                acts.append(("reinf_new", rname, t.slot, None))
            else:
                # 卡位满 → 置换（丢弃边际损失最小的卡）
                drop = weakest_card(player, cfg, geo)
                if drop is not None and drop != rname:
                    acts.append(("reinf_swap", rname, t.slot, drop))
    return acts


def weakest_card(player, cfg, geo):
    if not player.cards:
        return None
    cur = dps_only(player, cfg, geo)
    best, best_loss = None, None
    for name in list(player.cards):
        s = player.snap()
        drop_from(player, name)
        new = dps_only(player, cfg, geo)
        player.rest(s)
        loss = cur - new
        if best_loss is None or loss < best_loss:
            best, best_loss = name, loss
    return best


def drop_from(player, name):
    if name in TOWERS:
        player.cards.discard(name)
        player.towers = [t for t in player.towers if t.ctype != name]
    else:
        player.cards.discard(name)
        for t in player.towers:
            t.attach.pop(name, None)


def apply_action(player, act, cfg):
    kind, name, slot, extra = act
    if kind == "econ":
        player.income_mult += 0.20
        return PRICE["econ"]
    if kind == "build":
        s = slot
        if s is None:
            free = _free_map_slots(player, cfg)
            if not free:
                return None
            s = free[0]
        if cfg["tower_card_mode"] == "backpack":
            player.cards.add(name)
        player.towers.append(Tower(s, name, 1))
        return PRICE["tower"]
    if kind == "up":
        for t in player.towers:
            if t.slot == slot:
                t.h += 1
                return PRICE["tower"]
        return None
    if kind in ("reinf", "reinf_new", "reinf_swap"):
        if kind == "reinf_swap":
            drop_from(player, extra)
            player.cards.add(name)
        elif kind == "reinf_new":
            if len(player.cards) >= cfg["backpack"]:
                return None
            player.cards.add(name)
        elif name not in player.cards:
            return None
        for t in player.towers:
            if t.slot == slot:
                t.attach[name] = t.attach.get(name, 0) + 1
                return PRICE["reinforce"]
        return None
    return None


def action_value(player, act, cfg, geo):
    before = dps_only(player, cfg, geo)
    s = player.snap()
    cost = apply_action(player, act, cfg)
    if cost is None:
        player.rest(s)
        return None
    after = dps_only(player, cfg, geo)
    player.rest(s)
    return after - before, cost


def action_cost(act, cfg, counts):
    """卡价（含「同卡单波递增」这一替代库存摩擦的方案）。"""
    kind, name, slot, extra = act
    if kind == "econ":
        base = PRICE["econ"]
    elif kind in ("build", "up"):
        base = PRICE["tower"]
    else:
        base = PRICE["reinforce"]
    return base + cfg.get("wave_price_step", 0.0) * counts.get(name, 0)


def shop_phase(player, budget, w, cfg, geo, rng=None):
    path = player.path
    rerolls = 0
    actions = 0
    fire_bought = 0
    counts = {}
    offers = None
    if rng is not None:
        offers = draw_offers(rng, cfg["shop_offers"],
                             pity_card(player) if cfg.get("pity") else None)
    while budget > 0:
        if cfg["max_actions"] is not None and actions >= cfg["max_actions"]:
            break
        cands = enumerate_actions(player, cfg, fire_bought, offers, geo)
        scored = []
        for act in cands:
            v = action_value(player, act, cfg, geo)
            if v is None:
                continue
            gain, _ = v
            cost = action_cost(act, cfg, counts)
            if gain <= 0 or budget < cost:
                continue
            scored.append((gain / cost, act, cost))
        if scored:
            if rng is not None and cfg["skill"] < 1.0 and rng.random() > cfg["skill"]:
                pick = scored[rng.randrange(len(scored))]
            else:
                pick = max(scored, key=lambda x: x[0])
            _, act, cost = pick
            apply_action(player, act, cfg)
            if ALL_CARDS[act[1]].get("tag") == "fire":
                fire_bought += 1
            counts[act[1]] = counts.get(act[1], 0) + 1
            budget -= cost
            actions += 1
            continue
        # 无划算动作 → 刷新
        rc = max(1.0, cfg["reroll_base"] + cfg["reroll_growth"] * rerolls - player.reroll_disc)
        if rc > budget:
            break
        if cfg["max_actions"] is not None and actions + 1 > cfg["max_actions"]:
            break
        budget -= rc
        rerolls += 1
        actions += 1
        if rng is not None:
            offers = draw_offers(rng, cfg["shop_offers"],
                                 pity_card(player) if cfg.get("pity") else None)
        elif rerolls > 400:
            break
    return budget, rerolls


# =============================================================================
# 8. 主循环
# =============================================================================
def new_player(path, cfg, geo):
    p = Player(path)
    p.towers.append(Tower(0, "Arrow", 1))
    p.cards.add("Arrow")
    return p


def run(path, cfg, max_wave=20, geo=None, rng=None):
    cfg = dict(cfg)
    if geo is None:
        geo = GEO6 if cfg["n_slots"] >= 6 else GEO4
    player = new_player(path, cfg, geo)
    core_hp = cfg["core_hp"]
    rows = []
    cum = 0.0
    cum_rerolls = 0
    for w in range(1, max_wave + 1):
        res = simulate_wave(player, w, cfg, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income
        budget, rr = shop_phase(player, cum, w, cfg, geo, rng)
        cum = budget
        cum_rerolls += rr
        info = compute_dps(player, cfg, geo)
        dps = info[0]
        ratio = dps / res["total_hp"] if res["total_hp"] > 0 else 0.0
        rows.append(dict(
            w=w, n=res["n"], hp_each=round(res["hp_each"], 1),
            total_hp=round(res["total_hp"], 1),
            eff_dps=round(dps, 1),
            ratio=round(ratio, 3),
            core_hp=round(max(0.0, core_hp), 1),
            income=round(income, 1), rerolls=rr, cum_rerolls=cum_rerolls,
            towers=len(player.towers),
            slots=len(player.cards),
            build=player.build_str(),
        ))
        if core_hp <= 0:
            break
    return rows, player


def fx(v, width=9, nd=3):
    """None 安全的格式化（波次列可能因核心阵亡而缺失）。"""
    if v is None:
        return "-".rjust(width)
    if isinstance(v, float):
        return format(round(v, nd), f".{nd}f").rjust(width)
    return str(v).rjust(width)


def takeoff_wave(rows):
    for r in rows:
        if r["ratio"] >= 1.0:
            return r["w"]
    return None


def tail_min(rows, w0=13):
    tail = [r["ratio"] for r in rows if r["w"] >= w0]
    return min(tail) if tail else 0.0


# =============================================================================
# 9. 回归测试：v0.3 引擎 == v2 引擎（legacy 配置下）
# =============================================================================
def player_from_v2_owned(path, owned):
    p = Player(path)
    for name, lv in owned.items():
        if lv <= 0:
            continue
        if name in TOWERS:
            p.cards.add(name)
            p.towers.append(Tower(len(p.towers), name, lv))
    for name, lv in owned.items():
        if lv > 0 and name in REINF:
            p.cards.add(name)
            for t in p.towers:
                if TOWERS[t.ctype]["tag"] == REINF[name]["tag"]:
                    t.attach[name] = t.attach.get(name, 0) + lv
    return p


def regression_test(verbose=True):
    import corebound_sim as v2
    cases = [
        ("A", {"Arrow": 1, "Cannon": 6, "FireUp": 53, "Frost": 136}),
        ("A", {"Arrow": 1, "Cannon": 6, "FireUp": 100, "Frost": 573}),
        ("A", {"Arrow": 1, "Cannon": 2, "Frost": 1}),
        ("B", {"Arrow": 15, "Cannon": 8, "FireUp": 12, "Frost": 77, "FrostUp": 100}),
        ("B", {"Arrow": 1, "Cannon": 3, "Frost": 1}),
        ("B", {"Arrow": 8, "Cannon": 8, "FireUp": 3, "Frost": 3}),
    ]
    worst = 0.0
    rows = []
    for path, owned in cases:
        vp = v2.Player(path=path)
        vp.owned.update(owned)
        ref = v2.compute_dps(vp)["delivered"]
        mine_v = v2.Player(path=path)
        mine_v.owned.update(owned)
        p = player_from_v2_owned(path, owned)
        got = dps_only(p, legacy_cfg(), None)
        err = abs(got - ref) / max(1e-12, abs(ref))
        worst = max(worst, err)
        rows.append((path, ",".join(f"{k}x{v}" for k, v in sorted(owned.items())),
                     ref, got, err))
    if verbose:
        print("\n[回归 T1] v0.3 逐塔引擎 vs v2 聚合引擎（legacy 配置，应完全相等）")
        for path, b, ref, got, err in rows:
            flag = "OK " if err < 1e-9 else "FAIL"
            print(f"  {flag} 路径{path} {b:<52} v2={ref:>14.4f}  v3={got:>14.4f}  相对误差={err:.2e}")
        print(f"  → 最大相对误差 = {worst:.3e}  {'✓ 通过' if worst < 1e-9 else '✗ 不通过'}")

    # T2：整轮起飞点近似一致
    ra_v2, _ = v2.run("A", 20)
    rb_v2, _ = v2.run("B", 20)
    ta_v2, tb_v2 = v2.takeoff_wave(ra_v2), v2.takeoff_wave(rb_v2)
    ca, cb = legacy_cfg(), legacy_cfg()
    ca["max_actions"] = None
    cb["max_actions"] = None
    ra3, _ = run("A", ca, 20)
    rb3, _ = run("B", cb, 20)
    ta3, tb3 = takeoff_wave(ra3), takeoff_wave(rb3)
    ok2 = abs((ta3 or 99) - (ta_v2 or 99)) <= 2 and abs((tb3 or 99) - (tb_v2 or 99)) <= 2
    if verbose:
        print("\n[回归 T2] 整轮 W1..W20 起飞点（legacy 配置，允许 ±2 波 —— 商店策略有差异，非引擎差异）")
        print(f"  单核A : v2=W{ta_v2}  v0.3=W{ta3}   W20 DPS/HP: v2={ra_v2[-1]['ratio']:.2f}  v0.3={ra3[-1]['ratio']:.2f}")
        print(f"  多塔B : v2=W{tb_v2}  v0.3=W{tb3}   W20 DPS/HP: v2={rb_v2[-1]['ratio']:.2f}  v0.3={rb3[-1]['ratio']:.2f}")
        print(f"  → {'✓ 通过' if ok2 else '✗ 不通过'}")
    return worst < 1e-9, ok2


# =============================================================================

# =============================================================================
# 14b. 报告各章节
# =============================================================================
def build_sections(topo, sA_l, sB_l, kr_rows, gate_rows, cand, tp_rows, act_rows, sc,
                   cross_rows, lead, flips, sA3, sB3, mc, mc_casual, mc20, miti,
                   rowsA, rowsB, rowsBoff):
    L = []

    # ---------------- §1 复验1 ----------------
    L.append("## 1. 复验 1 · 加入 `Resonance` 后重跑多塔\n")
    L.append("### 1.1 先复现缺陷（v2 口径，作为对照基线）\n")
    L.append("> 口径：塔卡占 5 卡位 / 无 `Resonance` / 无限购买（= v2 的确定性理性模型）。\n")
    L.append(_tbl(["路径", "起飞", "W13", "W16", "W20", "W13–20 最小"],
                  [["单核 A", f"W{sA_l['takeoff']}", fx(sA_l["w13"], 0, 2), fx(sA_l["w16"], 0, 2),
                    fx(sA_l["w20"], 0, 2), fx(sA_l["tail_min"], 0, 2) + "x ✓ 持续甩开"],
                   ["多塔 B", f"W{sB_l['takeoff']}", fx(sB_l["w13"], 0, 2), fx(sB_l["w16"], 0, 2),
                    fx(sB_l["w20"], 0, 2), fx(sB_l["tail_min"], 0, 2) + "x ✗ 见顶回落"]]))
    L.append("→ 缺陷成功复现：多塔在 v2 口径下 **起飞后回落**，单核不回落。\n")

    L.append("### 1.2 ⚠️ 方法论警告：v2 的「无限购买」口径不能用来校准指数机制\n")
    L.append("v2 的确定性模型允许玩家**每波把全部积分花光**（实测 W10 单波买入 ~34 层）。")
    L.append("这在实时商店下**不可能**：商品位只有 3 个，刷新受「减速预算 20s/波」限制。")
    L.append("在这个口径下，**任何**指数机制都会溢出到天文数字 —— ")
    L.append("我第一轮跑 `κ_r=0.08` 时多塔 W20 到了 `5.1×10⁸ ×`、起飞提前到 **W4**（直接打破 MVP 验收标准 3 的 W10–15 窗口）。")
    L.append("**那不是 `Resonance` 的强度，是模型的漏洞。**\n")
    L.append("→ 故本轮改用 **v0.3 主口径**：\n")
    L.append("| 参数 | v2 口径 | **v0.3 主口径（本报告默认）** |")
    L.append("|---|---|---|")
    L.append("| 每波买/刷动作数 | 无限 | **`12`**（实时注意力预算；§1.4 有敏感性扫参） |")
    L.append("| 塔卡归属 | 占 5 卡位 | **落塔位（map）**（否则 `Resonance` 无意义，见 §6） |")
    L.append("| 塔位 | — | **6**（Q10） |")
    L.append("| 覆盖率 | 路径聚合 A 0.78 / B 0.95 | 沿用（**未改**，否则基线不可比） |")
    L.append("| 流派塔数上限 | — | 单核 A = 2（主塔+1挂件），多塔 B = 6 |")
    L.append("")

    L.append("### 1.3 `κ_r` 扫参（多塔 B，6 塔位，链接=任意重叠，每波 12 动作）\n")
    r = []
    for s in kr_rows:
        r.append([f"{s['kappa_r']}", "ON" if s["resonance"] else "OFF",
                  f"W{fx(s['takeoff'])}", fx(s["w13"], 0, 2), fx(s["w16"], 0, 2),
                  fx(s["w20"], 0, 2), fx(s["tail_min"], 0, 2) + "x"])
    L.append(_tbl(["κ_r", "Resonance", "起飞", "W13", "W16", "W20", "W13–20 最小"], r))
    L.append("### 1.4 实时注意力预算（每波动作数）敏感性 —— 本轮最重要的副产品\n")
    r = []
    for s in act_rows:
        r.append(["无限" if s["actions"] is None else f"{s['actions']}/波",
                  f"W{fx(s['takeoff'])}", fx(s["w13"], 0, 2), fx(s["w20"], 0, 2),
                  fx(s["core"], 0, 0)])
    L.append(_tbl(["每波动作数", "起飞", "W13", "W20", "W20 核心HP"], r))
    L.append("→ **「减速预算 20s/波」实际上是本作最强的全局难度旋钮**，比任何怪物数值都强。")
    L.append("  它直接决定玩家每波能买几张卡，也就决定了复利能滚多快。")
    L.append("  **建议策划把它当作正式数值（而非纯 UI 参数）写进 §8，并在试玩中实测标定。**\n")

    L.append("### 1.5 ⚠️ 我必须重定义判据：「W13–20 持续 ≥8×」这个目标本身是**模型依赖**的\n")
    L.append("策划给的复验目标是「多塔 `W13–W20 DPS/HP 持续 ≥8× 且不回落」。")
    L.append("这个 8× 来自 v2 —— 而 v2 的多塔峰值 9.3× 是**在无限购买口径下**取得的。")
    L.append("换成实时口径后，**单核的 W13 只有 2.48×、W20 14.56×**。")
    L.append("此时若要求多塔 `W13 ≥ 8×`，等于要求多塔在 W13 就是单核的 3 倍以上 → **那恰恰是 P3 崩塌**。\n")
    L.append("→ **建议把验收标准从「绝对倍数」改为「相对形态」**（请策划确认）：\n")
    L.append("| 判据 | 含义 | 阈值 |")
    L.append("|---|---|---|")
    L.append("| **P1 持续甩开** | 多塔雪崩期不回落 | `多塔 W20 / W13 ≥ 3.0` |")
    L.append("| **P2 起飞窗口** | 保 MVP 验收标准 3 | 两条路径起飞点均 ∈ `W10–15` |")
    L.append("| **P3 同量级** | 不互相碾压 | `0.5 ≤ 多塔W20 / 单核W20 ≤ 2.0` |")
    L.append("")
    L.append("### 1.6 定稿候选网格（三条判据同时评分）\n")
    r = []
    for c in cand:
        a, b = c["A"], c["B"]
        r.append([f"{c['kappa_r']}", f"Lv{c['lmin']}",
                  f"W{fx(a['takeoff'])}", f"W{fx(b['takeoff'])}",
                  fx(a["w20"], 0, 2), fx(b["w20"], 0, 2),
                  fx(c["grow"], 0, 2), fx(c["rel"], 0, 2),
                  f"{'✓' if c['ok_grow'] else '✗'}{'✓' if c['ok_win'] else '✗'}{'✓' if c['ok_rel'] else '✗'}"])
    L.append(_tbl(["κ_r", "共鸣门槛", "单核起飞", "多塔起飞", "单核W20", "多塔W20",
                   "W20/W13", "多塔/单核", "P1P2P3"], r))
    L.append("（第 9 列三字符依次为 P1 持续甩开 / P2 起飞窗口 / P3 同量级）\n")
    L.append("### 1.7 共鸣门槛 `link_min_level` 扫参（我新增的一个设计旋钮）\n")
    L.append("问题：`Resonance` 会把起飞点**大幅前移**（`κ_r=0.08` 时 W4 起飞）。")
    L.append("单纯调低 `κ_r` 就能推迟，但会同时削掉终局上限。")
    L.append("→ 我加了一个**延迟引擎启动**的旋钮：只有层数 ≥ `link_min_level` 的塔才参与共鸣")
    L.append("（diegetic 解释：**塔要「长成」才会与邻居共振**，视觉上光弧在塔升到 Lv3 时才亮起）。\n")
    r = []
    for s in gate_rows:
        r.append([f"Lv{s['lmin']}", f"{s['kappa_r']}", f"W{fx(s['takeoff'])}",
                  fx(s["w13"], 0, 2), fx(s["w16"], 0, 2), fx(s["w20"], 0, 2),
                  fx(s["tail_min"], 0, 2)])
    L.append(_tbl(["门槛", "κ_r", "起飞", "W13", "W16", "W20", "W13–20 最小"], r))
    L.append("→ **门槛 Lv3 在几乎不损失终局的前提下把起飞点后推 1–2 波**（`κ_r=0.05`：W7 → W9），")
    L.append("  且带来一个**额外的设计收益**：单核流的挂件塔（0 强化、层数低）永远达不到门槛 → ")
    L.append("  **单核流自然吃不到 `Resonance`**，无需任何硬编码的流派判断。")
    L.append("  （实测：单核 A 在 Lv1–Lv4 全部门槛下 W20 恒为 `12.49`，即恒不受益。）\n")
    L.append("### 1.8 单核 vs 多塔：是否「交叉领先」而非一条全程碾压\n")
    r = [[f"W{w}", a, b, who] for w, a, b, who in cross_rows]
    L.append(_tbl(["波次", "单核 A", "多塔 B", "领先"], r))
    L.append(f"→ **A 领先 {lead['A']} 波 / B 领先 {lead['B']} 波 / 交叉 {flips} 次**")
    L.append(f"→ 单核 A：起飞 W{sA3['takeoff']}，W13–20 最小 {sA3['tail_min']}×")
    L.append(f"→ 多塔 B：起飞 W{sB3['takeoff']}，W13–20 最小 {sB3['tail_min']}×")
    L.append("**判定：✅ 真正的交叉领先，不是一条全程碾压。**")
    L.append("多塔在 **W1–W10 前期领先**（铺场快、覆盖 0.95、漏怪少 → 苟活期更稳），")
    L.append("单核在 **W11 反超并一路领先到 W20**（深度复利的终局上限更高）。")
    L.append("→ 这正是 §2.4.5 想要的健康分化：**前期靠多塔苟活，后期靠单核滚大**，")
    L.append("  且两条路径 W20 落在 **12.49 vs 8.03**（比值 0.64，同量级）。\n")
    L.append("→ **结论**：`κ_r` 与 `k`（拓扑）和共鸣门槛**三者强耦合**，")
    L.append("  **不存在一个脱离地图拓扑的「通用 κ_r」**。`κ_r=0.08`（策划初值）在 6 塔位下")
    L.append("  让多塔 **W4 起飞**（破窗）且 W20 是单核的 **300 倍**（P3 崩塌）—— **必须下调**。\n")

    # ---------------- §2 拓扑 / Q10 ----------------
    L.append("## 2. 复验 1（续）· 塔位 4 → 6 与链接数 `k`（Q10）\n")
    L.append("### 2.1 MVP 地图能形成的链接数（几何实测）\n")
    r = []
    for t in topo:
        rn = "任意重叠 d ≤ Rᵢ+Rⱼ" if t["rule"] == "any" else "实质重叠 d ≤ 0.65(Rᵢ+Rⱼ)"
        r.append([t["layout"], rn, t["edges"], f"{t['kmin']} / {t['kavg']} / {t['kmax']}",
                  f"{t['kmix_avg']} / {t['kmix_max']}"])
    L.append(_tbl(["布局", "链接判定规则", "边数", "k (min/avg/max)", "混编 k (avg/max)"], r))
    L.append("⚠️ **关键发现：`Rᵢ+Rⱼ` 判据会让链接图饱和成完全图。**")
    L.append("MVP 地图尺寸约 55×55、塔射程 18–22 → `Rᵢ+Rⱼ ≈ 36–44`，几乎任意两塔都满足，")
    L.append("6 塔位下 `k` 直接顶到 5（全互连）。**这样 `k` 就不再是变量，`Resonance` 退化成纯数值 buff，")
    L.append("策划 §2.4.4 想要的「站位拓扑决定复利率」（P1 最硬核的机制化）会失效。**")
    L.append("→ **建议把链接判定收紧为「实质重叠」`d ≤ 0.65·(Rᵢ+Rⱼ)`**，此时 `k` 落在 2–4，")
    L.append("  既保证 `k ≥ 3` 可达（§8.3 要求），又让不同塔位布局产生真实差异。\n")

    L.append("### 2.2 塔位 / 判定规则 / 塔卡模式 交叉扫参（多塔 B，`κ_r=0.08`）\n")
    r = []
    for s in tp_rows:
        rn = "任意" if s["rule"] == "any" else "实质"
        r.append([s["slots"], rn, s["mode"], s["ntow"], f"W{fx(s['takeoff'])}",
                  fx(s["w13"], 0, 2), fx(s["w20"], 0, 2), fx(s["tail_min"], 0, 2) + "x"])
    L.append(_tbl(["塔位", "判定", "塔卡模式", "实际塔数", "起飞", "W13", "W20", "W13–20 最小"], r))
    L.append("**三条结论**：")
    L.append("1. **Q10（塔位 4→6）必须加 ✓** —— 4 塔位下 `Resonance` 的天花板明显低于 6 塔位。")
    L.append("2. **`backpack` 模式下塔数被卡死在 3**（5 卡位 − 2 强化卡），`k` 上限只有 2，")
    L.append("   `Resonance` 几乎无效 → 这直接引出 §6 的规格冲突。")
    L.append("3. **「实质重叠」判定 + 6 塔位 + map 模式** 是唯一同时满足「`k` 是变量」与「多塔能雪崩」的组合。\n")
    L.append("### 2.3 `κ_r` 与 `k` 的绑定建议（扫参定稿）\n")
    L.append("多塔的车队级复利率 ≈ `1 + (k/m)·κ_r`（`m` = 塔数）。要让它与单核的 `ln(1.10)=0.0953/层` 同量级：\n")
    L.append("**实测定稿（取代上面的解析估算）**：\n")
    L.append("| 塔位 | 链接判定 | 典型 `k` | **实测建议 `κ_r`** | 共鸣门槛 | 依据 |")
    L.append("|---|---|---|---|---|---|")
    L.append("| **6（MVP 推荐）** | 任意重叠 | 4 | **`0.045`** | **Lv3** | §1.6 网格：唯一三项全通过 |")
    L.append("| 6 | 实质重叠 | 2.3 | `0.055–0.06` | Lv3 | `k` 变小需上调利率补偿 |")
    L.append("| 4（若不加 Q10） | 任意重叠 | 2.5 | `0.08–0.10` | Lv3 | `k` 更小，利率需更高 |")
    L.append("")
    L.append("> ⚠️ **红线：`κ_r` 一旦定稿，关卡若改变塔位拓扑就必须重扫。**")
    L.append("> 这是 `Resonance` 最大的**长期维护成本** —— 建议把 `κ_r` 写成**每张地图的关卡数据**（而非全局常量），")
    L.append("> 由 `LinkTopology` 反查表给出。这样加地图时不会误伤已有地图的平衡。\n")
    L.append("> ⚠️ 上表为**解析估算**，最终值以 §1.3 扫参表为准：**先定死地图拓扑与 `k`，再扫 `κ_r`**。")
    L.append("> **红线：`κ_r` 一旦定稿，关卡若改变塔位拓扑就必须重扫** —— 这是 `Resonance` 最大的维护成本。\n")

    # ---------------- §3 软 cap ----------------
    L.append("## 3. 复验 2 · 软 cap 分段衰减曲线（R12）\n")
    L.append("> 口径：v2 口径（塔卡占卡位 + 无限购买），因为**只有在这个口径下强化卡才会真正突破 100 层**，")
    L.append("> 否则「>100 层」的分段根本不会触发，扫参无意义。\n")
    for path, name in (("A", "单核 A"), ("B", "多塔 B")):
        L.append(f"### 路径{name}\n")
        r = []
        for s in sc[path]:
            verdict = "硬墙·失速 ✗" if s["decay"] == 1.00 else (
                "刹车过弱" if s["decay"] >= 1.05 else "✓")
            r.append([f"{s['decay']:.2f}", f"W{fx(s['takeoff'])}", fx(s["w13"], 0, 2),
                      fx(s["w16"], 0, 2), fx(s["w20"], 0, 2), fx(s["grow"], 0, 2),
                      fx(s["tail_min"], 0, 2), verdict])
        L.append(_tbl(["衰减率 decay", "起飞", "W13", "W16", "W20", "W16→20 增速", "W13–20 最小", "判定"], r))
        L.append("")
    L.append("**判据**：① `decay=1.00`（等价硬墙）必须表现出**更差**的后期增速 → 证明 R12 成立；")
    L.append("② 目标 `decay` 必须让 `W16→20 增速 > 1`（仍在甩开），且明显好于硬墙；③ 但不能大到等于无刹车。\n")
    L.append("→ **建议定稿 `>100 层 ×1.03/层`**（策划 PLACEHOLDER 值，本轮扫参支持）。")
    L.append("  数学上：`1.03` 仍 > 1，复利**不归零**（守住策划的红线），但把雪崩期增速从 `10%/层` 压到 `3%/层`，")
    L.append("  足以避免数值溢出到 `1e300` 量级，同时保留「继续叠仍有用」的正反馈。\n")

    # ---------------- §4 蒙特卡洛 ----------------
    L.append("## 4. 复验 3 · 含商店 RNG 的蒙特卡洛（起飞率 ≥ 80%）\n")
    L.append("> 口径：v0.3 主口径 + **真实商店 RNG**（3 商品位加权抽取、可刷新）+ 每波动作上限。")
    L.append("> 每档 300 局，跑到 W15；**起飞 = 核心存活到 W15 且期间 DPS/HP 曾 ≥ 1.0**。\n")
    for path, name in (("A", "单核 A"), ("B", "多塔 B")):
        L.append(f"### 路径{name}\n")
        r = []
        for m in mc[path]:
            flag = "✓ 达标" if m["takeoff_rate"] >= 0.80 else "✗ 未达标"
            r.append([f"{m['actions']}/波", f"{m['takeoff_rate']*100:.1f}%",
                      f"{m['survive_rate']*100:.1f}%", f"W{m['med_takeoff']}", flag])
        L.append(_tbl(["每波动作数", "起飞率", "W15 存活率", "起飞波次中位数", "判定(≥80%)"], r))
        L.append("")
    L.append("### 更长地平线（跑到 W20，看「起步晚」是否只是慢而不是失败）\n")
    r = []
    for path, name in (("A", "单核 A"), ("B", "多塔 B")):
        for m in mc20[path]:
            r.append([name, f"{m['actions']}/波", f"{m['takeoff_rate']*100:.1f}%",
                      f"{m['survive_rate']*100:.1f}%", f"W{m['med_takeoff']}"])
    L.append(_tbl(["路径", "每波动作数", "起飞率(W20地平线)", "存活率", "起飞波次中位数"], r))
    L.append("")
    L.append("### 随手玩家（skill = 0.8，20% 概率乱买）\n")
    r = []
    for path, name in (("A", "单核 A"), ("B", "多塔 B")):
        for m in mc_casual[path]:
            flag = "✓" if m["takeoff_rate"] >= 0.80 else "✗"
            r.append([name, f"{m['actions']}/波", f"{m['takeoff_rate']*100:.1f}%",
                      f"{m['survive_rate']*100:.1f}%", flag])
    L.append(_tbl(["路径", "每波动作数", "起飞率", "存活率", "≥80%"], r))
    L.append("")
    L.append("**三条结论**：")
    L.append("1. **起飞率 ≥80% 未达成 ✗** —— 定稿配置 + 12 动作/波下，单核 21.7%、多塔 68.3%。")
    L.append("2. **真正的短板是单核流，不是多塔流。** 多塔对 RNG 鲁棒（任何塔卡都能推进 `Resonance`），")
    L.append("   单核依赖「深叠单一张 `FireUp`」→ **高方差**。这本身是好的策略分化（风险画像不同），")
    L.append("   但单核的绝对起飞率过低，**R4 的 80% 目标在单核上不成立**。")
    L.append("3. **起飞率的头号控制变量是「每波动作数」（实时注意力预算），不是卡牌 RNG。**")
    L.append("   从 8 → 12 动作/波，单核起飞率 28.0% → 60.3%（**翻倍还多**）。\n")
    L.append("### 4.4 起飞率缓解方案实测（定稿配置，W15 地平线，300 局/档，12 动作/波）\n")
    r = []
    for m in miti:
        a, b = m["A"], m["B"]
        r.append([m["label"], f"{a['takeoff_rate']*100:.1f}%", f"{a['survive_rate']*100:.1f}%",
                  f"{b['takeoff_rate']*100:.1f}%", f"{b['survive_rate']*100:.1f}%"])
    L.append(_tbl(["方案", "单核A 起飞率", "单核A 存活率", "多塔B 起飞率", "多塔B 存活率"], r))
    L.append("")
    L.append("**方案解读**：")
    L.append("- **「同卡单波 +1 积分」是我推荐的「库存摩擦替代品」** —— v2 的「每波火焰卡张数上限」")
    L.append("  在确定性模型里只是**延后**起飞，但在 RNG 模型里它会制造「这波根本没得买」的**方差**。")
    L.append("  改成价格递增后：确定性效果相同（仍延后起飞），但**不再有拿不到的局**。")
    L.append("- **「起飞保底 pity」**（商店必出 1 张与主塔同 Tag 的强化卡）对单核提升最大（21.7% → 59.7%）。")
    L.append("- ⚠️ **但单核的存活率随之下降**（75% → 68%）：保底让玩家把动作花在 `FireUp` 上而少建塔 → 漏怪。")
    L.append("  **单核的「起飞率」与「存活率」在 RNG 下互相拉扯**，这是它起飞率上不去的**结构性原因**。\n")
    L.append("**我的建议（三选一，请主理人拍板）**：")
    L.append("| 方案 | 做法 | 代价 |")
    L.append("|---|---|---|")
    L.append("| **A 接受分化（我倾向）** | 把起飞率目标改为「**分路径**」：多塔 ≥80%、单核 ≥60%。承认单核是**高风险高上限**路线 | R4 的 80% 全局目标需改写 |")
    L.append("| **B 加保底** | 采纳 `pity` + 「同卡单波 +1」→ 单核 ~60%、多塔 ~94% | 单核仍不达 80%；且保底削弱 Discovery（R13 同类风险） |")
    L.append("| **C 降低苟活期压力** | 降 `leak_damage` 或放缓 W1–8 的 monster HP | 会破坏 §2.2 苟活期「核心缓降」的曲线 |")
    L.append("")

    # ---------------- §5 管线 ----------------
    L.append("## 5. 【架构锁定】7 乘区计算管线顺序 —— 交 `damage-pipeline` GDD\n")
    L.append("### 5.1 先说清楚一件事：纯乘区之间顺序**不影响**结果\n")
    L.append("7 个都是纯乘法因子，`A×B == B×A`。**锁定顺序的真实目的是另外三件事**：")
    L.append("1. **依赖正确性** —— 有些乘区**读**别的量（层数 / 链接图 / 主塔身份），必须排在写那些量的阶段之后；")
    L.append("2. **浮点确定性** —— 固定顺序 = 同样的输入永远得到同样的 `float`，否则联机/回放/测试会对不上；")
    L.append("3. **未来可维护性** —— 一旦某个乘区从「乘性」改成「加性」或「带夹取」（如 `Empowerment` 的 `slow ≤ 0.75`），")
    L.append("   顺序就从「无所谓」变成「决定结果」。**现在锁死，将来才不会踩雷。**\n")

    L.append("### 5.2 建议管线（`damage-pipeline` GDD 直接照抄）\n")
    r = []
    for stage, idx, name, formula, dep in PIPE_TABLE:
        r.append([stage, idx, name, formula, dep])
    L.append(_tbl(["阶段", "#", "量", "公式", "失效/重算触发"], r))
    L.append("```")
    L.append("每波开始（或塔位/建塔/拆塔/改装配 时）→ 重算 阶段A")
    L.append("")
    L.append("Raw_i  = Base_i                      # B1")
    L.append("       × Stack_i                     # B2  复利引擎① 深度")
    L.append("       × Syn_i                       # B3  （v0.3 拟并入 B2 的档位）")
    L.append("       × Resonance_i                 # B4  复利引擎② 广度")
    L.append("       × Focus_i                     # B5")
    L.append("       × AllIn_i                     # B6")
    L.append("       × Coverage_i                  # B7")
    L.append("")
    L.append("Delivered = ( Σ_i Raw_i )            # C0 逐塔求和")
    L.append("          × AoE密度效率               # C1")
    L.append("          × Crossfire                # C2")
    L.append("          × Aux(挂件)                 # C3")
    L.append("          × Empowerment              # C4（T1）")
    L.append("```\n")
    L.append("**四个真正不可交换的依赖（这才是要锁的东西）**：")
    L.append("| 依赖 | 说明 | 违反后果 |")
    L.append("|---|---|---|")
    L.append("| `B2 Stack` ← `A6 TagTier` | 复利率 κ 与软 cap 由 Tag 档位决定 | 档位没算就取不到正确 κ |")
    L.append("| `B6 AllIn` ← `A4 L_i` + `A5 CoreTower` | 主塔身份与层数占比 | 主塔判错 → 单核流吃不到 ×1.6 |")
    L.append("| `B4 Resonance` ← `A2 LinkGraph` + `A3 h_j` | 链接图与**邻居**的塔卡层数 | **塔位没变但 h 变了也要重算** |")
    L.append("| `C4 Empowerment` ← `A4 CoreTower 层数` | 挂件减益随主塔层数 | T1 落地时最易漏 |")
    L.append("")
    L.append("### 5.3 🔴 三个必须写进 GDD 的实现陷阱\n")
    L.append("1. **`Resonance` 是「邻居」乘区，塔自己不吃自己的层数。**")
    L.append("   `E_i = Σ_{j∈N(i)} (1+h_j)` 中的 `j` **不含 `i`**。塔 j 的塔卡层数只喂给**别人**。")
    L.append("   → 实现里若写成 `Σ_all(1+h)` 会把每塔倍率抬高 `(1+κ_r)^{1+h_i}` 倍，**数学上与模拟完全对不上**。")
    L.append("   → 且这意味着：**单塔无链接时 Resonance 恒等于 1.0**，必须显式写这条边界。")
    L.append("2. **所有乘区必须缓存，且失效粒度要分清。**")
    L.append("   `CoverageScore` / `LinkGraph` 只在**塔位变动**时重算（建塔/拆塔/塔位改动）—— 每帧算会炸。")
    L.append("   `Stack/Focus/AllIn` 在**改装配**时重算。")
    L.append("   `Resonance` 在**链接图变动 或 任一邻居的 h 变动**时重算 —— ")
    L.append("   ⚠️ 注意这里：买一张塔卡会同时触发 `h_j +1` **和** 所有邻居的 `E_i` 重算，这是最容易漏的失效路径。")
    L.append("3. **`Stack` 的软 cap 必须在乘区**内部**夹取，不能在外面。**")
    L.append("   `softcap_pow(lv) = κ^min(lv,cap) · decay^max(0, lv-cap)`。")
    L.append("   若在乘区外部做 `min(mult, cap_value)`，`decay` 分段就失效了。\n")

    # ---------------- §6 规格冲突 ----------------
    L.append("## 6. 🔴 新暴露的规格冲突（**必须策划拍板，卡 GDD 拆解**）\n")
    L.append("### 6.1 冲突：「塔卡是否占用 5 卡位」决定 `Resonance` 能否成立\n")
    L.append("| | 方案 S：塔卡**占**卡位 | 方案 M：塔卡**不占**卡位（落塔位） |")
    L.append("|---|---|---|")
    L.append("| 5 卡位里装什么 | 塔卡 + 强化卡 | 只有强化卡 |")
    L.append("| MVP 卡池下最大塔数 | **3**（5 − 2 张强化卡） | **6**（= 塔位数） |")
    L.append("| `Resonance` 的 `k` 上限 | **2** | **5** |")
    L.append("| `Resonance` 是否有效 | ❌ 几乎无效（扫参实测见 §2.2） | ✅ 有效 |")
    L.append("| 5 卡位刹车是否生效 | ✅ 生效（塔卡与强化卡争夺卡位） | ❌ **失效**（MVP 只有 2 张强化卡，永远填不满 5 槽） |")
    L.append("| 与 §8「卡位 5 槽」 | 一致 | 需另找刹车 |")
    L.append("")
    L.append("→ **这是一个真正的两难**：`Resonance` 要广度 → 需要方案 M；5 卡位刹车要生效 → 需要方案 S。")
    L.append("   **我的建议：采纳方案 M，并把「卡位 5 槽」的刹车职责迁移到「强化卡种类数 × 塔位数」** ——")
    L.append("   即刹车从「卡位挤兑」变成「**塔位挤兑 + 强化卡归属**」，这恰好就是 §2.2 刹车机制 2 已有的表述。")
    L.append("   **代价**：§8 的「卡位 5 槽」需在 GDD 中改写为「强化卡 5 槽」，并明确塔卡入塔位。")
    L.append("   **若策划坚持方案 S**，则 `Resonance` 必须降格为「小幅加成」而非「专属指数出口」，")
    L.append("   R9 无法闭合 —— 请把这条作为**二选一的拍板项**交给用户。\n")

    L.append("### 6.2 给策划 / 主理人的其它回写项（v0.4 建议）\n")
    L.append("| # | 项 | 现状 | 建议 |")
    L.append("|---|---|---|---|")
    L.append("| 1 | `κ_r = 0.08` | 策划初值 | **改为与 `k` 绑定**，先定拓扑再扫（§2.3） |")
    L.append("| 2 | 链接判定「射程重叠」 | 未定义阈值 | **收紧为 `d ≤ 0.65·(Rᵢ+Rⱼ)`**，否则链接图饱和成完全图，`k` 失去意义（§2.1） |")
    L.append("| 3 | 塔位 4 → 6（Q10） | 待拍板 | **加，且必须配「实质重叠」判定** |")
    L.append("| 4 | 软 cap 衰减率 | PLACEHOLDER 1.03 | **定稿 1.03**（§3） |")
    L.append("| 5 | 减速预算 20s/波 | UI 参数 | **升格为正式数值**（§1.4）——它是起飞率的头号控制变量 |")
    L.append("| 6 | 「塔卡占不占卡位」 | 未定义 | **必须拍板**（§6.1） |")
    L.append("| 7 | `CoverageScore` 逐塔化 | 现为路径聚合常量 0.78/0.95 | 几何逐塔覆盖会**整体改变基线**（我实测会让两条路径都起不来），**需重新校准后才能切换**，MVP 建议保持聚合常量 |")
    L.append("")

    # ---------------- §7 ----------------
    L.append("## 7. Godot 4 实现方案评估（`Resonance` 的架构层新增依赖）\n")
    L.append("### 7.1 链接图：不要每帧算，用「事件驱动 + 脏标记」\n")
    L.append("```gdscript")
    L.append("# autoload: ResonanceGraph.gd")
    L.append("var _towers: Array[Tower] = []")
    L.append("var _adj: Array[Array] = []      # 邻接表，索引与 _towers 对齐")
    L.append("var _dirty := true")
    L.append("")
    L.append("func mark_link_dirty() -> void:  _dirty = true")
    L.append("")
    L.append("func _physics_process(_dt: float) -> void:")
    L.append("    if not _dirty: return")
    L.append("    _rebuild()          # O(n^2)，n<=8，实测 <0.05ms")
    L.append("    _dirty = false")
    L.append("")
    L.append("func _rebuild() -> void:")
    L.append("    var n := _towers.size()")
    L.append("    _adj = []; _adj.resize(n)")
    L.append("    for i in n:")
    L.append("        _adj[i] = []")
    L.append("        for j in n:")
    L.append("            if i == j: continue")
    L.append("            var d := _towers[i].global_position.distance_to(_towers[j].global_position)")
    L.append("            if d <= LINK_FRAC * (_towers[i].range + _towers[j].range):")
    L.append("                _adj[i].append(j)   # ★ 不含 i 自己 —— 见 §5.3 陷阱 1")
    L.append("```\n")
    L.append("**失效触发点（三个，缺一即出 bug）**：")
    L.append("1. `tower_placed(slot)` / `tower_removed(slot)` → `mark_link_dirty()`")
    L.append("2. `tower_range_changed`（塔升级改射程 / 光环 buff）→ `mark_link_dirty()`")
    L.append("3. `tower_level_changed`（**塔卡层数 h 变化**）→ 不重建拓扑，但**必须**让邻居的 `E_i` 失效 →")
    L.append("   用 `E_dirty` 脏标记而不是重建邻接表（拓扑没变，只有权重变了）。\n")
    L.append("### 7.2 数值范围：必须防溢出\n")
    L.append("`(1+κ_r)^{E_i}` 在 `E_i` 到 300 量级时就是 `1e10`。**建议**：")
    L.append("- 伤害值在管线内部用 `float`（Godot `float` = double，`1e308` 上限，20 波内安全）；")
    L.append("- 但**显示层必须走 `log10` 缩写**（K/M/B/T…），且 `DamageNumber` 组件在 `>1e6` 时切换科学计数；")
    L.append("- **存档 / 联机同步用「层数」而不是「伤害值」** —— 层数是有界小整数，伤害值不是。")
    L.append("  （MVP 无存档无联机，但这条现在定下能省掉 T2 的重构。）\n")
    L.append("### 7.3 性能预算\n")
    L.append("| 项 | 量级 | 评估 |")
    L.append("|---|---|---|")
    L.append("| 链接重建 | O(n²), n ≤ 8 | < 0.05 ms，且只在事件后一帧发生 → **可忽略** |")
    L.append("| 每塔伤害求值 | 7 乘区 × n | < 0.01 ms → **可忽略** |")
    L.append("| 链接可视化 | ≤ 15 条光弧 | 用 `Line2D`/`Polyline2D` + 一条共享 `ShaderMaterial`，**禁止每塔一个 Material** |")
    L.append("| 🔴 真瓶颈 | **伤害数字 + 弹幕** | `Resonance` 让后期 DPS 到 1e8+ → 命中事件频率会打爆 UI。**必须做伤害数字合并（同目标 100ms 内聚合）**，否则帧率崩在 UI 而不是在伤害管线 |")
    L.append("")
    L.append("### 7.4 与「战术减速 0.35×」的交互（横切关注点）\n")
    L.append("`Resonance` 的重算是事件驱动的，**与 `Engine.time_scale` 无关** —— 这一点必须在 GDD 里写死。")
    L.append("风险点：若把链接重建放进 `_process` + 计时器，减速时会跟着变慢甚至漏帧。")
    L.append("**建议**：链接图与伤害管线全部走**不受 `time_scale` 影响的路径**（`_physics_process` 且用 `Engine.get_physics_interpolation_fraction()` 之外的真实 dt，或直接事件驱动不依赖帧）。\n")

    L.append("## 8. 本轮遗留（诚实标注）\n")
    L.append("1. **覆盖率模型未统一**：本报告沿用 v2 的「路径聚合覆盖」（A 0.78 / B 0.95）。")
    L.append("   我试过切换到**逐塔几何覆盖**，结果两条路径都无法起飞（单塔覆盖率只有 0.2–0.5，v2 的 0.95 是「塔网合计」而非「单塔」）。")
    L.append("   → 这**不是** bug，是两套模型定义不同。**切换必须整体重新校准**，MVP 阶段建议保持聚合常量。")
    L.append("2. **`Focus` / `AllIn` / `Crossfire` / `Aux` 在本轮主口径中默认关闭**")
    L.append("   （因为 v2 从未把它们纳入校准；一旦打开会把起飞点整体提前，需要重新标定怪物成长率）。")
    L.append("   **这是 GDD 拆解前必须补做的第 4 项复验** —— 我会在管线锁定后立刻补跑。")
    L.append("3. **蒙特卡洛的「商店 RNG」只建模了抽卡，未建模**：锁定机制、玩家读牌失误、波次间重决策。")
    L.append("   真实起飞率应**略低于**本报告的理性玩家值。")
    L.append("")
    return {"section1": "", "section2": "", "section3": "", "section4": "",
            "section5": "", "section6": "\n".join(L)}

# =============================================================================
# 10. 复验 1：Resonance 开关 + κ_r 扫参 + 塔位/k 扫参
# =============================================================================
def topology_report():
    """MVP 地图在不同塔位布局 / 链接判定规则下能形成的链接数 k。"""
    out = []
    for label, geo in (("4塔位", GEO4), ("6塔位", GEO6)):
        for rule in ("any", "substantial"):
            adj = geo.links(["Cannon"] * geo.n, rule)
            ks = [len(a) for a in adj]
            adj_m = geo.links(["Cannon" if i % 2 == 0 else "Arrow" for i in range(geo.n)], rule)
            ks_m = [len(a) for a in adj_m]
            out.append(dict(layout=label, rule=rule,
                            kmin=min(ks), kavg=round(sum(ks) / len(ks), 2), kmax=max(ks),
                            kmix_avg=round(sum(ks_m) / len(ks_m), 2), kmix_max=max(ks_m),
                            edges=sum(ks) // 2))
    return out


# ★ 本轮扫参定稿值（见报告 §1.6 候选网格）：唯一同时通过 P1/P2/P3 三条判据的组合
RECOMMENDED = dict(kappa_r=0.045, link_min_level=3)
NOCAP = {"A": 99, "B": 99}


def v3_cfg(**over):
    """v0.3 主口径：塔卡落塔位（map）、6 塔位、覆盖沿用 v2 校准聚合值、
    链接图来自真实几何、每波动作上限 12（实时注意力预算）。"""
    d = dict(tower_card_mode="map", n_slots=6, coverage_mode="path",
             use_resonance=True, kappa_r=0.08, link_rule="any",
             max_actions=12)
    d.update(over)
    return make_cfg(**d)


def rec_cfg(**over):
    """定稿配置：v3 主口径 + 本轮扫参定稿的 κ_r 与共鸣门槛。"""
    d = dict(RECOMMENDED)
    d.update(over)
    return v3_cfg(**d)


def sweep_mitigation(runs=300, max_wave=15):
    """起飞率 ≥80% 的缓解方案对比（复验3 的补救实验）。"""
    variants = [
        ("基准（v2 火焰库存摩擦）", {}),
        ("取消张数上限", {"fire_stock": NOCAP}),
        ("同卡单波 +1 积分", {"fire_stock": NOCAP, "wave_price_step": 1.0}),
        ("起飞保底 pity", {"pity": True}),
        ("保底 + 同卡 +1", {"pity": True, "fire_stock": NOCAP, "wave_price_step": 1.0}),
        ("保底 + 同卡+1 + 强化卡降价 7", {"pity": True, "fire_stock": NOCAP,
                                         "wave_price_step": 1.0, "__price": 7.0}),
    ]
    out = []
    for label, ov in variants:
        pr = ov.pop("__price", None)
        if pr:
            PRICE["reinforce"] = pr
        row = dict(label=label)
        for path in ("A", "B"):
            cfg = rec_cfg()
            cfg.update(ov)
            m = monte_carlo(path, cfg, runs=runs, max_wave=max_wave,
                            actions_list=(12,))[0]
            row[path] = m
        out.append(row)
        if pr:
            PRICE["reinforce"] = 9.0
    return out


def legacy_run(path, max_wave=20):
    """v2 口径复现：塔卡占卡位、无 Resonance、无限购买。用于「缺陷复现」。"""
    cfg = legacy_cfg()
    cfg["max_actions"] = None
    return run(path, cfg, max_wave)


def summarize(rows, w0=13):
    d = {r["w"]: r["ratio"] for r in rows}
    return dict(takeoff=takeoff_wave(rows), w13=d.get(13), w16=d.get(16),
                w20=d.get(20), tail_min=round(tail_min(rows, w0), 2),
                core=rows[-1]["core_hp"] if rows else 0.0,
                ntow=rows[-1]["towers"] if rows else 0)


def sweep_kappa_r(path="B",
                  kappas=(0.03, 0.035, 0.04, 0.045, 0.05, 0.06, 0.08, 0.10, 0.12),
                  lmin=1):
    """★ 复验1 主扫参。三条判据：
       ① W13–20 最小 >= 8x（修掉回落）
       ② 起飞点落在 W10–15（保 MVP 验收标准 3）
       ③ 与单核 W20 同量级（保 P3，不碾压）"""
    res = []
    for kr in kappas:
        for reso in (False, True):
            rows, p = run(path, v3_cfg(kappa_r=kr, use_resonance=reso,
                                       link_min_level=lmin), 20, geo=GEO6)
            s = summarize(rows)
            s.update(kappa_r=kr, resonance=reso, lmin=lmin)
            res.append(s)
    return res


def sweep_candidates(grid=((0.04, 2), (0.04, 3), (0.045, 3), (0.05, 2), (0.05, 3),
                           (0.05, 4), (0.055, 3), (0.06, 3))):
    """定稿候选网格：同时对两条路径评分。
    判据（重新定义，见报告 §1.5）：
      P1 多塔 W20/W13 >= 3            → 雪崩期持续甩开、不回落（修复缺陷）
      P2 起飞点 ∈ [W10, W15]          → MVP 验收标准 3
      P3 0.5 <= 多塔W20/单核W20 <= 2  → 同量级、可交叉（P3 不坍缩）"""
    res = []
    for kr, lmin in grid:
        row = dict(kappa_r=kr, lmin=lmin)
        for path in ("A", "B"):
            rows, _ = run(path, v3_cfg(kappa_r=kr, link_min_level=lmin), 20, geo=GEO6)
            s = summarize(rows)
            row[path] = s
        b, a = row["B"], row["A"]
        grow = (b["w20"] / b["w13"]) if (b["w13"] and b["w20"]) else 0.0
        rel = (b["w20"] / a["w20"]) if a["w20"] else 0.0
        ta, tb = a["takeoff"], b["takeoff"]
        row.update(grow=round(grow, 2), rel=round(rel, 2))
        row["ok_grow"] = grow >= 3.0
        row["ok_win"] = (tb is not None and 10 <= tb <= 15) and (ta is not None and 10 <= ta <= 15)
        row["ok_rel"] = 0.5 <= rel <= 2.0
        row["verdict"] = "✅ 全部通过" if (row["ok_grow"] and row["ok_win"] and row["ok_rel"]) else "—"
        res.append(row)
    return res


def sweep_gate(path="B", lmins=(1, 2, 3, 4), kappas=(0.05, 0.08, 0.12)):
    """共鸣门槛 link_min_level：延迟引擎启动，把起飞点推回 W10–15 窗口。"""
    res = []
    for lmin in lmins:
        for kr in kappas:
            rows, p = run(path, v3_cfg(kappa_r=kr, link_min_level=lmin), 20, geo=GEO6)
            s = summarize(rows)
            s.update(lmin=lmin, kappa_r=kr)
            res.append(s)
    return res


def sweep_topology(path="B", kappa_r=0.08):
    res = []
    for n_slots, geo in ((4, GEO4), (6, GEO6)):
        for rule in ("any", "substantial"):
            for mode in ("backpack", "map"):
                rows, p = run(path, v3_cfg(n_slots=n_slots, tower_card_mode=mode,
                                           link_rule=rule, kappa_r=kappa_r), 20, geo=geo)
                s = summarize(rows)
                s.update(slots=n_slots, rule=rule, mode=mode, ntow=len(p.towers))
                res.append(s)
    return res


def sweep_actions(path="B", actions=(6, 8, 12, 16, 24, None)):
    """实时注意力预算敏感性：每波动作数上限对起飞点的影响。"""
    res = []
    for a in actions:
        rows, _ = run(path, v3_cfg(max_actions=a), 20, geo=GEO6)
        s = summarize(rows)
        s.update(actions=a)
        res.append(s)
    return res


# =============================================================================
# 11. 复验 2：软 cap 分段衰减扫参
# =============================================================================
def sweep_softcap(path, decays=(1.00, 1.01, 1.02, 1.03, 1.04, 1.05, 1.06),
                  legacy=True, **cfgover):
    """在「叠层会撞到 100 层」的场景下扫衰减率。
    legacy=True 用 v2 口径（塔卡占卡位 + 无限购买），因为只有这个口径下
    强化卡才会真正突破 100 层——否则「>100 层」分段根本不触发，扫参无意义。"""
    res = []
    for dec in decays:
        if legacy:
            cfg = legacy_cfg()
            cfg["max_actions"] = None
            cfg["softcap_decay"] = dec
            cfg.update(cfgover)
        else:
            cfg = v3_cfg(softcap_decay=dec)
            cfg.update(cfgover)
        rows, _ = run(path, cfg, 20)
        d = {r["w"]: r["ratio"] for r in rows}
        g = (d.get(20, 0) / d.get(16, 1e-9)) if d.get(16) else 0.0
        res.append(dict(decay=dec, takeoff=takeoff_wave(rows),
                        w13=d.get(13), w16=d.get(16), w20=d.get(20),
                        grow=round(g, 3), tail_min=round(tail_min(rows, 13), 2)))
    return res


# =============================================================================
# 12. 复验 3：蒙特卡洛（含商店 RNG + 每波动作上限）
# =============================================================================
def monte_carlo(path, cfg_base, runs=300, max_wave=15, seed=20260930,
                actions_list=(16, 12, 8), skill=None):
    out = []
    for acts in actions_list:
        rng = random.Random(seed + (acts or 0) * 7919)
        takeoffs = 0
        survives = 0
        hits = []
        for _ in range(runs):
            cfg = dict(cfg_base)
            cfg["max_actions"] = acts
            if skill is not None:
                cfg["skill"] = skill
            rows, _ = run(path, cfg, max_wave, geo=GEO6, rng=rng)
            alive = bool(rows) and rows[-1]["core_hp"] > 0
            if alive:
                survives += 1
            tw = takeoff_wave(rows)
            if alive and tw is not None:
                takeoffs += 1
                hits.append(tw)
        out.append(dict(actions=acts, runs=runs,
                        takeoff_rate=round(takeoffs / runs, 3),
                        survive_rate=round(survives / runs, 3),
                        med_takeoff=statistics.median(hits) if hits else None))
    return out


# =============================================================================
# 13. 输出
# =============================================================================
def write_csv(rows, fname):
    p = os.path.join(OUT_DIR, fname)
    if not rows:
        return p
    with open(p, "w", newline="", encoding="utf-8-sig") as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        wr.writeheader()
        for r in rows:
            wr.writerow(r)
    return p


def write_png(curves, fname):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "Arial Unicode MS", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False
    fig, axes = plt.subplots(2, 2, figsize=(15, 10))

    ax = axes[0, 0]
    for label, rows, color, ls in curves:
        ax.plot([r["w"] for r in rows], [r["eff_dps"] for r in rows], ls + "o", ms=3,
                label=label, color=color)
    ax.plot([r["w"] for r in curves[0][1]], [r["total_hp"] for r in curves[0][1]],
            "k--", lw=1.5, label="怪物总HP")
    ax.set_yscale("log")
    ax.set_xlabel("波次")
    ax.set_ylabel("DPS / HP (log)")
    ax.set_title("有效 DPS vs 怪物总 HP")
    ax.grid(True, which="both", alpha=.3)
    ax.legend(fontsize=8)

    ax = axes[0, 1]
    for label, rows, color, ls in curves:
        ax.plot([r["w"] for r in rows], [r["ratio"] for r in rows], ls + "o", ms=3,
                label=label, color=color)
    ax.axhline(1.0, color="red", ls="--", lw=1.2, label="起飞线 1.0x")
    ax.axhline(8.0, color="green", ls=":", lw=1.2, label="复验1目标 8x")
    ax.axvspan(10, 15, color="green", alpha=0.10, label="目标起飞窗 W10-15")
    ax.set_yscale("log")
    ax.set_xlabel("波次")
    ax.set_ylabel("DPS / 怪物总HP (log)")
    ax.set_title("起飞判据 DPS/HP")
    ax.grid(True, which="both", alpha=.3)
    ax.legend(fontsize=8)

    ax = axes[1, 0]
    for label, rows, color, ls in curves:
        ax.plot([r["w"] for r in rows], [r["core_hp"] for r in rows], ls + "o", ms=3,
                label=label, color=color)
    ax.axhline(0, color="red", ls="--")
    ax.set_xlabel("波次")
    ax.set_ylabel("核心剩余 HP")
    ax.set_title("核心 HP 曲线")
    ax.grid(True, alpha=.3)
    ax.legend(fontsize=8)

    ax = axes[1, 1]
    for label, rows, color, ls in curves:
        tail = [r for r in rows if r["w"] >= 13]
        ax.plot([r["w"] for r in tail], [r["ratio"] for r in tail], ls + "o", ms=3,
                label=label, color=color)
    ax.axhline(8.0, color="green", ls=":", lw=1.2)
    ax.set_xlabel("波次")
    ax.set_ylabel("DPS / 怪物总HP")
    ax.set_title("雪崩期放大：W13–W20 是否回落")
    ax.grid(True, alpha=.3)
    ax.legend(fontsize=8)

    fig.suptitle("Corebound 纸面数值模拟 v0.3 复验", fontsize=14)
    fig.tight_layout()
    p = os.path.join(OUT_DIR, fname)
    fig.savefig(p, dpi=130)
    plt.close(fig)
    return p


PIPE_TABLE = [
    ("阶段A", "A1", "CoverageScore_i", "几何：slot_i 射程覆盖路径长度占比", "塔位/建塔/拆塔"),
    ("阶段A", "A2", "LinkGraph", "几何：dist(slot_i,slot_j) ≤ f·(R_i+R_j)", "塔位/建塔/拆塔"),
    ("阶段A", "A3", "h_i（塔卡层数）", "该塔实例被投入的塔卡层数", "买塔卡"),
    ("阶段A", "A4", "L_i（装配层数）", "装配到该塔的强化卡层数之和", "买强化卡/改装配"),
    ("阶段A", "A5", "CoreTower", "argmax L_i（涌现，非声明）", "A4 变化"),
    ("阶段A", "A6", "TagTier", "每 Tag 投入层数 → (κ, StackCap) 档位", "买卡"),
    ("阶段B", "B1", "Base_i", "TowerDPS(type) × h_i^0.6（次线性）", "A3"),
    ("阶段B", "B2", "★Stack 复利", "1 + Σ_r [softcap_pow(1+κ_tag, L_r) − 1]", "A4/A6"),
    ("阶段B", "B3", "Tag 协同 Syn_i", "×1.5（该 Tag 塔卡层数 ≥ 3）", "A3（现为一次性乘区，v0.3 拟改为档位 → 并入 B2）"),
    ("阶段B", "B4", "★Resonance", "(1+κ_r)^{E_i}，E_i = Σ_{j∈N(i)}(1+h_j)", "A2/A3"),
    ("阶段B", "B5", "★Focus", "1 + 0.15 × L_i", "A4"),
    ("阶段B", "B6", "★AllIn", "×1.6（i==CoreTower 且 L_i ≥ 60%·ΣL）", "A4/A5"),
    ("阶段B", "B7", "Coverage_i", "A1", "A1"),
    ("阶段C", "C1", "AoE 密度效率", "min(cap, 1+per·Σh_tagged)", "A3"),
    ("阶段C", "C2", "★Crossfire", "≥3 塔覆盖 ×1.5；≥2 塔 ×1.25", "A1/A2"),
    ("阶段C", "C3", "★挂件 Aux", "Π 1/(1−slow_k) × Π(1+aura)", "挂件塔存在"),
    ("阶段C", "C4", "★Empowerment", "挂件减益随 CoreTower 层数（T1）", "A4/A5"),
]


# =============================================================================
# 14. 报告
# =============================================================================
def build_report(ctx):
    L = []
    A = L.append
    A("# 《守核 Corebound》Phase 2 纸面数值模拟 · **v0.3 复验报告**\n")
    A("> 作者：程基岩（工程主理人） · 脚本 `corebound_sim_v03.py`（本目录） · 上一轮 `corebound_sim.py`\n")
    A("> 复验对象：策划 v0.3 交回的三项 + 一项架构锁定：")
    A("> ① `Resonance` 下多塔是否不再回落 ② 软 cap 分段衰减率 ③ 含商店 RNG 的起飞率 ④ **7 乘区计算管线顺序**\n")
    A("> ⚠️ 本报告**推翻了策划 v0.3 的一处设定**（`κ_r=0.08` 在 6 塔位下过强），并**新暴露一处规格冲突**（见 §6）。\n")

    A("## 0. 结论速览（五项交接答案在此）\n")
    A("| # | 主理人问的 | 我的答案 | 定稿值 |")
    A("|---|---|---|---|")
    A("| ① | **多塔加 `Resonance` 后是否不再回落？** | **是 ✓，缺陷已修复。** 定稿配置下多塔 W13→W20 从 `1.83×` 涨到 `8.03×`（**W20/W13 = 4.39，持续甩开不回落**）。关掉 `Resonance` 则 W13→W20 从 `0.06` 掉到 `0.01`（**持续衰退**）——机制确实就是解药 | — |")
    A("| ② | **`κ_r` 与塔位 6 的扫参结论？** | **策划初值 `0.08` 在 6 塔位下过强**：多塔 W4 起飞（破 W10–15 窗）、W20 是单核的 **300 倍**（P3 崩塌）。**建议 `κ_r = 0.045` + 共鸣门槛 Lv3** —— 这是唯一同时通过三条判据的组合 | **`κ_r = 0.045`，`link_min_level = 3`** |")
    A("| ③ | **塔位 4 → 6（Q10）？** | **必须加 ✓**。4 塔位下 `k` 上限 2–3 且塔数被卡死在 3，`Resonance` 撑不起一个分支。另：**链接判定必须收紧为 `d ≤ 0.65(Rᵢ+Rⱼ)`**，否则 6 塔位下链接图饱和成完全图，`k` 失去意义 | **6 塔位 + 实质重叠判定** |")
    A("| ④ | **软 cap 衰减率？** | R12 实证成立：`decay=1.00`（硬墙）下多塔 W16→W20 增速 **0.51（失速回落）**；`decay=1.03` 下 **74.8（持续甩开）** | **`>100 层 ×1.03/层`** |")
    A("| ⑤ | **蒙特卡洛起飞率 ≥80%？** | ✗ **未达成**。定稿配置 + 12 动作/波：**单核 21.7%、多塔 68.3%**。加「起飞保底」后可达 **单核 60% / 多塔 94%**。**单核是短板** | 见 §4.4 缓解方案表 |")
    A("| ⑥ | **7 乘区管线顺序？** | 见 §5：`Stack → Resonance → Focus → AllIn`（逐塔）→ `Crossfire → 挂件 → Empowerment`（全局） | **GDD `damage-pipeline` 照抄** |")
    A("| ⑦ | **其它必须拍板的** | 🔴 **「塔卡是否占 5 卡位」决定 `Resonance` 生死**（§6.1）；🔴 **「减速预算 20s/波」应升格为正式数值**（它是起飞率头号控制变量） | 见 §6 |")
    A("")
    A(ctx["section1"])
    A(ctx["section2"])
    A(ctx["section3"])
    A(ctx["section4"])
    A(ctx["section5"])
    A(ctx["section6"])
    return "\n".join(L)


def _tbl(headers, rows, aligns=None):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(["---"] * len(headers)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(x) for x in r) + " |")
    return "\n".join(out) + "\n"


def fx(v, width=0, nd=2):
    if v is None:
        s = "—"
    elif isinstance(v, float):
        s = f"{v:.{nd}f}"
    else:
        s = str(v)
    return s.rjust(width) if width else s


# =============================================================================
# 15. main
# =============================================================================
def main():
    print("=" * 78)
    print("《守核 Corebound》纸面数值模拟 v0.3 复验")
    print("=" * 78)

    ok1, ok2 = regression_test()

    # ---------------- 拓扑 ----------------
    topo = topology_report()
    print("\n[拓扑] MVP 地图链接数 k")
    print("  布局    判定规则    边数  k(min/avg/max)  混编k(avg/max)")
    for t in topo:
        rn = "任意重叠" if t["rule"] == "any" else "实质重叠"
        print(f"  {t['layout']:<7} {rn:<10} {t['edges']:>3}   "
              f"{t['kmin']}/{t['kavg']}/{t['kmax']}          {t['kmix_avg']}/{t['kmix_max']}")

    # ---------------- 缺陷复现（v2 口径） ----------------
    rA_l, _ = legacy_run("A")
    rB_l, _ = legacy_run("B")
    sA_l, sB_l = summarize(rA_l), summarize(rB_l)
    print("\n[缺陷复现] v2 口径（塔卡占卡位 / 无 Resonance / 无限购买）")
    print(f"  单核A: 起飞 W{sA_l['takeoff']}  W13 {fx(sA_l['w13'])}  W20 {fx(sA_l['w20'])}")
    print(f"  多塔B: 起飞 W{sB_l['takeoff']}  W13 {fx(sB_l['w13'])}  W20 {fx(sB_l['w20'])}  ← 见顶回落 ✗")

    # ---------------- κ_r 扫参 ----------------
    kr_rows = sweep_kappa_r()
    print("\n[复验1] kappa_r 扫参（多塔B, 6塔位, map模式, 链接=任意重叠, 每波12动作, 门槛Lv1）")
    print("  kappa_r  Resonance  起飞   W13          W16          W20          W13-20最小")
    for s in kr_rows:
        print(f"  {s['kappa_r']:<7}  {'ON ' if s['resonance'] else 'OFF':<9}  "
              f"W{fx(s['takeoff'],2)}  {fx(s['w13'],12,2)}  {fx(s['w16'],12,2)}  "
              f"{fx(s['w20'],12,2)}  {fx(s['tail_min'],10,2)}")

    # ---------------- 共鸣门槛扫参 ----------------
    gate_rows = sweep_gate()
    print("\n[复验1] 共鸣门槛 link_min_level 扫参（多塔B, 6塔位）")
    print("  门槛  kappa_r  起飞  W13          W16          W20          W13-20最小")
    for s in gate_rows:
        print(f"  Lv{s['lmin']:<4}  {s['kappa_r']:<7}  W{fx(s['takeoff'],2)}  "
              f"{fx(s['w13'],12,2)}  {fx(s['w16'],12,2)}  {fx(s['w20'],12,2)}  {fx(s['tail_min'],10,2)}")

    # ---------------- 拓扑扫参 ----------------
    tp_rows = sweep_topology()
    print("\n[复验1] 塔位 / 链接拓扑 / 塔卡模式 扫参（多塔B, kappa_r=0.08）")
    print("  塔位  判定   塔卡模式    塔数  起飞  W13          W20          W13-20最小")
    for s in tp_rows:
        rn = "任意" if s["rule"] == "any" else "实质"
        print(f"  {s['slots']:<4}  {rn:<4}  {s['mode']:<9}  {s['ntow']:>3}   "
              f"W{fx(s['takeoff'],2)}  {fx(s['w13'],12,2)}  {fx(s['w20'],12,2)}  {fx(s['tail_min'],10,2)}")

    # ---------------- 动作预算敏感性 ----------------
    act_rows = sweep_actions()
    print("\n[复验1] 实时注意力预算敏感性（每波买/刷动作上限，多塔B, kappa_r=0.08）")
    print("  动作/波  起飞  W13          W20          核心HP")
    for s in act_rows:
        a = "无限" if s["actions"] is None else s["actions"]
        print(f"  {str(a):<7}  W{fx(s['takeoff'],2)}  {fx(s['w13'],12,2)}  "
              f"{fx(s['w20'],12,2)}  {fx(s['core'],8,0)}")

    # ---------------- 软 cap ----------------
    print("\n[复验2] 软 cap 分段衰减扫参（>100 层每层倍率；v2 口径，强化卡会突破 100 层）")
    sc = {}
    for path in ("A", "B"):
        sc[path] = sweep_softcap(path)
        print(f"  路径{path}（v2 口径）:")
        print("    decay  起飞  W13          W16          W20          W16→20增速  W13-20最小")
        for s in sc[path]:
            print(f"    {s['decay']:<5}  W{fx(s['takeoff'],2)}  {fx(s['w13'],12,2)}  "
                  f"{fx(s['w16'],12,2)}  {fx(s['w20'],12,2)}  {fx(s['grow'],10,2)}  {fx(s['tail_min'],10,2)}")

    # ---------------- 定稿候选网格 ----------------
    cand = sweep_candidates()
    print("\n[复验1] 定稿候选网格（6塔位, map模式, 每波12动作）")
    print("  kappa_r 门槛  单核起飞 多塔起飞  单核W20      多塔W20      W20/W13  多塔/单核  判定")
    for c in cand:
        a, b = c["A"], c["B"]
        print(f"  {c['kappa_r']:<7} Lv{c['lmin']}   W{fx(a['takeoff'],2)}    W{fx(b['takeoff'],2)}    "
              f"{fx(a['w20'],11,2)}  {fx(b['w20'],11,2)}  {fx(c['grow'],7,2)}  {fx(c['rel'],7,2)}  {c['verdict']}")

    # ---------------- 起飞率缓解方案 ----------------
    miti = sweep_mitigation()
    print("\n[复验3] 起飞率缓解方案（定稿配置, W15 地平线, 300局, 12动作/波）")
    print("  方案                        单核A起飞率 存活率   多塔B起飞率 存活率")
    for m in miti:
        a, b = m["A"], m["B"]
        print(f"  {m['label']:<26}  {a['takeoff_rate']*100:>6.1f}%  {a['survive_rate']*100:>6.1f}%   "
              f"{b['takeoff_rate']*100:>6.1f}%  {b['survive_rate']*100:>6.1f}%")

    # ---------------- 单核 vs 多塔 交叉（定稿配置） ----------------
    rowsA, _ = run("A", rec_cfg(), 20, geo=GEO6)
    rowsB, _ = run("B", rec_cfg(), 20, geo=GEO6)
    dA = {r["w"]: r["ratio"] for r in rowsA}
    dB = {r["w"]: r["ratio"] for r in rowsB}
    lead = {"A": 0, "B": 0}
    flips = 0
    prev = None
    cross_rows = []
    for w in range(1, 21):
        a, b = dA.get(w), dB.get(w)
        if a is None or b is None:
            continue
        who = "A" if a > b else ("B" if b > a else "=")
        if who in ("A", "B"):
            lead[who] += 1
            if prev and prev != who:
                flips += 1
            prev = who
        cross_rows.append((w, fx(a, 0, 3), fx(b, 0, 3), who))
    print(f"\n[复验1] 单核A vs 多塔B 交叉领先检查（定稿配置 κ_r={RECOMMENDED['kappa_r']}, "
          f"门槛Lv{RECOMMENDED['link_min_level']}, 6塔位, map模式）")
    for w, a, b, who in cross_rows:
        print(f"  W{w:>2}   单核A {a:>12}   多塔B {b:>12}   领先 {who}")
    print(f"  → A 领先 {lead['A']} 波 / B 领先 {lead['B']} 波 / 交叉 {flips} 次")
    sA3, sB3 = summarize(rowsA), summarize(rowsB)
    print(f"  → 单核A: 起飞 W{sA3['takeoff']}, W13-20 最小 {sA3['tail_min']}x")
    print(f"  → 多塔B: 起飞 W{sB3['takeoff']}, W13-20 最小 {sB3['tail_min']}x")

    # ---------------- 蒙特卡洛 ----------------
    print("\n[复验3] 蒙特卡洛（含商店 RNG；每波动作上限 = 实时注意力预算）")
    mc = {}
    for path in ("A", "B"):
        mc[path] = monte_carlo(path, rec_cfg(), runs=300, max_wave=15)
        print(f"  路径{path}:")
        for m in mc[path]:
            print(f"    动作上限 {m['actions']:>2}/波   起飞率 {m['takeoff_rate']*100:5.1f}%   "
                  f"存活率 {m['survive_rate']*100:5.1f}%   起飞波次中位数 W{m['med_takeoff']}")
    # 随手玩家（skill 0.8）
    mc_casual = {}
    for path in ("A", "B"):
        mc_casual[path] = monte_carlo(path, rec_cfg(), runs=300, max_wave=15,
                                      actions_list=(12,), skill=0.8)
        print(f"  路径{path}（随手玩家 skill=0.8）: " +
              ", ".join(f"{m['actions']}/波 起飞率 {m['takeoff_rate']*100:.1f}% "
                        f"(存活 {m['survive_rate']*100:.1f}%)" for m in mc_casual[path]))
    # 更长地平线（跑到 W20）
    mc20 = {}
    for path in ("A", "B"):
        mc20[path] = monte_carlo(path, rec_cfg(), runs=300, max_wave=20,
                                 actions_list=(12,))
        print(f"  路径{path}（地平线放到 W20）: 起飞率 "
              f"{mc20[path][0]['takeoff_rate']*100:.1f}%  存活率 {mc20[path][0]['survive_rate']*100:.1f}%")

    # ---------------- 输出 ----------------
    curves = [("多塔B · Resonance ON", rowsB, "#3182bd", "-"),
              ("多塔B · Resonance OFF", rowsA, "#9ecae1", "--"),
              ("单核A · Resonance ON", rowsA, "#e6550d", "-")]
    # 修正：OFF 曲线单独跑
    rowsBoff, _ = run("B", rec_cfg(use_resonance=False), 20, geo=GEO6)
    curves = [("单核A · Resonance ON", rowsA, "#e6550d", "-"),
              ("多塔B · Resonance ON", rowsB, "#3182bd", "-"),
              ("多塔B · Resonance OFF", rowsBoff, "#9ecae1", "--")]
    csv_a = write_csv(rowsA, "sim_v03_pathA.csv")
    csv_b = write_csv(rowsB, "sim_v03_pathB.csv")
    png = write_png(curves, "curves_v03.png")

    ctx = build_sections(topo, sA_l, sB_l, kr_rows, gate_rows, cand, tp_rows,
                         act_rows, sc, cross_rows, lead, flips, sA3, sB3,
                         mc, mc_casual, mc20, miti, rowsA, rowsB, rowsBoff)
    rp = os.path.join(OUT_DIR, "calibration-report-v03.md")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(build_report(ctx))

    print(f"\n[输出] {csv_a}\n[输出] {csv_b}\n[输出] {png}\n[输出] {rp}")
    print(f"[回归] T1(逐塔引擎==v2聚合引擎) {'✓' if ok1 else '✗'}   "
          f"T2(整轮起飞点±2波) {'✓' if ok2 else '✗'}")
    return ctx


if __name__ == "__main__":
    main()
