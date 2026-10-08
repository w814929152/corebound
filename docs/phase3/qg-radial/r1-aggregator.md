# R-1：径向验证脚本接入聚合入口 `radial8`

> 质量门 `docs/phase3/quality-gate-radial-migration.md` · R-1（🔴 P1 放行前置项）
> 执行：程基岩（技术负责人） · 引擎 Godot 4.7.2 headless · 工作目录 `D:/roguedemo`

---

## 1. 目标与结论（先给结论）

| 项 | 结果 |
|---|---|
| `radial8` 聚合入口 | ✅ 已实现并实测通过 |
| 一键全跑 | ✅ **exit 0** · 9 项全绿 · **285 s（≈4 分 45 秒）** |
| exit code 传播 | ✅ 注入失败实测 **exit 1**，进程内套件 / 子进程两条路径均已验证 |
| 默认无参回归未受影响 | ✅ 仍只跑 slice1~8 + t1aggro，**exit 0 · 144 s**，日志中零径向内容 |
| 重型诊断件可达性 | ✅ 额外提供 `radial8diag`（11 项，**exit 0 · 414 s**），10 个径向脚本 + 探针全部有入口 |

改动只落在 `tests/run_tests.gd`（+ 两份运行日志）。**未改任何玩法代码 / GDD / 判据口径。**

---

## 2. 改了什么

唯一代码改动文件：**`tests/run_tests.gd`**

1. **参数分派**新增 `radial8` / `radial8diag` 两个入口值（与既有 `radial` / `geo8` / `sliceN` 并列）。
2. 新增三个配置常量：`RADIAL8_GATES`（6 个闸门件）、`RADIAL8_DIAG`（1 个轻量诊断件）、`RADIAL8_DIAG_HEAVY`（2 个重型诊断件）。
3. 新增三个函数：
   - `_godot_bin()` —— 子进程用哪个 Godot（优先环境变量 `GODOT_BIN`，否则 `OS.get_executable_path()`）；
   - `_radial8_subproc(item)` —— 串行拉起一个子脚本，返回 `{name, code, ms, marks}`；
   - `_run_radial8(include_heavy)` —— 聚合主体，末尾打印 ASCII 汇总表。
4. 顶部注释补齐跑法、入口语义与已知限制。

### 2.1 机制选型：为什么是「两套机制」而不是一套

径向脚本天然分成两类，**沿用各自既有的组织方式**是最低风险的做法：

| 类别 | 脚本 | 机制 |
|---|---|---|
| **A. 套件** | `test_suite_geo8.gd`、`test_suite_radial.gd` | `extends RefCounted` + `run_all() -> bool` → **进程内 preload 直调**（与既有 `geo8` / `radial` 分支完全同款） |
| **B. 独立脚本** | 7 个 `run_slice_*` / `scan_*` / `probe_*` | `extends SceneTree`，在 `_initialize()` 内**自行 `quit(code)`** → 只能**子进程**拉起 |

B 类不能用函数调用的原因：这些脚本在 `_initialize()` 末尾自己调 `quit()`；若在主进程里 `new()` 一个非主循环的 `SceneTree` 实例再调 `_initialize()`，`quit()` 不会传播退出码，也就拿不到 PASS/FAIL。故用 `OS.execute` 串行拉起子进程并回收各自 exit code —— 实测 `OS.execute` 在 headless `--script` 下**是阻塞的**，且退出码可正确回收。

> 关键约束：`radial` 套件会切 `SpaceModel.mode = RADIAL`（全局开关），跑完立即设回 `PATH`，防止污染同进程内后续默认回归 —— 沿用原代码已有的防护。

### 2.2 入口清单

**`-- radial8`（一键回归，9 项）**

| # | 名称 | 脚本 | 语义 |
|---|---|---|---|
| 1 | `geo8(套件)` | `test_suite_geo8.gd` | 闸门 · 八槽 E8-A 几何（进程内） |
| 2 | `radial(套件)` | `test_suite_radial.gd` | 闸门 · 阶段0 运动学（进程内） |
| 3 | `geo8_smoke` | `run_slice_geo8_smoke.gd` | 闸门 · 八槽端到端冒烟 |
| 4 | `geo8_golden` | `run_slice_geo8_golden.gd` | 闸门① · 逐位零污染 |
| 5 | `expo` | `run_slice_expo.gd` | 闸门 · 径向暴露度解析解单测 |
| 6 | `bulwark8` | `run_slice_bulwark8.gd` | 闸门 · 径向肉盾塔 |
| 7 | `panorama8` | `run_slice_panorama8.gd` | 闸门 · 全景几何自洽 |
| 8 | `attrition8` | `run_slice_attrition8.gd` | 闸门 · V-1′ 300 局验收 |
| 9 | `geo8_mc` | `run_slice_geo8_mc.gd` | **诊断（脚本内恒 `quit(0)`）** |

**`-- radial8diag`（= radial8 + 2 个重型诊断件，11 项）**

| # | 名称 | 脚本 | 说明 |
|---|---|---|---|
| 10 | `scan_attrition8` | `scan_attrition8.gd` | 扫描器，恒 `quit(0)`；聚合时传**粗扫档 `60 局 × 步长 1.0`** |
| 11 | `probe_radial_aggro` | `probe_radial_aggro.gd` | 探针，恒 `quit(0)` |

**为什么 `scan_attrition8` / `probe_radial_aggro` 不进 `radial8`**：两者源码内都是硬编码 `quit(0)`，**没有任何 PASS/FAIL 闸门语义**，纳入只会拖慢一键回归而零保护价值。而 `scan_attrition8` 默认档是 `[1.0, 6.0]` 步长 0.5 = **11 个点 × 300 局**的网格扫描，单点量级已属分钟级，全量约 1 小时 —— 放进日常入口不可接受。故降级到 `radial8diag`（配粗扫档压到 ~2 分钟），保证它们"一行命令可复现"、不游离在入口之外，需要定稿级 300 局 × 0.5 扫描时仍直接跑原脚本。

**为什么 `geo8_mc` 留在 `radial8` 里**：它是闸门②的基线诊断，虽然脚本内恒 `quit(0)`，但纳入后可一键复现；汇总表里标 `INFO` 而非 `PASS`，提醒读者**它不会主动报错**。其退出码仍并入聚合（非零 = 脚本崩了，也是真信号）。

---

## 3. 实测结果

### 3.1 `-- radial8` 全绿（最终代码，2026-10-08）

```
<godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- radial8
→ exit 0 · 墙钟 285 s
```

```
radial8 汇总（9 项 · 总耗时 282.7 s）
  [PASS] geo8(套件)               exit=0      36 ms  失败标记x   -
  [PASS] radial(套件)             exit=0     911 ms  失败标记x   -
  [PASS] geo8_smoke             exit=0     949 ms  失败标记x   0
  [PASS] geo8_golden            exit=0     759 ms  失败标记x   0
  [PASS] expo                   exit=0     677 ms  失败标记x   0
  [PASS] bulwark8               exit=0     517 ms  失败标记x   0
  [PASS] panorama8              exit=0     583 ms  失败标记x   0
  [PASS] attrition8             exit=0  105760 ms  失败标记x   0
  [INFO] geo8_mc                exit=0  172445 ms  失败标记x   0
radial8 结论：PASS（exit 0）
```

- 进程内套件：`geo8` 32/0、`radial` 42/0（与质量门记录一致）。
- 全日志 `[FAIL]` 出现次数 **0**。
- 完整日志：`docs/phase3/qg-radial/r1-radial8.log`

**耗时结构**：`geo8_mc` 172 s + `attrition8` 106 s = **278 s，占总量 98%**。其余 7 项合计不到 5 秒。
→ 若后续觉得一键入口太慢，**第一个可优化点就是把 `geo8_mc` 挪到 `radial8diag`**（它恒 `quit(0)`，无闸门价值），可把 `-- radial8` 压到约 110 s。是否调整请主理人拍板，我未擅自改。

### 3.2 `-- radial8diag`（11 项）

```
→ exit 0 · 墙钟 414 s
  [INFO] scan_attrition8        exit=0  126235 ms  （粗扫 60 局 × 步长 1.0，6 个点）
  [INFO] probe_radial_aggro     exit=0    1973 ms
```
日志：`docs/phase3/qg-radial/r1-radial8diag.log`
粗扫档确认生效（网格 1.00/2.00/…/6.00，表头"每点 60 局 MC"）。

### 3.3 exit code 传播验证（注入失败实验）

临时制造两处失败（改完即 `git checkout` 还原，已确认无残留）：

| 注入点 | 类型 | 目的 |
|---|---|---|
| `test_suite_geo8.gd` `run_all()` 强制 `return false` | **进程内套件**路径 | 验证 A 类失败能翻 exit code |
| `run_slice_expo.gd` 强制 `quit(1)` | **子进程**路径 | 验证 B 类失败能翻 exit code |

结果：

```
RADIAL8 exit=1 · 283 s
radial8 汇总（9 项 · 总耗时 280.9 s）
  [FAIL] geo8(套件)               exit=1      34 ms
  [FAIL] expo                   exit=1     631 ms
  [PASS] 其余 7 项 …（未 fail-fast，仍跑完并给出完整报告）
radial8 结论：FAIL（exit 1）
```

✅ 两条路径的失败都能传播成整体非零退出；且聚合器**不做 fail-fast** —— 一处失败仍会跑完其余项，便于一次拿到完整回归画像。
日志：`docs/phase3/qg-radial/r1-radial8-failinject.log`

补充：另在探针阶段验证过「脚本路径不存在」时 Godot 子进程返回 exit 1，聚合器能正确捕获。代码中也加了 `FileAccess.file_exists` 前置校验（Godot 可执行文件 / 验证脚本任一缺失即响亮失败），避免路径写错导致的**假绿**。

### 3.4 默认无参回归未受影响

```
<godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd
→ exit 0 · 144 s
```

- 日志中**零**径向内容（grep `radial / 八槽 / 径向` 无命中）。
- 8 个套件汇总：222 / 2228 / 142 / 123 / 302 / 41 / 31 / 99 —— 全部「失败 0 项」。
- 结论：`radial8` 是独立入口值，`only == ""` 的默认分支一行未动，默认 PATH 快速回归**未被拖慢、未被改变**。

---

## 4. 已知限制（需要知道，但不阻塞放行）

**Windows 下聚合日志里子脚本的中文会乱码。**
根因实测确认：Godot 4.7.2 的 `OS.execute` 用**系统 ANSI 代码页（GBK）**解码子进程 stdout，而非 UTF-8，且是**有损**转换（部分字节落成 PUA 私有区字符，不可逆）。父进程自己 `print()` 的部分正常。

影响与缓解：
- `[PASS]` / `[FAIL]` / 数值 / 末尾 ASCII 汇总表**全部不受影响** → CI 判定与失败定位可用；
- 聚合器额外统计每段子脚本输出里的 `[FAIL]` 标记数（纯 ASCII），并在汇总表输出；
- 汇总表与行内标签**故意不使用 `[FAIL]` 字面量**，因此 **grep `\[FAIL\]` 聚合日志 = 0 即真全绿**，不会被聚合器自身文案误报；
- 需要读中文原文时，单独直接跑该脚本即可（不走 `OS.execute`，输出正常）。

未采用的两个修法及理由：`OS.execute` 传 `null` 让子进程继承 stdout —— 绑定是强类型 `Array`，传 `null` 直接解析报错；改用 `cmd.exe` 重定向再读文件 —— 可行但引入 Windows 专属依赖，未来上 Linux CI 会炸，得不偿失。

---

## 5. 一键跑法（贴给 CI / 人工）

```bash
GD="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 日常 PATH 快速回归（默认，144 s）
"$GD" --headless --path D:/roguedemo --script res://tests/run_tests.gd

# 径向保护网一键全跑（285 s）
"$GD" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- radial8

# 径向 + 重型诊断件（414 s，人工判读用）
"$GD" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- radial8diag
```

注意：入口参数走 `OS.get_cmdline_user_args()`，**必须**用 `--` 分隔（`-- radial8`），否则参数不生效。

---

## 6. 给主理人的两点建议（未擅自执行）

1. **`geo8_mc` 是否挪出 `radial8`**：它占一键回归 61% 耗时（172 s）且恒 `quit(0)`、零闸门价值。挪到 `radial8diag` 后 `-- radial8` 约 110 s。改一行常量即可，等你拍板。
2. **下一步才谈 CI**：R-1 只解决"有一键入口 + exit code 可信"。工程**仍然没有 CI**（无 CI 配置文件、无自动触发）。质量门 §2.4-a 把"无 CI"和"脚本游离"并列为同一条，本条只完成了后半段。建议后续单独开一条：CI 配置文件 + `radial8` 作为 nightly/周频任务、`slice1~8+t1aggro` 作为每次 push 任务。另外 §4.4 提的 stderr 白名单（TextServer/Font RID 泄漏污染 CI 信号）也应一并纳入，否则"exit 0 + stderr 非空"会让真失败淹没在红字里。
