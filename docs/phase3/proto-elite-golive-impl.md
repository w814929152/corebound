# 原型 / 精英波 **上线** · 落地实现记录（C-1 ~ C-9）

| 项 | 内容 |
|---|---|
| 文档 | `docs/phase3/proto-elite-golive-impl.md` |
| 执行 | 程基岩（工程）· 2026-10-10 |
| 依据规格 | `docs/phase3/proto-elite-golive-spec.md`（§1/§2/§5/**§8 拍板记录**/**附录 C 落地工单**） |
| 环境 | Godot `v4.7.2.stable.official.ed1daf0bf` · Windows · `<root> = D:/roguedemo` |
| 范围 | 只改必要文件（`boot.gd` / `space_model.gd` / `shop_controller.gd` / `test_suite_radial.gd` / `run_slice_panorama8.gd` / 新 MC 脚本 / R-10 文档）+ 本记录 + 截帧证据 |
| 红线 | 🔴 零定稿数值改动 · PATH 逐位等价 · 禁削 B 抬 A · 禁下调判据阈值 · 未 git commit |

---

## 0. 一句话结论

**C-1 ~ C-9 全部落地**。窗口模式注入双开关（`prototype_split_enabled` / `elite_waves_enabled`，aggro 保持 OFF）→
默认 headless 回归**逐位一致**（`222/2228/142/123/302/41/31/92/216 = 3397 项 · 0 失败 · exit 0`）、
`radial8` **8-8 PASS**、R-10 由**假红待办**转**真闸门 `[R-10-CLOSED]`**、
实机口径 300 局 MC **B 起飞率 0.917 ≥ 0.80（PASS）**、实机截帧核到原型/精英全部要素。

---

## 1. 改动清单（文件 ↔ 行 + 关键 diff）

| # | 文件 | 位置 | 改动 |
|---|---|---|---|
| **C-1** | `scripts/ui/boot.gd` | 窗口分支 `else:`（L34-46） | `add_child(BattleShop.instantiate())` → 具名 `var bs = ...; add_child(bs)`；紧随其后设 `bs.wave_director.prototype_split_enabled = true` / `bs.wave_director.elite_waves_enabled = true`；`tower_aggro_enabled` **保持 false**；加 `print("[boot] proto/elite ON（RADIAL 实机口径）")`。headless 分支**未动**。 |
| **C-2** | `scripts/geo/space_model.gd` | `rho_of_t`（L108-126） | 上钳参照 `1.0` → `1.0 / maxf(m_spd, 1e-9)`（= `t_remain_max/t_reach`）；同步更正函数头注释（写明 1/m_spd 参照 + m_spd==1 逐位恒等 + 防除零）。 |
| **C-3** | `tests/test_suite_radial.gd` | E-R4 Tank（L137-142） | Tank 断言 `55.0*2.0/3.0`（=36.67 钳制错值）→ **`55.0`**；文案改「Tank 归环」。**未动其他断言**。 |
| **C-4** | `scripts/gameplay/shop_controller.gd` | `_on_wave_ended`（L357-367）+ 头注释（L18-23）+ `_realtime_is_golden_equivalent` 注释（L377-380） | 去「回落金标本 + WARN」分支；波次匹配时**直接** `res = rt`（仅缺失/不匹配才回落 `_pending_result`）。`_realtime_is_golden_equivalent()` **保留函数、不再被调用**（grep 确认唯一调用点即本处，无其他引用）。 |
| **C-5** | `tests/run_slice_proto_elite_mc.gd` | **新增** | 实机口径 MC 入口：RADIAL + proto/elite ON + aggro OFF；300 局 × (A/B) × (n_slots 6 门禁臂 / 8 参考臂)；输出起飞率/存活率/中位起飞波/平均结算波/核心 HP 分布；**B@6 ≥ 0.80 硬门禁**（破线 exit 1）。**不进默认回归**。 |
| **C-6** | `tests/run_slice_panorama8.gd` | P-G8-5（L107-139）+ 头注释（L14-18） | 「假定式」`R_s*max_m_spd`（=73.33）→ **生产镜像式** `R_s*m_spd*clampf(1.0/m_spd,0,1)`；proto OFF/ON **两档都转真闸门**（断言 `spawn_rho_max ≤ span`）；保留三条 `M_SPD` 真值断言；删 `[TODO-R10]` → `[R-10-CLOSED]`；注释登记原式错误口径。 |
| **C-7** | `docs/phase3/qg-radial/r6789-10-test-hygiene.md` | §R-10（L83-96）+ §0 行 + §5 行 | 结论「几何不满足=真实待办」**更正为口径错误（已证伪）**；链接 `proto-elite-golive-spec.md §1.2/§8.5`；原结论降为 `<details>` 历史留档。 |
| **C-8** | `docs/phase3/proto-elite-w1.png` · `-w1-zoom.png` · `-w5-elite.png` · `-w5-zoom.png` | **新增** | 窗口模式实机截帧（原图 + 放大剪裁对照）。临时截帧脚本 `tests/_tmp_proto_capture.gd` 用后**已删**。 |
| **C-9** | 本文件 | — | 记录 + 证据 + 偏差 + 未决。 |

> 说明：`_tmp_proto_capture.gd` / `_tmp_zoom.py` 为临时工具，**跑完即删**（已确认 `tests/_tmp*` 为空）。

---

## 2. 逐项 ↔ 规格节号对照

| 工单 | 规格依据 | 落地 ↔ 规格一致性 |
|---|---|---|
| C-1 | spec §2.2 / §2.3 / 附录 C-1 | 注入点 = `boot.gd` 窗口分支、`add_child(bs)` 后、deferred `start_run` 前（`battle_shop.gd:50` 建 `wave_director`、`:91` deferred 开波）；**未注入** `battle_shop.gd`（保 `run_slice5_scene_smoke` L80 自选口径能力）。aggro 保持 OFF（stakeholder #4）。 |
| C-2 | spec §1.8 / §8.1 / 附录 C-2 | 上钳 `1.0 → 1.0/m_spd`；`rho_of_t(15, 2/3) = 55.0`；`m_spd==1 → 1/m_spd ≡ 1.0` 逐位恒等。 |
| C-3 | spec §8.1 / 附录 C-3 | E-R4 Tank 断言改 `55.0`（"出生在环上"正确值）。 |
| C-4 | spec §2.4 / §8.2 / 附录 C-4 | 去回落、去 WARN，取 `rt`（实机战斗↔收入一致）。 |
| C-5 | spec §4.2 / §8.3 / 附录 C-5 | RADIAL + proto/elite ON，300 局，80% 门禁。 |
| C-6 | spec §5.2 / §8.5 / 附录 C-6 | 生产镜像式 + `[R-10-CLOSED]`；proto OFF/ON 两档 PASS；`radial8` 不误红。 |
| C-7 | spec §1.2 / §8.5 / 附录 C-7 | R-10 结论更正为口径错误。 |
| C-8 | spec §6.2 | Rush 尖刺扇 / Tank 焦褐内环 / Elite 品红环 / 三档摆幅 / 精英波标记。 |
| C-9 | spec 附录 C-9 | 本文件。 |

---

## 3. 验收证据（原始输出）

### 3.1 默认回归 —— 逐位一致 ✅

```
$ <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd
EXIT = 0   [FAIL] 出现次数 = 0
汇总：通过  222 项 / 失败 0 项      （切片1）
汇总：通过 2228 项 / 失败 0 项      （切片2）
汇总：通过  142 项 / 失败 0 项      （切片3）
汇总：通过  123 项 / 失败 0 项      （切片4）
汇总：通过  302 项 / 失败 0 项      （切片5）
汇总：通过   41 项 / 失败 0 项      （切片6）
汇总：通过   31 项 / 失败 0 项      （切片7）
切片8 合计：PASS=92  FAIL=0         （切片8）
T1 仇恨 汇总：通过 216 项 / 失败 0 项
```
→ 聚合读数 **`222/2228/142/123/302/41/31/92/216 = 3397 项 · 0 失败`**，与改前**逐位相同**（C-2 只在 `m_spd==1` 时恒等 → 金标本零扰动守住）。

### 3.2 `radial8` 聚合 —— 8-8 PASS ✅

```
$ <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- radial8
radial8 结论：PASS（exit 0）· 8 项 · 总耗时 124.7 s
  [PASS] geo8(套件) exit=0 · radial(套件) exit=0 · geo8_smoke exit=0 · geo8_golden exit=0
         expo exit=0 · bulwark8 exit=0 · panorama8 exit=0 · attrition8 exit=0
```

### 3.3 `panorama8` 单跑 —— P-G8-5 转真闸门 ✅

```
$ <godot> --headless --path D:/roguedemo --script res://tests/run_slice_panorama8.gd
   [PASS] Rush m_spd == 4/3 / Swarm m_spd == 1 / Tank m_spd == 2/3
   最大出生极径（生产镜像式）= 55.00 · 包围盒内切半径 span=58.00
   prototype_split_enabled（生产默认）= false
   [PASS] P-G8-5 (proto OFF) 最大出生极径 55.00 ≤ span 58.00（全原型口径）
   [R-10-CLOSED] 最大出生 ρ = 55.00 ≤ span 58.00（口径更正：t_remain=t_reach/m_spd）
八槽全景几何自洽汇总：失败 0 项          EXIT = 0
```

### 3.4 实机口径 MC（C-5）—— 300 局 ✅

```
$ <godot> --headless --path D:/roguedemo --script res://tests/run_slice_proto_elite_mc.gd
口径：RADIAL · proto/elite ON · aggro OFF · n_slots=6(门禁臂)/8(参考臂) · seed=20260930 · κ_r=0.050 · W_MAX=20

---- n_slots=6（实机默认 · 门禁臂）----
  [A 单核] 起飞率=0.670  存活率=0.670  中位起飞波=8.0   平均结算波=17.19  (201/300)
       核心 HP 分布  0(失守):99  0<hp<=250:0  250<hp<=500:2  500<hp<=750:1  750<hp<1000:198  1000:0
  [B 多塔] 起飞率=0.917  存活率=1.000  中位起飞波=13.0  平均结算波=20.00  (275/300)
       核心 HP 分布  0(失守):0  0<hp<=250:0  250<hp<=500:1  500<hp<=750:0  750<hp<1000:2  1000:297

---- n_slots=8（八槽径向 · 参考臂 · Q-R9 未批准为出货配置）----
  [A 单核] 起飞率=0.670  存活率=0.670  中位起飞波=8.0   平均结算波=17.19  (201/300)
  [B 多塔] 起飞率=0.853  存活率=1.000  中位起飞波=13.0  平均结算波=20.00  (256/300)

  门禁判定（S5-D1 · 多塔 B 起飞率 ≥ 0.80）
  [PASS] B(n_slots=6) 起飞率 0.917 ≥ 0.80
MC_EXIT = 0
```

**判读**：
- **B@6 = 0.917 ≥ 0.80 → 门禁 PASS**（与 S5-D1 校准闸门历史读数 91.7% 一致②③）；B 中位起飞波 = **W13**（∈ W10–15）；B 存活率 1.000、297/300 满血 → 多塔流近乎免疫。
- A 单核起飞率 0.670（≥ 六槽 A 红线 0.60）；A 中位起飞波 W8（已拍板接受，不在 W10–15 窗口）。
- 🟡 **口径说明**：`RunLoopProto` 批处理镜像 `WaveDirector._substep` 的战斗结算**与 PATH/RADIAL 无关**（mode 只改"位置派生"、不改"t_remain 结算链"）→ 本 MC 设 `mode=RADIAL`（对齐实机口径标签）但数值与 PATH 相同；这是设计使然，非缺陷。

### 3.5 实机截帧（C-8）✅

窗口模式（`--path D:/roguedemo`，非 headless）实机截帧，四张落 `docs/phase3/`：

| 文件 | 内容 | 核到的要素 |
|---|---|---|
| `proto-elite-w1.png` | W1 全帧（10 怪铺满出生环） | 出生环上三原型分布 |
| `proto-elite-w1-zoom.png` | W1 放大剪裁对照 | **Rush 4 根长尖刺** / **Tank 焦褐内环 + 6 短粗刺** / **Swarm 5 中刺** / **三档摆幅（径向拉长 sway 态）** |
| `proto-elite-w5-elite.png` | W5 全帧（精英波，16 怪） | 顶部 **「精英波」标记** + 品红环精英 |
| `proto-elite-w5-zoom.png` | W5 放大剪裁对照 | **Elite 品红环 `#E8437F`**（Swarm 精英 / Tank 精英各一）+ 原型体 |

> 截帧方法：临时脚本 `tests/_tmp_proto_capture.gd` 以 RADIAL + proto/elite ON + `dps=0`（保怪不死）
> 确定性跳波（W1/W5），`RenderingServer.frame_post_draw` 后取视口纹理存 PNG（每段 <30s，规避窗口后台化挂死）。
> 放大剪裁用 Pillow（按敌橙 / 精英品红掩膜取组件 + 紧裁 + 最近邻放大）。**临时脚本已删除。**

---

## 4. 红线核对

| # | 红线 | 状态 | 证据 |
|---|---|---|---|
| 1 | 零定稿数值改动（`ATTRITION/κ_r/AGGRO_R/塔位6/SLOTS6/SPAWN_RADIUS/核心HP/leak_damage/hp_growth/M_HP/M_SPD/M_DPS/ELITE_*/SAPPER_DMG_MULT/三守恒`） | ✅ | 改动仅窗口注入 + `rho_of_t` 上钳 + 收入口径 + 测试/文档；`git diff` 无任何数值常量变更 |
| 2 | PATH 逐位等价 | ✅ | 默认回归聚合读数逐位不变；C-2 `m_spd==1` 时 `1/m_spd≡1.0` |
| 3 | 禁削 B 抬 A / 禁下调阈值 | ✅ | 未动任何强度项；MC 门禁阈值 0.80 与 S5-D1 一致，未下调 |
| 4 | `t_remain` 唯一权威 / 出生角零 RNG / `t_reach=10.0` 恒定 | ✅ | 未触碰 `spawn_theta` / `t_reach` |
| 5 | SpaceModel 双模可回滚（默认 PATH，窗口注入 RADIAL） | ✅ | `boot.gd` 回滚=删三行；`rho_of_t` 改动对 PATH 逐位恒等 |
| 6 | 渲染层只读 snapshot / 零玩法写入 / 零新信号 | ✅ | 渲染层脚本**未改动**；截帧为临时脚本（已删） |
| 7 | 未 git commit | ✅ | 保留工作区变更 |

---

## 5. 偏差登记

| # | 偏差 | 说明 | 处置 |
|---|---|---|---|
| **D-1** | MC 入口命名 | 规格建议 `run_slice_panorama8_proto_mc.gd`；实际命名 **`tests/run_slice_proto_elite_mc.gd`**（更贴合"原型/精英 MC"语义，与 `run_slice_geo8_mc.gd` 同族） | 已按建议"或类似"落地；如需改名请一并告知 |
| **D-2** | MC 臂数 | 规格仅要求 1 个实机口径 300 局；本次额外跑 **n_slots=8 参考臂**（Q-R9 八槽未批准为出货） | 门禁只判 **B@6**；8 槽为 INFO，不影响门禁 |
| **D-3** | RADIAL 对批处理 MC 数值无影响 | `RunLoopProto` 镜像 mode-agnostic 的战斗结算 → 设 RADIAL 与 PATH 数值相同 | 如实登记；已对齐实机口径标签，非缺陷 |
| **D-4** | `_realtime_is_golden_equivalent()` 成为未调用函数 | C-4 去闸门后唯一调用点移除 | 保留函数（grep 确认无其他引用）+ 注释标注"参考谓词、不再入账"；未删以降低扰动 |
| **D-5** | boot.gd `var bs` 未用静态 `:=` | 用未标注 `var bs = BattleShop.instantiate()` 以避免 `Node` 静态类型对 `bs.wave_director` 的成员访问报错 | `--check-only` 通过；语义等价（具名变量） |
| **D-6** | MC A/B 同 seed 复用 | A、B、8 槽臂各用 `PyRandom.new(20260930)`（与 S5-D1 / geo8_mc 同纪律） | 与既有 MC 脚本一致 |

---

## 6. 未决项 / 交接

1. 🔴 **`tower_aggro_enabled` 仍 OFF**（本刀范围，Sapper 仅"标记 + 可辨识"、无塔损）—— 属 T1 批次，需另立项（spec §8.4）。
2. 🟡 **八槽是否出货**（Q-R9）未结 —— 本 MC 已附八槽参考读数（B=0.853 仍 ≥0.80），待文策渊/用户定。
3. 🟢 实机截帧为**静态帧**；三档摆幅 / 核心呼吸等属"亚像素级"演出，建议需要时以 0.5× 录屏目视（同第三刀方法论）。
4. 🔴 本刀**未 git commit**，工作区变更保留，待主理人独立复核后提交。

---

*文档结束 · 程基岩 · 第四刀 C-1~C-9 落地 · 零定稿数值改动 · 默认回归逐位一致 · radial8 8-8 · MC B=0.917 · 截帧四张*
