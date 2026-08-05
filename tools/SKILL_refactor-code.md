---
name: "tidekeeper-refactor-code"
description: "Refactors Tidekeeper Godot/GDScript/Python tooling without changing intended gameplay behavior. Use when the user asks to refactor code, clean architecture, extract modules, reduce duplication, improve typing, or restructure scenes/scripts under godot_project/ or tools/."
---

# Tidekeeper 代码重构助手

> 重构 `godot_project/`、`tools/`、`config/` 消费侧代码时使用。必须先遵循 `tools/SKILL.md`；本 skill 追加重构纪律（行为守恒、小步提交、可验证）。

## 一、何时调用

- 用户说：重构代码 / 抽模块 / 降重复 / 理清场景树 / 加强类型 / 改名整理
- 审核或实现后出现结构债，但不要求改玩法

## 二、前置

1. 阅读并遵守 [`tools/SKILL.md`](SKILL.md)（架构 / 类型 / 对象池 / 数据驱动红线）
2. 明确范围：文件列表 +「行为必须不变」或「允许的行为差异」
3. 有测试则先跑：`godot --headless --path godot_project res://scenes/tests/w1_unit_tests.tscn`

## 三、工作流

```
Task Progress:
- [ ] 1. 锁定目标：可读性 / 去重 / 对齐 SKILL 场景树 / 性能，三选一为主
- [ ] 2. 行为基线：列出对外 API、信号、autoload、config 字段依赖
- [ ] 3. 小步改动：一次一个主题；避免顺手加功能
- [ ] 4. 验证：单测 + 主场景 headless 冒烟（或说明无法跑的原因）
- [ ] 5. 摘要：改了什么、为何更清晰、风险点
```

## 四、硬约束（重构也不可破）

| 红线 | 要求 |
|------|------|
| 运行时实例化 | 禁止业务路径 `instantiate`；只允许对象池预分配 / 受控 `expand` |
| 物理 | 海量敌我检测走 `SpatialHash`，不改回 Physics2D 主路径 |
| 类型 | GDScript 保持静态类型；`@onready` + `$`；禁止 `get_node("a"+"b")` |
| 数据 | 玩法数值只读 `config/`；不手改 `exp_table.json` |
| 随机 | 局内随机走 `RNG` autoload |
| 范围 | 不引入第三方 ECS；不把 P2/延后系统（侵蚀等）做进 MVP |

## 五、推荐手法

### 5.1 优先

- 提取重复逻辑到 `scripts/core/` 或明确命名的 helper
- 对齐 SKILL §2.2 场景树（`Main → World → …`）；空壳节点补脚本或删掉死节点
- `Array` → `Array[T]`；补 `class_name` / 信号类型
- 把硬编码角色/武器数值迁到 `config/`（若缺表，先加 JSON 再改读取）
- Python 工具：去 emoji、统一 `[OK]/[FAIL]`，保持 Windows GBK 可跑

### 5.2 避免

- 大爆炸重写整局循环
- 「重构」时偷偷改数值、夜长、掉落、AI 频率
- 为抽象而抽象（过早 ECS、过深继承）
- 删除看似无用但文档/任务表仍引用的骨架（改为标注 TODO 周次）

## 六、行为守恒检查单

- [ ] Autoload 名与加载顺序未无故更改
- [ ] 信号名/参数兼容（或同步改所有连接方）
- [ ] 对象池 acquire/release 语义不变
- [ ] 昼夜时长常量仍为 45/60/90/120
- [ ] 配置键名与 `config/*.json` 一致

## 七、交付格式

```markdown
## 代码重构摘要
- 目标：…
- 行为：守恒 / 有意差异（列出）
- 改动文件：…
- 验证：单测 …；冒烟 …
- 后续可选：…
```

## 八、关联

- 主开发约定：`tools/SKILL.md`（`tidekeeper-godot-dev`）
- 文档重构：`tools/SKILL_refactor-docs.md`（`tidekeeper-refactor-docs`）
- 代码审查：`tools/SKILL_code-review.md`（`tidekeeper-code-review`）
