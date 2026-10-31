"""
OSD 文字模板 → osd_writer.v
改 OSD 显示内容只需改下面三处，然后运行： python gen_osd.py

  STATUS   : 第 0 行状态栏，{名字} 为动态字段（宽度 = FIELDS 里给的表达式个数）
  SUBTITLE : 滚动字幕文字（第 28 行，最多 80 字符，循环滚动）
  FIELDS   : 每个字段 = 若干个 Verilog 表达式，每个表达式算出一个 ASCII 字符
  MENU     : 设置模式下，在这些标签前显示 '>' 表示当前选中的参数项（item 编号: 标签）
"""
import os, sys

STATUS   = " IMG {img}/{cnt}  MODE {mode}  PERIOD {per}s  BRIGHT {bri}  CONTRAST {con}  VOLUME {vol}  FADE {fade}"
SUBTITLE = "  Anlogic EG4S20 HDMI Multimedia Player  ***  FAT32 + SDRAM preload + DDS music  ***  KEY2 next  KEY4 auto  "
MENU     = {0: "BRIGHT", 1: "CONTRAST", 2: "VOLUME", 3: "PERIOD"}

D = lambda e: f"(7'd48 + {e})"                      # 数字 0~9 → ASCII
FIELDS = {
    "img":  [D("{5'd0, cur} + 7'd1")],
    "cnt":  [D("{4'd0, img_count}")],
    "mode": ["(mode == 2'd2 ? 7'd32 : mode == 2'd1 ? 7'd65 : 7'd77)", "(mode == 2'd2 ? 7'd77 : mode == 2'd1 ? 7'd85 : 7'd65)", "(mode == 2'd2 ? 7'd86 : mode == 2'd1 ? 7'd84 : 7'd78)"],   # "MAN" / "AUT" / " MV"
    "per":  [D("{3'd0, period_sec}")],
    "bri":  ["(brightness[3] ? 7'd45 : 7'd43)", D("{3'd0, (brightness[3] ? -brightness : brightness)}")],
    "con":  [D("(contrast >= 4'd10 ? 7'd1 : 7'd0)"), D("{3'd0, (contrast >= 4'd10 ? contrast - 4'd10 : contrast)}")],
    "vol":  [D("(volume >= 4'd10 ? 7'd1 : 7'd0)"),   D("{3'd0, (volume >= 4'd10 ? volume - 4'd10 : volume)}")],
    "fade": ["(fade_on ? 7'd32 : 7'd79)", "(fade_on ? 7'd79 : 7'd70)", "(fade_on ? 7'd78 : 7'd70)"],
}

# ---------- 展开状态栏模板 ----------
cells = []                     # 每列：('c', 字符) 或 ('e', 表达式)
i = 0
while i < len(STATUS):
    if STATUS[i] == '{':
        j = STATUS.index('}', i)
        cells += [('e', e) for e in FIELDS[STATUS[i+1:j]]]
        i = j + 1
    else:
        cells.append(('c', STATUS[i])); i += 1
assert len(cells) <= 80, "状态栏超过 80 列"
menu_cols = {}
plain = ''.join(c if k == 'c' else '#' for k, c in cells)
for item, label in MENU.items():
    p = plain.index(label)
    menu_cols[p - 1] = item

sub = SUBTITLE.ljust(80)[:80]

L = []
L += ["// 由 gen_osd.py 生成，请修改 gen_osd.py 后重新生成",
      "// 持续把状态栏（第 0 行）和字幕（第 28 行）写入 osd_layer 的字符 RAM",
      "module osd_writer(",
      "    input  wire              clk,",
      "    input  wire              rst,",
      "    input  wire              status_on,      // 显示状态栏",
      "    input  wire              sub_on,         // 显示字幕",
      "    input  wire              set_mode,",
      "    input  wire [1:0]        item,",
      "    input  wire [1:0]        cur,",
      "    input  wire [2:0]        img_count,",
      "    input  wire [1:0]        mode,",
      "    input  wire [3:0]        period_sec,",
      "    input  wire signed [3:0] brightness,",
      "    input  wire [3:0]        contrast,",
      "    input  wire [3:0]        volume,",
      "    input  wire              fade_on,",
      "    output reg               wr_en,",
      "    output reg  [11:0]       wr_addr,",
      "    output reg  [6:0]        wr_char",
      ");",
      "reg [6:0] col;",
      "reg       row_sel;                 // 0 = 状态栏，1 = 字幕",
      "reg [6:0] st_c, sb_c;",
      "always @(*) begin",
      "    case (col)"]
for c, (k, v) in enumerate(cells):
    expr = f"7'd{ord(v)}" if k == 'c' else v
    if c in menu_cols:
        expr = f"((set_mode && item == 2'd{menu_cols[c]}) ? 7'd62 : {expr})"
    L.append(f"        7'd{c}: st_c = {expr};")
L += ["        default: st_c = 7'd32;", "    endcase", "    case (col)"]
for c, ch in enumerate(sub):
    L.append(f"        7'd{c}: sb_c = 7'd{ord(ch)};")
L += ["        default: sb_c = 7'd32;", "    endcase", "end",
      "// 复位后先把整个字符 RAM（2400 格）清成透明(0)，再循环刷新两行",
      "reg [11:0] clr_addr;",
      "reg        clearing;",
      "always @(posedge clk or posedge rst) begin",
      "    if (rst) begin col <= 7'd0; row_sel <= 1'b0; wr_en <= 1'b0; wr_addr <= 12'd0; wr_char <= 7'd32;",
      "                   clr_addr <= 12'd0; clearing <= 1'b1; end",
      "    else if (clearing) begin",
      "        wr_en <= 1'b1; wr_addr <= clr_addr; wr_char <= 7'd0;",
      "        if (clr_addr == 12'd2399) clearing <= 1'b0; else clr_addr <= clr_addr + 12'd1;",
      "    end else begin",
      "        wr_en   <= 1'b1;",
      "        wr_addr <= row_sel ? (12'd28 * 12'd80 + col) : {5'd0, col};",
      "        wr_char <= row_sel ? (sub_on ? sb_c : 7'd0) : (status_on ? st_c : 7'd0);   // 0 = 透明",
      "        if (col == 7'd79) begin col <= 7'd0; row_sel <= ~row_sel; end",
      "        else col <= col + 7'd1;",
      "    end",
      "end",
      "endmodule"]
out = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "osd_writer.v")
open(out, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("status:", plain)
print("menu marker cols:", menu_cols)
