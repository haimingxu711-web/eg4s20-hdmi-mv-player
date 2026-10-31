// =====================================================================
// 音频时基：由像素时钟精确分频出 48kHz 采样节拍，并生成 HDMI ACR 参数
//   25MHz / 48kHz = 3125/6，用累加器每拍 +6、满 3125 回绕，长期平均严格 48kHz
//   ACR：N = 6144，每 N/128 = 48 个采样发一次；48 个采样恰好 25000 个像素时钟，
//        因此 CTS 恒为 25000（音频与视频同源，无需测量）
// =====================================================================
module aud_timebase #(
    parameter integer CLK_HZ  = 25_000_000,
    parameter integer FS_HZ   = 48_000,
    parameter integer ACR_N   = 6144
)(
    input  wire        clk,
    input  wire        rst,
    output reg         sample_tick,     // 48kHz 单拍脉冲
    output reg         acr_valid,
    output reg  [19:0] acr_cts,
    output reg  [19:0] acr_n
);

// CLK_HZ/FS_HZ 化为最简分数 DEN/NUM（25e6/48e3 = 3125/6）
localparam integer G   = 8000;                   // gcd(25000000, 48000)
localparam integer DEN = CLK_HZ / G;             // 3125
localparam integer NUM = FS_HZ  / G;             // 6
localparam integer SAMPLES_PER_ACR = ACR_N / 128;                          // 48
localparam integer CTS = CLK_HZ / FS_HZ * SAMPLES_PER_ACR
                       + (CLK_HZ % FS_HZ) * SAMPLES_PER_ACR / FS_HZ;       // 25000

reg [12:0] acc;
reg [5:0]  smp_cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        acc         <= 13'd0;
        sample_tick <= 1'b0;
    end else if (acc + NUM >= DEN) begin
        acc         <= acc + NUM - DEN;
        sample_tick <= 1'b1;
    end else begin
        acc         <= acc + NUM;
        sample_tick <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        smp_cnt   <= 6'd0;
        acr_valid <= 1'b0;
        acr_cts   <= 20'd0;
        acr_n     <= 20'd0;
    end else begin
        acr_valid <= 1'b0;
        if (sample_tick) begin
            if (smp_cnt == SAMPLES_PER_ACR - 1) begin
                smp_cnt   <= 6'd0;
                acr_valid <= 1'b1;
                acr_cts   <= CTS;
                acr_n     <= ACR_N;
            end else
                smp_cnt <= smp_cnt + 6'd1;
        end
    end
end

endmodule
