// =====================================================================
// 测试画面源：上半屏 8 色竖条，下半屏灰度渐变，一个来回弹跳的白色方块
// （验证时序/HDMI 通路用；也是 "按模板写效果" 的第二个例子）
// =====================================================================
`include "vid_defs.vh"

module fx_testpat(
    input  wire           clk,
    input  wire           rst,
    input  wire [`VB-1:0] vi,
    output reg  [`VB-1:0] vo
);

wire [9:0] x  = `X(vi);
wire [9:0] y  = `Y(vi);
wire       de = `DE(vi);

reg vs_d;
always @(posedge clk) vs_d <= `VS(vi);
wire frame_start = vs_d & ~`VS(vi);

// 方块位置：每帧移动 4 像素，碰边反弹
reg [9:0] bx;
reg       dir;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        bx <= 10'd0; dir <= 1'b0;
    end else if (frame_start) begin
        if (!dir) begin
            if (bx >= 10'd640 - 64 - 4) dir <= 1'b1; else bx <= bx + 10'd4;
        end else begin
            if (bx <= 10'd4)            dir <= 1'b0; else bx <= bx - 10'd4;
        end
    end
end

// ===================== 用户代码区 =====================
reg [23:0] rgb_new;
always @(*) begin
    if (x >= bx && x < bx + 10'd64 && y >= 10'd208 && y < 10'd272)
        rgb_new = 24'hFFFFFF;                                 // 方块
    else if (y < 10'd240) begin                               // 80 像素一条
        if      (x < 10'd80)  rgb_new = 24'hFFFFFF;
        else if (x < 10'd160) rgb_new = 24'hFFFF00;
        else if (x < 10'd240) rgb_new = 24'h00FFFF;
        else if (x < 10'd320) rgb_new = 24'h00FF00;
        else if (x < 10'd400) rgb_new = 24'hFF00FF;
        else if (x < 10'd480) rgb_new = 24'hFF0000;
        else if (x < 10'd560) rgb_new = 24'h0000FF;
        else                  rgb_new = 24'h000000;
    end else
        rgb_new = {3{x[9:2]}};                                // 灰度渐变
end
// =====================================================

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= de ? `VSET_RGB(vi, rgb_new) : vi;
end

endmodule
