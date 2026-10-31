// =====================================================================
// OSD 文字图层：80 列 x 30 行字符网格（每格 8x16 像素）叠加到画面上
//   字符内容存放在内部字符 RAM 中，由写口 (wr_en, wr_addr=行*80+列, wr_char) 写入
//   字符 0 = 透明；其余字符（含空格）所在格子：背景压暗 50%，笔画为 fg_color
//   SCROLL_ROW 行为滚动字幕：每帧左移 1 像素，80 个字符循环
// 延迟 3 拍（字符 RAM 1 拍 + 字库 1 拍 + 输出 1 拍）
// =====================================================================
`include "vid_defs.vh"

module osd_layer #(
    parameter [4:0] SCROLL_ROW = 5'd28
)(
    input  wire           clk,
    input  wire           rst,
    input  wire           en,
    input  wire           scroll_en,
    input  wire [23:0]    fg_color,
    input  wire [23:0]    sub_color,          // 字幕颜色
    // 字符 RAM 写口
    input  wire           wr_en,
    input  wire [11:0]    wr_addr,
    input  wire [6:0]     wr_char,
    // 像素流
    input  wire [`VB-1:0] vi,
    output reg  [`VB-1:0] vo
);

// ---------------- 字符 RAM ----------------
reg [6:0] cram [0:2399];
always @(posedge clk) if (wr_en && wr_addr < 12'd2400) cram[wr_addr] <= wr_char;

// ---------------- 滚动偏移 ----------------
reg       vs_d;
reg [9:0] scroll;                                 // 0..639
always @(posedge clk or posedge rst) begin
    if (rst) begin vs_d <= 1'b1; scroll <= 10'd0; end
    else begin
        vs_d <= `VS(vi);
        if (vs_d & ~`VS(vi) && scroll_en)
            scroll <= (scroll == 10'd639) ? 10'd0 : scroll + 10'd1;
    end
end

// ---------------- 第 1 拍：查字符 ----------------
wire [9:0]  x = `X(vi);
wire [9:0]  y = `Y(vi);
wire [4:0]  row = y[8:4];
wire        is_sub = (row == SCROLL_ROW);
wire [10:0] xs_raw = {1'b0, x} + {1'b0, scroll};
wire [9:0]  xs = is_sub ? ((xs_raw >= 11'd640) ? xs_raw - 11'd640 : xs_raw[9:0]) : x;
wire [6:0]  col = xs[9:3];

reg [6:0]     ch;
reg [`VB-1:0] v1;
reg [2:0]     px1;
reg [3:0]     fr1;
reg           sub1;
always @(posedge clk) begin
    ch   <= cram[{7'd0, row} * 12'd80 + {5'd0, col}];      // 显式 12 位，避免乘积截断
    v1   <= vi;
    px1  <= xs[2:0];
    fr1  <= y[3:0];
    sub1 <= is_sub;
end

// ---------------- 第 2 拍：查字库 ----------------
wire [7:0] glyph;
wire       ch_vis = (ch != 7'd0);                     // 0 = 透明，空格 = 暗底空白
font_rom u_font(.clk(clk), .addr({(ch_vis ? ch : 7'd32), fr1}), .data(glyph));

reg [`VB-1:0] v2;
reg [2:0]     px2;
reg           vis2, sub2;
always @(posedge clk) begin
    v2   <= v1;
    px2  <= px1;
    vis2 <= ch_vis;
    sub2 <= sub1;
end

// ===================== 用户代码区：合成 =====================
wire [23:0] rgb  = `RGB(v2);
wire        bit_on = glyph[3'd7 - px2];
wire [23:0] dark = {1'b0, rgb[23:17], 1'b0, rgb[15:9], 1'b0, rgb[7:1]};   // 压暗 50%
wire [23:0] rgb_new = !vis2 ? rgb : bit_on ? (sub2 ? sub_color : fg_color) : dark;
// ===========================================================

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= (en && `DE(v2)) ? `VSET_RGB(v2, rgb_new) : v2;
end

endmodule
