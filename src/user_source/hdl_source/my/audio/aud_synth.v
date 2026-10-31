// =====================================================================
// 旋律合成器（音频源）：DDS 正弦 + 指数衰减包络（拨弦/钢琴感）
//   song   : 选择曲目（与当前图片联动，切图即换曲，从头播放）
//   volume : 0~15 音量；mute=1 静音
// 输出 48kHz、24 位有符号 PCM（左右声道相同），pcm_valid 每个采样一拍
//
// 【音频源统一接口】任何音频源只要输出 pcm_valid / pcm_l / pcm_r 即可接到 HDMI，
//  换声音 = 换一个音频源模块。
// =====================================================================
module aud_synth #(
    parameter integer STEP_SAMPLES = 7200      // 一个八分音符 = 0.15s
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,     // 来自 aud_timebase
    input  wire [1:0]         song,
    input  wire [3:0]         volume,
    input  wire               mute,
    output reg                pcm_valid,
    output reg  signed [23:0] pcm_l,
    output reg  signed [23:0] pcm_r
);

// ---------------- 乐谱推进 ----------------
reg  [4:0]  step;
reg  [15:0] smp_in_step;
reg  [1:0]  song_d;
wire [4:0]  rom_note;
wire [2:0]  rom_len;
reg  [4:0]  cur_note;
wire [31:0] phase_inc;
reg         note_on;                           // 新音符开始，包络复位

aud_song_rom u_rom(
    .song(song), .step(step), .note(rom_note), .len(rom_len),
    .note_q(cur_note), .phase_inc(phase_inc)
);

wire [18:0] step_len_smp = rom_len * STEP_SAMPLES;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        step        <= 5'd0;
        smp_in_step <= 16'd0;
        song_d      <= 2'd0;
        cur_note    <= 5'd0;
        note_on     <= 1'b0;
    end else begin
        note_on <= 1'b0;
        song_d  <= song;
        if (song != song_d) begin                    // 换曲：从头开始
            step        <= 5'd0;
            smp_in_step <= 16'd0;
            note_on     <= 1'b1;
        end else if (sample_tick) begin
            if (rom_len == 3'd0) begin               // 曲终，回到开头
                step        <= 5'd0;
                smp_in_step <= 16'd0;
            end else if (smp_in_step == 16'd0) begin // 音符开始
                cur_note    <= rom_note;
                note_on     <= 1'b1;
                smp_in_step <= 16'd1;
            end else if (smp_in_step >= step_len_smp - 1) begin
                step        <= step + 5'd1;
                smp_in_step <= 16'd0;
            end else
                smp_in_step <= smp_in_step + 16'd1;
        end
    end
end

// ---------------- 包络：每 64 个采样乘以 255/256（约 0.34s 衰减到 37%） ----------------
reg [15:0] env;          // 0..65535
reg [5:0]  env_div;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        env     <= 16'd0;
        env_div <= 6'd0;
    end else if (note_on) begin
        env     <= (cur_note == 5'd0) ? 16'd0 : 16'hFFFF;     // 休止符不发声
        env_div <= 6'd0;
    end else if (sample_tick) begin
        env_div <= env_div + 6'd1;
        if (env_div == 6'd63)
            env <= env - (env >> 8);                   // 时间常数 64*256 样本 ≈ 0.34s
    end
end

// ---------------- DDS 相位累加 ----------------
reg [31:0] phase;
always @(posedge clk or posedge rst) begin
    if (rst)               phase <= 32'd0;
    else if (sample_tick)  phase <= phase + phase_inc;
end

// ---------------- 正弦查表（1/4 周期表 + 对称展开） ----------------
wire [1:0]  quad = phase[31:30];
wire [7:0]  qidx = quad[0] ? ~phase[29:22] : phase[29:22];
wire [14:0] qval;
sine_q_rom u_sine(.clk(clk), .addr(qidx), .data(qval));

// 流水：tick → (ROM 1 拍) → 乘包络 → 乘音量 → 输出
// 注意：乘积位宽要显式给足（s_env 最大约 2^31，再乘 15 约 2^35），否则会截断溢出
reg        t1, t2, t3;
reg        neg1, neg2;
reg signed [16:0] s_sine;          // ±32767
reg signed [33:0] s_env;           // s_sine * env
wire signed [39:0] s_mix = s_env * $signed({1'b0, (mute ? 4'd0 : volume)});   // 40 位接住，取 [35:12]

always @(posedge clk or posedge rst) begin
    if (rst) begin
        t1 <= 0; t2 <= 0; t3 <= 0; neg1 <= 0; neg2 <= 0;
        s_sine <= 0; s_env <= 0;
        pcm_valid <= 1'b0; pcm_l <= 24'sd0; pcm_r <= 24'sd0;
    end else begin
        t1   <= sample_tick;
        neg1 <= quad[1];
        t2   <= t1;
        neg2 <= neg1;
        if (t1) s_sine <= neg1 ? -$signed({2'b00, qval}) : $signed({2'b00, qval});
        t3   <= t2;
        if (t2) s_env  <= s_sine * $signed({1'b0, env});
        pcm_valid <= t3;
        if (t3) begin
            pcm_l <= s_mix[35:12];
            pcm_r <= s_mix[35:12];
        end
    end
end

endmodule
