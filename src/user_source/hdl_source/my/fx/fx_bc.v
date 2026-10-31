// =====================================================================
// 亮度 / 对比度调节（逐通道）：
//   out = clamp( (in - 128) * contrast / 8 + 128 + brightness * 8 )
//   brightness : -8 ~ +7（有符号），每档 ±8 灰阶
//   contrast   : 0 ~ 15，8 = 原始对比度
// =====================================================================
`include "vid_defs.vh"

module fx_bc(
    input  wire              clk,
    input  wire              rst,
    input  wire              en,
    input  wire signed [3:0] brightness,
    input  wire        [3:0] contrast,
    input  wire [`VB-1:0]    vi,
    output reg  [`VB-1:0]    vo
);

wire [23:0] rgb = `RGB(vi);

function [7:0] adj(input [7:0] c, input [3:0] con, input signed [3:0] bri);
    reg signed [13:0] t;
    begin
        t = (($signed({6'd0, c}) - 14'sd128) * $signed({10'd0, con})) >>> 3;
        t = t + 14'sd128 + ($signed(bri) * 14'sd8);
        adj = (t < 0) ? 8'd0 : (t > 255) ? 8'd255 : t[7:0];
    end
endfunction

// ===================== 用户代码区 =====================
wire [23:0] rgb_new = { adj(`R8(rgb), contrast, brightness),
                        adj(`G8(rgb), contrast, brightness),
                        adj(`B8(rgb), contrast, brightness) };
// =====================================================

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= (en && `DE(vi)) ? `VSET_RGB(vi, rgb_new) : vi;
end

endmodule
