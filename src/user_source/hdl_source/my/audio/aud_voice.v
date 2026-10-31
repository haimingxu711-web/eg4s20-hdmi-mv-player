// =====================================================================
// 一个声部：乐谱表（块 RAM）+ 事件推进 + DDS 音色 + 包络
//   乐谱每个事件 W 位，公共字段：[W-1:W-7] 音高（MIDI 号，0 = 休止） [W-8:W-27] 时长（采样数）
//                                [END_BIT] 最后一个事件（播完回到开头） [1] tie 连音不重新起音 [0] hold 结尾不释放
//   其余位（歌词、切图）原样从 ev 输出，由上层使用
//   音色：基波 3/4 + 二次谐波 1/4（比纯正弦饱满）
//   包络：起音 5ms 线性 → 约 0.17s 衰减到 45% 保持 → 音符结束前 20ms 释放（避免爆音）
// 输出 smp = 波形 × 包络（34 位有符号），smp_valid 在 sample_tick 后第 4 拍
// =====================================================================
module aud_voice #(
    parameter integer W       = 72,
    parameter integer AW      = 10,
    parameter integer DEPTH   = 1024,
    parameter integer END_BIT = 18,
    parameter         MIF     = "none.mif",
    parameter         HEX     = "none.hex",
    parameter         IMPL    = "AUTO",
    parameter [15:0]  ATK     = 16'd273,       // 起音：每采样 +273，240 采样到顶
    parameter [15:0]  SUS     = 16'd29491,     // 保持电平 45%
    parameter [19:0]  REL     = 20'd960        // 结束前 960 采样（20ms）开始释放
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                sample_tick,
    input  wire                restart,        // 回到乐谱开头
    output reg  [W-1:0]        ev,             // 当前事件
    output reg                 ev_load,        // 新事件开始（单拍）
    output wire [15:0]         env_lv,         // 当前包络（给演唱小人做嘴型）
    output reg                 smp_valid,
    output reg  signed [33:0]  smp
);

// ---------------- 乐谱推进 ----------------
reg  [AW-1:0] addr;
wire [W-1:0]  q;
rom_sp #(.W(W), .AW(AW), .DEPTH(DEPTH), .MIF(MIF), .HEX(HEX), .IMPL(IMPL)) u_rom(.clk(clk), .addr(addr), .q(q));

reg  [19:0] remain;                            // 本事件还剩多少个采样
wire [6:0]  pitch = ev[W-1:W-7];
wire        tie   = ev[1];
wire        hold  = ev[0];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        addr <= {AW{1'b0}}; remain <= 20'd0; ev <= {W{1'b0}}; ev_load <= 1'b0;
    end else begin
        ev_load <= 1'b0;
        if (restart) begin
            addr <= {AW{1'b0}}; remain <= 20'd0; ev <= {W{1'b0}};
        end else if (sample_tick) begin
            if (remain == 20'd0) begin             // 装入下一个事件（q 早已稳定）
                ev      <= q;
                ev_load <= 1'b1;
                remain  <= q[W-8:W-27] - 20'd1;
                addr    <= q[END_BIT] ? {AW{1'b0}} : addr + 1'b1;
            end else
                remain <= remain - 20'd1;
        end
    end
end

// ---------------- 包络 ----------------
reg [15:0] env;
assign env_lv = env;
reg        atk;
reg [5:0]  div;
wire       rel = (pitch == 7'd0) || (!hold && remain < REL);
always @(posedge clk or posedge rst) begin
    if (rst) begin
        env <= 16'd0; atk <= 1'b0; div <= 6'd0;
    end else if (ev_load) begin
        if (!tie) atk <= (pitch != 7'd0);          // 新音符：从当前电平开始起音
        div <= 6'd0;
    end else if (sample_tick) begin
        if (rel)
            env <= (env < 16'd128) ? 16'd0 : env - (env >> 7);       // 时间常数 128 采样
        else if (atk) begin
            if (env >= 16'hFFFF - ATK) begin env <= 16'hFFFF; atk <= 1'b0; end
            else env <= env + ATK;
        end else begin
            div <= div + 6'd1;
            if (div == 6'd63 && env > SUS) env <= env - ((env - SUS) >> 7);   // 时间常数约 8192 采样
        end
    end
end

// ---------------- DDS ----------------
wire [31:0] inc;
aud_pitch_inc u_inc(.pitch(pitch), .inc(inc));
reg  [31:0] phase;
always @(posedge clk or posedge rst) begin
    if (rst)              phase <= 32'd0;
    else if (sample_tick) phase <= phase + inc;
end
wire [31:0] phase2 = {phase[30:0], 1'b0};      // 二次谐波
wire [7:0]  ia = phase[30]  ? ~phase[29:22]  : phase[29:22];
wire [7:0]  ib = phase2[30] ? ~phase2[29:22] : phase2[29:22];
wire [14:0] qa, qb;
sine_q_rom u_sa(.clk(clk), .addr(ia), .data(qa));
sine_q_rom u_sb(.clk(clk), .addr(ib), .data(qb));
reg na, nb;                                    // 与 ROM 输出对齐的符号
always @(posedge clk) begin na <= phase[31]; nb <= phase2[31]; end

// 流水：tick → t1 地址 → t2 ROM 出数、合成 → t3 乘包络 → smp_valid
reg t1, t2, t3;
reg signed [16:0] s;
wire signed [16:0] sa = na ? -$signed({2'b00, qa}) : $signed({2'b00, qa});
wire signed [16:0] sb = nb ? -$signed({2'b00, qb}) : $signed({2'b00, qb});
wire signed [33:0] prod = s * $signed({1'b0, env});           // 17 x 17 位，34 位接住
always @(posedge clk or posedge rst) begin
    if (rst) begin
        t1 <= 0; t2 <= 0; t3 <= 0; s <= 17'sd0; smp <= 34'sd0; smp_valid <= 1'b0;
    end else begin
        t1 <= sample_tick; t2 <= t1; t3 <= t2;
        if (t2) s <= sa - (sa >>> 2) + (sb >>> 2);              // 3/4 基波 + 1/4 二次谐波，不超过 ±32767
        smp_valid <= t3;
        if (t3) smp <= prod;
    end
end

endmodule
