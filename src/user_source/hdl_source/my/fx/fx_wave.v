// =====================================================================
// 音频可视化：画面下方叠加 示波器波形 + 音量柱（带峰值保持）
//   每帧采集 640 个音频样本（48kHz 下约 13ms）写入乒乓缓冲，下一帧显示，无撕裂
//   波形区：y = WAVE_Y0 ~ WAVE_Y0+79（中线 WAVE_Y0+40），半透明暗底
//   音量柱：波形区右侧 16 像素宽，绿色，峰值线为红色
// =====================================================================
`include "vid_defs.vh"

module fx_wave #(
    parameter [9:0] WAVE_Y0 = 10'd352,
    parameter [9:0] WAVE_XE = 10'd600,         // 波形右边界
    parameter [9:0] BAR_X0  = 10'd612          // 音量柱左边（宽 16）
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               en,
    input  wire               pcm_valid,
    input  wire signed [23:0] pcm,
    input  wire [`VB-1:0]     vi,
    output reg  [`VB-1:0]     vo
);

wire [9:0]  x  = `X(vi);
wire [9:0]  y  = `Y(vi);
wire        de = `DE(vi);
wire [23:0] rgb = `RGB(vi);

reg vs_d;
always @(posedge clk) vs_d <= `VS(vi);
wire frame_start = vs_d & ~`VS(vi);

// ---------------- 采样写入（乒乓） ----------------
reg [6:0] wbuf [0:2047];           // 两块（地址最高位 = 块号），每块用前 640 个，存 0~79 的纵向位置
reg       wsel;                    // 当前写哪块
reg [9:0] widx;
reg [23:0] peak, level, hold;
reg [5:0]  hold_t;
wire [23:0] mag = pcm[23] ? -pcm : pcm;
// 振幅 → 0~79：取 pcm[22:16]（±128 级）缩到 ±39，再加中线 40
wire signed [7:0] s8  = pcm[23:16];
wire signed [8:0] pos_s = 9'sd40 - (s8 >>> 2) - (s8 >>> 4); // ≈ 40 - s8*0.31（全部有符号运算）
wire [6:0]        pos   = pos_s[8] ? 7'd0 : (pos_s > 9'sd79 ? 7'd79 : pos_s[6:0]);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wsel <= 1'b0; widx <= 10'd0; peak <= 0; level <= 0; hold <= 0; hold_t <= 0;
    end else begin
        if (pcm_valid && widx < 10'd640) begin
            wbuf[{wsel, widx}] <= pos;              // 写当前块
            widx <= widx + 10'd1;
            if (mag > peak) peak <= mag;
        end
        if (frame_start) begin
            wsel  <= ~wsel; widx <= 10'd0;
            level <= peak;  peak <= 0;
            if (peak >= hold || hold_t == 6'd0) begin hold <= peak; hold_t <= 6'd40; end
            else hold_t <= hold_t - 6'd1;
        end
    end
end

// ---------------- 显示 ----------------
reg  [6:0] wpos, wprev;
always @(posedge clk) begin
    wpos  <= wbuf[{~wsel, x}];        // 读另一块（上一帧采集的）
    wprev <= wpos;                    // 前一列的位置，用于连线
end

reg [`VB-1:0] v1;
always @(posedge clk) v1 <= vi;

// ===================== 用户代码区 =====================
wire [9:0] x1 = `X(v1), y1 = `Y(v1);
wire       band1 = (y1 >= WAVE_Y0) && (y1 < WAVE_Y0 + 10'd80);
wire [6:0] yy1 = y1 - WAVE_Y0;
wire [23:0] rgb1 = `RGB(v1);
wire [23:0] dark = {2'b0, rgb1[23:18], 2'b0, rgb1[15:10], 2'b0, rgb1[7:2]};   // 压暗 75%
// 音量柱：x 612~627，高度 = level[23:17]（满幅约 64 像素）
wire [6:0] lv_h = (level[23:17] > 7'd79) ? 7'd79 : level[23:17];
wire [6:0] hd_h = (hold[23:17]  > 7'd79) ? 7'd79 : hold[23:17];
wire in_bar  = (x1 >= BAR_X0) && (x1 < BAR_X0 + 10'd16);
wire bar_on  = in_bar && (7'd79 - yy1) < lv_h;
wire hold_on = in_bar && (7'd79 - yy1) == hd_h;
wire [6:0] lo = (wpos < wprev) ? wpos : wprev;
wire [6:0] hi = (wpos < wprev) ? wprev : wpos;
wire wave_on = (x1 < WAVE_XE) && (x1 != 10'd0) && (yy1 + 7'd1 >= lo) && (yy1 <= hi);   // 相邻两点竖直连线
wire [23:0] rgb_new = !band1 ? rgb1 :
                      hold_on ? 24'hFF3030 :
                      bar_on  ? 24'h30E060 :
                      wave_on ? 24'h40E0FF : dark;
// =====================================================

always @(posedge clk or posedge rst) begin
    if (rst) vo <= {`VB{1'b0}};
    else     vo <= (en && `DE(v1)) ? `VSET_RGB(v1, rgb_new) : v1;
end

endmodule
