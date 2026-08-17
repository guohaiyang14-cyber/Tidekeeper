# W12 被动系统（PassiveSystem）代码评审

> **评审对象**：W12 未提交改动（9 文件：3 新增 + 6 修改）
> **评审范围**：`passive_system.gd`（新增 autoload）、`config/passives.json`（effect 桶）、`project.godot`（注册）、`game_state.gd`（减伤/经验乘区 + 槽查询）、`weapon_base.gd`（伤害/攻速乘区）、`player.gd`（拾取半径乘区）、`scenes/tests/w12_passive_test.tscn` + `.gd`（机检）
> **方法**：逐文件读 diff + 新文件全读 + 全量机检回归
> **机检佐证**：`w12_passive_test` **50/0**；回归 `w11_refine_test` 86/0、`w10_evolution_test` 79/0（均 0 失败）

---

## 一、结论

**无阻断性 Bug，可进入下一原型周。** W12 接线正确、乘区分层清晰（基础×等级 → ×进化 → ×精炼 → ×被动，各独立可叠），公共信号契约变更安全，autoload 命名/初始化顺序红线均遵守（规避了 W11 的 `get_path` 崩溃）。

发现 **6 项问题，全部为低优先级（信息级/打磨级）**，无 [高]/[中]。其中 #1 为文档与实现口径不一致，#2–#4 为 MVP 范围内的已知待办或可选优化，#5–#6 为确认项（无风险）。

---

## 二、发现清单

### #1 [低] 经验倍率未硬钳制，与文档口径「钳制 ≤1.5」不一致

`passive_system.gd::get_exp_mult()`：

```gdscript
func get_exp_mult() -> float:
	return 1.0 + _total_pct("exp_pct") / 100.0
```

无 `clamp`。验收清单 4.3.7 标注「（钳制 ≤1.5 设计）」，但实现靠 config 隐式封顶——当前只有 `exp_sac` 提供 `exp_pct`（10%×5=50% → 倍率 1.5），恰好凑到 1.5。

- **风险**：若日后新增第二个 `exp_pct` 被动，倍率会突破 1.5 且无任何保护，与文档「钳制」语义不符。
- **建议（二选一，对齐即可）**：
  - 实现侧加 `clampf(1.0 + _total_pct("exp_pct") / 100.0, 1.0, 1.5)`，与文档一致；
  - 或把清单 4.3.7 措辞改为「由 config 上限约束（当前设计上限 1.5）」。

> 注：减伤/暴击/CD 三个比例类已 `clamp`（0.9 / 1.0 / 0.8），唯独经验未钳制，口径不统一，建议一并收敛。

---

### #2 [低] 三个桶已聚合但无消费侧接线（crit / area / cd）

`get_crit_chance()` / `get_area_mult()` / `get_cd_reduction()` 当前**无调用方**，属清单 4.3.11 「待验收」的已知缺口（钥被动深机制 MVP 简化为桶值，但 weapon 侧未消费）。

- 这是设计预期，不是缺陷；但作为公共 API 目前是死代码。
- **建议**：在 W13（或 MVP 打磨阶段）补消费侧——暴击判定、AoE 范围缩放、技能/被动 CD 缩减——否则长期留存「已聚合未接线」的 API 易被误判为遗漏。待接线后把 4.3.11 翻「通过（机检）」。

---

### #3 [低] `_total_pct` 每次调用都遍历并查 config，未缓存

`get_leveled_damage()`（每次开火）→ `get_damage_mult()` → `_total_pct()`，对 `GameState.passive_levels` 逐一调用 `ConfigLoader.get_passive()` 查表：

```gdscript
for wid in GameState.passive_levels.keys():
    var data: Dictionary = ConfigLoader.get_passive(sid)
    ...
```

- **规模**：仅 O(12) 字典查找，MVP 完全无压力（连射武器每弹重算也可忽略）。
- **可选优化**（非必须）：在 `add_passive` / `remove_passive` 时重算并缓存 8 个桶值，查询转 O(1)。当前不建议为性能提前优化，仅记录以便后续若接 350 敌性能周（W19）再评估。

---

### #4 [低] `_BUCKETS` const 未被使用

`passive_system.gd` 顶部定义了 8 桶常量数组 `_BUCKETS`，但 `_total_pct(bucket)` 接收字符串参数、未遍历/校验 `_BUCKETS`，该 const 仅具文档/注册意义。

- 无功能影响。
- **建议（轻微 robustness）**：若希望强校验传入 bucket 合法，可在 `_total_pct` 开头加 `assert(bucket in _BUCKETS, "未知被动桶: " + bucket)`，避免拼写错误静默返回 0。低优先级。

---

### #5 [信息/确认] 公开信号发射值变更（exp_gained / player_damaged）

W12 改了这两个信号的发射值：

- `GameState.add_exp`：`exp_gained.emit(gained, ...)` —— 现在发**实得经验**（已乘经验倍率），原为原始 `amount`。
- `GameState.damage_player`：`player_damaged.emit(applied, ...)` —— 现在发**实扣血量**（已减伤），原为原始 `amount`。

核查调用方：

- `player.gd::_on_player_damaged(_amount)` 忽略入参（仅触发闪红 `_hurt_flash`），不受影响。
- `exp_gained` 当前**仅测试连接**（`w12_passive_test._on_exp`），无 UI/玩法消费者。

→ **变更安全**，属信号契约预期演进。记录：UI 后续接「经验获得数字 / 伤害飘字」时应使用「实得/实扣」语义（已含被动效果），不要再用原始值重算。

---

### #6 [信息/良好] 初始化顺序与命名红线均遵守

- `project.godot`：`PassiveSystem` 注册于 `RefineSystem` 之后、`SaveSystem` 之前，顺序合理。
- 方法名全部自定义（`get_damage_mult` / `get_attack_speed_mult` / `get_crit_chance` 等），**规避了 W11 的 `get_path` 与 `Node` 原生冲突崩溃**（autoload 启动期解析失败 → Nil）。
- `PassiveSystem` 无状态，只读 `GameState.passive_levels` / `ConfigLoader`，不 instantiate、不在 `_ready` 反向调用其他 autoload → 无启动期相互依赖。
- **减伤统一入口**：所有玩家伤害（接触/弹幕/自爆）均经 `GameState.damage_player` 单一入口，被动减伤覆盖全部来源，设计正确。

---

## 三、修复建议汇总

| # | 严重度 | 描述 | 建议动作 | 是否阻塞 |
|---|--------|------|---------|---------|
| 1 | 低 | 经验倍率未钳制，与文档「≤1.5」不符 | 加 clamp 或改清单措辞（二选一对齐） | 否 |
| 2 | 低 | crit/area/cd 桶已聚合未接线 | W13/MVP 打磨补消费侧 | 否 |
| 3 | 低 | `_total_pct` 无缓存 | 可选，性能周再评估 | 否 |
| 4 | 低 | `_BUCKETS` const 未用 | 加 assert 校验（可选） | 否 |
| 5 | 信息 | 信号发射值变更 | 已确认安全，记录待 UI 使用 | 否 |
| 6 | 信息 | 初始化/命名红线 | 良好，无需动作 | 否 |

**结论**：0 高/中，6 低/信息；无阻断项。可直接进入下一原型周，或顺手修 #1（最小成本、消除文档/实现歧义）。

---

## 四、评审流程记录

- 评审时间：2026-08-17
- 评审人：AI（WorkBuddy）
- 配套机检：`w12_passive_test`（50/0）、回归 `w11_refine_test`（86/0）、`w10_evolution_test`（79/0）
- 提交状态：W12 改动尚未 commit（用户「3」启动，未要求提交）

---

## 五、修复记录

用户确认「修复」后，于 2026-08-17 修复两项低优先级发现（#1、#4）；#2/#3 留待后续周次：

- **#1 已修复**：`get_exp_mult()` 加 `clampf(..., 1.0, 1.5)`，与验收清单 4.3.7「钳制 ≤1.5」口径一致。改动文件 `godot_project/scripts/autoload/passive_system.gd`。
- **#4 已修复**：`_total_pct(bucket)` 开头加 `assert(bucket in _BUCKETS)`，防止拼写错误静默返回 0（debug 构建生效，release 自动剥离，无运行开销）。

> 未修复（设计预期 / 非缺陷）：
> - **#2**：`get_crit_chance`/`get_area_mult`/`get_cd_reduction` 三桶消费侧接线属 W13 功能任务（清单 4.3.11「待验收」），本回合不实现。
> - **#3**：`_total_pct` 缓存为可选性能优化，待 W19 性能周评估，MVP 规模 O(12) 无压力。
> - **#5 / #6**：信息级，无需动作。

- **修复后验证**：`w12_passive_test` 50/0、`w11_refine_test` 86/0、`w10_evolution_test` 79/0 全绿（含 clamp 后经验倍率仍精确 1.5、assert 未误触发）。
- 修复改动**尚未提交**（用户「修复」未附带「提交」指令，遵循不自动提交约定）。

---

## 六、二次审查修复（2026-08-17，用户「修复」）

针对二次 code review 的 P1/P2：

| 项 | 动作 |
|---|---|
| P1 crit/area/cd 未接线 | `WeaponBase.roll_hit_damage` / `scale_area_radius` / `get_attack_interval`；8 武器 fire/tick 消费；`crit_damage_mult` 入 `passives.json` |
| P1 减伤≠GDD | 清单 4.3.6 / `passives.json` note / `get_damage_reduction` 注释标明 MVP 线性 ≤0.9 |
| P2 注释 / 场景数 / 拾取测脆 | `set_pickup_radius_mult` 注释；机检 18 场景；拾取测用 `base_pickup_radius` |
| P2 `_total_pct` 缓存 | 仍留 W19 |

验证：`w12_passive_test` **56/0**；`w5_weapon_test` 11/0；`w11_refine_test` 86/0。

---

## 七、三次审查修复（2026-08-17）

| 项 | 动作 |
|---|---|
| P1 齐射/AoE 共用一次暴击 | AoE/近战每目标 `roll_hit_damage`；弹道 `get_leveled_damage` 发射，`Projectile` 每次命中 `PassiveSystem.apply_crit_to_damage` |
| P2 哨兵/注释/GDD 口径 | `get_attack_interval` 无效返回 -1；暴击/范围 MVP≠GDD 写入 metadata 与注释 |

验证：`w12` **57/0**；`w5` 11/0。