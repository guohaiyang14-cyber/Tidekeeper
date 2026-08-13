# AGENTS.md — Tidekeeper agent 入口

> Skill 正文只维护在 `tools/SKILL*.md`。改完后运行：`powershell -ExecutionPolicy Bypass -File tools/sync_skills.ps1`

## 开始任务前

1. **功能开发** → 阅读 [`tools/SKILL.md`](tools/SKILL.md)（`tidekeeper-godot-dev`）
2. **重构文档** → 阅读 [`tools/SKILL_refactor-docs.md`](tools/SKILL_refactor-docs.md)
3. **重构代码** → 阅读 [`tools/SKILL_refactor-code.md`](tools/SKILL_refactor-code.md)（仍须遵守主 Skill 红线）
4. **代码审查** → 阅读 [`tools/SKILL_code-review.md`](tools/SKILL_code-review.md)
5. 设计口径：`docs/《潮汐守夜人》游戏设计文档.md`（v0.3.4）
6. 周任务：`docs/单人开发任务拆分表_20周.md`

## Skill 一览

| name | 源文件 | 触发 |
|------|--------|------|
| `tidekeeper-godot-dev` | `tools/SKILL.md` | 写 GDScript / 场景 / 系统 / 配置 |
| `tidekeeper-refactor-docs` | `tools/SKILL_refactor-docs.md` | 重构文档、对齐口径、消矛盾 |
| `tidekeeper-refactor-code` | `tools/SKILL_refactor-code.md` | 重构代码、抽模块、行为守恒整理 |
| `tidekeeper-code-review` | `tools/SKILL_code-review.md` | code review / 审 diff / 查红线 |

## IDE 配置

| IDE | 配置 |
|-----|------|
| Cursor | `.cursor/rules/*.mdc` + `.cursor/skills/<name>/SKILL.md` + `.cursorrules` |
| Claude | `CLAUDE.md` |
| Trae | `.trae/skills/<name>/SKILL.md`（硬链接） |
| 通用 | 本文件 |

## 红线摘要

- Godot **4.7.1** + GDScript 静态类型
- 对象池：运行时禁止 `instantiate`
- 只读 `config/`；`exp_table.json` 禁手改
- MVP 不做侵蚀 / 契约 / 无尽 / 每日挑战 / 精炼 III

## 环境配置

- **Godot 引擎**（本机示例，可按安装路径替换）: `E:\Godot\Godot_v4.7.1-stable_win64_console.exe`

## 单测

```bash
# 使用本机 Godot 绝对路径（示例）
# 必须带 --fixed-fps 60：headless 下 delta 非确定（每帧真实耗时波动），
# 不固定帧率会导致依赖攻击/刷怪节奏的断言偶发失败（如 w5 area_burn）。
& "E:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --fixed-fps 60 --path godot_project res://scenes/tests/w1_unit_tests.tscn
```
