// =====================================================================
// 主题音乐（音频源）：主旋律声部 + 歌词进度 + MV 切图节点
//   乐谱/歌词由 theme/gen_theme.py 从 MIDI + 歌词生成，换歌不用改这里
//   主旋律事件 72 位：
//     [71:65] 音高  [64:45] 时长(采样)  [44:34] S 已开始的字数  [33:26] 当前句号
//     [25] 新字开始  [24] 切图  [23:21] 目标图号  [20:19] 转场样式  [18] 末事件
//     [17:2] 当前字每变色 1 像素的采样数  [1] tie  [0] hold
//   输出给歌词层：line / chr_s / wipe（当前字已变色的像素数 0~24）
//   输出给播放器：img_sw 单拍脉冲 + img + style
// 【音频源统一接口】pcm_valid / pcm_l / pcm_r，与 aud_synth 相同
// 加伴奏：再实例化 aud_voice（36 位乐谱：音高/时长/[8]末事件/[1]tie/[0]hold），在下面混音处相加
// =====================================================================
`include "theme_cfg.vh"

module aud_music(
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire               restart,         // 从头播放（进入 MV 模式时）
    input  wire [3:0]         volume,
    input  wire               mute,
    output reg                pcm_valid,
    output reg  signed [23:0] pcm_l,
    output reg  signed [23:0] pcm_r,
    // 歌词进度
    output reg  [7:0]         line,
    output reg  [10:0]        chr_s,
    output reg  [4:0]         wipe,
    // MV 切图
    output reg                img_sw,
    output reg  [2:0]         img,
    output reg  [1:0]         style,
    // 演唱小人
    output wire [15:0]        mel_env,         // 主旋律包络
    output reg                note_on          // 新音符起头（非休止、非连音），单拍
);

wire [71:0]        ev_m;
wire               ld_m, v_m;
wire signed [33:0] s_m;
aud_voice #(.W(72), .AW(10), .DEPTH(1024), .END_BIT(18),
            .MIF(`TH_SCORE_MEL_MIF), .HEX(`TH_SCORE_MEL_HEX), .IMPL("32K")) u_mel(
    .clk(clk), .rst(rst), .sample_tick(sample_tick), .restart(restart),
    .ev(ev_m), .ev_load(ld_m), .env_lv(mel_env), .smp_valid(v_m), .smp(s_m)
);

// ---------------- 歌词进度 ----------------
reg [15:0] spp, wcnt;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        line <= 8'd0; chr_s <= 11'd0; wipe <= 5'd0; spp <= 16'd1; wcnt <= 16'd0;
        img_sw <= 1'b0; img <= 3'd0; style <= 2'd0; note_on <= 1'b0;
    end else begin
        img_sw <= 1'b0;
        note_on <= ld_m && (ev_m[71:65] != 7'd0) && !ev_m[1];
        if (ld_m) begin
            line  <= ev_m[33:26];
            chr_s <= ev_m[44:34];
            if (ev_m[25]) begin wipe <= 5'd0; wcnt <= 16'd0; spp <= ev_m[17:2]; end
            if (ev_m[24]) begin img_sw <= 1'b1; img <= ev_m[23:21]; style <= ev_m[20:19]; end
        end else if (sample_tick && wipe < 5'd24) begin
            if (wcnt + 16'd1 >= spp) begin wcnt <= 16'd0; wipe <= wipe + 5'd1; end
            else wcnt <= wcnt + 16'd1;
        end
    end
end

// ---------------- 混音 + 音量 ----------------
// 乘积 40 位接住（34 位 x 5 位），取 [35:12]，满音量约 0.93 满幅
wire signed [39:0] s_mix = s_m * $signed({1'b0, (mute ? 4'd0 : volume)});
always @(posedge clk or posedge rst) begin
    if (rst) begin
        pcm_valid <= 1'b0; pcm_l <= 24'sd0; pcm_r <= 24'sd0;
    end else begin
        pcm_valid <= v_m;
        if (v_m) begin
            pcm_l <= s_mix[35:12];
            pcm_r <= s_mix[35:12];
        end
    end
end

endmodule
