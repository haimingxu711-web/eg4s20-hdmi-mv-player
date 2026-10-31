# 用 Windows 等宽字体渲染 ASCII 32~126 为 8x16 点阵，生成 font_rom.v
import os, sys
from PIL import Image, ImageDraw, ImageFont
FONT = r"C:\Windows\Fonts\consola.ttf"
font = ImageFont.truetype(FONT, 14)
L = ["// 8x16 ASCII 点阵字库（字符 32~126），由 gen_font.py 生成",
     "// addr = {char[6:0], row[3:0]}，data 最高位 = 最左像素",
     "module font_rom(", "    input  wire        clk,", "    input  wire [10:0] addr,",
     "    output reg  [7:0]  data", ");", "always @(posedge clk) begin", "    case (addr)"]
preview = []
for c in range(32, 127):
    img = Image.new("L", (8, 16), 0)
    d = ImageDraw.Draw(img)
    bbox = font.getbbox("M")
    d.text((0, 1 - bbox[1] + 1), chr(c), font=font, fill=255)
    for r in range(16):
        bits = 0
        for x in range(8):
            if img.getpixel((x, r)) > 110: bits |= 0x80 >> x
        if bits: L.append(f"        11'h{(c << 4) | r:03x}: data <= 8'h{bits:02x};")
        if chr(c) in "A8": preview.append(format(bits, "08b").replace("0", ".").replace("1", "#"))
L += ["        default: data <= 8'h00;", "    endcase", "end", "endmodule"]
out = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "font_rom.v")
open(out, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("\n".join(preview))
