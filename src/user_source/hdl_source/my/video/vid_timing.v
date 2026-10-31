// =====================================================================
// 视频时序发生器：直接产生像素流总线（rgb 填 0，由后级填色）
// 默认 640x480@60Hz（像素时钟 25MHz，VESA 时序，hs/vs 低有效）
// 额外输出：
//   line_start  每个有效行开始前 LEAD 个时钟的单拍脉冲（给帧读取模块预取用）
//   frame_start 每帧开始（vs 起始）单拍脉冲
// =====================================================================
`include "vid_defs.vh"

module vid_timing #(
    parameter H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_BP = 48,
    parameter V_ACTIVE = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33
)(
    input  wire           clk,
    input  wire           rst,
    output reg  [`VB-1:0] vo,
    output reg            frame_start
);

localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;   // 800
localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;   // 525

reg [10:0] hc;   // 0..H_TOTAL-1，0~H_ACTIVE-1 为有效区
reg [10:0] vc;   // 0..V_TOTAL-1，0~V_ACTIVE-1 为有效区

always @(posedge clk or posedge rst) begin
    if (rst) begin
        hc <= 11'd0;
        vc <= 11'd0;
    end else if (hc == H_TOTAL - 1) begin
        hc <= 11'd0;
        vc <= (vc == V_TOTAL - 1) ? 11'd0 : vc + 11'd1;
    end else
        hc <= hc + 11'd1;
end

wire de = (hc < H_ACTIVE) && (vc < V_ACTIVE);
wire hs = ~((hc >= H_ACTIVE + H_FP) && (hc < H_ACTIVE + H_FP + H_SYNC));
wire vs = ~((vc >= V_ACTIVE + V_FP) && (vc < V_ACTIVE + V_FP + V_SYNC));

always @(posedge clk or posedge rst) begin
    if (rst) begin
        vo          <= {1'b1, 1'b1, 1'b0, 10'd0, 10'd0, 24'd0};
        frame_start <= 1'b0;
    end else begin
        vo          <= {vs, hs, de, de ? hc[9:0] : 10'd0, de ? vc[9:0] : 10'd0, 24'd0};
        frame_start <= (hc == 0) && (vc == V_ACTIVE + V_FP);   // 场同步开始
    end
end

endmodule
