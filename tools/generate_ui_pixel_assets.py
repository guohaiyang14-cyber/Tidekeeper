#!/usr/bin/env python3
# ============================================================================
# generate_ui_pixel_assets.py — 生成 Tidekeeper 卡通像素风 UI 图集
#
# 输出：godot_project/assets/ui/pixel/*.png（RGBA，无外部依赖，手写 PNG 编码）
#
# 画法要点（与「简陋方块」的区别就在这里）：
#   1. 四层框架：外描边 → 斜面(亮/暗) → 主框色 → 内暗分隔线
#   2. 倒角：四角切 2~3 像素成斜边，不是纯圆角矩形
#   3. 铆钉：四角内缩处 2×2 小钉（左上亮、右下暗），金属板质感
#   4. 渐变：填充顶部 2~3 行受光、底部 1~2 行落影（都落在九宫格边距内，
#      拉伸中段不会吃掉这些层次）
#   5. 图标按资源名逐个手绘点阵（心/币/星/骷髅/宝箱/剑/光标），
#      四档色调 o=描边 X=主色 h=高光 d=暗部
#
# 九宫格约束：所有细节必须画在 texture_margin 以内（四边各 margin 像素），
#             中段会被拉伸/平铺，只放纯色。
# 用法：
#   python tools/generate_ui_pixel_assets.py                  # 只出资源
#   python tools/generate_ui_pixel_assets.py --sheet out.png  # 额外出对照表（放大 3×）
# ============================================================================
import os
import struct
import sys
import zlib

# 每个逻辑像素 = BLOCK×BLOCK 实际像素
BLOCK = 3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot_project", "assets", "ui", "pixel")

# 调色板：卡通像素风（深描边 + 高饱和填充 + 单侧高光）
PALETTE = {
    "outline":      (26, 19, 32, 255),    # 近黑紫描边
    "outline_soft": (42, 31, 58, 255),
    "panel_bg":     (43, 36, 64, 255),    # 面板底
    "panel_top":    (55, 48, 79, 255),
    "panel_edge":   (110, 98, 168, 255),
    "panel_hi":     (156, 143, 224, 255),
    "btn_fill":     (61, 53, 96, 255),
    "btn_hover":    (78, 69, 128, 255),
    "btn_press":    (34, 28, 56, 255),
    "btn_dis":      (42, 39, 52, 255),
    "btn_edge":     (124, 111, 192, 255),
    "btn_hi":       (179, 166, 240, 255),
    # 「已点亮 / 已完成」态：沿用原扁平样式的绿色语义（lit = 绿、available = 蓝紫、locked = 灰）
    "btn_lit_fill": (38, 70, 56, 255),
    "btn_lit_edge": (96, 196, 140, 255),
    "btn_lit_hi":   (156, 232, 184, 255),
    "accent_bg":    (30, 58, 58, 255),
    "accent_edge":  (79, 179, 160, 255),
    "accent_hi":    (127, 224, 200, 255),
    "death_bg":     (58, 30, 40, 255),
    "death_edge":   (201, 86, 107, 255),
    "death_hi":     (255, 138, 158, 255),
    # 进化共鸣（金色，与事件卡的青色区分：共鸣是稀有庆祝感）
    "gold_bg":      (58, 46, 22, 255),
    "gold_edge":    (242, 181, 60, 255),
    "gold_hi":      (255, 224, 138, 255),
    "chip_bg":      (36, 30, 54, 255),
    "chip_edge":    (94, 82, 144, 255),
    "groove":       (30, 25, 46, 255),
    "groove_dark":  (18, 14, 26, 255),
    "groove_rim":   (86, 74, 126, 255),
    "hp_main":      (232, 84, 63, 255),
    "hp_hi":        (255, 158, 128, 255),
    "hp_dark":      (163, 44, 34, 255),
    "exp_main":     (79, 179, 232, 255),
    "exp_hi":       (170, 228, 255, 255),
    "exp_dark":     (42, 111, 158, 255),
    "boss_main":    (201, 86, 63, 255),
    "boss_hi":      (255, 170, 130, 255),
    "boss_dark":    (140, 44, 30, 255),
    "gold":         (242, 181, 60, 255),
    "gold_hi":      (255, 232, 158, 255),
    "gold_dark":    (168, 112, 26, 255),
    "white":        (244, 240, 255, 255),
    "teal":         (95, 212, 138, 255),
    "purple":       (155, 107, 214, 255),
    "bone":         (226, 218, 200, 255),
    "bone_hi":      (255, 253, 240, 255),
    "bone_dark":    (168, 158, 140, 255),
    "steel":        (168, 186, 212, 255),
    "steel_hi":     (232, 242, 255, 255),
    "steel_dark":   (104, 120, 148, 255),
    "wood":         (139, 90, 43, 255),
    "wood_hi":      (192, 134, 74, 255),
    "wood_dark":    (94, 58, 26, 255),
}


# ----------------------------------------------------------------------------
# 颜色运算
# ----------------------------------------------------------------------------
def _rgba(color):
    return PALETTE[color] if isinstance(color, str) else color


def shade(color, f):
    """变暗（f<1）/ 变亮（f>1，向白色插值）。"""
    r, g, b, a = _rgba(color)
    if f <= 1.0:
        return (int(r * f), int(g * f), int(b * f), a)
    t = min(1.0, f - 1.0)
    return (
        int(r + (255 - r) * t),
        int(g + (255 - g) * t),
        int(b + (255 - b) * t),
        a,
    )


def mix(c1, c2, t):
    r1, g1, b1, a1 = _rgba(c1)
    r2, g2, b2, _ = _rgba(c2)
    return (
        int(r1 + (r2 - r1) * t),
        int(g1 + (g2 - g1) * t),
        int(b1 + (b2 - b1) * t),
        a1,
    )


# ----------------------------------------------------------------------------
# 画布
# ----------------------------------------------------------------------------
class Canvas:
    """逻辑像素画布；px() 按 BLOCK 放大写入。"""

    def __init__(self, lw: int, lh: int, block: int = BLOCK):
        self.lw, self.lh, self.b = lw, lh, block
        self.w, self.h = lw * block, lh * block
        self.buf = [[(0, 0, 0, 0)] * self.w for _ in range(self.h)]

    def px(self, x: int, y: int, color) -> None:
        if color is None:
            return
        if not (0 <= x < self.lw and 0 <= y < self.lh):
            return
        col = _rgba(color)
        for dy in range(self.b):
            row = self.buf[y * self.b + dy]
            for dx in range(self.b):
                row[x * self.b + dx] = col

    def fill_rect(self, x0: int, y0: int, x1: int, y1: int, color) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.px(x, y, color)

    def frame(self, x0: int, y0: int, x1: int, y1: int, color) -> None:
        for x in range(x0, x1 + 1):
            self.px(x, y0, color)
            self.px(x, y1, color)
        for y in range(y0, y1 + 1):
            self.px(x0, y, color)
            self.px(x1, y, color)

    def hline(self, x0: int, x1: int, y: int, color) -> None:
        for x in range(x0, x1 + 1):
            self.px(x, y, color)

    def vline(self, x: int, y0: int, y1: int, color) -> None:
        for y in range(y0, y1 + 1):
            self.px(x, y, color)

    def bevel(self, x0: int, y0: int, x1: int, y1: int, hi, lo) -> None:
        """左上受光、右下落影（凸起）。"""
        self.hline(x0, x1, y0, hi)
        self.vline(x0, y0, y1, hi)
        self.hline(x0, x1, y1, lo)
        self.vline(x1, y0, y1, lo)

    def bevel_in(self, x0: int, y0: int, x1: int, y1: int, hi, lo) -> None:
        """反斜面（凹陷）：左上落影、右下受光。"""
        self.hline(x0, x1, y0, lo)
        self.vline(x0, y0, y1, lo)
        self.hline(x0, x1, y1, hi)
        self.vline(x1, y0, y1, hi)

    def chamfer(self, n: int, depth: int = 2) -> None:
        """四角切斜边（像素风的倒角，比圆角更有硬朗感）。"""
        for d in range(depth):
            span = depth - d
            for x in range(0, span):
                self.px(x, d, None)
                self.px(n - x, d, None)
                self.px(x, n - d, None)
                self.px(n - x, n - d, None)

    def nail(self, x: int, y: int, color) -> None:
        """2×2 铆钉：左上亮、右下暗。"""
        c = _rgba(color)
        self.px(x, y, shade(c, 1.45))
        self.px(x + 1, y, c)
        self.px(x, y + 1, c)
        self.px(x + 1, y + 1, shade(c, 0.55))

    def png_bytes(self) -> bytes:
        raw = bytearray()
        for row in self.buf:
            raw.append(0)  # filter type 0
            for r, g, b, a in row:
                raw += bytes((r, g, b, a))
        return _encode_png(self.w, self.h, bytes(raw))

    def save(self, name: str) -> None:
        os.makedirs(OUT, exist_ok=True)
        data = self.png_bytes()
        path = os.path.join(OUT, name)
        with open(path, "wb") as f:
            f.write(data)
        print(f"  {name:22s} {self.w:3d}x{self.h:3d}  {len(data) / 1024:6.1f} KB")


def _encode_png(w: int, h: int, raw: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8bit RGBA
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


# ----------------------------------------------------------------------------
# 九宫格：面板
# ----------------------------------------------------------------------------
def panel(name: str, fill: str, edge: str, hi: str, size: int = 24, depth: int = 3) -> None:
    """金属板式面板：外描边 → 斜面 → 主框 → 内暗线 → 受光顶 → 四角铆钉。

    size=24 逻辑（×BLOCK=72px），九宫格边距取 7 逻辑（21px）：
    所有装饰都在边距内，中段只有纯色，拉伸后不糊。
    """
    c = Canvas(size, size)
    n = size - 1
    base = _rgba(fill)
    e = _rgba(edge)
    h = _rgba(hi)

    # 1) 底 + 竖向渐变（顶部受光 3 档、底部落影 2 档，全部在上下边距内）
    c.fill_rect(0, 0, n, n, base)
    c.fill_rect(1, 1, n - 1, 1, shade(base, 1.30))
    c.fill_rect(1, 2, n - 1, 2, shade(base, 1.16))
    c.fill_rect(1, 3, n - 1, 3, shade(base, 1.07))
    c.fill_rect(1, n - 2, n - 1, n - 2, shade(base, 0.80))
    c.fill_rect(1, n - 1, n - 1, n - 1, shade(base, 0.62))

    # 2) 四层框架
    c.frame(0, 0, n, n, "outline")                       # 外描边
    c.bevel(1, 1, n - 1, n - 1, shade(e, 1.45), shade(e, 0.52))  # 斜面
    c.frame(2, 2, n - 2, n - 2, e)                       # 主框色
    c.frame(3, 3, n - 3, n - 3, shade(base, 0.55))       # 内暗分隔线

    # 3) 内侧受光边（左上 1px 高光，压在主框内侧）
    c.hline(4, n - 4, 4, shade(h, 0.92))
    c.vline(4, 4, n - 4, shade(h, 0.92))
    c.hline(4, n - 4, n - 4, shade(base, 0.70))
    c.vline(n - 4, 4, n - 4, shade(base, 0.70))

    # 4) 四角铆钉
    for x, y in ((5, 5), (n - 6, 5), (5, n - 6), (n - 6, n - 6)):
        c.nail(x, y, e)

    # 5) 倒角
    c.chamfer(n, depth)
    c.save(name)
    return c


# ----------------------------------------------------------------------------
# 九宫格：按钮
# ----------------------------------------------------------------------------
def button(name: str, fill: str, edge: str, hi: str, state: str = "normal", size: int = 16) -> None:
    """按钮：斜面 + 顶部玻璃高光 + 四角铆钉。

    state: normal / hover / pressed / disabled / lit
      - hover  ：整体提亮 + 顶部高光更白
      - pressed：反斜面 + 顶部内阴影，读起来是「按进去」
      - disabled：去饱和、无高光
      - lit    ：绿色 + 内侧发光环
    """
    c = Canvas(size, size)
    n = size - 1
    base = _rgba(fill)
    e = _rgba(edge)
    h = _rgba(hi)

    if state == "hover":
        base = shade(base, 1.18)
        e = shade(e, 1.20)
    elif state == "pressed":
        base = shade(base, 0.62)
        e = shade(e, 0.80)
    elif state == "disabled":
        base = _rgba("btn_dis")
        e = mix(e, "outline_soft", 0.65)
        h = shade(base, 1.25)
    elif state == "lit":
        e = shade(e, 1.10)

    # 1) 底 + 竖向渐变
    c.fill_rect(0, 0, n, n, base)
    if state != "disabled":
        c.fill_rect(1, 1, n - 1, 1, shade(base, 1.42))
        c.fill_rect(1, 2, n - 1, 2, shade(base, 1.22))
        c.fill_rect(1, 3, n - 1, 3, shade(base, 1.08))
    c.fill_rect(1, n - 2, n - 1, n - 2, shade(base, 0.76))
    c.fill_rect(1, n - 1, n - 1, n - 1, shade(base, 0.58))

    # 2) 框架
    c.frame(0, 0, n, n, "outline")
    if state == "pressed":
        # 按下：反斜面 + 顶部两行内阴影 + 底部一道亮边（凹陷的「口沿」）
        c.bevel_in(1, 1, n - 1, n - 1, shade(e, 1.30), shade(e, 0.40))
        c.hline(2, n - 2, 2, shade(base, 0.38))
        c.vline(2, 2, n - 2, shade(base, 0.50))
        c.hline(2, n - 2, n - 2, shade(base, 1.55))
    else:
        c.bevel(1, 1, n - 1, n - 1, shade(e, 1.55), shade(e, 0.45))
        c.frame(2, 2, n - 2, n - 2, shade(base, 0.72))   # 内暗线，压出层次

    # 3) 玻璃高光（顶部 1px，只在中段，两端各留 3px 避免贴到铆钉）
    if state in ("normal", "hover", "lit"):
        gloss = h if state != "hover" else shade(h, 1.25)
        c.hline(4, n - 4, 1, shade(gloss, 0.85))
    if state == "lit":
        # 内侧发光环（已点亮态更醒目）
        c.hline(3, n - 3, 3, shade(h, 0.70))
        c.hline(3, n - 3, n - 3, shade(h, 0.55))

    # 4) 四角铆钉
    if state != "disabled":
        for x, y in ((3, 3), (n - 4, 3), (3, n - 4), (n - 4, n - 4)):
            c.nail(x, y, e)

    # 5) 倒角
    c.chamfer(n, 2)
    c.save(name)
    return c


# ----------------------------------------------------------------------------
# 九宫格：进度条（中段平铺）
# ----------------------------------------------------------------------------
def bar_bg(name: str, size: int = 8) -> None:
    """凹槽：外描边 + 上/左内阴影 + 下/右内反光 + 深槽底。
    8×8 逻辑（24px），九宫格边距 2 → 上下各 6px 的层次不会被纵向拉伸吃掉。"""
    c = Canvas(size, size)
    n = size - 1
    c.fill_rect(0, 0, n, n, "groove_dark")
    c.fill_rect(1, 2, n - 1, n - 2, "groove")
    c.hline(1, n - 1, 1, "outline_soft")        # 顶部内阴影
    c.vline(1, 1, n - 1, "outline_soft")        # 左侧内阴影
    c.hline(1, n - 1, n - 1, "groove_rim")      # 底部反光
    c.vline(n - 1, 1, n - 1, "groove_rim")      # 右侧反光
    c.frame(0, 0, n, n, "outline")
    c.chamfer(n, 1)
    c.save(name)
    return c


def bar_fill(name: str, main: str, hi: str, dark: str, size: int = 8) -> None:
    """填充：顶部 1px 玻璃高光 + 2 档渐变 + 底部暗边 + 1px 深色描边。
    列方向必须完全一致，否则平铺会出现竖缝。"""
    c = Canvas(size, size)
    n = size - 1
    m = _rgba(main)
    c.fill_rect(0, 0, n, n, m)
    c.hline(0, n, 1, _rgba(hi))                     # 玻璃高光
    c.hline(0, n, 2, shade(m, 1.32))
    c.hline(0, n, 3, shade(m, 1.08))
    c.hline(0, n, n - 2, shade(m, 0.70))            # 底部渐暗
    c.hline(0, n, n - 1, _rgba(dark))
    c.frame(0, 0, n, n, "outline")
    c.chamfer(n, 1)
    c.save(name)
    return c


# ----------------------------------------------------------------------------
# 九宫格：芯片 / 槽位
# ----------------------------------------------------------------------------
def chip(size: int = 12) -> None:
    """HUD 武器/被动槽的小铭牌：薄板 + 倒角 + 顶部受光。

    注意：12 逻辑（36px）只够画到边距 4（12px），所以**不放铆钉**——
    铆钉会落进中段被拉伸成横条。细节全压在框架上。
    """
    c = Canvas(size, size)
    n = size - 1
    base = _rgba("chip_bg")
    e = _rgba("chip_edge")
    c.fill_rect(0, 0, n, n, base)
    c.fill_rect(1, 1, n - 1, 1, shade(base, 1.40))
    c.fill_rect(1, 2, n - 1, 2, shade(base, 1.15))
    c.fill_rect(1, n - 2, n - 1, n - 2, shade(base, 0.78))
    c.fill_rect(1, n - 1, n - 1, n - 1, shade(base, 0.60))
    c.frame(0, 0, n, n, "outline")
    c.bevel(1, 1, n - 1, n - 1, shade(e, 1.40), shade(e, 0.55))
    c.frame(2, 2, n - 2, n - 2, shade(base, 0.62))
    c.chamfer(n, 2)
    c.save("chip.png")
    return c


def slot(size: int = 16) -> None:
    """空槽位：内凹 + 实线内框 + 四角缺口，读起来是「这里可以放东西」。

    不用虚线：虚线横穿中段会被九宫格拉成一条长线。
    """
    c = Canvas(size, size)
    n = size - 1
    base = _rgba("chip_bg")
    e = _rgba("chip_edge")
    c.fill_rect(0, 0, n, n, shade(base, 0.80))
    c.frame(0, 0, n, n, "outline")
    c.bevel_in(1, 1, n - 1, n - 1, shade(e, 0.55), shade(e, 1.15))
    c.frame(3, 3, n - 3, n - 3, shade(e, 0.70))
    # 四角缺口（亮），落在四角边距内
    for x, y in ((4, 4), (n - 4, 4), (4, n - 4), (n - 4, n - 4)):
        c.px(x, y, shade(e, 1.35))
        c.px(x + 1, y, shade(e, 0.85))
    c.chamfer(n, 2)
    c.save("slot_frame.png")
    return c


# ----------------------------------------------------------------------------
# 点阵图标（16×16 逻辑，按资源名逐个手绘）
#   o=描边  X=主色  h=高光  d=暗部  g=第二色（金/钢）
# ----------------------------------------------------------------------------
ICONS = {
    # 红心：左上加双高光、右下压暗，经典血条心
    "icon_heart": (
        "................",
        "..oooo...oooo...",
        ".ohhXXo.oXXddo..",
        "ohhXXXXoXXXddo..",
        "ohhXXXXXXXXddo..",
        "ohXXXXXXXXXddo..",
        "oXXXXXXXXXXddo..",
        "oXXXXXXXXXXddo..",
        ".oXXXXXXXXddo...",
        "..oXXXXXXddo....",
        "...oXXXXddo.....",
        "....oXXddo......",
        ".....oXdo.......",
        "......oo........",
        "................",
        "................",
    ),
    # 金币：外圈金环 + 盘面 + 中央潮汐波纹（三道错位短横，读起来是水波）
    "icon_coin": (
        "................",
        ".....oooooo.....",
        "...oohhhhhhoo...",
        "..ohhXXXXXXhho..",
        ".ohhXXXXXXXXhho.",
        ".ohXXXXXXXXXXdo.",
        "ohXXXXdddXXXXXdo",
        "ohXXXXXXXdddXXdo",
        "ohXXXXdddXXXXXdo",
        "ohXXXXXXXXXXXddo",
        ".ohXXXXXXXXXddo.",
        ".ohhXXXXXXXddo..",
        "..ohhXXXXXddo...",
        "...oohddddoo....",
        ".....oooooo.....",
        "................",
    ),
    # 星：左上受光 / 右下压暗，五角带棱面
    "icon_star": (
        "................",
        ".......oo.......",
        "......ohho......",
        "......ohXo......",
        ".....ohhXXo.....",
        "oooooohXXXXooooo",
        "ohhhhhXXXXXXdddo",
        "ohhhhXXXXXXdddo.",
        ".ohhXXXXXXdddo..",
        "..ohXXXXXXddo...",
        "...ohXXXXddo....",
        "...ohXXXXddo....",
        "..ohhXXXXXddo...",
        "..ohho..oXddo...",
        ".ohho....odddo..",
        ".oo........oo...",
    ),
    # 骷髅：颅顶受光、眼窝/鼻孔镂空、下颌牙齿
    "icon_skull": (
        "................",
        "....oooooooo....",
        "..oohhhhhhhhoo..",
        ".ohhXXXXXXXXXXo.",
        "ohhXXXXXXXXXXXdo",
        "ohXXXXXXXXXXXddo",
        "ohXXooXXXXooXddo",
        "ohXooooXXooooXdo",
        "ohXXooXXXXooXddo",
        "ohXXXXXooXXXddo.",
        "ohXXXXooooXXddo.",
        ".oXXoXoXoXXoddo.",
        ".oXXXXXXXXXXXdo.",
        "..oXoXoXoXoXdo..",
        "...oooddddooo...",
        "................",
    ),
    # 宝箱：木箱 + 金属包边 + 锁扣 + 木板缝
    "icon_chest": (
        "................",
        "...oooooooooo...",
        "..ohhhhhhhhhho..",
        "..oXXXXXXXXXXo..",
        "oooooooooooooooo",
        "ohhXXddXXddXXhho",
        "oXXXXXXXXXXXXXXo",
        "oooooooooooooooo",
        "ohhXXddXXddXXhho",
        "oXXXXXooooXXXXXo",
        "oXXXXogggoXXXXXo",
        "oXXXXogXgoXXXXXo",
        "oXXXXXooooXXXXXo",
        "ohhXXddXXddXXhho",
        "oooooooooooooooo",
        "................",
    ),
    # 剑：斜置长剑，刃面高光 + 金色十字护手 + 握柄 + 圆头
    "icon_sword": (
        ".............oo.",
        "............ohho",
        "...........ohhXo",
        "..........ohhXdo",
        ".........ohhXdo.",
        "........ohhXdo..",
        ".......ohhXdo...",
        "......ohhXdo....",
        ".....ohhXdo.....",
        "....ohhXdo......",
        "...ohhXdo.......",
        "..ogogXdo.......",
        ".oggggggo.......",
        "..ogoXgo........",
        "...oXddo........",
        "....oo..........",
    ),
    # 光标：白箭头 + 深色描边 + 右侧落影
    "cursor_arrow": (
        "oo..............",
        "ohho............",
        "ohXho...........",
        "ohXXho..........",
        "ohXXXho.........",
        "ohXXXXho........",
        "ohXXXXXho.......",
        "ohXXXXXXho......",
        "ohXXXXXXXho.....",
        "ohXXXXoooXho....",
        "ohXXho..oXho....",
        "ohXho....oXho...",
        "ohho.....oXho...",
        "oo........oXho..",
        "...........oXo..",
        "............o...",
    ),
}

# 每个图标的主色 / 高光 / 暗部
ICON_COLORS = {
    "icon_heart": ("hp_main", "hp_hi", "hp_dark"),
    "icon_coin": ("gold", "gold_hi", "gold_dark"),
    "icon_star": ("gold", "gold_hi", "gold_dark"),
    "icon_skull": ("bone", "bone_hi", "bone_dark"),
    "icon_chest": ("wood", "wood_hi", "wood_dark"),
    "icon_sword": ("steel", "steel_hi", "steel_dark"),
    "cursor_arrow": ("white", "white", "outline"),
}

# 图标里额外字符 → 调色板色名（与主色系无关的固定色）
ICON_EXTRA = {"g": "gold", "w": "white", "b": "outline"}


def draw_icon(name: str, rows) -> Canvas:
    main, hi, dark = ICON_COLORS[name]
    c = Canvas(16, 16)
    if len(rows) != 16:
        raise SystemExit(f"{name} 行数 {len(rows)} != 16")
    for y, line in enumerate(rows):
        if len(line) != 16:
            raise SystemExit(f"{name} 第 {y + 1} 行宽度 {len(line)} != 16: {line!r}")
        for x, ch in enumerate(line):
            if ch == ".":
                continue
            if ch == "o":
                color = "outline"
            elif ch == "X":
                color = main
            elif ch == "h":
                color = hi
            elif ch == "d":
                color = dark
            elif ch in ICON_EXTRA:
                color = ICON_EXTRA[ch]
            else:
                raise SystemExit(f"{name} 未知字符 {ch!r}")
            c.px(x, y, color)
    c.save(name + ".png")
    return c


# ----------------------------------------------------------------------------
# 对照表（开发用，不写入项目资源）
# ----------------------------------------------------------------------------
def compose_sheet(path: str, canvases, scale: int = 3) -> None:
    pad = 8 * scale
    cols = 4
    cw = max(c.w for c in canvases) * scale
    ch = max(c.h for c in canvases) * scale
    rows = (len(canvases) + cols - 1) // cols
    W = cols * (cw + pad) + pad
    H = rows * (ch + pad) + pad
    buf = [[(24, 20, 34, 255)] * W for _ in range(H)]
    for i, cv in enumerate(canvases):
        ox = pad + (i % cols) * (cw + pad)
        oy = pad + (i // cols) * (ch + pad)
        for y in range(cv.h):
            for x in range(cv.w):
                col = cv.buf[y][x]
                if col[3] == 0:
                    continue
                for dy in range(scale):
                    row = buf[oy + y * scale + dy]
                    for dx in range(scale):
                        row[ox + x * scale + dx] = col
    raw = bytearray()
    for row in buf:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    with open(path, "wb") as f:
        f.write(_encode_png(W, H, bytes(raw)))
    print(f"对照表: {path}  {W}x{H}（{len(canvases)} 个，放大 {scale}×，每行 {cols} 个）")


# ----------------------------------------------------------------------------
def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass
    sheet_path = ""
    for arg in sys.argv[1:]:
        if arg.startswith("--sheet="):
            sheet_path = arg.split("=", 1)[1]
    print(f"输出目录: {OUT}（逻辑像素 ×{BLOCK}）")
    made = []

    print("九宫格面板（24×24，边距 7）:")
    made.append(panel("panel_dark.png", "panel_bg", "panel_edge", "panel_hi"))
    made.append(panel("panel_accent.png", "accent_bg", "accent_edge", "accent_hi"))
    made.append(panel("panel_death.png", "death_bg", "death_edge", "death_hi"))
    # 进化共鸣：金色（对应原 evolution_effect_ui 传入的金色 StyleBoxFlat）
    made.append(panel("panel_gold.png", "gold_bg", "gold_edge", "gold_hi"))

    print("九宫格按钮（16×16，边距 6）:")
    made.append(button("btn_normal.png", "btn_fill", "btn_edge", "btn_hi", "normal"))
    made.append(button("btn_hover.png", "btn_hover", "btn_hi", "white", "hover"))
    made.append(button("btn_pressed.png", "btn_press", "btn_edge", "btn_hi", "pressed"))
    made.append(button("btn_disabled.png", "btn_dis", "outline_soft", "white", "disabled"))
    # 「已点亮」态：绿色系，与「可购买」（紫）「未解锁」（灰）三态互不混淆
    made.append(button("btn_lit.png", "btn_lit_fill", "btn_lit_edge", "btn_lit_hi", "lit"))

    print("九宫格芯片 / 槽位:")
    made.append(chip(12))
    made.append(slot(16))

    print("进度条（8×8，边距 2）:")
    made.append(bar_bg("bar_bg.png"))
    made.append(bar_fill("bar_hp.png", "hp_main", "hp_hi", "hp_dark"))
    made.append(bar_fill("bar_exp.png", "exp_main", "exp_hi", "exp_dark"))
    made.append(bar_fill("bar_boss.png", "boss_main", "boss_hi", "boss_dark"))

    print("点阵图标 / 光标（16×16）:")
    for name, rows in ICONS.items():
        made.append(draw_icon(name, rows))

    if sheet_path:
        compose_sheet(sheet_path, [m for m in made if m is not None])

    print(f"完成，共 {len(made)} 个资源。")


if __name__ == "__main__":
    main()
