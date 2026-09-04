---
name: "tidekeeper-refactor-docs"
description: "Refactors Tidekeeper design/docs for consistency, version alignment, and cross-references. Use when the user asks to refactor docs, restructure markdown, sync GDD/README/task tables, fix doc contradictions, or clean docs/ after design changes."
---

# Tidekeeper 文档重构助手

> 重构 `docs/`、`README.md` 及相关说明时使用。玩法数值与红线以主设计文档 + `tools/SKILL.md` 为准，本 skill 只管文档结构与口径一致。

## 一、何时调用

- 用户说：重构文档 / 整理文档 / 对齐口径 / 消歧 / 更新日志 / 拆分或合并 md
- 发现多份文档互相矛盾、版本戳过期、链接失效、MVP 范围写错

## 二、权威顺序（冲突时）

1. `docs/《潮汐守夜人》游戏设计文档.md`（当前 v0.3.5）
2. `docs/《潮汐守夜人》设计文档更新日志_*.md`
3. `docs/技术选型.md` / `docs/单人开发任务拆分表_20周.md` / 原型验收清单
4. `README.md`（目录与入口说明，不另立玩法规则）
5. `tools/SKILL.md`（实现红线；文档不得鼓励违反）

## 三、工作流

```
Task Progress:
- [ ] 1. 明确范围：哪些文件、要解决的矛盾/目标结构
- [ ] 2. 盘点引用：版本号、§章节、config 字段、周次(W1–W20)
- [ ] 3. 起草变更：先列「改什么/为什么」，再动笔
- [ ] 4. 同步卫星文档：README / Sprint 清单 / 验收清单 / 更新日志
- [ ] 5. 自检：无矛盾、无过期版本、无把延后内容写进 MVP
```

### 3.1 允许做

- 合并重复段落、拆过长章节、统一术语表
- 修正错误引用、过期版本戳、死链
- 把已否决方案移入「归档 / 不在 MVP」并加一句指向
- 更新日志追加一条（日期 + 变更要点）

### 3.2 禁止做

- 擅自改玩法数值、夜长、槽位、精炼约束、MVP 范围
- 把侵蚀 / 诅咒契约 / 无尽 / 每日挑战 / 精炼 III 写回 MVP
- 手改 `config/exp_table.json` 或伪造「已实现」状态
- 为重构而重构：无矛盾、无结构问题时不扩写

## 四、术语与格式

| 项 | 约定 |
|----|------|
| 引擎 | Godot **4.7.1**（勿写回 4.3 等旧口径） |
| 周期 | 单人 **20 周**；原型 **W1–W4** |
| 夜长 | 常规 45s / 精英 60s / 天灾 90s / 终局 120s |
| 槽位 | 武器 4 / 被动 6 |
| 精炼 MVP | 最多 **2 II**，无 III |
| 标题 | 保持现有中文文档风格；不引入无关英文化大改 |

## 五、交付格式

重构完成后用简短清单回复：

```markdown
## 文档重构摘要
- 范围：…
- 对齐到：主文档 vX.Y.Z
- 改动文件：…
- 消除的矛盾：…
- 未改（需设计决策）：…
```

## 六、关联

- 实现红线：`tools/SKILL.md`（`tidekeeper-godot-dev`）
- 代码侧重构：`tools/SKILL_refactor-code.md`（`tidekeeper-refactor-code`）
