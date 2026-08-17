# W13 商店完善 + 经济闭环（逻辑 + 机检）代码评审

> **评审对象**：W13 未提交改动（7 文件：3 新增 + 4 修改）
> **评审范围**：`game_state.gd`（remove_weapon / reroll_passive / reroll_weapon / _shop_paid_cost）、`rest_system.gd`（新增 autoload）、`project.godot`（注册）、`scenes/tests/w13_shop_test.tscn` + `.gd`（机检）、`docs/原型验证验收清单.md`（v2.3）、`docs/开发进度总览.md`
> **方法**：逐文件读 diff + 新增文件全读 + 全量机检回归
> **机检佐证**：`w13_shop_test` **25/0**；回归 `w12_passive_test` 57/0、`w11_refine_test` 86/0、`w10_evolution_test` 79/0（均 0 失败）
> **范围说明**：本回合用户选「逻辑 + 机检」，商店 UI 沿用 W4 `shop_ui` 未大改（清单 4.4.9「待验收」），故 UI 接线不在本次评审阻塞范围。

---

## 一、结论

**无阻断性 Bug，可进入下一原型周。** W13 逻辑正确、经济闭环无刷币（退款 13 < 原价 16）、重铸/休息接线清晰，autoload 命名与初始化顺序红线均遵守（延续 W11/W12 教训）。

发现 **6 项问题，全部为低优先级（信息级/打磨级）**，无 [高]/[中]。其中 #1–#2 为轻微代码整洁项，#3 为 UI 同步待办（与现有惯例一致），#4–#5 为设计/测试健壮性注记。

---

## 二、发现清单

### #1 [低] `_shop_paid_cost(kind, id)` 的 `id` 参数未使用

```gdscript
func _shop_paid_cost(kind: String, id: String) -> int:
	var meta: Dictionary = ConfigLoader.get_weapon_shop_meta() if kind == "weapon" else ConfigLoader.get_passive_shop_meta()
	base = int(meta.get("cost", ...))
	discount = float(meta.get("discount", 0.2))
	return maxi(1, roundi(float(base) * (1.0 - discount)))
```

`id` 形参未被读取——价格来自全局 shop metadata（所有武器同价、所有被动同价），与 `ShopManager._weapon_cost()/_passive_cost()` 行为一致（也是全局统一定价，不按 id 区分）。

- **影响**：死参数；调用方 `reroll_passive/reroll_weapon` 传入 id 但被忽略，略具误导性（看似按物品计价，实际按类计价）。
- **建议**：去掉 `id` 形参（`_shop_paid_cost(kind: String)`），或补注释「本作全局统一定价，不按 id 区分」。低优先级。

---

### #2 [低] 折扣公式两处重复（双源真相）

折扣价计算逻辑存在于两处：
- `ShopManager._discounted(base, discount)`（私有）：`maxi(1, roundi(base * (1 - discount)))`
- `GameState._shop_paid_cost`：`maxi(1, roundi(float(base) * (1.0 - discount)))`

两者公式相同但代码重复。若未来折扣规则变化（如改为向下取整、加最低价档），需同步两处，否则购买价与退款价会不一致。

- **建议**：将折扣公式收敛到单一来源——例如把 `ShopManager._discounted` 提升为公开静态/`ConfigLoader` 辅助（如 `ConfigLoader.discounted_price(base, discount)`），`GameState._shop_paid_cost` 复用之。低优先级（当前公式一致、测试已交叉验证）。

---

### #3 [低] `apply_rest` 改 `player_health` 不发信号（UI 同步待办）

`rest_system.gd::apply_rest()`：

```gdscript
func apply_rest() -> int:
	var before: int = GameState.player_health
	GameState.player_health = GameState.player_max_health
	return GameState.player_max_health - before
```

直接写 `GameState.player_health`，**未 emit 任何信号**。`GameState` 当前只有 `player_damaged` 信号（伤害时发），**无 `player_health_changed`**。故休息回血后，HUD 血条不会自动刷新（除非在抉择之昼进入时整体重绘）。

- **影响**：当前 UI 沿用 W4 雏形且本回合未做大改（4.4.9 待验收），影响有限；但 W18 做 HUD 完整化时需处理。
- **说明**：此行为与现有惯例一致——`start_new_run`（line 98）也直接赋值 `player_health = player_max_health` 不发信号，运行开始整体刷新。故非新引入的缺陷，而是既有约定。
- **建议**：W18 接 HUD 时，让 DayPhase 在 `apply_rest` 后主动刷新血条显示（轮询或新增 `player_health_changed` 信号）。本回合不阻塞。

---

### #4 [低] 退款忽略武器等级 / 全局统一定价（设计选择，MVP 可预测）

`reroll_weapon` 退 `roundi(paid * 0.8)`，其中 `paid` 来自全局 shop metadata 的基础价（折扣后），**不随武器等级浮动**。本作武器升级（`add_weapon` 对已持有者）为免费，故「升到 7 级的武器」与「1 级武器」退款相同——逻辑自洽（玩家未为等级额外付费）。

- **影响**：无 Bug；属 MVP 简化口径。若未来升级改为付费，则退款需按累计付费重算。
- **建议**：在 `reroll_*` 注释或设计文档注明「MVP 退款 = 基础价 ×80%，不随等级」。低优先级。

---

### #5 [低] 测试 `_test_buy_deducts` 依赖洗牌产出被动项

```gdscript
shop.open_shop()
var items: Array = shop.get_current_items()
var item: Dictionary = {}
for it in items:
	if it["kind"] == "passive":
		item = it
		break
_assert(not item.is_empty(), "商店含被动项")
```

该用例依赖 `ShopManager._build_items()` 的 RNG 洗牌在 6 件在售中包含至少 1 个被动（12 被动 + 8 武器取 6，P(0 被动) ≈ 0.07%，极低）。当前固定种子 `20261313` 下确定性通过（25/0）；**若日后改种子导致该次洗牌无被动，用例会 early-return 而不断言购买扣费**，弱化为「空过」。

- **建议**：改为直接 `shop.buy({"id": <某被动>, "kind": "passive", "cost": _paid("passive")})` 强制构造，避免依赖洗牌结果。低优先级（当前稳定通过）。

---

### #6 [信息/良好] 状态与红线均正确

- `remove_weapon` 正确清除 `evolved_weapons`（卸下进化武器时同步取消进化标记），与 `is_weapon_evolved` 真源一致。
- `reroll_passive/reroll_weapon` 对未持有项返回 0 且不退款、不崩溃；先查持有再 remove+add_tidecoins，顺序安全。
- `project.godot`：`RestSystem` 注册于 `PassiveSystem` 之后、`SaveSystem` 之前，顺序合理；`RestSystem._ready` 仅打印，无启动期反向调用其他 autoload（apply_rest 仅在玩法期调用），无 W11 `get_path` 式崩溃风险。
- `RestSystem` 无状态，只读/写 `GameState.player_health`，符合红线。
- 经济闭环：`refund(13) < paid(16)` 经 `_test_economy_no_exploit` 验证，无无限刷币。

---

## 三、修复建议汇总

| # | 严重度 | 描述 | 建议动作 | 是否阻塞 |
|---|--------|------|---------|---------|
| 1 | 低 | `_shop_paid_cost` 的 `id` 形参未使用 | 去掉形参或补注释 | 否 |
| 2 | 低 | 折扣公式 ShopManager/GameState 双源 | 收敛到 ConfigLoader 辅助（可选） | 否 |
| 3 | 低 | `apply_rest` 无 health 信号（与 start_new_run 同惯例） | W18 接 HUD 时刷新血条 | 否 |
| 4 | 低 | 退款忽略等级/全局定价 | 注释注明 MVP 口径 | 否 |
| 5 | 低 | 测试依赖洗牌出被动项 | 改构造 item 强制触发 | 否 |
| 6 | 信息 | 状态/红线正确 | 良好，无需动作 | 否 |

**结论**：0 高/中，6 低/信息；无阻断项。可直接进入下一原型周（W14 事件卡），或顺手修 #1（去死参数，最小成本）。

---

## 五、审查修复记录（2026-08-17，用户「修复」）

针对二次审查（精炼残留 / 硬编码 / 局内接线）及上表 P2：

| 项 | 动作 |
|---|---|
| 精炼残留 | `remove_weapon` 同步 `refine_tiers.erase` |
| 退款/休息硬编码 | `refund_ratio`、`rest_interval_nights` 入 config |
| 局内接线 | World 进昼 `try_apply_rest_for_night`；ShopUI 重铸按钮；`loadout_changed` |
| 折扣双源 / 死参 | `ConfigLoader.get_shop_paid_cost`；删除 `_shop_paid_cost` |
| 回血信号 | `GameState.heal_player_to_full` + `player_health_changed` |

验证：`w13_shop_test` **32/0**。

---

## 四、评审流程记录

- 评审时间：2026-08-17
- 评审人：AI（WorkBuddy）
- 配套机检：`w13_shop_test`（25/0）、回归 `w12_passive_test`（57/0）、`w11_refine_test`（86/0）、`w10_evolution_test`（79/0）
- 提交状态：W13 改动尚未 commit（用户「继续开发」启动，未要求提交）
