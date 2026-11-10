# 战场防御塔贴图 v2（2026-11-10）

> 目标：解决「战场里摆的塔长得都一样」。本轮只动美术资产与其产线/守卫，
> 不动数值 SSOT、金标本、玩法逻辑与渲染代码。

## 1. 问题复盘

旧产线 `tools/gen_art_pack_v1.py::gen_battle_sprites()` 用**同一套八边形模板**批量烘焙 15 张
`art/2d/sprites/sp_tower_*_v1.png`：

```
外描边八边形 → 深青底座 → 亮青塔身 → 左上白圆高光 → 中心圆 → 徽记 → 外扩描边
```

唯一差异是中心半径 `0.31R` 的小徽记（正 n 边形 + 1~2 笔符号）。在战场实际尺寸
（`monster_layer.gd` 的 `tsize = 4.0 * sc`，128² 贴图缩到约 40~60px）下，这个微差异几乎不可辨。

两处叠加的结构性问题：

1. **贴图分支会短路程序化差异**：`scripts/ui/monster_layer.gd::_draw_radial_towers()` 中
   `if tower_tex != null: draw_texture_rect(...)` 直接返回，`_draw_radial_tower_glyph()` /
   `_draw_glyph_mark()` / `_tower_glyph_color()` 全部落在 `else` 里。也就是说，
   贴图存在时 GDScript 里那些精心设计的边数 / 符号 / 配色**根本不执行** —— 辨识度完全由 PNG 承担。
2. **覆盖率只有 18%**：数值 SSOT `scripts/data/building_card_params.gd` 的 `TOWERS`(3) +
   `TOWERS_EXT`(79) 共 **82 个可摆放塔原型**，其中只有 15 个有贴图。其余 67 个走程序化降级，
   而 `_draw_radial_tower_glyph()` 未登记的 ctype 落默认 `n=3` 三角 —— 与 Arrow 撞脸。

这也解释了为什么 CI 全绿却长期没人发现：v1 时**没有任何图片资产 lint、尺寸校验或像素回归**。

## 2. 红线（art-bible）

| 条目 | 约束 | v2 的处理 |
|---|---|---|
| §3.1 | 塔的**外轮廓/剪影**必须严格 8 重对称，内芯徽记不得改变外框形状或顶点数 | 所有塔共用同一八边形外框；生成器末尾再叠一层八边形 alpha 蒙版 `clip_silhouette()`，任何武装部件都越不出剪影 |
| §2.1 | 玩家塔整体待在冷色极（青）做敌我识别，暖色越界会读成敌人 | 底盘/外框恒为 `#1A6B7D` + `#3ED0E8`；tag 色只用于内圈装甲、部件与内芯，不外溢到外框 |
| §9.2① | 任何游戏状态不得仅靠颜色传达 | tag 同时编码为形状：装甲端帽形状 + 中心符号 + 武装构型，三通道形状冗余 |
| §7.2 | 层 6 塔 = 双层八边形 + rim + 形态递进 + 受击闪 | 贴图只负责塔身；rim / 选中环 / 等级形态 / 充能环 / 受击白闪仍由 `monster_layer.gd` 运行时叠加，贴图外缘留干净边距 |

**未越过的边界**：本轮**没有修改 `scripts/ui/monster_layer.gd` 的任何一行**，也没有改
`ui_style.gd` 色板、`card_text.gd` 文案、`building_card_params.gd` 数值、`scenes/battle_shop.tscn` 层序。
因此 `_draw_radial_towers` 之后运行时叠加的 rim / 选中 / 等级 / 充能效果全部保持原样。

## 3. v2 视觉语言

统一骨架（阵营锚点，82 张一致）：外描边八边形 → 深青底盘 → tag 暗色内环 →
耀青主盘 → 8 个铆钉 → 左上贴边高光弧（不再用 v1 那个遮住内芯的大白圆）。

差异通道（全部落在八边形内框，覆盖约 70% 塔面）：

| # | 通道 | 取值 | 作用 |
|---|---|---|---|
| 1 | 武装构型 `arch` | 12 种：箭簇 / 重炮 / 冰晶 / 长枪 / 电极 / 破甲 / 符文环 / 虚空 / 卫星 / 转轮 / 双管 / 涡轮 | 宏观剪影级差异，主塔手工指定，卡包塔按 tag 循环 |
| 2 | 扇区装甲 `arms` / `spin` | 3~8 片 + 3 档旋转 | 覆盖塔面 1/3 的大色块，片数一眼可数 |
| 3 | tag 端帽形状 | 箭头 / 菱形 / 叉 / 尖刺 / 折线 / 横杠 / 圆点 / 双环 | 颜色之外的族形状编码 |
| 4 | 中心徽记 `sides` / `shade` | 正 3~17 边形 + 4 档明度 | 沿用 `_draw_radial_tower_glyph` 的边数约定 |
| 5 | 塔专属大符号 `glyph` | 12 种：三角 / 方 / 菱 / 五边 / 六边 / 四角星 / 六角星 / X / 双环 / 闪电 / 雪花 / 双 V | **族内主辨识通道**；v1 同族共用中心符号是撞脸主因 |
| 6 | 序号刻度 `pips` / 卫星 `sats` | 1~4 点 / 0~6 颗 | 同族同构型也能分辨，且不使用文字 |

tag 色表严格取自 art-bible §2.2 与 `ui_style.gd` 已登记色，不发明新色：

| tag | 主色 | 端帽 | 说明 |
|---|---|---|---|
| `""`（物理基础） | `#3ED0E8` 耀青 | 箭头 | 玩家本命色 |
| `fire` | `#FF6B3D` 熔橙 | 菱形 | 暖色仅限内圈/部件小面积 |
| `frost` | `#3EA8FF` 湖蓝 | 叉 | |
| `pierce` | `#FFC94A` 辉金 | 尖刺 | |
| `shock` | `#FFC94A` 辉金 | 折线 | 与运行时 `_tower_glyph_color` 电族口径一致 |
| `sunder` | `#9AA5B1` 钢灰 | 横杠 | |
| `hex` | `#B45CFF` 幽紫 | 圆点 | |
| `true` | `#F7FCFF` 近白 | 双环 | 配星紫 `#7A5CFF` 虚空环 |

小尺寸工程处理：4× 超采样（512²）后 LANCZOS 缩到 128²；所有描边统一 1.35× 增益，
炮管部件设 `min 0.095u` 宽度下限，端帽放大 1.8×；避免 v1 那种「细线缩到 1px 糊成一团」。

## 4. 加载契约（未改动）

```
scripts/data/building_card_params.gd  TOWERS / TOWERS_EXT  ->  ctype
scripts/ui/monster_layer.gd:1682      "sp_tower_" + ctype.to_lower()
scripts/ui/monster_layer.gd:145,152   res://art/2d/sprites/<name>_v1.png
scripts/ui/monster_layer.gd:1684      draw_texture_rect(Rect2(4.0*sc, 4.0*sc))  ->  恒 128²
```

`*.import` / `*.uid` 按 `.gitignore:31-35` 不入库，CI 在 `ci.yml` 里跑 `--headless --import` 重新生成；
本地要让新贴图在窗口模式生效，也需跑一次导入（见 §6）。

## 5. 产线与复现

生成器：`tools/gen_tower_sprites_v2.py`（Pillow，4× 超采样，纯确定性、无随机数）。
塔清单**运行时直接解析** `building_card_params.gd`，不硬编码；以后新增塔原型，重跑即自动补齐贴图。
`update_manifest()` 严格沿用 `art/manifest.json` 的 HEAD 格式（`indent=1`、末尾无换行），避免整份重排。

```bash
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"

py -3 tools/gen_tower_sprites_v2.py                 # 82 张贴图 + 预览 + manifest 登记
py -3 tools/gen_tower_sprites_v2.py --only Arrow    # 单张调试
"$GODOT" --headless --path . --import              # 让 Godot 重建 .import
"$GODOT" --headless --path . --script res://tests/lint_tower_sprites.gd   # 资产守卫
```

产物：

- `art/2d/sprites/sp_tower_<ctype>_v1.png` × 82（15 张覆盖 + 67 张新增），128² RGBA。
- `art/manifest.json`：塔身登记由 15 条扩到 82 条，file/size 与其它条目同格式。
- `design/art/previews/tower-sprites-v2-contact.png`：按 tag 分组总览（附名字与构型名）；
  当前文件是首版 **81 张快照**，第 82 个原型 `Icehunter` 为后续单张补齐，未重出总览。
- `design/art/previews/tower-sprites-v2-before-after.png`：15 张主塔的新旧并排对比（旧图取自 git HEAD）。

## 6. 守卫

新增 `tests/lint_tower_sprites.gd`（免导入，与 `lint_audio_assets.gd` 同款）：
用 `FileAccess` 裸文件系统校验 ① 82 个原型都有对应贴图、② PNG 签名合法、③ IHDR 恒 128×128、
④ 目录里无孤儿贴图、⑤ 任意两张不得逐字节相同（防塌回同一模板）。
已接入 `tests/run_tests.gd` 默认回归，也可单独用 `-- towersprites` 跑。

> 边界说明：md5 唯一性只能防「完全相同」，防不住「同模板换色」这类视觉雷同；
> 视觉质量仍靠上面的预览图人工验收。若以后要做像素级差异度门槛，可在此 lint 里加中心区域直方图比较。

## 7. 已知限制 / 后续

- **`Icehunter` 是单张补齐**：数值表新增第 82 个原型后，只用 `--only Icehunter` 补了这一张；
  同族按名字排序的 `idx` 会整体后移，导致其余 frost 塔的构型参数与「全量重跑」结果不同。
  数值表稳定后应全量重跑生成器并重出预览总览（本轮按约定未重新出图）。
- **PATH 模式**（headless 金标本基线）的塔仍是纯 `draw_circle`，不受本轮影响；本轮只服务实机 RADIAL。
- `art/2d/icons/ic_proto_*` 三张原型图标仍**未接线**（`ui_style.icon()` 只加载 coin/scrap/reroll 等）；可另开一轮接进卡面/商店。
- 根目录 `G:/AI Demo/art-turret/` 两张 AI 炮塔概念图是 3/4 侧视球体、风格与俯视八边形不符，且不在 `res://` 内，本轮未使用。
- 若要让每座塔连**外轮廓**都不同（art-bible §8.6 的「唯一剪影」字面要求），需先修订 §3.1 红线并走 ADR；当前实现是「统一外剪影 + 内部唯一构型」的合规折中。
- `build/windows/Corebound.exe` 仍是旧包（见 2026-11-09 交接），要看到新塔需重新导出。
- AI 出图（三风格样张 / 蓝图简化版 15 张）为**并列方案**，存于 `art/2d/sprites_ai_v3/`，未接线、未纳入本次提交。
