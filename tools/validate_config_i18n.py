#!/usr/bin/env python3
# ============================================================================
# validate_config_i18n.py — Tidekeeper 配置 / i18n 一致性校验（W20 集成验收·机器可验）
# 校验项：
#   1) config/*.json 内部与跨文件引用 id 存在（角色初始武器 / 灯塔前置 / 进化·精炼武器 /
#      敌人词缀 / 天灾夜 Boss / 事件效果引用武器被动 / 难度档位 / 星尘·挫败感参数）。
#   2) config/i18n.csv：代码中 localize("key") 用到的 key 全部存在；缺失 key 回退测试。
# 仅用标准库；退出码 0=全部通过，1=存在失败项。
# 用法：python tools/validate_config_i18n.py
# ============================================================================
import csv
import json
import os
import re
import sys

# Windows 控制台 UTF-8 输出（避免中文校验项乱码）
if hasattr(sys.stdout, "reconfigure"):
	try:
		sys.stdout.reconfigure(encoding="utf-8")
	except Exception:
		pass

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(REPO, "config")
SCRIPTS_DIR = os.path.join(REPO, "godot_project", "scripts")

failed = 0
checked = 0


def load_json(name):
    path = os.path.join(CONFIG_DIR, name)
    if not os.path.isfile(path):
        print("[FAIL] 配置文件缺失: %s" % name)
        global failed
        failed += 1
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def ok(cond, label):
    global failed, checked
    checked += 1
    if cond:
        print("[OK]   %s" % label)
    else:
        failed += 1
        print("[FAIL] %s" % label)


def collect_ids(table, subkey):
    """table 形如 {subkey: {id: {...}}}，返回 id 集合。"""
    return set((table.get(subkey) or {}).keys())


# ---------------------------------------------------------------------------
# 加载配置
# ---------------------------------------------------------------------------
weapons = load_json("weapons.json")
enemies = load_json("enemies.json")
bosses = load_json("bosses.json")
events = load_json("events.json")
passives = load_json("passives.json")
evolutions = load_json("evolutions.json")
refine = load_json("refine_paths.json")
characters = load_json("characters.json")
lighthouse = load_json("lighthouse_tree.json")
meta = load_json("meta.json")
frustration = load_json("frustration.json")
difficulty = load_json("difficulty.json")

weapon_ids = collect_ids(weapons, "weapons")
enemy_ids = collect_ids(enemies, "enemies")
affix_ids = set(k for k in (enemies.get("affixes") or {}).keys() if k != "_meta")
passive_ids = collect_ids(passives, "passives")
boss_ids = collect_ids(bosses, "bosses")
event_ids = collect_ids(events, "events")
char_ids = collect_ids(characters, "characters")
evo_weapon_ids = collect_ids(evolutions, "paths")
refine_weapon_ids = collect_ids(refine, "paths")

all_lh_nodes = set()
for branch in (lighthouse.get("branches") or {}).values():
    all_lh_nodes |= set((branch.get("nodes") or {}).keys())

global_starting = (weapons.get("metadata") or {}).get("starting_weapon", "")

# ---------------------------------------------------------------------------
# 1) 跨文件引用一致性
# ---------------------------------------------------------------------------
print("== 配置跨引用一致性 ==")

# 角色初始武器
for cid in char_ids:
    c = characters["characters"][cid]
    sw = c.get("starting_weapon", global_starting)
    if sw == "":
        ok(True, "角色 %s 无初始武器(回退全局)" % cid)
    else:
        ok(sw in weapon_ids, "角色 %s 初始武器 %s 存在" % (cid, sw))

# 灯塔前置节点
for nid in all_lh_nodes:
    node = None
    for branch in (lighthouse.get("branches") or {}).values():
        node = (branch.get("nodes") or {}).get(nid)
        if node is not None:
            break
    req = node.get("requires", "") if isinstance(node, dict) else ""
    if req not in ("", None):
        ok(req in all_lh_nodes, "灯塔节点 %s 前置 %s 存在" % (nid, req))

# 进化路径武器
for wid in evo_weapon_ids:
    ok(wid in weapon_ids, "进化路径武器 %s 存在" % wid)
# 进化掉落规则（并非武器引用，而是按夜掉落参数）
drops = evolutions.get("drops") or {}
for night_key, cnt in (drops.get("boss_drop_count") or {}).items():
    ok(int(night_key) in (10, 15, 20), "进化掉落 boss_drop_count 夜 %s ∈ {10,15,20}" % night_key)
    ok(isinstance(cnt, int), "进化掉落 boss_drop_count[%s]=%s 为数值" % (night_key, cnt))
for n in (drops.get("elite_night_guaranteed") or []):
    ok(isinstance(n, int), "进化掉落 elite_night_guaranteed 夜 %s 为数值" % n)
ok(isinstance(drops.get("elite_per_night_cap"), int), "进化掉落 elite_per_night_cap 为数值")

# 精炼路径武器
for wid in refine_weapon_ids:
    ok(wid in weapon_ids, "精炼路径武器 %s 存在" % wid)

# 敌人词缀引用
for eid in enemy_ids:
    e = enemies["enemies"][eid]
    for a in (e.get("affixes") or []):
        ok(a in affix_ids, "敌人 %s 词缀 %s 存在" % (eid, a))

# 天灾夜 Boss：night ∈ {10,15,20}，且 3 个
boss_nights = []
for bid in boss_ids:
    b = bosses["bosses"][bid]
    night = b.get("night")
    boss_nights.append(night)
    ok(night in (10, 15, 20), "Boss %s night=%s ∈ {10,15,20}" % (bid, night))
ok(sorted(boss_nights) == [10, 15, 20], "天灾夜集合 = [10,15,20] (实际 %s)" % sorted(boss_nights))

# 事件：excluded_nights 数值；effect 引用的武器/被动存在
def _walk_effect(o, eid):
    """递归查找 effect 中的 weapon/passive 字符串引用并校验其存在（模块级，避免循环内重复定义）。"""
    if isinstance(o, dict):
        for k, val in o.items():
            if k in ("weapon", "passive") and isinstance(val, str):
                if k == "weapon":
                    ok(val in weapon_ids, "事件 %s 效果武器 %s 存在" % (eid, val))
                else:
                    ok(val in passive_ids, "事件 %s 效果被动 %s 存在" % (eid, val))
            else:
                _walk_effect(val, eid)
    elif isinstance(o, list):
        for it in o:
            _walk_effect(it, eid)


for eid in event_ids:
    ev = events["events"][eid]
    for v in (ev.get("excluded_nights") or []):
        ok(isinstance(v, (int, float)), "事件 %s excluded_night=%s 为数值" % (eid, v))
    _walk_effect(ev.get("effect", {}), eid)

# 难度档位
tiers = difficulty.get("tiers") or {}
ok("lighthouse" in tiers and "watcher" in tiers, "难度档位含 lighthouse/watcher")
ok(isinstance(difficulty.get("max_enemies"), int) and difficulty.get("max_enemies") == 350,
   "difficulty.max_enemies=350 (=%s)" % difficulty.get("max_enemies"))
ok(isinstance((difficulty.get("teaching") or {}).get("nights"), int), "difficulty.teaching.nights 为数值")

# 星尘 / 挫败感参数
st = meta.get("stardust") or {}
ok(isinstance(st.get("base"), (int, float)), "meta.stardust.base 为数值")
ok(isinstance(st.get("first_clear_mult"), (int, float)), "meta.stardust.first_clear_mult 为数值")
fb = frustration.get("fallback") or {}
ok(isinstance(fb.get("enabled"), bool), "frustration.fallback.enabled 为布尔")
stg = frustration.get("struggle") or {}
ok(isinstance(stg.get("kills_to_revive"), int), "frustration.struggle.kills_to_revive 为数值")

# ---------------------------------------------------------------------------
# 2) i18n.csv 覆盖
# ---------------------------------------------------------------------------
print("== i18n.csv 覆盖 ==")
csv_path = os.path.join(CONFIG_DIR, "i18n.csv")
ok(os.path.isfile(csv_path), "i18n.csv 存在")
csv_keys = set()
if os.path.isfile(csv_path):
    with open(csv_path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            k = (row.get("key") or "").strip()
            if k:
                csv_keys.add(k)

# 收集代码中 localize("key") / localize('key') 字面量
# 仅统计生产代码（跳过 tests 目录，测试允许探测缺失/动态 key）；
# 跳过动态格式 key（含 % 或 {，如 "difficulty.tier.%s"）。
used_keys = set()
dynamic_keys = set()
lit_re = re.compile(r'localizef?\(\s*["\']([^"\']+)["\']')
for root, _dirs, files in os.walk(SCRIPTS_DIR):
    if os.path.basename(root) == "tests":
        continue  # 测试代码允许引用缺失/动态 key（如回退用例）
    for fn in files:
        if not fn.endswith(".gd"):
            continue
        with open(os.path.join(root, fn), "r", encoding="utf-8") as f:
            for line in f:
                for m in lit_re.findall(line):
                    if "%" in m or "{" in m:
                        dynamic_keys.add(m)
                        continue
                    used_keys.add(m)

ok(len(used_keys) > 0, "生产代码中检测到 %d 个 localize 字面量 key" % len(used_keys))
if dynamic_keys:
    print("  [INFO] 跳过 %d 个动态格式 key: %s" % (len(dynamic_keys), sorted(dynamic_keys)))
missing = sorted(k for k in used_keys if k not in csv_keys)
ok(len(missing) == 0, "所有生产 localize key 均在 i18n.csv 中 (缺失=%s)" % (missing if missing else "无"))

# 缺失 key 回退自检（localize 未命中应回退 key 自身，这里只确认 csv 含常用 key）
for must in ("ui.game_over", "ui.victory", "difficulty.tier.lighthouse", "difficulty.tier.watcher"):
    ok(must in csv_keys, "i18n 关键 key 存在: %s" % must)

# ---------------------------------------------------------------------------
print("------------------------------------------------------------")
print("校验项=%d 失败=%d" % (checked, failed))
sys.exit(1 if failed else 0)
