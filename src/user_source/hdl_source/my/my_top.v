// =====================================================================
// 顶层：HDMI 多媒体播放系统（自有架构）
//
//  TF 卡 ─ sd_card ─ img_loader(FAT32+BMP) ─┐ (sd_clk = 板载 50MHz)
//                                            ▼
//                                    mem_ctrl ─ SDRAM IP   (mem_clk 100MHz，原 125MHz 读数据采样余量不足会出零星噪点)
//                                     │A路  │B路
//  vid_timing ─ vid_frame_src ─ fx_fade ─ fx_bc ─ fx_nosig ─ fx_wave ─ fx_lyric ─ osd_layer ─ vid_to_axis ─ HDMI IP
//  param_ctrl（按键菜单）  player（切图/轮播/MV/转场）  aud_timebase + aud_music（主题曲 + 歌词进度 + 切图节点）
//
// 普通模式(SW4 下)：KEY1 复位  KEY2 下一张  KEY3 轮播周期(2/3/5/8s)  KEY4 模式：手动 → 定时轮播 → MV（图片跟音乐切）
// 设置模式(SW4 上)：KEY3 选参数(亮度/对比度/音量/周期)  KEY2 加  KEY4 减（OSD 显示）
// 拨码：SW1 声音  SW2 转场特效  SW3 信息层（卡拉OK 歌词 + 音频波形/音量柱）  SW4 设置模式  SW6 数码管
// 数码管（左→右）：周期秒数 | 模式(- 手动 / A 轮播 / P MV) | 当前图号 | 图片总数 | SD 状态 | 装载状态
// 厂商 IP：sys_pll、video_pll、sdram、HDMI 1.4b Transmitter、HDMI PHY
// =====================================================================
`include "vid_defs.vh"
`include "theme_cfg.vh"

module my_top(
    input wire clk,              // 50MHz
    input wire rst_n,            // KEY1
    input wire key1,             // KEY2：下一张
    input wire key3,             // KEY3：轮播周期
    input wire key2,             // KEY4：自动轮播
    input wire sw_audio_on,      // SW1
    input wire sw2,              // SW2
    input wire sw3,              // SW3
    input wire sw4,              // SW4

    output wire [5:0]  seg_sel,
    output wire [7:0]  seg_data,

    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P,
    output wire HDMI_DDC_SCL,
    inout wire HDMI_DDC_SDA,

    output wire sd_ncs,
    output wire sd_dclk,
    output wire sd_mosi,
    input wire sd_miso
);

// =========================== 时钟 ===========================
wire video_clk, hdmi_5x_clk, sd_clk, mem_clk, mem_clk_sft;
video_pll u_video_pll(.refclk(clk), .clk0_out(video_clk), .clk1_out(hdmi_5x_clk), .reset(1'b0));
sys_pll   u_sys_pll  (.refclk(clk), .clk0_out(), .clk1_out(mem_clk), .clk2_out(mem_clk_sft), .reset(1'b0));
// SD 卡 / 装载器直接用板载 50MHz（SPI 最高 25MHz，用不到 100MHz，时序更宽松）
assign sd_clk = clk;

// =========================== 复位 ===========================
// 50MHz 下上电/按键后保持约 20ms，再同步到各时钟域
reg [19:0] por_cnt;
reg        por;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin por_cnt <= 20'd0; por <= 1'b1; end
    else if (por_cnt != 20'hFFFFF) begin por_cnt <= por_cnt + 20'd1; por <= 1'b1; end
    else por <= 1'b0;
end
reg [1:0] rv, rs, rm;
always @(posedge video_clk or posedge por) if (por) rv <= 2'b11; else rv <= {rv[0], 1'b0};
always @(posedge sd_clk    or posedge por) if (por) rs <= 2'b11; else rs <= {rs[0], 1'b0};
always @(posedge mem_clk   or posedge por) if (por) rm <= 2'b11; else rm <= {rm[0], 1'b0};
wire rst = rv[1], rst_sd = rs[1], rst_mem = rm[1];

// =========================== 按键 / 拨码 ===========================
wire key_a, key_b, key_c, sw_snd, sw_fade, sw_sub, sw_set;
key_debounce u_k2(.clk(video_clk), .rst(rst), .key_in(key1),        .level(),        .press(key_a),    .rls());
key_debounce u_k3(.clk(video_clk), .rst(rst), .key_in(key3),        .level(),        .press(key_b),    .rls());
key_debounce u_k4(.clk(video_clk), .rst(rst), .key_in(key2),        .level(),        .press(key_c),    .rls());
key_debounce u_s1(.clk(video_clk), .rst(rst), .key_in(sw_audio_on), .level(sw_snd),  .press(), .rls());
key_debounce u_s2(.clk(video_clk), .rst(rst), .key_in(sw2),         .level(sw_fade), .press(), .rls());
key_debounce u_s3(.clk(video_clk), .rst(rst), .key_in(sw3),         .level(sw_sub),  .press(), .rls());
key_debounce u_s4(.clk(video_clk), .rst(rst), .key_in(sw4),         .level(sw_set),  .press(), .rls());

// =========================== TF 卡 → 图片装载 ===========================
wire        sd_ready, sd_idle, sd_init_err;
wire [3:0]  sd_dbg, ld_dbg;
wire        rd_req, rd_bv, rd_done, rd_err;
wire [31:0] rd_lba;
wire [7:0]  rd_byte;
sd_card #(.SLOW_DIV(8'd63), .FAST_DIV(8'd1)) u_sd(   // 50MHz：初始化 397kHz，读数据 25MHz
    .clk(sd_clk), .rst(rst_sd), .ready(sd_ready), .idle(sd_idle), .init_err(sd_init_err), .dbg_state(sd_dbg),
    .rd_req(rd_req), .rd_lba(rd_lba), .rd_byte(rd_byte), .rd_byte_valid(rd_bv), .rd_done(rd_done), .rd_err(rd_err),
    .sd_cs(sd_ncs), .sd_sclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
);

wire        px_valid, px_ready;
wire [20:0] px_addr;
wire [31:0] px_data;
wire [2:0]  img_count;
wire [3:0]  img_ok;
wire        ld_done, fs_err;
img_loader u_ld(
    .clk(sd_clk), .rst(rst_sd), .start(1'b1), .sd_ready(sd_ready), .sd_idle(sd_idle),
    .rd_req(rd_req), .rd_lba(rd_lba), .rd_byte(rd_byte), .rd_byte_valid(rd_bv), .rd_done(rd_done), .rd_err(rd_err),
    .px_ready(px_ready), .px_valid(px_valid), .px_addr(px_addr), .px_data(px_data),
    .img_count(img_count), .img_ok(img_ok), .done(ld_done), .fs_err(fs_err), .dbg_state(ld_dbg)
);

// 装载状态同步到视频域（done 之后 img_count/img_ok 保持不变）
reg [1:0] done_s, ready_s, fserr_s;
always @(posedge video_clk) begin
    done_s  <= {done_s[0],  ld_done};
    ready_s <= {ready_s[0], sd_ready};
    fserr_s <= {fserr_s[0], fs_err};
end
wire       loaded   = done_s[1] && !fserr_s[1] && (img_count != 3'd0);
wire [1:0] ld_status = !ready_s[1] ? 2'd0 : !done_s[1] ? 2'd1 : fserr_s[1] ? 2'd2 : 2'd3;

// =========================== SDRAM ===========================
wire        sdr_init_done, sdr_init_ref_vld, sdr_busy;
wire        app_wr_en, app_rd_en, sdr_rd_en, app_ref_req;
wire [20:0] app_wr_addr, app_rd_addr;
wire [31:0] app_wr_din, sdr_rd_dout;
sdram u_sdram(
    .Clk(mem_clk), .Clk_sft(mem_clk_sft), .Rst(rst_mem),
    .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_init_ref_vld), .Sdr_busy(sdr_busy),
    .App_ref_req(app_ref_req),
    .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr), .App_wr_dm(4'b0000), .App_wr_din(app_wr_din),
    .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr), .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_dout)
);

wire        a_tgl, b_tgl, a_rd, b_rd;
wire [1:0]  a_slot_m, b_slot_m;
wire [23:0] a_rgb, b_rgb;
wire [7:0]  dbg_ref;                      // 调试：SDRAM 刷新频率（数码管右两位，装载完成后显示）
mem_ctrl u_mem(
    .mem_clk(mem_clk), .rst(rst_mem), .sdr_init_done(sdr_init_done), .sdr_busy(sdr_busy), .sdr_ref(sdr_init_ref_vld),
    .dbg_ref_rate(dbg_ref), .app_ref_req(app_ref_req),
    .app_wr_en(app_wr_en), .app_wr_addr(app_wr_addr), .app_wr_din(app_wr_din),
    .app_rd_en(app_rd_en), .app_rd_addr(app_rd_addr), .sdr_rd_en(sdr_rd_en), .sdr_rd_dout(sdr_rd_dout),
    .wr_clk(sd_clk), .px_valid(px_valid), .px_addr(px_addr), .px_data(px_data), .px_ready(px_ready),
    .vid_clk(video_clk),
    .a_req_tgl(a_tgl), .a_slot(a_slot_m), .a_rd(a_rd), .a_rgb(a_rgb),
    .b_req_tgl(b_tgl), .b_slot(b_slot_m), .b_rd(b_rd), .b_rgb(b_rgb)
);

// =========================== 参数菜单 + 播放控制 ===========================
wire              frame_start;
wire              k_next, k_period, k_auto;
wire [1:0]        item, period_sel;
wire signed [3:0] brightness;
wire [3:0]        contrast, volume;
wire [5:0]        show_cnt;
param_ctrl u_param(
    .clk(video_clk), .rst(rst), .frame_start(frame_start), .set_mode(sw_set),
    .key_a(key_a), .key_b(key_b), .key_c(key_c),
    .k_next(k_next), .k_period(k_period), .k_auto(k_auto),
    .item(item), .brightness(brightness), .contrast(contrast), .volume(volume),
    .period_sel(period_sel), .show_cnt(show_cnt)
);

wire [1:0] slot_a, slot_b, cur, mode;
wire [7:0] alpha;
wire       fading, music_restart;
wire [2:0] trans_style;
wire [3:0] period_sec;
wire       mv_sw;                         // 切图节点，来自下方 aud_music
wire [2:0] mv_img;
wire [1:0] mv_style;
player u_player(
    .clk(video_clk), .rst(rst), .frame_start(frame_start), .ready(loaded), .img_count(img_count),
    .k_next(k_next), .k_auto(k_auto), .fade_en(sw_fade),
    .mv_sw(mv_sw), .mv_img(mv_img), .mv_style(mv_style),
    .slot_a(slot_a), .slot_b(slot_b), .alpha(alpha), .fading(fading), .style(trans_style),
    .mode(mode), .music_restart(music_restart),
    .period_sel(period_sel), .period_sec(period_sec), .cur(cur)
);

// OSD 内容
wire        osd_we;
wire [11:0] osd_wa;
wire [6:0]  osd_wc;
osd_writer u_osdw(
    .clk(video_clk), .rst(rst),
    .status_on(sw_set || show_cnt != 6'd0), .sub_on(sw_sub && (`TH_NLINES == 0)),   // 有歌词时滚动字幕让位给歌词
    .set_mode(sw_set), .item(item), .cur(cur), .img_count(img_count), .mode(mode),
    .period_sec(period_sec), .brightness(brightness), .contrast(contrast), .volume(volume),
    .fade_on(sw_fade), .wr_en(osd_we), .wr_addr(osd_wa), .wr_char(osd_wc)
);

// =========================== 视频效果链 ===========================
// 音频样本（由下方音频部分产生，fx_wave 也要用）
wire        pcm_valid;
wire [23:0] pcm_l, pcm_r;
wire [`VB-1:0] v_tim, v_src, v_fade, v_bc, v_nosig, v_wave, v_lyr, v_osd, v_fx;
wire [7:0]     lyr_line;                  // 歌词进度（来自 aud_music）
wire [10:0]    lyr_chr;
wire [4:0]     lyr_wipe;
wire [15:0]    mel_env;                   // 主旋律包络 / 新音符（给演唱小人）
wire           av_note;
wire [`VB-1:0] v_av;
wire [23:0]    rgb_b;
vid_timing    u_tim  (.clk(video_clk), .rst(rst), .vo(v_tim), .frame_start(frame_start));
vid_frame_src u_src  (.clk(video_clk), .rst(rst), .vi(v_tim), .frame_start(frame_start),
                      .slot_a(slot_a), .slot_b(slot_b),
                      .a_req_tgl(a_tgl), .a_slot(a_slot_m), .a_rd(a_rd), .a_rgb(a_rgb),
                      .b_req_tgl(b_tgl), .b_slot(b_slot_m), .b_rd(b_rd), .b_rgb(b_rgb),
                      .vo(v_src), .rgb_b(rgb_b), .cur_slot_a(), .cur_slot_b());
fx_fade       u_fade (.clk(video_clk), .rst(rst), .en(fading), .alpha(alpha), .style(trans_style),
                      .vi(v_src), .rgb_b(rgb_b), .vo(v_fade));
fx_bc         u_bc   (.clk(video_clk), .rst(rst), .en(1'b1), .brightness(brightness), .contrast(contrast),
                      .vi(v_fade), .vo(v_bc));
fx_nosig      u_nosig(.clk(video_clk), .rst(rst), .en(!loaded), .status(ld_status), .vi(v_bc), .vo(v_nosig));
fx_wave #(.WAVE_Y0(10'd316), .WAVE_XE(10'd464), .BAR_X0(10'd472))     // 右侧让给演唱小人
              u_wave (.clk(video_clk), .rst(rst), .en(sw_sub && sw_snd), .pcm_valid(pcm_valid), .pcm(pcm_l),
                      .vi(v_nosig), .vo(v_wave));
fx_avatar     u_av   (.clk(video_clk), .rst(rst), .en(sw_sub && loaded),
                      .sing((`TH_TITLE == 0) || (lyr_line != 8'd0)), .env(mel_env), .note_on(av_note),
                      .vi(v_wave), .vo(v_av));
fx_lyric      u_lyr  (.clk(video_clk), .rst(rst), .en(sw_sub && loaded),
                      .line(lyr_line), .chr_s(lyr_chr), .wipe(lyr_wipe), .vi(v_av), .vo(v_lyr));
osd_layer     u_osd  (.clk(video_clk), .rst(rst), .en(1'b1), .scroll_en(1'b1),
                      .fg_color(24'hFFFFFF), .sub_color(24'hFFD700),
                      .wr_en(osd_we), .wr_addr(osd_wa), .wr_char(osd_wc), .vi(v_lyr), .vo(v_osd));
fx_template   u_fx   (.clk(video_clk), .rst(rst), .en(1'b0), .vi(v_osd), .vo(v_fx));
// ↑ 新效果：复制 fx_template.v 改一行，en 接一个开关，在这里接一行实例化

wire        axis_user, axis_valid, axis_last;
wire [23:0] axis_data;
vid_to_axis u_axis(.clk(video_clk), .rst(rst), .vi(v_fx),
    .axis_user(axis_user), .axis_valid(axis_valid), .axis_last(axis_last), .axis_data(axis_data));

// =========================== 音频 ===========================
wire        sample_tick, acr_valid;          // pcm_valid / pcm_l / pcm_r 已在效果链之前声明
wire [19:0] acr_cts, acr_n;
aud_timebase u_atb(.clk(video_clk), .rst(rst), .sample_tick(sample_tick),
                   .acr_valid(acr_valid), .acr_cts(acr_cts), .acr_n(acr_n));
aud_music    u_mus(.clk(video_clk), .rst(rst), .sample_tick(sample_tick), .restart(music_restart),
                   .volume(volume), .mute(~sw_snd),
                   .pcm_valid(pcm_valid), .pcm_l(pcm_l), .pcm_r(pcm_r),
                   .line(lyr_line), .chr_s(lyr_chr), .wipe(lyr_wipe),
                   .img_sw(mv_sw), .img(mv_img), .style(mv_style),
                   .mel_env(mel_env), .note_on(av_note));

// =========================== HDMI（厂商 IP） ===========================
reg  [16:0] edid_dly;
wire        edid_trig = (edid_dly == 17'd100000);
always @(posedge video_clk or posedge rst)
    if (rst)                        edid_dly <= 17'd0;
    else if (edid_dly != 17'h1FFFF) edid_dly <= edid_dly + 17'd1;

wire [9:0] tmds_ch0, tmds_ch1, tmds_ch2, tmds_clk;
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"), .HTOTAL(800), .HSA(96), .HFP(16), .HBP(48), .HACTIVE(640),
    .VTOTAL(525), .VSA(2), .VFP(10), .VBP(33), .VACTIVE(480),
    .VIDEO_VIC(1), .VIDEO_TPG("Disable"), .VIDEO_FORMAT("RGB"),
    .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(250)
) u_hdmi(
    .I_pixel_clk(video_clk), .I_rst(rst),
    .I_edid_read_trig(edid_trig), .O_edid_read_valid(), .O_edid_read_data(),
    .I_axis_s_user(axis_user), .I_axis_s_valid(axis_valid), .I_axis_s_last(axis_last), .I_axis_s_data(axis_data),
    .O_axis_s_ready(),
    .I_audio_valid(pcm_valid), .I_audio_left_data(pcm_l), .I_audio_right_data(pcm_r),
    .I_acr_valid(acr_valid), .I_acr_cts(acr_cts), .I_acr_n(acr_n),
    .O_video_locked(), .O_ddc_scl(HDMI_DDC_SCL), .IO_ddc_sda(HDMI_DDC_SDA),
    .O_ch0_tmds_data(tmds_ch0), .O_ch1_tmds_data(tmds_ch1), .O_ch2_tmds_data(tmds_ch2), .O_clk_tmds_data(tmds_clk)
);
hdmi_phy_wrapper #(.DEVICE("EG")) u_phy(
    .I_pixel_clk(video_clk), .I_serial_clk(hdmi_5x_clk), .I_rst(rst),
    .I_tmds_channel_0(tmds_ch0), .I_tmds_channel_1(tmds_ch1), .I_tmds_channel_2(tmds_ch2), .I_tmds_channel_clk(tmds_clk),
    .O_tmds_ch0_p(HDMI_D0_P), .O_tmds_ch1_p(HDMI_D1_P), .O_tmds_ch2_p(HDMI_D2_P), .O_tmds_clk_p(HDMI_CLK_P)
);

// =========================== 数码管 ===========================
reg [7:0] dbg_ref_s1, dbg_ref_s2;         // 慢变化的调试值，两级同步即可
always @(posedge video_clk) begin dbg_ref_s1 <= dbg_ref; dbg_ref_s2 <= dbg_ref_s1; end
seg_disp u_seg(
    .clk(video_clk), .rst(rst),
    .d0({1'b0, period_sec}),
    .d1(mode == 2'd2 ? 5'd18 : mode == 2'd1 ? 5'd10 : 5'd17),
    .d2(loaded ? {3'd0, cur} + 5'd1 : 5'd17),
    .d3({2'd0, img_count}),
    .d4(loaded ? {1'b0, dbg_ref_s2[7:4]} : {1'b0, sd_dbg}),   // 装载完成后：SDRAM 刷新次数/0.65ms（十六进制）
    .d5(loaded ? {1'b0, dbg_ref_s2[3:0]} : {1'b0, ld_dbg}),
    .seg_sel(seg_sel), .seg_data(seg_data)
);

endmodule
