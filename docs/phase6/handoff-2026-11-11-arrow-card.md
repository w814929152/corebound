# 箭塔限色卡面试装 · 2026-11-11

- 用户确认将本次生成的箭塔插画替换到游戏中预览；原图由用户保存至 `output/arrow-card/arrow-original.png`。
- 新资源：`art/2d/cards/card_arrow_illustration_v2.png`。`ui_style.card_art("Arrow")` 返回新图，图鉴与背包沿用各自等比缩放规则；原版资源保留。
- 商店箭塔使用全幅卡框插画，取消重复的中央插图，保留插画区占位，三卡尺寸一致。仅文字上下区域覆盖暗色渐变以保证可读性。其他塔保留现有背景与插画。
- 预览：`tools/preview_arrow_card.gd` 打开真实商店场景，展示 Arrow / Frost / Oblivion；`tools/shoot_native_cards.gd` 可生成截图，当前截图 `output/imagegen/native-cards-shop.png`。
- 已执行 Godot 资源导入、窗口截图目检、商店专项（三尺寸、PATH/RADIAL）、商店购买与拖放交互专项，后两项均输出 PASS，退出码 0；退出仍有既有日志目录及资源清理警告。未执行全量回归，未提交或推送。
- 不改数值、战场塔贴图或其他会话未提交的美术工作；既有 attrition8 已知红未处理。
