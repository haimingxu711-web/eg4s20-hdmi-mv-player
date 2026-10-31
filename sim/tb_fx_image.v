// 图像效果仿真：两张 640x480 图片 → 转场/亮度对比度/OSD 效果链 → out.hex
// 改下面 initial 里的参数即可看不同效果；用 img_tool.py 转成 PNG 查看
`timescale 1ns/1ps
`include "vid_defs.vh"
module tb_fx_image;
reg clk = 0, rst = 1; always #20 clk = ~clk;
reg [23:0] img_a [0:307199];
reg [23:0] img_b [0:307199];
initial begin $readmemh("a.hex", img_a); $readmemh("b.hex", img_b); end

// ---- 效果参数（按需修改） ----
reg        fade_en = 1;  reg [7:0] alpha = 8'd96;
reg        bc_en   = 1;  reg signed [3:0] bri = 4'sd2;  reg [3:0] con = 4'd10;
reg        set_mode = 1; reg [1:0] item = 2'd1;

wire [`VB-1:0] v_tim, v_src, v_fade, v_bc, v_osd; wire fs;
vid_timing u_tim(.clk(clk), .rst(rst), .vo(v_tim), .frame_start(fs));
// 模拟帧源：同 vid_frame_src 一样延迟 1 拍
reg [`VB-1:0] vsrc_r; reg [23:0] rgb_b_r;
always @(posedge clk) begin
    vsrc_r  <= `DE(v_tim) ? `VSET_RGB(v_tim, img_a[`Y(v_tim)*640 + `X(v_tim)]) : v_tim;
    rgb_b_r <= img_b[`Y(v_tim)*640 + `X(v_tim)];
end
assign v_src = vsrc_r;
fx_fade  u_fade(.clk(clk), .rst(rst), .en(fade_en), .alpha(alpha), .vi(v_src), .rgb_b(rgb_b_r), .vo(v_fade));
fx_bc    u_bc  (.clk(clk), .rst(rst), .en(bc_en), .brightness(bri), .contrast(con), .vi(v_fade), .vo(v_bc));
wire osd_we; wire [11:0] osd_wa; wire [6:0] osd_wc;
osd_writer u_ow(.clk(clk), .rst(rst), .status_on(1'b1), .sub_on(1'b1), .set_mode(set_mode), .item(item),
    .cur(2'd1), .img_count(3'd4), .auto_on(1'b1), .period_sec(4'd3), .brightness(bri), .contrast(con),
    .volume(4'd6), .fade_on(fade_en), .wr_en(osd_we), .wr_addr(osd_wa), .wr_char(osd_wc));
osd_layer u_osd(.clk(clk), .rst(rst), .en(1'b1), .scroll_en(1'b1), .fg_color(24'hFFFFFF), .sub_color(24'hFFD700),
    .wr_en(osd_we), .wr_addr(osd_wa), .wr_char(osd_wc), .vi(v_bc), .vo(v_osd));

integer fd, frame = 0;
always @(posedge clk) begin
    if (fs) begin
        frame = frame + 1;
        if (frame == 3) begin $fclose(fd); $display("written out.hex"); $finish; end
        if (frame == 2) fd = $fopen("out.hex", "w");
    end
    if (frame == 2 && `DE(v_osd)) $fwrite(fd, "%06h\n", `RGB(v_osd));
end
initial #100 rst = 0;
endmodule
