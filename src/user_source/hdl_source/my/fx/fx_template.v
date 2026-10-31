// =====================================================================
// 【画面效果模板】 新增一个效果的步骤：
//   1. 复制本文件，改文件名和模块名（例：fx_gray.v / module fx_gray）
//   2. 需要外部参数就在端口里加（例：input wire [7:0] level）
//   3. 只改下面 "用户代码区" 里的一行或几行：根据输入算出 rgb_new
//   4. 在顶层效果链里加一行实例化，把上一级 vo 接到本级 vi
//
// 可直接使用的输入（都已与当前像素对齐）：
//   x, y          当前像素坐标
//   r, g, b       当前像素的 8 位分量
//   rgb           当前像素 24 位颜色
//   de            是否有效像素
//   frame_start   每帧开始时的单拍脉冲（做动画计数用）
// 固定延迟 1 拍；en=0 时直通（效果关闭）。
// =====================================================================
`include "vid_defs.vh"

module fx_template(
    input  wire           clk,
    input  wire           rst,
    input  wire           en,          // 效果开关（接拨码或参数寄存器）
    input  wire [`VB-1:0] vi,          // 上一级像素流
    output reg  [`VB-1:0] vo           // 本级输出像素流
);

// ---------- 现成可用的信号（不用改） ----------
wire [9:0]  x   = `X(vi);
wire [9:0]  y   = `Y(vi);
wire        de  = `DE(vi);
wire [23:0] rgb = `RGB(vi);
wire [7:0]  r   = `R8(rgb);
wire [7:0]  g   = `G8(rgb);
wire [7:0]  b   = `B8(rgb);

reg vs_d;
always @(posedge clk) vs_d <= `VS(vi);
wire frame_start = vs_d & ~`VS(vi);          // vs 下降沿 = 新一帧

// ===================== 用户代码区（只改这里） =====================
// 例：反色效果
wire [23:0] rgb_new = ~rgb;
// =================================================================

always @(posedge clk or posedge rst) begin
    if (rst)
        vo <= {`VB{1'b0}};
    else
        vo <= (en && de) ? `VSET_RGB(vi, rgb_new) : vi;
end

endmodule
