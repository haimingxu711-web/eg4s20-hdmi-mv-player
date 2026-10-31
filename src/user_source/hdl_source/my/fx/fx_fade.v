// =====================================================================
// 转场效果（A = 当前图，B = 下一张，alpha = 进度 0~255，已由 player 做缓入缓出）
//   每种样式算出两个混合源 X、Y 和权重 w（0~256），统一用一个混合器：out = (X*(256-w) + Y*w) / 256
//   一般 X = A、Y = B；“经白/经黑”前半程 X=A、Y=白/黑，后半程 X=白/黑、Y=B
//   style 0 淡入淡出：w = alpha
//   style 1 擦除    ：从左到右揭开 B，边界带 64 像素柔和过渡
//   style 2 百叶窗  ：每 64 行一条，逐条展开 B，边缘 16 行过渡
//   style 3 圆形展开：从屏幕中心向外扩散，边缘 32 像素过渡
//   style 4 亮度溶解：按 B 的明暗逐步显现，暗部先出、亮部后出（像墨晕开），MV 用
//   style 5 经白淡化：A → 柔白 → B，适合副歌/高潮
//   style 6 经黑淡化：A → 黑 → B，适合段落结束/循环回开头
//   style 7 长淡入淡出（同 0，时长由 player 决定）
// （按 fx_template 写法：新增样式 = 算 w（必要时换 X/Y），在 case 里加一行）
// =====================================================================
`include "vid_defs.vh"

module fx_fade(
    input  wire           clk,
    input  wire           rst,
    input  wire           en,           // 转场进行中
    input  wire [7:0]     alpha,        // 进度
    input  wire [2:0]     style,
    input  wire [`VB-1:0] vi,           // A 路
    input  wire [23:0]    rgb_b,        // B 路（与 vi 同拍）
    output reg  [`VB-1:0] vo
);

wire [9:0]  x   = `X(vi);
wire [9:0]  y   = `Y(vi);
wire        de  = `DE(vi);
wire [23:0] rgb = `RGB(vi);

// 有符号距离 d（正 = 已进入 B 区）乘以 2^sh 后限制到 0~256
function [8:0] ramp;
    input signed [12:0] d;
    input [2:0]         sh;
    reg   signed [16:0] v;
    begin
        v = d <<< sh;
        ramp = (v <= 17'sd0) ? 9'd0 : (v >= 17'sd256) ? 9'd256 : v[8:0];
    end
endfunction

// ===================== 用户代码区 =====================
// 1 擦除：边界 pos ≈ alpha*2.8（0~715），d = pos - x
wire [10:0] wipe_pos = {2'b0, alpha, 1'b0} + {4'b0, alpha[7:1]} + {5'b0, alpha[7:2]} + {7'b0, alpha[7:4]};
wire signed [12:0] d_wipe  = $signed({2'b0, wipe_pos}) - $signed({3'b0, x});
// 2 百叶窗：每条展开到 pb = alpha*3/8（0~94），d = pb - 条内行号
wire [7:0]  pb = {2'b0, alpha[7:2]} + {3'b0, alpha[7:3]};
wire signed [12:0] d_blind = $signed({5'b0, pb}) - $signed({7'b0, y[5:0]});
// 3 圆形：距离近似 max + 3/8*min，半径 r ≈ alpha*1.78（0~452）
wire [9:0]  dx   = (x >= 10'd320) ? x - 10'd320 : 10'd320 - x;
wire [9:0]  dy   = (y >= 10'd240) ? y - 10'd240 : 10'd240 - y;
wire [9:0]  dmx  = (dx > dy) ? dx : dy;
wire [9:0]  dmn  = (dx > dy) ? dy : dx;
wire [10:0] dist = {1'b0, dmx} + {3'b0, dmn[9:2]} + {4'b0, dmn[9:3]};
wire [10:0] rad  = {3'b0, alpha} + {4'b0, alpha[7:1]} + {5'b0, alpha[7:2]} + {8'b0, alpha[7:5]};
wire signed [12:0] d_iris = $signed({2'b0, rad}) - $signed({2'b0, dist});
// 4 亮度溶解：B 的亮度 lum = (R + 2G + B)/4；门限 thr = alpha*1.25（0~318），d = thr - lum，64 级过渡
wire [9:0]  lum_sum = {2'b0, `R8(rgb_b)} + {1'b0, `G8(rgb_b), 1'b0} + {2'b0, `B8(rgb_b)};
wire [7:0]  lum     = lum_sum[9:2];
wire [9:0]  thr     = {2'b0, alpha} + {4'b0, alpha[7:2]};
wire signed [12:0] d_luma = $signed({3'b0, thr}) - $signed({5'b0, lum});
// 5/6 经白/经黑：前半程 A→中间色，后半程 中间色→B；半程内 w = (alpha 的低 7 位)*2
wire        second = alpha[7];
wire [8:0]  w_half = {1'b0, alpha[6:0], 1'b0} + {8'd0, alpha[6]};      // 0~256
wire [23:0] mid_c  = (style == 3'd5) ? 24'hF6F2EA : 24'h000000;       // 柔白（略暖）/ 黑

reg [8:0]  w;                        // Y 的权重 0~256
reg [23:0] cx, cy;                   // 混合源
always @(*) begin
    cx = rgb; cy = rgb_b;
    case (style)
        3'd1:    w = ramp(d_wipe, 3'd2);                     // 64 像素过渡带
        3'd2:    w = ramp(d_blind, 3'd4);                    // 16 行过渡
        3'd3:    w = ramp(d_iris, 3'd3);                     // 32 像素过渡
        3'd4:    w = ramp(d_luma, 3'd2);                     // 64 级亮度过渡
        3'd5, 3'd6: begin
                 w = w_half;
                 if (second) cx = mid_c; else cy = mid_c;
        end
        default: w = {1'b0, alpha} + {8'd0, alpha[7]};       // 0 / 7：淡入淡出，0~256
    endcase
end
// =====================================================

wire [8:0]  wa = 9'd256 - w;
wire [16:0] r_mix = `R8(cx) * wa + `R8(cy) * w;
wire [16:0] g_mix = `G8(cx) * wa + `G8(cy) * w;
wire [16:0] b_mix = `B8(cx) * wa + `B8(cy) * w;
wire [23:0] rgb_new = {r_mix[15:8], g_mix[15:8], b_mix[15:8]};

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= (en && de) ? `VSET_RGB(vi, rgb_new) : vi;
end

endmodule
