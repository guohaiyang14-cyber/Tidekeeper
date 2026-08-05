---
name: "tidekeeper-code-review"
description: "Reviews Tidekeeper GDScript, scenes, config consumers, and Python tools against project red lines. Use when the user asks for code review, PR review, diff review, agent-generated code audit, or to check ObjectPool/SpatialHash/typing/config compliance."
---

# Tidekeeper 代码审查助手

> 审查 `godot_project/`、`tools/`、配置消费代码。标准来源：`tools/SKILL.md` + 主设计文档红线。默认 **只报告、不直接改代码**；用户明确要求「顺手修」时再改。

## 一、何时调用

- 用户说：code review / 代码审查 / 审 diff / 审 PR / 检查 agent 生成代码
- 合并前、W 末验收前、或重构/功能实现后的质量门禁

## 二、前置

1. 阅读 [`tools/SKILL.md`](SKILL.md) 红线与架构约定
2. 确认审查范围：未提交 diff / 指定文件 / 相对某分支
3. 能跑则跑：`godot --headless --path godot_project res://scenes/tests/w1_unit_tests.tscn`

## 三、审查工作流

```
Task Progress:
- [ ] 1. 收集变更：git diff / 指定路径；列出触及的 autoload、信号、config 键
- [ ] 2. 红线扫描：对象池 / 物理 / 类型 / 硬编码 / RNG / MVP 范围
- [ ] 3. 正确性：空引用、状态机、生命周期、池耗尽、信号断开
- [ ] 4. 性能：_process 分配、全量遍历、不必要的 instantiate/expand
- [ ] 5. 输出分级发现项 + 建议；无问题也写明已覆盖的检查面
```

## 四、检查清单

### 4.1 P0 红线（违反即阻断）

| 检查 | 不合格示例 |
|------|------------|
| 运行时实例化 | 战斗/刷怪/弹道路径直接 `instantiate`（未走池） |
| 物理主路径 | 用 Physics2D 做海量敌我碰撞，绕过 `SpatialHash` |
| 经验表 | 手改 `config/exp_table.json` |
| MVP 范围 | 引入侵蚀 / 诅咒契约 / 无尽 / 每日挑战 / 精炼 III 玩法代码 |
| 引擎 | 依赖非 Godot 4.7.x API 或把项目降到未锁定版本 |

### 4.2 P1 正确性 / 约定

- GDScript 缺少静态类型；`get_node("a"+"b")`；应用 `@onready`+$ 却用松散查找
- 局内随机未走 `RNG` autoload
- 玩法数值硬编码（应读 `config/`）；角色/武器表可迁未迁
- 信号参数类型/改名未同步所有连接方
- `GameState` 开局未 `start_new_run`；昼夜时长偏离 45/60/90/120
- 对象池 `acquire` 未重置状态 / `release` 未失活
- 场景树与 SKILL §2.2 严重偏离且无说明

### 4.3 P2 可维护性 / 性能

- 过长函数、重复逻辑、无意义抽象
- `_process` / 每帧 `Array` 新建、字符串拼接
- `expand()` 被当作常规生成手段
- 测试缺失：改了池/哈希/RNG/经验却无单测更新
- Python 工具在 Windows 控制台因非 ASCII 崩溃

### 4.4 安全 / 存档（轻量）

- `user://` 存档 JSON 无版本字段或盲目信任解析结果
- 路径拼接读到仓库外任意文件（配置加载应限制在 `config/`）

## 五、分级与口吻

| 级别 | 含义 |
|------|------|
| **P0** | 必须修才能合入 / 继续下周 |
| **P1** | 应修；可短时带入但须登记 |
| **P2** | 建议；不阻塞 |

- 每条发现写清：**位置**（文件/符号）→ **问题** → **为何违反哪条约定** → **建议改法**
- 不复述大段无关代码；不把风格偏好写成 P0
- agent 生成代码按 SKILL §7.3：**默认不信任**，重点盯池与类型

## 六、交付格式

```markdown
## Code Review 摘要
- 范围：…
- 结论：通过 / 有条件通过 / 阻断
- 验证：单测 …（通过/失败/未跑）

### P0
- `path:symbol` — 问题。建议：…

### P1
- …

### P2
- …

### 已覆盖且无问题
- 对象池路径 / SpatialHash / RNG / 配置只读 / …
```

## 七、与其它 Skill 的边界

| 需求 | 用哪个 |
|------|--------|
| 审查问题 | `tidekeeper-code-review`（默认只报告） |
| 按审查结果改结构 | **本 skill** |
| 写新功能 | `tidekeeper-godot-dev` |
| 文档口径 | `tidekeeper-refactor-docs` |

## 八、关联

- 主约定：`tools/SKILL.md`
- 重构：`tools/SKILL_refactor-code.md`
