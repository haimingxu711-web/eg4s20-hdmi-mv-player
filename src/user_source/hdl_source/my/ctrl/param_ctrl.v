// =====================================================================
// 参数菜单（按键配置）
//   普通模式（SW4 拨下）：KEY2 下一张，KEY3 切换轮播周期，KEY4 开/关自动轮播
//   设置模式（SW4 拨上）：KEY3 选择参数项，KEY2 加，KEY4 减
//     参数项：0 亮度(-8~+7)  1 对比度(0~15)  2 音量(0~15)  3 轮播周期(2/3/5/8s)
// 输出的 k_next/k_auto/k_period 只在普通模式下有效，直接接 player
// 新增参数：在 NUM_ITEMS 加一、增加一个寄存器和一行 case 即可
// =====================================================================
module param_ctrl(
    input  wire              clk,
    input  wire              rst,
    input  wire              frame_start,
    input  wire              set_mode,       // SW4
    input  wire              key_a,          // KEY2 按下脉冲
    input  wire              key_b,          // KEY3
    input  wire              key_c,          // KEY4
    // 普通模式下转发给播放器
    output wire              k_next,
    output wire              k_period,
    output wire              k_auto,
    // 参数
    output reg  [1:0]        item,           // 当前选中项
    output reg  signed [3:0] brightness,
    output reg  [3:0]        contrast,
    output reg  [3:0]        volume,
    output reg  [1:0]        period_sel,
    output reg  [5:0]        show_cnt         // >0 时显示 OSD（按键后保持约 3 秒，单位 64 帧）
);

assign k_next   = !set_mode & key_a;
assign k_period = 1'b0;                      // 周期统一在本模块管理
assign k_auto   = !set_mode & key_c;

wire inc = set_mode & key_a;
wire dec = set_mode & key_c;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        item <= 2'd0; brightness <= 4'sd0; contrast <= 4'd8; volume <= 4'd6; period_sel <= 2'd1;
    end else begin
        if (!set_mode && key_b) period_sel <= period_sel + 2'd1;
        if (set_mode && key_b)  item <= item + 2'd1;
        if (inc) case (item)
            2'd0: if (brightness != 4'sd7) brightness <= brightness + 4'sd1;
            2'd1: if (contrast   != 4'd15) contrast   <= contrast + 4'd1;
            2'd2: if (volume     != 4'd15) volume     <= volume + 4'd1;
            2'd3: period_sel <= period_sel + 2'd1;
        endcase
        if (dec) case (item)
            2'd0: if (brightness != -4'sd8) brightness <= brightness - 4'sd1;
            2'd1: if (contrast   != 4'd0)   contrast   <= contrast - 4'd1;
            2'd2: if (volume     != 4'd0)   volume     <= volume - 4'd1;
            2'd3: period_sel <= period_sel - 2'd1;
        endcase
    end
end

// OSD 显示计时：任意按键后显示约 3 秒（show_cnt 每 64 帧减 1）
reg [5:0] fcnt;
always @(posedge clk or posedge rst) begin
    if (rst) begin show_cnt <= 6'd3; fcnt <= 6'd0; end
    else if (key_a | key_b | key_c) begin show_cnt <= 6'd3; fcnt <= 6'd0; end
    else if (frame_start) begin
        fcnt <= fcnt + 6'd1;
        if (fcnt == 6'd63 && show_cnt != 6'd0) show_cnt <= show_cnt - 6'd1;
    end
end

endmodule