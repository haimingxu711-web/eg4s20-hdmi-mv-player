// =====================================================================
// 卡拉OK 歌词层（KTV 双行交替）
//   上行 y=Y0 起 24 像素，左对齐 X0，显示偶数句；下行 y=Y1 起，右对齐到 X1E，显示奇数句
//   正在唱的句子逐字变色（当前字按 wipe 逐像素推进），另一行预告下一句；歌名行（句 0 带标志）粉色
//   字库 24x24、2bpp：0 透明 1 描边 2 半亮边 3 填充（gen_theme.py 只渲染歌词用到的字）
//   歌词进度 line / chr_s / wipe 来自 aud_music，每帧消隐期锁存一次
// 延迟 3 拍（字表 1 拍 + 字库 1 拍 + 输出 1 拍）
// =====================================================================
`include "vid_defs.vh"
`include "theme_cfg.vh"

module fx_lyric #(
    parameter [9:0] Y0  = 10'd404,
    parameter [9:0] Y1  = 10'd436,
    parameter [9:0] X0  = 10'd40,
    parameter [9:0] X1E = 10'd600
)(
    input  wire           clk,
    input  wire           rst,
    input  wire           en,
    input  wire [7:0]     line,
    input  wire [10:0]    chr_s,
    input  wire [4:0]     wipe,
    input  wire [`VB-1:0] vi,
    output reg  [`VB-1:0] vo
);

// ---------------- 每帧：锁存进度，读两行的句表 ----------------
reg vs_d;
always @(posedge clk) vs_d <= `VS(vi);
wire fstart = vs_d & ~`VS(vi);

reg  [7:0]  la;
wire [15:0] lq;                                   // [15] 歌名 [14:10] 字数 [9:0] 首字序号
rom_sp #(.W(16), .AW(8), .DEPTH(256), .MIF(`TH_LYR_LINE_MIF), .HEX(`TH_LYR_LINE_HEX)) u_line(
    .clk(clk), .addr(la), .q(lq));

reg  [7:0]  L;
reg  [10:0] S;
reg  [4:0]  WP;
reg  [2:0]  seq;
reg  [9:0]  p0, p1, xe0, xs1;
reg         ok0, ok1, h0, h1, tt0, tt1;
reg  [7:0]  ln0, ln1;                             // 两行当前显示的句号（换句时淡入）
reg  [4:0]  fd0, fd1;                             // 淡入计数 0~16 帧
wire [7:0]  l_even = line[0] ? line + 8'd1 : line;
wire [7:0]  l_odd  = line[0] ? line : line + 8'd1;
wire [9:0]  w24    = {1'b0, lq[14:10], 4'd0} + {2'b0, lq[14:10], 3'd0};   // 字数 x 24
always @(posedge clk or posedge rst) begin
    if (rst) begin
        seq <= 3'd0; la <= 8'd0; L <= 8'd0; S <= 11'd0; WP <= 5'd0;
        p0 <= 10'd0; p1 <= 10'd0; xe0 <= 10'd0; xs1 <= 10'd0;
        ok0 <= 1'b0; ok1 <= 1'b0; h0 <= 1'b0; h1 <= 1'b0; tt0 <= 1'b0; tt1 <= 1'b0;
        ln0 <= 8'hFF; ln1 <= 8'hFF; fd0 <= 5'd0; fd1 <= 5'd0;
    end else begin
        case (seq)
        3'd0: if (fstart) begin L <= line; S <= chr_s; WP <= wipe; la <= l_even; seq <= 3'd1; end
        3'd1: seq <= 3'd2;                                    // 等 ROM
        3'd2: begin
            p0 <= lq[9:0]; xe0 <= X0 + w24; tt0 <= lq[15];
            ok0 <= (la < `TH_NLINES) && (lq[14:10] != 5'd0); h0 <= (la == L);
            ln0 <= la; fd0 <= (la != ln0) ? 5'd0 : (fd0 == 5'd16 ? fd0 : fd0 + 5'd1);
            la <= (L[0] ? L : L + 8'd1); seq <= 3'd3;
        end
        3'd3: seq <= 3'd4;
        3'd4: begin
            p1 <= lq[9:0]; xs1 <= X1E - w24; tt1 <= lq[15];
            ok1 <= (la < `TH_NLINES) && (lq[14:10] != 5'd0); h1 <= (la == L);
            ln1 <= la; fd1 <= (la != ln1) ? 5'd0 : (fd1 == 5'd16 ? fd1 : fd1 + 5'd1);
            seq <= 3'd0;
        end
        default: seq <= 3'd0;
        endcase
    end
end

// ---------------- 第 0 拍：定位行、列 ----------------
wire [9:0]  x  = `X(vi);
wire [9:0]  y  = `Y(vi);
wire        r0 = (y >= Y0) && (y < Y0 + 10'd24);
wire        r1 = (y >= Y1) && (y < Y1 + 10'd24);
wire [9:0]  xs = r1 ? xs1 : X0;
wire [9:0]  xe = r1 ? X1E : xe0;
wire [9:0]  ptr = r1 ? p1 : p0;
wire [9:0]  gyw = r1 ? (y - Y1) : (y - Y0);
// 列号 / 字内像素用计数器得到（避免除以 24）
reg  [4:0]  col_r, sub_r;
wire        start = (x == xs);
wire [4:0]  col_c = start ? 5'd0 : (sub_r == 5'd23 ? col_r + 5'd1 : col_r);
wire [4:0]  sub_c = start ? 5'd0 : (sub_r == 5'd23 ? 5'd0 : sub_r + 5'd1);
always @(posedge clk) if (`DE(vi)) begin col_r <= col_c; sub_r <= sub_c; end

wire        act0 = en && `DE(vi) && (r0 ? ok0 : r1 ? ok1 : 1'b0) && (x >= xs) && (x < xe);
wire [9:0]  g0   = ptr + {5'd0, col_c};                 // 全局字序号
wire [8:0]  gid;
rom_sp #(.W(9), .AW(10), .DEPTH(1024), .MIF(`TH_LYR_CHR_MIF), .HEX(`TH_LYR_CHR_HEX)) u_chr(
    .clk(clk), .addr(g0), .q(gid));

reg [`VB-1:0] v1;
reg           act1, hl1, tt1_p;
reg [4:0]     sub1, gy1, fd_1;
reg [9:0]     g1;
always @(posedge clk) begin
    v1 <= vi; act1 <= act0; sub1 <= sub_c; gy1 <= gyw[4:0]; g1 <= g0;
    hl1 <= r1 ? h1 : h0; tt1_p <= r1 ? tt1 : tt0; fd_1 <= r1 ? fd1 : fd0;
end

// ---------------- 第 1 拍：查字库 ----------------
wire [12:0] gaddr = {gid[7:0], 4'd0} + {1'b0, gid[7:0], 3'd0} + {8'd0, gy1};   // 字形号 x 24 + 行
wire [47:0] gq;
rom_sp #(.W(48), .AW(13), .DEPTH(`TH_GLYPH_DEPTH), .MIF(`TH_GLYPH_MIF), .HEX(`TH_GLYPH_HEX), .IMPL("32K")) u_glyph(
    .clk(clk), .addr(gaddr), .q(gq));

reg [`VB-1:0] v2;
reg           act2, hl2, tt2;
reg [4:0]     sub2, gy2, fd_2;
reg [9:0]     g2;
always @(posedge clk) begin
    v2 <= v1; act2 <= act1; sub2 <= sub1; gy2 <= gy1; g2 <= g1; hl2 <= hl1; tt2 <= tt1_p; fd_2 <= fd_1;
end

// 换句淡入：按 0/1/4、1/2、3/4、1 四档与背景混合（只用移位和加法）
function [7:0] mix4;
    input [7:0] bg, fg;
    input [2:0] lv;                  // 0~4
    reg   [9:0] s;
    begin
        case (lv)
            3'd0:    s = {bg, 2'b00};
            3'd1:    s = {1'b0, bg, 1'b0} + {2'b0, bg} + {2'b0, fg};
            3'd2:    s = {1'b0, bg, 1'b0} + {1'b0, fg, 1'b0};
            3'd3:    s = {2'b0, bg} + {1'b0, fg, 1'b0} + {2'b0, fg};
            default: s = {fg, 2'b00};
        endcase
        mix4 = s[9:2];
    end
endfunction

// ===================== 用户代码区：着色 =====================
wire [47:0] sh   = gq << {sub2, 1'b0};
wire [1:0]  px   = sh[47:46];
wire [10:0] gp1  = {1'b0, g2} + 11'd1;
wire        sung = hl2 && ((gp1 < S) || (gp1 == S && sub2 < WP));
wire [7:0]  grad = 8'h50 + {3'd0, gy2} * 8'd7;           // 已唱：上橙下黄渐变
wire [23:0] fill = tt2 ? 24'hFF9AD8 : sung ? {8'hFF, grad, 8'h30} : 24'h5CE6FF;   // 歌名粉色 / 已唱橙黄 / 未唱亮青（和剧集白字幕区分）
wire [23:0] rgb  = `RGB(v2);
wire [23:0] dark = {2'b0, rgb[23:18], 2'b0, rgb[15:10], 2'b0, rgb[7:2]};          // 描边：背景压暗 75%
wire [23:0] half = {1'b0, fill[23:17], 1'b0, fill[15:9], 1'b0, fill[7:1]} +
                   {1'b0, dark[23:17], 1'b0, dark[15:9], 1'b0, dark[7:1]};
wire [23:0] txt  = (px == 2'd3) ? fill : (px == 2'd2) ? half : (px == 2'd1) ? dark : rgb;
wire [2:0]  lv   = (fd_2 == 5'd16) ? 3'd4 : {1'b0, fd_2[3:2]};      // 16 帧（约 0.27s）内 4 档淡入
wire [23:0] rgb_new = {mix4(rgb[23:16], txt[23:16], lv), mix4(rgb[15:8], txt[15:8], lv), mix4(rgb[7:0], txt[7:0], lv)};
// ===========================================================

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= (act2 && `DE(v2)) ? `VSET_RGB(v2, rgb_new) : v2;
end

endmodule
