#!/usr/bin/env python3
# ============================================================================
# generate_pixel_sprites.py — 生成 Tidekeeper 角色/敌人/地面像素精灵
#
# 与 generate_ui_pixel_assets.py 共用同一套 Canvas / PNG 编码 / 调色板工具。
#
# 画法：程序化组合基本体（椭圆团块 + 眼睛 + 肢体 + 尖刺），
#       每个团块自动做「左上受光 / 右下压暗 / 1px 深色描边」，
#       比纯色方块有体积感，也比逐像素手绘更容易批量调。
#
# 输出：
#   godot_project/assets/sprites/enemies/<id>.png   9 只杂兵（16×16 逻辑）
#   godot_project/assets/sprites/enemies/<id>.png 3 只 Boss（与 config/bosses.json 的 id 对齐，不带 boss_ 前缀）
#   godot_project/assets/sprites/player/<id>.png    角色（16×16 逻辑）
#   godot_project/assets/sprites/ground/floor_<n>.png 地面砖（16×16 逻辑，可平铺）
# 逻辑像素统一 ×BLOCK 放大。
# 工具化用法（供 AI agent 调用）：
#   python tools/generate_pixel_sprites.py all                 # 生成全部精灵
#   python tools/generate_pixel_sprites.py one <cat> <id>       # 生成单个（如 one player stargazer）
#   python tools/generate_pixel_sprites.py list                # 列出可用 category/id
#   python tools/generate_pixel_sprites.py check               # 校验 config id ↔ png 是否对齐
# 也可 --sheet=out.png 拼对照表；或 import 本模块调用
# generate_one / generate_all / list_ids / check_alignment。
# ============================================================================
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_ui_pixel_assets import (  # noqa: E402
    BLOCK,
    Canvas,
    compose_sheet,
    shade,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "godot_project", "assets", "sprites")

OUTLINE = (22, 16, 30, 255)

# 敌人配色（每种一套 主色/暗部/高光）
C = {
    "goblin":  ((96, 176, 132, 255), (52, 112, 88, 255), (168, 232, 184, 255)),
    "crab":    ((140, 150, 168, 255), (78, 86, 104, 255), (206, 216, 234, 255)),
    "jelly":   ((196, 128, 208, 255), (118, 66, 138, 255), (240, 190, 248, 255)),
    "diver":   ((70, 96, 148, 255), (34, 50, 86, 255), (128, 176, 232, 255)),
    "bomb":    ((214, 118, 74, 255), (134, 62, 38, 255), (255, 186, 130, 255)),
    "raven":   ((84, 72, 110, 255), (44, 36, 62, 255), (140, 126, 178, 255)),
    "summon":  ((126, 100, 186, 255), (66, 48, 110, 255), (186, 160, 240, 255)),
    "pike":    ((92, 128, 172, 255), (44, 66, 102, 255), (166, 200, 236, 255)),
    "reef":    ((110, 130, 104, 255), (56, 70, 54, 255), (168, 190, 152, 255)),
    "archon":  ((150, 190, 226, 255), (62, 92, 138, 255), (226, 244, 255, 255)),
    "queen":   ((216, 140, 220, 255), (124, 64, 146, 255), (255, 208, 255, 255)),
    "star":    ((232, 176, 92, 255), (140, 92, 36, 255), (255, 226, 150, 255)),
    "keeper":  ((226, 196, 132, 255), (140, 104, 56, 255), (255, 236, 190, 255)),
}
GOLD = (242, 196, 88, 255)
GOLD_HI = (255, 236, 168, 255)
WHITE = (246, 244, 255, 255)


# ----------------------------------------------------------------------------
# 基本体
# ----------------------------------------------------------------------------
def blob(c: Canvas, cx: float, cy: float, rx: float, ry: float, tone, oc=OUTLINE,
         shade_it: bool = True) -> set:
    """椭圆团块：自动左上受光 / 右下压暗 / 1px 描边。返回内部像素集合。"""
    main, dark, hi = tone
    inside = set()
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            nx = (x - cx) / max(rx, 0.001)
            ny = (y - cy) / max(ry, 0.001)
            if nx * nx + ny * ny <= 1.0:
                inside.add((x, y))
    for (x, y) in inside:
        col = main
        if shade_it:
            t = ((x - cx) / max(rx, 0.001)) * 0.55 + ((y - cy) / max(ry, 0.001)) * 0.85
            if t < -0.50:
                col = hi
            elif t > 0.42:
                col = dark
        c.px(x, y, col)
    for (x, y) in inside:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (x + dx, y + dy) not in inside:
                c.px(x, y, oc)
                break
    return inside


def eye(c: Canvas, x: int, y: int, size: int = 1, white=WHITE, pupil=OUTLINE) -> None:
    """方眼：size=1 为 2×2 白 + 1 黑瞳。"""
    if size <= 1:
        c.px(x, y, white)
        c.px(x + 1, y, white)
        c.px(x, y + 1, white)
        c.px(x + 1, y + 1, white)
        c.px(x + 1, y + 1, pupil)
    else:
        c.fill_rect(x, y, x + size, y + size, white)
        c.fill_rect(x + size - 1, y + size - 1, x + size - 1, y + size - 1, pupil)


def line(c: Canvas, x0: int, y0: int, x1: int, y1: int, color, thick: int = 1) -> None:
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    x, y = x0, y0
    while True:
        for oy in range(thick):
            for ox in range(thick):
                c.px(x + ox, y + oy, color)
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


def spike(c: Canvas, x: int, y: int, dx: int, dy: int, length: int, color, oc=OUTLINE) -> None:
    """三角尖刺（用于鳍 / 角 / 尾）。"""
    for i in range(length):
        px, py = x + dx * i, y + dy * i
        half = max(0, (length - i) // 2)
        for j in range(-half, half + 1):
            c.px(px + (j if dx == 0 else 0), py + (j if dy == 0 else 0), color)
    c.px(x + dx * length, y + dy * length, oc)


def ground_tile(seed: int, base, speck, crack) -> Canvas:
    """可平铺的地面砖：底色 + 随机斑点 + 少量裂纹。"""
    c = Canvas(16, 16)
    rnd = random.Random(seed)
    c.fill_rect(0, 0, 15, 15, base)
    for _ in range(26):
        x, y = rnd.randrange(16), rnd.randrange(16)
        c.px(x, y, speck)
    for _ in range(4):
        x, y = rnd.randrange(3, 13), rnd.randrange(3, 13)
        line(c, x, y, x + rnd.randrange(-2, 3), y + rnd.randrange(1, 3), crack)
    return c


# ----------------------------------------------------------------------------
# 杂兵（16×16）
# ----------------------------------------------------------------------------
def e_goblin() -> Canvas:
    """小水鬼：矮胖水鬼，大眼 + 两侧鳍。"""
    t = C["goblin"]
    c = Canvas(16, 16)
    blob(c, 8, 10, 5.4, 4.6, t)                 # 身体
    blob(c, 8, 5.6, 4.0, 3.4, t)                # 头
    spike(c, 2, 10, -1, 0, 2, t[1])             # 左鳍
    spike(c, 13, 10, 1, 0, 2, t[1])             # 右鳍
    eye(c, 5, 5)
    eye(c, 9, 5)
    c.hline(6, 9, 8, t[1])                      # 嘴
    return c


def e_crab() -> Canvas:
    """铁壳蟹：厚甲壳 + 双钳 + 短腿。"""
    t = C["crab"]
    c = Canvas(16, 16)
    for i in range(3):                          # 腿
        c.px(3 - i, 12 + i, t[1])
        c.px(12 + i, 12 + i, t[1])
    blob(c, 8, 9, 5.6, 3.8, t)                  # 壳
    blob(c, 2.5, 8, 2.2, 2.2, t)                # 左钳
    blob(c, 13.5, 8, 2.2, 2.2, t)               # 右钳
    c.hline(5, 10, 7, t[1])                     # 壳缝
    eye(c, 5, 6)
    eye(c, 9, 6)
    return c


def e_elite_crab() -> Canvas:
    """巨钳王（第 5 夜命名精英）：大号铁壳蟹 + 巨钳 + 金冠。24×24 逻辑 px。"""
    t = C["crab"]
    c = Canvas(24, 24)
    for i in range(3):                          # 腿（加粗）
        c.fill_rect(4 - i, 17 + i, 6 - i, 18 + i, t[1])
        c.fill_rect(17 + i, 17 + i, 19 + i, 18 + i, t[1])
    blob(c, 12, 14, 9.0, 6.2, t)                # 壳（大号）
    # 金冠：壳顶三齿
    spike(c, 8, 7, 0, -1, 3, GOLD)
    spike(c, 12, 6, 0, -1, 4, GOLD)
    spike(c, 16, 7, 0, -1, 3, GOLD)
    # 巨钳（左右各一，带钳口缝）
    blob(c, 3.0, 13, 3.2, 2.8, t)
    blob(c, 21.0, 13, 3.2, 2.8, t)
    c.fill_rect(1, 11, 4, 12, t[1])             # 左钳上颚缝
    c.fill_rect(19, 11, 22, 12, t[1])           # 右钳上颚缝
    c.hline(8, 15, 15, t[1])                    # 壳缝
    for x in (9, 12, 15):                       # 壳上金铆
        c.px(x, 11, GOLD)
    # 怒目：眼 + 压暗眉脊
    eye(c, 8, 9)
    eye(c, 14, 9)
    c.hline(7, 10, 8, t[1])
    c.hline(13, 16, 8, t[1])
    return c


def e_jelly() -> Canvas:
    """水母浮游：伞盖 + 4 条触手。"""
    t = C["jelly"]
    c = Canvas(16, 16)
    blob(c, 8, 6.5, 5.6, 4.2, t)                # 伞盖
    c.hline(3, 12, 9, t[1])                     # 伞沿
    for i, x in enumerate((4, 6, 9, 11)):       # 触手
        line(c, x, 10, x + (1 if i % 2 else -1), 14, t[1])
    eye(c, 5, 6)
    eye(c, 9, 6)
    return c


def e_diver() -> Canvas:
    """深潜者：兜帽 + 发光眼。"""
    t = C["diver"]
    c = Canvas(16, 16)
    blob(c, 8, 11, 4.8, 4.2, t)                 # 身
    blob(c, 8, 5.5, 4.2, 4.2, t)                # 兜帽
    c.fill_rect(5, 5, 10, 8, (18, 26, 44, 255))  # 帽内阴影
    c.px(6, 6, (150, 226, 255, 255))
    c.px(9, 6, (150, 226, 255, 255))
    c.px(6, 7, (90, 170, 220, 255))
    c.px(9, 7, (90, 170, 220, 255))
    return c


def e_bomb() -> Canvas:
    """爆炸贝：贝壳 + 引线 + 火星。"""
    t = C["bomb"]
    c = Canvas(16, 16)
    blob(c, 8, 10, 5.6, 4.4, t)                 # 壳
    for x in range(4, 13, 2):                   # 壳纹
        c.px(x, 9, t[1])
    line(c, 8, 6, 10, 2, t[1])                  # 引线
    c.px(11, 1, GOLD_HI)
    c.px(10, 1, GOLD)
    eye(c, 5, 9)
    eye(c, 9, 9)
    return c


def e_raven() -> Canvas:
    """鸦群：展翅剪影 + 尖喙。"""
    t = C["raven"]
    c = Canvas(16, 16)
    spike(c, 8, 8, -1, -1, 4, t[1])             # 左翼
    spike(c, 8, 8, 1, -1, 4, t[1])              # 右翼
    blob(c, 8, 9, 3.0, 3.6, t)                  # 身
    blob(c, 8, 5.5, 2.4, 2.2, t)                # 头
    c.px(8, 5, GOLD)                            # 喙
    c.px(7, 5, GOLD_HI)
    c.px(7, 5, (255, 200, 60, 255))
    c.px(10, 5, (255, 220, 90, 255))            # 眼
    return c


def e_summon() -> Canvas:
    """潮汐召唤师：长袍 + 法杖 + 顶端宝珠。"""
    t = C["summon"]
    c = Canvas(16, 16)
    for y in range(8, 15):                      # 长袍（梯形）
        w = 2 + (y - 8) // 2
        c.fill_rect(8 - w, y, 8 + w, y, t[0] if y < 13 else t[1])
    blob(c, 8, 5.5, 3.2, 3.2, t)                # 头兜
    c.px(7, 5, (240, 220, 255, 255))
    c.px(9, 5, (240, 220, 255, 255))
    line(c, 13, 3, 13, 14, (120, 96, 60, 255))  # 杖
    blob(c, 13, 2.5, 1.6, 1.6, (GOLD, (150, 100, 30, 255), GOLD_HI))
    return c


def e_pike() -> Canvas:
    """渊潮长枪兵：甲胄 + 长枪 + 盾。"""
    t = C["pike"]
    c = Canvas(16, 16)
    blob(c, 8, 10, 4.2, 4.2, t)                 # 身
    blob(c, 8, 5, 3.2, 3.2, t)                  # 头
    c.fill_rect(6, 4, 9, 6, t[1])               # 面甲
    c.px(7, 5, (200, 240, 255, 255))
    c.px(8, 5, (200, 240, 255, 255))
    line(c, 2, 14, 13, 2, (150, 170, 196, 255), 1)   # 长枪
    c.px(13, 1, (232, 244, 255, 255))                # 枪尖
    blob(c, 12.5, 11, 2.4, 3.0, ((120, 150, 190, 255), (70, 90, 120, 255), (180, 205, 230, 255)))  # 盾
    return c


def e_reef() -> Canvas:
    """暗礁巨人（24×24）：岩石堆成的巨躯。"""
    t = C["reef"]
    c = Canvas(24, 24)
    blob(c, 12, 16, 8.0, 6.6, t)                # 躯干
    blob(c, 12, 7, 5.0, 4.6, t)                 # 头
    blob(c, 5, 13, 3.0, 2.6, t)                 # 左臂
    blob(c, 19, 13, 3.0, 2.6, t)                # 右臂
    for (x, y, r) in ((7, 4, 1.6), (16, 5, 1.4), (10, 18, 1.8), (17, 17, 1.4)):
        blob(c, x, y, r, r * 0.9, t)            # 礁石凸起
    eye(c, 9, 7)
    eye(c, 14, 7)
    c.hline(10, 14, 10, t[1])
    return c


# ----------------------------------------------------------------------------
# Boss（24×24）
# ----------------------------------------------------------------------------
def b_archon() -> Canvas:
    """潮汐执政官：长袍 + 王冠 + 三叉戟。"""
    t = C["archon"]
    c = Canvas(24, 24)
    for y in range(12, 22):                     # 长袍
        w = 3 + (y - 12) // 2
        c.fill_rect(12 - w, y, 12 + w, y, t[0] if y < 20 else t[1])
    blob(c, 12, 8, 4.6, 4.4, t)                 # 头
    c.px(10, 8, (240, 252, 255, 255))
    c.px(14, 8, (240, 252, 255, 255))
    # 王冠
    for x, h in ((8, 2), (10, 3), (12, 4), (14, 3), (16, 2)):
        c.fill_rect(x, 4 - h, x, 3, GOLD)
    c.hline(8, 16, 3, GOLD_HI)
    # 三叉戟
    line(c, 21, 4, 21, 21, (150, 170, 196, 255))
    for dx in (-2, 0, 2):
        c.fill_rect(21 + dx, 1, 21 + dx, 3, (232, 244, 255, 255))
    c.hline(19, 23, 3, (232, 244, 255, 255))
    return c


def b_queen() -> Canvas:
    """水母女王：巨型伞盖 + 王冠 + 长触手。"""
    t = C["queen"]
    c = Canvas(24, 24)
    blob(c, 12, 9, 9.0, 6.4, t)                 # 伞盖
    c.hline(4, 20, 13, t[1])                    # 伞沿
    for i, x in enumerate((6, 10, 14, 18)):     # 触手
        line(c, x, 14, x + (2 if i % 2 else -2), 21, t[1])
    for x, h in ((8, 2), (11, 3), (13, 3), (16, 2)):   # 王冠
        c.fill_rect(x, 3 - h, x, 2, GOLD)
    c.hline(8, 16, 2, GOLD_HI)
    eye(c, 9, 8, 2)
    eye(c, 14, 8, 2)
    return c


def b_star() -> Canvas:
    """噬星者：星形躯体 + 中央独眼。"""
    t = C["star"]
    c = Canvas(24, 24)
    cx, cy = 12, 12
    pts = []
    for i in range(10):
        ang = -1.5708 + i * 3.14159 / 5.0
        r = 10.0 if i % 2 == 0 else 4.6
        pts.append((cx + int(round(r * __import__("math").cos(ang))),
                    cy + int(round(r * __import__("math").sin(ang)))))
    # 扫描线填充多边形
    for y in range(0, 24):
        xs = []
        for i in range(len(pts)):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % len(pts)]
            if (y0 <= y < y1) or (y1 <= y < y0):
                xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(xs[i]) + 1, int(xs[i + 1])):
                nx = (x - cx) / 10.0
                ny = (y - cy) / 10.0
                tt = nx * 0.55 + ny * 0.85
                c.px(x, y, t[2] if tt < -0.35 else (t[1] if tt > 0.30 else t[0]))
    # 描边
    for y in range(24):
        for x in range(24):
            if c.buf[y * BLOCK][x * BLOCK][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < 24 and 0 <= ny < 24) or c.buf[ny * BLOCK][nx * BLOCK][3] == 0:
                    c.px(x, y, OUTLINE)
                    break
    blob(c, 12, 12, 3.4, 3.4, ((30, 22, 40, 255), (16, 12, 24, 255), (56, 40, 72, 255)))
    c.px(12, 12, (255, 120, 90, 255))
    c.px(11, 11, (255, 190, 150, 255))
    return c


# ----------------------------------------------------------------------------
# 玩家
# ----------------------------------------------------------------------------
def p_keeper() -> Canvas:
    """守夜人：斗篷 + 提灯（暖光）。"""
    t = C["keeper"]
    c = Canvas(16, 16)
    for y in range(7, 15):                      # 斗篷
        w = 3 + (y - 7) // 3
        c.fill_rect(8 - w, y, 8 + w, y, t[0] if y < 13 else t[1])
    blob(c, 8, 5, 3.2, 3.2, t)                  # 头
    c.fill_rect(6, 4, 9, 6, (40, 30, 26, 255))  # 帽檐
    c.px(7, 6, (255, 236, 190, 255))
    c.px(9, 6, (255, 236, 190, 255))
    blob(c, 13, 11, 1.8, 2.0, (GOLD, (150, 100, 30, 255), GOLD_HI))   # 提灯
    c.px(13, 10, (255, 246, 210, 255))
    return c


def p_blacksmith() -> Canvas:
    """铁匠：宽肩 + 围裙 + 铁锤。"""
    skin = ((150, 120, 96, 255), (90, 66, 50, 255), (200, 170, 140, 255))
    apron = ((110, 86, 66, 255), (70, 50, 36, 255), (150, 120, 96, 255))
    c = Canvas(16, 16)
    for y in range(7, 15):                      # 宽身（铁匠更壮）
        w = 4 + (y - 7) // 2
        c.fill_rect(8 - w, y, 8 + w, y, apron[0] if y < 12 else apron[1])
    blob(c, 8, 5, 3.4, 3.4, skin)               # 大头
    c.fill_rect(5, 3, 10, 6, (60, 44, 36, 255))  # 头发
    c.px(7, 6, (40, 30, 26, 255)); c.px(9, 6, (40, 30, 26, 255))
    c.fill_rect(4, 9, 11, 11, apron[0])           # 围裙
    c.fill_rect(12, 7, 14, 10, STEEL_T[0])        # 锤头
    c.fill_rect(12, 7, 14, 7, STEEL_T[2])
    c.fill_rect(13, 10, 13, 14, (90, 70, 40, 255))  # 柄
    return c


def p_stargazer() -> Canvas:
    """星象师：长袍 + 兜帽 + 胸前发光星核。"""
    robe = ((70, 64, 120, 255), (40, 36, 78, 255), (120, 112, 180, 255))  # 紫袍
    c = Canvas(16, 16)
    for y in range(7, 15):                      # 长袍（梯形）
        w = 2 + (y - 7) // 2
        c.fill_rect(8 - w, y, 8 + w, y, robe[0] if y < 13 else robe[1])
    blob(c, 8, 5, 3.0, 3.2, robe)               # 兜帽头
    c.fill_rect(6, 4, 9, 6, robe[1])             # 帽檐阴影
    c.px(7, 6, (210, 220, 255, 255)); c.px(9, 6, (210, 220, 255, 255))  # 冷光眼
    c.px(8, 11, (255, 240, 150, 255))            # 星核
    c.px(7, 11, (160, 150, 90, 255)); c.px(9, 11, (160, 150, 90, 255))
    c.px(8, 10, (255, 250, 200, 255)); c.px(8, 12, (255, 250, 200, 255))
    return c



# ----------------------------------------------------------------------------
# 武器 / 被动图标（16×16 逻辑，按资源名逐个组合基本体）
# ----------------------------------------------------------------------------
STEEL_T = ((168, 186, 212, 255), (104, 120, 148, 255), (232, 242, 255, 255))
GOLD_T = ((242, 181, 60, 255), (168, 112, 26, 255), (255, 232, 158, 255))
RED_T = ((214, 84, 70, 255), (140, 44, 34, 255), (255, 158, 128, 255))
TEAL_T = ((95, 212, 196, 255), (40, 120, 110, 255), (190, 250, 240, 255))
PURP_T = ((164, 120, 214, 255), (92, 60, 150, 255), (222, 196, 252, 255))
AMBER_T = ((255, 196, 92, 255), (170, 110, 30, 255), (255, 236, 170, 255))
WHITE_T = ((238, 242, 255, 255), (170, 180, 210, 255), (255, 255, 255, 255))


def ring(c: Canvas, cx: float, cy: float, r: float, color) -> None:
    """空心圆描边（1px 逻辑）。"""
    for a in range(0, 360, 6):
        rad = math.radians(a)
        c.px(int(cx + math.cos(rad) * r), int(cy + math.sin(rad) * r), color)


def w_harpoon() -> Canvas:
    """鱼叉枪：斜置枪杆 + 三叉矛头 + 握柄。"""
    t = STEEL_T
    c = Canvas(16, 16)
    c.fill_rect(2, 13, 3, 14, (90, 70, 40, 255))      # 握柄
    line(c, 4, 12, 11, 4, t[0])                         # 枪杆
    line(c, 4, 11, 11, 3, t[1])
    for dx in (-1, 0, 1):                               # 三叉矛头
        line(c, 11 + dx, 3, 13 + dx, 1, t[0])
    c.px(13, 1, t[2])
    line(c, 4, 12, 7, 9, t[1])                         # 倒钩
    return c


def w_holy_fire() -> Canvas:
    """灯塔圣火：水滴火苗 + 内焰高光 + 底座。"""
    t = AMBER_T
    c = Canvas(16, 16)
    blob(c, 8, 7, 3.4, 4.2, ((255, 150, 60, 255), (150, 70, 20, 255), (255, 220, 130, 255)))
    blob(c, 8, 9, 1.8, 2.2, ((255, 240, 170, 255), (255, 190, 90, 255), (255, 255, 220, 255)))
    c.fill_rect(5, 13, 10, 14, (90, 70, 50, 255))      # 灯座
    return c


def w_anchor_hammer() -> Canvas:
    """锚锤：锤头 + 锚尖 + 握柄。"""
    t = STEEL_T
    c = Canvas(16, 16)
    c.fill_rect(4, 3, 11, 7, t[0])                      # 锤头
    c.fill_rect(4, 3, 11, 3, t[2])
    c.fill_rect(4, 7, 11, 7, t[1])
    line(c, 7, 7, 7, 14, (90, 70, 40, 255))            # 柄
    line(c, 7, 14, 6, 15, t[0])                         # 锚尖
    line(c, 7, 14, 8, 15, t[0])
    return c


def w_spore() -> Canvas:
    """水母孢子：孢囊 + 斑点 + 小刺。"""
    t = TEAL_T
    c = Canvas(16, 16)
    blob(c, 8, 8, 4.6, 4.6, t)
    c.px(6, 6, t[2]); c.px(10, 7, t[2]); c.px(8, 10, t[2])
    for a in range(0, 360, 45):
        rad = math.radians(a)
        spike(c, int(8 + math.cos(rad) * 4), int(8 + math.sin(rad) * 4),
              int(math.cos(rad) * 2), int(math.sin(rad) * 2), 2, t[1])
    return c


def w_storm_cloud() -> Canvas:
    """雷暴云：云团 + 闪电。"""
    t = (180, 190, 210, 255)
    c = Canvas(16, 16)
    blob(c, 6, 5, 3.0, 2.6, (t, (110, 120, 140, 255), (235, 242, 255, 255)))
    blob(c, 11, 5, 3.2, 2.8, (t, (110, 120, 140, 255), (235, 242, 255, 255)))
    blob(c, 8, 7, 4.0, 3.0, (t, (110, 120, 140, 255), (235, 242, 255, 255)))
    line(c, 8, 9, 7, 12, (255, 240, 120, 255))         # 闪电
    line(c, 7, 12, 9, 12, (255, 240, 120, 255))
    line(c, 9, 12, 8, 15, (255, 240, 120, 255))
    return c


def w_jellyfish_cannon() -> Canvas:
    """水母炮：炮管 + 炮口水母。"""
    t = PURP_T
    c = Canvas(16, 16)
    c.fill_rect(2, 7, 9, 10, (90, 70, 50, 255))        # 炮身
    c.fill_rect(2, 7, 9, 7, (130, 110, 90, 255))
    blob(c, 11, 5, 3.4, 3.0, t)                         # 炮口水母
    c.hline(8, 14, 7, t[1])
    return c


def w_anchor_chain() -> Canvas:
    """锚链：三节铁链环。"""
    t = STEEL_T
    c = Canvas(16, 16)
    ring(c, 5, 4, 2.4, t[1]); ring(c, 5, 4, 1.4, t[0])
    ring(c, 9, 8, 2.4, t[1]); ring(c, 9, 8, 1.4, t[0])
    ring(c, 5, 12, 2.4, t[1]); ring(c, 5, 12, 1.4, t[0])
    line(c, 5, 6, 9, 6, t[2])                            # 高光连接
    return c


def w_albatross() -> Canvas:
    """信天翁：展翅 + 身躯 + 喙。"""
    t = WHITE_T
    c = Canvas(16, 16)
    spike(c, 8, 9, -1, -1, 5, t[0])                     # 左翼
    spike(c, 8, 9, 1, -1, 5, t[0])
    blob(c, 8, 10, 2.4, 3.2, t)
    c.px(8, 7, (250, 200, 60, 255))                      # 喙
    c.px(7, 8, (30, 30, 40, 255))                         # 眼
    return c


def p_pearl() -> Canvas:
    """夜明珠：发光珠 + 高光 + 星芒。"""
    c = Canvas(16, 16)
    blob(c, 8, 9, 4.6, 4.6, ((230, 240, 255, 255), (150, 170, 210, 255), (255, 255, 255, 255)))
    c.px(6, 7, (255, 255, 255, 255)); c.px(5, 7, (255, 255, 255, 255))
    c.px(8, 3, (255, 255, 255, 255)); c.px(8, 2, (255, 255, 255, 255))
    return c


def p_amulet() -> Canvas:
    """护身符：链弧 + 宝石。"""
    c = Canvas(16, 16)
    ring(c, 8, 4, 3.4, (120, 130, 160, 255))             # 链弧
    blob(c, 8, 11, 3.0, 3.2, GOLD_T)
    c.px(7, 9, (255, 255, 220, 255))
    return c


def p_tide_bell() -> Canvas:
    """潮信铃：铃身 + 铃舌。"""
    t = GOLD_T
    c = Canvas(16, 16)
    blob(c, 8, 8, 4.2, 4.0, t)
    c.fill_rect(4, 8, 12, 11, t[1])
    c.hline(4, 12, 12, t[2])
    c.px(8, 4, t[1])                                     # 顶钮
    c.px(8, 13, (90, 70, 40, 255))                        # 铃舌
    return c


def p_lamp_core() -> Canvas:
    """灯芯石：发光核 + 外壳。"""
    c = Canvas(16, 16)
    blob(c, 8, 9, 4.4, 4.0, ((110, 90, 70, 255), (60, 48, 36, 255), (150, 130, 100, 255)))
    blob(c, 8, 9, 2.2, 2.2, AMBER_T)
    return c


def p_tide_compass() -> Canvas:
    """潮汐罗盘：表盘 + 指针。"""
    c = Canvas(16, 16)
    ring(c, 8, 8, 5.4, (120, 130, 160, 255))
    blob(c, 8, 8, 4.6, 4.6, ((60, 70, 90, 255), (30, 38, 52, 255), (120, 140, 170, 255)))
    line(c, 8, 8, 5, 4, (255, 120, 90, 255))             # 指针
    line(c, 8, 8, 11, 12, (220, 220, 230, 255))
    return c


def p_lamp_oil() -> Canvas:
    """燃灯油：油瓶 + 软木塞。"""
    c = Canvas(16, 16)
    c.fill_rect(7, 2, 9, 3, (120, 80, 50, 255))         # 塞
    c.fill_rect(7, 3, 9, 5, (150, 160, 190, 255))        # 颈
    blob(c, 8, 10, 4.2, 4.4, ((120, 200, 220, 255), (60, 120, 150, 255), (190, 240, 250, 255)))
    return c


def p_iron_chain() -> Canvas:
    """铁链：两节粗链环。"""
    t = STEEL_T
    c = Canvas(16, 16)
    ring(c, 6, 6, 3.0, t[1]); ring(c, 6, 6, 1.8, t[0])
    ring(c, 11, 11, 3.0, t[1]); ring(c, 11, 11, 1.8, t[0])
    return c


def p_humus() -> Canvas:
    """腐殖质：土堆 + 嫩芽。"""
    c = Canvas(16, 16)
    blob(c, 8, 12, 5.4, 2.6, ((90, 70, 50, 255), (50, 38, 28, 255), (130, 110, 80, 255)))
    line(c, 8, 12, 8, 6, (90, 200, 120, 255))           # 茎
    blob(c, 6, 6, 1.8, 1.6, ((130, 220, 150, 255), (60, 140, 90, 255), (200, 250, 210, 255)))
    blob(c, 10, 7, 1.8, 1.6, ((130, 220, 150, 255), (60, 140, 90, 255), (200, 250, 210, 255)))
    return c


def p_storm_flask() -> Canvas:
    """风暴瓶：瓶身 + 内部闪电。"""
    c = Canvas(16, 16)
    blob(c, 8, 10, 4.2, 4.4, ((150, 180, 220, 255), (80, 110, 160, 255), (210, 235, 255, 255)))
    c.fill_rect(7, 3, 9, 5, (150, 180, 220, 255))
    line(c, 8, 7, 7, 10, (255, 240, 120, 255))
    line(c, 7, 10, 9, 10, (255, 240, 120, 255))
    line(c, 9, 10, 8, 13, (255, 240, 120, 255))
    return c


def p_abyss_eye() -> Canvas:
    """深海之眼：眼眶 + 瞳 + 高光。"""
    c = Canvas(16, 16)
    blob(c, 8, 8, 5.6, 4.0, ((70, 90, 130, 255), (30, 40, 70, 255), (120, 150, 200, 255)))
    blob(c, 8, 8, 2.6, 2.6, ((30, 22, 40, 255), (16, 12, 24, 255), (56, 40, 72, 255)))
    c.px(9, 7, (255, 120, 90, 255))
    c.px(8, 6, (255, 200, 160, 255))
    return c


def p_coral_barrier() -> Canvas:
    """珊瑚屏障：分叉珊瑚 + 底座。"""
    t = ((230, 130, 150, 255), (150, 70, 90, 255), (255, 190, 205, 255))
    c = Canvas(16, 16)
    line(c, 8, 14, 8, 6, t[0])                          # 主干
    line(c, 8, 10, 4, 5, t[0])                          # 左叉
    line(c, 8, 10, 12, 5, t[0])                         # 右叉
    c.px(4, 4, t[2]); c.px(12, 4, t[2]); c.px(8, 5, t[2])
    c.fill_rect(4, 14, 12, 15, t[1])
    return c


def p_exp_sac() -> Canvas:
    """经验囊：囊袋 + 束口 + 星纹。"""
    c = Canvas(16, 16)
    blob(c, 8, 10, 4.6, 4.0, TEAL_T)
    c.fill_rect(6, 4, 10, 6, (60, 120, 110, 255))      # 束口
    c.px(8, 6, (255, 255, 220, 255))                    # 星纹
    c.px(7, 9, (255, 255, 220, 255)); c.px(9, 9, (255, 255, 220, 255))
    return c


# ----------------------------------------------------------------------------
# 召唤物（summons 类别；2026-10-22 召唤类武器可视化）
# ----------------------------------------------------------------------------

SUMMON_TONES = {
    # 水母召唤物：青蓝调（与敌方紫水母 e_jelly 区分）
    "jellyfish": ((110, 210, 220, 255), (40, 130, 150, 255), (200, 250, 255, 255)),
    # 信天翁：白羽 + 黄喙（与敌方紫鸦 e_raven 区分）
    "albatross": ((238, 242, 250, 255), (150, 160, 185, 255), (255, 255, 255, 255)),
}


def s_jellyfish() -> Canvas:
    """水母召唤物：半圆伞盖 + 4 条长触手 + 双眼（24x24）。"""
    t = SUMMON_TONES["jellyfish"]
    c = Canvas(24, 24)
    blob(c, 12, 10, 8.0, 6.5, t)                  # 伞盖
    c.hline(5, 18, 18, t[1])                      # 伞沿
    for i, x in enumerate((6, 9, 15, 18)):        # 触手（波浪）
        line(c, x, 17, x + (1 if i % 2 else -1), 23, t[1])
        c.px(x + (1 if i % 2 else -1), 23, t[2])
    eye(c, 9, 9, size=1)
    eye(c, 15, 9, size=1)
    c.px(12, 5, t[2]); c.px(11, 4, t[2])          # 伞顶高光
    return c


def s_albatross() -> Canvas:
    """信天翁召唤物：展翼俯冲姿势 + 尖喙 + 尾羽（24x24）。"""
    t = SUMMON_TONES["albatross"]
    c = Canvas(24, 24)
    spike(c, 12, 11, -1, -1, 9, t[1])             # 左翼（前缘指上）
    spike(c, 12, 11, 1, -1, 9, t[1])              # 右翼
    for i in range(3):                            # 翼上覆羽
        c.px(12 - 5 - i, 11 - 4 - i, t[0])
        c.px(12 + 5 + i, 11 - 4 - i, t[0])
    blob(c, 12, 12, 2.8, 4.2, t)                  # 身
    blob(c, 12, 7.5, 2.2, 2.2, t)                 # 头
    c.px(12, 7, GOLD)                             # 喙
    c.px(12, 8, GOLD_HI)
    c.px(11, 6, OUTLINE); c.px(13, 6, OUTLINE)    # 眼
    line(c, 12, 16, 10, 21, t[1])                 # 尾羽
    line(c, 12, 16, 14, 21, t[1])
    return c


SUMMON_ICONS = {
    "jellyfish": s_jellyfish,
    "albatross": s_albatross,
}


WEAPON_ICONS = {
    "harpoon": w_harpoon,
    "holy_fire": w_holy_fire,
    "anchor_hammer": w_anchor_hammer,
    "spore": w_spore,
    "storm_cloud": w_storm_cloud,
    "jellyfish_cannon": w_jellyfish_cannon,
    "anchor_chain": w_anchor_chain,
    "albatross": w_albatross,
}

PASSIVE_ICONS = {
    "pearl": p_pearl,
    "amulet": p_amulet,
    "tide_bell": p_tide_bell,
    "lamp_core": p_lamp_core,
    "tide_compass": p_tide_compass,
    "lamp_oil": p_lamp_oil,
    "iron_chain": p_iron_chain,
    "humus": p_humus,
    "storm_flask": p_storm_flask,
    "abyss_eye": p_abyss_eye,
    "coral_barrier": p_coral_barrier,
    "exp_sac": p_exp_sac,
}


# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# 公共工具 API（供其他 AI agent / 脚本导入或经 CLI 调用）
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# 世界装饰（灯塔塔楼 / 竞技场礁石边界）— 2026-10-22 用户反馈：
# 「灯塔应是有高度的塔+光束」「边界要有明确障碍物」。塔楼 32×56 逻辑
# （≈玩家 3 倍高），底部中心对齐（碰撞圆心即塔基）；礁石 20×28 逻辑，
# 底部对齐，沿竞技场圆周实例化。
# ----------------------------------------------------------------------------
_STONE = ((198, 202, 216, 255), (96, 102, 128, 255), (240, 243, 252, 255))
_BAND = ((188, 76, 68, 255), (108, 38, 36, 255), (230, 132, 120, 255))
_IRON = ((86, 94, 118, 255), (40, 46, 68, 255), (142, 152, 182, 255))
_LAMP = ((255, 216, 122, 255), (198, 130, 42, 255), (255, 248, 214, 255))
_ROOF = ((98, 110, 142, 255), (44, 52, 80, 255), (152, 164, 198, 255))
_REEF = ((112, 132, 106, 255), (54, 70, 52, 255), (170, 192, 154, 255))
_REEF2 = ((120, 128, 158, 255), (58, 66, 96, 255), (182, 192, 220, 255))
_GLOW = ((120, 220, 255, 255), (40, 120, 180, 255), (210, 248, 255, 255))
# 散落光源调色板（2026-10-23：荧光藻/贝类/夜明珠）
_ALGAE = ((72, 196, 150, 255), (26, 96, 78, 255), (176, 255, 216, 255))
_SHELL = ((236, 168, 118, 255), (128, 74, 48, 255), (255, 228, 190, 255))
_PEARL = ((198, 216, 246, 255), (86, 108, 156, 255), (246, 252, 255, 255))


def w_lighthouse() -> Canvas:
    """灯塔塔楼 32×56 逻辑（96×168px）：石塔身 + 双红带 + 铁艺灯室 + 锥顶。"""
    c = Canvas(32, 56)
    cx = 16
    # 避雷针 + 顶珠
    c.vline(cx, 0, 2, _IRON[1])
    c.px(cx, 3, _IRON[2])
    # 锥形屋顶（上窄下宽）
    for y in range(4, 10):
        hw = 1 + (y - 4)          # y=4 → 1, y=9 → 6
        col = _ROOF[0]
        if y >= 8:
            col = _ROOF[1]
        for x in range(cx - hw, cx + hw + 1):
            c.px(x, y, col)
        c.px(cx - hw, y, _ROOF[2])
        c.px(cx + hw, y, _ROOF[1])
    # 屋顶檐口（铁）
    c.fill_rect(cx - 8, 10, cx + 8, 11, _IRON[1])
    c.hline(cx - 8, cx + 8, 10, _IRON[2])
    # 灯室：玻璃 + 竖梃
    c.fill_rect(cx - 6, 12, cx + 6, 20, _LAMP[0])
    for x in range(cx - 6, cx + 7):
        c.px(x, 12, _LAMP[2])
        c.px(x, 20, _LAMP[1])
    for x in (cx - 3, cx, cx + 3):
        c.vline(x, 12, 20, _IRON[1])
    c.frame(cx - 6, 12, cx + 6, 20, _IRON[1])
    # 灯室下平台 + 围栏
    c.fill_rect(cx - 9, 21, cx + 9, 22, _IRON[1])
    c.hline(cx - 9, cx + 9, 21, _IRON[2])
    for x in range(cx - 8, cx + 9, 4):
        c.vline(x, 19, 20, _IRON[2])  # 围栏短柱（灯室两侧）
    # 塔身（下宽上窄）：hw 6→11
    for y in range(23, 53):
        t = float(53 - y) / 30.0     # 0 顶 → 1 底
        hw = int(round(6.0 + 5.0 * t))
        in_band = (27 <= y <= 31) or (41 <= y <= 45)
        for x in range(cx - hw, cx + hw + 1):
            col = _BAND[0] if in_band else _STONE[0]
            c.px(x, y, col)
        # 受光/落影
        for x in range(cx - hw, cx - hw + 2):
            c.px(x, y, _BAND[2] if in_band else _STONE[2])
        for x in range(cx + hw - 1, cx + hw + 1):
            c.px(x, y, _BAND[1] if in_band else _STONE[1])
        c.px(cx - hw, y, OUTLINE)
        c.px(cx + hw, y, OUTLINE)
    # 砖缝纹理（两条暗线）
    for y in (35, 47):
        for x in range(cx - 8, cx + 9):
            c.px(x, y, _STONE[1])
    # 门（拱形洞口）
    c.fill_rect(cx - 2, 49, cx + 2, 55, OUTLINE)
    c.px(cx - 2, 48, OUTLINE)
    c.px(cx + 2, 48, OUTLINE)
    c.hline(cx - 2, cx + 2, 48, OUTLINE)
    # 基座（加宽两级台阶）
    c.fill_rect(cx - 12, 53, cx + 12, 54, _STONE[1])
    c.fill_rect(cx - 13, 55, cx + 13, 55, _STONE[1])
    c.hline(cx - 13, cx + 13, 53, _STONE[2])
    return c


def _reef_post(variant: int) -> Canvas:
    """礁石界桩 20×28 逻辑（60×84px），底部对齐；3 个变体。"""
    c = Canvas(20, 28)
    base = _REEF if variant != 2 else _REEF2
    blob(c, 10.0, 19.0, 7.5, 7.0, base)
    blob(c, 10.0, 12.0, 4.5, 5.5, base)     # 上凸岩柱
    if variant == 0:
        spike(c, 13, 4, 1, -1, 5, _REEF[2])   # 岩尖
        spike(c, 6, 8, -1, -1, 4, _REEF[1])
    elif variant == 1:
        # 能量符文（与代码绘制的能量弧同色系）
        c.vline(10, 6, 16, _GLOW[0])
        c.px(8, 9, _GLOW[2])
        c.px(12, 12, _GLOW[2])
        c.px(9, 14, _GLOW[2])
        c.frame(7, 5, 13, 17, _GLOW[1])
    else:
        spike(c, 8, 6, -1, -1, 6, base[2])    # 珊瑚双角
        spike(c, 12, 6, 1, -1, 6, base[2])
        blob(c, 4.0, 22.0, 3.0, 2.5, base)
        blob(c, 16.0, 22.0, 3.0, 2.5, base)
    return c


def _glow_algae() -> Canvas:
    """荧光藻 16×14 逻辑（48×42px）：三根发光水草 + 顶端荧光球 + 底部礁石基座。"""
    c = Canvas(16, 14)
    # 底部礁石基座
    c.fill_rect(2, 12, 13, 13, _ALGAE[1])
    c.hline(2, 13, 12, _ALGAE[0])
    # 左茎（向左弯）
    for x, y in [(4, 11), (3, 10), (3, 9), (2, 8), (2, 7), (1, 6)]:
        c.px(x, y, _ALGAE[0])
    # 中茎（直立微右）
    for x, y in [(8, 11), (8, 10), (8, 9), (8, 8), (9, 7), (9, 6)]:
        c.px(x, y, _ALGAE[0])
    # 右茎（向右弯）
    for x, y in [(12, 11), (12, 10), (13, 9), (13, 8), (13, 7), (14, 6)]:
        c.px(x, y, _ALGAE[0])
    # 顶端荧光球（2×2 亮）
    for tx, ty in [(1, 5), (9, 5), (13, 5)]:
        c.px(tx, ty, _ALGAE[2])
        c.px(tx + 1, ty, _ALGAE[2])
        c.px(tx, ty + 1, _ALGAE[2])
    return c


def _glow_shell() -> Canvas:
    """荧光贝类 14×10 逻辑（42×30px）：扇形贝壳 + 放射纹 + 顶端荧光。"""
    c = Canvas(14, 10)
    cx = 7
    # 扇形壳体：底部尖、向上展开
    for y in range(3, 10):
        t = float(9 - y) / 6.0  # 0 底 → 1 顶
        hw = int(round(1.0 + 4.5 * t))
        for x in range(cx - hw, cx + hw + 1):
            c.px(x, y, _SHELL[0])
        c.px(cx - hw, y, _SHELL[1])
        c.px(cx + hw, y, _SHELL[1])
    # 放射纹（4 条亮线）
    for dx in (-3, -1, 1, 3):
        for y in range(4, 9):
            x = cx + int(round(dx * (9 - y) / 5.0))
            c.px(x, y, _SHELL[2])
    # 顶端荧光（贝壳开口处的光点）
    c.px(cx - 1, 2, _SHELL[2])
    c.px(cx, 2, _SHELL[2])
    c.px(cx + 1, 2, _SHELL[2])
    c.px(cx, 1, _SHELL[2])
    return c


def _glow_pearl() -> Canvas:
    """夜明珠 10×10 逻辑（30×30px）：发光圆珠 + 左上高光 + 贝壳托座。"""
    c = Canvas(10, 10)
    # 贝壳托座
    c.fill_rect(2, 8, 7, 9, _SHELL[1])
    c.hline(2, 7, 8, _SHELL[0])
    # 珠体（圆形，带描边与受光/落影）
    blob(c, 5.0, 5.0, 3.6, 3.6, _PEARL)
    # 左上高光
    c.px(3, 3, _PEARL[2])
    c.px(4, 3, _PEARL[2])
    c.px(3, 4, _PEARL[2])
    # 底部反光
    c.px(6, 7, _PEARL[2])
    return c


def save_sprite(category: str, sprite_id: str, cv) -> None:
    """把一张 Canvas 写成 godot_project/assets/sprites/<category>/<id>.png。"""
    d = os.path.join(SPRITES, category)
    os.makedirs(d, exist_ok=True)
    data = cv.png_bytes()
    with open(os.path.join(d, sprite_id + ".png"), "wb") as f:
        f.write(data)
    print(f"  {category}/{sprite_id}.png  {cv.w}x{cv.h}  {len(data)/1024:.1f} KB")


def generate_one(category: str, sprite_id: str):
    """生成单个精灵（若注册表中存在）。返回 Canvas；未注册返回 None。

    例：generate_one("player", "stargazer") / generate_one("enemies", "small_goblin")
    """
    key = (category, sprite_id)
    if key not in REGISTRY:
        print(f"[skip] 未注册: {category}/{sprite_id}（用 `list` 子命令查看可用项）")
        return None
    cv = REGISTRY[key]()
    save_sprite(category, sprite_id, cv)
    return cv


def generate_all():
    """生成全部已注册精灵，返回 Canvas 列表。"""
    out = []
    for (cat, sid), fn in REGISTRY.items():
        cv = fn()
        save_sprite(cat, sid, cv)
        out.append(cv)
    return out


def list_ids() -> dict:
    """返回 {category: [id, ...]}，即本工具当前能生成的全部精灵。"""
    out = {}
    for cat, sid in REGISTRY:
        out.setdefault(cat, []).append(sid)
    return out


def check_alignment() -> bool:
    """交叉核查 config id ↔ 磁盘 png：列出缺图的 id，返回是否全部对齐。

    沿用「检查」轮方法：解析 config/{enemies,bosses,weapons,passives,characters}.json
    的 id 集合，与 assets/sprites 下对应目录的 png 基名比对。缺图只是列出、不报错，
    因为运行时对缺失纹理是静默隐藏（这正是需要本检查的原因）。
    """
    import glob
    import json

    def pngs(cat: str):
        return set(
            os.path.splitext(os.path.basename(f))[0]
            for f in glob.glob(os.path.join(SPRITES, cat) + "/*.png")
        )

    def cfg_ids(path: str, nodekey: str):
        node = json.load(open(path, encoding="utf-8"))[nodekey]
        if isinstance(node, dict):
            return set(node.keys())
        if isinstance(node, list):
            return set(e["id"] for e in node if "id" in e)
        return set()

    checks = [
        ("enemies.json", "enemies", "enemies"),
        ("bosses.json", "bosses", "enemies"),
        ("weapons.json", "weapons", "weapons"),
        ("passives.json", "passives", "passives"),
        ("characters.json", "characters", "player"),
    ]
    ok = True
    for fname, key, cat in checks:
        miss = cfg_ids(os.path.join(ROOT, "config", fname), key) - pngs(cat)
        if miss:
            ok = False
            print(f"[MISSING] config/{fname} ({key}): 缺图 {sorted(miss)}")
        else:
            print(f"[OK] config/{fname} ({key})")
    # 命名精英（enemies.json metadata.elite.id，如巨钳王）也走 enemies 目录
    elite_id = str(
        (json.load(open(os.path.join(ROOT, "config", "enemies.json"), encoding="utf-8"))
         .get("metadata", {}).get("elite", {}) or {}).get("id", "")
    )
    if elite_id:
        if elite_id in pngs("enemies"):
            print(f"[OK] enemies.json (elite): {elite_id}")
        else:
            ok = False
            print(f"[MISSING] enemies.json (elite): 缺图 ['{elite_id}']")
    print("结论:", "全部对齐 ✅" if ok else "存在缺图 ❌")
    return ok


# ----------------------------------------------------------------------------
# 注册表：哪些 (category, id) 由哪个绘制函数生成
# ----------------------------------------------------------------------------

_GROUND_TRIPLETS = (
    # 2026-10-22 截图反馈「没有看到地图的绘制」：原配色亮度仅 30~55，深夜色背景下
    # 等于隐形 → 整体提亮约 2.5~3 倍（base lum≈93 / speck≈126 / crack≈70），
    # 保留海底蓝青色调；夜视野遮罩压暗后仍可辨瓷砖纹理
    ((74, 96, 126, 255), (106, 130, 162, 255), (54, 72, 98, 255)),
    ((70, 92, 122, 255), (100, 124, 156, 255), (50, 68, 94, 255)),
    ((78, 100, 130, 255), (112, 136, 168, 255), (58, 76, 102, 255)),
)


def _ground_maker(i: int):
    base, speck, crack = _GROUND_TRIPLETS[i]
    return ground_tile(20260824 + i, base, speck, crack)


def _build_registry() -> dict:
    reg = {}
    # 敌人杂兵
    for name, fn in (
        ("small_goblin", e_goblin),
        ("iron_crab", e_crab),
        ("giant_claw_king", e_elite_crab),
        ("jellyfish_drifter", e_jelly),
        ("deep_diver", e_diver),
        ("bomb_shell", e_bomb),
        ("raven_flock", e_raven),
        ("tide_summoner", e_summon),
        ("abyssal_pikeman", e_pike),
        ("reef_giant", e_reef),
    ):
        reg[("enemies", name)] = fn
    # 敌人 Boss（与 config/bosses.json 的 id 对齐，不带 boss_ 前缀）
    for name, fn in (
        ("tide_archon", b_archon),
        ("jellyfish_queen", b_queen),
        ("devouring_star", b_star),
    ):
        reg[("enemies", name)] = fn
    # 玩家角色
    for name, fn in (
        ("watcher", p_keeper),
        ("blacksmith", p_blacksmith),
        ("stargazer", p_stargazer),
    ):
        reg[("player", name)] = fn
    # 地面砖
    for i in range(len(_GROUND_TRIPLETS)):
        reg[("ground", f"floor_{i}")] = (lambda i=i: _ground_maker(i))
    # 召唤物（武器 summon 块引用）
    for name, fn in SUMMON_ICONS.items():
        reg[("summons", name)] = fn
    # 武器 / 被动图标
    for name, fn in WEAPON_ICONS.items():
        reg[("weapons", name)] = fn
    for name, fn in PASSIVE_ICONS.items():
        reg[("passives", name)] = fn
    # 世界装饰（灯塔塔楼 / 竞技场礁石边界 / 散落光源）
    reg[("world", "lighthouse_tower")] = w_lighthouse
    for i in range(3):
        reg[("world", f"reef_post_{i}")] = (lambda i=i: _reef_post(i))
    # 散落光源（config/map.json scattered_lights.kinds[].id）
    reg[("world", "glow_algae")] = _glow_algae
    reg[("world", "glow_shell")] = _glow_shell
    reg[("world", "glow_pearl")] = _glow_pearl
    return reg


REGISTRY = _build_registry()


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def main(argv=None) -> int:
    """CLI 入口（见文件头用法）。返回进程退出码。"""
    import argparse

    p = argparse.ArgumentParser(
        prog="generate_pixel_sprites.py",
        description="Tidekeeper 像素精灵生成工具（供 AI agent 调用）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python tools/generate_pixel_sprites.py all\n"
            "  python tools/generate_pixel_sprites.py one enemies small_goblin\n"
            "  python tools/generate_pixel_sprites.py one player stargazer\n"
            "  python tools/generate_pixel_sprites.py list\n"
            "  python tools/generate_pixel_sprites.py check\n"
        ),
    )
    sub = p.add_subparsers(dest="cmd")
    p_all = sub.add_parser("all", help="生成全部精灵（默认行为）")
    p_all.add_argument("--sheet", metavar="OUT.png", help="把所有结果拼成对照表 PNG")
    p_one = sub.add_parser("one", help="生成单个精灵")
    p_one.add_argument("category", help="enemies / player / ground / weapons / passives")
    p_one.add_argument("id", help="精灵 id（用 list 查看可用项）")
    p_one.add_argument("--sheet", metavar="OUT.png", help="把该张结果拼成对照表 PNG")
    sub.add_parser("list", help="列出可用 category/id")
    sub.add_parser("check", help="校验 config id ↔ png 是否对齐")
    args = p.parse_args(argv)

    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass

    cmd = args.cmd
    canvases = []
    if cmd is None or cmd == "all":
        canvases = generate_all()
        print(f"完成，共 {len(canvases)} 个精灵。")
    elif cmd == "one":
        cv = generate_one(args.category, args.id)
        if cv is None:
            return 2
        canvases = [cv]
    elif cmd == "list":
        reg = list_ids()
        for cat in sorted(reg):
            print(f"{cat}: {', '.join(sorted(reg[cat]))}")
        return 0
    elif cmd == "check":
        return 0 if check_alignment() else 1

    sheet = getattr(args, "sheet", "") or ""
    if sheet:
        compose_sheet(sheet, canvases, scale=4)
    return 0


if __name__ == "__main__":
    sys.exit(main())
