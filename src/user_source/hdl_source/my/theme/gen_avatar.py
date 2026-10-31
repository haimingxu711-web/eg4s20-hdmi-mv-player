"""
演唱小人（Q 版茂茂 / 许茂山）像素画生成器 → avatar.mif/.hex（精灵帧）+ avatar_pal.mif/.hex（调色板）
64x64 像素、16 色（0 = 透明），4 帧：0 闭嘴  1 小张嘴  2 大张嘴  3 眨眼（闭嘴）
硬件 fx_avatar 放大 2 倍显示（128x128），嘴型跟旋律包络、眨眼和点头由硬件控制
换形象：改下面 draw() 里的形状和 PAL 颜色，运行 python gen_avatar.py
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.dirname(os.path.abspath(__file__))
N = 64
PAL = [
    (0, 0, 0),          # 0 透明
    (44, 30, 26),       # 1 描边
    (62, 42, 30),       # 2 头发
    (104, 74, 52),      # 3 头发高光
    (246, 204, 170),    # 4 皮肤
    (222, 170, 138),    # 5 皮肤阴影
    (240, 150, 140),    # 6 腮红
    (34, 26, 24),       # 7 眼睛/眉毛
    (130, 40, 44),      # 8 口腔
    (204, 204, 210),    # 9 外袍浅灰
    (160, 160, 172),    # 10 外袍阴影
    (40, 54, 86),       # 11 藏青交领
    (232, 232, 238),    # 12 领口花纹
    (255, 255, 255),    # 13 高光
    (226, 112, 112),    # 14 舌头
    (110, 110, 124),    # 15 衣褶
]

def draw(mouth, blink):
    im = Image.new("P", (N, N), 0)
    im.putpalette([c for rgb in PAL for c in rgb] + [0] * (768 - 48))
    d = ImageDraw.Draw(im)
    # ---- 身体：外袍（梯形）+ 交领 ----
    d.polygon([(14, 47), (50, 47), (56, 63), (8, 63)], fill=9)
    d.polygon([(8, 63), (14, 50), (18, 63)], fill=10)            # 左侧阴影
    d.polygon([(56, 63), (50, 50), (46, 63)], fill=10)
    d.polygon([(22, 46), (42, 46), (32, 60)], fill=11)           # V 形藏青交领
    d.polygon([(26, 46), (38, 46), (32, 54)], fill=4)            # 脖子
    for (fx, fy) in [(25, 49), (39, 49), (28, 54), (36, 54)]:    # 领口白花（在藏青交领上）
        d.point([(fx, fy), (fx - 1, fy), (fx + 1, fy), (fx, fy - 1), (fx, fy + 1)], fill=12)
    d.line([(32, 60), (32, 63)], fill=15)                        # 衣襟
    # ---- 头：圆脸 ----
    d.ellipse([11, 8, 53, 49], fill=4)
    d.ellipse([11, 30, 53, 49], fill=4)
    d.arc([12, 24, 52, 49], 20, 160, fill=5)                     # 下巴阴影
    # ---- 头发：锅盖头 + 齐刘海 + 小发髻 ----
    d.ellipse([27, 0, 37, 9], fill=2)                            # 发髻
    d.chord([9, 5, 55, 45], 180, 360, fill=2)                    # 头顶
    d.rectangle([12, 16, 52, 22], fill=2)                        # 齐刘海
    for x in range(13, 52, 4):                                   # 刘海发梢
        d.point([(x, 23), (x + 1, 23)], fill=2)
    d.rectangle([9, 18, 13, 36], fill=2)                         # 两侧鬓发
    d.rectangle([51, 18, 55, 36], fill=2)
    d.line([(28, 8), (36, 8)], fill=1)                           # 发髻与头发分界
    d.point([(30, 2), (31, 2), (30, 3)], fill=3)                 # 发髻高光
    d.line([(18, 8), (26, 5)], fill=3)                           # 高光
    d.line([(16, 11), (20, 9)], fill=3)
    # ---- 五官 ----
    d.line([(19, 25), (25, 26)], fill=7)                         # 眉毛（略八字，呆萌）
    d.line([(39, 26), (45, 25)], fill=7)
    if blink:
        d.line([(20, 30), (25, 30)], fill=7)
        d.line([(39, 30), (44, 30)], fill=7)
    else:                                                        # 小眼睛
        d.rectangle([21, 29, 24, 31], fill=7); d.point((22, 29), fill=13)
        d.rectangle([40, 29, 43, 31], fill=7); d.point((41, 29), fill=13)
    d.ellipse([15, 33, 21, 37], fill=6)                          # 腮红
    d.ellipse([43, 33, 49, 37], fill=6)
    d.point([(31, 35), (32, 35)], fill=5)                        # 鼻子
    if mouth == 0:
        d.line([(29, 41), (35, 41)], fill=8)
    elif mouth == 1:
        d.ellipse([29, 39, 35, 43], fill=8)
    else:
        d.ellipse([27, 38, 37, 46], fill=8)
        d.ellipse([29, 42, 35, 46], fill=14)
    # ---- 手拿麦克风（右手，麦克风头靠近嘴边）----
    d.line([(48, 55), (42, 47)], fill=15, width=2)               # 麦克风杆
    d.ellipse([39, 42, 45, 48], fill=7)                          # 麦克风头
    d.point([(40, 43), (41, 43)], fill=10)                       # 网罩高光
    d.ellipse([45, 51, 52, 58], fill=4)                          # 手
    d.arc([45, 51, 52, 58], 90, 200, fill=5)
    # ---- 描边：透明像素紧挨着非透明像素 → 描边色 ----
    px = im.load()
    edge = [(x, y) for y in range(N) for x in range(N) if px[x, y] == 0 and any(
        0 <= x + dx < N and 0 <= y + dy < N and px[x + dx, y + dy] not in (0, 1)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    for p in edge: px[p] = 1
    return im

FRAMES = [draw(0, False), draw(1, False), draw(2, False), draw(0, True)]

def write_rom(name, width, data):
    hd = (width + 3) // 4
    with open(os.path.join(OUT, name + ".hex"), "w") as f:
        for v in data: f.write(f"{v:0{hd}x}\n")
    with open(os.path.join(OUT, name + ".mif"), "w") as f:
        f.write(f"WIDTH={width};\nDEPTH={len(data)};\n\nADDRESS_RADIX=DEC;\nDATA_RADIX=HEX;\n\nCONTENT BEGIN\n")
        for a, v in enumerate(data): f.write(f"\t{a}\t:\t{v:0{hd}X};\n")
        f.write("END;\n")

pix = []
for im in FRAMES:
    pix += list(im.get_flattened_data())                                    # 地址 = 帧*4096 + 行*64 + 列
write_rom("avatar", 4, pix)
write_rom("avatar_pal", 24, [(r << 16) | (g << 8) | b for r, g, b in PAL])
od = OUT.replace("\\", "/")
with open(os.path.join(OUT, "..", "common", "avatar_cfg.vh"), "w", encoding="utf-8") as f:
    f.write("// 由 gen_avatar.py 生成，请勿手改\n")
    for n in ("avatar", "avatar_pal"):
        f.write(f'`define AV_{n.upper()}_MIF "{od}/{n}.mif"\n`define AV_{n.upper()}_HEX "{od}/{n}.hex"\n')
# 预览：4 帧放大 4 倍，绿色背景
sheet = Image.new("RGB", (N * 4 * 4 + 30, N * 4), (60, 110, 70))
for i, im in enumerate(FRAMES):
    rgb = Image.new("RGB", (N, N), (60, 110, 70))
    mask = Image.new("L", (N, N)); mask.putdata([255 if v else 0 for v in im.get_flattened_data()])
    rgb.paste(im.convert("RGB"), (0, 0), mask)
    sheet.paste(rgb.resize((N * 4, N * 4), Image.NEAREST), (i * (N * 4 + 10), 0))
sheet.save(os.path.join(OUT, "avatar_preview.png"))
print("ok")
