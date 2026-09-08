---
name: "tidekeeper-testbot-coverage"
description: "Keeps Tidekeeper Debug TestBot ACCEPT coverage in sync when adding or changing gameplay features. Use when shipping new systems, combat rules, config-driven mechanics, acceptance checklist items, or when the user mentions TestBot, bot-suite, ACCEPT, or机器人测试覆盖."
---

# Tidekeeper TestBot 覆盖同步

> 新功能落地时，**必须同步** Debug TestBot 可机读验收（`[TestBot] ACCEPT`），避免只靠专项机检、回归漏扫局内路径。  
> 主开发约定：[`tools/SKILL.md`](SKILL.md)。任务明细：[`docs/TestBot验收任务.md`](../docs/TestBot验收任务.md)。  
> **Clone / 拉代码后**：先跑 `powershell -ExecutionPolicy Bypass -File tools/sync_skills.ps1`，再写功能（同步 Trae + Cursor 硬链接；`.cursor/` 不入库）。

## 一、何时调用（强制）

在完成或收尾以下工作后**立即**执行本 skill（与功能同一 PR / 同一交付，不可「以后再补」）：

- 新玩法系统 / 局内规则 / 刷怪·词缀·事件·商店·成长·挫败感·难度
- 改 `config/` 且改变局内可观测行为（阈值、开关、表结构）
- 在 `docs/原型验证验收清单.md` 新增或改写可机读项
- 用户提到：TestBot / 机器人 / `--bot-suite` / ACCEPT / 验收套件

**可不做 Bot ACCEPT**（写明理由即可）：纯 UI 排版、纯美术/音效、Profiler 帧率、真人手感、仅 headless 单元逻辑且与局内路径无关的纯函数。

## 二、两层测试（都要考虑）

| 层 | 用途 | 典型入口 |
|----|------|----------|
| **专项机检** | 确定性断言、边界、公式 | `godot_project/scenes/tests/*.tscn` |
| **TestBot ACCEPT** | 局内路径可回归、可汇总 | `test_bot.gd` + `bot_suite.gd` + `debug*.bat` |

专项机检**不能替代** Bot：Bot 验证「正式开局 / 昼夜 / 信号 / 池 / 刷怪」真实路径上是否出现证据。

## 三、工作流

```
Task Progress:
- [ ] 1. 对照原型验证验收清单：新行为对应 #id（已有则复用；没有则先补清单再接线）
- [ ] 2. 设计可观测证据（信号 / GameState / spawner / 配置自检 / 峰值），禁止改玩法数值来「配合 Bot」
- [ ] 3. 在 test_bot.gd 增加 ACCEPT 探针（仅 --bot-suite 时记录；fail 不被后续 pass 抹掉）
- [ ] 4. 把 id 写入 bot_suite.gd 合适 suite 的 checklist（smoke 要短、acceptance 要全）
- [ ] 5. 更新 tools/check_bot_acceptance.py 的 CHECKLIST_LABELS
- [ ] 6. 更新 docs/TestBot验收任务.md 覆盖矩阵；必要时进度总览一句
- [ ] 7. 说明如何跑：debug.bat --bot-suite=smoke 或 debug_acceptance.bat；汇总 check_bot_acceptance.py
```

## 四、实现约定（红线）

1. **只观测、不改数值**：Bot 阈值（如峰值下限）属 Debug 门槛，玩法数值仍只读 `config/`
2. **无 suite 不污染**：`_suite_name == ""` 时不打 ACCEPT、不挂额外观测信号（与现有 `_record_accept` 一致）
3. **清单 id 稳定**：与 `docs/原型验证验收清单.md` / `TestBot验收任务.md` 编号一致
4. **语义勿假绿**：
   - 配置自检 alone → 最多 `skip` / `info`，不可当「生效」`pass`
   - `pass` 需局内证据（采样到实体、信号、命中、规则夜次等）
   - 多探针项须用 `_record_accept_keep_fail`（或等价）：既有 `fail` 不被后续 `pass` 抹掉；新探针不得只调 `_record_accept` 而允许 pass 盖 fail
5. **对象池 / 禁 instantiate**：观测路径禁止热路径 `instantiate`；连信号须在 `_exit_tree` 断开
6. **MVP 禁区**：不为侵蚀 / 契约 / 无尽 / 每日挑战 / 精炼 III 加 Bot 任务

## 五、文件清单（通常要动）

| 文件 | 改什么 |
|------|--------|
| `godot_project/scripts/debug/test_bot.gd` | ACCEPT 探针 / 采样 / 信号钩子 |
| `godot_project/scripts/debug/bot_suite.gd` | `SUITE_DEFAULTS[*].checklist` |
| `tools/check_bot_acceptance.py` | `CHECKLIST_LABELS` |
| `docs/TestBot验收任务.md` | 套件表 + 覆盖矩阵 |
| `docs/原型验证验收清单.md` | 若新增验收 # |
| （可选）`godot_project/scripts/tests/*_test.gd` | 专项机检并行补齐 |

参考现有探针：`1.1.2` 夜长、`2.4.2`/`2.4.3` 词缀、`4.3.12` 软上限、`4.5.4` 开箱、`4.9.1` 同屏峰值、`5.2` 无 SCRIPT ERROR。

## 六、套件选择建议

| 变更类型 | 至少写入 |
|----------|----------|
| 核心循环 / 崩溃面 | `smoke` + `crash` |
| 战斗 / 词缀 / 刷怪 / 拾取 | `smoke` + `acceptance`（建议再加 `full`） |
| 角色 / 难度 / 灯塔 meta | `meta` + `acceptance` |
| 通关 / 终局 | `full` + `acceptance` |

## 七、交付自检（对用户可见）

功能交付说明中须含一行：

- **TestBot**：清单 id=`…`；suite=`…`；证据=`…`；或 **N/A（原因）**

未写清视为未完成。

## 八、与其它 Skill 边界

| 需求 | Skill |
|------|--------|
| 写功能 + 红线 | `tidekeeper-godot-dev`（本 skill 为强制伴随） |
| Bot / ACCEPT 覆盖同步 | **本 skill** |
| 审查是否漏 Bot | `tidekeeper-code-review`（查「新功能无 ACCEPT」） |
| 只改文档口径 | `tidekeeper-refactor-docs` |

## 九、关联

- `docs/TestBot验收任务.md`
- `docs/原型验证验收清单.md`
- `debug.bat` / `debug_acceptance.bat`
- `python tools/check_bot_acceptance.py --latest`
