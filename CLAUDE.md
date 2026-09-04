# CLAUDE.md — Tidekeeper

修改本仓库前，按任务类型阅读对应 skill（正文在 `tools/`）：

| 任务 | 阅读 |
|------|------|
| 功能开发 / 场景 / 配置 | [`tools/SKILL.md`](tools/SKILL.md) |
| 重构文档 | [`tools/SKILL_refactor-docs.md`](tools/SKILL_refactor-docs.md) |
| 重构代码 | [`tools/SKILL_refactor-code.md`](tools/SKILL_refactor-code.md) |
| 代码审查 | [`tools/SKILL_code-review.md`](tools/SKILL_code-review.md) |

入口总表：[`AGENTS.md`](AGENTS.md)。同步硬链接：`tools/sync_skills.ps1`。

## 基线

- Godot 4.7.1 + GDScript（静态类型）
- 主文档 v0.3.5；任务表 20 周
- 数据：`config/*.json`；经验表由脚本生成

## 红线

1. 禁止第三方 ECS；节点 + 对象池
2. 运行时禁止业务 `instantiate`
3. 禁止硬编码玩法数值；禁止手改 `exp_table.json`
4. MVP 不做：侵蚀 / 契约 / 无尽 / 每日挑战 / 精炼 III
