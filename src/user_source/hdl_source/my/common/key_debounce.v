// =====================================================================
// 按键/拨码消抖：同步 + 稳定 MS 毫秒才更新
//   level  : 消抖后的电平（按键按下为 0，拨码拨上为 1，均为原始极性）
//   press  : 按键按下（1→0）单拍脉冲
//   rls    : 按键松开（0→1）单拍脉冲
// =====================================================================
module key_debounce #(
    parameter integer CLK_HZ = 25_000_000,
    parameter integer MS     = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire key_in,
    output reg  level,
    output reg  press,
    output reg  rls
);

localparam integer CNT_MAX = CLK_HZ / 1000 * MS;

reg [1:0]  sync;
reg [23:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sync    <= 2'b11;
        cnt     <= 24'd0;
        level   <= 1'b1;
        press   <= 1'b0;
        rls <= 1'b0;
    end else begin
        sync    <= {sync[0], key_in};
        press   <= 1'b0;
        rls <= 1'b0;
        if (sync[1] == level)
            cnt <= 24'd0;
        else if (cnt == CNT_MAX - 1) begin
            cnt     <= 24'd0;
            level   <= sync[1];
            press   <=  level & ~sync[1];
            rls <= ~level &  sync[1];
        end else
            cnt <= cnt + 24'd1;
    end
end

endmodule
