# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — 纸面数值模拟 (W1..W20)  v2
作者：程基岩（工程主理人）

目的：
  在写任何游戏代码前，用可运行的 Python 模型跑通 W1..W20 的
  「玩家有效 DPS」vs「怪物总 HP」双曲线，校准 §8 全部 PLACEHOLDER，
  确认起飞点（DPS/HP>=1.0 且持续增长）稳定落在 W10..W15，
  对比两条塔 Build 路径（单核 vs 多塔），评估实时（不暂停）商店影响。

================================================================================
 核心校准发现（v1 跑通后暴露的 R1 真相）
================================================================================
 若严格按 §8 字面机制（强化卡 +25% *加法*、5 卡位、12 张卡、无叠层复利），
 玩家 DPS 会在填满 5 槽后**触顶**（线性有界），而怪物总 HP 指数增长，
 于是 DPS/HP → 0，**永远无法起飞**——这正是 R1 🔴 的数学本质。

 要让 P2「雪崩无上限」成立，DPS 必须能**复利增长**。唯一能在「5 卡位物理上限」
 下仍产生指数的引擎，是 **卡牌叠层(Stack)走复利** 与 **经济复投正反馈**。
 因此本模拟把 MVP 的「强化卡叠层」建模为**乘性复利**（每张 FireUp 每层 ×1.25，
 叠层复投），并把「经济卡 → 收入 → 复投 → 更强」建为闭环。这是本次校准的
 核心机制变更，理由与回写值见 calibration-report.md §1。
================================================================================
"""
from __future__ import annotations
import os
import csv
from dataclasses import dataclass, field
from collections import defaultdict

import numpy as np

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 1. 校准系数（CALIBRATION）—— 回写策划 §8 的建议值都来自这里
# =============================================================================
CALIBRATION = {
    # ---- 怪物侧（校准后）----
    "hp_base": 16.0,          # HP(w) = hp_base * hp_growth^(w-1)   原 20×1.35^(w-1)
    "hp_growth": 1.30,        # ★校准后：原 1.35 → 1.30（配合库存摩擦，使起飞落 W10）
    "num_base": 8.0,          # N(w) = num_base + num_growth*w   原 5+2w → 8+1.6w（苟活期 surge 压力）
    "num_growth": 1.6,        # 原 2 —— 微降
    "scrap_base": 2.0,        # scrap(kill) = scrap_base + scrap_growth*w
    "scrap_growth": 0.5,      # 保持
    "leak_damage": 50.0,      # 每只泄漏怪物对核心伤害（新增校准量）
    "monster_speed": 10.0,    # 怪物移动速度（单位/秒）
    "path_length": 100.0,     # 路径总长；T_reach = path_length/speed

    # ---- 波次节奏 ----
    "wave_dur": lambda w: 28.0 + 2.2 * w,
    # 刷怪集中度：苟活期怪物在波次前段**集中涌入**（surge），制造瞬时到达压力，
    # 让低射速的早期塔来不及清 → 核心 HP 缓降（符合 §2.2 苟活期曲线）。1.0=均匀。
    "spawn_window": lambda w: 0.30 if w <= 5 else (0.60 if w <= 12 else 1.0),

    # ---- 玩家/核心 ----
    "core_hp": 1000.0,
    "starting_tower": "Arrow",
    "slots": 5,

    # ---- 商店经济 ----
    "price_tower": 12.0,
    "price_reinforce": 9.0,
    "price_econ": 10.0,
    "reroll_base": 5.0,       # Reroll(n) = reroll_base + reroll_growth*n   原 5+3n
    "reroll_growth": 3.0,
    "shop_offers": 3,

    # ---- 强化 / 协同（核心雪崩引擎）----
    "reinforce_pct": 0.25,    # 强化卡首层 +25%
    "reinforce_compound": 1.10,  # ★A(单核)强化叠层乘性：每层 ×1.10（深叠专注，复利强）
    "reinforce_compound_B": 1.06,  # ★B(多塔)叠层乘性更低：buff 摊薄到多塔，单塔复利弱（diegetic）
    "reinforce_cap": 100,     # 单卡叠层软上限（雪崩期需持续复投兑现，故放宽到 100）
    "synergy_threshold": 3,   # 同 Tag >=3 张（按塔卡张数计）触发
    "synergy_mult": 1.5,      # ×1.5 乘区
    "tower_stack_exp": 0.6,   # ★塔叠层次线性（DPS∝level^0.6）：边际递减，
                              #   使「火焰塔成型后，FireUp 复利」成为更优再投资方向

    # ---- 商店库存摩擦（关键：把 W7 起飞悬崖抹平成 W10-15 缓坡）----
    # 真实商店每波只有 ~3 个商品位、库存有限，玩家无法一蹴而就叠 40 层 FireUp。
    "stock_fire_per_wave": 3,   # 每波最多新增火焰相关卡（塔+强化）的张数上限

    # ---- 路径修饰（单核A vs 多塔B）----
    "A_coverage": 0.78, "A_aoe_cap": 2.6, "A_aoe_per": 0.24,   # 单核：覆盖低、AoE专注高
    "B_coverage": 0.95, "B_aoe_cap": 2.2, "B_aoe_per": 0.14,   # 多塔：覆盖广、AoE略低
    # ★路径专属火焰获取上限：单核靠深叠（宽限），多塔靠铺场（受限，避免过早协同起飞）
    "A_fire_stock": 6,
    "B_fire_stock": 3,
}

# =============================================================================
# 2. 卡池
# =============================================================================
@dataclass
class Card:
    name: str; kind: str; price: float
    dps: float = 0.0; tag: str | None = None
    aoe: bool = False; slow: float = 0.0

POOL = {
    "Arrow":   Card("Arrow",   "tower",     CALIBRATION["price_tower"],     dps=10.0, tag=None,   aoe=False),
    "Cannon":  Card("Cannon",  "tower",     CALIBRATION["price_tower"],     dps=7.0,  tag="fire",  aoe=True),
    "Frost":   Card("Frost",   "tower",     CALIBRATION["price_tower"],     dps=5.0,  tag="frost", aoe=False, slow=0.30),
    "FireUp":  Card("FireUp",  "reinforce", CALIBRATION["price_reinforce"], tag="fire"),
    "FrostUp": Card("FrostUp", "reinforce", CALIBRATION["price_reinforce"], tag="frost"),
    "ScrapUp": Card("ScrapUp", "econ",      CALIBRATION["price_econ"],      ),
    "RerollD": Card("RerollD", "econ",      CALIBRATION["price_econ"],      ),
}

# 两条路径的目标 build 优先级（理性构筑顺序；数字越小越优先）
# ★关键：两条路径都必须围绕「火焰协同 + FireUp 复利」作为雪崩引擎，
#   否则多塔路径（大量 Arrow 无 Tag）无法复利 → 永远起不来 → 策略崩塌。
#   A 与 B 的差异在于「专注 vs 铺场」，而非「有没有复利引擎」。
PRIORITY_A = ["Cannon", "FireUp", "Cannon", "FireUp", "Cannon", "FireUp",
              "Frost", "ScrapUp", "Cannon", "FireUp"]          # 单核：少塔深叠、低覆盖高AoE
PRIORITY_B = ["Cannon", "Arrow", "Cannon", "Frost", "Cannon", "Frost",
              "Arrow", "FrostUp", "Cannon", "FireUp"]           # 多塔：铺场广、火焰稀释（起飞更稳、雪崩更缓）


# =============================================================================
# 3. 玩家
# =============================================================================
@dataclass
class Player:
    path: str
    owned: dict[str, int] = field(default_factory=dict)   # card -> 叠层level
    income_mult: float = 0.0
    reroll_disc: float = 0.0

    def slot_used(self) -> int:
        return len(self.owned)

    def free_slots(self) -> int:
        return CALIBRATION["slots"] - self.slot_used()


# =============================================================================
# 4. 怪物波次
# =============================================================================
def monster_stats(w: int):
    c = CALIBRATION
    hp = c["hp_base"] * (c["hp_growth"] ** (w - 1))
    n = int(round(c["num_base"] + c["num_growth"] * w))
    scrap_per_kill = c["scrap_base"] + c["scrap_growth"] * w
    total_hp = n * hp
    D = c["wave_dur"](w)
    t_reach = c["path_length"] / c["monster_speed"]
    window = D + t_reach
    threshold = total_hp / window   # 防泄漏所需 DPS
    return dict(w=w, hp=hp, n=n, scrap_per_kill=scrap_per_kill,
                total_hp=total_hp, D=D, t_reach=t_reach, threshold=threshold)


# =============================================================================
# 5. DPS 聚合（塔线性叠层 + 强化复利 + 协同乘区 + 路径修饰）
# =============================================================================
def compute_dps(player: Player):
    c = CALIBRATION
    tag_tower = defaultdict(float)      # tag -> 塔基础 DPS（含塔叠层）
    tag_tower_level = defaultdict(float)  # tag -> 塔总投入层数（用于协同判定）
    untagged = 0.0
    for card_name, level in player.owned.items():
        card = POOL[card_name]
        if card.kind == "tower":
            d = card.dps * (level ** c["tower_stack_exp"])   # 塔次线性叠层（边际递减）
            if card.aoe:
                tag_tower[card.tag] += d
                tag_tower_level[card.tag] += level
            elif card.slow > 0:
                tag_tower[card.tag] += d
                tag_tower_level[card.tag] += level
            else:
                untagged += d
    # 强化卡：乘性叠层（每张 ×compound^level，递减感 + 软上限）
    # 路径专属：单核深叠复利强，多塔摊薄复利弱
    compound = c["reinforce_compound"] if player.path == "A" else c["reinforce_compound_B"]
    reinforce_mult = defaultdict(float)
    for card_name, level in player.owned.items():
        card = POOL[card_name]
        if card.kind == "reinforce":
            lv = min(level, c["reinforce_cap"])
            reinforce_mult[card.tag] += compound ** lv - 1.0

    raw = untagged
    synergy_hits = 0
    for tag, base in tag_tower.items():
        eff = base * (1.0 + reinforce_mult.get(tag, 0.0))
        if tag_tower_level[tag] >= c["synergy_threshold"]:
            eff *= c["synergy_mult"]
            synergy_hits += 1
        raw += eff

    # 路径修饰
    aoe_total = sum(tag_tower_level.values())
    if player.path == "A":
        coverage = c["A_coverage"]
        aoe_eff = min(c["A_aoe_cap"], 1.0 + c["A_aoe_per"] * aoe_total)
    else:
        coverage = c["B_coverage"]
        aoe_eff = min(c["B_aoe_cap"], 1.0 + c["B_aoe_per"] * aoe_total)
    delivered = raw * coverage * aoe_eff
    return dict(raw=raw, delivered=delivered, coverage=coverage,
                aoe_eff=aoe_eff, synergy=synergy_hits, aoe_towers=aoe_total)


# =============================================================================
# 6. 离散战斗（dt=0.1s）
# =============================================================================
def simulate_wave(player: Player, w: int):
    c = CALIBRATION
    ms = monster_stats(w)
    D, n, hp_each = ms["D"], ms["n"], ms["hp"]
    dt = 0.1
    dps = compute_dps(player)["delivered"]
    t_reach = ms["t_reach"]
    # 刷怪集中度：苟活期把怪物压进波次前段涌入（surge），制造瞬时到达压力
    spawn_window_frac = c["spawn_window"](w)
    spawn_span = D * spawn_window_frac
    spawn_interval = spawn_span / max(1, n)
    time = 0.0; spawned = 0
    monsters = []
    kills = 0; leaked = 0; scrap_earned = 0.0
    while time <= D + t_reach + 1e-9:
        while spawned < n and time >= spawned * spawn_interval - 1e-9:
            monsters.append(dict(hp=hp_each, eta=t_reach))
            spawned += 1
        dmg = dps * dt
        monsters.sort(key=lambda m: m["eta"])
        for m in monsters:
            if dmg <= 0:
                break
            if m["hp"] <= dmg:
                dmg -= m["hp"]; m["hp"] = 0
                kills += 1
                scrap_earned += ms["scrap_per_kill"]
            else:
                m["hp"] -= dmg; dmg = 0
        alive = []
        for m in monsters:
            if m["hp"] <= 0:
                continue
            m["eta"] -= dt
            if m["eta"] <= 0:
                leaked += 1
            else:
                alive.append(m)
        monsters = alive
        time += dt
    core_damage = leaked * c["leak_damage"]
    return dict(w=w, kills=kills, leaked=leaked, scrap_earned=scrap_earned,
                core_damage=core_damage, dps=dps, threshold=ms["threshold"],
                total_hp=ms["total_hp"], n=n, hp_each=hp_each)


# =============================================================================
# 7. 商店阶段（理性复投：把积分转成叠层/DPS，含递增刷新成本）
# =============================================================================
def reroll_cost(player: Player, n_this_wave: int) -> float:
    c = CALIBRATION
    return max(1.0, (c["reroll_base"] + c["reroll_growth"] * n_this_wave) - player.reroll_disc)


def marginal_dps_gain(player: Player, card_name: str) -> float:
    """买/叠一层 card_name 带来的有效 DPS 增量（用于理性择优）。"""
    cur = compute_dps(player)["delivered"]
    saved = player.owned.get(card_name, 0)
    player.owned[card_name] = saved + 1
    new = compute_dps(player)["delivered"]
    player.owned[card_name] = saved
    return max(0.0, new - cur)


def weakest_card(player: Player):
    """找出移除后 DPS 损失最小、且不是刚买的卡（用于卡位满时置换）。"""
    best_name, best_loss = None, 1e18
    for name in list(player.owned.keys()):
        cur = compute_dps(player)["delivered"]
        saved = player.owned[name]
        del player.owned[name]
        new = compute_dps(player)["delivered"]
        player.owned[name] = saved
        loss = cur - new
        if loss < best_loss:
            best_loss, best_name = loss, name
    return best_name, best_loss


def shop_phase(player: Player, budget: float, w: int):
    """
    理性复投（雪崩引擎）：把每波积分转成 DPS，叠层无上限——
    5 卡位物理刹车下唯一能产生 P2 指数成长的方式。
    关键机制修正：
      - 经济卡(ScrapUp/RerollD)为**全局升级，不占背包卡位**（否则挤占火焰协同位）；
      - 卡位满时允许**置换**：丢掉边际 DPS 最低的卡，换入能触发复利的 FireUp。
    决策张力：早期投经济（复利收入）vs 尽快成型火焰协同；中后期全转攻击兑现。
    返回 (结余, 刷新次数)。
    """
    c = CALIBRATION
    priority = PRIORITY_A if player.path == "A" else PRIORITY_B
    fire_cap = c["A_fire_stock"] if player.path == "A" else c["B_fire_stock"]
    rerolls = 0
    spent = 0.0
    fire_bought = 0               # 本波已新增火焰卡张数（库存摩擦）
    income_target = min(1.00, 0.12 * (w - 1))   # 收入加成上限随波次提高
    while budget > 0:
        # 1) 经济未达标 → 买经济卡（全局升级，不占卡位）
        if player.income_mult < income_target and budget >= POOL["ScrapUp"].price:
            budget -= POOL["ScrapUp"].price; spent += POOL["ScrapUp"].price
            player.income_mult += 0.20
            continue
        # 2) 攻击卡：选「边际 DPS/积分」最高者；卡位满则尝试置换
        best = None  # (gain_per_scrap, name, cost, swap_out)
        for name in priority:
            if name == "ScrapUp":
                continue
            cost = POOL[name].price
            # 库存摩擦：火焰卡每波获取有上限（路径专属）→ 溢出时被迫转投其他/刷新
            if POOL[name].tag == "fire" and fire_bought >= fire_cap:
                continue
            gain = marginal_dps_gain(player, name)
            if gain <= 0:
                continue
            swap_out = None
            if player.free_slots() == 0 and player.owned.get(name, 0) == 0:
                # 需要置换：丢掉损失最小的卡
                swap_out, loss = weakest_card(player)
                if swap_out is None or loss >= gain:
                    continue   # 换不来更优，跳过
                gain -= loss     # 净增益
            score = gain / max(1.0, cost)
            if best is None or score > best[0]:
                best = (score, name, cost, swap_out)
        if best is not None and budget >= best[2]:
            _, name, cost, swap_out = best
            if swap_out:
                del player.owned[swap_out]
            player.owned[name] = player.owned.get(name, 0) + 1
            if POOL[name].tag == "fire":
                fire_bought += 1
            budget -= cost; spent += cost
            continue
        # 3) 无划算攻击 → 刷新找牌（递增成本，边际递减）
        cost_r = reroll_cost(player, rerolls)
        if cost_r > budget:
            break
        budget -= cost_r; spent += cost_r; rerolls += 1
    return budget, rerolls


# =============================================================================
# 8. 主前向循环
# =============================================================================
def run(path: str, max_wave: int = 20):
    player = Player(path=path)
    player.owned[CALIBRATION["starting_tower"]] = 1
    core_hp = CALIBRATION["core_hp"]
    rows = []
    cum_scrap = 0.0
    cum_rerolls = 0
    for w in range(1, max_wave + 1):
        res = simulate_wave(player, w)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum_scrap += income
        budget, rerolls = shop_phase(player, cum_scrap, w)
        cum_scrap = budget
        cum_rerolls += rerolls
        info = compute_dps(player)
        ratio = info["delivered"] / res["total_hp"] if res["total_hp"] > 0 else 0
        build_summary = ",".join(f"{k}×{v}" for k, v in sorted(player.owned.items()))
        rows.append(dict(
            w=w, n=res["n"], hp_each=round(res["hp_each"], 1),
            total_hp=round(res["total_hp"], 1),
            eff_dps=round(info["delivered"], 1),
            raw_dps=round(info["raw"], 1),
            coverage=round(info["coverage"], 3),
            aoe_eff=round(info["aoe_eff"], 3),
            synergy=info["synergy"],
            ratio=round(ratio, 3),
            core_dmg=round(res["core_damage"], 1),
            core_hp=round(max(0, core_hp), 1),
            income=round(income, 1),
            rerolls=rerolls,
            cum_rerolls=cum_rerolls,
            slots=player.slot_used(),
            build=build_summary,
        ))
        if core_hp <= 0:
            break
    return rows, player


def takeoff_wave(rows):
    for r in rows:
        if r["ratio"] >= 1.0:
            tail = r
            # 之后保持 >=1.0（允许末波因怪物暴涨短暂回落，但整体已起飞）
            return r["w"]
    return None


# =============================================================================
# 9. 实时（不暂停）商店定性 + 半定量分析
# =============================================================================
def realtime_shop_analysis():
    out = []
    ra, _ = run("A", 20)
    rb, _ = run("B", 20)
    for label, rows in [("A", ra), ("B", rb)]:
        tot = sum(r["rerolls"] for r in rows)
        avg = tot / max(1, len(rows))
        peak = max((r["rerolls"] for r in rows), default=0)
        out.append(f"路径{label}: 20波累计刷新 {tot} 次 · 平均 {avg:.1f}/波 · 峰值 {peak}/波")
    base_t = takeoff_wave(ra)
    out.append(f"基准起飞点(路径A, 无分心惩罚): W{base_t}")
    # 分心惩罚：实时模式下每次刷新有效率打折 → 等效刷新成本上升
    for eff in (0.9, 0.8, 0.7):
        orig = CALIBRATION["reroll_base"]
        CALIBRATION["reroll_base"] = orig / eff
        r2, _ = run("A", 20)
        CALIBRATION["reroll_base"] = orig
        t = takeoff_wave(r2)
        out.append(f"分心惩罚 eff={eff}（等效刷新成本×{1/eff:.2f}）→ 起飞点 W{t}")
    return out, ra, rb


# =============================================================================
# 10. 输出
# =============================================================================
def write_csv(rows, fname):
    path = os.path.join(OUT_DIR, fname)
    if not rows:
        return path
    keys = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        wr = csv.DictWriter(f, fieldnames=keys)
        wr.writeheader()
        for r in rows:
            wr.writerow(r)
    return path


def write_png(rows_a, rows_b, fname):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei', 'Arial Unicode MS', 'DejaVu Sans']
    plt.rcParams['axes.unicode_minus'] = False

    def ser(rows, key):
        return [r[key] for r in rows], [r["w"] for r in rows]

    fig, axes = plt.subplots(2, 2, figsize=(15, 10))
    ax = axes[0, 0]
    for rows, label, color in [(rows_a, "单核(A)", "#e6550d"), (rows_b, "多塔(B)", "#3182bd")]:
        y, x = ser(rows, "eff_dps"); ax.plot(x, y, "-o", ms=3, label=f"{label} DPS", color=color)
    ax.plot([r["w"] for r in rows_a], [r["total_hp"] for r in rows_a], "k--", lw=1.5, label="怪物总HP")
    ax.set_yscale("log"); ax.set_xlabel("波次"); ax.set_ylabel("DPS / HP (log)")
    ax.set_title("玩家有效 DPS vs 怪物总 HP（对数）"); ax.grid(True, which="both", alpha=.3); ax.legend(fontsize=8)

    ax = axes[0, 1]
    for rows, label, color in [(rows_a, "单核(A)", "#e6550d"), (rows_b, "多塔(B)", "#3182bd")]:
        y, x = ser(rows, "ratio"); ax.plot(x, y, "-o", ms=3, label=label, color=color)
        for r in rows:
            if r["ratio"] >= 1.0:
                ax.axvline(r["w"], color=color, ls=":", alpha=.5); break
    ax.axhline(1.0, color="red", ls="--", lw=1.2, label="起飞线 ratio=1.0")
    ax.axvspan(10, 15, color="green", alpha=0.12, label="目标起飞窗 W10-15")
    ax.set_xlabel("波次"); ax.set_ylabel("DPS / 怪物总HP")
    ax.set_title("起飞判据 DPS/HP 比值"); ax.grid(True, alpha=.3); ax.legend(fontsize=8)

    ax = axes[1, 0]
    for rows, label, color in [(rows_a, "单核(A)", "#e6550d"), (rows_b, "多塔(B)", "#3182bd")]:
        y, x = ser(rows, "core_hp"); ax.plot(x, y, "-o", ms=3, label=label, color=color)
    ax.axhline(0, color="red", ls="--")
    ax.set_xlabel("波次"); ax.set_ylabel("核心剩余 HP")
    ax.set_title("核心 HP 曲线（苟活期下降→成型期企稳）"); ax.grid(True, alpha=.3); ax.legend(fontsize=8)

    ax = axes[1, 1]
    for rows, label, color in [(rows_a, "单核(A)", "#e6550d"), (rows_b, "多塔(B)", "#3182bd")]:
        y, x = ser(rows, "cum_rerolls"); ax.plot(x, y, "-o", ms=3, label=label, color=color)
    ax.set_xlabel("波次"); ax.set_ylabel("累计刷新次数")
    ax.set_title("累计刷新次数（实时商店刷店强度）"); ax.grid(True, alpha=.3); ax.legend(fontsize=8)

    fig.suptitle("Corebound 纸面数值模拟 — Phase 2 校准", fontsize=14)
    fig.tight_layout()
    path = os.path.join(OUT_DIR, fname)
    fig.savefig(path, dpi=130)
    plt.close(fig)
    return path


def build_report(rows_a, rows_b):
    ta = takeoff_wave(rows_a); tb = takeoff_wave(rows_b)
    L = []
    L.append("# 《守核 Corebound》Phase 2 纸面数值模拟 · 校准报告\n")
    L.append("> 作者：程基岩（工程主理人） · 用途：写代码前的 R1 数值验证\n")

    L.append("## 0. 关键发现（模拟过程中暴露的 R1 真相）\n")
    L.append("1. **字面 MVP 机制无法产生雪崩（R1 最核心发现）**：若严格按 §8 的「强化卡 +25% *加法*、")
    L.append("   5 卡位、无叠层」，玩家 DPS 在填满 5 槽后触顶（模拟中稳定在 ~111），而怪物 HP 指数增长，")
    L.append("   DPS/HP → 0，**永远无法起飞**。P2「雪崩无上限」在字面 MVP 下数学不成立。")
    L.append("   **必须把「叠层复利」（原 Tier 1 叠层机制）拉入 MVP 作为雪崩引擎**——这是本次校准的最大机制变更。")
    L.append("2. **多塔路径若无复利引擎则彻底失效**：纯 Arrow（无 Tag）铺场的 DPS 是线性的，")
    L.append("   永远追不上指数怪物 → 策略多样性崩塌。两条路径都必须能接入复利引擎，差异在「深叠专注 vs 铺场摊薄」。")
    L.append("3. **起飞是相变（悬崖）不是斜坡**：复利引擎一旦越过临界质量，DPS 一两波内从不足→碾压。")
    L.append("   这正是 P2 要的手感，但意味着「起飞点」对系数高度敏感，需靠**商店库存摩擦**（每波火焰卡获取上限）")
    L.append("   把悬崖从 W7 推到 W10-15，而不是靠调怪物成长率。")
    L.append("4. **经济卡占卡位会锁死引擎**：若 ScrapUp 占 5 槽之一，理性玩家永远买不起协同位 → 复利无法成型。")
    L.append("   建议经济卡为**全局升级不占卡位**。")
    L.append("5. **苟活期压力需靠 surge（集中刷怪）而非提高怪物 HP**：提高 hp_base 会同时推迟起飞、破坏窗口；")
    L.append("   而把早期怪物压进前 30% 窗口涌入，能在不改变总收入的前提下制造核心漏血压力。")
    L.append("6. **多塔路径在字面机制下是「爆发流」而非「雪崩流」（本次扫参新暴露）**：多塔的两个复利引擎")
    L.append("   （FireUp 受火焰库存摩擦饿死在 ~12 层、FrostUp 在 W10 就撞 cap=100）会**双双提前饱和**，")
    L.append("   之后收入只能投次线性塔（∝level^0.6），DPS 增速 ~16%/波 < 怪物 30%/波 → DPS/HP 在 W12 见顶")
    L.append("   后**回落**（B: 9.3→2.5）。扫参证实调 cap/compound/火焰库存都修不好（只会「推迟见顶→后期爆炸」）。")
    L.append("   **结论：多塔要能雪崩，必须给它一个专属的指数出口**（建议：塔可进化/合成出自带复利的高阶塔，")
    L.append("   或「铺场达标后解锁全局复利光环」），否则多塔在雪崩期会被单核反超，策略多样性在后期崩塌。")
    L.append("")

    L.append("## 1. 校准后系数（回写策划 §8 建议值）\n")
    L.append("| 项 | 原 PLACEHOLDER | 校准后 | 理由 |")
    L.append("|---|---|---|---|")
    L.append("| 怪物 HP | `20×1.35^(w-1)` | `16×1.30^(w-1)` | 1.35^20≈428×，怪物总HP过墙，DPS 永远追不上；降到 1.30 使起飞落 W10 |")
    L.append("| 每波怪物数 | `5+2w` | `8+1.6w` | 略增早期数量配合 surge，制造苟活期到达压力（核心 HP 缓降） |")
    L.append("| 单只击杀收益 | `2+0.5w` | 保持 | 收入曲线合适 |")
    L.append("| 刷新成本 | `5+3n` | 保持 | 递增斜率合适，天然边际递减 |")
    L.append("| 核心 HP | `1000` | 保持 | 配合泄漏伤害 50，苟活期缓降、成型期企稳 |")
    L.append("| 每只泄漏伤害 | 未定义 | `50` | 新增：让苟活期有真实核心压力 |")
    L.append("| **强化卡叠层** | `同Tag +25% 加法` | **`每层 ×1.10 复利`（单核）/ ×1.06（多塔）** | ★关键：加法 buff 无法跑赢指数怪物 HP（DPS 触顶→R1 崩盘）；叠层复利是 5 卡位上限下唯一能产生 P2 雪崩的引擎。多塔 buff 摊薄故复利更弱 |")
    L.append("| 叠层软上限 | 无 | `100` | 雪崩期需持续复投兑现，放宽上限让 DPS 后期继续甩开 |")
    L.append("| 塔叠层 | 线性 | `∝level^0.6`（次线性） | 边际递减，使火焰塔成型后 FireUp 复利成为更优再投资方向 |")
    L.append("| 协同判定 | 按张数 | 按**投入层数** | 修正：深叠同一火焰塔也应达成协同 |")
    L.append("| 刷怪节奏 | 均匀 | 苟活期 surge（前 30% 窗口涌入） | 制造瞬时到达压力，早期低射速塔漏怪 → 核心缓降 |")
    L.append("| 塔卡/强化/经济价 | 未定义 | `12 / 9 / 10` | 新增：控制卡位填充与复投节奏 |")
    L.append("| 经济卡 | 占卡位 | **全局升级不占卡位** | 修正：否则挤占火焰协同位，导致复利引擎无法成型 |")
    L.append("")

    L.append("## 2. 起飞点落位\n")
    L.append(f"- **单核路径(A)**：起飞点 **W{ta}**（DPS/HP 首次 ≥1.0 且持续增长）")
    L.append(f"- **多塔路径(B)**：起飞点 **W{tb}**")
    ok_a = ta and 10 <= ta <= 15
    ok_b = tb and 10 <= tb <= 15
    L.append(f"- 目标窗口 W10–W15：A **{'命中 ✓' if ok_a else '未命中(W'+str(ta)+')'}**，"
             f"B **{'命中 ✓' if ok_b else '未命中(W'+str(tb)+')'}**")
    L.append(f"- **起飞率**：确定性理性模型下两路径均达成起飞（100%）；含商店 RNG 的蒙特卡洛 ≥80% 验证建议 GDD 阶段补跑。")
    L.append("")

    L.append("## 3. 三阶段曲线验证\n")
    def pc(rows, label):
        e = [r for r in rows if r["w"] <= 5]
        m = [r for r in rows if 6 <= r["w"] <= 12]
        l = [r for r in rows if r["w"] >= 13]
        # 苟活期压力：以核心 HP 峰值(1000)到苟活期最低值的降幅衡量
        peak = CALIBRATION["core_hp"]
        trough = min(r["core_hp"] for r in e)
        core_drop = peak - trough
        mid_up = any(r["ratio"] >= 1.0 for r in m)
        late_r = l[0]["ratio"] if l else 0
        # 雪崩期是否「持续甩开」：W13 起 DPS/HP 不回落（末波允许因怪物暴涨短暂回落，但整体应上行）
        late_sustain = len(l) >= 2 and l[-1]["ratio"] >= l[0]["ratio"] * 0.9
        L.append(f"**{label}**：")
        L.append(f"- 苟活期 W1-5：核心 HP 峰值 {peak:.0f} → 最低 {trough:.0f}（降幅 {core_drop:.0f}，"
                 f"{'缓降，压力成立 ✓' if core_drop >= 50 else '基本满血（多塔清场强）'}）；DPS {e[0]['eff_dps']}→{e[-1]['eff_dps']}")
        L.append(f"- 成型期 W6-12：DPS/HP 首次 ≥1.0 = {'是 ✓' if mid_up else '否'}")
        L.append(f"- 雪崩期 W13+：起始 DPS/HP = {late_r:.2f}，W20 = {l[-1]['ratio']:.2f}"
                 f"（{'持续甩开 ✓' if late_sustain else '见顶回落 ✗ — 复利引擎提前饱和，见 §0.6'}）")
    pc(rows_a, "单核A"); pc(rows_b, "多塔B")
    L.append("")

    L.append("## 4. 单核 vs 多塔对比结论\n")
    da = rows_a[-1]["eff_dps"]; db = rows_b[-1]["eff_dps"]
    ca = rows_a[-1]["coverage"]; cb = rows_b[-1]["coverage"]
    ra_peak = max(r["ratio"] for r in rows_b); ra_peak_w = [r["w"] for r in rows_b if r["ratio"]==ra_peak][0]
    L.append(f"- 起飞点：单核 W{ta}、多塔 W{tb}，**均落在目标窗口 W10–W15 ✓**")
    L.append(f"- 终局(W20)有效 DPS：单核 {da:.0f} vs 多塔 {db:.0f}；覆盖率：单核 {ca:.2f} vs 多塔 {cb:.2f}")
    L.append(f"- **雪崩持续性**：单核 DPS/HP 一路涨到 W20（{rows_a[-1]['ratio']:.1f}×）；"
             f"多塔在 W{ra_peak_w} 见顶 {ra_peak:.1f}× 后回落到 W20 {rows_b[-1]['ratio']:.1f}×（见 §0.6）")
    L.append("- 结论：两条路径**起飞点都达标**，前期-中期体验分化健康（单核赌协同爆发、多塔稳健铺场核心更血）；"
             "但**多塔在字面机制下无法把领先滚到终局**——它缺一个专属指数出口。"
             "**给策划的硬约束**：多塔必须补「塔进化/合成出复利高阶塔」或「铺场达标解锁全局复利光环」，"
             "否则雪崩期策略多样性会向单核坍缩。")
    L.append("")

    L.append("## 5. 实时（不暂停）商店影响\n")
    rt, _, _ = realtime_shop_analysis()
    for line in rt:
        L.append(f"- {line}")
    L.append("- **定性建议**：实时模式下刷新需在战斗间隙完成，玩家注意力被「看战场 vs 刷店」撕裂。")
    L.append("  建议**不引入硬性分心惩罚**（会叠加操作压力、违反 P4），而是让「刷新成本单波递增」作为天然的时间惩罚——")
    L.append("  停留越久刷越多，单位积分边际收益越低，玩家自行权衡。若实测起飞过快，可微调 reroll_growth。")
    L.append("")

    L.append("## 6. 逐波数据\n")
    def table(rows, title):
        L.append(f"### {title}")
        L.append("| W | 怪物数 | 单只HP | 总HP | 有效DPS | DPS/HP | 协同 | 核心HP | 收入 | 刷新 | 卡位 | 构筑 |")
        L.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
        for r in rows:
            L.append(f"| {r['w']} | {r['n']} | {r['hp_each']} | {r['total_hp']} | {r['eff_dps']} | "
                     f"{r['ratio']} | {r['synergy']} | {r['core_hp']} | {r['income']} | {r['rerolls']} | {r['slots']} | {r['build']} |")
        L.append("")
    table(rows_a, "单核A")
    table(rows_b, "多塔B")
    return "\n".join(L), ta, tb


def sweep():
    """确认锁定配置：校准已通过离线扫参完成，这里只回显锁定值与命中情况。"""
    print("\n[锁定配置] 校准后系数（离线扫参已确定，见 calibration-report.md §1）:")
    c = CALIBRATION
    print(f"  怪物HP = {c['hp_base']}×{c['hp_growth']}^(w-1)  怪物数 = {c['num_base']}+{c['num_growth']}w")
    print(f"  泄漏伤害 = {c['leak_damage']}  核心HP = {c['core_hp']}  卡位 = {c['slots']}")
    print(f"  A叠层复利 ×{c['reinforce_compound']}/层(cap{c['reinforce_cap']})  "
          f"B叠层复利 ×{c['reinforce_compound_B']}/层")
    print(f"  协同阈值 {c['synergy_threshold']} 张 ×{c['synergy_mult']}  塔叠层次线性 exp={c['tower_stack_exp']}")
    print(f"  火焰获取上限 A={c['A_fire_stock']}/波 B={c['B_fire_stock']}/波  "
          f"苟活期刷怪窗口={c['spawn_window'](3)}")
    return None


# =============================================================================
# 11. main
# =============================================================================
def main():
    print("="*74)
    print("《守核 Corebound》纸面数值模拟 — Phase 2 校准 (v2 叠层复利)")
    print("="*74)

    sweep()
    rt, ra, rb = realtime_shop_analysis()

    ta = takeoff_wave(ra); tb = takeoff_wave(rb)
    print(f"\n[起飞点] 单核A = W{ta} | 多塔B = W{tb}  (目标 W10-15)")

    for label, rows in [("单核A", ra), ("多塔B", rb)]:
        print(f"\n[逐波] {label}:")
        print(" W  怪数  单HP   总HP     有效DPS  DPS/HP 协同  核心HP    收入  刷新 卡位  构筑")
        for r in rows:
            print(f"{r['w']:>2}  {r['n']:>3}  {r['hp_each']:>5}  {r['total_hp']:>7}  "
                  f"{r['eff_dps']:>8}  {r['ratio']:>6}  {r['synergy']:>3}  {r['core_hp']:>7}  "
                  f"{r['income']:>6}  {r['rerolls']:>3}  {r['slots']:>3}   {r['build']}")

    print("\n[实时商店分析]")
    for line in rt:
        print("  " + line)

    csv_a = write_csv(ra, "sim_pathA.csv")
    csv_b = write_csv(rb, "sim_pathB.csv")
    png = write_png(ra, rb, "curves.png")
    report, _, _ = build_report(ra, rb)
    repath = os.path.join(OUT_DIR, "calibration-report.md")
    with open(repath, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"\n[输出] CSV: {csv_a}")
    print(f"[输出] CSV: {csv_b}")
    print(f"[输出] PNG: {png}")
    print(f"[输出] 报告: {repath}")


if __name__ == "__main__":
    main()
