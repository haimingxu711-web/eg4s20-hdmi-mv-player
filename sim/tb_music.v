// 主题音乐仿真：加速采样节拍（每 8 拍一个），把事件/歌词进度/切图节点打印出来，PCM 写到 pcm.txt
`timescale 1ns/1ps
module tb_music;
reg clk = 0, rst = 1; always #20 clk = ~clk;
reg [2:0] tdiv = 0; reg tick = 0;
always @(posedge clk) begin tdiv <= tdiv + 1; tick <= (tdiv == 3'd7); end
reg restart = 0;
wire pv; wire signed [23:0] pl, pr; wire [7:0] line; wire [10:0] chs; wire [4:0] wipe; wire isw; wire [2:0] img; wire [1:0] sty;
aud_music u(.clk(clk), .rst(rst), .sample_tick(tick), .restart(restart), .volume(4'd15), .mute(1'b0),
    .pcm_valid(pv), .pcm_l(pl), .pcm_r(pr), .line(line), .chr_s(chs), .wipe(wipe), .img_sw(isw), .img(img), .style(sty));
integer n = 0, fd, peak = 0, mag;
reg [7:0] line_d = 8'hFF;
always @(posedge clk) begin
    if (tick) n = n + 1;
    if (pv) begin
        $fwrite(fd, "%0d\n", pl);
        mag = pl < 0 ? -pl : pl; if (mag > peak) peak = mag;
    end
    if (isw) $display("%8.3fs  切图 -> %0d  样式 %0d", n / 48000.0, img, sty);
    if (line != line_d) begin $display("%8.3fs  句 %0d  S=%0d", n / 48000.0, line, chs); line_d = line; end
    if (n == 48000 * 36) begin $display("PCM 峰值 %0d（满幅 8388607）", peak); $fclose(fd); $finish; end
end
// 中途检查一次逐字变色：第 5 秒打印
always @(posedge clk) if (tick && n == 48000 * 5 + 6000) $display("  5.125s: line=%0d S=%0d wipe=%0d", line, chs, wipe);
initial begin fd = $fopen("pcm.txt", "w"); #200 rst = 0; end
endmodule
