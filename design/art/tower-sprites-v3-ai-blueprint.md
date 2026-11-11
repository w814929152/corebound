# 防御塔美术 v3-ai · A 蓝图几何风（简化版，15 张）

> **状态：已选定风格并产出 15 张主塔贴图；并列方案，未接线、未覆盖 v2。**
> 创建：2026-11-10 · 交付物为设计/美术草稿，正式落地前需团队评审与素材授权确认。

## 1. 需求与对策

用户从三风格样张中选定 **A 蓝图几何风**，并要求 **「减少看不清楚的美术细节」**。
旧 A 样张的八边形里塞满铆钉、刻度、蚀刻线与细描边，缩到战场 48px 后糊成一团深色。
本轮从三处收敛：

| 环节 | 做法 |
|---|---|
| **出图端** | 极简 prompt：只允许 3–5 个大几何块面、粗描边、平涂高对比；显式禁用铆钉 / 螺丝 / 刻度 / 微文字 / 细线 / 渐变纹理 / 装饰图案；要求每个形状在 48px 缩略图下仍可读 |
| **后处理端** | 抠底归一 128² 后，按**战场实际尺寸 48px 做往返重采样** —— 读不出来的小结构被自然吸收，只留大块面与粗轮廓；再量化到 **7 色平涂** + 提亮增对比恢复鲜艳度 |
| **单塔返工** | `Bolt` 首次生成残留黑色尖刺与锯齿伪影，单独重出一张（加强禁尖刺/禁深色区域），产线改为「同目录取最新源图」，单塔重出自动生效 |

15 张共用同一套 prompt，只替换「单一主武装特征」与 tag 强调色，保证风格一致。

## 2. 产线与复现

```bash
py -3 tools/gen_tower_ai_blueprint.py --prompts   # 导出 15 塔 prompt（prompts.json）
py -3 tools/gen_tower_ai_blueprint.py --process   # 抠底 + 去细节 + 归一 + 出两张对比板
```

- 源图：`design/art/previews/ai-v3-blueprint/<Ctype>/<时间戳>.png`（按塔分目录，避免并行生成撞名）
- 抠底复用 `tools/ai_sprite_cutout.py`（径向背景场 + 连通域填实，去水印/网格线/白底）
- 成品：`art/2d/sprites_ai_v3/blueprint/sp_tower_<ctype>_ai_blueprint.png`

## 3. 15 座主塔

| ctype | tag | 主武装特征 | 强调色 |
|---|---|---|---|
| Arrow | physical | 斜向巨型箭矢 + 三角徽记 | `#3ED0E8` |
| Cannon | fire | 双粗炮管 + 菱形 | `#FF6B3D` |
| Frost | frost | 六角雪晶 | `#3EA8FF` |
| Lance | pierce | 长枪 + 三角 | `#FFC94A` |
| Tesla | shock | 双同心环 + 粗闪电 | `#FFC94A` |
| Sunder | sunder | 双楔形破甲块 + X | `#9AA5B1` |
| Hex | hex | 六边符文环 | `#B45CFF` |
| Ember | fire | 三片火瓣 | `#FF6B3D` |
| Icicle | frost | 三根冰锥 | `#3EA8FF` |
| Javelin | pierce | V 形双标枪 | `#FFC94A` |
| Bolt | shock | 单个粗闪电 | `#FFC94A` |
| Maul | sunder | 巨型锤头 + X | `#9AA5B1` |
| Rune | hex | 圆形符文 | `#B45CFF` |
| Oblivion | true | 空芯 + 亮环 | `#F7FCFF` |
| Void | true | 实心球 + 轨道环 | `#F7FCFF` |

## 4. 验收

- 15 张全部 **128² RGBA**，透明底干净（无白底 / 水印残留），每张恰好 **7 色平涂**，**md5 两两不同**。
- `tower-sprites-v3-ai-blueprint.png`：顶部三列「旧 A → 简化版 A → v2 基准」128² / 48px 对比，下方 15 塔总览。
- `tower-sprites-v3-ai-blueprint-48px.png`：15 塔战场实际 48px 全览 —— 均可读出形状 + tag 颜色，明显优于旧 A 在 48px 下的模糊深色团。
- 与 v2 相比：细节大幅减少、颜色更统一；v2 的高饱和青色块面在 48px 下仍略胜一筹。

## 5. 已知限制（落地前需处理）

1. **tag 强调色部分失效**：AI 未严格按指定 hex 上色（如 `Lance` 偏绿、`Tesla` 偏米色），
   若接线需补一层程序化 tag 色块，否则违反 art-bible §9.2「不得仅靠颜色区分」的形状冗余要求。
2. **剪影未统一**：部分塔有探出八边形的武装件（Arrow 箭矢、Frost 雪晶、Icicle 冰锥），
   与 §3.1 八边形红线冲突。落地需叠八边形 alpha 蒙版，或走 ADR 修订红线。
3. **仍有少量残留细碎件**：Hex / Maul 的一圈小方块、Frost 顶部雪晶枝在 48px 下仍偏碎，
   已由 48px 往返重采样柔化，但不如纯程序化干净。
4. **最相似的一对**：`Arrow` 与 `Void`（均为蓝色八边形 + 中心圆环），建议给 Void 补一个更明显的轨道形状。
5. **只覆盖 15 座主塔**，未铺到全部 82 个可摆放原型；AI 逐张生成的风格一致性无法像程序化产线那样硬保证。

## 6. 接线说明

成品文件名 `sp_tower_<ctype>_ai_blueprint.png` 与运行时拼名契约
`sp_tower_<ctype>_v1.png`（`monster_layer.gd::_sprite`）不匹配，因此**不会被加载**，
不影响 v2、金标本、数值 SSOT 与任何回归断言。要真正替换战场贴图，需：
改拼名 / 覆盖 v2 文件 → `--headless --import` → 重导出 `build/windows/Corebound.exe` → 全量回归。

---

本内容为设计草稿参考，正式落地前需经团队评审与合规审核；AI 生成素材的使用授权亦需团队确认。
