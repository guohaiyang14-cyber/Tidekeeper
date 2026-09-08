# TestBot 验收任务（对齐原型验证验收清单）

> **版本**：v1.0  
> **日期**：2026-09-08  
> **对齐**：[`原型验证验收清单.md`](原型验证验收清单.md) v3.5+ · [`开发进度总览.md`](开发进度总览.md) · `AGENTS.md`

---

## 1. 目的

把「可机读 / 可回归」的验收项接到 Debug TestBot 套件上，使机器人任务与清单编号一一对应；纯视觉 / Profiler / 真人体验项仍标 **人工**。

| 证据类型 | 工具 |
|----------|------|
| Godot 日志 `[TestBot] ACCEPT` / `ACCEPT_SUMMARY` | `python tools/check_bot_acceptance.py` |
| CombatLog JSONL | `python tools/stats_combat_logs.py` |
| 局次胜负 / 夜次 | `python tools/view_bot_runs.py` |

---

## 2. 套件一览（`--bot-suite`）

| suite | 默认角色 | 难度 | 灯塔 | max_night | max_runs | 主要清单 id |
|-------|----------|------|------|-----------|----------|-------------|
| `smoke` | watcher | lighthouse | none | 10 | 3 | 1.1.1 / 1.1.2 / 1.2.3 / 3.3 / 5.2 |
| `crash` | watcher | lighthouse | none | 8 | 3 | 5.2 / 3.3 |
| `full` | watcher | lighthouse | random | 20 | 5 | 3.3 / 2.5.3 / 4.10.1 / 5.2 |
| `meta` | cycle×3 角色 | cycle 难度 | cycle 灯塔 | 12 | 9 | 4.6.x / 4.8.1（解锁覆盖） |
| `acceptance` | watcher | lighthouse | sweep×2/档 | 20 | 6 | 上表综合 + 4.5.2 / 4.5.3 / 4.2.8 |

显式 CLI / 环境变量 **覆盖** suite 默认值。

---

## 3. 启动示例

```bat
rem 推荐：验收总套件（灯塔 none→partial→full 各 2 局，夜上限 20，满 6 局退出）
debug_acceptance.bat

rem 等价
debug.bat --bot-suite=acceptance --bot-speed=6

rem 冒烟：3 局打到第 10 夜截断
debug.bat --bot-suite=smoke

rem 崩溃回归：3 局打到第 8 夜
debug.bat --bot-suite=crash --bot-speed=8

rem 自定义
debug.bat --bot-suite=full --bot-character=blacksmith --bot-difficulty=watcher --bot-max-runs=3
```

| 参数 | 环境变量 | 含义 |
|------|----------|------|
| `--bot-suite=` | `TIDEKEEPER_BOT_SUITE` | smoke / crash / full / meta / acceptance |
| `--bot-character=` | `TIDEKEEPER_BOT_CHARACTER` | watcher / blacksmith / stargazer / cycle / random |
| `--bot-difficulty=` | `TIDEKEEPER_BOT_DIFFICULTY` | lighthouse / watcher（守夜人档）/ cycle |
| `--bot-max-night=` | `TIDEKEEPER_BOT_MAX_NIGHT` | 0=不截断；到 N 夜昼后计完成并重开 |
| `--bot-max-runs=` | `TIDEKEEPER_BOT_MAX_RUNS` | 0=不限；完成 N 局后 quit |
| `--bot-lighthouse=` | `TIDEKEEPER_BOT_LIGHTHOUSE` | 同既有 |
| `--bot-runs-per-config=` | `TIDEKEEPER_BOT_RUNS_PER_CONFIG` | 同既有 |
| `--bot-speed=` | `TIDEKEEPER_BOT_SPEED` | 同既有 |

`meta` 套件会会话内解锁全部角色（`MetaSystem` 覆盖，**不写存档**）。

---

## 4. ACCEPT 行格式

```
[TestBot] ACCEPT id=1.1.2 status=pass detail=n=5_expect=60_got=60
[TestBot] ACCEPT_SUMMARY suite=acceptance runs=6 wins=1 ge8=6 ge10=4 script_err=0 pass=1.1.1,1.1.2,... fail=- skip=4.2.8
```

| status | 含义 |
|--------|------|
| pass | 本进程已观察到通过证据 |
| fail | 观察到与清单冲突（含 5.2 在完成局达标但仍扫到 SCRIPT ERROR）；**可覆盖先前 pass** |
| skip | 本局未触发（如未精炼）；不覆盖 pass/fail |
| info | 辅助信息 |

仅 `--bot-suite=…` 时输出 ACCEPT（自由 Debug 跑不打）。`ACCEPT_SUMMARY` 含 `script_err=N`。夜上限截断会先 `MetaSystem.end_run()` 再选角重开（`cycle` 角色会推进）。`check_bot_acceptance.py` 解析与上述覆盖规则一致。

汇总：

```bash
python tools/check_bot_acceptance.py --latest
python tools/check_bot_acceptance.py --suite acceptance --json
```

---

## 5. 清单覆盖矩阵

| 清单 # | Bot 能力 | 套件 | 人工仍需 |
|--------|----------|------|----------|
| 1.1.1 昼夜循环 | 夜结束 / peak / 截断均需 **≥10** | smoke / acceptance | — |
| 1.1.2 夜长 | 对比 `duration_for_night` | 全部 | — |
| 1.1.5 跳过焦点 | — | — | 试玩 |
| 1.2.1 移速 | `base_move_speed` vs config | 全部 | 手感 |
| 1.2.3 守望者 | 选角日志 | smoke+ | — |
| 1.2.4 灯塔碰撞 | — | — | 试玩 |
| 3.3 到 8~10 夜 | peak / cutoff / 夜结束 **≥8** | smoke / crash / acceptance | — |
| 5.2 连续 3 局无崩 | ≥3 局 peak≥8 **且** 本会话 `godot.log` 无新增 `SCRIPT ERROR`/`Error at:`；`fail` 可覆盖先前 `pass`；汇总前重算 | crash / acceptance | 硬崩溃仍可能来不及写日志；日志轮转时只重锚定 EOF、不重扫文件头 |
| 4.5.2 N15 排除反转 | 事件 id | full / acceptance | — |
| 4.5.3 夹击 | spawner.is_pincer_mode | full / acceptance | — |
| 4.2.8 精炼入口 | Bot 调用 RefineSystem | full / acceptance | UI 排版 |
| 2.5.3 / 4.10.1 | 通关 win | full | — |
| 4.6 / 4.8 | 角色 cycle / 难度 | meta | UI |
| 5.1 / 5.3 | — | — | Profiler |
| 4.1.4 / 4.4.9 / 4.5.9 / 4.6.13 / 4.7.11 | — | — | 视觉 |

---

## 6. 与 CombatLog 的关系

- Bot 套件跑 Debug 时 CombatLog 默认开启（`debug_only`）。
- `map.pincer` 已与 `EnemySpawner.is_pincer_mode()` 对齐（含第 15 夜天灾夹击）。
- 勾选清单时：**ACCEPT_SUMMARY + CombatLog** 可并用；帧率/内存仍只认 Profiler。
