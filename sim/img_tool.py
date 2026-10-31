"""
图像 <-> 仿真数据 转换工具
  python img_tool.py tohex  <图片> <输出.hex>      任意图片 → 640x480，每行一个 RRGGBB
  python img_tool.py topng  <输入.hex> <输出.png>  仿真输出 → PNG
"""
import sys
from PIL import Image, ImageOps
W, H = 640, 480
mode, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
if mode == 'tohex':
    img = ImageOps.exif_transpose(Image.open(src)).convert('RGB')
    img.thumbnail((W, H)); canvas = Image.new('RGB', (W, H)); canvas.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
    with open(dst, 'w') as f:
        for y in range(H):
            for x in range(W):
                r, g, b = canvas.getpixel((x, y)); f.write('%02x%02x%02x\n' % (r, g, b))
else:
    vals = [int(l, 16) for l in open(src) if l.strip()]
    img = Image.new('RGB', (W, H))
    img.putdata([((v >> 16) & 255, (v >> 8) & 255, v & 255) for v in vals[:W * H]])
    img.save(dst); print('saved', dst, len(vals), 'pixels')
