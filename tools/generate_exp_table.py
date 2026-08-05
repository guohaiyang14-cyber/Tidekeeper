"""
经验表生成脚本
用途：根据设计文档公式 E(n) = floor(22 × 1.11^(n-1) + 3×(n-1)) 生成 30 级经验表
用法：python generate_exp_table.py
输出：控制台打印经验表 + 生成 config/exp_table.json（配置表目录）

红线：经验表必须由本脚本生成，禁止手改单行
"""

import json
import math
import os
from typing import Dict, Any, List, Tuple


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
        # E(n) = floor(22 × 1.11^(n-1) + 3×(n-1))
        if n == 1:
            exp = 22
        else:
            exp = int(math.floor(22 * (1.11 ** (n - 1)) + 3 * (n - 1)))
        
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
    print("公式: E(n) = floor(22 × 1.11^(n-1) + 3×(n-1))")
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
    print(f"  第 1 级: {exp_table[1]['exp_required']} (预期 22)")
    print(f"  第 10 级: {exp_table[10]['exp_required']} (预期 83)")
    print(f"  第 20 级: {exp_table[20]['exp_required']} (预期 216)")
    print(f"  第 30 级: {exp_table[30]['exp_required']} (预期 540)")
    
    # 校验
    checks = [
        (1, 22),
        (10, 83),
        (20, 216),
        (30, 540),
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
            "formula": "E(n) = floor(22 * 1.11^(n-1) + 3*(n-1))",
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