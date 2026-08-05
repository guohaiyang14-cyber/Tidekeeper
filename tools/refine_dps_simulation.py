"""
精炼 III 级 DPS 模拟脚本
用途：验证精炼 III 级的 DPS 倍率是否满足 ≤3.5× 约束；锚压按「施加持续 × 覆盖率」估算
用法：python refine_dps_simulation.py
输出：控制台打印详细分析报告

注意：dps_mult 来自 config/refine_data.py 估算系数，非主文档明文；Boss 血量对齐主文档 §9.4。
"""

import os
import sys
from typing import Dict, List, Tuple, Any

# 确保能从仓库根导入 config 包（脚本位于 tools/，需回退一级）
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.refine_data import REFINE_PATHS

# ============================================================
# 基础参数设定（对齐主文档 §9.4 / 附录 B.10）
# ============================================================

BASE_DPS = 100  # 假设进化后单目标 DPS=100（相对比较用）

# 主文档 §9.4 第 20 夜 Boss 底数（多阶段分池；此处用总额作相对分析）
BOSS_HP = 7000

BOSS_FIGHT_DURATION = 120  # 第 20 夜时长（秒）

# 星海锚坠精炼后 CD（附录 B.10 精炼 I：2.5s）；锚压每次持续 3s
ANCHOR_PRESS_CD = 2.5
ANCHOR_PRESS_DURATION = 3.0


def calculate_refine_dps(base_dps: float, refine_data: Dict[str, Any]) -> Tuple[float, float]:
    dps_mult = (
        refine_data["refine_I"]["dps_mult"]
        * refine_data["refine_II"]["dps_mult"]
        * refine_data["refine_III"]["dps_mult"]
    )
    return base_dps * dps_mult, dps_mult


def anchor_press_uptime(cd: float = ANCHOR_PRESS_CD, duration: float = ANCHOR_PRESS_DURATION) -> float:
    """单次施加持续 duration，CD=cd → 稳态覆盖率 cap 于 1.0。"""
    if cd <= 0:
        return 1.0
    return min(1.0, duration / cd)


def calculate_boss_damage_with_percent(
    base_dps: float,
    boss_hp: int,
    percent_damage_per_sec: float,
    duration: int,
    uptime: float,
) -> Tuple[float, float, float]:
    """
    百分比伤害 = boss_hp × %/秒 × 战斗时长 × 覆盖率
    （覆盖率由 CD 与单次持续决定，禁止按 120s 满覆盖硬算）
    """
    base_damage = base_dps * duration
    percent_damage = boss_hp * percent_damage_per_sec * duration * uptime
    total_damage = base_damage + percent_damage
    return total_damage, total_damage / duration, percent_damage


def simulate_all_paths() -> List[Dict[str, Any]]:
    print("=" * 80)
    print("精炼 III 级 DPS 模拟报告")
    print("=" * 80)
    print()
    print("基准参数：")
    print(f"  - 进化后武器基准 DPS: {BASE_DPS}（相对）")
    print(f"  - Boss 血量（§9.4 吞噬之星）: {BOSS_HP:,}")
    print(f"  - Boss 战时长: {BOSS_FIGHT_DURATION} 秒")
    print(f"  - 约束：精炼 III DPS 倍率 ≤ 3.5×（相对进化后）")
    uptime = anchor_press_uptime()
    print(
        f"  - 锚压覆盖率: {uptime:.0%} "
        f"（持续 {ANCHOR_PRESS_DURATION}s / CD {ANCHOR_PRESS_CD}s）"
    )
    print()
    print("=" * 80)
    print()

    results = []

    for path_id, refine_data in REFINE_PATHS.items():
        final_dps, dps_mult = calculate_refine_dps(BASE_DPS, refine_data)

        if refine_data.get("has_percent_damage", False):
            percent_per_sec = refine_data.get("percent_damage_per_sec", 0.01)
            total_damage, avg_dps, percent_damage = calculate_boss_damage_with_percent(
                final_dps, BOSS_HP, percent_per_sec, BOSS_FIGHT_DURATION, uptime
            )
        else:
            total_damage = final_dps * BOSS_FIGHT_DURATION
            avg_dps = final_dps
            percent_damage = 0.0

        results.append({
            "id": path_id,
            "name": refine_data["name"],
            "type": refine_data["type"],
            "dps_mult": dps_mult,
            "final_dps": final_dps,
            "total_damage": total_damage,
            "avg_dps": avg_dps,
            "percent_damage": percent_damage,
            "constraint_met": dps_mult <= 3.5,
        })

    print("【精炼 III 级 DPS 倍率结果】")
    print()
    print("| # | 路径名 | 类型 | DPS 倍率 | 约束检查 |")
    print("|---|--------|------|---------|---------|")
    for r in results:
        status = "[OK]" if r["constraint_met"] else "[FAIL]"
        print(f"| {r['id']} | {r['name'][:18]} | {r['type']} | {r['dps_mult']:.2f}x | {status} |")

    print()
    print("=" * 80)
    print()
    print("【Boss 战伤害分析（相对 §9.4 底数；单武器、无其他乘区）】")
    print()
    print("| # | 路径名 | 最终 DPS | 总伤害（120s） | Boss 血量占比 |")
    print("|---|--------|---------|---------------|--------------|")
    for r in results:
        hp_percent = (r["total_damage"] / BOSS_HP) * 100
        print(
            f"| {r['id']} | {r['name'][:18]} | {r['avg_dps']:.1f} | "
            f"{r['total_damage']:,.0f} | {hp_percent:.1f}% |"
        )

    print()
    print("=" * 80)
    print()

    violations = [r for r in results if not r["constraint_met"]]
    if violations:
        print("[WARN] constraint violations:")
        for v in violations:
            print(f"  [FAIL] #{v['id']} {v['name']}: {v['dps_mult']:.2f}x > 3.5x")
    else:
        print("[OK] all 10 paths dps_mult <= 3.5x (refine_data estimates)")

    print()
    print("=" * 80)
    print()
    print("[NOTE]")
    print("- BASE_DPS=100 is relative; absolute Boss% is not acceptance criteria.")
    print("- Acceptance focus: dps_mult <= 3.5x.")
    print()

    results_by_id = {r["id"]: r for r in results}
    r10 = results_by_id[10]
    pct_of_boss = r10["percent_damage"] / BOSS_HP * 100
    print(f"#{r10['id']} {r10['name']} (anchor press)")
    print(f"  - flat DPS part: {r10['final_dps']:.1f}")
    print(
        f"  - percent part: {r10['percent_damage']:,.0f} "
        f"({pct_of_boss:.1f}% Boss HP; uptime {uptime:.0%})"
    )
    print(
        f"  - formula: 1%/s * fight_s * uptime "
        f"(uptime=min(1, {ANCHOR_PRESS_DURATION}/{ANCHOR_PRESS_CD}))"
    )
    print()

    r9 = results_by_id[9]
    print(f"#{r9['id']} {r9['name']}")
    print(f"  - dps_mult only {r9['dps_mult']:.2f}x (control kit)")
    print()
    print("=" * 80)
    return results


if __name__ == "__main__":
    simulate_all_paths()
