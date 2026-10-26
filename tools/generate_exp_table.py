"""
经验表生成脚本
用途：生成预生成经验表 config/exp_table.json
用法：python generate_exp_table.py
输出：控制台打印经验表 + 生成 config/exp_table.json（配置表目录）

说明：表内默认生成至 30 级。运行时 ExpTable：人物无硬顶；n ≥ 30 时 E(n)=E(30)（GDD §6.2）。
红线：经验表必须由本脚本生成，禁止手改单行

两种模型：
1. night_targets（默认，2026-10-26 起）：按「每夜经验收入估计 + 每夜结束目标等级」反推每级所需经验
2. formula（历史模型）：E(n) = floor(BASE × RATIO^(n-1) + LINEAR×(n-1))
"""

import json
import math
import os
from typing import Dict, Any, List, Tuple

# ============================================================================
# 模型一：夜间目标等级（默认）
# ============================================================================
# 2026-10-26 用户反馈「等级提升的快了，前面6级一夜两级即可，后面一夜一级然后递减」：
# 实测（真人 1 局，run s933110520）第 4 夜已 Lv11（累计 1123 经验），节奏过快。
# 改为按「每夜目标等级」反推曲线：前 3 夜各升 2 级（Lv3/5/7），之后每夜 1 级，
# 第 15 夜起递减到约 0.5 级/夜（Lv21 封在第 20 夜）。
#
# INCOME_PER_NIGHT：每夜经验收入估计（来源：CombatLog 实测 + 后续按刷怪量外推）
# TARGET_LEVEL_BY_NIGHT：该夜结束时的目标等级
INCOME_PER_NIGHT: List[int] = [
    35, 70, 390, 660, 1000, 1450, 2000, 2700, 3500, 4500,
    5700, 7200, 9000, 11000, 13500, 16500, 20000, 24000, 29000, 35000,
]
TARGET_LEVEL_BY_NIGHT: List[int] = [
    3, 5, 7, 8, 9, 10, 11, 12, 13, 14,
    15, 16, 17, 18, 18, 19, 19, 20, 20, 21,
]
# 超出末夜目标等级后的每级增长倍率（保证表仍到 30 级且单调递增）
TAIL_GROWTH: float = 1.45

# ============================================================================
# 模型二：公式（历史模型，保留可切换）
# ============================================================================
# 2026-10-23 用户反馈「成长太快，10 夜左右所有武器 7 级、被动 5 级」：
# 实测一局 11 夜到 Lv27（累计 3064 经验 @ 第 10 夜），曲线过平。
# 保持曲线形状不变（同样的相对节奏），整体上抬约 1.9x：BASE 22 → 42，LINEAR 3 → 6
BASE: int = 42
RATIO: float = 1.11
LINEAR: int = 6

MODEL: str = "night_targets"

# 2026-10-26 code-review 修：FORMULA 原先硬编码成 night_targets 的说明，且总是写进
# metadata —— 切到 MODEL="formula" 时会生成「模型是 formula、公式却写着 night_targets」
# 的自相矛盾元数据。改为按 MODEL 取对应公式，单一数据源。
FORMULA_BY_MODEL: Dict[str, str] = {
    "night_targets": "night_targets: 每夜收入 %s × 目标等级 %s" % (
        "[" + ",".join(str(v) for v in INCOME_PER_NIGHT[:3]) + ",...]",
        "[" + ",".join(str(v) for v in TARGET_LEVEL_BY_NIGHT[:3]) + ",...]",
    ),
    "formula": "E(n) = floor(%d × %.2f^(n-1) + %d × (n-1))" % (BASE, RATIO, LINEAR),
}


def current_formula() -> str:
    """当前 MODEL 对应的公式说明（写进 metadata.formula）"""
    return FORMULA_BY_MODEL.get(MODEL, MODEL)


def model_params() -> Dict[str, Any]:
    """当前 MODEL 的入参快照（写进 metadata.params，便于回溯「这表是怎么来的」）"""
    if MODEL == "formula":
        return {"base": BASE, "ratio": RATIO, "linear": LINEAR}
    return {
        "income_per_night": list(INCOME_PER_NIGHT),
        "target_level_by_night": list(TARGET_LEVEL_BY_NIGHT),
        "tail_growth": TAIL_GROWTH,
    }


def _cumulative_income() -> List[int]:
    out: List[int] = []
    total: int = 0
    for v in INCOME_PER_NIGHT:
        total += int(v)
        out.append(total)
    return out


def _anchor_points() -> List[Tuple[int, int]]:
    """(累计经验, 该点等级)：起点 (0, 1) + 每夜结束点；目标等级强制非降"""
    cum = _cumulative_income()
    pts: List[Tuple[int, int]] = [(0, 1)]
    for i, c in enumerate(cum):
        lv = int(TARGET_LEVEL_BY_NIGHT[i]) if i < len(TARGET_LEVEL_BY_NIGHT) else pts[-1][1]
        if lv < pts[-1][1]:
            lv = pts[-1][1]
        pts.append((c, lv))
    return pts


def _cum_for_level(pts: List[Tuple[int, int]], level: int) -> int:
    """反查「达到 level 级所需累计经验」；段内线性插值，超出末点返回 -1"""
    for i in range(len(pts) - 1):
        c0, l0 = pts[i]
        c1, l1 = pts[i + 1]
        if l0 <= level <= l1 and l1 > l0:
            frac = float(level - l0) / float(l1 - l0)
            return int(round(c0 + (c1 - c0) * frac))
    return -1


def generate_by_night_targets(max_level: int = 30) -> Dict[int, Dict[str, int]]:
    pts = _anchor_points()
    top_level: int = pts[-1][1]
    cum_by_level: Dict[int, int] = {1: 0}
    for lv in range(2, top_level + 1):
        c = _cum_for_level(pts, lv)
        if c >= 0:
            cum_by_level[lv] = c
    # 逐级所需经验：锚点范围内按累计经验差分；超出范围记 0（末段另行补齐）
    exp_by_level: Dict[int, int] = {}
    for lv in range(1, max_level + 1):
        if lv + 1 in cum_by_level:
            e = cum_by_level[lv + 1] - cum_by_level.get(lv, 0)
        else:
            e = 0
        exp_by_level[lv] = max(1, e) if e > 0 else 0
    # 注：插值取整可能在最初几级造成 1~2 点轻微回落（如 18→17），不做事后平滑——
    # 平滑会抬高累计值，导致夜间目标整体错位一级（实测 495→496 就掉一级）
    # 末段（超出锚点等级）按几何增长补齐
    anchored_max = max([lv for lv, e in exp_by_level.items() if e > 0] or [1])
    prev_exp = exp_by_level[anchored_max]
    for lv in range(anchored_max + 1, max_level + 1):
        prev_exp = max(prev_exp + 1, int(round(prev_exp * TAIL_GROWTH)))
        exp_by_level[lv] = prev_exp
    table: Dict[int, Dict[str, int]] = {}
    cumulative: int = 0
    for n in range(1, max_level + 1):
        cumulative += exp_by_level[n]
        table[n] = {
            "level": n,
            "exp_required": exp_by_level[n],
            "cumulative_exp": cumulative,
        }
    return table


def generate_exp_table(max_level: int = 30) -> Dict[int, Dict[str, int]]:
    """公式模型：E(n) = floor(BASE × RATIO^(n-1) + LINEAR×(n-1))"""
    exp_table: Dict[int, Dict[str, int]] = {}
    cumulative: int = 0
    for n in range(1, max_level + 1):
        exp = int(math.floor(BASE * (RATIO ** (n - 1)) + LINEAR * (n - 1)))
        cumulative += exp
        exp_table[n] = {
            "level": n,
            "exp_required": exp,
            "cumulative_exp": cumulative,
        }
    return exp_table


def main() -> None:
    print("=" * 60)
    print("经验表生成器")
    print("模型: " + MODEL)
    print("=" * 60)
    print()

    if MODEL == "night_targets":
        exp_table = generate_by_night_targets(30)
    else:
        exp_table = generate_exp_table(30)

    print(f"{'等级':>4} | {'本级所需经验':>12} | {'累计经验':>12}")
    print("-" * 40)
    for level in [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 25, 30]:
        if level in exp_table:
            d = exp_table[level]
            print(f"{level:>4} | {d['exp_required']:>12} | {d['cumulative_exp']:>12}")

    print()
    print("夜间目标核对（按 INCOME_PER_NIGHT 累计，看落到哪一级）：")
    cum_income = 0
    for i, inc in enumerate(INCOME_PER_NIGHT):
        cum_income += inc
        reached = 1
        for lv in range(1, 31):
            if exp_table[lv]["cumulative_exp"] <= cum_income:
                reached = lv + 1
        print("  第 %2d 夜：累计经验 %7d → 约 Lv%-2d（目标 Lv%d）" % (
            i + 1, cum_income, reached, TARGET_LEVEL_BY_NIGHT[i]))

    # 校验（与 validate_config_i18n.py 的口径一致）
    e1 = exp_table[1]["exp_required"]
    e10 = exp_table[10]["exp_required"]
    e20 = exp_table[20]["exp_required"]
    c20 = exp_table[20]["cumulative_exp"]
    c25 = exp_table[25]["cumulative_exp"]
    checks = [
        (len(exp_table) >= 30, "至少 30 级 (%d)" % len(exp_table)),
        (e1 > 0 and e10 > e1 and e20 > e10, "单调递增 E1=%d E10=%d E20=%d" % (e1, e10, e20)),
        (c20 >= 3200, "累计 Lv20 ≥3200 (%d)" % c20),
        (c25 >= 5500, "累计 Lv25 ≥5500 (%d)" % c25),
    ]
    print()
    all_pass = True
    for ok_flag, desc in checks:
        print("  %s %s" % ("[OK]" if ok_flag else "[FAIL]", desc))
        if not ok_flag:
            all_pass = False

    output = {
        "metadata": {
            # formula / params 都按当前 MODEL 生成，避免切模型后元数据自相矛盾
            "formula": current_formula(),
            "model": MODEL,
            "params": model_params(),
            "max_level": 30,
            "generated_by": "generate_exp_table.py",
            "note": "Do not edit by hand; regenerate via this script",
        },
        "levels": exp_table,
    }

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    config_dir = os.path.join(repo_root, "config")
    output_path = os.path.join(config_dir, "exp_table.json")
    os.makedirs(config_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print()
    print(f"Exported: {output_path}")
    print()
    print("[OK] all checks passed" if all_pass else "[WARN] some checks failed")


if __name__ == "__main__":
    main()
