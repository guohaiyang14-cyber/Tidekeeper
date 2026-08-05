"""
精炼路径共享数据模块
用途：为精炼 DPS 模拟和风险分析脚本提供统一的数据源
数据源：设计文档附录 B（精炼路径数据）
"""

REFINE_PATHS = {
    1: {
        "name": "深渊鱼叉 → 深溯之径",
        "type": "定向弹幕",
        "has_aoe_scaling": True,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "追踪精度 +100%",
            "dps_mult": 1.15,
        },
        "refine_II": {
            "desc": "弹射 +2（总 5），衰减 10%",
            "dps_mult": 1.40,
        },
        "refine_III": {
            "desc": "穿渊贯海：暴击穿透全敌人，暴击率+5%",
            "dps_mult": 1.25,
            "risk": "低",
        },
    },
    2: {
        "name": "永昼圣火 → 耀阳之径",
        "type": "范围型",
        "has_aoe_scaling": True,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "灼烧范围 +40%，燃烧 +2s",
            "dps_mult": 1.35,
        },
        "refine_II": {
            "desc": "灼烧伤害 +80%，被灼烧移速 -15%",
            "dps_mult": 1.80,
        },
        "refine_III": {
            "desc": "焚天烈焰：被灼烧死亡引爆（范围120伤害+3秒灼烧）",
            "dps_mult": 1.20,
            "risk": "中",
            "notes": "需计算：120伤害×爆炸范围，是否会导致连锁爆炸？",
        },
    },
    3: {
        "name": "风暴之锚 → 雷霆之径",
        "type": "链式",
        "has_aoe_scaling": True,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "链跳 +2（总 4），链速 +50%",
            "dps_mult": 1.50,
        },
        "refine_II": {
            "desc": "闪电伤害 +60%，25% 减速",
            "dps_mult": 1.60,
        },
        "refine_III": {
            "desc": "天崩地裂：链终点雷击（150%伤害+1秒眩晕）",
            "dps_mult": 1.30,
            "risk": "低",
        },
    },
    4: {
        "name": "水母巢 → 群生之径",
        "type": "召唤",
        "has_aoe_scaling": False,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "爆炸范围 +50%，伤害 +40%",
            "dps_mult": 1.40,
        },
        "refine_II": {
            "desc": "召唤物 +1（总 4），伤害 +30%",
            "dps_mult": 1.30,
        },
        "refine_III": {
            "desc": "生生不息：爆炸生成临时精英召唤物（10秒，×2）",
            "dps_mult": 1.15,
            "risk": "低",
        },
    },
    5: {
        "name": "湮灭雷暴 → 苍穹之径",
        "type": "范围型",
        "has_aoe_scaling": True,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "连锁 +2（总 4），范围 +30%",
            "dps_mult": 1.50,
        },
        "refine_II": {
            "desc": "落雷伤害 +50%，CD -0.5s",
            "dps_mult": 1.70,
        },
        "refine_III": {
            "desc": "雷云永续：落点雷云（3秒，每秒30%落雷伤害）",
            "dps_mult": 1.25,
            "risk": "中",
            "notes": "3秒×30%落雷伤害，对群怪伤害较高，但无百分比",
        },
    },
    6: {
        "name": "深渊水母王 → 漩涡之径",
        "type": "定向弹幕",
        "has_aoe_scaling": True,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "弹幕 +2（总 8），漩涡 +40%",
            "dps_mult": 1.35,
        },
        "refine_II": {
            "desc": "定身 60%，时长 +0.3s",
            "dps_mult": 1.10,
        },
        "refine_III": {
            "desc": "深渊之怒：漩涡中心每秒生成2只毒水母",
            "dps_mult": 1.20,
            "risk": "中",
            "notes": "60秒战斗×2只/秒=120只毒水母，需计入实体上限",
        },
    },
    7: {
        "name": "永恒锚轮 → 不屈之径",
        "type": "环绕型",
        "has_aoe_scaling": False,
        "has_percent_damage": False,
        "has_true_damage": True,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "锚链 +2（总 8），递增 +25%",
            "dps_mult": 1.30,
        },
        "refine_II": {
            "desc": "反震之力：反弹提升至50%，转为真实伤害",
            "dps_mult": 1.15,
            "risk": "高",
            "notes": "【重点】真实伤害忽略减伤/护甲，对Boss可能过于有效",
        },
        "refine_III": {
            "desc": "震荡冲击：每4秒震荡波（击退+0.3秒眩晕）",
            "dps_mult": 1.10,
            "risk": "低",
        },
    },
    8: {
        "name": "永恒鸥群 → 翱翔之径",
        "type": "召唤",
        "has_aoe_scaling": False,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "鸥群 +1，鸥王 +50%",
            "dps_mult": 1.40,
        },
        "refine_II": {
            "desc": "+15% 暴击，暴伤 +80%",
            "dps_mult": 1.35,
        },
        "refine_III": {
            "desc": "王者归来：鸥王死亡召唤2只精英信天翁",
            "dps_mult": 1.10,
            "risk": "低",
        },
    },
    9: {
        "name": "永夜潮汐 → 潮汐之径",
        "type": "控制",
        "has_aoe_scaling": False,
        "has_percent_damage": False,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.0,
        "refine_I": {
            "desc": "减速 60%，击退 +50%",
            "dps_mult": 1.05,
        },
        "refine_II": {
            "desc": "眩晕 +0.2s，频率 5s→4.5s",
            "dps_mult": 1.05,
        },
        "refine_III": {
            "desc": "永夜无尽：潮湿（减速15%，2秒）",
            "dps_mult": 1.05,
            "risk": "低",
        },
    },
    10: {
        "name": "星海锚坠 → 陨星之径",
        "type": "爆发",
        "has_aoe_scaling": True,
        "has_percent_damage": True,
        "has_true_damage": False,
        "percent_damage_per_sec": 0.01,
        "refine_I": {
            "desc": "CD 降至 2.5s，震荡波 +15%",
            "dps_mult": 1.50,
        },
        "refine_II": {
            "desc": "眩晕 +0.3s，爆炸 150%",
            "dps_mult": 1.25,
        },
        "refine_III": {
            "desc": "星海坠陨：锚压：每秒1%最大生命，持续3秒",
            "dps_mult": 1.50,
            "risk": "中",
            "notes": "【已修正】从 2%/秒 降为 1%/秒，不再独立秒杀 Boss",
        },
    },
}