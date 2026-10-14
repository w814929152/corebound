# Phase 6 · P2-Sapper ①「落机制」独立复核

> **复核人**：严守真（quality-lead） · **性质**：独立只读复核（自行写探针 / 自行重跑，**不采信实现方自报数**）
> **被测提交**：`7209be6`（`refactor(balance): P2-Sapper ①落机制 — SAPPER_DMG_MULT → sapper_dmg_mult(w) SSOT`）
> **规格**：`docs/phase6/balance-p2-spec.md` §1.2 / §3 / §7.1 / §8.2 组 A
> **我未改任何生产代码、未 push**。新增只读探针：`tests/_qa_sapper_probe.gd`。原始日志：`ci-logs/_qa_sapper_*.log`、`ci-logs/_qa_realtime_mc.log`。

---

## §0 结论速览

**总体判定：✅ PASS**（五项全过，未发现缺陷，无需打回）

| # | 项 | 判定 | 关键读数 |
|---|---|---|---|
| ① | 中性逐位性（严格 `==`） | ✅ PASS | 探针 **7/0**；`w∈{1..9,10,15,20,100}` 全严格 `== 3.0`；`w<10` 分支**直接 return const**（`:66`，不经乘法） |
| ② | 残留直读（全仓含 tools/tests/scenes） | ✅ PASS | 唯一生产 `.gd` 读点 = `monster_data.gd`（定义 `:50` + 函数体 `:66/:69`）；无第二直读 |
| ③ | 独立复现 `203` | ✅ PASS | **我**跑实时 MC：OFF B@6 = **203/300 = 0.677**（== 批处理基线）；PRODUCT B@6 = 0.84 ≥ 0.80；EXIT=0 · 121s |
| ④ | 🔴 传值正确性（`w` 同源） | ✅ **同源** | 三路径（实时/批处理/三原型）**全部同源**；`w` 单点写入、无步进；**未找到任何错位反例**（详见 §3） |
| ⑤ | 形状/边界 | ✅ PASS | `mvp_config.gd` **未碰**（零 cfg-shape 变更）；新参为**必填**（无默认）→ 漏改即编译错，非静默错位 |

---

## §1 被测范围与提交洁净

```
7209be6 refactor(balance): P2-Sapper ①落机制
  scripts/data/monster_data.gd           | 22 +++++++ (4 const + sapper_dmg_mult)
  scripts/engine/wave_sim_aggro.gd       | 15 ++++---- (贯穿 sapper_mult)
  scripts/engine/wave_sim_proto_aggro.gd | 10 +++---- (贯穿 sapper_mult)
  scripts/gameplay/wave_director.gd      | 11 ++++--- (波级预计算 + 贯穿)
4 files changed, 41 insertions(+), 17 deletions(-)
```

- 逐提交核过：**恰 4 文件**；**未触碰** `mvp_config.gd` / `scenes/**` / `tests/**` / 音频 / VFX。✅
- HEAD = `084ba79`（其后为 memory chore），被测 = `7209be6`。

---

## §2 逐项证据

### [1] 中性逐位性 —— ✅ PASS（自写探针）

`tests/_qa_sapper_probe.gd`（**我独立写**，只读 `monster_data.gd` 的 const + static func）：

```
const 读数: SAPPER_DMG_MULT=3.0  W0=10  G0=1.0  SLOPE=0.0  CAP=3.0
w=1..9,10,15,20,100  →  mult=3.0   ==3.0?=true   （逐 w 严格 ==，非 is_equal_approx）
[A1] sapper_dmg_mult(5) 逐位 == 3.0                                  PASS
[A2] ∀ w∈{1..9}: == 3.0（梯度不泄漏 W<10）                            PASS
[A3] ∀ w∈{1..200}: ≥ 3.0（单调不减）                                  PASS
[A4] ∀ w∈{10,15,20}: == 3.0 × clampf(G0+SLOPE·(w−W0), G0, CAP)        PASS
[A5] (G0==1 && SLOPE==0) ⇒ ∀ w∈{1..200}: == 3.0                       PASS
[①] 中性覆盖列表（含 100）全严格 == 3.0                                PASS
[⑤a] SAPPER_RAMP_* 全为 float 常量（无 int 截断）                      PASS
探针汇总：通过 7 项 / 失败 0 项 · EXIT=0
```

- **`w<10` 分支直接 return const**（读码 `monster_data.gd:65-66`：`if w < SAPPER_RAMP_W0: return SAPPER_DMG_MULT`，**不经乘法**）。✅
- **`w≥10` 分支 IEEE 精确**：`g = 1.0 + 0.0·float(w−10) = 1.0`；`clampf(1.0,1.0,3.0) = 1.0`；`3.0 · 1.0` 在 IEEE-754 下**精确 = 3.0**。⇒ `==` 通过即**逐位**相等。

### [2] 残留直读 —— ✅ PASS（全仓 grep）

`SAPPER_DMG_MULT` 全仓命中（含 `tools/`、`tests/`、`scenes/`、`.tscn`）：
- `scripts/data/monster_data.gd` —— **唯一生产读点**（定义 `:50` + 函数体 `:66/:69`）。✅
- `tests/_qa_sapper_probe.gd` —— **我本次新增的探针**（仅打印串引用，非消费）。✅
- 其余全为 `docs/**`、`design/**` 的 **`.md` 文档**（非代码）。
- ⇒ **无第二处消费性直读**。（`scenes/`、`tools/` 零命中；`.tscn` 零命中。）

### [3] 独立复现 `203` —— ✅ PASS（自跑）

| 入口 | 命令 | **我的读数** | EXIT | 耗时 |
|---|---|---|---|---|
| 实时版 MC | `run_realtime_counterplay_mc.gd` | OFF B@6 = **203/300 = 0.677**（== 批处理基线）· PRODUCT B@6 = 0.84 | 0 | 121s |
| W5/W10 Sapper 等价 | `run_tests.gd -- t1aggro` | **234/0** · AC-T1-17/18 `\|d\|=0.0` | 0 | 31s |
| 三轴合并镜像退化守护 | `run_tests.gd -- aggro_golive` | **56/0** · 交叉 Sapper PATH+RADIAL W5/W10 全 `\|d\|=0` | 0 | 85s |

- **实时 MC 守门 PASS**：`OFF B@6 复现批处理基线 203/300=0.677 ✅（实时↔批处理零分岔）`。
- **AC-T1-25A/B**（真身↔镜像 逐波差异 / 整局 B+Sapper 逐波逐位差异）：`got=0 want=0`。✅
- 与工程自报「`203` 逐位复现」**一致**（我独立取得）。

### [4] 传值正确性 —— ✅ 同源（详见 §3）

### [5] 形状/边界 —— ✅ PASS

- **`mvp_config.gd` 未碰**：提交恰 4 文件（无 `mvp_config.gd`）⇒ `cfg_of()` 金标对象形状**零变更**。✅
- **签名插入是「必填」非「默认」**：`_apply_aggro(...)` / `_damage_tower(...)` 新增 `sapper_mult: float` 为**无默认值的必填位参** ⇒ 任何漏改调用点会**编译报错**（响亮），**不会**靠默认值静默错位。✅
- 全部调用点核过（3 处 `_apply_aggro` + 3 处 `_damage_tower`），**均已按新签名位序传参**，无遗漏、无错位：
  - `wave_sim_aggro.gd:254` / `wave_sim_proto_aggro.gd:195` / `wave_director.gd:423`
  - `wave_sim_aggro.gd:693` / `wave_sim_proto_aggro.gd:249` / `wave_director.gd:464`
- `tests/` 侧**无**直调这些内部函数的调用点（`probe_radial_aggro.gd` 仅注释提及）。

---

## §3 🔴 第 ④ 项专章：`w` 同源判定 —— **同源（无错位）**

> **方法论前提（team-lead 交底，我认同）**：中性 `g≡1` ⇒ 传错 `w`（含 `w±1`）**也全绿** ⇒ **测试证明不了接线**。故本项**只能静态核**（读码取证），**不采信任何绿色门禁**。

**全仓 `sapper_dmg_mult(w)` 实际调用点 = 恰 3 处**（非 9；team-lead 交底的「9」我按实测订正为 3）：

| 路径 | 乘数调用点 | 同路径 **Sapper 标记**调用点 | 二者的 `w` 来源 | 判定 |
|---|---|---|---|---|
| **批处理镜像** | `wave_sim_aggro.gd:255` `sapper_dmg_mult(w)` | `:118` `_build_sapper_flags(n, w, sapper)` | **同为函数形参 `w`** | ✅ **同源** |
| **三原型镜像** | `wave_sim_proto_aggro.gd:196` `sapper_dmg_mult(w)` | `:138` `_WaveSimAggro._build_sapper_flags(n, w, elite_enabled)` | **同为函数形参 `w`** | ✅ **同源** |
| **实时真身** | `wave_director.gd:443` `sapper_dmg_mult(w)` | `:749` `_spawn_one` 内 `is_elite_wave(w)`（置 `m.sapper`） | **同为成员 `w`** | ✅ **同源** |

**逐条核证：**

1. **实时侧成员 `w` 的时序（team-lead 点名的历史坑）**：
   - 全文件 `w` **仅一处写入**：`wave_director.gd:234 w = p_w`（在 `start_wave`），**无自增/无步进**（`grep` `w\s*[-+]?=` 仅命中 `:234`）。
   - `_apply_aggro()` 在 `:423`（`_process`→`advance` 战斗 tick）被调用，**先于**它 `start_wave` 已把 `w` 置为**本波**。
   - `_spawn_one`（生成期置 `m.sapper`）与 `_apply_aggro`（战斗期算 `sapper_mult`）**读同一成员 `w`，波内恒定** ⇒ 生成期与战斗期**不可能读到不同 `w`**。
   - ⇒ 「`w` 在 `start_wave` 才自增」的坑**不适用**（是**赋值**非自增，且波内不再改）。✅

2. **批处理侧同源**：`simulate_wave_aggro(player, w, …)` 的形参 `w` **同时**喂给 `_build_sapper_flags(n, w, sapper)`（`:118`，决定谁是 Sapper）**和** `sapper_dmg_mult(w)`（`:255`，决定倍率）—— 单一变量、同一来源。✅

3. **三原型侧同源**：`simulate_wave_proto_aggro(player, w, …)` 的形参 `w` 同时喂 `_build_sapper_flags(n, w, elite_enabled)`（`:138`）与 `sapper_dmg_mult(w)`（`:196`）。✅

4. **调用方传的 `w` = 真波号**（非自增值/计数）：
   - `run_loop_aggro.gd:73-74`：`for w in range(1, max_wave+1): simulate_wave_aggro(player, w, …)`
   - `run_loop_proto_aggro.gd:65-66`：同上
   - `run_realtime_counterplay_mc.gd:88-90`：`for w in range(1, W_MAX+1): wd.start_wave(w)`
   - ⇒ 三处均为**循环波号 1..N**，直接透传。✅

5. **反例搜索（照实报）：未找到任何 `w` 不同源或错位**。无一处传 `w±1`、波内计数或自增值。（旁证：`wave_director.gd:918` 的 `is_elite_wave(w + 1)` 是 snapshot 的「下一波是否精英」，**不在**乘数链上。）

> **🔴 对「提交②能否做」的结论**：**可以**（就 `w` 接线而言）。三路径乘数与 Sapper 标记**同源**，翻参（`G0/SLOPE` 非中性）后，倍率将作用在**本波正确波号**，不会错波。**唯一提示（非缺陷、非本项范围）**：三原型镜像的 Sapper **触发**用 `elite_enabled`（`:138`），批处理镜像用 `sapper` 形参 —— 二者是**触发开关**差异（既有设计，非本次重构引入），与 `w` 同源性**无关**；翻参前建议确认产品口径下这两个开关的取值一致性（属提交②的验收，非本①缺陷）。

---

## §4 未证实 / 残余

1. **中性对「接线正确性」的掩盖**：`g≡1` 下**任何** `w` 都返回 3.0 ⇒ **运行时无法区分 `w` 是否传对**。本项结论**完全建立在静态同源读码**之上（这正是 team-lead 指定、也是唯一可行的方法）。**不宣称**「门禁绿 ⇒ 接线对」。
2. **提交②的数值落点**（`G0/SLOPE/CAP` 具体值、W10/15/20 恢复压力是否达标）**不在本次范围** —— 属 spec §8.2 组 B，须 MC 标定 + 用户拍板。

---

## §5 复现（全部命令）

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# [1] 我的中性逐位探针（项① + A1–A5）
"$GODOT" --headless --path . --script res://tests/_qa_sapper_probe.gd

# [3] 独立复现 203（实时真身 MC · 300 局/臂 · ~121s）
"$GODOT" --headless --path . --script res://tests/run_realtime_counterplay_mc.gd

# [3] W5/W10 Sapper 等价 + AC-T1-25A/B
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- t1aggro
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- aggro_golive
```

> ⚠️ 单实例锁：`.godot/` 同刻仅一个 Godot。
