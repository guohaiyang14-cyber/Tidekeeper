---
name: "tidekeeper-godot-dev"
description: "Godot 4 + GDScript dev assistant for Tidekeeper roguelite. Invoke when writing GDScript, creating scenes, implementing weapons/enemies/bosses, debugging gameplay, or adding any game feature per design doc."
---

# Tidekeeper Godot 开发助手

> 《潮汐守夜人》项目专用开发约定。辅助 GDScript 编码、场景搭建、系统实现时必须遵循。

## 〇、调用方式

| IDE | 方式 |
|-----|------|
| Trae | 自动加载（`.trae/skills/` 硬链接；`tools/sync_skills.ps1`） |
| Cursor | `.cursor/rules/tidekeeper-godot-dev.mdc` + `.cursor/skills/<name>/` + `.cursorrules` |
| Claude | 根目录 `CLAUDE.md` |
| 通用 agent | 根目录 `AGENTS.md` |
| 手动 | 「请先阅读 tools/SKILL.md」 |

### 项目 Skill 一览（正文均在 `tools/`）

| Skill | 源文件 | 用途 |
|-------|--------|------|
| `tidekeeper-godot-dev` | `tools/SKILL.md` | **主开发约定**（写功能必读） |
| `tidekeeper-refactor-docs` | `tools/SKILL_refactor-docs.md` | 重构 / 对齐文档 |
| `tidekeeper-refactor-code` | `tools/SKILL_refactor-code.md` | 重构代码（行为守恒） |
| `tidekeeper-code-review` | `tools/SKILL_code-review.md` | 代码审查（默认只报告） |

> 约定变更只改 `tools/SKILL*.md`，然后运行 `tools/sync_skills.ps1` 同步 Trae + Cursor。
> Trae 内置 skill（code-review / debugger 等）由 Trae 自动调度。

## 一、项目基线

- **引擎**：Godot 4.7.1 stable（锁定版本）
- **语言**：GDScript（强制静态类型）
- **模式**：单人 + agent 开发，20 周周期
- **主文档**：`docs/《潮汐守夜人》游戏设计文档.md`（v0.3.5）
- **任务表**：`docs/单人开发任务拆分表_20周.md`
- **技术选型**：`docs/技术选型.md`

## 二、架构约定（必须遵循）

### 2.1 不用 ECS 框架

使用 Godot 原生节点系统 + 代码层对象池。**禁止引入 RelEcs 等第三方 ECS**。

### 2.2 场景树结构

```
Main
├── World
│   ├── Player
│   ├── EnemySpawner
│   ├── EnemyPool / ProjectilePool / ParticlePool / PickupPool
│   └── SpatialHash
├── UI (HUD / DayPhaseUI / ResultUI)
├── GameState (autoload)
└── SaveSystem (autoload)
```

### 2.3 对象池（禁止运行时 instantiate）

- 预分配：场景加载时 `preload` + `instantiate` 填充池
- 获取：`pool.acquire()` → 激活 + 重置状态
- 回收：`pool.release(node)` → 失活 + 移出场景树
- **红线：运行时禁止 `instantiate`，必须走对象池**

### 2.4 碰撞（不用 Godot Physics2D）

- 自定义 `SpatialHash` 类，`Dictionary` 存储 `Vector2i → Array[Node]`
- 网格尺寸 = 敌人半径 × 4（约 80 游戏单位）
- 敌人↔敌人：仅分离检测（排斥向量），不做物理碰撞
- 投射物↔敌人：投射物查所在网格 + 8 邻格

### 2.5 渲染优化

- 同种敌人用 `MultiMeshInstance2D` 批量渲染（单 draw call / 种类）
- 粒子全局池 200 实例 + 优先级回收

## 三、GDScript 代码规范

### 3.1 静态类型（强制）

```gdscript
# ✅ 正确
var health: int = 100
var enemies: Array[Enemy] = []
func take_damage(amount: int) -> void:

# ❌ 错误（禁止无类型）
var health = 100
func take_damage(amount):
```

### 3.2 命名约定

| 类型 | 约定 | 示例 |
|------|------|------|
| 类/节点 | PascalCase | `EnemyBase`, `WeaponHarpoon` |
| 函数/变量 | snake_case | `take_damage`, `move_speed` |
| 常量 | SCREAMING_SNAKE | `MAX_ENEMIES`, `NIGHT_DURATION` |
| 信号 | snake_case | `enemy_died`, `night_started` |
| 文件 | snake_case | `enemy_base.gd`, `weapon_harpoon.gd` |

### 3.3 节点获取

```gdscript
# ✅ 用 @onready + $ 语法
@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: ProgressBar = $UI/HealthBar

# ❌ 禁止 get_node() 字符串拼接
get_node("Sprite2D")
```

### 3.4 信号

```gdscript
# 定义
signal enemy_died(enemy: Enemy)
signal night_started(night_number: int)

# 连接（强类型）
enemy_died.connect(_on_enemy_died)

# 发射
enemy_died.emit(self)
```

## 四、数据驱动规则

### 4.1 config/ 是唯一数据源

- 武器/敌人/Boss/事件配置：`config/*.json`
- 经验表：`config/exp_table.json`（由 `tools/generate_exp_table.py` 生成）
- 精炼数据：`config/refine_data.py`

### 4.2 禁止硬编码数值

```gdscript
# ✅ 从配置读取
var damage: int = weapon_data["base_damage"]
var exp_required: int = ExpTable.get_exp(level)

# ❌ 禁止硬编码
var damage: int = 12  # 鱼叉枪伤害
```

### 4.3 经验表红线

- **必须由 `tools/generate_exp_table.py` 生成**
- **禁止手动修改 `config/exp_table.json` 任意一行**
- 运行时通过 `ExpTable` 单例查表

## 五、核心系统实现约定

### 5.1 昼夜循环

- 夜晚时长常量：常规 45s / 精英 60s / 天灾 90s / 终局 120s
- 夜晚结束无条件进昼（敌人未清完也切换）
- 抉择之昼无强制倒计时（可无限停留）

### 5.2 武器系统

- 8 种基础武器：鱼叉枪/灯塔圣火/锚锤/水母孢子/雷暴云/水母炮/锚链/信天翁
- 武器槽上限 4 个、被动槽上限 6 个
- 自动索敌、自动攻击
- 武器等级 1~7

### 5.3 敌人 AI 分帧

| 分组 | 更新频率 | 包含 |
|------|---------|------|
| 远程敌人 | 每 1 帧 | 潮汐召唤师 |
| 近战敌人 | 每 2 帧 | 小水鬼/铁壳蟹/深潜者 |
| 小怪/召唤物 | 每 4 帧 | 水母浮游/爆炸贝/毒水母 |

### 5.4 精炼约束

- MVP 只有精炼 I/II（精炼 III 延后封测）
- 一局最多 2 II（MVP 无 III）
- 精炼 III DPS ≤ 3.5×（封测校验，非 MVP）

### 5.5 确定性 RNG

- 全局 `RNG` 单例（autoload），基于 `RandomNumberGenerator`
- 所有随机决策走此单例
- 整数采样优先，避免浮点误差
- 种子存入存档，支持回放

## 六、性能预算

| 指标 | 目标 | 达标节点 |
|------|------|---------|
| 同屏敌人 | 350~450 @ 60fps（PC） | W19 |
| 100 敌 60fps | W8 达标 | W8 |
| 内存 | ≤ 512MB | W19 |
| draw call | ≤ 100 | W19 |

## 七、agent 协作分工

### 7.1 委托 agent（高效）

- 配置表 JSON 生成（武器/敌人/Boss 数据）
- 脚手架代码（对象池、空间哈希、RNG 单例）
- 行为类武器/敌人实现
- Bug 定位+修复
- 单元测试用例
- 文档更新

### 7.2 人工主导（不委托）

- 架构决策（模块边界、接口设计）
- 玩法调优（手感、节奏、难度曲线）
- 试玩验证（每周五试玩）
- 数值校准（DPS/血量/经验）

### 7.3 agent 生成代码审查

- agent 生成的代码**必须人工审查后才能提交**
- 重点关注：对象池使用（是否误用 instantiate）、类型注解、性能（是否在循环中分配内存）

## 八、红线事项（不可违反）

1. **不得删除 MVP 范围内的任何功能**（3 角色 / 8 武器 / 8 进化 / 8 精炼 I-II / 9 敌人 / 3 Boss / 7 事件）
2. **侵蚀等级 / 诅咒契约 / 无尽模式 / 每日挑战** 不得进入 MVP
3. **精炼 III** 延后至封测前；MVP 上限为 2 II
4. **经验表由脚本生成**，禁止手改 `config/exp_table.json`
5. 代码需保持 **60fps 目标**（100 敌 W8 达标 / 350 敌 W19 达标）
6. 运行时只读 `config/`，禁止硬编码数值
7. **P2 任务可砍**，但 P0/P1 不可砍
8. 锁定 Godot 4.7.1 stable 版本

## 九、常用参考

| 需求 | 查看文档 |
|------|---------|
| 武器/敌人/Boss 数值 | 主文档 §9.4 MVP 底数表 |
| 进化路径 | 主文档 §6.5 + 附录 A.1 |
| 精炼路径 | 主文档附录 B + `config/refine_data.py` |
| 机制实现疑点 | `docs/实现疑点清单.md`（17 题已解答） |
| 性能优化 | `docs/实现疑点清单.md` Q10-Q12 |
| 时长控制 | `docs/单局时长控制策略.md` |
| 每周任务 | `docs/单人开发任务拆分表_20周.md` |
| 原型验收 | `docs/原型验证验收清单.md` |

## 十、代码生成模板

### 10.1 敌人基类示例

```gdscript
class_name EnemyBase
extends CharacterBody2D

signal enemy_died(enemy: EnemyBase)

@export var max_health: int = 100
@export var move_speed: float = 80.0
@export var damage: int = 10

var health: int
var target: Node2D
var update_group: int = 2  # 1=每帧, 2=每2帧, 4=每4帧

func _ready() -> void:
    health = max_health

func acquire(p_target: Node2D, spawn_pos: Vector2) -> void:
    target = p_target
    global_position = spawn_pos
    health = max_health
    visible = true
    process_mode = Node.PROCESS_MODE_INHERIT

func release() -> void:
    visible = false
    process_mode = Node.PROCESS_MODE_DISABLED

func take_damage(amount: int) -> void:
    health -= amount
    if health <= 0:
        enemy_died.emit(self)
        release()

func _physics_process(delta: float) -> void:
    if Engine.get_process_frames() % update_group != 0:
        return
    if target:
        var direction: Vector2 = (target.global_position - global_position).normalized()
        velocity = direction * move_speed
        move_and_slide()
```

### 10.2 对象池示例

```gdscript
class_name EnemyPool
extends Node

@export var enemy_scene: PackedScene
@export var pool_size: int = 500

var _pool: Array[EnemyBase] = []

func _ready() -> void:
    for i in pool_size:
        var enemy: EnemyBase = enemy_scene.instantiate()
        enemy.process_mode = Node.PROCESS_MODE_DISABLED
        enemy.visible = false
        add_child(enemy)
        _pool.append(enemy)

func acquire() -> EnemyBase:
    for enemy in _pool:
        if not enemy.visible:
            return enemy
    push_error("EnemyPool exhausted!")
    return null

func release(enemy: EnemyBase) -> void:
    enemy.release()

## 十一、Headless 测试与 .godot 缓存（高频坑）

> 本会话（W5）实测踩坑，反复出现，务必记牢。

- **class_name 注册依赖缓存**：Godot headless **不会**自动扫描注册「未被 autoload/场景直接引用」的脚本 `class_name`（缓存文件 `.godot/global_script_class_cache.cfg` 由编辑器生成）。新增脚本后用代码 `.new()` 会报 `Could not resolve script` / `Could not find type X`。修复：跑一次 `godot --headless --editor --quit --path godot_project` 重建缓存。
- **严禁 `rm -rf .godot` 后只跑 `--quit-after`**：删缓存会让全项目 class_name 失效（满屏 "Could not find type"）；`--quit-after` 不扫描脚本、无法重建。正确顺序：先 `--editor --quit`（或 `--import`）重建缓存，再跑业务场景。
- **`preload` 自依赖强制注册**：凡用 `.new()` 实例化某 class 的脚本，在文件顶部 `const _X = preload("res://.../x.gd")`，确保 headless 强制加载并注册 class_name（例：weapon_manager.gd 顶部 preload 三种武器类）。
- **单测帧时间确定性**：headless 默认 fps 高，`await get_tree().process_frame` 固定帧数 ≠ 固定时长。攻击间隔长的武器（如圣火 1.25s）在 150 帧内可能不触发。运行单测**务必加 `--fixed-fps 60`**（150 帧 = 2.5s），断言才稳定可复现。
- **单测场景运行范式**：`godot --headless --fixed-fps 60 --path godot_project res://scenes/tests/<name>.tscn`；autoload 单例（ConfigLoader/GameState/RNG…）随场景自动加载；测试内 `await get_tree().process_frame` 推进帧，结束 `get_tree().quit(0/1)`（0=全过 / 1=有失败）。
- **Godot 路径（本机示例）**：`E:\Godot\Godot_v4.7.1-stable_win64_console.exe`。
```
