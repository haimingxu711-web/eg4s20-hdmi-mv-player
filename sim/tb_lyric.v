// 歌词层 + 转场画面仿真：两张图 → fx_fade → fx_lyric → OUT（hex），用 img_tool.py 转 PNG
// 参数用 vsim -G 改：STYLE/ALPHA/FADE_EN 转场；LINE/CHS/WIPE 歌词进度
`timescale 1ns/1ps
`include "vid_defs.vh"
module tb_lyric;
parameter integer STYLE = 0, ALPHA = 128, FADE_EN = 0;
parameter integer LINE = 1, CHS = 12, WIPE = 12;
parameter OUT = "out.hex";
parameter integer SHOT = 20;                 // 截第几帧（歌词换句淡入需要 16 帧）
reg clk = 0, rst = 1; always #20 clk = ~clk;
reg [23:0] img_a [0:307199];
reg [23:0] img_b [0:307199];
initial begin $readmemh("../run_fx/a.hex", img_a); $readmemh("../run_fx/b.hex", img_b); end
wire [`VB-1:0] v_tim, v_fade, v_lyr; wire fs;
vid_timing u_tim(.clk(clk), .rst(rst), .vo(v_tim), .frame_start(fs));
reg [`VB-1:0] vsrc_r; reg [23:0] rgb_b_r;
always @(posedge clk) begin
    vsrc_r  <= `DE(v_tim) ? `VSET_RGB(v_tim, img_a[`Y(v_tim)*640 + `X(v_tim)]) : v_tim;
    rgb_b_r <= img_b[`Y(v_tim)*640 + `X(v_tim)];
end
fx_fade  u_fade(.clk(clk), .rst(rst), .en(FADE_EN != 0), .alpha(ALPHA[7:0]), .style(STYLE[2:0]), .vi(vsrc_r), .rgb_b(rgb_b_r), .vo(v_fade));
fx_lyric u_lyr (.clk(clk), .rst(rst), .en(1'b1), .line(LINE[7:0]), .chr_s(CHS[10:0]), .wipe(WIPE[4:0]), .vi(v_fade), .vo(v_lyr));
integer fd, frame = 0;
always @(posedge clk) begin
    if (fs) begin
        frame = frame + 1;
        if (frame == SHOT + 1) begin $fclose(fd); $finish; end
        if (frame == SHOT) fd = $fopen(OUT, "w");
    end
    if (frame == SHOT && `DE(v_lyr)) $fwrite(fd, "%06h\n", `RGB(v_lyr));
end
initial #100 rst = 0;
endmodule
