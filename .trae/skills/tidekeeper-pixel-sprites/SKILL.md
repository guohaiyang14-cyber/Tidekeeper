---
name: "tidekeeper-pixel-sprites"
description: "Tidekeeper 项目「游戏像素精灵」生成与校验工具（单一实现：tools/generate_pixel_sprites.py）。需要新增/修改敌人、Boss、玩家角色（watcher/blacksmith/stargazer）、地面砖、武器、被动图标等像素精灵时调用；或某 id 找不到贴图、敌人显示成方块、角色显示成兜底圆、贴图缺失时；或校验 config id ↔ png 是否对齐（缺图会静默掉图、不报错）时。触发词：生成精灵、加个敌人图、改角色图、补图标、缺图、方块、没贴图、纯色、像素图、sprite、generate_pixel_sprites、精灵对齐、缺图校验。工具零依赖手写 PNG，输出到 godot_project/assets/sprites/{enemies,player,ground,weapons,passives}/<id>.png。仅覆盖游戏精灵，不含 UI 像素资源（generate_ui_pixel_assets.py）。主开发约定：tools/SKILL.md。"
---

# Tidekeeper 游戏像素精灵 — 生成与校验工具

> **Clone / 拉代码后**新增精灵前，先跑 `powershell -ExecutionPolicy Bypass -File tools/sync_skills.ps1`
> 让各 agent 工具包拿到最新技能硬链接（`.cursor/`、`.workbuddy-ai/` 不入库，靠此脚本本地再生）。
>
> 本技能是**可发现入口**；真正的绘制逻辑全在 **`tools/generate_pixel_sprites.py`**（单一事实源，勿在别处重复造轮子）。
> 所有命令都在**项目根**执行。底层复用 `tools/generate_ui_pixel_assets.py` 的 `Canvas / PNG 编码 / shade / compose_sheet`（零依赖手写 PNG：zlib + IHDR/IDAT/IEND）。

## 输出目录

```
godot_project/assets/sprites/enemies/<id>.png   # 9 杂兵 + 3 Boss 同在 enemies/（Boss 不带 boss_ 前缀）
godot_project/assets/sprites/player/<id>.png    # 角色（目录名 player 是单数！）
godot_project/assets/sprites/ground/floor_<n>.png
godot_project/assets/sprites/weapons/<id>.png
godot_project/assets/sprites/passives/<id>.png
```

**文件名 = config 里的 id**（运行时按 `enemy_id`/角色 id 等经 `scripts/core/sprite_lib.gd` 取图；缺失则静默隐藏，不报错——这正是必须跑 `check` 的原因）。

## CLI 用法（在项目根执行）

```bash
python tools/generate_pixel_sprites.py list                 # 列出当前能生成的全部 category/id（REGISTRY）
python tools/generate_pixel_sprites.py check                # 校验 config id ↔ png，列出缺图的 id
python tools/generate_pixel_sprites.py one <cat> <id>        # 生成单个，如 one player stargazer / one enemies small_goblin
python tools/generate_pixel_sprites.py all                  # 生成全部（默认行为，确定性幂等）
python tools/generate_pixel_sprites.py all --sheet=/tmp/x.png  # 拼一张对照表便于目视
```

退出码：`one` 命中未注册 id 返回 `2` 并打印 `[skip]`（不崩）；`check` 有缺图返回 `1`，全对齐返回 `0`。

## 可 import API（其他 agent / 脚本）

```python
import importlib.util
spec = importlib.util.spec_from_file_location("gps", "tools/generate_pixel_sprites.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

m.list_ids()                 # -> {"enemies":[...], "player":[...], "ground":[...], "weapons":[...], "passives":[...]}
m.check_alignment()          # -> True/False（打印对齐明细）
cv = m.generate_one("player", "stargazer")   # -> Canvas 或 None（未注册）
m.generate_all()             # -> 生成并返回 Canvas 列表
m.REGISTRY                   # {(category, id): 绘制函数}
```

## 如何新增一张精灵（标准流程）

1. 在 `tools/generate_pixel_sprites.py` 对应区写一个绘制函数（返回 16×16 逻辑 `Canvas`；用现成基本体 `blob/eye/spike/line/ring`）。
   例：新增敌人 `e_kraken()`。
2. 注册进 `REGISTRY` 来源：杂兵/Boss 加进 `_build_registry()` 的对应元组；武器进 `WEAPON_ICONS`；被动进 `PASSIVE_ICONS`。
   **id 必须与 `config/*.json` 里的 id 完全一致**（敌人→`enemies.json`，Boss→`bosses.json`，武器→`weapons.json`，被动→`passives.json`，角色→`characters.json`）。
3. `python tools/generate_pixel_sprites.py all`（或 `one <cat> <id>`）。
4. `python tools/generate_pixel_sprites.py check` 确认对齐；必要时
   `godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/diag_visibility_test.tscn` 复核。
5. 只提交 `tools/generate_pixel_sprites.py` + 新 `.png`（`tools/*.md` 是正典技能，改动走仓库提交）。

## 已知坑（写前先读）

- **`player/` 是单数**：别 `ls players`。
- **Boss 精灵存 `enemies/` 且不带 `boss_` 前缀**：文件名必须等于 `bosses.json` 的 id（`tide_archon`/`jellyfish_queen`/`devouring_star`）。
  曾因生成器存成 `boss_<id>.png` 而运行时按 `id` 取图 → 3 个 Boss 静默不显示。
- **无 `.import` 文件**：`assets/sprites/**` 下没有 `.import`，精灵在编辑器/打包里加载走
  `scripts/core/sprite_lib.gd` 的 `ResourceLoader.load → Image.load_from_file 兜底`。改文件名**只需动 `.png`**，不用管 `.import`。
- **本工具确定性、幂等**：重跑产物 md5 一致；重构前后不得改变既有像素输出（改绘制参数属有意的美术改动，例外）。
- **敌人 `Visual` 节点名必须保留** `Visual`（`scripts/tests/diag_visibility_test.gd` 断言 `has_node("Visual")`）；改 `scenes/enemy.tscn` 时注意。
- **技能注册**：改本技能或新增技能，走 `tools/SKILL_*.md` + `tools/sync_skills.ps1`，不要直接写 `.cursor` / `.workbuddy-ai` 下的 skills 目录。

## 与其他工具的分界

- 本技能 = **游戏精灵**（敌人/Boss/角色/地面/武器/被动图标），共 38 张。
- `tools/generate_ui_pixel_assets.py` = **UI 像素资源**（面板/按钮/进度条/图标贴图，走 `config/ui_skin.json` + `scripts/ui/pixel_skin.gd`），未 CLI 化，需另外处理。
- 两者共用 `Canvas/PNG` 编码，但用途、配置源、输出目录不同，勿混。
