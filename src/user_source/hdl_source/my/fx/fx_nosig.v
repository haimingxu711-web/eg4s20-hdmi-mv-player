// =====================================================================
// 无图兜底画面：en=1 时（未装载/无有效图片）输出彩条 + 底部状态色带
//   底部色带颜色表示状态：红 = 文件系统错误，黄 = 正在装载，蓝 = 卡未就绪
// =====================================================================
`include "vid_defs.vh"

module fx_nosig(
    input  wire           clk,
    input  wire           rst,
    input  wire           en,
    input  wire [1:0]     status,       // 0 卡未就绪 1 装载中 2 文件系统错误 3 无图片
    input  wire [`VB-1:0] vi,
    output reg  [`VB-1:0] vo
);

wire [9:0] x  = `X(vi);
wire [9:0] y  = `Y(vi);
wire       de = `DE(vi);

// ===================== 用户代码区 =====================
reg [23:0] rgb_new;
always @(*) begin
    if (y >= 10'd440)
        case (status)
            2'd0: rgb_new = 24'h0000FF;
            2'd1: rgb_new = 24'hFFFF00;
            2'd2: rgb_new = 24'hFF0000;
            default: rgb_new = 24'h808080;
        endcase
    else if (x < 10'd80)  rgb_new = 24'hFFFFFF;
    else if (x < 10'd160) rgb_new = 24'hFFFF00;
    else if (x < 10'd240) rgb_new = 24'h00FFFF;
    else if (x < 10'd320) rgb_new = 24'h00FF00;
    else if (x < 10'd400) rgb_new = 24'hFF00FF;
    else if (x < 10'd480) rgb_new = 24'hFF0000;
    else if (x < 10'd560) rgb_new = 24'h0000FF;
    else                  rgb_new = 24'h000000;
end
// =====================================================

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= (en && de) ? `VSET_RGB(vi, rgb_new) : vi;
end

endmodule
