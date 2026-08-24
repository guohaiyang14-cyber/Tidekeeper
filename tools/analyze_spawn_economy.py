# ============================================================================
# analyze_spawn_economy.py — 刷怪频率改动后的经验/货币成长曲线核对
# 复刻 enemy_spawner.gd 的真实刷怪公式（_compute_count / _current_interval /
# 旧行为「预算耗尽即停刷」 vs 新行为「维持 min_active 直到夜晚结束」），
# 模拟不同击杀速率 K（敌/秒）下每夜击杀数 → 经验/货币收入 → 累计等级，
# 对照设计目标（文档 §6.2：第10夜≈15级，第20夜≈26~30级）。
#
# 三种行为对照：
#   old     —— 原「每夜硬经验预算」：预算耗尽即停刷（所有掉落=预算敌）
#   new     —— 维持 min_active 直到夜尽，但 floor 补刷敌也给满掉落 → 强玩家超供爆级
#   new_cap —— 维持 min_active 但 floor 补刷敌掉落归零（经济与手感解耦，本环境落地方案）
#
# 纯 stdlib，读取 config/*.json，不依赖 Godot。
# 运行：python tools/analyze_spawn_economy.py
# ============================================================================
import json
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return json.load(f)


enemies = load("config/enemies.json")
diff = load("config/difficulty.json")
bosses = load("config/bosses.json")
exp_tbl = load("config/exp_table.json")

spawn = enemies["metadata"]["spawn"]
BASE_COUNT = spawn["base_count"]          # 10
PER_NIGHT = spawn["per_night"]            # 3
SPARSE = spawn["sparse_seconds"]          # 12
I_START = spawn["interval_start"]         # 2.0
I_DENSE = spawn["interval_dense"]         # 0.8
I_PRESS = spawn["interval_pressure"]      # 0.4
MIN_ACTIVE = spawn["min_active"]          # 8
MAX_ENEMIES = diff["max_enemies"]         # 350
COUNT_MULT = 1.0                          # 灯塔档位 enemy_count_multiplier

ed = enemies["enemies"]
# 每夜可刷敌人 base_exp 列表（均匀抽样，与 spawner._pick_enemy_def 一致）
eligible_base = {}
for n in range(1, 21):
    lst = [int(d.get("base_exp", 0)) for d in ed.values()
           if int(d.get("spawn_night", 99)) <= n]
    eligible_base[n] = lst

boss_by_night = {int(b["night"]): b for b in bosses["bosses"].values()}


def night_duration(n):
    if n == 20:
        return 120.0
    if n in (10, 15):
        return 90.0
    if n == 5:
        return 60.0
    return 45.0


def compute_count(n):
    c = BASE_COUNT + PER_NIGHT * (n - 1)
    c = int(round(c * COUNT_MULT))
    return min(c, MAX_ENEMIES)


def interval(elapsed, dur):
    if elapsed < SPARSE:
        return I_START
    if elapsed < dur * 0.6:
        return I_DENSE
    return I_PRESS


def level_from_cum(cum):
    lv = 1
    for k in range(1, 31):
        if exp_tbl["levels"][str(k)]["cumulative_exp"] <= cum:
            lv = k
        else:
            break
    return lv


def simulate(night, K, behavior):
    """返回 (exp, coin)。

    behavior ∈ {"old", "new", "new_cap"}：
      old     —— 预算耗尽即停刷（所有掉落=预算敌；原曲线调校基准）
      new     —— 维持 min_active 直到夜尽，floor 补刷敌也给满掉落（超供）
      new_cap —— 维持 min_active 但 floor 补刷敌掉落归零（经济与手感解耦）

    active 维护「每只活跃敌的掉落经验值」列表：
      - 预算敌：从本夜 eligible base_exp 抽取（>0）
      - 精英/天灾 Boss：固定值（>0，不随夜缩放）
      - floor 补刷敌：new 给满掉落（>0）；new_cap 归零（=0）
    击杀时按 FIFO 弹出并计入掉落；floor(=0) 不计入经验也不计入潮币。
    """
    dur = night_duration(night)
    budget = compute_count(night)
    remaining = budget
    active = []                 # 每只活跃敌的掉落经验值（floor 补刷在 new_cap 中为 0）
    elapsed = 0.0
    spawn_timer = 0.0
    spawning = True             # 仅控制「是否继续刷怪」；夜晚始终跑满全程
    exp_total = 0
    coin_total = 0
    dt = 1.0 / 60.0
    rnd = random.Random(20260818 + night)
    ebase = eligible_base[night]

    # 精英夜（夜5 巨钳王，base_exp=5*3=15）+ 天灾夜 Boss（base_exp 见 bosses.json）
    # 作为预算敌（掉落按固定值，击杀时计入，不重复前置计入）
    if night == 5:
        active.append(15)
    b = boss_by_night.get(night)
    if b:
        active.append(int(b["base_exp"]))

    # 夜晚始终模拟到结束（真实游戏里 _spawning=false 只停刷怪，已在屏敌人仍会被击杀/掉落）
    while elapsed < dur:
        elapsed += dt
        # 击杀：本帧最多 K*dt 只（无论是否仍在刷怪，已屏敌人照常死亡）
        kills = K * dt
        ki = int(kills)
        if kills - ki >= rnd.random():
            ki += 1
        for _ in range(min(ki, len(active))):
            v = active.pop(0)
            if v > 0:                 # floor 补刷敌(v=0) 经验/潮币均归零
                exp_total += v
                coin_total += max(1, round(v))
        # 刷怪（仅 spawning 时）
        spawn_timer -= dt
        if spawn_timer <= 0.0:
            if spawning and len(active) < MAX_ENEMIES:
                if behavior == "old":
                    if remaining > 0:
                        remaining -= 1
                        active.append(ebase[rnd.randrange(len(ebase))])
                        spawn_timer = interval(elapsed, dur)
                    else:
                        spawning = False      # 预算耗尽即停刷（夜晚仍继续，已屏敌照杀）
                        spawn_timer = 0.1
                else:  # new / new_cap：维持 min_active 直到夜晚结束
                    if remaining > 0 or len(active) < MIN_ACTIVE:
                        if remaining > 0:
                            remaining -= 1
                            active.append(ebase[rnd.randrange(len(ebase))])
                        else:
                            # 预算耗尽后的密度 floor 补刷
                            active.append(ebase[rnd.randrange(len(ebase))] if behavior == "new" else 0)
                        spawn_timer = interval(elapsed, dur)
                    else:
                        spawn_timer = interval(elapsed, dur)
            else:
                spawn_timer = 0.1
    return exp_total, coin_total


def run(behavior, K):
    cum = 0
    rows = []
    for n in range(1, 21):
        e, c = simulate(n, K, behavior)
        cum += e
        rows.append((n, e, c, cum, level_from_cum(cum)))
    return rows


def _levels(rows):
    return {n: lv for (n, *_r, lv) in rows}


def _cum_n(rows, n):
    return [cum for (nn, _e, _c, cum, _lv) in rows if nn == n][0]


def main():
    print("=" * 100)
    print("刷怪经济 × 成长曲线核对（复刻 enemy_spawner 真实公式）")
    print("设计目标 §6.2：第10夜≈15级，第20夜≈26~30级（累计经验 1066 / 3778~5668）")
    print("=" * 100)
    print("夜晚 | 本夜预算敌 | 时长(s)")
    for n in range(1, 21):
        print("  N%-2d  count=%-3d  dur=%.0f" % (n, compute_count(n), night_duration(n)))

    ks = [0.5, 1.0, 2.0, 5.0, 50.0]
    print("\n--- 同击杀速率 K 下：old（预算封顶） / new（维持min_active, floor给满掉落） / new_cap（floor掉落归零=解耦） ---")
    print("%-22s %7s %7s %7s %7s   %12s" % (
        "场景", "N5级", "N10级", "N15级", "N20级", "N20累计EXP"))
    for K in ks:
        old = _levels(run("old", K))
        new = _levels(run("new", K))
        cap = _levels(run("new_cap", K))
        old_cum = _cum_n(run("old", K), 20)
        new_cum = _cum_n(run("new", K), 20)
        cap_cum = _cum_n(run("new_cap", K), 20)
        print("%-22s %7d %7d %7d %7d   %12d" % (
            "old  K=%.1f" % K, old[5], old[10], old[15], old[20], old_cum))
        print("%-22s %7d %7d %7d %7d   %12d" % (
            "new  K=%.1f" % K, new[5], new[10], new[15], new[20], new_cum))
        print("%-22s %7d %7d %7d %7d   %12d" % (
            "new_cap K=%.1f" % K, cap[5], cap[10], cap[15], cap[20], cap_cum))

    # 经济解耦校验：new_cap 必须与原 old 预算曲线重合（floor 掉落归零后，
    # 经济只来自预算敌，与「预算封顶」等价）
    print("\n" + "=" * 100)
    print("经济解耦校验：new_cap 应与原 old 预算曲线完全重合（floor 掉落归零）")
    print("=" * 100)
    all_ok = True
    for K in ks:
        old_cum = _cum_n(run("old", K), 20)
        cap_cum = _cum_n(run("new_cap", K), 20)
        ok = (old_cum == cap_cum)
        all_ok = all_ok and ok
        print("K=%.1f: old N20累计=%d  new_cap N20累计=%d  %s" % (
            K, old_cum, cap_cum, "✓ 重合（经济已解耦）" if ok else "✗ 偏离"))

    # 改动（未解耦）的额外供给：new 相对 old 的超供倍数
    print("\n" + "=" * 100)
    print("若不解耦（new）的额外供给（new - old，同 K）：经验增量 / 倍数")
    print("=" * 100)
    for K in ks:
        old_n10 = _cum_n(run("old", K), 10)
        new_n10 = _cum_n(run("new", K), 10)
        old_n20 = _cum_n(run("old", K), 20)
        new_n20 = _cum_n(run("new", K), 20)
        print("K=%.1f: N10 +%d (×%.2f)   N20 +%d (×%.2f)" % (
            K, new_n10 - old_n10, new_n10 / max(1, old_n10),
            new_n20 - old_n20, new_n20 / max(1, old_n20)))

    print("\n" + "=" * 100)
    print("结论：%s" % (
        "经济与手感已解耦 — 维持 min_active 密度修复（消除空窗）的同时，"
        "floor 补刷敌掉落归零使经济严格回到原预算曲线，强玩家不爆级、弱玩家仍达标。"
        if all_ok else
        "校验失败 — new_cap 与 old 未重合，需复查 floor 掉落归零逻辑。"))
    print("=" * 100)


if __name__ == "__main__":
    main()
