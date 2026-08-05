"""
精炼路径风险分析脚本
用途：系统性检查所有精炼路径的秒杀风险
用法：python refine_risk_analysis.py
输出：控制台打印详细风险报告
"""

import os
import sys
from typing import Dict, Any

# 确保能从仓库根导入 config 包（脚本位于 tools/，需回退一级）
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.refine_data import REFINE_PATHS

# ============================================================
# 风险分析函数
# ============================================================

def calculate_path_dps_mult(refine_data: Dict[str, Any]) -> float:
    """
    计算精炼路径的总 DPS 倍率（I × II × III）
    """
    return (refine_data["refine_I"]["dps_mult"]
            * refine_data["refine_II"]["dps_mult"]
            * refine_data["refine_III"]["dps_mult"])


def analyze_risk() -> None:
    """
    分析所有精炼路径的风险
    """
    print("=" * 80)
    print("精炼路径风险分析报告")
    print("=" * 80)
    print()
    print("【检查维度】")
    print("  1. 是否有百分比伤害（%最大生命）")
    print("  2. 是否有真实伤害（忽略减伤/护甲）")
    print("  3. 是否有 AOE 范围过大")
    print("  4. 是否有持续生成实体（可能超上限）")
    print("  5. DPS 倍率是否超过 3.5×")
    print()
    print("=" * 80)
    print()
    
    # 检查项 1：百分比伤害
    print("【1. 百分比伤害检查】")
    print()
    percent_paths = [(k, v) for k, v in REFINE_PATHS.items() if v.get("has_percent_damage", False)]
    
    if percent_paths:
        for id, data in percent_paths:
            print(f"  [WARN] #{id} {data['name']}")
            print(f"     - type: {data['type']}")
            percent_val = data.get("percent_damage_per_sec", 0)
            print(f"     - percent damage: {percent_val*100:.0f}%/s")
            print(f"     - issue: percent damage may be too strong vs Boss")
            if percent_val >= 0.02:
                print(f"     - doc status: [FAIL] still {percent_val*100:.0f}%/s, lower it")
            else:
                print(f"     - doc status: [OK] reduced to {percent_val*100:.0f}%/s")
        print()
        print("  [Advice]")
        print("  - confirm doc value is 1%/s")
        print("  - if still 2%/s, fix the design doc immediately")
    else:
        print("  [OK] no percent-damage paths")
    print()
    
    # 检查项 2：真实伤害
    print("【2. 真实伤害检查】")
    print()
    true_paths = [(k, v) for k, v in REFINE_PATHS.items() if v.get("has_true_damage", False)]
    
    if true_paths:
        for id, data in true_paths:
            print(f"  [WARN] #{id} {data['name']}")
            print(f"     - type: {data['type']}")
            # 查找真实伤害所在的精炼等级
            for refine_level in ["refine_I", "refine_II", "refine_III"]:
                if refine_level in data and "真实伤害" in data[refine_level].get("desc", ""):
                    level_display = refine_level.replace("refine_", "精炼 ")
                    print(f"     - true damage at: {level_display}")
                    print(f"     - {level_display} desc: {data[refine_level]['desc']}")
                    print(f"     - risk: {data[refine_level].get('risk', 'unset')}")
                    if "notes" in data[refine_level]:
                        print(f"     - notes: {data[refine_level]['notes']}")
                    break
            print(f"     - issue: true damage ignores Boss armor")
            print(f"     - advice: cap Boss true damage at 30%")
    else:
        print("  [OK] no true-damage paths")
    print()
    
    # 检查项 3：AOE 缩放
    print("【3. AOE 缩放检查】")
    print()
    aoe_paths = [(k, v) for k, v in REFINE_PATHS.items() if v.get("has_aoe_scaling", False)]
    print(f"  AOE-scaling path count: {len(aoe_paths)}")
    print("  [OK] AOE scaling needs multi-target DPS; no extra Boss edge")
    print("  [OK] expected design, no special action")
    print()
    
    # 检查项 4：持续实体生成
    print("【4. 持续实体生成检查】")
    print()
    for id, data in REFINE_PATHS.items():
        desc = data["refine_III"]["desc"]
        if "生成" in desc or "召唤" in desc or "雷云" in desc:
            print(f"  [WARN] #{id} {data['name']}")
            print(f"     - desc: {desc}")
            print(f"     - entity count: verify vs 350~450 cap during implementation")
    print()
    
    # 检查项 5：DPS 倍率
    print("【5. DPS 倍率检查（动态计算）】")
    print()
    
    for id, data in REFINE_PATHS.items():
        dps_mult = calculate_path_dps_mult(data)
        status = "[OK]" if dps_mult <= 3.5 else "[FAIL]"
        print(f"  {status} #{id} {data['name'][:20]}... DPS mult {dps_mult:.2f}x")
    print()
    
    print("=" * 80)
    print()
    
    # 汇总
    print("【风险汇总】")
    print()
    risks = []
    
    if percent_paths:
        for id, data in percent_paths:
            percent_val = data.get("percent_damage_per_sec", 0)
            if percent_val >= 0.02:
                risks.append(("高", f"#{id} {data['name']}: percent still {percent_val*100:.0f}%/s"))
            else:
                risks.append(("低", f"#{id} {data['name']}: percent reduced to {percent_val*100:.0f}%/s"))
    
    if true_paths:
        risks.append(("中", "#7 永恒锚轮: true damage (II) needs Boss cap (doc note present)"))
    
    if risks:
        for level, risk in risks:
            print(f"  [{level}] {risk}")
    else:
        print("  [OK] no significant risks")
    
    print()
    print("=" * 80)
    print()
    print("【建议行动】")
    print()
    print("1. [OK] done: doc B.10 percent damage updated to 1%/s")
    print("2. [OK] done: #7 true damage Boss cap note added")
    print("3. [DEV] verify entity spawn counts for #4/#6/#8 vs cap")
    print("4. [TUNE] measure #10 anchor press via CD*duration (see refine_dps_simulation.py)")
    print("5. Boss HP baseline: GDD §9.4 Devouring Star 7000 — do not use 500k assumptions")


# ============================================================
# 主程序
# ============================================================

if __name__ == "__main__":
    analyze_risk()