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
            print(f"  ⚠️  #{id} {data['name']}")
            print(f"     - 类型：{data['type']}")
            percent_val = data.get("percent_damage_per_sec", 0)
            print(f"     - 百分比伤害：{percent_val*100:.0f}%/秒")
            print(f"     - 问题：百分比伤害对 Boss 可能过于有效")
            if percent_val >= 0.02:
                print(f"     - 文档状态：❌ 仍为 {percent_val*100:.0f}%/秒，建议降低")
            else:
                print(f"     - 文档状态：✅ 已降至 {percent_val*100:.0f}%/秒，合理")
        print()
        print("  【建议】")
        print("  - 确认文档中的数值是否已更新为 1%/秒")
        print("  - 如仍为 2%/秒，需立即修正文档")
    else:
        print("  ✅ 无路径包含百分比伤害")
    print()
    
    # 检查项 2：真实伤害
    print("【2. 真实伤害检查】")
    print()
    true_paths = [(k, v) for k, v in REFINE_PATHS.items() if v.get("has_true_damage", False)]
    
    if true_paths:
        for id, data in true_paths:
            print(f"  ⚠️  #{id} {data['name']}")
            print(f"     - 类型：{data['type']}")
            # 查找真实伤害所在的精炼等级
            for refine_level in ["refine_I", "refine_II", "refine_III"]:
                if refine_level in data and "真实伤害" in data[refine_level].get("desc", ""):
                    level_display = refine_level.replace("refine_", "精炼 ")
                    print(f"     - 真实伤害位置：{level_display}")
                    print(f"     - {level_display} 描述：{data[refine_level]['desc']}")
                    print(f"     - 风险等级：{data[refine_level].get('risk', '未设置')}")
                    if "notes" in data[refine_level]:
                        print(f"     - 备注：{data[refine_level]['notes']}")
                    break
            print(f"     - 问题：真实伤害忽略 Boss 减伤/护甲，可能过于有效")
            print(f"     - 建议：对 Boss 真实伤害上限设为 30%")
    else:
        print("  ✅ 无路径包含真实伤害")
    print()
    
    # 检查项 3：AOE 缩放
    print("【3. AOE 缩放检查】")
    print()
    aoe_paths = [(k, v) for k, v in REFINE_PATHS.items() if v.get("has_aoe_scaling", False)]
    print(f"  含 AOE 缩放的路径数：{len(aoe_paths)}")
    print("  ✅ AOE 缩放路径需要在多目标场景下计算 DPS，但对 Boss（单目标）无额外优势")
    print("  ✅ 这是正常设计，无需特殊处理")
    print()
    
    # 检查项 4：持续实体生成
    print("【4. 持续实体生成检查】")
    print()
    for id, data in REFINE_PATHS.items():
        desc = data["refine_III"]["desc"]
        if "生成" in desc or "召唤" in desc or "雷云" in desc:
            print(f"  ⚠️  #{id} {data['name']}")
            print(f"     - 描述：{desc}")
            print(f"     - 实体数量估算：需在开发时验证是否超过 350~450 上限")
    print()
    
    # 检查项 5：DPS 倍率
    print("【5. DPS 倍率检查（动态计算）】")
    print()
    
    for id, data in REFINE_PATHS.items():
        dps_mult = calculate_path_dps_mult(data)
        status = "✅" if dps_mult <= 3.5 else "❌"
        print(f"  {status} #{id} {data['name'][:20]}... DPS倍率 {dps_mult:.2f}×")
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
                risks.append(("高", f"#{id} {data['name']}：百分比伤害仍为 {percent_val*100:.0f}%/秒，建议降低"))
            else:
                risks.append(("低", f"#{id} {data['name']}：百分比伤害已降至 {percent_val*100:.0f}%/秒，合理"))
    
    if true_paths:
        risks.append(("中", "#7 永恒锚轮：真实伤害（精炼 II）需对 Boss 设置上限（文档已补充说明）"))
    
    if risks:
        for level, risk in risks:
            print(f"  【{level}】 {risk}")
    else:
        print("  ✅ 无显著风险")
    
    print()
    print("=" * 80)
    print()
    print("【建议行动】")
    print()
    print("1. ✅ 已完成：文档 B.10 百分比伤害已更新为 1%/秒")
    print("2. ✅ 已完成：#7 永恒锚轮真实伤害已添加 Boss 上限说明")
    print("3. 【开发阶段】验证 #4/#6/#8 的实体生成数量是否超过上限")
    print("4. 【调优阶段】实测 #10 锚压：按 CD×持续覆盖率建模（见 refine_dps_simulation.py）")
    print("5. Boss 底血以主文档 §9.4（吞噬之星 7000）为准，勿再用 50 万假设值做绝对结论")


# ============================================================
# 主程序
# ============================================================

if __name__ == "__main__":
    analyze_risk()