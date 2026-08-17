# W11 精炼系统 — 代码评审报告

> 评审对象：未提交的 W11 改动（4 新增 + 9 修改文件，与 `git diff` 一致）
> 评审日期：2026-08-17
> 评审结论：**无阻断性 Bug，可提交**（确认后连同 `docs/原型验证验收清单.md` v2.1 一起 commit，不 push）

---

## 一、评审范围

| 文件 | 类型 | 说明 |
|---|---|---|
| `config/refine_paths.json` | 新增 | 8 路径 I/II + rules（MVP #1~#8） |
| `godot_project/scripts/autoload/refine_system.gd` | 新增 | 精炼系统 autoload |
| `godot_project/scenes/tests/w11_refine_test.tscn` | 新增 | 测试场景 |
| `godot_project/scripts/tests/w11_refine_test.gd` | 新增 | 78 断言机检 |
| `godot_project/scripts/autoload/config_loader.gd` | 改 | 加载 refine + 查询方法 + 8 路径红线校验 |
| `godot_project/scripts/autoload/game_state.gd` | 改 | refine_tiers / 精华 / 信号 / 重置 |
| `godot_project/scripts/combat/weapon_base.gd` | 改 | get_leveled_damage 叠加精炼乘区 |
| `godot_project/scripts/core/enemy_spawner.gd` | 改 | 击杀接入 Boss/精英掉落 |
| `godot_project/scripts/core/shop_ui.gd` | 改 | 精炼按钮 + 精华标签 |
| `godot_project/scripts/autoload/evolution_system.gd` | 改 | `get_path`→`evolution_path`（规避原生方法冲突） |
| `godot_project/scripts/tests/w10_evolution_test.gd` | 改 | 同步 `evolution_path` 调用点 |
| `godot_project/project.godot` | 改 | 注册 RefineSystem |

---

## 二、已验证正确的关键点（通过项）

- **跨局重置**：`start_new_run` 重置 `refine_essence=0` / `refine_ii_count=0` / `refine_tiers.clear()` → 无跨局残留。
- **倍率乘区**：`weapon_base.get_leveled_damage` 与进化乘区**分离、可叠加**；`get_refine_multiplier` 累积 I×II，`tier<=0` 返回 `1.0`（安全兜底）。
- **II 全局上限**：仅在 `target==2` 时校验 `refine_ii_count >= MAX_REFINE_II` 且**仅在此处 `+1`**，每把 II 武器恰好 +1 次，无重复计数、封顶正确。
- **不可撤销**：`cur>=2` 直接返回 0，无 III（`MAX_REFINE_III=0`）。
- **掉落规则**：Boss `10:1 / 15:2 / 20:3`（字符串/整型 key 双兼容）；精英 `≥12 夜 + 30% + 每夜上限 1`；`essence_cap` 截断生效。
- **配置驱动**：`refine_paths.json` 只读；加 8 路径红线校验（`push_warning`）。
- **历史坑已修复**：autoload 不再定义与 `Node` 原生同名方法（`get_path`→`evolution_path`/`refine_path`），规避此前 autoload 变 `Nil` 的崩溃。
- **接入正确**：`enemy_spawner` 击杀接入掉落；`shop_ui` 镜像进化入口渲染精炼按钮并受 night/essence 门控。
- **回归绿**：`w11_refine_test` 78/0；`w10_evolution_test` 79/0；`prototype_acceptance_test` 16/0。

---

## 三、发现的问题

### [中] 1. `set_refine_tier` 为公开方法，绕过 `refine_ii_count` 计数
`GameState.set_refine_tier` 只写 `refine_tiers`，不维护 `refine_ii_count`；II 计数的 `+1` 散落在 `RefineSystem.refine`（仅 `target==2`）。
当前只有 `RefineSystem` 调用 `set`，**无真实 bug**；但任何未来代码直接 `set_refine_tier(w, 2)` 会让「全局最多 2 把 II」的上限失效（计数不同步）。

> **建议**：把 `ii_count` 自增移入 `GameState.set_refine_tier`（依据 `tier` 参数），或改为私有 `_set_refine_tier` 仅 `RefineSystem` 可用，使计数与等级强绑定。

### [中] 2. `RefineSystem.essence_changed` 为死信号
`refine()` 末尾 `essence_changed.emit(0, total)`，但 UI 实际连的是 `GameState.refine_essence_changed`。该 autoload 信号既无连接方，语义也易混淆（`amount` 传 `0` 却表示「消耗后变化」）。当前两套信号重复 emit，属冗余。

> **建议**：删除该信号，或令其携带真实 delta（如 `-cost`）并让 `shop_ui` 改用之。

### [中 / 已知延后] 3. 存档不持久化精炼进度
`SaveSystem` 为 W1 骨架，仅存解锁/设置，**不持久化任何局内状态**（`weapon_levels`/`weapon_slots`/`refine_tiers` 均无）。精炼进度在 W16 存档落地前不会丢（整局当前不存），但 W16 实现存档时**必须**一并序列化 `refine_tiers + refine_essence + refine_ii_count`，否则读档后精炼回退。

> **建议**：在 W16 任务卡登记「精炼状态需随局内存档读写」，与进化/武器等级同批处理。

### [低] 4. `consume_refine_essence(0)` 返回 `true`
`amount<=0` 直接 `return true`，语义上「消耗 0 视为成功」。安全（`RefineSystem` 不会传 0），但建议在注释明确，避免被误用为「未校验余额即放行」。

### [低] 5. `grant_essence` 触顶时精英掉落静默丢失
`try_elite_drop` 在 `refine_essence` 已达 `essence_cap` 时 `grant_essence(1)` 返回 0，`_elite_drops_this_night` 不 `+1`，掉落被吞且无反馈。符合设计（精华有上限），但玩家满精华时击杀精英无任何提示，体验上可加 toast（可选）。

### [低] 6. `next_refine_tier` 多次调用 `get_rules()`
单函数内 `get_rules()` 被调用 3 次（取 `unlock_night` / `require_evolved` / `cost`）。规模小（8 武器）可忽略；要抠性能可缓存到局部变量。

### [低] 7. 测试未覆盖 `shop_ui` 按钮交互（4.2.8 已如实标「待验收」）
`w11_refine_test` 只验逻辑；`refine()→set_refine_tier→ii_count` 路径经 `RefineSystem.refine` 验证（充分），但 UI 点击、标签刷新、门控渲染需人工试玩。已如实标注，非遗漏。

---

## 四、设计一致性核对

- `require_evolved=false`（精炼不强制先进化）与设计 §6.6 决策一致，且为配置开关，未来可切。✅
- MVP 约束「最多 2 II、无 III」由 `MAX_REFINE_II=2` + `MAX_REFINE_III=0` + `next_refine_tier` 门控三位一体保证。✅
- 伤害仅加伤害、不加 HP/EXP，符合 §6.6 红线。✅

---

## 五、建议处理顺序

1. **[中] 落地 #1**：把 `ii_count` 自增移入 `GameState.set_refine_tier` —— 防回归，低成本，建议本次一并改。
2. **[中] 清理 #2**：删除/接管冗余 `RefineSystem.essence_changed` 信号。
3. **[中/延后] 登记 #3**：W16 任务卡补「精炼状态随存档读写」。
4. **[低] #4–#7**：可延后或随相关功能顺手处理。

---

## 七、修复记录（2026-08-17）

用户确认后已修复 #1、#2：

- **#1 已修复**：`GameState.set_refine_tier` 现自行维护 `refine_ii_count`（依据旧/新阶：跨过 II 门槛 +1，离开 -1），II 全局计数与精炼等级强绑定；`RefineSystem.refine` 内重复的 `refine_ii_count += 1` 已删除。任何直接调用 `set_refine_tier` 不再能绕过上限。
- **#2 已修复**：`RefineSystem.essence_changed` 信号及其在 `refine()` / `grant_essence()` 的两处 emit 已删除（全局无连接，UI 只连 `GameState.refine_essence_changed`）。`refined` 信号保留为合法公开事件钩子。

**验证**：`w11_refine_test` 78/0、`w10_evolution_test` 79/0 仍全绿；`refine_system.gd` 无 `essence_changed` 残留引用。

**未改项（当时）**：#3（W16 存档登记）、#4–#7（低优先级）。

### 二次修复（同日，对齐正式 review P1/P2）

- `require_evolved=true`（对齐 §6.6）；`next_refine_tier` 默认亦为 true
- UI：按钮展示本阶/累积 `dps_mult`，不再展示行为 desc；「粹炼」→「淬炼」
- 删除死信号 `refine_done`；`set_refine_tier` `clampi(0,2)`；`start_new_run` 发 `refine_essence_changed`
- `w11_refine_test` 增补须进化 / tier clamp 用例

---

## 六、结论

W11 精炼系统实现正确、测试充分、与进化系统形成清晰对称的独立养成轴（须先进化）。**无阻断性 Bug**。
