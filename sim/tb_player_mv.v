// 播放器模式/MV 切图仿真：frame_start 每 16 拍一次
`timescale 1ns/1ps
module tb_player_mv;
reg clk = 0, rst = 1; always #20 clk = ~clk;
reg [3:0] fc = 0; wire fs = (fc == 0); always @(posedge clk) fc <= fc + 1;
reg k_next = 0, k_auto = 0, mv_sw = 0; reg [2:0] mv_img = 0; reg [1:0] mv_style = 0;
wire [1:0] sa, sb, sty, mode, cur, ps; wire [7:0] alpha; wire fading, mrs; wire [3:0] psec;
player u(.clk(clk), .rst(rst), .frame_start(fs), .ready(1'b1), .img_count(3'd4), .k_next(k_next), .k_auto(k_auto),
    .fade_en(1'b1), .mv_sw(mv_sw), .mv_img(mv_img), .mv_style(mv_style), .slot_a(sa), .slot_b(sb), .alpha(alpha),
    .fading(fading), .style(sty), .mode(mode), .music_restart(mrs), .period_sel(2'd0), .period_sec(psec), .cur(cur));
task pulse_auto; begin @(posedge clk) k_auto <= 1; @(posedge clk) k_auto <= 0; end endtask
task mv(input [2:0] i, input [1:0] s); begin @(posedge clk) begin mv_sw <= 1; mv_img <= i; mv_style <= s; end @(posedge clk) mv_sw <= 0; end endtask
reg fading_d = 0;
always @(posedge clk) begin
    fading_d <= fading;
    if (fading & !fading_d) $display("%0t 转场开始 %0d -> %0d 样式 %0d 模式 %0d", $time, sa, sb, sty, mode);
    if (!fading & fading_d) $display("%0t 转场结束 cur=%0d", $time, cur);
    if (mrs) $display("%0t 音乐重新开始", $time);
end
// 采样缓动曲线
always @(posedge clk) if (fs && fading && (u.t == 8'd0 || u.t == 8'd64 || u.t == 8'd128 || u.t == 8'd192 || u.t == 8'd252)) $display("    t=%0d alpha=%0d", u.t, alpha);
initial begin
    #100 rst = 0;
    #2000 mv(3'd2, 2'd1);                // 手动模式：MV 节点应被忽略
    #2000 pulse_auto;                    // → 定时轮播（2 秒 = 120 帧）
    #(16*40*130*1) ;
    pulse_auto;                          // → MV，应发 restart
    #(16*40*80) mv(3'd3, 2'd3);          // 切到图 3（样式 3）
    #(16*40*20) mv(3'd1, 2'd2);          // 转场中到来：结束后再切到图 1
    #(16*40*160) mv(3'd1, 2'd0);         // 已是图 1：忽略
    #(16*40*10) k_next <= 1; #40 k_next <= 0;   // MV 中手动下一张
    #(16*40*100) $finish;
end
endmodule
