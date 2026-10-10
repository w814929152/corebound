# QG-RADIAL-01 · P2 测试卫生清理（R-6 ~ R-10）汇总记录

| 项 | 内容 |
|---|---|
| 任务 | Phase 6 打磨 · 清质量门 P2 测试卫生遗留（R-6 ~ R-10） |
| 依据 | `docs/phase3/quality-gate-radial-migration.md` §3.3-⑧⑨ / §2.4(b)(d) / §4.1 |
| 执行 | 程基岩（工程）· 2026-10-10 |
| 环境 | Godot `v4.7.2.stable.official.ed1daf0bf` · Windows · headless · `--path D:/roguedemo` |
| 范围红线 | **只改 `tests/` 下 5 个文件** · 零 `scripts/` 改动 · 零定稿数值改动 |
| 结论 | ✅ 5 项全部落地 · 三条验收全绿 · 🔴 暴露一处既有"从未执行"断言并修正（见 §6） |

---

## 0. 一句话结论

1. **R-6~R-10 五项全部落地**：恒真断言→真值常量、影子副本→生产真身、自指断言→外部真值、名实不符→补真径向臂、缺 m_spd 校验→补包围盒校验。
2. **三条验收全绿**：默认回归 `exit 0`、`-- radial8` `exit 0`、`-- geo8` `exit 0`；附加 `geo8_mc(300)` 亦 `exit 0`。
3. **零生产改动**：`scripts/` 一行未动；R-7 直接调用已存在的 `static func`，无需把真身"暴露为可调"。
4. 🔴 **一处既有问题被卫生修复暴露并修红**：`test_suite_radial` 的 E-R6 五条断言因前一行非法 `free()` 而**从未真正执行**；移除后首次执行，3 条因容差过紧（1e-7 < float32 精度）翻红 → 定性为**测试容差 bug，非生产回归**，已修正容差。详见 §6。

---

## 1. 逐项：改前（病根）→ 改后（真信号）

### R-6 · `panorama8` 三条数学恒真断言 → 对照真值

文件：`tests/run_slice_panorama8.gd`

| 判据 | 改前（恒真，无证伪能力） | 改后（对照真值） |
|---|---|---|
| P-G8-2 | `SPAWN_RADIUS <= span-3.0`，而 `span := SPAWN_RADIUS+3.0`（同构造式 → 恒真） | `R_s == 55.0` 且 `span == 58.0`（§2.2 定稿几何常量） |
| P-G8-3 | `cx := (box_lo+box_hi)*0.5` 恒等于 `core.x`（同构造式 → 恒真） | `core == (28,28)`（径向核心定稿常量） |
| P-G8-4 | `sc > 0.0`（全正量 → 恒真） | `sc ∈ [8.0, 9.0]`（合理区间常量；1920×1080/MARGIN=48 → sc≈8.483） |

- **文案修正（R-6 附）**：原 P-G8-4 输出 `约 984 世界单位/屏高` 是**错的** —— `984 = wh×sc` 是世界高映射的**像素数**；屏高覆盖的**世界单位**应为 `vh/sc ≈ 127.3`。已改正输出。
- 断言现已能随"几何常量被误改"而 FAIL（如 `R_s` 改动 → P-G8-2 红；核心改动 → P-G8-3 红；`span` 改动 → P-G8-4 越界红）。

**证据**：`panorama8` 单独跑 `exit 0`；新增断言全 PASS（`sc=8.483 ∈ [8.0,9.0]`）。

### R-7 · `bulwark8` 影子副本 → 直接调生产真身

文件：`tests/run_slice_bulwark8.gd`

- **改前（影子实现）**：测试内联了一份 `_relocate()`（只实现 RADIAL 单分支），断言打的是**副本**不是生产真身 → 真身（含 PATH/RADIAL 双分派、`_slot_has_tower` 肉盾交换等分支）一旦漂移，测试仍全绿。
- **改后（真身）**：删除内联副本（34 行），改为直接调用
  `WaveSimAggro._relocate_carry_to_safe(player, geo)` —— 该函数已是 `static func`（`wave_sim_aggro.gd:287`），**无需任何生产改动**。
- 数值结果不变（主力塔 S1 → S5，`expo_frac` 0.2839 → 0.1066），但现在断言真正打到生产函数上：真身漂移 → 立即翻红。

**证据**：`bulwark8` 单独跑 `exit 0`；B-G8-1/2/3 全 PASS（安全位 = [3,5,6,7]）。

### R-8 · `geo8_mc` 名实不符 → 选 **①**（补真径向臂）

文件：`tests/run_slice_geo8_mc.gd`

- **改前**：脚本头自称"径向阶段1 · 八槽 MC 起飞率对照"，但**从未设 `SpaceModel.mode`** → 实为"八槽 × PATH"（名实不符）。
- **改后（选①）**：新增 **RADIAL 臂** —— 同一 seed、同四组（A6/A8/B6/B8），分别跑
  `ARM 1 = PATH`（既有基线）与 `ARM 2 = RADIAL`（真径向，怪物从出生环 `R_s=55` 直插核心），并输出 `RADIAL - PATH` 同 seed 对照表。跑完 `SpaceModel.mode` 设回 PATH（防污染全局开关）。

**选①而非②的理由**：① 信息量更大（给出真径向起飞率，回答脚本本应回答的问题），且**保留了 PATH 臂** → 既有 PATH 基线逐位不变（§4 已实证），不构成"改变现有基线"的副作用；② 只是改名，零信息增量。

**新旧对照（300 局 MC · 同 seed PyRandom(20260930)）**：

| 口径 | A 六槽 | A 八槽 | ΔA | B 六槽 | B 八槽 | ΔB |
|---|---|---|---|---|---|---|
| **PATH**（旧口径 · 逐位保留） | 0.283 | 0.340 | +0.057 | 0.813 | 0.873 | +0.060 |
| **RADIAL**（新口径 · 真径向） | 0.607 | 0.550 | −0.057 | 0.900 | 0.870 | −0.030 |

- 判读：PATH 与 RADIAL 下八槽 Δ 均温和（|Δ| ≤ 0.06），八槽不破坏起飞可行性。
- 🟡 **注**：本表 PATH 数字（0.283/0.340/0.813/0.873）与质量门报告（2026-10-08）记录的 PATH 数字（0.430/0.530/0.917/0.870）**不同** —— 原因是引擎在 V-7/V-8 批次后演进（`run_loop_aggro` / `shop_ai` / `takeoff_rate` 口径扩展），**非本次改动所致**。§4 用 HEAD 原版脚本实证：原版今日输出 == 新脚本 ARM 1（逐位）。

**证据**：`geo8_mc` 单独跑（300 局）`exit 0`。

### R-9 · `geo8` E-G8-6 自指断言 → 外部真值；E-5 对齐补断言

文件：`tests/test_suite_geo8.gd`（E-G8-6）、`tests/test_suite_radial.gd`（E-5）

- **E-G8-6 改前（自指）**：`_check("S6 暴露楔形 = asin(9/r6)/π", wedge6, asin(AGGRO_R/r6)/PI, 1e-12)` —— `wedge6` 就是 `asin(9/r6)/π`，用自己算的式子比刚算的值 → **恒真**。
- **E-G8-6 改后（外部真值）**：对照草案 `radial-core-siege-draft.md` §2.4.1b / §2.6.2 的**文档真值 11.25%**（S6/S7 远哨 r=26 暴露楔形各 = 11.25%），容差 5e-4。另加 S6≈S7 **对称性**断言（独立于闭式解的有意义性质）。
- **E-5 补断言（"批处镜像位置 == 实时 monster.pos"）**：见 §3。

**证据**：`-- geo8` `exit 0`，33 通过 / 0 失败（原 32/0，新增对称断言 +1）。E-G8-6 实测 `wedge6=0.112512 / wedge7=0.112513`，与外部真值 0.1125 的 |d| ≈ 1.2e-5（< 5e-4）。

### R-10 · `panorama8` 补 `m_spd≠1` 怪物包围盒校验

文件：`tests/run_slice_panorama8.gd`（新增 P-G8-5）

- **查 `scripts/data/monster_data.gd`**：`M_SPD = {Rush: 4/3, Swarm: 1.0, Tank: 2/3}` → `max(m_spd) = 4/3`。
- **计算**：出生极径 `ρ_0 = R_s × m_spd`（`SpaceModel.rho_of_t`）。三原型最大出生 ρ = `55 × 4/3 = 73.33` > 相机包围盒内切半径 `span = 58`。轴向来袭的 Rush 会出生在包围盒外（相机看不到）。
- **结论**：**当前几何不满足** —— 这是**真实待办**（非测试的错）：三原型开启前必须**钳制出生 ρ（≤ 58）** 或**扩大 span（≥ 73.33）**。
- **断言设计（分档，避免误红既有闸门）**：`prototype_split_enabled` 是 `WaveDirector` 运行时开关、MVP 默认 `false`（且 `panorama8` ∈ `radial8` 闸门，当前必须保持绿）。
  - 读**生产真身默认值**（`WaveDirector.new().prototype_split_enabled`，非影子常量）；
  - `proto OFF` → 断言**当前生效出生 ρ（基准怪 m_spd=1，R_s=55）≤ span=58**（PASS），并打印 `[TODO-R10]` 待办；
  - `proto ON` → 断言**三原型最大出生 ρ ≤ span**（真实闸门；几何未钳制前必红）。
- 附：断言 `M_SPD` 三原型常量真值（Rush=4/3 / Swarm=1 / Tank=2/3），纳入"几何/数据常量被误改即红"的证伪网。

**证据**：`panorama8` 单独跑 `exit 0`；P-G8-5 全 PASS + 打印待办登记。

---

## 2. 三条验收（+ 附加）exit code

| # | 入口 | exit | 结果 |
|---|---|---|---|
| 1 | `--script res://tests/run_tests.gd`（默认无参 = PATH 金标本） | **0** | 222 / 2228 / 142 / 123 / 302 / 41 / 31 / 92 / 216 = **3397 项断言 · 0 失败** |
| 2 | `--script res://tests/run_tests.gd -- radial8` | **0** | 8 项全 PASS（geo8 套件 / radial 套件 / geo8_smoke / geo8_golden / expo / bulwark8 / panorama8 / attrition8）· 总耗时 124.1 s |
| 3 | `--script res://tests/run_tests.gd -- geo8` | **0** | 33 通过 / 0 失败 |
| 附 | `--script res://tests/run_slice_geo8_mc.gd`（300 局诊断） | **0** | PATH + RADIAL 双臂跑完 |

> 各改动脚本单独跑：`run_slice_panorama8.gd` → exit 0；`run_slice_bulwark8.gd` → exit 0；`run_slice_geo8_mc.gd` → exit 0；`-- geo8` → exit 0；`-- radial` → exit 0（48/0）。
>
> ⚠️ 默认回归 `slice1~slice8` 断言数（222/2228/142/123/302/41/31/92）与质量门（2026-10-08）**逐位相同** → 本次改动未触及默认口径。`t1aggro` 由 99 增至 216（V-7/V-8 批次扩展，非本次）。

---

## 3. R-9 附：E-5 批处镜像位置对齐断言

- **原质量门 §2.4(d)**：阶段3 的生产改动（`wave_sim_aggro._monster_pos` 按模式分派）使批处理镜像与实时版位置对齐，但**没有任何断言直接比对"批处理镜像位置 == 实时 monster.pos"**。
- **补法（低成本）**：在 `tests/test_suite_radial.gd` 新增 `_test_batch_mirror_alignment()` —— 在 RADIAL 下对 **5 个 θ × 5 个 t_remain = 25 组**，逐组断言
  `WaveSimAggro._monster_pos(batch, v0_)` == `Monster.pos(v0_)`（`distance_to` ≤ 1e-12）。
- **归属说明**：E-5 是 RADIAL 专属口径（两边同用 `R_s`），而 `SpaceModel.mode` 只在 `test_suite_radial` 内为 RADIAL，故把断言放该套件（E-5 的自然归属）而非 `test_suite_geo8`（其运行于 PATH）。
- **结果**：25 组 **最大 |d| = 0.0**（两边同调 `SpaceModel.radial_pos_of_t`）→ PASS。

---

## 4. "选①是否改变 PATH 基线"实证

为排除"R-8 补 RADIAL 臂动了 PATH 基线"的可能，用 **HEAD 原版脚本**（`git show HEAD:tests/run_slice_geo8_mc.gd`，暂存为临时探针）在**同环境、同 300 局**重跑：

| 口径 | A6 | A8 | ΔA | B6 | B8 | ΔB |
|---|---|---|---|---|---|---|
| HEAD 原版脚本（仅 PATH） | 0.283 | 0.340 | +0.057 | 0.813 | 0.873 | +0.060 |
| 新脚本 **ARM 1 (PATH)** | 0.283 | 0.340 | +0.057 | 0.813 | 0.873 | +0.060 |

→ **逐位相同**。证明①只**新增** RADIAL 臂，**未改动 PATH 基线**。（临时探针文件已删除。）

---

## 5. 未触发红项（R-6~R-10 本体）

R-6~R-10 五项的**新/改断言全部 PASS**，无本体红项：
- R-6：真值常量命中（R_s=55 / span=58 / core=(28,28) / sc=8.483）。
- R-7：真身调用结果与旧副本一致（S1→S5）。
- R-8：PATH 臂逐位保留（§4），RADIAL 臂新增跑通。
- R-9：外部真值 11.25% 命中（|d|≈1.2e-5）；E-5 镜像对齐 |d|=0。
- R-10：按设计——**几何对 Rush 不满足**（真实待办），但断言按 proto 开关分档，当前 proto OFF → PASS + 待办登记。

---

## 6. 🔴 既有问题暴露（卫生修复的连带发现）—— 如实报告

### 6.1 现象

R-9 卫生修复中，为消除 stderr 噪声移除了 `test_suite_radial.gd` 内的非法 `free()` 调用（`_Monster` 是 `RefCounted`，Godot 报 `Can't free a RefCounted object`）。其中 `_test_v0_and_kinematics` 里 `m.free()` 位于 **E-R6 断言之前** → 该错误使函数**在此处中止**，**E-R6 的 5 条断言从未真正执行**。移除 `free()` 后，E-R6 **首次执行**，其中 **3 条翻红**：

```
[FAIL] E-R6 t_remain=10.0  got=55.0000038147 want=55.0000000000 |d|=3.81e-6
[FAIL] E-R6 t_remain=5.0   got=27.5000019073 want=27.5000000000 |d|=1.91e-6
[FAIL] E-R6 t_remain=2.5   got=13.7499990463 want=13.7500000000 |d|=0.95e-6
```

（`t_remain=7.5` 与 `0.0` 两条 |d|=0 PASS。）

### 6.2 定性：**测试容差 bug，非生产回归**

- **根因**：E-R6 断言 `pos 到核心距离 == ρ`，容差原为 `1e-7`。但 Godot `Vector2` 为 **float32**，`pos = core + ρ·(cosθ,sinθ)` 再经 `distance_to` 的 `sqrt(cos²+sin²)` 回读，相对精度 ~1e-7 → `ρ≈55` 时 |d| ≈ 3.8e-6 > 1e-7。
- **同类旁证**：兄弟脚本 `run_slice_radial_smoke.gd` 的 ⑤ 早已用 **1e-5** 容差，并明文注释"`sqrt(cos²+sin²)` 浮点噪声 ~1e-6，乘 ρ(~50) 后 ~2e-6"。→ E-R6 的 1e-7 是**孤例式的过紧容差**。
- **生产侧**：`Monster.pos` / `SpaceModel.radial_pos_of_t` 数学正确（极坐标恒等式），无任何回归。

### 6.3 处置（不掩盖）

- 容差 `1e-7 → 1e-5`（与兄弟脚本同口径，附推导注释）。此为**修正过紧容差**，**非**删除断言掩盖问题。
- 移除 3 处非法 `free()`（`m` / `m2` / 新增 E-5 函数内），消除 `Can't free a RefCounted object` stderr 噪声（对齐质量门 §4.2"回归信号可用"的方向）。
- **报告判定交由主理人 / 文策渊**：本项为**既有测试卫生问题**（断言长期静默未跑 + 容差过紧），**非本次改动引入的回归**，亦不涉及任何定稿数值或玩法行为。

> 🟡 附带说明：`radial8` 聚合日志里中文乱码 = `run_tests.gd` 头部已登记的 **Windows GBK 坑**（`OS.execute` 解码子进程 stdout），`[PASS]`/`[FAIL]`/数值均 ASCII 不受影响。

---

## 7. 改动文件清单

| 文件 | 覆盖项 |
|---|---|
| `tests/run_slice_panorama8.gd` | R-6、R-10 |
| `tests/run_slice_bulwark8.gd` | R-7 |
| `tests/run_slice_geo8_mc.gd` | R-8 |
| `tests/test_suite_geo8.gd` | R-9（E-G8-6） |
| `tests/test_suite_radial.gd` | R-9（E-5）+ 卫生（非法 free() / E-R6 容差） |

- ✅ **未改动**：任何 `scripts/`、`design/`、`docs/` 生产/文档内容、任何定稿数值。
- 🟡 工作区另有**非本次**的既存改动（`project.godot` 头注释、`design/gdd/radial-core-siege-draft.md`、`.workbuddy/memory/*`），**非本任务产出**，本任务未触碰。

---

## 8. 证据留档

| 文件（`docs/phase3/qg-radial/`，`*.log` 受 .gitignore 保护） | 内容 |
|---|---|
| `final-default.log` | 默认回归（3397 断言 / 0 失败） |
| `final-radial8.log` | radial8 聚合（8 项全 PASS） |
| `final-geo8.log` | geo8 几何验收（33/0） |
| `final-geo8mc.log` | geo8_mc 300 局（PATH + RADIAL 双臂） |
| `orig-geo8mc-300.log` | HEAD 原版脚本 300 局（§4 基线对拍） |
| `final-exitcodes.log` | 四入口 exit code |

---

*报告结束 · 程基岩 · QG-RADIAL-01 R-6~R-10 · 只改 tests/ · 零生产改动 · 零定稿数值改动*
