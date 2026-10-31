// 演唱小人 + 歌词画面仿真：图片 → fx_avatar → fx_lyric → OUT（hex）
`timescale 1ns/1ps
`include "vid_defs.vh"
module tb_avatar;
parameter integer ENV = 16'hC000, SING = 1;
parameter integer LINE = 9, CHS = 75, WIPE = 12;
parameter OUT = "av.hex";
parameter integer SHOT = 20;
reg clk = 0, rst = 1; always #20 clk = ~clk;
reg [23:0] img_a [0:307199];
initial $readmemh("../run_fx/a.hex", img_a);
wire [`VB-1:0] v_tim, v_av, v_lyr; wire fs;
vid_timing u_tim(.clk(clk), .rst(rst), .vo(v_tim), .frame_start(fs));
reg [`VB-1:0] vsrc_r;
always @(posedge clk) vsrc_r <= `DE(v_tim) ? `VSET_RGB(v_tim, img_a[`Y(v_tim)*640 + `X(v_tim)]) : v_tim;
fx_avatar u_av (.clk(clk), .rst(rst), .en(1'b1), .sing(SING != 0), .env(ENV[15:0]), .note_on(1'b0), .vi(vsrc_r), .vo(v_av));
fx_lyric  u_lyr(.clk(clk), .rst(rst), .en(1'b1), .line(LINE[7:0]), .chr_s(CHS[10:0]), .wipe(WIPE[4:0]), .vi(v_av), .vo(v_lyr));
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
