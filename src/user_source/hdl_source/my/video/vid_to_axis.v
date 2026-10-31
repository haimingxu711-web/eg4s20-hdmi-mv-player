// =====================================================================
// 像素流总线 → HDMI 1.4b 发射 IP 的 AXI-Stream 视频输入
//   user  : 一帧第一个有效像素
//   last  : 每行最后一个有效像素
//   valid : de
// 坐标直接来自总线，无需自行计数。
// =====================================================================
`include "vid_defs.vh"

module vid_to_axis #(
    parameter H_ACTIVE = 640
)(
    input  wire           clk,
    input  wire           rst,
    input  wire [`VB-1:0] vi,
    output reg            axis_user,
    output reg            axis_valid,
    output reg            axis_last,
    output reg  [23:0]    axis_data
);

wire de = `DE(vi);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        axis_user  <= 1'b0;
        axis_valid <= 1'b0;
        axis_last  <= 1'b0;
        axis_data  <= 24'd0;
    end else begin
        axis_valid <= de;
        axis_data  <= `RGB(vi);
        axis_user  <= de && (`X(vi) == 10'd0) && (`Y(vi) == 10'd0);
        axis_last  <= de && (`X(vi) == H_ACTIVE - 1);
    end
end

endmodule
