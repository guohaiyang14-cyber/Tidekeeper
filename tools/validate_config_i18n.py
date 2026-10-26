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


def _num(v, default: float = 0.0) -> float:
    """配置值安全转 float：非数值/缺失/布尔退默认。

    ok() 只记录 FAIL、不会拦截后续强转——坏值（字符串/数组/null）会让
    float()/int() 直接 traceback 崩溃，整个校验器中断而非记失败项
    （2026-10-23 code-review P1：配置 JSON 解析盲目信任无校验）。
    """
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return default
    return float(v)


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
upgrade = load_json("upgrade.json")
exp_table = load_json("exp_table.json")

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

# 天灾夜 Boss：收集夜次集合（与 night.json 的交叉校验见下方 night 段）
boss_nights = []
for bid in boss_ids:
    b = bosses["bosses"][bid]
    boss_nights.append(b.get("night"))

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

# passives.json effect_buckets 含 vision_radius_units（W23 新增）
p_buckets = (passives.get("metadata") or {}).get("effect_buckets") or []
ok("vision_radius_units" in p_buckets, "passives.metadata.effect_buckets 含 vision_radius_units")
# pearl（夜明珠）提供视野
pearl_eff = (passives.get("passives") or {}).get("pearl", {}).get("effect") or {}
ok(_num(pearl_eff.get("vision_radius_units")) > 0.0,
   "passives.pearl.effect.vision_radius_units >0 (%s)" % pearl_eff.get("vision_radius_units"))

# 难度档位
tiers = difficulty.get("tiers") or {}
ok("lighthouse" in tiers and "watcher" in tiers, "难度档位含 lighthouse/watcher")
ok(isinstance(difficulty.get("max_enemies"), int) and difficulty.get("max_enemies") == 350,
   "difficulty.max_enemies=350 (=%s)" % difficulty.get("max_enemies"))
ok(isinstance((difficulty.get("teaching") or {}).get("nights"), int), "difficulty.teaching.nights 为数值")

# 昼夜循环夜长（config/night.json ↔ Boss 夜 / 精英夜 / 进化保底夜口径）
night = load_json("night.json")
durations = night.get("durations") or {}
for tname in ("normal", "elite", "calamity", "final"):
    v = durations.get(tname)
    ok(isinstance(v, (int, float)) and v > 0, "night.durations.%s 为正数值 (%s)" % (tname, v))
night_types = night.get("night_types") or {}
elite_nights_cfg = night_types.get("elite_nights")
calamity_nights_cfg = night_types.get("calamity_nights")
final_night_cfg = night_types.get("final_night")
ok(isinstance(elite_nights_cfg, list) and len(elite_nights_cfg) > 0
   and all(isinstance(n, int) for n in elite_nights_cfg),
   "night.night_types.elite_nights 为非空整数表 (%s)" % elite_nights_cfg)
ok(isinstance(calamity_nights_cfg, list) and len(calamity_nights_cfg) > 0
   and all(isinstance(n, int) for n in calamity_nights_cfg),
   "night.night_types.calamity_nights 为非空整数表 (%s)" % calamity_nights_cfg)
ok(isinstance(final_night_cfg, int) and final_night_cfg > 0,
   "night.night_types.final_night 为正整数 (%s)" % final_night_cfg)
ok(str(night_types.get("default_type", "")) in durations,
   "night.night_types.default_type 在 durations 中 (%s)" % night_types.get("default_type"))
# Boss 夜 = 天灾夜 + 终局夜（bosses.json night 集合须与 night.json 映射一致）
boss_nights_expected = sorted(list(calamity_nights_cfg or []) + [final_night_cfg])
ok(sorted(boss_nights) == boss_nights_expected,
   "Boss 夜集合 = 天灾夜+终局夜 %s (实际 %s)" % (boss_nights_expected, sorted(boss_nights)))
# 天灾夜词缀表口径与 night.json  calamity 映射一致（enemies.json 含终局夜）
affix_calamity = sorted(((enemies.get("metadata") or {}).get("affix_rules") or {}).get("calamity_nights") or [])
ok(affix_calamity == sorted(list(calamity_nights_cfg or []) + [final_night_cfg]),
   "enemies.json calamity_nights = 天灾夜+终局夜 %s (实际 %s)" % (boss_nights_expected, affix_calamity))
# 进化保底夜必须是精英夜
for n in (evolutions.get("drops") or {}).get("elite_night_guaranteed") or []:
    ok(n in (elite_nights_cfg or []),
       "进化保底夜 %s ∈ night.elite_nights %s" % (n, elite_nights_cfg))

# 星尘 / 挫败感参数
st = meta.get("stardust") or {}
ok(isinstance(st.get("base"), (int, float)), "meta.stardust.base 为数值")
ok(isinstance(st.get("first_clear_mult"), (int, float)), "meta.stardust.first_clear_mult 为数值")
fb = frustration.get("fallback") or {}
ok(isinstance(fb.get("enabled"), bool), "frustration.fallback.enabled 为布尔")
stg = frustration.get("struggle") or {}
ok(isinstance(stg.get("kills_to_revive"), int), "frustration.struggle.kills_to_revive 为数值")

# ---------------------------------------------------------------------------
# 1b) 像素风 UI 皮肤（config/ui_skin.json ↔ assets/ui/pixel/*.png）
# ---------------------------------------------------------------------------
print("== UI 皮肤资源一致性 ==")
skin = load_json("ui_skin.json")
SKIN_DIR = os.path.join(REPO, "godot_project", "assets", "ui", "pixel")


def png_size(path):
    """零依赖读取 PNG IHDR 宽高（前 24 字节：8 sig + 4 len + 4 'IHDR' + 4 w + 4 h）。"""
    try:
        with open(path, "rb") as f:
            head = f.read(24)
        if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
            return None
        return (int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"))
    except OSError:
        return None


ok(isinstance(skin.get("enabled"), bool), "ui_skin.enabled 为布尔")
skin_dir_cfg = str(skin.get("asset_dir") or "")
ok(skin_dir_cfg.startswith("res://") and skin_dir_cfg.endswith("/"),
   "ui_skin.asset_dir 为 res:// 目录 (%s)" % skin_dir_cfg)
skin_rel = skin_dir_cfg.replace("res://", "", 1).rstrip("/")
skin_abs = os.path.join(REPO, "godot_project", skin_rel.replace("/", os.sep))
ok(os.path.isdir(skin_abs), "ui_skin.asset_dir 磁盘存在 (%s)" % skin_rel)

nine = skin.get("nine_patch") or {}
styles = skin.get("styles") or {}
ok(len(styles) > 0, "ui_skin.styles 非空 (%d 条)" % len(styles))

for sid, sdef in styles.items():
    tex_name = str((sdef or {}).get("texture") or "")
    tex_path = os.path.join(skin_abs, tex_name)
    ok(tex_name != "" and os.path.isfile(tex_path), "样式 %s 贴图存在 (%s)" % (sid, tex_name))
    patch_key = str((sdef or {}).get("patch") or "")
    ok(patch_key in nine, "样式 %s 的 patch 键 %s 在 nine_patch 中" % (sid, patch_key))
    if not os.path.isfile(tex_path):
        continue
    size = png_size(tex_path)
    ok(size is not None, "样式 %s 贴图为合法 PNG (%s)" % (sid, tex_name))
    if size is None:
        continue
    margin = nine.get(patch_key)
    if not isinstance(margin, int):
        ok(False, "样式 %s 的 nine_patch.%s 为整数" % (sid, patch_key))
        continue
    # 九宫格四边边距之和必须小于贴图边长，否则中段被挤成负宽（Godot 会静默画成纯色块）
    ok(0 < margin * 2 < size[0] and 0 < margin * 2 < size[1],
       "样式 %s 九宫格边距 %d×2 < 贴图 %d×%d" % (sid, margin, size[0], size[1]))

# 反向：目录内每个 PNG 要么被 styles 引用，要么是图标类（icon_/cursor_）
if os.path.isdir(skin_abs):
    referenced = {str((s or {}).get("texture") or "") for s in styles.values()}
    orphans = []
    for fn in sorted(os.listdir(skin_abs)):
        if not fn.endswith(".png"):
            continue
        if fn.startswith("icon_") or fn.startswith("cursor_"):
            continue
        if fn not in referenced:
            orphans.append(fn)
    ok(len(orphans) == 0, "ui_skin 目录无孤儿贴图 (孤儿=%s)" % (orphans if orphans else "无"))

# theme 段引用的 style id 必须存在于 styles
for type_name, slots in (skin.get("theme") or {}).items():
    for slot_name, style_id in (slots or {}).items():
        ok(str(style_id) in styles,
           "theme.%s.%s 引用样式 %s 存在" % (type_name, slot_name, style_id))

# ---------------------------------------------------------------------------
# 1c) 地图 / 灯塔 / 黑夜视线（config/map.json ↔ config/night.json ↔ world 精灵）
#     2026-10-22 用户反馈五件套：塔楼+光束 / 黑夜视线 / 边界障碍物 / 界外击杀 / 地图放大
# ---------------------------------------------------------------------------
print("== 地图 / 灯塔 / 黑夜视线一致性 ==")
mapc = load_json("map.json")
SPRITE_WORLD_DIR = os.path.join(REPO, "godot_project", "assets", "sprites", "world")
UNIT_TO_PIXEL = 60.0  # 与 player.gd const UNIT_TO_PIXEL 同步（红线：数值不得硬编码于业务逻辑）
DEFAULT_WINDOW_W = 1280  # 默认打开页面宽（用户要求「地图至少比默认页面大一些」）
DEFAULT_WINDOW_H = 720  # 默认打开页面高（视口对角线校验用）


def _color3(v, label):
    """三通道 [0,1] 颜色合法性。"""
    ok(isinstance(v, list) and len(v) == 3
       and all(isinstance(c, (int, float)) and 0.0 <= c <= 1.0 for c in v),
       "%s 为三通道 [0,1] 颜色 (%s)" % (label, v))


lh = mapc.get("lighthouse") or {}
# 地面砖段（2026-10-23 code-review 修复：ground 段曾被误删、字段错并进 scattered_lights，
# 两个 getter 靠默认值 floor_0/4096 侥幸行为不变；此处钉死结构，防止再次静默退化）
gnd = mapc.get("ground")
ok(isinstance(gnd, dict) and len(gnd) > 0,
   "map.json 存在独立 ground 段（不得被删除或并入其他段）")
if isinstance(gnd, dict):
    gnd_tile = str(gnd.get("tile_id") or "")
    ok(gnd_tile != "", "ground.tile_id 非空 (%s)" % gnd_tile)
    gnd_png = os.path.join(REPO, "godot_project", "assets", "sprites", "ground", gnd_tile + ".png")
    ok(gnd_tile != "" and os.path.isfile(gnd_png),
       "地面砖精灵存在 (assets/sprites/ground/%s.png)" % gnd_tile)
    gnd_cover = _num(gnd.get("cover_px"))
    ok(gnd_cover >= 512.0, "ground.cover_px ≥512（与 get_ground_cover_px 下限一致）(%s)" % gnd_cover)
    _vp_diag = (DEFAULT_WINDOW_W ** 2 + DEFAULT_WINDOW_H ** 2) ** 0.5
    ok(gnd_cover > _vp_diag,
       "ground.cover_px %.0f > 视口对角线 %.0f（铺开范围须覆盖视口）" % (gnd_cover, _vp_diag))
# 回归守卫：ground 字段不得残留在 scattered_lights（P1 曾犯错的形态）
_sl_pre = mapc.get("scattered_lights") or {}
ok("tile_id" not in _sl_pre and "cover_px" not in _sl_pre,
   "scattered_lights 内无 ground 字段残留（tile_id/cover_px 归属 ground 段）")

sprite_id = str(lh.get("sprite_id") or "")
tower_png = os.path.join(SPRITE_WORLD_DIR, sprite_id + ".png") if sprite_id else ""
ok(sprite_id != "" and os.path.isfile(tower_png),
   "灯塔精灵 %s 存在 (assets/sprites/world/%s.png)" % (sprite_id, sprite_id))
if os.path.isfile(tower_png):
    tsize = png_size(tower_png)
    ok(tsize is not None, "灯塔精灵为合法 PNG (%s)" % (tsize,))
    if tsize is not None:
        # 「灯塔应该是一个有高度的塔」：塔楼贴图必须明显高于宽（宽高比 < 1）
        ok(tsize[1] > tsize[0],
           "灯塔塔楼有高度：%dx%d 高>宽" % (tsize[0], tsize[1]))
ok(isinstance(lh.get("lamp_height_px"), (int, float)) and lh.get("lamp_height_px") > 0,
   "lighthouse.lamp_height_px 为正数值 (%s)" % lh.get("lamp_height_px"))
ok(isinstance(lh.get("lamp_glow_radius_px"), (int, float)) and lh.get("lamp_glow_radius_px") > 0,
   "lighthouse.lamp_glow_radius_px 为正数值 (%s)" % lh.get("lamp_glow_radius_px"))

beam = lh.get("beam") or {}
ok(isinstance(beam.get("enabled"), bool), "lighthouse.beam.enabled 为布尔")
ok(isinstance(beam.get("length_units"), (int, float)) and beam.get("length_units") > 0,
   "beam.length_units 为正数值 (%s → %dpx)" % (beam.get("length_units"), int(_num(beam.get("length_units")) * UNIT_TO_PIXEL)))
ha = beam.get("half_angle_deg")
ok(isinstance(ha, (int, float)) and 0.0 < float(ha) < 90.0,
   "beam.half_angle_deg 在 (0,90) 度 (%s)" % ha)
ok(isinstance(beam.get("rotation_speed_deg"), (int, float)) and beam.get("rotation_speed_deg") >= 0,
   "beam.rotation_speed_deg 为非负数值 (%s)" % beam.get("rotation_speed_deg"))
_color3(beam.get("color"), "beam.color")
ba = beam.get("alpha")
ok(isinstance(ba, (int, float)) and 0.0 < float(ba) <= 1.0,
   "beam.alpha 在 (0,1] (%s)" % ba)

arena = mapc.get("arena") or {}
ok(isinstance(arena.get("enabled"), bool), "arena.enabled 为布尔")
arena_enabled = bool(arena.get("enabled", True))
radius_units = _num(arena.get("radius_units"))
radius_px = radius_units * UNIT_TO_PIXEL
# 2026-10-23 用户反馈「去掉地图范围限制」→ arena.enabled=false。
# 参数全部保留（便于一键恢复），因此无论开关都校验参数合法性；
# 仅在开启时校验「地图大于默认窗口」这一设计意图。
ok(radius_units > 0.0, "arena.radius_units 为正数值 (%s → %dpx)" % (radius_units, radius_px))
if arena_enabled:
    ok(radius_px * 2.0 > DEFAULT_WINDOW_W,
       "竞技场直径 %dpx > 默认窗口宽 %dpx（用户要求地图大于默认页面）" % (radius_px * 2.0, DEFAULT_WINDOW_W))
else:
    # 关闭态：参数保留供恢复，且不得残留「硬限制」副作用
    ok(radius_px * 2.0 > DEFAULT_WINDOW_W,
       "arena 已关闭但仍保留 radius=%dpx（> 窗口 %dpx，便于恢复）" % (radius_px * 2.0, DEFAULT_WINDOW_W))

scm = arena.get("spawn_clamp_margin_px")
ok(isinstance(scm, (int, float)) and 0.0 <= float(scm) < radius_px,
   "arena.spawn_clamp_margin_px 在 [0,半径) (%s)" % scm)

leash = arena.get("enemy_leash") or {}
ok(isinstance(leash.get("enabled"), bool), "arena.enemy_leash.enabled 为布尔")
lm = leash.get("margin_px")
ok(isinstance(lm, (int, float)) and 0.0 <= float(lm) < radius_px,
   "arena.enemy_leash.margin_px 在 [0,半径) (%s)" % lm)

boundary = arena.get("boundary") or {}
ok(isinstance(boundary.get("enabled"), bool), "arena.boundary.enabled 为布尔")
if not arena_enabled:
    ok(boundary.get("enabled") is False,
       "arena 关闭时 boundary.enabled 同步为 false（不生成界桩）")
post_ids = boundary.get("post_ids") or []
ok(isinstance(post_ids, list) and len(post_ids) > 0,
   "boundary.post_ids 非空列表 (%s)" % (post_ids,))
for pid in post_ids:
    png = os.path.join(SPRITE_WORLD_DIR, str(pid) + ".png")
    ok(os.path.isfile(png), "界桩精灵 %s 存在" % pid)
ok(isinstance(boundary.get("post_spacing_px"), (int, float)) and boundary.get("post_spacing_px") > 0,
   "boundary.post_spacing_px 为正数值 (%s)" % boundary.get("post_spacing_px"))
ok(isinstance(boundary.get("post_scale"), (int, float)) and boundary.get("post_scale") > 0,
   "boundary.post_scale 为正数值 (%s)" % boundary.get("post_scale"))
for arc_key in ("energy_arc", "outer_tint"):
    arc = boundary.get(arc_key) or {}
    ok(isinstance(arc.get("enabled"), bool), "boundary.%s.enabled 为布尔" % arc_key)
    _color3(arc.get("color"), "boundary.%s.color" % arc_key)
    aa = arc.get("alpha")
    ok(isinstance(aa, (int, float)) and 0.0 < float(aa) <= 1.0,
       "boundary.%s.alpha 在 (0,1] (%s)" % (arc_key, aa))
    if arc_key == "energy_arc":
        ok(isinstance(arc.get("width"), (int, float)) and arc.get("width") > 0,
           "energy_arc.width 为正数值 (%s)" % arc.get("width"))
        ok(isinstance(arc.get("dash_px"), (int, float)) and arc.get("dash_px") > 0,
           "energy_arc.dash_px 为正数值 (%s)" % arc.get("dash_px"))

# 散落光源（荧光藻 / 贝类 / 夜明珠）：2026-10-23 用户要求
print("== map.json scattered_lights 散落光源 ==")
# 灯塔辉光半径在 night.json.vision（本节先于 vision 段执行，故就地读取）
_sl_glow_u = _num(((night.get("vision") or {}).get("lighthouse_glow_units")))
sl = mapc.get("scattered_lights") or {}
ok(isinstance(sl.get("enabled"), bool), "scattered_lights.enabled 为布尔")
sl_enabled = bool(sl.get("enabled", False))
sl_per = int(_num(sl.get("lights_per_chunk")))
ok(sl_per > 0, "scattered_lights.lights_per_chunk >0 (%s)" % sl_per)
sl_chunk = _num(sl.get("chunk_px"))
ok(sl_chunk >= 240.0, "scattered_lights.chunk_px ≥240（区块边长）(%s)" % sl_chunk)
sl_cr = int(_num(sl.get("chunk_radius")))
ok(sl_cr >= 2, "scattered_lights.chunk_radius ≥2（覆盖 1280x720 视口）(%s)" % sl_cr)
# 覆盖率：区块半径 × 区块边长 须盖住视口半对角线（约 735px）
ok(sl_cr * sl_chunk >= 960.0,
   "散落光源覆盖半径 %dpx ≥960px（视口半对角线 735px + 余量）" % int(sl_cr * sl_chunk))
# 2026-10-23 用户反馈「野生光源应该是常亮的」→ 呼吸脉冲已停用
ok("pulse_speed" not in sl, "scattered_lights 无 pulse_speed（常亮，脉冲已停用）")
ok("count" not in sl and "spawn_min_units" not in sl,
   "scattered_lights 已改区块生成（无 count/spawn_min_units 残留）")
sl_r = _num(sl.get("radius_units"))
ok(sl_r > 0.0, "scattered_lights.radius_units >0 (%s → %dpx)" % (sl_r, sl_r * UNIT_TO_PIXEL))
ok(sl_r < _sl_glow_u, "散落光源半径 %s 单位 < 灯塔辉光 %s 单位（小型光源）" % (sl_r, _sl_glow_u))
sl_int = _num(sl.get("intensity"))
ok(0.0 < sl_int <= 1.0, "scattered_lights.intensity ∈(0,1] (%s)" % sl_int)
sl_core = _num(sl.get("core_ratio"))
ok(0.0 <= sl_core < 1.0, "scattered_lights.core_ratio ∈[0,1) (%s)" % sl_core)
sl_gap = _num(sl.get("min_gap_units"))
ok(sl_gap > 0.0, "scattered_lights.min_gap_units >0 (%s → %dpx)" % (sl_gap, sl_gap * UNIT_TO_PIXEL))
# 2026-10-23 第二轮（用户反馈「野外光源不发出扇形光…不要挡住下方的视野…减少数量…素材也要减小」）
sl_ss = _num(sl.get("sprite_scale"))
ok(0.25 <= sl_ss <= 2.0, "scattered_lights.sprite_scale ∈[0.25,2] (%s)" % sl_ss)
ok(sl_ss < 1.0, "散落光源素材已缩小（sprite_scale=%.2f <1）" % sl_ss)
sl_hs = _num(sl.get("halo_scale"))
ok(1.0 <= sl_hs <= 6.0, "scattered_lights.halo_scale ∈[1,6]（光晕=素材半边长×该值）(%s)" % sl_hs)
# 减量：面密度 每区块数/区块面积 应显著低于旧配置（3 个 / 480px 区块）
sl_density = sl_per / (sl_chunk * sl_chunk) if sl_chunk > 0 else 0.0
_old_density = 3.0 / (480.0 * 480.0)
ok(sl_density < _old_density * 0.8,
   "光源面密度已下降（%.2e → %.2e /px²，减量生效）" % (_old_density, sl_density))
# 外观改动不得顺手改照明：radius_units/intensity 维持 1.2/1.0
ok(abs(sl_r - 1.2) < 1e-6, "散落光源照明半径未随外观缩小而改变（radius_units=%.2f）" % sl_r)
ok(abs(sl_int - 1.0) < 1e-6, "散落光源照明强度未随外观缩小而改变（intensity=%.2f）" % sl_int)
# 旧版扇形光字段不得残留
ok("halo_segs" not in sl and "halo_mult" not in sl,
   "scattered_lights 无旧版扇形光字段残留（halo_segs/halo_mult）")

sl_kinds = sl.get("kinds") or []
ok(isinstance(sl_kinds, list) and len(sl_kinds) >= 3,
   "scattered_lights.kinds ≥3 类（荧光藻/贝类/夜明珠）(%s)" % len(sl_kinds))
sl_kind_ids = []
sl_weight_sum = 0
for kd in sl_kinds:
    if not isinstance(kd, dict):
        ok(False, "scattered_lights.kinds 项为对象 (%r)" % (kd,))
        continue
    kid = str(kd.get("id") or "")
    sl_kind_ids.append(kid)
    ok(kid != "", "散落光源 kind.id 非空 (%r)" % (kd,))
    kw = int(_num(kd.get("weight")))
    ok(kw > 0, "散落光源 %s.weight >0 (%s)" % (kid, kw))
    sl_weight_sum += kw
    _color3(kd.get("color"), "scattered_lights.kinds[%s].color" % kid)
    rm = _num(kd.get("radius_mult"))
    ok(rm > 0.0, "散落光源 %s.radius_mult >0 (%s)" % (kid, rm))
    # 精灵必须存在（world 目录下与 id 同名 PNG）
    kpng = os.path.join(SPRITE_WORLD_DIR, kid + ".png")
    ok(os.path.isfile(kpng), "散落光源精灵 %s.png 存在" % kid)
ok(sl_weight_sum > 0, "散落光源权重总和 >0 (%s)" % sl_weight_sum)
for need in ("glow_algae", "glow_shell", "glow_pearl"):
    ok(need in sl_kind_ids, "散落光源含类型 %s（用户点名）" % need)

# 反向：world 目录 PNG 无孤儿（塔楼 + 界桩 + 散落光源之外不允许静默残留）
if os.path.isdir(SPRITE_WORLD_DIR):
    expected = set([sprite_id]) | {str(p) for p in post_ids} | set(sl_kind_ids)
    orphans = []
    for fn in sorted(os.listdir(SPRITE_WORLD_DIR)):
        if not fn.endswith(".png"):
            continue
        if fn[:-4] not in expected:
            orphans.append(fn)
    ok(len(orphans) == 0, "world 精灵目录无孤儿 (孤儿=%s)" % (orphans if orphans else "无"))

# night.json vision 段
vision = night.get("vision") or {}
ok(isinstance(vision.get("night_restricted"), bool), "night.vision.night_restricted 为布尔")
# W23：移除默认玩家视野 radius_units，改为多光源模型
pbv = _num(vision.get("player_base_vision_units"))
ok(pbv >= 0.0, "night.vision.player_base_vision_units ≥0 (%s)" % pbv)
glow_u = _num(vision.get("lighthouse_glow_units"))
ok(glow_u > 0.0, "night.vision.lighthouse_glow_units >0 (%s → %dpx)" % (glow_u, glow_u * UNIT_TO_PIXEL))
ok(glow_u * UNIT_TO_PIXEL <= radius_px,
   "灯塔辉光半径 %dpx ≤ arena.radius %dpx（参数自洽，arena 关闭时仍成立）" % (glow_u * UNIT_TO_PIXEL, radius_px))
gi = _num(vision.get("lighthouse_glow_intensity"))
ok(0.0 < gi <= 1.0, "night.vision.lighthouse_glow_intensity ∈(0,1] (%s)" % gi)
gcr = _num(vision.get("lighthouse_glow_core_ratio"))
ok(0.0 <= gcr < 1.0, "night.vision.lighthouse_glow_core_ratio ∈[0,1) (%s)" % gcr)
ok(str(vision.get("falloff", "")) in ("linear", "smooth", "inverse_square"),
   "night.vision.falloff 为已知曲线 (%s)" % vision.get("falloff"))
rs = int(_num(vision.get("radial_segments")))
ok(rs >= 3, "night.vision.radial_segments ≥3 (%s)" % rs)
_color3(vision.get("fog_color"), "night.vision.fog_color")
fa = vision.get("fog_alpha")
ok(isinstance(fa, (int, float)) and 0.0 < float(fa) <= 1.0,
   "night.vision.fog_alpha 在 (0,1] (%s)" % fa)
ok(float(fa) >= 0.90, "night.vision.fog_alpha ≥0.90（边缘极致漆黑）")
# 命中闪光（瞬态光源）：命中点短暂开雾，让雾下的敌人显形
hf_u = _num(vision.get("hit_flash_units"))
ok(0.0 < hf_u <= 6.0, "night.vision.hit_flash_units ∈(0,6] (%s)" % hf_u)
glow_u_cmp = _num(vision.get("lighthouse_glow_units"))
ok(hf_u < glow_u_cmp,
   "night.vision.hit_flash_units < lighthouse_glow_units（命中闪光弱于灯塔 %s < %s）" % (hf_u, glow_u_cmp))
hf_i = _num(vision.get("hit_flash_intensity"))
ok(0.0 < hf_i <= 1.0, "night.vision.hit_flash_intensity ∈(0,1] (%s)" % hf_i)
hf_d = _num(vision.get("hit_flash_duration"))
ok(0.05 <= hf_d <= 2.0, "night.vision.hit_flash_duration ∈[0.05,2]s (%s)" % hf_d)
hf_m = int(_num(vision.get("hit_flash_max")))
ok(1 <= hf_m <= 64, "night.vision.hit_flash_max ∈[1,64] (%s)" % hf_m)
hf_c = _num(vision.get("hit_flash_core_ratio"))
ok(0.0 <= hf_c < 1.0, "night.vision.hit_flash_core_ratio ∈[0,1) (%s)" % hf_c)
_color3(vision.get("hit_flash_color"), "night.vision.hit_flash_color")
# 光束不穿出地图（beam length ≤ arena radius）
bl = _num(beam.get("length_units"))
ok(0.0 < bl <= radius_units,
   "光束长度 %dpx ≤ arena.radius %dpx（参数自洽）" % (bl * UNIT_TO_PIXEL, radius_px))

# ---------------------------------------------------------------------------
# 成长节奏：经验表 + 商店（2026-10-23 用户反馈「10 夜左右所有武器 7 级、被动 5 级」）
# ---------------------------------------------------------------------------
print("== 成长节奏（exp_table.json + 商店）==")
_lv = exp_table.get("levels") or {}
ok(len(_lv) >= 30, "exp_table 至少 30 级 (%d)" % len(_lv))
_e1 = int(_num((_lv.get("1") or {}).get("exp_required")))
_e10 = int(_num((_lv.get("10") or {}).get("exp_required")))
_e20 = int(_num((_lv.get("20") or {}).get("exp_required")))
ok(_e1 > 0 and _e10 > _e1 and _e20 > _e10, "经验曲线单调递增 (E1=%d E10=%d E20=%d)" % (_e1, _e10, _e20))
# 关键平衡线：第 10 夜（约累计 3000 经验）不应超过 Lv20，否则成长过快
_c20 = int(_num((_lv.get("20") or {}).get("cumulative_exp")))
_c25 = int(_num((_lv.get("25") or {}).get("cumulative_exp")))
ok(_c20 >= 3200, "累计到 Lv20 需 ≥3200 经验 (%d)（第 10 夜不应到 Lv20+）" % _c20)
ok(_c25 >= 5500, "累计到 Lv25 需 ≥5500 经验 (%d)（终局前仍有升级空间）" % _c25)

_up_shop = upgrade.get("shop") or {}
_cap = int(_num(_up_shop.get("max_purchases_per_visit")))
ok(1 <= _cap <= 6, "upgrade.shop.max_purchases_per_visit ∈[1,6] (%d)" % _cap)
_w_cost = int(_num((((weapons.get("metadata") or {}).get("shop") or {}).get("cost"))))
_p_cost = int(_num((((passives.get("metadata") or {}).get("shop") or {}).get("cost"))))
ok(_w_cost >= 40, "武器商店原价 ≥40（防商店取代升级成为主要成长来源）(%d)" % _w_cost)
ok(_p_cost >= 28, "被动商店原价 ≥28（同上）(%d)" % _p_cost)

# ---------------------------------------------------------------------------
# 2) i18n.csv 覆盖
# ---------------------------------------------------------------------------
print("== i18n.csv 覆盖 ==")
csv_path = os.path.join(CONFIG_DIR, "i18n.csv")
ok(os.path.isfile(csv_path), "i18n.csv 存在")
csv_keys = set()
bad_rows = []
if os.path.isfile(csv_path):
    with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header is None or [c.strip() for c in header[:3]] != ["key", "zh", "en"]:
            bad_rows.append((1, "bad_header", header))
        for i, row in enumerate(reader, start=2):
            if not row or all(not str(c).strip() for c in row):
                continue
            if len(row) != 3:
                bad_rows.append((i, "cols=%d" % len(row), (row[0][:48] if row else "")))
                continue
            k = (row[0] or "").strip()
            if not k or "." not in k:
                bad_rows.append((i, "bad_key", k[:48]))
                continue
            csv_keys.add(k)
ok(
    len(bad_rows) == 0,
    "i18n.csv 行结构合法（3 列 / key 含 '.'）(异常=%s)" % (bad_rows[:5] if bad_rows else "无"),
)

# 兼容旧路径：DictReader 再扫一遍（与上表应一致）
if os.path.isfile(csv_path) and not csv_keys:
    with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
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
# 2026-10-26 检查补：升级三选一卡片 meta 的中文原值必须有 i18n 映射
# 卡片 meta 直接取自 config 中文取值——weapons.json 的 attack_type、
# passives.json 的 series/category。upgrade_ui.gd 若漏一个，英文界面就会
# 残留中文（曾漏 attack_type → 显示「[Weapon] 定向弹幕」）。
# ---------------------------------------------------------------------------
_up_ui_path = os.path.join(SCRIPTS_DIR, "ui", "upgrade_ui.gd")
_up_ui = ""
if os.path.isfile(_up_ui_path):
    with open(_up_ui_path, "r", encoding="utf-8") as _fh:
        _up_ui = _fh.read()
ok(bool(_up_ui), "upgrade_ui.gd 可读取（卡片 meta 映射检查前提）")


def _mapped_keys(src: str, const_name: str):
    """抽出 const _X := { "中文": "key", ... } 里的中文键集合（粗略但够用）"""
    import re as _re
    m = _re.search(r"const\s+%s\s*:=\s*\{(.*?)\n\}" % const_name, src, _re.S)
    if not m:
        return set()
    return set(_re.findall(r'"([^"]+)"\s*:', m.group(1)))


def _entries(section):
    """config 的段既可能是 id→对象 的字典，也可能是数组；统一取出对象列表"""
    if isinstance(section, dict):
        return [v for v in section.values() if isinstance(v, dict)]
    if isinstance(section, list):
        return [v for v in section if isinstance(v, dict)]
    return []


_attack_vals = {str(x.get("attack_type", "")) for x in _entries(weapons.get("weapons"))}
_attack_vals.discard("")
_mapped_attack = _mapped_keys(_up_ui, "_ATTACK_KEYS")
ok(_attack_vals and _attack_vals <= _mapped_attack,
   "武器卡 attack_type 全部有 i18n 映射 (缺失=%s)" % sorted(_attack_vals - _mapped_attack))

_passive_entries = _entries(passives.get("passives"))
_series_vals = {str(x.get("series", "")) for x in _passive_entries}
_series_vals.discard("")
_mapped_series = _mapped_keys(_up_ui, "_SERIES_KEYS")
ok(_series_vals <= _mapped_series,
   "被动卡 series 全部有 i18n 映射 (缺失=%s)" % sorted(_series_vals - _mapped_series))

_cat_vals = {str(x.get("category", "")) for x in _passive_entries}
_cat_vals.discard("")
# 溢出奖励（潮币/血包）的 category 同样是 config 中文原值
_overflow_entries = _entries(upgrade.get("overflow_offers"))
_cat_vals |= {str(x.get("category", "")) for x in _overflow_entries}
_cat_vals.discard("")
_mapped_cat = _mapped_keys(_up_ui, "_CAT_KEYS")
ok(_cat_vals <= _mapped_cat,
   "被动卡 category 全部有 i18n 映射 (缺失=%s)" % sorted(_cat_vals - _mapped_cat))

# 溢出奖励卡的 name / desc 走 localize_config_name/desc("upgrade_offer", id, ...)，
# 是动态 key（校验器扫不到字面量）→ 这里按 config 里的 id 逐个反查
_missing_offer_keys = []
for _o in _overflow_entries:
    _oid = str(_o.get("id", ""))
    if not _oid:
        continue
    for _suffix in ("name", "desc"):
        _k = "upgrade_offer.%s.%s" % (_oid, _suffix)
        if _k not in csv_keys:
            _missing_offer_keys.append(_k)
ok(not _missing_offer_keys,
   "溢出奖励卡 name/desc 均有 i18n key (缺失=%s)" % (_missing_offer_keys or "无"))
ok("ui.upgrade.cat_overflow" in csv_keys, "溢出奖励分类 i18n key 存在")

# ---------------------------------------------------------------------------
# 2026-10-23 第二轮：光不遮挡 + 机器人视野受限（源码级断言）
# 用户反馈：「灯塔的光束不能挡住下面视野，所有的光都不应该会挡住下面内容」
#          「机器人测试的时候大多数时间都是灯塔范围外，这不符合实际玩家视野受限的情况」
# ---------------------------------------------------------------------------
print("== 光不遮挡 / 机器人视野受限（源码级） ==")
GD = SCRIPTS_DIR


def _src(rel: str) -> str:
    p = os.path.join(GD, rel)
    if not os.path.isfile(p):
        return ""
    with open(p, "r", encoding="utf-8") as fh:
        return fh.read()


def _code_only(src: str) -> str:
    """去掉 GDScript 行注释（# 开头），只保留代码——注释里的历史教训记录不算数。"""
    return "\n".join(l for l in src.splitlines() if not l.strip().startswith("#"))


# ① 独立光效层脚本存在，且用加色混合
fx_src = _src("core/vision_light_fx.gd")
ok(fx_src != "", "存在独立光效层脚本 core/vision_light_fx.gd")
ok("BLEND_MODE_ADD" in fx_src, "光效层用 BLEND_MODE_ADD（光束/命中闪光只提亮不遮挡）")
ok("draw_light_fx" in fx_src, "光效层回调 overlay.draw_light_fx（draw_* 必须在绘制节点上调用）")

# ② 雾罩本体必须保持 MIX：不得给自己挂 ADD 材质
ov_src = _src("core/vision_overlay.gd")
ok("z_index = _RENDER_Z.FOG" in ov_src, "雾罩绝对层级引用 RenderZ.FOG（恒定 80）")
rz_src = _src("core/render_z.gd")
ok(rz_src != "", "存在层级常量单一来源 core/render_z.gd")
ok("FOG: int = 80" in rz_src and "ABOVE_FOG: int = 81" in rz_src,
   "RenderZ 定义雾罩 80 / 雾上 81")
ok("LIGHT_FX_Z_INDEX: int = _RENDER_Z.ABOVE_FOG" in ov_src,
   "光效层层级引用 RenderZ.ABOVE_FOG（紧贴雾罩之上）")
# 雾罩自身 _ready 里不应出现 material = （材质只挂在光效层/灯塔/散落光源上）
ov_ready = ov_src.split("func _ready()", 1)[-1].split("func ", 1)[0] if "func _ready()" in ov_src else ""
ok("material" not in ov_ready, "雾罩 _ready() 不挂材质（保持默认 MIX，黑夜遮挡不失效）")
ok("_setup_light_fx" in ov_src, "雾罩负责创建光效层子节点")

# ③ 灯塔灯室辉光与散落光源光晕都必须是加色
bc_src = _src("world/lighthouse_beacon.gd")
ok("BLEND_MODE_ADD" in bc_src, "灯塔灯室辉光用 BLEND_MODE_ADD（不盖住塔身下方与地面）")
ls_src = _src("world/light_scatter.gd")
ok("BLEND_MODE_ADD" in ls_src, "散落光源光晕用 BLEND_MODE_ADD（不遮挡下方视野）")
ok("sprite_scale" in ls_src, "散落光源支持素材缩放 sprite_scale")
ok("halo_radius" in ls_src, "散落光源区分 halo_radius（绘制）与 radius（照明）")

# ④ 光晕圆周细分必须足够（低分段大半径 = 棱面/扇形感，v3.22 的教训）
m = re.search(r"const\s+HALO_RING_SEGS\s*:\s*int\s*=\s*(\d+)", ls_src)
ok(m is not None and int(m.group(1)) >= 20,
   "光晕圆周细分 HALO_RING_SEGS ≥20（实测 %s，否则弧长过大被读成扇形）"
   % (m.group(1) if m else "缺失"))
ok("GradientTexture2D" not in _code_only(ls_src),
   "散落光源代码不用 GradientTexture2D（运行时纹理上传时机导致光晕不显示，已回退 fan 路径；注释里的教训记录除外）")

# ⑤ 机器人必须像视野受限的真人一样待在灯塔亮圈内
bot_src = _src("debug/test_bot.gd")
ok("LIGHT_STAY_RATIO" in bot_src, "机器人有亮圈驻留常量 LIGHT_STAY_RATIO")
ok("LIGHT_PULL_WEIGHT" in bot_src, "机器人有出圈回拉权重 LIGHT_PULL_WEIGHT")
ok("_bias_toward_light" in bot_src, "机器人实现 _bias_toward_light")
ok("_compute_raw_move_direction" in bot_src,
   "机器人走位经 _compute_move_direction → _compute_raw_move_direction → _bias_toward_light 包装")
ok("is_struggling" in bot_src and "return dir" in bot_src,
   "挣扎窗口（无敌凑杀）不受亮圈约束")
# 2026-10-26 视野总开关关停：亮圈驻留前提消失，机器人必须同步停用该约束，
# 否则仍按盲打窝在灯塔旁，测出的难度/胜率与全图可见的真人脱节
ok("_vision_enabled" in bot_src and "if not _vision_enabled()" in bot_src,
   "亮圈驻留受 vision.enabled 总开关门控（关停即停用）")
# 2026-10-26 宝箱改夜间动态刷新：机器人必须有寻箱行为，否则整局 0 开箱
ok("CHEST_SEEK_RADIUS" in bot_src and "_bias_toward_chest" in bot_src,
   "机器人有寻箱行为（CHEST_SEEK_RADIUS + _bias_toward_chest）")
ok("_bias_toward_chest" in bot_src and "try_nearest_chest_position" in bot_src,
   "寻箱走 PickupSystem.try_nearest_chest_position（不自己遍历场景树）")

# ---------------------------------------------------------------------------
print("------------------------------------------------------------")
print("校验项=%d 失败=%d" % (checked, failed))
sys.exit(1 if failed else 0)
