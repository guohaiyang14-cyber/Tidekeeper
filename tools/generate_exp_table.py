"""
经验表生成脚本
用途：根据公式 E(n) = floor(BASE × RATIO^(n-1) + LINEAR×(n-1)) 生成预生成经验表
用法：python generate_exp_table.py
输出：控制台打印经验表 + 生成 config/exp_table.json（配置表目录）

说明：表内默认生成至 30 级。运行时 ExpTable：人物无硬顶；n ≥ 30 时 E(n)=E(30)（GDD §6.2）。
红线：经验表必须由本脚本生成，禁止手改单行
"""

import json
import math
import os
from typing import Dict, Any, List, Tuple

# ---- 曲线参数（唯一调参入口）----
# 2026-10-23 用户反馈「成长太快，10 夜左右所有武器 7 级、被动 5 级」：
# 实测一局 11 夜到 Lv27（累计 3064 经验 @ 第 10 夜），曲线过平。
# 保持曲线形状不变（同样的相对节奏），整体上抬约 1.9x：
#   BASE 22 → 42，LINEAR 3 → 6
# 结果：第 10 夜 ≈ Lv18（原 Lv24），第 20 夜 ≈ Lv25（原封顶 Lv30）。
BASE: int = 42
RATIO: float = 1.11
LINEAR: int = 6
FORMULA: str = "E(n) = floor(%d * %s^(n-1) + %d*(n-1))" % (BASE, RATIO, LINEAR)


def generate_exp_table(max_level: int = 30) -> Dict[int, Dict[str, int]]:
    """
    生成经验表
    
    参数：
    - max_level: 最大等级（默认 30）
    
    返回：
    - exp_table: dict，键为等级、值为所需经验
    """
    exp_table: Dict[int, Dict[str, int]] = {}
    cumulative: int = 0
    
    for n in range(1, max_level + 1):
        # E(n) = floor(BASE × RATIO^(n-1) + LINEAR×(n-1))
        exp = int(math.floor(BASE * (RATIO ** (n - 1)) + LINEAR * (n - 1)))
        
        cumulative += exp
        exp_table[n] = {
            "level": n,
            "exp_required": exp,
            "cumulative_exp": cumulative
        }
    
    return exp_table


def main() -> None:
    print("=" * 60)
    print("经验表生成器")
    print("公式: " + FORMULA)
    print("=" * 60)
    print()
    
    exp_table = generate_exp_table(30)
    
    # 打印表格
    print(f"{'等级':>4} | {'本级所需经验':>12} | {'累计经验':>12}")
    print("-" * 40)
    
    for level in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 20, 26, 30]:
        if level in exp_table:
            data = exp_table[level]
            print(f"{level:>4} | {data['exp_required']:>12} | {data['cumulative_exp']:>12}")
    
    print()
    print("关键校验：")
    for lv in (1, 10, 20, 30):
        print(f"  第 {lv} 级: {exp_table[lv]['exp_required']} (累计 {exp_table[lv]['cumulative_exp']})")
    
    # 校验
    checks = [
        (1, BASE),
        (10, int(math.floor(BASE * (RATIO ** 9) + LINEAR * 9))),
        (20, int(math.floor(BASE * (RATIO ** 19) + LINEAR * 19))),
        (30, int(math.floor(BASE * (RATIO ** 29) + LINEAR * 29))),
    ]
    
    all_pass = True
    for level, expected in checks:
        actual = exp_table[level]['exp_required']
        status = "[OK]" if actual == expected else "[FAIL]"
        if actual != expected:
            all_pass = False
        print(f"  {status} Lv {level}: {actual} (expected {expected})")
    
    # 导出 JSON
    output = {
        "metadata": {
            "formula": FORMULA,
            "max_level": 30,
            "generated_by": "generate_exp_table.py",
            "note": "Do not edit by hand; regenerate via this script"
        },
        "levels": exp_table
    }
    
    # 导出 JSON（输出到 config/ 配置表目录，作为数据驱动的一部分）
    script_dir = os.path.dirname(os.path.abspath(__file__))  # tools/
    repo_root = os.path.dirname(script_dir)  # 仓库根
    config_dir = os.path.join(repo_root, "config")
    output_path = os.path.join(config_dir, "exp_table.json")
    os.makedirs(config_dir, exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    
    print()
    print(f"Exported: {output_path}")
    
    if all_pass:
        print()
        print("[OK] all checks passed")
    else:
        print()
        print("[WARN] some checks failed — verify formula params")


if __name__ == "__main__":
    main()